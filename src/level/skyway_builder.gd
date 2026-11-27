class_name SkywayBuilder
extends RefCounted
## The level's `skyways` ([{x0, x1}]): enclosed glass galleries carried over the pavement at the first
## upper floor, from x0 to x1, against the facades (over a side street they bridge it). Each is cover:
## one box collider on the cover layer from the soffit to the roof over z 0..Z1, so the walker's rain
## rays stop on it, and LevelBuilder.cover_map() marks it COVER_VOLUME so the visual rain stops on its
## roof and never falls inside the glass. It is high, so wind-slanted rain gets further in under its ends
## than under an awning; the rays and the cover map both follow from the geometry.
##
## Section (z, y), from the soffit up: a thin white floor plate (SOFFIT_Y to DECK_Y) with downlights
## in its underside, a chrome nosing and a cyan neon line along its front edge; plate glass leaning
## out from FRONT_Z at the foot to TOP_Z at GLASS_TOP between slim mullions, a chrome handrail behind
## it; and a thin white roof plate with a tapered eave, a row of glowing saucers in its ceiling.
## There is no back wall: the towers' first floors and the lobbies' upper halves show through the
## gallery (over a side street the back is glazed too), and passengers walk it in coats of all colours.
## Slim tapered columns stand under its front edge every COLUMN_EVERY m or less, never in a side
## street's road, and clear of the kerb props. Runs inside LevelBuilder.build: it only adds nodes.

