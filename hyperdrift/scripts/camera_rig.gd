extends Node3D
## Chase camera with trauma shake, speed FOV kick, beat punch and a
## BEAT-CUT CINEMATIC MODE on sky structures: while the ship rides a corkscrew,
## loop, spiral or arc the camera cuts to a new shot on every bar (4 beats),
## eases between them, and rolls with the deck so the horizon turns over with
## the ship. Shake / cinematic can be toned down in SETTINGS > EFFECTS.

var target = null
var game = null
var trauma := 0.0
var dead_cam := false

@onready var cam: Camera3D = $Camera

var _noise := FastNoiseLite.new()
var _t := 0.0
var _pos := Vector3(0, 4.2, 10.0)
var _look := Vector3(0, 1.4, -14.0)
var _up := Vector3.UP
var _death_angle := 0.0
var _fov := 74.0
var _cine := 0.0
var _shot := 0
var _shot_bar := -1
var _shot_blend := 1.0
var _rail_blend := 0.0      # 0..1 how "on the structure" the framing is (eased)
var _fov_add_eased := 0.0   # eased per-shot FOV bonus

## Shots relative to the ship's rail frame: [offset, look offset, fov add].
## NOTE: the rail frame's basis.z points BACKWARD (forward travel = -z), so
## a positive offset.z is BEHIND the ship. All shots live on the trailing side.
const SHOTS := [
	[Vector3(0.0, 3.6, 12.0), Vector3(0.0, 1.2, -16.0), 6.0],    # close chase
	[Vector3(-7.0, 1.6, 7.0), Vector3(0.0, 1.0, -10.0), 4.0],    # low left trailing
	[Vector3(0.0, 8.5, 18.0), Vector3(0.0, 0.5, -22.0), 12.0],   # high wide over
	[Vector3(7.0, 1.5, 8.0), Vector3(0.0, 1.0, -10.0), 4.0],     # low right trailing
	[Vector3(-4.5, 4.5, 16.0), Vector3(0.0, 1.0, -14.0), 6.0],   # high left three-quarter
	[Vector3(4.5, 4.5, 16.0), Vector3(0.0, 1.0, -14.0), 6.0],    # high right three-quarter
]


func _ready() -> void:
	_noise.seed = 7
	_noise.frequency = 0.9
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cam.near = 0.08
	cam.far = 900.0
	cam.fov = _fov


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount * Persist.shake_amount, 0.0, 1.2)


