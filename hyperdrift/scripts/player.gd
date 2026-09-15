extends Area3D
## The hover-jet. Geometry is generated from primitives at runtime, so the whole
## project stays asset-free while still looking like a real ship.

const V := preload("res://scripts/visuals.gd")
const Ships := preload("res://scripts/ship_factory.gd")

const TRACK_HALF := 14.7   # widened ~9% (was 13.5)
const HOVER_Y := 1.05
const DUCK_Y := 0.44
const GRAVITY := 46.0
const JUMP_V := 15.0
const STRAFE_MAX := 21.0
const STRAFE_ACCEL := 140.0
const STRAFE_BRAKE := 30.0

var game = null
var alive := true
var input_enabled := false
var auto_pilot := true

var vx := 0.0
var vy := 0.0
var hover := HOVER_Y
var grounded := true
var ducking := false
var coyote := 0.0
var jump_buffer := 0.0
## Rail riding (sky structures). While on_rail the ship is positioned from a
## path frame: lateral = frame X, lift = frame Y, progress = distance along path.
var on_rail := false
var rail_s := 0.0
var lateral := 0.0      # lateral offset on the deck (also position.x when flat)
var lift := 0.0         # height above the deck
var rail_frame := Transform3D.IDENTITY
var _t := 0.0
var _tilt := 0.0
var _roll := 0.0
var _bob := 0.0

@onready var model: Node3D = $Model
@onready var shape: CollisionShape3D = $Shape
@onready var graze_zone: Area3D = $GrazeZone

var _box: BoxShape3D
var _graze_box: BoxShape3D
var _thruster: GPUParticles3D
var _sparks: GPUParticles3D
var _burst: GPUParticles3D
var _shield: MeshInstance3D
var _light: OmniLight3D
var _engine_glow: Array[MeshInstance3D] = []
var ship_id := 0
var _phantom_model: Node3D
var _music_flares: Array[MeshInstance3D] = []
var _flare_mats: Array[ShaderMaterial] = []


func _ready() -> void:
	collision_layer = 1
	collision_mask = 6
	monitoring = true
	monitorable = false
	_box = shape.shape as BoxShape3D
	var gs := graze_zone.get_child(0) as CollisionShape3D
	_graze_box = gs.shape as BoxShape3D
	area_entered.connect(_on_area_entered)
	graze_zone.area_entered.connect(_on_graze)
	_build_ship()
	position.y = hover


# ------------------------------------------------------------------- geometry

func _build_ship() -> void:
	# Vector interceptor hull — shared with the hangar preview (ship_factory).
	for g in Ships.build_vector(model):
		_engine_glow.append(g)

	_light = OmniLight3D.new()
	_light.light_color = V.CYAN
	_light.light_energy = 2.6
	_light.omni_range = 22.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.2, -3.0)
	add_child(_light)

	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(0.22, 0.22, 0.9)
	_thruster = V.make_particles(150, 0.55, trail_mesh, V.glow_material(V.CYAN, 4.0),
			7.0, 12.0, 0.5, 1.3, Color(0.6, 1.0, 1.0, 1.0), Color(1.0, 0.2, 0.7, 0.0))
	_thruster.position = Vector3(0, -0.02, 1.7)
	var tpm: ParticleProcessMaterial = _thruster.process_material
	tpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	tpm.emission_box_extents = Vector3(0.7, 0.12, 0.05)
	add_child(_thruster)

	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.12, 0.12, 0.4)
	_sparks = V.make_particles(60, 0.5, spark_mesh, V.glow_material(V.YELLOW, 5.0),
			12.0, 60.0, 0.4, 1.2, Color(1.0, 0.95, 0.5, 1.0), Color(1.0, 0.25, 0.1, 0.0),
			Vector3(0, -22, 0))
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	add_child(_sparks)

	var burst_mesh := BoxMesh.new()
	burst_mesh.size = Vector3(0.3, 0.3, 0.3)
	_burst = V.make_particles(200, 1.5, burst_mesh, V.glow_material(V.ORANGE, 6.0),
			26.0, 180.0, 0.6, 2.4, Color(1.0, 0.9, 0.6, 1.0), Color(1.0, 0.1, 0.4, 0.0),
			Vector3(0, -12, 0))
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	add_child(_burst)

	var sm := SphereMesh.new()
	sm.radius = 1.7
	sm.height = 3.4
	sm.radial_segments = 20
	sm.rings = 12
	_shield = MeshInstance3D.new()
	_shield.mesh = sm
	var shield_mat := V.orb_material(Color(0.4, 0.9, 1.0), 1.5)
	_shield.material_override = shield_mat
	_shield.scale = Vector3(1.0, 0.72, 1.25)
	_shield.visible = false
	add_child(_shield)
	_build_phantom_ship()
	_build_music_flares()
	set_ship(Persist.ship_id)


