class_name ModernBuilder
extends RefCounted
## The jet-age city centre, drawn in code and called from LevelBuilder like the roadside's:
##   glass_tower  a curtain-wall tower (4 m ground floor + 3.2 m per `floors`): pilotis clad in
##                travertine in front of a recessed glass lobby on a terrazzo floor, `sign` in
##                stainless capitals on the fascia over it (lot style `glass_tower`).
##   lobby        a double-height glass lobby (ground and first floor, 7.2 m), lit inside with
##                `"lit": true`, a mezzanine and globe lamps; the tower rises above it.
##   plaza        an open paved plaza (no cover) with planters, flagpoles and globe lamps, its tower
##                SET_BACK behind the lot line: `floors` sets how much of the skyline shows above it.
##   side_wall / far_facade   glass down and across a side street beside a modern lot.
##   skyline      skyscrapers behind the street for `aesthetic: "modern"`, offices lit, beacons on top.
## Purely visual: none of it is cover and nothing collides. Every curtain wall is one quad in a merged
## mesh drawn by src/fx/curtain_wall.gdshader, so a tower costs a handful of draw calls.
## Runs inside LevelBuilder.build, possibly on a worker thread: it only adds nodes.

const STYLES := ["glass_tower", "lobby", "plaza"]
const GROUND_H := 4.0         # kit convention: the ground floor, then 3.2 m storeys
const STOREY := 3.2
const RECESS := 1.8           # how far a tower's lobby glass stands behind its pilotis
const FASCIA_Y := 3.3         # underside of the fascia over the recess; the sign sits on it, in the 3.1-3.9 band
const LOBBY_H := 7.2          # a lobby's double height
const SET_BACK := 16.0        # a plaza's tower stands this far behind the lot line
const DEPTH := 10.0           # tower mass behind the facade, seen from side streets
const SKYLINE_Z := [-55.0, -90.0]   # the two rows of skyscrapers


static func lot(b: LevelBuilder, x: float, w: float, style: String, floors: int, lot_d: Dictionary) -> void:
	var lit := bool(lot_d.get("lit", true))
	var seed := float(b._lot_hash(x, "tower") % 997) / 997.0
	var pal := int(lot_d.get("palette", b._lot_hash(x, "palette") % 4))
	var h := GROUND_H + STOREY * maxi(floors, 0)
	match style:
		"glass_tower":
			_tower(b, x, x + w, 0.0, h, seed, pal, lit)
			_ground_floor(b, x, x + w, 0.0, lit, seed)
			if lot_d.has("sign"):
				sign_text(b, x + w * 0.5, FASCIA_Y + 0.35, 0.06, String(lot_d["sign"]), w - 1.0)
		"lobby":
			_tower(b, x, x + w, 0.0, maxf(h, LOBBY_H), seed, pal, lit, LOBBY_H)
			_lobby(b, x, x + w, lit, seed)
			if lot_d.has("sign"):
				sign_text(b, x + w * 0.5, FASCIA_Y + 0.35, 0.02, String(lot_d["sign"]), w - 1.0)
		"plaza":
			_plaza(b, x, w)
			var tx0 := x + minf(2.0, w * 0.15)
			var tx1 := x + w - minf(2.0, w * 0.15)
			_tower(b, tx0, tx1, -SET_BACK, h, seed, pal, lit)
			_ground_floor(b, tx0, tx1, -SET_BACK, lit, seed)
			if lot_d.has("sign"):
				sign_text(b, (tx0 + tx1) * 0.5, FASCIA_Y + 0.35, -SET_BACK + 0.06, String(lot_d["sign"]), tx1 - tx0 - 1.0)


# --- visuals: towers ------------------------------------------------------------------------------

