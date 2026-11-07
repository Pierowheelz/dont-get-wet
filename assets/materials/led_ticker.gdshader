// Scrolling dot-matrix LED ticker. text_tex is a white-on-black text strip (led_text.png);
// the quad's UV (0..1) shows `window` of it, scrolling with TIME * speed.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D text_tex : source_color, filter_linear, repeat_enable;
uniform vec4 color : source_color = vec4(1.0, 0.62, 0.15, 1.0);
uniform float speed = 0.05;
uniform float window = 0.18;        // fraction of the strip visible at once
uniform vec2 dots = vec2(160.0, 12.0);
uniform float energy = 3.0;

void fragment() {
	vec2 cell = floor(UV * dots) + 0.5;
	vec2 uvq = cell / dots;
	float u = fract(uvq.x * window + TIME * speed);
	float lum = texture(text_tex, vec2(u, uvq.y)).r;
	vec2 f = fract(UV * dots) - 0.5;
	float dotmask = smoothstep(0.5, 0.3, length(f));
	float on = step(0.35, lum);
	vec3 off_col = color.rgb * 0.06;
	ALBEDO = mix(off_col * dotmask, color.rgb * energy, on * dotmask);
}
