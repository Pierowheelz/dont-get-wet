# Builds the raincoat outfit for a man on the walker's own model, without reshaping the walker:
# - raincoat.glb: a long coat skirt and a fedora, skinned to walker_model.glb's armature. The skirt is a
#   flared tube from under the jacket hem to mid-calf, open at the front below the knees, weighted to the
#   pelvis at the top and to the thighs further down. The fedora is weighted wholly to the head.
# - raincoat_suit.webp: the walker's suit texture with the jacket dyed the coat's tan and the trousers
#   dark, shirt and tie left alone.
# Usage: blender -b --factory-startup --python build_raincoat.py -- <walker_model.glb> <out_dir>
import bpy, bmesh, sys, math, os
import numpy as np

src, out_dir = sys.argv[sys.argv.index("--") + 1:][:2]

COAT = (0.50, 0.42, 0.30)      # sRGB
TROUSERS = (0.11, 0.11, 0.12)
FELT = (0.36, 0.31, 0.25)
BAND = (0.05, 0.045, 0.04)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=src)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name, srgb, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*to_linear(srgb), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    m.use_backface_culling = True
    return m


def skin(obj, groups, mats):
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


def solidify(obj, thickness):
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


# --- Coat skirt ------------------------------------------------------------------------------------
# Blender frame of the MPFB rig: +Z up, the character faces -Y, his left is +X.
# Rings (z, half width, front depth, back depth): starts inside the jacket (hem at z 0.89) so the join
# is hidden, then flares to the hem.
PROFILE = [(0.95, 0.180, 0.140, 0.120), (0.87, 0.214, 0.170, 0.142), (0.80, 0.226, 0.182, 0.146),
           (0.60, 0.240, 0.198, 0.152), (0.40, 0.255, 0.205, 0.158)]
CENTRE_Y = -0.02
SEGMENTS = 40          # around; vertex 0 and SEGMENTS are the two edges of the front opening
RING_STEP = 0.035
SLIT_TOP = 0.62        # the front opening closes above this height
LEG_TOP, LEG_FULL, LEG_MAX = 0.97, 0.72, 0.95
SIDE_BLEND = 0.12      # half-width (m) over which the back seam shares the two thighs


def ring_at(z):
    for (z0, *a), (z1, *b) in zip(PROFILE, PROFILE[1:]):
        if z1 <= z <= z0:
            t = (z0 - z) / (z0 - z1)
            return [p + (q - p) * t for p, q in zip(a, b)]
    return PROFILE[-1][1:] if z < PROFILE[-1][0] else PROFILE[0][1:]


top, hem = PROFILE[0][0], PROFILE[-1][0]
rings = int(round((top - hem) / RING_STEP))
bm = bmesh.new()
grid = []
weights = []
for r in range(rings + 1):
    z = top - (top - hem) * r / rings
    half, front, back = ring_at(z)
    row = []
    for j in range(SEGMENTS + 1):
        phi = math.tau * j / SEGMENTS
        x = half * math.sin(phi)
        y = CENTRE_Y - (front if math.cos(phi) > 0.0 else back) * math.cos(phi)
        left = smoothstep(-SIDE_BLEND, SIDE_BLEND, x)
        if math.cos(phi) > 0.0:
            # Below the slit each front panel follows only its own thigh.
            own = 1.0 if j < SEGMENTS / 2 else 0.0
            k = 1.0 - smoothstep(SLIT_TOP, SLIT_TOP + 0.06, z)
            left += (own - left) * k
        leg = LEG_MAX * smoothstep(LEG_TOP, LEG_FULL, z)
        weights.append((1.0 - leg, leg * left, leg * (1.0 - left)))
        row.append(bm.verts.new((x, y, z)))
    grid.append(row)
