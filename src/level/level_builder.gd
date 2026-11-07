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
const SIGN_Z := 0.09   # just in front of the kit's fascia board face (z 0.055)
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
var kit: Dictionary = {}            # active era's kit: kind -> style -> Array of module dicts
var _kits: Dictionary = {}          # era ("60s", "retro") -> kit
var props_kit: Dictionary = {}      # id -> prop dict
var lit_windows: Array = []         # [Vector3 position, Color] for lights
var inn_door_x := -1.0              # world x of the inn door (from the kit), -1 if unknown
var sign_font: Font
var _mats := {}
var _awning_shader: Shader
var _scene_cache := {}
var _drip_mesh: QuadMesh


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
	kit = _kits.get("60s", {})
	for c in data.get("crossings", []):
		_build_crossing(c)
	_build_backdrop()
	for p in data.get("props", []):
		_build_prop(p)


## Cover height map for the visual rain, over x (whole level) and z (behind facades → camera side):
## R = height of a thin cover shell (awning/slab), G = 1 where such a shell exists, B = solid
## ground/roof height. Drops only stop on a shell when they cross it from above, so slanted
## (windy) rain blows in under the edges exactly as the gameplay rays assume.
const COVER_RES := 10.0          # texels per metre along x
const COVER_RES_Z := 4.0
const COVER_Z0 := -3.0
const COVER_Z1 := 13.0


func cover_map() -> Array:
	var L: float = data["length"]
	var x0 := -30.0
	var w := int((L + 60.0) * COVER_RES)
	var h := int((COVER_Z1 - COVER_Z0) * COVER_RES_Z)
	var img := Image.create(w, h, false, Image.FORMAT_RGBF)
	var crossings: Array = []
	for c in data.get("crossings", []):
		crossings.append([float(c["x"]), float(c["x"]) + float(c["w"])])
	for ix in w:
		var x := x0 + (ix + 0.5) / COVER_RES
		var in_cross := false
		for c in crossings:
			if x > c[0] and x < c[1]:
				in_cross = true
		for iz in h:
			var z := COVER_Z0 + (iz + 0.5) / COVER_RES_Z
			var y := ROAD_Y if (z > SIDEWALK_W or in_cross) else 0.0
			if z < 0.0 and not in_cross:
				y = 30.0            # inside buildings / behind facades: never visible
			img.set_pixel(ix, iz, Color(y, 0, y))
	for lot in data.get("lots", []):
		var lx: float = lot["x"]
		var lw: float = lot["w"]
		match lot.get("cover", "none"):
			"awning":
				var segs := [[0.0, lw]]
				for t in lot.get("tears", []):
					var ns: Array = []
					for sgm in segs:
						if t[0] > sgm[0]: ns.append([sgm[0], minf(float(t[0]), sgm[1])])
						if t[1] < sgm[1]: ns.append([maxf(float(t[1]), sgm[0]), sgm[1]])
					segs = ns
				for sgm in segs:
					_cover_fill(img, x0, lx + sgm[0], lx + sgm[1], 0.0, AWNING_DEPTH, true)
			"balcony":
				_cover_fill(img, x0, lx, lx + lw, 0.0, 2.4, false, 3.35)
			"arcade":
				_cover_fill(img, x0, lx, lx + lw, 0.0, 2.9, false, 3.6)
			"canopy":
				_cover_fill(img, x0, lx + 0.15, lx + lw - 0.15, -0.2, 3.3, false, 3.55)
	var tex := ImageTexture.create_from_image(img)
	return [tex, Vector4(x0, COVER_Z0, w / COVER_RES, COVER_Z1 - COVER_Z0)]


