extends SubViewportContainer
## Live 3D hangar preview: a turntable SubViewport showing the real ship
## geometry (built by ship_factory.gd, the same code the game flies), with
## pulsing engine glow, music flares, thruster and a neon display stage.
##
## One instance is shared between SETTINGS > HANGAR and the title-screen
## HANGAR overlay: hud.gd reparents this node when the overlay opens/closes.

const V := preload("res://scripts/visuals.gd")
const Ships := preload("res://scripts/ship_factory.gd")

var ship_id := 0
var auto_rotate := true

var _viewport: SubViewport
var _turntable: Node3D
var _models: Array[Node3D] = []
var _glow_sets: Array = []
var _flares: Array[MeshInstance3D] = []
var _flare_mats: Array[ShaderMaterial] = []
var _thruster: GPUParticles3D
var _ship_light: OmniLight3D
var _rim_light: OmniLight3D
var _ring_a: MeshInstance3D
var _ring_b: MeshInstance3D
var _t := 0.0
var _switch_pulse := 0.0
var _built := false


func setup(initial_ship: int, view_size: Vector2i) -> void:
	if _built:
		return
	_built = true
	ship_id = clampi(initial_ship, 0, Ships.SHIP_COUNT - 1)
	process_mode = Node.PROCESS_MODE_ALWAYS
	stretch = true
	custom_minimum_size = Vector2(view_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.name = "HangarView"
	_viewport.size = view_size
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.gui_disable_input = true
	_viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	_build_stage()
	_build_ships()
	set_ship(ship_id, false)


func set_ship(id: int, pulse: bool = true) -> void:
	ship_id = clampi(id, 0, Ships.SHIP_COUNT - 1)
	if not _built:
		return
	for i in _models.size():
		_models[i].visible = (i == ship_id)
	_apply_ship_tint()
	if pulse:
		_switch_pulse = 1.0


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.004, 0.02, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.42, 0.72)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.85
	env.fog_enabled = false
	env.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(4.4, 2.5, 5.6)
	cam.fov = 42.0
	cam.near = 0.05
	cam.far = 120.0
	_viewport.add_child(cam)
	cam.look_at(Vector3(0, 0.75, 0.2))

	var key := DirectionalLight3D.new()
	key.light_color = Color(0.85, 0.88, 1.0)
	key.light_energy = 1.0
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-48, 32, 0)
	_viewport.add_child(key)

	var fill := OmniLight3D.new()
	fill.light_color = Color(0.35, 0.75, 1.0)
	fill.light_energy = 1.1
	fill.omni_range = 14.0
	fill.shadow_enabled = false
	fill.position = Vector3(-4.5, 2.5, 3.5)
	_viewport.add_child(fill)

	_rim_light = OmniLight3D.new()
	_rim_light.light_color = Color(1.0, 0.3, 0.7)
	_rim_light.light_energy = 1.5
	_rim_light.omni_range = 16.0
	_rim_light.shadow_enabled = false
	_rim_light.position = Vector3(3.5, 1.6, -4.5)
	_viewport.add_child(_rim_light)

	# Display stage: dark disc + two neon rings.
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 5.4
	disc_mesh.bottom_radius = 5.6
	disc_mesh.height = 0.14
	disc_mesh.radial_segments = 48
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = V.metal_material(Color(0.02, 0.02, 0.05), 0.6, 0.45, Color(0.05, 0.10, 0.22), 0.5)
	disc.position = Vector3(0, -0.07, 0)
	_viewport.add_child(disc)

	_ring_a = MeshInstance3D.new()
	var ra := TorusMesh.new()
	ra.inner_radius = 3.05
	ra.outer_radius = 3.18
	ra.rings = 64
	ra.ring_segments = 8
	_ring_a.mesh = ra
	_ring_a.material_override = V.glow_material(V.CYAN, 2.2)
	_ring_a.position = Vector3(0, 0.02, 0)
	_viewport.add_child(_ring_a)

	_ring_b = MeshInstance3D.new()
	var rb := TorusMesh.new()
	rb.inner_radius = 4.35
	rb.outer_radius = 4.44
	rb.rings = 72
	rb.ring_segments = 8
	_ring_b.mesh = rb
	_ring_b.material_override = V.glow_material(V.MAGENTA, 1.8)
	_ring_b.position = Vector3(0, 0.02, 0)
	_viewport.add_child(_ring_b)

	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_turntable.position = Vector3(0, 1.2, 0)
	_turntable.rotation.y = -0.55
	_viewport.add_child(_turntable)


