class_name ViaductBuilder
extends RefCounted
## Static geometry of a level's monorail: the beam along the whole track, the pillars that carry
## it, its lamps, and the deck spans hung off its back (cover). Runs inside LevelBuilder.build
## (possibly on a worker thread), so it only adds nodes. The moving trains and the wash live in
## ViaductTrains.

const PILLAR_Z := (Track.BEAM_Z0 + Track.BEAM_Z1) * 0.5
const PILLAR_STEP := 14.0
const LAMP_EVERY := 2           # pillars per beam lamp: about the old lamp-post spacing
const GIRDER_STEP := 2.5
const GIRDER_Y := 3.12          # foot of a girder at the fascia; still above the signs under the deck
const FASCIA_Y0 := 3.2
const FASCIA_Y1 := 3.78         # just under the train's back skirt (Track.TRAIN_Y)
const DRIP_CHUNK := 30.0        # drip emitters stay short so off-screen ones are culled
const BEAM_DRIP := 0.33         # the beam's drip line is light and sparse: the only drip along the viaduct

var b: LevelBuilder
var paint: Material
var chrome: Material


func build(p_builder: LevelBuilder, tr: Track) -> void:
	b = p_builder
	paint = b._mat("deck_paint", Color(0.7, 0.67, 0.6), 0.75)
	chrome = b._material_res("chrome", b._mat("chrome_fb", Color(0.85, 0.86, 0.88), 0.1, 1.0))
	var mid := (tr.x0 + tr.x1) * 0.5
	var span := tr.x1 - tr.x0
	# The beam in cross-section (z, y), bevelled along its underside.
	var z0 := Track.BEAM_Z0
	var z1 := Track.BEAM_Z1
	b.root.add_child(extrude(PackedVector2Array([Vector2(z0 + 0.1, Track.BEAM_Y), Vector2(z1 - 0.1, Track.BEAM_Y),
		Vector2(z1, Track.BEAM_Y + 0.12), Vector2(z1, Track.BEAM_TOP), Vector2(z0, Track.BEAM_TOP),
		Vector2(z0, Track.BEAM_Y + 0.12)]), tr.x0, tr.x1, paint))
	# The guide rails the bogies' side wheels run on, and a neon line along the soffit.
	for z in [z0 - 0.01, z1 + 0.01]:
		b._box(Vector3(span, 0.1, 0.02), Vector3(mid, Track.BEAM_TOP - 0.42, z), chrome)
	b._box(Vector3(span, 0.04, 0.04), Vector3(mid, Track.BEAM_Y + 0.13, z1 + 0.015), chrome)
	var tube := b._box(Vector3(span, 0.03, 0.03), Vector3(mid, Track.BEAM_Y - 0.02, (z0 + z1) * 0.5),
		b._neon_mat(Color(0.25, 1.0, 0.92), 2.2))
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dx := tr.x0
	while dx < tr.x1:
		b._drips(dx, minf(dx + DRIP_CHUNK, tr.x1), Track.BEAM_Y + 0.1, z1 + 0.04, BEAM_DRIP)
		dx += DRIP_CHUNK
	for d in tr.decks:
		_deck(d[0], d[1])
	var lamp := b._neon_mat(Color(0.85, 0.95, 1.0), 1.6)
	var i := 0
	var px := ceilf(tr.x0 / PILLAR_STEP) * PILLAR_STEP
	while px <= tr.x1:
		if not _in_crossing(px):
			_pillar(px)
		if i % LAMP_EVERY == 0 and not tr.deck_at(px):
			var head := b._box(Vector3(0.9, 0.06, 0.2), Vector3(px, Track.BEAM_Y - 0.03, z0 + 0.05), lamp)
			head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b._lamp_light(px, Track.BEAM_Y - 0.12, z0)
		i += 1
		px += PILLAR_STEP


