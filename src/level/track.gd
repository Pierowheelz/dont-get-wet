class_name Track
extends RefCounted
## A level's elevated railway (its `track` record) and the covered spans along it (`viaducts`).
## `style` "monorail" is a beam in front of the walker with glass decks hung off it; "railway" is a
## brick viaduct over the pavement whose arches (the `viaducts` spans) are cover from the rain and
## the wash alike, joined by open iron girder spans.
## Trains set off from x1 at `departures` on the level clock, each a random `gap` after the last,
## run right to left to x0, and shed a sheet of water for WASH_LEN behind the nose wherever they are.
## Under a deck the sheet falls from the deck's underside, elsewhere from the train's. Everything
## here is a pure function of the level clock and the departures rolled for this attempt, so
## gameplay, visuals, audio and the bots all read the same train.

const TRAIN_SPEED := 12.0
const WASH_LEN := 11.0          # the sheet trails the nose this far, so each point is wet ~0.9 s
const WASH_S := WASH_LEN / TRAIN_SPEED   # how long the sheet falls on any one spot
const TRAIN_LEN := 30.0
const WARN_S := 2.0

# Cross-section (z toward the camera, y up). The beam runs in front of the walker's line (z 1.6),
# so it never shelters him, and low enough that the camera, looking up from 2.6 m, sees the train's
# underside. Lamp posts, balconies and arcades would stand in its way (see track-clearance).
const BEAM_Z0 := 2.5
const BEAM_Z1 := 3.2
const BEAM_Y := 3.65            # underside of the beam
const BEAM_TOP := 4.1
const RAIL_Y := BEAM_TOP - 0.05   # the guide rails cap the beam's sides
const TRAIN_Y := 3.85           # underside of the train's skirts: the sheet falls from here off a deck
const TRAIN_Z0 := 1.25
const TRAIN_Z1 := 4.45
# A deck hangs off the back of the beam, below the train, over the walker and above the awnings (3.05).
const DECK_Y := 3.35
const DECK_TOP := BEAM_Y
const DECK_Z0 := 0.6            # clear of the blade signs on the facades
const DECK_Z1 := BEAM_Z0

# Railway cross-section: the viaduct stands over the pavement, from the shopfronts to the kerb, low
# enough that the camera sees the carriages over the parapet. Its arches are solid cover above every
# awning; the girder spans between them have an open floor, so rain and the sheet fall through.
const RAIL_Z0 := 0.15           # back face, against the shopfronts
const RAIL_Z1 := 3.45           # front face, over the kerb
const RAIL_SOFFIT := 3.1        # underside of an arch's vault: clear of the awnings (3.05 at the wall)
const RAIL_BED := 3.5           # top of the deck, where the sleepers lie
const RAIL_PARAPET := 3.85
const RAIL_TRAIN_Y := 3.95      # underside of the carriages: the sheet falls from here
const RAIL_TRAIN_Z0 := 0.35
const RAIL_TRAIN_Z1 := 3.25
const RAIL_TRAIN_LEN := 25.0    # two carriages

var x0: float
var x1: float
var style: String
var gap_min: float
var gap_max: float
var decks: Array = []           # [x0, x1] of each deck span (railway: each run of arches)
var train_len := TRAIN_LEN
var departures := PackedFloat64Array()   # ascending level-clock times a train sets off from x1
var _rng := RandomNumberGenerator.new()


## `seed` rolls this attempt's departures; the same seed always gives the same trains.
static func parse(track: Dictionary, viaducts: Array, seed: int) -> Track:
	var tr := Track.new()
	tr.x0 = float(track["x0"])
	tr.x1 = float(track["x1"])
	tr.style = String(track.get("style", "monorail"))
	if tr.railway():
		tr.train_len = RAIL_TRAIN_LEN
	tr.gap_min = float(track["gap"][0])
	tr.gap_max = float(track["gap"][1])
	assert(tr.gap_min > WASH_S and tr.gap_max >= tr.gap_min, "train gap shorter than one wash")
	for v in viaducts:
		tr.decks.append([float(v["x0"]), float(v["x1"])])
	tr._rng.seed = seed
	# The first train set off a whole crossing before the clock starts, so the track is busy at t = 0.
	tr.departures.append(-(tr.x1 - tr.x0 + tr.train_len) / TRAIN_SPEED - tr._rng.randf_range(0.0, tr.gap_max))
	return tr


func railway() -> bool:
	return style == "railway"


## Under a railway arch: dry, the sheet can't reach him, and nobody behind him has a clear shot.
func arch_at(x: float) -> bool:
	return railway() and deck_at(x)


func on_track(x: float) -> bool:
	return x >= x0 and x <= x1


func deck_at(x: float) -> bool:
	for d in decks:
		if x >= d[0] and x <= d[1]:
			return true
	return false


## Height the sheet falls from at x: a deck's underside, or the train's. A railway's sheet always
## falls from the carriages, onto an arch's deck or through a girder span's open floor.
func sheet_top(x: float) -> float:
	if railway():
		return RAIL_TRAIN_Y
	return DECK_Y if deck_at(x) else TRAIN_Y


## Index in `departures` of the train that set off most recently by t (-1 before the first);
## noses(t)[i] belongs to departure(t) - i. Rolls further departures as the clock nears the last one,
## so there is always a next train.
func departure(t: float) -> int:
	while departures[-1] <= t:
		departures.append(departures[-1] + _rng.randf_range(gap_min, gap_max))
	return departures.bsearch(t, false) - 1


func wash_at(x: float, t: float) -> bool:
	return wash_eta(x, t) == 0.0


## Seconds until the sheet next falls at x: 0 while it is falling there, INF off the track.
func wash_eta(x: float, t: float) -> float:
	if not on_track(x):
		return INF
	var u := t - (x1 - x) / TRAIN_SPEED   # when a train passing x now would have set off
	var k := departure(u)
	if k >= 0 and u - departures[k] < WASH_S:
		return 0.0
	return departures[k + 1] - u


## World x of every train nose on the track at time t, newest first.
func noses(t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var k := departure(t)
	while k >= 0:
		var nx := x1 - TRAIN_SPEED * (t - departures[k])
		if nx + train_len < x0:
			break
		out.append(nx)
		k -= 1
	return out


## The stretch [a, b] the sheet is falling on behind a nose at `nx`, or an empty array.
func wash_span(nx: float) -> Array:
	var a := maxf(nx, x0)
	var b := minf(nx + WASH_LEN, x1)
	return [a, b] if b > a else []
