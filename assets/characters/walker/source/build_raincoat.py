# Builds the raincoat outfit for a man on the walker's own model, without reshaping the walker:
# - raincoat.glb: a long coat skirt and a fedora, skinned to walker_model.glb's armature. The skirt is a
#   flared tube from under the jacket hem to mid-calf, open at the front below the knees, weighted to the
#   pelvis at the top and to the thighs further down. The fedora is weighted wholly to the head.
# - raincoat_suit.webp: the walker's suit texture with the jacket dyed the coat's tan and the trousers
#   dark, shirt and tie left alone.
# Usage: blender -b --factory-startup --python build_raincoat.py -- <walker_model.glb> <out_dir>
import bpy, bmesh, sys, math, os
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from outfit_common import load_walker, smoothstep, material, skin, solidify, coat_skirt, SuitTexture

src, out_dir = sys.argv[sys.argv.index("--") + 1:][:2]

COAT = (0.50, 0.42, 0.30)      # sRGB
TROUSERS = (0.11, 0.11, 0.12)
FELT = (0.36, 0.31, 0.25)
BAND = (0.05, 0.045, 0.04)

rig = load_walker(src)

# --- Coat skirt ------------------------------------------------------------------------------------
# Rings (z, half width, front depth, back depth): starts inside the jacket (hem at z 0.89) so the join
# is hidden, then flares to the hem.
coat = coat_skirt(rig, "long_coat", [(0.95, 0.180, 0.140, 0.120), (0.87, 0.214, 0.170, 0.142),
                                     (0.80, 0.226, 0.182, 0.146), (0.60, 0.240, 0.198, 0.152),
                                     (0.40, 0.255, 0.205, 0.158)], material("coat", COAT, 0.7), slit_top=0.62)

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
skin(hat, rig, {"head": [1.0] * len(mesh.vertices)}, [material("felt", FELT, 0.85), material("band", BAND, 0.5)])
solidify(hat, rig, 0.004)

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
coat.select_set(True)
hat.select_set(True)
glb = os.path.join(out_dir, "raincoat.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True, export_animations=False,
                          export_skins=True, export_apply=False, export_yup=True)
print("EXPORTED", glb, len(coat.data.vertices), "+", len(hat.data.vertices), "verts")

# --- Suit texture ----------------------------------------------------------------------------------
tex = SuitTexture(covered_from=0.64)
px, lum, trousers, covered = tex.px, tex.lum, tex.trousers, tex.covered
cloth = 1.0 - np.clip((lum - 0.3) / 0.2, 0.0, 1.0)  # the grey suit cloth
cloth = cloth * cloth * (3.0 - 2.0 * cloth) * (1.0 - tex.bright)
for mask, colour in ((trousers, TROUSERS), (~trousers, COAT)):
    ref = np.median(lum[mask & (lum < 0.3)])
    shade = np.clip(lum / ref, 0.0, 1.6)[..., None]
    target = np.array(colour, dtype=np.float32) + (np.array(COAT, dtype=np.float32) - colour) * covered[..., None]
    k = (cloth * mask)[..., None]
    px[..., :3] = px[..., :3] * (1.0 - k) + target * shade * k
tex.save(os.path.join(out_dir, "raincoat_suit.webp"), "raincoat_suit")