## A tower's mass and its curtain wall from `from_y` (the ground floor's top) to h, front at z.
static func _tower(b: LevelBuilder, x0: float, x1: float, z: float, h: float, seed: float, pal: int, lit: bool,
		from_y := GROUND_H) -> void:
	var mass := b._mat("tower_mass", Color(0.07, 0.08, 0.09), 0.6, 0.3)
	b._box(Vector3(x1 - x0 - 0.24, h - 0.05, DEPTH), Vector3((x0 + x1) * 0.5, h * 0.5, z - 0.3 - DEPTH * 0.5), mass)
	var st := _curtain_st()
	curtain(st, Vector3(x0 + 0.1, from_y, z), Vector3(x1 - 0.1, h, z), Vector3.BACK, seed,
		0.38 if lit else 0.22, pal, 1.0, from_y)
	_commit_curtain(b, st)
	var sts := {}
	var mull: Material = _mullion_mat(b, pal)
	# Mullion fins on every other bay line, standing proud of the glass, and a crown at the top.
	var bx := x0 + 0.1
	while bx <= x1 - 0.1 + 0.001:
		RoadsideBuilder._add(sts, mull, bx - 0.03, bx + 0.03, from_y, h, z, z + 0.14)
		bx += 3.2
	RoadsideBuilder._add(sts, b._mat("tower_crown", Color(0.2, 0.22, 0.24), 0.5, 0.5), x0 + 0.1, x1 - 0.1, h, h + 1.6, z - 0.6, z - 0.2)
	RoadsideBuilder._add(sts, mull, x0 + 0.05, x1 - 0.05, h - 0.1, h + 0.05, z - 0.1, z + 0.18)
	RoadsideBuilder._commit(b, sts)


static func _mullion_mat(b: LevelBuilder, pal: int) -> Material:
	var cols := [Color(0.72, 0.75, 0.78), Color(0.33, 0.23, 0.13), Color(0.78, 0.78, 0.76), Color(0.1, 0.1, 0.11)]
	return b._mat("mullion_%d" % pal, cols[pal], 0.28, 0.85)


## The ground floor under a tower: travertine pilotis at the front line, a fascia over the recess
## (the sign's band), lobby glass RECESS back, terrazzo underfoot, downlights in the soffit.
static func _ground_floor(b: LevelBuilder, x0: float, x1: float, z: float, lit: bool, seed: float) -> void:
	var sts := {}
	var trav := travertine(b)
	var w := x1 - x0
	var n := maxi(1, roundi(w / 3.2))
	for i in n + 1:
		var px := clampf(x0 + w * i / n, x0 + 0.3, x1 - 0.3)
		RoadsideBuilder._add(sts, trav, px - 0.28, px + 0.28, 0.0, FASCIA_Y, z - 0.55, z - 0.0)
	RoadsideBuilder._add(sts, trav, x0, x1, FASCIA_Y, GROUND_H, z - RECESS, z + 0.04)
	RoadsideBuilder._add(sts, b._mat("terrazzo", Color(0.5, 0.48, 0.44), 0.3), x0, x1, -0.1, 0.012, z - RECESS, z)
	RoadsideBuilder._add(sts, b._mat("tower_soffit", Color(0.62, 0.6, 0.56), 0.8), x0, x1, FASCIA_Y - 0.03, FASCIA_Y, z - RECESS, z - 0.02)
	var down := b._neon_mat(Color(1.0, 0.93, 0.8), 2.0)
	var dx := x0 + 1.6
	while dx < x1 - 0.8:
		RoadsideBuilder._add(sts, down, dx - 0.15, dx + 0.15, FASCIA_Y - 0.04, FASCIA_Y - 0.03, z - 1.1, z - 0.8)
		dx += 3.2
	_glass_front(b, sts, x0 + 0.1, x1 - 0.1, z - RECESS, FASCIA_Y, lit, seed)
	RoadsideBuilder._commit(b, sts)
	if lit:
		b.lit_windows.append([Vector3((x0 + x1) * 0.5, 2.0, z - RECESS + 0.6), Color(1.0, 0.86, 0.66)])


