extends RefCounted
## Visuals for level features: gutter streams (and the broken pipes they pour from), puddles, warm vents, sun breaks, fire barrels.
## Gameplay effects of these live in Level/Player; this only builds what you see.

var level: Node3D
var root: Node3D


func build(p_level: Node3D, p_root: Node3D, data: Dictionary) -> void:
	level = p_level
	root = p_root
	for g in level.builder.gutters:
		_gutter(g)
	for f in data.get("features", []):
		match f["type"]:
			"puddle": _puddle(float(f["x"]), float(f.get("w", 1.0)), bool(f.get("deep", false)))
			"vent": _vent(float(f["x"]))
			"sun": _sun(float(f["x"]), float(f["w"]))
			"fire_barrel": _fire(float(f["x"]))


## A gutter stream, poured from the source LevelBuilder._resolve_gutters picked for it.
func _gutter(g: Dictionary) -> void:
	var x: float = g["x"]
	var top: float
	var z := STREAM_Z
	if g["kind"] == "collapse":
		top = g["top"]
		z = g["z"]
	else:
		top = _gooseneck(g)
	var col := _water_column(Vector3(x, top, z), 0.045, 0.09)
	var sp := _splash(Vector3(x, 0.05, z), Vector3.UP, 70.0, 90, 0.15)
	if level.get("gutter_visuals") != null:
		level.gutter_visuals.append([x, col, sp, top])
	_puddle(x, 1.1, false)


const STREAM_Z := 1.65          # the walker's line: gutter streams fall here
const PIPE_R := 0.055
const SPOUT_Z := 2.75           # an intact gooseneck throws its water out here, past the awnings


## A downpipe comes down the facade to just above the awnings, then a gooseneck arm reaches out
## over the walkway to throw the water clear of them. Returns the height the stream leaves it.
## The arm also runs along the street so it reads as a pipe from the side-on camera.
func _gooseneck(g: Dictionary) -> float:
	var x: float = g["x"]
	var s := float(g["side"])
	var mat: Material = load("res://assets/materials/galvanized.tres")
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.035)
	dark.roughness = 0.9
	var wall := Vector3(x - s * 0.7, 3.85, 0.12)
	var brk := Vector3(x, 3.45, STREAM_Z)          # where it split or snapped
	var dir := (brk - wall).normalized()
	var top_y := _building_top(wall.x) - 0.35
	# Down the facade: wall brackets and a hopper head under the roof gutter.
	_tube(Vector3(wall.x, top_y, wall.z), wall + Vector3(0, 0.12, 0), PIPE_R, mat)
	_box(Vector3(0.34, 0.3, 0.24), Vector3(wall.x, top_y + 0.12, 0.12), mat)
	var by := wall.y + 0.7
	while by < top_y - 0.4:
		_box(Vector3(0.16, 0.05, 0.2), Vector3(wall.x, by, 0.08), dark)
		by += 1.6
	# Elbow out from the wall, and a wire stay holding the arm up.
	var elbow := wall + Vector3(0, 0.12, 0)
	_tube(elbow, elbow + dir * 0.12, PIPE_R, mat)
	_ball(elbow, PIPE_R * 1.12, mat)
	var stay_at := wall + dir * (wall.distance_to(brk) * 0.7)
	_tube(Vector3(wall.x - s * 0.15, wall.y + 1.1, 0.06), stay_at + Vector3(0, PIPE_R, 0), 0.008, dark)
	_box(Vector3(0.05, 0.05, 0.06), stay_at + Vector3(0, PIPE_R * 0.5, 0), dark)
	if g["kind"] == "crack":
		# Whole arm out to the spout; a split along its belly over the walkway.
		var spout := wall + dir * ((SPOUT_Z - wall.z) / dir.z)
		_tube(elbow + dir * 0.1, spout, PIPE_R, mat)
		_ball(spout, PIPE_R * 1.12, mat)
		_tube(spout, spout + Vector3(0, -0.22, 0.03), PIPE_R, mat)
		_splash(spout + Vector3(0, -0.24, 0.03), Vector3.DOWN, 4.0, 14, 0.02)   # what still gets through
		var split := _box(Vector3(0.05, 0.03, 0.26), brk + Vector3(0, -PIPE_R * 0.75, 0), dark)
		split.basis = Basis(Quaternion(Vector3.BACK, dir))
		var bulge := _ball(brk + Vector3(0, -PIPE_R * 0.2, 0), PIPE_R * 1.22, mat)
		bulge.basis = Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(1.0, 1.9, 0.9))
		_splash(brk + Vector3(0, -PIPE_R, 0), Vector3.DOWN, 14.0, 30, 0.05)
		return brk.y - PIPE_R
	# Snapped off over the walkway: a ragged open end, the rest of the arm on the pavement.
	_tube(elbow + dir * 0.1, brk, PIPE_R, mat)
	var lip := _tube(brk - dir * 0.01, brk + dir * 0.01, PIPE_R * 0.8, dark)
	lip.mesh.radial_segments = 10
	for k in 6:
		var a := TAU * k / 6.0 + 0.4
		var tooth_len := 0.04 + 0.05 * absf(sin(a * 2.7))
		var basis := Basis(Quaternion(Vector3.UP, dir))
		var off := basis * Vector3(cos(a), 0.0, sin(a)) * PIPE_R * 0.95
		var t := _box(Vector3(0.03, tooth_len, 0.006), brk + off + dir * tooth_len * 0.45, mat)
		t.basis = basis * Basis(Vector3.UP, a)
	var piece_at := Vector3(x + s * 0.6, PIPE_R, 0.55)       # fell and rolled against the wall
	var piece_dir := Vector3(s * 0.96, 0.0, -0.28).normalized()
	_tube(piece_at - piece_dir * 0.5, piece_at + piece_dir * 0.5, PIPE_R, mat)
	_ball(piece_at + piece_dir * 0.5, PIPE_R * 1.12, mat)
	_tube(piece_at + piece_dir * 0.5, piece_at + piece_dir * 0.5 + Vector3(0, 0.02, 0.24), PIPE_R, mat)
	return brk.y


