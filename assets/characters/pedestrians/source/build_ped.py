# Builds one pedestrian GLB from MakeHuman/MPFB2 assets, described by a JSON spec (see peds_spec.json).
# Usage: BLENDER_USER_RESOURCES=<profile with MPFB 2.0.18 + asset packs> \
#        blender -b --python build_ped.py -- <peds_spec.json> <ped id> <out.glb>
import bpy, sys, json

spec_path, ped_id, out = sys.argv[sys.argv.index("--") + 1:][:3]
spec = json.load(open(spec_path))[ped_id]

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.exportservice import ExportService

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

info = HumanService._create_default_human_info_dict()
info["name"] = "ped"
info["phenotype"].update(spec["phenotype"])
info["phenotype"]["race"] = spec.get("race", {"asian": 0.1, "caucasian": 0.8, "african": 0.1})
info["rig"] = "game_engine"
info["eyes"] = "high-poly/high-poly.mhclo"
info["eyebrows"] = spec.get("eyebrows", "eyebrow001/eyebrow001.mhclo")
info["eyelashes"] = "eyelashes01/eyelashes01.mhclo"
info["hair"] = spec.get("hair", "")
info["clothes"] = spec["clothes"]
info["skin_mhmat"] = spec["skin"]
info["skin_material_type"] = "GAMEENGINE"
info["eyes_material_type"] = "GAMEENGINE"
info["clothes_material_type"] = "GAMEENGINE"

settings = HumanService.get_default_deserialization_settings()
settings["subdiv_levels"] = 0
basemesh = HumanService.deserialize_from_dict(info, settings)
ExportService.bake_modifiers_remove_helpers(basemesh, bake_masks=True, bake_subdiv=False, remove_helpers=True, also_proxy=False)

rig = basemesh.parent
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
total = 0
for o in meshes:
    bpy.context.view_layer.objects.active = o
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    o.select_set(True)
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(o.modifiers):
        if m.type == 'MASK':
            bpy.ops.object.modifier_apply(modifier=m.name)
        elif m.type == 'SUBSURF':
            o.modifiers.remove(m)
    for key, ratio in spec.get("decimate", {}).items():
        if key in o.name:
            dec = o.modifiers.new("Decimate", 'DECIMATE')
            dec.ratio = ratio
            while o.modifiers.find("Decimate") > 0:
                bpy.ops.object.modifier_move_up(modifier="Decimate")
            bpy.ops.object.modifier_apply(modifier="Decimate")
    bpy.ops.object.shade_smooth()
    total += sum(len(p.vertices) - 2 for p in o.data.polygons)  # triangles
    print("MESH", o.name, len(o.data.polygons))
print("TRIS", total)

# Cap texture size to keep the GLBs small.
for img in bpy.data.images:
    if img.size[0] > 1024 or img.size[1] > 1024:
        f = 1024.0 / max(img.size[0], img.size[1])
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))

zs = [(o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices]
print("HEIGHT", max(zs), min(zs))

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
for o in meshes:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=False,
                          export_skins=True, export_apply=False, export_yup=True, export_image_format='WEBP',
                          export_image_quality=82)
print("EXPORTED", out)
