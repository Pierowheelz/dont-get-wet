extends Node
## Pelvis / foot pitch vs the rest pose (degrees, + = tipped forward / toes down).
var sk: Skeleton3D
var w: Node3D
var acc := {}
var n := 0
func _pitch_vs_rest(bone: String, axis_local: Vector3) -> float:
	var i := sk.find_bone(bone)
	var cur := (w.global_transform.basis.inverse() * sk.global_transform.basis * sk.get_bone_global_pose(i).basis.orthonormalized() * axis_local)
	return rad_to_deg(atan2(cur.x, cur.y))
func _grab() -> void:
	var hips := sk.find_bone("Hips")
	var hr := sk.get_bone_global_rest(hips).basis.orthonormalized()
	var up_l := hr.inverse() * Vector3.UP          # hips local axis that is world-up at rest
	var fwd_l := hr.inverse() * Vector3(0, 0, 1)    # skeleton forward (+Z in skel space)
	var k := {"pelvis_up": _pitch_vs_rest("Hips", up_l)}
	for side in ["Left", "Right"]:
		var f := sk.find_bone(side + "Foot")
		var t := sk.find_bone(side + "Toes")
		var fp := w.to_local(sk.to_global(sk.get_bone_global_pose(f).origin))
		var tp := w.to_local(sk.to_global(sk.get_bone_global_pose(t).origin))
		var d := tp - fp
		k[side + "_toe_pitch"] = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))   # + = toes up
		k[side + "_foot_y"] = fp.y
		var tb := sk.global_transform.basis * sk.get_bone_global_pose(t).basis.orthonormalized()
		var td := w.global_transform.basis.inverse() * (tb * Vector3.UP)
		k[side + "_toeseg_pitch"] = rad_to_deg(atan2(td.y, Vector2(td.x, td.z).length()))
	for key in k:
		acc[key] = acc.get(key, []) + [k[key]]
	n += 1
func _ready() -> void:
	w = load("res://assets/characters/walker/walker.tscn").instantiate()
	add_child(w)
	sk = w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var r := sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin - sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin
	print("rest toe pitch %.1f°" % rad_to_deg(atan2(r.y, Vector2(r.x, r.z).length())))
	var trb := sk.get_bone_global_rest(sk.find_bone("LeftToes")).basis.orthonormalized() * Vector3.UP
	print("rest toe-seg dir (skel space) ", trb)
	for spd in [0.0, 1.3]:
		w.set_motion(spd, 0.0)
		for i in 60: await get_tree().process_frame
		acc = {}
		sk.skeleton_updated.connect(_grab)
		for i in 90: await get_tree().process_frame
		sk.skeleton_updated.disconnect(_grab)
		var out := "speed %.1f:" % spd
		# toe pitch when that foot is planted (lowest 25% of foot heights)
		for side in ["Left", "Right"]:
			var ys: Array = acc[side + "_foot_y"]
			var sorted := ys.duplicate(); sorted.sort()
			var thr: float = sorted[int(sorted.size() * 0.25)]
			var tp := 0.0; var c := 0
			for j in ys.size():
				if ys[j] <= thr:
					tp += acc[side + "_toe_pitch"][j]; c += 1
			var ts := 0.0
			for j in ys.size():
				if ys[j] <= thr:
					ts += acc[side + "_toeseg_pitch"][j]
			out += " %s planted foot %.1f° toe-seg %.1f°" % [side, tp / max(c, 1), ts / max(c, 1)]
		var pu: Array = acc["pelvis_up"]
		out += "  pelvis up-axis lean %.1f° (+fwd)" % (pu.reduce(func(a, b): return a + b) / pu.size())
		print(out)
	get_tree().quit()
