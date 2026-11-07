"""Retro-future / neon building modules + outskirts (industrial) pieces.

Called from buildings.py (`retro.build(buildings_module)`) so everything lands in the same
assets/buildings/kit.json. Same conventions as the 60s kit: origin bottom-left at the building
line, +X along the street, facade at z = 0, depth into -Z, ground = 4.0 m, upper = 3.2 m.

Material slots that code can drive:
  neon_*        emissive tubes (neon_cyan/pink/orange/violet/green/red) - recolour by prefix
  holo_screen   0..1-UV quad for an animated holo ad (src/fx/holo_ad.gdshader by default)
  sign_face / sign_face_dark   0..1-UV sign board face (sign_rect in kit.json)
"""
import math

import kitlib
from kitlib import Builder, R, T, xf_push

NEONS = ["neon_cyan", "neon_pink", "neon_orange", "neon_violet", "neon_green", "neon_red"]
RETRO_AES = ["neon", "rundown_neon"]
OUT_AES = ["outskirts", "industrial"]

bk = None  # buildings module (set in build)


# ------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------

def sphere(B, p, r, mat, segs=8):
    x, y, z = p
    B.lathe([(0.0, y - r), (r * 0.71, y - r * 0.71), (r, y), (r * 0.71, y + r * 0.71), (0.0, y + r)], x, z, mat, segs=segs)


def neon_path(B, pts, mat, r=0.016, closed=False, wall_z=None, clips=True):
    """Glowing tube through game points; small joint spheres; optional stand-off clips to wall_z."""
    P = list(pts) + ([pts[0]] if closed else [])
    for a, b in zip(P[:-1], P[1:]):
        B.tube(a, b, r, mat, segs=8, caps=False)
    for i, p in enumerate(P[:-1] if closed else P):
        sphere(B, p, r * 1.05, mat, segs=8)
        if clips and wall_z is not None and i % 3 == 0:
            B.tube((p[0], p[1], wall_z), (p[0], p[1], p[2] - r), 0.005, "metal_dark", segs=5, caps=False)


def rounded_rect_pts(x0, x1, y0, y1, z, rad=0.12, n=4):
    pts = []
    corners = [(x1 - rad, y0 + rad, -90), (x1 - rad, y1 - rad, 0), (x0 + rad, y1 - rad, 90), (x0 + rad, y0 + rad, 180)]
    for (cx, cy, a0) in corners:
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a), z))
    return pts


def neon_rect(B, x0, x1, y0, y1, z, mat, rad=0.12, wall_z=None):
    neon_path(B, rounded_rect_pts(x0, x1, y0, y1, z, rad), mat, closed=True, wall_z=wall_z)


def panel_grid(B, x0, x1, y0, y1, z, mat, pw=0.6, ph=0.6, openings=(), gap=0.012, depth=0.025):
    """Enamel/steel panels proud of the wall plane; panel seams align with openings."""
    xs = {x0, x1}
    ys = {y0, y1}
    n = max(1, int(round((x1 - x0) / pw)))
    xs |= {x0 + (x1 - x0) * k / n for k in range(n)}
    m = max(1, int(round((y1 - y0) / ph)))
    ys |= {y0 + (y1 - y0) * k / m for k in range(m)}
    for (a, b, c, d) in openings:
        xs |= {a, b}
        ys |= {c, d}
    xs = sorted(x for x in xs if x0 <= x <= x1)
    ys = sorted(y for y in ys if y0 <= y <= y1)
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            a, b, c, d = xs[i], xs[i + 1], ys[j], ys[j + 1]
            if b - a < 0.05 or d - c < 0.05:
                continue
            cx, cy = (a + b) / 2, (c + d) / 2
            if any(o[0] < cx < o[1] and o[2] < cy < o[3] for o in openings):
                continue
            B.box(a + gap / 2, b - gap / 2, c + gap / 2, d - gap / 2, z, z + depth, mat, 0.006, segs=1)


def speedlines(B, x0, x1, y, z, n=3, gap=0.07, mat="chrome", r=0.012):
    for k in range(n):
        yy = y - k * gap
        B.tube((x0 + r, yy, z), (x1 - r, yy, z), r, mat, segs=8)
        sphere(B, (x0 + r, yy, z), r, mat, 6)
        sphere(B, (x1 - r, yy, z), r, mat, 6)


def pylon(B, xc, y0, y1, r, mat, neon=None):
    B.tube((xc, y0, 0.0), (xc, y1, 0.0), r, mat, segs=20)
    B.lathe([(0.0, y1), (r + 0.02, y1), (r + 0.03, y1 + 0.03), (r + 0.01, y1 + 0.06), (0.0, y1 + 0.06)], xc, 0.0, "chrome", segs=20)
    B.lathe([(0.0, y0), (r + 0.04, y0), (r + 0.04, y0 + 0.12), (r + 0.01, y0 + 0.16), (0.0, y0 + 0.16)], xc, 0.0, "chrome", segs=20)
    if neon:
        neon_path(B, [(xc, y0 + 0.4, r + 0.035), (xc, y1 - 0.25, r + 0.035)], neon, wall_z=r - 0.01)


def holo_frame(B, x0, x1, y0, y1, z=0.25, seed_mat="holo_screen"):
    bk.frame_ring(B, x0 - 0.05, x1 + 0.05, y0 - 0.05, y1 + 0.05, z - 0.04, z + 0.02, 0.05, "steel_dark")
    B.rect_z(x0, x1, y0, y1, z, seed_mat, uv=(0, 0, 1, 1))
    B.box(x0 + 0.2, x1 - 0.2, y0 - 0.12, y0 - 0.05, z - 0.06, z + 0.04, "steel_dark", 0.01)   # emitter bar
    B.box(x0 + 0.3, x1 - 0.3, y0 - 0.1, y0 - 0.08, z + 0.04, z + 0.045, "neon_cyan", 0.0)
    for xx in (x0 + 0.2, x1 - 0.2):
        for yy in (y0 + 0.2, y1 - 0.2):
            B.tube((xx, yy, 0.0), (xx, yy, z - 0.04), 0.02, "steel_dark", segs=8)


def vending(B, x, z_back=0.0, variant=0, w=0.9, h=1.85, d=0.7):
    """Vending machine standing on the ground with its back at z_back, centred on x."""
    body = ["enamel_coral", "enamel_teal"][variant % 2]
    B.box(x - w / 2, x + w / 2, 0.05, h, z_back, z_back + d, body, 0.03)
    B.box(x - w / 2 - 0.01, x + w / 2 + 0.01, 0.0, 0.07, z_back, z_back + d + 0.01, "steel_dark", 0.01)
    B.rect_z(x - w / 2 + 0.05, x + w / 2 - 0.05, 0.14, h - 0.05, z_back + d + 0.004, ["vending_a", "vending_b"][variant % 2], uv=(0, 0, 1, 1))
    B.box(x - w / 2 + 0.03, x + w / 2 - 0.03, h - 0.04, h + 0.03, z_back + 0.02, z_back + d + 0.02, "chrome", 0.015)
    B.marker("omni_cool", (x, 1.4, z_back + d + 0.5))


def graffiti(B, x, y, z, w, cell, ang=0.0):
    h = w * 0.5
    u0 = (cell % 2) * 0.5
    row = cell // 2
    v0 = 1.0 - (row + 1) * 0.25
    with xf_push(B, T(x, y, z) @ R("Z", ang)):
        B.rect_z(-w / 2, w / 2, -h / 2, h / 2, 0.0, "graffiti", uv=(u0, v0, u0 + 0.5, v0 + 0.25))


def ribbed(B, x0, x1, y0, y1, z, mat, pitch=0.15, depth=0.035):
    B.rect_z(x0, x1, y0, y1, z, mat)
    x = x0 + pitch * 0.3
    while x < x1 - pitch * 0.4:
        B.box(x, x + pitch * 0.42, y0, y1, z, z + depth, mat, 0.008, segs=1)
        x += pitch


