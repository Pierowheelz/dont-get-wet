class_name Umbrella
extends Node3D
## Procedural umbrella. Local space: grip/handle at origin, shaft along +Y, canopy apex at SHAFT_LEN.
## `open` (0..1) drives the rib angle, so a half-open umbrella really is smaller and lower; the
## convex collider on the umbrella physics layer is rebuilt from the same geometry so the rain model
## sees exactly what the player sees.

const SHAFT_LEN := 0.75
const RIBS := 8
const RING_STEPS := 7
const ANGLE_OPEN := deg_to_rad(72.0)
const ANGLE_CLOSED := deg_to_rad(174.0)
const UMBRELLA_LAYER := 1 << 3

@export var canopy_color := Color(0.58, 0.1, 0.09)   # oxblood: reads against dark streets

var open := 0.0
var radius := 0.62          # rim radius when fully open
var droop := 0.0
var _built_key := Vector3(-1, -1, -1)
var _ready_done := false
var _sway_t := 0.0

var _canopy: MeshInstance3D
var _shaft: MeshInstance3D
var _handle: MeshInstance3D
var _body: StaticBody3D
var _shape: ConvexPolygonShape3D
var _col: CollisionShape3D
var _canopy_mat: StandardMaterial3D
var _pivot: Node3D            # rotates for droop sway


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_canopy_mat = StandardMaterial3D.new()
	_canopy_mat.albedo_color = canopy_color
	_canopy_mat.roughness = 0.28
	_canopy_mat.metallic_specular = 0.7
	_canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_canopy_mat.vertex_color_use_as_albedo = true
	_canopy_mat.rim_enabled = true
	_canopy_mat.rim = 0.35
	_canopy_mat.rim_tint = 0.3
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.78, 0.78, 0.8)
	metal.metallic = 0.9
	metal.roughness = 0.3
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.17, 0.08)
	wood.roughness = 0.45

	_canopy = MeshInstance3D.new()
	_canopy.material_override = _canopy_mat
	_pivot.add_child(_canopy)

	_shaft = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.016
	cyl.bottom_radius = 0.018
	cyl.height = SHAFT_LEN + 0.12
	cyl.radial_segments = 10
	_shaft.mesh = cyl
	_shaft.position.y = (SHAFT_LEN + 0.12) * 0.5 - 0.02
	_shaft.material_override = metal
	_pivot.add_child(_shaft)

	# J-shaped handle below the grip.
	_handle = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.035
	torus.outer_radius = 0.058
	torus.rings = 16
	torus.ring_segments = 8
	_handle.mesh = torus
	_handle.rotation = Vector3(PI * 0.5, 0, 0)
	_handle.position = Vector3(-0.046, -0.06, 0)
	_handle.material_override = wood
	_pivot.add_child(_handle)
	var grip_cyl := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.016
	gc.bottom_radius = 0.016
	gc.height = 0.14
	grip_cyl.mesh = gc
	grip_cyl.position.y = 0.0
	grip_cyl.material_override = wood
	_pivot.add_child(grip_cyl)

	_body = StaticBody3D.new()
	_body.collision_layer = UMBRELLA_LAYER
	_body.collision_mask = 0
	_shape = ConvexPolygonShape3D.new()
	_shape.points = PackedVector3Array([Vector3(0, SHAFT_LEN, 0), Vector3(0.1, SHAFT_LEN - 0.1, 0),
		Vector3(-0.1, SHAFT_LEN - 0.1, 0.05), Vector3(0, SHAFT_LEN - 0.1, -0.1)])
	_col = CollisionShape3D.new()
	_col.shape = _shape
	_body.add_child(_col)
	_pivot.add_child(_body)
	_rebuild()


## p_open is the umbrella's overall open amount; the canopy starts spreading once the arm is up.
func set_state(p_open: float, p_radius: float, p_droop: float) -> void:
	open = clampf((p_open - 0.12) / 0.88, 0.0, 1.0)
	radius = p_radius
	droop = clampf(p_droop, 0.0, 1.0)


func _process(delta: float) -> void:
	_sway_t += delta
	# Exhausted droop: canopy sags to one side and wobbles.
	var sway := (sin(_sway_t * 2.3) * 0.22 + sin(_sway_t * 5.1) * 0.08) * droop
	_pivot.rotation = Vector3(sway * 0.4, 0, sway - droop * 0.35)
	var key := Vector3(snappedf(open, 0.02), snappedf(radius, 0.01), snappedf(droop, 0.05))
	if key != _built_key:
		_built_key = key
		_rebuild()


func _rebuild() -> void:
	var t := ease(open, -1.6)
	var ang := lerpf(ANGLE_CLOSED, ANGLE_OPEN, t)
	# droop crumples the canopy a little (smaller effective radius)
	var cover_scale := lerpf(1.0, Tun.f("umbrella_droop_coverage") if is_inside_tree() else 0.65, droop)
	var rib_len := radius / sin(ANGLE_OPEN) * cover_scale
	var apex := Vector3(0, SHAFT_LEN, 0)
	# Vertices: grid [rib_index_interp][ring] where rib directions interpolate around the shaft.
	var segs := RIBS * 3
	var rows: Array = []
	for s in segs + 1:
		var a := TAU * float(s) / segs
		var rib_phase := fmod(float(s), 3.0) / 3.0   # 0 at a rib, sag between ribs
		var sag := sin(rib_phase * PI) * 0.06 * t
		var dir_h := Vector3(cos(a), 0, sin(a))
		var row: Array = []
		for r in RING_STEPS + 1:
			var u := float(r) / RING_STEPS
			# curve: ribs bend downward toward the tip when open
			var local_ang := ang + u * u * 0.35 * t
			var d := sin(local_ang) * dir_h + Vector3(0, cos(local_ang), 0)
			var p := apex + d * rib_len * u
			p.y -= sag * u * u            # scallop between ribs
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
			var d2: Vector3 = rows[s][r + 1]
			var edge := 1.0 if r == RING_STEPS - 1 else 0.0
			st.set_color(Color(0.72, 0.72, 0.72).lerp(Color(1.0, 0.95, 0.9), edge))
			st.set_uv(Vector2(float(s) / segs, float(r) / RING_STEPS))
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(a)
			st.add_vertex(d2)
			st.add_vertex(c)
	st.generate_normals()
	_canopy.mesh = st.commit()

	# Collider: apex + rim ring + mid ring (a solid cap).
	var pts := PackedVector3Array()
	pts.append(apex + Vector3(0, 0.02, 0))
	for s in range(0, segs, 2):
		pts.append(rows[s][RING_STEPS])
		pts.append(rows[s][RING_STEPS / 2])
	if open >= 0.05:
		_shape.points = pts
	_col.disabled = open < 0.05


## World-space centre of the canopy rim and its approximate radius (used by the autopilot & FX).
func canopy_center() -> Vector3:
	return _canopy.global_transform * Vector3(0, SHAFT_LEN - 0.15, 0)


func current_radius() -> float:
	var t := ease(open, -1.6)
	return sin(lerpf(ANGLE_CLOSED, ANGLE_OPEN, t)) * radius / sin(ANGLE_OPEN)
