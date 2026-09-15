extends CanvasLayer
## All UI is built in code. Title / pause screens are button driven (PLAY,
## MODE, MAP, HANGAR, SETTINGS). SETTINGS is one compact tabbed panel (820 x 540):
##   GAME     mode, map, speed-follows-music, drop auto-boost, quality, fullscreen
##   EFFECTS  glow, shake, aberration, speed blur, scanlines, beat flash,
##            letterbox, cinematic cam, dust, gobo lights + brightness
##   AUDIO    music / sfx / engine volume, beat sync, beat clock read-out
##   MUSIC    game themes vs device music, library, playlist, transport
##   HANGAR   hovercraft select with a live 3D turntable preview (also on title)

const V := preload("res://scripts/visuals.gd")
const Biomes := preload("res://scripts/biomes.gd")
const Ships := preload("res://scripts/ship_factory.gd")
const ShipPreview := preload("res://scripts/ship_preview.gd")

const ENERGY_W := 460.0
const COMBO_W := 190.0
const XP_W := 460.0
const GOLD := Color(1.0, 0.85, 0.3)
const PANEL_W := 820.0
const PANEL_H := 540.0
const HANGAR_TAB := 4

var game = null
var settings_open := false

var _root: Control
var _hud_group: Control
var _menu: Control
var _over: Control
var _pause: Control
var _toasts: Control

# ---- hud
var _score_lbl: Label
var _best_lbl: Label
var _speed_lbl: Label
var _dist_lbl: Label
var _combo_lbl: Label
var _combo_bar: ColorRect
var _combo_bar_bg: ColorRect
var _energy_fill: ColorRect
var _energy_lbl: Label
var _power_lbl: Label
var _mult_lbl: Label
var _pips: Array[ColorRect] = []
var _xp_lbl: Label
var _xp_val: Label
var _xp_fill: ColorRect
var _beat_dot: ColorRect
var _beat_lbl: Label
var _music_lbl: Label
var _rhythm_lbl: Label
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _bridge_title: Label

# ---- menu / over / pause
var _prompt: Label
var _menu_best: Label
var _menu_pilot: Label
var _menu_xp_fill: ColorRect
var _menu_unlock: Label
var _biome_name: Label
var _biome_sub: Label
var _mode_btn: Button
var _menu_now: Label
var _over_title: Label
var _over_score: Label
var _over_stats: Label
var _over_record: Label
var _over_prompt: Label
var _over_xp_lbl: Label
var _over_xp_fill: ColorRect
var _pause_now: Label

# ---- settings panel
var _panel: PanelContainer
var _tabs: TabContainer
var _mode_opt: OptionButton
var _map_opt: OptionButton
var _quality_opt: OptionButton
var _fs_check: CheckButton
var _music_list: VBoxContainer
var _music_status: Label
var _music_time: Label
var _music_progress: ProgressBar
var _src_game: Button
var _src_device: Button
var _shuffle_btn: Button
var _beat_status: Label
var _file_dialog: FileDialog
var _sliders: Dictionary = {}

# ---- hangar (live ship preview, shared by the HANGAR tab + title overlay)
var hangar_open := false
var _hangar_preview: ShipPreview
var _hangar_host: Control
var _hangar_name: Label
var _hangar_tag: Label
var _hangar_desc: Label
var _hangar_specs: Label
var _game_ship_lbl: Label
var _menu_ship_lbl: Label
var _overlay: Control
var _overlay_host: Control
var _overlay_name: Label
var _overlay_tag: Label
var _overlay_desc: Label
var _overlay_specs: Label

var _shown_score := 0.0
var _t := 0.0
var _last_combo := 0
var _pip_flash := 0.0
var _beat_scale := 1.0

# ---- loading overlay (covers everything while the world lays out)
var _load_panel: Control
var _load_bg: ColorRect
var _load_title: Label
var _load_sub: Label
var _load_progress: ProgressBar
var _load_beat: ColorRect
var _load_beat_scale := 1.0
var _load_message: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 3
	_build()
	Sound.device_library_changed.connect(_rebuild_tracks)
	Sound.track_changed.connect(_on_track_changed)
	Sound.source_changed.connect(func(_m: int) -> void: _refresh_music_status())


# ============================================================== builders

func _area(al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float, parent: Control = null) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob
	(_root if parent == null else parent).add_child(c)
	return c


func _lbl(parent: Control, text: String, size: int, color: Color, halign: int,
		x: float, y: float, w: float, h: float, outline: int = 6) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.custom_minimum_size = Vector2(0, h)
	l.horizontal_alignment = halign
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.02, 0.0, 0.06, 0.9))
	l.pivot_offset = Vector2(w * 0.5, h * 0.5)
	parent.add_child(l)
	return l


