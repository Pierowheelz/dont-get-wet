class_name LevelBuilder
extends RefCounted
## Builds the street (ground, buildings, cover, features, props) from level JSON.
## Cover geometry gets StaticBody3D colliders on the `cover` physics layer — the rain model is driven
## entirely by these colliders, so what you see is what blocks the rain.

const COVER_LAYER := 1 << 1
const SIDEWALK_W := 3.5
const ROAD_Y := -0.16
const AWNING_WALL_Y := 3.05
const AWNING_FRONT_Y := 2.6
const AWNING_DEPTH := 2.35
const KIT_PATH := "res://assets/buildings/kit.json"
const PROPS_PATH := "res://assets/props/props.json"

const AWNING_COLORS := {
	"red": [Color(0.55, 0.12, 0.1), Color(0.85, 0.8, 0.7)],
	"green": [Color(0.12, 0.32, 0.18), Color(0.82, 0.8, 0.68)],
	"blue": [Color(0.12, 0.2, 0.4), Color(0.8, 0.8, 0.75)],
	"brown": [Color(0.32, 0.2, 0.12), Color(0.75, 0.62, 0.42)],
	"orange": [Color(0.7, 0.32, 0.08), Color(0.85, 0.78, 0.6)],
	"teal": [Color(0.08, 0.38, 0.38), Color(0.8, 0.8, 0.72)],
}

var root: Node3D
var data: Dictionary
var rng := RandomNumberGenerator.new()
var kit: Dictionary = {}            # style -> kind -> Array of module dicts
var props_kit: Dictionary = {}      # id -> prop dict
var lit_windows: Array = []         # [Vector3 position, Color] for lights
var sign_font: Font
var _mats := {}
var _awning_shader: Shader
var _scene_cache := {}


func build(p_root: Node3D, p_data: Dictionary) -> void:
	root = p_root
	data = p_data
	rng.seed = hash(String(data.get("id", "level")))
	_awning_shader = load("res://src/fx/awning.gdshader")
	_load_kits()
	if ResourceLoader.exists("res://assets/fonts/sign.ttf"):
		sign_font = load("res://assets/fonts/sign.ttf")
	_build_ground()
	for lot in data.get("lots", []):
		_build_lot(lot)
	for c in data.get("crossings", []):
		_build_crossing(c)
	_build_backdrop()
	for p in data.get("props", []):
		_build_prop(p)


# --- helpers --------------------------------------------------------------------------------

func _mat(key: String, color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


func _material_res(name: String, fallback: Material) -> Material:
	var path := "res://assets/materials/%s.tres" % name
	if ResourceLoader.exists(path):
		return load(path)
	return fallback


func _box(size: Vector3, center: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	(parent if parent else root).add_child(mi)
	return mi


func _cover_box(size: Vector3, xform: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = COVER_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.transform = xform
	root.add_child(body)


func _instance(path: String) -> Node3D:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	var ps: PackedScene = _scene_cache[path]
	return ps.instantiate() if ps else null


func _load_kits() -> void:
	if FileAccess.file_exists(KIT_PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH))
		if d is Dictionary:
			for m in d.get("modules", []):
				if not ResourceLoader.exists(m["scene"]):
					continue
				var style: String = m.get("style", m["kind"])
				var kind: String = m["kind"]
				if not kit.has(kind):
					kit[kind] = {}
				if not kit[kind].has(style):
					kit[kind][style] = []
				kit[kind][style].append(m)
	if FileAccess.file_exists(PROPS_PATH):
		var d2: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROPS_PATH))
		if d2 is Dictionary:
			for p in d2.get("props", []):
				if ResourceLoader.exists(p["scene"]):
					props_kit[p["id"]] = p


# --- ground ---------------------------------------------------------------------------------

