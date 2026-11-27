shader_type spatial;
// Aircraft warning lights on the skyscrapers: red, a hot core in a soft halo, slowly flashing (each
// on its own phase) or steady. All of a street's lights are one mesh of quads that turn to face the
// camera here: every corner of a quad sits at the light's own position, and
//   UV      the corner (0..1)
//   COLOR   r phase, g radius in metres / 8, b 1 steady, 0 flashing
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

varying vec4 look;

void vertex() {
	look = COLOR;
	vec3 c = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	c.xy += (UV * 2.0 - 1.0) * COLOR.g * 8.0;
	VERTEX = c;
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float ph = fract(TIME * 0.5 + look.r);
	float on = mix(smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.45, 0.6, ph)), 1.0, look.b);
	float core = 1.0 - smoothstep(0.1, 0.24, r);
	float halo = pow(max(1.0 - r, 0.0), 3.0);
	ALBEDO = vec3(1.0, 0.1, 0.06) * (core * 3.0 + halo * 0.7) * (0.12 + 0.88 * on);
}
