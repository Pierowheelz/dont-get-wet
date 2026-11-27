shader_type sky;
// A grey, rainy late afternoon over the suburbs: a low ceiling of cloud, darker where it is thick,
// with paler breaks in it, warm toward the low sun; haze down at the horizon. Static (no TIME), so
// the radiance the street's ambient light comes from is drawn once.

uniform vec3 top_color : source_color = vec3(0.5, 0.53, 0.57);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.72, 0.72);
uniform vec3 cloud_dark : source_color = vec3(0.36, 0.38, 0.42);
uniform vec3 break_color : source_color = vec3(0.86, 0.8, 0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.8, 0.55);
uniform vec3 ground_color : source_color = vec3(0.2, 0.21, 0.2);
uniform vec3 sun_dir = vec3(-0.75, 0.22, -0.62);   // low in the west, behind and to the left of the street
uniform float breaks = 0.38;                        // how much of the cloud has broken

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sd = normalize(sun_dir);
	float toward = max(dot(d, sd), 0.0);
	if (h < 0.0) {
		COLOR = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	} else {
		vec2 uv = d.xz / (h + 0.08);
		float n = fbm(uv * 0.55 + vec2(3.0, 1.0));
		float m = fbm(uv * 1.6 + vec2(-2.0, 5.0));
		vec3 base = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
		vec3 c = mix(base, cloud_dark, smoothstep(0.42, 0.72, n) * 0.75);
		// Breaks: where the cloud is thin, paler sky, and warm where it faces the low sun.
		float br = smoothstep(breaks, breaks - 0.12, n + (m - 0.5) * 0.18);
		vec3 lit = mix(break_color, sun_color, pow(toward, 3.0));
		c = mix(c, lit, br * (0.45 + 0.55 * pow(toward, 2.0)));
		// The cloud's undersides take the sun's warmth near it.
		c += sun_color * pow(toward, 8.0) * 0.25;
		c = mix(c, horizon_color, smoothstep(0.18, 0.0, h) * 0.75);
		COLOR = c;
	}
}
