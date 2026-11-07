extends Node3D
## Visual test bench for the environment kit: lays out a street from kit.json + props.json under a
## rainy-dusk light setup and pans a camera along it (one stop per rendered frame).
##
##   godot --path . --write-movie /tmp/kit/frame.png --fixed-fps 5 --quit-after 10 \
##         res://assets/buildings/test/kit_preview.tscn
##
## Optional user args (after `--`): --start=X  --step=M  --cam_y=1.6  --cam_z=9  --fov=55  --warmup=1
##   --shot=props   frames the prop line-up / car instead of the street.

const KIT := "res://assets/buildings/kit.json"
const PROPS := "res://assets/props/props.json"
const SIGN_DIR := "res://assets/textures/signs/"

# Street layout: [ground id, [upper ids...], cap id, sign texture or ""]
const STREET := [
	["filler_pilaster_g_05", ["filler_pilaster_u_05", "filler_pilaster_u_05"], "", ""],
	["shop_lit_6a", ["upper_6a", "upper_6b"], "cap_cornice_6", "sign_diner"],
	["filler_downpipe_g_06", ["filler_downpipe_u_06", "filler_downpipe_u_06"], "", ""],
	["shuttered_4a", ["upper_4c"], "cap_parapet_4", "sign_hardware"],
	["shop_dark_5a", ["upper_5d", "upper_5a"], "cap_cornice_5", "sign_for_lease"],
	["boarded_4a", ["upper_4d"], "cap_flat_4", ""],
	["shop_lit_3a", ["upper_3a", "upper_3e"], "cap_cornice_3", "sign_barber"],
	["doorway_3a", ["upper_3b", "upper_3c"], "cap_parapet_3", ""],
	["shop_lit_5a", ["upper_5b"], "cap_parapet_5", "sign_laundromat"],
	["filler_alley_g_10", [], "", ""],
	["shuttered_6a", ["upper_6c", "upper_6d"], "cap_parapet_6", "sign_shoe_repair"],
	["shop_lit_4a", ["upper_4e", "upper_4a"], "cap_cornice_4", "sign_pawn"],
	["wall_4a", ["upper_4b"], "cap_flat_4", ""],
	["shop_dark_8a", ["upper_8c", "upper_8a"], "cap_cornice_8", "sign_drugs"],
	["shuttered_5a", ["upper_5c"], "cap_flat_5", ""],
	["shop_lit_4b", ["upper_4a", "upper_4b"], "cap_parapet_4", "sign_newsstand"],
	["boarded_6a", ["upper_6e"], "cap_cornice_6", ""],
	["shop_dark_3a", ["upper_3d"], "cap_flat_3", ""],
	["shuttered_8a", ["upper_8d", "upper_8e"], "cap_parapet_8", ""],
	["doorway_4a", ["upper_4c", "upper_4a"], "cap_cornice_4", ""],
	["shop_dark_4a", ["upper_4d"], "cap_parapet_4", ""],
	["wall_3a", ["upper_3c"], "cap_flat_3", ""],
	["shop_dark_6a", ["upper_6b", "upper_6c"], "cap_cornice_6", ""],
	["boarded_5a", ["upper_5e"], "cap_parapet_5", ""],
	["shuttered_3a", ["upper_3a"], "cap_flat_3", ""],
	["wall_5a", ["upper_5a", "upper_5d"], "cap_cornice_5", ""],
	["shop_lit_8a", ["upper_8b", "upper_8a"], "cap_parapet_8", "sign_diner"],
	["inn_8a", ["upper_8a", "upper_8b", "upper_8e"], "cap_cornice_8", "sign_hotel"],
	["inn_6a", ["upper_6a", "upper_6b"], "cap_parapet_6", ""],
	["filler_pilaster_g_03", ["filler_pilaster_u_03"], "", ""],
]

var _mods := {}
var _cam: Camera3D
var _frame := 0
var _start := 9.0
var _step := 14.0
var _warmup := 1
var _shot := "street"
var _rain := true
var _cam_z := 9.0
var _cam_y := 1.6
var _views: Array = []  # [[pos, look_at], ...] from --view=px,py,pz,lx,ly,lz;... ("L" = street length)
var _street_len := 0.0


func _ready() -> void:
	_parse_args()
	_mods = _load_json(KIT, "modules")
	_build_env()
	_build_street()
	_build_ground(-10.0, _street_len + 20.0)
	_place_props()
	if _rain:
		_build_rain()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"start": _start = float(kv[1])
			"step": _step = float(kv[1])
			"warmup": _warmup = int(kv[1])
			"shot": _shot = kv[1]
			"rain": _rain = kv[1] != "0"
			"cam_z": _cam_z = float(kv[1])
			"cam_y": _cam_y = float(kv[1])
			"view": _views = Array(kv[1].split(";"))