func _cover_fill(img: Image, x0: float, a: float, b: float, z0: float, z1: float, sloped: bool, flat_y := 0.0) -> void:
	var ia := int((a - x0) * COVER_RES)
	var ib := int((b - x0) * COVER_RES)
	for ix in range(maxi(ia, 0), mini(ib, img.get_width())):
		for iz in img.get_height():
			var z := COVER_Z0 + (iz + 0.5) / COVER_RES_Z
			if z >= z0 and z <= z1:
				var y := flat_y
				if sloped:
					y = AWNING_WALL_Y - (AWNING_WALL_Y - AWNING_FRONT_Y) * (z / AWNING_DEPTH)
				var old := img.get_pixel(ix, iz)
				img.set_pixel(ix, iz, Color(y, 1.0, old.b))


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
			var aes: String = data.get("aesthetic", "rundown")
			for m in d.get("modules", []):
				if not ResourceLoader.exists(m["scene"]):
					continue
				var ok: Array = m.get("aesthetics", [])
				if not ok.is_empty() and not ok.has(aes) and not (aes == "neon" and ok.has("rundown_neon")):
					continue
				var style: String = m.get("style", m["kind"])
				var kind: String = m["kind"]
				var era: String = m.get("era", "60s")
				if not _kits.has(era):
					_kits[era] = {}
				var k: Dictionary = _kits[era]
				if not k.has(kind):
					k[kind] = {}
				if not k[kind].has(style):
					k[kind][style] = []
				k[kind][style].append(m)
	kit = _kits.get("60s", {})
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
	# Retro-future modules replace 60s ones with probability = the level's neon value.
	kit = _kits.get("60s", {})
	var retro: Dictionary = _kits.get("retro", {})
	if not retro.is_empty() and rng.randf() < float(data.get("neon", 0.0)):
		var st: String = lot.get("style", "wall")
		if retro.get("ground", {}).has(st):
			kit = retro
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
		"canopy":
			# Gas-station canopy (the kit module draws it; we add the collider).
			_cover_box(Vector3(w - 0.3, 0.4, 3.5), Transform3D(Basis(), Vector3(x + w * 0.5, 3.75, 1.55)))
			_drips(x + 0.15, x + w - 0.15, 3.5, 3.32)
	if lot.has("sign") and style != "vacant":
		_build_sign(x, w, String(lot["sign"]), style, bool(lot.get("neon", false)))
	if style != "vacant" and rng.randf() < float(data.get("neon", 0.0)) * 0.45:
		_build_holo(x, w, floors)
	if style != "vacant" and floors >= 1 and w >= 6.0 and rng.randf() < float(data.get("neon", 0.0)) * 0.5:
		var cid := "overhead_cables_10" if w >= 10.0 else "overhead_cables_6"
		if props_kit.has(cid):
			var cn := _instance(props_kit[cid]["scene"])
			if cn:
				cn.position = Vector3(x, float(props_kit[cid].get("mount_y", 6.6)), 0.0)
				root.add_child(cn)


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
			if p[0].has("door") and inn_door_x < 0.0:
				inn_door_x = x + pad + float(p[1]) + float(p[0]["door"][0])
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
		_drips(a, b, AWNING_FRONT_Y - 0.26, AWNING_DEPTH + 0.05)
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


## A line of drips falling from a cover edge: telegraphs exactly where shelter ends.
func _drips(a: float, b: float, y: float, z: float) -> void:
	var w := b - a
	if w < 0.3:
		return
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(w * 14.0))
	p.lifetime = 0.75
	p.randomness = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.5, 0.01, 0.03)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	p.process_material = pm
	if _drip_mesh == null:
		_drip_mesh = QuadMesh.new()
		_drip_mesh.size = Vector2(0.018, 0.16)
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dm.albedo_color = Color(0.75, 0.82, 0.95, 0.55)
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_drip_mesh.material = dm
	p.draw_pass_1 = _drip_mesh
	p.position = Vector3((a + b) * 0.5, y, z)
	p.visibility_aabb = AABB(Vector3(-w * 0.5 - 0.5, -4.0, -0.5), Vector3(w + 1.0, 4.5, 1.0))
	root.add_child(p)


func _build_slab(x: float, w: float, y: float, depth: float, columns: bool) -> void:
	var conc := _material_res("concrete", _mat("slab", Color(0.42, 0.4, 0.37), 0.85))
	_box(Vector3(w, 0.28, depth), Vector3(x + w * 0.5, y, depth * 0.5), conc)
	_box(Vector3(w, 0.9, 0.08), Vector3(x + w * 0.5, y + 0.6, depth - 0.04), _mat("rail", Color(0.12, 0.12, 0.12), 0.5, 0.7))
	_cover_box(Vector3(w, 0.28, depth), Transform3D(Basis(), Vector3(x + w * 0.5, y, depth * 0.5)))
	_drips(x, x + w, y - 0.15, depth + 0.02)
	if columns:
		var cx := x + 0.3
		while cx < x + w:
			_box(Vector3(0.3, y, 0.3), Vector3(cx, y * 0.5, depth - 0.2), conc)
			cx += 3.5


