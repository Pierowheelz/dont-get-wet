class_name CountryBuilder
extends RefCounted
## The country (`aesthetic: "country"`), drawn in code and called from LevelBuilder like the
## roadside's and the glass city's. No pavement: the walker follows a worn footpath along a grass
## verge at the pavement's height, with hedges and fields behind him and a narrow lane in front.
## Lot styles (any street may use them; only a country street gets the verge, the lane and the hills):
##   hedge        a hawthorn hedge along the lot line, fields beyond (no cover)
##   field_gate   the hedge with a gap and a five-bar gate in it, a track into the field (no cover)
##   stone_wall   a dry stone wall with its coping stones on end (no cover)
##   tree         a big old broadleaf in the hedge, its crown reaching out over the verge; give it
##                `cover: "trees"` (TreeCover: the crown keeps off all but `tree_leak` of the rain)
##   bus_shelter  a timber shelter with a tin roof over the path (`cover: "shelter"`)
##   barn         an open-fronted Dutch barn full of hay (`cover: "barn"`)
##   lychgate     a roofed churchyard gate over the path, the church behind (`cover: "shelter"`)
##   cottage      a cottage on the lane; `cover: "porch"` puts a porch over its door
##   inn          on a country street, the pub at the end: its door is INN_DOOR into the lot
## Cover is gameplay and lives in code: the colliders and the rain's cover map use the constants
## below (a tree's are TreeCover's), never the drawn shapes. Everything else is visual. Where
## res://assets/country/<name>.glb exists the model replaces the code's stand-in (docs/CONTRACTS.md
## §10); a model's materials whose names contain "foliage" or "leaf" become the swaying foliage shader.
## Every leafy mesh (trees, hedges a few metres at a time) is in the node group &"foliage" with its
## own material on src/fx/foliage.gdshader (`gust`, `gust_dir`), and has metas "x0" and "x1".
## Runs inside LevelBuilder.build, possibly on a worker thread: it only adds nodes.

const STYLES := ["hedge", "field_gate", "stone_wall", "tree", "bus_shelter", "barn", "lychgate", "cottage"]
const COVERS := ["shelter", "barn", "porch"]   # with `trees` (TreeCover), the country's cover values

# Gameplay geometry. Colliders and the rain's cover map read only these.
const SHELTER_Y := 2.6      # underside of a bus shelter's or lychgate's roof
const SHELTER_Z := 2.4      # how far its roof reaches toward the lane
const PORCH_Y := 2.55
const PORCH_Z := 2.35
const PORCH_W := 2.6        # a porch's width when the lot gives no `porch` span, centred on the door
const BARN_Y := 4.4         # the barn roof's underside at its eaves
const BARN_Z := 2.6         # its front edge
const BARN_BACK := -7.0
const INN_DOOR := 4.0       # the pub's door is this far into its lot, as the kit inn's is

# Visual layout.
const HEDGE_H := 1.75
const HEDGE_Z := -0.45      # the hedge's centre line
const HEDGE_Z0 := -1.0
const HEDGE_Z1 := 0.1
const WALL_H := 1.15
const WALL_Z := -0.3
const GATE_W := 3.6
const PATH_Z0 := 0.95       # the worn footpath down the verge (the walker's line is 1.6)
const PATH_Z1 := 2.25
const LANE_Z1 := 9.5        # the far edge of the lane
const POLE_GAP := 42.0      # telegraph poles along the hedge line
const POLE_Z := -0.55
const WIRE_Y := 7.3
const HEDGE_PIECE := 4.0    # a hedge is drawn as nodes about this long, so a gust moves it piecewise

const HEDGE_DARK := Color(0.05, 0.09, 0.04)
const HEDGE_LIGHT := Color(0.2, 0.28, 0.1)


# --- lots ------------------------------------------------------------------------------------------

static func lot(b: LevelBuilder, x: float, w: float, style: String, lot_d: Dictionary) -> void:
	match style:
		"hedge":
			hedge(b, x, x + w)
		"field_gate":
			_field_gate(b, x, w)
		"stone_wall":
			stone_wall(b, x, x + w)
		"tree":
			_tree_lot(b, x, w)
		"bus_shelter":
			_bus_shelter(b, x, w)
		"barn":
			_barn(b, x, w)
		"lychgate":
			_lychgate(b, x, w)
		"cottage":
			_cottage(b, x, w, lot_d)
		"inn":
			_pub(b, x, w, lot_d)


## The lot's cover (a value of COVERS): its collider on the `cover` layer and its drip line. A porch also draws itself, since it is only as wide as its span.
static func cover(b: LevelBuilder, lot_d: Dictionary) -> void:
	var x := float(lot_d["x"])
	var w := float(lot_d["w"])
	var style := String(lot_d.get("style", ""))
	match String(lot_d.get("cover", "none")):
		"shelter":
			if style not in ["bus_shelter", "lychgate"]:
				push_warning("level %s: cover shelter at x=%.1f wants a bus_shelter or lychgate lot" % [b.data.get("id", "?"), x])
			b._cover_box(Vector3(w, 0.2, SHELTER_Z), Transform3D(Basis(), Vector3(x + w * 0.5, SHELTER_Y + 0.1, SHELTER_Z * 0.5)))
			b._drips(x + 0.1, x + w - 0.1, SHELTER_Y - 0.02, SHELTER_Z + 0.05)
		"barn":
			if style != "barn":
				push_warning("level %s: cover barn at x=%.1f on a '%s' lot" % [b.data.get("id", "?"), x, style])
			b._cover_box(Vector3(w, 0.25, BARN_Z - BARN_BACK), Transform3D(Basis(), Vector3(x + w * 0.5, BARN_Y + 0.12, (BARN_Z + BARN_BACK) * 0.5)))
			b._drips(x + 0.1, x + w - 0.1, BARN_Y - 0.05, BARN_Z + 0.05)
		"porch":
			var sp := porch_span(lot_d)
			b._cover_box(Vector3(sp[1] - sp[0], 0.2, PORCH_Z), Transform3D(Basis(), Vector3(x + (sp[0] + sp[1]) * 0.5, PORCH_Y + 0.1, PORCH_Z * 0.5)))
			b._drips(x + sp[0] + 0.05, x + sp[1] - 0.05, PORCH_Y - 0.02, PORCH_Z + 0.05)
			_porch(b, x + sp[0], x + sp[1])


## Local [x0, x1] of a `porch` lot's porch: the lot's `porch` field, else PORCH_W centred on its door.
static func porch_span(lot_d: Dictionary) -> Array:
	var w := float(lot_d["w"])
	if lot_d.has("porch"):
		return [clampf(float(lot_d["porch"][0]), 0.0, w), clampf(float(lot_d["porch"][1]), 0.0, w)]
	var d := door_x(lot_d)
	var a := clampf(d - PORCH_W * 0.5, 0.0, maxf(w - PORCH_W, 0.0))
	return [a, minf(a + PORCH_W, w)]


## Local x of a cottage's or the pub's front door (`door` overrides a cottage's).
static func door_x(lot_d: Dictionary) -> float:
	if String(lot_d.get("style", "")) == "inn":
		return INN_DOOR
	return float(lot_d.get("door", float(lot_d["w"]) * 0.5))


## Height of the rain-stopping surface of a cover at depth z (the rain's cover map): on its roof,
## falling toward the lane, so no drop shows under it.
static func cover_top(kind: String, z := 0.0) -> float:
	var back := clampf(1.0 - z / SHELTER_Z, 0.0, 1.0)
	match kind:
		"shelter": return SHELTER_Y + 0.05 + 0.4 * back
		"porch": return PORCH_Y + 0.2
		"barn": return BARN_Y + 0.25
	return 0.0


# --- hedges, walls, gates --------------------------------------------------------------------------

## A hawthorn hedge from a to b along the lot line: a model tiled every 4 m, or clumps of leaves
## over a dark core.
static func hedge(b: LevelBuilder, a: float, c: float, z := HEDGE_Z) -> void:
	if c - a < 0.3:
		return
	var n := maxi(1, roundi((c - a) / HEDGE_PIECE))
	var tw := (c - a) / n
	for i in n:
		var a0 := a + tw * i
		var m := TreeCover.model(b, "hedge_4m", Vector3(a0, 0.0, z - HEDGE_Z))
		if m:
			m.scale.x = tw / 4.0
			TreeCover.tag_foliage(m, a0, a0 + tw)
		else:
			_hedge_piece(b, a0, a0 + tw, z)


