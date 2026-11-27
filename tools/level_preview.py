#!/usr/bin/env python3
"""Level preview and design check for the street JSONs in levels/.

  tools/level_preview.py main_street -o out.png [--trace a.jsonl ...] [--report]

The PNG is one long strip wrapped into rows of ROW_M metres. The report derives open-sky spans
from the JSON the way LevelBuilder.cover_map() does and exits 1 when a design rule fails.

It can't simulate scripted threats (`attackers`, `henchmen`, `drive_bys`, the `courier`,
`helicopters`, `squalls`, `runners`): tools/preview.sh, which plays the street with both bots, is the
judge of those. On a street with skyways, or in the suburbs or the country, they are weighed into the
scores as threats (see threats()); elsewhere they are left out, and the strip only marks where each
helicopter is triggered (and where it hovers) and where each squall is triggered (and where its gust
blows on a walking walker). A
`skyway` is cover like an awning, only higher, so wind slants rain in further under its ends.

On a country street a lot with `cover: "trees"` is neither cover nor open sky: its crown lets
`tree_leak` of the rain through, so it scores that share of the rain, counts as a place to recover in
span-crossable (as does a sun break of SUN_RECOVER_M or more), and never holds a checkpoint. The
country's other cover (`shelter`, `barn`, `porch`) is cover like an awning.
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
    "walkway": (176, 150, 96),
    "canopy": (46, 148, 150),
    "deck": (92, 104, 122),
    "skyway": (60, 175, 90),
}
# Drawn and listed in the legend only on a street that has them, so other streets' strips are unchanged.
COUNTRY_COLORS = {
    "shelter": (150, 112, 70),
    "barn": (120, 70, 50),
    "porch": (205, 150, 120),
    "trees": (96, 160, 80),
}
WASH_C = (60, 150, 225)
HELI_C = (150, 60, 150)
GUST_C = (40, 140, 110)
SQUALL_OFF = 20.0     # a gust sets off this far upwind of its trigger (Squall.START_OFF)
SQUALL_SPEED = 8.0    # and its front blows down the lane at this (Squall.SPEED)
WALK = 1.3            # walk_speed, for where a gust meets a walking walker
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
        tr = data.get("track")
        self.track = (float(tr["x0"]), float(tr["x1"])) if tr else None
        # A railway's arches (its `viaducts`) are solid brick: the wash can't fall through them.
        self.railway = bool(tr) and tr.get("style", "monorail") == "railway"
        # Share of the time a sheet is falling on any one spot of the track, from the mean gap between trains.
        self.wash_duty = WASH_S / ((float(tr["gap"][0]) + float(tr["gap"][1])) / 2.0) if tr else 0.0
        self.decks = [(float(v["x0"]), float(v["x1"])) for v in data.get("viaducts", [])]
        self.skyways = [(float(v["x0"]), float(v["x1"])) for v in data.get("skyways", [])]
        self.trees = [(float(lot["x"]), float(lot["x"]) + float(lot["w"])) for lot in data.get("lots", [])
                      if lot.get("cover") == "trees"]
        self.tree_leak = float(load_tunables().get("tree_leak", 0.15))
        self.country = data.get("aesthetic") == "country" or bool(self.trees)
        self.covers = self._cover_spans()
        self.wash = self._wash_zones()

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
            elif kind in ("balcony", "arcade", "walkway", "shelter", "barn"):
                out.append((lx, lx + lw, kind))
            elif kind == "porch":
                a, b = porch_span(lot)
                out.append((lx + a, lx + b, kind))
            elif kind == "canopy":
                out.append((lx + 0.15, lx + lw - 0.15, kind))
        return out + [(a, b, "deck") for a, b in self.decks] + [(a, b, "skyway") for a, b in self.skyways]

    def _wash_zones(self):
        """[(x0, x1)] of track with no lot cover: where a passing train's sheet of water lands on the
        walker (Level.wash_at), under a monorail deck or not. It falls straight down, so awnings, slabs
        and a railway's arches stop it."""
        if not self.track:
            return []
        lot = [(a, b) for a, b, kind in self.covers if kind != "deck" or self.railway]
        run = [(max(self.track[0], 0.0), min(self.track[1], self.end_x))]
        return [(a, b) for a, b in _subtract(run, lot) if b - a > 1e-6]

    def under_deck(self, x):
        return any(a <= x <= b for a, b in self.decks)

    def under_skyway(self, x):
        return any(a <= x <= b for a, b in self.skyways)

    def cover_h(self, x):
        """Height of the cover over x, which sets how far wind slants rain in under its end: a deck's,
        else an awning's or slab's, else a skyway's."""
        if self.under_deck(x):
            return ARCH_H if self.railway else DECK_H
        if self.under_skyway(x) and not any(a <= x <= b for a, b, kind in self.covers if kind not in ("deck", "skyway")):
            return SKYWAY_H
        if any(a <= x <= b for a, b, kind in self.covers if kind == "barn"):
            return BARN_H
        return SLANT_H

    def cover_share(self):
        """Shares of end_x under any cover, and under a skyway."""
        n = max(int(self.end_x / STEP), 1)
        xs = [(i + 0.5) * STEP for i in range(n)]
        return (sum(1 for x in xs if self.covered(x)) / n, sum(1 for x in xs if self.under_skyway(x)) / n)

    def washed(self, x):
        return any(a <= x <= b for a, b in self.wash)

    def rain(self, x):
        if any(a < x < b for a, b in self.sun):
            return 0.0
        return curve(self.rain_keys, x, self.end_x)

    def wind(self, x):
        return curve(self.wind_keys, x, self.end_x)

    def covered(self, x):
        # Cover is painted after the crossing's open road in cover_map, so cover wins.
        return any(a <= x <= b for a, b, _ in self.covers)

    def treed(self, x):
        """Under a tree's crown and no cover: tree_leak of the rain gets through."""
        return any(a <= x <= b for a, b in self.trees) and not self.covered(x)

    def sunny(self, x):
        return any(a < x < b for a, b in self.sun)

    def exposure(self, x):
        """Share of the rain that reaches a walker with the umbrella shut: 0 under cover, tree_leak
        under trees, 1 in the open."""
        return 0.0 if self.covered(x) else (self.tree_leak if self.treed(x) else 1.0)

    def shares(self):
        """Shares of end_x under full cover, in sun, under trees (and not in sun) and in open rain."""
        n = max(int(self.end_x / STEP), 1)
        c = s = t = 0
        for i in range(n):
            x = (i + 0.5) * STEP
            if self.covered(x):
                c += 1
            elif self.sunny(x):
                s += 1
            elif self.treed(x):
                t += 1
        return c / n, s / n, t / n, 1.0 - (c + s + t) / n

    def uncovered_spans(self):
        """Spans with no full cover (open sky and trees)."""
        return self._spans(lambda x: not self.covered(x))

    def open_spans(self):
        """Spans of open sky: no cover and no trees."""
        return self._spans(lambda x: not self.covered(x) and not self.treed(x))

    def recovery_spans(self):
        """Open sky the walker has to cross with the umbrella up: open spans, split on a country street
        wherever a sun break of SUN_RECOVER_M or more lets him shut it and get his breath back (under
        trees he can too). Other streets were checked with a sun break inside its span, and still are."""
        if not self.country:
            return self.open_spans()
        out = []
        for a, b in self.open_spans():
            runs = [(a, b)]
            for s0, s1 in self.sun:
                if min(b, s1) - max(a, s0) >= SUN_RECOVER_M:
                    runs = _subtract(runs, [(s0, s1)])
            out += [r for r in runs if r[1] - r[0] > 1e-6]
        return out

    def _spans(self, pred):
        spans, start, i = [], None, 0
        n = int(self.end_x / STEP)
        while i <= n:
            x = i * STEP
            if pred(x):
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
# checkpoints: where a failed player can resume. Shared by tools/streets/street.py (which writes
# them into the level JSON) and the checkpoints-safe design check.

