extends Node3D
## Endless procedural highway.
##
## Decor (buildings, posts, arches, skyline) streams in fixed 60 m chunks.
## HAZARDS are scheduled on the BEAT CLOCK: every gate is placed where the ship
## will be when a future beat lands, so the level is phrased to the music -
## the built-in themes or whatever the player loaded from their device. When
## no beat lock exists the clock free-runs at the last tempo, so the same code
## path always produces a fair, evenly phrased track.

const V := preload("res://scripts/visuals.gd")
const ObstacleScript := preload("res://scripts/obstacle.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const BridgeScript := preload("res://scripts/bridge.gd")
const Biomes := preload("res://scripts/biomes.gd")
const NoirCarScript := preload("res://scripts/noir_car.gd")
const BUILDING_SHADER: Shader = preload("res://shaders/building.gdshader")

const CHUNK := 60.0
const AHEAD := 12 # skyline streams 720m ahead so tall Nocturne towers are present from the horizon
const TRACK_HALF := 14.7   # widened ~9% (was 13.5)
const CLEANUP_BEHIND := 40.0
const MIN_CORRIDOR := 6.4
const HORIZON_T := 4.6          # seconds of hazards scheduled ahead
const REST_EVERY := 7           # every Nth phrase is a breather

var game = null
var player = null
var bridge = null
var rng := RandomNumberGenerator.new()
var demo_mode := true
var biome_id := 0

var next_z := -60.0
var chunk_index := 0
var gates: Array = []           # [{z, done}] hazard gates for on-beat scoring
var _next_beat := 0
var _phrase_i := 0
var _last_bridge_dist := 0.0
var _bridge_interval := 700.0
var _structure_i := 0
var _pending_structure_z := -1e9   # Z where the next structure WILL be placed (reservation)
var gobo_rig = null
var rhythm_mode := false
var notes_live: Array = []

var _obstacles: Array = []
var _pickups: Array = []
var _posts: Array = []
var _arches: Array = []
var _towers: Array = []
var _buildings: Array = []
var _bursts: Array = []
var _burst_i := 0
var _shatters: Array = []
var _shatter_i := 0
var _shock_rings: Array = []
var _shock_t: Array = []

var _mats := {}
var _floor: MeshInstance3D
var _floor_mat: ShaderMaterial
var _rails: Array[MeshInstance3D] = []
var _dust: GPUParticles3D
var _rain: GPUParticles3D
var _hit_flash := 0.0
var _building_mats: Array = []
var _building_style := 0
var _noir_cars: Array = []
var _noir_car_t := 0.0
var _noir_atmosphere := 0.0
var _moon: MeshInstance3D
var _moon_halo: MeshInstance3D
var _moon_mat: StandardMaterial3D
var _moon_halo_mat: StandardMaterial3D
var _deco_crown_mat: StandardMaterial3D
var _deco_trim_mat: StandardMaterial3D


func _ready() -> void:
	rng.randomize()
	_build_materials()
	_build_ground()
	_build_pools()
	bridge = BridgeScript.new()
	add_child(bridge)
	gobo_rig = preload("res://scripts/gobo_rig.gd").new()
	add_child(gobo_rig)
	apply_biome(biome_id)


# --------------------------------------------------------------- static world

func _build_materials() -> void:
	_mats["block"] = V.neon_material(V.MAGENTA, 0, 2.9)
	_mats["low"] = V.neon_material(V.YELLOW, 1, 3.1)
	_mats["hang"] = V.neon_material(V.CYAN, 2, 3.1)
	_mats["mover"] = V.neon_material(V.ORANGE, 0, 3.0)
	_mats["spin"] = V.neon_material(V.VIOLET, 0, 3.0)
	_mats["hunter"] = V.neon_material(Color(1.0, 0.15, 0.25), 0, 3.4)
	# These two are intentionally matte StandardMaterial3D assets: Nocturne is
	# architectural and moonlit, not another emissive neon biome.
	_mats["obelisk"] = V.metal_material(Color(0.25, 0.18, 0.12), 0.45, 0.72, Color(0.06, 0.035, 0.02), 0.15)
	_mats["dustwall"] = V.metal_material(Color(0.42, 0.27, 0.13), 0.15, 0.92, Color(0.2, 0.1, 0.03), 0.25)
	_mats["deco_edge"] = V.metal_material(Color(0.42, 0.21, 0.14), 0.75, 0.28, Color(0.72, 0.42, 0.15), 0.8)
	_mats["cab"] = V.metal_material(Color(0.045, 0.055, 0.10), 0.86, 0.24, Color(0.02, 0.04, 0.10), 0.30)
	_mats["cab_trim"] = V.metal_material(Color(0.92, 0.70, 0.32), 0.82, 0.20, Color(0.95, 0.60, 0.16), 0.70)
	_mats["laser"] = V.glow_material(Color(1.0, 0.45, 0.75), 5.5)
	_mats["laser_idle"] = V.glow_material(Color(0.6, 0.6, 0.7), 0.8)
	_mats["rail"] = V.metal_material(Color(0.06, 0.02, 0.12), 0.7, 0.25, V.MAGENTA, 2.4)
	_mats["post"] = V.metal_material(Color(0.04, 0.03, 0.09), 0.8, 0.3, V.CYAN, 3.2)
	_mats["arch"] = V.metal_material(Color(0.05, 0.02, 0.1), 0.85, 0.2, V.VIOLET, 2.2)
	_mats["tower"] = V.metal_material(Color(0.03, 0.02, 0.07), 0.6, 0.45, Color(0.35, 0.12, 0.6), 0.55)
	_deco_crown_mat = V.metal_material(Color(0.018, 0.023, 0.055), 0.82, 0.24, Color(0.13, 0.07, 0.21), 0.35)
	_deco_trim_mat = V.metal_material(Color(0.48, 0.30, 0.13), 0.92, 0.22, Color(0.72, 0.46, 0.15), 0.55)
	for i in 8:
		var m := ShaderMaterial.new()
		m.shader = BUILDING_SHADER
		m.set_shader_parameter("seed", float(i) * 13.7 + 1.3)
		_building_mats.append(m)


func _build_ground() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(460.0, 900.0)
	pm.subdivide_width = 4
	pm.subdivide_depth = 8
	_floor = MeshInstance3D.new()
	_floor.mesh = pm
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = preload("res://shaders/grid_floor.gdshader")
	_floor_mat.set_shader_parameter("track_half", TRACK_HALF + 0.4)
	_floor.material_override = _floor_mat
	add_child(_floor)

	for s in [-1.0, 1.0]:
		var rm := BoxMesh.new()
		rm.size = Vector3(0.55, 1.0, 880.0)
		var r := MeshInstance3D.new()
		r.mesh = rm
		r.material_override = _mats["rail"]
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.position = Vector3(s * (TRACK_HALF + 0.6), 0.5, 0.0)
		add_child(r)
		_rails.append(r)

	var dust_mesh := BoxMesh.new()
	dust_mesh.size = Vector3(0.06, 0.06, 1.3)
	_dust = V.make_particles(260, 3.0, dust_mesh, V.glow_material(V.CYAN, 1.5),
			0.6, 25.0, 0.4, 1.5, Color(0.6, 0.95, 1.0, 0.0), Color(1.0, 0.4, 0.9, 0.0))
	var dpm: ParticleProcessMaterial = _dust.process_material
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dpm.emission_box_extents = Vector3(48.0, 16.0, 120.0)
	dpm.color_ramp = V.gradient_tex(Color(0.5, 0.95, 1.0, 0.9), Color(1.0, 0.35, 0.85, 0.0))
	_dust.emitting = true
	add_child(_dust)

	# Nocturne rain: muted, low-density streaks that catch the moonlight. The
	# emitter follows the ship and is disabled on every other map.
	var rain_mesh := BoxMesh.new()
	rain_mesh.size = Vector3(0.025, 0.68, 0.025)
	_rain = V.make_particles(460, 1.5, rain_mesh, V.glow_material(Color(0.42, 0.52, 0.92, 0.42), 0.65),
			16.0, 8.0, 0.35, 0.9, Color(0.54, 0.62, 1.0, 0.42), Color(0.28, 0.24, 0.58, 0.0), Vector3(0, -28.0, 0))
	var rpm: ParticleProcessMaterial = _rain.process_material
	rpm.direction = Vector3(-0.08, -1.0, 0.18)
	rpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rpm.emission_box_extents = Vector3(42.0, 3.0, 76.0)
	_rain.position = Vector3(0, 22.0, -70.0)
	_rain.emitting = false
	_rain.visible = false
	add_child(_rain)

	# Nocturne's persistent full moon. It follows the player at a horizon-safe
	# distance so the Art Deco skyline can silhouette against it without ever
	# being consumed by the moving world origin.
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 18.0
	moon_mesh.height = 36.0
	moon_mesh.radial_segments = 28
	moon_mesh.rings = 14
	_moon_mat = StandardMaterial3D.new()
	_moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_moon_mat.albedo_color = Color(1.0, 0.93, 0.68)
	_moon_mat.emission_enabled = true
	_moon_mat.emission = Color(0.62, 0.5, 0.25)
	_moon_mat.emission_energy_multiplier = 0.85
	_moon = MeshInstance3D.new()
	_moon.mesh = moon_mesh
	_moon.material_override = _moon_mat
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon.visible = false
	add_child(_moon)
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 23.0
	halo_mesh.height = 46.0
	halo_mesh.radial_segments = 24
	halo_mesh.rings = 12
	_moon_halo_mat = V.glow_material(Color(0.58, 0.25, 0.45, 0.18), 0.7)
	_moon_halo = MeshInstance3D.new()
	_moon_halo.mesh = halo_mesh
	_moon_halo.material_override = _moon_halo_mat
	_moon_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon_halo.visible = false
	add_child(_moon_halo)


func _build_pools() -> void:
	for i in 110:
		var o = ObstacleScript.new()
		add_child(o)
		o.recycle()
		_obstacles.append(o)
	for i in 220:
		var p = PickupScript.new()
		add_child(p)
		p.recycle()
		_pickups.append(p)

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.4, 6.0, 0.4)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(2.4, 0.4, 0.4)
	for i in 44:
		var root := Node3D.new()
		var pole := MeshInstance3D.new()
		pole.mesh = post_mesh
		pole.material_override = _mats["post"]
		pole.position.y = 3.0
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pole)
		var head := MeshInstance3D.new()
		head.mesh = head_mesh
		head.material_override = _mats["post"]
		head.position.y = 6.0
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(head)
		root.position = Vector3(0, -500, 0)
		add_child(root)
		_posts.append(root)

	for i in 10:
		var arch := Node3D.new()
		var beam := BoxMesh.new()
		beam.size = Vector3(40.0, 0.8, 0.8)
		var top := MeshInstance3D.new()
		top.mesh = beam
		top.material_override = _mats["arch"]
		top.position.y = 12.5
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arch.add_child(top)
		for s in [-1.0, 1.0]:
			var col := BoxMesh.new()
			col.size = Vector3(0.9, 12.5, 0.9)
			var mi := MeshInstance3D.new()
			mi.mesh = col
			mi.material_override = _mats["arch"]
			mi.position = Vector3(s * 19.4, 6.25, 0.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			arch.add_child(mi)
		arch.position = Vector3(0, -500, 0)
		add_child(arch)
		_arches.append(arch)

	for i in 124:
		var b := MeshInstance3D.new()
		b.mesh = BoxMesh.new()
		b.material_override = _building_mats[i % _building_mats.size()]
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_attach_deco_crown(b)
		b.position = Vector3(0, -500, 0)
		add_child(b)
		_buildings.append(b)

	# Nocturne traffic: safe background sedans gliding toward the camera in the
	# outer lane, each with warm headlights reflecting on the wet boulevard.
	for i in 5:
		var car = NoirCarScript.new()
		add_child(car)
		_noir_cars.append(car)

	for i in 44:
		var t := MeshInstance3D.new()
		t.mesh = BoxMesh.new()
		t.material_override = _mats["tower"]
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.position = Vector3(0, -500, 0)
		add_child(t)
		_towers.append(t)

	var shard := BoxMesh.new()
	shard.size = Vector3(0.14, 0.14, 0.34)
	for i in 10:
		var bu := V.make_particles(26, 0.6, shard, V.glow_material(V.CYAN, 5.0),
				11.0, 180.0, 0.5, 1.5, Color(1, 1, 1, 1), Color(1, 1, 1, 0))
		bu.one_shot = true
		bu.explosiveness = 1.0
		bu.emitting = false
		add_child(bu)
		_bursts.append(bu)

	# ---- SHATTER pool for adrenaline smashes: big chunky debris that tumbles
	# out under gravity, plus a flat expanding shock ring on the deck.
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.55, 0.55, 0.55)
	for i in 8:
		var sh := V.make_particles(64, 1.35, chunk, V.glow_material(V.MAGENTA, 4.0),
				22.0, 140.0, 0.45, 1.6, Color(1, 1, 1, 1), Color(1, 1, 1, 0), Vector3(0, -26.0, 0))
		sh.one_shot = true
		sh.explosiveness = 0.95
		sh.emitting = false
		var pm: ParticleProcessMaterial = sh.process_material
		pm.angular_velocity_min = -720.0
		pm.angular_velocity_max = 720.0
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(1.2, 1.4, 0.6)
		add_child(sh)
		_shatters.append(sh)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.85
		tm.outer_radius = 1.0
		tm.rings = 32
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = V.orb_material(V.MAGENTA, 4.0)
		ring.rotation_degrees = Vector3(90, 0, 0)
		ring.visible = false
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_shock_rings.append(ring)
		_shock_t.append(-1.0)


