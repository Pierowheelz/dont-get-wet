#!/usr/bin/env python3
"""Level preview and design check for the street JSONs in levels/.

  tools/level_preview.py main_street -o out.png [--trace a.jsonl ...] [--report]

The PNG is one long strip wrapped into rows of ROW_M metres. The report derives open-sky spans
from the JSON the way LevelBuilder.cover_map() does and exits 1 when a design rule fails.
"""
import argparse
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ROW_M = 60.0
PX_M = 20.0
LEFT = 78
SP_COLORS = [(232, 222, 250), (214, 236, 226), (250, 228, 210), (220, 232, 248), (246, 222, 232)]
RIGHT = 24
STEP = 0.1  # sampling resolution for cover maths, metres

COVER_COLORS = {
    "awning": (196, 74, 64),
    "balcony": (140, 98, 62),
    "arcade": (128, 96, 168),
    "canopy": (46, 148, 150),
}
INK = (30, 34, 42)
MUTED = (110, 116, 128)
BG = (247, 247, 244)
SKY = (205, 226, 244)
RAIN_C = (70, 120, 200)
WIND_C = (222, 130, 30)
WET_C = (214, 52, 52)
STA_C = (40, 110, 210)
GRID = (222, 224, 228)


def load_tunables():
    with open(os.path.join(ROOT, "data", "tunables.json")) as f:
        return json.load(f)


def load_level(arg):
    path = arg if arg.endswith(".json") else os.path.join(ROOT, "levels", arg + ".json")
    with open(path) as f:
        return json.load(f)


def curve(keys, x, end_x):
    """Same lookup as Level._curve: keyframes are [fraction of end_x, value]."""
    p = min(max(x / max(end_x, 1.0), 0.0), 1.0)
    for i in range(1, len(keys)):
        if p <= keys[i][0]:
            a, b = keys[i - 1], keys[i]
            t = (p - a[0]) / max(b[0] - a[0], 0.0001)
            return a[1] + (b[1] - a[1]) * t
    return keys[-1][1]


class Street:
    def __init__(self, data):
        self.d = data
        self.end_x = float(data["end_x"])
        self.rain_keys = data.get("rain", [[0, 1], [1, 1]])
        self.wind_keys = data.get("wind", [[0, 0], [1, 0]])
        self.gusts = bool(data.get("gusts", False))
        self.crossings = [(float(c["x"]), float(c["x"]) + float(c["w"])) for c in data.get("crossings", [])]
        self.features = data.get("features", [])
        self.sun = [(float(f["x"]), float(f["x"]) + float(f["w"])) for f in self.features if f["type"] == "sun"]
        self.covers = self._cover_spans()

    def _cover_spans(self):
        """[(x0, x1, kind)] of fixed cover. Awning tears are cut out; canopy is inset 0.15 m."""
        out = []
        for lot in self.d.get("lots", []):
            kind = lot.get("cover", "none")
            lx, lw = float(lot["x"]), float(lot["w"])
            if kind == "awning":
                segs = [(0.0, lw)]
                for t0, t1 in lot.get("tears", []):
                    nxt = []
                    for a, b in segs:
                        if t0 > a:
                            nxt.append((a, min(t0, b)))
                        if t1 < b:
                            nxt.append((max(t1, a), b))
                    segs = nxt
                out += [(lx + a, lx + b, kind) for a, b in segs if b > a]
            elif kind in ("balcony", "arcade"):
                out.append((lx, lx + lw, kind))
            elif kind == "canopy":
                out.append((lx + 0.15, lx + lw - 0.15, kind))
        return out

    def rain(self, x):
        if any(a < x < b for a, b in self.sun):
            return 0.0
        return curve(self.rain_keys, x, self.end_x)

    def wind(self, x):
        return curve(self.wind_keys, x, self.end_x)

    def covered(self, x):
        # Cover is painted after the crossing's open road in cover_map, so cover wins.
        return any(a <= x <= b for a, b, _ in self.covers)

    def open_spans(self):
        spans, start, i = [], None, 0
        n = int(self.end_x / STEP)
        while i <= n:
            x = i * STEP
            if not self.covered(x):
                if start is None:
                    start = x
            elif start is not None:
                spans.append((start, x))
                start = None
            i += 1
        if start is not None:
            spans.append((start, self.end_x))
        return spans