## PHANTOM: a lower, broader Art Deco interceptor. It has the same collision
## profile as the Vector ship, so ship choice is a visual identity choice and
## never creates an unfair handling advantage.
func _build_phantom_ship() -> void:
	_phantom_model = Node3D.new()
	_phantom_model.name = "Phantom"
	add_child(_phantom_model)
	for g in Ships.build_phantom(_phantom_model):
		_engine_glow.append(g)
	_phantom_model.visible = false


## Texture-free disco lens flares: one bass engine bloom, two melody wing
## flares, plus transient sparkle hits. They are attached to the ship so they
## remain readable through rolls and loops.
func _build_music_flares() -> void:
	var built: Dictionary = Ships.build_music_flares(self)
	for f in built["flares"]:
		_music_flares.append(f)
	for m in built["mats"]:
		_flare_mats.append(m)


func set_ship(id: int) -> void:
	ship_id = clampi(id, 0, 1)
	model.visible = ship_id == 0
	if _phantom_model != null:
		_phantom_model.visible = ship_id == 1


# ----------------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	_t += delta
	if game == null:
		return

	var axis := 0.0
	var want_jump := false
	var want_duck := false
	if auto_pilot:
		axis = sin(_t * 0.55) * 0.85 + sin(_t * 1.7) * 0.15
	elif input_enabled and alive:
		axis = Input.get_axis("move_left", "move_right")
		want_jump = Input.is_action_just_pressed("jump")
		want_duck = Input.is_action_pressed("duck")

	var trk = game.track
	var spd: float = game.travel_speed()

	# ---- forward: flat highway or along a structure's rail
	if on_rail:
		rail_s += spd * delta
		if rail_s >= trk.rail_length():
			on_rail = false
			var fe: Transform3D = trk.rail_frame(trk.rail_length())
			# Preserve the current hover height when handing back to the flat
			# boulevard. Setting Y to 0 here caused a visible one-frame drop.
			global_transform = Transform3D(Basis.IDENTITY, Vector3(fe.origin.x + lateral, lift, fe.origin.z))
			position.x = fe.origin.x + lateral
			lateral = position.x
	else:
		global_position.z -= spd * delta
		if trk.rail_entry(global_position.z) and alive:
			on_rail = true
			# Carry any tiny frame overshoot into the rail distance. The entry
			# tangent is horizontal, so this removes the perceptible hitch.
			rail_s = maxf(0.0, trk.bridge.start_z - global_position.z)
			lateral = position.x
			game.on_structure_enter()

	# ---- strafe (lateral on the deck)
	if absf(axis) > 0.05:
		vx = move_toward(vx, axis * STRAFE_MAX, STRAFE_ACCEL * delta)
	else:
		vx = move_toward(vx, 0.0, STRAFE_BRAKE * delta * 4.0)
	lateral += vx * delta
	var lim := TRACK_HALF - 0.8
	if absf(lateral) > lim:
		lateral = clampf(lateral, -lim, lim)
		if absf(vx) > 4.0 and alive:
			_sparks.global_position = global_position + global_transform.basis.x * signf(lateral) * 0.8
			_sparks.restart()
			game.add_trauma(0.16)
			Sound.play("graze", 0.7, -6.0)
		vx *= -0.25

	# ---- jump / duck / gravity (all along the deck's up axis)
	if want_jump:
		jump_buffer = 0.14
	jump_buffer = maxf(0.0, jump_buffer - delta)
	coyote = maxf(0.0, coyote - delta)

	ducking = want_duck and alive
	var target_hover: float = DUCK_Y if ducking else HOVER_Y

	if grounded:
		coyote = 0.12
		hover = lerpf(hover, target_hover, clampf(delta * 18.0, 0.0, 1.0))
		lift = hover
		if jump_buffer > 0.0:
			jump_buffer = 0.0
			grounded = false
			vy = JUMP_V
			Sound.play("jump", randf_range(0.95, 1.08), -5.0)
			game.add_trauma(0.05)
	else:
		vy -= GRAVITY * delta
		if ducking:
			vy -= GRAVITY * 1.35 * delta
		lift += vy * delta
		if lift <= target_hover:
			lift = target_hover
			hover = target_hover
			grounded = true
			if vy < -6.0:
				Sound.play("land", randf_range(0.9, 1.1), -9.0)
				game.add_trauma(0.07)
			vy = 0.0

	_bob = sin(_t * 4.4) * 0.05 * (1.0 if grounded else 0.2)
	var lift_v := lift + (_bob if grounded else 0.0)

	# ---- place the ship
	# The ambient sky-lift is ALWAYS applied (not gated on the ambient flag):
	# game._ambient_lift is a continuously eased value that glides up when an
	# ambient passage starts and glides back down when it ends. Gating it on the
	# boolean used to drop the ship 22 m in a single frame at the end.
	var sky: float = 0.0 if game == null else game._ambient_lift
	if on_rail:
		rail_frame = trk.rail_frame(rail_s)
		var origin := rail_frame.origin + rail_frame.basis.x * lateral + rail_frame.basis.y * (lift_v + sky)
		global_transform = Transform3D(rail_frame.basis, origin)
	else:
		rail_frame = Transform3D.IDENTITY
		global_transform = Transform3D(Basis.IDENTITY, Vector3(lateral, lift_v + sky, global_position.z))
		position.x = lateral

	# ---- collider follows the duck pose
	var h: float = 0.62 if ducking else 0.95
	_box.size = Vector3(1.15, h, 1.75)
	_graze_box.size = Vector3(3.3, h + 1.5, 2.9)

	_update_model(delta)


