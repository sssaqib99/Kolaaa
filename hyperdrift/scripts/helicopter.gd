extends Node3D
## Background police/patrol helicopter that sweeps across the skyline every
## 20-30 s. It carries a visible searchlight cone pointing DOWN at the highway
## (matching the reference art) plus a real SpotLight3D so the ground and
## buildings actually get lit. Rotor speed and beacon flash follow the music.

var visible_t := 0.0
var lifetime := 0.0
var active := false
var phase := 0.0
var heading := 1.0
var altitude := 58.0
var start_z := 0.0
var x_amp := 95.0
var y_amp := 5.0
var sweep_phase := 0.0

@onready var rotor: MeshInstance3D = $MainRotor
@onready var tail_rotor: MeshInstance3D = $TailRotor
@onready var beacon: MeshInstance3D = $Beacon
@onready var body: MeshInstance3D = $Body

var search: SpotLight3D
var beam: MeshInstance3D
var beam_mat: StandardMaterial3D
var beam_origin := Vector3.ZERO


func _ready() -> void:
	visible = false
	for n in [body, rotor, tail_rotor, beacon]:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_searchlight()


## Searchlight rig: a real SpotLight3D aimed straight down plus a translucent
## cone mesh so the beam is visible in the air as well as lighting the ground.
func _build_searchlight() -> void:
	search = SpotLight3D.new()
	search.light_color = Color(0.92, 0.97, 1.0)
	search.light_energy = 6.0
	search.spot_angle = 24.0
	search.spot_attenuation = 1.0
	search.spot_range = 120.0
	search.shadow_enabled = false
	# Aim it straight down: the spotlight's local -Z is its beam direction.
	search.rotation_degrees = Vector3(-90, 0, 0)
	search.position = Vector3(0, -0.8, 0)
	add_child(search)

	# Visible cone: narrow at the fixture, wide at the ground, fading at the tip.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var len := 46.0
	var segs := 16
	for ring in 2:
		var rad := 0.45 if ring == 0 else 12.5
		var y := -1.0 if ring == 0 else -len
		var alpha := 0.55 if ring == 0 else 0.0
		for s in segs + 1:
			var ang := float(s) / float(segs) * TAU
			st.set_normal(Vector3(cos(ang), 0.0, sin(ang)))
			st.set_color(Color(1, 1, 1, alpha))
			st.add_vertex(Vector3(cos(ang) * rad, y, sin(ang) * rad))
	var arr := ArrayMesh.new()
	st.commit(arr)
	beam_mat = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.vertex_color_use_as_albedo = true
	beam_mat.albedo_color = Color(0.78, 0.92, 1.0)
	beam_mat.disable_receive_shadows = true
	beam = MeshInstance3D.new()
	beam.mesh = arr
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	# A glowing lens where the beam leaves the fuselage.
	var lens := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.34
	lm.height = 0.68
	lm.radial_segments = 10
	lm.rings = 6
	lens.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(2.6, 3.0, 3.4)
	lens.material_override = lmat
	lens.position = Vector3(0, -0.85, 0.4)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lens)
	beam_origin = lens.position


## Spawn behind the player and fly across. heading +1 = left->right, -1 reverse.
func spawn(near_player_z: float, h: int = 0) -> void:
	heading = -1.0 if h % 2 == 1 else 1.0
	altitude = 54.0 + randf_range(-5.0, 12.0)
	start_z = near_player_z + (520.0 if heading > 0.0 else -520.0)
	lifetime = 32.0
	visible_t = 0.0
	phase = randf() * TAU
	sweep_phase = randf() * TAU
	active = true
	visible = true
	if search != null:
		search.light_energy = 6.0


func despawn() -> void:
	active = false
	visible = false
	if search != null:
		search.light_energy = 0.0


func _process(delta: float) -> void:
	if not active:
		return
	visible_t += delta
	if visible_t > lifetime:
		despawn()
		return

	var z_offset := start_z - heading * (visible_t * 26.0)
	var x_offset := sin(visible_t * 0.55 + phase) * x_amp
	var y_offset := altitude + sin(visible_t * 0.4 + phase) * y_amp
	position = Vector3(x_offset, y_offset, z_offset)
	rotation_degrees = Vector3(-7.0, 0.0, 6.0 if heading > 0.0 else -6.0)

	# Rotor speed follows the music.
	var sp: float = Sound.intensity
	var rotor_speed: float = 800.0 + sp * 1400.0 + Sound.spike * 2500.0
	rotor.rotation_degrees.y += delta * rotor_speed
	tail_rotor.rotation_degrees.x += delta * rotor_speed * 2.6

	# Beacon strobes on 8th notes.
	var beat_frac := fposmod(Sound.beat_pos() * 2.0, 1.0)
	var bp := 1.0 if beat_frac < 0.35 else 0.18
	var mat: StandardMaterial3D = beacon.material_override
	if mat != null:
		var bcol := Color(1, 0.18, 0.18) * (1.4 + bp * 2.0)
		mat.albedo_color = bcol
		mat.emission = bcol
		mat.emission_energy_multiplier = 1.2 + bp * 2.2

	# ---- Searchlight: sweeps slowly across the highway, brightens on spikes.
	sweep_phase += delta * 0.5
	var sweep := sin(sweep_phase) * 22.0
	var intensity := 0.75 + sp * 0.35 + Sound.spike * 0.6
	if search != null:
		search.light_energy = 5.0 * intensity
		# Tilt the beam with the sweep (about the travel axis).
		search.rotation_degrees = Vector3(-90.0 + sweep * 0.0, 0.0, sweep)
	if beam != null:
		beam.rotation_degrees = Vector3(0.0, 0.0, sweep * 0.4)
		beam_mat.albedo_color = Color(0.78, 0.92, 1.0) * intensity