# ---------------------------------------------------------------------------------------------
# report

START_COVER_M = 20.0
RAMP_TOL = 0.20
HOLD_TOL = 0.30


def decile_table(st, tun):
    spans = st.open_spans()
    rows = []
    step = st.end_x / 10.0
    for k in range(10):
        a, b = k * step, (k + 1) * step
        n = max(int((b - a) / STEP), 1)
        xs = [a + (i + 0.5) * (b - a) / n for i in range(n)]
        open_frac = sum(1 for x in xs if not st.covered(x)) / n
        longest = max([min(b, s1) - max(a, s0) for s0, s1 in spans if s1 > a and s0 < b] + [0.0])
        longest_full = max([s1 - s0 for s0, s1 in spans if s1 > a and s0 < b] + [0.0])
        g = sum(1 for f in st.features if f["type"] == "gutter" and a <= f["x"] < b)
        p = sum(1 for f in st.features if f["type"] == "puddle" and a <= f["x"] < b)
        c = sum(1 for c0, c1 in st.crossings if a <= c0 < b)
        rain = sum(st.rain(x) for x in xs) / n
        wind = sum(abs(st.wind(x)) for x in xs) / n
        per100 = 100.0 / (b - a)
        diff = 10.0 * sum((not st.covered(x)) * st.rain(x) * (1 + abs(st.wind(x))) for x in xs) / n \
            + (0.5 * g + 0.15 * p + 0.4 * c) * per100
        rows.append(dict(a=a, b=b, open=open_frac, longest=longest, longest_full=longest_full,
                         g=g, p=p, c=c, rain=rain, wind=wind, diff=diff))
    return rows


DIFF_FORMULA = ("difficulty = 10 * mean(open_sky * rain * (1 + |wind|)) "
                "+ (0.5*gutters + 0.15*puddles + 0.4*crossings) per 100 m, per decile of end_x "
                "(rain is 0 in sun breaks)")


def crossable_m(tun, wind):
    """Metres walkable with the umbrella up from a full bar to empty (no hurry), at a given |wind|."""
    drain = tun["stamina_drain_umbrella"] + tun["stamina_drain_wind"] * wind * wind
    secs = tun["stamina_max"] / drain
    return secs * tun["walk_speed_umbrella"], secs, drain


