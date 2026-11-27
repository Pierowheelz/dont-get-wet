"""Generate the country-lane models for Long Lane (docs/CONTRACTS.md §10).

    blender -b -P tools/blender/country.py [-- --preview DIR] [--only NAME[,NAME...]]

Writes assets/country/<name>.glb: two field oaks, a hawthorn hedge, a five-bar gate, a Dutch barn
full of hay, a tiled bus shelter, a lychgate, a telegraph pole and the lane's small furniture (hay
bales, a milk churn stand, a milestone, a fingerpost). Also two suburban street trees for a
nature strip, a plane and a gum, which stand at z = 2.9 with their heads set back over the footpath.

Game coordinates, as everywhere in the kit: +X the way the walker walks, +Y up, +Z toward the
camera, 1 unit a metre, the origin on the ground. z = 0 is the hedge line, the walker's line is
z = 1.6 and the lane's edge z = 3.5.

Unlike the street kit these files carry their whole look: no textures and no shared .tres. Every
material is white and the paint is in the vertex colours (COLOR_0, linear): moss on what faces the
sky, damp at the foot, rust down the tin, each plank, tile and bale its own tone. Leaves are meshes
named Foliage (or Grass) whose material's name holds "foliage"; their COLOR_0 alpha is how far
that leaf may sway (0 held still, 1 free), so the game's wind shader needs nothing else.

`--preview DIR` also renders three views of each model into DIR: `<name>_game.png` from where the
game's camera stands (with a walker-sized figure on the walking line), `<name>_side.png` square on
and `<name>_three.png` from the lane at an angle.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kitlib  # noqa: E402
from kitlib import Builder, ROOT, R, T, gv, xf_push  # noqa: E402

OUT = os.path.join(ROOT, "assets", "country")
FONT = os.path.join(ROOT, "assets", "fonts", "BebasNeue-Regular.ttf")
TAU = math.tau
UP = Vector((0.0, 1.0, 0.0))


# ------------------------------------------------------------------------------------------------
# paint
# ------------------------------------------------------------------------------------------------

def lin(c):
    """An sRGB colour as the linear one the vertex colours hold."""
    return Vector([((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c])


MOSS = lin((0.27, 0.34, 0.13))
LICHEN = lin((0.60, 0.60, 0.42))
RUST = lin((0.40, 0.19, 0.09))

# col: the paint (sRGB). mottle: how blotchy. moss, lichen, rust: how much of each can grow on it.
# damp: how much darker it stands in the wet at its foot. sky: how much lighter its upward faces
# are than its undersides. double: seen from both sides. emit: glows (colour, energy).
MATS = {
    "country_bark":          dict(col=(0.23, 0.20, 0.17), rough=0.8),
    "country_oak_foliage":   dict(col=(0.20, 0.31, 0.13), rough=0.85, double=True),
    "country_plane_foliage": dict(col=(0.22, 0.31, 0.12), rough=0.85, double=True),
    "country_gum_foliage":   dict(col=(0.30, 0.36, 0.24), rough=0.8, double=True),
    "country_gum_bark":      dict(col=(0.62, 0.58, 0.50), rough=0.6),
    "country_hedge_foliage": dict(col=(0.18, 0.29, 0.13), rough=0.85, double=True),
    "country_grass_foliage": dict(col=(0.24, 0.36, 0.14), rough=0.8, double=True),
    "country_timber":        dict(col=(0.40, 0.36, 0.30), rough=0.7, mottle=0.3, moss=0.45, damp=0.4),
    "country_timber_tarred": dict(col=(0.13, 0.11, 0.10), rough=0.55, mottle=0.3, moss=0.2, damp=0.3),
    "country_paint_cream":   dict(col=(0.70, 0.66, 0.53), rough=0.6, mottle=0.16, moss=0.12, damp=0.4, streak=0.2),
    "country_paint_green":   dict(col=(0.13, 0.25, 0.18), rough=0.5, mottle=0.2, damp=0.3),
    "country_paint_white":   dict(col=(0.84, 0.83, 0.77), rough=0.45, mottle=0.1, rust=0.12, damp=0.3, streak=0.15),
    "country_paint_black":   dict(col=(0.05, 0.05, 0.05), rough=0.45, mottle=0.1, sky=0.1),
    "country_enamel":        dict(col=(0.07, 0.23, 0.15), rough=0.25, mottle=0.08, rust=0.15, sky=0.1),
    "country_brick":         dict(col=(0.47, 0.24, 0.18), rough=0.85, mottle=0.35, moss=0.3, damp=0.45),
    "country_stone":         dict(col=(0.50, 0.48, 0.43), rough=0.85, mottle=0.3, moss=0.55, lichen=0.5, damp=0.4),
    "country_concrete":      dict(col=(0.47, 0.46, 0.43), rough=0.8, mottle=0.25, moss=0.3, damp=0.4),
    "country_tile":          dict(col=(0.50, 0.25, 0.16), rough=0.6, mottle=0.3, moss=0.6, lichen=0.3),
    "country_slate":         dict(col=(0.34, 0.35, 0.36), rough=0.45, mottle=0.25, moss=0.5, lichen=0.45),
    "country_corrugated":    dict(col=(0.44, 0.46, 0.47), rough=0.45, metal=0.5, mottle=0.2, rust=0.75, streak=0.3, double=True, sky=0.2),
    "country_hay":           dict(col=(0.70, 0.62, 0.37), rough=0.9, mottle=0.3, freq=7.0, damp=0.15),
    "country_twine":         dict(col=(0.62, 0.38, 0.16), rough=0.8),
    "country_earth":         dict(col=(0.30, 0.25, 0.17), rough=0.9, mottle=0.4, freq=1.6, sky=0.0),
    "country_iron":          dict(col=(0.09, 0.09, 0.10), rough=0.5, metal=0.6, mottle=0.2, rust=0.35),
    "country_galvanised":    dict(col=(0.58, 0.60, 0.61), rough=0.35, metal=0.8, mottle=0.2, rust=0.12, sky=0.15),
    "country_ceramic":       dict(col=(0.83, 0.82, 0.75), rough=0.2, mottle=0.08),
    "country_lamp_glass":    dict(col=(1.0, 0.78, 0.45), rough=0.3, emit=((1.0, 0.72, 0.38), 2.2), sky=0.0),
}


def get_material(name):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    d = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = d.get("rough", 0.7)
    bsdf.inputs["Metallic"].default_value = d.get("metal", 0.0)
    if "emit" in d:
        e, k = d["emit"]
        bsdf.inputs["Emission Color"].default_value = (e[0], e[1], e[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = k
    m.use_backface_culling = not d.get("double", False)
    c = d["col"]
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    return m


kitlib.get_material = get_material     # the Builder asks kitlib for its materials


def nz(p):
    return noise.noise(Vector(p))


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def clamp(x, a=0.0, b=1.0):
    return min(max(x, a), b)


def shade(spec, tone, p, n):
    """The paint at point p whose face looks along n: the material's colour, weathered."""
    m = 0.5 + 0.5 * nz(p * spec.get("freq", 2.3))
    k = 1.0 - spec.get("mottle", 0.0) * m
    k *= 1.0 - spec.get("sky", 0.28) * (0.5 - 0.5 * n.y)
    k *= 1.0 - spec.get("damp", 0.0) * smooth(0.45, 0.0, p.y)
    if "streak" in spec:                       # where the rain runs down an upright face
        s = max(0.0, nz(Vector((p.x * 5.0, p.y * 0.35, p.z * 5.0))))
        k *= 1.0 - spec["streak"] * s * (1.0 - abs(n.y))
    c = Vector((spec["_lin"].x * tone[0], spec["_lin"].y * tone[1], spec["_lin"].z * tone[2])) * k
    if "rust" in spec:
        w = spec["rust"] * smooth(0.42, 0.8, 0.5 + 0.6 * nz(Vector((p.x * 1.4, p.y * 0.45, p.z * 1.4)) + Vector((3, 1, 7)))
                                  + 0.25 * nz(p * 6.0))
        c = c.lerp(RUST * (0.6 + 0.6 * m), w)
    if "moss" in spec:
        w = spec["moss"] * smooth(0.5, 0.95, 0.5 + 0.42 * n.y + 0.55 * nz(p * 1.2 + Vector((7, 3, 1)))
                                  + 0.2 * smooth(0.6, 0.0, p.y))
        c = c.lerp(MOSS * (0.6 + 0.7 * m), w)
    if "lichen" in spec:
        w = spec["lichen"] * smooth(0.62, 0.74, 0.5 + 0.5 * nz(p * 3.4 + Vector((1, 9, 4))) + 0.12 * n.y)
        c = c.lerp(LICHEN * (0.8 + 0.3 * m), w)
    return (clamp(c.x), clamp(c.y), clamp(c.z), 1.0)


for _spec in MATS.values():
    _spec["_lin"] = lin(_spec["col"])


# ------------------------------------------------------------------------------------------------
# builders
# ------------------------------------------------------------------------------------------------

