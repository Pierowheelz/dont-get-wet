#!/usr/bin/env bash
# Render screenshots of a scene at given times (seconds).
#   tools/shots.sh OUT_DIR "1,3,5" [scene] [-- extra game args]
cd "$(dirname "$0")/.."
out="$1"; times="$2"; scene="${3:-res://src/level/level.tscn}"; shift 3 2>/dev/null
mkdir -p "$out"; rm -f "$out"/shot_*.png
timeout 300 godot --path . --resolution 1920x1080 --fixed-fps 30 "$scene" -- --shots="$times" --shot-dir="$out" "$@" >"$out/log.txt" 2>&1
grep -E "SCRIPT ERROR|^ERROR" "$out/log.txt" | grep -v "resources still in use" | head -5
ls "$out"/shot_*.png 2>/dev/null | wc -l
