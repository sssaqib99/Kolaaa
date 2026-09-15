extends Node
## Persist — profile, records, XP progression and settings, plus runtime
## InputMap setup.
##
## Input actions are registered from code so the project has zero external
## dependencies and always ships with a working control scheme
## (keyboard + gamepad) no matter which Godot version opens it.

const SAVE_PATH := "user://hyperdrift.cfg"

# ---- records
var best_score: int = 0
var best_distance: int = 0
var best_combo: int = 0
var total_runs: int = 0
var total_orbs: int = 0

# ---- progression
var total_xp: int = 0

# ---- settings
var music_volume: float = 0.8
var sfx_volume: float = 0.9
var engine_volume: float = 0.7
var quality: int = 2 # 0 = performance, 1 = balanced, 2 = ultra
var biome: int = 0
var music_mode: int = 0 # 0 = built-in synth themes, 1 = music from device
var music_files: PackedStringArray = PackedStringArray()
var music_folders: PackedStringArray = PackedStringArray()
var device_index: int = 0
var shuffle: bool = false
var beat_sync: bool = true
var ship_id: int = 0 # 0 = Vector interceptor, 1 = Phantom cruiser

# ---- game options
var mode: int = 0                 # 0 = CLASSIC (hazards), 1 = RHYTHM (beat pads only)
var speed_follows_music: bool = true
var drop_boost: bool = true

# ---- effects options (all user adjustable in SETTINGS > EFFECTS)
var glow_amount: float = 0.65     # 0..2, bloom strength (default reduced)
var shake_amount: float = 0.8     # 0..1.5
var aberration_amount: float = 0.7
var warp_amount: float = 0.8
var scanlines: bool = true
var beat_flash: bool = true
var letterbox: bool = true
var gobos: bool = true
var gobo_brightness: float = 0.8
var dust: bool = true
var cinematic_cam: bool = true
var helicopters: bool = true      # patrol helicopter + searchlight

signal record_changed

## Pilot-level unlocks. Level -> perk description.
const UNLOCKS := {
	3: "BOOST REGEN +25%",
	5: "COMBO WINDOW +0.6s",
	8: "START WITH 4 SHIELDS",
	12: "MAGNET LASTS 14s",
	16: "OVERDRIVE LASTS 9s",
	20: "ALL SCORE x1.1",
	25: "START EVERY RUN AT 40 KM/H BOOST",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_profile()


func _setup_input() -> void:
	var actions := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE, KEY_W, KEY_UP],
		"duck": [KEY_S, KEY_DOWN, KEY_CTRL],
		"pause": [KEY_ESCAPE, KEY_P],
		"adrenaline": [KEY_E, KEY_Q],
		"restart": [KEY_R],
		"start": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER],
		"mute": [KEY_M],
		"quality": [KEY_F1],
		"fullscreen": [KEY_F11],
		"music_panel": [KEY_F2],
		"next_track": [KEY_BRACKETRIGHT],
		"prev_track": [KEY_BRACKETLEFT],
	}
	for action_name in actions.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, 0.35)
		for key in actions[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action_name, ev)

	_add_pad_button("jump", JOY_BUTTON_A)
	_add_pad_button("duck", JOY_BUTTON_B)
	_add_pad_button("pause", JOY_BUTTON_START)
	_add_pad_button("adrenaline", JOY_BUTTON_LEFT_SHOULDER)
	_add_pad_button("adrenaline", JOY_BUTTON_X)
	_add_pad_button("start", JOY_BUTTON_A)
	_add_pad_button("start", JOY_BUTTON_START)
	_add_pad_button("restart", JOY_BUTTON_Y)
	_add_pad_button("music_panel", JOY_BUTTON_BACK)
	_add_pad_button("move_left", JOY_BUTTON_DPAD_LEFT)
	_add_pad_button("move_right", JOY_BUTTON_DPAD_RIGHT)
	_add_pad_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_pad_axis("move_right", JOY_AXIS_LEFT_X, 1.0)


func _add_pad_button(action_name: String, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action_name, ev)


func _add_pad_axis(action_name: String, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action_name, ev)


# ------------------------------------------------------------------- profile

