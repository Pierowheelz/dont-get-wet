extends SceneTree
## Renders a side-view filmstrip of one raw Animation on the walker model (no AnimationTree,
## no procedural layer).  godot --path . --resolution 1800x500 -s res://tools/mocap/filmstrip.gd -- ANIM.res OUT.png [frames=8] [view=side|front]
var _a: Animation
var _skel: Skeleton3D
var _model: Node3D
var _out := ""
var _n := 8
var _view := "side"
var _vps: Array[SubViewport] = []
var _frame := 0

func _initialize():
	var args := OS.get_cmdline_user_args()
	_a = load(args[0]); _out = args[1]
	for x in args.slice(2):
		if x.begins_with("frames="): _n = int(x.substr(7))
		if x.begins_with("view="): _view = x.substr(5)
	var w: Node3D = load("res://assets/characters/walker/walker.tscn").instantiate()
	root.add_child(w)
	await process_frame
	var tree: AnimationTree = w.get_node("AnimationTree")
	tree.active = false
	w.set_process(false)
	_skel = w.find_child("GeneralSkeleton", true, false)
	var mod = _skel.get_node("PoseModifier")
	mod.active = false
	_model = w.get_node("Model")
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	var player := AnimationPlayer.new()
	_model.add_child(player)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"a", _a)
	player.add_animation_library(&"", lib)
	player.root_node = player.get_path_to(_model)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(&"a")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.33, 0.36, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); root.add_child(sun)
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); g.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.22, 0.22, 0.24); g.material_override = gm
	root.add_child(g)
	for i in 41:
		var m := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.01, 0.004, 3.0); m.mesh = bm
		m.position = Vector3(0, 0.002, -2.0 + i * 0.1); m.rotation_degrees.y = 90; var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.8, 0.75, 0.3) if i % 5 == 0 else Color(0.45, 0.45, 0.4); m.material_override = mm
		root.add_child(m)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.1
	if _view == "front":
		cam.position = Vector3(0, 0.95, 4)
	else:
		cam.position = Vector3(4, 0.95, 0); cam.rotation_degrees = Vector3(0, 90, 0)
	root.add_child(cam)
	cam.make_current()
	var imgs: Array[Image] = []
	for k in _n:
		player.seek(_a.length * k / _n, true)
		player.advance(0)
		await process_frame
		await RenderingServer.frame_post_draw
		var im := root.get_viewport().get_texture().get_image()
		var w2 := im.get_width(); var h2 := im.get_height()
		imgs.append(im.get_region(Rect2i(int(w2 * 0.5 - h2 * 0.32), 0, int(h2 * 0.64), h2)))
	var tw := imgs[0].get_width(); var th := imgs[0].get_height()
	var sheet := Image.create(tw * _n, th, false, imgs[0].get_format())
	for k in _n:
		sheet.blit_rect(imgs[k], Rect2i(0, 0, tw, th), Vector2i(k * tw, 0))
	sheet.save_png(_out)
	print("saved ", _out)
	quit()