## A deck span from xa to xb, hung off the back of the beam: a solid slab with an enamel fascia,
## haunched girders beneath it and lamps in its soffit. The fascia hangs only as low as the slab's
## back edge already hides, so the signs dropped below the deck (LevelBuilder._sign_under_deck) still show.
func _deck(xa: float, xb: float) -> void:
	var w := xb - xa
	var xm := (xa + xb) * 0.5
	var z0 := Track.DECK_Z0
	var z1 := Track.DECK_Z1
	var y0 := Track.DECK_Y
	var y1 := Track.DECK_TOP
	var zc := (z0 + z1) * 0.5
	b._cover_box(Vector3(w, y1 - y0, z1 - z0), Transform3D(Basis(), Vector3(xm, (y0 + y1) * 0.5, zc)))
	b._box(Vector3(w, y1 - y0, z1 - z0), Vector3(xm, (y0 + y1) * 0.5, zc), b._mat("deck_soffit", Color(0.36, 0.35, 0.34), 0.9))
	b._box(Vector3(w, y1 - y0, 0.14), Vector3(xm, (y0 + y1) * 0.5, z0 + 0.07), paint)
	var enamel := b._mat("deck_fascia", Color(0.86, 0.82, 0.72), 0.35, 0.1)
	enamel.emission_enabled = true
	enamel.emission = enamel.albedo_color
	enamel.emission_energy_multiplier = 0.18
	b._box(Vector3(w, FASCIA_Y1 - FASCIA_Y0, 0.16), Vector3(xm, (FASCIA_Y0 + FASCIA_Y1) * 0.5, z1 - 0.08), enamel)
	var band := b._box(Vector3(w - 0.3, 0.07, 0.02), Vector3(xm, FASCIA_Y1 - 0.13, z1 + 0.005), b._neon_mat(Color(1.0, 0.62, 0.25), 1.4))
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for y in [FASCIA_Y0 + 0.01, FASCIA_Y1 - 0.01]:
		b._box(Vector3(w, 0.04, 0.04), Vector3(xm, y, z1 + 0.01), chrome)
	var tube := b._box(Vector3(w - 0.4, 0.035, 0.035), Vector3(xm, FASCIA_Y0 + 0.06, z1 + 0.03), b._neon_mat(Color(0.25, 1.0, 0.92), 2.2))
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rib := PackedVector2Array([Vector2(z0 + 0.14, y0), Vector2(z1 - 0.16, y0), Vector2(z1 - 0.16, GIRDER_Y),
		Vector2(z0 + 0.14, y0 - 0.06)])
	var rx := xa + GIRDER_STEP * 0.5
	while rx < xb - 0.6:
		b.root.add_child(extrude(rib, rx - 0.07, rx + 0.07, paint))
		b._box(Vector3(0.18, 0.025, 0.2), Vector3(rx, GIRDER_Y + 0.01, z1 - 0.26), chrome)
		b._box(Vector3(0.08, FASCIA_Y1 - FASCIA_Y0 - 0.06, 0.03), Vector3(rx, (FASCIA_Y0 + FASCIA_Y1) * 0.5, z1 + 0.01), chrome)
		rx += GIRDER_STEP
	for hx in [xa + 0.15, xb - 0.15]:
		b.root.add_child(extrude(rib, hx - 0.15, hx + 0.15, paint))
	var lamp := b._neon_mat(Color(0.85, 0.95, 1.0), 1.6)
	var lx := xa + GIRDER_STEP
	while lx < xb - 1.0:
		var bar := b._box(Vector3(1.2, 0.05, 0.12), Vector3(lx, y0 - 0.03, 1.7), lamp)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var om := OmniLight3D.new()
		om.light_color = Color(0.72, 0.9, 1.0)
		om.light_energy = 0.9
		om.omni_range = 5.0
		om.omni_attenuation = 1.3
		om.light_volumetric_fog_energy = 0.4
		om.position = Vector3(lx, y0 - 0.35, 1.9)
		b.root.add_child(om)
		lx += GIRDER_STEP * 2.0


## A station stair flight against the shopfronts, from the pavement at x + STAIR_RUN up to the deck at
## x. Dressing: it sits behind the walker's line, and the space under its high end shelters a booth.
const STAIR_RUN := 6.0
const STAIR_Z0 := 0.12
const STAIR_Z1 := 1.0


