class_name DriveBy
extends Node3D
## The level's `drive_bys`: a black sedan that comes up the near lane of the road from behind the
## walker, splashes him as it passes, then slows ahead of him while a passenger sits up on the back
## window's sill and fires one telegraphed shot (WaterJet) back at him. When the walker passes an entry's x:
##   WARN   engine and tyre hiss from the left (the car is still out of shot), its headlights sweeping
##          the pavement ahead; the camera eases out (Level.camera_pull) so the lane is in frame.
##   PASS   its kerb-side wheels throw the road water at him (DropletBurst) from behind, then beside:
##          a canopy tilted back toward it stops what it meets.
##   AIM    once it is ahead, the passenger sits up: a 0.6 s glint, then the shot, from ahead: a
##          canopy tilted forward stops it. A shot that soaks him fails the attempt as SHOT.
##   AWAY   once the shot has landed it speeds off to the right; the camera eases back in.
## The splash and the shot are separate, each blocked its own way, so the canopy has to swing from
## back to forward between them. One car at a time; a checkpoint resume skips entries behind it.

enum Phase { OFF, WARN, PASS, AIM, AWAY }

const CAR := preload("res://src/level/idling_car.gd")
const LANE_Z := 5.4           # the near lane, as the scenery traffic uses
const START_BACK := 34.0      # how far behind the walker the car is when the warning starts
const REL_SPEED := 13.0       # m/s faster than the walker until it is level with him
const PULL := 6.0             # metres the camera eases back while it passes
const SPLASH_FROM := 7.0      # its front wheel starts throwing water this far behind him...
const SPLASH_TO := 0.0        # ...and keeps on until it is level with him (the later bursts land ahead)
const SPLASH_BURSTS := 6
const SPLASH_DROPS := 160     # per burst
const SPLASH_SHARE := 0.9     # of wet_car_splash, once SPLASH_FULL of him is soaked
const SPLASH_FULL := 0.5
const SPLASH_PER_POINT := 22.0
const WHEEL := Vector3(1.35, 0.1, -0.85)    # the kerb-side front wheel, local to the car
const SPLASH_CARRY := 0.38    # share of the car's speed past him the thrown water keeps along the street
const SPLASH_UP := Vector2(5.6, 6.8)    # m/s up: a high arc that comes down on him from behind...
const SPLASH_IN := Vector2(3.2, 4.0)    # ...m/s across toward the pavement
const MUZZLE := Vector3(-1.75, 1.3, -0.75)   # the passenger's umbrella tip as he aims back over the boot
const BRAKE := 14.0           # m/s² it sheds its speed with once past him
const AIM_LEAD := 7.5         # metres ahead of the walker the back window holds while the passenger aims
const SPLASH_LANDED := 1.1    # s into the pass by which the last of the splash on him has come down
const LEAN_AT := 1.2          # s into the pass the passenger starts to lean out (then the glint)
const LEAN_S := 0.3
const AWAY_ACCEL := 8.0
const AWAY_S := 2.2           # the camera holds out this long once it speeds away
const BACK_SEAT := Vector3(-0.75, 0.0, -0.42)
const SILL := Vector3(-0.75, 0.05, -0.75)   # where his feet are once he sits up on the back window's sill
const LEAN := 0.2             # rad he leans out toward the kerb, sitting up on the sill
const CABIN_LIGHT := 6.0      # the light on the passenger once he is up on the sill
const BRACE_BACK_S := 0.35    # the bots tilt back this long before the splash starts...
const BRACE_FIRE_S := 0.5     # ...and forward this long before the shot leaves

var level: Node
var phase := Phase.OFF
var jet: WaterJet
var splashes: Array[DropletBurst] = []
var splash_wet := 0.0         # what this car's splash put on him
var _splashes_done := 0
var _queue: Array = []        # trigger x, ascending
var _next := 0
var _t := 0.0
var _speed := 0.0
var _bursts_left := 0
var _lean := 0.0
var _car: Node3D
var _passenger: Node3D
var _gun: Umbrella
var _cabin: OmniLight3D
var _hiss: AudioStreamPlayer3D