func _building_top(x: float) -> float:
	for lot in level.data.get("lots", []):
		if x >= float(lot["x"]) and x < float(lot["x"]) + float(lot["w"]) and int(lot.get("floors", 0)) > 0:
			return 4.0 + 3.2 * int(lot["floors"])
	return 7.2


func _tube(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = a.distance_to(b)
	c.radial_segments = 12
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * 0.5)
	root.add_child(mi)
	return mi


func _ball(at: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)
	return mi


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)
	return mi


## A falling column of water from `from` straight down to the pavement. Built 1 m tall and scaled,
## so Level can cut it off where it lands on the umbrella.
func _water_column(from: Vector3, r_top: float, r_bottom: float) -> MeshInstance3D:
	var water := ShaderMaterial.new()
	water.shader = load("res://src/fx/water_stream.gdshader")
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r_top
	cyl.bottom_radius = r_bottom
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 8
	col.mesh = cyl
	col.material_override = water
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	col.scale.y = from.y - 0.02
	col.position = Vector3(from.x, (from.y + 0.02) * 0.5, from.z)
	root.add_child(col)
	return col


## Droplets thrown from `at`: splash-back off the pavement (up), or spray from a leak (down).
func _splash(at: Vector3, dir: Vector3, spread: float, amount: int, radius: float) -> GPUParticles3D:
	var sp := GPUParticles3D.new()
	sp.amount = amount
	sp.lifetime = 0.45
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	sp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.75, 0.82, 0.95, 0.6)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = dm
	sp.draw_pass_1 = q
	sp.position = at
	root.add_child(sp)
	return sp


func _puddle(x: float, w: float, deep: bool) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, 1.6 if not deep else 2.4)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/fx/puddle.gdshader")
	mi.material_override = mat
	mi.position = Vector3(x, level.ground_y(x) + 0.012, 1.6)
	root.add_child(mi)