CHECKPOINT_TARGETS = (0.25, 0.5, 0.75)   # fractions of end_x
CHECKPOINT_TOL = 0.10                    # a checkpoint may sit this fraction of end_x from its target
CLEAR_M = 4.0                            # dry metres required ahead of a checkpoint
PREFER_CLEAR_M = 5.0                     # ... and the pick favours this much
PREFER_PENALTY_M = 2.0                   # how much farther from the target a < PREFER_CLEAR_M candidate counts
ENTRY_M = 0.5                            # checkpoint sits this far into a safe run, so the whole body is sheltered
SLANT_H = 3.1                            # awning height the wind slants rain across
DECK_H = 3.35                            # Track.DECK_Y: a deck's ends let slanted rain further in
ARCH_H = 3.1                             # Track.RAIL_SOFFIT: the same at the ends of a run of railway arches
SKYWAY_H = 4.45                          # SkywayBuilder.SOFFIT_Y: the same at a skyway's ends
BARN_H = 4.4                             # CountryBuilder.BARN_Y: the same at a Dutch barn's ends
SUN_RECOVER_M = 4.0                      # a sun break this long splits an open span for span-crossable
PORCH_W = 2.6                            # CountryBuilder.PORCH_W
INN_DOOR = 4.0                           # CountryBuilder.INN_DOOR
SKYWAY_TARGET = 0.6                      # a skyway street keeps at least this share of end_x under cover
WASH_S = 11.0 / 12.0                     # Track.WASH_S: seconds a sheet falls on any one spot
WIND_SLANT = 0.9                         # Level.rain_dir: sideways rain per unit of wind
GUST_MAX = 1.4                           # Level.wind: gusts scale wind by up to 1 + 0.4
BODY_HALF_M = 0.3
GUTTER_HALF_M = 0.6
CAR_THREAT_M = 10.5                      # headlights start this far before a car crossing


