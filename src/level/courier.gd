class_name Courier
extends Node3D
## The level's `courier`: a scripted pedestrian the walker must keep in frame without being noticed.
## He waits in a doorway at `appear_x`, steps out under a yellow umbrella when the walker comes near,
## and walks ahead at PACE to the inn door at `door_x`, stopping at each of `stops` to look in a
## shop window for `dur` seconds. He never furls the umbrella, so he needs no cover.
##
## Glances: when the walker is within glance_dist() behind him, he slows (SLOW_S) and turns his head
## and shoulders back (TURN_S). If the walker's umbrella isn't tilted fully forward when the turn
## completes, `suspicion` goes up by one. Suspicion shows only in what he does:
## - every gain: he holds the look GAIN_HOLD_S longer and a low sting plays
## - 1: glances from a metre further, and checks the shop-window reflection at every stop
## - 2: walks at PACE_UNEASY and cuts his window stops short
## - 3: his free hand goes inside his coat on every glance
## - the 4th gain: he turns, aims the umbrella and fires twice (the attempt fails as `shot`)
## He fails the attempt as `made` if the walker comes within MADE_DIST of him (or passes him), and as
## `lost` once he has been off the right edge of the frame for LOST_S.

enum Phase { WAIT, STEP_OUT, WALK, WINDOW, DOOR, INSIDE, AIM }

const OUTFIT := "res://assets/characters/walker/raincoat.glb"
const STING := "res://assets/audio/glance_sting.ogg"
const UMBRELLA_YELLOW := Color(0.98, 0.78, 0.06)
const SUIT_TINT := Color(1.35, 1.02, 0.66)   # a plain brown suit over the walker's grey cloth

const PACE := 1.15
const PACE_UNEASY := 1.25
const ACCEL := 1.8
const GLANCE_DIST := 5.0
const GLANCE_DIST_UNEASY := 1.0   # added from suspicion 1
const GLANCE_PACE := 0.35         # he dawdles while he looks back
const SLOW_S := 0.4
const TURN_S := 1.6               # 2 s from the first slowing to the full look back: time to react
const LOOK_S := 0.35              # at full turn before he turns forward again
const GAIN_HOLD_S := 0.6
const BACK_S := 0.8
const GLANCE_COOLDOWN := 5.0      # from the end of one glance to the start of the next
const SEE_EXTRA := 3.0            # a completed turn catches a face up to this far past glance_dist()
const FULL_FORWARD := 0.9         # tilt, as a fraction of umbrella_max_tilt, that hides the face...
const FULL_OPEN := 0.5            # ...with the canopy at least this far open
const WINDOW_GLANCE_AT := 0.5     # s into a window stop when he checks the reflection
const WINDOW_SHORT := 0.6         # window stop length from suspicion 2
const WINDOW_HINT_DIST := 5.0
const MADE_DIST := 1.2
const LOST_S := 2.0
const SHOT_AT := 4
const STEP_OUT_GAP := 8.0         # he steps out once the walker is this close to his doorway
const RESUME_GAP := 6.5           # a checkpoint resume (or --start-x) puts him this far ahead
const FINAL_M := 6.0              # inside this of his door he stops checking and just goes in
const LANE_Z := 1.35              # a little behind the walker's line
const DOOR_Z := 0.35              # standing in the doorway
const INSIDE_Z := -1.2
const TWIST := 1.9                # rad of upper-body turn at full glance (plus the hips' HIP_TURN)
const HIP_TURN := 0.5
const WINDOW_TWIST := 0.9
const AIM_TURN_S := 0.5
const BOT_ROOM := 2.5              # the bots keep at least this much frame ahead of him
const SECOND_SHOT_S := 0.25        # glint before his second barrel, right after the first lands
const SHOT_FAIL_S := 0.5          # after the second lands, the attempt fails

