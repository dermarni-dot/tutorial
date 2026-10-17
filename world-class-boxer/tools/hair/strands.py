"""Alpha strand textures for the hair cards (numpy, no Blender needed).

Every texture is a greyscale albedo (the game multiplies it by the hair colour through the
mesh's vertex colours) with a straight alpha channel. Strands run along +v (top of the image
= root, bottom = tip) so a card's UVs map root -> tip down the image.

    python strands.py OUTDIR [--size 1024]

writes one PNG per family (see FAMILIES). Deterministic: same seed, same pixels.
"""
import argparse
import math
import os

import numpy as np
from PIL import Image

RNG = np.random.default_rng


def _blank(w, h):
    return np.zeros((h, w), np.float32), np.zeros((h, w), np.float32)


def _splat_line(lum, alp, xs, ys, width, shade, opacity, wrapy=False):
    """Draw an anti-aliased polyline (xs, ys in pixels) of the given width into lum/alp
    (premultiplied accumulation, 'over' compositing)."""
    h, w = lum.shape
    for i in range(len(xs) - 1):
        x0, y0, x1, y1 = xs[i], ys[i], xs[i + 1], ys[i + 1]
        seg = max(1, int(math.hypot(x1 - x0, y1 - y0) * 1.5))
        for s in range(seg):
            t = s / seg
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            wd = width[i] + (width[i + 1] - width[i]) * t
            op = opacity[i] + (opacity[i + 1] - opacity[i]) * t
            sh = shade[i] + (shade[i + 1] - shade[i]) * t
            r = max(0.6, wd * 0.5)
            ix0, ix1 = int(math.floor(x - r - 1)), int(math.ceil(x + r + 1))
            iy = int(round(y))
            if wrapy:
                iy %= h
            elif iy < 0 or iy >= h:
                continue
            for ix in range(ix0, ix1 + 1):
                px = ix % w  # wrap horizontally: atlases tile across u
                d = abs(ix + 0.5 - x)
                cov = min(1.0, max(0.0, r + 0.5 - d)) * op
                if cov <= 0:
                    continue
                a0 = alp[iy, px]
                lum[iy, px] = sh * cov + lum[iy, px] * (1 - cov)
                alp[iy, px] = cov + a0 * (1 - cov)


def _strand_field(w, h, seed, count, width_px, waviness, curl_amp, length=(0.75, 1.0), taper=0.75,
                  dark_root=0.35, x_range=(0, 1), y0=0.0, flyaway=0.04):
    """Many strands from the top (roots) towards the bottom (tips)."""
    rng = RNG(seed)
    lum, alp = _blank(w, h)
    for k in range(count):
        x = rng.uniform(*x_range) * w
        L = rng.uniform(*length) * (h - y0 * h)
        n = max(8, int(L / 6))
        phase = rng.uniform(0, math.tau)
        freq = rng.uniform(0.7, 1.3)
        drift = rng.normal(0, 0.03) * w
        ys = np.linspace(y0 * h + rng.uniform(0, 0.04) * h, y0 * h + L, n)
        t = (ys - ys[0]) / max(1.0, L)
        xs = (x + drift * t
              + waviness * w * 0.02 * np.sin(phase + t * math.tau * 3 * freq)
              + curl_amp * w * 0.012 * np.sin(phase * 2 + t * math.tau * 14 * freq))
        if rng.random() < flyaway:  # a stray hair leaving the clump
            xs = xs + (t ** 2) * rng.normal(0, 0.06) * w
        wid = width_px * rng.uniform(0.7, 1.3) * (1 - taper * t ** 1.6)
        base = rng.uniform(0.55, 1.0)
        shade = base * (1 - dark_root * (1 - t) ** 2) * (0.9 + 0.1 * np.sin(t * 9 + phase))
        op = np.clip(1.0 - np.maximum(0, t - 0.82) / 0.18, 0, 1) * rng.uniform(0.75, 1.0)
        _splat_line(lum, alp, list(xs), list(ys), list(wid), list(shade), list(op))
    return lum, alp


