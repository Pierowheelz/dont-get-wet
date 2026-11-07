#!/usr/bin/env python3
"""Generate the painted textures used by the kit (shop interiors, lit windows, posters, ghost sign,
awning canvas, optional painted 60s shop signs). Pure Python + Pillow, deterministic (fixed seeds).

    python3 tools/blender/gen_textures.py

Output: assets/textures/generated/*.png  (all original work, no third-party content).
Interior images are ORTHOGRAPHIC elevations of a shop's back wall: the 3D interior box in each
module supplies the perspective (floor, ceiling, side walls), this image is what hangs on the back.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops, ImageEnhance

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "generated")
SIGNS = os.path.join(ROOT, "assets", "textures", "signs")

FONT_CANDIDATES = {
    "narrow": ["/usr/share/fonts/urw-base35/NimbusSansNarrow-Bold.otf",
               "/usr/share/fonts/dejavu-sans-fonts/DejaVuSansCondensed-Bold.ttf"],
    "sans": ["/usr/share/fonts/urw-base35/NimbusSans-Bold.otf",
             "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf"],
    "serif": ["/usr/share/fonts/urw-base35/C059-Bold.otf",
              "/usr/share/fonts/urw-base35/NimbusRoman-Bold.otf"],
    "script": ["/usr/share/fonts/urw-base35/Z003-MediumItalic.otf",
               "/usr/share/fonts/urw-base35/C059-BdIta.otf"],
}


def font(kind, size):
    for p in FONT_CANDIDATES[kind]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


_NOISE_SEED = [1000]


def seeded_noise(size, sigma):
    """Deterministic replacement for Image.effect_noise (grey 'L' image, mean 128)."""
    _NOISE_SEED[0] += 1
    rng = random.Random(_NOISE_SEED[0])
    w, h = size
    data = bytes(max(0, min(255, int(128 + rng.gauss(0, sigma)))) for _ in range(w * h))
    return Image.frombytes("L", (w, h), data)


def painterly(im, strength=1.0, seed=0):
    """Cheap 'painted' look: soften, mode filter (blobby strokes), subtle canvas noise."""
    rng = random.Random(seed)
    w, h = im.size
    mode = im.mode
    rgb = im.convert("RGB")
    rgb = rgb.filter(ImageFilter.GaussianBlur(1.2 * strength))
    rgb = rgb.filter(ImageFilter.ModeFilter(int(5 + 4 * strength)))
    rgb = rgb.filter(ImageFilter.SMOOTH_MORE)
    # brush-stroke noise
    noise = seeded_noise((w // 4, h // 4), 24).resize((w, h), Image.BICUBIC).convert("RGB")
    rgb = ImageChops.blend(rgb, ImageChops.multiply(rgb, ImageChops.invert(noise).point(lambda v: 255 - v // 5)), 0.6)
    if mode == "RGBA":
        out = rgb.convert("RGBA")
        out.putalpha(im.getchannel("A"))
        return out
    return rgb


def glow(draw_im, cx, cy, r, color, alpha=160):
    lay = Image.new("RGBA", draw_im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k in range(12, 0, -1):
        rr = r * k / 12
        a = int(alpha * (1 - k / 13) ** 1.6)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=color + (a,))
    draw_im.alpha_composite(lay)


def vgrad(w, h, top, bottom):
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im


def save(im, name, folder=OUT):
    os.makedirs(folder, exist_ok=True)
    im.save(os.path.join(folder, name), optimize=True)
    print("wrote", os.path.join(os.path.relpath(folder, ROOT), name), im.size)


# ------------------------------------------------------------------------------------------------
# interiors (back-wall elevations, 1024 x 512 ~ 6 m x 3 m)
# ------------------------------------------------------------------------------------------------
W, H = 1024, 512


def interior_diner():
    rng = random.Random(1)
    im = vgrad(W, H, (205, 160, 105), (150, 95, 55)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # cream tiles lower wall + red band
    d.rectangle([0, 250, W, H], fill=(214, 196, 160))
    for x in range(0, W, 22):
        d.line([(x, 250), (x, H)], fill=(190, 172, 140), width=2)
    for y in range(250, H, 22):
        d.line([(0, y), (W, y)], fill=(190, 172, 140), width=2)
    d.rectangle([0, 238, W, 256], fill=(150, 30, 25))
    # kitchen pass-through (bright)
    d.rectangle([380, 120, 700, 235], fill=(255, 236, 190))
    d.rectangle([380, 225, 700, 238], fill=(170, 170, 175))
    for k in range(5):
        x = 400 + k * 60
        d.rectangle([x, 200, x + 40, 224], fill=(240, 240, 235))  # plates
    # menu boards
    for bx in (60, 760):
        d.rectangle([bx, 60, bx + 220, 200], fill=(35, 30, 28))
        for k in range(8):
            y = 78 + k * 15
            d.line([(bx + 14, y), (bx + 14 + rng.randint(90, 150), y)], fill=(230, 225, 210), width=4)
            d.line([(bx + 180, y), (bx + 205, y)], fill=(230, 200, 120), width=4)
    # clock
    d.ellipse([310, 70, 360, 120], fill=(240, 235, 220), outline=(40, 40, 40), width=4)
    d.line([(335, 95), (335, 78)], fill=(20, 20, 20), width=3)
    d.line([(335, 95), (348, 100)], fill=(20, 20, 20), width=3)
    # back counter with pie case, coffee urns
    d.rectangle([0, 330, W, 380], fill=(200, 200, 205))
    d.rectangle([0, 380, W, H], fill=(140, 30, 28))
    for x in range(0, W, 64):
        d.line([(x, 380), (x, H)], fill=(110, 20, 20), width=3)
    d.rectangle([90, 270, 260, 330], fill=(230, 220, 200), outline=(180, 180, 185), width=3)
    for k in range(4):
        d.ellipse([100 + k * 40, 300, 135 + k * 40, 325], fill=(200, 140, 70))
    for ux in (760, 820):
        d.rectangle([ux, 250, ux + 44, 330], fill=(185, 185, 190))
        d.ellipse([ux - 2, 240, ux + 46, 262], fill=(205, 205, 210))
    # pendant lamps
    for lx in (150, 420, 660, 900):
        d.line([(lx, 0), (lx, 40)], fill=(30, 30, 30), width=3)
        d.pieslice([lx - 30, 30, lx + 30, 80], 180, 360, fill=(160, 40, 30))
        glow(im, lx, 62, 90, (255, 220, 150), 170)
    return painterly(im, 1.0, 1)


def interior_laundromat():
    im = vgrad(W, H, (200, 220, 205), (170, 190, 175)).convert("RGBA")
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 40], fill=(225, 235, 225))
    # fluorescent tubes
    for k in range(4):
        x = 60 + k * 250
        d.rectangle([x, 12, x + 170, 26], fill=(250, 255, 245))
        glow(im, x + 85, 20, 120, (230, 255, 235), 120)
    # dryers (top row) and washers (bottom row)
    for row, (y0, y1) in enumerate([(130, 290), (310, 480)]):
        for k in range(7):
            x0 = 20 + k * 143
            d.rectangle([x0, y0, x0 + 130, y1], fill=(232, 232, 225), outline=(150, 150, 150), width=3)
            d.rectangle([x0 + 8, y0 + 8, x0 + 122, y0 + 30], fill=(180, 185, 180))
            cx, cy, r = x0 + 65, (y0 + 40 + y1) // 2, 46
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(160, 160, 165))
            d.ellipse([cx - r + 9, cy - r + 9, cx + r - 9, cy + r - 9], fill=(45, 55, 60) if row else (70, 70, 75))
            if row and k % 3 == 1:  # clothes tumbling
                d.chord([cx - 30, cy - 10, cx + 30, cy + 34], 0, 180, fill=(170, 60, 50))
    # sign panels
    f = font("narrow", 44)
    d.rectangle([380, 50, 640, 112], fill=(30, 80, 70))
    d.text((395, 56), "WASH  25c", font=f, fill=(240, 240, 220))
    d.rectangle([0, 480, W, H], fill=(120, 130, 120))
    return painterly(im, 0.9, 2)


def interior_pawn():
    rng = random.Random(3)
    im = vgrad(W, H, (150, 105, 55), (95, 60, 30)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # pegboard wall
    for y in range(20, 330, 14):
        for x in range(10, W, 14):
            d.point((x, y), fill=(110, 75, 40))
    # guitars hanging
    for k in range(6):
        x = 40 + k * 70
        col = rng.choice([(150, 70, 20), (190, 120, 40), (40, 20, 15), (160, 30, 25)])
        d.line([(x, 30), (x, 120)], fill=(60, 35, 20), width=8)
        d.ellipse([x - 26, 110, x + 26, 170], fill=col)
        d.ellipse([x - 32, 150, x + 32, 230], fill=col)
        d.ellipse([x - 8, 150, x + 8, 166], fill=(20, 15, 10))
    # shelves with TVs radios
    for sy in (150, 270):
        d.rectangle([480, sy, W, sy + 10], fill=(80, 50, 25))
        x = 490
        while x < W - 60:
            w = rng.randint(50, 110)
            h = rng.randint(50, 100)
            kind = rng.random()
            if kind < 0.4:
                d.rectangle([x, sy - h, x + w, sy], fill=(70, 55, 40))
                d.rounded_rectangle([x + 8, sy - h + 8, x + w - 20, sy - 8], 8, fill=(80, 100, 95))
            elif kind < 0.7:
                d.rounded_rectangle([x, sy - h // 2, x + w, sy], 6, fill=rng.choice([(170, 140, 90), (120, 30, 30), (60, 60, 70)]))
                d.ellipse([x + 6, sy - h // 2 + 6, x + 30, sy - 6], fill=(40, 40, 40))
            else:
                d.rectangle([x, sy - h, x + w, sy], fill=rng.choice([(200, 180, 120), (90, 80, 70), (150, 150, 155)]))
            x += w + rng.randint(4, 16)
    # glass display counter with jewellery
    d.rectangle([0, 360, W, 400], fill=(200, 210, 200))
    d.rectangle([0, 400, W, H], fill=(70, 45, 25))
    for k in range(60):
        x = rng.randint(10, W - 10)
        d.ellipse([x, 372, x + 8, 380], fill=(255, 220, 120))
    glow(im, 300, 40, 260, (255, 210, 130), 110)
    glow(im, 780, 40, 260, (255, 210, 130), 110)
    # security grille hint
    for x in range(0, W, 26):
        d.line([(x, 0), (x, 340)], fill=(60, 50, 40), width=2)
    return painterly(im, 1.0, 3)


def interior_barber():
    im = vgrad(W, H, (215, 225, 225), (180, 190, 190)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # tiles
    for x in range(0, W, 26):
        d.line([(x, 300), (x, H)], fill=(170, 185, 190), width=2)
    for y in range(300, H, 26):
        d.line([(0, y), (W, y)], fill=(170, 185, 190), width=2)
    # long mirror reflecting the warm room
    d.rectangle([40, 90, W - 40, 280], fill=(150, 140, 120), outline=(190, 190, 195), width=8)
    for k in range(3):
        cx = 200 + k * 310
        d.rounded_rectangle([cx - 50, 180, cx + 50, 280], 18, fill=(120, 30, 30))  # chairs in mirror
        d.rectangle([cx - 8, 140, cx + 8, 180], fill=(110, 95, 80))
    # counter with bottles
    d.rectangle([40, 290, W - 40, 320], fill=(240, 240, 235))
    rng = random.Random(4)
    for k in range(40):
        x = rng.randint(50, W - 60)
        h = rng.randint(18, 40)
        d.rectangle([x, 290 - h, x + 9, 290], fill=rng.choice([(40, 110, 60), (170, 120, 40), (60, 90, 160), (200, 200, 200)]))
    # barber chairs (foreground of back wall)
    for k in range(3):
        cx = 200 + k * 310
        d.rounded_rectangle([cx - 60, 330, cx + 60, 430], 22, fill=(140, 25, 25))
        d.rectangle([cx - 70, 400, cx + 70, 420], fill=(200, 200, 205))
        d.rectangle([cx - 10, 430, cx + 10, 480], fill=(190, 190, 195))
        d.ellipse([cx - 50, 470, cx + 50, 495], fill=(170, 170, 175))
    # lights
    for k in range(4):
        glow(im, 130 + k * 250, 40, 110, (255, 245, 220), 150)
    return painterly(im, 0.9, 4)


def interior_newsstand():
    rng = random.Random(5)
    im = vgrad(W, H, (170, 125, 70), (120, 80, 45)).convert("RGBA")
    d = ImageDraw.Draw(im)
    for ry in (40, 150, 260):
        d.rectangle([0, ry + 95, W, ry + 104], fill=(70, 45, 25))
        x = 10
        while x < W - 40:
            w = rng.randint(48, 62)
            col = tuple(rng.randint(60, 240) for _ in range(3))
            d.rectangle([x, ry, x + w, ry + 95], fill=col)
            d.rectangle([x + 4, ry + 6, x + w - 4, ry + 22], fill=(240, 235, 220))
            d.rectangle([x + 8, ry + 34, x + w - 8, ry + 80], fill=tuple(max(0, c - 60) for c in col))
            x += w + rng.randint(2, 8)
    # cigarette shelf + counter
    d.rectangle([0, 370, W, 400], fill=(60, 40, 25))
    for x in range(10, W, 18):
        d.rectangle([x, 372, x + 14, 396], fill=rng.choice([(200, 30, 30), (240, 240, 230), (30, 90, 160), (220, 180, 40)]))
    d.rectangle([0, 400, W, H], fill=(90, 55, 30))
    glow(im, 512, 20, 400, (255, 220, 150), 120)
    return painterly(im, 1.0, 5)


def interior_hotel():
    rng = random.Random(6)
    im = vgrad(W, H, (120, 70, 35), (80, 40, 20)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # wood panelling
    for x in range(0, W, 85):
        d.rectangle([x + 6, 60, x + 79, 300], outline=(70, 35, 15), width=5)
    d.rectangle([0, 300, W, 312], fill=(60, 30, 12))
    # reception desk
    d.rectangle([300, 320, 760, 450], fill=(90, 45, 20))
    d.rectangle([290, 310, 770, 330], fill=(130, 70, 30))
    for x in range(320, 750, 60):
        d.rectangle([x, 345, x + 40, 430], outline=(60, 28, 10), width=4)
    # key rack
    d.rectangle([420, 120, 640, 250], fill=(70, 35, 15))
    for r in range(4):
        for c in range(8):
            d.rectangle([432 + c * 26, 132 + r * 30, 448 + c * 26, 150 + r * 30], fill=(40, 20, 8))
            if rng.random() < 0.6:
                d.line([(440 + c * 26, 140 + r * 30), (440 + c * 26, 156 + r * 30)], fill=(220, 180, 90), width=3)
    # stairs + palm
    for k in range(8):
        d.rectangle([840 + k * 20, 450 - k * 30, W, 450 - k * 30 + 30], fill=(120, 30, 30))
    d.rectangle([110, 380, 170, 450], fill=(150, 110, 70))
    for k in range(9):
        a = math.pi * (0.15 + 0.7 * k / 8)
        d.line([(140, 380), (140 + 120 * math.cos(a) * (1 if k % 2 else -1), 380 - 140 * math.sin(a))], fill=(40, 80, 40), width=10)
    d.rectangle([0, 450, W, H], fill=(110, 25, 25))  # carpet
    glow(im, 512, 30, 230, (255, 220, 150), 170)
    glow(im, 200, 200, 120, (255, 200, 120), 120)
    glow(im, 820, 200, 120, (255, 200, 120), 120)
    return painterly(im, 1.0, 6)


def interior_empty():
    rng = random.Random(7)
    im = vgrad(W, H, (70, 64, 58), (45, 40, 36)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # peeling wallpaper patches
    for k in range(30):
        x, y = rng.randint(0, W), rng.randint(0, 330)
        d.rectangle([x, y, x + rng.randint(20, 90), y + rng.randint(20, 60)], fill=(85, 78, 66))
    # back door with a faint light
    d.rectangle([700, 150, 800, 400], fill=(30, 28, 25))
    d.rectangle([712, 165, 788, 260], fill=(120, 120, 110))
    # stacked chairs, boxes, an old counter
    d.rectangle([80, 320, 420, 400], fill=(55, 45, 38))
    for k in range(6):
        x = rng.randint(450, 950)
        s = rng.randint(40, 90)
        d.rectangle([x, 400 - s, x + s * 1.3, 400], fill=(rng.randint(80, 110), rng.randint(65, 85), 50))
    for k in range(3):
        x = 150 + k * 60
        d.line([(x, 250), (x + 10, 320)], fill=(40, 30, 25), width=6)
        d.line([(x + 40, 250), (x + 30, 320)], fill=(40, 30, 25), width=6)
    d.rectangle([0, 400, W, H], fill=(35, 32, 30))
    return painterly(im, 1.1, 7)


# ------------------------------------------------------------------------------------------------
# upper-floor window interiors (512 x 512)
# ------------------------------------------------------------------------------------------------

def window_lit(variant=0):
    rng = random.Random(10 + variant)
    S = 512
    if variant == 0:
        im = vgrad(S, S, (220, 150, 80), (150, 85, 40)).convert("RGBA")
    else:
        im = vgrad(S, S, (200, 160, 110), (120, 80, 50)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # wallpaper stripes
    for x in range(0, S, 36):
        d.rectangle([x, 0, x + 14, S], fill=tuple(int(c * 0.93) for c in im.getpixel((x, 200))[:3]))
    # picture frame, lamp
    d.rectangle([300, 120, 400, 200], fill=(70, 45, 25))
    d.rectangle([310, 130, 390, 190], fill=(150, 160, 140))
    glow(im, 150, 260, 200, (255, 225, 160), 200)
    d.polygon([(110, 220), (190, 220), (175, 270), (125, 270)], fill=(240, 210, 150))
    if variant == 0:
        # sheer curtains on both sides
        for side in (0, 1):
            x0 = 0 if side == 0 else S - 130
            for k in range(7):
                xx = x0 + k * 19
                d.rectangle([xx, 0, xx + 12, S], fill=(235, 200, 150, 255))
    else:
        # roller blind pulled half down
        d.rectangle([0, 0, S, 210], fill=(225, 205, 160))
        d.rectangle([0, 205, S, 216], fill=(150, 120, 80))
        d.ellipse([245, 216, 265, 236], outline=(120, 90, 60), width=3)
        # plant silhouette
        d.rectangle([380, 430, 440, 512], fill=(60, 35, 20))
        for k in range(8):
            a = math.pi * (0.1 + 0.8 * k / 7)
            d.line([(410, 430), (410 + 80 * math.cos(a), 430 - 110 * math.sin(a))], fill=(40, 60, 30), width=9)
    return painterly(im, 1.0, 10 + variant)


def window_dark():
    S = 512
    im = vgrad(S, S, (28, 30, 34), (14, 14, 16)).convert("RGBA")
    d = ImageDraw.Draw(im)
    for side in (0, 1):
        x0 = 0 if side == 0 else S - 150
        for k in range(8):
            xx = x0 + k * 19
            d.rectangle([xx, 0, xx + 11, S], fill=(46, 44, 42))
    d.rectangle([180, 300, 340, 420], fill=(20, 18, 17))
    return painterly(im, 1.0, 20)


# ------------------------------------------------------------------------------------------------
# posters atlas (4 x 2 posters, each 256 x 512), ghost sign, awning canvas
# ------------------------------------------------------------------------------------------------

def posters():
    rng = random.Random(30)
    im = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    specs = [
        ("FOR\nLEASE", (230, 220, 190), (180, 20, 20)),
        ("CLOSED", (240, 235, 210), (20, 20, 20)),
        ("BOXING\nFRI 8PM", (220, 190, 60), (30, 30, 30)),
        ("VOTE\nHALE", (30, 60, 120), (240, 235, 220)),
        ("CIRCUS", (200, 50, 40), (250, 220, 60)),
        ("JAZZ\nTONITE", (25, 25, 30), (230, 180, 60)),
        ("GOING\nOUT OF\nBUSINESS", (240, 230, 70), (180, 20, 20)),
        ("NO\nBILLS", (200, 195, 180), (40, 40, 40)),
    ]
    for i, (txt, bg, fg) in enumerate(specs):
        col, row = i % 4, i // 4
        x0, y0 = col * 256, row * 512
        p = Image.new("RGBA", (256, 512), bg + (255,))
        d = ImageDraw.Draw(p)
        lines = txt.split("\n")
        fs = 70 if len(lines) < 3 else 54
        f = font("narrow", fs)
        y = 60
        for ln in lines:
            tw = d.textlength(ln, font=f)
            d.text(((256 - tw) / 2, y), ln, font=f, fill=fg)
            y += fs + 10
        # graphic bits
        d.rectangle([20, 400, 236, 410], fill=fg)
        for k in range(5):
            d.line([(30, 430 + k * 14), (30 + rng.randint(100, 190), 430 + k * 14)], fill=fg, width=5)
        # weather: fade, stains, torn edges via alpha
        p = ImageEnhance.Color(p).enhance(0.6)
        stain = seeded_noise((64, 128), 60).resize((256, 512), Image.BICUBIC)
        p = Image.composite(p, Image.new("RGBA", p.size, (120, 110, 90, 255)), stain.point(lambda v: 255 if v > 90 else 120 + v))
        a = Image.new("L", (256, 512), 255)
        ad = ImageDraw.Draw(a)
        for k in range(rng.randint(2, 5)):  # torn chunks
            cx = rng.choice([0, 256]) if rng.random() < 0.5 else rng.randint(0, 256)
            cy = rng.choice([0, 512]) if cx not in (0, 256) else rng.randint(0, 512)
            r = rng.randint(25, 80)
            pts = [(cx + r * math.cos(t) * rng.uniform(0.5, 1.2), cy + r * math.sin(t) * rng.uniform(0.5, 1.2)) for t in [j * 0.5 for j in range(13)]]
            ad.polygon(pts, fill=0)
        p.putalpha(ImageChops.multiply(p.getchannel("A"), a))
        im.alpha_composite(p, (x0, y0))
    return painterly(im, 0.5, 30)


def ghost_sign():
    rng = random.Random(40)
    w, h = 1024, 512
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([20, 20, w - 20, h - 20], fill=(180, 160, 110, 255))
    d.rectangle([40, 40, w - 40, h - 40], outline=(120, 40, 30, 255), width=10)
    f1 = font("serif", 120)
    f2 = font("narrow", 70)
    f3 = font("script", 90)
    d.text((80, 60), "Harland's", font=f3, fill=(120, 40, 30, 255))
    d.text((80, 190), "HARDWARE & PAINT", font=f2, fill=(40, 50, 70, 255))
    d.text((80, 300), "EST. 1921", font=f1, fill=(120, 40, 30, 255))
    # fade: patchy alpha + brick-mortar-ish horizontal loss
    noise = seeded_noise((w // 8, h // 8), 80).resize((w, h), Image.BICUBIC)
    alpha = noise.point(lambda v: int(max(0, min(255, (v - 60) * 1.6))))
    for y in range(0, h, 22):
        ImageDraw.Draw(alpha).line([(0, y), (w, y)], fill=0, width=3)
    a = ImageChops.multiply(im.getchannel("A"), alpha)
    a = a.point(lambda v: int(v * 0.75))
    im.putalpha(a)
    return painterly(im, 0.6, 40)


def awning_canvas():
    S = 512
    im = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(im)
    for k in range(8):
        col = (150, 35, 30) if k % 2 == 0 else (215, 205, 180)
        d.rectangle([k * 64, 0, k * 64 + 63, S], fill=col)
    noise = seeded_noise((S // 2, S // 2), 40).resize((S, S), Image.BICUBIC).convert("RGB")
    im = ImageChops.multiply(im, noise.point(lambda v: 150 + v // 3))
    # weave
    for y in range(0, S, 4):
        d.line([(0, y), (S, y)], fill=None)
    return painterly(im, 0.4, 50)


# ------------------------------------------------------------------------------------------------
# optional painted shop signs (1024 x 192 ~ signage band 0.8 m high)
# ------------------------------------------------------------------------------------------------

def sign(text, bg, fg, style="narrow", sub=None, seed=0, border=None):
    rng = random.Random(seed)
    w, h = 1024, 192
    im = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(im)
    if border:
        d.rectangle([10, 10, w - 10, h - 10], outline=border, width=8)
    fs = 120 if sub is None else 104
    f = font(style, fs)
    tw = d.textlength(text, font=f)
    if tw > w - 80:
        f = font(style, int(fs * (w - 80) / tw))
        tw = d.textlength(text, font=f)
    ty = 22 if sub is None else 8
    d.text(((w - tw) / 2 + 5, ty + 5), text, font=f, fill=tuple(max(0, c - 70) for c in bg))
    d.text(((w - tw) / 2, ty), text, font=f, fill=fg)
    if sub:
        f2 = font("sans", 34)
        sw = d.textlength(sub, font=f2)
        d.text(((w - sw) / 2, 140), sub, font=f2, fill=fg)
    # weathering: fade, peel, grime streaks running down
    im = ImageEnhance.Color(im).enhance(0.7)
    noise = seeded_noise((w // 16, h // 16), 50).resize((w, h), Image.BICUBIC).convert("RGB")
    im = ImageChops.multiply(im, noise.point(lambda v: 200 + v // 5))
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    for k in range(18):
        x = rng.randint(0, w)
        ld.line([(x, rng.randint(0, h // 2)), (x + rng.randint(-3, 3), h)], fill=(50, 45, 38, rng.randint(25, 70)), width=rng.randint(2, 6))
    lay = lay.filter(ImageFilter.GaussianBlur(2))
    im = im.convert("RGBA")
    im.alpha_composite(lay)
    im = im.convert("RGB")
    d = ImageDraw.Draw(im)
    for k in range(12):
        x, y = rng.randint(0, w), rng.randint(0, h)
        r = rng.randint(4, 16)
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(c * 0.85) for c in bg))
    return painterly(im, 0.35, seed)


def main():
    save(interior_diner(), "interior_diner.png")
    save(interior_laundromat(), "interior_laundromat.png")
    save(interior_pawn(), "interior_pawn.png")
    save(interior_barber(), "interior_barber.png")
    save(interior_newsstand(), "interior_newsstand.png")
    save(interior_hotel(), "interior_hotel.png")
    save(interior_empty(), "interior_empty.png")
    save(window_lit(0), "window_lit.png")
    save(window_lit(1), "window_lit_b.png")
    save(window_dark(), "window_dark.png")
    save(posters(), "posters.png")
    save(ghost_sign(), "ghost_sign.png")
    save(awning_canvas(), "awning_canvas.png")
    signs = [
        ("sign_diner.png", "EAT  DINER", (150, 30, 25), (240, 230, 200), "narrow", "COFFEE  -  PIE  -  OPEN ALL NIGHT", (240, 230, 200)),
        ("sign_laundromat.png", "LAUNDROMAT", (30, 90, 85), (240, 240, 225), "narrow", "SELF SERVICE  -  COIN OP", None),
        ("sign_pawn.png", "PAWN  &  LOAN", (25, 25, 28), (225, 185, 60), "sans", "WE BUY GOLD  -  GUITARS  -  RADIOS", (225, 185, 60)),
        ("sign_barber.png", "Barber Shop", (230, 225, 210), (140, 25, 25), "script", None, (30, 50, 110)),
        ("sign_newsstand.png", "NEWS  &  TOBACCO", (40, 60, 40), (235, 225, 190), "narrow", "MAGAZINES  -  CIGARS", None),
        ("sign_hotel.png", "HOTEL  MERIDIAN", (60, 20, 18), (230, 195, 120), "serif", "ROOMS  -  WEEKLY RATES", (230, 195, 120)),
        ("sign_hardware.png", "HARDWARE", (200, 190, 160), (40, 60, 90), "narrow", None, None),
        ("sign_drugs.png", "DRUGS", (215, 210, 190), (30, 70, 130), "sans", "SODA FOUNTAIN", (30, 70, 130)),
        ("sign_shoe_repair.png", "SHOE REPAIR", (30, 40, 60), (230, 220, 200), "narrow", None, None),
        ("sign_for_lease.png", "FOR LEASE", (225, 220, 205), (160, 20, 20), "narrow", "INQUIRE WITHIN", None),
    ]
    for i, (fn, t, bg, fg, st, sub, border) in enumerate(signs):
        save(sign(t, bg, fg, st, sub, seed=100 + i, border=border), fn, SIGNS)


if __name__ == "__main__":
    main()
