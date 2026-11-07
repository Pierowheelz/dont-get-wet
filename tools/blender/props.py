"""Generate street props for the 60s main street (docs/CONTRACTS.md §3).

    blender -b --factory-startup --python tools/blender/props.py

Writes assets/props/*.glb and assets/props/props.json. Origin = base centre; front faces +Z (road).
Wall props (place = wall / wall_high) have their back on z = 0 and stick out into +Z.
car_sedan*: 60s full-size sedan facing +X, origin at the ground centre.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kitlib  # noqa: E402
from kitlib import Builder, ROOT, T, R, xf_push  # noqa: E402

OUT = os.path.join(ROOT, "assets", "props")
RES = "res://assets/props/"
PROPS = []


def register(pid, place, footprint, tags=(), era="60s", **extra):
    e = {"id": pid, "scene": RES + pid + ".glb", "place": place, "era": era,
         "footprint": [round(footprint[0], 2), round(footprint[1], 2)],
         "tags": list(tags)}
    e.update(extra)
    PROPS.append(e)


def export(B, pid):
    tris = kitlib.build_and_export(B, os.path.join(OUT, pid + ".glb"))
    print("prop %-18s tris %6d" % (pid, tris))


# ------------------------------------------------------------------------------------------------

def lamp_post():
    B = Builder("lamp_post")
    m = "metal_green"
    B.lathe([(0.0, 0.0), (0.24, 0.0), (0.24, 0.06), (0.21, 0.09), (0.21, 0.16), (0.17, 0.2), (0.16, 0.45),
             (0.18, 0.5), (0.18, 0.56), (0.13, 0.62), (0.11, 0.9), (0.13, 0.94), (0.13, 1.0), (0.085, 1.06),
             (0.075, 1.1), (0.0, 1.1)], 0, 0, m, segs=20)
    # fluted shaft: 8 thin ribs around a tapered core
    B.lathe([(0.0, 1.05), (0.075, 1.05), (0.058, 3.75), (0.0, 3.75)], 0, 0, m, segs=16)
    for k in range(8):
        a = 2 * math.pi * k / 8
        B.tube((0.07 * math.cos(a), 1.12, 0.07 * math.sin(a)), (0.056 * math.cos(a), 3.7, 0.056 * math.sin(a)), 0.012, m, segs=6)
    B.lathe([(0.0, 3.72), (0.09, 3.72), (0.11, 3.78), (0.11, 3.84), (0.08, 3.88), (0.09, 3.94), (0.13, 3.98),
             (0.13, 4.04), (0.0, 4.04)], 0, 0, m, segs=20)
    # acorn lantern
    B.lathe([(0.0, 4.02), (0.12, 4.04), (0.19, 4.16), (0.21, 4.32), (0.19, 4.48), (0.13, 4.6), (0.0, 4.63)], 0, 0, "sodium_lamp", segs=24)
    B.lathe([(0.0, 4.58), (0.16, 4.58), (0.17, 4.62), (0.1, 4.7), (0.05, 4.78), (0.03, 4.9), (0.0, 4.93)], 0, 0, m, segs=20)
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        B.tube((0.12 * math.cos(a), 4.03, 0.12 * math.sin(a)), (0.2 * math.cos(a), 4.3, 0.2 * math.sin(a)), 0.01, m, segs=6)
    B.marker("omni_sodium", (0.0, 4.25, 0.0))
    export(B, "lamp_post")
    register("lamp_post", "curb", (0.5, 0.5), ["light", "cover_none"], height=4.93)


def hydrant():
    B = Builder("hydrant")
    m = "paint_red"
    B.lathe([(0.0, 0.0), (0.17, 0.0), (0.17, 0.05), (0.14, 0.07), (0.14, 0.1), (0.115, 0.12), (0.115, 0.52),
             (0.13, 0.54), (0.13, 0.58), (0.12, 0.6), (0.11, 0.66), (0.08, 0.72), (0.035, 0.75), (0.0, 0.76)],
            0, 0, m, segs=24)
    for k in range(8):  # flange bolts
        a = 2 * math.pi * k / 8
        B.tube((0.155 * math.cos(a), 0.05, 0.155 * math.sin(a)), (0.155 * math.cos(a), 0.075, 0.155 * math.sin(a)), 0.012, "galvanized", segs=6)
    B.tube((0, 0.75, 0), (0, 0.8, 0), 0.03, "galvanized", segs=5)                   # pentagon nut
    for sx in (-1, 1):  # hose nozzles
        B.tube((0.1 * sx, 0.42, 0), (0.19 * sx, 0.42, 0), 0.045, m, segs=16)
        B.tube((0.19 * sx, 0.42, 0), (0.22 * sx, 0.42, 0), 0.052, "galvanized", segs=6)
        B.tube((0.22 * sx, 0.42, 0), (0.24 * sx, 0.42, 0), 0.02, "galvanized", segs=5)
    B.tube((0, 0.4, 0.1), (0, 0.4, 0.2), 0.065, m, segs=16)                         # pumper nozzle
    B.tube((0, 0.4, 0.2), (0, 0.4, 0.235), 0.075, "galvanized", segs=6)
    B.tube((0, 0.4, 0.235), (0, 0.4, 0.255), 0.025, "galvanized", segs=5)
    # chain
    for k in range(6):
        t = k / 5
        B.tube((0.2 * (1 - t), 0.36 - 0.08 * math.sin(t * math.pi), 0.2 * t), (0.2 * (1 - t) - 0.03, 0.355 - 0.08 * math.sin(t * math.pi), 0.2 * t + 0.03), 0.006, "galvanized", segs=5)
    export(B, "hydrant")
    register("hydrant", "curb", (0.5, 0.5), [], height=0.8)


def trash_can():
    B = Builder("trash_can")
    prof = [(0.0, 0.0), (0.24, 0.0), (0.25, 0.02)]
    y = 0.05
    for k in range(4):  # corrugation rings
        prof += [(0.255, y), (0.265, y + 0.02), (0.265, y + 0.04), (0.255, y + 0.06)]
        y += 0.17
    prof += [(0.27, 0.72), (0.28, 0.74), (0.27, 0.75), (0.0, 0.75)]
    B.lathe(prof, 0, 0, "galvanized", segs=28)
    with xf_push(B, T(0.02, 0.75, 0.01) @ R("Z", 4)):  # lid slightly askew
        B.lathe([(0.0, 0.0), (0.3, 0.0), (0.3, 0.035), (0.27, 0.05), (0.15, 0.09), (0.0, 0.1)], 0, 0, "galvanized", segs=28)
        B.tube((-0.07, 0.12, 0), (0.07, 0.12, 0), 0.012, "galvanized", segs=8)
        for sx in (-1, 1):
            B.tube((0.07 * sx, 0.09, 0), (0.07 * sx, 0.12, 0), 0.01, "galvanized", segs=6)
    for sx in (-1, 1):  # side handles
        B.tube((0.27 * sx, 0.62, -0.06), (0.3 * sx, 0.6, 0.0), 0.01, "galvanized", segs=6)
        B.tube((0.3 * sx, 0.6, 0.0), (0.27 * sx, 0.62, 0.06), 0.01, "galvanized", segs=6)
    # newspaper poking out
    with xf_push(B, T(-0.08, 0.82, 0.05) @ R("Z", 25)):
        B.box(-0.12, 0.12, -0.08, 0.08, -0.004, 0.004, "posters", 0.0)
    export(B, "trash_can")
    register("trash_can", "sidewalk", (0.6, 0.6), [], height=0.9)


def newspaper_box(pid="newspaper_box", paint="paint_yellow"):
    B = Builder(pid)
    # stand
    B.box(-0.18, 0.18, 0.0, 0.03, -0.18, 0.18, "metal_dark", 0.008)
    for sx in (-1, 1):
        B.tube((0.12 * sx, 0.03, 0.0), (0.12 * sx, 0.36, 0.0), 0.02, "metal_dark", segs=8)
    # body
    B.box(-0.26, 0.26, 0.36, 0.98, -0.22, 0.2, paint, 0.025)
    with xf_push(B, T(0, 0.98, -0.01) @ R("X", -8)):
        B.box(-0.27, 0.27, 0.0, 0.05, -0.23, 0.23, paint, 0.02)
    # window door
    B.box(-0.23, 0.23, 0.5, 0.93, 0.19, 0.215, paint, 0.012)
    B.rect_z(-0.19, 0.19, 0.6, 0.88, 0.216, "glass_dark")
    B.rect_z(-0.17, 0.17, 0.62, 0.86, 0.19, "posters", uv=(0.25, 0.5, 0.5, 1.0))
    B.box(-0.08, 0.08, 0.52, 0.56, 0.215, 0.23, "chrome", 0.006)                    # handle
    # coin mechanism
    B.box(0.06, 0.22, 0.98, 1.12, -0.05, 0.12, "galvanized", 0.015)
    B.box(0.1, 0.18, 1.06, 1.08, 0.12, 0.125, "metal_dark", 0.0)
    B.tube((0.14, 1.02, 0.12), (0.14, 1.02, 0.15), 0.018, "chrome", segs=10)
    export(B, pid)
    register(pid, "sidewalk", (0.6, 0.5), [], height=1.12)


def bench():
    B = Builder("bench")
    L = 1.8
    for sx in (-1, 1):  # cast iron ends (side profile in ZY, extruded along X)
        x = sx * (L / 2 - 0.12)
        prof = [(0.25, 0.0), (0.18, 0.0), (0.12, 0.38), (-0.16, 0.38), (-0.2, 0.0), (-0.27, 0.0), (-0.22, 0.42),
                (-0.26, 0.86), (-0.3, 0.9), (-0.22, 0.88), (-0.17, 0.44), (0.2, 0.44), (0.24, 0.62), (0.27, 0.6), (0.24, 0.42)]
        B.sweep(prof, x - 0.03, x + 0.03, "metal_dark", sharp_deg=30)
    for k in range(3):  # seat slats
        z = 0.18 - k * 0.13
        B.box(-L / 2, L / 2, 0.44, 0.475, z - 0.055, z + 0.055, "wood_dark", 0.01)
    for k in range(3):  # back slats
        y = 0.55 + k * 0.12
        zc = -0.19 - (y - 0.44) * 0.18
        with xf_push(B, T(0, y, zc) @ R("X", 10)):
            B.box(-L / 2, L / 2, -0.045, 0.045, -0.015, 0.015, "wood_dark", 0.008)
    export(B, "bench")
    register("bench", "sidewalk", (1.8, 0.6), ["seat"], height=0.92)


def mailbox():
    B = Builder("mailbox")
    m = "paint_blue"
    for sx in (-1, 1):
        for sz in (-1, 1):
            B.box(sx * 0.2 - 0.025, sx * 0.2 + 0.025, 0.0, 0.16, sz * 0.17 - 0.025, sz * 0.17 + 0.025, "metal_dark", 0.006)
    B.box(-0.26, 0.26, 0.14, 0.95, -0.23, 0.23, m, 0.025)
    # rounded top built from a tube along Z, clipped by the body below (lower half hidden inside)
    B.tube((0, 0.95, -0.23), (0, 0.95, 0.23), 0.26, m, segs=32)
    B.box(-0.27, 0.27, 0.14, 0.2, -0.24, 0.24, m, 0.01)
    # pull-down chute door + handle
    with xf_push(B, T(0, 1.02, 0.21) @ R("X", -12)):
        B.box(-0.18, 0.18, -0.07, 0.12, 0.0, 0.03, m, 0.012)
        B.box(-0.1, 0.1, -0.06, -0.035, 0.03, 0.05, "chrome", 0.006)
    B.box(-0.16, 0.16, 0.55, 0.66, 0.23, 0.24, "trim_white", 0.004)   # blank info plate
    B.box(-0.12, 0.12, 0.3, 0.42, 0.23, 0.245, m, 0.008)              # collection door
    export(B, "mailbox")
    register("mailbox", "curb", (0.6, 0.5), [], height=1.22)


def parking_meter(pid="parking_meter"):
    B = Builder(pid)
    B.lathe([(0.0, 0.0), (0.07, 0.0), (0.07, 0.03), (0.04, 0.05), (0.035, 1.05), (0.06, 1.08), (0.0, 1.1)], 0, 0, "galvanized", segs=14)
    # head
    B.box(-0.1, 0.1, 1.08, 1.32, -0.075, 0.075, "metal_green", 0.03)
    B.tube((0, 1.32, -0.075), (0, 1.32, 0.075), 0.1, "metal_green", segs=24)
    for sz in (-1, 1):
        B.tube((0, 1.33, sz * 0.075), (0, 1.33, sz * 0.09), 0.075, "chrome", segs=20)
        B.tube((0, 1.33, sz * 0.09), (0, 1.33, sz * 0.1), 0.062, "glass_dark", segs=20)
    B.box(0.09, 0.11, 1.18, 1.24, -0.02, 0.02, "chrome", 0.005)
    B.tube((0.1, 1.15, 0), (0.15, 1.15, 0), 0.018, "chrome", segs=10)
    B.box(-0.03, 0.03, 1.2, 1.24, 0.075, 0.085, "metal_dark", 0.0)
    export(B, pid)
    register(pid, "curb", (0.3, 0.3), [], height=1.42)


def street_sign():
    B = Builder("street_sign")
    B.lathe([(0.0, 0.0), (0.06, 0.0), (0.06, 0.08), (0.035, 0.12), (0.03, 3.1), (0.04, 3.12), (0.0, 3.16)], 0, 0, "metal_green", segs=12)
    for (y, ang) in ((2.75, 0), (2.95, 90)):
        with xf_push(B, T(0, y, 0) @ R("Y", ang)):
            B.box(-0.5, 0.5, -0.085, 0.085, -0.01, 0.01, "street_blade", 0.004)
            for zz in (0.0105, -0.0105):
                fz = 1 if zz > 0 else -1
                for (a, b, c, d) in ((-0.48, 0.48, 0.06, 0.07), (-0.48, 0.48, -0.07, -0.06), (-0.48, -0.47, -0.07, 0.07), (0.47, 0.48, -0.07, 0.07)):
                    B.rect_z(a, b, c, d, zz, "trim_white", facing=fz)
            B.box(-0.05, 0.05, -0.1, 0.1, -0.03, 0.03, "metal_green", 0.008)
    # a no-parking plate lower down
    B.box(-0.15, 0.15, 1.9, 2.3, 0.035, 0.045, "trim_white", 0.004)
    B.box(-0.12, 0.12, 2.12, 2.16, 0.045, 0.048, "paint_red", 0.0)
    B.box(-0.04, 0.04, 2.04, 2.08, 0.045, 0.048, "paint_red", 0.0)
    export(B, "street_sign")
    register("street_sign", "curb", (0.3, 0.3), ["blank_blades"], height=3.16)


def wall_ac_unit():
    B = Builder("wall_ac_unit")
    W, H, D = 0.66, 0.44, 0.55
    B.box(-W / 2, W / 2, 0.0, H, 0.0, D, "plastic_beige", 0.025)
    B.box(-W / 2 + 0.03, W / 2 - 0.03, 0.03, H - 0.03, D, D + 0.015, "plastic_beige", 0.01)
    for k in range(9):  # louvres
        y = 0.06 + k * 0.037
        with xf_push(B, T(0, y, D + 0.02) @ R("X", -25)):
            B.box(-W / 2 + 0.06, W / 2 - 0.06, -0.006, 0.006, -0.012, 0.012, "galvanized", 0.0)
    B.rect_z(-W / 2 + 0.05, W / 2 - 0.05, 0.05, H - 0.05, D + 0.012, "trim_dark")
    for sx in (-1, 1):  # side vent slots
        for k in range(5):
            z = 0.1 + k * 0.08
            B.box(sx * (W / 2) - 0.004, sx * (W / 2) + 0.004, 0.12, 0.34, z, z + 0.035, "trim_dark", 0.0)
    for sx in (-1, 1):  # brackets
        with xf_push(B, T(sx * 0.25, 0.0, 0.0) @ R("Y", -90)):
            B.prism_z([(0.0, 0.0), (0.0, -0.3), (0.45, -0.01), (0.45, 0.0)], -0.015, 0.015, "metal_rust", bevel=0.004)
    # rust streak + drip tray
    B.box(-0.1, 0.1, -0.02, 0.0, 0.3, 0.5, "metal_rust", 0.004)
    B.rect_z(0.12, 0.2, -0.6, 0.0, 0.003, "metal_rust")
    B.marker("vent", (0.0, H / 2, D + 0.05))
    export(B, "wall_ac_unit")
    register("wall_ac_unit", "wall_high", (0.7, 0.6), ["warm_air"], height=0.44, mount_y=2.5)


def fire_barrel():
    B = Builder("fire_barrel")
    r = 0.29
    prof = [(0.0, 0.0), (r - 0.01, 0.0), (r, 0.02), (r, 0.28), (r + 0.012, 0.29), (r + 0.012, 0.31), (r, 0.32),
            (r, 0.58), (r + 0.012, 0.59), (r + 0.012, 0.61), (r, 0.62), (r, 0.86), (r + 0.006, 0.875), (r - 0.012, 0.88),
            (r - 0.02, 0.86), (r - 0.02, 0.1), (0.0, 0.1)]
    B.lathe(prof, 0, 0, "metal_rust", segs=32)
    # glowing holes punched near the bottom
    for k in range(7):
        a = 2 * math.pi * k / 7 + 0.3
        p = (r * math.cos(a), 0.18 + 0.04 * (k % 2), -r * math.sin(a))
        q = ((r + 0.004) * math.cos(a), 0.18 + 0.04 * (k % 2), -(r + 0.004) * math.sin(a))
        B.tube(p, q, 0.028, "fire_glow", segs=8)
    # embers + charred wood
    B.lathe([(0.0, 0.7), (0.26, 0.7), (0.24, 0.76), (0.14, 0.8), (0.0, 0.82)], 0, 0, "fire_glow", segs=16)
    for k in range(5):
        a = k * 1.3
        B.tube((0.18 * math.cos(a), 0.72, 0.18 * math.sin(a)), (-0.12 * math.cos(a + 0.4), 0.95, -0.12 * math.sin(a + 0.4)), 0.03, "metal_dark", segs=6)
    B.marker("omni_fire", (0.0, 1.2, 0.0))
    B.marker("warm", (0.0, 1.0, 0.0))
    export(B, "fire_barrel")
    register("fire_barrel", "sidewalk", (0.7, 0.7), ["warm_air", "fire", "light"], height=0.95)


def downpipe(pid, H):
    B = Builder(pid)
    z = 0.09
    r = 0.05
    B.tube((0, 0.28, z), (0, H - 0.35, z), r, "galvanized", segs=14)
    # shoe (turns out to the sidewalk) — the gutter stream starts at the outlet marker
    B.tube((0, 0.34, z), (0, 0.16, z + 0.16), r, "galvanized", segs=14)
    B.tube((0, 0.16, z + 0.16), (0, 0.12, z + 0.24), r * 1.1, "galvanized", segs=14)
    B.marker("outlet", (0.0, 0.1, z + 0.26))
    # hopper head + gutter stub
    B.lathe([(0.0, H - 0.4), (r + 0.005, H - 0.4), (r + 0.01, H - 0.36), (0.0, H - 0.36)], 0, z, "galvanized", segs=14)
    B.prism_z([(-0.1, H - 0.36), (0.1, H - 0.36), (0.16, H - 0.1), (-0.16, H - 0.1)], 0.0, 0.2, "galvanized", bevel=0.01)
    B.box(-0.17, 0.17, H - 0.1, H - 0.06, 0.0, 0.21, "galvanized", 0.008)
    y = 0.8
    while y < H - 0.6:  # wall brackets
        B.box(-0.075, 0.075, y, y + 0.045, 0.0, z + r + 0.02, "metal_dark", 0.006)
        y += 1.6
    export(B, pid)
    register(pid, "wall", (0.35, 0.35), ["gutter"], height=round(H, 2), outlet=[0.0, 0.1, round(z + 0.26, 3)])


def trash_bags():
    B = Builder("trash_bags")
    rng = B.rng
    for (x, z, s) in ((0.0, 0.0, 1.0), (0.42, 0.1, 0.85), (0.2, -0.3, 0.9), (-0.35, 0.15, 0.75)):
        m = B.mark()
        h = 0.55 * s
        r = 0.27 * s
        B.lathe([(0.0, 0.0), (r * 0.7, 0.0), (r, h * 0.25), (r * 1.02, h * 0.55), (r * 0.8, h * 0.85),
                 (r * 0.25, h * 0.98), (0.06, h * 1.02), (0.05, h * 1.12), (0.0, h * 1.14)], x, z, "trash_bag", segs=14)
        B.jitter(B.new_faces(m), 0.03 * s, rng)
    export(B, "trash_bags")
    register("trash_bags", "wall", (1.1, 0.8), ["clutter"], height=0.65)


def crates():
    B = Builder("crates")
    rng = B.rng

    def crate(cx, cy, cz, ang):
        with xf_push(B, T(cx, cy, cz) @ R("Y", ang)):
            w, d, h = 0.5, 0.35, 0.3
            for k in range(3):
                y = 0.02 + k * 0.095
                for sz in (-1, 1):
                    B.box(-w / 2, w / 2, y, y + 0.07, sz * d / 2 - 0.012, sz * d / 2 + 0.012, "wood_boards", 0.004)
                for sx in (-1, 1):
                    B.box(sx * w / 2 - 0.012, sx * w / 2 + 0.012, y, y + 0.07, -d / 2, d / 2, "wood_boards", 0.004)
            for sx in (-1, 1):
                for sz in (-1, 1):
                    B.box(sx * (w / 2 - 0.03) - 0.02, sx * (w / 2 - 0.03) + 0.02, 0.0, h, sz * (d / 2 - 0.03) - 0.02, sz * (d / 2 - 0.03) + 0.02, "wood_boards", 0.004)
            B.box(-w / 2 + 0.02, w / 2 - 0.02, 0.0, 0.02, -d / 2 + 0.02, d / 2 - 0.02, "wood_boards", 0.0)
    crate(0.0, 0.0, 0.0, 3)
    crate(0.55, 0.0, 0.05, -6)
    crate(0.2, 0.3, 0.0, 12)
    # flattened cardboard leaning on them
    with xf_push(B, T(-0.35, 0.0, 0.1) @ R("Z", 12)):
        B.box(-0.02, 0.0, 0.0, 0.7, -0.3, 0.3, "cardboard", 0.004)
    export(B, "crates")
    register("crates", "wall", (1.2, 0.6), ["clutter"], height=0.6)


def bollard():
    B = Builder("bollard")
    B.lathe([(0.0, 0.0), (0.13, 0.0), (0.13, 0.05), (0.11, 0.08), (0.1, 0.7), (0.115, 0.72), (0.115, 0.76),
             (0.1, 0.8), (0.08, 0.86), (0.04, 0.9), (0.0, 0.91)], 0, 0, "metal_dark", segs=20)
    B.lathe([(0.0, 0.6), (0.106, 0.6), (0.106, 0.66), (0.0, 0.66)], 0, 0, "paint_yellow", segs=20)
    export(B, "bollard")
    register("bollard", "curb", (0.3, 0.3), [], height=0.91)


def phone_booth():
    B = Builder("phone_booth")
    W, D, H = 0.9, 0.9, 2.25
    B.box(-W / 2 - 0.03, W / 2 + 0.03, 0.0, 0.08, -D / 2 - 0.03, D / 2 + 0.03, "concrete", 0.01)
    for sx in (-1, 1):
        for sz in (-1, 1):
            B.box(sx * W / 2 - 0.04, sx * W / 2 + 0.04, 0.08, H, sz * D / 2 - 0.04, sz * D / 2 + 0.04, "aluminium", 0.012)
    B.box(-W / 2 - 0.04, W / 2 + 0.04, H, H + 0.25, -D / 2 - 0.04, D / 2 + 0.04, "aluminium", 0.02)
    B.box(-W / 2 + 0.02, W / 2 - 0.02, H + 0.05, H + 0.2, D / 2 + 0.04, D / 2 + 0.045, "lamp_bulb", 0.0)
    B.box(-W / 2 + 0.02, W / 2 - 0.02, H + 0.05, H + 0.2, -D / 2 - 0.045, -D / 2 - 0.04, "lamp_bulb", 0.0)
    B.box(-W / 2 - 0.05, W / 2 + 0.05, H + 0.25, H + 0.29, -D / 2 - 0.05, D / 2 + 0.05, "aluminium", 0.01)
    # glass sides with horizontal rails (front = folding door)
    for (fz, facing) in ((D / 2, 1), (-D / 2, -1)):
        B.rect_z(-W / 2 + 0.04, W / 2 - 0.04, 0.12, H - 0.02, fz, "glass_dirty", facing=facing)
        for y in (0.45, 1.1, 1.8):
            B.box(-W / 2 + 0.04, W / 2 - 0.04, y, y + 0.04, fz - 0.015, fz + 0.015, "aluminium", 0.005)
    for (fx, facing) in ((W / 2, 1), (-W / 2, -1)):
        B.rect_x(-D / 2 + 0.04, D / 2 - 0.04, 0.12, H - 0.02, fx, "glass_dirty", facing=facing)
        for y in (0.45, 1.1, 1.8):
            B.box(fx - 0.015, fx + 0.015, y, y + 0.04, -D / 2 + 0.04, D / 2 - 0.04, "aluminium", 0.005)
    # phone on the back wall
    B.box(-0.15, 0.15, 1.1, 1.6, -D / 2 + 0.04, -D / 2 + 0.18, "metal_dark", 0.02)
    B.box(-0.03, 0.03, 1.25, 1.5, -D / 2 + 0.18, -D / 2 + 0.24, "metal_dark", 0.015)
    B.box(-0.08, 0.08, 1.62, 1.7, -D / 2 + 0.04, -D / 2 + 0.12, "lamp_bulb", 0.005)
    B.marker("omni_lamp", (0.0, 2.2, 0.0))
    export(B, "phone_booth")
    register("phone_booth", "sidewalk", (1.0, 1.0), ["light", "shelter"], height=2.54)


def sandwich_board():
    B = Builder("sandwich_board")
    for s in (-1, 1):
        with xf_push(B, T(0, 0, 0.0) @ R("X", 12 * s)):
            B.box(-0.3, 0.3, 0.0, 0.9, s * 0.0 - 0.012, s * 0.0 + 0.012, "wood_dark", 0.006)
            fz = 0.013 * (1 if s > 0 else -1)
            B.rect_z(-0.25, 0.25, 0.08, 0.84, fz, "sign_board_dark", facing=s)
    export(B, "sandwich_board")
    register("sandwich_board", "sidewalk", (0.6, 0.45), ["clutter"], height=0.9)


def cardboard_boxes():
    B = Builder("cardboard_boxes")
    rng = B.rng
    y = 0.0
    for (w, h, d, dx, ang) in ((0.6, 0.45, 0.45, 0.0, 4), (0.5, 0.35, 0.4, 0.05, -9), (0.35, 0.3, 0.3, -0.05, 15)):
        with xf_push(B, T(dx, y, 0) @ R("Y", ang)):
            m = B.mark()
            B.box(-w / 2, w / 2, 0.0, h, -d / 2, d / 2, "cardboard", 0.015)
            B.jitter(B.new_faces(m), 0.008, rng)
            B.box(-w / 2 + 0.02, w / 2 - 0.02, h - 0.005, h + 0.004, -0.03, 0.03, "plastic_beige", 0.0)
        y += h
    export(B, "cardboard_boxes")
    register("cardboard_boxes", "wall", (0.7, 0.6), ["clutter"], height=round(y, 2))


# ------------------------------------------------------------------------------------------------
# 60s sedan
# ------------------------------------------------------------------------------------------------

def wheel(B, x, z, side):
    """side = +1 (camera side, hubcap facing +Z) or -1."""
    rot = R("X", 90 if side > 0 else -90)
    with xf_push(B, T(x, 0.36, z) @ rot):
        # tyre (axis = local Y, outer face at +Y)
        B.lathe([(0.0, -0.1), (0.24, -0.1), (0.31, -0.108), (0.345, -0.095), (0.36, -0.06), (0.362, 0.0),
                 (0.36, 0.06), (0.345, 0.095), (0.31, 0.108), (0.24, 0.11), (0.0, 0.11)], 0, 0, "rubber", segs=32)
        # whitewall ring, painted steel wheel, chrome dish hubcap
        B.lathe([(0.262, 0.1105), (0.312, 0.1105), (0.312, 0.111), (0.262, 0.111)], 0, 0, "trim_white", segs=32)
        B.lathe([(0.0, 0.106), (0.25, 0.106), (0.245, 0.116), (0.2, 0.12), (0.0, 0.12)], 0, 0, "metal_dark", segs=32)
        B.lathe([(0.0, 0.118), (0.175, 0.118), (0.18, 0.124), (0.16, 0.138), (0.1, 0.152), (0.045, 0.16), (0.0, 0.162)],
                0, 0, "chrome", segs=32)
        B.lathe([(0.0, 0.155), (0.045, 0.155), (0.04, 0.17), (0.0, 0.175)], 0, 0, "paint_red", segs=16)


def car_sedan(pid, paint, roof=None):
    B = Builder(pid)
    roof = roof or paint
    HW = 0.99   # half width of the body
    # ---- lower body: side profile with wheel arches, extruded across the width, rounded ----
    fx, rx = 1.5, -1.45     # wheel centres
    ar = 0.43               # arch radius
    pts = [(-2.58, 0.33)]
    for (cx) in (rx, fx):
        pts.append((cx - ar - 0.02, 0.33))
        for k in range(13):
            a = math.pi - math.pi * k / 12
            pts.append((cx + ar * math.cos(a), 0.36 + ar * math.sin(a)))
        pts.append((cx + ar + 0.02, 0.33))
    pts += [(2.6, 0.34), (2.67, 0.46), (2.68, 0.62), (2.67, 0.78), (2.62, 0.88), (2.5, 0.92), (1.0, 0.94),
            (-1.0, 0.95), (-2.35, 0.97), (-2.6, 0.95), (-2.69, 0.88), (-2.7, 0.62), (-2.68, 0.44)]
    m = B.mark()
    B.prism_z(pts, -HW, HW, paint)
    body = B.new_faces(m)
    edges = list({e for f in body for e in f.edges})
    import bmesh
    res = bmesh.ops.bevel(B.bm, geom=edges, offset=0.075, segments=3, profile=0.5, affect="EDGES", clamp_overlap=True)
    for f in res.get("faces", []):
        f.smooth = True
        f.material_index = B.mi(paint)
    for f in B.new_faces(m):
        f.normal_update()
        if f.normal.z < -0.45:      # blender Z = game up: underside + wheel well ceilings
            f.material_index = B.mi("metal_dark")
    B.mark_sharp(B.new_faces(m), 50)
    # ---- tail fins (subtle 60s blades on the rear deck) ----
    for side in (-1, 1):
        z = side * (HW - 0.06)
        with xf_push(B, T(0, 0, z)):
            B.sweep([(-0.06, 0.93), (0.06, 0.93), (0.05, 0.985), (0.0, 1.0), (-0.05, 0.985)], -2.62, -1.3, paint, sharp_deg=70)
    # ---- cabin / greenhouse ----
    yb, yt = 0.94, 1.42
    bw, tw = 0.9, 0.76          # half widths at belt / roof
    b_front, b_rear = 0.95, -1.62
    t_front, t_rear = 0.28, -0.98
    P = {
        "bfl": (b_front, yb, -bw), "bfr": (b_front, yb, bw), "brl": (b_rear, yb, -bw), "brr": (b_rear, yb, bw),
        "tfl": (t_front, yt, -tw), "tfr": (t_front, yt, tw), "trl": (t_rear, yt, -tw), "trr": (t_rear, yt, tw),
    }
    V = {k: B.v(p) for k, p in P.items()}
    m = B.mark()
    quads = [
        ("roof", ["tfl", "tfr", "trr", "trl"][::-1]),
        ("front", ["bfl", "bfr", "tfr", "tfl"]),
        ("rear", ["brr", "brl", "trl", "trr"]),
        ("left", ["brl", "bfl", "tfl", "trl"]),
        ("right", ["bfr", "brr", "trr", "tfr"]),
        ("bottom", ["bfl", "brl", "brr", "bfr"]),
    ]
    faces = {}
    for (nm, ks) in quads:
        faces[nm] = B.face([V[k] for k in ks], roof if nm == "roof" else paint)
    B._orient_outward(list(faces.values()), ((b_front + b_rear) / 2, (yb + yt) / 2, 0.0))
    bevel_edges = [e for e in {e for f in faces.values() for e in f.edges} if faces["bottom"] not in e.link_faces]
    res = bmesh.ops.bevel(B.bm, geom=bevel_edges, offset=0.07, segments=4, profile=0.5, affect="EDGES", clamp_overlap=True)
    for f in res.get("faces", []):
        f.smooth = True
        f.material_index = B.mi(paint)

    # glass: inset copies of the window faces, lifted 4 mm off the hull
    def lerp(a, b, t):
        return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

    def glass_quad(p0, p1, p2, p3, inset_u, inset_v, normal_out):
        # p0..p3 counter-clockwise from outside; inset in fractions along the two edge directions
        q0 = lerp(lerp(p0, p1, inset_u[0]), lerp(p3, p2, inset_u[0]), inset_v[0])
        q1 = lerp(lerp(p0, p1, inset_u[1]), lerp(p3, p2, inset_u[1]), inset_v[0])
        q2 = lerp(lerp(p0, p1, inset_u[1]), lerp(p3, p2, inset_u[1]), inset_v[1])
        q3 = lerp(lerp(p0, p1, inset_u[0]), lerp(p3, p2, inset_u[0]), inset_v[1])
        n = normal_out
        cen = [(q0[i] + q2[i]) / 2 for i in range(3)]
        cab = ((b_front + b_rear) / 2, (yb + yt) / 2 - 0.3, 0.0)
        if sum(n[i] * (cen[i] - cab[i]) for i in range(3)) < 0:
            n = tuple(-c for c in n)
            q0, q1, q2, q3 = q3, q2, q1, q0
        qs = [tuple(q[i] + n[i] * 0.004 for i in range(3)) for q in (q0, q1, q2, q3)]
        f = B.quad(*qs, "glass_car")
        f.normal_update()
        return f

    def nrm(a, b, c):
        from mathutils import Vector
        return tuple((Vector(b) - Vector(a)).cross(Vector(c) - Vector(a)).normalized())

    # windshield & rear window
    for (k0, k1, k2, k3) in (("bfl", "bfr", "tfr", "tfl"), ("brr", "brl", "trl", "trr")):
        p = [P[k] for k in (k0, k1, k2, k3)]
        glass_quad(*p, (0.07, 0.93), (0.1, 0.88), nrm(p[0], p[1], p[2]))
    # side windows (two per side, split by the B pillar)
    for (k0, k1, k2, k3) in (("brl", "bfl", "tfl", "trl"), ("bfr", "brr", "trr", "tfr")):
        p = [P[k] for k in (k0, k1, k2, k3)]
        n = nrm(p[0], p[1], p[2])
        left = k0 == "brl"
        # u runs rear->front on the left side, front->rear on the right side
        a, b = ((0.1, 0.5), (0.54, 0.9)) if left else ((0.1, 0.46), (0.5, 0.9))
        glass_quad(*p, a, (0.12, 0.86), n)
        glass_quad(*p, b, (0.12, 0.86), n)
    # chrome drip rail along the roof edge + belt line
    for side in (-1, 1):
        B.tube((t_rear - 0.02, yt - 0.03, side * (tw + 0.035)), (t_front + 0.02, yt - 0.03, side * (tw + 0.035)), 0.012, "chrome", segs=6)
        B.tube((b_rear, yb + 0.005, side * (bw + 0.02)), (b_front, yb + 0.005, side * (bw + 0.02)), 0.01, "chrome", segs=6)
        # side spear trim
        B.box(-2.55, 2.5, 0.7, 0.73, side * HW - 0.012, side * HW + 0.012, "chrome", 0.006)
        # rocker trim
        B.box(-1.0, 1.05, 0.36, 0.42, side * HW - 0.01, side * HW + 0.012, "chrome", 0.006)
        # door shut lines (dark) + handles
        for xl in (0.92, -0.32, -1.4):
            B.box(xl - 0.006, xl + 0.006, 0.45, 0.93, side * HW - 0.004, side * HW + 0.004, "metal_dark", 0.0)
        for xh in (0.62, -0.62):
            B.box(xh - 0.09, xh + 0.09, 0.83, 0.86, side * HW, side * (HW + 0.025), "chrome", 0.008)
    # interior: seat backs, dash, steering wheel
    B.box(-1.25, -0.95, 0.6, 1.2, -0.75, 0.75, "car_interior", 0.06)
    B.box(-0.25, 0.05, 0.6, 1.2, -0.75, 0.75, "car_interior", 0.06)
    B.box(0.75, 0.95, 0.75, 1.02, -0.85, 0.85, "car_interior", 0.04)
    with xf_push(B, T(0.62, 1.02, -0.38) @ R("Z", 60)):
        ring = 16
        for k in range(ring):
            a0 = 2 * math.pi * k / ring
            a1 = 2 * math.pi * (k + 1) / ring
            B.tube((0, 0.19 * math.cos(a0), 0.19 * math.sin(a0)), (0, 0.19 * math.cos(a1), 0.19 * math.sin(a1)), 0.014, "trim_dark", segs=6)
    # ---- front: grille, quad headlights, bumper, hood ornament ----
    gx = 2.68
    B.box(gx - 0.05, gx + 0.005, 0.5, 0.78, -0.82, 0.82, "metal_dark", 0.01)
    for k in range(5):
        y = 0.53 + k * 0.055
        B.box(gx - 0.02, gx + 0.012, y, y + 0.014, -0.55, 0.55, "chrome", 0.004)
    for zc in (-0.62, 0.62):
        for dz in (-0.12, 0.12):
            z = zc + dz
            B.tube((gx - 0.02, 0.66, z), (gx + 0.03, 0.66, z), 0.095, "chrome", segs=24)
            B.tube((gx + 0.03, 0.66, z), (gx + 0.038, 0.66, z), 0.08, "headlight", segs=24)
    with xf_push(B, R("Y", -90)):
        # sweep along local X == world Z; profile (z_local, y) with z_local == -world x
        bumper = [(-2.66, 0.3), (-2.78, 0.31), (-2.81, 0.37), (-2.8, 0.45), (-2.76, 0.49), (-2.66, 0.49)]
        B.sweep(bumper, -0.98, 0.98, "chrome", sharp_deg=60)
        rbump = [(2.68, 0.33), (2.79, 0.34), (2.82, 0.4), (2.81, 0.48), (2.77, 0.52), (2.68, 0.52)]
        B.sweep(rbump, -0.98, 0.98, "chrome", sharp_deg=60)
    for side in (-1, 1):  # bumper wrap ends
        B.box(2.52, 2.74, 0.31, 0.48, side * 0.98 - 0.04, side * 0.98 + 0.04, "chrome", 0.03)
        B.box(-2.76, -2.5, 0.34, 0.51, side * 0.98 - 0.04, side * 0.98 + 0.04, "chrome", 0.03)
    B.box(2.2, 2.3, 0.94, 0.98, -0.02, 0.02, "chrome", 0.01)                      # hood ornament
    # ---- rear: round tail lights, plate, trunk lock ----
    for side in (-1, 1):
        for zc in (0.55, 0.8):
            z = side * zc
            B.tube((-2.68, 0.72, z), (-2.71, 0.72, z), 0.075, "chrome", segs=20)
            B.tube((-2.71, 0.72, z), (-2.715, 0.72, z), 0.062, "tail_light", segs=20)
    B.box(-2.73, -2.69, 0.56, 0.72, -0.17, 0.17, "trim_white", 0.008)
    B.box(-2.72, -2.69, 0.8, 0.83, -0.04, 0.04, "chrome", 0.004)
    # mirror (driver side, -Z) and antenna
    B.tube((0.85, 0.98, -HW), (0.85, 1.08, -HW - 0.08), 0.012, "chrome", segs=6)
    with xf_push(B, T(0.85, 1.08, -HW - 0.1) @ R("X", 90)):
        B.lathe([(0.0, -0.02), (0.05, -0.02), (0.06, 0.0), (0.05, 0.02), (0.0, 0.03)], 0, 0, "chrome", segs=14)
    B.tube((-1.9, 0.95, 0.75), (-1.95, 1.75, 0.75), 0.004, "chrome", segs=4)
    # wheels
    for x in (fx, rx):
        for side in (-1, 1):
            wheel(B, x, side * (HW - 0.12), side)
    # tyre-on-ground contact shadow helper (dark quad under the car)
    B.rect_y(-2.6, 2.6, -0.9, 0.9, 0.005, "metal_dark", facing=1)
    export(B, pid)
    register(pid, "road", (5.6, 2.1), ["car", "foreground"], height=1.45, length=5.62)


# ------------------------------------------------------------------------------------------------

def main():
    kitlib.reset_scene()
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".glb"):
            os.remove(os.path.join(OUT, f))
    lamp_post()
    hydrant()
    trash_can()
    newspaper_box()
    newspaper_box("newspaper_box_b", "paint_blue")
    bench()
    mailbox()
    parking_meter()
    street_sign()
    wall_ac_unit()
    fire_barrel()
    downpipe("downpipe", 7.2)
    downpipe("downpipe_short", 4.0)
    downpipe("downpipe_tall", 10.4)
    trash_bags()
    crates()
    bollard()
    phone_booth()
    sandwich_board()
    cardboard_boxes()
    car_sedan("car_sedan", "car_paint_teal")
    car_sedan("car_sedan_b", "car_paint_cream", roof="car_paint_maroon")
    car_sedan("car_sedan_c", "car_paint_maroon", roof="car_paint_cream")
    import retro_props
    retro_props.build(sys.modules[__name__])
    with open(os.path.join(OUT, "props.json"), "w") as f:
        json.dump({"version": 1, "generator": "tools/blender/props.py",
                   "notes": "era: '60s' | 'retro'. wall_high props carry mount_y (suggested height); spans (cables) carry span. "
                            "Materials neon_* are recolourable emissive tubes, holo_screen / led_ticker are animated quads. "
                            "Origin = base centre, front faces +Z. Markers: omni_* -> OmniLight3D (kit_import.gd), "
                            "outlet = downpipe gutter outlet, vent/warm = warm-air source. Cars: origin at ground "
                            "centre, facing +X; drop them to road level (sidewalk top y=0, road ~-0.15).",
                   "props": PROPS}, f, indent=1)
    print("wrote props.json with %d props" % len(PROPS))


if __name__ == "__main__":
    main()
