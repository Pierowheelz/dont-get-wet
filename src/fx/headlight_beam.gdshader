shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// A headlight's beam through rain: brightest at the lamp, fading along the cone, and soft at its
// silhouette (faces seen edge-on fade out) so it never shows a hard outline.
uniform vec3 tint : source_color = vec3(1.0, 0.93, 0.78);
uniform float strength = 0.09;

void fragment() {
	float along = pow(1.0 - UV.y, 1.6);
	float edge = pow(abs(dot(NORMAL, VIEW)), 2.5);
	ALBEDO = tint;
	ALPHA = clamp(strength * along * edge, 0.0, 1.0);
}
