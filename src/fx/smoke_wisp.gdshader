shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A thin thread of cigarette smoke on one upright quad: it rises from the bottom middle, wavers and
// widens as it climbs, and thins out to nothing at the top. `drift` leans it downwind (in quad widths).

uniform vec4 color : source_color = vec4(0.62, 0.64, 0.7, 1.0);
uniform float strength = 0.34;
uniform float drift = 0.0;

void fragment() {
	float h = 1.0 - UV.y;
	float x = (UV.x - 0.5) * 2.0;
	float t = TIME;
	float sway = (sin(h * 6.5 - t * 1.5) * 0.2 + sin(h * 13.0 - t * 2.3 + 1.7) * 0.09) * h + drift * h * h;
	float width = mix(0.03, 0.2, h);
	float d = (x - sway) / width;
	// A second, fainter strand that peels away from the first higher up.
	float d2 = (x - sway - (0.1 + 0.25 * sin(h * 4.0 - t * 0.9)) * smoothstep(0.25, 0.9, h)) / (width * 1.3);
	float thread = exp(-d * d * 2.2) + 0.5 * exp(-d2 * d2 * 2.2) * smoothstep(0.2, 0.5, h);
	ALBEDO = color.rgb;
	ALPHA = clamp(thread, 0.0, 1.0) * smoothstep(0.0, 0.05, h) * pow(1.0 - h, 1.3) * strength;
}
