#!/usr/bin/env python3
"""Check every audio file required by docs/CONTRACTS.md §5.

    python3 tools/audio/verify.py

Reports duration, channels, peak, loudness and, for *_loop files, a click check at the seam (the
largest 2nd difference across the wrap vs the file's 99.9th percentile) plus RMS just before/after
the loop point (informational: music legitimately has a downbeat at the start).  Exit status 1 if anything is missing, clipping or clicky.
"""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dsp  # noqa: E402

AUDIO = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "audio"))

REQUIRED = (["rain_light_loop", "rain_heavy_loop", "rain_on_umbrella_loop", "rain_on_awning_loop",
             "gutter_loop", "wind_loop", "traffic_distant_loop"]
            + [f"footstep_wet_{i}" for i in range(1, 5)] + [f"footstep_run_{i}" for i in range(1, 5)]
            + ["puddle_splash", "car_pass", "car_splash", "umbrella_open", "umbrella_close",
               "umbrella_drop", "ui_move", "ui_confirm", "ui_back", "ui_denied", "fail_sting",
               "win_sting", "token", "door_open", "music_menu_loop", "music_level_loop"])


def seam(x):
    """Click detector at the wrap point. Returns (ratio, rms dB before, rms dB after) where
    ratio = largest 2nd-difference within +-2 ms of the seam / the file's 99.9th percentile
    2nd-difference (a click shows up as a spike > 1)."""
    m = x.mean(axis=0)
    w = dsp.nsamp(0.002)
    joined = np.concatenate([m[-w - 2:], m[: w + 2]])
    d2_seam = np.abs(np.diff(joined, 2)).max()
    d2_all = np.percentile(np.abs(np.diff(m, 2)), 99.9) + 1e-9
    v = dsp.nsamp(0.05)
    a = dsp.db(np.sqrt(np.mean(m[-v:] ** 2)))
    b = dsp.db(np.sqrt(np.mean(m[:v] ** 2)))
    return d2_seam / d2_all, a, b


def main():
    bad = []
    total = 0
    print(f"{'file':24s} {'ch':>2s} {'dur':>7s} {'peak':>7s} {'LUFS':>6s}  seam(click ratio, rms 50ms before/after)")
    for name in REQUIRED:
        path = os.path.join(AUDIO, name + ".ogg")
        if not os.path.exists(path):
            print(f"{name:24s} MISSING")
            bad.append(name)
            continue
        total += os.path.getsize(path)
        x = dsp.read_audio(path)
        pk = dsp.peak_db(x)
        lu = dsp.lufs(x)
        line = f"{name:24s} {x.shape[0]:2d} {x.shape[1] / dsp.SR:6.2f}s {pk:6.1f}  {lu:6.1f}"
        problems = []
        if pk > -0.3:
            problems.append("near clipping")
        if name.endswith("_loop"):
            ratio, a, b = seam(x)
            line += f"  {ratio:5.2f}  {a:6.1f}/{b:6.1f} dB"
            if ratio > 1.0:
                problems.append("seam")
            if x.shape[0] != 2:
                problems.append("loop not stereo")
            d = x.shape[1] / dsp.SR
            if d < 20 or (d > 60 and not name.startswith("music")):
                problems.append("loop length")
        elif x.shape[0] != 1:
            problems.append("sfx not mono")
        if problems:
            bad.append(name)
            line += "   <-- " + ", ".join(problems)
        print(line)
    print(f"total size: {total / 1e6:.1f} MB")
    if bad:
        print("PROBLEMS:", ", ".join(bad))
        return 1
    print("all OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
