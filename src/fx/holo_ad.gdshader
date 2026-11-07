shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

// Retro-future holographic billboard: drifting abstract shapes, scanlines, glitch flicker.
uniform vec4 tint : source_color = vec4(0.2, 1.0, 0.95, 1.0);
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME + seed;
	float glitch = step(0.97, hash(floor(t * 8.0) + seed)) * (hash(floor(uv.y * 20.0) + t) - 0.5) * 0.1;
	uv.x += glitch;
	// Shapes: a ring, a bar chart, a wordmark block that cycle every few seconds.
	float phase = mod(floor(t / 4.0), 3.0);
	vec2 c = uv - vec2(0.5);
	float shape;
	if (phase < 0.5) {
		float r = length(c * vec2(1.8, 1.0));
		shape = smoothstep(0.03, 0.0, abs(r - 0.3 - 0.05 * sin(t * 2.0)));
	} else if (phase < 1.5) {
		float bar = floor(uv.x * 7.0);
		float hgt = 0.2 + 0.6 * hash(bar + floor(t / 4.0));
		shape = step(1.0 - uv.y, hgt * (0.8 + 0.2 * sin(t * 3.0 + bar))) * step(0.15, fract(uv.x * 7.0));
	} else {
		shape = step(abs(c.y), 0.12) * step(abs(c.x), 0.35 + 0.05 * sin(t));
	}
	float border = step(0.47, max(abs(c.x), abs(c.y)));
	float scan = 0.65 + 0.35 * sin(uv.y * 160.0 - t * 12.0);
	float flick = 0.85 + 0.15 * hash(floor(t * 20.0));
	float a = (shape * 0.9 + border * 0.6 + 0.06) * scan * flick;
	ALBEDO = tint.rgb * a * 2.2;
	ALPHA = a;
}
