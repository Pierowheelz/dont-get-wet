#!/usr/bin/env python3
"""Write the Godot materials for the environment kit (assets/materials/*.tres) from materials_def.py.

    python3 tools/blender/gen_materials.py

- `pbr`      StandardMaterial3D with albedo/normal/roughness from assets/textures/<tex>/ (Poly Haven 1K),
             uv1_scale = 1 / tile because the Blender generators write UVs in metres.
             desat=True uses a greyscale copy of the albedo (generated here) so it can be tinted.
- `wet`      ShaderMaterial using wet_ground.gdshader (world-space UVs, darkened albedo, low roughness,
             noise puddle mask with animated rain ripples). Used by sidewalk / asphalt_wet.
- `flat`, `glass`, `emissive`, `image`, `decal` as described in materials_def.py.
"""
import os
import sys

from PIL import Image, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from materials_def import MATS  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MAT_DIR = os.path.join(ROOT, "assets", "materials")
TEX = "res://assets/textures/"


def col(c, a=1.0):
    return "Color(%.4f, %.4f, %.4f, %.4f)" % (c[0], c[1], c[2], a)


def tex_paths(name, desat=False):
    base = "%s%s/%s" % (TEX, name, name)
    diff = base + ("_diff_desat_1k.jpg" if desat else "_diff_1k.jpg")
    if desat:
        src = os.path.join(ROOT, "assets", "textures", name, name + "_diff_1k.jpg")
        dst = os.path.join(ROOT, "assets", "textures", name, name + "_diff_desat_1k.jpg")
        if not os.path.exists(dst):
            im = ImageOps.grayscale(Image.open(src)).convert("RGB")
            # re-normalise brightness so the tint colour is close to the final albedo
            im = ImageOps.autocontrast(im, cutoff=1)
            im = im.point(lambda v: int(70 + v * 0.7))
            im.save(dst, quality=90)
    return diff, base + "_nor_gl_1k.jpg", base + "_rough_1k.jpg"


class Res:
    def __init__(self, type_):
        self.type = type_
        self.ext = []
        self.sub = []
        self.props = []

    def ext_res(self, type_, path):
        rid = "%d_%s" % (len(self.ext) + 1, os.path.basename(path).split(".")[0][:12])
        self.ext.append((type_, path, rid))
        return 'ExtResource("%s")' % rid

    def sub_res(self, type_, props):
        rid = "%s_%d" % (type_, len(self.sub) + 1)
        self.sub.append((type_, rid, props))
        return 'SubResource("%s")' % rid

    def write(self, path):
        lines = ['[gd_resource type="%s" load_steps=%d format=3]' % (self.type, len(self.ext) + len(self.sub) + 1), ""]
        for (t, p, rid) in self.ext:
            lines.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, p, rid))
        if self.ext:
            lines.append("")
        for (t, rid, props) in self.sub:
            lines.append('[sub_resource type="%s" id="%s"]' % (t, rid))
            lines += ["%s = %s" % kv for kv in props]
            lines.append("")
        lines.append("[resource]")
        lines += ["%s = %s" % kv for kv in self.props]
        lines.append("")
        with open(path, "w") as f:
            f.write("\n".join(lines))


