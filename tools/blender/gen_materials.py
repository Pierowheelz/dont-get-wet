#!/usr/bin/env python3
"""Write the Godot materials for the environment kit (assets/materials/*.tres) from materials_def.py.

    python3 tools/blender/gen_materials.py

- `pbr`      StandardMaterial3D with albedo/normal/roughness from assets/textures/<tex>/ (Poly Haven 1K),
             uv1_scale = 1 / tile because the Blender generators write UVs in metres.
             desat=True uses a greyscale copy of the albedo (generated here) so it can be tinted.
             wide=N uses a re-laid copy of the texture set covering N x N tiles (generated here, see
             widen) and maps it in world space, so a wall shows no repeat within N * tile metres
             and stacked or neighbouring modules do not show the same patch.
- `wet`      ShaderMaterial using wet_ground.gdshader (world-space UVs, darkened albedo, low roughness,
             noise puddle mask with animated rain ripples). Used by sidewalk / asphalt_wet.
- `flat`, `glass`, `emissive`, `image`, `decal` as described in materials_def.py.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from materials_def import MATS  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MAT_DIR = os.path.join(ROOT, "assets", "materials")
TEX = "res://assets/textures/"


def col(c, a=1.0):
    return "Color(%.4f, %.4f, %.4f, %.4f)" % (c[0], c[1], c[2], a)


def tex_paths(name, desat=False, wide=0):
    base = "%s%s/%s" % (TEX, name, name)
    if wide:
        widen(name, wide)
        return base + "_diff_wide.jpg", base + "_nor_gl_wide.jpg", base + "_rough_wide.jpg"
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


def widen(name, n, size=2048, cells=7):
    """Write <name>_{diff,nor_gl,rough}_wide.jpg: an n x n tile area of the texture re-laid as
    irregular patches, each a differently shifted (and sometimes mirrored) window of the source,
    so its recognisable marks stop landing on a grid. Most patches use a calmed copy with the dark
    marks filled in, which leaves the damage in scattered clusters instead of all over the wall.
    Tileable; the three maps share one layout."""
    folder = os.path.join(ROOT, "assets", "textures", name)
    maps = ("diff", "nor_gl", "rough")
    out = [os.path.join(folder, "%s_%s_wide.jpg" % (name, m)) for m in maps]
    if all(os.path.exists(p) for p in out):
        return
    rng = np.random.default_rng(1960)
    s = size // n                                   # source tile edge in output pixels
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    wx, wy = x.copy(), y.copy()
    for _ in range(6):                              # periodic wobble so patch edges are not straight
        kx, ky = rng.integers(-5, 6, 2)
        ph, amp = rng.uniform(0, 2 * np.pi, 2), rng.uniform(0.008, 0.02, 2) * size
        arg = 2 * np.pi * (kx * x + ky * y) / size
        wx += amp[0] * np.sin(arg + ph[0])
        wy += amp[1] * np.sin(arg + ph[1])
    # one seed per jittered grid cell; nearest and second-nearest seed for every pixel (wrapping)
    g = size / cells
    seeds = [((i + rng.uniform(0.15, 0.85)) * g, (j + rng.uniform(0.15, 0.85)) * g) for i in range(cells) for j in range(cells)]
    d1 = np.full((size, size), 1e9, np.float32)
    d2 = d1.copy()
    i1 = np.zeros((size, size), np.int32)
    i2 = i1.copy()
    for k, (sx, sy) in enumerate(seeds):
        dx = np.abs(wx - sx) % size
        dy = np.abs(wy - sy) % size
        d = np.hypot(np.minimum(dx, size - dx), np.minimum(dy, size - dy))
        near, mid = d < d1, (d >= d1) & (d < d2)
        d2 = np.where(near, d1, np.where(mid, d, d2))
        i2 = np.where(near, i1, np.where(mid, k, i2))
        d1 = np.where(near, d, d1)
        i1 = np.where(near, k, i1)
    w1 = 0.5 + 0.5 * np.clip((d2 - d1) / (0.012 * size), 0.0, 1.0)   # soft seam about 2.5 cm of wall wide
    w1 = (w1 * w1 * (3 - 2 * w1))[..., None]
    off = rng.integers(0, s, (len(seeds), 2))
    mirror = rng.random(len(seeds)) < 0.5
    worn = rng.random(len(seeds)) < 0.3
    xi, yi = x.astype(np.int32), y.astype(np.int32)

    def load(m):
        return np.asarray(Image.open(os.path.join(folder, "%s_%s_1k.jpg" % (name, m))).convert("RGB").resize((s, s), Image.LANCZOS), np.float32)

    def blur(a, r):                                 # wrapping gaussian, done in frequency space
        f = np.fft.fftfreq(s)
        k = np.exp(-2 * (np.pi * r) ** 2 * (f[:, None] ** 2 + f[None, :] ** 2))
        k = k.reshape(k.shape + (1,) * (a.ndim - 2))
        return np.fft.ifft2(np.fft.fft2(a, axes=(0, 1)) * k, axes=(0, 1)).real.astype(np.float32)

    lum = load("diff").mean(-1)
    dark = np.clip((np.median(lum) - lum - 8.0) / 14.0, 0.0, 1.0)       # the marks are darker than the plaster
    dark = np.clip(blur(dark, s / 170) * 2.5, 0.0, 1.0)[..., None]
    for m, path in zip(maps, out):
        src = load(m)
        if m == "nor_gl":
            fill = np.array((128.0, 128.0, 255.0), np.float32)
        else:                                       # the surrounding plaster, spread across each mark
            fill = blur(src * (1 - dark), s / 12) / np.maximum(blur(1 - dark, s / 12), 1e-3)
            grain = np.roll(src - blur(src, s / 250), (s // 2, s // 3), (0, 1)) * np.roll(1 - dark, (s // 2, s // 3), (0, 1))
            fill = fill + grain
        calm = src * (1 - dark) + fill * dark

        def patch(idx):
            u = (np.where(mirror[idx], -xi - 1, xi) + off[idx, 0]) % s
            v = (yi + off[idx, 1]) % s
            px = np.where(worn[idx][..., None], src[v, u], calm[v, u])
            if m == "nor_gl":                       # a mirrored patch leans the other way in X
                px = np.where(mirror[idx][..., None], px * (-1, 1, 1) + (255, 0, 0), px)
            return px
        im = patch(i1) * w1 + patch(i2) * (1 - w1)
        im = Image.fromarray(np.clip(im + 0.5, 0, 255).astype(np.uint8))
        if m != "diff":                             # relief and roughness hold up at half size
            im = im.resize((size // 2, size // 2), Image.LANCZOS)
        im.save(path, quality=90)


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
        wide = d.get("wide", 0)
        diff, nor, rough = tex_paths(d["tex"], d.get("desat", False), wide)
        P.append(("albedo_color", col(tint)))
        P.append(("albedo_texture", r.ext_res("Texture2D", diff)))
        P.append(("metallic", "%.3f" % d.get("metal", 0.0)))
        P.append(("roughness", "%.3f" % d.get("rough", 1.0)))
        P.append(("roughness_texture", r.ext_res("Texture2D", rough)))
        P.append(("normal_enabled", "true"))
        P.append(("normal_scale", "%.2f" % d.get("normal", 1.0)))
        P.append(("normal_texture", r.ext_res("Texture2D", nor)))
        if not d.get("uv01"):
            s = 1.0 / (d.get("tile", 1.0) * max(wide, 1))
            P.append(("uv1_scale", "Vector3(%.4f, %.4f, %.4f)" % (s, s, s)))
        if wide:
            P.append(("uv1_triplanar", "true"))
            P.append(("uv1_world_triplanar", "true"))
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
