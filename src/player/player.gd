class_name Player
extends WetBody
## The walker: auto-walks along +X, the player only controls the umbrella, hurry, stop and tilt
## (and, on armed streets, the water shot: WaterGun). Owns stamina, wetness and the analytic
## rain-exposure model (docs/DESIGN.md §5); splashes and shots wet him through WetBody.

signal defeated
signal arrived
signal splashed(amount: float)
signal puddle_stepped(pos: Vector3, running: bool)
signal footstep(running: bool)

enum State { WALK, STOPPED, DEFEATED, ENTERING, DONE }
const HIT_BLAME_S := 1.5

const COVER_MASK := 1 << 1
const UMBRELLA_MASK := 1 << 3
const HIP_Y := 0.95                # lean pivot for the body samples
const NECK_Y := 1.55               # head-duck pivot
const RAIN_SKY_Y := 3.6            # above every cover: where a drop's x decides if it's raining
const CHARACTER_SCENE := "res://assets/characters/walker/walker.tscn"

var state := State.WALK
var run_amount := 0.0
var open := 0.0
var tilt := 0.0                    # rad the shaft leans from upright (+ ahead): the open canopy's tilt, or the raised furled shaft's aim
var _debug_t := 0.0
var aim := 0.0                     # 0..1 the furled shaft raised to aim (armed streets only)
var droop := 0.0
var stamina := 100.0
var exposure := 0.0                # 0..1 rain exposure this frame (for HUD/FX)
var gutter_hit := 0.0
var exhausted := false
var hurry := 0.0
var drying := 0.0                  # current dry rate (for FX)
var sheltered := false             # head is under fixed cover (awning/balcony)
var gutter_on_umbrella := 0.0      # 0..1 how much of a gutter stream the umbrella is catching
var stats := {"exposure_time": 0.0, "splashes": 0, "puddles": 0, "wet_rain": 0.0, "wet_gutter": 0.0, "wet_splash": 0.0, "wet_wash": 0.0, "wet_rotor": 0.0, "wet_hit": 0.0, "dried": 0.0}
var fail_cause := &"wet"         # what ended the attempt (HUD.FAIL_TITLES): wet, shot, lost, made
var jet_kick := 0.0                # 0..1: a blocked jet has knocked the canopy aside (WaterJet); decays
const JET_KICK_S := 0.7            # a full shove takes this long to recover from
const JET_KICK_TILT := 0.6         # rad the canopy is knocked forward by a full shove
const JET_KICK_DROOP := 0.7        # and how far it sags (as when exhausted)
const RECOIL_TILT := 0.22          # rad the canopy kicks away from a shot as it fires
const AIM_RAISE_S := 0.2           # s to bring the furled shaft up from his side to aim, or back down
const AIM_SWING := 0.8              # share of the raise over which the furled umbrella changes hands
const AIM_READY := 0.9             # how far up the furled shaft must be before it fires
var _hit_cause := &"wet"
var _hit_t := -INF
var _wall_x := INF                 # while a side-street car crosses, the kerb he can't walk past (CarHazard.wall_for)

var gun: WaterGun
var _prev_x := 0.0
var _step_phase := 0.0
var _ap_hold := 0.0
var _ap_resting := false          # autopilot is holding Stop until stamina is full
var _ap_no_rest_before := -INF      # autopilot won't settle to rest again before this x
var _ap_filling := false          # autopilot is stopped under a stream, refilling the shot
var _ap_fill_dry := 0.0           # s it has stood there without the stream refilling it
const FILL_GIVE_UP_S := 1.5
var _drips: GPUParticles3D                 # autopilot: keep umbrella up a little after leaving rain


## Drying runs at full rate only when nearly soaked and slows exponentially as he dries off, so a
## warm spot rescues a bad start but never repays the time spent standing in it. The falloff never
## takes it below `dry_min_rate` (1% of wet_max per 5 s), or above the spot's own rate.
static func dry_speed(spot_rate: float, wet_frac: float) -> float:
	var falloff := exp(-Tun.f("dry_falloff") * maxf(Tun.f("dry_full_above") - wet_frac, 0.0))
	return minf(spot_rate, maxf(spot_rate * falloff, Tun.f("dry_min_rate")))


