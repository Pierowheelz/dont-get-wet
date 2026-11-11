class_name ViaductBuilder
extends RefCounted
## Static geometry of one viaduct span: the deck (cover), its soffit lights and the pillars along
## the kerb. Runs inside LevelBuilder.build (possibly on a worker thread), so it only adds nodes.
## The moving train and the wash live in ViaductTrains.

const PILLAR_Z := 3.05
const PILLAR_STEP := 14.0
const RIB_STEP := 2.0

var b: LevelBuilder


func build(p_builder: LevelBuilder, v: Viaduct) -> void:
	b = p_builder
	var w := v.x1 - v.x0
	var paint := b._mat("deck_paint", Color(0.7, 0.67, 0.6), 0.75)
	var chrome := b._material_res("chrome", b._mat("chrome_fb", Color(0.85, 0.86, 0.88), 0.1, 1.0))
	var shade := b._mat("deck_soffit", Color(0.36, 0.37, 0.4), 0.8)
	# Deck in cross-section (z, y): flat soffit, a chamfered nose toward the street, flat top.
	var deck := PackedVector2Array([
		Vector2(Viaduct.DECK_Z0, Viaduct.DECK_Y), Vector2(Viaduct.DECK_Z1 - 0.35, Viaduct.DECK_Y),
		Vector2(Viaduct.DECK_Z1, Viaduct.DECK_Y + 0.25), Vector2(Viaduct.DECK_Z1, Viaduct.DECK_TOP - 0.15),
		Vector2(Viaduct.DECK_Z1 - 0.15, Viaduct.DECK_TOP), Vector2(Viaduct.DECK_Z0, Viaduct.DECK_TOP)])
	b.root.add_child(extrude(deck, v.x0, v.x1, paint))
	# The guideway beam the train straddles.
	b.root.add_child(extrude(PackedVector2Array([Vector2(1.25, Viaduct.DECK_TOP), Vector2(2.05, Viaduct.DECK_TOP),
		Vector2(2.05, Viaduct.DECK_TOP + 0.7), Vector2(1.95, Viaduct.DECK_TOP + 0.8),
		Vector2(1.35, Viaduct.DECK_TOP + 0.8), Vector2(1.25, Viaduct.DECK_TOP + 0.7)]), v.x0 - 30.0, v.x1 + 30.0, paint))
	b._cover_box(Vector3(w, Viaduct.DECK_TOP - Viaduct.DECK_Y, Viaduct.DECK_Z1 - Viaduct.DECK_Z0),
		Transform3D(Basis(), Vector3((v.x0 + v.x1) * 0.5, (Viaduct.DECK_Y + Viaduct.DECK_TOP) * 0.5,
		(Viaduct.DECK_Z0 + Viaduct.DECK_Z1) * 0.5)))
	# Chrome trim along the chamfer and a neon tube under it, so the deck edge reads from below.
	b._box(Vector3(w, 0.05, 0.06), Vector3((v.x0 + v.x1) * 0.5, Viaduct.DECK_Y + 0.02, Viaduct.DECK_Z1 - 0.37), chrome)
	var neon := b._neon_mat(Color(0.25, 1.0, 0.92), 2.2)
	var tube := b._box(Vector3(w - 0.4, 0.035, 0.035), Vector3((v.x0 + v.x1) * 0.5, Viaduct.DECK_Y - 0.03, Viaduct.DECK_Z1 - 0.5), neon)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Soffit ribs and lamps.
	var rx := v.x0 + 1.0
	while rx < v.x1 - 0.5:
		b._box(Vector3(0.22, 0.16, Viaduct.DECK_Z1 - Viaduct.DECK_Z0 - 0.45), Vector3(rx, Viaduct.DECK_Y - 0.08,
			(Viaduct.DECK_Z0 + Viaduct.DECK_Z1 - 0.45) * 0.5), shade)
		rx += RIB_STEP
	var lamp := b._neon_mat(Color(0.85, 0.95, 1.0), 1.6)
	var lx := v.x0 + 3.0
	while lx < v.x1 - 2.0:
		var bar := b._box(Vector3(1.2, 0.05, 0.12), Vector3(lx, Viaduct.DECK_Y - 0.03, 1.7), lamp)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var om := OmniLight3D.new()
		om.light_color = Color(0.72, 0.9, 1.0)
		om.light_energy = 0.9
		om.omni_range = 5.5
		om.omni_attenuation = 1.3
		om.light_volumetric_fog_energy = 0.4
		om.position = Vector3(lx, Viaduct.DECK_Y - 0.35, 1.9)
		b.root.add_child(om)
		lx += 8.0
	b._drips(v.x0 + 0.2, v.x1 - 0.2, Viaduct.DECK_Y + 0.2, Viaduct.DECK_Z1 + 0.04)
	# Pillars at the kerb, evenly spaced so both ends get one; none in a side street's roadway.
	var n := maxi(1, roundi(w / PILLAR_STEP))
	for i in n + 1:
		var px := lerpf(v.x0 + 0.6, v.x1 - 0.6, float(i) / n)
		if not _in_crossing(px):
			_pillar(px, paint, chrome)


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
	var rise := Viaduct.DECK_Y / steps
	var run := STAIR_RUN / steps
	var zc := (STAIR_Z0 + STAIR_Z1) * 0.5
	var zw := STAIR_Z1 - STAIR_Z0
	for i in steps:
		var sx := x + STAIR_RUN - (i + 0.5) * run
		b._box(Vector3(run + 0.01, rise, zw), Vector3(sx, (i + 0.5) * rise, zc), paint)
		b._box(Vector3(run + 0.01, 0.04, zw + 0.02), Vector3(sx, (i + 1) * rise - 0.02, zc), tread)
	var slope := atan2(Viaduct.DECK_Y, STAIR_RUN)
	var length := sqrt(STAIR_RUN * STAIR_RUN + Viaduct.DECK_Y * Viaduct.DECK_Y)
	for z in [STAIR_Z1 + 0.06]:
		var stringer := b._box(Vector3(length, 0.26, 0.1), Vector3(x + STAIR_RUN * 0.5, Viaduct.DECK_Y * 0.5 - 0.45, z), tread)
		stringer.rotation.z = -slope
		var rail := b._box(Vector3(length, 0.05, 0.05), Vector3(x + STAIR_RUN * 0.5, Viaduct.DECK_Y * 0.5 + 0.95, z), chrome)
		rail.rotation.z = -slope
		var post := 1
		while post < 6:
			var px := x + STAIR_RUN * post / 6.0
			var py := Viaduct.DECK_Y * (1.0 - float(post) / 6.0)
			b._box(Vector3(0.04, 0.95, 0.04), Vector3(px, py + 0.47, z), chrome)
			post += 1
	var neon := b._neon_mat(Color(1.0, 0.3, 0.7), 2.0)
	var tube := b._box(Vector3(length - 0.6, 0.03, 0.03), Vector3(x + STAIR_RUN * 0.5, Viaduct.DECK_Y * 0.5 - 0.3, STAIR_Z1 + 0.12), neon)
	tube.rotation.z = -slope
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _in_crossing(x: float) -> bool:
	for c in b.data.get("crossings", []):
		if x > float(c["x"]) - 0.6 and x < float(c["x"]) + float(c["w"]) + 0.6:
			return true
	return false