def porch_span(lot):
    """Local (x0, x1) of a `porch` lot's porch, as CountryBuilder.porch_span: its `porch` field, else
    PORCH_W centred on its door."""
    w = float(lot["w"])
    if "porch" in lot:
        return (min(max(float(lot["porch"][0]), 0.0), w), min(max(float(lot["porch"][1]), 0.0), w))
    door = INN_DOOR if lot.get("style") == "inn" else float(lot.get("door", w / 2))
    a = min(max(door - PORCH_W / 2, 0.0), max(w - PORCH_W, 0.0))
    return (a, min(a + PORCH_W, w))


def _subtract(runs, zones):
    for z0, z1 in zones:
        out = []
        for a, b in runs:
            if z1 <= a or z0 >= b:
                out.append((a, b))
                continue
            if z0 > a:
                out.append((a, z0))
            if z1 < b:
                out.append((z1, b))
        runs = out
    return runs


def safe_runs(st):
    """[(start, end)] of cover that is dry for a walker: awnings merged where lots touch, shrunk at each
    end by the wind slant plus half a body, with gutters, car-threat zones and train wash cut
    out (a checkpoint restores the level clock, so a train can be on its way)."""
    spans = sorted((a, b) for a, b, _ in st.covers)
    merged = []
    for a, b in spans:
        if merged and a <= merged[-1][1] + 1e-6:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])

    def margin(x):
        w = abs(st.wind(x)) * (GUST_MAX if st.gusts else 1.0)
        return st.cover_h(x) * WIND_SLANT * w + BODY_HALF_M

    runs = [(a if a <= 0.0 else a + margin(a), b - margin(b)) for a, b in merged]
    zones = [(a - BODY_HALF_M, b + BODY_HALF_M) for a, b in st.wash]
    for f in st.features:
        x = float(f["x"])
        w = float(f.get("w", 1.0))
        if f["type"] == "gutter":
            zones.append((x - GUTTER_HALF_M, x + GUTTER_HALF_M))
    for c in st.d.get("crossings", []):
        if c.get("car"):
            zones.append((float(c["x"]) - CAR_THREAT_M, float(c["x"]) + float(c["w"])))
    return [(a, b) for a, b in _subtract(runs, zones) if b > a]


def clear_ahead(st, x):
    """Metres from x to the first hazard (cover edge, gutter, car threat, wash); 0 when x is not safe."""
    for a, b in safe_runs(st):
        if a <= x <= b:
            return b - x
    return 0.0


