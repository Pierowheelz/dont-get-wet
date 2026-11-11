extends SkeletonModifier3D
## Procedural pose layer for pedestrians (runs after the locomotion AnimationTree).
## Behaviours: hold an open umbrella (right or left hand), smoke (right hand to mouth now and then),
## check a wristwatch (left arm), hurry hunched against the rain, look around while standing.
## Targets are authored in the *character* frame (+X forward, +Y up, +Z = character's right).

var umbrella := 0.0     # 0..1 the umbrella arm holds the shaft up in front of the chest
var umbrella_left := false
var holding := false    # the umbrella hand is closed on a handle, arm raised or not
var smoke := false
var watch := false
var watch_right := false  # check the watch with the right (camera-side) arm
var hunch := 0.0        # 0..1 lean into the rain (hurrying, hood up)
var look_around := 0.0  # 0..1 idle head turns
var time := 0.0
var seed_phase := 0.0
var char_from_skel := Transform3D.IDENTITY
var hold_pos := Vector3(0.30, 1.42, 0.07)  # umbrella grip (palm centre), scaled per body height

var grip_r_offset := Transform3D.IDENTITY  # umbrella grip in RightHand bone space (+Y = to canopy)
var grip_l_offset := Transform3D.IDENTITY  # the same in LeftHand bone space
var hand_r_offset := Transform3D.IDENTITY  # between index & middle finger, for the cigarette

var _b := {}
var _hang := {}
var _curl_axes := {}
var _thumb_local := {}   # side -> thumb direction in hand-bone space
var _len := {}           # side -> [upper, lower]
var _chest_rest := Vector3.ZERO
var _ok := false

const BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
const FINGERS := ["Index", "Middle", "Ring", "Little"]
const SEGMENTS := ["Proximal", "Intermediate", "Distal"]
const CURL := {"Proximal": 1.25, "Intermediate": 1.45, "Distal": 0.9}


func setup(skel: Skeleton3D, idle_anim: Animation, height_scale: float) -> void:
	for n in BONES:
		_b[n] = skel.find_bone(n)
		if _b[n] < 0:
			push_error("ped: missing bone %s" % n)
			return
	for n in ["LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm"]:
		var tr := idle_anim.find_track(NodePath("%GeneralSkeleton:" + n), Animation.TYPE_ROTATION_3D)
		_hang[n] = idle_anim.rotation_track_interpolate(tr, 0.0) if tr >= 0 \
				else skel.get_bone_rest(_b[n]).basis.get_rotation_quaternion()
	for side in ["Left", "Right"]:
		var ua := skel.get_bone_global_rest(_b[side + "UpperArm"]).origin
		var la := skel.get_bone_global_rest(_b[side + "LowerArm"]).origin
		var ha := skel.get_bone_global_rest(_b[side + "Hand"]).origin
		_len[side] = [ua.distance_to(la), la.distance_to(ha)]
		var h := skel.get_bone_global_rest(_b[side + "Hand"])
		var inv := h.affine_inverse()
		var th := inv * skel.get_bone_global_rest(skel.find_bone(side + "ThumbProximal")).origin
		var li := inv * skel.get_bone_global_rest(skel.find_bone(side + "LittleProximal")).origin
		var t := th - li
		_thumb_local[side] = (t - Vector3.UP * t.y).normalized()
		for f in FINGERS:
			for s in SEGMENTS:
				_add_curl_axis(skel, side + f + s)
		for s in ["Proximal", "Distal"]:
			_add_curl_axis(skel, side + "Thumb" + s)
	_chest_rest = skel.get_bone_global_rest(_b["UpperChest"]).origin
	hold_pos.y *= height_scale
	hold_pos.x *= lerpf(1.0, height_scale, 0.5)
	grip_r_offset = _grip_offset(skel, "Right")
	grip_l_offset = _grip_offset(skel, "Left")
	var h_r := skel.get_bone_global_rest(_b["RightHand"])
	var idx := h_r.affine_inverse() * skel.get_bone_global_rest(skel.find_bone("RightIndexIntermediate")).origin
	var mdi := h_r.affine_inverse() * skel.get_bone_global_rest(skel.find_bone("RightMiddleIntermediate")).origin
	hand_r_offset = Transform3D(Basis.IDENTITY, (idx + mdi) * 0.5)
	_ok = true


