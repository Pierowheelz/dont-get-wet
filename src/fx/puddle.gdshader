shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

// Rain-rippled puddle: mirror-smooth, darkened, with animated ring ripples in the normal.
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec2 ripple(vec2 uv, float t) {
	vec2 cell = floor(uv);
	vec2 n = vec2(0.0);
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 c = cell + vec2(float(x), float(y));
		float h = hash(c);
		vec2 center = c + vec2(hash(c + 3.1), hash(c + 7.7));
		float phase = fract(t * 1.3 + h);
		vec2 d = uv - center;
		float r = length(d);
		float ring = sin((r - phase * 0.9) * 40.0) * smoothstep(0.0, 0.1, phase * 0.9 - r + 0.08) * (1.0 - phase);
		ring *= smoothstep(0.9, 0.0, r);
		n += normalize(d + 1e-4) * ring;
	}
	return n;
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.55, 1.0, length(centered * vec2(1.0, 1.0)));
	vec2 r = ripple(UV * 6.0, TIME);
	NORMAL_MAP = normalize(vec3(r * 0.35 + 0.5, 1.0));
	ALBEDO = vec3(0.02, 0.022, 0.026);
	ROUGHNESS = 0.02;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ALPHA = edge * 0.92;
}
