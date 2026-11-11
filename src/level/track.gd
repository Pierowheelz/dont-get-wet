class_name Track
extends RefCounted
## A level's elevated monorail (its `track` record) and the deck spans along it (`viaducts`).
## A train sets off from x1 every `period` s, offset by `phase` on the level clock, runs right to
## left to x0, and sheds a sheet of water for WASH_LEN behind its nose wherever it is. Under a deck
## the sheet falls from the deck's underside, elsewhere from the train's. Everything here is a pure
## function of the level clock, so gameplay, visuals, audio and the bots all read the same train.

const TRAIN_SPEED := 12.0
const WASH_LEN := 11.0          # the sheet trails the nose this far, so each point is wet ~0.9 s
const TRAIN_LEN := 30.0
const WARN_S := 2.0

# Cross-section (z toward the camera, y up). The beam runs in front of the walker's line (z 1.6),
# so it never shelters him, and low enough that the camera, looking up from 2.6 m, sees the train's
# underside. Lamp posts, balconies and arcades would stand in its way (see track-clearance).
const BEAM_Z0 := 2.5
const BEAM_Z1 := 3.2
const BEAM_Y := 3.65            # underside of the beam
const BEAM_TOP := 4.5
const TRAIN_Y := 3.85           # underside of the train's skirts: the sheet falls from here off a deck
const TRAIN_Z0 := 1.25
const TRAIN_Z1 := 4.45
# A deck hangs off the back of the beam, below the train, over the walker and above the awnings (3.05).
const DECK_Y := 3.35
const DECK_TOP := BEAM_Y
const DECK_Z0 := 0.6            # clear of the blade signs on the facades
const DECK_Z1 := BEAM_Z0

var x0: float
var x1: float
var style: String
var period: float
var phase: float
var decks: Array = []           # [x0, x1] of each deck span


static func parse(track: Dictionary, viaducts: Array) -> Track:
	var tr := Track.new()
	tr.x0 = float(track["x0"])
	tr.x1 = float(track["x1"])
	tr.style = String(track.get("style", "monorail"))
	tr.period = float(track["period"])
	tr.phase = float(track.get("phase", 0.0))
	assert(tr.period > WASH_LEN / TRAIN_SPEED, "track period shorter than one wash")
	for v in viaducts:
		tr.decks.append([float(v["x0"]), float(v["x1"])])
	return tr


func on_track(x: float) -> bool:
	return x >= x0 and x <= x1


func deck_at(x: float) -> bool:
	for d in decks:
		if x >= d[0] and x <= d[1]:
			return true
	return false


## Height the sheet falls from at x: a deck's underside, or the train's.
func sheet_top(x: float) -> float:
	return DECK_Y if deck_at(x) else TRAIN_Y


## Seconds since the front of the current cycle's sheet passed x (0..period).
func _since_front(x: float, t: float) -> float:
	return fposmod(t - phase - (x1 - x) / TRAIN_SPEED, period)


func wash_at(x: float, t: float) -> bool:
	return on_track(x) and _since_front(x, t) < WASH_LEN / TRAIN_SPEED


## Seconds until the sheet next falls at x: 0 while it is falling there, INF off the track.
func wash_eta(x: float, t: float) -> float:
	if not on_track(x):
		return INF
	var s := _since_front(x, t)
	return 0.0 if s < WASH_LEN / TRAIN_SPEED else period - s


## Departure number of the train that set off most recently; noses(t)[i] belongs to cycle(t) - i.
func cycle(t: float) -> int:
	return floori((t - phase) / period)


## World x of the nose of the train that set off most recently.
func nose(t: float) -> float:
	return x1 - TRAIN_SPEED * fposmod(t - phase, period)


## World x of every train nose on the track at time t, newest first.
func noses(t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var nx := nose(t)
	while nx + TRAIN_LEN >= x0:
		out.append(nx)
		nx -= TRAIN_SPEED * period
	return out


## The stretch [a, b] the sheet is falling on behind a nose at `nx`, or an empty array.
func wash_span(nx: float) -> Array:
	var a := maxf(nx, x0)
	var b := minf(nx + WASH_LEN, x1)
	return [a, b] if b > a else []
