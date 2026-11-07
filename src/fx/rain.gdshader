shader_type particles;
// Rain streaks. Emitted in a box around the emitter (which follows the camera), falling along
// `fall_dir`. Killed on collision with the height-field (awnings, umbrella, ground) and inside
// sunny zones, so the visual rain matches the gameplay rain model.

uniform vec3 box_extents = vec3(14.0, 7.0, 5.0);
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform float fall_speed = 9.0;
uniform float streak_length = 0.45;
uniform float intensity = 1.0;          // 0..1.5, fraction of particles alive
uniform vec4 sun_zones[8];              // x0, x1 world; zw unused
uniform int sun_zone_count = 0;
uniform float splash_fraction = 0.25;

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
	bool dead = COLLIDED;
	for (int i = 0; i < sun_zone_count; i++) {
		if (pos.x > sun_zones[i].x && pos.x < sun_zones[i].y) dead = true;
	}
	if (pos.y < -1.0) dead = true;
	if (COLLIDED && CUSTOM.x < splash_fraction * clamp(intensity / 1.5, 0.0, 1.0)) {
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
