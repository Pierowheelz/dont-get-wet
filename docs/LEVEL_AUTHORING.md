# Authoring a street

How to turn a `tools/level_gen.py` draft in `levels/*.json` into a hand-authored street. Main Street
(`levels/main_street.json`) is the worked example. Numbers come from `data/tunables.json` at the time
of writing. Check them there if a result looks off.

## Workflow

1. Write the street down as a list of set pieces before touching the JSON. For each one, note its
   name, its x range, and the one thing it asks of the player.
2. Write or edit the plan script and run it: `python3 tools/streets/LEVEL.py`. The JSON it writes
   carries `"authored": true`, so `level_gen.py` skips the file.
3. Run the fast static check after every edit. It needs no Godot run.
   `python3 tools/level_preview.py LEVEL --report -o /tmp/LEVEL.png`
4. Run both bots and render the strip. Open the PNG and read it, every time.
   `tools/preview.sh LEVEL OUT_DIR` (exits 1 if a design rule fails)
5. Screenshot each set piece and look at it. Start each shot under cover, because a shot that starts
   in open sky begins with the umbrella closed and the walker gets soaked.
   `tools/shots.sh OUT "2,6,10" res://src/level/level.tscn --autopilot --level=LEVEL --start-x=M`
   `python3 tools/grid.py sheet.png OUT/shot_*.png`
6. Before committing, run `tools/test.sh` and
   `tools/playtest.sh LEVEL`. The playtest must report 0 errors.

Lots sit end to end, so every later `x` shifts when you change one width. Write the street as a plan
script, `tools/streets/LEVEL.py` (copy `tools/streets/main_street.py`): lots and crossings in walking
order, with features, props and set pieces placed relative to tagged lots (`s.mid("pipe")`). Run it to
rewrite `levels/LEVEL.json`; the plan is the source, so never hand-edit the JSON afterwards.
`awning_style=` on a lot picks one of the styles in docs/CONTRACTS.md; leave it out to get the
automatic mix.

## What each element does in play

Speeds: walk 1.3 m/s, 1.2 m/s with the umbrella open, hurry 2.0, run 3.2. The umbrella takes 1.3 s to
open or close, so a player has to start opening about 1.7 m before a gap.

Stamina is 100. The open umbrella drains 3/s, which is about 33 m of open sky on a full bar.
Hurrying drains 9/s and running drains 18/s. Stamina regenerates at 12/s only while the umbrella is
fully closed, and at 20/s while stopped with it closed. Stop is a hold control that works at any
stamina; the bots stop under cover once stamina falls to 24.

Wetness runs from 0 to 50 (the HUD shows a percentage). Open sky adds 9/s x rain intensity x the
exposed fraction of the body, so one bare second in the rain costs about 9 (18%). Only sun breaks,
vents and fire barrels dry the walker, at their full rate only above 90% wet. Below that the rate
halves for every 7 points drier (`dry_falloff` 10), so at 60% it is about 5% of full, but never
slower than 1% every 5 s (`dry_min_rate` 0.1/s). Drying
rescues a near-soaked run; it never pays back the time spent standing in it. On the early streets
every sun break, vent and fire barrel ends before two thirds of `end_x`, so drying can save a bad
start but never the finish.

Score is `250 x (1 - wet/50) + 750 x min(1, par/time)`, with par = `end_x / 1.3` (`Street(..., par_speed=)` overrides it for one street; Arcade Lane uses 1.4 because the bots take no rain there and read its cars perfectly). Time dominates:
S needs 950, which a run at par reaches with up to 20% wet.

**Lots** (`x`, `w`, `style`, `cover`, `floors`, optional `sign`, `awning_color`, `awning_style`, `tears`,
`neon`):

| `cover` | Shelter | Notes |
|---|---|---|
| `awning` | canvas, tin or chrome, 2.35 m deep; nine `awning_style`s (docs/CONTRACTS.md) that all shelter the same | The walker (z 1.6) is fully under it. `awning_color`: red, green, blue, brown, orange, teal. |
| `awning` + `tears` | holes at local `[x0, x1]` | Each tear is real open sky with a hanging flap. 1 to 1.4 m tears read well. |
| `balcony` | flat slab at 4.12 m, 2.4 m deep | Pale concrete with a rail, lit underneath. |
| `arcade` | flat slab at 4.15 m, 2.9 m deep, columns every 3.5 m | Reads as a colonnade. Columns can hide part of a sign. |
| `canopy` | gas-station roof | Only with `style: "gas_station"`, which draws it. |
| `walkway` | flat slab at 3.0 m, 2.4 m deep, steel posts at its front edge | A motel's upper walkway roofing the lower one; use with `style: "motel"`. |
| `none` | open sky | |

`style` picks the ground-floor kit module: `shop_lit` (lit window, warm sign), `shop_dark`,
`shuttered`, `boarded`, `wall`, `doorway`, `inn`, `vacant` (chain-link fence, no building), plus
`gas_station`, `warehouse` and `loading_dock`, and two drawn in code (`src/level/roadside_builder.gd`):
`motel` (a row of numbered rooms, doors and curtained windows, one storey per floor; give it
`cover: "walkway"`) and `forecourt` (an open concrete apron with painted bays and a floodlight, its
building 10 m back from the street: `sign` goes on that building, unlit unless `"lit": true`, and
`"note"` puts a small card in its window, such as "CLOSED"). Plan scripts pass these as keywords:
`s.lot("dlot", 12, "forecourt", "none", sign="DINER", note="CLOSED")`. Kit widths are 3, 4, 5, 6 and 8 m. Other widths get
padded with filler strips, so a 1 to 1.5 m `wall` lot makes a narrow seam between buildings.
Building height is 4 m + 3.2 m per floor. Signs are lit only on `shop_lit` and `inn`. The font
shrinks to fit the lot width. `neon=True` gives a signed lot tube lettering on either kit era. On a
street with `neon` above 0 the builder swaps some lots to the retro kit, and a signless retro lot gets
a random filler name; pass `sign=" "` on narrow seams to keep it blank.

