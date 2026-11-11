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
var resumed := false           # this Level started from a checkpoint
var checkpoints: Array = []    # x of each checkpoint, ascending

var gutters: Array = []        # x positions, as LevelBuilder resolved them
var gutter_visuals: Array = [] # [x, column MeshInstance3D, splash GPUParticles3D, source height]
var puddles: Array = []        # [x0, x1, deep]
var sun_zones: Array = []      # [x0, x1] rain-free span (the break, widened to meet nearby cover)
var dry_zones: Array = []      # [x0, x1, rate, needs_closed_umbrella]
var crossings: Array = []      # [x0, x1]
var cars: Array = []           # CarHazard nodes
var track: Track              # the elevated monorail, or null
var phones: Array = []         # {x, keep, line} of every ringing payphone, in prop order

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
	par_time = end_x / float(data.get("par_speed", Tun.f("par_speed")))
	_rain_curve = data.get("rain", [[0, 1], [1, 1]])
	_wind_curve = data.get("wind", [[0, 0], [1, 0]])
	_gusts = data.get("gusts", false)
	for c in data.get("crossings", []):
		crossings.append([float(c["x"]), float(c["x"]) + float(c["w"])])
	checkpoints = data.get("checkpoints", [])

	var pre: Dictionary = Game.prebuilt
	Game.prebuilt = {}
	if pre.get("id", "") == level_id:
		# Built on a worker thread by Game.play_level while the loading card played.
		data = pre["data"]
		world = pre["world"]
		builder = pre["builder"]
		add_child(world)
	else:
		world = Node3D.new()
		world.name = "World"
		add_child(world)
		builder = LevelBuilder.new()
		var t0 := Time.get_ticks_msec()
		builder.build(world, data)
		if OS.get_cmdline_user_args().has("--fps-log"):
			print("build: %d ms" % (Time.get_ticks_msec() - t0))
	if builder.inn_door_x > 0.0:
		end_x = builder.inn_door_x
		par_time = end_x / float(data.get("par_speed", Tun.f("par_speed")))
	_parse_features()
	_setup_environment()
	_setup_shop_lights()

	player = Player.new()
	player.name = "Player"
	player.level = self
	var debug_cp := Game.debug_resume_cp >= 0 and Game.debug_resume_cp < checkpoints.size()
	var resume: bool = debug_cp or (Game.resuming and Game.checkpoint.get("id", "") == level_id)
	var spawn_x := Game.debug_start_x if Game.debug_start_x > 0.0 else 1.5
	if debug_cp:
		spawn_x = float(checkpoints[Game.debug_resume_cp])
	elif resume:
		spawn_x = float(Game.checkpoint["x"])
	# Placed before entering the tree: the player's first step runs from where _ready saw him, and a
	# later move would sweep him through every puddle between the start and the checkpoint.
	player.position = Vector3(spawn_x, ground_y(spawn_x), Tun.f("player_z"))
	add_child(player)
	player.wet = Game.debug_start_wet
	elapsed = Game.debug_clock
	if debug_cp:
		_take_checkpoint(Game.debug_resume_cp)
	if resume:
		_restore_checkpoint()
	Game.resuming = false
	player.defeated.connect(_on_defeated)
	player.arrived.connect(_on_arrived)

	camera = Camera3D.new()
	camera.fov = Tun.f("camera_fov")
	camera.far = 200.0
	add_child(camera)
	_cam_x = player.position.x + Tun.f("camera_lead")
	_update_camera(1.0)
	camera.make_current()

	add_child(DynamicResolution.new())

	var t1 := Time.get_ticks_msec()
	rain_fx = RainFX.new()
	rain_fx.level = self
	rain_fx.camera = camera
	add_child(rain_fx)
	if OS.get_cmdline_user_args().has("--fps-log"):
		print("rain/cover map: %d ms" % (Time.get_ticks_msec() - t1))

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

	if track:
		var trains := preload("res://src/level/viaduct_trains.gd").new()
		trains.level = self
		add_child(trains)

	var peds := preload("res://src/level/pedestrians.gd").new()
	peds.level = self
	add_child(peds)
	if data.has("follower"):
		var follower := preload("res://src/level/follower.gd").new()
		follower.name = "Follower"
		follower.level = self
		add_child(follower)

	var traffic := preload("res://src/level/traffic.gd").new()
	traffic.level = self
	add_child(traffic)

	hud = preload("res://src/ui/hud.gd").new()
	hud.level = self
	add_child(hud)
	Game.hide_loading()   # the HUD starts on black and fades in
	if Game.settings.get("painterly", true):
		add_child(preload("res://src/fx/post_fx.gd").new())
	if ResourceLoader.exists("res://src/audio/level_audio.gd"):
		audio = load("res://src/audio/level_audio.gd").new()
		audio.level = self
		add_child(audio)
	_load_hints()


