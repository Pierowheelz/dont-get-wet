extends Node3D
## Visual test for the walker: side-on camera at +Z looking -Z (like the game), scripted timeline.
## Args (after --): cam=side|front|three|close   from=<seconds to skip>   wet=<0..1>

var walker: Node3D
var cam: Camera3D
var t := 0.0
var mode := "side"
var skip := 0.0
var label: Label

const TIMELINE := [
	# t_end, speed, run, raise, tilt, droop, stopped, mood, title
	[2.0, 1.3, 0.0, 0.0, 0.0, 0.0, false, &"normal", "walk"],
	[3.5, 1.15, 0.0, -1.0, 0.0, 0.0, false, &"normal", "raise"],
	[4.5, 1.15, 0.0, 1.0, 0.0, 0.0, false, &"normal", "hold"],
	[5.5, 1.15, 0.0, 1.0, 0.85, 0.0, false, &"normal", "tilt fwd"],
	[6.5, 1.15, 0.0, 1.0, -0.85, 0.0, false, &"normal", "tilt back"],
	[8.0, 1.0, 0.0, 1.0, 0.0, 1.0, false, &"normal", "droop"],
	[9.5, 3.2, 1.0, 0.0, 0.0, 0.0, false, &"normal", "run"],
	[10.5, 0.0, 0.0, 0.0, 0.0, 0.0, true, &"normal", "stopped"],
	[12.5, 0.8, 0.0, 0.0, 0.0, 0.0, false, &"sad", "sad walk"],
]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cam="): mode = a.substr(4)
		if a.begins_with("from="): skip = float(a.substr(5))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.36, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -150, 0)
	fill.light_energy = 0.4
	add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 8)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.25, 0.27)
	gm.roughness = 0.4
	ground.material_override = gm
	ground.position = Vector3(80, 0, 1.6)
	add_child(ground)
	# 1 m tick marks along the walk line to judge foot sliding / heights.
	for i in 120:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.005, 0.5)
		m.mesh = bm
		m.position = Vector3(i - 5, 0.003, 1.6)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.9, 0.85, 0.3)
		m.material_override = mm
		add_child(m)
	# Height reference pole at 2.0 m / 1.5 m marks, travels with the walker (behind).
	walker = load("res://assets/characters/walker/walker.tscn").instantiate()
	walker.position = Vector3(0, 0, 1.6)
	add_child(walker)
	_attach_umbrella(walker.get_grip(&"right"), true)
	_attach_umbrella(walker.get_grip(&"left"), false)
	cam = Camera3D.new()
	cam.fov = 35
	add_child(cam)
	cam.make_current()
	label = Label.new()
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override(&"font_size", 40)
	add_child(label)
	if skip > 0.0:
		var dt := 1.0 / 30.0
		while t < skip:
			_step(dt)

var _open_umb: Node3D
func _attach_umbrella(grip_node: Node3D, open: bool) -> void:
	var grip := Node3D.new()
	grip_node.add_child(grip)
	if open: _open_umb = grip
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.008
	cm.height = 0.75 if open else 0.78
	shaft.mesh = cm
	shaft.position = Vector3(0, cm.height * 0.5 - 0.05, 0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.1, 0.1)
	shaft.material_override = sm
	grip.add_child(shaft)
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.016
	hm.bottom_radius = 0.016
	hm.height = 0.12
	handle.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.45, 0.25, 0.1)
	handle.material_override = hmat
	grip.add_child(handle)
	var canopy := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	if open:
		cone.bottom_radius = 0.55
		cone.height = 0.28
		canopy.position = Vector3(0, 0.75 - 0.14 - 0.05, 0)
	else:
		cone.bottom_radius = 0.05
		cone.top_radius = 0.0
		cone.height = 0.5
		canopy.position = Vector3(0, 0.45, 0)
	canopy.mesh = cone
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.7, 0.12, 0.1) if open else Color(0.15, 0.15, 0.4)
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	canopy.material_override = cmat
	grip.add_child(canopy)
	# Axis gizmo: +Y green stub at the palm.
	var ax := MeshInstance3D.new()
	var axm := BoxMesh.new()
	axm.size = Vector3(0.01, 0.01, 0.06)
	ax.mesh = axm
	ax.position = Vector3(0, 0, 0.03)
	var axmat := StandardMaterial3D.new()
	axmat.albedo_color = Color(0.1, 0.3, 1.0)
	ax.material_override = axmat
	grip.add_child(ax)

func _process(delta: float) -> void:
	_step(delta)

var _raise := 0.0
var _seg_start := 0.0
func _step(dt: float) -> void:
	t += dt
	var seg: Array = TIMELINE[-1]
	var seg_start := 0.0
	for s in TIMELINE:
		if t < s[0]:
			seg = s
			break
		seg_start = s[0]
	var raise: float = seg[3]
	if raise < 0.0:
		raise = clampf((t - seg_start) / (seg[0] - seg_start), 0.0, 1.0)
	walker.set_motion(seg[1], seg[2])
	walker.set_stopped(seg[6])
	walker.set_mood(seg[7])
	walker.set_umbrella_pose(raise, seg[4], seg[5])
	walker.set_wetness(clampf((t - 7.0) / 3.0, 0.0, 1.0))
	if _open_umb: _open_umb.visible = raise > 0.02
	if dt > 0.0 and walker.has_method("_apply_params") and not is_processing():
		walker._apply_params(dt)
	walker.position.x += seg[1] * dt
	var target := walker.global_position
	match mode:
		"front":
			cam.position = target + Vector3(3.6, 1.1, 0.4)
			cam.look_at(target + Vector3(0, 1.0, 0))
		"three":
			cam.position = target + Vector3(2.4, 1.5, 3.0)
			cam.look_at(target + Vector3(0, 1.1, 0))
		"close":
			cam.position = target + Vector3(0.3, 1.45, 2.0)
			cam.look_at(target + Vector3(0.1, 1.45, 0))
		_:
			cam.position = Vector3(target.x + 0.4, 1.2, target.z + 5.5)
			cam.look_at(Vector3(target.x + 0.4, 1.05, target.z))
	if label:
		label.text = "%s  t=%.1f" % [seg[8], t]
	if absf(t - 4.2) < dt * 0.5 + 0.001 or absf(t - 4.6) < dt * 0.5 + 0.001:
		var g: Node3D = walker.get_grip(&"right")
		var lp := walker.to_local(g.global_position)
		print("GRIP_R t=%.2f local=%s up=%s" % [t, lp, (walker.global_transform.basis.inverse() * g.global_transform.basis.y).normalized()])
		var gl: Node3D = walker.get_grip(&"left")
		print("GRIP_L local=%s up=%s" % [walker.to_local(gl.global_position), (walker.global_transform.basis.inverse() * gl.global_transform.basis.y).normalized()])