def run_checks(st, tun, rows):
    checks = []

    first_open = [s for s in st.open_spans() if s[0] < START_COVER_M]
    ok = not first_open
    msg = (f"first {START_COVER_M:.0f} m is under continuous cover" if ok else
           f"open sky at {first_open[0][0]:.1f}-{min(first_open[0][1], START_COVER_M):.1f} m. DESIGN §7: the start is a "
           f"tutorial-ish stretch under continuous cover, so the player can learn the controls dry")
    checks.append(("start-covered", ok, msg))

    mid = 5
    d = [r["diff"] for r in rows]
    peak = max(d) or 1.0
    drops = [(k, d[k - 1] - d[k]) for k in range(1, mid) if d[k - 1] - d[k] > RAMP_TOL * peak]
    ok = not drops
    if ok:
        msg = f"difficulty never falls by more than {RAMP_TOL:.0%} of peak ({RAMP_TOL * peak:.1f}) before the midpoint"
    else:
        k, v = drops[0]
        msg = (f"difficulty falls {v:.1f} from decile {k} to {k + 1} (tolerance {RAMP_TOL * peak:.1f} = "
               f"{RAMP_TOL:.0%} of peak {peak:.1f}). DESIGN §7: difficulty ramps up to the midpoint")
    checks.append(("ramp-to-midpoint", ok, msg))

    plateau = d[mid:]
    pm = sum(plateau) / len(plateau)
    bad = [(mid + i + 1, v) for i, v in enumerate(plateau) if abs(v - pm) > HOLD_TOL * pm]
    first_half = sum(d[:mid]) / mid
    ok = not bad and first_half < pm
    if ok:
        msg = f"deciles 6-10 stay within {HOLD_TOL:.0%} of their mean {pm:.1f}; first half averages {first_half:.1f}"
    else:
        parts = [f"deciles {', '.join(f'{k} ({v:.1f})' for k, v in bad)} stray more than {HOLD_TOL:.0%} from the "
                 f"second-half mean {pm:.1f}"] if bad else []
        if first_half >= pm:
            parts.append(f"first half ({first_half:.1f}) is not easier than the second ({pm:.1f})")
        msg = "; ".join(parts) + ". DESIGN §7: ramp to the midpoint, then hold steady to the end"
    checks.append(("hold-after-midpoint", ok, msg))

    worst = None
    for s0, s1 in st.open_spans():
        w = max(abs(st.wind(s0 + i * STEP)) for i in range(int((s1 - s0) / STEP) + 1))
        head = min(st.wind(s0 + i * STEP) for i in range(int((s1 - s0) / STEP) + 1))
        reach, secs, drain = crossable_m(tun, w)
        reach *= 1.0 - tun["headwind_slow"] * max(-head, 0.0)
        over = (s1 - s0) - reach
        if worst is None or over > worst[0]:
            worst = (over, s0, s1, w, reach, secs, drain)
    over, s0, s1, w, reach, secs, drain = worst
    ok = over <= 0
    detail = (f"span {s0:.1f}-{s1:.1f} m is {s1 - s0:.1f} m; {tun['stamina_max']:.0f} stamina at "
              f"{drain:.1f}/s (umbrella {tun['stamina_drain_umbrella']:.1f} + wind {tun['stamina_drain_wind']:.1f}*{w:.2f}^2) "
              f"lasts {secs:.0f} s at {tun['walk_speed_umbrella']:.1f} m/s = {reach:.1f} m")
    if ok:
        msg = "longest span is crossable on a full bar with the umbrella up. Tightest: " + detail
    else:
        msg = (f"{detail}. The walker is exhausted {over:.1f} m short and the umbrella droops "
               f"(DESIGN §6 / tunables stamina_*), so shorten the span or add cover/vent inside it")
    checks.append(("span-crossable", ok, msg))
    return checks


def print_report(st, tun, rows, checks, name):
    print(f"== {name}: end_x {st.end_x:.1f} m, {len(st.open_spans())} open spans, "
          f"gusts {'yes' if st.gusts else 'no'} ==")
    print(f"{'decile':>6} {'metres':>11} {'open':>5} {'longest':>8} {'gut':>3} {'pud':>3} {'xing':>4} "
          f"{'rain':>5} {'|wind|':>6} {'diff':>6}")
    for k, r in enumerate(rows, 1):
        longest = f"{r['longest_full']:.1f}"
        print(f"{k:>6} {r['a']:>5.0f}-{r['b']:<5.0f} {r['open']:>5.0%} {longest:>8} {r['g']:>3} {r['p']:>3} "
              f"{r['c']:>4} {r['rain']:>5.2f} {r['wind']:>6.2f} {r['diff']:>6.1f}")
    print(DIFF_FORMULA)
    print("longest = full length of the longest open span touching the decile (may extend past it)")
    print("checks:")
    for cid, ok, msg in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {cid}: {msg}")
    return all(ok for _, ok, _ in checks)


# ---------------------------------------------------------------------------------------------
# rendering

_font_cache = {}


