class_name Player
extends Node3D
## The walker: auto-walks along +X, the player only controls the umbrella, hurry, stop and tilt.
## Owns stamina, wetness and the analytic rain-exposure model (docs/DESIGN.md §5).

signal stop_refused
signal defeated
signal arrived
signal splashed(amount: float)
signal puddle_stepped(pos: Vector3, running: bool)
signal footstep(running: bool)

enum State { WALK, STOPPED, DEFEATED, ENTERING, DONE }

const COVER_MASK := 1 << 1
const UMBRELLA_MASK := 1 << 3
const CHARACTER_SCENE := "res://assets/characters/walker/walker.tscn"

## Body sample points (local, facing +X) and their weights for exposure.
const SAMPLES := [
	[Vector3(0.0, 1.74, 0.0), 2.0],     # head
	[Vector3(0.02, 1.5, 0.19), 1.4],    # shoulders
	[Vector3(0.02, 1.5, -0.19), 1.4],
	[Vector3(0.13, 1.22, 0.0), 1.0],    # chest
	[Vector3(-0.13, 1.22, 0.0), 1.0],   # back
	[Vector3(0.0, 0.95, 0.12), 0.8],    # hips
	[Vector3(0.12, 0.55, 0.0), 0.6],    # knees
	[Vector3(-0.1, 0.55, 0.0), 0.5],
	[Vector3(0.14, 0.18, 0.0), 0.4],    # shins / shoes
]

var level: Node                    # the Level (provides rain_intensity, wind, dry_rate, ground_y...)
var state := State.WALK
var speed := 0.0
var run_amount := 0.0
var open := 0.0
var tilt := 0.0
var droop := 0.0
var stamina := 100.0
var wet := 0.0
var exposure := 0.0                # 0..1 rain exposure this frame (for HUD/FX)
var gutter_hit := 0.0
var exhausted := false
var hurry := 0.0
var drying := 0.0                  # current dry rate (for FX)
var sheltered := false             # head is under fixed cover (awning/balcony)
var stats := {"exposure_time": 0.0, "splashes": 0, "puddles": 0, "wet_rain": 0.0, "wet_gutter": 0.0, "wet_puddle": 0.0, "wet_splash": 0.0, "dried": 0.0}

var visual: Node3D
var umbrella: Umbrella
var _prev_x := 0.0
var _step_phase := 0.0
var _end_t := 0.0
var _dropped_umbrella := false
var _ap_hold := 0.0
var _drips: GPUParticles3D                 # autopilot: keep umbrella up a little after leaving rain


func _ready() -> void:
	stamina = Tun.f("stamina_max")
	if ResourceLoader.exists(CHARACTER_SCENE):
		visual = (load(CHARACTER_SCENE) as PackedScene).instantiate()
	else:
		visual = Node3D.new()
		visual.set_script(load("res://src/player/placeholder_character.gd"))
	add_child(visual)
	umbrella = Umbrella.new()
	# Umbrella lives in world space (it is positioned from the grip each frame, and can be dropped).
	umbrella.top_level = true
	add_child(umbrella)
	_prev_x = position.x
	# Soft fill light so the walker reads against the dark street.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.7
	fill.omni_range = 3.2
	fill.omni_attenuation = 1.5
	fill.position = Vector3(0.35, 1.15, 1.7)
	fill.light_specular = 0.3
	add_child(fill)
	_drips = GPUParticles3D.new()
	_drips.amount = 40
	_drips.lifetime = 0.6
	_drips.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.18, 0.5, 0.16)
	pm.gravity = Vector3(0, -9.8, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	_drips.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.05)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(0.75, 0.82, 0.95, 0.6)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = dm
	_drips.draw_pass_1 = q
	_drips.position = Vector3(0, 1.0, 0)
	_drips.emitting = false
	add_child(_drips)


