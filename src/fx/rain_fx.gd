class_name RainFX
extends Node3D
## Camera-following rain: streak particles that die on contact with a height-field collider
## (so they stop on awnings/umbrella), ground splashes, and a foreground blur layer.

var level: Node
var camera: Camera3D
var _rain: GPUParticles3D
var _near: GPUParticles3D
var _splash: GPUParticles3D
var _hf: GPUParticlesCollisionHeightField3D
var _mat: ShaderMaterial
var _near_mat: ShaderMaterial


func _ready() -> void:
	var shader: Shader = load("res://src/fx/rain.gdshader")
	_splash = _make_splash()
	add_child(_splash)

	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rain = _make_layer(_mat, 14000, Vector3(16.0, 7.0, 4.5), 0.42, 0.010, 0.33)
	add_child(_rain)
	_rain.sub_emitter = _rain.get_path_to(_splash)

	# Foreground layer: fewer, longer, softer streaks close to the camera.
	_near_mat = ShaderMaterial.new()
	_near_mat.shader = shader
	_near = _make_layer(_near_mat, 900, Vector3(6.0, 4.5, 1.2), 0.9, 0.02, 0.12)
	add_child(_near)

	_hf = GPUParticlesCollisionHeightField3D.new()
	_hf.size = Vector3(44.0, 24.0, 18.0)
	_hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	_hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS
	_hf.follow_camera_enabled = true
	add_child(_hf)


func _make_layer(mat: ShaderMaterial, amount: int, extents: Vector3, length: float, width: float, alpha: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = (extents.y * 2.0 + 2.0) / 8.0
	p.preprocess = p.lifetime
	p.fixed_fps = 0
	p.local_coords = false
	p.process_material = mat
	p.visibility_aabb = AABB(-extents * 2.0 - Vector3(0, 4, 0), extents * 4.0 + Vector3(0, 8, 0))
	p.collision_base_size = 0.02
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat.set_shader_parameter("box_extents", extents)
	mat.set_shader_parameter("streak_length", length)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.7, 0.78, 0.9, alpha)
	dm.albedo_texture = _streak_texture()
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.disable_receive_shadows = true
	dm.vertex_color_use_as_albedo = false
	q.material = dm
	p.draw_pass_1 = q
	return p


func _streak_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0)
	t.width = 16
	t.height = 1
	return t


func _make_splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 4000
	p.lifetime = 0.28
	p.emitting = true
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.7, 0.78, 0.9, 0.5)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = dm
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-30, -5, -20), Vector3(60, 20, 40))
	return p


func _process(_delta: float) -> void:
	if camera == null or level == null:
		return
	var cx := camera.global_position.x
	var dir: Vector3 = level.rain_dir(cx)
	var inten: float = level.rain_intensity_raw(cx)
	_rain.global_position = Vector3(cx, 6.5, 1.0)
	_near.global_position = Vector3(cx, 3.0, camera.global_position.z - 2.2)
	for m in [_mat, _near_mat]:
		m.set_shader_parameter("fall_dir", dir)
		m.set_shader_parameter("intensity", inten)
	var zones: Array = level.sun_zones
	var arr := PackedVector4Array()
	for z in zones:
		arr.append(Vector4(z[0], z[1], 0, 0))
	while arr.size() < 8:
		arr.append(Vector4(1e9, 1e9, 0, 0))
	_mat.set_shader_parameter("sun_zones", arr)
	_mat.set_shader_parameter("sun_zone_count", mini(zones.size(), 8))
	_near_mat.set_shader_parameter("sun_zones", arr)
	_near_mat.set_shader_parameter("sun_zone_count", mini(zones.size(), 8))
