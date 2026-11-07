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
var _rim_r := 0.0

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


# --- open / close choreography (all keyed on the player's overall open amount 0..1) ---------------
# Opening: he leans in and the right arm raises it at ~70° (tipped forward); the left hand reaches in to the runner; only
# then does the canopy spread (to 95% as the hand slides up); the hand lets go and the umbrella
# tilts back to its carried angle while the canopy latches the last 5%. Closing is the reverse, so
# it never starts folding before the hand is back on the shaft.
const HAND_ON := 0.3        # left hand reaches the runner: canopy may start to spread
const HAND_OFF := 0.86      # canopy at 95%: hand leaves the shaft, umbrella tilts back
const OPEN_SPREAD := 0.95


## Canopy spread 0..1 for an overall open amount.
static func canopy_spread(o: float) -> float:
	if o <= HAND_ON:
		return 0.0
	if o < HAND_OFF:
		var t := (o - HAND_ON) / (HAND_OFF - HAND_ON)
		return OPEN_SPREAD * (1.0 - (1.0 - t) * (1.0 - t))   # the push spreads it fast, then it eases in
	return lerpf(OPEN_SPREAD, 1.0, clampf((o - HAND_OFF) / (1.0 - HAND_OFF), 0.0, 1.0))


## 0..1 how far the right arm has raised it (done just as the left hand arrives).
static func arm_raise(o: float) -> float:
	return smoothstep(0.0, HAND_ON - 0.04, o)


## 0..1 the left hand's hold on the shaft (reach in → hold → let go).
static func hand_on_shaft(o: float) -> float:
	return smoothstep(0.08, HAND_ON, o) * (1.0 - smoothstep(HAND_OFF, 1.0, o))


## 0..1 weight of the forward tip: raised at ~60° and held there through the whole opening; it
## swings up to vertical only as the left hand lets go.
static func open_tip(o: float) -> float:
	return 1.0 - smoothstep(HAND_OFF, 1.0, o)


## Forward lean (rad) of the walker's upper body while he opens / closes it: leans in as the arm comes
## up, straightens as the umbrella swings upright. Player.gd leans its rain sample points to match.
const OPEN_LEAN := 0.26          # whole upper body, hinging mostly at the hips
const OPEN_DUCK := 0.3           # extra head/neck pitch on top (ducking in under it)


static func open_lean(o: float) -> float:
	return OPEN_LEAN * arm_raise(o) * open_tip(o)


static func open_duck(o: float) -> float:
	return OPEN_DUCK * arm_raise(o) * open_tip(o)


## p_open is the umbrella's overall open amount (see canopy_spread).
func set_state(p_open: float, p_radius: float, p_droop: float) -> void:
	open = canopy_spread(clampf(p_open, 0.0, 1.0))
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
	# droop crumples the canopy a little (smaller effective radius)
	var cover_scale := lerpf(1.0, Tun.f("umbrella_droop_coverage"), droop)
	# Ribs are arcs: their angle from the shaft runs from a0 at the apex to a1 at the tip, so a
	# fully open umbrella is a taut dome — a crescent when seen side-on. Closed, both fold down.
	var a0 := lerpf(ANGLE_CLOSED, deg_to_rad(86.0), t)
	var a1 := lerpf(ANGLE_CLOSED, deg_to_rad(138.0), t)
	var rib_len := radius / _open_extent() * cover_scale
	var seg_len := rib_len / RING_STEPS
	var apex := Vector3(0, SHAFT_LEN, 0)
	# Fabric is slack while opening/closing and taut when fully open.
	var slack := 0.07 * sin(t * PI) + 0.012 * t
	var segs := RIBS * 3
	var rows: Array = []
	_rim_r = 0.0
	for s in segs + 1:
		var a := TAU * float(s) / segs
		var rib_phase := fmod(float(s), 3.0) / 3.0   # 0 at a rib, sag between ribs
		var sag := sin(rib_phase * PI) * slack
		var dir_h := Vector3(cos(a), 0, sin(a))
		var row: Array = [apex]
		var p := apex
		for r in RING_STEPS:
			var ang := lerpf(a0, a1, (float(r) + 0.5) / RING_STEPS)
			p += (sin(ang) * dir_h + Vector3(0, cos(ang), 0)) * seg_len
			var u := float(r + 1) / RING_STEPS
			var q := p - Vector3(0, sag * u * u, 0) - dir_h * sag * 0.6 * u * u
			row.append(q)
		_rim_r = maxf(_rim_r, Vector2(p.x, p.z).length())
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
	return _rim_r


## Horizontal reach of a unit-length rib when fully open (for sizing ribs to the radius).
static func _open_extent() -> float:
	var h := 0.0
	for r in RING_STEPS:
		h += sin(lerpf(deg_to_rad(86.0), deg_to_rad(138.0), (float(r) + 0.5) / RING_STEPS)) / RING_STEPS
	return h


# --- static canopies for bystanders ----------------------------------------------------------

enum Style { TAUT, LOOSE, INVERTED, TORN }


## Builds a static canopy mesh (grip at origin, shaft along +Y, apex at `apex_y`) in one of a few
## styles, using the same rib-arc construction as the player's umbrella. No collider: bystander
## umbrellas never affect the rain model.
static func canopy_mesh(radius: float, style: int, seed: int, apex_y := SHAFT_LEN) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a0 := deg_to_rad(86.0)
	var a1 := deg_to_rad(138.0)
	var slack := 0.012
	match style:
		Style.LOOSE:
			a1 = deg_to_rad(146.0)
			slack = 0.075
		Style.INVERTED:          # blown inside-out: ribs sweep up into a bowl
			a0 = deg_to_rad(70.0)
			a1 = deg_to_rad(28.0)
			slack = 0.05
	var rib_len := radius / _open_extent()
	var seg_len := rib_len / RING_STEPS
	var apex := Vector3(0, apex_y, 0)
	var segs := RIBS * 3
	var missing := {}
	if style == Style.TORN:
		for i in rng.randi_range(1, 2):
			missing[rng.randi() % RIBS] = rng.randf_range(0.35, 0.9)   # panel index -> how much is gone
	var rows: Array = []
	for s in segs + 1:
		var a := TAU * float(s) / segs
		var sag := sin(fmod(float(s), 3.0) / 3.0 * PI) * slack
		var dir_h := Vector3(cos(a), 0, sin(a))
		var row: Array = [apex]
		var p := apex
		var bend := 0.0
		if style == Style.TORN and missing.has(int(s / 3) % RIBS) and s % 3 == 0:
			bend = rng.randf_range(0.2, 0.6)          # a bent rib at the tear
		for r in RING_STEPS:
			var ang := lerpf(a0, a1 + bend, (float(r) + 0.5) / RING_STEPS)
			p += (sin(ang) * dir_h + Vector3(0, cos(ang), 0)) * seg_len
			var u := float(r + 1) / RING_STEPS
			row.append(p - Vector3(0, sag * u * u, 0) - dir_h * sag * 0.6 * u * u)
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segs:
		var panel := int(s / 3) % RIBS
		for r in RING_STEPS:
			if missing.has(panel) and float(r) / RING_STEPS > 1.0 - float(missing[panel]):
				continue                               # torn-away fabric
			var a: Vector3 = rows[s][r]
			var b: Vector3 = rows[s + 1][r]
			var c: Vector3 = rows[s + 1][r + 1]
			var d: Vector3 = rows[s][r + 1]
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	st.generate_normals()
	return st.commit()
