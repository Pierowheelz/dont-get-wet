class_name ModernBuilder
extends RefCounted
## The jet-age city centre, drawn in code and called from LevelBuilder like the roadside's:
##   glass_tower  a curtain-wall tower (4 m ground floor + 3.2 m per `floors`): travertine piers at
##                the lot line in front of a glass lobby RECESS back, lit and furnished (lifts, a
##                reception or a mural wall, by the lot), `sign` in lit capitals on an enamel fascia.
##   lobby        a double-height glass lobby (7.2 m) with a mezzanine, pendant lamps and a feature on
##                its back wall (a departures board for a terminal or an airline, else a clock or a
##                mural); the tower rises above it. `"lit": false` leaves either kind dark.
##   plaza        an open paved plaza (no cover): a pool, a spire or a clipped tree, the neighbours'
##                flanks either side (glass where they are towers) and its tower SET_BACK behind the
##                lot line, in the haze, so the skyline stands over it.
##   side_wall / far_facade   glass down and across a side street beside a modern lot.
##   skyline      three rows of skyscrapers behind the street for `aesthetic: "modern"`, each paler
##                in the haze than the one in front, windows lit, warning lights on the tall ones.
## Purely visual: none of it is cover and nothing collides. Every curtain wall is one quad drawn by
## src/fx/curtain_wall.gdshader (rooms behind the glass and all), the whole skyline is two meshes,
## and each lot's solid parts are batched by material, so a tower costs a handful of draw calls.
## Runs inside LevelBuilder.build, possibly on a worker thread: it only adds nodes.

const STYLES := ["glass_tower", "lobby", "plaza"]
const GROUND_H := 4.0         # kit convention: the ground floor, then 3.2 m storeys
const STOREY := 3.2
const BAY := 1.6              # curtain-wall bay (curtain_wall.gdshader's bay_w)
const RECESS := 1.8           # how far a tower's lobby glass stands behind its piers
const ROOM := 3.8             # depth of the lobby behind that glass
const FASCIA_Y := 3.3         # underside of the fascia over the recess; the sign sits on it, in the 3.1-3.9 band
const LOBBY_H := 7.2          # a lobby's double height
const LOBBY_DEPTH := 8.0
const SET_BACK := 40.0        # a plaza's tower stands this far behind the lot line, low enough in the frame for the skyline to stand over it
const DEPTH := 10.0           # tower mass behind the facade
const FLANK := 34.0           # how far a tower's glass side runs back down a side street
const FIN_TOP := 34.0         # mullion fins are drawn this high: no camera sees further up a near tower
# The skyline's rows: [z, lowest, tallest, haze]. The far rows are low enough in the frame to show
# their tops; the near one mostly runs out of it.
const SKYLINE := [[-58.0, 28.0, 70.0, 0.2], [-96.0, 45.0, 100.0, 0.42], [-150.0, 60.0, 135.0, 0.62]]
const PALETTES := [0, 0, 2, 0, 1, 0, 2, 3]   # mostly blue-green glass, some white spandrels, a little bronze and black
const FASCIA := [Color(0.05, 0.27, 0.27), Color(0.17, 0.1, 0.05), Color(0.06, 0.09, 0.19), Color(0.04, 0.04, 0.05)]


static func lot(b: LevelBuilder, x: float, w: float, style: String, floors: int, lot_d: Dictionary) -> void:
	var lit := bool(lot_d.get("lit", true))
	var seed := float(b._lot_hash(x, "tower") % 997) / 997.0
	var pal := int(lot_d.get("palette", PALETTES[b._lot_hash(x, "palette") % PALETTES.size()]))
	var h := GROUND_H + STOREY * maxi(floors, 0)
	var text := String(lot_d.get("sign", ""))
	match style:
		"glass_tower":
			_tower(b, x, x + w, 0.0, h, seed, pal, lit)
			_ground_floor(b, x, x + w, 0.0, lit, pal)
			sign_text(b, x + w * 0.5, FASCIA_Y + 0.35, 0.06, text, w - 1.0)
		"lobby":
			_tower(b, x, x + w, 0.0, maxf(h, LOBBY_H), seed, pal, lit, LOBBY_H)
			_lobby(b, x, x + w, lit, text)
			sign_text(b, x + w * 0.5, FASCIA_Y + 0.35, 0.02, text, w - 1.0)
		"plaza":
			_plaza(b, x, w)
			# Its tower, 40 m back, is drawn like the skyline's: in its own haze, since the street's fog
			# would swallow a curtain wall that far off.
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_block(st, x - 3.0, x + w + 3.0, 0.0, h, -SET_BACK, DEPTH, Color(seed, 0.5 if lit else 0.15, 0.06, float(b._lot_hash(x, "plaza_tower") % 3) * 0.5))
			_commit_shader(b, st, "skyline", "res://src/fx/skyline.gdshader")
			# The neighbours' flanks, as deep as the buildings are, in glass where they are towers.
			for side in [[x, 1.0], [x + w, -1.0]]:
				var nb := _neighbour(b, side[0], side[1])
				if not nb.is_empty() and String(nb.get("style", "")) != "plaza":
					side_wall(b, side[0], int(nb.get("floors", 2)), side[1], STYLES.has(String(nb.get("style", ""))), DEPTH + 2.0)


## The lot that ends (facing 1) or starts (facing -1) at x: the one whose flank faces that way.
static func _neighbour(b: LevelBuilder, x: float, facing: float) -> Dictionary:
	for l in b.data.get("lots", []):
		var edge := float(l["x"]) + (float(l["w"]) if facing > 0.0 else 0.0)
		if absf(edge - x) < 0.05:
			return l
	return {}


# --- visuals: towers ------------------------------------------------------------------------------

