"""Generate the vehicles that are not street props (docs/CONTRACTS.md §9).

    blender -b --factory-startup --python tools/blender/vehicles.py [-- --preview DIR]

Writes assets/vehicles/helicopter.glb: Skyway's airport shuttle, an invented 1960s twin-turbine
city helicopter. A boat hull with a planing step and chine strakes, a glazed bubble nose with the
crew inside, a row of lit cabin windows over a teal cheatline, SKYWAY in capitals low on both flanks
(where the street sees it, from below), sponsons carrying the main wheels, the turbines in a housing
on the roof, a tail boom swept up to a fin, five blades over the hub and a five-blade tail rotor.

Game coordinates, as everywhere in the kit: +X the nose, +Y up, 1 unit a metre. The origin is the
main rotor hub. The objects the game looks for sit directly under the scene root:
    Rotor              hub and blades, turned about Y (child RotorBlur: the smear behind each blade)
    TailRotor          origin at its hub, disc in its local XY plane (child TailBlur)
    SearchlightMount   the lamp under the chin; the beam starts at its origin
    BeaconTop, BeaconBelly   the anti-collision lights' lenses
    Flash, CockpitGlow, BellyLight   empties that assets/vehicles/vehicle_import.gd turns into lights
Materials are names from materials_def.py, swapped for the shared .tres files at import.
`--preview DIR` also renders a few Workbench views of it into DIR, for a look without the game.
"""
import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kitlib  # noqa: E402
from kitlib import Builder, ROOT, R, T, gv, xf_push  # noqa: E402

OUT = os.path.join(ROOT, "assets", "vehicles")
FONT = os.path.join(ROOT, "assets", "fonts", "BebasNeue-Regular.ttf")

WHITE, TEAL, NAVY, ALU = "heli_white", "enamel_teal", "heli_navy", "aluminium"
GLASS, DARK, CHROME = "heli_glass", "metal_dark", "chrome"
ROTOR_R = 4.0
CONE = math.radians(2.5)      # the blades cone up a little under load


def pchip(xs, ys):
    """A monotone cubic through (xs, ys), xs ascending: no overshoot between keys."""
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        x = min(max(x, xs[0]), xs[-1])
        i = 0
        while i < n - 2 and x > xs[i + 1]:
            i += 1
        t = (x - xs[i]) / h[i]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])
    return f