var level: Node
var phase := Phase.WAIT
var speed := 0.0
var suspicion := 0
var appear_x := 20.0
var door_x := 400.0
var stops: Array = []          # [x, dur] ascending
var _next_stop := 0
var _stop_t := 0.0
var _stop_len := 0.0
var _glance_t := -1.0          # s since the current glance began, -1 when not glancing
var _glance_hold := LOOK_S
var _glance_window := false
var _glance_checked := false
var _cooldown := 0.0
var _off_t := 0.0
var _phase_t := 0.0
var _open := 0.0
var _hand := 0.0
var _yaw := 0.0                # root yaw: 0 faces up the street (+X)
var _aim_fired := false
var _shots_landed := 0
var _pace_override := -1.0     # --courier-pace=M (testing)
var _resume_gap := RESUME_GAP  # --courier-gap=M (testing)
var _aim_at := -1.0            # --courier-aim=S: he is made at S s on the level clock (testing)

var _model: Node3D
var _umbrella: Umbrella
var _grip: Node3D
var _twist: CourierTwist
var _sting: AudioStreamPlayer


func _ready() -> void:
	var spec: Dictionary = level.data["courier"]
	appear_x = float(spec.get("appear_x", 20.0))
	door_x = float(spec.get("door_x", level.end_x))
	for s in spec.get("stops", []):
		stops.append([float(s["x"]), float(s.get("dur", 3.0))])
	stops.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--courier-suspicion="):
			suspicion = clampi(int(a.substr(20)), 0, SHOT_AT - 1)
		if a.begins_with("--courier-pace="):
			_pace_override = float(a.substr(15))
		if a.begins_with("--courier-gap="):
			_resume_gap = float(a.substr(14))
		if a.begins_with("--courier-aim="):
			_aim_at = float(a.substr(14))
	_build_model()
	_build_fx()
	var px: float = level.player.position.x
	if level.resumed:
		suspicion = int(Game.checkpoint.get("courier", suspicion))
	if px > appear_x - STEP_OUT_GAP:
		# Resumed (or started) past his doorway: he is already on his way, just ahead.
		position = Vector3(px + _resume_gap, level.ground_y(px + _resume_gap), LANE_Z)
		phase = Phase.WALK
		speed = _pace()
		_open = 1.0
		_cooldown = GLANCE_COOLDOWN
	else:
		position = Vector3(appear_x, level.ground_y(appear_x), DOOR_Z)
		_yaw = -PI * 0.5   # facing the street from his doorway
	while _next_stop < stops.size() and stops[_next_stop][0] <= position.x:
		_next_stop += 1
	_pose(0.0)


func _build_model() -> void:
	_model = (load(Player.CHARACTER_SCENE) as PackedScene).instantiate()
	_model.set("umbrella_left", true)   # the free right hand is on the camera side
	add_child(_model)
	var skel := _model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var outfit := (load(OUTFIT) as PackedScene).instantiate()
	var hat := outfit.find_child("fedora", true, false) as MeshInstance3D
	hat.owner = null
	hat.reparent(skel, false)
	outfit.free()
	for m in skel.find_children("*", "MeshInstance3D", true, false):
		if String(m.name).to_lower().contains("elegantsuit"):
			var mi := m as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat is StandardMaterial3D:
					var d := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					d.albedo_color = SUIT_TINT
					mi.set_surface_override_material(s, d)
	_twist = CourierTwist.new()
	_twist.name = "CourierTwist"
	skel.add_child(_twist)   # after the walker's PoseModifier, so it turns the finished pose
	_twist.setup(skel, skel.get_node("PoseModifier"))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.95, 0.85)
	fill.light_energy = 1.3
	fill.omni_range = 3.2
	fill.omni_attenuation = 1.4
	fill.position = Vector3(0.3, 1.4, 1.1)
	fill.light_specular = 0.2
	add_child(fill)
	_grip = _model.call("get_grip", &"right")
	_umbrella = Umbrella.new()
	_umbrella.canopy_color = UMBRELLA_YELLOW
	_grip.add_child(_umbrella)
	_umbrella._body.collision_layer = 0   # scenery: it shelters nobody else
	# The only yellow umbrella in the city: a touch of glow so it reads in the dark.
	_umbrella._canopy_mat.emission_enabled = true
	_umbrella._canopy_mat.emission = UMBRELLA_YELLOW
	_umbrella._canopy_mat.emission_energy_multiplier = 0.35


