"""One-shot SFX: footsteps, splashes, cars, umbrella handling, UI, stings, door."""
from __future__ import annotations

import numpy as np

from dsp import (SR, add_at, fade, bp, env_ad, hp, k_bubble, k_tick, lp, lreverb, lreverb_mono, make_ir,
                 nsamp, resonator, rng, tax, tv_lowpass, undb)
from instruments import (bell_partials, brush_swish, metal_click, mtof, n2m, rhodes, upright_bass,
                         vibes)

_IR_CACHE = {}


def street_ir_mono(t60=0.6):
    if t60 not in _IR_CACHE:
        _IR_CACHE[t60] = make_ir(rng(9000 + int(t60 * 100)), t60=t60, pre_ms=4, hf_ratio=0.5,
                                 density_ms=5, early=10)
    return _IR_CACHE[t60][0]


def hall_ir(t60=2.4):
    key = ("hall", t60)
    if key not in _IR_CACHE:
        _IR_CACHE[key] = make_ir(rng(9100), t60=t60, pre_ms=18, hf_ratio=0.4, density_ms=30)
    return _IR_CACHE[key]


def pk(x):
    return x / (np.abs(x).max() + 1e-12)


def logu(r, a, b, size=None):
    return np.exp(r.uniform(np.log(a), np.log(b), size))


def droplets(r, n, start, count, spread, amp=1.0, f_lo=1500, f_hi=4500, tick=(2000, 7000),
             maxt=None):
    """Water droplets scattering/landing after a splash: ticks + little bubbles."""
    out = np.zeros(n)
    times = start + r.exponential(spread, count)
    if maxt is not None:
        times = times[times < start + maxt]
    for tm in times:
        p = nsamp(tm)
        if p >= n:
            continue
        a = amp * np.exp(-(tm - start) / (spread * 2.5)) * np.exp(0.5 * r.standard_normal())
        k = k_tick(r, logu(r, *tick), 1.6, r.uniform(0.0003, 0.0015))
        if r.random() < 0.45:
            b = k_bubble(logu(r, f_lo, f_hi), r.uniform(0.003, 0.012), r.uniform(0.1, 0.5))
            kk = np.zeros(max(len(k), len(b)))
            kk[: len(k)] += k
            kk[: len(b)] += 0.6 * b
            k = kk
        add_at(out, k * a * r.choice([-1, 1]), p, circular=False)
    return out


# --------------------------------------------------------------------------- footsteps

def footstep(seed, run=False):
    r = rng(seed)
    n = nsamp(0.6)
    x = np.zeros(n)
    t0 = nsamp(0.003)

    # heel: dull thud (pitch-dropping low sine) + muffled click + a little pavement body
    m = nsamp(0.15)
    t = tax(m)
    f = r.uniform(85, 125) * (1 + 0.8 * np.exp(-t / 0.006))
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(m, 0.0006, r.uniform(0.009, 0.014))
    click = lp(r.standard_normal(m), r.uniform(2200, 3400), 2) * env_ad(m, 0.0002, 0.003)
    body = resonator(click, r.uniform(200, 380), 0.012) + 0.6 * resonator(click, r.uniform(600, 900),
                                                                         0.006)
    heel = 0.7 * pk(thud) + 0.6 * pk(click) + 0.6 * pk(body)
    add_at(x, pk(heel) * (1.0 if run else 0.9), t0, circular=False)

    # wet slap: the sole coming down flat on a film of water
    gap = r.uniform(0.026, 0.042) if run else r.uniform(0.055, 0.085)
    ts = 0.003 + gap
    m2 = nsamp(0.3)
    t2 = tax(m2)
    tau = r.uniform(0.022, 0.034) * (1.35 if run else 1.0)
    slap = bp(r.standard_normal(m2), 350, 5500, 2) * env_ad(m2, 0.0012, tau)
    slap *= 1 + 0.7 * lp(r.standard_normal(m2), 180, 2) / 0.1  # squelchy irregularity
    slap_low = np.sin(2 * np.pi * r.uniform(110, 160) * t2) * env_ad(m2, 0.001, 0.02)
    sl = pk(slap) + 0.35 * pk(slap_low)
    add_at(x, pk(sl) * (1.0 if run else r.uniform(0.75, 0.9)), nsamp(ts), circular=False)

    # splatter of displaced water
    cnt = r.integers(35, 60) if run else r.integers(10, 20)
    x += droplets(r, n, ts + 0.004, cnt, 0.035 if run else 0.025, 0.22 if run else 0.14,
                  maxt=0.18)

    x = lreverb_mono(x, street_ir_mono(0.4), 0.10)[: nsamp(0.48)]
    return fade(x, 0.0, 0.08)