func _update_model(delta: float) -> void:
	var k := clampf(delta * 12.0, 0.0, 1.0)
	_roll = lerpf(_roll, -vx / STRAFE_MAX * 0.55, k)
	_tilt = lerpf(_tilt, clampf(-vy * 0.022, -0.35, 0.35) + (0.22 if ducking else 0.0), k)
	# Detailed music reactivity: bass gives the hull physical weight, sustained
	# drones create a tiny hover drift, melody lifts the nose and percussion
	# adds short bright attitude ticks. All values come from Sound's six-band
	# music director, so synth bass and acoustic tracks both feel alive.
	var bass_k: float = Sound.bass_pulse
	var drone_k: float = Sound.drone
	var melody_k: float = Sound.melody
	var perc_k: float = Sound.percussion * Sound.transient
	var beat_roll: float = sin(_t * 1.7) * drone_k * 0.025 + sin(_t * 6.0) * perc_k * 0.035
	var beat_pitch: float = -bass_k * 0.055 + melody_k * 0.022 + perc_k * 0.045
	model.rotation.z = _roll + beat_roll
	model.rotation.x = _tilt + beat_pitch
	model.rotation.y = lerpf(model.rotation.y, vx / STRAFE_MAX * 0.18 + melody_k * 0.025, k)
	if _phantom_model != null:
		_phantom_model.rotation = model.rotation
	var squash: float = 0.72 if ducking else 1.0
	var bass_scale := Vector3(1.0 + bass_k * 0.075, 1.0 - bass_k * 0.042, 1.0 + bass_k * 0.11)
	var target_scale := Vector3(1.0 + (1.0 - squash) * 0.35, squash, 1.0) * bass_scale
	model.scale = model.scale.lerp(target_scale, k)
	if _phantom_model != null:
		_phantom_model.scale = _phantom_model.scale.lerp(target_scale * (Vector3(1.08, 0.94, 1.06) if ship_id == 1 else Vector3.ONE), k)

	var boost: float = game.boost_visual
	var thrust: float = 0.38 + boost * 0.9 + bass_k * 0.32 + perc_k * 0.22
	_thruster.speed_scale = 0.85 + boost * 1.6 + bass_k * 0.55 + perc_k * 0.34
	_thruster.amount_ratio = clampf(thrust, 0.15, 1.0)
	for g in _engine_glow:
		g.scale = Vector3.ONE * (1.0 + boost * 0.8 + bass_k * 0.42 + perc_k * 0.25 + sin(_t * 22.0) * 0.035)
	_light.light_energy = 2.0 + boost * 3.0 + bass_k * 1.4 + melody_k * 0.7 + perc_k * 1.3
	_update_music_flares(bass_k, drone_k, melody_k, perc_k, boost)

	var inv: bool = game.invuln_t > 0.0
	var adren: bool = game.adrenaline_t > 0.0
	_shield.visible = inv or adren
	if inv or adren:
		var m: ShaderMaterial = _shield.material_override
		if adren:
			# ADRENALINE: a bigger, hotter orange shield that throbs on the beat
			# - the ship reads as a battering ram.
			var bp: float = fposmod(Sound.beat_pos(), 1.0) if Sound.beat_locked else fposmod(_t * 2.0, 1.0)
			var throb: float = 1.0 + 0.12 * exp(-bp * 6.0)
			_shield.scale = Vector3(1.25, 0.9, 1.5) * throb
			m.set_shader_parameter("orb_color", V.ORANGE.lerp(Color(1.0, 0.95, 0.6), 0.5 * exp(-bp * 6.0)))
			m.set_shader_parameter("energy", 2.6 + 1.6 * exp(-bp * 6.0))
			_light.light_color = V.ORANGE
			_light.light_energy = 5.0 + boost * 3.0
		else:
			_shield.scale = Vector3(1.0, 0.72, 1.25) * (1.0 + sin(_t * 14.0) * 0.05)
			m.set_shader_parameter("orb_color", V.LIME if game.overdrive_t > 0.0 else Color(0.4, 0.9, 1.0))
			m.set_shader_parameter("energy", 1.5)
			_light.light_color = V.CYAN