func _ready() -> void:
	Inputs.new_attempt()
	stamina = Tun.f("stamina_max") if is_nan(Game.debug_stamina) else Game.debug_stamina
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
	gun = WaterGun.new()
	gun.player = self
	gun.armed = Game.armed(level.level_id)
	gun.shots = gun.capacity()
	add_child(gun)
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
			_trudge(delta)
			return
		State.ENTERING, State.DONE:
			_process_entering(delta)
			return

	var u: float
	var h: float
	var tl: float
	var stop_req: bool
	var fire_req: bool
	var aim_in := NAN                # where the furled shaft is aimed (rad), NAN at rest
	var max_tilt := Tun.f("umbrella_max_tilt")
	if Game.autopilot:
		var ap := _autopilot(delta)
		if level.courier:
			ap = level.courier.steer_bot(self, ap)
		if _rotor_threat(Game.umbrella_open_time() + 0.5):
			ap[0] = 1.0   # whoever else wants the canopy tilted, the wash wins: up and upright
			ap[2] = 0.0
		if Game.debug_human:
			ap = _humanise(ap, delta)
		if Game.debug_lazy:
			ap[0] = 0.0
		u = ap[0]; h = ap[1]; tl = ap[2]; stop_req = ap[3]
		fire_req = _autopilot_fire(tl)
		if fire_req and absf(tl) > 0.3:
			aim_in = signf(tl) * max_tilt
	else:
		u = Inputs.umbrella()
		h = Inputs.hurry()
		tl = Inputs.tilt()
		stop_req = Inputs.stop_held()
		fire_req = Inputs.fire_held()
		aim_in = Inputs.aim(max_tilt)

	if not is_nan(Game.debug_tilt):
		u = 1.0; tl = Game.debug_tilt
	_debug_t += delta
	if not is_nan(Game.debug_aim) and _debug_t > 1.0:
		u = 0.0; aim_in = Game.debug_aim * max_tilt
	if Game.debug_fire:
		fire_req = true
	if _debug_t >= Game.debug_stop:
		stop_req = true

	var smax := Tun.f("stamina_max")
	# --- umbrella open/close: same speed both ways, reverses from wherever it is ---------------
	var open_rate := 1.0 / maxf(Game.umbrella_open_time(), 0.05)
	open = move_toward(open, u, open_rate * delta)
	if open <= 0.0 and not gun.armed:
		Inputs.mouse_tilt = 0.0
	# Armed, the furled shaft is the gun: the aim raises it and points it. Firing from rest swings it
	# up toward the side it last fired, and it stays up a moment between shots.
	var furled := gun.armed and open <= 0.0
	if furled and is_nan(aim_in) and (fire_req or gun.holding()):
		aim_in = gun.last_side * max_tilt
	var raised := furled and not is_nan(aim_in)
	aim = move_toward(aim, 1.0 if raised else 0.0, delta / AIM_RAISE_S)
	var tilt_to := tl * max_tilt if open > 0.0 else (aim_in if raised else 0.0)
	tilt = move_toward(tilt, tilt_to, Tun.f("umbrella_tilt_speed") * delta)

	gun.step(delta, fire_req and (open > 0.0 or aim >= AIM_READY and absf(tilt - tilt_to) < 0.15))

	# --- stop -------------------------------------------------------------------------------
	_wall_x = INF
	for c in level.cars:
		if is_instance_valid(c):
			_wall_x = minf(_wall_x, c.wall_for(position.x))
	var held := position.x + speed * delta >= _wall_x
	if state == State.WALK or state == State.STOPPED:
		state = State.STOPPED if stop_req or held else State.WALK

	# --- stamina ----------------------------------------------------------------------------
	var wind := _wind()
	hurry = h if (not exhausted and stamina > 0.0 and state == State.WALK) else 0.0
	var drain := 0.0
	if open > 0.0 and state != State.STOPPED:   # holding it up while standing still is free
		drain += Tun.f("stamina_drain_umbrella") * open * Game.umbrella_drain_mult()
		drain += Tun.f("stamina_drain_wind") * wind * wind * open * Game.umbrella_drain_mult()
	# In a helicopter's wash the open canopy fights the downdraught, standing still or not.
	var rotor: float = level.rotor_at(position.x, level.elapsed) if open > 0.0 else 0.0
	if rotor > 0.0:
		drain += Tun.f("stamina_drain_rotor") * open * rotor * Game.umbrella_drain_mult()
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
	jet_kick = move_toward(jet_kick, 0.0, delta / JET_KICK_S)

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
	if held:
		speed = 0.0
		position.x = _wall_x
	run_amount = clampf((speed - Tun.f("walk_speed")) / (Tun.f("run_speed") - Tun.f("walk_speed")), 0.0, 1.0)
	# Position is integrated per render frame in _process (smooth at any refresh rate);
	# physics only decides the speed.
	_footsteps(delta)

	# --- wetness ----------------------------------------------------------------------------
	_update_umbrella()
	var intensity: float = level.rain_intensity(position.x)
	exposure = _rain_exposure() if intensity > 0.0 else 0.0
	var head := sample_world(SAMPLES[0][0])
	sheltered = _cast(head, head - rain_dir() * 30.0, COVER_MASK)
	var gain := exposure * intensity * Tun.f("wet_rain_rate")
	if exposure > 0.05:
		stats["exposure_time"] += delta
	stats["wet_rain"] += gain * delta
	gutter_hit = _gutter_exposure()
	gain += gutter_hit * Tun.f("wet_gutter_rate")
	stats["wet_gutter"] += gutter_hit * Tun.f("wet_gutter_rate") * delta
	var wash_hit := _wash_exposure()
	gain += wash_hit * Tun.f("wet_wash_rate")
	stats["wet_wash"] += wash_hit * Tun.f("wet_wash_rate") * delta
	var rotor_hit := _rotor_exposure()
	gain += rotor_hit * Tun.f("wet_rotor_rate")
	stats["wet_rotor"] += rotor_hit * Tun.f("wet_rotor_rate") * delta
	_check_puddles()
	drying = dry_speed(level.dry_rate(position.x, open), wet / Tun.f("wet_max"))
	stats["dried"] += minf(drying * delta, wet)
	wet = clampf(wet + (gain - drying) * delta, 0.0, Tun.f("wet_max"))
	if wet >= Tun.f("wet_max"):
		fail(_hit_cause if level.elapsed - _hit_t < HIT_BLAME_S else &"wet")
		return
	_prev_x = position.x
	if position.x >= level.end_x:
		_begin_entering()


