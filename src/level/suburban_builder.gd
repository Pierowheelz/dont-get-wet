class_name SuburbanBuilder
extends RefCounted
## The edge of town (`aesthetic: "suburban"`): a 1960s suburb past the bypass that has been left
## behind, drawn in code and called from LevelBuilder like the roadside's. A concrete footpath with a
## grass nature strip between it and the kerb; lots, all set behind the footpath line (z 0):
##   house         brick-veneer or weatherboard, set back behind a front garden and a low fence
##   flats         a three-storey walk-up block of flats over a car park strip
##   vacant_block  an overgrown block behind a sagging wire fence, an agent's board gone grey
##   park          a strip of park: a swing set with one swing gone, a bench, a bin, trees behind
##   church_hall   a brick hall on the footpath line; `cover: "porch"` puts a porch over the footpath at
##                 its door (CountryBuilder's porch: full cover)
##   bus_shelter   a bus shelter on the footpath, its glass cracked, its timetable faded; give it
##                 `cover: "shelter"` (CountryBuilder's shelter roof numbers: full cover)
##   overbridge    a railway bridge across the street on concrete abutments; `cover: "bridge"` (full
##                 cover, the visual rain stops under it from the wall out to the camera)
##   inn           a 1960s brick corner pub (`sign`, e.g. "ROYAL HOTEL"); its door is at the lot's x + 4
## Kit lots (`shop_lit`, `shop_dark`, `shuttered`, ...) are the shopping strip, under the awning
## styles this aesthetic picks (verandas). Any lot with `cover: "trees"` gets street trees on the
## nature strip (`street_tree_a/b.glb` when present) and its crown's gameplay from TreeCover.
## `shelter` and `porch` cover are CountryBuilder's (its colliders, drips and rain map, any street);
## only `bridge` is this builder's.
##
## Lot fields (all optional; left out, the lot picks by a stable hash):
##   state  "lived" (lit windows, a car in the carport), "empty" (dark, overgrown, an agent's board)
##          or "boarded" (windows boarded, gutter hanging, paint peeling)
##   walls  "brick" or "weatherboard" (houses)
##   fence  "brick", "picket", "hedge", "wire" or "none"
##   drive  "left", "right" or "none": a carport and driveway that side, its crossover over the
##          nature strip and a dropped kerb
##   car    "sedan" (in the carport), "wreck" (a rusted-out car on the driveway) or "none"
##   sign   a house's or a block's agent's board ("FOR SALE", "SOLD"); a hall's, the flats' or the pub's name
##   thin   0..1 how far the suburb has thinned out here toward the country: houses sit in wider
##          yards, the rooftops behind give way to a paddock with a wire fence and gums
## Props: `lamp_post` is a power pole with a sodium lamp on its arm (`"lamp": "out"` or `"flicker"`
## for a dead or failing one), `power_pole` one without; wires run between them.
## Runs inside LevelBuilder.build, possibly on a worker thread: it only adds nodes.

const STYLES := ["house", "flats", "vacant_block", "park", "church_hall", "bus_shelter", "overbridge", "inn"]
const PROPS := ["lamp_post", "power_pole"]
const PATH_Z1 := 2.4          # the footpath runs from the fence line to here
const STRIP_Z1 := 3.34        # then the nature strip to the kerb
const SET_BACK := 7.0         # a house's front wall stands this far behind the fence line
const TREE_Z := 2.9           # street trees stand on the nature strip
const POLE_Z := 3.12
const BRIDGE_Y := 4.8         # underside of the rail overbridge's girders
const BRIDGE_Z0 := -0.6       # its abutment face, behind the footpath
const BRIDGE_Z1 := 16.0       # it runs on over the road and past the camera
const TREE_MODELS := ["street_tree_a", "street_tree_b"]   # res://assets/country/, docs/CONTRACTS.md §10

const BRICKS := [Color(0.62, 0.34, 0.22), Color(0.74, 0.62, 0.47), Color(0.4, 0.24, 0.18), Color(0.56, 0.42, 0.33)]
const BOARDS := [Color(0.82, 0.78, 0.66), Color(0.62, 0.7, 0.6), Color(0.78, 0.74, 0.7), Color(0.66, 0.62, 0.52)]
const TRIMS := [Color(0.85, 0.83, 0.76), Color(0.2, 0.3, 0.24), Color(0.55, 0.2, 0.14), Color(0.86, 0.84, 0.8)]
const TILES := [Color(0.48, 0.23, 0.16), Color(0.3, 0.31, 0.32), Color(0.34, 0.22, 0.16), Color(0.42, 0.28, 0.22)]
const IRON := [Color(0.24, 0.32, 0.27), Color(0.45, 0.17, 0.13), Color(0.47, 0.48, 0.47), Color(0.36, 0.3, 0.24)]


## Whether this street's builder draws `style` here instead of the kit.
static func draws(b: LevelBuilder, style: String) -> bool:
	return b.suburban() and STYLES.has(style)


