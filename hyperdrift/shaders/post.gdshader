// Full screen grade: chromatic aberration, radial speed-warp, vignette,
// damage flash, scanlines and film grain. Driven live from main.gd.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float aberration = 0.0;
uniform float warp = 0.0;
uniform float vignette_amount = 0.42;
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.12, 0.3);
uniform float scanline = 0.035;
uniform float grain = 0.02;
uniform float desaturate = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - vec2(0.5);
	float r = length(c);

	float ab = aberration * 0.006 + 0.0004;
	vec3 col;
	col.r = texture(screen_tex, uv + c * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * ab).b;

	if (warp > 0.002) {
		vec3 acc = vec3(0.0);
		for (int i = 1; i <= 6; i++) {
			float t = float(i) / 6.0;
			acc += texture(screen_tex, uv - c * t * warp * 0.11).rgb;
		}
		acc /= 6.0;
		col = mix(col, acc, clamp(warp, 0.0, 1.0) * 0.7 * smoothstep(0.12, 0.62, r));
	}

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), clamp(desaturate, 0.0, 1.0));

	col = mix(col, flash_color, clamp(flash, 0.0, 1.0));
	col *= 1.0 - vignette_amount * smoothstep(0.32, 0.98, r);
	col *= 1.0 - scanline * (0.5 + 0.5 * sin(SCREEN_UV.y * 1400.0));
	col += (hash(uv * 640.0 + fract(TIME) * 91.0) - 0.5) * grain;

	COLOR = vec4(col, 1.0);
}
