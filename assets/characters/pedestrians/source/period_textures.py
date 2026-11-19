#!/usr/bin/env python3
"""1960s dress for the pedestrians without rebuilding their models: reads the clothing albedo
embedded in models/ped_*.glb and writes repainted copies to textures/, which the ped_*.tscn scenes
apply over the model's own (ped.gd `albedo_overrides`). Denim becomes plain wool trousers, trainers
become dark leather shoes.
Run: python3 assets/characters/pedestrians/source/period_textures.py   (needs Pillow + numpy)"""
import io, json, os, struct
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "models")
OUT = os.path.join(HERE, "..", "textures")


def embedded(glb: str, image: str) -> Image.Image:
    b = open(os.path.join(MODELS, glb), "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    im = next(i for i in j["images"] if i.get("name") == image)
    bv = j["bufferViews"][im["bufferView"]]
    at = 20 + jl + 8 + bv.get("byteOffset", 0)
    return Image.open(io.BytesIO(b[at:at + bv["byteLength"]])).convert("RGBA")


def wool(img: Image.Image, colour, only_blue: bool, contrast=0.3) -> Image.Image:
    """Flatten the cloth's fades and creases to `contrast` and dye it `colour` (linear-ish 0..1 RGB at
    the cloth's mean brightness). `only_blue` leaves everything that isn't denim blue as it was."""
    a = np.asarray(img).astype(np.float32) / 255.0
    rgb = a[..., :3]
    lum = rgb @ np.array([0.3, 0.59, 0.11], np.float32)
    if only_blue:
        mask = ((rgb[..., 2] > rgb[..., 0] * 1.12) & (lum > 0.08)).astype(np.float32)
        mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))) / 255.0
    else:
        mask = np.ones_like(lum)
    mean = float((lum * mask).sum() / max(mask.sum(), 1.0))
    weave = np.clip(1.0 + (lum - mean) / max(mean, 0.05) * contrast, 0.55, 1.45)
    dyed = np.clip(weave[..., None] * np.array(colour, np.float32), 0.0, 1.0)
    out = rgb * (1.0 - mask[..., None]) + dyed * mask[..., None]
    res = np.concatenate([out, a[..., 3:]], axis=-1)
    return Image.fromarray((res * 255.0 + 0.5).astype(np.uint8), "RGBA")


def muted(img: Image.Image, keep: float) -> Image.Image:
    """Pull every colour toward its own grey, keeping `keep` of the saturation."""
    a = np.asarray(img).astype(np.float32)
    lum = a[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
    a[..., :3] = lum[..., None] + (a[..., :3] - lum[..., None]) * keep
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), "RGBA")


def save(img: Image.Image, name: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    img.convert("RGB").save(os.path.join(OUT, name), "WEBP", quality=88, method=6)
    print("wrote", name)


# The whole sheet is one tintable grey wool: the scene's tint_options pick the trouser colour.
save(wool(embedded("ped_hoodie.glb", "male_casualsuit01_diffuse"), (0.42, 0.42, 0.42), False),
     "hoodie_trousers.webp")
save(wool(embedded("ped_hoodie.glb", "shoes05_diffuse"), (0.11, 0.075, 0.055), False, 0.5),
     "hoodie_shoes.webp")
save(wool(embedded("ped_man_jacket.glb", "male_casualsuit05_diffuse"), (0.17, 0.16, 0.16), True),
     "man_jacket_clothes.webp")
save(muted(wool(embedded("ped_smoker.glb", "male_casualsuit03_diffuse"), (0.2, 0.17, 0.13), True), 0.5),
     "smoker_clothes.webp")