func _ready() -> void:
	for d in level.data.get("drive_bys", []):
		_queue.append(float(d["x"]))
	_queue.sort()
	while _next < _queue.size() and _queue[_next] <= level.player.position.x:
		_next += 1
	_car = CAR.new()
	add_child(_car)
	for side in [-0.62, 0.62]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.93, 0.78)
		sl.light_energy = 14.0
		sl.spot_range = 34.0
		sl.spot_angle = 20.0
		sl.spot_attenuation = 0.6
		sl.light_volumetric_fog_energy = 3.0
		sl.position = Vector3(2.4, 0.7, side)
		# Dipped toward the kerb so the beams fall across the pavement ahead of the walker.
		sl.basis = Basis(Vector3.UP, -PI * 0.5 - 0.1) * Basis(Vector3.RIGHT, -0.06)
		_car.add_child(sl)
	# It passes between the camera and the pavement, so the flank in shot is its unlit side: a cool
	# light rides above that side for the paint's shoulder and roof to catch, and the paint is a
	# shade off black so the body has a shape.
	var flank := OmniLight3D.new()
	flank.light_color = Color(0.62, 0.72, 1.0)
	flank.light_energy = 2.4
	flank.omni_range = 6.5
	flank.omni_attenuation = 1.3
	flank.light_volumetric_fog_energy = 0.0
	flank.position = Vector3(0.2, 2.5, 2.9)
	_car.add_child(flank)
	var body := _car.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var paint := body.get_surface_override_material(0) as StandardMaterial3D
	if paint:
		paint = paint.duplicate()
		paint.albedo_color = Color(0.045, 0.05, 0.065)
		paint.roughness = 0.26
		body.set_surface_override_material(0, paint)
	_passenger = (load(Player.CHARACTER_SCENE) as PackedScene).instantiate()
	_car.add_child(_passenger)
	# The cabin's light spills out with him as he sits up, or he is a dark suit against a dark street.
	_cabin = OmniLight3D.new()
	_cabin.light_color = Color(1.0, 0.84, 0.6)
	_cabin.omni_range = 2.8
	_cabin.omni_attenuation = 1.4
	_cabin.light_volumetric_fog_energy = 0.0
	_cabin.position = SILL + Vector3(-0.7, 1.6, 1.1)
	_cabin.light_energy = 0.0
	_car.add_child(_cabin)
	_gun = Umbrella.new()
	_gun.layer = Umbrella.NPC_UMBRELLA_LAYER
	_passenger.call("get_grip", &"right").add_child(_gun)
	_hiss = AudioStreamPlayer3D.new()
	_hiss.bus = &"SFX"
	_hiss.stream = load("res://assets/audio/car_pass.ogg")
	_hiss.max_distance = 80.0
	_hiss.unit_size = 9.0
	_hiss.panning_strength = 1.6
	_hiss.pitch_scale = 0.9
	_car.add_child(_hiss)
	visible = false


## Where the next one starts (INF when none is left).
func next_x() -> float:
	return _queue[_next] if _next < _queue.size() else INF


## A car is on its way or still in shot: no resting, no refilling, keep the canopy up.
func coming() -> bool:
	return phase != Phase.OFF and phase != Phase.AWAY


## Which way the canopy should face now: -1 back toward the car's splash, +1 forward toward the
## passenger's shot, 0 when neither is due (the bots tilt this way, and only then: tilted over, the
## canopy lets the rain in).
func brace() -> float:
	match phase:
		Phase.WARN:
			return -1.0 if _to_splash() / REL_SPEED < BRACE_BACK_S else 0.0
		Phase.PASS:
			if _t < SPLASH_LANDED:
				return -1.0
			return 1.0 if LEAN_AT + LEAN_S + WaterJet.GLINT_S - _t < BRACE_FIRE_S else 0.0
		Phase.AIM:
			if jet == null or not is_instance_valid(jet) or jet.phase == WaterJet.Phase.SPENT:
				return 0.0
			return 1.0 if jet.time_to_fire() < BRACE_FIRE_S else 0.0
	return 0.0


## Metres the front wheel still has to close before it starts throwing water at him.
func _to_splash() -> float:
	return level.player.position.x - (position.x + WHEEL.x) - SPLASH_FROM


func _process(delta: float) -> void:
	var p: Player = level.player
	if p == null:
		return
	_t += delta
	var playing := p.state == Player.State.WALK or p.state == Player.State.STOPPED
	match phase:
		Phase.OFF:
			if playing and _next < _queue.size() and p.position.x >= _queue[_next]:
				_begin()
				_next += 1
			return
		Phase.WARN:
			_speed = p.speed + REL_SPEED
			if _to_splash() <= 0.0:
				_set_phase(Phase.PASS)
				_bursts_left = SPLASH_BURSTS
		Phase.PASS:
			if _bursts_left > 0:
				_speed = p.speed + REL_SPEED
				var done := float(SPLASH_BURSTS - _bursts_left) / float(SPLASH_BURSTS - 1)
				if p.position.x - (position.x + WHEEL.x) <= lerpf(SPLASH_FROM, SPLASH_TO, done):
					_splash(p)
					_bursts_left -= 1
			else:
				_speed = move_toward(_speed, _hold_speed(p, REL_SPEED), BRAKE * delta)
			_t_lean(delta, _t >= LEAN_AT)
			if _t >= LEAN_AT + LEAN_S:
				_set_phase(Phase.AIM)
				jet = WaterJet.fire(level, _muzzle)
		Phase.AIM:
			_speed = move_toward(_speed, _hold_speed(p, 4.0), BRAKE * delta)
			_t_lean(delta, true)
			if jet == null or not is_instance_valid(jet) or jet.phase == WaterJet.Phase.SPENT:
				_set_phase(Phase.AWAY)
		Phase.AWAY:
			_speed += AWAY_ACCEL * delta
			_t_lean(delta, false)
			if _t >= AWAY_S:
				level.set("camera_pull", 0.0)
				if position.x > level.camera.global_position.x + 40.0:
					_set_phase(Phase.OFF)
					visible = false
					_hiss.stop()
	position.x += _speed * delta
	_pose()


