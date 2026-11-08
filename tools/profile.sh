#!/usr/bin/env bash
# Frame-time profile of a level on autopilot, one run per config; each config switches features off.
#   tools/profile.sh OUT_DIR LEVEL "base ssr vfog ssr,ssao" [-- extra game args, e.g. --low]
# A config is "base" or a comma list for --perf-off (see src/core/perf_probe.gd).
cd "$(dirname "$0")/.."
out="$1"; level="$2"; configs="$3"; shift 3; [ "$1" = "--" ] && shift
mkdir -p "$out"
for c in $configs; do
	offarg=(); [[ $c != base* ]] && offarg=(--perf-off="$c")
	timeout "${TIMEOUT:-120}" godot ${GPU_PROFILE:+--gpu-profile} --path . --resolution "${RES:-1920x1080}" res://src/level/level.tscn -- \
		--autopilot --level="$level" --profile="$out/$level-$c.json" --perf-secs="${SECS:-12}" "${offarg[@]}" "$@" \
		>"$out/$level-$c.log" 2>&1
	grep -E "SCRIPT ERROR|^ERROR" "$out/$level-$c.log" | grep -v "resources still in use" | head -3
done
python3 - "$out" "$level" $configs <<'PY'
import json, sys
out, level, cfgs = sys.argv[1], sys.argv[2], sys.argv[3:]
rows = []
for c in cfgs:
    try: rows.append((c, json.load(open(f"{out}/{level}-{c}.json"))))
    except Exception as e: print(c, "FAILED", e)
base = dict(rows).get("base")
print(f"{'config':24} {'gpu p50':>8} {'gpu p95':>8} {'cpu p50':>8} {'wall p50':>9} {'wall %':>7} {'d gpu':>7} frames")
for c, r in rows:
    g, w = r["gpu_ms"]["p50"], r["frame_ms"]["p50"]
    dg = g - base["gpu_ms"]["p50"] if base else 0
    pct = 100 * (w / base["frame_ms"]["p50"] - 1) if base else 0
    print(f"{c:24} {g:8.2f} {r['gpu_ms']['p95']:8.2f} {r['cpu_ms']['p50']:8.2f} {w:9.2f} {pct:6.1f}% {dg:7.2f} {r['frames']}")
PY
