# Don't Get Wet — Game Design Document

Game design: **Peter Wells**

Status: living document. Prototype phase (v0.1). Numbers in **Tunables** are starting points and live in
`data/tunables.json`; change them there, not in code.

## 1. Pitch

A close-up 3D side-scroller in a city where it never stops raining. You don't steer — the character
walks forward on their own. Your job is to keep them dry: open the umbrella under exposed sky, close it
under cover to recover stamina, hurry across gaps, and read the street ahead. Get too wet and they give
up, drop the umbrella, and trudge off-screen.

Closer to an action game than a rhythm game: the player makes constant small trade-offs between
**wetness**, **stamina** and **time**.

## 2. Core loop

1. Walk along a street (auto-walk, steady pace).
2. Rain falls wherever the sky isn't blocked (awnings, balconies, roofs, umbrella).
3. Hold the umbrella trigger to open (partial press = partial open). Opening takes time, protects
   proportionally while opening, and drains stamina while open.
4. Release to close (same speed as opening). Stamina recovers whenever the umbrella is closed.
5. Reach the inn/shelter at the end of the level → scored on **dryness** and **time** → tokens.
6. Pick the next location on the city map (adjacent nodes only), spend tokens on umbrella upgrades.

## 3. Controls

| Action | Gamepad | Keyboard / mouse | Touch |
|---|---|---|---|
| Umbrella (hold, analog) | Right trigger | Right mouse / Space (digital) | Hold right-side button |
| Hurry (analog; full = run) | Left trigger | Shift (full) / W (half) | Hold left-side button |
| Stop (hold) | Left bumper | S / Ctrl | Hold Stop button |
| Tilt umbrella fwd/back | Either stick X (both pushed = average) | Mouse left/right (sticky; cursor hidden in play) / Q, E | Drag on umbrella button |
| Pause | Start | Esc | Pause icon |

Digital inputs ramp to full over ~0.1 s so keyboard feels as smooth as a trigger.

## 4. Character

- Man, mid-20s to middle-aged, raincoat-less office clothes (that's the joke — he's not dressed for it).
- States: `WALK`, `HURRY` (analog blend walk→jog→run), `STOPPED`, `EXHAUSTED` (stamina 0), `DEFEATED`
  (fail sequence), `ENTERING` (level-complete sequence).
- Walk speed is reduced while the umbrella is open (scaled by open fraction) and by strong headwind.
- Wetness is visible on the character: clothes darken, hair flattens, drips fall from him.

### Umbrella

- `open` ∈ [0,1]. Target = trigger amount. Moves toward target at `1 / open_time` per second, both
  directions (closing is as fast as opening). Releasing mid-animation reverses from where it is.
- Coverage radius = `radius * ease(open)`, so a half-open umbrella protects partially.
- When closed, the character carries it in the off-hand.
- Tilt ∈ [-max_tilt, +max_tilt] around the walking axis (forward/back only), default vertical, eases
  back to vertical when the stick is released.
- **Exhausted** (stamina = 0 while open): the umbrella droops and sways, coverage drops; it can still be
  opened/closed. Stamina only regenerates while closed.

### Stamina (0–100)

- Drains while walking with the umbrella open (× open fraction; × wind load), and while hurrying.
  Standing still (Stop) with it open costs nothing.
- Regenerates whenever the umbrella is fully closed — even in the rain.
- **Stop** (LB, hold) stands him still for as long as it is held and he walks on when it is released.
  It works at any stamina, beats hurry, and the umbrella may stay open (for waiting under a gutter
  stream, say). Stamina regenerates faster while stopped, but only with the umbrella fully closed.

### Wetness (0–100)

- Increases with rain exposure × rain intensity, gutter streams and car splashes. Puddles
  only splash underfoot: nobody can step round one, so they cost nothing.
- Decreases **only** in sunny patches and warm air (vents, fires), at full rate above 90 and
  exponentially slower below it. Drying rescues a soaked run but never repays time spent waiting.
  On the early streets none sits in the final third. A street can slow that falloff (`dry.falloff`):
  on Long Lane the sun dries a half-wet walker about nine times as fast, so drying is part of the play.
- Resets between levels (the character spends the night at the inn).
- Reaching 100 → **fail sequence**: drop umbrella, scrolling stops, sad walk off the left of the
  screen, "You got wet" screen with Checkpoint / Restart / Map / Menu.
- Checkpoints at ~25/50/75%. A checkpoint resume starts at most 80 wet and costs 5% of the level
  score (additive per resume; a full restart clears the count). From the third resume of the same
  segment, each resume starts another 5 wet drier; reaching the next checkpoint resets that count.

## 5. Rain & exposure model

The game is only fair if it's readable, so exposure is **analytic** (not per-droplet):

- A rain direction vector (vertical, bent by wind).
- Each physics frame, ~9 sample points on the character's body (head, shoulders, torso, arms, legs)
  are ray-cast *against* the rain direction. Any hit on the `cover` physics layer (awnings, balconies,
  roofs, the umbrella canopy) blocks that sample. A tree's crown (its own `trees` layer) lets
  `tree_leak` (7%) of the rain through to a sample it shades, unless the open canopy is over it too.
