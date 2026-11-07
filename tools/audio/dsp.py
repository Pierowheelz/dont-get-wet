"""Shared DSP helpers for the Don't Get Wet audio generators.

Conventions
- Sample rate SR = 44100. Mono signals are 1-D arrays, stereo signals are shape (2, n).
- "c*" helpers are *circular*: they treat the buffer as periodic, so anything built only from
  them loops sample-exactly (no crossfade needed).  "l*" helpers are linear (for one-shots).
"""
from __future__ import annotations

import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def secs(n: int) -> float:
    return n / SR


def nsamp(seconds: float) -> int:
    return int(round(seconds * SR))


def tax(n: int) -> np.ndarray:
    return np.arange(n) / SR


def db(x):
    return 20 * np.log10(np.maximum(np.abs(x), 1e-12))


def undb(d):
    return 10 ** (np.asarray(d) / 20)


# --------------------------------------------------------------------------- frequency domain

def fgrid(n: int) -> np.ndarray:
    return np.fft.rfftfreq(n, 1 / SR)


def mag_bp(f, lo=None, hi=None, order=2):
    """Butterworth-like magnitude response (zero phase when applied in the FFT domain)."""
    f = np.asarray(f, dtype=float)
    h = np.ones_like(f)
    if hi:
        h = h / np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        h = h / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return h


def mag_peak(f, fc, q, gain_db):
    """Smooth bell bump on a log-frequency axis (magnitude only)."""
    f = np.maximum(np.asarray(f, dtype=float), 1.0)
    bw = 1.0 / q  # in octaves, roughly
    x = np.log2(f / fc) / bw
    return undb(gain_db * np.exp(-0.5 * x * x * 4))


def cfilt(x, h):
    """Circular zero-phase filter. h: array over rfft bins or callable(freqs)."""
    n = x.shape[-1]
    X = np.fft.rfft(x, axis=-1)
    if callable(h):
        h = h(fgrid(n))
    return np.fft.irfft(X * h, n, axis=-1)


def cnoise(n, r, h=None):
    x = r.standard_normal(n)
    return cfilt(x, h) if h is not None else x


def pink(f):
    return 1 / np.sqrt(np.maximum(f, 20.0))


def brown(f):
    return 1 / np.maximum(f, 20.0)


def smooth_rand(n, r, rate_hz):
    """Periodic smooth random curve (zero mean, unit std) with energy below ~rate_hz."""
    x = r.standard_normal(n)
    f = fgrid(n)
    h = np.exp(-((f / rate_hz) ** 2))
    h[0] = 0
    y = cfilt(x, h)
    return y / (y.std() + 1e-12)


def periodic_freq(f, n):
    """Nearest frequency with an integer number of cycles in n samples (for loop LFOs)."""
    cycles = max(1, round(f * n / SR))
    return cycles * SR / n


def cplace(n, kernel, pos, amp):
    """Circularly sum copies of `kernel` at sample positions `pos` with gains `amp`."""
    train = np.zeros(n)
    if len(pos):
        np.add.at(train, np.asarray(pos) % n, amp)
    k = np.zeros(n)
    k[: min(len(kernel), n)] = kernel[:n]
    return np.fft.irfft(np.fft.rfft(train) * np.fft.rfft(k), n)


def lplace(n, kernel, pos, amp):
    """Linear version of cplace (output truncated to n)."""
    m = n + len(kernel)
    train = np.zeros(m)
    pos = np.asarray(pos, dtype=int)
    ok = (pos >= 0) & (pos < n)
    if ok.any():
        np.add.at(train, pos[ok], np.asarray(amp)[ok] if np.ndim(amp) else amp)
    return signal.fftconvolve(train, kernel)[:n]


def add_at(buf, x, pos, circular=True):
    """Add x into buf starting at sample pos (last axis); wraps if circular, else truncates."""
    n = buf.shape[-1]
    m = x.shape[-1]
    pos = int(pos)
    if circular:
        pos %= n
        i = 0
        while i < m:
            take = min(m - i, n - pos)
            buf[..., pos : pos + take] += x[..., i : i + take]
            i += take
            pos = 0
    else:
        if pos >= n or pos + m <= 0:
            return
        a = max(0, -pos)
        b = min(m, n - pos)
        buf[..., pos + a : pos + b] += x[..., a:b]


def cconv(x, ir):
    """Circular convolution (x periodic). x: (n,) or (c, n); ir: (len,) or (c, len)."""
    n = x.shape[-1]
    k = np.zeros(ir.shape[:-1] + (n,))
    m = min(ir.shape[-1], n)
    k[..., :m] = ir[..., :m]
    # wrap any IR longer than the loop
    if ir.shape[-1] > n:
        rest = ir[..., n:]
        for s in range(0, rest.shape[-1], n):
            seg = rest[..., s : s + n]
            k[..., : seg.shape[-1]] += seg
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * np.fft.rfft(k, axis=-1), n, axis=-1)


