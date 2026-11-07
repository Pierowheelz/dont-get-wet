shader_type spatial;
render_mode cull_disabled;

// Striped canvas awning with grime and a wet sheen.
uniform vec4 color_a : source_color = vec4(0.55, 0.12, 0.1, 1.0);
uniform vec4 color_b : source_color = vec4(0.85, 0.8, 0.7, 1.0);
uniform float stripe_count = 10.0;
uniform float grime = 0.5;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float s = step(0.5, fract(UV.x * stripe_count));
	vec3 col = mix(color_a.rgb, color_b.rgb, s);
	float n = noise(UV * vec2(stripe_count * 2.0, 6.0)) * 0.6 + noise(UV * vec2(stripe_count * 8.0, 30.0)) * 0.4;
	// grime streaks run down the canvas (UV.y increases toward the front edge)
	float streak = noise(vec2(UV.x * stripe_count * 3.0, UV.y * 1.5));
	col *= mix(1.0, 0.45 + 0.4 * n, grime * (0.4 + 0.6 * UV.y));
	col *= mix(1.0, 0.7, grime * smoothstep(0.55, 0.9, streak));
	ALBEDO = col * 0.8;
	ROUGHNESS = mix(0.35, 0.7, n);
	SPECULAR = 0.6;
}
