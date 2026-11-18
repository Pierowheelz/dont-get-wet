class_name RailwayBuilder
extends RefCounted
## Static geometry of a `railway` track (Track.railway()): a low brick viaduct standing over the
## pavement. Each `viaducts` span is a run of brick arches whose vault is cover (rain and wash);
## everywhere else the line crosses on open iron girder spans, built like the monorail's truss, that
## rain and the sheet fall through. Also the carriages (make_train) and the lanterns hung from the
## viaduct (bracket_lamp). Runs inside LevelBuilder.build, possibly on a worker thread: it only adds nodes.

const BAY := 5.4                # target pier spacing along an arch run
const PIER_W := 0.8
const PIER_Z0 := 2.75           # the front pier blocks stand at the kerb; the walker passes behind them
const BACK_Z1 := 0.5            # back pier blocks, against the shopfronts
const FACE_Z0 := 3.1            # the front wall (spandrels and parapet) is FACE_Z0..Track.RAIL_Z1 thick
const SPRING_Y := 2.15          # each arch springs from its piers here and rises to just under the soffit
const CROWN_Y := 3.0
const RING_W := 0.26            # the arch ring of headers round each opening
const ARCH_STRIPS := 14
const GIRDER_TOP := 4.15        # through girders: the carriages run between them, below their top chord
const GIRDER_BOT := 3.15
const GIRDER_ZS := [3.3, 0.3]   # front (kerb) and back (shopfront) main girders
const GIRDER_PANEL := 1.0
const GIRDER_CHUNK := 30.0
const CHORD := 0.13
const WEB := 0.05
const CROSS_STEP := 1.25        # cross girders under the open floor
const RAIL_ZS := [1.1, 2.55]    # standard gauge, centred over the walker's line
const COLUMN_MAX := 15.0        # a girder span longer than this gets cast-iron columns under it

var b: LevelBuilder
var brick: Material
var brick_dark: Material
var stone: Material
var iron: Material


func build(p_builder: LevelBuilder, tr: Track) -> void:
	b = p_builder
	brick = _triplanar(b._material_res("brick_red", b._mat("rail_brick_fb", Color(0.42, 0.2, 0.15), 0.95)), 0.55)
	brick_dark = _triplanar(b._material_res("brick_dark", b._mat("rail_brick_dark_fb", Color(0.2, 0.17, 0.16), 0.95)), 0.3)
	stone = b._mat("rail_stone", Color(0.52, 0.49, 0.44), 0.8)
	iron = b._mat("rail_iron", Color(0.13, 0.17, 0.15), 0.55, 0.45)
	var open_from := tr.x0
	for d in tr.decks:
		_girders(open_from, d[0])
		_arches(d[0], d[1])
		open_from = d[1]
	_girders(open_from, tr.x1)


static func _triplanar(src: Material, darken: float) -> Material:
	var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	m.albedo_color = m.albedo_color.darkened(1.0 - darken - 0.45)
	return m


# --- arches -----------------------------------------------------------------------------------

