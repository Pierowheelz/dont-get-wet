class_name RoadsideBuilder
extends RefCounted
## Static geometry for a roadside strip, called from LevelBuilder like the railway's:
##   motel        a row of motel rooms, doors and curtained windows, a storey per floor (lot style `motel`)
##   walkway      an open walkway along the upper floor whose slab roofs the one along the ground-floor
##                rooms (lot cover `walkway`: cover over z 0..WALK_DEPTH at WALK_Y).
##   forecourt    an open concrete apron with painted bays and a low building set well back from the
##                street, signed (lot style `forecourt`, no cover).
##   billboard    a lit hoarding on two posts behind the lot line (prop `billboard`, `text`).
##   pylon_sign   a tall lit box sign on a pole (prop `pylon_sign`, `text`).
## Runs inside LevelBuilder.build, possibly on a worker thread: it only adds nodes.

const WALK_Y := 3.0          # top of the walkway slab (the upper floor's walkway, the lower one's roof)
const WALK_DEPTH := 2.4
const STOREY := 3.1
const ROOM_W := 3.6
const DOOR_COLORS := [Color(0.1, 0.42, 0.44), Color(0.72, 0.36, 0.1)]
const SET_BACK := 10.0       # how far behind the lot line a forecourt's building stands


static func motel(b: LevelBuilder, x: float, w: float, floors: int) -> void:
	var storeys := maxi(floors, 0) + 1
	var h := storeys * STOREY + 0.5
	b._box(Vector3(w, h, 8.0), Vector3(x + w * 0.5, h * 0.5, -4.0), b._mat("motel_wall", Color(0.74, 0.69, 0.58), 0.85))
	_wall_face(b, _textured(b, "motel_stucco", "plaster", Color(0.98, 0.9, 0.75)), x, x + w, 0.0, h, 0.004)
	var sts := {}
	var trim := b._mat("motel_trim", Color(0.86, 0.84, 0.78), 0.6)
	_add(sts, trim, x - 0.05, x + w + 0.05, h - 0.4, h, -0.15, 0.35)
	_add(sts, b._mat("motel_base", Color(0.4, 0.36, 0.31), 0.8), x, x + w, 0.0, 0.32, 0.0, 0.03)
	var n := maxi(1, roundi(w / ROOM_W))
	var rw := w / n
	var door_col: Color = DOOR_COLORS[b._lot_hash(x, "motel") % DOOR_COLORS.size()]
	var door := b._mat("motel_door_%d" % DOOR_COLORS.find(door_col), door_col, 0.5)
	var number := 1 + b._lot_hash(x, "rooms") % 20
	for s in storeys:
		var y0 := s * STOREY + (WALK_Y - STOREY + 0.11 if s > 0 else 0.0)
		for i in n:
			var rx := x + i * rw
			_room(b, sts, rx, rw, y0, door, number)
			number += 1
		# A shallow pier on each party wall, so the row reads as rooms and not one long wall.
		for i in n + 1:
			var px := clampf(x + i * rw, x + 0.09, x + w - 0.09)
			_add(sts, trim, px - 0.09, px + 0.09, y0, y0 + STOREY - 0.2, 0.0, 0.05)
	_commit(b, sts)


## The walkway along a motel's rooms: the upper floor's slab (railing on top) roofs the lower walkway
## and is cover; steel posts hold it up at its front edge, one between each pair of rooms.
static func walkway(b: LevelBuilder, x: float, w: float) -> void:
	b._build_slab(x, w, WALK_Y, WALK_DEPTH, false)
	var steel := b._mat("motel_post", Color(0.2, 0.2, 0.21), 0.5, 0.6)
	var n := maxi(1, roundi(w / ROOM_W))
	for i in n + 1:
		var px := clampf(x + i * w / n, x + 0.1, x + w - 0.1)
		b._box(Vector3(0.1, WALK_Y, 0.1), Vector3(px, WALK_Y * 0.5, WALK_DEPTH - 0.18), steel)