const SOFFIT_Y := 4.45       # underside of the floor plate: above the 3.1-3.9 m sign band
const DECK_Y := 4.6          # the gallery's floor
const GLASS_TOP := 7.42      # head of the front glazing, the ceiling
const ROOF_Y := 7.6          # top of the roof plate
const FRONT_Z := 2.96        # foot of the front glazing
const TOP_Z := 3.14          # head of the front glazing, which leans out
const BACK_Z := 0.4          # the back glazing where the gallery bridges a side street
const Z1 := 3.3              # the cover's front edge (the eave), short of the kerb at 3.5
const COLUMN_Z := 2.75       # columns' centre: clear of an open canopy on the walker's line (z 1.6 + 0.8)
const COLUMN_EVERY := 9.0
const COLUMN_CLEAR := 0.6    # from a side street's kerb and from a kerb prop
const MULLION_EVERY := 1.6
const LIGHT_EVERY := 7.0     # a downlight (and a spot onto the pavement) under the soffit
const SAUCER_EVERY := 2.4    # between the glowing saucers in the ceiling
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
	var white := ModernBuilder.white(b)
	var soffit := b._mat("skyway_soffit", Color(0.6, 0.64, 0.64), 0.7)
	var alu := b._mat("skyway_alu", Color(0.8, 0.82, 0.84), 0.25, 0.85)
	var chrome := b._mat("chrome", Color(0.82, 0.84, 0.88), 0.12, 1.0)
	var neon := b._neon_mat(Color(0.35, 0.95, 1.0), 2.6)
	var lamp := b._neon_mat(Color(1.0, 0.92, 0.8), 2.5)
	var saucer := b._neon_mat(Color(1.0, 0.95, 0.84), 2.0)
	_glass.set_shader_parameter("tint", Color(0.36, 0.6, 0.6, 0.17))
	# The floor: a thin white plate, a paler soffit panel let into its underside, a nosing,
	# and the neon line between them that marks the edge of the dry pavement.
	RoadsideBuilder._add(sts, white, x0, x1, SOFFIT_Y + 0.02, DECK_Y, 0.0, FRONT_Z + 0.06)
	RoadsideBuilder._add(sts, soffit, x0 + 0.02, x1 - 0.02, SOFFIT_Y, SOFFIT_Y + 0.02, 0.0, FRONT_Z - 0.12)
	RoadsideBuilder._add(sts, neon, x0 + 0.05, x1 - 0.05, SOFFIT_Y, SOFFIT_Y + 0.02, FRONT_Z - 0.11, FRONT_Z - 0.07)
	RoadsideBuilder._add(sts, white, x0, x1, SOFFIT_Y, DECK_Y + 0.02, FRONT_Z + 0.06, FRONT_Z + 0.085)
	# The roof: a thin plate, its eave tapered to a chrome drip edge; glowing saucers in the ceiling.
	_section(sts, white, x0, x1, [Vector2(0.0, GLASS_TOP), Vector2(TOP_Z + 0.03, GLASS_TOP), Vector2(Z1, GLASS_TOP + 0.1),
		Vector2(Z1, ROOF_Y), Vector2(0.0, ROOF_Y)])
	RoadsideBuilder._add(sts, chrome, x0, x1, ROOF_Y - 0.05, ROOF_Y, Z1, Z1 + 0.025)
	var sx := x0 + SAUCER_EVERY * 0.5
	while sx < x1:
		ModernBuilder.cyl(sts, saucer, Vector3(sx, GLASS_TOP - 0.035, 1.65), Vector3(sx, GLASS_TOP, 1.65), 0.34, 0.34, 14)
		sx += SAUCER_EVERY
	# Where it bridges a road the back is glazed too; against the buildings it is open to them.
	for seg in _walls(x0, x1, crossings):
		if not seg[2]:
			_glass_quad(Vector3(seg[0], DECK_Y, BACK_Z), Vector3(seg[1], GLASS_TOP, BACK_Z), false)
			var bn := maxi(1, roundi((seg[1] - seg[0]) / MULLION_EVERY))
			for i in bn + 1:
				var bx: float = lerpf(seg[0], seg[1], float(i) / bn)
				RoadsideBuilder._add(sts, alu, bx - 0.02, bx + 0.02, DECK_Y, GLASS_TOP, BACK_Z - 0.06, BACK_Z)
			RoadsideBuilder._add(sts, chrome, seg[0], seg[1], DECK_Y + 0.98, DECK_Y + 1.02, BACK_Z + 0.08, BACK_Z + 0.12)
	# The front glazing in one leaning sheet between slim mullions, a rail at its foot, a handrail behind.
	_glass_quad(Vector3(x0, DECK_Y, FRONT_Z), Vector3(x1, GLASS_TOP, TOP_Z), true)
	var n := maxi(1, roundi((x1 - x0) / MULLION_EVERY))
	for i in n + 1:
		var mx := clampf(x0 + (x1 - x0) * i / n, x0 + 0.03, x1 - 0.03)
		_lean_bar(sts, alu, mx, 0.04)
	RoadsideBuilder._add(sts, alu, x0, x1, DECK_Y, DECK_Y + 0.05, FRONT_Z, FRONT_Z + 0.06)
	RoadsideBuilder._add(sts, chrome, x0 + 0.1, x1 - 0.1, DECK_Y + 0.98, DECK_Y + 1.02, FRONT_Z - 0.16, FRONT_Z - 0.12)
	# Glazed ends.
	_end(sts, alu, white, x0, -1.0)
	_end(sts, alu, white, x1, 1.0)
	# Downlights in the soffit, each throwing a pool onto the pavement, so the walker reads under it.
	var lx := x0 + LIGHT_EVERY * 0.5
	while lx < x1:
		ModernBuilder.cyl(sts, lamp, Vector3(lx, SOFFIT_Y, 1.5), Vector3(lx, SOFFIT_Y + 0.025, 1.5), 0.2, 0.2, 12)
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
	# A warm wash inside, so the passengers, the ceiling and the mullions read from the street.
	var ix := x0 + 5.0
	while ix < x1 - 2.0:
		var om := OmniLight3D.new()
		om.light_color = Color(1.0, 0.94, 0.84)
		om.light_energy = 1.4
		om.omni_range = 7.0
		om.light_volumetric_fog_energy = 0.3
		om.position = Vector3(ix, GLASS_TOP - 0.7, 1.6)
		b.root.add_child(om)
		ix += 13.0
	# Columns: white, tapered to a slim foot in a chrome shoe.
	for cx in column_xs(x0, x1, crossings, b.data.get("props", [])):
		ModernBuilder.cyl(sts, chrome, Vector3(cx, 0.0, COLUMN_Z), Vector3(cx, 0.3, COLUMN_Z), 0.15, 0.115, 14)
		ModernBuilder.cyl(sts, white, Vector3(cx, 0.3, COLUMN_Z), Vector3(cx, SOFFIT_Y, COLUMN_Z), 0.1, 0.17, 14)
	ModernBuilder._commit(b, sts)
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
	var prof := PackedVector2Array([Vector2(FRONT_Z + 0.0, DECK_Y), Vector2(FRONT_Z + 0.07, DECK_Y),
		Vector2(TOP_Z + 0.07, GLASS_TOP), Vector2(TOP_Z + 0.0, GLASS_TOP)])
	ViaductBuilder.loft_into(RailwayBuilder._st(sts, mat), [[x - w * 0.5, prof], [x + w * 0.5, prof]])


