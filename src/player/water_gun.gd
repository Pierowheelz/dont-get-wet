class_name WaterGun
extends Node
## The shot built into the walker's umbrella, on armed streets (Game.armed). Each shot is a short,
## wide, fast DropletBurst out of the shaft's tip, along the shaft: the open canopy's tilt aims it, and
## furled, the aim input raises the shaft and points it (Player.aim). A body whose chest is within
## ASSIST of the shaft's line pulls the shot onto it. Droplets are
## spent at Game.gun_range() (Long Barrel); a burst that soaks HIT_FULL of a body wets it gun_hit
## times Game.gun_pressure_mult() (Pressure), so two clean hits soak a man and Pressure tier 3 does it
## in one. It holds gun_shots and refills at gun_refill_rain while the open canopy catches the rain, or
## at gun_refill_stream while he stands stopped under a gutter stream with the umbrella open.

signal fired(burst: DropletBurst)

const PELLETS := 40
const SPEED := 15.0
const SPREAD_UP := 0.08        # rad, up and down
const SPREAD_ACROSS := 0.035   # rad across the street
const SPEED_JITTER := 0.08
const REACH_JITTER := 0.1      # droplets are spent up to this share short of the full range
const HIT_FULL := 0.45         # share of a body (DropletBurst.exposure) a shot must soak to wet it gun_hit
const HIT_PER_POINT := 2.0
const AIM_Y := 1.25            # aimed at the chest
const BACK_TILT := 0.3         # share of the full tilt back past which it fires behind
const ASSIST := 0.7            # rad either side of the shaft's line within which a body pulls the shot onto its chest
const TIP := 0.09              # m past the end of the shaft the water leaves
const HOLD_S := 0.6            # s the furled shaft stays up after a shot
const STREAM_SHARE := 0.5      # how much of a stream the canopy must catch to refill from it
const RECOIL_S := 0.22

var player: Player
var armed := false
var shots := 0.0               # fractional while refilling; a shot needs a whole one
var last_side := 1.0          # the side it last fired: a shot from rest swings the furled shaft up that way
var recoil := 0.0              # 1 the moment it fires, back to 0 over RECOIL_S
var _cool := 0.0
var _hold := 0.0


func capacity() -> int:
	return int(Tun.f("gun_shots"))


## One physics step: refill, and fire if asked and the shaft is up.
func step(delta: float, want_fire: bool) -> void:
	if not armed:
		return
	recoil = move_toward(recoil, 0.0, delta / RECOIL_S)
	_cool -= delta
	_hold -= delta
	var rate := refill_rate()
	var before := floori(shots)
	shots = minf(shots + rate * delta, capacity())
	if floori(shots) > before and rate == Tun.f("gun_refill_stream"):
		_sound("puddle_splash", -6.0, 0.7 + 0.15 * floori(shots))
	if want_fire and _cool <= 0.0 and shots >= 1.0:
		fire()


## Shots per second it refills at right now: fast stopped under a gutter stream with the umbrella
## open, slowly while the open canopy is out in the rain, and not at all furled or under cover.
func refill_rate() -> float:
	if player.open < 0.95:
		return 0.0
	if player.state == Player.State.STOPPED and player.gutter_on_umbrella >= STREAM_SHARE:
		return Tun.f("gun_refill_stream")
	var x := player.position.x
	if player.level.rain_intensity(x) <= 0.0:
		return 0.0
	var top := player.umbrella.canopy_center()
	return 0.0 if player._cast(top, top - player.rain_dir() * 30.0, Player.COVER_MASK) else Tun.f("gun_refill_rain")


## True when a shot can go now: water in it and the last one cleared.
func ready() -> bool:
	return armed and shots >= 1.0 and _cool <= 0.0


## True for a moment after a shot: the furled shaft stays up between quick shots.
func holding() -> bool:
	return _hold > 0.0


## +1 forward, -1 behind: the way the shaft leans.
func aim_sign() -> float:
	return -1.0 if player.tilt < -BACK_TILT * Tun.f("umbrella_max_tilt") else 1.0