## Umbrella grip in the hand bone's space: +Y runs pinky -> thumb (shaft through the fist).
func _grip_offset(skel: Skeleton3D, side: String) -> Transform3D:
	var h := skel.get_bone_global_rest(_b[side + "Hand"])
	var mid := h.affine_inverse() * skel.get_bone_global_rest(skel.find_bone(side + "MiddleProximal")).origin
	var palm := (h.basis.orthonormalized().inverse() * Vector3.DOWN).normalized()
	var y: Vector3 = _thumb_local[side]
	var x := (Vector3.UP - y * y.dot(Vector3.UP)).normalized()
	return Transform3D(Basis(x, y, x.cross(y).normalized()), Vector3.UP * mid.length() * 0.8 + palm * 0.035)


func _add_curl_axis(skel: Skeleton3D, bone_name: String) -> void:
	var i := skel.find_bone(bone_name)
	if i < 0:
		return
	var g := skel.get_bone_global_rest(i)
	var kids := skel.get_bone_children(i)
	var dir: Vector3
	if kids.size() > 0:
		dir = (skel.get_bone_global_rest(kids[0]).origin - g.origin).normalized()
	else:
		dir = (g.origin - skel.get_bone_global_rest(skel.get_bone_parent(i)).origin).normalized()
	_curl_axes[i] = (g.basis.orthonormalized().inverse() * dir.cross(Vector3.DOWN).normalized()).normalized()


static func pulse(t: float, period: float, on: float, ramp: float) -> float:
	var p := fposmod(t, period)
	if p > on:
		return 0.0
	return smoothstep(0.0, ramp, p) * (1.0 - smoothstep(on - ramp, on, p))