## Speed that brings the back window to AIM_LEAD ahead of him and holds it there.
func _hold_speed(p: Player, faster: float) -> float:
	var ahead := position.x + BACK_SEAT.x - p.position.x
	return p.speed + clampf((AIM_LEAD - ahead) * 2.0, -2.0, faster)


func _begin() -> void:
	var p: Player = level.player
	position = Vector3(p.position.x - START_BACK, LevelBuilder.ROAD_Y, LANE_Z)
	_speed = p.speed + REL_SPEED
	_lean = 0.0
	jet = null
	splashes.clear()
	splash_wet = 0.0
	_splashes_done = 0
	_set_phase(Phase.WARN)
	visible = true
	level.set("camera_pull", PULL)
	_hiss.play()
	if level.has_method("hint_once"):
		level.hint_once("drive_by", "Headlights. Behind.", 3.0)


func _set_phase(ph: Phase) -> void:
	phase = ph
	_t = 0.0


## One burst of road water off the kerb-side front wheel, thrown up and over at the pavement and
## carried forward by the car's speed: from behind him at first, then from beside him.
func _splash(p: Player) -> void:
	var at := global_transform * WHEEL
	var starts := PackedVector3Array()
	var vels := PackedVector3Array()
	var fwd: float = p.speed + REL_SPEED * SPLASH_CARRY
	for i in SPLASH_DROPS:
		starts.append(at + Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.1), randf_range(-0.1, 0.1)))
		vels.append(Vector3(fwd + randf_range(-1.0, 1.0), randf_range(SPLASH_UP.x, SPLASH_UP.y), -randf_range(SPLASH_IN.x, SPLASH_IN.y)))
	var amount := Tun.f("wet_car_splash") * SPLASH_SHARE / float(SPLASH_BURSTS)
	var b := DropletBurst.spawn(level, starts, vels, amount, {"full": SPLASH_FULL / float(SPLASH_BURSTS),
		"per_point": SPLASH_PER_POINT / float(SPLASH_BURSTS), "cause": &"splash", "color": Color(0.7, 0.78, 0.9, 0.55)})
	splashes.append(b)
	b.done.connect(func(_landed: int, _stopped: int) -> void:
		splash_wet += b.given_to(p)
		_splashes_done += 1
		if _splashes_done == SPLASH_BURSTS and is_instance_valid(p):
			p.splash_done(splash_wet))
	if _bursts_left == SPLASH_BURSTS:
		var au: Node = level.get("audio")
		if au and au.has_method("play"):
			au.play("car_splash", -2.0, 1.15)


## The passenger's aim: out of the back window, back down the street (WaterJet reads the shaft as +y).
func _muzzle() -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, PI * 0.5), global_transform * MUZZLE)


func _t_lean(delta: float, out: bool) -> void:
	_lean = move_toward(_lean, 1.0 if out else 0.0, delta / LEAN_S)


## The passenger sits low in the back, then sits up on the kerb-side back window's sill, his chest
## above the roof, facing back down the street with the furled umbrella levelled at the walker.
func _pose() -> void:
	var l := smoothstep(0.0, 1.0, _lean)
	_passenger.visible = l > 0.02 or phase == Phase.AIM
	_cabin.light_energy = CABIN_LIGHT * l
	_passenger.basis = Basis(Vector3.RIGHT, -LEAN * l) * Basis(Vector3.UP, PI)
	_passenger.position = (BACK_SEAT + Vector3(0.0, -0.75, 0.0)).lerp(SILL, l)
	_passenger.call("set_motion", 0.0, 0.0)
	_passenger.call("set_stopped", true)
	var aim := WaterJet.AIM_TILT * l
	_passenger.call("set_umbrella_pose", lerpf(0.0, WaterJet.AIM_RAISE, l), aim, 0.0)
	_passenger.call("set_umbrella_open", 0.0)
	_gun.set_state(0.0, Game.umbrella_radius(0), 0.0)