class Hull:
    """A body lofted along X through superellipse sections. Keys are (x, cy, hw, ht, hb, nt, nb):
    the widest line's height, the half width, the height above and depth below that line, and the
    exponents of the upper and lower halves (2 an ellipse, more a rounded box, less a V)."""

    def __init__(self, keys):
        keys = sorted(keys)
        xs = [k[0] for k in keys]
        self.x0, self.x1 = xs[0], xs[-1]
        self.f = [pchip(xs, [k[i] for k in keys]) for i in range(1, 7)]

    def at(self, x):
        return tuple(f(x) for f in self.f)

    def point(self, x, v, side=1.0):
        """The surface at station x, v from -1 (keel) through 0 (widest) to 1 (roof centre)."""
        cy, hw, ht, hb, nt, nb = self.at(x)
        n = nt if v >= 0 else nb
        z = hw * max(0.0, 1.0 - abs(v) ** n) ** (1.0 / n)
        return (x, cy + v * (ht if v >= 0 else hb), side * z)

    def surface(self, x, y, side=1.0, lift=0.0):
        """The point of the flank at (x, y), pushed `lift` outward: decals are laid with this."""
        cy, hw, ht, hb, nt, nb = self.at(x)
        v = (y - cy) / (ht if y >= cy else hb)
        n = nt if v >= 0 else nb
        z = hw * max(0.0, 1.0 - min(abs(v), 1.0) ** n) ** (1.0 / n)
        return (x, y, side * (z + lift))

    def loft(self, B, xs, V, mat_of, inward=0.0, flip=False, caps=(None, None)):
        """Skin stations xs (ascending) at rows V (-1..1). mat_of(x, v, side) names each face's
        material (None leaves it out). `inward` shrinks the shell (a liner); `flip` turns it inside
        out. caps: a material for the pole closing the first and last station."""
        vring = list(V) + list(reversed(V[1:-1]))
        sides = [1.0] * len(V) + [-1.0] * (len(V) - 2)
        rings = []
        for x in xs:
            ring = []
            for v, s in zip(vring, sides):
                p = self.point(x, v, s)
                if inward:
                    cy = self.at(x)[0]
                    r = math.hypot(p[1] - cy, p[2])
                    k = max(0.0, 1.0 - inward / max(r, 1e-4))
                    p = (x, cy + (p[1] - cy) * k, p[2] * k)
                ring.append(B.v(p))
            rings.append(ring)
        n = len(vring)
        faces = []
        for i in range(len(xs) - 1):
            xm = 0.5 * (xs[i] + xs[i + 1])
            for j in range(n):
                k = (j + 1) % n
                vm = 0.5 * (vring[j] + vring[k])
                side = 1.0 if j < len(V) - 1 else -1.0
                mat = mat_of(xm, vm, side)
                if mat is None:
                    continue
                vs = [rings[i][j], rings[i + 1][j], rings[i + 1][k], rings[i][k]]
                faces.append(B.face(list(reversed(vs)) if flip else vs, mat, smooth=True))
        for (ring, x, mat, front) in ((rings[0], xs[0], caps[0], False), (rings[-1], xs[-1], caps[1], True)):
            if mat is None:
                continue
            cy = self.at(x)[0]
            c = B.v((x + (0.04 if front else -0.04), cy, 0.0))
            for j in range(n):
                k = (j + 1) % n
                vs = [ring[j], ring[k], c] if front else [ring[k], ring[j], c]
                faces.append(B.face(list(reversed(vs)) if flip else vs, mat, smooth=True))
        B.mark_sharp(faces, 38.0)
        return faces

    def rail(self, B, v, x0, x1, r, mat, side=1.0, step=0.12, lift=0.0):
        """A thin tube along row v from x0 to x1 (strakes, glazing bars)."""
        n = max(1, int(abs(x1 - x0) / step))
        pts = [self.point(x0 + (x1 - x0) * i / n, v, side) for i in range(n + 1)]
        for a, b in zip(pts, pts[1:]):
            B.tube((a[0], a[1], a[2] + side * lift), (b[0], b[1], b[2] + side * lift), r, mat, segs=6, caps=False)

    def hoop(self, B, x, v0, v1, r, mat, steps=14):
        """A tube round station x from row v0 to v1, on both sides (a glazing frame)."""
        for side in (1.0, -1.0):
            pts = [self.point(x, v0 + (v1 - v0) * i / steps, side) for i in range(steps + 1)]
            for a, b in zip(pts, pts[1:]):
                B.tube(a, b, r, mat, segs=6, caps=False)


def ball(B, c, r, mat, segs=12, rings=8, sy=1.0):
    prof = [(r * math.sin(math.pi * i / rings), c[1] - r * sy * math.cos(math.pi * i / rings)) for i in range(rings + 1)]
    prof[0] = (0.0, prof[0][1])
    prof[-1] = (0.0, prof[-1][1])
    B.lathe(prof, c[0], c[2], mat, segs=segs)


def wheel(B, x, y, z, r, w=0.16):
    B.tube((x, y, z - w / 2), (x, y, z + w / 2), r, "rubber", segs=20, bevel=min(0.05, r * 0.25))
    B.tube((x, y, z - w / 2 - 0.012), (x, y, z + w / 2 + 0.012), r * 0.45, CHROME, segs=14, bevel=0.01)


def decal(B, hull, bm, ox, oy, side, mat, lift, strip=0.09):
    """Lay a flat shape (a bmesh in its XY plane, metres) on the hull's flank with its origin at
    (ox, oy), reading left to right from outside on either side. Cut into strips so it follows the
    curve of the flank."""
    ys = [v.co.y for v in bm.verts]
    y = min(ys) + strip
    while y < max(ys):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, y, 0), plane_no=(0, 1, 0))
        y += strip
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    faces = []
    for f in bm.faces:
        pts = [hull.surface(ox + side * v.co.x, oy + v.co.y, side, lift) for v in f.verts]
        faces.append(B.face([B.v(p) for p in pts], mat))
    B._orient_outward(faces, (ox, oy, 0.0))
    bm.free()