## A stable roll for a lot: the same street always dresses the same way.
static func _rng(b: LevelBuilder, x: float, salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = b._lot_hash(x, "suburb:" + salt)
	return r


static func _pick(lot: Dictionary, key: String, options: Array, r: RandomNumberGenerator, weights := []) -> String:
	if lot.has(key):
		return String(lot[key])
	if weights.is_empty():
		return options[r.randi() % options.size()]
	var t := r.randf() * float(weights.reduce(func(a, c): return a + c, 0.0))
	for i in options.size():
		t -= float(weights[i])
		if t <= 0.0:
			return options[i]
	return options[-1]


static func lot(b: LevelBuilder, x: float, w: float, style: String, floors: int, d: Dictionary) -> void:
	var r := _rng(b, x, style)
	var sts := {}
	match style:
		"house":
			_house(b, sts, x, w, d, r)
		"flats":
			_flats(b, sts, x, w, maxi(floors, 1), d, r)
		"vacant_block":
			_vacant_block(b, sts, x, w, d, r)
		"park":
			_park(b, sts, x, w, d, r)
		"church_hall":
			_church_hall(b, sts, x, w, d, r)
		"bus_shelter":
			_bus_shelter(b, sts, x, w, d, r)
		"overbridge":
			_overbridge(b, sts, x, w, d)
		"inn":
			_pub(b, sts, x, w, maxi(floors, 1), d)
	RoadsideBuilder._commit(b, sts)
	var cover := String(d.get("cover", "none"))
	var wants: String = {"bus_shelter": "shelter", "church_hall": "porch", "overbridge": "bridge"}.get(style, "")
	if cover in ["shelter", "porch", "bridge"] and cover != wants:
		push_warning("level %s: %s at x=%.1f can't be cover '%s'" % [b.data.get("id", "?"), style, x, cover])


## Street trees for a lot with `cover: "trees"`, on any lot style. Called for every suburban lot.
static func cover(b: LevelBuilder, d: Dictionary) -> void:
	if String(d.get("cover", "none")) != "trees":
		return
	var x := float(d["x"])
	var w := float(d["w"])
	var node := TreeCover.build(b, x, w, {"crown": false})   # the crown's gameplay; the trees are drawn here
	var n := maxi(1, roundi(w / 9.0))
	var r := _rng(b, x, "trees")
	for i in n:
		var tx := x + w * (i + 0.5) / n + r.randf_range(-0.6, 0.6)
		street_tree(b, node, tx, x, x + w, r.randi() % 2, r)


# --- the street: footpath, nature strip, kerb ---------------------------------------------------------

## The ground from x0 to x1 between crossings: footpath, nature strip (cut by driveway crossovers),
## kerb and gutter, with leaves and litter lying in the gutter; and the yards behind, as far back as
## the eye goes.
static func ground(b: LevelBuilder, x0: float, x1: float) -> void:
	var sts := {}
	var path := _m(b, "footpath", Color(0.5, 0.49, 0.46), 0.55)
	var grass := _m(b, "verge", Color(0.24, 0.3, 0.17), 0.9)
	var kerb := _m(b, "kerb", Color(0.56, 0.55, 0.52), 0.5)
	var crossover := _m(b, "crossover", Color(0.46, 0.45, 0.42), 0.6)
	RoadsideBuilder._add(sts, path, x0, x1, -0.3, 0.0, -0.05, PATH_Z1)
	# Joints across the footpath every 1.5 m: what makes it read as poured concrete.
	var joint := _m(b, "path_joint", Color(0.3, 0.3, 0.29), 0.6)
	var jx := ceilf(x0 / 1.5) * 1.5
	while jx < x1:
		RoadsideBuilder._add(sts, joint, jx - 0.012, jx + 0.012, 0.0, 0.004, 0.0, PATH_Z1)
		jx += 1.5
	var cuts: Array = driveways(b).filter(func(dw): return dw[1] > x0 and dw[0] < x1)
	var gx := x0
	for dw: Array in cuts + [[x1, x1]]:
		var a := maxf(float(dw[0]), x0)
		if a > gx:
			RoadsideBuilder._add(sts, grass, gx, a, -0.3, 0.035, PATH_Z1, STRIP_Z1)
		if dw[0] < dw[1]:
			RoadsideBuilder._add(sts, crossover, a, minf(float(dw[1]), x1), -0.3, 0.008, PATH_Z1, STRIP_Z1 + 0.16)
		gx = minf(float(dw[1]), x1)
	# The kerb, dropped at each crossover.
	var kx := x0
	for dw: Array in cuts + [[x1, x1]]:
		var a := maxf(float(dw[0]), x0)
		if a > kx:
			RoadsideBuilder._add(sts, kerb, kx, a, -0.3, 0.06, STRIP_Z1, 3.52)
		kx = minf(float(dw[1]), x1)
	# Leaves, bark and the odd bit of rubbish washed into the gutter.
	var r := _rng(b, x0, "gutter")
	var leaf: Array = [_m(b, "leaf_a", Color(0.33, 0.22, 0.1), 0.9), _m(b, "leaf_b", Color(0.42, 0.3, 0.12), 0.9),
		_m(b, "leaf_c", Color(0.22, 0.2, 0.12), 0.9)]
	var lx := x0 + r.randf_range(0.5, 3.0)
	while lx < x1 - 0.5:
		var l := r.randf_range(0.6, 2.4)
		RoadsideBuilder._add(sts, leaf[r.randi() % 3], lx, minf(lx + l, x1), LevelBuilder.ROAD_Y, LevelBuilder.ROAD_Y + 0.025,
			3.52, 3.52 + r.randf_range(0.12, 0.3))
		if r.randf() < 0.25:
			var c := lx + l * 0.5
			RoadsideBuilder._add(sts, _m(b, "litter", Color(0.72, 0.7, 0.62), 0.8), c - 0.12, c + 0.1,
				LevelBuilder.ROAD_Y, LevelBuilder.ROAD_Y + 0.03, 3.56, 3.72)
		lx += l + r.randf_range(1.5, 7.0)
	RoadsideBuilder._commit(b, sts)


## The yards and paddocks behind the lots, out to the hills: one plane under everything.
static func land(b: LevelBuilder) -> void:
	var L: float = b.data["length"]
	b._box(Vector3(L + 400.0, 0.1, 260.0), Vector3(L * 0.5, -0.07, -130.1), _m(b, "yards", Color(0.26, 0.3, 0.2), 0.95))


## [x0, x1] of every driveway crossover: a house's carport side.
static func driveways(b: LevelBuilder) -> Array:
	var out: Array = []
	for l in b.data.get("lots", []):
		if String(l.get("style", "")) != "house":
			continue
		var dw := _drive_span(b, l)
		if not dw.is_empty():
			out.append(dw)
	out.sort_custom(func(p, q): return p[0] < q[0])
	return out


static func _drive_span(b: LevelBuilder, l: Dictionary) -> Array:
	var x := float(l["x"])
	var w := float(l["w"])
	var side := _drive_side(b, l)
	if side == "none":
		return []
	return [x + 0.5, x + 3.3] if side == "left" else [x + w - 3.3, x + w - 0.5]


static func _drive_side(b: LevelBuilder, l: Dictionary) -> String:
	var w := float(l["w"])
	if w < 11.0 and not l.has("drive"):
		return "none"
	var r := _rng(b, float(l["x"]), "drive")
	return _pick(l, "drive", ["left", "right", "none"], r, [0.4, 0.4, 0.2])


# --- houses ----------------------------------------------------------------------------------------

static func _house(b: LevelBuilder, sts: Dictionary, x: float, w: float, d: Dictionary, r: RandomNumberGenerator) -> void:
	var state := _pick(d, "state", ["lived", "empty", "boarded"], r, [0.5, 0.35, 0.15])
	var walls := _pick(d, "walls", ["brick", "weatherboard"], r, [0.55, 0.45])
	var thin := clampf(float(d.get("thin", 0.0)), 0.0, 1.0)
	var fence := _pick(d, "fence", ["brick", "picket", "hedge", "wire"], r,
		[0.35 * (1.0 - thin), 0.3, 0.2, 0.15 + thin])
	var side := _drive_side(b, d)
	var car := _pick(d, "car", ["sedan", "wreck", "none"], r,
		[0.8 if state == "lived" else 0.0, 0.3 if state != "lived" else 0.05, 0.4])
	if side == "none" and car != "wreck":
		car = "none"
	var gone := state != "lived"
	# The house: narrower in a wider yard as the suburb thins.
	var margin := 0.8 + thin * 2.2
	var hx0 := x + margin
	var hx1 := x + w - margin
	if side == "left":
		hx0 = x + 4.2
	elif side == "right":
		hx1 = x + w - 4.2
	if hx1 - hx0 < 5.0:
		var c := (hx0 + hx1) * 0.5
		hx0 = c - 2.5
		hx1 = c + 2.5
	var zf := -SET_BACK - thin * 3.0
	var depth := 9.0
	var trim: Color = TRIMS[r.randi() % TRIMS.size()]
	if gone:
		trim = trim.lerp(Color(0.6, 0.6, 0.58), 0.35)
	var trim_m := _m(b, "trim_%s" % trim.to_html(), trim, 0.7)
	var wall_h := 2.85
	var plinth := 0.45
	var top := plinth + wall_h
	# Garden: lawn (long and seeding if no one is mowing it), a path from the gate, shrubs.
	var lawn := _m(b, "lawn_long" if gone else "lawn", Color(0.3, 0.33, 0.17) if gone else Color(0.27, 0.36, 0.18), 0.9)
	RoadsideBuilder._add(sts, lawn, x, x + w, -0.05, 0.03, zf - 0.5, -0.2)
	var door_x := lerpf(hx0, hx1, 0.3 if r.randf() < 0.5 else 0.7)
	var conc := _m(b, "garden_path", Color(0.5, 0.49, 0.45), 0.7)
	RoadsideBuilder._add(sts, conc, door_x - 0.45, door_x + 0.45, -0.05, 0.04, zf + 0.2, -0.15)
	if gone:
		_tufts(b, sts, x + 0.3, x + w - 0.3, zf + 0.4, -0.6, 14 + int(w * 1.5), r)
	_shrubs(b, x + 0.4, x + w - 0.4, zf + 1.2, zf + 0.4, 2 + r.randi() % 3, r, gone)
	# Walls and their front face.
	var body_c: Color
	var face: Material
	if walls == "brick":
		body_c = BRICKS[r.randi() % BRICKS.size()]
		face = RoadsideBuilder._textured(b, "sub_brick_%s" % body_c.to_html(), "brick_painted", body_c)
	else:
		body_c = BOARDS[r.randi() % BOARDS.size()]
		if gone:
			body_c = body_c.lerp(Color(0.55, 0.53, 0.5), 0.4)
		face = _m(b, "boards_%s" % body_c.to_html(), body_c, 0.8)
	b._box(Vector3(hx1 - hx0, top, depth), Vector3((hx0 + hx1) * 0.5, top * 0.5, zf - depth * 0.5),
		_m(b, "house_mass_%s" % body_c.to_html(), body_c.darkened(0.25), 0.9))
	RoadsideBuilder._add(sts, _m(b, "plinth", Color(0.36, 0.3, 0.27), 0.9), hx0 - 0.02, hx1 + 0.02, 0.0, plinth, zf - 0.1, zf + 0.04)
	if walls == "brick":
		RoadsideBuilder._wall_face(b, face, hx0, hx1, plinth, top, zf + 0.012)
	else:
		_weatherboards(b, sts, face, hx0, hx1, plinth, top, zf, gone, r)
	# Windows either side of the door, the front door under a little porch roof.
	var wins: Array = []
	var span_l := door_x - 0.8 - hx0
	var span_r := hx1 - door_x - 0.8
	for sp in [[hx0 + 0.6, door_x - 0.9, span_l], [door_x + 0.9, hx1 - 0.6, span_r]]:
		if sp[2] < 1.4:
			continue
		var ww := minf(2.4, float(sp[2]) - 0.6)
		var cx := (float(sp[0]) + float(sp[1])) * 0.5
		wins.append([cx - ww * 0.5, cx + ww * 0.5])
	var lit_one := state == "lived" and r.randf() < 0.75 and not wins.is_empty()
	for i in wins.size():
		var wn: Array = wins[i]
		var kind := "dark"
		if state == "boarded":
			kind = "boards"
		elif state == "empty":
			kind = "broken" if r.randf() < 0.4 else "dark"
		elif lit_one and i == 0:
			kind = "lit"
		else:
			kind = "curtain"
		_window(b, sts, wn[0], wn[1], plinth + 0.75, plinth + 2.05, zf, kind, trim_m)
	_door(b, sts, door_x, plinth, zf, state, trim_m)
	# Porch: a skillion on a pair of posts in front of the door.
	var porch_m := _m(b, "porch_roof", Color(0.4, 0.4, 0.39), 0.6)
	RoadsideBuilder._add(sts, conc, door_x - 1.1, door_x + 1.1, 0.0, plinth, zf, zf + 1.5)
	RoadsideBuilder._add(sts, porch_m, door_x - 1.2, door_x + 1.2, top - 0.25, top - 0.15, zf, zf + 1.7)
	for px in [door_x - 1.1, door_x + 1.1]:
		RoadsideBuilder._add(sts, _m(b, "iron_post", Color(0.12, 0.12, 0.12), 0.5), px - 0.04, px + 0.04, plinth, top - 0.25, zf + 1.55, zf + 1.63)
	# Roof: a hipped roof of concrete tiles on brick; corrugated iron, gabled, on weatherboard.
	var eave := 0.55
	var roof_c: Color = TILES[r.randi() % TILES.size()] if walls == "brick" else IRON[r.randi() % IRON.size()]
	if gone:
		roof_c = roof_c.lerp(Color(0.32, 0.3, 0.27), 0.35)
	var roof_m := _m(b, "roof_%s" % roof_c.to_html(), roof_c, 0.75 if walls == "brick" else 0.45, 0.0 if walls == "brick" else 0.3)
	var rise := (depth + eave * 2.0) * 0.5 * (0.45 if walls == "brick" else 0.5)
	_roof(b, sts, roof_m, face if walls != "brick" else trim_m, hx0 - eave, hx1 + eave, zf + eave, zf - depth - eave, top, rise, walls == "brick")
	# Fascia and gutter along the front eave; an abandoned house's has come away at one end.
	var gutter := _m(b, "gutter", Color(0.55, 0.56, 0.54), 0.45, 0.4)
	if state == "boarded":
		RoadsideBuilder._add(sts, gutter, hx0 - eave, lerpf(hx0, hx1, 0.55), top - 0.12, top, zf + eave - 0.08, zf + eave + 0.06)
		var hang := b._box(Vector3((hx1 - hx0) * 0.5, 0.1, 0.12), Vector3(lerpf(hx0, hx1, 0.78) + eave * 0.5, top - 0.42, zf + eave), gutter)
		hang.rotation.z = -0.32
	else:
		RoadsideBuilder._add(sts, gutter, hx0 - eave, hx1 + eave, top - 0.12, top, zf + eave - 0.08, zf + eave + 0.06)
	# A chimney, and a TV aerial on a mast.
	if r.randf() < 0.6:
		var chx := lerpf(hx0, hx1, r.randf_range(0.15, 0.85))
		RoadsideBuilder._add(sts, _m(b, "chimney", body_c.darkened(0.15) if walls == "brick" else Color(0.45, 0.28, 0.2), 0.9),
			chx - 0.3, chx + 0.3, top, top + rise + 0.9, zf - depth * 0.55, zf - depth * 0.4)
	if r.randf() < (0.8 if state == "lived" else 0.5):
		_aerial(b, sts, lerpf(hx0, hx1, r.randf_range(0.2, 0.8)), top + rise * 0.9, zf - depth * 0.5, state == "boarded")
	# Carport, driveway and a car.
	if side != "none":
		_carport(b, sts, x, w, side, zf, top, state, car, r)
	elif car == "wreck":
		_car(b, x + w * 0.5, -3.2, "wreck", r)
	# The front fence, a letterbox at the gate, an agent's board on an empty one.
	var gate := [door_x - 0.55, door_x + 0.55]
	var dw := _drive_span(b, d)
	_fence(b, sts, x, x + w, fence, gate, dw, gone, r)
	_letterbox(b, sts, gate[1] + 0.35, gone)
	if d.has("sign") or (state == "empty" and r.randf() < 0.55):
		_agent_board(b, sts, lerpf(x, x + w, 0.72 if door_x < x + w * 0.5 else 0.28), -1.4, String(d.get("sign", "FOR SALE")), r)
	if state == "lived" and lit_one:
		b.lit_windows.append([Vector3(float(wins[0][0]) * 0.5 + float(wins[0][1]) * 0.5, plinth + 1.4, zf - 0.8), Color(1.0, 0.7, 0.42)])


## Weatherboards: the wall in its paint, a shadow line under every board, bare grey timber showing
## where the paint has peeled.
static func _weatherboards(b: LevelBuilder, sts: Dictionary, paint: Material, x0: float, x1: float, y0: float, y1: float,
		zf: float, peeling: bool, r: RandomNumberGenerator) -> void:
	RoadsideBuilder._add(sts, paint, x0, x1, y0, y1, zf - 0.02, zf + 0.02)
	var line := _m(b, "board_line", Color(0.2, 0.19, 0.17), 0.9)
	var bare := _m(b, "board_bare", Color(0.5, 0.48, 0.44), 0.95)
	var y := y0 + 0.18
	while y < y1 - 0.05:
		RoadsideBuilder._add(sts, line, x0, x1, y - 0.018, y, zf + 0.02, zf + 0.032)
		if peeling and r.randf() < 0.35:
			var px := r.randf_range(x0, x1 - 1.0)
			RoadsideBuilder._add(sts, bare, px, px + r.randf_range(0.4, 1.6), y, y + 0.17, zf + 0.02, zf + 0.03)
		y += 0.18


static func _window(b: LevelBuilder, sts: Dictionary, x0: float, x1: float, y0: float, y1: float, zf: float, kind: String,
		trim: Material) -> void:
	var alu := _m(b, "win_alu", Color(0.62, 0.63, 0.62), 0.35, 0.7)
	var glass: Material = b._mat("glass_dark", Color(0.03, 0.035, 0.04), 0.05, 0.3)
	match kind:
		"lit":
			glass = RoadsideBuilder._glow(b, "sub_win_lit", Color(1.0, 0.72, 0.42), 0.9)
		"curtain":
			glass = _m(b, "curtain_drawn", Color(0.55, 0.42, 0.3), 0.8)
	RoadsideBuilder._add(sts, glass, x0, x1, y0, y1, zf, zf + 0.03)
	RoadsideBuilder._add(sts, alu, x0 - 0.04, x1 + 0.04, y1, y1 + 0.05, zf, zf + 0.06)
	RoadsideBuilder._add(sts, alu, x0 - 0.04, x1 + 0.04, y0 - 0.05, y0, zf, zf + 0.06)
	RoadsideBuilder._add(sts, trim, x0 - 0.1, x1 + 0.1, y0 - 0.12, y0 - 0.05, zf, zf + 0.12)
	var n := maxi(2, roundi((x1 - x0) / 0.8))
	for i in range(1, n):
		var mx := lerpf(x0, x1, float(i) / n)
		RoadsideBuilder._add(sts, alu, mx - 0.02, mx + 0.02, y0, y1, zf, zf + 0.05)
	match kind:
		"boards":
			var ply := _m(b, "ply_grey", Color(0.46, 0.4, 0.31), 0.95)
			RoadsideBuilder._add(sts, ply, x0 - 0.06, x1 + 0.06, y0 - 0.04, y1 + 0.04, zf + 0.06, zf + 0.09)
			var bat := b._box(Vector3(Vector2(x1 - x0, y1 - y0).length(), 0.08, 0.03),
				Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, zf + 0.11), _m(b, "batten", Color(0.36, 0.3, 0.22), 0.9))
			bat.rotation.z = atan2(y1 - y0, x1 - x0)
		"broken":
			# A pane gone: the dark room behind, a jagged pale edge where the glass still hangs.
			var bx := lerpf(x0, x1, 0.25)
			RoadsideBuilder._add(sts, _m(b, "room_black", Color(0.01, 0.01, 0.01), 1.0), bx, bx + 0.6, y0 + 0.1, y1 - 0.1, zf + 0.031, zf + 0.035)
			RoadsideBuilder._add(sts, _m(b, "glass_shard", Color(0.42, 0.44, 0.46), 0.1, 0.3), bx, bx + 0.25, y1 - 0.35, y1 - 0.1, zf + 0.035, zf + 0.04)


