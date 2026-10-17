"""Fades family + the shared scalp cap (Blender, headless):

    /opt/bpyenv/bin/python tools/hair/build_fades.py [--render] [--only key,key] [--quick]

Writes
* textures/hair_short.png      tileable short-hair tile (straight / wavy): the cap of every style
* textures/hair_shortcoil.png  tileable tile of tiny tight coils / sponge curls (Curly, Kinky, Coiled)
* textures/hair_waves.png      tileable 360-waves tile (ridges round the crown on the cap's polar UV)
* textures/hair_crop.png       short tapered tufts (4 strips) for the straight / wavy crop-top cards
* out/cap/                     the shared scalp cap (HairCap, polar UV, thetaMax, tile)
* out/<style key>/             the fade / buzz / waves / caesar / crew entries
* blend/<key>.blend            every model, openable in Blender (materials preview the painted cap)
and, with --render, self-check renders + sheets in the scratchpad (FAM_DIR).

Geometry is built in Blender: the cap and the fur shells are bmesh grids laid on the skull's radial
table, the shells get their tufted unevenness from a Displace modifier (Clouds texture, weighted by a
vertex group that fades to zero at every shell edge), the crop-top cards are strips swept along
guide curves (bpy curve objects, bevel-less, converted through the evaluated depsgraph) that follow
a comb flow over the scalp, and every vertex is checked against the game's head mesh with a
mathutils BVHTree (pushed out to the clearance where it is too close). The evaluated meshes are read
back into hairlib.Piece objects and exported with hairlib.export_style.
"""
import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import hairlib  # noqa: E402
from hairlib import Piece, Skull, smoothstep  # noqa: E402

TEX = os.path.join(HERE, "textures")
BLEND = os.path.join(HERE, "blend")
REF = os.path.join(HERE, "ref")
FAM_DIR = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/fam/fades"

TAU = 2 * math.pi
# the cap's polar UV: v = theta / THETA_MAX. The nape's hairline sits at theta ~141 deg, so the cap must
# reach ~146 deg (the game's placeholder 2.2 rad = 126 deg would cut the nape off)
THETA_MAX = math.radians(148.0)
TILE = [8, 4]  # the tile repeats (u, v) over the cap: ~0.33 x 0.29 studs a tile at the equator
CAP_OFF = 0.02  # the cap's height above the skull (the runtime fit's residual is <= 0.015)
CLEAR = 0.02  # minimum height of any scalp-hugging layer above the skull / head mesh


# =============================================================================================
# Textures (numpy): strands drawn with anti-aliased capsules at 4x, box-filtered down
# =============================================================================================
def pnoise(h, w, seed, fmax=4, amp_decay=0.7, octaves=None):
    """tileable smooth noise in [-1, 1] (random cosines with integer frequencies: periodic in both axes)"""
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


def pnoise_at(field, x, y):
    """sample a tileable field at pixel coords (wrapping, nearest)"""
    h, w = field.shape
    return field[int(y) % h, int(x) % w]


class Canvas:
    """greyscale + alpha accumulation, 'over' compositing; wraps in both axes when tile=True"""

    def __init__(self, w, h, tile=True, base_lum=0.5):
        self.w, self.h, self.tile = w, h, tile
        self.L = np.full((h, w), base_lum, np.float32)
        self.A = np.zeros((h, w), np.float32)

    def strand(self, xs, ys, wid, lum, op):
        """one strand: polyline (xs, ys px), per-point width (px), lum, opacity. Coverage is the max over
        its segments (a strand never darkens itself at its joints)."""
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
        best = np.full(gx.shape, 1e9)
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
            c = np.clip(rr + 0.5 - d, 0, 1) * (op[i] + (op[i + 1] - op[i]) * t)
            # thin strands: keep their energy (a 0.6 px strand covers 0.6 of a pixel)
            c = c * np.minimum(1.0, (2 * rr) / 1.0) ** 0.0
            s = lum[i] + (lum[i + 1] - lum[i]) * t
            m = c > cov
            cov = np.where(m, c, cov)
            sh = np.where(m, s, sh)
            best = np.minimum(best, d)
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

    def down(self, f):
        """box filter by f (premultiplied, so transparent texels never pull the colour dark)"""
        h, w = self.h // f, self.w // f
        A = self.A.reshape(h, f, w, f).mean(axis=(1, 3))
        LA = (self.L * self.A).reshape(h, f, w, f).mean(axis=(1, 3))
        L = np.where(A > 1e-4, LA / np.maximum(A, 1e-4), self.L.reshape(h, f, w, f).mean(axis=(1, 3)))
        return L, A


def save_tex(path, L, A, lo=0.25, hi=1.0):
    L = np.clip(L, lo, hi)
    A = np.clip(A, 0, 1)
    # bleed: fully transparent texels take the mean hair tone (mips never halo)
    if (A > 0.02).any():
        mean = float((L * A).sum() / max(1e-6, A.sum()))
        L = np.where(A > 0.02, L, mean)
    g = (L * 255 + 0.5).astype(np.uint8)
    a = (A * 255 + 0.5).astype(np.uint8)
    Image.fromarray(np.dstack([g, g, g, a]), "RGBA").save(path, optimize=True)
    return path


def tex_short(size=256, seed=21, ss=4):
    """Short hair lying back from the crown (on the cap's polar UV +v points away from the crown, so the
    strands follow the natural growth: forward over the forehead, down the sides and the back).
    Three layers: a dense dark undercoat (roots, the hair's shadowed inside), the main coat of fine
    tapered hairs with a gently swirling flow, and sparse light tips. Tileable both ways."""
    W = size * ss
    cv = Canvas(W, W, tile=True, base_lum=0.42)
    rng = np.random.default_rng(seed)
    flow = pnoise(64, 64, seed + 1, fmax=3) * 0.32  # flow direction offset (rad), periodic
    dens = pnoise(64, 64, seed + 2, fmax=5) * 0.5  # clumping of the coat (subtle, small scale)
    k = W / 1024.0  # px per (1024-tile px)
    # undercoat: short dark stubs, dense
    for _ in range(int(9000 * (size / 256) ** 2)):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        ang = math.pi / 2 + pnoise_at(flow, x / W * 64, y / W * 64) + rng.normal(0, 0.45)
        L = rng.uniform(6, 16) * k
        xs = [x, x + math.cos(ang) * L]
        ys = [y, y + math.sin(ang) * L]
        g = rng.uniform(0.27, 0.4)
        cv.strand(xs, ys, [3.6 * k, 2.8 * k], [g, g + 0.05], [0.85, 0.7])
    # the coat
    n = int(12000 * (size / 256) ** 2)
    for _ in range(n):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        dd = pnoise_at(dens, x / W * 64, y / W * 64)
        if rng.random() < 0.25 * (0.5 - dd):
            continue
        ang = math.pi / 2 + pnoise_at(flow, x / W * 64, y / W * 64) + rng.normal(0, 0.22)
        L = rng.uniform(18, 46) * k
        bend = rng.normal(0, 0.25)
        m = 4
        t = np.linspace(0, 1, m)
        a = ang + bend * t
        xs = x + np.concatenate([[0], np.cumsum(np.cos(a[:-1]) * L / (m - 1))])
        ys = y + np.concatenate([[0], np.cumsum(np.sin(a[:-1]) * L / (m - 1))])
        base = rng.uniform(0.72, 1.08)
        lum = base * (0.42 + 0.5 * t ** 0.8)
        wid = (3.4 - 2.0 * t ** 1.4) * k * rng.uniform(0.85, 1.15)
        op = np.clip(0.95 - 0.35 * t ** 2, 0, 1) * rng.uniform(0.8, 1.0)
        cv.strand(xs, ys, wid, lum, op)
    # a few light, longer tips catching the light
    for _ in range(int(700 * (size / 256) ** 2)):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        ang = math.pi / 2 + pnoise_at(flow, x / W * 64, y / W * 64) + rng.normal(0, 0.3)
        L = rng.uniform(30, 60) * k
        xs = [x, x + math.cos(ang) * L * 0.5, x + math.cos(ang + 0.15) * L]
        ys = [y, y + math.sin(ang) * L * 0.5, y + math.sin(ang + 0.15) * L]
        cv.strand(xs, ys, [2.6 * k, 2.0 * k, 1.0 * k], [0.7, 0.95, 1.0], [0.8, 0.7, 0.35])
    L, A = cv.down(ss)
    A = np.clip(0.08 + A * 1.1, 0, 0.97)
    return L, A


