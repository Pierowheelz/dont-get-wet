// Rain-soaked ground (sidewalk, asphalt). World-space XZ mapping so adjacent ground pieces tile
// seamlessly; darker albedo + low roughness everywhere (wetness), plus a noise-driven puddle mask
// where the surface becomes a near-mirror with animated rain ripples.
// Generated alongside tools/blender/gen_materials.py (edit parameters there or in the .tres files).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D puddle_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile_size = 2.0;          // metres per texture repeat
uniform float wetness : hint_range(0.0, 1.0) = 1.0;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.35;
uniform float puddle_scale = 8.0;       // metres per puddle-noise repeat
uniform bool world_uv = true;
uniform float ripple_strength = 0.6;
uniform float ripple_density = 3.0;     // ripple cells per metre
uniform float ripple_speed = 1.1;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 ripples(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 acc = vec2(0.0);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 c = cell + vec2(float(i), float(j));
			float h = hash12(c);
			vec2 centre = vec2(float(i), float(j)) + vec2(hash12(c + 1.7), hash12(c + 3.1));
			float phase = fract(t + h);
			vec2 d = f - centre;
			float r = length(d);
			float ring = phase * 0.9;
			float w = sin((r - ring) * 40.0) * smoothstep(0.12, 0.0, abs(r - ring)) * (1.0 - phase);
			acc += d / max(r, 1e-3) * w;
		}
	}
	return acc;
}

void fragment() {
	vec2 uv = world_uv ? vec2(world_pos.x, world_pos.z) / tile_size : UV;
	vec3 alb = texture(albedo_tex, uv).rgb * tint.rgb;
	float base_r = texture(rough_tex, uv).r;
	vec3 nm = texture(normal_tex, uv).rgb;

	float n = texture(puddle_noise, world_pos.xz / puddle_scale).r;
	float thr = 1.0 - puddle_amount;
	float puddle = smoothstep(thr, thr + 0.06, n) * wetness;
	// damp rim around puddles + cavities (dark texels) hold more water
	float cavity = 1.0 - clamp(dot(texture(albedo_tex, uv).rgb, vec3(0.333)) * 1.6, 0.0, 1.0);
	float damp = clamp(wetness * (0.75 + 0.25 * cavity) + smoothstep(thr - 0.12, thr, n) * 0.3, 0.0, 1.0);

	alb *= mix(1.0, 0.42, damp);
	alb = mix(alb, alb * 0.55, puddle);
	float rough = mix(base_r, base_r * 0.22 + 0.04, damp);
	rough = mix(rough, 0.03, puddle);

	vec2 rp = ripples(world_pos.xz * ripple_density, TIME * ripple_speed) * ripple_strength * puddle;
	vec3 flat_n = vec3(0.5, 0.5, 1.0);
	nm = mix(nm, flat_n, clamp(puddle + damp * 0.35, 0.0, 1.0));
	nm.xy += rp * 0.5;

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0;
}