def _coil_field(w, h, seed, coils, radius_px, tight, fill=0.85):
    """Kinky / coily texture: many small helices seen side-on, tileable, dense core."""
    rng = RNG(seed)
    lum, alp = _blank(w, h)
    for k in range(coils):
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        r = radius_px * rng.uniform(0.6, 1.4)
        turns = rng.uniform(2.5, 5.0)
        ang0 = rng.uniform(0, math.tau)
        dirx, diry = rng.normal(0, 1), rng.normal(0, 1)
        dl = math.hypot(dirx, diry) or 1
        dirx, diry = dirx / dl, diry / dl
        n = int(turns * 16)
        tt = np.linspace(0, 1, n)
        ang = ang0 + tt * turns * math.tau
        along = (tt - 0.5) * r * turns * (1.2 - tight * 0.6)
        xs = cx + dirx * along + np.cos(ang) * r * (-diry) + np.sin(ang) * r * 0.25 * dirx
        ys = cy + diry * along + np.cos(ang) * r * dirx + np.sin(ang) * r * 0.25 * diry
        wid = np.full(n, max(1.1, radius_px * 0.22))
        front = 0.5 + 0.5 * np.sin(ang)  # the near side of each turn catches the light
        shade = rng.uniform(0.5, 0.95) * (0.55 + 0.45 * front)
        op = np.full(n, rng.uniform(0.7, 1.0))
        ys = np.clip(ys, 0, h - 1)
        _splat_line(lum, alp, list(xs), list(ys), list(wid), list(shade), list(op))
    # dense core: the coils interlock, so the card is nearly solid inside and frizzy at the edge.
    # Fill the gaps with the coils' mean tone, darkened (the deeper hair behind them).
    lum[:] = _bleed(lum, alp) * np.where(alp > 0.02, 1.0, 0.55) + 0.0
    lum[:] = np.where(alp > 0.02, lum, lum * 1.0)
    alp[:] = np.clip(alp * 1.25 + fill * 0.15, 0, 1)
    return lum, alp


def _edge_mask(h, w, top_soft, bottom_soft, side_soft):
    v = (np.arange(h) + 0.5) / h
    u = (np.arange(w) + 0.5) / w
    mv = np.clip(v / max(1e-3, top_soft), 0, 1) * np.clip((1 - v) / max(1e-3, bottom_soft), 0, 1)
    mu = np.clip(np.minimum(u, 1 - u) / max(1e-3, side_soft), 0, 1)
    return np.outer(mv, mu)


def _noise(h, w, seed, scale):
    rng = RNG(seed)
    gh, gw = max(2, int(h / scale)), max(2, int(w / scale))
    g = rng.random((gh + 1, gw + 1)).astype(np.float32)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img, np.float32) / 255.0


def _save(path, lum, alp, gamma=1.0):
    lum = np.clip(lum, 0, 1) ** gamma
    rgb = (lum * 255 + 0.5).astype(np.uint8)
    a = (np.clip(alp, 0, 1) * 255 + 0.5).astype(np.uint8)
    img = np.dstack([rgb, rgb, rgb, a])
    # bleed colour into fully transparent texels so mip levels do not halo dark
    Image.fromarray(img, "RGBA").save(path, optimize=True)


def _bleed(lum, alp):
    out = lum.copy()
    mask = alp > 0.02
    if mask.any():
        mean = float((lum * alp).sum() / max(1e-6, alp.sum()))
        out[~mask] = mean
    return out


# ---------------------------------------------------------------------------------------------
# families. Each one is an atlas of strips; the Blender builder maps its cards into these strips.
# Strip layout (u ranges) per family is mirrored in build_hair.py (ATLAS).


def tex_straight(size, seed=11):
    """Long straight / wavy strands: 4 strips (u quarters): 0 dense clump, 1 medium, 2 sparse
    wispy, 3 wavy. Each strip is a card: roots at v=0, tips at v=1."""
    w = h = size
    lum, alp = _blank(w, h)
    q = w // 4
    specs = [
        dict(count=int(size * 0.55), width_px=size / 420, waviness=0.3, curl_amp=0.0, flyaway=0.02),
        dict(count=int(size * 0.35), width_px=size / 460, waviness=0.4, curl_amp=0.0, flyaway=0.05),
        dict(count=int(size * 0.16), width_px=size / 520, waviness=0.6, curl_amp=0.0, flyaway=0.12,
             length=(0.55, 1.0)),
        dict(count=int(size * 0.42), width_px=size / 430, waviness=2.6, curl_amp=0.15, flyaway=0.04),
    ]
    for i, sp in enumerate(specs):
        l, a = _strand_field(q, h, seed + i, x_range=(0.08, 0.92), **sp)
        a *= _edge_mask(h, q, 0.02, 0.06, 0.08)
        lum[:, i * q:(i + 1) * q] = l
        alp[:, i * q:(i + 1) * q] = a
    return _bleed(lum, alp), alp


