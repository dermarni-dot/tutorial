"""Locs family hair: "Dreadlocks" (long locs onto the shoulders / upper back), "Short Dreads" (the default male
hairstyle: short locs standing and falling from the crown) and "Twists" (medium two-strand twists). Modelled in
Blender (bpy 4.2), exported with hairlib.

    /opt/bpyenv/bin/python tools/hair/build_locs.py [--render DIR] [--only dreadlocks,short_dreads,twists]
                                                    [--no-tex] [--samples N] [--quick]

Writes tools/hair/textures/hair_loc.png, tools/hair/out/<key>/ (meshes + style.json) and
tools/hair/blend/<key>.blend; with --render, Cycles self-check renders and a sheet per style.

How the hair is built (game nominal head space, numerically; see CONTRACT.md):
* Roots: box-parted sections over the default skull: a row along the natural hairline (jittered along and
  across it), sideburn locs, then brick-laid rings round a pole (the vertex; for Short Dreads the crown whorl,
  with a tight ring of small locs round it, and extra rows of fine short locs at the temples and over the ears).
  Coverage passes then add locs where the scalp still shows - from the scalp normal and from the top, back,
  back-34, low-back, side and front view directions - largest gap first, once on the grown guides and once more
  on the relaxed ones, so the cap (cut "full", low density) shows scalp only in the partings between roots.
* Guides: hanging locs (Dreadlocks, Twists) are laid along the scalp from their roots (the style's flow: straight
  back off the face, each section turned +/-15-20 degrees of its own so neighbours cross, a little lift at the
  crown for volume, sideburns up and back, over the ears back above them) and relaxed by a position-based
  simulation: gravity, inextensible segments, bending stiffness, shape memory of the styled part, collisions
  against the game's head mesh and the torso mesh with a body offset (BVH nearest-point queries, Blender
  mathutils), the ear boxes, a face guard, and loc-to-loc repulsion; then a slight S-wave and a settle.
  Short Dreads grow from the whorl flow (a spiral round the whorl, radial further out, +/-25 degrees of smooth
  noise plus each loc's own angle): off the scalp, a soft S of their own (the heading turns about the scalp
  normal one way then the other), drooping under gravity and lying down onto the head, the hairline row rising
  and lying back over the next row; kept within ~1.25 x the head's width and off the face and ears.
  The relaxed guides are kept in the .blend as curve objects.
* Locs: closed tubes along the guides (Short Dreads 7 sides, 6 at the back, 5 on the fine side locs; Dreadlocks
  and Twists 6, 8 on the front hairline row): a root cone growing out of the scalp, closed toward it, lumpy and
  slightly irregular ring to ring, tapering at the tip into a rounded cap (no open ring anywhere). v runs from
  0 at the root to ~1 at the tip of every loc (the game's root-to-tip tints and Tips / Ombre dyes); u wraps once
  round each tube over one or both of the loc core's two identical u-periods (whichever keeps the texture about
  as dense round the loc as along it), twists over the twist core. Twists carry two strand lobes in the geometry
  (a ring every quarter turn) lined up with the twist strip's grooves. The tubes are one Blender mesh (seams
  welded, UVs per corner) with Displace modifiers (Clouds bulges and lumps, weighted off at the roots); the
  evaluated mesh comes back as the game pieces. A frizz fin (two-sided card of the transparent frizz strip)
  twists round each loc as a second Blender mesh.
* Clearance: every vertex is checked against the head mesh (BVH) and kept at least CLEAR_MIN above it (and the
  skull table, also through the female fit), hanging locs at least 0.045 off the torso; soft occlusion is baked
  into the vertex colours with BVH ray casts (locs, head and torso), darker near the scalp and between locs.
* Pieces: static HairTop and swinging chains (hairfx "swing", two segments for Dreadlocks, one for Twists,
  length "hang"). A chain's locs are cut exactly on planes normal to the chain's axis: plane A through its lowest
  leaving point (everything above stays in HairTop, so nothing that lies on the scalp swings) and, for
  Dreadlocks, plane B half way down; the pivots are the means of the cut points (every break lies on its
  joint's plane) and the ring interval just below a cut is also emitted into the piece above as a sleeve, so a
  swinging lower piece does not open a gap. Short Dreads: HairTop plus bouncing crown clusters.
  Triangles of every piece are emitted from the innermost loc outward, tubes before frizz.
"""
import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import hairlib as hl  # noqa: E402

TEX_DIR = os.path.join(HERE, "textures")
BLEND_DIR = os.path.join(HERE, "blend")
REF = hl.REF
TEX_KEY = "loc"
TEX_PATH = os.path.join(TEX_DIR, f"hair_{TEX_KEY}.png")
TAU = 2 * math.pi

# ------------------------------------------------------------------------------------------- texture "loc"
# One 1024 x 1024 atlas, greyscale albedo 0.25..1 with straight alpha, three strips side by side (u ranges):
#   loc   0.000-0.375: matted rope. Core 0.03125-0.34375 is opaque and periodic in u across the core (a tube
#                      wraps the core once round its circumference) and in v (tileable along the loc); the 32-px
#                      fringes either side continue the pattern and fray out in alpha (for flat cards that need a
#                      fuzzy silhouette).
#   twist 0.375-0.750: a two-strand twist, the same core / fringe layout. Two helical strands, TWIST_TURNS full
#                      turns over the texture's height, the grooves on u_core - TWIST_TURNS v = 0 (mod 0.5) (the
#                      tube's geometry carries the same grooves, so lobes in the image and in the silhouette line
#                      up).
#   frizz 0.750-1.000: sparse flyaway fibres and small kinks on transparent, periodic in v; clear in the middle
#                      (the frizz ribbon runs through its loc), fuzz just outside the loc's silhouette.
# The builders map v = 0 at the root and v <= 1 at every tip (the strip is tileable in v all the same).
TEX_SIZE = 1024
LOC_STRIP = (0.0, 0.375)
TWIST_STRIP = (0.375, 0.75)
FRIZZ_STRIP = (0.75, 1.0)
FRINGE = 32 / 1024
LOC_CORE = (LOC_STRIP[0] + FRINGE, LOC_STRIP[1] - FRINGE)
TWIST_CORE = (TWIST_STRIP[0] + FRINGE, TWIST_STRIP[1] - FRINGE)
TWIST_TURNS = 4  # full turns of the strand pair per v unit (root to tip of every twist)
LOC_PERIOD = (LOC_CORE[1] - LOC_CORE[0]) / 2  # the loc core holds two identical u-periods
LOC_LUMPS = 4.5  # felted lumps per v unit (root to tip) along each bundle


def _pnoise(h, w, scale, seed, sy=None):
    """periodic (in both axes) band-limited noise, 0..1, feature size ~scale px (sy: along v)"""
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.normal(0, 1, (h, w)))
    fy = np.fft.fftfreq(h)[:, None] * ((sy or scale) / scale)
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-(fx * fx + fy * fy) * (scale * math.pi) ** 2 / 2.0)
    n = np.real(np.fft.ifft2(f * g))
    n = (n - n.mean()) / (n.std() + 1e-9)
    return np.clip(0.5 + 0.18 * n, 0, 1)


def _pblur(a, sigma):
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


class Fibres:
    """additive fibre splatting on a periodic h x w grid: density D and shade-weighted S (bilinear deposits of
    points every ~0.5 px along each fibre, then a small periodic blur gives the fibre its width)"""

    def __init__(self, h, w):
        self.h, self.w = h, w
        self.D = np.zeros((h, w))
        self.S = np.zeros((h, w))

    def add(self, xs, ys, shade, weight):
        """xs, ys: (n,) sample positions (px), shade / weight per sample"""
        h, w = self.h, self.w
        x0 = np.floor(xs).astype(np.int64)
        y0 = np.floor(ys).astype(np.int64)
        fx, fy = xs - x0, ys - y0
        for dx, dy, wt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
            iy, ix = (y0 + dy) % h, (x0 + dx) % w
            np.add.at(self.D, (iy, ix), wt * weight)
            np.add.at(self.S, (iy, ix), wt * weight * shade)

    def strands(self, rng, n, length, angle, ang_sd, wiggle, shade, weight=1.0, mask=None, x_range=None,
                curl=0.0):
        """n fibres, each a gently wavy (and optionally kinky) polyline sampled every 0.5 px"""
        h, w = self.h, self.w
        L = rng.uniform(*length, n)
        a0 = angle(rng, n) if callable(angle) else rng.normal(angle, ang_sd, n)
        x = rng.uniform(*(x_range or (0, w)), n)
        y = rng.uniform(0, h, n)
        sh = rng.uniform(*shade, n)
        ph = rng.uniform(0, math.tau, n)
        fq = rng.uniform(0.5, 1.5, n)
        for i in range(n):
            m = max(4, int(L[i] * 2))
            t = np.linspace(0, 1, m)
            s = t * L[i]
            bend = wiggle * np.sin(ph[i] + t * math.tau * fq[i]) + curl * np.sin(ph[i] * 3 + s * 0.9)
            ca, sa = math.sin(a0[i]), math.cos(a0[i])  # angle from +v (down the image)
            px = x[i] + ca * s + sa * bend
            py = y[i] + sa * s - ca * bend
            wt = np.full(m, weight) * np.clip(np.minimum(t, 1 - t) * 6, 0, 1)  # soft ends
            if mask is not None:
                wt = wt * mask(px % w, py % h, i)
            shd = sh[i] * (0.85 + 0.15 * np.sin(ph[i] + s * 0.2))
            self.add(px, py, shd, wt)

    def coils(self, rng, n, radius, turns, shade, weight=1.0):
        h, w = self.h, self.w
        for i in range(n):
            r = rng.uniform(*radius)
            tr = rng.uniform(*turns)
            m = max(8, int(tr * math.tau * r * 2))
            t = np.linspace(0, 1, m)
            a = rng.uniform(0, math.tau) + t * tr * math.tau
            cx, cy = rng.uniform(0, w), rng.uniform(0, h)
            drift = rng.normal(0, 1, 2) * r * 1.5
            px = cx + r * np.cos(a) * (1 + 0.3 * t) + drift[0] * t
            py = cy + r * np.sin(a) * 0.8 + drift[1] * t
            self.add(px, py, np.full(m, rng.uniform(*shade)), np.full(m, weight))

    def result(self, sigma=0.55, k=1.1):
        D = np.maximum(_pblur(self.D, sigma), 0)
        S = np.maximum(_pblur(self.S, sigma), 0)
        lum = S / np.maximum(D, 1e-6)
        alpha = 1 - np.exp(-k * D)
        return lum, alpha


def _loc_core(h, w, seed):
    """one u-period of the matted rope (w px round, h px root to tip): bundles of fine fibres running mostly
    along the loc (v), each bundle pinched into felted lumps (~LOC_LUMPS per v unit) with short dark creases of
    occlusion between bundles and lumps, crossing fibres that wrap round the loc, small loops and knots, and a
    faint low-frequency variation (amplitude < 0.15). Anisotropic (fibres along v), periodic in u."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    # bundles: 3 per period, their centre lines wandering a little; a lump profile along each
    nb = 3
    bund = np.zeros((h, w))
    best = np.full((h, w), 9.0)
    lump_all = np.zeros((h, w))
    for b in range(nb):
        wan = (_pnoise(h, 1, 30, seed + 100 + b)[:, 0] - 0.5) * w * 0.7
        cx = (b + 0.5 + 0.2 * rng.uniform(-1, 1)) * w / nb + wan
        dx = (xx - cx[:, None] + w / 2) % w - w / 2
        dn = np.abs(dx) / (w / nb / 2)  # 0 at the bundle's centre line .. 1 at its edge
        ph = rng.uniform(0, 1)
        fq = LOC_LUMPS * rng.uniform(0.85, 1.2)
        # felted lumps along the bundle: a rounded bump per lump, irregular spacing
        t = (yy / h * fq + ph + 0.12 * np.sin(yy / h * TAU * 2 + b * 2.1)) % 1.0
        lump = np.sin(math.pi * t) ** 0.6
        sel = dn < best
        best = np.where(sel, dn, best)
        bund = np.where(sel, 1 - np.clip(dn, 0, 1) ** 2.2, bund)
        lump_all = np.where(sel, lump, lump_all)
    # crease darkness: between bundles (broken up so it never runs as a long line) and between lumps
    brk = _pnoise(h, w, 14, seed + 7, sy=40)
    crease_u = (1 - bund) ** 1.5 * np.clip((brk - 0.45) / 0.2, 0, 1)
    shade = 1 - 0.3 * crease_u - 0.3 * (1 - lump_all) * (0.6 + 0.4 * bund)
    low = _pnoise(h, w, 70, seed + 9, sy=160)
    shade = shade * (1 + 0.28 * (low - 0.5))  # +/- ~0.1
    k = h * w / (1024.0 * 160.0)
    # fibres: long fine ones along v (the bulk), crossing / wrapping ones, short loops and knots
    under = Fibres(h, w)
    under.strands(rng, int(5200 * k), (30, 90), 0.0, 0.22, 2.0, (0.35, 0.7), curl=0.8)
    under.strands(rng, int(1400 * k), (10, 30), lambda r, n: r.normal(1.0, 0.35, n) * r.choice([-1, 1], n), 0,
                  1.5, (0.3, 0.6), curl=1.2)
    lu, au = under.result(0.55, 0.9)
    over = Fibres(h, w)
    over.strands(rng, int(2600 * k), (40, 120), 0.0, 0.18, 2.5, (0.7, 1.0), curl=0.6)
    over.strands(rng, int(700 * k), (12, 34), lambda r, n: r.normal(1.15, 0.3, n) * r.choice([-1, 1], n), 0,
                 2.0, (0.6, 0.95), curl=1.0)
    over.coils(rng, int(260 * k), (1.2, 3.0), (0.8, 1.6), (0.6, 0.95))
    # knots: little clusters of loops
    for _ in range(int(40 * k)):
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        for _j in range(rng.integers(4, 9)):
            r = rng.uniform(1.0, 2.8)
            a = rng.uniform(0, TAU) + np.linspace(0, TAU * rng.uniform(0.8, 1.5), 20)
            ox, oy = rng.normal(0, 3.0, 2)
            over.add(cx + ox + r * np.cos(a), cy + oy + r * np.sin(a) * 1.3, np.full(20, rng.uniform(0.6, 0.9)),
                     np.full(20, 1.0))
    lo, ao = over.result(0.5, 1.3)
    felt = 0.18 * (1 - au) + lu * au
    lum = felt * (1 - ao) + lo * ao
    lum = lum * (0.45 + 0.55 * np.clip(shade, 0, 1.1))
    return np.clip(lum, 0, 1)


def _twist_core(h, w, seed):
    """two strands twisted round each other, TWIST_TURNS full turns per v unit: lobes between helical grooves
    (u - TWIST_TURNS v = 0 mod 0.5); the lobes alternate strand A / strand B (each its own fibre direction, a
    counter-twist along its strand, and its own shade), each lobe rounded with a dark groove on both sides"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    wob = (_pnoise(h, w, 14, seed + 5) - 0.5) * 0.05
    uc = (xx + 0.5) / w
    vv = (yy + 0.5) / h

    def qof(u, v, wb=0.0):
        return ((u - TWIST_TURNS * v + wb) % 0.5) / 0.5  # 0 / 1 grooves, 0.5 the middle of a strand

    def strand_of(u, v, wb=0.0):
        return np.floor(((u - TWIST_TURNS * v + wb) % 1.0) / 0.5).astype(np.int64)  # 0: A, 1: B

    q = qof(uc, vv, wob)
    sid = strand_of(uc, vv, wob)
    lobe = np.sin(math.pi * q) ** 0.55
    lumpy = _pnoise(h, w, 9, seed + 1)
    helix = math.atan2(TWIST_TURNS * w, h)  # angle of the grooves from +v
    lums = []
    for s_i, (dang, shd) in enumerate(((math.radians(-22), (0.62, 1.0)), (math.radians(-12), (0.5, 0.88)))):
        def mask(px, py, i, s_i=s_i):
            uu, vq = (px + 0.5) / w, (py + 0.5) / h
            qq = qof(uu, vq)
            return (strand_of(uu, vq) == s_i) * np.clip(np.sin(math.pi * qq) * 2.2 - 0.25, 0, 1)
        under = Fibres(h, w)
        under.strands(rng, 4200, (10, 30), helix + dang, 0.25, 1.0, (shd[0] * 0.6, shd[1] * 0.75), mask=mask,
                      curl=1.0)
        lu, au = under.result(0.6, 1.0)
        over = Fibres(h, w)
        over.strands(rng, 2400, (14, 40), helix + dang, 0.14, 0.9, shd, mask=mask, curl=0.6)
        over.coils(rng, 300, (1.2, 2.6), (0.8, 1.5), (0.6, 0.95))
        lo, ao = over.result(0.5, 1.3)
        lums.append(((0.2 * (1 - au) + lu * au) * (1 - ao) + lo * ao))
    lum = np.where(sid == 0, lums[0], lums[1])
    lum = lum * (0.55 + 0.45 * lobe) * (0.9 + 0.2 * (lumpy - 0.5))
    groove = np.clip(q * (1 - q) * 4 / 0.28, 0, 1) ** 0.8
    lum = lum * (0.3 + 0.7 * groove)
    return np.clip(lum * 1.1, 0, 1)