func _process(delta: float) -> void:
	_t += delta
	trauma = maxf(0.0, trauma - delta * 1.55)
	if target == null:
		return

	var tp: Vector3 = target.global_position
	var boost: float = 0.0 if game == null else game.boost_visual
	var speed01: float = 0.0 if game == null else game.speed01()
	var beat: float = 0.0 if game == null else game.beat_pulse
	var on_rail: bool = target.on_rail
	# Ambient is a CONTINUOUS 0..1 weight (eased by main), not a boolean, so
	# the camera slides between the chase framing and the sky framing and
	# never pops when the passage begins or ends.
	var amb_w: float = 0.0 if game == null else game.ambient_weight
	var cine_on: bool = (on_rail and not dead_cam and Persist.cinematic_cam) or amb_w > 0.02
	_cine = lerpf(_cine, 1.0 if cine_on else 0.0, clampf(delta * 1.6, 0.0, 1.0))

	var want_pos: Vector3
	var want_look: Vector3
	var want_up := Vector3.UP
	var fov_add := 0.0

	if dead_cam:
		_death_angle += delta * 0.55
		var radius := 11.0
		want_pos = tp + Vector3(sin(_death_angle) * radius, 4.5 + sin(_death_angle * 0.6) * 1.2, cos(_death_angle) * radius)
		want_look = tp + Vector3(0, 0.8, 0)
		_pos = _pos.lerp(want_pos, clampf(delta * 2.2, 0.0, 1.0))
		_look = _look.lerp(want_look, clampf(delta * 3.0, 0.0, 1.0))
	elif on_rail:
		# ---- enter / exit blend -------------------------------------------
		# _rail_blend eases 0 -> 1 over ~1.1 s on entry and back on exit, so
		# the camera glides from the chase framing into the cinematic shots
		# instead of snapping.
		_rail_blend = minf(1.0, _rail_blend + delta * 0.9)
		# New shot every 4 bars (16 beats). Crossfade is slow (delta * 0.7)
		# so successive shots morph into each other over ~1.4 s.
		var bar_i := int(floorf(Sound.beat_pos() / 4.0))
		if bar_i != _shot_bar:
			_shot_bar = bar_i
			if Persist.cinematic_cam:
				var step := 1 + (bar_i % 3)
				_shot = (_shot + step) % SHOTS.size()
			else:
				_shot = 0
			_shot_blend = 0.0
		_shot_blend = minf(1.0, _shot_blend + delta * 0.7)
		var f: Transform3D = target.rail_frame
		var s: Array = SHOTS[_shot]
		var off: Vector3 = s[0]
		var loff: Vector3 = s[1]
		# FOV bonus eases in slowly instead of jumping per shot.
		_fov_add_eased = lerpf(_fov_add_eased, float(s[2]), clampf(delta * 2.0, 0.0, 1.0))
		fov_add = _fov_add_eased
		# Gentle beat-driven dolly along the shot's own axis.
		var sway := sin(Sound.beat_pos() * PI * 0.5) * 0.8 * _shot_blend
		var shot_pos: Vector3 = f.origin + f.basis.x * (off.x + sway) + f.basis.y * off.y + f.basis.z * off.z
		var shot_look: Vector3 = f.origin + f.basis.x * loff.x + f.basis.y * loff.y + f.basis.z * loff.z
		# Mix the CURRENT camera position toward the shot target: at the start
		# of the blend want ~= _pos (no jump), at full blend want = shot.
		var rb: float = _rail_blend * _rail_blend * (3.0 - 2.0 * _rail_blend)
		want_pos = _pos.lerp(shot_pos, rb)
		want_look = _look.lerp(shot_look, rb)
		want_up = _up.lerp(f.basis.y, rb).normalized()
		var k := clampf(delta * (3.0 + 3.0 * _shot_blend), 0.0, 1.0)
		_pos = _pos.lerp(want_pos, k)
		_look = _look.lerp(want_look, clampf(delta * 4.0, 0.0, 1.0))
		# Safety net: a shot must stay BEHIND the ship. The rail frame's
		# basis.z points BACKWARD, so a trailing camera has a positive dot with
		# basis.z. If that ever goes < 2 (camera too close / in front), clamp
		# it to a trailing position so the ship stays in frame.
		var cam_behind: float = (_pos - f.origin).dot(f.basis.z)
		if cam_behind < 2.0:
			_pos = f.origin + f.basis.z * 5.0 + f.basis.y * 3.0
	else:
		_rail_blend = maxf(0.0, _rail_blend - delta * 1.2)
		# ---- normal chase framing
		var chase_pos := Vector3(
			clampf(tp.x * 0.62, -5.2, 5.2),
			maxf(tp.y, 0.9) * 0.55 + 3.05 + boost * 0.25,
			tp.z + 9.6 + boost * 1.4 + speed01 * 0.8)
		var chase_look := Vector3(tp.x * 0.35, maxf(tp.y, 0.8) * 0.4 + 1.35, tp.z - 16.0)
		# ---- ambient sky framing: a high, wide crane shot that stays BEHIND
		# the ship (positive z) and only sways side to side. It never orbits
		# around to the front.
		var sway := sin(_t * 0.18) * 11.0
		var sky_pos := Vector3(
			tp.x * 0.5 + sway,
			tp.y + 9.0 + sin(_t * 0.4) * 1.2,
			tp.z + 24.0)
		var sky_look := Vector3(tp.x * 0.3, tp.y + 0.6, tp.z - 22.0)
		# Blend by the continuous ambient weight (smoothstep for a soft ease).
		var w: float = amb_w * amb_w * (3.0 - 2.0 * amb_w)
		want_pos = chase_pos.lerp(sky_pos, w)
		want_look = chase_look.lerp(sky_look, w)
		# Slower follow while ambient so the glide feels floaty.
		var follow: float = lerpf(8.5, 1.6, w)
		_pos = _pos.lerp(want_pos, clampf(delta * follow, 0.0, 1.0))
		_pos.z = clampf(_pos.z, tp.z + 7.6, tp.z + lerpf(14.5, 30.0, w))
		_look = _look.lerp(want_look, clampf(delta * lerpf(7.0, 2.2, w), 0.0, 1.0))
		_shot_bar = -1

	_up = _up.slerp(want_up, clampf(delta * 3.0, 0.0, 1.0)).normalized()
	global_position = _pos
	var fwd := (_look - _pos)
	if fwd.length() > 0.01 and absf(fwd.normalized().dot(_up)) < 0.995:
		look_at(_look, _up)

	var want_fov := 74.0 + speed01 * 15.0 + boost * 11.0 + fov_add * _cine
	if dead_cam:
		want_fov = 62.0
	# Ambient: widen and breathe, blended by weight so there is no FOV pop.
	want_fov = lerpf(want_fov, 62.0 + 3.0 * sin(_t * 0.25), amb_w)
	_fov = lerpf(_fov, want_fov, clampf(delta * 3.2, 0.0, 1.0))

	var s2 := trauma * trauma
	cam.position = Vector3(
		_noise.get_noise_2d(_t * 80.0, 0.0) * s2 * 1.05,
		_noise.get_noise_2d(0.0, _t * 80.0) * s2 * 0.85,
		_noise.get_noise_2d(_t * 55.0, 55.0) * s2 * 0.5)
	cam.rotation.z = _noise.get_noise_2d(_t * 60.0, 120.0) * s2 * 0.16
	cam.fov = _fov + s2 * 3.5 + beat * (1.4 + 2.6 * _cine)


func reset() -> void:
	dead_cam = false
	trauma = 0.0
	_death_angle = 0.0
	_cine = 0.0
	_rail_blend = 0.0
	_fov_add_eased = 0.0
	_up = Vector3.UP
	_shot = 0
	_shot_bar = -1
	_shot_blend = 1.0
	_pos = Vector3(0, 4.2, 10.0)
	_look = Vector3(0, 1.4, -14.0)
	rotation = Vector3.ZERO
