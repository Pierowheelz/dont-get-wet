class_name WaterGun
extends Node
## The shot built into the walker's umbrella, on armed streets (Game.armed). Each shot is a short,
## wide, fast DropletBurst from the umbrella's tip along the street: forward, or behind once the
## open canopy is tilted back past BACK_TILT (with it furled, the last tilt input picks the side).
## It is aimed up or down at the chest of the nearest body it can reach on that side. Droplets are
## spent at Game.gun_range() (Long Barrel); a burst that soaks HIT_FULL of a body wets it gun_hit
## times Game.gun_pressure_mult() (Pressure), so two clean hits soak a man and Pressure tier 3 does it
## in one. It holds gun_shots and refills by itself at gun_refill_idle, or at gun_refill_stream while
## he stands stopped under a gutter stream with the umbrella open.

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
const STREAM_SHARE := 0.5      # how much of a stream the canopy must catch to refill from it
const RECOIL_S := 0.22
const FURLED_Y := 0.95         # furled, the shot leaves at least this high...
const FURLED_REACH := 0.25     # ...and this far out from his fist

var player: Player
var armed := false
var shots := 0.0               # fractional while refilling; a shot needs a whole one
var aim_back := false          # furled: the side the last tilt input picked
var recoil := 0.0              # 1 the moment it fires, back to 0 over RECOIL_S
var _cool := 0.0


func capacity() -> int:
	return int(Tun.f("gun_shots"))


## One physics step: aim, refill, and fire if asked and ready. `tl` is the tilt input (-1..1).
func step(delta: float, want_fire: bool, tl: float) -> void:
	if not armed:
		return
	recoil = move_toward(recoil, 0.0, delta / RECOIL_S)
	_cool -= delta
	if player.open <= 0.0:
		if tl < -BACK_TILT:
			aim_back = true
		elif tl > BACK_TILT:
			aim_back = false
	var rate := refill_rate()
	var before := floori(shots)
	shots = minf(shots + rate * delta, capacity())
	if floori(shots) > before and rate == Tun.f("gun_refill_stream"):
		_sound("puddle_splash", -6.0, 0.7 + 0.15 * floori(shots))
	if want_fire and _cool <= 0.0 and shots >= 1.0:
		fire()


## Shots per second it refills at right now.
func refill_rate() -> float:
	var under_stream := player.state == Player.State.STOPPED and player.open >= 0.95 \
		and player.gutter_on_umbrella >= STREAM_SHARE
	return Tun.f("gun_refill_stream") if under_stream else Tun.f("gun_refill_idle")


## +1 forward, -1 behind.
func aim_sign() -> float:
	if player.open > 0.0:
		return -1.0 if player.tilt < -BACK_TILT * Tun.f("umbrella_max_tilt") else 1.0
	return -1.0 if aim_back else 1.0


## The umbrella's tip while it is up; furled (hanging tip down from his fist), the shot leaves from
## the fist at hip height instead of the pavement.
func muzzle() -> Vector3:
	if player.open > 0.0:
		return player.umbrella.global_transform * Vector3(0.0, Umbrella.SHAFT_LEN + 0.09, 0.0)
	var fist := player.umbrella.global_position
	return Vector3(fist.x + aim_sign() * FURLED_REACH, maxf(fist.y, player.global_position.y + FURLED_Y), fist.z)


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
	recoil = 1.0
	var side := aim_sign()
	var from := muzzle()
	var reach := Game.gun_range()
	var at := Vector3(from.x + side * reach * 0.75, player.level.ground_y(from.x) + AIM_Y, from.z)
	var m := mark(from, side)
	if m:
		at = m.global_position + Vector3(0.0, AIM_Y, 0.0)
	var vels := pellets(launch(from, at, side))
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
