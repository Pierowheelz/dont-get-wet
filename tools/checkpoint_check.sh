#!/usr/bin/env bash
# Proves in the real game that every checkpoint is dry: start the walker on each checkpoint with the
# umbrella never opened (--lazy) and fail if he gets any wetter before CLEAR_M metres further on.
#   tools/checkpoint_check.sh [level_id ...]      (default: every level with checkpoints)
# Exits 1 on any failure.
set -u
cd "$(dirname "$0")/.."
levels=("$@")
if [ ${#levels[@]} -eq 0 ]; then levels=(main_street arcade_lane neon_junction canal_row mill_road); fi
out=$(mktemp -d)
clear_m=$(python3 -c "import sys; sys.path.insert(0, 'tools'); import level_preview; print(level_preview.CLEAR_M)")

run() { # level index x
  timeout 120 godot --headless --path . --fixed-fps 60 res://src/level/level.tscn -- \
    --autopilot --lazy --level="$1" --start-x="$3" --trace="$out/$1_$2.jsonl" >/dev/null 2>&1
}

for l in "${levels[@]}"; do
  i=0
  for x in $(python3 -c "import json; print(*json.load(open('levels/$l.json'))['checkpoints'])"); do
    i=$((i + 1))
    run "$l" "$i" "$x" &
  done
done
wait

rc=0
for l in "${levels[@]}"; do
  i=0
  for x in $(python3 -c "import json; print(*json.load(open('levels/$l.json'))['checkpoints'])"); do
    i=$((i + 1))
    msg=$(python3 - "$out/${l}_$i.jsonl" "$x" "$clear_m" <<'EOF'
import json, sys
path, cp, clear = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
rows = [json.loads(r) for r in open(path) if r.startswith("{")]
dry = [r for r in rows if r["x"] < cp + clear]
wet = [r for r in dry if r["wet"] > 0.0]
reach = max(r["x"] for r in rows)
first = next((r["x"] for r in rows if r["wet"] > 0.0), None)
if reach < cp + clear:
    print("FAIL walker stopped at x=%.2f before the %.1f m window ended" % (reach, clear)); sys.exit(1)
if wet:
    print("FAIL wet %.2f at x=%.2f, %.2f m after the checkpoint" % (wet[0]["wet"], wet[0]["x"], wet[0]["x"] - cp)); sys.exit(1)
print("ok   first wet at x=%s (%s m past the checkpoint)" % ("%.2f" % first if first else "never", "%.2f" % (first - cp) if first else "-"))
EOF
)
    echo "$l cp$i x=$x: $msg"
    case "$msg" in FAIL*) rc=1 ;; esac
  done
done
rm -rf "$out"
exit $rc