## A run of brick arches from xa to xb: piers at both ends and every BAY or so between, a segmental
## arch over each bay in the front wall, a parapet and coping along the top, and a vault behind the
## face whose soffit is cover from Track.RAIL_SOFFIT up to the deck.
func _arches(xa: float, xb: float) -> void:
	var w := xb - xa
	var n := maxi(1, roundi((w - PIER_W) / BAY))
	var step := (w - PIER_W) / n
	var piers: Array = []
	for i in n + 1:
		piers.append(xa + PIER_W * 0.5 + i * step)
	b._cover_box(Vector3(w, Track.RAIL_BED - Track.RAIL_SOFFIT, Track.RAIL_Z1 - Track.RAIL_Z0),
		Transform3D(Basis(), Vector3((xa + xb) * 0.5, (Track.RAIL_SOFFIT + Track.RAIL_BED) * 0.5, (Track.RAIL_Z0 + Track.RAIL_Z1) * 0.5)))
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := SurfaceTool.new()
	ring.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z1 := Track.RAIL_Z1
	for i in n:
		var a: float = piers[i] + PIER_W * 0.5
		var c: float = piers[i + 1] - PIER_W * 0.5
		var prev := Vector2(a, SPRING_Y)
		for k in range(1, ARCH_STRIPS + 1):
			var x := lerpf(a, c, float(k) / ARCH_STRIPS)
			var cur := Vector2(x, _intrados(a, c, x))
			_wall_strip(face, prev, cur, FACE_Z0, z1, Track.RAIL_PARAPET)
			# The ring of headers round the opening, a shade proud of the face.
			_quad(ring, Vector3(prev.x, prev.y, z1 + 0.02), Vector3(cur.x, cur.y, z1 + 0.02),
				Vector3(cur.x, cur.y + RING_W, z1 + 0.02), Vector3(prev.x, prev.y + RING_W, z1 + 0.02), Vector3.BACK)
			_quad(ring, Vector3(prev.x, prev.y, FACE_Z0), Vector3(cur.x, cur.y, FACE_Z0),
				Vector3(cur.x, cur.y, z1 + 0.02), Vector3(prev.x, prev.y, z1 + 0.02), Vector3.DOWN)
			prev = cur
	for px: float in piers:
		# Front pier: a pilaster proud of the face, with a stone impost where the arches spring.
		_wall_strip(face, Vector2(px - PIER_W * 0.5, 0.0), Vector2(px + PIER_W * 0.5, 0.0), PIER_Z0, z1, Track.RAIL_PARAPET)
		b._box(Vector3(PIER_W + 0.1, 0.14, z1 - PIER_Z0 + 0.12), Vector3(px, SPRING_Y - 0.07, (PIER_Z0 + z1) * 0.5 + 0.04), stone)
		b._box(Vector3(PIER_W + 0.06, 0.3, z1 - PIER_Z0 + 0.1), Vector3(px, 0.15, (PIER_Z0 + z1) * 0.5 + 0.03), stone)
		b._box(Vector3(PIER_W, Track.RAIL_SOFFIT, BACK_Z1 - Track.RAIL_Z0), Vector3(px, Track.RAIL_SOFFIT * 0.5, (Track.RAIL_Z0 + BACK_Z1) * 0.5), brick)
	for m in [[face, brick], [ring, brick_dark]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (m[0] as SurfaceTool).commit()
		mi.material_override = m[1]
		b.root.add_child(mi)
	# Behind the face: the vault's soffit, the back wall up to the parapet, coping and a string course.
	var zc := (BACK_Z1 + FACE_Z0) * 0.5
	b._box(Vector3(w, Track.RAIL_BED - Track.RAIL_SOFFIT, FACE_Z0 - BACK_Z1), Vector3((xa + xb) * 0.5, (Track.RAIL_SOFFIT + Track.RAIL_BED) * 0.5, zc), brick_dark)
	b._box(Vector3(w, Track.RAIL_PARAPET - Track.RAIL_SOFFIT, BACK_Z1 - Track.RAIL_Z0), Vector3((xa + xb) * 0.5, (Track.RAIL_SOFFIT + Track.RAIL_PARAPET) * 0.5, (Track.RAIL_Z0 + BACK_Z1) * 0.5), brick)
	for zz in [[FACE_Z0 - 0.06, z1 + 0.1], [Track.RAIL_Z0 - 0.05, BACK_Z1 + 0.06]]:
		b._box(Vector3(w + 0.1, 0.1, zz[1] - zz[0]), Vector3((xa + xb) * 0.5, Track.RAIL_PARAPET + 0.05, (zz[0] + zz[1]) * 0.5), stone)
	b._box(Vector3(w, 0.1, 0.08), Vector3((xa + xb) * 0.5, Track.RAIL_BED - 0.02, z1 + 0.05), stone)
	# A bulkhead lamp in every other vault, so the arches read as shelter and not a black hole.
	for i in range(0, n, 2):
		var lx: float = (piers[i] + piers[i + 1]) * 0.5
		var lamp := b._box(Vector3(0.3, 0.08, 0.18), Vector3(lx, Track.RAIL_SOFFIT - 0.05, 1.4), b._neon_mat(Color(1.0, 0.78, 0.45), 1.6))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var om := OmniLight3D.new()
		om.light_color = Color(1.0, 0.72, 0.42)
		om.light_energy = 1.1
		om.omni_range = 4.5
		om.omni_attenuation = 1.3
		om.light_volumetric_fog_energy = 0.6
		om.position = Vector3(lx, Track.RAIL_SOFFIT - 0.4, 1.5)
		b.root.add_child(om)


## Height of the arch's underside at x in a bay [a, c]: a circular segment from SPRING_Y to CROWN_Y.
static func _intrados(a: float, c: float, x: float) -> float:
	var half := (c - a) * 0.5
	var rise := CROWN_Y - SPRING_Y
	var r := (half * half + rise * rise) / (2.0 * rise)
	var dx := x - (a + c) * 0.5
	return CROWN_Y - r + sqrt(maxf(r * r - dx * dx, 0.0))


## The wall from p0 to p1 (x, underside y) up to `top`, z0..z1 thick: front, back and underside.
func _wall_strip(st: SurfaceTool, p0: Vector2, p1: Vector2, z0: float, z1: float, top: float) -> void:
	_quad(st, Vector3(p0.x, p0.y, z1), Vector3(p1.x, p1.y, z1), Vector3(p1.x, top, z1), Vector3(p0.x, top, z1), Vector3.BACK)
	_quad(st, Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, top, z0), Vector3(p0.x, top, z0), Vector3.FORWARD)
	_quad(st, Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1), Vector3.DOWN)
	if p0.y < 0.01 and p1.y < 0.01:   # a pier: its two sides face into the bays
		for x in [p0.x, p1.x]:
			var nrm := Vector3.LEFT if x == p0.x else Vector3.RIGHT
			_quad(st, Vector3(x, 0.0, z0), Vector3(x, 0.0, z1), Vector3(x, top, z1), Vector3(x, top, z0), nrm)


