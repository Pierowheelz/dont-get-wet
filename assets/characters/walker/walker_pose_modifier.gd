extends SkeletonModifier3D
## Procedural layer applied on top of the locomotion AnimationTree (runs after the mixer).
## - spine/neck slump (sad), bent-over heavy breathing (stopped / catching breath)
## - right arm: analytic two-bone IK to the umbrella-holding pose, blended by `raise`
## - left arm: slightly damped swing (carrying the closed umbrella), fists around the handles;
##   while the umbrella opens/closes it reaches in under the canopy and slides the runner up/down
##   the shaft, with the head ducked and the upper body leaning in a little
## The base locomotion is natural motion capture with the posture already normalised (neutral
## pelvis / lower spine, level head; tools/mocap/retarget.py), so this layer no longer re-poses the
## torso, legs or swinging arms - it only adds the overlays above.
## All targets are authored in the *character* frame (+X forward, +Y up, +Z = character's right).

# Driven by walker.gd every frame.
var raise := 0.0
var spread := 0.0      # umbrella open amount 0..1 (drives the left hand's runner push)
var tilt := 0.0
var droop := 0.0
var sad := 0.0
var breath := 0.0      # 0..1 weight of the "catching breath" overlay
var run := 0.0         # gait position: 0 walk .. 0.5 brisk .. 1 jog
var stride := 1.0      # leg swing amplitude kept (walker.gd shortens the cycle to match)
@export var hip_back := 0.0      # rad the pelvis is pitched back (legs counter-rotated: no)
@export var pelvis_tilt := 0.16   # rad of posterior pelvic tilt (tucks the backside under)
@export_range(0.0, 1.0) var posture_fix := 0.0   # per-frame torso straightening (0 = trust the clip)
@export_range(0.0, 1.0) var head_level := 0.5    # per-frame head stabilisation (eyes level)
@export var toe_swing_max := -0.12  # rad of toe-up allowed while the foot swings
@export var toe_target := -0.3   # planted foot pitch (rad, + = toes up)
@export var knee_unbend := 0.17     # rad of knee flexion removed (clip retarget offset)
@export var free_arm_swing := 0.55  # free-arm swing per unit thigh swing (opposite leg)
@export_range(0.0, 1.0) var carry_damp := 0.25   # left (umbrella-carrying) arm swing damping
var time := 0.0
var char_from_skel := Transform3D.IDENTITY

# Umbrella hold pose (character frame, metres). Grip = palm centre.
const HOLD_POS := Vector3(0.30, 1.46, 0.07)
const HOLD_FWD := 0.17     # hand this far in front of the neck base
const HOLD_DROP := -0.19   # and this far below it (chest/chin height)
const HOLD_FINGER_DIR := Vector3(0.35, 0.0, -1.0)  # knuckles point forward/inward across the chest
const ELBOW_POLE := Vector3(0.25, -1.0, 0.35)   # elbow down, slightly forward and out
# Left hand on the shaft while opening/closing (runner push). Heights are along the shaft above the
# right-hand grip; the hand rides up as the canopy spreads.
const RUNNER_LOW := 0.12
const RUNNER_HIGH := 0.47
const OPEN_TIP := deg_to_rad(20.0)  # opened / closed at ~70° above horizontal (20° off vertical)
const RUNNER_PUSH_FWD := 0.12    # right hand holds the umbrella this much further out meanwhile
const RUNNER_FINGER_DIR := Vector3(0.3, 0.0, 1.0)   # knuckles point across the body to the right
const ELBOW_POLE_L := Vector3(0.15, -1.0, -0.55)    # elbow down and out to the left

var grip_r_offset := Transform3D.IDENTITY  # grip frame expressed in RightHand bone space
var grip_l_offset := Transform3D.IDENTITY  # grip frame expressed in LeftHand bone space
var grip_lf_offset := Transform3D.IDENTITY # left fist closed around a shaft (like grip_r_offset)