func _update_music_flares(bass_k: float, drone_k: float, melody_k: float, perc_k: float, boost: float) -> void:
	if _flare_mats.is_empty():
		return
	var dominant := Sound.dominant_layer
	var palette := V.CYAN
	match dominant:
		"BASS": palette = Color(1.0, 0.34, 0.18)
		"DRONE": palette = Color(0.48, 0.32, 1.0)
		"MELODY": palette = Color(0.28, 0.92, 1.0)
		"PERCUSSION": palette = Color(1.0, 0.82, 0.38)
		"SILENT": palette = Color(0.12, 0.16, 0.28)
	var values := [bass_k + boost * 0.65, melody_k, melody_k, perc_k, perc_k, drone_k * 0.7 + melody_k * 0.25]
	for i in _flare_mats.size():
		var f: ShaderMaterial = _flare_mats[i]
		var value: float = clampf(values[i], 0.0, 1.4)
		var c: Color = palette
		if i == 0:
			c = palette.lerp(V.CYAN, 0.35)
		elif i == 5:
			c = Color(0.80, 0.58, 1.0).lerp(palette, 0.35)
		f.set_shader_parameter("flare_color", c)
		f.set_shader_parameter("strength", value * (1.05 if i == 0 else 0.62))
		f.set_shader_parameter("pulse", clampf(bass_k + perc_k * 0.8 + boost * 0.55, 0.0, 1.5))
		if i < _music_flares.size():
			var flare := _music_flares[i]
			var s: float = 0.75 + value * (1.2 if i == 0 else 0.65)
			flare.scale = Vector3(s, s, 1.0)


# ------------------------------------------------------------------ callbacks

func _on_area_entered(a: Area3D) -> void:
	if not alive:
		return
	if a.is_in_group("pickup"):
		if a.live:
			game.collect(a)
	elif a.is_in_group("obstacle"):
		if a.live:
			game.hit(a)


func _on_graze(a: Area3D) -> void:
	if not alive or auto_pilot:
		return
	if a.is_in_group("obstacle") and a.live:
		game.graze(a.global_position)


# --------------------------------------------------------------------- events

func pop_sparks(where: Vector3) -> void:
	_sparks.global_position = where
	_sparks.restart()


func explode() -> void:
	alive = false
	model.visible = false
	if _phantom_model != null:
		_phantom_model.visible = false
	for flare in _music_flares:
		flare.visible = false
	_shield.visible = false
	_thruster.emitting = false
	_burst.global_position = global_position
	_burst.restart()
	_light.light_color = V.ORANGE
	_light.light_energy = 9.0


func revive() -> void:
	alive = true
	set_ship(ship_id)
	for flare in _music_flares:
		flare.visible = true
	model.scale = Vector3.ONE
	model.rotation = Vector3.ZERO
	_thruster.emitting = true
	_light.light_color = V.CYAN
	_light.light_energy = 2.6
	vx = 0.0
	vy = 0.0
	hover = HOVER_Y
	lift = HOVER_Y
	lateral = 0.0
	on_rail = false
	rail_s = 0.0
	grounded = true
	ducking = false
	global_transform = Transform3D(Basis.IDENTITY, Vector3(0, HOVER_Y, 0))
	_roll = 0.0
	_tilt = 0.0