func _parse_features() -> void:
	for f in data.get("features", []):
		var x: float = f["x"]
		match f["type"]:
			"puddle":
				puddles.append([x - f.get("w", 1.0) * 0.5, x + f.get("w", 1.0) * 0.5, f.get("deep", false)])
			"sun":
				sun_zones.append([x, x + float(f["w"])])
				dry_zones.append([x, x + float(f["w"]), Tun.f("dry_sun_rate"), true])
			"vent":
				var w: float = f.get("w", 1.6)
				dry_zones.append([x - w * 0.5, x + w * 0.5, Tun.f("dry_vent_rate"), false])
			"fire_barrel":
				var w2: float = f.get("w", 1.8)
				dry_zones.append([x - w2 * 0.5, x + w2 * 0.5, Tun.f("dry_vent_rate") * 1.2, false])
	for g in builder.gutters:
		gutters.append(g["x"])
	track = builder.track
	for pr in data.get("props", []):
		if pr.get("id", "") == "phone_booth" and pr.get("ring", false):
			phones.append({"x": float(pr["x"]), "keep": bool(pr.get("keep", false)), "line": String(pr.get("line", ""))})
	_join_sun_to_cover()


## Sun breaks sit inset in an open lot, leaving a strip of rain between the break and the awning
## next to it — walking from the sun into the shelter got you briefly soaked at the awning's edge.
## Widen each break's rain-free span (not its drying) to meet cover that starts close by, running
## SUN_COVER_OVERLAP under it so the whole body is sheltered before the rain resumes.
const SUN_COVER_GAP := 2.0
const SUN_COVER_OVERLAP := 0.5


func _join_sun_to_cover() -> void:
	for z in sun_zones:
		for lot in data.get("lots", []):
			if String(lot.get("cover", "none")) == "none":
				continue
			var l0: float = lot["x"]
			var l1: float = l0 + float(lot["w"])
			if l0 >= z[1] and l0 - z[1] < SUN_COVER_GAP:
				z[1] = l0 + SUN_COVER_OVERLAP
			elif l1 <= z[0] and z[0] - l1 < SUN_COVER_GAP:
				z[0] = l1 - SUN_COVER_OVERLAP


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


## The sun only dries what the umbrella isn't shading; vents and barrels warm you either way.
func dry_rate(x: float, umbrella_open: float) -> float:
	var r := 0.0
	for z in dry_zones:
		if x > z[0] and x < z[1]:
			r += z[2] * (1.0 - umbrella_open if z[3] else 1.0)
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


## Whether a train's sheet of water is falling at x at level-clock time t. Callers pass `elapsed`,
## which a checkpoint restores, so trains stay in sync after a resume.
func wash_at(x: float, t: float) -> bool:
	return track != null and track.wash_at(x, t)


## Seconds until a train's sheet next falls at x (0 while it is falling there, INF off the track).
func wash_eta(x: float, t: float) -> float:
	return track.wash_eta(x, t) if track else INF


## A payphone rings from PHONE_HEAR before the walker reaches it until he passes it, or, with `keep`,
## until he answers it (holds stop beside it).
const PHONE_HEAR := 18.0


func phone_ringing(i: int, px: float) -> bool:
	var ph: Dictionary = phones[i]
	if _seen.has("phone@%d" % i) or ph["x"] - px > PHONE_HEAR:
		return false
	return px <= ph["x"] or ph["keep"]


func progress() -> float:
	return clampf(player.position.x / end_x, 0.0, 1.0) if player else 0.0


