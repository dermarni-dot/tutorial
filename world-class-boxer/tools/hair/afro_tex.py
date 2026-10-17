"""The "coily" strand atlas for the afro family (owned by build_afro.py). numpy + PIL only.

Layout (hairlib.ATLAS["coily"]): u 0..0.5 "tight" = a clump of tight, interlocked kinky coils; u 0.5..1
"loose" = a clump of looser curls (ringlets). Both strips are one card each (512 x 1024 at size 1024: a
card is about twice as long as it is wide), root at v = 0 and tip at v = 1, fuzzy all round: a dense,
nearly opaque core (the coils behind the coils, darkened with depth) and a frizzy silhouette made of
the coils themselves. Greyscale albedo 0.25 .. 1 with straight alpha; colour is bled into transparent
texels so mip levels do not halo.

The coils are drawn as helices seen side on: each turn's near side is brighter and nearer (a height
per sample), the samples are composited in height bins bottom up ('over'), so the deepest hair is the
darkest and the frontmost loops catch the light.
"""
import math

import numpy as np
from PIL import Image, ImageFilter

RNG = np.random.default_rng


def _noise(h, w, seed, cells, octaves=3):
    rng = RNG(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        gh, gw = max(2, int(cells * 2 ** o * h / max(h, w)) + 1), max(2, int(cells * 2 ** o * w / max(h, w)) + 1)
        g = (rng.random((gh, gw)) * 255).astype(np.uint8)
        img = Image.fromarray(g).resize((w, h), Image.BICUBIC)
        out += amp * (np.asarray(img, np.float32) / 255.0)
        tot += amp
        amp *= 0.5
    return out / tot


def _box1(a, r, axis):
    if r < 1:
        return a
    pad = [(0, 0), (0, 0)]
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def _blur(a, r):
    """~Gaussian blur of sigma ~r: three box passes per axis"""
    b = max(1, int(round(r * 0.9)))
    for _ in range(3):
        a = _box1(_box1(a, b, 0), b, 1)
    return a


class Canvas:
    """height-binned 'over' compositor for anti-aliased round samples"""

    def __init__(self, w, h, bins=20):
        self.w, self.h = w, h
        self.bins = bins
        self.samples = []  # (x, y, r, z, shade, op)

    def add(self, x, y, r, z, shade, op):
        self.samples.append(np.stack([np.asarray(a, np.float32).ravel() * np.ones(np.size(x), np.float32)
                                      for a in (x, y, r, z, shade, op)], 1))

    def render(self, lum=None, alp=None):
        w, h = self.w, self.h
        lum = np.zeros((h, w), np.float32) if lum is None else lum
        alp = np.zeros((h, w), np.float32) if alp is None else alp
        S = np.concatenate(self.samples, 0)
        z = S[:, 3]
        edges = np.quantile(z, np.linspace(0, 1, self.bins + 1))
        bi = np.clip(np.searchsorted(edges, z, side="right") - 1, 0, self.bins - 1)
        for b in range(self.bins):
            T = S[bi == b]
            if len(T) == 0:
                continue
            cov = np.zeros(h * w, np.float32)
            ls = np.zeros(h * w, np.float32)
            ws = np.zeros(h * w, np.float32)
            rmax = float(T[:, 2].max())
            R = int(math.ceil(rmax + 1.0))
            oy, ox = np.mgrid[-R:R + 1, -R:R + 1]
            oy, ox = oy.ravel(), ox.ravel()
            for c0 in range(0, len(T), 20000):
                C = T[c0:c0 + 20000]
                x, y, r, sh, op = C[:, 0:1], C[:, 1:2], C[:, 2:3], C[:, 4:5], C[:, 5:6]
                ix = np.floor(x).astype(np.int32) + ox[None]
                iy = np.floor(y).astype(np.int32) + oy[None]
                d = np.hypot(ix + 0.5 - x, iy + 0.5 - y)
                c = np.clip(r + 0.5 - d, 0, 1) * op
                ok = (c > 0.003) & (iy >= 0) & (iy < h)
                ix = ix % w
                idx = (iy * w + ix)[ok]
                cc = c[ok]
                np.maximum.at(cov, idx, cc)
                np.add.at(ls, idx, cc * np.broadcast_to(sh, c.shape)[ok])
                np.add.at(ws, idx, cc)
            cov = cov.reshape(h, w)
            ll = (ls / np.maximum(ws, 1e-6)).reshape(h, w)
            lum[:] = ll * cov + lum * (1 - cov)
            alp[:] = cov + alp * (1 - cov)
        return lum, alp


def _coils(cv, rng, n, cx, cy, radius, length, stroke, axis_jit, z0, zspan, shade0, op, tight, pts_per_turn=20,
           wander=0.25, tilt=(0.1, 1.2)):
    """n helices in 3D seen orthographically (loops where the axis points at the eye, zigzags side on):
    centres cx, cy (px), radius / length / stroke (px); axis mostly along v (axis_jit radians of spread in
    the image plane, tilt = range of its angle out of the plane); z0 base heights. tight 0..1: 1 = kinky
    (irregular, sharpened turns, wandering axis), 0 = round open ringlets."""
    for k in range(n):
        R = radius[k]
        L = length[k]
        pitch = R * (1.6 - 0.9 * tight) * rng.uniform(0.8, 1.25)
        turns = max(1.2, L / pitch)
        m = int(turns * pts_per_turn)
        t = np.linspace(0, 1, m)
        a = rng.normal(math.pi / 2, axis_jit)
        e = rng.uniform(*tilt) * rng.choice([-1, 1])
        A = np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])
        B1 = np.cross(A, [0.0, 0.0, 1.0])
        if np.linalg.norm(B1) < 1e-3:
            B1 = np.array([1.0, 0, 0])
        B1 /= np.linalg.norm(B1)
        B2 = np.cross(A, B1)
        s = (t - 0.5) * L * abs(math.cos(e)) ** 0  # length along the axis
        s = (t - 0.5) * L
        ph = rng.uniform(0, math.tau) + t * turns * math.tau
        rr = R * (1 + 0.3 * tight * np.sin(t * turns * 1.7 + rng.uniform(0, 6)) + rng.normal(0, 0.1 * tight, m))
        c, sn = np.cos(ph), np.sin(ph)
        if tight > 0.5:
            c = np.sign(c) * np.abs(c) ** (1 - 0.4 * tight)
        # the axis wanders (kinky hair does not run straight)
        wv = wander * R * turns ** 0.5
        w1 = wv * np.sin(t * math.pi * rng.uniform(0.6, 1.8) + rng.uniform(0, 6))
        w2 = wv * np.sin(t * math.pi * rng.uniform(0.6, 1.8) + rng.uniform(0, 6))
        P = (A[None] * s[:, None] + B1[None] * (rr * c + w1)[:, None] + B2[None] * (rr * sn + w2)[:, None])
        x = cx[k] + P[:, 0]
        y = cy[k] + P[:, 1]
        dz = (B1[2] * c + B2[2] * sn)  # -1 .. 1: the far / near side of each turn
        z = z0[k] + zspan * dz
        front = 0.5 + 0.5 * dz
        sh = shade0[k] * (0.45 + 0.55 * front ** 0.9)
        w = stroke[k] * (0.8 + 0.35 * front) * 0.5
        seg = np.hypot(np.diff(x), np.diff(y))
        cum = np.concatenate([[0], np.cumsum(seg)])
        q = max(4, int(cum[-1] / 0.6))
        tq = np.linspace(0, cum[-1], q)
        X = np.interp(tq, cum, x)
        Y = np.interp(tq, cum, y)
        Z = np.interp(tq, cum, z)
        SH = np.interp(tq, cum, sh)
        W = np.interp(tq, cum, w)
        tt = tq / max(1e-6, cum[-1])
        OP = op[k] * np.clip(np.minimum(tt, 1 - tt) / 0.08, 0.2, 1)
        cv.add(X, Y, W, Z, SH, OP)