static func _door(b: LevelBuilder, sts: Dictionary, x: float, y0: float, zf: float, state: String, trim: Material) -> void:
	var cols := {"lived": Color(0.45, 0.2, 0.12), "empty": Color(0.32, 0.28, 0.24), "boarded": Color(0.42, 0.36, 0.27)}
	RoadsideBuilder._add(sts, trim, x - 0.52, x + 0.52, y0, y0 + 2.15, zf, zf + 0.06)
	RoadsideBuilder._add(sts, _m(b, "door_%s" % state, cols[state], 0.6), x - 0.44, x + 0.44, y0, y0 + 2.08, zf, zf + 0.08)
	if state == "lived":
		RoadsideBuilder._add(sts, RoadsideBuilder._glow(b, "door_glass", Color(1.0, 0.75, 0.48), 0.5), x - 0.12, x + 0.12, y0 + 0.9, y0 + 1.9, zf, zf + 0.09)


## A hipped (or, `hip` false, a gabled) roof over the rectangle x0..x1, z_back..z_front at eaves
## height y, its ridge `rise` above; `gable_m` fills the gable ends.
static func _roof(b: LevelBuilder, sts: Dictionary, mat: Material, gable_m: Material, x0: float, x1: float, zf: float, zb: float,
		y: float, rise: float, hip: bool) -> void:
	var zm := (zf + zb) * 0.5
	var half := (zf - zb) * 0.5
	var ry := y + rise
	var r0 := Vector3(x0 + (half if hip else 0.0), ry, zm)
	var r1 := Vector3(x1 - (half if hip else 0.0), ry, zm)
	if r0.x > r1.x:
		r0.x = (x0 + x1) * 0.5
		r1.x = r0.x
	var a := Vector3(x0, y, zf)
	var c := Vector3(x1, y, zf)
	var e := Vector3(x1, y, zb)
	var f := Vector3(x0, y, zb)
	_quad(sts, mat, a, c, r1, r0, Vector3(0, 1, 1))
	_quad(sts, mat, f, e, r1, r0, Vector3(0, 1, -1))
	if hip:
		_tri(sts, mat, a, f, r0, Vector3(-1, 1, 0))
		_tri(sts, mat, c, e, r1, Vector3(1, 1, 0))
	else:
		_tri(sts, gable_m, a + Vector3(0.5, 0, -0.5), f + Vector3(0.5, 0, 0.5), r0 + Vector3(0.5, -0.05, 0), Vector3.LEFT)
		_tri(sts, gable_m, c + Vector3(-0.5, 0, -0.5), e + Vector3(-0.5, 0, 0.5), r1 + Vector3(-0.5, -0.05, 0), Vector3.RIGHT)
	# The ridge capping.
	RoadsideBuilder._add(sts, _m(b, "ridge_cap", Color(0.25, 0.22, 0.2), 0.7), r0.x - 0.05, r1.x + 0.05, ry - 0.03, ry + 0.06, zm - 0.1, zm + 0.1)


static func _aerial(b: LevelBuilder, sts: Dictionary, x: float, y: float, z: float, bent: bool) -> void:
	var al := _m(b, "aerial", Color(0.6, 0.62, 0.63), 0.4, 0.7)
	RoadsideBuilder._add(sts, al, x - 0.025, x + 0.025, y - 0.5, y + 2.2, z - 0.025, z + 0.025)
	var boom := b._box(Vector3(2.2, 0.03, 0.03), Vector3(x, y + 2.1, z), al)
	if bent:
		boom.rotation.z = 0.35
	for k in 5:
		var ex := -0.9 + k * 0.45
		var el := b._box(Vector3(0.025, 0.025, 1.4 - k * 0.18), Vector3(x + ex * cos(boom.rotation.z), y + 2.1 + ex * sin(boom.rotation.z), z), al)
		el.rotation.z = boom.rotation.z


static func _carport(b: LevelBuilder, sts: Dictionary, x: float, w: float, side: String, zf: float, top: float, state: String,
		car: String, r: RandomNumberGenerator) -> void:
	var cx0 := x + 0.5 if side == "left" else x + w - 3.6
	var cx1 := cx0 + 3.1
	var steel := _m(b, "carport_post", Color(0.2, 0.2, 0.2), 0.5, 0.6)
	var roof := _m(b, "carport_roof", Color(0.55, 0.56, 0.55) if state == "lived" else Color(0.42, 0.4, 0.36), 0.5, 0.4)
	var z0 := zf - 6.0
	var z1 := zf + 0.4
	RoadsideBuilder._add(sts, roof, cx0 - 0.1, cx1 + 0.1, top - 0.35, top - 0.25, z0, z1)
	for px in [cx0, cx1]:
		for pz in [z0 + 0.2, z1 - 0.2]:
			RoadsideBuilder._add(sts, steel, px - 0.05, px + 0.05, 0.0, top - 0.35, pz - 0.05, pz + 0.05)
	# Two concrete wheel strips down to the footpath, grass between them.
	var conc := _m(b, "drive_strip", Color(0.47, 0.46, 0.43), 0.65)
	var mid := (cx0 + cx1) * 0.5
	for sx in [mid - 0.75, mid + 0.75]:
		RoadsideBuilder._add(sts, conc, sx - 0.32, sx + 0.32, -0.05, 0.045, z0, 0.0)
	if car == "sedan":
		_car(b, mid, zf - 2.4, "sedan", r)
	elif car == "wreck":
		_car(b, mid, -2.6, "wreck", r)


## A parked car nose to the street: a 60s sedan, or one long since burnt out and left to rust.
static func _car(b: LevelBuilder, x: float, z: float, kind: String, r: RandomNumberGenerator) -> void:
	var ids := ["car_sedan", "car_sedan_b", "car_sedan_c"].filter(func(id): return b.props_kit.has(id))
	var n: Node3D = b._instance(b.props_kit[ids[r.randi() % ids.size()]]["scene"]) if not ids.is_empty() else CarHazard.greybox_car()
	if n == null:
		return
	n.position = Vector3(x, 0.0, z)
	n.rotation.y = PI * 0.5 + r.randf_range(-0.08, 0.08)
	if kind == "wreck":
		n.position.y = -0.14
		n.rotation.z = 0.04
		n.rotation.y += r.randf_range(-0.2, 0.2)
		var rust := b._material_res("metal_rust", b._mat("rust", Color(0.32, 0.17, 0.1), 0.9))
		var burnt := b._mat("burnt", Color(0.06, 0.055, 0.05), 0.95)
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = rust if r.randf() < 0.6 else burnt
	b.root.add_child(n)


static func _fence(b: LevelBuilder, sts: Dictionary, x0: float, x1: float, kind: String, gate: Array, drive: Array, gone: bool,
		r: RandomNumberGenerator) -> void:
	var gaps: Array = [gate]
	if not drive.is_empty():
		gaps.append(drive)
	gaps.sort_custom(func(p, q): return p[0] < q[0])
	var runs: Array = []
	var fx := x0
	for g: Array in gaps:
		if g[0] > fx:
			runs.append([fx, g[0]])
		fx = maxf(fx, g[1])
	if x1 > fx:
		runs.append([fx, x1])
	var z := -0.12
	for run: Array in runs:
		var a: float = run[0]
		var c: float = run[1]
		if c - a < 0.1:
			continue
		match kind:
			"brick":
				var brick := RoadsideBuilder._textured(b, "fence_brick", "brick_painted", Color(0.62, 0.36, 0.24))
				RoadsideBuilder._add(sts, brick, a, c, 0.0, 0.62, z - 0.12, z + 0.12)
				RoadsideBuilder._add(sts, _m(b, "fence_cap", Color(0.52, 0.32, 0.22), 0.8), a - 0.02, c + 0.02, 0.62, 0.7, z - 0.15, z + 0.15)
				for px in [a + 0.18, c - 0.18]:
					RoadsideBuilder._add(sts, brick, px - 0.18, px + 0.18, 0.0, 0.85, z - 0.18, z + 0.18)
			"picket":
				var paint := _m(b, "picket_grey" if gone else "picket", Color(0.62, 0.6, 0.55) if gone else Color(0.85, 0.84, 0.8), 0.7)
				RoadsideBuilder._add(sts, paint, a, c, 0.35, 0.42, z - 0.05, z)
				RoadsideBuilder._add(sts, paint, a, c, 0.75, 0.82, z - 0.05, z)
				var px := a + 0.06
				while px < c - 0.04:
					if not (gone and r.randf() < 0.22):   # palings missing
						var h := 1.0 + (r.randf_range(-0.12, 0.0) if gone else 0.0)
						var p := b._box(Vector3(0.08, h, 0.022), Vector3(px, h * 0.5, z + 0.012), paint)
						if gone and r.randf() < 0.15:
							p.rotation.z = r.randf_range(-0.25, 0.25)
					px += 0.14
				for px2 in [a + 0.05, c - 0.05]:
					RoadsideBuilder._add(sts, paint, px2 - 0.05, px2 + 0.05, 0.0, 1.1, z - 0.1, z)
			"hedge":
				_hedge(b, a, c, z - 0.35, gone, r)
			"wire":
				var post := _m(b, "fence_post", Color(0.34, 0.3, 0.24), 0.9)
				var wire := _m(b, "fence_wire", Color(0.3, 0.3, 0.3), 0.5, 0.6)
				var px := a + 0.1
				while px <= c:
					var lean := r.randf_range(-0.12, 0.12) if gone else 0.0
					var p := b._box(Vector3(0.09, 1.05, 0.09), Vector3(px, 0.5, z), post)
					p.rotation.z = lean
					px += 2.4
				for wy in [0.4, 0.75, 1.0]:
					var sag := b._box(Vector3(c - a, 0.012, 0.012), Vector3((a + c) * 0.5, wy - (0.08 if gone else 0.0), z + 0.05), wire)
					sag.rotation.z = 0.0
	if kind == "brick" or kind == "picket":
		_gatepost_gate(b, gate, z, kind, gone)


