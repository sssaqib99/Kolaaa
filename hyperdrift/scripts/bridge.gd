extends Node3D
## SKY STRUCTURES — four rail bridges the highway can turn into:
##
##   ARC        gentle banking sky-bridge (the original)
##   CORKSCREW  one full 360° barrel roll around the travel axis
##   LOOP       a true vertical loop-de-loop (ship goes upside down)
##   SPIRAL     a two-turn spiral highway climbing around a tower and back down
##
## Every type is a smooth parametric path u∈[0,1] -> Transform3D. While the
## ship is on a structure it rides the frame ("magnetic rails"): lateral input
## slides along the frame's X, jumps go along the frame's Y, gravity always
## pulls back onto the deck. The frames start and end level at ground height so
## the hand-over from / to the flat highway is seamless.
##
## A double helix of light wraps the path and spins in lock-step with the beat.
## The deck is lined with XP crystals + XP rings. No hazards spawn on a structure.

const V := preload("res://scripts/visuals.gd")

enum Kind { ARC, CORKSCREW, LOOP, SPIRAL }

const SEG_N := 96
const HELIX_N := 96
const DECK_W := 31.4        # default highway width (matches the 14.7 half-track + shoulders)
const DECK_W_LOOP := 19.0   # the hoop section is narrower so its two sides clear
const PYLON_N := 40

var kind: int = Kind.ARC
var active := false
var start_z := 0.0
var end_z := 0.0
var length := 300.0      # path length (approx) - used for progress speed
var pulse := 0.0

var _segs: Array[Node3D] = []
var _pylons: Array[MeshInstance3D] = []
var _portals: Array[Node3D] = []
var _helix: Array[MultiMeshInstance3D] = []
var _deck_mat: StandardMaterial3D
var _rail_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _swirl_mat: StandardMaterial3D
var _swirl_a := V.CYAN
var _swirl_b := V.MAGENTA
var _seg_len := 10.0
var _deck_meshes: Array[BoxMesh] = []
var _rail_nodes: Array[MeshInstance3D] = []
var _strip_meshes: Array[BoxMesh] = []
var _rail_meshes: Array[BoxMesh] = []
var deck_width := 29.0


func _ready() -> void:
	_deck_mat = V.metal_material(Color(0.04, 0.02, 0.09), 0.85, 0.3, V.CYAN, 0.25)
	_rail_mat = V.metal_material(Color(0.03, 0.02, 0.06), 0.9, 0.2, V.CYAN, 3.0)
	_glow_mat = V.glow_material(V.CYAN, 2.5)
	_swirl_mat = V.glow_material(Color(1, 1, 1), 2.6)

	for i in SEG_N:
		var seg := Node3D.new()
		var deck := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(DECK_W, 0.8, 1.0)
		deck.mesh = dm
		_deck_meshes.append(dm)
		deck.material_override = _deck_mat
		deck.position = Vector3(0, -0.4, 0)
		seg.add_child(deck)
		for s in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.5, 1.3, 1.0)
			rail.mesh = rm
			_rail_meshes.append(rm)
			rail.material_override = _rail_mat
			rail.position = Vector3(s * (DECK_W * 0.5 - 0.3), 0.5, 0.0)
			_rail_nodes.append(rail)
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			seg.add_child(rail)
		var strip := MeshInstance3D.new()
		var stm := BoxMesh.new()
		stm.size = Vector3(DECK_W - 2.0, 0.2, 1.0)
		strip.mesh = stm
		_strip_meshes.append(stm)
		strip.material_override = _glow_mat
		strip.position = Vector3(0.0, -0.9, 0.0)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.add_child(strip)
		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(2.4, 0.15, 0.4)
		lamp.mesh = lm
		lamp.material_override = _glow_mat
		lamp.position = Vector3(0.0, 0.05, 0.0)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.add_child(lamp)
		add_child(seg)
		_segs.append(seg)

	for i in PYLON_N:
		var py := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(1.6, 1.0, 1.6)
		py.mesh = pm
		py.material_override = _deck_mat
		py.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(py)
		_pylons.append(py)

	for i in 2:
		var portal := Node3D.new()
		for s in [-1.0, 1.0]:
			var col := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(1.2, 18.0, 1.2)
			col.mesh = cm
			col.material_override = _rail_mat
			col.position = Vector3(s * 16.5, 9.0, 0.0)
			portal.add_child(col)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(34.0, 1.2, 1.2)
		beam.mesh = bm
		beam.material_override = _rail_mat
		beam.position = Vector3(0.0, 18.0, 0.0)
		portal.add_child(beam)
		add_child(portal)
		_portals.append(portal)

	var shard := BoxMesh.new()
	shard.size = Vector3(1.0, 1.0, 1.0)
	for h in 2:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = shard
		mm.instance_count = HELIX_N
		mmi.multimesh = mm
		mmi.material_override = _swirl_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_helix.append(mmi)
	clear()