def tex_shortcoil(size=256, seed=61, ss=4):
    """Tiny tight coils gathered into sponge-curl clusters (Kinky / Coiled / Curly short hair): each
    cluster a soft dome of interlocked coils (lit at its top, shadowed between clusters), every coil a
    small helix drawn hair by hair. Tileable both ways (clusters on a jittered periodic grid)."""
    W = size * ss
    cv = Canvas(W, W, tile=True, base_lum=0.3)
    rng = np.random.default_rng(seed)
    k = W / 1024.0
    # cluster centres on a jittered grid (periodic)
    g = 16
    cell = W / g
    cents = []
    for i in range(g):
        for j in range(g):
            cents.append(((i + 0.5 + rng.uniform(-0.3, 0.3)) * cell, (j + 0.5 + rng.uniform(-0.3, 0.3)) * cell,
                          cell * rng.uniform(0.6, 0.8)))
    cents = np.array(cents)
    # dark interlocked base (the dense inside of coily hair)
    for _ in range(int(6000 * (size / 256) ** 2)):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        r = rng.uniform(3, 7) * k
        a0 = rng.uniform(0, TAU)
        t = np.linspace(0, rng.uniform(1.0, 1.8) * TAU, 9)
        xs = x + np.cos(a0 + t) * r
        ys = y + np.sin(a0 + t) * r * 0.8 + t * r * 0.12
        cv.strand(xs, ys, np.full(9, 2.6 * k), np.full(9, rng.uniform(0.3, 0.45)), np.full(9, 0.7))
    # coils in the clusters
    for (cx, cy, cr) in cents:
        nco = int(rng.uniform(20, 30) * (cr / (cell * 0.5)) ** 2)
        for _ in range(nco):
            rr = cr * math.sqrt(rng.random())
            th = rng.uniform(0, TAU)
            x, y = cx + math.cos(th) * rr, cy + math.sin(th) * rr
            dome = math.sqrt(max(0.0, 1 - (rr / cr) ** 2))
            # light from the top of the image (up the head): the near side of each cluster brighter
            lit = 0.5 + 0.5 * (-(y - cy) / cr) * 0.6 + 0.4 * dome
            r = rng.uniform(4.5, 9) * k
            turns = rng.uniform(1.2, 2.2)
            m = int(10 * turns)
            t = np.linspace(0, turns * TAU, m)
            a0 = rng.uniform(0, TAU)
            ax = rng.uniform(0, TAU)
            along = (t / (turns * TAU) - 0.5) * r * 2.2
            xs = x + np.cos(a0 + t) * r + math.cos(ax) * along
            ys = y + np.sin(a0 + t) * r * 0.75 + math.sin(ax) * along
            front = 0.5 + 0.5 * np.sin(a0 + t)
            lum = np.clip((0.42 + 0.42 * lit * (0.6 + 0.4 * front)) * rng.uniform(0.85, 1.1), 0.25, 1.0)
            cv.strand(xs, ys, np.full(m, 2.4 * k), lum, np.full(m, 0.92))
    # fine frizz between clusters
    for _ in range(int(1500 * (size / 256) ** 2)):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        r = rng.uniform(2, 4) * k
        t = np.linspace(0, TAU * 1.5, 8)
        a0 = rng.uniform(0, TAU)
        cv.strand(x + np.cos(a0 + t) * r, y + np.sin(a0 + t) * r, np.full(8, 1.6 * k), np.full(8, 0.6), np.full(8, 0.55))
    L, A = cv.down(ss)
    # the gaps between clusters thinner than the clusters (a faded coily cut reads as coils thinning out)
    hh = A.shape[0]
    yy, xx = np.mgrid[0:hh, 0:hh] * (W / hh)
    near = np.zeros_like(A)
    for (cx, cy, cr) in cents:
        for ox in (-W, 0, W):
            for oy in (-W, 0, W):
                d2 = ((xx - cx - ox) ** 2 + (yy - cy - oy) ** 2) / (cr * cr)
                near = np.maximum(near, np.clip(1 - d2, 0, 1))
    A = np.clip((0.03 + A * 1.05) * (0.6 + 0.4 * np.sqrt(near)), 0, 0.98)
    return L, A


WAVE_RIDGES = 6  # ridges per tile along v: x TILE[1] = 24 over the cap (~1 cm apart, as the game's waveLam)


def tex_waves(size=256, seed=71, ss=4):
    """360 waves: hair brushed out from the crown (+v on the cap) lying in tight ripples. The ripples are
    bands across v (rings round the crown on the polar UV), gently chevroned along u; every strand
    snakes laterally in phase with them and its brightness follows the ridge (crests catch the light,
    troughs are dark). WAVE_RIDGES whole ridges per tile in v and whole chevrons in u: tileable."""
    W = size * ss
    cv = Canvas(W, W, tile=True, base_lum=0.3)
    rng = np.random.default_rng(seed)
    k = W / 1024.0
    lam = W / WAVE_RIDGES

    def phase(x, y):  # ridge phase (cycles) at a texel: v bands, chevroned by u (2 chevrons a tile)
        return y / lam + 0.12 * np.sin(TAU * 1 * x / W) + 0.05 * np.sin(TAU * 3 * x / W + 1.3) + 0.03 * np.sin(TAU * 7 * x / W + 0.4)

    for _ in range(int(9000 * (size / 256) ** 2)):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        L = rng.uniform(0.55, 1.2) * lam
        m = 9
        t = np.linspace(0, 1, m)
        ys = y + t * L
        ph = phase(x, ys)
        xs = x + np.sin(TAU * ph) * lam * 0.07 + t * rng.normal(0, 0.1) * lam
        crest = 0.5 + 0.5 * np.cos(TAU * ph)
        lum = np.clip((0.4 + 0.42 * crest ** 1.3) * rng.uniform(0.8, 1.15), 0.25, 1.0)
        wid = (3.0 - 1.2 * t) * k
        op = np.full(m, rng.uniform(0.75, 0.95))
        cv.strand(xs, ys, wid, lum, op)
    L, A = cv.down(ss)
    A = np.clip(0.18 + A * 0.9, 0, 0.98)  # (the dense under-layer: waves are full, never see-through)
    return L, A