func station_stairs(p_builder: LevelBuilder, x: float) -> void:
	b = p_builder
	var paint := b._mat("deck_paint", Color(0.7, 0.67, 0.6), 0.75)
	var tread := b._mat("stair_tread", Color(0.3, 0.31, 0.33), 0.6, 0.3)
	var chrome := b._material_res("chrome", b._mat("chrome_fb", Color(0.85, 0.86, 0.88), 0.1, 1.0))
	var steps := 24
	var rise := Track.DECK_Y / steps
	var run := STAIR_RUN / steps
	var zc := (STAIR_Z0 + STAIR_Z1) * 0.5
	var zw := STAIR_Z1 - STAIR_Z0
	for i in steps:
		var sx := x + STAIR_RUN - (i + 0.5) * run
		b._box(Vector3(run + 0.01, rise, zw), Vector3(sx, (i + 0.5) * rise, zc), paint)
		b._box(Vector3(run + 0.01, 0.04, zw + 0.02), Vector3(sx, (i + 1) * rise - 0.02, zc), tread)
	var slope := atan2(Track.DECK_Y, STAIR_RUN)
	var length := sqrt(STAIR_RUN * STAIR_RUN + Track.DECK_Y * Track.DECK_Y)
	for z in [STAIR_Z1 + 0.06]:
		var stringer := b._box(Vector3(length, 0.26, 0.1), Vector3(x + STAIR_RUN * 0.5, Track.DECK_Y * 0.5 - 0.45, z), tread)
		stringer.rotation.z = -slope
		var rail := b._box(Vector3(length, 0.05, 0.05), Vector3(x + STAIR_RUN * 0.5, Track.DECK_Y * 0.5 + 0.95, z), chrome)
		rail.rotation.z = -slope
		var post := 1
		while post < 6:
			var px := x + STAIR_RUN * post / 6.0
			var py := Track.DECK_Y * (1.0 - float(post) / 6.0)
			b._box(Vector3(0.04, 0.95, 0.04), Vector3(px, py + 0.47, z), chrome)
			post += 1
	var neon := b._neon_mat(Color(1.0, 0.3, 0.7), 2.0)
	var tube := b._box(Vector3(length - 0.6, 0.03, 0.03), Vector3(x + STAIR_RUN * 0.5, Track.DECK_Y * 0.5 - 0.3, STAIR_Z1 + 0.12), neon)
	tube.rotation.z = -slope
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _in_crossing(x: float) -> bool:
	for c in b.data.get("crossings", []):
		if x > float(c["x"]) - 0.6 and x < float(c["x"]) + float(c["w"]) + 0.6:
			return true
	return false


## A googie column under the beam: slim at the foot, flaring into the beam, with chrome collars.
func _pillar(x: float) -> void:
	var h := Track.BEAM_Y
	var flare := 0.4
	_cylinder(0.14, 0.2, 0.35, h - flare, x, paint)
	_cylinder(0.2, 0.33, h - flare, h, x, paint)
	_cylinder(0.24, 0.19, 0.0, 0.35, x, chrome)
	for y in [1.9, h - flare]:
		var r := lerpf(0.14, 0.2, (y - 0.35) / (h - flare - 0.35)) + 0.025
		_cylinder(r, r, y - 0.035, y + 0.035, x, chrome)


func _cylinder(r0: float, r1: float, y0: float, y1: float, x: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = y1 - y0
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(x, (y0 + y1) * 0.5, PILLAR_Z)
	b.root.add_child(mi)


## A prism along x from a convex (z, y) profile, flat-shaded, with end caps.
static func extrude(profile: PackedVector2Array, xa: float, xb: float, mat: Material) -> MeshInstance3D:
	return loft([[xa, profile], [xb, profile]], mat)


## A flat-shaded solid through (z, y) cross-sections placed along x, all with the same point count
## and winding, capped at both ends. Each profile must be convex.
static func loft(sections: Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	loft_into(st, sections)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func loft_into(st: SurfaceTool, sections: Array) -> void:
	var rings: Array = []
	for sec in sections:
		var ring: Array = []
		for p: Vector2 in sec[1]:
			ring.append(Vector3(sec[0], p.y, p.x))
		rings.append(ring)
	var n: int = rings[0].size()
	for k in rings.size() - 1:
		var ra: Array = rings[k]
		var rb: Array = rings[k + 1]
		var axis := (_centroid(ra) + _centroid(rb)) * 0.5
		for i in n:
			var j := (i + 1) % n
			var q := [ra[i], rb[i], rb[j], ra[j]]
			var nrm: Vector3 = (q[2] - q[0]).cross(q[3] - q[1]).normalized()
			if nrm.dot((q[0] + q[1] + q[2] + q[3]) * 0.25 - axis) < 0.0:
				nrm = -nrm
			_tri(st, q[0], q[1], q[2], nrm)
			_tri(st, q[0], q[2], q[3], nrm)
	for end in [[rings[0], rings[1]], [rings[-1], rings[-2]]]:
		var ring: Array = end[0]
		var nrm := (_centroid(ring) - _centroid(end[1])).normalized()
		for i in range(1, n - 1):
			_tri(st, ring[0], ring[i], ring[i + 1], nrm)


static func _centroid(ring: Array) -> Vector3:
	var c := Vector3.ZERO
	for v: Vector3 in ring:
		c += v
	return c / ring.size()


## One triangle facing along nrm (Godot's front faces wind clockwise as seen from outside).
static func _tri(st: SurfaceTool, a: Vector3, c1: Vector3, c2: Vector3, nrm: Vector3) -> void:
	var v := [a, c1, c2] if nrm.dot((c1 - a).cross(c2 - a)) < 0.0 else [a, c2, c1]
	for p: Vector3 in v:
		st.set_normal(nrm)
		st.set_uv(Vector2(p.x, p.y + p.z) * 0.5)
		st.add_vertex(p)
