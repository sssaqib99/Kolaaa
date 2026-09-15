extends RefCounted
## Shared hovercraft construction + metadata.
##
## Both the in-game ship (player.gd) and the live hangar preview
## (ship_preview.gd, used by SETTINGS > HANGAR and the title-screen HANGAR
## overlay) build their models from here, so what you see while selecting is
## exactly what you fly. Everything is still procedural primitives: no assets.

const V := preload("res://scripts/visuals.gd")
const MUSIC_FLARE_SHADER: Shader = preload("res://shaders/music_flare.gdshader")

const SHIP_VECTOR := 0
const SHIP_PHANTOM := 1
const SHIP_COUNT := 2


static func ship_name(id: int) -> String:
	return "PHANTOM" if id == SHIP_PHANTOM else "VECTOR"


static func ship_tagline(id: int) -> String:
	if id == SHIP_PHANTOM:
		return "Art Deco heavy cruiser  •  violet engines"
	return "Agile neon interceptor  •  cyan engines"


static func ship_desc(id: int) -> String:
	if id == SHIP_PHANTOM:
		return "A lower, broader Art Deco cruiser: long wedge hull, swept chrome-edged wings, violet engine pods and an exhaust spine. Same fair collision and handling as Vector — pure presence."
	return "The original neon dart: cone nose, glass canopy, magenta winglets and twin cyan pods. Same fair collision and handling as Phantom — pure agility."


## Display rows of [LABEL, VALUE] for the hangar UI.
static func ship_specs(id: int) -> Array:
	if id == SHIP_PHANTOM:
		return [
			["CLASS", "HEAVY CRUISER"],
			["HULL", "DECO WEDGE"],
			["ENGINES", "TWIN VIOLET"],
			["ACCENT", "CHROME + VIOLET"],
			["HANDLING", "IDENTICAL"],
		]
	return [
		["CLASS", "INTERCEPTOR"],
		["HULL", "NEON DART"],
		["ENGINES", "TWIN CYAN"],
		["ACCENT", "MAGENTA + CYAN"],
		["HANDLING", "IDENTICAL"],
	]


static func ship_accent(id: int) -> Color:
	return V.VIOLET if id == SHIP_PHANTOM else V.CYAN


static func ship_engine_color(id: int) -> Color:
	return V.VIOLET if id == SHIP_PHANTOM else V.CYAN


static func add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


## VECTOR interceptor hull. Returns the engine glow rings (pulsed by whoever
## owns the model).
static func build_vector(parent: Node3D) -> Array:
	var glows: Array = []
	var hull := V.metal_material(Color(0.07, 0.08, 0.13), 0.95, 0.17, Color.BLACK, 0.0)
	var accent := V.metal_material(Color(0.03, 0.03, 0.06), 1.0, 0.12, V.MAGENTA, 2.6)
	var trim := V.metal_material(Color(0.02, 0.05, 0.07), 1.0, 0.1, V.CYAN, 3.2)
	var glass := V.glow_material(Color(0.35, 0.95, 1.0), 2.2, false)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.35, 0.95, 1.0, 0.55)

	# Nose cone
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.5
	nose.height = 2.0
	nose.radial_segments = 10
	add_part(parent, nose, hull, Vector3(0, 0, -1.55), Vector3(-90, 0, 0))

	# Fuselage
	var body := CylinderMesh.new()
	body.top_radius = 0.5
	body.bottom_radius = 0.44
	body.height = 1.9
	body.radial_segments = 10
	add_part(parent, body, hull, Vector3(0, 0, 0.4), Vector3(-90, 0, 0))

	# Canopy
	var canopy := SphereMesh.new()
	canopy.radius = 0.4
	canopy.height = 0.8
	canopy.radial_segments = 12
	canopy.rings = 7
	var cp := add_part(parent, canopy, glass, Vector3(0, 0.24, -0.35), Vector3.ZERO)
	cp.scale = Vector3(0.85, 0.52, 1.5)

	# Wings + winglets
	for s in [-1.0, 1.0]:
		var wing := BoxMesh.new()
		wing.size = Vector3(1.7, 0.11, 1.05)
		var w := add_part(parent, wing, hull, Vector3(s * 1.05, -0.04, 0.35), Vector3(0, s * -9.0, s * 11.0))
		w.scale = Vector3(1.0, 1.0, 1.0)
		var tipm := BoxMesh.new()
		tipm.size = Vector3(0.16, 0.42, 0.9)
		add_part(parent, tipm, accent, Vector3(s * 1.85, 0.1, 0.45), Vector3(0, 0, s * 11.0))
		var stripe := BoxMesh.new()
		stripe.size = Vector3(1.3, 0.045, 0.16)
		add_part(parent, stripe, trim, Vector3(s * 1.0, 0.035, 0.2), Vector3(0, s * -9.0, s * 11.0))
		# Engine pod
		var pod := CylinderMesh.new()
		pod.top_radius = 0.26
		pod.bottom_radius = 0.3
		pod.height = 1.25
		pod.radial_segments = 10
		add_part(parent, pod, hull, Vector3(s * 0.62, -0.02, 1.05), Vector3(-90, 0, 0))
		var ring := TorusMesh.new()
		ring.inner_radius = 0.2
		ring.outer_radius = 0.3
		ring.rings = 14
		ring.ring_segments = 6
		var rg := add_part(parent, ring, V.glow_material(V.CYAN, 5.0), Vector3(s * 0.62, -0.02, 1.68), Vector3(90, 0, 0))
		glows.append(rg)

	# Tail fin
	var fin := BoxMesh.new()
	fin.size = Vector3(0.1, 0.75, 0.9)
	add_part(parent, fin, accent, Vector3(0, 0.45, 1.05), Vector3(-14, 0, 0))

	# Belly glow strip
	var belly := BoxMesh.new()
	belly.size = Vector3(0.6, 0.06, 2.4)
	add_part(parent, belly, V.glow_material(V.CYAN, 3.0), Vector3(0, -0.33, 0.1), Vector3.ZERO)
	return glows