## Attaches a tiered Art Deco crown to every pooled building. Non-Nocturne
## maps simply hide it; Nocturne reveals it and sizes it from the tower's live
## width/height, producing varied setbacks, crowns and needle spires instead
## of a skyline made from identical plain boxes.
func _attach_deco_crown(building: MeshInstance3D) -> void:
	var crown := Node3D.new()
	crown.name = "DecoCrown"
	crown.visible = false
	building.add_child(crown)
	var setback := MeshInstance3D.new()
	setback.name = "Setback"
	setback.mesh = BoxMesh.new()
	setback.material_override = _deco_crown_mat
	setback.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	crown.add_child(setback)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	cap.mesh = BoxMesh.new()
	cap.material_override = _deco_trim_mat
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	crown.add_child(cap)
	var spire := MeshInstance3D.new()
	spire.name = "Spire"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 4
	spire.mesh = cm
	spire.material_override = _deco_crown_mat
	spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	crown.add_child(spire)
	var beacon := OmniLight3D.new()
	beacon.name = "CrownLight"
	beacon.light_color = Color(0.96, 0.73, 0.28)
	beacon.light_energy = 0.0
	beacon.omni_range = 18.0
	beacon.shadow_enabled = false
	crown.add_child(beacon)


func _configure_deco_crown(building: MeshInstance3D, w: float, h: float, seed_value: int) -> void:
	var crown := building.get_node_or_null("DecoCrown") as Node3D
	if crown == null:
		return
	var active := _building_style == 4
	crown.visible = active
	if not active:
		return
	# The crown begins at the top of the live box (building is centred on Y).
	crown.position = Vector3(0.0, h * 0.5, 0.0)
	var setback := crown.get_node("Setback") as MeshInstance3D
	var cap := crown.get_node("Cap") as MeshInstance3D
	var spire := crown.get_node("Spire") as MeshInstance3D
	var beacon := crown.get_node("CrownLight") as OmniLight3D
	var levels: float = 2.5 + float(seed_value % 4) * 1.25
	var sw: float = maxf(3.5, w * (0.45 + float(seed_value % 3) * 0.08))
	var sd: float = maxf(3.5, w * (0.50 + float((seed_value + 1) % 3) * 0.08))
	var sm := setback.mesh as BoxMesh
	sm.size = Vector3(sw, levels, sd)
	setback.position = Vector3(0.0, levels * 0.5, 0.0)
	var cm := cap.mesh as BoxMesh
	cm.size = Vector3(sw * 0.72, 0.42, sd * 0.72)
	cap.position = Vector3(0.0, levels + 0.22, 0.0)
	var cone := spire.mesh as CylinderMesh
	var sp_h: float = 3.5 + float(seed_value % 5) * 2.6
	cone.bottom_radius = maxf(0.5, sw * 0.18)
	cone.height = sp_h
	spire.position = Vector3(0.0, levels + 0.42 + sp_h * 0.5, 0.0)
	beacon.position = Vector3(0.0, levels + 0.42 + sp_h + 0.3, 0.0)
	# Only every fourth roof carries a real light; the rest use emissive crown
	# geometry. This keeps the dense Art Deco skyline performant.
	beacon.visible = seed_value % 4 == 0
	beacon.light_energy = 0.35 + 0.35 * sin(float(seed_value) * 2.0)


func pop_burst(at: Vector3, color: Color) -> void:
	if _bursts.is_empty():
		return
	var b: GPUParticles3D = _bursts[_burst_i]
	_burst_i = (_burst_i + 1) % _bursts.size()
	b.global_position = at
	var mat: StandardMaterial3D = b.material_override
	mat.albedo_color = Color(color.r * 4.5, color.g * 4.5, color.b * 4.5, 1.0)
	b.restart()


## Adrenaline SMASH: chunky glowing debris + an expanding shock ring on the deck.
func pop_shatter(at: Vector3, color: Color, size_hint: float = 1.0) -> void:
	if _shatters.is_empty():
		return
	var sh: GPUParticles3D = _shatters[_shatter_i]
	var ring: MeshInstance3D = _shock_rings[_shatter_i]
	_shock_t[_shatter_i] = 0.0
	_shatter_i = (_shatter_i + 1) % _shatters.size()
	sh.global_position = at
	sh.amount_ratio = clampf(0.5 + size_hint * 0.5, 0.4, 1.0)
	var mat: StandardMaterial3D = sh.material_override
	mat.albedo_color = Color(color.r * 4.0, color.g * 4.0, color.b * 4.0, 1.0)
	sh.restart()
	ring.global_position = Vector3(at.x, 0.35, at.z)
	ring.scale = Vector3.ONE * 0.6
	ring.visible = true
	var rm: ShaderMaterial = ring.material_override
	rm.set_shader_parameter("orb_color", color.lightened(0.3))
	rm.set_shader_parameter("energy", 5.0)


func _tick_shock_rings(delta: float) -> void:
	for i in _shock_rings.size():
		if _shock_t[i] < 0.0:
			continue
		_shock_t[i] += delta
		var k: float = _shock_t[i] / 0.55
		var ring: MeshInstance3D = _shock_rings[i]
		if k >= 1.0:
			ring.visible = false
			_shock_t[i] = -1.0
			continue
		var e: float = 1.0 - (1.0 - k) * (1.0 - k)   # ease-out expansion
		ring.scale = Vector3.ONE * lerpf(0.6, 9.0, e)
		var rm: ShaderMaterial = ring.material_override
		rm.set_shader_parameter("energy", 5.0 * (1.0 - k))


# ---------------------------------------------------------------- biomes

