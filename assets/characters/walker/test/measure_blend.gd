extends SceneTree
## Measures metres per gait cycle of the walker's walk/brisk/jog blend at several gait positions
## (planted-foot backward speed while the tree runs at exactly 1 cycle per second).
func _initialize():
	var w: Node3D = load("res://assets/characters/walker/walker.tscn").instantiate()
	root.add_child(w)
	await process_frame
	var tree: AnimationTree = w.get_node("AnimationTree")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	w.set_process(false)
	var skel: Skeleton3D = w.find_child("GeneralSkeleton", true, false)
	var feet := [skel.find_bone("LeftFoot"), skel.find_bone("RightFoot")]
	var toes := [skel.find_bone("LeftToes"), skel.find_bone("RightToes")]
	var out := []
	for jw in [0.0, 0.25, 0.5, 0.75, 1.0]:
		tree.set(&"parameters/gait/blend_position", jw)
		tree.set(&"parameters/ts/scale", 1.0)
		tree.set(&"parameters/stop/blend_amount", 0.0)
		var N := 200
		var dt := 1.0 / N
		for i in N: tree.advance(dt)  # settle
		var ys := [[], []]; var xs := [[], []]
		for i in N + 1:
			tree.advance(dt)
			for k in 2:
				var pf := w.to_local(skel.to_global(skel.get_bone_global_pose(feet[k]).origin))
				var pt := w.to_local(skel.to_global(skel.get_bone_global_pose(toes[k]).origin))
				ys[k].append(minf(pf.y, pt.y)); xs[k].append(pt.x if pt.y < pf.y else pf.x)
		var speeds := []
		for k in 2:
			var miny: float = ys[k].min()
			for i in N:
				if ys[k][i] < miny + 0.02 and ys[k][i + 1] < miny + 0.02:
					speeds.append(-(xs[k][i + 1] - xs[k][i]) / dt)
		speeds.sort()
		var med: float = speeds[speeds.size() / 2] if speeds.size() > 0 else 0.0
		out.append(snappedf(med, 0.01))
		print("gait=%.2f  m/cycle=%.3f  samples=%d  p25=%.2f p75=%.2f" % [jw, med, speeds.size(), speeds[speeds.size() / 4], speeds[3 * speeds.size() / 4]])
	print("CYCLE_M := ", out)
	quit()