def font(size, bold=False):
    key = (size, bold)
    if key not in _font_cache:
        name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
        for base in ("/usr/share/fonts/dejavu-sans-fonts", "/usr/share/fonts/TTF", "/usr/share/fonts/truetype/dejavu",
                     "/usr/share/fonts/dejavu"):
            p = os.path.join(base, name)
            if os.path.exists(p):
                _font_cache[key] = ImageFont.truetype(p, size)
                break
        else:
            try:
                _font_cache[key] = ImageFont.truetype(name, size)
            except OSError:
                _font_cache[key] = ImageFont.load_default(size)
    return _font_cache[key]


def load_trace(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("{"):
                rows.append(json.loads(line))
    return rows


def glyph(d, kind, cx, y, w_px):
    if kind == "puddle":
        r = max(w_px / 2, 5)
        d.ellipse([cx - r, y + 10, cx + r, y + 20], fill=(90, 150, 220), outline=(40, 90, 170))
    elif kind == "gutter":
        d.rectangle([cx - 5, y + 1, cx + 5, y + 5], fill=(60, 70, 80))
        d.rectangle([cx - 1.5, y + 5, cx + 1.5, y + 22], fill=(30, 150, 170))
        d.polygon([(cx - 5, y + 20), (cx + 5, y + 20), (cx, y + 28)], fill=(30, 150, 170))
    elif kind == "sun":
        d.rectangle([cx - w_px / 2, y + 22, cx + w_px / 2, y + 27], fill=(250, 214, 80))
        d.ellipse([cx - 7, y + 6, cx + 7, y + 20], fill=(250, 200, 40), outline=(200, 140, 0))
        for a in range(8):
            ang = a * math.pi / 4
            d.line([cx + 9 * math.cos(ang), y + 13 + 9 * math.sin(ang), cx + 13 * math.cos(ang), y + 13 + 13 * math.sin(ang)],
                   fill=(220, 160, 0), width=1)
    elif kind == "vent":
        for dy in (0, 7):
            d.line([(cx - 6, y + 20 - dy), (cx, y + 12 - dy), (cx + 6, y + 20 - dy)], fill=(230, 120, 40), width=2)
    elif kind == "fire_barrel":
        d.rectangle([cx - 5, y + 14, cx + 5, y + 26], fill=(90, 70, 60), outline=INK)
        d.polygon([(cx - 4, y + 14), (cx + 4, y + 14), (cx, y + 2)], fill=(240, 110, 30))
    else:
        d.rectangle([cx - 5, y + 10, cx + 5, y + 22], outline=(160, 40, 160), width=2)
        d.text((cx, y + 16), "?", fill=(160, 40, 160), font=font(10), anchor="mm")


FEATURE_NAMES = {"puddle": "puddle", "gutter": "gutter", "sun": "sun break", "vent": "warm vent",
                 "fire_barrel": "fire barrel"}


def render(st, tun, traces, out, title):
    n_rows = math.ceil(st.end_x / ROW_M)
    W = int(LEFT + ROW_M * PX_M + RIGHT)
    H_TICK, H_RAIN, H_COVER, H_XING, H_FEAT, H_TR, GAP = 22, 64, 26, 18, 40, 78, 18
    pieces = st.d.get("set_pieces", [])
    H_SP = 20 if pieces else 0
    row_h = H_TICK + H_SP + H_RAIN + H_COVER + H_XING + H_FEAT + H_TR * len(traces) + GAP
    top = 54
    legend_h = 96
    img = Image.new("RGB", (W, top + row_h * n_rows + legend_h), BG)
    d = ImageDraw.Draw(img)
    d.text((LEFT, 14), title, fill=INK, font=font(22, True))
    d.text((W - RIGHT, 20), f"{st.end_x:.0f} m to the door, rain 0-{max(v for _, v in st.rain_keys):.2f}, "
           f"|wind| to {max(abs(v) for _, v in st.wind_keys):.2f}{', gusts' if st.gusts else ''}",
           fill=MUTED, font=font(13), anchor="ra")

    for r in range(n_rows):
        x0m = r * ROW_M
        x1m = min(x0m + ROW_M, st.end_x)
        y0 = top + r * row_h

        def X(m):
            return LEFT + (m - x0m) * PX_M

        right_px = X(x1m)
        y = y0
        # ticks
        for m in range(int(x0m), int(x1m) + 1):
            if m % 10 == 0:
                d.text((X(m), y + 6), f"{m}", fill=INK, font=font(12, True), anchor="mm")
        y_tick_end = y + H_TICK
        y_lanes_end = y + row_h - GAP
        for m in range(int(x0m), int(x1m) + 1):
            if m % 10 == 0:
                d.line([(X(m), y_tick_end - 5), (X(m), y_lanes_end)], fill=(190, 194, 202), width=1)
            elif m % 5 == 0:
                d.line([(X(m), y_tick_end - 3), (X(m), y_tick_end)], fill=(190, 194, 202), width=1)
        if x0m <= st.end_x <= x1m + 1e-6:
            d.line([(X(st.end_x), y + H_TICK), (X(st.end_x), y_lanes_end)], fill=(30, 150, 60), width=3)
            d.text((X(st.end_x) + 4, y + H_TICK + 8), "door", fill=(30, 150, 60), font=font(12, True), anchor="lm")
        y += H_TICK

        for i, p in enumerate(pieces):
            a, b = max(float(p["x0"]), x0m), min(float(p["x1"]), x1m)
            if b <= a:
                continue
            col = SP_COLORS[i % len(SP_COLORS)]
            d.rectangle([X(a), y + 2, X(b), y + H_SP - 3], fill=col)
            label = p["name"] if float(p["x0"]) >= x0m else p["name"] + " (cont.)"
            d.text((X(a) + 4, y + H_SP // 2), label, fill=INK, font=font(11, True), anchor="lm")
        y += H_SP

        # rain + wind
        d.text((LEFT - 8, y + 18), "rain", fill=RAIN_C, font=font(12, True), anchor="rm")
        d.text((LEFT - 8, y + 46), "wind", fill=WIND_C, font=font(12, True), anchor="rm")
        rain_h, base = 36, y + 38
        pts = [(X(x0m), base), (X(x1m), base)]
        m = x0m
        top_pts = []
        while m <= x1m + 1e-6:
            raw = curve(st.rain_keys, m, st.end_x)
            top_pts.append((X(m), base - raw / 1.5 * rain_h))
            m += 0.5
        d.polygon(pts + top_pts[::-1], fill=(190, 210, 240))
        d.line(top_pts, fill=RAIN_C, width=2)
        for s0, s1 in st.sun:
            if s1 > x0m and s0 < x1m:
                d.rectangle([X(max(s0, x0m)), y + 2, X(min(s1, x1m)), base], fill=(252, 236, 160))
        # redraw rain outline above the sun tint
        d.line(top_pts, fill=RAIN_C, width=2)
        zero = y + 52
        d.line([(LEFT, zero), (right_px, zero)], fill=GRID, width=1)
        wp, m = [], x0m
        while m <= x1m + 1e-6:
            wv = curve(st.wind_keys, m, st.end_x)
            wp.append((X(m), zero - wv * 22))
            m += 0.5
        d.line(wp, fill=WIND_C, width=2)
        if st.gusts:
            for i in range(len(wp) - 1):
                amp = 4 * math.sin((x0m + i * 0.5) * 2.1)
                d.line([(wp[i][0], wp[i][1] + amp), (wp[i + 1][0], wp[i + 1][1] - amp)], fill=(240, 180, 90), width=1)
        y += H_RAIN

        # cover
        d.text((LEFT - 8, y + 13), "cover", fill=INK, font=font(12, True), anchor="rm")
        d.rectangle([LEFT, y + 2, right_px, y + H_COVER - 4], fill=SKY)
        for a, b, kind in st.covers:
            if b > x0m and a < x1m:
                d.rectangle([X(max(a, x0m)), y + 2, X(min(b, x1m)), y + H_COVER - 4], fill=COVER_COLORS[kind])
        for s0, s1 in st.open_spans():
            if s1 > x0m and s0 < x1m and s1 - s0 >= 5.0:
                xa, xb = X(max(s0, x0m)), X(min(s1, x1m))
                d.text(((xa + xb) / 2, y + 12), f"{s1 - s0:.0f} m open", fill=(40, 70, 120), font=font(11), anchor="mm")
        y += H_COVER

        # crossings
        d.text((LEFT - 8, y + 9), "xing", fill=INK, font=font(12, True), anchor="rm")
        for c0, c1 in st.crossings:
            if c1 > x0m and c0 < x1m:
                xa, xb = X(max(c0, x0m)), X(min(c1, x1m))
                d.rectangle([xa, y + 1, xb, y + H_XING - 2], fill=(120, 124, 134))
                for sx in range(int(xa) + 4, int(xb) - 2, 12):
                    d.rectangle([sx, y + 6, sx + 5, y + 11], fill=(150, 154, 164))
                if xb - xa > 60:
                    d.text(((xa + xb) / 2, y + 9), f"cars {c1 - c0:.0f} m", fill=(255, 255, 255), font=font(10, True), anchor="mm",
                           stroke_width=2, stroke_fill=(120, 124, 134))
        y += H_XING

        # features
        d.text((LEFT - 8, y + 16), "hazards", fill=INK, font=font(12, True), anchor="rm")
        for f in st.features:
            fx = float(f["x"])
            fw = float(f.get("w", 1.0))
            cx = fx + (fw / 2 if f["type"] == "sun" else 0.0)
            if x0m <= cx <= x1m:
                glyph(d, f["type"], X(cx), y, fw * PX_M)
                d.text((X(cx), y + 31), f"{fx:.0f}", fill=MUTED, font=font(9), anchor="mm")
        y += H_FEAT

        # traces
        for label, rows_t in traces:
            d.rectangle([LEFT, y + 2, right_px, y + H_TR - 4], fill=(255, 255, 255), outline=GRID)
            d.text((LEFT - 8, y + 20), label, fill=INK, font=font(11, True), anchor="rm")
            d.text((LEFT - 8, y + 34), "wet", fill=WET_C, font=font(10), anchor="rm")
            d.text((LEFT - 8, y + 46), "stamina", fill=STA_C, font=font(10), anchor="rm")
            lo, hi = y + 8, y + H_TR - 10
            seg = [t for t in rows_t if x0m - 0.3 <= t["x"] <= x1m + 0.3]
            if seg:
                for a_, b_ in zip(seg, seg[1:]):
                    if a_["open"] > 0.5:
                        d.rectangle([X(a_["x"]), y + 3, X(b_["x"]), y + 6], fill=(40, 60, 90))
                    if a_["hurry"] > 0.05:
                        d.rectangle([X(a_["x"]), y + H_TR - 7, X(b_["x"]), y + H_TR - 4], fill=(240, 150, 30))
                st_pts = [(X(t["x"]), hi - t["stamina"] / tun["stamina_max"] * (hi - lo)) for t in seg]
                wt_pts = [(X(t["x"]), hi - t["wet"] / tun["wet_max"] * (hi - lo)) for t in seg]
                d.line(st_pts, fill=STA_C, width=2)
                d.line(wt_pts, fill=WET_C, width=2)
                last = rows_t[-1]
                if last["state"] == 2 or last["wet"] >= tun["wet_max"] - 0.01:
                    if x0m <= last["x"] <= x1m:
                        d.text((X(last["x"]), lo), "X soaked", fill=WET_C, font=font(11, True), anchor="rm")
            y += H_TR

    ly = top + row_h * n_rows + 6
    d.line([(LEFT, ly), (W - RIGHT, ly)], fill=GRID)
    ly += 10
    x = LEFT
    for kind, col in COVER_COLORS.items():
        d.rectangle([x, ly, x + 22, ly + 12], fill=col)
        d.text((x + 28, ly + 6), kind, fill=INK, font=font(12), anchor="lm")
        x += 100
    d.rectangle([x, ly, x + 22, ly + 12], fill=SKY)
    d.text((x + 28, ly + 6), "open sky (tears too)", fill=INK, font=font(12), anchor="lm")
    x += 180
    d.rectangle([x, ly, x + 22, ly + 12], fill=(120, 124, 134))
    d.text((x + 28, ly + 6), "side street (cars)", fill=INK, font=font(12), anchor="lm")
    ly += 26
    x = LEFT
    for kind in ("puddle", "gutter", "sun", "vent", "fire_barrel"):
        glyph(d, kind, x + 14, ly - 8, 20)
        d.text((x + 34, ly + 8), FEATURE_NAMES[kind], fill=INK, font=font(12), anchor="lm")
        x += 140
    ly += 30
    d.line([(LEFT, ly), (LEFT + 24, ly)], fill=RAIN_C, width=2)
    d.text((LEFT + 30, ly), "rain 0-1.5", fill=INK, font=font(12), anchor="lm")
    d.line([(LEFT + 130, ly), (LEFT + 154, ly)], fill=WIND_C, width=2)
    d.text((LEFT + 160, ly), "wind (up = tailwind, down = headwind)", fill=INK, font=font(12), anchor="lm")
    d.line([(LEFT + 450, ly), (LEFT + 474, ly)], fill=WET_C, width=2)
    d.text((LEFT + 480, ly), f"wetness 0-{tun['wet_max']:.0f}", fill=INK, font=font(12), anchor="lm")
    d.line([(LEFT + 600, ly), (LEFT + 624, ly)], fill=STA_C, width=2)
    d.text((LEFT + 630, ly), "stamina 0-100", fill=INK, font=font(12), anchor="lm")
    d.rectangle([LEFT + 740, ly - 2, LEFT + 764, ly + 1], fill=(40, 60, 90))
    d.text((LEFT + 770, ly), "umbrella open", fill=INK, font=font(12), anchor="lm")
    d.rectangle([LEFT + 880, ly - 2, LEFT + 904, ly + 1], fill=(240, 150, 30))
    d.text((LEFT + 910, ly), "hurrying", fill=INK, font=font(12), anchor="lm")
    img.save(out)


def trace_summary(label, rows, tun):
    last = rows[-1]
    s = last["stats"]
    outcome = "SOAKED" if last["state"] == 2 else "reached the door"
    return (f"{label}: final wet {last['wet']:.1f}/{tun['wet_max']:.0f} at x={last['x']:.0f} t={last['t']:.0f}s; "
            f"rain {s['wet_rain']:.1f} gutter {s['wet_gutter']:.1f} puddle {s['wet_puddle']:.1f} "
            f"splash {s['wet_splash']:.1f} dried {s['dried']:.1f}; min stamina "
            f"{min(r['stamina'] for r in rows):.0f}; {outcome}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("level", help="level id (levels/ID.json) or a path to a level JSON")
    ap.add_argument("--trace", action="append", default=[], metavar="FILE", help="autopilot trace (repeatable)")
    ap.add_argument("-o", "--out", help="write the PNG here")
    ap.add_argument("--report", action="store_true", help="print the decile table and design checks")
    a = ap.parse_args()

    data = load_level(a.level)
    tun = load_tunables()
    st = Street(data)
    traces = []
    for i, p in enumerate(a.trace):
        label = os.path.splitext(os.path.basename(p))[0]
        traces.append((label, load_trace(p)))
    ok = True
    if a.out:
        render(st, tun, traces, a.out, f"{data.get('name', data['id'])}  ({data['id']})")
        print(f"wrote {a.out}")
    if a.report or not a.out:
        rows = decile_table(st, tun)
        checks = run_checks(st, tun, rows)
        ok = print_report(st, tun, rows, checks, data["id"])
    for label, rows_t in traces:
        if rows_t:
            print(trace_summary(label, rows_t, tun))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