**The glass city** (`aesthetic: "modern"`, `src/level/modern_builder.gd`) draws three more styles in
code, all without cover, and a skyline of skyscrapers (offices lit, red beacons on the tall ones)
behind the street instead of the usual dark silhouette. Its kit lots (`shop_lit`, `inn`, ...) all use
the retro kit, and only the lots its `neon` roll picks get tube lettering or a filler name.

- `glass_tower`: a curtain-wall tower, 4 m + 3.2 m per `floors` (8 to 20 or more): travertine pilotis at
  the lot line in front of a lobby 1.8 m back on a terrazzo floor, `sign` in stainless capitals on the
  fascia over it (3.3 to 4 m).
- `lobby`: a double-height glass lobby (7.2 m) with a mezzanine and globe lamps, the tower above it;
  the same sign band. Pair it with a `revolving_door` for a terminal or hotel entrance.
- `plaza`: an open travertine plaza (open sky) with planters, flagpoles and globe lamps, its tower
  16 m back. Keep its `floors` low (3 to 6) so the skyline shows above it.

The towers' lobbies are lit unless the lot sets `"lit": false`; `"palette": 0-3` picks the glass
(blue-green, bronze, white spandrels, black) instead of the automatic one. A side street beside a modern
lot is lined with glass, and towers close its far end.

**`camera`** (`{"distance", "height", "fov", "pitch", "lead"}`, any of them;
`Street(..., camera={...})`) replaces the camera tunables (`camera_distance`, `camera_height`,
`camera_fov`, `camera_pitch_deg`, `camera_lead`) for one street. Pitch is in degrees, positive looks
up. The frame checks (`Level.in_frame`, the courier's frame edge, the henchmen's) follow the real
camera, the drive-by pull eases out from it, and the rain box grows to fill the wider view with up to
1.8 times the drops. A wider view makes the walker smaller: at distance 10.5, fov 52 he is about a
sixth of the screen's height (a quarter by default). Keep his feet well above the bottom edge.

The level ends at the inn door. The builder sets `end_x` from the kit door: an 8 m `inn` lot puts the
door at `x + 4`. Keep the JSON `end_x` in step with it, because the preview uses the JSON value.

**Crossings** (`x`, `w`, optional `car`; `s.xing(tag, w, car=True)`) are open road. The ground drops 0.16 m, props inside are
skipped, and `"car": true` adds a car whose splash costs up to 25 (`wet_car_splash`). The splash is a burst of
600 real droplets (`DropletBurst`) thrown off the puddle at about 45 degrees, fanned along the street: only
those that come down on the walker from the knees up wet him. Each wets the body point nearest it (the
weighted points rain is measured on, `WetBody.SAMPLES`); 25 droplets soak a point, and the splash costs the full
25 once half his weighted body is soaked (`CarHazard.SPLASH_FULL`). Unblocked it costs the full 25 up to about
4 m short of the crossing, about 16 at 5 m, 11 at 6 m and almost nothing past 8 m. A forward-tilted open umbrella
stops the droplets it meets: about 3 get through at 3 m, about 2 from 4 m out (closer in the wave is still
rising and more gets under it: about 7 at 2 m). From the moment the car sets off until its body has
passed his line, the walker can't step off the kerb: he is held 0.6 m short of the crossing
(`CarHazard.KERB_GAP`, where the wave still reaches all of him), standing as if stopped, and walks on
once it has gone. Running at the crossing doesn't beat the splash. A walker already past that point
when it sets off isn't held.

**Features:**

| `type` | Effect |
|---|---|
| `gutter` (`x`, optional `kind`, `side`) | A falling column on the walker's line. Inside 0.45 m of it the rate is 26/s unless the umbrella is directly above. The bot opens for it even under cover. Put it in a `wall` seam or inside a tear of 1 m or more; the build warns if it lands on intact canvas. The builder draws what it pours from: `snapped` (a gooseneck downpipe broken off over the walkway, the piece on the pavement), `crack` (the same pipe split open) or `collapse` (the nearest canvas within 1 m has slumped off its frame and spills from its corner, which hangs 0.3 m past the canvas edge; the stream moves there from `x`; canvas awnings only, otherwise it falls back to `snapped` at `x`). Without `kind` a street cycles through the three. `side` is 1 when the source reaches the stream from lower x, -1 from higher x. The gutter brings its own downpipe, so don't add a `downpipe` prop at the same x. |
| `puddle` (`x`, `w`, `deep`) | Splashes underfoot (louder running) but costs no wetness: nobody can step around one, so it would be a cost the player can't avoid. Set dressing only; the design checks ignore it. |
| `sun` (`x`, `w`) | No rain, and 3/s drying (before the wetness falloff) scaled by how closed the umbrella is (open shades him, no drying). The rain-free span stretches to meet cover within 2 m. Both bots close the umbrella in it. |
| `vent` (`x`, `w` = 1.6) | 4.5/s drying. |
| `fire_barrel` (`x`, `w` = 1.8) | 5.4/s drying. It sits against the wall and looks right under a balcony. |

**Props** are dressing only: `lamp_post`, `hydrant`, `trash_can`, `newspaper_box(_b)`, `bench`,
`mailbox`, `parking_meter`, `street_sign`, `downpipe`, `trash_bags`, `crates`, `cardboard_boxes`,
`bollard`, `phone_booth`, `sandwich_board`, `chainlink_fence_4`, and more in
`assets/props/props.json`. A `phone_booth` with `"ring": true` (`s.prop("phone_booth", x, ring=True)`)
rings as the walker approaches, with a lamp in the booth flashing on each ring, and goes quiet once he
passes it. Two optional fields change that:

- `"keep": true` keeps it ringing after he passes, until it is answered.
- `"line": "..."` is shown as a hint when he holds stop within 1.5 m of the booth for 0.6 s while it
  rings, once per attempt. That answers it and the ringing stops.

`revolving_door` (`s.prop("revolving_door", x)`) is a hotel's glass drum set into the facade at `x`
(radius 0.95 m, standing 1.2 m out onto the pavement), its four leaves turning slowly, with a brass top
and warm light inside. Dressing only; keep figures and henchmen 1.3 m clear of it.

