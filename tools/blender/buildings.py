"""Generate the modular 60s main-street building kit.

    blender -b --factory-startup --python tools/blender/buildings.py

Writes assets/buildings/*.glb and assets/buildings/kit.json (see docs/CONTRACTS.md §2).
Conventions: module origin = bottom-left corner of the facade at the building line; spans
x in [0, width], y in [0, height]; main wall face at z = 0, depth into -Z. Trim (sills, piers,
fascia, cornices) projects up to ~0.16 m in front of z = 0 (caps up to ~0.5 m).
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kitlib  # noqa: E402
from kitlib import Builder, Matrix, ROOT  # noqa: E402

OUT = os.path.join(ROOT, "assets", "buildings")
RES = "res://assets/buildings/"

GH = 4.0      # ground storey height (contract)
UH = 3.2      # upper storey height (contract)
PIER = 0.3
SIGN = (PIER, 3.14, None, 3.86)  # x0, y0, x1(=W-PIER), y1 of the plain sign board
SIGN_Z = 0.055                   # sign face plane

MODULES = []


AESTHETICS_60S = ["rundown", "industrial", "rundown_neon", "outskirts"]


def register(mid, kind, width, height, style=None, tags=(), era="60s", aesthetics=None, **extra):
    """era: "60s" (decayed main street) or "retro" (retro-future/neon). aesthetics: the level
    aesthetics (levels/*.json "aesthetic") this module suits best."""
    e = {"id": mid, "scene": RES + mid + ".glb", "kind": kind, "width": round(width, 3),
         "height": round(height, 3), "era": era, "tags": list(tags),
         "aesthetics": list(aesthetics if aesthetics is not None else AESTHETICS_60S)}
    if style:
        e["style"] = style
    e.update(extra)
    MODULES.append(e)


def export(B, mid):
    tris = kitlib.build_and_export(B, os.path.join(OUT, mid + ".glb"))
    print("module %-24s tris %6d" % (mid, tris))
    return tris


# ------------------------------------------------------------------------------------------------
# small helpers
# ------------------------------------------------------------------------------------------------

def box_rot(B, cx, cy, cz, sx, sy, sz, ang, mat, bevel=0.0):
    old = B.xf
    B.xf = old @ Matrix.Translation((cx, cy, cz)) @ Matrix.Rotation(ang, 4, "Z")
    B.box(-sx / 2, sx / 2, -sy / 2, sy / 2, -sz / 2, sz / 2, mat, bevel)
    B.xf = old


def poster(B, x, y, z, w, h, cell, ang=0.0):
    """Poster quad (posters.png atlas, 4x2 cells) centred at x, y facing +Z."""
    u0 = (cell % 4) * 0.25
    v0 = 0.5 if cell < 4 else 0.0
    old = B.xf
    B.xf = old @ Matrix.Translation((x, y, z)) @ Matrix.Rotation(ang, 4, "Z")
    B.rect_z(-w / 2, w / 2, -h / 2, h / 2, 0.0, "posters", uv=(u0, v0, u0 + 0.25, v0 + 0.5))
    B.xf = old


def moulding(B, x0, x1, y, mat, proj=0.12, h=0.1, z=0.0):
    """Cornice-like moulding whose top is at y, projecting `proj` in front of z."""
    p = [(z, y - h), (z + proj * 0.35, y - h), (z + proj * 0.45, y - h * 0.78),
         (z + proj * 0.7, y - h * 0.62), (z + proj * 0.92, y - h * 0.38), (z + proj, y - h * 0.18),
         (z + proj, y), (z, y)]
    B.sweep(p, x0, x1, mat)


def sill(B, x0, x1, y, mat, proj=0.07, back=-0.16, th=0.07):
    p = [(back, y - th), (proj - 0.015, y - th), (proj, y - th + 0.015), (proj, y - 0.012),
         (proj - 0.02, y), (back, y + 0.012)]
    B.sweep(p, x0, x1, mat)
    # drip groove underside implied; little end blocks
    return


def frame_ring(B, x0, x1, y0, y1, z0, z1, t, mat, bevel=0.008, bottom=True):
    """Rectangular frame of member width t (window/door frame)."""
    B.box(x0, x0 + t, y0, y1, z0, z1, mat, bevel)
    B.box(x1 - t, x1, y0, y1, z0, z1, mat, bevel)
    B.box(x0 + t, x1 - t, y1 - t, y1, z0, z1, mat, bevel)
    if bottom:
        B.box(x0 + t, x1 - t, y0, y0 + t, z0, z1, mat, bevel)


def end_walls(B, W, H, mat, depth):
    """Close the module's left/right ends so a building reads as a solid block when its neighbour
    is shorter (seen at an angle) or at the end of a street."""
    B.rect_x(-depth, 0.0, 0.0, H, 0.0, mat, facing=-1)
    B.rect_x(-depth, 0.0, 0.0, H, W, mat, facing=1)


def interior_box(B, x0, x1, y0, y1, z_front, z_back, back_mat, side_mat, floor_mat, ceil_mat=None,
                 u_off=0.0, img_w=6.0, img_h=3.0):
    ceil_mat = ceil_mat or side_mat
    ww = x1 - x0
    u0 = u_off
    u1 = u_off + ww / img_w
    B.rect_z(x0, x1, y0, y1, z_back, back_mat, uv=(u0, (0.0), u1, (y1 - y0) / img_h))
    B.rect_x(z_back, z_front, y0, y1, x0, side_mat, facing=1)
    B.rect_x(z_back, z_front, y0, y1, x1, side_mat, facing=-1)
    B.rect_y(x0, x1, z_back, z_front, y0 + 0.001, floor_mat, facing=1)
    B.rect_y(x0, x1, z_back, z_front, y1, ceil_mat, facing=-1)


# ------------------------------------------------------------------------------------------------
# ground storey frame: wall, piers, fascia (awning mount y=3.0), sign band 3.1-3.9, string course
# ------------------------------------------------------------------------------------------------

def ground_frame(B, W, wall, trim, opening_list, pier_mat="stone_trim", sign_mat="sign_board",
                 reveal=0.2, piers=True):
    B.wall(0.0, W, 0.0, GH, 0.0, opening_list, wall, depth=reveal)
    end_walls(B, W, GH, wall, 3.0)
    if piers:
        for (a, b) in ((0.0, PIER), (W - PIER, W)):
            B.box(a + 0.01, b - 0.01, 0.0, 2.86, -0.02, 0.06, wall if pier_mat == "wall" else pier_mat, 0.02)
            B.box(a, b, 0.0, 0.38, -0.02, 0.1, "stone_trim", 0.025)          # plinth
            B.sweep([(-0.02, 2.84), (0.08, 2.84), (0.08, 2.88), (0.11, 2.9), (0.11, 2.98), (-0.02, 2.98)],
                    a, b, "stone_trim")                                         # capital
    # fascia / awning beam (top at 3.1, awning mounts at y = 3.0)
    B.box(0.0, W, 2.98, 3.1, -0.02, 0.15, trim, 0.02)
    B.box(0.0, W, 2.95, 2.99, -0.02, 0.1, trim, 0.008)
    # sign band: plain board, face at z = SIGN_Z with 0..1 UVs on its own material
    sx0, sx1 = PIER, W - PIER
    B.box(sx0, sx1, SIGN[1], SIGN[3], -0.02, SIGN_Z - 0.002, sign_mat, 0.008)
    B.rect_z(sx0 + 0.01, sx1 - 0.01, SIGN[1] + 0.01, SIGN[3] - 0.01, SIGN_Z, "sign_face", uv=(0, 0, 1, 1))
    frame_ring(B, sx0 - 0.06, sx1 + 0.06, SIGN[1] - 0.04, SIGN[3] + 0.06, -0.02, SIGN_Z + 0.03, 0.06, trim)
    moulding(B, 0.0, W, GH, "stone_trim", proj=0.16, h=0.1)
    return (sx0, SIGN[1], sx1, SIGN[3], SIGN_Z)


# ------------------------------------------------------------------------------------------------
# shopfront (glass, bulkhead, mullions, recessed door, interior)
# ------------------------------------------------------------------------------------------------

def shopfront(B, x0, x1, lit, back_img, frame, bulk, door="center", rng=None, broken=0,
              posters_n=0, furniture=None, glass=None, zg=-0.2, door_w=1.0, recess=0.9, side_mat=None):
    rng = rng or B.rng
    glass = glass or ("glass_lit" if lit else "glass_dirty")
    side = side_mat or ("interior_warm" if lit else "interior_dark")
    floor = "terrazzo" if lit else "interior_dark"
    z_back = -2.7
    interior_box(B, x0, x1, 0.0, 3.0, zg - 0.02, z_back, back_img, side, floor, side,
                 u_off=rng.uniform(0, 0.3))
    # ceiling lights
    if lit:
        for k in range(max(1, int((x1 - x0) / 2.2))):
            cx = x0 + (k + 0.5) * (x1 - x0) / max(1, int((x1 - x0) / 2.2))
            B.box(cx - 0.6, cx + 0.6, 2.9, 2.96, -1.5, -1.38, "lamp_bulb", 0.01)
            B.box(cx - 0.62, cx + 0.62, 2.96, 3.0, -1.52, -1.36, "aluminium", 0.005)
        B.marker("omni_warm", ((x0 + x1) / 2, 2.4, -0.9))
    # door segment
    segs = []
    if door is None:
        segs = [(x0, x1)]
        dx0 = dx1 = None
    else:
        if door == "center":
            dc = (x0 + x1) / 2
        elif door == "left":
            dc = x0 + 0.15 + door_w / 2 + 0.05
        else:
            dc = x1 - 0.15 - door_w / 2 - 0.05
        dx0, dx1 = dc - door_w / 2 - 0.05, dc + door_w / 2 + 0.05
        if dx0 - x0 > 0.2:
            segs.append((x0, dx0))
        if x1 - dx1 > 0.2:
            segs.append((dx1, x1))
    head_y = 2.92
    tb0, tb1 = 2.34, 2.43
    # window segments
    pane_list = []
    for (a, b) in segs:
        B.box(a, b, 0.0, 0.5, zg - 0.1, zg + 0.04, bulk, 0.015)                 # bulkhead
        B.sweep([(zg - 0.1, 0.49), (zg + 0.07, 0.49), (zg + 0.08, 0.51), (zg + 0.06, 0.55), (zg - 0.1, 0.55)],
                a, b, frame)                                                     # sill cap
        n = max(1, int(math.ceil((b - a) / 1.6)))
        xs = [a + (b - a) * k / n for k in range(n + 1)]
        for xm in xs:
            B.box(xm - 0.035, xm + 0.035, 0.5, head_y, zg - 0.06, zg + 0.05, frame, 0.008)
        for k in range(n):
            pane_list.append((xs[k] + 0.035, xs[k + 1] - 0.035, 0.55, tb0))
        B.box(a, b, tb0, tb1, zg - 0.06, zg + 0.05, frame, 0.008)                # transom bar
        # transom: small panes
        nt = max(1, int(round((b - a) / 0.55)))
        txs = [a + (b - a) * k / nt for k in range(nt + 1)]
        for xm in txs[1:-1]:
            B.box(xm - 0.018, xm + 0.018, tb1, head_y, zg - 0.03, zg + 0.03, frame, 0.005)
        for k in range(nt):
            pane_list.append((txs[k] + 0.02, txs[k + 1] - 0.02, tb1, head_y))
    B.box(x0, x1, head_y, 3.0, zg - 0.08, zg + 0.06, frame, 0.01)               # head
    # glass
    broken_set = set(rng.sample(range(len(pane_list)), min(broken, len(pane_list)))) if broken else set()
    for i, (a, b, c, d) in enumerate(pane_list):
        if i in broken_set:
            B.shattered_pane(a, b, c, d, zg, glass, hole=rng.uniform(0.4, 0.8))
        else:
            B.rect_z(a, b, c, d, zg, glass)
    # posters stuck inside glass
    for k in range(posters_n):
        a, b, c, d = pane_list[rng.randrange(len(pane_list))]
        if d - c < 1.0:
            continue
        pw = min(0.5, (b - a) * 0.6)
        poster(B, rng.uniform(a + pw / 2, b - pw / 2), rng.uniform(c + 0.6, d - 0.6), zg - 0.01, pw, pw * 2,
               rng.choice([0, 1, 6, 7]), rng.uniform(-0.05, 0.05))
    # recessed entry
    if door is not None:
        zd = zg - recess
        B.rect_y(dx0, dx1, zd, zg + 0.06, 0.012, "terrazzo", facing=1)
        for (xx, f) in ((dx0, 1), (dx1, -1)):
            # glazed returns
            B.box(xx - 0.035, xx + 0.035, 0.0, 2.92, zd, zg + 0.05, frame, 0.008)
            B.box(xx - 0.03 if f > 0 else xx - 0.0, xx + 0.0 if f > 0 else xx + 0.03, 0.0, 0.5, zd, zg, bulk, 0.01)
            B.rect_x(zd + 0.05, zg - 0.05, 0.55, 2.34, xx + 0.031 * f, glass, facing=f)
            B.box(xx - 0.035, xx + 0.035, 2.34, 2.43, zd, zg, frame, 0.006)
        # soffit over the recess
        B.rect_y(dx0 + 0.035, dx1 - 0.035, zd, zg, 2.43, "trim_dark", facing=-1)
        # door + frame
        frame_ring(B, dx0 + 0.035, dx1 - 0.035, 0.0, 2.43, zd - 0.06, zd + 0.02, 0.06, frame, bottom=False)
        lx0, lx1 = dx0 + 0.1, dx1 - 0.1
        frame_ring(B, lx0, lx1, 0.02, 2.36, zd - 0.04, zd, 0.09, frame)
        B.box(lx0 + 0.09, lx1 - 0.09, 0.02, 0.3, zd - 0.035, zd - 0.005, "aluminium" if lit else "metal_dark", 0.004)
        B.rect_z(lx0 + 0.09, lx1 - 0.09, 0.3, 2.27, zd - 0.02, glass)
        B.tube((lx0 + 0.15, 1.05, zd + 0.03), (lx1 - 0.15, 1.05, zd + 0.03), 0.018, "chrome", segs=10)
        for xx in (lx0 + 0.15, lx1 - 0.15):
            B.tube((xx, 1.05, zd), (xx, 1.05, zd + 0.03), 0.012, "chrome", segs=8)
        if lit:
            B.marker("door", ((dx0 + dx1) / 2, 0.0, zd))
    # furniture
    if furniture:
        furniture(B, x0, x1, rng)
    return pane_list


def furn_diner(B, x0, x1, rng):
    B.box(x0 + 0.1, x1 - 0.1, 0.0, 1.02, -2.05, -1.6, "trim_red", 0.02)
    B.box(x0 + 0.05, x1 - 0.05, 1.02, 1.08, -2.1, -1.52, "terrazzo", 0.015)
    B.box(x0 + 0.1, x1 - 0.1, 0.0, 0.12, -1.62, -1.58, "chrome", 0.01)
    x = x0 + 0.5
    while x < x1 - 0.4:
        B.tube((x, 0.0, -1.25), (x, 0.7, -1.25), 0.03, "chrome", segs=10)
        B.lathe([(0.0, 0.66), (0.19, 0.66), (0.2, 0.7), (0.19, 0.76), (0.0, 0.77)], x, -1.25, "trim_red", segs=16)
        B.lathe([(0.0, 0.0), (0.16, 0.0), (0.16, 0.03), (0.0, 0.03)], x, -1.25, "chrome", segs=16)
        x += 0.62


def furn_pawn(B, x0, x1, rng):
    B.box(x0 + 0.2, x1 - 0.2, 0.0, 0.9, -1.9, -1.4, "wood_dark", 0.02)
    B.box(x0 + 0.2, x1 - 0.2, 0.9, 1.15, -1.9, -1.4, "glass_lit", 0.005)
    B.box(x0 + 0.2, x1 - 0.2, 1.15, 1.18, -1.92, -1.38, "wood_dark", 0.01)
    # a guitar and a radio in the window
    B.box(x0 + 0.4, x0 + 0.85, 0.55, 0.85, -0.6, -0.4, "wood_dark", 0.03)
    B.tube((x0 + 0.5, 0.86, -0.45), (x0 + 0.5, 0.95, -0.45), 0.01, "chrome")


def furn_laundromat(B, x0, x1, rng):
    B.box(x0 + 0.6, x1 - 0.6, 0.8, 0.86, -1.5, -0.9, "plastic_beige", 0.015)
    for xx in (x0 + 0.7, x1 - 0.7):
        B.box(xx - 0.04, xx + 0.04, 0.0, 0.8, -1.25, -1.15, "chrome", 0.01)
    # a row of 3D washers along one side (parallax)
    x = x0 + 0.1
    while x < x1 - 0.7:
        B.box(x, x + 0.62, 0.0, 0.9, -2.68, -2.1, "trim_white", 0.025)
        B.tube((x + 0.31, 0.45, -2.1), (x + 0.31, 0.45, -2.06), 0.2, "chrome", segs=20)
        B.tube((x + 0.31, 0.45, -2.06), (x + 0.31, 0.45, -2.05), 0.16, "glass_dark", segs=20)
        x += 0.66


def furn_barber(B, x0, x1, rng):
    x = x0 + 0.8
    while x < x1 - 0.6:
        B.lathe([(0.0, 0.0), (0.25, 0.0), (0.25, 0.04), (0.06, 0.08), (0.06, 0.4), (0.0, 0.4)], x, -1.6, "chrome", segs=16)
        B.box(x - 0.3, x + 0.3, 0.4, 0.6, -1.85, -1.35, "trim_red", 0.06)
        B.box(x - 0.28, x + 0.28, 0.6, 1.3, -1.9, -1.78, "trim_red", 0.06)
        B.box(x - 0.34, x - 0.28, 0.55, 0.8, -1.8, -1.35, "chrome", 0.02)
        B.box(x + 0.28, x + 0.34, 0.55, 0.8, -1.8, -1.35, "chrome", 0.02)
        x += 1.4


def furn_news(B, x0, x1, rng):
    # tiered magazine rack in the window (uses the poster atlas as covers)
    for k in range(3):
        y = 0.6 + k * 0.32
        z = -0.45 - k * 0.12
        B.box(x0 + 0.1, x1 - 0.1, y - 0.03, y, z - 0.18, z + 0.02, "wood_dark", 0.01)
        x = x0 + 0.15
        while x < x1 - 0.4:
            poster(B, x + 0.11, y + 0.14, z - 0.06, 0.2, 0.3, B.rng.randrange(8), 0.0)
            x += 0.24


# ------------------------------------------------------------------------------------------------
# ground module types
# ------------------------------------------------------------------------------------------------

LIT_SHOPS = {
    "diner": ("interior_diner", furn_diner, "trim_red", "terrazzo"),
    "laundromat": ("interior_laundromat", furn_laundromat, "aluminium", "terrazzo_green"),
    "pawn": ("interior_pawn", furn_pawn, "trim_dark", "brick_dark"),
    "barber": ("interior_barber", furn_barber, "trim_white", "terrazzo"),
    "newsstand": ("interior_newsstand", furn_news, "trim_green", "wood_dark"),
}


def gm_shop_lit(mid, W, shop, wall, door="center"):
    img, furn, frame, bulk = LIT_SHOPS[shop]
    B = Builder(mid)
    sign = ground_frame(B, W, wall, frame if frame != "aluminium" else "trim_dark", [(PIER, W - PIER, 0.0, 2.95)])
    shopfront(B, PIER, W - PIER, True, img, frame, bulk, door=door, furniture=furn)
    export(B, mid)
    register(mid, "ground", W, GH, "shop_lit", ["lit", shop], sign_rect=list(sign))


def gm_shop_dark(mid, W, wall, frame="trim_dark", door="center", broken=1, posters_n=2):
    B = Builder(mid)
    sign = ground_frame(B, W, wall, frame, [(PIER, W - PIER, 0.0, 2.95)], sign_mat="sign_board")
    shopfront(B, PIER, W - PIER, False, "interior_empty", frame, B.rng.choice(["terrazzo", "brick_dark", "terrazzo_green"]),
              door=door, broken=broken, posters_n=posters_n, furniture=None)
    export(B, mid)
    register(mid, "ground", W, GH, "shop_dark", ["dark"], sign_rect=list(sign))


def roller_shutter(B, x0, x1, y_top, mat, zc=-0.12, posters_n=1):
    rng = B.rng
    pitch = 0.075
    pts = []
    y = 0.09
    while y <= y_top + 1e-6:
        pts.append((zc + 0.011 * math.sin(2 * math.pi * y / pitch), y))
        y += pitch / 6
    B.sweep(pts, x0 + 0.03, x1 - 0.03, mat, closed=False, sharp_deg=80)
    B.box(x0 + 0.03, x1 - 0.03, 0.0, 0.09, zc - 0.035, zc + 0.03, "aluminium", 0.01)     # bottom bar
    for xx in (x0 + 0.3, x1 - 0.3):
        B.box(xx - 0.07, xx + 0.07, 0.04, 0.07, zc + 0.03, zc + 0.06, "metal_dark", 0.006)  # handles
    # padlock
    cx = (x0 + x1) / 2
    B.box(cx - 0.04, cx + 0.04, 0.02, 0.1, zc + 0.03, zc + 0.06, "brass", 0.008)
    B.tube((cx - 0.025, 0.1, zc + 0.045), (cx - 0.025, 0.15, zc + 0.045), 0.006, "chrome", segs=8)
    B.tube((cx + 0.025, 0.1, zc + 0.045), (cx + 0.025, 0.15, zc + 0.045), 0.006, "chrome", segs=8)
    B.tube((cx - 0.025, 0.15, zc + 0.045), (cx + 0.025, 0.15, zc + 0.045), 0.006, "chrome", segs=8)
    # guides
    for xx in (x0, x1 - 0.06):
        B.box(xx, xx + 0.06, 0.0, y_top, zc - 0.05, zc + 0.04, "galvanized", 0.008)
    # housing box (rounded)
    B.box(x0 - 0.02, x1 + 0.02, y_top, y_top + 0.3, zc - 0.08, 0.08, "galvanized", 0.06)
    for k in range(posters_n):
        pw = rng.uniform(0.45, 0.6)
        poster(B, rng.uniform(x0 + 0.5, x1 - 0.5), rng.uniform(1.0, 1.8), zc + 0.013, pw, pw * 2,
               rng.randrange(8), rng.uniform(-0.06, 0.06))


def gm_shuttered(mid, W, wall, mat="roller_door", split=False, trim="trim_dark", door_side=None):
    B = Builder(mid)
    sign = ground_frame(B, W, wall, trim, [(PIER, W - PIER, 0.0, 2.95)], reveal=0.25)
    # dark interior lining behind the shutter so nothing shows through gaps
    B.rect_z(PIER, W - PIER, 0.0, 2.95, -0.25, "interior_dark")
    x0, x1 = PIER, W - PIER
    if door_side:
        # steel side door with its own frame, shutter over the rest
        dw = 1.0
        if door_side == "left":
            dx0, dx1 = x0, x0 + dw + 0.1
            x0 = dx1 + 0.14
        else:
            dx0, dx1 = x1 - dw - 0.1, x1
            x1 = dx0 - 0.14
        wall_strip = (dx1, x0) if door_side == "left" else (x1, dx0)
        B.box(wall_strip[0], wall_strip[1], 0.0, 2.95, -0.25, 0.0, wall, 0.0)
        steel_door(B, dx0 + 0.05, dx1 - 0.05, 2.25, "trim_green", z=-0.14)
        B.box(dx0, dx1, 2.25, 2.95, -0.2, -0.1, "plywood", 0.01)
    if split and (x1 - x0) > 3.5:
        mid_x = (x0 + x1) / 2
        B.box(mid_x - 0.08, mid_x + 0.08, 0.0, 2.95, -0.22, -0.02, "galvanized", 0.01)
        roller_shutter(B, x0, mid_x - 0.08, 2.62, mat)
        roller_shutter(B, mid_x + 0.08, x1, 2.62, mat)
    else:
        roller_shutter(B, x0, x1, 2.62, mat, posters_n=2 if x1 - x0 > 3 else 1)
    B.rect_z(PIER, W - PIER, 2.62, 2.95, -0.21, "interior_dark")
    export(B, mid)
    register(mid, "ground", W, GH, "shuttered", ["dark"], sign_rect=list(sign))


def gm_boarded(mid, W, wall, frame="trim_green"):
    B = Builder(mid)
    rng = B.rng
    sign = ground_frame(B, W, wall, frame, [(PIER, W - PIER, 0.0, 2.95)], sign_mat="sign_board_dark")
    panes = shopfront(B, PIER, W - PIER, False, "interior_empty", frame, "brick_dark", door="center",
                      broken=0, glass="glass_dirty", recess=0.25)
    zf = -0.2 + 0.07
    # plywood over the display windows, broken transom glass stays visible
    for (a, b, c, d) in panes:
        if d - c > 1.0:
            x = a - 0.03
            while x < b - 0.05:
                w = min(1.22, b + 0.03 - x)
                ang = rng.uniform(-0.02, 0.02)
                box_rot(B, x + w / 2, (c + d) / 2, zf + rng.uniform(0, 0.01), w - 0.01, d - c + 0.08, 0.018, ang, "plywood", 0.004)
                if rng.random() < 0.6:
                    poster(B, x + w / 2 + rng.uniform(-0.15, 0.15), rng.uniform(1.1, 1.7), zf + 0.022, 0.42, 0.84,
                           rng.randrange(8), rng.uniform(-0.08, 0.08))
                x += w
    # planks nailed across the recessed door
    dc = W / 2
    for k in range(6):
        y = 0.35 + k * 0.36 + rng.uniform(-0.05, 0.05)
        box_rot(B, dc, y, -0.2 + 0.075, 1.25, 0.15, 0.025, rng.uniform(-0.12, 0.12), "wood_boards", 0.006)
    export(B, mid)
    register(mid, "ground", W, GH, "boarded", ["dark"], sign_rect=list(sign))


def steel_door(B, x0, x1, h, mat, z=-0.12):
    frame_ring(B, x0 - 0.06, x1 + 0.06, 0.0, h + 0.06, z - 0.04, z + 0.05, 0.06, "metal_dark", bottom=False)
    B.box(x0, x1, 0.0, h, z - 0.04, z, mat, 0.006)
    for (a, b) in ((0.15, 1.0), (1.15, h - 0.15)):
        B.box(x0 + 0.12, x1 - 0.12, a, b, z, z + 0.012, mat, 0.004)
    B.box(x0 + 0.02, x1 - 0.02, 0.02, 0.25, z, z + 0.006, "metal_rust", 0.003)
    B.tube((x1 - 0.12, 1.0, z), (x1 - 0.12, 1.0, z + 0.06), 0.012, "chrome", segs=8)
    B.box(x1 - 0.16, x1 - 0.06, 0.98, 1.02, z + 0.05, z + 0.07, "chrome", 0.005)


def barred_window(B, x0, x1, y0, y1, glass="glass_dirty", depth=0.18):
    zf = -depth
    B.rect_z(x0, x1, y0, y1, zf, glass)
    frame_ring(B, x0, x1, y0, y1, zf - 0.02, zf + 0.04, 0.05, "trim_dark")
    B.rect_z(x0, x1, y0, y1, zf - 0.3, "interior_dark")
    x = x0 + 0.1
    while x < x1 - 0.05:
        B.tube((x, y0, -0.03), (x, y1, -0.03), 0.012, "metal_dark", segs=8)
        x += 0.12
    for y in (y0 + 0.08, y1 - 0.08):
        B.box(x0, x1, y - 0.015, y + 0.015, -0.05, -0.02, "metal_dark", 0.004)
    sill(B, x0 - 0.06, x1 + 0.06, y0, "stone_trim", proj=0.06)


def gm_wall(mid, W, wall, door_x=None, window=True, extras=True):
    B = Builder(mid)
    rng = B.rng
    door_x = W * 0.3 if door_x is None else door_x
    ops = [(door_x, door_x + 1.0, 0.0, 2.25)]
    wx0 = door_x + 1.5 if door_x + 1.5 + 1.2 < W - PIER else PIER + 0.2
    if window and wx0 + 1.2 < W - PIER and not (wx0 < door_x + 1.0 + 0.2 and wx0 + 1.2 > door_x - 0.2):
        ops.append((wx0, wx0 + 1.2, 1.7, 2.5))
    else:
        window = False
    sign = ground_frame(B, W, wall, "trim_dark", ops, pier_mat="wall", sign_mat="sign_board_dark", reveal=0.12)
    steel_door(B, door_x + 0.06, door_x + 0.94, 2.19, rng.choice(["trim_green", "metal_rust", "trim_blue"]))
    B.box(door_x - 0.1, door_x + 1.1, 2.25, 2.37, -0.02, 0.04, "stone_trim", 0.012)   # lintel
    B.box(door_x - 0.05, door_x + 1.05, 0.0, 0.08, -0.12, 0.22, "concrete", 0.015)    # step
    if window:
        barred_window(B, wx0, wx0 + 1.2, 1.7, 2.5)
    if extras:
        # electric meter + conduit, vent louvre
        mx = door_x - 0.6 if door_x > 1.2 else door_x + 1.35
        B.box(mx - 0.18, mx + 0.18, 1.4, 1.9, 0.0, 0.14, "galvanized", 0.02)
        B.tube((mx, 1.62, 0.14), (mx, 1.62, 0.16), 0.08, "glass_dark", segs=16)
        B.tube((mx, 1.9, 0.07), (mx, 2.95, 0.07), 0.018, "galvanized", segs=8)
        vx = W - PIER - 0.7
        if not any(o[0] - 0.3 < vx + 0.5 and o[1] + 0.3 > vx for o in ops):
            B.box(vx, vx + 0.5, 0.35, 0.75, -0.03, 0.03, "metal_dark", 0.01)
            for k in range(6):
                y = 0.4 + k * 0.06
                box_rot(B, vx + 0.25, y + 0.02, 0.03, 0.44, 0.012, 0.05, 0.0, "galvanized", 0.003)
        # some posters on the brick
        for k in range(rng.randint(1, 3)):
            px = rng.uniform(PIER + 0.4, W - PIER - 0.4)
            if any(o[0] - 0.3 < px < o[1] + 0.3 for o in ops):
                continue
            poster(B, px, rng.uniform(1.1, 1.6), 0.004, 0.45, 0.9, rng.randrange(8), rng.uniform(-0.05, 0.05))
    export(B, mid)
    register(mid, "ground", W, GH, "wall", ["dark"], sign_rect=list(sign))


def gm_doorway(mid, W, wall):
    """Residential entrance (stairs to the apartments above)."""
    B = Builder(mid)
    rng = B.rng
    dc = W / 2 if W < 3.5 else PIER + 1.2
    dx0, dx1 = dc - 0.6, dc + 0.6
    ops = [(dx0, dx1, 0.0, 2.6)]
    if W >= 3.5:
        ops.append((dx1 + 0.6, W - PIER - 0.25, 0.9, 2.5))
    sign = ground_frame(B, W, wall, "trim_dark", ops, pier_mat="wall", sign_mat="sign_board_dark", reveal=0.4)
    zd = -0.4
    # stone surround: pilasters + entablature
    for (a, b) in ((dx0 - 0.22, dx0), (dx1, dx1 + 0.22)):
        B.box(a, b, 0.0, 2.6, -0.02, 0.07, "stone_trim", 0.015)
        B.box(a - 0.02, b + 0.02, 0.0, 0.3, -0.02, 0.1, "stone_trim", 0.02)
    B.box(dx0 - 0.26, dx1 + 0.26, 2.6, 2.85, -0.02, 0.09, "stone_trim", 0.015)
    moulding(B, dx0 - 0.32, dx1 + 0.32, 2.95, "stone_trim", proj=0.15, h=0.1)
    # steps (inside the reveal plus one projecting slab)
    B.box(dx0, dx1, 0.0, 0.16, zd, 0.25, "stone_trim", 0.02)
    B.box(dx0 + 0.02, dx1 - 0.02, 0.16, 0.3, zd, -0.05, "stone_trim", 0.02)
    # door: wood panel door with glazed top + transom
    z = zd + 0.02
    frame_ring(B, dx0 + 0.02, dx1 - 0.02, 0.3, 2.6, z - 0.04, z + 0.05, 0.07, "wood_dark", bottom=False)
    B.box(dx0 + 0.09, dx1 - 0.09, 2.08, 2.15, z - 0.03, z + 0.04, "wood_dark", 0.006)
    B.rect_z(dx0 + 0.09, dx1 - 0.09, 2.15, 2.53, z - 0.01, "glass_lit")
    B.rect_z(dx0 + 0.09, dx1 - 0.09, 0.3, 2.53, z - 0.6, "interior_warm")
    B.box(dx0 + 0.09, dx1 - 0.09, 0.3, 2.08, z - 0.06, z - 0.02, "wood_dark", 0.006)
    frame_ring(B, dx0 + 0.09, dx1 - 0.09, 0.3, 2.08, z - 0.02, z + 0.02, 0.1, "wood_dark")
    B.box(dx0 + 0.19, dx1 - 0.19, 0.42, 1.2, z - 0.02, z + 0.005, "wood_dark", 0.01)
    B.box(dx0 + 0.19, dx1 - 0.19, 1.3, 1.98, z - 0.02, z - 0.015, "wood_dark", 0.0)
    B.rect_z(dx0 + 0.19, dx1 - 0.19, 1.3, 1.98, z + 0.001, "glass_dark")
    B.tube((dx1 - 0.2, 1.05, z + 0.02), (dx1 - 0.2, 1.05, z + 0.08), 0.025, "brass", segs=12)
    # house number plate, mailboxes, wall lamps
    B.box(dc - 0.15, dc + 0.15, 2.65, 2.8, 0.09, 0.1, "brass", 0.004)
    mbx = dx1 + 0.3
    for r in range(2):
        for c in range(2):
            x = mbx + c * 0.2
            y = 1.2 + r * 0.28
            B.box(x, x + 0.18, y, y + 0.25, 0.0, 0.08, "brass", 0.01)
    for xx in (dx0 - 0.4, dx1 + 0.4):
        if xx < PIER or xx > W - PIER:
            continue
        B.box(xx - 0.06, xx + 0.06, 2.0, 2.2, 0.0, 0.03, "metal_dark", 0.006)
        B.tube((xx, 2.12, 0.03), (xx, 2.12, 0.18), 0.012, "metal_dark", segs=8)
        B.lathe([(0.0, 1.9), (0.07, 1.92), (0.09, 2.08), (0.06, 2.16), (0.0, 2.2)], xx, 0.2, "lamp_bulb", segs=12)
        B.lathe([(0.0, 2.18), (0.11, 2.18), (0.02, 2.28), (0.0, 2.28)], xx, 0.2, "metal_dark", segs=12)
    B.marker("omni_lamp", (dc, 2.2, 0.5))
    B.marker("door", (dc, 0.3, zd))
    if W >= 3.5:
        o = ops[1]
        barred_window(B, o[0], o[1], o[2], o[3], glass="glass_dark")
    export(B, mid)
    register(mid, "ground", W, GH, "doorway", ["residential"], sign_rect=list(sign))


def gm_inn(mid, W, wall):
    """Hotel / inn entrance: the level goal. Warm lobby, double glass doors, brass lanterns."""
    B = Builder(mid)
    dc = W / 2
    dw = 1.8
    dx0, dx1 = dc - dw / 2 - 0.25, dc + dw / 2 + 0.25
    sign = ground_frame(B, W, wall, "trim_red", [(PIER, dx0, 0.0, 2.95), (dx0, dx1, 0.0, 2.95), (dx1, W - PIER, 0.0, 2.95)],
                        sign_mat="sign_board_dark")
    # stone columns flanking the door
    for (a, b) in ((dx0 - 0.3, dx0 + 0.02), (dx1 - 0.02, dx1 + 0.3)):
        B.box(a, b, 0.0, 2.95, -0.25, 0.1, "stone_trim", 0.02)
        B.box(a - 0.03, b + 0.03, 0.0, 0.42, -0.25, 0.14, "stone_trim", 0.025)
        moulding(B, a - 0.04, b + 0.04, 2.95, "stone_trim", proj=0.18, h=0.14, z=0.0)
    # lobby windows each side
    shopfront(B, PIER, dx0 - 0.3, True, "interior_hotel", "brass", "terrazzo_green", door=None)
    shopfront(B, dx1 + 0.3, W - PIER, True, "interior_hotel", "brass", "terrazzo_green", door=None)
    # entrance: two steps, recessed double doors, lit transom
    zd = -1.0
    B.box(dx0 + 0.02, dx1 - 0.02, 0.0, 0.14, zd, 0.3, "stone_trim", 0.02)
    B.box(dx0 + 0.02, dx1 - 0.02, 0.14, 0.28, zd, 0.0, "stone_trim", 0.02)
    B.rect_x(zd, 0.0, 0.28, 2.95, dx0 + 0.02, "wood_dark", facing=1)
    B.rect_x(zd, 0.0, 0.28, 2.95, dx1 - 0.02, "wood_dark", facing=-1)
    B.rect_y(dx0 + 0.02, dx1 - 0.02, zd, 0.0, 2.95, "trim_cream", facing=-1)
    B.box(dc - 0.3, dc + 0.3, 2.85, 2.95, -0.6, -0.4, "lamp_bulb", 0.02)
    interior_box(B, dx0 + 0.02, dx1 - 0.02, 0.28, 2.95, zd - 0.05, -3.0, "interior_hotel", "interior_warm", "terrazzo",
                 u_off=0.35)
    frame_ring(B, dc - dw / 2 - 0.06, dc + dw / 2 + 0.06, 0.28, 2.95, zd - 0.05, zd + 0.04, 0.07, "brass", bottom=False)
    B.box(dc - dw / 2, dc + dw / 2, 2.3, 2.37, zd - 0.04, zd + 0.03, "brass", 0.006)
    B.rect_z(dc - dw / 2, dc + dw / 2, 2.37, 2.88, zd - 0.01, "glass_lit")
    for (a, b) in ((dc - dw / 2, dc - 0.01), (dc + 0.01, dc + dw / 2)):
        frame_ring(B, a, b, 0.29, 2.3, zd - 0.03, zd + 0.02, 0.08, "brass")
        B.rect_z(a + 0.08, b - 0.08, 0.37, 2.22, zd - 0.01, "glass_lit")
        B.box(a + 0.08, b - 0.08, 0.37, 0.6, zd - 0.025, zd + 0.005, "brass", 0.004)
        hx = b - 0.12 if a < dc else a + 0.12
        B.tube((hx, 0.9, zd + 0.06), (hx, 1.6, zd + 0.06), 0.015, "brass", segs=10)
    # brass lanterns on the columns
    for xx in (dx0 - 0.14, dx1 + 0.14):
        B.tube((xx, 2.2, 0.1), (xx, 2.2, 0.32), 0.015, "brass", segs=8)
        B.lathe([(0.0, 1.95), (0.08, 1.98), (0.1, 2.15), (0.07, 2.24), (0.0, 2.26)], xx, 0.34, "lamp_bulb", segs=12)
        B.lathe([(0.0, 2.22), (0.13, 2.22), (0.03, 2.34), (0.0, 2.36)], xx, 0.34, "brass", segs=12)
        B.lathe([(0.0, 1.9), (0.06, 1.9), (0.08, 1.96), (0.0, 1.96)], xx, 0.34, "brass", segs=12)
    B.marker("omni_lamp", (dx0 - 0.14, 2.1, 0.5))
    B.marker("omni_lamp", (dx1 + 0.14, 2.1, 0.5))
    B.marker("omni_warm", (dc, 2.4, -1.6))
    B.marker("door", (dc, 0.28, zd))
    # boot scraper / doormat
    B.box(dc - 0.6, dc + 0.6, 0.28, 0.295, zd + 0.05, zd + 0.65, "trim_red", 0.004)
    export(B, mid)
    register(mid, "ground", W, GH, "inn", ["lit", "goal"], sign_rect=list(sign), door=[dc, zd])


# ------------------------------------------------------------------------------------------------
# upper storeys
# ------------------------------------------------------------------------------------------------

def window_layout(W, rng):
    n = {3: 1, 4: 2, 5: 2, 6: 3, 8: 4}.get(int(W), max(1, int(W / 2)))
    ww = {1: 1.2, 2: 1.05, 3: 1.05, 4: 1.05}[n] if W != 5 else 1.25
    pitch = W / n
    return [((k + 0.5) * pitch - ww / 2, (k + 0.5) * pitch + ww / 2) for k in range(n)]


def sash_window(B, x0, x1, y0, y1, state, trim, rng):
    """Double-hung sash window in an opening; state in lit/lit_b/dark/broken/boarded/bricked."""
    zf = -0.14
    if state == "bricked":
        B.rect_z(x0, x1, y0, y1, -0.1, "brick_dark")
        return
    # interior room
    img = {"lit": "window_lit", "lit_b": "window_lit_b"}.get(state, "window_dark")
    B.rect_z(x0, x1, y0, y1, -0.9, img, uv=(0.1, 0.0, 0.9, 1.0))
    side = "interior_warm" if state.startswith("lit") else "interior_dark"
    B.rect_x(-0.9, zf, y0, y1, x0, side, facing=1)
    B.rect_x(-0.9, zf, y0, y1, x1, side, facing=-1)
    B.rect_y(x0, x1, -0.9, zf, y1, side, facing=-1)
    B.rect_y(x0, x1, -0.9, zf, y0, "interior_dark", facing=1)
    if state.startswith("lit"):
        B.marker("omni_window", ((x0 + x1) / 2, (y0 + y1) / 2 + 0.3, -0.5))
    # frame + sashes
    t = 0.07
    frame_ring(B, x0, x1, y0, y1, zf - 0.05, zf + 0.04, t, trim)
    ym = (y0 + y1) / 2
    ix0, ix1 = x0 + t, x1 - t
    # bottom sash (back), top sash (front)
    st = 0.05
    frame_ring(B, ix0, ix1, y0 + t, ym + 0.025, zf - 0.04, zf - 0.005, st, trim)
    frame_ring(B, ix0, ix1, ym - 0.025, y1 - t, zf - 0.005, zf + 0.03, st, trim)
    xm = (ix0 + ix1) / 2
    B.box(xm - 0.015, xm + 0.015, ym + 0.02, y1 - t - st, zf + 0.0, zf + 0.025, trim, 0.003)
    B.box(xm - 0.015, xm + 0.015, y0 + t + st, ym - 0.02, zf - 0.035, zf - 0.01, trim, 0.003)
    panes_bot = [(ix0 + st, xm - 0.015, y0 + t + st, ym + 0.025 - st), (xm + 0.015, ix1 - st, y0 + t + st, ym + 0.025 - st)]
    panes_top = [(ix0 + st, xm - 0.015, ym - 0.025 + st, y1 - t - st), (xm + 0.015, ix1 - st, ym - 0.025 + st, y1 - t - st)]
    glass = "glass_dark" if not state.startswith("lit") else "glass_lit"
    for (pz, panes) in ((zf - 0.022, panes_bot), (zf + 0.012, panes_top)):
        for (a, b, c, d) in panes:
            if state == "broken" and rng.random() < 0.6:
                if rng.random() < 0.35:
                    continue  # pane completely gone
                B.shattered_pane(a, b, c, d, pz, "glass_dirty", hole=rng.uniform(0.4, 0.85))
            else:
                B.rect_z(a, b, c, d, pz, glass)
    # blinds / curtains
    if state in ("dark", "broken") and rng.random() < 0.7:
        bh = rng.uniform(0.2, 0.9)
        B.box(ix0, ix1, y1 - t - bh, y1 - t, zf - 0.09, zf - 0.07, rng.choice(["trim_cream", "plastic_beige", "trim_white"]), 0.0)
    if state == "boarded":
        x = x0 - 0.06
        while x < x1 + 0.05:
            w = min(0.6, x1 + 0.06 - x)
            box_rot(B, x + w / 2, (y0 + y1) / 2, 0.02, w - 0.01, y1 - y0 + 0.12, 0.018, rng.uniform(-0.025, 0.025), "plywood", 0.004)
            x += w
        for k in range(2):
            box_rot(B, (x0 + x1) / 2, y0 + 0.4 + k * 0.8, 0.045, x1 - x0 + 0.2, 0.12, 0.022, rng.uniform(-0.2, 0.2), "wood_boards", 0.005)


def upper(mid, W, wall, trim, states, lintel="stone", belt=True, ac=False):
    B = Builder(mid)
    rng = B.rng
    wins = window_layout(W, rng)
    y0, y1 = 0.95, 2.6
    ops = [(a, b, y0, y1) for (a, b) in wins]
    B.wall(0.0, W, 0.0, UH, 0.0, ops, wall, depth=0.14)
    end_walls(B, W, UH, wall, 1.2)
    if belt:
        B.sweep([(-0.02, 0.0), (0.05, 0.0), (0.05, 0.12), (0.03, 0.15), (-0.02, 0.15)], 0.0, W, "stone_trim")
    for i, (a, b) in enumerate(wins):
        st = states[i % len(states)]
        sash_window(B, a, b, y0, y1, st, trim, rng)
        sill(B, a - 0.08, b + 0.08, y0, "stone_trim", proj=0.08)
        if lintel == "stone":
            B.box(a - 0.1, b + 0.1, y1, y1 + 0.24, -0.02, 0.035, "stone_trim", 0.012)
            kc = (a + b) / 2
            B.prism_z([(kc - 0.09, y1 - 0.02), (kc + 0.09, y1 - 0.02), (kc + 0.12, y1 + 0.28), (kc - 0.12, y1 + 0.28)],
                      -0.02, 0.06, "stone_trim", bevel=0.01)
        elif lintel == "arch":
            # segmental brick arch approximated by a soldier course
            n = int((b - a + 0.2) / 0.075)
            for k in range(n):
                x = a - 0.1 + (k + 0.5) * (b - a + 0.2) / n
                h = 0.22 + 0.06 * math.sin(math.pi * (k + 0.5) / n)
                B.box(x - 0.033, x + 0.033, y1, y1 + h, -0.01, 0.015, wall, 0.006)
        else:  # plain metal-capped modern lintel
            B.box(a - 0.05, b + 0.05, y1, y1 + 0.12, -0.02, 0.02, "concrete", 0.01)
        if ac and i == len(wins) - 1:
            ac_unit_in_window(B, a, b, y0)
    export(B, mid)
    tags = sorted({s for s in states})
    register(mid, "upper", W, UH, None, tags + (["lit"] if any(s.startswith("lit") for s in states) else []))


def ac_unit_in_window(B, a, b, y0):
    c = (a + b) / 2
    B.box(c - 0.33, c + 0.33, y0 + 0.02, y0 + 0.45, -0.25, 0.2, "plastic_beige", 0.02)
    for k in range(7):
        B.box(c - 0.28, c + 0.28, y0 + 0.07 + k * 0.05, y0 + 0.09 + k * 0.05, 0.2, 0.215, "galvanized", 0.003)
    for sx in (-1, 1):  # angle brackets under the unit
        with kitlib.xf_push(B, kitlib.T(c + sx * 0.26, y0 + 0.02, 0.0) @ kitlib.R("Y", -90)):
            B.prism_z([(0.0, 0.0), (0.0, -0.22), (0.2, -0.01), (0.2, 0.0)], -0.012, 0.012, "metal_rust", bevel=0.003)


# ------------------------------------------------------------------------------------------------
# caps
# ------------------------------------------------------------------------------------------------

def cap_cornice(mid, W, wall, trim):
    B = Builder(mid)
    H = 0.95
    B.wall(0.0, W, 0.0, H - 0.25, 0.0, [], wall)
    end_walls(B, W, H - 0.25, wall, 1.2)
    B.rect_y(0.0, W, -1.2, -0.3, H - 0.25, "concrete", facing=1)
    # frieze
    B.box(0.0, W, 0.05, 0.45, -0.02, 0.05, trim, 0.01)
    # dentils
    x = 0.08
    while x < W - 0.1:
        B.box(x, x + 0.07, 0.45, 0.55, 0.0, 0.11, trim, 0.006)
        x += 0.14
    # brackets (consoles)
    n = max(2, int(round(W / 0.9)) + 1)
    for k in range(n):
        bx = 0.08 + k * (W - 0.16 - 0.12) / (n - 1)
        prof = [(0.0, 0.2), (0.08, 0.2), (0.12, 0.28), (0.14, 0.4), (0.22, 0.55), (0.34, 0.66), (0.4, 0.7), (0.0, 0.7)]
        B.sweep([(z, y) for (z, y) in prof], bx, bx + 0.12, trim, sharp_deg=50)
    # crown
    crown = [(0.0, 0.7), (0.42, 0.7), (0.42, 0.74), (0.46, 0.76), (0.5, 0.8), (0.52, 0.86), (0.5, 0.9),
             (0.47, 0.92), (0.47, 0.95), (-0.3, 0.95), (-0.3, 0.7)]
    B.sweep(crown, 0.0, W, trim, sharp_deg=50)
    export(B, mid)
    register(mid, "cap", W, H, None, ["cornice"])


def cap_parapet(mid, W, wall, stepped=False):
    B = Builder(mid)
    H = 0.9
    top = H
    B.wall(0.0, W, 0.0, H - 0.08, 0.0, [], wall)
    B.box(0.0, W, 0.0, H - 0.08, -0.3, 0.0, wall, 0.0)
    end_walls(B, W, 0.3, wall, 1.2)
    B.rect_y(0.0, W, -1.2, -0.3, 0.3, "concrete", facing=1)
    B.sweep([(-0.02, 0.0), (0.05, 0.0), (0.05, 0.1), (0.03, 0.13), (-0.02, 0.13)], 0.0, W, "stone_trim")
    # recessed panels
    n = max(1, int(round(W / 2.2)))
    pw = (W - 0.4) / n
    for k in range(n):
        a = 0.2 + k * pw + 0.1
        b = 0.2 + (k + 1) * pw - 0.1
        frame_ring(B, a, b, 0.24, H - 0.2, -0.01, 0.035, 0.06, "stone_trim")
    B.box(-0.02, W + 0.0, H - 0.08, H, -0.36, 0.06, "stone_trim", 0.02)        # coping
    if stepped and W >= 5:
        c = W / 2
        hw = min(1.4, W * 0.22)
        B.box(c - hw, c + hw, H - 0.08, H + 0.45, -0.3, 0.0, wall, 0.0)
        B.wall(c - hw, c + hw, H - 0.08, H + 0.45, 0.0, [], wall)
        B.box(c - hw - 0.03, c + hw + 0.03, H + 0.45, H + 0.53, -0.36, 0.06, "stone_trim", 0.02)
        B.box(c - 0.5, c + 0.5, H - 0.02, H + 0.36, -0.01, 0.04, "stone_trim", 0.01)   # date panel
        top = H + 0.53
    export(B, mid)
    register(mid, "cap", W, round(top, 3), None, ["parapet"] + (["stepped"] if stepped and W >= 5 else []))


def cap_roofedge(mid, W, wall):
    B = Builder(mid)
    H = 0.35
    B.wall(0.0, W, 0.0, H - 0.06, 0.0, [], wall)
    B.box(0.0, W, 0.0, H - 0.06, -0.3, 0.0, wall, 0.0)
    B.box(-0.0, W, H - 0.08, H, -0.34, 0.05, "galvanized", 0.01)
    end_walls(B, W, H - 0.08, wall, 1.2)
    B.rect_y(0.0, W, -1.2, -0.34, 0.1, "concrete", facing=1)
    B.box(0.0, W, H - 0.14, H - 0.08, 0.02, 0.05, "galvanized", 0.004)
    export(B, mid)
    register(mid, "cap", W, H, None, ["flat"])


# ------------------------------------------------------------------------------------------------
# side walls (face in x = 0 plane facing +X, z in [-width, 0])
# ------------------------------------------------------------------------------------------------

def side_wall(mid, D, H, wall, windows=0, ad=False, downpipe=True, plinth=False, coping=False):
    B = Builder(mid)
    B.xf = kitlib.side_xf()
    rng = B.rng
    ops = []
    for k in range(windows):
        cx = D * (k + 1) / (windows + 1)
        ops.append((cx - 0.5, cx + 0.5, 0.95, 2.45))
    B.wall(0.0, D, 0.0, H, 0.0, ops, wall, depth=0.14)
    for (a, b, c, d) in ops:
        sash_window(B, a, b, c, d, rng.choice(["dark", "broken", "boarded", "bricked"]), "trim_dark", rng)
        sill(B, a - 0.06, b + 0.06, c, "stone_trim", proj=0.06)
        B.box(a - 0.06, b + 0.06, d, d + 0.18, -0.02, 0.03, "stone_trim", 0.01)
    if plinth:
        B.box(0.0, D, 0.0, 0.45, -0.02, 0.06, "concrete", 0.02)
    if ad:
        B.rect_z(0.6, min(D - 0.6, 0.6 + 2.0 * (H - 0.6)), 0.3, H - 0.3, 0.004, "ghost_sign")
    if downpipe:
        x = D - 0.35
        B.tube((x, 0.0, 0.1), (x, H, 0.1), 0.05, "galvanized", segs=12)
        for y in (0.6, H * 0.5, H - 0.4):
            B.box(x - 0.07, x + 0.07, y, y + 0.04, 0.0, 0.16, "metal_dark", 0.006)
    if coping:
        B.box(0.0, D, H - 0.08, H, -0.06, 0.06, "stone_trim", 0.02)
    export(B, mid)


# ------------------------------------------------------------------------------------------------
# fillers
# ------------------------------------------------------------------------------------------------

def filler(mid, W, H, kind, wall):
    B = Builder(mid)
    if kind == "pilaster":
        B.wall(0.0, W, 0.0, H, -0.02, [], wall)
        B.box(0.03, W - 0.03, 0.0, H, -0.02, 0.07, wall if H < 3.5 else "stone_trim", 0.015)
        if H >= 3.5:
            B.box(0.0, W, 0.0, 0.38, -0.02, 0.1, "stone_trim", 0.02)
            moulding(B, 0.0, W, 3.1, "stone_trim", proj=0.14, h=0.16)
            moulding(B, 0.0, W, GH, "stone_trim", proj=0.16, h=0.1)
    elif kind == "downpipe":
        B.wall(0.0, W, 0.0, H, 0.0, [], wall)
        x = W / 2
        B.tube((x, 0.25 if H >= 3.5 else 0.0, 0.11), (x, H, 0.11), 0.055, "galvanized", segs=14)
        for y in ([0.9, 2.2, 3.4] if H >= 3.5 else [0.6, 2.2]):
            B.box(x - 0.08, x + 0.08, y, y + 0.045, 0.0, 0.18, "metal_dark", 0.006)
        if H >= 3.5:
            # shoe: turns out toward the sidewalk; gutter stream starts at the marker
            B.tube((x, 0.32, 0.11), (x, 0.12, 0.3), 0.055, "galvanized", segs=14)
            B.marker("outlet", (x, 0.1, 0.34))
            B.box(0.0, W, 0.0, 0.38, -0.02, 0.06, "stone_trim", 0.02)
            moulding(B, 0.0, W, GH, "stone_trim", proj=0.16, h=0.1)
    elif kind == "alley":
        # narrow dark gap between buildings with an iron gate
        B.rect_z(0.0, W, 0.0, H, -3.0, "interior_dark")
        B.rect_x(-3.0, 0.0, 0.0, H, 0.0, wall, facing=1)
        B.rect_x(-3.0, 0.0, 0.0, H, W, wall, facing=-1)
        B.rect_y(0.0, W, -3.0, 0.0, 0.002, "concrete", facing=1)
        for x in [0.05 + k * 0.11 for k in range(int((W - 0.1) / 0.11) + 1)]:
            B.tube((x, 0.0, -0.15), (x, 2.3, -0.15), 0.01, "metal_dark", segs=6)
            B.lathe([(0.0, 2.3), (0.02, 2.3), (0.0, 2.42)], x, -0.15, "metal_dark", segs=6)
        for y in (0.15, 1.2, 2.2):
            B.box(0.0, W, y, y + 0.04, -0.17, -0.13, "metal_dark", 0.005)
    export(B, mid)


# ------------------------------------------------------------------------------------------------

def main():
    kitlib.reset_scene()
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".glb"):
            os.remove(os.path.join(OUT, f))

    # ---- ground (style, width) ----
    gm_shop_lit("shop_lit_3a", 3.0, "barber", "brick_red", door="right")
    gm_shop_lit("shop_lit_4a", 4.0, "pawn", "brick_brown", door="left")
    gm_shop_lit("shop_lit_5a", 5.0, "laundromat", "plaster_teal")
    gm_shop_lit("shop_lit_6a", 6.0, "diner", "brick_red", door="right")
    gm_shop_lit("shop_lit_4b", 4.0, "newsstand", "plaster_ochre", door="right")
    gm_shop_lit("shop_lit_8a", 8.0, "diner", "brick_brown")
    gm_shop_dark("shop_dark_3a", 3.0, "plaster", door="left", broken=1, posters_n=1)
    gm_shop_dark("shop_dark_4a", 4.0, "brick_red", frame="trim_green", broken=1)
    gm_shop_dark("shop_dark_5a", 5.0, "brick_painted", frame="trim_cream", door="right", broken=2)
    gm_shop_dark("shop_dark_6a", 6.0, "plaster_ochre", frame="trim_red", broken=1, posters_n=3)
    gm_shop_dark("shop_dark_8a", 8.0, "brick_brown", frame="aluminium", broken=3, posters_n=3)
    gm_shuttered("shuttered_3a", 3.0, "brick_brown")
    gm_shuttered("shuttered_4a", 4.0, "plaster", mat="roller_door_blue")
    gm_shuttered("shuttered_5a", 5.0, "brick_red", door_side="right")
    gm_shuttered("shuttered_6a", 6.0, "brick_painted", split=True)
    gm_shuttered("shuttered_8a", 8.0, "plaster_teal", split=True, mat="roller_door_blue")
    gm_boarded("boarded_4a", 4.0, "brick_red")
    gm_boarded("boarded_5a", 5.0, "plaster", frame="trim_red")
    gm_boarded("boarded_6a", 6.0, "brick_brown", frame="trim_cream")
    gm_wall("wall_3a", 3.0, "brick_red", door_x=1.0, window=False)
    gm_wall("wall_4a", 4.0, "brick_brown", door_x=0.6)
    gm_wall("wall_5a", 5.0, "concrete", door_x=3.4)
    gm_doorway("doorway_3a", 3.0, "brick_red")
    gm_doorway("doorway_4a", 4.0, "brick_brown")
    gm_inn("inn_6a", 6.0, "brick_red")
    gm_inn("inn_8a", 8.0, "brick_brown")

    # ---- upper storeys ----
    walls = ["brick_red", "brick_brown", "plaster", "brick_painted", "plaster_teal", "brick_red", "plaster_ochre"]
    trims = ["trim_cream", "trim_green", "trim_white", "trim_dark", "trim_red"]
    variants = [
        ("a", ["dark", "dark", "lit", "dark"], "stone", False),
        ("b", ["lit", "dark", "lit_b", "dark"], "arch", True),
        ("c", ["broken", "dark", "broken", "boarded"], "stone", False),
        ("d", ["boarded", "boarded", "bricked", "boarded"], "plain", False),
        ("e", ["dark", "lit_b", "dark", "broken"], "plain", True),
    ]
    k = 0
    for W in (3.0, 4.0, 5.0, 6.0, 8.0):
        for (suf, states, lintel, ac) in variants:
            mid = "upper_%d%s" % (int(W), suf)
            st = states[k % 2:] + states[:k % 2] if suf not in ("c", "d") else states
            upper(mid, W, walls[k % len(walls)], trims[k % len(trims)], st, lintel=lintel, ac=ac)
            k += 1

    # ---- caps ----
    for i, W in enumerate((3.0, 4.0, 5.0, 6.0, 8.0)):
        w = int(W)
        cap_cornice("cap_cornice_%d" % w, W, walls[i], ["trim_green", "trim_cream", "trim_dark", "trim_red", "trim_cream"][i])
        cap_parapet("cap_parapet_%d" % w, W, walls[(i + 1) % len(walls)], stepped=(W >= 5))
        cap_roofedge("cap_flat_%d" % w, W, walls[(i + 2) % len(walls)])

    # ---- sides ----
    for D in (6.0, 10.0):
        d = int(D)
        side_wall("side_ground_%d" % d, D, GH, "brick_red", windows=0, plinth=True)
        register("side_ground_%d" % d, "side", D, GH, None, ["ground"])
        side_wall("side_upper_%d" % d, D, UH, "brick_red", windows=max(1, d // 4))
        register("side_upper_%d" % d, "side", D, UH, None, ["upper"])
        side_wall("side_cap_%d" % d, D, 0.9, "brick_red", windows=0, downpipe=False, coping=True)
        register("side_cap_%d" % d, "side", D, 0.9, None, ["cap"])
    side_wall("side_upper_ad_10", 10.0, UH, "brick_brown", windows=0, ad=True)
    register("side_upper_ad_10", "side", 10.0, UH, None, ["upper", "ghost_sign"])
    side_wall("side_ground_brown_10", 10.0, GH, "brick_brown", windows=0, plinth=True)
    register("side_ground_brown_10", "side", 10.0, GH, None, ["ground"])

    # ---- fillers ----
    for (mid, W, H, kind, wall, tags) in [
        ("filler_pilaster_g_03", 0.3, GH, "pilaster", "brick_red", ["ground"]),
        ("filler_pilaster_g_05", 0.5, GH, "pilaster", "brick_brown", ["ground"]),
        ("filler_downpipe_g_06", 0.6, GH, "downpipe", "brick_red", ["ground", "gutter"]),
        ("filler_alley_g_10", 1.0, GH, "alley", "brick_brown", ["ground", "gap"]),
        ("filler_pilaster_u_03", 0.3, UH, "pilaster", "brick_red", ["upper"]),
        ("filler_pilaster_u_05", 0.5, UH, "pilaster", "brick_brown", ["upper"]),
        ("filler_downpipe_u_06", 0.6, UH, "downpipe", "brick_red", ["upper"]),
        ("filler_brick_u_10", 1.0, UH, "pilaster", "brick_red", ["upper"]),
    ]:
        filler(mid, W, H, kind, wall)
        register(mid, "filler", W, H, None, tags)

    import retro
    retro.build(sys.modules[__name__])

    with open(os.path.join(OUT, "kit.json"), "w") as f:
        json.dump({
            "version": 2,
            "generator": "tools/blender/buildings.py (+ retro.py)",
            "notes": "ground: awning mount y=3.0, sign board face at z=sign_rect[4] spanning sign_rect[0..3] "
                     "(x0,y0,x1,y1) with its own material 'sign_face' (0..1 UVs). Markers in the scenes: "
                     "omni_* -> OmniLight3D (added by kit_import.gd), door -> Node3D at the entrance, "
                     "outlet -> downpipe gutter outlet. era: '60s' | 'retro'. aesthetics: level aesthetics a "
                     "module suits. Retro boards use material 'sign_face_dark' (prefix sign_face). Materials "
                     "named neon_* are emissive tubes (recolourable); 'holo_screen' is a 0..1-UV quad using "
                     "src/fx/holo_ad.gdshader. cover: list of boxes [x0,y0,z0,x1,y1,z1] that block rain.",
            "modules": MODULES}, f, indent=1)
    print("wrote kit.json with %d modules" % len(MODULES))


if __name__ == "__main__":
    main()
