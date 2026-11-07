"""Retro-future / rundown_neon props and retro cars (called from props.py).

Decorations for the 60s kit (rundown_neon): neon blade signs, tangled overhead cables, a projecting
LED ticker; neon street furniture (vending machines); outskirts bits (chain-link section, gas
pump); and three hover-ish 60s-futurist sedans `car_retro_*` (facing +X, origin ground centre).
"""
import math

import kitlib
from kitlib import Builder, R, T, xf_push
import retro
from retro import neon_path, neon_rect, sphere

pm = None  # props module


def reg(pid, place, fp, tags, era="retro", **extra):
    pm.register(pid, place, fp, tags, era=era, **extra)


# ------------------------------------------------------------------------------------------------
# rundown_neon decorations
# ------------------------------------------------------------------------------------------------

def neon_blade(pid, neon, neon2, h=2.2, w=0.7):
    """Vertical sign standing 0.35 m off the wall on brackets; face toward +Z with a 0..1-UV
    sign_face_dark quad (for code text) framed by a neon outline. Origin = wall point at its base."""
    B = Builder(pid)
    z0 = 0.3
    B.box(-w / 2, w / 2, 0.0, h, z0 - 0.06, z0 + 0.06, "enamel_black", 0.03)
    B.rect_z(-w / 2 + 0.06, w / 2 - 0.06, 0.12, h - 0.12, z0 + 0.061, "sign_face_dark", uv=(0, 0, 1, 1))
    neon_rect(B, -w / 2 + 0.03, w / 2 - 0.03, 0.03, h - 0.03, z0 + 0.09, neon, rad=0.12, wall_z=z0 + 0.06)
    # chevrons down the edge strip
    for k in range(int(h / 0.35)):
        y = 0.25 + k * 0.35
        neon_path(B, [(-w / 2 - 0.1, y + 0.1, z0), (-w / 2 - 0.02, y, z0), (-w / 2 - 0.1, y - 0.1, z0)], neon2, clips=False)
    for y in (0.25, h - 0.25):  # wall brackets
        B.box(-0.05, 0.05, y - 0.03, y + 0.03, 0.0, z0 - 0.05, "steel_dark", 0.008)
        B.box(-0.12, 0.12, y - 0.1, y + 0.1, 0.0, 0.02, "steel_dark", 0.008)
    B.tube((w / 2 - 0.1, 0.0, z0 - 0.05), (w / 2 - 0.1, -0.6, 0.02), 0.01, "rubber", segs=5)  # feed cable
    B.marker("omni_" + neon, (0.0, h / 2, z0 + 0.6))
    pm.export(B, pid)
    reg(pid, "wall_high", (w + 0.2, 0.5), ["neon", "sign", "rundown_neon"], height=h, mount_y=4.2,
        sign_rect=[-w / 2 + 0.06, 0.12, w / 2 - 0.06, h - 0.12, z0 + 0.061])


def neon_googie(pid, neon):
    """Googie disc + arrow with chaser bulbs (blank face for code text)."""
    B = Builder(pid)
    z0 = 0.35
    r = 0.55
    with xf_push(B, T(0, 1.6, z0) @ R("X", 90)):
        B.lathe([(0.0, -0.07), (r, -0.07), (r + 0.03, 0.0), (r, 0.07), (0.0, 0.07)], 0, 0, "enamel_coral", segs=32)
    for k in range(20):
        a = 2 * math.pi * k / 20
        sphere(B, (r * 0.9 * math.cos(a), 1.6 + r * 0.9 * math.sin(a), z0 + 0.08), 0.03, "lamp_bulb", 6)
    B.rect_z(-0.38, 0.38, 1.4, 1.8, z0 + 0.072, "sign_face_dark", uv=(0, 0, 1, 1))
    # arrow below pointing down-left at the door
    pts = [(0.5, 1.0, z0), (0.5, 0.3, z0), (-0.3, 0.3, z0)]
    B.prism_z([(0.42, 1.0), (0.58, 1.0), (0.58, 0.38), (-0.2, 0.38), (-0.2, 0.22), (0.42, 0.22)][::-1], z0 - 0.05, z0 + 0.05, "enamel_black", bevel=0.01)
    B.prism_z([(-0.2, 0.1), (-0.2, 0.5), (-0.45, 0.3)], z0 - 0.05, z0 + 0.05, "enamel_black", bevel=0.01)
    neon_path(B, [(p[0], p[1], z0 + 0.07) for p in pts], neon, wall_z=z0 + 0.05)
    neon_path(B, [(-0.18, 0.47, z0 + 0.07), (-0.42, 0.3, z0 + 0.07), (-0.18, 0.13, z0 + 0.07)], neon, wall_z=z0 + 0.05)
    for y in (0.3, 1.6):
        B.box(-0.04, 0.04, y - 0.03, y + 0.03, 0.0, z0 - 0.05, "steel_dark", 0.006)
    B.marker("omni_" + neon, (0.0, 1.2, z0 + 0.7))
    pm.export(B, pid)
    reg(pid, "wall_high", (1.3, 0.5), ["neon", "sign", "googie", "rundown_neon"], height=2.2, mount_y=3.95,
        sign_rect=[-0.38, 1.4, 0.38, 1.8, z0 + 0.072])


