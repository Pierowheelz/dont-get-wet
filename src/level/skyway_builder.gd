class_name SkywayBuilder
extends RefCounted
## The level's `skyways` ([{x0, x1}]): enclosed glass galleries carried over the pavement at the first
## upper floor, from x0 to x1, against the facades (over a side street they bridge it). Each is cover:
## one box collider on the cover layer from the soffit to the roof over z 0..Z1, so the walker's rain
## rays stop on it, and LevelBuilder.cover_map() marks it COVER_VOLUME so the visual rain stops on its
## roof and never falls inside the glass. It is high, so wind-slanted rain gets further in under its ends
## than under an awning; the rays and the cover map both follow from the geometry.
##
## Section (z, y), from the soffit up: a white concrete floor slab (SOFFIT_Y to DECK_Y) with downlights
## in its underside and a cyan neon line along its lower front edge, then glazing leaning out from
## FRONT_Z at the bottom to TOP_Z at GLASS_TOP, a white roof fascia, and the roof at ROOF_Y. Inside: a
## lit travertine back wall (glass over side streets), a luminous ceiling and a few passengers walking.
## Slim tapered columns stand under its front edge every COLUMN_EVERY m or less, never in a side
## street's road, and clear of the kerb props. Runs inside LevelBuilder.build: it only adds nodes.

const SOFFIT_Y := 4.45       # underside of the floor slab: above the 3.1-3.9 m sign band
const DECK_Y := 4.95         # the gallery's floor
const GLASS_TOP := 7.1       # top of the front glazing
const ROOF_Y := 7.6          # top of the roof slab
const FRONT_Z := 3.0         # foot of the front glazing (the slab's front face)
const TOP_Z := 3.22          # top of the front glazing, which leans out
const BACK_Z := 0.4           # the gallery's back wall, in front of anything a kit facade carries
const Z1 := 3.3              # the cover's front edge (roof fascia), short of the kerb at 3.5
const COLUMN_Z := 2.75       # columns' centre: clear of an open canopy on the walker's line (z 1.6 + 0.8)
const COLUMN_EVERY := 9.0
const COLUMN_CLEAR := 0.6    # from a side street's kerb and from a kerb prop
const MULLION_EVERY := 1.6
const LIGHT_EVERY := 7.0     # a downlight (and a spot onto the pavement) under the soffit
const KERB_PROPS := ["lamp_post", "hydrant", "parking_meter", "street_sign", "mailbox", "trash_can",
	"newspaper_box", "newspaper_box_b", "phone_booth", "bollard"]

var b: LevelBuilder
var _glass: ShaderMaterial


## [x0, x1] of each skyway in the level data, in order.
static func spans(data: Dictionary) -> Array:
	var out: Array = []
	for s in data.get("skyways", []):
		out.append([float(s["x0"]), float(s["x1"])])
	return out


static func under(data: Dictionary, x: float) -> bool:
	for s in data.get("skyways", []):
		if x >= float(s["x0"]) and x <= float(s["x1"]):
			return true
	return false


func build(builder: LevelBuilder) -> void:
	b = builder
	_glass = ShaderMaterial.new()
	_glass.shader = load("res://src/fx/skyway_glass.gdshader")
	var crossings: Array = []
	for c in b.data.get("crossings", []):
		crossings.append([float(c["x"]), float(c["x"]) + float(c["w"])])
	for sp in spans(b.data):
		_cover(sp[0], sp[1])
		draw(sp[0], sp[1], crossings)