## One piece of hedge drawn in code: small clumps of leaves scattered over the face and along a
## wandering top, over a dark core.
static func _hedge_piece(b: LevelBuilder, a: float, c: float, z: float) -> void:
	var o := Vector3((a + c) * 0.5, 0.0, z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = b._lot_hash(a, "hedge")
	_slab(st, Vector3(a + 0.02, 0.0, z - 0.42) - o, Vector3(c - 0.02, HEDGE_H - 0.3, z + 0.3) - o)
	var px := a + 0.12
	while px < c - 0.1:
		var top := HEDGE_H + 0.18 * sin(px * 0.9 + float(r.randi() % 7)) - 0.1
		for k in 3:
			var rad := r.randf_range(0.26, 0.42)
			var py := r.randf_range(0.25, top - rad * 0.5) if k < 2 else top - rad * 0.6
			var face := z + 0.28 - absf(py - top * 0.5) * 0.12 if k < 2 else z + r.randf_range(-0.3, 0.2)
			TreeCover.puff(st, Vector3(px + r.randf_range(-0.12, 0.12), py, face) - o, rad, 0.8,
				Vector3(px, top * 0.45, z - 0.8) - o, r.randi(), 7, 4, 0.75)
		px += r.randf_range(0.24, 0.36)
	TreeCover.foliage_node(b, st, o, a, c, HEDGE_DARK, HEDGE_LIGHT, 0.025, 0.2, 1.6).material_override.set_shader_parameter("leaf_scale", 3.2)


## A box of foliage (a hedge's dense core), its faces' normals out from its centre.
static func _slab(st: SurfaceTool, p0: Vector3, p1: Vector3) -> void:
	var c := (p0 + p1) * 0.5
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z)
	var faces := [
		[v.call(p0.x, p0.y, p1.z), v.call(p1.x, p0.y, p1.z), v.call(p1.x, p1.y, p1.z), v.call(p0.x, p1.y, p1.z)],
		[v.call(p0.x, p1.y, p0.z), v.call(p1.x, p1.y, p0.z), v.call(p1.x, p1.y, p1.z), v.call(p0.x, p1.y, p1.z)],
		[v.call(p0.x, p0.y, p0.z), v.call(p0.x, p0.y, p1.z), v.call(p0.x, p1.y, p1.z), v.call(p0.x, p1.y, p0.z)],
		[v.call(p1.x, p0.y, p0.z), v.call(p1.x, p0.y, p1.z), v.call(p1.x, p1.y, p1.z), v.call(p1.x, p1.y, p0.z)],
	]
	for q in faces:
		TreeCover.tri_out(st, q[0], q[1], q[2], c, c)
		TreeCover.tri_out(st, q[0], q[2], q[3], c, c)


static func stone_wall(b: LevelBuilder, a: float, c: float) -> void:
	var sts := {}
	var stones := []
	for col in [Color(0.42, 0.4, 0.36), Color(0.34, 0.33, 0.3), Color(0.47, 0.44, 0.38), Color(0.38, 0.36, 0.31), Color(0.3, 0.31, 0.26)]:
		stones.append(b._mat("drystone_%s" % col.to_html(), col, 0.85))
	var moss := b._mat("drystone_moss", Color(0.2, 0.25, 0.11), 0.9)
	var r := RandomNumberGenerator.new()
	r.seed = b._lot_hash(a, "wall")
	var core := b._mat("drystone_core", Color(0.16, 0.16, 0.14), 0.9)
	RoadsideBuilder._add(sts, core, a, c, 0.0, WALL_H - 0.12, WALL_Z - 0.22, WALL_Z + 0.17)
	# Courses of rough stones, each its own size, set in and out of the face, thicker low down.
	var y := 0.0
	var row := 0
	while y < WALL_H - 0.18:
		var course := r.randf_range(0.12, 0.2) * (1.25 if row == 0 else 1.0)
		var batter := 0.06 * (1.0 - y / WALL_H)
		var sx := a - r.randf() * 0.2
		while sx < c - 0.02:
			var len := r.randf_range(0.18, 0.55)
			var x0 := maxf(sx, a)
			var x1 := minf(sx + len - 0.025, c)
			if x1 - x0 > 0.05:
				var hgt := course * r.randf_range(0.7, 1.0)
				var y0 := y + r.randf_range(0.0, course - hgt)
				var zf := WALL_Z + 0.18 + batter + r.randf_range(-0.05, 0.05)
				var m: Material = moss if r.randf() < 0.07 else stones[r.randi() % stones.size()]
				RoadsideBuilder._add(sts, m, x0, x1, y0, y0 + hgt, WALL_Z - 0.2, zf)
			sx += len
		y += course
		row += 1
	# The coping: flat stones set on end along the top, leaning a little this way and that.
	var cx := a
	while cx < c - 0.05:
		var t := r.randf_range(0.07, 0.13)
		var hh := r.randf_range(0.2, 0.32)
		var m: Material = moss if r.randf() < 0.25 else stones[r.randi() % stones.size()]
		RoadsideBuilder._add(sts, m, cx, minf(cx + t, c), y, y + hh, WALL_Z - 0.2, WALL_Z + 0.16)
		cx += t + r.randf_range(0.0, 0.03)
	RoadsideBuilder._commit(b, sts)


static func _field_gate(b: LevelBuilder, x: float, w: float) -> void:
	var g0 := x + maxf((w - GATE_W) * 0.5, 0.0)
	var g1 := minf(g0 + GATE_W, x + w)
	hedge(b, x, g0 - 0.15)
	hedge(b, g1 + 0.15, x + w)
	var m := TreeCover.model(b, "gate", Vector3(g0, 0.0, 0.0))
	if m:
		m.scale.x = (g1 - g0) / GATE_W
	else:
		_gate(b, g0, g1)
	# A muddy track through the gap and away across the field.
	var track := b._mat("field_track", Color(0.17, 0.13, 0.09), 0.35)
	b._box(Vector3(g1 - g0 - 0.4, 0.02, 14.0), Vector3((g0 + g1) * 0.5, 0.0, -7.5), track)
	var r := RandomNumberGenerator.new()
	r.seed = b._lot_hash(x, "bales")
	if r.randf() < 0.6:
		_bales(b, (g0 + g1) * 0.5 + r.randf_range(-6.0, 6.0), -9.0 - r.randf() * 6.0)


## A five-bar field gate, shut, between its two posts.
static func _gate(b: LevelBuilder, g0: float, g1: float) -> void:
	var sts := {}
	var wood := b._mat("gate_wood", Color(0.5, 0.47, 0.4), 0.8)
	var post := b._mat("gate_post", Color(0.27, 0.22, 0.17), 0.85)
	var z := HEDGE_Z + 0.1
	RoadsideBuilder._add(sts, post, g0 - 0.12, g0 + 0.12, 0.0, 1.45, z - 0.12, z + 0.12)
	RoadsideBuilder._add(sts, post, g1 - 0.12, g1 + 0.12, 0.0, 1.45, z - 0.12, z + 0.12)
	var a := g0 + 0.16
	var c := g1 - 0.2
	RoadsideBuilder._add(sts, wood, a, a + 0.1, 0.12, 1.22, z - 0.04, z + 0.04)   # the hanging stile
	RoadsideBuilder._add(sts, wood, c - 0.08, c, 0.12, 1.15, z - 0.04, z + 0.04)  # the head
	for i in 5:
		var y := 0.24 + i * 0.22
		RoadsideBuilder._add(sts, wood, a, c, y, y + (0.1 if i == 4 else 0.07), z - 0.03, z + 0.03)
	RoadsideBuilder._commit(b, sts)
	# The brace, from the foot of the hanging stile up to the head.
	var br := b._box(Vector3(Vector2(c - a, 0.9).length(), 0.07, 0.05), Vector3((a + c) * 0.5, 0.72, z + 0.04), wood)
	br.rotation.z = atan2(0.86, c - a)


## Two round bales of hay in a field.
static func _bales(b: LevelBuilder, x: float, z: float) -> void:
	var m := TreeCover.model(b, "hay_bales", Vector3(x, 0.0, z))
	if m:
		return
	var sts := {}
	var hay := _hay_mat(b)
	for i in 2:
		var bx := x + i * 1.7
		ModernBuilder.cyl(sts, hay, Vector3(bx, 0.72, z - 0.6), Vector3(bx, 0.72, z + 0.6), 0.72, 0.72, 16)
	RoadsideBuilder._commit(b, sts)


# --- trees -----------------------------------------------------------------------------------------

## A tree lot: the hedge runs on under it and a big old tree grows out of it (TreeCover: an oak model
## if there is one, else one drawn in code), its crown out over the verge.
static func _tree_lot(b: LevelBuilder, x: float, w: float) -> void:
	hedge(b, x, x + w)
	TreeCover.build(b, x, w, {"models": ["oak_a", "oak_b"]})


