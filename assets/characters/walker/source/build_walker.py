# Builds walker.glb from MakeHuman/MPFB2 CC0 system assets.
# Usage: BLENDER_USER_RESOURCES=<dir with MPFB 2.0.18 + makehuman_system_assets_cc0 installed> \
#        blender -b --python build_walker.py -- <out.glb>
import bpy, sys, math
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.exportservice import ExportService
from bl_ext.user_default.mpfb.services.objectservice import ObjectService

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

info = HumanService._create_default_human_info_dict()
info["name"] = "walker"
info["phenotype"].update({"gender": 1.0, "age": 0.62, "muscle": 0.5, "weight": 0.56,
                          "proportions": 0.6, "height": float(__import__("os").environ.get("WALKER_HEIGHT", "0.55"))})
info["phenotype"]["race"] = {"asian": 0.05, "caucasian": 0.85, "african": 0.10}
info["rig"] = "game_engine"
info["eyes"] = "high-poly/high-poly.mhclo"
info["eyebrows"] = "eyebrow001/eyebrow001.mhclo"
info["eyelashes"] = "eyelashes01/eyelashes01.mhclo"
info["teeth"] = "teeth_base/teeth_base.mhclo"
info["hair"] = "short02/short02.mhclo"
info["clothes"] = ["male_elegantsuit01/male_elegantsuit01.mhclo", "shoes04/shoes04.mhclo"]
info["skin_mhmat"] = "middleage_caucasian_male/middleage_caucasian_male.mhmat"
info["skin_material_type"] = "GAMEENGINE"
info["eyes_material_type"] = "GAMEENGINE"
info["clothes_material_type"] = "GAMEENGINE"

settings = HumanService.get_default_deserialization_settings()
settings["subdiv_levels"] = 0
basemesh = HumanService.deserialize_from_dict(info, settings)

ExportService.bake_modifiers_remove_helpers(basemesh, bake_masks=True, bake_subdiv=False, remove_helpers=True, also_proxy=False)

rig = basemesh.parent
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in meshes:
    bpy.context.view_layer.objects.active = o
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    o.select_set(True)
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(o.modifiers):
        if m.type in ('MASK',):
            bpy.ops.object.modifier_apply(modifier=m.name)
        elif m.type == 'SUBSURF':
            o.modifiers.remove(m)
    # Smooth: one subdivision level on body, suit and hair (not eyes/teeth/brows/lashes)
    n = o.name.lower()
    if any(k in n for k in ("body", "suit", "shoes", "short02")):
        sub = o.modifiers.new("Sub", 'SUBSURF')
        sub.levels = 1
        sub.render_levels = 1
        # move before armature
        while o.modifiers.find("Sub") > 0:
            bpy.ops.object.modifier_move_up(modifier="Sub")
        bpy.ops.object.modifier_apply(modifier="Sub")
    bpy.ops.object.shade_smooth()
    print("MESH", o.name, len(o.data.polygons), [m.type for m in o.modifiers], [s.material.name if s.material else None for s in o.material_slots])

# report height
zs = []
for o in meshes:
    for v in o.data.vertices:
        zs.append((o.matrix_world @ v.co).z)
print("HEIGHT", max(zs), min(zs))
print("BONES", [b.name for b in rig.data.bones])

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
for o in meshes:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=False,
                          export_skins=True, export_apply=False, export_yup=True, export_image_format='WEBP',
                          export_image_quality=88)
print("EXPORTED", out)
