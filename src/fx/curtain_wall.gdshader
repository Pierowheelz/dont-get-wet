shader_type spatial;
// A jet-age curtain wall drawn on one quad: vision glass and spandrel panels floor by floor, slim
// mullions between bays, and offices lit or dark behind the glass. ModernBuilder merges many walls
// into one mesh and passes each wall's look in its vertices:
//   UV      metres along the wall (x) and height above the ground (y)
//   UV2.x   height of the wall's first floor line; UV2.y the floor height
//   COLOR   r seed, g share of offices lit, b palette (0..3 / 4), a detail (1 near: mullions drawn; 0 far)
// Palettes: 0 blue-green glass, sea-green spandrels, stainless (Lever House); 1 bronze glass and
// bronze mullions; 2 grey glass, white enamel spandrels; 3 black glass and black steel.
render_mode specular_schlick_ggx;

uniform float bay_w = 1.6;

varying vec4 look;
varying vec2 floors;

const vec3 GLASS[4] = vec3[](vec3(0.035, 0.085, 0.085), vec3(0.07, 0.05, 0.035), vec3(0.05, 0.065, 0.075), vec3(0.025, 0.03, 0.035));
const vec3 SPAN[4] = vec3[](vec3(0.07, 0.16, 0.15), vec3(0.11, 0.08, 0.05), vec3(0.72, 0.71, 0.66), vec3(0.04, 0.04, 0.045));
const vec3 MULL[4] = vec3[](vec3(0.72, 0.75, 0.78), vec3(0.33, 0.23, 0.13), vec3(0.78, 0.78, 0.76), vec3(0.1, 0.1, 0.11));

void vertex() {
	look = COLOR;
	floors = UV2;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	int pal = clamp(int(look.b * 4.0 + 0.5), 0, 3);
	float seed = look.r * 97.0;
	float fh = max(floors.y, 1.0);
	float fy = UV.y - floors.x;
	float fl = floor(fy / fh);
	float ly = fy - fl * fh;                 // height within the floor
	float bay = floor(UV.x / bay_w);
	float lx = UV.x - bay * bay_w;
	vec2 fw = max(fwidth(UV), vec2(1e-4));
	// Spandrel: the band from the floor line up to the sill, edges softened by the pixel footprint.
	float sill = 0.95;
	float span = 1.0 - smoothstep(sill - fw.y, sill + fw.y, ly);
	span = max(span, smoothstep(fh - 0.12 - fw.y, fh - 0.12 + fw.y, ly));   // slab edge under the next sill
	// Mullions: a line each side of every bay, blended to their average when they get sub-pixel.
	float mw = 0.04;
	float dm = min(lx, bay_w - lx);
	float line = 1.0 - smoothstep(mw - fw.x, mw + fw.x, dm);
	float mull = mix(line, 2.0 * mw / bay_w, smoothstep(mw, mw * 4.0, fw.x)) * look.a;
	// Offices: runs of 2-5 bays per floor, lit or dark; a few whole floors burn late.
	float run = 2.0 + floor(hash3(vec3(fl, seed, 3.0)) * 4.0);
	float room = floor(bay / run);
	float r = hash3(vec3(room, fl, seed));
	float whole = step(0.93, hash3(vec3(fl, seed, 7.0)));
	float on = max(step(r, look.g), whole * step(0.15, look.g));
	vec3 cool = vec3(0.78, 0.9, 1.0);
	vec3 warm = vec3(1.0, 0.82, 0.58);
	vec3 office = mix(cool, warm, step(0.78, hash3(vec3(room, fl, seed + 5.0))));
	float vy = clamp((ly - sill) / (fh - 0.12 - sill), 0.0, 1.0);
	float ceil_glow = 0.55 + 0.45 * smoothstep(0.55, 0.95, vy);
	// Venetian blinds in some lit offices: soft horizontal slats, part-drawn.
	float blinds = step(0.6, hash3(vec3(room, fl, seed + 11.0)));
	float drawn = hash3(vec3(room, fl, seed + 13.0));
	float slat = 0.75 + 0.25 * sin(ly * 60.0);
	float slats = mix(1.0, mix(slat, 0.75, smoothstep(0.01, 0.03, fw.y)) * 0.8, blinds * step(1.0 - drawn, vy));
	float pane = hash3(vec3(bay, fl, seed + 2.0));
	vec3 glass = GLASS[pal] * (0.85 + 0.3 * pane);
	float vision = (1.0 - span) * (1.0 - mull);
	ALBEDO = mix(mix(glass, SPAN[pal], span), MULL[pal], mull);
	METALLIC = mix(mix(0.6, 0.25, span), 0.5, mull);
	ROUGHNESS = mix(mix(0.05 + 0.05 * pane, 0.32, span), 0.28, mull);
	SPECULAR = 0.7;
	EMISSION = office * on * ceil_glow * slats * vision * 0.55;
}
