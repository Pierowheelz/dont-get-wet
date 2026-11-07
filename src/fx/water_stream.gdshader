shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never;

// Falling column of water: scrolling noise streaks, fresnel-bright edges.
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 uv = vec2(UV.x * 6.0, UV.y * 3.0 - TIME * 6.0);
	float n = noise(uv * vec2(2.0, 1.0)) * 0.6 + noise(uv * vec2(6.0, 3.0)) * 0.4;
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float streak = smoothstep(0.45, 0.85, noise(vec2(UV.x * 24.0, UV.y * 2.0 - TIME * 9.0)));
	ALBEDO = vec3(0.32, 0.38, 0.46);
	ALPHA = clamp(0.08 + streak * 0.35 + fres * 0.3, 0.0, 0.6);
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	METALLIC = 0.2;
}
