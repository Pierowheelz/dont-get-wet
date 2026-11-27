extends Node3D
## The level's `runners`: one of their men, on the walker's own model and suit, who comes up from
## behind at a sprint, fires one quick shot as he goes by and runs on out of shot. One at a time (a
## later one waits until the last has gone). When the walker passes an entry's x:
##   WARN   running footsteps panned left, WARN_S of them, while he is still out of shot: the only warning.
##   RUN    he sprints in from the left edge of the frame at `runner_speed` (about 1.6 times the
##          walker's run) on the verge's road side (LANE_Z), the furled umbrella carried at his hip
##          like a rifle. Once he is FIRE_AHEAD past the walker, or will be by the time the glint ends,
##          he shoulders it (RAISE_S), aims it back over his shoulder and fires one telegraphed jet
##          (WaterJet, a GLINT_S glint) back at the walker: it lands `hit` in full (default
##          `wet_runner_hit`) through Player.soak(&"shot"), so one that soaks him fails as SHOT.
##   AWAY   he runs on out of the right of the frame and is gone.
## He is an NpcBody: the walker's shots can soak him (two clean hits; his umbrella is furled, so
## nothing is in the way), and then he gives up as the walker does and the run is over. A jet already
## in the air flies on. The first runner each attempt shows a hint as he comes, unless his entry has
## its own `hint`. A checkpoint resume skips every runner whose x is behind it.

enum Phase { OFF, WARN, RUN, AWAY }

const LANE_Z := 2.35          # between the walker's line and the lane edge, so he passes in full view
const WARN_S := 0.8           # footsteps before he enters the frame
const ENTER_MARGIN := 0.6     # how far outside the frame he is when the warning ends
const OUT_MARGIN := 1.5       # past the right edge of the frame, he is gone
const FIRE_AHEAD := 2.5       # metres past the walker he is when the shot leaves (his muzzle 1.5 m)
const RAISE_S := 0.25         # to bring the furled umbrella up to his shoulder
const GLINT_S := 0.3
const STEP_M := 1.45          # a sprinter's stride: one footfall per this many metres

var level: Node
var phase := Phase.OFF
var speed := 0.0
var index := -1               # which entry of `runners` is (or was last) on
var jet: WaterJet             # his shot, glinting or in the air
var man: NpcBody
var _queue: Array = []        # {x, hit (-1: wet_runner_hit), hint (null: built in)}, ascending x
var _next := 0
var _t := 0.0
var _raise_t := -1.0          # s since he began to shoulder the umbrella (-1: not yet)
var _jet_x := 0.0             # where his shot left from
var _aim := 0.0
var _steps: AudioStreamPlayer3D
var _step_phase := 0.0


func _ready() -> void:
	for r in level.data.get("runners", []):
		_queue.append({"x": float(r["x"]), "hit": float(r.get("hit", -1.0)), "hint": r.get("hint", null)})
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["x"] < b["x"])
	while _next < _queue.size() and _queue[_next]["x"] <= level.player.position.x:
		_next += 1
	_new_man()
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = &"SFX"
	_steps.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_steps.panning_strength = 2.0
	_steps.volume_db = -6.0
	_steps.position.y = 0.2
	add_child(_steps)
	visible = false
	position = Vector3(-100.0, 0.0, LANE_Z)


func _new_man() -> void:
	man = NpcBody.new()
	man.name = "Runner"
	man.level = level
	add_child(man)
	man.soaked.connect(_on_soaked)
	man.umbrella.set_state(0.0, Game.umbrella_radius(0), 0.0)


## Soaked: he has left on his own (NpcBody) and this run is over. A shot already in the air flies on.
func _on_soaked() -> void:
	if jet and is_instance_valid(jet) and jet.phase == WaterJet.Phase.GLINT:
		jet.queue_free()
		jet = null
	_end()
	_new_man()


func _end() -> void:
	phase = Phase.OFF
	visible = false
	speed = 0.0


## Where the next one starts (INF when none is left).
func next_x() -> float:
	return _queue[_next]["x"] if _next < _queue.size() else INF


## He is on: from the first footstep until he has gone.
func on() -> bool:
	return phase != Phase.OFF


## From his first footstep until his shot has landed: what a player can hear and see coming (the
## bots open up and stop resting on this, never on his trigger x).
func threat() -> bool:
	return phase == Phase.WARN or phase == Phase.RUN or incoming()


## His jet is glinting or in the air.
func incoming() -> bool:
	return jet != null and is_instance_valid(jet) and jet.phase != WaterJet.Phase.SPENT


## His shot is glinting or in the air: the moment to tilt toward him (side()). Tilted over sooner,
## the canopy only lets the rain in (a sharp eye can go as he shoulders the umbrella, RAISE_S before).
func brace() -> bool:
	return incoming()


