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
	var wall := b._mat("motel_wall", Color(0.74, 0.69, 0.58), 0.85)
	b._box(Vector3(w, h, 8.0), Vector3(x + w * 0.5, h * 0.5, -4.0), wall)
	var trim := b._mat("motel_trim", Color(0.86, 0.84, 0.78), 0.6)
	b._box(Vector3(w + 0.1, 0.4, 0.5), Vector3(x + w * 0.5, h - 0.2, 0.1), trim)
	var n := maxi(1, roundi(w / ROOM_W))
	var rw := w / n
	var door_col: Color = DOOR_COLORS[b._lot_hash(x, "motel") % DOOR_COLORS.size()]
	var door := b._mat("motel_door_%d" % DOOR_COLORS.find(door_col), door_col, 0.5)
	var number := 1 + b._lot_hash(x, "rooms") % 20
	for s in storeys:
		var y0 := s * STOREY + (WALK_Y - STOREY + 0.11 if s > 0 else 0.0)
		for i in n:
			var rx := x + i * rw
			_room(b, rx, rw, y0, door, number)
			number += 1


## The walkway along a motel's rooms: the upper floor's slab (railing on top) roofs the lower walkway
## and is cover; steel posts hold it up at its front edge, one between each pair of rooms.
static func walkway(b: LevelBuilder, x: float, w: float) -> void:
	b._build_slab(x, w, WALK_Y, WALK_DEPTH, false)
	var steel := b._mat("motel_post", Color(0.2, 0.2, 0.21), 0.5, 0.6)
	var n := maxi(1, roundi(w / ROOM_W))
	for i in n + 1:
		var px := clampf(x + i * w / n, x + 0.1, x + w - 0.1)
		b._box(Vector3(0.1, WALK_Y, 0.1), Vector3(px, WALK_Y * 0.5, WALK_DEPTH - 0.18), steel)


## One room: a coloured door with its number, and a window whose curtains are lit or drawn dark.
static func _room(b: LevelBuilder, rx: float, rw: float, y0: float, door: Material, number: int) -> void:
	var dx := rx + rw * 0.28
	b._box(Vector3(0.92, 2.1, 0.08), Vector3(dx, y0 + 1.05, 0.04), door)
	b._box(Vector3(0.06, 0.06, 0.06), Vector3(dx + 0.34, y0 + 1.0, 0.1), b._mat("brass", Color(0.7, 0.55, 0.25), 0.3, 0.8))
	var lbl := Label3D.new()
	lbl.text = str(number)
	lbl.font_size = 64
	lbl.pixel_size = 0.004
	if b.sign_font:
		lbl.font = b.sign_font
	lbl.modulate = Color(0.85, 0.8, 0.6)
	lbl.position = Vector3(dx, y0 + 2.32, 0.03)
	lbl.double_sided = false
	b.root.add_child(lbl)
	var lit := b.rng.randf() < 0.3
	var wx := rx + rw * 0.68
	var glass: StandardMaterial3D
	if lit:
		glass = b._mat("curtain_lit", Color(0.95, 0.72, 0.42), 0.6)
		glass.emission_enabled = true
		glass.emission = Color(1.0, 0.66, 0.34)
		glass.emission_energy_multiplier = 1.1
	else:
		glass = b._mat("curtain_dark", Color(0.18, 0.13, 0.1), 0.7)
	b._box(Vector3(1.4, 1.1, 0.06), Vector3(wx, y0 + 1.55, 0.03), glass)
	b._box(Vector3(1.55, 0.08, 0.14), Vector3(wx, y0 + 0.98, 0.06), b._mat("motel_trim", Color(0.86, 0.84, 0.78), 0.6))
	# A door light under the walkway, a bare bulb in a cage.
	var bulb := b._neon_mat(Color(1.0, 0.82, 0.55), 1.4)
	var bm := b._box(Vector3(0.12, 0.12, 0.1), Vector3(dx + 0.75, y0 + 2.45, 0.08), bulb)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if lit:
		b.lit_windows.append([Vector3(wx, y0 + 1.6, -0.8), Color(1.0, 0.68, 0.38)])


