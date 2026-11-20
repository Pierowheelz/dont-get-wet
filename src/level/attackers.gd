extends Node3D
## The level's `attackers`: men in the walker's own suit, under the same umbrella, who come up behind
## him one at a time. When the walker passes an attacker's x the warning starts: brisk footsteps panned
## left and his long shadow, thrown ahead along the pavement by a lamp behind him, for WARN_S before
## he walks into the frame. He closes to HOLD_GAP behind the walker (the camera eases back to keep him
## in shot) and fires `shots` telegraphed jets (WaterJet), one every SHOT_EVERY. While the walker is
## under a railway arch he holds his fire, but each held shot still counts. Out of water, he drops
## back off the left. Once he has closed in he walks no faster than the walker's walking pace, so
## hurrying or running leaves him behind; out of the frame for GIVE_UP_S, he gives up for good.
## Each man is an NpcBody: the walker's shots can soak him (two clean hits), and then he gives up as
## the walker does and trudges off on his own; the next man comes as if he had dropped back.
## An entry may set `gap` (how far back he holds, instead of HOLD_GAP), `hint` (shown as he comes,
## instead of the first man's two hints) and `wait`: then he is posted at that x from the start,
## standing under cover facing back down the street, and when the walker reaches his x he fires from
## where he stands (no warning: he is in plain sight) until the walker has passed him, then turns
## and follows like the others. Posted, he skips a shot whose moment comes while the walker is out
## of RANGE without spending it, and once they are spent he stays at his post.
## A checkpoint resume skips every attacker whose x is behind it.

enum Phase { OFF, WARN, FIRE, LEAVE }

const WARN_S := 2.5
const CLOSE_IN := 1.0        # m/s faster than the walker as he comes up during the warning
const LANE_Z := 1.25         # just behind the walker's line, so the jets run along it
const HOLD_GAP := 5.8        # how far behind the walker he settles to fire
const IN_FRAME := 1.3        # the camera keeps him this far inside the left edge while he's on
const ENTER_MARGIN := 0.7    # how far outside the frame he is when the warning ends
const OUT_MARGIN := 1.2
const SHOT_EVERY := 2.5
const FIRST_SHOT := 2.2      # after the warning: time to walk into the frame and close in
const RANGE := 9.0           # further back than this he can't reach, and the shot is lost
const MAX_SPEED := 2.8         # coming up behind him, before he has closed in
const BRACE_S := 0.35          # how long before a shot leaves the bots tilt back for it
const GIVE_UP_S := 1.0         # out of the frame this long after the warning, he gives up
const SOAKED_HOLD_S := 2.5     # the camera keeps a soaked man in shot this long as he gives up
const FIRST_SHOT_POSTED := 0.8  # a posted man is already in shot: his first glint comes quickly
const TURN_S := 0.9            # after the walker passes his post, before he can fire again
const POST_Z := 0.9            # a posted man stands back toward the wall, under the cover
const SHADOW_W := 2.6         # across the pavement: the lamp is off to the kerb side, so it fans out
const SHADOW_Z := 1.2
const SHADOW_LEN := [3.5, 11.0]   # the lamp shadow's length as the warning starts and ends
const SHADOW_FADE := 1.5     # it fades once he's in the frame
const LAMP_Y := 2.9

var level: Node
var phase := Phase.OFF
var speed := 0.0
var index := -1              # which entry of `attackers` is (or was last) on
var shots_left := 0
var held := 0                # shots held because the walker was under an arch
var jet: WaterJet            # the jet in the air, if any
var _queue: Array = []       # [x, shots, gap, wait (-1: comes from behind), hint, hit (-1: wet_jet_hit)] ascending
var posted := false          # the next man is standing at his `wait` post
var _jet_x := 0.0            # where the shot in the air was fired from (the next man may be posted since)
var _next := 0
var _t := 0.0                # time in this phase
var _shot_t := 0.0
var _aim := 0.0
var _fired := 0
var _closed := false         # he has reached HOLD_GAP once: from now on, walking pace at most
var _out_t := 0.0
var _shadow_a := 0.0
var _shadow_f := 0.0
var man: NpcBody             # the one on now (or next): a fresh one after each is soaked
var _shadow: MeshInstance3D
var _shadow_mat: ShaderMaterial
var _pool: SpotLight3D
var _steps: AudioStreamPlayer3D
var _step_phase := 0.0
var _stride := 0.0


