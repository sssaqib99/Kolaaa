extends Area3D
## Pooled collectible: energy orbs, the three power-ups, XP crystals and the
## big XP rings found on the sky-bridge.

enum Kind { ORB, SHIELD, MAGNET, OVERDRIVE, XP, RING, NOTE }

const V := preload("res://scripts/visuals.gd")

var kind: int = Kind.ORB
var live := false
var note_variant := 0
var note_beat := 0
var _pad: MeshInstance3D
var _pad_mat: ShaderMaterial
var player = null # untyped on purpose: cross-script duck typing
var game = null

var _core: MeshInstance3D
var _ring: MeshInstance3D
var _crystal: Node3D
var _core_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _crystal_mat: ShaderMaterial
var _light: OmniLight3D
var _shape: SphereShape3D
var _t := 0.0
var _home := Vector3.ZERO
var _pulled := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("pickup")

	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.84
	sm.radial_segments = 12
	sm.rings = 7
	_core = MeshInstance3D.new()
	_core.mesh = sm
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Materials are built once and re-parameterised on respawn (no churn).
	_core_mat = V.orb_material(V.CYAN, 2.4)
	_core.material_override = _core_mat
	add_child(_core)

	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.78
	tm.rings = 24
	tm.ring_segments = 8
	_ring = MeshInstance3D.new()
	_ring.mesh = tm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.rotation_degrees = Vector3(90, 0, 0)
	_ring_mat = V.orb_material(V.CYAN, 3.0)
	_ring.material_override = _ring_mat
	add_child(_ring)

	# XP crystal: two four-sided cones = an octahedron.
	_crystal = Node3D.new()
	_crystal_mat = V.orb_material(V.YELLOW, 3.0)
	for s in [1.0, -1.0]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.42
		cm.height = 0.62
		cm.radial_segments = 4
		cm.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _crystal_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, s * 0.31, 0)
		mi.rotation_degrees = Vector3(0 if s > 0 else 180, 45, 0)
		_crystal.add_child(mi)
	_crystal.visible = false
	add_child(_crystal)

	# Rhythm-mode beat pad: a flat glowing ring you fly through.
	var pm := TorusMesh.new()
	pm.inner_radius = 1.1
	pm.outer_radius = 1.5
	pm.rings = 28
	pm.ring_segments = 8
	_pad = MeshInstance3D.new()
	_pad.mesh = pm
	_pad_mat = V.orb_material(V.CYAN, 3.2)
	_pad.material_override = _pad_mat
	_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pad.visible = false
	add_child(_pad)

	var col := CollisionShape3D.new()
	_shape = SphereShape3D.new()
	_shape.radius = 0.95
	col.shape = _shape
	add_child(col)

	_light = OmniLight3D.new()
	_light.omni_range = 7.0
	_light.light_energy = 1.6
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)


func setup(k: int, pos: Vector3) -> void:
	kind = k
	position = pos
	_home = pos
	_t = randf() * TAU
	live = true
	visible = true
	set_deferred("monitorable", true)
	_pulled = false
	var c := V.CYAN
	var big := false
	_core.visible = true
	_crystal.visible = false
	_pad.visible = false
	_ring.scale = Vector3.ONE
	_ring.rotation_degrees = Vector3(90, 0, 0)
	scale = Vector3.ONE
	match kind:
		Kind.ORB:
			c = V.CYAN if game == null else game.orb_color
		Kind.SHIELD:
			c = V.LIME
			big = true
		Kind.MAGNET:
			c = V.VIOLET
			big = true
		Kind.OVERDRIVE:
			c = V.ORANGE
			big = true
		Kind.XP:
			c = Color(1.0, 0.85, 0.3)
			_core.visible = false
			_crystal.visible = true
		Kind.RING:
			c = Color(1.0, 0.9, 0.45)
			_core.visible = false
	_core_mat.set_shader_parameter("orb_color", c)
	_core_mat.set_shader_parameter("energy", 3.4 if big else 2.4)
	_ring_mat.set_shader_parameter("orb_color", c.lightened(0.25))
	_crystal_mat.set_shader_parameter("orb_color", c)
	_ring.visible = big or kind == Kind.RING
	if kind == Kind.RING:
		_ring.scale = Vector3.ONE * 3.4
		_ring.rotation_degrees = Vector3(0, 0, 0)
		_shape.radius = 2.1
	else:
		_shape.radius = 1.35 if big else 0.95
		scale = Vector3.ONE * (1.35 if big else 1.0)
	_light.light_color = c
	_light.visible = big or kind == Kind.RING
	set_physics_process(true)


## Rhythm-mode pad. variant: 0 pad, 1 half-beat (small), 2 wide bar, 3 triplet.
func setup_note(pos: Vector3, variant: int, beat_index: int) -> void:
	setup(Kind.NOTE, pos)
	note_variant = variant
	note_beat = beat_index
	_core.visible = false
	_ring.visible = false
	_pad.visible = true
	var c: Color = V.CYAN if game == null else game.orb_color
	var big := false
	match variant:
		1:
			c = c.lightened(0.35)
			_pad.scale = Vector3(0.7, 0.7, 0.7)
		2:
			c = V.YELLOW
			_pad.scale = Vector3(4.6, 1.0, 1.0)
			big = true
		3:
			c = V.MAGENTA
			_pad.scale = Vector3(0.85, 0.85, 0.85)
		_:
			_pad.scale = Vector3.ONE
	_pad_mat.set_shader_parameter("orb_color", c)
	_pad_mat.set_shader_parameter("energy", 3.6)
	_shape.radius = 1.6 if not big else 2.6
	_light.visible = big
	_light.light_color = c


func recycle() -> void:
	live = false
	visible = false
	# Deferred: collection happens from inside an area signal callback.
	set_deferred("monitorable", false)
	set_physics_process(false)
	position = Vector3(0, -500, 0)


func _physics_process(delta: float) -> void:
	_t += delta
	_core.rotation.y += delta * 2.2
	_crystal.rotation.y += delta * 3.0
	if kind == Kind.RING:
		_ring.rotation.z += delta * 1.2
	elif kind == Kind.NOTE:
		_pad.rotation.z += delta * (2.0 + Sound.spike * 8.0)
		var bp: float = fposmod(Sound.beat_pos(), 1.0)
		var pul: float = 1.0 + 0.18 * exp(-bp * 6.0)
		_pad_mat.set_shader_parameter("energy", 2.6 + pul * 1.4)
	else:
		_ring.rotation.z += delta * 3.4
	if _pulled or game == null or player == null:
		_magnet_step(delta)
		return
	position.y = _home.y + sin(_t * 2.6) * 0.16
	_magnet_step(delta)


func _magnet_step(delta: float) -> void:
	if game == null or player == null:
		return
	if game.magnet_t <= 0.0 or (kind != Kind.ORB and kind != Kind.XP):
		return
	var to_p: Vector3 = player.global_position - global_position
	if to_p.length() < 22.0 and to_p.z < 4.0:
		_pulled = true
		global_position += to_p.normalized() * delta * (26.0 + (22.0 - to_p.length()) * 2.2)
