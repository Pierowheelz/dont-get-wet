extends Node
var sk: Skeleton3D
var w: Node3D
var mins := {}
var samples := []
func _grab() -> void:
	var row := []
	for side in ["Left", "Right"]:
		var h := sk.get_bone_global_pose(sk.find_bone(side + "UpperLeg")).origin
		var k := sk.get_bone_global_pose(sk.find_bone(side + "LowerLeg")).origin
		var a := sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin
		row.append(rad_to_deg((k - h).angle_to(a - k)))
		row.append(w.to_local(sk.to_global(a)).y)
	samples.append(row)
func _ready() -> void:
	w = load("res://assets/characters/walker/walker.tscn").instantiate()
	add_child(w)
	sk = w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	for spd in [1.0, 1.3, 2.0, 3.0]:
		w.set_motion(spd, clampf((spd - 1.3) / 1.9, 0.0, 1.0))
		for i in 60: await get_tree().process_frame
		samples = []
		sk.skeleton_updated.connect(_grab)
		for i in 90: await get_tree().process_frame
		sk.skeleton_updated.disconnect(_grab)
		# stance = foot near its lowest; report knee flexion there
		var out := "speed %.1f:" % spd
		for s in 2:
			var lows := samples.map(func(r): return r[s * 2 + 1])
			var mn: float = lows.min()
			var stance_knees := []
			for r in samples:
				if r[s * 2 + 1] < mn + 0.01:
					stance_knees.append(r[s * 2])
			stance_knees.sort()
			out += "  %s stance knee: min %.0f° median %.0f°" % [["L", "R"][s], stance_knees[0], stance_knees[stance_knees.size() / 2]]
		print(out)
	get_tree().quit()