# --------------------------------------------------------------------------- IIR helpers (linear)

def bp(x, lo, hi, order=2):
    hi = min(hi, SR * 0.45)
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def lp(x, fc, order=2):
    sos = signal.butter(order, min(fc, SR * 0.45), btype="low", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def hp(x, fc, order=2):
    sos = signal.butter(order, fc, btype="high", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def resonator(x, f0, tau):
    """Two-pole resonator with decay time constant tau (s), unity-ish peak gain."""
    rr = np.exp(-1 / (tau * SR))
    w = 2 * np.pi * f0 / SR
    b = [1 - rr]
    a = [1, -2 * rr * np.cos(w), rr * rr]
    return signal.lfilter(b, a, x, axis=-1)


def tv_lowpass(x, fc_curve, order_blend=(250, 500, 1000, 2000, 4000, 8000, 16000)):
    """Time-varying low-pass by crossfading a bank of fixed low-passes (cheap, smooth)."""
    fcs = np.array(order_blend, dtype=float)
    bank = np.stack([lp(x, f, 2) for f in fcs])
    lf = np.log2(np.clip(fc_curve, fcs[0], fcs[-1]))
    lfc = np.log2(fcs)
    idx = np.clip(np.searchsorted(lfc, lf) - 1, 0, len(fcs) - 2)
    frac = (lf - lfc[idx]) / (lfc[idx + 1] - lfc[idx])
    ar = np.arange(len(x))
    return bank[idx, ar] * (1 - frac) + bank[idx + 1, ar] * frac


# --------------------------------------------------------------------------- envelopes & kernels

def env_ad(n, attack, decay):
    t = tax(n)
    return (1 - np.exp(-t / max(attack, 1e-5))) * np.exp(-t / decay)


def k_tick(r, fc, bw_oct, tau):
    """A drop tick: exponentially decaying band-limited noise burst."""
    n = max(16, int(SR * tau * 6))
    x = r.standard_normal(n) * env_ad(n, 0.00008, tau)
    lo = fc / 2 ** (bw_oct / 2)
    hi = fc * 2 ** (bw_oct / 2)
    x = bp(x, max(lo, 30), hi, 2)
    return x / (np.abs(x).max() + 1e-12)


def k_bubble(f0, tau, chirp, phase=0.0):
    """Minnaert-style bubble 'plink': decaying sine whose pitch rises as it decays."""
    n = max(16, int(SR * tau * 6))
    t = tax(n)
    f = f0 * (1 + chirp * (1 - np.exp(-t / (tau * 1.5))))
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    x = np.sin(ph) * env_ad(n, 0.0002, tau)
    return x / (np.abs(x).max() + 1e-12)


MEMBRANE = [(1.0, 1.0), (1.594, 0.7), (2.136, 0.55), (2.296, 0.5), (2.653, 0.35), (2.918, 0.3),
            (3.156, 0.22), (3.501, 0.18)]


def k_membrane(r, f0, tau, click=0.4, click_fc=3000, n_modes=8, damp_hi=1.6):
    """Struck membrane (fabric panel): circular-membrane modes + a tap transient."""
    n = int(SR * tau * 6)
    t = tax(n)
    x = np.zeros(n)
    for ratio, a in MEMBRANE[:n_modes]:
        fr = f0 * ratio * (1 + 0.02 * r.standard_normal())
        tt = tau / (ratio ** damp_hi)
        x += a * np.sin(2 * np.pi * fr * t + r.uniform(0, 6.28)) * np.exp(-t / tt)
    x *= 1 - np.exp(-t / 0.0004)
    if click:
        c = k_tick(r, click_fc, 1.6, 0.0006)
        x[: len(c)] += click * c * np.abs(x).max()
    return x / (np.abs(x).max() + 1e-12)


def poisson_times(r, n, rate, env=None):
    """Event sample positions for a Poisson process of `rate`/s over n samples, optionally
    thinned by an envelope array (values 0..1, length n)."""
    count = r.poisson(rate * n / SR)
    pos = np.sort(r.integers(0, n, count))
    if env is not None:
        keep = r.random(count) < env[pos]
        pos = pos[keep]
    return pos


def drop_field(n, r, rate, kernels, amp_sigma=0.6, env=None, circular=True, amp_env=None):
    """Sum of many grains drawn from a list of kernels (each a class of similar drops)."""
    pos = poisson_times(r, n, rate, env)
    amp = np.exp(amp_sigma * r.standard_normal(len(pos)))
    amp *= r.choice([-1.0, 1.0], len(pos))
    if amp_env is not None:
        amp *= amp_env[pos]
    cls = r.integers(0, len(kernels), len(pos))
    out = np.zeros(n)
    place = cplace if circular else lplace
    for i, k in enumerate(kernels):
        m = cls == i
        if m.any():
            out += place(n, k, pos[m], amp[m])
    return out


# --------------------------------------------------------------------------- reverb

def make_ir(r, t60=2.0, pre_ms=12.0, channels=2, hf_ratio=0.45, lf_ratio=1.1, density_ms=25.0,
            early=8, length=None):
    """Synthetic stereo reverb impulse response: band-wise exponentially decaying noise."""
    n = nsamp(length or t60 * 1.3)
    t = tax(n)
    bands = [(None, 400, t60 * lf_ratio), (400, 1800, t60), (1800, 6000, t60 * (1 + hf_ratio) / 2),
             (6000, None, t60 * hf_ratio)]
    out = np.zeros((channels, n))
    for c in range(channels):
        acc = np.zeros(n)
        for lo, hi, T in bands:
            x = r.standard_normal(n)
            if lo and hi:
                x = bp(x, lo, hi, 2)
            elif hi:
                x = lp(x, hi, 2)
            else:
                x = hp(x, lo, 2)
            acc += x * np.exp(-6.91 * t / T)
        acc *= 1 - np.exp(-t / (density_ms / 1000))
        for _ in range(early):
            p = nsamp(r.uniform(0.004, 0.06))
            acc[p] += r.uniform(0.3, 1.0) * r.choice([-1, 1]) * np.abs(acc[:nsamp(0.1)]).max() * 0.6
        pre = nsamp(pre_ms / 1000)
        acc = np.concatenate([np.zeros(pre), acc])[:n]
        out[c] = acc / np.sqrt(np.sum(acc ** 2))
    return out


def lreverb(x, ir, wet=0.3, dry=1.0):
    """Linear stereo reverb of a mono or stereo signal. Returns stereo with tail appended."""
    x = np.atleast_2d(x)
    if x.shape[0] == 1:
        x = np.vstack([x, x])
    n = x.shape[1] + ir.shape[1] - 1
    out = np.zeros((2, n))
    for c in range(2):
        out[c, : x.shape[1]] += dry * x[c]
        out[c] += wet * signal.fftconvolve(x[c], ir[c])[:n]
    return out


def lreverb_mono(x, ir_mono, wet=0.2):
    w = signal.fftconvolve(x, ir_mono)
    y = np.zeros(len(w))
    y[: len(x)] += x
    y += wet * w
    return y


# --------------------------------------------------------------------------- spectral shaping

THIRD_OCT = 1000 * 2 ** (np.arange(-17, 15) / 3)  # ~20 Hz .. 20 kHz


def band_levels(x, centers=THIRD_OCT):
    """Average power (dB) in 1/3-octave bands of a mono or stereo signal."""
    x = np.atleast_2d(x)
    P = np.mean(np.abs(np.fft.rfft(x, axis=-1)) ** 2, axis=0)
    f = fgrid(x.shape[-1])
    out = []
    for c in centers:
        m = (f >= c / 2 ** (1 / 6)) & (f < c * 2 ** (1 / 6))
        out.append(10 * np.log10(P[m].mean() + 1e-30) if m.any() else -300)
    return np.array(out)


def match_spectrum(x, target, strength=1.0, max_db=18.0):
    """Circular zero-phase EQ moving the 1/3-oct spectrum of x toward `target`
    (list of (freq, dB) points, relative). Preserves overall level roughly."""
    x2 = np.atleast_2d(x)
    lv = band_levels(x2)
    tf = np.array([p[0] for p in target], dtype=float)
    td = np.array([p[1] for p in target], dtype=float)
    tgt = np.interp(np.log2(THIRD_OCT), np.log2(tf), td, left=td[0] - 12, right=td[-1] - 12)
    valid = lv > -250
    diff = np.where(valid, tgt - lv, 0)
    # remove offset: align at the loudest target band
    ref = np.argmax(np.where(valid, tgt, -999))
    diff -= diff[ref]
    diff = np.clip(diff * strength, -max_db, max_db)
    f = fgrid(x2.shape[-1])
    gd = np.interp(np.log2(np.maximum(f, 10)), np.log2(THIRD_OCT), diff)
    y = cfilt(x2, undb(gd))
    return y if np.ndim(x) > 1 else y[0]


# --------------------------------------------------------------------------- loudness

def _kweight(x):
    fs = SR
    f0 = 1681.974450955533
    G = 3.999843853973347
    Q = 0.7071752369554196
    K = np.tan(np.pi * f0 / fs)
    Vh = 10 ** (G / 20)
    Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0 = 38.13547087602444
    Q = 0.5003270373238773
    K = np.tan(np.pi * f0 / fs)
    d = 1 + K / Q + K * K
    b2 = [1, -2, 1]
    a2 = [1, 2 * (K * K - 1) / d, (1 - K / Q + K * K) / d]
    y = signal.lfilter(b1, a1, x, axis=-1)
    return signal.lfilter(b2, a2, y, axis=-1)


def lufs(x):
    """Integrated loudness (ITU-R BS.1770-4, gated)."""
    x = np.atleast_2d(x)
    y = _kweight(x)
    blk = nsamp(0.4)
    hop = nsamp(0.1)
    if y.shape[1] < blk:
        y = np.pad(y, ((0, 0), (0, blk - y.shape[1])))
    starts = np.arange(0, y.shape[1] - blk + 1, hop)
    cs = np.cumsum(np.pad(y ** 2, ((0, 0), (1, 0))), axis=1)
    z = (cs[:, starts + blk] - cs[:, starts]) / blk
    zs = z.sum(axis=0)
    l = -0.691 + 10 * np.log10(zs + 1e-30)
    g = zs[l > -70]
    if not len(g):
        return -100.0
    rel = -0.691 + 10 * np.log10(g.mean()) - 10
    g2 = zs[(l > -70) & (l > rel)]
    return float(-0.691 + 10 * np.log10(g2.mean()))


def peak_db(x):
    return float(db(np.abs(x).max()))


def norm_peak(x, target_db=-1.0):
    return x * undb(target_db) / (np.abs(x).max() + 1e-12)


def soft_ceiling(x, ceil_db=-1.5, knee_db=6.0):
    """Transparent-ish soft clip above (ceil - knee); output never exceeds ceil."""
    c = undb(ceil_db)
    k = undb(ceil_db - knee_db)
    a = np.abs(x)
    over = a > k
    y = x.copy()
    y[over] = np.sign(x[over]) * (k + (c - k) * np.tanh((a[over] - k) / (c - k)))
    return y


def norm_loudness(x, target_lufs=-16.0, ceil_db=-1.5, knee_db=4.0):
    """Gain to target integrated loudness; rare peaks are soft-limited below ceil_db."""
    y = x
    for _ in range(4):  # the limiter shaves a little loudness, so iterate to converge
        y = y * undb(target_lufs - lufs(y))
        if np.abs(y).max() > undb(ceil_db - knee_db):
            y = soft_ceiling(y, ceil_db, knee_db)
    return y


def fade(x, fin=0.002, fout=0.01):
    x = x.copy()
    a = nsamp(fin)
    b = nsamp(fout)
    if a:
        x[..., :a] *= np.linspace(0, 1, a) ** 2
    if b:
        x[..., -b:] *= np.linspace(1, 0, b) ** 2
    return x


def trim_tail(x, thresh_db=-70.0, pad=0.02):
    """Cut trailing near-silence from a one-shot."""
    a = np.abs(np.atleast_2d(x)).max(axis=0)
    lim = a.max() * undb(thresh_db)
    idx = np.nonzero(a > lim)[0]
    end = min(a.shape[0], (idx[-1] if len(idx) else 0) + nsamp(pad))
    return x[..., :end]


def pan(x, p):
    """Equal-power pan of mono x; p in [-1, 1]. p may be an array (time-varying)."""
    th = (np.asarray(p) + 1) * np.pi / 4
    return np.vstack([x * np.cos(th), x * np.sin(th)])


# --------------------------------------------------------------------------- output

def write_ogg(path, x, quality=5):
    """Write mono (n,) or stereo (2, n) float audio to Ogg Vorbis via ffmpeg."""
    x = np.asarray(x, dtype=np.float64)
    if np.abs(x).max() > 1.0:
        raise ValueError(f"{path}: clipping ({peak_db(x):.2f} dBFS)")
    data = x.T.astype(np.float32) if x.ndim > 1 else x.astype(np.float32)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, "tmp.wav")
        wavfile.write(wav, SR, data)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis",
                        "-q:a", str(quality), "-ar", str(SR), path], check=True)


def read_audio(path):
    """Decode any file to float (channels, n) via ffmpeg."""
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                            "stream=channels", "-of", "csv=p=0", path], capture_output=True,
                           text=True, check=True)
    ch = int(probe.stdout.strip().split(",")[0])
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-acodec",
                          "pcm_f32le", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    a = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return a.reshape(-1, ch).T