# ------------------------------------------------------------------ profiles

static func _ss(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


## Path position for parameter u (0 = entry, 1 = exit), relative to start_z.
func _pos(u: float) -> Vector3:
	match kind:
		Kind.CORKSCREW:
			# True barrel roll: the ship rides a CIRCLE in the X/Y plane (centred
			# at y = r) while advancing linearly in Z. At u=0 the ship is at the
			# BOTTOM of the circle, exactly on road level, so the structure starts
			# and ends connected to the ground. One full rotation, no
			# self-intersection (each Z slice is a clean circle).
			var r := 16.0
			# Smoothstep phase has zero lateral/vertical velocity at the road
			# connection, removing the sharp first-frame barrel-roll snap.
			var phi := TAU * _ss(u)
			return Vector3(sin(phi) * r, r - cos(phi) * r, -330.0 * u)
		Kind.LOOP:
			# LOOP-DE-LOOP as a leaning vertical hoop. Both ends of the hoop face
			# connect to the ROAD (x = 0, y = 0) instead of the hoop closing on
			# itself, and the exit sits 40 m further along — so the ship always
			# leaves. The lateral sway (x = A*sin(TAU*u)) pushes the ascending
			# and descending sides of the hoop onto opposite lanes, which is what
			# keeps the deck ribbons apart (verified 33 m clearance vs an 18 m
			# hoop deck). The exit Z is well past the entry gate, so the ship can
			# never re-enter and spin forever.
			var r := 26.0
			var lead := 40.0
			var sway := 32.0
			var phi := TAU * _ss(u)
			var x := sway * sin(phi)             # 0 at both ends -> joins the road
			var y := r - cos(phi) * r            # 0 at entry/exit, 2r = 52 m at the top
			var z := -sin(phi) * r - lead * u    # vertical circle + forward progress
			return Vector3(x, y, z)
		Kind.SPIRAL:
			# One big sweeping turn around a vertical axis (a 360° spiral
			# highway) with a height arc. A single turn is used so the deck
			# can never cross itself — two turns would collide mid-way.
			var r := 40.0
			var th := TAU * _ss(u)
			# Squared sine has a flat tangent at both road connections.
			var h := 30.0 * pow(sin(PI * u), 2.0)
			return Vector3(r - cos(th) * r, h, -280.0 * u - sin(th) * r * 0.5)
		_:
			var hgt := 16.0 * pow(sin(PI * u), 2.0)
			return Vector3(0.0, hgt, -300.0 * u)


## Desired "up" for the deck at u (before orthonormalisation).
func _up(u: float, p: Vector3) -> Vector3:
	match kind:
		Kind.CORKSCREW:
			# The deck's up points FROM THE SHIP TOWARD THE CIRCLE CENTRE.
			# This MUST stay in phase with _pos (same phi = TAU * u) or the deck
			# ribbon twists through the path. At u=0/1 the centre is directly
			# above so up = world-up — entry/exit connect flat, no blend needed.
			var phi := TAU * _ss(u)
			var centre := Vector3(0.0, 16.0, p.z)
			var to_c := centre - p
			if to_c.length() < 0.01:
				return Vector3.UP
			return to_c.normalized()
		Kind.LOOP:
			# Deck up always points from the ship toward the hoop centre which
			# drifts forward with u (matching _pos). World-up at entry/exit
			# (bottom of the hoop), world-down at the top (inverted).
			var centre := Vector3(0.0, 26.0, -40.0 * u)
			var to_c := centre - p
			if to_c.length() < 0.01:
				return Vector3.UP
			return to_c.normalized()
		Kind.SPIRAL:
			var th := TAU * _ss(u)
			var centre := Vector3(40.0, p.y, -280.0 * u - sin(th) * 40.0 * 0.5)
			var inward := centre - p
			inward.y = 0.0
			var bank := 0.42 * sin(PI * u)
			return (Vector3.UP + inward.normalized() * bank).normalized()
		_:
			var roll := 0.2 * sin(TAU * u) * sin(PI * u)
			return Vector3(-sin(roll), cos(roll), 0.0)


## Full frame at u: origin in world space, basis.z = -forward, basis.y = deck up.
func frame_at(u: float) -> Transform3D:
	u = clampf(u, 0.0, 1.0)
	var e := 0.0025
	var p := _pos(u)
	var pa := _pos(clampf(u - e, 0.0, 1.0))
	var pb := _pos(clampf(u + e, 0.0, 1.0))
	var fwd := (pb - pa)
	if fwd.length() < 0.0001:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var up := _up(u, p)
	up = (up - fwd * up.dot(fwd)).normalized()
	if up.length() < 0.01:
		up = Vector3.UP
	var right := up.cross(-fwd).normalized()
	# basis columns: x = right, y = up, z = back
	var basis := Basis(right, up, -fwd)
	return Transform3D(basis, Vector3(p.x, p.y, start_z + p.z))


func frame_at_progress(s: float) -> Transform3D:
	return frame_at(s / length)


func _measure_length() -> float:
	var l := 0.0
	var prev := _pos(0.0)
	for i in range(1, 121):
		var p := _pos(float(i) / 120.0)
		l += p.distance_to(prev)
		prev = p
	return l


func kind_name() -> String:
	match kind:
		Kind.CORKSCREW: return "CORKSCREW"
		Kind.LOOP: return "LOOP-DE-LOOP"
		Kind.SPIRAL: return "SPIRAL HIGHWAY"
		_: return "SKYBRIDGE"


func contains(z: float) -> bool:
	return active and z <= start_z and z >= end_z


## Hazard exclusion zone.
func blocks(z: float) -> bool:
	return active and z <= start_z + 40.0 and z >= end_z - 40.0


## Lateral lane for the XP crystals.
func lane_x(u: float) -> float:
	return 8.0 * sin(TAU * 2.0 * u)


# ------------------------------------------------------------------- control

## Resizes the pooled deck / rail / strip meshes to the current deck_width.
func _apply_deck_width() -> void:
	var w := deck_width
	for dm in _deck_meshes:
		dm.size = Vector3(w, 0.8, 1.0)
	for sm in _strip_meshes:
		sm.size = Vector3(maxf(w - 2.0, 4.0), 0.2, 1.0)
	var i := 0
	for rm in _rail_meshes:
		rm.size = Vector3(0.5, 1.3, 1.0)
		i += 1
	i = 0
	for rn in _rail_nodes:
		var side := -1.0 if (i % 2 == 0) else 1.0
		rn.position = Vector3(side * (w * 0.5 - 0.3), 0.5, 0.0)
		i += 1


func place(z0: float, k: int, vis: Dictionary) -> void:
	kind = k
	start_z = z0
	length = _measure_length()
	end_z = start_z + _pos(1.0).z
	active = true
	visible = true
	var b: Dictionary = vis["bridge"]
	var deck_c: Color = b["deck"]
	var rail_c: Color = b["rail"]
	_swirl_a = b["swirl_a"]
	_swirl_b = b["swirl_b"]
	_deck_mat.albedo_color = deck_c
	_deck_mat.emission = rail_c
	_rail_mat.emission = rail_c
	_glow_mat.albedo_color = Color(rail_c.r * 2.5, rail_c.g * 2.5, rail_c.b * 2.5, 1.0)

	# The loop hoop uses a narrower deck so its two sides never meet; every
	# other structure uses the full highway width.
	deck_width = DECK_W_LOOP if kind == Kind.LOOP else DECK_W
	_apply_deck_width()

	_seg_len = length / float(SEG_N) + 0.6
	for i in SEG_N:
		var u := (float(i) + 0.5) / float(SEG_N)
		var seg := _segs[i]
		seg.global_transform = frame_at(u)
		seg.scale = Vector3(1.0, 1.0, _seg_len)
		seg.visible = true

	var pi_ := 0
	for i in range(0, SEG_N, 3):
		var u := (float(i) + 0.5) / float(SEG_N)
		var f := frame_at(u)
		# Only drop pylons where the deck is (roughly) upright and off the ground.
		if f.basis.y.y < 0.55 or f.origin.y < 1.5:
			continue
		for s in [-1.0, 1.0]:
			if pi_ >= _pylons.size():
				break
			var py := _pylons[pi_]
			pi_ += 1
			var foot: Vector3 = f.origin + f.basis.x * float(s) * (deck_width * 0.5 - 2.5)
			var h: float = foot.y + 2.5
			py.visible = true
			py.scale = Vector3(1.0, h, 1.0)
			py.position = Vector3(foot.x, h * 0.5 - 2.5, foot.z)
	while pi_ < _pylons.size():
		_pylons[pi_].visible = false
		pi_ += 1

	_portals[0].global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, start_z + 4.0))
	var fe := frame_at(1.0)
	_portals[1].global_transform = Transform3D(Basis.IDENTITY, Vector3(fe.origin.x, 0.0, fe.origin.z - 4.0))
	for p in _portals:
		p.visible = true

	for h in _helix.size():
		var mm: MultiMesh = _helix[h].multimesh
		for i in HELIX_N:
			var u := (float(i) + 0.5) / float(HELIX_N)
			var kk := 0.5 + 0.5 * sin(u * TAU * 2.0 + float(h) * PI)
			mm.set_instance_color(i, _swirl_a.lerp(_swirl_b, kk))
		_helix[h].visible = true
	_update_helix()


