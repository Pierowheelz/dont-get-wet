shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// A spinning rotor seen as a blur: a faint disc, darker toward the tips where the blades sweep
// fastest, a lighter tip ring, and a few blade streaks turning with it. Drawn on a flat disc whose
// UV runs across it (centre at 0.5, 0.5).
uniform vec3 tint : source_color = vec3(0.16, 0.17, 0.2);
uniform float blades = 5.0;
uniform float spin = 18.0;          // rad/s the streaks turn at
uniform float strength = 0.32;
uniform float hub = 0.08;           // share of the radius the hub covers

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x) + TIME * spin;
	float streak = pow(0.5 + 0.5 * cos(a * blades), 6.0);
	float body = smoothstep(hub, hub + 0.15, r) * (0.35 + 0.65 * r);
	float tip = smoothstep(0.86, 0.93, r) * (1.0 - smoothstep(0.96, 1.0, r));
	ALBEDO = mix(tint, vec3(0.85, 0.86, 0.9), tip * 0.6);
	ALPHA = clamp(strength * (body * (0.45 + 0.55 * streak) + tip * 0.7) * (1.0 - smoothstep(0.97, 1.0, r)), 0.0, 1.0);
}