`billboard` (`s.prop("billboard", x, text="LINE ONE\nLINE TWO")`) is a lit 10 m hoarding on two
posts 3 m behind the lot line, from 2.5 m to 5.7 m up; put it behind a `vacant` or `forecourt` lot.
`pylon_sign` (`s.prop("pylon_sign", x, text="...")`) is a lit box sign topping a 6 m pole 1.2 m behind
the lot line. Both are dressing only; `\n` breaks the lines.

`station_stairs` (`s.prop("station_stairs", x)`) is a stair flight against the shopfronts from the
pavement at `x + 6` up to a deck span at `x`. It is dressing only and only makes sense under a deck;
the space under its high end (`x` to about `x + 2`) fits a phone booth.

**`figures`** (`x`, optional `facing`; `s.figure(x)`) are people built from the walker's own model,
standing still in a doorway with the umbrella furled. Scenery only: put them under cover, away from
features. `facing` is `"street"` (the default: he faces up the street, the way the walker goes) or
`"away"` (`s.figure(x, facing="away")`: he faces the building, back to the camera).

**`hints`** (`x`, `text`, `dur`; `s.hint(x, text, dur=4.0)`) are HUD lines shown once per attempt as
the walker passes `x`, for `dur` seconds. The text takes the same `{stop}`, `{hurry}`, `{tilt}`,
`{tilt_forward}` and `{umbrella}` tokens as the built-in hints. A checkpoint resume skips every hint
at or before the checkpoint. A first-encounter hint (gutter, sun, wind, stop) that fires in the
same moment replaces it, so keep `x` clear of the first gutter and sun break.

