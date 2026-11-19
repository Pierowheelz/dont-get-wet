shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

// Rain-rippled puddle: mirror-smooth, darkened, with animated ring ripples in the normal. Its outline
// follows noise in world space, so every puddle lies in its own hollow and none is a neat oval.
varying vec2 wxz;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

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

void vertex() {
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float shore = noise(wxz * 1.7) * 0.34 + noise(wxz * 5.3) * 0.14 - 0.2;
	float d = length(centered) + shore;
	// A crisp waterline with a thin damp margin outside it.
	float water = 1.0 - smoothstep(0.66, 0.72, d);
	float damp = 1.0 - smoothstep(0.72, 0.92, d);
	vec2 r = ripple(UV * 6.0, TIME) * water;
	NORMAL_MAP = normalize(vec3(r * 0.35 + 0.5, 1.0));
	ALBEDO = vec3(0.02, 0.022, 0.026);
	ROUGHNESS = mix(0.18, 0.02, water);
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ALPHA = max(water * 0.92, damp * 0.4) * (1.0 - smoothstep(0.9, 1.0, max(abs(centered.x), abs(centered.y))));
}