var _b := {}
var _hang := {}          # bone name -> Quaternion relaxed hanging arm pose (idle clip, frame 0)
var _curl_axes := {}     # bone idx -> local curl axis
var _len_upper := 0.26
var _len_lower := 0.26
var _chest_rest := Vector3.ZERO
var _head_up_local := Vector3.UP
var _ok := false

const BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
const FINGERS := ["Index", "Middle", "Ring", "Little"]
const SEGMENTS := ["Proximal", "Intermediate", "Distal"]
const CURL := {"Proximal": 1.25, "Intermediate": 1.45, "Distal": 0.9}


func setup(skel: Skeleton3D, idle_anim: Animation) -> void:
	for n in BONES:
		_b[n] = skel.find_bone(n)
		if _b[n] < 0:
			push_error("walker: missing bone %s" % n)
			return
	for n in ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]:
		var tr := idle_anim.find_track(NodePath("%GeneralSkeleton:" + n), Animation.TYPE_ROTATION_3D)
		_hang[n] = idle_anim.rotation_track_interpolate(tr, 0.0) if tr >= 0 \
				else skel.get_bone_rest(_b[n]).basis.get_rotation_quaternion()
	var ua := skel.get_bone_global_rest(_b["RightUpperArm"]).origin
	var la := skel.get_bone_global_rest(_b["RightLowerArm"]).origin
	var ha := skel.get_bone_global_rest(_b["RightHand"]).origin
	_len_upper = ua.distance_to(la)
	_len_lower = la.distance_to(ha)
	_chest_rest = skel.get_bone_global_rest(_b["UpperChest"]).origin
	# The head bone's local axis that points world-up in the rest pose.
	var hr := skel.get_bone_global_rest(_b["Head"]).basis.orthonormalized()
	_head_up_local = (hr.inverse() * Vector3.UP).normalized()
	# Profile rest is a T-pose with palms facing down (-Y).
	var palm_n := Vector3.DOWN
	for side in ["Left", "Right"]:
		for f in FINGERS:
			for s in SEGMENTS:
				_add_curl_axis(skel, side + f + s, palm_n)
		for s in ["Proximal", "Distal"]:
			_add_curl_axis(skel, side + "Thumb" + s, palm_n)
	grip_r_offset = _make_grip(skel, "Right", true)
	grip_l_offset = _make_grip(skel, "Left", false)
	grip_lf_offset = _make_grip(skel, "Left", true)
	# Left: aim the grip so the closed umbrella hangs straight down (slightly forward) when the arm
	# is in its relaxed hanging pose, instead of following the curled finger direction.
	var hang_hand := _hang_global(skel, idle_anim, _b["LeftHand"]).basis.orthonormalized()
	var down_l := (hang_hand.inverse() * Vector3(0.0, -1.0, 0.0)).normalized()
	var gl := grip_l_offset
	var x_l := (gl.basis.x - down_l * gl.basis.x.dot(down_l)).normalized()
	grip_l_offset = Transform3D(Basis(x_l, down_l, x_l.cross(down_l).normalized()), gl.origin)
	_ok = true


func _hang_global(skel: Skeleton3D, anim: Animation, bone: int) -> Transform3D:
	var chain: Array[int] = []
	var i := bone
	while i >= 0:
		chain.push_front(i)
		i = skel.get_bone_parent(i)
	var g := Transform3D.IDENTITY
	for b in chain:
		var rest := skel.get_bone_rest(b)
		var tr := anim.find_track(NodePath("%GeneralSkeleton:" + skel.get_bone_name(b)), Animation.TYPE_ROTATION_3D)
		var q := anim.rotation_track_interpolate(tr, 0.0) if tr >= 0 else rest.basis.get_rotation_quaternion()
		g = g * Transform3D(Basis(q), rest.origin)
	return g


