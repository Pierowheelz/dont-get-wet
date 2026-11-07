<img src="assets/icon.svg" width="64" height="64" alt="">

# Don't Get Wet

A close-up 3D side-scroller in a city where it never stops raining. He walks on his own; you keep
him dry: open the umbrella under open sky, close it under cover to get your stamina back, hurry
across gaps, tilt into the wind, and shield yourself from passing cars.

Built with **Godot 4.7** (GDScript, Forward+). Design: [`docs/DESIGN.md`](docs/DESIGN.md).
Content interfaces: [`docs/CONTRACTS.md`](docs/CONTRACTS.md). Asset credits: [`assets/CREDITS.md`](assets/CREDITS.md).

## Running

```sh
godot --path .                 # play (opens the main menu)
godot --path . --editor        # open in the editor
```

## Controls

| Action | Gamepad | Keyboard / mouse | Touch |
|---|---|---|---|
| Umbrella (hold; partial press = partly open) | RT | Right mouse / Space | Right pad |
| Hurry (full = run) | LT | Shift (W = brisk walk) | Left pad |
| Stop for breath (only at ≤25% stamina) | LB | S / Ctrl | Stop button |
| Tilt umbrella forward / back | Right stick | E / Q, mouse wheel | Drag on right pad |
| Pause / restart | Start / Back | Esc / R | — |

## Developer tools

```sh
python3 tools/level_gen.py                   # regenerate first-draft level layouts into levels/*.json
tools/playtest.sh [--human] [level ...]      # autopilot bot plays levels headless, prints score & wetness sources
godot --headless --path . res://tests/run_tests.tscn   # rain-exposure / umbrella / splash tests
tools/shots.sh OUT_DIR "1,3,5" res://src/level/level.tscn --autopilot --level=main_street --start-x=40
python3 tools/grid.py sheet.png OUT_DIR/shot_*.png      # contact sheet of screenshots
```

Debug game args (after `--`): `--level=ID`, `--autopilot`, `--human`, `--lazy` (never opens the
umbrella), `--start-x=M`, `--wet=N`, `--fps-log`, `--shots=t1,t2 --shot-dir=DIR`.

Gameplay numbers live in [`data/tunables.json`](data/tunables.json).

## Layout

```
src/core     autoloads: Tun (tunables), Inputs, Game (progression, save, scene flow)
src/player   walker controller, umbrella, placeholder character
src/level    level runner, street builder, features, traffic
src/hazards  side-street cars
src/fx       rain particles, painterly post filter, shaders
src/audio    level soundscape
src/ui       HUD, menus, city map, touch controls
levels/      fixed level layouts (JSON) + map graph (index.json)
assets/      character, building kit, props, materials, audio, fonts (see CREDITS.md)
tools/       level generator, Blender kit generators, audio generators, test tooling
```
