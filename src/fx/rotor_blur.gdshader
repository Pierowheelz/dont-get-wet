shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The smear a turning rotor blade leaves behind it, as film catches it. Drawn on fans that turn
// with the blades (tools/blender/vehicles.py): UV.x runs from 0 at the blade to 1 where its smear
// has faded, UV.y from the hub (0) to the tip (1). A whole faint disc is the same mesh at one UV.x.
uniform vec3 tint : source_color = vec3(0.6, 0.64, 0.72);
uniform float strength = 0.7;

void fragment() {
	float trail = pow(1.0 - UV.x, 1.7);
	float edge = 1.0 - smoothstep(0.975, 1.0, UV.y);
	float body = smoothstep(0.0, 0.1, UV.y) * (0.4 + 0.6 * UV.y);
	float tip = smoothstep(0.9, 0.945, UV.y);
	ALBEDO = mix(tint, vec3(0.86, 0.88, 0.93), tip * 0.55);
	ALPHA = clamp(strength * trail * (body + tip * 0.35) * edge, 0.0, 1.0);
}
