# Builds the skirt of a long coat skinned to a pedestrian's armature: a flared tube from under the
# jacket hem to below the knee, open at the front from the hem up past the knees. It is weighted to the
# pelvis at the top and to the thighs further down (each side to its own thigh, the back seam shared).
# Usage: blender -b --factory-startup --python build_long_coat.py -- <ped.glb> <out.glb>
import bpy, bmesh, sys, math

src, out = sys.argv[sys.argv.index("--") + 1:][:2]

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=src)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

# Blender frame of the MPFB rig: +Z up, the character faces -Y, his left is +X.
# Rings (z, half width, front depth, back depth): starts inside the jacket (hem at z 0.846) so the
# join is hidden, then flares to the hem.
PROFILE = [(0.93, 0.165, 0.150, 0.085), (0.85, 0.188, 0.166, 0.112), (0.80, 0.205, 0.178, 0.125),
           (0.40, 0.275, 0.215, 0.175)]
CENTRE_Y = -0.02
SEGMENTS = 40          # around; vertex 0 and SEGMENTS are the two edges of the front opening
RING_STEP = 0.035
SLIT_TOP = 0.62        # the front opening closes above this height
LEG_TOP, LEG_FULL, LEG_MAX = 0.92, 0.55, 0.9
SIDE_BLEND = 0.12      # half-width (m) over which the back seam shares the two thighs


def ring_at(z):
    for (z0, *a), (z1, *b) in zip(PROFILE, PROFILE[1:]):
        if z1 <= z <= z0:
            t = (z0 - z) / (z0 - z1)
            return [p + (q - p) * t for p, q in zip(a, b)]
    return PROFILE[-1][1:] if z < PROFILE[-1][0] else PROFILE[0][1:]


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


top, hem = PROFILE[0][0], PROFILE[-1][0]
rings = int(round((top - hem) / RING_STEP))
bm = bmesh.new()
grid = []
weights = {}
for r in range(rings + 1):
    z = top - (top - hem) * r / rings
    half, front, back = ring_at(z)
    row = []
    for j in range(SEGMENTS + 1):
        phi = math.tau * j / SEGMENTS
        x = half * math.sin(phi)
        y = CENTRE_Y - (front if math.cos(phi) > 0.0 else back) * math.cos(phi)
        v = bm.verts.new((x, y, z))
        left = smoothstep(-SIDE_BLEND, SIDE_BLEND, x)
        if math.cos(phi) > 0.0:
            # Below the slit each front panel follows only its own thigh.
            own = 1.0 if j < SEGMENTS / 2 else 0.0
            k = 1.0 - smoothstep(SLIT_TOP, SLIT_TOP + 0.06, z)
            left += (own - left) * k
        leg = LEG_MAX * smoothstep(LEG_TOP, LEG_FULL, z)
        weights[v] = {"pelvis": 1.0 - leg, "thigh_l": leg * left, "thigh_r": leg * (1.0 - left)}
        row.append(v)
    grid.append(row)
for r in range(rings):
    for j in range(SEGMENTS):
        bm.faces.new((grid[r][j], grid[r + 1][j], grid[r + 1][j + 1], grid[r][j + 1]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

mesh = bpy.data.meshes.new("long_coat")
bm.to_mesh(mesh)
order = [v for row in grid for v in row]
bm.free()
coat = bpy.data.objects.new("long_coat", mesh)
bpy.context.collection.objects.link(coat)
coat.parent = rig
for name in ("pelvis", "thigh_l", "thigh_r"):
    g = coat.vertex_groups.new(name=name)
    for i, v in enumerate(order):
        w = weights[v][name]
        if w > 1e-4:
            g.add([i], w, 'REPLACE')
mat = bpy.data.materials.new("long_coat")
mesh.materials.append(mat)
for p in mesh.polygons:
    p.use_smooth = True

bpy.context.view_layer.objects.active = coat
coat.select_set(True)
sol = coat.modifiers.new("Solidify", 'SOLIDIFY')
sol.thickness = 0.012
sol.offset = -1.0
sol.use_rim = True
bpy.ops.object.modifier_apply(modifier=sol.name)
arm = coat.modifiers.new("Armature", 'ARMATURE')
arm.object = rig

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
coat.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=False,
                          export_skins=True, export_apply=False, export_yup=True)
print("EXPORTED", out, len(coat.data.vertices), "verts")