class CB(Builder):
    """The kit's Builder, painting vertex colours as it finishes. Each part made after `tone()`
    takes that tone, so no two planks are quite the same grey."""

    def __init__(self, name, seed=None):
        super().__init__(name, seed)
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.tl = self.bm.faces.layers.int.new("tone")
        self.tones = [(1.0, 1.0, 1.0)]
        self.cur = 0

    def tone(self, var=0.14, hue=0.04):
        k = 1.0 - self.rng.uniform(0.0, var)
        h = self.rng.uniform(-hue, hue)
        self.tones.append((k * (1.0 + h), k, k * (1.0 - h)))
        self.cur = len(self.tones) - 1

    def plain(self, k=1.0):
        self.tones.append((k, k, k))
        self.cur = len(self.tones) - 1

    def face(self, verts, mat, smooth=False):
        f = super().face(verts, mat, smooth)
        f[self.tl] = self.cur
        return f

    def _bevel(self, faces, width, segs, mat):
        if width <= 0:
            return
        edges = list({e for f in faces for e in f.edges})
        res = bmesh.ops.bevel(self.bm, geom=edges, offset=width, offset_type="OFFSET", segments=segs,
                              profile=0.5, affect="EDGES", clamp_overlap=True)
        mi = self.mi(mat)
        for f in res.get("faces", []):
            f.material_index = mi
            f.smooth = True
            f[self.tl] = self.cur

    # -- shapes ---------------------------------------------------------------------------------
    def obox(self, o, ax, ay, az, mat, bevel=0.0, segs=1):
        """A box from corner o along three edge vectors (any orientation)."""
        o, ax, ay, az = Vector(o), Vector(ax), Vector(ay), Vector(az)
        P = [o, o + ax, o + ax + ay, o + ay, o + az, o + ax + az, o + ax + ay + az, o + ay + az]
        V = [self.v(p) for p in P]
        idx = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        faces = [self.face([V[i] for i in q], mat) for q in idx]
        self._orient_outward(faces, o + (ax + ay + az) * 0.5)
        if bevel > 0.0005:
            self._bevel(faces, min(bevel, 0.45 * min(ax.length, ay.length, az.length)), segs, mat)
        return faces

    def beam(self, p0, p1, w, h, mat, up=(0, 1, 0), bevel=0.0):
        """A timber from p0 to p1, w across and h deep (h measured toward `up`)."""
        p0, p1, upv = Vector(p0), Vector(p1), Vector(up)
        a = p1 - p0
        t = a.normalized()
        side = t.cross(upv)
        if side.length < 1e-4:
            side = t.cross(Vector((0, 0, 1)))
        side.normalize()
        upv = side.cross(t).normalized()
        return self.obox(p0 - side * (w / 2) - upv * (h / 2), a, upv * h, side * w, mat, bevel)

    def brace(self, p0, p1, bulge, w, h, mat, n=6, bevel=0.0):
        """A curved brace from p0 to p1, bowed by `bulge` at its middle."""
        p0, p1, b = Vector(p0), Vector(p1), Vector(bulge)
        c = (p0 + p1) * 0.5 + b * 2.0
        pts = [p0.lerp(c, i / n).lerp(c.lerp(p1, i / n), i / n) for i in range(n + 1)]
        for a, d in zip(pts, pts[1:]):
            e = (d - a).normalized() * (0.3 * h)
            self.beam(a - e, d + e, w, h, mat, up=b if b.length > 1e-4 else (0, 1, 0), bevel=bevel)

    def poly(self, pts, mat, both=False):
        V = [self.v(p) for p in pts]
        f = self.face(V, mat)
        if both:
            self.face([self.v(p) for p in reversed(pts)], mat)
        return f

    def grid(self, o, eu, ev, nu, nv, mat, lift=None):
        """A flat sheet o + u·eu + v·ev cut into nu × nv, so the paint has somewhere to vary.
        lift(u, v) raises each point along the sheet's normal."""
        o, eu, ev = Vector(o), Vector(eu), Vector(ev)
        nrm = eu.cross(ev).normalized()
        V = [[self.v(o + eu * (i / nu) + ev * (j / nv) + (nrm * lift(i / nu, j / nv) if lift else Vector()))
              for j in range(nv + 1)] for i in range(nu + 1)]
        return [self.face([V[i][j], V[i + 1][j], V[i + 1][j + 1], V[i][j + 1]], mat, smooth=lift is not None)
                for i in range(nu) for j in range(nv)]

    def blade(self, p, d, length, width, mat):
        """A wisp of straw or a leaf: a pointed quad seen from both sides."""
        p, d = Vector(p), Vector(d).normalized()
        s = d.cross(Vector((self.rng.uniform(-1, 1), self.rng.uniform(-1, 1), self.rng.uniform(-1, 1))))
        s = s.normalized() * (width / 2) if s.length > 1e-3 else Vector((width / 2, 0, 0))
        pts = [p, p + d * (0.45 * length) + s, p + d * length, p + d * (0.45 * length) - s]
        self.poly(pts, mat, both=True)

    def tiles(self, o, along, down, out, mat, w=0.26, expose=0.22, length=0.34, t=0.022, lift=0.045, var=0.3, over=0.05):
        """Courses of tiles on a slope: o its top corner at the ridge, `along` the whole run of
        the eave, `down` from ridge to eave, `out` the way the slope faces."""
        o, along, down, n = Vector(o), Vector(along), Vector(down), Vector(out).normalized()
        L, S = along.length, down.length
        a, d = along / L, down / S
        rows = int(math.ceil((S + over) / expose))
        for r in range(rows):
            s0 = r * expose
            s1 = min(s0 + length, S + over)
            if s1 - s0 < 0.04:
                continue
            x = -w * (0.5 if r % 2 else 0.0) - self.rng.uniform(0.0, 0.03)
            while x < L:
                x0, x1 = max(x, 0.0), min(x + w, L)
                x += w
                if x1 - x0 < 0.05:
                    continue
                self.tone(var, 0.07)
                top = o + a * (x0 + 0.004) + d * s0 + n * (0.004 + self.rng.uniform(0.0, 0.008))
                run = d * (s1 - s0) + n * (lift * (s1 - s0) / length + self.rng.uniform(-0.004, 0.006))
                self.obox(top, a * (x1 - x0 - 0.008), n * t, run, mat)
        self.plain()

    def corrugated(self, base, ulen, nv, mat, pitch=0.25, amp=0.03, sheet=1.0, seg=4):
        """Corrugated iron: base(u, v) -> (point, normal) for u metres along the waves' run and
        v 0..1 down the sheet. Each sheet-wide strip is its own tone."""
        nu = max(1, int(round(ulen / pitch))) * seg
        V = []
        for i in range(nu + 1):
            u = ulen * i / nu
            col = []
            for j in range(nv + 1):
                p, n = base(u, j / nv)
                col.append(self.v(Vector(p) + Vector(n) * (amp * math.cos(TAU * i / seg))))
            V.append(col)
        last = -1
        for i in range(nu):
            s = int((ulen * i / nu) / sheet)
            if s != last:
                self.tone(0.22, 0.03)
                last = s
            for j in range(nv):
                self.face([V[i][j], V[i + 1][j], V[i + 1][j + 1], V[i][j + 1]], mat, smooth=True)
        self.plain()

    def text(self, text, cap, origin, right, up, mat, tracking=1.08):
        """Letters `cap` tall lying in the plane (right, up), centred on origin's x, baseline at origin."""
        origin, right, up = Vector(origin), Vector(right).normalized(), Vector(up).normalized()
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = text
        cu.font = bpy.data.fonts.load(FONT, check_existing=True)
        cu.align_x = "CENTER"
        cu.space_character = tracking
        ob = bpy.data.objects.new("t", cu)
        bpy.context.scene.collection.objects.link(ob)
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bm = bmesh.new()
        bm.from_mesh(me)
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.meshes.remove(me)
        bpy.data.curves.remove(cu)
        ys = [v.co.y for v in bm.verts]
        s = cap / (max(ys) - min(ys))
        y0 = min(ys)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        want = gv(self.xf.to_3x3() @ right.cross(up))
        for f in bm.faces:
            g = self.face([self.v(origin + right * (v.co.x * s) + up * ((v.co.y - y0) * s)) for v in f.verts], mat)
            g.normal_update()
            if g.normal.dot(want) < 0:
                g.normal_flip()
        bm.free()

    # -- finishing ------------------------------------------------------------------------------
    def dice(self, step):
        """Cut every face on a grid of `step` metres, so moss and damp can shade across it."""
        bm = self.bm
        for ax in range(3):
            lo = min(v.co[ax] for v in bm.verts)
            hi = max(v.co[ax] for v in bm.verts)
            k = math.floor(lo / step) + 1
            while k * step < hi - 1e-4:
                co, no = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
                co[ax], no[ax] = k * step, 1.0
                bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
                k += 1

    def paint(self):
        bm = self.bm
        bm.normal_update()
        for f in bm.faces:
            spec = MATS[self.mats[f.material_index]]
            ti = f[self.tl]
            tone = self.tones[ti] if 0 <= ti < len(self.tones) else self.tones[0]
            for l in f.loops:
                co = l.vert.co
                nb = l.vert.normal if f.smooth else f.normal
                l[self.col] = shade(spec, tone, Vector((co.x, co.z, -co.y)), Vector((nb.x, nb.z, -nb.y)))

    def finish(self, dice=0.0):
        if dice > 0.0:
            self.dice(dice)
        self.paint()
        objs = super().finish()
        objs[0].data.color_attributes.active_color_name = "Col"
        objs[0].data.color_attributes.render_color_index = 0
        return objs


class Raw:
    """A mesh given vertex by vertex with its own normals and colours: trunks and leaves, whose
    shading wants to follow the whole crown, not each little face."""

    def __init__(self, name, mat):
        self.name, self.mat = name, mat
        self.p, self.n, self.c, self.f = [], [], [], []

    def vert(self, p, n, c):
        self.p.append(Vector(p))
        self.n.append(Vector(n).normalized())
        self.c.append(c)
        return len(self.p) - 1

    def finish(self):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata([gv(p) for p in self.p], [], self.f)
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        me.normals_split_custom_set_from_vertices([gv(n) for n in self.n])
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        attr.data.foreach_set("color", [x for c in self.c for x in c])
        me.color_attributes.active_color_name = "Col"
        me.color_attributes.render_color_index = 0
        me.materials.append(get_material(self.mat))
        me.update()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return [ob]


# ------------------------------------------------------------------------------------------------
# trees, hedge, grass
# ------------------------------------------------------------------------------------------------

BARK = lin((0.24, 0.21, 0.18))
BARK_MOSS = lin((0.26, 0.33, 0.14))
OAK_PAL = (lin((0.09, 0.16, 0.09)), lin((0.19, 0.30, 0.12)), lin((0.42, 0.50, 0.19)))
HEDGE_PAL = (lin((0.07, 0.13, 0.08)), lin((0.14, 0.24, 0.10)), lin((0.27, 0.36, 0.14)))
PLANE_PAL = (lin((0.08, 0.13, 0.07)), lin((0.19, 0.27, 0.10)), lin((0.40, 0.45, 0.17)))
GUM_PAL = (lin((0.12, 0.17, 0.13)), lin((0.26, 0.33, 0.22)), lin((0.48, 0.53, 0.36)))
GRASS_PAL = (lin((0.10, 0.17, 0.07)), lin((0.21, 0.33, 0.11)), lin((0.40, 0.50, 0.19)))
SKY = Vector((-0.25, 0.9, 0.35)).normalized()      # where the leaves' own light comes from
_ICO = {}


def ico(sub):
    if sub not in _ICO:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        bm.verts.index_update()
        _ICO[sub] = ([v.co.normalized() for v in bm.verts], [[v.index for v in f.verts] for f in bm.faces])
        bm.free()
    return _ICO[sub]


def bark_col(p, n):
    m = 0.5 + 0.5 * nz(p * 2.3)
    c = BARK * (0.62 + 0.6 * m)
    c *= 0.82 + 0.25 * nz(Vector((p.x * 8.0, p.y * 0.7, p.z * 8.0)))        # fissures running up it
    moss = smooth(0.45, 0.9, 0.5 + 0.4 * n.y - 0.22 * n.x + 0.5 * nz(p * 0.9 + Vector((5, 1, 2))))
    c = c.lerp(BARK_MOSS * (0.6 + 0.7 * m), 0.8 * moss)
    c *= 1.0 - 0.3 * smooth(0.5, 0.0, p.y)
    return (c.x, c.y, c.z, 1.0)


def make_bark(base, patch, amount, moss_amount):
    """Bark that sheds in plates: `base` with long patches of `patch` showing through."""
    base, patch = lin(base), lin(patch)

    def col(p, n):
        m = 0.5 + 0.5 * nz(p * 2.3)
        c = base * (0.7 + 0.45 * m)
        w = amount * smooth(0.46, 0.6, 0.5 + 0.5 * nz(Vector((p.x * 2.6, p.y * 0.55, p.z * 2.6)) + Vector((4, 8, 2))))
        c = c.lerp(patch * (0.75 + 0.4 * m), w)
        c *= 0.86 + 0.2 * nz(Vector((p.x * 9.0, p.y * 0.5, p.z * 9.0)))
        moss = smooth(0.5, 0.95, 0.5 + 0.4 * n.y - 0.2 * n.x + 0.5 * nz(p * 0.9 + Vector((5, 1, 2))))
        c = c.lerp(BARK_MOSS * (0.6 + 0.7 * m), moss_amount * moss)
        c *= 1.0 - 0.3 * smooth(0.5, 0.0, p.y)
        return (clamp(c.x), clamp(c.y), clamp(c.z), 1.0)
    return col


PLANE_BARK = make_bark((0.27, 0.25, 0.21), (0.50, 0.49, 0.37), 0.8, 0.5)
GUM_BARK = make_bark((0.66, 0.62, 0.54), (0.36, 0.30, 0.25), 0.7, 0.15)