def porthole(B, cx, cy, r, state="dark", z=0.0):
    rot = T(cx, cy, z) @ R("X", 90)
    with xf_push(B, rot):
        # chrome rim (local +Y = world +Z)
        B.lathe([(r - 0.02, -0.05), (r + 0.07, -0.01), (r + 0.075, 0.03), (r + 0.04, 0.06), (r - 0.02, 0.05)], 0, 0, "chrome", segs=28)
        # tunnel + back wall
        glass = "glass_lit" if state.startswith("lit") else "glass_dark"
        B.lathe([(0.0, 0.0), (r - 0.01, 0.0), (r - 0.01, 0.005), (0.0, 0.012)], 0, 0, glass, segs=24)
    back = {"lit": "window_lit", "lit_b": "window_lit_b"}.get(state, "window_dark")
    B.rect_z(cx - r, cx + r, cy - r, cy + r, z - 0.4, back, uv=(0.2, 0.2, 0.8, 0.8))
    for k in range(10):  # tunnel liner (octagon-ish panels)
        a0 = 2 * math.pi * k / 10
        a1 = 2 * math.pi * (k + 1) / 10
        p0 = (cx + r * math.cos(a0), cy + r * math.sin(a0))
        p1 = (cx + r * math.cos(a1), cy + r * math.sin(a1))
        B.quad((p1[0], p1[1], z - 0.4), (p0[0], p0[1], z - 0.4), (p0[0], p0[1], z), (p1[0], p1[1], z),
               "interior_warm" if state.startswith("lit") else "interior_dark")
    if state.startswith("lit"):
        B.marker("omni_window", (cx, cy, z - 0.2))


def retro_frame(B, W, clad, openings, neon=None, board=True, pylons=True, pylon_mat="enamel_black"):
    """Ground storey shell: clad panels, rounded pylons, streamlined fascia (awning mount y=3.0),
    pill-shaped sign board (3.1-3.9) with neon outline, chrome cap band. Returns sign_rect."""
    B.wall(0.0, W, 0.0, bk.GH, 0.0, openings, "steel_dark", depth=0.22)
    bk.end_walls(B, W, bk.GH, "steel_dark", 3.0)
    panel_grid(B, 0.0, W, 0.0, 2.95, 0.0, clad, 0.6, 0.75, openings=openings)
    if pylons:
        pylon(B, 0.17, 0.0, 2.92, 0.16, pylon_mat, neon)
        pylon(B, W - 0.17, 0.0, 2.92, 0.16, pylon_mat, neon)
    # streamlined fascia: rounded nose
    nose = [(-0.02, 2.95), (0.12, 2.95)] + [(0.12 + 0.075 * math.sin(math.pi * k / 6), 3.025 - 0.075 * math.cos(math.pi * k / 6)) for k in range(1, 6)] + [(0.12, 3.1), (-0.02, 3.1)]
    B.sweep(nose, 0.0, W, "enamel_black", sharp_deg=50)
    speedlines(B, 0.05, W - 0.05, 2.9, 0.06, n=2, gap=0.05)
    sx0, sx1 = 0.45, W - 0.45
    if board:
        B.box(sx0, sx1, 3.13, 3.87, -0.02, bk.SIGN_Z - 0.002, "enamel_black", 0.01)
        for xe in (sx0, sx1):
            B.tube((xe, 3.5, -0.02), (xe, 3.5, bk.SIGN_Z - 0.002), 0.37, "enamel_black", segs=24)
        B.rect_z(sx0 + 0.01, sx1 - 0.01, 3.15, 3.85, bk.SIGN_Z, "sign_face_dark", uv=(0, 0, 1, 1))
        if neon:
            pts = []
            r = 0.4
            for k in range(13):  # right semicircle
                a = -math.pi / 2 + math.pi * k / 12
                pts.append((sx1 + r * math.cos(a), 3.5 + r * math.sin(a), bk.SIGN_Z + 0.03))
            for k in range(13):
                a = math.pi / 2 + math.pi * k / 12
                pts.append((sx0 + r * math.cos(a), 3.5 + r * math.sin(a), bk.SIGN_Z + 0.03))
            neon_path(B, pts, neon, closed=True, wall_z=bk.SIGN_Z)
            B.marker("omni_" + neon, (W / 2, 3.4, 0.9))
    B.box(0.0, W, 3.92, 4.0, -0.02, 0.1, "chrome", 0.02)
    B.box(0.0, W, 3.1, 3.92, -0.02, 0.0, "steel_dark", 0.0)
    return [sx0, 3.15, sx1, 3.85, bk.SIGN_Z]


def reg(mid, kind, W, H, style, tags, **extra):
    bk.register(mid, kind, W, H, style, tags, era="retro", aesthetics=RETRO_AES, **extra)


# ------------------------------------------------------------------------------------------------
# retro ground modules
# ------------------------------------------------------------------------------------------------

def furn_noodle(B, x0, x1, rng):
    B.box(x0 + 0.1, x1 - 0.1, 0.0, 1.0, -1.9, -1.5, "enamel_coral", 0.02)
    B.box(x0 + 0.05, x1 - 0.05, 1.0, 1.06, -1.95, -1.42, "chrome", 0.015)
    x = x0 + 0.5
    while x < x1 - 0.4:
        B.tube((x, 0.0, -1.15), (x, 0.7, -1.15), 0.03, "chrome", segs=10)
        B.lathe([(0.0, 0.66), (0.19, 0.66), (0.2, 0.7), (0.19, 0.76), (0.0, 0.77)], x, -1.15, "enamel_teal", segs=16)
        x += 0.62
    for k in range(int((x1 - x0) / 0.9)):  # paper lanterns
        lx = x0 + 0.45 + k * 0.9
        B.tube((lx, 3.0, -0.8), (lx, 2.7, -0.8), 0.006, "metal_dark", segs=4)
        B.lathe([(0.0, 2.38), (0.1, 2.42), (0.14, 2.55), (0.1, 2.68), (0.0, 2.72)], lx, -0.8, "neon_red", segs=12)


def furn_arcade(B, x0, x1, rng):
    x = x0 + 0.15
    k = 0
    while x < x1 - 0.7:
        B.box(x, x + 0.65, 0.0, 1.8, -2.6, -1.9, "enamel_black", 0.03)
        B.box(x + 0.06, x + 0.59, 1.0, 1.55, -1.9, -1.88, NEONS[k % len(NEONS)], 0.0)
        B.box(x + 0.02, x + 0.63, 1.58, 1.78, -1.92, -1.88, NEONS[(k + 2) % len(NEONS)], 0.0)
        B.box(x + 0.05, x + 0.6, 0.85, 0.95, -1.9, -1.7, "chrome", 0.01)
        x += 0.75
        k += 1


def furn_parts(B, x0, x1, rng):
    B.box(x0 + 0.3, x1 - 0.3, 0.0, 0.9, -1.8, -1.3, "steel_dark", 0.02)
    B.box(x0 + 0.3, x1 - 0.3, 0.9, 0.95, -1.82, -1.28, "chrome", 0.01)
    for k in range(3):  # robot torso on the counter
        cx = x0 + 0.8 + k * (x1 - x0 - 1.6) / 2
        B.lathe([(0.0, 0.95), (0.14, 0.95), (0.16, 1.2), (0.12, 1.35), (0.0, 1.36)], cx, -1.55, "aluminium", segs=16)
        sphere(B, (cx, 1.47, -1.55), 0.1, "aluminium", 12)
        B.box(cx - 0.06, cx + 0.06, 1.45, 1.49, -1.46, -1.44, "neon_cyan", 0.0)


def furn_cafe(B, x0, x1, rng):
    x = x0 + 0.3
    while x < x1 - 0.9:
        B.box(x, x + 0.8, 0.0, 0.75, -1.6, -1.2, "steel_dark", 0.02)
        B.box(x + 0.1, x + 0.7, 0.75, 1.15, -1.55, -1.5, "steel_dark", 0.01)
        B.box(x + 0.14, x + 0.66, 0.79, 1.11, -1.5, -1.495, "neon_green", 0.0)
        x += 1.0


SHOPS = {
    "noodle": ("interior_noodle", furn_noodle, "interior_warm"),
    "arcade": ("interior_arcade", furn_arcade, "interior_cool"),
    "parts": ("interior_parts", furn_parts, "interior_cool"),
    "cafe": ("interior_cafe", furn_cafe, "interior_cool"),
}


def r_shop_lit(mid, W, shop, clad, neon, door="center", vending_niche=False, holo=False):
    img, furn, side = SHOPS[shop]
    B = Builder(mid)
    x0, x1 = 0.33, W - 0.33
    if vending_niche:
        x1 = W - 1.35
    ops = [(x0, x1, 0.0, 2.95)]
    if vending_niche:
        ops.append((x1 + 0.1, W - 0.33, 0.0, 2.2))
    sign = retro_frame(B, W, clad, ops, neon=neon)
    bk.shopfront(B, x0, x1, True, img, "chrome", "terrazzo_green" if shop != "noodle" else "enamel_black",
                 door=door, furniture=furn, side_mat=side)
    neon_rect(B, x0 + 0.06, x1 - 0.06, 0.6, 2.88, 0.03, neon, rad=0.2, wall_z=0.0)
    if vending_niche:
        nx0, nx1 = x1 + 0.1, W - 0.33
        B.rect_z(nx0, nx1, 0.0, 2.2, -0.75, "steel_dark")
        B.rect_y(nx0, nx1, -0.75, 0.0, 0.002, "terrazzo", facing=1)
        vending(B, (nx0 + nx1) / 2, -0.72, variant=W > 6)
    bk.export(B, mid)
    reg(mid, "ground", W, bk.GH, "shop_lit", ["lit", shop, "neon"], sign_rect=sign)


