"""Long family hair: "Long Hair" for the Straight and Wavy hair types (two entries: "long" for Straight, "long_wavy"
for Wavy). Modelled in Blender (bpy 4.2), exported with hairlib.

    /opt/bpyenv/bin/python tools/hair/build_long.py [--render DIR] [--only long,long_wavy] [--no-tex]
                                                    [--samples N] [--views 34,side] [--looks f_brown]

Writes tools/hair/textures/hair_straight.png, tools/hair/out/<key>/ (meshes + style.json) and
tools/hair/blend/<key>.blend; with --render, Cycles self-check renders and a sheet per style.

How the hair is built (game nominal head space, numerically; see CONTRACT.md):
* Texture "straight" (owned here): 1024 x 1024, four 256-px strips (dense clump, medium, wispy flyaway, wavy).
  Every strip is drawn strand by strand at 2x and filtered down: long continuous strands from the root (v = 0)
  to tapered, staggered, transparent tips (v = 1), gathered into natural clumps that tighten toward the tips,
  root darkening, a darker under-fill inside the dense strips (the deeper hair), alpha falling to zero at both
  strip edges (no card borders) and colour bled into the transparent texels (mip-friendly).
* Guides: every card is a guide strand. Its scalp part is a spline through waypoints - its root on a subtle
  centre parting (the front ones run just inside the natural hairline), the temple, over the top of the ear
  and down to a release line behind the ears and round the back of the head - projected on the default
  skull at the layer's height. Its hanging part is relaxed by a position-based simulation (gravity,
  inextensible segments, bending stiffness, collisions against the skull table and the head mesh, the ear
  boxes and BOTH torso meshes - male and female - through Blender BVH trees; the back curtain drifts back
  over the trapezius onto the upper back, the side locks forward in front of the shoulders). The relaxed
  guides are kept in the .blend as curve objects.
* Cards: strips along the guides (4 layers: a dense scalp layer, two main layers, an outer layer of finer
  locks and flyaways), wider down the hanging part, outward-facing shading normals, built as Blender meshes
  with per-corner UVs and colours. A Displace modifier (Clouds noise, vertex-group weighted off on the
  scalp) breaks the hanging curtain into clumps; the Wavy entry adds S-waves to the guides and uses the wavy
  strip outside. The evaluated meshes come back as the game pieces; clearance is then enforced against the
  head mesh and the skull table (also at the female fit and 0.965x narrow). Soft occlusion is baked into
  the vertex colours with BVH ray casts (hair, head, torso) times a per-layer shade.
* Pieces: static HairTop (everything over the head) and swinging chains split from the same cards: the back
  curtain in 4 chains and a side lock each side (seg 1 below the anchor, seg 2 'b' from the shoulders down),
  hairfx swing, length "hang", hideUnder hood. Triangles of every piece are emitted innermost layer first.
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
from PIL import Image, ImageFilter  # noqa: E402

TEX_DIR = os.path.join(HERE, "textures")
BLEND_DIR = os.path.join(HERE, "blend")
TEX_KEY = "straight"
TEX_PATH = os.path.join(TEX_DIR, f"hair_{TEX_KEY}.png")
TAU = 2 * math.pi
TEX_SIZE = 1024
STRIPS = {"dense": (0.0, 0.25), "medium": (0.25, 0.5), "wispy": (0.5, 0.75), "wavy": (0.75, 1.0)}


# =========================================================================================== texture
def _box1(a, r, axis):
    """box blur of radius r along axis (edge-clamped), via cumulative sums"""
    if r < 1:
        return a
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def _blur(a, sigma):
    """~gaussian blur (three box passes per axis)"""
    if sigma <= 0.3:
        return a
    r = max(1, int(round(sigma * 0.9)))
    out = a.astype(np.float32)
    for _ in range(3):
        out = _box1(out, r, 0)
        out = _box1(out, r, 1)
    return out


def _smoothn(n, rng, k=5):
    """smooth 1d noise (n samples, unit-ish amplitude)"""
    g = rng.normal(0, 1, k + 3)
    x = np.linspace(0, k, n)
    i = np.floor(x).astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    return g[i] * (1 - f) + g[i + 1] * f


class Canvas:
    """greyscale + alpha, 'over' compositing of anti-aliased near-vertical strands (one x per row)"""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.lum = np.zeros((h, w), np.float32)
        self.alp = np.zeros((h, w), np.float32)

    def strand(self, ys, xs, wid, shade, op, x_lo, x_hi):
        """ys: integer rows (increasing), xs: float centre per row, wid/shade/op per row"""
        m = (ys >= 0) & (ys < self.h)
        ys, xs, wid, shade, op = ys[m], xs[m], wid[m], shade[m], op[m]
        if len(ys) == 0:
            return
        r = np.maximum(0.5, wid * 0.5)
        R = int(np.ceil(r.max())) + 1
        base = np.floor(xs).astype(np.int64)
        for k in range(-R, R + 1):
            px = base + k
            d = np.abs(px + 0.5 - xs)
            cov = np.clip(r + 0.5 - d, 0, 1) * op
            ok = (cov > 0) & (px >= x_lo) & (px < x_hi)
            if not ok.any():
                continue
            yy, xx, c, s = ys[ok], px[ok], cov[ok], shade[ok]
            self.lum[yy, xx] = s * c + self.lum[yy, xx] * (1 - c)
            self.alp[yy, xx] = c + self.alp[yy, xx] * (1 - c)


def _strip(w, h, seed, n_strands, n_clumps, width_px, clump_k, fill, len_min, wave_amp=0.0, wave_per=0.0,
           stray=0.03, shade_lo=0.5, edge=0.09, tip_spread=0.25, root_dark=0.3, clump_lo=0.75, spread=0.5, root_soft=0.07):
    """one card strip (w x h at 2x), roots at the top. Returns lum, alpha (0..1)."""
    rng = np.random.default_rng(seed)
    cv = Canvas(w, h)
    margin = edge * w
    # clump centre lines: evenly spread with jitter, meandering a little
    cx = (np.arange(n_clumps) + 0.5) / n_clumps
    cx = margin + (w - 2 * margin) * np.clip(cx + rng.normal(0, 0.25 / n_clumps, n_clumps), 0.02, 0.98)
    rows = np.arange(h)
    tt = rows / (h - 1)
    clump_lines = []
    wave_ph = rng.uniform(0, TAU)
    for c in range(n_clumps):
        mean = cx[c] + _smoothn(h, rng, 4) * w * 0.025
        if wave_amp:
            ph = wave_ph + rng.normal(0, 0.35)
            amp = wave_amp * w * rng.uniform(0.8, 1.2) * np.clip(tt / 0.12, 0, 1)
            mean = mean + amp * np.sin(ph + tt * TAU * wave_per)
        clump_lines.append(mean)
    clump_lines = np.array(clump_lines)
    clump_len = rng.uniform(clump_lo, 1.0, n_clumps)  # each clump's tip ends at its own length
    clump_len[rng.integers(n_clumps)] = 1.0
    for k in range(n_strands):
        c = int(rng.integers(n_clumps))
        # roots spread over the strip, thinning toward its edges (a ragged edge made of strands, not a cut)
        x0 = w * 0.5 + (w * 0.5 - margin) * float(np.clip(rng.normal(0, spread), -1.15, 1.15))
        y0 = int(h * root_soft * rng.uniform(0.0, 1.0) ** 2.2)  # staggered roots: a soft root edge
        lmax = clump_len[c]
        L = rng.uniform(len_min, 1.0) ** 0.6 * lmax  # most strands reach near the tip
        y1 = int(h * min(1.0, L))
        if y1 - y0 < 16:
            continue
        ys = rows[y0:y1]
        t = (ys - y0) / max(1, (h - 1 - y0))
        # gathered into the clump toward the tip; a few strays leave it
        kc = clump_k * np.clip(t * 1.2, 0, 1) ** 2.2
        tgt = clump_lines[c][ys] + rng.normal(0, 1) * w * 0.012 * (1 - t * 0.6)
        xs = x0 * (1 - kc) + tgt * kc + _smoothn(len(ys), rng, 6) * w * 0.006
        if wave_amp:
            xs = xs + (clump_lines[c][ys] - clump_lines[c][ys].mean()) * (1 - kc) * 0.85
        if rng.random() < stray:
            xs = xs + (t ** 2.2) * rng.normal(0, 0.18) * w
        xs = np.clip(xs, margin * 0.55, w - margin * 0.55)
        # tapered, staggered tip
        tl = (ys - y0) / max(1, y1 - y0)
        tip = np.clip((1 - tl) / tip_spread, 0, 1)
        wid = width_px * rng.uniform(0.75, 1.3) * (0.35 + 0.65 * tip ** 0.7)
        base = rng.uniform(shade_lo, 1.0)
        shade = base * (1 - root_dark * (1 - np.clip(t / 0.15, 0, 1)) ** 2) * (0.92 + 0.08 * _smoothn(len(ys), rng, 3))
        if wave_amp:
            # crests catch the light: brighten where the strand runs straight down
            slope = np.gradient(xs) if len(xs) > 2 else np.zeros_like(xs)
            shade = shade * (0.9 + 0.18 * np.exp(-(slope * 3.0) ** 2))
        op = rng.uniform(0.65, 1.0) * np.clip(tip / 0.45, 0, 1) ** 0.8 * np.clip((ys - y0) / (0.02 * h), 0.25, 1)
        cv.strand(ys, xs, wid, shade, op, 0, w)
    lum, alp = cv.lum, cv.alp
    if fill > 0:
        # the deeper hair under the strands: a darker blurred body, strongest in the clump cores
        body = _blur(alp, w * 0.02)
        uu = (np.arange(w) + 0.5) / w
        core = np.exp(-((uu - 0.5) / 0.2) ** 2)[None, :]
        body = np.clip(body * 1.25, 0, 1) ** 2 * fill * core
        bl = 0.42 + 0.25 * _blur(lum, w * 0.02) / np.maximum(_blur(alp, w * 0.02), 1e-3)
        lum = lum * alp + bl * body * (1 - alp)
        alp = alp + body * (1 - alp)
        lum = lum / np.maximum(alp, 1e-4)
    # edges: alpha to zero toward both strip edges (no card border)
    u = (np.arange(w) + 0.5) / w
    eu = np.clip(np.minimum(u, 1 - u) / edge, 0, 1)
    eu = eu * eu * (3 - 2 * eu)
    alp = alp * eu[None, :]
    # the very root row fades in (a card's root edge never shows a line)
    ev = np.clip(tt / 0.012, 0, 1)
    alp = alp * ev[:, None]
    return lum, alp


def _bleed(lum, alp, passes=6):
    """colour pushed into the transparent texels (mip levels do not halo dark or bright)"""
    w = alp.copy()
    l = lum * w
    out = lum.copy()
    for i in range(passes):
        r = 2 ** i
        bw = _blur(w, r)
        bl = _blur(l, r)
        fillv = bl / np.maximum(bw, 1e-5)
        m = (alp < 0.5) & (bw > 1e-4)
        k = np.clip(1 - alp * 2, 0, 1)
        out = np.where(m, out * (1 - k) + fillv * k, out)
    return out


def make_texture(path, size=TEX_SIZE, seed=1101, report=False):
    ss = 2  # drawn at 2x, box-filtered down
    W, H = size * ss, size * ss
    sw = W // 4
    specs = {
        # dense clump: the bulk of every layer; nearly opaque inside, strands breaking out at the edges and tips
        "dense": dict(n_strands=int(sw * 0.5), spread=0.42, n_clumps=7, width_px=2.6, clump_k=0.8, fill=0.85, len_min=0.55, clump_lo=0.72,
                      stray=0.03, shade_lo=0.62, edge=0.10, tip_spread=0.3),
        # medium: a lighter lock (gaps between clumps; the layer under it shows through)
        "medium": dict(n_strands=int(sw * 0.3), spread=0.45, n_clumps=6, width_px=2.4, clump_k=0.85, fill=0.35, len_min=0.45, clump_lo=0.65, root_soft=0.11,
                       stray=0.05, shade_lo=0.5, edge=0.12, tip_spread=0.32),
        # wispy flyaways: a few loose strands, staggered lengths
        "wispy": dict(n_strands=int(sw * 0.12), n_clumps=4, width_px=2.0, clump_k=0.35, fill=0.0, len_min=0.3,
                      stray=0.35, shade_lo=0.6, edge=0.14, tip_spread=0.5),
        # wavy: dense clumps on broad S-waves (2.5 waves root to tip), crests lighter
        "wavy": dict(n_strands=int(sw * 0.48), spread=0.42, n_clumps=6, width_px=2.6, clump_k=0.75, fill=0.7, len_min=0.55, clump_lo=0.75,
                     wave_amp=0.075, wave_per=2.5, stray=0.04, shade_lo=0.55, edge=0.13, tip_spread=0.3),
    }
    lum = np.zeros((H, W), np.float32)
    alp = np.zeros((H, W), np.float32)
    for i, (name, sp) in enumerate(specs.items()):
        l, a = _strip(sw, H, seed + 17 * i, **sp)
        lum[:, i * sw:(i + 1) * sw] = l
        alp[:, i * sw:(i + 1) * sw] = a
    # box filter to the final size (premultiplied)
    pl = (lum * alp).reshape(size, ss, size, ss).mean((1, 3))
    a = alp.reshape(size, ss, size, ss).mean((1, 3))
    l = pl / np.maximum(a, 1e-5)
    l = _bleed(l, a)
    l = np.clip(0.25 + 0.75 * np.clip(l, 0, 1), 0.25, 1.0)
    g = (l * 255 + 0.5).astype(np.uint8)
    A = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    if report:
        q = size // 4
        for i, name in enumerate(specs):
            prof = a[int(size * 0.3):int(size * 0.6), i * q:(i + 1) * q].mean(0)
            print(name, " ".join(f"{x:.2f}" for x in prof[::16]))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.dstack([g, g, g, A]), "RGBA").save(path, optimize=True)
    return path




# =========================================================================================== reference
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import hairlib as hl  # noqa: E402

REF = hl.REF
SK = hl.Skull()
C = SK.c.copy()
SKD = SK.data
SKF_PATH = os.path.join(REF, "skull_f.json")
SKF = hl.Skull(SKF_PATH) if os.path.exists(SKF_PATH) else None
EARS = [(np.array(SKD["ears"][s]["min"]), np.array(SKD["ears"][s]["max"])) for s in ("left", "right")]
FIT0 = dict(W=0.383, T=0.591, Fz=-0.460, Bz=0.520)  # HairAssetData fit0 (the default male skull)
CLEAR_MIN = 0.0215  # every vertex over the head at least this far above the head mesh and the skull tables
EAR_CLEAR = 0.022
AXIS_Z = 0.04  # the neck / body's vertical axis (x = 0, z = AXIS_Z)


def smooth(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


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


def signed(bvh, p, maxd):
    """(nearest point, outward unit direction, signed distance) or None beyond maxd"""
    loc, n, _i, d = bvh.find_nearest(Vector(p), maxd)
    if loc is None:
        return None
    q = np.array(loc)
    nn = np.array(n)
    v = np.asarray(p) - q
    s = float(np.dot(v, nn))
    if d > 1e-7 and s >= 0:
        return q, v / d, d
    return q, nn, (-d if s < 0 else d)


class Ref:
    """the game's head (ears left out: thin shells give wrong inside / outside answers behind them; the ear boxes
    keep hair away from them) and upper torso, as BVH trees"""

    def __init__(self, sex):
        P, F = load_obj_mesh(os.path.join(REF, f"head_{sex}.obj"), "Head")
        sk = SKD
        if sex == "f" and SKF is not None:
            sk = SKF.data
        ears = [(np.array(sk["ears"][s]["min"]) - 0.012, np.array(sk["ears"][s]["max"]) + 0.012)
                for s in ("left", "right")]
        keep = [t for t in F if not any(np.all((P[list(t)] > lo) & (P[list(t)] < hi)) for lo, hi in ears)]
        self.headP, self.headF = P, F
        self.head = BVHTree.FromPolygons([tuple(p) for p in P], keep)
        Pt, Ft = load_obj_mesh(os.path.join(REF, f"torso_{sex}.obj"), "UpperTorso")
        self.torsoP, self.torsoF = Pt, Ft
        self.torso = BVHTree.FromPolygons([tuple(p) for p in Pt], Ft)

    def height(self, p):
        r = signed(self.head, p, 1.0)
        return r[2] if r else 9.0


def fit_of(sk):
    def plane_point(az, y_target):
        best = None
        for th in np.linspace(0.3, 2.6, 900):
            p = sk.point(th, math.radians(az))
            if best is None or abs(p[1] - y_target) < abs(best[1] - y_target):
                best = p
        return best
    return dict(W=plane_point(90, 0.15)[0], T=sk.c[1] + sk.radius(0.0, 0.0), Fz=plane_point(180, 0.2)[2],
                Bz=plane_point(0, 0.1)[2])


def female_fit():
    """the runtime skull fit (CONTRACT) that carries the pieces onto the default female skull"""
    if SKF is None:
        return dict(ax=0.965, ay=1.0, az=1.0, dz=0.0)
    ff = fit_of(SKF)
    return dict(ax=ff["W"] / FIT0["W"], ay=ff["T"] / FIT0["T"], az=(ff["Bz"] - ff["Fz"]) / (FIT0["Bz"] - FIT0["Fz"]),
                dz=(ff["Bz"] + ff["Fz"]) / 2 - (FIT0["Bz"] + FIT0["Fz"]) / 2)


FIT_F = female_fit()


def apply_fit(P, fit):
    return np.asarray(P) * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]


def skull_radius_v(sk, th, az):
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


def polar(P, c):
    d = np.atleast_2d(P) - c
    r = np.linalg.norm(d, axis=1)
    th = np.arccos(np.clip(d[:, 1] / np.maximum(r, 1e-9), -1, 1))
    az = np.arctan2(d[:, 0], d[:, 2]) % TAU
    return d, r, th, az


def skull_height_v(sk, P):
    _d, r, th, az = polar(P, sk.c)
    return r - skull_radius_v(sk, th, az), th


def skull_push_v(P, off, th_max=2.55):
    """points pushed out radially to at least off above the male skull table and (through the female fit) the
    female one"""
    P = np.atleast_2d(np.asarray(P, dtype=np.float64))
    off = np.broadcast_to(np.asarray(off, dtype=np.float64), (len(P),))
    d, r, th, az = polar(P, C)
    need = skull_radius_v(SK, th, az) + off
    if SKF is not None:
        q = apply_fit(P, FIT_F)
        _dq, rq, thq, azq = polar(q, SKF.c)
        deficit = skull_radius_v(SKF, thq, azq) + off - rq
        need = np.where(thq <= th_max, np.maximum(need, r + deficit), need)
    m = (th <= th_max) & (r < need) & (r > 1e-6)
    out = P.copy()
    out[m] = C + d[m] / r[m, None] * need[m, None]
    return out


def ear_push(p, grow):
    """p pushed out of both ear boxes grown by grow (up, back, forward or outward: the nearest face)"""
    for lo, hi in EARS:
        lo2, hi2 = lo - grow, hi + grow
        if np.all(p > lo2) and np.all(p < hi2):
            side = 1.0 if lo[0] > 0 else -1.0
            cands = [(hi2[1] - p[1], 1, hi2[1]), (hi2[2] - p[2], 2, hi2[2]), (p[2] - lo2[2], 2, lo2[2])]
            cands.append((hi2[0] - p[0], 0, hi2[0]) if side > 0 else (p[0] - lo2[0], 0, lo2[0]))
            _d, ax, val = min(cands)
            p = p.copy()
            p[ax] = val
    return p


# ------------------------------------------------------------------------------------------- hairline
def _hairline(kind="Natural"):
    ln = SKD["hairline"]["lines"][kind]
    pts = [e[1:4] for side in ("right", "left") for e in ln[side] if e and len(e) >= 4]
    hgt = np.array([e for e in ln["height"] if e], dtype=np.float64)
    return np.array(pts, dtype=np.float64), hgt


HL_PTS, HL_H = _hairline()


def da_of(P):
    P = np.atleast_2d(P)
    return np.arctan2(np.abs(P[:, 0]), 0.05 - P[:, 2])


def hairline_y(P):
    return np.interp(da_of(P), HL_H[:, 0], HL_H[:, 1])


def scalp_of(P):
    d, _r, th, az = polar(P, C)
    r = skull_radius_v(SK, th, az)
    return C + unit(d) * r[:, None]


def edge_dist(P):
    """signed distance (studs) from the scalp point under P to the natural hairline: + inside the hair"""
    s = scalp_of(P)
    dd = np.sqrt(((s[:, None, :] - HL_PTS[None, :, :]) ** 2).sum(-1)).min(1)
    inside = s[:, 1] - hairline_y(s)
    return np.where(inside >= 0, dd, -dd)


def theta_at(az, f_ok, lo=0.02, hi=2.55):
    """the largest polar angle at azimuth az (rad) where f_ok(scalp point) still holds (bisection; f_ok true
    near the top of the head)"""
    for _ in range(36):
        m = (lo + hi) / 2
        if f_ok(SK.point(m, az)):
            lo = m
        else:
            hi = m
    return lo


# =========================================================================================== styles
# layers, innermost first: (name, strands per side, offset above the scalp, strips {strip: weight}, hairline margin,
# tip y (at length 0.5) and its spread, card width at the root / over the head / hanging, shade)
LAYERS = [
    # the hairline layer: rooted along the front hairline (temple to centre), sweeping with the front hair; its
    # front edge (wispy / medium strips) is the soft hairline
    dict(name="edge", n=7, off=0.03, strips={"medium": 0.6, "wispy": 0.4}, margin=0.028, tip=-1.2, tip_var=0.06,
         w=(0.05, 0.085, 0.1), shade=0.97, phase=0.0, rel=(0.03, 0.0), root="hairline", fmax=0.22),
    dict(name="scalp", n=15, off=0.025, strips={"dense": 1.0}, margin=0.06, tip=-1.12, tip_var=0.05,
         w=(0.065, 0.14, 0.12), shade=0.93, phase=0.0, rel=(0.0, -0.12)),
    dict(name="inner", n=14, off=0.037, strips={"dense": 0.85, "medium": 0.15}, margin=0.055, tip=-1.30,
         tip_var=0.06, w=(0.065, 0.13, 0.125), shade=0.96, phase=0.37, rel=(0.025, -0.02)),
    dict(name="main", n=14, off=0.05, strips={"dense": 0.7, "medium": 0.3}, margin=0.05, tip=-1.42,
         tip_var=0.07, w=(0.06, 0.125, 0.125), shade=0.98, phase=0.71, rel=(0.04, 0.06)),
    dict(name="outer", n=11, off=0.063, strips={"dense": 0.4, "medium": 0.6}, margin=0.05, tip=-1.36,
         tip_var=0.12, w=(0.055, 0.11, 0.11), shade=1.0, phase=0.19, rel=(0.05, 0.1)),
]
FLYAWAYS = dict(n=7, off=0.072, strip="wispy", w=(0.03, 0.05), len=(0.2, 0.4), shade=1.0)

STYLES = {
    "long": dict(entry=dict(styles=["Long Hair"], types=["Straight"], cap={"cut": "full", "density": 1}),
                 wavy=False, volume=1.0, seed=7),
    "long_wavy": dict(entry=dict(styles=["Long Hair"], types=["Wavy"], cap={"cut": "full", "density": 1}),
                      wavy=True, volume=1.15, seed=8),
}

PSI_FRONT = 1.125  # part angle (from +Y toward the face) just inside the front hairline
PSI_BACK = -0.32  # the part's back end, behind the crown
PART_X = 0.006  # the subtle centre parting: roots this far either side of x = 0
F_SIDE = 0.24  # strands with f below this fall forward as the side locks
ANCHOR_Y = {"back": -0.14, "side": -0.22}  # hanging chains start here (their pivot height)
SEG2_Y = {"back": -0.80, "side": -0.74}  # and the second segment from here (the shoulders)
CHAINS = ["HairClump01", "HairClump02", "HairClump03", "HairClump04", "HairClump05", "HairClump06"]
HAIRLINE_CARDS = False  # short locks rooted across the hairline (off: the edge layer makes the hairline)
HAIRFX = dict(stiff=0.3, mass=1.0, mass2=0.8)


def part_point(psi, side):
    d = np.array([0.0, math.cos(psi), -math.sin(psi)])
    p = C + d * SK.radius(*SK.angles(d))
    p[0] = side * PART_X
    return scalp_of(p)[0]


def release_point(f, side, rel):
    """where a strand leaves the head: behind the ear (f = 0) round the back to the centre (f = 1), at the layer's
    heights rel = (behind the ear, back centre): the outer layers leave near the widest part of the head and fall
    straight, the inner ones follow the skull further under the occiput"""
    az = side * math.radians(56.0) * (1 - f) ** 1.15
    y = rel[0] + (rel[1] - rel[0]) * f
    th = theta_at(az, lambda p: p[1] > y)
    return SK.point(th, az)


def scalp_path(f, side, layer, vol, rng, n=48):
    """the strand's path over the scalp (points ON the skull, then lifted by offs): a great circle from its root
    on the parting to its release point, kept a margin inside the natural hairline and above the ear"""
    if layer.get("root") == "hairline":
        # on the hairline at da (temple .. front centre), just inside it
        da_r = 0.8 * (1 - f / layer["fmax"]) + 0.02
        hp = HL_PTS[np.sign(HL_PTS[:, 0]) == side] if side > 0 else HL_PTS[HL_PTS[:, 0] <= 0]
        dd = da_of(hp)
        o = np.argsort(dd)
        hp, dd = hp[o], dd[o]
        h = np.array([np.interp(da_r, dd, hp[:, k]) for k in range(3)])
        th, az = SK.angles(h - C)
        R = SK.point(theta_at(az, lambda q: edge_dist(q[None])[0] >= layer["margin"], hi=th + 0.05), az)
        Q = release_point(f * 0.6, side, layer["rel"])
    else:
        R = part_point(PSI_FRONT + (PSI_BACK - PSI_FRONT) * f, side)
        Q = release_point(f, side, layer["rel"])
    a, b = unit(R - C), unit(Q - C)
    om = math.acos(float(np.clip(np.dot(a, b), -1, 1)))
    t = np.linspace(0, 1, n)
    D = (np.sin((1 - t) * om)[:, None] * a + np.sin(t * om)[:, None] * b) / math.sin(om)
    hw = layer["w"][1] * 0.5
    margin = layer["margin"]
    for _it in range(4):
        _d, _r, th, az = polar(C + D, C)
        P = C + D * skull_radius_v(SK, th, az)[:, None]
        for i in range(1, n - 1):
            p = P[i]
            # inside the hairline by the margin (the front strands run along it: their front edge is the hairline)
            if edge_dist(p[None])[0] < margin:
                th_i = theta_at(az[i], lambda q: edge_dist(q[None])[0] >= margin, lo=0.02, hi=th[i])
                p = SK.point(th_i, az[i])
            # above the ear: its box top + clearance + the card's half width (the card lies near vertical there)
            if side * p[0] > 0.2 and -0.02 < p[2] < 0.31:
                ytop = EARS[0][1][1] + EAR_CLEAR + hw * 0.9 + 0.012
                k = smooth(0.31, 0.24, p[2]) * smooth(-0.02, 0.06, p[2])
                ylim = 0.02 + (ytop - 0.02) * k
                if p[1] < ylim:
                    th_i = theta_at(az[i], lambda q: q[1] >= ylim, lo=0.02, hi=th[i])
                    p = SK.point(th_i, az[i])
            P[i] = p
        # relax (keep the ends): no kinks where the guards bent the path
        D = unit(P - C)
        for _s in range(3):
            D[1:-1] = unit(D[1:-1] * 0.5 + (D[:-2] + D[2:]) * 0.25)
    _d, _r, th, az = polar(C + D, C)
    P = C + D * skull_radius_v(SK, th, az)[:, None]
    # heights: rising out of the parting and the hairline, fuller over the crown
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    ed = edge_dist(P)
    base = 0.0225
    tgt = layer["off"] * vol * (1 + 0.55 * smooth(0.25, 0.56, P[:, 1]))
    ramp = np.minimum(smooth(0.0, 0.12, s), smooth(0.0, 0.11, ed))
    off = base + (tgt - base) * ramp
    Pn = C + unit(P - C) * (np.linalg.norm(P - C, axis=1) + off)[:, None]
    return Pn, off, s


# =========================================================================================== guides
class Strand:
    __slots__ = ("side", "f", "layer", "li", "scalp", "off", "hang", "tip_y", "lock", "strip", "mirror", "v0",
                 "seed", "G", "s_rel", "wave_ph", "body_off", "w", "fly", "vend", "shade")

    def __init__(self, **kw):
        for k in self.__slots__:
            setattr(self, k, kw.get(k))
        if self.vend is None:
            self.vend = 1.0


def pick(rng, weights):
    keys = list(weights)
    p = np.array([weights[k] for k in keys], dtype=np.float64)
    return keys[int(rng.choice(len(keys), p=p / p.sum()))]


def make_strands(cfg, log):
    rng = np.random.default_rng(cfg["seed"])
    vol = cfg["volume"]
    out = []
    for li, L in enumerate(LAYERS):
        n = L["n"]
        for side in (1, -1):
            for i in range(n):
                f = (i + 0.5 + L["phase"] * 0.8 + rng.uniform(-0.18, 0.18)) / (n + 0.4)
                f = float(np.clip(f, 0.0, 1.0)) * L.get("fmax", 1.0)
                P, off, _s = scalp_path(f, side, L, vol, rng)
                lock = f < F_SIDE
                # the hem: a soft U at the back (the centre longest), the side locks a little shorter
                tip = L["tip"] - 0.05 * f - (0.0 if not lock else -0.04) + rng.uniform(-1, 1) * L["tip_var"]
                strip = pick(rng, L["strips"])
                if cfg["wavy"] and strip in ("dense", "medium") and li >= 1 and rng.random() < 0.75:
                    strip = "wavy"
                out.append(Strand(side=side, f=f, layer=L["name"], li=li, scalp=P, off=off, tip_y=tip, lock=lock,
                                  strip=strip, mirror=bool(rng.random() < 0.5), v0=float(rng.uniform(0, 0.05)),
                                  seed=int(rng.integers(1 << 30)), wave_ph=float(f * 2.2 + li * 0.5 + rng.normal(0, 0.25)),
                                  body_off=0.03 + 0.016 * li, w=L["w"], fly=False))
    log(f"  {len(out)} strands")
    return out


class Sim:
    """position-based dynamics on the hanging parts (N chains of M points, the first pinned at the release
    point): gravity, inextensible segments, bending stiffness, collisions against the skull tables, the head
    mesh (jaw, neck), both torsos and the ear boxes, and the drape bias (back curtain back, side locks forward)"""

    def __init__(self, refs, X, seg, off, body_off, lock, side):
        self.refs = refs
        self.X = X.copy()
        self.Xp = X.copy()
        self.X0 = X.copy()
        self.seg = seg
        self.off = off
        self.body_off = body_off
        self.lock = lock
        self.side = side

    def constraints(self, k=4):
        X = self.X
        for _ in range(k):
            d = X[:, 1:] - X[:, :-1]
            ln = np.linalg.norm(d, axis=2, keepdims=True)
            corr = (1 - self.seg[:, None, None] / np.maximum(ln, 1e-9)) * d * 0.5
            X[:, :-1] += corr
            X[:, 1:] -= corr
            X[:, 0] = self.X0[:, 0]
            # bending: keep every other point at least ~2 seg * 0.97 apart (a soft, mostly straight strand)
            d2 = X[:, 2:] - X[:, :-2]
            l2 = np.linalg.norm(d2, axis=2, keepdims=True)
            c = np.minimum(0, l2 - 2 * self.seg[:, None, None] * 0.97) / np.maximum(l2, 1e-9) * d2 * 0.25
            X[:, :-2] += c
            X[:, 2:] -= c
            X[:, 0] = self.X0[:, 0]

    def collide(self):
        X = self.X
        N, M, _ = X.shape
        P = X.reshape(-1, 3)
        offs = np.repeat(self.off, M)
        bo = np.repeat(self.body_off, M)
        P[:] = skull_push_v(P, offs)
        for idx in range(len(P)):
            p = P[idx]
            if p[1] < 0.2:
                for ref in self.refs:
                    r = signed(ref.head, p, offs[idx] + 0.06)
                    if r is not None and r[2] < offs[idx]:
                        p = r[0] + r[1] * offs[idx]
            if p[1] < -0.45:
                for ref in self.refs:
                    r = signed(ref.torso, p, bo[idx] + 0.06)
                    if r is not None and r[2] < bo[idx]:
                        p = r[0] + r[1] * bo[idx]
            if -0.35 < p[1] < 0.15 and abs(p[0]) > 0.2:
                p = ear_push(p, EAR_CLEAR + 0.01)
            P[idx] = p
        X[:] = P.reshape(N, M, 3)
        X[:, 0] = self.X0[:, 0]

    def run(self, iters, log=None):
        lock = self.lock[:, None]
        side = self.side[:, None]
        for it in range(iters):
            V = (self.X - self.Xp) * 0.9
            self.Xp = self.X.copy()
            self.X += V
            self.X[:, :, 1] -= 0.0018
            y = self.X[:, :, 1]
            # side locks: forward round the neck, in front of the shoulder (x ~ 0.47, z ~ -0.3)
            # (only once on the shoulder: from behind the ear the lock falls straight, then over the shoulder top)
            pull = lock & (y < -0.62)
            k = np.where(pull, 0.012 * smooth(-0.62, -0.9, y), 0.0)
            self.X[:, :, 2] += k * (self.tz[:, None] - self.X[:, :, 2])
            self.X[:, :, 0] += k * (side * self.tx[:, None] - self.X[:, :, 0]) * 0.5
            self.X[:, 0] = self.X0[:, 0]
            self.constraints()
            if it % 2 == 0 or it > iters - 10:
                self.collide()
        for _ in range(4):
            self.constraints(2)
            self.collide()
        return self.X


def chain_smooth(X, passes=2, k=0.3):
    X = X.copy()
    for _ in range(passes):
        Y = X.copy()
        Y[:, 1:-1] = X[:, 1:-1] * (1 - k) + (X[:, :-2] + X[:, 2:]) * (k / 2)
        X = Y
    return X


def hang_strands(strands, refs, cfg, log, M=30):
    """the hanging parts: from each release point straight down, relaxed by the simulation"""
    N = len(strands)
    X = np.zeros((N, M, 3))
    seg = np.zeros(N)
    off = np.zeros(N)
    body = np.zeros(N)
    for i, st in enumerate(strands):
        Q = st.scalp[-1]
        L = (Q[1] - st.tip_y) * 1.12 + 0.05
        seg[i] = L / (M - 1)
        off[i] = st.off[-1]
        body[i] = st.body_off * cfg["volume"]
        out = unit(np.array([Q[0], 0.0, Q[2] - AXIS_Z]))
        for j in range(M):
            X[i, j] = Q + np.array([0, -1.0, 0]) * seg[i] * j + out * 0.02 * j * seg[i]
    lock = np.array([st.lock for st in strands])
    side = np.array([float(st.side) for st in strands])
    sim = Sim(refs, X, seg, off, body, lock, side)
    # the side locks spread over the front of the shoulder (each its own drape target)
    rs = np.random.default_rng(cfg["seed"] + 3)
    sim.tx = np.array([0.36 + 0.26 * (st.f / F_SIDE) + rs.uniform(-0.04, 0.04) for st in strands])
    sim.tz = np.array([-0.2 - 0.14 * (1 - st.f / F_SIDE) + rs.uniform(-0.04, 0.04) for st in strands])
    t0 = time.time()
    Xs = sim.run(120)
    Xs = chain_smooth(Xs, 2, 0.3)
    sim.X = Xs
    sim.collide()
    log(f"  hanging sim {N} x {M}: {time.time() - t0:.1f}s")
    for i, st in enumerate(strands):
        H = sim.X[i]
        # cut at the strand's tip height (where the drape is longer than it hangs, the full length)
        below = np.nonzero(H[:, 1] < st.tip_y)[0]
        if len(below):
            j = int(below[0])
            a, b = H[j - 1], H[j]
            t = (a[1] - st.tip_y) / max(1e-9, a[1] - b[1])
            H = np.vstack([H[:j], a + (b - a) * t])
        st.hang = H
        st.s_rel = None
    return strands


def collide_pts(P, off, body_off, refs, head=True):
    """points out of the skull tables, the head meshes, both torsos and the ear boxes"""
    P = skull_push_v(P, off)
    off = np.broadcast_to(np.asarray(off, dtype=np.float64), (len(P),))
    body_off = np.broadcast_to(np.asarray(body_off, dtype=np.float64), (len(P),))
    for idx in range(len(P)):
        p = P[idx]
        if head and p[1] < 0.2:
            for ref in refs:
                r = signed(ref.head, p, off[idx] + 0.06)
                if r is not None and r[2] < off[idx]:
                    p = r[0] + r[1] * off[idx]
        if p[1] < -0.45:
            for ref in refs:
                r = signed(ref.torso, p, body_off[idx] + 0.06)
                if r is not None and r[2] < body_off[idx]:
                    p = r[0] + r[1] * body_off[idx]
        if -0.35 < p[1] < 0.15 and abs(p[0]) > 0.2:
            p = ear_push(p, EAR_CLEAR + 0.01)
        P[idx] = p
    return P


def densify(P, sub=4):
    """Catmull-Rom through P -> (dense points, arc length at each)"""
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
    s = np.atleast_1d(s)
    return np.stack([np.interp(s, S, D[:, k]) for k in range(3)], -1)


def finish_guides(strands, refs, cfg, log):
    """scalp part + hanging part = the guide; the Wavy entry's broad S-waves down the hanging part"""
    for st in strands:
        G = np.vstack([st.scalp, st.hang[1:]])
        s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(G, axis=0), axis=1))])
        st.s_rel = float(s[len(st.scalp) - 1])
        if cfg["wavy"]:
            sh = np.maximum(0, s - st.s_rel)
            amp = 0.03 * smooth(0.03, 0.3, sh) * (1 + 0.15 * math.sin(st.seed % 97))
            T = unit(np.gradient(G, axis=0))
            out = unit(np.stack([G[:, 0], np.zeros(len(G)), G[:, 2] - AXIS_Z], 1))
            lat = unit(np.cross(T, out))
            ph = TAU * sh / 0.34 + st.wave_ph
            G = G + (np.sin(ph)[:, None] * lat * 0.85 + np.cos(ph)[:, None] * out * 0.4) * amp[:, None]
            m = sh > 0
            G[m] = collide_pts(G[m], st.off[-1], st.body_off * cfg["volume"], refs)
        st.G = G
    return strands