func _ready() -> void:
	for a in level.data.get("attackers", []):
		_queue.append([float(a["x"]), int(a.get("shots", 5)), float(a.get("gap", HOLD_GAP)),
			float(a.get("wait", -1.0)), a.get("hint", null), float(a.get("hit", -1.0))])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# A checkpoint resume spawns the walker past some of them; those stay spent, and one who was on
	# at the checkpoint doesn't come back.
	while _next < _queue.size() and _queue[_next][0] <= level.player.position.x:
		_next += 1
	_new_man()
	_shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_shadow.mesh = q
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = load("res://src/fx/lamp_shadow.gdshader")
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	_shadow.visible = false
	add_child(_shadow)
	_pool = SpotLight3D.new()
	_pool.light_color = Color(1.0, 0.74, 0.45)
	_pool.spot_range = 16.0
	_pool.spot_angle = 46.0
	_pool.spot_attenuation = 0.45
	_pool.light_volumetric_fog_energy = 1.2
	_pool.shadow_enabled = false
	_pool.top_level = true
	_pool.light_energy = 0.0
	add_child(_pool)
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = &"SFX"
	_steps.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_steps.panning_strength = 2.0
	_steps.volume_db = -9.0
	_steps.position.y = 0.2
	add_child(_steps)
	visible = false
	position = Vector3(-100.0, 0.0, LANE_Z)


func _new_man() -> void:
	man = NpcBody.new()
	man.level = level
	add_child(man)
	man.soaked.connect(_on_soaked)


## Soaked: he has left on his own (NpcBody); the attack is over as if he had dropped back.
func _on_soaked() -> void:
	if posted and phase == Phase.OFF:
		_next += 1          # soaked at his post before he ever fired
	posted = false
	if jet and is_instance_valid(jet) and jet.phase == WaterJet.Phase.GLINT:
		jet.queue_free()
		jet = null    # a shot already in the air flies on: incoming() keeps the bots braced for it
	_set_phase(Phase.OFF)
	visible = false
	speed = 0.0
	_new_man()
	get_tree().create_timer(SOAKED_HOLD_S, false).timeout.connect(_release_camera)


## The camera held back a moment so the walker saw him give up; it comes forward unless the next is on.
func _release_camera() -> void:
	if phase == Phase.OFF:
		level.set("camera_bias", 0.0)


## A jet is glinting or in the air: the moment to tilt back.
func incoming() -> bool:
	return jet != null and is_instance_valid(jet) and jet.phase != WaterJet.Phase.SPENT


## The shot is about to leave or in the air: the moment to have the canopy tilted back (the arm
## takes about a quarter of a second to swing it).
func brace() -> bool:
	return incoming() and jet.time_to_fire() < BRACE_S


## He's on and still has water.
func armed() -> bool:
	return phase in [Phase.WARN, Phase.FIRE] and shots_left > 0


## Seconds until his next glint could start (INF when he has none left): the bots open up ahead of it.
func next_glint_in() -> float:
	if not armed():
		return INF
	if incoming():
		return 0.0
	return (WARN_S - _t + FIRST_SHOT) if phase == Phase.WARN else maxf(_shot_t, 0.0)