static func _quad(st: SurfaceTool, a: Vector3, c: Vector3, d: Vector3, e: Vector3, nrm: Vector3) -> void:
	ViaductBuilder._tri(st, a, c, d, nrm)
	ViaductBuilder._tri(st, a, d, e, nrm)


# --- girder spans -------------------------------------------------------------------------------

## The open bridge from xa to xb: a riveted lattice girder along the kerb and another along the
## shopfronts, cross girders and rail stringers between them. Nothing here is cover.
func _girders(xa: float, xb: float) -> void:
	if xb - xa < 0.3:
		return
	var x := xa
	while xb - x > 0.2:
		var xe := minf(x + GIRDER_CHUNK, xb)
		var n := maxi(1, roundi((xe - x) / GIRDER_PANEL))
		var step := (xe - x) / n
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lo := GIRDER_BOT + CHORD * 0.5
		var hi := GIRDER_TOP - CHORD * 0.5
		for z: float in GIRDER_ZS:
			ViaductBuilder._bar(st, Vector3(x, lo, z), Vector3(xe, lo, z), CHORD)
			ViaductBuilder._bar(st, Vector3(x, hi, z), Vector3(xe, hi, z), CHORD)
			for k in n + 1:
				var kx := x + k * step
				ViaductBuilder._bar(st, Vector3(kx, lo, z), Vector3(kx, hi, z), WEB)
				if k < n:
					ViaductBuilder._bar(st, Vector3(kx, lo, z), Vector3(kx + step, hi, z), WEB)
					ViaductBuilder._bar(st, Vector3(kx, hi, z), Vector3(kx + step, lo, z), WEB)
		var cx := x + CROSS_STEP * 0.5
		while cx < xe:
			ViaductBuilder._bar(st, Vector3(cx, Track.RAIL_BED - 0.25, GIRDER_ZS[1]), Vector3(cx, Track.RAIL_BED - 0.25, GIRDER_ZS[0]), 0.12)
			cx += CROSS_STEP
		for z: float in RAIL_ZS:
			ViaductBuilder._bar(st, Vector3(x, Track.RAIL_BED - 0.12, z), Vector3(xe, Track.RAIL_BED - 0.12, z), 0.14)
			ViaductBuilder._bar(st, Vector3(x, Track.RAIL_BED + 0.04, z), Vector3(xe, Track.RAIL_BED + 0.04, z), 0.07)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = iron
		b.root.add_child(mi)
		x = xe
	# A lantern where the span leaves each run of arches and on every column, so the open stretches
	# between the arches aren't left in the dark.
	var lamps: Array = [xa + 1.2, xb - 1.2] if xb - xa > 6.0 else []
	var span := xb - xa
	if span > COLUMN_MAX:
		var k := ceili(span / COLUMN_MAX)
		for i in range(1, k):
			var px := xa + span * i / k
			if not _in_crossing(px):
				for z: float in GIRDER_ZS:
					_column(px, z)
				lamps.append(px + 0.35)
	for lx: float in lamps:
		if lx > -6.0 and lx < float(b.data.get("length", 0.0)) + 6.0 and not _in_crossing(lx):
			bracket_lamp(b, lx)