def card_rows(st, cfg):
    """sample the guide into card rows (arc lengths), with rows forced at the chain splits; returns a dict"""
    D, S = densify(st.G, 4)
    L = float(S[-1])
    kind = "side" if st.lock else "back"
    splits = {}
    for nm, yv in (("a", ANCHOR_Y[kind]), ("b", SEG2_Y[kind])):
        j = np.nonzero((D[:, 1] < yv) & (S > st.s_rel))[0]
        if len(j) and not st.fly:
            j = int(j[0])
            t = (D[j - 1, 1] - yv) / max(1e-9, D[j - 1, 1] - D[j, 1])
            splits[nm] = float(S[j - 1] + (S[j] - S[j - 1]) * t)
    # rows: finer where the guide bends (turning per stud), coarse down the straight hanging part
    Tn = unit(np.gradient(D, axis=0))
    ang = np.arccos(np.clip((Tn[1:] * Tn[:-1]).sum(1), -1, 1))
    kap = np.concatenate([[0], ang / np.maximum(np.diff(S), 1e-6)])
    kap = np.convolve(kap, np.ones(7) / 7, mode="same")
    hmin_hang, hmax_hang = (0.075, 0.085) if cfg["wavy"] else (0.035, 0.13)
    rows = [0.0]
    s = 0.0
    while s < L - 1e-6:
        k = float(np.interp(s, S, kap))
        hmin, hmax = (0.045, 0.085) if s < st.s_rel else (hmin_hang, hmax_hang)
        h = float(np.clip(0.22 / max(k, 1e-6), hmin, hmax))
        if s < 0.1:
            h = min(h, 0.04)
        s = min(L, s + h)
        if L - s < 0.02:
            s = L
        rows.append(s)
    for v in splits.values():
        j = int(np.argmin(np.abs(np.array(rows) - v)))
        if 0 < j < len(rows) - 1:
            rows[j] = v
        else:
            rows.append(v)
    rows = np.array(sorted(set(round(x, 7) for x in rows)))
    P = at_s(D, S, rows)
    idx = {nm: int(np.argmin(np.abs(rows - v))) for nm, v in splits.items()}
    return dict(s=rows, P=P, L=L, split=idx, kind=kind)