## A lobby's glazing at z from the floor to `top`, aluminium mullions and a bronze door pair, and the
## lit (or dim) interior behind: a glowing back wall with lift doors.
static func _glass_front(b: LevelBuilder, sts: Dictionary, x0: float, x1: float, z: float, top: float, lit: bool,
		seed: float) -> void:
	var alu := b._mat("motel_alu", Color(0.55, 0.56, 0.58), 0.35, 0.8)
	var inside: Material = RoadsideBuilder._glow(b, "lobby_lit", Color(0.95, 0.82, 0.62), 0.9) if lit \
		else b._mat("lobby_dim", Color(0.06, 0.07, 0.075), 0.2, 0.4)
	RoadsideBuilder._add(sts, inside, x0, x1, 0.0, top, z - 0.06, z - 0.02)
	if lit:
		var bronze := b._mat("lift_bronze", Color(0.38, 0.26, 0.14), 0.35, 0.8)
		var lx := x0 + 1.2 + fmod(seed * 7.0, 1.5)
		while lx < x1 - 1.4:
			RoadsideBuilder._add(sts, bronze, lx, lx + 1.1, 0.0, 2.3, z - 0.02, z - 0.01)
			lx += 3.0
	var n := maxi(2, roundi((x1 - x0) / 1.8))
	for i in n + 1:
		var mx := lerpf(x0, x1, float(i) / n)
		RoadsideBuilder._add(sts, alu, mx - 0.03, mx + 0.03, 0.0, top, z, z + 0.07)
	RoadsideBuilder._add(sts, alu, x0, x1, top - 0.08, top, z, z + 0.08)
	RoadsideBuilder._add(sts, alu, x0, x1, 0.0, 0.1, z, z + 0.08)
	var door := (x0 + x1) * 0.5
	RoadsideBuilder._add(sts, b._mat("brass", Color(0.7, 0.55, 0.25), 0.3, 0.8), door - 0.9, door + 0.9, 2.3, 2.38, z, z + 0.09)
	RoadsideBuilder._add(sts, b._mat("brass", Color(0.7, 0.55, 0.25), 0.3, 0.8), door - 0.02, door + 0.02, 0.0, 2.3, z, z + 0.09)


## The double-height lobby: glass from the pavement to LOBBY_H a little behind the lot line, the
## interior behind it (mezzanine, back wall, globe lamps), and a stainless sign bar across the glass.
static func _lobby(b: LevelBuilder, x0: float, x1: float, lit: bool, seed: float) -> void:
	var sts := {}
	var z := -0.15
	var deep := -8.0
	var trav := travertine(b)
	var back: Material = RoadsideBuilder._glow(b, "lobby_back", Color(0.85, 0.74, 0.58), 0.55) if lit \
		else b._mat("lobby_back_dim", Color(0.2, 0.18, 0.15), 0.6)
	RoadsideBuilder._add(sts, back, x0 + 0.2, x1 - 0.2, 0.0, LOBBY_H, deep - 0.1, deep)
	RoadsideBuilder._add(sts, b._mat("terrazzo", Color(0.5, 0.48, 0.44), 0.3), x0, x1, -0.1, 0.012, deep, z)
	RoadsideBuilder._add(sts, b._mat("tower_soffit", Color(0.62, 0.6, 0.56), 0.8), x0, x1, LOBBY_H - 0.1, LOBBY_H, deep, z)
	for ex in [x0, x1 - 0.25]:
		RoadsideBuilder._add(sts, trav, ex, ex + 0.25, 0.0, LOBBY_H, deep, z + 0.1)
	# The mezzanine across the back, its white fascia and chrome rail.
	var white := b._mat("skyway_concrete", Color(0.86, 0.85, 0.8), 0.55)
	RoadsideBuilder._add(sts, white, x0 + 0.25, x1 - 0.25, 3.6, 4.0, deep, -4.6)
	RoadsideBuilder._add(sts, b._mat("chrome", Color(0.82, 0.84, 0.88), 0.12, 1.0), x0 + 0.25, x1 - 0.25, 4.95, 5.0, -4.7, -4.6)
	# Globe lamps on rods from the ceiling.
	var globe := b._neon_mat(Color(1.0, 0.9, 0.72), 2.2 if lit else 0.4)
	var gx := x0 + 1.5 + fmod(seed * 5.0, 1.0)
	while gx < x1 - 1.0:
		var g := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		g.mesh = sm
		g.material_override = globe
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.position = Vector3(gx, 5.6, -2.6)
		b.root.add_child(g)
		RoadsideBuilder._add(sts, b._mat("chrome", Color(0.82, 0.84, 0.88), 0.12, 1.0), gx - 0.01, gx + 0.01, 5.8, LOBBY_H, -2.61, -2.59)
		gx += 2.6
	# The glazing: tall panes, a door pair in bronze, the sign bar.
	var alu := b._mat("motel_alu", Color(0.55, 0.56, 0.58), 0.35, 0.8)
	var n := maxi(2, roundi((x1 - x0) / 1.8))
	for i in n + 1:
		var mx := lerpf(x0 + 0.25, x1 - 0.25, float(i) / n)
		RoadsideBuilder._add(sts, alu, mx - 0.035, mx + 0.035, 0.0, LOBBY_H, z, z + 0.1)
	RoadsideBuilder._add(sts, alu, x0, x1, LOBBY_H - 0.15, LOBBY_H, z - 0.05, z + 0.12)
	RoadsideBuilder._add(sts, b._mat("brass", Color(0.7, 0.55, 0.25), 0.3, 0.8), x0 + 0.25, x1 - 0.25, 2.5, 2.58, z, z + 0.1)
	RoadsideBuilder._add(sts, b._mat("lobby_band", Color(0.16, 0.17, 0.18), 0.3, 0.7), x0 + 0.25, x1 - 0.25, FASCIA_Y, GROUND_H - 0.05, z - 0.02, z + 0.0)
	RoadsideBuilder._commit(b, sts)
	var glass := ShaderMaterial.new()
	glass.shader = load("res://src/fx/skyway_glass.gdshader")
	glass.set_shader_parameter("tint", Color(0.4, 0.6, 0.6, 0.14))
	glass.set_shader_parameter("rain", 0.5)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(x1 - x0 - 0.5, LOBBY_H)
	q.mesh = qm
	q.material_override = glass
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = Vector3((x0 + x1) * 0.5, LOBBY_H * 0.5, z + 0.05)
	b.root.add_child(q)
	if lit:
		b.lit_windows.append([Vector3((x0 + x1) * 0.5, 2.5, -1.6), Color(1.0, 0.86, 0.66)])


