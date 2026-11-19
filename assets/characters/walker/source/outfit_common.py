# Shared helpers for the outfits built on the walker's own model (build_raincoat.py, build_slicker.py):
# skinned added meshes and the walker's suit texture, dyed.
import bpy, bmesh, math
import numpy as np


def load_walker(src):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=src)
    return next(o for o in bpy.data.objects if o.type == 'ARMATURE')


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name, srgb, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*to_linear(srgb), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    m.use_backface_culling = True
    return m


def skin(obj, rig, groups, mats):
    obj.parent = rig
    for name, ws in groups.items():
        g = obj.vertex_groups.new(name=name)
        for i, w in enumerate(ws):
            if w > 1e-4:
                g.add([i], w, 'REPLACE')
    for m in mats:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.use_smooth = True


def solidify(obj, rig, thickness):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    sol = obj.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = thickness
    sol.offset = -1.0
    sol.use_rim = True
    bpy.ops.object.modifier_apply(modifier=sol.name)
    # Closed now, so the recalculated normals all face out (the culled back faces are the inside).
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.modifiers.new("Armature", 'ARMATURE').object = rig


def mesh_object(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


# --- Coat skirt ------------------------------------------------------------------------------------
# Blender frame of the MPFB rig: +Z up, the character faces -Y, his left is +X.
def coat_skirt(rig, name, profile, mat, slit_top, centre_y=-0.02, segments=40, ring_step=0.035,
               leg_top=0.97, leg_full=0.72, leg_max=0.95, side_blend=0.12):
    """A flared tube through the rings `profile` [(z, half width, front depth, back depth)], top down,
    open at the front below `slit_top`, weighted to the pelvis at the top and to the thighs further
    down. Vertex 0 and `segments` of each ring are the two edges of the front opening."""
    def ring_at(z):
        for (z0, *a), (z1, *b) in zip(profile, profile[1:]):
            if z1 <= z <= z0:
                t = (z0 - z) / (z0 - z1)
                return [p + (q - p) * t for p, q in zip(a, b)]
        return profile[-1][1:] if z < profile[-1][0] else profile[0][1:]

    top, hem = profile[0][0], profile[-1][0]
    rings = int(round((top - hem) / ring_step))
    bm = bmesh.new()
    grid = []
    weights = []
    for r in range(rings + 1):
        z = top - (top - hem) * r / rings
        half, front, back = ring_at(z)
        row = []
        for j in range(segments + 1):
            phi = math.tau * j / segments
            x = half * math.sin(phi)
            y = centre_y - (front if math.cos(phi) > 0.0 else back) * math.cos(phi)
            left = smoothstep(-side_blend, side_blend, x)
            if math.cos(phi) > 0.0:
                # Below the slit each front panel follows only its own thigh.
                own = 1.0 if j < segments / 2 else 0.0
                k = 1.0 - smoothstep(slit_top, slit_top + 0.06, z)
                left += (own - left) * k
            leg = leg_max * smoothstep(leg_top, leg_full, z)
            weights.append((1.0 - leg, leg * left, leg * (1.0 - left)))
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for r in range(rings):
        for j in range(segments):
            bm.faces.new((grid[r][j], grid[r + 1][j], grid[r + 1][j + 1], grid[r][j + 1]))
    coat = mesh_object(name, bm)
    skin(coat, rig, {"pelvis": [w[0] for w in weights], "thigh_l": [w[1] for w in weights],
                     "thigh_r": [w[2] for w in weights]}, [mat])
    solidify(coat, rig, 0.012)
    return coat


# --- Suit texture ----------------------------------------------------------------------------------
def suit_mesh():
    return next(o for o in bpy.data.objects if o.type == 'MESH' and "elegantsuit" in o.name.lower())


def suit_faces():
    """(UV island id, bind-pose height, UV triangles) for every face of the suit."""
    suit = suit_mesh()
    bm = bmesh.new()
    bm.from_mesh(suit.data)
    uvl = bm.loops.layers.uv.active
    parent = list(range(len(bm.faces)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def uv_of(f, vert):
        return next(tuple(l[uvl].uv) for l in f.loops if l.vert == vert)

    for e in bm.edges:
        if len(e.link_faces) == 2:
            f0, f1 = e.link_faces
            if all(np.allclose(uv_of(f0, v), uv_of(f1, v), atol=1e-5) for v in e.verts):
                parent[find(f0.index)] = find(f1.index)
    faces = []
    for f in bm.faces:
        uvs = [tuple(l[uvl].uv) for l in f.loops]
        faces.append((find(f.index), (suit.matrix_world @ f.calc_center_median()).z,
                      [(uvs[0], uvs[i], uvs[i + 1]) for i in range(1, len(uvs) - 1)]))
    bm.free()
    return faces


def raster(weighted_tris, shape):
    """Per-pixel maximum of the weights of the UV triangles covering it (row 0 = v 0, as in pixels)."""
    hh, ww = shape
    mask = np.zeros(shape, dtype=np.float32)
    for tri, wgt in weighted_tris:
        p = np.array([(t[0] * ww - 0.5, t[1] * hh - 0.5) for t in tri])
        x0, y0 = np.floor(p.min(axis=0)).astype(int)
        x1, y1 = np.ceil(p.max(axis=0)).astype(int)
        xs, ys = np.meshgrid(np.arange(max(x0, 0), min(x1, ww - 1) + 1), np.arange(max(y0, 0), min(y1, hh - 1) + 1))
        d = (p[1, 1] - p[2, 1]) * (p[0, 0] - p[2, 0]) + (p[2, 0] - p[1, 0]) * (p[0, 1] - p[2, 1])
        if abs(d) < 1e-9:
            continue
        a = ((p[1, 1] - p[2, 1]) * (xs - p[2, 0]) + (p[2, 0] - p[1, 0]) * (ys - p[2, 1])) / d
        b = ((p[2, 1] - p[0, 1]) * (xs - p[2, 0]) + (p[0, 0] - p[2, 0]) * (ys - p[2, 1])) / d
        inside = (a >= -0.01) & (b >= -0.01) & (a + b <= 1.01)
        mask[ys[inside], xs[inside]] = np.maximum(mask[ys[inside], xs[inside]], wgt)
    return mask


class SuitTexture:
    """The walker's suit texture as linear floats, row 0 the bottom of the image, with the masks the
    dyes need: `trousers`, `lum`, the mostly white islands (`bright`: shirt front and tie, cuffs) and
    `covered` (trouser pixels the coat skirt always hides, above `covered_from`)."""

    def __init__(self, covered_from):
        self.img = next(i for i in bpy.data.images if "elegantsuit" in i.name.lower())
        w, h = self.img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        self.img.pixels.foreach_get(px)
        self.px = px.reshape(h, w, 4)
        u = (np.arange(w) + 0.5) / w
        v = 1.0 - (np.arange(h) + 0.5) / h  # glTF v: 0 at the top
        # The trouser UV islands are the only ones below v 0.468 left of u 0.75 (sleeves are to the right).
        self.trousers = (v[:, None] > 0.468) & (u[None, :] < 0.75)
        self.lum = self.px[..., :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
        faces = suit_faces()
        islands = {}
        for isl, z, tris in faces:
            islands.setdefault(isl, []).extend(tris)
        lum = self.lum
        bright = [(tri, 1.0) for tris in islands.values()
                  if np.mean([lum[min(int(sum(t[1] for t in tri) / 3 * h), h - 1), min(int(sum(t[0] for t in tri) / 3 * w), w - 1)]
                              for tri in tris]) > 0.45 for tri in tris]
        self.bright = raster(bright, (h, w))
        # A thigh that pushes through the skirt in a stride shouldn't show: these pixels take the coat's colour.
        self.covered = raster([(tri, smoothstep(covered_from, covered_from + 0.08, z)) for isl, z, tris in faces
                               for tri in tris], (h, w)) * self.trousers

    def save(self, path, name, alpha=None):
        h, w = self.lum.shape
        px = self.px.copy()
        px[..., 3] = 1.0 if alpha is None else alpha
        out_img = bpy.data.images.new(name, w, h, alpha=alpha is not None)
        out_img.pixels.foreach_set(px.ravel())
        out_img.filepath_raw = path
        out_img.file_format = 'WEBP'
        bpy.context.scene.render.image_settings.quality = 88
        out_img.save()
        print("EXPORTED", path)
