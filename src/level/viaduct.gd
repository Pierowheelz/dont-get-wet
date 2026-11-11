class_name Viaduct
extends RefCounted
## One span from a level's `viaducts` list: an elevated deck over the walker's line from x0 to x1.
## A train crosses it right to left every `period` s, offset by `phase` on the level clock, and shakes
## a sheet of water off the deck for WASH_LEN behind its nose. Everything here is a pure function of
## the level clock, so gameplay, visuals, audio and the bots all read the same train.

const TRAIN_SPEED := 12.0
const WASH_LEN := 11.0          # the sheet trails the nose this far, so each point is wet ~0.9 s
const RUN_IN := 24.0            # the nose sets off this far right of x1: 2 s of warning before the span
const TRAIN_LEN := 30.0
const WARN_S := 2.0
const DECK_Y := 4.6             # underside of the deck
const DECK_TOP := 5.45
const DECK_Z0 := 0.25
const DECK_Z1 := 3.35

var x0: float
var x1: float
var style: String
var period: float
var phase: float


static func parse(d: Dictionary) -> Viaduct:
	var v := Viaduct.new()
	v.x0 = float(d["x0"])
	v.x1 = float(d["x1"])
	v.style = String(d.get("style", "monorail"))
	v.period = float(d["period"])
	v.phase = float(d.get("phase", 0.0))
	assert(v.period > WASH_LEN / TRAIN_SPEED, "viaduct period shorter than one wash")
	return v


func covers(x: float) -> bool:
	return x >= x0 and x <= x1


## Seconds since the front of the current cycle's sheet passed x (0..period).
func _since_front(x: float, t: float) -> float:
	return fposmod(t - phase - (x1 + RUN_IN - x) / TRAIN_SPEED, period)


func wash_at(x: float, t: float) -> bool:
	return covers(x) and _since_front(x, t) < WASH_LEN / TRAIN_SPEED


## Seconds until the sheet next falls at x: 0 while it is falling there, INF off the span.
func wash_eta(x: float, t: float) -> float:
	if not covers(x):
		return INF
	var s := _since_front(x, t)
	return 0.0 if s < WASH_LEN / TRAIN_SPEED else period - s


## World x of the nose of the train that set off this cycle.
func nose(t: float) -> float:
	return x1 + RUN_IN - TRAIN_SPEED * fposmod(t - phase, period)


## World x of every train nose within reach of the span at time t (usually one).
func noses(t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var nx := nose(t)
	while nx + TRAIN_LEN >= x0 - RUN_IN:
		out.append(nx)
		nx -= TRAIN_SPEED * period
	return out


## The stretch [a, b] of deck the sheet is falling from behind a nose at `nx`, or an empty array.
func wash_span(nx: float) -> Array:
	var a := maxf(nx, x0)
	var b := minf(nx + WASH_LEN, x1)
	return [a, b] if b > a else []
