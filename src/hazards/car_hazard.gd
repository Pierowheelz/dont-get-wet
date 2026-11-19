class_name CarHazard
extends Node3D
## A car that speeds out of a side street through the puddle at the crossing, throwing a wave of
## water at the walker just before they cross. Tilting the umbrella forward shields from it.

signal approaching
signal splashed_puddle(at: Vector3)

enum S { IDLE, DRIVING, GONE }

const TRIGGER_DIST := 8.5
const SPEED := 11.0
const START_Z := -30.0
const SPLASH_DROPS := 600
const SPLASH_Z := 0.5          # the wave's width across the street, each side of the walker's line
const SPLASH_SPREAD := 15.0    # degrees either side of its direction, along the street
const SPLASH_REACH_S := 1.4
const SPLASH_FULL := 0.5      # share of his body (DropletBurst.exposure) the wave must soak for the whole wet_car_splash
const SPLASH_PER_POINT := 25.0 # droplets that soak one body point

var level: Node
var crossing_x := 0.0
var crossing_w := 9.0
var state := S.IDLE
var _splashed := false
var _body: Node3D
var _lights: Array[SpotLight3D] = []
var _beacon: Label3D
var _t := 0.0
var burst: DropletBurst        # the last splash
var _splash_t := 0.0
var splash_dir := Vector3(-1.0, 1.0, 0.0)   # the wave leaves the puddle at about 45 degrees...
var splash_v := [5.5, 10.0]                   # ...at these speeds (m/s)


func _ready() -> void:
	position = Vector3(crossing_x + 1.7, LevelBuilder.ROAD_Y, START_Z)
	rotation.y = -PI * 0.5
	_body = _make_body()
	add_child(_body)
	for side in [-0.65, 0.65]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.92, 0.75)
		sl.light_energy = 8.0
		sl.spot_range = 30.0
		sl.spot_angle = 22.0
		sl.light_volumetric_fog_energy = 3.0
		sl.position = Vector3(2.2, 0.7, side)
		sl.rotation = Vector3(0, -PI * 0.5, 0)   # local -Z → +X (car forward)
		sl.rotation.z = -0.05
		add_child(sl)
		_lights.append(sl)
	visible = false
	# Warning beacon at the corner: flashes while a car is coming down the side street.
	_beacon = Label3D.new()
	_beacon.text = "!"
	_beacon.font_size = 220
	_beacon.pixel_size = 0.0065
	_beacon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon.modulate = Color(1.0, 0.72, 0.2)
	_beacon.outline_size = 40
	_beacon.outline_modulate = Color(0.05, 0.03, 0.0, 0.85)
	_beacon.no_depth_test = true
	_beacon.top_level = true
	_beacon.visible = false
	add_child(_beacon)
	_beacon.global_position = Vector3(crossing_x + 0.3, 2.9, 2.2)


func _make_body() -> Node3D:
	var car_path := CarHazard.pick_car(level)
	return load(car_path).instantiate() if ResourceLoader.exists(car_path) else greybox_car()


## A car model suited to the level: retro hover-cars appear with probability = neon.
static func pick_car(lvl: Node) -> String:
	var neon: float = lvl.data.get("neon", 0.0) if lvl else 0.0
	var ids: Array = ["car_retro_a", "car_retro_b", "car_retro_c"] if randf() < neon else ["car_sedan", "car_sedan_b", "car_sedan_c"]
	return "res://assets/props/%s.glb" % ids[randi() % ids.size()]


static func greybox_car() -> Node3D:
	var n := Node3D.new()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.45, 0.1, 0.08)
	paint.metallic = 0.6
	paint.roughness = 0.25
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.06, 0.08)
	glass.roughness = 0.05
	glass.metallic = 0.5
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.03, 0.03, 0.03)
	tire.roughness = 0.8
	var parts := [[Vector3(4.8, 0.7, 1.9), Vector3(0, 0.65, 0), paint], [Vector3(2.4, 0.55, 1.7), Vector3(-0.2, 1.25, 0), glass]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.material_override = p[2]
		mi.position = p[1]
		n.add_child(mi)
	for wx in [-1.5, 1.5]:
		for wz in [-0.85, 0.85]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.34
			cm.bottom_radius = 0.34
			cm.height = 0.25
			w.mesh = cm
			w.material_override = tire
			w.rotation.x = PI * 0.5
			w.position = Vector3(wx, 0.34, wz)
			n.add_child(w)
	return n


static func _droplet_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


func is_threat_for(x: float) -> bool:
	if state == S.GONE:
		return false
	if _splashed and not splash_in_air():
		return false
	var d := crossing_x - x
	return d > -0.5 and d < TRIGGER_DIST + 2.0


## The wave is still coming down on the pavement (strays after SPLASH_REACH_S are stragglers).
func splash_in_air() -> bool:
	return _splashed and _t - _splash_t < SPLASH_REACH_S


func _physics_process(delta: float) -> void:
	var player: Node3D = level.player
	match state:
		S.IDLE:
			if player.position.x > crossing_x + crossing_w:
				state = S.GONE
				set_physics_process(false)
			elif player.position.x >= crossing_x - TRIGGER_DIST:
				state = S.DRIVING
				visible = true
				approaching.emit()
		S.DRIVING:
			_t += delta
			_beacon.visible = not _splashed and fmod(_t, 0.4) < 0.26
			position.z += SPEED * delta
			if not _splashed and position.z >= 0.6:
				_splashed = true
				_splash_t = _t
				_beacon.visible = false
				_do_splash(player)
			if position.z > 40.0:
				state = S.GONE
				visible = false
				set_physics_process(false)


## The wave off the puddle: a DropletBurst, so the walker gets wet only where its droplets reach him
## (`wet_car_splash` once it has soaked SPLASH_FULL of him), and a forward-tilted canopy stops what it meets.
func _do_splash(player: Node3D) -> void:
	var at := Vector3(crossing_x + 0.9, LevelBuilder.ROAD_Y + 0.1, Tun.f("player_z"))
	splashed_puddle.emit(at)
	var starts := PackedVector3Array()
	for i in SPLASH_DROPS:
		starts.append(at + Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.1), randf_range(-SPLASH_Z, SPLASH_Z)))
	# Fanned along the street (up and down), barely across it: a wave thrown at the pavement.
	var vels := PackedVector3Array()
	var base := atan2(splash_dir.y, -splash_dir.x)
	for i in SPLASH_DROPS:
		var a := base + deg_to_rad(randf_range(-SPLASH_SPREAD, SPLASH_SPREAD))
		var v := randf_range(splash_v[0], splash_v[1])
		vels.append(Vector3(-cos(a), sin(a), randf_range(-0.06, 0.06)) * v)
	burst = DropletBurst.spawn(level, starts, vels, Tun.f("wet_car_splash"), {"full": SPLASH_FULL,
		"per_point": SPLASH_PER_POINT, "cause": &"splash", "color": Color(0.7, 0.78, 0.9, 0.55)})
	var p := player as Player
	var b := burst
	b.done.connect(func(_landed: int, _stopped: int) -> void: p.splash_done(b.given_to(p)))