def overhead_cables(pid, span, seed):
    """Tangled cables hanging along the facade between two anchors (origin = left anchor on the
    wall). Hangs below y = 0 (sag), drifts out to z ~ 0.9."""
    B = Builder(pid, seed=seed)
    rng = B.rng
    n = 7
    for k in range(n):
        y0 = rng.uniform(-0.15, 0.15)
        y1 = rng.uniform(-0.25, 0.25)
        sag = rng.uniform(0.35, 1.2)
        zmid = rng.uniform(0.25, 0.9)
        r = rng.choice([0.008, 0.012, 0.018])
        pts = []
        for i in range(17):
            t = i / 16
            pts.append((span * t, y0 + (y1 - y0) * t - sag * 4 * t * (1 - t), 0.05 + zmid * 4 * t * (1 - t) + 0.02 * k * (1 - abs(2 * t - 1))))
        for a, b in zip(pts[:-1], pts[1:]):
            B.tube(a, b, r, "rubber", segs=5, caps=False)
        if k == 2:  # a coiled loop of slack
            cx = span * rng.uniform(0.3, 0.7)
            t = cx / span
            cy = y0 + (y1 - y0) * t - sag * 4 * t * (1 - t)
            cz = 0.05 + zmid * 4 * t * (1 - t)
            prev = None
            for i in range(37):
                a = 2 * math.pi * i / 12
                p = (cx + 0.12 * math.cos(a), cy - 0.12 - 0.12 * math.sin(a) - i * 0.004, cz + 0.02 * math.sin(a * 0.5))
                if prev:
                    B.tube(prev, p, 0.01, "rubber", segs=5, caps=False)
                prev = p
    # anchors / insulators and a junction box with a drop wire
    for x in (0.0, span):
        B.box(x - 0.06, x + 0.06, -0.12, 0.12, 0.0, 0.06, "steel_dark", 0.01)
        for k in range(3):
            B.lathe([(0.0, -0.05), (0.03, -0.04), (0.03, 0.04), (0.0, 0.05)], x - 0.04 + k * 0.04, 0.08, "plastic_beige", segs=8)
    jx = span * 0.5
    B.box(jx - 0.2, jx + 0.2, -0.9, -0.5, 0.0, 0.18, "galvanized", 0.02)
    B.tube((jx, -0.5, 0.09), (jx + 0.3, 0.0, 0.3), 0.012, "rubber", segs=5)
    B.tube((jx, -0.9, 0.09), (jx, -2.4, 0.05), 0.012, "rubber", segs=5)
    pm.export(B, pid)
    reg(pid, "wall_high", (span, 1.0), ["cables", "rundown_neon", "span"], era="60s", span=span, mount_y=6.6, height=1.3)


