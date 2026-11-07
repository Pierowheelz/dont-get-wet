shader_type spatial;
render_mode cull_disabled;

// Awning canvas (stripes or solid, with trims) or corrugated tin, with grime and a wet sheen.
// UV.x spans the whole awning (`width` metres); UV.y is 0..1 wall to front on the canopy and 1..2
// down the valance.
uniform vec4 color_a : source_color = vec4(0.55, 0.12, 0.1, 1.0);
uniform vec4 color_b : source_color = vec4(0.85, 0.8, 0.7, 1.0);
uniform float width = 4.0;
uniform float stripe_w = 0.45;      // one colour_a + colour_b pair; 0 = solid colour_a
uniform float hem = 0.0;            // colour_b band along the canopy's front edge (fraction of depth)
uniform float seam_w = 0.0;         // spacing of darker rib seams across the canopy; 0 = none
uniform bool valance_solid = false;
uniform bool piping = false;        // two colour_b lines on the valance
uniform bool tin = false;
uniform float grime = 0.5;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float x = UV.x * width;
	bool valance = UV.y > 1.0;
	float vy = valance ? UV.y - 1.0 : UV.y;
	float n = noise(vec2(x * 4.4, UV.y * 6.0)) * 0.6 + noise(vec2(x * 17.8, UV.y * 30.0)) * 0.4;
	// grime streaks run down toward the front edge
	float streak = noise(vec2(x * 6.6, UV.y * 1.5));
	vec3 col;
	if (tin) {
		float groove = 0.5 + 0.5 * sin(x / 0.2 * TAU);   // same phase as the mesh corrugation
		vec3 paint = mix(vec3(0.4, 0.41, 0.4), color_a.rgb, 0.3);
		float rust = smoothstep(0.5, 0.85, noise(vec2(x * 1.2, UV.y * 2.5)) * 0.75 + UV.y * 0.35 + grime * 0.2);
		col = mix(paint, vec3(0.32, 0.15, 0.07), rust) * (0.7 + 0.3 * groove);
		ALBEDO = col * mix(1.0, 0.75, grime * smoothstep(0.55, 0.9, streak));
		METALLIC = mix(0.55, 0.1, rust);
		ROUGHNESS = mix(0.35, 0.8, rust);
	} else {
		col = stripe_w > 0.0 ? mix(color_a.rgb, color_b.rgb, step(0.5, fract(x / stripe_w))) : color_a.rgb;
		if (!valance && UV.y > 1.0 - hem) col = color_b.rgb;
		if (!valance && seam_w > 0.0 && abs(fract(x / seam_w) - 0.5) > 0.475) col *= 0.45;
		if (valance && valance_solid) col = color_a.rgb;
		if (valance && piping && (abs(vy - 0.15) < 0.045 || abs(vy - 0.62) < 0.045)) col = color_b.rgb;
		col *= mix(1.0, 0.45 + 0.4 * n, grime * (0.4 + 0.6 * min(UV.y, 1.0)));
		col *= mix(1.0, 0.7, grime * smoothstep(0.55, 0.9, streak));
		ALBEDO = col * 0.8;
		ROUGHNESS = mix(0.35, 0.7, n);
		SPECULAR = 0.6;
	}
}