- `exposure` = weighted fraction of unblocked samples. `wetness += exposure × intensity × rate × dt`.
- Visual rain is GPU particles colliding with a height-field that follows the camera, so drops visibly
  stop on awnings and the umbrella — what you see matches what the model computes.
- Cover edges are telegraphed: drip lines along awning edges, gutters pouring, puddles where the sky is
  open.

## 6. Hazards & helpers

| Feature | Effect | Counter |
|---|---|---|
| Open sky gap (short 2–3 m, long 5–15 m, crossings 8–12 m) | Rain exposure | Umbrella / hurry |
| Broken awning (tears/holes) | Local exposure inside "cover" | Umbrella / timing |
| Gutter stream (awning edge, downpipe) | Heavy local stream, high rate | Umbrella, tilt toward it |
| Car splash (side-street crossings) | Big burst from the front just before the crossing | Tilt umbrella forward |
| Wind (later levels) | Bends rain, extra stamina drain, slows when open into a headwind | Tilt into the rain |
| Helicopter rotor wash (Skyway Terminal) | A moving footprint where the downdraught drives the rain in under any cover | Open canopy held upright |
| Street trees (Long Lane) | Partial cover: 7% of the rain gets through | Shut the umbrella under them to rest, dry off in the sun |
| Gust (Long Lane) | Heard and seen coming down the street; slants the rain and shakes the trees' water down, shoves an open canopy | Open canopy held upright under the trees |
| Fairweather's quiet car (Long Lane) | Comes up from behind with no lights and no sound until its tyres hiss; a low sheet of water no tilt keeps off | None: dry off in the sun |
| Runner (Long Lane) | One of their men sprints up from behind and fires once as he passes | Tilt toward him at the glint; or shoot him |
| Hurricane wind (future) | Damages umbrella | Upgrades |
| Sunny patch | Dries slowly | Close umbrella to enjoy it |
| Warm vent / aircon / fire barrel | Dries faster, local | — |

## 7. Levels

- **Fixed, hand-tuned layouts** (learnable). Stored as JSON in `levels/`. A seeded generator
  (`tools/level_gen.py`) produced the first drafts; each street is now authored as a plan script in
  `tools/streets/` (see `docs/LEVEL_AUTHORING.md`) that writes its JSON. The game never generates at
  runtime. `tools/preview.sh` renders a street with both bots' runs and checks the pacing rules below.
- Length 3–8 minutes. Difficulty ramps from easy to the midpoint, then holds steady to the end.
  Difficulty knobs: gap length, gap density, cover reliability (broken awnings), rain intensity,
  gutters, puddle density, wind, cars.
- Start: short tutorial-ish stretch under continuous cover. End: the inn/shelter door — the character
  walks in.
- Layout grammar: the street is a sequence of **lots** (building frontages 2–12 m), each with a cover
  type (`awning` with optional `tears`, `balcony`, `arcade`, `canopy`, `none`) plus **crossings**
  (side streets, where cars come from) and **features** (sun, vent, fire barrel, gutter, puddle).

### First five locations (v1)

```
  [Country]                                                  [City centre]
  Mill Road ── Canal Row ── MAIN STREET ── Arcade Lane ── Neon Junction
     (5)          (2)          (1)            (3)             (4/5)
```

| # | Name | Aesthetic | New mechanic | Length |
|---|---|---|---|---|
| 1 | Main Street | Rundown 60s downtown, mostly shuttered, few lit shops | Core (cover, gutters, puddles, sun, vents) | ~3.5 min |
| 2 | Canal Row | Rundown, warehouses, more open sky | Light wind, longer gaps | ~4.5 min |
| 3 | Arcade Lane | 60s main street + first neon / retro-future signage | Side-street cars & splashes | ~4.5 min |
| 4 | Neon Junction | Mostly retro-future, neon, wet chrome | Wind + cars, heavy gutters | ~6 min |
| 5 | Mill Road | Edge of town, sparse cover, sunny breaks | Long exposed stretches, gusts | ~6 min |

Aesthetic rule: adjacent locations share a look. Moving toward the centre adds retro-future neon;
moving toward the country thins out buildings.

### Skyway Terminal (street 7 toward the centre)

The downtown air terminal: jet-age glass towers and an enclosed glass skyway over the pavement, seen
from further back (the street's `camera`) so the towers read at their size. From here on the rain
stops being the umbrella's main job: at least 60% of the street is under cover (88% as built). The
umbrella is for the airport helicopters' rotor wash, which drives the rain in under any cover where it
passes (held up and upright), for Fairweather's glances while you tail him (tilted fully forward to
hide your face), for his men's jets and the drive-bys (tilted at the shot), and for the shot itself.
Story: you tail Fairweather, the man in the yellow slicker, to the terminal; his men are waiting; his
helicopter passes over as you reach the Skyway Terminal Hotel, and the outro sends you on to The Zenith.

### Long Lane (street 7 toward the country)