## A tower's mass and its curtain wall from `from_y` (the ground floor's top) to h, front at z.
static func _tower(b: LevelBuilder, x0: float, x1: float, z: float, h: float, seed: float, pal: int, lit: bool,
		from_y := GROUND_H) -> void:
	var mass := b._mat("tower_mass", Color(0.05, 0.06, 0.07), 0.6, 0.3)
	b._box(Vector3(x1 - x0 - 0.1, h - from_y, DEPTH), Vector3((x0 + x1) * 0.5, (h + from_y) * 0.5, z - 0.4 - DEPTH * 0.5), mass)
	var st := _curtain_st()
	curtain(st, Vector3(x0, from_y, z), Vector3(x1, h, z), Vector3.BACK, seed, 0.4 if lit else 0.2, pal, 1.0, from_y)
	_commit_curtain(b, st)
	var sts := {}
	var mull: Material = _mullion_mat(b, pal)
	# A mullion fin on every bay line, standing proud of the glass, and a wider one at each corner.
	var top := minf(h, FIN_TOP)
	var bx := ceilf(x0 / BAY) * BAY
	while bx <= x1 - 0.2:
		if bx > x0 + 0.2:
			RoadsideBuilder._add(sts, mull, bx - 0.025, bx + 0.025, from_y, top, z, z + 0.15)
		bx += BAY
	for ex in [x0, x1 - 0.09]:
		RoadsideBuilder._add(sts, mull, ex, ex + 0.09, from_y, top, z - 0.05, z + 0.2)
	if h <= FIN_TOP:   # a low tower shows its top: a white parapet and the lift house behind it
		var white := white(b)
		RoadsideBuilder._add(sts, white, x0 - 0.05, x1 + 0.05, h, h + 0.5, z - DEPTH - 0.4, z + 0.22)
		RoadsideBuilder._add(sts, mass, lerpf(x0, x1, 0.3), lerpf(x0, x1, 0.75), h + 0.5, h + 3.2, z - 6.0, z - 2.5)
	_commit(b, sts)


static func _mullion_mat(b: LevelBuilder, pal: int) -> Material:
	var cols := [Color(0.74, 0.77, 0.8), Color(0.36, 0.25, 0.14), Color(0.8, 0.8, 0.78), Color(0.1, 0.1, 0.11)]
	return b._mat("mullion_%d" % pal, cols[pal], 0.28, 0.85)


## The ground floor under a tower: travertine piers at the lot line, an enamel fascia over the
## recess (the sign's band), the lobby's glass RECESS back, and the lobby itself behind it.
static func _ground_floor(b: LevelBuilder, x0: float, x1: float, z: float, lit: bool, pal: int) -> void:
	var sts := {}
	var trav := travertine(b)
	var alu := b._mat("skyway_alu", Color(0.8, 0.82, 0.84), 0.25, 0.85)
	var w := x1 - x0
	var gz := z - RECESS
	var back := gz - ROOM
	RoadsideBuilder._add(sts, terrazzo(b), x0, x1, -0.1, 0.012, back, z)
	RoadsideBuilder._add(sts, b._mat("tower_soffit", Color(0.7, 0.69, 0.65), 0.8), x0, x1, FASCIA_Y, FASCIA_Y + 0.06, back, z - 0.02)
	# Piers: half a pier at each end (it pairs with the neighbour's), whole ones between.
	RoadsideBuilder._add(sts, trav, x0, x0 + 0.22, 0.0, FASCIA_Y, z - 0.5, z)
	RoadsideBuilder._add(sts, trav, x1 - 0.22, x1, 0.0, FASCIA_Y, z - 0.5, z)
	var n := maxi(1, roundi(w / 3.4))
	for i in range(1, n):
		var px := x0 + w * i / n
		RoadsideBuilder._add(sts, trav, px - 0.22, px + 0.22, 0.0, FASCIA_Y, z - 0.5, z)
	RoadsideBuilder._add(sts, _enamel(b, pal), x0, x1, FASCIA_Y, GROUND_H, z - 0.4, z + 0.05)
	for y in [FASCIA_Y, GROUND_H - 0.04]:
		RoadsideBuilder._add(sts, alu, x0, x1, y, y + 0.04, z + 0.05, z + 0.075)
	var down := b._neon_mat(Color(1.0, 0.93, 0.8), 2.2)
	var dn := maxi(2, roundi(w / 1.7))
	for i in dn:
		var dx := x0 + w * (i + 0.5) / dn
		cyl(sts, down, Vector3(dx, FASCIA_Y - 0.03, z - 0.95), Vector3(dx, FASCIA_Y + 0.01, z - 0.95), 0.11, 0.11, 10)
	_glass_front(b, sts, x0 + 0.05, x1 - 0.05, gz, FASCIA_Y)
	var kind := b._lot_hash(x0 + z * 3.0, "lobby") % 3 if lit else 3
	_lobby_room(b, sts, x0, x1, gz, back, kind)
	_commit(b, sts)
	if lit:
		b.lit_windows.append([Vector3((x0 + x1) * 0.5, 2.0, gz + 0.6), Color(1.0, 0.86, 0.66)])


## A lobby's glazing at z from the floor to `top`: slim aluminium mullions, a door pair with brass
## pulls in the middle, and the pane itself.
static func _glass_front(b: LevelBuilder, sts: Dictionary, x0: float, x1: float, z: float, top: float) -> void:
	var alu := b._mat("skyway_alu", Color(0.8, 0.82, 0.84), 0.25, 0.85)
	var brass := b._mat("brass", Color(0.7, 0.55, 0.25), 0.3, 0.8)
	var n := maxi(2, roundi((x1 - x0) / 1.7))
	for i in n + 1:
		var mx := lerpf(x0 + 0.03, x1 - 0.03, float(i) / n)
		RoadsideBuilder._add(sts, alu, mx - 0.025, mx + 0.025, 0.0, top, z, z + 0.08)
	RoadsideBuilder._add(sts, alu, x0, x1, top - 0.07, top, z, z + 0.08)
	RoadsideBuilder._add(sts, alu, x0, x1, 0.0, 0.08, z, z + 0.08)
	var door := (x0 + x1) * 0.5
	RoadsideBuilder._add(sts, alu, door - 0.95, door + 0.95, 2.25, 2.31, z, z + 0.09)
	for s in [-1.0, 0.0, 1.0]:
		RoadsideBuilder._add(sts, alu, door + s * 0.95 - 0.02, door + s * 0.95 + 0.02, 0.0, 2.25, z, z + 0.09)
	for s in [-1.0, 1.0]:
		RoadsideBuilder._add(sts, brass, door + s * 0.12 - 0.015, door + s * 0.12 + 0.015, 0.85, 1.35, z + 0.09, z + 0.13)
	RoadsideBuilder._add(sts, _pane(b), x0, x1, 0.08, top - 0.07, z + 0.02, z + 0.03)