func _process(delta: float) -> void:
	if visual == null:
		return
	if state == State.WALK or state == State.STOPPED:
		position.x = minf(position.x + speed * delta, _wall_x)
		position.y = level.ground_y(position.x)
	visual.set_motion(speed, run_amount)
	visual.set_stopped(state == State.STOPPED or (state == State.DONE))
	if visual.has_method("set_winded"):
		visual.set_winded(1.0 - stamina / Tun.f("stamina_max"))
	var kick := jet_kick * JET_KICK_TILT - gun.recoil * RECOIL_TILT * gun.aim_sign()
	visual.set_umbrella_pose(arm_raise() if not _dropped_umbrella else 0.0, tilt + kick, maxf(droop, jet_kick * JET_KICK_DROOP))
	if visual.has_method("set_aim"):
		visual.set_aim(aim if open <= 0.0 and not _dropped_umbrella else 0.0)
	if visual.has_method("set_umbrella_open"):
		visual.set_umbrella_open(open if not _dropped_umbrella else 0.0)
	visual.set_wetness(wet / Tun.f("wet_max"))
	var w01 := wet / Tun.f("wet_max")
	_drips.emitting = w01 > 0.15 and visible
	_drips.amount_ratio = clampf(w01, 0.0, 1.0)
	_update_umbrella()