def solve_checkpoints(st):
    """One checkpoint per CHECKPOINT_TARGETS: a safe run's start, nearest the target, ascending."""
    cands = []
    for a, b in safe_runs(st):
        c = round(a + ENTRY_M, 2)
        if clear_ahead(st, c) >= CLEAR_M:
            cands.append(c)
    out = []
    for f in CHECKPOINT_TARGETS:
        t = f * st.end_x

        def cost(c):
            return abs(c - t) + (0.0 if clear_ahead(st, c) >= PREFER_CLEAR_M else PREFER_PENALTY_M)

        pool = [c for c in cands if abs(c - t) <= CHECKPOINT_TOL * st.end_x and (not out or c > out[-1])]
        if not pool:
            raise ValueError(f"{st.d['id']}: no safe checkpoint within {CHECKPOINT_TOL:.0%} of end_x around "
                             f"{t:.1f} m (target {f:.0%}); add {CLEAR_M:.0f} m of dry cover or set s.checkpoints")
        out.append(min(pool, key=cost))
    return out


# ---------------------------------------------------------------------------------------------
# report

START_COVER_M = 20.0
RAMP_TOL = 0.20
WASH_W = 5.2      # a metre the wash can land on scores this x its wash duty of a metre of open sky at rain 1
HOLD_TOL = 0.30


# Scripted threats the preview can't simulate carry a street's pacing where cover has taken the rain
# away (a street with skyways) or where the sun dries off what the rain does (the suburbs and the
# country), so there they are weighed in like gutters, per 100 m of the decile they land in. Other
# streets were paced on the rain alone and leave them out.
# A helicopter's wash meets a walking walker some metres past its trigger (HELI_MEET_M, by direction);
# a hover adds its seconds. The courier's tail is spread over his walk from doorway to door.
HELI_W = 3.0
HELI_HOVER_W = 1.0          # per second hovering
HELI_MEET_M = {-1: 8.0, 1: 12.0}
HENCHMAN_W = 2.5
DRIVE_BY_W = 2.5
ATTACKER_W = 2.0
COURIER_W = 3.0             # per 100 m of his walk
COURIER_STOP_W = 1.0
QUIET_DRIVE_BY_W = 3.0      # no warning, so it lands
SQUALL_W = 2.0
SQUALL_PER_S_W = 0.5        # per second the gust blows
SQUALL_MEET_M = 2.6         # the gust reaches a walking walker about 2 s past its trigger
RUNNER_W = 2.0


def weighs_threats(st):
    """Whether this street's pacing counts its scripted threats (see threats())."""
    return bool(st.d.get("skyways")) or st.d.get("aesthetic") in ("suburban", "country")


def threats(st):
    """[(x0, x1, weight)] of the street's scripted threats, a point threat as x0 == x1."""
    out = []
    for h in st.d.get("helicopters", []):
        if "hover_x" in h:
            hx = float(h["hover_x"])
            out.append((hx, hx, HELI_W + HELI_HOVER_W * float(h.get("hover_s", 3.0))))
        else:
            hx = float(h["x"]) + HELI_MEET_M.get(int(h.get("dir", -1)), 8.0)
            out.append((hx, hx, HELI_W))
    out += [(float(h["x"]), float(h["x"]), HENCHMAN_W) for h in st.d.get("henchmen", [])]
    out += [(float(d["x"]), float(d["x"]), QUIET_DRIVE_BY_W if d.get("quiet") else DRIVE_BY_W)
            for d in st.d.get("drive_bys", [])]
    for q in st.d.get("squalls", []):
        qx = float(q["x"]) + SQUALL_MEET_M
        out.append((qx, qx, SQUALL_W + SQUALL_PER_S_W * float(q.get("dur", 3.0))))
    out += [(float(r["x"]), float(r["x"]), RUNNER_W) for r in st.d.get("runners", [])]
    out += [(float(a["x"]), float(a["x"]), ATTACKER_W) for a in st.d.get("attackers", [])]
    c = st.d.get("courier")
    if c:
        a0, a1 = float(c.get("appear_x", 20.0)), float(c.get("door_x", st.end_x))
        out.append((a0, a1, COURIER_W * (a1 - a0) / 100.0))
        out += [(float(w["x"]), float(w["x"]), COURIER_STOP_W) for w in c.get("stops", [])]
    return out


def _threat_in(t, a, b):
    """The share of threat t's weight that lands in [a, b)."""
    x0, x1, w = t
    if x1 <= x0:
        return w if a <= x0 < b else 0.0
    return w * max(0.0, min(b, x1) - max(a, x0)) / (x1 - x0)


