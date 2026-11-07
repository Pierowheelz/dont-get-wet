#!/usr/bin/env python3
"""Regenerate every synthesised audio file in assets/audio/.

    python3 tools/audio/generate.py              # all files
    python3 tools/audio/generate.py rain_heavy_loop ui_move   # selected files
    python3 tools/audio/generate.py --list

All sounds are synthesised from fixed seeds, so output is reproducible (bit-exact for the same
numpy/scipy versions; Vorbis encoding may differ slightly across ffmpeg/libvorbis builds).
Requires numpy, scipy and ffmpeg (with libvorbis) on PATH.

Levels: one-shots are peak-normalised to -1 dBFS; ambience loops to -16 LUFS; music to -18 LUFS
(sits under the rain). Loops are built with circular DSP so they wrap sample-exactly.
"""
from __future__ import annotations

import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import ambience  # noqa: E402
import dsp  # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "audio"))

AMBIENCE_LUFS = -16.0
MUSIC_LUFS = -18.0
SFX_PEAK_DB = -1.0


def _registry():
    reg = {}
    for name, fn in ambience.LOOPS.items():
        reg[name] = ("loop", fn)
    try:
        import oneshots
        for name, fn in oneshots.SFX.items():
            reg[name] = ("sfx", fn)
    except ImportError:
        pass
    try:
        import music
        for name, fn in music.TRACKS.items():
            reg[name] = ("music", fn)
    except ImportError:
        pass
    return reg


def finish(kind, x):
    x = np.asarray(x, dtype=float)
    # remove any DC offset; for loops this is circularly safe
    x = x - x.mean(axis=-1, keepdims=True)
    if kind == "sfx":
        if x.ndim > 1:
            x = x.mean(axis=0)
        x = dsp.hp(x, 30.0, 2)  # no useful content below 30 Hz in any one-shot
        x = dsp.trim_tail(x, -60.0)
        x = dsp.fade(x, 0.0005, 0.02)
        return dsp.norm_peak(x, SFX_PEAK_DB), 4
    target = AMBIENCE_LUFS if kind == "loop" else MUSIC_LUFS
    return dsp.norm_loudness(x, target, ceil_db=-1.5), 5


def main(argv):
    reg = _registry()
    if "--list" in argv:
        print("\n".join(sorted(reg)))
        return 0
    names = [a for a in argv if not a.startswith("-")] or sorted(reg)
    unknown = [n for n in names if n not in reg]
    if unknown:
        print("unknown:", ", ".join(unknown))
        return 1
    for name in names:
        kind, fn = reg[name]
        t0 = time.time()
        x, q = finish(kind, fn())
        path = os.path.join(OUT, name + ".ogg")
        dsp.write_ogg(path, x, q)
        dur = x.shape[-1] / dsp.SR
        lvl = f"{dsp.lufs(x):6.1f} LUFS" if kind != "sfx" else f"{dsp.peak_db(x):6.1f} dBpk"
        print(f"{name:24s} {kind:5s} {dur:6.2f}s {lvl}  ({time.time() - t0:.1f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
