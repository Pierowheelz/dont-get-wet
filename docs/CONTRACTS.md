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
func set_wetness(w: float) -> void                             # 0..1, darken clothes, flatten hair, etc.
func set_mood(mood: StringName) -> void                        # &"normal" or &"sad" (defeated walk)
func get_grip(hand: StringName) -> Node3D                      # &"right" (raised, open) / &"left" (carried, closed)
```

- Feet at origin, facing **+X**, height ≈ 1.78 m. No root motion — the player script moves the root.
- `get_grip()` returns a Node3D that follows the hand bone. Its origin is in the palm; its local **+Y**
  points from the handle toward the canopy. For `&"right"` with `raise = 1, tilt = 0`, +Y is world-up
  and the grip is ~1.95–2.05 m above the feet. For `&"left"`, +Y points down toward the ground
  (umbrella carried closed like a cane / hanging).
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
`music_menu_loop`, `music_level_loop`.

## 6. Credits

Every third-party asset gets a line in `assets/CREDITS.md`: file(s), author, source URL, licence.
CC0 preferred; CC-BY allowed with attribution. Nothing with NC/ND or unclear licences.