static func _gatepost_gate(b: LevelBuilder, gate: Array, z: float, kind: String, gone: bool) -> void:
	# A low gate (iron in a brick wall, palings in a picket fence), standing open; on an empty house
	# it hangs off one hinge.
	var gw := float(gate[1]) - float(gate[0]) - 0.1
	var mat: Material = _m(b, "gate_iron", Color(0.12, 0.12, 0.12), 0.5, 0.6)
	if kind == "picket":
		mat = _m(b, "picket_grey" if gone else "picket", Color(0.62, 0.6, 0.55) if gone else Color(0.85, 0.84, 0.8), 0.7)
	var g := Node3D.new()
	g.position = Vector3(float(gate[0]) + 0.05, 0.0, z)
	g.rotation.y = 1.25
	b.root.add_child(g)
	for k in [0.06, gw - 0.06]:
		var stile := b._box(Vector3(0.06, 0.85, 0.04), Vector3(k, 0.5, 0.0), mat, g)
		stile.name = "Stile"
	for y in [0.3, 0.8]:
		b._box(Vector3(gw, 0.05, 0.04), Vector3(gw * 0.5, y, 0.0), mat, g)
	var px := 0.2
	while px < gw - 0.1:
		b._box(Vector3(0.03 if kind != "picket" else 0.07, 0.6, 0.03), Vector3(px, 0.55, 0.0), mat, g)
		px += 0.14 if kind != "picket" else 0.16
	if gone:
		g.rotation.z = -0.22
		g.position.y = -0.04


static func _letterbox(b: LevelBuilder, sts: Dictionary, x: float, gone: bool) -> void:
	var post := _m(b, "lb_post", Color(0.3, 0.28, 0.25), 0.8)
	RoadsideBuilder._add(sts, post, x - 0.05, x + 0.05, 0.0, 0.95, -0.42, -0.32)
	var body := _m(b, "letterbox_rust" if gone else "letterbox", Color(0.35, 0.24, 0.17) if gone else Color(0.55, 0.15, 0.1), 0.6, 0.3)
	RoadsideBuilder._add(sts, body, x - 0.18, x + 0.18, 0.95, 1.25, -0.5, -0.2)
	if gone:   # junk mail spilling out of the slot
		RoadsideBuilder._add(sts, _m(b, "junk_mail", Color(0.78, 0.76, 0.7), 0.8), x - 0.12, x + 0.12, 1.12, 1.16, -0.2, -0.12)


## An agent's board on two posts, faded to grey in the weather, leaning a little.
static func _agent_board(b: LevelBuilder, sts: Dictionary, x: float, z: float, text: String, r: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	n.position = Vector3(x, 0.0, z)
	n.rotation.z = r.randf_range(-0.06, 0.06)
	n.rotation.y = r.randf_range(-0.15, 0.15)
	b.root.add_child(n)
	var post := _m(b, "board_post", Color(0.35, 0.31, 0.26), 0.9)
	for px in [-0.6, 0.6]:
		var p := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 1.7, 0.07)
		p.mesh = bm
		p.material_override = post
		p.position = Vector3(px, 0.85, 0.0)
		n.add_child(p)
	var board := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.45, 0.9, 0.03)
	board.mesh = bb
	board.material_override = _m(b, "agent_board", Color(0.68, 0.66, 0.6), 0.9)
	board.position = Vector3(0.0, 1.3, 0.04)
	n.add_child(board)
	var band := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = Vector3(1.45, 0.2, 0.034)
	band.mesh = bm2
	band.material_override = _m(b, "agent_band", Color(0.45, 0.2, 0.16), 0.9)
	band.position = Vector3(0.0, 1.66, 0.04)
	n.add_child(band)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 64
	lbl.pixel_size = 0.0042 * minf(1.0, 8.0 / maxf(text.length(), 1.0))
	if b.sign_font:
		lbl.font = b.sign_font
	lbl.modulate = Color(0.32, 0.27, 0.24)
	lbl.shaded = true
	lbl.double_sided = false
	lbl.position = Vector3(0.0, 1.25, 0.06)
	n.add_child(lbl)


## Tufts of long grass, a sign of a lawn nobody mows any more.
static func _tufts(b: LevelBuilder, sts: Dictionary, x0: float, x1: float, z0: float, z1: float, n: int,
		r: RandomNumberGenerator) -> void:
	var cols: Array = [Color(0.3, 0.34, 0.15), Color(0.42, 0.4, 0.2), Color(0.36, 0.38, 0.18)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var tx := r.randf_range(x0, x1)
		var tz := r.randf_range(minf(z0, z1), maxf(z0, z1))
		var h := r.randf_range(0.18, 0.5)
		var s := r.randf_range(0.2, 0.45)
		_blob(st, Vector3(tx, 0.0, tz), Vector3(s, h, s * 0.7), cols[i % 3], 0.0, 0.7, r)
	_foliage_mesh(b, st, Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5))


## Garden shrubs: rounded masses, in the foliage group so a gust moves them.
static func _shrubs(b: LevelBuilder, x0: float, x1: float, z0: float, z1: float, n: int, r: RandomNumberGenerator,
		wild: bool) -> void:
	for i in n:
		var c := Vector3(r.randf_range(x0, x1), 0.0, r.randf_range(minf(z0, z1), maxf(z0, z1)))
		var s := r.randf_range(0.5, 1.0) * (1.4 if wild else 1.0)
		var col := Color(0.18, 0.27, 0.13).lerp(Color(0.3, 0.33, 0.16), r.randf())
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_blob(st, c + Vector3(0, s * 0.7, 0), Vector3(s, s * 0.8, s * 0.8), col, 0.0, 0.6, r)
		_foliage_mesh(b, st, c)


## A hedge along the fence line, in pieces about 3 m long so a gust moves it piecewise.
static func _hedge(b: LevelBuilder, x0: float, x1: float, z: float, wild: bool, r: RandomNumberGenerator) -> void:
	var px := x0
	while px < x1 - 0.2:
		var l := minf(3.0, x1 - px)
		var h := r.randf_range(1.1, 1.3) if not wild else r.randf_range(1.5, 2.1)
		var col := Color(0.16, 0.25, 0.12) if not wild else Color(0.22, 0.28, 0.13)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var k := 0.0
		while k < l:
			var s := r.randf_range(0.45, 0.7) * (1.25 if wild else 1.0)
			_blob(st, Vector3(px + k + s * 0.5, h - s * 0.6, z), Vector3(s * 0.8, s * 0.9, 0.45 + (0.2 if wild else 0.0)), col, 0.05, 0.5, r)
			_blob(st, Vector3(px + k + s * 0.5, (h - s) * 0.45, z), Vector3(s * 0.75, (h - s) * 0.5 + 0.1, 0.42), col.darkened(0.15), 0.0, 0.0, r)
			k += s * 0.9
		_foliage_mesh(b, st, Vector3(px + l * 0.5, 0.0, z))
		px += l


# --- the other lots --------------------------------------------------------------------------------

static func _flats(b: LevelBuilder, sts: Dictionary, x: float, w: float, floors: int, d: Dictionary, r: RandomNumberGenerator) -> void:
	var storeys := floors + 1
	var st_h := 2.8
	var h := storeys * st_h + 0.5
	var zf := -5.0
	var depth := 11.0
	var x0 := x + 0.6
	var x1 := x + w - 0.6
	var brick_c: Color = [Color(0.66, 0.5, 0.36), Color(0.56, 0.3, 0.2), Color(0.72, 0.64, 0.52)][r.randi() % 3]
	var brick := RoadsideBuilder._textured(b, "sub_brick_%s" % brick_c.to_html(), "brick_painted", brick_c)
	b._box(Vector3(x1 - x0, h, depth), Vector3((x0 + x1) * 0.5, h * 0.5, zf - depth * 0.5), _m(b, "flats_mass", brick_c.darkened(0.3), 0.9))
	RoadsideBuilder._wall_face(b, brick, x0, x1, 0.0, h, zf + 0.012)
	var conc := _m(b, "flats_slab", Color(0.62, 0.6, 0.55), 0.8)
	var rail := _m(b, "flats_rail", Color(0.14, 0.14, 0.14), 0.5, 0.6)
	# A breeze-block stairwell in the middle, open to the weather.
	var sx := (x0 + x1) * 0.5
	var breeze := _m(b, "breeze_block", Color(0.74, 0.72, 0.66), 0.85)
	RoadsideBuilder._add(sts, breeze, sx - 1.2, sx + 1.2, 0.0, h + 0.6, zf, zf + 0.3)
	var gap := _m(b, "breeze_gap", Color(0.12, 0.11, 0.1), 0.9)
	for gy in range(0, int((h + 0.4) / 0.4)):
		for gx in 5:
			var cx := sx - 0.96 + gx * 0.48
			var cy := 0.2 + gy * 0.4
			RoadsideBuilder._add(sts, gap, cx - 0.13, cx + 0.13, cy, cy + 0.24, zf + 0.3, zf + 0.31)
	# Each storey: a slab edge, balconies with steel rails, windows (a few lit, a few boarded).
	var lit_n := 0
	for s in storeys:
		var y0 := s * st_h
		RoadsideBuilder._add(sts, conc, x0 - 0.05, x1 + 0.05, y0 + st_h - 0.12, y0 + st_h + 0.08, zf, zf + 0.15)
		for half in [[x0 + 0.4, sx - 1.5], [sx + 1.5, x1 - 0.4]]:
			var a: float = half[0]
			var c: float = half[1]
			if c - a < 1.5:
				continue
			var kind := "curtain"
			var roll := r.randf()
			if roll < 0.22:
				kind = "lit"
			elif roll < 0.42:
				kind = "boards"
			elif roll < 0.62:
				kind = "dark"
			_window(b, sts, a + 0.3, c - 0.3, y0 + 0.9, y0 + 2.2, zf, kind, conc)
			if kind == "lit" and lit_n < 2:
				lit_n += 1
				b.lit_windows.append([Vector3((a + c) * 0.5, y0 + 1.5, zf - 0.8), Color(1.0, 0.72, 0.45)])
			if s > 0:
				RoadsideBuilder._add(sts, conc, a, c, y0 - 0.1, y0 + 0.05, zf, zf + 1.1)
				RoadsideBuilder._add(sts, rail, a, c, y0 + 0.95, y0 + 1.0, zf + 1.05, zf + 1.1)
				var px := a
				while px <= c:
					RoadsideBuilder._add(sts, rail, px - 0.015, px + 0.015, y0, y0 + 0.95, zf + 1.06, zf + 1.09)
					px += 0.12
	RoadsideBuilder._add(sts, conc, x0 - 0.1, x1 + 0.1, h - 0.1, h + 0.25, zf - depth, zf + 0.2)
	# A strip of lawn and the car park in front, a low wall at the street.
	RoadsideBuilder._add(sts, _m(b, "lawn_long", Color(0.3, 0.33, 0.17), 0.9), x, x + w, -0.05, 0.03, zf, -0.2)
	RoadsideBuilder._add(sts, _m(b, "carpark", Color(0.18, 0.18, 0.19), 0.4), x + 0.5, x + w - 0.5, -0.05, 0.04, zf + 0.2, -2.0)
	_tufts(b, sts, x + 0.3, x + w - 0.3, -0.5, -1.8, int(w * 1.2), r)
	_fence(b, sts, x, x + w, "brick", [sx - 0.6, sx + 0.6], [], false, r)
	if d.has("sign"):
		ModernBuilder.sign_text(b, sx, h - 1.0, zf + 0.32, String(d["sign"]), 2.3)