**`follower`** (`{"appear": [{"x", "hold"}]}`; `s.follower(x, hold)` once per appearance) is
a scripted NPC in a long raincoat and fedora, on the walker's own model and gait. When the walker passes an `appear` x, he walks in from the left edge of the frame on
the back lane, holds 0.55 m inside it for `hold` seconds (the same on 16:9 and 21:9), then slows and
drops back out of frame. He opens a starter-size umbrella (never the walker's upgrades) in his left
hand when the rain reaches him, and furls it after 2 s under cover. He copies the walker 0.6 s late: he stops when the walker stops (or
stands, defeated or at the door) and matches his walking or hurrying speed. He never comes within
3 m. Within 6 m of the walker his footsteps play quietly, panned with his position. Scenery only:
the bots and the rain model ignore him, and a checkpoint resume skips appearances behind it. Put
each `x` where the walker is under cover, so a player who stops to listen stays dry.

**`courier`** (`{"appear_x", "door_x", "stops": [{"x", "dur"}], "look"?}`; `s.courier(appear_x, door_x,
stops=[(x, dur), ...], look=None)`) is a scripted pedestrian the walker must keep in frame, under the only
yellow umbrella on the street. He stands in a doorway at `appear_x` and steps out onto a lane just
behind the walker's once the walker is 8 m from it, opening the umbrella as he goes; he never furls it,
so he needs no cover. He walks at 1.15 m/s to `door_x` (the inn door) and goes in ahead of the walker.
At each stop `x` he faces the shop window for `dur` seconds. The rules, all in `src/level/courier.gd`:

- **Glance.** When the walker is within 5 m behind him he slows for 0.4 s, then turns his head and
  shoulders back over 1.6 s (2 s in all, time to react), holds, and turns forward again; at most one glance every 5 s. As the turn
  completes, if the walker's umbrella is not open and tilted fully forward (90% of the maximum
  tilt, the tilt that blocks a car's splash), his suspicion goes up by one.
- **Suspicion shows only in what he does.** Each gain: he holds the look 0.6 s longer and a low sting
  plays (`glance_sting`). At 1 he glances from 6 m, and at every window stop he checks the reflection
  (a glance while facing the glass). At 2 he walks at 1.25 m/s and window stops are 40% shorter. At 3
  his free hand goes inside his coat on every glance. The 4th gain: he turns to face the walker, aims the
  umbrella and fires twice (`WaterJet`, 0.6 s glint, then 0.25 s for the second barrel). Each shot
  carries a car's splash (`wet_car_splash`) in pellets the canopy can't stop; 0.5 s after the second
  lands, the attempt fails as `shot`.
- **Fails.** `made` when the walker comes within 1.2 m of him or passes him; `lost` when he has been
  off the right edge of the frame (taken as at least 16:9) for 2 s. Neither applies in the last 6 m
  before his door.
- **Hints** are event-driven, once per attempt: when he steps out, at his first glance, and the first
  time the walker is within 5 m of him at a window stop.
- **The bots** hold stop to stay his glance distance + 1.2 m back where the frame allows (keeping
  2.5 m of frame ahead of him), hurry if he is about to leave the frame, never wait under a gutter, and open the umbrella tilted fully forward while he glances. The human bot reacts late as
  usual. `level_preview.py` ignores him (`tools/preview.sh` is the judge); the street's `par_speed`
  has to allow for his pace and stops (Atomic Avenue uses 1.25).
- **Checkpoints.** A resume (or `--start-x`) past his doorway puts him 6.5 m ahead and already walking,
  with the stops behind spent and his suspicion as it was at the checkpoint.
- **`look`** (optional): leave it out for the brown suit, fedora and yellow umbrella (Atomic Avenue).
  `"slicker"` makes him Fairweather, the man in the yellow slicker: dressed as `slickers` are
  (`RaincoatFigure.dress`, hood up), the rain never wets him, and he never opens his umbrella. It
  hangs furled like a cane from his camera-side right fist as he walks, stops and glances, and his
  left hand is the one that goes inside his coat. On the 4th gain he turns to the walker, shoulders
  the furled umbrella in his left hand (the walker model's `set_aim`) and fires both barrels from its
  tip. The step-out hint names him. Every rule above is unchanged.
- **Testing flags:** `--courier-suspicion=N` starts him at suspicion N, `--courier-pace=M` makes him
  walk at M m/s (to test `lost`), `--courier-gap=M` changes the 6.5 m resume gap,
  `--courier-aim=S` has him fire at S s on the level clock (to see the shot), and `--courier-close`
  frames him with a close camera (screenshots).

Put stops in front of lit windows, and give the walker somewhere to wait about 5 m short of each.

**Street text in `levels/index.json`.** Besides `blurb` and `outro` (a string, or an array of lines
shown one under another), a node can carry `load` (one
line under the street name on the loading card) and `fail` (an array of fail-screen lines that
replaces the generic pool for that street). `fail` can instead be a dictionary keyed by fail cause
(`wet`, `shot`, `lost`, `made`; titles in `HUD.FAIL_TITLES`), each an array of lines. A cause with no
lines shows only its title; `wet` falls back to the generic pool. Code ends an attempt with a cause
through `Player.fail(cause)`, or `Player.soak(amount, cause)` for a burst of wetness that is blamed
if it soaks him within 1.5 s.

**`track`** (`x0`, `x1`, `style`, `gap`; `s.track(gap=(10, 25))`) is an elevated monorail beam along the
street, just in front of the walker's line. `s.track()` runs it from 40 m before the street to 40 m past
its end, so neither end shows; pass `x0=`/`x1=` to shorten it, and keep the ends off screen, because a
train appears at `x1` and vanishes past `x0`. Trains set off from `x1` a random `gap` apart, uniform
between its two values in seconds and rolled afresh on every attempt (a checkpoint resume rolls again),
and run right to left at 12 m/s. Trains are already on the track when the clock starts. Wherever it is,
it sheds a sheet of water for 11 m behind its nose, so each point is wet for about 0.9 s. The sheet
falls straight down:

- Lot cover stops it: an awning beneath the track keeps the walker dry.
- An open umbrella held upright stops it. A tilted one doesn't: rays go straight up from the body
  samples to the train's underside (or a deck's), and `wet_wash_rate` (36/s, near the gutter rate)
  applies to the exposed fraction. In open sky with wind that is the street's test: tilt into the
  rain, or straighten up for the train.
- Two seconds before the sheet reaches him, a rumble builds (`train_pass`) and the train's headlight
  sweeps in from the right; the camera shakes as it goes over. The first train shows a hint.

The beam's underside is at 3.65 m and the train's skirts hang to 3.4 to 3.85 m, low enough that the
camera sees them. Things that stand higher at the kerb or over the pavement go through the train, so
`level_preview.py --report` fails **track-clearance** for a `lamp_post` prop on the track (the beam
carries its own lamps, one every other pillar) and for a `balcony` or `arcade` lot under it (their
slabs sit at 4.1 m); use awnings. Shop signs (3.1 to 3.9 m on the facade), blade signs and awnings
clear it. Pillars stand under the beam every 14 m, never in a side street.

**`viaducts`** (`x0`, `x1`, `style`; `s.viaduct(from_tag, to_tag)`) are deck spans hung off the back of
the beam from the start of `from_tag` to the end of `to_tag`, and need a `track`. A deck is a solid slab
over the walker (underside 3.35 m, above the awnings) with an enamel fascia, a girder under it every 2.5
m and lamps in its soffit, and it is cover, so no rain falls beneath it between trains. The visual rain
stops across the deck's whole x range, from the wall out to the camera, and awnings beneath it don't
drip; the beam's light drip line is the only one along the viaduct. A deck would hide the 3.4 to 3.9 m
part of the sign band, so a shop beneath one hangs a smaller sign just above its awning instead. When a
train crosses it, the sheet falls from the deck's underside instead of the train's, so the deck is
shelter from the rain but not from the wash. A gutter under a deck fails track-clearance, because its
downpipe reaches out through the deck.

Everything follows from `Level.wash_at(x, t)` and `wash_eta(x, t)` on the level clock (`elapsed`) and
the attempt's departures (`Track.departures`), so gameplay, visuals, sound and the bots agree within a
run. Testing flags: `--clock=S` starts the clock at S, `--train-seed=N` rolls the same departures every
time (`--autopilot` runs and the tests always use seed 1, so bot numbers compare), and `--wash-always`
drops the sheet along the whole track at once. The bots open the umbrella upright when a sheet will land
on bare pavement on their path within the opening time plus 0.5 s, and never rest where it can land.
They read every train perfectly and almost never get washed, so a track costs them stamina, time and a
little slanted rain while they stand upright; Telstar Parade sets `par_speed` 1.4 for that reason.
`style` is `"monorail"` or `"railway"` (below).

**Railway** (`s.track(gap, style="railway")`, `s.viaduct(from_tag, to_tag, style="railway")`) is a low
brick viaduct standing over the pavement instead of a beam in front of it, on the same schedule and the
same sheet of water. Its `viaducts` are runs of brick arches: piers at the kerb every 5.4 m or so, a
vault over the pavement from 3.1 m (above every awning) to the deck at 3.5 m, and that vault is cover
from the rain **and** from the sheet, which falls from the carriages (3.95 m) onto the deck. Lots under
the arches take `cover: "none"`; an arch hides the facade above 3.1 m, so their signs drop to the
lintel (2.8 m), and an awning lot's sign is left off. Between the arches the line crosses on open
lattice girder spans with cast-iron columns under long ones: rain and the sheet fall through them onto
the pavement, so a girder span plays like open track and an awning beneath it keeps both off. A lantern
hangs from the girders where each span meets the arches and on every column; `s.prop("bracket_lamp", x)`
hangs another anywhere. Lamp posts, balconies and arcades still fail track-clearance. The trains are
two carriages of country stock, seen over the parapet from about 3.9 m up. level_preview counts the
arches as cover and leaves them out of the wash. `Track.arch_at(x)` is true under a railway's arches.

**`skyways`** (`[{"x0", "x1"}]`; `s.skyway(from_tag, to_tag)`, `src/level/skyway_builder.gd`) are
enclosed glass galleries over the pavement from the start of `from_tag` to the end of `to_tag`, and
cover. One may bridge a side street. Its underside is at 4.45 m, above the sign band, so shop signs
beneath it show; it reaches from the facades to 3.3 m, short of the kerb, and its roof is at 7.6 m.
Slim columns stand under its front edge at most 9 m apart, never in a side street's road and 0.6 m
clear of kerb props. Rain drips from its front edge, and the visual rain stops on its roof and never
shows inside the glass. Because it is high, wind slants rain in under its ends much further than
under an awning: 1 m inside the upwind end in a 0.6 wind the walker is fully wet (under an awning,
about an eighth), and dry again some 5 m in. Lots under a skyway normally take `cover: "none"`; an
awning beneath it keeps its own drip line off. Lamp posts, balconies and arcades under a skyway fail
the **skyway-clearance** check, and a lot beneath one gets no blade sign, hologram or overhead cables.

**`idling_sedan`** (`s.prop("idling_sedan", x)`, x inside a crossing without `car`) stops a black
sedan nose-out in that side street with its engine running: wipers, exhaust, headlamps and a hat
behind the wheel. Scenery only.

**`attackers`** (`[{"x", "shots"}]`; `s.attacker(x, shots=5)`) are scripted pursuers on the walker's
own model, suit and umbrella, who come up behind him one at a time (a later one waits until the last
has gone). When the walker passes `x`:

- **Warning, 2.5 s:** brisk footsteps panned left, and his long shadow thrown ahead of him along the
  pavement by a lamp behind him, growing as he comes, before he is in shot. Author a `bracket_lamp`
  about 9 m before `x` so the lamp is there.
- **Then** he walks in from the left and holds 5.8 m behind the walker; the camera eases back
  (`Level.camera_bias`) to keep him 1.3 m inside the left edge. Once he has closed in he walks no
  faster than `walk_speed`, so a walker who hurries or runs leaves him behind: out of the frame for
  1 s, he gives up and doesn't come back.
- **Every 2.5 s** he fires a telegraphed shot (`WaterJet`): a 0.6 s glint at his umbrella's tip
  (brought down to chest height), then a tight shotgun burst of 46 pellets (`DropletBurst`) out
  along the street, `WaterJet.SHOT_ELEV` (5 degrees) above level and fast enough to reach his chest
  where he'll be. Each pellet that reaches him from the knees up wets the body point nearest it (3
  soak a point; a full hit, half his weighted body soaked, is `wet_jet_hit`, 12, through `Player.soak(amount, &"shot")`, so a shot that soaks him fails the
  attempt as SHOT); his canopy stops the ones it meets. Upright, it stops none; tilted back toward
  the shooter, 70% of full tilt stops about three quarters, 85% nearly all (flat back lets the rain
  in). A canopy that stops a fifth or more is shoved aside for 0.7 s (tilt and droop, `jet_shove`,
  less with Sturdy Frame: `upgrade_sturdy_jet_shove`).