def led_ticker(pid, length=2.6):
    """Projecting LED ticker (scrolling led_ticker shader) on two brackets, parallel to the facade."""
    B = Builder(pid)
    h, d = 0.36, 0.16
    z0 = 0.45
    B.box(-length / 2, length / 2, 0.0, h, z0 - d / 2, z0 + d / 2, "enamel_black", 0.03)
    B.rect_z(-length / 2 + 0.05, length / 2 - 0.05, 0.05, h - 0.05, z0 + d / 2 + 0.002, "led_ticker", uv=(0, 0, 1, 1))
    B.box(-length / 2 - 0.02, length / 2 + 0.02, h - 0.02, h + 0.02, z0 - d / 2 - 0.01, z0 + d / 2 + 0.02, "chrome", 0.01)
    B.box(-length / 2 - 0.02, length / 2 + 0.02, -0.02, 0.02, z0 - d / 2 - 0.01, z0 + d / 2 + 0.02, "chrome", 0.01)
    for x in (-length / 2 + 0.3, length / 2 - 0.3):
        B.box(x - 0.03, x + 0.03, h * 0.3, h * 0.7, 0.0, z0 - d / 2, "steel_dark", 0.008)
        B.tube((x, h, z0 - d / 2), (x, h + 0.5, 0.0), 0.012, "steel_dark", segs=6)
    B.tube((length / 2 - 0.2, 0.0, z0 - 0.05), (length / 2 - 0.1, -0.5, 0.02), 0.01, "rubber", segs=5)
    B.marker("omni_neon_orange", (0.0, h / 2, z0 + 0.6))
    pm.export(B, pid)
    reg(pid, "wall_high", (length, 0.6), ["led", "rundown_neon", "neon"], height=h, mount_y=4.15)


def vending_machine(pid, variant):
    B = Builder(pid)
    retro.vending(B, 0.0, -0.35, variant=variant)
    pm.export(B, pid)
    reg(pid, "wall", (0.95, 0.75), ["vending", "light"], height=1.88)


def chainlink_fence(pid, L=4.0):
    B = Builder(pid)
    H = 2.2
    for x in (-L / 2, 0.0, L / 2):
        B.tube((x, 0.0, 0.0), (x, H + 0.1, 0.0), 0.035, "galvanized", segs=10)
        sphere(B, (x, H + 0.1, 0.0), 0.04, "galvanized", 8)
    B.tube((-L / 2, H, 0.0), (L / 2, H, 0.0), 0.022, "galvanized", segs=8)
    B.tube((-L / 2, 0.1, 0.0), (L / 2, 0.1, 0.0), 0.015, "galvanized", segs=6)
    B.rect_z(-L / 2, L / 2, 0.06, H, 0.0, "chainlink")
    pm.export(B, pid)
    reg(pid, "sidewalk", (L, 0.2), ["fence", "outskirts"], era="60s", height=H + 0.14)


def gas_pump(pid):
    B = Builder(pid)
    B.box(-0.5, 0.5, 0.0, 0.18, -0.3, 0.3, "concrete", 0.03)
    retro.pump(B, 0.0, 0.18, 0.0, "enamel_coral")
    pm.export(B, pid)
    reg(pid, "curb", (1.0, 0.6), ["outskirts", "light"], era="60s", height=2.0)


# ------------------------------------------------------------------------------------------------
# retro cars
# ------------------------------------------------------------------------------------------------

