"""The world's detail textures (gym floor tiles, wear decals, city cracks, posters) drawn with PIL + numpy into
tools/world/out. publish_world.py uploads them and writes src/shared/WorldAssetData.lua.

    /opt/bpyenv/bin/python tools/world/build_textures.py        # (any Python with Pillow + numpy)

Every image is deterministic (fixed seeds), so a re-run only changes the files whose drawing changed and the
upload cache keeps the ids of the rest. Colours follow the WCB identity (src/shared/UI.lua Theme: ink, gold, red)
and the emblem is cropped from the title logo (tools/ui/out/logo.png).

Tileable surfaces are drawn mid-grey or white so the game tints them with Texture.Color3 to the floor / wall
colour; decals are white or black on transparent so one image serves light and dark surfaces.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")
LOGO = os.path.join(ROOT, "tools", "ui", "out", "logo.png")
BLACK = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
XBOLD = "/usr/share/fonts/opentype/inter/InterDisplay-ExtraBold.otf"
SEMI = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"

INK = (11, 15, 23)
INK2 = (22, 28, 39)
GOLD = (255, 205, 83)
GOLD_DEEP = (208, 148, 43)
GOLD_LIGHT = (255, 232, 160)
RED = (243, 65, 76)
RED_DEEP = (150, 18, 30)
WHITE = (242, 244, 248)


def font(path, px):
    return ImageFont.truetype(path, int(px))


def tile_noise(n, scale, seed, octaves=4):
    """seamless value noise in 0..1 (n x n), periodic on the image size"""
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        g = max(2, int(scale * (2 ** o)))
        grid = rng.random((g, g))
        # bilinear upsample with wrap
        xs = np.arange(n) * g / n
        i0 = np.floor(xs).astype(int) % g
        i1 = (i0 + 1) % g
        f = xs - np.floor(xs)
        f = f * f * (3 - 2 * f)
        rows = grid[i0][:, :] * (1 - f)[:, None] + grid[i1] * f[:, None]
        layer = rows[:, i0] * (1 - f)[None, :] + rows[:, i1] * f[None, :]
        out += layer * amp
        tot += amp
        amp *= 0.5
    return out / tot


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name)
    img.save(p, optimize=True)
    print("wrote", os.path.relpath(p, ROOT), img.size)


# ---------------------------------------------------------------------------------------------------- surfaces
def rubber_tiles():
    """2 x 2 interlocking rubber gym tiles with EPDM flecks; mid-grey, tinted in game (Texture.Color3)."""
    n = 512
    base = 0.55 + 0.08 * (tile_noise(n, 6, 11) - 0.5)
    img = np.stack([base] * 3, axis=-1)
    rng = np.random.default_rng(12)
    # flecks: small light / dark / coloured specks
    for _ in range(5200):
        x, y = rng.integers(0, n, 2)
        r = rng.choice([1, 1, 1, 2])
        c = rng.choice([0.85, 0.3, 0.72, 0.4])
        tint = np.array([c, c, c])
        if rng.random() < 0.08:
            tint = np.array([0.75, 0.32, 0.3]) if rng.random() < 0.5 else np.array([0.35, 0.45, 0.7])
        img[max(0, y - r // 2):y + r, max(0, x - r // 2):x + r] = tint
    # seams: each tile 256 px; a dark groove with a lit edge, drawn wrapping
    t = 256
    for k in range(0, n, t):
        for w, v in ((0, 0.2), (1, 0.18), (2, 0.3), (3, 0.62)):
            img[(k + w) % n, :, :] = v
            img[:, (k + w) % n, :] = v
    # interlock puzzle teeth along the seams (subtle darker bumps)
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(im)
    for k in range(0, n, t):
        for j in range(0, n, 32):
            off = 4 if (j // 32) % 2 == 0 else -4
            d.ellipse([k + off - 5, j + 10, k + off + 5, j + 22], outline=(60, 60, 60))
            d.ellipse([j + 10, k + off - 5, j + 22, k + off + 5], outline=(60, 60, 60))
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    save(im, "rubber_tiles.png")


def canvas_weave():
    """ring canvas: a fine cotton weave with soft stains; white, tinted to the canvas colour."""
    n = 512
    y, x = np.mgrid[0:n, 0:n]
    weave = 0.5 + 0.5 * np.sin(x * 2 * math.pi / 8) * np.sin(y * 2 * math.pi / 8)
    stains = tile_noise(n, 3, 21, 5)
    v = 0.9 + 0.06 * (weave - 0.5) - 0.18 * np.clip(stains - 0.55, 0, 1) * 2
    img = np.stack([v, v * 0.995, v * 0.985], axis=-1)
    save(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB"), "canvas_weave.png")


def sidewalk():
    """concrete sidewalk slabs (2 x 2 per image) with saw-cut joints and broom texture; mid-grey, tinted in game."""
    n = 512
    base = 0.6 + 0.06 * (tile_noise(n, 5, 81) - 0.5) + 0.03 * (tile_noise(n, 40, 82, 2) - 0.5)
    y, x = np.mgrid[0:n, 0:n]
    broom = 0.012 * np.sin(y * 2 * math.pi / 3.0 + tile_noise(n, 8, 83, 2) * 6)
    v = base + broom
    # per-slab tone shift
    rng = np.random.default_rng(84)
    for i in range(2):
        for j in range(2):
            v[i * 256:(i + 1) * 256, j * 256:(j + 1) * 256] += rng.uniform(-0.03, 0.03)
    for k in range(0, n, 256):
        for w, val in ((0, 0.32), (1, 0.36), (2, 0.46), (3, 0.66)):
            v[(k + w) % n, :] = val
            v[:, (k + w) % n] = val
    img = np.stack([v, v * 0.995, v * 0.98], axis=-1)
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(0.5))
    save(im, "sidewalk.png")


# ---------------------------------------------------------------------------------------------------- decals
def blob_alpha(n, seed, scale, thresh, soft):
    a = tile_noise(n, scale, seed, 5)
    return np.clip((a - thresh) / soft, 0, 1)


def scuffs():
    """shoe skids and rubber scuffs: black on transparent (floor decals)."""
    n = 512
    rng = np.random.default_rng(31)
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    for _ in range(26):
        layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        cx, cy = rng.uniform(70, n - 70, 2)
        r = rng.uniform(25, 120)
        a0 = rng.uniform(0, 360)
        span = rng.uniform(20, 90)
        w = int(rng.uniform(2, 9))
        alpha = int(rng.uniform(40, 120))
        d.arc([cx - r, cy - r, cx + r, cy + r], a0, a0 + span, fill=(15, 15, 15, alpha), width=w)
        layer = layer.filter(ImageFilter.GaussianBlur(rng.uniform(0.6, 2.2)))
        im = Image.alpha_composite(im, layer)
    for _ in range(14):
        layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x, y = rng.uniform(40, n - 40, 2)
        L = rng.uniform(20, 70)
        ang = rng.uniform(0, math.pi)
        d.line([x, y, x + math.cos(ang) * L, y + math.sin(ang) * L], fill=(10, 10, 10, int(rng.uniform(60, 140))), width=int(rng.uniform(3, 10)))
        layer = layer.filter(ImageFilter.GaussianBlur(2.0))
        im = Image.alpha_composite(im, layer)
    # a soft grimy cloud to tie it together
    a = blob_alpha(n, 33, 3, 0.5, 0.5) * 50
    cloud = np.zeros((n, n, 4), np.uint8)
    cloud[..., 3] = a.astype(np.uint8)
    im = Image.alpha_composite(Image.fromarray(cloud, "RGBA"), im)
    # fade to the edges so the decal never shows a square
    im.putalpha(Image.fromarray((np.array(im)[..., 3] * edge_fade(n)).astype(np.uint8)))
    save(im, "scuffs.png")


def edge_fade(n, margin=0.18):
    y, x = np.mgrid[0:n, 0:n] / (n - 1)
    fx = np.clip(np.minimum(x, 1 - x) / margin, 0, 1)
    fy = np.clip(np.minimum(y, 1 - y) / margin, 0, 1)
    return fx * fy


def grime():
    """water stains / grime running down a wall from a window sill or a pipe: black on transparent, 512 x 1024."""
    w, h = 512, 1024
    rng = np.random.default_rng(41)
    a = np.zeros((h, w))
    for _ in range(40):
        x = rng.uniform(30, w - 30)
        width = rng.uniform(6, 40)
        length = rng.uniform(0.35, 0.95) * h
        strength = rng.uniform(0.15, 0.5)
        xs = np.arange(w)
        prof = np.exp(-((xs - x) / width) ** 2)
        ys = np.arange(h)
        fall = np.clip(1 - ys / length, 0, 1) ** 1.4
        a += strength * fall[:, None] * prof[None, :]
    n = tile_noise(1024, 6, 42, 5)[:h, :w]
    a = a * (0.6 + 0.8 * n)
    top = np.clip(1 - np.arange(h) / 60, 0, 1)[:, None] * 0.0
    a = np.clip(a + top, 0, 0.85)
    side = np.clip(np.minimum(np.arange(w), w - 1 - np.arange(w)) / 60, 0, 1)[None, :]
    a *= side
    img = np.zeros((h, w, 4), np.uint8)
    img[..., 0:3] = (24, 20, 16)
    img[..., 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(img, "RGBA"), "grime.png")


def cracks():
    """sidewalk / asphalt cracks and an oil stain: black on transparent."""
    n = 512
    rng = np.random.default_rng(51)
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def crack(x, y, ang, L, w, depth):
        pts = [(x, y)]
        for _ in range(int(L / 8)):
            ang += rng.normal(0, 0.35)
            x += math.cos(ang) * 8
            y += math.sin(ang) * 8
            pts.append((x, y))
            if depth < 2 and rng.random() < 0.08:
                crack(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.2), L * 0.4, max(1, w - 1), depth + 1)
        d.line(pts, fill=(12, 12, 12, 210), width=int(w), joint="curve")

    for _ in range(4):
        crack(rng.uniform(80, 430), rng.uniform(80, 430), rng.uniform(0, 2 * math.pi), rng.uniform(140, 300), 3, 0)
    im = im.filter(ImageFilter.GaussianBlur(0.7))
    # oil stain
    a = blob_alpha(n, 52, 4, 0.55, 0.25)
    y, x = np.mgrid[0:n, 0:n]
    disc = np.clip(1 - np.hypot(x - 330, y - 340) / 120, 0, 1)
    stain = np.zeros((n, n, 4), np.uint8)
    stain[..., 0:3] = (8, 8, 10)
    stain[..., 3] = (np.clip(a * disc * 1.6, 0, 0.55) * 255).astype(np.uint8)
    im = Image.alpha_composite(Image.fromarray(stain, "RGBA"), im)
    im.putalpha(Image.fromarray((np.array(im)[..., 3] * edge_fade(n, 0.12)).astype(np.uint8)))
    save(im, "cracks.png")


def manhole():
    """a cast-iron manhole cover, transparent outside the disc."""
    n = 512
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = n / 2
    d.ellipse([8, 8, n - 8, n - 8], fill=(58, 58, 60, 255))
    d.ellipse([28, 28, n - 28, n - 28], fill=(78, 78, 80, 255))
    # raised grid / diamond pattern
    for k in range(-12, 13):
        x = c + k * 18
        d.line([x - 200, c - 200, x + 200, c + 200], fill=(64, 64, 66, 255), width=5)
        d.line([x - 200, c + 200, x + 200, c - 200], fill=(64, 64, 66, 255), width=5)
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse([40, 40, n - 40, n - 40], fill=255)
    inner = Image.new("RGBA", (n, n), (78, 78, 80, 255))
    im = Image.composite(im, Image.composite(inner, im, Image.new("L", (n, n), 0)), mask)
    d = ImageDraw.Draw(im)
    d.ellipse([28, 28, n - 28, n - 28], outline=(44, 44, 46, 255), width=6)
    d.rectangle([c - 150, c - 34, c + 150, c + 34], fill=(70, 70, 72, 255))
    f = font(BLACK, 44)
    txt = "WCB CITY"
    tw = d.textlength(txt, font=f)
    d.text((c - tw / 2, c - 28), txt, font=f, fill=(40, 40, 42, 255))
    f2 = font(XBOLD, 26)
    for t, yy in (("SEWER", c - 120), ("1987", c + 84)):
        tw = d.textlength(t, font=f2)
        d.text((c - tw / 2, yy), t, font=f2, fill=(44, 44, 46, 255))
    # rust and wear
    arr = np.array(im).astype(np.float64)
    nz = tile_noise(n, 8, 61, 5)
    arr[..., 0] += (nz - 0.5) * 40 + 8
    arr[..., 1] += (nz - 0.5) * 30
    arr[..., 2] += (nz - 0.5) * 24 - 6
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    outer = Image.new("L", (n, n), 0)
    ImageDraw.Draw(outer).ellipse([8, 8, n - 8, n - 8], fill=255)
    im.putalpha(outer)
    save(im, "manhole.png")


# ---------------------------------------------------------------------------------------------------- posters
def emblem(size):
    """the WCB emblem (rounded gold-framed square, glove, red WCB pill) cropped from the title logo"""
    logo = Image.open(LOGO).convert("RGBA").crop((14, 112, 306, 404))
    return logo.resize((size, size), Image.LANCZOS)


def grad_bg(w, h, top, bottom, seed, grain=10):
    y = np.linspace(0, 1, h)[:, None, None]
    img = np.array(top)[None, None, :] * (1 - y) + np.array(bottom)[None, None, :] * y
    img = np.repeat(img, w, axis=1)
    rng = np.random.default_rng(seed)
    img += rng.normal(0, grain, (h, w, 1))
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def text_center(d, cx, y, txt, f, fill, spacing=0):
    if spacing:
        widths = [d.textlength(ch, font=f) for ch in txt]
        tw = sum(widths) + spacing * (len(txt) - 1)
        x = cx - tw / 2
        for ch, wv in zip(txt, widths):
            d.text((x, y), ch, font=f, fill=fill)
            x += wv + spacing
        return
    tw = d.textlength(txt, font=f)
    d.text((cx - tw / 2, y), txt, font=f, fill=fill)


def fit(d, txt, path, px, maxw):
    f = font(path, px)
    while d.textlength(txt, font=f) > maxw and px > 10:
        px -= 2
        f = font(path, px)
    return f


def gold_text(base, cx, y, txt, f, shadow=True):
    """gold ramp text (UI.GoldRamp) with a dark drop shadow"""
    w, h = base.size
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    tw = md.textlength(txt, font=f)
    md.text((cx - tw / 2, y), txt, font=f, fill=255)
    if shadow:
        sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        sh.putalpha(mask.filter(ImageFilter.GaussianBlur(4)).point(lambda v: int(v * 0.7)))
        base.alpha_composite(sh, (4, 6))
    bb = mask.getbbox()
    if not bb:
        return
    y0, y1 = bb[1], bb[3]
    ramp = np.zeros((h, w, 4), np.uint8)
    cols = [(255, 244, 205), (255, 212, 92), (226, 160, 40), (255, 214, 110)]
    for yy in range(y0, y1):
        t = (yy - y0) / max(1, y1 - y0 - 1) * (len(cols) - 1)
        i = min(len(cols) - 2, int(t))
        fr = t - i
        c = [cols[i][k] * (1 - fr) + cols[i + 1][k] * fr for k in range(3)]
        ramp[yy, :, 0:3] = c
        ramp[yy, :, 3] = 255
    g = Image.fromarray(ramp, "RGBA")
    g.putalpha(mask)
    base.alpha_composite(g)


def boxer_silhouette(d, x, y, s, facing, fill):
    """a simple boxer in guard (head, shoulders, torso, two gloves up) as solid shapes"""
    f = facing
    d.ellipse([x - 0.16 * s, y, x + 0.16 * s, y + 0.36 * s], fill=fill)  # head
    d.polygon([(x - 0.42 * s, y + 0.5 * s), (x + 0.42 * s, y + 0.5 * s), (x + 0.3 * s, y + 1.3 * s), (x - 0.3 * s, y + 1.3 * s)], fill=fill)
    d.rounded_rectangle([x - 0.2 * s, y + 0.3 * s, x + 0.2 * s, y + 0.6 * s], 10, fill=fill)  # neck / traps
    # arms in guard
    d.line([(x - 0.4 * s, y + 0.6 * s), (x - 0.15 * s + f * 0.25 * s, y + 0.95 * s), (x - 0.05 * s + f * 0.45 * s, y + 0.42 * s)], fill=fill, width=int(0.16 * s), joint="curve")
    d.line([(x + 0.4 * s, y + 0.6 * s), (x + 0.15 * s + f * 0.25 * s, y + 0.95 * s), (x + 0.2 * s + f * 0.5 * s, y + 0.5 * s)], fill=fill, width=int(0.16 * s), joint="curve")
    for gx, gy, gr in ((x - 0.05 * s + f * 0.45 * s, y + 0.38 * s, 0.15), (x + 0.2 * s + f * 0.5 * s, y + 0.46 * s, 0.15)):
        d.ellipse([gx - gr * s, gy - gr * s, gx + gr * s, gy + gr * s], fill=fill)


def poster_fight_night():
    W, H = 512, 768
    im = grad_bg(W, H, (30, 8, 12), INK, 71)
    # red corner left, blue corner right, split on a diagonal
    split = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(split)
    sd.polygon([(0, 140), (W * 0.62, 140), (W * 0.38, 560), (0, 560)], fill=(150, 18, 30, 235))
    sd.polygon([(W * 0.62, 140), (W, 140), (W, 560), (W * 0.38, 560)], fill=(24, 60, 160, 235))
    im.alpha_composite(split)
    # halftone dots fading toward the middle
    d = ImageDraw.Draw(im)
    for y in range(150, 556, 14):
        for x in range(6, W, 14):
            r = 1.0 + 4.0 * abs(x - W / 2) / (W / 2)
            d.ellipse([x - r, y - r, x + r, y + r], fill=(0, 0, 0, 70))
    # two gloves meeting in the middle (emblem gloves, mirrored)
    glove = Image.open(LOGO).convert("RGBA").crop((86, 160, 236, 310)).resize((210, 210), Image.LANCZOS)
    ga = np.array(glove).astype(np.float64)
    key = np.clip((ga[..., 0:3].max(axis=2) - 70) / 50, 0, 1)
    ga[..., 3] = ga[..., 3] * key
    glove = Image.fromarray(ga.astype(np.uint8), "RGBA")
    im.alpha_composite(glove, (int(W / 2 - 220), 240))
    im.alpha_composite(glove.transpose(Image.FLIP_LEFT_RIGHT), (int(W / 2 + 10), 240))
    cone = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cone)
    cd.polygon([(W / 2 - 40, 0), (W / 2 + 40, 0), (W - 60, 560), (60, 560)], fill=(255, 230, 180, 40))
    im.alpha_composite(cone.filter(ImageFilter.GaussianBlur(30)))
    gold_text(im, W / 2, 430, "VS", font(BLACK, 110))
    d = ImageDraw.Draw(im)
    text_center(d, W / 2, 30, "WCB PRESENTS", font(XBOLD, 30), GOLD, spacing=6)
    d.rectangle([40, 76, W - 40, 80], fill=RED)
    gold_text(im, W / 2, 84, "FIGHT NIGHT", fit(d, "FIGHT NIGHT", BLACK, 92, W - 50))
    d = ImageDraw.Draw(im)
    d.text((24, 160), "RED", font=font(BLACK, 44), fill=(255, 255, 255, 230))
    tw = d.textlength("BLUE", font=font(BLACK, 44))
    d.text((W - 24 - tw, 160), "BLUE", font=font(BLACK, 44), fill=(255, 255, 255, 230))
    d.rectangle([0, 560, W, H], fill=INK)
    d.rectangle([0, 560, W, 568], fill=GOLD)
    text_center(d, W / 2, 586, "RIVERA  vs  KOVAC", fit(d, "RIVERA  vs  KOVAC", BLACK, 54, W - 60), WHITE)
    text_center(d, W / 2, 652, "12 ROUNDS  -  WORLD TITLE", font(XBOLD, 30), GOLD, spacing=2)
    text_center(d, (W - 90) / 2, 704, "SATURDAY  -  WCB ARENA", font(SEMI, 26), (178, 188, 205))
    im.alpha_composite(emblem(70), (W - 90, 684))
    save(im.convert("RGB"), "poster_fightnight.png")


def poster_undisputed():
    W, H = 512, 768
    im = grad_bg(W, H, INK2, INK, 72)
    d = ImageDraw.Draw(im)
    # radiating gold rays behind the emblem
    rays = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    cx, cy = W / 2, 300
    for k in range(24):
        a0 = k * 2 * math.pi / 24
        a1 = a0 + math.pi / 48
        rd.polygon([(cx, cy), (cx + math.cos(a0) * 700, cy + math.sin(a0) * 700), (cx + math.cos(a1) * 700, cy + math.sin(a1) * 700)], fill=(255, 205, 83, 34))
    im.alpha_composite(rays)
    em = emblem(300)
    im.alpha_composite(em, (int(cx - 150), int(cy - 150)))
    d = ImageDraw.Draw(im)
    text_center(d, W / 2, 34, "THE ROAD TO", font(XBOLD, 36), (178, 188, 205), spacing=8)
    f = fit(d, "UNDISPUTED", BLACK, 96, W - 40)
    gold_text(im, W / 2, 470, "UNDISPUTED", f)
    d = ImageDraw.Draw(im)
    d.rectangle([60, 590, W - 60, 596], fill=RED)
    text_center(d, W / 2, 616, "TRAIN.  FIGHT.  BECOME", font(XBOLD, 34), WHITE, spacing=2)
    text_center(d, W / 2, 664, "WORLD CLASS.", font(BLACK, 44), GOLD)
    save(im.convert("RGB"), "poster_undisputed.png")


def poster_gym_rules():
    W, H = 512, 768
    im = grad_bg(W, H, (236, 228, 210), (214, 202, 178), 73, grain=6)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 120], fill=INK)
    text_center(d, W / 2, 22, "GYM RULES", font(BLACK, 74), GOLD)
    rules = ["1. HANDS UP. CHIN DOWN.", "2. WRAP YOUR HANDS.", "3. NO EGOS IN THE RING.", "4. RESPECT THE COACH.", "5. WIPE THE BENCH.", "6. PUT YOUR WEIGHTS BACK.", "7. SHOW UP. EVERY DAY."]
    f = fit(d, max(rules, key=len), XBOLD, 34, W - 80)
    for i, r in enumerate(rules):
        d.text((40, 160 + i * 66), r, font=f, fill=(30, 26, 22))
        d.line([40, 206 + i * 66, W - 40, 206 + i * 66], fill=(180, 168, 146), width=2)
    d.rectangle([0, H - 110, W, H], fill=RED_DEEP)
    text_center(d, (W - 100) / 2 + 6, H - 76, "DISCIPLINE BEATS TALENT", fit(d, "DISCIPLINE BEATS TALENT", BLACK, 40, W - 130), WHITE)
    im.alpha_composite(emblem(84), (W - 96, H - 100))
    # wear: creases and a torn corner
    arr = np.array(im).astype(np.float64)
    nz = tile_noise(768, 5, 74, 5)[:H, :W]
    arr[..., 0:3] *= (0.92 + 0.12 * nz)[..., None]
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(im)
    crease = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(crease)
    cd.line([0, 300, W, 330], fill=(0, 0, 0, 22), width=2)
    cd.line([0, 302, W, 332], fill=(255, 255, 255, 30), width=1)
    cd.line([250, 120, 236, H - 110], fill=(0, 0, 0, 16), width=2)
    im.alpha_composite(crease.filter(ImageFilter.GaussianBlur(1)))

    save(im.convert("RGB"), "poster_rules.png")


def poster_champion():
    W, H = 512, 768
    im = grad_bg(W, H, RED_DEEP, (40, 6, 10), 75)
    d = ImageDraw.Draw(im)
    # a championship belt: strap, centre plate, side plates
    cy = 330
    d.rounded_rectangle([20, cy - 50, W - 20, cy + 50], 30, fill=(18, 18, 22))
    for sx in (90, W - 90):
        d.ellipse([sx - 48, cy - 48, sx + 48, cy + 48], fill=GOLD_DEEP)
        d.ellipse([sx - 38, cy - 38, sx + 38, cy + 38], fill=GOLD)
    d.ellipse([W / 2 - 130, cy - 130, W / 2 + 130, cy + 130], fill=GOLD_DEEP)
    d.ellipse([W / 2 - 115, cy - 115, W / 2 + 115, cy + 115], fill=GOLD_LIGHT)
    d.ellipse([W / 2 - 100, cy - 100, W / 2 + 100, cy + 100], fill=GOLD)
    im.alpha_composite(emblem(150), (int(W / 2 - 75), int(cy - 75)))
    d = ImageDraw.Draw(im)
    text_center(d, W / 2, 40, "WORLD", font(BLACK, 84), WHITE)
    f = fit(d, "CHAMPION", BLACK, 96, W - 40)
    gold_text(im, W / 2, 128, "CHAMPION", f)
    d = ImageDraw.Draw(im)
    text_center(d, W / 2, 520, "HALL OF CHAMPIONS", font(XBOLD, 36), GOLD, spacing=3)
    d.rectangle([80, 572, W - 80, 576], fill=GOLD)
    text_center(d, W / 2, 596, "EVERY CHAMPION", font(XBOLD, 40), WHITE)
    text_center(d, W / 2, 646, "STARTED HERE", font(BLACK, 52), WHITE)
    save(im.convert("RGB"), "poster_champion.png")


def banner_wcb():
    """a tall hanging fight banner (1 : 3): ink cloth, gold border, the emblem, WCB and a red band"""
    W, H = 340, 1020
    im = grad_bg(W, H, INK2, INK, 76, grain=6)
    d = ImageDraw.Draw(im)
    d.rectangle([10, 10, W - 10, H - 10], outline=GOLD, width=6)
    d.rectangle([22, 22, W - 22, H - 22], outline=GOLD_DEEP, width=2)
    im.alpha_composite(emblem(250), (45, 70))
    d = ImageDraw.Draw(im)
    for i, ch in enumerate("WCB"):
        gold_text(im, W / 2, 360 + i * 150, ch, font(BLACK, 150))
    d = ImageDraw.Draw(im)
    d.rectangle([22, 820, W - 22, 880], fill=RED)
    text_center(d, W / 2, 828, "BOXING", font(BLACK, 42), WHITE, spacing=6)
    text_center(d, W / 2, 910, "EST. 1987", font(XBOLD, 34), (178, 188, 205), spacing=4)
    # cloth folds: soft vertical shading
    arr = np.array(im).astype(np.float64)
    xs = np.arange(W)
    fold = 0.9 + 0.1 * np.sin(xs / W * math.pi * 3)
    arr[..., 0:3] *= fold[None, :, None]
    save(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").convert("RGB"), "banner_wcb.png")


ALL = [rubber_tiles, sidewalk, canvas_weave, scuffs, grime, cracks, manhole, poster_fight_night, poster_undisputed, poster_gym_rules,
       poster_champion, banner_wcb]

if __name__ == "__main__":
    for fn in ALL:
        fn()