## The arm comes up during the first part of the opening (the canopy spreads after, Umbrella), or
## to aim the furled shaft.
func arm_raise() -> float:
	return maxf(Umbrella.arm_raise(open), aim)


func _wind() -> float:
	return level.wind(position.x) if level else 0.0


func rain_dir() -> Vector3:
	return level.rain_dir(position.x)


func _update_umbrella() -> void:
	if _dropped_umbrella or visual == null:
		return
	var hand: StringName = &"right" if open > 0.0 or aim > 0.0 else &"left"
	var grip: Node3D = visual.get_grip(hand)
	if grip:
		umbrella.global_transform = grip.global_transform
		# Brought up to aim, it swings from the hand it hangs in to the one that aims it rather than
		# jumping there; it is all the way across before it can fire (AIM_READY).
		var swing := smoothstep(0.0, AIM_SWING, aim)
		if open <= 0.0 and swing < 1.0:
			var from: Transform3D = visual.get_grip(&"left").global_transform
			umbrella.global_transform = Transform3D(from.basis.orthonormalized().slerp(grip.global_basis.orthonormalized(), swing),
					from.origin.lerp(grip.global_position, swing))
	umbrella.set_state(open, Game.umbrella_radius(), maxf(droop, jet_kick * JET_KICK_DROOP))


## A blocked jet knocks the canopy aside for a moment, letting the rain in. `amount` 0..1 is the
## shove after Sturdy Frame (Game.jet_shove_mult).
func jet_shove(amount: float) -> void:
	jet_kick = maxf(jet_kick, clampf(amount, 0.0, 1.0))


# --- exposure -------------------------------------------------------------------------------

func _cast(from: Vector3, to: Vector3, mask: int) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.hit_back_faces = true
	q.hit_from_inside = true
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## While he leans in to open / close the umbrella, the upper-body samples lean forward with him
## (pivoting at the hips, as the pose modifier bends the spine).
func pose_sample(local: Vector3) -> Vector3:
	if not _dropped_umbrella and open > 0.0:
		if local.y > HIP_Y:
			local.x += (local.y - HIP_Y) * tan(Umbrella.open_lean(open))
		if local.y > NECK_Y:      # head ducks further at the neck
			local.x += (local.y - NECK_Y) * tan(Umbrella.open_duck(open))
	return local


## Fraction (weighted 0..1) of body samples that rain can reach.
## How much rain still gets past the umbrella while it is opening/closing: ~100% at the start of
## the animation, falling to 0% only once it is fully open (the canopy isn't taut until then).
func umbrella_leak() -> float:
	return pow(clampf(1.0 - open, 0.0, 1.0), 0.7)


func _rain_exposure() -> float:
	var up := -rain_dir() * 30.0
	var leak := umbrella_leak()
	var total := 0.0
	var hit := 0.0
	for s in SAMPLES:
		var p := sample_world(s[0])
		total += s[1]
		if _cast(p, p + up, COVER_MASK):
			continue                      # sheltered by an awning/balcony
		# Slanted rain reaching this sample fell through the sky upwind of it: none if that's a
		# sun break (e.g. stepping from the sun in under an awning with a tailwind).
		var x_sky := p.x + up.x / maxf(up.y, 0.01) * maxf(RAIN_SKY_Y - p.y, 0.0)
		if level.rain_intensity(x_sky) <= 0.0:
			continue
		if _cast(p, p + up, UMBRELLA_MASK):
			hit += s[1] * leak            # under the umbrella: only leaks while it moves
		else:
			hit += s[1]
	return hit / total