## The end of the shaft, where the water leaves.
func muzzle() -> Vector3:
	return player.umbrella.global_transform * Vector3(0.0, Umbrella.SHAFT_LEN + TIP, 0.0)


## The shaft's direction in the street's plane, toward the tip.
func barrel() -> Vector3:
	var d := player.umbrella.global_basis.y
	d.z = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3(aim_sign(), 0.0, 0.0)


## True if `body`'s chest is within ASSIST of the shaft's line, so a shot would land on it.
func on_line(body: WetBody) -> bool:
	var to := body.global_position + Vector3(0.0, AIM_Y, 0.0) - muzzle()
	to.z = 0.0
	return to.length() > 0.01 and barrel().angle_to(to.normalized()) <= ASSIST


## The nearest body it can wet on the side it aims, within range of `from` (null if none).
func mark(from: Vector3, side: float) -> WetBody:
	var best: WetBody = null
	var best_d := Game.gun_range() + 0.3
	for body: WetBody in WetBody.of_level(player.level):
		if body == player or not body.wettable():
			continue
		var d := (body.global_position.x - from.x) * side
		if d > 0.3 and d < best_d:
			best = body
			best_d = d
	return best


func fire() -> DropletBurst:
	shots -= 1.0
	_cool = Tun.f("gun_cadence")
	_hold = HOLD_S
	recoil = 1.0
	var side := aim_sign()
	last_side = side
	var from := muzzle()
	var reach := Game.gun_range()
	var v0 := barrel() * SPEED
	var m := mark(from, side)
	if m and on_line(m):
		v0 = launch(from, m.global_position + Vector3(0.0, AIM_Y, 0.0), side)
	var vels := pellets(v0)
	var starts := PackedVector3Array()
	starts.resize(vels.size())
	starts.fill(from)
	var burst := DropletBurst.spawn(player.level, starts, vels, Tun.f("gun_hit") * Game.gun_pressure_mult(),
		{"full": HIT_FULL, "per_point": HIT_PER_POINT, "cause": &"shot", "shooter": player, "reach": reach,
		"reach_jitter": REACH_JITTER, "size": 0.06, "trail": 4, "color": Color(0.75, 0.86, 1.0, 0.6)})
	_sound("car_splash", -6.0, 2.6)
	_sound("puddle_splash", -2.0, 1.9)
	fired.emit(burst)
	return burst


## Launch velocity of the centre droplet: SPEED along the street toward `side`, on the low arc that
## meets `at` (aimed straight at it if it is out of reach), drifting across to its lane.
static func launch(from: Vector3, at: Vector3, side: float) -> Vector3:
	var g := DropletBurst.GRAVITY
	var dx := maxf(absf(at.x - from.x), 0.5)
	var dy := at.y - from.y
	var v2 := SPEED * SPEED
	var disc := v2 * v2 - g * (g * dx * dx + 2.0 * dy * v2)
	var elev := atan((v2 - sqrt(disc)) / (g * dx)) if disc >= 0.0 else atan2(dy, dx)
	var flight := dx / (SPEED * cos(elev))
	return Vector3(side * cos(elev) * SPEED, sin(elev) * SPEED, (at.z - from.z) / flight)


## The burst round `v0`: fanned up and down in the street's plane, a little across it, strung out in speed.
static func pellets(v0: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var speed := v0.length()
	var d := v0 / speed
	var up := Vector3(-d.y, d.x, 0.0).normalized() * signf(d.x)
	var across := Vector3(0.0, 0.0, 1.0)
	for i in PELLETS:
		var dir := (d + up * randf_range(-SPREAD_UP, SPREAD_UP) + across * randf_range(-SPREAD_ACROSS, SPREAD_ACROSS)).normalized()
		out.append(dir * speed * (1.0 + randf_range(-SPEED_JITTER, SPEED_JITTER)))
	return out


func _sound(name: String, db: float, pitch: float) -> void:
	var au: Node = player.level.get("audio")
	if au and au.has_method("play"):
		au.play(name, db, pitch)
