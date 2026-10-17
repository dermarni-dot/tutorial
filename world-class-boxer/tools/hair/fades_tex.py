"""Textures of the fades family (numpy, deterministic): the scalp cap's tiles and the crop-top tufts.

* short      128 x 256 tile (tileable): 1-4 mm hairs lying along +v (away from the crown on the cap's polar UV)
* shortcoil  128 x 256 tile (tileable): tiny tight coils, randomly turned, evenly packed (no dark clumps)
* waves      1024 x 1024 whole-cap image (capTileRepeat {1, 1}): 360 waves, ~15 ridges crown -> nape, a calm whorl
             at the crown, every ridge its own phase / amplitude (no u-periodic star)
* crop       512 x 512, 4 tuft strips, root (v 0) to tip (v 1), alpha fading in at the root

The cap tiles are drawn on a square, physically isotropic canvas (one tile covers ~0.33 x 0.29 studs of scalp
at the equator: 8 x 4 repeats) and box-filtered to 128 x 256, so one tile texel is one cap texel at the full
LOD's 1024 cap (no aliasing when the game paints it). Greyscale albedo is high (mean ~0.8: a multiplied
blonde stays blonde); darkness only at the roots and in the gaps.
"""
import math

import numpy as np
from PIL import Image

TAU = 2 * math.pi


