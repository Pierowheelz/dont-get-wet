# Integration contracts

These are the interfaces between gameplay code (`src/`) and content (`assets/`). Gameplay code only
relies on what is written here, so content can be swapped without touching code.

World conventions (all content):
- 1 unit = 1 metre. **+X = walking direction** (left → right on screen). **+Y = up**.
  **+Z = toward the camera** (the road side). Buildings' facades sit at `z = 0` and extend into −Z.
- The sidewalk runs from `z = 0` (building line) to `z = 3.5` (curb). Road beyond that (camera side).
- The character walks along `z ≈ 1.6`.

## 1. Character visual — `res://assets/characters/walker/walker.tscn`

Root `Node3D` with a script that implements **all** of these methods (see
`src/player/placeholder_character.gd` for a reference implementation with no real art):

```gdscript
func set_motion(speed_mps: float, run_amount: float) -> void   # in-place locomotion; run_amount 0 walk → 1 full run
func set_stopped(stopped: bool) -> void                        # idle / catching breath
func set_umbrella_pose(raise: float, tilt: float, droop: float) -> void
    # raise 0..1: right arm goes from relaxed to holding the umbrella above the head
    # tilt (radians): + leans the umbrella forward (+X), − backward. Range about ±0.7
    # droop 0..1: exhausted — arm sags and sways
func set_umbrella_open(open: float) -> void                    # 0..1 player's open amount; while it is between
    # closed and fully open the left hand reaches under the canopy and slides up/down the shaft
func set_wetness(w: float) -> void                             # 0..1, darken clothes, flatten hair, etc.
func set_mood(mood: StringName) -> void                        # &"normal" or &"sad" (defeated walk)
func get_grip(hand: StringName) -> Node3D                      # &"right" (raised, open) / &"left" (carried, closed)
```

- Feet at origin, facing **+X**, height ≈ 1.78 m. No root motion — the player script moves the root.
- `get_grip()` returns a Node3D that follows the hand bone. Its origin is in the palm; its local **+Y**
  points from the handle toward the canopy. For `&"right"` with `raise = 1, tilt = 0`, +Y is world-up
  and the grip is ~1.40–1.55 m above the feet, ~0.10–0.20 m in front of the chest (+X), elbow bent —
  the natural way people hold an umbrella. The umbrella shaft is 0.75 m, so the canopy apex sits at
  ~2.2 m. Tilt rotates the grip about the Z axis (+ tilts the canopy toward +X). For `&"left"`, +Y points down toward the ground
  (umbrella carried closed like a cane / hanging). With `umbrella_left` set before it enters the tree, the
  walker holds the open umbrella in his left fist instead, mirrored, and `&"right"` is that left-fist grip.
- The player script turns the root 180° about Y to walk left (defeat sequence).

## 2. Building kit — `res://assets/buildings/kit.json`

```json
{ "modules": [
  { "id": "shop_lit_5a", "scene": "res://assets/buildings/shop_lit_5a.glb", "kind": "ground",
    "width": 5.0, "height": 4.0, "style": "shop_lit", "era": "60s", "tags": ["lit"] }
]}
```

- Module origin = **bottom-left corner of the facade at the building line**. Spans `x ∈ [0, width]`,
  `y ∈ [0, height]`, front face at `z = 0`, depth into −Z (at least 0.5 m of visible reveal/sill depth).
- `kind`:
  - `ground` — ground-floor shopfront, height exactly 4.0. Awnings mount at y = 3.0, signage band
    3.1–3.9. `style` ∈ `shop_lit`, `shop_dark`, `shuttered`, `boarded`, `wall`, `doorway`, `inn`.
  - `upper` — an upper storey, height exactly 3.2.
  - `cap` — cornice/parapet that tops a building, any height.
  - `side` — a building's side wall seen down a side street. Its face lies in the plane `x = 0`,
    facing **+X**, spanning `z ∈ [−width, 0]` (so `width` = depth into the block) and `y ∈ [0, height]`.
    The builder mirrors it (scale.x = −1) for the other side of a crossing.
  - `filler` — narrow pilaster/drainpipe strips (0.3–1.0 m) used to pad widths.
