shader_type sky;
// The sky over a country street: a grey morning of rain cloud, dark underneath, breaking up toward
// the low sun into bright gaps with lit edges. Seen mostly just above the hills, so the cloud deck
// is drawn on a flat plane that squeezes toward the horizon.

uniform vec3 zenith : source_color = vec3(0.32, 0.37, 0.44);
uniform vec3 horizon : source_color = vec3(0.56, 0.58, 0.6);
uniform vec3 cloud_dark : source_color = vec3(0.17, 0.19, 0.22);
uniform vec3 cloud_lit : source_color = vec3(0.55, 0.56, 0.58);
uniform vec3 sun_col : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 sun_dir = vec3(-0.45, 0.3, -0.84);
uniform float cover = 0.62;         // 0..1 how much of the sky the cloud deck covers
uniform float drift = 0.004;        // how fast the clouds move along the street

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	float el = d.y;
	vec3 col = mix(horizon, zenith, smoothstep(0.0, 0.45, el));
	float sun = max(dot(d, sd), 0.0);
	col += sun_col * pow(sun, 8.0) * 0.35;
	if (el > -0.08) {
		vec2 uv = d.xz / (max(el, 0.0) + 0.08) * 0.9 + vec2(TIME * drift, 0.0);
		float n = fbm(uv);
		float thick = smoothstep(1.0 - cover - 0.12, 1.0 - cover + 0.22, n);
		vec3 cl = mix(cloud_lit, cloud_dark, smoothstep(0.45, 0.85, n));
		// Edges of the cloud toward the sun catch its light.
		float rim = smoothstep(0.0, 0.45, thick) * (1.0 - smoothstep(0.45, 1.0, thick));
		cl += sun_col * rim * pow(sun, 3.0) * 0.8;
		vec3 gap = mix(col * 1.12, sun_col * 1.4, pow(sun, 5.0) * 0.6);
		col = mix(gap, cl, thick);
		// Haze: the far cloud melts into the horizon.
		col = mix(horizon, col, smoothstep(-0.06, 0.12, el));
	}
	COLOR = col;
}
