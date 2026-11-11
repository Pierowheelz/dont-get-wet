shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// A sheet of water shaken off the viaduct deck. Noise runs in world space so the segments that make
// up one sheet read as a single curtain. `front`/`back` are the sheet's world x ends: the leading
// edge (left, under the train's nose) is ragged and thin, the trailing edge thins out as it drains.
uniform float front = 0.0;
uniform float back = 11.0;
uniform float top_y = 4.6;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fall = TIME * 8.0;
	// Thin torrents: narrow bright columns that break up as they fall, over a faint film.
	float cols = noise(vec2(wpos.x * 34.0, wpos.y * 0.35 + fall * 0.6));
	float rope = smoothstep(0.55, 0.95, cols) * (0.55 + 0.45 * noise(vec2(wpos.x * 34.0, wpos.y * 2.5 + fall * 2.2)));
	float film = noise(vec2(wpos.x * 5.0, wpos.y * 1.2 + fall)) * 0.5 + 0.5 * noise(vec2(wpos.x * 13.0, wpos.y * 3.0 + fall * 1.5));
	float span = clamp((wpos.x - front) / max(back - front, 0.01), 0.0, 1.0);
	float lead = smoothstep(0.0, 0.06, span);
	float trail = 1.0 - smoothstep(0.5, 1.0, span);
	float lip = smoothstep(top_y, top_y - 0.25, wpos.y);
	float a = (0.05 + 0.14 * film + 0.75 * rope) * lead * mix(0.3, 1.0, trail) * lip;
	ALBEDO = vec3(0.72, 0.8, 0.9);
	EMISSION = vec3(0.32, 0.38, 0.46) * rope;
	ALPHA = clamp(a, 0.0, 0.85);
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
}