## A googie column: slim at the foot, flaring into the deck, with chrome collars.
func _pillar(x: float, paint: Material, chrome: Material) -> void:
	var h := Viaduct.DECK_Y
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = 0.14
	cm.top_radius = 0.26
	cm.height = h - 0.35
	cm.radial_segments = 16
	cm.rings = 1
	col.mesh = cm
	col.material_override = paint
	col.position = Vector3(x, 0.35 + cm.height * 0.5, PILLAR_Z)
	b.root.add_child(col)
	var plinth := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.bottom_radius = 0.24
	pm.top_radius = 0.19
	pm.height = 0.35
	pm.radial_segments = 16
	pm.rings = 1
	plinth.mesh = pm
	plinth.material_override = chrome
	plinth.position = Vector3(x, 0.175, PILLAR_Z)
	b.root.add_child(plinth)
	for y in [1.9, h - 0.25]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		var r := lerpf(0.14, 0.26, (y - 0.35) / (h - 0.35)) + 0.025
		rm.bottom_radius = r
		rm.top_radius = r
		rm.height = 0.07
		rm.radial_segments = 16
		rm.rings = 1
		ring.mesh = rm
		ring.material_override = chrome
		ring.position = Vector3(x, y, PILLAR_Z)
		b.root.add_child(ring)


## A prism along x from a convex (z, y) profile, flat-shaded, with end caps.
static func extrude(profile: PackedVector2Array, xa: float, xb: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector2.ZERO
	for p in profile:
		c += p
	c /= profile.size()
	for i in profile.size():
		var p := profile[i]
		var q := profile[(i + 1) % profile.size()]
		var e := q - p
		var n2 := Vector2(e.y, -e.x).normalized()
		if n2.dot((p + q) * 0.5 - c) < 0.0:
			n2 = -n2
		var nrm := Vector3(0.0, n2.y, n2.x)
		var v := [Vector3(xa, p.y, p.x), Vector3(xb, p.y, p.x), Vector3(xb, q.y, q.x), Vector3(xa, q.y, q.x)]
		var tri: Array = [0, 1, 2, 0, 2, 3] if nrm.dot((v[1] - v[0]).cross(v[2] - v[0])) < 0.0 else [0, 2, 1, 0, 3, 2]
		for k in tri:
			st.set_normal(nrm)
			st.set_uv(Vector2(v[k].x, v[k].y + v[k].z) * 0.5)
			st.add_vertex(v[k])
	for end in [[xa, -1.0], [xb, 1.0]]:
		var nrm := Vector3(end[1], 0, 0)
		for i in range(1, profile.size() - 1):
			var v := [Vector3(end[0], profile[0].y, profile[0].x), Vector3(end[0], profile[i].y, profile[i].x),
				Vector3(end[0], profile[i + 1].y, profile[i + 1].x)]
			var tri: Array = [0, 1, 2] if nrm.dot((v[1] - v[0]).cross(v[2] - v[0])) < 0.0 else [0, 2, 1]
			for k in tri:
				st.set_normal(nrm)
				st.set_uv(Vector2(v[k].z, v[k].y) * 0.5)
				st.add_vertex(v[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi
