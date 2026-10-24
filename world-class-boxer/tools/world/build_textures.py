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


# ---------------------------------------------------------------------------------------------------- gym, second pass
# (every name, headline and poster bout below is made up: no real fighters, papers or brands)
SERIF = "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf"
SERIF_REG = "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf"
SERIF_IT = "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf"
COND = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
CARL = "/usr/share/fonts/truetype/crosextra/Carlito-Bold.ttf"
CARL_IT = "/usr/share/fonts/truetype/crosextra/Carlito-BoldItalic.ttf"

CHAMPS = [
    ("OLD PETE", "FOUNDER", "1987"), ("SONNY VARGA", "MIDDLEWEIGHT", "1989"), ("ROCCO BELLINI", "HEAVYWEIGHT", "1994"),
    ("DEE HART", "LIGHTWEIGHT", "1998"), ("MARCUS OKOYE", "CRUISERWEIGHT", "2003"), ("LENA KROSS", "FEATHERWEIGHT", "2008"),
    ("TITO ALVARADO", "WELTERWEIGHT", "2011"), ("JAMAL PRYCE", "HEAVYWEIGHT", "2015"), ("NADIA SORELL", "BANTAMWEIGHT", "2019"),
    ("VIKTOR HALE", "LIGHT HEAVY", "2022"),
]


def wobble(img, amp, period, seed):
    """a hand-drawn waver: rows and columns shifted by a slow sine (marker / brush text)"""
    a = np.array(img)
    h, w = a.shape[:2]
    rng = np.random.default_rng(seed)
    ph = rng.random(2) * 6.28
    out = np.zeros_like(a)
    ys = np.arange(h)
    xs = np.arange(w)
    dx = (amp * np.sin(ys / period + ph[0])).astype(int)
    dy = (amp * np.sin(xs / (period * 1.3) + ph[1])).astype(int)
    for y in range(h):
        out[y] = np.roll(a[y], dx[y], axis=0)
    a = out.copy()
    for x in range(w):
        out[:, x] = np.roll(a[:, x], dy[x], axis=0)
    return Image.fromarray(out, img.mode)


def paper_tex(w, h, base, seed, grain=7, stain=0.12):
    im = grad_bg(w, h, base, tuple(int(c * 0.93) for c in base), seed, grain=grain)
    arr = np.array(im).astype(np.float64)
    n = max(w, h)
    nz = tile_noise(n, 4, seed + 1, 5)[:h, :w]
    arr[..., 0:3] *= (1 - stain + stain * 2 * nz)[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def tape(im, x, y, w, h, ang, seed):
    t = Image.new("RGBA", (int(w), int(h)), (236, 226, 190, 170))
    td = ImageDraw.Draw(t)
    rng = np.random.default_rng(seed)
    for k in range(0, int(w), 6):
        td.line([k, 0, k + rng.integers(-3, 4), h], fill=(255, 255, 240, 40), width=1)
    t = t.rotate(ang, expand=True, resample=Image.BICUBIC)
    im.alpha_composite(t, (int(x - t.size[0] / 2), int(y - t.size[1] / 2)))


def drop_shadow(im, card, x, y, blur=6, off=(5, 7), alpha=0.55):
    a = card.split()[3].filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * alpha))
    sh = Image.new("RGBA", card.size, (0, 0, 0, 255))
    sh.putalpha(a)
    im.alpha_composite(sh, (int(x + off[0]), int(y + off[1])))
    im.alpha_composite(card, (int(x), int(y)))


def vintage_poster(w, h, top, names, sub, venue, palette, seed):
    """an old letterpress fight bill: paper, two-colour blocks, big condensed names, worn"""
    bg, ink, accent = palette
    im = paper_tex(w, h, bg, seed, grain=6, stain=0.16)
    d = ImageDraw.Draw(im)
    d.rectangle([8, 8, w - 8, h - 8], outline=ink, width=4)
    d.rectangle([8, 8, w - 8, int(h * 0.16)], fill=ink)
    text_center(d, w / 2, int(h * 0.035), top, fit(d, top, COND, int(h * 0.1), w - 30), bg)
    boxer_silhouette(d, w * 0.3, h * 0.2, h * 0.3, 1, accent)
    boxer_silhouette(d, w * 0.7, h * 0.2, h * 0.3, -1, ink)
    a, b = names
    y = int(h * 0.6)
    text_center(d, w / 2, y, a, fit(d, a, COND, int(h * 0.11), w - 24), ink)
    text_center(d, w / 2, y + int(h * 0.105), "vs", font(SERIF_IT, int(h * 0.06)), accent)
    text_center(d, w / 2, y + int(h * 0.165), b, fit(d, b, COND, int(h * 0.11), w - 24), ink)
    d.rectangle([8, int(h * 0.88), w - 8, h - 8], fill=accent)
    text_center(d, w / 2, int(h * 0.895), sub, fit(d, sub, COND, int(h * 0.045), w - 30), bg)
    text_center(d, w / 2, int(h * 0.94), venue, fit(d, venue, SERIF, int(h * 0.04), w - 30), bg)
    # wear: faded patches, folds, a torn corner
    arr = np.array(im).astype(np.float64)
    nz = tile_noise(max(w, h), 6, seed + 9, 5)[:h, :w]
    fade = np.clip((nz - 0.55) * 3, 0, 0.45)
    arr[..., 0:3] = arr[..., 0:3] * (1 - fade[..., None]) + np.array(bg)[None, None, :] * fade[..., None]
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(im)
    d.line([0, h * 0.5, w, h * 0.52], fill=(0, 0, 0, 40), width=2)
    d.line([w * 0.5, 0, w * 0.48, h], fill=(0, 0, 0, 30), width=2)
    rng = np.random.default_rng(seed)
    cx = rng.choice([0, 1])
    cut = [(w - 1, 0), (w - 1, int(h * 0.09)), (int(w * 0.86), 0)] if cx else [(0, h - 1), (0, int(h * 0.9)), (int(w * 0.12), h - 1)]
    d.polygon(cut, fill=(0, 0, 0, 0))
    return im


def poster_wall():
    """a 4 : 1 strip of old fight bills pasted edge to edge on the boxing area's north wall, taped and overlapping"""
    W, H = 1024, 256
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bills = [
        ("FRIDAY FIGHTS", ("VARGA", "BELLINI"), "10 ROUNDS - MIDDLEWEIGHT", "CITY COMMUNITY HALL", ((232, 220, 190), (24, 22, 26), (170, 30, 34))),
        ("CHAMPIONSHIP", ("HART", "OKOYE"), "FOR THE WCB TITLE", "WCB ARENA", ((240, 226, 176), (20, 40, 90), (200, 60, 30))),
        ("THE RECKONING", ("KROSS", "SORELL"), "12 ROUNDS - FEATHERWEIGHT", "RIVERSIDE ARMORY", ((226, 216, 200), (30, 30, 30), (210, 160, 40))),
        ("SATURDAY NIGHT", ("PRYCE", "MALDEN"), "HEAVYWEIGHT ELIMINATOR", "WCB ARENA", ((236, 210, 170), (110, 20, 24), (24, 24, 30))),
        ("HOMECOMING", ("ALVARADO", "QUINN"), "WELTERWEIGHT - 10 ROUNDS", "OLD PETE'S GYM PRESENTS", ((228, 226, 210), (20, 60, 50), (180, 40, 40))),
        ("FIGHT NIGHT", ("HALE", "DUBOIS"), "LIGHT HEAVYWEIGHT", "WCB STADIUM", ((240, 232, 214), (40, 20, 60), (226, 150, 30))),
    ]
    rng = np.random.default_rng(301)
    x = 4
    for i, (top, names, sub, venue, pal) in enumerate(bills):
        bw = 168 + int(rng.integers(-8, 10))
        bh = 238 + int(rng.integers(-10, 4))
        card = vintage_poster(bw, bh, top, names, sub, venue, pal, 310 + i)
        ang = float(rng.uniform(-2.5, 2.5))
        card = card.rotate(ang, expand=True, resample=Image.BICUBIC)
        drop_shadow(im, card, x, (H - card.size[1]) / 2 + rng.integers(-4, 5), blur=4, off=(3, 4), alpha=0.5)
        tape(im, x + card.size[0] * 0.5, 10 + rng.integers(0, 6), 46, 14, float(rng.uniform(-8, 8)), 320 + i)
        x += bw - 6
    save(im, "poster_wall.png")


def clipping(w, h, paper, headline, lines, seed, photo=False):
    im = paper_tex(w, h, paper, seed, grain=5, stain=0.1)
    d = ImageDraw.Draw(im)
    d.text((10, 6), "THE CITY LEDGER  -  SPORTS", font=font(SERIF_IT, 13), fill=(80, 70, 60))
    d.line([10, 24, w - 10, 24], fill=(60, 54, 46), width=1)
    y = 30
    words = headline.split()
    line = ""
    fh = font(SERIF, int(min(34, w / 9)))
    for wd in words:
        t = (line + " " + wd).strip()
        if d.textlength(t, font=fh) > w - 20:
            d.text((10, y), line, font=fh, fill=(22, 20, 18))
            y += fh.size + 2
            line = wd
        else:
            line = t
    d.text((10, y), line, font=fh, fill=(22, 20, 18))
    y += fh.size + 6
    if photo:
        ph = (w - 20, int(h * 0.36))
        pim = grad_bg(ph[0], ph[1], (150, 146, 138), (70, 66, 60), seed + 2, grain=18)
        pd = ImageDraw.Draw(pim)
        boxer_silhouette(pd, ph[0] * 0.35, ph[1] * 0.12, ph[1] * 0.75, 1, (30, 28, 26))
        boxer_silhouette(pd, ph[0] * 0.68, ph[1] * 0.16, ph[1] * 0.7, -1, (50, 46, 42))
        im.alpha_composite(pim, (10, y))
        y += ph[1] + 6
    fb = font(SERIF_REG, 12)
    rng = np.random.default_rng(seed)
    col_w = (w - 30) / 2
    for c in range(2):
        yy = y
        while yy < h - 14:
            lw = col_w * float(rng.uniform(0.7, 1.0))
            d.line([10 + c * (col_w + 10), yy + 6, 10 + c * (col_w + 10) + lw, yy + 6], fill=(110, 102, 92), width=3)
            yy += 11
    for k, t in enumerate(lines):
        d.text((10, y - 2 + k * 0), "", font=fb)
    # yellowed edges
    arr = np.array(im).astype(np.float64)
    yy, xx = np.mgrid[0:h, 0:w]
    e = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)) / 18.0
    e = np.clip(e, 0, 1)
    arr[..., 2] *= 0.82 + 0.18 * e
    arr[..., 1] *= 0.92 + 0.08 * e
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def clippings_board():
    """a cork board of yellowed newspaper clippings pinned up by the boxing area's door (2 : 1)"""
    W, H = 1024, 512
    nz = tile_noise(1024, 40, 330, 3)[:H, :W]
    cork = np.zeros((H, W, 4))
    cork[..., 0] = 172 + 40 * (nz - 0.5)
    cork[..., 1] = 128 + 34 * (nz - 0.5)
    cork[..., 2] = 82 + 26 * (nz - 0.5)
    cork[..., 3] = 255
    rng = np.random.default_rng(331)
    for _ in range(9000):
        x, y = rng.integers(0, W), rng.integers(0, H)
        cork[y, x, 0:3] *= rng.uniform(0.6, 1.2)
    im = Image.fromarray(np.clip(cork, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W - 1, H - 1], outline=(92, 62, 36), width=18)
    d.rectangle([16, 16, W - 17, H - 17], outline=(60, 40, 22), width=3)
    items = [
        (40, 40, 300, 230, "VARGA STUNS CHAMP IN THE NINTH", True),
        (360, 34, 250, 170, "LOCAL GYM TURNS OUT ANOTHER CHAMPION", False),
        (640, 50, 330, 200, "HART TAKES IT UNANIMOUS", True),
        (380, 230, 220, 240, "OLD PETE: THIRTY YEARS OF GRIT", True),
        (40, 290, 300, 180, "KROSS KEEPS HER BELT", False),
        (630, 280, 180, 190, "CITY AMATEUR CROWN FOR TEEN", False),
        (830, 270, 160, 200, "PRYCE CALLS OUT THE WORLD", False),
    ]
    papers = [(232, 224, 200), (226, 218, 192), (238, 230, 206), (220, 210, 182)]
    for i, (x, y, w, h, head, ph) in enumerate(items):
        card = clipping(w, h, papers[i % 4], head, [], 340 + i, photo=ph)
        card = card.rotate(float(rng.uniform(-5, 5)), expand=True, resample=Image.BICUBIC)
        drop_shadow(im, card, x, y, blur=5, off=(4, 5), alpha=0.5)
        d = ImageDraw.Draw(im)
        px, py = x + card.size[0] / 2 + rng.integers(-20, 20), y + 10
        col = [(200, 30, 40), (40, 90, 200), (230, 190, 40), (40, 150, 70)][i % 4]
        d.ellipse([px - 7, py - 7, px + 7, py + 7], fill=col)
        d.ellipse([px - 3, py - 4, px + 1, py], fill=(255, 255, 255, 160))
    save(im.convert("RGB"), "clippings.png")


def hall_of_champions():
    """the Hall of Champions photo wall: a dark title band, ten framed b/w photos with brass nameplates (2 : 1)"""
    W, H = 1024, 512
    im = grad_bg(W, H, (40, 30, 26), (24, 18, 16), 350, grain=5)
    d = ImageDraw.Draw(im)
    # wood panelling
    for x in range(0, W, 64):
        d.line([x, 0, x, H], fill=(16, 12, 10), width=2)
    d.rectangle([0, 0, W, 76], fill=INK)
    d.rectangle([0, 72, W, 76], fill=GOLD)
    im.alpha_composite(emblem(60), (16, 8))
    im.alpha_composite(emblem(60), (W - 76, 8))
    gold_text(im, W / 2, 6, "HALL OF CHAMPIONS", fit(d, "HALL OF CHAMPIONS", BLACK, 60, W - 200))
    d = ImageDraw.Draw(im)
    cols, rows = 5, 2
    cw, chh = 172, 190
    gx = (W - cols * cw) / (cols + 1)
    for i, (name, div, yr) in enumerate(CHAMPS):
        c, r = i % cols, i // cols
        x = int(gx + c * (cw + gx))
        y = int(94 + r * (chh + 20))
        frame = Image.new("RGBA", (cw, chh - 34), (0, 0, 0, 0))
        fd = ImageDraw.Draw(frame)
        fd.rectangle([0, 0, cw - 1, chh - 35], fill=(14, 12, 10))
        fd.rectangle([6, 6, cw - 7, chh - 41], fill=(232, 226, 210))
        pw, ph = cw - 28, chh - 62
        rng = np.random.default_rng(360 + i)
        tone = (int(rng.integers(150, 190)),) * 3
        photo = grad_bg(pw, ph, tone, (60, 58, 54), 370 + i, grain=14)
        pd = ImageDraw.Draw(photo)
        # the champion holding a belt up over his / her head (silhouette)
        cx, s = pw / 2, ph * 0.8
        pd.ellipse([cx - 0.12 * s, ph * 0.22, cx + 0.12 * s, ph * 0.22 + 0.27 * s], fill=(28, 26, 24))
        pd.polygon([(cx - 0.32 * s, ph * 0.52), (cx + 0.32 * s, ph * 0.52), (cx + 0.24 * s, ph), (cx - 0.24 * s, ph)], fill=(28, 26, 24))
        pd.line([(cx - 0.3 * s, ph * 0.56), (cx - 0.36 * s, ph * 0.28), (cx - 0.3 * s, ph * 0.08)], fill=(28, 26, 24), width=int(0.12 * s), joint="curve")
        pd.line([(cx + 0.3 * s, ph * 0.56), (cx + 0.36 * s, ph * 0.28), (cx + 0.3 * s, ph * 0.08)], fill=(28, 26, 24), width=int(0.12 * s), joint="curve")
        pd.rounded_rectangle([cx - 0.42 * s, ph * 0.02, cx + 0.42 * s, ph * 0.12], 6, fill=(36, 34, 30))
        pd.ellipse([cx - 0.12 * s, ph * 0.0, cx + 0.12 * s, ph * 0.15], fill=(205, 200, 186))
        if i % 3 == 1:
            pd.rectangle([0, ph * 0.85, pw, ph], fill=(90, 86, 80))  # ring ropes
            pd.line([0, ph * 0.7, pw, ph * 0.68], fill=(210, 206, 196), width=3)
        frame.alpha_composite(photo, (14, 12))
        drop_shadow(im, frame, x, y, blur=5, off=(4, 6), alpha=0.6)
        d = ImageDraw.Draw(im)
        # brass nameplate
        ny = y + chh - 30
        d.rounded_rectangle([x + 8, ny, x + cw - 8, ny + 30], 4, fill=GOLD_DEEP)
        d.rounded_rectangle([x + 10, ny + 2, x + cw - 10, ny + 28], 3, fill=(222, 178, 82))
        text_center(d, x + cw / 2, ny + 3, name, fit(d, name, COND, 14, cw - 26), (40, 26, 10))
        text_center(d, x + cw / 2, ny + 17, div + "  " + yr, fit(d, div + "  " + yr, COND, 10, cw - 26), (70, 46, 18))
    save(im.convert("RGB"), "hall_champions.png")


def block_wall():
    """painted concrete block (CMU) wall: 2 x 4 blocks in running bond per tile, mortar joints, pits; mid-grey,
    tinted in game to the wall colour"""
    n = 512
    base = 0.6 + 0.06 * (tile_noise(n, 8, 380) - 0.5) + 0.04 * (tile_noise(n, 40, 381, 2) - 0.5)
    img = np.stack([base] * 3, axis=-1)
    rows, bw = 4, n // 2
    bh = n // rows
    yy, xx = np.mgrid[0:n, 0:n]
    joint = np.zeros((n, n))
    for r in range(rows):
        y0 = r * bh
        joint[(yy >= y0) & (yy < y0 + 5)] = 1
        off = (bw // 2) * (r % 2)
        for c in range(3):
            x0 = (off + c * bw) % n
            m = (yy >= y0) & (yy < y0 + bh) & (((xx - x0) % n) < 5)
            joint[m] = 1
    img[joint > 0] *= 0.72
    # each block a slightly different shade, soft bevel under the joint
    rng = np.random.default_rng(382)
    for r in range(rows):
        off = (bw // 2) * (r % 2)
        for c in range(2):
            x0 = (off + c * bw) % n
            k = rng.uniform(0.95, 1.05)
            m = (yy >= r * bh + 5) & (yy < (r + 1) * bh) & (((xx - x0) % n) >= 5) & (((xx - x0) % n) < bw)
            img[m] *= k
            sh = (yy >= r * bh + 5) & (yy < r * bh + 9) & (((xx - x0) % n) < bw)
            img[sh] *= 0.9
    for _ in range(2600):
        x, y = rng.integers(0, n, 2)
        img[y, x] *= rng.uniform(0.55, 0.85)
    save(Image.fromarray(np.clip(img * 255, 0, 255).astype(np.uint8), "RGB"), "block_wall.png")


def whiteboard():
    """a whiteboard with a hand-drawn weekly training schedule in marker (2 : 1)"""
    W, H = 1024, 512
    im = grad_bg(W, H, (246, 248, 250), (230, 233, 236), 390, grain=2)
    # ghosts of old wiped notes
    ghost = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(ghost)
    rng = np.random.default_rng(391)
    for _ in range(14):
        x, y = rng.integers(40, W - 200), rng.integers(60, H - 40)
        gd.text((x, y), "".join(rng.choice(list("ABCDEFGHJKLMNPRSTW 0123456789"), 12)), font=font(CARL, 30), fill=(120, 130, 150, 14))
    im.alpha_composite(ghost.filter(ImageFilter.GaussianBlur(2)))
    ink = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)
    BLK, BLU, RD, GRN = (24, 28, 40, 255), (30, 70, 190, 255), (200, 30, 40, 255), (30, 130, 70, 255)
    d.text((40, 18), "FIGHT CAMP - 6 WEEKS OUT!", font=font(CARL_IT, 52), fill=RD)
    d.line([40, 82, 640, 86], fill=RD, width=4)
    days = [("MON", "ROADWORK 5K  /  PADS  /  BAG 6x3", BLK), ("TUE", "SPARRING 6 RDS  -  KEEP THAT JAB", BLU),
            ("WED", "STRENGTH  +  CORE  /  ROPE 15 MIN", BLK), ("THU", "TECHNIQUE  /  SPEED BAG", BLU),
            ("FRI", "SPARRING 8 RDS  !!", RD), ("SAT", "ROADWORK  (WEIGH-IN 10AM)", BLK), ("SUN", "REST.  EAT.  SLEEP.", GRN)]
    for i, (dname, txt, col) in enumerate(days):
        y = 104 + i * 54
        d.text((48, y), dname, font=font(CARL, 40), fill=col)
        d.line([140, y + 6, 140, y + 44], fill=BLK, width=3)
        d.text((158, y + 2), txt, font=fit(d, txt, CARL, 36, 560), fill=col)
    d.line([30, 100, 30, 486], fill=BLK, width=3)
    # side notes
    d.text((760, 110), "WEIGHT", font=font(CARL, 34), fill=BLK)
    for k, (wk, lb) in enumerate([("WK1", "168"), ("WK2", "166"), ("WK3", "165"), ("WK4", "163")]):
        d.text((760, 150 + k * 38), wk + "  " + lb, font=font(CARL, 30), fill=BLU)
    d.line([752, 104, 752, 310], fill=BLK, width=3)
    d.ellipse([744, 330, 990, 470], outline=RD, width=4)
    d.text((772, 356), "HANDS UP!", font=font(CARL_IT, 40), fill=RD)
    d.text((786, 404), "- COACH", font=font(CARL, 28), fill=RD)
    ink = wobble(ink, 2, 23, 392)
    im.alpha_composite(ink.filter(ImageFilter.GaussianBlur(0.6)))
    d = ImageDraw.Draw(im)
    # aluminium frame and the marker tray shadow
    d.rectangle([0, 0, W - 1, H - 1], outline=(170, 174, 180), width=10)
    d.rectangle([10, 10, W - 11, H - 11], outline=(205, 208, 212), width=2)
    save(im.convert("RGB"), "whiteboard.png")


def tv_fight():
    """a fight broadcast on the gym TVs: four frames (2 x 2 of 512 x 256) cycled by the client (ImageRectOffset)"""
    W, H = 1024, 512
    im = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    poses = [(0.38, 0.62, 1, -1, "RD 4", "2:31"), (0.42, 0.58, 1, -1, "RD 4", "1:58"), (0.30, 0.66, 1, -1, "RD 4", "1:12"), (0.45, 0.6, 1, -1, "RD 5", "2:59")]
    for f, (ax, bx, fa, fb, rd, clk) in enumerate(poses):
        fw, fh = 512, 256
        fr = grad_bg(fw, fh, (18, 14, 30), (6, 6, 10), 400 + f, grain=4)
        d = ImageDraw.Draw(fr)
        # crowd: dark heads with flash bulbs
        rng = np.random.default_rng(410 + f)
        for _ in range(240):
            x, y = rng.integers(0, fw), rng.integers(10, 110)
            r = rng.integers(4, 8)
            d.ellipse([x - r, y - r, x + r, y + r], fill=(30 + rng.integers(0, 20), 26, 34))
        for _ in range(10):
            x, y = rng.integers(0, fw), rng.integers(10, 100)
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(255, 255, 240))
        # ring: canvas, ropes, posts, a light pool
        d.polygon([(40, 250), (472, 250), (420, 150), (92, 150)], fill=(206, 200, 190))
        glow = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse([130, 140, 380, 250], fill=(255, 240, 210, 70))
        fr.alpha_composite(glow.filter(ImageFilter.GaussianBlur(20)))
        d = ImageDraw.Draw(fr)
        for k, col in enumerate([(230, 200, 60), (240, 240, 240), (200, 40, 40)]):
            y = 128 + k * 14
            d.line([70, y + 20, 442, y + 20], fill=col, width=3)
        d.rectangle([66, 110, 76, 250], fill=(200, 40, 40))
        d.rectangle([436, 110, 446, 250], fill=(40, 80, 200))
        boxer_silhouette(d, fw * ax, 112, 100, fa, (150, 30, 36))
        boxer_silhouette(d, fw * bx, 116, 96, fb, (36, 60, 150))
        # broadcast graphics: the WCB bug, score strip, round and clock
        fr.alpha_composite(emblem(40), (8, 8))
        d.rectangle([90, 214, 422, 246], fill=(11, 15, 23, 230))
        d.rectangle([90, 214, 96, 246], fill=RED)
        d.rectangle([416, 214, 422, 246], fill=(58, 142, 255))
        d.text((104, 219), "HART", font=font(XBOLD, 20), fill=WHITE)
        tw = d.textlength("OKOYE", font=font(XBOLD, 20))
        d.text((408 - tw, 219), "OKOYE", font=font(XBOLD, 20), fill=WHITE)
        text_center(d, 256, 216, rd, font(BLACK, 14), GOLD)
        text_center(d, 256, 230, clk, font(XBOLD, 14), WHITE)
        d.rectangle([fw - 64, 10, fw - 8, 30], fill=RED)
        text_center(d, fw - 36, 12, "LIVE", font(BLACK, 15), WHITE)
        # scanlines
        sl = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        sd = ImageDraw.Draw(sl)
        for y in range(0, fh, 3):
            sd.line([0, y, fw, y], fill=(0, 0, 0, 26))
        fr.alpha_composite(sl)
        im.alpha_composite(fr, ((f % 2) * fw, (f // 2) * fh))
    save(im.convert("RGB"), "tv_fight.png")


def stencil(text, name, seed):
    """a spray-painted stencil slogan: white on transparent (8 : 1), stencil bridges, overspray and a few drips"""
    W, H = 1024, 128
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    f = fit(md, text, BLACK, 104, W - 40)
    tw = md.textlength(text, font=f)
    md.text(((W - tw) / 2, 6), text, font=f, fill=255)
    # stencil bridges: thin vertical gaps through every letter
    a = np.array(mask).astype(np.float64)
    for x in range(0, W, 37):
        a[:, x:x + 4] *= 0.0 if (x // 37) % 2 == 0 else 1.0
    rng = np.random.default_rng(seed)
    # drips below some letters
    for _ in range(9):
        x = int(rng.integers(40, W - 40))
        col = a[:, x]
        ys = np.nonzero(col > 128)[0]
        if len(ys):
            y0 = ys.max()
            ln = int(rng.integers(6, 20))
            a[y0:min(H, y0 + ln), x:x + 3] = 220
    soft = Image.fromarray(a.astype(np.uint8), "L")
    over = soft.filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.35))
    core = soft.filter(ImageFilter.GaussianBlur(0.8))
    al = np.maximum(np.array(over), np.array(core)).astype(np.float64)
    nz = tile_noise(1024, 30, seed + 1, 3)[:H, :W]
    al *= 0.7 + 0.3 * nz
    im = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    im.putalpha(Image.fromarray(np.clip(al, 0, 255).astype(np.uint8), "L"))
    save(im, name)


def paint_chips():
    """chipped paint: flakes of the bare grey surface showing through, light grey on transparent (wall decal)"""
    n = 512
    nz = tile_noise(n, 9, 420, 5)
    nz2 = tile_noise(n, 30, 421, 3)
    a = np.clip((nz * 0.7 + nz2 * 0.3 - 0.62) * 9, 0, 1)
    im = np.zeros((n, n, 4))
    im[..., 0:3] = 200 + 30 * (nz2[..., None] - 0.5)
    im[..., 3] = a * 255 * edge_fade(n)
    save(Image.fromarray(np.clip(im, 0, 255).astype(np.uint8), "RGBA"), "paint_chips.png")


def puddle():
    """a water puddle on the floor: a dark wet patch with a light rim and a sheen (floor decal)"""
    n = 512
    yy, xx = np.mgrid[0:n, 0:n] / (n - 1) - 0.5
    r = np.sqrt(xx * xx * 1.0 + yy * yy * 1.6)
    a = np.clip((tile_noise(n, 3, 430, 5) * 0.5 + (0.5 - r) * 1.6 - 0.32) / 0.05, 0, 1)
    im = np.zeros((n, n, 4))
    nz = tile_noise(n, 12, 431, 3)
    im[..., 0] = 40 + 30 * nz
    im[..., 1] = 48 + 34 * nz
    im[..., 2] = 60 + 40 * nz
    rim = np.clip(a - np.array(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))) / 255.0, 0, 1)
    im[..., 0:3] += (rim * 400)[..., None]
    im[..., 3] = np.clip(a * 150 + rim * 200, 0, 255)
    save(Image.fromarray(np.clip(im, 0, 255).astype(np.uint8), "RGBA"), "puddle.png")


def floor_wear():
    """a worn path: rubbed, lighter floor where feet keep landing (white, low alpha; floor decal)"""
    n = 512
    nz = tile_noise(n, 5, 440, 5)
    streak = tile_noise(n, 60, 441, 2)
    a = np.clip((nz - 0.35) * 1.6, 0, 1) * (0.6 + 0.4 * streak)
    a *= edge_fade(n, 0.3)
    im = np.zeros((n, n, 4))
    im[..., 0:3] = 236
    im[..., 3] = a * 120
    save(Image.fromarray(np.clip(im, 0, 255).astype(np.uint8), "RGBA"), "floor_wear.png")


def backdrop_wcb():
    """a weigh-in step-and-repeat backdrop: the emblem and WCB in a staggered grid on ink (tileable)"""
    n = 512
    big = Image.new("RGBA", (n + 256, n), INK + (255,))
    em = emblem(140)
    d = ImageDraw.Draw(big)
    for r in range(2):
        for c in range(3):
            x = c * 256 + (128 if r % 2 else 0)
            y = r * 256
            if x >= n + 256 - 10:
                continue
            big.alpha_composite(em, (x + 58, y + 22))
            text_center(d, x + 128, y + 178, "WCB", font(BLACK, 46), GOLD)
    im = big.crop((0, 0, n, n))
    im.alpha_composite(big.crop((n, 0, n + 256, n)), (0, 0))
    save(im.convert("RGB"), "backdrop_wcb.png")


ALL = [rubber_tiles, sidewalk, canvas_weave, scuffs, grime, cracks, manhole, poster_fight_night, poster_undisputed, poster_gym_rules,
       poster_champion, banner_wcb, poster_wall, clippings_board, hall_of_champions, block_wall, whiteboard, tv_fight,
       lambda: stencil("OUTWORK EVERYONE", "stencil_outwork.png", 450), lambda: stencil("NO SHORTCUTS", "stencil_shortcuts.png", 451),
       lambda: stencil("NO DAYS OFF", "stencil_nodays.png", 452), paint_chips, puddle, floor_wear, backdrop_wcb]

if __name__ == "__main__":
    for fn in ALL:
        fn()
