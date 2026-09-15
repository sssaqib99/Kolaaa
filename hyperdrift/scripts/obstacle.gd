extends Area3D
## A single pooled hazard. Colour + scrolling arrows communicate the required
## action, and several kinds animate on the BEAT CLOCK so the level literally
## dances to whatever music is playing.
##
##  BLOCK     dodge                      LASER     beam blinks on the beat
##  LOW       jump                       PISTON    slams down on the beat
##  HANG      duck                       ROTOR     quarter-turn per beat
##  MOVER     slides sideways            HUNTER    homes in on the ship
##  SPIN      rotating bar               PENDULUM  swings across on half-beats

enum Kind { BLOCK, LOW, HANG, MOVER, SPIN, LASER, PISTON, ROTOR, HUNTER, PENDULUM, OBELISK, DUSTWALL, CAB }

const TRACK_HALF := 14.7   # widened ~9% (was 13.5)
const PISTON_UP := 7.2
const PISTON_DOWN := 1.6
const PENDULUM_AMP := 0.72
const PENDULUM_ARM := 8.5

var kind: int = Kind.BLOCK
var base_x := 0.0
var move_range := 0.0
var move_speed := 1.0
var spin_speed := 0.0
var phase := 0.0          # beats
var live := false
var game = null
var player = null
var laser_on := false
var _locked := false

var _mesh_inst: MeshInstance3D
var _box_mesh: BoxMesh
var _shape: CollisionShape3D
var _box_shape: BoxShape3D
var _parts: Array[MeshInstance3D] = []
var _t := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("obstacle")

	_box_mesh = BoxMesh.new()
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = _box_mesh
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_inst)

	_box_shape = BoxShape3D.new()
	_shape = CollisionShape3D.new()
	_shape.shape = _box_shape
	add_child(_shape)

	for i in 3:
		var p := MeshInstance3D.new()
		p.mesh = BoxMesh.new()
		p.visible = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_parts.append(p)


# ------------------------------------------------------------------- setup

func _begin(k: int, pos: Vector3) -> void:
	kind = k
	position = pos
	base_x = pos.x
	rotation = Vector3.ZERO
	phase = 0.0
	_t = 0.0
	_locked = false
	laser_on = false
	live = true
	visible = true
	_mesh_inst.visible = true
	_mesh_inst.position = Vector3.ZERO
	_mesh_inst.rotation = Vector3.ZERO
	_shape.position = Vector3.ZERO
	_shape.rotation = Vector3.ZERO
	for p in _parts:
		p.visible = false
		p.position = Vector3.ZERO
		p.rotation = Vector3.ZERO
		p.scale = Vector3.ONE
	set_deferred("monitorable", true)
	set_deferred("monitoring", false)
	collision_mask = 0
	set_physics_process(true)


