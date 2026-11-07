extends SceneTree
## Dumps a skeleton's rest pose to JSON for tools/mocap/retarget.py.
## godot --headless --path . -s res://tools/mocap/dump_rest.gd -- SCENE.tscn OUT.json
func _initialize():
	var args := OS.get_cmdline_user_args()
	var scene: String = args[0] if args.size() > 0 else "res://assets/characters/walker/walker.tscn"
	var out: String = args[1] if args.size() > 1 else "user://rest.json"
	var w: Node = load(scene).instantiate()
	root.add_child(w)
	var sk: Skeleton3D = w.find_child("GeneralSkeleton", true, false)
	var bones := []
	for b in sk.get_bone_count():
		var g := sk.get_bone_global_rest(b)
		var l := sk.get_bone_rest(b)
		bones.append({"name": sk.get_bone_name(b), "parent": sk.get_bone_parent(b),
			"g_basis": [g.basis.x.x, g.basis.x.y, g.basis.x.z, g.basis.y.x, g.basis.y.y, g.basis.y.z, g.basis.z.x, g.basis.z.y, g.basis.z.z],
			"g_origin": [g.origin.x, g.origin.y, g.origin.z],
			"l_quat": [l.basis.get_rotation_quaternion().x, l.basis.get_rotation_quaternion().y, l.basis.get_rotation_quaternion().z, l.basis.get_rotation_quaternion().w],
			"l_origin": [l.origin.x, l.origin.y, l.origin.z]})
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"motion_scale": sk.motion_scale, "bones": bones}))
	f.close()
	print("wrote ", out)
	quit()
