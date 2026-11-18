class_name DropletBurst
extends Node3D
## A burst of water droplets flown one by one, so what wets the walker is exactly what the player
## sees reach him. Each droplet falls under gravity; near the walker every step is checked against
## his open canopy and lot cover (it stops there) and against his body from the knees up (a capsule:
## it lands, and he gets `wet_per_drop` wetter, TORSO_WEIGHT times that on his torso; his shins, which no umbrella can cover, don't count). Droplets that miss fall to the street. A car's splash and a fired
## water shot are both bursts.
##   var b := DropletBurst.spawn(level, starts, velocities, wet_per_drop)
##   b.hit.connect(func(amount: float) -> void: ...)        # each step's landed droplets
##   b.done.connect(func(landed: int, stopped: int) -> void: ...)

signal hit(amount: float)
signal done(landed: int, stopped: int)

const GRAVITY := 9.8
const BODY_R := 0.2           # the walker as a capsule round his line, from his knees (no umbrella can
const BODY_LOW := 0.55        # cover his shins, so droplets there don't count)...
const BODY_TOP := 1.75        # ...to the top of his head
const TORSO := [0.95, 1.45]   # waist to shoulders: what soaks through first, so a droplet there counts
const TORSO_WEIGHT := 1.2     # TORSO_WEIGHT times
const NEAR := 1.6             # within this of him (x and z) a droplet is checked each step
const LIFE := 2.5

var level: Node
var wet_per_drop := 1.0
var through_umbrella := false # the canopy doesn't stop these (a parting shot that can't be blocked)
var landed := 0               # droplets that reached his body
var stopped := 0              # droplets his canopy stopped
var stopped_cover := 0        # droplets an awning or other lot cover stopped
var max_wet := INF            # the most the whole burst can add
var wet_given := 0.0
var size := 0.09
var trail := 0                # ghost copies behind each droplet, so a fast one reads as a streak
var trail_dt := 0.014
var color := Color(0.75, 0.85, 1.0, 0.75)
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _scale := PackedFloat32Array()
var _alive: Array[bool] = []
var _live := 0
var _t := 0.0
var _mm: MultiMeshInstance3D
var _splash: GPUParticles3D


static func spawn(p_level: Node, starts: PackedVector3Array, velocities: PackedVector3Array, p_wet_per_drop: float,
		opts := {}) -> DropletBurst:
	var b := DropletBurst.new()
	b.level = p_level
	b.wet_per_drop = p_wet_per_drop
	for k in opts:
		b.set(k, opts[k])
	b._pos = starts.duplicate()
	b._vel = velocities.duplicate()
	for i in starts.size():
		b._scale.append(randf_range(0.6, 1.4))
		b._alive.append(true)
	b._live = starts.size()
	p_level.add_child(b)
	return b


## A cone of `n` velocities round `dir` (half-angle `spread` rad, speeds `v_min`..`v_max`).
static func cone(n: int, dir: Vector3, spread: float, v_min: float, v_max: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var d := dir.normalized()
	var a := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := d.cross(a)
	for i in n:
		var r := spread * sqrt(randf())
		var th := randf() * TAU
		var v := (d * cos(r) + (a * cos(th) + b * sin(th)) * sin(r)).normalized()
		out.append(v * randf_range(v_min, v_max))
	return out


func _ready() -> void:
	top_level = true
	_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = CarHazard._droplet_tex()
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.billboard_keep_scale = true
	q.material = dm
	mm.mesh = q
	mm.instance_count = _pos.size() * (trail + 1)
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.extra_cull_margin = 16.0
	add_child(_mm)
	_splash = GPUParticles3D.new()
	_splash.amount = 64
	_splash.lifetime = 0.45
	_splash.explosiveness = 0.0
	_splash.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, -9.8, 0)
	_splash.process_material = pm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.05, 0.05)
	var sm := dm.duplicate() as StandardMaterial3D
	sm.vertex_color_use_as_albedo = false
	sm.albedo_color = color
	sq.material = sm
	_splash.draw_pass_1 = sq
	_splash.visibility_aabb = AABB(Vector3(-20, -4, -4), Vector3(40, 8, 8))
	add_child(_splash)
	_draw()


