extends Node
## Level soundscape. Rain layers follow intensity; under cover the open-rain bed is muffled and
## the awning patter comes up; the umbrella drums when open in the rain; music loses its top end
## as the walker gets wetter. Missing files are skipped silently (audio is optional content).

const DIR := "res://assets/audio/"

var level: Node
var _loops := {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _prev_open := 0.0
var _open_dir := 0
var _music_filter: AudioEffectLowPassFilter
var _rain_filter: AudioEffectLowPassFilter
var _cache := {}


func _ready() -> void:
	_setup_buses()
	_loop("rain_light", "rain_light_loop", "Rain")
	_loop("rain_heavy", "rain_heavy_loop", "Rain")
	_loop("awning", "rain_on_awning_loop", "SFX")
	_loop("umbrella", "rain_on_umbrella_loop", "SFX")
	_loop("wind", "wind_loop", "SFX")
	_loop("traffic", "traffic_distant_loop", "SFX")
	_loop("music", "music_level_loop", "Music")
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)
	for g in level.gutters:
		var s := _stream("gutter_loop")
		if s:
			var p3 := AudioStreamPlayer3D.new()
			p3.stream = s
			p3.bus = &"SFX"
			p3.max_distance = 14.0
			p3.unit_size = 2.0
			p3.position = Vector3(g, 1.2, 1.6)
			p3.autoplay = true
			level.world.add_child(p3)
	var pl: Player = level.player
	pl.footstep.connect(func(running: bool) -> void:
		play(("footstep_run_%d" if running else "footstep_wet_%d") % randi_range(1, 4), -8.0 if not running else -5.0, randf_range(0.92, 1.08)))
	pl.puddle_stepped.connect(func(_p: Vector3, running: bool) -> void: play("puddle_splash", 0.0 if running else -4.0))
	pl.splashed.connect(func(amount: float) -> void: play("car_splash", lerpf(-8.0, 2.0, clampf(amount / 25.0, 0.0, 1.0))))
	pl.defeated.connect(func() -> void:
		play("umbrella_drop", -2.0)
		get_tree().create_timer(1.2).timeout.connect(func() -> void: play("fail_sting", -3.0)))
	pl.arrived.connect(func() -> void:
		get_tree().create_timer(1.6).timeout.connect(func() -> void: play("door_open", -4.0))
		get_tree().create_timer(2.4).timeout.connect(func() -> void: play("win_sting", -4.0)))
	for car in level.cars:
		car.approaching.connect(func() -> void: _play_3d("car_pass", car, 4.0))
		car.splashed_puddle.connect(func(at: Vector3) -> void: _play_3d_at("car_splash", at, 2.0))


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX", "Rain"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(idx, lp)
	_music_filter = AudioServer.get_bus_effect(AudioServer.get_bus_index("Music"), 0)
	_rain_filter = AudioServer.get_bus_effect(AudioServer.get_bus_index("Rain"), 0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(Game.settings.get("music", 0.7)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(Game.settings.get("sfx", 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Rain"), linear_to_db(Game.settings.get("sfx", 1.0)))


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(DIR + name + ext):
			s = load(DIR + name + ext)
			break
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = name.ends_with("_loop")
	elif s is AudioStreamWAV and name.ends_with("_loop"):
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
	_cache[name] = s
	return s


func _loop(key: String, file: String, bus: String) -> void:
	var s := _stream(file)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	p.play(randf() * maxf(s.get_length() - 1.0, 0.0))
	_loops[key] = p


func _set_loop(key: String, linear: float, delta: float, speed := 3.0) -> void:
	if not _loops.has(key):
		return
	var p: AudioStreamPlayer = _loops[key]
	var cur := db_to_linear(p.volume_db)
	cur = move_toward(cur, clampf(linear, 0.0, 1.5), speed * delta)
	p.volume_db = linear_to_db(maxf(cur, 0.0001))


func play(name: String, db := 0.0, pitch := 1.0) -> void:
	var s := _stream(name)
	if s == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = s
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return


func _play_3d(name: String, parent: Node3D, db: float) -> void:
	var s := _stream(name)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = &"SFX"
	p.volume_db = db
	p.max_distance = 60.0
	p.unit_size = 6.0
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _play_3d_at(name: String, at: Vector3, db: float) -> void:
	var holder := Node3D.new()
	level.world.add_child(holder)
	holder.global_position = at
	_play_3d(name, holder, db)
	get_tree().create_timer(4.0).timeout.connect(holder.queue_free)


func car_pass(car: Node3D) -> void:
	_play_3d("car_pass", car, 0.0)


func _process(delta: float) -> void:
	var pl: Player = level.player
	if pl == null:
		return
	var x := pl.position.x
	var inten: float = level.rain_intensity(x)
	var heavy := clampf((inten - 0.8) / 0.5, 0.0, 1.0)
	var sheltered := pl.sheltered
	var under_umbrella := pl.umbrella.open > 0.3 and not sheltered
	# Open-rain bed: always present, muffled when sheltered / under the umbrella.
	_set_loop("rain_light", inten * (1.0 - heavy * 0.6) * 0.8, delta)
	_set_loop("rain_heavy", inten * heavy * 0.9, delta)
	if _rain_filter:
		var target := 20000.0
		if sheltered:
			target = 2200.0
		elif under_umbrella:
			target = 5000.0
		_rain_filter.cutoff_hz = lerpf(_rain_filter.cutoff_hz, target, 1.0 - exp(-5.0 * delta))
	_set_loop("awning", (0.75 if sheltered else 0.0) * inten, delta)
	_set_loop("umbrella", pl.umbrella.open * inten * (0.0 if sheltered else 0.9), delta, 6.0)
	_set_loop("wind", absf(level.wind(x)) * 1.2, delta)
	_set_loop("traffic", 0.25, delta)
	var defeated := pl.state == Player.State.DEFEATED
	_set_loop("music", 0.0 if defeated else 0.55, delta, 0.6)
	if _music_filter:
		var wet := pl.wet / Tun.f("wet_max")
		_music_filter.cutoff_hz = lerpf(18000.0, 900.0, clampf(wet * 1.1, 0.0, 1.0))
	# Umbrella open/close sound when the motion starts in a new direction.
	var d := signf(pl.open - _prev_open)
	if d != 0.0 and int(d) != _open_dir:
		_open_dir = int(d)
		if d > 0.0 and _prev_open < 0.5:
			play("umbrella_open", -4.0, randf_range(0.95, 1.05))
		elif d < 0.0 and _prev_open > 0.5:
			play("umbrella_close", -5.0, randf_range(0.95, 1.05))
	_prev_open = pl.open