func _build_fx() -> void:
	_sting = AudioStreamPlayer.new()
	_sting.bus = &"SFX"
	_sting.volume_db = -4.0
	if ResourceLoader.exists(STING):
		_sting.stream = load(STING)
	add_child(_sting)


# --- public -----------------------------------------------------------------------------------

## How close behind him the walker can come before he glances back.
func glance_dist() -> float:
	return GLANCE_DIST + (GLANCE_DIST_UNEASY if suspicion >= 1 else 0.0)


## True from the moment a glance starts until he has turned forward again.
func glancing() -> bool:
	return _glance_t >= 0.0


## He is out on the street, where the walker has to keep him in frame and out of reach.
func tailing() -> bool:
	return phase == Phase.STEP_OUT or phase == Phase.WALK or phase == Phase.WINDOW


## Whether the walker's face is hidden: the canopy open and tilted fully forward, the same full
## forward tilt that blocks a car's splash.
static func face_hidden(p: Player) -> bool:
	return p.open >= FULL_OPEN and p.tilt >= FULL_FORWARD * Tun.f("umbrella_max_tilt")


## The autopilots tail him: hold stop to stay glance_dist() + 1 m back where the frame allows it
## (BOT_ROOM ahead of him), never let him walk out of frame (hurry if he nears its right edge),
## never wait under a gutter, and tilt the open umbrella fully forward while he glances. Takes and returns the bot's [umbrella, hurry, tilt, stop].
func steer_bot(p: Player, ap: Array) -> Array:
	if not tailing() or p.state == Player.State.DEFEATED:
		return ap
	var out := ap.duplicate()
	var gap := position.x - p.position.x
	var room := frame_right() - (position.x + 0.3)
	# Out of his glance if the frame allows; past that, hang back as far as it does and hide the face.
	var keep := minf(glance_dist() + 1.2, gap + room - BOT_ROOM)
	if position.x >= door_x - FINAL_M:
		keep = 0.0   # he's going in; follow him to the door
	var in_stream: bool = level.gutters.any(func(g: float) -> bool: return absf(p.position.x - g) < 0.9)
	if room < 1.0:
		out[3] = false
		out[1] = 0.5
		p._ap_resting = false
	elif in_stream:
		out[3] = false   # never wait under a gutter's stream: walk on through it, umbrella up
	elif gap < keep or (p.state == Player.State.STOPPED and gap < keep + 0.6 and room > BOT_ROOM):
		out[3] = true
		out[1] = 0.0
	elif gap < keep + 3.0:
		out[1] = 0.0
	if glancing():
		out[0] = 1.0
		out[2] = 1.0
	return out


## World x of the right edge of the frame on his lane. The frame is taken as at least 16:9 (a
## headless run's window is square), so on a narrower screen he can leave the picture a little early.
func frame_right() -> float:
	var cam: Camera3D = level.camera
	var vp := get_viewport().get_visible_rect().size
	var aspect := maxf(vp.x / maxf(vp.y, 1.0), 16.0 / 9.0)
	var depth := cam.global_position.z - position.z
	return cam.global_position.x + depth * tan(deg_to_rad(cam.fov) * 0.5) * aspect


# --- loop -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var p: Player = level.player
	if p == null or level.camera == null:
		return
	_phase_t += delta
	var live := p.state == Player.State.WALK or p.state == Player.State.STOPPED
	match phase:
		Phase.WAIT:
			if live and p.position.x >= appear_x - STEP_OUT_GAP:
				_set_phase(Phase.STEP_OUT)
				level.hint_once("courier", "That's him. Keep him in sight, and keep your distance.", 4.5)
		Phase.STEP_OUT:
			_step_out(delta)
		Phase.WALK:
			_walk(delta, p, live)
		Phase.WINDOW:
			_window(delta, p, live)
		Phase.DOOR:
			_door(delta, p)
		Phase.AIM:
			_aim(delta, p)
	if _aim_at >= 0.0 and tailing() and level.elapsed >= _aim_at:
		_aim_at = -1.0
		suspicion = SHOT_AT - 1
		_gain()
	if live and tailing():
		_check_fails(delta, p)
	_pose(delta)


func _set_phase(ph: Phase) -> void:
	phase = ph
	_phase_t = 0.0