# --- visuals: plaza -------------------------------------------------------------------------------

## Travertine paving back to the tower, planters with clipped shrubs, three flagpoles, globe lamps.
static func _plaza(b: LevelBuilder, x: float, w: float) -> void:
	var paving := b._mat("plaza_paving", Color(0.6, 0.57, 0.52), 0.22)
	b._box(Vector3(w, 0.3, SET_BACK), Vector3(x + w * 0.5, -0.15 + 0.004, -SET_BACK * 0.5), paving)
	var sts := {}
	var joint := b._mat("plaza_joint", Color(0.36, 0.34, 0.31), 0.5)
	var jx := x + 1.5
	while jx < x + w - 0.1:
		RoadsideBuilder._add(sts, joint, jx - 0.02, jx + 0.02, 0.0, 0.012, -SET_BACK, -0.05)
		jx += 1.5
	var jz := -1.5
	while jz > -SET_BACK:
		RoadsideBuilder._add(sts, joint, x, x + w, 0.0, 0.012, jz - 0.02, jz + 0.02)
		jz -= 1.5
	var trav := travertine(b)
	var shrub := b._mat("plaza_shrub", Color(0.06, 0.12, 0.07), 0.9)
	var px := x + 2.0
	while px + 3.0 < x + w - 1.0:
		for pz in [-4.5, -10.5]:
			RoadsideBuilder._add(sts, trav, px, px + 3.0, 0.0, 0.55, pz - 0.7, pz + 0.7)
			RoadsideBuilder._add(sts, shrub, px + 0.15, px + 2.85, 0.55, 0.95, pz - 0.55, pz + 0.55)
		px += 6.5
	# A long travertine bench slab near the street, flagpoles toward one side.
	if w >= 8.0:
		RoadsideBuilder._add(sts, trav, x + w * 0.5 - 1.8, x + w * 0.5 + 1.8, 0.0, 0.45, -1.9, -1.3)
	var pole := b._mat("flagpole", Color(0.85, 0.86, 0.86), 0.3, 0.8)
	var flag_cols := [Color(0.5, 0.1, 0.1), Color(0.12, 0.2, 0.45), Color(0.75, 0.72, 0.62)]
	for i in 3:
		var fx := x + 1.2 + i * 1.3
		RoadsideBuilder._add(sts, pole, fx - 0.05, fx + 0.05, 0.0, 10.0, -2.6, -2.5)
		# A sodden flag hanging close to its pole.
		RoadsideBuilder._add(sts, b._mat("flag_%d" % i, flag_cols[i], 0.9), fx + 0.05, fx + 0.45, 8.0, 9.8, -2.57, -2.53)
	RoadsideBuilder._commit(b, sts)
	var lx := x + 1.5
	while lx < x + w - 0.5:
		b._box(Vector3(0.1, 0.9, 0.1), Vector3(lx, 0.45, -0.6), pole)
		var g := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.17
		sm.height = 0.34
		g.mesh = sm
		g.material_override = b._neon_mat(Color(1.0, 0.93, 0.8), 2.0)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.position = Vector3(lx, 1.02, -0.6)
		b.root.add_child(g)
		var om := OmniLight3D.new()
		om.light_color = Color(1.0, 0.88, 0.7)
		om.light_energy = 1.0
		om.omni_range = 4.0
		om.light_volumetric_fog_energy = 0.5
		om.position = Vector3(lx, 1.3, -0.3)
		b.root.add_child(om)
		lx += 5.0
	b._box(Vector3(w + 6.0, 9.0, 1.0), Vector3(x + w * 0.5, 4.5, -SET_BACK - DEPTH - 2.0), b._mat("farwall", Color(0.22, 0.2, 0.19), 0.9))