def text_shape(text, cap, tracking=1.1, shear=0.22):
    """`text` as a flat mesh, its capitals `cap` tall, centred on x, baseline at y 0."""
    cu = bpy.data.curves.new("title", "FONT")
    cu.body = text
    cu.font = bpy.data.fonts.load(FONT)
    cu.align_x = "CENTER"
    cu.space_character = tracking
    cu.shear = shear
    ob = bpy.data.objects.new("title", cu)
    bpy.context.scene.collection.objects.link(ob)
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)
    ys = [v.co.y for v in bm.verts]
    s = cap / (max(ys) - min(ys))
    y0 = min(ys)
    for v in bm.verts:
        v.co.x, v.co.y = v.co.x * s, (v.co.y - y0) * s
    return bm


def rounded_rect(w, h, r, n=5):
    """A w x h rectangle with rounded corners, centred, as a one-face bmesh."""
    pts = []
    for (cx, cy, a0) in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    bm = bmesh.new()
    bm.faces.new([bm.verts.new((x, y, 0.0)) for (x, y) in pts])
    return bm


def rect(w, h):
    bm = bmesh.new()
    bm.faces.new([bm.verts.new((x, y, 0.0)) for (x, y) in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2))])
    return bm


# ------------------------------------------------------------------------------------------------
# the Skyway shuttle
# ------------------------------------------------------------------------------------------------

NOSE_X, NOSE_LEN = 2.3, 1.2          # the bubble: an ellipsoid from the cockpit's rear frame to the tip
GLASS_X, QUARTER_X = 2.25, 1.72      # glazed ahead of GLASS_X; quarter-lights back to QUARTER_X
BELT = -1.97                         # the hull's widest line, where the cheatline runs
ROWS = [-1.0, -0.97, -0.9, -0.8, -0.68, -0.56, -0.45, -0.3, -0.17, -0.06, 0.0, 0.12, 0.22, 0.34, 0.47,
        0.6, 0.72, 0.82, 0.9, 0.955, 0.985, 1.0]
CHINE = -0.45                        # the row where the planing bottom meets the flank


def fuselage():
    keys = []
    for k in range(11):              # the bubble nose
        a = math.radians(88.0) * k / 10.0
        s = math.cos(a)
        keys.append((NOSE_X + NOSE_LEN * math.sin(a), -2.0 - 0.1 * math.sin(a) ** 2, 1.03 * s, 1.08 * s, 0.84 * s, 2.0, 1.9))
    keys += [
        (1.8, BELT, 1.05, 1.12, 0.93, 2.5, 1.6),
        (1.2, BELT, 1.06, 1.12, 0.98, 2.6, 1.5),
        (0.0, BELT, 1.06, 1.12, 1.00, 2.6, 1.5),
        (-0.80, BELT, 1.06, 1.12, 1.00, 2.6, 1.5),
        (-0.84, BELT, 1.06, 1.12, 0.87, 2.6, 1.5),     # the planing step
        (-2.0, BELT, 1.04, 1.12, 0.78, 2.6, 1.5),
        (-3.0, -1.93, 0.92, 1.06, 0.55, 2.4, 1.6),
        (-3.8, -1.74, 0.66, 0.84, 0.38, 2.2, 1.8),     # the cabin closes into the boom
        (-4.6, -1.50, 0.44, 0.57, 0.36, 2.0, 2.0),
        (-5.6, -1.36, 0.33, 0.42, 0.32, 2.0, 2.0),
        (-6.6, -1.24, 0.25, 0.32, 0.27, 2.0, 2.0),
        (-7.3, -1.14, 0.19, 0.25, 0.22, 2.0, 2.0),
        (-7.7, -1.08, 0.11, 0.15, 0.13, 2.0, 2.0),
    ]
    return Hull(keys)


def hull_mat(x, v, side):
    if x > GLASS_X and -0.3 < v < 0.955:
        return GLASS
    if QUARTER_X < x <= GLASS_X and 0.22 < v < 0.82:
        return GLASS
    if x > GLASS_X and v >= 0.955:
        return ALU                    # the glazing's centre post
    if v < CHINE:
        return ALU                    # the planing bottom, left in polished metal
    if -0.06 < v < 0.0:
        return NAVY
    if 0.0 <= v < 0.12:
        return TEAL
    return WHITE


def stations(h, extra=()):
    xs = {round(k, 3) for k in extra}
    x = h.x0
    while x < h.x1:
        xs.add(round(x, 3))
        x += 0.2
    xs.add(round(h.x1, 3))
    return sorted(xs)