const NEON_COLORS := [Color(0.2, 1.0, 0.95), Color(1.0, 0.25, 0.75), Color(1.0, 0.55, 0.15),
	Color(0.55, 0.35, 1.0), Color(0.35, 1.0, 0.4), Color(1.0, 0.2, 0.25)]


func _build_sign(x: float, w: float, text: String, style: String, neon: bool) -> void:
	if neon:
		_build_neon(x, w, text)
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.pixel_size = 0.004
	if sign_font:
		lbl.font = sign_font
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.position = Vector3(x + w * 0.5, 3.5, SIGN_Z)
	var lit := style in ["shop_lit", "inn"]
	lbl.modulate = Color(1.0, 0.85, 0.55) if lit else Color(0.55, 0.5, 0.42)
	lbl.outline_size = 0
	lbl.shaded = not lit
	lbl.double_sided = false
	var max_w := (w - 0.6) / lbl.pixel_size
	lbl.font_size = int(clampf(max_w / maxf(1.0, text.length() * 0.62), 40.0, 110.0))
	root.add_child(lbl)


## Retro-future neon: glowing tube lettering on the fascia, a vertical blade sign, coloured spill.
func _build_neon(x: float, w: float, text: String) -> void:
	var col: Color = NEON_COLORS[rng.randi() % NEON_COLORS.size()]
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 64
	tm.pixel_size = 0.0045
	tm.depth = 0.03
	if sign_font:
		tm.font = sign_font
	var est_w := text.length() * tm.font_size * 0.62 * tm.pixel_size
	if est_w > w - 0.6:
		tm.pixel_size *= (w - 0.6) / est_w
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = _neon_mat(col, 6.0)
	mi.position = Vector3(x + w * 0.5, 3.42, SIGN_Z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var om := OmniLight3D.new()
	om.light_color = col
	om.light_energy = 2.2
	om.omni_range = 5.5
	om.light_volumetric_fog_energy = 1.2
	om.position = Vector3(x + w * 0.5, 3.3, 0.9)
	root.add_child(om)
	# Vertical blade sign on taller buildings: prefer the kit's modelled signs.
	var kit_signs: Array = ["neon_blade_a", "neon_blade_b", "neon_googie", "led_ticker"].filter(func(id): return props_kit.has(id))
	if w >= 4.0 and not kit_signs.is_empty() and rng.randf() < 0.8:
		var pid: String = kit_signs[rng.randi() % kit_signs.size()]
		var sn := _instance(props_kit[pid]["scene"])
		if sn:
			sn.position = Vector3(x + w - 0.8 if pid != "led_ticker" else x + w * 0.5, float(props_kit[pid].get("mount_y", 4.2)), 0.0)
			if pid == "led_ticker":
				sn.position.y = 4.15
				sn.position.z = 0.0
			root.add_child(sn)
		return
	if w >= 4.0 and rng.randf() < 0.75:
		var col2: Color = NEON_COLORS[rng.randi() % NEON_COLORS.size()]
		var blade := Node3D.new()
		blade.position = Vector3(x + w - 0.6, 4.15, 0.25)
		root.add_child(blade)
		var letters := text.split(" ")[0].left(6)
		var h := letters.length() * 0.5 + 0.4
		var back := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, h, 0.12)
		back.mesh = bm
		back.material_override = _mat("blade_back", Color(0.06, 0.06, 0.07), 0.4, 0.6)
		back.position = Vector3(0, h * 0.5, 0)
		blade.add_child(back)
		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.74, h + 0.06, 0.1)
		frame.mesh = fm
		frame.material_override = _neon_mat(col2, 2.0)
		frame.scale = Vector3(1.0, 1.0, 1.0)
		frame.position = back.position
		frame.transparency = 0.6
		blade.add_child(frame)
		for i in letters.length():
			var lt := TextMesh.new()
			lt.text = letters[i]
			lt.font_size = 64
			lt.pixel_size = 0.006
			lt.depth = 0.02
			if sign_font:
				lt.font = sign_font
			var li := MeshInstance3D.new()
			li.mesh = lt
			li.material_override = _neon_mat(col2, 7.0)
			li.position = Vector3(0, h - 0.45 - i * 0.5, 0.07)
			blade.add_child(li)
		var bl := OmniLight3D.new()
		bl.light_color = col2
		bl.light_energy = 1.6
		bl.omni_range = 5.0
		bl.light_volumetric_fog_energy = 1.5
		bl.position = Vector3(0.0, h * 0.5, 0.6)
		blade.add_child(bl)
		bl.set_script(load("res://src/fx/neon_flicker.gd"))