func _build_ground() -> void:
	var L: float = data["length"]
	var x0 := -30.0
	var x1 := L + 30.0
	var sidewalk := _material_res("sidewalk", _mat("sidewalk", Color(0.36, 0.35, 0.34), 0.25))
	var curb := _material_res("curb", _mat("curb", Color(0.45, 0.44, 0.42), 0.4))
	var road := _material_res("asphalt_wet", _mat("road", Color(0.07, 0.07, 0.08), 0.12))
	# Sidewalk pieces between crossings.
	var cuts: Array = []
	for c in data.get("crossings", []):
		cuts.append([float(c["x"]), float(c["x"]) + float(c["w"])])
	var sx := x0
	for c in cuts + [[x1, x1]]:
		var ex: float = c[0]
		if ex > sx:
			_box(Vector3(ex - sx, 0.3, SIDEWALK_W), Vector3((sx + ex) * 0.5, -0.15, SIDEWALK_W * 0.5), sidewalk)
			_box(Vector3(ex - sx, 0.32, 0.25), Vector3((sx + ex) * 0.5, -0.15, SIDEWALK_W - 0.12), curb)
		sx = c[1]
	# Road (camera side) and under-crossing road.
	_box(Vector3(x1 - x0, 0.2, 14.0), Vector3((x0 + x1) * 0.5, ROAD_Y - 0.1, SIDEWALK_W + 7.0), road)
	for c in cuts:
		_box(Vector3(c[1] - c[0], 0.2, 60.0), Vector3((c[0] + c[1]) * 0.5, ROAD_Y - 0.1, SIDEWALK_W - 30.0), road)
		# zebra crossing stripes along the walking line
		var stripe := _mat("zebra", Color(0.75, 0.74, 0.7), 0.35)
		var zx: float = c[0] + 0.8
		while zx < c[1] - 0.8:
			_box(Vector3(0.5, 0.02, 2.6), Vector3(zx, ROAD_Y + 0.005, 1.7), stripe)
			zx += 1.0


# --- buildings ------------------------------------------------------------------------------

func _build_lot(lot: Dictionary) -> void:
	var x: float = lot["x"]
	var w: float = lot["w"]
	var style: String = lot.get("style", "wall")
	var floors: int = int(lot.get("floors", 2))
	if style == "vacant":
		_build_vacant(x, w)
	else:
		_build_facade(x, w, style, floors, lot)
	match lot.get("cover", "none"):
		"awning":
			_build_awning(x, w, lot.get("tears", []), lot.get("awning_color", "red"))
		"balcony":
			_build_slab(x, w, 3.35, 2.4, false)
		"arcade":
			_build_slab(x, w, 3.6, 2.9, true)
	if lot.has("sign") and style != "vacant":
		_build_sign(x, w, String(lot["sign"]), style, bool(lot.get("neon", false)))


func _wall_color() -> Color:
	var palette := [Color(0.42, 0.22, 0.17), Color(0.5, 0.42, 0.33), Color(0.36, 0.33, 0.3),
		Color(0.55, 0.5, 0.42), Color(0.3, 0.24, 0.2), Color(0.45, 0.38, 0.36)]
	return palette[rng.randi() % palette.size()]


func _build_facade(x: float, w: float, style: String, floors: int, lot: Dictionary) -> void:
	var height := 4.0 + floors * 3.2
	if _kit_facade(x, w, style, floors):
		return
	var wall := _mat("wall_%d" % (rng.randi() % 6), _wall_color(), 0.9)
	var depth := 9.0
	_box(Vector3(w, height, depth), Vector3(x + w * 0.5, height * 0.5, -depth * 0.5 - 0.3), wall)
	# Pilasters between shopfronts and a cornice.
	var trim := _mat("trim", Color(0.6, 0.57, 0.5), 0.7)
	_box(Vector3(0.35, 4.0, 0.35), Vector3(x + 0.17, 2.0, -0.15), trim)
	_box(Vector3(w, 0.35, 0.5), Vector3(x + w * 0.5, height + 0.1, -0.25), trim)
	_box(Vector3(w, 0.8, 0.3), Vector3(x + w * 0.5, 3.5, -0.15), _mat("signband", Color(0.2, 0.18, 0.16), 0.8))
	# Ground floor
	var glass_dark := _mat("glass_dark", Color(0.03, 0.035, 0.04), 0.05, 0.3)
	match style:
		"shop_lit", "inn":
			var glow := StandardMaterial3D.new()
			glow.albedo_color = Color(0.9, 0.7, 0.45)
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.72, 0.42)
			glow.emission_energy_multiplier = 1.4
			_box(Vector3(w - 1.2, 2.5, 0.1), Vector3(x + w * 0.5, 1.75, -0.45), glow)
			lit_windows.append([Vector3(x + w * 0.5, 2.0, -1.2), Color(1.0, 0.68, 0.38)])
			if style == "inn":
				var door := _mat("inn_door", Color(0.25, 0.12, 0.06), 0.6)
				_box(Vector3(1.4, 2.6, 0.12), Vector3(x + w * 0.5, 1.3, -0.3), door)
		"shop_dark", "doorway":
			_box(Vector3(w - 1.2, 2.5, 0.1), Vector3(x + w * 0.5, 1.75, -0.45), glass_dark)
		"shuttered":
			_box(Vector3(w - 1.0, 2.9, 0.12), Vector3(x + w * 0.5, 1.45, -0.32), _mat("shutter", Color(0.38, 0.38, 0.37), 0.55, 0.6))
		"boarded":
			_box(Vector3(w - 1.0, 2.6, 0.12), Vector3(x + w * 0.5, 1.6, -0.3), _mat("boards", Color(0.36, 0.28, 0.18), 0.9))
	# Upper floor windows
	for f in floors:
		var wy := 4.0 + f * 3.2 + 1.7
		var n := maxi(1, int(w / 2.2))
		for i in n:
			var wx := x + (i + 0.5) * w / n
			var lit := rng.randf() < 0.12
			var m := _mat("win_lit", Color(0.9, 0.75, 0.5), 0.3) if lit else glass_dark
			if lit:
				m.emission_enabled = true
				m.emission = Color(0.95, 0.7, 0.4)
				m.emission_energy_multiplier = 0.8
			_box(Vector3(1.1, 1.6, 0.1), Vector3(wx, wy, -0.28), m)
			_box(Vector3(1.3, 0.12, 0.25), Vector3(wx, wy - 0.86, -0.2), trim)


