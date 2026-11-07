extends Node3D
## Reference implementation of the character-visual contract (docs/CONTRACTS.md §1).
## A crude procedurally-animated mannequin used until the real character exists.

var _speed := 0.0
var _run := 0.0
var _stopped := false
var _raise := 0.0
var _tilt := 0.0
var _droop := 0.0
var _wet := 0.0
var _mood: StringName = &"normal"
var _phase := 0.0
var _t := 0.0

var _body: Node3D
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _legs: Array[Node3D] = []
var _arm_l: Node3D
var _arm_r: Node3D
var _grip_l: Node3D
var _grip_r: Node3D
var _cloth_mat := StandardMaterial3D.new()
var _skin_mat := StandardMaterial3D.new()


func _ready() -> void:
	_cloth_mat.albedo_color = Color(0.32, 0.3, 0.27)
	_cloth_mat.roughness = 0.85
	_skin_mat.albedo_color = Color(0.78, 0.6, 0.5)
	_body = Node3D.new()
	add_child(_body)
	_torso = _mesh(CapsuleMesh.new(), _cloth_mat)
	(_torso.mesh as CapsuleMesh).radius = 0.2
	(_torso.mesh as CapsuleMesh).height = 0.7
	_torso.position = Vector3(0, 1.25, 0)
	_body.add_child(_torso)
	_head = _mesh(SphereMesh.new(), _skin_mat)
	(_head.mesh as SphereMesh).radius = 0.12
	(_head.mesh as SphereMesh).height = 0.26
	_head.position = Vector3(0, 1.66, 0)
	_body.add_child(_head)
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(0, 0.92, 0.1 * side)
		_body.add_child(hip)
		var leg := _mesh(CapsuleMesh.new(), _cloth_mat)
		(leg.mesh as CapsuleMesh).radius = 0.08
		(leg.mesh as CapsuleMesh).height = 0.92
		leg.position = Vector3(0, -0.46, 0)
		hip.add_child(leg)
		_legs.append(hip)
	_arm_l = _make_arm(-1)
	_arm_r = _make_arm(1)
	_grip_l = Node3D.new()
	_grip_l.position = Vector3(0, -0.62, 0)
	_grip_l.rotation = Vector3(0, 0, PI)  # +Y points down when the arm hangs
	_arm_l.add_child(_grip_l)
	_grip_r = Node3D.new()
	_grip_r.position = Vector3(0, -0.62, 0)
	_grip_r.rotation = Vector3(0, 0, PI)
	_arm_r.add_child(_grip_r)


func _make_arm(side: int) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(0, 1.48, 0.25 * side)
	_body.add_child(shoulder)
	var arm := _mesh(CapsuleMesh.new(), _cloth_mat)
	(arm.mesh as CapsuleMesh).radius = 0.06
	(arm.mesh as CapsuleMesh).height = 0.62
	arm.position = Vector3(0, -0.31, 0)
	shoulder.add_child(arm)
	return shoulder


func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return mi


func _process(delta: float) -> void:
	_t += delta
	var stride := lerpf(1.4, 2.2, _run)
	if not _stopped:
		_phase += delta * _speed / maxf(stride * 0.5, 0.01) * PI
	var swing := 0.0 if _stopped else lerpf(0.45, 0.8, _run) * clampf(_speed / 1.2, 0.0, 1.3)
	_legs[0].rotation.z = sin(_phase) * swing
	_legs[1].rotation.z = -sin(_phase) * swing
	var bob := absf(sin(_phase)) * 0.04 * swing
	var slump := 0.35 if _mood == &"sad" else 0.0
	_body.position.y = bob - slump * 0.05
	_body.rotation.z = -lerpf(0.0, 0.25, _run) + slump * 0.4 * -1.0
	_head.position = Vector3(0.0 + slump * 0.08, 1.66 - slump * 0.06, 0)
	_arm_l.rotation.z = -sin(_phase) * swing * 0.6
	# Right arm: swing when lowered, raised overhead when holding the open umbrella.
	var sway := sin(_t * 3.1) * 0.25 * _droop
	var raised := PI - 0.15 - _droop * 0.5
	_arm_r.rotation.z = lerpf(sin(_phase) * swing * 0.6, raised, _raise) + sway * _raise
	# Grip: when raised, make +Y point up (canopy direction) then apply tilt.
	_grip_r.rotation.z = -_arm_r.rotation.z - _tilt
	var dark := lerpf(1.0, 0.55, _wet)
	_cloth_mat.albedo_color = Color(0.32, 0.3, 0.27) * dark
	_cloth_mat.roughness = lerpf(0.85, 0.35, _wet)


func set_motion(speed_mps: float, run_amount: float) -> void:
	_speed = speed_mps
	_run = run_amount


func set_stopped(stopped: bool) -> void:
	_stopped = stopped


func set_umbrella_pose(raise: float, tilt: float, droop: float) -> void:
	_raise = raise
	_tilt = tilt
	_droop = droop


func set_wetness(w: float) -> void:
	_wet = clampf(w, 0.0, 1.0)


func set_mood(mood: StringName) -> void:
	_mood = mood


func get_grip(hand: StringName) -> Node3D:
	return _grip_r if hand == &"right" else _grip_l