func _neon_mat(col: Color, energy: float) -> StandardMaterial3D:
	var key := "neon_%s_%.1f" % [col.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


## Animated holographic advert panel on upper floors (retro-future streets).
func _build_holo(x: float, w: float, floors: int) -> void:
	if floors < 2 or w < 4.0:
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(minf(w - 1.0, 4.0), 2.2)
	mi.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/fx/holo_ad.gdshader")
	mat.set_shader_parameter("tint", NEON_COLORS[rng.randi() % NEON_COLORS.size()])
	mat.set_shader_parameter("seed", rng.randf() * 100.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x + w * 0.5, 4.0 + 3.2 * (floors - 1) + 1.4, 0.35)
	root.add_child(mi)


# --- crossings & backdrop -------------------------------------------------------------------

func _build_crossing(c: Dictionary) -> void:
	var x0: float = c["x"]
	var x1: float = x0 + float(c["w"])
	var floors_l := 2
	var floors_r := 2
	for lot in data.get("lots", []):
		if absf(float(lot["x"]) + float(lot["w"]) - x0) < 0.05:
			floors_l = int(lot.get("floors", 2))
		if absf(float(lot["x"]) - x1) < 0.05:
			floors_r = int(lot.get("floors", 2))
	# Side walls of the corner buildings, receding down the side street.
	_side_street_wall(x0, floors_l, 1.0)
	_side_street_wall(x1, floors_r, -1.0)
	# Far facade across the end of the side street, lost in the fog.
	var far_z := -34.0
	var fx := x0 - 4.0
	while fx < x1 + 4.0:
		var fw := rng.randf_range(4.0, 7.0)
		var fh := 4.0 + 3.2 * rng.randi_range(1, 4)
		_box(Vector3(fw, fh, 1.0), Vector3(fx + fw * 0.5, fh * 0.5, far_z), _mat("far_%d" % (rng.randi() % 3), _wall_color().darkened(0.45), 0.9))
		if rng.randf() < 0.6:
			var glow := _mat("farwin", Color(0.9, 0.7, 0.45), 0.5)
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.7, 0.4)
			glow.emission_energy_multiplier = 0.9
			_box(Vector3(1.0, 1.2, 0.05), Vector3(fx + fw * 0.5, 5.5 + rng.randi_range(0, 2) * 3.2, far_z + 0.55), glow)
		fx += fw
	# Side-street sidewalks.
	var sidewalk := _material_res("sidewalk", _mat("sidewalk", Color(0.36, 0.35, 0.34), 0.25))
	_box(Vector3(2.2, 0.3, 34.0), Vector3(x0 + 1.1, -0.15, -17.0), sidewalk)
	_box(Vector3(2.2, 0.3, 34.0), Vector3(x1 - 1.1, -0.15, -17.0), sidewalk)
	# Stop line and a street sign / traffic light at the far corner.
	_box(Vector3(x1 - x0 - 4.4, 0.02, 0.3), Vector3((x0 + x1) * 0.5, ROAD_Y + 0.005, -1.0), _mat("zebra", Color(0.75, 0.74, 0.7), 0.35))
	_traffic_light(x1 - 0.6)
	# A couple of street lamps down the side street so it isn't a black void.
	for lz in [-7.0, -19.0]:
		var lx := x0 + 1.2 if lz > -10.0 else x1 - 1.2
		if props_kit.has("lamp_post"):
			var n := _instance(props_kit["lamp_post"]["scene"])
			n.position = Vector3(lx, 0, lz)
			n.rotation.y = PI * 0.5 if lx < (x0 + x1) * 0.5 else -PI * 0.5
			root.add_child(n)
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.7, 0.42)
		sl.light_energy = 4.0
		sl.spot_range = 10.0
		sl.spot_angle = 60.0
		sl.light_volumetric_fog_energy = 2.5
		sl.position = Vector3(lx, 4.9, lz)
		sl.rotation = Vector3(-PI * 0.5, 0, 0)
		root.add_child(sl)