## One room: a framed door with its number, stepped lights and a kick plate, a bulkhead lamp beside
## it, and a sliding window whose curtains hang in folds, lit or drawn dark, over a wall air conditioner.
static func _room(b: LevelBuilder, sts: Dictionary, rx: float, rw: float, y0: float, door: Material, number: int) -> void:
	var trim := b._mat("motel_trim", Color(0.86, 0.84, 0.78), 0.6)
	var alu := b._mat("motel_alu", Color(0.55, 0.56, 0.58), 0.35, 0.8)
	var dark := b._mat("motel_dark", Color(0.05, 0.05, 0.055), 0.4, 0.3)
	var dx := rx + rw * 0.28
	_add(sts, trim, dx - 0.54, dx + 0.54, y0, y0 + 2.2, 0.0, 0.05)
	_add(sts, door, dx - 0.46, dx + 0.46, y0 + 0.02, y0 + 2.12, 0.0, 0.085)
	_add(sts, alu, dx - 0.42, dx + 0.42, y0 + 0.06, y0 + 0.26, 0.085, 0.092)
	_add(sts, b._mat("brass", Color(0.7, 0.55, 0.25), 0.3, 0.8), dx + 0.31, dx + 0.37, y0 + 0.97, y0 + 1.03, 0.085, 0.14)
	for k in 3:   # three small lights stepped down the door
		var lx := dx - 0.22 + k * 0.17
		var ly := y0 + 1.72 - k * 0.2
		_add(sts, dark, lx - 0.06, lx + 0.06, ly - 0.06, ly + 0.06, 0.085, 0.09)
	var lbl := Label3D.new()
	lbl.text = str(number)
	lbl.font_size = 64
	lbl.pixel_size = 0.004
	if b.sign_font:
		lbl.font = b.sign_font
	lbl.modulate = Color(0.85, 0.8, 0.6)
	lbl.position = Vector3(dx, y0 + 2.4, 0.03)
	lbl.double_sided = false
	b.root.add_child(lbl)
	var lit := b.rng.randf() < 0.3
	var wx := rx + rw * 0.68
	var folds: Array
	if lit:
		folds = [_glow(b, "curtain_lit", Color(1.0, 0.68, 0.36), 1.0), _glow(b, "curtain_lit_fold", Color(1.0, 0.63, 0.31), 0.8)]
	else:
		folds = [b._mat("curtain_dark", Color(0.18, 0.13, 0.1), 0.7), b._mat("curtain_dark_fold", Color(0.11, 0.08, 0.065), 0.7)]
	_add(sts, alu, wx - 0.77, wx + 0.77, y0 + 0.98, y0 + 2.14, 0.0, 0.05)
	var fx := wx - 0.7
	var k := 0
	while fx < wx + 0.7 - 0.001:
		_add(sts, folds[k % 2], fx, fx + 0.1, y0 + 1.04, y0 + 2.08, 0.0, 0.058 if k % 2 == 0 else 0.054)
		fx += 0.1
		k += 1
	_add(sts, alu, wx - 0.025, wx + 0.025, y0 + 1.04, y0 + 2.08, 0.0, 0.07)
	_add(sts, trim, wx - 0.84, wx + 0.84, y0 + 0.92, y0 + 0.99, 0.0, 0.13)
	# The air conditioner through the wall under the window.
	_add(sts, alu, wx - 0.34, wx + 0.34, y0 + 0.36, y0 + 0.78, 0.0, 0.16)
	for g in 5:
		_add(sts, dark, wx - 0.28, wx + 0.28, y0 + 0.42 + g * 0.065, y0 + 0.455 + g * 0.065, 0.16, 0.165)
	# A bulkhead lamp by the door, under the walkway.
	_add(sts, dark, dx + 0.66, dx + 0.84, y0 + 2.32, y0 + 2.5, 0.0, 0.05)
	_add(sts, b._neon_mat(Color(1.0, 0.82, 0.55), 1.4), dx + 0.69, dx + 0.81, y0 + 2.35, y0 + 2.47, 0.05, 0.12)
	if lit:
		b.lit_windows.append([Vector3(wx, y0 + 1.6, -0.8), Color(1.0, 0.68, 0.38)])


## An open apron of concrete with painted bays, and a low building SET_BACK behind the lot line.
static func forecourt(b: LevelBuilder, x: float, w: float, lot: Dictionary) -> void:
	# The apron is the same rain-soaked tarmac as the road, so the floodlight lies across it in the wet.
	var apron := b._material_res("asphalt_wet", b._mat("forecourt", Color(0.3, 0.3, 0.29), 0.35))
	b._box(Vector3(w, 0.3, SET_BACK + 2.0), Vector3(x + w * 0.5, -0.15, -(SET_BACK + 2.0) * 0.5), apron)
	var sts := {}
	var paint := b._mat("bay_paint", Color(0.62, 0.6, 0.53), 0.5)
	var bx := x + 1.0
	while bx < x + w - 0.5:
		_add(sts, paint, bx - 0.05, bx + 0.05, 0.0, 0.012, -5.85, -1.35)
		bx += 2.6
	var bw := maxf(w - 1.6, 3.0)
	var bh := 4.2
	var cx := x + w * 0.5
	var fz := -SET_BACK
	b._box(Vector3(bw, bh, 6.0), Vector3(cx, bh * 0.5, fz - 3.0), b._mat("forecourt_wall", Color(0.46, 0.42, 0.36), 0.85))
	_wall_face(b, _textured(b, "forecourt_render", "concrete", Color(0.62, 0.57, 0.5)), cx - bw * 0.5, cx + bw * 0.5, 0.0, bh, fz + 0.004)
	_add(sts, b._mat("forecourt_fascia", Color(0.62, 0.15, 0.12), 0.6), cx - bw * 0.5 - 0.2, cx + bw * 0.5 + 0.2, bh - 0.35, bh + 0.15, fz - 0.4, fz + 1.0)
	var shut := not bool(lot.get("lit", false))
	# The shop window: a run of plate glass in aluminium bars over a tiled stall riser, a door at one end.
	var alu := b._mat("motel_alu", Color(0.55, 0.56, 0.58), 0.35, 0.8)
	var glass: Material = b._mat("glass_dark", Color(0.03, 0.035, 0.04), 0.05, 0.3) if shut else _glow(b, "showroom_lit", Color(0.5, 0.66, 0.74), 0.45)
	var g0 := cx - bw * 0.5 + 0.6
	var g1 := cx + bw * 0.5 - 0.6
	_add(sts, glass, g0, g1, 0.7, 2.5, fz, fz + 0.04)
	_add(sts, b._mat("forecourt_riser", Color(0.2, 0.25, 0.24), 0.4), g0 - 0.05, g1 + 0.05, 0.0, 0.7, fz, fz + 0.07)
	_add(sts, alu, g0 - 0.05, g1 + 0.05, 2.5, 2.58, fz, fz + 0.09)
	_add(sts, alu, g0 - 0.05, g1 + 0.05, 0.68, 0.74, fz, fz + 0.09)
	var panes := maxi(2, roundi((g1 - g0) / 1.7))
	for i in panes + 1:
		var mx := lerpf(g0, g1, float(i) / panes)
		_add(sts, alu, mx - 0.03, mx + 0.03, 0.7, 2.5, fz, fz + 0.09)
	var door_x := lerpf(g0, g1, (panes - 0.5) / panes)
	_add(sts, alu, door_x - 0.5, door_x + 0.5, 0.0, 2.2, fz + 0.04, fz + 0.1)
	_add(sts, glass, door_x - 0.42, door_x + 0.42, 0.25, 2.1, fz + 0.1, fz + 0.11)
	if not shut:
		# What the lit window shows from the road: a counter and the strip lights over it.
		_add(sts, b._mat("showroom_counter", Color(0.12, 0.1, 0.09), 0.7), g0 + 0.4, door_x - 0.9, 0.7, 1.3, fz + 0.04, fz + 0.07)
		var tube := b._neon_mat(Color(0.9, 0.97, 1.0), 1.6)
		for i in panes:
			var tx := lerpf(g0, g1, (i + 0.5) / panes)
			_add(sts, tube, tx - 0.5, tx + 0.5, 2.3, 2.38, fz + 0.04, fz + 0.07)
	_commit(b, sts)
	if lot.has("sign"):
		var lbl := Label3D.new()
		lbl.text = String(lot["sign"])
		lbl.pixel_size = 0.006
		if b.sign_font:
			lbl.font = b.sign_font
		lbl.font_size = int(clampf((bw - 0.8) / 0.006 / maxf(1.0, lbl.text.length() * 0.62), 40.0, 120.0))
		lbl.modulate = Color(0.5, 0.45, 0.38) if shut else Color(1.0, 0.85, 0.55)
		lbl.shaded = shut
		lbl.position = Vector3(cx, bh - 0.1, fz + 1.02)
		lbl.double_sided = false
		b.root.add_child(lbl)
	if lot.has("note"):
		var note := Label3D.new()
		note.text = String(lot["note"])
		note.font_size = 48
		note.pixel_size = 0.005
		note.modulate = Color(0.8, 0.75, 0.65)
		note.shaded = true
		note.position = Vector3(cx - bw * 0.25, 1.9, fz + 0.08)
		note.double_sided = false
		b.root.add_child(note)
	b._box(Vector3(w + 6.0, 9.0, 1.0), Vector3(cx, 4.5, fz - 8.0), b._mat("farwall", Color(0.22, 0.2, 0.19), 0.9))
	_floodlight(b, x + 0.5, -0.8, Color(1.0, 0.78, 0.5) if shut else Color(0.92, 0.95, 1.0))