func _pace() -> float:
	if _pace_override > 0.0:
		return _pace_override
	return PACE_UNEASY if suspicion >= 2 else PACE


## Out of the doorway and onto his lane, opening the umbrella as he goes.
func _step_out(delta: float) -> void:
	_open = move_toward(_open, 1.0, delta / Game.umbrella_open_time(0))
	speed = move_toward(speed, _pace(), ACCEL * delta)
	var vz := minf(1.0, (LANE_Z - position.z) / maxf(delta, 1e-4)) if position.z < LANE_Z else 0.0
	var vx := maxf(speed, 0.25)
	position.x += vx * delta
	position.z = minf(position.z + vz * delta, LANE_Z)
	_yaw = move_toward(_yaw, -atan2(vz, vx), 3.0 * delta)
	if absf(_yaw) < 0.01 and position.z >= LANE_Z - 0.001:
		_yaw = 0.0
		_set_phase(Phase.WALK)
		_cooldown = 2.0


func _walk(delta: float, p: Player, live: bool) -> void:
	var target := _pace()
	if glancing():
		target = GLANCE_PACE
	elif position.x >= door_x - FINAL_M:
		# Going in: keep ahead of the walker if he's right behind.
		var gap := position.x - p.position.x
		if gap < 2.5:
			target = maxf(target, p.speed + 0.4)
	speed = move_toward(speed, target, ACCEL * delta)
	position.x += speed * delta
	position.y = level.ground_y(position.x)
	_cooldown -= delta
	if glancing():
		_glance_step(delta, p)
	elif live and _cooldown <= 0.0 and position.x < door_x - FINAL_M and position.x - p.position.x <= glance_dist():
		_start_glance(false)
	if not glancing():
		if position.x >= door_x:
			_set_phase(Phase.DOOR)
		elif _next_stop < stops.size() and position.x >= stops[_next_stop][0]:
			_stop_len = stops[_next_stop][1] * (WINDOW_SHORT if suspicion >= 2 else 1.0)
			_next_stop += 1
			_stop_t = 0.0
			_set_phase(Phase.WINDOW)


## A shop window: he faces it for the stop's length. From suspicion 1 he checks the reflection.
func _window(delta: float, p: Player, live: bool) -> void:
	speed = move_toward(speed, 0.0, 3.0 * delta)
	position.x += speed * delta
	_stop_t += delta
	var gap := position.x - p.position.x
	if live and gap <= WINDOW_HINT_DIST:
		level.hint_once("courier_window", "Hang back ({stop}). Let him get ahead.", 4.0)
	if glancing():
		_glance_step(delta, p)
	elif suspicion >= 1 and live and _stop_t >= WINDOW_GLANCE_AT and not _glance_checked:
		_start_glance(true)
	var leaving := _stop_t >= _stop_len and not glancing()
	_yaw = move_toward(_yaw, 0.0 if leaving else PI * 0.5, 3.5 * delta)
	if leaving and absf(_yaw) < 0.01:
		_glance_checked = false
		_cooldown = maxf(_cooldown, 1.5)
		_set_phase(Phase.WALK)


func _start_glance(window: bool) -> void:
	_glance_t = 0.0
	_glance_hold = LOOK_S
	_glance_window = window
	_glance_checked = false
	level.hint_once("courier_glance", "He's checking behind him. Hide your face ({tilt_forward}).", 4.0)


## Time through a glance: slow, turn, (look), turn back. The look is judged as the turn completes.
func _glance_step(delta: float, p: Player) -> void:
	_glance_t += delta
	var turned := SLOW_S + TURN_S
	if not _glance_checked and _glance_t >= turned:
		_glance_checked = true
		var seen := position.x - p.position.x <= glance_dist() + SEE_EXTRA
		var live := p.state == Player.State.WALK or p.state == Player.State.STOPPED
		if live and seen and not face_hidden(p):
			_gain()
	if _glance_t >= turned + _glance_hold + BACK_S:
		_glance_t = -1.0
		_cooldown = GLANCE_COOLDOWN


