class_name Level
extends Node3D
## Runs one level: builds the street from JSON, owns world queries used by the player
## (rain, wind, drying, ground height), the camera, and the fail / finish flow.

const ROAD_Y := LevelBuilder.ROAD_Y

var data: Dictionary
var level_id := ""
var length := 100.0
var end_x := 90.0
var par_time := 60.0
var elapsed := 0.0
var finished := false

var gutters: Array = []        # x positions
var puddles: Array = []        # [x0, x1, deep]
var sun_zones: Array = []      # [x0, x1]
var dry_zones: Array = []      # [x0, x1, rate]
var crossings: Array = []      # [x0, x1]
var cars: Array = []           # CarHazard nodes

var player: Player
var camera: Camera3D
var rain_fx: RainFX
var hud: Node
var audio: Node
var world: Node3D
var builder: LevelBuilder
var _rain_curve: Array
var _wind_curve: Array
var _gusts := false
var _cam_locked := false
var _cam_x := 0.0
var _t := 0.0


func _ready() -> void:
	Tun.reload()
	level_id = Game.current_level if Game.current_level != "" else Game.start_node
	Game.current_level = level_id
	data = Game.level_data(level_id)
	length = data.get("length", 100.0)
	end_x = data.get("end_x", length - 10.0)
	par_time = end_x / Tun.f("walk_speed")
	_rain_curve = data.get("rain", [[0, 1], [1, 1]])
	_wind_curve = data.get("wind", [[0, 0], [1, 0]])
	_gusts = data.get("gusts", false)
	for c in data.get("crossings", []):
		crossings.append([float(c["x"]), float(c["x"]) + float(c["w"])])

	world = Node3D.new()
	world.name = "World"
	add_child(world)
	builder = LevelBuilder.new()
	builder.build(world, data)
	_parse_features()
	_setup_environment()
	_setup_shop_lights()

	player = Player.new()
	player.name = "Player"
	player.level = self
	player.position = Vector3(Game.debug_start_x if Game.debug_start_x > 0.0 else 1.5, 0.0, Tun.f("player_z"))
	add_child(player)
	player.defeated.connect(_on_defeated)
	player.arrived.connect(_on_arrived)

	camera = Camera3D.new()
	camera.fov = Tun.f("camera_fov")
	camera.far = 200.0
	add_child(camera)
	_cam_x = player.position.x + Tun.f("camera_lead")
	_update_camera(1.0)
	camera.make_current()

	rain_fx = RainFX.new()
	rain_fx.level = self
	rain_fx.camera = camera
	add_child(rain_fx)

	var feats := preload("res://src/level/features.gd").new()
	feats.build(self, world, data)
	for c in data.get("crossings", []):
		if c.get("car", false):
			var car := CarHazard.new()
			car.level = self
			car.crossing_x = float(c["x"])
			car.crossing_w = float(c["w"])
			world.add_child(car)
			cars.append(car)
			car.approaching.connect(_on_car_approaching)

	var traffic := preload("res://src/level/traffic.gd").new()
	traffic.level = self
	add_child(traffic)

	hud = preload("res://src/ui/hud.gd").new()
	hud.level = self
	add_child(hud)
	if Game.settings.get("painterly", true):
		add_child(preload("res://src/fx/post_fx.gd").new())
	if ResourceLoader.exists("res://src/audio/level_audio.gd"):
		audio = load("res://src/audio/level_audio.gd").new()
		audio.level = self
		add_child(audio)


func _parse_features() -> void:
	for f in data.get("features", []):
		var x: float = f["x"]
		match f["type"]:
			"gutter":
				gutters.append(x)
			"puddle":
				puddles.append([x - f.get("w", 1.0) * 0.5, x + f.get("w", 1.0) * 0.5, f.get("deep", false)])
			"sun":
				sun_zones.append([x, x + float(f["w"])])
				dry_zones.append([x, x + float(f["w"]), Tun.f("dry_sun_rate")])
			"vent":
				var w: float = f.get("w", 1.6)
				dry_zones.append([x - w * 0.5, x + w * 0.5, Tun.f("dry_vent_rate")])
			"fire_barrel":
				var w2: float = f.get("w", 1.8)
				dry_zones.append([x - w2 * 0.5, x + w2 * 0.5, Tun.f("dry_vent_rate") * 1.2])


# --- world queries --------------------------------------------------------------------------

