shader_type spatial;
// A skyway's tinted plate glass: blue-green, faintly reflective, with rain running down it in thin
// rivulets. UV is in metres (x along the street, y up), so the streaks keep their size on every pane.
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.36, 0.58, 0.58, 0.3);
uniform float rain = 1.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = UV;
	float cw = 0.05;                        // rivulet lane width
	float lane = floor(p.x / cw);
	float fx = fract(p.x / cw);
	float h = hash(lane);
	float on = step(0.78, hash(lane * 1.7 + 3.1));
	float y = p.y + TIME * (0.35 + 0.9 * h) + h * 17.0;
	float seg = fract(y / (0.5 + 0.9 * hash(lane + 9.0)));
	float streak = on * smoothstep(0.42, 0.05, abs(fx - 0.5)) * smoothstep(0.0, 0.1, seg) * smoothstep(1.0, 0.55, seg);
	// Beads: small round drops scattered over the pane, fixed in place.
	vec2 cell = floor(p / 0.11);
	vec2 f = fract(p / 0.11) - 0.5;
	float bh = hash(cell.x * 31.0 + cell.y * 7.0);
	float bead = step(0.86, bh) * smoothstep(0.22, 0.08, length(f - vec2(bh - 0.9, 0.0)));
	float wet = clamp(streak * 0.8 + bead * 0.5, 0.0, 1.0) * rain;
	ALBEDO = tint.rgb;
	ALPHA = clamp(tint.a + wet * 0.22, 0.0, 1.0);
	ROUGHNESS = 0.04;
	METALLIC = 0.25;
	SPECULAR = 0.9;
	EMISSION = vec3(0.55, 0.68, 0.75) * wet * 0.12;
	RIM = 0.4;
	RIM_TINT = 0.6;
}
