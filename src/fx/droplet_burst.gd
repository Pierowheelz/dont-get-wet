class_name DropletBurst
extends Node3D
## A burst of water droplets flown one by one, so what wets a body is exactly what the player sees
## reach it. The burst flies at every WetBody of the level but its `shooter` (a weatherproof body
## only takes `cause` &"shot"). Each droplet falls under gravity; near a body every step is checked
## against lot cover and that body's open canopy (it stops there) and against the body from the
## knees up (a capsule). A droplet on a body wets the body sample nearest it (WetBody.SAMPLES, the
## same weighted points rain is measured on); a sample is soaked once `per_point` droplets reach it.
## The burst's exposure of a body is the weighted share of its samples soaked, as rain's is, and it
## wets that body `amount` (WetBody.soak with `cause`) once that share reaches `full`. Droplets that
## miss fall to the street; with a `reach`, droplets further than that from where they started are
## spent: they wet nobody and drop out of the air. A car's splash and a fired water shot are bursts.
##   var b := DropletBurst.spawn(level, starts, velocities, amount, {"cause": &"shot", "shooter": me})
##   b.done.connect(func(landed: int, stopped: int) -> void: b.given_to(body) ...)

signal done(landed: int, stopped: int)

const GRAVITY := 9.8
const BODY_R := 0.2           # the walker as a capsule round his line, from his knees (no umbrella can
const BODY_LOW := 0.55        # cover his shins, so droplets there don't count)...
const BODY_TOP := 1.75        # ...to the top of his head
const NEAR := 1.6             # within this of him (x and z) a droplet is checked each step
const LIFE := 2.5
const SPENT_KEEP := 0.2       # share of its speed along the street a spent droplet keeps

var level: Node
var amount := 1.0             # wetness once `full` of a body is soaked
var full := 0.6               # weighted share of body samples that counts as a full hit
var per_point := 4.0          # droplets that soak one body sample
var cause := &"splash"        # passed to WetBody.soak
var shooter: WetBody          # never wet by its own burst
var reach := 0.0              # metres along the street a droplet carries before it is spent (0: no limit)
var reach_jitter := 0.0       # each droplet's reach falls short of `reach` by up to this share
var through_umbrella := false # canopies don't stop these (a parting shot that can't be blocked)
var landed := 0               # droplets that reached a body
var stopped := 0              # droplets a body's canopy stopped
var stopped_cover := 0        # droplets an awning or other lot cover stopped
var wet_given := 0.0
var _targets: Array = []      # WetBody
var _hits := {}               # WetBody -> {soak: {sample index: droplets}, landed, stopped, given}
var size := 0.09
var trail := 0                # ghost copies behind each droplet, so a fast one reads as a streak
var trail_dt := 0.014
var color := Color(0.75, 0.85, 1.0, 0.75)
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _scale := PackedFloat32Array()
var _alive: Array[bool] = []
var _spent: Array[bool] = []
var _from := PackedVector3Array()
var _reach := PackedFloat32Array()
var _live := 0
var _t := 0.0
var _mm: MultiMeshInstance3D
var _splash: GPUParticles3D


static func spawn(p_level: Node, starts: PackedVector3Array, velocities: PackedVector3Array, p_amount: float,
		opts := {}) -> DropletBurst:
	var b := DropletBurst.new()
	b.level = p_level
	b.amount = p_amount
	for k in opts:
		b.set(k, opts[k])
	b._pos = starts.duplicate()
	b._from = starts.duplicate()
	b._vel = velocities.duplicate()
	for i in starts.size():
		b._scale.append(randf_range(0.6, 1.4))
		b._alive.append(true)
		b._spent.append(false)
	b._live = starts.size()
	if b.reach > 0.0:
		for i in starts.size():
			b._reach.append(b.reach * (1.0 - randf() * b.reach_jitter))
	b._targets = WetBody.of_level(p_level).filter(func(body: WetBody) -> bool:
		return body != b.shooter and (b.cause == &"shot" or not body.weatherproof))
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
	var space := get_world_3d().direct_space_state
	var got := {}
	var samples := {}             # this step's posed samples, per body that a droplet reached
	for i in _pos.size():
		if not _alive[i]:
			continue
		var a := _pos[i]
		var v := _vel[i]
		v.y -= GRAVITY * delta
		if reach > 0.0 and not _spent[i] and absf(a.x - _from[i].x) > _reach[i]:
			_spent[i] = true
			v.x *= SPENT_KEEP
			v.z *= SPENT_KEEP
		var b := a + v * delta
		_vel[i] = v
		if not _spent[i] and _meet(i, a, b, space, got, samples):
			continue
		if (v.y < 0.0 and b.y < level.ground_y(b.x)) or _t > LIFE:   # falling onto the street (the kerb lip doesn't catch a rising one)
			_kill(i, b if b.y >= level.ground_y(b.x) else Vector3(b.x, level.ground_y(b.x) + 0.02, b.z))
			continue
		_pos[i] = b
	for body: WetBody in got:
		var r: Dictionary = _hits[body]
		var wet := amount * minf(exposure(body) / full, 1.0)
		if wet > r["given"]:
			body.soak(wet - r["given"], cause)
			wet_given += wet - r["given"]
			r["given"] = wet
	_draw()
	if _live == 0:
		set_physics_process(false)
		done.emit(landed, stopped)
		get_tree().create_timer(0.6, false).timeout.connect(queue_free)