func _load_json(path: String, key: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		return out
	for m in data.get(key, []):
		out[m["id"]] = m
	return out


func _inst(id: String, mods: Dictionary) -> Node3D:
	if not mods.has(id):
		push_warning("missing " + id)
		return null
	var ps: PackedScene = load(mods[id]["scene"])
	return ps.instantiate() as Node3D


func _build_street() -> void:
	var x := 0.0
	for row in STREET:
		var g := _inst(row[0], _mods)
		if g == null:
			continue
		var w: float = _mods[row[0]]["width"]
		g.position = Vector3(x, 0, 0)
		add_child(g)
		if row[3] != "":
			_apply_sign(g, SIGN_DIR + row[3] + ".png")
		var y: float = _mods[row[0]]["height"]
		for u in row[1]:
			var un := _inst(u, _mods)
			if un == null:
				continue
			un.position = Vector3(x, y, 0)
			add_child(un)
			y += float(_mods[u]["height"])
		if row[2] != "":
			var c := _inst(row[2], _mods)
			if c:
				c.position = Vector3(x, y, 0)
				add_child(c)
		var style: String = _mods[row[0]].get("style", "")
		if style in ["shop_lit", "shop_dark", "inn"] and w >= 3.0 and row[0] != "shop_dark_3a":
			_add_awning(x + 0.15, x + w - 0.15, style == "shop_dark")
		x += w
	_street_len = x
	# side street corner at the end
	var s := _inst("side_ground_10", _mods)
	if s:
		s.position = Vector3(x, 0, 0)
		add_child(s)
		var su := _inst("side_upper_ad_10", _mods)
		if su:
			su.position = Vector3(x, 4.0, 0)
			add_child(su)


func _apply_sign(root: Node, tex_path: String) -> void:
	if not ResourceLoader.exists(tex_path):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.roughness = 0.7
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var sm := m.surface_get_material(i)
			if sm and sm.resource_name == "sign_face":
				(mi as MeshInstance3D).set_surface_override_material(i, mat)


func _add_awning(x0: float, x1: float, torn: bool) -> void:
	# Stand-in for the code-generated awning: sloped striped canvas from y=3.0 out to z=1.6.
	var depth := 1.6
	var drop := 0.7
	var mesh := QuadMesh.new()
	var length := sqrt(depth * depth + drop * drop)
	mesh.size = Vector2(x1 - x0, length)
	var mat: Material = load("res://assets/materials/awning_canvas.tres").duplicate()
	(mat as StandardMaterial3D).uv1_scale = Vector3((x1 - x0) / 1.0, 1.0, 1.0)
	(mat as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	if torn:
		(mat as StandardMaterial3D).albedo_color = Color(0.55, 0.55, 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) * 0.5, 3.0 - drop * 0.5, depth * 0.5)
	mi.rotation = Vector3(-PI * 0.5 + atan2(drop, depth), 0, 0)
	add_child(mi)
	var val := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(x1 - x0, 0.25, 0.01)
	val.mesh = vm
	val.material_override = mat
	val.position = Vector3((x0 + x1) * 0.5, 3.0 - drop - 0.12, depth)
	add_child(val)


func _build_ground(x0: float, x1: float) -> void:
	var L := x1 - x0
	var cx := (x0 + x1) * 0.5
	# sidewalk slab: top at y = 0, z 0..3.3 (curb stone 3.3..3.5)
	_box(Vector3(cx, -0.1, 1.65), Vector3(L, 0.2, 3.3), "res://assets/materials/sidewalk.tres")
	_box(Vector3(cx, -0.1, 3.4), Vector3(L, 0.2, 0.2), "res://assets/materials/curb.tres")
	# road: 15 cm below the sidewalk
	_box(Vector3(cx, -0.25, 14.0), Vector3(L, 0.2, 21.0), "res://assets/materials/asphalt_wet.tres")
	# backdrop wall behind the camera-side so reflections aren't empty
	_box(Vector3(cx, 6.0, 26.0), Vector3(L, 12.0, 0.5), "res://assets/materials/brick_dark.tres")


func _box(pos: Vector3, size: Vector3, mat_path: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = load(mat_path)
	mi.position = pos
	add_child(mi)


func _place_props() -> void:
	var props := _load_json(PROPS, "props")
	if props.is_empty():
		return
	var line := [
		# id, x, z (z < 0 means: use the default for its `place`)
		["lamp_post", 3.0], ["hydrant", 7.5], ["newspaper_box", 9.6], ["trash_can", 12.2],
		["parking_meter", 16.0], ["bench", 19.0], ["mailbox", 22.5], ["fire_barrel", 27.0],
		["lamp_post", 29.0], ["street_sign", 33.0], ["parking_meter", 38.0], ["trash_bags", 41.0],
		["crates", 44.5], ["lamp_post", 55.0], ["hydrant", 60.0], ["newspaper_box", 64.0],
		["bollard", 70.0], ["phone_booth", 76.0], ["lamp_post", 81.0], ["trash_can", 85.0],
		["bench", 91.0], ["lamp_post", 107.0], ["sandwich_board", 112.0], ["mailbox", 118.0],
		["lamp_post", 133.0], ["fire_barrel", 125.0],
	]
	for p in line:
		var n := _inst(p[0], props)
		if n == null:
			continue
		n.position = Vector3(p[1], 0, _default_z(props[p[0]]))
		add_child(n)
	# wall props
	var walls := [["wall_ac_unit", 13.0, 2.6], ["downpipe", 6.3, 0.0], ["wall_ac_unit", 48.0, 2.4], ["downpipe", 64.6, 0.0]]
	for p in walls:
		var n := _inst(p[0], props)
		if n:
			n.position = Vector3(p[1], p[2], 0.0)
			add_child(n)
	# parked cars
	for c in [[10.0, "car_sedan"], [35.0, "car_sedan_b"], [100.0, "car_sedan_c"]]:
		var car := _inst(c[1], props)
		if car:
			car.position = Vector3(c[0], -0.15, 4.65)
			add_child(car)


func _default_z(p: Dictionary) -> float:
	match p.get("place", "sidewalk"):
		"curb": return 3.0
		"wall": return 0.0
		"road": return 4.6
		"wall_high": return 0.0
		_: return 1.0


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.09, 0.11, 0.15)
	sm.sky_horizon_color = Color(0.22, 0.26, 0.32)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.035)
	sm.ground_horizon_color = Color(0.14, 0.15, 0.17)
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.2, 0.24, 0.3)
	env.fog_density = 0.012
	env.fog_aerial_perspective = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.6, 0.65, 0.72)
	env.volumetric_fog_emission = Color(0.02, 0.025, 0.03)
	env.volumetric_fog_length = 40.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.62, 0.7, 0.85)
	sun.light_energy = 0.35
	sun.rotation_degrees = Vector3(-55, 20, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.position = Vector3(_start, 1.6, 9.0)
	_cam.current = true
	add_child(_cam)


func _build_rain() -> void:
	var p := GPUParticles3D.new()
	p.amount = 4000
	p.local_coords = true
	p.lifetime = 1.2
	p.preprocess = 1.2
	p.visibility_aabb = AABB(Vector3(-20, -10, -10), Vector3(40, 30, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 0.5, 6)
	pm.direction = Vector3(0.05, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3(0, -2, 0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.45)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(0.7, 0.75, 0.85, 0.12)
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = qm
	p.draw_pass_1 = q
	p.position = Vector3(0, 9, 3.5)
	_cam.add_child(p)
	p.position = Vector3(0, 7.5, -5.5)


func _process(_dt: float) -> void:
	var k := maxi(0, _frame - _warmup)
	if not _views.is_empty():
		var parts: PackedStringArray = String(_views[k % _views.size()]).split(",")
		var f := func(t: String) -> float: return float(t.replace("L", str(_street_len))) if not t.begins_with("L") else _street_len + float(t.substr(1))
		var pos := Vector3(f.call(parts[0]), f.call(parts[1]), f.call(parts[2]))
		var at := Vector3(f.call(parts[3]), f.call(parts[4]), f.call(parts[5]))
		_cam.position = pos
		_cam.look_at(at)
	elif _shot == "car":
		var views := [[Vector3(15.5, 1.3, 8.0), Vector3(10.5, 0.6, 4.6)], [Vector3(4.5, 1.2, 8.5), Vector3(9.5, 0.6, 4.6)], [Vector3(13.8, 0.9, 6.6), Vector3(10.0, 0.5, 4.6)], [Vector3(10.0, 3.5, 10.0), Vector3(10.0, 0.5, 4.6)]]
		var v: Array = views[k % views.size()]
		_cam.position = v[0]
		_cam.look_at(v[1])
	elif _shot == "props":
		var spots := [Vector3(10.5, 1.4, 9.5), Vector3(3.0, 1.6, 7.0), Vector3(17.0, 1.4, 7.0), Vector3(25.0, 1.4, 7.0), Vector3(36.0, 1.5, 9.5), Vector3(42.0, 1.4, 7.0), Vector3(66.0, 1.6, 7.5), Vector3(76.0, 1.6, 8.0), Vector3(100.0, 1.5, 9.5)]
		_cam.position = spots[k % spots.size()]
	else:
		_cam.position = Vector3(_start + _step * k, _cam_y, _cam_z)
	_frame += 1
