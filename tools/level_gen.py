#!/usr/bin/env python3
"""Generate first-draft fixed level layouts into levels/*.json.

The game never generates levels at runtime: this script is run by a developer, the output is
committed, and may then be hand-edited. Re-running overwrites the drafts (use --only to limit); levels
marked "authored": true are skipped unless --force.

    python3 tools/level_gen.py              # all levels
    python3 tools/level_gen.py --only main_street

Layout grammar (see docs/DESIGN.md §7): a street of contiguous *lots* (building frontages), interrupted
by *crossings* (side streets), plus point/zone *features* (gutter, puddle, vent, sun, fire_barrel, car).
"""
import argparse
import json
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "levels"

# The map graph (levels/index.json) is hand-edited; this script only writes street layouts.
LEVELS = {
    "main_street": dict(seed=1961, length=255, neon=0.0, wind=(0.0, 0.0), cars=False, rain=(0.75, 1.15),
                        d=(0.0, 0.75), lit=0.3, crossing_every=(55, 75), sun=1, aesthetic="rundown"),
    "canal_row": dict(seed=1962, length=320, neon=0.0, wind=(0.0, 0.35), cars=False, rain=(0.85, 1.2),
                      d=(0.1, 0.85), lit=0.15, crossing_every=(60, 85), sun=1, aesthetic="industrial",
                      vacant=0.18),
    "arcade_lane": dict(seed=1963, length=330, neon=0.35, wind=(0.0, 0.12), cars=True, rain=(0.8, 1.12),
                        d=(0.1, 0.78), lit=0.45, crossing_every=(45, 60), sun=1, aesthetic="rundown_neon"),
    "neon_junction": dict(seed=1964, length=420, neon=0.85, wind=(0.1, 0.38), cars=True, rain=(0.85, 1.15),
                          d=(0.2, 0.9), lit=0.7, crossing_every=(45, 60), sun=0, aesthetic="neon", gusts=True),
    "mill_road": dict(seed=1965, length=420, neon=0.0, wind=(-0.1, -0.42), cars=True, rain=(0.8, 1.2),
                      d=(0.2, 1.0), lit=0.1, crossing_every=(70, 95), sun=3, aesthetic="outskirts",
                      vacant=0.3, gusts=True),
}

SHOP_NAMES = ["DINER", "LAUNDROMAT", "PAWN", "BARBER", "NEWS", "DRUGS", "SHOES", "RADIO & TV", "HARDWARE",
              "BAKERY", "TAILOR", "DELI", "LIQUOR", "CAFE", "BOOKS", "TOYS", "FLORIST", "LOANS", "CLEANERS",
              "RECORDS", "CHECKS CASHED", "SODA", "TOBACCO", "WATCH REPAIR", "PHOTO", "GROCERY", "GIFTS"]
NEON_NAMES = ["NOODLES", "ARCADE", "CYBER CAFE", "KARAOKE", "ROBOTICS", "HOLO-TV", "SYNTH", "VR DEN",
              "CHROME", "JUICE BAR", "PACHINKO", "NEO DINER", "24 HR", "PARTS & MODS", "RAMEN", "ATOMIC",
              "JETSET", "ORBIT", "LASER TAG", "DATA DEN", "VOLTS", "SATELLITE", "COMET", "FUSION",
              "MAG-LEV", "HYPER", "PIXEL", "ROCKET", "NEON NITES", "CAPSULE", "STARLITE", "TUBES"]
INDUSTRIAL_NAMES = ["FREIGHT", "MARINE SUPPLY", "COLD STORAGE", "ROPE & CHAIN", "SHIP CHANDLER", "BAIT",
                    "MACHINE SHOP", "SALVAGE", "DOCK 7", "TIMBER", "WELDING", "FEED & SEED", "TIRES",
                    "AUTO PARTS", "PLUMBING", "TRUCK STOP", "MOTEL", "GARAGE", "SCRAP METAL"]


def lerp(a, b, t):
    return a + (b - a) * t


def round_to(v, step=0.5):
    return round(v / step) * step