def chain_of(st, p_anchor):
    if st.lock:
        return CHAINS[4] if st.side < 0 else CHAINS[5]
    az = math.degrees(math.atan2(p_anchor[0], p_anchor[2] - AXIS_Z))
    if az < -24:
        return CHAINS[0]
    if az < 0:
        return CHAINS[1]
    if az < 24:
        return CHAINS[2]
    return CHAINS[3]


class Card:
    """one card: rows of (left, right) vertices with normals, uvs, hang weights; split into piece segments"""

    def __init__(self, st, rows, rng):
        s, P, L = rows["s"], rows["P"], rows["L"]
        n = len(s)
        T = unit(np.gradient(P, axis=0))
        rad = unit(P - C)
        hor = unit(np.stack([P[:, 0], np.zeros(n), P[:, 2] - AXIS_Z], 1))
        b = smooth(st.s_rel - 0.05, st.s_rel + 0.25, s) if not st.fly else np.zeros(n)
        nout = unit(rad * (1 - b)[:, None] + hor * b[:, None])
        side = unit(np.cross(T, nout))
        face = unit(np.cross(side, T))
        tw = rng.uniform(-0.4, 0.4) * smooth(st.s_rel, st.s_rel + 0.5, s) if not st.fly else np.zeros(n)
        side = unit(side * np.cos(tw)[:, None] + face * np.sin(tw)[:, None])
        face = unit(np.cross(side, T))
        face = np.where((face * nout).sum(1, keepdims=True) < 0, -face, face)
        w0, w1, w2 = st.w
        w = w0 + (w1 - w0) * smooth(0.0, 0.22, s)
        if not st.fly:
            if st.lock:
                w2 = w2 * 1.3  # the side locks: fuller clumps over the front of the shoulder
            w = w + (w2 - w1) * smooth(st.s_rel - 0.1, st.s_rel + 0.3, s)
        w = w * (1 - 0.25 * smooth(L * 0.7, L, s)) * rng.uniform(0.92, 1.08)
        hw = w * 0.5
        self.st = st
        self.n = n
        self.left = P - side * hw[:, None]
        self.right = P + side * hw[:, None]
        # over the scalp each vertex keeps its own height: a card edge running near the hairline dips to the
        # scalp there (the hair mass thins into the hairline instead of ending in a lifted card edge)
        sc = s < st.s_rel + 1e-6
        if sc.any() and st.off is not None:
            ss = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(st.scalp, axis=0), axis=1))])
            row_off = np.interp(s[sc], ss, st.off)
            for E in (self.left, self.right):
                Pe = E[sc]
                ed = edge_dist(Pe)
                oe = np.minimum(row_off, 0.0225 + (row_off - 0.0225) * smooth(0.0, 0.09, ed))
                oe = np.maximum(oe, 0.0225)
                _d, _r, th, az = polar(Pe, C)
                E[sc] = C + unit(Pe - C) * (skull_radius_v(SK, th, az) + oe)[:, None]
        # shading normals: outward from the head (one soft volume over the scalp), a little of the card's own
        # facing down the hanging part (the locks catch the light separately there)
        kf = 0.3 * b
        self.N = unit(face * kf[:, None] + nout * (1 - kf)[:, None])
        self.nout = nout
        u0, u1 = STRIPS[st.strip]
        if st.mirror:
            u0, u1 = u1, u0
        self.u = (u0, u1)
        self.v = st.v0 + (st.vend - st.v0) * s / L
        self.s = s
        self.hangw = smooth(st.s_rel, st.s_rel + 0.35, s) if not st.fly else np.zeros(n)
        self.rootk = 0.82 + 0.18 * smooth(0.0, 0.08, s)
        # piece segments: (piece name, first row, last row)
        sp = rows["split"]
        if "a" in sp and "b" in sp and sp["a"] < sp["b"] < n - 1:
            a, bb = sp["a"], sp["b"]
            ch = chain_of(st, P[a])
            self.segs = [("HairTop", 0, a), (ch, a, bb), (ch + "b", bb, n - 1)]
        elif "a" in sp and sp["a"] < n - 1:
            a = sp["a"]
            ch = chain_of(st, P[a])
            self.segs = [("HairTop", 0, a), (ch, a, n - 1)]
        else:
            self.segs = [("HairTop", 0, n - 1)]