func apply_biome(id: int) -> void:
	biome_id = id
	var d := Biomes.visual(id)
	var obst: Dictionary = d["obst"]
	_set_neon("block", obst["block"])
	_set_neon("low", obst["low"])
	_set_neon("hang", obst["hang"])
	_set_neon("mover", obst["mover"])
	_set_neon("spin", obst["spin"])
	_set_neon("hunter", obst["hunter"])
	var lc: Color = obst["laser"]
	var lm: StandardMaterial3D = _mats["laser"]
	lm.albedo_color = Color(lc.r * 5.5, lc.g * 5.5, lc.b * 5.5, 1.0)
	if obst.has("obelisk"):
		var om: StandardMaterial3D = _mats["obelisk"]
		om.albedo_color = obst["obelisk"]
	if obst.has("dustwall"):
		var dw: StandardMaterial3D = _mats["dustwall"]
		dw.albedo_color = obst["dustwall"]
	if obst.has("cab"):
		var cab: StandardMaterial3D = _mats["cab"]
		cab.albedo_color = obst["cab"]
	if obst.has("cab_trim"):
		var ct: StandardMaterial3D = _mats["cab_trim"]
		ct.albedo_color = obst["cab_trim"]
		ct.emission = obst["cab_trim"]

	for key in ["rail", "post", "arch", "tower"]:
		var e: Dictionary = d[key]
		var m: StandardMaterial3D = _mats[key]
		m.albedo_color = e["albedo"]
		m.emission = e["emit"]
		m.emission_energy_multiplier = e["energy"]

	var g: Dictionary = d["grid"]
	_floor_mat.set_shader_parameter("base_color", g["base"])
	_floor_mat.set_shader_parameter("grid_color", g["grid"])
	_floor_mat.set_shader_parameter("edge_color", g["edge"])
	_floor_mat.set_shader_parameter("cell_size", g["cell"])
	_floor_mat.set_shader_parameter("track_half", TRACK_HALF + 0.4)
	var road: Dictionary = d.get("road", {})
	_floor_mat.set_shader_parameter("street_mode", float(road.get("street_mode", 0.0)))
	_floor_mat.set_shader_parameter("asphalt_color", road.get("asphalt", Color(0.02, 0.02, 0.05)))
	_floor_mat.set_shader_parameter("curb_color", road.get("curb", Color(0.05, 0.03, 0.12)))
	_floor_mat.set_shader_parameter("line_color", road.get("line", Color(0.75, 0.85, 1.0)))
	_floor_mat.set_shader_parameter("center_color", road.get("center", Color(1.0, 0.45, 0.7)))
	_floor_mat.set_shader_parameter("wetness", float(road.get("wetness", 0.0)))
	_floor_mat.set_shader_parameter("night_mix", 0.0)

	var bd: Dictionary = d["building"]
	_building_style = int(bd["style"])
	for i in _building_mats.size():
		var bm: ShaderMaterial = _building_mats[i]
		bm.set_shader_parameter("base_color", bd["base"])
		bm.set_shader_parameter("window_color", bd["window"])
		bm.set_shader_parameter("accent_color", bd["accent"])
		bm.set_shader_parameter("window_density", bd["density"])
		bm.set_shader_parameter("energy", bd["energy"])
		bm.set_shader_parameter("style", _building_style)
		bm.set_shader_parameter("night_mix", 0.0)

	_deco_crown_mat.albedo_color = Color(0.025, 0.03, 0.07) if _building_style == 4 else Color(0.018, 0.023, 0.055)
	_deco_crown_mat.emission = Color(0.18, 0.08, 0.25) if _building_style == 4 else Color(0.13, 0.07, 0.21)
	_deco_trim_mat.albedo_color = Color(0.42, 0.18, 0.12) if _building_style == 4 else Color(0.48, 0.30, 0.13)
	_deco_trim_mat.emission = Color(0.82, 0.48, 0.18) if _building_style == 4 else Color(0.72, 0.46, 0.15)
	_moon.visible = biome_id == Biomes.NOCTURNE
	_moon_halo.visible = biome_id == Biomes.NOCTURNE
	_rain.visible = biome_id == Biomes.NOCTURNE
	_rain.emitting = biome_id == Biomes.NOCTURNE and Persist.dust

	var dc: Color = d["dust"]
	var dpm: ParticleProcessMaterial = _dust.process_material
	dpm.color_ramp = V.gradient_tex(Color(dc.r, dc.g, dc.b, 0.9), Color(1.0 - dc.b * 0.4, 0.35, 0.85, 0.0))
	var dm: StandardMaterial3D = _dust.material_override
	dm.albedo_color = Color(dc.r * 1.5, dc.g * 1.5, dc.b * 1.5, 1.0)

	if bridge != null and bridge.active:
		bridge.place(bridge.start_z, bridge.kind, d)
	_respawn_decor()
	for car in _noir_cars:
		car.recycle()
	_noir_car_t = 0.0


func _set_neon(key: String, c: Color) -> void:
	var m: ShaderMaterial = _mats[key]
	m.set_shader_parameter("neon_color", c)


## Pulse every building's window glow (called on beat by main.gd).
func set_building_pulse(p: float) -> void:
	var bd: Dictionary = Biomes.visual(biome_id)["building"]
	var e: float = bd["energy"]
	for m in _building_mats:
		m.set_shader_parameter("energy", e * (1.0 + 0.35 * p))


func _respawn_decor() -> void:
	for b in _buildings:
		b.position.y = -500.0
	for t in _towers:
		t.position.y = -500.0
	for p in _posts:
		p.position.y = -500.0
	for a in _arches:
		a.position.y = -500.0
	var z := -60.0
	if player != null:
		z = player.global_position.z
	next_z = z - CHUNK
	var saved := chunk_index
	var i := 0
	while i < AHEAD + 2:
		_decorate(z - float(i) * CHUNK)
		i += 1
	chunk_index = saved


# ------------------------------------------------------------------ rail API

func on_bridge(z: float) -> bool:
	return bridge != null and bridge.contains(z)


## True when the flat highway hands the ship over to a structure at this z.
func rail_entry(z: float) -> bool:
	return bridge != null and bridge.active and z <= bridge.start_z and z > bridge.start_z - 6.0


func rail_frame(s: float) -> Transform3D:
	return bridge.frame_at_progress(s)


func rail_length() -> float:
	return bridge.length if bridge != null else 0.0


# --------------------------------------------------------------------- update

func _process(delta: float) -> void:
	if player == null:
		return
	var pz: float = player.global_position.z
	_floor.global_position = Vector3(0.0, 0.0, pz - 350.0)
	for r in _rails:
		r.global_position.z = pz - 380.0
	_dust.global_position = Vector3(0.0, 7.0, pz - 80.0)
	_rain.global_position = Vector3(0.0, 22.0, pz - 72.0)
	_tick_nocturne_scenery(delta, pz)

	_hit_flash = maxf(0.0, _hit_flash - delta * 2.2)
	_tick_shock_rings(delta)
	_floor_mat.set_shader_parameter("focus_z", pz)
	_floor_mat.set_shader_parameter("hit_flash", _hit_flash)
	if game != null:
		_floor_mat.set_shader_parameter("boost", game.boost_visual)
		_floor_mat.set_shader_parameter("beat_pulse", game.beat_pulse)
	_update_music_layer_visuals(delta)

	while next_z > pz - CHUNK * AHEAD:
		_spawn_chunk()

	_maybe_bridge(pz)
	_schedule(pz)

	var limit := pz + CLEANUP_BEHIND
	for o in _obstacles:
		if o.live and o.position.z > limit:
			o.recycle()
	for p in _pickups:
		if p.live and p.position.z > limit:
			p.recycle()
	var gi := gates.size() - 1
	while gi >= 0:
		if gates[gi]["z"] > pz + 12.0:
			gates.remove_at(gi)
		gi -= 1


func flash_floor() -> void:
	_hit_flash = 1.0


## Maps the dominant musical layer to a visual palette. The road/grid takes
## bass, drones, melody and percussion independently rather than merely
## flashing every beat.
func _update_music_layer_visuals(_delta: float) -> void:
	var c := Color(0.38, 0.75, 1.0)
	match Sound.dominant_layer:
		"BASS": c = Color(1.0, 0.32, 0.22)
		"DRONE": c = Color(0.38, 0.34, 0.82)
		"MELODY": c = Color(0.40, 0.88, 1.0)
		"PERCUSSION": c = Color(1.0, 0.82, 0.38)
		"SILENT": c = Color(0.18, 0.2, 0.3)
	if biome_id == Biomes.NOCTURNE:
		c = c.lerp(Color(0.86, 0.34, 0.48), 0.30 * (1.0 - _noir_atmosphere))
	_floor_mat.set_shader_parameter("layer_color", c)
	_floor_mat.set_shader_parameter("bass_pulse", Sound.bass_pulse)
	_floor_mat.set_shader_parameter("drone_level", Sound.drone)
	_floor_mat.set_shader_parameter("melody_level", Sound.melody)
	_floor_mat.set_shader_parameter("percussion_level", Sound.percussion)
	_floor_mat.set_shader_parameter("transient_level", Sound.transient)
	# Crown lights breathe with the low drone but flash brighter on percussion.
	if _building_style == 4:
		for b in _buildings:
			var crown := b.get_node_or_null("DecoCrown") as Node3D
			if crown != null and crown.visible:
				var light := crown.get_node_or_null("CrownLight") as OmniLight3D
				if light != null and light.visible:
					light.light_energy = 0.16 + Sound.drone * 0.48 + Sound.transient * Sound.percussion * 0.65


func set_dust(on: bool) -> void:
	if _dust != null:
		_dust.emitting = on
		_dust.visible = on
	if _rain != null:
		_rain.emitting = on and biome_id == Biomes.NOCTURNE
		_rain.visible = on and biome_id == Biomes.NOCTURNE


## ---------------------------------------------------------------- Nocturne scenery
## The fourth map owns a separate visual layer: a moon locked to the skyline,
## safe opposing traffic, and a song-driven red-dusk -> indigo-night grade.