func _physics_process(delta: float) -> void:
	_t += delta
	var p: Player = level.player
	var near_x := p.global_position.x
	var near_z := p.global_position.z
	var foot := p.global_position.y
	var space := get_world_3d().direct_space_state
	var mask := Player.COVER_MASK | (0 if through_umbrella else Player.UMBRELLA_MASK)
	var got := 0.0
	for i in _pos.size():
		if not _alive[i]:
			continue
		var a := _pos[i]
		var v := _vel[i]
		v.y -= GRAVITY * delta
		var b := a + v * delta
		_vel[i] = v
		if absf(b.x - near_x) < NEAR and absf(b.z - near_z) < NEAR and b.y < foot + 3.2:
			var q := PhysicsRayQueryParameters3D.create(a, b, mask)
			q.hit_back_faces = true
			var h := space.intersect_ray(q)
			if not h.is_empty():
				var umb := (h["collider"] as CollisionObject3D).collision_layer & Player.UMBRELLA_MASK != 0
				if umb:
					stopped += 1
				else:
					stopped_cover += 1
				_kill(i, h["position"])
				continue
			var on := _body_hit(a, b, Vector3(near_x, foot, near_z))
			if p.state != Player.State.DEFEATED and on >= 0.0:
				landed += 1
				got += TORSO_WEIGHT if on >= TORSO[0] and on <= TORSO[1] else 1.0
				_kill(i, b)
				continue
		if (v.y < 0.0 and b.y < level.ground_y(b.x)) or _t > LIFE:   # falling onto the street (the kerb lip doesn't catch a rising one)
			_kill(i, b if b.y >= level.ground_y(b.x) else Vector3(b.x, level.ground_y(b.x) + 0.02, b.z))
			continue
		_pos[i] = b
	if got > 0 and wet_given < max_wet:
		var amount := minf(got * wet_per_drop, max_wet - wet_given)
		wet_given += amount
		hit.emit(amount)
	_draw()
	if _live == 0:
		set_physics_process(false)
		done.emit(landed, stopped)
		get_tree().create_timer(0.6, false).timeout.connect(queue_free)


func _kill(i: int, at: Vector3) -> void:
	_alive[i] = false
	_live -= 1
	_splash.emit_particle(Transform3D(Basis(), at), Vector3.ZERO, Color.WHITE, Color.WHITE,
		GPUParticles3D.EMIT_FLAG_POSITION)


## Height above his feet where the step a-b meets the walker (within BODY_R of his axis, a vertical
## segment from his knees up), or -1 if it misses him.
static func _body_hit(a: Vector3, b: Vector3, foot: Vector3) -> float:
	var c := foot + Vector3(0.0, BODY_LOW, 0.0)
	var d := foot + Vector3(0.0, BODY_TOP - BODY_R, 0.0)
	var pts := Geometry3D.get_closest_points_between_segments(a, b, c, d)
	var h := pts[1].y - foot.y
	# Flat at the knees (no rounded end reaching down over the shins); rounded over the head.
	if h <= BODY_LOW + 0.01 or pts[0].distance_to(pts[1]) >= BODY_R:
		return -1.0
	return h


func _draw() -> void:
	var mm := _mm.multimesh
	var k := trail + 1
	for i in _pos.size():
		for j in k:
			var idx := i * k + j
			if not _alive[i]:
				mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
				continue
			var back := _vel[i] * (trail_dt * j)
			var s := _scale[i] * (1.0 - 0.14 * j)
			mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * s), _pos[i] - back))
			mm.set_instance_color(idx, Color(color.r, color.g, color.b, color.a * (1.0 - 0.15 * j)))