def hairline_strands(cfg, rng, spacing=0.028, length=0.24):
    """short locks rooted on the natural hairline (front and temples), combed away from the parting and back: the
    whole strip on each (staggered soft roots at the hairline, tapered tips under the main layers), so the
    hairline is hair growing out of the scalp, not a card border"""
    pts = HL_PTS[np.argsort(np.arctan2(HL_PTS[:, 0], 0.05 - HL_PTS[:, 2]))]
    da = np.arctan2(pts[:, 0], 0.05 - pts[:, 2])
    keep = np.abs(da) < 1.16
    pts, da = pts[keep], da[keep]
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    sl = np.concatenate([[0], np.cumsum(seg)])
    out = []
    n = int(sl[-1] / spacing)
    for k in range(n + 1):
        sk = (k + rng.uniform(-0.25, 0.25)) * sl[-1] / n
        h = at_s(pts, sl, np.clip(sk, 0, sl[-1]))[0]
        dah = float(np.interp(sk, sl, da))
        sgn = 1.0 if dah > 0 else -1.0
        if abs(dah) < 0.02:
            sgn = 1.0 if k % 2 else -1.0
        a = min(1.0, abs(dah))
        d0 = unit(np.array([sgn * (0.85 - 0.45 * a), 0.5, 0.2 + 0.75 * a]))
        # straight in from the hairline (its root edge lies along the line), turning to the comb
        h2 = at_s(pts, sl, np.clip(sk + 0.01, 0, sl[-1]))[0] - at_s(pts, sl, np.clip(sk - 0.01, 0, sl[-1]))[0]
        nrm0 = unit(h - C)
        inward = unit(np.cross(nrm0, unit(h2)))
        if np.dot(inward, np.array([0.0, 1.0, 0.3])) < 0:
            inward = -inward
        # walk on the scalp from just inside the hairline
        th, az = SK.angles(h - C)
        p = SK.point(th - 0.006, az)
        P = [p]
        step = length / 5
        for _i in range(5):
            nrm = unit(p - C)
            kk = smooth(0.0, 3.5, _i)
            dd = unit(inward * (1 - kk) + d0 * kk)
            d = unit(dd - nrm * float(np.dot(dd, nrm)))
            q = p + d * step
            q = scalp_of(q)[0]
            P.append(q)
            p = q
        P = np.array(P)
        t = np.linspace(0, 1, len(P))
        P = C + unit(P - C) * (np.linalg.norm(P - C, axis=1) + 0.0225 + 0.014 * t ** 0.7)[:, None]
        st = Strand(side=int(sgn), f=0.0, layer="hairline", li=0, scalp=P, off=np.full(len(P), 0.0225), hang=None,
                    tip_y=P[-1, 1], lock=False, strip="medium" if rng.random() < 0.6 else "dense",
                    mirror=bool(rng.random() < 0.5), v0=0.0, vend=1.0, seed=int(rng.integers(1 << 30)), wave_ph=0.0,
                    body_off=0.05, w=(0.05, 0.065, 0.065), fly=True, shade=0.97)
        st.G = P
        st.s_rel = float(np.linalg.norm(np.diff(P, axis=0), axis=1).sum())
        out.append(st)
    return out


