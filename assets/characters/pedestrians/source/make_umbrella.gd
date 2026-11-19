extends SceneTree
## Generates the static open-umbrella canopy mesh used by NPC pedestrians (same construction as
## src/player/umbrella.gd at open = 1) and its wooden crook handle. Run: godot --headless --path . -s res://assets/characters/pedestrians/source/make_umbrella.gd
const SHAFT_LEN := 0.75
const RIBS := 8
const RING_STEPS := 7
const ANGLE_OPEN := deg_to_rad(72.0)

func _initialize() -> void:
	var radius := 0.56
	var rib_len := radius / sin(ANGLE_OPEN)
	var apex := Vector3(0, SHAFT_LEN, 0)
	var segs := RIBS * 3
	var rows: Array = []
	for s in segs + 1:
		var a := TAU * float(s) / segs
		var rib_phase := fmod(float(s), 3.0) / 3.0
		var sag := sin(rib_phase * PI) * 0.06
		var dir_h := Vector3(cos(a), 0, sin(a))
		var row: Array = []
		for r in RING_STEPS + 1:
			var u := float(r) / RING_STEPS
			var la := ANGLE_OPEN + u * u * 0.35
			var p := apex + (sin(la) * dir_h + Vector3(0, cos(la), 0)) * rib_len * u
			p.y -= sag * u * u
			p -= dir_h * sag * 0.5 * u * u
			row.append(p)
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segs:
		for r in RING_STEPS:
			var a: Vector3 = rows[s][r]
			var b: Vector3 = rows[s + 1][r]
			var c: Vector3 = rows[s + 1][r + 1]
			var d: Vector3 = rows[s][r + 1]
			for v in [a, c, b, a, d, c]:
				st.set_uv(Vector2(0, 0))
				st.add_vertex(v)
	st.generate_normals()
	var canopy := st.commit()
	# Ribs: thin dark lines under the canopy, one per rib.
	var rs := SurfaceTool.new()
	rs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in RIBS:
		var s := k * 3
		for r in RING_STEPS:
			var p0: Vector3 = rows[s][r] - Vector3(0, 0.004, 0)
			var p1: Vector3 = rows[s][r + 1] - Vector3(0, 0.004, 0)
			var side := (p1 - p0).cross(Vector3.UP).normalized() * 0.004
			for v in [p0 - side, p1 - side, p1 + side, p0 - side, p1 + side, p0 + side]:
				rs.add_vertex(v)
	rs.generate_normals()
	ResourceSaver.save(_crook(), "res://assets/characters/pedestrians/umbrella/crook.res")
	ResourceSaver.save(canopy, "res://assets/characters/pedestrians/umbrella/canopy.res")
	ResourceSaver.save(rs.commit(), "res://assets/characters/pedestrians/umbrella/ribs.res")
	print("saved umbrella meshes")
	quit()


## The handle: a straight wooden grip through the fist, bending into a J crook below it (toward +X).
func _crook() -> ArrayMesh:
	const R := 0.013
	const BEND := 0.042
	const SIDES := 8
	var path: Array = [Vector3(0, 0.075, 0), Vector3(0, -0.07, 0)]
	for i in range(1, 11):
		var a := PI + (PI + 0.35) * float(i) / 10.0
		path.append(Vector3(BEND + cos(a) * BEND, -0.07 + sin(a) * BEND, 0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rings: Array = []
	for i in path.size():
		var p: Vector3 = path[i]
		var fwd: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side := fwd.cross(Vector3(0, 0, 1)).normalized()
		var ring: Array = []
		for k in SIDES:
			var a := TAU * float(k) / SIDES
			ring.append(p + (side * cos(a) + Vector3(0, 0, 1) * sin(a)) * R)
		rings.append(ring)
	for i in path.size() - 1:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			for v in [rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i + 1][k]]:
				st.add_vertex(v)
	for e in [0, path.size() - 1]:       # flat ends
		for k in range(1, SIDES - 1):
			var tri: Array = [rings[e][0], rings[e][k], rings[e][k + 1]]
			if e == 0:
				tri.reverse()
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()