## An open apron of concrete with painted bays, and a low building SET_BACK behind the lot line.
static func forecourt(b: LevelBuilder, x: float, w: float, lot: Dictionary) -> void:
	var conc := b._mat("forecourt", Color(0.3, 0.3, 0.29), 0.35)
	b._box(Vector3(w, 0.3, SET_BACK + 2.0), Vector3(x + w * 0.5, -0.15, -(SET_BACK + 2.0) * 0.5), conc)
	var paint := b._mat("bay_paint", Color(0.7, 0.68, 0.6), 0.5)
	var bx := x + 1.0
	while bx < x + w - 0.5:
		b._box(Vector3(0.1, 0.02, 4.5), Vector3(bx, 0.005, -3.6), paint)
		bx += 2.6
	var bw := maxf(w - 1.6, 3.0)
	var bh := 4.2
	var wall := b._mat("forecourt_wall", Color(0.46, 0.42, 0.36), 0.85)
	var cx := x + w * 0.5
	b._box(Vector3(bw, bh, 6.0), Vector3(cx, bh * 0.5, -SET_BACK - 3.0), wall)
	b._box(Vector3(bw + 0.4, 0.5, 1.4), Vector3(cx, bh - 0.1, -SET_BACK + 0.3), b._mat("forecourt_fascia", Color(0.62, 0.15, 0.12), 0.6))
	var shut := not bool(lot.get("lit", false))
	var glass := b._mat("glass_dark", Color(0.03, 0.035, 0.04), 0.05, 0.3)
	b._box(Vector3(bw - 1.2, 1.8, 0.08), Vector3(cx, 1.6, -SET_BACK + 0.02), glass)
	if lot.has("sign"):
		var lbl := Label3D.new()
		lbl.text = String(lot["sign"])
		lbl.pixel_size = 0.006
		if b.sign_font:
			lbl.font = b.sign_font
		lbl.font_size = int(clampf((bw - 0.8) / 0.006 / maxf(1.0, lbl.text.length() * 0.62), 40.0, 120.0))
		lbl.modulate = Color(0.5, 0.45, 0.38) if shut else Color(1.0, 0.85, 0.55)
		lbl.shaded = shut
		lbl.position = Vector3(cx, bh - 0.1, -SET_BACK + 1.02)
		lbl.double_sided = false
		b.root.add_child(lbl)
	if lot.has("note"):
		var note := Label3D.new()
		note.text = String(lot["note"])
		note.font_size = 48
		note.pixel_size = 0.005
		note.modulate = Color(0.8, 0.75, 0.65)
		note.shaded = true
		note.position = Vector3(cx - bw * 0.25, 1.9, -SET_BACK + 0.08)
		note.double_sided = false
		b.root.add_child(note)
	b._box(Vector3(w + 6.0, 9.0, 1.0), Vector3(cx, 4.5, -SET_BACK - 8.0), b._mat("farwall", Color(0.22, 0.2, 0.19), 0.9))
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


## A hoarding on two steel posts, its face lit by two lamps on arms: `text`, one line per "\n".
static func billboard(b: LevelBuilder, x: float, text: String, z := -3.0) -> void:
	var steel := b._mat("hoarding_steel", Color(0.16, 0.16, 0.17), 0.55, 0.6)
	var bw := 10.0
	var y0 := 3.4
	var bh := 3.4
	for dx in [-3.2, 3.2]:
		b._box(Vector3(0.3, y0 + 0.2, 0.3), Vector3(x + dx, (y0 + 0.2) * 0.5, z - 0.3), steel)
	b._box(Vector3(bw + 0.3, bh + 0.3, 0.2), Vector3(x, y0 + bh * 0.5, z - 0.12), steel)
	var face := b._mat("hoarding_face", Color(0.86, 0.84, 0.78), 0.8)
	b._box(Vector3(bw, bh, 0.06), Vector3(x, y0 + bh * 0.5, z), face)
	b._box(Vector3(bw, 0.5, 0.07), Vector3(x, y0 + 0.3, z + 0.005), b._mat("hoarding_band", Color(0.12, 0.13, 0.15), 0.7))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 150
	lbl.pixel_size = 0.0075
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
	var top := 7.4
	var sw := 3.0
	var sh := 2.3
	b._box(Vector3(0.28, top - sh, 0.28), Vector3(x, (top - sh) * 0.5, z), steel)
	var box := b._neon_mat(Color(0.95, 0.93, 0.85), 0.9)
	b._box(Vector3(sw, sh, 0.4), Vector3(x, top - sh * 0.5, z), box).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b._box(Vector3(sw + 0.16, 0.18, 0.46), Vector3(x, top + 0.05, z), b._mat("pylon_red", Color(0.7, 0.12, 0.1), 0.5))
	b._box(Vector3(sw + 0.16, 0.18, 0.46), Vector3(x, top - sh - 0.05, z), b._mat("pylon_red", Color(0.7, 0.12, 0.1), 0.5))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.pixel_size = 0.0055
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