func _process(delta: float) -> void:
	var p: Player = level.player
	if p == null or level.camera == null:
		return
	_t += delta
	var playing := p.state == Player.State.WALK or p.state == Player.State.STOPPED
	if phase == Phase.OFF:
		_post()
		if playing and _next < _queue.size() and p.position.x >= _queue[_next][0]:
			_begin(_next)
			_next += 1
		elif posted:
			_pose(delta)
		return
	if not playing and phase != Phase.LEAVE:
		_leave()
	match phase:
		Phase.WARN:
			var target := _frame_edge() - ENTER_MARGIN - CLOSE_IN * maxf(WARN_S - _t, 0.0)
			speed = clampf((target - position.x) / maxf(delta, 0.001), 0.0, MAX_SPEED)
			if _t >= WARN_S:
				_set_phase(Phase.FIRE)
				_shot_t = FIRST_SHOT
		Phase.FIRE:
			var gap := p.position.x - position.x
			if posted and gap > 0.5 and shots_left > 0:
				_fall_in()       # the walker has gone by his post: he turns and follows
			_closed = _closed or gap <= hold_gap() + 0.3
			var cap := Tun.f("walk_speed") if _closed else MAX_SPEED
			speed = 0.0 if posted else clampf(p.speed + clampf((gap - hold_gap()) * 0.8, -0.6, 1.0), 0.0, cap)
			_out_t = _out_t + delta if position.x < _frame_edge() - OUT_MARGIN else 0.0
			if _out_t >= GIVE_UP_S:
				_leave()     # outrun: he doesn't come back
			else:
				_fire_control(delta, p)
		Phase.LEAVE:
			speed = 0.0 if posted else move_toward(speed, maxf(p.speed - 0.9, 0.0), 2.0 * delta)
			if position.x < _frame_edge() - OUT_MARGIN:
				_set_phase(Phase.OFF)
				visible = false
				speed = 0.0
				posted = false
				man.rotation.y = 0.0
	position.x += speed * delta
	position.y = level.ground_y(position.x)
	_pose(delta)
	_draw_shadow(delta)
	_footsteps(delta)


func _begin(i: int) -> void:
	index = i
	shots_left = _queue[i][1]
	held = 0
	_fired = 0
	_closed = false
	_out_t = 0.0
	visible = true
	if _queue[i][4] != null:
		_hint(String(_queue[i][4]), 3.5)
	elif i == 0:
		_hint("Behind you.", 3.0)
	if posted:
		_set_phase(Phase.FIRE)    # in plain sight already: no warning
		_shot_t = FIRST_SHOT_POSTED
		return
	_set_phase(Phase.WARN)
	position.x = _frame_edge() - ENTER_MARGIN - CLOSE_IN * WARN_S - 1.5
	position.z = LANE_Z
	speed = level.player.speed + CLOSE_IN
	level.set("camera_bias", _camera_bias())


## How far behind the walker this man settles to fire.
func hold_gap() -> float:
	return float(_queue[index][2]) if index >= 0 else HOLD_GAP


## +1 when the shot in the air (or the man on now) comes from ahead of the walker, -1 from behind:
## the way to tilt to block it.
func side() -> float:
	var from := _jet_x if incoming() else position.x
	return 1.0 if from > level.player.position.x else -1.0


## Stands the next man at his post (an entry with `wait`) once nobody else is on, facing back down
## the street with his umbrella up, until the walker reaches his x.
func _post() -> void:
	if posted or _next >= _queue.size() or float(_queue[_next][3]) < 0.0:
		return
	posted = true
	position = Vector3(float(_queue[_next][3]), level.ground_y(float(_queue[_next][3])), POST_Z)
	man.rotation.y = PI
	speed = 0.0
	visible = true


## The walker has passed his post: he turns round and comes after him like the others.
func _fall_in() -> void:
	posted = false
	man.rotation.y = 0.0
	if jet and is_instance_valid(jet) and jet.phase == WaterJet.Phase.GLINT:
		jet.queue_free()
		jet = null
	_shot_t = maxf(_shot_t, TURN_S)
	level.set("camera_bias", _camera_bias())


func _set_phase(ph: Phase) -> void:
	phase = ph
	_t = 0.0


func _leave() -> void:
	if jet and is_instance_valid(jet) and jet.phase == WaterJet.Phase.GLINT:
		jet.queue_free()
	jet = null
	_set_phase(Phase.LEAVE)
	level.set("camera_bias", 0.0)


## One shot per SHOT_EVERY; a shot whose moment comes while the walker is under an arch, or out of
## a follower's reach, is held and lost. A posted man skips one out of his reach without spending it.
func _fire_control(delta: float, p: Player) -> void:
	var sheltered := _under_arch(p.position.x)
	if jet and is_instance_valid(jet) and jet.phase == WaterJet.Phase.GLINT and sheltered:
		jet.queue_free()      # he ducked in under the arch mid-aim
		jet = null
	if incoming():
		return
	_shot_t -= delta
	if _shot_t > 0.0:
		return
	if shots_left <= 0:
		_leave()
		return
	if posted and absf(p.position.x - position.x) > RANGE:
		_shot_t = SHOT_EVERY
		return
	shots_left -= 1
	_shot_t = SHOT_EVERY
	if sheltered or absf(p.position.x - position.x) > RANGE:
		held += 1
		return
	jet = WaterJet.fire(level, _muzzle, float(_queue[index][5]))
	jet.shooter = man
	_jet_x = position.x
	_fired += 1
	if index == 0 and _fired == 1 and _queue[0][4] == null:
		_hint("Tilt back ({tilt}) to put the umbrella between you.", 4.0)