def _frizz(h, w, seed):
    """the frizz fins' strip: loose fibres and kinks on transparent. The middle (|u - centre| < 0.3 of the half
    width, inside the loc the fin runs through) is clear, the fuzz is densest just outside the loc's silhouette
    (0.45-0.6) and thins out to nothing at both u edges; fibres leave the loc at an angle. Periodic in v."""
    rng = np.random.default_rng(seed)
    f = Fibres(h, w)

    def prof(px, py, i):
        x = np.abs((px + 0.5) / w * 2 - 1)  # 0 middle .. 1 edge
        return smooth(0.28, 0.48, x) * (1 - smooth(0.6, 1.0, x))

    def ang(r, n):
        return r.normal(0, 0.6, n)
    f.strands(rng, 2600, (16, 60), ang, 0, 3.0, (0.55, 1.0), mask=prof, curl=2.2)
    f.strands(rng, 1300, (8, 26), lambda r, n: r.uniform(0, math.tau, n), 0, 2.5, (0.5, 0.9), mask=prof, curl=3.0)
    lum, a = f.result(0.45, 1.0)
    xx = np.abs((np.arange(w) + 0.5) / w * 2 - 1)[None, :]
    a = a * smooth(0.3, 0.45, xx) * (1 - smooth(0.65, 0.99, xx))
    a = np.clip(a * 1.1, 0, 0.92)
    return np.clip(lum, 0, 1), a


def _strip(core, fringe_px, seed):
    """core (periodic in u) + fringes either side continuing the pattern, fraying out in alpha"""
    h, w = core.shape
    W = w + 2 * fringe_px
    idx = (np.arange(W) - fringe_px) % w
    lum = core[:, idx]
    d = np.maximum(fringe_px - np.arange(W), np.arange(W) - (w + fringe_px - 1)).astype(np.float64)
    d = np.clip(d, 0, None)[None, :] / fringe_px  # 0 inside the core .. 1 at the strip edge
    n = _pnoise(h, W, 6, seed)
    n2 = _pnoise(h, W, 2.5, seed + 1)
    a = np.clip(1.0 - (d * 1.25 + (n - 0.5) * 1.1 * d) / 0.9, 0, 1)
    a = a * np.where(d > 0, np.clip(0.55 + 1.6 * (n2 - 0.5) + 0.45 * (1 - d), 0, 1), 1.0)
    a[:, fringe_px:fringe_px + w] = 1.0
    return lum, a


def _stretch(lum, mid):
    """more mid-frequency contrast: the core's 1st..99th percentiles spread over 0.02..0.98 (albedo ~0.27..0.99
    after the 0.25..1 mapping), its median moved to mid, so the dark felted crevices and the bright fibres both
    survive the game's multiply by a dark hair colour"""
    lo, md, hi = np.percentile(lum, [1, 50, 99])
    x = np.clip((lum - lo) / max(1e-6, hi - lo), 0, 1)
    m = (md - lo) / max(1e-6, hi - lo)
    g = math.log(mid) / math.log(max(1e-3, min(0.999, m)))
    return 0.02 + 0.96 * x ** g


