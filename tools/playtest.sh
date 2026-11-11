#!/usr/bin/env bash
# Run the autopilot bot through every level (headless, fast) and print results.
#   tools/playtest.sh [level_id ...]
cd "$(dirname "$0")/.."
extra=()
levels=()
for a in "$@"; do if [[ $a == --* ]]; then extra+=("$a"); else levels+=("$a"); fi; done
if [ ${#levels[@]} -eq 0 ]; then levels=(main_street canal_row arcade_lane neon_junction mill_road kiln_street telstar_parade); fi
for l in "${levels[@]}"; do
  out=$(timeout 120 godot --headless --path . --fixed-fps 60 res://src/level/level.tscn -- --autopilot --level="$l" "${extra[@]}" 2>&1)
  res=$(echo "$out" | grep -m1 -E "AUTOPILOT_(RESULT|DEFEATED)")
  errs=$(echo "$out" | grep -E "SCRIPT ERROR|^ERROR" | grep -vc "resources still in use")
  echo "$l: ${res:-NO RESULT} (errors: $errs)"
done
