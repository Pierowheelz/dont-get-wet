class_name LevelBuilder
extends RefCounted
## Builds the street (ground, buildings, cover, features, props) from level JSON.
## Cover geometry gets StaticBody3D colliders on the `cover` physics layer — the rain model is driven
## entirely by these colliders, so what you see is what blocks the rain.

const COVER_LAYER := 1 << 1
const SIDEWALK_W := 3.5
const ROAD_Y := -0.16
const AWNING_DEPTH := 2.35
const BALCONY_Y := 4.12   # above the 3.1–3.9 sign band so signs stay visible
const ARCADE_Y := 4.15
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

## Awning designs, keyed by the lot field `awning_style`. Every style shelters the same footprint
## (z 0 → AWNING_DEPTH across the lot, minus tears), stays below the 3.1 m sign band, and crosses the
## walker's line at the same height (see _check_awning_styles); they differ in silhouette so a street
## of awnings doesn't read as one repeated module.
##   eras / aesthetics: where the style may be picked automatically (empty aesthetics = any street)
##   profile: canopy height over depth, see _awning_y ("line", "arc" + bulge, "dome")
##   fabric: "canvas" (stripe_w 0 = solid, hem = front band, seam_w = rib seams), "tin", "acrylic", "enamel"
##   valance: "none", "scallop", "straight", "zigzag"; valance_solid / piping are canvas trims
##   frame: "arms", "brackets" (+ gutter), "chrome" (front tube + ribs), "chrome_edge", "bulbs", "none"
##   ends: closed side cheeks; glow: neon strip under the front edge
const AWNING_STYLES := {
	"classic": {"eras": ["60s"], "aesthetics": ["rundown", "rundown_neon", "neon"],
		"profile": "line", "wall_y": 3.05, "front_y": 2.6, "fabric": "canvas", "stripe_w": 0.45, "hem": 0.0,
		"sag": 0.05, "valance": "scallop", "valance_h": 0.28, "valance_solid": false, "piping": false,
		"frame": "arms", "ends": false, "glow": false},
	"wide_stripe": {"eras": ["60s"], "aesthetics": ["rundown", "rundown_neon", "neon", "outskirts"],
		"profile": "line", "wall_y": 3.05, "front_y": 2.55, "fabric": "canvas", "stripe_w": 1.1, "hem": 0.0,
		"sag": 0.06, "valance": "straight", "valance_h": 0.3, "valance_solid": true, "piping": true,
		"frame": "arms", "ends": false, "glow": false},
	"pennant": {"eras": ["60s"], "aesthetics": [],
		"profile": "line", "wall_y": 2.95, "front_y": 2.65, "fabric": "canvas", "stripe_w": 0.0, "hem": 0.0,
		"sag": 0.03, "valance": "zigzag", "valance_h": 0.36, "valance_solid": false, "piping": true,
		"frame": "arms", "ends": false, "glow": false},
	"dome": {"eras": ["60s"], "aesthetics": [],
		"profile": "dome", "wall_y": 2.83, "front_y": 2.5, "fabric": "canvas", "stripe_w": 0.0, "hem": 0.1, "seam_w": 0.75,
		"sag": 0.0, "valance": "none", "valance_h": 0.0, "valance_solid": false, "piping": false,
		"frame": "none", "ends": true, "glow": false},
	"waterfall": {"eras": ["60s"], "aesthetics": ["rundown", "rundown_neon", "industrial", "outskirts"],
		"profile": "line", "wall_y": 3.05, "front_y": 2.6, "fabric": "canvas", "stripe_w": 0.7, "hem": 0.0,
		"sag": 0.0, "valance": "straight", "valance_h": 0.34, "valance_solid": false, "piping": false,
		"frame": "none", "ends": true, "glow": false},
	"tin": {"eras": ["60s"], "aesthetics": ["industrial", "outskirts"],
		"profile": "line", "wall_y": 2.95, "front_y": 2.65, "fabric": "tin", "stripe_w": 0.0, "hem": 0.0,
		"sag": 0.0, "valance": "none", "valance_h": 0.0, "valance_solid": false, "piping": false,
		"frame": "brackets", "ends": false, "glow": false},
	"bubble": {"eras": ["retro"], "aesthetics": [],
		"profile": "arc", "wall_y": 2.8, "front_y": 2.6, "bulge": 0.1, "fabric": "acrylic", "stripe_w": 0.0,
		"hem": 0.0, "sag": 0.0, "valance": "none", "valance_h": 0.0, "valance_solid": false, "piping": false,
		"frame": "chrome", "ends": false, "glow": true},
	"googie": {"eras": ["retro"], "aesthetics": [],
		"profile": "line", "wall_y": 2.72, "front_y": 2.76, "fabric": "enamel", "stripe_w": 0.0, "hem": 0.0,
		"sag": 0.0, "valance": "straight", "valance_h": 0.2, "valance_solid": false, "piping": false,
		"frame": "chrome_edge", "ends": false, "glow": true},
	"marquee": {"eras": ["retro"], "aesthetics": [],
		"profile": "line", "wall_y": 2.78, "front_y": 2.74, "fabric": "enamel", "stripe_w": 0.0, "hem": 0.0,
		"sag": 0.0, "valance": "straight", "valance_h": 0.3, "valance_solid": false, "piping": false,
		"frame": "bulbs", "ends": false, "glow": false},
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
var _awning_style_at := {}          # lot x -> AWNING_STYLES key, resolved while building
var _prev_awning := [-INF, ""]      # [end x, style] of the last awning built
var _awning_used := {}              # style -> lots given it so far
var gutters: Array = []             # resolved gutter streams, see _resolve_gutters


func build(p_root: Node3D, p_data: Dictionary) -> void:
	root = p_root
	data = p_data
	rng.seed = hash(String(data.get("id", "level")))
	_awning_shader = load("res://src/fx/awning.gdshader")
	assert(_check_awning_styles())
	_load_kits()
	_resolve_gutters()
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
				var s: Dictionary = AWNING_STYLES[_awning_style_at.get(lx, "classic")]
				for sgm in _canvas_spans(lot):
					_cover_fill(img, x0, lx + sgm[0], lx + sgm[1], 0.0, AWNING_DEPTH, func(z): return _awning_y(s, z))
			"balcony":
				_cover_fill(img, x0, lx, lx + lw, 0.0, 2.4, func(_z): return BALCONY_Y)
			"arcade":
				_cover_fill(img, x0, lx, lx + lw, 0.0, 2.9, func(_z): return ARCADE_Y)
			"canopy":
				_cover_fill(img, x0, lx + 0.15, lx + lw - 0.15, -0.2, 3.3, func(_z): return 3.55)
	var tex := ImageTexture.create_from_image(img)
	return [tex, Vector4(x0, COVER_Z0, w / COVER_RES, COVER_Z1 - COVER_Z0)]


## Local [x0, x1] spans of an awning lot's canvas, around its tears.
static func _canvas_spans(lot: Dictionary) -> Array:
	var segs := [[0.0, float(lot["w"])]]
	for t in lot.get("tears", []):
		var ns: Array = []
		for sgm in segs:
			if t[0] > sgm[0]: ns.append([sgm[0], minf(float(t[0]), sgm[1])])
			if t[1] < sgm[1]: ns.append([maxf(float(t[1]), sgm[0]), sgm[1]])
		segs = ns
	return segs


## Gutter streams. Gameplay only knows a stream's x; this decides what it pours from, so the water
## always visibly comes out of something:
##   "crack" / "snapped": a gooseneck downpipe that comes off the facade above the awnings and
##     reaches out to throw roof water clear of them, split (crack) or broken off (snapped) right
##     over the walkway; the water falls past an awning's end or through a tear.
##   "collapse": the canvas beside the gap has lost its frame; its corner has slumped a little way
##     out over the gap and everything the awning catches spills off that corner. Canvas only sags
##     so far, so the stream moves to the corner (COLLAPSE_REACH past the edge), not the other way.
## A feature may name `kind` and `side` (+1: the source reaches the stream from lower x, -1: from
## higher x); otherwise a street cycles through the kinds. Each entry: {x, kind, side} plus, for
## a collapse, lot_x (the awning's lot), edge (world x of the slumped canvas edge), z and top.
## Level takes the streams' gameplay x from here.
const GUTTER_KINDS := ["snapped", "collapse", "crack"]
const GUTTER_REACH := 1.0        # furthest a collapse looks for canvas beside its gap
const COLLAPSE_REACH := 0.3      # how far the slumped corner hangs out past the canvas edge
const COLLAPSE_SPAN := 1.4       # length of canvas, back from the edge, that slumps
const COLLAPSE_DROP := 0.36      # how far the slumped corner falls (stays above the walker's umbrella)
const COLLAPSE_Z := 1.9          # how far back toward the wall the slumped corner is pulled


func _resolve_gutters() -> void:
	var spans: Array = []   # [x0, x1, lot x] of every awning's canvas, world x
	for lot in data.get("lots", []):
		if lot.get("cover", "none") == "awning":
			for sp in _canvas_spans(lot):
				spans.append([float(lot["x"]) + sp[0], float(lot["x"]) + sp[1], float(lot["x"])])
	var fs: Array = data.get("features", []).filter(func(f): return f["type"] == "gutter")
	fs.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	for i in fs.size():
		var f: Dictionary = fs[i]
		var x := float(f["x"])
		var left: Array = []    # nearest canvas ending before x, within reach
		var right: Array = []
		for sp in spans:
			if sp[0] < x and x < sp[1]:
				push_warning("level %s: gutter at x=%.2f falls on intact awning canvas" % [data.get("id", "?"), x])
			if sp[1] <= x and x - sp[1] <= GUTTER_REACH and (left.is_empty() or sp[1] > left[1]):
				left = sp
			if sp[0] >= x and sp[0] - x <= GUTTER_REACH and (right.is_empty() or sp[0] < right[0]):
				right = sp
		var g := {"x": x, "kind": String(f.get("kind", GUTTER_KINDS[i % GUTTER_KINDS.size()])),
			"side": int(f.get("side", 1 if i % 2 == 0 else -1))}
		if not GUTTER_KINDS.has(g["kind"]):
			push_warning("level %s: unknown gutter kind '%s' at x=%.2f" % [data.get("id", "?"), g["kind"], x])
			g["kind"] = "snapped"
		if g["kind"] == "collapse":
			if (left if g["side"] > 0 else right).is_empty() and not f.has("side"):
				g["side"] = -g["side"]
			var own: Array = left if g["side"] > 0 else right
			if own.is_empty():
				g["kind"] = "snapped"
			else:
				g["lot_x"] = own[2]
				g["edge"] = own[1] if g["side"] > 0 else own[0]
				g["planned_x"] = x
				g["x"] = float(g["edge"]) + g["side"] * COLLAPSE_REACH
		gutters.append(g)


## The collapses slumping on the awning of the lot at x (resolved gutters). Only cloth on light
## arms can slump; on any other awning the gutter falls back to a broken pipe.
func _collapses_on(x: float, s: Dictionary) -> Array:
	var out: Array = []
	for g in gutters:
		if g["kind"] != "collapse" or not is_equal_approx(float(g["lot_x"]), x):
			continue
		if s["fabric"] != "canvas" or not ["arms", "none"].has(s["frame"]):
			g["kind"] = "snapped"
			g["x"] = g["planned_x"]
			continue
		g["z"] = COLLAPSE_Z
		g["top"] = _awning_y(s, AWNING_DEPTH) - COLLAPSE_DROP - 0.04
		out.append(g)
	return out


func _cover_fill(img: Image, x0: float, a: float, b: float, z0: float, z1: float, height: Callable) -> void:
	var ia := int((a - x0) * COVER_RES)
	var ib := int((b - x0) * COVER_RES)
	for ix in range(maxi(ia, 0), mini(ib, img.get_width())):
		for iz in img.get_height():
			var z := COVER_Z0 + (iz + 0.5) / COVER_RES_Z
			if z >= z0 and z <= z1:
				var y: float = height.call(z)
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
	var era := "60s"
	var retro: Dictionary = _kits.get("retro", {})
	if not retro.is_empty() and rng.randf() < float(data.get("neon", 0.0)):
		var st: String = lot.get("style", "wall")
		if retro.get("ground", {}).has(st):
			kit = retro
			era = "retro"
			if not lot.has("sign") and st != "vacant":
				lot = lot.duplicate()
				lot["sign"] = RETRO_FILLER_NAMES[rng.randi() % RETRO_FILLER_NAMES.size()]
				lot["neon"] = true
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
			var aw := _pick_awning_style(lot, era)
			_awning_style_at[x] = aw
			_build_awning(x, w, lot.get("tears", []), lot.get("awning_color", "red"), AWNING_STYLES[aw],
				NEON_COLORS[_lot_hash(x, "glow") % NEON_COLORS.size()], _collapses_on(x, AWNING_STYLES[aw]))
		"balcony":
			_build_slab(x, w, BALCONY_Y, 2.4, false)
		"arcade":
			_build_slab(x, w, ARCADE_Y, 2.9, true)
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
	# Inset from the lot edges so its faces never sit coplanar with kit/side-wall faces (z-fighting).
	_box(Vector3(maxf(w - 0.24, 0.1), height - 0.05, 8.0), Vector3(x + w * 0.5, height * 0.5 - 0.03, -4.7),
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

func _lot_hash(x: float, salt: String) -> int:
	# Stable per lot and independent of the shared rng, so awning choices never shift the level's
	# other random choices (facade modules, signs, holograms).
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s:%s:%.2f" % [data.get("id", "level"), salt, x])
	return r.randi()


func _pick_awning_style(lot: Dictionary, era: String) -> String:
	var x: float = lot["x"]
	var name: String = lot.get("awning_style", "")
	if name != "" and not AWNING_STYLES.has(name):
		push_warning("level %s: unknown awning_style '%s' at x=%s" % [data.get("id", "?"), name, x])
		name = ""
	if name == "":
		var aes: String = data.get("aesthetic", "rundown")
		var pool: Array = AWNING_STYLES.keys().filter(func(k):
			var s: Dictionary = AWNING_STYLES[k]
			return s["eras"].has(era) and (s["aesthetics"].is_empty() or s["aesthetics"].has(aes)))
		if pool.size() > 1 and absf(float(_prev_awning[0]) - x) < 0.05:
			pool.erase(_prev_awning[1])
		# Shuffle bag: the least-used styles so far, so a street gets an even mix without clumps.
		var least: int = pool.map(func(k): return _awning_used.get(k, 0)).min()
		pool = pool.filter(func(k): return _awning_used.get(k, 0) == least)
		name = pool[_lot_hash(x, "awning") % pool.size()]
	_awning_used[name] = _awning_used.get(name, 0) + 1
	_prev_awning = [x + float(lot["w"]), name]
	return name


## Canopy height at depth z (0 = wall, AWNING_DEPTH = front edge). The mesh, colliders, rain cover
## map and drip line all read this, so rain stops exactly where the canopy is drawn.
func _awning_y(s: Dictionary, z: float) -> float:
	var t := clampf(z / AWNING_DEPTH, 0.0, 1.0)
	var wy: float = s["wall_y"]
	var fy: float = s["front_y"]
	match s["profile"]:
		"arc":
			return lerpf(wy, fy, t) + float(s["bulge"]) * sin(PI * t)
		"dome":
			return fy + (wy - fy) * sqrt(1.0 - t * t)
	return lerpf(wy, fy, t)


## Depths of the canopy's mesh rows / collider joints, bunched toward the front edge where the dome
## profile turns down steeply.
func _awning_zs(s: Dictionary) -> PackedFloat32Array:
	var zs := PackedFloat32Array()
	for j in 13:
		var v := j / 12.0
		zs.append(AWNING_DEPTH * (1.0 - (1.0 - v) * (1.0 - v)))
	return zs


## Gameplay rain rays rise in the x-y plane at the walker's z, so where a taller awning meets a lower
## one downwind they slip through the step. Holding every style to the classic's height across the
## walker's band (z 1.4-1.8), and the front edge to the umbrella-safe range, keeps sheltering
## identical for all styles.
func _check_awning_styles() -> bool:
	for k in AWNING_STYLES:
		var s: Dictionary = AWNING_STYLES[k]
		for z in [1.4, 1.6, 1.8]:
			assert(absf(_awning_y(s, z) - _awning_y(AWNING_STYLES["classic"], z)) < 0.06,
				"awning style %s leaves the walker's band at z=%.1f" % [k, z])
		var fy := _awning_y(s, AWNING_DEPTH)
		assert(fy >= 2.5 and fy <= 2.8, "awning style %s front edge %.2f outside 2.5-2.8" % [k, fy])
		for z in _awning_zs(s):
			assert(_awning_y(s, z) <= 3.05, "awning style %s rises into the sign band" % k)
	return true


## Bottom of whatever hangs at the front edge: where the drip line starts.
func _awning_drip_y(s: Dictionary) -> float:
	return _awning_y(s, AWNING_DEPTH) - float(s["valance_h"]) - 0.02


func _build_awning(x: float, w: float, tears: Array, color_name: String, s: Dictionary, glow_col: Color,
		collapses: Array) -> void:
	var cols: Array = AWNING_COLORS.get(color_name, AWNING_COLORS["red"])
	# Drawn for every style so the shared rng sequence (facades, signs) doesn't depend on the style.
	var grime := rng.randf_range(0.3, 0.8)
	var mats := _awning_materials(s, cols, w, grime)
	# Split into segments around tears (tears are local [x0, x1]).
	var segs: Array = []
	var sx := 0.0
	var sorted_tears := tears.duplicate()
	sorted_tears.sort_custom(func(a, b): return a[0] < b[0])
	for t in sorted_tears:
		segs.append([sx, float(t[0])])
		sx = float(t[1])
	segs.append([sx, w])
	var zs := _awning_zs(s)
	for sg in segs:
		var a: float = x + sg[0]
		var b: float = x + sg[1]
		if b - a < 0.05:
			continue
		var slump := {}         # {right: the slumping edge is the segment's right end, reach}
		for g in collapses:
			if is_equal_approx(float(g["edge"]), a) or is_equal_approx(float(g["edge"]), b):
				slump = {"right": is_equal_approx(float(g["edge"]), b), "reach": absf(float(g["x"]) - float(g["edge"]))}
		var mi := MeshInstance3D.new()
		mi.mesh = _awning_mesh(s, sg[0], b - a, w, s["ends"] and sg[0] <= 0.0 and not (slump and not slump["right"]),
			s["ends"] and sg[1] >= w and not (slump and slump["right"]), slump)
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mats[i])
		mi.position = Vector3(a, 0.0, 0.0)
		root.add_child(mi)
		for j in zs.size() - 1:
			var p0 := Vector2(zs[j], _awning_y(s, zs[j]))
			var d := Vector2(zs[j + 1], _awning_y(s, zs[j + 1])) - p0
			var mid := p0 + d * 0.5
			_cover_box(Vector3(b - a, 0.06, d.length() + 0.02),
				Transform3D(Basis.from_euler(Vector3(atan2(-d.y, d.x), 0, 0)), Vector3((a + b) * 0.5, mid.y, mid.x)))
		var span := minf(COLLAPSE_SPAN, b - a)
		_drips(a + (span if slump and not slump["right"] else 0.0), b - (span if slump and slump["right"] else 0.0),
			_awning_drip_y(s), AWNING_DEPTH + 0.05)
	# Torn flaps hanging into tears, unless the canvas there has slumped into the tear instead.
	var fy := _awning_y(s, AWNING_DEPTH)
	for t in sorted_tears:
		if collapses.any(func(g): return is_equal_approx(float(g["edge"]), x + float(t[0]))):
			continue
		var flap := _box(Vector3((float(t[1]) - float(t[0])) * 0.35, 0.6, 0.02),
			Vector3(x + float(t[0]) + 0.2, fy - 0.2, AWNING_DEPTH - 0.4), mats[0])
		flap.rotation = Vector3(0.3, 0, 0.25)
	_awning_frame(s, x, w, glow_col, collapses)


## [canopy material, valance material], matching the mesh's surfaces.
func _awning_materials(s: Dictionary, cols: Array, w: float, grime: float) -> Array:
	match s["fabric"]:
		"acrylic":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(cols[0].lightened(0.3), 0.42)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.06
			m.metallic_specular = 1.0
			m.rim_enabled = true
			m.rim = 0.6
			return [m, m]
		"enamel":
			var top := _mat("enamel_%s" % cols[1].to_html(), cols[1], 0.3, 0.15)
			top.cull_mode = BaseMaterial3D.CULL_DISABLED
			var fascia := _mat("enamel_%s" % cols[0].to_html(), cols[0].lightened(0.25), 0.25, 0.2)
			fascia.cull_mode = BaseMaterial3D.CULL_DISABLED
			return [top, fascia]
	var mat := ShaderMaterial.new()
	mat.shader = _awning_shader
	mat.set_shader_parameter("color_a", cols[0])
	mat.set_shader_parameter("color_b", cols[1])
	mat.set_shader_parameter("width", w)
	var sw: float = s["stripe_w"]
	# Whole number of stripe pairs across the awning so both ends finish on a full stripe.
	mat.set_shader_parameter("stripe_w", w / maxf(1.0, roundf(w / sw)) if sw > 0.0 else 0.0)
	mat.set_shader_parameter("hem", s["hem"])
	mat.set_shader_parameter("seam_w", s.get("seam_w", 0.0))
	mat.set_shader_parameter("valance_solid", s["valance_solid"])
	mat.set_shader_parameter("piping", s["piping"])
	mat.set_shader_parameter("tin", s["fabric"] == "tin")
	mat.set_shader_parameter("grime", grime)
	return [mat, mat]


## Canopy (surface 0, plus closed side cheeks) and valance (surface 1, if the style has one) for one
## tear-free segment. Local x 0..w; u0 is the segment's offset within the full awning so stripes and
## corrugations line up across tears. UV.y: 0..1 wall to front on the canopy, 1..2 down the valance.
## `slump` ({right, reach}, or empty) lets the canvas at one end fall away from its frame: its front
## corner drops, swings back toward the wall and hangs out `reach` past the end, where the stream is.
func _awning_mesh(s: Dictionary, u0: float, w: float, full_w: float, end_l: bool, end_r: bool,
		slump := {}) -> ArrayMesh:
	var zs := _awning_zs(s)
	var tin: bool = s["fabric"] == "tin"
	var sag: float = s["sag"]
	var vs: Array = [0.0]                # arc-length fraction of each row, for UV.y
	for j in range(1, zs.size()):
		vs.append(vs[j - 1] + Vector2(zs[j] - zs[j - 1], _awning_y(s, zs[j]) - _awning_y(s, zs[j - 1])).length())
	for j in vs.size():
		vs[j] /= vs[-1]
	var pos := func(xl: float, j: int) -> Vector3:
		var v: float = vs[j]
		var y := _awning_y(s, zs[j]) - sag * (sin(v * PI) + 0.3 * sin(xl / w * PI * maxf(1.0, w / 1.5)) * v)
		if tin:
			y += 0.025 * sin((u0 + xl) / 0.2 * TAU)
		var p := Vector3(xl, y, zs[j])
		if slump:
			p += _slump_offset(slump, xl, w, v)
		return p
	var nx := maxi(2, int(w / (0.04 if tin else 0.25)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nx:
		var xa := w * i / nx
		var xb := w * (i + 1) / nx
		for j in zs.size() - 1:
			_quad(st, pos.call(xa, j), pos.call(xb, j), pos.call(xb, j + 1), pos.call(xa, j + 1),
				Vector2((u0 + xa) / full_w, vs[j]), Vector2((u0 + xb) / full_w, vs[j + 1]))
	# Side cheeks: fan from the wall at front-edge height up to the profile, plus a wedge down to the
	# valance hem. Inset so neighbouring awnings' cheeks are never coplanar.
	var fy := _awning_y(s, AWNING_DEPTH)
	for e in [[end_l, 0.01], [end_r, w - 0.01]]:
		if not e[0]:
			continue
		var ex: float = e[1]
		var anchor := Vector3(ex, fy, 0.0)
		for j in zs.size() - 1:
			var p0 := Vector3(ex, _awning_y(s, zs[j]), zs[j])
			var p1 := Vector3(ex, _awning_y(s, zs[j + 1]), zs[j + 1])
			st.set_uv(Vector2((u0 + ex) / full_w, 0.5)); st.add_vertex(anchor)
			st.set_uv(Vector2((u0 + ex + zs[j]) / full_w, vs[j])); st.add_vertex(p0)
			st.set_uv(Vector2((u0 + ex + zs[j + 1]) / full_w, vs[j + 1])); st.add_vertex(p1)
		var front := Vector3(ex, fy, AWNING_DEPTH)
		st.set_uv(Vector2((u0 + ex) / full_w, 0.5)); st.add_vertex(anchor)
		st.set_uv(Vector2((u0 + ex + AWNING_DEPTH) / full_w, 1.0)); st.add_vertex(front)
		st.set_uv(Vector2((u0 + ex + AWNING_DEPTH) / full_w, 1.0)); st.add_vertex(front + Vector3(0, -float(s["valance_h"]), 0.03))
	st.generate_normals()
	var mesh := st.commit()
	var vh: float = s["valance_h"]
	if s["valance"] == "none":
		return mesh
	# Valance: hangs from the front edge, kicked slightly outward at the hem.
	var last := zs.size() - 1
	var vnx := maxi(2, int(w / 0.05))
	var hem := func(xl: float) -> float:
		var p := u0 + xl
		match s["valance"]:
			"scallop":
				return vh - absf(sin(p / 0.45 * PI)) * 0.06
			"zigzag":
				return vh - absf(fposmod(p / 0.3, 1.0) - 0.5) * 2.0 * 0.12
		return vh
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in vnx:
		var xa := w * i / vnx
		var xb := w * (i + 1) / vnx
		var pa: Vector3 = pos.call(xa, last)
		var pb: Vector3 = pos.call(xb, last)
		var ha: float = hem.call(xa) * _valance_left(slump, xa, w)
		var hb: float = hem.call(xb) * _valance_left(slump, xb, w)
		st.set_uv(Vector2((u0 + xa) / full_w, 1.0)); st.add_vertex(pa)
		st.set_uv(Vector2((u0 + xb) / full_w, 1.0)); st.add_vertex(pb)
		st.set_uv(Vector2((u0 + xb) / full_w, 1.0 + hb / vh)); st.add_vertex(pb + Vector3(0, -hb, 0.03))
		st.set_uv(Vector2((u0 + xa) / full_w, 1.0)); st.add_vertex(pa)
		st.set_uv(Vector2((u0 + xb) / full_w, 1.0 + hb / vh)); st.add_vertex(pb + Vector3(0, -hb, 0.03))
		st.set_uv(Vector2((u0 + xa) / full_w, 1.0 + ha / vh)); st.add_vertex(pa + Vector3(0, -ha, 0.03))
	st.generate_normals()
	return st.commit(mesh)


func _slump_k(slump: Dictionary, xl: float, w: float, v: float) -> float:
	var d: float = (w - xl) if slump["right"] else xl
	var t := clampf(1.0 - d / minf(COLLAPSE_SPAN, w), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t) * v


func _slump_offset(slump: Dictionary, xl: float, w: float, v: float) -> Vector3:
	var k := _slump_k(slump, xl, w, v)
	return Vector3((1.0 if slump["right"] else -1.0) * float(slump["reach"]) * k * k * k,
		-COLLAPSE_DROP * k * k, -(AWNING_DEPTH - COLLAPSE_Z) * k * k)


## Fraction of the valance still hanging at xl: it has torn away along the slumped corner.
func _valance_left(slump: Dictionary, xl: float, w: float) -> float:
	return 1.0 if slump.is_empty() else 1.0 - _slump_k(slump, xl, w, 1.0)


func _awning_frame(s: Dictionary, x: float, w: float, glow_col: Color, collapses: Array) -> void:
	var wy := _awning_y(s, 0.0)
	var fy := _awning_y(s, AWNING_DEPTH)
	var chrome := _mat("chrome", Color(0.82, 0.84, 0.88), 0.12, 1.0)
	match s["frame"]:
		"arms":
			var frame := _mat("frame", Color(0.15, 0.15, 0.15), 0.4, 0.8)
			for fx in [x + 0.1, x + w - 0.1]:
				if collapses.any(func(g): return absf(float(g["edge"]) - fx) < 0.2):
					# The arm that let go: snapped part-way out, the outer piece hanging off it.
					var mid := Vector2(AWNING_DEPTH * 0.45, lerpf(wy, fy, 0.45) - 0.05)
					_strut(fx, Vector2(0.0, wy - 0.05), mid, 0.04, frame)
					_strut(fx, mid, mid + Vector2(0.3, -0.62), 0.035, frame)
					continue
				_strut(fx, Vector2(0.0, wy - 0.05), Vector2(AWNING_DEPTH, fy - 0.05), 0.04, frame)
		"brackets":
			# Rusty steel knee braces kept close to the wall (clear of the walker), and a front gutter.
			var steel := _mat("tin_bracket", Color(0.22, 0.15, 0.1), 0.7, 0.5)
			var n := maxi(1, ceili(w / 3.0))
			for i in n + 1:
				var bx := x + 0.15 + (w - 0.3) * i / n
				_strut(bx, Vector2(0.0, wy - 0.8), Vector2(0.95, _awning_y(s, 0.95) - 0.04), 0.06, steel)
			_box(Vector3(w, 0.09, 0.1), Vector3(x + w * 0.5, fy - 0.03, AWNING_DEPTH + 0.03), steel)
		"chrome":
			_box(Vector3(w, 0.06, 0.06), Vector3(x + w * 0.5, fy, AWNING_DEPTH), chrome)
			var zs := _awning_zs(s)
			var n := maxi(1, roundi(w / 1.5))
			for i in n + 1:
				var rx := x + 0.04 + (w - 0.08) * i / n
				for j in zs.size() - 1:
					_strut(rx, Vector2(zs[j], _awning_y(s, zs[j]) + 0.01), Vector2(zs[j + 1], _awning_y(s, zs[j + 1]) + 0.01), 0.035, chrome)
		"chrome_edge":
			_box(Vector3(w, 0.035, 0.05), Vector3(x + w * 0.5, fy + 0.01, AWNING_DEPTH + 0.01), chrome)
		"bulbs":
			_marquee_bulbs(x, w, fy, float(s["valance_h"]))
	if s["glow"]:
		var strip := _box(Vector3(w - 0.1, 0.03, 0.03), Vector3(x + w * 0.5, _awning_drip_y(s) + 0.005, AWNING_DEPTH + 0.04),
			_neon_mat(glow_col.lerp(Color(1, 1, 1), 0.35), 2.4))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Two staggered rows of lit bulbs on a marquee fascia, as one mesh.
func _marquee_bulbs(x: float, w: float, fy: float, fascia_h: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.035
	for row in 2:
		var by := fy - fascia_h * (0.3 + 0.4 * row)
		var bx := 0.15 + 0.14 * row
		while bx < w - 0.12:
			var c := Vector3(bx, by, AWNING_DEPTH + 0.05)
			_quad(st, c + Vector3(-r, -r, 0), c + Vector3(r, -r, 0), c + Vector3(r, r, 0), c + Vector3(-r, r, 0),
				Vector2.ZERO, Vector2.ONE)
			bx += 0.28
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var bulb: StandardMaterial3D = _neon_mat(Color(1.0, 0.86, 0.6), 3.0).duplicate()
	bulb.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = bulb
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, 0.0, 0.0)
	root.add_child(mi)


## A square bar between two (z, y) points in the plane x = const.
func _strut(x: float, p0: Vector2, p1: Vector2, thick: float, mat: Material) -> void:
	var d := p1 - p0
	var bar := _box(Vector3(thick, thick, d.length()), Vector3(x, (p0.y + p1.y) * 0.5, (p0.x + p1.x) * 0.5), mat)
	bar.rotation.x = atan2(-d.y, d.x)


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
	# Pale painted concrete with a moulded fascia, lit from below by the shopfront, so it reads
	# as a balcony/arcade and not a black void.
	var conc := _mat("slab_paint", Color(0.62, 0.58, 0.52), 0.7)
	conc.uv1_triplanar = true
	var fascia := _mat("slab_fascia", Color(0.72, 0.68, 0.6), 0.6)
	_box(Vector3(w, 0.22, depth), Vector3(x + w * 0.5, y, depth * 0.5), conc)
	_box(Vector3(w, 0.34, 0.14), Vector3(x + w * 0.5, y - 0.02, depth - 0.07), fascia)
	_box(Vector3(w, 0.06, 0.06), Vector3(x + w * 0.5, y + 0.95, depth - 0.1), _mat("rail", Color(0.12, 0.12, 0.12), 0.5, 0.7))
	var px := x + 0.15
	while px <= x + w:
		_box(Vector3(0.03, 0.8, 0.03), Vector3(px, y + 0.52, depth - 0.1), _mat("rail", Color(0.12, 0.12, 0.12), 0.5, 0.7))
		px += 0.3
	_cover_box(Vector3(w, 0.28, depth), Transform3D(Basis(), Vector3(x + w * 0.5, y, depth * 0.5)))
	_drips(x, x + w, y - 0.15, depth + 0.02)
	var under := OmniLight3D.new()
	under.light_color = Color(1.0, 0.8, 0.6)
	under.light_energy = 0.5
	under.omni_range = 3.0
	under.light_volumetric_fog_energy = 0.0
	under.position = Vector3(x + w * 0.5, y - 0.6, depth * 0.6)
	root.add_child(under)
	if columns:
		var cx := x + 0.3
		while cx < x + w:
			_box(Vector3(0.3, y, 0.3), Vector3(cx, y * 0.5, depth - 0.2), conc)
			cx += 3.5


const RETRO_FILLER_NAMES := ["OPEN", "VACANCY", "BAR", "LIVE", "EAT", "TV", "ROOMS", "GAMES", "CAFE", "NO VACANCY"]
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
	# White-hot tube core with a coloured halo (light + bloom) keeps the lettering readable.
	mi.material_override = _neon_mat(col.lerp(Color(1, 1, 1), 0.55), 2.6)
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
			li.material_override = _neon_mat(col2.lerp(Color(1, 1, 1), 0.55), 3.0)
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
	# Nudge out into the side street so the wall face isn't coplanar with the facade modules' ends.
	n.position = Vector3(x + facing * 0.04, y, z)
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
	for c in data.get("crossings", []):
		if x > float(c["x"]) - 0.4 and x < float(c["x"]) + float(c["w"]) + 0.4:
			return     # never in the roadway
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
	sl.shadow_enabled = not Game.settings.get("low_quality", false)
	sl.position = Vector3(x, 5.0, 2.2)
	sl.rotation = Vector3(-PI * 0.5, 0, 0)
	root.add_child(sl)