func _physics_process(delta: float) -> void:
	match state:
		State.DEFEATED:
			_process_defeated(delta)
			return
		State.ENTERING, State.DONE:
			_process_entering(delta)
			return

	var u: float
	var h: float
	var tl: float
	var stop_req: bool
	if Game.autopilot:
		var ap := _autopilot(delta)
		if Game.debug_human:
			ap = _humanise(ap, delta)
		if Game.debug_lazy:
			ap[0] = 0.0
		u = ap[0]; h = ap[1]; tl = ap[2]; stop_req = ap[3]
	else:
		u = Inputs.umbrella()
		h = Inputs.hurry()
		tl = Inputs.tilt()
		stop_req = Inputs.stop_pressed()

	var smax := Tun.f("stamina_max")
	# --- umbrella open/close: same speed both ways, reverses from wherever it is ---------------
	var open_rate := 1.0 / maxf(Game.umbrella_open_time(), 0.05)
	open = move_toward(open, u, open_rate * delta)
	if open <= 0.0:
		Inputs.wheel_tilt = 0.0
	var max_tilt := Tun.f("umbrella_max_tilt")
	tilt = move_toward(tilt, tl * max_tilt if open > 0.0 else 0.0, Tun.f("umbrella_tilt_speed") * delta)

	# --- stop -------------------------------------------------------------------------------
	if stop_req and state == State.WALK:
		if stamina <= Tun.f("stop_threshold") * smax:
			state = State.STOPPED
		else:
			stop_refused.emit()
	if state == State.STOPPED and (stamina >= smax - 0.01 or h > 0.5):
		state = State.WALK   # resumes at full stamina, or early if the player hurries off

	# --- stamina ----------------------------------------------------------------------------
	var wind := _wind()
	hurry = h if (not exhausted and stamina > 0.0 and state == State.WALK) else 0.0
	var drain := 0.0
	if open > 0.0:
		drain += Tun.f("stamina_drain_umbrella") * open * Game.umbrella_drain_mult()
		drain += Tun.f("stamina_drain_wind") * wind * wind * open * Game.umbrella_drain_mult()
	if hurry > 0.0:
		# Scales from zero so a lightly-resting trigger costs almost nothing.
		drain += Tun.f("stamina_drain_hurry") * minf(hurry * 2.0, 1.0) + (Tun.f("stamina_drain_run") - Tun.f("stamina_drain_hurry")) * maxf(hurry * 2.0 - 1.0, 0.0)
	if open <= 0.0 and hurry < 0.05:
		stamina += (Tun.f("stamina_regen_stopped") if state == State.STOPPED else Tun.f("stamina_regen")) * delta
	stamina = clampf(stamina - drain * delta, 0.0, smax)
	if stamina <= 0.0 and drain > 0.0:
		exhausted = true
	elif exhausted and stamina >= Tun.f("exhausted_recover") * smax:
		exhausted = false
	droop = move_toward(droop, 1.0 if (exhausted and open > 0.0) else 0.0, 1.5 * delta)

	# --- speed ------------------------------------------------------------------------------
	var target := lerpf(Tun.f("walk_speed"), Tun.f("walk_speed_umbrella"), open)
	if hurry > 0.0:
		var fast := lerpf(Tun.f("hurry_speed"), Tun.f("run_speed"), clampf((hurry - 0.5) * 2.0, 0.0, 1.0))
		fast = lerpf(fast, fast * 0.75, open)
		target = lerpf(target, fast, clampf(hurry * 2.0, 0.0, 1.0))
	if wind < 0.0:
		target *= 1.0 - Tun.f("headwind_slow") * -wind * open
	if exhausted:
		target *= 0.85
	if state == State.STOPPED:
		target = 0.0
	speed = move_toward(speed, target, Tun.f("speed_response") * delta)
	run_amount = clampf((speed - Tun.f("walk_speed")) / (Tun.f("run_speed") - Tun.f("walk_speed")), 0.0, 1.0)
	# Position is integrated per render frame in _process (smooth at any refresh rate);
	# physics only decides the speed.
	_footsteps(delta)

	# --- wetness ----------------------------------------------------------------------------
	_update_umbrella()
	var intensity: float = level.rain_intensity(position.x)
	exposure = _rain_exposure() if intensity > 0.0 else 0.0
	var head := _sample_world(SAMPLES[0][0])
	sheltered = _cast(head, head - rain_dir() * 30.0, COVER_MASK)
	var gain := exposure * intensity * Tun.f("wet_rain_rate")
	if exposure > 0.05:
		stats["exposure_time"] += delta
	stats["wet_rain"] += gain * delta
	gutter_hit = _gutter_exposure()
	gain += gutter_hit * Tun.f("wet_gutter_rate")
	stats["wet_gutter"] += gutter_hit * Tun.f("wet_gutter_rate") * delta
	_check_puddles()
	drying = level.dry_rate(position.x)
	stats["dried"] += minf(drying * delta, wet)
	wet = clampf(wet + (gain - drying) * delta, 0.0, Tun.f("wet_max"))
	if wet >= Tun.f("wet_max"):
		_defeat()
		return
	_prev_x = position.x
	if position.x >= level.end_x:
		_begin_entering()