- **Under a railway arch** he holds his fire, but the held shot still counts, as does one he can't
  reach from more than 9 m back. After `shots` he drops back out of the left of the frame.
- **He can be soaked.** Each man is an `NpcBody` with the walker's capacity (`wet_max`, 50): two
  clean hits of the walker's shot soak him. Soaked, he drops his umbrella and trudges off the left
  as the walker does when he fails; the camera holds back 2.5 s so it is seen, and the next one
  comes as if he had dropped back. He holds 5.8 m back, past the base range of the shot (4 m), so
  on an armed street only Long Barrel reaches him there unless the walker stops and lets him close in.

Optional fields per entry (`s.attacker(x, shots, gap=, wait=, hint=, hit=)`):

- **`hit`** replaces `wet_jet_hit` (12) as the wetness of one of his shots landing in full. The
  Bypass uses 8, like Rocket Row's waiting men, since the walker fights back there.

- **`gap`** replaces the 5.8 m he holds back (`hold_gap()`); the camera's ease-back follows it. At
  3.6 m he is inside the shot's base range.
- **`wait`** posts him at that x from the start, under cover at z 0.9, facing back down the street
  with his umbrella up, as soon as nobody earlier is on. He is in plain sight and can be soaked there
  (that spends his entry). When the walker reaches his `x` he fires from his post without the
  warning (first glint 0.8 s in, then every 2.5 s); once the walker is 0.5 m past him he turns and
  follows like the others. Posted, he never spends a shot on a walker more than 9 m off: he lets
  that moment pass and keeps the shot, so he can't be waited out from beyond his reach. With his shots
  spent he stays at his post. `side()` says which way to tilt to block the one on now; the bots brace
  that way.
- **`hint`** is shown as he comes, instead of the first man's two built-in hints.

A man soaked while his shot is in the air doesn't take the shot with him: it lands, and the bots stay
braced for it. The first one shows "Behind you." as the warning starts and a tilt-back hint at his first glint. A
checkpoint resume skips every pursuer whose `x` is behind it, so one who was on at the checkpoint
doesn't come back. The bots open up ahead of each glint (`next_glint_in`, as the canopy takes
`umbrella_open_time` to open) and tilt back (85% of full tilt) when a jet glints, with the human
bot's reaction delay, and never stop to rest in his line of fire. level_preview can't simulate them and
ignores them: `tools/preview.sh` is the judge. Bring each in some 15 m short of a run of arches, so a
few shots come in the open and the rest are held, and keep the human bot's minimum stamina above 10:
the umbrella stays up through every shot.

**`henchmen`** (`[{"x"}]`; `s.henchman(x)`) are men on the walker's own model, suit and umbrella,
each standing under cover at `x` (lane z 0.75, by the shopfronts) with the umbrella furled, facing back
down the street like the `figures` around them. The rules, all in `src/level/henchmen.gd`:

- **In range.** When the walker is within 7.5 m of one (`RANGE`, ahead or behind) and the man is in the
  frame (taken as at least 16:9, `Level.in_frame`), he opens the umbrella (0.9 s) and fires a telegraphed
  `WaterJet` at him 0.5 s later: a 0.6 s glint, then the burst. A jet that lands in full wets the walker
  8 (`HIT`, cause `shot`); a canopy tilted toward him stops what it meets and is shoved as usual.
- **Timer.** The gap from one jet landing to the next glint cycles through `INTERVALS` (2.4, 3.1, 2.7,
  3.4 s; each man starts at a different place in the table), each nudged by up to 0.2 s at random.
- **Canopy.** Between shots he holds it overhead, so the walker's shot reaches his chest; from the glint
  until his jet has landed it is brought down at the walker and stops the shot (40 of 40 droplets in
  the tests). The opening is the 2 to 3 s between his shots.
- **Passed.** Once the walker is 0.35 m past him he turns round (0.6 s) and keeps firing from behind
  while the walker is in range and in the frame.