The last of the suburbs past the Bypass, and the bridge between the town's dark streets and the
country: a 1960s suburb that has been left behind (empty and boarded houses among the lived-in ones,
a shut shopping strip, a railway overbridge, a church hall, a bus shelter with cracked glass), in the
grey daylight of a rainy late afternoon, brighter than the streets before it and darker than the
country after it, thinning toward the country at its far end. Little real cover (14%): street trees
(32%) keep most of the rain off but not all, and a low sun breaks through often and for a long way
(28%), drying him much faster than elsewhere. Against that, wetness he can't do much about: gusts that
shake the trees' water down, two runners who fire once as they pass, and Fairweather's black car coming
up behind three times with its lights off, through the puddles. Story: Fairweather is driving; you
reach the Royal Hotel and his car waits in the lane all night. The country look (hedges, oaks, fields,
a barn, a lychgate, a pub) is built and kept for the last street, The County Road.

## 8. Map, scoring, progression

- After a level: score screen → **city map**. Nodes adjacent to the current node are selectable; hover/
  focus shows a short preview popup (name, blurb, best score, difficulty). The map is one straight road
  from the country to the city centre, longer than the screen: about five streets show at a time and it
  scrolls to the focused one. Streets that aren't built yet show on it as "Coming soon" and can't be
  picked. `levels/index.json` (hand-edited) holds the graph; a node with `"soon": true` has no level file.
- **Runs.** The start street sits in the middle of the map, with streets leading left and right. Each
  direction is its own run with its own map position, best scores, tokens and upgrades, saved in its own
  slot. A new player's first run picks its direction with the first street they walk off the start;
  after that the run can't select streets on the other side. The main menu shows "← Continue" and
  "Continue →" (or "← Start" / "Start →" for a direction with no run yet), and each run can be
  restarted on its own.
- **Score** (0–1000): `dryness_score = 250 × (1 − wetness/100)`, `time_score = 750 × clamp(par / time)`
  where par = length / 1.3 m/s (a street may set a stricter `par_speed`). Time matters three times as much as dryness. Grades: D < 650 ≤ C < 780 ≤ B < 880 ≤ A < 950 ≤ S.
- **Tokens** = `floor(score × 0.0065)` (≈ S 6, A 5–6, B 5, C 4), paid only for improving on your best
  score for that street (so replays can earn more, never farm).
- Best scores shown on the map and in the main menu's level replay list. The list holds every street
  either run has walked; a replay is scored under the run that walked it and never moves that run on
  the map.
- **Upgrades** (3 tiers each, costs 6 / 12 / 18 tokens):
  - *Sturdy frame* — less stamina drain, less wind load (future: less damage).
  - *Wide canopy* — larger coverage radius.
  - *Featherweight* — faster open/close.
- No monetisation. Save file: `user://save.json` (version 2: settings, the active run, and a list of
  runs). A version 1 save (one run at the top level) loads as the run for the side it was played on.

## 9. Camera & presentation

- Close side-on perspective camera from the road, looking at the near sidewalk and shopfronts. Nothing
  beyond the near side of the street is shown.
- Character sits ~⅓ from the left so the player sees ~2× more street ahead than behind.
- Occasional foreground occluders (passing cars on the road, sign posts, pedestrians) — sparse.
- Scrolling stops on fail.

### Art direction

- **Painterly, not low-poly.** Smooth, bevelled, high-poly geometry, painted-look shading: a
  Kuwahara/oil-paint post filter, soft volumetric fog, wet reflective ground, warm shop light vs cold
  rain light.
- Early levels: decayed 1960s American-style main street — faded signage, boarded windows, striped
  canvas awnings (some torn), brick and terrazzo, sodium lamps. Later: retro-future neon and chrome
  creep in as you approach the centre. Toward the country the light grows: the suburbs (Long Lane) are
  a grey, brighter daylight, and the country (The County Road) brighter still.
- Character: CC0 high-poly human (MakeHuman/MPFB or similar), procedural/authored animation.
- Assets: Blender scripts in `tools/blender/` generate modular buildings/props reproducibly; CC0
  textures/models from Poly Haven / ambientCG. Licences are tracked in `assets/CREDITS.md`.

### Audio

Layered rain (intensity follows `rain_intensity`), rain-on-umbrella drumming that fades with open
fraction, rain-on-awning patter when under cover, footsteps (wet), distant traffic, shop hums, music
that thins when you're drenched.

## 10. Tech

- Godot 4.7, GDScript, Forward+ renderer. Targets: Linux/Windows desktop and Steam Deck first; mobile
  later with a reduced-quality preset.
- Structure: `src/` (scripts & scenes), `levels/` (JSON), `data/` (tunables), `assets/`, `tools/`,
  `tests/`.
- Headless tests: `tools/test.sh`, which runs `res://tests/run_tests.tscn` in parallel shards at `--fixed-fps 60`.
- Autopilot bot (`--autopilot`) plays levels to sanity-check that every level is beatable and to tune
  difficulty.

## 11. Out of scope for the prototype

Hurricane damage, localisation, mobile export. The story is told only through each street's text in
`levels/index.json` (blurb, loading line, fail lines, outro) and its hints.
