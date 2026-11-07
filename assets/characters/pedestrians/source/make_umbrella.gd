extends SceneTree
## Generates the static open-umbrella canopy mesh used by NPC pedestrians (same construction as
## src/player/umbrella.gd at open = 1). Run: godot --headless --path . -s res://assets/characters/pedestrians/source/make_umbrella.gd
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
	ResourceSaver.save(canopy, "res://assets/characters/pedestrians/umbrella/canopy.res")
	ResourceSaver.save(rs.commit(), "res://assets/characters/pedestrians/umbrella/ribs.res")
	print("saved umbrella meshes")
	quit()