- **Soaked.** Each is an `NpcBody`: two clean hits of the walker's shot soak him and he plays the defeat
  walk. A man is *dealt with* when he is soaked or the walker comes within 1 m of him (`dealt_with`).
- **Hint.** The first man to open up shows "He's looking for you..." once per attempt.
- **Checkpoints.** A resume leaves out every man more than 7.5 m behind it. Put each checkpoint at
  least 12 m short of the next man, so a resume starts out of range (`s.checkpoints` by hand if the
  solver lands too close), and put refill gutters outside every man's range: the bots never refill
  under fire.
- **The bots** open up ahead of each glint, tilt toward the man while his jet glints and flies (85% of
  full tilt: forward for one ahead, back for one behind), never rest in range of one, and fire only
  when the line from the umbrella to his chest is clear of his canopy. `level_preview.py` ignores them;
  `tools/preview.sh` is the judge.

**`pickup`** (`{"x", "after"}`; `s.pickup(xing_tag, after)`) stops a black sedan in the side street at
the crossing starting at `x` (one without `car`), headlights off, with a man in a yellow slicker
(`RaincoatFigure`, watching) waiting at the corner under the last canopy before it. He is
scenery: no water reaches him. While the walker is within 22 m short of the crossing the camera eases
2.5 m ahead (`Level.camera_bias`) to keep him in shot, and the first time he is in the frame the hint
"Raincoat. Of course he wore a raincoat." shows. When henchman number `after` (0-based, in x order) is
dealt with, the engine turns over and the headlights come on (the car warning and its hint) while he
walks round the corner and gets in. Then, at least 1.3 s after the engine started, the car pulls out
across the pavement and throws the usual car splash (`CarHazard`) as soon as the walker is 3.5 to
6 m short of the crossing. It waits while he is closer or in the road, and once he is across it
leaves behind him. A resume past the crossing leaves the car out; one past the man `after` starts
with him boarding. Place the crossing about 6.5 m past that man, with the man inside the last
canopy.

**`drive_bys`** (`[{"x"}]`; `s.drive_by(x)`, `src/hazards/drive_by.gd`) are cars that come up the
near lane of the road (z 5.4) from behind the walker, one at a time. When the walker passes `x`:

- **Warning:** the engine and tyre hiss (`car_pass`) from the left while the car is still out of
  shot, 34 m back; its headlights, dipped toward the kerb, sweep the pavement ahead of him. The
  camera eases out (`Level.camera_pull`, 6 m, plus 0.12 m of height per metre) so the lane is in
  frame. The first one each attempt shows "Headlights. Behind.".
- **Splash:** from when its kerb-side front wheel is 7 m behind him until it draws level, the wheel
  throws six bursts of road water (`DropletBurst`, cause `splash`) up and over at the pavement,
  carried forward by the car: they come down on him from behind. Unblocked that is about 11
  (90% of `wet_car_splash` once half his body is soaked); a canopy tilted back 60% or more stops it.
- **Shot:** it slows to hold its back window 7.5 m ahead of him; 1.2 s into the pass a passenger sits
  up on the kerb-side back window's sill, then a `WaterJet` (0.6 s glint, `wet_jet_hit`) leaves
  from over the boot back at him. A canopy tilted forward 85% or more stops most of it (a few pellets
  get past a moving walker, as with the men on foot); one that soaks him fails the attempt as SHOT.
  The walker's own shot has no effect on the car.
- Once the shot has landed it speeds off to the right; 2.2 s later the camera eases back in.

The splash and the shot are separate: the canopy has to swing from back to forward between them.
Tilting over costs rain in the open, so put the trigger about 4.5 m short of cover: the splash lands
in the open and the shot as he reaches the cover (`DRIVE_BY_LEAD` in `tools/streets/the_bypass.py`).
The scenery traffic waits while one is on, and sends no car from 40 m short of its `x` (`DRIVE_BY_CLEAR_M`), so none is on the lane when it comes. A checkpoint resume skips every drive-by whose `x` is
behind it. The bots hold the umbrella open while one is on, never rest or refill, tilt back
(`DriveBy.brace()` -1) from 0.35 s before the splash until it has landed and forward (+1) from 0.5 s
before the shot until it has landed. level_preview ignores them (`tools/preview.sh` is the judge).

**`helicopters`** (`[{"x", "dir", "speed", "hover_x", "hover_s"}]`, all but `x` optional;
`s.helicopter(x, dir=-1, speed=None, hover_x=None, hover_s=None)`, `src/hazards/helicopter.gd`) are
the shuttle helicopters flying low along the street between the terminal and the airport. When the
walker passes `x`:

- **Flight.** One comes in 50 m past `x` (`dir` -1, the default: flying right to left, toward him) or
  50 m short of it (`dir` 1: overtaking him from behind), flies 110 m along the street over the
  pavement's front edge at `speed` (6 m/s by default) and is gone. With `hover_x` it brakes at
  2.5 m/s² to a stop over that x, hovers `hover_s` seconds (3 if left out) and flies on; `hover_x`
  must lie on its path at least its braking distance (7.2 m at 6 m/s) from either end, or the hover
  is dropped with a warning. From ahead its wash meets a walking walker about 6.4 s after the
  trigger, some 8 m past `x`; from behind at 6 m/s, about 9.5 s after it, some 12 m past `x`.
  Nothing is random: each flight is a pure function of the level clock from the moment it is
  triggered.
- **Wash.** The footprint on the pavement under it is full strength within 3 m either side of it and
  fades out over the next 1.2 m, so a passing one sits on a spot for about a second. Inside it cover
  is no shelter (skyway, awning, slab or deck): each body sample is soaked, by the wash's strength
  there, unless the open canopy is straight above it (a vertical ray, leaking while the canopy
  opens), at `wet_rotor_rate` (10/s). Upright the canopy keeps all of it off; tilted fully over it
  doesn't. A pass with the umbrella shut costs about 10 (20%); a hover costs that much for every
  second he stands in it. While the umbrella is open in the wash the canopy fights the downdraught:
  `stamina_drain_rotor` (4/s) on top, walking or standing (Sturdy Frame cuts it like the rest).