# --- loop -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if player and player.state != Player.State.DEFEATED and player.state != Player.State.DONE and not finished:
		elapsed += delta
	_update_camera(delta)
	if player:
		_first_encounters()
		_street_hints()
		_train_and_phone_hints(delta)
		_update_gutter_streams()
		_check_checkpoints()
	if Game.autopilot and Game.trace_path != "" and player:
		_write_trace()
	if Game.autopilot and player and int(_t / 10.0) != int((_t - delta) / 10.0):
		print("t=%.0f x=%.1f wet=%.1f sta=%.1f open=%.2f state=%d" % [_t, player.position.x, player.wet, player.stamina, player.open, player.state])
	if Input.is_action_just_pressed(&"restart") and not get_tree().paused:
		Game.play_level(level_id)


var _trace_file: FileAccess
var _trace_next_x := 0.0


func _write_trace() -> void:
	if _trace_file == null:
		_trace_file = FileAccess.open(Game.trace_path, FileAccess.WRITE)
		if _trace_file == null:
			push_error("cannot open trace file " + Game.trace_path)
			Game.trace_path = ""
			return
	var done: bool = player.state == Player.State.DONE or player.state == Player.State.DEFEATED
	if player.position.x < _trace_next_x and not done:
		return
	_trace_next_x = player.position.x + 0.25
	var row := {"t": snappedf(_t, 0.01), "x": snappedf(player.position.x, 0.01), "wet": snappedf(player.wet, 0.01),
		"stamina": snappedf(player.stamina, 0.1), "open": snappedf(player.open, 0.01), "tilt": snappedf(player.tilt, 0.01),
		"sheltered": player.sheltered, "speed": snappedf(player.speed, 0.01), "hurry": snappedf(player.hurry, 0.01),
		"exhausted": player.exhausted, "state": int(player.state), "stats": player.stats.duplicate()}
	_trace_file.store_line(JSON.stringify(row))
	_trace_file.flush()


## When the umbrella is catching a gutter stream, cut the falling column off at the canopy and
## move its splash up onto the umbrella, so what you see matches what you hear.
func _update_gutter_streams() -> void:
	for gv in gutter_visuals:
		var gx: float = gv[0]
		var col: MeshInstance3D = gv[1]
		var sp: GPUParticles3D = gv[2]
		var top: float = gv[3]
		var bottom := 0.02
		if absf(gx - player.position.x) < 1.6 and player.gutter_on_umbrella > 0.0:
			# canopy surface height at the stream (dome: highest at the shaft)
			var c: Vector3 = player.umbrella.canopy_center()
			var r: float = maxf(player.umbrella.current_radius(), 0.01)
			var d := clampf(absf(gx - c.x) / r, 0.0, 1.0)
			bottom = c.y + 0.15 - 0.3 * d * d
		var h := top - bottom
		col.scale.y = h
		col.position.y = bottom + h * 0.5
		sp.position.y = bottom + 0.03


var _seen := {}
var _next_cp := 0


func _check_checkpoints() -> void:
	if finished or (player.state != Player.State.WALK and player.state != Player.State.STOPPED):
		return
	while _next_cp < checkpoints.size() and player.position.x >= float(checkpoints[_next_cp]):
		_take_checkpoint(_next_cp)


## Remembers the walker's state at checkpoint `i` so a failed run can resume from it.
func _take_checkpoint(i: int) -> void:
	Game.checkpoint = {"id": level_id, "index": i, "x": float(checkpoints[i]), "wet": player.wet,
		"stamina": player.stamina, "exhausted": player.exhausted, "elapsed": elapsed, "stats": player.stats.duplicate(),
		"seen": _seen.duplicate(), "car_hints": _car_hints}
	_next_cp = i + 1


## Restores the walker's state from `Game.checkpoint`; _ready already spawned him at its x.
func _restore_checkpoint() -> void:
	var cp := Game.checkpoint
	player.wet = cp["wet"]
	player.stamina = cp["stamina"]
	player.exhausted = cp["exhausted"]
	player.stats = cp["stats"].duplicate()
	elapsed = cp["elapsed"]
	_seen = cp["seen"].duplicate()
	_car_hints = cp["car_hints"]
	_next_cp = int(cp["index"]) + 1
	resumed = true


var _hints: Array = []   # [x, text, duration] from the level's `hints`, ascending x
var _next_hint := 0