def leaf_col(pal, light, jit=0.0):
    c = pal[0].lerp(pal[1], smooth(0.0, 0.55, light)).lerp(pal[2], smooth(0.55, 1.0, light))
    c = Vector((c.x * (1.0 + jit), c.y, c.z * (1.0 - jit)))
    return c


def limb(W, pts, radii, segs, rmod=None, colfn=bark_col):
    """A tapering round limb through pts (trunk, bough, twig), closed at its tip."""
    n = len(pts)
    tang = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
    u = tang[0].cross(Vector((1, 0, 0)) if abs(tang[0].x) < 0.9 else Vector((0, 0, 1))).normalized()
    rings = []
    for i in range(n):
        t = tang[i]
        u = (u - t * u.dot(t)).normalized()
        w = t.cross(u)
        ring = []
        for k in range(segs):
            th = TAU * k / segs
            d = u * math.cos(th) + w * math.sin(th)
            p = pts[i] + d * (radii[i] * (rmod(th, pts[i]) if rmod else 1.0 + 0.06 * nz(pts[i] * 1.7 + d)))
            ring.append(W.vert(p, d, colfn(p, d)))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(segs):
            j = (k + 1) % segs
            W.f.append((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
    tip = pts[-1] + tang[-1] * (radii[-1] * 0.6)
    ti = W.vert(tip, tang[-1], colfn(tip, tang[-1]))
    for k in range(segs):
        W.f.append((rings[-1][k], rings[-1][(k + 1) % segs], ti))


def bezier(a, c, b, n):
    return [a.lerp(c, i / n).lerp(c.lerp(b, i / n), i / n) for i in range(n + 1)]


def spray(F, p, n, axis, size, pal, light, alpha, rng, floor=None, width=0.6):
    """A spray of leaves: one pointed quad, both faces, shaded like the mass it grows from."""
    side = axis.cross(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))))
    if side.length < 1e-3:
        side = axis.cross(UP)
    side = side.normalized() * (size * width * 0.5)
    pts = [p - axis * (0.12 * size), p + axis * (0.42 * size) + side, p + axis * size, p + axis * (0.42 * size) - side]
    if floor is not None:
        pts = [Vector((q.x, max(q.y, floor), q.z)) for q in pts]
    jit = rng.uniform(-0.12, 0.12)
    cr = leaf_col(pal, light - 0.12, jit)
    ct = leaf_col(pal, light + 0.16, jit)
    cols = [cr, cr.lerp(ct, 0.5), ct, cr.lerp(ct, 0.5)]
    al = [alpha * 0.8, alpha, alpha, alpha] if not isinstance(alpha, (list, tuple)) else alpha
    i0 = len(F.p)
    for q, c, a in zip(pts, cols, al):
        F.vert(q, n, (c.x, c.y, c.z, a))
    F.f.append((i0, i0 + 1, i0 + 2, i0 + 3))


def dab(F, p, ns, axis, size, pal, light, alpha, rng, n, width=0.8, floor=None):
    """A spray of leaves lying on the mass it grows from like a slate on a roof: a broad
    pointed quad along `axis`, its face toward `ns`."""
    w = axis.cross(ns)
    if w.length < 1e-3:
        w = axis.cross(UP)
    w = w.normalized() * (0.5 * width * size)
    pts = [p - axis * (0.3 * size), p + axis * (0.12 * size) + w, p + axis * (0.7 * size), p + axis * (0.12 * size) - w]
    if floor is not None and min(q.y for q in pts) < floor:
        return
    if (pts[1] - pts[0]).cross(pts[2] - pts[1]).dot(ns) < 0:
        pts = [pts[0], pts[3], pts[2], pts[1]]
    jit = rng.uniform(-0.14, 0.14)
    cr, ct = leaf_col(pal, light - 0.14, jit), leaf_col(pal, light + 0.18, jit)
    i0 = len(F.p)
    for q, c in zip(pts, (cr, cr.lerp(ct, 0.4), ct, cr.lerp(ct, 0.4))):
        F.vert(q, n, (c.x, c.y, c.z, alpha))
    F.f.append((i0, i0 + 1, i0 + 2, i0 + 3))


def clump(F, c, rad, crown_c, crown_r, rng, dabs, pal, floor, sway, droop=0.8, width=0.8, size=(0.36, 0.9)):
    """A mass of leaves: a dark lumpy ball for the depth of it, covered in sprays that droop
    and lift off its surface. The shading follows the whole crown as much as the ball, so the
    tree reads as one rounded head."""
    dirs, faces = ico(2)
    off = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))

    def at(d, k=1.0):
        s = k * (1.0 + 0.3 * nz(d * 1.6 + off) + 0.14 * nz(d * 4.1 + off))
        p = c + Vector((d.x * rad.x * s, d.y * rad.y * s * (0.55 if d.y < 0 else 1.0), d.z * rad.z * s))
        out = p - crown_c
        out = Vector((out.x / crown_r.x, out.y / crown_r.y, out.z / crown_r.z)).normalized()
        n = (d * 0.5 + out * 0.5 + UP * 0.15).normalized()
        h = clamp((p.y - floor(3.0)) / (2.0 * crown_r.y))
        l = 0.05 + 0.5 * max(0.0, n.dot(SKY)) + 0.33 * h + 0.16 * nz(p * 0.7 + off) + 0.08 * nz(p * 2.6)
        return p, n, l
    base = len(F.p)
    for d in dirs:
        p, n, l = at(d, 0.84)
        p.y = max(p.y, floor(p.z) + 0.1)
        col = leaf_col(pal, l * 0.45 - 0.12)
        F.vert(p, n, (col.x, col.y, col.z, sway(p)))
    for f in faces:
        F.f.append(tuple(base + i for i in f))
    for _ in range(dabs):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        p, n, l = at(d)
        ns = Vector((d.x / rad.x, d.y / rad.y, d.z / rad.z)).normalized()
        down = -UP + ns * ns.y
        t1 = ns.cross(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))))
        t1 = t1.normalized() if t1.length > 1e-3 else Vector((1, 0, 0))
        axis = (down * droop + t1 * rng.uniform(0.2, 0.9) + ns * rng.uniform(0.1, 0.65)).normalized()
        if rng.random() < 0.1:
            l += 0.22                                    # a spray that catches the light
        dab(F, p + ns * rng.uniform(-0.05, 0.14), ns, axis, rng.uniform(*size), pal, l + rng.uniform(-0.08, 0.08), sway(p), rng, n,
            width=width, floor=floor(p.z + 0.3) - 0.05)


OAK = dict(fol="country_oak_foliage", bark="country_bark", barkfn=bark_col, pal=OAK_PAL, fork_y=2.9, bole=0.52, flare=0.24,
           clump=(0.34, 0.33, 0.4), shell=(0.5, 0.72), dabs=165, zlim=(-3.1, 3.85), hang=1.15, leaves={})
# A street tree stands on the nature strip at z = 2.9, so its head is set back over the footpath.
PLANE = dict(OAK, fol="country_plane_foliage", barkfn=PLANE_BARK, pal=PLANE_PAL, fork_y=3.3, bole=0.37, flare=0.14,
             clump=(0.35, 0.33, 0.4), zlim=(-4.45, 1.65), hang=0.0, leaves=dict(size=(0.4, 0.95)))
GUM = dict(OAK, fol="country_gum_foliage", bark="country_gum_bark", barkfn=GUM_BARK, pal=GUM_PAL, fork_y=4.0, bole=0.33, flare=0.1,
           clump=(0.25, 0.25, 0.3), shell=(0.55, 0.85), dabs=175, zlim=(-4.45, 1.65), hang=0.0,
           leaves=dict(droop=1.7, width=0.42, size=(0.45, 0.95)))


def oak(name, seed, crown_c, crown_r, n_clumps, lean, n_boughs, stub=False, kind=OAK):
    """A tree. As an oak: a short thick bole with flared roots, boughs that go out more than up,
    and a broad head of leaves browsed level underneath by the cattle. `kind` makes it a plane
    (a taller clean bole, bark shed in plates) or a gum (a pale bole forking high, small open
    masses of long hanging leaves with the sky between them)."""
    rng = random.Random(seed)
    W, F = Raw("Trunk", kind["bark"]), Raw("Foliage", kind["fol"])
    C, Rr = Vector(crown_c), Vector(crown_r)
    FY, barkfn = kind["fork_y"], kind["barkfn"]
    fork = Vector((lean[0], FY, lean[1]))

    def floor(z):
        """The underside of the leaves: 3.55 m over the walking line; an oak's hang lower behind the hedge line."""
        return 3.55 - kind["hang"] * smooth(0.1, -1.1, z)

    def sway(p):
        d = math.hypot(p.x - fork.x, p.z - fork.z) / max(Rr.x, Rr.z)
        return clamp(0.25 + 0.45 * d + 0.4 * (p.y - 3.55) / (2.0 * Rr.y))

    # Where the masses of leaves sit: spread evenly through the crown's shell, a few inside.
    centres = []
    for _ in range(n_clumps):
        best, bd = None, -1.0
        k = rng.uniform(0.78, 1.2)
        ry = Rr.y * kind["clump"][1] * k
        for _try in range(40):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
            if d.y < -0.35:
                d.y = -d.y * 0.5
            u = rng.uniform(*kind["shell"]) if rng.random() > 0.14 else rng.uniform(0.0, 0.3)
            q = C + Vector((d.x * Rr.x * u, d.y * Rr.y * u, d.z * Rr.z * u))
            q.y = max(q.y, floor(q.z) + 0.8 * ry + 0.1)
            dist = min([Vector(((q.x - e.x) / Rr.x, (q.y - e.y) / Rr.y, (q.z - e.z) / Rr.z)).length for e, _ in centres] or [9.0])
            if dist > bd:
                best, bd = q, dist
        centres.append((best, k))

    # The boughs: a leader and one for each quarter of the crown; each mass of leaves hangs
    # from the bough it is nearest.
    dirs = [Vector((0.1, 1.0, 0.05)).normalized()]
    a0 = rng.uniform(0, TAU)
    for i in range(n_boughs - 1):
        a = a0 + TAU * i / (n_boughs - 1) + rng.uniform(-0.25, 0.25)
        dirs.append(Vector((math.cos(a), rng.uniform(0.4, 0.75), math.sin(a))).normalized())
    groups = [[] for _ in dirs]
    for q, _ in centres:
        v = (q - fork).normalized()
        groups[max(range(len(dirs)), key=lambda i: dirs[i].dot(v))].append(q)

    def twigs(path, radii, group):
        for q in group:
            end = q - UP * (0.1 * Rr.y)
            i = min(range(3, len(path)), key=lambda j: (path[j] - end).length)
            mid = (path[i] + end) * 0.5 + UP * 0.25 + Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.1, 0.3), rng.uniform(-0.35, 0.35)))
            rs = max(radii[i] * 0.55, 0.05)
            limb(W, bezier(path[i], mid, end, 5), [rs + (0.025 - rs) * (j / 5) ** 0.7 for j in range(6)], 6, colfn=barkfn)

    def bough(start, group, r0, n=9):
        mean = sum(group, Vector()) / len(group)
        target = start + (mean - start) * 0.85
        L = (target - start).length
        ctrl = start + (target - start) * 0.36 + UP * (0.3 * L) + Vector((rng.uniform(-0.4, 0.4), 0, rng.uniform(-0.4, 0.4)))
        path = bezier(start, ctrl, target, n)
        ph = rng.uniform(0, TAU)
        side = (target - start).cross(UP).normalized() if (target - start).cross(UP).length > 0.1 else Vector((1, 0, 0))
        path = [p + side * (0.16 * math.sin(i * 1.9 + ph) * min(i, n - i) / n * 2.0) for i, p in enumerate(path)]
        return path, [r0 + (0.07 - r0) * (i / n) ** 0.8 for i in range(n + 1)]

    # The bole, running on into the leader.
    ys = [-0.2, 0.0, 0.1, 0.25, 0.5, 0.9, 1.5] + [2.1 + 0.5 * i for i in range(int((FY - 0.3 - 2.1) / 0.5) + 1)]
    bend = rng.uniform(0, TAU)
    pts = [Vector((fork.x * (max(y, 0.0) / FY) ** 1.4 + 0.07 * math.sin(y * 1.3 + bend), y,
                   fork.z * (max(y, 0.0) / FY) ** 1.4 + 0.05 * math.cos(y * 1.1 + bend))) for y in ys]
    BR = kind["bole"]
    rad = [BR + kind["flare"] * math.exp(-max(y, 0.0) / 0.26) + 0.06 * smooth(FY - 1.0, FY - 0.2, y) for y in ys]
    lead = groups[0] or [C + UP * (0.4 * Rr.y)]
    lp, lr = bough(pts[-1], lead, BR * 0.88)
    ph = rng.uniform(0, TAU)

    def rmod(th, p):
        but = math.exp(-max(p.y, 0.0) / 0.4)
        return 1.0 + 0.2 * but * math.cos(5.0 * th + ph) + 0.03 * math.sin(13.0 * th + 4.0 * nz(p * 0.7)) + 0.07 * nz(p * 1.9 + Vector((th, 0, 0)))
    limb(W, pts + lp[1:], rad + lr[1:], 16, rmod=rmod, colfn=barkfn)
    twigs([pts[-1]] * 3 + lp[3:], [lr[0]] * 3 + lr[3:], groups[0])
    for d, group in zip(dirs[1:], groups[1:]):
        if not group:
            continue
        start = fork + Vector((d.x, 0, d.z)) * 0.2 + UP * rng.uniform(-0.5, -0.15)
        path, radii = bough(start, group, clamp(0.24 + 0.03 * len(group), 0.26, 0.37) * BR / 0.52)
        limb(W, path, radii, 9, colfn=barkfn)
        twigs(path, radii, group)
    if stub:                                    # the stump of a bough lost in some old gale
        a = Vector((-0.3 + fork.x * 0.5, 2.1, -0.1))
        limb(W, [a, a + Vector((-0.5, 0.25, 0.12)), a + Vector((-0.95, 0.42, 0.2)), a + Vector((-1.15, 0.47, 0.22))],
             [0.2, 0.17, 0.15, 0.13], 9)

    for q, k in centres:
        ck = kind["clump"]
        clump(F, q, Vector((Rr.x * ck[0] * k, Rr.y * ck[1] * k, Rr.z * ck[2] * k)), C, Rr, rng, kind["dabs"], kind["pal"], floor, sway,
              **kind["leaves"])

    # Keep the head inside the lot it was drawn for.
    for p in F.p:
        p.x = clamp(p.x, C.x - Rr.x - 0.25, C.x + Rr.x + 0.25)
        p.z = clamp(p.z, *kind["zlim"])
    return W.finish() + F.finish()