func set_nocturne_atmosphere(mix_amount: float) -> void:
	_noir_atmosphere = clampf(mix_amount, 0.0, 1.0)
	_floor_mat.set_shader_parameter("night_mix", _noir_atmosphere)
	for m in _building_mats:
		m.set_shader_parameter("night_mix", _noir_atmosphere)
	if _moon_mat != null:
		_moon_mat.emission_energy_multiplier = lerpf(0.75, 1.7, _noir_atmosphere)
	if _moon_halo_mat != null:
		_moon_halo_mat.albedo_color = Color(0.48, 0.10, 0.26, 0.12 + _noir_atmosphere * 0.13)


func _tick_nocturne_scenery(delta: float, pz: float) -> void:
	var nocturne := biome_id == Biomes.NOCTURNE
	if _moon != null:
		_moon.visible = nocturne
		_moon_halo.visible = nocturne
	if not nocturne:
		for car in _noir_cars:
			if car.active:
				car.recycle()
		return
	# Keep the full moon permanently behind the Art Deco horizon. It tracks the
	# player only in Z, like a matte-painted skyline element.
	# Matches the sky shader's moon direction (-0.28, 0.18, -1) so the 3D
	# disc and atmospheric halo read as a single oversized full moon.
	_moon.global_position = Vector3(-82.0, 54.0, pz - 300.0)
	_moon_halo.global_position = _moon.global_position
	_rain.amount_ratio = lerpf(0.36, 0.82, _noir_atmosphere)
	_noir_car_t -= delta
	if _noir_car_t <= 0.0:
		for car in _noir_cars:
			if not car.active:
				var side := -1.0 if randf() < 0.5 else 1.0
				# The car stays in a far outer lane so it remains atmospheric traffic,
				# not a surprise gameplay hazard.
				car.spawn(Vector3(side * 10.8, 0.55, pz - randf_range(100.0, 175.0)), side * 10.8, player)
				_noir_car_t = randf_range(5.5, 10.5)
				break


func reset() -> void:
	for o in _obstacles:
		o.recycle()
	for p in _pickups:
		p.recycle()
	for car in _noir_cars:
		car.recycle()
	_noir_car_t = 0.0
	gates.clear()
	_next_beat = 0
	_phrase_i = 0
	_last_bridge_dist = 0.0
	_bridge_interval = 700.0
	notes_live.clear()
	_pending_structure_z = -1e9
	bridge.clear()
	next_z = -70.0
	chunk_index = 0
	if player != null:
		next_z = player.global_position.z - CHUNK
	_respawn_decor()


# ------------------------------------------------------------------- bridge

func _maybe_bridge(pz: float) -> void:
	var dist: float = 0.0 if game == null else game.distance
	if bridge.active:
		if pz < bridge.end_z - 120.0:
			bridge.clear()
		return
	var interval: float = 420.0 if demo_mode else _bridge_interval
	# Reserve the corridor ~60 m of travel before we place the structure so
	# the scheduler never fills it in the meantime.
	if dist - _last_bridge_dist > interval - 60.0:
		_pending_structure_z = pz - 260.0
	else:
		_pending_structure_z = -1e9
	if dist - _last_bridge_dist > interval:
		var k: int = _structure_i % 4
		_structure_i += 1
		var z0: float = pz - 260.0
		bridge.place(z0, k, Biomes.visual(biome_id))
		# ---- No double-spawn: the structure owns its Z corridor. Anything the
		# beat scheduler already dropped inside it (hazards, notes, power-ups)
		# is recycled, and the scheduler is bumped past the exit so the next
		# phrase begins on clean road.
		_clear_hazards_in(bridge.start_z + 40.0, bridge.end_z - 40.0)
		_skip_scheduler_past(bridge.end_z - 40.0, pz)
		_place_bridge_pickups()
		# Retire any already-streamed buildings that the new structure now runs
		# through, and decorate the empty band so the corridor reads as clear.
		clear_decor_around_structure()
		_backfill_structure_corridor()
		_last_bridge_dist = dist
		_bridge_interval = rng.randf_range(900.0, 1300.0)
		_pending_structure_z = -1e9


## Recycle every live hazard / pickup / gate whose Z lies inside [z_lo, z_hi].
func _clear_hazards_in(z_hi: float, z_lo: float) -> void:
	for o in _obstacles:
		if o.live and o.position.z <= z_hi and o.position.z >= z_lo:
			o.recycle()
	for p in _pickups:
		if p.live and p.position.z <= z_hi and p.position.z >= z_lo:
			p.recycle()
	var i := gates.size() - 1
	while i >= 0:
		var gz: float = float(gates[i]["z"])
		if gz <= z_hi and gz >= z_lo:
			gates.remove_at(i)
		i -= 1
	i = notes_live.size() - 1
	while i >= 0:
		var n = notes_live[i]
		if not n.live or (n.position.z <= z_hi and n.position.z >= z_lo):
			if n.live:
				n.recycle()
			notes_live.remove_at(i)
		i -= 1


## Advance the beat scheduler so its next gate lands beyond `z_exit`.
func _skip_scheduler_past(z_exit: float, pz: float) -> void:
	var now: float = Sound.now()
	var spd: float = 30.0 if game == null else maxf(game.base_speed(), 8.0)
	var t_exit: float = now + (pz - z_exit) / spd
	var k := 0
	while Sound.time_of_beat(_next_beat) < t_exit and k < 400:
		_next_beat += 1
		k += 1
	# Land on a downbeat for a clean musical restart.
	while _next_beat % 4 != 0:
		_next_beat += 1


## The music's DOMINANT beat subdivision right now, in beats:
##   0.5  = 8th notes  (busy hats / high energy)
##   1.0  = quarter notes (normal groove)
##   2.0  = half notes (breakdown / quiet)
func _dominant_subdivision() -> float:
	if Sound.breakdown or Sound.energy < 0.2:
		return 2.0
	if Sound.highs > 0.55 or Sound.drop_active:
		return 0.5
	return 1.0


## XP crystals along a structure are laid on the music's dominant beat grid, so
## collecting them plays the groove back: one crystal per beat (or per 8th when
## the track is busy, per half-bar when it is quiet). The XP RINGS always sit on
## the DOWNBEAT of a bar so the big pickups land with the kick.
func _place_bridge_pickups() -> void:
	var now: float = Sound.now()
	var spd: float = 30.0 if game == null else maxf(game.base_speed(), 8.0)
	var period: float = Sound.beat_period
	var sub: float = _dominant_subdivision()
	# Distance the ship covers per subdivision at current speed.
	var step: float = maxf(spd * period * sub, 5.0)
	var L: float = bridge.length
	# Time at which the ship will reach the structure entry.
	var pz: float = player.global_position.z if player != null else 0.0
	var t_entry: float = now + (pz - bridge.start_z) / spd
	# First beat index at or after entry, snapped to the subdivision grid.
	var b_entry: float = (t_entry - Sound.time_of_beat(0)) / period
	var b: float = ceilf(b_entry / sub) * sub
	# Walk the beat grid across the structure.
	var s_along := (b - b_entry) * period * spd
	var rings_placed := 0
	var margin := 12.0
	while s_along < L - margin:
		if s_along > margin:
			var u: float = s_along / L
			var f: Transform3D = bridge.frame_at(u)
			var x: float = bridge.lane_x(u)
			var on_downbeat: bool = fmod(b, 4.0) < 0.001
			if on_downbeat and rings_placed < 3 and u > 0.2 and u < 0.85:
				_ring_at(f.origin + f.basis.x * x + f.basis.y * 1.4)
				rings_placed += 1
			else:
				_xp_at(f.origin + f.basis.x * x + f.basis.y * 1.25)
		b += sub
		s_along += step
	# Guarantee at least one ring even on a very short structure.
	if rings_placed == 0:
		var f: Transform3D = bridge.frame_at(0.5)
		_ring_at(f.origin + f.basis.x * bridge.lane_x(0.5) + f.basis.y * 1.4)


func _xp_at(p: Vector3) -> void:
	var pk = _free_pickup()
	pk.game = game
	pk.player = player
	pk.setup(PickupScript.Kind.XP, p)


func _ring_at(p: Vector3) -> void:
	var pk = _free_pickup()
	pk.game = game
	pk.player = player
	pk.setup(PickupScript.Kind.RING, p)


# ------------------------------------------------------------ beat scheduler

func _schedule(pz: float) -> void:
	var now: float = Sound.now()
	var speed_now: float = 30.0 if game == null else maxf(game.base_speed(), 8.0)
	var floor_beat: int = Sound.next_beat_index() + 2
	if _next_beat < floor_beat:
		_next_beat = floor_beat
	var guard := 0
	while Sound.time_of_beat(_next_beat) < now + HORIZON_T and guard < 8:
		_schedule_phrase(pz, now, speed_now)
		guard += 1


func _z_at_beat(k: int, pz: float, now: float, speed_now: float) -> float:
	return pz - speed_now * (Sound.time_of_beat(k) - now)


