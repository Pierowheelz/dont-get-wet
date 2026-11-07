extends SceneTree
# Measures natural ground speed and foot phase of each locomotion clip on the walker skeleton.
func _initialize():
	var model: Node3D = load("res://assets/characters/walker/walker_model.glb").instantiate()
	root.add_child(model)
	await process_frame
	print("in tree ", model.is_inside_tree(), " skel ", model.get_node_or_null("%GeneralSkeleton"))
	var skel: Skeleton3D = model.find_child("GeneralSkeleton", true, false)
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.root_node = ap.get_path_to(model)
	var lib := AnimationLibrary.new()
	for n in ["idle", "walk", "walk_formal", "jog", "sprint"]:
		lib.add_animation(n, load("res://assets/characters/walker/anim/%s.res" % n))
	ap.add_animation_library("", lib)
	var lf := skel.find_bone("LeftFoot"); var rf := skel.find_bone("RightFoot")
	var lt := skel.find_bone("LeftToes"); var rt := skel.find_bone("RightToes")
	print("rest hand_r global: ", skel.get_bone_global_rest(skel.find_bone("RightHand")))
	print("rest upperarm_r global: ", skel.get_bone_global_rest(skel.find_bone("RightUpperArm")))
	print("rest lowerarm_r global: ", skel.get_bone_global_rest(skel.find_bone("RightLowerArm")))
	print("rest thumb1_r: ", skel.get_bone_global_rest(skel.find_bone("RightThumbMetacarpal")).origin, " little1_r ", skel.get_bone_global_rest(skel.find_bone("RightLittleProximal")).origin, " mid1_r ", skel.get_bone_global_rest(skel.find_bone("RightMiddleProximal")).origin)
	print("rest head ", skel.get_bone_global_rest(skel.find_bone("Head")).origin, " upperchest ", skel.get_bone_global_rest(skel.find_bone("UpperChest")).origin)
	print("skel xform ", skel.global_transform, " motion_scale ", skel.motion_scale)
	for n in ["walk", "jog", "sprint", "idle"]:
		ap.play(n)
		var a := ap.get_animation(n)
		var N := 400
		var dt := a.length / N
		var ys := {lf: [], rf: []}
		var zs := {lf: [], rf: []}
		for i in N + 1:
			ap.seek(i * dt, true)
			for b in [lf, rf]:
				var p := skel.get_bone_global_pose(b).origin
				ys[b].append(p.y); zs[b].append(p.z)
		var out := ""
		for b in [lf, rf]:
			var miny: float = ys[b].min()
			var tot := 0.0; var cnt := 0; var first := -1; var last := -1
			for i in N:
				if ys[b][i] < miny + 0.03 and ys[b][i + 1] < miny + 0.03:
					tot += -(zs[b][i + 1] - zs[b][i]) / dt; cnt += 1
					if first < 0: first = i
					last = i
			out += " %s miny=%.3f contact_speed=%.3f contact_frac=%.2f first=%.3f last=%.3f" % [skel.get_bone_name(b), miny, tot / maxf(cnt, 1), float(cnt) / N, first / float(N), last / float(N)]
		print(n, " len=%.3f" % a.length, out)
	quit()
