"""The "coily" atlas for the afro family (owned by build_afro.py). numpy + PIL only, deterministic.

Layout (1024 x 1024; hairlib.ATLAS["coily"]: u 0..0.5 "tight", u 0.5..1 "loose"):

    cell        u range      v range     what
    CLOUD_A     0.00-0.50    0.00-0.50   a soft round cloud of tight kinky coils (dense, near-opaque core)
    TILE_D      0.00-0.50    0.50-1.00   a tileable dense coil tile (inner shells, near-opaque)
    TILE_S      0.50-1.00    0.00-0.25   a tileable sparse tight-coil tile (outer shells: the fuzzy edge)
    TILE_L      0.50-1.00    0.25-0.50   a tileable sparse loose-curl tile (the Curly variant's outer shells)
    FIN_T       0.50-0.75    0.50-1.00   a fuzz tuft of tight coils, root at its top (v 0.5) .. sparse tips
    FIN_L       0.75-1.00    0.50-1.00   a tuft of 2-3 loose ringlets, root at its top

The clouds have no outline to trace: the coil density falls off gradually (noise-modulated) over the
outer ~35% of the cell, so a cloud's edge is made of single loops. The surface cards are laid tangent to
the afro's layers in heavy overlap and random rotation (no cell grid, no leaf or feather silhouette).

The coils are springs seen at an angle (loops): each sample has a depth (the near side of a loop is
brighter); coils are composited in depth batches back to front ('over'), deeper batches darker, over a
dark fill in the core, so the cloud reads as interlocked hair with depth. Greyscale albedo 0.25..1 with
straight alpha; colour is bled into transparent texels so mip levels do not halo.
"""
import math

import numpy as np
from PIL import Image

RNG = np.random.default_rng
SIZE = 1024
SS = 2  # supersampling of the splat canvases

# cell -> (u0, v0, u1, v1) in the atlas
CELLS = {
    "CLOUD_A": (0.0, 0.0, 0.5, 0.5),
    "TILE_D": (0.0, 0.5, 0.5, 1.0),
    "TILE_S": (0.5, 0.0, 1.0, 0.25),
    "TILE_L": (0.5, 0.25, 1.0, 0.5),
    "FIN_T": (0.5, 0.5, 0.75, 1.0),
    "FIN_L": (0.75, 0.5, 1.0, 1.0),
}