## A lamp on a tall pole at the front corner of a forecourt, thrown back across the apron.
static func _floodlight(b: LevelBuilder, x: float, z: float, col: Color) -> void:
	var steel := b._mat("pylon_steel", Color(0.75, 0.74, 0.7), 0.4, 0.6)
	b._box(Vector3(0.14, 6.0, 0.14), Vector3(x, 3.0, z), steel)
	b._box(Vector3(0.6, 0.14, 0.3), Vector3(x + 0.2, 6.0, z - 0.1), steel)
	var lamp := b._neon_mat(col, 2.2)
	b._box(Vector3(0.5, 0.06, 0.24), Vector3(x + 0.2, 5.92, z - 0.1), lamp).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sl := SpotLight3D.new()
	sl.light_color = col
	sl.light_energy = 6.0
	sl.spot_range = 16.0
	sl.spot_angle = 55.0
	sl.spot_attenuation = 0.7
	sl.shadow_enabled = false
	sl.light_volumetric_fog_energy = 1.2
	sl.position = Vector3(x + 0.2, 5.85, z - 0.1)
	sl.rotation = Vector3(-PI * 0.5 + 0.45, -0.5, 0)
	b.root.add_child(sl)


## A hoarding on two steel posts, low enough to read under the street's camera, its face lit by two lamps on arms: `text`, one line per "\n".
static func billboard(b: LevelBuilder, x: float, text: String, z := -3.0) -> void:
	var steel := b._mat("hoarding_steel", Color(0.16, 0.16, 0.17), 0.55, 0.6)
	var bw := 10.0
	var y0 := 2.5
	var bh := 3.2
	for dx in [-3.2, 3.2]:
		b._box(Vector3(0.3, y0 + 0.2, 0.3), Vector3(x + dx, (y0 + 0.2) * 0.5, z - 0.3), steel)
	b._box(Vector3(bw + 0.3, bh + 0.3, 0.2), Vector3(x, y0 + bh * 0.5, z - 0.12), steel)
	var face := b._mat("hoarding_face", Color(0.86, 0.84, 0.78), 0.8)
	b._box(Vector3(bw, bh, 0.06), Vector3(x, y0 + bh * 0.5, z), face)
	b._box(Vector3(bw, 0.5, 0.07), Vector3(x, y0 + 0.3, z + 0.005), b._mat("hoarding_band", Color(0.12, 0.13, 0.15), 0.7))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 150
	lbl.pixel_size = 0.006
	lbl.line_spacing = -18.0
	if b.sign_font:
		lbl.font = b.sign_font
	lbl.modulate = Color(0.1, 0.1, 0.12)
	lbl.shaded = true
	lbl.position = Vector3(x, y0 + bh * 0.55 + 0.15, z + 0.05)
	lbl.double_sided = false
	b.root.add_child(lbl)
	for dx in [-2.6, 2.6]:
		b._box(Vector3(0.06, 0.06, 0.9), Vector3(x + dx, y0 + bh + 0.25, z + 0.45), steel)
		var lamp := b._neon_mat(Color(1.0, 0.92, 0.75), 2.0)
		b._box(Vector3(0.5, 0.1, 0.2), Vector3(x + dx, y0 + bh + 0.2, z + 0.9), lamp).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.92, 0.78)
		sl.light_energy = 5.0
		sl.spot_range = 6.0
		sl.spot_angle = 50.0
		sl.shadow_enabled = false
		sl.light_volumetric_fog_energy = 0.8
		sl.position = Vector3(x + dx, y0 + bh + 0.15, z + 1.0)
		sl.rotation = Vector3(-PI * 0.5 - 0.5, 0, 0)
		b.root.add_child(sl)