# --- visuals: side streets and the skyline --------------------------------------------------------

## The glass flank of a modern lot down a side street: face in the plane x, facing +X (or -X).
static func side_wall(b: LevelBuilder, x: float, floors: int, facing: float) -> void:
	var h := GROUND_H + STOREY * maxi(floors, 0)
	var depth := 28.0
	var mass := b._mat("tower_mass", Color(0.07, 0.08, 0.09), 0.6, 0.3)
	b._box(Vector3(0.5, h, depth), Vector3(x - facing * 0.3, h * 0.5, -depth * 0.5), mass)
	var st := _curtain_st()
	var seed := float(b._lot_hash(x, "side") % 997) / 997.0
	curtain(st, Vector3(x + facing * 0.02, GROUND_H, -0.4), Vector3(x + facing * 0.02, h, -depth), Vector3(facing, 0, 0),
		seed, 0.3, b._lot_hash(x, "palette") % 4, 1.0, GROUND_H)
	_commit_curtain(b, st)
	var sts := {}
	RoadsideBuilder._add(sts, travertine(b), minf(x, x + facing * 0.06), maxf(x, x + facing * 0.06), 0.0, GROUND_H, -depth, -0.4)
	RoadsideBuilder._commit(b, sts)


## Glass towers across the far end of a side street.
static func far_facade(b: LevelBuilder, x0: float, x1: float, z: float) -> void:
	var st := _curtain_st()
	var mass := b._mat("tower_mass", Color(0.07, 0.08, 0.09), 0.6, 0.3)
	var fx := x0 - 6.0
	var i := 0
	while fx < x1 + 6.0:
		var r := b._lot_hash(fx, "far")
		var fw := 8.0 + float(r % 7)
		var fh := 30.0 + float(r % 40)
		b._box(Vector3(fw, fh, 6.0), Vector3(fx + fw * 0.5, fh * 0.5, z - 3.0), mass)
		curtain(st, Vector3(fx + 0.2, GROUND_H, z + 0.02), Vector3(fx + fw - 0.2, fh, z + 0.02), Vector3.BACK,
			float(r % 991) / 991.0, 0.3, r % 4, 0.6, GROUND_H)
		fx += fw + 0.4
		i += 1
	_commit_curtain(b, st)


