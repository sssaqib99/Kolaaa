// Neon hazard material. arrow_mode encodes the required action so the player can
// read every obstacle instantly at 200km/h:  0 = dodge, 1 = jump, 2 = duck.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 neon_color : source_color = vec3(1.0, 0.18, 0.62);
uniform float energy = 2.6;
uniform int arrow_mode = 0;
uniform float pulse_speed = 3.0;
uniform float scan_scale = 3.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 2.0);
	float pulse = 0.65 + 0.35 * sin(TIME * pulse_speed);

	float stripes;
	if (arrow_mode == 1) {
		stripes = smoothstep(0.5, 0.98, fract(UV.y * scan_scale + TIME * 1.15));
	} else if (arrow_mode == 2) {
		stripes = smoothstep(0.5, 0.98, fract(-UV.y * scan_scale + TIME * 1.15));
	} else {
		stripes = smoothstep(0.62, 1.0, fract((UV.x + UV.y) * scan_scale * 0.6 + TIME * 0.4));
	}

	float frame = 1.0 - smoothstep(0.035, 0.075, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));

	ALBEDO = neon_color * 0.05;
	METALLIC = 0.45;
	ROUGHNESS = 0.22;
	RIM = 0.7;
	EMISSION = neon_color * (fres * energy * pulse + stripes * energy * 0.45 + frame * energy * 0.8 + 0.1);
}