static func _vacant_block(b: LevelBuilder, sts: Dictionary, x: float, w: float, d: Dictionary, r: RandomNumberGenerator) -> void:
	RoadsideBuilder._add(sts, _m(b, "block_dirt", Color(0.27, 0.27, 0.17), 0.95), x, x + w, -0.05, 0.03, -16.0, -0.2)
	_tufts(b, sts, x + 0.2, x + w - 0.2, -14.0, -0.6, int(w * 6.0), r)
	_shrubs(b, x + 0.5, x + w - 0.5, -12.0, -5.0, 2 + int(w / 6.0), r, true)
	_fence(b, sts, x, x + w, "wire", [x + w * 0.45, x + w * 0.45 + 1.4], [], true, r)
	_agent_board(b, sts, x + w * 0.5, -2.0, String(d.get("sign", "LAND FOR SALE")), r)
	# What gets dumped on an empty block: a mattress, a car tyre, a heap of rubble.
	RoadsideBuilder._add(sts, _m(b, "mattress", Color(0.55, 0.5, 0.42), 0.95), x + 1.0, x + 2.9, 0.0, 0.22, -4.5, -3.6)
	ModernBuilder.cyl(sts, _m(b, "tyre", Color(0.05, 0.05, 0.05), 0.9), Vector3(x + w - 2.0, 0.0, -3.0), Vector3(x + w - 2.0, 0.2, -3.0), 0.36, 0.36, 10)
	RoadsideBuilder._add(sts, _m(b, "rubble", Color(0.45, 0.4, 0.36), 0.95), x + w * 0.6, x + w * 0.6 + 1.6, 0.0, 0.4, -9.0, -7.5)
	# The neighbours' side fences down either edge.
	for ex in [x + 0.05, x + w - 0.05]:
		RoadsideBuilder._add(sts, _m(b, "paling", Color(0.38, 0.34, 0.28), 0.9), ex - 0.03, ex + 0.03, 0.0, 1.8, -18.0, -6.0)


static func _park(b: LevelBuilder, sts: Dictionary, x: float, w: float, d: Dictionary, r: RandomNumberGenerator) -> void:
	RoadsideBuilder._add(sts, _m(b, "park_grass", Color(0.25, 0.33, 0.17), 0.9), x, x + w, -0.05, 0.03, -24.0, -0.2)
	_tufts(b, sts, x + 0.2, x + w - 0.2, -18.0, -0.5, int(w * 2.0), r)
	# Treated-pine bollards along the street, a chain gone between two of them.
	var pine := _m(b, "bollard_pine", Color(0.42, 0.36, 0.26), 0.9)
	var px := x + 0.4
	while px < x + w:
		RoadsideBuilder._add(sts, pine, px - 0.08, px + 0.08, 0.0, 0.6, -0.3, -0.14)
		px += 1.6
	# The swing set: an A-frame of steel pipe, two seats, one hanging by one chain.
	var sx := x + w * 0.35
	var sz := -6.0
	var pipe := _m(b, "swing_pipe", Color(0.35, 0.38, 0.36), 0.5, 0.5)
	for ex in [sx - 1.6, sx + 1.6]:
		for dz in [-0.8, 0.8]:
			ModernBuilder.cyl(sts, pipe, Vector3(ex, 0.0, sz + dz), Vector3(ex, 2.3, sz), 0.04)
	ModernBuilder.cyl(sts, pipe, Vector3(sx - 1.6, 2.3, sz), Vector3(sx + 1.6, 2.3, sz), 0.045)
	var chain := _m(b, "swing_chain", Color(0.25, 0.25, 0.25), 0.5, 0.6)
	var seat := _m(b, "swing_seat", Color(0.2, 0.17, 0.14), 0.8)
	for k in 2:
		var cx := sx - 0.7 + k * 1.4
		if k == 0:
			for ex in [cx - 0.22, cx + 0.22]:
				RoadsideBuilder._add(sts, chain, ex - 0.01, ex + 0.01, 0.55, 2.3, sz - 0.01, sz + 0.01)
			RoadsideBuilder._add(sts, seat, cx - 0.25, cx + 0.25, 0.5, 0.56, sz - 0.1, sz + 0.1)
		else:
			RoadsideBuilder._add(sts, chain, cx - 0.23, cx - 0.21, 0.4, 2.3, sz - 0.01, sz + 0.01)
			var s := b._box(Vector3(0.5, 0.06, 0.2), Vector3(cx - 0.12, 0.35, sz), seat)
			s.rotation.z = 1.2
	RoadsideBuilder._add(sts, _m(b, "swing_dirt", Color(0.3, 0.26, 0.2), 0.95), sx - 1.4, sx + 1.4, -0.03, 0.035, sz - 0.6, sz + 0.6)
	# A bench and a bin by the path, a sign on its own post.
	var bx := x + w * 0.72
	RoadsideBuilder._add(sts, pine, bx - 0.9, bx + 0.9, 0.42, 0.48, -2.1, -1.7)
	RoadsideBuilder._add(sts, pine, bx - 0.9, bx + 0.9, 0.55, 0.85, -2.12, -2.06)
	for lx in [bx - 0.75, bx + 0.75]:
		RoadsideBuilder._add(sts, _m(b, "bench_leg", Color(0.15, 0.15, 0.15), 0.6), lx - 0.04, lx + 0.04, 0.0, 0.45, -2.05, -1.75)
	ModernBuilder.cyl(sts, _m(b, "park_bin", Color(0.2, 0.28, 0.22), 0.6, 0.3), Vector3(bx + 1.5, 0.0, -1.0), Vector3(bx + 1.5, 0.85, -1.0), 0.28)
	RoadsideBuilder._add(sts, _m(b, "path_gravel", Color(0.44, 0.4, 0.34), 0.95), x + w * 0.55, x + w * 0.55 + 1.4, -0.04, 0.04, -12.0, -0.3)
	if d.has("sign"):
		var lbl := Label3D.new()
		lbl.text = String(d["sign"])
		lbl.font_size = 48
		lbl.pixel_size = 0.004
		if b.sign_font:
			lbl.font = b.sign_font
		lbl.modulate = Color(0.85, 0.82, 0.7)
		lbl.shaded = true
		lbl.double_sided = false
		var sgx := x + 1.4
		RoadsideBuilder._add(sts, pine, sgx - 0.05, sgx + 0.05, 0.0, 1.5, -0.7, -0.6)
		RoadsideBuilder._add(sts, _m(b, "park_sign", Color(0.16, 0.26, 0.2), 0.7), sgx - 0.8, sgx + 0.8, 1.2, 1.6, -0.6, -0.56)
		lbl.position = Vector3(sgx, 1.4, -0.54)
		b.root.add_child(lbl)
	# Park trees standing back on the grass.
	var n := maxi(1, int(w / 10.0))
	for i in n:
		park_tree(b, Vector3(x + w * (i + 0.5) / n + r.randf_range(-1.5, 1.5), 0.0, r.randf_range(-16.0, -11.0)), r)


static func _church_hall(b: LevelBuilder, sts: Dictionary, x: float, w: float, d: Dictionary, r: RandomNumberGenerator) -> void:
	var porch := String(d.get("cover", "none")) == "porch"
	var zf := -0.15
	var depth := 16.0
	var wall_h := 4.6
	var brick := RoadsideBuilder._textured(b, "hall_brick", "brick_painted", Color(0.58, 0.4, 0.3))
	var x0 := x + 0.3
	var x1 := x + w - 0.3
	b._box(Vector3(x1 - x0, wall_h, depth), Vector3((x0 + x1) * 0.5, wall_h * 0.5, zf - depth * 0.5), _m(b, "hall_mass", Color(0.4, 0.28, 0.22), 0.9))
	RoadsideBuilder._wall_face(b, brick, x0, x1, 0.0, wall_h, zf + 0.012)
	# Its gable end to the street: a steep fibro-cement gable, a cross on the ridge.
	var ry := wall_h + (x1 - x0) * 0.45
	var fibro := _m(b, "hall_fibro", Color(0.7, 0.68, 0.62), 0.85)
	_tri(sts, fibro, Vector3(x0, wall_h, zf + 0.01), Vector3(x1, wall_h, zf + 0.01), Vector3((x0 + x1) * 0.5, ry, zf + 0.01), Vector3.BACK)
	var roof := _m(b, "hall_roof", Color(0.3, 0.3, 0.3), 0.6, 0.3)
	var cx := (x0 + x1) * 0.5
	_quad(sts, roof, Vector3(x0 - 0.3, wall_h - 0.15, zf + 0.3), Vector3(cx, ry + 0.1, zf + 0.3), Vector3(cx, ry + 0.1, zf - depth),
		Vector3(x0 - 0.3, wall_h - 0.15, zf - depth), Vector3(-1, 1, 0))
	_quad(sts, roof, Vector3(x1 + 0.3, wall_h - 0.15, zf + 0.3), Vector3(cx, ry + 0.1, zf + 0.3), Vector3(cx, ry + 0.1, zf - depth),
		Vector3(x1 + 0.3, wall_h - 0.15, zf - depth), Vector3(1, 1, 0))
	var cross := _m(b, "hall_cross", Color(0.75, 0.74, 0.7), 0.6)
	RoadsideBuilder._add(sts, cross, cx - 0.06, cx + 0.06, ry, ry + 1.2, zf + 0.1, zf + 0.22)
	RoadsideBuilder._add(sts, cross, cx - 0.35, cx + 0.35, ry + 0.7, ry + 0.82, zf + 0.1, zf + 0.22)
	# Tall narrow windows of coloured glass, dark; a pair of doors.
	var glass := _m(b, "hall_glass", Color(0.12, 0.14, 0.16), 0.1, 0.3)
	var n := maxi(2, int((x1 - x0) / 2.2))
	for i in n:
		var wx := lerpf(x0 + 1.0, x1 - 1.0, (i + 0.5) / n)
		if absf(wx - x - CountryBuilder.door_x(d)) < 1.3:
			continue
		RoadsideBuilder._add(sts, glass, wx - 0.3, wx + 0.3, 1.0, 3.6, zf + 0.01, zf + 0.04)
		RoadsideBuilder._add(sts, cross, wx - 0.38, wx + 0.38, 0.9, 1.0, zf, zf + 0.1)
	var dx := x + CountryBuilder.door_x(d)   # the porch (CountryBuilder.porch_span) is centred on it
	RoadsideBuilder._add(sts, _m(b, "hall_door", Color(0.3, 0.18, 0.1), 0.6), dx - 0.9, dx + 0.9, 0.0, 2.4, zf + 0.01, zf + 0.06)
	RoadsideBuilder._add(sts, _m(b, "hall_step", Color(0.52, 0.5, 0.46), 0.8), dx - 1.3, dx + 1.3, 0.0, 0.14, zf, zf + 0.7)
	# A notice board by the door, its notices long out of date.
	var nb := x0 + 0.9
	RoadsideBuilder._add(sts, _m(b, "notice_frame", Color(0.2, 0.2, 0.2), 0.6), nb - 0.6, nb + 0.6, 1.0, 1.9, zf + 0.01, zf + 0.07)
	RoadsideBuilder._add(sts, _m(b, "notice_paper", Color(0.7, 0.68, 0.6), 0.9), nb - 0.5, nb - 0.05, 1.15, 1.75, zf + 0.07, zf + 0.08)
	RoadsideBuilder._add(sts, _m(b, "notice_paper_b", Color(0.62, 0.58, 0.45), 0.9), nb + 0.05, nb + 0.48, 1.2, 1.6, zf + 0.07, zf + 0.08)
	if d.has("sign"):
		ModernBuilder.sign_text(b, cx, wall_h + 0.4, zf + 0.02, String(d["sign"]), minf(x1 - x0 - 1.5, 4.5))
	RoadsideBuilder._add(sts, _m(b, "hall_apron", Color(0.46, 0.45, 0.42), 0.7), x, x + w, -0.05, 0.02, zf, -0.05)
	if porch:
		# CountryBuilder draws the porch over the footpath at the door (and its cover); a lamp under it.
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.82, 0.6)
		lamp.light_energy = 0.6
		lamp.omni_range = 4.0
		lamp.position = Vector3(dx, CountryBuilder.PORCH_Y - 0.3, 0.6)
		b.root.add_child(lamp)
	else:
		RoadsideBuilder._add(sts, _m(b, "hall_canopy", Color(0.66, 0.64, 0.58), 0.75), cx - 1.5, cx + 1.5, 2.7, 2.85, zf, zf + 1.2)