- Widths should include 3, 4, 5, 6, 8 m for `ground` and `upper`.

## 3. Props — `res://assets/props/props.json`

```json
{ "props": [ { "id": "lamp_post", "scene": "res://assets/props/lamp_post.glb",
               "place": "curb", "footprint": [0.4, 0.4], "tags": [] } ] }
```

- Origin at the base centre. `place` ∈ `curb` (z≈3.2), `wall` (against z=0), `sidewalk`, `road`,
  `wall_high` (mounted on a facade at the given height).
- Required ids: `lamp_post`, `hydrant`, `trash_can`, `newspaper_box`, `bench`, `mailbox`,
  `parking_meter`, `street_sign`, `wall_ac_unit` (warm-air vent), `fire_barrel`, `downpipe`,
  `car_sedan` (60s sedan, facing +X, origin at ground centre).

## 4. Materials — `res://assets/materials/*.tres`

Required: `sidewalk.tres`, `asphalt_wet.tres`, `curb.tres`, `brick_red.tres`, `brick_brown.tres`,
`plaster.tres`, `concrete.tres`, `awning_canvas.tres` (optional; code generates striped canvas).

## 5. Audio — `res://assets/audio/`

`.ogg` (preferred) or `.wav`. Loops must be seamless and named `*_loop`.

`rain_light_loop`, `rain_heavy_loop`, `rain_on_umbrella_loop`, `rain_on_awning_loop`, `gutter_loop`,
`wind_loop`, `traffic_distant_loop`, `footstep_wet_1..4`, `footstep_run_1..4`, `puddle_splash`,
`car_pass`, `car_splash`, `umbrella_open`, `umbrella_close`, `umbrella_drop`, `ui_move`,
`ui_confirm`, `ui_back`, `ui_denied`, `fail_sting`, `win_sting`, `token`, `door_open`,
`music_menu_loop`, `music_level_loop`, `phone_ring`, `train_pass` (a monorail train passing
overhead, its nose passing 2.4 s in).

## 6. Awning lots — `levels/*.json`

A lot with `"cover": "awning"` shelters `z ∈ [0, 2.35]` across its width, minus any `tears`
(local `[x0, x1]` gaps). Every style keeps that footprint, mounts at or below y = 3.05 (under the
sign band) and has its front edge between 2.5 and 2.8 m, so the style is purely visual.

- `awning_color` (optional, default `red`): `red`, `green`, `blue`, `brown`, `orange`, `teal`.
- `awning_style` (optional): one of the styles below. When absent, the builder picks one from the
  styles allowed for the lot's era and the level's `aesthetic`. It deals them like a shuffle bag
  (least-used first, ties broken by a hash of level id and lot x), and never gives two touching
  awning lots the same style. An unknown name logs a warning and falls back to the automatic pick.

| style | look | auto-picked for |
|---|---|---|
| `classic` | narrow stripes, scalloped valance, black arms | 60s lots on `rundown`, `rundown_neon`, `neon` |
| `wide_stripe` | broad stripes, straight solid valance with piping | 60s lots on `rundown`, `rundown_neon`, `neon`, `outskirts` |
| `pennant` | solid canvas, deep zigzag valance with piping | 60s lots, any street |
| `dome` | rounded quarter-barrel with rib seams, hem band, closed ends | 60s lots, any street |
| `waterfall` | near-flat top, upright striped front, closed ends | 60s lots on `rundown`, `rundown_neon`, `industrial`, `outskirts` |
| `tin` | corrugated rusty metal, knee braces, gutter | 60s lots on `industrial`, `outskirts` |
| `bubble` | tinted acrylic canopy, chrome ribs, neon edge strip | retro-future lots |
| `googie` | upturned enamel slab, chrome edge, neon strip | retro-future lots |
| `marquee` | flat slab with a deep fascia of lit bulbs | retro-future lots |

A lot is retro-future when the builder swaps in the retro kit for it (probability = the level's
`neon`).

## 7. Credits

Every third-party asset gets a line in `assets/CREDITS.md`: file(s), author, source URL, licence.
CC0 preferred; CC-BY allowed with attribution. Nothing with NC/ND or unclear licences.