func _side_street_wall(x: float, floors: int, facing: float) -> void:
	var sides: Dictionary = kit.get("side", {})
	var mods: Array = []
	for st in sides:
		mods.append_array(sides[st])
	var ground: Array = mods.filter(func(m): return String(m["id"]).contains("ground"))
	var upper: Array = mods.filter(func(m): return String(m["id"]).contains("upper"))
	var cap: Array = mods.filter(func(m): return String(m["id"]).contains("cap"))
	var z := 0.0
	var seg := 0
	while z > -30.0:
		var f := floors if seg == 0 else rng.randi_range(1, 4)
		var depth := 10.0
		if ground.is_empty():
			var h := 4.0 + 3.2 * f
			_box(Vector3(0.6, h, depth), Vector3(x - facing * 0.3, h * 0.5, z - depth * 0.5),
				_mat("sidewall_%d" % (rng.randi() % 4), _wall_color().darkened(0.25), 0.9))
		else:
			var g: Dictionary = ground[rng.randi() % ground.size()]
			depth = float(g["width"])
			_place_side(g, x, 0.0, z, facing)
			for i in f:
				if not upper.is_empty():
					_place_side(upper[rng.randi() % upper.size()], x, 4.0 + 3.2 * i, z, facing, depth)
			if not cap.is_empty():
				_place_side(cap[rng.randi() % cap.size()], x, 4.0 + 3.2 * f, z, facing, depth)
		z -= depth
		seg += 1


func _place_side(m: Dictionary, x: float, y: float, z: float, facing: float, fit_depth := -1.0) -> void:
	var n := _instance(m["scene"])
	if n == null:
		return
	n.position = Vector3(x, y, z)
	var sc := 1.0
	if fit_depth > 0.0:
		sc = fit_depth / float(m["width"])
	# Modules face +X spanning z in [-width, 0]; mirror for walls that face -X.
	n.scale = Vector3(facing, 1.0, sc)
	root.add_child(n)


func _traffic_light(x: float) -> void:
	var pole := _mat("pole", Color(0.12, 0.13, 0.12), 0.5, 0.8)
	_box(Vector3(0.12, 3.6, 0.12), Vector3(x, 1.8, -0.6), pole)
	_box(Vector3(0.32, 0.9, 0.3), Vector3(x, 3.4, -0.6), _mat("tl_box", Color(0.18, 0.17, 0.08), 0.6, 0.3))
	var lamp := StandardMaterial3D.new()
	var amber := Color(1.0, 0.6, 0.1)
	lamp.albedo_color = amber
	lamp.emission_enabled = true
	lamp.emission = amber
	lamp.emission_energy_multiplier = 4.0
	_box(Vector3(0.16, 0.16, 0.05), Vector3(x, 3.4, -0.44), lamp)
	var ol := OmniLight3D.new()
	ol.light_color = amber
	ol.light_energy = 0.8
	ol.omni_range = 3.0
	ol.position = Vector3(x, 3.4, -0.2)
	ol.set_script(load("res://src/fx/blink.gd"))
	root.add_child(ol)


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
			# Sidewalk props sit against the shopfronts (behind the walker) so they never hide him.
			var z := 3.2 if place == "curb" else (0.35 if place == "wall" else 0.6)
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
	# Sodium lamps downtown; cold LED streetlights as the city turns retro-future.
	sl.light_color = Color(1.0, 0.7, 0.42).lerp(Color(0.62, 0.8, 1.0), float(data.get("neon", 0.0)))
	sl.light_energy = 3.2
	sl.spot_range = 9.0
	sl.spot_angle = 55.0
	sl.light_volumetric_fog_energy = 2.0
	sl.shadow_enabled = true
	sl.position = Vector3(x, 5.0, 2.2)
	sl.rotation = Vector3(-PI * 0.5, 0, 0)
	root.add_child(sl)