- **Telegraph.** The rotor's thud (`rotor_loop`) builds from its side from the moment it is
  triggered; its searchlight sweeps the pavement about 9 m ahead of it; while it is within 28 m of him
  the camera eases out 4 m (`Level.camera_pull`, as for a drive-by) so it is seen whole, and it
  shakes as it goes over; under it the rain is driven in sideways and spray blows out along the
  pavement. The first one each attempt shows "Rotor wash! It blows the rain in under cover. Umbrella
  up ({umbrella})." 3.5 s before its wash reaches him. Its rotor hub flies just under the top of that
  eased-out frame, between 9 and 14 m up.

`Level.rotor_at(x, t)` (0 to 1) and `Level.rotor_eta(x, t)` read the wash on the level clock: a
triggered helicopter's future is known, so a later `t` predicts it. The bots open up, upright,
when the wash will be on their path within the opening time plus 0.5 s; it overrides any tilt a
courier's glance or a gunman asks for, so don't stack those on a pass. They never rest or refill
within the opening time plus 3 s of it. A checkpoint resume skips every helicopter whose `x` is
behind it. `level_preview.py` draws each trigger (an arrow the way it flies, a ring at `hover_x`)
and leaves the wash out of its scores: `tools/preview.sh` is the judge. Trigger each where the walker
has some 10 m of cover ahead, so a player who reads it has time to open up, and keep hovers short: an
open canopy walking in the wash costs 7 stamina a second.

`--start-x` past a trigger skips that helicopter too; for screenshots, start about 2 m short of it.
A modelled helicopter at `res://assets/vehicles/helicopter.tscn` (or `.glb`) replaces the stand-in
built in code; docs/CONTRACTS.md §8 says what it must provide.

**`slickers`** (`[{"x", "z", "facing", "pose"}]`; `s.slicker(x, z=0.8, facing=1,
pose="stand")`) place a man in a yellow slicker (`RaincoatFigure`) at x on lane z:
`facing` 1 or -1, `pose` `"stand"`, `"watch"` (turned toward the street) or `"walk"`. Scenery only:
he is no `WetBody`, so the walker's shots pass him. Put him under cover.

**The walker's shot (armed streets).** From the sixth street out from Main Street on either side
(`Game.GUN_FROM`; the number is the street's place on the map, `Game.street_number`), the walker can
fire the umbrella: RB, F or the left mouse button (`{fire}` in hint text), or the FIRE button with
touch controls. Below that it is locked and the HUD shows no water meter. The first armed street a
run walks shows "There's a reason the umbrella is heavy. ({fire})". `--armed` arms any street for
testing.

- **Aim:** the shot leaves the end of the shaft, along the shaft. Open, the canopy's tilt aims it.
  Furled, the aim input raises the shaft from his side and points it (`Player.aim`, `Inputs.aim`): a
  stick by its direction (left behind, right ahead, up overhead, within `umbrella_max_tilt` of
  upright), Q / E, the mouse and the touch slider by how far they're pushed. At rest it hangs at his
  side; firing from rest swings it up toward the side it last fired, and it stays up 0.6 s after a
  shot. A body whose chest is within 40° of the shaft's line (`WaterGun.ASSIST`) pulls the shot onto
  it.
- **The burst:** 40 droplets (`WaterGun`, a `DropletBurst` with cause `shot`) at 15 m/s from the
  umbrella's tip, fanned ±0.08 rad up and down. Droplets are spent at the range, `gun_range` 4 m plus
  `upgrade_barrel_range_add` per Long Barrel tier ([0, 2, 4, 6]), each up to 10% short of it; spent
  ones drop out of the air and wet nobody.
- **Damage:** a burst that soaks 45% of a body's weighted points wets it `gun_hit` (25, half of
  `wet_max`) times `upgrade_pressure_mult` per Pressure tier ([1, 1.25, 1.5, 2]): two clean hits soak
  a man, one at Pressure tier 3. A canopy the droplets meet stops them, so a man whose umbrella is
  between takes proportionally less.
- **Water:** `gun_shots` 4, one every `gun_cadence` 0.35 s while the button is held. It refills at
  `gun_refill_rain` (0.08 a second, one shot in 12.5 s) while the open canopy is out in the rain (not
  furled, not under cover), and at `gun_refill_stream` (one a second, with
  a rising splash per shot) while the walker is stopped with the umbrella fully open under a gutter
  stream that lands on at least half the canopy. A gutter is a refill point: put one before a fight.
- **Shop:** Long Barrel (`barrel`) and Pressure (`pressure`), 3 tiers each at `upgrade_costs`, are
  offered once the run has walked a fifth street.
- **Bots:** under `--autopilot` the walker fires whenever a soakable man is in range and in shot on
  the side it aims (tilting back for one behind), and stops under a gutter stream to refill when two
  or more shots are gone (the human bot asks its reaction time early so it stops under the stream;
  either gives up after 1.5 s stopped without the stream refilling it). Each soak prints `NPC_SOAKED x= t=`.