def grass(G, cx, cz, rx, rz, n, rng, h=(0.12, 0.36)):
    """Tufts of grass round a foot: thin blades bending outward."""
    for _ in range(n):
        a = rng.uniform(0, TAU)
        r = rng.uniform(0.75, 1.15)
        p = Vector((cx + math.cos(a) * rx * r, 0.0, cz + math.sin(a) * rz * r))
        hh = rng.uniform(*h)
        lean = Vector((math.cos(a), 0, math.sin(a))) * rng.uniform(0.0, 0.45) + Vector((rng.uniform(-0.2, 0.2), 0, rng.uniform(-0.2, 0.2)))
        axis = (UP + lean).normalized()
        l = rng.uniform(0.25, 0.75)
        spray(G, p, (UP + lean * 0.5).normalized(), axis, hh, GRASS_PAL, l, [0.0, 0.5, 1.0, 0.5], rng, floor=0.0, width=0.22)


def hedge():
    """Four metres of hawthorn hedge that tiles end to end: both ends have the same section."""
    rng = random.Random("hedge")
    F = Raw("Foliage", "country_hedge_foliage")
    N, M, LEN = 32, 12, 4.0

    def per(x, a, b):
        ang = TAU * x / LEN
        return nz(Vector((math.cos(ang) * a, math.sin(ang) * a, b)))

    def surf(x, t, k=1.0):
        a = math.pi * t
        cz, sy = math.cos(a), math.sin(a)
        H = 1.6 + 0.1 * per(x, 0.9, 3.1) + 0.05 * per(x, 2.6, 8.3)
        hw = 0.4 + 0.05 * per(x, 1.1, 6.0)
        n = Vector((0.0, sy, cz)).normalized()
        bump = 0.07 * per(x, 1.7, t * 4.0 + 1.0) + 0.04 * per(x, 3.6, t * 9.0 + 5.0)
        z = -0.5 + k * (hw * math.copysign(abs(cz) ** 0.55, cz) + n.z * bump)
        y = k * (H * sy ** 0.5 + n.y * bump)
        return Vector((x, max(y, 0.0), z)), n

    def light(p, n):
        return 0.08 + 0.42 * max(0.0, n.dot(SKY)) + 0.32 * smooth(0.1, 1.7, p.y) + 0.18 * per(p.x, 1.3, p.y * 1.5 + n.z)

    def sway(p):
        return clamp(p.y / 1.8) ** 1.5

    V = []
    for i in range(N + 1):
        x = LEN * i / N
        row = []
        for j in range(M + 1):
            p, n = surf(x if i < N else 0.0, j / M, 0.9)
            p.x = x
            col = leaf_col(HEDGE_PAL, light(p, n) * 0.45 - 0.1)
            row.append(F.vert(p, n, (col.x, col.y, col.z, sway(p))))
        V.append(row)
    for i in range(N):
        for j in range(M):
            F.f.append((V[i][j], V[i + 1][j], V[i + 1][j + 1], V[i][j + 1]))
    for i, nx in ((0, -1.0), (N, 1.0)):          # the cut ends, seen where a gate breaks the hedge
        c = F.vert((LEN * i / N, 0.8, -0.5), (nx, 0.3, 0), (HEDGE_PAL[1].x * 0.7, HEDGE_PAL[1].y * 0.7, HEDGE_PAL[1].z * 0.7, 0.3))
        for j in range(M):
            F.f.append((V[i][j + 1], V[i][j], c) if i == 0 else (V[i][j], V[i][j + 1], c))
    for _ in range(2300):
        x, t = rng.uniform(0.0, LEN), rng.uniform(0.01, 0.99)
        p, n = surf(x, t)
        shoot = 0.3 < t < 0.7 and rng.random() < 0.25    # the year's growth standing up off the top
        rnd = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if shoot:
            axis = (UP + rnd * 0.3).normalized()
            ns = (Vector((0, 0, 1)) + rnd * 0.4).normalized()
            size, width = rng.uniform(0.2, 0.36), 0.45
        else:
            axis = (UP * 0.55 + n * rng.uniform(0.1, 0.6) + rnd * 0.7).normalized()
            ns = (n + rnd * 0.3).normalized()
            size, width = rng.uniform(0.2, 0.36), 0.8
        dab(F, p + n * rng.uniform(-0.04, 0.05), ns, axis, size, HEDGE_PAL, light(p, n) + (0.12 if shoot else 0.0) + rng.uniform(-0.08, 0.08),
            sway(p), rng, (n + UP * 0.3).normalized(), width=width)
    for p in F.p:
        p.z = clamp(p.z, -1.0, 0.1)
        p.y = max(p.y, 0.0)
    return F.finish()


# ------------------------------------------------------------------------------------------------
# timber and tin
# ------------------------------------------------------------------------------------------------

def plank(B, x0, x1, y0, y1, z0, z1, mat, bevel=0.012, var=0.16):
    B.tone(var)
    return B.box(x0, x1, y0, y1, z0, z1, mat, bevel, segs=1)


def gate():
    """A five-bar field gate between its posts, hung at the left and dropping a little at the
    latch as they all do."""
    B = CB("Body")
    G = Raw("Grass", "country_grass_foliage")
    tm, iron = "country_timber", "country_iron"
    z = -0.05
    for x in (0.1, 3.5):
        plank(B, x - 0.1, x + 0.1, -0.1, 1.42, z - 0.1, z + 0.1, tm, 0.025)
        B.lathe([(0.135, 1.42), (0.135, 1.45), (0.0, 1.56)], x, z, tm, segs=4, sharp_deg=20.0)   # weathered cap
        grass(G, x, z, 0.16, 0.16, 16, B.rng)
    hx = 0.26                                                                # the hanging stile
    with xf_push(B, T(hx, 0.12, z) @ R("Z", -0.9) @ T(-hx, -0.12, -z)):
        plank(B, hx, hx + 0.09, 0.1, 1.4, z - 0.04, z + 0.04, tm, 0.012)
        plank(B, 3.25, 3.34, 0.12, 1.22, z - 0.035, z + 0.035, tm, 0.012)
        for i, y in enumerate((0.2, 0.41, 0.64, 0.9)):
            plank(B, hx + 0.09, 3.25, y - 0.045, y + 0.045, z - 0.016, z + 0.016, tm, 0.008)
        B.tone(0.16)                                                         # the top rail, deep at the heel
        B.obox((hx + 0.09, 1.1, z - 0.03), (3.16 - hx, 0.05, 0), (0, 0.15, 0), (0, 0, 0.06), tm, 0.01)
        B.obox((hx + 0.09, 1.1, z - 0.03), (3.16 - hx, 0.05, 0), (0, 0.08, 0), (0, 0, 0.06), tm, 0.0)
        for (a, b) in (((hx + 0.1, 0.2), (1.85, 1.13)), ((3.24, 0.2), (1.85, 1.13))):
            B.tone(0.16)
            B.beam((a[0], a[1], z + 0.03), (b[0], b[1], z + 0.03), 0.028, 0.085, tm, bevel=0.006)
        plank(B, 1.81, 1.89, 0.16, 1.16, z + 0.016, z + 0.044, tm, 0.006)
        B.plain(0.9)
        for y in (0.2, 1.17):                                                # strap hinges
            B.box(hx - 0.04, hx + 0.55, y - 0.02, y + 0.02, z + 0.04, z + 0.05, iron)
            B.tube((hx - 0.06, y - 0.05, z + 0.06), (hx - 0.06, y + 0.05, z + 0.06), 0.014, iron, segs=8)
        B.box(3.2, 3.42, 0.86, 0.9, z + 0.036, z + 0.05, iron)                 # the latch
        B.tube((3.1, 0.88, z + 0.05), (3.1, 0.88, z + 0.1), 0.012, iron, segs=6)
    return B.finish(dice=0.3) + G.finish()


