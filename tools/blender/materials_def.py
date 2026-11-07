"""Shared material table for the environment kit.

Pure Python (no bpy) so it can be imported both by the Blender generators (which only need a
preview colour + the material *name*) and by gen_materials.py (which writes the Godot .tres files).

Every Blender material name used by the generators must exist here. In Godot the post-import
script (assets/buildings/kit_import.gd) replaces each imported material whose name matches
res://assets/materials/<name>.tres with that resource, so the .glb files stay small (no embedded
textures) and all modules share the same textured materials.

Keys:
  kind     pbr | flat | glass | emissive | image | wet | decal
  tex      Poly Haven texture folder in assets/textures/ (pbr / wet)
  tile     metres covered by one texture repeat (UVs are generated in metres)
  tint     albedo multiplier (pbr) or albedo colour (flat/glass)
  rough    roughness (flat) or roughness multiplier (pbr)
  metal    metallic
  emit     (r, g, b, energy) emission
  alpha    transparency (glass / decal)
  img      generated image in assets/textures/generated/ (image / decal kinds); UVs are 0..1
  preview  colour used for the Blender material (fallback look if the remap is not applied)
"""

MATS = {
    # --- walls / masonry -------------------------------------------------------------------
    "brick_red":      dict(kind="pbr", tex="red_brick", tile=1.4, tint=(0.80, 0.74, 0.72), rough=1.0, preview=(0.45, 0.2, 0.15)),
    "brick_brown":    dict(kind="pbr", tex="brick_wall_02", tile=2.0, tint=(0.78, 0.68, 0.60), rough=1.0, preview=(0.35, 0.25, 0.2)),
    "brick_dark":     dict(kind="pbr", tex="brick_wall_02", tile=2.0, tint=(0.42, 0.38, 0.36), rough=1.0, preview=(0.2, 0.17, 0.15)),
    "brick_painted":  dict(kind="pbr", tex="red_brick", tile=1.4, tint=(0.62, 0.66, 0.62), rough=1.0, preview=(0.5, 0.52, 0.5), desat=True),
    "plaster":        dict(kind="pbr", tex="worn_plaster_wall", tile=1.8, tint=(0.82, 0.78, 0.70), rough=1.0, preview=(0.6, 0.57, 0.5)),
    "plaster_teal":   dict(kind="pbr", tex="worn_plaster_wall", tile=1.8, tint=(0.45, 0.62, 0.60), rough=1.0, preview=(0.3, 0.45, 0.43)),
    "plaster_ochre":  dict(kind="pbr", tex="worn_plaster_wall", tile=1.8, tint=(0.92, 0.72, 0.45), rough=1.0, preview=(0.7, 0.5, 0.3)),
    "concrete":       dict(kind="pbr", tex="concrete_wall_006", tile=2.0, tint=(0.85, 0.84, 0.82), rough=1.0, preview=(0.5, 0.5, 0.48)),
    "stone_trim":     dict(kind="pbr", tex="concrete_wall_006", tile=1.2, tint=(1.15, 1.10, 1.00), rough=0.9, preview=(0.7, 0.68, 0.62)),
    "terrazzo":       dict(kind="pbr", tex="terrazzo_tiles", tile=1.0, tint=(0.95, 0.92, 0.88), rough=0.6, preview=(0.55, 0.45, 0.4)),
    "terrazzo_green": dict(kind="pbr", tex="terrazzo_tiles", tile=1.0, tint=(0.55, 0.85, 0.75), rough=0.6, preview=(0.3, 0.5, 0.42), desat=True),
    "curb":           dict(kind="pbr", tex="dirty_concrete", tile=1.5, tint=(0.62, 0.61, 0.6), rough=0.55, preview=(0.45, 0.45, 0.44)),
    "sidewalk":       dict(kind="wet", tex="concrete_pavement", tile=1.8, tint=(0.80, 0.79, 0.77), wetness=0.85, puddles=0.30, preview=(0.35, 0.35, 0.35)),
    "asphalt_wet":    dict(kind="wet", tex="asphalt_02", tile=3.0, tint=(0.70, 0.70, 0.72), wetness=1.0, puddles=0.42, preview=(0.1, 0.1, 0.11)),
    # --- metals -----------------------------------------------------------------------------
    "roller_door":    dict(kind="pbr", tex="green_metal_rust", tile=1.0, tint=(0.62, 0.64, 0.66), rough=0.9, metal=0.3, desat=True, preview=(0.35, 0.37, 0.38)),
    "roller_door_blue": dict(kind="pbr", tex="green_metal_rust", tile=1.0, tint=(0.40, 0.55, 0.85), rough=0.9, metal=0.3, desat=True, preview=(0.2, 0.3, 0.45)),
    "metal_rust":     dict(kind="pbr", tex="green_metal_rust", tile=0.8, tint=(0.75, 0.42, 0.25), rough=1.0, metal=0.2, desat=True, preview=(0.4, 0.22, 0.12)),
    "metal_green":    dict(kind="pbr", tex="green_metal_rust", tile=0.8, tint=(0.75, 0.85, 0.75), rough=0.9, metal=0.2, preview=(0.15, 0.3, 0.2)),
    "metal_dark":     dict(kind="flat", tint=(0.06, 0.06, 0.065), rough=0.45, metal=0.6, preview=(0.06, 0.06, 0.065)),
    "aluminium":      dict(kind="flat", tint=(0.55, 0.56, 0.58), rough=0.32, metal=0.9, preview=(0.55, 0.56, 0.58)),
    "chrome":         dict(kind="flat", tint=(0.85, 0.86, 0.88), rough=0.1, metal=1.0, preview=(0.85, 0.86, 0.88)),
    "brass":          dict(kind="flat", tint=(0.62, 0.45, 0.22), rough=0.35, metal=1.0, preview=(0.62, 0.45, 0.22)),
    "galvanized":     dict(kind="pbr", tex="green_metal_rust", tile=0.6, tint=(0.62, 0.64, 0.66), rough=0.7, metal=0.7, desat=True, preview=(0.5, 0.5, 0.52)),
    # --- painted trim -----------------------------------------------------------------------
    "trim_cream":     dict(kind="flat", tint=(0.66, 0.62, 0.52), rough=0.55, preview=(0.66, 0.62, 0.52)),
    "trim_green":     dict(kind="flat", tint=(0.08, 0.18, 0.14), rough=0.5, preview=(0.08, 0.18, 0.14)),
    "trim_red":       dict(kind="flat", tint=(0.36, 0.08, 0.06), rough=0.5, preview=(0.36, 0.08, 0.06)),
    "trim_dark":      dict(kind="flat", tint=(0.07, 0.07, 0.07), rough=0.5, preview=(0.07, 0.07, 0.07)),
    "trim_white":     dict(kind="flat", tint=(0.72, 0.72, 0.68), rough=0.5, preview=(0.72, 0.72, 0.68)),
    "trim_blue":      dict(kind="flat", tint=(0.10, 0.18, 0.30), rough=0.5, preview=(0.10, 0.18, 0.30)),
    "sign_board":     dict(kind="pbr", tex="worn_plaster_wall", tile=2.5, tint=(0.62, 0.58, 0.50), rough=0.8, preview=(0.45, 0.42, 0.36)),
    "sign_face":      dict(kind="pbr", tex="worn_plaster_wall", tile=2.5, tint=(0.62, 0.58, 0.50), rough=0.8, uv01=True, preview=(0.45, 0.42, 0.36)),
    "sign_board_dark": dict(kind="pbr", tex="worn_plaster_wall", tile=2.5, tint=(0.18, 0.2, 0.2), rough=0.8, preview=(0.15, 0.16, 0.16)),
    # --- wood -------------------------------------------------------------------------------
    "wood_boards":    dict(kind="pbr", tex="weathered_planks", tile=2.0, tint=(0.75, 0.70, 0.62), rough=1.0, preview=(0.35, 0.3, 0.25)),
    "plywood":        dict(kind="pbr", tex="plywood", tile=1.2, tint=(0.9, 0.8, 0.66), rough=1.0, preview=(0.5, 0.42, 0.3)),
    "wood_dark":      dict(kind="pbr", tex="weathered_planks", tile=1.5, tint=(0.40, 0.30, 0.24), rough=0.8, preview=(0.2, 0.15, 0.1)),
    # --- glass ------------------------------------------------------------------------------
    "glass_lit":      dict(kind="glass", tint=(0.75, 0.70, 0.60), alpha=0.12, rough=0.04, preview=(0.8, 0.7, 0.5)),
    "glass_dark":     dict(kind="glass", tint=(0.03, 0.035, 0.04), alpha=0.82, rough=0.05, metal=0.3, preview=(0.03, 0.035, 0.04)),
    "glass_dirty":    dict(kind="glass", tint=(0.22, 0.22, 0.19), alpha=0.42, rough=0.25, preview=(0.12, 0.12, 0.1)),
    "glass_car":      dict(kind="glass", tint=(0.04, 0.05, 0.06), alpha=0.9, rough=0.03, metal=0.3, preview=(0.04, 0.05, 0.06)),
    # --- emissive / light sources -----------------------------------------------------------
    "lamp_bulb":      dict(kind="emissive", tint=(1.0, 0.85, 0.6), emit=(1.0, 0.72, 0.38, 5.0), preview=(1.0, 0.8, 0.5)),
    "sodium_lamp":    dict(kind="emissive", tint=(1.0, 0.7, 0.3), emit=(1.0, 0.55, 0.16, 2.6), preview=(1.0, 0.6, 0.2)),
    "fire_glow":      dict(kind="emissive", tint=(1.0, 0.5, 0.1), emit=(1.0, 0.38, 0.08, 6.0), preview=(1.0, 0.4, 0.1)),
    "tail_light":     dict(kind="emissive", tint=(0.5, 0.03, 0.03), emit=(0.8, 0.03, 0.02, 0.6), rough=0.2, preview=(0.6, 0.05, 0.05)),
    "headlight":      dict(kind="emissive", tint=(0.9, 0.9, 0.85), emit=(1.0, 0.92, 0.75, 0.12), rough=0.1, preview=(0.9, 0.9, 0.85)),
    "interior_warm":  dict(kind="emissive", tint=(0.55, 0.36, 0.2), emit=(1.0, 0.62, 0.32, 0.55), rough=0.9, preview=(0.6, 0.4, 0.25)),
    "interior_dark":  dict(kind="flat", tint=(0.035, 0.032, 0.03), rough=0.95, preview=(0.04, 0.035, 0.03)),
    # --- painted images (generated by gen_textures.py) -------------------------------------
    "interior_diner":      dict(kind="image", img="interior_diner.png", emit_energy=1.3, preview=(0.8, 0.6, 0.4)),
    "interior_laundromat": dict(kind="image", img="interior_laundromat.png", emit_energy=1.05, preview=(0.7, 0.75, 0.7)),
    "interior_pawn":       dict(kind="image", img="interior_pawn.png", emit_energy=1.25, preview=(0.7, 0.5, 0.3)),
    "interior_barber":     dict(kind="image", img="interior_barber.png", emit_energy=0.95, preview=(0.75, 0.65, 0.55)),
    "interior_newsstand":  dict(kind="image", img="interior_newsstand.png", emit_energy=1.2, preview=(0.75, 0.6, 0.4)),
    "interior_hotel":      dict(kind="image", img="interior_hotel.png", emit_energy=1.25, preview=(0.7, 0.5, 0.3)),
    "interior_empty":      dict(kind="image", img="interior_empty.png", emit_energy=0.3, preview=(0.1, 0.09, 0.08)),
    "window_lit":          dict(kind="image", img="window_lit.png", emit_energy=1.3, preview=(0.9, 0.6, 0.3)),
    "window_lit_b":        dict(kind="image", img="window_lit_b.png", emit_energy=1.1, preview=(0.8, 0.55, 0.35)),
    "window_dark":         dict(kind="image", img="window_dark.png", emit_energy=0.0, preview=(0.05, 0.05, 0.05)),
    "posters":             dict(kind="image", img="posters.png", emit_energy=0.0, rough=0.85, preview=(0.7, 0.65, 0.55)),
    "ghost_sign":          dict(kind="decal", img="ghost_sign.png", alpha=1.0, rough=0.9, preview=(0.7, 0.65, 0.55)),
    "awning_canvas":       dict(kind="image", img="awning_canvas.png", emit_energy=0.0, rough=0.9, tile=1.0, preview=(0.5, 0.15, 0.1)),
    # --- props ------------------------------------------------------------------------------
    "paint_red":      dict(kind="pbr", tex="green_metal_rust", tile=0.5, tint=(0.75, 0.18, 0.12), rough=0.75, desat=True, preview=(0.5, 0.1, 0.08)),
    "paint_blue":     dict(kind="pbr", tex="green_metal_rust", tile=0.5, tint=(0.20, 0.32, 0.55), rough=0.6, desat=True, preview=(0.12, 0.2, 0.35)),
    "paint_yellow":   dict(kind="pbr", tex="green_metal_rust", tile=0.5, tint=(0.85, 0.62, 0.12), rough=0.6, desat=True, preview=(0.7, 0.5, 0.1)),
    "paint_green":    dict(kind="pbr", tex="green_metal_rust", tile=0.5, tint=(0.75, 0.9, 0.78), rough=0.6, preview=(0.1, 0.25, 0.15)),
    "street_blade":   dict(kind="flat", tint=(0.04, 0.22, 0.12), rough=0.4, preview=(0.04, 0.22, 0.12)),
    "plastic_beige":  dict(kind="flat", tint=(0.55, 0.52, 0.45), rough=0.6, preview=(0.55, 0.52, 0.45)),
    "rubber":         dict(kind="flat", tint=(0.025, 0.025, 0.025), rough=0.75, preview=(0.025, 0.025, 0.025)),
    "car_paint_teal": dict(kind="flat", tint=(0.12, 0.30, 0.30), rough=0.22, metal=0.25, clearcoat=True, preview=(0.12, 0.3, 0.3)),
    "car_paint_cream": dict(kind="flat", tint=(0.62, 0.58, 0.48), rough=0.25, metal=0.15, clearcoat=True, preview=(0.62, 0.58, 0.48)),
    "car_paint_maroon": dict(kind="flat", tint=(0.28, 0.05, 0.06), rough=0.22, metal=0.25, clearcoat=True, preview=(0.28, 0.05, 0.06)),
    "car_interior":   dict(kind="flat", tint=(0.10, 0.07, 0.06), rough=0.8, preview=(0.1, 0.07, 0.06)),
    "trash_bag":      dict(kind="flat", tint=(0.015, 0.016, 0.018), rough=0.25, preview=(0.02, 0.02, 0.02)),
    "cardboard":      dict(kind="pbr", tex="plywood", tile=0.8, tint=(0.62, 0.45, 0.28), rough=1.0, preview=(0.45, 0.32, 0.2)),
}


def preview(name):
    return MATS[name].get("preview", (0.5, 0.5, 0.5))