# --------------------------------------------------------------------------- splashes & cars

def puddle_splash(seed=1201):
    r = rng(seed)
    n = nsamp(1.3)
    x = np.zeros(n)
    plop = k_bubble(r.uniform(210, 260), 0.035, 0.5)
    thump = lp(r.standard_normal(nsamp(0.2)), 220, 2) * env_ad(nsamp(0.2), 0.002, 0.03)
    m = nsamp(0.6)
    t = tax(m)
    splash = bp(r.standard_normal(m), 400, 7500, 2) * env_ad(m, 0.004, 0.085)
    splash *= np.exp(0.6 * lp(r.standard_normal(m), 90, 2) / 0.08)
    sheet = bp(r.standard_normal(m), 1200, 9000, 2) * env_ad(m, 0.025, 0.14)
    add_at(x, 0.5 * pk(thump), 0, circular=False)
    add_at(x, 0.55 * pk(plop), nsamp(0.006), circular=False)
    add_at(x, 1.0 * pk(splash), nsamp(0.004), circular=False)
    add_at(x, 0.35 * pk(sheet), nsamp(0.02), circular=False)
    x += droplets(r, n, 0.09, 110, 0.18, 0.35, 900, 3500)
    return lreverb_mono(x, street_ir_mono(0.7), 0.12)


def _car_pass_core(r, dur, tc, d, v, engine=True, bright_max=11000):
    n = nsamp(dur)
    t = tax(n)
    xp = v * (t - tc)
    rr = np.sqrt(d * d + xp * xp)
    near = d / rr
    amp = near ** 1.15
    vr = v * xp / rr
    dop = 343.0 / (343.0 + vr)
    hiss = bp(r.standard_normal(n), 250, 12000, 2)
    hiss = tv_lowpass(hiss, 1500 + bright_max * near ** 1.8)
    spray = hp(r.standard_normal(n), 2500, 2) * np.exp(0.5 * lp(r.standard_normal(n), 30, 1) / 0.1)
    spray = tv_lowpass(spray, 2500 + 12000 * near ** 2)
    roar = lp(r.standard_normal(n), 180, 2)
    out = pk(hiss) * amp + 0.35 * pk(spray) * near ** 2.2 + 0.6 * pk(roar) * amp
    if engine:
        f0 = r.uniform(48, 60)
        ph = 2 * np.pi * np.cumsum(f0 * dop) / SR
        eng = np.zeros(n)
        for h in range(1, 14):
            eng += np.sin(h * ph + r.uniform(0, 6.28)) * (1 / h ** 0.9) * (1 + 0.3 * r.random())
        eng *= 1 + 0.25 * np.sin(ph / 2)  # lumpy V8-ish firing
        eng = lp(eng, 900, 2)
        out += 0.45 * pk(eng) * amp ** 1.1
    return out


def car_pass(seed=1301):
    r = rng(seed)
    x = _car_pass_core(r, 5.0, 2.3, 3.0, 13.0)
    x *= np.minimum(1, tax(len(x)) / 0.3) * np.minimum(1, (5.0 - tax(len(x))) / 0.6)
    return lreverb_mono(x, street_ir_mono(0.9), 0.15)


def car_splash(seed=1401):
    r = rng(seed)
    dur = 3.2
    n = nsamp(dur)
    ts = 0.75
    x = 0.55 * _car_pass_core(r, dur, ts + 0.1, 2.0, 14.0, engine=True)
    x *= np.minimum(1, tax(n) / 0.25)
    m = nsamp(1.4)
    t = tax(m)
    sheet = bp(r.standard_normal(m), 250, 10000, 2) * env_ad(m, 0.012, 0.22)
    sheet *= np.exp(0.7 * lp(r.standard_normal(m), 60, 2) / 0.07)
    whump = lp(r.standard_normal(m), 170, 2) * env_ad(m, 0.006, 0.07)
    slosh = bp(r.standard_normal(m), 500, 3000, 2) * env_ad(m, 0.06, 0.25)
    add_at(x, 1.0 * pk(sheet), nsamp(ts), circular=False)
    add_at(x, 0.7 * pk(whump), nsamp(ts), circular=False)
    add_at(x, 0.4 * pk(slosh), nsamp(ts + 0.05), circular=False)
    x += droplets(r, n, ts + 0.15, 260, 0.35, 0.3, 800, 3500)
    x *= np.minimum(1, (dur - tax(n)) / 0.5).clip(0)
    return lreverb_mono(x, street_ir_mono(0.9), 0.14)


