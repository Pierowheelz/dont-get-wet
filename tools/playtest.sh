#!/usr/bin/env bash
# Run the autopilot bot through every level (headless, fast) and print results.
#   tools/playtest.sh [level_id ...]
cd "$(dirname "$0")/.."
levels=("$@")
if [ ${#levels[@]} -eq 0 ]; then levels=(main_street canal_row arcade_lane neon_junction mill_road); fi
for l in "${levels[@]}"; do
  out=$(timeout 120 godot --headless --path . --fixed-fps 60 res://src/level/level.tscn -- --autopilot --level="$l" 2>&1)
  res=$(echo "$out" | grep -m1 -E "AUTOPILOT_(RESULT|DEFEATED)")
  errs=$(echo "$out" | grep -cE "SCRIPT ERROR|^ERROR")
  echo "$l: ${res:-NO RESULT} (errors: $errs)"
done