func _add_curl_axis(skel: Skeleton3D, bone_name: String, palm_n: Vector3) -> void:
	var i := skel.find_bone(bone_name)
	if i < 0:
		return
	var g := skel.get_bone_global_rest(i)
	var dir := Vector3.ZERO
	var kids := skel.get_bone_children(i)
	if kids.size() > 0:
		dir = (skel.get_bone_global_rest(kids[0]).origin - g.origin).normalized()
	else:
		dir = (g.origin - skel.get_bone_global_rest(skel.get_bone_parent(i)).origin).normalized()
	var axis_g := dir.cross(palm_n).normalized()
	_curl_axes[i] = (g.basis.orthonormalized().inverse() * axis_g).normalized()


## Grip frame in hand-bone space. Right: +Y runs pinky->thumb (shaft through the fist, canopy up).
## Left: +Y runs wrist->fingers (closed umbrella hangs from the hooked fingers).
func _make_grip(skel: Skeleton3D, side: String, through_fist: bool) -> Transform3D:
	var h := skel.get_bone_global_rest(skel.find_bone(side + "Hand"))
	var inv := h.affine_inverse()
	var thumb := inv * skel.get_bone_global_rest(skel.find_bone(side + "ThumbProximal")).origin
	var little := inv * skel.get_bone_global_rest(skel.find_bone(side + "LittleProximal")).origin
	var middle := inv * skel.get_bone_global_rest(skel.find_bone(side + "MiddleProximal")).origin
	var palm := (h.basis.orthonormalized().inverse() * Vector3.DOWN).normalized()
	var along := Vector3.UP  # bone axis (wrist -> knuckles)
	var tdir := thumb - little
	tdir = (tdir - along * tdir.dot(along)).normalized()
	var x: Vector3
	var y: Vector3
	var origin: Vector3
	if through_fist:
		y = tdir
		x = (along - y * along.dot(y)).normalized()
		origin = along * middle.length() * 0.80 + palm * 0.035
	else:
		y = along
		x = tdir
		origin = along * middle.length() * 0.95 + palm * 0.03
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), origin)


