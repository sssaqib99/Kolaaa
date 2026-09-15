extends Node3D
## HYPERDRIFT game director.
##
## Modes
##   CLASSIC  hazards + orbs + sky structures, 3 shields, death on 0.
##   RHYTHM   no hazards. Beat PADS are laid on the beat grid straight from the
##            live music structure; fly through them on time to score. No death:
##            the run is about accuracy and streak.
##
## Music -> game
##   * travel speed follows the music (intensity + tempo ratio) - if the song
##     slows down or breaks down, so does the ship.
##   * a detected DROP triggers the drop sequence: white-out, hitstop, camera
##     kick, auto-boost for the drop's length, gobo strobe, floor shockwave.
##   * every bar the world pulses; sky structures cut the camera on the bar.

const V := preload("res://scripts/visuals.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const Biomes := preload("res://scripts/biomes.gd")

enum State { MENU, PLAY, PAUSE, DEAD }
enum Mode { CLASSIC, RHYTHM }

const SPEED_BASE := 26.0
const SPEED_MAX := 55.0
const COMBO_TIME := 3.6
const CHECKPOINT := 500.0

var state: int = State.MENU
var mode: int = Mode.CLASSIC
var speed := SPEED_BASE
var distance := 0.0
var score := 0.0
var combo := 0
var run_best_combo := 0
var combo_timer := 0.0
var multiplier := 1
var shields := 3
var energy := 100.0
var boosting := false
var boost_visual := 0.0
var invuln_t := 0.0
var overdrive_t := 0.0
var magnet_t := 0.0
var orbs := 0
var grazes := 0
var run_time := 0.0
var new_record := false
var orb_color := V.CYAN

# ---- progression / beat
var xp_run := 0
var beat_hits := 0
var beat_streak := 0
var beat_pulse := 0.0
var on_bridge := false
var bridges_crossed := 0

# ---- rhythm mode
var notes_hit := 0
var notes_missed := 0
var perfects := 0
var accuracy := 1.0

# ---- music -> game
var music_speed_mult := 1.0
var drop_boost_t := 0.0
var drop_flash := 0.0

# ---- ADRENALINE (classic mode only)
## Charged by XP earned during the run. When full, press E / Y / LB to trigger:
## shield + boost for a level/XP-scaled duration, and every obstacle in the way is
## SMASHED with a pop, debris, shock ring and a drum hit. Smashes score and
## refund a little charge so a good run can chain them.
const ADREN_FULL := 260.0
const ADREN_BASE_DURATION := 6.5
const ADREN_MAX_DURATION := 15.0
var adrenaline := 0.0         # 0..ADREN_FULL
var adrenaline_t := 0.0       # seconds remaining while active
var smashes := 0
var _adren_flash := 0.0

var _hitstop := 0.0
var _slowmo := 0.0
var _flash := 0.0
var _flash_color := Color(1.0, 0.12, 0.3)
var _speed_penalty := 0.0
var _dead_time := 0.0
var _next_checkpoint := CHECKPOINT
var _next_dist_xp := 100.0
var _beat_nudge := 1.0
var _post_mat: ShaderMaterial

@onready var player = $Player
@onready var track = $Track
@onready var rig = $CameraRig
@onready var hud = $HUD
@onready var post: ColorRect = $PostFX/Post
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $KeyLight
@onready var fill_light: DirectionalLight3D = $FillLight
@onready var helicopter: Node3D = $Helicopter

# ---- helicopter / ambient / loading
var _heli_timer := 0.0
var _heli_active := false
var _heli_interval := 24.0
var _ambient_sky := false         # music is ambient -> ship rises + peace mode
var _ambient_lift := 0.0
var _ambient_target := 0.0
var ambient_weight := 0.0         # 0..1 continuous, drives the camera blend
var _nocturne_mix := 0.0          # crimson dusk -> violet midnight atmosphere
var _sky_mat: ShaderMaterial
var _loading := false             # loading screen is up
var _loading_label := ""
var _post_run := false            # last run had device music with beat lock
var _rng_seeded := false

## Helicopter timer driver (called by _process). A patrol helicopter crosses the
## skyline every 20-30 s with its searchlight sweeping the highway below.
func _update_heli(delta: float) -> void:
	if not Persist.helicopters:
		if _heli_active:
			helicopter.despawn()
			_heli_active = false
		return
	_heli_timer += delta
	if _heli_timer > _heli_interval and not _heli_active:
		helicopter.spawn(player.global_position.z, int(_heli_timer))
		_heli_timer = 0.0
		_heli_interval = randf_range(20.0, 30.0)
		_heli_active = true
	if _heli_active and helicopter.visible_t > helicopter.lifetime:
		helicopter.despawn()
		_heli_active = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Seed the random number generator once per process so timing-driven
	# events (helicopter intervals, jitter, etc.) are reproducible.
	if not _rng_seeded:
		seed(1337)
		_rng_seeded = true
	_post_mat = post.material as ShaderMaterial
	player.game = self
	track.game = self
	track.player = player
	rig.target = player
	rig.game = self
	hud.game = self
	mode = Persist.mode
	Sound.beat.connect(_on_beat)
	Sound.bar.connect(_on_bar)
	Sound.drop.connect(_on_drop)
	Sound.breakdown_started.connect(_on_breakdown_started)
	Sound.breakdown_ended.connect(_on_breakdown_ended)
	Sound.ambient_started.connect(_on_ambient_started)
	Sound.ambient_ended.connect(_on_ambient_ended)
	apply_effect_settings()
	apply_biome(Persist.biome)
	to_menu()


# -------------------------------------------------------------------- biomes

func apply_biome(id: int) -> void:
	Persist.biome = id
	var d := Biomes.visual(id)
	var env := world_env.environment

	var s: Dictionary = d["sky"]
	var sky_mat := env.sky.sky_material as ShaderMaterial
	_sky_mat = sky_mat
	for key in ["zenith_color", "horizon_color", "ground_color", "sun_color", "sun_core", "star_density", "intensity", "aurora", "aurora_a", "aurora_b"]:
		var src: String = key
		match key:
			"zenith_color": src = "zenith"
			"horizon_color": src = "horizon"
			"ground_color": src = "ground"
			"sun_color": src = "sun"
			"star_density": src = "stars"
		sky_mat.set_shader_parameter(key, s[src])
	# Noir-specific atmosphere uniforms safely default to disabled for the
	# existing three maps.
	sky_mat.set_shader_parameter("night_mix", 0.0)
	sky_mat.set_shader_parameter("night_zenith", s.get("night_zenith", s["zenith"]))
	sky_mat.set_shader_parameter("night_horizon", s.get("night_horizon", s["horizon"]))
	sky_mat.set_shader_parameter("moon", float(s.get("moon", 0.0)))
	sky_mat.set_shader_parameter("moon_color", s.get("moon_color", Color(1, 1, 1)))
	sky_mat.set_shader_parameter("moon_size", float(s.get("moon_size", 0.1)))
	_nocturne_mix = 0.0

	var f: Dictionary = d["fog"]
	env.fog_light_color = f["color"]
	env.fog_density = f["density"]
	env.volumetric_fog_density = f["vol"]
	env.volumetric_fog_albedo = f["vol_albedo"]
	env.volumetric_fog_emission = f["vol_emission"]

	var l: Dictionary = d["light"]
	env.ambient_light_color = l["ambient"]
	env.ambient_light_energy = l["ambient_e"]
	key_light.light_color = l["key"]
	key_light.light_energy = l["key_e"]
	fill_light.light_color = l["fill"]
	fill_light.light_energy = l["fill_e"]

	orb_color = d["orb"]
	track.apply_biome(id)
	if track.gobo_rig != null:
		var b: Dictionary = d["bridge"]
		var gobo_base := Color(0.92, 0.70, 0.38) if id == Biomes.NOCTURNE else Color(0.72, 0.85, 1.0)
		track.gobo_rig.set_colors(gobo_base, b["swirl_b"])
	Sound.play_biome_music(id)
	hud.refresh_biome()
	Persist.save_profile()


func set_biome(id: int) -> void:
	id = clampi(id, 0, Biomes.COUNT - 1)
	if id == Persist.biome:
		return
	apply_biome(id)
	Sound.play("power", 1.1, -5.0)
	hud.pop_text(Biomes.name_of(id), V.CYAN)


func cycle_biome(dir: int) -> void:
	set_biome(wrapi(Persist.biome + dir, 0, Biomes.COUNT))


func set_mode(m: int) -> void:
	mode = m
	Persist.mode = m
	Persist.save_profile()
	hud.refresh_mode()


# ------------------------------------------------------------------- settings

## Push every SETTINGS > EFFECTS value into the live scene.
func apply_effect_settings() -> void:
	var env := world_env.environment
	if env != null:
		var g: float = Persist.glow_amount
		env.glow_enabled = g > 0.02
		env.glow_intensity = 0.35 + 0.95 * g
		env.glow_strength = 0.85 + 0.25 * g
		env.glow_bloom = 0.1 + 0.28 * g
		env.glow_hdr_threshold = lerpf(1.35, 0.7, clampf(g / 2.0, 0.0, 1.0))
		var q: int = Persist.quality
		env.volumetric_fog_enabled = q >= 2
		env.ssao_enabled = q >= 1
		var vp := get_viewport()
		vp.msaa_3d = Viewport.MSAA_4X if q >= 2 else (Viewport.MSAA_2X if q == 1 else Viewport.MSAA_DISABLED)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q >= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	if _post_mat != null:
		_post_mat.set_shader_parameter("scanline", 0.035 if Persist.scanlines else 0.0)
	if track != null:
		if track.gobo_rig != null:
			track.gobo_rig.set_enabled(Persist.gobos)
			track.gobo_rig.brightness = Persist.gobo_brightness
		track.set_dust(Persist.dust)
	if hud != null and not on_bridge:
		hud.set_letterbox(false)


# --------------------------------------------------------------------- helpers

func base_speed() -> float:
	var m := 1.0
	if boosting:
		m += 0.38
	if overdrive_t > 0.0:
		m += 0.22
	return speed * m * (1.0 - _speed_penalty) * music_speed_mult


## Actual travel speed, including the subtle beat-lock rubber band.
func travel_speed() -> float:
	return base_speed() * _beat_nudge


func speed01() -> float:
	return clampf((travel_speed() - SPEED_BASE) / (SPEED_MAX * 1.6 - SPEED_BASE), 0.0, 1.0)


func difficulty() -> float:
	return clampf((speed - SPEED_BASE) / (SPEED_MAX - SPEED_BASE), 0.0, 1.0)


func add_trauma(v: float) -> void:
	rig.add_trauma(v)


func max_shields() -> int:
	return 4 if Persist.has_perk(8) else 3


func beat_sync_active() -> bool:
	return Persist.beat_sync and Sound.beat_locked


func is_rhythm() -> bool:
	return mode == Mode.RHYTHM


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	var ud: float = delta / maxf(Engine.time_scale, 0.0001)
	_tick_time_scale(ud)
	_update_music_speed(ud)
	_update_nocturne_atmosphere(ud)
	_update_heli(delta)

	match state:
		State.MENU:
			_menu_tick(delta)
		State.PLAY:
			_play_tick(delta)
		State.DEAD:
			_dead_tick(delta, ud)

	_flash = maxf(0.0, _flash - ud * 3.4)
	drop_flash = maxf(0.0, drop_flash - ud * 1.6)
	beat_pulse = maxf(0.0, beat_pulse - ud * 4.5)
	boost_visual = lerpf(boost_visual, 1.0 if boosting else 0.0, clampf(ud * 5.0, 0.0, 1.0))
	# Ambient sky-lift: a gentle glide UP (0.85/s) and an even gentler glide
	# DOWN (0.45/s) so the ship settles back onto the road like a landing, not
	# a drop. Also exposes a 0..1 weight the camera blends with.
	var rate: float = 0.85 if _ambient_target > _ambient_lift else 0.45
	_ambient_lift = lerpf(_ambient_lift, _ambient_target, clampf(ud * rate, 0.0, 1.0))
	ambient_weight = clampf(_ambient_lift / 22.0, 0.0, 1.0)
	_update_bridge_state()
	_update_post()
	Sound.set_engine(speed01(), boost_visual, state != State.MENU and player.alive)
	hud.tick(delta)


func _tick_time_scale(ud: float) -> void:
	var target := 1.0
	if _hitstop > 0.0:
		_hitstop -= ud
		target = 0.06
	elif _slowmo > 0.0:
		_slowmo -= ud
		target = 0.45
	elif state == State.DEAD:
		target = clampf(0.35 + _dead_time * 0.9, 0.35, 1.0)
	if target < Engine.time_scale:
		Engine.time_scale = target
	else:
		Engine.time_scale = lerpf(Engine.time_scale, target, clampf(ud * 5.0, 0.0, 1.0))


## Speed follows the music: quiet / slowing music slows the ship, loud music
## and a faster tempo push it. Smoothed so it feels like a swell, not jitter.
func _update_music_speed(ud: float) -> void:
	var target := 1.0
	if Persist.speed_follows_music and Sound.beat_source != "NONE":
		var inten: float = Sound.intensity
		var tempo: float = clampf(Sound.tempo_ratio, 0.72, 1.22)
		target = lerpf(0.68, 1.16, clampf(inten, 0.0, 1.0)) * tempo
		if Sound.breakdown:
			target *= 0.82
		if Sound.drop_active:
			target *= 1.08
	music_speed_mult = lerpf(music_speed_mult, target, clampf(ud * 0.9, 0.0, 1.0))


## Nocturne Boulevard begins in a crimson jazz-club dusk and slowly grades into
## a dark blue-violet midnight when the arrangement thins out. This uses the
## live energy analysis rather than a fixed timer, so a quiet piano passage
## pushes night further in while a brass/drum swell warms the red back up.
func _update_nocturne_atmosphere(ud: float) -> void:
	if Persist.biome != Biomes.NOCTURNE:
		_nocturne_mix = lerpf(_nocturne_mix, 0.0, clampf(ud * 0.8, 0.0, 1.0))
		return
	var target := clampf(0.16 + (1.0 - Sound.intensity) * 0.58 + (0.18 if Sound.breakdown else 0.0), 0.10, 0.94)
	# Very slow grade: it should feel like the sky changes with the song, not
	# like a color effect popping between beats.
	_nocturne_mix = lerpf(_nocturne_mix, target, clampf(ud * 0.10, 0.0, 1.0))
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("night_mix", _nocturne_mix)
	track.set_nocturne_atmosphere(_nocturne_mix)
	var env := world_env.environment
	if env != null:
		env.fog_light_color = Color(0.42, 0.025, 0.075).lerp(Color(0.055, 0.028, 0.20), _nocturne_mix)
		env.fog_density = lerpf(0.012, 0.018, _nocturne_mix)
		env.ambient_light_color = Color(0.22, 0.07, 0.24).lerp(Color(0.08, 0.07, 0.30), _nocturne_mix)
		key_light.light_color = Color(0.92, 0.35, 0.30).lerp(Color(0.36, 0.32, 0.78), _nocturne_mix)
		fill_light.light_color = Color(0.24, 0.18, 0.50).lerp(Color(0.20, 0.14, 0.52), _nocturne_mix)


func _menu_tick(delta: float) -> void:
	speed = 30.0
	distance += travel_speed() * delta
	_beat_nudge = 1.0


func _play_tick(delta: float) -> void:
	run_time += delta
	speed = clampf(SPEED_BASE + distance / 46.0, SPEED_BASE, SPEED_MAX)
	_speed_penalty = maxf(0.0, _speed_penalty - delta * 0.55)
	_update_beat_nudge(delta)

	var eff := travel_speed()
	distance += eff * delta
	var score_mult := 1.1 if Persist.has_perk(20) else 1.0
	if not is_rhythm():
		score += eff * delta * 0.55 * float(multiplier) * (1.4 if boosting else 1.0) * score_mult

	# Boost: ONLY automatic, triggered by a music DROP. Manual boost has been
	# removed from the input map entirely; pressing Shift does nothing.
	drop_boost_t = maxf(0.0, drop_boost_t - delta)
	_tick_adrenaline(delta)
	_adrenaline_sweep()
	var want_boost: bool = overdrive_t > 0.0 or drop_boost_t > 0.0
	if want_boost and not boosting:
		Sound.play("boost", randf_range(0.95, 1.1), -7.0)
	boosting = want_boost
	if not boosting:
		energy = minf(100.0, energy + 3.0 * (1.25 if Persist.has_perk(3) else 1.0) * delta)

	invuln_t = maxf(0.0, invuln_t - delta)
	overdrive_t = maxf(0.0, overdrive_t - delta)
	magnet_t = maxf(0.0, magnet_t - delta)
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
			multiplier = 1

	if distance >= _next_checkpoint:
		_next_checkpoint += CHECKPOINT
		var bonus := 250 * multiplier
		score += float(bonus)
		energy = minf(100.0, energy + 25.0)
		hud.pop_text("%dm CHECKPOINT  +%d" % [int(distance / CHECKPOINT) * int(CHECKPOINT), bonus], V.LIME)
		Sound.play("power", 1.15, -5.0)
		add_xp(25)
	if distance >= _next_dist_xp:
		_next_dist_xp += 100.0
		add_xp(5)

	if is_rhythm():
		for n in track.collect_missed_notes(player.global_position.z):
			_note_missed()
	else:
		_check_gates()


func _dead_tick(delta: float, ud: float) -> void:
	_dead_time += ud
	distance += travel_speed() * delta * 0.2
	speed = maxf(0.0, speed - delta * 26.0)


# ---------------------------------------------------------------------- beat

func _on_beat(_index: int) -> void:
	if not Sound.beat_locked:
		return
	beat_pulse = 1.0
	track.set_building_pulse(1.0)
	if track.bridge != null:
		track.bridge.pulse = 1.0
	hud.on_beat()
	if state == State.PLAY and beat_sync_active() and not is_rhythm():
		Sound.play("tick", 1.0, -26.0)


func _on_bar(index: int) -> void:
	if not Sound.beat_locked or state == State.MENU:
		return
	# Every 8 bars: a phrase flash in the biome colour.
	if index % 8 == 0 and Persist.beat_flash:
		_flash_color = orb_color
		_flash = maxf(_flash, 0.25)


func _on_drop(strength: float) -> void:
	if state == State.MENU:
		return
	_flash_color = Color(1, 1, 1)
	_flash = 0.9
	drop_flash = 1.0
	_hitstop = 0.16
	rig.add_trauma(0.7 + 0.4 * strength)
	track.flash_floor()
	if track.bridge != null:
		track.bridge.pulse = 1.5
	Input.start_joy_vibration(0, 0.5, 0.9, 0.5)
	Sound.play("record", 0.85, -6.0)
	Sound.play("boost", 0.8, -4.0)
	if state == State.PLAY:
		if Persist.drop_boost:
			drop_boost_t = Sound.drop_time_left
			invuln_t = maxf(invuln_t, 1.2)
		score += float(150 * multiplier)
		add_xp(20)
		hud.pop_text("THE DROP", V.WHITE)
		hud.pop_text_delayed("AUTO BOOST  %d s" % int(round(Sound.drop_time_left)), V.ORANGE, 0.6)


func _on_breakdown_started() -> void:
	if state == State.PLAY:
		hud.pop_small("BREAKDOWN  —  ship easing off")


func _on_breakdown_ended() -> void:
	pass


## AMBIENT: the music is a sustained quiet passage -> the ship floats
## upward into the sky and the camera eases into a peaceful wide shot.
## The level keeps running normally underneath.
func _on_ambient_started() -> void:
	if state == State.MENU:
		return
	_ambient_sky = true
	_ambient_target = 22.0
	hud.pop_text("AMBIENT  —  DRIFTING INTO THE SKY", V.LIME)


func _on_ambient_ended() -> void:
	_ambient_sky = false
	_ambient_target = 0.0
	if state == State.PLAY:
		hud.pop_text("BACK TO THE GROUND", V.CYAN)


func _check_gates() -> void:
	var pz: float = player.global_position.z
	var i: int = track.gates.size() - 1
	while i >= 0:
		var g: Dictionary = track.gates[i]
		if pz <= float(g["z"]):
			track.gates.remove_at(i)
			if beat_sync_active():
				var off: float = absf(Sound.beat_offset(Sound.now()))
				if off < 0.055:
					_beat_hit("PERFECT", 10, 2, 90)
				elif off < 0.125:
					_beat_hit("ON BEAT", 5, 1, 45)
				else:
					beat_streak = 0
		i -= 1


func _beat_hit(label: String, xp: int, chain: int, pts: int) -> void:
	beat_hits += 1
	beat_streak += 1
	combo += chain
	run_best_combo = maxi(run_best_combo, combo)
	combo_timer = _combo_time()
	multiplier = clampi(1 + combo / 5, 1, 10)
	score += float(pts * multiplier)
	add_xp(xp)
	hud.pop_small("%s  +%d XP" % [label, xp])
	Sound.play("combo", 1.3 if label == "PERFECT" else 1.05, -10.0)
	if beat_streak > 0 and beat_streak % 8 == 0:
		energy = minf(100.0, energy + 20.0)
		hud.pop_text("BEAT STREAK x%d" % beat_streak, V.ORANGE)
		Sound.play("power", 1.3, -6.0)


## Rubber-bands travel speed by up to +-6% so the next gate lands on a beat.
func _update_beat_nudge(delta: float) -> void:
	var target := 1.0
	if beat_sync_active() and not track.gates.is_empty() and not is_rhythm():
		var pz: float = player.global_position.z
		var best_d := 1e9
		for g in track.gates:
			var d: float = pz - float(g["z"])
			if d > 2.0 and d < best_d:
				best_d = d
		if best_d < 70.0:
			var sp := maxf(base_speed(), 5.0)
			var dt_arr := best_d / sp
			var now: float = Sound.now()
			var off: float = Sound.beat_offset(now + dt_arr)
			var dt_target := dt_arr - off
			if dt_target > 0.15:
				target = clampf(dt_arr / dt_target, 0.94, 1.06)
	_beat_nudge = lerpf(_beat_nudge, target, clampf(delta * 4.0, 0.0, 1.0))


# --------------------------------------------------------------- rhythm mode

func _note_hit(n) -> void:
	var off: float = absf(Sound.beat_offset(Sound.now())) if Sound.beat_locked else 0.06
	var label := "GOOD"
	var pts := 60
	var xp := 3
	if off < 0.06:
		label = "PERFECT"
		pts = 120
		xp = 6
		perfects += 1
	elif off > 0.16:
		label = "LATE" if Sound.beat_offset(Sound.now()) > 0.0 else "EARLY"
		pts = 30
		xp = 1
	if n.note_variant == 2:
		pts *= 2
		xp += 2
	notes_hit += 1
	beat_hits += 1
	beat_streak += 1
	combo += 1
	run_best_combo = maxi(run_best_combo, combo)
	combo_timer = _combo_time() + 1.0
	multiplier = clampi(1 + combo / 8, 1, 10)
	score += float(pts * multiplier)
	energy = minf(100.0, energy + 3.0)
	add_xp(xp)
	accuracy = float(notes_hit) / float(maxi(notes_hit + notes_missed, 1))
	Sound.play("orb", clampf(0.9 + float(beat_streak) * 0.02, 0.9, 2.0), -9.0)
	if label == "PERFECT":
		Sound.play("combo", 1.4, -12.0)
	hud.pop_small("%s  +%d" % [label, pts * multiplier])
	rig.add_trauma(0.03)
	if beat_streak % 16 == 0:
		hud.pop_text("STREAK %d" % beat_streak, V.ORANGE)
		Sound.play("power", 1.3, -6.0)
		rig.add_trauma(0.2)


func _note_missed() -> void:
	notes_missed += 1
	if beat_streak >= 8:
		hud.pop_small("MISS  —  streak lost")
		Sound.play("graze", 0.6, -10.0)
	beat_streak = 0
	combo = 0
	multiplier = 1
	accuracy = float(notes_hit) / float(maxi(notes_hit + notes_missed, 1))


# ------------------------------------------------------------------ structures

func on_structure_enter() -> void:
	if state != State.PLAY:
		return
	var nm: String = track.bridge.kind_name()
	hud.pop_text("%s  —  XP RUN" % nm, V.YELLOW)
	Sound.play("power", 0.8, -6.0)
	rig.add_trauma(0.12)


func _update_bridge_state() -> void:
	var inside: bool = player.on_rail
	if inside == on_bridge:
		return
	on_bridge = inside
	hud.set_letterbox(inside and Persist.letterbox)
	if not inside and state == State.PLAY:
		bridges_crossed += 1
		score += float(400 * multiplier)
		add_xp(150)
		hud.pop_text("STRUCTURE CLEARED  +150 XP", V.YELLOW)
		Sound.play("record", 1.15, -8.0)


# ---------------------------------------------------------------- progression

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	if state == State.PLAY:
		xp_run += amount
		_charge_adrenaline(amount)
	var lvl: int = Persist.add_xp(amount)
	if lvl > 0:
		_level_up(lvl)


func _level_up(lvl: int) -> void:
	Persist.save_profile()
	hud.pop_text("PILOT LEVEL %d" % lvl, V.LIME)
	var unlock := Persist.unlock_text(lvl)
	if not unlock.is_empty():
		hud.pop_text_delayed("UNLOCKED:  %s" % unlock, V.CYAN, 1.1)
	Sound.play("levelup", 1.0, -4.0)
	rig.add_trauma(0.3)
	_flash_color = V.LIME
	_flash = 0.3
	if state == State.PLAY:
		shields = mini(max_shields(), shields + 1)
		energy = 100.0
		score += 500.0
	hud.refresh()


func _combo_time() -> float:
	return COMBO_TIME + (0.6 if Persist.has_perk(5) else 0.0)


# ------------------------------------------------------------------- gameplay

func collect(a) -> void:
	var kind: int = a.kind
	var at: Vector3 = a.global_position
	if kind == PickupScript.Kind.NOTE:
		track.forget_note(a)
		a.recycle()
		track.pop_burst(at, orb_color)
		if state == State.PLAY:
			_note_hit(a)
		return
	a.recycle()
	var burst_color := orb_color
	match kind:
		PickupScript.Kind.SHIELD: burst_color = V.LIME
		PickupScript.Kind.MAGNET: burst_color = V.VIOLET
		PickupScript.Kind.OVERDRIVE: burst_color = V.ORANGE
		PickupScript.Kind.XP, PickupScript.Kind.RING: burst_color = Color(1.0, 0.85, 0.3)
	track.pop_burst(at, burst_color)
	var in_run := state == State.PLAY
	match kind:
		PickupScript.Kind.ORB:
			orbs += 1
			combo += 1
			run_best_combo = maxi(run_best_combo, combo)
			combo_timer = _combo_time()
			multiplier = clampi(1 + combo / 5, 1, 10)
			energy = minf(100.0, energy + 4.5)
			score += 22.0 * float(multiplier)
			Sound.play("orb", clampf(0.85 + float(combo) * 0.035, 0.85, 2.1), -9.0)
			rig.add_trauma(0.018)
			if in_run:
				add_xp(1)
			if combo > 0 and combo % 10 == 0:
				Sound.play("combo", 1.0, -6.0)
				hud.pop_text("COMBO x%d" % multiplier, V.CYAN)
		PickupScript.Kind.XP:
			combo += 1
			run_best_combo = maxi(run_best_combo, combo)
			combo_timer = _combo_time()
			multiplier = clampi(1 + combo / 5, 1, 10)
			score += 30.0 * float(multiplier)
			Sound.play("xp", clampf(0.9 + float(combo) * 0.03, 0.9, 1.9), -8.0)
			rig.add_trauma(0.02)
			if in_run:
				add_xp(5)
		PickupScript.Kind.RING:
			score += 200.0 * float(multiplier)
			Sound.play("shield", 1.2, -4.0)
			rig.add_trauma(0.25)
			_flash_color = Color(1.0, 0.9, 0.45)
			_flash = 0.2
			if in_run:
				add_xp(30)
				hud.pop_text("XP RING  +30", Color(1.0, 0.9, 0.45))
		PickupScript.Kind.SHIELD:
			shields = mini(max_shields(), shields + 1)
			invuln_t = maxf(invuln_t, 1.2)
			Sound.play("shield", 1.0, -4.0)
			hud.pop_text("SHIELD RESTORED", V.LIME)
			hud.flash_shields()
		PickupScript.Kind.MAGNET:
			magnet_t = 14.0 if Persist.has_perk(12) else 10.0
			Sound.play("power", 1.0, -4.0)
			hud.pop_text("ORB MAGNET", V.VIOLET)
		PickupScript.Kind.OVERDRIVE:
			overdrive_t = 9.0 if Persist.has_perk(16) else 7.0
			invuln_t = maxf(invuln_t, overdrive_t)
			energy = 100.0
			Sound.play("power", 0.85, -3.0)
			hud.pop_text("OVERDRIVE!", V.ORANGE)
			rig.add_trauma(0.35)
			_flash_color = V.ORANGE
			_flash = 0.45
	hud.refresh()


func graze(at: Vector3) -> void:
	if state != State.PLAY or invuln_t > 0.0 or is_rhythm():
		return
	grazes += 1
	combo += 1
	run_best_combo = maxi(run_best_combo, combo)
	combo_timer = _combo_time()
	multiplier = clampi(1 + combo / 5, 1, 10)
	energy = minf(100.0, energy + 2.5)
	score += 30.0 * float(multiplier)
	Sound.play("graze", randf_range(1.4, 1.7), -12.0)
	hud.pop_small("GRAZE +%d" % (30 * multiplier))
	rig.add_trauma(0.05)
	add_xp(2)


func hit(a) -> void:
	if state != State.PLAY or is_rhythm():
		return
	# ADRENALINE: the ship is a battering ram — smash the hazard instead of
	# taking the hit. Satisfying pop, debris, shock ring, drum hit, score.
	if adrenaline_t > 0.0:
		_smash_obstacle(a)
		return
	if invuln_t > 0.0:
		return
	shields -= 1
	combo = 0
	multiplier = 1
	beat_streak = 0
	_speed_penalty = 0.38
	_hitstop = 0.1
	_flash_color = Color(1.0, 0.12, 0.3)
	_flash = 0.8
	track.flash_floor()
	player.pop_sparks(player.global_position + Vector3(0, 0, -1.2))
	rig.add_trauma(0.9)
	Input.start_joy_vibration(0, 0.65, 0.95, 0.35)
	hud.refresh()
	hud.flash_shields()
	if shields <= 0:
		_die()
	else:
		invuln_t = 1.9
		_slowmo = 0.22
		Sound.play("hit", randf_range(0.9, 1.1), -3.0)
		hud.pop_text("-1 SHIELD", V.MAGENTA)


# ---------------------------------------------------------------- adrenaline

func adrenaline_ready() -> bool:
	return not is_rhythm() and adrenaline_t <= 0.0 and adrenaline >= ADREN_FULL


func adrenaline_duration() -> float:
	# XP progression extends the power. Run XP also gives a small dynamic bonus,
	# so a high-performing run naturally earns a longer adrenaline window.
	var level_bonus: float = float(maxi(Persist.level() - 1, 0)) * 0.22
	var run_bonus: float = clampf(float(xp_run) / 180.0, 0.0, 4.5)
	return minf(ADREN_MAX_DURATION, ADREN_BASE_DURATION + level_bonus + run_bonus)


func adrenaline_ratio() -> float:
	return clampf(adrenaline / ADREN_FULL, 0.0, 1.0)


## Called from add_xp: every XP point earned in the run charges the meter.
func _charge_adrenaline(xp: int) -> void:
	if is_rhythm() or state != State.PLAY or adrenaline_t > 0.0:
		return
	var before := adrenaline
	adrenaline = minf(ADREN_FULL, adrenaline + float(xp) * 1.35)
	if before < ADREN_FULL and adrenaline >= ADREN_FULL:
		hud.pop_text("ADRENALINE READY  —  PRESS  E", V.ORANGE)
		Sound.play("clap", 1.0, -6.0)
		Sound.play("kick", 1.0, -4.0)
		rig.add_trauma(0.15)


func activate_adrenaline() -> void:
	if state != State.PLAY or is_rhythm():
		return
	# Pressing E again cancels an active adrenaline run cleanly.
	if adrenaline_t > 0.0:
		cancel_adrenaline()
		return
	if not adrenaline_ready():
		return
	adrenaline = 0.0
	adrenaline_t = adrenaline_duration()
	invuln_t = maxf(invuln_t, adrenaline_t + 0.4)
	drop_boost_t = maxf(drop_boost_t, adrenaline_t)   # free boost for the duration
	energy = 100.0
	_adren_flash = 1.0
	_flash_color = V.ORANGE
	_flash = 0.7
	_hitstop = 0.08
	rig.add_trauma(0.55)
	track.flash_floor()
	Input.start_joy_vibration(0, 0.4, 0.9, 0.5)
	Sound.play("adren_on", 1.0, -3.0)
	hud.pop_text("A D R E N A L I N E", V.ORANGE)
	hud.flash_shields()


func cancel_adrenaline() -> void:
	if adrenaline_t <= 0.0:
		return
	adrenaline_t = 0.0
	drop_boost_t = minf(drop_boost_t, 0.25)
	invuln_t = minf(invuln_t, 0.35)
	hud.pop_text("ADRENALINE CANCELLED", V.WHITE)
	Sound.play("rim", 0.8, -10.0)


func _tick_adrenaline(delta: float) -> void:
	if adrenaline_t <= 0.0:
		return
	adrenaline_t = maxf(0.0, adrenaline_t - delta)
	_adren_flash = maxf(0.0, _adren_flash - delta * 2.0)
	# Beat-locked crackle so the state reads through the music.
	if Sound.beat_locked and fposmod(Sound.beat_pos() * 2.0, 1.0) < 0.06 and randf() < 0.5:
		Sound.play("hat", 1.3, -18.0)
	if adrenaline_t <= 0.0:
		hud.pop_text("ADRENALINE OVER", V.WHITE)
		Sound.play("snare", 0.9, -8.0)
		invuln_t = maxf(invuln_t, 0.8)   # grace so you don't eat a hit on the exact frame it ends


func _adrenaline_sweep() -> void:
	if adrenaline_t <= 0.0 or state != State.PLAY or is_rhythm():
		return
	# Proactively smash hazards in the flight corridor instead of waiting for a
	# physics collision. This makes adrenaline feel invincible and decisive.
	for o in track._obstacles:
		if not o.live or o.smashing:
			continue
		var dz: float = player.global_position.z - o.global_position.z
		if dz <= 0.0 or dz > 25.0:
			continue
		var half_w: float = 1.5
		if o._box_mesh != null:
			half_w = maxf(1.1, o._box_mesh.size.x * 0.5)
		if absf(player.global_position.x - o.global_position.x) <= half_w + 1.6:
			_smash_obstacle(o)


## Smash a hazard we ran into while adrenaline is active.
func _smash_obstacle(a) -> void:
	if a == null or not a.live:
		return
	var at: Vector3 = a.global_position
	var col: Color = a.smash()
	smashes += 1
	# Scale the debris by how big the hazard was.
	var size_hint := 1.0
	if a._box_mesh != null:
		var s: Vector3 = a._box_mesh.size
		size_hint = clampf((s.x * s.y) / 12.0, 0.5, 2.0)
	track.pop_shatter(at, col, size_hint)
	track.pop_burst(at, col)
	# Score + chain + a little charge refund so smash chains feel rewarding.
	combo += 2
	run_best_combo = maxi(run_best_combo, combo)
	combo_timer = _combo_time()
	multiplier = clampi(1 + combo / 5, 1, 10)
	score += float(180 * multiplier)
	add_xp(4)
	# No time-slow here: adrenaline should feel fast and invincible. The kick,
	# debris, ring, flash, camera thump and rumble carry the impact instead.
	rig.add_trauma(0.32)
	_flash_color = col
	_flash = maxf(_flash, 0.28)
	Sound.play("smash", randf_range(0.92, 1.08), -4.0)
	Sound.play("kick", randf_range(0.95, 1.05), -6.0)
	Input.start_joy_vibration(0, 0.3, 0.7, 0.12)
	hud.pop_small("SMASH  +%d" % (180 * multiplier))


func _die() -> void:
	state = State.DEAD
	_dead_time = 0.0
	boosting = false
	player.explode()
	player.input_enabled = false
	rig.dead_cam = true
	rig.add_trauma(1.2)
	Sound.play("death", 1.0, -2.0)
	Sound.play("hit", 0.7, -2.0)
	Sound.set_music_db(-24.0)
	Input.start_joy_vibration(0, 0.9, 1.0, 0.7)
	_flash_color = Color(1.0, 0.12, 0.3)
	_flash = 1.0
	new_record = Persist.submit_run(int(score), int(distance), run_best_combo, orbs)
	if new_record:
		Sound.play("record", 1.0, -3.0)
	hud.show_game_over()


## RHYTHM mode has no death - the player ends the run from the pause screen.
func end_run() -> void:
	if state != State.PLAY and state != State.PAUSE:
		return
	get_tree().paused = false
	state = State.DEAD
	_dead_time = 1.0
	boosting = false
	player.input_enabled = false
	rig.dead_cam = true
	Sound.set_music_db(-16.0)
	new_record = Persist.submit_run(int(score), int(distance), run_best_combo, orbs)
	if new_record:
		Sound.play("record", 1.0, -3.0)
	hud.show_game_over()


# ---------------------------------------------------------------- state moves

func _reset_common() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	boosting = false
	boost_visual = 0.0
	invuln_t = 0.0
	overdrive_t = 0.0
	magnet_t = 0.0
	on_bridge = false
	drop_boost_t = 0.0
	_beat_nudge = 1.0
	music_speed_mult = 1.0
	track.rhythm_mode = false
	track.reset()
	player.revive()
	player.global_position = Vector3(0, 1.05, 0)
	rig.reset()
	hud.set_letterbox(false)


func to_menu() -> void:
	state = State.MENU
	_reset_common()
	speed = 30.0
	distance = 0.0
	track.demo_mode = true
	player.auto_pilot = true
	player.input_enabled = false
	Sound.set_music_db(-16.0)
	hud.show_menu()


func start_run() -> void:
	state = State.PLAY
	# Ensure the settings / music panel cannot leak into the run view.
	hud.hide_settings()
	_reset_common()
	speed = SPEED_BASE
	distance = 0.0
	score = 0.0
	combo = 0
	run_best_combo = 0
	combo_timer = 0.0
	multiplier = 1
	shields = max_shields()
	energy = 100.0
	orbs = 0
	grazes = 0
	run_time = 0.0
	new_record = false
	invuln_t = 1.0
	xp_run = 0
	beat_hits = 0
	beat_streak = 0
	bridges_crossed = 0
	notes_hit = 0
	notes_missed = 0
	perfects = 0
	accuracy = 1.0
	adrenaline = 0.0
	adrenaline_t = 0.0
	smashes = 0
	_adren_flash = 0.0
	_speed_penalty = 0.0
	_dead_time = 0.0
	_next_checkpoint = CHECKPOINT
	_next_dist_xp = 100.0
	track.demo_mode = false
	track.rhythm_mode = is_rhythm()
	player.auto_pilot = false
	player.input_enabled = false  # wait for layout to finish before input
	Sound.set_music_db(-9.0)
	# Loading screen + real-time beat-lock layout.
	var msg := "SYNTH  —  %s" % Biomes.theme_of(Persist.biome) if Sound.music_mode == 0 else "DEVICE  —  %d BPM" % int(roundf(Sound.beat_bpm))
	hud.show_loading(msg)
	_begin_layout()


## Spawns a coroutine that waits for the beat clock to lock (or times out) and
## then lifts the loading overlay. Used by start_run().
func _begin_layout() -> void:
	_loading = true
	# Helper: wait for the live beat clock to lock (or for the synth timeout).
	var wait_for_lock := func() -> void:
		var t := 0.0
		var timeout := 5.0 if Sound.music_mode == 1 else 0.1
		while t < timeout and not Sound.beat_locked:
			await get_tree().create_timer(0.1).timeout
			t += 0.1
	var stage := func(progress: float, message: String) -> void:
		hud.update_loading(progress, message)
		await get_tree().create_timer(0.12).timeout
	var finish := func() -> void:
		hud.update_loading(1.0, "READY  —  %d BPM" % int(roundf(Sound.beat_bpm)) if Sound.beat_locked else "READY")
		await get_tree().create_timer(0.18).timeout
		_loading = false
		hud.hide_loading()
		if state == State.PLAY:
			player.input_enabled = true
			Sound.play("power", 1.25, -4.0)
			if is_rhythm():
				hud.pop_text("RHYTHM MODE  —  FLY THROUGH THE PADS ON THE BEAT", V.CYAN)
		_flash_color = orb_color
		_flash = 0.3
	# Run the whole sequence as one async function.
	var run := func() -> void:
		await get_tree().create_timer(0.12).timeout
		await wait_for_lock.call()
		await stage.call(0.18, "LAYING OUT HIGHWAY…")
		await stage.call(0.42, "PLACING LANDMARKS…")
		await stage.call(0.66, "PLACING HAZARDS ON THE BEAT…")
		await stage.call(0.86, "PLOTTING SKY STRUCTURES…")
		await finish.call()
	run.call()


func is_loading() -> bool:
	return _loading


func pause_game(p: bool) -> void:
	if p and state == State.PLAY:
		state = State.PAUSE
		get_tree().paused = true
		hud.show_pause()
		Sound.set_music_db(-22.0)
	elif not p and state == State.PAUSE:
		state = State.PLAY
		get_tree().paused = false
		invuln_t = maxf(invuln_t, 0.6) # beat-driven hazards keep moving while paused
		hud.show_hud()
		Sound.set_music_db(-9.0)


# ------------------------------------------------------------------ post / fx

func _update_post() -> void:
	if _post_mat == null:
		return
	var sp := speed01()
	var ab: float = Persist.aberration_amount
	var wp: float = Persist.warp_amount
	var bf: float = (beat_pulse * 0.25) if Persist.beat_flash else 0.0
	_post_mat.set_shader_parameter("aberration", (boost_visual * 0.85 + _flash * 1.4 + sp * 0.3 + bf + drop_flash * 0.8) * ab)
	_post_mat.set_shader_parameter("warp", (boost_visual * 0.9 + sp * 0.22 + _flash * 0.3 + drop_flash * 0.5) * wp)
	_post_mat.set_shader_parameter("flash", _flash * 0.55 + _adren_flash * 0.12)
	_post_mat.set_shader_parameter("flash_color", _flash_color)
	_post_mat.set_shader_parameter("desaturate", 0.6 if state == State.DEAD else (0.0 if Sound.ambient else (0.25 if Sound.breakdown else 0.0)))
	_post_mat.set_shader_parameter("vignette_amount", 0.4 + boost_visual * 0.16 + (0.1 if Sound.breakdown else 0.0) + (-0.18 if Sound.ambient else 0.0))
	var env := world_env.environment
	if env != null and state == State.PLAY:
		var base_fog: float = Biomes.visual(Persist.biome)["fog"]["density"]
		env.fog_density = base_fog * (0.45 if Sound.ambient else 1.0)


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		var m: bool = Sound.toggle_mute()
		hud.pop_text("AUDIO OFF" if m else "AUDIO ON", V.WHITE)
	if event.is_action_pressed("fullscreen"):
		toggle_fullscreen()
	if event.is_action_pressed("next_track"):
		Sound.next_track()
	if event.is_action_pressed("prev_track"):
		Sound.prev_track()

	if hud.settings_open:
		if event.is_action_pressed("music_panel") or event.is_action_pressed("pause"):
			hud.hide_settings()
		return

	match state:
		State.MENU:
			if event.is_action_pressed("music_panel"):
				hud.show_settings(0)
			elif event.is_action_pressed("move_left"):
				cycle_biome(-1)
			elif event.is_action_pressed("move_right"):
				cycle_biome(1)
			elif event.is_action_pressed("start") or event.is_action_pressed("jump"):
				Sound.play("ui", 1.0, -6.0)
				start_run()
		State.PLAY:
			if event.is_action_pressed("adrenaline"):
				if adrenaline_t > 0.0:
					cancel_adrenaline()
				elif adrenaline_ready():
					activate_adrenaline()
				elif not is_rhythm():
					Sound.play("rim", 0.8, -14.0)
					hud.pop_small("ADRENALINE  %d%%" % int(adrenaline_ratio() * 100.0))
			elif event.is_action_pressed("music_panel"):
				pause_game(true)
				hud.show_settings(0)
			elif event.is_action_pressed("pause"):
				pause_game(true)
		State.PAUSE:
			if event.is_action_pressed("music_panel"):
				hud.show_settings(0)
			elif event.is_action_pressed("pause") or event.is_action_pressed("start"):
				pause_game(false)
			elif event.is_action_pressed("restart"):
				start_run()
		State.DEAD:
			if _dead_time > 0.7 and (event.is_action_pressed("restart") or event.is_action_pressed("start") or event.is_action_pressed("jump")):
				Sound.play("ui", 1.2, -6.0)
				Sound.set_music_db(-9.0)
				start_run()
			elif _dead_time > 0.7 and event.is_action_pressed("pause"):
				to_menu()


func toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func is_fullscreen() -> bool:
	return get_window().mode == Window.MODE_FULLSCREEN