## Visual only (an art pass may restyle all of it): the gallery from x0 to x1. Gameplay needs only
## that nothing below SOFFIT_Y reaches past the columns' line, and the columns where column_xs puts them.
func draw(x0: float, x1: float, crossings: Array) -> void:
	var sts := {}
	var white := b._mat("skyway_concrete", Color(0.86, 0.85, 0.8), 0.55)
	var soffit := b._mat("skyway_soffit", Color(0.7, 0.7, 0.68), 0.7)
	var alu := b._mat("skyway_alu", Color(0.78, 0.8, 0.82), 0.25, 0.85)
	var chrome := b._mat("chrome", Color(0.82, 0.84, 0.88), 0.12, 1.0)
	var floor := b._mat("skyway_floor", Color(0.42, 0.36, 0.3), 0.5)
	var wall := RoadsideBuilder._glow(b, "skyway_wall", Color(0.78, 0.7, 0.58), 0.35)
	var ceiling := b._neon_mat(Color(0.92, 0.96, 1.0), 1.25)
	var neon := b._neon_mat(Color(0.35, 0.95, 1.0), 3.0)
	var lamp := b._neon_mat(Color(1.0, 0.92, 0.8), 2.5)
	# The floor slab: a deep white fascia whose lower edge is drawn back, a darker soffit, the floor.
	_section(sts, white, x0, x1, [Vector2(0.0, SOFFIT_Y + 0.12), Vector2(FRONT_Z - 0.12, SOFFIT_Y + 0.12),
		Vector2(FRONT_Z - 0.04, SOFFIT_Y), Vector2(FRONT_Z + 0.04, SOFFIT_Y + 0.1), Vector2(FRONT_Z + 0.06, DECK_Y),
		Vector2(0.0, DECK_Y)])
	RoadsideBuilder._add(sts, soffit, x0 + 0.02, x1 - 0.02, SOFFIT_Y + 0.06, SOFFIT_Y + 0.12, 0.0, FRONT_Z - 0.14)
	RoadsideBuilder._add(sts, floor, x0, x1, DECK_Y, DECK_Y + 0.03, 0.05, FRONT_Z)
	RoadsideBuilder._add(sts, neon, x0 + 0.05, x1 - 0.05, SOFFIT_Y + 0.02, SOFFIT_Y + 0.05, FRONT_Z - 0.05, FRONT_Z + 0.0)
	# The roof: a white fascia over the glazing's head, a chrome drip edge, the slab behind.
	_section(sts, white, x0, x1, [Vector2(0.0, GLASS_TOP), Vector2(TOP_Z, GLASS_TOP), Vector2(Z1, GLASS_TOP + 0.05),
		Vector2(Z1, ROOF_Y), Vector2(0.0, ROOF_Y)])
	RoadsideBuilder._add(sts, chrome, x0, x1, ROOF_Y - 0.06, ROOF_Y, Z1, Z1 + 0.03)
	# Inside: the luminous ceiling in a grid of panels, the back wall (glass where it bridges a road).
	RoadsideBuilder._add(sts, ceiling, x0 + 0.1, x1 - 0.1, GLASS_TOP - 0.05, GLASS_TOP - 0.02, 0.3, FRONT_Z - 0.1)
	for z in [1.2, 2.1]:
		RoadsideBuilder._add(sts, alu, x0 + 0.1, x1 - 0.1, GLASS_TOP - 0.08, GLASS_TOP - 0.04, z - 0.03, z + 0.03)
	for seg in _walls(x0, x1, crossings):
		if seg[2]:
			RoadsideBuilder._add(sts, wall, seg[0], seg[1], DECK_Y, GLASS_TOP, BACK_Z - 0.07, BACK_Z)
			RoadsideBuilder._add(sts, chrome, seg[0], seg[1], DECK_Y + 0.95, DECK_Y + 1.0, BACK_Z, BACK_Z + 0.06)
		else:
			_glass_quad(Vector3(seg[0], DECK_Y, BACK_Z), Vector3(seg[1], GLASS_TOP, BACK_Z), false)
	# The front glazing in one leaning sheet, with mullions down it and a transom near the foot.
	_glass_quad(Vector3(x0, DECK_Y, FRONT_Z), Vector3(x1, GLASS_TOP, TOP_Z), true)
	var n := maxi(1, roundi((x1 - x0) / MULLION_EVERY))
	for i in n + 1:
		var mx := clampf(x0 + (x1 - x0) * i / n, x0 + 0.04, x1 - 0.04)
		_lean_bar(sts, alu, mx, 0.05)
	RoadsideBuilder._add(sts, alu, x0, x1, DECK_Y + 0.55, DECK_Y + 0.6, FRONT_Z + 0.02, FRONT_Z + 0.07)
	# Glazed ends.
	_end(sts, alu, white, x0, -1.0)
	_end(sts, alu, white, x1, 1.0)
	# Downlights in the soffit, each throwing a pool onto the pavement, so the walker reads under it.
	var lx := x0 + LIGHT_EVERY * 0.5
	while lx < x1:
		RoadsideBuilder._add(sts, lamp, lx - 0.25, lx + 0.25, SOFFIT_Y + 0.04, SOFFIT_Y + 0.06, 1.2, 1.7)
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.88, 0.72)
		sl.light_energy = 5.5
		sl.spot_range = 7.0
		sl.spot_angle = 60.0
		sl.shadow_enabled = false
		sl.light_volumetric_fog_energy = 0.6
		sl.position = Vector3(lx, SOFFIT_Y - 0.05, 1.5)
		sl.rotation = Vector3(-PI * 0.5, 0, 0)
		b.root.add_child(sl)
		lx += LIGHT_EVERY
	# A cool wash inside, so the glazing and mullions read from the street.
	var ix := x0 + 5.0
	while ix < x1 - 2.0:
		var om := OmniLight3D.new()
		om.light_color = Color(0.85, 0.95, 1.0)
		om.light_energy = 1.2
		om.omni_range = 6.0
		om.light_volumetric_fog_energy = 0.3
		om.position = Vector3(ix, GLASS_TOP - 0.6, 1.6)
		b.root.add_child(om)
		ix += 12.0
	for cx in column_xs(x0, x1, crossings, b.data.get("props", [])):
		_column(cx, white, chrome)
	RoadsideBuilder._commit(b, sts)
	_passengers(x0, x1)


