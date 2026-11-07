extends Node
## Measures where the walker's torso/head sit relative to his feet, AFTER the pose modifier.
var sk: Skeleton3D
var w: Node3D
var acc := {}
var count := 0
const NAMES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftFoot", "RightFoot"]

var _miny := 9.0
func _grab() -> void:
	for f in ["LeftToes", "RightToes", "LeftFoot", "RightFoot"]:
		_miny = minf(_miny, w.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone(f)).origin)).y)
	for n in NAMES:
		var p := w.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone(n)).origin))
		acc[n] = acc.get(n, Vector3.ZERO) + p
	count += 1

func _ready() -> void:
	w = load("res://assets/characters/walker/walker.tscn").instantiate()
	add_child(w)
	sk = w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	for mode in ["walk", "hold", "run"]:
		w.set_motion(3.0 if mode == "run" else (1.0 if mode == "hold" else 1.3), 1.0 if mode == "run" else 0.0)
		w.set_umbrella_pose(1.0 if mode == "hold" else 0.0, 0.0, 0.0)
		for i in 90: await get_tree().process_frame
		acc = {}
		count = 0
		sk.skeleton_updated.connect(_grab)
		for f in 60: await get_tree().process_frame
		sk.skeleton_updated.disconnect(_grab)
		var feet: Vector3 = (acc["LeftFoot"] + acc["RightFoot"]) * 0.5 / count
		var line: String = String(mode) + ":"
		for n in NAMES.slice(0, 6):
			var p: Vector3 = acc[n] / count
			line += "  %s x=%+.3f y=%.2f" % [n, p.x - feet.x, p.y]
		var hip: Vector3 = acc["Hips"] / count
		var nk: Vector3 = acc["Neck"] / count
		var hd: Vector3 = acc["Head"] / count
		line += "  | torso lean %.1f°  neck lean %.1f°" % [rad_to_deg(atan2(nk.x - hip.x, nk.y - hip.y)), rad_to_deg(atan2(hd.x - nk.x, hd.y - nk.y))]
		print(line)
		print("   feet min y: %.3f" % _miny)
		_miny = 9.0
	get_tree().quit()