def r_shop_dark(mid, W, clad, neon_dead=True):
    B = Builder(mid)
    rng = B.rng
    x0, x1 = 0.33, W - 0.33
    sign = retro_frame(B, W, clad, [(x0, x1, 0.0, 2.95)], neon=None)
    # dead neon around the sign + window
    sx0, sx1 = 0.45, W - 0.45
    neon_rect(B, sx0 - 0.3, sx1 + 0.3, 3.12, 3.88, bk.SIGN_Z + 0.03, "neon_dead", rad=0.36, wall_z=bk.SIGN_Z)
    bk.shopfront(B, x0, x1, False, "interior_empty", "chrome", "enamel_black", door="left", broken=2, posters_n=1)
    neon_rect(B, x0 + 0.06, x1 - 0.06, 0.6, 2.88, 0.03, "neon_dead", rad=0.2, wall_z=0.0)
    # one flickering survivor + graffiti on the cladding
    neon_path(B, [(x1 - 0.5, 0.9, 0.05), (x1 - 0.5, 2.2, 0.05)], "neon_pink", wall_z=0.0)
    for k in range(2):
        graffiti(B, rng.uniform(0.8, W - 0.8), rng.uniform(0.25, 0.45), 0.03, 1.1, rng.randrange(8), rng.uniform(-0.05, 0.05))
    bk.export(B, mid)
    reg(mid, "ground", W, bk.GH, "shop_dark", ["dark", "dead_neon", "graffiti"], sign_rect=sign)


def r_shuttered(mid, W, clad, mat="roller_door", split=False, vending_side=False):
    B = Builder(mid)
    rng = B.rng
    x0, x1 = 0.33, W - 0.33
    if vending_side:
        x1 = W - 1.3
    ops = [(x0, x1, 0.0, 2.95)]
    sign = retro_frame(B, W, clad, ops, neon=rng.choice(NEONS) if rng.random() < 0.5 else None)
    B.rect_z(x0, x1, 0.0, 2.95, -0.25, "interior_dark")
    if split and (x1 - x0) > 3.5:
        m = (x0 + x1) / 2
        B.box(m - 0.08, m + 0.08, 0.0, 2.95, -0.22, -0.02, "steel_dark", 0.01)
        bk.roller_shutter(B, x0, m - 0.08, 2.62, mat, posters_n=0)
        bk.roller_shutter(B, m + 0.08, x1, 2.62, mat, posters_n=0)
    else:
        bk.roller_shutter(B, x0, x1, 2.62, mat, posters_n=0)
    B.rect_z(x0, x1, 2.62, 2.95, -0.21, "interior_dark")
    # graffiti sprayed across the slats
    n = max(1, int((x1 - x0) / 1.6))
    for k in range(n):
        gx = x0 + (k + 0.5) * (x1 - x0) / n
        graffiti(B, gx + rng.uniform(-0.2, 0.2), rng.uniform(0.7, 1.7), -0.097, min(1.5, (x1 - x0) / n * 0.95), rng.randrange(8), rng.uniform(-0.08, 0.08))
    if vending_side:
        vending(B, W - 0.8, 0.0, variant=rng.randrange(2))
    bk.export(B, mid)
    reg(mid, "ground", W, bk.GH, "shuttered", ["dark", "graffiti"], sign_rect=sign)


def r_wall(mid, W, clad, vend=1, holo=False):
    B = Builder(mid)
    rng = B.rng
    door_x = 0.5
    ops = [(door_x, door_x + 1.0, 0.0, 2.3)]
    gb_x0 = door_x + 1.4
    gb_x1 = min(W - 0.4, gb_x0 + 1.6)
    gb_x0 = round(gb_x0 / 0.2) * 0.2
    gb_x1 = round(gb_x1 / 0.2) * 0.2
    ops.append((gb_x0, gb_x1, 0.8, 2.6))
    sign = retro_frame(B, W, clad, ops, neon=None, board=True)
    # porthole service door
    bk.steel_door(B, door_x + 0.06, door_x + 0.94, 2.24, "steel_dark", z=-0.12)
    porthole(B, door_x + 0.5, 1.6, 0.16, "dark", z=-0.08)
    B.box(door_x - 0.05, door_x + 1.05, 2.3, 2.4, -0.02, 0.05, "chrome", 0.01)
    # glass-block panel, glowing from inside
    B.box(gb_x0, gb_x1, 0.8, 2.6, -0.16, -0.06, "glass_block_lit", 0.0)
    bk.frame_ring(B, gb_x0 - 0.04, gb_x1 + 0.04, 0.76, 2.64, -0.08, 0.03, 0.04, "chrome")
    # vending machines in front of the wall
    vx = gb_x1 + 0.6
    for k in range(vend):
        if vx + 0.45 > W - 0.35:
            break
        vending(B, vx, 0.03, variant=k + rng.randrange(2))
        vx += 1.0
    # pipes & cable conduit
    B.tube((0.4, 0.0, 0.1), (0.4, 3.9, 0.1), 0.04, "steel_ribbed", segs=10)
    for k in range(3):
        y = 2.75 + k * 0.05
        B.tube((0.4, y, 0.06 + k * 0.03), (W - 0.4, y - 0.02, 0.06 + k * 0.03), 0.015, "rubber", segs=6)
    graffiti(B, rng.uniform(1.0, W - 1.0), 0.45, 0.03, 1.2, rng.randrange(8))
    if holo and W >= 6:
        holo_frame(B, W - 2.6, W - 0.6, 3.15, 3.85, z=0.2)
    bk.export(B, mid)
    reg(mid, "ground", W, bk.GH, "wall", ["dark", "glass_block", "vending"], sign_rect=sign)


