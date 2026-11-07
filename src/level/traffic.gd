extends Node3D
## Occasional foreground traffic on the near lane of the main road (scenery only).
## Cars pass between the camera and the walker, throwing road spray.

var level: Node
var _next := 12.0
var _cars: Array = []


func _process(delta: float) -> void:
	_next -= delta
	if _next <= 0.0 and level.player and level.player.state == Player.State.WALK:
		_next = randf_range(22.0, 45.0)
		_spawn()
	for c in _cars.duplicate():
		var n: Node3D = c[0]
		n.position.x += c[1] * delta
		if absf(n.position.x - level.camera.position.x) > 40.0:
			n.queue_free()
			_cars.erase(c)


func _spawn() -> void:
	var dir := -1.0 if randf() < 0.6 else 1.0
	var cam_x: float = level.camera.position.x
	var car := Node3D.new()
	var path := "res://assets/props/%s.glb" % ["car_sedan", "car_sedan_b", "car_sedan_c"][randi() % 3]
	var body: Node3D = load(path).instantiate() if ResourceLoader.exists(path) else CarHazard.greybox_car()
	car.add_child(body)
	car.position = Vector3(cam_x - dir * 30.0, LevelBuilder.ROAD_Y, 5.4)
	car.rotation.y = 0.0 if dir > 0.0 else PI
	for side in [-0.65, 0.65]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.92, 0.75)
		sl.light_energy = 6.0
		sl.spot_range = 22.0
		sl.spot_angle = 24.0
		sl.light_volumetric_fog_energy = 2.5
		sl.position = Vector3(2.2, 0.7, side)
		sl.rotation = Vector3(0, -PI * 0.5, 0)
		car.add_child(sl)
	var tail := OmniLight3D.new()
	tail.light_color = Color(1.0, 0.1, 0.05)
	tail.light_energy = 1.5
	tail.omni_range = 3.0
	tail.position = Vector3(-2.5, 0.7, 0)
	car.add_child(tail)
	# Road spray behind the wheels.
	var spray := GPUParticles3D.new()
	spray.amount = 160
	spray.lifetime = 0.6
	spray.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-1, 0.6, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.2, 0.05, 0.9)
	spray.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.7, 0.78, 0.9, 0.45)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = dm
	spray.draw_pass_1 = q
	spray.position = Vector3(-1.5, 0.15, 0)
	car.add_child(spray)
	add_child(car)
	_cars.append([car, dir * randf_range(10.0, 14.0)])
	if level.audio and level.audio.has_method("car_pass"):
		level.audio.car_pass(car)