## How far through its turn the current glance is, 0 (facing ahead) to 1 (looking back).
func glance_turn() -> float:
	if _glance_t < 0.0:
		return 0.0
	var t := _glance_t - SLOW_S
	if t < TURN_S:
		return smoothstep(0.0, TURN_S, t)
	t -= TURN_S + _glance_hold
	return 1.0 - smoothstep(0.0, BACK_S, t)


func _gain() -> void:
	suspicion += 1
	_glance_hold = LOOK_S + GAIN_HOLD_S
	if _sting.stream:
		_sting.play()
	if suspicion >= SHOT_AT:
		_glance_t = -1.0
		_set_phase(Phase.AIM)


func _check_fails(delta: float, p: Player) -> void:
	if position.x >= door_x - FINAL_M:
		_off_t = 0.0
		return
	if position.x - p.position.x < MADE_DIST:
		_glance_t = SLOW_S + TURN_S * 0.5   # he turns and looks straight at him
		_glance_hold = 99.0
		_glance_checked = true
		p.fail(&"made")
		return
	_off_t = _off_t + delta if position.x - 0.3 > frame_right() else 0.0
	if _off_t >= LOST_S:
		p.fail(&"lost")


## In at the inn door: turn to it, furl the umbrella, walk in, gone.
func _door(delta: float, p: Player) -> void:
	speed = move_toward(speed, 0.0, 4.0 * delta)
	position.x += speed * delta
	_yaw = move_toward(_yaw, PI * 0.5, 3.0 * delta)
	var hurry := 1.6 if p.position.x > door_x - 2.0 else 1.0
	_open = move_toward(_open, 0.0, hurry * delta / Game.umbrella_open_time(0))
	if _yaw > 1.2:
		position.z -= 1.3 * hurry * delta
	if position.z < INSIDE_Z:
		_set_phase(Phase.INSIDE)
		visible = false


## The 4th gain: he turns right round, points the umbrella at the walker and fires.
func _aim(delta: float, p: Player) -> void:
	speed = move_toward(speed, 0.0, 3.0 * delta)
	position.x += speed * delta
	# Round to face the walker, wherever he is, by the shorter way: from a shop window that is on
	# round with his back to the camera, from walking it is past the camera so his face shows.
	var face := 0.0
	if p.position.x < position.x:
		face = PI if _yaw > 0.0 else -PI
	_yaw = move_toward(_yaw, face, PI / AIM_TURN_S * delta)
	_hand = move_toward(_hand, 0.0, 3.0 * delta)
	if _phase_t >= AIM_TURN_S and not _aim_fired:
		_aim_fired = true
		_shoot(p, WaterJet.GLINT_S)


## Both barrels, each soaking like a car's splash whatever the canopy does: he's been made, so the
## attempt fails as SHOT once the second has landed.
func _shoot(p: Player, glint: float) -> void:
	var jet := WaterJet.fire(level, _muzzle, Tun.f("wet_car_splash"), glint)
	jet.always_hits = true
	jet.resolved.connect(func(_blocked: bool) -> void:
		_shots_landed += 1
		if _shots_landed == 1:
			_shoot(p, SECOND_SHOT_S)
		else:
			get_tree().create_timer(SHOT_FAIL_S, false).timeout.connect(func() -> void:
				if is_instance_valid(p):
					p.fail(&"shot")))


func _muzzle() -> Transform3D:
	var t := _umbrella.global_transform
	return Transform3D(t.basis, t * Vector3(0.0, Umbrella.SHAFT_LEN + 0.09, 0.0))


# --- the look ---------------------------------------------------------------------------------

