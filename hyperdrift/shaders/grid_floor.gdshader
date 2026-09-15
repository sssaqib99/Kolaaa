// Infinite world-space neon grid. The plane follows the player, the grid stays
// locked to world coordinates so it reads as a truly endless highway.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.012, 0.008, 0.035);
uniform vec3 grid_color : source_color = vec3(0.13, 0.85, 1.0);
uniform vec3 edge_color : source_color = vec3(1.0, 0.13, 0.58);
uniform float cell_size = 4.0;
uniform float fade_dist = 300.0;
uniform float track_half = 15.1;
uniform float energy = 1.5;
uniform float focus_z = 0.0;
uniform float hit_flash = 0.0;
uniform float boost = 0.0;
uniform float beat_pulse = 0.0;
// NOCTURNE BOULEVARD: swaps the retro grid for a rain-dark Art Deco street.
uniform float street_mode = 0.0;
uniform vec3 asphalt_color : source_color = vec3(0.045, 0.055, 0.10);
uniform vec3 curb_color : source_color = vec3(0.22, 0.12, 0.34);
uniform vec3 line_color : source_color = vec3(0.82, 0.72, 0.52);
uniform vec3 center_color : source_color = vec3(0.92, 0.58, 0.22);
uniform float wetness = 0.0;
uniform float night_mix = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_mask(vec2 p, float w) {
	vec2 g = abs(fract(p - 0.5) - 0.5) / fwidth(p);
	float l = min(g.x, g.y);
	return 1.0 - min(l / w, 1.0);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float line_at(float x, float center, float width) {
	float aa = max(fwidth(x) * 1.8, 0.015);
	return 1.0 - smoothstep(width, width + aa, abs(x - center));
}

void fragment() {
	vec2 gp = wpos.xz / cell_size;
	float fine = grid_mask(gp, 1.35);
	float coarse = grid_mask(gp * 0.2, 2.0);

	float dist = length(vec2(wpos.x * 0.35, wpos.z - focus_z));
	float fade = 1.0 - smoothstep(fade_dist * 0.2, fade_dist, dist);

	// Pulse rings racing outward from the ship.
	float ring = exp(-fract(dist * 0.016 - TIME * 0.35) * 7.0);

	float on_track = 1.0 - smoothstep(track_half, track_half + 1.4, abs(wpos.x));
	vec3 gc = mix(edge_color, grid_color, on_track);

	vec3 col = base_color;
	col += gc * (fine * 1.0 + coarse * 0.9) * energy * fade;
	col += gc * ring * 0.45 * fade;
	col += grid_color * 0.035 * on_track * fade;
	col += edge_color * (1.0 - on_track) * 0.05 * fade;
	col += vec3(1.0, 0.35, 0.7) * hit_flash * fade * 1.5;
	col += grid_color * boost * 0.25 * fine * fade;

	// Beat: the whole grid breathes with the music and a shock-ring leaves the ship.
	float beat_ring = exp(-abs(dist - (1.0 - beat_pulse) * 90.0) * 0.12) * beat_pulse;
	col += gc * beat_pulse * 0.45 * (fine + coarse * 0.5) * fade;
	col += gc * beat_ring * 0.9 * fade;

	// Nocturne's physical boulevard. The asphalt has fine aggregate, wet
	// reflections, dashed lane separators, a brass double centre line and pale
	// sidewalks. It uses only a faint emission so it reads as a real road.
	float road = 1.0 - smoothstep(track_half, track_half + 0.7, abs(wpos.x));
	float n = hash21(floor(wpos.xz * 2.8));
	float grain = (n - 0.5) * 0.13 + sin(wpos.z * 0.72 + wpos.x * 1.31) * 0.018;
	vec3 asphalt = asphalt_color * (0.82 + grain);
	asphalt = mix(asphalt, asphalt * vec3(0.48, 0.56, 0.82), wetness * 0.22 * (0.5 + 0.5 * sin(wpos.z * 0.19)));
	vec3 sidewalk = mix(curb_color * 0.42, curb_color * 0.72, n);
	vec3 street_col = mix(sidewalk, asphalt, road);
	float dash = step(0.38, fract((wpos.z + 2.5) / 10.0));
	float lane_marks = (line_at(wpos.x, -track_half * 0.34, 0.065) + line_at(wpos.x, track_half * 0.34, 0.065)) * dash * road;
	float edge_marks = (line_at(abs(wpos.x), track_half - 0.42, 0.08)) * road;
	float center_marks = (line_at(wpos.x, -0.19, 0.045) + line_at(wpos.x, 0.19, 0.045)) * dash * road;
	street_col = mix(street_col, line_color, clamp(lane_marks + edge_marks, 0.0, 1.0));
	street_col = mix(street_col, center_color, clamp(center_marks, 0.0, 1.0));
	float puddle = smoothstep(0.76, 0.98, hash21(floor(wpos.xz * 0.19))) * road;
	street_col += vec3(0.10, 0.07, 0.20) * puddle * wetness * 0.35;
	vec3 street_em = (line_color * lane_marks * 0.12 + center_color * center_marks * 0.18 + curb_color * edge_marks * 0.08) * (1.0 - night_mix * 0.25);

	ALBEDO = mix(col * 0.12, street_col, street_mode);
	EMISSION = mix(col * 1.35, street_em, street_mode);
	ROUGHNESS = mix(0.45, 0.72 - wetness * 0.35, street_mode);
	METALLIC = mix(0.0, wetness * 0.3, street_mode);
}