def _clump_mask(w, h, seed, wobble=0.2, root_narrow=0.0, power=2.0, sx=1.0, sy=1.0):
    """q < 1 inside the clump (a rounded, lumpy blob filling most of the card), q ~ 0 at its centre"""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    x = (xx + 0.5) / w * 2 - 1
    y = (yy + 0.5) / h * 2 - 1
    x = x * sx / (1 - root_narrow * np.clip(-y, 0, 1) ** 2)
    y = y * sy
    n = _noise(h, w, seed, 3, 2) - 0.5
    q = (np.abs(x) ** power + np.abs(y) ** power) ** (1 / power)
    return q * (1 + wobble * 2 * n)


def _strip(w, h, seed, tight):
    rng = RNG(seed)
    q = _clump_mask(w, h, seed + 1, wobble=0.2 if tight else 0.24, root_narrow=0.0 if tight else 0.12,
                    power=3.0 if tight else 2.2, sx=1.06 if tight else 1.0, sy=1.03 if tight else 1.0)
    cv = Canvas(w, h, bins=18)
    sc = w / 512.0
    if tight:
        # (count, radius px, length px, stroke px, z0, op, shade): dense interlocked kinky coils, 3 depths
        layers = [
            (900, (9, 15), (36, 90), (4.0, 5.4), 0.0, 0.9, (0.38, 0.58)),
            (800, (10, 16), (40, 100), (4.2, 5.8), 1.0, 0.95, (0.52, 0.78)),
            (650, (11, 18), (42, 110), (4.4, 6.2), 2.0, 1.0, (0.64, 0.96)),
        ]
        jit, tilt, fill = 1.2, (0.0, 1.4), 0.96
    else:
        layers = [
            (330, (13, 22), (80, 170), (4.2, 5.8), 0.0, 0.85, (0.36, 0.56)),
            (300, (14, 24), (90, 200), (4.4, 6.2), 1.0, 0.95, (0.5, 0.78)),
            (250, (15, 26), (100, 220), (4.6, 6.6), 2.0, 1.0, (0.64, 0.98)),
        ]
        jit, tilt, fill = 0.4, (0.25, 0.9), 0.85
    for li, (cnt, rad, ln, st, z0, op, shd) in enumerate(layers):
        cnt = int(cnt * sc * sc * h / (2 * w))
        cx, cy = [], []
        while len(cx) < cnt:  # rejection-sample centres inside the clump (fewer in the fringe)
            x, y = rng.uniform(0, w), rng.uniform(0, h)
            qq = q[min(h - 1, int(y)), min(w - 1, int(x))]
            keep = np.clip((1.08 - qq) / 0.6, 0, 1) ** 1.5
            if rng.random() < keep:
                cx.append(x)
                cy.append(y)
        cx, cy = np.array(cx), np.array(cy)
        qq = q[np.clip(cy.astype(int), 0, h - 1), np.clip(cx.astype(int), 0, w - 1)]
        R = rng.uniform(*rad, cnt) * sc
        L = rng.uniform(*ln, cnt) * sc
        S = rng.uniform(*st, cnt) * sc
        # the clump's outer coils sit higher (they are its silhouette), the core deeper
        z = z0 + rng.uniform(0, 1, cnt)
        # the fringe (the clump's silhouette) is thinner and a little darker than its body: no bright rim
        fr = np.clip((qq - 0.5) / 0.5, 0, 1)
        shade = rng.uniform(*shd, cnt) * (0.8 + 0.2 * cy / h)  # roots a little darker
        S = S * (1 - 0.3 * fr)
        _coils(cv, rng, cnt, cx, cy, R, L, S, jit, z, 0.35, shade, op * (1 - 0.45 * fr), 1.0 if tight else 0.2,
               tilt=tilt)
    # dense core: the coils behind the coils (dark, mottled, nearly opaque) so a card never shows a void
    n = _noise(h, w, seed + 7, 24, 3)
    core = np.clip(1 - q / 0.8, 0, 1) ** 0.5
    lum0 = (0.24 + 0.14 * n).astype(np.float32)
    alp0 = (core * fill).astype(np.float32)
    lum, alp = cv.render(lum0.copy(), alp0.copy())
    # a soft border fade so the card's rectangle never shows (alpha 0 at the edge texels)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    bx = np.minimum(xx + 0.5, w - xx - 0.5) / (w * 0.05)
    by = np.minimum(yy + 0.5, h - yy - 0.5) / (h * 0.03)
    alp *= np.clip(np.minimum(bx, by), 0, 1)
    alp = np.clip(0.6 * alp + 0.4 * _blur(alp, 1.5), 0, 1)  # mip-friendly: no hard alpha steps
    return lum, alp


