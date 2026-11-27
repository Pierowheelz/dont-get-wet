shader_type spatial;
// The ground on a country street (CountryBuilder), patterned in world space so it never repeats:
//   mode 0  the grass verge, with the worn footpath the walker follows (path_z0..path_z1) trodden
//           to wet mud and standing water down its middle
//   mode 1  fields and hills: a patchwork of pasture, ploughland and stubble, cut by darker field edges
//   mode 2  the lane: wet tarmac gone grey at the edges, puddles in the ruts

uniform int mode = 0;
uniform vec3 grass_a : source_color = vec3(0.16, 0.24, 0.09);
uniform vec3 grass_b : source_color = vec3(0.3, 0.36, 0.14);
uniform vec3 mud : source_color = vec3(0.2, 0.15, 0.1);
uniform vec3 tarmac : source_color = vec3(0.07, 0.07, 0.075);
uniform float path_z0 = 0.95;
uniform float path_z1 = 2.25;
uniform float cell = 46.0;         // field width along the street (mode 1)

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise2(p) * 0.55 + noise2(p * 2.3 + 5.1) * 0.3 + noise2(p * 5.7 + 1.7) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 col;
	float rough;
	float spec = 0.5;
	if (mode == 0) {
		float g = fbm(p * vec2(0.9, 1.6));
		col = mix(grass_a, grass_b, smoothstep(0.25, 0.8, g));
		// Tufts: fine streaks across the verge.
		col *= 0.85 + 0.3 * noise2(p * vec2(9.0, 30.0));
		rough = 0.62;
		// The footpath: edges that wander, mud down the middle, standing water in the dips.
		float wob = (fbm(vec2(p.x * 0.35, 3.0)) - 0.5) * 0.5;
		float a = smoothstep(path_z0 - 0.25, path_z0 + 0.15, p.y + wob);
		float b = 1.0 - smoothstep(path_z1 - 0.15, path_z1 + 0.25, p.y + wob * 0.8);
		float worn = a * b * (0.75 + 0.25 * noise2(p * 3.0));
		vec3 path = mix(mud, mud * 1.35 + vec3(0.03, 0.03, 0.02), noise2(p * 2.2));
		col = mix(col, path, smoothstep(0.2, 0.7, worn));
		rough = mix(rough, 0.3, worn);
		float pool = smoothstep(0.66, 0.74, fbm(p * vec2(0.45, 1.2) + 11.0)) * smoothstep(0.5, 0.9, worn);
		col = mix(col, col * 0.35, pool);
		rough = mix(rough, 0.03, pool);
		spec = mix(spec, 0.8, pool);
	} else if (mode == 1) {
		// Fields along the street, their edges wandering; each its own crop.
		float fx = (p.x + (fbm(vec2(p.y * 0.02, 1.0)) - 0.5) * cell * 0.6) / cell;
		float fz = (p.y + (fbm(vec2(p.x * 0.02, 4.0)) - 0.5) * 20.0) / 38.0;
		vec2 id = floor(vec2(fx, fz));
		float k = hash2(id);
		vec3 pasture = mix(grass_a, grass_b, 0.4 + 0.5 * hash2(id + 3.0));
		vec3 plough = vec3(0.2, 0.14, 0.09) * (0.9 + 0.3 * hash2(id + 5.0));
		vec3 stubble = vec3(0.38, 0.33, 0.17);
		col = k < 0.62 ? pasture : (k < 0.84 ? plough : stubble);
		// Furrows and mown rows across the ploughland and stubble.
		float rows = 0.85 + 0.15 * sin((p.x * 0.8 + p.y * 0.3) * 3.0);
		col *= k < 0.62 ? 0.9 + 0.2 * fbm(p * 0.3) : rows;
		// Darker margins where a field meets its hedge.
		vec2 e = abs(fract(vec2(fx, fz)) - 0.5);
		col *= mix(0.6, 1.0, smoothstep(0.43, 0.38, max(e.x * 1.0, e.y)));
		rough = 0.8;
	} else {
		float g = fbm(p * vec2(0.6, 1.4));
		col = tarmac * (0.8 + 0.4 * g);
		float pool = smoothstep(0.62, 0.7, fbm(p * vec2(0.25, 0.9) + 3.0));
		col = mix(col, col * 0.5, pool);
		rough = mix(0.18, 0.02, pool);
		spec = 0.7;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