func _process_modification_with_delta(_delta: float) -> void:
	if not _ok:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	var s_from_c := char_from_skel.affine_inverse()
	var right_axis := (s_from_c.basis * Vector3(0, 0, 1)).normalized()
	var up_axis := (s_from_c.basis * Vector3.UP).normalized()
	var t := time + seed_phase

	var watch_w := pulse(t, 7.5, 3.2, 0.6) if watch else 0.0
	var smoke_w := pulse(t + 2.0, 8.0, 3.0, 0.7) if smoke else 0.0

	# Torso & head. Forward pitch = negative rotation about the character's +Z axis.
	# (The mocap clips already have a neutral, upright posture; only overlays are added here.)
	_rot_global(skel, _b["Spine"], right_axis, -hunch * 0.10)
	_rot_global(skel, _b["Chest"], right_axis, -hunch * 0.06)
	_rot_global(skel, _b["Neck"], right_axis, -hunch * 0.04 - watch_w * 0.15)
	_rot_global(skel, _b["Head"], right_axis, -hunch * 0.18 - watch_w * 0.30 + smoke_w * 0.06)
	if look_around > 0.0:
		var yaw := (sin(t * 0.37) * 0.6 + sin(t * 0.91 + 1.3) * 0.25) * look_around * (1.0 - watch_w)
		_rot_global(skel, _b["Neck"], up_axis, yaw * 0.4)
		_rot_global(skel, _b["Head"], up_axis, yaw * 0.6)

	# Feet: in this rig the rest pose leaves the toes ~17° up; flatten planted feet and keep the
	# toes from pointing up during the swing (same correction as the player walker).
	for side in ["Left", "Right"]:
		var ft := skel.find_bone(side + "Foot")
		var tb := skel.find_bone(side + "Toes")
		if ft < 0 or tb < 0:
			continue
		var fp := char_from_skel * skel.get_bone_global_pose(ft).origin
		var tp := char_from_skel * skel.get_bone_global_pose(tb).origin
		var d := tp - fp
		var pitch := atan2(d.y, Vector2(d.x, d.z).length())
		var planted := 1.0 - smoothstep(0.09, 0.2, fp.y)
		var allowed := lerpf(-0.12, -0.3, planted)
		_rot_global(skel, ft, right_axis, -clampf(pitch - allowed, 0.0, 0.8))

	# Arms: calmer swing when carrying something / hurrying hands near the body.
	var left_hang := 0.1 + hunch * 0.3
	var right_hang := 0.1 + hunch * 0.3
	for n in ["LeftUpperArm", "LeftLowerArm"]:
		_slerp_to(skel, _b[n], _hang[n], left_hang)
	for n in ["RightUpperArm", "RightLowerArm"]:
		_slerp_to(skel, _b[n], _hang[n], right_hang)

	var chest_now := skel.get_bone_global_pose(_b["UpperChest"]).origin
	var chest_d := (char_from_skel.basis * (chest_now - _chest_rest)) * Vector3(1.0, 0.8, 0.6)

	if umbrella > 0.001:
		var m := -1.0 if umbrella_left else 1.0  # mirror across the character's sagittal plane
		var x_c := Vector3(0.35, 0.0, -m).normalized()
		var at := Vector3(hold_pos.x, hold_pos.y, hold_pos.z * m) + chest_d
		var grip_c := Transform3D(Basis(x_c, Vector3.UP, x_c.cross(Vector3.UP).normalized()), at)
		var hand_s := s_from_c * grip_c * (grip_l_offset if umbrella_left else grip_r_offset).affine_inverse()
		_solve_arm(skel, "Left" if umbrella_left else "Right", hand_s, Vector3(-0.15, -1.0, 0.75 * m), umbrella)
	elif smoke_w > 0.001:
		var hs: float = hold_pos.y / 1.42
		var mouth := Vector3(0.13, 1.56 * hs, 0.03) + chest_d
		var wrist := Vector3(0.20, 1.40 * hs, 0.10) + chest_d
		var hb := _hand_basis("Right", s_from_c.basis * (mouth - wrist).normalized(), s_from_c.basis * Vector3(0.2, 0.3, -1.0))
		_solve_arm(skel, "Right", Transform3D(hb, s_from_c * wrist), Vector3(-0.2, -1.0, 0.6), smoke_w)

	if watch_w > 0.001:
		# Forearm across the chest, palm down, back of the wrist turned up toward the eyes.
		var hs2: float = hold_pos.y / 1.42
		var m := 1.0 if watch_right else -1.0  # mirror across the character's sagittal plane
		var side := "Right" if watch_right else "Left"
		var wrist_w := Vector3(0.25, 1.24 * hs2, 0.06 * m) + chest_d
		var hb_w := _hand_basis(side, s_from_c.basis * Vector3(0.35, 0.1, -1.0 * m).normalized(), s_from_c.basis * Vector3(-1.0, 0.2, 0.0))
		_solve_arm(skel, side, Transform3D(hb_w, s_from_c * wrist_w), Vector3(-0.2, -1.0, 0.6 * m), watch_w)

	_curl_hand(skel, "Right", 1.0 if holding and not umbrella_left else (0.55 if smoke else 0.3))
	_curl_hand(skel, "Left", 1.0 if holding and umbrella_left else 0.35)


## Hand basis (skeleton space) whose fingers point along `fingers` with the thumb toward `thumb`.
func _hand_basis(side: String, fingers: Vector3, thumb: Vector3) -> Basis:
	var yt := fingers.normalized()
	var xt := (thumb - yt * thumb.dot(yt)).normalized()
	var target := Basis(xt, yt, xt.cross(yt).normalized())
	var tl: Vector3 = _thumb_local[side]
	var local := Basis(tl, Vector3.UP, tl.cross(Vector3.UP).normalized())
	return target * local.inverse()