## What stands in a tower's lobby, from its glass (gz) to its back wall: 0 lifts in a walnut wall,
## 1 a reception desk under a clock, 2 a mosaic wall with a mural, 3 shut for the night.
static func _lobby_room(b: LevelBuilder, sts: Dictionary, x0: float, x1: float, gz: float, back: float, kind: int) -> void:
	var cx := (x0 + x1) * 0.5
	var w := x1 - x0
	var walls := [RoadsideBuilder._glow(b, "lobby_walnut", Color(0.36, 0.21, 0.11), 0.55),
		RoadsideBuilder._glow(b, "lobby_trav", Color(0.85, 0.76, 0.6), 0.6),
		RoadsideBuilder._glow(b, "lobby_mosaic", Color(0.08, 0.4, 0.4), 0.6),
		b._mat("lobby_shut", Color(0.09, 0.1, 0.11), 0.6)]
	var wall: Material = walls[kind]
	var side: Material = b._mat("lobby_shut", Color(0.09, 0.1, 0.11), 0.6) if kind == 3 \
		else RoadsideBuilder._glow(b, "lobby_side", Color(0.6, 0.56, 0.48), 0.3)
	RoadsideBuilder._add(sts, wall, x0, x1, 0.0, FASCIA_Y, back - 0.1, back)
	RoadsideBuilder._add(sts, side, x0, x0 + 0.1, 0.0, FASCIA_Y, back, gz)
	RoadsideBuilder._add(sts, side, x1 - 0.1, x1, 0.0, FASCIA_Y, back, gz)
	var white := white(b)
	var walnut := b._mat("walnut", Color(0.3, 0.17, 0.09), 0.5)
	var lamp := b._neon_mat(Color(1.0, 0.9, 0.72), 2.4)
	var z1 := back + 0.03
	match kind:
		0:
			var bronze := RoadsideBuilder._glow(b, "lift_bronze", Color(0.62, 0.45, 0.24), 0.35)
			var dark := b._mat("lift_gap", Color(0.05, 0.04, 0.03), 0.6)
			var amber := b._neon_mat(Color(1.0, 0.6, 0.15), 3.0)
			var lifts := maxi(1, int((w - 1.0) / 2.2))
			for i in lifts:
				var lx := cx + (i - (lifts - 1) * 0.5) * 2.2
				RoadsideBuilder._add(sts, bronze, lx - 0.6, lx + 0.6, 0.0, 2.25, back, z1)
				RoadsideBuilder._add(sts, dark, lx - 0.01, lx + 0.01, 0.0, 2.25, z1, z1 + 0.005)
				RoadsideBuilder._add(sts, amber, lx - 0.12, lx + 0.12, 2.42, 2.5, back, z1)
			# A planter with a rubber plant by the glass.
			cyl(sts, white, Vector3(x1 - 0.8, 0.0, gz - 0.8), Vector3(x1 - 0.8, 0.5, gz - 0.8), 0.28, 0.36, 10)
			cyl(sts, b._mat("plaza_shrub", Color(0.07, 0.16, 0.08), 0.9), Vector3(x1 - 0.8, 0.5, gz - 0.8), Vector3(x1 - 0.8, 1.9, gz - 0.8), 0.42, 0.1, 8)
		1:
			RoadsideBuilder._add(sts, walnut, cx - 1.2, cx + 1.2, 0.0, 1.02, back + 0.9, back + 1.5)
			RoadsideBuilder._add(sts, white, cx - 1.3, cx + 1.3, 1.02, 1.08, back + 0.85, back + 1.6)
			ball(sts, lamp, Vector3(cx + 0.8, 1.28, back + 1.2), 0.15)
			_clock(b, sts, Vector3(cx - 0.2, 2.35, z1), 0.34)
			# A low sofa under the side wall.
			var teal := b._mat("sofa_teal", Color(0.08, 0.34, 0.36), 0.7)
			RoadsideBuilder._add(sts, teal, x0 + 0.3, x0 + 1.0, 0.18, 0.45, back + 0.5, gz - 0.9)
			RoadsideBuilder._add(sts, teal, x0 + 0.3, x0 + 0.48, 0.45, 0.85, back + 0.5, gz - 0.9)
		2:
			var orange := RoadsideBuilder._glow(b, "mural_orange", Color(0.85, 0.36, 0.1), 0.7)
			var cream := RoadsideBuilder._glow(b, "mural_cream", Color(0.9, 0.84, 0.66), 0.7)
			RoadsideBuilder._add(sts, cream, cx - 1.5, cx - 0.3, 0.9, 2.7, back, z1)
			RoadsideBuilder._add(sts, orange, cx - 0.7, cx + 0.5, 1.4, 2.2, z1, z1 + 0.02)
			cyl(sts, cream, Vector3(cx + 1.0, 2.1, back), Vector3(cx + 1.0, 2.1, z1 + 0.02), 0.45, 0.45, 20)
			RoadsideBuilder._add(sts, white, cx - 1.1, cx + 1.1, 0.3, 0.44, back + 1.0, back + 1.5)
			# A floor lamp with a drum shade.
			cyl(sts, b._mat("chrome", Color(0.82, 0.84, 0.88), 0.12, 1.0), Vector3(x0 + 0.7, 0.0, back + 0.6), Vector3(x0 + 0.7, 1.5, back + 0.6), 0.02)
			cyl(sts, lamp, Vector3(x0 + 0.7, 1.5, back + 0.6), Vector3(x0 + 0.7, 1.85, back + 0.6), 0.2, 0.16, 10)
		3:
			RoadsideBuilder._add(sts, b._mat("lift_gap", Color(0.05, 0.04, 0.03), 0.6), cx - 1.2, cx + 1.2, 0.0, 1.02, back + 0.9, back + 1.5)
			cyl(sts, b._neon_mat(Color(0.6, 0.75, 1.0), 0.8), Vector3(cx, FASCIA_Y - 0.03, back + 1.2), Vector3(cx, FASCIA_Y, back + 1.2), 0.14, 0.14, 10)
	if kind != 3:   # two glowing saucers in the ceiling
		for s in [-0.25, 0.25]:
			cyl(sts, lamp, Vector3(cx + w * s, FASCIA_Y - 0.04, gz - ROOM * 0.5), Vector3(cx + w * s, FASCIA_Y, gz - ROOM * 0.5), 0.3, 0.3, 14)


