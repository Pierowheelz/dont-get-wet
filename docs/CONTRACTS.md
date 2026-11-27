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
func set_stopped(stopped: bool) -> void                        # standing still, upright
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

Optional (the player calls it if the visual has it): `set_aim(amount: float)`, 0..1 the furled umbrella
shouldered and aimed along the pose's `tilt` while `raise` brings the arm up. Ahead and overhead the
crook sits at the shoulder with the other hand under the shaft; aimed behind, he twists toward the
camera, looks back and points it one-handed. The grip's +Y still runs along the shaft toward the tip.

Also optional: `set_winded(amount: float)`, 0..1 how out of breath he is (the player passes the share
of stamina spent). Stopped with the umbrella down he stands upright and breathes quietly at 0; toward
1 his chest and shoulders heave harder and faster and he gives a few degrees at the waist. Nothing
breathes while the umbrella is raised: the canopy's cover follows the hand.

- Feet at origin, facing **+X**, height ≈ 1.78 m. No root motion — the player script moves the root.
- `get_grip()` returns a Node3D that follows the hand bone. Its origin is in the palm; its local **+Y**
  points from the handle toward the canopy. For `&"right"` with `raise = 1, tilt = 0`, +Y is world-up
  and the grip is ~1.40–1.55 m above the feet, ~0.10–0.20 m in front of the chest (+X), elbow bent —
  the natural way people hold an umbrella. The umbrella shaft is 0.75 m, so the canopy apex sits at
  ~2.2 m. Tilt rotates the grip about the Z axis (+ tilts the canopy toward +X). For `&"left"`, +Y points down toward the ground
  (umbrella carried closed like a cane / hanging). With `umbrella_left` set before it enters the tree, the
  walker holds the open umbrella in his left fist instead, mirrored, and `&"right"` is that left-fist grip.
- The player script turns the root 180° about Y to walk left (defeat sequence).
- NPCs that can be soaked (`NpcBody`) use the same scene and methods: `set_wetness` darkens their
  suit as they get wet, and `set_mood(&"sad")` with the turn and walk left plays their defeat.

Physics layers (`project.godot`): 1 `world`, 2 `cover` (awnings, balconies, arches: the walker's rain
cover), 3 `player`, 4 `umbrella` (the walker's canopy), 5 `npc_umbrella` (soakable NPCs' canopies:
they stop droplets flown at those NPCs and never shelter the walker).

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
overhead, its nose passing 2.4 s in), `rotor_loop` (a turbine helicopter close overhead: three-bladed
rotor slap at 9 Hz, turbine whine, tail-rotor buzz; mono, the game places it on the helicopter).

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
| `rocket` | enamel slab with a chrome edge, a neon strip and a tail fin toward each end (one shared where two canopies meet): each fin runs from the wall to the front edge and stands only as tall as leaves its sign clear | never: name it |

A lot is retro-future when the builder swaps in the retro kit for it (probability = the level's
`neon`).

## 7. Skyways and the glass city — `levels/*.json`

A `skyways` entry `{"x0", "x1"}` is cover from x0 to x1: one box on the `cover` layer from y 4.45
(`SkywayBuilder.SOFFIT_Y`) to 7.6 (`ROOF_Y`) and z 0 to 3.3 (`Z1`), mirrored in the rain's cover map as
`COVER_VOLUME` (drops splash on the roof, vanish inside, and fall beneath the soffit). These numbers,
the columns' line (z 2.75, clear of an open canopy on the walker's line) and `column_xs` are gameplay;
everything `SkywayBuilder.draw` adds is visual and may be restyled, as long as nothing hangs below the
soffit in front of the columns' line. As drawn, the gallery's floor (`DECK_Y`) is 0.15 m above the
soffit and it has no back wall. Likewise every lot style in `ModernBuilder` and its skyline is
visual only (no collider, no cover): an art pass may replace any of it, keeping `glass_tower` and
`lobby` signs in the 3.1–3.9 m band and the `plaza` open.

## 8. Credits

Every third-party asset gets a line in `assets/CREDITS.md`: file(s), author, source URL, licence.
CC0 preferred; CC-BY allowed with attribution. Nothing with NC/ND or unclear licences.

## 9. Helicopter model — `res://assets/vehicles/helicopter.tscn` (or `.glb`)

`helicopter.glb` is Skyway's shuttle, generated by `tools/blender/vehicles.py` (a boat-hulled
twin-turbine with a glazed nose, SKYWAY on both flanks). Without a model `src/hazards/helicopter.gd`
builds a stand-in in code. A scene whose root is a `Node3D` with these conventions replaces it (the
game duplicates it for each flight):