def tex_short(size, seed=21):
    """Close crop / buzz / fade: a tileable field of short dense hairs lying back over the scalp
    (u tiles round the head, v from the hairline back). Alpha is the hair coverage; the game
    multiplies it by the fade mask it paints per style."""
    w = h = size
    lum, alp = _blank(w, h)
    rng = RNG(seed)
    n = int(size * size / 22)
    for k in range(n):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        L = rng.uniform(4, 10) * size / 1024
        ang = rng.normal(math.pi / 2, 0.35)  # combed back (down the texture)
        xs = [x, x + math.cos(ang) * L]
        ys = [y, min(h - 1, y + math.sin(ang) * L)]
        _splat_line(lum, alp, xs, ys, [2.4 * size / 1024, 1.4 * size / 1024],
                    [rng.uniform(0.35, 0.6), rng.uniform(0.6, 1.0)], [0.9, 0.7])
    lum = _bleed(lum, alp)
    alp = np.clip(alp * 1.15, 0, 1)
    return lum, alp


def tex_coily(size, seed=31):
    """Afro / high top / curly: two strips. u 0..0.5: dense tight coils (the afro's volume
    cards, fuzzy all round); u 0.5..1: looser curls (curly top, long curly)."""
    w = h = size
    lum, alp = _blank(w, h)
    half = w // 2
    l, a = _coil_field(half, h, seed, coils=int(size * 2.4), radius_px=size / 150, tight=1.0)
    m = _edge_mask(h, half, 0.12, 0.12, 0.12)
    a = a * (0.35 + 0.65 * m) * (0.6 + 0.4 * _noise(h, half, seed + 5, 18))
    a = np.where(m > 0.999, np.maximum(a, 0.9), a)
    lum[:, :half], alp[:, :half] = l, a
    l, a = _coil_field(half, h, seed + 1, coils=int(size * 1.1), radius_px=size / 80, tight=0.4, fill=0.5)
    m = _edge_mask(h, half, 0.1, 0.12, 0.14)
    lum[:, half:], alp[:, half:] = l, a * (0.3 + 0.7 * m)
    return _bleed(lum, alp), alp


