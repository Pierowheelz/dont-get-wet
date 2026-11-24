#!/usr/bin/env bash
# Runs tests/run_tests.tscn split across SHARDS parallel Godot processes (default 6), each on its
# own throwaway save, at --fixed-fps 60 so game time runs as fast as the CPU allows.
#   tools/test.sh            SHARDS=1 tools/test.sh   (one process, every check in file order)
# Prints each shard's log, then its FAIL lines and the overall result. Exits 1 on any failure.
set -u
cd "$(dirname "$0")/.."
n=${SHARDS:-6}
out=$(mktemp -d)
for ((i = 0; i < n; i++)); do
  timeout 600 godot --headless --fixed-fps 60 --path . res://tests/run_tests.tscn -- \
    --save="$out/save_$i.json" --shard="$i/$n" >"$out/$i.log" 2>&1 &
done
wait

rc=0
for ((i = 0; i < n; i++)); do cat "$out/$i.log"; done
echo
for ((i = 0; i < n; i++)); do
  result=$(grep -E '^(PASSED|FAILED)' "$out/$i.log" || echo "FAILED: no result (crashed?)")
  [[ $result == PASSED ]] || rc=1
  grep -E '^  FAIL |SCRIPT ERROR' "$out/$i.log"
  echo "shard $i/$n: $result"
done
echo "$(grep -hc '^  ok ' "$out"/*.log | paste -sd+ | bc) ok, logs in $out"
echo "$([ $rc -eq 0 ] && echo PASSED || echo FAILED)"
exit $rc