def pnoise(h, w, seed, fmax=4, amp_decay=0.7):
    """tileable smooth noise in ~[-1, 1] (random cosines with integer frequencies)"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    u, v = xx / w, yy / h
    out = np.zeros((h, w))
    tot = 0.0
    for fx in range(-fmax, fmax + 1):
        for fy in range(0, fmax + 1):
            if fx == 0 and fy == 0:
                continue
            f = math.hypot(fx, fy)
            if f > fmax:
                continue
            a = amp_decay ** f * rng.uniform(0.5, 1.0)
            out += a * np.cos(TAU * (fx * u + fy * v) + rng.uniform(0, TAU))
            tot += a
    return out / max(1e-9, tot) * 2.2


class Canvas:
    """greyscale + alpha, 'over' compositing, wrapping in both axes when tile=True"""

    def __init__(self, w, h, tile=True, base_lum=0.5):
        self.w, self.h, self.tile = w, h, tile
        self.L = np.full((h, w), base_lum, np.float32)
        self.A = np.zeros((h, w), np.float32)

    def strand(self, xs, ys, wid, lum, op):
        xs, ys = np.asarray(xs, np.float64), np.asarray(ys, np.float64)
        wid, lum, op = np.asarray(wid, np.float64), np.asarray(lum, np.float64), np.asarray(op, np.float64)
        r = wid.max() * 0.5 + 1.5
        x0, x1 = int(math.floor(xs.min() - r)), int(math.ceil(xs.max() + r))
        y0, y1 = int(math.floor(ys.min() - r)), int(math.ceil(ys.max() + r))
        if not self.tile:
            x0, y0 = max(0, x0), max(0, y0)
            x1, y1 = min(self.w - 1, x1), min(self.h - 1, y1)
            if x1 < x0 or y1 < y0:
                return
        gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1].astype(np.float64)
        px, py = gx + 0.5, gy + 0.5
        cov = np.zeros(gx.shape)
        sh = np.zeros(gx.shape)
        for i in range(len(xs) - 1):
            ax, ay, bx, by = xs[i], ys[i], xs[i + 1], ys[i + 1]
            dx, dy = bx - ax, by - ay
            ll = dx * dx + dy * dy
            t = np.clip(((px - ax) * dx + (py - ay) * dy) / max(ll, 1e-9), 0, 1)
            qx, qy = ax + dx * t - px, ay + dy * t - py
            d = np.sqrt(qx * qx + qy * qy)
            rr = (wid[i] + (wid[i + 1] - wid[i]) * t) * 0.5
            # a sub-pixel strand keeps its energy: coverage = width where it is thinner than a pixel
            c = np.clip(np.maximum(rr, 0.5) + 0.5 - d, 0, 1) * np.minimum(1.0, 2 * rr) \
                * (op[i] + (op[i + 1] - op[i]) * t)
            s = lum[i] + (lum[i + 1] - lum[i]) * t
            m = c > cov
            cov = np.where(m, c, cov)
            sh = np.where(m, s, sh)
        if self.tile:
            iy = np.arange(y0, y1 + 1) % self.h
            ix = np.arange(x0, x1 + 1) % self.w
            Ls = self.L[np.ix_(iy, ix)]
            As = self.A[np.ix_(iy, ix)]
            self.L[np.ix_(iy, ix)] = sh * cov + Ls * (1 - cov)
            self.A[np.ix_(iy, ix)] = cov + As * (1 - cov)
        else:
            Ls = self.L[y0:y1 + 1, x0:x1 + 1]
            As = self.A[y0:y1 + 1, x0:x1 + 1]
            self.L[y0:y1 + 1, x0:x1 + 1] = sh * cov + Ls * (1 - cov)
            self.A[y0:y1 + 1, x0:x1 + 1] = cov + As * (1 - cov)

    def down(self, fx, fy=None):
        """box filter by fx (columns) x fy (rows), premultiplied (transparent texels never pull the colour)"""
        fy = fy or fx
        h, w = self.h // fy, self.w // fx
        A = self.A.reshape(h, fy, w, fx).mean(axis=(1, 3))
        LA = (self.L * self.A).reshape(h, fy, w, fx).mean(axis=(1, 3))
        L = np.where(A > 1e-4, LA / np.maximum(A, 1e-4), self.L.reshape(h, fy, w, fx).mean(axis=(1, 3)))
        return L, A


def save_tex(path, L, A, lo=0.25, hi=1.0):
    L = np.clip(L, lo, hi)
    A = np.clip(A, 0, 1)
    if (A > 0.02).any():
        mean = float((L * A).sum() / max(1e-6, A.sum()))
        L = np.where(A > 0.02, L, mean)
    g = (L * 255 + 0.5).astype(np.uint8)
    a = (A * 255 + 0.5).astype(np.uint8)
    Image.fromarray(np.dstack([g, g, g, a]), "RGBA").save(path, optimize=True)
    return path


def rank_dither(A, seed, lo=0.84, hi=0.99, blur=0.6):
    """Decorrelate the tile's alpha rank from its low-frequency structure. The game's PaintCap thins a fade (and
    a < 1 density such as the Buzz Cut's 0.62) by thresholding each texel's (alpha, grey) rank: if the dense
    texels all saturate, the grey's slow lock-to-lock variation decides the order and the cap thins in blotches.
    A fine, uniform-rank noise (~1-2 texels: ~0.5 mm on the scalp) scales the alpha so the thinning is an even
    stubble speckle; the gaps between strands (low alpha) still go first."""
    h, w = A.shape
    rng = np.random.default_rng(seed)
    n = rng.random((h, w))
    if blur > 0:
        k = np.array([math.exp(-0.5 * (i / blur) ** 2) for i in (-2, -1, 0, 1, 2)])
        k /= k.sum()
        n = sum(kk * np.roll(n, i - 2, 0) for i, kk in enumerate(k))
        n = sum(kk * np.roll(n, i - 2, 1) for i, kk in enumerate(k))
    r = np.empty(h * w)
    r[np.argsort(n.ravel(), kind="stable")] = (np.arange(h * w) + 0.5) / (h * w)
    return A * (lo + (hi - lo) * r.reshape(h, w))


# canvas for one cap tile: 1024 x 1024 px ~ 0.33 x 0.29 studs (px ~ 0.0003 studs ~ 0.06 mm), filtered 8 x 4
TILE_CANVAS = 1024
PX_PER_STUD = 3300.0
MM = PX_PER_STUD * 1.2 / 230.0  # canvas px per millimetre (a 1.2-stud head is ~23 cm tall)


def _wrap_noise(seed, fmax=3):
    n = pnoise(64, 64, seed, fmax=fmax)

    def at(x, y):
        return n[int(y / TILE_CANVAS * 64) % 64, int(x / TILE_CANVAS * 64) % 64]
    return at


def tex_short(seed=21):
    """Short hair lying back from the crown (+v): ~0.08 mm hairs in loose parallel locks, 1.5-4.5 mm of each
    visible, dark at the root (where it leaves the scalp) and light toward the tip; the lock direction drifts
    slowly (+-12 deg). An undercoat of shorter, darker hairs fills between the locks (the scalp barely shows
    at full coverage); the fade's threshold removes the faint undercoat first."""
    W = TILE_CANVAS
    cv = Canvas(W, W, tile=True, base_lum=0.55)
    rng = np.random.default_rng(seed)
    flow = _wrap_noise(seed + 1)
    lockn = _wrap_noise(seed + 3, fmax=6)
    # undercoat
    for _ in range(9000):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        ang = math.pi / 2 + 0.2 * flow(x, y) + rng.normal(0, 0.28)
        L = rng.uniform(1.0, 2.2) * MM
        g = rng.uniform(0.5, 0.64)
        cv.strand([x, x + math.cos(ang) * L], [y, y + math.sin(ang) * L], [2.0, 1.6], [g - 0.06, g],
                  [0.85, 0.65])
    # the coat: hairs in locks (a lock = a few hairs sharing a root area and direction)
    nlocks = 4200
    for _ in range(nlocks):
        cx, cy = rng.uniform(0, W), rng.uniform(0, W)
        ang0 = math.pi / 2 + 0.2 * flow(cx, cy) + rng.normal(0, 0.12)
        base = 0.86 + 0.14 * lockn(cx, cy) + rng.normal(0, 0.05)
        for _ in range(int(rng.integers(2, 6))):
            x, y = cx + rng.normal(0, 2.2), cy + rng.normal(0, 2.2)
            ang = ang0 + rng.normal(0, 0.07)
            L = rng.uniform(1.5, 4.5) * MM
            m = 5
            t = np.linspace(0, 1, m)
            a = ang + rng.normal(0, 0.12) * t
            xs = x + np.concatenate([[0], np.cumsum(np.cos(a[:-1]) * L / (m - 1))])
            ys = y + np.concatenate([[0], np.cumsum(np.sin(a[:-1]) * L / (m - 1))])
            lum = np.clip(base * (0.62 + 0.4 * t ** 0.7), 0.3, 1.0)
            wid = (1.7 - 0.9 * t ** 1.5) * rng.uniform(0.85, 1.2)
            op = np.clip(0.95 - 0.5 * t ** 2.5, 0, 1)
            cv.strand(xs, ys, wid, lum, op)
    L, A = cv.down(8, 4)
    A = np.clip(0.06 + A * 1.08, 0, 1.0)
    return L, rank_dither(A, seed + 9)


def tex_shortcoil(seed=61):
    """Tiny tight coils (Curly / Kinky / Coiled short hair): ~2-3.5 mm loops, each coil a few turns of a hair
    seen from above at a random tilt and turn, packed evenly with a blue-noise-ish jitter (no clusters, no dark
    blotches). Each loop is lit on its crown-facing side; the gaps are a soft mid tone, not black."""
    W = TILE_CANVAS
    cv = Canvas(W, W, tile=True, base_lum=0.6)
    rng = np.random.default_rng(seed)
    # dense fine frizz underneath
    for _ in range(6000):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        r = rng.uniform(0.5, 1.0) * MM
        t = np.linspace(0, rng.uniform(1.0, 1.7) * TAU, 9)
        a0 = rng.uniform(0, TAU)
        cv.strand(x + np.cos(a0 + t) * r, y + np.sin(a0 + t) * r * rng.uniform(0.6, 1.0),
                  np.full(9, 2.0), np.full(9, rng.uniform(0.5, 0.62)), np.full(9, 0.75))
    # coils on a jittered grid (periodic): ~even spacing
    g = 18
    cell = W / g
    order = rng.permutation(g * g * 2)
    for q in order:
        i, j = (q // 2) % g, (q // 2) // g
        x = (i + 0.5 + rng.uniform(-0.45, 0.45)) * cell
        y = (j + 0.5 + rng.uniform(-0.45, 0.45)) * cell
        if q % 2:
            x, y = x + cell * 0.5, y + cell * 0.5
        r = rng.uniform(1.4, 2.4) * MM
        squash = rng.uniform(0.55, 1.0)  # tilt of the coil's axis toward the viewer
        rot = rng.uniform(0, TAU)
        turns = rng.uniform(1.6, 2.6)
        m = int(12 * turns)
        t = np.linspace(0, turns * TAU, m)
        a0 = rng.uniform(0, TAU)
        along = (t / (turns * TAU) - 0.5) * r * rng.uniform(0.6, 1.4)
        lx = np.cos(a0 + t) * r
        ly = np.sin(a0 + t) * r * squash + along
        cr, sr = math.cos(rot), math.sin(rot)
        xs = x + lx * cr - ly * sr
        ys = y + lx * sr + ly * cr
        # lit on the near (upper) part of each turn, a little on the crown-facing side
        front = 0.5 + 0.5 * np.sin(a0 + t)
        up = 0.5 - 0.5 * np.clip((ys - y) / (r * 1.5), -1, 1)
        lum = np.clip((0.52 + 0.36 * front ** 1.5 + 0.12 * up) * rng.uniform(0.92, 1.06), 0.3, 1.0)
        cv.strand(xs, ys, np.full(m, rng.uniform(2.6, 3.4)), lum, np.full(m, 0.95))
    L, A = cv.down(8, 4)
    A = np.clip(0.06 + A * 1.04, 0, 1.0)
    return L, rank_dither(A, seed + 9, lo=0.86, blur=1.0)


# ---------------------------------------------------------------------------------------- 360 waves
WAVES_SIZE = 1024
WAVES_V0 = 0.056  # ridge spacing in v (theta / thetaMax): ~1.6 cm on the scalp, ~15 ridges crown -> nape
WAVES_CALM = 0.12  # v below this: the crown's whorl (no ridges)


def tex_waves(theta_max, seed=71, size=WAVES_SIZE):
    """360 waves as one whole-cap image on the polar UV (u = az / 2pi, v = theta / thetaMax; repeated 1 x 1):
    hair brushed out from the crown lying in ripples that ring the head. Every ridge has its own phase drift and
    amplitude round the head (random low harmonics in u over the WHOLE circle: nothing repeats), the ripples
    fade out toward the crown into a calm whorl (the hair turns round the crown there), and each ridge is shaded
    as a crest: a highlight on its crown-facing slope, a soft shadow in the trough below it.
    Built with line-integral convolution: white noise smeared along the hair's direction (snaking with the
    ripple), so the strands are continuous and the image is fast to make."""
    rng = np.random.default_rng(seed)
    H = W = size
    j, i = np.mgrid[0:H, 0:W].astype(np.float64)
    u = (i + 0.5) / W
    v = (j + 0.5) / H
    th = v * theta_max
    # texel aspect: a u texel is 2 pi sin(theta) / (theta_max) times a v texel on the scalp
    asp = np.maximum(0.06, TAU * np.sin(th) / theta_max)
    calm = np.clip((v - WAVES_CALM * 0.6) / (WAVES_CALM * 0.8), 0, 1) ** 1.5

    def harmonics(n, amp, seed2):
        r = np.random.default_rng(seed2)
        out = np.zeros_like(u)
        for k in range(1, n + 1):
            out += amp / k ** 0.9 * r.uniform(0.3, 1.0) * np.cos(TAU * k * u + r.uniform(0, TAU))
        return out
    # ridge phase: rings of v, drifting round the head (low harmonics), a little per-ridge noise
    drift = harmonics(4, 0.4, seed + 1) + harmonics(9, 0.1, seed + 2)
    phase = (v - WAVES_CALM) / WAVES_V0 + drift * calm
    ridge = np.floor(phase)
    # per-ridge amplitude and extra phase (by ridge index, varying round the head)
    amp = np.ones_like(u)
    for r0 in range(-4, 40):
        m = ridge == r0
        if not m.any():
            continue
        rr = np.random.default_rng(seed * 100 + r0 + 7)
        a = 0.75 + 0.25 * np.cos(TAU * rr.integers(1, 4) * u + rr.uniform(0, TAU)) + rr.normal(0, 0.05)
        amp = np.where(m, a, amp)
    amp = amp * calm
    f = phase - ridge  # 0..1 inside a ridge: crest at ~0.35
    # height profile: a rounded crest, a long trough (asymmetric, like brushed waves)
    h = np.where(f < 0.35, np.sin(f / 0.35 * math.pi / 2), np.cos((f - 0.35) / 0.65 * math.pi / 2) ** 1.6)
    dh = np.gradient(h, axis=0)  # along v (rows)
    lit = np.clip(-dh * 18, -1, 1)  # crown-facing slope lit (rows grow away from the crown)
    # hair direction: +v, snaking with the ripple (lateral u offset ~ the slope); round the crown a swirl
    swirl = (1 - calm) * 0.9
    ang = np.pi / 2 + amp * 0.38 * np.cos(TAU * f) + swirl
    # line integral convolution of white noise along the direction field (in texel units, aspect corrected)
    noise = rng.random((H, W))
    acc = np.zeros((H, W))
    wsum = 0.0
    L = 9
    for sgn in (1, -1):
        x, y = i.copy(), j.copy()
        for s in range(L):
            wgt = 1.0 - s / L
            xi = np.mod(np.round(x).astype(int), W)
            yi = np.clip(np.round(y).astype(int), 0, H - 1)
            acc += noise[yi, xi] * wgt
            wsum += wgt
            a = ang[yi, xi]
            x = x + sgn * np.cos(a) / asp[yi, xi] * 1.0
            y = y + sgn * np.sin(a) * 1.0
    lic = acc / wsum
    lic = (lic - lic.mean()) / (lic.std() + 1e-9)
    strands = np.clip(0.5 + 0.22 * lic, 0, 1)
    lum = 0.74 + 0.2 * lit * amp + 0.12 * (h - 0.5) * amp + 0.18 * (strands - 0.5)
    lum = lum - 0.16 * amp * np.clip(-lit, 0, 1)  # the trough's soft shadow
    A = np.clip(0.9 + 0.14 * (strands - 0.5) - 0.05 * np.clip(-lit, 0, 1) * amp, 0, 0.98)
    return lum, A


# ---------------------------------------------------------------------------------------- crop tufts
CROP_STRIPS = 4


def tex_crop(w=512, h=512, seed=81, ss=2):
    """Short tufts for the crop-top cards: CROP_STRIPS strips across u, each a tuft of fine hairs from a broad
    root (v 0) converging into a few tapered points (v 1). Alpha fades in over the first ~30 % (the card grows
    out of the hair under it: no visible card start), at both sides, and to the tips. Mean grey ~0.8."""
    W, H = w * ss, h * ss
    cv = Canvas(W, H, tile=False, base_lum=0.7)
    rng = np.random.default_rng(seed)
    sw = W / CROP_STRIPS
    for s in range(CROP_STRIPS):
        x0 = s * sw
        blunt = s == 0  # strip 0: a blunt-cut tuft (hairs side by side, ending together near v 1: a fringe)
        npts = 3 + s % 3
        tips = [x0 + sw * (0.22 + 0.56 * (i + rng.uniform(0.25, 0.75)) / npts) for i in range(npts)]
        for _ in range(170 + 20 * s):
            rx = x0 + sw * (0.5 + 0.4 * rng.uniform(-1, 1) * abs(rng.uniform(-1, 1)) ** 0.3)
            tx = tips[rng.integers(npts)] + rng.normal(0, sw * 0.035)
            if blunt:
                tx = rx + rng.normal(0, sw * 0.03)
            L = H * (rng.uniform(0.86, 0.95) if blunt else rng.uniform(0.55, 0.97))
            m = 10
            t = np.linspace(0, 1, m)
            pull = t ** 1.3
            xs = rx + (tx - rx) * pull * (L / H) + np.sin(t * 3 + rng.uniform(0, TAU)) * sw * 0.012
            ys = H * rng.uniform(0.0, 0.06) + t * L
            lum = np.clip(rng.uniform(0.88, 1.05) * (0.66 + 0.36 * t ** 0.7), 0.3, 1.0)
            wid = np.maximum(0.8, (3.2 - 2.2 * t ** 1.2)) * rng.uniform(0.8, 1.2)
            if blunt:
                op = 0.85 * np.clip(np.minimum(t / 0.3, 1) ** 1.6 * (1 - np.maximum(0, t - 0.9) / 0.1 * 0.4), 0, 1)
                wid = np.maximum(1.2, 2.8 - 0.8 * t)
            else:
                op = 0.85 * np.clip(np.minimum(t / 0.3, 1) ** 1.6 * (1 - np.maximum(0, t - 0.72) / 0.28 * 0.9), 0, 1)
            cv.strand(xs, ys, wid, lum, op * rng.uniform(0.8, 1.0))
    L, A = cv.down(ss)
    hh, ww = A.shape
    uu = (np.arange(ww) + 0.5) / ww * CROP_STRIPS
    fu = uu - np.floor(uu)
    side = np.clip(np.minimum(fu, 1 - fu) / 0.12, 0, 1)
    A = A * side[None, :]
    return L, A
