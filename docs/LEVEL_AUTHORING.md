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
6. Before committing, run `godot --headless --path . res://tests/run_tests.tscn` and
   `tools/playtest.sh LEVEL`. The playtest must report 0 errors.

Lots sit end to end, so every later `x` shifts when you change one width. Write the street as a plan
script, `tools/streets/LEVEL.py` (copy `tools/streets/main_street.py`): lots and crossings in walking
order, with features, props and set pieces placed relative to tagged lots (`s.mid("pipe")`). Run it to
rewrite `levels/LEVEL.json`; the plan is the source, so never hand-edit the JSON afterwards.
`awning_style=` on a lot picks one of the styles in docs/CONTRACTS.md; leave it out to get the
automatic mix.

## What each element does in play

Speeds: walk 1.3 m/s, 1.0 m/s with the umbrella open, hurry 2.0, run 3.2. The umbrella takes 1.3 s to
open or close, so a player has to start opening about 1.7 m before a gap.

Stamina is 100. The open umbrella drains 3/s, which is about 33 m of open sky on a full bar.
Hurrying drains 9/s and running drains 18/s. Stamina regenerates at 12/s only while the umbrella is
fully closed, and at 20/s while stopped with it closed. Stop is a hold control that works at any
stamina; the bots stop under cover once stamina falls to 24.

Wetness runs from 0 to 50 (the HUD shows a percentage). Open sky adds 9/s x rain intensity x the
exposed fraction of the body, so one bare second in the rain costs about 9 (18%). Only sun breaks,
vents and fire barrels dry the walker.

Score is `700 x (1 - wet/50) + 300 x min(1, par/time)`, with par = `end_x / 1.3`. S needs 950,
which allows about 2 to 4% wet at a typical time ratio of 0.88 to 0.92.

**Lots** (`x`, `w`, `style`, `cover`, `floors`, optional `sign`, `awning_color`, `awning_style`, `tears`,
`neon`):

| `cover` | Shelter | Notes |
|---|---|---|
| `awning` | canvas, tin or chrome, 2.35 m deep; nine `awning_style`s (docs/CONTRACTS.md) that all shelter the same | The walker (z 1.6) is fully under it. `awning_color`: red, green, blue, brown, orange, teal. |
| `awning` + `tears` | holes at local `[x0, x1]` | Each tear is real open sky with a hanging flap. 1 to 1.4 m tears read well. |
| `balcony` | flat slab at 4.12 m, 2.4 m deep | Pale concrete with a rail, lit underneath. |
| `arcade` | flat slab at 4.15 m, 2.9 m deep, columns every 3.5 m | Reads as a colonnade. Columns can hide part of a sign. |
| `canopy` | gas-station roof | Only with `style: "gas_station"`, which draws it. |
| `none` | open sky | |

`style` picks the ground-floor kit module: `shop_lit` (lit window, warm sign), `shop_dark`,
`shuttered`, `boarded`, `wall`, `doorway`, `inn`, `vacant` (chain-link fence, no building), plus
`gas_station`, `warehouse` and `loading_dock`. Kit widths are 3, 4, 5, 6 and 8 m. Other widths get
padded with filler strips, so a 1 to 1.5 m `wall` lot makes a narrow seam between buildings.
Building height is 4 m + 3.2 m per floor. Signs are lit only on `shop_lit` and `inn`. The font
shrinks to fit the lot width. `neon=True` gives a signed lot tube lettering on either kit era. On a
street with `neon` above 0 the builder swaps some lots to the retro kit, and a signless retro lot gets
a random filler name; pass `sign=" "` on narrow seams to keep it blank.

The level ends at the inn door. The builder sets `end_x` from the kit door: an 8 m `inn` lot puts the
door at `x + 4`. Keep the JSON `end_x` in step with it, because the preview uses the JSON value.

**Crossings** (`x`, `w`, optional `car`; `s.xing(tag, w, car=True)`) are open road. The ground drops 0.16 m, props inside are
skipped, and `"car": true` adds a car whose splash costs up to 20. A forward-tilted open umbrella blocks most
of it.

**Features:**