## Gameplay: the cover (one box on the cover layer, soffit to roof, wall to Z1) and the drip line
## that marks its front edge. The rain cover map (LevelBuilder.cover_map) matches this box.
func _cover(x0: float, x1: float) -> void:
	b._cover_box(Vector3(x1 - x0, ROOF_Y - SOFFIT_Y, Z1), Transform3D(Basis(),
		Vector3((x0 + x1) * 0.5, (SOFFIT_Y + ROOF_Y) * 0.5, Z1 * 0.5)))
	# Water off the glazing gathers at the slab's lower lip and drips from its front edge.
	b._drips(x0 + 0.05, x1 - 0.05, SOFFIT_Y - 0.02, FRONT_Z + 0.06, 1.2, 1.05)


## Columns under the front edge: one near each end, more between so none is more than COLUMN_EVERY
## apart, each moved out of side-street roads and away from kerb props.
static func column_xs(x0: float, x1: float, crossings: Array, props: Array) -> Array:
	var blocked: Array = []   # [a, b] where no column may stand
	for c in crossings:
		blocked.append([float(c[0]) - COLUMN_CLEAR, float(c[1]) + COLUMN_CLEAR])
	for p in props:
		if KERB_PROPS.has(String(p["id"])):
			blocked.append([float(p["x"]) - COLUMN_CLEAR, float(p["x"]) + COLUMN_CLEAR])
	var free := func(x: float) -> bool:
		return x >= x0 + 0.3 and x <= x1 - 0.3 and not blocked.any(func(r: Array) -> bool: return x > r[0] and x < r[1])
	var out: Array = []
	var prev := -INF
	var t := x0 + 0.5
	while true:
		# Nearest free spot at or before the target (so no gap grows past COLUMN_EVERY), else after it.
		var at := INF
		var s := t
		while s > maxf(prev + 1.5, x0) and not free.call(s):
			s -= 0.1
		if s > maxf(prev + 1.5, x0) and free.call(s):
			at = s
		else:
			s = t
			while s < x1 - 0.3 and not free.call(s):
				s += 0.1
			if free.call(s):
				at = s
		if at == INF:
			break
		out.append(at)
		prev = at
		t = minf(at + COLUMN_EVERY, x1 - 0.5)
		if t - at < 2.5:
			break
	return out


## Back-wall segments [a, b, solid]: solid against buildings, glass where the skyway bridges a road.
func _walls(x0: float, x1: float, crossings: Array) -> Array:
	var out: Array = []
	var a := x0
	for c in crossings:
		if c[1] <= x0 or c[0] >= x1:
			continue
		if c[0] > a:
			out.append([a, c[0], true])
		out.append([maxf(c[0], x0), minf(c[1], x1), false])
		a = minf(c[1], x1)
	if a < x1:
		out.append([a, x1, true])
	return out


## A profile (z, y) drawn as a prism from x0 to x1.
func _section(sts: Dictionary, mat: Material, x0: float, x1: float, profile: Array) -> void:
	ViaductBuilder.loft_into(RailwayBuilder._st(sts, mat), [[x0, PackedVector2Array(profile)], [x1, PackedVector2Array(profile)]])


## A mullion up the leaning front glazing at x.
func _lean_bar(sts: Dictionary, mat: Material, x: float, w: float) -> void:
	var prof := PackedVector2Array([Vector2(FRONT_Z + 0.0, DECK_Y), Vector2(FRONT_Z + 0.09, DECK_Y),
		Vector2(TOP_Z + 0.09, GLASS_TOP), Vector2(TOP_Z + 0.0, GLASS_TOP)])
	ViaductBuilder.loft_into(RailwayBuilder._st(sts, mat), [[x - w * 0.5, prof], [x + w * 0.5, prof]])