def decile_table(st, tun):
    thr = threats(st) if weighs_threats(st) else []
    spans = st.open_spans()
    rows = []
    step = st.end_x / 10.0
    for k in range(10):
        a, b = k * step, (k + 1) * step
        n = max(int((b - a) / STEP), 1)
        xs = [a + (i + 0.5) * (b - a) / n for i in range(n)]
        open_frac = sum(1 for x in xs if not st.covered(x) and not st.treed(x)) / n
        trees = sum(1 for x in xs if st.treed(x)) / n
        longest = max([min(b, s1) - max(a, s0) for s0, s1 in spans if s1 > a and s0 < b] + [0.0])
        longest_full = max([s1 - s0 for s0, s1 in spans if s1 > a and s0 < b] + [0.0])
        g = sum(1 for f in st.features if f["type"] == "gutter" and a <= f["x"] < b)
        p = sum(1 for f in st.features if f["type"] == "puddle" and a <= f["x"] < b)
        c = sum(1 for c0, c1 in st.crossings if a <= c0 < b)
        rain = sum(st.rain(x) for x in xs) / n
        wind = sum(abs(st.wind(x)) for x in xs) / n
        per100 = 100.0 / (b - a)
        wash = sum(1 for x in xs if st.washed(x)) / n
        diff = 10.0 * sum(st.exposure(x) * st.rain(x) * (1 + abs(st.wind(x))) for x in xs) / n \
            + 10.0 * WASH_W * st.wash_duty * wash + (0.5 * g + 0.4 * c) * per100
        threat = sum(_threat_in(t, a, b) for t in thr) * per100
        diff += threat
        rows.append(dict(a=a, b=b, open=open_frac, trees=trees, longest=longest, longest_full=longest_full,
                         g=g, p=p, c=c, rain=rain, wind=wind, wash=wash, threat=threat, diff=diff))
    return rows


DIFF_FORMULA = ("difficulty = 10 * mean(open_sky * rain * (1 + |wind|)) "
                f"+ 10 * {WASH_W} * duty * wash + (0.5*gutters + 0.4*crossings) per 100 m, per decile "
                "of end_x (rain is 0 in sun breaks; wash = share of track with no lot cover (a railway's arches count as "
                "lot cover); duty = share of the "
                "time a sheet falls on a spot, Track.WASH_S over the mean train gap) + threat (skyway, suburban and country streets only, scripted: "
                f"{HELI_W:g} per helicopter pass + {HELI_HOVER_W:g}/s hovering, {HENCHMAN_W:g} per henchman, "
                f"{DRIVE_BY_W:g} per drive-by ({QUIET_DRIVE_BY_W:g} quiet), {ATTACKER_W:g} per pursuer, the courier's "
                f"tail {COURIER_W:g} per 100 m + {COURIER_STOP_W:g} per window stop, {SQUALL_W:g} per gust + "
                f"{SQUALL_PER_S_W:g}/s, {RUNNER_W:g} per runner) per 100 m")


def crossable_m(tun, wind):
    """Metres walkable with the umbrella up from a full bar to empty (no hurry), at a given |wind|."""
    drain = tun["stamina_drain_umbrella"] + tun["stamina_drain_wind"] * wind * wind
    secs = tun["stamina_max"] / drain
    return secs * tun["walk_speed_umbrella"], secs, drain