def bale(B, x, y, z, L=0.9, H=0.36, W=0.45, yaw=0.0, mat="country_hay"):
    """A plain square bale lying along X, its corner at (x, y, z) going toward −Z."""
    r = B.rng
    with xf_push(B, T(x + L / 2, y, z - W / 2) @ R("Y", yaw + r.uniform(-2.0, 2.0))):
        B.tone(0.24, 0.05)
        B.box(-L / 2 + 0.008, L / 2 - 0.008, 0.0, H - 0.006, -W / 2, W / 2, mat, 0.04, segs=1)


def softbale(B, M, L=0.95, W=0.47, H=0.38):
    """A bale seen close: rounded, lumpy, pinched in where its two strings bite."""
    r = B.rng
    nu, nv = 14, 16
    off = Vector((r.uniform(0, 30), r.uniform(0, 30), r.uniform(0, 30)))
    with xf_push(B, M):
        B.tone(0.2, 0.05)
        rings = []
        for i in range(nu + 1):
            a = -math.pi / 2 + math.pi * i / nu
            cx, cr = math.sin(a), max(math.cos(a), 0.0)
            x = (L / 2) * math.copysign(abs(cx) ** 0.22, cx)
            k = cr ** 0.22
            if k < 1e-3:
                rings.append([B.v((x, H / 2, 0.0))])
                continue
            k *= 1.0 - 0.06 * (math.exp(-((x - 0.24) / 0.035) ** 2) + math.exp(-((x + 0.24) / 0.035) ** 2))
            ring = []
            for j in range(nv):
                th = TAU * j / nv
                cy, sz = math.cos(th), math.sin(th)
                p = Vector((x, (H / 2) * math.copysign(abs(cy) ** 0.25, cy) * k, (W / 2) * math.copysign(abs(sz) ** 0.25, sz) * k))
                p *= 1.0 + 0.035 * nz(p * 5.0 + off)
                ring.append(B.v((p.x, p.y + H / 2, p.z)))
            rings.append(ring)
        faces = []
        for A, C in zip(rings, rings[1:]):
            for j in range(nv):
                k2 = (j + 1) % nv
                if len(A) == 1:
                    vs = [A[0], C[j], C[k2]]
                elif len(C) == 1:
                    vs = [A[j], A[k2], C[0]]
                else:
                    vs = [A[j], A[k2], C[k2], C[j]]
                faces.append(B.face(vs, "country_hay", smooth=True))
        B._orient_outward(faces, (0.0, H / 2, 0.0))
        B.plain()
        for x in (-0.24, 0.24):                                              # the strings
            h, w, t = H / 2 * 0.975, W / 2 * 0.975, 0.008
            for (a, b) in (((-h, -w), (-h, w)), ((-h, w), (h, w)), ((h, w), (h, -w)), ((h, -w), (-h, -w))):
                B.beam((x, a[0] + H / 2, a[1]), (x, b[0] + H / 2, b[1]), t, t, "country_twine", up=(1, 0, 0))
        for _ in range(26):                                                  # loose straws
            p = Vector((r.uniform(-L / 2, L / 2), r.uniform(0.02, H), r.choice((-W / 2, W / 2)) * 0.97))
            d = Vector((r.uniform(-1, 1), r.uniform(-0.4, 1), math.copysign(0.7, p.z)))
            B.tone(0.25, 0.05)
            B.blade(p, d, r.uniform(0.06, 0.16), 0.02, "country_hay")
        B.plain()


def hay_bales():
    """A few bales left by the gateway: two on the ground, one across them, one fallen against
    the end, one on its own."""
    B = CB("Body")
    G = Raw("Grass", "country_grass_foliage")
    softbale(B, T(-0.5, 0.0, -0.1) @ R("Y", 3.0))
    softbale(B, T(-0.48, 0.0, 0.4) @ R("Y", -2.0))
    softbale(B, T(-0.5, 0.375, 0.15) @ R("Y", 84.0))
    softbale(B, T(0.36, 0.2, 0.12) @ R("Z", 58.0) @ R("Y", 90.0) @ T(0, -0.19, 0))
    softbale(B, T(0.68, 0.0, 0.42) @ R("Y", -28.0))
    grass(G, -0.05, 0.15, 1.25, 0.75, 44, B.rng)
    return B.finish() + G.finish()


def dutch_barn():
    """An open-fronted Dutch barn: a curved tin roof on tarred posts, tin on the back and ends,
    the hay stacked inside with the near end half used. Eight metres long; its roof reaches out
    over the verge to z = 2.6."""
    B = CB("Body")
    r = B.rng
    tar, tin, hay = "country_timber_tarred", "country_corrugated", "country_hay"
    LEN, ZB, ZF, EAVE, RISE = 8.0, -5.0, 2.6, 4.45, 1.9
    half = (ZF - ZB) / 2
    RAD = (half * half + RISE * RISE) / (2 * RISE)
    zc, yc = (ZF + ZB) / 2, EAVE + RISE - RAD
    phi0 = math.asin(half / RAD)

    def arc(phi, inset=0.0):
        return Vector((0.0, yc + (RAD - inset) * math.cos(phi), zc + (RAD - inset) * math.sin(phi)))

    def roof_y(z, inset=0.0):
        return yc + math.sqrt(max((RAD - inset) ** 2 - (z - zc) ** 2, 0.0))

    # The roof, a little proud of the walls at each end.
    def roof(u, v):
        phi = -phi0 + 2 * phi0 * v
        p = arc(phi)
        return (Vector((u - 0.12, p.y, p.z)), Vector((0.0, math.cos(phi), math.sin(phi))))
    B.corrugated(roof, LEN + 0.24, 12, tin, sheet=0.9)

    # Tin on the back, and on both ends as far forward as the building line.
    B.corrugated(lambda u, v: (Vector((u, (EAVE - 0.05) * (1 - v), ZB + 0.06)), Vector((0, 0, 1))), LEN, 4, tin, sheet=0.9)
    for x, s in ((0.07, 1.0), (LEN - 0.07, -1.0)):
        def end(u, v, x=x, s=s):
            z = ZB + 0.06 + u
            return (Vector((x, (roof_y(z, 0.08)) * (1 - v), z)), Vector((s, 0, 0)))
        B.corrugated(end, -0.2 - ZB, 5, tin, sheet=0.9)

    # The frame: posts front and back, a curved rib and a tie at each, purlins, the eaves beam.
    frames = (0.15, LEN / 2, LEN - 0.15)
    for x in frames:
        for z in (ZB + 0.12, 2.4):
            plank(B, x - 0.1, x + 0.1, 0.0, roof_y(z, 0.3), z - 0.1, z + 0.1, tar, 0.02)
            B.plain()
            B.box(x - 0.2, x + 0.2, -0.05, 0.14, z - 0.2, z + 0.2, "country_concrete", 0.03, segs=1)
        if x != LEN / 2:
            plank(B, x - 0.1, x + 0.1, 0.0, roof_y(-0.2, 0.3), -0.3, -0.1, tar, 0.02)
        B.tone(0.15)
        pts = [arc(-phi0 + 2 * phi0 * i / 14, 0.19) for i in range(15)]
        for a, b in zip(pts, pts[1:]):
            B.beam((x, a.y, a.z), (x, b.y, b.z), 0.08, 0.14, tar, up=(0, 1, 0))
        plank(B, x - 0.05, x + 0.05, 4.42, 4.6, ZB + 0.1, 2.5, tar, 0.012)
        for z0, z1 in ((2.4, 1.7), (ZB + 0.12, ZB + 0.82)):
            B.beam((x, 3.72, z0), (x, 4.44, z1), 0.07, 0.11, tar, up=(0, 0, -1 if z1 < z0 else 1))
    for i in range(1, 8):
        p = arc(-phi0 + 2 * phi0 * i / 8, 0.09)
        B.tone(0.15)
        B.beam((0.0, p.y, p.z), (LEN, p.y, p.z), 0.07, 0.1, tar, up=(0, math.cos(-phi0 + 2 * phi0 * i / 8), math.sin(-phi0 + 2 * phi0 * i / 8)))
    plank(B, 0.0, LEN, 4.38, 4.6, 2.33, 2.47, tar, 0.02)                       # the eaves beam over the verge
    for x in frames:
        for s in (-1, 1):
            if 0.0 < x + s * 0.75 < LEN:
                B.tone(0.15)
                B.beam((x, 3.7, 2.4), (x + s * 0.72, 4.4, 2.4), 0.07, 0.11, tar, up=(-s, 0, 0))
    # The gutter along the front and its pipe down the last post.
    B.plain(0.9)
    B.tube((-0.1, 4.37, ZF + 0.05), (LEN + 0.1, 4.33, ZF + 0.05), 0.07, "country_iron", segs=8)
    B.tube((LEN - 0.15, 4.3, ZF + 0.05), (LEN - 0.15, 4.0, 2.52), 0.04, "country_iron", segs=8)
    B.tube((LEN - 0.15, 4.0, 2.52), (LEN - 0.15, 0.2, 2.52), 0.04, "country_iron", segs=8)

    # The floor: trodden earth and chaff, kept behind the building line so the verge stays the game's.
    B.plain()
    B.grid((0.12, 0.025, 0.05), (LEN - 0.24, 0, 0), (0, 0, ZB + 0.05), 20, 12, "country_earth")

    # The stack: courses of bales stepping back as they rise, the right-hand end part used.
    BL, BH, BW = 0.9, 0.36, 0.45
    ends = [8, 8, 8, 7, 7, 6, 5, 5, 4]                                        # bales in each course
    x0 = 0.42
    for k, nb in enumerate(ends):
        y = 0.03 + k * BH
        zf = -0.95 - 0.13 * k - (0.1 if k % 2 else 0.0)
        shift = 0.0 if k % 2 == 0 else -0.2
        for c in range(nb):
            bale(B, x0 + shift + c * BL + r.uniform(-0.015, 0.015), y, zf + r.uniform(-0.03, 0.03), BL, BH, BW)
        # the bales behind, as one mass with a broken top
        B.tone(0.12)
        xe = x0 + shift + nb * BL
        B.grid((x0 + shift, y + BH - 0.01, zf - BW + 0.02), (xe - x0 - shift, 0, 0), (0, 0, ZB + 0.15 - (zf - BW)), nb * 2, 6, hay,
               lift=lambda u, v: 0.02 * nz(Vector((u * 9.0, v * 5.0, k * 3.1))))
        B.grid((xe - 0.01, y, zf - BW + 0.02), (0, BH, 0), (0, 0, ZB + 0.15 - (zf - BW)), 1, 6, hay)
        for _ in range(nb * 3):
            p = Vector((r.uniform(x0, xe), y + r.uniform(0.05, BH), zf + 0.01))
            B.tone(0.3, 0.05)
            B.blade(p, (r.uniform(-1, 1), r.uniform(-0.8, 0.6), 0.8), r.uniform(0.08, 0.2), 0.025, hay)
    # Loose hay pulled down at the used end, two bales waiting, a fork stood in the heap.
    B.tone(0.1)
    B.lathe([(1.15, 0.03), (0.95, 0.16), (0.6, 0.36), (0.25, 0.5), (0.0, 0.54)], 6.55, -1.25, hay, segs=14)
    for _ in range(60):
        a, q = r.uniform(0, TAU), r.uniform(0.2, 1.1)
        p = Vector((6.55 + math.cos(a) * q, 0.05 + 0.5 * (1 - q / 1.15), -1.25 - math.sin(a) * q))
        B.tone(0.3, 0.05)
        B.blade(p, (math.cos(a), r.uniform(0.2, 1.2), -math.sin(a)), r.uniform(0.12, 0.3), 0.03, hay)
    bale(B, 5.0, 0.03, -0.25, yaw=8.0)
    bale(B, 5.25, 0.39, -0.3, yaw=-14.0)
    B.plain()
    B.beam((6.9, 0.3, -1.0), (7.25, 1.75, -0.75), 0.035, 0.035, "country_timber")       # the fork
    for dz in (-0.07, 0.0, 0.07):
        B.beam((6.9 + dz * 0.3, 0.3, -1.0 + dz), (6.83 + dz * 0.3, 0.02, -1.06 + dz), 0.012, 0.012, "country_iron")
    # A ladder against the stack.
    for dx in (-0.2, 0.2):
        B.tone(0.12)
        B.beam((2.5 + dx, 0.03, -0.3), (2.5 + dx, 3.5, -2.05), 0.05, 0.07, "country_timber", up=(0, 0.45, 0.9))
    for i in range(10):
        t = 0.08 + 0.085 * i
        B.tube((2.3, 0.03 + 3.47 * t, -0.3 - 1.75 * t), (2.7, 0.03 + 3.47 * t, -0.3 - 1.75 * t), 0.017, "country_timber", segs=6, caps=False)
    return B.finish()