## A glazed end: a frame round the section and a pane across it.
func _end(sts: Dictionary, alu: Material, white: Material, ex: float, s: float) -> void:
	RoadsideBuilder._add(sts, white, ex - 0.08, ex + 0.08, SOFFIT_Y + 0.1, ROOF_Y, 0.0, 0.25)
	_lean_bar(sts, alu, ex, 0.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [Vector3(ex, DECK_Y, 0.2), Vector3(ex, DECK_Y, FRONT_Z), Vector3(ex, GLASS_TOP, TOP_Z), Vector3(ex, GLASS_TOP, 0.2)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3(s, 0, 0))
		st.set_uv(Vector2(p[i].z, p[i].y))
		st.add_vertex(p[i])
	_add_glass(st.commit())


## One pane from a (bottom left) to c (top right); `lean` slopes it from a.z at the foot to c.z at the head.
func _glass_quad(a: Vector3, c: Vector3, lean: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zt := c.z if lean else a.z
	var p := [Vector3(a.x, a.y, a.z), Vector3(c.x, a.y, a.z), Vector3(c.x, c.y, zt), Vector3(a.x, c.y, zt)]
	var nrm := Vector3(0, -(zt - a.z), c.y - a.y).normalized()
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(nrm)
		st.set_uv(Vector2(p[i].x, p[i].y))
		st.add_vertex(p[i])
	_add_glass(st.commit())


func _add_glass(mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _glass
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.root.add_child(mi)


## A slim tapered white column on a chrome shoe under the front edge.
func _column(x: float, white: Material, chrome: Material) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.12
	cm.height = SOFFIT_Y
	cm.radial_segments = 16
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = white
	mi.position = Vector3(x, SOFFIT_Y * 0.5, COLUMN_Z)
	b.root.add_child(mi)
	var shoe := CylinderMesh.new()
	shoe.top_radius = 0.135
	shoe.bottom_radius = 0.16
	shoe.height = 0.3
	shoe.radial_segments = 16
	shoe.rings = 1
	var si := MeshInstance3D.new()
	si.mesh = shoe
	si.material_override = chrome
	si.position = Vector3(x, 0.15, COLUMN_Z)
	b.root.add_child(si)


## A few people walking the gallery, in silhouette against the lit back wall, some with a bag.
func _passengers(x0: float, x1: float) -> void:
	var n := int((x1 - x0) / 9.0)
	if n <= 0:
		return
	var node := Node3D.new()
	node.set_script(load("res://src/level/skyway_walkers.gd"))
	b.root.add_child(node)
	var dark := b._mat("skyway_figure", Color(0.06, 0.06, 0.07), 0.8)
	var coat := b._mat("skyway_figure_coat", Color(0.15, 0.13, 0.12), 0.8)
	for i in n:
		var r := b._lot_hash(x0 + i * 9.0, "skyway_walker")
		var fig := Node3D.new()
		var mat: Material = coat if r % 3 == 0 else dark
		var body := CapsuleMesh.new()
		body.radius = 0.2
		body.height = 1.45
		var bi := MeshInstance3D.new()
		bi.mesh = body
		bi.material_override = mat
		bi.position = Vector3(0, 0.75, 0)
		bi.scale = Vector3(1.0, 1.0, 0.7)
		fig.add_child(bi)
		var head := SphereMesh.new()
		head.radius = 0.11
		head.height = 0.24
		var hi := MeshInstance3D.new()
		hi.mesh = head
		hi.material_override = dark
		hi.position = Vector3(0.02, 1.58, 0)
		fig.add_child(hi)
		if r % 4 == 1:   # a hat
			var hat := CylinderMesh.new()
			hat.top_radius = 0.1
			hat.bottom_radius = 0.17
			hat.height = 0.1
			var ht := MeshInstance3D.new()
			ht.mesh = hat
			ht.material_override = dark
			ht.position = Vector3(0.02, 1.68, 0)
			fig.add_child(ht)
		if r % 2 == 0:   # a suitcase
			b._box(Vector3(0.45, 0.32, 0.14), Vector3(0.05, 0.42, 0.24), coat, fig)
		fig.position = Vector3(x0 + (i + 0.5) * (x1 - x0) / n, DECK_Y, 0.9 + float(r % 5) * 0.32)
		node.add_child(fig)
		node.call("add_walker", fig, x0 + 0.6, x1 - 0.6, (0.6 + float(r % 7) * 0.12) * (1.0 if r % 2 == 0 else -1.0))