## A cast-iron column under a girder: a fluted shaft on a plinth, with a flared capital.
func _column(x: float, z: float) -> void:
	_cylinder(0.12, 0.12, 0.3, GIRDER_BOT - 0.25, x, z, iron)
	_cylinder(0.12, 0.24, GIRDER_BOT - 0.25, GIRDER_BOT, x, z, iron)
	_cylinder(0.2, 0.2, 0.0, 0.3, x, z, stone)


func _cylinder(r0: float, r1: float, y0: float, y1: float, x: float, z: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = y1 - y0
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(x, (y0 + y1) * 0.5, z)
	b.root.add_child(mi)


func _in_crossing(x: float) -> bool:
	for c in b.data.get("crossings", []):
		if x > float(c["x"]) - 0.6 and x < float(c["x"]) + float(c["w"]) + 0.6:
			return true
	return false


# --- lanterns -----------------------------------------------------------------------------------

## A lantern hung from the viaduct's front edge at x, over the kerb: a rod, a glass box, a warm cone.
## Authored as the `bracket_lamp` prop (the track keeps lamp posts off the pavement).
static func bracket_lamp(p_builder: LevelBuilder, x: float) -> void:
	var lb := p_builder
	var metal := lb._mat("rail_iron", Color(0.13, 0.17, 0.15), 0.55, 0.45)
	var z := 3.0
	lb._box(Vector3(0.04, 0.5, 0.04), Vector3(x, GIRDER_BOT - 0.25, z), metal)
	lb._box(Vector3(0.22, 0.05, 0.22), Vector3(x, 2.7, z), metal)
	var glass := lb._neon_mat(Color(1.0, 0.7, 0.36), 1.8)
	var lantern := lb._box(Vector3(0.13, 0.2, 0.13), Vector3(x, 2.58, z), glass)
	lantern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for dx in [-0.07, 0.07]:   # the frame's corner posts
		lb._box(Vector3(0.02, 0.22, 0.02), Vector3(x + dx, 2.58, z + 0.07), metal)
	lb._box(Vector3(0.2, 0.05, 0.2), Vector3(x, 2.46, z), metal)
	lb._box(Vector3(0.12, 0.06, 0.12), Vector3(x, 2.43, z), metal)
	var sl := SpotLight3D.new()
	sl.light_color = Color(1.0, 0.72, 0.42)
	sl.light_energy = 3.0
	sl.spot_range = 7.0
	sl.spot_angle = 62.0
	sl.light_volumetric_fog_energy = 1.6
	sl.shadow_enabled = false
	sl.position = Vector3(x, 2.35, z - 0.6)
	sl.rotation = Vector3(-PI * 0.5, 0, 0)
	lb.root.add_child(sl)


# --- the carriages ------------------------------------------------------------------------------
# Country stock seen over the parapet: the camera sees the near side from about 3.9 m up to the top of
# the frame (about 4.9 m there), so the detail is the waist line and the lit bottom of the windows.
# Local x runs from the cab end (0) back to the tail, like the monorail's; built along +x.

const CAR_LEN := 12.2
const CAR_GAP := 0.6
const FLOOR_Y := Track.RAIL_TRAIN_Y
const WAIST_Y := 4.28
const WIN_Y0 := 4.38
const WIN_Y1 := 5.05
const ROOF_Y := 6.4


static func make_train(green: bool) -> Node3D:
	var root := Node3D.new()
	var sts := {}
	var paint := _flat(Color(0.15, 0.24, 0.17) if green else Color(0.32, 0.09, 0.08), 0.0, 0.55)
	var lining := _flat(Color(0.78, 0.66, 0.38), 0.3, 0.5)
	var dark := _flat(Color(0.06, 0.06, 0.07), 0.4, 0.6)
	var roof := _flat(Color(0.26, 0.27, 0.28), 0.1, 0.7)
	var window := _flat(Color(1.0, 0.84, 0.56), 0.0, 0.4, 1.1)
	var lens := _flat(Color(1.0, 0.96, 0.85), 0.0, 0.2, 6.0)
	var red := _flat(Color(1.0, 0.12, 0.1), 0.0, 0.4, 4.0)
	var z0 := Track.RAIL_TRAIN_Z0
	var z1 := Track.RAIL_TRAIN_Z1
	var zm := (z0 + z1) * 0.5
	var hull := PackedVector2Array([Vector2(z0, FLOOR_Y), Vector2(z1, FLOOR_Y), Vector2(z1, ROOF_Y - 0.4),
		Vector2(z1 - 0.35, ROOF_Y), Vector2(z0 + 0.35, ROOF_Y), Vector2(z0, ROOF_Y - 0.4)])
	for k in 2:
		var xa := k * (CAR_LEN + CAR_GAP)
		var xb := xa + CAR_LEN
		ViaductBuilder.loft_into(_st(sts, paint), [[xa, hull], [xb, hull]])
		_box(sts, roof, xa + 0.1, xb - 0.1, z0 + 0.3, z1 - 0.3, ROOF_Y - 0.05, ROOF_Y + 0.06)
		_box(sts, dark, xa + 0.3, xb - 0.3, z0 + 0.2, z1 - 0.2, Track.RAIL_BED + 0.35, FLOOR_Y + 0.01)
		for bx in [xa + 2.0, xb - 2.0]:
			_box(sts, dark, bx - 1.2, bx + 1.2, z0 + 0.25, z1 - 0.25, Track.RAIL_BED + 0.05, FLOOR_Y)
		_box(sts, lining, xa + 0.15, xb - 0.15, z1 - 0.01, z1 + 0.012, WAIST_Y - 0.03, WAIST_Y + 0.02)
		var wx := xa + 1.0
		while wx + 0.9 < xb - 0.6:
			_box(sts, window, wx, wx + 0.9, z1 - 0.02, z1 + 0.008, WIN_Y0, WIN_Y1)
			_box(sts, lining, wx + 0.42, wx + 0.48, z1, z1 + 0.014, WIN_Y0, WIN_Y1)
			wx += 1.25
		if k == 0:
			# The cab end: a flat front with a warning panel and one headlamp low on it.
			_box(sts, _flat(Color(0.85, 0.66, 0.12), 0.0, 0.5), xa - 0.012, xa, z0 + 0.4, z1 - 0.4, FLOOR_Y + 0.05, WIN_Y0 - 0.05)
			_box(sts, lens, xa - 0.04, xa, zm - 0.14, zm + 0.14, WAIST_Y - 0.05, WAIST_Y + 0.2)
		else:
			_box(sts, dark, xa - CAR_GAP - 0.05, xa + 0.05, z0 + 0.7, z1 - 0.7, FLOOR_Y, ROOF_Y - 0.3)
	_box(sts, red, 2 * CAR_LEN + CAR_GAP, 2 * CAR_LEN + CAR_GAP + 0.04, zm - 0.25, zm + 0.25, WAIST_Y, WAIST_Y + 0.12)
	for mat: Material in sts:
		var mi := MeshInstance3D.new()
		mi.mesh = (sts[mat] as SurfaceTool).commit()
		mi.material_override = mat
		if mat in [window, lens, red]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# The lit windows spill a little warm light over the wet girders as it passes.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.55)
	glow.light_energy = 1.2
	glow.omni_range = 6.0
	glow.omni_attenuation = 1.4
	glow.shadow_enabled = false
	glow.position = Vector3(CAR_LEN, WIN_Y0, z1 + 0.6)
	root.add_child(glow)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.95, 0.82)
	lamp.light_energy = 16.0
	lamp.spot_range = 22.0
	lamp.spot_angle = 24.0
	lamp.spot_attenuation = 0.5
	lamp.light_volumetric_fog_energy = 2.5
	lamp.shadow_enabled = false
	lamp.position = Vector3(-0.1, WAIST_Y + 0.07, zm)
	lamp.rotation = Vector3(0.0, PI * 0.5, 0.0)    # local -Z -> world -X
	lamp.rotate_object_local(Vector3.RIGHT, -0.3)
	root.add_child(lamp)
	var beam := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = 1.8
	cone.height = 13.0
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	var bm := ShaderMaterial.new()
	bm.shader = load("res://src/fx/headlight_beam.gdshader")
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dir := Vector3(-cos(0.3), -sin(0.3), 0.0)
	beam.transform = Transform3D(Basis(Quaternion(Vector3.DOWN, dir)), lamp.position + dir * 6.5)
	root.add_child(beam)
	return root


static func _st(sts: Dictionary, mat: Material) -> SurfaceTool:
	if not sts.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[mat] = st
	return sts[mat]


static func _box(sts: Dictionary, mat: Material, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float) -> void:
	var rect := PackedVector2Array([Vector2(z0, y0), Vector2(z1, y0), Vector2(z1, y1), Vector2(z0, y1)])
	ViaductBuilder.loft_into(_st(sts, mat), [[x0, rect], [x1, rect]])


static func _flat(color: Color, metal: float, rough: float, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m
