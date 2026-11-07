#!/usr/bin/env bash
# Renders a standard posture contact sheet of the walker (side walk cycle, umbrella hold, hurry,
# close-up, three-quarter, and an in-game frame) to OUT.png.   tools/posture_sheet.sh OUT.png
cd "$(dirname "$0")/.."
out="$1"; tmp="$(dirname "$out")/posture_tmp"; rm -rf "$tmp"; mkdir -p "$tmp/side" "$tmp/close" "$tmp/three" "$tmp/game"
T=res://assets/characters/walker/test/test.tscn
timeout 90 godot --path . --resolution 900x900 --fixed-fps 30 $T -- --shots=0.8,1.0,1.2,1.4,4.6,8.6,9.0 --shot-dir="$tmp/side" >/dev/null 2>&1
timeout 90 godot --path . --resolution 900x900 --fixed-fps 30 $T -- cam=close --shots=1.0,4.6 --shot-dir="$tmp/close" >/dev/null 2>&1
timeout 90 godot --path . --resolution 900x900 --fixed-fps 30 $T -- cam=three --shots=1.0,4.6 --shot-dir="$tmp/three" >/dev/null 2>&1
timeout 120 godot --path . --resolution 1920x1080 --fixed-fps 30 res://src/level/level.tscn -- --autopilot --level=main_street --start-x=36 --shots=1.5,3.5 --shot-dir="$tmp/game" >/dev/null 2>&1
python3 - "$tmp" "$out" <<'PY'
import sys
from PIL import Image, ImageDraw
tmp, out = sys.argv[1], sys.argv[2]
tiles = []
for i, lab in enumerate(["walk a", "walk b", "walk c", "walk d", "umbrella", "hurry a", "hurry b"]):
    im = Image.open(f"{tmp}/side/shot_{i:02d}.png"); w, h = im.size
    tiles.append((im.crop((int(w*.2), int(h*.15), int(w*.8), int(h*.9))), "side " + lab))
for i, lab in enumerate(["walk", "umbrella"]):
    tiles.append((Image.open(f"{tmp}/close/shot_{i:02d}.png"), "close " + lab))
for i, lab in enumerate(["walk", "umbrella"]):
    im = Image.open(f"{tmp}/three/shot_{i:02d}.png"); w, h = im.size
    tiles.append((im.crop((int(w*.1), 0, int(w*.9), h)), "3/4 " + lab))
for i in range(2):
    im = Image.open(f"{tmp}/game/shot_{i:02d}.png"); w, h = im.size
    tiles.append((im.crop((int(w*.12), int(h*.3), int(w*.52), int(h*.95))), "in game"))
TW, TH, cols = 360, 440, 5
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (TW*cols, TH*rows), (20, 20, 24))
d = ImageDraw.Draw(sheet)
for k, (im, lab) in enumerate(tiles):
    x, y = (k % cols)*TW, (k // cols)*TH
    im.thumbnail((TW, TH-20))
    sheet.paste(im, (x + (TW-im.width)//2, y + 20))
    d.text((x+6, y+4), lab, fill=(230, 220, 200))
sheet.save(out)
PY
echo "$out"