## A tall box sign on a pole, lit from inside: `text`, one line per "\n".
static func pylon_sign(b: LevelBuilder, x: float, text: String, z := -1.2) -> void:
	var steel := b._mat("pylon_steel", Color(0.75, 0.74, 0.7), 0.4, 0.6)
	var top := 6.0
	var sw := 3.6
	var sh := 2.2
	b._box(Vector3(0.28, top - sh, 0.28), Vector3(x, (top - sh) * 0.5, z), steel)
	var box := b._neon_mat(Color(0.95, 0.93, 0.85), 0.9)
	b._box(Vector3(sw, sh, 0.4), Vector3(x, top - sh * 0.5, z), box).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b._box(Vector3(sw + 0.16, 0.18, 0.46), Vector3(x, top + 0.05, z), b._mat("pylon_red", Color(0.7, 0.12, 0.1), 0.5))
	b._box(Vector3(sw + 0.16, 0.18, 0.46), Vector3(x, top - sh - 0.05, z), b._mat("pylon_red", Color(0.7, 0.12, 0.1), 0.5))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.pixel_size = 0.0042
	lbl.line_spacing = -10.0
	if b.sign_font:
		lbl.font = b.sign_font
	lbl.modulate = Color(0.62, 0.1, 0.08)
	lbl.position = Vector3(x, top - sh * 0.5, z + 0.21)
	lbl.double_sided = false
	b.root.add_child(lbl)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.95, 0.85)
	glow.light_energy = 1.4
	glow.omni_range = 5.0
	glow.position = Vector3(x, top - sh * 0.5, z + 1.2)
	b.root.add_child(glow)


# --- helpers --------------------------------------------------------------------------------------
# Detail is merged into one mesh per material (a motel is a few hundred small boxes otherwise).

## A box from x0..x1, y0..y1, z0..z1 added to the surface for `mat`.
static func _add(sts: Dictionary, mat: Material, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	RailwayBuilder._box(sts, mat, x0, x1, z0, z1, y0, y1)


static func _commit(b: LevelBuilder, sts: Dictionary) -> void:
	for mat: Material in sts:
		var mi := MeshInstance3D.new()
		mi.mesh = (sts[mat] as SurfaceTool).commit()
		mi.material_override = mat
		var sm := mat as StandardMaterial3D
		if sm and sm.emission_enabled:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.root.add_child(mi)


## The kit's textured material `res` in another colour. Falls back to the flat colour if it is missing.
static func _textured(b: LevelBuilder, key: String, res: String, tint: Color) -> Material:
	if b._mats.has(key):
		return b._mats[key]
	var src := b._material_res(res, null) as StandardMaterial3D
	if src == null:
		return b._mat(key, tint * 0.75)
	var m: StandardMaterial3D = src.duplicate()
	m.albedo_color = tint
	b._mats[key] = m
	return m


## A wall's street face as one quad with UVs in metres, as the kit's walls have, so a kit material
## tiles across it at the scale it does on the buildings either side.
static func _wall_face(b: LevelBuilder, mat: Material, x0: float, x1: float, y0: float, y1: float, z: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector2 in [Vector2(x0, y0), Vector2(x0, y1), Vector2(x1, y1), Vector2(x0, y0), Vector2(x1, y1), Vector2(x1, y0)]:
		st.set_normal(Vector3.BACK)
		st.set_tangent(Plane(1.0, 0.0, 0.0, 1.0))
		st.set_uv(Vector2(p.x, -p.y))
		st.add_vertex(Vector3(p.x, p.y, z))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.root.add_child(mi)


## A lit, shaded surface: it glows but still takes the street's light.
static func _glow(b: LevelBuilder, key: String, col: Color, energy: float) -> StandardMaterial3D:
	var m := b._mat(key, col, 0.7)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m
