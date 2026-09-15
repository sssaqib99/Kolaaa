// Camera-facing disco/trance flare plane. Every flare is a QuadMesh placed
// behind the hovercraft; UV patterns render radial blooms, crosses, streaks
// and diamond gobo hits with no texture files.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec3 flare_color : source_color = vec3(0.35, 0.9, 1.0);
uniform float strength = 1.0;
uniform float style = 0.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float radial = exp(-r * r * 4.4);
	float cross = exp(-abs(p.x) * 36.0) + exp(-abs(p.y) * 36.0);
	float diag = exp(-abs(p.x - p.y) * 28.0) + exp(-abs(p.x + p.y) * 28.0);
	float streak = exp(-abs(p.y) * 14.0) * exp(-abs(p.x) * 1.8);
	float ring = exp(-abs(r - 0.58) * 18.0);
	float pattern = radial;
	if (style < 0.5) {
		pattern = radial + cross * 0.32;
	} else if (style < 1.5) {
		pattern = radial * 0.42 + streak * 0.66;
	} else if (style < 2.5) {
		pattern = radial * 0.34 + diag * 0.34 + ring * 0.26;
	} else {
		pattern = radial * 0.55 + cross * 0.18 + diag * 0.16;
	}
	float alpha = clamp(pattern * strength, 0.0, 1.0);
	vec3 col = flare_color * (0.55 + pulse * 1.75) * pattern * strength;
	ALBEDO = col;
	EMISSION = col;
	ALPHA = alpha;
}