func _schedule_phrase(pz: float, now: float, speed_now: float) -> void:
	var diff: float = 0.0 if game == null else game.difficulty()
	var period: float = Sound.beat_period
	var per_beat := speed_now * period
	var min_gate: float = lerpf(24.0, 18.0, diff)
	if rhythm_mode:
		min_gate = 9.0
	var bpg := int(ceilf(min_gate / maxf(per_beat, 0.5)))
	if bpg == 3:
		bpg = 4
	bpg = clampi(bpg, 1, 8)
	var slots := 4 if diff > 0.3 else 3
	var zs: Array = []
	for i in slots:
		zs.append(_z_at_beat(_next_beat + i * bpg, pz, now, speed_now))
	var gap := per_beat * float(bpg)
	_next_beat += slots * bpg + 2 * bpg
	_phrase_i += 1

	# Never drop hazards on a sky structure - it is pure reward space. Test
	# EVERY gate, not just the ends, so a phrase can't straddle the entry ramp.
	if bridge.active:
		for zz in zs:
			if bridge.blocks(float(zz)):
				return
	# Also refuse a phrase whose gates would land inside the NEXT structure's
	# reserved corridor (it is placed ~260 m ahead of the ship, so anything
	# scheduled beyond that horizon during the placement frame would collide).
	if _pending_structure_z > -1e8:
		for zz in zs:
			if float(zz) <= _pending_structure_z + 40.0 and float(zz) >= _pending_structure_z - 420.0:
				return
	if demo_mode:
		_pattern_flow(zs, gap)
		return
	if rhythm_mode:
		_rhythm_phrase(pz, now, speed_now, bpg, slots)
		return
	if _phrase_i <= 2:
		_pattern_intro(zs, gap)
		return
	if _phrase_i % REST_EVERY == 0:
		_pattern_breather(zs, gap, diff)
		return

	var pool := ["slalom", "hurdles", "ducks", "wall_gap", "lasers", "beat_wave"]
	if diff > 0.15:
		pool.append_array(["rhythm", "pistons", "slalom", "lasers", "beat_wave"])
	if diff > 0.32:
		pool.append_array(["movers", "corridor", "pendulums", "rhythm", "wave"])
	if diff > 0.5:
		pool.append_array(["spinner", "scatter", "rotors", "hunters", "pistons", "wave"])
	if diff > 0.72:
		pool.append_array(["gauntlet", "mixed", "hunters", "pendulums", "wave"])
	if biome_id == Biomes.NOCTURNE:
		pool.append_array(["noir_gate", "shadow_bloom", "noir_gate", "deco_run", "cabaret"])

	match pool[rng.randi_range(0, pool.size() - 1)]:
		"slalom": _pattern_slalom(zs, gap)
		"hurdles": _pattern_hurdles(zs, gap)
		"ducks": _pattern_ducks(zs, gap)
		"wall_gap": _pattern_wall_gap(zs, gap)
		"rhythm": _pattern_rhythm(zs, gap)
		"movers": _pattern_movers(zs, gap)
		"corridor": _pattern_corridor(zs, gap)
		"spinner": _pattern_spinner(zs, gap)
		"scatter": _pattern_scatter(zs, gap)
		"gauntlet": _pattern_gauntlet(zs, gap)
		"lasers": _pattern_lasers(zs, gap)
		"pistons": _pattern_pistons(zs, gap)
		"rotors": _pattern_rotors(zs, gap)
		"hunters": _pattern_hunters(zs, gap)
		"pendulums": _pattern_pendulums(zs, gap)
		"mixed": _pattern_mixed(zs, gap)
		"beat_wave": _pattern_beat_wave(zs, gap)
		"wave": _pattern_wave(zs, gap)
		"noir_gate": _pattern_noir_gate(zs, gap)
		"shadow_bloom": _pattern_shadow_bloom(zs, gap)
		"deco_run": _pattern_deco_run(zs, gap)
		"cabaret": _pattern_cabaret(zs, gap)
		_: _pattern_slalom(zs, gap)

	for z in zs:
		gates.append({"z": z, "done": false})

	if _phrase_i % 5 == 3:
		var roll := rng.randf()
		var kind: int = PickupScript.Kind.SHIELD
		if roll > 0.66:
			kind = PickupScript.Kind.OVERDRIVE
		elif roll > 0.33:
			kind = PickupScript.Kind.MAGNET
		_power(kind, _lane(rng.randi_range(-1, 1)), zs[zs.size() - 1] - gap * 1.4)


func _spawn_chunk() -> void:
	var z0 := next_z
	next_z -= CHUNK
	chunk_index += 1
	_decorate(z0)


# ------------------------------------------------------------------- spawning

func _free_obstacle():
	for o in _obstacles:
		if not o.live and not o.smashing:
			o.game = game
			o.player = player
			return o
	var n = ObstacleScript.new()
	add_child(n)
	n.game = game
	n.player = player
	_obstacles.append(n)
	return n


func _free_pickup():
	for p in _pickups:
		if not p.live:
			return p
	var n = PickupScript.new()
	add_child(n)
	_pickups.append(n)
	return n


func _beat_of_z(z: float) -> int:
	# Which beat index a gate at z corresponds to (for phase-correct hazards).
	var now: float = Sound.now()
	var speed_now: float = 30.0 if game == null else maxf(game.base_speed(), 8.0)
	var pz: float = player.global_position.z if player != null else 0.0
	var t := now + (pz - z) / speed_now
	return int(roundf((t - Sound.time_of_beat(0)) / Sound.beat_period))


func _block(x: float, z: float, w: float = 3.0, h: float = 4.4) -> void:
	var o = _free_obstacle()
	o.setup(ObstacleScript.Kind.BLOCK, Vector3(x, h * 0.5, z), Vector3(w, h, 1.8), _mats["block"])


func _low(x: float, z: float, w: float = 7.0) -> void:
	var o = _free_obstacle()
	o.setup(ObstacleScript.Kind.LOW, Vector3(x, 0.66, z), Vector3(w, 1.32, 1.8), _mats["low"])


func _hang(x: float, z: float, w: float = 8.0) -> void:
	var o = _free_obstacle()
	o.setup(ObstacleScript.Kind.HANG, Vector3(x, 2.62, z), Vector3(w, 2.9, 1.8), _mats["hang"])


func _mover(x: float, z: float, rangex: float, speed: float) -> void:
	var o = _free_obstacle()
	o.setup(ObstacleScript.Kind.MOVER, Vector3(x, 2.2, z), Vector3(2.6, 4.4, 1.8), _mats["mover"])
	o.move_range = rangex
	o.move_speed = speed


func _spinner(z: float, speed: float) -> void:
	var o = _free_obstacle()
	o.setup(ObstacleScript.Kind.SPIN, Vector3(0.0, 2.6, z), Vector3(17.0, 0.9, 1.5), _mats["spin"])
	o.spin_speed = speed


func _laser(x: float, z: float, w: float, low: bool) -> void:
	var o = _free_obstacle()
	var k := _beat_of_z(z)
	o.setup_laser(Vector3(x, 0.0, z), w, low, _mats["low"] if low else _mats["hang"], _mats["laser"], _mats["laser_idle"], float(1 - (k % 2)))


func _piston(x: float, z: float, safe_on_beat: bool) -> void:
	var o = _free_obstacle()
	var k := _beat_of_z(z)
	var ph := float(k % 2) if safe_on_beat else float((k + 1) % 2)
	o.setup_piston(Vector3(x, 0.0, z), _mats["spin"], _mats["arch"], ph)


func _rotor(x: float, z: float) -> void:
	var o = _free_obstacle()
	o.setup_rotor(Vector3(x, 0.0, z), _mats["spin"], _mats["arch"], 1.0 if rng.randf() < 0.5 else -1.0)


func _hunter(x: float, z: float) -> void:
	var o = _free_obstacle()
	o.setup_hunter(Vector3(x, 0.0, z), _mats["hunter"], _mats["mover"])


func _pendulum(x: float, z: float) -> void:
	var o = _free_obstacle()
	var k := _beat_of_z(z)
	o.setup_pendulum(Vector3(x, 0.0, z), _mats["arch"], _mats["spin"], float(k % 2))


func _obelisk(x: float, z: float) -> void:
	var o = _free_obstacle()
	var k := _beat_of_z(z)
	o.setup_obelisk(Vector3(x, 0.0, z), _mats["obelisk"], _mats["deco_edge"], float(k % 2))


func _dustwall(x: float, z: float, width: float = 9.0) -> void:
	var o = _free_obstacle()
	var k := _beat_of_z(z)
	o.setup_dustwall(Vector3(x, 0.0, z), width, _mats["dustwall"], _mats["deco_edge"], float(k % 2))


func _cab(x: float, z: float) -> void:
	var o = _free_obstacle()
	var k := _beat_of_z(z)
	o.setup_cab(Vector3(x, 0.0, z), _mats["cab"], _mats["cab_trim"], float(k % 2))


func _orb(x: float, y: float, z: float) -> void:
	var p = _free_pickup()
	p.game = game
	p.player = player
	p.setup(PickupScript.Kind.ORB, Vector3(x, y, z))


func _xp(x: float, y: float, z: float) -> void:
	var p = _free_pickup()
	p.game = game
	p.player = player
	p.setup(PickupScript.Kind.XP, Vector3(x, y, z))


func _ring(x: float, y: float, z: float) -> void:
	var p = _free_pickup()
	p.game = game
	p.player = player
	p.setup(PickupScript.Kind.RING, Vector3(x, y, z))


func _orb_line(x: float, z: float, count: int, spacing: float, arc: float = 0.0, y0: float = 1.15) -> void:
	for i in count:
		var k: float = 0.0 if count <= 1 else float(i) / float(count - 1)
		_orb(x, y0 + sin(k * PI) * arc, z - float(i) * spacing)


func _power(kind: int, x: float, z: float) -> void:
	var p = _free_pickup()
	p.game = game
	p.player = player
	p.setup(kind, Vector3(x, 1.5, z))


func _lane(i: int) -> float:
	return clampf(float(i) * 4.2, -TRACK_HALF + 2.4, TRACK_HALF - 2.4)


# ------------------------------------------------------------------- patterns
# Every pattern receives the gate positions (zs, nearest first) and the gap
# between gates - both already phrased on the beat.

func _pattern_intro(zs: Array, gap: float) -> void:
	_orb_line(0.0, zs[0], 6, 3.0)
	if zs.size() > 1:
		_low(0.0, zs[1], 8.0)
		_orb_line(0.0, zs[1] - 3.0, 5, 2.6, 1.9)


func _pattern_flow(zs: Array, gap: float) -> void:
	var x := _lane(rng.randi_range(-2, 2))
	_orb_line(x, zs[0], 9, gap * 0.25, rng.randf_range(0.0, 2.0))
	if rng.randf() < 0.5 and zs.size() > 2:
		_orb_line(-x, zs[2], 7, gap * 0.25, rng.randf_range(0.0, 1.6))