## Gutter streams: a heavy column of water at a fixed x, only the umbrella blocks it.
## How much of a gutter's falling column is landing on the canopy right now (0..1), found by
## casting straight down the stream — so the sound starts the instant water meets the umbrella.
func _stream_on_canopy() -> float:
	if open <= 0.0 or _dropped_umbrella:
		return 0.0
	var reach := umbrella.current_radius() + 0.15
	var cx := umbrella.canopy_center().x
	for g in level.gutters:
		if absf(cx - g) > reach:
			continue
		var hits := 0
		for dz in [-0.12, 0.0, 0.12]:
			var z: float = position.z + dz
			if _cast(Vector3(g, 2.9, z), Vector3(g, 0.6, z), UMBRELLA_MASK):
				hits += 1
		return hits / 3.0
	return 0.0


func _gutter_exposure() -> float:
	gutter_on_umbrella = _stream_on_canopy()
	for g in level.gutters:
		if absf(position.x - g) < 0.45:
			# The stream is a vertical column at x = g. Body points inside it get soaked unless
			# something (the umbrella) is directly above them in the column.
			var total := 0.0
			var hit := 0.0
			var blocked := 0.0
			for s in SAMPLES:
				var p := sample_world(s[0])
				if absf(p.x - g) > 0.22:
					continue
				total += s[1]
				var at := Vector3(g, p.y, p.z)
				if _cast(at, Vector3(g, 2.9, p.z), UMBRELLA_MASK):
					hit += s[1] * umbrella_leak()
					blocked += s[1]
				else:
					hit += s[1]
			return hit / total if total > 0.0 else 0.0
	return 0.0


## A train's sheet falls straight down off the train, or off the deck it is crossing: each body
## sample under it is soaked unless lot cover (an awning or slab) or the canopy is directly above it.
func _wash_exposure() -> float:
	if level.track == null:
		return 0.0
	var t: float = level.elapsed
	var total := 0.0
	var hit := 0.0
	for s in SAMPLES:
		var p := sample_world(s[0])
		total += s[1]
		if not level.wash_at(p.x, t):
			continue
		var top := Vector3(p.x, level.track.sheet_top(p.x) - 0.05, p.z)
		if _cast(p, top, COVER_MASK):
			continue
		hit += s[1] * (umbrella_leak() if _cast(p, top, UMBRELLA_MASK) else 1.0)
	return hit / total


## A helicopter's rotor wash drives the rain in under every kind of cover: each body sample inside
## it is soaked, by the wash's strength there, unless the open canopy is straight above it.
func _rotor_exposure() -> float:
	if level.helicopters == null:
		return 0.0
	var t: float = level.elapsed
	var total := 0.0
	var hit := 0.0
	for s in SAMPLES:
		var p := sample_world(s[0])
		total += s[1]
		var k: float = level.rotor_at(p.x, t)
		if k <= 0.0:
			continue
		hit += s[1] * k * (umbrella_leak() if _cast(p, Vector3(p.x, RAIN_SKY_Y, p.z), UMBRELLA_MASK) else 1.0)
	return hit / total


## The bots' read of the rotor wash: will it be on him anywhere he'll be over the next `horizon`
## seconds? Walks his own path forward in time against the same Level.rotor_at gameplay uses.
func _rotor_threat(horizon: float) -> bool:
	if level.helicopters == null:
		return false
	var t: float = level.elapsed
	var v := maxf(speed, Tun.f("walk_speed")) if state == State.WALK else 0.0
	var tau := 0.0
	while tau <= horizon:
		var x := position.x + v * tau
		for dx in [-0.35, 0.35]:
			if level.rotor_at(x + dx, t + tau) > 0.0:
				return true
		tau += 0.1
	return false


## Lot cover (an awning or slab) between this spot and the sheet: the wash can't land here.
func _under_lot_cover(x: float) -> bool:
	var p := Vector3(x, level.ground_y(x) + 1.7, position.z)
	return _cast(p, Vector3(x, level.track.sheet_top(x) - 0.05, position.z), COVER_MASK)


## The bots' read of the wash: will a sheet land, on bare pavement, somewhere he'll be over the next
## `horizon` seconds? Walks his own path forward in time against the same Level.wash_at gameplay uses.
func _wash_threat(horizon: float) -> bool:
	if level.track == null:
		return false
	var t: float = level.elapsed
	var v := maxf(speed, Tun.f("walk_speed")) if state == State.WALK else 0.0
	var tau := 0.0
	while tau <= horizon:
		var x := position.x + v * tau
		for dx in [-0.35, 0.35]:
			if level.wash_at(x + dx, t + tau) and not _under_lot_cover(x + dx):
				return true
		tau += 0.1
	return false