func _kit_facade(x: float, w: float, style: String, floors: int) -> bool:
	if not kit.has("ground"):
		return false
	var grounds: Dictionary = kit["ground"]
	var options: Array = grounds.get(style, grounds.get("wall", []))
	if options.is_empty():
		return false
	# Fill width with the widest modules that fit, padding with fillers.
	var placed := 0.0
	var parts: Array = []
	var guard := 0
	while w - placed > 0.29 and guard < 12:
		guard += 1
		var best: Dictionary = {}
		var candidates := options.duplicate()
		candidates.shuffle()
		for m in candidates:
			if float(m["width"]) <= w - placed + 0.01 and (best.is_empty() or float(m["width"]) > float(best["width"])):
				best = m
		if best.is_empty():
			for st in grounds:
				for m in grounds[st]:
					if float(m["width"]) <= w - placed + 0.01 and (best.is_empty() or float(m["width"]) > float(best["width"])):
						best = m
		if best.is_empty():
			break
		parts.append([best, placed])
		placed += float(best["width"])
	# Center the composition; leftover becomes filler on both sides.
	var pad := (w - placed) * 0.5
	for p in parts:
		var n := _instance(p[0]["scene"])
		if n:
			n.position = Vector3(x + pad + p[1], 0, 0)
			root.add_child(n)
	_fill(x, pad)
	_fill(x + w - pad, pad)
	# Upper storeys
	var uppers: Dictionary = kit.get("upper", {})
	var ups: Array = []
	for st in uppers:
		ups.append_array(uppers[st])
	for f in floors:
		var px := 0.0
		var g := 0
		while w - px > 0.29 and g < 12:
			g += 1
			var best: Dictionary = {}
			ups.shuffle()
			for m in ups:
				if float(m["width"]) <= w - px + 0.01 and (best.is_empty() or float(m["width"]) > float(best["width"])):
					best = m
			if best.is_empty():
				break
			var n := _instance(best["scene"])
			if n:
				n.position = Vector3(x + px, 4.0 + f * 3.2, 0)
				root.add_child(n)
			px += float(best["width"])
		_fill(x + px, w - px, 4.0 + f * 3.2, 3.2)
	var caps: Array = []
	for st in kit.get("cap", {}):
		caps.append_array(kit["cap"][st])
	if not caps.is_empty():
		var cap: Dictionary = caps[rng.randi() % caps.size()]
		var cx := 0.0
		while cx < w - 0.1:
			var n := _instance(cap["scene"])
			if n:
				n.position = Vector3(x + cx, 4.0 + floors * 3.2, 0)
				var cw := float(cap["width"])
				if cx + cw > w:
					n.scale.x = (w - cx) / cw
				root.add_child(n)
			cx += float(cap["width"])
	# Back mass so the building has depth when seen from crossings.
	var height := 4.0 + floors * 3.2
	_box(Vector3(w, height, 8.0), Vector3(x + w * 0.5, height * 0.5, -4.6),
		_material_res("brick_brown", _mat("back", Color(0.3, 0.24, 0.2), 0.9)))
	return true


