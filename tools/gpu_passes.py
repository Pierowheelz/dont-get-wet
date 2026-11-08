#!/usr/bin/env python3
"""Average Godot --gpu-profile blocks per log into a pass x config table (ms).
   tools/gpu_passes.py OUT_DIR LEVEL cfg1 cfg2 ..."""
import re, sys
out, level, cfgs = sys.argv[1], sys.argv[2], sys.argv[3:]
tables, order = {}, []
for c in cfgs:
    blocks, cur = [], None
    for line in open(f"{out}/{level}-{c}.log", errors="replace"):
        if line.startswith("GPU PROFILE"):
            cur = {"TOTAL": float(re.search(r"total ([\d.]+)ms", line).group(1))}
            blocks.append(cur)
        elif cur is not None and (m := re.match(r"\s+-(.+): ([\d.e-]+)ms", line)):
            cur[m.group(1)] = cur.get(m.group(1), 0.0) + float(m.group(2))
            if m.group(1) not in order: order.append(m.group(1))
    blocks = blocks[len(blocks) // 2:]   # sampling window: skip load and warmup
    tables[c] = {k: sum(b.get(k, 0.0) for b in blocks) / max(len(blocks), 1) for k in order + ["TOTAL"]}
print(f"{'pass':40}" + "".join(f"{c[:11]:>12}" for c in cfgs))
for k in order + ["TOTAL"]:
    print(f"{k[:40]:40}" + "".join(f"{tables[c].get(k, 0):12.3f}" for c in cfgs))
