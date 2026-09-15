extends RefCounted
## Shared palette + material / particle factories used across the whole game.

const NEON_SHADER: Shader = preload("res://shaders/neon.gdshader")
const ORB_SHADER: Shader = preload("res://shaders/orb.gdshader")

const CYAN := Color(0.18, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.16, 0.62)
const YELLOW := Color(1.0, 0.78, 0.16)
const LIME := Color(0.48, 1.0, 0.36)
const VIOLET := Color(0.62, 0.36, 1.0)
const ORANGE := Color(1.0, 0.46, 0.12)
const WHITE := Color(0.9, 0.97, 1.0)
const DEEP := Color(0.05, 0.02, 0.12)


static func neon_material(color: Color, arrow_mode: int, energy: float = 2.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = NEON_SHADER
	m.set_shader_parameter("neon_color", color)
	m.set_shader_parameter("arrow_mode", arrow_mode)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("pulse_speed", 3.0)
	m.set_shader_parameter("scan_scale", 3.0)
	return m


static func orb_material(color: Color, energy: float = 2.2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ORB_SHADER
	m.set_shader_parameter("orb_color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("pulse_speed", 5.0)
	return m


static func glow_material(color: Color, energy: float = 4.0, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Unshaded output comes from ALBEDO only, so bake the energy in to get HDR
	# values above 1.0 -> the glow pass picks them up as real neon bloom.
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.disable_receive_shadows = true
	# Lets GPUParticles colour ramps (and their alpha fade) drive the render.
	m.vertex_color_use_as_albedo = true
	if additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func metal_material(albedo: Color, metallic: float, roughness: float, emission: Color, e_energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	m.rim_enabled = true
	m.rim = 0.75
	m.rim_tint = 0.4
	if e_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = e_energy
	return m


static func gradient_tex(a: Color, b: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Generic emitter used for thrusters, sparks, dust and explosions.
static func make_particles(amount: int, lifetime: float, mesh: Mesh, mat: Material,
		velocity: float, spread: float, scale_min: float, scale_max: float,
		color_a: Color, color_b: Color, gravity: Vector3 = Vector3.ZERO) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.draw_pass_1 = mesh
	p.material_override = mat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = spread
	pm.initial_velocity_min = velocity * 0.4
	pm.initial_velocity_max = velocity
	pm.gravity = gravity
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	pm.damping_min = velocity * 0.25
	pm.damping_max = velocity * 0.6
	pm.color_ramp = gradient_tex(color_a, color_b)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	p.process_material = pm
	return p
