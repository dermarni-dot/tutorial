"""Textures of the fades family (numpy, deterministic): the scalp cap's tiles and the crop-top tufts.

* short      128 x 256 tile (tileable): 1-4 mm hairs lying along +v (away from the crown on the cap's polar UV)
* shortcoil  128 x 256 tile (tileable): tiny tight coils, randomly turned, evenly packed (no dark clumps)
* waves      1024 x 1024 whole-cap image (capTileRepeat {1, 1}): 360 waves, ~23 ridges crown -> nape, tighter toward the hairline, in shallow chevrons, a calm whorl
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


def blue_noise(h, w, seed, sigma=1.3, iters=2):
    """tileable blue-ish noise ranked uniform in (0, 1): white noise high-passed (minus its wrapped gaussian blur)
    twice, so neighbouring texels are anti-correlated (no clumps above ~2 texels: an even speckle when thresholded)"""
    rng = np.random.default_rng(seed)
    n = rng.random((h, w))
    r = int(math.ceil(sigma * 3))
    k = np.array([math.exp(-0.5 * (i / sigma) ** 2) for i in range(-r, r + 1)])
    k /= k.sum()
    for _ in range(iters):
        b = sum(kk * np.roll(n, i - r, 0) for i, kk in enumerate(k))
        b = sum(kk * np.roll(b, i - r, 1) for i, kk in enumerate(k))
        n = n - b
        o = np.empty(h * w)
        o[np.argsort(n.ravel(), kind="stable")] = (np.arange(h * w) + 0.5) / (h * w)
        n = o.reshape(h, w)
    return n


def rank_dither(A, seed, lo=0.9, hi=1.0, sigma=1.3):
    """Decorrelate the tile's alpha rank from its low-frequency structure. The game's PaintCap thins a fade (and
    a < 1 density such as the Buzz Cut's 0.62) by thresholding each texel's (alpha, grey) rank: if the dense
    texels all saturate, the grey's slow lock-to-lock variation decides the order and the cap thins in blotches.
    A blue-noise rank (anti-correlated neighbours: ~0.5 mm speckle on the scalp, never clumps) scales the alpha a
    little, so the thinning is an even stubble speckle; the gaps between strands (low alpha) still go first."""
    h, w = A.shape
    return A * (lo + (hi - lo) * blue_noise(h, w, seed, sigma))


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
    for _ in range(14000):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        ang = math.pi / 2 + 0.2 * flow(x, y) + rng.normal(0, 0.28)
        L = rng.uniform(1.0, 2.2) * MM
        g = rng.uniform(0.5, 0.64)
        cv.strand([x, x + math.cos(ang) * L], [y, y + math.sin(ang) * L], [2.0, 1.6], [g - 0.06, g],
                  [0.9, 0.75])
    # the coat: hairs in locks (a lock = a few hairs sharing a root area and direction)
    nlocks = 4200
    for _ in range(nlocks):
        cx, cy = rng.uniform(0, W), rng.uniform(0, W)
        ang0 = math.pi / 2 + 0.2 * flow(cx, cy) + rng.normal(0, 0.12)
        base = 0.86 + 0.04 * lockn(cx, cy) + rng.normal(0, 0.06)  # (no lock-scale blotches)
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
    # a dense, even coat: mean alpha ~0.88 (the scalp barely shows at full coverage), the variation only at strand
    # scale (the gaps between hairs a little lower, never low-frequency patches)
    A = np.clip(0.4 + A * 0.74, 0, 1.0)
    # (compressed toward opaque so the blue-noise rank, not the strands' own clumping, orders the thinning: at the
    # Buzz Cut's 0.62 density the stubble is an even speckle; mean alpha ~0.88)
    A = np.clip(0.72 + 0.28 * A, 0, 1.0)
    return L, rank_dither(A, seed + 9, lo=0.82, hi=1.0)


def tex_shortcoil(seed=61):
    """Tiny tight coils (Curly / Kinky / Coiled short hair): ~3-5 mm coils, each a filled spiral of a hair seen
    from above at a random tilt and turn (the turns touch: a packed sponge-curl blob, dark core, soft highlight on
    its near / crown-facing rim), packed evenly with a blue-noise-ish jitter (no clusters, no dark blotches)."""
    W = TILE_CANVAS
    cv = Canvas(W, W, tile=True, base_lum=0.6)
    rng = np.random.default_rng(seed)
    # dense fine frizz underneath
    for _ in range(9000):
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
        # a filled coil: a spiral from the coil's rim in to ~30 % of its radius, wide enough that the turns touch
        # (a packed blob, not a thin outline): the rim lit on its near / crown-facing side, the core dark
        turns = rng.uniform(2.4, 3.4)
        m = int(14 * turns)
        t = np.linspace(0, turns * TAU, m)
        a0 = rng.uniform(0, TAU)
        rho = r * (1.0 - 0.7 * t / (turns * TAU))
        lx = np.cos(a0 + t) * rho
        ly = np.sin(a0 + t) * rho * squash
        cr, sr = math.cos(rot), math.sin(rot)
        xs = x + lx * cr - ly * sr
        ys = y + lx * sr + ly * cr
        front = 0.5 + 0.5 * np.sin(a0 + t)
        up = 0.5 - 0.5 * np.clip((ys - y) / (r * 1.5), -1, 1)
        core = rho / r
        lum = (0.47 + 0.26 * front ** 1.5 + 0.08 * up) * (0.7 + 0.3 * core) * rng.uniform(0.92, 1.06)
        lum = np.clip(lum, 0.3, 0.86)  # (the rim highlights ~15 % lower than the old outlines)
        wid = np.maximum(3.0, 0.24 * r * (0.7 + 0.3 * core)) * rng.uniform(0.9, 1.1)
        cv.strand(xs, ys, wid, lum, np.full(m, 0.95))
    L, A = cv.down(8, 4)
    A = np.clip(0.34 + A * 0.76, 0, 1.0)
    A = np.clip(0.7 + 0.3 * A, 0, 1.0)
    return L, rank_dither(A, seed + 9, lo=0.82, hi=1.0, sigma=1.6)


# ---------------------------------------------------------------------------------------- 360 waves
WAVES_SIZE = 1024
WAVES_N = 19  # ridges from the calm crown to the cap's edge (the nape)
WAVES_TIGHT = 1.4  # how much tighter the pitch is at the hairline than next to the crown (1 + this)
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
    # ridge phase: rings of v whose pitch tightens away from the crown (broad ripples near the crown, tight ones at
    # the sides and the nape: the brush lays the hair flatter and the waves closer there), WAVES_N ridges in all;
    # drifting round the head (low harmonics) and bent into shallow chevrons (a triangle wave in u whose phase
    # drifts with v and differs side to side), a little per-ridge noise
    vv = np.linspace(0, 1, 2049)
    pitch = 1.0 / (1.0 + WAVES_TIGHT * np.clip((vv - WAVES_CALM) / (1 - WAVES_CALM), 0, 1) ** 1.2)
    F = np.concatenate([[0], np.cumsum(np.diff(vv) / pitch[1:])])
    F = (F - np.interp(WAVES_CALM, vv, F))
    F = F / np.interp(1.0, vv, F) * WAVES_N
    drift = harmonics(4, 0.45, seed + 1) + harmonics(9, 0.12, seed + 2)
    cph = 13.0 * u + 1.7 * v + 0.6 * harmonics(3, 1.0, seed + 5)
    chev = 0.32 * (2 * np.abs(cph - np.floor(cph) - 0.5) - 0.5) * np.clip((v - WAVES_CALM) / 0.25, 0, 1)
    phase = np.interp(v, vv, F) + (drift + chev) * calm
    # uneven, broken crests: the head split into irregular azimuth sectors (5-7 a turn, 1/7..1/4 turn each), each
    # ridge shifted by its own +-0.3 period per sector, blended over a short width at the sector borders (the
    # crests jog there: broken lines, not continuous corduroy rings)
    rs = np.random.default_rng(seed + 11)
    nsec = 6
    cuts = np.sort(rs.uniform(0, 1, nsec))
    ridge0 = np.floor(phase)
    fr0 = phase - ridge0
    sec_off = {}

    def off_of(r0, uu):
        """ridge r0's sector offset at u (sector borders blended over 0.024 turn: the crest jogs there)"""
        if r0 not in sec_off:
            rr = np.random.default_rng(seed * 1000 + 31 * r0 + 5)
            cr = np.sort((cuts + rr.normal(0, 0.03, nsec)) % 1.0)
            sec_off[r0] = (cr, rr.uniform(-0.3, 0.3, nsec))
        cr, offs = sec_off[r0]
        k = np.searchsorted(cr, uu) % nsec
        kp = (k - 1) % nsec
        d_next = (cr[k] - uu) % 1.0
        d_prev = (uu - cr[kp]) % 1.0
        w1 = np.clip(0.5 - d_next / 0.024, 0, 0.5)
        w0 = np.clip(0.5 - d_prev / 0.024, 0, 0.5)
        return offs[kp] * (1 - w1 - w0) + offs[k] * w1 + offs[(kp - 1) % nsec] * w0
    jit = np.zeros_like(u)
    for r0 in range(-4, 40):
        m = ridge0 == r0
        if not m.any():
            continue
        # continuous in v: ridge r0's offset blended into r0 + 1's across the ridge (no seams between ridges)
        t = fr0[m] * fr0[m] * (3 - 2 * fr0[m])
        jit[m] = off_of(r0, u[m]) * (1 - t) + off_of(r0 + 1, u[m]) * t
    phase = phase + jit * calm
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
    f = phase - ridge  # 0..1 inside a ridge: crest at ~0.4
    # height profile: a rounded crest, a long trough (asymmetric, like brushed waves)
    h = np.where(f < 0.4, np.clip(np.sin(f / 0.4 * math.pi / 2), 0, 1) ** 1.3,
                 np.clip(np.cos((f - 0.4) / 0.6 * math.pi / 2), 0, 1) ** 1.3)
    dh = np.gradient(h, axis=0)  # along v (rows)
    lit = np.clip(-dh * 14, -1, 1)  # crown-facing slope lit (rows grow away from the crown)
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
    # the ridge's sheen carried in the albedo (a light crest band), the trough only a little darker and its
    # depth varying along the ridge (breaks), alpha nearly flat (no dark see-through grooves)
    brk = 0.55 + 0.45 * (0.5 + 0.5 * np.cos(TAU * 4 * u + ridge * 2.39 + harmonics(5, 1.5, seed + 13)))
    crest = np.clip(1 - np.abs(f - 0.38) / 0.16, 0, 1) ** 1.5
    lum = 0.7 + 0.16 * crest * amp + 0.07 * lit * amp + 0.18 * (strands - 0.5)
    lum = lum - 0.035 * amp * brk * np.clip(-lit, 0, 1)  # the trough's soft shadow
    A = np.clip(0.91 + 0.14 * (strands - 0.5) - 0.02 * np.clip(-lit, 0, 1) * amp * brk, 0, 0.98)
    return lum, A


# ---------------------------------------------------------------------------------------- crop tufts
CROP_STRIPS = 4


def tex_crop(w=512, h=512, seed=81, ss=2):
    """Short tufts for the crop-top cards: CROP_STRIPS strips across u, each one tapered tuft (a strand group) from
    a broad root (v 0) converging into 2-4 fine points (v 1); strip 0 is a blunt-cut tuft (the Caesar's fringe).
    Strands are distinct (each its own value: dark gaps between groups, no felt), darker at the root (~0.55) and
    ~15 % lighter toward the tip (max albedo 0.86: a multiplied blonde never washes out to straw). Alpha fades in
    over the first ~22 % (the card grows out of the shells: no visible start), at the strip's sides, and to the
    points (tips taper to sub-texel width and fade: no blunt quads)."""
    W, H = w * ss, h * ss
    cv = Canvas(W, H, tile=False, base_lum=0.6)
    rng = np.random.default_rng(seed)
    sw = W / CROP_STRIPS
    for s in range(CROP_STRIPS):
        x0 = s * sw
        blunt = s == 0
        npts = (2, 3, 4)[s % 3] if not blunt else 1
        tips = [x0 + sw * (0.2 + 0.6 * (i + rng.uniform(0.3, 0.7)) / npts) for i in range(npts)]
        nstr = 260 if blunt else 300
        for k in range(nstr):
            # root spread: dense in the middle of the strip, thinning to its sides
            rx = x0 + sw * (0.5 + 0.42 * np.clip(rng.normal(0, 0.45), -1, 1))
            g = int(rng.integers(npts))
            tx = tips[g] + rng.normal(0, sw * 0.02)
            if blunt:
                tx = rx + rng.normal(0, sw * 0.02)
            # strands of a point's group end at different lengths (the point tapers), outer ones shorter
            far = abs(rx - tx) / sw
            L = H * (rng.uniform(0.84, 0.96) if blunt else np.clip(rng.uniform(0.62, 0.98) - 0.5 * far, 0.35, 0.98))
            m = 12
            t = np.linspace(0, 1, m)
            pull = t ** 1.2
            xs = rx + (tx - rx) * pull * (L / H) + np.sin(t * 2.6 + rng.uniform(0, TAU)) * sw * 0.008
            ys = H * rng.uniform(0.0, 0.05) + t * L
            base = rng.uniform(0.54, 0.64) if rng.random() > 0.06 else rng.uniform(0.44, 0.5)  # a few darker strands
            lum = np.clip(base * (1.0 + 0.17 * t ** 0.8) + 0.06 * (1 - far), 0.3, 0.86)
            if blunt:
                wid = np.maximum(1.4, 3.6 - 1.2 * t) * rng.uniform(0.8, 1.2)
                op = np.clip(np.minimum(t / 0.22, 1) ** 1.5, 0, 1) * (1 - 0.35 * np.clip((t - 0.9) / 0.1, 0, 1))
            else:
                wid = np.maximum(0.5, 3.8 * (1 - t ** 1.4)) * rng.uniform(0.8, 1.2)
                op = np.clip(np.minimum(t / 0.22, 1) ** 1.5, 0, 1) * (1 - np.clip((t - 0.78) / 0.22, 0, 1) ** 1.3)
            cv.strand(xs, ys, wid, lum, op * rng.uniform(0.85, 1.0))
    L, A = cv.down(ss)
    hh, ww = A.shape
    uu = (np.arange(ww) + 0.5) / ww * CROP_STRIPS
    fu = uu - np.floor(uu)
    side = np.clip(np.minimum(fu, 1 - fu) / 0.1, 0, 1)
    A = A * side[None, :]
    return np.minimum(L, 0.86), A