## A checkpoint resume spawns the walker past some hints; those stay spent.
func _load_hints() -> void:
	for h in data.get("hints", []):
		_hints.append([float(h["x"]), String(h["text"]), float(h.get("dur", 4.0))])
	_hints.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	while _next_hint < _hints.size() and _hints[_next_hint][0] <= player.position.x:
		_next_hint += 1


## Each of the level's `hints` shows once, as the walker passes its x.
func _street_hints() -> void:
	while _next_hint < _hints.size() and player.position.x >= _hints[_next_hint][0]:
		var h: Array = _hints[_next_hint]
		_next_hint += 1
		if hud:
			hud.hint(h[1], h[2])


## One-off contextual hints the first time each mechanic shows up in a level.
func _first_encounters() -> void:
	if hud == null or not hud.has_method("hint") or player.state != Player.State.WALK:
		return
	var x := player.position.x
	if not _seen.has("gutter"):
		for g in gutters:
			if g - x > 0.0 and g - x < 5.0:
				_seen["gutter"] = true
				hud.hint("Overflowing gutter ahead — keep the umbrella upright as you pass under it.", 3.5)
	if not _seen.has("sun"):
		for z in sun_zones:
			if z[0] - x > 0.0 and z[0] - x < 4.0:
				_seen["sun"] = true
				hud.hint("A break in the clouds. Close the umbrella and let the sun dry you off.", 3.5)
	if not _seen.has("wind") and absf(wind(x)) > 0.18:
		_seen["wind"] = true
		hud.hint("The wind is slanting the rain — tilt the umbrella into it ({tilt}).", 4.0)
	if not _seen.has("stop") and player.stamina <= Tun.f("stop_threshold") * Tun.f("stamina_max") and player.sheltered:
		_seen["stop"] = true
		hud.hint("Puffed out? Hold {stop} to stand still under cover and catch your breath.", 3.5)


const PHONE_ANSWER_M := 1.5
const PHONE_ANSWER_S := 0.6
var _phone_hold := 0.0


## The first train's warning, and a phone's `line` once he holds stop beside it while it rings
## (which answers it).
func _train_and_phone_hints(delta: float) -> void:
	if hud == null or not hud.has_method("hint"):
		return
	var x := player.position.x
	if not _seen.has("train") and player.state == Player.State.WALK and wash_eta(x, elapsed) <= Track.WARN_S:
		_seen["train"] = true
		hud.hint("Train coming. The viaduct sheds water when it passes. Wait it out ({stop}) or hurry ({hurry}).", 4.5)
	var near := -1
	for i in phones.size():
		if phones[i]["line"] != "" and absf(phones[i]["x"] - x) < PHONE_ANSWER_M and phone_ringing(i, x):
			near = i
	_phone_hold = _phone_hold + delta if near >= 0 and player.state == Player.State.STOPPED else 0.0
	if _phone_hold >= PHONE_ANSWER_S:
		_seen["phone@%d" % near] = true
		_phone_hold = 0.0
		hud.hint(phones[near]["line"], 5.0)


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
		hud.hint("Headlights! Tilt the umbrella forward to block the splash  ({tilt_forward})", 3.5)


func _on_defeated() -> void:
	_cam_locked = true
	if hud and hud.has_method("close_pause"):
		hud.close_pause()
	if Game.autopilot and Game._shots.is_empty():
		print("AUTOPILOT_DEFEATED x=%.1f t=%.1f stats=%s" % [player.position.x, elapsed, JSON.stringify(player.stats)])
		get_tree().quit()
		return
	# Let him trudge off the left of the frozen screen before the fail card.
	var t := 0.0
	while t < 7.0:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		if get_tree().paused:
			continue
		t += get_process_delta_time()
		if t > 3.5 and player.position.x < camera.position.x - 6.5:
			break
	hud.show_fail()


func _on_arrived() -> void:
	finished = true
	var wet := player.wet
	var t := elapsed
	while player.state != Player.State.DONE:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	await get_tree().create_timer(0.6, false).timeout
	if not is_inside_tree():
		return
	var result := Game.finish_level(level_id, wet, t, par_time)
	if Game.autopilot and Game._shots.is_empty():
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
	if Game.settings["low_quality"]:
		GraphicsCheck.apply_low(env, moon)


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