def run_checks(st, tun, rows):
    checks = []

    first_open = [s for s in st.uncovered_spans() if s[0] < START_COVER_M]
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
    for s0, s1 in st.recovery_spans() or [(0.0, 0.0)]:
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
               f"(DESIGN §6 / tunables stamina_*), so shorten the span or put cover inside it")
    checks.append(("span-crossable", ok, msg))

    cps = [float(c) for c in st.d.get("checkpoints", [])]
    rows_cp = [(c, f * st.end_x, clear_ahead(st, c)) for c, f in zip(cps, CHECKPOINT_TARGETS)]
    problems = []
    if len(cps) != len(CHECKPOINT_TARGETS):
        problems.append(f"{len(cps)} checkpoints, expected {len(CHECKPOINT_TARGETS)}")
    if cps != sorted(set(cps)):
        problems.append("checkpoints are not strictly ascending")
    for i, (c, t, clear) in enumerate(rows_cp, 1):
        if abs(c - t) > CHECKPOINT_TOL * st.end_x:
            problems.append(f"#{i} at {c:.1f} m is {abs(c - t):.1f} m from its target {t:.1f} m (tolerance "
                            f"{CHECKPOINT_TOL * st.end_x:.1f} m)")
        if clear < CLEAR_M:
            problems.append(f"#{i} at {c:.1f} m has {clear:.1f} m of dry cover ahead (need {CLEAR_M:.0f} m)")
    detail = "; ".join(f"#{i} x={c:.2f} target={t:.1f} clear-ahead={clear:.1f} m" for i, (c, t, clear) in enumerate(rows_cp, 1))
    ok = not problems
    msg = detail if ok else ("; ".join(problems) + f". A failed player resumes at a checkpoint, so it must sit "
                             f"under cover with {CLEAR_M:.0f} m of dry stretch ahead: " + detail)
    checks.append(("checkpoints-safe", ok, msg))

    if st.track:
        clash = [f"lamp_post at {float(p['x']):.1f} m" for p in st.d.get("props", [])
                 if p["id"] == "lamp_post" and st.track[0] <= float(p["x"]) <= st.track[1]]
        clash += [f"{lot['cover']} at {float(lot['x']):.1f} m" for lot in st.d.get("lots", [])
                  if lot.get("cover") in ("balcony", "arcade")
                  and st.track[0] < float(lot["x"]) + float(lot["w"]) and st.track[1] > float(lot["x"])]
        clash += [f"gutter at {float(f['x']):.1f} m under a deck" for f in st.features
                  if f["type"] == "gutter" and st.under_deck(float(f["x"]))]
        ok = not clash
        lamps = "hang a bracket_lamp from the viaduct" if st.railway else "the beam carries lamps"
        msg = ("no lamp posts, balconies or arcades under the track, no gutters under a deck" if ok else
               "; ".join(clash) + ". The train runs below lamp-post heads and balcony and arcade slabs, and a "
               "deck sits where a gutter's downpipe reaches out, so they pass through each other: drop the lamp "
               f"post ({lamps}), use an awning, or move the gutter off the deck")
        checks.append(("track-clearance", ok, msg))

    if st.skyways:
        clash = [f"lamp_post at {float(p['x']):.1f} m" for p in st.d.get("props", [])
                 if p["id"] == "lamp_post" and st.under_skyway(float(p["x"]))]
        clash += [f"{lot['cover']} at {float(lot['x']):.1f} m" for lot in st.d.get("lots", [])
                  if lot.get("cover") in ("balcony", "arcade")
                  and any(a < float(lot["x"]) + float(lot["w"]) and b > float(lot["x"]) for a, b in st.skyways)]
        ok = not clash
        msg = ("no lamp posts, balconies or arcades under a skyway" if ok else
               "; ".join(clash) + ". A skyway's floor is at 4.45 m over the pavement out to 3.3 m: a lamp post's "
               "head and a balcony's rail stand up through it. Its soffit lights the pavement; use awnings or no cover")
        checks.append(("skyway-clearance", ok, msg))
    return checks