def bus_shelter():
    """A country bus shelter: brick plinth, boarded back, a bench, a tiled roof carried out over
    the verge on two posts. The walker passes under the roof between the wall and the posts."""
    B = CB("Body")
    G = Raw("Grass", "country_grass_foliage")
    cream, green, brick, tile = "country_paint_cream", "country_paint_green", "country_brick", "country_tile"
    W = 4.0
    # Plinth and floor.
    B.box(0.0, W, 0.0, 0.5, -0.14, 0.06, brick, 0.012, segs=1)
    for x0, x1 in ((0.0, 0.14), (W - 0.14, W)):
        B.box(x0, x1, 0.0, 0.5, 0.06, 0.78, brick, 0.012, segs=1)
    B.box(0.14, W - 0.14, 0.0, 0.035, 0.06, 0.8, "country_concrete", 0.01, segs=1)
    # The boarded back and the half-height wings.
    n = 27
    for i in range(n):
        x0 = 0.1 + (W - 0.2) * i / n
        plank(B, x0 + 0.004, x0 + (W - 0.2) / n - 0.004, 0.5, 2.52, -0.085, -0.055, cream, 0.0, var=0.1)
    for x in (0.02, W - 0.14):
        for i in range(5):
            z0 = 0.06 + 0.7 * i / 5
            plank(B, x + 0.03, x + 0.07, 0.5, 1.3, z0 + 0.004, z0 + 0.136, cream, 0.0, var=0.1)
        plank(B, x, x + 0.12, 1.3, 1.37, 0.0, 0.8, green, 0.01)
    for x in (0.07, W / 2, W - 0.07):                                          # the back frame
        plank(B, x - 0.055, x + 0.055, 0.5, 2.52, -0.06, 0.05, green, 0.012)
    for y in (0.5, 1.45):
        plank(B, 0.1, W - 0.1, y, y + 0.08, -0.058, 0.04, green, 0.01)
    for x in (0.07, W - 0.07):
        plank(B, x - 0.055, x + 0.055, 0.5, 2.52, 0.68, 0.79, green, 0.012)
    # Timetable case on the back wall.
    plank(B, 2.55, 3.35, 1.6, 2.3, -0.055, -0.02, green, 0.008)
    B.plain()
    B.box(2.6, 3.3, 1.65, 2.25, -0.03, -0.012, cream)
    B.plain(0.5)
    for i in range(9):
        B.box(2.66, 3.24 - 0.12 * (i % 3), 2.16 - i * 0.055, 2.175 - i * 0.055, -0.014, -0.009, "country_paint_black")
    # The bench.
    for i in range(3):
        plank(B, 0.3, W - 0.3, 0.45, 0.48, 0.1 + i * 0.14, 0.22 + i * 0.14, "country_timber", 0.008)
    for x in (0.5, W / 2, W - 0.5):
        plank(B, x - 0.03, x + 0.03, 0.035, 0.45, 0.1, 0.48, green, 0.008)
    # Posts on stone pads at the front corners, the plates they carry, braces along the front.
    FZ = 2.2
    for x, s in ((0.1, 1), (W - 0.1, -1)):
        B.plain()
        B.box(x - 0.14, x + 0.14, -0.05, 0.2, FZ - 0.14, FZ + 0.14, "country_stone", 0.03, segs=1)
        plank(B, x - 0.065, x + 0.065, 0.2, 2.5, FZ - 0.065, FZ + 0.065, green, 0.015)
        plank(B, x - 0.06, x + 0.06, 2.5, 2.67, -0.1, FZ + 0.07, green, 0.012)
        B.tone(0.14)
        B.brace((x, 1.92, FZ), (x + s * 0.6, 2.52, FZ), (-s * 0.06, 0.06, 0), 0.06, 0.09, green)
        grass(G, x, FZ, 0.2, 0.2, 12, B.rng, h=(0.1, 0.25))
    plank(B, -0.05, W + 0.05, 2.5, 2.67, FZ - 0.065, FZ + 0.065, green, 0.012)
    plank(B, 0.0, W, 2.5, 2.62, -0.1, 0.02, green, 0.01)
    # The roof: ridge along the lane, clay tiles toward the camera, the boarded gables.
    X0, X1, ZR, YR, ZE, ZBK, YE = -0.18, W + 0.18, 1.05, 3.5, 2.42, -0.32, 2.63
    for ze, s in ((ZE, 1.0), (ZBK, -1.0)):
        d = Vector((0, YE - YR, ze - ZR))
        nrm = Vector((0, abs(d.z), s * abs(d.y))).normalized()
        B.tone(0.1)
        B.obox(Vector((X0 + 0.03, YR, ZR)) - nrm * 0.055, (X1 - X0 - 0.06, 0, 0), d, nrm * 0.045, cream)
        if s > 0:
            B.tiles((X0, YR, ZR), (X1 - X0, 0, 0), d, nrm, tile)
        else:                                                                  # never seen: plain courses
            for k in range(8):
                B.tone(0.25, 0.06)
                B.obox(Vector((X0, YR, ZR)) + d * (k / 8), (X1 - X0, 0, 0), d * (1.25 / 8) + nrm * 0.03, nrm * 0.022, tile)
        for i in range(9):                                                     # rafter ends under the eaves
            x = 0.1 + (W - 0.2) * i / 8
            B.tone(0.12)
            B.beam(Vector((x, YR, ZR)) - nrm * 0.1, Vector((x, YR, ZR)) + d - nrm * 0.1, 0.05, 0.08, green, up=nrm)
    B.plain()
    for i in range(11):                                                        # ridge tiles
        x = X0 + (X1 - X0) * i / 11
        B.tone(0.25, 0.06)
        B.tube((x + 0.01, YR + 0.015, ZR), (x + (X1 - X0) / 11 - 0.01, YR + 0.015, ZR), 0.085, tile, segs=8)
    for x in (0.1, W - 0.1):
        B.tone(0.1)
        for pts in ([(x, 2.67, -0.1), (x, 2.67, FZ + 0.07), (x, YR - 0.06, ZR)],):
            B.poly(pts, cream, both=True)
    for x in (X0, X1):                                                         # bargeboards
        for ze in (ZE, ZBK):
            B.tone(0.12)
            B.beam((x, YR + 0.01, ZR), (x, YE + 0.01, ze), 0.03, 0.13, green, up=(0, 1, 0.01))
    # The fascia over the front, and the stop's plate on it.
    plank(B, X0, X1, 2.46, 2.63, ZE, ZE + 0.03, green, 0.008)
    B.plain()
    B.box(1.5, 2.5, 2.475, 2.615, ZE + 0.03, ZE + 0.04, "country_enamel", 0.004, segs=1)
    B.text("BUS STOP", 0.085, (2.0, 2.503, ZE + 0.043), (1, 0, 0), (0, 1, 0), "country_paint_cream", tracking=1.25)
    return B.finish(dice=0.9) + G.finish()