def body():
    B = Builder("Body")
    h = fuselage()
    nose = [NOSE_X + NOSE_LEN * math.sin(math.radians(88.0) * k / 10.0) for k in range(11)]
    xs = stations(h, nose + [GLASS_X, QUARTER_X, 1.2, -0.80, -0.84, 0.0])
    h.loft(B, xs, ROWS, hull_mat, caps=(WHITE, GLASS))
    # Behind the glass: a dark liner (the hull's own faces are one-sided), a bulkhead, the crew.
    liner = [x for x in xs if x >= QUARTER_X - 0.001]
    h.loft(B, liner, ROWS, lambda x, v, s: None if hull_mat(x, v, s) == GLASS else "car_interior",
           inward=0.03, flip=True, caps=("car_interior", None))
    B.box(2.92, 3.02, -2.3, -1.78, -0.62, 0.62, DARK, 0.03)                    # instrument coaming
    B.box(2.9, 2.921, -2.2, -1.86, -0.55, 0.55, "panel_glow")
    for z in (-0.4, 0.4):
        B.box(2.18, 2.3, -2.35, -1.42, z - 0.24, z + 0.24, "car_interior", 0.04)   # seat back
        B.box(2.32, 2.56, -2.2, -1.68, z - 0.2, z + 0.2, NAVY, 0.07)              # the pilot
        ball(B, (2.46, -1.52, z), 0.115, "plastic_beige")
        B.lathe([(0.0, -1.47), (0.125, -1.47), (0.12, -1.42), (0.07, -1.385), (0.0, -1.38)], 2.46, z, "trim_white", segs=12)
        B.box(2.5, 2.64, -1.475, -1.46, z - 0.1, z + 0.1, DARK)                   # cap peak
    # Glazing bars.
    bar = 0.022
    h.hoop(B, GLASS_X, -0.3, 0.955, bar * 1.3, ALU)
    h.hoop(B, 2.86, -0.3, 0.955, bar, ALU)
    h.hoop(B, QUARTER_X, 0.22, 0.82, bar, ALU, steps=8)
    for side in (1.0, -1.0):
        h.rail(B, -0.3, GLASS_X, 3.47, bar * 1.2, ALU, side, step=0.06)
        h.rail(B, 0.34, GLASS_X, 3.4, bar, ALU, side, step=0.06)
        h.rail(B, 0.22, QUARTER_X, GLASS_X, bar, ALU, side)
        h.rail(B, 0.82, QUARTER_X, GLASS_X, bar, ALU, side)
        # Boat hull: a chine strake each side and a spray rail at the step.
        h.rail(B, CHINE, 2.9, -3.1, 0.024, CHROME, side)
    for x0, x1 in ((2.9, -0.8), (-0.86, -3.0)):
        h.rail(B, -1.0, x0, x1, 0.03, ALU)                                        # keel
    # Cabin windows over the cheatline, and the titles low on the flank.
    for side in (1.0, -1.0):
        for k in range(7):
            wx = 1.22 - k * 0.62
            decal(B, h, rounded_rect(0.5, 0.48, 0.12), wx, -1.5, side, ALU, 0.006)
            decal(B, h, rounded_rect(0.42, 0.4, 0.09), wx, -1.5, side, "heli_window", 0.012)
        decal(B, h, text_shape("SKYWAY", 0.34), 0.72, -2.42, side, NAVY, 0.012)
        # The airstair door's shut lines behind the cockpit.
        for dx in (1.56, 0.9):
            decal(B, h, rect(0.014, 1.0), dx, -1.55, side, DARK, 0.005)
    turbines(B)
    sponsons(B)
    tail(B, h)
    # Nose wheel, the lamp's housing under the chin, aerials.
    for z in (-0.11, 0.11):
        wheel(B, 1.95, -2.9, z, 0.19, 0.12)
    B.tube((2.62, -2.7, 0.0), (2.62, -2.86, 0.0), 0.11, CHROME, r1=0.14, segs=14)
    B.prism_z([(-1.9, -2.72), (-2.25, -2.72), (-2.3, -3.0), (-2.15, -3.0)], -0.015, 0.015, ALU)   # blade aerial
    for z in (-0.5, 0.5):                                                          # pitot heads
        B.tube((3.05, -2.52, z), (3.42, -2.56, z), 0.012, CHROME, segs=6)
    # Nav lights: starboard green (+Z), port red, white at the tail.
    ball(B, (-1.35, -2.44, 1.78), 0.06, "nav_green", 8, 6)
    ball(B, (-1.35, -2.44, -1.78), 0.06, "nav_red", 8, 6)
    ball(B, (-7.86, -1.06, 0.0), 0.05, "nav_white", 8, 6)
    return B.finish()


