#!/usr/bin/env bash
# One command for a street: run the perfect and --human bots with traces, render the PNG, print the report.
#   tools/preview.sh LEVEL_ID [OUT_DIR]      (default OUT_DIR: build/preview)
# Writes OUT_DIR/LEVEL_ID/LEVEL_ID.png plus perfect.jsonl and human.jsonl traces. Exits 1 if a design rule fails.
set -u
cd "$(dirname "$0")/.."
level=${1:?usage: tools/preview.sh LEVEL_ID [OUT_DIR]}
out=${2:-build/preview}/$level
mkdir -p "$out"

run_bot() { # name [extra bot args]
  timeout 300 godot --headless --path . --fixed-fps 60 res://src/level/level.tscn -- \
    --autopilot --level="$level" --trace="$out/$1.jsonl" ${2:-} 2>&1 \
    | grep -m1 -E "AUTOPILOT_(RESULT|DEFEATED)" | cut -c1-220 > "$out/$1.result"
}
run_bot perfect &
run_bot human --human &
wait

python3 tools/level_preview.py "$level" --trace "$out/perfect.jsonl" --trace "$out/human.jsonl" -o "$out/$level.png" --report
rc=$?
for b in perfect human; do echo "$b bot: $(cat "$out/$b.result")"; done
exit $rc