| `type` | Effect |
|---|---|
| `gutter` (`x`) | A falling column at z 1.65. Inside 0.45 m of it the rate is 26/s unless the umbrella is directly above. The bot opens for it even under cover. The column starts at 2.78 m, so it clips through intact awning canvas. Put it in a `wall` seam or inside a tear of 1 m or more. |
| `puddle` (`x`, `w`, `deep`) | Stepping in costs 0.75 walking and 2.5 running (above about 2.2 m/s). `deep` multiplies that by 1.6. Nobody can step around one, so the lesson is "walk, don't run". |
| `sun` (`x`, `w`) | No rain, and 3/s drying scaled by how closed the umbrella is (open shades him, no drying). The rain-free span stretches to meet cover within 2 m. Both bots close the umbrella in it. |
| `vent` (`x`, `w` = 1.6) | 4.5/s drying. |
| `fire_barrel` (`x`, `w` = 1.8) | 5.4/s drying. It sits against the wall and looks right under a balcony. |

**Props** are dressing only: `lamp_post`, `hydrant`, `trash_can`, `newspaper_box(_b)`, `bench`,
`mailbox`, `parking_meter`, `street_sign`, `downpipe`, `trash_bags`, `crates`, `cardboard_boxes`,
`bollard`, `phone_booth`, `sandwich_board`, `chainlink_fence_4`, and more in
`assets/props/props.json`.

**`set_pieces`** (`name`, `x0`, `x1`, `teaches`) is a top-level list the game ignores. Fill it in so
the next person can see the intent without replaying the street.

## The design checks

`level_preview.py` scores each tenth of `end_x` (about 26 m) for open sky x rain, plus gutters,
puddles and crossings. The checks are:

- **start-covered.** The first 20 m has no open sky.
- **ramp-to-midpoint.** Through decile 5, no decile falls more than 20% of the peak below the one
  before it.
- **hold-after-midpoint.** Deciles 6 to 10 stay within 30% of their mean, and the first half
  averages lower than the second.
- **span-crossable.** No open span is longer than one bar of stamina (33 m with no wind).

A decile is short, so a breather has to sit inside the same decile as its test. A decile that is all
cover right after a hard one fails the ramp check. Sun breaks count as zero rain, so a sun decile
needs other gaps or puddles to stay inside the hold band. A big set piece can straddle a decile
boundary to split its weight.

## Pacing pattern (Main Street)

Teach one idea safely, test it once, then combine ideas at the end. Each roughly 26 m holds one test
and the cover that follows it.

| x (m) | Set piece | Asks the player to |
|---|---|---|
| 0 to 28 | The Bijou arcade (diner, cinema colonnade) | walk under continuous cover |
| 28 to 68 | First gaps (2.5, 4, 3, 5 m) | open the umbrella for a short gap |
| 80 to 104 | Elm Street and the Hotel Ambassador | cross 12 m (about 40 stamina), then close up under 12 m of balconies |
| 104 to 139 | The drainpipe at the Savings & Loan | keep the umbrella upright under a gutter, then walk through a puddle |
| 139 to 162 | Oak Street | deep puddles at both kerbs, then 15 m of cover |
| 162 to 192 | The Palace lot | close the umbrella in a 6 m sun break between two rainy strips, then a fire barrel |
| 220 to 257 | Pawn Row | torn awnings that keep the umbrella up, a gutter through a tear, a breather, a last gutter at the inn |

Recovery needs real cover. After a gap the walker closes the umbrella (1.3 s) and only then starts to
regenerate, and a player reopens about 2 m before the next gap. Cover shorter than about 5 m
therefore gives back almost nothing. A row of torn awnings with short intact pieces plays as one long
stretch with the umbrella up, which is what makes Pawn Row a stamina test.

## Pitfalls

- **The perfect bot hurries whenever stamina is above 80 and nothing is ahead.** It meets each gap
  with about 80, not 100, and stops (about 4 s each) once it falls to 24. Watch its `min stamina` and
  its time. Each stop costs score.
- **Neither bot takes rain damage in normal play.** Their wetness comes from puddles minus drying.
  To make the wetness curve move, put puddles at the tests and drying after them.
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
- **The title screen shows Main Street from 4 to 60 m.** Keep that stretch good-looking.
- **Colonnade columns hide sign letters.** Use short signs on `arcade` lots, or accept the
  partial word.