func _pattern_slalom(zs: Array, gap: float) -> void:
	var side: float = 1.0 if rng.randf() < 0.5 else -1.0
	for z in zs:
		var x := side * rng.randf_range(2.0, 6.5)
		_block(x, z, rng.randf_range(2.8, 4.0))
		_orb(-x * 0.85, 1.2, z)
		side = -side


func _pattern_hurdles(zs: Array, gap: float) -> void:
	# Low hurdles you can jump; the walk-through notch drifts gate to gate the
	# same way the wall-gap opening does, so it never teleports across the road.
	var notch_half := 3.0
	var lim: float = TRACK_HALF - notch_half - 1.0
	var notch: float = 0.0
	if player != null and not player.on_rail:
		notch = clampf(player.lateral, -lim, lim)
	var dir: float = 1.0 if rng.randf() < 0.5 else -1.0
	for i in zs.size():
		var z: float = zs[i]
		if i > 0:
			var max_shift := _reachable_shift(gap)
			if rng.randf() < 0.3:
				dir = -dir
			var prev_n := notch
			notch = clampf(notch + dir * rng.randf_range(max_shift * 0.3, max_shift), -lim, lim)
			notch = clampf(notch, prev_n - max_shift, prev_n + max_shift)
			if absf(notch) >= lim - 0.01:
				dir = -dir
		var lw: float = maxf(0.0, notch - notch_half + TRACK_HALF)
		var rw: float = maxf(0.0, TRACK_HALF - (notch + notch_half))
		if lw > 1.0:
			_low(-TRACK_HALF + lw * 0.5, z, lw)
		if rw > 1.0:
			_low(TRACK_HALF - rw * 0.5, z, rw)
		_orb_line(notch, z + 4.0, 4, 2.4, 2.3)


func _pattern_ducks(zs: Array, gap: float) -> void:
	for z in zs:
		var x: float = rng.randf_range(-2.5, 2.5)
		_hang(x, z, rng.randf_range(9.0, 15.0))
		_orb_line(x, z + 3.0, 4, 2.4, 0.0, 0.75)


## How far the ship can realistically strafe between two gates `gap` metres apart.
## Uses the ship's real strafe speed and the current travel speed, with a safety
## factor so the required move is comfortably inside what the player can do.
func _reachable_shift(gap: float) -> float:
	var spd: float = 30.0 if game == null else maxf(game.travel_speed(), 8.0)
	var t: float = gap / spd                  # seconds between the gates
	var strafe := 21.0                        # player STRAFE_MAX (m/s)
	return clampf(t * strafe * 0.62, 3.0, 10.0)


## Corridor width grows with speed so fast sections stay fair.
func _corridor_width() -> float:
	var spd: float = 30.0 if game == null else game.travel_speed()
	var k: float = clampf((spd - 26.0) / 30.0, 0.0, 1.0)
	return lerpf(MIN_CORRIDOR + 1.2, MIN_CORRIDOR + 4.4, k)


## WALL WAVE: full-width red walls with one opening each. The opening DRIFTS
## smoothly from gate to gate — the shift between consecutive openings is
## capped at what the ship can actually strafe in that time — so the wave reads
## as a lane you steer along, not a random hole hunt.
func _pattern_wall_gap(zs: Array, gap: float) -> void:
	var corridor := _corridor_width()
	var half_gap: float = corridor * 0.5
	var lim: float = TRACK_HALF - half_gap - 0.6
	# Start the opening near the ship's current lane so the first wall is fair.
	var gx: float = 0.0
	if player != null:
		gx = clampf(player.lateral if player.on_rail == false else 0.0, -lim, lim)
	var dir: float = 1.0 if rng.randf() < 0.5 else -1.0
	for i in zs.size():
		var z: float = zs[i]
		if i > 0:
			var max_shift := _reachable_shift(gap)
			# Wander in one direction, occasionally reversing, never more than
			# the reachable shift per gate.
			if rng.randf() < 0.3:
				dir = -dir
			var prev_gx := gx
			gx = clampf(gx + dir * rng.randf_range(max_shift * 0.35, max_shift), -lim, lim)
			# Hard guarantee: the opening never moves further than the ship can
			# strafe in the gate time, even after edge clamping.
			gx = clampf(gx, prev_gx - max_shift, prev_gx + max_shift)
			# If we clamped against the edge, bounce back inward next time.
			if absf(gx) >= lim - 0.01:
				dir = -dir
		var left_w: float = maxf(0.0, gx - half_gap + TRACK_HALF)
		var right_w: float = maxf(0.0, TRACK_HALF - (gx + half_gap))
		if left_w > 0.8:
			_block(-TRACK_HALF + left_w * 0.5, z, left_w)
		if right_w > 0.8:
			_block(TRACK_HALF - right_w * 0.5, z, right_w)
		# A trail of orbs marks the opening so it is readable from far away.
		_orb(gx, 1.2, z + 4.0)
		_orb(gx, 1.2, z)
		_orb(gx, 1.2, z - 3.5)


func _pattern_rhythm(zs: Array, gap: float) -> void:
	for i in zs.size():
		var z: float = zs[i]
		if i % 2 == 0:
			_low(0.0, z, 11.0)
			_orb_line(0.0, z + 3.4, 4, 2.4, 2.2)
		else:
			_hang(0.0, z, 15.0)
			_orb_line(0.0, z + 3.0, 4, 2.4, 0.0, 0.7)


func _pattern_movers(zs: Array, gap: float) -> void:
	for z in zs:
		_mover(0.0, z, rng.randf_range(4.5, 7.5), rng.randf_range(1.0, 1.8))
		_orb(rng.randf_range(-8.0, 8.0), 1.2, z - gap * 0.4)


func _pattern_corridor(zs: Array, gap: float) -> void:
	# A long red wall hugging ONE side. The open lane it leaves is always at
	# least 60% of the road (so it reads as "hug the other side", not "thread a
	# needle"), and a line of orbs shows the safe lane from far away.
	var side: float = 1.0 if rng.randf() < 0.5 else -1.0
	var open_w: float = maxf(_corridor_width() * 1.6, TRACK_HALF * 1.2)
	var wall_w: float = clampf(TRACK_HALF * 2.0 - open_w, 4.0, 9.0)
	var wall_x: float = side * (TRACK_HALF - wall_w * 0.5)
	var z0: float = zs[0]
	var z1: float = zs[zs.size() - 1]
	var length: float = z0 - z1 + 6.0
	var o = _free_obstacle()
	o.setup(ObstacleScript.Kind.BLOCK, Vector3(wall_x, 2.2, (z0 + z1) * 0.5), Vector3(wall_w, 4.4, length), _mats["block"])
	_orb_line(-side * (TRACK_HALF - wall_w - open_w * 0.5), z0 + 2.0, 9, length / 9.0)


func _pattern_spinner(zs: Array, gap: float) -> void:
	_spinner(zs[0], rng.randf_range(1.2, 2.0) * (1.0 if rng.randf() < 0.5 else -1.0))
	if zs.size() > 1:
		_orb_line(_lane(rng.randi_range(-1, 1)), zs[1], 6, gap * 0.22, 1.4)
	if zs.size() > 2:
		_spinner(zs[2], rng.randf_range(1.4, 2.2))


func _pattern_scatter(zs: Array, gap: float) -> void:
	# Scattered single blocks, ONE per gate, spread across lanes. No Z jitter -
	# every hazard sits exactly on its beat so phrases never overlap.
	var last_x := 99.0
	for z in zs:
		var x := rng.randf_range(-9.5, 9.5)
		# Never put two consecutive blocks in the same lane band.
		if absf(x - last_x) < 4.0:
			x = -x
		last_x = x
		_block(x, z, rng.randf_range(2.2, 3.4))
		_orb(-x * 0.6, 1.2, z - gap * 0.5)


func _pattern_gauntlet(zs: Array, gap: float) -> void:
	for i in zs.size():
		var z: float = zs[i]
		match i % 3:
			0:
				_block(-rng.randf_range(7.0, 9.5), z, 3.4)
				_block(rng.randf_range(7.0, 9.5), z, 3.4)
				_orb(0.0, 1.2, z)
				_orb(0.0, 1.2, z - 3.0)
			1:
				_low(0.0, z, 15.0)
				_orb_line(0.0, z + 3.0, 3, 2.4, 2.4)
			2:
				_hang(0.0, z, 17.0)
				# The mover rides its OWN gate, not the mid-gap, so it can't
				# stack on top of the next phrase's hazard.
				_orb_line(0.0, z + 3.0, 3, 2.4, 0.0, 0.7)


func _pattern_breather(zs: Array, gap: float, diff: float) -> void:
	# Rest phrase: an XP lane laid on the music's dominant subdivision. The
	# crystals therefore land on the beat as you fly through them - a little
	# rhythm break between hazard phrases.
	var x := _lane(rng.randi_range(-1, 1))
	var sub: float = _dominant_subdivision()
	var spd: float = 30.0 if game == null else maxf(game.base_speed(), 8.0)
	var step: float = maxf(spd * Sound.beat_period * sub, 4.0)
	var z: float = zs[0] + step * 0.5
	var z_end: float = zs[zs.size() - 1] - step * 0.5
	var i := 0
	while z > z_end and i < 24:
		var arc: float = (1.2 + diff) * sin(float(i) / 8.0 * PI)
		_xp(x, 1.15 + maxf(arc, 0.0), z)
		z -= step
		i += 1


func _pattern_lasers(zs: Array, gap: float) -> void:
	for i in zs.size():
		var z: float = zs[i]
		var x := _lane(rng.randi_range(-1, 1))
		_laser(x, z, rng.randf_range(10.0, 14.0), i % 2 == 0)
		_orb(x, 1.2, z - gap * 0.5)


