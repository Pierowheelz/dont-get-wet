#!/usr/bin/env bash
# Visual cost of switching features off: one paused frame, as-is twice (noise floor) and with them off.
#   tools/ab_shot.sh OUT_DIR LEVEL "msaa scale75 msaa,fxaa" [-- extra game args, e.g. --start-x=40]
cd "$(dirname "$0")/.."
out="$1"; level="$2"; configs="$3"; shift 3; [ "$1" = "--" ] && shift
for c in $configs; do
	d="$out/$level-$c"; mkdir -p "$d"
	timeout 120 godot --path . --resolution "${RES:-1920x1080}" res://src/level/level.tscn -- \
		--autopilot --level="$level" --perf-ab="$d" --profile=x --perf-off="$c" "$@" >"$d/log.txt" 2>&1
	python3 - "$d" "$c" <<'PY'
import sys, numpy as np
from PIL import Image
d, c = sys.argv[1], sys.argv[2]
im = {k: np.asarray(Image.open(f"{d}/{k}.png").convert("RGB"), dtype=np.float32) for k in ("a0", "a1", "b")}
def psnr(x, y):
    mse = ((x - y) ** 2).mean()
    return 10 * np.log10(255 ** 2 / mse) if mse > 0 else float("inf")
def changed(x, y): return 100 * (np.abs(x - y).max(2) > 8).mean()
print(f"{c:22} noise {psnr(im['a0'], im['a1']):5.1f} dB  vs-off {psnr(im['a0'], im['b']):5.1f} dB  px>8: {changed(im['a0'], im['b']):5.2f}%  (noise {changed(im['a0'], im['a1']):.2f}%)")
PY
done
