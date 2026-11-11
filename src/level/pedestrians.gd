extends Node3D
## Scenery pedestrians: people sheltering in lit doorways, and the occasional passer-by walking
## the other way — mostly behind the walker (against the shopfronts), sometimes in front (along
## the curb) as a foreground occluder. They never affect gameplay.

const MANIFEST := "res://assets/characters/pedestrians/peds.json"
const LANE_BACK := 0.95    # clear of wall props (vending machines, benches, crates ≤ ~0.8 m)
const LANE_FRONT := 2.45   # clear of curb props (lamps, meters, hydrants at z ≈ 3.2)

var level: Node
var _walkers: Array = []
var _standers: Array = []
var _active: Array = []        # [node, speed]
var _figures: Array = []       # [visual, umbrella]: men in the walker's own suit, standing still
var _next := 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not d is Array:
		return
	for p in d:
		if not ResourceLoader.exists(p["scene"]):
			continue
		(_walkers if p["kind"] == "walker" else _standers).append(load(p["scene"]))
	_rng.seed = hash(String(level.level_id)) + 7
	_place_figures()
	_place_standers()
	_prewarm()


## Instance every walker variant once, just off-camera, so first-spawn shader compiles happen
## during the level fade-in rather than mid-play.
func _prewarm() -> void:
	var i := 0
	for ps in _walkers:
		var n: Node3D = ps.instantiate()
		n.position = Vector3(-6.0 - i, 0.0, 0.6)
		level.world.add_child(n)
		get_tree().create_timer(1.5).timeout.connect(n.queue_free)
		i += 1


func _place_standers() -> void:
	if _standers.is_empty():
		return
	var last := -100.0
	for lot in level.data.get("lots", []):
		var x: float = lot["x"]
		if lot.get("style", "") != "shop_lit" or lot.get("cover", "none") == "none" or x - last < 28.0:
			continue
		if _rng.randf() > 0.55:
			continue
		var sx := x + float(lot["w"]) * _rng.randf_range(0.2, 0.8)
		var blocked := false
		for pr in level.data.get("props", []):
			if absf(float(pr["x"]) - sx) < 1.3:
				blocked = true
		for f in level.data.get("features", []) + level.data.get("figures", []):
			if absf(float(f["x"]) - sx) < 1.5:
				blocked = true
		if blocked:
			continue
		last = x
		var n: Node3D = _standers[_rng.randi() % _standers.size()].instantiate()
		n.position = Vector3(sx, 0.0, 0.45)
		n.rotation.y = -PI * 0.5 + _rng.randf_range(-0.5, 0.5)   # roughly facing the street
		level.world.add_child(n)
		if n.has_method("setup"):
			n.setup(_rng.randi())
		if n.has_method("set_walking"):
			n.set_walking(0.0)


## The level's `figures`: the walker's own model in a doorway, umbrella furled at his side,
## facing up the street the way the walker is going, or with `"facing": "away"` toward the building.
func _place_figures() -> void:
	if not ResourceLoader.exists(Player.CHARACTER_SCENE):
		return
	for f in level.data.get("figures", []):
		var v: Node3D = (load(Player.CHARACTER_SCENE) as PackedScene).instantiate()
		v.position = Vector3(float(f["x"]), level.ground_y(float(f["x"])), 0.5)
		if f.get("facing", "street") == "away":
			v.rotation.y = PI * 0.5   # back to the camera
		level.world.add_child(v)
		v.set_motion(0.0, 0.0)
		v.set_stopped(false)
		v.set_umbrella_pose(0.0, 0.0, 0.0)
		v.set_wetness(0.0)
		var u := Umbrella.new()
		u.top_level = true
		v.add_child(u)
		u.set_state(0.0, Game.umbrella_radius(), 0.0)
		(func() -> void: u._body.collision_layer = 0).call_deferred()   # scenery: never shelters anyone
		_figures.append([v, u])


func _process(delta: float) -> void:
	for fg: Array in _figures:
		var grip: Node3D = fg[0].get_grip(&"left")
		if grip:
			fg[1].global_transform = grip.global_transform
	if _walkers.is_empty() or level.camera == null:
		return
	_next -= delta
	if _next <= 0.0:
		_next = _rng.randf_range(14.0, 30.0)
		_spawn_walker()
	var cam_x: float = level.camera.position.x
	for a in _active.duplicate():
		var n: Node3D = a[0]
		n.position.x += a[1] * delta
		n.position.y = level.ground_y(n.position.x)
		# Step aside (toward the wall or the curb) while passing the walker so nobody clips.
		var lane: float = a[2]
		var target := lane
		if absf(n.position.x - level.player.position.x) < 2.2:
			target = 0.25 if lane < 1.6 else 3.0
		n.position.z = move_toward(n.position.z, target, 1.6 * delta)
		if absf(n.position.x - cam_x) > 26.0:
			n.queue_free()
			_active.erase(a)


func _spawn_walker() -> void:
	var p: Player = level.player
	if p == null or p.state != Player.State.WALK:
		return
	var n: Node3D = _walkers[_rng.randi() % _walkers.size()].instantiate()
	var speed: float = n.get("suggested_speed") if n.get("suggested_speed") != null else 1.2
	var oncoming := true   # never overtake the walker
	var front := _rng.randf() < 0.25
	var cam_x: float = level.camera.position.x
	var dir := -1.0 if oncoming else 1.0
	# Same-direction walkers must be faster than us and start behind; oncoming start ahead.
	if not oncoming:
		speed = maxf(speed, 1.9)
	n.position = Vector3(cam_x + (22.0 if oncoming else -22.0), 0.0, LANE_FRONT if front else LANE_BACK)
	n.rotation.y = PI if oncoming else 0.0
	level.world.add_child(n)
	if n.has_method("setup"):
		n.setup(_rng.randi())
	if n.has_method("set_walking"):
		n.set_walking(speed)
	_active.append([n, dir * speed, n.position.z])
