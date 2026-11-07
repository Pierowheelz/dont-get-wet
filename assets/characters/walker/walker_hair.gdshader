shader_type spatial;
// Hair cards for the walker. Wetness darkens, adds gloss and pulls the hair flat to the scalp.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float flatten_m = 0.004;

void vertex() {
	VERTEX -= NORMAL * flatten_m * wetness;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * mix(1.0, 0.55, wetness);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = mix(0.72, 0.5, wetness);
	SPECULAR = mix(0.35, 0.5, wetness);
}