## A wall clock facing the street: a white dial in a brass rim, its hands at ten past ten.
static func _clock(b: LevelBuilder, sts: Dictionary, at: Vector3, r: float) -> void:
	var brass := b._mat("brass", Color(0.7, 0.55, 0.25), 0.3, 0.8)
	var dark := b._mat("lift_gap", Color(0.05, 0.04, 0.03), 0.6)
	cyl(sts, brass, at, at + Vector3(0, 0, 0.03), r * 1.12, r * 1.12, 20)
	cyl(sts, RoadsideBuilder._glow(b, "clock_face", Color(0.95, 0.93, 0.85), 0.9), at, at + Vector3(0, 0, 0.04), r, r, 20)
	var c := at + Vector3(0, 0, 0.05)
	for hand in [[-1.05, 0.55], [1.05, 0.8]]:
		var tip: Vector3 = c + Vector3(sin(hand[0]), cos(hand[0]), 0.0) * r * float(hand[1])
		cyl(sts, dark, c, tip, r * 0.045, r * 0.03, 4)


## The double-height lobby: glass from the pavement to LOBBY_H a little behind the lot line, and the
## hall behind it: a mezzanine across the back on round columns, pendant lamps in a row, seating, and
## on the back wall a departures board (a terminal, an airline, a travel office) or a clock or mural.
static func _lobby(b: LevelBuilder, x0: float, x1: float, lit: bool, text: String) -> void:
	var sts := {}
	var z := -0.15
	var deep := -LOBBY_DEPTH
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var r := b._lot_hash(x0, "hall")
	var trav := travertine(b)
	var white := white(b)
	var chrome := b._mat("chrome", Color(0.82, 0.84, 0.88), 0.12, 1.0)
	var alu := b._mat("skyway_alu", Color(0.8, 0.82, 0.84), 0.25, 0.85)
	var shut := b._mat("lobby_shut", Color(0.09, 0.1, 0.11), 0.6)
	var backs := [RoadsideBuilder._glow(b, "hall_trav", Color(0.85, 0.75, 0.58), 0.6),
		RoadsideBuilder._glow(b, "hall_teal", Color(0.07, 0.36, 0.37), 0.6),
		RoadsideBuilder._glow(b, "hall_walnut", Color(0.4, 0.23, 0.12), 0.6)]
	var back: Material = backs[r % 3] if lit else shut
	var side: Material = RoadsideBuilder._glow(b, "lobby_side", Color(0.6, 0.56, 0.48), 0.3) if lit else shut
	RoadsideBuilder._add(sts, back, x0, x1, 0.0, LOBBY_H, deep - 0.1, deep)
	RoadsideBuilder._add(sts, terrazzo(b), x0, x1, -0.1, 0.012, deep, z)
	RoadsideBuilder._add(sts, b._mat("tower_soffit", Color(0.7, 0.69, 0.65), 0.8), x0, x1, LOBBY_H - 0.1, LOBBY_H, deep, z)
	RoadsideBuilder._add(sts, side, x0, x0 + 0.1, 0.0, LOBBY_H, deep, z - 0.3)
	RoadsideBuilder._add(sts, side, x1 - 0.1, x1, 0.0, LOBBY_H, deep, z - 0.3)
	for ex in [x0, x1 - 0.22]:   # a travertine pier at each end, pairing with the neighbour's
		RoadsideBuilder._add(sts, trav, ex, ex + 0.22, 0.0, LOBBY_H, z - 0.3, z + 0.15)
	# The mezzanine: a white slab with a glass balustrade under a chrome rail, on two round columns.
	RoadsideBuilder._add(sts, white, x0 + 0.1, x1 - 0.1, 3.7, 4.0, deep, -4.8)
	RoadsideBuilder._add(sts, chrome, x0 + 0.1, x1 - 0.1, 4.95, 5.0, -4.87, -4.82)
	RoadsideBuilder._add(sts, _pane(b), x0 + 0.1, x1 - 0.1, 4.0, 4.95, -4.85, -4.84)
	for s in [-0.3, 0.3]:
		cyl(sts, white, Vector3(cx + w * s, 0.0, -4.4), Vector3(cx + w * s, LOBBY_H - 0.1, -4.4), 0.16, 0.16, 12)
	# Drum pendants on rods, in a row along the hall.
	var lamp := b._neon_mat(Color(1.0, 0.9, 0.72), 2.4 if lit else 0.15)
	var pn := maxi(2, roundi(w / 2.4))
	for i in pn:
		var gx := x0 + w * (i + 0.5) / pn
		var gy := 5.3 + 0.35 * float((r + i) % 2)
		cyl(sts, lamp, Vector3(gx, gy, -2.4), Vector3(gx, gy + 0.36, -2.4), 0.26, 0.2, 12)
		cyl(sts, chrome, Vector3(gx, gy + 0.36, -2.4), Vector3(gx, LOBBY_H - 0.1, -2.4), 0.012, 0.012, 4)
	if lit:
		var z1 := deep + 0.03
		if text.contains("TERMINAL") or text.contains("AIR") or text.contains("TRAVEL") or text.contains("HOLIDAYS"):
			_departures(b, sts, cx, minf(w - 2.0, 5.0), z1)
			_clock(b, sts, Vector3(cx + minf(w * 0.5 - 0.9, 3.4), 6.2, z1), 0.42)
		elif r % 2 == 0:
			_clock(b, sts, Vector3(cx, 5.7, z1), 0.6)
		else:
			var orange := RoadsideBuilder._glow(b, "mural_orange", Color(0.85, 0.36, 0.1), 0.7)
			var cream := RoadsideBuilder._glow(b, "mural_cream", Color(0.9, 0.84, 0.66), 0.7)
			RoadsideBuilder._add(sts, cream, cx - 1.8, cx + 0.2, 4.5, 6.6, deep, z1)
			RoadsideBuilder._add(sts, orange, cx - 0.6, cx + 1.4, 5.0, 6.0, z1, z1 + 0.02)
			cyl(sts, cream, Vector3(cx + 1.5, 6.1, deep), Vector3(cx + 1.5, 6.1, z1 + 0.03), 0.5, 0.5, 20)
		# A counter under the mezzanine, benches out in the hall.
		var walnut := b._mat("walnut", Color(0.3, 0.17, 0.09), 0.5)
		RoadsideBuilder._add(sts, walnut, cx - w * 0.3, cx + w * 0.3, 0.0, 1.05, deep + 1.0, deep + 1.6)
		RoadsideBuilder._add(sts, white, cx - w * 0.3 - 0.1, cx + w * 0.3 + 0.1, 1.05, 1.11, deep + 0.95, deep + 1.7)
		var teal := b._mat("sofa_teal", Color(0.08, 0.34, 0.36), 0.7)
		for s in [-0.25, 0.25]:
			RoadsideBuilder._add(sts, teal, cx + w * s - 0.8, cx + w * s + 0.8, 0.2, 0.44, -2.9, -2.3)
	# The glazing: tall panes between slim mullions, a dark band across them for the sign.
	var n := maxi(2, roundi(w / 2.0))
	for i in n + 1:
		var mx := lerpf(x0 + 0.24, x1 - 0.24, float(i) / n)
		RoadsideBuilder._add(sts, alu, mx - 0.03, mx + 0.03, 0.0, LOBBY_H, z, z + 0.1)
	RoadsideBuilder._add(sts, alu, x0, x1, LOBBY_H - 0.12, LOBBY_H, z - 0.05, z + 0.12)
	RoadsideBuilder._add(sts, alu, x0 + 0.22, x1 - 0.22, 0.0, 0.08, z, z + 0.1)
	RoadsideBuilder._add(sts, b._mat("lobby_band", Color(0.06, 0.07, 0.08), 0.3, 0.6), x0 + 0.22, x1 - 0.22, FASCIA_Y, GROUND_H - 0.05, z - 0.02, z + 0.02)
	RoadsideBuilder._add(sts, alu, x0 + 0.22, x1 - 0.22, FASCIA_Y - 0.04, FASCIA_Y, z, z + 0.1)
	RoadsideBuilder._add(sts, _pane(b), x0 + 0.22, x1 - 0.22, 0.08, LOBBY_H - 0.12, z + 0.03, z + 0.04)
	_commit(b, sts)
	if lit:
		b.lit_windows.append([Vector3(cx, 2.5, -1.6), Color(1.0, 0.86, 0.66)])