def _strip_clusters(w, h, seed):
    """the tight strip: a clump of curl clusters (popcorn / cauliflower). Kinky hair at game distance reads as
    soft, lumpy clusters, not as single coils: each cluster is a dome of tight coils (its middle nearest the
    eye and brightest, its rim deeper and darker), the clusters overlap into one clump whose outline is the
    clusters' frizzy rims. A dark, nearly opaque fill under the middle of every cluster keeps the clump
    dense; the card's border texels are clear."""
    rng = RNG(seed)
    sc = w / 512.0
    q = _clump_mask(w, h, seed + 1, wobble=0.22, power=2.6, sx=1.08, sy=1.03)
    cv = Canvas(w, h, bins=22)
    # cluster centres inside the clump (Poisson-ish: reject ones too near earlier ones)
    blobs = []
    tries = 0
    while len(blobs) < 16 and tries < 8000:
        tries += 1
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        qq = q[min(h - 1, int(y)), min(w - 1, int(x))]
        if qq > 0.7:
            continue
        R = rng.uniform(95, 150) * sc * (1 - 0.45 * max(0.0, qq - 0.35))
        R = min(R, x - 0.1 * w, w * 0.9 - x, y - 0.06 * h, h * 0.94 - y)
        if R < 60 * sc:
            continue
        if any(math.hypot(x - bx, y - by) < 0.7 * (R + br) for bx, by, br, _z in blobs):
            continue
        blobs.append((x, y, R, rng.uniform(0, 1.2)))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    fill_a = np.zeros((h, w), np.float32)
    fill_l = np.full((h, w), 0.24, np.float32)
    for (bx, by, R, bz) in blobs:
        # coils: denser toward the middle, three depths; the dome lifts and lights the middle ones
        n = int(70 * (R / (70 * sc)) ** 2)
        rr = R * np.sqrt(rng.uniform(0, 1, n)) ** 0.85
        aa = rng.uniform(0, math.tau, n)
        cx = bx + rr * np.cos(aa)
        cy = by + rr * np.sin(aa) * 1.0
        dome = np.sqrt(np.clip(1 - (rr / R) ** 2, 0, 1))
        cr = rng.uniform(13, 21, n) * sc
        cl = rng.uniform(40, 100, n) * sc
        cs = rng.uniform(5.2, 7.4, n) * sc * (0.75 + 0.25 * dome)
        z = bz + 2.2 * dome + rng.uniform(0, 0.6, n)
        shade = rng.uniform(0.75, 1.0, n) * (0.3 + 0.7 * dome ** 0.7) * (0.85 + 0.15 * cy / h)
        op = 0.82 + 0.18 * dome
        _coils(cv, rng, n, cx, cy, cr, cl, cs, 1.3, z, 0.25, shade, op, 1.0, tilt=(0.0, 1.4), wander=0.35)
        d = np.hypot(xx - bx, yy - by) / R
        a = np.clip((0.82 - d) / 0.3, 0, 1)
        l = 0.22 + 0.2 * np.sqrt(np.clip(1 - d * d, 0, 1))
        fill_l = np.where(a > fill_a, l, fill_l)
        fill_a = np.maximum(fill_a, a)
    nz = _noise(h, w, seed + 7, 30, 3)
    fill_l = fill_l * (0.85 + 0.3 * nz)
    lum, alp = cv.render(fill_l.copy(), (fill_a * 0.97).astype(np.float32))
    bx_ = np.minimum(xx + 0.5, w - xx - 0.5) / (w * 0.05)
    by_ = np.minimum(yy + 0.5, h - yy - 0.5) / (h * 0.03)
    alp *= np.clip(np.minimum(bx_, by_), 0, 1)
    alp = np.clip(0.65 * alp + 0.35 * _blur(alp, 1.5), 0, 1)
    return lum, alp


