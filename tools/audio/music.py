"""Two sparse noir-jazz loops: music_menu_loop (D minor, 66 BPM) and music_level_loop (C minor, 70 BPM).

Notes are placed on a circular timeline (tails of the last bar ring into the first) and reverb is a
circular convolution, so the loops wrap sample-exactly.
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, add_at, cconv, cfilt, mag_bp, make_ir, nsamp, pan, periodic_freq, rng, tax)
from instruments import (brush_swish, brush_tap, feather_kick, mtof, n2m, pad, rhodes,
                         upright_bass, vibes)

SWING = 2 / 3  # swung eighth position within a beat


class Score:
    def __init__(self, bpm, bars, seed):
        self.spb = 60.0 / bpm
        self.bars = bars
        self.n = nsamp(bars * 4 * self.spb)
        self.r = rng(seed)
        self.tracks = {}

    def at(self, bar, beat):
        return (bar * 4 + beat) * self.spb

    def add(self, track, bar, beat, sig, gain=1.0, p=0.0, jitter=0.008):
        buf = self.tracks.setdefault(track, np.zeros((2, self.n)))
        t = self.at(bar, beat) + self.r.normal(0, jitter)
        add_at(buf, pan(sig * gain, p), nsamp(t))

    def vel(self, v, spread=0.08):
        return float(np.clip(v + self.r.normal(0, spread), 0.05, 1.0))


def S(names):
    return [mtof(n2m(x)) for x in names.split()]


def comp(sc, bar, beat, voicing, dur_beats, v, roll=0.018, track="rhodes", p=0.0):
    for i, f in enumerate(voicing):
        sig = rhodes(f, dur_beats * sc.spb, sc.vel(v, 0.05), r=sc.r, bright=1.15)
        sc.add(track, bar, beat + i * roll / sc.spb, sig, 1.0, p + 0.12 * (i - len(voicing) / 2) / 2,
               jitter=0.006)


def bassnote(sc, bar, beat, name, dur_beats, v=0.8):
    sig = upright_bass(mtof(n2m(name)), dur_beats * sc.spb * 0.95, sc.vel(v, 0.06), r=sc.r)
    sc.add("bass", bar, beat, sig, 1.0, 0.0, jitter=0.006)


def brushes(sc, bar, v=1.0, taps=True, ghost=False, kick=True):
    for b in range(4):
        sw = brush_swish(sc.spb * 1.05, sc.vel(0.2 * v, 0.03), sc.r)
        sc.add("drums", bar, b, sw, 1.0, 0.25 if b % 2 else 0.15, jitter=0.01)
        if taps and b % 2 == 1:
            sc.add("drums", bar, b, brush_tap(sc.vel(0.22 * v, 0.03), sc.r), 1.0, 0.2)
        if kick and b % 2 == 0:
            sc.add("drums", bar, b, feather_kick(0.22 * v), 1.0, 0.0)
    if ghost:
        sc.add("drums", bar, 3 + SWING, brush_tap(sc.vel(0.08 * v, 0.02), sc.r), 1.0, 0.25)


def melody(sc, notes, inst="vibes", v=0.55, p=-0.2):
    for bar, beat, name, dur in notes:
        f = mtof(n2m(name))
        if inst == "vibes":
            sig = vibes(f, dur * sc.spb, sc.vel(v, 0.05), trem_hz=3.6, trem_depth=0.2)
        else:
            sig = rhodes(f, dur * sc.spb, sc.vel(v, 0.05), r=sc.r, bright=1.2)
        sc.add("melody", bar, beat, sig, 1.0, p, jitter=0.01)


def mixdown(sc, gains, sends, t60=2.6, trem=(2.4, 0.18), seed=77):
    r = rng(seed)
    ir = make_ir(r, t60=t60, pre_ms=22, hf_ratio=0.4, density_ms=35)
    n = sc.n
    dry = np.zeros((2, n))
    send = np.zeros((2, n))
    for name, buf in sc.tracks.items():
        x = buf * gains.get(name, 1.0)
        if name == "rhodes" and trem:
            f = periodic_freq(trem[0], n)
            ph = 2 * np.pi * f * tax(n)
            x = x * np.vstack([1 - trem[1] * (0.5 + 0.5 * np.sin(ph)),
                               1 - trem[1] * (0.5 - 0.5 * np.sin(ph))])
        dry += x
        send += x * sends.get(name, 0.2)
    wet = cconv(send, ir)
    out = dry + wet
    out = cfilt(out, lambda f: mag_bp(f, 32, 9500, 2))
    pk = np.abs(out).max()
    out = np.tanh(1.3 * out / pk * 0.8) / np.tanh(1.3 * 0.8)  # a touch of tape warmth
    return out


# --------------------------------------------------------------------------- menu

def menu():
    sc = Score(66, 16, 4242)
    chords = [  # (voicing, [(beat, bass, dur)])
        ("F3 A3 C4 E4", [(0, "D2", 2), (2, "A1", 2)]),                    # Dm9
        ("A3 D4 E4", [(0, "Bb1", 2), (2, "F2", 1.5), (3 + SWING, "Ab1", 0.33)]),  # Bbmaj7#11
        ("Bb3 D4 F4 A4", [(0, "G1", 2), (2, "D2", 2)]),                   # Gm9
        ("G3 C#4 F4 Bb4", [(0, "A1", 2), (2, "E2", 1.5), (3 + SWING, "C#2", 0.33)]),  # A7b9b13
        ("C4 E4 F4 A4", [(0, "D2", 2), (2, "C2", 2)]),                    # Dm9
        ("Bb3 D4 G4 A4", [(0, "Eb2", 2), (2, "Bb1", 2)]),                 # Ebmaj7#11
        (None, [(0, "E2", 2), (2, "A1", 2)]),                             # Em7b5 | A7b9
        ("E4 F4 A4 C5", [(0, "D2", 2), (2, "A1", 1.5), (3 + SWING, "C#2", 0.33)]),  # Dm9
    ]
    for half in range(2):
        for i, (voi, bass) in enumerate(chords):
            bar = half * 8 + i
            last = half == 1 and i == 7
            if i == 6:
                comp(sc, bar, 0, S("D4 G4 Bb4"), 1.8, 0.42)
                comp(sc, bar, 2, S("C#4 G4 Bb4"), 1.8, 0.4)
            elif last:  # turnaround: A7sus4 -> A7b9
                comp(sc, bar, 0, S("G3 C4 D4 E4"), 1.8, 0.42)
                comp(sc, bar, 2, S("G3 C#4 F4 Bb4"), 1.9, 0.4)
            else:
                pattern = (bar * 7 + half) % 3
                if pattern == 0:
                    comp(sc, bar, 0, S(voi), 3.5, 0.45)
                elif pattern == 1:
                    comp(sc, bar, 0, S(voi), 1.6, 0.45)
                    comp(sc, bar, 2 + SWING, S(voi), 1.2, 0.3)
                else:
                    comp(sc, bar, -1 + SWING, S(voi), 3.2, 0.42)
            if last:
                bass = [(0, "A1", 2), (2, "A1", 1.5), (3 + SWING, "C#2", 0.33)]
            for beat, nn, d in bass:
                bassnote(sc, bar, beat, nn, d, 0.85 if beat == 0 else 0.7)
            brushes(sc, bar, 1.0 if bar >= 1 else 0.7, taps=bar >= 1, ghost=(bar % 4 == 3))

    melody(sc, [
        (1, 2, "E5", 2),
        (2, 0, "D5", 1.5), (2, 1 + SWING, "C5", 0.33), (2, 2, "Bb4", 2),
        (3, SWING, "C#5", 1.2), (3, 2, "Bb4", 1), (3, 3, "A4", 1),
        (4, 0, "A4", 3),
        (5, 1, "G4", 1), (5, 2, "A4", 2),
        (6, 0, "Bb4", 1.5), (6, 2, "G4", 1), (6, 3, "F4", 1),
        (7, 0, "E4", 3),
        (9, SWING, "A5", 1.3), (9, 2, "E5", 2),
        (10, 0, "F5", 1), (10, 1, "D5", 1), (10, 2, "Bb4", 2),
        (11, 0, "C#5", 2), (11, 2 + SWING, "E5", 1.2),
        (12, 0, "D5", 2), (12, 2, "C5", 1), (12, 3, "A4", 1),
        (13, 0, "Bb4", 2), (13, 2, "D5", 2),
        (14, 0, "D5", 1), (14, 1, "Bb4", 1), (14, 2, "C#5", 2),
        (15, 0, "D5", 2), (15, 2, "C#5", 2),
    ], inst="vibes", v=0.5)

    return mixdown(sc, gains=dict(rhodes=0.9, bass=0.8, drums=0.75, melody=0.55),
                   sends=dict(rhodes=0.35, bass=0.1, drums=0.3, melody=0.5))


# --------------------------------------------------------------------------- level

def level():
    sc = Score(70, 24, 777)
    prog = [  # 2-bar chords: (voicing, root, fifth/other, approach-to-next or None)
        ("Eb3 G3 Bb3 D4", "C2", "G1", "B1"),          # Cm9
        ("G3 C4 D4 Eb4", "Ab1", "Eb2", "Gb1"),         # Abmaj7#11
        ("Ab3 C4 Eb4 G4", "F1", "C2", "F#1"),          # Fm9
        ("F3 B3 Eb4 Ab4", "G1", "D2", "Db2"),          # G7b9b13
        ("G3 Bb3 D4 Eb4", "C2", "G1", "C2"),           # Cm9
        ("F3 Ab3 C4 Eb4", "Db2", "Ab1", "E1"),         # Dbmaj9
        ("Ab3 C4 Eb4 G4", "F1", "C2", "F#1"),          # Fm9
        ("F3 B3 Eb4 Ab4", "G1", "D2", "D2"),           # G7b9b13
        ("Bb3 D4 F4 G4", "Eb2", "Bb1", "A1"),          # Ebmaj9
        ("G3 C4 D4 Eb4", "Ab1", "Eb2", "Eb2"),         # Abmaj7#11
        ("C4 F4 Ab4", "D2", "Ab1", "Ab1"),             # Dm7b5
        ("F3 B3 Eb4 Ab4", "G1", "D2", "B1"),           # G7b9b13 -> Cm9
    ]
    for i, (voi, root, other, appr) in enumerate(prog):
        bar = 2 * i
        section_b = i >= 8
        v = 0.4 if not section_b else 0.34
        if i % 2 == 0:
            comp(sc, bar, 0, S(voi), 6.5, v)
            comp(sc, bar + 1, 2 + SWING, S(voi), 1.2, v * 0.6)
        else:
            # broken chord, unhurried
            for k, f in enumerate(S(voi)):
                sig = rhodes(f, (6 - k * SWING) * sc.spb, sc.vel(v * 0.9, 0.05), r=sc.r)
                sc.add("rhodes", bar, k * SWING, sig, 1.0, -0.15 + 0.1 * k, jitter=0.01)
            comp(sc, bar + 1, 2, S(voi), 1.8, v * 0.55)
        bassnote(sc, bar, 0, root, 2, 0.85)
        bassnote(sc, bar, 2, other, 2, 0.7)
        bassnote(sc, bar + 1, 0, root, 2.5 if section_b else 2, 0.75)
        if not section_b:
            bassnote(sc, bar + 1, 2, other, 1, 0.65)
        bassnote(sc, bar + 1, 3, appr, 1, 0.6)
        for b in (bar, bar + 1):
            brushes(sc, b, 0.8 if not section_b else 0.55, taps=not section_b,
                    ghost=(b % 4 == 3 and not section_b), kick=True)
        if section_b:
            sc.add("pad", bar, 0, pad(S(voi), 2 * 4 * sc.spb, 0.5, sc.r, attack=2.0, rel=2.5), 1.0, 0.0)

    melody(sc, [
        (4, 0, "C5", 2), (4, 2 + SWING, "Eb5", 1.3),
        (5, 0, "C5", 1), (5, 1, "Ab4", 3),
        (6, 0, "F4", 2), (6, 2, "G4", 2),
        (7, 0, "Ab4", 2), (7, 2, "B4", 2),
        (8, 0, "C5", 4),
        (10, 0, "F5", 2), (10, 2, "Eb5", 1), (10, 3, "C5", 1),
        (11, 0, "Ab4", 4),
        (12, SWING, "G4", 1.3), (12, 2, "Ab4", 1), (12, 3, "C5", 1),
        (13, 0, "Eb5", 3),
        (14, 0, "D5", 2), (14, 2, "B4", 2),
        (15, 0, "Ab4", 2), (15, 2, "G4", 2),
    ], inst="rhodes", v=0.42, p=-0.25)
    melody(sc, [
        (16, 0, "G5", 4),
        (18, 0, "G5", 2), (18, 2, "Eb5", 2),
        (20, 0, "F5", 2), (20, 2, "C5", 2),
        (22, 0, "B4", 2), (22, 2, "D5", 2),
    ], inst="vibes", v=0.42, p=0.2)

    return mixdown(sc, gains=dict(rhodes=0.85, bass=0.72, drums=0.6, melody=0.5, pad=0.22),
                   sends=dict(rhodes=0.35, bass=0.1, drums=0.3, melody=0.45, pad=0.6),
                   t60=2.8)


TRACKS = {
    "music_menu_loop": menu,
    "music_level_loop": level,
}