CROP_STRIPS = 4


def tex_crop(w=512, h=512, seed=81, ss=2):
    """Short tufts for the crop-top cards (straight / wavy): CROP_STRIPS strips across u, each a tuft of
    fine hairs from a broad root (v = 0) converging into a few tapered points (v = 1); alpha fades at
    the root (it grows out of the shell, no visible card start), at both sides and to the tips."""
    W, H = w * ss, h * ss
    cv = Canvas(W, H, tile=False, base_lum=0.5)
    rng = np.random.default_rng(seed)
    sw = W / CROP_STRIPS
    k = H / 1024.0
    for s in range(CROP_STRIPS):
        x0 = s * sw
        npts = 2 + s % 3  # points the tuft converges into
        tips = [x0 + sw * (0.25 + 0.5 * (i + rng.uniform(0.2, 0.8)) / npts) for i in range(npts)]
        nh = 80 + 16 * s
        for _ in range(nh):
            rx = x0 + sw * (0.5 + 0.38 * rng.uniform(-1, 1) * abs(rng.uniform(-1, 1)) ** 0.3)
            tx = tips[rng.integers(npts)] + rng.normal(0, sw * 0.03)
            L = H * rng.uniform(0.6, 0.97)
            m = 10
            t = np.linspace(0, 1, m)
            pull = t ** 1.3
            xs = rx + (tx - rx) * pull * (L / H) + np.sin(t * 3 + rng.uniform(0, TAU)) * sw * 0.01
            ys = H * rng.uniform(0.0, 0.05) + t * L
            lum = np.clip(rng.uniform(0.75, 1.05) * (0.52 + 0.48 * t ** 0.7), 0.25, 1.0)
            wid = np.maximum(0.5, (2.2 - 1.5 * t ** 1.2) * k * 2) * rng.uniform(0.8, 1.2)
            op = 0.8 * np.clip(np.minimum(t / 0.28, 1) ** 1.5 * (1 - np.maximum(0, t - 0.7) / 0.3 * 0.85), 0, 1)
            cv.strand(xs, ys, wid, lum, op * rng.uniform(0.8, 1.0))
    L, A = cv.down(ss)
    hh, ww = A.shape
    u = (np.arange(ww) + 0.5) / ww * CROP_STRIPS
    fu = u - np.floor(u)
    side = np.clip(np.minimum(fu, 1 - fu) / 0.12, 0, 1)
    A = A * side[None, :]
    return L, A


def build_textures(only=None):
    os.makedirs(TEX, exist_ok=True)
    out = {}
    for key, fn in (("short", tex_short), ("shortcoil", tex_shortcoil), ("waves", tex_waves), ("crop", tex_crop)):
        if only and key not in only:
            continue
        t0 = time.time()
        L, A = fn()
        p = save_tex(os.path.join(TEX, f"hair_{key}.png"), L, A)
        out[key] = p
        print(f"texture {key}: {L.shape[1]}x{L.shape[0]} mean alpha {A.mean():.2f} ({time.time() - t0:.1f}s)")
    return out




# =============================================================================================
# Reference data: skull, hairlines, the game's coverage grids, the head mesh (BVH)
# =============================================================================================
class Ref:
    def __init__(self):
        self.sk = Skull()
        self.skf = Skull(os.path.join(REF, "skull_f.json")) if os.path.exists(os.path.join(REF, "skull_f.json")) else None
        d = self.sk.data
        self.d = d
        lines = d["hairline"]["lines"]
        self.hl = {}
        for kind, L in lines.items():
            h = np.array([[a, y] for a, y in L["height"]], np.float64)
            self.hl[kind] = h
        da = self.hl["Natural"][:, 0]
        self.hl_da = da
        self.hl_min = np.min(np.stack([np.interp(da, h[:, 0], h[:, 1]) for h in self.hl.values()]), axis=0)
        self.hl_nat = np.interp(da, self.hl["Natural"][:, 0], self.hl["Natural"][:, 1])
        fz = d["fades"]
        self.fade_top = fz["FADE_TOP"]
        self.cov = {k: np.asarray(v, np.float64) for k, v in fz["coverage"].items()}
        self.cov_th = np.radians(np.asarray(d["radial"]["thetas"], np.float64))
        self.cov_az = np.radians(np.asarray(d["radial"]["azimuths"], np.float64))
        # a blurred copy of each coverage grid (soft ramps for the shells' thickness: converge over ~4 cm)
        self.covb = {k: self._blur(v, 2.2) for k, v in self.cov.items()}
        ears = d["ears"]
        self.ears = [(np.array(ears[s]["min"]), np.array(ears[s]["max"])) for s in ("left", "right")]

    @staticmethod
    def _blur(g, sig):
        from math import exp
        r = int(sig * 3)
        k = np.array([exp(-0.5 * (i / sig) ** 2) for i in range(-r, r + 1)])
        k /= k.sum()
        # wrap in az (axis 1), clamp in theta (axis 0)
        out = np.zeros_like(g)
        for i, w in zip(range(-r, r + 1), k):
            out += w * np.roll(g, i, axis=1)
        g2 = out
        pad = np.pad(g2, ((r, r), (0, 0)), mode="edge")
        out = np.zeros_like(g2)
        for i, w in enumerate(k):
            out += w * pad[i:i + g2.shape[0]]
        return out

    def grid_at(self, g, theta, az):
        """bilinear sample of a (theta, az) grid (theta clamped, az wrapped); arrays ok"""
        th = np.clip(np.asarray(theta, np.float64), self.cov_th[0], self.cov_th[-1])
        dth = self.cov_th[1] - self.cov_th[0]
        fi = th / dth
        i0 = np.clip(np.floor(fi).astype(int), 0, len(self.cov_th) - 2)
        ti = fi - i0
        n = len(self.cov_az)
        fa = (np.asarray(az, np.float64) % TAU) / (TAU / n)
        j0 = np.floor(fa).astype(int) % n
        tj = fa - np.floor(fa)
        j1 = (j0 + 1) % n
        a = g[i0, j0] * (1 - tj) + g[i0, j1] * tj
        b = g[i0 + 1, j0] * (1 - tj) + g[i0 + 1, j1] * tj
        return a * (1 - ti) + b * ti

    @staticmethod
    def da_of(p):
        """angle from the front centre round the vertical axis x = 0, z = 0.05 (0 front .. pi back)"""
        return math.atan2(abs(p[0]), -(p[2] - 0.05))

    def inside(self, p, margin=0.0, which="min"):
        """above the hairline (of the lowest kind: min, or Natural) by -margin"""
        h = self.hl_min if which == "min" else self.hl_nat
        return p[1] > np.interp(self.da_of(p), self.hl_da, h) - margin

    def in_ear(self, p, pad=0.02):
        for lo, hi in self.ears:
            if np.all(p > lo - pad) and np.all(p < hi + pad):
                return True
        return False


