class_name FinBuilder
extends RefCounted
## Tail fins on rocket-fin canopies (awning frame "fins"), built by LevelBuilder once every lot's
## sign is up. A canopy has one fin toward each end, and two canopies that meet share one on the join.
## A fin runs from the wall out to the front edge: its ridge sweeps up to a tip against the wall, the
## canopy's skin is drawn up to it on both sides, and a neon tube follows the ridge and turns down the
## fascia, with a lamp on the tip.
## The camera looks from below the canopy's top and never sees it, so the ridge reaching the front
## edge and the tube crossing the fascia are what stand the fin on the canopy. The height is at the
## wall because the sign is there: seen from a passing camera, anything tall on the front edge slides
## metres across the facade and over the lettering, and at the wall it hardly moves.
## Runs inside LevelBuilder.build, possibly on a worker thread: it only adds nodes.

const GROUP := &"canopy_fins"
const D := LevelBuilder.AWNING_DEPTH
const TIP := 0.97              # the ridge's height over the roof at the wall
## The ridge from the front edge back to the wall, as (depth, height over the roof).
const RIDGE: Array[Vector2] = [Vector2(D + 0.02, 0.05), Vector2(2.0, 0.1), Vector2(1.6, 0.18), Vector2(1.25, 0.3),
	Vector2(0.95, 0.47), Vector2(0.7, 0.7), Vector2(0.5, 0.88), Vector2(0.36, TIP), Vector2(0.06, TIP)]
const SKIN_FOOT := 0.22        # how far the skin spreads to each side of the ridge at the front edge,
const SKIN_FLARE := 0.43       # and how much further under the tip
const SKIN_ROWS: Array[float] = [0.0, 0.05, 0.12, 0.22, 0.36, 0.54, 0.76, 1.0]
const INSET := SKIN_FOOT + SKIN_FLARE   # an end fin stands this far in, so its skin stays on its canopy
const TUBE := 0.02
## A fin stays out of every sign's way in views up to this wide. Wider still, a fin at the very edge
## of the frame can touch the first letter of its sign.
const VIEW_ASPECT := 3440.0 / 1440.0
const SIGN_MARGIN := 0.12
const MIN_SCALE := 0.4         # a fin its sign would hold lower than this is left off

var _meshes := {}              # roof rise -> ArrayMesh
var _profiles := {}            # [mesh, sign's bottom edge, roof height] -> _profile


## `canopies`: {x, w, wall_y, front_y, tears, glow, cols} per finned canopy. `signs`: each sign's
## face on the facade, as a Rect2 in x and y.
func build(b: LevelBuilder, canopies: Array, signs: Array[Rect2]) -> void:
	for c in canopies:
		var x0: float = c["x"]
		var x1: float = x0 + float(c["w"])
		var before: Array = canopies.filter(func(o: Dictionary) -> bool: return is_equal_approx(float(o["x"]) + float(o["w"]), x0))
		if before.is_empty():
			_fin(b, x0 + INSET, c, c, signs)
		else:
			_fin(b, x0, before[0], c, signs)
		if not canopies.any(func(o: Dictionary) -> bool: return is_equal_approx(float(o["x"]), x1)):
			_fin(b, x1 - INSET, c, c, signs)


## One fin at x, between the canopies whose skin lies to its left and right (the same one, away from a join).
func _fin(b: LevelBuilder, x: float, left: Dictionary, right: Dictionary, signs: Array[Rect2]) -> void:
	if _torn(left, x) or _torn(right, x):
		return
	var wall_y: float = right["wall_y"]
	var mesh := _mesh(float(right["front_y"]) - wall_y)
	var height := 1.0
	for sign in signs:
		height = minf(height, _height_clear_of(sign, mesh, x, wall_y))
	if height < MIN_SCALE:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, _skin(b, left["cols"][0]))
	mi.set_surface_override_material(1, _skin(b, right["cols"][0]))
	mi.set_surface_override_material(2, b._neon_mat((right["glow"] as Color).lerp(Color(1, 1, 1), 0.3), 3.0))
	mi.set_surface_override_material(3, b._neon_mat(Color(1.0, 0.9, 0.75), 3.5))
	mi.position = Vector3(x, wall_y, 0.0)
	mi.scale.y = height
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group(GROUP)
	b.root.add_child(mi)


func _torn(c: Dictionary, x: float) -> bool:
	return (c["tears"] as Array).any(func(t: Array) -> bool:
		return float(c["x"]) + float(t[0]) < x + INSET and float(c["x"]) + float(t[1]) > x - INSET)


## The skin in the fascia's colour. The side of a fin turned from its sign's light would go black
## against the night, so the skin carries a little of its own colour.
func _skin(b: LevelBuilder, col: Color) -> StandardMaterial3D:
	var m := b._mat("fin_skin_%s" % col.to_html(), col.lightened(0.25), 0.3, 0.15)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = col.lightened(0.25)
	m.emission_energy_multiplier = 0.22
	return m