def print_report(st, tun, rows, checks, name):
    print(f"== {name}: end_x {st.end_x:.1f} m, {len(st.open_spans())} open spans, "
          f"gusts {'yes' if st.gusts else 'no'} ==")
    trees = bool(st.trees)
    print(f"{'decile':>6} {'metres':>11} {'open':>5} " + (f"{'trees':>5} " if trees else "")
          + f"{'longest':>8} {'gut':>3} {'pud':>3} {'xing':>4} "
          f"{'rain':>5} {'|wind|':>6} {'wash':>5} {'threat':>6} {'diff':>6}")
    for k, r in enumerate(rows, 1):
        longest = f"{r['longest_full']:.1f}"
        print(f"{k:>6} {r['a']:>5.0f}-{r['b']:<5.0f} {r['open']:>5.0%} " + (f"{r['trees']:>5.0%} " if trees else "")
              + f"{longest:>8} {r['g']:>3} {r['p']:>3} "
              f"{r['c']:>4} {r['rain']:>5.2f} {r['wind']:>6.2f} {r['wash']:>5.0%} {r['threat']:>6.1f} {r['diff']:>6.1f}")
    print(DIFF_FORMULA)
    if st.d.get("courier"):
        print("courier: the scripted pedestrian is not simulated here; tools/preview.sh is the judge of tailing him")
    helis = st.d.get("helicopters", [])
    if helis:
        print(f"helicopters: {len(helis)} triggered at x " + ", ".join(f"{float(h['x']):.0f}" for h in helis)
              + ("; weighed in as a threat (not simulated)" if weighs_threats(st) else "; their rotor wash is not scored here")
              + ", tools/preview.sh is the judge")
    squalls = st.d.get("squalls", [])
    if squalls:
        print(f"squalls: {len(squalls)} triggered at x " + ", ".join(f"{float(q['x']):.0f}" for q in squalls)
              + "; the gust's slant and the trees' shower are not scored here, tools/preview.sh is the judge")
    print("longest = full length of the longest open span touching the decile (may extend past it)")
    share, sky = st.cover_share()
    line = f"cover: {share:.0%} of end_x under cover ({sky:.0%} under a skyway)"
    if st.skyways:
        line += f"; a skyway street aims for at least {SKYWAY_TARGET:.0%}" + (" (short)" if share < SKYWAY_TARGET else "")
    print(line)
    if st.country:
        print(f"country: a tree's crown lets {st.tree_leak:.0%} of the rain through, so a metre under trees scores that "
              f"share of open sky; trees and sun breaks of {SUN_RECOVER_M:.0f} m or more split spans for span-crossable")
    if st.country:
        c, s, t, o = st.shares()
        print(f"country: of end_x {c:.0%} under full cover, {t:.0%} under trees ({st.tree_leak:.0%} of the rain gets "
              f"through), {s:.0%} in sun, {o:.0%} open rain")
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


def heli_glyph(d, h, x0m, x1m, X, y):
    """A helicopter's trigger: a small silhouette at x with an arrow the way it flies, and a ring
    under hover_x if it stops there."""
    hx, hdir = float(h["x"]), (-1 if float(h.get("dir", -1)) < 0 else 1)
    if x0m <= hx <= x1m:
        cx, cy = X(hx), y + 26
        d.line([(cx, y + 2), (cx, y + H_FEAT_PX)], fill=HELI_C, width=1)
        d.ellipse([cx - 7, cy - 4, cx + 7, cy + 4], fill=HELI_C)
        d.line([(cx - 9 * hdir, cy), (cx - 17 * hdir, cy - 2)], fill=HELI_C, width=2)
        d.line([(cx - 11, cy - 7), (cx + 11, cy - 7)], fill=HELI_C, width=2)
        d.line([(cx, cy - 7), (cx, cy - 4)], fill=HELI_C, width=2)
        ax = cx + 14 * hdir
        d.line([(cx + 9 * hdir, cy - 12), (ax, cy - 12)], fill=HELI_C, width=2)
        d.polygon([(ax, cy - 15), (ax, cy - 9), (ax + 4 * hdir, cy - 12)], fill=HELI_C)
    if "hover_x" in h and x0m <= float(h["hover_x"]) <= x1m:
        vx = X(float(h["hover_x"]))
        d.ellipse([vx - 8, y + 4, vx + 8, y + 12], outline=HELI_C, width=2)
        d.text((vx, y + 20), f"{float(h.get('hover_s', 0)):.0f}s", fill=HELI_C, font=font(9, True), anchor="mm")


def squall_glyph(d, sq, st, x0m, x1m, X, y):
    """A squall's trigger: three gust lines at x with an arrow the way it blows, and a bracket over
    where it blows on a walking walker (from its front meeting him to its tail passing him)."""
    sx, dur = float(sq["x"]), float(sq.get("dur", 3.0))
    gdir = 1 if st.wind(sx) > 0 else -1
    # Front: sx - gdir*OFF + gdir*V*t meets him at sx + WALK*t; its tail passes him dur*V/(V - gdir*WALK) later.
    t_meet = SQUALL_OFF / (SQUALL_SPEED - gdir * WALK)
    a = sx + WALK * t_meet
    b = a + WALK * dur * SQUALL_SPEED / (SQUALL_SPEED - gdir * WALK)
    if b > x0m and a < x1m:
        xa, xb = X(max(a, x0m)), X(min(b, x1m))
        d.line([(xa, y + 33), (xb, y + 33)], fill=GUST_C, width=3)
        d.line([(xa, y + 29), (xa, y + 37)], fill=GUST_C, width=1)
        d.line([(xb, y + 29), (xb, y + 37)], fill=GUST_C, width=1)
    if x0m <= sx <= x1m:
        cx = X(sx)
        d.line([(cx, y + 2), (cx, y + H_FEAT_PX - 6)], fill=GUST_C, width=1)
        for yy, ln in ((9, 14), (15, 22), (21, 12)):
            d.line([(cx - gdir * ln / 2, y + yy), (cx + gdir * ln / 2, y + yy)], fill=GUST_C, width=2)
        tip = cx + gdir * 13
        d.polygon([(tip, y + 11), (tip, y + 19), (tip + gdir * 5, y + 15)], fill=GUST_C)
        d.text((cx - gdir * 14, y + 26), f"gust {dur:g}s", fill=GUST_C, font=font(9, True), anchor="lm" if gdir < 0 else "rm")