Every body water can wet is a `WetBody` (`src/player/wet_body.gd`): feet at its origin, facing +X,
measured on the weighted `SAMPLES`, with its own wetness and `wet_max()`, the physics layer of its
canopy (`canopy_mask()`), and `weatherproof` (only shots wet it). The walker is one; an NPC that can
be soaked is an `NpcBody` (`src/level/npc_body.gd`), which brings the walker's model and umbrella, and
whose owner moves and poses it until it is soaked. NPC canopies are on their own physics layer
(`npc_umbrella`, `Umbrella.NPC_UMBRELLA_LAYER`): they stop droplets flown at the NPC and never keep
rain, streams or sheets off the walker. Every `DropletBurst` (car splashes, jets, the walker's shot)
flies at every body of the level but the one that fired it.

**`set_pieces`** (`name`, `x0`, `x1`, `teaches`) is a top-level list the game ignores. Fill it in so
the next person can see the intent without replaying the street.

## The design checks

`level_preview.py` scores each tenth of `end_x` (about 26 m) for open sky x rain, plus gutters and
crossings. A deck counts as cover. Every metre of track with no lot cover beneath it, deck or open
sky, scores `WASH_W` (5.2) x the wash duty of a metre of open sky at rain 1 on top. The duty is the
share of the time a sheet falls on a spot, 0.92 s over the mean gap (0.052 for `gap` 10 to 25 s),
because the preview can't know an attempt's timing. The `wash` column shows that share, and the strip
draws it in the hazards lane. The checks are:

- **start-covered.** The first 20 m has no open sky.
- **ramp-to-midpoint.** Through decile 5, no decile falls more than 20% of the peak below the one
  before it.
- **hold-after-midpoint.** Deciles 6 to 10 stay within 30% of their mean, and the first half
  averages lower than the second.
- **span-crossable.** No open span is longer than one bar of stamina (33 m with no wind).
- **checkpoints-safe.** `"checkpoints"` holds three x values, one near 25%, 50% and 75% of `end_x`
  (within 10% of `end_x`). Each sits 0.5 m into a stretch of cover and has `CLEAR_M` (4 m) of dry cover
  ahead before the next gap, gutter, car crossing's headlight zone or stretch of track with
  no lot cover (the wash can land there whatever the trains do, so on a street with a track only
  awnings and slabs qualify). Cover ends are pulled in
  by the wind slant plus half a body. `Street.write()` picks them with `solve_checkpoints`, so the plan
  never lists them. To place them by hand, set `s.checkpoints = [x1, x2, x3]` before `s.write()`; the
  check still applies. `tools/checkpoint_check.sh` replays each one in the game with the umbrella shut
  and the sheet falling along the whole track (`--wash-always`), and fails if the walker gets wet
  inside those 4 m.
- **track-clearance** (streets with a `track`). No lamp post, balcony or arcade under the track and no
  gutter under a deck, as described under `track` above.
- **skyway-clearance** (streets with `skyways`). No lamp post, balcony or arcade under a skyway.

The report also prints the share of `end_x` under cover and under a skyway; a skyway street aims for
at least 60%. A skyway counts as cover everywhere in the preview, and its ends are pulled in by its
own height (4.45 m) times the wind slant, so checkpoints sit further inside it in wind.

A decile is short, so a breather has to sit inside the same decile as its test. A decile that is all
cover right after a hard one fails the ramp check. Sun breaks count as zero rain, so a sun decile
needs other gaps or gutters to stay inside the hold band. A big set piece can straddle a decile
boundary to split its weight.

## Pacing pattern (Main Street)

Teach one idea safely, test it once, then combine ideas at the end. Each roughly 26 m holds one test
and the cover that follows it.

| x (m) | Set piece | Asks the player to |
|---|---|---|
| 0 to 28 | The Bijou arcade (diner, cinema colonnade) | walk under continuous cover |
| 28 to 68 | First gaps (2.5, 4, 3, 5 m) | open the umbrella for a short gap |
| 80 to 104 | Elm Street and the Hotel Ambassador | cross 12 m (about 40 stamina), then close up under 12 m of balconies by a fire barrel |
| 104 to 139 | The drainpipe at the Savings & Loan | keep the umbrella upright under a gutter, then a second through a torn awning |
| 139 to 162 | Oak Street | deep puddles at both kerbs (a splash, no cost), then 15 m of cover |
| 162 to 192 | The Palace lot | close the umbrella in a 6 m sun break between two rainy strips |
| 220 to 257 | Pawn Row | torn awnings that keep the umbrella up, a gutter through a tear, a breather, a last gutter at the inn |

Recovery needs real cover. After a gap the walker closes the umbrella (1.3 s) and only then starts to
regenerate, and a player reopens about 2 m before the next gap. Cover shorter than about 5 m
therefore gives back almost nothing. A row of torn awnings with short intact pieces plays as one long
stretch with the umbrella up, which is what makes Pawn Row a stamina test.

## Pitfalls

- **The perfect bot hurries whenever stamina is above 80 and nothing is ahead.** It meets each gap
  with about 80, not 100, and stops (about 4 s each) once it falls to 24. Watch its `min stamina` and
  its time. Each stop costs score.
- **Neither bot takes much rain damage in normal play.** On a street without cars or gutters they
  stay almost dry, and drying never matters. To make the wetness curve move, put gutters or car
  crossings at the tests.
- **`tests/run_tests.gd` uses the first untorn awning of 4 m or more and the first `none` lot of 4 m
  or more** on Main Street. It expects full exposure at the centre of that open lot, so it must not
  be a sun break.
- **Cover the car approach.** Headlights appear about 10.5 m before a car crossing and the right
  response is to tilt fully forward, which bares his back to the rain. Open sky in that approach
  costs 7 to 19 wet (measured on Arcade Lane and Neon Junction). Gentle streets keep 11 m of cover
  before each car crossing; an open verge there is a deliberate, hard test (Mill Road's County Line).
- **The bots never tilt under a gutter**, so gutters cost them nothing. The gutter test only bites a
  real player who keeps the umbrella tilted into the wind.
- **Exhaustion is a cliff.** Once stamina hits 0 the umbrella droops and wetness climbs 15 to 35 in a
  few metres. Keep the human bot's minimum stamina above about 10.
- **span-crossable treats a rain/sun/rain field as one span**, so such a field is capped at about
  26 m even though the sun lets a player recover.
- **`--start-x` for screenshots:** start under cover. Cars whose crossing is behind the start never
  drive.
- **`--slicker=X[,stand|watch|walk[,1|-1[,Z]]]`** places a man in a yellow slicker
  (`src/level/raincoat_figure.gd`) at x X, lane z Z (default 0.8), for screenshots only;
  `--slicker-close` frames the first one with a close camera.
- **`--aim=-1..1`** (with `--armed` below street six) holds the furled umbrella raised and pointed that
  share of `umbrella_max_tilt` from a second in, `--fire` holds the shot down, and `--player-close`
  frames the walker with a close camera. Screenshots only.
- **`--stop`** holds Stop from the start (`--stop=S` from S seconds in) and **`--stamina=N`** starts
  the street with N stamina, for looking at the walker standing rested or out of breath. Screenshots
  only.
- **The title screen shows Main Street from 4 to 60 m.** Keep that stretch good-looking.
- **Colonnade columns hide sign letters.** Use short signs on `arcade` lots, or accept the
  partial word.
