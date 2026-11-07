"""Seamless ambience loops: rain layers, gutter, wind, distant traffic.

Everything here is built from circular (periodic) operations, so each loop wraps sample-exactly.
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, add_at, cconv, cfilt, cnoise, drop_field, k_bubble, k_membrane, k_tick,
                 make_ir, mag_bp, mag_peak, match_spectrum, nsamp, pan, periodic_freq, pink,
                 brown, rng, smooth_rand, tax, undb, lp, bp, hp)


def logu(r, a, b, size=None):
    return np.exp(r.uniform(np.log(a), np.log(b), size))


def unit(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def spread_field(n, r, rate, kernels, pans, sigma=0.7, amp_env=None):
    """Drop field spread over several fixed pan positions -> stereo."""
    out = np.zeros((2, n))
    for p in pans:
        f = drop_field(n, r, rate / len(pans), kernels, sigma, amp_env=amp_env)
        out += pan(f, p)
    return out


def splat_kernels(r, count, f_lo=900, f_hi=3200, tick_fc=(1500, 5000)):
    ks = []
    for _ in range(count):
        tick = k_tick(r, logu(r, *tick_fc), 1.8, r.uniform(0.0006, 0.002))
        bub = k_bubble(logu(r, f_lo, f_hi), r.uniform(0.006, 0.022), r.uniform(0.3, 1.0),
                       r.uniform(0, 6.28))
        k = np.zeros(max(len(tick), len(bub)))
        k[: len(tick)] += tick
        k[: len(bub)] += bub * r.uniform(0.3, 0.9)
        ks.append(k / np.abs(k).max())
    return ks


def street_ir(r, t60=0.9):
    return make_ir(r, t60=t60, pre_ms=5, hf_ratio=0.5, density_ms=6, early=10)


# --------------------------------------------------------------------------- rain

RAIN_LIGHT_SPEC = [(60, -26), (100, -22), (200, -16), (500, -9), (1000, -5), (2000, -2), (4000, 0),
                   (8000, -2), (12000, -6), (16000, -12), (20000, -20)]
RAIN_HEAVY_SPEC = [(40, -16), (60, -13), (100, -11), (200, -9), (500, -6), (1000, -3), (2000, -1),
                   (4000, 0), (8000, -2), (12000, -6), (16000, -12), (20000, -20)]


def rain(seed, dur, heavy=False):
    r = rng(seed)
    n = nsamp(dur)
    fine_k = [k_tick(r, logu(r, 2500, 11000), r.uniform(1.0, 2.0), r.uniform(0.00012, 0.0006))
              for _ in range(24)]
    mid_k = [k_tick(r, logu(r, 700, 4000), r.uniform(1.2, 2.2), r.uniform(0.0008, 0.003))
             for _ in range(24)]
    plink_k = [k_bubble(logu(r, 1400, 5000), r.uniform(0.004, 0.018), r.uniform(0.3, 1.2),
                        r.uniform(0, 6.28)) for _ in range(20)]
    close_k = splat_kernels(r, 16)

    # slow, gentle intensity swells (rain never sounds perfectly constant)
    swell_db = 3.0 if heavy else 2.0
    swell = undb(swell_db * smooth_rand(n, r, 0.07) / 2)

    if heavy:
        rates = dict(fine=9000, mid=1400, plink=140, close=22)
        gains = dict(fine=0, mid=-1, plink=-11, close=-9, bed=-2, rumble=-6)
    else:
        rates = dict(fine=1500, mid=220, plink=30, close=5)
        gains = dict(fine=0, mid=-3, plink=-13, close=-9, bed=-10, rumble=-20)

    out = np.zeros((2, n))
    bed_common = cnoise(n, r, lambda f: pink(f) * mag_bp(f, 600 if not heavy else 300, 10000, 2))
    for c in range(2):
        fine = drop_field(n, r, rates["fine"], fine_k, 0.5 if heavy else 0.75, amp_env=swell)
        mid = drop_field(n, r, rates["mid"], mid_k, 0.8, amp_env=swell)
        plink = drop_field(n, r, rates["plink"], plink_k, 0.7)
        bed = 0.6 * bed_common + 0.8 * cnoise(
            n, r, lambda f: pink(f) * mag_bp(f, 600 if not heavy else 300, 10000, 2))
        bed *= swell
        rumble = cnoise(n, r, lambda f: brown(f) * mag_bp(f, 35, 260, 2))
        rumble *= undb(2.0 * smooth_rand(n, r, 0.15) / 2)
        out[c] += (undb(gains["fine"]) * unit(fine) + undb(gains["mid"]) * unit(mid)
                   + undb(gains["plink"]) * unit(plink) + undb(gains["bed"]) * unit(bed)
                   + undb(gains["rumble"]) * unit(rumble))
    close = spread_field(n, r, rates["close"], close_k, np.linspace(-0.9, 0.9, 7), 0.6)
    out += undb(gains["close"]) * close / (np.sqrt(np.mean(close ** 2)) + 1e-12)

    out = match_spectrum(out, RAIN_HEAVY_SPEC if heavy else RAIN_LIGHT_SPEC, 0.85)
    ir = street_ir(r, 1.1 if heavy else 0.9)
    out = out + 0.22 * cconv(out, ir)
    return out


# --------------------------------------------------------------------------- rain on umbrella

UMBRELLA_SPEC = [(60, -22), (100, -14), (200, -6), (400, 0), (800, -1), (1600, -3), (3200, -5),
                 (6400, -9), (12000, -16), (16000, -22), (20000, -30)]


def rain_on_umbrella(seed, dur):
    r = rng(seed)
    n = nsamp(dur)
    hit_k = [k_membrane(r, logu(r, 230, 620), r.uniform(0.02, 0.05), click=r.uniform(0.4, 0.9),
                        click_fc=logu(r, 2200, 5000)) for _ in range(28)]
    big_k = [k_membrane(r, logu(r, 160, 330), r.uniform(0.04, 0.08), click=0.6, click_fc=2000)
             for _ in range(8)]
    rim_k = splat_kernels(r, 10, 700, 2200)
    swell = undb(2.5 * smooth_rand(n, r, 0.09) / 2)
    pans = np.linspace(-0.55, 0.55, 6)

    hits = spread_field(n, r, 85, hit_k, pans, 0.75, amp_env=swell)
    patter = spread_field(n, r, 700, hit_k, pans, 0.5, amp_env=swell)
    big = spread_field(n, r, 1.4, big_k, pans, 0.4)
    rim = spread_field(n, r, 3.0, rim_k, [-0.9, -0.7, 0.7, 0.9], 0.5)
    hiss = np.vstack([cnoise(n, r, lambda f: pink(f) * mag_bp(f, 300, 3500, 2)) for _ in range(2)])
    hiss *= swell

    def u(x):
        return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)

    out = u(hits) + undb(-7) * u(patter) + undb(-3) * u(big) + undb(-16) * u(rim) \
        + undb(-15) * u(hiss)
    out = match_spectrum(out, UMBRELLA_SPEC, 0.6)
    out = out + 0.12 * cconv(out, street_ir(r, 0.5))
    return out


# --------------------------------------------------------------------------- rain on awning

AWNING_SPEC = [(50, -18), (80, -10), (150, -4), (300, 0), (600, -2), (1200, -5), (2500, -7),
               (5000, -11), (10000, -17), (16000, -25), (20000, -32)]


def rain_on_awning(seed, dur):
    r = rng(seed)
    n = nsamp(dur)
    canvas_k = [k_membrane(r, logu(r, 110, 300), r.uniform(0.012, 0.03), click=r.uniform(0.2, 0.45),
                           click_fc=logu(r, 1300, 2600), damp_hi=2.0) for _ in range(28)]
    drip_k = splat_kernels(r, 16, 700, 2600, (1200, 4000))
    swell = undb(2.0 * smooth_rand(n, r, 0.08) / 2)
    pans = np.linspace(-0.8, 0.8, 7)

    hits = spread_field(n, r, 320, canvas_k, pans, 0.65, amp_env=swell)
    dense = spread_field(n, r, 1800, canvas_k, pans, 0.4, amp_env=swell)
    # drip line along the awning's front edge, a metre or so in front: steady plips & splats
    drips = spread_field(n, r, 11, drip_k, np.linspace(-0.9, 0.9, 9), 0.45)
    beyond = np.vstack([cnoise(n, r, lambda f: pink(f) * mag_bp(f, 400, 5000, 2))
                        for _ in range(2)]) * swell

    def u(x):
        return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)

    out = u(hits) + undb(-6) * u(dense) + undb(-10) * u(drips) + undb(-14) * u(beyond)
    out = match_spectrum(out, AWNING_SPEC, 0.6)
    out = out + 0.15 * cconv(out, street_ir(r, 0.7))
    return out


# --------------------------------------------------------------------------- gutter

GUTTER_SPEC = [(50, -20), (100, -12), (200, -6), (400, -1), (800, 0), (1600, -2), (3200, -5),
               (6400, -10), (12000, -18), (20000, -30)]


def gutter(seed, dur):
    r = rng(seed)
    n = nsamp(dur)
    bub_k = [k_bubble(logu(r, 300, 1700), r.uniform(0.008, 0.04), r.uniform(0.4, 1.6),
                      r.uniform(0, 6.28)) for _ in range(32)]
    splash_k = [k_tick(r, logu(r, 900, 4500), 1.8, r.uniform(0.0008, 0.003)) for _ in range(16)]
    out = np.zeros((2, n))
    for c in range(2):
        burble = undb(6 * smooth_rand(n, r, 3.0) / 2)
        bubbles = drop_field(n, r, 170, bub_k, 0.6, amp_env=burble / burble.max())
        splashes = drop_field(n, r, 90, splash_k, 0.6)
        turb = undb(5 * smooth_rand(n, r, 14.0) / 2)
        pour = cnoise(n, r, lambda f: pink(f) * mag_bp(f, 250, 2600, 2)) * turb
        hiss = cnoise(n, r, lambda f: mag_bp(f, 1500, 9000, 2))
        out[c] = (unit(bubbles) + undb(-4) * unit(pour) + undb(-8) * unit(splashes)
                  + undb(-17) * unit(hiss))
    # a little shared signal so the stream sounds like one source, slightly off-centre
    mid = out.mean(axis=0)
    out = 0.55 * out + 0.45 * np.vstack([mid * 1.05, mid * 0.95])
    out = cfilt(out, lambda f: mag_peak(f, 290, 3.0, 4.0))  # hollow downpipe resonance
    out = match_spectrum(out, GUTTER_SPEC, 0.6)
    out = out + 0.2 * cconv(out, street_ir(r, 0.8))
    return out


# --------------------------------------------------------------------------- gutter on umbrella

def gutter_on_umbrella(seed, dur):
    """A gutter's stream drumming on the umbrella: the same taut-nylon membrane hits as rain on the
    umbrella (plasticky, bright), but a dense continuous torrent of them — a fast drum-roll with
    heavier splats mixed in and spray tearing off the canopy edge. Built to layer over
    rain_on_umbrella_loop."""
    r = rng(seed)
    n = nsamp(dur)
    hit_k = [k_membrane(r, logu(r, 260, 700), r.uniform(0.015, 0.04), click=r.uniform(0.6, 1.0),
                        click_fc=logu(r, 2500, 6000)) for _ in range(32)]
    big_k = [k_membrane(r, logu(r, 200, 420), r.uniform(0.03, 0.06), click=0.8, click_fc=2600)
             for _ in range(12)]
    spray_k = splat_kernels(r, 16, 1200, 4200)
    surge = undb(3.0 * smooth_rand(n, r, 2.2) / 2)
    pans = np.linspace(-0.3, 0.3, 5)

    roll = spread_field(n, r, 1800, hit_k, pans, 0.55, amp_env=surge)     # continuous torrent
    hits = spread_field(n, r, 220, hit_k, pans, 0.8, amp_env=surge)       # audible individual taps
    big = spread_field(n, r, 35, big_k, pans, 0.6, amp_env=surge)         # heavier gobbets
    spray = spread_field(n, r, 120, spray_k, [-0.8, -0.5, 0.5, 0.8], 0.6, amp_env=surge)
    hiss = np.vstack([cnoise(n, r, lambda f: pink(f) * mag_bp(f, 600, 6000, 2)) for _ in range(2)])
    hiss *= surge

    def u(x):
        return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)

    out = u(roll) + undb(-2) * u(hits) + undb(-5) * u(big) + undb(-10) * u(spray) \
        + undb(-14) * u(hiss)
    out = match_spectrum(out, UMBRELLA_SPEC, 0.6)
    out = out + 0.1 * cconv(out, street_ir(r, 0.45))
    return out


# --------------------------------------------------------------------------- wind

WIND_SPEC = [(30, -10), (40, -6), (80, -2), (160, 0), (315, -2), (630, -6), (1250, -11),
             (2500, -17), (5000, -24), (10000, -32), (20000, -45)]


def wind(seed, dur):
    r = rng(seed)
    n = nsamp(dur)
    gust = smooth_rand(n, r, 0.12)
    out = np.zeros((2, n))
    lag = nsamp(0.35)
    for c in range(2):
        g = undb(9 * np.roll(gust, c * lag) / 2)  # +-9 dB-ish gusts
        g /= g.mean()
        g2 = undb(4 * smooth_rand(n, r, 0.5) / 2)
        low = cnoise(n, r, lambda f: brown(f) * mag_bp(f, 25, 220, 2)) * (0.6 + 0.4 * g)
        mid = cnoise(n, r, lambda f: pink(f) * mag_bp(f, 220, 1300, 2)) * g ** 1.5 * g2
        high = cnoise(n, r, lambda f: mag_bp(f, 1500, 6000, 2)) * g ** 2
        whistle = np.zeros(n)
        for fc in (610, 660, 720, 940, 1010):
            band = cnoise(n, r, lambda f, fc=fc: np.exp(-0.5 * ((f - fc) / (fc / 70)) ** 2))
            e = np.maximum(g * undb(6 * smooth_rand(n, r, 0.2) / 2) - 1.2, 0) ** 2
            whistle += unit(band) * e
        out[c] = (unit(low) + undb(-3) * unit(mid) + undb(-14) * unit(high)
                  + undb(-24) * whistle / (np.sqrt(np.mean(whistle ** 2)) + 1e-12))
    out = match_spectrum(out, WIND_SPEC, 0.5)
    return out


# --------------------------------------------------------------------------- distant traffic

TRAFFIC_SPEC = [(30, -10), (40, -5), (80, 0), (160, -1), (315, -4), (630, -8), (1250, -12),
                (2500, -17), (5000, -24), (10000, -34), (20000, -50)]


def _pass_segment(r, seg_s, width_s, bright, direction):
    seg_s = max(seg_s, 7 * width_s)
    m = nsamp(seg_s)
    t = tax(m) - seg_s / 2
    env = np.exp(-0.5 * (t / width_s) ** 2) * np.sin(np.pi * np.arange(m) / m) ** 2
    hiss = bp(r.standard_normal(m), 350, bright, 2)
    roar = lp(r.standard_normal(m), 260, 2) * 2.5
    tone = np.zeros(m)
    f0 = r.uniform(32, 48)
    dop = 1 + 0.035 * np.tanh(-t / (width_s * 0.6)) * 1  # gentle doppler drop
    ph = 2 * np.pi * np.cumsum(f0 * dop) / SR
    for h in range(1, 7):
        tone += np.sin(h * ph + r.uniform(0, 6.28)) / h ** 1.3
    x = (unit(hiss) + undb(-4) * unit(roar) + undb(-12) * unit(tone)) * env
    p = direction * np.tanh(t / (width_s * 1.2)) * 0.85
    return pan(x, p)


def traffic(seed, dur):
    r = rng(seed)
    n = nsamp(dur)
    drone = np.vstack([cnoise(n, r, lambda f: brown(f) * mag_bp(f, 28, 420, 2)) for _ in range(2)])
    drone *= undb(3 * smooth_rand(n, r, 0.04) / 2)
    city_hiss = np.vstack([cnoise(n, r, lambda f: pink(f) * mag_bp(f, 300, 3000, 2))
                           for _ in range(2)])
    passes = np.zeros((2, n))
    times = np.sort(r.uniform(0, dur, 8))
    for i, t0 in enumerate(times):
        seg = _pass_segment(r, 9.0, r.uniform(1.1, 2.4), r.uniform(2500, 4500),
                            r.choice([-1, 1]))
        add_at(passes, seg * undb(r.uniform(-7, 0)), nsamp(t0 - 4.5))
    # one heavier vehicle (bus) lumbering past
    seg = _pass_segment(r, 14.0, 3.5, 1800, 1)
    add_at(passes, seg * undb(-1), nsamp(dur * 0.62 - 7))
    # a far-off car horn, twice, a long way down the street
    hm = nsamp(1.4)
    th = tax(hm)
    horn = np.zeros(hm)
    for (a, b) in ((0.0, 0.28), (0.42, 0.95)):
        g = ((th >= a) & (th < b)).astype(float)
        g = lp(g, 30, 1)
        for f in (392.0, 466.0):
            for h in range(1, 6):
                horn += g * np.sin(2 * np.pi * f * h * th) / h
    horn = lp(hp(horn, 300), 1800)
    horn = pan(horn, -0.4) * undb(-9)
    add_at(passes, horn / np.abs(horn).max() * np.sqrt(np.mean(passes ** 2)) * 1.6,
           nsamp(dur * 0.27))

    out = unit(drone) + undb(-10) * unit(city_hiss) + undb(-2) * passes / (
        np.sqrt(np.mean(passes ** 2)) + 1e-12)
    out = match_spectrum(out, TRAFFIC_SPEC, 0.5)
    ir = make_ir(r, t60=2.6, pre_ms=30, hf_ratio=0.35, density_ms=30)
    out = 0.7 * out + 0.55 * cconv(out, ir)
    return out


LOOPS = {
    "rain_light_loop": (lambda: rain(101, 40.0, heavy=False)),
    "rain_heavy_loop": (lambda: rain(202, 40.0, heavy=True)),
    "rain_on_umbrella_loop": (lambda: rain_on_umbrella(303, 30.0)),
    "rain_on_awning_loop": (lambda: rain_on_awning(404, 30.0)),
    "gutter_loop": (lambda: gutter(505, 24.0)),
    "gutter_on_umbrella_loop": (lambda: gutter_on_umbrella(515, 16.0)),
    "wind_loop": (lambda: wind(606, 45.0)),
    "traffic_distant_loop": (lambda: traffic(707, 50.0)),
}