H_FEAT_PX = 36

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
        for a, b, kind in sorted(st.covers, key=lambda c: c[2] in ("deck", "skyway")):
            if b > x0m and a < x1m:
                # A deck or skyway is a band across the top, so the lot cover beneath it still shows.
                y1 = y + 9 if kind in ("deck", "skyway") else y + H_COVER - 4
                d.rectangle([X(max(a, x0m)), y + 2, X(min(b, x1m)), y1], fill=COVER_COLORS[kind])
        for s0, s1 in st.open_spans():
            if s1 > x0m and s0 < x1m and s1 - s0 >= 5.0:
                xa, xb = X(max(s0, x0m)), X(min(s1, x1m))
                d.text(((xa + xb) / 2, y + 12), f"{s1 - s0:.0f} m open", fill=(40, 70, 120), font=font(11), anchor="mm")
        for i, c in enumerate(st.d.get("checkpoints", []), 1):
            if x0m <= c <= x1m:
                d.line([(X(c), y - 2), (X(c), y + H_COVER)], fill=(20, 140, 70), width=3)
                d.text((X(c) + 3, y + 7), f"cp{i}", fill=(20, 140, 70), font=font(10, True), anchor="lm")
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
        for a, b in st.wash:
            if b > x0m and a < x1m:
                xa, xb = X(max(a, x0m)), X(min(b, x1m))
                d.rectangle([xa, y + 2, xb, y + 8], fill=WASH_C)
                for sx in range(int(xa) + 3, int(xb), 7):
                    d.line([(sx, y + 8), (sx, y + 14)], fill=WASH_C, width=1)
                if xb - xa > 50:
                    d.text(((xa + xb) / 2, y + 5), "train wash", fill=(255, 255, 255), font=font(9, True), anchor="mm")
        for h in st.d.get("helicopters", []):
            heli_glyph(d, h, x0m, x1m, X, y)
        for sq in st.d.get("squalls", []):
            squall_glyph(d, sq, st, x0m, x1m, X, y)
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
                    # x can step back: he steers back to the inn door if he overshoots it.
                    xa, xb = sorted((X(a_["x"]), X(b_["x"])))
                    if a_["open"] > 0.5:
                        d.rectangle([xa, y + 3, xb, y + 6], fill=(40, 60, 90))
                    if a_["hurry"] > 0.05:
                        d.rectangle([xa, y + H_TR - 7, xb, y + H_TR - 4], fill=(240, 150, 30))
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
    x += 170
    d.rectangle([x, ly + 2, x + 22, ly + 8], fill=WASH_C)
    d.text((x + 28, ly + 6), "train wash (track, no lot cover)", fill=INK, font=font(12), anchor="lm")
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
    outcome = ("reached the door" if last["state"] != 2 else
               "SOAKED" if last["wet"] >= tun["wet_max"] - 0.01 else "FAILED dry (a scripted fail: lost, made or shot)")
    return (f"{label}: final wet {last['wet']:.1f}/{tun['wet_max']:.0f} at x={last['x']:.0f} t={last['t']:.0f}s; "
            f"rain {s['wet_rain']:.1f} gutter {s['wet_gutter']:.1f} "
            f"splash {s['wet_splash']:.1f} wash {s.get('wet_wash', 0.0):.1f} rotor {s.get('wet_rotor', 0.0):.1f} "
            f"shower {s.get('wet_shower', 0.0):.1f} dried {s['dried']:.1f}; min stamina "
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