## Puddles splash underfoot but don't wet him: nobody can step round one, so it would be a cost
## the player can't avoid.
func _check_puddles() -> void:
	for p in level.puddles:
		var x0: float = p[0]
		if _prev_x < x0 and position.x >= x0:
			stats["puddles"] += 1
			puddle_stepped.emit(global_position + Vector3(0.2, 0, 0), run_amount > 0.45)


## The splash is over: `total` reached him in all.
func splash_done(total: float) -> void:
	if total > 0.0:
		stats["splashes"] += 1
		splashed.emit(total)


func _footsteps(delta: float) -> void:
	if speed < 0.1:
		return
	var stride := lerpf(0.75, 1.1, run_amount)
	_step_phase += speed * delta / stride
	if _step_phase >= 1.0:
		_step_phase -= 1.0
		footstep.emit(run_amount > 0.45)


# --- end states -----------------------------------------------------------------------------

func wettable() -> bool:
	return state == State.WALK or state == State.STOPPED


## A burst of wetness all at once: a car's splash, or a water jet that got through. If a jet soaks
## him within HIT_BLAME_S of it, the attempt fails with `cause` rather than "wet"; a splash takes
## the blame no more than the rain does.
func soak(amount: float, cause: StringName) -> void:
	if not wettable():
		return
	super.soak(amount, cause)
	if cause == &"splash":
		stats["wet_splash"] += amount
		return
	stats["wet_hit"] += amount
	_hit_cause = cause
	_hit_t = level.elapsed


## Ends the attempt for `cause` (see HUD.FAIL_TITLES): he gives up and trudges off as when soaked.
func fail(cause: StringName) -> void:
	if state == State.DEFEATED or state == State.ENTERING or state == State.DONE:
		return
	fail_cause = cause
	_defeat()


func _defeat() -> void:
	state = State.DEFEATED
	open = 0.0
	_give_up()
	defeated.emit()


func _begin_entering() -> void:
	state = State.ENTERING
	_end_t = 0.0
	arrived.emit()


const DOOR_IN_SPEED := 1.0         # m/s he walks in at
const DOOR_BRAKE := 4.0            # m/s2 he slows at on reaching the door
const DOOR_TURN := 3.0             # rad/s he can turn at a walk
const DOOR_GRIP := 4.0             # m/s2 sideways: at speed he can only turn as tightly as this allows
const DOOR_LOOK := 0.4             # m ahead he aims once at the doorway, keeping him centred in it
const DOORSTEP_Z := 0.7            # he waits here for the umbrella to finish closing
const INSIDE_Z := -1.2

## He rounds in through the door at `level.end_x`, steering back to it if he came in too fast to turn
## on the spot, and doesn't step under the porch until his umbrella is down.
func _process_entering(delta: float) -> void:
	_end_t += delta
	open = move_toward(open, 0.0, delta / maxf(Game.umbrella_open_time(), 0.05))
	_update_umbrella()
	var aim := Vector2(level.end_x, minf(0.0, position.z - DOOR_LOOK))
	var want := atan2(position.z - aim.y, aim.x - position.x)   # rotation.y: 0 along the street, PI/2 into the door
	var turn := minf(DOOR_TURN, DOOR_GRIP / maxf(speed, 0.01))
	rotation.y = move_toward(rotation.y, want, turn * delta)
	var target := DOOR_IN_SPEED * maxf(cos(want - rotation.y), 0.2)
	if open > 0.0:
		target = minf(target, sqrt(2.0 * DOOR_BRAKE * maxf(position.z - DOORSTEP_Z, 0.0)))
	speed = move_toward(speed, target, (DOOR_BRAKE if speed > target else 0.5 * DOOR_BRAKE) * delta)
	position.x += cos(rotation.y) * speed * delta
	position.z -= sin(rotation.y) * speed * delta
	position.y = level.ground_y(position.x)
	if position.z < INSIDE_Z:
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
	if level.rain_intensity(x) <= 0.0:
		return false
	var p := Vector3(x, level.ground_y(x) + height, position.z)
	return not _cast(p, p - rain_dir() * 30.0, COVER_MASK)