def measure_fit(sk):
    """the runtime skull-fit extents on a radial table (CONTRACT: W at y 0.15 toward +X, T straight up,
    Fz at y 0.2 toward -Z, Bz at y 0.1 toward +Z, all from x = 0, z = the skull centre's z)"""
    cz = float(sk.c[2])
    cy = float(sk.c[1])

    def cross(o, dvec):
        lo, hi = 0.0, 1.6
        for _ in range(50):
            m = (lo + hi) / 2
            if sk.height(o + dvec * m) < 0:
                lo = m
            else:
                hi = m
        return (lo + hi) / 2

    W = cross(np.array([0, 0.15, cz]), np.array([1.0, 0, 0]))
    T = cy + cross(np.array([0, cy, cz]), np.array([0, 1.0, 0]))
    Fz = cz - cross(np.array([0, 0.2, cz]), np.array([0, 0, -1.0]))
    Bz = cz + cross(np.array([0, 0.1, cz]), np.array([0, 0, 1.0]))
    return W, T, Fz, Bz


def fit_map(sk_to, sk_from=None):
    W0, T0, F0, B0 = measure_fit(sk_from) if sk_from is not None else (0.383, 0.591, -0.460, 0.520)
    W, T, Fz, Bz = measure_fit(sk_to)
    return np.array([W / W0, T / T0, (Bz - Fz) / (B0 - F0)]), (Bz + Fz) / 2 - (B0 + F0) / 2


# =============================================================================================
# Blender helpers
# =============================================================================================
def bl():
    import bpy
    return bpy


def reset_blend():
    bpy = bl()
    bpy.ops.wm.read_factory_settings(use_empty=True)


def obj_from_arrays(name, P, T, coll=None):
    bpy = bl()
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, p)) for p in P], [], [tuple(map(int, t)) for t in T])
    me.update()
    ob = bpy.data.objects.new(name, me)
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


class HeadBVH:
    """the game's generated head (nominal space) as a Blender object + BVHTree"""

    def __init__(self, path, name="RefHead"):
        import render
        from mathutils.bvhtree import BVHTree
        md = render.load_obj(path)["Head"]
        P = md["p"].reshape(-1, 3)
        T = md["t"].reshape(-1, 3)
        self.P, self.T = P, T
        self.bvh = BVHTree.FromPolygons([tuple(p) for p in P], [tuple(int(i) for i in t) for t in T])
        self.centre = np.array([0, 0.15, 0.035])

    def signed(self, p):
        from mathutils import Vector
        loc, nrm, idx, dist = self.bvh.find_nearest(Vector(tuple(p)))
        if loc is None:
            return 1.0
        loc = np.array(loc)
        out = np.dot(p - loc, loc - self.centre) >= 0
        return dist if out else -dist


# =============================================================================================
# The scalp cap: rings of the polar grid laid on the skull
# =============================================================================================
def ring_segments(theta, nmax=96):
    n = int(round(nmax * math.sin(theta) / 8.0)) * 8
    return max(16, min(nmax, n))


def polar_grid(ref, theta_max=THETA_MAX, dth_deg=2.0, nmax=96):
    """vertices (theta, az, u, v) ring by ring and the triangles stitching them (pole: a fan with one pole
    vertex per segment, so every vertex has a proper u). Returns arrays th, az, U, V, T."""
    nr = int(round(math.degrees(theta_max) / dth_deg))
    thetas = np.linspace(0, theta_max, nr + 1)
    TH, AZ, UU, VV = [], [], [], []
    rings = []
    tris = []
    for i, th in enumerate(thetas):
        if i == 0:
            rings.append(None)
            continue
        n = ring_segments(th, nmax)
        idx = []
        for j in range(n + 1):
            u = j / n
            TH.append(th)
            AZ.append(u * TAU)
            UU.append(u)
            VV.append(th / theta_max)
            idx.append(len(TH) - 1)
        rings.append(idx)
    # pole fan
    r1 = rings[1]
    n1 = len(r1) - 1
    for j in range(n1):
        u = (j + 0.5) / n1
        TH.append(0.0)
        AZ.append(u * TAU)
        UU.append(u)
        VV.append(0.0)
        tris.append((len(TH) - 1, r1[j], r1[j + 1]))
    for i in range(1, len(rings) - 1):
        A, B = rings[i], rings[i + 1]
        na, nb = len(A) - 1, len(B) - 1
        a = b = 0
        while a < na or b < nb:
            if b >= nb or (a < na and (a + 1) / na <= (b + 1) / nb):
                tris.append((A[a], B[b], A[a + 1]))
                a += 1
            else:
                tris.append((A[a], B[b], B[b + 1]))
                b += 1
    return (np.array(TH), np.array(AZ), np.array(UU), np.array(VV), np.array(tris, np.int64))


def orient_outward(P, T, centre):
    T = T.copy()
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    n = np.cross(b - a, c - a)
    out = (a + b + c) / 3 - centre
    flip = np.einsum("ij,ij->i", n, out) < 0
    T[flip] = T[flip][:, [0, 2, 1]]
    return T


def compact(keep_tris, *arrays):
    """drop unused vertices: returns remapped tris and the arrays reindexed"""
    used = np.unique(keep_tris.ravel())
    remap = -np.ones(max(len(arrays[0]), used.max() + 1), np.int64)
    remap[used] = np.arange(len(used))
    return remap[keep_tris], [a[used] for a in arrays]