## +1 when his shot (or he himself, before he fires) is ahead of the walker, -1 behind: the way to
## tilt the canopy to put it between them.
func side() -> float:
	var from := _jet_x if incoming() else position.x
	return 1.0 if from > level.player.position.x else -1.0


func _process(delta: float) -> void:
	var p: Player = level.player
	if p == null or level.camera == null:
		return
	_t += delta
	var playing := p.state == Player.State.WALK or p.state == Player.State.STOPPED
	if phase == Phase.OFF:
		if playing and _next < _queue.size() and p.position.x >= _queue[_next]["x"]:
			_begin(_next)
			_next += 1
		return
	speed = Tun.f("runner_speed")
	match phase:
		Phase.WARN:
			if _t >= WARN_S:
				_set_phase(Phase.RUN)
		Phase.RUN:
			var ahead := position.x - p.position.x
			var rel := maxf(speed - p.speed, 0.5)
			if _raise_t < 0.0 and playing and ahead + rel * (RAISE_S + GLINT_S) >= FIRE_AHEAD:
				_raise_t = 0.0
			if _raise_t >= 0.0:
				_raise_t += delta
				if _raise_t >= RAISE_S and jet == null:
					if playing:
						jet = WaterJet.fire(level, _muzzle, float(_queue[index]["hit"]) if _queue[index]["hit"] >= 0.0
							else Tun.f("wet_runner_hit"), GLINT_S)
						jet.shooter = man
						_jet_x = position.x
					_set_phase(Phase.AWAY)
		Phase.AWAY:
			if position.x > _frame_right() + OUT_MARGIN and not (jet and is_instance_valid(jet) and jet.phase == WaterJet.Phase.GLINT):
				_end()
	position.x += speed * delta
	position.y = level.ground_y(position.x)
	_pose(delta)
	_footsteps(delta)


func _begin(i: int) -> void:
	index = i
	jet = null
	_raise_t = -1.0
	_aim = 0.0
	_step_phase = 1.0     # the first footfall is the first anyone knows of him
	_set_phase(Phase.WARN)
	var p: Player = level.player
	speed = Tun.f("runner_speed")
	position = Vector3(_frame_left() - ENTER_MARGIN - maxf(speed - p.speed, 0.5) * WARN_S, level.ground_y(p.position.x), LANE_Z)
	man.position = Vector3.ZERO
	man.rotation = Vector3.ZERO
	visible = true
	if _queue[i]["hint"] != null:
		_hint(String(_queue[i]["hint"]), 3.5)
	elif level.has_method("hint_once"):
		level.hint_once("runner", "Running feet. Tilt toward him as he goes by ({tilt}).", 3.5)


func _set_phase(ph: Phase) -> void:
	phase = ph
	_t = 0.0


func _hint(text: String, dur: float) -> void:
	if level.hud and level.hud.has_method("hint"):
		level.hud.hint(text, dur)


func _muzzle() -> Transform3D:
	var t := man.umbrella.global_transform
	return Transform3D(t.basis, t * Vector3(0.0, Umbrella.SHAFT_LEN + 0.09, 0.0))


## At a sprint with the furled umbrella at his hip; shouldered and aimed back over his shoulder to fire,
## then down to his hip again as he runs on.
func _pose(delta: float) -> void:
	var aiming := _raise_t >= 0.0 and (phase == Phase.RUN or jet != null and is_instance_valid(jet) and jet.phase == WaterJet.Phase.GLINT)
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta / RAISE_S)
	var v: Node = man.visual
	v.call("set_motion", speed, 1.0)
	v.call("set_stopped", false)
	v.call("set_carry", 1.0 - _aim)
	v.call("set_aim", _aim)
	v.call("set_umbrella_pose", _aim, -WaterJet.AIM_TILT * _aim, 0.0)
	v.call("set_umbrella_open", 0.0)
	man.umbrella.set_state(0.0, Game.umbrella_radius(0), 0.0)


## World x of the left and right edges of the frame on his lane, the frame taken as at least 16:9
## (as Level.in_frame takes it).
func _half() -> float:
	var cam: Camera3D = level.camera
	var vp := get_viewport().get_visible_rect().size
	var aspect := maxf(vp.x / maxf(vp.y, 1.0), 16.0 / 9.0)
	return (cam.global_position.z - LANE_Z) * tan(deg_to_rad(cam.fov) * 0.5) * aspect


func _frame_left() -> float:
	return level.camera.global_position.x - _half()


func _frame_right() -> float:
	return level.camera.global_position.x + _half()


## A sprinter's footfalls, panned with him: off to the left before he's in shot.
func _footsteps(delta: float) -> void:
	_step_phase += speed * delta / STEP_M
	if _step_phase < 1.0:
		return
	_step_phase -= 1.0
	var s := load("res://assets/audio/footstep_run_%d.ogg" % randi_range(1, 4)) as AudioStream
	if s:
		_steps.stream = s
		_steps.pitch_scale = randf_range(1.1, 1.2)
		_steps.play()
