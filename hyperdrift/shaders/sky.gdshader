// Procedural synthwave sky: gradient, banded retro sun, stars and horizon haze.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.015, 0.005, 0.06);
uniform vec3 horizon_color : source_color = vec3(0.45, 0.04, 0.42);
uniform vec3 ground_color : source_color = vec3(0.008, 0.004, 0.025);
uniform vec3 sun_color : source_color = vec3(1.0, 0.32, 0.62);
uniform vec3 sun_core : source_color = vec3(1.0, 0.85, 0.45);
uniform float star_density = 0.986;
uniform float intensity = 1.0;
uniform float aurora = 0.0;
uniform vec3 aurora_a : source_color = vec3(0.2, 1.0, 0.55);
uniform vec3 aurora_b : source_color = vec3(0.55, 0.3, 1.0);
// NOCTURNE BOULEVARD: the live soundtrack slowly grades crimson dusk into a
// midnight indigo palette. The moon stays bright through the transition.
uniform float night_mix = 0.0;
uniform vec3 night_zenith : source_color = vec3(0.006, 0.006, 0.035);
uniform vec3 night_horizon : source_color = vec3(0.10, 0.024, 0.23);
uniform float moon = 0.0;
uniform vec3 moon_color : source_color = vec3(0.95, 0.91, 0.72);
uniform float moon_size = 0.115;

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float moon_hash(vec2 p) {
	p = fract(p * vec2(142.31, 317.43));
	p += dot(p, p + 17.87);
	return fract(p.x * p.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y * 0.5 + 0.5, 0.0, 1.0);

	// Vertical gradient. night_mix is only non-zero for Nocturne Boulevard.
	vec3 zc = mix(zenith_color, night_zenith, night_mix);
	vec3 hc = mix(horizon_color, night_horizon, night_mix);
	vec3 col = mix(hc, zc, smoothstep(0.5, 0.92, h));
	col = mix(ground_color, col, smoothstep(0.42, 0.52, h));

	// Horizon haze band
	float haze = exp(-abs(d.y) * 26.0);
	col += hc * haze * 0.9;

	// Big retro sun straight ahead (-Z)
	vec3 sundir = normalize(vec3(0.0, 0.10, -1.0));
	float sd = dot(d, sundir);
	float disc = smoothstep(0.9955, 0.9975, sd);
	float bands = step(0.42, fract(d.y * 90.0 - TIME * 0.15));
	float band_mix = mix(1.0, bands, smoothstep(0.115, 0.015, d.y));
	vec3 sun_grad = mix(sun_color, sun_core, smoothstep(0.02, 0.14, d.y));
	col += sun_grad * disc * band_mix * 2.6 * intensity;
	col += sun_color * pow(max(sd, 0.0), 90.0) * 0.9;
	col += sun_color * pow(max(sd, 0.0), 12.0) * 0.12;

	// Stars (upper hemisphere only)
	vec2 sc = vec2(atan(d.x, d.z) * 2.2, d.y * 3.4);
	vec2 cellf = floor(sc * 70.0);
	float rnd = hash21(cellf);
	float star = step(star_density, rnd);
	float tw = 0.55 + 0.45 * sin(TIME * 2.4 + rnd * 42.0);
	col += vec3(0.75, 0.85, 1.0) * star * tw * smoothstep(0.05, 0.45, d.y) * 1.6;

	// Full moon with a subtle crater pattern. The disc remains in the sky as
	// Nocturne changes from crimson dusk to indigo midnight.
	if (moon > 0.001) {
		vec3 md = normalize(vec3(-0.28, 0.18, -1.0));
		float moon_dot = dot(d, md);
		float rad = max(moon_size, 0.01);
		float disc_m = smoothstep(cos(rad), cos(rad * 0.87), moon_dot);
		vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
		vec3 up = normalize(cross(right, md));
		vec2 muv = vec2(dot(d, right), dot(d, up)) / rad;
		float inside = 1.0 - smoothstep(0.82, 1.0, length(muv));
		float crater = step(0.74, moon_hash(floor(muv * 8.0 + vec2(13.0)))) * inside;
		float rim = 1.0 - smoothstep(0.70, 0.97, length(muv));
		vec3 mcol = moon_color * (1.0 - crater * 0.24 + rim * 0.10);
		col += mcol * disc_m * moon * 1.5;
		col += moon_color * pow(max(moon_dot, 0.0), 36.0) * moon * 0.18;
	}

	// Aurora curtains (Glacier map): slow drifting bands high in the sky.
	if (aurora > 0.001) {
		float az = atan(d.x, d.z);
		float band = sin(az * 3.0 + TIME * 0.12 + sin(az * 7.0 - TIME * 0.21) * 0.8) * 0.5 + 0.5;
		band = pow(band, 3.0);
		float band2 = pow(sin(az * 5.0 - TIME * 0.09 + 1.7) * 0.5 + 0.5, 4.0);
		float curtain = smoothstep(0.10, 0.32, d.y) * (1.0 - smoothstep(0.42, 0.88, d.y));
		float rays = 0.7 + 0.3 * sin(az * 40.0 + TIME * 0.6 + d.y * 30.0);
		vec3 ac = mix(aurora_a, aurora_b, smoothstep(0.15, 0.6, d.y + 0.15 * sin(az * 5.0 + TIME * 0.3)));
		col += ac * (band + band2 * 0.6) * curtain * rays * aurora * 1.5;
	}

	COLOR = col * intensity;
}