## A departures board `w` wide on a hall's back wall: a black board, rows of amber and white lines.
static func _departures(b: LevelBuilder, sts: Dictionary, cx: float, w: float, z: float) -> void:
	RoadsideBuilder._add(sts, b._mat("lift_gap", Color(0.05, 0.04, 0.03), 0.6), cx - w * 0.5, cx + w * 0.5, 4.5, 6.7, z - 0.03, z + 0.02)
	var amber := b._neon_mat(Color(1.0, 0.66, 0.2), 2.0)
	var pale := b._neon_mat(Color(0.85, 0.92, 1.0), 1.4)
	for row in 7:
		var y := 6.42 - row * 0.28
		var r := b._lot_hash(cx + row, "board")
		RoadsideBuilder._add(sts, pale, cx - w * 0.46, cx - w * (0.12 + 0.1 * float(r % 3)), y, y + 0.1, z + 0.02, z + 0.03)
		RoadsideBuilder._add(sts, amber, cx + w * 0.05, cx + w * (0.2 + 0.05 * float(r % 4)), y, y + 0.1, z + 0.02, z + 0.03)
		RoadsideBuilder._add(sts, pale, cx + w * 0.38, cx + w * 0.46, y, y + 0.1, z + 0.02, z + 0.03)


# --- visuals: plaza -------------------------------------------------------------------------------

## Travertine paving back to the tower and, by the lot, a pool with a lit rim, a chrome spire or a
## clipped tree in a planter; globe lamps toward the street. Kept spare: the view is the point.
static func _plaza(b: LevelBuilder, x: float, w: float) -> void:
	var sts := {}
	var cx := x + w * 0.5
	var r := b._lot_hash(x, "plaza")
	var trav := travertine(b)
	var chrome := b._mat("chrome", Color(0.82, 0.84, 0.88), 0.12, 1.0)
	RoadsideBuilder._add(sts, b._mat("plaza_paving", Color(0.62, 0.59, 0.54), 0.2), x, x + w, -0.3, 0.004, -SET_BACK, 0.0)
	var joint := b._mat("plaza_joint", Color(0.36, 0.34, 0.31), 0.5)
	var jz := -2.0
	while jz > -SET_BACK:
		RoadsideBuilder._add(sts, joint, x, x + w, 0.0, 0.01, jz - 0.02, jz + 0.02)
		jz -= 2.0
	RoadsideBuilder._add(sts, joint, cx - 0.02, cx + 0.02, 0.0, 0.01, -SET_BACK, 0.0)
	var feature := r % 3 if w >= 5.5 else 2
	match feature:
		0:   # a long pool, dark water inside a travertine kerb, a line of light under its rim
			var half := minf(w * 0.5 - 1.2, 2.2)
			RoadsideBuilder._add(sts, trav, cx - half - 0.2, cx + half + 0.2, 0.0, 0.3, -12.2, -4.8)
			RoadsideBuilder._add(sts, b._mat("pool_water", Color(0.02, 0.05, 0.06), 0.03, 0.7), cx - half, cx + half, 0.3, 0.305, -12.0, -5.0)
			RoadsideBuilder._add(sts, b._neon_mat(Color(0.35, 0.95, 1.0), 2.2), cx - half - 0.2, cx + half + 0.2, 0.05, 0.08, -4.8, -4.77)
		1:   # a chrome spire on a travertine drum, a red light at its tip
			cyl(sts, trav, Vector3(cx, 0.0, -7.0), Vector3(cx, 0.5, -7.0), 0.9, 0.9, 16)
			cyl(sts, chrome, Vector3(cx, 0.5, -7.0), Vector3(cx, 11.0, -7.0), 0.16, 0.02, 10)
			for ring in [3.2, 5.4]:
				cyl(sts, chrome, Vector3(cx, ring, -7.0), Vector3(cx, ring + 0.05, -7.0), 0.5 - ring * 0.05, 0.5 - ring * 0.05, 16)
			cyl(sts, b._neon_mat(Color(1.0, 0.15, 0.1), 4.0), Vector3(cx, 11.0, -7.0), Vector3(cx, 11.12, -7.0), 0.06, 0.06, 8)
		2:   # a round planter and a clipped tree
			var shrub := b._mat("plaza_shrub", Color(0.07, 0.16, 0.08), 0.9)
			cyl(sts, trav, Vector3(cx, 0.0, -5.5), Vector3(cx, 0.55, -5.5), 0.75, 0.85, 14)
			cyl(sts, b._mat("walnut", Color(0.3, 0.17, 0.09), 0.5), Vector3(cx, 0.55, -5.5), Vector3(cx, 2.0, -5.5), 0.07, 0.05, 6)
			cyl(sts, shrub, Vector3(cx, 1.9, -5.5), Vector3(cx, 3.0, -5.5), 0.75, 0.95, 10)
			cyl(sts, shrub, Vector3(cx, 3.0, -5.5), Vector3(cx, 3.9, -5.5), 0.95, 0.4, 10)
	# Globe lamps on slim posts either side, set back from the pavement, and one light between them.
	var post := b._mat("skyway_alu", Color(0.8, 0.82, 0.84), 0.25, 0.85)
	var globe := b._neon_mat(Color(1.0, 0.93, 0.8), 2.0)
	for lx in [x + 0.7, x + w - 0.7]:
		cyl(sts, post, Vector3(lx, 0.0, -1.2), Vector3(lx, 2.3, -1.2), 0.035, 0.025, 6)
		ball(sts, globe, Vector3(lx, 2.46, -1.2), 0.19)
	_commit(b, sts)
	var om := OmniLight3D.new()
	om.light_color = Color(1.0, 0.9, 0.74)
	om.light_energy = 1.6
	om.omni_range = 7.0
	om.light_volumetric_fog_energy = 0.5
	om.position = Vector3(cx, 2.6, -1.4)
	b.root.add_child(om)