- Origin at the **main rotor hub**. Local **+X = the nose**, +Y up, 1 unit = 1 m. Rotor radius about
  4 m, nose to tail about 11 m; the fuselage hangs about 1 to 3 m below the hub (the game flies the
  hub at least 11 m up, so that clears a skyway's roof at 7.6 m). The game turns it
  180° about Y to fly right to left, so both flanks are seen; livery (SKYWAY) on both.
- Named nodes, each optional, found with `get_node_or_null` directly under the root:
  `Rotor` (the game sets its `rotation.y`, spinning it about local Y), `TailRotor` (spun about local
  Z: put the tail rotor's disc in the local XY plane), `SearchlightMount` (the searchlight's beam
  starts at its origin; the game aims the light itself), `BeaconTop` and `BeaconBelly` (shown only
  while the anti-collision light flashes) and an `OmniLight3D` named `Flash` (lit with them).
- Everything else (pitch, bob, the searchlight, spray, sound, camera) is the game's. Keep lights in
  the scene few and short-ranged; nav lights and lit windows are best as emissive materials.
- A `.glb` can't carry Godot lights or shader materials: `assets/vehicles/vehicle_import.gd` (set as
  the import script by `tools/blender/configure_imports.py`) swaps material names for
  `assets/materials/<name>.tres` like the kit's, and turns the empties `Flash`, `CockpitGlow` and
  `BellyLight` into lights. The blur of the turning blades is geometry inside `Rotor` and `TailRotor`
  drawn by `src/fx/rotor_blur.gdshader`, so it turns with them.

## 10. Country models — `res://assets/country/<name>.glb`

The country lane's hedgerow, trees, farm and furniture, and two suburban street trees, generated by `tools/blender/country.py`
(`blender -b -P tools/blender/country.py`, `-- --preview DIR` to render views, `--only a,b` for
some). The script fails if a model breaks a number in the table. `CountryBuilder` uses a model when
its file exists and its own stand-in otherwise; collision and rain cover stay in code.

- World conventions as above: +X the walker's way, +Y up, +Z toward the camera, the origin on the
  ground. **Lot pieces** (`hedge_4m`, `gate`, `dutch_barn`, `bus_shelter`, `lychgate`) have their
  origin at the lot's left end on the hedge line, like a kit module: they span `x ∈ [0, width]` and
  sit behind `z = 0` except where the table says they reach over the verge. **Trees and props** have
  their origin at the centre of their foot.
- **Paint is in the vertex colours.** No textures, no shared `.tres`: every material is white and
  `COLOR_0` (linear) carries the colour, the moss, rust and damp. `assets/country/country_import.gd`
  (set by `tools/blender/configure_imports.py`) turns on `vertex_color_use_as_albedo` for every
  material, which Godot's importer otherwise leaves off for the first surface of each mesh. A
  replacement material must read `COLOR.rgb` as its albedo or bring its own colour.
- **Materials** are named `country_<what>` (`country_bark`, `country_timber`, `country_tile`,
  `country_corrugated`, `country_hay` …; the table in `country.py` lists them with their roughness).
  The ones to sway have **"foliage" in the name**: `country_oak_foliage`, `country_plane_foliage`, `country_gum_foliage`,
  `country_hedge_foliage`, `country_grass_foliage`. They are double-sided and their leaves are single quads: draw them with
  culling off.
- **Nodes** directly under the scene root: `Trunk` and `Foliage` (the trees), `Foliage` (the hedge),
  `Body` (everything else's solid parts) and `Grass` (tufts at the foot of most props, a foliage
  material). On a foliage mesh `COLOR_0.a` is **how far that leaf may move: 0 held still, 1 free**
  (a tree: about 0.25 at the fork to 1 at the outermost leaves; the hedge: 0 at the ground to 1 at
  its top; grass: 0 at the root, 1 at the tip), so a wind shader can multiply its displacement by
  `COLOR.a` and needs nothing else. Foliage normals are smoothed over the whole crown.