# --------------------------------------------------------------------------- umbrella

def _scrape(r, dur, rate0, rate1):
    """Runner sliding along the shaft: stick-slip friction pulses through metal-ish band."""
    n = nsamp(dur)
    t = tax(n)
    rate = rate0 + (rate1 - rate0) * t / dur
    ph = np.cumsum(rate) / SR
    pulses = np.maximum(0, np.sin(2 * np.pi * ph)) ** 12
    x = bp(r.standard_normal(n), 1800, 7000, 2) * (0.3 + pulses)
    return x * np.sin(np.pi * t / dur) ** 0.8


def umbrella_open(seed=1501):
    r = rng(seed)
    n = nsamp(1.0)
    x = np.zeros(n)
    add_at(x, 0.3 * metal_click(r, 1.2, 0.6), 0, circular=False)
    add_at(x, 0.3 * pk(_scrape(r, 0.32, 90, 150)), nsamp(0.02), circular=False)
    # fabric whoosh: swelling, brightening, fluttering
    m = nsamp(0.42)
    t = tax(m)
    w = hp(r.standard_normal(m), 200, 2)
    w = tv_lowpass(w, 700 + 4500 * (t / t[-1]) ** 1.5)
    w *= (t / t[-1]) ** 2 * (1 + 0.6 * lp(r.standard_normal(m), 30, 2) / 0.08)
    w *= np.minimum(1, (t[-1] - t) / 0.02)
    add_at(x, 0.85 * pk(w), nsamp(0.03), circular=False)
    # canopy pops taut
    m = nsamp(0.25)
    t = tax(m)
    pop = bp(r.standard_normal(m), 120, 700, 2) * env_ad(m, 0.001, 0.018)
    snap = hp(r.standard_normal(m), 900, 2) * env_ad(m, 0.0005, 0.01)
    add_at(x, 0.7 * pk(0.7 * pk(pop) + pk(snap)), nsamp(0.44), circular=False)
    # runner locks
    add_at(x, 1.0 * metal_click(r), nsamp(0.47), circular=False)
    for d in (0.505, 0.53, 0.56):
        add_at(x, 0.12 * metal_click(r, r.uniform(0.9, 1.4), 0.5), nsamp(d), circular=False)
    return lreverb_mono(x, street_ir_mono(0.5), 0.08)


def umbrella_close(seed=1601):
    r = rng(seed)
    n = nsamp(0.9)
    x = np.zeros(n)
    add_at(x, 0.45 * metal_click(r, 0.9, 0.7), 0, circular=False)
    # reverse-ish swish: grows toward the end, sweeping darker as the canopy folds
    m = nsamp(0.44)
    t = tax(m)
    w = hp(r.standard_normal(m), 250, 2)
    w = tv_lowpass(w, 4500 - 3300 * (t / t[-1]))
    w *= (t / t[-1]) ** 2.5 * (1 + 0.5 * lp(r.standard_normal(m), 25, 2) / 0.08)
    w *= np.minimum(1, (t[-1] - t) / 0.025)
    add_at(x, 0.7 * pk(w), nsamp(0.02), circular=False)
    # fabric crinkle
    for tm in np.sort(r.uniform(0.1, 0.44, 22)):
        k = k_tick(r, logu(r, 2000, 6500), 1.5, r.uniform(0.0004, 0.0012))
        add_at(x, k * 0.1 * r.uniform(0.4, 1), nsamp(tm), circular=False)
    add_at(x, 0.18 * pk(_scrape(r, 0.26, 140, 80)), nsamp(0.18), circular=False)
    # snap shut
    m = nsamp(0.2)
    t = tax(m)
    thud = np.sin(2 * np.pi * 140 * t) * env_ad(m, 0.001, 0.02)
    add_at(x, 0.35 * pk(thud), nsamp(0.465), circular=False)
    add_at(x, 1.0 * metal_click(r, 0.85, 0.8), nsamp(0.465), circular=False)
    return lreverb_mono(x, street_ir_mono(0.5), 0.08)