func _rect(parent: Control, color: Color, x: float, y: float, w: float, h: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _style_button(b: Button, accent: Color, primary: bool = false) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(accent.r, accent.g, accent.b, 0.24 if primary else 0.10)
	n.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	n.set_border_width_all(2)
	n.set_corner_radius_all(8)
	n.content_margin_left = 14
	n.content_margin_right = 14
	n.content_margin_top = 5
	n.content_margin_bottom = 5
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(accent.r, accent.g, accent.b, 0.36)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(accent.r, accent.g, accent.b, 0.62)
	p.border_color = Color(1, 1, 1, 0.9)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", n)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color(1, 1, 1))
	b.focus_mode = Control.FOCUS_NONE


func _btn(parent: Control, text: String, pos: Vector2, size: Vector2, accent: Color = V.CYAN, primary: bool = false, font: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font)
	_style_button(b, accent, primary)
	parent.add_child(b)
	return b


func _shade(parent: Control, alpha: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.005, 0.06, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _title(parent: Control, text: String, size: int, y: float) -> void:
	_lbl(parent, text, size, Color(1.0, 0.12, 0.55, 0.85), HORIZONTAL_ALIGNMENT_CENTER, -7, y + 4, 1200, size + 22, 0)
	_lbl(parent, text, size, Color(0.15, 0.95, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 7, y - 4, 1200, size + 22, 0)
	_lbl(parent, text, size, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, y, 1200, size + 22, 10)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	_hud_group = _area(0, 0, 1, 1, 0, 0, 0, 0)
	_toasts = _area(0, 0, 1, 1, 0, 0, 0, 0)

	var tl := _area(0, 0, 0, 0, 42, 26, 482, 176, _hud_group)
	_lbl(tl, "SCORE", 20, Color(0.55, 0.85, 1.0, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 300, 26)
	_score_lbl = _lbl(tl, "0", 64, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT, 0, 22, 420, 70, 8)
	_best_lbl = _lbl(tl, "BEST 0", 20, Color(1.0, 0.45, 0.85, 0.9), HORIZONTAL_ALIGNMENT_LEFT, 2, 92, 340, 26)
	_rhythm_lbl = _lbl(tl, "", 19, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 2, 118, 420, 26, 4)

	var tr := _area(1, 0, 1, 0, -442, 26, -42, 176, _hud_group)
	_lbl(tr, "VELOCITY", 20, Color(0.55, 0.85, 1.0, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 0, 0, 400, 26)
	_speed_lbl = _lbl(tr, "0 KM/H", 46, V.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 0, 22, 400, 58, 8)
	_dist_lbl = _lbl(tr, "0 M", 26, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 0, 84, 400, 32)
	_music_lbl = _lbl(tr, "", 16, Color(0.8, 0.9, 1.0, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 0, 118, 400, 22, 4)

	var tc := _area(0.5, 0, 0.5, 0, -160, 24, 160, 190, _hud_group)
	_combo_lbl = _lbl(tc, "", 54, V.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 320, 64, 8)
	_mult_lbl = _lbl(tc, "", 20, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0, 60, 320, 24)
	_combo_bar_bg = _rect(tc, Color(1, 1, 1, 0.12), 160 - COMBO_W * 0.5, 90, COMBO_W, 6)
	_combo_bar = _rect(tc, V.YELLOW, 160 - COMBO_W * 0.5, 90, COMBO_W, 6)
	_beat_dot = _rect(tc, V.CYAN, 160 - 8, 112, 16, 16)
	_beat_dot.pivot_offset = Vector2(8, 8)
	_beat_lbl = _lbl(tc, "", 16, Color(0.7, 0.95, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0, 132, 320, 22, 4)

	var bc := _area(0.5, 1, 0.5, 1, -ENERGY_W * 0.5 - 10, -166, ENERGY_W * 0.5 + 10, -28, _hud_group)
	_xp_lbl = _lbl(bc, "PILOT LV 1", 17, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 10, 0, 240, 22, 4)
	_xp_val = _lbl(bc, "", 17, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, ENERGY_W - 230, 0, 240, 22, 4)
	_rect(bc, Color(1, 0.85, 0.3, 0.13), 10, 24, XP_W, 6)
	_xp_fill = _rect(bc, GOLD, 10, 24, 0, 6)
	_energy_lbl = _lbl(bc, "BOOST  [ SHIFT ]", 19, Color(0.7, 0.95, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 10, 62, ENERGY_W, 24)
	_rect(bc, Color(0.6, 0.9, 1.0, 0.13), 10, 90, ENERGY_W, 18)
	_energy_fill = _rect(bc, V.CYAN, 10, 90, ENERGY_W, 18)

	var bl := _area(0, 1, 0, 1, 42, -104, 402, -28, _hud_group)
	_lbl(bl, "SHIELDS", 19, Color(0.6, 1.0, 0.7, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 300, 24)
	for i in 4:
		_pips.append(_rect(bl, V.LIME, float(i) * 54.0, 30, 46, 14))

	var br := _area(1, 1, 1, 1, -442, -104, -42, -28, _hud_group)
	_power_lbl = _lbl(br, "", 22, V.VIOLET, HORIZONTAL_ALIGNMENT_RIGHT, 0, 8, 400, 56)

	_bar_top = ColorRect.new()
	_bar_top.color = Color(0, 0, 0, 0.92)
	_bar_top.anchor_right = 1.0
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_top)
	_bar_bot = ColorRect.new()
	_bar_bot.color = Color(0, 0, 0, 0.92)
	_bar_bot.anchor_top = 1.0
	_bar_bot.anchor_right = 1.0
	_bar_bot.anchor_bottom = 1.0
	_bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_bot)
	_bridge_title = _lbl(_bar_bot, "", 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 0, 0, 4)
	_bridge_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bridge_title.modulate.a = 0.0

	_build_loading()
	_build_menu()
	_build_over()
	_build_pause()
	_build_settings()
	_build_hangar()
	refresh_biome()
	refresh_ship()


func _build_loading() -> void:
	_load_panel = Control.new()
	_load_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_load_panel.visible = false
	_root.add_child(_load_panel)

	_load_bg = ColorRect.new()
	_load_bg.color = Color(0.012, 0.004, 0.025, 0.96)
	_load_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_panel.add_child(_load_bg)

	var ring := ColorRect.new()
	ring.color = Color(0.1, 0.4, 0.7, 0.16)
	ring.size = Vector2(220, 220)
	ring.pivot_offset = Vector2(110, 110)
	ring.anchor_left = 0.5
	ring.anchor_right = 0.5
	ring.anchor_top = 0.5
	ring.anchor_bottom = 0.5
	ring.offset_left = -110
	ring.offset_right = 110
	ring.offset_top = -110
	ring.offset_bottom = 110
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_panel.add_child(ring)
	_load_beat = ring

	var box := Control.new()
	box.anchor_left = 0.5; box.anchor_right = 0.5
	box.anchor_top = 0.5; box.anchor_bottom = 0.5
	box.offset_left = -360; box.offset_right = 360
	box.offset_top = -160; box.offset_bottom = 160
	_load_panel.add_child(box)

	_lbl(box, "HYPERDRIFT", 56, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, -110, 720, 72, 12)
	_load_title = _lbl(box, "GENERATING WORLD FROM MUSIC…", 24, V.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 0, -22, 720, 32, 6)
	_load_sub = _lbl(box, "", 18, Color(0.85, 0.95, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 0, 18, 720, 28, 4)
	_load_message = _lbl(box, "", 15, Color(0.7, 0.85, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 0, 52, 720, 22, 3)
	_load_progress = ProgressBar.new()
	_load_progress.max_value = 1.0
	_load_progress.show_percentage = false
	_load_progress.custom_minimum_size = Vector2(620, 10)
	_load_progress.position = Vector2(50, 88)
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(1, 1, 1, 0.1)
	var pfill := StyleBoxFlat.new()
	pfill.bg_color = V.CYAN
	_load_progress.add_theme_stylebox_override("background", pbg)
	_load_progress.add_theme_stylebox_override("fill", pfill)
	box.add_child(_load_progress)


func show_loading(message: String) -> void:
	if _load_panel == null:
		return
	# The loading panel is a child of _root but was added BEFORE the menu, so
	# the menu would otherwise render ON TOP of it. Hide every other screen.
	_clear_toasts()
	_menu.visible = false
	_over.visible = false
	_pause.visible = false
	if _panel != null:
		_panel.visible = false
	settings_open = false
	_load_panel.visible = true
	_load_panel.modulate.a = 0.0
	create_tween().tween_property(_load_panel, "modulate:a", 1.0, 0.22)
	_load_title.text = "GENERATING WORLD FROM MUSIC…"
	_load_sub.text = message
	_load_message.text = ""
	_load_progress.value = 0.0
	_load_beat_scale = 1.0


func update_loading(progress: float, message: String) -> void:
	_load_progress.value = clampf(progress, 0.0, 1.0)
	_load_message.text = message
	_load_beat_scale = 1.4


func hide_loading() -> void:
	if _load_panel == null:
		return
	var tw := create_tween()
	tw.tween_property(_load_panel, "modulate:a", 0.0, 0.28)
	tw.tween_callback(func() -> void: _load_panel.visible = false)


func _build_menu() -> void:
	_menu = _area(0, 0, 1, 1, 0, 0, 0, 0)
	_shade(_menu, 0.55)
	var box := _area(0.5, 0.5, 0.5, 0.5, -600, -340, 600, 340, _menu)
	_title(box, "HYPERDRIFT", 112, 0)
	_lbl(box, "N E O N   H I G H W A Y   P R O T O C O L", 22, Color(0.6, 0.9, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 0, 128, 1200, 30)

	_menu_pilot = _lbl(box, "PILOT LV 1", 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 0, 166, 1200, 28, 6)
	_rect(box, Color(1, 0.85, 0.3, 0.14), 300, 198, 600, 7)
	_menu_xp_fill = _rect(box, GOLD, 300, 198, 0, 7)
	_menu_unlock = _lbl(box, "", 16, Color(0.75, 0.95, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0, 208, 1200, 22, 4)
	_menu_best = _lbl(box, "BEST 0", 26, V.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 0, 232, 1200, 32)

	# Map selector (clickable arrows)
	_biome_name = _lbl(box, "NEON GRID", 38, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, 276, 1200, 46, 8)
	_biome_sub = _lbl(box, "", 17, Color(0.6, 0.9, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 0, 322, 1200, 24)
	_btn(box, "<", Vector2(400, 278), Vector2(56, 42), V.MAGENTA).pressed.connect(func() -> void: game.cycle_biome(-1))
	_btn(box, ">", Vector2(744, 278), Vector2(56, 42), V.MAGENTA).pressed.connect(func() -> void: game.cycle_biome(1))

	# Hovercraft quick-select (the full live 3D preview lives in the HANGAR)
	_menu_ship_lbl = _lbl(box, "HOVERCRAFT:  VECTOR", 17, V.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 0, 348, 1200, 24, 4)
	_btn(box, "<", Vector2(408, 344), Vector2(52, 32), V.MAGENTA, false, 18).pressed.connect(func() -> void: cycle_ship_ui(-1))
	_btn(box, ">", Vector2(740, 344), Vector2(52, 32), V.MAGENTA, false, 18).pressed.connect(func() -> void: cycle_ship_ui(1))

	# Main buttons: PLAY / MODE / HANGAR / SETTINGS / MUSIC
	var play := _btn(box, "▶   PLAY", Vector2(600 - 170, 386), Vector2(340, 58), V.CYAN, true, 28)
	play.pressed.connect(func() -> void: Sound.play("ui", 1.0, -6.0); game.start_run())
	_mode_btn = _btn(box, "MODE:  CLASSIC", Vector2(600 - 344, 454), Vector2(164, 46), V.YELLOW, false, 16)
	_mode_btn.pressed.connect(func() -> void: game.set_mode(1 - game.mode); Sound.play("ui", 1.1, -6.0))
	var hg := _btn(box, "HANGAR", Vector2(600 - 170, 454), Vector2(164, 46), V.CYAN, true, 16)
	hg.pressed.connect(func() -> void: show_hangar())
	var st := _btn(box, "⚙  SETTINGS", Vector2(600 + 4, 454), Vector2(164, 46), V.VIOLET, true, 16)
	st.pressed.connect(func() -> void: show_settings(0))
	var mu := _btn(box, "♪  MUSIC", Vector2(600 + 178, 454), Vector2(164, 46), V.LIME, false, 16)
	mu.pressed.connect(func() -> void: show_settings(3))
	_menu_now = _lbl(box, "", 16, Color(0.85, 0.9, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 0, 508, 1200, 22, 4)

	_lbl(box, "A / D  STRAFE      SPACE  JUMP      S  DUCK      E  ADRENALINE      H  HANGAR      ESC  PAUSE      F2  SETTINGS", 16,
			Color(0.85, 0.9, 1.0, 0.65), HORIZONTAL_ALIGNMENT_CENTER, 0, 538, 1200, 24, 4)
	_prompt = _lbl(box, "PRESS  SPACE  TO DRIVE", 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, 574, 1200, 44, 8)
	_menu.visible = false


func _build_over() -> void:
	_over = _area(0, 0, 1, 1, 0, 0, 0, 0)
	_shade(_over, 0.62)
	var box := _area(0.5, 0.5, 0.5, 0.5, -600, -320, 600, 320, _over)
	_over_title = _lbl(box, "SIGNAL LOST", 84, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1200, 106, 10)
	_over_record = _lbl(box, "NEW RECORD", 32, V.LIME, HORIZONTAL_ALIGNMENT_CENTER, 0, 108, 1200, 40)
	_lbl(box, "FINAL SCORE", 20, Color(0.6, 0.9, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 0, 154, 1200, 26)
	_over_score = _lbl(box, "0", 80, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, 176, 1200, 90, 10)
	_over_stats = _lbl(box, "", 21, Color(0.85, 0.92, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 0, 274, 1200, 70, 4)
	_over_xp_lbl = _lbl(box, "", 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 0, 352, 1200, 30, 6)
	_rect(box, Color(1, 0.85, 0.3, 0.14), 300, 388, 600, 8)
	_over_xp_fill = _rect(box, GOLD, 300, 388, 0, 8)
	_btn(box, "▶   RUN IT BACK", Vector2(600 - 300, 420), Vector2(290, 52), V.CYAN, true, 22).pressed.connect(func() -> void: game.start_run())
	_btn(box, "MAIN MENU", Vector2(600 + 10, 420), Vector2(290, 52), V.MAGENTA, false, 22).pressed.connect(func() -> void: game.to_menu())
	_over_prompt = _lbl(box, "SPACE / R  —  RUN IT BACK        ESC  —  MENU", 18, Color(1.0, 0.6, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0, 484, 1200, 30, 4)
	_over.visible = false


func _build_pause() -> void:
	_pause = _area(0, 0, 1, 1, 0, 0, 0, 0)
	_shade(_pause, 0.6)
	var box := _area(0.5, 0.5, 0.5, 0.5, -600, -220, 600, 220, _pause)
	_title(box, "PAUSED", 88, 0)
	_btn(box, "▶   RESUME", Vector2(600 - 330, 150), Vector2(210, 50), V.CYAN, true, 20).pressed.connect(func() -> void: game.pause_game(false))
	_btn(box, "RESTART", Vector2(600 - 105, 150), Vector2(210, 50), V.YELLOW, false, 20).pressed.connect(func() -> void: game.start_run())
	_btn(box, "END RUN", Vector2(600 + 120, 150), Vector2(210, 50), V.MAGENTA, false, 20).pressed.connect(func() -> void: game.end_run())
	_btn(box, "⚙   SETTINGS", Vector2(600 - 220, 214), Vector2(210, 46), V.VIOLET, true, 18).pressed.connect(func() -> void: show_settings(0))
	_btn(box, "♪   MUSIC", Vector2(600 + 10, 214), Vector2(210, 46), V.LIME, false, 18).pressed.connect(func() -> void: show_settings(3))
	_pause_now = _lbl(box, "", 17, Color(0.85, 0.9, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 0, 276, 1200, 24, 4)
	_lbl(box, "ESC  RESUME        R  RESTART        F2  SETTINGS", 16, Color(0.7, 0.8, 1.0, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 0, 306, 1200, 22, 3)
	_pause.visible = false


# ============================================================== settings panel

func _build_settings() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_W * 0.5
	_panel.offset_top = -PANEL_H * 0.5
	_panel.offset_right = PANEL_W * 0.5
	_panel.offset_bottom = PANEL_H * 0.5
	_panel.visible = false
	_root.add_child(_panel)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.01, 0.07, 0.97)
	sb.border_color = Color(0.2, 0.9, 1.0, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var head := HBoxContainer.new()
	vbox.add_child(head)
	var title := _lbl(head, "SETTINGS", 26, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 400, 34, 6)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn(head, "✕  CLOSE", Vector2.ZERO, Vector2(120, 34), V.MAGENTA, false, 16).pressed.connect(hide_settings)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(PANEL_W - 36, PANEL_H - 70)
	_tabs.add_theme_font_size_override("font_size", 17)
	vbox.add_child(_tabs)

	_build_tab_game()
	_build_tab_effects()
	_build_tab_audio()
	_build_tab_music()
	_build_tab_hangar()

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.size = Vector2(820, 560)
	_file_dialog.add_filter("*.mp3, *.ogg, *.wav", "Audio files")
	_file_dialog.files_selected.connect(_on_files_selected)
	_file_dialog.file_selected.connect(func(p: String) -> void: _on_files_selected(PackedStringArray([p])))
	_file_dialog.dir_selected.connect(_on_folder_selected)
	add_child(_file_dialog)


func _tab(name_: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = name_
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	_tabs.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	margin.add_child(v)
	return v


func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var l := _lbl(h, label, 16, Color(0.8, 0.92, 1.0, 0.9), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 250, 30, 3)
	l.custom_minimum_size = Vector2(250, 30)
	return h


## label | slider | value  — all sliders are stored so they can be re-synced.
func _slider(parent: Control, key: String, label: String, lo: float, hi: float, value: float, fmt: String, on_change: Callable) -> void:
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(380, 26)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	h.add_child(s)
	var vl := _lbl(h, fmt % value, 15, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 0, 0, 70, 30, 3)
	vl.custom_minimum_size = Vector2(70, 30)
	var scale := 100.0 if fmt.ends_with("%%") else 1.0
	vl.text = fmt % (value * scale)
	s.value_changed.connect(func(v: float) -> void: vl.text = fmt % (v * scale); on_change.call(v); Persist.save_profile())
	_sliders[key] = s


func _toggle(parent: Control, label: String, value: bool, on_change: Callable) -> CheckButton:
	var h := _row(parent, label)
	var c := CheckButton.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool) -> void: on_change.call(on); Persist.save_profile())
	h.add_child(c)
	return c


func _option(parent: Control, label: String, items: Array, selected: int, on_change: Callable) -> OptionButton:
	var h := _row(parent, label)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = selected
	o.custom_minimum_size = Vector2(300, 32)
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 16)
	o.item_selected.connect(func(i: int) -> void: on_change.call(i); Persist.save_profile())
	h.add_child(o)
	return o


func _build_tab_game() -> void:
	var v := _tab("GAME")
	_mode_opt = _option(v, "GAME MODE", ["CLASSIC  —  hazards, shields, sky structures", "RHYTHM  —  no hazards, fly through beat pads"], Persist.mode,
			func(i: int) -> void: game.set_mode(i))
	var maps: Array = []
	for i in Biomes.COUNT:
		maps.append("%s  (%s)" % [Biomes.name_of(i), Biomes.theme_of(i)])
	_map_opt = _option(v, "MAP", maps, Persist.biome, func(i: int) -> void: game.set_biome(i))
	# HOVERCRAFT selection lives in the HANGAR tab (live 3D preview); this row
	# shows the current pick and jumps there.
	var sh := _row(v, "HOVERCRAFT")
	_game_ship_lbl = _lbl(sh, "", 16, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 250, 30, 3)
	_game_ship_lbl.custom_minimum_size = Vector2(250, 30)
	_btn(sh, "OPEN HANGAR  →", Vector2.ZERO, Vector2(210, 32), V.VIOLET, true, 15).pressed.connect(func() -> void: show_settings(HANGAR_TAB))
	_toggle(v, "SHIP SPEED FOLLOWS THE MUSIC", Persist.speed_follows_music, func(on: bool) -> void: Persist.speed_follows_music = on)
	_toggle(v, "AUTO-BOOST ON THE DROP", Persist.drop_boost, func(on: bool) -> void: Persist.drop_boost = on)
	_toggle(v, "OBSTACLES / PADS FOLLOW THE BEAT", Persist.beat_sync, func(on: bool) -> void: Persist.beat_sync = on)
	_quality_opt = _option(v, "GRAPHICS QUALITY", ["PERFORMANCE", "BALANCED", "ULTRA"], Persist.quality,
			func(i: int) -> void: Persist.quality = i; game.apply_effect_settings())
	_fs_check = _toggle(v, "FULLSCREEN", false, func(on: bool) -> void:
		if on != game.is_fullscreen():
			game.toggle_fullscreen()
	)
	var h := _row(v, "PROGRESS")
	_btn(h, "RESET XP & RECORDS", Vector2.ZERO, Vector2(230, 34), V.MAGENTA, false, 15).pressed.connect(
			func() -> void: Persist.reset_progress(); _refresh_pilot(); pop_text("PROGRESS RESET", V.MAGENTA))


func _build_tab_effects() -> void:
	var v := _tab("EFFECTS")
	_slider(v, "glow", "GLOW / BLOOM STRENGTH", 0.0, 2.0, Persist.glow_amount, "%.2f", func(x: float) -> void: Persist.glow_amount = x; game.apply_effect_settings())
	_slider(v, "shake", "CAMERA SHAKE", 0.0, 1.5, Persist.shake_amount, "%.2f", func(x: float) -> void: Persist.shake_amount = x)
	_slider(v, "aberration", "CHROMATIC ABERRATION", 0.0, 1.5, Persist.aberration_amount, "%.2f", func(x: float) -> void: Persist.aberration_amount = x)
	_slider(v, "warp", "SPEED BLUR", 0.0, 1.5, Persist.warp_amount, "%.2f", func(x: float) -> void: Persist.warp_amount = x)
	_toggle(v, "GOBO / MOVING-HEAD LIGHTS", Persist.gobos, func(on: bool) -> void: Persist.gobos = on; game.apply_effect_settings())
	_toggle(v, "PATROL HELICOPTER + SEARCHLIGHT", Persist.helicopters, func(on: bool) -> void: Persist.helicopters = on; Persist.save_profile())
	_slider(v, "gobo_brightness", "GOBO BEAM BRIGHTNESS", 0.1, 1.6, Persist.gobo_brightness, "%.2f", func(x: float) -> void: Persist.gobo_brightness = x; game.apply_effect_settings())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	v.add_child(grid)
	for spec in [["BEAT FLASH", "beat_flash"], ["SCANLINES", "scanlines"], ["CINEMATIC CAMERA ON STRUCTURES", "cinematic_cam"],
			["LETTERBOX ON STRUCTURES", "letterbox"], ["AMBIENT DUST", "dust"]]:
		var c := CheckButton.new()
		c.text = spec[0]
		c.button_pressed = Persist.get(spec[1])
		c.focus_mode = Control.FOCUS_NONE
		c.add_theme_font_size_override("font_size", 14)
		var key: String = spec[1]
		c.toggled.connect(func(on: bool) -> void: Persist.set(key, on); Persist.save_profile(); game.apply_effect_settings())
		grid.add_child(c)


func _build_tab_audio() -> void:
	var v := _tab("AUDIO")
	_slider(v, "music", "MUSIC VOLUME", 0.0, 1.0, Persist.music_volume, "%.0f%%", func(x: float) -> void: Persist.music_volume = x; Sound.apply_volumes())
	_slider(v, "sfx", "SFX VOLUME", 0.0, 1.0, Persist.sfx_volume, "%.0f%%", func(x: float) -> void: Persist.sfx_volume = x; Sound.apply_volumes())
	_slider(v, "engine", "ENGINE VOLUME", 0.0, 1.0, Persist.engine_volume, "%.0f%%", func(x: float) -> void: Persist.engine_volume = x)
	_beat_status = _lbl(v, "", 15, Color(0.7, 0.95, 1.0, 0.8), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 700, 26, 3)
	_lbl(v, "[  and  ]  change track at any time   •   M  mute", 14, Color(0.6, 0.8, 1.0, 0.6), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 700, 24, 3)


func _build_tab_music() -> void:
	var v := _tab("MUSIC")
	var src := HBoxContainer.new()
	src.add_theme_constant_override("separation", 10)
	v.add_child(src)
	var grp := ButtonGroup.new()
	_src_game = _btn(src, "GAME THEMES", Vector2.ZERO, Vector2(200, 38), V.CYAN, false, 16)
	_src_game.toggle_mode = true
	_src_game.button_group = grp
	_src_game.pressed.connect(func() -> void: Sound.use_synth(); _refresh_music_status())
	_src_device = _btn(src, "♪  MY DEVICE MUSIC", Vector2.ZERO, Vector2(220, 38), V.LIME, false, 16)
	_src_device.toggle_mode = true
	_src_device.button_group = grp
	_src_device.pressed.connect(_on_device_source_pressed)
	_shuffle_btn = _btn(src, "SHUFFLE", Vector2.ZERO, Vector2(110, 38), V.VIOLET, false, 15)
	_shuffle_btn.toggle_mode = true
	_shuffle_btn.toggled.connect(func(on: bool) -> void: Sound.set_shuffle(on))

	_music_status = _lbl(v, "", 16, V.CYAN, HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 760, 24, 3)
	_music_progress = ProgressBar.new()
	_music_progress.max_value = 1.0
	_music_progress.show_percentage = false
	_music_progress.custom_minimum_size = Vector2(760, 8)
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(1, 1, 1, 0.1)
	var pfill := StyleBoxFlat.new()
	pfill.bg_color = V.CYAN
	_music_progress.add_theme_stylebox_override("background", pbg)
	_music_progress.add_theme_stylebox_override("fill", pfill)
	v.add_child(_music_progress)
	_music_time = _lbl(v, "", 13, Color(0.8, 0.9, 1.0, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 760, 18, 3)

	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	v.add_child(tr)
	_btn(tr, "|<<", Vector2.ZERO, Vector2(70, 34), V.CYAN, false, 15).pressed.connect(func() -> void: Sound.prev_track())
	_btn(tr, ">  ||", Vector2.ZERO, Vector2(80, 34), V.CYAN, true, 15).pressed.connect(func() -> void: Sound.toggle_play(); _refresh_music_status())
	_btn(tr, ">>|", Vector2.ZERO, Vector2(70, 34), V.CYAN, false, 15).pressed.connect(func() -> void: Sound.next_track())
	_btn(tr, "+ ADD FILES…", Vector2.ZERO, Vector2(140, 34), V.LIME, true, 15).pressed.connect(_pick_files)
	_btn(tr, "+ ADD FOLDER…", Vector2.ZERO, Vector2(150, 34), V.LIME, true, 15).pressed.connect(_pick_folder)
	_btn(tr, "SCAN LIBRARY", Vector2.ZERO, Vector2(140, 34), V.CYAN, false, 15).pressed.connect(_scan_system)
	_btn(tr, "CLEAR", Vector2.ZERO, Vector2(80, 34), V.MAGENTA, false, 15).pressed.connect(func() -> void: Sound.clear_library(); _refresh_music_status())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_music_list = VBoxContainer.new()
	_music_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_music_list)


# ============================================================== hangar (live ship select)

func _build_tab_hangar() -> void:
	var v := _tab("HANGAR")
	_lbl(v, "HOVERCRAFT  —  LIVE 3D PREVIEW  (SELECTION APPLIES INSTANTLY)", 15, Color(0.75, 0.9, 1.0, 0.9), HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 760, 22, 3)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	_btn(h, "<", Vector2.ZERO, Vector2(52, 230), V.MAGENTA, false, 26).pressed.connect(func() -> void: cycle_ship_ui(-1))
	_hangar_host = Control.new()
	_hangar_host.custom_minimum_size = Vector2(620, 230)
	h.add_child(_hangar_host)
	_btn(h, ">", Vector2.ZERO, Vector2(52, 230), V.MAGENTA, false, 26).pressed.connect(func() -> void: cycle_ship_ui(1))
	_hangar_preview = ShipPreview.new()
	_hangar_host.add_child(_hangar_preview)
	_hangar_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hangar_preview.setup(Persist.ship_id, Vector2i(620, 230))
	_hangar_name = _lbl(v, "", 24, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 760, 28, 6)
	_hangar_tag = _lbl(v, "", 14, V.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 760, 20, 3)
	_hangar_desc = _lbl(v, "", 13, Color(0.82, 0.88, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 760, 34, 3)
	_hangar_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hangar_specs = _lbl(v, "", 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 760, 20, 3)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(brow)
	_btn(brow, "PREV", Vector2.ZERO, Vector2(150, 34), V.MAGENTA, false, 15).pressed.connect(func() -> void: cycle_ship_ui(-1))
	_btn(brow, "SELECT", Vector2.ZERO, Vector2(220, 34), V.CYAN, true, 15).pressed.connect(_on_ship_select)
	_btn(brow, "NEXT", Vector2.ZERO, Vector2(150, 34), V.MAGENTA, false, 15).pressed.connect(func() -> void: cycle_ship_ui(1))


func _build_hangar() -> void:
	_overlay = _area(0, 0, 1, 1, 0, 0, 0, 0)
	var shade := _shade(_overlay, 0.80)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := _area(0.5, 0.5, 0.5, 0.5, -470, -330, 470, 330, _overlay)
	_lbl(box, "HANGAR", 64, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 940, 78, 10)
	_lbl(box, "SELECT YOUR HOVERCRAFT  —  LEFT / RIGHT TO BROWSE, ENTER TO SELECT", 16, Color(0.7, 0.9, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0, 80, 940, 24, 4)
	_overlay_host = Control.new()
	_overlay_host.position = Vector2(90, 110)
	_overlay_host.size = Vector2(760, 320)
	box.add_child(_overlay_host)
	_btn(box, "<", Vector2(22, 210), Vector2(56, 110), V.MAGENTA, false, 30).pressed.connect(func() -> void: cycle_ship_ui(-1))
	_btn(box, ">", Vector2(862, 210), Vector2(56, 110), V.MAGENTA, false, 30).pressed.connect(func() -> void: cycle_ship_ui(1))
	_overlay_name = _lbl(box, "", 34, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 0, 438, 940, 42, 8)
	_overlay_tag = _lbl(box, "", 16, V.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 0, 480, 940, 24, 3)
	_overlay_desc = _lbl(box, "", 15, Color(0.84, 0.90, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 20, 506, 900, 48, 3)
	_overlay_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_specs = _lbl(box, "", 15, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 0, 556, 940, 24, 3)
	_btn(box, "SELECT", Vector2(470 - 230, 588), Vector2(220, 50), V.CYAN, true, 20).pressed.connect(_on_overlay_select)
	_btn(box, "CLOSE", Vector2(470 + 10, 588), Vector2(220, 50), V.MAGENTA, false, 20).pressed.connect(func() -> void: hide_hangar())
	_overlay.visible = false


func show_hangar() -> void:
	if _overlay == null or hangar_open:
		return
	if settings_open:
		hide_settings()
	hangar_open = true
	# Move the single live preview into the overlay.
	if _hangar_preview != null and _overlay_host != null:
		_hangar_preview.get_parent().remove_child(_hangar_preview)
		_overlay_host.add_child(_hangar_preview)
		_hangar_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.25)
	refresh_ship()
	Sound.play("ui", 1.0, -6.0)


func hide_hangar() -> void:
	if not hangar_open:
		return
	hangar_open = false
	if _overlay != null:
		_overlay.visible = false
	if _hangar_preview != null and _hangar_host != null and _hangar_preview.get_parent() != _hangar_host:
		_hangar_preview.get_parent().remove_child(_hangar_preview)
		_hangar_host.add_child(_hangar_preview)
		_hangar_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	refresh_ship()


func cycle_ship_ui(dir: int) -> void:
	if game == null:
		return
	Sound.play("ui", 1.1, -8.0)
	game.cycle_ship(dir)


func _on_ship_select() -> void:
	Sound.play("power", 1.2, -6.0)
	pop_text("%s SELECTED" % Ships.ship_name(Persist.ship_id), Ships.ship_accent(Persist.ship_id))
	refresh_ship()


func _on_overlay_select() -> void:
	_on_ship_select()
	hide_hangar()


## Pushes the current ship into every readout: GAME tab, title menu,
## HANGAR tab and the overlay. Called by game.set_ship, so switching anywhere
## (even from the title arrows) updates the live 3D preview too.
func refresh_ship() -> void:
	var id: int = clampi(Persist.ship_id, 0, Ships.SHIP_COUNT - 1)
	var accent: Color = Ships.ship_accent(id)
	if _game_ship_lbl != null:
		_game_ship_lbl.text = Ships.ship_name(id)
		_game_ship_lbl.add_theme_color_override("font_color", accent)
	if _menu_ship_lbl != null:
		_menu_ship_lbl.text = "HOVERCRAFT:  %s" % Ships.ship_name(id)
		_menu_ship_lbl.add_theme_color_override("font_color", accent)
	if _hangar_preview != null:
		_hangar_preview.set_ship(id)
	if _hangar_name != null:
		_hangar_name.text = Ships.ship_name(id)
		_hangar_name.add_theme_color_override("font_color", accent)
		_hangar_tag.text = Ships.ship_tagline(id)
		_hangar_desc.text = Ships.ship_desc(id)
		_hangar_specs.text = _ship_spec_line(id)
	if _overlay_name != null:
		_overlay_name.text = Ships.ship_name(id)
		_overlay_name.add_theme_color_override("font_color", accent)
		_overlay_tag.text = Ships.ship_tagline(id)
		_overlay_desc.text = Ships.ship_desc(id)
		_overlay_specs.text = _ship_spec_line(id)


func _ship_spec_line(id: int) -> String:
	var parts: Array[String] = []
	for spec in Ships.ship_specs(id):
		parts.append("%s: %s" % [str(spec[0]), str(spec[1])])
	return "   •   ".join(parts)


func show_settings(tab: int = 0) -> void:
	hide_hangar()
	settings_open = true
	_panel.visible = true
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.18)
	_tabs.current_tab = clampi(tab, 0, _tabs.get_tab_count() - 1)
	_sync_settings()
	_rebuild_tracks()
	_refresh_music_status()


func hide_settings() -> void:
	settings_open = false
	if _panel != null:
		_panel.visible = false
		_panel.modulate.a = 0.0
	refresh_mode()
	refresh_biome()


func _sync_settings() -> void:
	_mode_opt.selected = Persist.mode
	_map_opt.selected = Persist.biome
	refresh_ship()
	_quality_opt.selected = Persist.quality
	_fs_check.set_pressed_no_signal(game.is_fullscreen())
	for k in _sliders.keys():
		var s: HSlider = _sliders[k]
		match k:
			"glow": s.set_value_no_signal(Persist.glow_amount)
			"shake": s.set_value_no_signal(Persist.shake_amount)
			"aberration": s.set_value_no_signal(Persist.aberration_amount)
			"warp": s.set_value_no_signal(Persist.warp_amount)
			"gobo_brightness": s.set_value_no_signal(Persist.gobo_brightness)
			"music": s.set_value_no_signal(Persist.music_volume)
			"sfx": s.set_value_no_signal(Persist.sfx_volume)
			"engine": s.set_value_no_signal(Persist.engine_volume)
	_shuffle_btn.set_pressed_no_signal(Sound.shuffle)
	_src_game.set_pressed_no_signal(Sound.music_mode == 0)
	_src_device.set_pressed_no_signal(Sound.music_mode == 1)


# ============================================================== screens

func show_menu() -> void:
	hide_hangar()
	_clear_toasts()
	_menu.visible = true
	_over.visible = false
	_pause.visible = false
	_hud_group.visible = false
	_menu.modulate.a = 0.0
	create_tween().tween_property(_menu, "modulate:a", 1.0, 0.6)
	_menu_best.text = "BEST  %s" % _fmt(Persist.best_score)
	refresh_biome()
	refresh_mode()
	_refresh_pilot()


func show_hud() -> void:
	hide_hangar()
	_clear_toasts()
	_menu.visible = false
	_over.visible = false
	_pause.visible = false
	_hud_group.visible = true
	_shown_score = 0.0
	_last_combo = 0
	refresh()


## Clears any floating toasts so stale text from a previous screen never
## lingers over the menu or the play field.
func _clear_toasts() -> void:
	if _toasts == null:
		return
	for c in _toasts.get_children():
		c.queue_free()


func show_pause() -> void:
	hide_hangar()
	_pause.visible = true
	_pause.modulate.a = 0.0
	create_tween().tween_property(_pause, "modulate:a", 1.0, 0.25)
	_pause_now.text = "♪  %s" % Sound.current_track_name()


func show_game_over() -> void:
	hide_hangar()
	_over.visible = true
	_over.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_property(_over, "modulate:a", 1.0, 0.5)
	_over_title.text = "RUN COMPLETE" if game.is_rhythm() else "SIGNAL LOST"
	_over_score.text = _fmt(int(game.score))
	_over_record.visible = game.new_record
	if game.is_rhythm():
		_over_stats.text = "PADS HIT  %d       MISSED  %d       PERFECT  %d       ACCURACY  %d%%\nBEST STREAK  x%d       DISTANCE  %d M       STRUCTURES  %d       BEST  %s" % [
			game.notes_hit, game.notes_missed, game.perfects, int(game.accuracy * 100.0), game.run_best_combo,
			int(game.distance), game.bridges_crossed, _fmt(Persist.best_score)]
	else:
		_over_stats.text = "DISTANCE  %d M       ORBS  %d       BEST COMBO  x%d       ON-BEAT GATES  %d\nGRAZES  %d       SMASHES  %d       STRUCTURES  %d       TOP SPEED  %d KM/H       BEST  %s" % [
			int(game.distance), game.orbs, game.run_best_combo, game.beat_hits, game.grazes,
			game.smashes, game.bridges_crossed, int(game.speed * 3.6 * 1.6), _fmt(Persist.best_score)]
	var lvl: int = Persist.level()
	var into: int = Persist.xp_into_level()
	var need: int = Persist.xp_to_next(lvl)
	_over_xp_lbl.text = "XP  +%d          PILOT LV %d          %s / %s" % [game.xp_run, lvl, _fmt(into), _fmt(need)]
	_over_xp_fill.size.x = 0.0
	var xt := create_tween()
	xt.tween_interval(0.9)
	xt.tween_property(_over_xp_fill, "size:x", 600.0 * float(into) / float(need), 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func flash_shields() -> void:
	_pip_flash = 1.0


func refresh() -> void:
	if game == null:
		return
	var mx: int = game.max_shields()
	var rhythm: bool = game.is_rhythm()
	for i in _pips.size():
		_pips[i].visible = i < mx and not rhythm
		_pips[i].color = V.LIME if i < game.shields else Color(1, 1, 1, 0.12)


func refresh_biome() -> void:
	if _biome_name == null:
		return
	var id: int = Persist.biome
	_biome_name.text = Biomes.name_of(id)
	_biome_sub.text = "%s   •   THEME: %s  (%d BPM)" % [Biomes.subtitle_of(id), Biomes.theme_of(id), int(Biomes.bpm_of(id))]
	if _map_opt != null:
		_map_opt.selected = id
	_refresh_music_status()


func refresh_mode() -> void:
	if _mode_btn == null or game == null:
		return
	_mode_btn.text = "MODE:  %s" % ("RHYTHM" if game.is_rhythm() else "CLASSIC")
	if _mode_opt != null:
		_mode_opt.selected = game.mode


func _refresh_pilot() -> void:
	var lvl: int = Persist.level()
	var into: int = Persist.xp_into_level()
	var need: int = Persist.xp_to_next(lvl)
	_menu_pilot.text = "PILOT LV %d      %s / %s XP" % [lvl, _fmt(into), _fmt(need)]
	_menu_xp_fill.size.x = 600.0 * float(into) / float(need)
	var nx: Dictionary = Persist.next_unlock(lvl)
	if int(nx["level"]) > 0:
		_menu_unlock.text = "NEXT UNLOCK  LV %d:  %s" % [int(nx["level"]), str(nx["text"])]
	else:
		_menu_unlock.text = "MAX RANK — ALL PERKS UNLOCKED"
	_menu_best.text = "BEST  %s" % _fmt(Persist.best_score)


func set_letterbox(on: bool) -> void:
	var h := 76.0 if on else 0.0
	if on and game != null and game.track.bridge != null:
		_bridge_title.text = "   ".join(game.track.bridge.kind_name().split(""))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bar_top, "offset_bottom", h, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bar_bot, "offset_top", -h, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bridge_title, "modulate:a", 1.0 if on else 0.0, 0.7)


func on_beat() -> void:
	_beat_scale = 1.9


# ============================================================== toasts

func pop_text(msg: String, color: Color) -> void:
	var l := _lbl(_toasts, msg, 40, color, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1200, 56, 8)
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 0.38
	l.anchor_bottom = 0.38
	l.offset_left = -600
	l.offset_right = 600
	l.offset_top = 0
	l.offset_bottom = 56
	l.pivot_offset = Vector2(600, 28)
	l.scale = Vector2(0.7, 0.7)
	var y0 := l.position.y
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", y0 - 75.0, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(l.queue_free)


func pop_text_delayed(msg: String, color: Color, delay: float) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(pop_text.bind(msg, color))


func pop_small(msg: String) -> void:
	var l := _lbl(_toasts, msg, 24, Color(1.0, 0.85, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 420, 32, 6)
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 0.56
	l.anchor_bottom = 0.56
	var off := randf_range(-240.0, 240.0)
	l.offset_left = -210 + off
	l.offset_right = 210 + off
	l.offset_top = randf_range(-20.0, 20.0)
	l.offset_bottom = l.offset_top + 32
	var y0 := l.position.y
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", y0 - 95.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(l.queue_free)


# ============================================================== music tab logic

func _on_device_source_pressed() -> void:
	if Sound.device_paths.is_empty():
		pop_text("ADD MUSIC FROM YOUR DEVICE FIRST", V.LIME)
		_pick_files()
	else:
		Sound.use_device()
	_refresh_music_status()


func _start_dir() -> String:
	var start := ""
	if Persist.music_folders.size() > 0:
		start = Persist.music_folders[Persist.music_folders.size() - 1]
	if start.is_empty() or not DirAccess.dir_exists_absolute(start):
		start = OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	if start.is_empty() or not DirAccess.dir_exists_absolute(start):
		start = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return start


func _pick_files() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.title = "Pick music files (mp3 / ogg / wav)"
	var s := _start_dir()
	if not s.is_empty():
		_file_dialog.current_dir = s
	_file_dialog.popup_centered()


func _pick_folder() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.title = "Pick a folder of music (scans sub-folders)"
	var s := _start_dir()
	if not s.is_empty():
		_file_dialog.current_dir = s
	_file_dialog.popup_centered()


func _scan_system() -> void:
	var n: int = Sound.scan_system_music()
	if n > 0:
		Sound.use_device()
		pop_text("%d TRACKS FOUND IN YOUR MUSIC FOLDER" % n, V.LIME)
	else:
		pop_text("NO MUSIC FOLDER FOUND — USE ADD FILES", V.MAGENTA)
	_rebuild_tracks()
	_refresh_music_status()


func _on_files_selected(paths: PackedStringArray) -> void:
	var n: int = Sound.add_files(paths)
	if Sound.device_paths.size() > 0:
		Sound.use_device()
		pop_text("%d TRACKS ADDED" % n if n > 0 else "ALREADY IN LIBRARY", V.LIME)
	else:
		pop_text("NO PLAYABLE AUDIO SELECTED", V.MAGENTA)
	_rebuild_tracks()
	_refresh_music_status()


func _on_folder_selected(dir: String) -> void:
	var n: int = Sound.add_folder(dir)
	if Sound.device_paths.size() > 0:
		Sound.use_device()
		pop_text("%d TRACKS ADDED" % n if n > 0 else "FOLDER ALREADY LOADED", V.LIME)
	else:
		pop_text("NO AUDIO FILES FOUND IN THAT FOLDER", V.MAGENTA)
	_rebuild_tracks()
	_refresh_music_status()


func _on_track_changed(track_name: String) -> void:
	_refresh_music_status()
	_rebuild_tracks()
	if not settings_open:
		pop_small("♪ " + track_name)


func _refresh_music_status() -> void:
	if _music_status == null:
		return
	var paused := Sound.is_music_paused()
	_music_status.text = "%s:   %s" % ["PAUSED" if paused else "NOW PLAYING", Sound.current_track_name()]
	_src_game.set_pressed_no_signal(Sound.music_mode == 0)
	_src_device.set_pressed_no_signal(Sound.music_mode == 1)
	if _pause_now != null:
		_pause_now.text = "♪  %s" % Sound.current_track_name()
	if _menu_now != null:
		_menu_now.text = "♪  %s" % Sound.current_track_name()


func _fmt_time(sec: float) -> String:
	var s := int(maxf(sec, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


func _rebuild_tracks() -> void:
	if _music_list == null:
		return
	for c in _music_list.get_children():
		c.queue_free()
	if Sound.device_paths.is_empty():
		var l := _lbl(_music_list, "NO DEVICE MUSIC LOADED YET  —  USE  \"+ ADD FILES\"  OR  \"+ ADD FOLDER\"  (MP3 / OGG / WAV)",
				15, Color(0.8, 0.85, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 740, 50)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	for i in Sound.device_paths.size():
		var current := Sound.music_mode == 1 and i == Sound.device_index
		var b := Button.new()
		b.text = "%s  %02d    %s" % ["▶" if current else "  ", i + 1, Sound.device_names[i]]
		b.custom_minimum_size = Vector2(730, 32)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_font_size_override("font_size", 15)
		_style_button(b, V.LIME if current else Color(0.45, 0.6, 0.85), current)
		var idx := i
		b.pressed.connect(func() -> void: Sound.play_device(idx))
		_music_list.add_child(b)


# ============================================================== tick

func _fmt(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = " " + out
	return out


func tick(delta: float) -> void:
	_t += delta
	if game == null:
		return

	# Hard guarantee: the menu / game-over overlay can never stay on screen
	# while a run is active (a stale node previously leaked into gameplay).
	if game.state == 1:
		if _menu.visible:
			_menu.visible = false
		if _over.visible:
			_over.visible = false

	# Loading ring pulses on the beat while the world is being laid out.
	if _load_panel != null and _load_panel.visible and _load_beat != null:
		var k := clampf(delta * 10.0, 0.0, 1.0)
		_load_beat_scale = lerpf(_load_beat_scale, 1.0, k)
		_load_beat.scale = Vector2(_load_beat_scale, _load_beat_scale)
		_load_beat.rotation = fmod(_t * 0.35, TAU)

	if _prompt != null:
		_prompt.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 4.0))
	if _over_record != null and _over_record.visible:
		var p: float = 1.0 + 0.08 * sin(_t * 8.0)
		_over_record.scale = Vector2(p, p)

	if settings_open:
		_music_progress.value = Sound.track_progress()
		_music_time.text = "%s  /  %s" % [_fmt_time(Sound.track_position()), _fmt_time(Sound.track_length())]
		var src: String = Sound.beat_source
		var extra := "   •   %s  B%d D%d M%d P%d  ×%.2f%s" % [
			Sound.dominant_layer, int(Sound.bass_wave * 100.0), int(Sound.drone * 100.0), int(Sound.melody * 100.0), int(Sound.percussion * 100.0), Sound.tempo_ratio,
			"   •   DROP!" if Sound.drop_active else ("   •   BREAKDOWN" if Sound.breakdown else "")]
		if src == "SYNTH":
			_beat_status.text = "BEAT CLOCK:  EXACT  —  %d BPM%s" % [int(roundf(Sound.beat_bpm)), extra]
		elif src == "DEVICE":
			_beat_status.text = (("BEAT CLOCK:  LOCKED  —  %d BPM" % int(roundf(Sound.beat_bpm))) if Sound.beat_locked else ("BEAT CLOCK:  LISTENING…  %d%%" % int(Sound.beat_conf * 100.0))) + extra
		else:
			_beat_status.text = "BEAT CLOCK:  NO MUSIC"

	if not _hud_group.visible:
		return

	_shown_score = lerpf(_shown_score, game.score, clampf(delta * 9.0, 0.0, 1.0))
	if absf(_shown_score - game.score) < 1.0:
		_shown_score = game.score
	_score_lbl.text = _fmt(int(_shown_score))
	_best_lbl.text = "BEST  %s" % _fmt(maxi(Persist.best_score, int(game.score)))
	_speed_lbl.text = "%d KM/H" % int(game.travel_speed() * 3.6 * 1.6)
	_dist_lbl.text = "%d M" % int(game.distance)
	var msm: float = game.music_speed_mult
	var tag := ""
	if Sound.drop_active:
		tag = "DROP  ×%.2f" % msm
	elif Sound.breakdown:
		tag = "BREAKDOWN  ×%.2f" % msm
	elif Persist.speed_follows_music and Sound.beat_source != "NONE":
		tag = "MUSIC  ×%.2f" % msm
	_music_lbl.text = tag
	if game.is_rhythm():
		_rhythm_lbl.text = "PADS %d / %d    ACC %d%%    STREAK %d" % [game.notes_hit, game.notes_hit + game.notes_missed, int(game.accuracy * 100.0), game.beat_streak]
	else:
		_rhythm_lbl.text = ""

	var combo: int = game.combo
	if combo != _last_combo:
		if combo > _last_combo:
			_combo_lbl.scale = Vector2(1.35, 1.35)
		_last_combo = combo
	_combo_lbl.scale = _combo_lbl.scale.lerp(Vector2.ONE, clampf(delta * 9.0, 0.0, 1.0))
	if combo > 0:
		_combo_lbl.text = "x%d" % game.multiplier
		_mult_lbl.text = "%d CHAIN" % combo
		var hue: float = clampf(0.14 - float(game.multiplier) * 0.012, 0.0, 1.0)
		var c := Color.from_hsv(hue, 0.85, 1.0)
		_combo_lbl.add_theme_color_override("font_color", c)
		_combo_bar.color = c
		_combo_bar.size.x = COMBO_W * clampf(game.combo_timer / 3.6, 0.0, 1.0)
		_combo_bar_bg.visible = true
		_combo_bar.visible = true
	else:
		_combo_lbl.text = ""
		_mult_lbl.text = ""
		_combo_bar_bg.visible = false
		_combo_bar.visible = false

	_beat_scale = lerpf(_beat_scale, 1.0, clampf(delta * 10.0, 0.0, 1.0))
	_beat_dot.scale = Vector2(_beat_scale, _beat_scale)
	var locked: bool = Sound.beat_locked
	var synced: bool = game.beat_sync_active()
	_beat_dot.color = (V.CYAN if synced else Color(1, 1, 1, 0.5)) if locked else Color(1, 1, 1, 0.18)
	if not Persist.beat_sync:
		_beat_lbl.text = "BEAT SYNC OFF"
	elif Sound.beat_source == "DEVICE" and not locked:
		_beat_lbl.text = "LISTENING…  %d%%" % int(Sound.beat_conf * 100.0)
	elif locked:
		_beat_lbl.text = "SYNC  %d BPM%s" % [int(roundf(Sound.beat_bpm)), ("   STREAK %d" % game.beat_streak) if game.beat_streak > 1 else ""]
	else:
		_beat_lbl.text = ""

	# The bottom bar is the ADRENALINE meter in classic mode (XP-charged,
	# press E when full) and the auto-boost readout in rhythm mode.
	if not game.is_rhythm():
		var ar: float = game.adrenaline_ratio()
		var active: bool = game.adrenaline_t > 0.0
		if active:
			var left: float = game.adrenaline_t / game.adrenaline_duration()
			_energy_fill.size.x = ENERGY_W * left
			_energy_fill.color = V.ORANGE.lerp(Color(1, 1, 1), 0.25 + 0.25 * sin(_t * 14.0))
			_energy_lbl.text = "ADRENALINE  %0.1f s  —  SMASH EVERYTHING" % game.adrenaline_t
			_energy_lbl.modulate.a = 1.0
		elif ar >= 1.0:
			_energy_fill.size.x = ENERGY_W
			_energy_fill.color = V.ORANGE.lerp(Color(1, 1, 1), 0.3 + 0.3 * sin(_t * 8.0))
			_energy_lbl.text = "ADRENALINE READY  —  PRESS  E"
			_energy_lbl.modulate.a = 0.8 + 0.2 * sin(_t * 8.0)
		else:
			_energy_fill.size.x = ENERGY_W * ar
			_energy_fill.color = Color(1.0, 0.55, 0.15).lerp(V.ORANGE, ar)
			_energy_lbl.text = "ADRENALINE  %d%%  —  charges with XP" % int(ar * 100.0)
			_energy_lbl.modulate.a = 0.7
	else:
		var e: float = clampf(game.energy / 100.0, 0.0, 1.0)
		_energy_fill.size.x = ENERGY_W * e
		var ec := V.CYAN
		if game.overdrive_t > 0.0 or game.drop_boost_t > 0.0:
			ec = V.ORANGE
		elif e < 0.25:
			ec = Color(1.0, 0.35, 0.35)
		var shine: float = (0.15 + 0.15 * sin(_t * 9.0)) if game.boosting else 0.0
		_energy_fill.color = ec.lerp(Color(1, 1, 1), shine)
		_energy_lbl.text = "DROP BOOST  %0.1f" % game.drop_boost_t if game.drop_boost_t > 0.0 else "AUTO BOOST  —  WAITING FOR DROP"
		_energy_lbl.modulate.a = 0.6 + (0.4 if game.boosting else 0.0)

	var lvl: int = Persist.level()
	var into: int = Persist.xp_into_level()
	var need: int = Persist.xp_to_next(lvl)
	_xp_lbl.text = "PILOT LV %d" % lvl
	_xp_val.text = "%s / %s XP   (+%d)" % [_fmt(into), _fmt(need), game.xp_run]
	var want_w := XP_W * float(into) / float(need)
	_xp_fill.size.x = want_w if _xp_fill.size.x > want_w + 2.0 else lerpf(_xp_fill.size.x, want_w, clampf(delta * 6.0, 0.0, 1.0))

	var lines: Array[String] = []
	if game.overdrive_t > 0.0:
		lines.append("OVERDRIVE  %0.1f" % game.overdrive_t)
	if game.magnet_t > 0.0:
		lines.append("MAGNET  %0.1f" % game.magnet_t)
	if game.invuln_t > 0.0 and game.overdrive_t <= 0.0 and not game.is_rhythm():
		lines.append("SHIELDED  %0.1f" % game.invuln_t)
	_power_lbl.text = "\n".join(lines)

	if _pip_flash > 0.0:
		_pip_flash = maxf(0.0, _pip_flash - delta * 3.0)
		var s: float = 1.0 + _pip_flash * 0.35
		for i in _pips.size():
			_pips[i].scale = Vector2(s, s)
	refresh()