func _solve_arm(skel: Skeleton3D, side: String, hand_s: Transform3D, pole_c: Vector3, w: float) -> void:
	w = clampf(w, 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	var s_from_c := char_from_skel.affine_inverse()
	var i_sh: int = _b[side + "Shoulder"]
	var i_ua: int = _b[side + "UpperArm"]
	var i_la: int = _b[side + "LowerArm"]
	var i_h: int = _b[side + "Hand"]
	var l1: float = _len[side][0]
	var l2: float = _len[side][1]
	var anim_ua := skel.get_bone_pose_rotation(i_ua)
	var anim_la := skel.get_bone_pose_rotation(i_la)
	var anim_h := skel.get_bone_pose_rotation(i_h)
	var g_ua := skel.get_bone_global_pose(i_ua)
	var s := g_ua.origin
	var wrist := hand_s.origin
	var to_w := wrist - s
	var d := clampf(to_w.length(), 0.02, (l1 + l2) * 0.999)
	var u := to_w.normalized()
	var pole := (s_from_c.basis * pole_c).normalized()
	pole = (pole - u * pole.dot(u)).normalized()
	var a := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var elbow := s + u * l1 * cos(a) + pole * l1 * sin(a)
	var ua_basis := g_ua.basis.orthonormalized()
	ua_basis = Basis(_arc(ua_basis.y, (elbow - s).normalized())) * ua_basis
	var la_basis := ua_basis * skel.get_bone_pose(i_la).basis.orthonormalized()
	la_basis = Basis(_arc(la_basis.y, (wrist - elbow).normalized())) * la_basis
	var h_local := (la_basis.inverse() * hand_s.basis.orthonormalized()).get_rotation_quaternion()
	la_basis = la_basis * Basis(Vector3.UP, 2.0 * atan2(h_local.y, h_local.w) * 0.6)
	var sh_basis := skel.get_bone_global_pose(i_sh).basis.orthonormalized()
	skel.set_bone_pose_rotation(i_ua, anim_ua.slerp((sh_basis.inverse() * ua_basis).get_rotation_quaternion(), w))
	skel.set_bone_pose_rotation(i_la, anim_la.slerp((ua_basis.inverse() * la_basis).get_rotation_quaternion(), w))
	skel.set_bone_pose_rotation(i_h, anim_h.slerp((la_basis.inverse() * hand_s.basis.orthonormalized()).get_rotation_quaternion(), w))


func _curl_hand(skel: Skeleton3D, side: String, amount: float) -> void:
	for f in FINGERS:
		for s in SEGMENTS:
			_curl(skel, skel.find_bone(side + f + s), CURL[s] * amount)
	_curl(skel, skel.find_bone(side + "ThumbProximal"), 0.35 * amount)
	_curl(skel, skel.find_bone(side + "ThumbDistal"), 0.5 * amount)


func _curl(skel: Skeleton3D, i: int, ang: float) -> void:
	if i < 0 or not _curl_axes.has(i):
		return
	skel.set_bone_pose_rotation(i, (skel.get_bone_pose_rotation(i) * Quaternion(_curl_axes[i], ang)).normalized())


func _slerp_to(skel: Skeleton3D, i: int, target: Quaternion, k: float) -> void:
	if k > 0.0:
		skel.set_bone_pose_rotation(i, skel.get_bone_pose_rotation(i).slerp(target, k))


func _rot_global(skel: Skeleton3D, i: int, axis_s: Vector3, ang: float) -> void:
	if absf(ang) < 1e-5:
		return
	var p := skel.get_bone_parent(i)
	var pb := skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	skel.set_bone_pose_rotation(i, (Quaternion((pb.inverse() * axis_s).normalized(), ang) * skel.get_bone_pose_rotation(i)).normalized())


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.cross(to).length_squared() < 1e-10:
		return Quaternion.IDENTITY if from.dot(to) > 0.0 else Quaternion(Vector3.RIGHT, PI)
	return Quaternion(from, to)