def lychgate():
    """A lychgate: an oak frame on low stone walls with a stone-slated roof whose gable faces
    the lane, a pair of gates to the churchyard at the back, a lantern under the middle beam.
    The walker passes through it sideways, under the roof."""
    B = CB("Body")
    G = Raw("Grass", "country_grass_foliage")
    oak_, stone, slate = "country_timber", "country_stone", "country_slate"
    W, XS = 4.0, (0.45, 3.55)
    ZB, ZM, ZFP = -0.95, 0.0, 2.15
    for xs in XS:
        B.tone(0.08)
        B.box(xs - 0.22, xs + 0.22, -0.05, 0.85, -1.2, 0.22, stone, 0.035, segs=1)       # dwarf wall
        B.tone(0.1)
        B.box(xs - 0.27, xs + 0.27, 0.85, 0.94, -1.25, 0.27, stone, 0.03, segs=1)        # its coping
        B.tone(0.1)
        B.box(xs - 0.2, xs + 0.2, -0.05, 0.3, ZFP - 0.2, ZFP + 0.2, stone, 0.04, segs=1)  # pad under the front post
        plank(B, xs - 0.1, xs + 0.1, 0.94, 2.55, ZB - 0.1, ZB + 0.1, oak_, 0.02)
        plank(B, xs - 0.1, xs + 0.1, 0.94, 2.55, ZM - 0.1, ZM + 0.1, oak_, 0.02)
        plank(B, xs - 0.1, xs + 0.1, 0.3, 2.55, ZFP - 0.1, ZFP + 0.1, oak_, 0.02)
        plank(B, xs - 0.1, xs + 0.1, 2.55, 2.75, -1.25, 2.38, oak_, 0.02)                # wall plate
        B.tone(0.14)                                                                     # braces back along the wall
        B.brace((xs, 1.85, ZM), (xs, 2.56, ZM - 0.48), (0, 0.04, 0.04), 0.07, 0.1, oak_)
        B.tone(0.14)
        B.brace((xs, 1.85, ZB), (xs, 2.56, ZB + 0.48), (0, 0.04, -0.04), 0.07, 0.1, oak_)
        grass(G, xs, ZFP, 0.28, 0.28, 14, B.rng, h=(0.1, 0.28))
    # The churchyard wall's ends, to meet whatever stands either side.
    for x0, x1 in ((0.0, 0.25), (W - 0.25, W)):
        B.tone(0.1)
        B.box(x0, x1, -0.05, 1.05, -0.42, -0.02, stone, 0.03, segs=1)
    # Tie beams across, each with a brace up from its posts.
    for z in (ZB, ZM, ZFP):
        plank(B, 0.2, W - 0.2, 2.75, 2.95, z - 0.09, z + 0.09, oak_, 0.02)
        if z != ZM:
            for xs, s in ((XS[0], 1), (XS[1], -1)):
                B.tone(0.14)
                B.brace((xs, 1.8, z), (xs + s * 0.7, 2.77, z), (-s * 0.07, 0.07, 0), 0.08, 0.11, oak_)
    # The roof: ridge running back from the lane, a slope to either hand.
    YE, YR, Z0, Z1 = 2.74, 4.84, -1.32, 2.4
    for s in (-1.0, 1.0):
        xe = 2.0 + s * 2.0
        d = Vector((xe - 2.0, YE - YR, 0))
        nrm = Vector((s * abs(d.y), abs(d.x), 0)).normalized()
        B.tone(0.1)
        B.obox(Vector((2.0, YR, Z0 + 0.03)) - nrm * 0.06, (0, 0, Z1 - Z0 - 0.06), d, nrm * 0.05, oak_)
        B.tiles((2.0, YR, Z0), (0, 0, Z1 - Z0), d, nrm, slate, w=0.3, expose=0.25, length=0.38, t=0.028, var=0.3)
        for z in (Z0 + 0.12, ZM, Z1 - 0.22):                                              # rafters
            B.tone(0.14)
            B.beam(Vector((2.0, YR, z)) - nrm * 0.13, Vector((2.0, YR, z)) + d * 0.99 - nrm * 0.13, 0.09, 0.13, oak_, up=nrm)
        B.tone(0.16)                                                                      # bargeboard on the gable
        B.beam(Vector((2.0, YR + 0.03, Z1 + 0.02)), Vector((2.0, YR + 0.03, Z1 + 0.02)) + d * 1.04, 0.035, 0.2, oak_, up=nrm)
    for i in range(9):                                                                    # ridge stones
        z = Z0 + (Z1 - Z0) * i / 9
        B.tone(0.25, 0.05)
        B.tube((2.0, YR + 0.02, z + 0.01), (2.0, YR + 0.02, z + (Z1 - Z0) / 9 - 0.01), 0.1, slate, segs=8)
    # The gable's truss: king post, curved struts, a cross at the peak.
    plank(B, 1.93, 2.07, 2.95, YR - 0.2, ZFP - 0.06, ZFP + 0.06, oak_, 0.015)
    for s in (-1, 1):
        B.tone(0.14)
        B.brace((2.0 + s * 0.08, 3.0, ZFP), (2.0 + s * 1.05, 3.72, ZFP), (s * 0.06, -0.08, 0), 0.07, 0.1, oak_)
    plank(B, 1.965, 2.035, YR + 0.05, YR + 0.75, Z1 - 0.1, Z1 - 0.03, oak_, 0.01)
    plank(B, 1.8, 2.2, YR + 0.48, YR + 0.55, Z1 - 0.1, Z1 - 0.03, oak_, 0.01)
    # The gates to the churchyard, between the back posts.
    for x0, x1, s in ((0.68, 1.98, 1), (2.02, 3.32, -1)):
        hx = x0 if s > 0 else x1                                                          # hung on the outer post
        plank(B, x0, x0 + 0.07, 0.12, 1.12, ZB - 0.03, ZB + 0.03, oak_, 0.008)
        plank(B, x1 - 0.07, x1, 0.12, 1.12, ZB - 0.03, ZB + 0.03, oak_, 0.008)
        for y in (0.25, 0.9):
            plank(B, x0 + 0.07, x1 - 0.07, y, y + 0.07, ZB - 0.025, ZB + 0.025, oak_, 0.008)
        for i in range(8):
            x = x0 + 0.12 + (x1 - x0 - 0.3) * i / 7
            t = (x - hx) / (x1 - x0) * s
            plank(B, x, x + 0.065, 0.16, 1.0 + 0.22 * math.sin(t * math.pi / 2), ZB + 0.025, ZB + 0.045, oak_, 0.0)
        B.plain(0.9)
        B.box(hx - 0.03 if s > 0 else hx - 0.4, hx + 0.4 if s > 0 else hx + 0.03, 0.92, 0.95, ZB + 0.045, ZB + 0.053, "country_iron")
    # The lantern.
    B.plain(0.9)
    B.tube((2.0, 2.75, ZM), (2.0, 2.58, ZM), 0.008, "country_iron", segs=6, caps=False)
    B.lathe([(0.0, 2.58), (0.11, 2.54), (0.1, 2.52)], 2.0, ZM, "country_iron", segs=4, sharp_deg=20.0)
    B.plain()
    B.lathe([(0.075, 2.52), (0.06, 2.3)], 2.0, ZM, "country_lamp_glass", segs=4, sharp_deg=20.0)
    B.plain(0.9)
    B.lathe([(0.07, 2.27), (0.07, 2.3), (0.0, 2.3)], 2.0, ZM, "country_iron", segs=4, sharp_deg=20.0)
    B.marker("Lamp", (2.0, 2.4, ZM))
    return B.finish(dice=1.0) + G.finish()


def telegraph_pole():
    """A tarred pole with two arms across the lane, eight pot insulators and a climber's steps."""
    B = CB("Body")
    G = Raw("Grass", "country_grass_foliage")
    tar, iron = "country_timber_tarred", "country_iron"
    H = 8.2
    prof = [(0.15 - 0.055 * (y / H), y) for y in (-0.1, 0.0, 0.4, 1.0, 2.0, 3.2, 4.5, 5.8, 7.0, H - 0.06)]
    B.tone(0.05)
    B.lathe(prof + [(0.06, H), (0.0, H + 0.05)], 0.0, 0.0, tar, segs=14, sharp_deg=60.0)
    B.plain()
    B.lathe([(0.11, H - 0.02), (0.105, H + 0.03), (0.0, H + 0.1)], 0.0, 0.0, "country_galvanised", segs=14)   # zinc cap
    for y, half, zs in ((7.55, 0.95, (-0.82, -0.36, 0.36, 0.82)), (7.0, 0.72, (-0.6, -0.26, 0.26, 0.6))):
        plank(B, 0.1, 0.19, y - 0.055, y + 0.055, -half, half, tar, 0.012)
        for s in (-1, 1):
            B.plain(0.9)
            B.beam((0.2, y - 0.02, s * half * 0.62), (0.13, y - 0.42, s * 0.03), 0.008, 0.035, iron, up=(1, 0, 0))
        for z in zs:
            B.plain()
            B.tube((0.145, y + 0.05, z), (0.145, y + 0.13, z), 0.012, iron, segs=6, caps=False)
            B.lathe([(0.0, y + 0.1), (0.03, y + 0.1), (0.055, y + 0.115), (0.058, y + 0.15), (0.04, y + 0.16), (0.045, y + 0.185),
                     (0.045, y + 0.215), (0.028, y + 0.235), (0.0, y + 0.24)], 0.145, z, "country_ceramic", segs=10, sharp_deg=70.0)
    B.plain(0.9)
    for i in range(9):                                                        # steps, from above a man's reach
        y, s = 3.2 + 0.42 * i, (1 if i % 2 else -1)
        B.tube((0.0, y, s * 0.08), (0.0, y, s * 0.3), 0.011, iron, segs=6)
    B.plain()
    B.box(-0.05, 0.05, 1.9, 2.02, 0.128, 0.135, "country_paint_white")           # number plate
    grass(G, 0.0, 0.0, 0.2, 0.2, 18, B.rng)
    return B.finish(dice=0.6) + G.finish()


def churn(B, x, z, lean=0.0, lid=True):
    """A ten-gallon milk churn."""
    st = "country_galvanised"
    with xf_push(B, T(x, 0.0, z) @ R("Z", lean)):
        B.tone(0.12, 0.01)
        B.lathe([(0.0, 0.0), (0.185, 0.0), (0.19, 0.02), (0.19, 0.45), (0.175, 0.52), (0.13, 0.6), (0.122, 0.66), (0.145, 0.7),
                 (0.13, 0.7), (0.0, 0.69)], 0.0, 0.0, st, segs=18, sharp_deg=45.0)
        for y in (0.03, 0.44):
            B.tube((0, y, 0), (0, y + 0.018, 0), 0.196, st, segs=18, caps=False)
        if lid:
            B.tone(0.12, 0.01)
            B.lathe([(0.115, 0.69), (0.155, 0.705), (0.16, 0.725), (0.1, 0.745), (0.035, 0.75), (0.03, 0.785), (0.05, 0.795), (0.0, 0.8)],
                    0.0, 0.0, st, segs=18, sharp_deg=45.0)
        for s in (-1, 1):                                                     # the two handles
            pts = [Vector((s * 0.17, 0.52, 0)), Vector((s * 0.215, 0.5, 0)), Vector((s * 0.215, 0.42, 0)), Vector((s * 0.19, 0.4, 0))]
            for a, b in zip(pts, pts[1:]):
                B.tube(a, b, 0.011, st, segs=6)
        B.plain()
        B.box(-0.035, 0.035, 0.3, 0.34, 0.186, 0.193, "country_paint_white")


def milk_churn_stand():
    """The farm's churn stand at the lane side: a sleeper-built platform at lorry-bed height
    with the morning's churns on it and one waiting on the ground."""
    B = CB("Body")
    G = Raw("Grass", "country_grass_foliage")
    tm = "country_timber_tarred"
    for x in (-0.78, 0.78):
        for z in (-0.36, 0.36):
            plank(B, x - 0.08, x + 0.08, -0.05, 0.8, z - 0.08, z + 0.08, tm, 0.015)
            grass(G, x, z, 0.13, 0.13, 9, B.rng, h=(0.1, 0.3))
    for z in (-0.36, 0.36):
        plank(B, -0.9, 0.9, 0.68, 0.8, z - 0.05, z + 0.05, tm, 0.012)
        B.tone(0.14)
        B.beam((-0.76, 0.1, z), (0.76, 0.66, z), 0.04, 0.09, tm, up=(0, 1, 0), bevel=0.006)
    for i in range(5):
        z = -0.47 + i * 0.19
        plank(B, -0.92, 0.92, 0.8, 0.86, z, z + 0.18, "country_timber", 0.01)
    with xf_push(B, T(0, 0.86, 0)):
        churn(B, -0.58, -0.08)
        churn(B, -0.14, 0.1)
        churn(B, 0.32, -0.12, lid=False)
    with xf_push(B, T(0.24, 0.86, 0.22) @ R("X", 8.0) @ R("Z", -4.0)):                   # its lid, set down beside it
        B.tone(0.12, 0.01)
        B.lathe([(0.0, 0.0), (0.115, 0.0), (0.155, 0.015), (0.16, 0.035), (0.1, 0.055), (0.035, 0.06), (0.03, 0.095), (0.05, 0.105), (0.0, 0.11)],
                0.0, 0.0, "country_galvanised", segs=18, sharp_deg=45.0)
    churn(B, 0.62, 0.72, lean=2.0)
    return B.finish(dice=0.3) + G.finish()


def milestone():
    """A roadside milestone: a round-headed slab, whitened on its face, leaning a little."""
    B = CB("Body")
    G = Raw("Grass", "country_grass_foliage")
    w, h, d = 0.23, 0.56, 0.2
    with xf_push(B, R("Z", 3.5) @ R("X", -4.0)):
        pts = [(-w, -0.2), (w, -0.2), (w, h)] + [(w * math.cos(a), h + w * math.sin(a)) for a in [math.pi * i / 10 for i in range(1, 10)]] + [(-w, h)]
        B.prism_z(pts, -d / 2, d / 2, "country_stone", bevel=0.02)
        B.plain()
        face = [(-w + 0.05, 0.1), (w - 0.05, 0.1), (w - 0.05, h)] + [((w - 0.05) * math.cos(a), h + (w - 0.05) * math.sin(a)) for a in
                                                                    [math.pi * i / 10 for i in range(1, 10)]] + [(-w + 0.05, h)]
        B.poly_z(face, d / 2 + 0.003, "country_paint_white")
        ink, zt = "country_paint_black", d / 2 + 0.006
        B.text("TOWN", 0.085, (0.0, 0.56, zt), (1, 0, 0), (0, 1, 0), ink)
        B.text("7", 0.15, (0.0, 0.36, zt), (1, 0, 0), (0, 1, 0), ink)
        B.text("MILES", 0.07, (0.0, 0.24, zt), (1, 0, 0), (0, 1, 0), ink)
    grass(G, 0.0, 0.0, 0.3, 0.18, 34, B.rng, h=(0.1, 0.34))
    return B.finish(dice=0.12) + G.finish()