## PHANTOM: a lower, broader Art Deco heavy cruiser. Same collision profile as
## the Vector ship, so ship choice is a visual identity choice and never
## creates an unfair handling advantage. Returns the engine glow rings.
static func build_phantom(parent: Node3D) -> Array:
	var glows: Array = []
	var hull := V.metal_material(Color(0.018, 0.028, 0.075), 0.95, 0.16, Color(0.025, 0.06, 0.18), 0.45)
	var chrome := V.metal_material(Color(0.27, 0.34, 0.60), 1.0, 0.16, Color(0.24, 0.52, 1.0), 1.0)
	var violet := V.metal_material(Color(0.08, 0.025, 0.15), 0.95, 0.18, Color(0.64, 0.20, 1.0), 2.2)
	var glass := V.glow_material(Color(0.24, 0.58, 1.0), 1.5, false)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.20, 0.48, 0.92, 0.52)

	# Long low wedge silhouette.
	var belly := BoxMesh.new()
	belly.size = Vector3(2.15, 0.46, 3.8)
	add_part(parent, belly, hull, Vector3(0, -0.05, 0.15), Vector3.ZERO)
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.78
	nose.height = 2.2
	nose.radial_segments = 4
	add_part(parent, nose, hull, Vector3(0, 0.0, -2.05), Vector3(-90, 45, 0))
	var canopy := BoxMesh.new()
	canopy.size = Vector3(1.35, 0.46, 1.78)
	add_part(parent, canopy, glass, Vector3(0, 0.30, -0.25), Vector3(0, 0, 0))
	# Swept wings and tip fins.
	for side in [-1.0, 1.0]:
		var wing := BoxMesh.new()
		wing.size = Vector3(1.95, 0.09, 1.55)
		add_part(parent, wing, hull, Vector3(side * 1.5, -0.02, 0.30), Vector3(0, side * -14.0, side * 13.0))
		var edge := BoxMesh.new()
		edge.size = Vector3(1.72, 0.05, 0.11)
		add_part(parent, edge, chrome, Vector3(side * 1.48, 0.06, -0.08), Vector3(0, side * -14.0, side * 13.0))
		var fin := BoxMesh.new()
		fin.size = Vector3(0.11, 0.64, 0.86)
		add_part(parent, fin, violet, Vector3(side * 2.25, 0.25, 0.76), Vector3(0, 0, side * 8.0))
		var pod := CylinderMesh.new()
		pod.top_radius = 0.30
		pod.bottom_radius = 0.34
		pod.height = 1.15
		pod.radial_segments = 10
		add_part(parent, pod, hull, Vector3(side * 0.78, -0.05, 1.58), Vector3(-90, 0, 0))
		var ring := TorusMesh.new()
		ring.inner_radius = 0.24
		ring.outer_radius = 0.34
		ring.rings = 16
		ring.ring_segments = 6
		var glow := add_part(parent, ring, V.glow_material(V.VIOLET, 4.5), Vector3(side * 0.78, -0.05, 2.15), Vector3(90, 0, 0))
		glows.append(glow)
	# Roof fin and an Art Deco exhaust spine.
	var spine := BoxMesh.new()
	spine.size = Vector3(0.22, 0.62, 1.4)
	add_part(parent, spine, violet, Vector3(0, 0.36, 1.08), Vector3(-8, 0, 0))
	var strip := BoxMesh.new()
	strip.size = Vector3(0.32, 0.05, 2.55)
	add_part(parent, strip, chrome, Vector3(0, -0.30, 0.10), Vector3.ZERO)
	return glows


## Texture-free music lens flares: one bass engine bloom, two melody wing
## flares, plus transient sparkle hits. Same layout as the live ship.
## Returns {"flares": Array[MeshInstance3D], "mats": Array[ShaderMaterial]}.
static func build_music_flares(parent: Node3D) -> Dictionary:
	var flares: Array = []
	var mats: Array = []
	var positions := [
		Vector3(0, 0.0, 2.35), Vector3(-1.95, 0.10, 0.80), Vector3(1.95, 0.10, 0.80),
		Vector3(-0.70, 0.48, 1.55), Vector3(0.70, 0.48, 1.55), Vector3(0, 0.42, -1.8),
	]
	var sizes := [2.5, 1.15, 1.15, 0.72, 0.72, 0.60]
	for i in positions.size():
		var flare := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(sizes[i], sizes[i])
		flare.mesh = quad
		var fm := ShaderMaterial.new()
		fm.shader = MUSIC_FLARE_SHADER
		fm.set_shader_parameter("flare_color", V.CYAN)
		fm.set_shader_parameter("strength", 0.0)
		fm.set_shader_parameter("style", float(i % 4))
		fm.set_shader_parameter("pulse", 0.0)
		flare.material_override = fm
		flare.position = positions[i]
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(flare)
		flares.append(flare)
		mats.append(fm)
	return {"flares": flares, "mats": mats}