## Droplet i's step a-b near a body: stopped by cover or a canopy, or landing on a body. True if it
## ended there.
func _meet(i: int, a: Vector3, b: Vector3, space: PhysicsDirectSpaceState3D, got: Dictionary, samples: Dictionary) -> bool:
	var near: Array = []
	var mask := Player.COVER_MASK
	for body: WetBody in _targets:
		if not is_instance_valid(body):
			continue
		var f := body.global_position
		if absf(b.x - f.x) < NEAR and absf(b.z - f.z) < NEAR and b.y < f.y + 3.2:
			near.append(body)
			if not through_umbrella:
				mask |= body.canopy_mask()
	if near.is_empty():
		return false
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	q.hit_back_faces = true
	var h := space.intersect_ray(q)
	if not h.is_empty():
		var layer := (h["collider"] as CollisionObject3D).collision_layer
		var holder: WetBody = null
		for body: WetBody in near:
			if body.canopy_mask() & layer != 0:
				holder = body
				break
		if holder:
			stopped += 1
			_record(holder)["stopped"] += 1
		else:
			stopped_cover += 1
		_kill(i, h["position"])
		return true
	for body: WetBody in near:
		var foot := body.global_position
		if not body.wettable() or _body_hit(a, b, foot) < 0.0:
			continue
		landed += 1
		var r := _record(body)
		r["landed"] += 1
		if not samples.has(body):
			samples[body] = body.body_samples()
		_wet_nearest(r["soak"], samples[body], pts_on(a, b, foot), body.across())
		got[body] = true
		_kill(i, b)
		return true
	return false


func _record(body: WetBody) -> Dictionary:
	if not _hits.has(body):
		_hits[body] = {"soak": {}, "landed": 0, "stopped": 0, "given": 0.0}
	return _hits[body]


## Droplets that reached `body`, droplets its canopy stopped, and the wetness it took.
func landed_on(body: WetBody) -> int:
	return _hits[body]["landed"] if _hits.has(body) else 0


func stopped_by(body: WetBody) -> int:
	return _hits[body]["stopped"] if _hits.has(body) else 0


func given_to(body: WetBody) -> float:
	return _hits[body]["given"] if _hits.has(body) else 0.0


func _kill(i: int, at: Vector3) -> void:
	_alive[i] = false
	_live -= 1
	_splash.emit_particle(Transform3D(Basis(), at), Vector3.ZERO, Color.WHITE, Color.WHITE,
		GPUParticles3D.EMIT_FLAG_POSITION)


## The weighted share (0..1) of `body`'s samples this burst has soaked so far.
func exposure(body: WetBody) -> float:
	if not _hits.has(body):
		return 0.0
	var soak: Dictionary = _hits[body]["soak"]
	var total := 0.0
	var wet := 0.0
	for i in WetBody.SAMPLES.size():
		var w: float = WetBody.SAMPLES[i][1]
		total += w
		wet += w * minf(soak.get(i, 0) / per_point, 1.0)
	return wet / total


## A droplet reached a body at `at`: it wets the sample nearest it, measured in the body's side-on
## plane (left and right are the same distance, so a droplet between his shoulders wets both).
static func _wet_nearest(soak: Dictionary, samples: Array, at: Vector3, across: Vector3) -> void:
	var best := INF
	var d := []
	for s in samples:
		var off: Vector3 = at - s[0]
		off -= across * off.dot(across)
		d.append(off.length())
		best = minf(best, d[-1])
	for i in d.size():
		if d[i] <= best + 0.01:
			soak[i] = soak.get(i, 0) + 1


## Where on his line the step a-b comes nearest (the point the droplet meets him).
static func pts_on(a: Vector3, b: Vector3, foot: Vector3) -> Vector3:
	var pts := Geometry3D.get_closest_points_between_segments(a, b,
		foot + Vector3(0.0, BODY_LOW, 0.0), foot + Vector3(0.0, BODY_TOP - BODY_R, 0.0))
	return pts[0]


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
