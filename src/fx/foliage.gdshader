shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
// Leaves on a country street (CountryBuilder): tree crowns and hedges, drawn as painterly clumps of
// wet green that drift in the breeze and thrash in a gust. `gust` (0..1) is set per node by the
// squalls; `gust_dir` is the way the wind blows along the street (+1 toward +X).
// Card foliage from a model brings its own texture (`use_tex`) and is cut out on its alpha.

uniform vec3 leaf_dark : source_color = vec3(0.07, 0.12, 0.06);
uniform vec3 leaf_light : source_color = vec3(0.27, 0.36, 0.13);
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform bool use_tex = false;
uniform float alpha_cut = 0.35;
uniform float gust = 0.0;           // 0..1: how hard a gust is shaking this node
uniform float gust_dir = 1.0;       // +1 the wind blows toward +X, -1 toward -X
uniform float sway = 0.1;           // metres the crown drifts in a breeze at the top of `reach`
uniform float base_y = 3.0;         // world height where the foliage starts to move
uniform float reach = 6.0;          // height over which the motion grows to full
uniform float wet = 0.7;            // 0..1 how glossy the rain has left the leaves
uniform float leaf_scale = 1.1;     // how fine the clumps of light and dark leaves are
uniform float flutter = 1.0;        // 0 for something leafy-looking that doesn't move (hay)

varying vec3 wpos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 w = VERTEX;
	float h = clamp((w.y - base_y) / max(reach, 0.01), 0.0, 1.0);
	h *= h;   // stiff low down, freest at the top
	float g = clamp(gust, 0.0, 1.0);
	float ph = w.x * 0.23 + w.z * 0.11;
	float t = TIME;
	vec3 off = vec3(0.0);
	// A breeze: slow drifting of the whole crown.
	off.x += sway * (0.6 * sin(t * 0.8 + ph) + 0.3 * sin(t * 2.1 + ph * 2.3));
	off.z += sway * 0.4 * sin(t * 1.1 + ph * 1.7);
	// A gust: the crown leans hard downwind and pumps, and every clump thrashes.
	off.x += gust_dir * g * reach * 0.09 * (1.0 + 0.35 * sin(t * 4.3 + ph));
	off.y -= g * reach * 0.025;
	off *= h;
	float leaf = (0.015 + 0.1 * g) * flutter;
	off += leaf * (0.4 + 0.6 * h) * vec3(sin(t * 9.0 + ph * 7.0), 0.6 * sin(t * 12.0 + ph * 5.0), cos(t * 8.0 + ph * 6.0));
	VERTEX = w + off;
	wpos = w;
}

void fragment() {
	// Clumps of light and dark leaves in world space, so neighbouring trees never repeat.
	vec3 q = wpos * leaf_scale;
	float n = noise3(q) * 0.55 + noise3(q * 2.8 + 7.0) * 0.3 + noise3(q * 7.3) * 0.15;
	vec3 col = mix(leaf_dark, leaf_light, smoothstep(0.3, 0.75, n));
	// The sky lights the tops of the clumps; their undersides sit in their own shade.
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	col *= mix(0.6, 1.08, clamp(wn.y * 0.5 + 0.5, 0.0, 1.0));
	if (use_tex) {
		vec4 tx = texture(leaf_tex, UV);
		if (tx.a < alpha_cut) {
			discard;
		}
		col *= tx.rgb * 1.6;
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.4, wet);
	SPECULAR = 0.35 + 0.25 * wet;
	BACKLIGHT = col * 0.6;   // a low sun shines through the leaves
}
