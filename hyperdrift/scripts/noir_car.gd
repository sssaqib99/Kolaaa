extends Node3D
## A stylized 1930s-inspired boulevard sedan used only on Nocturne Boulevard.
## It is scenery, never a collision object: one pool instance glides past the
## ship in the opposing lane, headlights reflecting off the wet asphalt.

var active := false
var player = null
var speed := 28.0
var lane_x := 0.0
var _t := 0.0
var _wheels: Array[MeshInstance3D] = []
var _headlights: Array[OmniLight3D] = []
var _body_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	_build()
	recycle()


func _build() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.018, 0.026, 0.07)
	_body_mat.metallic = 0.88
	_body_mat.roughness = 0.22
	_body_mat.rim_enabled = true
	_body_mat.rim = 0.45
	_body_mat.rim_tint = 0.25

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.06, 0.16, 0.30)
	_glass_mat.metallic = 0.5
	_glass_mat.roughness = 0.12
	_glass_mat.emission_enabled = true
	_glass_mat.emission = Color(0.03, 0.13, 0.26)
	_glass_mat.emission_energy_multiplier = 0.65

	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_mat.albedo_color = Color(2.8, 2.0, 0.65)

	# Long low body, hood and cabin make a clear Art Deco silhouette.
	_add_box(Vector3(3.0, 0.72, 6.1), Vector3(0, 0.72, 0), _body_mat)
	_add_box(Vector3(2.35, 0.56, 2.55), Vector3(0, 1.28, 0.45), _glass_mat)
	_add_box(Vector3(2.72, 0.32, 1.35), Vector3(0, 1.05, -2.08), _body_mat)
	# Chrome grille / running boards.
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.42, 0.48, 0.66)
	chrome.metallic = 1.0
	chrome.roughness = 0.18
	_add_box(Vector3(1.55, 0.45, 0.13), Vector3(0, 0.72, -3.1), chrome)
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.18, 0.12, 4.8), Vector3(side * 1.62, 0.47, 0), chrome)
		for z in [-1.75, 1.7]:
			var wheel := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.58
			wm.bottom_radius = 0.58
			wm.height = 0.26
			wm.radial_segments = 14
			wheel.mesh = wm
			wheel.material_override = chrome
			wheel.position = Vector3(side * 1.58, 0.48, z)
			wheel.rotation_degrees = Vector3(0, 0, 90)
			add_child(wheel)
			_wheels.append(wheel)
	# Twin warm headlights.
	for side in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.22
		lm.height = 0.44
		lamp.mesh = lm
		lamp.material_override = _lamp_mat
		lamp.position = Vector3(side * 0.85, 0.74, -3.18)
		add_child(lamp)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.78, 0.38)
		light.light_energy = 1.2
		light.omni_range = 16.0
		light.shadow_enabled = false
		light.position = lamp.position
		add_child(light)
		_headlights.append(light)


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func spawn(pos: Vector3, x: float, p: Node3D) -> void:
	global_position = pos
	lane_x = x
	player = p
	position.x = lane_x
	_t = 0.0
	speed = randf_range(24.0, 34.0)
	rotation_degrees = Vector3(0, 180, 0)
	active = true
	visible = true


func recycle() -> void:
	active = false
	visible = false
	global_position = Vector3(0, -500, 0)


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	# Opposing traffic travels toward the camera, passing the ship on the far lane.
	global_position.z += speed * delta
	global_position.x = lane_x + sin(_t * 0.7) * 0.18
	for w in _wheels:
		w.rotation.x += speed * delta * 1.4
	var pulse := 0.85 + 0.15 * sin(_t * 7.0 + Sound.beat_pos() * TAU)
	for light in _headlights:
		light.light_energy = 1.0 * pulse + Sound.intensity * 0.45
	if player != null and global_position.z > player.global_position.z + 65.0:
		recycle()