def _knock(r, scale=1.0):
    n = nsamp(0.25)
    imp = np.zeros(n)
    imp[:30] = r.standard_normal(30) * np.exp(-np.arange(30) / 6)
    x = np.zeros(n)
    for f, tau, a in ((470, 0.04, 1.0), (1130, 0.025, 0.7), (2350, 0.015, 0.45), (3900, 0.008, 0.3)):
        x += a * pk(resonator(imp, f * scale, tau))
    return pk(x + 0.4 * pk(hp(imp, 1500)))


def umbrella_drop(seed=1701):
    r = rng(seed)
    n = nsamp(1.6)
    x = np.zeros(n)
    for tm, g in ((0.0, 1.0), (0.21, 0.42), (0.33, 0.18)):
        add_at(x, g * _knock(r, r.uniform(0.95, 1.05)), nsamp(tm), circular=False)
        for _ in range(int(4 + 6 * g)):
            add_at(x, g * 0.3 * metal_click(r, r.uniform(1.0, 1.6), 0.4),
                   nsamp(tm + r.uniform(0.0, 0.1)), circular=False)
    # canopy flops onto the wet pavement
    m = nsamp(0.5)
    flop = lp(r.standard_normal(m), 200, 2) * env_ad(m, 0.004, 0.05)
    splash = bp(r.standard_normal(m), 500, 6000, 2) * env_ad(m, 0.003, 0.07)
    add_at(x, 0.6 * pk(flop) + 0.45 * pk(splash), nsamp(0.06), circular=False)
    x += droplets(r, n, 0.08, 35, 0.12, 0.18)
    add_at(x, 0.08 * pk(_scrape(r, 0.35, 60, 30)), nsamp(0.4), circular=False)
    return lreverb_mono(x, street_ir_mono(0.6), 0.1)


# --------------------------------------------------------------------------- UI

def ui_move(seed=1801):
    r = rng(seed)
    x = np.zeros(nsamp(0.2))
    add_at(x, pk(k_bubble(1350, 0.016, 0.3)), 0, circular=False)
    add_at(x, 0.25 * pk(k_bubble(2720, 0.008, 0.3)), 0, circular=False)
    x = lp(x, 6000, 2)
    return lreverb(x, hall_ir(1.2), wet=0.12).mean(axis=0)


def _seq(events, total, wet=0.25, t60=2.0):
    """events: list of (time, mono signal, pan-less gain)."""
    n = nsamp(total)
    x = np.zeros(n)
    for tm, sig, g in events:
        add_at(x, sig * g, nsamp(tm), circular=False)
    return lreverb(x, hall_ir(t60), wet=wet).mean(axis=0)


def ui_confirm():
    ev = [(0.0, rhodes(mtof(n2m("A4")), 0.25, 0.55), 1.0),
          (0.07, rhodes(mtof(n2m("E5")), 0.3, 0.6), 0.9),
          (0.07, vibes(mtof(n2m("E6")), 0.2, 0.4), 0.25)]
    return _seq(ev, 1.4, 0.22, 1.6)


def ui_back():
    ev = [(0.0, rhodes(mtof(n2m("E5")), 0.12, 0.45), 0.8),
          (0.06, rhodes(mtof(n2m("A4")), 0.25, 0.5), 1.0)]
    return _seq(ev, 1.1, 0.2, 1.4)


def ui_denied():
    ev = []
    for tm in (0.0, 0.12):
        for nn in ("Bb2", "B2"):
            ev.append((tm, rhodes(mtof(n2m(nn)), 0.07, 0.6, rel=0.03), 1.0))
    x = _seq(ev, 0.6, 0.08, 0.8)
    return lp(x, 1100, 2)


def token():
    def ting(f):
        n = nsamp(1.4)
        return bell_partials(f, (1, 2.756, 5.404, 8.933), (0.6, 0.25, 0.09, 0.04),
                             (1, 0.45, 0.2, 0.08), n)
    ev = [(0.0, ting(mtof(n2m("G6"))), 0.7), (0.075, ting(mtof(n2m("D7"))), 0.8),
          (0.075, vibes(mtof(n2m("G5")), 0.3, 0.5), 0.35)]
    return _seq(ev, 1.6, 0.25, 1.8)


# --------------------------------------------------------------------------- stings