def make_loc_texture(path, size=TEX_SIZE, seed=61):
    h = size
    fr = int(round(FRINGE * size))
    cw = int(round((LOC_CORE[1] - LOC_CORE[0]) * size))
    lum = np.zeros((h, size))
    alp = np.zeros((h, size))
    # the loc core: two identical u-periods (LOC_PERIOD wide each) of one rope tile, 1024 px root to tip
    tile = _loc_core(h, cw // 2, seed)
    lc = _stretch(np.hstack([tile, tile]), 0.45)
    l, a = _strip(lc, fr, seed + 10)
    x0 = int(LOC_STRIP[0] * size)
    lum[:, x0:x0 + l.shape[1]], alp[:, x0:x0 + l.shape[1]] = l, a
    tc = _stretch(_twist_core(h, cw, seed + 20), 0.5)
    l, a = _strip(tc, fr, seed + 30)
    x0 = int(TWIST_STRIP[0] * size)
    lum[:, x0:x0 + l.shape[1]], alp[:, x0:x0 + l.shape[1]] = l, a
    fl, fa = _frizz(h, int((FRIZZ_STRIP[1] - FRIZZ_STRIP[0]) * size), seed + 40)
    x0 = int(FRIZZ_STRIP[0] * size)
    lum[:, x0:], alp[:, x0:] = fl, fa
    # albedo 0.25..1; colour bled into (nearly) transparent texels so mips do not halo
    lum = 0.25 + 0.75 * np.clip(lum, 0, 1)
    m = alp > 0.03
    lum = np.where(m, lum, float((lum * alp).sum() / max(1e-6, alp.sum())))
    from PIL import Image
    g = (np.clip(lum, 0, 1) * 255 + 0.5).astype(np.uint8)
    A = (np.clip(alp, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(np.dstack([g, g, g, A]), "RGBA").save(path, optimize=True)
    return path


# ------------------------------------------------------------------------------------------- reference
JOINT_SLEEVE = 0.03  # the ring interval just below a chain joint, emitted into both pieces
ROOT_K = 0.55  # a loc's radius at the scalp / its full radius (the root cone)
CLEAR = 0.026  # target height of every loc surface above the head (nominal studs)
CLEAR_MIN = 0.0215  # enforced after the modifiers (male head mesh; the skull table and the female fit checked)
EAR_CLEAR = 0.024
EAR_BOX_MIN = 0.021  # every vertex at least this far outside the ear boxes (skull.json ears.clearance 0.02)
SK = hl.Skull()
C = SK.c.copy()
SKD = SK.data
DOWN = np.array([0.0, -1.0, 0.0])


def smooth(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def tproj(v, n):
    """v projected on the plane normal to n, unit"""
    return unit(v - n * float(np.dot(v, n)))


def load_obj_mesh(path, obj):
    P, F, cur = [], [], None
    for line in open(path):
        if line.startswith("v "):
            P.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("o "):
            cur = line.split(None, 1)[1].strip()
        elif line.startswith("f ") and cur == obj:
            ids = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
            for k in range(1, len(ids) - 1):
                F.append((ids[0], ids[k], ids[k + 1]))
    return np.asarray(P), F


class Ref:
    """the game's head (with ears and neck) and upper torso as BVH trees"""

    def __init__(self, sex="m"):
        P, F = load_obj_mesh(os.path.join(REF, f"head_{sex}.obj"), "Head")
        self.headP, self.headF = P, F
        # the ears are thin shells whose nearest-face normals give the wrong inside / outside answer just behind
        # them: the collision head leaves them out (the ear boxes keep hair away from them instead)
        sk = None
        if sex == "f" and os.path.exists(os.path.join(REF, "skull_f.json")):
            with open(os.path.join(REF, "skull_f.json")) as f:
                sk = json.load(f)
        ears = [(np.array(e["min"]) - 0.012, np.array(e["max"]) + 0.012)
                for e in ((sk or SKD)["ears"][s] for s in ("left", "right"))]
        keep = []
        for tri in F:
            q = P[list(tri)]
            if any(np.all((q > lo) & (q < hi)) for lo, hi in ears):
                continue
            keep.append(tri)
        self.headF_noear = keep
        self.head = BVHTree.FromPolygons([tuple(p) for p in P], keep)
        Pt, Ft = load_obj_mesh(os.path.join(REF, f"torso_{sex}.obj"), "UpperTorso")
        self.torsoP, self.torsoF = Pt, Ft
        self.torso = BVHTree.FromPolygons([tuple(p) for p in Pt], Ft)

    @staticmethod
    def signed(bvh, p, maxd=2.0):
        """(nearest point, outward direction, signed distance) or None beyond maxd"""
        loc, n, _i, d = bvh.find_nearest(Vector(p), maxd)
        if loc is None:
            return None
        q = np.array(loc)
        nn = np.array(n)
        v = np.asarray(p) - q
        s = float(np.dot(v, nn))
        if d > 1e-6 and s >= 0:
            return q, v / d, d
        return q, nn, -d if s < 0 else d

    def height(self, p):
        r = self.signed(self.head, p)
        return r[2] if r else 9.0


EARS = [(np.array(SKD["ears"][s]["min"]), np.array(SKD["ears"][s]["max"])) for s in ("left", "right")]


SKF = hl.Skull(os.path.join(REF, "skull_f.json")) if os.path.exists(os.path.join(REF, "skull_f.json")) else None
FIT_F = None  # the female fit (main sets it): ax, ay, az, dz


def skull_push(p, off, th_max=2.6):
    """p pushed out radially to at least off above the skull table (the default male skull and, through the
    female fit, the female one): the runtime fits the pieces on the skull field, whose scalp lies up to ~0.017
    outside the head mesh"""
    d = p - C
    r = float(np.linalg.norm(d))
    th, az = SK.angles(d)
    if th > th_max or r < 1e-6:
        return p
    need = SK.radius(th, az) + off
    if SKF is not None and FIT_F is not None:
        q = p * [FIT_F["ax"], FIT_F["ay"], FIT_F["az"]] + [0, 0, FIT_F["dz"]]
        dq = q - SKF.c
        thq, azq = SK.angles(dq)
        if thq <= th_max:
            deficit = SKF.radius(thq, azq) + off - float(np.linalg.norm(dq))
            need = max(need, r + deficit)
    if r < need:
        return C + d / r * need
    return p


def skull_radius_v(sk, th, az):
    """vectorised hl.Skull.radius (bilinear in the table; theta clamped)"""
    T = sk.th
    th = np.clip(th, T[0], T[-1])
    i = np.clip(np.searchsorted(T, th) - 1, 0, len(T) - 2)
    ti = (th - T[i]) / (T[i + 1] - T[i])
    n = len(sk.az)
    a = (az % TAU) / (TAU / n)
    j = np.floor(a).astype(np.int64) % n
    tj = a - np.floor(a)
    j2 = (j + 1) % n
    r = sk.r
    top = r[i, j] * (1 - tj) + r[i, j2] * tj
    bot = r[i + 1, j] * (1 - tj) + r[i + 1, j2] * tj
    return top * (1 - ti) + bot * ti


def skull_push_v(P, off, th_max=2.6):
    """vectorised skull_push over points P (n, 3), offsets off (n,)"""
    d = P - C
    r = np.linalg.norm(d, axis=1)
    th = np.arccos(np.clip(d[:, 1] / np.maximum(r, 1e-9), -1, 1))
    az = np.arctan2(d[:, 0], d[:, 2]) % TAU
    need = skull_radius_v(SK, th, az) + off
    if SKF is not None and FIT_F is not None:
        q = P * [FIT_F["ax"], FIT_F["ay"], FIT_F["az"]] + [0, 0, FIT_F["dz"]]
        dq = q - SKF.c
        rq = np.linalg.norm(dq, axis=1)
        thq = np.arccos(np.clip(dq[:, 1] / np.maximum(rq, 1e-9), -1, 1))
        azq = np.arctan2(dq[:, 0], dq[:, 2]) % TAU
        deficit = skull_radius_v(SKF, thq, azq) + off - rq
        need = np.where(thq <= th_max, np.maximum(need, r + deficit), need)
    m = (th <= th_max) & (r < need) & (r > 1e-6)
    out = P.copy()
    out[m] = C + d[m] / r[m, None] * need[m, None]
    return out


def ear_push(p, grow):
    """p pushed out of both ear boxes grown by grow (through the nearest face, never inward toward the head)"""
    for lo, hi in EARS:
        lo2, hi2 = lo - grow, hi + grow
        if np.all(p > lo2) and np.all(p < hi2):
            side = 1.0 if lo[0] > 0 else -1.0
            cands = [(hi2[1] - p[1], 1, hi2[1]), (hi2[2] - p[2], 2, hi2[2]), (p[2] - lo2[2], 2, lo2[2])]
            # outward in x (away from the head)
            if side > 0:
                cands.append((hi2[0] - p[0], 0, hi2[0]))
            else:
                cands.append((p[0] - lo2[0], 0, lo2[0]))
            # near the top of the box: over the ear (up), not out beside it
            if hi2[1] - p[1] < 0.07:
                cands[0] = (cands[0][0] * 0.4, cands[0][1], cands[0][2])
            d, ax, val = min(cands)
            p = p.copy()
            p[ax] = val
    return p


# ------------------------------------------------------------------------------------------- hairline
def _hairline_points(kind="Natural"):
    ln = SKD["hairline"]["lines"][kind]
    pts = []
    for side in ("right", "left"):
        for e in ln[side]:
            if e and e is not False and len(e) >= 4:
                pts.append(e[1:4])
    hgt = np.array([e for e in ln["height"] if e], dtype=np.float64)
    return np.array(pts, dtype=np.float64), hgt


HL_PTS, HL_H = _hairline_points()


def da_of(p):
    p = np.atleast_2d(p)
    return np.arctan2(np.abs(p[:, 0]), 0.05 - p[:, 2])


def hairline_y(p):
    return np.interp(da_of(p), HL_H[:, 0], HL_H[:, 1])


def edge_dist(p):
    """signed distance (studs) from the scalp point under p to the natural hairline: + inside the hair"""
    p = np.atleast_2d(np.asarray(p, dtype=np.float64))
    d = unit(p - C)
    r = np.array([SK.radius(*SK.angles(di)) for di in d])
    s = C + d * r[:, None]
    dd = np.sqrt(((s[:, None, :] - HL_PTS[None, :, :]) ** 2).sum(-1)).min(1)
    inside = s[:, 1] - np.interp(da_of(s), HL_H[:, 0], HL_H[:, 1])
    return np.where(inside >= 0, dd, -dd)


# ------------------------------------------------------------------------------------------- roots
def hairline_row(spacing, margin, rng, jitter=0.15):
    """the first row of sections along the natural hairline (forehead, temples, sideburns, over the ears, nape):
    roots every `spacing` along the line, margin inside it"""
    ln = SKD["hairline"]["lines"]["Natural"]
    R = [e[1:4] for e in ln["right"] if e and len(e) >= 4]
    Lf = [e[1:4] for e in ln["left"] if e and len(e) >= 4]
    P = np.array(R[::-1] + Lf[1:], dtype=np.float64)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    sarc = np.concatenate([[0], np.cumsum(seg)])
    n = int(round(sarc[-1] / spacing))
    out = []
    crown = np.array([0.0, 0.62, 0.05])
    for k in range(n):
        t = (k + 0.5 + rng.uniform(-jitter, jitter)) * sarc[-1] / n
        p = np.array([np.interp(t, sarc, P[:, j]) for j in range(3)])
        sp, th, az = SK.project(p)
        nn = SK.normal(th, az)
        inward = tproj(crown - sp, nn)
        q = sp + inward * (margin + rng.uniform(-0.003, 0.015))
        q, th, az = SK.project(q)
        e = float(edge_dist(q)[0])
        if e < margin * 0.6:
            continue
        out.append(dict(th=th, az=az, p=q, n=SK.normal(th, az), e=e, rnd=rng.random(), rnd2=rng.random(),
                        rnd3=rng.random(), edge=True))
    return out


def _rot_from_y(pole):
    """rotation matrix taking +Y to the unit vector pole (Rodrigues)"""
    a = np.array([0.0, 1.0, 0.0])
    b = unit(pole)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx / (1 + c)


def box_roots(spacing, margin, seed, jitter=0.2, region=None, edge_spacing=None, pole=None, whorl_ring=0,
              grade=0.0, edge_gap=0.75):
    """box-parted sections: a row along the hairline, then brick-laid rings round a pole (the vertex, or the crown
    whorl for Short Dreads), each cell's centre (jittered) a root. whorl_ring: the first ring's root count (a
    tight ring of small locs round the pole, so the whorl is not a bald spot). grade: the sections are
    (1 - grade) x spacing near the pole, growing to (1 + grade) x spacing down the sides"""
    rng = np.random.default_rng(seed)
    edge = hairline_row(edge_spacing or spacing * 0.85, margin, rng, jitter=0.3) if edge_spacing != 0 else []
    if region is not None:
        edge = [r for r in edge if region(r["p"], r["e"])]
    Rm = _rot_from_y(pole) if pole is not None else np.eye(3)
    r0 = 0.47
    dth = spacing / r0
    out = []

    def add(t, a, **kw):
        d = Rm @ hl.Skull.direction(t, a)
        th, az = SK.angles(d)
        p = SK.point(th, az)
        e = float(edge_dist(p)[0])
        if e < margin + (spacing * edge_gap if edge else 0.0):
            return
        if region is not None and not region(p, e):
            return
        out.append(dict(th=th, az=az, p=p, n=SK.normal(th, az), e=e, rnd=rng.random(), rnd2=rng.random(),
                        rnd3=rng.random(), pole_t=t, **kw))
    add(0.02, 0.0, whorl=True)
    i = 0
    rot = rng.uniform(0, TAU)
    if whorl_ring:
        tw = dth * 0.5
        for j in range(whorl_ring):
            add(tw * rng.uniform(0.9, 1.1), (rot + (j + rng.uniform(-0.15, 0.15)) * TAU / whorl_ring) % TAU,
                whorl=True)
        i = 1
    def sp_at(t):
        return spacing * (1 - grade + 2 * grade * float(smooth(0.2, 1.3, t)))
    th = dth * 0.9 if not whorl_ring else dth * 0.5 + sp_at(0.0) / r0
    while True:
        if i > (1 if whorl_ring else 0):
            th += sp_at(th) / r0
        sp_t = sp_at(th)
        if th > 2.5:
            break
        n = max(4, int(round(TAU * r0 * math.sin(th) / sp_t)))
        rot += TAU / n * rng.uniform(0.35, 0.65)
        for j in range(n):
            a = (rot + (j + rng.uniform(-jitter, jitter)) * TAU / n) % TAU
            t = th + rng.uniform(-jitter, jitter) * sp_t / r0 * 0.8
            add(t, a)
        i += 1
    return edge + out


def sideburn_roots(seed, ys, inset=0.5):
    """roots down each sideburn (the strip of the natural hairline in front of the ear, between its front and
    back edges), `inset` of the way from the front edge to the back edge, at the heights ys"""
    rng = np.random.default_rng(seed)
    ln = SKD["hairline"]["lines"]["Natural"]
    out = []
    for side in ("right", "left"):
        E = np.array([e[:4] for e in ln[side] if e and len(e) >= 4], dtype=np.float64)
        fr = E[(E[:, 0] >= 1.18) & (E[:, 0] <= 1.30)]  # front edge, y falling
        bk = E[(E[:, 0] >= 1.30) & (E[:, 0] <= 1.80)]  # back edge, y rising, then over the ear
        for y in ys:
            zf = float(np.interp(-y, -fr[:, 2], fr[:, 3]))
            xf = float(np.interp(-y, -fr[:, 2], fr[:, 1]))
            if y <= bk[:, 2].max():
                k = int(np.argmax(bk[:, 2] >= y))
                zb = float(bk[k, 3])
            else:
                zb = zf + 0.07
            z = zf + (zb - zf) * min(inset, 0.06 / max(1e-3, zb - zf))
            q = np.array([xf, y, z])
            sp, th, az = SK.project(q)
            out.append(dict(th=th, az=az, p=sp, n=SK.normal(th, az), e=float(edge_dist(sp)[0]), rnd=rng.random(),
                            rnd2=rng.random(), rnd3=rng.random(), edge=True, sideburn=True))
    return out


# ------------------------------------------------------------------------------------------- guides
def in_ear_zone(p, rad):
    """beside or just above an ear, in front of its back edge: hanging hair must not drop here"""
    return abs(p[0]) > 0.18 and p[1] < 0.17 and p[2] < 0.25 + rad and p[1] > -0.4


def scalp_walk(root, heading, step, offs, n_max, y_tip, lift, drop=True, rad=0.04):
    """a guide laid on the scalp from root (root dict) along heading(p, n) at height offs(s) above the skull
    table, dropping off the head where the scalp turns in under its widest point (never beside an ear), then
    falling straight down to y_tip. Returns (points, scalp length)."""
    n0 = root["n"]
    p0 = SK.point(root["th"], root["az"], offs(0.0))
    pts = [p0]
    h0 = heading(p0, n0)
    d = unit(n0 * lift + h0 * (1 - lift))
    p = p0 + d * step
    pts.append(p)
    s = step
    scalp_len = None
    while len(pts) < n_max:
        if scalp_len is None:
            sp, th, az = SK.project(p)
            n = SK.normal(th, az)
            h = heading(sp, n)
            # the hair leaves the head where the scalp turns to face downward (past its widest point), only
            # behind the ears (never on the front half, never beside an ear)
            if drop and n[1] < -0.1 and sp[2] > 0.2 and not in_ear_zone(sp, rad):
                scalp_len = s
                continue
            q = p + h * step
            th2, az2 = SK.angles(q - C)
            q = SK.point(th2, az2, offs(s + step))
            # keep the step length
            q = p + unit(q - p) * step
            pts.append(q)
            p = q
            s += step
            if q[1] < y_tip:
                scalp_len = s
                break
        else:
            out = unit(np.array([p[0], 0.0, p[2] - C[2]]))
            q = p + unit(DOWN + out * 0.08) * step
            pts.append(q)
            p = q
            s += step
            if q[1] < y_tip:
                break
    return np.array(pts), (scalp_len if scalp_len is not None else s)


def resample(P, M):
    """polyline -> M points evenly spaced by arc length"""
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    t = np.linspace(0, s[-1], M)
    return np.stack([np.interp(t, s, P[:, k]) for k in range(3)], 1), s[-1]


class Sim:
    """position-based dynamics on N chains of M points (vectorised; the collisions use Blender's BVH trees)"""

    def __init__(self, ref, X, seg, rad, off, rest=None, wshape=None, pin=2, gravity=0.0016, damp=0.9,
                 bend=0.985, guard=None, repel=0.9, body=True, body_off=0.03):
        self.ref = ref
        self.X = X.copy()
        self.X0 = X.copy()
        self.Xp = X.copy()
        self.seg = seg
        self.rad = rad  # (N, M) loc radius at each point
        self.off = off  # (N, M) collision offset above the head
        self.rest = rest if rest is not None else X.copy()
        self.wshape = wshape if wshape is not None else np.zeros(X.shape[:2])
        self.pin = pin
        self.g = gravity
        self.damp = damp
        self.bend = bend
        self.guard = guard
        self.repel_k = repel
        self.body = body
        self.body_off = body_off  # clearance of the loc's surface from the torso (AnatomyHair's bodyOff)
        N, M, _ = X.shape
        cid = np.repeat(np.arange(N), M)
        pid = np.tile(np.arange(M), N)
        self._cid, self._pid = cid, pid

    def _pin(self):
        self.X[:, :self.pin] = self.X0[:, :self.pin]

    def constraints(self, k=4):
        X = self.X
        for _ in range(k):
            d = X[:, 1:] - X[:, :-1]
            ln = np.linalg.norm(d, axis=2, keepdims=True)
            corr = (1 - self.seg[:, None, None] / np.maximum(ln, 1e-9)) * d * 0.5
            X[:, :-1] += corr
            X[:, 1:] -= corr
            self._pin()
            d2 = X[:, 2:] - X[:, :-2]
            l2 = np.linalg.norm(d2, axis=2, keepdims=True)
            bend = self.bend if np.isscalar(self.bend) else self.bend[:, :-2, None]
            want = 2 * self.seg[:, None, None] * bend
            c = np.minimum(0, l2 - want) / np.maximum(l2, 1e-9) * d2 * 0.25
            X[:, :-2] += c
            X[:, 2:] -= c
            self._pin()

    def collide(self):
        X = self.X
        N, M, _ = X.shape
        head, torso = self.ref.head, self.ref.torso
        X[:, self.pin:] = skull_push_v(X[:, self.pin:].reshape(-1, 3),
                                       self.off[:, self.pin:].reshape(-1)).reshape(N, M - self.pin, 3)
        lo_all = np.min([lo for lo, _hi in EARS], axis=0) - 0.12
        hi_all = np.max([hi for _lo, hi in EARS], axis=0) + 0.12
        for i in range(N):
            for j in range(self.pin, M):
                p = X[i, j]
                off = self.off[i, j]
                r = Ref.signed(head, p, off + 0.05)
                if r is not None and r[2] < off:
                    p = r[0] + r[1] * off
                if self.body and p[1] < -0.3:
                    ob = self.rad[i, j] + self.body_off
                    r = Ref.signed(torso, p, ob + 0.05)
                    if r is not None and r[2] < ob:
                        p = r[0] + r[1] * ob
                if lo_all[1] < p[1] < hi_all[1] and lo_all[2] < p[2] < hi_all[2]:
                    p = ear_push(p, EAR_CLEAR + self.rad[i, j])
                if self.guard is not None:
                    p = self.guard(p, self.rad[i, j])
                X[i, j] = p

    def repel(self):
        X = self.X
        N, M, _ = X.shape
        P = X.reshape(-1, 3)
        # (roots squeeze: a loc lying over another's root presses it flat instead of riding high over it)
        R = (self.rad * np.where(np.arange(M) < 3, 0.5, 1.0)[None, :]).reshape(-1)
        D = P[:, None, :] - P[None, :, :]
        L = np.sqrt((D * D).sum(-1))
        want = (R[:, None] + R[None, :]) * self.repel_k
        same = (self._cid[:, None] == self._cid[None, :]) & (np.abs(self._pid[:, None] - self._pid[None, :]) <= 2)
        pinned = self._pid < self.pin
        m = (L < want) & ~same & (L > 1e-9)
        if not m.any():
            return
        f = np.where(m, (want - L) / np.maximum(L, 1e-9) * 0.25, 0.0)
        mv = (D * f[..., None]).sum(1)
        mv[pinned] = 0
        X += mv.reshape(N, M, 3)

    def run(self, iters, repel_every=2, log=None):
        for it in range(iters):
            V = (self.X - self.Xp) * self.damp
            self.Xp = self.X.copy()
            self.X += V
            self.X[:, :, 1] -= self.g
            self._pin()
            self.constraints()
            self.X += self.wshape[..., None] * (self.rest - self.X)
            if repel_every and it % repel_every == 0:
                self.repel()
            self.collide()
        # settle: constraints and collisions without inertia
        for _ in range(6):
            self.constraints(2)
            self.collide()
        return self.X


def smooth_chain(X, pin=2, passes=2, k=0.35):
    X = X.copy()
    for _ in range(passes):
        Y = X.copy()
        Y[:, 1:-1] = X[:, 1:-1] * (1 - k) + (X[:, :-2] + X[:, 2:]) * (k / 2)
        Y[:, :pin] = X[:, :pin]
        X = Y
    return X


# ------------------------------------------------------------------------------------------- tubes
def densify(P, sub=8):
    """Catmull-Rom through P, sub points per segment -> (dense points, arc length at each)"""
    P = np.asarray(P)
    ext = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for t in np.linspace(0, 1, sub, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-1])
    D = np.array(out)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(D, axis=0), axis=1))])
    return D, s


def at_s(D, S, s):
    return np.stack([np.interp(s, S, D[:, k]) for k in range(3)], -1)


def ring_positions(D, S, base, fine_ends, forced=(), min_ds=0.016, bend_k=0.3):
    """arc lengths of a tube's rings: base spacing, finer on bends and at the root / tip"""
    L = S[-1]
    # turning per stud along the dense curve
    T = unit(np.gradient(D, axis=0))
    ang = np.arccos(np.clip((T[1:] * T[:-1]).sum(1), -1, 1))
    ds = np.maximum(np.diff(S), 1e-6)
    kap = np.concatenate([[0], ang / ds])
    kap = np.convolve(kap, np.ones(9) / 9, mode="same")
    out = [0.0]
    s = 0.0
    while True:
        k = float(np.interp(s, S, kap))
        b = base(s) if callable(base) else base
        h = min(b, max(min_ds, bend_k / max(k, 1e-6)))
        if s < fine_ends[0] or s > L - fine_ends[1]:
            h = min(h, fine_ends[2])
        s += h
        if s >= L - 0.008:
            break
        out.append(s)
    out.append(L)
    # forced rings (chain cuts and their sleeves) are inserted; rings too close to one are dropped
    fs = [f for f in forced if 0.01 < f < L - 0.01]
    out = [x for x in out if all(abs(x - f) > 0.012 for f in fs) or x in (0.0, L)] + fs
    return np.array(sorted(set(round(x, 6) for x in out)))


class MeshBuild:
    """a Blender-ready mesh with welded positions and per-corner UVs: game vertices are (welded vertex, uv)
    pairs, faces carry a tag (loc index, segment) and the loc's sort key"""

    def __init__(self):
        self.W = []  # welded positions
        self.wmeta = []  # (loc, s) per welded vertex
        self.G = []  # game vertices: (wid, u, v)
        self.F = []  # faces: tuple of game vertex ids (3 or 4)
        self.Ftag = []  # (loc, seg)
        self.Fdup = []  # True: the reversed twin of a two-sided card face (left out of the Blender object)
        self.Fsleeve = []  # True: a joint sleeve (a copy of a ring interval, left out of the Blender object)
        self.Wn = []  # optional shading-normal hints per welded vertex

    def wv(self, p, loc, s, n=None):
        self.W.append(np.asarray(p, dtype=np.float64))
        self.wmeta.append((loc, s))
        self.Wn.append(n)
        return len(self.W) - 1

    def gv(self, wid, u, v):
        self.G.append((wid, float(u), float(v)))
        return len(self.G) - 1

    def face(self, ids, tag, dup=False, sleeve=False):
        self.F.append(tuple(ids))
        self.Ftag.append(tag)
        self.Fdup.append(dup or sleeve)
        self.Fsleeve.append(sleeve)


def frames(D, S, s_list, inward):
    """parallel-transport frames at the ring arc lengths; the first normal points toward `inward`"""
    T = unit(np.gradient(D, axis=0))
    tans = unit(np.stack([np.interp(s_list, S, T[:, k]) for k in range(3)], -1))
    nrm = inward - tans[0] * float(np.dot(inward, tans[0]))
    if np.linalg.norm(nrm) < 1e-6:
        nrm = np.cross(tans[0], [1, 0, 0])
    nrm = unit(nrm)
    out = []
    prev = tans[0]
    for t in tans:
        ax = np.cross(prev, t)
        sn = float(np.linalg.norm(ax))
        if sn > 1e-9:
            ax = ax / sn
            a = math.atan2(sn, float(np.dot(prev, t)))
            nrm = nrm * math.cos(a) + np.cross(ax, nrm) * math.sin(a) + ax * np.dot(ax, nrm) * (1 - math.cos(a))
        nrm = unit(nrm - t * float(np.dot(nrm, t)))
        out.append((t, nrm, unit(np.cross(t, nrm))))
        prev = t
    return out


