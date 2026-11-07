extends SceneTree
## Builds a looping Animation resource from tools/mocap/retarget.py JSON output.
## godot --headless --path . -s res://tools/mocap/build_anim.gd -- IN.json res://OUT.res
func _initialize():
	var args := OS.get_cmdline_user_args()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var out: String = args[1]
	var a := Animation.new()
	var length: float = d["length"]
	var n: int = (d["hips_pos"] as Array).size()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR
	a.step = 1.0 / float(d["fps"])
	var tp := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(tp, NodePath("%GeneralSkeleton:Hips"))
	for i in n:
		var p: Array = d["hips_pos"][i]
		a.position_track_insert_key(tp, length * i / n, Vector3(p[0], p[1], p[2]))
	var rot: Dictionary = d["rot"]
	for bone in rot:
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, NodePath("%GeneralSkeleton:" + bone))
		var keys: Array = rot[bone]
		for i in n:
			var q: Array = keys[i]
			a.rotation_track_insert_key(tr, length * i / n, Quaternion(q[0], q[1], q[2], q[3]).normalized())
	var err := ResourceSaver.save(a, out)
	print("saved ", out, " err=", err, " len=", length, " keys=", n)
	quit()