def fail_sting():
    r = rng(1901)
    ev = []
    mel = [("F5", 0.0, 0.34), ("E5", 0.4, 0.36), ("Eb5", 0.86, 0.5), ("D5", 1.5, 2.6)]
    for nn, tm, d in mel:
        ev.append((tm, rhodes(mtof(n2m(nn)), d, 0.5), 0.9))
    for i, nn in enumerate(("F3", "A3", "C4", "E4")):
        ev.append((1.5 + 0.035 * i, rhodes(mtof(n2m(nn)), 2.6, 0.38), 0.6))
    ev.append((1.48, upright_bass(mtof(n2m("D2")), 2.4, 0.9, r), 0.9))
    ev.append((1.42, brush_swish(0.9, 0.12, r), 1.0))
    return _seq(ev, 5.6, 0.32, 2.6)


def win_sting():
    r = rng(2001)
    ev = [(0.0, upright_bass(mtof(n2m("F2")), 2.5, 0.85, r), 0.9)]
    for i, nn in enumerate(("F3", "A3", "C4", "E4", "G4")):
        ev.append((0.06 * i, rhodes(mtof(n2m(nn)), 2.6, 0.5), 0.55))
    for nn, tm, d in (("A5", 0.45, 0.3), ("C6", 0.8, 0.35), ("E6", 1.2, 2.0)):
        ev.append((tm, vibes(mtof(n2m(nn)), d, 0.6), 0.6))
    ev.append((1.2, brush_swish(0.6, 0.1, r), 1.0))
    return _seq(ev, 5.0, 0.3, 2.6)


# --------------------------------------------------------------------------- door

def door_open(seed=2101):
    r = rng(seed)
    n = nsamp(2.8)
    x = np.zeros(n)
    # latch: heavier, lower metal click + thunk
    add_at(x, 0.9 * metal_click(r, 0.45, 1.6, 0.25), 0, circular=False)
    m = nsamp(0.2)
    add_at(x, 0.4 * pk(lp(r.standard_normal(m), 400) * env_ad(m, 0.002, 0.03)), 0, circular=False)
    # hinge creak: stick-slip pulses through wooden formants, rate wandering
    dur = 0.9
    m = nsamp(dur)
    t = tax(m)
    rate = 70 + 30 * np.sin(2 * np.pi * 0.9 * t + 1) + 15 * lp(r.standard_normal(m), 5, 1) / 0.05
    ph = np.cumsum(np.maximum(rate, 25)) / SR
    pulses = np.maximum(0, np.sin(2 * np.pi * ph)) ** 30
    exc = pulses * (1 + 0.3 * r.standard_normal(m))
    creak = sum(a * pk(resonator(exc, f, tau)) for f, tau, a in
                ((620, 0.01, 1.0), (1350, 0.008, 0.7), (2500, 0.005, 0.4), (3700, 0.004, 0.2)))
    creak *= np.sin(np.pi * t / dur) ** 0.7
    add_at(x, 0.35 * pk(creak), nsamp(0.12), circular=False)
    # air & rain sound shifting as the door swings
    whoosh = lp(r.standard_normal(nsamp(1.2)), 600, 2) * np.sin(np.pi * tax(nsamp(1.2)) / 1.2)
    add_at(x, 0.12 * pk(whoosh), nsamp(0.1), circular=False)
    # shop bell on a spring, clapper bouncing
    f0 = 1720
    for i, (tm, a) in enumerate(((0.32, 1.0), (0.43, 0.6), (0.52, 0.45), (0.66, 0.3), (0.8, 0.18),
                                 (0.97, 0.1))):
        b = bell_partials(f0 * (1 + 0.002 * r.standard_normal()),
                          (1, 1.5, 2.42, 3.98, 5.9), (0.9, 0.5, 0.3, 0.15, 0.07),
                          (1, 0.3, 0.45, 0.2, 0.1), nsamp(1.8))
        add_at(x, 0.16 * a * b, nsamp(tm), circular=False)
    return lreverb_mono(x, street_ir_mono(0.8), 0.15)


SFX = {
    **{f"footstep_wet_{i + 1}": (lambda i=i: footstep(1000 + i, run=False)) for i in range(4)},
    **{f"footstep_run_{i + 1}": (lambda i=i: footstep(1100 + i, run=True)) for i in range(4)},
    "puddle_splash": puddle_splash,
    "car_pass": car_pass,
    "car_splash": car_splash,
    "umbrella_open": umbrella_open,
    "umbrella_close": umbrella_close,
    "umbrella_drop": umbrella_drop,
    "ui_move": ui_move,
    "ui_confirm": ui_confirm,
    "ui_back": ui_back,
    "ui_denied": ui_denied,
    "fail_sting": fail_sting,
    "win_sting": win_sting,
    "token": token,
    "door_open": door_open,
}
