shader_type spatial;
// An aircraft warning light on a skyscraper: red, slowly flashing, each on its own phase.
render_mode unshaded, shadows_disabled;

instance uniform float phase = 0.0;

void fragment() {
	float on = smoothstep(0.0, 0.08, fract(TIME * 0.5 + phase)) * (1.0 - smoothstep(0.45, 0.6, fract(TIME * 0.5 + phase)));
	ALBEDO = vec3(1.0, 0.12, 0.08) * (0.3 + 4.0 * on);
}