func _pose(delta: float) -> void:
	var g := glance_turn()
	var hand_target := g if suspicion >= 3 and phase != Phase.AIM else 0.0
	# In fast, out slowly: the hand stays in his coat a moment after he faces front again.
	_hand = move_toward(_hand, hand_target, (2.5 if hand_target > _hand else 0.8) * delta) if delta > 0.0 else hand_target
	var root := _yaw
	var twist := 0.0
	if _glance_window:
		twist = WINDOW_TWIST * g       # facing the glass: over his left shoulder, toward the walker
	else:
		root += -HIP_TURN * g          # turning on the camera side, so his face shows
		twist = -TWIST * g
	rotation.y = root
	_twist.twist = twist
	_twist.hand = _hand
	var walking := speed if phase != Phase.DOOR else maxf(speed, 1.3 if absf(_yaw) > 1.2 else 0.0)
	_model.call("set_motion", walking, 0.0)
	_model.call("set_stopped", false)
	var raise := Umbrella.arm_raise(_open)
	var tilt := 0.0
	if phase == Phase.AIM:
		tilt = WaterJet.AIM_TILT * smoothstep(0.0, AIM_TURN_S, _phase_t)
	_model.call("set_umbrella_pose", raise, tilt, 0.0)
	_model.call("set_umbrella_open", _open)
	# Furled, it hangs from the fist like a cane, tip down and a little ahead (as the follower's).
	var furled := _grip.global_basis.orthonormalized().inverse() * global_basis.orthonormalized() * Basis(Vector3(0, 0, 1), PI + 0.18)
	_umbrella.basis = Basis(furled.get_rotation_quaternion().slerp(Quaternion.IDENTITY, raise))
	_umbrella.set_state(_open, Game.umbrella_radius(0), 0.0)


## Runs after the walker's pose modifier: turns his chest, neck and head about the vertical (a
## glance back), and reaches the free right hand in under the left lapel (`hand`).
class CourierTwist extends SkeletonModifier3D:
	var twist := 0.0
	var hand := 0.0
	var _pose_mod: Node
	var _b := {}
	const SHARE := {"UpperChest": 0.22, "Neck": 0.3, "Head": 0.48}
	static var ELBOW_POLE := Vector3(0.1, -0.25, 1.0)   # elbow out to his right, clear of the umbrella arm

	func setup(skel: Skeleton3D, pose_mod: Node) -> void:
		_pose_mod = pose_mod
		for n in ["UpperChest", "Neck", "Head", "RightHand"]:
			_b[n] = skel.find_bone(n)

	func _process_modification_with_delta(_delta: float) -> void:
		var skel := get_skeleton()
		if skel == null or _b.is_empty():
			return
		var char_from_skel: Transform3D = _pose_mod.get("char_from_skel")
		var skel_from_char := char_from_skel.affine_inverse()
		var up := (skel_from_char.basis * Vector3.UP).normalized()
		if absf(twist) > 1e-4:
			for n in SHARE:
				_rot_global(skel, _b[n], up, twist * SHARE[n])
		if hand > 0.001:
			_reach_lapel(skel, char_from_skel, skel_from_char)

	## Fingers in under the left lapel: the wrist at the right of his chest, the hand pointing up
	## and across to the left breast pocket.
	func _reach_lapel(skel: Skeleton3D, char_from_skel: Transform3D, skel_from_char: Transform3D) -> void:
		var neck := char_from_skel * skel.get_bone_global_pose(_b["Neck"]).origin
		var tips := neck + Vector3(0.04, -0.22, -0.12)
		var fingers := Vector3(-0.25, 0.3, -0.92).normalized()
		var wrist := tips - fingers * 0.17
		var anim := skel.get_bone_global_pose(_b["RightHand"])
		var f_s := (skel_from_char.basis * fingers).normalized()
		var b := Basis(_arc(anim.basis.orthonormalized().y, f_s)) * anim.basis.orthonormalized()
		var target := Transform3D(b, skel_from_char * wrist)
		var w := smoothstep(0.0, 1.0, hand)
		_pose_mod.call("_ik_arm", skel, skel_from_char, "Right", target, ELBOW_POLE, w)

	func _rot_global(skel: Skeleton3D, i: int, axis_s: Vector3, ang: float) -> void:
		var p := skel.get_bone_parent(i)
		var pb := skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
		var la := (pb.inverse() * axis_s).normalized()
		skel.set_bone_pose_rotation(i, (Quaternion(la, ang) * skel.get_bone_pose_rotation(i)).normalized())

	static func _arc(from: Vector3, to: Vector3) -> Quaternion:
		if from.cross(to).length_squared() < 1e-10:
			return Quaternion.IDENTITY if from.dot(to) > 0.0 else Quaternion(Vector3.RIGHT, PI)
		return Quaternion(from, to)
