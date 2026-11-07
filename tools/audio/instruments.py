"""Small synthesised instrument set (Rhodes-ish EP, upright bass, brushes, vibes, pad)."""
from __future__ import annotations

import numpy as np

from dsp import SR, bp, env_ad, hp, lp, nsamp, resonator, tax


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def n2m(name: str) -> int:
    """'C#4' / 'Eb3' / 'A2' -> MIDI number."""
    base = NOTE[name[0].upper()]
    i = 1
    while i < len(name) and name[i] in "#b":
        base += 1 if name[i] == "#" else -1
        i += 1
    return base + 12 * (int(name[i:]) + 1)


def endfade(x, sec=0.06):
    m = min(len(x), nsamp(sec))
    x = x.copy()
    x[-m:] *= np.cos(np.linspace(0, np.pi / 2, m)) ** 2
    return x


def _release(t, dur, rel):
    e = np.ones_like(t)
    m = t > dur
    e[m] = np.exp(-(t[m] - dur) / rel)
    return e


def rhodes(f, dur, vel=0.7, rel=0.18, r=None, bright=1.0):
    """FM electric piano: 1:1 FM body with decaying index + inharmonic tine 'ding'."""
    decay = float(np.clip(2.4 * (220.0 / f) ** 0.5, 0.6, 5.0))
    length = min(dur, decay * 3.5) + rel * 6
    n = nsamp(length)
    t = tax(n)
    env = (1 - np.exp(-t / 0.0015)) * np.exp(-t / decay) * _release(t, dur, rel)
    idx = (0.25 + 1.6 * bright * vel ** 1.5) * np.exp(-t / 0.3) + 0.12
    w = 2 * np.pi * f * t
    body = np.sin(w + idx * np.sin(w))
    tine = np.sin(2 * np.pi * f * 7.03 * t) * np.exp(-t / 0.025) * 0.22 * vel * bright
    second = np.sin(2 * w) * np.exp(-t / (decay * 0.35)) * 0.12
    x = env * (body + second) + tine * (1 - np.exp(-t / 0.0007))
    x = lp(x, 7000, 2)
    return endfade(x) * vel


def upright_bass(f, dur, vel=0.7, r=None, rel=0.08):
    """Additive plucked upright bass with a woody attack thump."""
    r = r or np.random.default_rng(int(f * 100))
    tau0 = 1.5 * (55.0 / f) ** 0.25
    n = nsamp(min(dur, tau0 * 3) + rel * 6 + 0.05)
    t = tax(n)
    glide = 1 + 0.008 * np.exp(-t / 0.035)
    x = np.zeros(n)
    B = 1.5e-4
    for k in range(1, 30):
        fk = k * f * np.sqrt(1 + B * k * k)
        if fk > 3500:
            break
        a = abs(np.sin(k * np.pi * 0.22)) / k ** 0.9
        tk = tau0 / (1 + 0.35 * (k - 1) ** 1.3)
        ph = 2 * np.pi * np.cumsum(fk * glide) / SR + r.uniform(0, 6.28)
        x += a * np.sin(ph) * np.exp(-t / tk)
    x *= (1 - np.exp(-t / 0.002)) * _release(t, dur, rel)
    thump = lp(r.standard_normal(n), 250, 2) * np.exp(-t / 0.018)
    finger = bp(r.standard_normal(n), 700, 2500, 2) * np.exp(-t / 0.005)
    x = x / (np.abs(x).max() + 1e-9) + 0.5 * thump / (np.abs(thump).max() + 1e-9) \
        + 0.06 * finger / (np.abs(finger).max() + 1e-9)
    x = lp(x, 2200, 2)
    return endfade(x) * vel


