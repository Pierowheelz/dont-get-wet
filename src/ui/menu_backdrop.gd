extends Node3D
## Title-screen backdrop: the first stretch of Main Street at night in the rain, a lone man
## walking under his umbrella, and a slow following camera. Purely decorative.

const LEVEL_ID := "main_street"
const STREET_END := 74.0
const LOOP_START := 4.0
const LOOP_END := 60.0
const WALK_SPEED := 0.95

## Emitted just before the walker loops back to the start (the menu fades to cover it).
signal loop_soon

var camera: Camera3D
var _walker: Node3D
var _umbrella: Umbrella
var _rain: RainFX
var _adapter: RainAdapter
var _t := 0.0
var _x := LOOP_START + 6.0
var _loop_warned := false


class RainAdapter extends Node:
	## Minimal stand-in for Level's weather queries, as used by RainFX.
	var sun_zones: Array = []
	var intensity := 0.85

	func rain_dir(_x: float) -> Vector3:
		return Vector3(0.12, -1.0, 0.0).normalized()

	func rain_intensity_raw(_x: float) -> float:
		return intensity


func _ready() -> void:
	var data := _trimmed_data()
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	var builder := LevelBuilder.new()
	if not data.is_empty():
		builder.build(world, data)
	_environment()
	_shop_lights(world, builder.lit_windows)

	camera = Camera3D.new()
	camera.fov = 46.0
	camera.far = 200.0
	add_child(camera)
	camera.make_current()

	_adapter = RainAdapter.new()
	add_child(_adapter)
	_rain = RainFX.new()
	_rain.level = _adapter
	_rain.camera = camera
	add_child(_rain)

	_spawn_walker()
	_update(0.0)


func _trimmed_data() -> Dictionary:
	var d: Dictionary = Game.level_data(LEVEL_ID).duplicate(true)
	if d.is_empty():
		return d
	var keep := func(arr: Array, key: String) -> Array:
		return arr.filter(func(e: Dictionary) -> bool: return float(e.get(key, 0.0)) < STREET_END)
	d["lots"] = keep.call(d.get("lots", []), "x")
	d["crossings"] = keep.call(d.get("crossings", []), "x")
	d["props"] = keep.call(d.get("props", []), "x")
	d["features"] = []
	d["length"] = STREET_END + 6.0
	d["end_x"] = STREET_END
	return d


func _spawn_walker() -> void:
	var path := "res://assets/characters/walker/walker.tscn"
	if not ResourceLoader.exists(path):
		return
	_walker = (load(path) as PackedScene).instantiate() as Node3D
	_walker.position = Vector3(_x, 0.0, Tun.f("player_z"))
	add_child(_walker)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.9
	fill.omni_range = 3.4
	fill.omni_attenuation = 1.5
	fill.position = Vector3(0.4, 1.9, 1.4)
	fill.light_specular = 0.3
	_walker.add_child(fill)
	_umbrella = Umbrella.new()
	_umbrella.top_level = true
	add_child(_umbrella)
	if _walker.has_method(&"set_wetness"):
		_walker.call(&"set_wetness", 0.18)


func _process(delta: float) -> void:
	_t += delta
	_update(delta)


func _update(delta: float) -> void:
	_x += WALK_SPEED * delta
	if _x > LOOP_END - 2.0 and not _loop_warned:
		_loop_warned = true
		loop_soon.emit()
	if _x > LOOP_END:
		_x = LOOP_START
		_loop_warned = false
	if _walker:
		_walker.position.x = _x
		_walker.call(&"set_motion", WALK_SPEED, 0.0)
		_walker.call(&"set_umbrella_pose", 1.0, sin(_t * 0.4) * 0.08, 0.0)
		var grip: Node3D = _walker.call(&"get_grip", &"right")
		if grip and _umbrella:
			_umbrella.global_transform = grip.global_transform
			_umbrella.set_state(1.0, Game.umbrella_radius(), 0.0)
	# Camera: walker sits right of centre, leaving the left of the frame for the title.
	# A slow breathing drift keeps the shot alive.
	var cx := _x - 1.7 + sin(_t * 0.13) * 0.25
	camera.position = Vector3(cx, 2.05 + sin(_t * 0.21) * 0.06, Tun.f("player_z") + 7.6)
	camera.rotation = Vector3(deg_to_rad(-2.5 + sin(_t * 0.17) * 0.4), deg_to_rad(sin(_t * 0.09) * 0.8), 0.0)
	_adapter.intensity = 0.8 + 0.15 * sin(_t * 0.05)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.05, 0.06, 0.09)
	sm.sky_horizon_color = Color(0.19, 0.19, 0.23)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.04)
	sm.ground_horizon_color = Color(0.19, 0.19, 0.23)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.ambient_light_sky_contribution = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.85
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.034
	env.volumetric_fog_albedo = Color(0.55, 0.6, 0.7)
	env.volumetric_fog_emission = Color(0.03, 0.035, 0.05)
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_length = 70.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.15, 0.16, 0.2)
	env.fog_density = 0.014
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.7, 0.9)
	moon.light_energy = 0.32
	moon.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	moon.light_volumetric_fog_energy = 0.3
	add_child(moon)


func _shop_lights(world: Node3D, lit: Array) -> void:
	for lw: Array in lit:
		var pos: Vector3 = lw[0]
		var col: Color = lw[1]
		var om := OmniLight3D.new()
		om.light_color = col
		om.light_energy = 2.2
		om.omni_range = 6.0
		om.omni_attenuation = 1.2
		om.position = pos
		om.light_volumetric_fog_energy = 1.5
		world.add_child(om)
		var spill := OmniLight3D.new()
		spill.light_color = col
		spill.light_energy = 0.9
		spill.omni_range = 4.0
		spill.position = Vector3(pos.x, 1.2, 1.2)
		world.add_child(spill)
