extends SceneTree
## Foot-skate check: moves the walker at several speeds and reports the world-space x-velocity of
## the planted foot, sampled after the pose modifier (should be ~0).
##   godot --headless --fixed-fps 120 --path . -s res://tools/mocap/skate_check.gd
var w: Node3D
var skel: Skeleton3D
var feet: Array
var toes: Array
var samples := []

func _grab() -> void:
	var cur := []
	for k in 2:
		var pf := skel.to_global(skel.get_bone_global_pose(feet[k]).origin)
		var pt := skel.to_global(skel.get_bone_global_pose(toes[k]).origin)
		cur.append(pt if pt.y < pf.y else pf)
	samples.append(cur)

func _initialize():
	w = load("res://assets/characters/walker/walker.tscn").instantiate()
	root.add_child(w)
	await process_frame
	skel = w.find_child("GeneralSkeleton", true, false)
	feet = [skel.find_bone("LeftFoot"), skel.find_bone("RightFoot")]
	toes = [skel.find_bone("LeftToes"), skel.find_bone("RightToes")]
	var args := OS.get_cmdline_user_args()
	var mood: StringName = &"sad" if args.has("sad") else &"normal"
	w.set_mood(mood)
	for sp in [0.8, 1.0, 1.3, 1.6, 2.0, 2.6, 3.2]:
		w.set_motion(sp, clampf((sp - 1.3) / 1.9, 0.0, 1.0))
		for i in 240:
			await process_frame
			w.position.x += sp / 120.0
		samples = []
		skel.skeleton_updated.connect(_grab)
		for i in 360:
			await process_frame
			w.position.x += sp / 120.0
		skel.skeleton_updated.disconnect(_grab)
		var mins := [9.0, 9.0]
		for c in samples:
			for k in 2: mins[k] = minf(mins[k], c[k].y)
		var v := []
		for i in range(1, samples.size()):
			for k in 2:
				if samples[i][k].y < mins[k] + 0.015 and samples[i - 1][k].y < mins[k] + 0.015:
					v.append((samples[i][k].x - samples[i - 1][k].x) * 120.0)
		v.sort()
		print("%s speed %.1f  planted-foot x-velocity p25 %+.2f  median %+.2f  p75 %+.2f m/s (n=%d)" % [mood, sp, v[v.size() / 4], v[v.size() / 2], v[3 * v.size() / 4], v.size()])
	quit()