def signpost():
    """A cast-iron fingerpost: black foot, white column, a ball finial, two fingers along the
    lane (read from the lane) and one pointing off across the fields."""
    B = CB("Body")
    G = Raw("Grass", "country_grass_foliage")
    white, black = "country_paint_white", "country_paint_black"
    B.lathe([(0.12, -0.05), (0.12, 0.05), (0.095, 0.1), (0.085, 0.55), (0.1, 0.58), (0.1, 0.62)], 0.0, 0.0, black, segs=12, sharp_deg=40.0)
    B.lathe([(0.075, 0.62), (0.058, 2.2), (0.05, 2.86), (0.075, 2.88), (0.075, 2.92), (0.04, 2.95), (0.03, 2.99), (0.065, 3.03),
             (0.085, 3.09), (0.065, 3.15), (0.02, 3.18), (0.0, 3.26)], 0.0, 0.0, white, segs=12, sharp_deg=40.0)
    for y in (0.9, 1.5):
        B.tube((0, y, 0), (0, y + 0.06, 0), 0.078 - 0.01 * (y - 0.6), black, segs=12, caps=False)

    def finger(y, yaw, text, length=1.05, st=1):
        with xf_push(B, R("Y", yaw)):
            hh, t = 0.085, 0.02
            pts = [(0.0, y - hh), (length - 0.1, y - hh), (length, y), (length - 0.1, y + hh), (0.0, y + hh)]
            B.plain()
            B.prism_z(pts, -t, t, white, bevel=0.006)
            B.tube((0, y - hh - 0.01, 0), (0, y + hh + 0.01, 0), 0.07, white, segs=12)           # its collar on the post
            for side in (1, -1):                                                              # a raised black edge
                zz = side * (t + 0.002)
                for (a, b) in ((pts[0], pts[1]), (pts[1], pts[2]), (pts[2], pts[3]), (pts[3], pts[4])):
                    B.beam((a[0], a[1], zz), (b[0], b[1], zz), 0.004, 0.012, black, up=(0, 0, 1))
            # the name, on the face the lane sees (st: which of the finger's faces that is)
            B.text(text, 0.085, (0.07 + (length - 0.17) / 2, y - 0.043, st * (t + 0.003)), (st, 0, 0), (0, 1, 0), black)
    finger(2.66, 0.0, "COUNTY ROAD 2")
    finger(2.44, 180.0, "TOWN 7", length=0.85, st=-1)
    finger(2.22, 90.0, "CHURCH", length=0.8)
    grass(G, 0.0, 0.0, 0.2, 0.2, 20, B.rng)
    return B.finish(dice=0.3) + G.finish()


MODELS = {
    "oak_a": lambda: oak("oak_a", 11, (0.0, 7.0, 0.4), (5.0, 3.6, 3.4), 26, (0.12, 0.0), 6),
    "oak_b": lambda: oak("oak_b", 23, (0.35, 7.4, 0.4), (4.5, 4.0, 3.4), 26, (-0.3, -0.05), 5, stub=True),
    "street_tree_a": lambda: oak("street_tree_a", 5, (0.0, 6.85, -1.4), (4.5, 3.5, 3.0), 26, (0.1, -0.1), 6, kind=PLANE),
    "street_tree_b": lambda: oak("street_tree_b", 41, (0.2, 7.3, -1.4), (4.3, 3.5, 3.0), 24, (0.25, -0.15), 5, kind=GUM),
    "hedge_4m": hedge,
    "gate": gate,
    "dutch_barn": dutch_barn,
    "bus_shelter": bus_shelter,
    "lychgate": lychgate,
    "telegraph_pole": telegraph_pole,
    "hay_bales": hay_bales,
    "milk_churn_stand": milk_churn_stand,
    "milestone": milestone,
    "signpost": signpost,
}


# ------------------------------------------------------------------------------------------------
# export, measure, preview
# ------------------------------------------------------------------------------------------------

def export_glb(objects, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
        export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_cameras=False, export_lights=False,
        export_animations=False, export_extras=False, export_loglevel=-1)


def measure(objs):
    """Triangles, and the box round the model in game coordinates."""
    tris, lo, hi = 0, [1e9] * 3, [-1e9] * 3
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
        for v in o.data.vertices:
            g = (v.co.x, v.co.z, -v.co.y)
            pts.append((g, o.name))
            for i in range(3):
                lo[i], hi[i] = min(lo[i], g[i]), max(hi[i], g[i])
    return tris, lo, hi, pts


STANDS_AT_Z = {"street_tree_a": 2.9, "street_tree_b": 2.9}


def preview(name, objs, lo, hi, folder):
    """Three Eevee views under a wet sky with a break of sun in it."""
    os.makedirs(folder, exist_ok=True)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.view_settings.view_transform = "Standard"
    extra = []
    for m in bpy.data.materials:                      # show the vertex paint
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        if bsdf and not bsdf.inputs["Base Color"].is_linked:
            a = nt.nodes.new("ShaderNodeVertexColor")
            a.layer_name = "Col"
            nt.links.new(a.outputs["Color"], bsdf.inputs["Base Color"])
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.42, 0.5, 0.6, 1.0)
    bg.inputs[1].default_value = 0.7
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.color = (1.0, 0.93, 0.8)
    sun.data.angle = math.radians(6.0)
    sun.rotation_euler = (Vector(gv((-0.5, -0.75, 0.55)))).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(sun)
    extra.append(sun)

    def flat(nm, col):
        m = bpy.data.materials.new(nm)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*col, 1.0)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
        return m
    gm, fm = flat("pv_ground", lin((0.22, 0.31, 0.15))), flat("pv_figure", lin((0.2, 0.2, 0.24)))
    me = bpy.data.meshes.new("pv_ground")
    me.from_pydata([gv(p) for p in ((-60, 0, -60), (60, 0, -60), (60, 0, 60), (-60, 0, 60))], [], [(3, 2, 1, 0)])
    me.materials.append(gm)
    ground = bpy.data.objects.new("pv_ground", me)
    sc.collection.objects.link(ground)
    extra.append(ground)
    cx = 0.5 * (lo[0] + hi[0])
    fig = CB("pv_fig")                                # a walker-sized figure with his umbrella up
    fig.mats, fig_x, pz = [], cx - 1.0, STANDS_AT_Z.get(name, 0.0)
    kitlib.get_material = lambda n: fm
    fig.lathe([(0.0, 0.0), (0.17, 0.0), (0.2, 0.9), (0.22, 1.45), (0.1, 1.55), (0.11, 1.7), (0.0, 1.78)], fig_x, 1.6 - pz, "pv", segs=12)
    fig.lathe([(0.56, 2.0), (0.3, 2.17), (0.0, 2.22)], fig_x + 0.12, 1.6 - pz, "pv", segs=16)
    fobj = Builder.finish(fig)
    kitlib.get_material = get_material
    extra += fobj
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    extra.append(cam)
    c = Vector((cx, 0.5 * (lo[1] + hi[1]), 0.5 * (lo[2] + hi[2])))
    size = max(hi[0] - lo[0], (hi[1] - lo[1]) * 16 / 9, 1.2)
    diag = (Vector(hi) - Vector(lo)).length

    def shoot(tag, pos, look, ortho=None, fov=None, show_fig=False):
        for o in fobj:
            o.hide_render = not show_fig
        cam.data.type = "ORTHO" if ortho else "PERSP"
        if ortho:
            cam.data.sensor_fit = "HORIZONTAL"
            cam.data.ortho_scale = ortho
        else:
            cam.data.sensor_fit = "VERTICAL"
            cam.data.angle_y = math.radians(fov)
        cam.location = gv(pos)
        cam.rotation_euler = (Vector(gv(look)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(folder, "%s_%s.png" % (name, tag))
        bpy.ops.render.render(write_still=True)
    # as the game sees it: 7.2 m out from the walking line, 2.6 m up, pitched down 3 degrees
    shoot("game", (cx, 2.6, 8.8 - pz), (cx, 2.6 - 8.8 * math.tan(math.radians(3.0)), -pz), fov=50.0, show_fig=True)
    shoot("side", (c.x, c.y, 60.0), (c.x, c.y, 0.0), ortho=size * 1.12)
    dist = diag * 1.75 + 0.6
    shoot("three", (c.x + 0.6 * dist, c.y + 0.28 * dist, c.z + 0.74 * dist), c, fov=38.0)
    for o in extra:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.worlds.remove(world)


def check(name, pts, lo, hi, tris):
    """What the game relies on (docs/CONTRACTS.md §10): fail loudly if a model breaks it."""
    bad = []
    if tris > 15000:
        bad.append("%d triangles" % tris)
    if name.startswith("oak"):
        low = min((g[1] for g, _ in pts if 0.6 <= g[2] <= 3.6 and g[1] > 0.5), default=9.0)
        if low < 3.4:
            bad.append("something hangs at %.2f m over the walking line" % low)
        if not (9.0 <= hi[0] - lo[0] <= 11.0 and lo[2] >= -3.2 and hi[2] <= 3.9 and 9.0 <= hi[1] <= 12.0):
            bad.append("crown out of bounds")
    if name.startswith("street_tree"):       # it stands at z = 2.9: the walking line is z -2.3..0.7 from its foot
        low = min((g[1] for g, o in pts if -2.3 <= g[2] <= 0.7 and (o == "Foliage" or math.hypot(g[0], g[2]) > 0.9)), default=9.0)
        if low < 3.4:
            bad.append("something hangs at %.2f m over the walking line" % low)
        if not (8.0 <= hi[0] - lo[0] <= 10.0 and lo[2] >= -4.5 and hi[2] <= 1.7 and 9.0 <= hi[1] <= 11.0):
            bad.append("crown out of bounds")
    if name == "hedge_4m" and not (lo[2] >= -1.001 and hi[2] <= 0.101 and 1.6 <= hi[1] <= 2.0):
        bad.append("hedge out of bounds")
    clear = {"bus_shelter": (2.45, 0.9, 2.1), "lychgate": (2.5, 0.9, 2.0), "dutch_barn": (4.2, 0.3, 2.25)}
    if name in clear:
        h, z0, z1 = clear[name]
        low = [g for g, o in pts if o == "Body" and z0 <= g[2] <= z1 and 0.5 < g[1] < h]
        if low:
            bad.append("%d points below %.2f m over the walking line, e.g. %s" % (len(low), h, tuple(round(v, 2) for v in low[0])))
    return bad


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    folder = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else list(MODELS)
    kitlib.reset_scene()
    failed = False
    for name in only:
        objs = MODELS[name]()
        tris, lo, hi, pts = measure(objs)
        export_glb(objs, os.path.join(OUT, name + ".glb"))
        bad = check(name, pts, lo, hi, tris)
        failed = failed or bool(bad)
        print("country %-17s tris %6d  x %6.2f..%5.2f  y %5.2f..%5.2f  z %5.2f..%5.2f  %s" % (
            name, tris, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], ("BAD: " + "; ".join(bad)) if bad else "ok"))
        if folder:
            preview(name, objs, lo, hi, folder)
        kitlib.clear_objects()
        for m in list(bpy.data.materials):
            bpy.data.materials.remove(m)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
