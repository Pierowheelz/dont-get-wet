shader_type spatial;
// The skyscrapers behind the glass city, each face one quad in a merged mesh: dark walls, windows
// lit in runs, and its own haze instead of the scene's fog, so the far rows sit paler and bluer than
// the near ones and their lit windows still carry. ModernBuilder passes each face's look in its
// vertices:
//   UV      metres along the face (x) and height above the ground (y)
//   UV2.x   shade (1 a street face, less for a flank)
//   COLOR   r seed, g share of windows lit, b haze (0 near .. 1 lost in it), a style
// Styles: 0 ribbon windows, 0.5 a grid of punched windows, 1 tall slots between piers.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec3 haze : source_color = vec3(0.15, 0.17, 0.24);

varying vec4 look;
varying float shade;

void vertex() {
	look = COLOR;
	shade = UV2.x;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	float seed = look.r * 91.0;
	int style = int(look.a * 2.0 + 0.5);
	float fh = 3.6;
	float bw = 2.0 + 1.6 * fract(seed * 0.37);
	vec2 cell = UV / vec2(bw, fh);
	float fl = floor(cell.y);
	float bay = floor(cell.x);
	vec2 f = fract(cell);
	vec2 px = max(fwidth(cell), vec2(1e-4));
	// Where the glass is within a cell.
	float y0 = style == 2 ? 0.06 : 0.32;
	float x0 = style == 0 ? -1.0 : (style == 1 ? 0.2 : 0.3);
	float glass = smoothstep(y0 - px.y, y0 + px.y, f.y) * (1.0 - smoothstep(0.9 - px.y, 0.9 + px.y, f.y));
	glass *= smoothstep(x0 - px.x, x0 + px.x, f.x) * (1.0 - smoothstep(1.0 - x0 - px.x, 1.0 - x0 + px.x, f.x));
	// Rooms lit in runs along a floor; a few whole floors burn late.
	float run = 1.0 + floor(hash3(vec3(fl, seed, 3.0)) * (style == 0 ? 6.0 : 3.0));
	float room = floor(bay / run);
	float on = step(hash3(vec3(room, fl, seed)), look.g);
	on = max(on, step(0.95, hash3(vec3(fl, seed, 7.0))) * step(0.1, look.g));
	vec3 lamp = mix(vec3(0.75, 0.88, 1.0), vec3(1.0, 0.8, 0.52), step(0.68, hash3(vec3(room, fl, seed + 5.0))));
	lamp *= 0.45 + 0.55 * hash3(vec3(room, fl, seed + 9.0));
	vec3 wall = vec3(0.026, 0.03, 0.042) * (0.8 + 0.5 * fract(seed * 0.13)) * shade;
	vec3 col = mix(wall, mix(wall * 1.7 + vec3(0.0, 0.004, 0.008), lamp * shade, on), glass);
	// Haze: thicker the farther the row, and pooled low where the city's light gathers in the rain.
	float low = exp(-UV.y / 28.0);
	float hz = clamp(look.b + 0.3 * low, 0.0, 0.96);
	ALBEDO = mix(col, haze * (1.0 + 0.7 * low), hz);
}
