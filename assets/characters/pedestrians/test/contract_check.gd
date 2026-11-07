extends SceneTree
## Headless check of every pedestrian in peds.json: contract methods, kind, feet height, face count.
func _initialize():
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/pedestrians/peds.json"))
	for e in manifest:
		var p: Node3D = load(e.scene).instantiate()
		root.add_child(p)
		p.rotation.y = PI  # walking left
		await process_frame
		assert(p.has_method("setup") and p.has_method("set_walking"))
		p.setup(42)
		p.set_walking(1.2 if e.kind == "walker" else 0.0)
		for i in 30: await process_frame
		var miny := 9.0
		var faces := 0
		for s in p.find_children("*", "Skeleton3D", true, false):
			for b in ["LeftToes", "RightToes", "LeftFoot", "RightFoot"]:
				miny = minf(miny, s.to_global(s.get_bone_global_pose(s.find_bone(b)).origin).y)
		for m in p.find_children("*", "MeshInstance3D", true, false):
			if m.mesh is ArrayMesh and m.get_parent() is Skeleton3D:
				for si in m.mesh.get_surface_count():
					faces += m.mesh.surface_get_array_index_len(si) / 3
		print("%-12s kind=%s/%s umbrella=%s min_foot_y=%.3f faces=%d" % [e.id, p.kind, e.kind, e.umbrella, miny, faces])
		p.queue_free()
	quit()