def turbines(B):
    """The twin turbines' housing on the roof, its intakes and exhausts, and the mast."""
    d = Hull([(2.0, -0.9, 0.42, 0.26, 0.08, 2.4, 2.0), (1.7, -0.9, 0.6, 0.44, 0.1, 2.8, 2.0),
              (1.0, -0.9, 0.66, 0.53, 0.1, 2.8, 2.0), (0.0, -0.9, 0.68, 0.57, 0.1, 2.8, 2.0),
              (-1.2, -0.9, 0.62, 0.5, 0.1, 2.6, 2.0), (-2.2, -0.9, 0.44, 0.33, 0.1, 2.2, 2.0),
              (-2.9, -0.9, 0.2, 0.14, 0.08, 2.0, 2.0), (-3.05, -0.9, 0.08, 0.06, 0.04, 2.0, 2.0)])
    rows = [-1.0, -0.5, 0.0, 0.2, 0.4, 0.58, 0.74, 0.86, 0.94, 0.985, 1.0]
    d.loft(B, stations(d), rows, lambda x, v, s: TEAL if (x > 1.72 and v > 0.0) else WHITE, caps=(WHITE, TEAL))
    for z in (-0.27, 0.27):
        B.tube((1.7, -0.66, z), (2.08, -0.66, z), 0.2, CHROME, segs=18, caps=False)
        B.tube((1.7, -0.66, z), (2.06, -0.66, z), 0.185, DARK, segs=18)
        ball(B, (2.07, -0.66, z), 0.07, CHROME, 8, 6)                              # the intake's bullet
    for s in (-1.0, 1.0):
        B.tube((-0.8, -0.64, s * 0.5), (-1.12, -0.56, s * 0.76), 0.1, DARK, r1=0.115, segs=14)
        B.tube((-1.08, -0.57, s * 0.728), (-1.135, -0.556, s * 0.772), 0.125, CHROME, segs=14, caps=False)
    B.lathe([(0.0, -0.4), (0.34, -0.4), (0.26, -0.3), (0.17, -0.22), (0.15, -0.16), (0.0, -0.16)], 0, 0, WHITE, segs=18)
    B.tube((0, -0.2, 0), (0, -0.04, 0), 0.065, ALU, segs=12)
    B.tube((-0.9, -0.4, 0.0), (-0.9, 0.02, 0.0), 0.012, ALU, segs=6)               # whip aerial


def sponsons(B):
    """A stub wing off the chine each side carrying a float, the main wheels half out beneath it."""
    pod = Hull([(-0.45, -2.45, 0.03, 0.03, 0.03, 2.0, 2.0), (-0.57, -2.45, 0.14, 0.12, 0.13, 2.0, 2.0),
                (-0.85, -2.45, 0.24, 0.2, 0.22, 2.0, 2.0), (-1.35, -2.45, 0.27, 0.22, 0.25, 2.2, 2.0),
                (-1.95, -2.45, 0.22, 0.18, 0.2, 2.0, 2.0), (-2.45, -2.43, 0.1, 0.09, 0.09, 2.0, 2.0),
                (-2.61, -2.42, 0.03, 0.03, 0.03, 2.0, 2.0)])
    rows = [-1.0, -0.86, -0.6, -0.3, 0.0, 0.3, 0.6, 0.86, 1.0]
    for s in (-1.0, 1.0):
        with xf_push(B, T(0.0, 0.0, s * 1.5)):
            pod.loft(B, stations(pod, [-0.57, -0.7]), rows,
                     lambda x, v, sd: TEAL if x > -0.8 else (ALU if v < -0.3 else WHITE), caps=(WHITE, TEAL))
        B.box(-1.95, -0.9, -2.44, -2.33, s * 0.7, s * 1.42, WHITE, 0.05)
        wheel(B, -1.35, -2.74, s * 1.5 + s * 0.1, 0.23, 0.15)                          # drawn up for flight
        wheel(B, -1.35, -2.74, s * 1.5 - s * 0.1, 0.23, 0.15)


