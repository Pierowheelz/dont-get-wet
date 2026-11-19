# Builds the yellow slicker outfit for a man on the walker's own model, without reshaping the walker:
# - slicker.glb, skinned to walker_model.glb's armature:
#   - slicker_skirt: an A-line coat skirt from under the jacket hem to mid-calf, buttoned down to
#     SLIT_TOP and open below it.
#   - slicker_hood: a roomy hood, up, open around the face, closing under the chin into a standing
#     collar that tucks into the jacket's neck. Weighted to the head, blending to the neck and chest
#     down the collar.
#   - slicker_buttons: two rows of dark round buttons down the front of the jacket and skirt (double-
#     breasted, so a row shows at the front edge in profile), each copying the skin weights of the
#     cloth under it.
# - slicker_suit.webp: the walker's suit texture with the jacket, shirt and tie all dyed slicker yellow,
#   the trousers left grey (and yellow where the skirt always hides them). Alpha is the roughness:
#   glossy oilskin over matte wool.
# Usage: blender -b --factory-startup --python build_slicker.py -- <walker_model.glb> <out_dir>
import bpy, bmesh, sys, math, os
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from outfit_common import load_walker, smoothstep, material, skin, solidify, coat_skirt, mesh_object, \
    suit_mesh, SuitTexture

src, out_dir = sys.argv[sys.argv.index("--") + 1:][:2]

YELLOW = (0.93, 0.76, 0.08)    # sRGB: fisherman's slicker, a lemon yellow that stays yellow under warm shop light
BUTTON = (0.06, 0.055, 0.05)
SLICKER_ROUGH = 0.42
TROUSER_ROUGH = 0.88
SLIT_TOP = 0.52

rig = load_walker(src)
suit = suit_mesh()

# --- Coat skirt ------------------------------------------------------------------------------------
# (z, half width, front depth, back depth): a stiffer cloth than the raincoat, so a fuller A-line.
skirt = coat_skirt(rig, "slicker_skirt", [(0.95, 0.184, 0.142, 0.122), (0.87, 0.220, 0.174, 0.146),
                                          (0.80, 0.234, 0.186, 0.154), (0.60, 0.256, 0.204, 0.164),
                                          (0.42, 0.278, 0.216, 0.174)],
                   material("slicker", YELLOW, SLICKER_ROUGH), slit_top=SLIT_TOP)

# --- Hood ------------------------------------------------------------------------------------------
# Rings (z, half width, front depth, back depth) about HOOD_Y, from inside the jacket collar up over
# the hair (half widths 0.091 at z 1.70-1.74, back of the head at y 0.05, crown at z 1.806).
HOOD_Y = -0.045
HOOD = [(1.44, 0.140, 0.062, 0.120), (1.50, 0.126, 0.082, 0.118), (1.55, 0.114, 0.106, 0.110),
        (1.60, 0.114, 0.126, 0.118), (1.65, 0.121, 0.138, 0.134), (1.70, 0.126, 0.146, 0.142),
        (1.75, 0.123, 0.148, 0.136), (1.79, 0.108, 0.140, 0.118), (1.825, 0.078, 0.104, 0.086),
        (1.848, 0.030, 0.040, 0.034)]
HOOD_TOP = 1.855
HOOD_STEP = 0.01
HOOD_SEGMENTS = 48
FACE = (1.578, 1.792, math.radians(60.0))   # the face opening: bottom (lip line), top (brow), widest half-angle


