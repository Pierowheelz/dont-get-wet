extends Node3D
## Visual test for pedestrians. Args after --:
##   mode=lineup (all peds in a row, walking in place / standing)   mode=street (walkers move, camera pans)
##   ped=<id> follow one ped (side camera)    cam=side|three
var mode := "lineup"
var only := ""
var cam_mode := "side"
var cam: Camera3D
var peds: Array = []
var t := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="): mode = a.substr(5)
		if a.begins_with("ped="): only = a.substr(4)
		if a.begins_with("cam="): cam_mode = a.substr(4)
	_rainy_world()
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/pedestrians/peds.json"))
	var x := 0.0
	var i := 0
	for e in manifest:
		if only != "" and e.id != only:
			continue
		var p: Node3D = load(e.scene).instantiate()
		add_child(p)
		p.position = Vector3(x, 0, 1.6 if e.kind == "walker" else 0.7)
		p.setup(1234 + i * 77)
		var spd: float = p.suggested_speed if e.kind == "walker" else 0.0
		p.set_walking(spd)
		peds.append({"node": p, "speed": spd if mode != "lineup" else 0.0, "id": e.id})
		var l := Label3D.new()
		l.text = e.id
		l.pixel_size = 0.004
		l.position = Vector3(x, 2.35, 1.6)
		l.modulate = Color(1, 1, 0.6)
		add_child(l)
		x += 1.9
		i += 1
	cam = Camera3D.new()
	cam.fov = 38
	add_child(cam)
	cam.make_current()

func _rainy_world() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.13, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.47, 0.6)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.3, 0.35, 0.42)
	e.fog_density = 0.02
	e.ssr_enabled = true
	var we := WorldEnvironment.new(); we.environment = e; add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 20, 0)
	key.light_color = Color(0.7, 0.78, 0.9)
	key.light_energy = 0.7
	key.shadow_enabled = true
	add_child(key)
	var shop := OmniLight3D.new()  # warm shop-window spill
	shop.light_color = Color(1.0, 0.75, 0.45)
	shop.light_energy = 2.5
	shop.omni_range = 9.0
	shop.position = Vector3(4, 2.2, 0.3)
	add_child(shop)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(200, 8); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.16, 0.16, 0.17); gm.roughness = 0.12; gm.metallic_specular = 0.6
	ground.material_override = gm
	ground.position = Vector3(60, 0, 2)
	add_child(ground)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(200, 6, 0.2); wall.mesh = bm
	var wm := StandardMaterial3D.new(); wm.albedo_color = Color(0.35, 0.22, 0.18); wm.roughness = 0.9
	wall.material_override = wm
	wall.position = Vector3(60, 3, -0.1)
	add_child(wall)
	for k in 40:  # 1 m ticks
		var m := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = Vector3(0.02, 0.004, 0.3); m.mesh = b
		var mm := StandardMaterial3D.new(); mm.albedo_color = Color(0.7, 0.65, 0.3); m.material_override = mm
		m.position = Vector3(k - 4, 0.002, 2.3); add_child(m)
	var rain := CPUParticles3D.new()
	rain.amount = 1500
	rain.lifetime = 0.9
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(12, 0.2, 3)
	rain.position = Vector3(6, 6, 2)
	rain.direction = Vector3.DOWN
	rain.spread = 2.0
	rain.initial_velocity_min = 7.0
	rain.initial_velocity_max = 8.0
	rain.gravity = Vector3(0, -2, 0)
	var q := QuadMesh.new(); q.size = Vector2(0.008, 0.35)
	var qm := StandardMaterial3D.new(); qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; qm.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = qm
	rain.mesh = q
	add_child(rain)

func _process(delta: float) -> void:
	t += delta
	var cx := 0.0
	for p in peds:
		p.node.position.x += p.speed * delta
		cx += p.node.position.x
	cx /= maxf(peds.size(), 1)
	if only != "":
		cx = peds[0].node.position.x
		if cam_mode == "three":
			cam.position = Vector3(cx + 2.2, 1.5, 4.6)
			cam.look_at(Vector3(cx, 1.0, 1.6))
		else:
			cam.position = Vector3(cx + 0.2, 1.1, 5.6)
			cam.look_at(Vector3(cx + 0.2, 0.95, 1.6))
	else:
		cam.position = Vector3(cx, 1.5, 13.5)
		cam.look_at(Vector3(cx, 1.0, 1.2))