func _build_ships() -> void:
	for id in range(Ships.SHIP_COUNT):
		var root := Node3D.new()
		root.name = Ships.ship_name(id)
		_turntable.add_child(root)
		var glows: Array
		if id == Ships.SHIP_VECTOR:
			glows = Ships.build_vector(root)
		else:
			glows = Ships.build_phantom(root)
			# Match the in-game Phantom presence scale (see player.gd).
			root.scale = Vector3(1.08, 0.94, 1.06)
		_models.append(root)
		_glow_sets.append(glows)
	# Shared music flares, same layout as the live ship.
	var built: Dictionary = Ships.build_music_flares(_turntable)
	for f in built["flares"]:
		_flares.append(f)
	for m in built["mats"]:
		_flare_mats.append(m)
	# Always-on display thruster.
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(0.22, 0.22, 0.9)
	_thruster = V.make_particles(80, 0.5, trail_mesh, V.glow_material(V.CYAN, 4.0),
			6.0, 10.0, 0.4, 1.1, Color(0.6, 1.0, 1.0, 1.0), Color(1.0, 0.2, 0.7, 0.0))
	_thruster.position = Vector3(0, 0.0, 1.9)
	var tpm: ParticleProcessMaterial = _thruster.process_material
	tpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	tpm.emission_box_extents = Vector3(0.7, 0.12, 0.05)
	_turntable.add_child(_thruster)
	_ship_light = OmniLight3D.new()
	_ship_light.light_color = V.CYAN
	_ship_light.light_energy = 1.6
	_ship_light.omni_range = 10.0
	_ship_light.shadow_enabled = false
	_ship_light.position = Vector3(0, 1.0, -2.2)
	_turntable.add_child(_ship_light)


## Recolour the preview-only lights / thruster to the selected ship.
func _apply_ship_tint() -> void:
	var engine: Color = Ships.ship_engine_color(ship_id)
	if _rim_light != null:
		_rim_light.light_color = engine.lerp(Color(1, 1, 1), 0.15)
	if _ship_light != null:
		_ship_light.light_color = engine
	if _thruster != null:
		var tpm: ParticleProcessMaterial = _thruster.process_material
		if ship_id == Ships.SHIP_PHANTOM:
			_thruster.material_override = V.glow_material(V.VIOLET, 4.0)
			tpm.color_ramp = V.gradient_tex(Color(0.72, 0.55, 1.0, 1.0), Color(0.45, 0.10, 1.0, 0.0))
		else:
			_thruster.material_override = V.glow_material(V.CYAN, 4.0)
			tpm.color_ramp = V.gradient_tex(Color(0.6, 1.0, 1.0, 1.0), Color(1.0, 0.2, 0.7, 0.0))


func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	_switch_pulse = maxf(0.0, _switch_pulse - delta * 2.2)
	if auto_rotate:
		_turntable.rotation.y += delta * (0.55 + _switch_pulse * 4.0)
	_turntable.position.y = 1.2 + sin(_t * 1.6) * 0.07
	var vis: Node3D = _models[ship_id]
	vis.rotation.z = sin(_t * 1.1) * 0.04
	vis.rotation.x = sin(_t * 0.9 + 1.3) * 0.03
	_ring_a.rotation.y += delta * 0.25
	_ring_b.rotation.y -= delta * 0.18
	# Drive the preview from the live music layers when music is playing, with
	# an idle wave underneath so the hangar always feels alive.
	var bass: float = maxf(Sound.bass_pulse, 0.30 + 0.22 * sin(_t * 2.2))
	var drone: float = maxf(Sound.drone, 0.30 + 0.20 * sin(_t * 0.9 + 2.0))
	var melody: float = maxf(Sound.melody, 0.25 + 0.20 * sin(_t * 1.4 + 4.0))
	var perc: float = maxf(Sound.percussion * Sound.transient, maxf(0.0, sin(_t * 4.4)) * 0.22)
	var glows: Array = _glow_sets[ship_id]
	var gs: float = 1.0 + bass * 0.35 + perc * 0.20 + _switch_pulse * 0.6 + sin(_t * 9.0) * 0.03
	for g in glows:
		(g as MeshInstance3D).scale = Vector3.ONE * gs
	_ship_light.light_energy = 1.6 + bass * 1.2 + melody * 0.6 + perc * 0.8 + _switch_pulse * 2.0
	_thruster.amount_ratio = clampf(0.45 + bass * 0.4 + _switch_pulse * 0.5, 0.15, 1.0)
	_thruster.speed_scale = 0.9 + bass * 0.5 + _switch_pulse * 1.2
	_update_flares(bass, drone, melody, perc)


func _update_flares(bass: float, drone: float, melody: float, perc: float) -> void:
	if _flare_mats.is_empty():
		return
	var engine: Color = Ships.ship_engine_color(ship_id)
	var palette: Color = engine
	match Sound.dominant_layer:
		"BASS":
			palette = Color(1.0, 0.34, 0.18)
		"DRONE":
			palette = Color(0.48, 0.32, 1.0)
		"MELODY":
			palette = Color(0.28, 0.92, 1.0)
		"PERCUSSION":
			palette = Color(1.0, 0.82, 0.38)
		"SILENT":
			palette = engine
	palette = palette.lerp(engine, 0.25)
	var values := [bass + _switch_pulse * 0.8, melody, melody, perc, perc, drone * 0.7 + melody * 0.25]
	for i in _flare_mats.size():
		var f: ShaderMaterial = _flare_mats[i]
		var value: float = clampf(float(values[i]), 0.0, 1.4)
		f.set_shader_parameter("flare_color", palette)
		f.set_shader_parameter("strength", value * (1.05 if i == 0 else 0.62))
		f.set_shader_parameter("pulse", clampf(bass + perc * 0.8 + _switch_pulse, 0.0, 1.5))
		var s: float = 0.75 + value * (1.2 if i == 0 else 0.65)
		_flares[i].scale = Vector3(s, s, 1.0)