def tail(B, h):
    """The fin swept up from the end of the boom, its tailplane to starboard, the gearbox to port."""
    fin = [(-6.55, -1.0), (-7.32, 0.3), (-7.86, 0.3), (-7.9, -1.22), (-7.0, -1.3)]
    B.prism_z(fin, -0.06, 0.06, WHITE, bevel=0.03)

    def band(y0, y1, mat, t):
        fx = lambda y: -6.55 + (-7.32 + 6.55) * (y + 1.0) / 1.3      # the leading edge at height y
        rx = lambda y: -7.9 + 0.04 * (y + 1.22) / 1.52                # the trailing edge
        B.prism_z([(fx(y0) + 0.004, y0), (fx(y1) + 0.004, y1), (rx(y1) - 0.004, y1), (rx(y0) - 0.004, y0)], -t, t, mat)
    band(-0.02, 0.306, TEAL, 0.066)
    band(-0.1, -0.02, NAVY, 0.066)
    B.box(-7.52, -6.95, -0.6, -0.55, 0.05, 1.25, WHITE, 0.02)                       # tailplane
    B.box(-7.52, -6.95, -0.602, -0.548, 1.05, 1.27, TEAL, 0.02)
    B.tube((TAIL_HUB[0], TAIL_HUB[1], -0.05), (TAIL_HUB[0], TAIL_HUB[1], TAIL_HUB[2] + 0.03), 0.09, ALU, r1=0.06, segs=12)


TAIL_HUB = (-7.6, -0.3, -0.24)
TAIL_R = 0.74


def rotor():
    """Hub, five blades with white tips, and the smear each leaves behind it as it turns."""
    B = Builder("Rotor")
    B.lathe([(0.0, -0.06), (0.2, -0.06), (0.24, 0.0), (0.22, 0.07), (0.13, 0.12), (0.0, 0.14)], 0, 0, CHROME, segs=20)
    B.lathe([(0.0, -0.13), (0.3, -0.13), (0.3, -0.1), (0.0, -0.1)], 0, 0, ALU, segs=20)     # swashplate
    for k in range(5):
        with xf_push(B, R("Y", 72.0 * k) @ R("Z", math.degrees(CONE))):
            B.tube((0.15, 0.03, 0.0), (0.62, 0.03, 0.0), 0.05, ALU, segs=10)
            B.tube((0.3, -0.11, 0.1), (0.42, 0.02, 0.06), 0.015, CHROME, segs=6)             # pitch link
            with xf_push(B, T(0.0, 0.03, 0.0) @ R("X", 5.0)):
                B.box(0.55, ROTOR_R - 0.32, -0.02, 0.02, -0.15, 0.15, "rotor_blade", 0.012)
                B.box(ROTOR_R - 0.32, ROTOR_R, -0.021, 0.021, -0.152, 0.152, "trim_white", 0.012)
    objs = B.finish()
    blur = Builder("RotorBlur")
    sweep, steps = math.radians(34.0), 8

    # UVs for src/fx/rotor_blur.gdshader: u 0 at the blade to 1 where its smear ends, v 1 at the hub
    # to 0 at the tip (glTF turns v over, so the shader reads the hub as 0).
    def at(r, a):          # a point of the coned disc, angle a about +Y
        return (r * math.cos(a), 0.03 + r * math.sin(CONE), -r * math.sin(a))
    r0, r1 = 0.5, ROTOR_R + 0.02
    for i in range(40):    # the whole disc, faintly
        a0, a1 = math.tau * i / 40, math.tau * (i + 1) / 40
        blur.quad(at(r0, a0), at(r1, a0), at(r1, a1), at(r0, a1), "rotor_blur", uv=[(0.8, 1), (0.8, 0), (0.8, 0), (0.8, 1)])
    for k in range(5):     # the game turns Rotor by -angle about Y, so each smear trails at +angle
        base = math.radians(72.0 * k)
        for i in range(steps):
            a0, a1 = base + sweep * i / steps, base + sweep * (i + 1) / steps
            u0, u1 = i / steps, (i + 1) / steps
            blur.quad(at(r0, a0), at(r1, a0), at(r1, a1), at(r0, a1), "rotor_blur", uv=[(u0, 1), (u0, 0), (u1, 0), (u1, 1)])
    bobjs = blur.finish()
    bobjs[0].parent = objs[0]
    return objs + bobjs


