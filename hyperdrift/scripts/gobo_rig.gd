extends Node3D
## CONCERT MOVING-HEAD GOBO RIG.
##
## A pool of rooftop fixtures, each firing a fan of five long beams (like the
## reference photo). All beams live in ONE MultiMesh, so 20 fixtures × 5 beams
## cost a single draw call. Every fixture runs one of several programs and all
## of them are clocked by the beat:
##
##   FAN      the fan opens/closes on each beat
##   SWEEP    slow pan across the road, direction flips every bar
##   NOD      tilt nods on every beat, pan drifts
##   CHASE    beams light up one after another on 8th notes
##   CROSS    two fixtures cross their fans on the downbeat
##   STROBE   during a DROP every fixture strobes on 16ths
##
## Program speed scales with Sound.spike / Sound.intensity, so lights get
## frantic exactly when the music does. Toggle + brightness live in SETTINGS.

const V := preload("res://scripts/visuals.gd")

const FIXTURES := 20
const BEAMS := 5
const BEAM_LEN := 82.0
enum Program { FAN, SWEEP, NOD, CHASE, CROSS }

var brightness := 0.8
var enabled := true

var _heads: Array[Node3D] = []
var _prog: Array[int] = []
var _seed: Array[float] = []
var _side: Array[float] = []
# Eased per-fixture state for SMOOTH motion between cuts. Every fixture
# holds its own pan/tilt/spread/beam_gain so motion is continuous, not stepped.
var _pan: PackedFloat32Array = PackedFloat32Array()
var _tilt: PackedFloat32Array = PackedFloat32Array()
var _spread: PackedFloat32Array = PackedFloat32Array()
var _lit: PackedFloat32Array = PackedFloat32Array()  # which beam index is bright (CHASE)
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _beam_mat: StandardMaterial3D
var _base_color := Color(0.72, 0.85, 1.0)
var _accent := Color(1.0, 0.3, 0.75)
var _spike_color := Color(1.0, 1.0, 1.0)  # colour to flash toward on each spike
var _spike_flash := 0.0                     # 0..1, decays after a spike
var _drop_t := 0.0
var _t := 0.0


func _ready() -> void:
	var head_mat := V.metal_material(Color(0.03, 0.03, 0.06), 0.9, 0.2, Color(0.6, 0.85, 1.0), 2.0)
	var lens_mat := V.glow_material(Color(0.85, 0.95, 1.0), 6.0)
	for i in FIXTURES:
		var h := Node3D.new()
		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.45
		bm.bottom_radius = 0.55
		bm.height = 0.5
		bm.radial_segments = 10
		base.mesh = bm
		base.material_override = head_mat
		base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(base)
		var yoke := MeshInstance3D.new()
		var ym := BoxMesh.new()
		ym.size = Vector3(1.4, 0.9, 0.7)
		yoke.mesh = ym
		yoke.material_override = head_mat
		yoke.position = Vector3(0, 0.7, 0)
		yoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(yoke)
		var lens := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.32
		lm.height = 0.64
		lm.radial_segments = 10
		lm.rings = 6
		lens.mesh = lm
		lens.material_override = lens_mat
		lens.position = Vector3(0, 0.7, 0.4)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(lens)
		h.position = Vector3(0, -500, 0)
		add_child(h)
		_heads.append(h)
		_prog.append(i % 5)
		_seed.append(randf() * TAU)
		_side.append(1.0)
		_pan.append(0.0)
		_tilt.append(-0.95)
		_spread.append(0.22)
		_lit.append(0.0)

	# One long thin additive beam mesh shared by every instance. Built by hand
	# (not a CylinderMesh) so it can carry a per-vertex colour gradient: full
	# brightness at the fixture, fading to fully transparent at the far tip.
	# Slightly thicker near field + wider far spread: visible like concert heads,
	# but still translucent enough not to wash out the skyline.
	var beam := _make_beam_mesh(BEAM_LEN, 0.24, 1.55)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.vertex_color_use_as_albedo = true
	_beam_mat.albedo_color = Color(1, 1, 1, 1)
	_beam_mat.disable_receive_shadows = true
	_beam_mat.no_depth_test = false
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = beam
	_mm.instance_count = FIXTURES * BEAMS
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = _beam_mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	Sound.drop.connect(_on_drop)
	Sound.spike_started.connect(_on_spike)
	set_enabled(Persist.gobos)
	brightness = Persist.gobo_brightness