# --- visuals: side streets and the skyline --------------------------------------------------------

## The flank of a lot down a side street or beside a plaza: face in the plane x, facing +X (or -X),
## `depth` deep. A tower's is glass over a travertine base with lit shop windows; any other
## building's (`glass` false) a plain dark wall.
static func side_wall(b: LevelBuilder, x: float, floors: int, facing: float, glass := true, depth := FLANK) -> void:
	if String(_neighbour(b, x, facing).get("style", "")) == "plaza":
		return   # a plaza is open to the side street beside it
	var h := GROUND_H + STOREY * maxi(floors, 0)
	var mass := b._mat("tower_mass", Color(0.05, 0.06, 0.07), 0.6, 0.3)
	var fx := x + facing * 0.02
	if not glass:
		b._box(Vector3(0.3, h, depth), Vector3(x - facing * 0.13, h * 0.5, -depth * 0.5 - 0.3),
			RoadsideBuilder._textured(b, "flank_plaster", "plaster", Color(0.5, 0.47, 0.43)))
		var lit := {}
		var warm := RoadsideBuilder._glow(b, "flank_window", Color(0.8, 0.68, 0.48), 0.5)
		for i in 5:
			var r := b._lot_hash(x + i * 1.7, "flank_lit")
			var wy := GROUND_H + STOREY * float(r % maxi(floors, 1)) + 1.0
			var wz0 := -2.5 - float((r >> 3) % 9) * 2.2
			RoadsideBuilder._add(lit, warm, minf(fx, fx + facing * 0.04), maxf(fx, fx + facing * 0.04), wy, wy + 1.5, wz0 - 1.1, wz0)
		_commit(b, lit)
		return
	b._box(Vector3(0.5, h - GROUND_H, depth), Vector3(x - facing * 0.3, (h + GROUND_H) * 0.5, -depth * 0.5 - 0.3), mass)
	var st := _curtain_st()
	var seed := float(b._lot_hash(x, "side") % 997) / 997.0
	curtain(st, Vector3(fx, GROUND_H, -0.3), Vector3(fx, h, -depth), Vector3(facing, 0, 0),
		seed, 0.34, PALETTES[b._lot_hash(x - facing * 0.5, "flank") % PALETTES.size()], 1.0, GROUND_H)
	_commit_curtain(b, st)
	var sts := {}
	var xa := minf(x, x + facing * 0.08)
	RoadsideBuilder._add(sts, travertine(b), xa - 0.3 * maxf(facing, 0.0), xa + 0.08 + 0.3 * maxf(-facing, 0.0), 0.0, GROUND_H, -depth, -0.3)
	# Shop windows let into the base, lit.
	var win := RoadsideBuilder._glow(b, "flank_window", Color(0.8, 0.68, 0.48), 0.5)
	var bar := b._mat("lift_gap", Color(0.05, 0.04, 0.03), 0.6)
	var wz := -3.0
	while wz > -depth + 5.0:
		RoadsideBuilder._add(sts, win, minf(x, x + facing * 0.1), maxf(x, x + facing * 0.1), 0.5, 2.7, wz - 3.2, wz)
		for k in 3:
			RoadsideBuilder._add(sts, bar, minf(x, x + facing * 0.12), maxf(x, x + facing * 0.12), 0.5, 2.7, wz - 0.03 - 1.6 * k, wz - 1.6 * k)
		wz -= 5.5
	_commit(b, sts)


## Low glass blocks across the far end of a side street: the skyline stands over them.
static func far_facade(b: LevelBuilder, x0: float, x1: float, z: float) -> void:
	var st := _curtain_st()
	var mass := b._mat("tower_mass", Color(0.05, 0.06, 0.07), 0.6, 0.3)
	var fx := x0 - 6.0
	while fx < x1 + 6.0:
		var r := b._lot_hash(fx, "far")
		var fw := 8.0 + float(r % 7)
		var fh := GROUND_H + STOREY * float(2 + r % 4)
		b._box(Vector3(fw, fh, 6.0), Vector3(fx + fw * 0.5, fh * 0.5, z - 3.0), mass)
		curtain(st, Vector3(fx + 0.1, GROUND_H, z + 0.02), Vector3(fx + fw - 0.1, fh, z + 0.02), Vector3.BACK,
			float(r % 991) / 991.0, 0.34, PALETTES[r % PALETTES.size()], 0.7, GROUND_H)
		fx += fw + 0.4
	_commit_curtain(b, st)