func _fill(x: float, w: float, y := 0.0, h := 4.0) -> void:
	if w <= 0.02:
		return
	_box(Vector3(w, h, 0.6), Vector3(x + w * 0.5, y + h * 0.5, -0.3),
		_material_res("brick_red", _mat("filler", Color(0.4, 0.22, 0.17), 0.9)))


func _build_vacant(x: float, w: float) -> void:
	# Chain-link fence and a far wall: open sky, no cover.
	var fence := _mat("fence", Color(0.3, 0.3, 0.3), 0.5, 0.7)
	_box(Vector3(w, 0.06, 0.06), Vector3(x + w * 0.5, 1.8, -0.1), fence)
	_box(Vector3(w, 0.06, 0.06), Vector3(x + w * 0.5, 0.2, -0.1), fence)
	var px := x
	while px <= x + w + 0.01:
		_box(Vector3(0.06, 1.9, 0.06), Vector3(px, 0.95, -0.1), fence)
		px += 2.0
	_box(Vector3(w, 0.3, 12.0), Vector3(x + w * 0.5, -0.15, -6.0), _mat("dirt", Color(0.12, 0.1, 0.08), 0.6))
	_box(Vector3(w + 6.0, 9.0, 1.0), Vector3(x + w * 0.5, 4.5, -14.0), _mat("farwall", Color(0.22, 0.2, 0.19), 0.9))


# --- cover ----------------------------------------------------------------------------------

func _build_awning(x: float, w: float, tears: Array, color_name: String) -> void:
	var cols: Array = AWNING_COLORS.get(color_name, AWNING_COLORS["red"])
	var mat := ShaderMaterial.new()
	mat.shader = _awning_shader
	mat.set_shader_parameter("color_a", cols[0])
	mat.set_shader_parameter("color_b", cols[1])
	mat.set_shader_parameter("stripe_count", roundf(w / 0.45))
	mat.set_shader_parameter("grime", rng.randf_range(0.3, 0.8))
	# Split into segments around tears (tears are local [x0, x1]).
	var segs: Array = []
	var sx := 0.0
	var sorted_tears := tears.duplicate()
	sorted_tears.sort_custom(func(a, b): return a[0] < b[0])
	for t in sorted_tears:
		segs.append([sx, float(t[0])])
		sx = float(t[1])
	segs.append([sx, w])
	var slope := atan2(AWNING_WALL_Y - AWNING_FRONT_Y, AWNING_DEPTH)
	var len := sqrt(AWNING_DEPTH * AWNING_DEPTH + pow(AWNING_WALL_Y - AWNING_FRONT_Y, 2))
	for s in segs:
		var a: float = x + s[0]
		var b: float = x + s[1]
		if b - a < 0.05:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _awning_mesh(b - a, len, a - x, w)
		mi.material_override = mat
		mi.position = Vector3(a, AWNING_WALL_Y, 0.0)
		mi.rotation.x = slope
		root.add_child(mi)
		var xf := Transform3D(Basis.from_euler(Vector3(slope, 0, 0)),
			Vector3((a + b) * 0.5, (AWNING_WALL_Y + AWNING_FRONT_Y) * 0.5, AWNING_DEPTH * 0.5))
		_cover_box(Vector3(b - a, 0.06, len), xf)
	# Torn flaps hanging into tears.
	for t in sorted_tears:
		var flap := _box(Vector3((float(t[1]) - float(t[0])) * 0.35, 0.6, 0.02),
			Vector3(x + float(t[0]) + 0.2, AWNING_FRONT_Y + 0.05, AWNING_DEPTH - 0.4), mat)
		flap.rotation = Vector3(0.3, 0, 0.25)
	# Metal frame arms.
	var frame := _mat("frame", Color(0.15, 0.15, 0.15), 0.4, 0.8)
	for fx in [x + 0.1, x + w - 0.1]:
		var arm := _box(Vector3(0.04, 0.04, len), Vector3(fx, (AWNING_WALL_Y + AWNING_FRONT_Y) * 0.5 - 0.05, AWNING_DEPTH * 0.5), frame)
		arm.rotation.x = slope