# --- shelters --------------------------------------------------------------------------------------

## A country bus shelter over the path: a timber back and end screens (stopping short of the path),
## front posts beyond the walker's line, a tin roof falling toward the lane, a bench and a timetable.
static func _bus_shelter(b: LevelBuilder, x: float, w: float) -> void:
	hedge(b, x - 0.01, x + 0.3)
	hedge(b, x + w - 0.3, x + w + 0.01)
	var m := TreeCover.model(b, "bus_shelter", Vector3(x, 0.0, 0.0))
	if m:
		m.scale.x = w / 4.0
		return
	var sts := {}
	var timber := b._mat("shelter_timber", Color(0.42, 0.33, 0.22), 0.75)
	var trim := b._mat("shelter_trim", Color(0.12, 0.22, 0.14), 0.6)
	var tin := b._mat("shelter_tin", Color(0.35, 0.33, 0.3), 0.45, 0.5)
	var back := SHELTER_Y + 0.35
	RoadsideBuilder._add(sts, timber, x, x + w, 0.0, back, -0.12, 0.0)
	for i in int(w / 0.2):   # boards
		var bx := x + 0.1 + i * 0.2
		RoadsideBuilder._add(sts, b._mat("shelter_timber_b", Color(0.3, 0.23, 0.15), 0.8), bx, bx + 0.02, 0.0, back, 0.0, 0.012)
	for ex in [x + 0.06, x + w - 0.06]:
		RoadsideBuilder._add(sts, timber, ex - 0.05, ex + 0.05, 0.3, SHELTER_Y - 0.05, 0.0, 0.75)   # end screen, clear of the path
		RoadsideBuilder._add(sts, trim, ex - 0.07, ex + 0.07, 0.0, SHELTER_Y, SHELTER_Z - 0.16, SHELTER_Z - 0.02)   # front post
	RoadsideBuilder._add(sts, trim, x, x + w, SHELTER_Y, SHELTER_Y + 0.16, SHELTER_Z - 0.16, SHELTER_Z)   # front beam
	# Bench along the back.
	RoadsideBuilder._add(sts, timber, x + 0.3, x + w - 0.3, 0.42, 0.48, 0.02, 0.4)
	RoadsideBuilder._add(sts, timber, x + 0.4, x + 0.5, 0.0, 0.42, 0.05, 0.35)
	RoadsideBuilder._add(sts, timber, x + w - 0.5, x + w - 0.4, 0.0, 0.42, 0.05, 0.35)
	# Timetable board.
	RoadsideBuilder._add(sts, b._mat("timetable", Color(0.75, 0.72, 0.62), 0.6), x + w * 0.5 - 0.3, x + w * 0.5 + 0.3, 1.3, 1.75, 0.0, 0.02)
	RoadsideBuilder._commit(b, sts)
	# The roof, falling toward the lane, corrugated.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(w / 0.1)
	for i in n:
		var xa := x - 0.1 + (w + 0.2) * i / n
		var xb := x - 0.1 + (w + 0.2) * (i + 1) / n
		var ya := 0.03 * sin(i * PI * 0.5)
		var yb := 0.03 * sin((i + 1) * PI * 0.5)
		_quad_up(st, Vector3(xa, back + 0.05 + ya, -0.25), Vector3(xb, back + 0.05 + yb, -0.25),
			Vector3(xb, SHELTER_Y + 0.17 + yb, SHELTER_Z + 0.2), Vector3(xa, SHELTER_Y + 0.17 + ya, SHELTER_Z + 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = tin
	b.root.add_child(mi)
	var lbl := Label3D.new()
	lbl.text = "BUS STOP"
	lbl.font_size = 40
	lbl.pixel_size = 0.004
	if b.sign_font:
		lbl.font = b.sign_font
	lbl.modulate = Color(0.85, 0.82, 0.7)
	lbl.shaded = true
	lbl.position = Vector3(x + w * 0.5, SHELTER_Y + 0.08, SHELTER_Z + 0.005)
	b.root.add_child(lbl)


## A lychgate: a steep tiled roof on oak posts, its gable to the lane, reaching out over the path;
## the churchyard behind it with its headstones and a yew, and the church beyond.
static func _lychgate(b: LevelBuilder, x: float, w: float) -> void:
	_church(b, x + w * 0.5)
	var m := TreeCover.model(b, "lychgate", Vector3(x, 0.0, 0.0))
	if m:
		m.scale.x = w / 4.0
		var lamp := m.get_node_or_null("Lamp") as Node3D
		if lamp:   # the model's lantern
			var om := OmniLight3D.new()
			om.light_color = Color(1.0, 0.76, 0.45)
			om.light_energy = 1.2
			om.omni_range = 4.0
			lamp.add_child(om)
		return
	var sts := {}
	var oak := b._mat("lych_oak", Color(0.26, 0.19, 0.13), 0.8)
	var tile := b._mat("lych_tile", Color(0.3, 0.17, 0.12), 0.7)
	var z0 := -1.8
	for ex in [x + 0.12, x + w - 0.12]:
		for pz in [z0 + 0.15, SHELTER_Z - 0.12]:
			RoadsideBuilder._add(sts, oak, ex - 0.1, ex + 0.1, 0.0, SHELTER_Y, pz - 0.1, pz + 0.1)
		RoadsideBuilder._add(sts, oak, ex - 0.11, ex + 0.11, SHELTER_Y, SHELTER_Y + 0.2, z0, SHELTER_Z + 0.1)   # wall plate
	# Tie beams across, and the gates (open, folded back against the posts behind the path).
	for pz in [z0 + 0.15, SHELTER_Z - 0.12]:
		RoadsideBuilder._add(sts, oak, x, x + w, SHELTER_Y + 0.05, SHELTER_Y + 0.22, pz - 0.08, pz + 0.08)
	RoadsideBuilder._add(sts, oak, x + 0.25, x + 0.33, 0.1, 1.2, z0 + 0.3, -0.4)
	RoadsideBuilder._add(sts, oak, x + w - 0.33, x + w - 0.25, 0.1, 1.2, z0 + 0.3, -0.4)
	RoadsideBuilder._add(sts, b._mat("lych_bench", Color(0.33, 0.25, 0.17), 0.8), x + 0.2, x + 0.55, 0.0, 0.45, z0 + 0.4, -0.2)
	RoadsideBuilder._commit(b, sts)
	# The roof: ridge along z, eaves either side over the posts, gable end to the lane.
	var ridge := SHELTER_Y + 0.2 + w * 0.55
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var za := z0 - 0.4
	var zb := SHELTER_Z + 0.35
	var e0 := Vector3(x - 0.3, SHELTER_Y + 0.12, 0)
	var e1 := Vector3(x + w + 0.3, SHELTER_Y + 0.12, 0)
	var rr := Vector3(x + w * 0.5, ridge, 0)
	_quad_up(st, Vector3(e0.x, e0.y, zb), Vector3(e0.x, e0.y, za), Vector3(rr.x, rr.y, za), Vector3(rr.x, rr.y, zb))
	_quad_up(st, Vector3(rr.x, rr.y, zb), Vector3(rr.x, rr.y, za), Vector3(e1.x, e1.y, za), Vector3(e1.x, e1.y, zb))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = tile
	b.root.add_child(mi)
	# Barge boards on the gable facing the lane.
	var sts2 := {}
	for k in 2:
		var ex: float = e0.x if k == 0 else e1.x
		var d := Vector2(rr.x - ex, rr.y - e0.y)
		var bar := b._box(Vector3(d.length() + 0.1, 0.22, 0.06), Vector3((ex + rr.x) * 0.5, (e0.y + rr.y) * 0.5 - 0.05, zb + 0.02), oak)
		bar.rotation.z = atan2(d.y, d.x)
	# The gable's timber infill, set back.
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	ViaductBuilder._tri(gst, Vector3(x, SHELTER_Y + 0.22, SHELTER_Z - 0.1), Vector3(x + w, SHELTER_Y + 0.22, SHELTER_Z - 0.1),
		Vector3(x + w * 0.5, ridge - 0.25, SHELTER_Z - 0.1), Vector3.BACK)
	var gi := MeshInstance3D.new()
	gi.mesh = gst.commit()
	gi.material_override = b._mat("lych_gable", Color(0.22, 0.16, 0.11), 0.85)
	b.root.add_child(gi)
	RoadsideBuilder._commit(b, sts2)


## The church behind a lychgate: a nave with a slate roof along the street and a west tower with
## battlements, in the haze beyond its churchyard.
static func _church(b: LevelBuilder, cx: float) -> void:
	var stone := b._mat("church_stone", Color(0.4, 0.38, 0.34), 0.85)
	var slate := b._mat("church_slate", Color(0.2, 0.21, 0.24), 0.6)
	var sts := {}
	var z1 := -13.0
	var z0 := -21.0
	var nx0 := cx - 5.0
	var nx1 := cx + 13.0
	RoadsideBuilder._add(sts, stone, nx0, nx1, 0.0, 6.5, z0, z1)
	# Lancet windows along the nave, some faintly lit.
	var glow := RoadsideBuilder._glow(b, "church_window", Color(0.95, 0.75, 0.45), 0.6)
	var dark := b._mat("church_glass", Color(0.06, 0.07, 0.08), 0.3)
	var wx := nx0 + 3.5
	var k := 0
	while wx < nx1 - 1.0:
		RoadsideBuilder._add(sts, glow if k % 2 == 0 else dark, wx - 0.35, wx + 0.35, 2.0, 4.6, z1, z1 + 0.05)
		wx += 3.2
		k += 1
	# Tower at the west end.
	var tx0 := nx0 - 4.6
	RoadsideBuilder._add(sts, stone, tx0, nx0 + 0.2, 0.0, 17.0, z0 + 1.6, z1 + 0.6)
	for i in 4:   # battlements
		var bx := tx0 + 0.1 + i * 1.3
		RoadsideBuilder._add(sts, stone, bx, bx + 0.7, 17.0, 17.7, z0 + 1.6, z1 + 0.6)
	RoadsideBuilder._add(sts, dark, tx0 + 1.8, tx0 + 2.8, 12.0, 14.0, z1 + 0.6, z1 + 0.65)   # belfry louvres
	RoadsideBuilder._add(sts, glow, tx0 + 1.9, tx0 + 2.7, 3.0, 5.5, z1 + 0.6, z1 + 0.65)
	RoadsideBuilder._commit(b, sts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zm := (z0 + z1) * 0.5
	_quad_up(st, Vector3(nx0, 6.4, z1 + 0.4), Vector3(nx1, 6.4, z1 + 0.4), Vector3(nx1, 10.5, zm), Vector3(nx0, 10.5, zm))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = slate
	b.root.add_child(mi)
	# The churchyard: headstones leaning in the grass, and a dark yew.
	var r := RandomNumberGenerator.new()
	r.seed = b._lot_hash(cx, "churchyard")
	var sts2 := {}
	var grave := b._mat("headstone", Color(0.5, 0.49, 0.45), 0.8)
	for i in 9:
		var gx := cx + r.randf_range(-9.0, 12.0)
		var gz := r.randf_range(-11.0, -3.0)
		var hgt := r.randf_range(0.6, 1.1)
		RoadsideBuilder._add(sts2, grave, gx - 0.3, gx + 0.3, 0.0, hgt, gz - 0.06, gz + 0.06)
	RoadsideBuilder._commit(b, sts2)
	var yx := cx + r.randf_range(4.0, 8.0)
	var o := Vector3(yx, 0.0, -7.0)
	var yst := SurfaceTool.new()
	yst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var rad := r.randf_range(1.0, 1.6)
		var py := 1.4 + i * 0.55
		TreeCover.puff(yst, Vector3(r.randf_range(-1.0, 1.0), py, r.randf_range(-1.0, 1.0)), rad * (1.0 - i * 0.06), 0.8, Vector3(0, py, 0), r.randi(), 10, 6)
	TreeCover.foliage_node(b, yst, o, yx - 2.0, yx + 2.0, Color(0.03, 0.06, 0.04), Color(0.1, 0.16, 0.08), 0.05, 1.0, 5.0)


## A Dutch barn: steel stanchions front and back, a curved roof of corrugated iron on them, open on
## every side, and the hay stacked inside.
static func _barn(b: LevelBuilder, x: float, w: float) -> void:
	var m := TreeCover.model(b, "dutch_barn", Vector3(x, 0.0, 0.0))
	if m:
		m.scale.x = w / 8.0
	else:
		var sts := {}
		var steel := b._mat("barn_steel", Color(0.3, 0.33, 0.28), 0.55, 0.5)
		var rust := b._mat("barn_rust", Color(0.36, 0.2, 0.12), 0.6, 0.4)
		var clad := b._mat("barn_clad", Color(0.27, 0.31, 0.25), 0.55, 0.45)
		var n := maxi(1, roundi(w / 4.5))
		for i in n + 1:
			var px := clampf(x + w * i / n, x + 0.08, x + w - 0.08)
			RoadsideBuilder._add(sts, steel, px - 0.07, px + 0.07, 0.0, BARN_Y, BARN_Z - 0.16, BARN_Z - 0.02)
			RoadsideBuilder._add(sts, steel, px - 0.07, px + 0.07, 0.0, BARN_Y, BARN_BACK, BARN_BACK + 0.14)
		RoadsideBuilder._add(sts, rust, x, x + w, BARN_Y, BARN_Y + 0.22, BARN_Z - 0.18, BARN_Z)
		RoadsideBuilder._add(sts, rust, x, x + w, BARN_Y, BARN_Y + 0.22, BARN_BACK, BARN_BACK + 0.18)
		# Corrugated sheets on the back and high on the ends, the front left open.
		var cx := x
		while cx < x + w - 0.01:
			RoadsideBuilder._add(sts, clad if int((cx - x) / 0.15) % 2 == 0 else rust, cx, minf(cx + 0.15, x + w), 1.6, BARN_Y,
				BARN_BACK - 0.05, BARN_BACK + 0.02 if int((cx - x) / 0.15) % 2 == 0 else BARN_BACK - 0.02)
			cx += 0.15
		for ex in [x + 0.02, x + w - 0.06]:
			RoadsideBuilder._add(sts, clad, ex, ex + 0.04, 2.4, BARN_Y, BARN_BACK, BARN_Z - 2.2)
		RoadsideBuilder._commit(b, sts)
		# The roof: a barrel vault from the front eave over to the back one, corrugated along it.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rise := 2.0
		var segs := 12
		var cz := (BARN_Z + BARN_BACK) * 0.5
		var half := (BARN_Z - BARN_BACK) * 0.5 + 0.25
		var nx := int((w + 0.4) / 0.12)
		for j in segs:
			var t0 := float(j) / segs
			var t1 := float(j + 1) / segs
			var z0 := cz + half * cos(PI * t0)
			var z1 := cz + half * cos(PI * t1)
			var y0 := BARN_Y + 0.2 + rise * sin(PI * t0)
			var y1 := BARN_Y + 0.2 + rise * sin(PI * t1)
			for i in nx:
				var xa := x - 0.2 + (w + 0.4) * i / nx
				var xb := x - 0.2 + (w + 0.4) * (i + 1) / nx
				var ca := 0.03 * sin(i * PI)
				var cb := 0.03 * sin((i + 1) * PI)
				_quad_up(st, Vector3(xa, y0 + ca, z0), Vector3(xb, y0 + cb, z0), Vector3(xb, y1 + cb, z1), Vector3(xa, y1 + ca, z1))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = b._mat("barn_roof", Color(0.36, 0.25, 0.17), 0.5, 0.45)
		b.root.add_child(mi)
	# Hay stacked inside, well back from the path, and the farmyard's mud.
	var hay := _hay_mat(b)
	var r := RandomNumberGenerator.new()
	r.seed = b._lot_hash(x, "hay")
	var sts2 := {}
	var bx := x + 0.3
	while bx < x + w - 1.3:
		var tiers := r.randi_range(2, 4)
		for t in tiers:
			var j := r.randf_range(-0.06, 0.06)
			RoadsideBuilder._add(sts2, hay, bx + j, bx + 1.12 + j, t * 0.86, t * 0.86 + 0.84, BARN_BACK + 0.4, -1.2 - t * 0.5 + j)
		bx += 1.2
	RoadsideBuilder._add(sts2, b._mat("yard_mud", Color(0.15, 0.12, 0.09), 0.35), x - 0.5, x + w + 0.5, -0.02, 0.012, BARN_BACK - 2.0, -0.6)
	RoadsideBuilder._commit(b, sts2)


## Straw: the leaves' shader in straw colours, fine-grained and still.
static func _hay_mat(b: LevelBuilder) -> Material:
	if not b._mats.has("_hay"):
		var m := TreeCover.foliage_material(b, Color(0.48, 0.38, 0.19), Color(0.64, 0.53, 0.29), 0.0, 0.0, 1.0)
		m.set_shader_parameter("leaf_scale", 14.0)
		m.set_shader_parameter("flutter", 0.0)
		m.set_shader_parameter("wet", 0.1)
		b._mats["_hay"] = m
	return b._mats["_hay"]


## A porch over a door, from a to c: a gabled hood on two posts when it is narrow, a lean-to
## verandah on posts when it is wide.
static func _porch(b: LevelBuilder, a: float, c: float) -> void:
	var sts := {}
	var post := b._mat("porch_post", Color(0.85, 0.83, 0.78), 0.6)
	var roof := b._mat("porch_roof", Color(0.24, 0.2, 0.19), 0.55)
	var n := maxi(1, roundi((c - a) / 3.0))
	for i in n + 1:
		var px := clampf(a + (c - a) * i / n, a + 0.07, c - 0.07)
		RoadsideBuilder._add(sts, post, px - 0.06, px + 0.06, 0.0, PORCH_Y, PORCH_Z - 0.14, PORCH_Z - 0.02)
	RoadsideBuilder._add(sts, post, a, c, PORCH_Y, PORCH_Y + 0.12, PORCH_Z - 0.16, PORCH_Z)
	RoadsideBuilder._commit(b, sts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if c - a <= 3.5:
		var mid := (a + c) * 0.5
		var ridge := PORCH_Y + 0.25 + (c - a) * 0.4
		_quad_up(st, Vector3(a - 0.15, PORCH_Y + 0.14, PORCH_Z + 0.2), Vector3(a - 0.15, PORCH_Y + 0.14, -0.05),
			Vector3(mid, ridge, -0.05), Vector3(mid, ridge, PORCH_Z + 0.2))
		_quad_up(st, Vector3(mid, ridge, PORCH_Z + 0.2), Vector3(mid, ridge, -0.05), Vector3(c + 0.15, PORCH_Y + 0.14, -0.05),
			Vector3(c + 0.15, PORCH_Y + 0.14, PORCH_Z + 0.2))
		var gst := SurfaceTool.new()
		gst.begin(Mesh.PRIMITIVE_TRIANGLES)
		ViaductBuilder._tri(gst, Vector3(a, PORCH_Y + 0.14, PORCH_Z + 0.05), Vector3(c, PORCH_Y + 0.14, PORCH_Z + 0.05),
			Vector3(mid, ridge - 0.1, PORCH_Z + 0.05), Vector3.BACK)
		var gi := MeshInstance3D.new()
		gi.mesh = gst.commit()
		gi.material_override = b._mat("porch_gable", Color(0.3, 0.25, 0.2), 0.8)
		b.root.add_child(gi)
	else:
		_quad_up(st, Vector3(a - 0.1, PORCH_Y + 0.85, -0.05), Vector3(c + 0.1, PORCH_Y + 0.85, -0.05),
			Vector3(c + 0.1, PORCH_Y + 0.14, PORCH_Z + 0.2), Vector3(a - 0.1, PORCH_Y + 0.14, PORCH_Z + 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = roof
	b.root.add_child(mi)


# --- buildings -------------------------------------------------------------------------------------

const WALLS := [Color(0.8, 0.78, 0.71), Color(0.47, 0.43, 0.38), Color(0.74, 0.68, 0.58)]   # whitewash, stone, cream
const DOORS := [Color(0.12, 0.22, 0.15), Color(0.36, 0.08, 0.07), Color(0.1, 0.14, 0.25)]


## A cottage on the lane: whitewash or stone, a steep roof of slate or thatch with chimneys at the
## ends, small-paned windows (one lit), and its door; `floors` 0 is a single storey.
static func _cottage(b: LevelBuilder, x: float, w: float, lot_d: Dictionary) -> void:
	var hh := b._lot_hash(x, "cottage")
	var eaves := 2.95 if int(lot_d.get("floors", 1)) <= 0 else 3.7
	var wall := b._mat("cottage_wall_%d" % (hh % 3), WALLS[hh % 3], 0.9)
	var thatch := (hh / 3) % 2 == 0
	_house(b, x, w, eaves, wall, thatch, door_x(lot_d), DOORS[(hh / 7) % 3], hh)
	# A climber up one corner of the front.
	var cx := x + (0.45 if hh % 2 == 0 else w - 0.45)
	var o := Vector3(cx, 0.0, 0.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = hh
	var y := 0.3
	while y < eaves - 0.3:
		for k in 2:
			TreeCover.puff(st, Vector3(r.randf_range(-0.35, 0.35), y, r.randf_range(0.0, 0.12)), r.randf_range(0.2, 0.32), 0.85,
				Vector3(0, y, -0.5), r.randi(), 7, 4, 0.6)
		y += r.randf_range(0.2, 0.3)
	TreeCover.foliage_node(b, st, o, cx - 0.5, cx + 0.5, HEDGE_DARK, Color(0.22, 0.3, 0.1), 0.01, 0.0, 3.0).material_override.set_shader_parameter("leaf_scale", 4.0)


## The pub at the end of the lane: two storeys of whitewash under slate, its name painted on the
## board over the ground floor and on a sign hanging from a bracket, windows lit, a lantern by the
## door, which is INN_DOOR into the lot (the level ends there).
static func _pub(b: LevelBuilder, x: float, w: float, lot_d: Dictionary) -> void:
	var wall := b._mat("pub_wall", Color(0.84, 0.82, 0.76), 0.85)
	_house(b, x, w, 6.0, wall, false, INN_DOOR, Color(0.1, 0.12, 0.1), 3, true)
	b.inn_door_x = x + INN_DOOR
	var text := String(lot_d.get("sign", "THE PLOUGH"))
	var sts := {}
	var board := b._mat("pub_board", Color(0.08, 0.13, 0.1), 0.6)
	var gold := Color(0.95, 0.8, 0.45)
	RoadsideBuilder._add(sts, board, x + 0.4, x + w - 0.4, 4.7, 5.25, 0.0, 0.08)
	# The hanging sign on its bracket, out over the verge at the far end.
	var sx := x + w - 1.2
	RoadsideBuilder._add(sts, board, sx - 0.04, sx + 0.04, 4.0, 4.08, 0.0, 1.3)
	RoadsideBuilder._add(sts, board, sx - 0.45, sx + 0.45, 2.9, 3.9, 1.05, 1.11)
	RoadsideBuilder._commit(b, sts)
	for p in [[Vector3(x + w * 0.5, 4.97, 0.1), text, 64], [Vector3(sx, 3.4, 1.12), text.replace("THE ", "THE\n"), 30]]:
		var lbl := Label3D.new()
		lbl.text = p[1]
		lbl.font_size = p[2]
		lbl.pixel_size = 0.004
		if b.sign_font:
			lbl.font = b.sign_font
		lbl.modulate = gold
		lbl.outline_size = 0
		lbl.double_sided = false
		lbl.position = p[0]
		if p[2] == 64:
			var max_w := (w - 1.2) / lbl.pixel_size
			lbl.font_size = int(clampf(max_w / maxf(1.0, text.length() * 0.62), 30.0, 90.0))
		b.root.add_child(lbl)
	# A lantern by the door.
	var lamp := b._neon_mat(Color(1.0, 0.78, 0.45), 3.0)
	var lx := x + INN_DOOR + 0.95
	b._box(Vector3(0.2, 0.3, 0.2), Vector3(lx, 2.45, 0.25), lamp)
	var om := OmniLight3D.new()
	om.light_color = Color(1.0, 0.75, 0.45)
	om.light_energy = 1.4
	om.omni_range = 4.5
	om.position = Vector3(lx, 2.3, 0.7)
	b.root.add_child(om)


## Dormer windows in the front of a cottage's roof, over the ground-floor windows: a little gabled
## box each, glazed to the street.
static func _dormers(b: LevelBuilder, slots: Array, eaves: float, ridge: float, zr: float, frame: Material, glass: Material,
		lit: Material, thatch: bool, r: RandomNumberGenerator) -> void:
	var sts := {}
	var slope := (ridge - eaves + 0.15) / (0.3 - zr)     # the roof's rise per metre back
	var y0 := eaves + 0.15
	var zf := -0.25
	var top := y0 + 0.95
	var zb := 0.3 - (top + 0.3 - eaves + 0.15) / slope
	var cheek := b._mat("thatch", Color(0.36, 0.28, 0.17), 0.95) if thatch else frame
	for cx: float in slots:
		var on := r.randf() < 0.3
		RoadsideBuilder._add(sts, cheek, cx - 0.6, cx + 0.6, y0 - 0.2, top + 0.12, zb, zf)
		RoadsideBuilder._add(sts, frame, cx - 0.48, cx + 0.48, y0, top, zf, zf + 0.04)
		RoadsideBuilder._add(sts, lit if on else glass, cx - 0.4, cx + 0.4, y0 + 0.06, top - 0.06, zf, zf + 0.05)
		RoadsideBuilder._add(sts, frame, cx - 0.02, cx + 0.02, y0 + 0.06, top - 0.06, zf, zf + 0.07)
		if on:
			b.lit_windows.append([Vector3(cx, y0 + 0.5, -1.0), Color(1.0, 0.7, 0.4)])
	RoadsideBuilder._commit(b, sts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cx: float in slots:
		var peak := top + 0.55
		_quad_up(st, Vector3(cx - 0.72, top + 0.05, zf + 0.25), Vector3(cx - 0.72, top + 0.05, zb), Vector3(cx, peak, zb), Vector3(cx, peak, zf + 0.25))
		_quad_up(st, Vector3(cx, peak, zf + 0.25), Vector3(cx, peak, zb), Vector3(cx + 0.72, top + 0.05, zb), Vector3(cx + 0.72, top + 0.05, zf + 0.25))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = b._mat("thatch", Color(0.36, 0.28, 0.17), 0.95) if thatch else b._mat("roof_slate", Color(0.17, 0.18, 0.21), 0.5)
	b.root.add_child(mi)


## A house front at the lot line: walls, a pitched roof along the street (slate, or thatch with a
## thick rounded eave), chimneys at both ends, a door at local `door` and windows either side of it,
## up to two rows of them.
static func _house(b: LevelBuilder, x: float, w: float, eaves: float, wall: Material, thatch: bool, door: float,
		door_col: Color, seed: int, pub := false) -> void:
	var sts := {}
	var depth := 6.5
	b._box(Vector3(w - 0.04, eaves, depth), Vector3(x + w * 0.5, eaves * 0.5, -depth * 0.5), wall)
	var frame := b._mat("window_frame", Color(0.88, 0.87, 0.82), 0.6)
	var glass := b._mat("cottage_glass", Color(0.07, 0.085, 0.1), 0.1, 0.3)
	var lit := RoadsideBuilder._glow(b, "cottage_lit", Color(1.0, 0.72, 0.4), 1.1)
	var sill := b._mat("cottage_sill", Color(0.55, 0.53, 0.48), 0.7)
	# Plinth and door.
	RoadsideBuilder._add(sts, b._mat("cottage_plinth", Color(0.25, 0.24, 0.22), 0.8), x, x + w, 0.0, 0.35, -0.02, 0.04)
	var dx := x + door
	RoadsideBuilder._add(sts, frame, dx - 0.55, dx + 0.55, 0.0, 2.25, 0.0, 0.05)
	RoadsideBuilder._add(sts, b._mat("door_%s" % door_col.to_html(), door_col, 0.5), dx - 0.45, dx + 0.45, 0.02, 2.15, 0.0, 0.08)
	RoadsideBuilder._add(sts, b._mat("brass", Color(0.7, 0.55, 0.25), 0.3, 0.8), dx + 0.3, dx + 0.36, 1.0, 1.06, 0.08, 0.12)
	# Windows: the ground row either side of the door, an upper row where there is a storey above.
	# Upper windows: a row in the wall of a two-storey house, dormers in the roof of a cottage.
	var rows := [0.95, 3.5] if pub else [0.95]
	var dormers := not pub and eaves > 3.2
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var slots: Array = []
	var sx := x + 0.9
	while sx < x + w - 0.8:
		if absf(sx + 0.55 - dx) > 1.25:
			slots.append(sx + 0.55)
			sx += 1.8
		else:
			sx += 0.3
	for wy: float in rows:
		for cx: float in slots:
			var on: bool = (wy < 2.0 and (pub or r.randf() < 0.5)) or r.randf() < 0.15
			var hw := 0.55 if pub else 0.45
			var top := wy + (1.2 if pub else 1.0) if wy < 2.0 else wy + 1.0
			RoadsideBuilder._add(sts, frame, cx - hw - 0.06, cx + hw + 0.06, wy - 0.06, top + 0.06, 0.0, 0.04)
			RoadsideBuilder._add(sts, lit if on else glass, cx - hw, cx + hw, wy, top, 0.0, 0.05)
			RoadsideBuilder._add(sts, frame, cx - 0.025, cx + 0.025, wy, top, 0.0, 0.07)
			for k in 2:
				var gy := lerpf(wy, top, (k + 1) / 3.0)
				RoadsideBuilder._add(sts, frame, cx - hw, cx + hw, gy - 0.02, gy + 0.02, 0.0, 0.07)
			RoadsideBuilder._add(sts, sill, cx - hw - 0.12, cx + hw + 0.12, wy - 0.12, wy - 0.04, 0.0, 0.14)
			if on:
				b.lit_windows.append([Vector3(cx, wy + 0.6, -0.8), Color(1.0, 0.7, 0.4)])
	RoadsideBuilder._commit(b, sts)
	# Roof along the street, its ridge set back, gable ends at the lot edges.
	var ridge := eaves + (3.6 if thatch else 2.8)
	if dormers:
		_dormers(b, slots, eaves, ridge, -depth * 0.5, frame, glass, lit, thatch, r)
	var zf := 0.35 if thatch else 0.25
	var zr := -depth * 0.5
	var roof_mat := b._mat("thatch", Color(0.36, 0.28, 0.17), 0.95) if thatch else b._mat("roof_slate", Color(0.17, 0.18, 0.21), 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad_up(st, Vector3(x - 0.1, eaves - 0.15, zf), Vector3(x + w + 0.1, eaves - 0.15, zf), Vector3(x + w + 0.1, ridge, zr),
		Vector3(x - 0.1, ridge, zr))
	_quad_up(st, Vector3(x - 0.1, ridge, zr), Vector3(x + w + 0.1, ridge, zr), Vector3(x + w + 0.1, eaves - 0.15, -depth - 0.25),
		Vector3(x - 0.1, eaves - 0.15, -depth - 0.25))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = roof_mat
	b.root.add_child(mi)
	if thatch:   # the thick rounded eave of a thatch
		var sts3 := {}
		ModernBuilder.cyl(sts3, roof_mat, Vector3(x - 0.1, eaves - 0.05, zf - 0.1), Vector3(x + w + 0.1, eaves - 0.05, zf - 0.1), 0.22, 0.22, 10)
		RoadsideBuilder._commit(b, sts3)
	# Gable ends filled in with the wall, and a chimney on each.
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gx in [x + 0.02, x + w - 0.02]:
		ViaductBuilder._tri(gst, Vector3(gx, eaves, 0.0), Vector3(gx, eaves, -depth), Vector3(gx, ridge - 0.1, zr),
			Vector3.LEFT if gx < x + w * 0.5 else Vector3.RIGHT)
	var gi := MeshInstance3D.new()
	gi.mesh = gst.commit()
	gi.material_override = wall
	b.root.add_child(gi)
	var sts4 := {}
	var brick := b._mat("chimney", Color(0.42, 0.25, 0.18), 0.85)
	for cx in [x + 0.55, x + w - 0.55]:
		RoadsideBuilder._add(sts4, brick, cx - 0.35, cx + 0.35, ridge - 1.0, ridge + 1.0, zr - 0.4, zr + 0.4)
		RoadsideBuilder._add(sts4, b._mat("chimney_pot", Color(0.45, 0.28, 0.2), 0.8), cx - 0.12, cx + 0.12, ridge + 1.0, ridge + 1.35, zr - 0.12, zr + 0.12)
	RoadsideBuilder._commit(b, sts4)


# --- the ground, the lane, crossings and the hills -------------------------------------------------

## The verge (grass with the worn path, cut at side lanes), the lane in front, the fields behind,
## and hedges running on past both ends of the street.
static func ground(b: LevelBuilder) -> void:
	var L: float = b.data["length"]
	var x0 := -40.0
	var x1 := L + 40.0
	var verge := _ground_mat(b, "verge", 0)
	var cuts: Array = []
	for c in b.data.get("crossings", []):
		cuts.append([float(c["x"]), float(c["x"]) + float(c["w"])])
	var sx := x0
	for c in cuts + [[x1, x1]]:
		var ex: float = c[0]
		if ex > sx:
			b._box(Vector3(ex - sx, 0.3, LevelBuilder.SIDEWALK_W - HEDGE_Z0 + 0.5), Vector3((sx + ex) * 0.5, -0.15, (LevelBuilder.SIDEWALK_W + HEDGE_Z0 - 0.5) * 0.5), verge)
		sx = c[1]
	var lane := _ground_mat(b, "lane", 2)
	b._box(Vector3(x1 - x0, 0.2, LANE_Z1 - LevelBuilder.SIDEWALK_W + 0.2), Vector3((x0 + x1) * 0.5, LevelBuilder.ROAD_Y - 0.1, (LANE_Z1 + LevelBuilder.SIDEWALK_W) * 0.5), lane)
	b._box(Vector3(x1 - x0, 0.2, 14.0), Vector3((x0 + x1) * 0.5, -0.12, LANE_Z1 + 7.0), verge)
	for c in cuts:
		b._box(Vector3(c[1] - c[0], 0.2, 60.0), Vector3((c[0] + c[1]) * 0.5, LevelBuilder.ROAD_Y - 0.1, LevelBuilder.SIDEWALK_W - 30.0), lane)
	# The fields behind, out to the hills.
	var fields := _ground_mat(b, "fields", 1)
	b._box(Vector3(x1 - x0 + 400.0, 0.2, 260.0), Vector3((x0 + x1) * 0.5, -0.14, HEDGE_Z0 - 130.0), fields)
	hedge(b, x0, 0.0)
	hedge(b, L, x1)


static func _ground_mat(b: LevelBuilder, key: String, mode: int) -> Material:
	var k := "country_ground_" + key
	if b._mats.has(k):
		return b._mats[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://src/fx/country_ground.gdshader")
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("path_z0", PATH_Z0)
	m.set_shader_parameter("path_z1", PATH_Z1)
	b._mats[k] = m
	return m


## A side lane: tarmac running back between hedges, a fingerpost at the far corner.
static func crossing(b: LevelBuilder, c: Dictionary) -> void:
	var x0 := float(c["x"])
	var x1 := x0 + float(c["w"])
	for side in [[x0 + 0.6, 1.0], [x1 - 0.6, -1.0]]:
		_hedge_back(b, side[0], HEDGE_Z0 - 0.4, -40.0)
	prop(b, "signpost", x1 - 0.8, {})


## A hedge running back from the street at x, from z0 to z1 (z1 < z0), for the sides of a side lane.
static func _hedge_back(b: LevelBuilder, x: float, z0: float, z1: float) -> void:
	var o := Vector3(x, 0.0, (z0 + z1) * 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = b._lot_hash(x, "hedge_back")
	var pz := z0
	while pz > z1:
		var rad := r.randf_range(0.6, 0.85)
		TreeCover.puff(st, Vector3(x + r.randf_range(-0.15, 0.15), rad * 0.9 + r.randf_range(0.0, 0.5), pz) - o, rad, 0.9, Vector3(x, -1.0, pz) - o, r.randi(), 8, 5)
		pz -= r.randf_range(0.6, 0.9)
	TreeCover.foliage_node(b, st, o, x - 0.5, x + 0.5, HEDGE_DARK, HEDGE_LIGHT, 0.02, 0.2, 1.6)


## Behind the street: hedgerows across the fields with a tree here and there, and two ridges of
## hills, the far one pale in the rain.
static func backdrop(b: LevelBuilder) -> void:
	var L: float = b.data["length"]
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(b.data.get("id", "country")) + ":backdrop")
	for row in [[-34.0, 1.1, 0.9], [-78.0, 1.5, 1.2], [-130.0, 2.0, 1.6]]:
		var z: float = row[0]
		var step: float = row[1]
		var rad: float = row[2]
		var x := -150.0
		while x < L + 150.0:
			var seg := r.randf_range(40.0, 90.0)
			var o := Vector3(x + seg * 0.5, 0.0, z)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var px := x
			while px < x + seg:
				TreeCover.puff(st, Vector3(px, rad * 0.85, z + r.randf_range(-0.5, 0.5)) - o, rad * r.randf_range(0.85, 1.15), 0.85,
					Vector3(px, -1.0, z) - o, r.randi(), 7, 4)
				if r.randf() < 0.03:   # a hedgerow tree
					var tr := rad * r.randf_range(2.4, 3.4)
					for k in 4:
						TreeCover.puff(st, Vector3(px + r.randf_range(-tr, tr) * 0.5, tr * 1.6 + r.randf_range(-0.4, 1.2) * tr * 0.5, z + r.randf_range(-1.0, 1.0)) - o,
							tr * r.randf_range(0.6, 0.85), 0.85, Vector3(px, tr, z) - o, r.randi(), 8, 5)
				px += step
			TreeCover.foliage_node(b, st, o, x, x + seg, HEDGE_DARK.lerp(HEDGE_LIGHT, 0.4), HEDGE_LIGHT, 0.0, 0.0, 1.0, false)
			x += seg + r.randf_range(4.0, 14.0)
	_ridge(b, -190.0, -150.0, L, 14.0, 30.0, r, "hills_near", Color(0.18, 0.24, 0.13))
	_ridge(b, -340.0, -290.0, L, 30.0, 60.0, r, "hills_far", Color(0.3, 0.35, 0.33))


## A ridge of hills from z_front (ground level) back to its crest at z_top, rising and falling along
## the street between lo and hi metres.
static func _ridge(b: LevelBuilder, z_top: float, z_front: float, L: float, lo: float, hi: float, r: RandomNumberGenerator,
		key: String, col: Color) -> void:
	var ph := [r.randf() * TAU, r.randf() * TAU, r.randf() * TAU]
	var hgt := func(x: float) -> float:
		var n := 0.5 + 0.28 * sin(x / 95.0 + ph[0]) + 0.15 * sin(x / 41.0 + ph[1]) + 0.07 * sin(x / 17.0 + ph[2])
		return lerpf(lo, hi, clampf(n, 0.0, 1.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs := [z_front, lerpf(z_front, z_top, 0.35), lerpf(z_front, z_top, 0.7), z_top, z_top - 30.0]
	var prof := [0.0, 0.55, 0.88, 1.0, 0.85]
	var x := -260.0
	var step := 8.0
	while x < L + 260.0:
		var ha: float = hgt.call(x)
		var hb: float = hgt.call(x + step)
		for j in zs.size() - 1:
			var p0 := Vector3(x, ha * prof[j] - 0.5, zs[j])
			var p1 := Vector3(x + step, hb * prof[j] - 0.5, zs[j])
			var p2 := Vector3(x + step, hb * prof[j + 1] - 0.5, zs[j + 1])
			var p3 := Vector3(x, ha * prof[j + 1] - 0.5, zs[j + 1])
			_quad_up(st, p0, p1, p2, p3)
		x += step
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	if key == "hills_near":
		var m: ShaderMaterial = _ground_mat(b, "hills", 1).duplicate()
		m.set_shader_parameter("cell", 70.0)
		mi.material_override = m
	else:
		mi.material_override = b._mat(key, col, 0.95)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.root.add_child(mi)


## Telegraph poles along the hedge line every POLE_GAP or so, clear of side lanes, buildings and
## trees, and of any lamp post the street places, with their wires sagging between them.
static func poles(b: LevelBuilder) -> void:
	var L: float = b.data["length"]
	var blocked: Array = []
	for c in b.data.get("crossings", []):
		blocked.append([float(c["x"]) - 1.5, float(c["x"]) + float(c["w"]) + 1.5])
	for l in b.data.get("lots", []):
		if String(l.get("style", "")) not in ["hedge", "field_gate", "stone_wall", "vacant"]:
			blocked.append([float(l["x"]) - 0.5, float(l["x"]) + float(l["w"]) + 0.5])
	for p in b.data.get("props", []):
		if p["id"] in ["lamp_post", "telegraph_pole"]:
			blocked.append([float(p["x"]) - 8.0, float(p["x"]) + 8.0])
	var xs: Array = []
	var x := 6.0
	while x < L + 30.0:
		var px := x
		var tries := 0
		while tries < 40 and blocked.any(func(s: Array) -> bool: return px > s[0] and px < s[1]):
			px += 1.0
			tries += 1
		if tries < 40:
			xs.append(px)
		x = px + POLE_GAP
	var sts := {}
	var wire := b._mat("wire", Color(0.05, 0.05, 0.05), 0.5)
	# Where the wires leave each pole: the model's insulators (docs/CONTRACTS.md §10), else the stand-in's.
	var model := TreeCover.model_scene(b, "telegraph_pole") != null
	var ends: Array = [Vector3(0.145, 7.79, -0.36), Vector3(0.145, 7.79, 0.36), Vector3(0.145, 7.24, -0.26),
		Vector3(0.145, 7.24, 0.26)] if model else [Vector3(0.0, WIRE_Y, -0.32), Vector3(0.0, WIRE_Y, 0.32)]
	for i in xs.size():
		_pole(b, xs[i])
		if i > 0 and xs[i] - xs[i - 1] < POLE_GAP * 1.6:
			for e: Vector3 in ends:
				var a := Vector3(xs[i - 1], 0.0, POLE_Z) + e
				var c := Vector3(xs[i], 0.0, POLE_Z) + e
				var n := 10
				var prev := a
				for k in range(1, n + 1):
					var t := float(k) / n
					var p := a.lerp(c, t) + Vector3(0, -0.9 * 4.0 * t * (1.0 - t), 0)
					ModernBuilder.cyl(sts, wire, prev, p, 0.012, 0.012, 4)
					prev = p
	RoadsideBuilder._commit(b, sts)


static func _pole(b: LevelBuilder, x: float) -> void:
	if TreeCover.model(b, "telegraph_pole", Vector3(x, 0.0, POLE_Z)):
		return
	var sts := {}
	var wood := b._mat("pole_wood", Color(0.24, 0.2, 0.16), 0.85)
	ModernBuilder.cyl(sts, wood, Vector3(x, 0.0, POLE_Z), Vector3(x, 8.0, POLE_Z), 0.14, 0.11, 10)
	RoadsideBuilder._add(sts, wood, x - 0.06, x + 0.06, WIRE_Y - 0.18, WIRE_Y - 0.06, POLE_Z - 0.6, POLE_Z + 0.6)
	var cer := b._mat("insulator", Color(0.75, 0.75, 0.72), 0.3)
	for dz in [-0.32, 0.32]:
		ModernBuilder.cyl(sts, cer, Vector3(x, WIRE_Y - 0.06, POLE_Z + dz), Vector3(x, WIRE_Y + 0.02, POLE_Z + dz), 0.035, 0.03, 8)
	RoadsideBuilder._commit(b, sts)


# --- props -----------------------------------------------------------------------------------------

const PROPS := ["hay_bales", "milk_churn_stand", "milestone", "signpost", "telegraph_pole"]


## A country prop at x (a model if there is one): returns false if `id` isn't one.
static func prop(b: LevelBuilder, id: String, x: float, p: Dictionary) -> bool:
	if id not in PROPS:
		return false
	var z := {"hay_bales": -8.0, "milk_churn_stand": 0.15, "milestone": 0.3, "signpost": -0.5, "telegraph_pole": POLE_Z}[id] as float
	z = float(p.get("z", z))
	if id == "telegraph_pole":
		_pole(b, x)
		return true
	if id == "hay_bales":
		_bales(b, x, z)
		return true
	if TreeCover.model(b, id, Vector3(x, 0.0, z)):
		return true
	var sts := {}
	match id:
		"milk_churn_stand":
			var timber := b._mat("churn_stand", Color(0.3, 0.24, 0.17), 0.85)
			RoadsideBuilder._add(sts, timber, x - 0.8, x + 0.8, 0.95, 1.05, z - 0.4, z + 0.4)
			for lx in [x - 0.7, x + 0.7]:
				RoadsideBuilder._add(sts, timber, lx - 0.06, lx + 0.06, 0.0, 0.95, z - 0.3, z + 0.3)
			var churn := b._mat("churn", Color(0.62, 0.63, 0.62), 0.35, 0.7)
			for k in 3:
				var cx := x - 0.5 + k * 0.5
				ModernBuilder.cyl(sts, churn, Vector3(cx, 1.05, z), Vector3(cx, 1.6, z), 0.18, 0.18, 12)
				ModernBuilder.cyl(sts, churn, Vector3(cx, 1.6, z), Vector3(cx, 1.75, z), 0.18, 0.08, 12)
		"milestone":
			var stone := b._mat("milestone", Color(0.62, 0.6, 0.55), 0.8)
			RoadsideBuilder._add(sts, stone, x - 0.22, x + 0.22, 0.0, 0.55, z - 0.12, z + 0.12)
			ModernBuilder.cyl(sts, stone, Vector3(x, 0.55, z - 0.12), Vector3(x, 0.55, z + 0.12), 0.22, 0.22, 12)
		"signpost":
			var white := b._mat("fingerpost", Color(0.85, 0.84, 0.8), 0.6)
			ModernBuilder.cyl(sts, white, Vector3(x, 0.0, z), Vector3(x, 2.6, z), 0.06, 0.06, 8)
			RoadsideBuilder._add(sts, white, x - 0.05, x + 0.95, 2.2, 2.38, z - 0.03, z + 0.03)
			RoadsideBuilder._add(sts, white, x - 0.9, x + 0.05, 1.95, 2.13, z - 0.03, z + 0.03)
			RoadsideBuilder._add(sts, b._mat("fingerpost_cap", Color(0.6, 0.12, 0.1), 0.5), x - 0.08, x + 0.08, 2.6, 2.72, z - 0.08, z + 0.08)
	RoadsideBuilder._commit(b, sts)
	return true


## A quad whose normal faces up (roofs, the hills), split into two triangles.
static func _quad_up(st: SurfaceTool, a: Vector3, b2: Vector3, c: Vector3, d: Vector3) -> void:
	var nrm := (b2 - a).cross(d - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	ViaductBuilder._tri(st, a, b2, c, nrm)
	ViaductBuilder._tri(st, a, c, d, nrm)


# --- the rain's cover map --------------------------------------------------------------------------

## On a country street the ground behind the lot line is field, not the inside of a building: rain
## falls there and lands on the hedge and wall tops; buildings still hide it. Called by
## LevelBuilder.cover_map before the lots' cover is painted.
static func cover_map_ground(b: LevelBuilder, img: Image, x0: float) -> void:
	var L: float = b.data["length"]
	var z0 := LevelBuilder.COVER_Z0
	b._solid_fill(img, x0, x0, 0.0, z0, 0.0, 0.0)
	b._solid_fill(img, x0, x0, 0.0, HEDGE_Z0, HEDGE_Z1, HEDGE_H)
	b._solid_fill(img, x0, L, L + 60.0, z0, 0.0, 0.0)
	b._solid_fill(img, x0, L, L + 60.0, HEDGE_Z0, HEDGE_Z1, HEDGE_H)
	for l in b.data.get("lots", []):
		var lx := float(l["x"])
		var lw := float(l["w"])
		match String(l.get("style", "")):
			"hedge", "tree", "bus_shelter", "lychgate", "barn":
				b._solid_fill(img, x0, lx, lx + lw, z0, 0.0, 0.0)
				if String(l["style"]) in ["hedge", "tree"]:
					b._solid_fill(img, x0, lx, lx + lw, HEDGE_Z0, HEDGE_Z1, HEDGE_H)
			"field_gate":
				b._solid_fill(img, x0, lx, lx + lw, z0, 0.0, 0.0)
				var g0 := lx + maxf((lw - GATE_W) * 0.5, 0.0)
				b._solid_fill(img, x0, lx, g0, HEDGE_Z0, HEDGE_Z1, HEDGE_H)
				b._solid_fill(img, x0, g0 + GATE_W, lx + lw, HEDGE_Z0, HEDGE_Z1, HEDGE_H)
			"stone_wall":
				b._solid_fill(img, x0, lx, lx + lw, z0, 0.0, 0.0)
				b._solid_fill(img, x0, lx, lx + lw, WALL_Z - 0.25, WALL_Z + 0.2, WALL_H + 0.2)


## A lot's COVERS entry in the rain's cover map: roofs are thin shells drops stop on, so slanted
## rain still blows in under their edges.
static func cover_map_lot(b: LevelBuilder, img: Image, x0: float, l: Dictionary) -> void:
	var lx := float(l["x"])
	var lw := float(l["w"])
	match String(l.get("cover", "none")):
		"shelter":
			b._cover_fill(img, x0, lx, lx + lw, -0.2, SHELTER_Z, func(z): return cover_top("shelter", z))
		"barn":
			b._cover_fill(img, x0, lx, lx + lw, LevelBuilder.COVER_Z0, BARN_Z, func(_z): return cover_top("barn"))
		"porch":
			var sp := porch_span(l)
			b._cover_fill(img, x0, lx + sp[0], lx + sp[1], -0.2, PORCH_Z, func(_z): return cover_top("porch"))


# --- light and sky ---------------------------------------------------------------------------------

## A wet grey morning in the country: a sky of broken rain cloud with the sun low behind it, soft
## daylight, a paler haze that lets the hills show, and the colour left in. Called by Level after
## its own environment is set up, on a country street only.
static func environment(env: Environment, light: DirectionalLight3D) -> void:
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://src/fx/country_sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_energy = 0.6
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_exposure = 1.0
	env.glow_hdr_threshold = 1.0
	env.volumetric_fog_density = 0.016
	env.volumetric_fog_albedo = Color(0.72, 0.76, 0.8)
	env.volumetric_fog_emission = Color(0.05, 0.055, 0.06)
	env.volumetric_fog_length = 90.0
	env.fog_light_color = Color(0.43, 0.47, 0.51)
	env.fog_density = 0.006
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.4
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.12
	light.light_color = Color(0.74, 0.8, 0.9)
	light.light_energy = 0.5
	light.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	light.shadow_blur = 2.5
	light.directional_shadow_max_distance = 60.0