func _curve(curve: Array, x: float) -> float:
	var p := clampf(x / maxf(end_x, 1.0), 0.0, 1.0)
	for i in range(1, curve.size()):
		if p <= float(curve[i][0]):
			var a: Array = curve[i - 1]
			var b: Array = curve[i]
			var t := (p - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(curve[-1][1])


func rain_intensity_raw(x: float) -> float:
	return _curve(_rain_curve, x)


func rain_intensity(x: float) -> float:
	for z in sun_zones:
		if x > z[0] and x < z[1]:
			return 0.0
	return rain_intensity_raw(x)


## Signed wind strength 0..~1 (+ blows toward +X = tailwind).
func wind(x: float) -> float:
	var w := _curve(_wind_curve, x)
	if _gusts:
		w *= 1.0 + 0.4 * sin(_t * 0.9) * sin(_t * 0.37 + 1.3)
	return w


func rain_dir(x: float) -> Vector3:
	return Vector3(wind(x) * 0.9, -1.0, 0.0).normalized()


func dry_rate(x: float) -> float:
	var r := 0.0
	for z in dry_zones:
		if x > z[0] and x < z[1]:
			r += z[2]
	return r


func ground_y(x: float) -> float:
	for c in crossings:
		if x > c[0] + 0.3 and x < c[1] - 0.3:
			return ROAD_Y
	return 0.0


func car_threat(x: float) -> bool:
	for c in cars:
		if c.is_threat_for(x):
			return true
	return false


func progress() -> float:
	return clampf(player.position.x / end_x, 0.0, 1.0) if player else 0.0


# --- loop -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if player and player.state != Player.State.DEFEATED and player.state != Player.State.DONE and not finished:
		elapsed += delta
	_update_camera(delta)
	if Game.autopilot and player and OS.has_environment("DGW_TRACE") and player.position.x > float(OS.get_environment("DGW_TRACE")) and int(_t * 2.0) != int((_t - delta) * 2.0):
		print("x=%.1f wind=%.2f exp=%.2f open=%.2f tilt=%.2f sta=%.0f wet=%.1f gut=%.2f exh=%s" % [player.position.x, wind(player.position.x), player.exposure, player.open, player.tilt, player.stamina, player.wet, player.gutter_hit, player.exhausted])
	if Game.autopilot and player and int(_t / 10.0) != int((_t - delta) / 10.0):
		print("t=%.0f x=%.1f wet=%.1f sta=%.1f open=%.2f state=%d" % [_t, player.position.x, player.wet, player.stamina, player.open, player.state])
	if Input.is_action_just_pressed(&"restart") and not get_tree().paused:
		Game.play_level(level_id)


func _update_camera(delta: float) -> void:
	if player == null or camera == null:
		return
	if not _cam_locked:
		var target := player.position.x + Tun.f("camera_lead")
		_cam_x = lerpf(_cam_x, target, 1.0 - exp(-6.0 * delta))
	var z := Tun.f("player_z") + Tun.f("camera_distance")
	camera.position = Vector3(_cam_x, Tun.f("camera_height"), z)
	camera.rotation = Vector3(deg_to_rad(Tun.f("camera_pitch_deg")), 0, 0)


# --- flow -----------------------------------------------------------------------------------

var _car_hints := 0


func _on_car_approaching() -> void:
	if _car_hints < 2 and hud and hud.has_method("hint"):
		_car_hints += 1
		var pad := Inputs.last_device == &"gamepad"
		hud.hint("Headlights! Tilt the umbrella forward to block the splash  (%s)" % ("right stick →" if pad else "E / scroll up"), 3.5)


func _on_defeated() -> void:
	_cam_locked = true
	if Game.autopilot:
		print("AUTOPILOT_DEFEATED x=%.1f t=%.1f stats=%s" % [player.position.x, elapsed, JSON.stringify(player.stats)])
		get_tree().quit()
		return
	await get_tree().create_timer(3.6).timeout
	hud.show_fail()


func _on_arrived() -> void:
	finished = true
	var wet := player.wet
	var t := elapsed
	while player.state != Player.State.DONE:
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	var result := Game.finish_level(level_id, wet, t, par_time)
	if Game.autopilot:
		print("AUTOPILOT_RESULT ", JSON.stringify(result), " stats=", JSON.stringify(player.stats))
		get_tree().quit()
		return
	hud.show_result(result)


# --- environment ----------------------------------------------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.05, 0.07, 0.12)
	sm.sky_horizon_color = Color(0.17, 0.2, 0.27)
	sm.ground_bottom_color = Color(0.03, 0.03, 0.04)
	sm.ground_horizon_color = Color(0.17, 0.2, 0.27)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_sky_contribution = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.028
	var neon: float = data.get("neon", 0.0)
	env.volumetric_fog_albedo = Color(0.55, 0.6, 0.7).lerp(Color(0.6, 0.5, 0.75), neon)
	env.volumetric_fog_emission = Color(0.03, 0.035, 0.05).lerp(Color(0.05, 0.02, 0.07), neon)
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_length = 70.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.17, 0.21)
	env.fog_density = 0.012
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = lerpf(0.82, 1.05, neon)
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.66, 0.92).lerp(Color(0.5, 0.55, 1.0), float(data.get("neon", 0.0)))
	moon.light_energy = 0.5
	moon.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	moon.light_volumetric_fog_energy = 0.3
	add_child(moon)


func _setup_shop_lights() -> void:
	for lw in builder.lit_windows:
		var om := OmniLight3D.new()
		om.light_color = lw[1]
		om.light_energy = 1.5
		om.omni_range = 5.0
		om.omni_attenuation = 1.2
		om.position = lw[0]
		om.light_volumetric_fog_energy = 1.5
		world.add_child(om)
		# Spill light onto the wet sidewalk.
		var spill := OmniLight3D.new()
		spill.light_color = lw[1]
		spill.light_energy = 0.45
		spill.omni_range = 4.0
		spill.position = Vector3(lw[0].x, 1.2, 1.2)
		world.add_child(spill)