static func _bus_shelter(b: LevelBuilder, sts: Dictionary, x: float, w: float, d: Dictionary, r: RandomNumberGenerator) -> void:
	var roofed := String(d.get("cover", "none")) == "shelter"
	# The yard behind: a paling fence and somebody's back garden.
	RoadsideBuilder._add(sts, _m(b, "lawn_long", Color(0.3, 0.33, 0.17), 0.9), x, x + w, -0.05, 0.03, -SET_BACK, -0.2)
	RoadsideBuilder._add(sts, _m(b, "paling", Color(0.38, 0.34, 0.28), 0.9), x, x + w, 0.0, 1.8, -0.9, -0.84)
	var a := x + 0.15
	var c := x + w - 0.15
	var frame := _m(b, "shelter_frame", Color(0.22, 0.3, 0.26), 0.5, 0.5)
	var panel := _m(b, "shelter_panel", Color(0.62, 0.6, 0.55), 0.85)
	# Back wall of fibro panels at the fence line; an advertising case gone blank; the timetable faded.
	RoadsideBuilder._add(sts, panel, a, c, 0.15, 2.3, -0.08, 0.0)
	RoadsideBuilder._add(sts, frame, a, c, 0.0, 0.15, -0.1, 0.02)
	RoadsideBuilder._add(sts, _m(b, "ad_case", Color(0.5, 0.52, 0.5), 0.3, 0.2), a + 0.3, a + 1.5, 0.6, 2.1, 0.0, 0.04)
	RoadsideBuilder._add(sts, _m(b, "timetable", Color(0.74, 0.72, 0.64), 0.9), c - 0.9, c - 0.35, 1.2, 1.75, 0.0, 0.03)
	RoadsideBuilder._add(sts, _m(b, "timetable_ink", Color(0.58, 0.56, 0.5), 0.9), c - 0.85, c - 0.4, 1.62, 1.7, 0.03, 0.035)
	# A bench along the back wall; a glass side screen behind the walker's line, cracked.
	RoadsideBuilder._add(sts, _m(b, "shelter_bench", Color(0.35, 0.27, 0.2), 0.8), a + 0.3, c - 0.3, 0.45, 0.5, 0.05, 0.42)
	var glass := _m(b, "shelter_glass", Color(0.55, 0.6, 0.62), 0.08, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.22
	for ex in [a, c]:
		RoadsideBuilder._add(sts, frame, ex - 0.04, ex + 0.04, 0.0, 2.45, 0.0, 1.0)
		RoadsideBuilder._add(sts, glass, ex - 0.01, ex + 0.01, 0.15, 2.3, 0.05, 0.95)
	var crack := _m(b, "glass_crack", Color(0.85, 0.88, 0.9), 0.1)
	for k in 4:
		var cr := b._box(Vector3(0.012, r.randf_range(0.4, 0.9), 0.012), Vector3(c - 0.02, 1.3 + r.randf_range(-0.3, 0.3), 0.5), crack)
		cr.rotation.x = r.randf_range(-1.2, 1.2)
	if roofed:
		# A skillion of fibro on a steel frame, falling toward the street; its underside and reach are
		# CountryBuilder's shelter numbers, whose collider, drips and rain map it shares.
		var y := CountryBuilder.SHELTER_Y
		var z1 := CountryBuilder.SHELTER_Z
		var roof := _m(b, "shelter_roof", Color(0.4, 0.43, 0.4), 0.6, 0.2)
		_quad(sts, roof, Vector3(x, y + 0.45, -0.15), Vector3(x + w, y + 0.45, -0.15), Vector3(x + w, y + 0.06, z1 + 0.05),
			Vector3(x, y + 0.06, z1 + 0.05), Vector3.UP)
		_quad(sts, roof, Vector3(x, y + 0.39, -0.15), Vector3(x + w, y + 0.39, -0.15), Vector3(x + w, y, z1 + 0.05),
			Vector3(x, y, z1 + 0.05), Vector3.DOWN)
		RoadsideBuilder._add(sts, frame, x, x + w, y - 0.06, y + 0.12, z1 - 0.03, z1 + 0.05)
		for ex in [a, c]:
			RoadsideBuilder._add(sts, frame, ex - 0.05, ex + 0.05, 0.0, y, z1 - 0.2, z1 - 0.1)
	# The stop's sign on its own pole at the kerb.
	var sgx := x + w - 0.3
	RoadsideBuilder._add(sts, _m(b, "stop_pole", Color(0.6, 0.6, 0.58), 0.4, 0.6), sgx - 0.03, sgx + 0.03, 0.0, 2.6, 3.05, 3.11)
	RoadsideBuilder._add(sts, _m(b, "stop_plate", Color(0.75, 0.6, 0.15), 0.6), sgx - 0.25, sgx + 0.25, 2.2, 2.6, 3.11, 3.13)


static func _overbridge(b: LevelBuilder, sts: Dictionary, x: float, w: float, d: Dictionary) -> void:
	var conc := RoadsideBuilder._textured(b, "abutment", "concrete", Color(0.86, 0.84, 0.78))
	if conc is StandardMaterial3D and not (conc as StandardMaterial3D).emission_enabled:
		# Lifted a little: under the deck it is in the bridge's own shade, and should still read as concrete.
		conc.emission_enabled = true
		conc.emission = Color(0.5, 0.49, 0.46)
		conc.emission_energy_multiplier = 0.18
	var stain := _m(b, "abutment_stain", Color(0.36, 0.36, 0.33), 0.9)
	var steel := _m(b, "girder", Color(0.33, 0.39, 0.37), 0.6, 0.4)
	var rust := _m(b, "girder_rust", Color(0.32, 0.2, 0.13), 0.85, 0.3)
	var top := BRIDGE_Y + 0.9
	# The abutment wall behind the footpath, rain streaks down it, and the embankment behind.
	RoadsideBuilder._wall_face(b, conc, x, x + w, 0.0, BRIDGE_Y, BRIDGE_Z0 + 0.01)
	b._box(Vector3(w, BRIDGE_Y, 3.0), Vector3(x + w * 0.5, BRIDGE_Y * 0.5, BRIDGE_Z0 - 1.5), _m(b, "abutment_mass", Color(0.4, 0.4, 0.38), 0.9))
	var sx := x + 0.6
	while sx < x + w - 0.3:
		RoadsideBuilder._add(sts, stain, sx, sx + 0.25, 0.4, BRIDGE_Y - 0.1, BRIDGE_Z0 + 0.012, BRIDGE_Z0 + 0.02)
		sx += 1.3 + fmod(sx * 7.3, 1.1)
	RoadsideBuilder._add(sts, _m(b, "embankment", Color(0.28, 0.31, 0.2), 0.95), x - 1.0, x + w + 1.0, 0.0, top - 0.2, -60.0, BRIDGE_Z0 - 3.0)
	# Retaining walls either side of the embankment, the neighbours' yards beside them.
	for ex in [x - 1.0, x + w + 1.0]:
		RoadsideBuilder._add(sts, conc, ex - 0.2, ex + 0.2, 0.0, BRIDGE_Y + 0.3, -40.0, BRIDGE_Z0)
	# The deck: two plate girders along its edges and the cross girders between, over the street
	# from the abutment out past the camera.
	for gx in [x + 0.25, x + w - 0.25]:
		RoadsideBuilder._add(sts, steel, gx - 0.25, gx + 0.25, BRIDGE_Y, top, BRIDGE_Z0 - 3.0, BRIDGE_Z1)
		RoadsideBuilder._add(sts, rust, gx - 0.26, gx + 0.26, BRIDGE_Y, BRIDGE_Y + 0.12, BRIDGE_Z0 - 3.0, BRIDGE_Z1)
		var sz := BRIDGE_Z0
		while sz < BRIDGE_Z1:   # web stiffeners
			RoadsideBuilder._add(sts, steel, gx - 0.3, gx + 0.3, BRIDGE_Y + 0.1, top - 0.05, sz, sz + 0.08)
			sz += 1.2
	RoadsideBuilder._add(sts, _m(b, "deck_soffit", Color(0.3, 0.31, 0.31), 0.8), x + 0.5, x + w - 0.5, BRIDGE_Y + 0.5, BRIDGE_Y + 0.6, BRIDGE_Z0 - 3.0, BRIDGE_Z1)
	var cz := BRIDGE_Z0 + 0.6
	while cz < BRIDGE_Z1:
		RoadsideBuilder._add(sts, steel, x + 0.5, x + w - 0.5, BRIDGE_Y + 0.25, BRIDGE_Y + 0.5, cz, cz + 0.14)
		cz += 2.0
	# The parapet rail on top, and a line of ballast showing over it.
	RoadsideBuilder._add(sts, steel, x, x + w, top, top + 0.9, BRIDGE_Z0 - 3.0, BRIDGE_Z0 - 2.9)
	RoadsideBuilder._add(sts, _m(b, "ballast", Color(0.36, 0.34, 0.32), 0.95), x + 0.5, x + w - 0.5, top - 0.1, top + 0.15, BRIDGE_Z0 - 3.0, BRIDGE_Z1)
	b._cover_box(Vector3(w, 0.9, BRIDGE_Z1 - BRIDGE_Z0 + 3.0),
		Transform3D(Basis(), Vector3(x + w * 0.5, BRIDGE_Y + 0.45, (BRIDGE_Z0 - 3.0 + BRIDGE_Z1) * 0.5)))
	# Water drips off both edges across the footpath and the road, and a lamp under it.
	for ex in [x + 0.05, x + w - 0.05]:
		_drips_z(b, ex, BRIDGE_Y - 0.02, 0.0, 9.0)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 1.6
	lamp.omni_range = 6.0
	lamp.position = Vector3(x + w * 0.5, BRIDGE_Y - 0.3, 0.8)
	b.root.add_child(lamp)
	if d.has("sign"):   # a clearance or a line name on the girder's face
		ModernBuilder.sign_text(b, x + w * 0.5, BRIDGE_Y + 0.5, BRIDGE_Z1, String(d["sign"]), w - 1.0)


## A line of drips falling from a cover edge that runs across the street (along z).
static func _drips_z(b: LevelBuilder, x: float, y: float, z0: float, z1: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = int((z1 - z0) * 10.0)
	p.lifetime = 0.9
	p.randomness = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.04, 0.01, (z1 - z0) * 0.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -9.8, 0)
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.018, 0.16)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.75, 0.82, 0.95, 0.5)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mesh.material = dm
	p.draw_pass_1 = mesh
	p.position = Vector3(x, y, (z0 + z1) * 0.5)
	p.visibility_aabb = AABB(Vector3(-0.5, -y - 0.5, -(z1 - z0) * 0.5 - 0.5), Vector3(1.0, y + 1.0, z1 - z0 + 1.0))
	b.root.add_child(p)