def r_doorway(mid, W, clad, neon):
    """Capsule-apartment entrance: rounded portal, porthole door, intercom, glass-block sidelights."""
    B = Builder(mid)
    dc = W / 2 if W < 3.5 else 1.4
    dx0, dx1 = dc - 0.6, dc + 0.6
    ops = [(dx0, dx1, 0.0, 2.6)]
    for xe in (dx0 - 0.6, dx1 + 0.2):
        ops.append((round(xe / 0.2) * 0.2, round(xe / 0.2) * 0.2 + 0.4, 0.4, 2.4))
    sign = retro_frame(B, W, clad, ops, neon=None)
    # rounded portal surround (arch top)
    B.prism_z([(dx0 - 0.15, 0.0), (dx0, 0.0), (dx0, 2.6), (dx0 - 0.15, 2.6)], -0.02, 0.09, "chrome", bevel=0.01)
    B.prism_z([(dx1, 0.0), (dx1 + 0.15, 0.0), (dx1 + 0.15, 2.6), (dx1, 2.6)], -0.02, 0.09, "chrome", bevel=0.01)
    top = []
    for k in range(13):
        a = math.pi * k / 12
        top.append((dc + 0.75 * math.cos(a), 2.6 + 0.4 * math.sin(a)))
    inner = [(dc + 0.6 * math.cos(math.pi * k / 12), 2.6 + 0.28 * math.sin(math.pi * k / 12)) for k in range(13)]
    for k in range(12):
        B.prism_z([top[k], inner[k], inner[k + 1], top[k + 1]][::-1], -0.02, 0.09, "chrome")
        B.prism_z([(inner[k + 1][0], 2.6), (inner[k][0], 2.6), inner[k], inner[k + 1]], -0.3, -0.25, "glass_block_lit")
    neon_path(B, [(dc + 0.85 * math.cos(math.pi * k / 16), 2.6 + 0.5 * math.sin(math.pi * k / 16), 0.12) for k in range(17)], neon, wall_z=0.0)
    # steps + door with porthole
    zd = -0.3
    B.box(dx0, dx1, 0.0, 0.15, zd, 0.22, "terrazzo", 0.02)
    B.box(dx0 + 0.05, dx1 - 0.05, 0.15, 2.58, zd - 0.05, zd, "enamel_teal", 0.02)
    porthole(B, dc, 1.6, 0.22, "lit", z=zd + 0.01)
    B.box(dc + 0.38, dc + 0.42, 0.9, 1.3, zd, zd + 0.05, "chrome", 0.01)
    # intercom with a little screen
    ix = dx0 - 0.25 if W < 3.5 else dx1 + 0.75
    B.box(ix - 0.1, ix + 0.1, 1.2, 1.6, 0.02, 0.07, "chrome", 0.01)
    B.rect_z(ix - 0.07, ix + 0.07, 1.38, 1.55, 0.072, "holo_screen", uv=(0, 0, 1, 1))
    for k in range(6):
        B.box(ix - 0.06 + (k % 2) * 0.07, ix - 0.01 + (k % 2) * 0.07, 1.23 + (k // 2) * 0.045, 1.26 + (k // 2) * 0.045, 0.07, 0.078, "neon_orange", 0.0)
    # glass-block sidelights
    for (a, b, c, d) in ops[1:]:
        B.box(a, b, c, d, -0.16, -0.06, "glass_block_lit", 0.0)
        bk.frame_ring(B, a - 0.03, b + 0.03, c - 0.03, d + 0.03, -0.08, 0.03, 0.03, "chrome")
    # neon arrow pointing at the door
    ax = dx1 + 0.45 if W >= 3.5 else dx1 + 0.2
    if ax + 0.3 < W - 0.35:
        neon_path(B, [(ax + 0.3, 2.85, 0.12), (ax, 2.85, 0.12), (ax, 2.4, 0.12)], neon, wall_z=0.0)
        neon_path(B, [(ax - 0.12, 2.55, 0.12), (ax, 2.4, 0.12), (ax + 0.12, 2.55, 0.12)], neon, wall_z=0.0)
    B.marker("omni_" + neon, (dc, 2.7, 0.6))
    B.marker("door", (dc, 0.15, zd))
    bk.export(B, mid)
    reg(mid, "ground", W, bk.GH, "doorway", ["residential", "neon"], sign_rect=sign)


def r_inn(mid, W, neon):
    """Googie hotel entrance (level goal): chrome-framed glass doors, lit lobby, starburst."""
    B = Builder(mid)
    dc = W / 2
    dw = 1.8
    dx0, dx1 = dc - dw / 2 - 0.2, dc + dw / 2 + 0.2
    ops = [(0.33, dx0 - 0.25, 0.0, 2.95), (dx0, dx1, 0.0, 2.95), (dx1 + 0.25, W - 0.33, 0.0, 2.95)]
    sign = retro_frame(B, W, "enamel_cream", ops, neon=neon, pylon_mat="enamel_teal")
    for (a, b) in ((dx0 - 0.25, dx0), (dx1, dx1 + 0.25)):
        pylon(B, (a + b) / 2, 0.0, 2.92, 0.13, "enamel_teal", neon)
    bk.shopfront(B, 0.33, dx0 - 0.25, True, "interior_lobby_retro", "chrome", "terrazzo_green", door=None)
    bk.shopfront(B, dx1 + 0.25, W - 0.33, True, "interior_lobby_retro", "chrome", "terrazzo_green", door=None)
    zd = -0.9
    B.box(dx0 + 0.02, dx1 - 0.02, 0.0, 0.14, zd, 0.28, "terrazzo", 0.02)
    B.rect_x(zd, 0.0, 0.14, 2.95, dx0 + 0.02, "enamel_teal", facing=1)
    B.rect_x(zd, 0.0, 0.14, 2.95, dx1 - 0.02, "enamel_teal", facing=-1)
    B.rect_y(dx0 + 0.02, dx1 - 0.02, zd, 0.0, 2.95, "enamel_cream", facing=-1)
    for k in range(3):  # recessed disc lights in the soffit
        B.tube((dc - 0.6 + k * 0.6, 2.95, -0.45), (dc - 0.6 + k * 0.6, 2.93, -0.45), 0.1, "lamp_bulb", segs=16)
    bk.interior_box(B, dx0 + 0.02, dx1 - 0.02, 0.14, 2.95, zd - 0.05, -3.0, "interior_lobby_retro", "interior_warm", "terrazzo", u_off=0.3)
    bk.frame_ring(B, dc - dw / 2 - 0.06, dc + dw / 2 + 0.06, 0.14, 2.95, zd - 0.05, zd + 0.04, 0.07, "chrome", bottom=False)
    B.rect_z(dc - dw / 2, dc + dw / 2, 2.35, 2.88, zd - 0.01, "glass_lit")
    for (a, b) in ((dc - dw / 2, dc - 0.01), (dc + 0.01, dc + dw / 2)):
        bk.frame_ring(B, a, b, 0.15, 2.3, zd - 0.03, zd + 0.02, 0.06, "chrome")
        B.rect_z(a + 0.06, b - 0.06, 0.21, 2.24, zd - 0.01, "glass_lit")
        hx = b - 0.12 if a < dc else a + 0.12
        B.tube((hx, 0.8, zd + 0.06), (hx, 1.7, zd + 0.06), 0.018, "chrome", segs=10)
    # starburst on the left end of the sign band
    sx, sy = 0.9, 4.45
    for k in range(12):
        a = 2 * math.pi * k / 12
        L = 0.55 if k % 2 == 0 else 0.35
        B.tube((sx, sy, 0.15), (sx + L * math.cos(a), sy + L * math.sin(a), 0.15), 0.012, "chrome", segs=6)
        sphere(B, (sx + L * math.cos(a), sy + L * math.sin(a), 0.15), 0.035, neon if k % 2 == 0 else "lamp_bulb", 8)
    sphere(B, (sx, sy, 0.15), 0.09, "chrome", 12)
    B.tube((sx, 3.95, 0.05), (sx, sy, 0.15), 0.02, "chrome", segs=8)
    B.marker("omni_warm", (dc, 2.4, -1.6))
    B.marker("door", (dc, 0.14, zd))
    bk.export(B, mid)
    reg(mid, "ground", W, bk.GH, "inn", ["lit", "goal", "neon"], sign_rect=sign, door=[dc, zd])


def r_kiosk(mid, W, neon):
    """Walk-up noodle counter: open front with a raised shutter and hanging lanterns."""
    B = Builder(mid)
    x0, x1 = 0.33, W - 0.33
    sign = retro_frame(B, W, "enamel_coral", [(x0, x1, 0.0, 2.95)], neon=neon)
    bk.interior_box(B, x0, x1, 0.0, 2.95, -0.25, -2.4, "interior_noodle", "interior_warm", "terrazzo", "interior_warm", u_off=0.1)
    B.box(x0, x1, 0.0, 1.05, -0.55, -0.1, "enamel_black", 0.02)                      # counter front
    B.box(x0 - 0.02, x1 + 0.02, 1.05, 1.11, -0.6, 0.12, "chrome", 0.02)              # counter top
    speedlines(B, x0 + 0.05, x1 - 0.05, 0.85, -0.09, n=3, gap=0.06)
    B.box(x0, x1, 2.62, 2.95, -0.26, 0.06, "galvanized", 0.06)                      # rolled-up shutter
    for k in range(int((x1 - x0) / 0.7)):
        lx = x0 + 0.35 + k * 0.7
        B.tube((lx, 2.62, -0.05), (lx, 2.35, -0.05), 0.006, "metal_dark", segs=4)
        B.lathe([(0.0, 2.02), (0.1, 2.06), (0.14, 2.18), (0.1, 2.31), (0.0, 2.35)], lx, -0.05, "neon_red" if k % 2 == 0 else "neon_orange", segs=12)
    for k in range(4):
        B.lathe([(0.0, 1.11), (0.09, 1.11), (0.11, 1.17), (0.08, 1.2), (0.0, 1.2)], x0 + 0.4 + k * (x1 - x0 - 0.8) / 3, -0.25, "enamel_cream", segs=14)
    B.marker("omni_warm", (W / 2, 2.2, -0.6))
    bk.export(B, mid)
    reg(mid, "ground", W, bk.GH, "shop_lit", ["lit", "noodle", "kiosk", "neon"], sign_rect=sign)


# ------------------------------------------------------------------------------------------------
# retro uppers and caps
# ------------------------------------------------------------------------------------------------

def cable_bundle(B, x0, x1, y, z, n=4, sag=0.25, rng=None):
    rng = rng or B.rng
    for k in range(n):
        yy = y + rng.uniform(-0.05, 0.05)
        zz = z + k * 0.03
        s = sag * rng.uniform(0.5, 1.3)
        pts = []
        for i in range(11):
            t = i / 10
            pts.append((x0 + (x1 - x0) * t, yy - s * 4 * t * (1 - t), zz))
        for a, b in zip(pts[:-1], pts[1:]):
            B.tube(a, b, 0.012, "rubber", segs=5, caps=False)


def dish(B, x, y, z, r=0.35, ang=25):
    with xf_push(B, T(x, y, z) @ R("Y", ang) @ R("X", 60)):
        B.lathe([(0.0, 0.0), (r * 0.5, 0.03), (r, 0.12), (r + 0.01, 0.13), (r * 0.5, 0.06), (0.0, 0.03)], 0, 0, "aluminium", segs=20)
        B.tube((0, 0.0, 0), (0, r * 0.9, 0), 0.012, "aluminium", segs=6)
        sphere(B, (0, r * 0.9, 0), 0.03, "steel_dark", 6)
    B.tube((x, y - 0.3, z - 0.1), (x, y, z), 0.025, "steel_dark", segs=8)


def r_upper(mid, W, variant, neon):
    B = Builder(mid)
    rng = B.rng
    H = bk.UH
    if variant == "a":   # ribbed cladding + ribbon window
        ops = [(0.2, W - 0.2, 1.0, 2.3)]
        B.wall(0.0, W, 0.0, H, -0.02, ops, "steel_dark", depth=0.12)
        ribbed(B, 0.0, W, 0.0, 1.0, 0.0, "steel_ribbed")
        ribbed(B, 0.0, W, 2.3, H, 0.0, "steel_ribbed")
        n = max(2, int(W / 1.0))
        xs = [0.2 + (W - 0.4) * k / n for k in range(n + 1)]
        for i in range(n):
            a, b = xs[i] + 0.03, xs[i + 1] - 0.03
            lit = rng.random() < 0.35
            B.rect_z(a, b, 1.0, 2.3, -0.12, "glass_lit" if lit else "glass_dark")
            B.rect_z(a, b, 1.0, 2.3, -0.8, "window_lit_b" if lit else "window_dark", uv=(0.1, 0.0, 0.9, 1.0))
            if lit:
                B.marker("omni_window", ((a + b) / 2, 1.8, -0.4))
        for x in xs:
            B.box(x - 0.03, x + 0.03, 1.0, 2.3, -0.13, -0.05, "chrome", 0.006)
        B.box(0.15, W - 0.15, 0.92, 1.0, -0.12, 0.08, "chrome", 0.015)
        B.box(0.15, W - 0.15, 2.3, 2.36, -0.12, 0.06, "chrome", 0.01)
        B.rect_x(-0.8, -0.12, 1.0, 2.3, 0.2, "interior_dark", facing=1)
        B.rect_x(-0.8, -0.12, 1.0, 2.3, W - 0.2, "interior_dark", facing=-1)
        cable_bundle(B, 0.0, W, 2.95, 0.08, n=3, rng=rng)
        tags = ["ribbed", "ribbon_window"]
    elif variant == "b":  # enamel panels + portholes + neon stripe
        n = max(1, int(round(W / 1.6)))
        r = 0.42
        holes = [((k + 0.5) * W / n - r, (k + 0.5) * W / n + r, 1.65 - r, 1.65 + r) for k in range(n)]
        B.wall(0.0, W, 0.0, H, -0.02, [], "steel_dark")
        panel_grid(B, 0.0, W, 0.2, H, 0.0, rng.choice(["enamel_cream", "enamel_mint", "enamel_teal"]), 0.8, 0.75, openings=holes)
        for k, (a, b, c, d) in enumerate(holes):
            porthole(B, (a + b) / 2, (c + d) / 2, r - 0.06, rng.choice(["lit", "dark", "dark", "lit_b"]), z=0.03)
        B.box(0.0, W, 0.0, 0.2, -0.02, 0.06, "enamel_black", 0.01)
        neon_path(B, [(0.15, 0.1, 0.09), (W - 0.15, 0.1, 0.09)], neon, wall_z=0.06)
        B.marker("omni_" + neon, (W / 2, 0.2, 0.7))
        tags = ["enamel", "porthole", "neon"]
    elif variant == "c":  # holo frame + ribbed + strip windows
        B.wall(0.0, W, 0.0, H, -0.02, [(0.3, W - 0.3, 2.55, 2.95)], "steel_dark", depth=0.1)
        ribbed(B, 0.0, W, 0.0, 2.55, 0.0, "steel_ribbed", pitch=0.2)
        ribbed(B, 0.0, W, 2.95, H, 0.0, "steel_ribbed", pitch=0.2)
        B.rect_z(0.3, W - 0.3, 2.55, 2.95, -0.1, "glass_block_lit" if rng.random() < 0.5 else "glass_dark")
        hw = min(W - 1.0, 4.0)
        holo_frame(B, (W - hw) / 2, (W + hw) / 2, 0.35, 2.25, z=0.3)
        tags = ["ribbed", "holo"]
    else:  # "d": glass block + AC units + cables + dish
        B.wall(0.0, W, 0.0, H, -0.02, [], "steel_dark")
        panel_grid(B, 0.0, W, 0.0, H, 0.0, "enamel_black", 1.0, 0.8)
        gx0 = round((W * 0.2) / 0.2) * 0.2
        gx1 = round((W * 0.8) / 0.2) * 0.2
        B.box(gx0, gx1, 1.0, 2.4, -0.02, 0.06, "glass_block_lit" if rng.random() < 0.6 else "glass_block", 0.0)
        bk.frame_ring(B, gx0 - 0.04, gx1 + 0.04, 0.96, 2.44, 0.0, 0.09, 0.04, "chrome")
        for k in range(max(1, int(W / 3))):
            ax = 0.6 + k * 2.6
            if ax + 0.4 > W:
                break
            B.box(ax - 0.33, ax + 0.33, 0.25, 0.7, 0.03, 0.55, "plastic_beige", 0.02)
            for j in range(7):
                B.box(ax - 0.28, ax + 0.28, 0.3 + j * 0.055, 0.32 + j * 0.055, 0.55, 0.565, "galvanized", 0.0)
            B.marker("vent", (ax, 0.45, 0.6))
        cable_bundle(B, 0.0, W, 2.9, 0.08, n=5, sag=0.35, rng=rng)
        cable_bundle(B, 0.0, W, 0.9, 0.1, n=2, sag=0.15, rng=rng)
        tags = ["glass_block", "ac", "cables"]
    bk.end_walls(B, W, H, "steel_dark", 1.2)
    bk.export(B, mid)
    reg(mid, "upper", W, H, None, tags + (["holo"] if variant == "c" else []))


def r_cap(mid, W, kind, neon):
    B = Builder(mid)
    rng = B.rng
    if kind == "band":
        H = 0.7
        B.wall(0.0, W, 0.0, H, 0.0, [], "steel_dark")
        nose = [(-0.3, 0.0), (0.06, 0.0)] + [(0.06 + 0.12 * math.sin(math.pi * k / 10), 0.3 - 0.3 * math.cos(math.pi * k / 10)) for k in range(1, 10)] + [(0.06, 0.6), (0.0, H), (-0.3, H)]
        B.sweep(nose, 0.0, W, rng.choice(["enamel_cream", "enamel_teal", "enamel_coral"]), sharp_deg=50)
        speedlines(B, 0.05, W - 0.05, 0.42, 0.18, n=3, gap=0.08)
        neon_path(B, [(0.1, H + 0.02, 0.02), (W - 0.1, H + 0.02, 0.02)], neon, wall_z=None)
        B.marker("omni_" + neon, (W / 2, H, 0.8))
        tags = ["streamline", "neon"]
    elif kind == "dish":
        H = 0.5
        B.wall(0.0, W, 0.0, H, 0.0, [], "steel_dark")
        B.box(0.0, W, H - 0.06, H, -0.35, 0.06, "chrome", 0.02)
        ribbed(B, 0.0, W, 0.0, H - 0.06, 0.0, "steel_ribbed", pitch=0.2)
        for k in range(max(1, int(W / 3.0))):
            dish(B, 0.8 + k * 2.8 + rng.uniform(-0.2, 0.2), H + 0.45, -0.4, r=rng.uniform(0.3, 0.5), ang=rng.uniform(-40, 40))
        mx = W - 0.5
        B.tube((mx, H, -0.3), (mx, H + 2.6, -0.3), 0.025, "steel_dark", segs=8)
        for j in range(4):
            y = H + 1.0 + j * 0.4
            B.tube((mx - 0.3 + j * 0.05, y, -0.3), (mx + 0.3 - j * 0.05, y, -0.3), 0.01, "aluminium", segs=5)
        sphere(B, (mx, H + 2.62, -0.3), 0.04, "neon_red", 8)
        cable_bundle(B, 0.2, W - 0.2, H + 0.05, 0.08, n=3, sag=0.1, rng=rng)
        H = H + 2.66
        tags = ["dish", "antenna", "cables"]
    else:  # "neon": rooftop lattice frame carrying a big neon outline + holo screen
        H = 2.6
        base = 0.4
        B.wall(0.0, W, 0.0, base, 0.0, [], "steel_dark")
        B.box(0.0, W, base - 0.06, base, -0.35, 0.06, "chrome", 0.02)
        fx0, fx1 = 0.3, W - 0.3
        top = H - 0.1
        for x in (fx0, fx1):
            B.tube((x, base, -0.3), (x, top, -0.3), 0.03, "steel_dark", segs=8)
            B.tube((x, base, -0.9), (x, top - 0.4, -0.3), 0.02, "steel_dark", segs=6)  # brace
        x = fx0
        while x < fx1 - 0.6:  # lattice diagonals
            B.tube((x, base + 0.05, -0.33), (x + 0.6, top, -0.33), 0.01, "steel_dark", segs=5)
            x += 0.6
        B.tube((fx0, top, -0.3), (fx1, top, -0.3), 0.03, "steel_dark", segs=8)
        B.tube((fx0, base + 0.1, -0.3), (fx1, base + 0.1, -0.3), 0.03, "steel_dark", segs=8)
        if W >= 4:
            hw = min(W - 1.4, 3.6)
            B.rect_z((W - hw) / 2, (W + hw) / 2, base + 0.4, top - 0.35, -0.24, "holo_screen", uv=(0, 0, 1, 1))
        neon_rect(B, fx0 + 0.1, fx1 - 0.1, base + 0.2, top - 0.1, -0.2, neon, rad=0.25, wall_z=-0.3)
        if W >= 5:
            neon_rect(B, fx0 + 0.25, fx1 - 0.25, base + 0.32, top - 0.22, -0.2, NEONS[(NEONS.index(neon) + 2) % len(NEONS)], rad=0.18, wall_z=-0.3)
        B.marker("omni_" + neon, (W / 2, (base + top) / 2, 0.6))
        tags = ["neon_frame", "holo"] if W >= 4 else ["neon_frame"]
    end_h = 0.4 if kind != "band" else 0.7
    bk.end_walls(B, W, end_h, "steel_dark", 1.2)
    B.rect_y(0.0, W, -1.2, -0.3, end_h, "concrete", facing=1)
    bk.export(B, mid)
    reg(mid, "cap", W, round(H, 3), None, tags)


def r_side(mid, D, H, kind):
    B = Builder(mid)
    B.xf = kitlib.side_xf()
    rng = B.rng
    B.wall(0.0, D, 0.0, H, -0.02, [], "steel_dark")
    if kind == "ground":
        panel_grid(B, 0.0, D, 0.0, H - 0.1, 0.0, "enamel_black", 1.0, 0.8)
        for k in range(3):
            graffiti(B, rng.uniform(1.0, D - 1.0), rng.uniform(0.6, 1.8), 0.03, rng.uniform(1.2, 1.8), rng.randrange(8))
        vending(B, D - 1.2, 0.03, variant=1)
        neon_path(B, [(0.3, 3.4, 0.08), (D - 0.3, 3.4, 0.08)], "neon_cyan", wall_z=0.025)
        B.box(0.0, D, H - 0.1, H, -0.02, 0.08, "chrome", 0.02)
        tags = ["ground"]
    elif kind == "upper":
        ribbed(B, 0.0, D, 0.0, H, 0.0, "steel_ribbed")
        for k in range(2):
            a = 1.0 + k * (D / 2)
            B.box(a, a + D / 2 - 2.0, 1.4, 2.0, 0.035, 0.05, "glass_dark", 0.0)
            bk.frame_ring(B, a - 0.04, a + D / 2 - 1.96, 1.36, 2.04, 0.03, 0.07, 0.04, "chrome")
        cable_bundle(B, 0.0, D, 2.9, 0.08, n=4, rng=rng)
        tags = ["upper"]
    else:
        prof = [(-0.3, 0.0), (0.06, 0.0)] + [(0.06 + 0.1 * math.sin(math.pi * k / 10), 0.25 - 0.25 * math.cos(math.pi * k / 10)) for k in range(1, 10)] + [(0.06, 0.5), (-0.3, 0.5)]
        B.sweep(prof, 0.0, D, "enamel_cream", sharp_deg=50)
        H = 0.5
        tags = ["cap"]
    bk.export(B, mid)
    reg(mid, "side", D, H, None, tags)


# ------------------------------------------------------------------------------------------------
# outskirts / industrial
# ------------------------------------------------------------------------------------------------

def corrugated(B, x0, x1, y0, y1, z, mat, pitch=0.076, amp=0.012):
    """Vertical corrugated sheet (sine profile swept upwards) facing +Z."""
    pts = []
    x = x0
    while x <= x1 + 1e-6:
        pts.append((x, z + amp * math.cos(2 * math.pi * (x - x0) / pitch)))
        x += pitch / 6
    # sweep along Y: build quads directly
    for (xa, za), (xb, zb) in zip(pts[:-1], pts[1:]):
        f = B.quad((xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za), mat, smooth=True)


def oreg(mid, kind, W, H, style, tags, **extra):
    bk.register(mid, kind, W, H, style, tags + ["outskirts", "industrial"], era="60s", aesthetics=OUT_AES, **extra)


def warehouse(mid, W, mat, door_w=3.4):
    B = Builder(mid)
    rng = B.rng
    dx0 = 0.6 if W < 7 else W - door_w - 1.6
    ops = [(dx0, dx0 + door_w, 0.0, 3.0), (dx0 + door_w + 0.5 if W < 7 else 0.9, (dx0 + door_w + 1.5) if W < 7 else 1.9, 0.0, 2.2)]
    if ops[1][1] > W - 0.2:
        ops = ops[:1]
    B.wall(0.0, W, 0.0, bk.GH, -0.03, ops, "steel_dark", depth=0.2)
    bk.end_walls(B, W, bk.GH, "steel_dark", 3.0)
    # corrugated cladding around the openings
    xs = sorted({0.0, W} | {o[0] for o in ops} | {o[1] for o in ops})
    for a, b in zip(xs[:-1], xs[1:]):
        inside = [o for o in ops if o[0] <= a and b <= o[1]]
        y0 = max([o[3] for o in inside], default=0.45)
        corrugated(B, a, b, y0, 3.55, 0.0, mat)
    B.box(0.0, W, 0.0, 0.45, -0.03, 0.08, "concrete", 0.02)                         # plinth
    # translucent clerestory band + flashing
    B.box(0.0, W, 3.55, 3.85, -0.03, 0.02, "glass_dirty", 0.0)
    for x in [k * 1.0 for k in range(int(W) + 1)]:
        B.box(max(0.0, x - 0.03), min(W, x + 0.03), 3.55, 3.85, 0.0, 0.04, "galvanized", 0.004)
    B.box(0.0, W, 3.85, 4.0, -0.3, 0.12, "galvanized", 0.01)
    # big roll-up door
    bk.roller_shutter(B, ops[0][0], ops[0][1], 2.7, rng.choice(["roller_door", "metal_rust"]), posters_n=0)
    B.rect_z(ops[0][0], ops[0][1], 2.7, 3.0, -0.2, "interior_dark")
    B.box(ops[0][0] - 0.1, ops[0][1] + 0.1, 0.0, 0.3, 0.02, 0.18, "hazard", 0.01)  # bump rail
    if len(ops) > 1:
        a, b = ops[1][0], ops[1][1]
        bk.steel_door(B, a + 0.05, b - 0.05, 2.15, "trim_green", z=-0.12)
        B.lathe([(0.0, 2.35), (0.12, 2.35), (0.14, 2.4), (0.0, 2.42)], (a + b) / 2, 0.2, "metal_dark", segs=12)
        B.tube(((a + b) / 2, 2.4, 0.0), ((a + b) / 2, 2.4, 0.2), 0.015, "metal_dark", segs=6)
        B.lathe([(0.0, 2.28), (0.06, 2.3), (0.0, 2.36)], (a + b) / 2, 0.2, "lamp_bulb", segs=10)
        B.marker("omni_lamp", ((a + b) / 2, 2.2, 0.5))
    # downpipe at one end; painted board for the business name (sign_rect)
    B.tube((W - 0.15, 0.3, 0.12), (W - 0.15, 3.9, 0.12), 0.05, "galvanized", segs=12)
    B.tube((W - 0.15, 0.35, 0.12), (W - 0.15, 0.15, 0.32), 0.05, "galvanized", segs=12)
    B.marker("outlet", (W - 0.15, 0.1, 0.36))
    sx0, sx1 = 0.4, min(W - 0.4, 0.4 + 3.6)
    if W >= 7:
        sx0, sx1 = 0.5, dx0 - 0.3
    B.box(sx0, sx1, 3.12, 3.5, 0.0, 0.05, "sign_board", 0.008)
    B.rect_z(sx0 + 0.01, sx1 - 0.01, 3.13, 3.49, 0.052, "sign_face", uv=(0, 0, 1, 1))
    bk.export(B, mid)
    oreg(mid, "ground", W, bk.GH, "warehouse", ["dark", "corrugated"], sign_rect=[sx0, 3.13, sx1, 3.49, 0.052])


def loading_dock(mid, W):
    """Chain-link fence + gate in front of an open yard and a loading dock (no cover over the yard)."""
    B = Builder(mid)
    rng = B.rng
    zf = -0.15           # fence line
    zb = -4.2            # dock building face
    # yard floor + back building with dock
    B.rect_y(0.0, W, zb, zf, 0.002, "concrete", facing=1)
    B.rect_x(zb, 0.0, 0.0, bk.GH, 0.0, "steel_dark", facing=-1)
    B.rect_x(zb, 0.0, 0.0, bk.GH, W, "steel_dark", facing=1)
    corrugated(B, 0.0, W, 1.25, 4.2, zb, "galvanized")
    B.box(0.0, W, 0.0, 1.2, zb, zb + 1.6, "concrete", 0.03)                     # dock platform
    B.box(0.0, W, 1.15, 1.2, zb + 1.5, zb + 1.62, "hazard", 0.005)
    for dx in (1.2, W - 2.4) if W >= 6 else (1.0,):
        with xf_push(B, T(0, 1.2, zb + 0.12)):
            bk.roller_shutter(B, dx, dx + 2.2, 2.2, "roller_door", zc=0.0, posters_n=0)
        for bx in (dx + 0.15, dx + 2.05):  # rubber dock bumpers
            B.box(bx - 0.1, bx + 0.1, 0.75, 1.15, zb + 1.6, zb + 1.72, "rubber", 0.02)
        B.box(dx - 0.1, dx + 2.3, 3.6, 3.75, zb + 0.1, zb + 0.9, "galvanized", 0.01)   # canopy over door
        B.lathe([(0.0, 3.5), (0.15, 3.5), (0.17, 3.56), (0.0, 3.58)], dx + 1.1, zb + 0.7, "lamp_bulb", segs=12)
        B.marker("omni_lamp", (dx + 1.1, 3.3, zb + 1.2))
    B.box(0.0, W, 4.2, 4.35, zb - 0.3, zb + 0.15, "galvanized", 0.01)
    # pallets and drums in the yard
    for k in range(rng.randint(2, 3)):
        px = rng.uniform(0.8, W - 1.6)
        for j in range(rng.randint(1, 3)):
            y = j * 0.15
            B.box(px, px + 1.2, y, y + 0.13, zb + 1.9, zb + 2.9, "wood_boards", 0.006)
    for k in range(2):
        B.lathe([(0.0, 0.0), (0.29, 0.0), (0.29, 0.88), (0.0, 0.88)], rng.uniform(0.6, W - 0.6), zb + 3.0 + k * 0.3, rng.choice(["paint_blue", "metal_rust"]), segs=20)
    # chain-link fence with posts, top rail, barbed wire, sliding gate
    H = 2.4
    gate0, gate1 = W * 0.35, W * 0.35 + 3.0
    for x in [k * 2.0 for k in range(int(W / 2.0) + 1)] + [gate0, gate1]:
        B.tube((x, 0.0, zf), (x, H + 0.35, zf), 0.035, "galvanized", segs=10)
        sphere(B, (x, H + 0.35, zf), 0.04, "galvanized", 8)
    B.tube((0.0, H, zf), (W, H, zf), 0.022, "galvanized", segs=8)
    B.tube((0.0, 0.08, zf), (W, 0.08, zf), 0.015, "galvanized", segs=6)
    B.rect_z(0.0, W, 0.05, H, zf, "chainlink")
    for k in range(3):
        B.tube((0.0, H + 0.12 + k * 0.1, zf + 0.12), (W, H + 0.12 + k * 0.1, zf + 0.12), 0.004, "galvanized", segs=4)
    x = 0.1
    while x < W:  # barbs
        for k in range(3):
            y = H + 0.12 + k * 0.1
            B.tube((x - 0.03, y - 0.02, zf + 0.1), (x + 0.03, y + 0.02, zf + 0.14), 0.003, "galvanized", segs=3)
        x += 0.25
    for x in (0.0, W):
        B.tube((x, H + 0.35, zf), (x, H + 0.35, zf + 0.2), 0.02, "galvanized", segs=6)
    # gate frame (slightly in front)
    bk.frame_ring(B, gate0, gate1, 0.05, H, zf + 0.04, zf + 0.08, 0.04, "galvanized")
    B.tube((gate0 + 0.04, 0.05, zf + 0.06), (gate1 - 0.04, H, zf + 0.06), 0.015, "galvanized", segs=6)
    B.box((gate0 + gate1) / 2 - 0.15, (gate0 + gate1) / 2 + 0.15, 1.25, 1.65, zf + 0.08, zf + 0.09, "trim_white", 0.004)
    B.box((gate0 + gate1) / 2 - 0.1, (gate0 + gate1) / 2 + 0.1, 1.4, 1.48, zf + 0.09, zf + 0.093, "paint_red", 0.0)
    bk.export(B, mid)
    oreg(mid, "ground", W, bk.GH, "loading_dock", ["dark", "open_sky", "fence"])


def gas_station(mid, W):
    """Corner gas station: small lit kiosk set back, a canopy over the sidewalk on two columns
    near the curb, a pump island. The canopy is real cover (see `cover` in kit.json)."""
    B = Builder(mid)
    rng = B.rng
    kx0, kx1 = 0.4, 4.2           # kiosk
    zk = -0.2
    ops = [(kx0 + 0.25, kx1 - 1.3, 0.55, 2.6), (kx1 - 1.15, kx1 - 0.25, 0.0, 2.3)]
    # kiosk shell
    B.wall(kx0, kx1, 0.0, 3.2, zk, ops, "enamel_cream", depth=0.12)
    B.rect_x(-3.0, zk, 0.0, 3.2, kx0, "enamel_cream", facing=-1)
    B.rect_x(-3.0, zk, 0.0, 3.2, kx1, "enamel_cream", facing=1)
    B.box(kx0 - 0.05, kx1 + 0.05, 3.2, 3.35, zk - 3.0, zk + 0.12, "enamel_coral", 0.02)
    B.box(kx0, kx1, 0.0, 0.55, zk, zk + 0.06, "enamel_coral", 0.01)
    a, b, c, d = ops[0]
    B.rect_z(a, b, c, d, zk - 0.08, "glass_lit")
    bk.frame_ring(B, a, b, c, d, zk - 0.1, zk - 0.02, 0.05, "aluminium")
    bk.interior_box(B, kx0 + 0.02, kx1 - 0.02, 0.0, 3.0, zk - 0.12, -2.8, "interior_newsstand", "interior_cool", "terrazzo", "interior_cool")
    a, b, c, d = ops[1]
    bk.frame_ring(B, a, b, 0.0, d, zk - 0.1, zk - 0.02, 0.05, "aluminium", bottom=False)
    B.rect_z(a + 0.05, b - 0.05, 0.05, d - 0.05, zk - 0.07, "glass_lit")
    B.box(a + 0.08, b - 0.08, 1.0, 1.06, zk - 0.05, zk - 0.02, "aluminium", 0.005)
    B.marker("door", ((a + b) / 2, 0.0, zk - 0.07))
    B.marker("omni_cool", ((kx0 + kx1) / 2, 2.6, -1.2))
    # service bay with roll-up door to the right, bare forecourt beyond
    if W > 6:
        bx0, bx1 = kx1, min(W - 0.3, kx1 + 3.2)
        B.wall(bx0, bx1, 0.0, 3.35, zk, [(bx0 + 0.25, bx1 - 0.25, 0.0, 2.8)], "enamel_cream", depth=0.15)
        B.rect_x(-3.0, zk, 0.0, 3.35, bx1, "enamel_cream", facing=1)
        bk.roller_shutter(B, bx0 + 0.25, bx1 - 0.25, 2.5, "roller_door_blue", zc=zk - 0.1, posters_n=0)
        B.rect_z(bx0 + 0.25, bx1 - 0.25, 2.5, 2.8, zk - 0.15, "interior_dark")
        B.box(bx0, bx1, 3.2, 3.35, zk - 3.0, zk + 0.12, "enamel_coral", 0.02)
    # backdrop wall at the module edge so the lot reads as a corner plot
    B.rect_z(0.0, W, 0.0, 3.0, -3.0, "concrete")
    # canopy: slab y 3.55..3.95 from z -0.2 to 3.3, columns at z = 2.85
    cy0, cy1 = 3.55, 3.95
    cz0, cz1 = -0.2, 3.3
    B.box(0.15, W - 0.15, cy0, cy1, cz0, cz1, "enamel_cream", 0.04)
    B.box(0.12, W - 0.12, cy1 - 0.18, cy1 + 0.02, cz1 - 0.02, cz1 + 0.05, "enamel_coral", 0.02)       # fascia band
    for k in range(int((W - 0.6) / 1.4)):  # recessed light panels in the soffit
        x = 0.5 + k * 1.4
        for z in (0.4, 1.6, 2.6):
            B.box(x, x + 0.9, cy0 - 0.01, cy0 + 0.005, z, z + 0.4, "canopy_light", 0.0)
    B.marker("omni_cool", (W / 2, 3.3, 1.6))
    cols = [1.0, W - 1.0]
    for x in cols:
        B.box(x - 0.12, x + 0.12, 0.0, cy0, 2.73, 2.97, "enamel_coral", 0.03)
        B.box(x - 0.16, x + 0.16, 0.0, 0.35, 2.69, 3.01, "concrete", 0.02)
    # pump island between the columns (near the curb, clear of the walking line z~1.6)
    B.box(1.4, W - 1.4, 0.0, 0.18, 2.55, 3.1, "concrete", 0.03)
    for k, px in enumerate([2.3, W - 2.3] if W >= 6 else [W / 2]):
        pump(B, px, 0.18, 2.82, ["enamel_coral", "enamel_teal"][k % 2])
    # price pole sign behind the canopy at the far end
    bk.export(B, mid)
    cover = [[0.15, cy0, cz0, W - 0.15, cy1, cz1]]
    oreg(mid, "ground", W, bk.GH, "gas_station", ["lit", "cover"], cover=cover,
         sign_rect=[0.3, cy1 - 0.17, W - 0.3, cy1 + 0.01, cz1 + 0.051])


def pump(B, x, y0, z, mat):
    """60s gas pump (front faces +Z), standing at height y0, centred on (x, z)."""
    w, d, h = 0.55, 0.38, 1.55
    B.box(x - w / 2, x + w / 2, y0, y0 + h, z - d / 2, z + d / 2, mat, 0.05)
    B.box(x - w / 2 + 0.04, x + w / 2 - 0.04, y0 + 0.85, y0 + 1.2, z + d / 2, z + d / 2 + 0.01, "trim_white", 0.008)
    for k in range(3):
        B.box(x - 0.18, x + 0.18, y0 + 0.9 + k * 0.1, y0 + 0.96 + k * 0.1, z + d / 2 + 0.01, z + d / 2 + 0.015, "metal_dark", 0.0)
    with xf_push(B, T(x, y0 + h + 0.18, z) @ R("X", 90)):
        B.lathe([(0.0, -0.05), (0.2, -0.05), (0.22, 0.0), (0.2, 0.05), (0.0, 0.05)], 0, 0, "lamp_bulb", segs=24)
    B.tube((x, y0 + h, z), (x, y0 + h + 0.0, z), 0.02, "chrome", segs=6)
    B.box(x + w / 2, x + w / 2 + 0.06, y0 + 0.9, y0 + 1.05, z - 0.04, z + 0.04, "chrome", 0.01)   # nozzle
    pts = [(x + w / 2 + 0.05, y0 + 0.9, z), (x + w / 2 + 0.2, y0 + 0.5, z + 0.05), (x + w / 2 + 0.12, y0 + 0.2, z + 0.1), (x + w / 2, y0 + 0.35, z + 0.15)]
    for a, b in zip(pts[:-1], pts[1:]):
        B.tube(a, b, 0.015, "rubber", segs=6)


def warehouse_side(mid, D, H, cap=False):
    B = Builder(mid)
    B.xf = kitlib.side_xf()
    if cap:
        B.box(0.0, D, 0.0, H, -0.3, 0.1, "galvanized", 0.01)
    else:
        B.wall(0.0, D, 0.0, H, -0.03, [], "steel_dark")
        corrugated(B, 0.0, D, 0.45, H, 0.0, B.rng.choice(["galvanized", "metal_rust"]))
        B.box(0.0, D, 0.0, 0.45, -0.03, 0.08, "concrete", 0.02)
        for x in [k * 2.0 for k in range(1, int(D / 2.0))]:
            B.box(x - 0.04, x + 0.04, 0.45, H, 0.0, 0.03, "galvanized", 0.004)
        B.tube((D - 0.4, 0.3, 0.12), (D - 0.4, H, 0.12), 0.05, "galvanized", segs=12)
    bk.export(B, mid)
    oreg(mid, "side", D, H, None, ["cap" if cap else "ground", "corrugated"])


# ------------------------------------------------------------------------------------------------

def build(buildings_module):
    global bk
    bk = buildings_module
    # ground
    r_kiosk("retro_shop_lit_3a", 3.0, "neon_pink")
    r_shop_lit("retro_shop_lit_4a", 4.0, "arcade", "enamel_black", "neon_violet", door="left")
    r_shop_lit("retro_shop_lit_5a", 5.0, "parts", "enamel_teal", "neon_cyan", door="right")
    r_shop_lit("retro_shop_lit_6a", 6.0, "cafe", "enamel_cream", "neon_green", door="left", vending_niche=True)
    r_shop_lit("retro_shop_lit_8a", 8.0, "noodle", "enamel_coral", "neon_pink", door="center")
    r_shop_lit("retro_shop_lit_6b", 6.0, "arcade", "enamel_mint", "neon_orange", door="right")
    r_shop_dark("retro_shop_dark_4a", 4.0, "enamel_mint")
    r_shop_dark("retro_shop_dark_6a", 6.0, "enamel_cream")
    r_shuttered("retro_shuttered_3a", 3.0, "enamel_black")
    r_shuttered("retro_shuttered_5a", 5.0, "enamel_teal", mat="roller_door_blue", vending_side=True)
    r_shuttered("retro_shuttered_8a", 8.0, "enamel_coral", split=True)
    r_wall("retro_wall_4a", 4.0, "enamel_black", vend=1)
    r_wall("retro_wall_6a", 6.0, "enamel_teal", vend=2, holo=True)
    r_doorway("retro_doorway_3a", 3.0, "enamel_cream", "neon_cyan")
    r_doorway("retro_doorway_4a", 4.0, "enamel_teal", "neon_pink")
    r_inn("retro_inn_6a", 6.0, "neon_orange")
    r_inn("retro_inn_8a", 8.0, "neon_cyan")
    # uppers
    k = 0
    for W in (3.0, 4.0, 5.0, 6.0, 8.0):
        for v in "abcd":
            r_upper("retro_upper_%d%s" % (int(W), v), W, v, NEONS[k % len(NEONS)])
            k += 1
    # caps
    for i, W in enumerate((3.0, 4.0, 5.0, 6.0, 8.0)):
        r_cap("retro_cap_band_%d" % int(W), W, "band", NEONS[i % len(NEONS)])
        r_cap("retro_cap_dish_%d" % int(W), W, "dish", NEONS[i % len(NEONS)])
        r_cap("retro_cap_neon_%d" % int(W), W, "neon", NEONS[(i + 3) % len(NEONS)])
    # sides (ids contain ground/upper/cap like the 60s ones)
    r_side("side_ground_retro_10", 10.0, bk.GH, "ground")
    r_side("side_upper_retro_10", 10.0, bk.UH, "upper")
    r_side("side_cap_retro_10", 10.0, 0.5, "cap")
    # outskirts / industrial
    warehouse("warehouse_6a", 6.0, "galvanized")
    warehouse("warehouse_8a", 8.0, "metal_rust")
    loading_dock("loading_dock_8a", 8.0)
    gas_station("gas_station_8a", 8.0)
    warehouse_side("side_ground_warehouse_10", 10.0, bk.GH)
    warehouse_side("side_cap_warehouse_10", 10.0, 0.3, cap=True)