def flyaway_strands(strands, cfg, rng):
    """short wispy cards lifting off the outer layer over the top and the crown"""
    outer = [st for st in strands if st.li == len(LAYERS) - 1]
    out = []
    for i in range(FLYAWAYS["n"] * 2):
        src = outer[int(rng.integers(len(outer)))]
        D, S = densify(src.scalp, 2)
        ln = rng.uniform(*FLYAWAYS["len"])
        s0 = rng.uniform(0.08, max(0.1, src.s_rel - ln - 0.05))
        ss = np.linspace(s0, s0 + ln, 9)
        P = at_s(D, S, ss)
        t = np.linspace(0, 1, 9)
        lift = 0.01 + 0.022 * t ** 1.5
        P = P + unit(P - C) * lift[:, None]
        P = P + np.cross(unit(P - C), unit(np.gradient(P, axis=0))) * (rng.normal(0, 0.03) * t ** 2)[:, None]
        st = Strand(side=src.side, f=src.f, layer="fly", li=len(LAYERS), scalp=P, off=None, hang=None,
                    tip_y=P[-1, 1], lock=False, strip=FLYAWAYS["strip"], mirror=bool(rng.random() < 0.5),
                    v0=float(rng.uniform(0.25, 0.5)), seed=int(rng.integers(1 << 30)), wave_ph=0.0,
                    body_off=0.08, w=(FLYAWAYS["w"][0], FLYAWAYS["w"][1], FLYAWAYS["w"][1]), fly=True)
        st.G = P
        st.s_rel = float(np.linalg.norm(np.diff(P, axis=0), axis=1).sum())
        out.append(st)
    return out