func _under_arch(x: float) -> bool:
	return level.track != null and level.track.arch_at(x)


func _muzzle() -> Transform3D:
	var t := man.umbrella.global_transform
	return Transform3D(t.basis, t * Vector3(0.0, Umbrella.SHAFT_LEN + 0.09, 0.0))


func _hint(text: String, dur: float) -> void:
	if level.hud and level.hud.has_method("hint"):
		level.hud.hint(text, dur)


## Open over him the whole time; tipped forward at the walker while a jet glints.
func _pose(delta: float) -> void:
	var aiming: bool = jet != null and is_instance_valid(jet) and jet.phase != WaterJet.Phase.SPENT
	_aim = move_toward(_aim, WaterJet.AIM_TILT if aiming else 0.0, delta * 4.0)
	var raise := lerpf(1.0, WaterJet.AIM_RAISE, _aim / WaterJet.AIM_TILT)   # brought down to chest height to fire
	man.visual.call("set_motion", speed, clampf((speed - Tun.f("walk_speed")) / (Tun.f("run_speed") - Tun.f("walk_speed")), 0.0, 1.0))
	man.visual.call("set_stopped", speed < 0.05)
	man.visual.call("set_umbrella_pose", raise, _aim, 0.0)
	man.visual.call("set_umbrella_open", 1.0)
	man.umbrella.set_state(1.0, Game.umbrella_radius(0), 0.0)


## The lamp's throw of him along the pavement: it lengthens through the warning and fades once he's in shot.
func _draw_shadow(delta: float) -> void:
	if phase == Phase.WARN:
		_shadow_a = clampf(_t / 0.6, 0.0, 1.0)
		_shadow_f = smoothstep(0.0, 1.0, _t / WARN_S)
	else:
		_shadow_a = move_toward(_shadow_a, 0.0, delta / SHADOW_FADE)
	_shadow.visible = _shadow_a > 0.01
	_pool.light_energy = 16.0 * _shadow_a
	if not _shadow.visible:
		return
	var length := lerpf(SHADOW_LEN[0], SHADOW_LEN[1], _shadow_f)
	var ground: float = level.ground_y(position.x) + 0.015
	_shadow.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(length, SHADOW_W, 1.0)),
		Vector3(position.x + 0.15 + length * 0.5, ground, SHADOW_Z))
	_shadow_mat.set_shader_parameter("alpha", _shadow_a)
	_shadow_mat.set_shader_parameter("stride", _stride)
	var lamp := Vector3(position.x - lerpf(1.0, 3.0, _shadow_f), LAMP_Y, LANE_Z + 0.3)
	_pool.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -0.42), lamp)


## Bias for Level's camera that keeps him IN_FRAME inside the left edge when he holds HOLD_GAP back.
func _camera_bias() -> float:
	var cam: Camera3D = level.camera
	var half := cam.global_position.x - _frame_edge()
	return minf(half - hold_gap() - IN_FRAME - Tun.f("camera_lead"), 0.0)


## World x of the left edge of the frame, on his lane.
func _frame_edge() -> float:
	var cam: Camera3D = level.camera
	var vp := get_viewport().get_visible_rect().size
	return cam.project_position(Vector2(0.0, vp.y * 0.6), cam.global_position.z - LANE_Z).x


## Heels a touch quicker than the walker's, panned with him, off to the left before he's in shot.
func _footsteps(delta: float) -> void:
	if speed < 0.1:
		return
	_stride += speed * delta / 0.68 * PI
	_step_phase += speed * delta / 0.68
	if _step_phase < 1.0:
		return
	_step_phase -= 1.0
	if phase == Phase.LEAVE and position.x < _frame_edge():
		return
	var s := load("res://assets/audio/footstep_run_%d.ogg" % randi_range(1, 4)) as AudioStream
	if s:
		_steps.stream = s
		_steps.pitch_scale = randf_range(1.05, 1.15)
		_steps.play()