func _awning_mesh(w: float, len: float, u0: float, full_w: float) -> ArrayMesh:
	# Slightly sagging canvas plane (local X along street, -Z... rotated by caller) + valance.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := maxi(2, int(w / 0.25))
	var nz := 6
	var grid: Array = []
	for i in nx + 1:
		var row: Array = []
		for j in nz + 1:
			var u := float(i) / nx
			var v := float(j) / nz
			var sag := sin(v * PI) * 0.05 + sin(u * PI * maxf(1.0, w / 1.5)) * 0.015 * v
			row.append(Vector3(u * w, -sag, v * len))
		grid.append(row)
	for i in nx:
		for j in nz:
			_quad(st, grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1],
				Vector2((u0 + float(i) / nx * w) / full_w, float(j) / nz),
				Vector2((u0 + float(i + 1) / nx * w) / full_w, float(j + 1) / nz))
	# Valance: hangs vertically from the front edge with a scalloped bottom.
	var vh := 0.28
	for i in nx:
		var p0: Vector3 = grid[i][nz]
		var p1: Vector3 = grid[i + 1][nz]
		var s0 := vh - absf(sin(float(i) / nx * w / 0.45 * PI)) * 0.06
		var s1 := vh - absf(sin(float(i + 1) / nx * w / 0.45 * PI)) * 0.06
		# local frame is rotated by slope; build "down" in world by undoing the slope roughly
		var down := Vector3(0, -cos(0.19), sin(0.19))
		_quad(st, p0, p1, p1 + down * s1, p0 + down * s0,
			Vector2((u0 + float(i) / nx * w) / full_w, 0.85), Vector2((u0 + float(i + 1) / nx * w) / full_w, 1.0))
	st.generate_normals()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv0: Vector2, uv1: Vector2) -> void:
	st.set_uv(Vector2(uv0.x, uv0.y)); st.add_vertex(a)
	st.set_uv(Vector2(uv1.x, uv0.y)); st.add_vertex(b)
	st.set_uv(Vector2(uv1.x, uv1.y)); st.add_vertex(c)
	st.set_uv(Vector2(uv0.x, uv0.y)); st.add_vertex(a)
	st.set_uv(Vector2(uv1.x, uv1.y)); st.add_vertex(c)
	st.set_uv(Vector2(uv0.x, uv1.y)); st.add_vertex(d)


func _build_slab(x: float, w: float, y: float, depth: float, columns: bool) -> void:
	var conc := _material_res("concrete", _mat("slab", Color(0.42, 0.4, 0.37), 0.85))
	_box(Vector3(w, 0.28, depth), Vector3(x + w * 0.5, y, depth * 0.5), conc)
	_box(Vector3(w, 0.9, 0.08), Vector3(x + w * 0.5, y + 0.6, depth - 0.04), _mat("rail", Color(0.12, 0.12, 0.12), 0.5, 0.7))
	_cover_box(Vector3(w, 0.28, depth), Transform3D(Basis(), Vector3(x + w * 0.5, y, depth * 0.5)))
	if columns:
		var cx := x + 0.3
		while cx < x + w:
			_box(Vector3(0.3, y, 0.3), Vector3(cx, y * 0.5, depth - 0.2), conc)
			cx += 3.5


func _build_sign(x: float, w: float, text: String, style: String, neon: bool) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.pixel_size = 0.004
	if sign_font:
		lbl.font = sign_font
	lbl.width = (w - 0.6) / lbl.pixel_size
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.position = Vector3(x + w * 0.5, 3.55, 0.05)
	var lit := style in ["shop_lit", "inn"] or neon
	lbl.modulate = Color(1.0, 0.85, 0.55) if not neon else Color(0.4, 1.0, 0.95)
	if not lit:
		lbl.modulate = Color(0.55, 0.5, 0.42)
	lbl.outline_size = 0
	lbl.shaded = not lit
	lbl.double_sided = false
	var max_w := (w - 0.6) / lbl.pixel_size
	lbl.font_size = int(clampf(max_w / maxf(1.0, text.length() * 0.62), 40.0, 110.0))
	root.add_child(lbl)
	if neon:
		var om := OmniLight3D.new()
		om.light_color = lbl.modulate
		om.light_energy = 1.2
		om.omni_range = 4.0
		om.position = lbl.position + Vector3(0, 0, 0.6)
		root.add_child(om)


# --- crossings & backdrop -------------------------------------------------------------------