def _braid_pattern(w, h, period, u0=0.0, u1=1.0):
    """A three-strand plait wrapped round a tube: u (u0..u1 of the way round) across, v along.
    Tileable in v when h is a whole number of periods."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = u0 + (u1 - u0) * (xx + 0.5) / w
    v = (yy + 0.5) / period
    lobe = np.zeros_like(u)
    shade = np.zeros_like(u)
    for s in range(3):
        ph = v + s / 3.0
        f = ph - np.floor(ph)
        c = 0.5 + 0.42 * np.sin((u + s / 3.0) * math.tau)
        d = np.abs(f - c)
        d = np.minimum(d, 1 - d)
        lob = np.clip(1 - d / 0.26, 0, 1)
        top = lob > lobe
        lobe = np.where(top, lob, lobe)
        strands = 0.75 + 0.25 * np.sin((f * 40 + u * 7 + s) * math.tau)
        shade = np.where(top, (0.35 + 0.65 * np.sqrt(lob)) * strands, shade)
    rim = np.abs(np.sin(u * math.pi))
    return np.clip(shade * (0.55 + 0.45 * rim), 0, 1)


def _plait(w, h, period, seed, strands_per_lobe=None, gap=0.18):
    """A three-strand plait seen from the front, drawn strand by strand: lobes alternate from
    the left and right edges in over the centre, each a bundle of fine hairs, every new lobe
    lying over the one before. Tileable in v (h must be a whole number of half-periods)."""
    rng = RNG(seed)
    lum, alp = _blank(w, h)
    n = strands_per_lobe or max(12, w // 5)
    half = period / 2
    k = 0
    y0 = -period
    while y0 < h + period:
        side = 1 if k % 2 == 0 else -1
        for j in range(n):
            o = (j / (n - 1) - 0.5)  # across the lobe
            pts = 18
            t = np.linspace(0, 1, pts)
            # from the outer edge, curving in over the centre, ending just past it (goes under)
            xs = w * 0.5 + side * w * (0.5 - gap * 0.5) * np.cos(t * math.pi * 0.62) - side * w * 0.08 * t
            ys = y0 + t * half * 1.15 + o * half * 1.35 * (0.3 + 0.7 * np.sin(t * math.pi)) + rng.normal(0, 0.6, pts)
            xs = xs + o * w * 0.05 * np.sin(t * math.pi)
            lift = np.sin(np.clip(t * 0.9 + 0.05, 0, 1) * math.pi)  # middle of the lobe is nearest the eye
            edge = 1 - (2 * abs(o)) ** 3
            shade = (0.25 + 0.75 * lift * (0.65 + 0.35 * edge)) * rng.uniform(0.75, 1.0)
            wid = np.full(pts, max(1.0, w / 120)) * rng.uniform(0.8, 1.2)
            op = np.clip(lift * 2.2, 0, 1) * 0.97
            _splat_line(lum, alp, list(xs), list(ys), list(wid), list(shade), list(op), wrapy=True)
        k += 1
        y0 += half
    return lum, alp


def tex_braid(size, seed=41):
    """Plaits: u 0..0.5 a three-strand braid along v (tileable in v), u 0.5..1 a loc (matted
    rope, fuzzy silhouette, tileable in v). Used on round tubes, so u wraps round the tube and
    the alpha only frays the outermost edge of the loc."""
    w = h = size
    lum, alp = _blank(w, h)
    half = w // 2
    rng = RNG(seed)
    pl, pa = _plait(half, h, size / 4, seed)
    lum[:, :half] = _bleed(pl, pa) * (0.35 + 0.65 * pa)
    yy, xx = np.mgrid[0:h, 0:half].astype(np.float32)
    u = (xx + 0.5) / half
    rim = np.abs(np.sin(u * math.pi))  # tube edges are darker (they face away)
    alp[:, :half] = 1.0
    # loc
    n1 = _noise(h, half, seed + 3, 10)
    n2 = _noise(h, half, seed + 4, 3)
    fibre = 0.6 + 0.4 * np.sin((xx / half * 31 + n1 * 6 + yy / h * 3) * math.tau)
    lum[:, half:] = np.clip((0.35 + 0.5 * n1 + 0.15 * n2) * fibre * (0.6 + 0.4 * rim), 0, 1)
    alp[:, half:] = 1.0
    l, a = _coil_field(half, h, seed + 9, coils=int(size * 0.8), radius_px=size / 260, tight=0.8, fill=0)
    lum[:, half:] = lum[:, half:] * (1 - a * 0.5) + l * a * 0.5
    return lum, alp


def tex_cornrow(size, seed=51):
    """Cornrows: u 0..0.75 one row of flat braid lying on the scalp (v runs front to back,
    tileable), seen from above: two interlocking rows of diagonal lobes (the plait's crossings),
    alpha falls off at the row's sides so the parting skin shows between rows; u 0.75..1 baby
    hairs / edge for the hairline (fine short strands, alpha)."""
    w = h = size
    lum, alp = _blank(w, h)
    rw = int(w * 0.75)
    # a plait lying on the scalp, crossings about as long as the row is wide; the alpha
    # leaves the parting's skin between rows
    flat, fa = _plait(rw, h, h / 2, seed)
    lum[:, :rw] = _bleed(flat, fa)
    alp[:, :rw] = np.clip(fa * 1.3, 0, 1)
    l, a = _strand_field(w - rw, h, seed, count=int(size * 0.2), width_px=size / 700, waviness=1.5,
                         curl_amp=0.6, length=(0.2, 0.5), x_range=(0.05, 0.95))
    lum[:, rw:], alp[:, rw:] = l, a * 0.85
    return _bleed(lum, alp), alp


FAMILIES = {
    "straight": tex_straight,
    "short": tex_short,
    "coily": tex_coily,
    "braid": tex_braid,
    "cornrow": tex_cornrow,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, fn in FAMILIES.items():
        if args.only and name not in args.only.split(","):
            continue
        lum, alp = fn(args.size)
        _save(os.path.join(args.out, f"hair_{name}.png"), lum, alp)
        print("wrote", name)


if __name__ == "__main__":
    main()