## Returns [umbrella, hurry, tilt, stop].
func _autopilot(delta: float) -> Array:
	var lead := maxf(speed, Tun.f("walk_speed")) * Game.umbrella_open_time() + 0.6
	var rd0 := rain_dir()
	var tl0 := clampf(-atan2(rd0.x, -rd0.y) / Tun.f("umbrella_max_tilt"), -1.0, 1.0)
	# Someone behind with water left, or a man in range ahead or behind: never stand resting in his
	# line of fire (deep under an arch a pursuer can't shoot). When a jet glints, open up and tilt toward it.
	var att: Node = level.get("attackers")
	var hm: Node = level.get("henchmen")
	var jet_in: bool = att != null and att.incoming() or hm != null and hm.incoming()
	var deep_in_arch: bool = level.track != null and level.track.arch_at(position.x) and level.track.arch_at(position.x + lead)
	var under_fire: bool = att != null and att.armed() and not deep_in_arch or hm != null and hm.armed()
	var next_glint: float = minf(att.next_glint_in() if att else INF, hm.next_glint_in() if hm else INF)
	# Stop is held, like a player keeping the button down until the bar is full. Deciding from the
	# live state instead let a flicker in the cover check release it mid-rest (worse with --human's
	# delayed replay). Rest through a light sprinkle at the cover's edge, but if a gust drives real
	# rain in, give up the rest and don't settle again until he has moved on a little.
	var car_coming: bool = level.car_threat(position.x)   # its splash takes a moment to land: no resting through it
	var db: DriveBy = level.drive_bys
	var drive_by: bool = db != null and db.coming()
	car_coming = car_coming or drive_by
	# A helicopter's wash coming his way: no resting or refilling until it has gone over.
	var rotor_near := _rotor_threat(Game.umbrella_open_time() + 3.0)
	var fill := _autopilot_refill(under_fire or car_coming or jet_in or rotor_near)
	if not fill.is_empty():
		return fill
	if _ap_resting:
		if stamina >= Tun.f("stamina_max") - 0.01 or exposure > 0.5 or under_fire or car_coming or rotor_near:
			_ap_resting = false
			_ap_no_rest_before = position.x + 1.5
		else:
			return [0.0, 0.0, tl0, true]
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
	var car_ahead := car_coming and not drive_by
	if car_coming:
		danger = true
	var wash := _wash_threat(Game.umbrella_open_time() + 0.5)
	if wash:
		danger = true
	var rotor := _rotor_threat(Game.umbrella_open_time() + 0.5)
	if rotor:
		danger = true
	if jet_in:
		danger = true
	# The canopy takes umbrella_open_time to open and a shot lands about a second after its glint:
	# have it up before his next one.
	if under_fire and next_glint < Game.umbrella_open_time() + 0.2:
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
	if wash or rotor:
		tl = 0.0
	var stop := false
	if stamina <= Tun.f("stop_threshold") * Tun.f("stamina_max") - 1.0 and sheltered and position.x >= _ap_no_rest_before and not under_fire and not car_coming and not rotor_near:
		stop = true
		for off in [-0.9, -0.45, 0.0, 0.45, 0.9]:
			if _exposed_at(position.x + off) or _exposed_at(position.x + off, 0.5):
				stop = false
		for g in level.gutters:
			if absf(g - position.x) < 1.2:
				stop = false
		for off in [-0.45, 0.45]:
			if level.track and level.track.on_track(position.x + off) and not _under_lot_cover(position.x + off):
				stop = false
	_ap_resting = stop
	# Swing the shaft onto a man only when a shot can go: tilted that far, the canopy lets the rain in.
	var shot_side := _ap_shot_side()
	if shot_side != 0.0:
		tl = (minf(tl, -0.85) if shot_side < 0.0 else maxf(tl, 0.85)) if open > 0.0 else shot_side
	# Put the canopy between him and the jet: well over toward it, not quite flat (that lets the rain in).
	var brace: float = hm.brace_side() if hm else 0.0
	if att != null and att.brace():
		brace = att.side()
	if brace < 0.0:
		tl = minf(tl, -0.85)
	elif brace > 0.0:
		tl = maxf(tl, 0.85)
	if drive_by and db.brace() != 0.0:
		tl = -0.7 if db.brace() < 0.0 else 0.85   # back toward the splash, then forward toward the shot
	return [u, h, tl, stop]