func _part(i: int, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var p := _parts[i]
	var bm: BoxMesh = p.mesh
	bm.size = size
	p.material_override = mat
	p.position = pos
	p.visible = true
	return p


func setup(k: int, pos: Vector3, size: Vector3, mat: Material) -> void:
	_begin(k, pos)
	_box_mesh.size = size
	_box_shape.size = size * Vector3(0.86, 0.9, 0.9)
	_mesh_inst.material_override = mat
	set_physics_process(kind == Kind.MOVER or kind == Kind.SPIN or kind == Kind.OBELISK or kind == Kind.DUSTWALL or kind == Kind.CAB)


## Blinking beam between two pylons. Off for one beat centred on the beat.
func setup_laser(pos: Vector3, width: float, low: bool, mat_pylon: Material, mat_beam: Material, mat_idle: Material, phase_beats: float) -> void:
	_begin(Kind.LASER, pos)
	phase = phase_beats
	var beam_y := 1.15 if low else 2.35
	_box_mesh.size = Vector3(width, 0.26, 0.26)
	_mesh_inst.position = Vector3(0.0, beam_y, 0.0)
	_mesh_inst.material_override = mat_beam
	_box_shape.size = Vector3(width, 0.5, 0.6)
	_shape.position = Vector3(0.0, beam_y, 0.0)
	_part(0, Vector3(0.7, 3.8, 0.7), mat_pylon, Vector3(-width * 0.5, 1.9, 0.0))
	_part(1, Vector3(0.7, 3.8, 0.7), mat_pylon, Vector3(width * 0.5, 1.9, 0.0))
	_part(2, Vector3(width, 0.08, 0.08), mat_idle, Vector3(0.0, beam_y, 0.0))
	# The laser detects the ship itself so the blink can never miss an overlap.
	set_deferred("monitorable", false)
	set_deferred("monitoring", true)
	collision_mask = 1


## Block that slams to the deck on the beat, hovers high in between.
func setup_piston(pos: Vector3, mat: Material, mat_rail: Material, phase_beats: float) -> void:
	_begin(Kind.PISTON, Vector3(pos.x, PISTON_UP, pos.z))
	phase = phase_beats
	_box_mesh.size = Vector3(3.2, 3.2, 1.9)
	_box_shape.size = Vector3(2.9, 2.9, 1.7)
	_mesh_inst.material_override = mat
	_part(0, Vector3(0.35, 11.0, 0.35), mat_rail, Vector3(1.9, 0.0, 0.0))
	_part(1, Vector3(0.35, 11.0, 0.35), mat_rail, Vector3(-1.9, 0.0, 0.0))


## Bar rotating a quarter turn per beat around the travel axis.
func setup_rotor(pos: Vector3, mat: Material, mat_hub: Material, dir: float) -> void:
	_begin(Kind.ROTOR, Vector3(pos.x, 4.6, pos.z))
	spin_speed = dir
	_box_mesh.size = Vector3(9.6, 0.7, 1.0)
	_box_shape.size = Vector3(9.2, 0.6, 0.9)
	_mesh_inst.material_override = mat
	_part(0, Vector3(1.3, 1.3, 1.4), mat_hub, Vector3.ZERO)


## Drone that tracks the ship's lane until the last moment.
func setup_hunter(pos: Vector3, mat: Material, mat_fin: Material) -> void:
	_begin(Kind.HUNTER, Vector3(pos.x, 1.35, pos.z))
	_box_mesh.size = Vector3(1.7, 1.1, 2.1)
	_box_shape.size = Vector3(1.6, 1.0, 2.0)
	_mesh_inst.material_override = mat
	_mesh_inst.rotation_degrees = Vector3(0, 0, 45)
	_part(0, Vector3(3.2, 0.12, 0.9), mat_fin, Vector3(0.0, 0.0, 0.3))
	_part(1, Vector3(0.12, 1.6, 0.9), mat_fin, Vector3(0.0, 0.2, 0.6))


## Wrecking-ball pendulum: extreme positions land on beats, crosses the centre on half beats.
func setup_pendulum(pos: Vector3, mat_arm: Material, mat_bob: Material, phase_beats: float) -> void:
	_begin(Kind.PENDULUM, Vector3(pos.x, 10.3, pos.z))
	phase = phase_beats
	_box_mesh.size = Vector3(0.32, PENDULUM_ARM, 0.32)
	_mesh_inst.position = Vector3(0.0, -PENDULUM_ARM * 0.5, 0.0)
	_mesh_inst.material_override = mat_arm
	_box_shape.size = Vector3(2.0, 2.0, 1.5)
	_shape.position = Vector3(0.0, -PENDULUM_ARM, 0.0)
	_part(0, Vector3(2.2, 2.2, 1.6), mat_bob, Vector3(0.0, -PENDULUM_ARM, 0.0))
	_part(1, Vector3(1.4, 0.6, 1.4), mat_arm, Vector3(0.0, 0.3, 0.0))
	_part(2, Vector3(0.5, 12.0, 0.5), mat_arm, Vector3(0.0, -6.0 + 0.6, -1.4))
	_parts[2].position = Vector3(0.0, -5.0, -1.3)


## Nocturne Boulevard: a carved Art Deco obelisk that rotates a few degrees on each
## downbeat. It is tall, narrow and readable, with a safe lane on either side.
func setup_obelisk(pos: Vector3, mat: Material, mat_band: Material, phase_beats: float) -> void:
	_begin(Kind.OBELISK, Vector3(pos.x, 3.5, pos.z))
	phase = phase_beats
	_box_mesh.size = Vector3(2.8, 7.0, 2.2)
	_box_shape.size = Vector3(2.5, 6.6, 2.0)
	_mesh_inst.material_override = mat
	_part(0, Vector3(3.2, 0.22, 2.5), mat_band, Vector3(0.0, 1.2, 0.0))
	_part(1, Vector3(3.2, 0.22, 2.5), mat_band, Vector3(0.0, -1.25, 0.0))


## Nocturne Boulevard: a shadow curtain sweeps laterally on the phrase, but never
## covers more than half the widened road. Players read its brass edge and move
## through the clear side.
func setup_dustwall(pos: Vector3, width: float, mat: Material, mat_edge: Material, phase_beats: float) -> void:
	_begin(Kind.DUSTWALL, Vector3(pos.x, 2.0, pos.z))
	phase = phase_beats
	move_range = minf(4.5, TRACK_HALF - width * 0.5 - 1.5)
	move_speed = 0.9
	_box_mesh.size = Vector3(width, 4.0, 1.6)
	_box_shape.size = Vector3(width * 0.88, 3.7, 1.45)
	_mesh_inst.material_override = mat
	_part(0, Vector3(width, 0.18, 0.18), mat_edge, Vector3(0.0, 2.05, 0.0))
	_part(1, Vector3(width, 0.18, 0.18), mat_edge, Vector3(0.0, -2.05, 0.0))


## A low vintage cab sweeps a single lane on the beat. It has a dark body,
## raised cabin and two brass headlamp strips so it reads as street traffic,
## not a generic block.
func setup_cab(pos: Vector3, mat: Material, trim: Material, phase_beats: float) -> void:
	_begin(Kind.CAB, Vector3(pos.x, 0.82, pos.z))
	phase = phase_beats
	move_range = 2.6
	move_speed = 1.0
	_box_mesh.size = Vector3(3.7, 1.15, 2.7)
	_box_shape.size = Vector3(3.3, 1.0, 2.45)
	_mesh_inst.material_override = mat
	_part(0, Vector3(2.35, 0.62, 1.45), trim, Vector3(0.0, 0.72, 0.25))
	_part(1, Vector3(2.8, 0.16, 0.16), trim, Vector3(0.0, -0.08, -1.38))
	_part(2, Vector3(0.42, 0.18, 0.12), trim, Vector3(0.95, 0.02, -1.44))


func recycle() -> void:
	live = false
	visible = false
	smashing = false
	scale = Vector3.ONE
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	collision_mask = 0
	set_physics_process(false)
	position = Vector3(0, -500, 0)


## ADRENALINE SMASH. The hazard stops being solid immediately, does a quick
## "pop" (inflate + squash over ~0.16 s) and then hands its debris to the
## track's shatter pool. Returns the colour to use for the debris.
var smashing := false
var _smash_t := 0.0

func smash() -> Color:
	if smashing or not live:
		return Color(1, 1, 1)
	smashing = true
	_smash_t = 0.0
	live = false                        # no further hits / scoring from it
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	collision_mask = 0
	set_physics_process(true)           # keep ticking for the pop animation
	var c := Color(1.0, 0.3, 0.6)
	var m = _mesh_inst.material_override
	if m is ShaderMaterial:
		var v = m.get_shader_parameter("neon_color")
		if v is Color:
			c = v
	elif m is StandardMaterial3D:
		c = m.albedo_color
	return c


func _tick_smash(delta: float) -> void:
	_smash_t += delta
	var k: float = _smash_t / 0.16
	if k >= 1.0:
		recycle()
		return
	# Inflate fast, then squash flat as it disappears (a cartoon pop).
	var inflate: float = 1.0 + 0.45 * sin(k * PI)
	var squash: float = 1.0 - k * k
	scale = Vector3(inflate * (1.0 + k * 0.6), inflate * squash, inflate)
	_mesh_inst.material_override = _mesh_inst.material_override


# ------------------------------------------------------------------ update

func _physics_process(delta: float) -> void:
	_t += delta
	if smashing:
		_tick_smash(delta)
		return
	match kind:
		Kind.MOVER:
			position.x = base_x + sin(_t * move_speed + phase) * move_range
			rotation.z = cos(_t * move_speed + phase) * 0.18
		Kind.SPIN:
			rotation.y += spin_speed * delta
		Kind.LASER:
			_tick_laser()
		Kind.PISTON:
			_tick_piston()
		Kind.ROTOR:
			rotation.z = (Sound.beat_pos() + phase) * (PI * 0.5) * spin_speed
		Kind.HUNTER:
			_tick_hunter(delta)
		Kind.PENDULUM:
			var a: float = PENDULUM_AMP * cos((Sound.beat_pos() + phase) * PI)
			rotation.z = a
			_parts[2].rotation.z = -a
		Kind.OBELISK:
			rotation.y = sin((Sound.beat_pos() + phase) * PI * 0.5) * 0.12
			_parts[0].rotation.y = rotation.y
			_parts[1].rotation.y = rotation.y
		Kind.DUSTWALL:
			position.x = base_x + sin((Sound.beat_pos() + phase) * PI * 0.5) * move_range
			rotation.y = sin((Sound.beat_pos() + phase) * PI) * 0.05
		Kind.CAB:
			position.x = base_x + sin((Sound.beat_pos() + phase) * PI * 0.5) * move_range
			rotation.y = sin((Sound.beat_pos() + phase) * PI * 0.5) * 0.12


func _tick_laser() -> void:
	# Off during the half-beat either side of the beat => on-beat arrival is safe.
	var c := Sound.beat_cycle(2.0, phase + 0.5)
	var on := c >= 0.5
	var charging := c > 0.4 and c < 0.5
	if on != laser_on:
		laser_on = on
		_mesh_inst.visible = on
	if charging:
		_parts[2].visible = int(_t * 30.0) % 2 == 0
	else:
		_parts[2].visible = not on
	if on and player != null and game != null:
		if overlaps_area(player):
			game.hit(self)


func _tick_piston() -> void:
	var p := Sound.beat_cycle(2.0, phase)
	var down := 0.0
	if p < 0.4:
		down = 0.0
	elif p < 0.5:
		down = smoothstep(0.4, 0.5, p)
	elif p < 0.75:
		down = 1.0
	else:
		down = 1.0 - smoothstep(0.75, 1.0, p)
	var y := lerpf(PISTON_UP, PISTON_DOWN, down)
	position.y = y
	var rail_center := 5.5
	_parts[0].position.y = rail_center - y
	_parts[1].position.y = rail_center - y


func _tick_hunter(delta: float) -> void:
	rotation.y += delta * 4.0
	position.y = 1.35 + sin(_t * 5.0) * 0.15
	if player == null or _locked:
		return
	var dist: float = player.global_position.z - global_position.z
	if dist < 24.0:
		_locked = true
		return
	var target: float = clampf(player.global_position.x, -TRACK_HALF + 1.6, TRACK_HALF - 1.6)
	position.x = move_toward(position.x, target, 7.5 * delta)