# =========================================================================================== Blender meshes
def card_mesh(cards, name, coll, displace=0.022, seed=0):
    """all cards of a layer as one Blender mesh (two vertices per row, per-corner UVs and colours, a "hang"
    vertex group) with a Displace modifier (Clouds) breaking the hanging part into clumps; returns the object
    and per-card vertex index bases"""
    V, F, UV, Wg = [], [], [], []
    bases = []
    for cd in cards:
        base = len(V)
        bases.append(base)
        for i in range(cd.n):
            V.append(tuple(cd.left[i]))
            V.append(tuple(cd.right[i]))
            UV.append((cd.u[0], 1.0 - cd.v[i]))
            UV.append((cd.u[1], 1.0 - cd.v[i]))
            Wg += [cd.hangw[i], cd.hangw[i]]
        for i in range(cd.n - 1):
            a, b = base + 2 * i, base + 2 * i + 1
            c, d = base + 2 * i + 3, base + 2 * i + 2
            F.append((a, b, c, d))
    me = bpy.data.meshes.new(name)
    me.from_pydata(V, [], F)
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    uv = np.array(UV)
    loops_v = np.zeros(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", loops_v)
    uvl.data.foreach_set("uv", uv[loops_v].ravel())
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    vg = ob.vertex_groups.new(name="hang")
    Wg = np.asarray(Wg)
    for wv in np.unique(np.round(Wg, 2)):
        ids = np.nonzero(np.abs(np.round(Wg, 2) - wv) < 1e-6)[0].tolist()
        if wv > 0:
            vg.add(ids, float(wv), "REPLACE")
    if displace > 0:
        tex = bpy.data.textures.new(f"{name}_clumps", type="CLOUDS")
        tex.noise_scale = 0.22
        tex.noise_depth = 2
        tex.noise_basis = "BLENDER_ORIGINAL"
        md = ob.modifiers.new("clumps", "DISPLACE")
        md.texture = tex
        md.texture_coords = "GLOBAL"
        md.direction = "NORMAL"
        md.strength = displace
        md.mid_level = 0.5
        md.vertex_group = "hang"
        tex2 = bpy.data.textures.new(f"{name}_sway", type="CLOUDS")
        tex2.noise_scale = 0.6
        md2 = ob.modifiers.new("sway", "DISPLACE")
        md2.texture = tex2
        md2.texture_coords = "GLOBAL"
        md2.direction = "X"
        md2.strength = displace * 0.8
        md2.mid_level = 0.5
        md2.vertex_group = "hang"
    return ob, bases


def evaluated_positions(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    P = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", P)
    ev.to_mesh_clear()
    return P.reshape(-1, 3)


def guide_curves(strands, name, coll):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    for st in strands:
        sp = cu.splines.new("POLY")
        sp.points.add(len(st.G) - 1)
        for i, p in enumerate(st.G):
            sp.points[i].co = (p[0], p[1], p[2], 1.0)
    cu.bevel_depth = 0.002
    ob = bpy.data.objects.new(name, cu)
    coll.objects.link(ob)
    return ob


# =========================================================================================== clearance, occlusion
def enforce_clearance(P, refs, hang_mask):
    """every vertex over the head CLEAR_MIN above the male head mesh, both skull tables (female through the fit)
    and the female head (through the fit); out of the ear boxes; hanging vertices off both torsos"""
    P = P.copy()
    # nothing on the forehead below the hairline
    fr = (P[:, 2] < -0.2) & (np.abs(P[:, 0]) < 0.3) & (P[:, 1] > -0.4)
    if fr.any():
        hy = hairline_y(P[fr]) - 0.003
        Q = P[fr]
        Q[:, 1] = np.maximum(Q[:, 1], hy)
        P[fr] = Q
    over = P[:, 1] > -0.42
    P[over] = skull_push_v(P[over], CLEAR_MIN + 0.0005)
    ref_m, ref_f = refs
    sc = np.array([FIT_F["ax"], FIT_F["ay"], FIT_F["az"]])
    for i in range(len(P)):
        p = P[i]
        r = signed(ref_m.head, p, CLEAR_MIN + 0.03) if p[1] > -1.15 else None
        if r is not None and r[2] < CLEAR_MIN:
            p = r[0] + r[1] * (CLEAR_MIN + 0.0005)
        q = apply_fit(p, FIT_F)
        r = signed(ref_f.head, q, CLEAR_MIN + 0.03) if p[1] > -1.15 else None
        if r is not None and r[2] < CLEAR_MIN:
            q2 = r[0] + r[1] * (CLEAR_MIN + 0.0005)
            p = p + (q2 - q) / sc
        if -0.35 < p[1] < 0.15 and abs(p[0]) > 0.2:
            p = ear_push(p, EAR_CLEAR)
        if p[1] < -0.45:
            for _k in range(4):
                for ref in refs:
                    r = signed(ref.torso, p, 0.3)
                    if r is not None and r[2] < 0.012:
                        p = r[0] + r[1] * 0.0135
        P[i] = p
    return P


def hemi_dirs(n=12, seed=3):
    rng = np.random.default_rng(seed)
    out = []
    for k in range(n):
        u, v = (k + rng.uniform(0, 1)) / n, rng.uniform(0, 1)
        r = math.sqrt(u)
        a = TAU * v
        out.append((r * math.cos(a), r * math.sin(a), math.sqrt(max(0.0, 1 - u))))
    return np.array(out)


def bake_ao(P, Nout, hair_tris, refs, dist=0.08):
    """ambient occlusion per vertex: cosine-distributed rays round the outward normal against the hair cards
    (partial occluders) and the head / torso (full)"""
    hair = BVHTree.FromPolygons([tuple(p) for p in P], hair_tris)
    body = [refs[0].head, refs[0].torso]
    H = hemi_dirs(12)
    ao = np.ones(len(P))
    for i in range(len(P)):
        n = Nout[i]
        t1 = unit(np.cross(n, [0.0, 1.0, 0.0] if abs(n[1]) < 0.9 else [1.0, 0.0, 0.0]))
        t2 = np.cross(n, t1)
        o = P[i] + n * 0.004
        occ = 0.0
        for h in H:
            d = t1 * h[0] + t2 * h[1] + n * h[2]
            hit = 0.0
            loc, _nn, _ix, dd = hair.ray_cast(Vector(o), Vector(d), dist)
            if loc is not None:
                hit = 0.45 * (1 - dd / dist) ** 0.5
            for bv in body:
                loc, _nn, _ix, dd = bv.ray_cast(Vector(o), Vector(d), dist)
                if loc is not None:
                    hit = max(hit, 1.0 * (1 - dd / dist) ** 0.5)
            occ += hit
        ao[i] = 1 - occ / len(H)
    return ao


# =========================================================================================== build
def build_style(key, cfg, refs, coll, log):
    rng = np.random.default_rng(cfg["seed"] * 101 + 5)
    strands = make_strands(cfg, log)
    hang_strands(strands, refs, cfg, log)
    finish_guides(strands, refs, cfg, log)
    fly = flyaway_strands(strands, cfg, rng) + (hairline_strands(cfg, rng) if HAIRLINE_CARDS else [])
    allst = strands + fly
    guide_curves(strands, f"{key} guides", coll)
    guide_curves(fly, f"{key} flyaway guides", coll)
    cards = []
    only = [x for x in os.environ.get("LONG_LAYERS", "").split(",") if x]  # debug: build only these layers
    for st in allst:
        cd = Card(st, card_rows(st, cfg), rng)
        if not only or st.layer in only:
            cards.append(cd)
    # Blender: one mesh per layer, Displace modifiers on the hanging part; read back the evaluated positions
    by_layer = {}
    for cd in cards:
        by_layer.setdefault(cd.st.li, []).append(cd)
    mat = hair_material()
    layer_names = [L["name"] for L in LAYERS] + ["flyaways"]
    allP, allN, metas = [], [], []
    for li in sorted(by_layer):
        cl = sorted(by_layer[li], key=lambda c: (c.st.f, c.st.side))
        ob, bases = card_mesh(cl, f"{key} cards {layer_names[li]}", coll,
                              displace=0.0 if li == len(LAYERS) else 0.016 + 0.004 * li, seed=li)
        ob.data.materials.append(mat)
        P = evaluated_positions(ob)
        for cd, base in zip(cl, bases):
            Pc = P[base:base + 2 * cd.n]
            cd.left, cd.right = Pc[0::2].copy(), Pc[1::2].copy()
            metas.append(cd)
    # clearance (one pass over every vertex)
    V = np.vstack([np.stack([cd.left, cd.right], 1).reshape(-1, 3) for cd in metas])
    for _ in range(3):
        V = enforce_clearance(V, refs, None)
    k = 0
    for cd in metas:
        Pc = V[k:k + 2 * cd.n]
        cd.left, cd.right = Pc[0::2].copy(), Pc[1::2].copy()
        k += 2 * cd.n
    # occlusion
    tris = []
    k = 0
    NO = []
    for cd in metas:
        for i in range(cd.n - 1):
            a, b, c, d = k + 2 * i, k + 2 * i + 1, k + 2 * i + 3, k + 2 * i + 2
            tris += [(a, b, c), (a, c, d)]
        NO.append(np.repeat(cd.nout, 2, axis=0))
        k += 2 * cd.n
    NO = np.vstack(NO)
    t0 = time.time()
    ao = bake_ao(V, NO, tris, refs)
    log(f"  occlusion {len(V)} verts: {time.time() - t0:.1f}s")
    k = 0
    for cd in metas:
        a = ao[k:k + 2 * cd.n].reshape(-1, 2).mean(1)
        shade = cd.st.shade or (LAYERS[cd.st.li]["shade"] if cd.st.li < len(LAYERS) else FLYAWAYS["shade"])
        cd.col = np.clip((0.58 + 0.42 * a) * shade * cd.rootk, 0.45, 1.0)
        k += 2 * cd.n
    # pieces: innermost layer first, front to back within a layer
    pieces = {}
    seg_rows = {}
    for cd in metas:
        for (nm, r0, r1) in cd.segs:
            seg_rows.setdefault(nm, []).append((cd, r0, r1))
    order = ["HairTop"] + [c for ch in CHAINS for c in (ch, ch + "b")]
    for nm in order:
        if nm not in seg_rows:
            continue
        p = hl.Piece(nm, TEX_KEY)
        for cd, r0, r1 in sorted(seg_rows[nm], key=lambda x: (x[0].st.li, x[0].st.f)):
            ids = []
            for i in range(r0, r1 + 1):
                c = float(cd.col[i])
                a = p.vert(cd.left[i], cd.N[i], (cd.u[0], cd.v[i]), (c, c, c, 1.0))
                b = p.vert(cd.right[i], cd.N[i], (cd.u[1], cd.v[i]), (c, c, c, 1.0))
                ids.append((a, b))
            for i in range(len(ids) - 1):
                a, b = ids[i]
                d, c = ids[i + 1]
                # the outward-facing pair first (its geometric normal agrees with the shading normal), then its twin
                p.T += [(a, c, d), (a, b, c), (a, d, c), (a, c, b)]
        pieces[nm] = (p, seg_rows[nm])
    out = []
    for nm, (p, segs) in pieces.items():
        if nm == "HairTop":
            p.meta = dict(material="SmoothPlastic", castShadow=True)
        else:
            chain = nm.rstrip("b")
            seg = 2 if nm.endswith("b") else 1
            top = np.array([(cd.left[r0] + cd.right[r0]) / 2 for cd, r0, r1 in segs]).mean(0)
            bot = np.array([(cd.left[r1] + cd.right[r1]) / 2 for cd, r0, r1 in segs]).mean(0)
            fx = dict(kind="swing", chain=chain.replace("Hair", ""), seg=seg, stiff=HAIRFX["stiff"],
                      mass=HAIRFX["mass"] if seg == 1 else HAIRFX["mass2"],
                      pivot=[round(float(x), 4) for x in top], tip=[round(float(x), 4) for x in bot])
            if seg == 2:
                fx["parent"] = chain
            p.meta = dict(hairfx=fx, length="hang", material="SmoothPlastic", castShadow=True,
                          hideUnder={"headgear": False, "hood": True})
        out.append(p)
    # seg 2 pivots are their seg 1 tips (the same rows): make them identical
    byname = {p.name: p for p in out}
    for p in out:
        fx = p.meta.get("hairfx")
        if fx and fx["seg"] == 2 and fx["parent"] in byname:
            fx["pivot"] = list(byname[fx["parent"]].meta["hairfx"]["tip"])
    return out, metas


def hair_material(name="hair_straight"):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(TEX_PATH, check_existing=True)
    tx.image.alpha_mode = "STRAIGHT"
    tint = nt.nodes.new("ShaderNodeRGB")
    tint.outputs[0].default_value = (0.19, 0.13, 0.09, 1)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1
    nt.links.new(tx.outputs[0], mix.inputs[6])
    nt.links.new(tint.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], bs.inputs["Base Color"])
    nt.links.new(tx.outputs[1], bs.inputs["Alpha"])
    m.blend_method = "HASHED"
    return m


def clearance_report(pieces, refs):
    ref_m, ref_f = refs
    out = dict(head_m=9.0, skull_m=9.0, head_f_fit=9.0, skull_f_fit=9.0, skull_m_narrow=9.0, inside_m=0,
               ear_box=9.0, face_below_hairline=0, torso_m=9.0, torso_f=9.0)
    for p in pieces:
        P = np.asarray(p.P)
        for lo, hi in EARS:
            dd = np.maximum(lo - P, P - hi)
            out["ear_box"] = min(out["ear_box"], float(np.max(dd, axis=1).min()))
        fr = (P[:, 2] < -0.2) & (np.abs(P[:, 0]) < 0.3) & (P[:, 1] > -0.4)
        if fr.any():
            out["face_below_hairline"] += int((P[fr, 1] < hairline_y(P[fr]) - 0.005).sum())
        Pf = apply_fit(P, FIT_F)
        hm, thm = skull_height_v(SK, P)
        hn, thn = skull_height_v(SK, P / np.array([0.965, 1, 1]))
        near = (hm < 0.12) & (P[:, 1] > -0.3) & (thm < 2.55)
        if near.any():
            out["skull_m"] = min(out["skull_m"], float(hm[near].min()))
            out["skull_m_narrow"] = min(out["skull_m_narrow"], float(hn[near].min()))
            if SKF is not None:
                hf, thf = skull_height_v(SKF, Pf)
                out["skull_f_fit"] = min(out["skull_f_fit"], float(hf[near].min()))
        for q, qf in zip(P, Pf):
            if q[1] > -1.15:
                h = ref_m.height(q)
                out["head_m"] = min(out["head_m"], h)
                if h < 0:
                    out["inside_m"] += 1
                out["head_f_fit"] = min(out["head_f_fit"], ref_f.height(qf))
            if q[1] < -0.45:
                for nm, ref in (("torso_m", ref_m), ("torso_f", ref_f)):
                    r = signed(ref.torso, q, 0.3)
                    if r is not None:
                        out[nm] = min(out[nm], r[2])
    return {k: (round(v, 4) if isinstance(v, float) else v) for k, v in out.items()}


# =========================================================================================== blend file
def save_blend(key, coll, refs, path):
    """the style's Blender scene: guide curves, card meshes (with their Displace modifiers), the exported pieces
    and the reference head / torso, under a root rotated from game space (+Y up) to Blender's +Z up"""
    root = bpy.data.objects.new(f"{key} (game head space)", None)
    bpy.context.scene.collection.objects.link(root)
    root.rotation_euler = (math.pi / 2, 0, math.pi)
    for ob in list(coll.objects):
        if ob.parent is None:
            ob.parent = root
    ref = refs[0]
    for nm, P, F in (("head_m (reference)", ref.headP, ref.headF), ("torso_m (reference)", ref.torsoP, ref.torsoF)):
        me = bpy.data.meshes.new(nm)
        me.from_pydata([tuple(p) for p in P], [], F)
        ob = bpy.data.objects.new(nm, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = root
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


def pieces_to_blender(pieces, coll):
    sub = bpy.data.collections.new("exported pieces")
    coll.children.link(sub)
    mat = hair_material()
    for p in pieces:
        hl.to_blender(single_sided(p), bpy, material=mat, collection=sub)


def single_sided(piece):
    """a copy without the reversed twins of the two-sided card triangles (Cycles / Blender shade both sides)"""
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


# =========================================================================================== renders
TINTS = {"black": (0.09, 0.078, 0.07), "brown": (0.188, 0.129, 0.094), "blonde": (0.77, 0.61, 0.36),
         "darkblonde": (0.42, 0.31, 0.19)}
SKINS = {"mid": None, "light": (0.72, 0.52, 0.4), "tan": (0.56, 0.38, 0.27), "deep": (0.2, 0.12, 0.08)}
LOOKS = {
    "f_brown": ("f", "brown", "light"),
    "f_blonde": ("f", "blonde", "tan"),
    "m_darkblonde": ("m", "darkblonde", "mid"),
    "m_black": ("m", "black", "deep"),
}
VIEWS = ["34", "side", "back", "close", "top34"]


def cap_standin(density, outdir):
    """the shared scalp cap as the game paints it for cut "full": the short tile (8 x 4), alpha = tile alpha x
    natural-hairline coverage x density"""
    gw, gh = 256, 128
    th = (np.arange(gh) + 0.5) / gh * 2.2
    az = (np.arange(gw) + 0.5) / gw * TAU
    TH, AZ = np.meshgrid(th, az, indexing="ij")
    s_ = np.sin(TH.ravel())
    D = np.stack([s_ * np.sin(AZ.ravel()), np.cos(TH.ravel()), s_ * np.cos(AZ.ravel())], -1)
    S = scalp_of(C + D * 0.4)
    cov = (smooth(-0.012, 0.01, edge_dist(S)) * density).reshape(gh, gw)
    W, H = 1024, 512
    cov = np.asarray(Image.fromarray((cov * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255
    tile = Image.open(os.path.join(TEX_DIR, "hair_short.png")).convert("RGBA").resize((W // 8, H // 4), Image.LANCZOS)
    t = np.tile(np.asarray(tile, np.float32) / 255, (4, 8, 1))
    t[..., 3] *= cov
    path = os.path.join(outdir, "capstandin_long.png")
    Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)
    p = hl.Piece("HairCap", "short")
    n_th, n_az = 60, 96
    ids = {}
    for i in range(n_th + 1):
        for j in range(n_az + 1):
            t_ = i / n_th * 2.2
            a_ = j / n_az * TAU
            d = hl.Skull.direction(t_, a_)
            ids[(i, j)] = p.vert(SK.point(t_, a_, 0.016), d, (j / n_az, i / n_th), (0.55, 0.55, 0.55))
    for i in range(n_th):
        for j in range(n_az):
            p.tri(ids[(i, j)], ids[(i + 1, j + 1)], ids[(i, j + 1)])
            p.tri(ids[(i, j)], ids[(i + 1, j)], ids[(i + 1, j + 1)])
    return p, path


MATTE = {"Roughness": 0.5, "Specular IOR Level": 0.35}


def render_style(key, pieces, outdir, samples, looks, views, res=(520, 620), tex=TEX_PATH):
    import render
    os.makedirs(outdir, exist_ok=True)
    cap, cap_tex = cap_standin(1.0, outdir)
    paths, labels = [], []
    for look in looks:
        head_name, tint_name, skin_name = LOOKS[look]
        tint = TINTS[tint_name]
        sc = render.Scene(res=res, samples=samples, focus=(0.0, -0.32, 0.04), dist=6.6)
        skin = SKINS[skin_name] or render.SKIN
        render.add_obj(sc, os.path.join(REF, f"head_{head_name}.obj"), tint=skin)
        for _nm, md in render.load_obj(os.path.join(REF, f"torso_{head_name}.obj")).items():
            sc.add_mesh(dict(md, c=None), material="skin", tint=skin, name="torso")
        scl, off = (1, 1, 1), (0, 0, 0)
        if head_name == "f":
            scl, off = (FIT_F["ax"], FIT_F["ay"], FIT_F["az"]), (0, 0, FIT_F["dz"])
        sc.add_piece(cap, texture=cap_tex, tint=tint, offset=off, scale=scl)
        dbg = os.environ.get("LONG_DEBUG", "")
        for p in pieces:
            q = single_sided(p)
            if "nocol" in dbg:
                q.C = [(1.0, 1.0, 1.0, 1.0)] * len(q.C)
            ob = sc.add_piece(q, texture=None if "notex" in dbg else tex, tint=tint, offset=off, scale=scl)
            bs = ob.data.materials[0].node_tree.nodes["Principled BSDF"]
            for k, v in MATTE.items():
                bs.inputs[k].default_value = v
        for v in views:
            path = os.path.join(outdir, f"{key}_{look}_{v}.png")
            if v == "close":
                sc.render(path, view=(16, 6, 1.0), dist=2.5, focus=(0, 0.22, -0.12))
            elif v == "top34":
                sc.render(path, view="top34", dist=4.9, focus=(0, 0.1, 0.0))
            elif v == "side":
                sc.render(path, view="side")
            else:
                sc.render(path, view=v)
            paths.append(path)
            labels.append(f"{look} {v}")
    out = os.path.join(outdir, f"sheet_{key}.jpg")
    render.sheet(paths, out, cols=len(views), labels=labels,
                 title=f"{key} ({sum(p.nt for p in pieces)} tris, {len(pieces)} pieces)", cell=(312, 372))
    return out


def load_pieces(key):
    """the exported pieces back from out/<key> (for renders without a rebuild)"""
    import struct
    d = json.load(open(os.path.join(hl.OUT, key, "style.json")))
    out = []
    for nm, rec in d["pieces"].items():
        b = open(os.path.join(hl.OUT, key, rec["mesh_file"]), "rb").read()
        i = b.index(b"\n") + 1
        _hs, _vs, _fs, nv, nt = struct.unpack("<HBBII", b[i:i + 12])
        i += 12
        p = hl.Piece(nm, rec["tex"])
        for _k in range(nv):
            x = struct.unpack("<3f3f2f", b[i:i + 32])
            i += 36
            c = struct.unpack("<4B", b[i:i + 4])
            i += 4
            p.P.append(x[0:3])
            p.N.append(x[3:6])
            p.U.append(x[6:8])
            p.C.append(tuple(v / 255 for v in c))
        for _k in range(nt):
            p.T.append(struct.unpack("<3I", b[i:i + 12]))
            i += 12
        out.append(p)
    return out


# =========================================================================================== main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--no-tex", action="store_true")
    ap.add_argument("--no-build", action="store_true", help="render the exported pieces without rebuilding")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--views", default="")
    ap.add_argument("--looks", default="")
    ap.add_argument("--res", default="520x620")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    t0 = time.time()

    def log(*a):
        print(f"[{time.time() - t0:6.1f}s]", *a, flush=True)
    if not args.no_build and (not args.no_tex or not os.path.exists(TEX_PATH)):
        make_texture(TEX_PATH)
        log("texture", TEX_PATH)
    log("female fit", {k: round(float(v), 4) for k, v in FIT_F.items()})
    keys = [k for k in STYLES if not args.only or k in args.only.split(",")]
    report = {}
    for key in keys:
        cfg = STYLES[key]
        if not args.no_build:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            refs = (Ref("m"), Ref("f"))
            coll = bpy.data.collections.new(f"{key} (long family)")
            bpy.context.scene.collection.children.link(coll)
            log(f"style {key}")
            pieces, _metas = build_style(key, cfg, refs, coll, log)
            clr = clearance_report(pieces, refs)
            log("  clearance", clr)
            entry = dict(cfg["entry"])
            entry.update(family="long", clearance=clr, texture_strips={k: list(v) for k, v in STRIPS.items()})
            data = hl.export_style(key, entry, pieces)
            log(f"  exported {key}: {data['tris']} tris, {len(pieces)} pieces")
            pieces_to_blender(pieces, coll)
            save_blend(key, coll, refs, os.path.join(BLEND_DIR, f"{key}.blend"))
            log("  saved", os.path.join(BLEND_DIR, f"{key}.blend"))
            report[key] = dict(tris=data["tris"], pieces={p.name: p.nt for p in pieces}, clearance=clr)
        if args.render:
            pieces = load_pieces(key)
            looks = args.looks.split(",") if args.looks else (
                ["f_brown", "f_blonde", "m_darkblonde"] if key == "long" else ["m_darkblonde", "f_brown", "f_blonde"])
            views = args.views.split(",") if args.views else VIEWS
            w, h = (int(x) for x in args.res.split("x"))
            sheet = render_style(key, pieces, args.render, args.samples, looks, views, res=(w, h))
            log("  sheet", sheet)
    if report:
        print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