def loc_radius(s, L, R, rnd, root_len=0.08, tip_r=0.6, lump=0.1, root_k=None, tip_len=None):
    """a loc's radius along its length: a thin root cone growing out of the scalp, lumpy, tapering to tip_r x R
    over the last tip_len (the tube builder then rounds the end with a dome)"""
    s = np.asarray(s, dtype=np.float64)
    ph1, ph2 = rnd * 17.0, rnd * 31.0
    rk = ROOT_K if root_k is None else root_k
    r = R * (rk + (1 - rk) * smooth(0.0, root_len, s) ** 0.8)
    r = r * (1 + lump * (0.6 * np.sin(s * 23 + ph1) + 0.4 * np.sin(s * 57 + ph2)))
    tl = min(0.12, L * 0.3) if tip_len is None else tip_len
    r = r * (1 - (1 - tip_r) * smooth(L - tl, L, s))
    return r


def build_tube(mb, loc_i, D, S, s_rings, radius, sides, strip, vps, v0, inward, lobes=None, ellipse=0.9,
               seg_of=None, tip_k=0.8, dome=1, root_k_apex=0.7):
    """one loc tube into MeshBuild mb, closed at both ends: a short cone into the scalp at the root (its apex just
    under the root ring) and a rounded dome (`dome` rings shrinking on a quarter circle, then an apex) at the tip.
    radius(s) -> r; lobes: None (round, a slightly elliptical section turning slowly, a little irregular ring to
    ring) or 'twist' (two strands: two lobes whose phase turns with v, TWIST_TURNS turns root to tip, lined up
    with the twist strip's grooves). u wraps once round the tube over `strip`; v = v0 + s / vps.
    Where the segment (piece) changes between two rings, that ring interval is emitted into both pieces (the upper
    piece's copy is a sleeve over the joint, so a swinging lower piece never opens a gap). Faces wind counter-
    clockwise seen from outside."""
    u0, u1 = strip
    fr = frames(D, S, s_rings, inward)
    C_ = at_s(D, S, s_rings)
    psi0 = loc_i * 1.7

    def ring(i, centre, t, nrm, bn, r, v, s, irregular):
        wids = []
        for k in range(sides):
            a = TAU * k / sides
            if lobes == "twist":
                ph = TAU * TWIST_TURNS * v
                rr = r * (0.76 + 0.34 * abs(math.sin(a - ph)) ** 0.7)
            else:
                psi = psi0 + s * 2.5
                rr = r / math.sqrt(math.cos(a - psi) ** 2 + (math.sin(a - psi) / ellipse) ** 2)
                if irregular:
                    hsh = math.sin(i * 12.9898 + k * 78.233 + loc_i * 3.71) * 43758.5453
                    rr *= 1 + 0.06 * ((hsh - math.floor(hsh)) - 0.5)
            p = centre + (nrm * math.cos(a) + bn * math.sin(a)) * rr
            wids.append(mb.wv(p, loc_i, s))
        return [mb.gv(wids[k % sides], u0 + (u1 - u0) * k / sides, v) for k in range(sides + 1)]
    rings, ring_s = [], []
    nR0 = len(s_rings)
    for i, s in enumerate(s_rings):
        t, nrm, bn = fr[i]
        rings.append(ring(i, C_[i], t, nrm, bn, float(radius(s)), v0 + s / vps, s, 0 < i < nR0 - 1))
        ring_s.append(s)
    # the dome
    tl, nl, bl = fr[-1]
    rl = float(radius(s_rings[-1]))
    L = s_rings[-1]
    for j in range(1, dome + 1):
        phi = j / (dome + 1) * math.pi / 2
        ds = rl * tip_k * math.sin(phi)
        rings.append(ring(nR0 + j, C_[-1] + tl * ds, tl, nl, bl, rl * math.cos(phi), v0 + (L + ds) / vps, L, False))
        ring_s.append(L)
    nR = len(rings)
    segs = [seg_of(0.5 * (ring_s[i] + ring_s[i + 1])) if seg_of else 0 for i in range(nR - 1)]
    for i in range(nR - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(sides):
            mb.face((r0[k], r0[k + 1], r1[k + 1], r1[k]), (loc_i, segs[i]))
        if i > 0 and segs[i] > segs[i - 1]:
            for k in range(sides):  # the sleeve over the joint, in the upper piece
                mb.face((r0[k], r0[k + 1], r1[k + 1], r1[k]), (loc_i, segs[i - 1]), sleeve=True)
    # root: a short cone into the scalp (no open ring anywhere)
    t0 = fr[0][0]
    r0_ = float(radius(s_rings[0]))
    # the apex points into the scalp (between back along the loc and toward the head's centre): the closed
    # root faces the scalp, it does not end in a point seen end-on
    into = unit(unit(C - C_[0]) * 0.7 - t0 * 0.3)
    wc = mb.wv(C_[0] + into * r0_ * root_k_apex, loc_i, 0.0)
    gc = mb.gv(wc, (u0 + u1) / 2, v0)
    for k in range(sides):
        mb.face((gc, rings[0][k + 1], rings[0][k]), (loc_i, segs[0] if segs else 0))
    # tip apex
    wt = mb.wv(C_[-1] + tl * rl * tip_k, loc_i, L)
    gt = mb.gv(wt, (u0 + u1) / 2, min(0.999, v0 + (L + rl * tip_k) / vps))
    for k in range(sides):
        mb.face((rings[-1][k], rings[-1][k + 1], gt), (loc_i, segs[-1] if segs else 0))
    return rings


def build_halo(mb, loc_i, D, S, radius, L, vps_frizz, inward, seg_of=None, root_k=1.9, k=1.5, step=0.05,
               s_start=0.006, rnd=0.0, fins=2):
    """the frizz round one loc: two crossed fins through its axis (two-sided cards of the frizz strip, k x the loc's
    diameter wide, a little wider round the root), so wherever the loc is seen from, fibres stand off its
    silhouette. The fins' shading normals point out from the loc's axis (they shade like its surface)."""
    u0, u1 = FRIZZ_STRIP[0] + 0.002, FRIZZ_STRIP[1] - 0.002
    s_end = L - min(0.012, L * 0.1)
    n = max(2, int(math.ceil((s_end - s_start) / step)) + 1)
    s_rings = np.linspace(s_start, s_end, n)
    fr = frames(D, S, s_rings, inward)
    C_ = at_s(D, S, s_rings)
    for fin in range(fins):
        rows = []
        for i, s in enumerate(s_rings):
            t, nrm, bn = fr[i]
            r = float(radius(s))
            hw = r * (k + (root_k - k) * (1 - smooth(0.0, 0.1, s)))
            # two crossed fins; a single fin twists round the loc (a turn every ~0.8) so it frays the silhouette
            # from every side along the length
            a = fin * math.pi / 2 + math.pi / 4 + rnd * 3.0 + s * (2.5 if fins > 1 else 4.0)
            side = nrm * math.cos(a) + bn * math.sin(a)
            v = s / vps_frizz
            wa = mb.wv(C_[i] - side * hw, loc_i, s, -side)
            wb = mb.wv(C_[i] + side * hw, loc_i, s, side)
            rows.append((wa, wb, v))
        for i in range(len(rows) - 1):
            (a0, b0, v0), (a1, b1, v1) = rows[i], rows[i + 1]
            seg = seg_of(0.5 * (s_rings[i] + s_rings[i + 1])) if seg_of else 0
            ga, gb = mb.gv(a0, u0, v0), mb.gv(b0, u1, v0)
            gc, gd = mb.gv(b1, u1, v1), mb.gv(a1, u0, v1)
            mb.face((ga, gb, gc, gd), (loc_i, seg))
            mb.face((ga, gd, gc, gb), (loc_i, seg), dup=True)


# ------------------------------------------------------------------------------------------- styles
def heading_hanging(back_front=1.7, side=0.1):
    """flow of hanging locs on the scalp: the front swept up and back over the top (toward a point behind the
    crown), the rest down and a little back, sideburns up and back over the ears, the sides behind the ears"""
    target = np.array([0.0, 0.66, 0.38])

    def f(p, n):
        z = p[2]
        wf = float(smooth(0.05, -0.32, z)) * float(smooth(0.05, 0.25, p[1]))
        out = np.array([p[0], 0.0, 0.0])
        down = DOWN + np.array([0, 0, 1.0]) * (0.25 + 0.5 * float(smooth(0.3, -0.1, z))) \
            + unit(out) * side * float(smooth(0.15, 0.35, abs(p[0])))
        # off the face: straight back over the top, fanning out a little with |x| (parallel rows that do not
        # converge on one point, which left a wedge of bare scalp behind the crown)
        back = unit(np.array([0.15 * p[0], 0.25 * float(smooth(0.3, -0.2, z)), 1.0]))
        v = unit(down) * (1 - wf) + back * wf * back_front
        if abs(p[0]) > 0.2 and p[1] < 0.2 and p[2] < 0.06:
            v = np.array([0.0, 0.55, 1.0])  # sideburns and temples: up and back over the ear
        elif in_ear_zone(p, 0.04) or (abs(p[0]) > 0.2 and p[1] < 0.24 and p[2] < 0.26):
            v = np.array([0.0, 0.12, 1.0])  # back above the ear (never across it), dropping behind it
        return tproj(v, n)
    return f


def guard_hanging(p, rad):
    """keep hanging hair off the forehead and the face"""
    if p[2] < -0.05 and abs(p[0]) < 0.42 and -0.6 < p[1] < 0.2 and abs(p[0]) < 0.3 + 0.2 * (p[2] + 0.05):
        p = p.copy()  # in front of the face: out to the side
        p[0] = math.copysign(0.3 + 0.2 * (p[2] + 0.05), p[0])
    if p[2] < -0.18 and p[1] < float(hairline_y(p)[0]) + 0.012 and p[1] > -0.2:
        p = p.copy()
        p[1] = float(hairline_y(p)[0]) + 0.012
    return p


def guard_short(p, rad):
    """short locs: nothing over the face below the hairline (the hairline's height in the direction of p, on the
    front half of the head), no further off the scalp than the silhouette allows (about 1.25 x the head's width)"""
    if p[2] < 0.05:
        hy = float(hairline_y(p)[0]) + 0.004 + rad * 0.8
        if p[1] < hy and p[1] > -0.3:
            p = p.copy()
            p[1] = hy
    h = SK.height(p)
    hmax = 0.07 + 0.08 * float(smooth(0.25, 0.5, p[1]))
    if h > hmax:
        d = p - C
        p = C + d * (1 - (h - hmax) / float(np.linalg.norm(d)))
    if abs(p[0]) > 0.45:
        p = p.copy()
        p[0] = math.copysign(0.45, p[0])
    return p


STYLES = {
    "dreadlocks": dict(
        entry=dict(styles=["Dreadlocks"], types=None, cap={"cut": "full", "density": 0.45}, capTile="shortcoil"),
        kind="hang", spacing=0.16, fill=12, fill2=10, min_gap=0.014, margin=0.03, seed=101, R=0.036, rvar=0.2, M=32,
        step=0.03, hang_len=1.05, side_short=0.25, L_max=2.25, sides=6, base_ds=0.42, base_scalp=0.25, min_ds=0.09, end_ds=0.06,
        bend_k=1.0, root_k=0.5, edge_root_k=0.3, lift=0.2, crown_lift=0.045, rot_deg=20,
        layer=0.024, repel=0.72, fins=1, chains=7, segs=2, stiff=0.35, mass=(1.5, 1.15), hang_split=0.5,
        edge_root=(0.55, 0.05, 0.25),
        prefix="HairLoc", chain="Loc", lobes=None, halo=dict(k=1.9, root_k=2.6, step=0.34), lump=0.12,
        tip_r=(0.55, 0.9), tip_k=0.9, dome=1, back_front=1.8, splay=0.24, wave=(0.012, 0.35), body_off=0.07,
        short_top=0.14, sideburn_ys=(0.17,),
        cov_dirs=("top", "back", "back34r", "back34l", "topback", "lowback")),
    "twists": dict(
        entry=dict(styles=["Twists"], types=None, cap={"cut": "full", "density": 0.45}, capTile="shortcoil"),
        kind="hang", spacing=0.19, fill=8, fill2=10, min_gap=0.014, margin=0.03, seed=303, R=0.044, rvar=0.14, M=24,
        step=0.025, root_k=0.5, edge_root_k=0.3, crown_lift=0.03, rot_deg=15,
        repel=0.72, fins=1, L_max=1.3, hang_len=0.4, side_short=0.2, sides=6, base_ds=0.064, min_ds=0.055,
        end_ds=0.05, bend_k=0.4, lift=0.3,
        layer=0.02, chains=8, segs=1, stiff=0.4, mass=(1.3,), hang_split=None, prefix="HairTwist", chain="Twist",
        lobes="twist", halo=dict(k=1.8, root_k=2.4, step=0.24), lump=0.04, tip_r=0.42, tip_k=1.0, dome=1,
        back_front=1.8, splay=0.14, wave=(0.008, 0.4), body_off=0.07, short_top=0.1, sideburn_ys=(0.15, 0.08),
        cov_dirs=("top", "back", "back34r", "back34l", "topback", "lowback")),
    "short_dreads": dict(
        entry=dict(styles=["Short Dreads"], types=None, cap={"cut": "full", "density": 0.5}, capTile="shortcoil"),
        kind="short", spacing=0.118, fill=45, fill2=25, min_gap=0.013, margin=0.026, seed=202, R=0.028, rvar=0.25, M=14,
        edge_gap=0.25, edge_spacing=0.075,
        sides=7, base_ds=0.16, min_ds=0.06, end_ds=0.1, bend_k=0.7, clusters=6, stiff=0.75, mass=1.3, lobes=None,
        halo=dict(k=1.6, root_k=2.2, step=0.2), lump=0.07, tip_r=0.62, tip_k=0.55, dome=0, fins=1,
        sideburn_ys=(0.17, 0.11, 0.05, -0.01),
        cov_dirs=("top", "back", "back34r", "back34l", "lowback", "sider", "sidel", "front34", "front34l", "front",
                  "fronttop")),
}


_SCALP_GRID = None


def scalp_grid(step=0.028, e_min=0.035):
    """points (and normals) every ~step over the scalp inside the natural hairline (e_min inside it)"""
    global _SCALP_GRID
    if _SCALP_GRID is None:
        P, Nn = [], []
        for th in np.arange(0.0, 2.3, step / 0.47):
            n_az = max(1, int(round(TAU * 0.47 * math.sin(th) / step)))
            for j in range(n_az):
                az = (j + 0.5 * (int(th / (step / 0.47)) % 2)) * TAU / n_az
                P.append(SK.point(th, az))
                Nn.append(SK.normal(th, az))
        P, Nn = np.array(P), np.array(Nn)
        e = edge_dist(P)
        _SCALP_GRID = (P, Nn, e)
    P, Nn, e = _SCALP_GRID
    m = e > e_min
    return P[m], Nn[m]


VIEW_DIRS = {
    # directions from the scalp toward the camera (unit after normalising): the coverage pass checks all of them
    "top": (0.0, 1.0, 0.0), "back": (0.0, 0.1, 1.0), "back34r": (0.6, 0.3, 0.75), "back34l": (-0.6, 0.3, 0.75),
    "lowback": (0.0, -0.3, 1.0), "sider": (1.0, 0.15, 0.1), "sidel": (-1.0, 0.15, 0.1),
    "topback": (0.0, 0.75, 0.66), "front34": (0.5, 0.45, -0.75), "front34l": (-0.5, 0.45, -0.75),
    "front": (0.15, 0.12, -1.0), "fronttop": (0.0, 0.65, -0.76),
}


class Coverage:
    """per scalp point and view direction: the gap between the line from the point toward the camera and the
    nearest loc surface (0 = some loc covers the point from that side). Directions: the point's own normal and
    VIEW_DIRS (only where the scalp faces the camera). Incremental: adding a loc only lowers gaps."""

    def __init__(self, P, Nn, dirs, k=0.95):
        self.P, self.Nn, self.k = P, Nn, k
        D = [None] + [unit(np.array(VIEW_DIRS[d], dtype=np.float64)) for d in dirs]
        self.dirs = D
        self.vis = np.stack([np.ones(len(P), bool) if d is None else (Nn @ d) > 0.25 for d in D])
        self.best = np.full((len(D), len(P)), 9.0)

    def add(self, lc):
        G, _S = densify(lc["G"] if "G" in lc else lc["P"], 3)
        R = lc["R"]
        for di, d in enumerate(self.dirs):
            for i0 in range(0, len(self.P), 512):
                q = self.P[i0:i0 + 512, None, :]
                n = self.Nn[i0:i0 + 512, None, :] if d is None else d[None, None, :]
                v = G[None, :, :] - q
                along = (v * n).sum(-1)
                perp = np.sqrt(np.maximum((v * v).sum(-1) - along ** 2, 0))
                over = np.where(along > -0.01, perp - R * self.k, 9.0).min(1)
                self.best[di, i0:i0 + 512] = np.minimum(self.best[di, i0:i0 + 512], over)

    def gaps(self):
        g = np.where(self.vis, np.maximum(self.best, 0), 0.0)
        return g.max(0), g

    def stats(self):
        g, per = self.gaps()
        return float((g > 0.004).mean()), float(g.max())


def coverage(locs, P, Nn, dirs=(), k=0.95):
    cv = Coverage(P, Nn, dirs, k)
    for lc in locs:
        cv.add(lc)
    return cv.gaps()[0]


def fill_gaps(locs, grow_at, max_add, min_gap, log, dirs=(), extra_dirs_gap=None):
    """adds locs where the scalp shows through (the largest gap first, from straight above the scalp and from the
    view directions); grow_at(th, az) -> a new loc dict or None"""
    P, Nn = scalp_grid()
    cv = Coverage(P, Nn, dirs)
    for lc in locs:
        cv.add(lc)
    added = 0
    tried = np.zeros(len(P), bool)
    while added < max_add:
        gap, _per = cv.gaps()
        gap = np.where(tried, 0.0, gap)
        i = int(np.argmax(gap))
        if gap[i] < min_gap:
            break
        # don't retry next to a point that was tried
        tried |= np.linalg.norm(P - P[i], axis=1) < 0.012
        th, az = SK.angles(P[i] - C)
        lc = grow_at(th, az)
        if lc is not None:
            locs.append(lc)
            cv.add(lc)
            added += 1
    frac, mx = cv.stats()
    log(f"  gap fill: +{added} locs; scalp showing at {100 * frac:.0f}% of (point, view) maxima, largest gap"
        f" {mx:.3f} (views: normal, {', '.join(dirs) or '-'})")
    return added


def build_guides_hanging(cfg, ref, log):
    rng = np.random.default_rng(cfg["seed"] + 1)
    roots = box_roots(cfg["spacing"], cfg["margin"], cfg["seed"])
    roots += sideburn_roots(cfg["seed"] + 5, cfg["sideburn_ys"])
    heading = heading_hanging(cfg["back_front"], cfg.get("splay", 0.1))
    locs = []
    root_len = 0.05

    def make(r, rot=None, head_fn=None):
        q = r["p"]
        if abs(q[0]) > 0.28 and q[1] < 0.13 and q[2] < 0.07 and not r.get("sideburn"):
            return None  # low on the sideburn, in front of the ear: a hanging loc from here would cross the ear
        R = cfg["R"] * float(np.clip(1 + cfg["rvar"] * rng.normal(), 0.72, 1.35))
        if r.get("edge"):
            R *= float(rng.uniform(0.6, 0.85))  # the hairline row: finer locs, uneven
        if r.get("sideburn"):
            R *= 0.9
        sp = r["p"]
        # the hairline row lies down from the root (within ~10 degrees of the scalp), the rest lift a little
        lift = 0.05 if r.get("edge") else (cfg["lift"] if r["e"] > 0.14 else 0.1)
        # front and side locs are a little shorter (they frame the face), back ones longest; ~14% of the top
        # locs (outer layer) much shorter, so the tips do not end on one line
        backness = float(smooth(-0.3, 0.45, sp[2]))
        hl_ = cfg["hang_len"] * (0.8 + 0.4 * r["rnd"]) * (1 - cfg["side_short"] * (1 - backness))
        if not r.get("edge") and r["rnd3"] < cfg["short_top"] and sp[1] > 0.4:
            hl_ *= 0.5
        # each section's own direction off the flow (neighbours cross), less at the hairline
        if rot is None:
            rot = math.radians(cfg.get("rot_deg", 20)) * float(rng.uniform(-1, 1)) * (0.5 if r.get("edge") else 1.0)
        base_heading = head_fn or heading

        def hdg(p, n, rot=rot):
            f = base_heading(p, n)
            return unit(f * math.cos(rot) + np.cross(n, f) * math.sin(rot))
        # the hairline row's roots taper more and over a shorter run (seen end-on from the front)
        er = cfg.get("edge_root", (cfg.get("edge_root_k", 0.45), 0.065, 0.3))
        rk, rl = ((er[0], er[1]) if r.get("edge")
                  else (cfg.get("root_k", ROOT_K), root_len))
        # crown volume: locs from the top rise off the scalp over the first ~30% of their run on it
        crown = float(smooth(0.42, 0.56, sp[1])) * float(smooth(-0.32, -0.12, sp[2])) * (0.0 if r.get("edge") else 1.0)
        bump_h = cfg.get("crown_lift", 0.0) * crown * (0.7 + 0.6 * r["rnd2"])

        def offs0(s, R=R, rk=rk, rl=rl):
            return CLEAR_MIN + 0.006 + R * (rk + (1 - rk) * float(smooth(0, rl, s)) ** 0.8)
        P, sl = scalp_walk(r, hdg, cfg["step"], offs0, 400, -3.0, lift, rad=R)
        layer = cfg["layer"] * float(np.clip(sl / 0.75, 0, 1)) * (0.75 + 0.5 * r["rnd2"])
        layer *= 0.0 if r.get("edge") else 1.0

        def bump(s, sl=sl, bump_h=bump_h):
            return bump_h * float(smooth(0.02, 0.3 * sl, s)) * (1 - 0.6 * float(smooth(0.35 * sl, 0.9 * sl, s)))

        def offs(s, R=R, layer=layer):
            return offs0(s, R) + layer * float(smooth(0.03, 0.2, s)) + bump(s)
        P, sl = scalp_walk(r, hdg, cfg["step"], offs, 400, -3.0, lift, rad=R)
        L = min(cfg["L_max"], sl + hl_)
        D, S = densify(P, 2)
        P = at_s(D, S, np.linspace(0, min(L, S[-1]), max(8, int(L / cfg["step"]) + 1)))
        # the front hairline row is seen close up: rounder sections
        sides = cfg["sides"] + 2 if (r.get("edge") and sp[2] < -0.1) else cfg["sides"]
        return dict(root=r, R=R, P=P, scalp_len=sl, layer=layer, root_len=rl, root_k=rk, bump=bump, sides=sides)
    for r in roots:
        lc = make(r)
        if lc is not None:
            locs.append(lc)
    # two crown locs lying over the centre-back parting, crossing it from either side
    for sgn in (-1, 1):
        th, az = 0.55, (-sgn * 0.22) % TAU
        p = SK.point(th, az)
        r = dict(th=th, az=az, p=p, n=SK.normal(th, az), e=float(edge_dist(p)[0]), rnd=rng.random(),
                 rnd2=rng.random(), rnd3=1.0, crossing=True)

        def cross_head(p_, n_, sgn=sgn):
            return tproj(np.array([0.3 * sgn, -1.0, 0.45]), n_)
        locs.append(make(r, rot=0.0, head_fn=cross_head))

    def grow_at(th, az):
        p = SK.point(th, az)
        e = float(edge_dist(p)[0])
        # a fill root close to the hairline belongs to the hairline row (lies down, finer, rounder)
        r = dict(th=th, az=az, p=p, n=SK.normal(th, az), e=e, rnd=rng.random(),
                 rnd2=rng.random(), rnd3=1.0, fill=True, edge=e < 0.07)
        return make(r)
    fill_gaps(locs, grow_at, cfg.get("fill", 0), cfg.get("min_gap", 0.014), log, dirs=cfg.get("cov_dirs", ()))
    log(f"  {len(locs)} locs from box-parted roots ({sum(1 for lc in locs if lc['root'].get('sideburn'))} sideburn)")
    relax_hanging(cfg, ref, locs, log)
    # a second coverage pass on the relaxed locs (from the view directions as well): new locs where the scalp
    # still shows, then all of them relaxed again together
    if cfg.get("fill2"):
        n1 = len(locs)
        fill_gaps(locs, grow_at, cfg["fill2"], cfg.get("min_gap", 0.014), log, dirs=cfg.get("cov_dirs", ()))
        for lc in locs[n1:]:
            lc["G"] = lc["P"]
        log(f"  second pass: +{len(locs) - n1} locs, relaxing all again")
        relax_hanging(cfg, ref, locs, log)
    return locs


def relax_hanging(cfg, ref, locs, log):
    M = cfg["M"]
    N = len(locs)
    X = np.zeros((N, M, 3))
    seg = np.zeros(N)
    rad = np.zeros((N, M))
    off = np.zeros((N, M))
    wsh = np.zeros((N, M))
    for i, lc in enumerate(locs):
        Pm, L = resample(lc["P"], M)
        X[i] = Pm
        seg[i] = L / (M - 1)
        lc["L"] = L
        s = np.linspace(0, L, M)
        rk, rl = lc["root_k"], lc["root_len"]
        rad[i] = lc["R"] * (rk + (1 - rk) * smooth(0, rl, s) ** 0.8)
        off[i] = CLEAR_MIN + 0.006 + rad[i] + lc["layer"] * smooth(0.03, 0.2, s) + np.array([lc["bump"](x) for x in s])
        # the styled part keeps its shape (combed back off the face), the hanging part follows gravity
        # (the hairline row firmly: it is combed back, it must not slide forward over the forehead)
        k_sh = 0.3 if lc["root"].get("edge") else 0.08
        wsh[i] = k_sh * (1 - smooth(lc["scalp_len"] - 0.06, lc["scalp_len"] + 0.12, s))
    # bending: a loc turns from its root onto the scalp within a few centimetres, then hangs nearly straight
    bend = np.zeros((N, M))
    for i, lc in enumerate(locs):
        s = np.linspace(0, lc["L"], M)
        bend[i] = 0.88 + (0.975 - 0.88) * smooth(0.05, 0.16, s)
    sim = Sim(ref, X, seg, rad, off, wshape=wsh, pin=2, gravity=0.0014, damp=0.9, bend=bend,
              guard=guard_hanging, repel=cfg.get("repel", 0.92), body_off=cfg["body_off"])
    t = time.time()
    X = sim.run(160)
    X = smooth_chain(X, passes=3)
    # a slight S-wave along the hanging part (sideways, in the plane of the body's surface), then settled again
    amp, lam = cfg["wave"]
    for i, lc in enumerate(locs):
        s = np.linspace(0, lc["L"], M)
        w = smooth(lc["scalp_len"], lc["scalp_len"] + 0.15, s) * amp
        ph = lc["root"]["rnd2"] * TAU
        T = unit(np.gradient(X[i], axis=0))
        out = unit(np.stack([X[i][:, 0], np.zeros(M), X[i][:, 2] - 0.03], 1))
        sd = unit(np.cross(T, out))
        X[i] += sd * (w * np.sin(TAU * s / lam + ph))[:, None]
    sim.X = X
    for _ in range(4):
        sim.constraints(2)
        sim.collide()
    log(f"  relaxed {N} guides in {time.time() - t:.1f}s")
    for i, lc in enumerate(locs):
        lc["G"] = sim.X[i].copy()


WHORL_TH, WHORL_AZ = 0.34, 0.25  # the crown whorl: behind the vertex, a little to the right


def _snoise(p, seed):
    """a smooth noise field over the head, about -1..1"""
    k = ((6.3, 4.1, -5.2, 0.3), (-3.7, 7.9, 4.4, 1.7), (5.1, -2.9, 6.8, 4.1), (8.3, 1.1, 3.0, 2.2))
    v = sum(math.sin(a * p[0] + b * p[1] + c * p[2] + ph + seed * 1.37) for a, b, c, ph in k)
    return max(-1.0, min(1.0, v / 2.2))


def side_zone(p):
    """the temples, the strip over the ears and just behind them (short, fine locs lying back over the ear)"""
    return abs(p[0]) > 0.22 and p[1] < 0.3 and -0.36 < p[2] < 0.24


def short_flow(p, n, rot=0.0, back=False):
    """Short Dreads' flow on the scalp: out from the crown whorl with a slight swirl, turned +/-25 degrees by a
    smooth noise field and the loc's own angle; at the temples and over the ears back and a little down; the
    hairline row (back=True): up and back over the scalp, toward the whorl, a little to the side"""
    w = SK.point(WHORL_TH, WHORL_AZ)
    rad = p - w
    rad = rad - n * float(np.dot(rad, n))
    if np.linalg.norm(rad) < 1e-4:
        rad = tproj(np.array([0.0, 0.0, -1.0]), n)
    rad = unit(rad)
    sw = unit(np.cross(n, rad))
    # a spiral round the whorl (the crown locs wrap round it and cover it), radial further out
    near = 1 - float(smooth(0.1, 0.36, float(np.linalg.norm(p - w))))
    f = unit(rad * (1 - 0.9 * near) + sw * (0.2 + 1.3 * near))
    if back:
        f = unit(-rad + 0.5 * unit(np.array([p[0], 0.0, 0.0]) + 1e-9) * float(smooth(0.05, 0.25, abs(p[0]))))
    elif side_zone(p):
        k = float(smooth(0.22, 0.3, abs(p[0])))
        f = unit(f * (1 - k) + np.array([0.0, -0.35, 1.0]) * k)
    a = math.radians(25) * _snoise(p, 0.0) + rot
    f = tproj(f, n)
    f = unit(f * math.cos(a) + np.cross(n, f) * math.sin(a))
    return f


def grow_short(r, L, R, lift, M, rnd, root_len, rk=ROOT_K, droop=1.0, curl=(5.0, 0.4, 0.0), back=False,
               lie=0.0):
    """one short loc grown from its root: off the scalp at `lift`, along the flow, its heading turning sideways
    with a soft S (curl: amplitude rad / stud, wavelength, phase) and drooping under gravity (droop) from about a
    fifth of its length; lie pulls it down onto the head over its second half. Kept off the skull, the face and
    the ears, within the silhouette."""
    n = r["n"]
    ds = L / (M - 1)

    def rr(s):
        return R * (rk + (1 - rk) * float(smooth(0, root_len, s)) ** 0.8)
    p = SK.point(r["th"], r["az"], CLEAR_MIN + 0.006 + rr(0))
    rot = math.radians(20) * (2 * rnd - 1)
    f = short_flow(p, n, rot, back)
    d = unit(n * lift + f * (1 - lift))
    pts = [p]
    G = (5.5 + 3.0 * r["rnd2"]) * droop
    ca, lam, ph = curl
    for k in range(1, M):
        s = k * ds
        sp, th, az = SK.project(pts[-1])
        nk = SK.normal(th, az)
        fk = short_flow(sp, nk, rot, back)
        # the S: the heading turns about the scalp normal, one way then the other
        ang = ca * math.sin(TAU * s / lam + ph) * ds
        d = d * math.cos(ang) + np.cross(nk, d) * math.sin(ang) + nk * float(np.dot(nk, d)) * (1 - math.cos(ang))
        wg = float(smooth(0.15 * L, 0.55 * L, s))
        wl = float(smooth(0.4 * L, 0.9 * L, s)) * lie
        d = unit(d + ds * (G * wg * DOWN + 1.2 * fk - 6.0 * wl * nk))
        q = pts[-1] + d * ds
        q = skull_push(q, CLEAR_MIN + 0.006 + rr(s))
        q = guard_short(q, rr(s))
        q = pts[-1] + unit(q - pts[-1]) * ds
        d = unit(q - pts[-1])
        pts.append(q)
    P = np.array(pts)
    # never over the ears: cut the loc before it reaches an ear (grown by the clearance)
    cut = len(P)
    for k, q in enumerate(P):
        for lo, hi in EARS:
            g = EAR_CLEAR + R + 0.008
            if np.all(q > lo - g) and np.all(q < hi + g):
                cut = min(cut, k)
    if cut < len(P):
        P = P[:max(4, cut)]
    return P


def side_roots(seed, spacing, margins):
    """extra rows of small locs at the temples and over / behind the ears (margins inside the natural hairline)"""
    rng = np.random.default_rng(seed)
    out = []
    for m in margins:
        for r in hairline_row(spacing, m, rng, jitter=0.3):
            if side_zone(r["p"]):
                r["side"] = True
                r["edge"] = False
                out.append(r)
    return out


def build_guides_short(cfg, ref, log):
    rng = np.random.default_rng(cfg["seed"] + 1)
    pole = hl.Skull.direction(WHORL_TH, WHORL_AZ)
    roots = box_roots(cfg["spacing"], cfg["margin"], cfg["seed"], pole=pole, whorl_ring=5, grade=0.15,
                      edge_gap=cfg.get("edge_gap", 0.3), edge_spacing=cfg.get("edge_spacing"))
    # the side zone gets its own rows of small locs (the box sections there are dropped)
    roots = [r for r in roots if not (side_zone(r["p"]) and not r.get("edge"))]
    roots += side_roots(cfg["seed"] + 9, 0.062, (0.045, 0.1, 0.155))
    roots += sideburn_roots(cfg["seed"] + 5, cfg["sideburn_ys"])
    M = cfg["M"]
    locs = []
    root_len = 0.04

    def make(r):
        sp = r["p"]
        R = cfg["R"] * float(np.clip(1 + cfg["rvar"] * rng.normal(), 0.7, 1.35))
        top = float(smooth(0.3, 0.55, sp[1]))
        front = float(smooth(-0.1, -0.35, sp[2]))
        # lengths 0.3..0.6 (median ~0.4), a little shorter toward the front; uneven
        L = (0.3 + 0.22 * float(rng.beta(2.0, 2.2))) * (1.0 + 0.12 * top) * (1 - 0.12 * front) \
            * (0.85 + 0.3 * r["rnd"])
        # the top lies out over the next ring of roots (no spokes of bare partings seen from above), the sides
        # and back fall against the head
        lift = 0.24 + 0.16 * top
        droop = 1.0 - 0.45 * top
        lie = 0.6 * (1 - top) + 0.25 * top
        curl = (float(rng.uniform(2.5, 5.0)) * rng.choice([-1, 1]), L * float(rng.uniform(1.1, 1.8)),
                float(rng.uniform(0, TAU)))
        back = False
        tip_r = None
        halo = True
        if r.get("whorl"):
            # the whorl: small locs curling round it and over it
            R *= 0.85
            lift, lie = 0.25, 0.7
            curl = (math.copysign(5.0, curl[0]), curl[1], curl[2])
        if r.get("edge") and not side_zone(sp):
            # the hairline row: rises off the scalp, then lies back over the next row (no bare band behind it)
            L = float(rng.uniform(0.2, 0.32))
            lift, droop, lie, back = 0.55, 0.5, 0.8, True
            R *= 0.85
        if r.get("side") or (r.get("edge") and side_zone(sp)):
            R = cfg["R"] * float(rng.uniform(0.62, 0.82))
            L = float(rng.uniform(0.08, 0.18))
            lift, droop, lie = 0.25, 0.6, 1.0
            curl = (curl[0] * 0.5, curl[1], curl[2])
        if r.get("sideburn"):
            R = cfg["R"] * float(rng.uniform(0.55, 0.7))
            L = float(rng.uniform(0.05, 0.08))
            lift, droop, lie = 0.2, 0.8, 1.0
            halo = False
            tip_r = 0.7
        L = float(np.clip(L, 0.05, 0.62))
        rk, rl = (0.4, 0.03) if (r.get("edge") or r.get("side")) else (ROOT_K, root_len)
        if r.get("sideburn"):
            rl = 0.02
        P = grow_short(r, L, R, lift, M, r["rnd3"], rl, rk, droop, curl, back, lie)
        Pm, L2 = resample(P, M)
        # fewer sides where the facets cannot be seen: the fine side / sideburn locs (R ~0.02) and the back
        sides = cfg["sides"]
        if r.get("side") or r.get("sideburn") or (r.get("edge") and side_zone(sp)):
            sides = 5
        elif sp[2] > -0.05:
            sides = 6  # behind the front half: seen from further away
        return dict(root=r, R=R, P=Pm, L=L2, layer=0.0, scalp_len=0.0, root_len=rl, root_k=rk, halo=halo,
                    tip_r=tip_r, sides=sides)
    for r in roots:
        locs.append(make(r))
    n0 = len(locs)

    def grow_at(th, az):
        p = SK.point(th, az)
        d = np.linalg.inv(_rot_from_y(pole)) @ unit(p - C)
        r = dict(th=th, az=az, p=p, n=SK.normal(th, az), e=float(edge_dist(p)[0]), rnd=rng.random(),
                 rnd2=rng.random(), rnd3=rng.random(), pole_t=math.acos(max(-1.0, min(1.0, d[1]))), fill=True,
                 side=side_zone(p))
        return make(r)
    fill_gaps(locs, grow_at, cfg.get("fill", 0), cfg.get("min_gap", 0.012), log, dirs=cfg.get("cov_dirs", ()))
    log(f"  {len(locs)} short locs ({n0} from box-parted roots round the whorl, the side rows and sideburns)")
    N = len(locs)
    X = np.stack([lc["P"] for lc in locs])
    seg = np.array([lc["L"] / (M - 1) for lc in locs])
    rad = np.zeros((N, M))
    off = np.zeros((N, M))
    wsh = np.zeros((N, M))
    for i, lc in enumerate(locs):
        s = np.linspace(0, lc["L"], M)
        rk, rl = lc["root_k"], lc["root_len"]
        rad[i] = lc["R"] * (rk + (1 - rk) * smooth(0, rl, s) ** 0.8)
        off[i] = CLEAR_MIN + 0.006 + rad[i]
        # springy: they keep their grown shape, the tips settle a little and the locs push each other apart
        wsh[i] = 0.16 * (1 - 0.6 * s / max(lc["L"], 1e-6))
    sim = Sim(ref, X, seg, rad, off, rest=X.copy(), wshape=wsh, pin=2, gravity=0.0006, damp=0.85, bend=0.99,
              guard=guard_short, repel=0.9, body=False)
    t = time.time()
    X = sim.run(80)
    X = smooth_chain(X, passes=1)
    sim.X = X
    sim.collide()
    log(f"  relaxed {N} short guides in {time.time() - t:.1f}s")
    Ls = []
    for i, lc in enumerate(locs):
        lc["G"] = sim.X[i].copy()
        Ls.append(float(np.linalg.norm(np.diff(lc["G"], axis=0), axis=1).sum()))
    # a second coverage pass on the relaxed locs: new locs (grown, kept off the skull, face and ears as they
    # grow) where the scalp still shows from one of the view directions
    n1 = len(locs)

    def grow_relaxed(th, az):
        lc = grow_at(th, az)
        lc["G"] = lc["P"].copy()
        Ls.append(float(np.linalg.norm(np.diff(lc["G"], axis=0), axis=1).sum()))
        return lc
    fill_gaps(locs, grow_relaxed, cfg.get("fill2", 0), cfg.get("min_gap", 0.012), log,
              dirs=cfg.get("cov_dirs", ()))
    log(f"  second pass: +{len(locs) - n1} locs")
    main = [l_ for l_, lc in zip(Ls, locs) if not (lc["root"].get("side") or lc["root"].get("sideburn"))]
    log("  lengths %.2f..%.2f median %.2f (main locs %.2f..%.2f median %.2f)" % (
        min(Ls), max(Ls), float(np.median(Ls)), min(main), max(main), float(np.median(main))))
    P_, N_ = scalp_grid()
    cv = Coverage(P_, N_, cfg.get("cov_dirs", ()))
    for lc in locs:
        cv.add(lc)
    frac, mx = cv.stats()
    log(f"  relaxed: scalp showing at {100 * frac:.0f}% of points, largest gap {mx:.3f}")
    return locs


# ------------------------------------------------------------------------------------------- splitting
def _plane_cross(D, S, s_from, p0, ax):
    """the first arc length >= s_from where the dense curve D passes the plane through p0 normal to ax (going
    along ax), or None"""
    h = (D - p0) @ ax
    i0 = int(np.searchsorted(S, s_from))
    for i in range(max(1, i0), len(D)):
        if h[i - 1] < 0 <= h[i]:
            t = -h[i - 1] / max(1e-12, h[i] - h[i - 1])
            return float(S[i - 1] + t * (S[i] - S[i - 1]))
    if i0 < len(D) and h[min(i0, len(D) - 1)] >= 0 and i0 > 0:
        return float(S[i0])
    return None


def split_hanging(cfg, locs, ref):
    """chains: the hanging locs grouped by the azimuth round the head of the point where they leave it. Per chain
    one axis (its mean hanging direction) and cut planes normal to it: plane A through the chain's lowest leaving
    point (everything above it - the scalp-lying parts and the tops of the locs that leave higher - stays in the
    static HairTop), and for two-segment chains plane B part way down the hanging part. Every member loc is cut
    exactly where it crosses each plane, so all its breaks lie on the plane of the joint (0 along the axis)."""
    for lc in locs:
        G = lc["G"]
        D, S = densify(G, 6)
        lc["D"], lc["S"] = D, S
        L = S[-1]
        lc["L"] = L
        h = np.array([ref.height(p) for p in D[::3]])
        sidx = S[::3]
        offc = CLEAR + lc["R"] + lc["layer"] + 0.04
        touching = np.where(h < offc)[0]
        sA = float(sidx[touching[-1]]) if len(touching) else 0.0
        sA = max(sA, 0.12)
        lc["sA"] = lc["sB"] = None
        if L - sA < 0.2:
            continue  # stays on the head
        lc["sA0"] = sA
        pA = at_s(D, S, np.array([sA]))[0]
        lc["pA0"] = pA
        lc["azA"] = math.atan2(pA[0], pA[2] - C[2])
    hang = [lc for lc in locs if lc.get("sA0") is not None]
    hang.sort(key=lambda lc: lc["azA"])
    K = cfg["chains"]
    chains = []
    for gi in range(K):
        mem = hang[gi * len(hang) // K:(gi + 1) * len(hang) // K]
        ax = unit(np.mean([unit(lc["D"][-1] - lc["pA0"]) for lc in mem], axis=0))
        # plane A: through the lowest leaving point along the axis
        pa = max((lc["pA0"] for lc in mem), key=lambda p: float(p @ ax))
        cuts = []
        for lc in mem:
            s = _plane_cross(lc["D"], lc["S"], 0.08, pa, ax)
            if s is not None and lc["L"] - s > 0.15:
                cuts.append((lc, s))
        if not cuts:
            continue
        ends = np.array([float((lc["D"][-1] - pa) @ ax) for lc, _s in cuts])
        pb = pa + ax * float(np.median(ends)) * cfg["hang_split"] if cfg["segs"] > 1 else None
        for lc, s in cuts:
            lc["sA"] = s
            lc["chain"] = gi
            if pb is not None:
                sb = _plane_cross(lc["D"], lc["S"], s + 0.05, pb, ax)
                if sb is not None and lc["L"] - sb > 0.08:
                    lc["sB"] = sb
        chains.append(dict(g=gi, ax=ax, pa=pa, pb=pb))
    cfg["_chains"] = chains
    return [lc for lc in locs if lc.get("sA") is not None]


def split_short(cfg, locs):
    """short dreads: crown locs go to bouncing clusters by azimuth, the rest stay in HairTop"""
    K = cfg["clusters"]
    for lc in locs:
        G = lc["G"]
        D, S = densify(G, 6)
        lc["D"], lc["S"], lc["L"] = D, S, S[-1]
        lc["sA"] = None
        r = lc["root"]["p"]
        if r[1] > 0.4:
            az = math.atan2(r[0], r[2] - C[2]) % TAU
            lc["cluster"] = int(az / TAU * K) % K


# ------------------------------------------------------------------------------------------- Blender mesh
def to_bmesh(mb, name, coll):
    """MeshBuild -> Blender object (welded vertices, per-corner UVs and colours)"""
    me = bpy.data.meshes.new(name)
    fl = [f for f, d in zip(mb.F, mb.Fdup) if not d]
    faces = [tuple(mb.G[g][0] for g in f) for f in fl]
    me.from_pydata([tuple(p) for p in mb.W], [], faces)
    me.update()
    me.uv_layers.new(name="UVMap")
    uv = me.uv_layers["UVMap"]
    for poly, f in zip(me.polygons, fl):
        poly.use_smooth = True
        for li, g in zip(poly.loop_indices, f):
            _w, u, v = mb.G[g]
            uv.data[li].uv = (u, 1.0 - v)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def add_lumps(ob, loc_weights, bulge=0.009, lumps=0.005, scale=(0.07, 0.022), seed=0):
    """Displace modifiers along the normals, weighted off at the roots: soft bulges (smooth noise, a few per loc
    length) and small felted lumps"""
    vg = ob.vertex_groups.new(name="lumps")
    for i, w in enumerate(loc_weights):
        if w > 1e-3:
            vg.add([i], float(w), "REPLACE")
    tv = bpy.data.textures.new(f"{ob.name}_bulges", "CLOUDS")
    tv.noise_scale = scale[0]
    tv.noise_depth = 0
    tv.noise_basis = "IMPROVED_PERLIN"
    tc = bpy.data.textures.new(f"{ob.name}_lumps", "CLOUDS")
    tc.noise_scale = scale[1]
    tc.noise_depth = 2
    m1 = ob.modifiers.new("bulges", "DISPLACE")
    m1.texture = tv
    m1.texture_coords = "GLOBAL"
    m1.direction = "NORMAL"
    m1.mid_level = 0.5
    m1.strength = -bulge
    m1.vertex_group = "lumps"
    m2 = ob.modifiers.new("lumps", "DISPLACE")
    m2.texture = tc
    m2.texture_coords = "GLOBAL"
    m2.direction = "NORMAL"
    m2.mid_level = 0.5
    m2.strength = lumps
    m2.vertex_group = "lumps"


def evaluated(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    oe = ob.evaluated_get(dg)
    me = oe.to_mesh()
    n = len(me.vertices)
    co = np.zeros(n * 3)
    me.vertices.foreach_get("co", co)
    nr = np.zeros(n * 3)
    me.vertex_normals.foreach_get("vector", nr)
    oe.to_mesh_clear()
    return co.reshape(-1, 3), nr.reshape(-1, 3)


def enforce_clearance(P, N, ref, minh, body_min=0.0):
    """vertices closer than minh to the head (body_min to the torso) pushed out along the outward direction;
    returns the count"""
    moved = 0
    for i in range(len(P)):
        r = Ref.signed(ref.head, P[i], minh + 0.01)
        q = P[i]
        if r is not None and r[2] < minh:
            q = r[0] + r[1] * (minh + 0.0005)
        q = skull_push(q, minh + 0.0005)
        q = ear_push(q, EAR_BOX_MIN)
        if body_min > 0 and q[1] < -0.3:
            r = Ref.signed(ref.torso, q, body_min + 0.01)
            if r is not None and r[2] < body_min:
                q = r[0] + r[1] * (body_min + 0.0005)
        if q[2] < -0.2 and abs(q[0]) < 0.32 and q[1] > -0.4:  # nothing on the forehead below the hairline
            hy = float(hairline_y(q)[0]) - 0.003
            if q[1] < hy:
                q = q.copy()
                q[1] = hy
        if not np.allclose(q, P[i]):
            P[i] = q
            moved += 1
    return moved


FIB = None


def hemi_dirs(n=14):
    """n directions over the hemisphere about +z (Fibonacci), elevation at least ~15 degrees"""
    global FIB
    if FIB is None:
        i = np.arange(n) + 0.5
        z = 1 - (i / n) * 0.75
        r = np.sqrt(1 - z * z)
        ph = i * math.pi * (3 - math.sqrt(5))
        FIB = np.stack([r * np.cos(ph), r * np.sin(ph), z], 1)
    return FIB


def bake_ao(P, N, bvh, dist=0.16, n=14, groups=None):
    """occlusion per vertex: the cosine-weighted share of hemisphere rays (about the vertex normal) that hit
    something between 0.012 and dist away (nearer hits are the loc's own lumps); with groups (a key per vertex,
    e.g. its loc and ring), each vertex is blended 60/40 with its group's mean, so the occlusion varies along a
    loc rather than in patches round it"""
    H = hemi_dirs(n)
    wsum = float(H[:, 2].sum())
    occ = np.zeros(len(P))
    for i in range(len(P)):
        nn = N[i]
        a = np.array([1.0, 0, 0]) if abs(nn[0]) < 0.9 else np.array([0, 1.0, 0])
        t1 = unit(np.cross(nn, a))
        t2 = np.cross(nn, t1)
        o = Vector(P[i] + nn * 0.012)
        hits = 0.0
        for d in H:
            dv = t1 * d[0] + t2 * d[1] + nn * d[2]
            loc, _n, _ix, _d = bvh.ray_cast(o, Vector(dv), dist)
            if loc is not None:
                hits += d[2]
        occ[i] = hits / wsum
    if groups is not None:
        acc = {}
        for i, g in enumerate(groups):
            t = acc.setdefault(g, [0.0, 0])
            t[0] += occ[i]
            t[1] += 1
        mean = np.array([acc[g][0] / acc[g][1] for g in groups])
        occ = 0.6 * mean + 0.4 * occ
    return occ


# ------------------------------------------------------------------------------------------- the style
def build_style(key, cfg, ref, coll, log):
    if cfg["kind"] == "hang":
        locs = build_guides_hanging(cfg, ref, log)
        split_hanging(cfg, locs, ref)
    else:
        locs = build_guides_short(cfg, ref, log)
        split_short(cfg, locs)
    # guide curves into the .blend
    gcoll = bpy.data.collections.new("guides (relaxed loc curves)")
    coll.children.link(gcoll)
    cu = bpy.data.curves.new(f"{key}_guides", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = 1
    for lc in locs:
        sp = cu.splines.new("POLY")
        sp.points.add(len(lc["G"]) - 1)
        for k, p in enumerate(lc["G"]):
            sp.points[k].co = (p[0], p[1], p[2], 1.0)
            sp.points[k].radius = lc["R"]
    gob = bpy.data.objects.new(f"{key}_guides", cu)
    gcoll.objects.link(gob)

    rng = np.random.default_rng(cfg["seed"] + 7)
    tubes, halos = MeshBuild(), MeshBuild()
    # v runs from the root (0) to the tip (~1) of every loc (the game tints the texture's rows root to tip: darker
    # roots, Tips / Ombre dyes; it does not tile this key). u wraps once round each tube: twists over the whole
    # twist core; locs over one or both of the loc core's two identical u-periods, whichever keeps the texel
    # density round the loc closest to the density along it (no bark-like stretching on the long locs)
    for li, lc in enumerate(locs):
        D, S, L = lc["D"], lc["S"], lc["L"]
        rnd = rng.random()
        R = lc["R"]
        root_len = lc.get("root_len", 0.08)
        root_k = lc.get("root_k", ROOT_K)
        tr = cfg["tip_r"]
        tip_r = float(rng.uniform(*tr)) if isinstance(tr, tuple) else tr
        if lc.get("tip_r") is not None:
            tip_r = lc["tip_r"]

        def radius(s, L=L, R=R, rnd=rnd, root_len=root_len, root_k=root_k, tip_r=tip_r):
            return loc_radius(s, L, R, rnd, root_len=root_len, tip_r=tip_r, lump=cfg["lump"], root_k=root_k)
        sA, sB = lc.get("sA"), lc.get("sB")
        forced = []
        for x in (sA, sB):
            if x is not None:
                forced += [x, x + JOINT_SLEEVE]

        def seg_of(s, sA=sA, sB=sB):
            if sA is None or s < sA:
                return 0
            if sB is None or s < sB:
                return 1
            return 2
        if cfg["lobes"] == "twist":
            # a ring every quarter turn of the strand pair: the lobes' silhouette zig-zags round the twist
            n_iv = int(round(4 * TWIST_TURNS))
            s_r = np.linspace(0, L, n_iv + 1)
            for f in forced:
                j = int(np.argmin(np.abs(s_r - f)))
                if 0 < j < n_iv:
                    s_r[j] = f
            s_r = np.array(sorted(set(np.round(s_r, 6))))
        else:
            bs = cfg.get("base_scalp")
            base = cfg["base_ds"]
            if bs and lc.get("scalp_len"):
                # finer over the scalp (the loc follows its curve), coarse down the straight hanging part
                fine = 0.45 if (lc["root"].get("edge") and lc["root"]["p"][2] < -0.1) else 0.0
                base = (lambda s, sl=lc["scalp_len"], bs=bs, bh=cfg["base_ds"], fine=fine:
                        0.085 if s < fine else (bs if s < sl + 0.05 else bh))
            s_r = ring_positions(D, S, base, (root_len, 0.05, cfg.get("end_ds", 0.034)), forced,
                                 cfg.get("min_ds", 0.016), cfg.get("bend_k", 0.3))
        lc["rings"] = len(s_r)
        if os.environ.get("LOCS_RINGS") and lc["root"].get("edge") and lc["root"]["p"][2] < -0.3:
            print("rings", li, round(L, 2), lc.get("scalp_len"), lc.get("sides"), np.round(s_r, 2).tolist())
        inward = unit(C - D[0])
        if cfg["lobes"] == "twist":
            strip = TWIST_CORE
            v0 = 0.0
        else:
            k = 2 if 40.2 * R / max(L, 1e-3) > 1.5 else 1
            off = 0.0 if k == 2 else float(rng.uniform(0, LOC_PERIOD))
            strip = (LOC_CORE[0] + off, LOC_CORE[0] + off + k * LOC_PERIOD)
            v0 = 0.03 * rng.random()
        lc["u_periods"] = (strip[1] - strip[0]) / LOC_PERIOD if cfg["lobes"] is None else None
        vps = (L + 1.1 * R) / (0.995 - v0)
        lc["vps"] = vps
        build_tube(tubes, li, D, S, s_r, radius, lc.get("sides", cfg["sides"]), strip, vps, v0, inward,
                   lobes=cfg["lobes"], seg_of=seg_of, tip_k=cfg.get("tip_k", 0.9), dome=cfg.get("dome", 1),
                   root_k_apex=cfg.get("edge_root", (0, 0, 0.3))[2] if lc["root"].get("edge") else 0.6)
        hc = cfg["halo"]
        if lc.get("halo", True):
            build_halo(halos, li, D, S, radius, L, vps, inward, seg_of=seg_of, root_k=hc["root_k"], k=hc["k"],
                       step=hc["step"], rnd=rng.random(), fins=cfg.get("fins", 2))
    log("  rings/loc %.1f, L %.2f..%.2f, sA/L %.2f, hanging %d" % (
        np.mean([lc["rings"] for lc in locs]), min(lc["L"] for lc in locs), max(lc["L"] for lc in locs),
        np.mean([(lc.get("sA") or lc["L"]) / lc["L"] for lc in locs]), sum(1 for lc in locs if lc.get("sA"))))
    log(f"  tubes: {len(tubes.W)} welded verts, {len(tubes.F)} faces; halos: {len(halos.W)} verts")
    # Blender objects, Displace modifiers (weighted off at the root), evaluated back
    mcoll = bpy.data.collections.new("modelled (modifier stacks)")
    coll.children.link(mcoll)
    tob = to_bmesh(tubes, f"{key}_locs", mcoll)
    w = [float(smooth(0.03, 0.12, s)) for (_l, s) in tubes.wmeta]
    add_lumps(tob, w, bulge=0.007 if cfg["lobes"] is None else 0.003, lumps=0.002, scale=(0.06, 0.016))
    hob = to_bmesh(halos, f"{key}_frizz", mcoll)
    Pt, Nt = evaluated(tob)
    Ph = np.array(halos.W)
    Nh = np.array([n for n in halos.Wn])
    bmin = 0.045 if cfg["kind"] == "hang" else 0.0
    moved_t = enforce_clearance(Pt, Nt, ref, CLEAR_MIN, bmin)
    moved_h = enforce_clearance(Ph, Nh, ref, CLEAR_MIN, bmin)
    log(f"  clearance pushes: tubes {moved_t}, halos {moved_h}")
    # soft occlusion: rays against the locs, the head and the torso
    tf = [tuple(mb_g for mb_g in (tubes.G[g][0] for g in f)) for f in tubes.F]
    allP = np.vstack([Pt, ref.headP, ref.torsoP])
    o1 = len(Pt)
    o2 = o1 + len(ref.headP)
    allF = tf + [(a + o1, b + o1, c + o1) for (a, b, c) in ref.headF] + [(a + o2, b + o2, c + o2)
                                                                        for (a, b, c) in ref.torsoF]
    bvh = BVHTree.FromPolygons([tuple(p) for p in allP], allF)
    t = time.time()
    occ_t = bake_ao(Pt, Nt, bvh, groups=[(l, round(sv, 5)) for (l, sv) in tubes.wmeta])
    occ_h = bake_ao(Ph, Nh, bvh, n=8)
    log(f"  occlusion baked in {time.time() - t:.1f}s")
    s_t = np.array([s for (_l, s) in tubes.wmeta])
    col_t = (0.5 + 0.5 * (1 - occ_t) ** 1.25) * (0.82 + 0.18 * smooth(0.0, 0.1, s_t))
    s_h = np.array([s for (_l, s) in halos.wmeta])
    col_h = (0.62 + 0.38 * (1 - occ_h)) * (0.85 + 0.15 * smooth(0.0, 0.1, s_h))
    col_t = np.clip(col_t, 0.5, 1.0)
    col_h = np.clip(col_h, 0.55, 1.0)
    # write the occlusion back to the Blender objects (corner colours) for the .blend
    for ob, mb, col in ((tob, tubes, col_t), (hob, halos, col_h)):
        me = ob.data
        me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        ca = me.color_attributes["Col"]
        for poly, f in zip(me.polygons, [f for f, d in zip(mb.F, mb.Fdup) if not d]):
            for li, g in zip(poly.loop_indices, f):
                c = float(col[mb.G[g][0]])
                ca.data[li].color = (c, c, c, 1.0)
    if "dump" in os.environ.get("LOCS_DEBUG", ""):
        import pickle
        with open(os.path.join(os.environ.get("LOCS_DUMP_DIR", "/tmp"), f"locs_{key}.pkl"), "wb") as fh:
            pickle.dump([dict(G=lc["G"], R=lc["R"], root={k: v for k, v in lc["root"].items()
                                                          if k in ("p", "edge", "side", "sideburn", "whorl", "fill")})
                         for lc in locs], fh)
    # pieces
    pieces = make_pieces(key, cfg, locs, ref, tubes, Pt, Nt, col_t, halos, Ph, Nh, col_h)
    return pieces, locs


def piece_names(cfg, locs):
    """loc index, segment -> piece name; and per piece its hairfx / hideUnder / length"""
    names = {}
    meta = {"HairTop": dict(material="Fabric", castShadow=True)}
    if cfg["kind"] == "hang":
        for li, lc in enumerate(locs):
            names[(li, 0)] = "HairTop"
            if lc.get("sA") is not None:
                g = lc["chain"] + 1
                names[(li, 1)] = f"{cfg['prefix']}{g:02d}"
                names[(li, 2)] = f"{cfg['prefix']}{g:02d}b"
    else:
        for li, lc in enumerate(locs):
            names[(li, 0)] = f"HairClump{lc['cluster'] + 1:02d}" if "cluster" in lc else "HairTop"
    return names, meta


def make_pieces(key, cfg, locs, ref, tubes, Pt, Nt, col_t, halos, Ph, Nh, col_h):
    names, meta = piece_names(cfg, locs)
    # per piece the faces, ordered from the innermost loc outward (tubes, then halos)
    per = {}
    for mb, tag in ((tubes, "t"), (halos, "h")):
        for fi, (li, sg) in enumerate(mb.Ftag):
            nm = names[(li, sg)]
            per.setdefault(nm, {"t": [], "h": []})[tag].append(fi)

    # sort key per (piece, loc): mean height above the head of the loc's welded vertices
    def loc_key(mb, P, fis):
        hk = {}
        for fi in fis:
            li = mb.Ftag[fi][0]
            if li not in hk:
                lc = locs[li]
                hk[li] = lc["layer"] + 0.0001 * li
        return hk
    pieces = []
    for nm in sorted(per):
        p = hl.Piece(nm, TEX_KEY)
        gmap = {}
        for mb, P, Nn, col, tag in ((tubes, Pt, Nt, col_t, "t"), (halos, Ph, Nh, col_h, "h")):
            fis = per[nm][tag]
            hk = loc_key(mb, P, fis)
            # inner first: by layer; within a loc by face order (root to tip)
            fis = sorted(fis, key=lambda fi: (hk[mb.Ftag[fi][0]], fi))
            for fi in fis:
                ids = []
                sl = mb.Fsleeve[fi]
                for g in mb.F[fi]:
                    kg = (tag, g, sl)
                    if kg not in gmap:
                        wid, u, v = mb.G[g]
                        c = float(col[wid])
                        n_ = Nn[wid]
                        # a sleeve sits a hair (0.0012) outside the surface it copies (no coincident faces)
                        pos = P[wid] + n_ * 0.0012 if sl else P[wid]
                        gmap[kg] = p.vert(pos, n_, (u, v), (c, c, c, 1.0))
                    ids.append(gmap[kg])
                if len(ids) == 4:
                    a, b, c_, d = ids
                    p.tri(a, b, c_)
                    p.tri(a, c_, d)
                else:
                    p.tri(*ids)
        pieces.append(p)
    # metadata: hairfx etc
    byname = {p.name: p for p in pieces}
    if cfg["kind"] == "hang":
        K = cfg["chains"]
        for g in range(K):
            mem = [lc for lc in locs if lc.get("chain") == g]
            if not mem:
                continue
            pA = np.mean([at_s(lc["D"], lc["S"], np.array([lc["sA"]]))[0] for lc in mem], axis=0)
            # the chain's tip: where its locs end, as low as the lowest end (x, z: the mean of the lower half of
            # the end points), so HairFX's length and body tests reach the real ends, not a point above them
            ends = sorted((lc["D"][-1] for lc in mem), key=lambda q: q[1])
            pE = np.mean(ends[:max(1, (len(ends) + 1) // 2)], axis=0)
            pE[1] = float(ends[0][1])
            n1 = f"{cfg['prefix']}{g + 1:02d}"
            n2 = n1 + "b"
            if cfg["segs"] > 1:
                pB = np.mean([at_s(lc["D"], lc["S"], np.array([lc["sB"]]))[0] for lc in mem
                              if lc.get("sB") is not None], axis=0)
            else:
                pB = pE
            fx1 = dict(kind="swing", chain=f"{cfg['chain']}{g + 1:02d}", seg=1, stiff=cfg["stiff"],
                       mass=cfg["mass"][0], pivot=[round(float(x), 4) for x in pA],
                       tip=[round(float(x), 4) for x in pB])
            if n1 in byname:
                byname[n1].meta.update(hairfx=fx1, length="hang", material="Fabric", castShadow=True)
                if pA[1] < 0.36:
                    byname[n1].meta["hideUnder"] = {"headgear": False, "hood": True}
            if cfg["segs"] > 1 and n2 in byname:
                fx2 = dict(kind="swing", chain=f"{cfg['chain']}{g + 1:02d}", seg=2, parent=n1, stiff=cfg["stiff"],
                           mass=cfg["mass"][1], pivot=[round(float(x), 4) for x in pB],
                           tip=[round(float(x), 4) for x in pE])
                byname[n2].meta.update(hairfx=fx2, length="hang", material="Fabric", castShadow=True,
                                       hideUnder={"headgear": False, "hood": True})
    else:
        for p in pieces:
            if p.name.startswith("HairClump"):
                ci = int(p.name[-2:]) - 1
                mem = [lc for lc in locs if lc.get("cluster") == ci]
                # pivot: the scalp under the cluster's roots; tip: the mean of its locs' tips
                rc = np.mean([lc["D"][0] for lc in mem], axis=0)
                sp, _th, _az = SK.project(rc)
                tip = np.mean([lc["D"][-1] for lc in mem], axis=0)
                p.meta.update(hairfx=dict(kind="bounce", stiff=cfg["stiff"], mass=cfg["mass"],
                                          pivot=[round(float(x), 4) for x in sp],
                                          tip=[round(float(x), 4) for x in tip]),
                              material="Fabric", castShadow=True)
    for p in pieces:
        if "material" not in p.meta:
            p.meta.update(meta.get(p.name, dict(material="Fabric", castShadow=True)))
    # HairTop first, then by name
    pieces.sort(key=lambda p: (p.name != "HairTop", p.name))
    return pieces


# ------------------------------------------------------------------------------------------- checks
def fit_of(skull_path):
    s = hl.Skull(skull_path)

    def plane_point(az, y_target):
        best = None
        for th in np.linspace(0.3, 2.6, 900):
            p = s.point(th, math.radians(az))
            if best is None or abs(p[1] - y_target) < abs(best[1] - y_target):
                best = p
        return best
    return dict(W=plane_point(90, 0.15)[0], T=s.c[1] + s.radius(0.0, 0.0), Fz=plane_point(180, 0.2)[2],
                Bz=plane_point(0, 0.1)[2])


def female_fit():
    fm = dict(W=0.383, T=0.591, Fz=-0.460, Bz=0.520)
    path = os.path.join(REF, "skull_f.json")
    if not os.path.exists(path):
        return dict(ax=0.965, ay=1.0, az=1.0, dz=0.0), None
    ff = fit_of(path)
    return dict(ax=ff["W"] / fm["W"], ay=ff["T"] / fm["T"], az=(ff["Bz"] - ff["Fz"]) / (fm["Bz"] - fm["Fz"]),
                dz=(ff["Bz"] + ff["Fz"]) / 2 - (fm["Bz"] + fm["Fz"]) / 2), path


def clearance_report(pieces, ref_m, ref_f, fit_f, skull_f_path):
    """minimum height above: the male head mesh, the male skull table, the female head mesh and skull through
    the female fit, and the male skull narrowed to 0.965 x width without a fit (the worst case)"""
    sk_f = hl.Skull(skull_f_path) if skull_f_path else None
    out = dict(head_m=9.0, skull_m=9.0, head_f_fit=9.0, skull_f_fit=9.0, skull_m_narrow=9.0, inside_m=0,
               ear_box=9.0, face_below_hairline=0)
    for p in pieces:
        P = np.asarray(p.P)
        # the ears (distance outside their boxes; negative = inside) and the forehead below the hairline
        for lo, hi in EARS:
            dd = np.maximum(lo - P, P - hi)
            out["ear_box"] = min(out["ear_box"], float(np.max(dd, axis=1).min()))
        fr = (P[:, 2] < -0.2) & (np.abs(P[:, 0]) < 0.3) & (P[:, 1] > -0.4)
        if fr.any():
            out["face_below_hairline"] += int((P[fr, 1] < hairline_y(P[fr]) - 0.005).sum())
        Pf = P * [fit_f["ax"], fit_f["ay"], fit_f["az"]] + [0, 0, fit_f["dz"]]
        for q, qf in zip(P, Pf):
            # only points over the head matter for the skull tables (hanging tips are far below)
            h = ref_m.height(q)
            out["head_m"] = min(out["head_m"], h)
            if h < 0:
                out["inside_m"] += 1
            out["head_f_fit"] = min(out["head_f_fit"], ref_f.height(qf))
            if h < 0.12 and q[1] > -0.3:
                out["skull_m"] = min(out["skull_m"], SK.height(q))
                qn = q / np.array([0.965, 1, 1])  # the point in a 0.965x narrower skull's frame
                out["skull_m_narrow"] = min(out["skull_m_narrow"], SK.height(qn) * 1.0)
                if sk_f is not None:
                    out["skull_f_fit"] = min(out["skull_f_fit"], sk_f.height(qf))
    return {k: (round(v, 4) if isinstance(v, float) else v) for k, v in out.items()}


# ------------------------------------------------------------------------------------------- blend file
def hair_material(name="hair_loc"):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(TEX_PATH, check_existing=True)
    tx.image.alpha_mode = "STRAIGHT"
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1
    nt.links.new(tx.outputs[0], mix.inputs[6])
    nt.links.new(vc.outputs[0], mix.inputs[7])
    tint = nt.nodes.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 1
    tint.inputs[7].default_value = (0.09, 0.078, 0.07, 1)
    nt.links.new(mix.outputs[2], tint.inputs[6])
    nt.links.new(tint.outputs[2], bs.inputs["Base Color"])
    nt.links.new(tx.outputs[1], bs.inputs["Alpha"])
    bs.inputs["Roughness"].default_value = 0.8
    m.blend_method = "HASHED"
    return m


def save_blend(key, coll, ref, path):
    root = bpy.data.objects.new("GameSpace (Y up, -Z face)", None)
    bpy.context.scene.collection.objects.link(root)
    root.rotation_euler = (math.pi / 2, 0, math.pi)
    m = hair_material()
    for ob in list(bpy.data.objects):
        if ob is root:
            continue
        if ob.parent is None:
            ob.parent = root
        if ob.type == "MESH":
            ob.data.materials.append(m)
        if ob.type == "CURVE":
            ob.hide_render = True
            ob.hide_set(True)
    me = bpy.data.meshes.new("head_m")
    me.from_pydata([tuple(p) for p in ref.headP], [], ref.headF)
    hob = bpy.data.objects.new("head_m (reference)", me)
    bpy.context.scene.collection.objects.link(hob)
    hob.parent = root
    me2 = bpy.data.meshes.new("torso_m")
    me2.from_pydata([tuple(p) for p in ref.torsoP], [], ref.torsoF)
    tob = bpy.data.objects.new("torso_m (reference)", me2)
    bpy.context.scene.collection.objects.link(tob)
    tob.parent = root
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


# ------------------------------------------------------------------------------------------- renders
def cap_standin(density, outdir, key, tile_key="shortcoil", th_max=2.58309):
    """the shared scalp cap as the game paints it for cut "full": the entry's tile (8 x 4) with alpha = tile alpha
    x natural-hairline coverage x density"""
    from PIL import Image
    gw, gh = 256, 128
    th = (np.arange(gh) + 0.5) / gh * th_max
    az = (np.arange(gw) + 0.5) / gw * TAU
    TH, AZ = np.meshgrid(th, az, indexing="ij")
    s_ = np.sin(TH.ravel())
    D = np.stack([s_ * np.sin(AZ.ravel()), np.cos(TH.ravel()), s_ * np.cos(AZ.ravel())], -1)
    r = np.array([SK.radius(*SK.angles(d)) for d in D])
    S = C + D * r[:, None]
    cov = (smooth(-0.012, 0.01, edge_dist(S)) * density).reshape(gh, gw)
    W, H = 1024, 512
    cov = np.asarray(Image.fromarray((cov * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255
    tile = Image.open(os.path.join(TEX_DIR, f"hair_{tile_key}.png")).convert("RGBA").resize((W // 8, H // 4), Image.LANCZOS)
    t = np.tile(np.asarray(tile, np.float32) / 255, (4, 8, 1))
    t[..., 3] *= cov
    path = os.path.join(outdir, f"capstandin_{key}.png")
    Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)
    p = hl.Piece("HairCap", "short")
    n_th, n_az = 60, 96
    ids = {}
    for i in range(n_th + 1):
        for j in range(n_az + 1):
            t_ = i / n_th * th_max
            a_ = j / n_az * TAU
            d = hl.Skull.direction(t_, a_)
            ids[(i, j)] = p.vert(SK.point(t_, a_, 0.016), d, (j / n_az, i / n_th), (0.5, 0.5, 0.5))
    for i in range(n_th):
        for j in range(n_az):
            p.tri(ids[(i, j)], ids[(i + 1, j + 1)], ids[(i, j + 1)])
            p.tri(ids[(i, j)], ids[(i + 1, j)], ids[(i + 1, j + 1)])
    return p, path


def single_sided(piece):
    """a render copy without the reversed twins of two-sided card triangles (Cycles shades both sides of a face;
    coplanar twins would double the alpha)"""
    q = hl.Piece(piece.name, piece.tex)
    q.P, q.N, q.U, q.C = piece.P, piece.N, piece.U, piece.C
    seen = set()
    for t in piece.T:
        k = tuple(sorted(t))
        if k in seen:
            continue
        seen.add(k)
        q.T.append(t)
    return q


MATTE = {"Roughness": 0.82, "Specular IOR Level": 0.2, "Anisotropic": 0.0}
TINTS = {"black": (0.09, 0.078, 0.07), "darkbrown": (0.188, 0.129, 0.094), "blonde": (0.77, 0.61, 0.36)}
SKINS = {"mid": None, "deep": (0.2, 0.12, 0.08), "light": (0.72, 0.52, 0.4)}


def render_style(key, cfg, pieces, outdir, samples, looks, res=(520, 620), fit_f=None):
    import render
    os.makedirs(outdir, exist_ok=True)
    cap, cap_tex = cap_standin(cfg["entry"]["cap"]["density"], outdir, key)
    long = cfg["kind"] == "hang" and key == "dreadlocks"
    paths, labels = [], []
    for (head_name, tint_name, skin_name, views) in looks:
        tint = TINTS[tint_name]
        focus = (0.0, -0.3, 0.06) if long else (0.0, 0.12, 0.02)
        dist = 6.4 if long else 4.4
        sc = render.Scene(res=res, samples=samples, focus=focus, dist=dist)
        skin = SKINS[skin_name] or render.SKIN
        render.add_obj(sc, os.path.join(REF, f"head_{head_name}.obj"), tint=skin)
        for nm, md in render.load_obj(os.path.join(REF, f"torso_{head_name}.obj")).items():
            sc.add_mesh(dict(md, c=None), material="skin", tint=skin, name="torso")
        scl, off = (1, 1, 1), (0, 0, 0)
        if head_name == "f" and fit_f:
            scl, off = (fit_f["ax"], fit_f["ay"], fit_f["az"]), (0, 0, fit_f["dz"])
        sc.add_piece(cap, texture=cap_tex, tint=tint, offset=off, scale=scl)
        for p in pieces:
            q = single_sided(p)
            dbg = os.environ.get("LOCS_DEBUG", "")  # debug renders: nocol, nofins, notex
            if "nocol" in dbg:
                q.C = [(1.0, 1.0, 1.0, 1.0)] * len(q.C)
            if "nofins" in dbg:
                U = np.asarray(q.U)
                q.T = [t for t in q.T if U[t[0], 0] < FRIZZ_STRIP[0]]
            if "notex" in dbg:
                ob = sc.add_piece(q, texture=None, tint=tint, offset=off, scale=scl)
            else:
                ob = sc.add_piece(q, texture=TEX_PATH, tint=tint, offset=off, scale=scl)
            bs = ob.data.materials[0].node_tree.nodes["Principled BSDF"]
            for k, v in MATTE.items():
                bs.inputs[k].default_value = v
        for v in views:
            path = os.path.join(outdir, f"{key}_{head_name}_{tint_name}_{v}.png")
            if v == "close":
                sc.render(path, view=(14, 6, 1.0), dist=2.3, focus=(0, 0.26, -0.12))
            elif v == "top":
                sc.render(path, view=(0, 86, 1.0), dist=3.8, focus=(0, 0.2, 0.0))
            elif v == "sideclose":
                sc.render(path, view=(80, 5, 1.0), dist=2.4, focus=(0.3, 0.15, -0.05))
            elif v == "top34":
                sc.render(path, view="top34", dist=4.6, focus=(0, 0.2, 0.0))
            else:
                sc.render(path, view=v)
            paths.append(path)
            labels.append(f"{head_name} {tint_name} {v}")
    out = os.path.join(outdir, f"sheet_{key}.jpg")
    render.sheet(paths, out, cols=5, labels=labels, title=f"{key} ({sum(p.nt for p in pieces)} tris)",
                 cell=(312, 372))
    return out


# ------------------------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--no-tex", action="store_true")
    ap.add_argument("--tex-only", action="store_true")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--no-export", action="store_true")
    ap.add_argument("--views", default="", help="renders: only these views (black hair look)")
    args = ap.parse_args()
    t0 = time.time()

    def log(*a):
        print(f"[{time.time() - t0:6.1f}s]", *a, flush=True)
    os.makedirs(TEX_DIR, exist_ok=True)
    if not args.no_tex or not os.path.exists(TEX_PATH):
        make_loc_texture(TEX_PATH)
        log("texture", TEX_PATH)
    if args.tex_only:
        return
    global FIT_F
    fit_f, skf = female_fit()
    FIT_F = fit_f
    log("female fit", {k: round(v, 4) for k, v in fit_f.items()})
    keys = [k for k in STYLES if not args.only or k in args.only.split(",")]
    report = {}
    for key in keys:
        cfg = STYLES[key]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        ref_m = Ref("m")
        ref_f = Ref("f")
        coll = bpy.data.collections.new(f"{key} (locs family)")
        bpy.context.scene.collection.children.link(coll)
        log(f"style {key}")
        pieces, locs = build_style(key, cfg, ref_m, coll, log)
        clr = clearance_report(pieces, ref_m, ref_f, fit_f, skf)
        entry = dict(cfg["entry"])
        entry.update(family="locs", clearance=clr, texture_strips={
            "loc": list(LOC_STRIP), "loc_core": list(LOC_CORE), "twist": list(TWIST_STRIP),
            "twist_core": list(TWIST_CORE), "frizz": list(FRIZZ_STRIP)})
        if not args.no_export:
            data = hl.export_style(key, entry, pieces)
            save_blend(key, coll, ref_m, os.path.join(BLEND_DIR, f"{key}.blend"))
        rep = dict(styles=cfg["entry"]["styles"], tris=sum(p.nt for p in pieces), locs=len(locs),
                   pieces={p.name: dict(nt=p.nt, hairfx=p.meta.get("hairfx", {}).get("kind")) for p in pieces},
                   clearance=clr)
        report[key] = rep
        log(json.dumps(rep))
        if args.render:
            looks = [("m", "black", "mid", ["34", "side", "back", "close", "top34", "top", "sideclose", "front"]),
                     ("m", "darkbrown", "deep", ["34", "back"]), ("f", "blonde", "light", ["34"])]
            if args.quick:
                looks = [("m", "black", "mid", ["34", "side", "back", "close", "top34"])]
            if args.views:
                looks = [("m", "black", "mid", args.views.split(","))]
            rep["sheet"] = render_style(key, cfg, pieces, args.render, args.samples, looks,
                                        res=(520, 620) if not args.quick else (390, 465), fit_f=fit_f)
            log("sheet", rep["sheet"])
    print(json.dumps(report, indent=1))
    log("done")


if __name__ == "__main__":
    main()