## The pub: a two-storey 1960s brick hotel built to the footpath, green tiles round its bar
## windows, cream render above with steel windows, its name in letters on the parapet. The door is at
## the lot's x + 4 (the level ends there).
static func _pub(b: LevelBuilder, sts: Dictionary, x: float, w: float, floors: int, d: Dictionary) -> void:
	var h := 4.0 + 3.2 * floors
	var brick := RoadsideBuilder._textured(b, "pub_brick", "brick_painted", Color(0.45, 0.24, 0.17))
	var render := _m(b, "pub_render", Color(0.8, 0.74, 0.6), 0.85)
	var tile := _m(b, "pub_tile", Color(0.14, 0.3, 0.22), 0.25, 0.1)
	b._box(Vector3(w - 0.1, h, 12.0), Vector3(x + w * 0.5, h * 0.5, -6.2), _m(b, "pub_mass", Color(0.36, 0.2, 0.15), 0.9))
	RoadsideBuilder._wall_face(b, brick, x, x + w, 1.1, 4.0, 0.012)
	RoadsideBuilder._wall_face(b, render, x, x + w, 4.0, h, 0.012)
	RoadsideBuilder._add(sts, tile, x, x + w, 0.0, 1.1, -0.02, 0.05)
	RoadsideBuilder._add(sts, _m(b, "pub_tile_cap", Color(0.6, 0.55, 0.4), 0.3), x, x + w, 1.08, 1.16, -0.02, 0.07)
	var door_x := x + 4.0
	if b.inn_door_x < 0.0:
		b.inn_door_x = door_x
	var frame := _m(b, "pub_frame", Color(0.2, 0.14, 0.1), 0.5)
	var warm := RoadsideBuilder._glow(b, "pub_glow", Color(1.0, 0.7, 0.4), 1.1)
	# The double doors, lit glass in their top halves, and the bar windows either side.
	RoadsideBuilder._add(sts, frame, door_x - 0.85, door_x + 0.85, 0.0, 2.6, 0.0, 0.06)
	RoadsideBuilder._add(sts, _m(b, "pub_door", Color(0.32, 0.17, 0.08), 0.5), door_x - 0.75, door_x + 0.75, 0.0, 2.45, 0.03, 0.08)
	for dx in [-0.38, 0.38]:
		RoadsideBuilder._add(sts, warm, door_x + dx - 0.28, door_x + dx + 0.28, 1.3, 2.2, 0.08, 0.09)
	for wn in [[x + 0.5, door_x - 1.2], [door_x + 1.2, x + w - 0.5]]:
		if float(wn[1]) - float(wn[0]) < 0.8:
			continue
		RoadsideBuilder._add(sts, frame, wn[0] - 0.06, wn[1] + 0.06, 1.2, 2.75, 0.0, 0.05)
		RoadsideBuilder._add(sts, warm, wn[0], wn[1], 1.26, 2.7, 0.02, 0.06)
		b.lit_windows.append([Vector3((float(wn[0]) + float(wn[1])) * 0.5, 1.9, -0.9), Color(1.0, 0.7, 0.4)])
	# Upstairs: steel windows, one lit (the publican's), the rest dark.
	var steel := _m(b, "pub_steel", Color(0.16, 0.18, 0.18), 0.5, 0.5)
	for f in floors:
		var wy := 4.0 + f * 3.2 + 0.9
		var n := maxi(1, int(w / 2.0))
		for i in n:
			var wx := x + (i + 0.5) * w / n
			var lit := (i + f) % 3 == 1
			RoadsideBuilder._add(sts, steel, wx - 0.6, wx + 0.6, wy - 0.05, wy + 1.55, 0.0, 0.05)
			RoadsideBuilder._add(sts, warm if lit else b._mat("glass_dark", Color(0.03, 0.035, 0.04), 0.05, 0.3), wx - 0.54, wx + 0.54, wy, wy + 1.5, 0.02, 0.06)
	RoadsideBuilder._add(sts, _m(b, "pub_parapet", Color(0.8, 0.74, 0.6), 0.7), x - 0.05, x + w + 0.05, h, h + 0.9, -0.25, 0.1)
	var text := String(d.get("sign", "ROYAL HOTEL"))
	# Its name on the parapet, and again in the band over the awning, where the street's camera sees it.
	ModernBuilder.sign_text(b, x + w * 0.5, h + 0.2, 0.1, text, w - 0.8)
	RoadsideBuilder._add(sts, _m(b, "pub_band", Color(0.12, 0.2, 0.15), 0.4, 0.1), x, x + w, 3.12, 3.95, 0.0, 0.06)
	ModernBuilder.sign_text(b, x + w * 0.5, 3.35, 0.06, text, w - 1.0)
	ModernBuilder.sign_text(b, door_x, 2.3, 0.08, "PUBLIC BAR", 1.3)
	var sl := SpotLight3D.new()
	sl.light_color = Color(1.0, 0.85, 0.65)
	sl.light_energy = 2.0
	sl.spot_range = 6.0
	sl.spot_angle = 50.0
	sl.position = Vector3(x + w * 0.5, h - 0.5, 1.6)
	sl.rotation = Vector3(0.9, 0, 0)
	b.root.add_child(sl)


# --- side streets, poles and wires, the backdrop -----------------------------------------------------

## A side street: footpaths and nature strips down both sides, fences receding, a street sign at the
## near corner and the houses across its far end.
static func crossing(b: LevelBuilder, x0: float, x1: float) -> void:
	var sts := {}
	var path := _m(b, "footpath", Color(0.5, 0.49, 0.46), 0.55)
	var grass := _m(b, "verge", Color(0.24, 0.3, 0.17), 0.9)
	var kerb := _m(b, "kerb", Color(0.56, 0.55, 0.52), 0.5)
	for side in [[x0, 1.0], [x1, -1.0]]:
		var e: float = side[0]
		var f: float = side[1]
		var lo := minf(e, e + f * 1.6)
		var hi := maxf(e, e + f * 1.6)
		RoadsideBuilder._add(sts, path, lo, hi, -0.3, 0.0, -40.0, PATH_Z1)
		var glo := minf(e + f * 1.6, e + f * 2.5)
		var ghi := maxf(e + f * 1.6, e + f * 2.5)
		RoadsideBuilder._add(sts, grass, glo, ghi, -0.3, 0.035, -40.0, PATH_Z1)
		var klo := minf(e + f * 2.5, e + f * 2.65)
		var khi := maxf(e + f * 2.5, e + f * 2.65)
		RoadsideBuilder._add(sts, kerb, klo, khi, -0.3, 0.06, -40.0, STRIP_Z1)
		# Fences along the side street, gardens behind them.
		var fx := e - f * 0.05
		RoadsideBuilder._add(sts, _m(b, "paling", Color(0.38, 0.34, 0.28), 0.9), minf(fx, fx - f * 0.05), maxf(fx, fx - f * 0.05), 0.0, 1.8, -40.0, -0.3)
	# The street's name on a pole at the corner.
	var sx := x1 - 0.5
	RoadsideBuilder._add(sts, _m(b, "sign_pole", Color(0.55, 0.56, 0.55), 0.4, 0.6), sx - 0.04, sx + 0.04, 0.0, 2.9, 2.9, 2.98)
	RoadsideBuilder._add(sts, _m(b, "street_name", Color(0.12, 0.2, 0.36), 0.5), sx - 0.6, sx + 0.6, 2.6, 2.85, 2.96, 3.0)
	# Houses across the far end.
	var r := _rng(b, x0, "xing")
	var hx := x0 - 5.0
	while hx < x1 + 5.0:
		var hw := r.randf_range(9.0, 13.0)
		_back_house(b, sts, hx + 1.0, hx + hw - 1.0, -34.0, r, 0.0)
		hx += hw
	RoadsideBuilder._commit(b, sts)


## Power poles where the street has lamp posts (each with a sodium lamp on its arm over the road)
## and where it has bare `power_pole` props; wires run from each to the next.
static func prop(b: LevelBuilder, p: Dictionary) -> void:
	var x := float(p["x"])
	var id := String(p["id"])
	var sts := {}
	var wood := _m(b, "pole_wood", Color(0.3, 0.25, 0.2), 0.95)
	ModernBuilder.cyl(sts, wood, Vector3(x, 0.0, POLE_Z), Vector3(x, 9.0, POLE_Z), 0.15, 0.11, 8)
	# Cross-arm and insulators at the top.
	RoadsideBuilder._add(sts, wood, x - 0.06, x + 0.06, 8.5, 8.62, POLE_Z - 1.0, POLE_Z + 1.0)
	var ins := _m(b, "insulator", Color(0.75, 0.72, 0.65), 0.3)
	for dz in [-0.9, -0.3, 0.3, 0.9]:
		RoadsideBuilder._add(sts, ins, x - 0.04, x + 0.04, 8.62, 8.8, POLE_Z + dz - 0.04, POLE_Z + dz + 0.04)
	if id == "lamp_post":
		var steel := _m(b, "lamp_arm", Color(0.5, 0.52, 0.52), 0.4, 0.6)
		var arm := b._box(Vector3(0.06, 0.06, 2.0), Vector3(x, 6.75, POLE_Z + 0.95), steel)
		arm.rotation.x = -0.12
		var lamp_state := String(p.get("lamp", "on"))
		RoadsideBuilder._add(sts, steel, x - 0.18, x + 0.18, 6.75, 6.92, POLE_Z + 1.6, POLE_Z + 2.3)
		var glow := b._neon_mat(Color(1.0, 0.62, 0.28), 2.2) if lamp_state != "out" else _m(b, "lamp_dead", Color(0.3, 0.28, 0.24), 0.4)
		var lens := b._box(Vector3(0.3, 0.06, 0.55), Vector3(x, 6.72, POLE_Z + 1.95), glow)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if lamp_state != "out":
			var sl := SpotLight3D.new()
			sl.light_color = Color(1.0, 0.66, 0.36)
			sl.light_energy = 1.8
			sl.spot_range = 10.0
			sl.spot_angle = 58.0
			sl.light_volumetric_fog_energy = 1.0
			sl.shadow_enabled = false
			sl.position = Vector3(x, 6.6, POLE_Z + 1.6)
			sl.rotation = Vector3(-PI * 0.5 + 0.25, 0, 0)
			b.root.add_child(sl)
			if lamp_state == "flicker":
				sl.set_script(load("res://src/fx/lamp_flicker.gd"))
				sl.set("lens", lens)
	RoadsideBuilder._commit(b, sts)


## Wires strung from pole to pole along the nature strip, sagging between them.
static func wires(b: LevelBuilder) -> void:
	var xs: Array = []
	for p in b.data.get("props", []):
		if PROPS.has(String(p.get("id", ""))):
			xs.append(float(p["x"]))
	xs.sort()
	var wire := _m(b, "power_wire", Color(0.08, 0.08, 0.08), 0.5)
	for i in xs.size() - 1:
		var a: float = xs[i]
		var c: float = xs[i + 1]
		if c - a > 60.0:
			continue
		for dz in [-0.9, -0.3, 0.3, 0.9]:
			var segs := 6
			for k in segs:
				var t0 := float(k) / segs
				var t1 := float(k + 1) / segs
				var y0 := 8.8 - 0.7 * 4.0 * t0 * (1.0 - t0)
				var y1 := 8.8 - 0.7 * 4.0 * t1 * (1.0 - t1)
				var p0 := Vector3(lerpf(a, c, t0), y0, POLE_Z + dz)
				var p1 := Vector3(lerpf(a, c, t1), y1, POLE_Z + dz)
				var seg := b._box(Vector3(p0.distance_to(p1), 0.018, 0.018), (p0 + p1) * 0.5, wire)
				seg.rotation.z = atan2(y1 - y0, p1.x - p0.x)
				seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Behind the street: the back yards and the rows of houses facing the next street, their roofs and