def hood_ring(z):
    for (z0, *a), (z1, *b) in zip(HOOD, HOOD[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3.0 - 2.0 * t) if z0 >= 1.79 else t
            return [p + (q - p) * t for p, q in zip(a, b)]
    return HOOD[-1][1:]


def face_half_angle(z):
    lo, hi, widest = FACE
    c, r = (lo + hi) * 0.5, (hi - lo) * 0.5
    q = 1.0 - ((z - c) / r) ** 2
    return widest * math.sqrt(q) if q > 0.0 else 0.0


bm = bmesh.new()
rows = []
zs = []
z = HOOD[0][0]
while z < HOOD[-1][0] - 1e-6:
    zs.append(z)
    z += HOOD_STEP
zs.append(HOOD[-1][0])
for z in zs:
    half, front, back = hood_ring(z)
    a = face_half_angle(z)
    row = []
    # Spread around the ring from one edge of the face opening to the other (a closed ring when the
    # opening is shut: its two ends coincide and are welded below).
    for j in range(HOOD_SEGMENTS + 1):
        phi = a + (math.tau - 2.0 * a) * j / HOOD_SEGMENTS
        x = half * math.sin(phi)
        y = HOOD_Y - (front if math.cos(phi) > 0.0 else back) * math.cos(phi)
        row.append(bm.verts.new((x, y, z)))
    rows.append(row)
for r in range(len(rows) - 1):
    for j in range(HOOD_SEGMENTS):
        bm.faces.new((rows[r][j], rows[r][j + 1], rows[r + 1][j + 1], rows[r + 1][j]))
apex = bm.verts.new((0.0, HOOD_Y + 0.004, HOOD_TOP))
for j in range(HOOD_SEGMENTS):
    bm.faces.new((rows[-1][j], rows[-1][j + 1], apex))
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
hood = mesh_object("slicker_hood", bm)
heights = [v.co.z for v in hood.data.vertices]
head_w = [smoothstep(1.56, 1.66, h) for h in heights]
neck_w = [(1.0 - hw) * smoothstep(1.45, 1.54, h) for h, hw in zip(heights, head_w)]
chest_w = [1.0 - hw - nw for hw, nw in zip(head_w, neck_w)]
skin(hood, rig, {"head": head_w, "neck_01": neck_w, "spine_03": chest_w},
     [material("slicker_hood", YELLOW, SLICKER_ROUGH)])
solidify(hood, rig, 0.008)

# --- Buttons ---------------------------------------------------------------------------------------
# Cast from in front of him onto the jacket and the skirt; each button lies on the cloth it hit and
# takes the skin weights of that cloth's nearest vertex.
BUTTON_Z = [1.38, 1.24, 1.10, 0.96, 0.82, 0.68]
BUTTON_X = (-0.062, 0.062)
BUTTON_R = 0.019
BUTTON_T = 0.011
BUTTON_SEGMENTS = 12


def evaluated(obj):
    """World-space vertices, BVH and KD tree of `obj` in its bind pose, with its vertex groups by index."""
    verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    polys = [tuple(p.vertices) for p in obj.data.polygons]
    kd = KDTree(len(verts))
    for i, v in enumerate(verts):
        kd.insert(v, i)
    kd.balance()
    return BVHTree.FromPolygons(verts, polys), kd, obj


cloths = [evaluated(suit), evaluated(skirt)]


def weights_of(obj, index):
    names = {g.index: g.name for g in obj.vertex_groups}
    return {names[g.group]: g.weight for g in obj.data.vertices[index].groups if g.weight > 1e-4}


bm = bmesh.new()
button_weights = []
for x, z in ((x, z) for z in BUTTON_Z for x in BUTTON_X):
    origin = Vector((x, -1.0, z))
    best = None
    for bvh, kd, obj in cloths:
        hit = bvh.ray_cast(origin, Vector((0.0, 1.0, 0.0)), 2.0)
        if hit[0] is not None and (best is None or hit[3] < best[0][3]):
            best = (hit, kd, obj)
    (loc, normal, _, _), kd, obj = best
    if normal.y > 0.0:
        normal = -normal
    _, nearest, _ = kd.find(loc)
    w = weights_of(obj, nearest)
    # A flat disc facing out along the cloth's normal, its back face just under the surface.
    t1 = normal.cross(Vector((0.0, 0.0, 1.0))).normalized()
    t2 = normal.cross(t1).normalized()
    centre = loc + normal * (BUTTON_T * 0.5)
    rings = []
    for depth, r in ((-BUTTON_T * 0.5, BUTTON_R), (BUTTON_T * 0.3, BUTTON_R), (BUTTON_T * 0.5, BUTTON_R * 0.7)):
        rings.append([bm.verts.new(centre + normal * depth + (t1 * math.cos(a) + t2 * math.sin(a)) * r)
                      for a in (math.tau * k / BUTTON_SEGMENTS for k in range(BUTTON_SEGMENTS))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(BUTTON_SEGMENTS):
            k1 = (k + 1) % BUTTON_SEGMENTS
            bm.faces.new((r0[k], r0[k1], r1[k1], r1[k]))
    bm.faces.new(rings[-1])
    bm.faces.new(list(reversed(rings[0])))
    button_weights.extend([w] * (3 * BUTTON_SEGMENTS))
buttons = mesh_object("slicker_buttons", bm)
groups = sorted({g for w in button_weights for g in w})
skin(buttons, rig, {g: [w.get(g, 0.0) for w in button_weights] for g in groups},
     [material("slicker_button", BUTTON, 0.3)])
for p in buttons.data.polygons:
    p.use_smooth = False
buttons.modifiers.new("Armature", 'ARMATURE').object = rig

bpy.ops.object.select_all(action='DESELECT')
for o in (rig, skirt, hood, buttons):
    o.select_set(True)
glb = os.path.join(out_dir, "slicker.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True, export_animations=False,
                          export_skins=True, export_apply=False, export_yup=True)
print("EXPORTED", glb, len(skirt.data.vertices), "+", len(hood.data.vertices), "+", len(buttons.data.vertices), "verts")

# --- Suit texture ----------------------------------------------------------------------------------
tex = SuitTexture(covered_from=0.60)
px, lum, trousers, covered = tex.px, tex.lum, tex.trousers, tex.covered
yellow = np.array(YELLOW, dtype=np.float32)
# Folds and seams from the suit cloth's own shading; the white shirt and tie take a flat yellow.
ref = np.median(lum[~trousers & (lum < 0.3)])
shade = np.clip(lum / ref, 0.55, 1.3)
shade = shade + (1.0 - shade) * tex.bright
coat = ~trousers | (covered > 0.0)
k = np.where(trousers, covered, 1.0)[..., None]
px[..., :3] = px[..., :3] * (1.0 - k) + yellow * shade[..., None] * k
rough = np.where(coat, SLICKER_ROUGH + (TROUSER_ROUGH - SLICKER_ROUGH) * (1.0 - k[..., 0]), TROUSER_ROUGH)
tex.save(os.path.join(out_dir, "slicker_suit.webp"), "slicker_suit", alpha=rough)