## Builds an open cone (thin at the fixture, wide at the far end) with a
## vertex-colour alpha gradient 1 -> 0 so the beam fades out toward its tip.
static func _make_beam_mesh(len: float, r_near: float, r_far: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var segs := 14
	for ring in 2:  # 0 = near (fixture), 1 = far tip
		var rad := r_near if ring == 0 else r_far
		var y := -len * 0.5 if ring == 0 else len * 0.5
		var a := 1.0 if ring == 0 else 0.0
		for s in segs + 1:  # extra column closes the wrap
			var ang := float(s) / float(segs) * TAU
			var nrm := Vector3(cos(ang), 0.0, sin(ang))
			st.set_normal(nrm)
			# Slight gamma on the fade so the beam stays visible most of its
			# length and only really dissolves near the tip.
			var aa: float = pow(a, 0.55)
			st.set_color(Color(1, 1, 1, aa))
			st.add_vertex(Vector3(cos(ang) * rad, y, sin(ang) * rad))
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


func set_colors(base: Color, accent: Color) -> void:
	_base_color = base
	_accent = accent


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	set_process(on)


func _on_drop(_strength: float) -> void:
	_drop_t = 4.0


## On every beat spike, flash the beams to a fresh vivid colour.
func _on_spike(strength: float) -> void:
	var hues := [
		Color(1.0, 0.2, 0.55), Color(0.3, 1.0, 0.8), Color(1.0, 0.85, 0.2),
		Color(0.6, 0.4, 1.0), Color(0.2, 0.9, 1.0), Color(1.0, 0.45, 0.1),
	]
	_spike_color = hues[int(_t * 7.3) % hues.size()]
	_spike_flash = maxf(_spike_flash, clampf(strength, 0.35, 1.0))


var _next := 0
func place_fixture(pos: Vector3, seed_i: int) -> void:
	var h := _heads[_next]
	_next = (_next + 1) % FIXTURES
	h.position = pos
	_side[_heads.find(h)] = -1.0 if pos.x > 0.0 else 1.0
	_prog[_heads.find(h)] = seed_i % 5
	# Aim each fixture toward the road below and slightly ahead, then let the
	# beat programs fan/sweep around this grounded target.
	h.look_at(Vector3(0.0, 0.0, pos.z - 18.0), Vector3.UP)


func _process(delta: float) -> void:
	if not enabled:
		return
	_t += delta
	_drop_t = maxf(0.0, _drop_t - delta)
	_spike_flash = maxf(0.0, _spike_flash - delta * 1.4)
	var bp: float = Sound.beat_pos()
	var beat_frac := fposmod(bp, 1.0)
	var pulse := exp(-beat_frac * 6.0)
	var spike: float = Sound.spike
	var fast := 1.0 + spike * 2.6 + Sound.intensity * 0.8
	var strobe := _drop_t > 0.0 or Sound.drop_active
	var bar_i := int(floorf(bp / 4.0))
	var bright := brightness * (0.55 + 0.45 * Sound.intensity + pulse * 0.45)
	if strobe:
		bright *= 1.0 if fposmod(bp * 4.0, 1.0) < 0.5 else 0.15
	# Base colour drifts toward the accent with sustained energy, then shifts its
	# palette according to the DOMINANT musical layer: bass gets warm low beams,
	# drones get violet washes, melody gets blue/teal follow spots and percussion
	# gets short white-gold spark beams.
	var col := _base_color.lerp(_accent, clampf(spike * 1.5, 0.0, 1.0))
	match Sound.dominant_layer:
		"BASS":
			col = col.lerp(Color(1.0, 0.34, 0.16), 0.48)
			bright *= 1.0 + Sound.bass_pulse * 0.32
		"DRONE":
			col = col.lerp(Color(0.46, 0.30, 1.0), 0.48)
			bright *= 0.72 + Sound.drone * 0.38
		"MELODY":
			col = col.lerp(Color(0.25, 0.90, 1.0), 0.56)
			bright *= 0.82 + Sound.melody * 0.45
		"PERCUSSION":
			col = col.lerp(Color(1.0, 0.86, 0.52), 0.54)
			bright *= 0.72 + Sound.transient * 0.70
	col = col.lerp(_spike_color, _spike_flash)
	bright *= 1.0 + _spike_flash * 0.8

	# Easing time: faster during a drop / spike so lights feel responsive,
	# gentler during quiet sections.
	var ease: float = clampf(delta * (4.5 + spike * 8.0 + (1.0 if strobe else 0.0)), 0.0, 1.0)

	for i in FIXTURES:
		var h := _heads[i]
		if h.position.y < -100.0:
			for b in BEAMS:
				_mm.set_instance_color(i * BEAMS + b, Color(0, 0, 0, 0))
			continue
		var sd := _seed[i]
		# ---- Compute TARGET pan / tilt / spread / lit for this fixture ----
		var t_pan := 0.0
		var t_tilt := -0.95
		var t_spread := 0.22
		var t_lit := 0.0
		match _prog[i]:
			Program.FAN:
				# Breathing fan: spread pulses with the music, pan drifts.
				t_spread = 0.10 + 0.30 * (1.0 - pulse)
				t_pan = sin(_t * 0.45 * fast + sd) * 0.45
				t_tilt = -0.95 + 0.08 * sin(_t * 0.6 + sd)
			Program.SWEEP:
				# Slow horizontal pan that wraps smoothly across bars.
				var sweep: float = fposmod(_t * 0.18 * fast + sd, TAU)
				t_pan = sin(sweep) * 0.95
				t_tilt = -0.85 + 0.18 * sin(_t * 0.7 + sd)
				t_spread = 0.18 + 0.06 * sin(sweep * 2.0)
			Program.NOD:
				# Tilt nods on every beat, pan drifts slowly.
				t_tilt = -1.15 + 0.45 * pulse + 0.06 * sin(_t * 0.9)
				t_pan = sin(_t * 0.32 * fast + sd) * 0.55
				t_spread = 0.18
			Program.CHASE:
				# The lit beam advances smoothly across the fan — not a step.
				t_lit = fposmod(_t * 0.8 * fast + sd, float(BEAMS))
				t_pan = sin(_t * 0.22 + sd) * 0.4
				t_spread = 0.28
				t_tilt = -0.92 + 0.08 * sin(_t * 0.5)
			Program.CROSS:
				# Two fixtures sweep toward / away from the centre, crossed.
				var breathe: float = (1.0 + sin(_t * 0.6 * fast + sd)) * 0.5
				t_pan = _side[i] * lerpf(0.95, 0.05, breathe)
				t_tilt = -0.78 + 0.08 * sin(_t * 0.4)
				t_spread = 0.14 + 0.10 * pulse
		if strobe:
			t_spread += 0.06 * sin(_t * 18.0 + sd)
			t_pan += 0.15 * sin(_t * 9.0 + sd)

		# ---- Smoothly ease toward the targets (no snapping). ----
		_pan[i] = lerpf(_pan[i], t_pan, ease)
		_tilt[i] = lerpf(_tilt[i], t_tilt, ease)
		_spread[i] = lerpf(_spread[i], t_spread, ease)
		# For CHASE we also ease the lit-beam index toward its target so the
		# "spotlight" travels across the fan instead of teleporting each beat.
		var lit_diff: float = t_lit - _lit[i]
		# Wrap the difference so easing goes the short way around.
		if lit_diff > 2.5:
			lit_diff -= float(BEAMS)
		elif lit_diff < -2.5:
			lit_diff += float(BEAMS)
		_lit[i] = _lit[i] + lit_diff * ease

		# ---- Write per-instance transforms and colours. ----
		var base_basis := h.global_transform.basis
		var pan := _pan[i]
		var tilt := _tilt[i]
		var spread := _spread[i]
		var per_beam_gain := [1.0, 1.0, 1.0, 1.0, 1.0]
		if _prog[i] == Program.CHASE:
			# Gaussian-style brightness around the moving lit position so the
			# spot looks like a real gobo, not a hard blink.
			var lit_pos := _lit[i]
			for b in BEAMS:
				var d: float = abs(float(b) - lit_pos)
				d = minf(d, float(BEAMS) - d)  # wrap distance
				per_beam_gain[b] = exp(-d * d * 2.5) * 1.0 + 0.18
		for b in BEAMS:
			var a := (float(b) - float(BEAMS - 1) * 0.5) * spread
			var rot := Basis(Vector3.UP, pan + a) * Basis(Vector3.RIGHT, tilt)
			var dir := (base_basis * rot).z * -1.0
			var origin := h.global_position + Vector3(0, 0.7, 0)
			var mid := origin + dir * BEAM_LEN * 0.5
			# Cylinder mesh points along its local Y; align Y with dir.
			var y_axis := dir
			var x_axis := y_axis.cross(Vector3.UP)
			if x_axis.length() < 0.01:
				x_axis = Vector3.RIGHT
			x_axis = x_axis.normalized()
			var z_axis := x_axis.cross(y_axis).normalized()
			var basis := Basis(x_axis, y_axis, z_axis)
			_mm.set_instance_transform(i * BEAMS + b, Transform3D(basis, mid))
			var g: float = float(bright) * per_beam_gain[b]
			_mm.set_instance_color(i * BEAMS + b, Color(col.r * g * 1.4, col.g * g * 1.4, col.b * g * 1.4, clampf(0.05 + 0.12 * g, 0.0, 0.35)))
