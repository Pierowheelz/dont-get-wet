#!/usr/bin/env bash
# Rebuilds the walker's mocap locomotion clips (assets/characters/walker/anim/mocap/*.res) from the
# CMU BVH sources in assets/characters/walker/source/cmu/ (see assets/CREDITS.md).
#   tools/mocap/build_clips.sh
# Posture targets (mean forward lean in degrees of Hips,Spine,Chest,UpperChest,Neck,Head) keep the
# pelvis/lower spine neutral (no sway-back) and the face level; see retarget.py.
set -e
cd "$(dirname "$0")/../.."
SRC=assets/characters/walker/source/cmu
OUT=assets/characters/walker/anim/mocap
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
godot --headless --path . -s res://tools/mocap/dump_rest.gd -- res://assets/characters/walker/walker.tscn "$TMP/rest.json" >/dev/null 2>&1
clip() {  # name bvh mode args...
	local name=$1 bvh=$2 mode=$3; shift 3
	python3 -I tools/mocap/retarget.py "$SRC/$bvh.bvh" "$TMP/rest.json" "$TMP/$name.json" --mode "$mode" "$@"
	godot --headless --path . -s res://tools/mocap/build_anim.gd -- "$TMP/$name.json" "res://$OUT/$name.res" 2>&1 | grep saved
}
clip walk  35_01 walk --posture 0,3,3,3,6,12      # relaxed walk, 1.31 m/s
clip brisk 16_21 walk --posture 1,4,4,4,7,12      # brisk walk, 1.8 m/s
clip jog   16_35 walk --posture 2,5,5,5,6,10      # light jog, 3.0 m/s
clip idle  77_02 idle --posture 0,3,3,3,6,12 --idle-len 5