for r in range(rings):
    for j in range(SEGMENTS):
        bm.faces.new((grid[r][j], grid[r + 1][j], grid[r + 1][j + 1], grid[r][j + 1]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
mesh = bpy.data.meshes.new("long_coat")
bm.to_mesh(mesh)
bm.free()
coat = bpy.data.objects.new("long_coat", mesh)
bpy.context.collection.objects.link(coat)
skin(coat, {"pelvis": [w[0] for w in weights], "thigh_l": [w[1] for w in weights],
            "thigh_r": [w[2] for w in weights]}, [material("coat", COAT, 0.7)])
solidify(coat, 0.012)

# --- Fedora ----------------------------------------------------------------------------------------
# Lathed around an ellipse that clears the walker's hair (half widths 0.089 x 0.110 at z 1.72).
HAT_Y = -0.058
HAT_Z = 1.708          # band bottom: just above the eyebrows (z 1.69), over the tops of the ears
CROWN = [(0.0, 0.100, 0.121), (0.06, 0.096, 0.117), (0.105, 0.088, 0.108), (0.118, 0.080, 0.099)]
BRIM = (0.060, 0.068)  # metres out from the crown base: at the sides, front and back
BAND_H = 0.030
HAT_SEGMENTS = 48


def brim_lift(phi, t):
    # Snapped down at the front, turned up at the back and the sides.
    c, s = math.cos(phi), math.sin(phi)
    end = (-0.016 if c > 0.0 else 0.014) * c * c + 0.011 * s * s
    return end * t * t


def crown_ring(h, rx, ry, phi):
    # The front of the crown is pinched at the top, either side of the centre crease.
    pinch = 0.016 * smoothstep(0.05, CROWN[-1][0], h) * math.exp(-((abs(math.sin(phi)) - 0.62) / 0.25) ** 2) \
        * max(math.cos(phi), 0.0)
    return (rx - pinch) * math.sin(phi), HAT_Y - (ry - pinch) * math.cos(phi), HAT_Z + h


bm = bmesh.new()
rows = []
for t in (1.0, 0.5, 0.0):
    row = []
    for j in range(HAT_SEGMENTS):
        phi = math.tau * j / HAT_SEGMENTS
        rx = CROWN[0][1] + BRIM[0] * t
        ry = CROWN[0][2] + BRIM[1] * t
        row.append(bm.verts.new((rx * math.sin(phi), HAT_Y - ry * math.cos(phi), HAT_Z + brim_lift(phi, t))))
    rows.append(row)
for h, rx, ry in CROWN[1:]:
    rows.append([bm.verts.new(crown_ring(h, rx, ry, math.tau * j / HAT_SEGMENTS)) for j in range(HAT_SEGMENTS)])
# Top: a lengthwise centre crease.
h_top, rx_top, ry_top = CROWN[-1]
for k in (0.66, 0.33):
    row = []
    for j in range(HAT_SEGMENTS):
        x, y, z = crown_ring(h_top, rx_top * k, ry_top * k, math.tau * j / HAT_SEGMENTS)
        row.append(bm.verts.new((x, y, z - 0.022 * (1.0 - k * k) * math.exp(-(x / 0.03) ** 2))))
    rows.append(row)
apex = bm.verts.new((0.0, HAT_Y, HAT_Z + h_top - 0.022))
faces_band = []
for r in range(len(rows) - 1):
    for j in range(HAT_SEGMENTS):
        j1 = (j + 1) % HAT_SEGMENTS
        bm.faces.new((rows[r][j], rows[r][j1], rows[r + 1][j1], rows[r + 1][j]))
for j in range(HAT_SEGMENTS):
    bm.faces.new((rows[-1][j], rows[-1][(j + 1) % HAT_SEGMENTS], apex))
# Band: a ribbon standing just proud of the crown's lowest stretch.
band_rows = []
for h in (0.0, BAND_H):
    k = h / CROWN[1][0]
    rx = CROWN[0][1] + (CROWN[1][1] - CROWN[0][1]) * k + 0.003
    ry = CROWN[0][2] + (CROWN[1][2] - CROWN[0][2]) * k + 0.003
    band_rows.append([bm.verts.new((rx * math.sin(p), HAT_Y - ry * math.cos(p), HAT_Z + h + 0.002))
                      for p in (math.tau * j / HAT_SEGMENTS for j in range(HAT_SEGMENTS))])
for j in range(HAT_SEGMENTS):
    j1 = (j + 1) % HAT_SEGMENTS
    f = bm.faces.new((band_rows[0][j], band_rows[0][j1], band_rows[1][j1], band_rows[1][j]))
    f.material_index = 1
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
mesh = bpy.data.meshes.new("fedora")
bm.to_mesh(mesh)
bm.free()
hat = bpy.data.objects.new("fedora", mesh)
bpy.context.collection.objects.link(hat)
skin(hat, {"head": [1.0] * len(mesh.vertices)}, [material("felt", FELT, 0.85), material("band", BAND, 0.5)])
solidify(hat, 0.004)

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
coat.select_set(True)
hat.select_set(True)
glb = os.path.join(out_dir, "raincoat.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True, export_animations=False,
                          export_skins=True, export_apply=False, export_yup=True)
print("EXPORTED", glb, len(coat.data.vertices), "+", len(hat.data.vertices), "verts")

# --- Suit texture ----------------------------------------------------------------------------------
def suit_faces():
    """(UV island id, bind-pose height, UV triangles) for every face of the suit."""
    suit = next(o for o in bpy.data.objects if o.type == 'MESH' and "elegantsuit" in o.name.lower())
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


img = next(i for i in bpy.data.images if "elegantsuit" in i.name.lower())
w, h = img.size
px = np.empty(w * h * 4, dtype=np.float32)
img.pixels.foreach_get(px)
px = px.reshape(h, w, 4)            # row 0 is the bottom of the image
u = (np.arange(w) + 0.5) / w
v = 1.0 - (np.arange(h) + 0.5) / h  # glTF v: 0 at the top
# The trouser UV islands are the only ones below v 0.468 left of u 0.75 (sleeves are to the right).
trousers = (v[:, None] > 0.468) & (u[None, :] < 0.75)
lum = px[..., :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
faces = suit_faces()
islands = {}
for isl, z, tris in faces:
    islands.setdefault(isl, []).extend(tris)
# The mostly white islands (shirt front and tie, cuffs) stay undyed.
bright = [(tri, 1.0) for tris in islands.values()
          if np.mean([lum[min(int(sum(t[1] for t in tri) / 3 * h), h - 1), min(int(sum(t[0] for t in tri) / 3 * w), w - 1)]
                      for tri in tris]) > 0.45 for tri in tris]
# The trousers are coat-coloured where the coat always covers them, so a thigh that pushes through the
# skirt in a stride doesn't show.
covered = raster([(tri, smoothstep(0.64, 0.72, z)) for isl, z, tris in faces for tri in tris], (h, w)) * trousers
cloth = 1.0 - np.clip((lum - 0.3) / 0.2, 0.0, 1.0)  # the grey suit cloth
cloth = cloth * cloth * (3.0 - 2.0 * cloth) * (1.0 - raster(bright, (h, w)))
for mask, colour in ((trousers, TROUSERS), (~trousers, COAT)):
    ref = np.median(lum[mask & (lum < 0.3)])
    shade = np.clip(lum / ref, 0.0, 1.6)[..., None]
    target = np.array(colour, dtype=np.float32) + (np.array(COAT, dtype=np.float32) - colour) * covered[..., None]
    k = (cloth * mask)[..., None]
    px[..., :3] = px[..., :3] * (1.0 - k) + target * shade * k
out_img = bpy.data.images.new("raincoat_suit", w, h)
out_img.pixels.foreach_set(px.ravel())
out_img.filepath_raw = os.path.join(out_dir, "raincoat_suit.webp")
out_img.file_format = 'WEBP'
bpy.context.scene.render.image_settings.quality = 88
out_img.save()
print("EXPORTED", out_img.filepath_raw)