func _vent(x: float) -> void:
	# Wall AC unit blowing warm air (visible heat haze + steam).
	var unit_path := "res://assets/props/wall_ac_unit.glb"
	if ResourceLoader.exists(unit_path):
		var n: Node3D = load(unit_path).instantiate()
		n.position = Vector3(x, 2.2, 0.0)
		root.add_child(n)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.5, 0.6)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.55, 0.52)
		m.roughness = 0.5
		m.metallic = 0.4
		mi.material_override = m
		mi.position = Vector3(x, 2.2, 0.3)
		root.add_child(mi)
	var steam := _steam(Vector3(x, 2.0, 0.65), Vector3(0, -0.5, 1.0), Color(1.0, 0.85, 0.7, 0.05))
	root.add_child(steam)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.55, 0.3)
	warm.light_energy = 0.6
	warm.omni_range = 2.0
	warm.light_volumetric_fog_energy = 0.0
	warm.position = Vector3(x, 1.8, 0.8)
	root.add_child(warm)


func _steam(pos: Vector3, dir: Vector3, color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.6
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.3, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.25, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = color
	dm.roughness = 1.0
	dm.vertex_color_use_as_albedo = true
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_texture = _soft_texture()
	q.material = dm
	p.draw_pass_1 = q
	p.position = pos
	return p


func _soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _sun(x: float, w: float) -> void:
	# A break in the clouds: a warm shaft of light through the fog onto a drying patch of pavement.
	var cx := x + w * 0.5
	var sl := SpotLight3D.new()
	sl.light_color = Color(1.0, 0.78, 0.45)
	sl.light_energy = 13.0
	sl.spot_range = 45.0
	sl.spot_angle = rad_to_deg(atan2(w * 0.5, 24.0)) + 1.5
	sl.spot_angle_attenuation = 0.4
	sl.spot_attenuation = 0.15
	sl.light_volumetric_fog_energy = 1.2
	sl.shadow_enabled = true
	sl.position = Vector3(cx - 5.0, 24.0, 1.0)
	root.add_child(sl)
	sl.look_at(Vector3(cx, 0.0, 1.6), Vector3.UP)
	# Soft additive shaft so the beam reads even through the painterly filter.
	var shaft := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w * 0.9, 16.0)
	shaft.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.8, 0.5, 0.16)
	m.albedo_texture = _shaft_texture()
	m.disable_receive_shadows = true
	shaft.material_override = m
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = Vector3(cx - 1.5, 8.0, 1.2)
	shaft.rotation.z = -atan2(5.0, 24.0)
	root.add_child(shaft)
	# Dry, warm patch of pavement.
	var patch := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, 3.4)
	patch.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.55, 0.48, 0.38)
	pmat.roughness = 0.8
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_texture = _soft_texture()
	pmat.uv1_scale = Vector3(1, 1, 1)
	patch.material_override = pmat
	patch.position = Vector3(cx, 0.01, 1.7)
	root.add_child(patch)


func _shaft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0)
	t.width = 64
	t.height = 4
	return t


func _fire(x: float) -> void:
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.9
	barrel.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.12, 0.06)
	m.roughness = 0.7
	m.metallic = 0.5
	barrel.material_override = m
	barrel.position = Vector3(x, 0.45, 0.55)
	root.add_child(barrel)
	var fire := GPUParticles3D.new()
	fire.amount = 60
	fire.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.5, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
	grad.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	fire.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_texture = _soft_texture()
	q.material = dm
	fire.draw_pass_1 = q
	fire.position = Vector3(x, 0.95, 0.55)
	root.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.5
	light.omni_range = 5.0
	light.light_volumetric_fog_energy = 0.3
	light.position = Vector3(x, 1.4, 0.8)
	light.shadow_enabled = true
	light.set_script(load("res://src/fx/flicker.gd"))
	root.add_child(light)
	root.add_child(_steam(Vector3(x, 1.3, 0.55), Vector3(0, 1, 0), Color(0.3, 0.3, 0.3, 0.2)))
