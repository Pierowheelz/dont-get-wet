shader_type spatial;
// A jet-age curtain wall drawn on one quad: bands of vision glass between enamel spandrels, slim
// aluminium mullions and transoms, and behind the glass a room for every office, drawn by casting
// the view ray into a box (interior mapping): the ceiling with its strip lights, the back wall with
// its desks and a door, the partitions either side. Offices are lit or dark in runs of bays, a few
// whole floors burn late, some have blinds part-drawn. Each pane tilts a hair differently, so the
// sky it mirrors breaks up pane by pane, and the glass turns to mirror where it is seen at a glance:
// the floors high overhead. ModernBuilder merges many walls into one mesh and passes each wall's
// look in its vertices:
//   UV      metres along the wall (x, the way the wall runs to the viewer's right) and height (y)
//   UV2.x   height of the wall's first floor line; UV2.y the floor height
//   COLOR   r seed, g share of offices lit, b palette (0..3 / 4), a detail (1 near; less far: mullions fade)
// Palettes: 0 blue-green glass over sea-green enamel, stainless mullions; 1 bronze glass and bronze
// mullions; 2 grey glass, white enamel spandrels; 3 black glass and black steel.
render_mode specular_schlick_ggx;

uniform float bay_w = 1.6;
uniform float room_depth = 4.6;

varying vec4 look;
varying vec2 floors;
varying vec3 wpos;
varying vec3 wnrm;

const vec3 GLASS[4] = vec3[](vec3(0.03, 0.075, 0.075), vec3(0.065, 0.045, 0.03), vec3(0.045, 0.06, 0.07), vec3(0.02, 0.024, 0.03));
const vec3 TINT[4] = vec3[](vec3(0.78, 1.0, 0.94), vec3(1.0, 0.84, 0.62), vec3(0.92, 0.97, 1.0), vec3(0.62, 0.66, 0.7));
const vec3 SPAN[4] = vec3[](vec3(0.09, 0.3, 0.29), vec3(0.2, 0.13, 0.07), vec3(0.72, 0.72, 0.68), vec3(0.035, 0.037, 0.042));
const vec3 MULL[4] = vec3[](vec3(0.74, 0.77, 0.8), vec3(0.36, 0.25, 0.14), vec3(0.8, 0.8, 0.78), vec3(0.1, 0.1, 0.11));