# ----------------------------------------------------------------------------- helpers
def sstep(e0, e1, x):
    t = np.clip((np.asarray(x, np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, sigma, wrap=False):
    """gaussian blur by FFT (zero padded so nothing wraps, or periodic)"""
    if sigma <= 0:
        return a
    h, w = a.shape
    p = 0 if wrap else int(math.ceil(sigma * 3)) + 1
    A = np.pad(a, p)
    H, W = A.shape
    fy = np.fft.fftfreq(H)[:, None]
    fx = np.fft.rfftfreq(W)[None, :]
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (fx * fx + fy * fy))
    out = np.fft.irfft2(np.fft.rfft2(A) * g, s=A.shape)
    return out[p:p + h, p:p + w] if p else out


def fbm(h, w, seed, cells=4, octaves=4, decay=0.55):
    """smooth value noise 0..1 (bicubic-upsampled random grids)"""
    rng = RNG(seed)
    out = np.zeros((h, w), np.float64)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        gh, gw = max(2, int(c * h / max(h, w)) + 2), max(2, int(c * w / max(h, w)) + 2)
        g = (rng.random((gh, gw)) * 255).astype(np.uint8)
        img = Image.fromarray(g).resize((w, h), Image.BICUBIC)
        out += amp * np.asarray(img, np.float64) / 255.0
        tot += amp
        amp *= decay
    out /= tot
    lo, hi = np.percentile(out, 1), np.percentile(out, 99)
    return np.clip((out - lo) / (hi - lo + 1e-9), 0, 1)


def splat(H, W, xs, ys, vals, sigma, wrap=False):
    """bilinear deposit of samples (canvas px) -> (coverage density, value sum), then blurred"""
    if wrap:
        xs, ys = xs % W, ys % H
    acc = np.zeros(H * W)
    accv = np.zeros(H * W)
    x0 = np.floor(xs).astype(np.int64)
    y0 = np.floor(ys).astype(np.int64)
    fx = xs - x0
    fy = ys - y0
    for dx, dy, wgt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        xi, yi = x0 + dx, y0 + dy
        if wrap:
            xi, yi = xi % W, yi % H
        ok = (xi >= 0) & (xi < W) & (yi >= 0) & (yi < H)
        idx = yi[ok] * W + xi[ok]
        acc += np.bincount(idx, weights=wgt[ok], minlength=H * W)
        accv += np.bincount(idx, weights=(wgt * vals)[ok], minlength=H * W)
    acc = blur(acc.reshape(H, W), sigma, wrap)
    accv = blur(accv.reshape(H, W), sigma, wrap)
    return acc, accv


# ----------------------------------------------------------------------------- coils
def coil_samples(rng, n, centres, radius, turns, pitch, axis, axis_jit, tilt, wander, step=0.45):
    """n springs: per coil (centre, axis angle) -> concatenated sample arrays x, y, z (loop depth -1..1),
    coil id. radius / turns / pitch: (lo, hi) ranges (canvas px). axis: base angle per coil (array) or None
    (random); tilt: how open the loops are (0 = a zigzag line, 1 = round loops); wander: axis bend."""
    xs, ys, zs, ids = [], [], [], []
    for i in range(n):
        rc = rng.uniform(*radius)
        tn = rng.uniform(*turns)
        pt = rc * rng.uniform(*pitch)
        a0 = (axis[i] if axis is not None else rng.uniform(0, 2 * math.pi)) + rng.normal(0, axis_jit)
        tl = rng.uniform(*tilt)
        L = 2 * math.pi * tn * rc * 1.1 + tn * pt
        m = max(12, int(L / step))
        t = np.linspace(0, 2 * math.pi * tn, m)
        # the axis bends a little along the coil (kinks); the radius breathes (irregular loops)
        ph = rng.uniform(0, 2 * math.pi, 3)
        ang = a0 + wander * (np.sin(t * 0.21 + ph[0]) + 0.5 * np.sin(t * 0.47 + ph[1]))
        rr = rc * (1 + 0.22 * np.sin(t * 0.63 + ph[2]) + rng.normal(0, 0.04, m).cumsum() * 0.02)
        ca, sa = np.cos(ang), np.sin(ang)
        da = np.gradient(t) * pt / (2 * math.pi)
        cx = np.cumsum(ca * da)
        cy = np.cumsum(sa * da)
        cx -= cx[m // 2]
        cy -= cy[m // 2]
        ct, st = np.cos(t + ph[0]), np.sin(t + ph[0])
        # loop: across the axis by cos, along it by sin * tilt (an open helix seen at an angle)
        x = centres[i][0] + cx + (-sa) * rr * ct + ca * rr * st * tl
        y = centres[i][1] + cy + ca * rr * ct + sa * rr * st * tl
        xs.append(x)
        ys.append(y)
        zs.append(st)
        ids.append(np.full(m, i))
    return np.concatenate(xs), np.concatenate(ys), np.concatenate(zs), np.concatenate(ids)


def sample_centres(rng, n, D, margin=0):
    """n points distributed by the density map D (canvas px)"""
    H, W = D.shape
    p = D.ravel() / D.sum()
    idx = rng.choice(H * W, size=n, p=p)
    y, x = np.divmod(idx, W)
    return np.stack([x + rng.random(n), y + rng.random(n)], axis=1)


def composite(H, W, layers):
    """layers: list of (coverage 0..1, albedo) back to front -> (albedo, alpha)"""
    C = np.zeros((H, W))
    A = np.zeros((H, W))
    for a, c in layers:
        C = c * a + C * (1 - a)
        A = a + A * (1 - a)
    return C / np.maximum(A, 1e-6) * (A > 1e-6), A


def coil_batches(rng, H, W, cents, depth, nb, prm, stroke, bright, dark_deep=0.5, wrap=False):
    """the coils in nb depth batches (deep first, darker), each splatted and turned into (coverage, albedo)"""
    order = np.argsort(depth)
    out = []
    per = int(math.ceil(len(cents) / nb))
    for b in range(nb):
        sel = order[b * per:(b + 1) * per]
        if len(sel) == 0:
            continue
        x, y, z, ids = coil_samples(rng, len(sel), cents[sel], axis=prm.get("axis")[sel] if prm.get("axis") is not None else None,
                                    **{k: v for k, v in prm.items() if k != "axis"})
        d = depth[sel][ids]
        base = rng.uniform(0.78, 1.0, len(sel))[ids]
        # near side of each loop catches the light; deeper coils are darker
        val = base * (0.5 + 0.5 * (z * 0.5 + 0.5) ** 0.8) * (dark_deep + (1 - dark_deep) * d) * bright
        acc, accv = splat(H, W, x, y, val, stroke, wrap)
        cov = 1 - np.exp(-acc * 4.0)
        alb = accv / np.maximum(acc, 1e-6)
        out.append((cov, np.clip(alb, 0, 1)))
    return out


# ----------------------------------------------------------------------------- cells
def cloud(w, h, seed, n, radius, turns, pitch, tilt, wander, fill, r0=0.36, spread=0.5, stroke=1.25,
          bright=1.0, lump=0.25):
    """a soft round cloud of coils (a surface patch); returns (albedo, alpha) at w x h"""
    rng = RNG(seed)
    W, H = w * SS, h * SS
    yy, xx = np.mgrid[0:H, 0:W]
    nx = (xx + 0.5) / W * 2 - 1
    ny = (yy + 0.5) / H * 2 - 1
    ang = np.arctan2(ny, nx)
    # an irregular, lumpy outline (broad wobble), far from any leaf / circle
    wob = np.zeros_like(nx)
    for k, amp in ((2, 0.10), (3, 0.09), (5, 0.06), (7, 0.04)):
        wob += amp * np.sin(k * ang + rng.uniform(0, 2 * math.pi))
    nz = fbm(H, W, seed + 1, cells=3, octaves=4)
    r = np.hypot(nx, ny) / (r0 * 2 * (1 + wob) * (0.85 + 0.3 * nz))
    edge = np.hypot(nx, ny)
    keep = sstep(0.98, 0.86, edge)  # nothing at the cell border
    lumps = fbm(H, W, seed + 2, cells=5, octaves=3)
    D = sstep(1.0, 1.0 - spread, r) * (1 - lump + lump * lumps) * keep
    cents = sample_centres(rng, n, D)
    depth = rng.random(n) ** 0.8
    # a coil near the centre sits deeper in the clump; one out on the edge is in front
    rc = np.hypot(cents[:, 0] / W * 2 - 1, cents[:, 1] / H * 2 - 1)
    depth = np.clip(0.65 * depth + 0.35 * np.clip(rc / (r0 * 2), 0, 1), 0, 1)
    prm = dict(radius=radius, turns=turns, pitch=pitch, axis=None, axis_jit=0.0, tilt=tilt, wander=wander)
    layers = []
    # the dark fill under the coils: the hair deep inside the clump (near-opaque core, soft edge)
    fa = fill * sstep(0.82, 0.25, r) * (0.75 + 0.25 * fbm(H, W, seed + 3, cells=16, octaves=3)) * keep
    fc = 0.36 + 0.14 * fbm(H, W, seed + 4, cells=24, octaves=2)
    layers.append((fa, fc))
    layers += coil_batches(rng, H, W, cents, depth, 6, prm, stroke * SS, bright)
    C, A = composite(H, W, layers)
    A *= keep
    return down(C, A, w, h)


def tuft(w, h, seed, n, radius, turns, pitch, tilt, wander, fill, stroke=1.25, width=0.36, axis_jit=0.5,
         ringlets=0, bright=1.0):
    """a fuzz tuft (a fin card): root at the top row (v = 0) .. sparse frizzy tips at the bottom"""
    rng = RNG(seed)
    W, H = w * SS, h * SS
    yy, xx = np.mgrid[0:H, 0:W]
    nx = (xx + 0.5) / W * 2 - 1
    t = (yy + 0.5) / H  # 0 root .. 1 tip
    nz = fbm(H, W, seed + 1, cells=3, octaves=4)
    wid = width * (1 - 0.5 * t) * (0.8 + 0.4 * nz)
    sideD = sstep(1.0, 0.35, np.abs(nx) / (wid * 2))
    keep = sstep(0.99, 0.9, np.abs(nx)) * sstep(0.0, 0.16, t) * sstep(1.0, 0.95, t)
    D = sideD * sstep(0.98, 0.3, t + 0.25 * (nz - 0.5)) * (0.35 + 0.65 * sstep(0.0, 0.2, t)) * keep
    layers = []
    fa = fill * sideD * sstep(0.6, 0.1, t) * (0.7 + 0.3 * fbm(H, W, seed + 3, cells=12, octaves=3)) * keep
    layers.append((fa, 0.32 + 0.1 * fbm(H, W, seed + 4, cells=20, octaves=2)))
    if n:
        cents = sample_centres(rng, n, D)
        depth = rng.random(n)
        axis = np.full(n, math.pi / 2) + rng.normal(0, 0.35, n)  # mostly root -> tip
        prm = dict(radius=radius, turns=turns, pitch=pitch, axis=axis, axis_jit=axis_jit, tilt=tilt, wander=wander)
        layers += coil_batches(rng, H, W, cents, depth, 4, prm, stroke * SS, bright)
    if ringlets:
        # a few long ringlets: several strands round one spiral, root to tip
        for k in range(ringlets):
            x0 = W * (0.5 + (k - (ringlets - 1) / 2) * 0.28 + rng.normal(0, 0.04))
            rc = W * rng.uniform(0.07, 0.1)
            pitch_ = rc * rng.uniform(1.3, 1.7)
            length = H * rng.uniform(0.7, 0.9)
            xs, ys, zs = [], [], []
            for s in range(8):
                m = int(length / 0.4)
                yv = np.linspace(H * 0.02, length, m)
                tt = yv / pitch_ * 2 * math.pi + s * 0.32 + rng.normal(0, 0.1)
                taper = 1 - 0.35 * (yv / H)
                drift = W * 0.05 * np.sin(yv / H * 2.2 + k)
                r_s = rc * taper * (1 + 0.1 * (s - 3.5) / 3.5)
                xs.append(x0 + drift + r_s * np.cos(tt) + rng.normal(0, 0.8, m).cumsum() * 0.05)
                ys.append(yv + r_s * 0.35 * np.sin(tt))
                zs.append(np.sin(tt))
            x, y, z = np.concatenate(xs), np.concatenate(ys), np.concatenate(zs)
            val = (0.45 + 0.55 * (z * 0.5 + 0.5)) * bright
            acc, accv = splat(H, W, x, y, val, stroke * SS * 1.1)
            layers.append((1 - np.exp(-acc * 4.0), np.clip(accv / np.maximum(acc, 1e-6), 0, 1)))
    C, A = composite(H, W, layers)
    A *= keep
    return down(C, A, w, h)


def pnoise(H, W, seed, scale):
    """periodic smooth noise 0..1 (FFT-filtered white noise)"""
    rng = RNG(seed)
    n = rng.normal(size=(H, W))
    n = blur(n, scale, wrap=True)
    lo, hi = np.percentile(n, 1), np.percentile(n, 99)
    return np.clip((n - lo) / (hi - lo + 1e-9), 0, 1)


def tile(w, h, seed, n, fill, fill_tone=0.36, stroke=1.0, nb=6, holes=0.0, dark_deep=0.5, **prm):
    """a tileable coil tile (continuous shells): coils spread evenly (wrapping), over a fill"""
    rng = RNG(seed)
    W, H = w * SS, h * SS
    cents = np.stack([rng.random(n) * W, rng.random(n) * H], axis=1)
    depth = rng.random(n)
    layers = []
    cl = pnoise(H, W, seed + 3, 30 * SS / 2)  # clump-scale variation of the fill
    fa = np.clip(fill * (0.75 + 0.5 * (cl - 0.5)) - holes * sstep(0.35, 0.0, cl), 0, 1)
    layers.append((fa, fill_tone + 0.12 * pnoise(H, W, seed + 4, 3 * SS)))
    p = dict(prm, axis=None, axis_jit=0.0)
    layers += coil_batches(rng, H, W, cents, depth, nb, p, stroke * SS, 1.0, dark_deep=dark_deep, wrap=True)
    C, A = composite(H, W, layers)
    return down(C, A, w, h)


def down(C, A, w, h):
    """supersampled -> cell resolution (premultiplied box filter)"""
    H, W = A.shape
    k = H // h
    pa = (C * A).reshape(h, k, w, k).mean(axis=(1, 3))
    a = A.reshape(h, k, w, k).mean(axis=(1, 3))
    c = pa / np.maximum(a, 1e-6)
    return c, a


def bleed(lum, alp, passes=12):
    """spread colour into transparent texels (mip-friendly)"""
    L = lum.copy()
    w = (alp > 0.02).astype(np.float64)
    L *= w
    for _ in range(passes):
        s = blur(L * 1.0, 2.0)
        n = blur(w, 2.0)
        fillv = s / np.maximum(n, 1e-6)
        L = np.where(w > 0, L, fillv)
        w = np.maximum(w, (n > 1e-3).astype(np.float64))
    return np.where(alp > 0.02, lum, L)


def tex_coily(size=SIZE, seed=31):
    """the whole atlas -> (lum 0..1, alpha 0..1) at size x size"""
    half, quarter = size // 2, size // 4
    s = size / 1024
    L = np.zeros((size, size))
    A = np.zeros((size, size))
    tight = dict(radius=(13 * s * SS, 21 * s * SS), turns=(1.6, 3.2), pitch=(0.5, 1.0), tilt=(0.5, 1.0),
                 wander=0.5)
    cells = {
        "CLOUD_A": cloud(half, half, seed + 10, n=420, fill=0.9, r0=0.37, spread=0.55, stroke=1.0, **tight),
        # the shells: dense (inner, near-opaque) and sparse (outer: single coils, the fuzzy silhouette by stacking)
        "TILE_D": tile(half, half, seed + 20, n=820, fill=0.93, fill_tone=0.44, stroke=1.0, dark_deep=0.66, **tight),
        "TILE_S": tile(half, quarter, seed + 30, n=190, fill=0.0, stroke=1.0, nb=4, **tight),
        # the Curly variant's outer shells: looser, larger curls (open loops, short ringlet arcs)
        "TILE_L": tile(half, quarter, seed + 35, n=70, fill=0.0, stroke=1.25, nb=4,
                       radius=(22 * s * SS, 34 * s * SS), turns=(1.1, 2.0), pitch=(0.8, 1.4), tilt=(0.35, 0.7),
                       wander=0.35),
        "FIN_T": tuft(quarter, half, seed + 40, n=110, fill=0.15, stroke=1.0, **tight),
        "FIN_L": tuft(quarter, half, seed + 50, n=20, radius=(16 * s * SS, 24 * s * SS), turns=(1.2, 2.2),
                      pitch=(0.9, 1.4), tilt=(0.3, 0.6), wander=0.3, fill=0.3, stroke=1.3, ringlets=3),
    }
    for k, (c, a) in cells.items():
        u0, v0, u1, v1 = CELLS[k]
        x0, y0 = int(u0 * size), int(v0 * size)
        L[y0:y0 + c.shape[0], x0:x0 + c.shape[1]] = c
        A[y0:y0 + a.shape[0], x0:x0 + a.shape[1]] = a
    return L, A


def save(path, lum, alp, lo=0.25, hi=1.0):
    lum = bleed(np.clip(lum, 0, 1), alp)
    g = lo + (hi - lo) * np.clip(lum, 0, 1)
    img = np.dstack([g, g, g, np.clip(alp, 0, 1)])
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(path)
    return path


if __name__ == "__main__":
    import sys
    import time
    t0 = time.time()
    L, A = tex_coily()
    out = sys.argv[1] if len(sys.argv) > 1 else "hair_coily.png"
    save(out, L, A)
    print("wrote", out, f"{time.time() - t0:.1f}s", "mean alpha", A.mean())