def loft(B, stations, mat, n=28, p=2.6):
    """stations: [(x, half_width, y_bottom, y_top), ...] rear -> front. Super-ellipse rings."""
    rings = []
    for (x, hw, yb, yt) in stations:
        yc, hh = (yb + yt) / 2, (yt - yb) / 2
        ring = []
        for i in range(n):
            t = 2 * math.pi * i / n
            c, s = math.cos(t), math.sin(t)
            z = hw * math.copysign(abs(c) ** (2 / p), c)
            y = yc + hh * math.copysign(abs(s) ** (2 / p), s)
            ring.append(B.v((x, y, z)))
        rings.append(ring)
    faces = []
    for A, Bb in zip(rings[:-1], rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            faces.append(B.face([A[i], A[j], Bb[j], Bb[i]], mat, smooth=True))
    # end caps: fan to centre points
    for ring, (x, hw, yb, yt), rev in ((rings[0], stations[0], True), (rings[-1], stations[-1], False)):
        c = B.v((x + (-0.02 if rev else 0.02), (yb + yt) / 2, 0.0))
        for i in range(n):
            j = (i + 1) % n
            vs = [ring[i], ring[j], c]
            faces.append(B.face(vs[::-1] if not rev else vs, mat, smooth=True))
    cen = (sum(s[0] for s in stations) / len(stations), (stations[0][2] + stations[0][3]) / 2, 0.0)
    B._orient_outward(faces, cen)
    B.mark_sharp(faces, 70)
    return faces


def body_hw(stations, x):
    for (a, b) in zip(stations[:-1], stations[1:]):
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return [a[i] + (b[i] - a[i]) * t for i in range(4)]
    return list(stations[-1] if x > stations[-1][0] else stations[0])


def car_retro(pid, paint, accent, strip, style):
    B = Builder(pid)
    S = [(-2.8, 0.5, 0.62, 0.98), (-2.65, 0.82, 0.48, 1.03), (-2.2, 0.95, 0.42, 1.04), (-1.0, 1.0, 0.4, 1.0),
         (0.5, 1.0, 0.4, 0.96), (1.7, 0.96, 0.42, 0.9), (2.35, 0.84, 0.45, 0.82), (2.7, 0.5, 0.5, 0.72)]
    if style == "b":  # rounder, shorter, raised tail
        S = [(-2.55, 0.45, 0.6, 1.02), (-2.35, 0.85, 0.46, 1.08), (-1.6, 0.98, 0.4, 1.06), (0.2, 1.0, 0.4, 0.98),
             (1.5, 0.95, 0.43, 0.9), (2.25, 0.8, 0.47, 0.8), (2.55, 0.42, 0.52, 0.7)]
    if style == "c":  # long and low
        S = [(-2.95, 0.55, 0.55, 0.9), (-2.75, 0.85, 0.42, 0.94), (-2.2, 0.98, 0.36, 0.95), (-0.8, 1.02, 0.34, 0.92),
             (0.8, 1.02, 0.34, 0.88), (2.0, 0.96, 0.36, 0.82), (2.6, 0.82, 0.4, 0.74), (2.9, 0.45, 0.46, 0.66)]
    loft(B, S, paint, n=32, p=2.8)
    x_rear, x_front = S[0][0], S[-1][0]
    # bubble canopy (glass) with chrome base ring
    cab = [(-1.55, 0.35, 0.82, 1.05), (-1.2, 0.62, 0.8, 1.3), (-0.4, 0.74, 0.8, 1.45), (0.35, 0.72, 0.8, 1.42),
           (0.9, 0.55, 0.8, 1.24), (1.2, 0.25, 0.85, 1.02)]
    if style == "b":
        cab = [(c[0] - 0.2, c[1], c[2], c[3] + 0.05) for c in cab]
    loft(B, cab, "glass_car", n=28, p=2.2)
    pts = []
    for k in range(25):  # chrome ring hugging the canopy base
        t = k / 24
        x = cab[0][0] + (cab[-1][0] - cab[0][0]) * t
        hw = body_hw(cab, x)[1]
        pts.append((x, 0.98, hw * 0.98))
    pts2 = [(p[0], p[1], -p[2]) for p in pts]
    for P in (pts, pts2):
        for a, b in zip(P[:-1], P[1:]):
            B.tube(a, b, 0.018, "chrome", segs=6, caps=False)
    # seats / pilot silhouettes inside the bubble
    B.box(-0.6, -0.3, 0.85, 1.3, -0.5, 0.5, "car_interior", 0.06)
    B.box(0.2, 0.45, 0.85, 1.05, -0.55, 0.55, "car_interior", 0.04)
    # light strips (recolourable neon) along the flanks + front headlight bar + tail lights
    for side in (-1, 1):
        P = []
        for k in range(21):
            x = x_rear + 0.25 + (x_front - x_rear - 0.45) * k / 20
            st = body_hw(S, x)
            P.append((x, 0.62, side * (st[1] + 0.012)))
        for a, b in zip(P[:-1], P[1:]):
            B.tube(a, b, 0.014, strip, segs=6, caps=False)
        sphere(B, P[0], 0.016, strip, 6)
        sphere(B, P[-1], 0.016, strip, 6)
        # chrome spear above the strip
        Q = [(p[0], 0.7, p[2] + side * 0.004) for p in P[2:-2]]
        for a, b in zip(Q[:-1], Q[1:]):
            B.tube(a, b, 0.01, "chrome", segs=5, caps=False)
    fx = x_front - 0.08
    B.box(fx - 0.1, fx + 0.04, 0.58, 0.64, -0.38, 0.38, "headlight", 0.02)
    with xf_push(B, T(x_front + 0.02, 0.6, 0.0) @ R("Z", -90)):  # chrome jet-intake nose ring
        B.lathe([(0.12, -0.04), (0.2, -0.02), (0.22, 0.03), (0.18, 0.06), (0.12, 0.04)], 0, 0, "chrome", segs=24)
        B.lathe([(0.0, 0.0), (0.12, 0.0), (0.12, 0.01), (0.0, 0.02)], 0, 0, accent, segs=16)
    # fins
    if style in ("a", "c"):
        for side in (-1, 1):
            z = side * (0.72 if style == "a" else 0.8)
            top = 1.55 if style == "a" else 1.38
            prof = [(x_rear + 0.05, 0.85), (x_rear + 1.6, 0.98), (x_rear + 0.55, top), (x_rear - 0.15, top + 0.02)]
            B.prism_z(prof, z - 0.035, z + 0.035, paint, bevel=0.015)
            # neon along the fin's leading edge + round tail light
            neon_path(B, [(x_rear + 1.55, 0.99, z), (x_rear + 0.55, top - 0.02, z)], strip, clips=False, r=0.012)
            with xf_push(B, T(x_rear - 0.13, top - 0.08, z) @ R("Z", 90)):
                B.lathe([(0.0, 0.0), (0.06, 0.0), (0.06, 0.06), (0.0, 0.07)], 0, 0, "tail_light", segs=16)
    if style == "b":  # dorsal fin + side pods
        prof = [(x_rear + 0.1, 1.0), (x_rear + 1.5, 1.04), (x_rear + 0.35, 1.62), (x_rear - 0.05, 1.62)]
        B.prism_z(prof, -0.035, 0.035, accent, bevel=0.015)
        neon_path(B, [(x_rear + 1.45, 1.05, 0.0), (x_rear + 0.35, 1.6, 0.0)], strip, clips=False, r=0.012)
        for side in (-1, 1):
            pod = [(x_rear - 0.1, 0.16, 0.5, 0.72), (x_rear + 0.4, 0.2, 0.48, 0.74), (x_rear + 1.6, 0.16, 0.5, 0.72), (x_rear + 2.0, 0.08, 0.55, 0.66)]
            with xf_push(B, T(0, 0, side * 1.0)):
                loft(B, pod, accent, n=16, p=2.0)
            with xf_push(B, T(x_rear - 0.1, 0.61, side * 1.0) @ R("Z", 90)):
                B.lathe([(0.0, 0.0), (0.09, 0.0), (0.09, 0.03), (0.0, 0.04)], 0, 0, "tail_light", segs=14)
    if style == "c":  # jet nacelle at the tail
        with xf_push(B, T(x_rear - 0.05, 0.75, 0.0) @ R("Z", 90)):
            B.lathe([(0.0, -0.3), (0.2, -0.3), (0.24, -0.1), (0.22, 0.12), (0.17, 0.16), (0.0, 0.17)], 0, 0, "chrome", segs=24)
            B.lathe([(0.0, 0.14), (0.15, 0.14), (0.15, 0.16), (0.0, 0.17)], 0, 0, "fire_glow", segs=20)
    # hover pads (glow) instead of wheels, skirt fairings
    for x in (x_rear + 0.9, x_front - 0.9):
        for side in (-1, 1):
            cz = side * 0.62
            B.lathe([(0.0, 0.3), (0.32, 0.3), (0.36, 0.36), (0.3, 0.42), (0.0, 0.42)], x, cz, "steel_dark", segs=24)
            B.lathe([(0.0, 0.29), (0.26, 0.29), (0.26, 0.3), (0.0, 0.305)], x, cz, "hover_glow", segs=24)
            B.marker("omni_hover", (x, 0.12, cz))
    B.rect_y(x_rear + 0.2, x_front - 0.2, -0.85, 0.85, 0.005, "metal_dark", facing=1)
    pm.export(B, pid)
    reg(pid, "road", (x_front - x_rear + 0.3, 2.1), ["car", "retro", "hover", "foreground"], height=1.6,
        length=round(x_front - x_rear + 0.3, 2))


def build(props_module):
    global pm
    pm = props_module
    neon_blade("neon_blade_a", "neon_pink", "neon_cyan")
    neon_blade("neon_blade_b", "neon_cyan", "neon_orange", h=2.8, w=0.6)
    neon_googie("neon_googie", "neon_orange")
    overhead_cables("overhead_cables_6", 6.0, 11)
    overhead_cables("overhead_cables_10", 10.0, 12)
    led_ticker("led_ticker")
    vending_machine("vending_machine_a", 0)
    vending_machine("vending_machine_b", 1)
    chainlink_fence("chainlink_fence_4")
    gas_pump("gas_pump")
    car_retro("car_retro_a", "car_paint_pearl", "car_paint_turq", "neon_cyan", "a")
    car_retro("car_retro_b", "car_paint_coral", "car_paint_pearl", "neon_pink", "b")
    car_retro("car_retro_c", "car_paint_black", "car_paint_coral", "neon_orange", "c")