def vibes(f, dur, vel=0.6, r=None, trem_hz=4.2, trem_depth=0.25):
    """Soft-mallet vibraphone: tuned bar partials 1, 4, 10 + slow motor tremolo."""
    decay = float(np.clip(3.0 * (523.0 / f) ** 0.4, 1.0, 5.0))
    n = nsamp(min(dur, decay * 3) + 1.2)
    t = tax(n)
    env = _release(t, dur, 0.25)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    x += 0.22 * vel * np.sin(2 * np.pi * f * 3.99 * t) * np.exp(-t / (decay * 0.18))
    x += 0.07 * vel * np.sin(2 * np.pi * f * 9.95 * t) * np.exp(-t / 0.05)
    x *= (1 - np.exp(-t / 0.001)) * env
    x *= 1 - trem_depth * (0.5 - 0.5 * np.cos(2 * np.pi * trem_hz * t))
    return endfade(x, 0.3) * vel


def bell_partials(f, partials, decays, amps, n):
    t = tax(n)
    x = np.zeros(n)
    for p, d, a in zip(partials, decays, amps):
        x += a * np.sin(2 * np.pi * f * p * t + p) * np.exp(-t / d)
    return endfade(x * (1 - np.exp(-t / 0.0005)), 0.4)


def brush_swish(dur, vel=0.5, r=None):
    """Brush stirred on a snare head: band-limited noise with a bowed envelope."""
    r = r or np.random.default_rng(1)
    n = nsamp(dur)
    t = tax(n)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.6
    grain = np.exp(0.5 * lp(r.standard_normal(n), 40, 1) / 0.15)
    grain /= grain.mean()
    x = bp(r.standard_normal(n), 2500, 11000, 2) * env * grain
    return x / (np.abs(x).max() + 1e-9) * vel


def brush_tap(vel=0.5, r=None):
    r = r or np.random.default_rng(2)
    n = nsamp(0.35)
    t = tax(n)
    noise = bp(r.standard_normal(n), 1500, 9000, 2) * env_ad(n, 0.0008, 0.045)
    wires = hp(r.standard_normal(n), 3000, 2) * env_ad(n, 0.002, 0.11) * 0.35
    body = np.sin(2 * np.pi * 185 * t * (1 + 0.1 * np.exp(-t / 0.01))) * env_ad(n, 0.001, 0.05)
    x = noise / np.abs(noise).max() + wires / np.abs(wires).max() * 0.35 + 0.35 * body
    return x / np.abs(x).max() * vel


def feather_kick(vel=0.3):
    n = nsamp(0.4)
    t = tax(n)
    f = 52 * (1 + 0.8 * np.exp(-t / 0.02))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.003, 0.14)
    return x * vel


def pad(freqs, dur, vel=0.4, r=None, attack=1.6, rel=2.5, cutoff=1400):
    """Warm detuned-saw pad, additive (band-limited) with a soft low-pass tilt."""
    r = r or np.random.default_rng(3)
    n = nsamp(dur + rel * 3)
    t = tax(n)
    x = np.zeros(n)
    for f in freqs:
        for det in (-0.006, 0.0, 0.0055):
            fd = f * (1 + det)
            ph0 = r.uniform(0, 6.28)
            for k in range(1, 40):
                if k * fd > cutoff * 2.5:
                    break
                a = np.exp(-((k * fd / cutoff) ** 2)) / k
                x += a * np.sin(2 * np.pi * k * fd * t + ph0 * k)
    env = np.clip(t / attack, 0, 1) ** 2 * _release(t, dur, rel)
    x *= env
    return endfade(x, 0.5) / (np.abs(x).max() + 1e-9) * vel


def metal_click(r, f_scale=1.0, tau_scale=1.0, n_s=0.12):
    """Small metallic click (umbrella runner / latch): impulse into high resonators."""
    n = nsamp(n_s)
    imp = np.zeros(n)
    imp[0] = 1.0
    imp[1:40] += r.standard_normal(39) * 0.3 * np.exp(-np.arange(39) / 8)
    x = np.zeros(n)
    for f, tau, a in ((2900, 0.02, 1.0), (4300, 0.012, 0.8), (6100, 0.008, 0.6), (8800, 0.005, 0.4),
                      (1750, 0.04, 0.25)):
        x += a * resonator(imp, f * f_scale * (1 + 0.03 * r.standard_normal()), tau * tau_scale)
    x += hp(imp, 2000, 2) * 0.5
    return x / (np.abs(x).max() + 1e-9)
