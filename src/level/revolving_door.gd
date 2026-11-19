extends Node3D
## The `revolving_door` prop: a hotel's revolving door set into the facade at x. A brass drum head with
## a lit ceiling, curved glass walls either side framed in brass with a kick plate, and four framed
## leaves with push bars turning slowly inside, on a dark mat. Dressing only: no collider, nothing the
## rain model sees.

const R := 0.95
const H := 2.35
const Z := 0.25               # the drum's centre: half in the building, half out on the pavement
const TURN := 0.45            # rad/s
const HEAD := 0.3             # the brass drum head above the glass
const WALL_ARC := 0.9         # rad each curved wall spans either side of the facade line
const ARC_STEPS := 8
const KICK := 0.28            # the kick plate's height
const BAR_Y := 1.05           # push bars

var _leaves: Node3D


func _ready() -> void:
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.8, 0.6, 0.28)
	brass.metallic = 0.75        # short of a mirror, which only has the night to reflect
	brass.roughness = 0.32
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.86, 0.92, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.04
	glass.metallic_specular = 1.0
	glass.rim_enabled = true
	glass.rim = 0.7
	var mat_rubber := StandardMaterial3D.new()
	mat_rubber.albedo_color = Color(0.07, 0.065, 0.06)
	mat_rubber.roughness = 0.9
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.86, 0.62)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.8, 0.5)
	glow.emission_energy_multiplier = 2.2

	_disc(R + 0.1, 0.03, 0.015, mat_rubber)
	_disc(R + 0.1, HEAD, H + 0.06 + HEAD * 0.5, brass)
	_disc(R + 0.14, 0.05, H + 0.06 + HEAD, brass)                # the head's cornice
	_disc(R - 0.06, 0.02, H + 0.05, glow)                        # the lit ceiling
	# The curved walls: glass between a brass kick plate and the head, a brass post at each end and
	# a rail at the push bars' height. Each wall is centred on the facade line, so half of it shows.
	var wall_glass := SurfaceTool.new()
	wall_glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_brass := SurfaceTool.new()
	wall_brass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [0.0, PI]:
		for i in ARC_STEPS:
			var a0 := side - WALL_ARC + 2.0 * WALL_ARC * i / ARC_STEPS
			var a1 := side - WALL_ARC + 2.0 * WALL_ARC * (i + 1) / ARC_STEPS
			_band(wall_glass, a0, a1, R, KICK, H)
			_band(wall_brass, a0, a1, R + 0.012, 0.0, KICK)
			_band(wall_brass, a0, a1, R + 0.012, BAR_Y - 0.03, BAR_Y + 0.03)
		for a: float in [side - WALL_ARC, side + WALL_ARC]:
			_post(0.045, H, Vector3(cos(a) * R, H * 0.5 + 0.06, Z + sin(a) * R), brass)
	wall_glass.generate_normals()
	wall_brass.generate_normals()
	for pair in [[wall_glass, glass], [wall_brass, _two_sided(brass)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as SurfaceTool).commit()
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0.0, 0.06, Z)
		add_child(mi)

	_leaves = Node3D.new()
	_leaves.position = Vector3(0.0, 0.06, Z)
	add_child(_leaves)
	_post(0.055, H, Vector3(0.0, H * 0.5, 0.0), brass, _leaves)
	var reach := R - 0.07
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.y = TAU * i / 4.0
		_leaves.add_child(arm)
		_part(Vector3(reach, H - 0.12, 0.02), Vector3(reach * 0.5 + 0.03, H * 0.5, 0.0), glass, arm)
		for y: float in [0.11, H - 0.07]:                         # bottom and top rails
			_part(Vector3(reach, 0.16 if y < 1.0 else 0.08, 0.045), Vector3(reach * 0.5 + 0.03, y, 0.0), brass, arm)
		_part(Vector3(0.06, H - 0.06, 0.05), Vector3(reach + 0.01, H * 0.5, 0.0), brass, arm)    # the stile at its outer edge
		_part(Vector3(reach - 0.16, 0.04, 0.09), Vector3(reach * 0.5 + 0.05, BAR_Y, 0.0), brass, arm)   # the push bar
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.52)
	lamp.light_energy = 2.2
	lamp.omni_range = 3.0
	lamp.light_volumetric_fog_energy = 0.0
	lamp.position = Vector3(0.0, H - 0.3, Z)
	add_child(lamp)


func _disc(radius: float, height: float, y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 32
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(0.0, y, Z)
	add_child(mi)


func _post(radius: float, height: float, at: Vector3, mat: Material, parent: Node3D = self) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)


func _part(size: Vector3, at: Vector3, mat: Material, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	parent.add_child(mi)


## One facet of a curved wall: the strip of the drum between angles a0 and a1, from y0 up to y1.
static func _band(st: SurfaceTool, a0: float, a1: float, radius: float, y0: float, y1: float) -> void:
	var p0 := Vector3(cos(a0), 0.0, sin(a0)) * radius
	var p1 := Vector3(cos(a1), 0.0, sin(a1)) * radius
	for v: Vector3 in [p0 + Vector3.UP * y0, p1 + Vector3.UP * y0, p1 + Vector3.UP * y1,
			p0 + Vector3.UP * y0, p1 + Vector3.UP * y1, p0 + Vector3.UP * y1]:
		st.add_vertex(v)


static func _two_sided(mat: StandardMaterial3D) -> StandardMaterial3D:
	var m: StandardMaterial3D = mat.duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _process(delta: float) -> void:
	_leaves.rotation.y += TURN * delta
