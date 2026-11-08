shader_type canvas_item;
// Painterly post filter: 4-sector Kuwahara (oil-paint brush clumping) + canvas grain,
// gentle edge ink, warm/cool split toning and a vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int radius = 3;
uniform float strength = 1.0;
uniform float grain = 0.035;
uniform float vignette = 0.35;
uniform float ink = 0.25;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	// Brush-stroke jitter: wobble the sampling grid with low-frequency noise.
	vec2 wob = (vec2(noise(uv * 180.0), noise(uv * 180.0 + 17.0)) - 0.5) * px * 1.5;
	vec3 m[4];
	vec3 s[4];
	for (int k = 0; k < 4; k++) { m[k] = vec3(0.0); s[k] = vec3(0.0); }
	float n = float((radius + 1) * (radius + 1));
	for (int j = 0; j <= radius; j++) {
		for (int i = 0; i <= radius; i++) {
			vec3 c;
			c = textureLod(screen_tex, uv + wob + vec2(float(-i), float(-j)) * px, 0.0).rgb; m[0] += c; s[0] += c * c;
			c = textureLod(screen_tex, uv + wob + vec2(float(i), float(-j)) * px, 0.0).rgb;  m[1] += c; s[1] += c * c;
			c = textureLod(screen_tex, uv + wob + vec2(float(i), float(j)) * px, 0.0).rgb;   m[2] += c; s[2] += c * c;
			c = textureLod(screen_tex, uv + wob + vec2(float(-i), float(j)) * px, 0.0).rgb;  m[3] += c; s[3] += c * c;
		}
	}
	float best = 1e9;
	vec3 col = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		vec3 mean = m[k] / n;
		vec3 var3 = abs(s[k] / n - mean * mean);
		float v = var3.r + var3.g + var3.b;
		if (v < best) { best = v; col = mean; }
	}
	vec3 orig = textureLod(screen_tex, uv, 0.0).rgb;
	col = mix(orig, col, strength);
	// Edge ink: darken where luminance changes sharply (sobel on the source).
	float l = dot(orig, vec3(0.299, 0.587, 0.114));
	float lx = dot(textureLod(screen_tex, uv + vec2(px.x * 1.5, 0.0), 0.0).rgb, vec3(0.299, 0.587, 0.114)) - l;
	float ly = dot(textureLod(screen_tex, uv + vec2(0.0, px.y * 1.5), 0.0).rgb, vec3(0.299, 0.587, 0.114)) - l;
	float edge = smoothstep(0.05, 0.25, length(vec2(lx, ly)));
	col *= 1.0 - edge * ink;
	// Split toning: cool shadows, warm highlights.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col * vec3(0.92, 0.98, 1.08), col * vec3(1.06, 1.0, 0.92), smoothstep(0.15, 0.7, lum));
	// Canvas grain.
	float g = noise(FRAGCOORD.xy * 0.7) * 0.6 + noise(FRAGCOORD.xy * 0.13) * 0.4;
	col += (g - 0.5) * grain;
	// Vignette.
	vec2 d = uv - 0.5;
	col *= 1.0 - vignette * smoothstep(0.25, 0.8, dot(d, d) * 2.2);
	COLOR = vec4(col, 1.0);
}