## Skyscrapers behind the street in two rows, their offices lit, a red beacon on the tall ones and a
## mast on a few. Seeded by the level id, so a street always shows the same skyline.
static func skyline(b: LevelBuilder) -> void:
	var L: float = b.data["length"]
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(b.data.get("id", "level")) + ":skyline")
	var mass := b._mat("skyline_mass", Color(0.035, 0.04, 0.05), 0.7, 0.2)
	var st := _curtain_st()
	var masses := {}
	var beacons: Array = []
	for row in 2:
		var z: float = SKYLINE_Z[row]
		var x := -60.0 + row * 9.0
		while x < L + 60.0:
			var w := r.randf_range(12.0, 26.0)
			var h := r.randf_range(40.0, 90.0) + row * r.randf_range(10.0, 70.0)
			var d := r.randf_range(12.0, 20.0)
			RoadsideBuilder._add(masses, mass, x, x + w, 0.0, h, z - d, z)
			curtain(st, Vector3(x + 0.3, 6.0, z + 0.02), Vector3(x + w - 0.3, h, z + 0.02), Vector3.BACK,
				r.randf(), r.randf_range(0.15, 0.4), r.randi() % 4, 0.0, 6.0, 3.6)
			if r.randf() < 0.35:   # a setback: a narrower block on top
				var w2 := w * r.randf_range(0.45, 0.7)
				var x2 := x + (w - w2) * 0.5
				var h2 := h + r.randf_range(12.0, 30.0)
				RoadsideBuilder._add(masses, mass, x2, x2 + w2, h, h2, z - d * 0.7, z - 2.0)
				curtain(st, Vector3(x2 + 0.3, h, z - 1.98), Vector3(x2 + w2 - 0.3, h2, z - 1.98), Vector3.BACK,
					r.randf(), 0.3, r.randi() % 4, 0.0, h, 3.6)
				h = h2
			if h > 85.0:
				beacons.append(Vector3(x + w * 0.5, h + 0.5, z - 2.0))
				if r.randf() < 0.4:
					RoadsideBuilder._add(masses, mass, x + w * 0.5 - 0.15, x + w * 0.5 + 0.15, h, h + 14.0, z - 3.0, z - 2.7)
					beacons[-1] = Vector3(x + w * 0.5, h + 14.2, z - 2.8)
			x += w + r.randf_range(2.0, 9.0)
	RoadsideBuilder._commit(b, masses)
	_commit_curtain(b, st)
	var red := ShaderMaterial.new()
	red.shader = load("res://src/fx/beacon.gdshader")
	for i in beacons.size():
		var bm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 8
		sm.rings = 4
		bm.mesh = sm
		bm.material_override = red
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bm.set_instance_shader_parameter("phase", float(i) * 0.37)
		bm.position = beacons[i]
		b.root.add_child(bm)


# --- helpers ----------------------------------------------------------------------------------------

## Stainless capitals on the fascia.
static func sign_text(b: LevelBuilder, cx: float, y: float, z: float, text: String, max_w: float) -> void:
	if text.strip_edges().is_empty():
		return
	var tm := TextMesh.new()
	tm.text = text.to_upper()
	tm.font_size = 64
	tm.pixel_size = 0.0055
	tm.depth = 0.04
	if b.sign_font:
		tm.font = b.sign_font
	var est := text.length() * tm.font_size * 0.62 * tm.pixel_size
	if est > max_w:
		tm.pixel_size *= max_w / est
	# Brushed steel catching the soffit's downlights: a little self-lit so it reads at night.
	var steel := b._mat("sign_steel", Color(0.86, 0.87, 0.88), 0.25, 0.85)
	steel.emission_enabled = true
	steel.emission = Color(0.75, 0.8, 0.85)
	steel.emission_energy_multiplier = 0.45
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = steel
	mi.position = Vector3(cx, y, z + 0.05)
	b.root.add_child(mi)


static func travertine(b: LevelBuilder) -> Material:
	return RoadsideBuilder._textured(b, "travertine", "concrete", Color(0.86, 0.8, 0.7))


static func _curtain_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## One curtain wall from corner a to corner c in a plane facing `nrm` (+Z, or ±X for a side wall),
## its look passed to curtain_wall.gdshader in the vertices.
static func curtain(st: SurfaceTool, a: Vector3, c: Vector3, nrm: Vector3, seed: float, lit: float, pal: int,
		detail: float, floor0: float, floor_h := STOREY) -> void:
	var col := Color(seed, lit, pal / 4.0, detail)
	var side := absf(nrm.x) > 0.5
	var corners: Array = [Vector3(a.x, a.y, a.z), Vector3(c.x, a.y, c.z), Vector3(c.x, c.y, c.z), Vector3(a.x, c.y, a.z)]
	var order := [0, 2, 1, 0, 3, 2] if (nrm.z > 0.0 or nrm.x > 0.0) else [0, 1, 2, 0, 2, 3]
	for i in order:
		var p: Vector3 = corners[i]
		st.set_color(col)
		st.set_normal(nrm)
		st.set_uv(Vector2(-p.z if side else p.x, p.y))
		st.set_uv2(Vector2(floor0, floor_h))
		st.add_vertex(p)


static func _commit_curtain(b: LevelBuilder, st: SurfaceTool) -> void:
	if not b._mats.has("curtain_wall"):
		var m := ShaderMaterial.new()
		m.shader = load("res://src/fx/curtain_wall.gdshader")
		b._mats["curtain_wall"] = m
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = b._mats["curtain_wall"]
	b.root.add_child(mi)
