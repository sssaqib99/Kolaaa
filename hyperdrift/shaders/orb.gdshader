// Additive, always-glowing collectible.
shader_type spatial;
render_mode blend_add, cull_back, unshaded, depth_draw_never, shadows_disabled;

uniform vec3 orb_color : source_color = vec3(0.25, 1.0, 0.9);
uniform float energy = 2.2;
uniform float pulse_speed = 5.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.6);
	float pulse = 0.72 + 0.28 * sin(TIME * pulse_speed + VERTEX.y * 6.0);
	vec3 c = orb_color * (0.35 + fres * energy) * pulse;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = 1.0;
}
