class_name PickupCar
extends CarHazard
## The level's `pickup`: a black sedan idling nose-out in a side street, headlights off, and a man in
## a yellow slicker (RaincoatFigure) waiting dry under the canopy at the corner. While the walker
## comes up to the crossing the camera eases LOOK_AHEAD forward, so the man is in shot. When henchman
## `after` is dealt with (soaked, or the walker reaches him) the engine turns over and the headlights
## come on (the warning) as the man walks round the corner and gets in; then the car pulls out across
## the pavement through the puddle, throwing the same splash as any car (CarHazard). It waits for the
## walker to come within DRIVE_AT of the crossing, and never pulls out once he is within KERB_M of it
## or in the road: the wave would land on his heels, or the car would hit him. The man is scenery; no
## water reaches him.

enum P { PARKED, BOARDING, STARTING, DRIVING, GONE }   # STARTING: he is in, the engine running

const PARK_Z := -2.6
const STAND := Vector3(-0.7, 0.0, 0.55)   # where he waits, from the crossing's start
const DOOR := Vector3(0.45, 0.0, -1.75)   # the passenger door, on the near side of the car
const BOARD_SPEED := 1.5
const START_S := 1.3                       # engine and headlights at least this long before it moves
const DRIVE_AT := 6.0
const KERB_M := 3.5
const LOOK_FROM := 22.0                    # the camera looks ahead from this far short of the crossing
const LOOK_AHEAD := 2.5
const ACCEL := 6.0
const LIGHTS := 8.0
const BEAM_FOG := 1.0                      # the beams in the street's haze: at a crossing car's 3 they wash the black car out pink
const SEEN_M := 14.0

var after := 0                  # the henchman whose end sends him to the car
var phase := P.PARKED
var man: RaincoatFigure
var _route: Array[Vector3] = []
var _pt := 0.0                   # time in this phase
var _v := 0.0
var _engine_t := -1.0            # s since the engine turned over (-1: not yet)
var _looking := false
var _idle_lights: Array[SpotLight3D] = []


func _make_body() -> Node3D:
	var car := Node3D.new()
	car.set_script(load("res://src/level/idling_car.gd"))
	return car


func _ready() -> void:
	super._ready()
	position.z = PARK_Z
	visible = true
	for l in _lights:
		l.light_energy = 0.0
		l.light_volumetric_fog_energy = BEAM_FOG
	for l in _body.find_children("*", "SpotLight3D", true, false):
		_idle_lights.append(l)
		l.visible = false             # parked dark
	man = RaincoatFigure.new()
	man.name = "Slicker"
	man.level = level
	man.facing = -1
	man.pose = RaincoatFigure.Pose.WATCH
	man.smoking = true
	man.walk_speed = BOARD_SPEED
	man.advance = false
	man.position = Vector3(crossing_x + STAND.x, level.ground_y(crossing_x + STAND.x), STAND.z)
	level.add_child(man)
	var hm: Node = level.get("henchmen")
	if hm:
		hm.dealt_with.connect(func(i: int) -> void: if i == after: _board())
	var xs: Array = level.data.get("henchmen", []).map(func(h: Dictionary) -> float: return float(h["x"]))
	xs.sort()
	var px: float = level.player.position.x
	if px > crossing_x + crossing_w:
		_gone()
	elif after < xs.size() and px > float(xs[after]) - 1.0:
		_board.call_deferred()


func is_threat_for(x: float) -> bool:
	if phase == P.PARKED or phase == P.GONE:
		return false
	if _splashed and not splash_in_air():
		return false
	var d := crossing_x - x
	return d > -0.5 and d < TRIGGER_DIST + 2.0


## The walker is far enough short of the crossing that pulling out now throws the puddle at him.
func _clear_to_go(px: float) -> bool:
	return px >= crossing_x - DRIVE_AT and px <= crossing_x - KERB_M or px > crossing_x + crossing_w


func _board() -> void:
	if phase != P.PARKED:
		return
	phase = P.BOARDING
	_pt = 0.0
	_engine_t = 0.0
	_sound("car_pass", -14.0, 0.45)
	approaching.emit()
	var corner := Vector3(crossing_x + DOOR.x, level.ground_y(crossing_x), man.position.z)
	_route = [corner, Vector3(crossing_x + DOOR.x, LevelBuilder.ROAD_Y, DOOR.z)]
	man.facing = 1
	man.pose = RaincoatFigure.Pose.WALK
	man.smoking = false


func _gone() -> void:
	phase = P.GONE
	state = S.GONE
	visible = false
	if man:
		man.queue_free()
		man = null
	_look(false)
	set_physics_process(false)


func _look(on: bool) -> void:
	if on != _looking:
		_looking = on
		level.set("camera_bias", LOOK_AHEAD if on else 0.0)


func _physics_process(delta: float) -> void:
	var p: Player = level.player
	_pt += delta
	_look(phase <= P.BOARDING and p.position.x > crossing_x - LOOK_FROM and p.position.x < crossing_x)
	if _engine_t >= 0.0:
		_engine_t += delta
		for l in _lights:
			l.light_energy = LIGHTS * clampf(_engine_t / START_S, 0.0, 1.0)
		for l in _idle_lights:
			l.visible = true
	if man and phase == P.PARKED and p.position.x > crossing_x - SEEN_M and level.in_frame(man.position.x, man.position.z):
		level.hint_once("slicker", "Raincoat. Of course he wore a raincoat.", 4.0)
	match phase:
		P.BOARDING:
			_walk_route(delta)
		P.STARTING:
			_beacon.visible = fmod(_pt, 0.4) < 0.26
			if _engine_t >= START_S and _clear_to_go(p.position.x):
				phase = P.DRIVING
				state = S.DRIVING
				_pt = 0.0
		P.DRIVING:
			_t += delta
			_v = minf(_v + ACCEL * delta, SPEED)
			position.z += _v * delta
			_beacon.visible = not _splashed and fmod(_t, 0.4) < 0.26
			if not _splashed and position.z >= 0.6:
				_splashed = true
				_splash_t = _t
				_beacon.visible = false
				if p.position.x < crossing_x:
					_do_splash(p)
			if position.z > 40.0:
				_gone()


## He walks round the corner to the car's near side and gets in.
func _walk_route(delta: float) -> void:
	if man == null:
		return
	if _route.is_empty():
		return
	var to := _route[0]
	var d := to - man.position
	d.y = 0.0
	var step := BOARD_SPEED * delta
	if d.length() <= step:
		man.position = to
		_route.pop_front()
		if _route.is_empty():
			_get_in()
		return
	man.position += d.normalized() * step
	man.position.y = to.y
	man.rotation.y = atan2(-d.z, d.x)


func _get_in() -> void:
	man.queue_free()
	man = null
	_sound("door_open", -6.0, 0.55)
	phase = P.STARTING
	_pt = 0.0


func _sound(n: String, db: float, pitch: float) -> void:
	var au: Node = level.get("audio")
	if au and au.has_method("play"):
		au.play(n, db, pitch)