def _bleed(lum, alp, passes=6):
    """push colour into the transparent texels (premultiplied blur / blurred alpha), so mips do not halo"""
    out = lum.copy()
    m = alp > 0.02
    pl, pa = lum * alp, alp.copy()
    for i in range(passes):
        r = 2 ** i
        bl, ba = _blur(pl, r), _blur(pa, r)
        fill = bl / np.maximum(ba, 1e-5)
        sel = (~m) & (ba > 1e-4)
        out[sel] = fill[sel]
        m = m | sel
    mean = float((lum * alp).sum() / max(1e-6, alp.sum()))
    out[~m] = mean
    return out


def tex_coily(size=1024, seed=31):
    w = h = size
    half = w // 2
    lum = np.zeros((h, w), np.float32)
    alp = np.zeros((h, w), np.float32)
    l, a = _strip_clusters(half, h, seed)
    lum[:, :half], alp[:, :half] = l, a
    l, a = _strip(half, h, seed + 100, tight=False)
    lum[:, half:], alp[:, half:] = l, a
    # contrast into the 0.25 .. 1 albedo range
    lum = 0.25 + 0.75 * np.clip((lum - 0.2) / 0.78, 0, 1) ** 1.2
    lum = _bleed(lum, alp)
    return lum, alp


def save(path, lum, alp):
    rgb = (np.clip(lum, 0, 1) * 255 + 0.5).astype(np.uint8)
    a = (np.clip(alp, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(np.dstack([rgb, rgb, rgb, a]), "RGBA").save(path, optimize=True)


if __name__ == "__main__":
    import sys
    import time
    t = time.time()
    lum, alp = tex_coily(int(sys.argv[2]) if len(sys.argv) > 2 else 1024)
    save(sys.argv[1], lum, alp)
    print("tex", time.time() - t)