class CapBase:
    """the cap's grid on this skull: scalp points, normals, UVs, and which part of it is hair region
    (every hairline kind, plus a margin) and clear of the face and the ears"""

    def __init__(self, ref, head, dth=2.0, nmax=96, fit=None):
        sk = ref.sk
        self.fit = fit  # (scale, dz, female skull): layers also keep CLEAR above the fitted female scalp
        th, az, U, V, T = polar_grid(ref, dth_deg=dth, nmax=nmax)
        n = len(th)
        S = np.array([sk.point(th[i], az[i], 0.0) for i in range(n)])
        N = np.array([sk.normal(max(th[i], 0.02), az[i]) for i in range(n)])
        D = np.array([Skull.direction(th[i], az[i]) for i in range(n)])  # radial unit
        R = np.array([sk.radius(th[i], az[i]) for i in range(n)])
        # hair region: above the lowest hairline of any kind, dilated by 0.03 studs over the surface
        ins = np.array([ref.inside(S[i], 0.0) for i in range(n)])
        dist = np.full(n, 9.0)
        Si = S[ins]
        for k in range(0, n, 512):
            blk = S[k:k + 512]
            dd = np.sqrt(((blk[:, None, :] - Si[None, :, :]) ** 2).sum(-1)).min(1)
            dist[k:k + 512] = dd
        dist[ins] = 0.0
        ok = dist < 0.034
        ear = np.array([ref.in_ear(S[i] + D[i] * CAP_OFF, 0.012) for i in range(n)])
        ok &= ~ear
        keepT = T[ok[T].all(axis=1)]
        self.th, self.az, self.U, self.V = th, az, U, V
        self.S, self.N, self.D, self.R = S, N, D, R
        self.T_all = T
        self.ok = ok
        self.keepT = keepT
        self.ref, self.head = ref, head
        # coverage (game's Kit.Cut grids, blurred) at each vertex
        self.cov = {k: ref.grid_at(g, th, az) for k, g in ref.covb.items()}
        self.cov_sharp = {k: ref.grid_at(g, th, az) for k, g in ref.cov.items()}
        # soft edge factor: 0 at the natural hairline, 1 ~4 cm inside (shells converge there)
        self.edge = np.clip((self.cov["none"] - 0.6) / 0.35, 0, 1) ** 1.2 * np.clip(self.cov_sharp["none"], 0, 1)
        # zero on the kept region's border (the shells always end on the cap, never cut off mid-air), eased in
        n_all = len(th)
        kept_v = np.zeros(n_all, bool)
        kept_v[keepT.ravel()] = True
        dropT = T[~ok[T].all(axis=1)]
        border = np.zeros(n_all, bool)
        border[dropT.ravel()] = True
        border &= kept_v
        bd = S[border]
        dist_b = np.full(n_all, 9.0)
        for k in range(0, n_all, 512):
            blk = S[k:k + 512]
            dist_b[k:k + 512] = np.sqrt(((blk[:, None, :] - bd[None, :, :]) ** 2).sum(-1)).min(1)
        self.edge *= np.clip(dist_b / 0.035, 0, 1) ** 1.5

    def layer(self, off, T=None):
        """positions at off above the skull, pushed out to the head mesh clearance"""
        P = self.S + self.D * np.asarray(off).reshape(-1, 1)
        idx = np.unique((self.keepT if T is None else T).ravel())
        for i in idx:
            for _ in range(4):
                s = self.head.signed(P[i])
                if s >= CLEAR + 0.0005:
                    break
                P[i] = P[i] + self.D[i] * (CLEAR + 0.001 - s)
            if self.fit is not None:
                fs, fdz, skf = self.fit
                for _ in range(3):
                    hf = skf.height(P[i] * fs + np.array([0, 0, fdz]))
                    if hf >= CLEAR + 0.0003:
                        break
                    P[i] = P[i] + self.D[i] * (CLEAR + 0.0006 - hf) / float(np.dot(np.abs(self.D[i]), fs))
        return P


def build_cap(cb):
    """the shared HairCap piece: the polar grid at CAP_OFF, trimmed to the hair region (Blender mesh)"""
    bpy = bl()
    P = cb.layer(np.full(len(cb.S), CAP_OFF))
    T = orient_outward(P, cb.keepT, cb.ref.sk.c)
    T2, (P2, N2, U2, V2) = compact(T, P, cb.N, cb.U, cb.V)
    ob = obj_from_arrays("HairCap", P2, T2)
    piece = Piece("HairCap", "cap", material="Plastic", castShadow=True)
    occ = 0.86
    for i in range(len(P2)):
        piece.vert(P2[i], N2[i], (U2[i], V2[i]), (occ, occ, occ, 1.0))
    for t in T2:
        piece.T.append(tuple(int(x) for x in t))
    return piece, ob


# =============================================================================================
# Shells (tex "cap"): fur layers over the region a style keeps longer, thinning to the cap at the edges
# =============================================================================================
SHELL_STEP = 0.008


def thickness(cb, spec):
    """thickness above the cap per vertex for a style spec:
    side = extra over the whole kept region (cov of the kind), top = the crop top over its region"""
    kind = spec["kind"]
    covk = cb.cov[kind]
    side_w = np.clip((covk - 0.55) / 0.4, 0, 1)
    y = cb.S[:, 1]
    if spec.get("top_region") == "all":
        top_w = np.clip((cb.cov["none"] - 0.5) / 0.45, 0, 1)
    elif kind == "burst":
        top_w = np.clip((covk - 0.6) / 0.35, 0, 1) * np.array([smoothstep(-0.05, 0.18, yy) for yy in y])
    else:
        ft = spec["fade_top"]
        top_w = np.array([smoothstep(ft - 0.07, ft + 0.08, yy) for yy in y])
    t = cb.edge * (spec["side"] * side_w + (spec["top"] - spec["side"]) * top_w * side_w)
    return t


def build_shells(cb, spec, name="HairTop", tufts=0.006, lean=0.0035, seed=5):
    """shell k sits at CAP_OFF + min(t, k * step) and exists where t > (k - 1) * step: each shell ends
    where it meets the one below (no step at any edge). A Displace modifier (Clouds) raises tufts on the
    outer shells, coherent through the stack (global coordinates), weighted by a vertex group."""
    bpy = bl()
    t = thickness(cb, spec)
    tmax = float(t.max())
    nsh = int(math.ceil(tmax / SHELL_STEP - 0.15))
    pieces, obs = [], []
    tex = bpy.data.textures.get("TuftNoise") or bpy.data.textures.new("TuftNoise", "CLOUDS")
    tex.noise_scale = 0.045
    tex.noise_depth = 2
    tex.noise_basis = "BLENDER_ORIGINAL"
    tex.intensity = 1.0
    tex.contrast = 1.4
    for k in range(1, nsh + 1):
        dk = k * SHELL_STEP
        # each shell ends on an irregular contour (a dithered threshold): a natural density variation, never a
        # line following the grid
        from mathutils import Vector, noise as mnoise
        dith = np.array([mnoise.noise(Vector(tuple(x * 40.0 + k * 7.7))) for x in cb.S])
        lo = (k - 1) * SHELL_STEP + 0.0008 + dith * SHELL_STEP * 0.7 * (k > 1)
        T = cb.keepT[(t[cb.keepT] > lo[cb.keepT]).any(axis=1)]
        if len(T) == 0:
            break
        h = CAP_OFF + np.minimum(t, dk)
        P = cb.layer(h, T)
        T = orient_outward(P, T, cb.ref.sk.c)
        T2, (P2, N2, U2, V2, t2, D2) = compact(T, P, cb.N, cb.U, cb.V, t, cb.D)
        nm = f"{name}{k}" if nsh > 1 else name
        ob = obj_from_arrays(nm, P2, T2)
        # vertex group: how much this shell's tufts may rise (0 at its edge, more on the outer shells)
        vg = ob.vertex_groups.new(name="tuft")
        frac = np.clip((t2 - (k - 1) * SHELL_STEP) / SHELL_STEP, 0, 1) * (k / max(1, nsh)) * np.clip(t2 / max(1e-6, tmax), 0, 1)
        # (the pole's duplicated vertices, one per segment, must move together: no tufts right at the crown)
        th2 = np.array([Skull.angles(x - cb.ref.sk.c)[0] for x in P2])
        frac = frac * np.clip((th2 - 0.04) / 0.08, 0, 1)
        for i, w in enumerate(frac):
            vg.add([i], float(w), "REPLACE")
        mod = ob.modifiers.new("Tufts", "DISPLACE")
        mod.texture = tex
        mod.texture_coords = "GLOBAL"
        mod.direction = "NORMAL"
        mod.mid_level = 0.0  # outward only: never below the clearance
        mod.strength = tufts
        mod.vertex_group = "tuft"
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        PE = np.array([v.co[:] for v in me.vertices])
        ev.to_mesh_clear()
        assert len(PE) == len(P2)
        occ = 0.62 + 0.38 * (k / max(1, nsh))
        piece = Piece(nm, "cap", material=spec.get("material", "Plastic"), castShadow=False)
        from mathutils import Vector, noise as mnoise
        for i in range(len(PE)):
            # clumpy shading: the normals wander (hair's specular breaks up, no smooth helmet highlight) and the
            # occlusion varies by clump, both coherent through the stack (same noise in global space)
            q = Vector(tuple(PE[i] * 70.0))
            nv = np.array(mnoise.noise_vector(q))
            wn = 0.18 * float(np.clip(t2[i] / max(1e-6, tmax), 0, 1))
            nn = N2[i] + nv * wn
            c = occ * (0.86 + 0.14 * (0.5 + 0.5 * mnoise.noise(Vector(tuple(PE[i] * 14.0 + 3.1)))))
            piece.vert(PE[i], nn, (U2[i], V2[i] - lean * k * min(1.0, V2[i] / 0.05)), (c, c, c, 1.0))
        for tt in T2:
            piece.T.append(tuple(int(x) for x in tt))
        pieces.append(piece)
        obs.append(ob)
    return pieces, obs, t


