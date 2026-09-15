// Roadside architecture. style 0 = cyber city window grid, style 1 = canyon
// mesa / refinery with lava seams, style 2 = glacier crystal, style 3 = legacy sandstone
// limestone citadel with carved balconies and cloth awnings. Windows are derived from local
// space so density stays physically constant no matter the building size.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_disabled, shadows_disabled;

uniform vec3 base_color : source_color = vec3(0.03, 0.02, 0.06);
uniform vec3 window_color : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 accent_color : source_color = vec3(1.0, 0.3, 0.7);
uniform float window_density = 0.4;
uniform float energy = 3.0;
uniform float seed = 0.0;
uniform int style = 0;
uniform float night_mix = 0.0;

varying vec3 lpos;
varying vec3 lnrm;

float h21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

void fragment() {
	vec3 n = normalize(lnrm);
	float top = step(0.5, abs(n.y));
	float side = 1.0 - top;
	float ux = mix(lpos.x, lpos.z, step(0.5, abs(n.x)));
	float uy = lpos.y;

	vec3 col = base_color;
	vec3 ecol = window_color;
	float em = 0.0;

	if (style == 1) {
		// Layered rock strata with glowing seams.
		float w = h21(vec2(seed, 3.0)) * 6.2831;
		float strata = sin(uy * 0.5 + w) * 0.5 + 0.5;
		col = mix(base_color, base_color * 2.3, strata * 0.65);
		col *= 0.85 + 0.3 * h21(vec2(floor(uy * 0.5), seed));
		float seam = smoothstep(0.88, 1.0, sin(uy * 0.85 + 1.3 + w));
		ecol = mix(window_color, accent_color, 0.6);
		em += seam * 0.55 * side;

		vec2 cell = vec2(floor(ux * 0.2), floor(uy * 0.26));
		float r = h21(cell + seed);
		float lit = step(1.0 - window_density * 0.5, r);
		vec2 f = vec2(fract(ux * 0.2), fract(uy * 0.26));
		float win = step(0.3, f.x) * step(f.x, 0.7) * step(0.3, f.y) * step(f.y, 0.7);
		float flick = step(0.06, h21(cell + floor(TIME * 0.5) + seed));
		em += lit * win * flick * energy * side;
	} else if (style == 2) {
		// Glacier: crystalline facets with glowing veins, brighter towards the peaks.
		float w = h21(vec2(seed, 5.0)) * 6.2831;
		float v1 = abs(fract((ux + uy * 0.6) * 0.08 + w) - 0.5);
		float v2 = abs(fract((ux - uy * 0.8) * 0.06 - w * 0.7) - 0.5);
		float vein = (1.0 - smoothstep(0.0, 0.035, v1)) + (1.0 - smoothstep(0.0, 0.03, v2));
		float facet = 0.85 + 0.45 * h21(vec2(floor(ux * 0.1 + w), floor(uy * 0.1)) + seed);
		col = base_color * facet * (1.0 + 0.6 * smoothstep(0.0, 50.0, uy));
		ecol = mix(window_color, accent_color, 0.5 + 0.5 * sin(uy * 0.25 + TIME * 0.5 + w));
		em += vein * 0.55 * side * (0.7 + 0.3 * sin(TIME * 1.4 + uy * 0.2 + w));
		em += smoothstep(8.0, 60.0, uy) * 0.35 * side;
		vec2 cell = vec2(floor(ux * 0.25), floor(uy * 0.2));
		float core = step(1.0 - window_density * 0.6, h21(cell + seed));
		vec2 f = vec2(fract(ux * 0.25), fract(uy * 0.2));
		float dot_m = 1.0 - smoothstep(0.12, 0.2, length(f - 0.5));
		em += core * dot_m * energy * 0.8 * side;
		em += top * 1.2;
	} else if (style == 3) {
		// Legacy sandstone: sun-baked blocks, recessed arches, dark
		// balcony bands and sparse brass windows. Kept matte and warm, not neon.
		float strata = sin(uy * 0.22 + seed * 3.0) * 0.5 + 0.5;
		float stone = 0.88 + 0.18 * h21(vec2(floor(ux * 0.08), floor(uy * 0.12)) + seed);
		col = base_color * stone * mix(0.78, 1.18, strata);
		float balcony = smoothstep(0.88, 0.98, sin(uy * 0.42 + seed));
		col = mix(col, accent_color * 0.45, balcony * side);
		vec2 cell = vec2(floor(ux * 0.17), floor(uy * 0.22));
		float lit = step(1.0 - window_density * 0.8, h21(cell + seed));
		vec2 f = vec2(fract(ux * 0.17), fract(uy * 0.22));
		float window = step(0.25, f.x) * step(f.x, 0.75) * step(0.32, f.y) * step(f.y, 0.68);
		float arch = smoothstep(0.2, 0.0, abs(f.x - 0.5)) * step(0.58, f.y);
		ecol = mix(window_color, accent_color, 0.18);
		col = mix(col, ecol * 0.3, lit * window * side);
		em += lit * window * energy * 0.22 * side;
		em += arch * balcony * 0.08;
		// Carved horizontal bands catch the key light without glowing.
		col += vec3(0.08, 0.055, 0.03) * smoothstep(0.8, 1.0, sin(uy * 0.65 + seed)) * side;
	} else if (style == 4) {
		// Nocturne Boulevard: hand-painted Art Deco noir. Deep blue-black shaft,
		// stepped horizontal setbacks, vertical fluting and sparse warm windows.
		// As the soundtrack relaxes, night_mix makes the city settle into a
		// violet-blue midnight without turning it into a neon grid.
		float flutes = 0.5 + 0.5 * sin(ux * 1.65 + seed * 2.0);
		float blocks = 0.5 + 0.5 * sin(uy * 0.34 + seed);
		vec3 day_col = base_color * (0.72 + 0.28 * flutes) + accent_color * blocks * 0.10;
		vec3 night_col = mix(vec3(0.008, 0.012, 0.045), vec3(0.07, 0.035, 0.16), flutes * 0.32);
		col = mix(day_col, night_col, night_mix);
		// Strong dark bands create the silhouette of setback floors.
		float setback = smoothstep(0.88, 0.98, sin(uy * 0.46 + seed * 0.4));
		col *= 1.0 - setback * 0.44;
		vec2 cell = vec2(floor(ux * 0.30), floor(uy * 0.22));
		float lit = step(1.0 - window_density, h21(cell + seed));
		vec2 f = vec2(fract(ux * 0.30), fract(uy * 0.22));
		float window = step(0.20, f.x) * step(f.x, 0.67) * step(0.18, f.y) * step(f.y, 0.78);
		ecol = mix(window_color, vec3(0.72, 0.54, 0.95), night_mix * 0.62);
		col = mix(col, ecol * 0.12, lit * window * side);
		em += lit * window * energy * side * (0.55 + 0.45 * (1.0 - night_mix));
		// Pale Art Deco crown highlight on upward faces.
		em += top * smoothstep(0.78, 1.0, flutes) * 0.18;
	} else {
		// Dense city window grid.
		vec2 cell = vec2(floor(ux * 0.4), floor(uy * 0.33));
		float r = h21(cell + seed);
		float lit = step(1.0 - window_density, r);
		vec2 f = vec2(fract(ux * 0.4), fract(uy * 0.33));
		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.18, f.y) * step(f.y, 0.72);
		float flick = step(0.03, h21(cell + floor(TIME * 0.6) + seed));
		ecol = mix(window_color, accent_color, step(0.74, h21(cell * 1.7 + seed)));
		col = mix(col, ecol * 0.22, lit * win * side);
		em += lit * win * flick * energy * side;

		// Rooftop beacon.
		float beacon = step(0.62, h21(vec2(seed, 9.0))) * top * (0.5 + 0.5 * sin(TIME * 4.0 + seed * 3.0));
		em += beacon * energy * 0.7;
	}

	// Fade the very bottom so buildings melt into the fog.
	col *= 0.55 + 0.45 * smoothstep(-2.0, 6.0, uy);
	em *= 0.35 + 0.65 * smoothstep(-2.0, 8.0, uy);

	ALBEDO = col;
	EMISSION = ecol * em;
	ROUGHNESS = 0.85;
	METALLIC = 0.1;
}