## Fires whenever a man in shot is in range on the side it aims and his canopy isn't in the way, but
## never while a jet is coming: the recoil would knock the canopy off it.
func _autopilot_fire(tl := 0.0) -> bool:
	if not gun.armed or gun.shots < 1.0:
		return false
	for shooter: Node in [level.get("attackers"), level.get("henchmen")]:
		if shooter and shooter.incoming():
			return false
	# Open, the canopy's tilt aims; furled, the side it is about to swing the shaft up to.
	var side := gun.aim_sign() if open > 0.0 or absf(tl) <= 0.3 else signf(tl)
	var m := _ap_mark(side)
	if m == null or open > 0.0 and not gun.on_line(m):
		return false   # furled, the shaft swings up onto him before it fires
	return not _cast(gun.muzzle(), m.global_position + Vector3(0.0, WaterGun.AIM_Y, 0.0), m.canopy_mask())


## The side (+1 ahead, -1 behind) of a man the bot could shoot right now: one in range and in shot,
## water in the barrel, no jet coming and his canopy not in the way. 0 if none.
func _ap_shot_side() -> float:
	if not gun.ready():
		return 0.0
	for shooter: Node in [level.get("attackers"), level.get("henchmen")]:
		if shooter and shooter.incoming():
			return 0.0
	var ahead := _ap_mark(1.0)
	var m := ahead if ahead else _ap_mark(-1.0)
	if m == null:
		return 0.0
	var side := 1.0 if ahead else -1.0
	var from := global_position + Vector3(side * 0.6, 1.5, 0.15)
	return 0.0 if _cast(from, m.global_position + Vector3(0.0, WaterGun.AIM_Y, 0.0), m.canopy_mask()) else side


## The man the shot would aim at on `side`, if the player could see him.
func _ap_mark(side: float) -> WetBody:
	var m := gun.mark(gun.muzzle(), side)
	return m if m and level.camera.is_position_in_frustum(m.global_position + Vector3(0.0, 1.2, 0.0)) else null


## Low on water and right under a stream with nothing coming: stop there, umbrella up and level,
## until the shot is full. Returns the controls, or [] to carry on.
func _autopilot_refill(threat: bool) -> Array:
	if not gun.armed or threat:
		_ap_filling = false
		return []
	# Stopped out from under the stream (a late stop overshoots it), it gives up rather than wait.
	_ap_fill_dry = _ap_fill_dry + get_physics_process_delta_time() if _ap_filling and state == State.STOPPED \
		and gun.refill_rate() < Tun.f("gun_refill_stream") else 0.0
	if _ap_filling and (gun.shots >= gun.capacity() or _ap_fill_dry > FILL_GIVE_UP_S):
		_ap_filling = false
		_ap_no_rest_before = position.x + 1.0
	if not _ap_filling and gun.shots <= gun.capacity() - 2 and position.x >= _ap_no_rest_before:
		# The human bot stops HUMAN_DELAY late: it asks that much sooner so it stops under the stream.
		var late := speed * HUMAN_DELAY if Game.debug_human else 0.0
		for g in level.gutters:
			if absf(g - position.x - late) < 0.15:
				_ap_filling = true
	return [1.0, 0.0, 0.0, true] if _ap_filling else []