## Skyscrapers behind the street in the SKYLINE rows, each row paler in the haze than the one in
## front, windows lit, a setback or a mast on some, red warning lights on the tall ones; and behind
## them all the glow the city throws up into the rain. Seeded by the level id, so a street always
## shows the same skyline. Two meshes (the towers' faces, the lights) and the glow.
static func skyline(b: LevelBuilder) -> void:
	var L: float = b.data["length"]
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(b.data.get("id", "level")) + ":skyline")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lights := SurfaceTool.new()
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: Array in SKYLINE:
		var z: float = row[0]
		var haze: float = row[3]
		var x := -90.0 + r.randf() * 10.0
		while x < L + 90.0:
			var w := r.randf_range(11.0, 24.0) * (1.0 - z / 300.0)
			var h := lerpf(row[1], row[2], pow(r.randf(), 1.6))
			var d := r.randf_range(12.0, 20.0)
			var look := Color(r.randf(), r.randf_range(0.2, 0.55), haze, float(r.randi() % 3) * 0.5)
			_block(st, x, x + w, 0.0, h, z, d, look)
			var top := h
			if r.randf() < 0.4:   # a setback: a narrower block on top
				var w2 := w * r.randf_range(0.45, 0.7)
				var x2 := x + (w - w2) * r.randf()
				top = h + r.randf_range(8.0, 22.0)
				_block(st, x2, x2 + w2, h, top, z - 2.0, d * 0.7, look)
			var mast := r.randf() < 0.3
			if mast:
				_block(st, x + w * 0.5 - 0.3, x + w * 0.5 + 0.3, top, top + 16.0, z - 3.0, 0.6, Color(look.r, 0.0, haze, 0.0))
				top += 16.0
			if mast or r.randf() < 0.45:
				_light(lights, Vector3(x + w * 0.5, top + 0.6, z - 3.0), r.randf(), 0.9 - z / 110.0, false)
			elif r.randf() < 0.5:   # or a steady one at each front corner
				for cx in [x + 0.4, x + w - 0.4]:
					_light(lights, Vector3(cx, h + 0.3, z + 0.1), 0.0, 0.5 - z / 180.0, true)
			x += w + r.randf_range(1.0, 10.0)
	_commit_shader(b, st, "skyline", "res://src/fx/skyline.gdshader")
	_commit_shader(b, lights, "beacon", "res://src/fx/beacon.gdshader").extra_cull_margin = 4.0
	# The city's glow behind them: palest at the ground, gone into the night sky at the top.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.vertex_color_use_as_albedo = true
	glow.disable_fog = true
	var gs := SurfaceTool.new()
	gs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gz := -190.0
	var bands := [[-20.0, Color(0.2, 0.2, 0.27, 1.0)], [25.0, Color(0.17, 0.18, 0.26, 1.0)], [70.0, Color(0.11, 0.13, 0.2, 0.8)], [150.0, Color(0.06, 0.08, 0.13, 0.0)]]
	for i in bands.size() - 1:
		var y0: float = bands[i][0]
		var y1: float = bands[i + 1][0]
		var c0: Color = bands[i][1]
		var c1: Color = bands[i + 1][1]
		for v: Array in [[-260.0, y0, c0], [L + 260.0, y1, c1], [L + 260.0, y0, c0], [-260.0, y0, c0], [-260.0, y1, c1], [L + 260.0, y1, c1]]:
			gs.set_color(v[2])
			gs.set_normal(Vector3.BACK)
			gs.add_vertex(Vector3(v[0], v[1], gz))
	var gm := MeshInstance3D.new()
	gm.mesh = gs.commit()
	gm.material_override = glow
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.root.add_child(gm)


## One skyscraper block from x0 to x1 and y0 to y1, its street face at z, d deep: the face and both
## flanks (no roof: nothing looks down on it).
static func _block(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, z: float, d: float, look: Color) -> void:
	_face(st, Vector3(x0, y0, z), Vector3(x1, y1, z), Vector3.BACK, look, 1.0)
	var flank := Color(fmod(look.r + 0.37, 1.0), look.g * 0.8, look.b, look.a)
	_face(st, Vector3(x1, y0, z), Vector3(x1, y1, z - d), Vector3.RIGHT, flank, 0.6)
	_face(st, Vector3(x0, y0, z - d), Vector3(x0, y1, z), Vector3.LEFT, flank, 0.6)


## A wall from corner a (bottom) to corner c (top), facing nrm, for skyline.gdshader.
static func _face(st: SurfaceTool, a: Vector3, c: Vector3, nrm: Vector3, look: Color, shade: float) -> void:
	var p := [a, Vector3(c.x, a.y, c.z), c, Vector3(a.x, c.y, a.z)]
	var along := Vector3.UP.cross(nrm)
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_color(look)
		st.set_normal(nrm)
		st.set_uv(Vector2(p[i].dot(along), p[i].y))
		st.set_uv2(Vector2(shade, 0.0))
		st.add_vertex(p[i])


## One warning light for beacon.gdshader: a quad whose corners all sit at `at` (the shader spreads
## them toward the camera), `size` metres across.
static func _light(st: SurfaceTool, at: Vector3, phase: float, size: float, steady: bool) -> void:
	for uv: Vector2 in [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]:
		st.set_color(Color(phase, clampf(size / 8.0, 0.0, 1.0), 1.0 if steady else 0.0))
		st.set_normal(Vector3.BACK)
		st.set_uv(uv)
		st.add_vertex(at)


# --- helpers ----------------------------------------------------------------------------------------