## The tallest a fin at x may stand (as a fraction of its full height) without any part of it
## showing in front of `sign`, from any camera position that has that part in frame.
## A point of the fin at depth z shows against the facade up to (z - SIGN_Z) * tan(half the view)
## to either side of where it stands, however far off the camera is.
func _height_clear_of(sign: Rect2, mesh: ArrayMesh, x: float, wall_y: float) -> float:
	var gap := maxf(sign.position.x - x, x - sign.end.x) - SIGN_MARGIN
	var side := 1 if sign.position.x > x else 2
	var view := tan(deg_to_rad(Tun.f("camera_fov")) * 0.5) * VIEW_ASPECT
	if gap > INSET + D * view:
		return 1.0
	var bottom := floorf((sign.position.y - SIGN_MARGIN) / 0.05) * 0.05
	var key := [mesh, bottom, wall_y]
	if not _profiles.has(key):
		_profiles[key] = _profile(mesh, bottom, wall_y, view)
	for e in _profiles[key]:
		if e[0] >= 1.0:
			break
		if gap <= 0.0 or e[side] > gap:
			return e[0]
	return 1.0


## For points over the fin, lowest first: [the height scale at which the point comes level with the
## sign's bottom edge as the camera sees it, how far right of the fin it can show, how far left].
func _profile(mesh: ArrayMesh, sign_bottom: float, wall_y: float, view: float) -> Array:
	var cam_y := Tun.f("camera_height")
	var cam_z := Tun.f("player_z") + Tun.f("camera_distance")
	var out := []
	for si in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size(), 3):
			for p: Vector3 in [v[i], v[i + 1], v[i + 2], (v[i] + v[i + 1]) * 0.5, (v[i + 1] + v[i + 2]) * 0.5, (v[i + 2] + v[i]) * 0.5]:
				if p.y <= 0.001:
					continue
				var level_y := cam_y + (sign_bottom - cam_y) * (cam_z - p.z) / (cam_z - LevelBuilder.SIGN_Z)
				var reach := (p.z - LevelBuilder.SIGN_Z) * view
				out.append([(level_y - wall_y) / p.y, p.x + reach, -p.x + reach])
	out.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
	return out


## Surfaces: the skin left of the ridge, the skin right of it, the neon tube, the tip lamp. The origin
## is on the roof at the wall; `rise` is how much higher the roof stands at its front edge.
func _mesh(rise: float) -> ArrayMesh:
	if _meshes.has(rise):
		return _meshes[rise]
	var at := func(i: int, u: float, side: float) -> Vector3:
		var r: Vector2 = RIDGE[i]
		return Vector3(side * u * (SKIN_FOOT + SKIN_FLARE * r.y / TIP), r.y * (1.0 - u) * (1.0 - u) + rise * r.x / D, r.x)
	var mesh: ArrayMesh = null
	for side: float in [-1.0, 1.0]:
		var st := _surface(0)
		for i in RIDGE.size() - 1:
			for k in SKIN_ROWS.size() - 1:
				_quad(st, at.call(i, SKIN_ROWS[k], side), at.call(i, SKIN_ROWS[k + 1], side),
					at.call(i + 1, SKIN_ROWS[k + 1], side), at.call(i + 1, SKIN_ROWS[k], side))
		st.generate_normals()
		mesh = st.commit(mesh)
	# Up the fascia from the glow strip under it, then back along the ridge to the tip.
	var path := PackedVector3Array([Vector3(0, rise - 0.22, D + 0.075), Vector3(0, rise + 0.06, D + 0.075)])
	for i in RIDGE.size() - 1:
		path.append(at.call(i, 0.0, 1.0) + Vector3(0, TUBE, 0))
	var st := _surface(-1)
	for i in path.size() - 1:
		var dir := (path[i + 1] - path[i]).normalized()
		var up := dir.cross(Vector3.RIGHT) * TUBE
		var ring: Array[Vector3] = [Vector3(TUBE, 0, 0) + up, Vector3(TUBE, 0, 0) - up, Vector3(-TUBE, 0, 0) - up, Vector3(-TUBE, 0, 0) + up]
		var a := path[i] - dir * TUBE * 0.5
		var c := path[i + 1] + dir * TUBE * 0.5
		for k in 4:
			_quad(st, a + ring[k], a + ring[(k + 1) % 4], c + ring[(k + 1) % 4], c + ring[k])
	st.generate_normals()
	mesh = st.commit(mesh)
	st = _surface(-1)
	var lamp: Vector3 = at.call(RIDGE.size() - 2, 0.0, 1.0) + Vector3(0, 0.05, 0.02)
	var around: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]
	for k in 4:
		for pole: Vector3 in [Vector3.UP, Vector3.DOWN]:
			for p: Vector3 in [around[k], pole, around[(k + 1) % 4]]:
				st.add_vertex(lamp + p * 0.05)
	st.generate_normals()
	_meshes[rise] = st.commit(mesh)
	return _meshes[rise]


func _surface(smooth_group: int) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(smooth_group)
	return st


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(p)