| file | origin | footprint (m) | notes |
|---|---|---|---|
| `oak_a` | trunk base | crown x −4.8…5.2, z −3.1…3.85, top 10.7 | broad even head, six boughs. Trunk about 1.1 m through at chest height, roots flaring to 0.9 m from the centre. Nothing below **3.4 m** over z 0.6…3.6; behind the hedge line the leaves hang to about 2.4 m. 13.4k tris |
| `oak_b` | trunk base | crown x −4.4…5.1, z −3.1…3.85, top 11.7 | taller head, leans left, the stub of a lost bough at 2.2 m on its left. Same clearance. 13.3k tris |
| `street_tree_a` | trunk base | crown x −4.6…4.75, z −4.45…1.65, top 11.0 | a suburban street tree for the nature strip (a plane: clean bole 0.75 m through, bark shed in plates, dense dark head). It **stands at z ≈ 2.9**, so its head is set back over the footpath: world z −1.55…4.55. Nothing but the bole below **3.4 m** over world z 0.6…3.6 (z −2.3…0.7 from its foot). Material `country_plane_foliage`. 13.6k tris |
| `street_tree_b` | trunk base | crown x −4.35…4.75, z −4.45…1.65, top 10.9 | a gum: pale bole (`country_gum_bark`) forking at 4 m, smaller masses of long hanging grey-green leaves (`country_gum_foliage`). Stands at z ≈ 2.9 with the same clearance. 13.0k tris |
| `hedge_4m` | left end, hedge line | x 0…4 (sprays to −0.15…4.2), z −1.0…0.1, top 1.6–1.9 | tiles end to end along X: both ends have the same section. A cut end is a flat dark face; hide it against a post. 5.4k tris |
| `gate` | left end, hedge line | x 0…3.6, z −0.35…0.2, posts 1.56, top rail 1.25 | five-bar gate hung on the left post; the bars are see-through, so draw the field behind. 2.6k tris |
| `dutch_barn` | left end, hedge line | x 0…8 (roof −0.12…8.12), z −5.1…2.7, crown 6.4 | curved tin roof whose front edge is at **z 2.6**, eaves 4.45; tin on the back and on both ends from z −5 to −0.2; hay stacked from z −1 back. Three front posts 0.2 m square at **x 0.15, 4.0, 7.85, z 2.4**, with braces and the eaves beam (underside 4.38) in that plane. Nothing below **4.2 m** over z 0.3…2.25. Its earth floor stops at z 0.05. 13.2k tris |
| `bus_shelter` | left end, hedge line | x 0…4 (roof −0.18…4.18), z −0.4…2.5, ridge 3.6 | boarded back wall at z −0.1, brick wings to z 0.78 (1.37 m high), bench to z 0.5. Tiled roof from z −0.32 to **2.42**, front fascia underside **2.46**, plates underside 2.5. Two posts 0.13 m square at **x 0.1 and 3.9, z 2.2**, each with a brace toward the middle in that plane. Nothing below 2.45 m over z 0.9…2.1. A `BUS STOP` plate on the fascia. 9.8k tris |
| `lychgate` | left end, hedge line | x 0…4 (eaves −0.15…4.15), z −1.3…2.5, ridge 4.9, cross 5.6 | gable toward the lane, roof from z −1.32 to **2.4**. Posts 0.2 m square at **x 0.45 and 3.55**, at z −0.95, 0.0 and **2.15**; stone dwarf walls under them from z −1.2 to 0.22; gates to the churchyard at z −0.95. Wall plates underside **2.55**; nothing below 2.5 m over z 0.9…2.0. An empty named `Lamp` at (2.0, 2.4, 0.0) marks the lantern, whose glass (`country_lamp_glass`) glows: put a light there if wanted. 11.3k tris |
| `telegraph_pole` | foot centre | x −0.2…0.3, z −0.95…0.95, top 8.3 | two arms across the lane (along Z) on its +X side. Wires leave the insulators' tops at x 0.145: y 7.79, z ±0.36 and ±0.82; y 7.24, z ±0.26 and ±0.6. 3.0k tris |
| `hay_bales` | centre | x −1.35…1.2, z −0.75…1.0, top 0.84 | five loose bales. 3.2k tris |
| `milk_churn_stand` | centre of the stand | x −1.0…1.0, z −0.6…0.9, deck 0.86, churns to 1.66 | three churns on the stand, one on the ground at (0.62, 0.72). 6.8k tris |
| `milestone` | foot centre | x −0.4…0.35, z −0.2…0.3, top 0.79 | reads `TOWN 7 MILES` on its +Z face. 1.4k tris |
| `signpost` | foot centre | x −0.85…1.05, z −0.8…0.27, top 3.26 | fingerpost: `COUNTY ROAD 2` pointing +X at 2.66 m, `TOWN 7` pointing −X at 2.44 m, `CHURCH` pointing −Z at 2.22 m; the first two read from the lane. 4.8k tris |
