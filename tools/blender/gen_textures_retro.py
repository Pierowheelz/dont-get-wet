#!/usr/bin/env python3
"""Painted textures for the retro-future / neon kit and the outskirts pieces (called by
gen_textures.py, or run directly). Deterministic; all original work.

Outputs in assets/textures/generated/:
  interior_noodle / interior_arcade / interior_parts / interior_cafe / interior_lobby_retro
  glass_block.png, graffiti.png (4x2 atlas, RGBA), vending_a.png / vending_b.png,
  chainlink.png (RGBA, alpha-scissor), led_text.png (ticker text strip), hazard.png
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageChops

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_textures as gt  # noqa: E402

W, H = 1024, 512


def _neon_line(im, pts, col, width=6, glow_r=18):
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.line(pts, fill=col + (150,), width=glow_r)
    lay = lay.filter(ImageFilter.GaussianBlur(glow_r * 0.6))
    im.alpha_composite(lay)
    d = ImageDraw.Draw(im)
    d.line(pts, fill=tuple(min(255, c + 90) for c in col) + (255,), width=width)


def interior_noodle():
    rng = random.Random(201)
    im = gt.vgrad(W, H, (60, 25, 40), (30, 15, 25)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # back shelves of bowls, steaming pots, glowing menu panels
    for k in range(6):
        x = 40 + k * 165
        d.rectangle([x, 70, x + 140, 170], fill=(250, 220, 150))
        for r in range(4):
            d.line([(x + 10, 85 + r * 20), (x + 10 + rng.randint(60, 120), 85 + r * 20)], fill=(120, 30, 30), width=6)
    d.rectangle([0, 230, W, 250], fill=(90, 70, 70))
    for k in range(14):
        x = 20 + k * 72
        d.ellipse([x, 205, x + 50, 232], fill=(235, 235, 230))
    for k in range(3):
        x = 200 + k * 260
        d.rectangle([x, 270, x + 110, 360], fill=(150, 150, 160))
        for s in range(4):
            sx = x + 20 + s * 25
            d.line([(sx, 270), (sx + rng.randint(-15, 15), 180)], fill=(220, 220, 230), width=10)
    # counter with stools painted at the bottom
    d.rectangle([0, 380, W, 420], fill=(200, 40, 60))
    d.rectangle([0, 420, W, H], fill=(70, 20, 30))
    for k in range(10):
        lx = 50 + k * 100
        d.line([(lx, 0), (lx, 30)], fill=(30, 10, 10), width=3)
        d.ellipse([lx - 22, 28, lx + 22, 72], fill=(230, 50, 40))
        gt.glow(im, lx, 50, 70, (255, 120, 80), 150)
    _neon_line(im, [(30, 190), (W - 30, 190)], (255, 60, 190))
    _neon_line(im, [(30, 375), (W - 30, 375)], (40, 240, 255), width=5)
    return gt.painterly(im, 0.9, 201)


def interior_arcade():
    rng = random.Random(202)
    im = gt.vgrad(W, H, (25, 15, 45), (40, 20, 60)).convert("RGBA")
    d = ImageDraw.Draw(im)
    for k in range(8):
        x = 10 + k * 128
        col = rng.choice([(200, 40, 160), (40, 160, 230), (230, 140, 30), (120, 60, 220)])
        d.rectangle([x, 120, x + 112, 470], fill=tuple(c // 3 for c in col))
        d.rectangle([x + 6, 125, x + 106, 160], fill=col)
        d.rectangle([x + 14, 180, x + 98, 290], fill=(20, 30, 40))
        for s in range(6):
            sx, sy = x + rng.randint(20, 90), rng.randint(190, 280)
            d.rectangle([sx, sy, sx + 8, sy + 8], fill=tuple(rng.randint(120, 255) for _ in range(3)))
        gt.glow(im, x + 56, 235, 80, col, 90)
        d.rectangle([x + 10, 300, x + 102, 340], fill=(40, 40, 50))
        for b in range(3):
            d.ellipse([x + 20 + b * 25, 310, x + 36 + b * 25, 326], fill=rng.choice([(255, 50, 50), (255, 230, 40), (60, 200, 255)]))
    d.rectangle([0, 470, W, H], fill=(60, 20, 80))
    for k in range(60):
        x, y = rng.randint(0, W), rng.randint(472, H)
        d.ellipse([x, y, x + 6, y + 6], fill=rng.choice([(255, 80, 200), (80, 220, 255), (255, 240, 80)]))
    _neon_line(im, [(0, 60), (W, 60)], (150, 80, 255))
    return gt.painterly(im, 0.8, 202)


def interior_parts():
    rng = random.Random(203)
    im = gt.vgrad(W, H, (30, 50, 60), (15, 25, 30)).convert("RGBA")
    d = ImageDraw.Draw(im)
    for sy in (140, 260, 380):
        d.rectangle([0, sy, W, sy + 10], fill=(90, 100, 110))
        x = 10
        while x < W - 60:
            w = rng.randint(40, 100)
            h = rng.randint(40, 100)
            kind = rng.random()
            if kind < 0.3:  # robot heads
                d.rounded_rectangle([x, sy - h, x + w, sy], 14, fill=(170, 175, 180))
                d.ellipse([x + 10, sy - h + 12, x + 26, sy - h + 28], fill=(80, 240, 255))
                d.ellipse([x + w - 26, sy - h + 12, x + w - 10, sy - h + 28], fill=(80, 240, 255))
            elif kind < 0.6:  # screens
                d.rectangle([x, sy - h, x + w, sy], fill=(40, 45, 50))
                d.rectangle([x + 6, sy - h + 6, x + w - 6, sy - 10], fill=(40, 200, 150))
            else:  # boxes of parts
                d.rectangle([x, sy - h // 2, x + w, sy], fill=rng.choice([(190, 120, 40), (120, 130, 140), (200, 60, 40)]))
            x += w + rng.randint(5, 20)
    d.rectangle([0, 420, W, H], fill=(40, 45, 55))
    for k in range(3):
        gt.glow(im, 170 + k * 340, 30, 160, (120, 230, 255), 140)
    return gt.painterly(im, 0.9, 203)


def interior_cafe():
    rng = random.Random(204)
    im = gt.vgrad(W, H, (20, 30, 30), (10, 18, 20)).convert("RGBA")
    d = ImageDraw.Draw(im)
    for row in range(2):
        for k in range(9):
            x = 20 + k * 112
            y = 120 + row * 150
            d.rectangle([x, y, x + 90, y + 80], fill=(60, 60, 55))
            d.rectangle([x + 8, y + 8, x + 82, y + 66], fill=(30, 200, 90))
            for ln in range(5):
                d.line([(x + 14, y + 16 + ln * 10), (x + 14 + rng.randint(20, 60), y + 16 + ln * 10)], fill=(180, 255, 190), width=3)
            gt.glow(im, x + 45, y + 37, 70, (40, 255, 120), 70)
    d.rectangle([0, 420, W, H], fill=(40, 25, 20))
    for k in range(5):
        d.rounded_rectangle([40 + k * 200, 380, 180 + k * 200, 470], 20, fill=(120, 30, 40))
    _neon_line(im, [(0, 40), (W, 40)], (40, 255, 230), width=5)
    return gt.painterly(im, 0.9, 204)


def interior_lobby_retro():
    im = gt.vgrad(W, H, (70, 40, 30), (40, 25, 25)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # curved desk, starburst clock, boomerang wallpaper
    rng = random.Random(205)
    for k in range(40):
        x, y = rng.randint(0, W), rng.randint(20, 300)
        d.arc([x, y, x + 50, y + 30], 200, 340, fill=(230, 160, 90), width=6)
    d.chord([250, 300, 770, 560], 180, 360, fill=(40, 160, 160))
    d.rectangle([250, 430, 770, H], fill=(40, 160, 160))
    d.arc([250, 300, 770, 560], 180, 360, fill=(240, 220, 180), width=10)
    cx, cy = 512, 150
    for k in range(16):
        a = 2 * math.pi * k / 16
        r = 90 if k % 2 == 0 else 60
        d.line([(cx, cy), (cx + r * math.cos(a), cy + r * math.sin(a))], fill=(240, 200, 90), width=6)
    d.ellipse([cx - 25, cy - 25, cx + 25, cy + 25], fill=(250, 240, 220))
    gt.glow(im, cx, cy, 220, (255, 200, 120), 140)
    d.rectangle([0, 480, W, H], fill=(140, 60, 40))
    _neon_line(im, [(60, 300), (240, 300)], (255, 70, 180))
    _neon_line(im, [(784, 300), (964, 300)], (255, 70, 180))
    return gt.painterly(im, 0.9, 205)


def glass_block():
    S = 512  # 1 m, 5 x 5 blocks of 0.2 m
    im = Image.new("RGB", (S, S), (150, 155, 150))
    d = ImageDraw.Draw(im)
    b = S // 5
    for i in range(5):
        for j in range(5):
            x0, y0 = i * b + 4, j * b + 4
            x1, y1 = x0 + b - 8, y0 + b - 8
            for k in range(12):  # radial-ish gradient: bright centre, darker edges
                t = k / 12
                c = int(150 + 90 * t)
                d.rectangle([x0 + k * 3, y0 + k * 3, x1 - k * 3, y1 - k * 3], fill=(c - 8, c, c + 6))
            for k in range(6):  # wavy refractive ridges
                yy = y0 + 10 + k * 15
                d.arc([x0 + 5, yy, x1 - 5, yy + 20], 200, 340, fill=(250, 255, 255), width=2)
    im = im.filter(ImageFilter.GaussianBlur(1.5))
    return im


def graffiti():
    rng = random.Random(206)
    im = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    words = ["DRIP", "UMBRA", "SOAK", "ZEPH", "K-9", "NO SUN", "RAINKING", "WET4LIFE"]
    cols = [(255, 60, 160), (60, 220, 255), (255, 210, 40), (120, 255, 90), (190, 90, 255), (255, 110, 40), (240, 240, 240), (255, 60, 60)]
    for i, wtxt in enumerate(words):
        cell = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
        d = ImageDraw.Draw(cell)
        f = gt.font("sans", int(min(150, 760 / max(1, len(wtxt)))))
        tw = d.textlength(wtxt, font=f)
        x = max(10, (512 - tw) / 2)
        y = 40
        fill = cols[i]
        outline = tuple(max(0, c // 4) for c in fill)
        # overspray halo
        halo = Image.new("RGBA", cell.size, (0, 0, 0, 0))
        ImageDraw.Draw(halo).text((x, y), wtxt, font=f, fill=fill + (120,), stroke_width=16, stroke_fill=fill + (90,))
        halo = halo.filter(ImageFilter.GaussianBlur(9))
        cell.alpha_composite(halo)
        d.text((x + 8, y + 8), wtxt, font=f, fill=(10, 10, 10, 220), stroke_width=10, stroke_fill=(10, 10, 10, 220))
        d.text((x, y), wtxt, font=f, fill=fill + (255,), stroke_width=9, stroke_fill=outline + (255,))
        # drips
        for k in range(rng.randint(5, 10)):
            dx = x + rng.uniform(10, tw - 10)
            dy = y + rng.uniform(90, 150)
            ln = rng.uniform(20, 80)
            d.line([(dx, dy), (dx, dy + ln)], fill=fill + (230,), width=rng.randint(3, 6))
            d.ellipse([dx - 4, dy + ln - 3, dx + 4, dy + ln + 5], fill=fill + (230,))
        cell = cell.filter(ImageFilter.SMOOTH)
        im.alpha_composite(cell, ((i % 2) * 512, (i // 2) * 256))
    return im


def vending(variant):
    w, h = 512, 1024
    base = [(200, 30, 40), (30, 90, 200)][variant]
    im = Image.new("RGBA", (w, h), base + (255,))
    d = ImageDraw.Draw(im)
    d.rectangle([20, 20, w - 20, 200], fill=(250, 250, 245))
    f = gt.font("sans", 110)
    txt = ["FIZZ", "KOLD"][variant]
    tw = d.textlength(txt, font=f)
    d.text(((w - tw) / 2, 40), txt, font=f, fill=base)
    # window with cans
    d.rectangle([40, 230, 360, 760], fill=(220, 230, 240))
    rng = random.Random(210 + variant)
    for r in range(6):
        for c in range(5):
            x, y = 55 + c * 60, 245 + r * 85
            col = rng.choice([(220, 40, 40), (40, 160, 70), (250, 200, 40), (40, 90, 200), (240, 240, 240)])
            d.rounded_rectangle([x, y, x + 42, y + 72], 10, fill=col)
            d.rectangle([x + 4, y + 30, x + 38, y + 40], fill=(255, 255, 255))
    # selection buttons + coin slot
    for r in range(8):
        d.rectangle([390, 250 + r * 55, 470, 290 + r * 55], fill=(250, 250, 200))
    d.rectangle([395, 720, 465, 760], fill=(40, 40, 40))
    d.rectangle([60, 830, w - 60, 960], fill=(25, 25, 25))
    return gt.painterly(im, 0.4, 210 + variant)


def chainlink():
    S = 256  # 0.4 m tile, 8 diamonds
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    n = 8
    p = S / n
    col = (170, 175, 175, 255)
    for k in range(-n, 2 * n):
        d.line([(k * p, 0), (k * p + S, S)], fill=col, width=4)
        d.line([(k * p, S), (k * p + S, 0)], fill=col, width=4)
    return im


def led_text():
    """Ticker text strip: white glyphs on black, sampled by led_ticker.gdshader."""
    msg = "  RAIN WARNING: HEAVY SHOWERS ALL NIGHT  ***  UMBRELLAS 2 FOR 1 AT PARTS & MODS  ***  " \
          "NOODLES OPEN 24 HR  ***  STAY DRY, CITIZEN  ***  NEXT TRAM: CANCELLED  ***"
    f = gt.font("sans", 26)
    tmp = ImageDraw.Draw(Image.new("L", (10, 10)))
    tw = int(tmp.textlength(msg, font=f)) + 20
    im = Image.new("L", (tw, 32), 0)
    ImageDraw.Draw(im).text((4, 0), msg, font=f, fill=255)
    return im.resize((2048, 32), Image.BILINEAR).convert("RGB")


def hazard():
    S = 256
    im = Image.new("RGB", (S, S), (220, 170, 20))
    d = ImageDraw.Draw(im)
    for k in range(-4, 8):
        x = k * 64
        d.polygon([(x, 0), (x + 32, 0), (x + 32 + S, S), (x + S, S)], fill=(25, 25, 25))
    return gt.painterly(im, 0.3, 220)


def main():
    gt.save(interior_noodle(), "interior_noodle.png")
    gt.save(interior_arcade(), "interior_arcade.png")
    gt.save(interior_parts(), "interior_parts.png")
    gt.save(interior_cafe(), "interior_cafe.png")
    gt.save(interior_lobby_retro(), "interior_lobby_retro.png")
    gt.save(glass_block(), "glass_block.png")
    gt.save(graffiti(), "graffiti.png")
    gt.save(vending(0), "vending_a.png")
    gt.save(vending(1), "vending_b.png")
    gt.save(chainlink(), "chainlink.png")
    gt.save(led_text(), "led_text.png")
    gt.save(hazard(), "hazard.png")


if __name__ == "__main__":
    main()
