"""Geometry helpers for the Don't Get Wet environment kit (run inside Blender 5.x).

All helpers take GAME coordinates (Godot, Y-up):
    +X = walking direction, +Y = up, +Z = toward the camera / road.
They are converted to Blender coordinates (Z-up) as (x, -z, y); the glTF exporter (+Y up) converts
back, so a point written as game (x, y, z) arrives in Godot at exactly (x, y, z).

A Builder accumulates one module into a single bmesh with several material slots, so every
exported module is one mesh (one draw call per material) plus optional marker empties
(e.g. "omni_warm" -> turned into an OmniLight3D by assets/buildings/kit_import.gd).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import materials_def  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def gv(p):
    """game (x, y, z) -> blender Vector."""
    return Vector((p[0], -p[2], p[1]))


# ------------------------------------------------------------------------------------------------
# scene / materials / export
# ------------------------------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def clear_objects():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def get_material(name):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    if name not in materials_def.MATS:
        raise KeyError("material %s missing from materials_def.MATS" % name)
    d = materials_def.MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    c = materials_def.preview(name)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1.0)
        bsdf.inputs["Roughness"].default_value = float(d.get("rough", 0.7)) if d["kind"] != "pbr" else 0.8
        bsdf.inputs["Metallic"].default_value = float(d.get("metal", 0.0))
        if "emit" in d:
            e = d["emit"]
            bsdf.inputs["Emission Color"].default_value = (e[0], e[1], e[2], 1.0)
            bsdf.inputs["Emission Strength"].default_value = e[3]
        if d["kind"] == "glass":
            bsdf.inputs["Alpha"].default_value = d.get("alpha", 0.5)
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    return m


def export_glb(objects, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=False,
        export_loglevel=-1,
    )


# ------------------------------------------------------------------------------------------------
# Builder
# ------------------------------------------------------------------------------------------------

class Builder:
    def __init__(self, name, seed=None):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.uvdone = self.bm.faces.layers.int.new("uvdone")
        self.mats = []
        self.markers = []  # (name, game pos)
        self.xf = Matrix.Identity(4)  # extra transform in GAME coordinates
        self.rng = random.Random(seed if seed is not None else name)

    # -- low level ------------------------------------------------------------------------
    def mi(self, mat):
        if mat not in self.mats:
            get_material(mat)
            self.mats.append(mat)
        return self.mats.index(mat)

    def v(self, p):
        q = self.xf @ Vector((p[0], p[1], p[2]))
        return self.bm.verts.new(gv(q))

    def face(self, verts, mat, smooth=False):
        f = self.bm.faces.new(verts)
        f.material_index = self.mi(mat)
        f.smooth = smooth
        return f

    def mark(self):
        """Index to pass to new_faces() later."""
        return len(self.bm.faces)

    def new_faces(self, mark):
        self.bm.faces.ensure_lookup_table()
        return [self.bm.faces[i] for i in range(mark, len(self.bm.faces))]

    def jitter(self, faces, amount, rng=None):
        rng = rng or self.rng
        vs = {v for f in faces for v in f.verts}
        for v in vs:
            v.co.x += rng.uniform(-amount, amount)
            v.co.y += rng.uniform(-amount, amount)
            v.co.z += rng.uniform(-amount, amount)

    def marker(self, name, p):
        q = self.xf @ Vector(p)
        self.markers.append((name, q))

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

    # -- primitives -------------------------------------------------------------------------
    def box(self, x0, x1, y0, y1, z0, z1, mat, bevel=0.0, segs=2):
        if x1 < x0: x0, x1 = x1, x0
        if y1 < y0: y0, y1 = y1, y0
        if z1 < z0: z0, z1 = z1, z0
        b = min(bevel, 0.45 * min(x1 - x0, y1 - y0, z1 - z0))
        P = [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
             (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)]
        V = [self.v(p) for p in P]
        idx = [(0, 1, 2, 3), (5, 4, 7, 6), (4, 0, 3, 7), (1, 5, 6, 2), (3, 2, 6, 7), (4, 5, 1, 0)]
        faces = [self.face([V[i] for i in q], mat) for q in idx]
        if b > 0.0005:
            self._bevel(faces, b, segs, mat)
        return faces

    def quad(self, p0, p1, p2, p3, mat, uv=None, smooth=False):
        """Quad from 4 game points (counter-clockwise seen from the front). uv: 4 (u,v) tuples."""
        V = [self.v(p) for p in (p0, p1, p2, p3)]
        f = self.face(V, mat, smooth)
        if uv is not None:
            for loop, t in zip(f.loops, uv):
                loop[self.uv].uv = t
            f[self.uvdone] = 1
        return f

    def rect_z(self, x0, x1, y0, y1, z, mat, uv=(0, 0, 1, 1), facing=1):
        """Axis aligned rectangle in a Z plane facing +Z (facing=1) or -Z. uv = (u0, v0, u1, v1)."""
        u0, v0, u1, v1 = uv
        if facing > 0:
            return self.quad((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z), mat,
                             [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
        return self.quad((x1, y0, z), (x0, y0, z), (x0, y1, z), (x1, y1, z), mat,
                         [(u1, v0), (u0, v0), (u0, v1), (u1, v1)])

    def rect_x(self, z0, z1, y0, y1, x, mat, facing=1, uv=None):
        """Rectangle in an X plane. facing=+1 -> normal +X."""
        if facing > 0:
            pts = [(x, y0, z1), (x, y0, z0), (x, y1, z0), (x, y1, z1)]
        else:
            pts = [(x, y0, z0), (x, y0, z1), (x, y1, z1), (x, y1, z0)]
        return self.quad(*pts, mat, uv=uv)

    def rect_y(self, x0, x1, z0, z1, y, mat, facing=1, uv=None):
        if facing > 0:
            pts = [(x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0)]
        else:
            pts = [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
        return self.quad(*pts, mat, uv=uv)

    def tube(self, p0, p1, r0, mat, r1=None, segs=16, caps=True, bevel=0.0, smooth=True, ang0=0.0):
        """Cylinder / cone between two game points."""
        r1 = r0 if r1 is None else r1
        a = Vector(p0)
        b = Vector(p1)
        axis = (b - a)
        L = axis.length
        axis.normalize()
        ref = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))
        u = axis.cross(ref).normalized()
        w = axis.cross(u).normalized()
        ring0, ring1 = [], []
        for i in range(segs):
            t = ang0 + 2 * math.pi * i / segs
            d = u * math.cos(t) + w * math.sin(t)
            ring0.append(self.v(a + d * r0))
            ring1.append(self.v(b + d * r1))
        faces = []
        for i in range(segs):
            j = (i + 1) % segs
            faces.append(self.face([ring0[i], ring0[j], ring1[j], ring1[i]], mat, smooth))
        caps_f = []
        if caps:
            caps_f.append(self.face(list(reversed(ring0)), mat))
            caps_f.append(self.face(ring1, mat))
        # fix orientation: make sure side normals point outwards
        self._orient_outward(faces + caps_f, (a + b) * 0.5)
        if bevel > 0 and caps:
            self._bevel(caps_f, bevel, 2, mat)
        return faces + caps_f

    def _orient_outward(self, faces, center_game):
        c = gv(self.xf @ Vector(center_game))
        flip = []
        for f in faces:
            f.normal_update()
            if f.normal.dot(f.calc_center_median() - c) < 0:
                flip.append(f)
        for f in flip:
            f.normal_flip()

    def lathe(self, profile, cx, cz, mat, segs=24, y_axis=True, smooth=True, sharp_deg=50.0, base=(0, 0, 0)):
        """Revolve [(r, y), ...] (bottom to top) around a vertical axis at (cx, cz).
        Points with r == 0 collapse to a single pole vertex."""
        rings = []
        for (r, y) in profile:
            if r <= 1e-5:
                rings.append([self.v((cx, y, cz))])
            else:
                ring = []
                for i in range(segs):
                    t = 2 * math.pi * i / segs
                    ring.append(self.v((cx + r * math.cos(t), y, cz - r * math.sin(t))))
                rings.append(ring)
        faces = []
        for k in range(len(rings) - 1):
            A, B = rings[k], rings[k + 1]
            for i in range(segs):
                j = (i + 1) % segs
                if len(A) == 1 and len(B) == 1:
                    continue
                if len(A) == 1:
                    vs = [A[0], B[i], B[j]]
                elif len(B) == 1:
                    vs = [A[i], A[j], B[0]]
                else:
                    vs = [A[i], A[j], B[j], B[i]]
                f = self.face(vs, mat, smooth)
                faces.append(f)
        # caps for open ends
        if len(rings[0]) > 1:
            faces.append(self.face(list(reversed(rings[0])), mat))
        if len(rings[-1]) > 1:
            faces.append(self.face(rings[-1], mat))
        self.mark_sharp(faces, sharp_deg)
        return faces

    def sweep(self, profile, x0, x1, mat, closed=True, smooth=True, sharp_deg=40.0, caps=True):
        """Extrude a 2D profile [(z, y), ...] along X from x0 to x1 (mouldings, sills, cornices).
        Profile should run so the outside is on the left when walking the points (any winding is
        fixed afterwards)."""
        if closed:
            area = 0.0
            for i in range(len(profile)):
                z1, y1 = profile[i]
                z2, y2 = profile[(i + 1) % len(profile)]
                area += z1 * y2 - z2 * y1
            if area < 0:
                profile = list(reversed(profile))
        A = [self.v((x0, y, z)) for (z, y) in profile]
        B = [self.v((x1, y, z)) for (z, y) in profile]
        n = len(profile)
        faces = []
        rng = range(n) if closed else range(n - 1)
        for i in rng:
            j = (i + 1) % n
            faces.append(self.face([A[i], B[i], B[j], A[j]], mat, smooth))
        capf = []
        if closed and caps:
            capf.append(self.face(A, mat))
            capf.append(self.face(list(reversed(B)), mat))
        self.mark_sharp(faces, sharp_deg)
        return faces + capf

    def mark_sharp(self, faces, deg):
        fs = set(faces)
        lim = math.radians(deg)
        for f in faces:
            f.normal_update()
        for f in faces:
            for e in f.edges:
                lf = [g for g in e.link_faces if g in fs]
                if len(lf) == 2:
                    if lf[0].normal.angle(lf[1].normal, 0.0) > lim:
                        e.smooth = False

    def poly_z(self, pts, z, mat, facing=1, uvrect=None):
        """Flat polygon in a Z plane from [(x, y), ...]."""
        P = pts if facing > 0 else list(reversed(pts))
        V = [self.v((x, y, z)) for (x, y) in P]
        f = self.face(V, mat)
        if uvrect:
            x0, y0, x1, y1 = uvrect
            for loop, (x, y) in zip(f.loops, P):
                loop[self.uv].uv = ((x - x0) / (x1 - x0), (y - y0) / (y1 - y0))
            f[self.uvdone] = 1
        return f

    def prism_z(self, pts, z0, z1, mat, bevel=0.0):
        """Extrude polygon [(x, y), ...] (CCW seen from +Z) between z0 (back) and z1 (front)."""
        F = [self.v((x, y, z1)) for (x, y) in pts]
        Bk = [self.v((x, y, z0)) for (x, y) in pts]
        faces = [self.face(F, mat), self.face(list(reversed(Bk)), mat)]
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.face([Bk[i], Bk[j], F[j], F[i]], mat))
        if bevel > 0:
            self._bevel(faces, bevel, 1, mat)
        return faces

    # -- composite helpers -----------------------------------------------------------------
    def wall(self, x0, x1, y0, y1, z, openings, mat, depth=0.3, back=False):
        """Facade plane at z (facing +Z) from x0..x1, y0..y1 with rectangular openings
        [(ox0, ox1, oy0, oy1)], each with reveals going `depth` into -Z."""
        xs = sorted({x0, x1} | {o[0] for o in openings} | {o[1] for o in openings})
        ys = sorted({y0, y1} | {o[2] for o in openings} | {o[3] for o in openings})
        xs = [x for x in xs if x0 <= x <= x1]
        ys = [y for y in ys if y0 <= y <= y1]
        grid = {}

        def gvtx(i, j):
            k = (i, j)
            if k not in grid:
                grid[k] = self.v((xs[i], ys[j], z))
            return grid[k]

        def inside(cx, cy):
            for (ox0, ox1, oy0, oy1) in openings:
                if ox0 < cx < ox1 and oy0 < cy < oy1:
                    return True
            return False

        for i in range(len(xs) - 1):
            for j in range(len(ys) - 1):
                cx = 0.5 * (xs[i] + xs[i + 1])
                cy = 0.5 * (ys[j] + ys[j + 1])
                if inside(cx, cy):
                    continue
                self.face([gvtx(i, j), gvtx(i + 1, j), gvtx(i + 1, j + 1), gvtx(i, j + 1)], mat)
        zb = z - depth
        for (ox0, ox1, oy0, oy1) in openings:
            if oy0 > y0 + 1e-4:  # bottom reveal (sill side)
                self.rect_y(ox0, ox1, zb, z, oy0, mat, facing=1)
            if oy1 < y1 - 1e-4:
                self.rect_y(ox0, ox1, zb, z, oy1, mat, facing=-1)
            self.rect_x(zb, z, oy0, oy1, ox0, mat, facing=1)
            self.rect_x(zb, z, oy0, oy1, ox1, mat, facing=-1)
        if back:
            self.rect_z(x0, x1, y0, y1, zb, mat, facing=-1)

    def shattered_pane(self, x0, x1, y0, y1, z, mat, hole=0.6):
        """Glass pane with a jagged hole (broken window)."""
        rng = self.rng
        cx = x0 + (x1 - x0) * rng.uniform(0.35, 0.65)
        cy = y0 + (y1 - y0) * rng.uniform(0.3, 0.7)
        n = 11
        # outer ring along the rectangle perimeter
        outer = []
        per = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        for k in range(n):
            t = k / n * 4.0
            e = int(t)
            f = t - e
            a = per[e]
            b = per[(e + 1) % 4]
            outer.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
        inner = []
        for (ox, oy) in outer:
            s = hole * rng.uniform(0.35, 1.0)
            inner.append((cx + (ox - cx) * s, cy + (oy - cy) * s))
        for k in range(n):
            j = (k + 1) % n
            pts = [outer[k], outer[j], inner[j], inner[k]]
            self.poly_z(pts, z, mat)

    def finish(self, sharp_angle=None):
        """Box-project UVs (metres) for faces that do not have explicit UVs; return the object."""
        bm = self.bm
        bm.normal_update()
        inv = self.xf.inverted()  # (not used for UVs: UVs are world-ish so textures line up)
        for f in bm.faces:
            if f[self.uvdone]:
                continue
            n = f.normal  # blender coords
            ax = max(range(3), key=lambda i: abs(n[i]))
            for loop in f.loops:
                co = loop.vert.co
                gx, gy, gz = co.x, co.z, -co.y
                if ax == 2:  # blender Z = game Y (horizontal faces)
                    loop[self.uv].uv = (gx, -gz)
                elif ax == 1:  # blender Y = game -Z (facade faces)
                    s = -1 if n[1] > 0 else 1  # front faces (+Z game) => -Y blender
                    loop[self.uv].uv = (gx * s, gy)
                else:  # side faces (game X)
                    loop[self.uv].uv = (-gz if n[0] > 0 else gz, gy)
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        for m in self.mats:
            me.materials.append(get_material(m))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        objs = [ob]
        for (nm, p) in self.markers:
            e = bpy.data.objects.new(nm, None)
            e.location = gv(p)
            e.empty_display_size = 0.2
            bpy.context.scene.collection.objects.link(e)
            objs.append(e)
        self.tris = sum(len(p.vertices) - 2 for p in me.polygons)
        return objs


class xf_push:
    """Context manager: temporarily post-multiply the builder transform (game coords)."""

    def __init__(self, B, M):
        self.B = B
        self.M = M

    def __enter__(self):
        self.old = self.B.xf
        self.B.xf = self.old @ self.M
        return self.B

    def __exit__(self, *a):
        self.B.xf = self.old


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def R(axis, deg):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def S(x, y, z):
    m = Matrix.Identity(4)
    m[0][0], m[1][1], m[2][2] = x, y, z
    return m


def side_xf():
    """Transform for `side` modules: build them like a facade (x along the wall, face toward +Z)
    and this rotates them so the face lies in the plane x = 0 facing +X, spanning z in [-w, 0]."""
    # game = (fz, fy, -fx)
    return Matrix(((0, 0, 1, 0), (0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 0, 1)))


def build_and_export(builder, path):
    objs = builder.finish()
    export_glb(objs, path)
    tris = builder.tris
    clear_objects()
    return tris
