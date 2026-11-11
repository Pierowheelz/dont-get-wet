shader_type particles;
// Rain streaks. Emitted in a box around the emitter (which follows the camera), falling along
// `fall_dir`. They stop (and splash) on a cover height map built from the level data (awnings,
// slabs, roofs, ground) and on the umbrella canopy, and vanish inside sunny zones — so the visual
// rain matches the gameplay rain model exactly — and under deck spans, out to the camera.

uniform vec3 box_extents = vec3(14.0, 7.0, 5.0);
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform float fall_speed = 9.0;
uniform float streak_length = 0.45;
uniform float intensity = 1.0;          // 0..1.5, fraction of particles alive
uniform vec4 sun_zones[8];              // x0, x1 world; zw unused
uniform int sun_zone_count = 0;
uniform vec3 cam_pos = vec3(0.0, 0.0, 10.0);
uniform float player_plane_z = 1.6;
uniform float sky_y = 3.6;              // Player.RAIN_SKY_Y
uniform float splash_fraction = 0.25;
uniform sampler2D cover_map : filter_nearest, repeat_disable;
uniform vec4 cover_rect = vec4(0.0, -2.0, 100.0, 16.0);   // x0, z0, size_x, size_z (metres)
uniform vec4 umbrella = vec4(0.0, -100.0, 0.0, 0.0);      // canopy centre xyz, radius (0 = closed)

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	uint seed = NUMBER * 7919u + RANDOM_SEED;
	vec3 r = vec3(hash(seed), hash(seed + 1u), hash(seed + 2u));
	vec3 origin = EMISSION_TRANSFORM[3].xyz;
	vec3 pos = origin + (r * 2.0 - 1.0) * box_extents;
	pos.y = origin.y + box_extents.y * (0.85 + 0.15 * r.y);
	vec3 dir = normalize(fall_dir);
	// shift upwind so slanted rain still fills the view
	pos.x -= dir.x / max(-dir.y, 0.2) * box_extents.y;
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = pos;
	VELOCITY = dir * fall_speed * (0.85 + 0.3 * hash(seed + 4u));
	CUSTOM = vec4(hash(seed + 5u), 0.0, 0.0, 0.0);
	ACTIVE = CUSTOM.x < clamp(intensity / 1.5, 0.0, 1.0);
}

void process() {
	vec3 pos = TRANSFORM[3].xyz;
	vec2 cuv = vec2((pos.x - cover_rect.x) / cover_rect.z, (pos.z - cover_rect.y) / cover_rect.w);
	vec3 cm = (cuv.x >= 0.0 && cuv.x <= 1.0 && cuv.y >= 0.0 && cuv.y <= 1.0) ? texture(cover_map, cuv).rgb : vec3(-0.16, 0.0, -0.16);
	bool hit = pos.y < cm.b;
	// Thin shell: only stops drops just below its surface (i.e. ones that fell onto it this step).
	if (cm.g > 0.5 && cm.g < 1.5 && pos.y < cm.r && pos.y > cm.r - 0.3) hit = true;
	if (umbrella.w > 0.05) {
		vec2 d = pos.xz - umbrella.xz;
		if (dot(d, d) < umbrella.w * umbrella.w && pos.y < umbrella.y + 0.12 && pos.y > umbrella.y - 0.35) hit = true;
	}
	bool dead = hit || (cm.g > 1.5 && pos.y < cm.r);   // under a deck: gone, no splash
	// Sun test, matching Player._rain_exposure: a drop reads as falling on whatever it covers on
	// screen, so move it along its camera ray into the player's plane, then follow its fall line to
	// sky_y, where gameplay decides whether that spot is rained on. Testing raw world x instead
	// cut the rain metres early in strong wind and offset it by the camera's lead.
	vec3 p = pos;
	float dz = cam_pos.z - pos.z;
	if (dz > 0.05) p = cam_pos + (pos - cam_pos) * (cam_pos.z - player_plane_z) / dz;
	float sun_x = p.x + fall_dir.x / min(fall_dir.y, -0.01) * (sky_y - p.y);
	for (int i = 0; i < sun_zone_count; i++) {
		if (sun_x > sun_zones[i].x && sun_x < sun_zones[i].y) dead = true;
	}
	if (pos.y < -1.0) dead = true;
	if (hit && CUSTOM.x < splash_fraction * clamp(intensity / 1.5, 0.0, 1.0)) {
		mat4 xf = mat4(1.0);
		xf[3].xyz = pos;
		emit_subparticle(xf, vec3(0.0), vec4(1.0), vec4(0.0), FLAG_EMIT_POSITION);
	}
	if (dead) {
		ACTIVE = false;
	}
	// Orient: local Y along velocity, scaled to streak length; face +Z (side camera).
	vec3 v = normalize(VELOCITY);
	vec3 side = normalize(cross(v, vec3(0.0, 0.0, 1.0)));
	TRANSFORM[0].xyz = side * 0.012;
	TRANSFORM[1].xyz = v * streak_length;
	TRANSFORM[2].xyz = vec3(0.0, 0.0, 1.0);
}
