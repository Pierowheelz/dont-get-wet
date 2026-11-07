extends Node3D
## Scenery pedestrians: people sheltering in lit doorways, and the occasional passer-by walking
## the other way — mostly behind the walker (against the shopfronts), sometimes in front (along
## the curb) as a foreground occluder. They never affect gameplay.

const MANIFEST := "res://assets/characters/pedestrians/peds.json"
const LANE_BACK := 1.0     # clear of wall props (vending machines, benches, crates ≤ ~0.8 m)
const LANE_FRONT := 2.45   # clear of curb props (lamps, meters, hydrants at z ≈ 3.2)

var level: Node
var _walkers: Array = []
var _standers: Array = []
var _active: Array = []        # [node, speed]
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
		for f in level.data.get("features", []):
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


func _process(delta: float) -> void:
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
		if absf(n.position.x - cam_x) > 26.0:
			n.queue_free()
			_active.erase(a)


func _spawn_walker() -> void:
	var p: Player = level.player
	if p == null or p.state != Player.State.WALK:
		return
	var n: Node3D = _walkers[_rng.randi() % _walkers.size()].instantiate()
	var speed: float = n.get("suggested_speed") if n.get("suggested_speed") != null else 1.2
	var oncoming := _rng.randf() < 0.75
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
	_active.append([n, dir * speed])