def standard(name, d):
    r = Res("StandardMaterial3D")
    P = r.props
    P.append(("resource_name", '"%s"' % name))
    kind = d["kind"]
    tint = d.get("tint", (1, 1, 1))
    if kind == "pbr":
        diff, nor, rough = tex_paths(d["tex"], d.get("desat", False))
        P.append(("albedo_color", col(tint)))
        P.append(("albedo_texture", r.ext_res("Texture2D", diff)))
        P.append(("metallic", "%.3f" % d.get("metal", 0.0)))
        P.append(("roughness", "%.3f" % d.get("rough", 1.0)))
        P.append(("roughness_texture", r.ext_res("Texture2D", rough)))
        P.append(("normal_enabled", "true"))
        P.append(("normal_scale", "%.2f" % d.get("normal", 1.0)))
        P.append(("normal_texture", r.ext_res("Texture2D", nor)))
        if not d.get("uv01"):
            s = 1.0 / d.get("tile", 1.0)
            P.append(("uv1_scale", "Vector3(%.4f, %.4f, %.4f)" % (s, s, s)))
    elif kind == "flat":
        P.append(("albedo_color", col(tint)))
        P.append(("metallic", "%.3f" % d.get("metal", 0.0)))
        P.append(("roughness", "%.3f" % d.get("rough", 0.6)))
        if d.get("clearcoat"):
            P.append(("clearcoat_enabled", "true"))
            P.append(("clearcoat", "1.0"))
            P.append(("clearcoat_roughness", "0.08"))
    elif kind == "glass":
        P.append(("transparency", "1"))
        P.append(("albedo_color", col(tint, d.get("alpha", 0.5))))
        P.append(("metallic", "%.3f" % d.get("metal", 0.1)))
        P.append(("metallic_specular", "0.8"))
        P.append(("roughness", "%.3f" % d.get("rough", 0.05)))
    elif kind == "emissive":
        e = d["emit"]
        P.append(("albedo_color", col(tint)))
        P.append(("roughness", "%.3f" % d.get("rough", 0.5)))
        P.append(("emission_enabled", "true"))
        P.append(("emission", col(e[:3])))
        P.append(("emission_energy_multiplier", "%.3f" % e[3]))
    elif kind in ("image", "decal"):
        img = r.ext_res("Texture2D", TEX + "generated/" + d["img"])
        P.append(("albedo_texture", img))
        P.append(("roughness", "%.3f" % d.get("rough", 0.8)))
        if "metal" in d:
            P.append(("metallic", "%.3f" % d["metal"]))
        scissor = d.get("scissor") or d["img"] == "posters.png"
        if kind == "decal" or scissor:
            P.append(("transparency", "2" if scissor else "1"))
            if scissor:
                P.append(("alpha_scissor_threshold", "0.5"))
        if d.get("double"):
            P.append(("cull_mode", "2"))
        if d.get("emit_energy", 0.0) > 0.0:
            P.append(("emission_enabled", "true"))
            P.append(("emission_texture", img))
            if "emit_tint" in d:  # tint = emission colour x texture (operator multiply)
                P.append(("emission", col(d["emit_tint"])))
                P.append(("emission_operator", "1"))
            P.append(("emission_energy_multiplier", "%.3f" % d["emit_energy"]))
            P.append(("albedo_color", col((0.6, 0.6, 0.6))))
        if "tile" in d:
            s = 1.0 / d["tile"]
            P.append(("uv1_scale", "Vector3(%.4f, %.4f, %.4f)" % (s, s, s)))
    P.append(("texture_filter", "5"))  # linear + mipmaps + anisotropic
    r.write(os.path.join(MAT_DIR, name + ".tres"))


def wet(name, d):
    r = Res("ShaderMaterial")
    diff, nor, rough = tex_paths(d["tex"])
    sh = r.ext_res("Shader", "res://assets/materials/wet_ground.gdshader")
    a = r.ext_res("Texture2D", diff)
    n = r.ext_res("Texture2D", nor)
    ro = r.ext_res("Texture2D", rough)
    noise = r.sub_res("FastNoiseLite", [("noise_type", "1"), ("seed", str(abs(hash(name)) % 1000 if False else (7 if name == "sidewalk" else 13))),
                                        ("frequency", "0.012"), ("fractal_octaves", "4"), ("fractal_gain", "0.55")])
    ntex = r.sub_res("NoiseTexture2D", [("width", "512"), ("height", "512"), ("seamless", "true"),
                                        ("seamless_blend_skirt", "0.2"), ("noise", noise)])
    P = r.props
    P.append(("resource_name", '"%s"' % name))
    P.append(("render_priority", "0"))
    P.append(("shader", sh))
    P.append(("shader_parameter/albedo_tex", a))
    P.append(("shader_parameter/normal_tex", n))
    P.append(("shader_parameter/rough_tex", ro))
    P.append(("shader_parameter/puddle_noise", ntex))
    t = d.get("tint", (1, 1, 1))
    P.append(("shader_parameter/tint", "Color(%.3f, %.3f, %.3f, 1)" % t))
    P.append(("shader_parameter/tile_size", "%.3f" % d["tile"]))
    P.append(("shader_parameter/wetness", "%.3f" % d.get("wetness", 1.0)))
    P.append(("shader_parameter/puddle_amount", "%.3f" % d.get("puddles", 0.35)))
    P.append(("shader_parameter/puddle_scale", "%.2f" % (7.0 if name == "sidewalk" else 11.0)))
    P.append(("shader_parameter/world_uv", "true"))
    r.write(os.path.join(MAT_DIR, name + ".tres"))


def shader_mat(name, d):
    r = Res("ShaderMaterial")
    sh = r.ext_res("Shader", d["shader"])
    P = r.props
    P.append(("resource_name", '"%s"' % name))
    P.append(("shader", sh))
    if "tex_param" in d:
        P.append(("shader_parameter/" + d["tex_param"][0], r.ext_res("Texture2D", TEX + "generated/" + d["tex_param"][1])))
    for k, v in d.get("params", {}).items():
        P.append(("shader_parameter/" + k, v))
    r.write(os.path.join(MAT_DIR, name + ".tres"))


def main():
    os.makedirs(MAT_DIR, exist_ok=True)
    for name, d in MATS.items():
        if d["kind"] == "shader":
            shader_mat(name, d)
        elif d["kind"] == "wet":
            wet(name, d)
        else:
            standard(name, d)
    print("wrote %d materials to %s" % (len(MATS), os.path.relpath(MAT_DIR, ROOT)))


if __name__ == "__main__":
    main()
