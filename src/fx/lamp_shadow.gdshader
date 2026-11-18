shader_type spatial;
// A man's long shadow thrown along the pavement by a lamp behind him: legs mid-stride, coat,
// shoulders, head and an open umbrella's dome at the far end. UV.x runs from his feet (0) to the tip
// of the umbrella's shadow (1); UV.y across. The penumbra widens toward the tip, as a lamp's does.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float alpha : hint_range(0.0, 1.0) = 0.8;
uniform float stride = 0.0;          // walking phase, radians
uniform vec3 tint : source_color = vec3(0.0, 0.0, 0.005);

float band(float v, float c, float hw, float blur) {
	return 1.0 - smoothstep(hw - blur, hw + blur, abs(v - c));
}

void fragment() {
	float u = UV.x;
	float v = UV.y - 0.5;
	float blur = 0.012 + 0.05 * u;
	// Legs: two strips from the feet to the hip, scissoring with his stride.
	float swing = 0.1 * sin(stride) * (1.0 - smoothstep(0.0, 0.4, u));
	float legs = max(band(v, swing, 0.06, blur), band(v, -swing, 0.06, blur)) * (1.0 - smoothstep(0.38, 0.42, u));
	// Coat and shoulders.
	float coat_w = mix(0.13, 0.2, smoothstep(0.38, 0.68, u));
	float coat = band(v, 0.0, coat_w, blur) * smoothstep(0.36, 0.4, u) * (1.0 - smoothstep(0.69, 0.72, u));
	// Head.
	float head = 1.0 - smoothstep(0.045 - blur, 0.045 + blur, length(vec2((u - 0.745) * 1.2, (v + 0.01) * 0.75)));
	// The arm up to the shaft, and the umbrella's dome beyond his head.
	float shaft = band(v, 0.1, 0.025, blur) * smoothstep(0.6, 0.62, u) * (1.0 - smoothstep(0.84, 0.86, u));
	float du = clamp((u - 0.8) / 0.2, 0.0, 1.0);
	float dome_w = 0.46 * sqrt(max(1.0 - du * du, 0.0));
	float dome = band(v, 0.06, dome_w, blur) * smoothstep(0.78, 0.81, u);
	float shape = max(max(legs, coat), max(head, max(shaft, dome)));
	// Darkest at his feet, thinning out toward the tip.
	ALBEDO = tint;
	ALPHA = shape * alpha * mix(1.0, 0.8, u);
}
