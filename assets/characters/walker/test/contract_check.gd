extends SceneTree
## Headless check of the CONTRACTS.md §1 API: grip heights/orientations, 180° turn, all calls.
func _initialize():
	var w: Node3D = load("res://assets/characters/walker/walker.tscn").instantiate()
	var gr: Node3D = w.get_grip(&"right")  # before entering the tree
	var gl: Node3D = w.get_grip(&"left")
	root.add_child(w)
	w.position = Vector3(5, 0, 1.6)
	for yaw in [0.0, PI]:
		w.rotation.y = yaw
		w.set_motion(1.3, 0.0); w.set_stopped(false); w.set_mood(&"normal"); w.set_wetness(0.5)
		for tilt in [0.0, 0.85, -0.85]:
			w.set_umbrella_pose(1.0, tilt, 0.0)
			var hs := []
			for i in 40:
				await process_frame
				hs.append(gr.global_position.y)
			var fwd := w.global_transform.basis.x
			var up := gr.global_transform.basis.y
			print("yaw=%.2f tilt=%+.2f grip_r y=[%.3f..%.3f] fwd_offset=%.3f up=%s up·fwd=%+.2f | grip_l y=%.3f up=%s" % [yaw, tilt, hs.min(), hs.max(), (gr.global_position - w.global_position).dot(fwd), up.snappedf(0.01), up.dot(fwd), gl.global_position.y, gl.global_transform.basis.y.snappedf(0.01)])
	w.set_umbrella_pose(1.0, 0.0, 1.0); w.set_motion(3.2, 1.0)
	for i in 20: await process_frame
	w.set_stopped(true); w.set_motion(0.0, 0.0)
	for i in 20: await process_frame
	w.set_stopped(false); w.set_mood(&"sad"); w.set_motion(0.8, 0.0); w.set_umbrella_pose(0.0, 0.0, 0.0)
	for i in 20: await process_frame
	print("api ok; feet min y = ", _min_foot(w))
	quit()
func _min_foot(w: Node3D) -> float:
	var s: Skeleton3D = w.find_child("GeneralSkeleton", true, false)
	var m := 9.0
	for b in ["LeftToes", "RightToes", "LeftFoot", "RightFoot"]:
		m = minf(m, s.to_global(s.get_bone_global_pose(s.find_bone(b)).origin).y)
	return m
