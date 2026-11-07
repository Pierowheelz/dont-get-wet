extends RefCounted
## Visuals for level features: gutter streams, puddles, warm vents, sun breaks, fire barrels.
## Gameplay effects of these live in Level/Player; this only builds what you see.

var level: Node3D
var root: Node3D


func build(p_level: Node3D, p_root: Node3D, data: Dictionary) -> void:
	level = p_level
	root = p_root
	for f in data.get("features", []):
		match f["type"]:
			"gutter": _gutter(float(f["x"]))
			"puddle": _puddle(float(f["x"]), float(f.get("w", 1.0)), bool(f.get("deep", false)))
			"vent": _vent(float(f["x"]))
			"sun": _sun(float(f["x"]), float(f["w"]))
			"fire_barrel": _fire(float(f["x"]))


func _gutter(x: float) -> void:
	# A broken downpipe / overflowing gutter: a thick falling column across the walkway.
	var water := ShaderMaterial.new()
	water.shader = load("res://src/fx/water_stream.gdshader")
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.09
	cyl.height = 2.75
	cyl.radial_segments = 12
	cyl.rings = 8
	col.mesh = cyl
	col.material_override = water
	col.position = Vector3(x, 1.4, 1.65)
	root.add_child(col)
	# Broken gutter lip above.
	var lip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.12, 0.25)
	lip.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.22, 0.2)
	m.metallic = 0.7
	m.roughness = 0.4
	lip.material_override = m
	lip.position = Vector3(x, 2.78, 1.65)
	lip.rotation.z = 0.25
	root.add_child(lip)
	# Splash at the bottom.
	var sp := GPUParticles3D.new()
	sp.amount = 90
	sp.lifetime = 0.45
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
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
	sp.position = Vector3(x, 0.05, 1.65)
	root.add_child(sp)
	_puddle(x, 1.1, false)


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