func _process_modification_with_delta(_delta: float) -> void:
	if not _ok:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	var skel_from_char := char_from_skel.affine_inverse()
	var right_axis := (skel_from_char.basis * Vector3(0, 0, 1)).normalized()

	# --- Torso: slump (sad) and bent-over heavy breathing (stopped) ---------------------------
	var heave := 0.5 + 0.5 * sin(time * TAU * 0.8)
	# Posture: the retargeted UAL clips lean the MPFB torso and head well forward. Instead of fixed
	# offsets, measure the actual pose each frame and straighten the chain so the chest stacks over
	# the hips and the head over the chest (slight natural lean, more when running), keeping the
	# face level. Sad / breathing overlays are added on top afterwards.
	_align_posture(skel, right_axis)
	var fid := fiddle()
	# Leaning into it while opening / closing (Umbrella.open_lean; the player's rain sample points
	# lean by the same angle, so this is real extra cover, not just a look).
	var lean := Umbrella.open_lean(spread)
	var duck := Umbrella.open_duck(spread)
	# Hip hinge: tip the pelvis forward and counter-rotate the thighs so the legs don't move.
	var hinge := lean * 0.5
	if hinge > 0.0:
		_rot_global(skel, _b["Hips"], right_axis, -hinge)
		for side in ["Left", "Right"]:
			_rot_global(skel, skel.find_bone(side + "UpperLeg"), right_axis, hinge)
	var pitch_spine := sad * 0.11 + breath * (0.13 + 0.03 * heave) + lean * 0.2
	var pitch_chest := sad * 0.10 + breath * (0.10 - 0.05 * heave) + lean * 0.15
	var pitch_upper := sad * 0.08 + breath * (0.05 - 0.04 * heave) + lean * 0.15
	var pitch_neck := sad * 0.14 + breath * 0.04 + duck * 0.45
	var pitch_head := sad * 0.30 + breath * (0.10 + 0.04 * heave) + duck * 0.55
	# Forward pitch = rotate +Y toward +X = negative rotation about the character's +Z axis.
	_rot_global(skel, _b["Spine"], right_axis, -pitch_spine)
	_rot_global(skel, _b["Chest"], right_axis, -pitch_chest)
	_rot_global(skel, _b["UpperChest"], right_axis, -pitch_upper)
	_rot_global(skel, _b["Neck"], right_axis, -pitch_neck)
	_rot_global(skel, _b["Head"], right_axis, -pitch_head)
	# Shoulders hunch forward when sad / heave when out of breath.
	var fwd_axis := (skel_from_char.basis * Vector3(1, 0, 0)).normalized()
	var shrug := breath * 0.06 * heave
	_rot_global(skel, _b["LeftShoulder"], fwd_axis, shrug + sad * 0.06)
	_rot_global(skel, _b["RightShoulder"], fwd_axis, -shrug - sad * 0.06)

	# --- Arms toward a limp hang: carrying the closed umbrella (left), defeated (both) --------
	# Hurrying with a closed umbrella: that arm pumps less (keeps the umbrella from flailing).
	var left_hang := clampf(carry_damp + 0.4 * run + sad * 0.5 + breath * 0.5, 0.0, 0.9)
	var right_hang := clampf(sad * 0.75 + breath * 0.5, 0.0, 0.9)
	for n in ["LeftUpperArm", "LeftLowerArm"]:
		_slerp_to(skel, _b[n], _hang[n], left_hang)
	for n in ["RightUpperArm", "RightLowerArm"]:
		_slerp_to(skel, _b[n], _hang[n], right_hang)

	# --- Right arm umbrella IK ---------------------------------------------------------------
	var w := clampf(raise, 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	if w > 0.001:
		_solve_umbrella_arm(skel, skel_from_char, w)
	# --- Left hand works the runner while the umbrella opens / closes ----------------------------
	if fid > 0.001 and w > 0.001:
		_solve_runner_arm(skel, skel_from_char, fid * w)

	# --- Legs: slow walking takes shorter steps (walker.gd lowers the cycle length to match) ----
	if stride < 0.999:
		for side in ["Left", "Right"]:
			var ul := skel.find_bone(side + "UpperLeg")
			var hp := char_from_skel * skel.get_bone_global_pose(ul).origin
			var kp := char_from_skel * skel.get_bone_global_pose(skel.find_bone(side + "LowerLeg")).origin
			var ld := (kp - hp).normalized()
			var thigh := atan2(ld.x, -ld.y)
			_rot_global(skel, ul, right_axis, -(1.0 - stride) * thigh)

	# --- Knees: the retargeted clips carry ~10° of extra knee flexion through the cycle (a half-
	# squat look). Straighten every frame by up to `knee_unbend`, never past 3° (walker lifts the
	# model to keep the feet on the ground).
	for side in ["Left", "Right"]:
		var ul := skel.find_bone(side + "UpperLeg")
		var kn := skel.find_bone(side + "LowerLeg")
		var ft := skel.find_bone(side + "Foot")
		var hp := skel.get_bone_global_pose(ul).origin
		var kp := skel.get_bone_global_pose(kn).origin
		var ap := skel.get_bone_global_pose(ft).origin
		var thigh := (kp - hp).normalized()
		var shin := (ap - kp).normalized()
		var flex := thigh.angle_to(shin)
		var undo := minf(knee_unbend * (1.0 - 0.5 * run), maxf(flex - deg_to_rad(3.0), 0.0))
		var axis := shin.cross(thigh)
		if undo > 0.0 and axis.length_squared() > 1e-8:
			_rot_global(skel, kn, axis.normalized(), undo)

	# --- Feet: the clips hold the toes ~5–11° up when planted; turn the feet down to flat ------
	for side in ["Left", "Right"]:
		var ft := skel.find_bone(side + "Foot")
		var fp := char_from_skel * skel.get_bone_global_pose(ft).origin
		var tp := char_from_skel * skel.get_bone_global_pose(skel.find_bone(side + "Toes")).origin
		var d := tp - fp
		var pitch := atan2(d.y, Vector2(d.x, d.z).length())     # + = toes up
		# Planted: flat. Swing / heel strike: the capture flicks the toes up a lot — allow only a
		# little dorsiflexion (toe_swing_max) so the toes never point up at the camera.
		var planted := 1.0 - smoothstep(0.09, 0.2, fp.y)
		var allowed := lerpf(toe_swing_max, toe_target, planted)
		var corr := clampf(pitch - allowed, 0.0, 0.8)
		# For a bone pointing forward (+X), a positive rotation about the right axis lifts it.
		_rot_global(skel, ft, right_axis, -corr)

	# --- Free arm: swing back behind the hip as the same-side leg comes forward ----------------
	if w < 0.5:
		_swing(skel, "Right", right_axis, free_arm_swing * (1.0 - 2.0 * w) * (1.0 - 0.7 * sad), 0.4)

	# --- Fists ---------------------------------------------------------------------------------
	_curl_hand(skel, "Left", 1.0)
	_curl_hand(skel, "Right", lerpf(0.35 + 0.25 * run, 1.0, w))


func _solve_umbrella_arm(skel: Skeleton3D, skel_from_char: Transform3D, w: float) -> void:
	var sway_a := (sin(time * 2.3) * 0.22 + sin(time * 3.9 + 1.0) * 0.07) * droop
	var sway_side := sin(time * 1.7 + 0.5) * 0.12 * droop
	# Tipped forward while being opened / closed (at least OPEN_TIP, more if the player tilts it).
	var tilt_now := lerpf(tilt, maxf(tilt, OPEN_TIP), Umbrella.open_tip(spread))
	var tilt_total := tilt_now + sway_a
	# Hold the umbrella relative to where his chest actually is (elbow bent ~90°, hand at chest/
	# chin height in front of the sternum), not at a fixed point he would have to reach for.
	var neck_c := char_from_skel * skel.get_bone_global_pose(_b["Neck"]).origin
	var p := Vector3(neck_c.x + HOLD_FWD, neck_c.y + HOLD_DROP, HOLD_POS.z)
	p.x += 0.03 * tilt_now     # the shaft tilts at the wrist; the arm barely moves
	p.y += -0.04 * absf(tilt_now) - 0.24 * droop
	p.z += 0.07 * droop
	# Opening / closing: hold it out a little ahead, so the folded canopy isn't in his face.
	var fid := fiddle()
	p.x += RUNNER_PUSH_FWD * fid
	p.y += 0.03 * fid

	var rot := Basis(Vector3(0, 0, 1), -tilt_total) * Basis(Vector3(1, 0, 0), sway_side)
	var y_c := rot * Vector3.UP
	var x_c := HOLD_FINGER_DIR.normalized()
	x_c = (x_c - y_c * x_c.dot(y_c)).normalized()
	var z_c := x_c.cross(y_c).normalized()
	var grip_c := Transform3D(Basis(x_c, y_c, z_c), p)
	var hand_s := skel_from_char * grip_c * grip_r_offset.affine_inverse()

	_ik_arm(skel, skel_from_char, "Right", hand_s, ELBOW_POLE, w)


## 0..1 how busy the left hand is with the umbrella: on while it opens/closes, off when it is
## closed (carried) or fully open (held in the right hand alone).
func fiddle() -> float:
	return Umbrella.hand_on_shaft(spread)


## Left fist around the shaft under the canopy, sliding up as it opens (down as it closes). The shaft
## frame comes from the right hand as just posed, so the hands stay together.
func _solve_runner_arm(skel: Skeleton3D, skel_from_char: Transform3D, w: float) -> void:
	var grip_r := skel.get_bone_global_pose(_b["RightHand"]) * grip_r_offset
	var y_s := grip_r.basis.y.normalized()
	var c := Umbrella.canopy_spread(spread) / Umbrella.OPEN_SPREAD
	var h := lerpf(RUNNER_LOW, RUNNER_HIGH, clampf(c, 0.0, 1.0))
	var x_s := (skel_from_char.basis * RUNNER_FINGER_DIR).normalized()
	x_s = (x_s - y_s * x_s.dot(y_s)).normalized()
	var grip_l := Transform3D(Basis(x_s, y_s, x_s.cross(y_s).normalized()), grip_r.origin + y_s * h)
	var target := grip_l * grip_lf_offset.affine_inverse()
	# Reach / let go by moving the hand target between its animated swing and the shaft (blending
	# joint rotations instead swings the arm out straight in front of him half way).
	var anim := skel.get_bone_global_pose(_b["LeftHand"])
	var k := smoothstep(0.0, 1.0, w)
	var hand_s := Transform3D(anim.basis.orthonormalized().slerp(target.basis.orthonormalized(), k),
			anim.origin.lerp(target.origin, k))
	_ik_arm(skel, skel_from_char, "Left", hand_s, ELBOW_POLE_L, clampf(w * 4.0, 0.0, 1.0))


## Analytic two-bone IK: place `side`'s hand bone at `hand_s` (skeleton space), elbow toward
## `pole_char` (character frame), blended over the animated pose by `w`.
func _ik_arm(skel: Skeleton3D, skel_from_char: Transform3D, side: String, hand_s: Transform3D, pole_char: Vector3, w: float) -> void:
	var i_sh := _b[side + "Shoulder"] as int
	var i_ua := _b[side + "UpperArm"] as int
	var i_la := _b[side + "LowerArm"] as int
	var i_h := _b[side + "Hand"] as int
	var anim_ua := skel.get_bone_pose_rotation(i_ua)
	var anim_la := skel.get_bone_pose_rotation(i_la)
	var anim_h := skel.get_bone_pose_rotation(i_h)

	var g_ua := skel.get_bone_global_pose(i_ua)
	var g_la := skel.get_bone_global_pose(i_la)
	var s := g_ua.origin
	var wrist := hand_s.origin
	var to_w := wrist - s
	var d := clampf(to_w.length(), 0.02, (_len_upper + _len_lower) * 0.999)
	var u := to_w.normalized()
	var pole := (skel_from_char.basis * pole_char).normalized()
	pole = (pole - u * pole.dot(u)).normalized()
	var cos_a := clampf((_len_upper * _len_upper + d * d - _len_lower * _len_lower) / (2.0 * _len_upper * d), -1.0, 1.0)
	var a := acos(cos_a)
	var elbow := s + u * _len_upper * cos(a) + pole * _len_upper * sin(a)

	# Upper arm: swing the animated basis so the bone points at the elbow.
	var ua_basis := g_ua.basis.orthonormalized()
	ua_basis = Basis(_arc(ua_basis.y, (elbow - s).normalized())) * ua_basis
	# Lower arm: carry the upper arm's new orientation, then swing to the wrist.
	var la_local_basis := skel.get_bone_pose(i_la).basis.orthonormalized()
	var la_basis := ua_basis * la_local_basis
	la_basis = Basis(_arc(la_basis.y, (wrist - elbow).normalized())) * la_basis
	# Move ~60% of the hand's twist into the forearm to avoid a candy-wrapper wrist.
	var h_local := (la_basis.inverse() * hand_s.basis.orthonormalized()).get_rotation_quaternion()
	var twist := 2.0 * atan2(h_local.y, h_local.w)
	la_basis = la_basis * Basis(Vector3.UP, twist * 0.6)

	var sh_basis := skel.get_bone_global_pose(i_sh).basis.orthonormalized()
	var q_ua := (sh_basis.inverse() * ua_basis).get_rotation_quaternion()
	var q_la := (ua_basis.inverse() * la_basis).get_rotation_quaternion()
	var q_h := (la_basis.inverse() * hand_s.basis.orthonormalized()).get_rotation_quaternion()
	skel.set_bone_pose_rotation(i_ua, anim_ua.slerp(q_ua, w))
	skel.set_bone_pose_rotation(i_la, anim_la.slerp(q_la, w))
	skel.set_bone_pose_rotation(i_h, anim_h.slerp(q_h, w))


func _curl_hand(skel: Skeleton3D, side: String, amount: float) -> void:
	for f in FINGERS:
		for s in SEGMENTS:
			_curl(skel, skel.find_bone(side + f + s), CURL[s] * amount)
	_curl(skel, skel.find_bone(side + "ThumbProximal"), 0.35 * amount)
	_curl(skel, skel.find_bone(side + "ThumbDistal"), 0.5 * amount)


func _curl(skel: Skeleton3D, i: int, ang: float) -> void:
	if i < 0 or not _curl_axes.has(i):
		return
	var q := skel.get_bone_pose_rotation(i)
	skel.set_bone_pose_rotation(i, (q * Quaternion(_curl_axes[i], ang)).normalized())


func _slerp_to(skel: Skeleton3D, i: int, target: Quaternion, k: float) -> void:
	if k <= 0.0:
		return
	skel.set_bone_pose_rotation(i, skel.get_bone_pose_rotation(i).slerp(target, k))


## Forward lean (radians, + = toward +X) of the segment a→b, in the character frame.
func _arm_angle(skel: Skeleton3D, side: String) -> float:
	var sh := char_from_skel * skel.get_bone_global_pose(_b[side + "UpperArm"]).origin
	var el := char_from_skel * skel.get_bone_global_pose(_b[side + "LowerArm"]).origin
	var d := (el - sh).normalized()
	return atan2(d.x, -d.y)


func _elbow_bend(skel: Skeleton3D, side: String) -> float:
	var sh := skel.get_bone_global_pose(_b[side + "UpperArm"]).origin
	var el := skel.get_bone_global_pose(_b[side + "LowerArm"]).origin
	var wr := skel.get_bone_global_pose(_b[side + "Hand"]).origin
	return (el - sh).angle_to(wr - el)


## Set an elbow to `bend` radians of flexion (forearm swung forward of the upper arm's line).
func _set_elbow(skel: Skeleton3D, side: String, right_axis: Vector3, bend: float) -> void:
	var ua: int = _b[side + "UpperArm"]
	var la: int = _b[side + "LowerArm"]
	var hd: int = _b[side + "Hand"]
	var sh := skel.get_bone_global_pose(ua).origin
	var el := skel.get_bone_global_pose(la).origin
	var wr := skel.get_bone_global_pose(hd).origin
	var upper := (el - sh).normalized()
	var cur := (wr - el).normalized()
	var target := (Basis(right_axis, bend) * upper).normalized()   # forearm forward of the upper arm
	var axis := cur.cross(target)
	if axis.length_squared() < 1e-8:
		return
	_rot_global(skel, la, axis.normalized(), cur.angle_to(target))


## Effective stride scale (kept for callers of the old API).
func stride_now() -> float:
	return stride


## Swing an upper arm from the shoulder, opposite to the same-side leg (the formal-walk clip
## barely swings its arms). `gain` = arm angle per unit of thigh angle.
func _swing(skel: Skeleton3D, side: String, right_axis: Vector3, gain: float, max_fwd := 0.35) -> void:
	var ua: int = _b[side + "UpperArm"]
	var sh := char_from_skel * skel.get_bone_global_pose(ua).origin
	var el := char_from_skel * skel.get_bone_global_pose(_b[side + "LowerArm"]).origin
	var dir := (el - sh).normalized()
	var ang := atan2(dir.x, -dir.y)              # + = arm swung forward
	var hip := char_from_skel * skel.get_bone_global_pose(skel.find_bone(side + "UpperLeg")).origin
	var knee := char_from_skel * skel.get_bone_global_pose(skel.find_bone(side + "LowerLeg")).origin
	var ld := (knee - hip).normalized()
	var thigh := atan2(ld.x, -ld.y)               # + = leg forward
	var target := clampf(-gain * thigh + 0.06, -0.26, max_fwd)   # slight forward bias, even swing
	# For a limb pointing DOWN, a positive rotation about the right axis swings it forward.
	_rot_global(skel, ua, right_axis, target - ang)


func _lean(skel: Skeleton3D, a: int, b: int) -> float:
	var v := char_from_skel.basis * (skel.get_bone_global_pose(b).origin - skel.get_bone_global_pose(a).origin)
	return atan2(v.x, v.y)


func _align_posture(skel: Skeleton3D, right_axis: Vector3) -> void:
	var w := 1.0 - 0.7 * sad        # sad slump is authored separately; mostly leave it alone
	# Torso: the whole hips → neck line should lean only slightly forward. (The UpperChest bone sits
	# low, at the bottom of the ribcage, so measuring to it misses the forward-hunched shoulders.)
	# Iterate a couple of times because each bone's rotation shifts the ones above it.
	# Pelvis: the clips carry the legs trailing behind the body (hips ~9 cm ahead of the feet on
	# average), so he looks like he's tipping forward. Pitch the pelvis back to bring the legs under
	# him; the spine is re-straightened below.
	_rot_global(skel, _b["Hips"], right_axis, hip_back * lerpf(1.0, 2.2, run) * w)
	# Posterior pelvic tilt WITHOUT moving the legs: tip the pelvis back, counter-rotate the thighs.
	var tilt_p := pelvis_tilt * w
	_rot_global(skel, _b["Hips"], right_axis, tilt_p)
	for side in ["Left", "Right"]:
		var th := skel.find_bone(side + "UpperLeg")
		if th >= 0:
			_rot_global(skel, th, right_axis, -tilt_p)
	# ...and bring the upper body back over it at the lower spine: flattens the lumbar curve so
	# the belly no longer pushes forward, without leaning the chest back.
	_rot_global(skel, _b["Spine"], right_axis, -tilt_p)
	# Optional per-frame straightening (off by default: the mocap clips carry a natural posture).
	if posture_fix > 0.0:
		var torso_target := lerpf(0.045, 0.1, run)
		for k in 2:
			var d := (_lean(skel, _b["Hips"], _b["Neck"]) - torso_target) * w * posture_fix
			_rot_global(skel, _b["Spine"], right_axis, d * 0.34)
			_rot_global(skel, _b["Chest"], right_axis, d * 0.33)
			_rot_global(skel, _b["UpperChest"], right_axis, d * 0.33)
	# Lean into the wind when holding the umbrella tilted forward (upper body only).
	var wind := -0.07 * maxf(tilt, 0.0) * raise * w
	_rot_global(skel, _b["Chest"], right_axis, wind * 0.5)
	_rot_global(skel, _b["UpperChest"], right_axis, wind * 0.5)
	# Head: keep the face level — the head bone's up axis near vertical (eyes very slightly down).
	var hb := char_from_skel.basis * skel.get_bone_global_pose(_b["Head"]).basis.orthonormalized()
	var up := hb * _head_up_local
	var hd := (atan2(up.x, up.y) - 0.2) * w * head_level
	_rot_global(skel, _b["Head"], right_axis, hd)


func _rot_global(skel: Skeleton3D, i: int, axis_s: Vector3, ang: float) -> void:
	if absf(ang) < 1e-5:
		return
	var p := skel.get_bone_parent(i)
	var pb := skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var la := (pb.inverse() * axis_s).normalized()
	skel.set_bone_pose_rotation(i, (Quaternion(la, ang) * skel.get_bone_pose_rotation(i)).normalized())


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var c := from.cross(to)
	var dt := from.dot(to)
	if c.length_squared() < 1e-10:
		return Quaternion.IDENTITY if dt > 0.0 else Quaternion(Vector3.RIGHT, PI)
	return Quaternion(from, to)
