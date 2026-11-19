# Builds the yellow slicker outfit for a man on the walker's own model, without reshaping the walker:
# - slicker.glb, skinned to walker_model.glb's armature:
#   - slicker_skirt: an A-line coat skirt from the waist to mid-calf. Its top wraps over the jacket's
#     hem and moves with the jacket, so the coat runs in one line from the shoulders down. It is
#     open at the front below SLIT_TOP, where each front panel swings with its own leg.
#   - slicker_hood: a PVC hood, up, worn close to the head: its edge frames the face, its top runs
#     back to a soft point behind the crown, dark inside. Its rim sits on the collar and shoulders.
#     Weighted to the head, blending to the neck and chest.
#   - slicker_flap: the storm flap down the middle of the front, from under the hood to the slit,
#     bridging the jacket's lapels, and a flap pocket on each hip.
#   - slicker_buttons: a row of dark snaps down the flap, on the centre line so they stand in the
#     silhouette from either side, and the two that fasten the hood at the throat.
#   - slicker_cords: the hood's white drawstrings, hanging on the chest.
#   The flap, snaps and cords copy the skin weights of the cloth under them.
# - slicker_suit.webp: the walker's suit texture with the jacket, shirt and tie all dyed slicker yellow,
#   the trousers left grey (and yellow where the skirt always hides them). Alpha is the roughness:
#   glossy oilskin over matte wool.
# Usage: blender -b --factory-startup --python build_slicker.py -- <walker_model.glb> <out_dir>
import bpy, bmesh, sys, math, os
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from outfit_common import load_walker, smoothstep, material, skin, solidify, coat_skirt, mesh_object, \
    suit_mesh, SuitTexture, Cloth

src, out_dir = sys.argv[sys.argv.index("--") + 1:][:2]

YELLOW = (0.93, 0.76, 0.08)    # sRGB: fisherman's slicker, a lemon yellow that stays yellow under warm shop light
LINING = (0.13, 0.10, 0.03)    # the hood's inside: deep in shadow, as an empty hood looks
BUTTON = (0.06, 0.055, 0.05)
CORD = (0.90, 0.88, 0.82)
SLICKER_ROUGH = 0.42
TROUSER_ROUGH = 0.88
SLIT_TOP = 0.74

rig = load_walker(src)
suit = suit_mesh()
jacket = Cloth(suit)
oilskin = material("slicker", YELLOW, SLICKER_ROUGH)

# --- Coat skirt ------------------------------------------------------------------------------------
# (z, half width, front depth, back depth): a stiffer cloth than the raincoat, so a fuller A-line.
# Above WRAP_Z it is let out over the jacket (waist 0.183 wide at z 1.04, hem 0.206 at z 0.89).
WRAP_Z = 0.88
skirt = coat_skirt(rig, "slicker_skirt", [(1.04, 0.184, 0.150, 0.122), (0.95, 0.200, 0.160, 0.140),
                                          (0.87, 0.220, 0.174, 0.152), (0.80, 0.234, 0.186, 0.158),
                                          (0.60, 0.256, 0.204, 0.166), (0.42, 0.278, 0.216, 0.174)],
                   oilskin, slit_top=SLIT_TOP, leg_hem=(0.66, 0.85), wrap=(jacket, WRAP_Z, 0.01))

# --- Hood ------------------------------------------------------------------------------------------
# A PVC hood, up, worn close: a finger's width off the head at the temples and a little slack behind
# it, its edge framing the face from the brow round the cheeks to the throat, its top running up and
# back to a soft point behind the crown.
# Rings (z, half width, front y, back y), from the collar up (head half widths 0.091 at z 1.70-1.74,
# forehead at y -0.15, nose -0.176, chin -0.16 at z 1.57, back of the head y 0.05, crown z 1.806; the
# shoulders' top is at z 1.526 at x 0.12).
HOOD = [(1.49, 0.130, -0.128, 0.100), (1.53, 0.114, -0.142, 0.092), (1.57, 0.106, -0.168, 0.084),
        (1.62, 0.104, -0.174, 0.080), (1.70, 0.106, -0.176, 0.080), (1.76, 0.104, -0.176, 0.082),
        (1.80, 0.094, -0.160, 0.084), (1.83, 0.074, -0.112, 0.082), (1.85, 0.046, -0.045, 0.074),
        (1.862, 0.018, 0.022, 0.064)]
HOOD_APEX = (0.046, 1.867)  # y, z
HOOD_STEP = 0.01
HOOD_SEGMENTS = 48
FACE = (1.568, 1.79, math.radians(60.0))   # the face opening: bottom (chin), top (brow), widest half-angle
HOOD_SEAT = (1.575, 0.03, 0.008)  # below this z the hood settles onto the jacket: the rim rides up this much over the shoulders and lies this far off the cloth