func _process(delta: float) -> void:
	if visual == null:
		return
	if state == State.WALK or state == State.STOPPED:
		position.x += speed * delta
		position.y = level.ground_y(position.x)
	visual.set_motion(speed, run_amount)
	visual.set_stopped(state == State.STOPPED or (state == State.DONE))
	visual.set_umbrella_pose(arm_raise() if not _dropped_umbrella else 0.0, tilt, droop)
	visual.set_wetness(wet / Tun.f("wet_max"))
	var w01 := wet / Tun.f("wet_max")
	_drips.emitting = w01 > 0.15 and visible
	_drips.amount_ratio = clampf(w01, 0.0, 1.0)
	_update_umbrella()


## The arm comes up during the first third of the opening; the canopy spreads after.
func arm_raise() -> float:
	return smoothstep(0.0, 0.35, open)


func _wind() -> float:
	return level.wind(position.x) if level else 0.0


func rain_dir() -> Vector3:
	return level.rain_dir(position.x)


func _update_umbrella() -> void:
	if _dropped_umbrella or visual == null:
		return
	var hand: StringName = &"right" if open > 0.0 else &"left"
	var grip: Node3D = visual.get_grip(hand)
	if grip:
		umbrella.global_transform = grip.global_transform
	umbrella.set_state(open, Game.umbrella_radius(), droop)


# --- exposure -------------------------------------------------------------------------------

func _cast(from: Vector3, to: Vector3, mask: int) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.hit_back_faces = true
	q.hit_from_inside = true
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _sample_world(local: Vector3) -> Vector3:
	return global_transform * local


## Fraction (weighted 0..1) of body samples that rain can reach.
func _rain_exposure() -> float:
	var up := -rain_dir() * 30.0
	var total := 0.0
	var hit := 0.0
	for s in SAMPLES:
		var p := _sample_world(s[0])
		total += s[1]
		if not _cast(p, p + up, COVER_MASK | UMBRELLA_MASK):
			hit += s[1]
	return hit / total


## Gutter streams: a heavy column of water at a fixed x, only the umbrella blocks it.
func _gutter_exposure() -> float:
	for g in level.gutters:
		if absf(position.x - g) < 0.45:
			# The stream is a vertical column at x = g. Body points inside it get soaked unless
			# something (the umbrella) is directly above them in the column.
			var total := 0.0
			var hit := 0.0
			for s in SAMPLES:
				var p := _sample_world(s[0])
				if absf(p.x - g) > 0.22:
					continue
				total += s[1]
				var at := Vector3(g, p.y, p.z)
				if not _cast(at, Vector3(g, 2.9, p.z), UMBRELLA_MASK):
					hit += s[1]
			return hit / total if total > 0.0 else 0.0
	return 0.0


func _check_puddles() -> void:
	for p in level.puddles:
		var x0: float = p[0]
		if _prev_x < x0 and position.x >= x0:
			var running := run_amount > 0.45
			var amt := Tun.f("wet_puddle_run") if running else Tun.f("wet_puddle_walk")
			if p[2]:
				amt *= 1.6
			wet += amt
			stats["puddles"] += 1
			stats["wet_puddle"] += amt
			puddle_stepped.emit(global_position + Vector3(0.2, 0, 0), running)


## Called by hazards (car splash). Rays from body samples toward `source`; umbrella/cover blocks.
func receive_splash(source: Vector3, amount: float) -> void:
	if state != State.WALK and state != State.STOPPED:
		return
	var total := 0.0
	var hit := 0.0
	for s in SAMPLES:
		var p := _sample_world(s[0])
		total += s[1]
		if not _cast(p, source, UMBRELLA_MASK | COVER_MASK):
			hit += s[1]
	var got := amount * hit / total
	wet = minf(wet + got, Tun.f("wet_max"))
	stats["splashes"] += 1
	stats["wet_splash"] += got
	splashed.emit(got)


func _footsteps(delta: float) -> void:
	if speed < 0.1:
		return
	var stride := lerpf(0.75, 1.1, run_amount)
	_step_phase += speed * delta / stride
	if _step_phase >= 1.0:
		_step_phase -= 1.0
		footstep.emit(run_amount > 0.45)


# --- end states -----------------------------------------------------------------------------

func _defeat() -> void:
	state = State.DEFEATED
	visual.set_mood(&"sad")
	_drop_umbrella()
	_end_t = 0.0
	defeated.emit()