def tail_rotor():
    """Five small blades in the local XY plane, turned about Z, and their smear."""
    B = Builder("TailRotor")
    B.tube((0, 0, -0.05), (0, 0, 0.05), 0.07, CHROME, segs=12, bevel=0.015)
    for k in range(5):
        with xf_push(B, R("Z", 72.0 * k)):
            B.box(0.05, TAIL_R - 0.1, -0.05, 0.05, -0.012, 0.012, "rotor_blade", 0.008)
            B.box(TAIL_R - 0.1, TAIL_R, -0.051, 0.051, -0.013, 0.013, "trim_white", 0.008)
    objs = B.finish()
    blur = Builder("TailBlur")
    sweep, steps = math.radians(50.0), 6

    def at(r, a):
        return (r * math.cos(a), r * math.sin(a), 0.0)
    r0, r1 = 0.08, TAIL_R + 0.01
    for i in range(24):
        a0, a1 = math.tau * i / 24, math.tau * (i + 1) / 24
        blur.quad(at(r0, a0), at(r1, a0), at(r1, a1), at(r0, a1), "rotor_blur", uv=[(0.75, 1), (0.75, 0), (0.75, 0), (0.75, 1)])
    for k in range(5):     # turned by +angle about Z, so each smear trails at -angle
        base = math.radians(72.0 * k)
        for i in range(steps):
            a0, a1 = base - sweep * i / steps, base - sweep * (i + 1) / steps
            u0, u1 = i / steps, (i + 1) / steps
            blur.quad(at(r0, a0), at(r1, a0), at(r1, a1), at(r0, a1), "rotor_blur", uv=[(u0, 1), (u0, 0), (u1, 0), (u1, 1)])
    bobjs = blur.finish()
    bobjs[0].parent = objs[0]
    objs[0].location = gv(TAIL_HUB)
    return objs + bobjs


def lens(name, pos, r, mat):
    B = Builder(name)
    ball(B, (0.0, 0.0, 0.0), r, mat, 10, 8)
    objs = B.finish()
    objs[0].location = gv(pos)
    return objs


def empty(name, pos):
    e = bpy.data.objects.new(name, None)
    e.location = gv(pos)
    bpy.context.scene.collection.objects.link(e)
    return [e]


def helicopter():
    objs = body() + rotor() + tail_rotor()
    objs += lens("SearchlightMount", (2.62, -2.9, 0.0), 0.12, "nav_white")
    objs += lens("BeaconTop", (-7.58, 0.36, 0.0), 0.09, "nav_red")
    objs += lens("BeaconBelly", (0.3, -3.02, 0.0), 0.09, "nav_red")
    objs += empty("Flash", (0.3, -3.3, 0.0)) + empty("CockpitGlow", (2.75, -1.95, 0.0)) + empty("BellyLight", (0.0, -3.45, 0.0))
    return objs


def preview(objs, folder):
    """Workbench views from where the street sees it: below and to one side."""
    from mathutils import Vector
    os.makedirs(folder, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.05, 0.06, 0.09)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    sc.collection.objects.link(cam)
    sc.camera = cam
    for o in objs:
        o.hide_render = "Blur" in o.name
    views = {"side": (0.5, -1.8, 16.0), "below": (2.0, -9.0, 12.0), "below_port": (-3.0, -9.0, -12.0),
             "front": (14.0, -4.0, 7.0), "rear": (-15.0, -5.0, 7.0), "top": (1.0, 12.0, 6.0)}
    for name, p in views.items():
        cam.location = gv(p)
        d = Vector(gv((-1.6, -1.4, 0.0))) - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(folder, name + ".png")
        bpy.ops.render.render(write_still=True)
    for o in objs:
        o.hide_render = False


def main():
    kitlib.reset_scene()
    objs = helicopter()
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in argv:
        preview(objs, argv[argv.index("--preview") + 1])
    tris = sum(len(p.vertices) - 2 for o in objs if o.type == "MESH" for p in o.data.polygons)
    kitlib.export_glb(objs, os.path.join(OUT, "helicopter.glb"))
    print("vehicle %-18s tris %6d" % ("helicopter", tris))


if __name__ == "__main__":
    main()