func clear() -> void:
	active = false
	visible = false
	for s in _segs:
		s.visible = false
	for p in _pylons:
		p.visible = false
	for p in _portals:
		p.visible = false
	for h in _helix:
		h.visible = false


func _process(delta: float) -> void:
	if not active:
		return
	pulse = maxf(0.0, pulse - delta * 3.0)
	_update_helix()
	_swirl_mat.albedo_color = Color(1, 1, 1) * (2.4 + pulse * 2.2)
	_rail_mat.emission_energy_multiplier = 3.0 + pulse * 2.5


func _update_helix() -> void:
	var spin: float = Sound.beat_pos() * (TAU / 8.0)
	var seg_len := length / float(HELIX_N) * 1.35
	var radius := 17.5 if kind == Kind.ARC else 13.0
	for h in _helix.size():
		var mm: MultiMesh = _helix[h].multimesh
		var off := float(h) * PI
		for i in HELIX_N:
			var u := (float(i) + 0.5) / float(HELIX_N)
			var f := frame_at(u)
			var theta := u * TAU * 3.0 + spin + off
			var r := radius * (0.75 + 0.25 * sin(PI * u))
			var pos := f.origin + f.basis.y * 4.5 + f.basis.x * (r * cos(theta)) + f.basis.y * (r * sin(theta))
			var basis := f.basis.rotated(f.basis.z, theta)
			basis = basis.scaled(Vector3(0.55, 1.5, seg_len))
			mm.set_instance_transform(i, Transform3D(basis, pos))
