class_name CarHazard
extends Node3D
## A car that speeds out of a side street through the puddle at the crossing, throwing a wave of
## water at the walker just before they cross. Tilting the umbrella forward shields from it.

signal approaching
signal splashed_puddle(at: Vector3)

enum S { IDLE, DRIVING, GONE }

const TRIGGER_DIST := 8.5
const SPEED := 15.0
const START_Z := -42.0

var level: Node
var crossing_x := 0.0
var crossing_w := 9.0
var state := S.IDLE
var _splashed := false
var _body: Node3D
var _spray: GPUParticles3D
var _lights: Array[SpotLight3D] = []


func _ready() -> void:
	position = Vector3(crossing_x + 1.7, LevelBuilder.ROAD_Y, START_Z)
	rotation.y = -PI * 0.5
	var car_path := "res://assets/props/car_sedan.glb"
	if ResourceLoader.exists(car_path):
		_body = load(car_path).instantiate()
	else:
		_body = _greybox_car()
	add_child(_body)
	for side in [-0.65, 0.65]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.92, 0.75)
		sl.light_energy = 8.0
		sl.spot_range = 30.0
		sl.spot_angle = 22.0
		sl.light_volumetric_fog_energy = 3.0
		sl.position = Vector3(2.2, 0.7, side)
		sl.rotation = Vector3(0, -PI * 0.5, 0)   # local -Z → +X (car forward)
		sl.rotation.z = -0.05
		add_child(sl)
		_lights.append(sl)
	visible = false
	_spray = _make_spray()
	_spray.top_level = true
	add_child(_spray)


func _greybox_car() -> Node3D:
	var n := Node3D.new()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.45, 0.1, 0.08)
	paint.metallic = 0.6
	paint.roughness = 0.25
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.06, 0.08)
	glass.roughness = 0.05
	glass.metallic = 0.5
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.03, 0.03, 0.03)
	tire.roughness = 0.8
	var parts := [[Vector3(4.8, 0.7, 1.9), Vector3(0, 0.65, 0), paint], [Vector3(2.4, 0.55, 1.7), Vector3(-0.2, 1.25, 0), glass]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.material_override = p[2]
		mi.position = p[1]
		n.add_child(mi)
	for wx in [-1.5, 1.5]:
		for wz in [-0.85, 0.85]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.34
			cm.bottom_radius = 0.34
			cm.height = 0.25
			w.mesh = cm
			w.material_override = tire
			w.rotation.x = PI * 0.5
			w.position = Vector3(wx, 0.34, wz)
			n.add_child(w)
	return n


func _make_spray() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 600
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-1.0, 0.9, 0.0)
	pm.spread = 28.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 8.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.3, 0.1, 1.2)
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.7, 0.78, 0.9, 0.7)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = dm
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-10, -2, -6), Vector3(20, 8, 12))
	return p


func is_threat_for(x: float) -> bool:
	if state == S.GONE or _splashed:
		return false
	var d := crossing_x - x
	return d > -0.5 and d < TRIGGER_DIST + 2.0


func _physics_process(delta: float) -> void:
	var player: Node3D = level.player
	match state:
		S.IDLE:
			if player.position.x >= crossing_x - TRIGGER_DIST:
				state = S.DRIVING
				visible = true
				approaching.emit()
		S.DRIVING:
			position.z += SPEED * delta
			if not _splashed and position.z >= 0.6:
				_splashed = true
				_do_splash(player)
			if position.z > 40.0:
				state = S.GONE
				visible = false
				set_physics_process(false)


func _do_splash(player: Node3D) -> void:
	var at := Vector3(crossing_x + 0.9, LevelBuilder.ROAD_Y + 0.1, 1.6)
	_spray.global_position = at
	_spray.restart()
	_spray.emitting = true
	splashed_puddle.emit(at)
	var dist := crossing_x - player.position.x
	var falloff := clampf(1.0 - (dist - 4.0) / 3.5, 0.0, 1.0)
	if dist < -0.5:
		falloff = 1.0
	if falloff <= 0.0:
		return
	# The wave arcs up and comes down on the walker from the front.
	var src := Vector3(player.position.x + clampf(dist, 1.0, 2.6), 2.1, player.position.z)
	player.receive_splash(src, Tun.f("wet_car_splash") * falloff)