## trees over the fences, thinning to paddock where the lots in front have `thin`; low hills beyond.
static func backdrop(b: LevelBuilder) -> void:
	land(b)
	wires(b)
	var L: float = b.data["length"]
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(b.data.get("id", "level")) + ":suburb")
	var sts := {}
	var hx := -40.0
	while hx < L + 40.0:
		var hw := r.randf_range(10.0, 15.0)
		var thin := _thin_at(b, hx + hw * 0.5)
		if r.randf() >= thin * 0.9:
			_back_house(b, sts, hx + r.randf_range(1.0, 2.5), hx + hw - r.randf_range(1.0, 2.5), -28.0 - r.randf() * 3.0, r, thin)
		if r.randf() < 0.35 + thin * 0.5:
			park_tree(b, Vector3(hx + r.randf() * hw, 0.0, -22.0 - r.randf() * 30.0), r, 0.8 + r.randf() * 0.5)
		if thin >= 0.5:
			# The paddock: a post-and-wire fence across the back of the yards, open grass beyond.
			RoadsideBuilder._add(sts, _m(b, "paddock", Color(0.5, 0.5, 0.27), 0.95), hx, hx + hw, -0.04, 0.01, -150.0, -24.0)
			var post := _m(b, "fence_post", Color(0.34, 0.3, 0.24), 0.9)
			var px := hx
			while px < hx + hw:
				RoadsideBuilder._add(sts, post, px - 0.05, px + 0.05, 0.0, 1.2, -24.05, -23.95)
				px += 3.0
		hx += hw
	# A second row further off, then the hills: long, low and pale in the rain.
	hx = -80.0
	while hx < L + 80.0:
		var hw := r.randf_range(9.0, 16.0)
		if r.randf() >= _thin_at(b, hx) * 0.95:
			_back_house(b, sts, hx + 1.0, hx + hw - 1.0, -58.0 - r.randf() * 6.0, r, 0.4)
		hx += hw
	var hill := _m(b, "hills", Color(0.3, 0.33, 0.29), 1.0)
	var st := RailwayBuilder._st(sts, hill)
	var x := -300.0
	var prev := 6.0
	while x < L + 300.0:
		var nx := x + 30.0
		var hy := 6.0 + 9.0 * (0.5 + 0.5 * sin(nx * 0.011 + 1.3)) + 4.0 * sin(nx * 0.031)
		ViaductBuilder._tri(st, Vector3(x, -1.0, -190.0), Vector3(nx, -1.0, -190.0), Vector3(nx, hy, -190.0), Vector3.BACK)
		ViaductBuilder._tri(st, Vector3(x, -1.0, -190.0), Vector3(nx, hy, -190.0), Vector3(x, prev, -190.0), Vector3.BACK)
		prev = hy
		x = nx
	RoadsideBuilder._commit(b, sts)


static func _thin_at(b: LevelBuilder, x: float) -> float:
	for l in b.data.get("lots", []):
		if x >= float(l["x"]) and x < float(l["x"]) + float(l["w"]):
			return clampf(float(l.get("thin", 0.0)), 0.0, 1.0)
	return 0.0


## A house seen over the back fences: walls, a hipped roof, sometimes a lit window.
static func _back_house(b: LevelBuilder, sts: Dictionary, x0: float, x1: float, z: float, r: RandomNumberGenerator, thin: float) -> void:
	var wall: Color = (BRICKS + BOARDS)[r.randi() % 8]
	var h := 3.1
	RoadsideBuilder._add(sts, _m(b, "back_wall_%s" % wall.to_html(), wall.darkened(0.15), 0.9), x0, x1, 0.0, h, z - 9.0, z)
	var roof_c: Color = (TILES + IRON)[r.randi() % 8]
	_roof(b, sts, _m(b, "back_roof_%s" % roof_c.to_html(), roof_c, 0.7), _m(b, "back_wall_%s" % wall.to_html(), wall.darkened(0.15), 0.9),
		x0 - 0.5, x1 + 0.5, z + 0.5, z - 9.5, h, 2.2, r.randf() < 0.6)
	if r.randf() < 0.3 * (1.0 - thin):
		var wx := lerpf(x0, x1, r.randf_range(0.2, 0.8))
		RoadsideBuilder._add(sts, RoadsideBuilder._glow(b, "back_win", Color(1.0, 0.72, 0.42), 0.7), wx - 0.6, wx + 0.6, 1.0, 2.1, z, z + 0.03)
	# A back fence in front of it.
	RoadsideBuilder._add(sts, _m(b, "paling", Color(0.38, 0.34, 0.28), 0.9), x0 - 1.0, x1 + 1.0, 0.0, 1.8, z + 5.0, z + 5.06)


# --- trees -----------------------------------------------------------------------------------------

## A street tree on the nature strip at x, its foliage tagged with the lot's span x0..x1 (under
## `parent`, TreeCover's node): a plane (kind 0) or a gum (1), the model if there is one, else drawn
## here. Its leaves are in the `&"foliage"` group on the foliage shader; its crown is over the footpath
## with nothing but the trunk below 3.4 m there.
static func street_tree(b: LevelBuilder, parent: Node3D, x: float, x0: float, x1: float, kind: int, r: RandomNumberGenerator) -> void:
	var m := TreeCover.model(b, TREE_MODELS[kind % TREE_MODELS.size()], Vector3(x, 0.0, TREE_Z), parent)
	if m:
		m.scale = Vector3.ONE * r.randf_range(0.94, 1.05)
		m.rotation.y = r.randf_range(-0.12, 0.12)
		TreeCover.tag_foliage(m, x0, x1)
		return
	_code_tree(b, Vector3(x, 0.0, TREE_Z), kind, r, 1.0)


## A tree standing back in a park or a yard: smaller masses on a short trunk, drawn here.
static func park_tree(b: LevelBuilder, at: Vector3, r: RandomNumberGenerator, s := 1.0) -> void:
	_code_tree(b, at, r.randi() % 2, r, s, false)


static func _code_tree(b: LevelBuilder, at: Vector3, kind: int, r: RandomNumberGenerator, s: float, over_path := true) -> void:
	var sts := {}
	var bark := _m(b, "bark_gum" if kind == 1 else "bark", Color(0.62, 0.58, 0.5) if kind == 1 else Color(0.27, 0.22, 0.17), 0.9)
	var lean := Vector3(0.0, 0.0, -1.3 if over_path else 0.0)   # a street tree leans its head over the footpath
	var fork := at + Vector3(0, 3.8 * s, 0) + lean * 0.5
	ModernBuilder.cyl(sts, bark, at, fork, 0.24 * s, 0.17 * s, 8)
	ModernBuilder.cyl(sts, bark, fork, fork + Vector3(-1.2, 2.2, 0) * s + lean * 0.3, 0.15 * s, 0.08 * s, 6)
	ModernBuilder.cyl(sts, bark, fork, fork + Vector3(1.3, 2.4, -0.4) * s + lean * 0.3, 0.15 * s, 0.08 * s, 6)
	RoadsideBuilder._commit(b, sts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.17, 0.25, 0.12) if kind == 0 else Color(0.32, 0.36, 0.26)
	var head := at + Vector3(0, 6.4 * s, 0) + lean
	for i in 7 if kind == 0 else 9:
		var off := Vector3(r.randf_range(-3.4, 3.4), r.randf_range(-1.2, 1.8), r.randf_range(-1.8, 1.8)) * s
		var rad := Vector3.ONE * r.randf_range(1.6, 2.4) * s * (0.8 if kind == 1 else 1.0)
		rad.y *= 0.75 if kind == 0 else 0.6
		var c := head + off
		if over_path:
			c.y = maxf(c.y, at.y + 3.4 + rad.y)   # nothing but the trunk below 3.4 m over the footpath
		_blob(st, c, rad, base.lerp(base.lightened(0.25), r.randf()), 0.3, 1.0, r)
	_foliage_mesh(b, st, at)


## A rough ellipsoid of leaves in `col`, sway weight from w0 at its base to w1 at its top.
static func _blob(st: SurfaceTool, c: Vector3, rad: Vector3, col: Color, w0: float, w1: float, r: RandomNumberGenerator) -> void:
	var rings := 4
	var segs := 7
	var pts: Array = []
	for j in rings + 1:
		var row: Array = []
		var t := PI * j / rings
		for i in segs:
			var a := TAU * i / segs
			var bump := 1.0 + r.randf_range(-0.14, 0.14)
			row.append(Vector3(sin(t) * cos(a) * rad.x, cos(t) * rad.y, sin(t) * sin(a) * rad.z) * bump)
		pts.append(row)
	for j in rings:
		for i in segs:
			var q: Array = [pts[j][i], pts[j][(i + 1) % segs], pts[j + 1][(i + 1) % segs], pts[j + 1][i]]
			for k: int in [0, 1, 2, 0, 2, 3]:
				var p: Vector3 = q[k]
				var shade := 0.75 + 0.25 * (p.y / maxf(rad.y, 0.01))
				st.set_color(Color(col.r * shade, col.g * shade, col.b * shade, lerpf(w0, w1, 0.5 + 0.5 * p.y / maxf(rad.y, 0.01))))
				st.set_normal(p.normalized())
				st.add_vertex(c + p)


static func _foliage_mesh(b: LevelBuilder, st: SurfaceTool, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var fm := TreeCover.foliage_material(b, TreeCover.LEAF_DARK, TreeCover.LEAF_LIGHT, 0.06, at.y, 4.0)
	fm.set_shader_parameter("vertex_paint", true)   # painted in the vertex colours, COLOR.a its sway weight
	mi.material_override = fm
	mi.set_meta("x0", at.x - 2.0)
	mi.set_meta("x1", at.x + 2.0)
	# Its node sits at the plant's foot so the gust reads its x; the mesh is in world coordinates.
	mi.position = at
	mi.mesh = _shifted(mi.mesh, -at)
	mi.add_to_group(&"foliage")
	b.root.add_child(mi)


static func _shifted(mesh: ArrayMesh, by: Vector3) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += by
	arrays[Mesh.ARRAY_VERTEX] = v
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# --- rain cover map, mood --------------------------------------------------------------------------

## The overbridge in the visual rain's cover map (LevelBuilder.cover_map): open air under a deck, from
## the wall out past the camera. (`shelter` and `porch` are CountryBuilder's.)
static func cover_map(b: LevelBuilder, img: Image, x0: float) -> void:
	for l in b.data.get("lots", []):
		var lx := float(l["x"])
		var lw := float(l["w"])
		if String(l.get("cover", "none")) == "bridge" and String(l.get("style", "")) == "overbridge":
			b._cover_fill(img, x0, lx, lx + lw, 0.0, LevelBuilder.COVER_Z1, func(_z): return BRIDGE_Y + 0.9, LevelBuilder.COVER_HIDE)


## The street's light: a grey, rainy late afternoon, real daylight under a lighter, broken sky;
## brighter than the city's night streets, darker than the open country. Called by Level after the
## default environment is set up.
static func mood(env: Environment, sun: DirectionalLight3D) -> void:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://src/fx/overcast_sky.gdshader")
	env.sky.sky_material = sm
	env.ambient_light_energy = 0.9
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_exposure = 1.15
	env.volumetric_fog_density = 0.016
	env.volumetric_fog_albedo = Color(0.62, 0.64, 0.66)
	env.volumetric_fog_emission = Color(0.07, 0.075, 0.08)
	env.fog_light_color = Color(0.46, 0.48, 0.5)
	env.fog_density = 0.009
	env.adjustment_saturation = 0.86
	sun.light_color = Color(0.84, 0.86, 0.9)
	sun.light_energy = 0.75
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-35), 0)


## The sun break's light here: a low late sun from behind and left of the street, warm, throwing
## long shadows toward the camera. [position offset from the break's centre, colour, energy].
static func low_sun(cx: float, w: float) -> Array:
	return [Vector3(cx - 14.0, 9.5, -16.0), Color(1.0, 0.72, 0.42), 16.0]


# --- helpers ---------------------------------------------------------------------------------------

static func _m(b: LevelBuilder, key: String, col: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	return b._mat("sub_" + key, col, rough, metal)


static func _tri(sts: Dictionary, mat: Material, a: Vector3, c: Vector3, e: Vector3, hint: Vector3) -> void:
	var n := (c - a).cross(e - a).normalized()
	if n.dot(hint) < 0.0:
		n = -n
	ViaductBuilder._tri(RailwayBuilder._st(sts, mat), a, c, e, n)


static func _quad(sts: Dictionary, mat: Material, a: Vector3, c: Vector3, e: Vector3, f: Vector3, hint: Vector3) -> void:
	_tri(sts, mat, a, c, e, hint)
	_tri(sts, mat, a, e, f, hint)