def gen_level(lid, cfg):
    rng = random.Random(cfg["seed"])
    L = cfg["length"]
    lots, crossings, features = [], [], []
    names_used = set()

    def difficulty(x):
        p = x / L
        return lerp(cfg["d"][0], cfg["d"][1], min(1.0, p / 0.5))

    recent = []

    def pick_name():
        if rng.random() < cfg["neon"]:
            pool = NEON_NAMES
        elif cfg["aesthetic"] in ("industrial", "outskirts") and rng.random() < 0.6:
            pool = INDUSTRIAL_NAMES
        else:
            pool = SHOP_NAMES
        fresh = [n for n in pool if n not in names_used]
        n = rng.choice(fresh) if fresh else rng.choice([n for n in pool if n not in recent[-8:]] or pool)
        names_used.add(n)
        recent.append(n)
        return n

    def building_style(lit_bias=0.0, covered=True):
        if cfg["aesthetic"] in ("industrial", "outskirts") and rng.random() < (0.4 if cfg["aesthetic"] == "outskirts" else 0.45):
            return "warehouse" if covered or rng.random() < 0.4 else "loading_dock"
        r = rng.random()
        lit = cfg["lit"] + lit_bias
        if r < lit:
            return "shop_lit"
        r = rng.random()
        if r < 0.35:
            return "shuttered"
        if r < 0.55:
            return "boarded"
        if r < 0.75:
            return "shop_dark"
        if r < 0.9:
            return "wall"
        return "doorway"

    def add_lot(x, w, cover, style=None, tears=None, **extra):
        style = style or building_style()
        lot = {"x": round(x, 2), "w": round(w, 2), "style": style, "cover": cover,
               "floors": (rng.choice([1, 1, 2]) if cfg["aesthetic"] in ("industrial", "outskirts")
                          else rng.choice([1, 2, 2, 3, 3, 4])) if style != "vacant" else 0}
        if style in ("shop_lit", "shop_dark", "inn") or (style == "shuttered" and rng.random() < 0.5):
            lot["sign"] = "THE RAINY DAY INN" if style == "inn" else pick_name()
        if cover == "awning":
            lot["awning_color"] = rng.choice(["red", "green", "blue", "brown", "orange", "teal"])
        if tears:
            lot["tears"] = tears
        if cfg["neon"] > 0 and rng.random() < cfg["neon"] * 0.8 and style not in ("vacant", "inn"):
            lot["neon"] = True
            if "sign" not in lot:
                lot["sign"] = pick_name() if rng.random() < 0.3 else rng.choice([n for n in NEON_NAMES if n not in recent[-8:]])
            recent.append(lot["sign"])
        lot.update(extra)
        lots.append(lot)
        return lot

    x = 0.0
    # --- intro: continuous cover, a lit shop or two -----------------------------------------
    intro_end = 14.0
    while x < intro_end:
        w = round_to(rng.uniform(4, 7))
        add_lot(x, w, "awning", style=building_style(0.3))
        x += w

    next_crossing = x + rng.uniform(*cfg["crossing_every"]) * 0.7
    sun_left = cfg["sun"]
    sun_slots = sorted(rng.uniform(0.25, 0.85) * L for _ in range(sun_left))
    end_x = L - 10.0

    while x < end_x - 8:
        d = difficulty(x)
        # ---- covered run ---------------------------------------------------------------
        run_len = rng.uniform(lerp(14, 5, d), lerp(26, 13, d))
        run_end = min(x + run_len, end_x)
        first = True
        while x < run_end - 1.5:
            w = round_to(min(rng.uniform(3, 8), max(3.0, run_end - x)))
            cover = "awning" if rng.random() > 0.12 else rng.choice(["balcony", "arcade"])
            tears = None
            if cover == "awning" and w >= 4 and rng.random() < 0.08 + 0.4 * d and not first:
                tw = round_to(rng.uniform(0.6, lerp(1.0, 2.2, d)), 0.1)
                tx = round(round_to(rng.uniform(0.8, w - tw - 0.8), 0.1), 2)
                tears = [[tx, round(tx + tw, 2)]]
            if cfg["aesthetic"] in ("industrial", "outskirts") and rng.random() < 0.06 and run_end - x >= 8:
                w = 8.0
                lot = add_lot(x, w, "canopy", style="gas_station", floors=0)
                x += w
                first = False
                continue
            lot = add_lot(x, w, cover, tears=tears)
            # warm vent on a covered lot
            if rng.random() < 0.08 and cover != "arcade":
                features.append({"type": "vent", "x": round(x + w * 0.5, 2), "w": 1.6})
            x += w
            first = False
        # gutter stream at the end of a covered run
        if rng.random() < 0.15 + 0.5 * d:
            features.append({"type": "gutter", "x": round(x - 0.25, 2)})
        if x >= end_x - 8:
            break

        # ---- gap ----------------------------------------------------------------------
        if x >= next_crossing:
            cw = round_to(rng.uniform(8, 12))
            cross = {"x": round(x, 2), "w": cw}
            if cfg["cars"] and rng.random() < 0.45 + 0.5 * d:
                cross["car"] = True
                features.append({"type": "puddle", "x": round(x + 1.2, 2), "w": 1.6, "deep": True})
            elif rng.random() < 0.5:
                features.append({"type": "puddle", "x": round(x + rng.uniform(2, cw - 2), 2), "w": 1.2})
            crossings.append(cross)
            x += cw
            next_crossing = x + rng.uniform(*cfg["crossing_every"])
            continue

        if sun_slots and x >= sun_slots[0]:
            sun_slots.pop(0)
            sw = round_to(rng.uniform(5, 8))
            add_lot(x, sw, "none", style="vacant" if rng.random() < 0.5 else None)
            features.append({"type": "sun", "x": round(x + 0.5, 2), "w": sw - 1.0})
            x += sw
            continue

        r = rng.random()
        if r < lerp(0.65, 0.3, d):
            gw = round_to(rng.uniform(2.0, 3.0))       # short gap
        else:
            gw = round_to(rng.uniform(5.0 + 2.0 * d, 7.0 + 7 * d))  # long gap (5-14 m)
        vacant = rng.random() < cfg.get("vacant", 0.08)
        gx = x
        while x < gx + gw - 0.4:
            w = min(round_to(rng.uniform(3, 8)), gx + gw - x)
            if w < 1.5 and lots:
                lots[-1]["w"] = round(lots[-1]["w"] + w, 2)
                x += w
                break
            st = "vacant" if vacant else building_style(covered=False)
            if st == "warehouse":
                st = "loading_dock" if w >= 8 else "wall"
            if st == "loading_dock" and w < 8:
                st = "wall"
            add_lot(x, w, "none", style=st)
            x += w
        if rng.random() < 0.3 + 0.3 * d:
            features.append({"type": "puddle", "x": round(gx + rng.uniform(0.6, max(0.7, gw - 0.6)), 2), "w": 1.0})
        if gw > 4 and rng.random() < 0.15:
            features.append({"type": "fire_barrel", "x": round(gx + gw * 0.5, 2), "w": 1.8})

    # ---- final stretch + inn -----------------------------------------------------------
    while x < end_x:
        w = round_to(min(rng.uniform(4, 6), max(3.0, end_x - x)))
        add_lot(x, w, "awning")
        x += w
    add_lot(x, 9.0, "awning", style="inn", floors=3, awning_color="red")
    door_x = x + 4.5
    x += 9.0
    add_lot(x, 8.0, "awning", style="shop_dark")
    x += 8.0

    # Lamp posts every ~14 m on the curb (purely visual, no cover).
    props = []
    px = 6.0
    while px < x:
        props.append({"id": "lamp_post", "x": round(px, 2)})
        px += rng.uniform(12, 18)
    for _ in range(int(x / 20)):
        props.append({"id": rng.choice(["hydrant", "trash_can", "newspaper_box", "bench", "mailbox",
                                         "parking_meter"]), "x": round(rng.uniform(4, x - 4), 2)})
    clutter = ["trash_bags", "crates", "cardboard_boxes", "newspaper_box_b", "sandwich_board", "phone_booth",
               "bollard", "downpipe"]
    if cfg["aesthetic"] in ("industrial", "outskirts"):
        clutter += ["crates", "crates", "trash_bags", "chainlink_fence_4"]
    if cfg["neon"] > 0:
        clutter += ["vending_machine_a", "vending_machine_b"] * int(1 + cfg["neon"] * 3)
    for _ in range(int(x / 14)):
        props.append({"id": rng.choice(clutter), "x": round(rng.uniform(4, x - 4), 2)})
    for c in crossings:
        props.append({"id": "street_sign", "x": round(c["x"] - 0.6, 2)})

    props = [p for p in props if not any(c["x"] - 0.5 < p["x"] < c["x"] + c["w"] + 0.5 for c in crossings)]
    rain = [[0.0, cfg["rain"][0]], [0.5, cfg["rain"][1]], [1.0, cfg["rain"][1]]]
    wind = [[0.0, cfg["wind"][0]], [0.5, cfg["wind"][1]], [1.0, cfg["wind"][1]]]
    node = next(n for n in json.loads((OUT / "index.json").read_text())["nodes"] if n["id"] == lid)
    return {
        "id": lid, "name": node["name"], "blurb": node.get("blurb", ""), "aesthetic": cfg["aesthetic"],
        "neon": cfg["neon"], "length": round(x, 2), "end_x": round(door_x, 2),
        "rain": rain, "wind": wind, "gusts": cfg.get("gusts", False),
        "lots": lots, "crossings": crossings,
        "features": sorted(features, key=lambda f: f["x"]), "props": sorted(props, key=lambda p: p["x"]),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--force", action="store_true", help="also overwrite hand-authored levels")
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    for lid, cfg in LEVELS.items():
        if args.only and lid not in args.only:
            continue
        path = OUT / f"{lid}.json"
        if path.exists() and json.loads(path.read_text()).get("authored") and not args.force:
            print(f"{lid}: hand-authored, skipped (--force to overwrite)")
            continue
        lvl = gen_level(lid, cfg)
        path.write_text(json.dumps(lvl, indent=1))
        gaps = [l for l in lvl["lots"] if l["cover"] == "none"]
        print(f"{lid}: length {lvl['length']} m, {len(lvl['lots'])} lots, {len(gaps)} open lots, "
              f"{len(lvl['crossings'])} crossings, {len(lvl['features'])} features")


if __name__ == "__main__":
    main()