## A glazed end: a slim white post at the wall, a mullion at the front and a pane across between them.
func _end(sts: Dictionary, alu: Material, white: Material, ex: float, s: float) -> void:
	RoadsideBuilder._add(sts, white, ex - 0.05, ex + 0.05, DECK_Y, GLASS_TOP, 0.0, 0.14)
	_lean_bar(sts, alu, ex, 0.07)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [Vector3(ex, DECK_Y, 0.14), Vector3(ex, DECK_Y, FRONT_Z), Vector3(ex, GLASS_TOP, TOP_Z), Vector3(ex, GLASS_TOP, 0.14)]
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


## A passenger's cloth: its colour, glowing a little so it carries through the tinted glass at night.
func _cloth(key: String, col: Color) -> StandardMaterial3D:
	var m := b._mat("skyway_cloth_" + key, col, 0.85)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.4
	return m


## A few people walking the gallery: coats and frocks in the colours of the day, hats, a case in hand.
func _passengers(x0: float, x1: float) -> void:
	var n := int((x1 - x0) / 9.0)
	if n <= 0:
		return
	var node := Node3D.new()
	node.set_script(load("res://src/level/skyway_walkers.gd"))
	b.root.add_child(node)
	var coats := [Color(0.62, 0.5, 0.33), Color(0.13, 0.17, 0.34), Color(0.58, 0.12, 0.1), Color(0.42, 0.42, 0.45),
		Color(0.1, 0.38, 0.4), Color(0.8, 0.74, 0.58), Color(0.72, 0.5, 0.12)]
	var dark := _cloth("dark", Color(0.07, 0.07, 0.09))
	var skin := _cloth("skin", Color(0.74, 0.55, 0.43))
	var body := CapsuleMesh.new()
	body.radius = 0.2
	body.height = 1.0
	var legs := CapsuleMesh.new()
	legs.radius = 0.13
	legs.height = 0.95
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.16
	skirt.bottom_radius = 0.3
	skirt.height = 0.62
	skirt.radial_segments = 10
	skirt.rings = 1
	var head := SphereMesh.new()
	head.radius = 0.11
	head.height = 0.24
	var crown := CylinderMesh.new()
	crown.top_radius = 0.1
	crown.bottom_radius = 0.12
	crown.height = 0.11
	crown.radial_segments = 10
	crown.rings = 1
	var brim := CylinderMesh.new()
	brim.top_radius = 0.19
	brim.bottom_radius = 0.19
	brim.height = 0.015
	brim.radial_segments = 12
	brim.rings = 1
	for i in n:
		var r := b._lot_hash(x0 + i * 9.0, "skyway_walker")
		var coat := _cloth("coat_%d" % (r % coats.size()), coats[r % coats.size()])
		var fig := Node3D.new()
		var frock := r % 3 == 1
		_part(fig, legs, skin if frock else dark, Vector3(0, 0.48, 0), Vector3(1.0, 1.0, 0.75))
		_part(fig, body, coat, Vector3(0, 1.02, 0), Vector3(1.0, 1.0, 0.7))
		if frock:
			_part(fig, skirt, coat, Vector3(0, 0.72, 0), Vector3(1.0, 1.0, 0.8))
		_part(fig, head, skin, Vector3(0.02, 1.62, 0), Vector3.ONE)
		if r % 4 != 2:   # a hat: a trilby, or a pillbox in the frock's colour
			_part(fig, crown, coat if frock else dark, Vector3(0.02, 1.74, 0), Vector3.ONE)
			if not frock:
				_part(fig, brim, dark, Vector3(0.03, 1.69, 0), Vector3.ONE)
		if r % 2 == 0:   # a suitcase
			b._box(Vector3(0.45, 0.32, 0.14), Vector3(0.05, 0.42, 0.26), _cloth("case", Color(0.4, 0.26, 0.14)), fig)
		fig.position = Vector3(x0 + (i + 0.5) * (x1 - x0) / n, DECK_Y, 0.9 + float(r % 5) * 0.32)
		node.add_child(fig)
		node.call("add_walker", fig, x0 + 0.6, x1 - 0.6, (0.6 + float(r % 7) * 0.12) * (1.0 if r % 2 == 0 else -1.0))


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