# =============================================================================================
# Crop-top cards (straight / wavy): short tufts combed forward over the top, laid on guide curves
# =============================================================================================
def surface_frame(sk, p):
    th, az = Skull.angles(p - sk.c)
    th = max(th, 0.03)
    n = sk.normal(th, az)
    return th, az, n


def build_crop(cb, spec, t_field, seed=11, name="HairCrop"):
    """tufts rooted inside the shell volume, rising a little (lift) and lying along the comb flow
    (forward over the top, down at the back of the crown, out at the sides); tips never cross the
    front hairline. Guides are Bezier splines in one Blender curve object (resolution 3), evaluated
    to 4 points each; a card strip is swept along every guide."""
    bpy = bl()
    ref, sk = cb.ref, cb.ref.sk
    rng = np.random.default_rng(seed)
    # candidate roots: vertices of the kept grid where the top is thick, jittered
    tt = t_field
    cand = np.where((tt > spec["top"] * 0.8) & cb.ok)[0]

    def t_at(q):
        j = int(np.argmin(((cb.S - q) ** 2).sum(1)))
        return tt[j]
    nwant = int(spec.get("cards", 420) * 1.05)
    roots = []
    tries = 0
    while len(roots) < nwant and tries < nwant * 20:
        tries += 1
        i = int(rng.choice(cand))
        th = cb.th[i] + rng.normal(0, 0.012)
        az = cb.az[i] + rng.normal(0, 0.03)
        p = sk.point(th, az, 0.0)
        roots.append((th, az, p, tt[i]))
    guides = []
    for (th, az, p, ti) in roots:
        # comb flow at the root: forward (toward -Z) projected on the tangent plane, blended into the
        # growth direction (+theta, away from the crown) behind the crown
        n = sk.normal(max(th, 0.03), az)
        fwd = np.array([0, 0, -1.0]) - n * (-n[2])
        fwd = fwd / (np.linalg.norm(fwd) + 1e-9)
        grow = sk.point(th + 0.02, az, 0.0) - p
        grow = grow / (np.linalg.norm(grow) + 1e-9)
        wb = smoothstep(0.05, 0.3, p[2]) * smoothstep(0.62, 0.35, p[1])  # behind / below the crown
        if th < 0.12:
            wb = 0.0
        flow = fwd * (1 - wb) + grow * wb
        flow = flow - n * np.dot(flow, n)
        flow = flow / (np.linalg.norm(flow) + 1e-9)
        # a little swirl and scatter
        side = np.cross(n, flow)
        flow = flow + side * rng.normal(0, 0.28)
        flow /= np.linalg.norm(flow)
        L = rng.uniform(0.045, 0.075)
        top_h = CAP_OFF + ti + rng.uniform(0.001, 0.007)
        root_h = CAP_OFF + rng.uniform(0.45, 0.75) * ti
        # march over the scalp along the flow
        pts = []
        q = p.copy()
        ok = True
        ns = 3
        for s in range(ns + 1):
            f = s / ns
            th_q, az_q, nq = surface_frame(sk, q)
            hq = root_h + (top_h - root_h) * math.sin(min(1.0, f * 1.6) * math.pi / 2) - 0.004 * f * f
            pq = sk.point(th_q, az_q, hq)
            pts.append(pq)
            if s < ns:
                fl = flow - nq * np.dot(flow, nq)
                fl /= np.linalg.norm(fl) + 1e-9
                q = sk.point(*Skull.angles(q + fl * L / ns - sk.c), 0.0)
        tip = pts[-1]
        # keep the face clear: the tip stays inside the natural hairline by 1.5 cm; tips may hang into the
        # fade only a little
        if not ref.inside(tip, -0.03, which="min"):
            ok = False
        # tips stay over the full top (a tuft hanging over the fade's top line reads as a fringe of spikes)
        if t_at(tip) < spec["top"] * 0.6 or t_at(pts[1]) < spec["top"] * 0.6:
            ok = False
        if ok:
            guides.append((np.array(pts), n, ti))
    # Blender guide curve: one Bezier spline per tuft, handles from the marched points
    cu = bpy.data.curves.new(name + "Guides", "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 3
    for pts, n, ti in guides:
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(1)
        a, b = sp.bezier_points[0], sp.bezier_points[1]
        a.co = tuple(pts[0])
        b.co = tuple(pts[-1])
        a.handle_left = tuple(pts[0] - (pts[1] - pts[0]))
        a.handle_right = tuple(pts[1])
        b.handle_left = tuple(pts[2])
        b.handle_right = tuple(pts[-1] + (pts[-1] - pts[2]))
    gob = bpy.data.objects.new(name + "Guides", cu)
    bpy.context.scene.collection.objects.link(gob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = gob.evaluated_get(dg).to_mesh()
    EP = np.array([v.co[:] for v in me.vertices])
    gob.evaluated_get(dg).to_mesh_clear()
    per = len(EP) // max(1, len(guides))
    piece = Piece(name, "crop", material="SmoothPlastic", castShadow=False)
    # inner (lower) tufts first: Roblox sorts per part, so the triangle order is the depth order inside it
    order = sorted(range(len(guides)), key=lambda g: guides[g][2] * 0 + float(EP[g * per:(g + 1) * per][:, 1].mean() * 0 + np.mean([sk.height(x) for x in EP[g * per:(g + 1) * per]])))
    for g in order:
        pts = EP[g * per:(g + 1) * per]
        if len(pts) < 2:
            continue
        # clearance on the evaluated curve
        for i in range(len(pts)):
            h = sk.height(pts[i])
            if h < CLEAR + 0.002:
                d = pts[i] - sk.c
                pts[i] = pts[i] + d / np.linalg.norm(d) * (CLEAR + 0.002 - h)
        ups = []
        for x in pts:
            th, az = Skull.angles(x - sk.c)
            ups.append(sk.normal(max(th, 0.03), az))
        w0 = rng.uniform(0.02, 0.03)
        widths = [w0 * (1.0 - 0.35 * (i / (len(pts) - 1)) ** 1.5) for i in range(len(pts))]
        s = int(rng.integers(CROP_STRIPS))
        strip = (s / CROP_STRIPS, (s + 1) / CROP_STRIPS)
        base = rng.uniform(0.8, 0.9)
        piece.card(list(pts), widths, ups, strip, shade=lambda t, b=base: (b + (1 - b) * t,) * 3,
                   twist=[rng.normal(0, 0.12)] * len(pts))
    return piece, gob, len(guides)


# =============================================================================================
# Styles
# =============================================================================================
STRAIGHT = ["Straight", "Wavy"]
CURLY = ["Curly", "Kinky", "Coiled"]
STAND_C = 1.3  # curly / coily hair stands further off the scalp at the same clipper length (AnatomyHair STAND)

# key, Looks.HairStyles ids, coverage kind, fade top (y), side extra, top extra (studs above the cap)
FAMILY = [
    ("buzz", ["Buzz Cut"], "none", None, 0.004, 0.004, "all"),
    ("waves360", ["360 Waves"], "none", None, 0.007, 0.007, "all"),
    ("fade_low", ["Low Fade"], "low", 0.15, 0.0, 0.026, None),
    ("fade_mid", ["Fade", "Mid Fade"], "mid", 0.24, 0.0, 0.026, None),
    ("fade_high", ["High Fade"], "high", 0.32, 0.0, 0.028, None),
    ("fade_taper", ["Taper Fade"], "taper", 0.12, 0.006, 0.026, None),
    ("fade_burst", ["Burst Fade"], "burst", 0.25, 0.005, 0.03, None),
    ("crew", ["Crew Cut"], "none", 0.2, 0.006, 0.03, None),
    ("caesar", ["Caesar Cut"], "none", None, 0.01, 0.02, "all"),
]


def entries():
    """style entries: clipper cuts (buzz, waves) are one entry for every type; the cuts with a crop top
    split straight / wavy (shells + combed tuft cards) from curly / coily (thicker shells only: the
    painted coil tile is the texture)"""
    out = []
    for key, styles, kind, ft, side, top, region in FAMILY:
        base = dict(kind=kind, fade_top=ft, side=side, top=top, top_region=region)
        if region == "all" and key in ("buzz", "waves360"):
            e = dict(base, key=key, styles=styles, types=None, cards=0, material="Plastic")
            if key == "waves360":
                e["capTile"] = "waves"
            out.append(e)
            continue
        out.append(dict(base, key=key, styles=styles, types=STRAIGHT, cards=420 if region != "all" else 520,
                        material="SmoothPlastic"))
        out.append(dict(base, key=key + "_c", styles=styles, types=CURLY, cards=0, side=side * STAND_C,
                        top=top * STAND_C, material="Plastic"))
    return out


# =============================================================================================
# Clearance
# =============================================================================================
class Clearance:
    def __init__(self, ref):
        self.ref = ref
        self.head_m = HeadBVH(os.path.join(REF, "head_m.obj"))
        self.head_f = HeadBVH(os.path.join(REF, "head_f.obj")) if os.path.exists(os.path.join(REF, "head_f.obj")) else None
        if ref.skf is not None:
            self.fit_s, self.fit_dz = fit_map(ref.skf)
        self.narrow = np.array([0.965, 1.0, 1.0])

    def measure(self, pieces):
        sk, skf = self.ref.sk, self.ref.skf
        r = {"skull_m": 9.0, "head_m": 9.0, "skull_f_fit": 9.0, "head_f_fit": 9.0, "skull_m_narrow_nofit": 9.0}
        for p in pieces:
            P = np.asarray(p.P)
            if len(P) > 4000:
                P = P[:: max(1, len(P) // 4000)]
            r["skull_m"] = min(r["skull_m"], min(sk.height(x) for x in P))
            r["head_m"] = min(r["head_m"], min(self.head_m.signed(x) for x in P))
            if skf is not None:
                Pf = P * self.fit_s + np.array([0, 0, self.fit_dz])
                r["skull_f_fit"] = min(r["skull_f_fit"], min(skf.height(x) for x in Pf))
                if self.head_f:
                    r["head_f_fit"] = min(r["head_f_fit"], min(self.head_f.signed(x) for x in Pf))
            # the female skull approximated as the male one 0.965x narrower, the mesh fitted by ax = 0.965
            # (the runtime fit): heights are the male's scaled; unfitted (worst case) the mesh is wider: more
            # clearance. Report the fitted figure on the narrowed skull.
            Pn = P * self.narrow
            sn = [np.linalg.norm((x - sk.c) / self.narrow) for x in Pn]
            r["skull_m_narrow_nofit"] = min(r["skull_m_narrow_nofit"], min(
                float(np.linalg.norm(x - sk.c) - np.linalg.norm(
                    (sk.point(*Skull.angles((x - sk.c) / self.narrow)) - sk.c) * self.narrow)) for x in Pn))
            del sn
        return {k: round(float(v), 4) for k, v in r.items()}


# =============================================================================================
# Self-check renders: the runtime cap texture emulated (tile x coverage), Cycles via render.py
# =============================================================================================
HAIR_TINTS = {
    "black": (0.09, 0.08, 0.075),
    "darkbrown": (48 / 255, 33 / 255, 24 / 255),
    "blonde": (196 / 255, 156 / 255, 92 / 255),
}
# cap density per style for the emulation (AnatomyHair SHORT density; coily hair 1.18x)
DENSITY = {"buzz": 0.62, "waves360": 0.9}


def paint_cap(ref, kind, tile_key, density, size=1024, out=None):
    """HK.PaintCap in numpy: the tile repeated TILE times over the cap UV, alpha = tile alpha x coverage
    (skull.json's Kit.Cut grid for the kind, at each texel's polar angles), greyscale kept (the renderer
    multiplies the tint)"""
    tile = np.asarray(Image.open(os.path.join(TEX, f"hair_{tile_key}.png")).convert("RGBA"), np.float64) / 255
    th_, tw_ = tile.shape[:2]
    j, i = np.mgrid[0:size, 0:size]
    u = (i + 0.5) / size
    v = (j + 0.5) / size
    cov = ref.grid_at(ref.cov[kind], v * THETA_MAX, u * TAU) * density
    tu = ((u * TILE[0] * tw_) % tw_).astype(int)
    tv = ((v * TILE[1] * th_) % th_).astype(int)
    g = tile[tv, tu, 0]
    a = tile[tv, tu, 3] * np.clip(cov, 0, 1)
    img = np.dstack([g, g, g, a])
    out = out or os.path.join(FAM_DIR, f"cap_{kind}_{tile_key}.png")
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(out)
    return out


def matte(ob):
    """Roblox Plastic / SmoothPlastic on short hair: a soft, low sheen (render.py's hair material is tuned for
    long glossy cards). Preview-only: a copy of the material per object."""
    m = ob.data.materials[0]
    if not m.name.endswith("#matte"):
        m2 = m.copy()
        m2.name = m.name[:50] + "#matte"
        ob.data.materials[0] = m2
        m = m2
    bs = m.node_tree.nodes["Principled BSDF"]
    bs.inputs["Roughness"].default_value = 0.8
    bs.inputs["Specular IOR Level"].default_value = 0.12
    try:
        bs.inputs["Anisotropic"].default_value = 0.0
    except KeyError:
        pass


def render_style(ref, e, pieces, capP, tint_name, views, res=(520, 620), samples=48, tag="", head="head_m"):
    import render
    tint = HAIR_TINTS[tint_name]
    curly = e["types"] == CURLY
    tile_key = e.get("capTile") or ("shortcoil" if curly else "short")
    dens = DENSITY.get(e["key"], 1.0) * (1.18 if curly and e["key"] in DENSITY else 1.0)
    capimg = paint_cap(ref, e["kind"], tile_key, min(1.0, dens))
    out = []
    for view in views:
        sc = render.Scene(res=res, samples=samples)
        render.add_obj(sc, os.path.join(REF, f"{head}.obj"))
        matte(sc.add_piece(capP, texture=capimg, tint=tint))
        for p in pieces:
            tex = capimg if p.tex == "cap" else os.path.join(TEX, f"hair_{p.tex}.png")
            ob = sc.add_piece(p, texture=tex, tint=tint)
            matte(ob)
        fn = os.path.join(FAM_DIR, f"{e['key']}{tag}_{tint_name}_{view if isinstance(view, str) else 'close'}.png")
        if view == "close":
            sc.render(fn, view="front", dist=1.75, focus=(0.0, 0.3, 0.0))
        else:
            sc.render(fn, view=view)
        out.append(fn)
    return out


# =============================================================================================
# Main
# =============================================================================================
def save_blend(key):
    bpy = bl()
    os.makedirs(BLEND, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, f"{key}.blend"), compress=True)


def clean_out(key):
    """this family's own output folder only: stale meshes from an earlier run never reach publish.py"""
    d = os.path.join(hairlib.OUT, key)
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith(".mesh") or f == "style.json":
                os.remove(os.path.join(d, f))


def add_head_obj(head):
    ob = obj_from_arrays("RefHead (game head, nominal)", head.P, head.T)
    return ob


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--quick", action="store_true", help="renders: small, few samples, 34 + close only")
    ap.add_argument("--only", default="")
    ap.add_argument("--skip-textures", action="store_true")
    ap.add_argument("--views", default="")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    only = set(filter(None, args.only.split(",")))
    t0 = time.time()
    if not args.skip_textures:
        build_textures()
    ref = Ref()
    head = HeadBVH(os.path.join(REF, "head_m.obj"))
    clr = Clearance(ref)
    fit = (clr.fit_s, clr.fit_dz, ref.skf) if ref.skf is not None else None
    cb = CapBase(ref, head, fit=fit)
    cbs = CapBase(ref, head, dth=2.5, nmax=72, fit=fit)  # the shells' coarser grid (same UV mapping)
    print(f"cap grid: {len(cb.S)} verts, {len(cb.keepT)} tris kept of {len(cb.T_all)} ({time.time() - t0:.1f}s)")

    # ---- the shared cap
    reset_blend()
    add_head_obj(head)
    capP, _ = build_cap(cb)
    cl = clr.measure([capP])
    clean_out("cap")
    hairlib.export_style("cap", {
        "styles": [], "types": None, "thetaMax": round(THETA_MAX, 5), "tile": TILE,
        "tiles": {"default": "short", "Curly": "shortcoil", "Kinky": "shortcoil", "Coiled": "shortcoil"},
        "clearance": cl,
        "notes": "shared scalp cap: polar UV u = az / 2pi (az 0 at the back, toward +X), v = theta / thetaMax",
    }, [capP])
    save_blend("cap")
    print(f"cap: {capP.nv} verts {capP.nt} tris clearance {cl}")
    report = {"cap": {"tris": capP.nt, "clearance": cl}}
    built = []

    for e in entries():
        if only and e["key"] not in only and e["key"].replace("_c", "") not in only:
            continue
        t1 = time.time()
        reset_blend()
        add_head_obj(head)
        capob = obj_from_arrays("HairCap (shared cap, out/cap)", np.asarray(capP.P), np.asarray(capP.T))
        capob.hide_render = False
        spec = dict(e)
        name = "HairFur" if e["top_region"] == "all" and e["key"] in ("buzz", "waves360") else "HairTop"
        pieces, obs, tfield = build_shells(cbs, spec, name=name, tufts=0.0015 if name == "HairFur" else 0.006)
        if e.get("cards"):
            crop, gob, ng = build_crop(cbs, spec, tfield, seed=hash(e["key"]) % 1000 if False else 11 + len(e["key"]))
            if crop.nt:
                pieces.append(crop)
        assert len(pieces) <= 16
        cl = clr.measure(pieces)
        entry = {
            "styles": e["styles"], "types": e["types"], "cap": {"cut": "style", "density": 1},
            "clearance": cl, "family": "fades",
        }
        if e.get("capTile"):
            entry["capTile"] = e["capTile"]
        for p in pieces:
            if p.tex == "cap":
                p.meta["material"] = e["material"]
        clean_out(e["key"])
        data = hairlib.export_style(e["key"], entry, pieces)
        save_blend(e["key"])
        report[e["key"]] = {"tris": data["tris"], "pieces": {p.name: p.nt for p in pieces}, "clearance": cl}
        print(f"{e['key']}: {len(pieces)} pieces, {data['tris']} tris, clearance {cl} ({time.time() - t1:.1f}s)")
        built.append((e, pieces))

    print(f"build done in {time.time() - t0:.1f}s")
    if not args.render:
        return report
    os.makedirs(FAM_DIR, exist_ok=True)
    import render
    tints = ["black", "darkbrown", "blonde"]
    views = args.views.split(",") if args.views else (["34", "close"] if args.quick else ["34", "side", "back", "close", "top34"])
    res, samples = ((300, 360), 16) if args.quick else ((520, 620), 48)
    sheets = []
    for n, (e, pieces) in enumerate(built):
        tint = tints[n % len(tints)]
        paths = render_style(ref, e, pieces, capP, tint, views, res=res, samples=samples)
        lab = [f"{v}" for v in views]
        out = os.path.join(FAM_DIR, f"sheet_{e['key']}.jpg")
        render.sheet(paths, out, cols=len(paths), labels=lab,
                     title=f"{e['key']}: {', '.join(e['styles'])} [{'/'.join(e['types']) if e['types'] else 'all types'}] "
                           f"{sum(p.nt for p in pieces)} tris, {tint}")
        sheets.append(out)
        print("sheet", out)
    return report


if __name__ == "__main__":
    rep = main()
    print(json.dumps(rep, indent=1))