func _drop_umbrella() -> void:
	_dropped_umbrella = true
	open = 0.0
	var start := umbrella.global_transform
	var land := Transform3D(Basis.from_euler(Vector3(0.2, randf() * TAU, PI * 0.55)),
		Vector3(start.origin.x + 0.25, level.ground_y(start.origin.x) + 0.1, start.origin.z + 0.3))
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		umbrella.global_transform = start.interpolate_with(land, t), 0.0, 1.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	umbrella.set_state(0.35, Game.umbrella_radius(), 0.0)


func _process_defeated(delta: float) -> void:
	_end_t += delta
	if _end_t < 0.9:
		speed = move_toward(speed, 0.0, 3.0 * delta)
		return
	rotation.y = move_toward(rotation.y, PI, 4.0 * delta)
	speed = move_toward(speed, 0.75, 1.5 * delta)
	position.x -= speed * delta
	position.y = level.ground_y(position.x)


func _begin_entering() -> void:
	state = State.ENTERING
	_end_t = 0.0
	arrived.emit()


func _process_entering(delta: float) -> void:
	_end_t += delta
	open = move_toward(open, 0.0, delta / maxf(Game.umbrella_open_time(), 0.05))
	_update_umbrella()
	if open > 0.0:
		speed = move_toward(speed, 0.5, 2.0 * delta)
		position.x += speed * delta
		return
	# Turn toward the door (−Z) and walk in.
	rotation.y = move_toward(rotation.y, PI * 0.5, 3.0 * delta)
	speed = move_toward(speed, 1.0, 2.0 * delta)
	if rotation.y > 1.2:
		position.z -= speed * delta
	if position.z < -1.2:
		state = State.DONE
		visible = false


# --- autopilot (testing bot) ----------------------------------------------------------------

var _ap_queue: Array = []
var _ap_t := 0.0
const HUMAN_DELAY := 0.4


## Delays the bot's decisions by a human reaction time and makes it a little sloppy.
func _humanise(ap: Array, delta: float) -> Array:
	_ap_t += delta
	_ap_queue.append([_ap_t, ap])
	var out: Array = _ap_queue[0][1]
	while _ap_queue.size() > 1 and _ap_t - float(_ap_queue[1][0]) >= HUMAN_DELAY:
		_ap_queue.pop_front()
		out = _ap_queue[0][1]
	out = out.duplicate()
	out[1] = 0.0 if stamina < 95.0 else out[1]   # humans hurry less precisely
	return out

func _exposed_at(x: float, height := 1.6) -> bool:
	var p := Vector3(x, level.ground_y(x) + height, position.z)
	return not _cast(p, p - rain_dir() * 30.0, COVER_MASK)


## Returns [umbrella, hurry, tilt, stop].
func _autopilot(delta: float) -> Array:
	var lead := maxf(speed, Tun.f("walk_speed")) * Game.umbrella_open_time() + 0.6
	var rd0 := rain_dir()
	var tl0 := clampf(-atan2(rd0.x, -rd0.y) / Tun.f("umbrella_max_tilt"), -1.0, 1.0)
	if state == State.STOPPED:
		return [1.0 if exposure > 0.2 else 0.0, 0.0, tl0, false]
	var danger := false
	var dx := -0.4
	while dx <= lead:
		if _exposed_at(position.x + dx) or _exposed_at(position.x + dx + 0.15, 0.9):
			danger = true
			break
		dx += 0.2
	for g in level.gutters:
		if g - position.x > -0.6 and g - position.x < lead:
			danger = true
	var car_ahead: bool = level.car_threat(position.x)
	if car_ahead:
		danger = true
	_ap_hold = 0.35 if danger else maxf(0.0, _ap_hold - delta)
	var u := 1.0 if (danger or _ap_hold > 0.0) else 0.0
	var h := 0.0
	if not danger and stamina > 80.0 and open <= 0.0:
		h = 0.5
	var rd := rain_dir()
	var tl := clampf(-atan2(rd.x, -rd.y) / Tun.f("umbrella_max_tilt"), -1.0, 1.0)
	if car_ahead:
		tl = 1.0
	for g in level.gutters:
		if absf(g - position.x) < 0.9:
			tl = 0.0     # straighten up under a gutter stream
	var stop := false
	if stamina <= Tun.f("stop_threshold") * Tun.f("stamina_max") - 1.0 and sheltered:
		stop = true
		for off in [-0.9, -0.45, 0.0, 0.45, 0.9]:
			if _exposed_at(position.x + off) or _exposed_at(position.x + off, 0.5):
				stop = false
		for g in level.gutters:
			if absf(g - position.x) < 1.2:
				stop = false
	return [u, h, tl, stop]