void vertex() {
	look = COLOR;
	floors = UV2;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

// A line `w` wide at distance `d`, softened by the pixel footprint `px`, easing to its average
// cover `avg` once it is thinner than a pixel (so far walls don't shimmer).
float line(float d, float w, float px, float avg) {
	return mix(1.0 - smoothstep(w - px, w + px, d), avg, smoothstep(w, w * 4.0, px));
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
	vec2 px = max(fwidth(UV), vec2(1e-4));
	float sill = 0.8;
	float head = fh - 0.34;
	float span = clamp(1.0 - smoothstep(sill - px.y, sill + px.y, ly) + smoothstep(head - px.y, head + px.y, ly), 0.0, 1.0);
	float mull = line(min(lx, bay_w - lx), 0.035, px.x, 0.07 / bay_w) * look.a;
	float tran = line(min(abs(ly - sill), abs(ly - head)), 0.03, px.y, 0.12 / fh) * look.a;
	float frame = max(mull, tran);

	// Offices: runs of 2-5 bays per floor, each lit or dark; a few whole floors burn late.
	float run = 2.0 + floor(hash3(vec3(fl, seed, 3.0)) * 4.0);
	float room = floor(bay / run);
	float whole = step(0.93, hash3(vec3(fl, seed, 7.0)));
	float on = max(step(hash3(vec3(room, fl, seed)), look.g), whole * step(0.15, look.g));
	vec3 lamp = mix(vec3(0.8, 0.92, 1.0), vec3(1.0, 0.82, 0.58), step(0.78, hash3(vec3(room, fl, seed + 5.0))));
	lamp *= 0.7 + 0.45 * hash3(vec3(room, fl, seed + 9.0));

	// The room behind the glass: a box W wide, `head` high, room_depth deep. d runs along the wall,
	// up, and into the building.
	vec3 view = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 along = normalize(cross(vec3(0.0, 1.0, 0.0), wnrm));
	vec3 d = vec3(dot(view, along), view.y, max(-dot(view, wnrm), 1e-3));
	d.x = abs(d.x) > 1e-4 ? d.x : 1e-4;
	d.y = abs(d.y) > 1e-4 ? d.y : 1e-4;
	float room_w = run * bay_w;
	vec3 p = vec3(UV.x - room * room_w, min(ly, head - 0.01), 0.0);
	vec3 t3 = (vec3(d.x > 0.0 ? room_w : 0.0, d.y > 0.0 ? head : 0.0, room_depth) - p) / d;
	float t = min(t3.x, min(t3.y, t3.z));
	vec3 hit = p + d * t;
	vec3 wall = mix(vec3(0.66, 0.6, 0.5), vec3(0.42, 0.52, 0.5), step(0.55, hash3(vec3(room, fl, seed + 17.0))));
	vec3 inside;
	if (t == t3.y) {
		if (d.y > 0.0) {
			// The ceiling: a strip light down the middle of every bay, in lengths.
			float strip = step(abs(fract(hit.x / bay_w) - 0.5), 0.15) * step(0.14, fract(hit.z / 1.5));
			inside = mix(vec3(0.42), vec3(1.9), strip);
		} else {
			inside = vec3(0.1, 0.085, 0.08);
		}
	} else if (t == t3.z) {
		// The back wall: desks and cabinets along its foot, a door somewhere in it.
		float desk = step(hit.y, 0.8) * step(0.35, hash3(vec3(floor(hit.x / 1.1), room + fl * 7.0, seed)));
		float door = step(abs(hit.x - room_w * (0.2 + 0.6 * hash3(vec3(room, fl, seed + 23.0)))), 0.45) * step(hit.y, 2.05);
		inside = wall * mix(0.62, 0.22, max(desk, door * 0.75));
	} else {
		inside = wall * 0.42;
	}
	inside *= mix(1.0, 0.6, clamp(hit.z / room_depth, 0.0, 1.0));
	// Venetian blinds in some offices, part-drawn from the head.
	float vy = clamp((ly - sill) / (head - sill), 0.0, 1.0);
	float blinds = step(0.64, hash3(vec3(room, fl, seed + 11.0))) * step(1.0 - hash3(vec3(room, fl, seed + 13.0)), vy);
	float slat = mix(0.8 + 0.2 * sin(ly * 70.0), 0.8, smoothstep(0.01, 0.03, px.y));
	inside = mix(inside, vec3(0.8, 0.76, 0.66) * 0.5 * slat, blinds);
	vec3 through = inside * mix(vec3(0.02, 0.024, 0.032), lamp, on) * TINT[pal];

	// The glass itself: each pane a hair out of true, mirroring the night sky (or the dark street).
	float pane = hash3(vec3(bay, fl, seed + 2.0));
	vec3 n2 = normalize(wnrm + along * (pane - 0.5) * 0.07 + vec3(0.0, 1.0, 0.0) * (hash3(vec3(bay, fl, seed + 4.0)) - 0.5) * 0.07);
	vec3 refl = reflect(view, n2);
	float fres = 0.06 + 0.94 * pow(1.0 - clamp(dot(-view, wnrm), 0.0, 1.0), 4.0);
	vec3 sky = mix(vec3(0.02, 0.024, 0.034), vec3(0.15, 0.19, 0.28), smoothstep(-0.1, 0.55, refl.y)) * (0.75 + 0.5 * pane);

	float vision = (1.0 - span) * (1.0 - frame);
	vec3 solid = mix(SPAN[pal] * (0.92 + 0.16 * pane), MULL[pal], frame);
	// The street's glow lifts the lower floors' metal and enamel a little; the sky does the rest.
	vec3 spill = solid * (vec3(1.0, 0.8, 0.6) * 0.1 * exp(-UV.y / 14.0) + vec3(0.02, 0.025, 0.035));
	ALBEDO = mix(solid, GLASS[pal], vision);
	METALLIC = mix(mix(0.3, 0.75, frame), 0.3, vision);
	ROUGHNESS = mix(mix(0.3, 0.26, frame), 0.05 + 0.05 * pane, vision);
	SPECULAR = 0.7;
	EMISSION = vision * (through * (1.0 - fres) + sky * fres) + (1.0 - vision) * spill;
}