func _build_crossing(c: Dictionary) -> void:
	var x: float = c["x"]
	var w: float = c["w"]
	# Side-street buildings receding into the block.
	for side in [-1, 1]:
		var bx := x - 0.0 if side < 0 else x + w
		var wall := _mat("side_%d" % side, _wall_color().darkened(0.2), 0.9)
		for k in 3:
			var h := rng.randf_range(8.0, 16.0)
			var bw := 9.0
			_box(Vector3(1.0, h, bw), Vector3(bx + side * -0.5 + (side * 0.0), h * 0.5, -10.0 - k * bw - bw * 0.5 + 9.0), wall)
	# Sign post & stop line.
	_box(Vector3(w - 1.0, 0.02, 0.3), Vector3(x + w * 0.5, ROAD_Y + 0.005, -1.0), _mat("zebra", Color(0.75, 0.74, 0.7), 0.35))


func _build_backdrop() -> void:
	# A distant skyline silhouette above the rooftops (very dark, in the fog).
	var L: float = data["length"]
	var m := _mat("skyline", Color(0.05, 0.055, 0.07), 1.0)
	var x := -30.0
	while x < L + 30.0:
		var w := rng.randf_range(6, 16)
		var h := rng.randf_range(16, 34)
		_box(Vector3(w, h, 4), Vector3(x + w * 0.5, h * 0.5, -30.0 - rng.randf() * 10.0), m)
		x += w + rng.randf_range(0, 4)


func _build_prop(p: Dictionary) -> void:
	var id: String = p["id"]
	var x: float = p["x"]
	if props_kit.has(id):
		var n := _instance(props_kit[id]["scene"])
		if n:
			var place: String = props_kit[id].get("place", "curb")
			var z := 3.2 if place == "curb" else (0.35 if place == "wall" else 2.8)
			n.position = Vector3(x, 0, z)
			root.add_child(n)
			if id == "lamp_post":
				_lamp_light(x)
			return
	# Greybox fallbacks
	match id:
		"lamp_post":
			var pole := _mat("pole", Color(0.12, 0.13, 0.12), 0.5, 0.8)
			_box(Vector3(0.14, 5.2, 0.14), Vector3(x, 2.6, 3.2), pole)
			_box(Vector3(0.1, 0.1, 1.2), Vector3(x, 5.15, 2.7), pole)
			var head := StandardMaterial3D.new()
			head.emission_enabled = true
			head.emission = Color(1.0, 0.6, 0.25)
			head.emission_energy_multiplier = 3.0
			_box(Vector3(0.35, 0.12, 0.5), Vector3(x, 5.05, 2.2), head)
			_lamp_light(x)
		"hydrant":
			_box(Vector3(0.3, 0.7, 0.3), Vector3(x, 0.35, 3.0), _mat("hydrant", Color(0.6, 0.12, 0.08), 0.5))
		"trash_can":
			_box(Vector3(0.55, 0.9, 0.55), Vector3(x, 0.45, 2.9), _mat("can", Color(0.2, 0.25, 0.2), 0.6, 0.5))
		"newspaper_box":
			_box(Vector3(0.5, 1.0, 0.45), Vector3(x, 0.5, 2.9), _mat("news", Color(0.15, 0.25, 0.5), 0.5, 0.3))
		"bench":
			_box(Vector3(1.6, 0.45, 0.5), Vector3(x, 0.45, 0.6), _mat("bench", Color(0.3, 0.2, 0.12), 0.8))
		"mailbox":
			_box(Vector3(0.5, 1.1, 0.5), Vector3(x, 0.55, 2.9), _mat("mail", Color(0.12, 0.18, 0.38), 0.5, 0.3))
		"parking_meter":
			_box(Vector3(0.1, 1.2, 0.1), Vector3(x, 0.6, 3.2), _mat("pole", Color(0.12, 0.13, 0.12), 0.5, 0.8))


func _lamp_light(x: float) -> void:
	var sl := SpotLight3D.new()
	sl.light_color = Color(1.0, 0.62, 0.3)
	sl.light_energy = 6.0
	sl.spot_range = 9.0
	sl.spot_angle = 55.0
	sl.light_volumetric_fog_energy = 2.0
	sl.shadow_enabled = true
	sl.position = Vector3(x, 5.0, 2.2)
	sl.rotation = Vector3(-PI * 0.5, 0, 0)
	root.add_child(sl)