## Lit capitals on the fascia: white letters, evenly spaced, that read from across the street at night.
static func sign_text(b: LevelBuilder, cx: float, y: float, z: float, text: String, max_w: float) -> void:
	if text.strip_edges().is_empty():
		return
	if not b._mats.has("modern_font"):
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Barlow-SemiBold.ttf") if ResourceLoader.exists("res://assets/fonts/Barlow-SemiBold.ttf") else b.sign_font
		fv.spacing_glyph = 6
		b._mats["modern_font"] = fv
	var tm := TextMesh.new()
	tm.text = text.to_upper()
	tm.font = b._mats["modern_font"]
	tm.font_size = 64
	tm.pixel_size = 0.0056
	tm.depth = 0.05
	var est := text.length() * (64.0 * 0.6 + 6.0) * tm.pixel_size
	if est > max_w:
		tm.pixel_size *= max_w / est
	var face := b._mat("sign_lit", Color(0.95, 0.95, 0.9), 0.4)
	face.emission_enabled = true
	face.emission = Color(1.0, 0.96, 0.86)
	face.emission_energy_multiplier = 1.5
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = face
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(cx, y, z + 0.05)
	b.root.add_child(mi)


## Travertine and white-painted concrete, each lifted a little so it stays pale in the shade at night.
static func travertine(b: LevelBuilder) -> Material:
	return _pale(b, "travertine", Color(0.84, 0.78, 0.66), 0.12)


static func white(b: LevelBuilder) -> Material:
	return _pale(b, "skyway_white", Color(0.9, 0.9, 0.86), 0.1)


static func _pale(b: LevelBuilder, key: String, col: Color, lift: float) -> Material:
	var m := b._mat(key, col, 0.5)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = lift
	return m


static func terrazzo(b: LevelBuilder) -> Material:
	return b._mat("terrazzo", Color(0.56, 0.53, 0.48), 0.22)


## The enamel of a tower's fascia, in its palette's colour.
static func _enamel(b: LevelBuilder, pal: int) -> Material:
	return b._mat("fascia_%d" % pal, FASCIA[pal], 0.3, 0.2)


## Plate glass for lobbies and balustrades, out of the rain: a faint blue-green tint and a sheen.
static func _pane(b: LevelBuilder) -> Material:
	if not b._mats.has("lobby_pane"):
		var m := ShaderMaterial.new()
		m.shader = load("res://src/fx/skyway_glass.gdshader")
		m.set_shader_parameter("tint", Color(0.4, 0.62, 0.62, 0.1))
		m.set_shader_parameter("rain", 0.0)
		b._mats["lobby_pane"] = m
	return b._mats["lobby_pane"]


## A round bar from a to c (radius r0 at a, r1 at c) in the batch: columns, lamps, dials, spires.
static func cyl(sts: Dictionary, mat: Material, a: Vector3, c: Vector3, r0: float, r1 := -1.0, n := 12) -> void:
	if r1 < 0.0:
		r1 = r0
	var st := RailwayBuilder._st(sts, mat)
	var axis := (c - a).normalized()
	var u := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.UP).normalized()
	var v := axis.cross(u)
	for i in n:
		var d0 := u * cos(TAU * i / n) + v * sin(TAU * i / n)
		var d1 := u * cos(TAU * (i + 1) / n) + v * sin(TAU * (i + 1) / n)
		var nrm := (d0 + d1).normalized()
		ViaductBuilder._tri(st, a + d0 * r0, c + d0 * r1, c + d1 * r1, nrm)
		ViaductBuilder._tri(st, a + d0 * r0, c + d1 * r1, a + d1 * r0, nrm)
		ViaductBuilder._tri(st, a, a + d0 * r0, a + d1 * r0, -axis)
		ViaductBuilder._tri(st, c, c + d0 * r1, c + d1 * r1, axis)


## A ball in the batch (lamp globes: drawn unshaded, so its facets don't show).
static func ball(sts: Dictionary, mat: Material, c: Vector3, r: float, n := 12, rings := 6) -> void:
	var st := RailwayBuilder._st(sts, mat)
	var at := func(j: int, i: int) -> Vector3:
		var t := PI * j / rings
		return Vector3(sin(t) * cos(TAU * i / n), cos(t), sin(t) * sin(TAU * i / n))
	for j in rings:
		for i in n:
			var q: Array = [at.call(j, i), at.call(j, i + 1), at.call(j + 1, i + 1), at.call(j + 1, i)]
			var nrm: Vector3 = (q[0] + q[1] + q[2] + q[3]).normalized()
			ViaductBuilder._tri(st, c + q[0] * r, c + q[1] * r, c + q[2] * r, nrm)
			ViaductBuilder._tri(st, c + q[0] * r, c + q[2] * r, c + q[3] * r, nrm)


static func _curtain_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## One curtain wall from corner a to corner c in a plane facing `nrm` (+Z, or ±X for a side wall),
## its look passed to curtain_wall.gdshader in the vertices.
static func curtain(st: SurfaceTool, a: Vector3, c: Vector3, nrm: Vector3, seed: float, lit: float, pal: int,
		detail: float, floor0: float, floor_h := STOREY) -> void:
	var col := Color(seed, lit, pal / 4.0, detail)
	var along := Vector3.UP.cross(nrm)   # the way the wall runs to the right of someone facing it
	var corners: Array = [Vector3(a.x, a.y, a.z), Vector3(c.x, a.y, c.z), Vector3(c.x, c.y, c.z), Vector3(a.x, c.y, a.z)]
	var order := [0, 2, 1, 0, 3, 2] if (nrm.z > 0.0 or nrm.x > 0.0) else [0, 1, 2, 0, 2, 3]
	for i in order:
		var p: Vector3 = corners[i]
		st.set_color(col)
		st.set_normal(nrm)
		st.set_uv(Vector2(p.dot(along), p.y))
		st.set_uv2(Vector2(floor0, floor_h))
		st.add_vertex(p)


static func _commit_curtain(b: LevelBuilder, st: SurfaceTool) -> void:
	_commit_shader(b, st, "curtain_wall", "res://src/fx/curtain_wall.gdshader")


static func _commit_shader(b: LevelBuilder, st: SurfaceTool, key: String, path: String) -> MeshInstance3D:
	if not b._mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(path)
		b._mats[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = b._mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.root.add_child(mi)
	return mi


## Adds a batch (material -> SurfaceTool) to the street, one mesh a material. Glass and anything
## that glows casts no shadow.
static func _commit(b: LevelBuilder, sts: Dictionary) -> void:
	for mat: Material in sts:
		var mi := MeshInstance3D.new()
		mi.mesh = (sts[mat] as SurfaceTool).commit()
		mi.material_override = mat
		var sm := mat as StandardMaterial3D
		if sm == null or sm.emission_enabled:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.root.add_child(mi)