func _pattern_pistons(zs: Array, gap: float) -> void:
	for z in zs:
		var lanes := [-1, 0, 1]
		if rng.randf() < 0.5:
			lanes = [-2, -1, 1, 2]
		for l in lanes:
			_piston(_lane(l), z, l == 0 or (l == -1 and lanes.size() == 4) or (l == 1 and lanes.size() == 4))
		_orb(_lane(0) if lanes.size() == 3 else _lane(-1), 1.2, z - gap * 0.5)


func _pattern_rotors(zs: Array, gap: float) -> void:
	for i in zs.size():
		var z: float = zs[i]
		var x := _lane(rng.randi_range(-1, 1))
		if i % 2 == 0:
			_rotor(x, z)
			_orb(x + (8.0 if x < 0.0 else -8.0), 1.2, z)
		else:
			_low(x, z, 9.0)
			_orb_line(x, z + 3.0, 3, 2.4, 2.2)


func _pattern_hunters(zs: Array, gap: float) -> void:
	for i in zs.size():
		var z: float = zs[i]
		if i % 2 == 0:
			_hunter(rng.randf_range(-5.0, 5.0), z)
		else:
			_block(-rng.randf_range(8.0, 10.0), z, 3.0)
			_block(rng.randf_range(8.0, 10.0), z, 3.0)
			_orb(0.0, 1.2, z)


func _pattern_pendulums(zs: Array, gap: float) -> void:
	var side: float = 1.0 if rng.randf() < 0.5 else -1.0
	for z in zs:
		_pendulum(side * 3.5, z)
		_orb(-side * 8.5, 1.2, z)
		side = -side


func _pattern_beat_wave(zs: Array, gap: float) -> void:
	# A flowing wave of alternating high/low blocks that creates a visual wave.
	for i in zs.size():
		var z: float = zs[i]
		var phase := float(i % 2)
		if phase == 0.0:
			_low(-5.5, z, 11.0)
			_orb_line(0.0, z + 3.0, 4, 2.2)
		else:
			_hang(-2.0, z, 12.0)
			_orb_line(0.0, z + 3.0, 4, 2.2, 0.0, 0.7)


func _pattern_wave(zs: Array, gap: float) -> void:
	# Sinusoidal wave of obstacles - nothing in the trough, block at the crest.
	for z in zs:
		var wave: float = sin(float(chunk_index) * 0.7 + z * 0.015)
		if wave > 0.25:
			_block(rng.randf_range(-5.0, 5.0), z, 3.2)
		else:
			# Open trough - just collect orbs
			_orb_line(0.0, z, 5, 2.6, 1.5)


## NOCTURNE BOULEVARD patterns -----------------------------------------------
## Dark Art Deco landmarks, moving shadow curtains and vintage cab hazards.

func _pattern_noir_gate(zs: Array, gap: float) -> void:
	# Alternating Art Deco obelisk pairs create a ceremonial boulevard. The
	# central route stays broad and is marked with warm amber pickups.
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	for i in zs.size():
		var z: float = zs[i]
		var x: float = side * 7.2
		_obelisk(x, z)
		if i % 2 == 0:
			_obelisk(-x, z)
		_orb(0.0, 1.3, z - gap * 0.35)
		side = -side


func _pattern_shadow_bloom(zs: Array, gap: float) -> void:
	# A moving half-screen of shadow/smoke. The safe side stays huge and is
	# marked by gold pickups; the curtain shifts only on downbeats.
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	for i in zs.size():
		var z: float = zs[i]
		_dustwall(side * 7.0, z, 10.0)
		_orb(-side * 7.2, 1.1, z)
		_orb(-side * 7.2, 1.1, z - gap * 0.4)
		side = -side


func _pattern_deco_run(zs: Array, gap: float) -> void:
	# Tall black Deco pylons form a readable slalom. The wide centre route stays
	# open and a golden pickup line marks the cinematic path.
	for i in zs.size():
		var z: float = zs[i]
		var side := -1.0 if i % 2 == 0 else 1.0
		_obelisk(side * 8.0, z)
		_orb(0.0, 1.35, z - gap * 0.35)


func _pattern_cabaret(zs: Array, gap: float) -> void:
	# Taxi-like Noir Cab hazards cross a lane on the beat. They are low, wide,
	# and always leave two clear lanes - a distinct street-level challenge.
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	for i in zs.size():
		var z: float = zs[i]
		_cab(side * 6.5, z)
		_orb(-side * 5.8, 1.2, z - gap * 0.3)
		side = -side


func _pattern_mixed(zs: Array, gap: float) -> void:
	# One hazard per gate, never two of the "big" kinds back to back.
	var last_big := false
	for z in zs:
		var pick := rng.randi_range(0, 5)
		var big := pick == 2 or pick == 3
		if big and last_big:
			pick = 0
			big = false
		last_big = big
		match pick:
			0: _laser(_lane(rng.randi_range(-1, 1)), z, 12.0, rng.randf() < 0.5)
			1: _piston(_lane(rng.randi_range(-2, 2)), z, true)
			2: _rotor(_lane(rng.randi_range(-1, 1)), z)
			3: _pendulum(rng.randf_range(-4.0, 4.0), z)
			4: _hunter(rng.randf_range(-4.0, 4.0), z)
			_: _block(rng.randf_range(-7.0, 7.0), z, 3.2)
		_orb(rng.randf_range(-9.0, 9.0), 1.2, z - gap * 0.5)


# ----------------------------------------------------------------- rhythm mode
## RHYTHM mode: no hazards. Beat PADS are laid down on the beat grid and the
## player scores by flying through them. The pattern for each phrase is picked
## from the live music structure:
##   quiet / breakdown  -> sparse single pads every 2 beats
##   normal             -> one pad per beat, lane random-walk
##   hats busy (highs)  -> 8th-note double pads
##   bass heavy         -> wide BAR pads (jump-through) on the downbeat
##   drop               -> triplet fans + full width bars, all lanes
var _lane_walk := 0

func _rhythm_phrase(pz: float, now: float, speed_now: float, bpg: int, slots: int) -> void:
	var base_beat := _next_beat - (slots * bpg + 2 * bpg)  # first beat of this phrase
	var beats := slots * bpg + 2 * bpg
	var quiet: bool = Sound.breakdown or Sound.energy < 0.22
	var busy: bool = Sound.highs > 0.55
	var heavy: bool = Sound.bass > 0.62
	var dropping: bool = Sound.drop_active
	var variant := "single"
	if dropping:
		variant = "drop"
	elif quiet:
		variant = "sparse"
	elif heavy and busy:
		variant = "bars8"
	elif busy:
		variant = "eighths"
	elif heavy:
		variant = "bars"
	var b := 0
	while b < beats:
		var k := base_beat + b
		var z := _z_at_beat(k, pz, now, speed_now)
		var downbeat := (k % 4) == 0
		match variant:
			"sparse":
				if b % 2 == 0:
					_note(_walk_lane(), z, k, 0)
				b += 1
			"eighths":
				_note(_walk_lane(), z, k, 0)
				var zh := _z_at_beat_f(float(k) + 0.5, pz, now, speed_now)
				_note(_lane_walk_side(), zh, k, 1)
				b += 1
			"bars":
				if downbeat:
					_note(0.0, z, k, 2)
				else:
					_note(_walk_lane(), z, k, 0)
				b += 1
			"bars8":
				if downbeat:
					_note(0.0, z, k, 2)
				else:
					_note(_walk_lane(), z, k, 0)
					var zh := _z_at_beat_f(float(k) + 0.5, pz, now, speed_now)
					_note(_lane_walk_side(), zh, k, 1)
				b += 1
			"drop":
				if downbeat:
					_note(0.0, z, k, 2)
				else:
					for t in 3:
						var zt := _z_at_beat_f(float(k) + float(t) / 3.0, pz, now, speed_now)
						_note(_lane(t - 1), zt, k, 3)
				b += 1
			_:
				_note(_walk_lane(), z, k, 0)
				b += 1


func _z_at_beat_f(kf: float, pz: float, now: float, speed_now: float) -> float:
	return pz - speed_now * (Sound.time_of_beat(kf) - now)


func _walk_lane() -> float:
	_lane_walk = clampi(_lane_walk + rng.randi_range(-1, 1), -2, 2)
	return _lane(_lane_walk)


func _lane_walk_side() -> float:
	return _lane(clampi(_lane_walk + (1 if rng.randf() < 0.5 else -1), -2, 2))


## variant: 0 = pad, 1 = half-beat pad (small), 2 = wide bar, 3 = triplet pad
func _note(x: float, z: float, beat_index: int, variant: int) -> void:
	var p = _free_pickup()
	p.game = game
	p.player = player
	p.setup_note(Vector3(x, 1.2, z), variant, beat_index)
	notes_live.append(p)


## Called by main every frame: notes that slipped behind the ship are misses.
func collect_missed_notes(pz: float) -> Array:
	var missed: Array = []
	var i := notes_live.size() - 1
	while i >= 0:
		var n = notes_live[i]
		if not n.live:
			notes_live.remove_at(i)
		elif n.position.z > pz + 2.5:
			missed.append(n)
			n.recycle()
			notes_live.remove_at(i)
		i -= 1
	return missed


func forget_note(n) -> void:
	var i := notes_live.find(n)
	if i >= 0:
		notes_live.remove_at(i)


# ----------------------------------------------------------------------- decor

## ------------------------------------------------------------------ clearance
## Bridges lift the highway into the sky, so any building whose footprint would
## intersect the structure corridor must be removed (or refused) — otherwise the
## deck appears to pass straight through the tower.

## Extra lateral room demanded by each structure beyond the deck half-width.
func _structure_clear_width() -> float:
	if bridge == null or not bridge.active:
		return 0.0
	match bridge.kind:
		BridgeScript.Kind.CORKSCREW:
			return 9.0    # the barrel roll swings wide
		BridgeScript.Kind.LOOP:
			return 22.0   # the hoop leans out far to the side
		BridgeScript.Kind.SPIRAL:
			return 26.0   # the spiral sweeps out over the city
		_:
			return 6.0