def hood_ring(z):
    for (z0, *a), (z1, *b) in zip(HOOD, HOOD[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            return [p + (q - p) * t for p, q in zip(a, b)]
    return HOOD[-1][1:]


def face_half_angle(z):
    lo, hi, widest = FACE
    c, r = (lo + hi) * 0.5, (hi - lo) * 0.5
    q = 1.0 - ((z - c) / r) ** 2
    return widest * q ** 0.4 if q > 0.0 else 0.0   # a rounded oblong, not a pointed oval


bm = bmesh.new()
nominal = bm.verts.layers.float.new("nominal")   # each vertex's ring height, before the rim's lift: what its skin weights go by
rows = []
zs = []
z = HOOD[0][0]
while z < HOOD[-1][0] - 1e-6:
    zs.append(z)
    z += HOOD_STEP
zs.append(HOOD[-1][0])
for z in zs:
    half, front, back = hood_ring(z)
    centre, depth = (front + back) * 0.5, (back - front) * 0.5
    a = face_half_angle(z)
    lift = HOOD_SEAT[1] * (1.0 - smoothstep(HOOD[0][0], HOOD_SEAT[0], z))
    row = []
    # Spread around the ring from one edge of the face opening to the other (a closed ring when the
    # opening is shut: its two ends coincide and are welded below).
    for j in range(HOOD_SEGMENTS + 1):
        phi = a + (math.tau - 2.0 * a) * j / HOOD_SEGMENTS
        row.append(bm.verts.new((half * math.sin(phi), centre - depth * math.cos(phi), z + lift * math.sin(phi) ** 2)))
        row[-1][nominal] = z
    rows.append(row)
for r in range(len(rows) - 1):
    for j in range(HOOD_SEGMENTS):
        bm.faces.new((rows[r][j], rows[r][j + 1], rows[r + 1][j + 1], rows[r + 1][j]))
apex = bm.verts.new((0.0, HOOD_APEX[0], HOOD_APEX[1]))
apex[nominal] = HOOD_APEX[1]
for j in range(HOOD_SEGMENTS):
    bm.faces.new((rows[-1][j], rows[-1][j + 1], apex))
# The hood's foot settles onto the collar and shoulders: its rim lies on the jacket, the rows above
# ease from there into the free shape, and nothing sinks in. The move is evened out between
# neighbours so no one vertex stands proud.
seat = [v for v in bm.verts if v[nominal] < HOOD_SEAT[0]]
for _ in range(4):
    move = {}
    for v in seat:
        loc, normal, _, _ = jacket.bvh.find_nearest(v.co)
        gap = (v.co - loc).dot(normal)
        settle = 1.0 - smoothstep(HOOD[0][0], HOOD_SEAT[0], v[nominal])
        if gap < HOOD_SEAT[2]:
            move[v] = normal * (HOOD_SEAT[2] - gap)
        else:
            move[v] = normal * (HOOD_SEAT[2] - gap) * settle
    for v in seat:
        near = [move.get(e.other_vert(v), Vector()) for e in v.link_edges]
        v.co += (move[v] + sum(near, Vector()) / len(near)) * 0.5
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
heights = [v[nominal] for v in bm.verts]
hood = mesh_object("slicker_hood", bm)
head_w = [smoothstep(1.56, 1.66, h) for h in heights]
neck_w = [(1.0 - hw) * smoothstep(1.47, 1.56, h) for h, hw in zip(heights, head_w)]
chest_w = [1.0 - hw - nw for hw, nw in zip(head_w, neck_w)]
skin(hood, rig, {"head": head_w, "neck_01": neck_w, "spine_03": chest_w},
     [material("slicker_hood", YELLOW, SLICKER_ROUGH), material("slicker_lining", LINING, 0.8)])
solidify(hood, rig, 0.008, lining=True)

# --- Storm flap ------------------------------------------------------------------------------------
# A raised strip down the middle of the front, laid on whichever cloth is frontmost and bridged across
# the hollow between the jacket's lapels. Each vertex takes the skin weights of the cloth under it.
cloths = [jacket, Cloth(skirt)]
FLAP_TOP, FLAP_BOTTOM = 1.50, SLIT_TOP + 0.02
FLAP_X = [-0.064, -0.056, -0.028, 0.0, 0.028, 0.056, 0.064]   # the outer two lie on the cloth: its edges
FLAP_RAISE = 0.007
FLAP_STEP = 0.02
POCKET_X = [0.082, 0.088, 0.12, 0.152, 0.158]   # a flap pocket on each hip
POCKET_Z = (0.965, 0.905)


def front_of(x, z):
    """The frontmost cloth at (x, z): its point and the cloth."""
    best = None
    for cloth in cloths:
        hit = cloth.bvh.ray_cast(Vector((x, -1.0, z)), Vector((0.0, 1.0, 0.0)), 2.0)
        if hit[0] is not None and (best is None or hit[0].y < best[0].y):
            best = (hit[0], cloth)
    return best


def bridged(ys, xs):
    """`ys` across `xs` with every hollow spanned: the front (lowest y) of their convex hull."""
    out = list(ys)
    for i in range(len(xs)):
        for a in range(i):
            for b in range(i + 1, len(xs)):
                chord = ys[a] + (ys[b] - ys[a]) * (xs[i] - xs[a]) / (xs[b] - xs[a])
                out[i] = min(out[i], chord)
    return out


def patch(bm, weights, xs, top, bottom):
    """A raised panel over the columns `xs` from `top` down to `bottom`, its rim lying on the cloth."""
    grid = []
    steps = max(int(round((top - bottom) / FLAP_STEP)), 3)
    for r in range(steps + 1):
        z = top - (top - bottom) * r / steps
        hits = [front_of(x, z) for x in xs]
        ys = bridged([h[0].y for h in hits], xs)
        end = r in (0, steps)
        row = []
        for i, (x, y, (at, cloth)) in enumerate(zip(xs, ys, hits)):
            edge = end or i in (0, len(xs) - 1)
            row.append(bm.verts.new((x, (at.y + 0.001) if edge else y - FLAP_RAISE, z)))
            weights.append(cloth.weights_near(at))
        grid.append(row)
    for r in range(steps):
        for i in range(len(xs) - 1):
            bm.faces.new((grid[r][i], grid[r + 1][i], grid[r + 1][i + 1], grid[r][i + 1]))


bm = bmesh.new()
flap_weights = []
patch(bm, flap_weights, FLAP_X, FLAP_TOP, FLAP_BOTTOM)
for side in (-1.0, 1.0):
    patch(bm, flap_weights, sorted(side * x for x in POCKET_X), *POCKET_Z)
flap = mesh_object("slicker_flap", bm)
bones = sorted({b for w in flap_weights for b in w})
skin(flap, rig, {b: [w.get(b, 0.0) for w in flap_weights] for b in bones}, [oilskin])
flap.modifiers.new("Armature", 'ARMATURE').object = rig
cloths.append(Cloth(flap))

# --- Buttons ---------------------------------------------------------------------------------------
# Cast from in front of him onto the flap; each button lies on the cloth it hit and takes the skin
# weights of that cloth's nearest vertex.
BUTTONS = [(0.0, 1.37), (0.0, 1.23), (0.0, 1.09), (0.0, 0.95), (0.0, 0.81),   # x, z: down the flap
           (-0.03, 1.538), (0.03, 1.538)]                                      # and fastening the hood at the throat
BUTTON_R = 0.016
BUTTON_T = 0.011
BUTTON_SEGMENTS = 12

cloths.append(Cloth(hood))
bm = bmesh.new()
button_weights = []
for x, z in BUTTONS:
    at, cloth = front_of(x, z)
    normal = cloth.bvh.find_nearest(at)[1]
    if normal.y > 0.0:
        normal = -normal
    w = cloth.weights_near(at)
    # A flat disc facing out along the cloth's normal, its back face just under the surface.
    t1 = normal.cross(Vector((0.0, 0.0, 1.0))).normalized()
    t2 = normal.cross(t1).normalized()
    centre = at + normal * (BUTTON_T * 0.5)
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

# --- Drawstrings -----------------------------------------------------------------------------------
# The hood's two white cords, from the corners of its opening down the chest, each ending in a toggle.
# They lie on the cloth in front of them and take its skin weights.
CORD_X = 0.045
CORD_Z = (1.56, 1.40)
CORD_R = 0.0045
CORD_OFF = 0.006
CORD_STEP = 0.02
TOGGLE = (0.008, 0.022)   # radius, length

bm = bmesh.new()
cord_weights = []
for side in (-1.0, 1.0):
    rings = []
    steps = int(round((CORD_Z[0] - CORD_Z[1]) / CORD_STEP))
    for r in range(steps + 2):
        last = r == steps + 1
        z = CORD_Z[0] - (CORD_Z[0] - CORD_Z[1]) * min(r, steps) / steps - (TOGGLE[1] if last else 0.0)
        x = side * (CORD_X + 0.012 * min(r, steps) / steps)          # they hang a little apart
        at, cloth = front_of(x, z)
        radius = TOGGLE[0] if r >= steps else CORD_R
        centre = Vector((x, at.y - CORD_OFF - radius, z))
        rings.append([bm.verts.new(centre + Vector((math.cos(a), math.sin(a), 0.0)) * radius)
                      for a in (math.tau * k / 6 for k in range(6))])
        cord_weights.extend([cloth.weights_near(at)] * 6)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(6):
            bm.faces.new((r0[k], r0[(k + 1) % 6], r1[(k + 1) % 6], r1[k]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
cords = mesh_object("slicker_cords", bm)
groups = sorted({g for w in cord_weights for g in w})
skin(cords, rig, {g: [w.get(g, 0.0) for w in cord_weights] for g in groups},
     [material("slicker_cord", CORD, 0.7)])
cords.modifiers.new("Armature", 'ARMATURE').object = rig

bpy.ops.object.select_all(action='DESELECT')
for o in (rig, skirt, hood, flap, buttons, cords):
    o.select_set(True)
glb = os.path.join(out_dir, "slicker.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True, export_animations=False,
                          export_skins=True, export_apply=False, export_yup=True)
print("EXPORTED", glb, len(skirt.data.vertices), "+", len(hood.data.vertices), "+", len(flap.data.vertices), "+",
      len(buttons.data.vertices), "+", len(cords.data.vertices), "verts")

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