func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_score = int(cfg.get_value("records", "best_score", 0))
	best_distance = int(cfg.get_value("records", "best_distance", 0))
	best_combo = int(cfg.get_value("records", "best_combo", 0))
	total_runs = int(cfg.get_value("stats", "total_runs", 0))
	total_orbs = int(cfg.get_value("stats", "total_orbs", 0))
	total_xp = int(cfg.get_value("stats", "total_xp", 0))
	music_volume = float(cfg.get_value("settings", "music_volume", 0.8))
	sfx_volume = float(cfg.get_value("settings", "sfx_volume", 0.9))
	engine_volume = float(cfg.get_value("settings", "engine_volume", 0.7))
	quality = int(cfg.get_value("settings", "quality", 2))
	biome = int(cfg.get_value("settings", "biome", 0))
	music_mode = int(cfg.get_value("settings", "music_mode", 0))
	device_index = int(cfg.get_value("settings", "device_index", 0))
	shuffle = bool(cfg.get_value("settings", "shuffle", false))
	beat_sync = bool(cfg.get_value("settings", "beat_sync", true))
	ship_id = int(cfg.get_value("settings", "ship_id", 0))
	mode = int(cfg.get_value("game", "mode", 0))
	speed_follows_music = bool(cfg.get_value("game", "speed_follows_music", true))
	drop_boost = bool(cfg.get_value("game", "drop_boost", true))
	glow_amount = float(cfg.get_value("fx", "glow", 0.65))
	shake_amount = float(cfg.get_value("fx", "shake", 0.8))
	aberration_amount = float(cfg.get_value("fx", "aberration", 0.7))
	warp_amount = float(cfg.get_value("fx", "warp", 0.8))
	scanlines = bool(cfg.get_value("fx", "scanlines", true))
	beat_flash = bool(cfg.get_value("fx", "beat_flash", true))
	letterbox = bool(cfg.get_value("fx", "letterbox", true))
	gobos = bool(cfg.get_value("fx", "gobos", true))
	helicopters = bool(cfg.get_value("fx", "helicopters", true))
	gobo_brightness = float(cfg.get_value("fx", "gobo_brightness", 0.8))
	dust = bool(cfg.get_value("fx", "dust", true))
	cinematic_cam = bool(cfg.get_value("fx", "cinematic_cam", true))
	music_files = PackedStringArray(cfg.get_value("library", "files", PackedStringArray()))
	music_folders = PackedStringArray(cfg.get_value("library", "folders", PackedStringArray()))
	# Migrate the single-folder setting from older profiles.
	var legacy: String = str(cfg.get_value("settings", "music_folder", ""))
	if not legacy.is_empty() and not music_folders.has(legacy):
		music_folders.append(legacy)


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("records", "best_score", best_score)
	cfg.set_value("records", "best_distance", best_distance)
	cfg.set_value("records", "best_combo", best_combo)
	cfg.set_value("stats", "total_runs", total_runs)
	cfg.set_value("stats", "total_orbs", total_orbs)
	cfg.set_value("stats", "total_xp", total_xp)
	cfg.set_value("settings", "music_volume", music_volume)
	cfg.set_value("settings", "sfx_volume", sfx_volume)
	cfg.set_value("settings", "engine_volume", engine_volume)
	cfg.set_value("settings", "quality", quality)
	cfg.set_value("settings", "biome", biome)
	cfg.set_value("settings", "music_mode", music_mode)
	cfg.set_value("settings", "device_index", device_index)
	cfg.set_value("settings", "shuffle", shuffle)
	cfg.set_value("settings", "beat_sync", beat_sync)
	cfg.set_value("settings", "ship_id", ship_id)
	cfg.set_value("game", "mode", mode)
	cfg.set_value("game", "speed_follows_music", speed_follows_music)
	cfg.set_value("game", "drop_boost", drop_boost)
	cfg.set_value("fx", "glow", glow_amount)
	cfg.set_value("fx", "shake", shake_amount)
	cfg.set_value("fx", "aberration", aberration_amount)
	cfg.set_value("fx", "warp", warp_amount)
	cfg.set_value("fx", "scanlines", scanlines)
	cfg.set_value("fx", "beat_flash", beat_flash)
	cfg.set_value("fx", "letterbox", letterbox)
	cfg.set_value("fx", "gobos", gobos)
	cfg.set_value("fx", "helicopters", helicopters)
	cfg.set_value("fx", "gobo_brightness", gobo_brightness)
	cfg.set_value("fx", "dust", dust)
	cfg.set_value("fx", "cinematic_cam", cinematic_cam)
	cfg.set_value("library", "files", music_files)
	cfg.set_value("library", "folders", music_folders)
	cfg.save(SAVE_PATH)


## Returns true when the finished run beat the stored record.
func submit_run(score: int, distance: int, combo: int, orbs: int) -> bool:
	var record := false
	total_runs += 1
	total_orbs += orbs
	if score > best_score:
		best_score = score
		record = true
	best_distance = maxi(best_distance, distance)
	best_combo = maxi(best_combo, combo)
	save_profile()
	record_changed.emit()
	return record


# ---------------------------------------------------------------- progression

static func xp_to_next(lvl: int) -> int:
	return 300 + 140 * (lvl - 1)


func level() -> int:
	var lvl := 1
	var remaining := total_xp
	while remaining >= xp_to_next(lvl) and lvl < 99:
		remaining -= xp_to_next(lvl)
		lvl += 1
	return lvl


func xp_into_level() -> int:
	var lvl := 1
	var remaining := total_xp
	while remaining >= xp_to_next(lvl) and lvl < 99:
		remaining -= xp_to_next(lvl)
		lvl += 1
	return remaining


## Adds XP. Returns the new level if a level-up happened, otherwise -1.
func add_xp(amount: int) -> int:
	if amount <= 0:
		return -1
	var before := level()
	total_xp += amount
	var after := level()
	return after if after > before else -1


static func unlock_text(lvl: int) -> String:
	return str(UNLOCKS.get(lvl, ""))


static func next_unlock(lvl: int) -> Dictionary:
	var keys := UNLOCKS.keys()
	keys.sort()
	for k in keys:
		if int(k) > lvl:
			return {"level": int(k), "text": str(UNLOCKS[k])}
	return {"level": -1, "text": "MAX RANK"}


func has_perk(required_level: int) -> bool:
	return level() >= required_level


func reset_progress() -> void:
	best_score = 0
	best_distance = 0
	best_combo = 0
	total_runs = 0
	total_orbs = 0
	total_xp = 0
	save_profile()
	record_changed.emit()