## True if a decor box at (x, z) with the given footprint and top Y would clash
## with the live structure ribbon. This is a real 3D test: a low light post can
## stay under a high bridge, but a tall tower is retired before the deck touches it.
func _clashes_with_structure(x: float, z: float, hw: float, hd: float, top_y: float = 500.0) -> bool:
	if bridge == null or not bridge.active:
		return false
	var deck_half: float = bridge.deck_width * 0.5
	var clear: float = _structure_clear_width()
	var segment_half: float = bridge.length / 96.0 * 0.8
	# Walk the structure's own path and test the actual deck center against the
	# building AABB. More samples than the old version remove false gaps between
	# checks on a corkscrew or spiral.
	var steps := 112
	for i in range(steps + 1):
		var u := float(i) / float(steps)
		var f: Transform3D = bridge.frame_at(u)
		var p := f.origin
		if absf(p.z - z) > hd + segment_half + 4.0:
			continue
		var dx: float = absf(p.x - x)
		if dx > hw + deck_half + clear:
			continue
		# The deck slab, rails and helix can only touch a tower that reaches this
		# height. Low scenery under an arc remains, tall Art Deco crowns do not.
		if p.y <= top_y + 8.0:
			return true
	return false


## Re-checks every live building/tower and retires any that now clash with an
## active structure. Called right after a structure is placed.
## After a structure clears a corridor through the city, re-seed that same Z
## band with buildings pushed safely OUTSIDE the structure's reach, so the
## skyline doesn't develop a visible hole where the corridor was carved.
func _backfill_structure_corridor() -> void:
	if bridge == null or not bridge.active:
		return
	var bd: Dictionary = Biomes.visual(biome_id)["building"]
	var reach: float = bridge.deck_width * 0.5 + _structure_clear_width() + 8.0
	var z_hi: float = bridge.start_z + 20.0
	var z_lo: float = bridge.end_z - 40.0
	var z := z_hi
	while z > z_lo:
		for side in [-1.0, 1.0]:
			if rng.randf() > 0.5:
				continue
			var h: float = rng.randf_range(bd["h_min"], bd["h_max"])
			var w: float = rng.randf_range(bd["w_min"], bd["w_max"])
			var bx: float = _offroad_building_x(side, w, reach + 4.0, reach + 60.0)
			# Reuse a pooled building if one is free.
			var b: MeshInstance3D = null
			for cand in _buildings:
				if cand.position.y < -100.0:
					b = cand
					break
			if b == null:
				break
			var bm: BoxMesh = b.mesh
			bm.size = Vector3(w, h, rng.randf_range(bd["w_min"], bd["w_max"]) * 1.4)
			var bz: float = z + rng.randf_range(-8.0, 8.0)
			if _clashes_with_structure(bx, bz, maxf(w, bm.size.z) * 0.5, maxf(w, bm.size.z) * 0.5, h + (24.0 if _building_style == 4 else 0.0)):
				b.position.y = -500.0
				continue
			b.position = Vector3(bx, h * 0.5 - 2.0, bz)
			b.rotation.y = 0.0 if _building_style == 4 else rng.randf_range(-0.25, 0.25)
			_configure_deco_crown(b, w, h, int(absf(z)) + int(absf(bx)))
		z -= rng.randf_range(26.0, 44.0)


func clear_decor_around_structure() -> void:
	if bridge == null or not bridge.active:
		return
	for b in _buildings:
		if b.position.y < -100.0:
			continue
		var bm: BoxMesh = b.mesh
		var hw: float = maxf(bm.size.x, bm.size.z) * 0.5
		var crown_top: float = b.position.y + bm.size.y * 0.5 + (24.0 if _building_style == 4 else 0.0)
		if _clashes_with_structure(b.position.x, b.position.z, hw, hw, crown_top):
			b.position.y = -500.0
	for t in _towers:
		if t.position.y < -100.0:
			continue
		var tm: BoxMesh = t.mesh
		var hw2: float = maxf(tm.size.x, tm.size.z) * 0.5
		if _clashes_with_structure(t.position.x, t.position.z, hw2, hw2, t.position.y + tm.size.y * 0.5):
			t.position.y = -500.0
	for arch in _arches:
		if arch.position.y < -100.0:
			continue
		if _clashes_with_structure(arch.position.x, arch.position.z, 21.0, 2.0, 14.0):
			arch.position.y = -500.0


## Lateral X so a building of width `w` sits fully off the asphalt (and, on
## Nocturne, past the sidewalk/curb) instead of overlapping the driveable road.
func _offroad_building_x(side: float, w: float, d_min: float, d_max: float) -> float:
	var curb: float = 7.5 if _building_style == 4 else 3.5
	var min_x: float = TRACK_HALF + curb + w * 0.5
	var x: float = rng.randf_range(d_min, d_max)
	return side * maxf(x, min_x)


func _decorate(z0: float) -> void:
	var bd: Dictionary = Biomes.visual(biome_id)["building"]

	for s in [-1.0, 1.0]:
		var post: Node3D = _posts.pop_front()
		_posts.push_back(post)
		var px: float = s * (TRACK_HALF + 3.0)
		var pz: float = z0 - rng.randf_range(5.0, 16.0)
		if _clashes_with_structure(px, pz, 2.0, 2.0, 7.0):
			post.position.y = -500.0
		else:
			post.position = Vector3(px, 0.0, pz)
			post.rotation.y = 0.0 if s > 0.0 else PI

	if chunk_index % 3 == 0:
		var arch: Node3D = _arches.pop_front()
		_arches.push_back(arch)
		var az: float = z0 - rng.randf_range(12.0, 44.0)
		if _clashes_with_structure(0.0, az, 21.0, 2.0, 14.0):
			arch.position.y = -500.0
		else:
			arch.position = Vector3(0.0, 0.0, az)

	var building_count: int = 8 if _building_style == 4 else 4
	for i in building_count:
		var b: MeshInstance3D = _buildings.pop_front()
		_buildings.push_back(b)
		var s2: float = 1.0 if (i % 2 == 0) else -1.0
		var h: float = rng.randf_range(bd["h_min"], bd["h_max"])
		var w: float = rng.randf_range(bd["w_min"], bd["w_max"])
		# Nocturne gets a deliberate Art Deco street canyon: four staggered
		# tiers per side, each with a different silhouette/height, visible from
		# the first horizon instead of arriving as random late boxes.
		var tier: int = i / 2
		if _building_style == 4:
			h = clampf(h + float((tier * 19 + chunk_index * 7) % 47), bd["h_min"], bd["h_max"])
			w = clampf(w * (0.78 + float(tier) * 0.10), bd["w_min"], bd["w_max"])
		var bm: BoxMesh = b.mesh
		bm.size = Vector3(w, h, rng.randf_range(bd["w_min"], bd["w_max"]) * 1.4)
		var bx: float = _offroad_building_x(s2, w, bd["d_min"], bd["d_max"])
		var bz: float = z0 - rng.randf_range(0.0, CHUNK)
		if _building_style == 4:
			bx = s2 * (18.0 + float(tier) * 10.5 + rng.randf_range(-1.8, 1.8))
			bz = z0 - float(tier) * 15.0 - rng.randf_range(1.0, 7.0)
			# The street-canyon tiers stay staggered, but never overlap the asphalt.
			bx = s2 * maxf(absf(bx), TRACK_HALF + 7.5 + w * 0.5)
		# Never spawn a building inside an active structure's corridor.
		if _clashes_with_structure(bx, bz, maxf(w, bm.size.z) * 0.5, maxf(w, bm.size.z) * 0.5, h + (24.0 if _building_style == 4 else 0.0)):
			b.position.y = -500.0
			continue
		b.position = Vector3(bx, h * 0.5 - 2.0, bz)
		if _building_style == 2:
			b.rotation.y = PI * 0.25 + rng.randf_range(-0.3, 0.3)
		elif _building_style == 4:
			# Nocturne's towers keep crisp, hand-painted Art Deco silhouettes.
			b.rotation.y = 0.0
		else:
			b.rotation.y = rng.randf_range(-0.25, 0.25)
		_configure_deco_crown(b, w, h, chunk_index * 11 + i)
		# Concert moving-head fixtures on the nearest rooftops. Nocturne uses a
		# denser four-fixture canopy to echo the skyline searchlight references.
		var fixture_limit: int = 4 if _building_style == 4 else 2
		if gobo_rig != null and i < fixture_limit and absf(b.position.x) < 60.0:
			# Building origin is at h/2 - 2, so the roof lives at h - 2.
			# For Deco towers, lift fixtures above the crown/spire base.
			var roof_y: float = b.position.y + h * 0.5 + 0.7
			if _building_style == 4:
				roof_y += 4.0 + float((chunk_index + i) % 4) * 1.2
			gobo_rig.place_fixture(Vector3(b.position.x, roof_y, b.position.z), i + chunk_index * 2)

	for i in 2:
		var t: MeshInstance3D = _towers.pop_front()
		_towers.push_back(t)
		var s3: float = 1.0 if rng.randf() < 0.5 else -1.0
		var th: float = rng.randf_range(30.0, 120.0)
		var tm: BoxMesh = t.mesh
		tm.size = Vector3(rng.randf_range(14.0, 38.0), th, rng.randf_range(14.0, 38.0))
		var tx: float = s3 * rng.randf_range(120.0, 260.0)
		var tz: float = z0 - rng.randf_range(0.0, CHUNK)
		if _clashes_with_structure(tx, tz, maxf(tm.size.x, tm.size.z) * 0.5, maxf(tm.size.x, tm.size.z) * 0.5, th):
			t.position.y = -500.0
			continue
		t.position = Vector3(tx, th * 0.5 - 4.0, tz)
