extends SkeletonModifier3D
## Procedural layer applied on top of the locomotion AnimationTree (runs after the mixer).
## - spine/neck slump (sad), bent-over heavy breathing (stopped / catching breath)
## - right arm: analytic two-bone IK to the umbrella-holding pose, blended by `raise`
## - left arm: reduced swing (carrying the closed umbrella), fists around the handles
## All targets are authored in the *character* frame (+X forward, +Y up, +Z = character's right).

# Driven by walker.gd every frame.
var raise := 0.0
var tilt := 0.0
var droop := 0.0
var sad := 0.0
var breath := 0.0      # 0..1 weight of the "catching breath" overlay
var run := 0.0         # 0 walk .. 1 run (allows a little more forward lean)
var time := 0.0
var char_from_skel := Transform3D.IDENTITY

# Umbrella hold pose (character frame, metres). Grip = palm centre.
const HOLD_POS := Vector3(0.30, 1.46, 0.07)
const HOLD_FINGER_DIR := Vector3(0.35, 0.0, -1.0)  # knuckles point forward/inward across the chest
const ELBOW_POLE := Vector3(-0.15, -1.0, 0.75)      # elbow down and out to the side

var grip_r_offset := Transform3D.IDENTITY  # grip frame expressed in RightHand bone space
var grip_l_offset := Transform3D.IDENTITY  # grip frame expressed in LeftHand bone space

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
	var pitch_spine := sad * 0.11 + breath * (0.13 + 0.03 * heave)
	var pitch_chest := sad * 0.10 + breath * (0.10 - 0.05 * heave)
	var pitch_upper := sad * 0.08 + breath * (0.05 - 0.04 * heave)
	var pitch_neck := sad * 0.14 + breath * 0.04
	var pitch_head := sad * 0.30 + breath * (0.10 + 0.04 * heave)
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
	var left_hang := clampf(0.35 + sad * 0.5 + breath * 0.5, 0.0, 0.9)
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

	# --- Fists ---------------------------------------------------------------------------------
	_curl_hand(skel, "Left", 1.0)
	_curl_hand(skel, "Right", 0.3 + 0.7 * w)


func _solve_umbrella_arm(skel: Skeleton3D, skel_from_char: Transform3D, w: float) -> void:
	var sway_a := (sin(time * 2.3) * 0.22 + sin(time * 3.9 + 1.0) * 0.07) * droop
	var sway_side := sin(time * 1.7 + 0.5) * 0.12 * droop
	var tilt_total := tilt + sway_a
	var p := HOLD_POS
	p.x += 0.10 * tilt - 0.05 * droop + sin(time * 2.3 - 0.4) * 0.04 * droop
	p.y += -0.04 * absf(tilt) - 0.24 * droop
	p.z += 0.07 * droop
	# Follow the torso (bob, slump) but keep the umbrella upright.
	var chest_now := skel.get_bone_global_pose(_b["UpperChest"]).origin
	var chest_delta_c := char_from_skel.basis * (chest_now - _chest_rest)
	p += chest_delta_c * Vector3(1.0, 0.8, 0.6)

	var rot := Basis(Vector3(0, 0, 1), -tilt_total) * Basis(Vector3(1, 0, 0), sway_side)
	var y_c := rot * Vector3.UP
	var x_c := HOLD_FINGER_DIR.normalized()
	x_c = (x_c - y_c * x_c.dot(y_c)).normalized()
	var z_c := x_c.cross(y_c).normalized()
	var grip_c := Transform3D(Basis(x_c, y_c, z_c), p)
	var hand_s := skel_from_char * grip_c * grip_r_offset.affine_inverse()

	var i_sh := _b["RightShoulder"] as int
	var i_ua := _b["RightUpperArm"] as int
	var i_la := _b["RightLowerArm"] as int
	var i_h := _b["RightHand"] as int
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
	var pole := (skel_from_char.basis * ELBOW_POLE).normalized()
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
func _lean(skel: Skeleton3D, a: int, b: int) -> float:
	var v := char_from_skel.basis * (skel.get_bone_global_pose(b).origin - skel.get_bone_global_pose(a).origin)
	return atan2(v.x, v.y)


func _align_posture(skel: Skeleton3D, right_axis: Vector3) -> void:
	var w := 1.0 - 0.7 * sad        # sad slump is authored separately; mostly leave it alone
	# Torso: hips → upper chest should lean only slightly forward.
	var torso_target := lerpf(0.07, 0.16, run)
	var d := (_lean(skel, _b["Hips"], _b["UpperChest"]) - torso_target) * w
	_rot_global(skel, _b["Spine"], right_axis, d * 0.4)
	_rot_global(skel, _b["Chest"], right_axis, d * 0.3)
	_rot_global(skel, _b["UpperChest"], right_axis, d * 0.3)
	# Neck: upper chest → head should be close to vertical (ears over shoulders).
	var nd := (_lean(skel, _b["UpperChest"], _b["Head"]) - lerpf(0.06, 0.12, run)) * w
	_rot_global(skel, _b["Neck"], right_axis, nd)
	# Head: keep the face level — the head bone's up axis near vertical.
	var hb := char_from_skel.basis * skel.get_bone_global_pose(_b["Head"]).basis.orthonormalized()
	var up := hb * _head_up_local
	var hd := (atan2(up.x, up.y) - 0.12) * w     # eyes level / very slightly down, not chin-up
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
