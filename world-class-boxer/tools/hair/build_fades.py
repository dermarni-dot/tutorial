"""Fades family + the shared scalp cap (Blender, headless):

    /opt/bpyenv/bin/python tools/hair/build_fades.py [--render] [--only key,key] [--views 34,side] [--quick]

Writes
* textures/hair_short.png      128x256 tileable tile: 1-4 mm hairs lying back from the crown (straight / wavy)
* textures/hair_shortcoil.png  128x256 tileable tile: tiny tight coils (Curly, Kinky, Coiled)
* textures/hair_waves.png      1024x1024 whole-cap 360-waves image (the entry's capTileRepeat = {1, 1})
* textures/hair_crop.png       short tapered tufts (4 strips) for the straight / wavy crop-top cards
  (generators in fades_tex.py)
* out/cap/                     the shared scalp cap (HairCap, polar UV, thetaMax, tile, tiles)
* out/<style key>/             the fade / buzz / waves / caesar / crew entries
* blend/<key>.blend            every model, openable in Blender
and, with --render, self-check renders + sheets in the scratchpad (FAM_DIR).

Geometry is built in Blender. The cap and the fur shells are polar grids laid on the skull's radial table and
pushed clear of the game's head mesh with a mathutils BVHTree; each shell is the cap's own surface lifted along
the skull ray by its height (so shells never come closer than SHELL_SEP to the layer under them), spans the
cap's whole footprint wherever the style can have any coverage (its edges lie where the painted cap is already
transparent: no edge line), and gets clump unevenness from a Displace modifier (Clouds) read back through the
depsgraph. The shells thin outward in the game: each names a capShell { rank, cov } variant of the painted cap
(HairAssetKit.PaintCap: only the tile's higher-ranked texels, and coverage below cov counts as none, so outer
shells give way first down a fade and at the hairline). The crop-top cards are swept along Bezier guide curves
(one curve object, evaluated by Blender) that follow the comb flow over the scalp; their tips follow the style's
own top profile (the fades' shelf at FADE_TOP, the crew's front lift, the Caesar's straight fringe).
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


def sstep(e0, e1, x):
    t = np.clip((np.asarray(x, np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
import fades_tex  # noqa: E402

TEX = os.path.join(HERE, "textures")
BLEND = os.path.join(HERE, "blend")
REF = os.path.join(HERE, "ref")
FAM_DIR = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/fam/fades"

TAU = 2 * math.pi
# the cap's polar UV: v = theta / THETA_MAX. The nape's hairline sits at theta ~141 deg, so the cap must
# reach ~146 deg (the game's old placeholder 2.2 rad = 126 deg would cut the nape off)
THETA_MAX = math.radians(148.0)
TILE = [8, 4]  # the tile repeats (u, v) over the cap: ~0.33 x 0.29 studs a tile at the equator
CAP_OFF = 0.02  # the cap's height above the skull (the runtime fit's residual is <= 0.015)
CLEAR = 0.02  # minimum height of any scalp-hugging layer above the skull / head mesh
SHELL_SEP = 0.0052  # minimum gap between a shell and the layer under it (no z-fighting in the game)
SHELL_SAG = 0.0027  # the coarse shell grid's chord sag + the cap's own push-out differences


def build_textures():
    os.makedirs(TEX, exist_ok=True)
    out = {}
    jobs = (("short", fades_tex.tex_short), ("shortcoil", fades_tex.tex_shortcoil),
            ("waves", lambda: fades_tex.tex_waves(THETA_MAX)), ("crop", fades_tex.tex_crop))
    for key, fn in jobs:
        t0 = time.time()
        L, A = fn()
        p = fades_tex.save_tex(os.path.join(TEX, f"hair_{key}.png"), L, A)
        out[key] = p
        print(f"texture {key}: {L.shape[1]}x{L.shape[0]} mean grey {float((L * A).sum() / A.sum()):.2f} "
              f"mean alpha {A.mean():.2f} ({time.time() - t0:.1f}s)")
    return out


CROP_STRIPS = fades_tex.CROP_STRIPS

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
        # inside / outside by the nearest face's own normal (the head mesh winds CCW from outside): a point in
        # the crevice behind an ear is outside, at its distance from the ear
        out = np.dot(p - np.array(loc), np.array(nrm)) >= 0
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

    def __init__(self, ref, head, dth=2.0, nmax=96, fit=None, margin=0.034):
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
        ok = dist < margin
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

def cap_layer(cb, T=None):
    """the cap's surface on this grid (CAP_OFF above the skull, pushed clear of the head mesh / female skull)"""
    if getattr(cb, "_capP", None) is None:
        cb._capP = cb.layer(np.full(len(cb.S), CAP_OFF))
    return cb._capP


# =============================================================================================
# Fur shells (tex "cap"): the cap's surface lifted, sparser outward (capShell variants of the painted cap)
# =============================================================================================
# the painted cap's variants the shells use (at most 3 per entry: each costs one half-size image per boxer)
VAR_1 = {"rank": 0.0, "cov": 0.4}  # the inner shell: the cap's own strands, but only where the cut is long
VAR_A = {"rank": 0.3, "cov": 0.55}
VAR_B = {"rank": 0.55, "cov": 0.7}
VAR_C = {"rank": 0.75, "cov": 0.82}
VAR_FUR = {"rank": 0.5, "cov": 0.35}  # a buzz / waves cut's one fur shell


def shell_variant(k, n):
    """the painted cap's variant shell k of n draws with (at most 4 per entry: each costs one half-size image per
    boxer). Every shell has a coverage floor: down a fade (and at a soft hairline) the cap alone carries the
    gradient and the shells give way from the outside in, so the stack never makes a fade opaque"""
    if n == 1:
        return VAR_FUR
    f = k / n
    if k == n and n >= 3:
        return VAR_C
    if f <= 0.34:
        return VAR_1
    if f <= 0.67:
        return VAR_A
    return VAR_B


def edge_factor(cb):
    """0 at the natural hairline, 1 ~2.5 cm inside it (the hair is shorter at its edge)"""
    return np.clip((cb.cov["none"] - 0.25) / 0.6, 0, 1) ** 0.9


def profile(cb, spec):
    """the style's hair height above the cap (studs) at every grid vertex: the top profile, the sides it keeps,
    and the fade (the shelf at FADE_TOP)"""
    kind = spec["kind"]
    S = cb.S
    x, y, z = S[:, 0], S[:, 1], S[:, 2]
    e = edge_factor(cb)
    covk = cb.cov[kind]
    shape = spec["shape"]
    T = spec["top"]
    if shape == "fur":
        t = np.full(len(S), spec["top"])
    elif shape == "fade":
        ft = spec["fade_top"]
        w = np.clip((covk - 0.45) / 0.5, 0, 1) * sstep(ft - 0.02, ft + 0.06, y)
        dome = 0.78 + 0.22 * sstep(0.15, 0.5, y)
        t = T * w * dome + 0.004 * np.clip(covk, 0, 1)
    elif shape == "taper":
        side = np.clip((covk - 0.4) / 0.5, 0, 1)
        top = sstep(0.14, 0.3, y)
        t = side * (spec["side"] + (T - spec["side"]) * top * (0.8 + 0.2 * sstep(0.3, 0.5, y)))
    elif shape == "burst":
        w = np.clip((covk - 0.45) / 0.5, 0, 1)
        top = sstep(0.08, 0.24, y)
        t = w * (spec["side"] + (T - spec["side"]) * top * (0.8 + 0.2 * sstep(0.3, 0.5, y)))
    elif shape == "crew":
        top = sstep(0.16, 0.32, y)
        front = T * (1 - sstep(-0.38, 0.2, z)) + spec["crown"] * sstep(-0.38, 0.2, z)
        t = spec["side"] + (front - spec["side"]) * top
    elif shape == "caesar":
        top = sstep(0.1, 0.3, y)
        t = spec["side"] + (T - spec["side"]) * top
    else:
        raise ValueError(shape)
    t = np.where(e > 0, t * e, 0.0) if shape != "fur" else t * np.clip(e * 2, 0.4, 1)
    return np.maximum(t, 0.0) * spec.get("scale", 1.0)


def shell_footprint(cb, spec):
    """the cap's footprint less the triangles where this style never has coverage (well below its fade: the
    shell's edge lies where the painted cap is already fully transparent)"""
    kind = spec["kind"]
    if getattr(cb, "_bad", None) is None:
        # vertices whose cap point could not be pushed clear of the head mesh (in behind an ear): no shell there
        Pc = cap_layer(cb)
        bad = np.zeros(len(Pc), bool)
        for i in np.unique(cb.keepT.ravel()):
            bad[i] = cb.head.signed(Pc[i]) < CLEAR - 0.0005
        cb._bad = bad
    T = cb.keepT[~cb._bad[cb.keepT].any(axis=1)]
    if kind == "none":
        return T
    cs, cbl = cb.cov_sharp[kind], cb.cov[kind]
    # (only where the fade itself takes the hair off: inside the natural hairline; never along the hairline)
    dead = (cs < 0.002) & (cbl < 0.01) & (cb.cov_sharp["none"] > 0.98) & (cb.cov["none"] > 0.9)
    return T[~dead[T].all(axis=1)]


def build_shells(cb, spec, name, n, ts, tufts=0.006, lean=0.9, seed=5):
    """n shells: shell k at CAP_OFF + d_k over the cap's own surface, d_k = max(k * SHELL_SEP, ts * k / n);
    a Displace modifier (Clouds, global coordinates: coherent through the stack) raises clumps, weighted by a
    vertex group that grows with k and with ts (separations only grow outward) and is 0 round the crown's pole.
    Shading normals wander a little by clump (no smooth helmet highlight); vertex colours darken inward."""
    bpy = bl()
    from mathutils import Vector, noise as mnoise
    Pc = cap_layer(cb)
    T0 = shell_footprint(cb, spec)
    tsmax = max(1e-6, float(ts.max()))
    # the outermost shell (plus its clumps) must clear the head mesh too: where it would run into an ear, no
    # shell at all (the same footprint for every shell of the stack: no edge between them)
    dmax = np.maximum(n * SHELL_SEP + SHELL_SAG, ts + SHELL_SAG) + tufts
    bad = np.zeros(len(Pc), bool)
    for i in np.unique(T0.ravel()):
        q = Pc[i] + cb.D[i] * dmax[i]
        bad[i] = cb.head.signed(q) < CLEAR or cb.ref.in_ear(q, 0.01)
    T0 = T0[~bad[T0].any(axis=1)]
    tex = bpy.data.textures.get("TuftNoise") or bpy.data.textures.new("TuftNoise", "CLOUDS")
    tex.noise_scale = 0.04
    tex.noise_depth = 2
    tex.noise_basis = "BLENDER_ORIGINAL"
    tex.contrast = 1.3
    pieces, obs = [], []
    material = spec.get("material", "Plastic")
    for k in range(1, n + 1):
        d = np.maximum(k * SHELL_SEP + SHELL_SAG, ts * k / n + SHELL_SAG)
        P = Pc + cb.D * d[:, None]
        T = orient_outward(P, T0, cb.ref.sk.c)
        T2, (P2, N2, U2, V2, t2, d2, th2, D2) = compact(T, P, cb.N, cb.U, cb.V, ts, d, cb.th, cb.D)
        nm = f"{name}{k}" if n > 1 else name
        ob = obj_from_arrays(nm, P2, T2)
        vg = ob.vertex_groups.new(name="tuft")
        frac = (k / n) * np.clip(t2 / tsmax, 0, 1) * np.clip((th2 - 0.05) / 0.1, 0, 1)
        for i, w in enumerate(frac):
            vg.add([i], float(w), "REPLACE")
        mod = ob.modifiers.new("Tufts", "DISPLACE")
        mod.texture = tex
        mod.texture_coords = "GLOBAL"
        # (along the skull ray, as custom normals: the seam's twin vertices move alike, no crack)
        ob.data.normals_split_custom_set_from_vertices([tuple(map(float, x)) for x in D2])
        mod.direction = "CUSTOM_NORMAL"
        mod.mid_level = 0.0  # outward only
        mod.strength = tufts
        mod.vertex_group = "tuft"
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        PE = np.array([v.co[:] for v in me.vertices])
        ev.to_mesh_clear()
        assert len(PE) == len(P2)
        var = shell_variant(k, n)
        piece = Piece(nm, "cap", material=material, castShadow=False)
        if var:
            piece.meta["capShell"] = dict(var)
        occ = 0.68 + 0.32 * (k / n)
        for i in range(len(PE)):
            q = Vector(tuple(PE[i] * 70.0))
            nv = np.array(mnoise.noise_vector(q))
            nn = N2[i] + nv * 0.16 * float(np.clip(t2[i] / tsmax, 0, 1))
            c = occ * (0.88 + 0.12 * (0.5 + 0.5 * mnoise.noise(Vector(tuple(PE[i] * 14.0 + 3.1)))))
            # the hair leans back: the shell shows the cap's texels from nearer the crown (strands lie along +v)
            vv = V2[i] - lean * d2[i] / (0.45 * THETA_MAX) * min(1.0, V2[i] / 0.06)
            piece.vert(PE[i], nn, (U2[i], max(0.0, vv)), (c, c, c, 1.0))
        for tt in T2:
            piece.T.append(tuple(int(x) for x in tt))
        pieces.append(piece)
        obs.append(ob)
    return pieces, obs


# =============================================================================================
# Crop-top cards (straight / wavy): short tufts combed over the top, laid on guide curves
# =============================================================================================
FRINGE_Y = 0.305  # the Caesar's straight fringe line (the front hairline's centre is at y 0.336)


def build_crop(cb, spec, t_full, t_shell, seed=11, name="HairCrop"):
    """Tufts rooted inside the shells (where the top is long), rising to the style's own top height at their tip
    and lying along the comb flow (forward over the top, down behind the crown, down and back at the sides).
    Tips stay 0.02 inside the natural hairline (flatter toward it: the top profile is lower there), except the
    Caesar's front tufts, which run forward to a straight fringe at FRINGE_Y. Guides are Bezier splines of one
    Blender curve object (resolution 3, evaluated by the depsgraph to 4 points each); a double-sided card strip
    is swept along each, its texture's alpha fading in at the root."""
    bpy = bl()
    ref, sk = cb.ref, cb.ref.sk
    rng = np.random.default_rng(seed)
    peak = float(t_full.max())
    cand = np.where((t_full > peak * spec.get("root_min", 0.55)) & cb.ok)[0]
    caesar = spec["shape"] == "caesar"

    def t_at(q):
        j = int(np.argmin(((cb.S - q) ** 2).sum(1)))
        return t_full[j], t_shell[j]

    nwant = spec.get("cards", 500)
    guides = []
    tries = 0
    while len(guides) < nwant and tries < nwant * 30:
        tries += 1
        i = int(rng.choice(cand))
        th = cb.th[i] + rng.normal(0, 0.014)
        az = cb.az[i] + rng.normal(0, 0.035)
        p = sk.point(th, az, 0.0)
        n = sk.normal(max(th, 0.03), az)
        fwd = np.array([0, 0, -1.0]) - n * (-n[2])
        fwd /= np.linalg.norm(fwd) + 1e-9
        grow = sk.point(th + 0.02, az, 0.0) - p
        grow /= np.linalg.norm(grow) + 1e-9
        wb = smoothstep(0.05, 0.3, p[2]) * smoothstep(0.62, 0.35, p[1])  # behind / below the crown: grows down
        if th < 0.12:
            wb = 0.0
        ws = smoothstep(0.18, 0.34, abs(p[0])) * (1 - wb)  # the sides: down and back
        flow = fwd * (1 - wb - ws) + grow * (wb + ws)
        flow -= n * np.dot(flow, n)
        flow /= np.linalg.norm(flow) + 1e-9
        side = np.cross(n, flow)
        flow = flow + side * rng.normal(0, 0.22)
        flow /= np.linalg.norm(flow)
        tf0, ts0 = t_at(p)
        L = rng.uniform(*spec.get("card_len", (0.055, 0.085)))
        front = caesar and p[2] < -0.18 and abs(p[0]) < 0.24
        if front:
            L = 0.16
        root_h = CAP_OFF + rng.uniform(0.35, 0.65) * ts0
        # march over the scalp along the flow
        qs = [p.copy()]
        q = p.copy()
        ns = 3 if not front else 12
        for s in range(ns):
            _, _, nq = surface_frame(sk, q)
            fl = flow - nq * np.dot(flow, nq)
            fl /= np.linalg.norm(fl) + 1e-9
            q = sk.point(*Skull.angles(q + fl * L / ns - sk.c), 0.0)
            qs.append(q.copy())
            if front and q[1] <= FRINGE_Y:
                break
        if front:
            if qs[-1][1] > FRINGE_Y + 0.004:
                continue
            # cut the march at the fringe line, resample to 4 points
            a, b = qs[-2], qs[-1]
            f = (a[1] - FRINGE_Y) / max(1e-6, a[1] - b[1])
            qs[-1] = a + (b - a) * f
            qq = np.array(qs)
            seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(qq, axis=0), axis=1))]
            if seg[-1] < 0.03:
                continue
            # (only the last 0.08 of the march: the tuft's own length)
            s0 = max(0.0, seg[-1] - rng.uniform(0.06, 0.085))
            ss = np.linspace(s0, seg[-1], 4)
            qs = [np.array([np.interp(sv, seg, qq[:, c]) for c in range(3)]) for sv in ss]
            qs = [sk.point(*Skull.angles(x - sk.c), 0.0) for x in qs]
            tf0, ts0 = t_at(qs[0])
            root_h = CAP_OFF + rng.uniform(0.4, 0.7) * ts0
        tip = qs[-1]
        tft, _ = t_at(tip)
        if front:
            tip_h = CAP_OFF + 0.006 + rng.uniform(0, 0.004)
        else:
            if not ref.inside(tip, -0.02, which="min"):
                continue
            if tft < peak * spec.get("tip_min", 0.3):
                continue
            tip_h = CAP_OFF + max(0.006, tft) * rng.uniform(0.9, 1.08)
        pts = []
        for s, x in enumerate(qs):
            f = s / (len(qs) - 1)
            th_q, az_q, _ = surface_frame(sk, x)
            mid = CAP_OFF + max(tf0, tft) * rng.uniform(0.95, 1.05)
            if front:
                h = root_h + (tip_h - root_h) * f ** 1.4 + (mid - root_h) * math.sin(f * math.pi) * 0.5
            else:
                h = root_h + (tip_h - root_h) * math.sin(f * math.pi / 2) ** 0.8
            pts.append(sk.point(th_q, az_q, max(h, CLEAR + 0.003)))
        guides.append((np.array(pts), root_h, front))
    # the guide curve: one Bezier spline per tuft, handles from the marched points
    cu = bpy.data.curves.new(name + "Guides", "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 3
    for pts, _, _ in guides:
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(1)
        a, b = sp.bezier_points[0], sp.bezier_points[1]
        a.co, b.co = tuple(pts[0]), tuple(pts[-1])
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
    order = sorted(range(len(guides)), key=lambda g: guides[g][1])
    for g in order:
        idx = np.linspace(0, per - 1, 4).round().astype(int)
        pts = EP[g * per:(g + 1) * per][idx].copy()
        for i in range(len(pts)):
            h = sk.height(pts[i])
            if h < CLEAR + 0.003:
                dd = pts[i] - sk.c
                pts[i] = pts[i] + dd / np.linalg.norm(dd) * (CLEAR + 0.003 - h)
            s = cb.head.signed(pts[i])
            if s < CLEAR + 0.002:
                dd = pts[i] - sk.c
                pts[i] = pts[i] + dd / np.linalg.norm(dd) * (CLEAR + 0.002 - s)
        ups = []
        for x in pts:
            th, az = Skull.angles(x - sk.c)
            ups.append(sk.normal(max(th, 0.03), az))
        w0 = rng.uniform(0.022, 0.034)
        widths = [w0 * (1.0 - 0.3 * (i / 3) ** 1.5) for i in range(4)]
        # (strip 0 is the blunt-cut tuft: the Caesar's fringe and much of its top; the others end in points)
        s = 0 if (caesar and (guides[g][2] or rng.random() < 0.4)) else int(rng.integers(1, CROP_STRIPS))
        base = rng.uniform(0.74, 0.88)
        piece.card(list(pts), widths, ups, (s / CROP_STRIPS, (s + 1) / CROP_STRIPS),
                   shade=lambda t, b=base: (b + (1 - b) * t,) * 3, twist=[rng.normal(0, 0.1)] * 4)
    return piece, gob, len(guides)


def surface_frame(sk, p):
    th, az = Skull.angles(p - sk.c)
    th = max(th, 0.03)
    return th, az, sk.normal(th, az)


# =============================================================================================
# Styles
# =============================================================================================
STRAIGHT = ["Straight", "Wavy"]
CURLY = ["Curly", "Kinky", "Coiled"]

# key, Looks.HairStyles ids, coverage kind, spec
FAMILY = [
    ("buzz", ["Buzz Cut"], "none", dict(shape="fur", top=0.005)),
    ("waves360", ["360 Waves"], "none", dict(shape="fur", top=0.0055, capTile="waves", capTileRepeat=[1, 1])),
    ("fade_low", ["Low Fade"], "low", dict(shape="fade", fade_top=0.15, top=0.068)),
    ("fade_mid", ["Fade", "Mid Fade"], "mid", dict(shape="fade", fade_top=0.24, top=0.068)),
    ("fade_high", ["High Fade"], "high", dict(shape="fade", fade_top=0.32, top=0.07)),
    ("fade_taper", ["Taper Fade"], "taper", dict(shape="taper", side=0.02, top=0.066)),
    ("fade_burst", ["Burst Fade"], "burst", dict(shape="burst", side=0.02, top=0.068)),
    ("crew", ["Crew Cut"], "none", dict(shape="crew", side=0.012, top=0.082, crown=0.04)),
    ("caesar", ["Caesar Cut"], "none", dict(shape="caesar", side=0.016, top=0.03, card_len=(0.05, 0.07),
                                            root_min=0.6, tip_min=0.5)),
]
SHELL_CAP_STRAIGHT = 0.05  # straight / wavy tops: the shells carry this much, the cards the rest
SHELL_STEP_CURLY = 0.0105  # curly / coily tops: shells only, about this far apart
CURLY_SCALE = 0.92


def entries():
    out = []
    for key, styles, kind, spec in FAMILY:
        base = dict(spec, kind=kind)
        if spec["shape"] == "fur":
            out.append(dict(base, key=key, styles=styles, types=None, cards=0, material="Plastic"))
            continue
        out.append(dict(base, key=key, styles=styles, types=STRAIGHT, cards=480 if spec["shape"] != "caesar" else 540,
                        material="SmoothPlastic"))
        out.append(dict(base, key=key + "_c", styles=styles, types=CURLY, cards=0, scale=CURLY_SCALE,
                        material="Plastic"))
    return out


# =============================================================================================
# Checks: clearance, shell separation, the u seam
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
        r = {"skull_m": 9.0, "head_m": 9.0, "skull_f_fit": 9.0, "head_f_fit": 9.0, "skull_m_narrow_fit": 9.0}
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
            # the male skull 0.965x narrower, the mesh fitted by the runtime's ax = 0.965: distance along the ray
            Pn = P * self.narrow
            r["skull_m_narrow_fit"] = min(r["skull_m_narrow_fit"], min(
                float(np.linalg.norm(x - sk.c) - np.linalg.norm(
                    (sk.point(*Skull.angles((x - sk.c) / self.narrow)) - sk.c) * self.narrow)) for x in Pn))
        return {k: round(float(v), 4) for k, v in r.items()}


def bvh_of(piece):
    from mathutils.bvhtree import BVHTree
    return BVHTree.FromPolygons([tuple(map(float, p)) for p in piece.P], [tuple(t) for t in piece.T])


def separation(lower, upper):
    """the smallest gap between two stacked layers: every vertex of each to the other's surface (both ways, so
    a coarse layer's chord sag between its vertices counts too)"""
    from mathutils import Vector
    bl_, bu = bvh_of(lower), bvh_of(upper)
    lo_used = set(i for t in lower.T for i in t)
    up_used = set(i for t in upper.T for i in t)
    best = 9.0
    for i in up_used:
        loc, _, _, dist = bl_.find_nearest(Vector(tuple(upper.P[i])))
        if loc is not None:
            best = min(best, dist)
    for i in lo_used:
        loc, _, _, dist = bu.find_nearest(Vector(tuple(lower.P[i])))
        if loc is not None:
            best = min(best, dist)
    return round(best, 4)


def seam_check(piece):
    """the polar grid's u = 0 / u = 1 seam: every used seam vertex has its twin (same position) on the other side"""
    used = sorted(set(i for t in piece.T for i in t))
    P = np.asarray(piece.P)
    U = np.asarray(piece.U)[:, 0]
    a = [i for i in used if U[i] < 1e-6 and np.asarray(piece.U)[i, 1] > 1e-6]
    b = [i for i in used if U[i] > 1 - 1e-6]
    pa, pb = P[a] if a else np.zeros((0, 3)), P[b] if b else np.zeros((0, 3))
    miss = 0
    for x in pa:
        if len(pb) == 0 or np.min(np.linalg.norm(pb - x, axis=1)) > 1e-5:
            miss += 1
    for x in pb:
        if len(pa) == 0 or np.min(np.linalg.norm(pa - x, axis=1)) > 1e-5:
            miss += 1
    return {"u0": len(a), "u1": len(b), "unmatched": miss}


# =============================================================================================
# Self-check renders: the runtime's painted cap emulated (HK.PaintCap in numpy), Cycles via render.py
# =============================================================================================
HAIR_TINTS = {
    "black": (0.09, 0.08, 0.075),
    "darkbrown": (48 / 255, 33 / 255, 24 / 255),
    "blonde": (196 / 255, 156 / 255, 92 / 255),
}
# the cap's density per style (AnatomyHair's CapCut for these styles; coily hair a little denser)
DENSITY = {"buzz": 0.62, "waves360": 0.9}
CAP_FADE_K = 4  # HK.CAP_FADE_K


def tile_rank(tile8):
    """HK.TileRank: each texel's mid-rank by (alpha, grey)"""
    key = tile8[..., 3].astype(np.int64) * 256 + tile8[..., 0].astype(np.int64)
    flat = key.ravel()
    hist = np.bincount(flat, minlength=65536).astype(np.float64)
    below = np.cumsum(hist) - hist
    mid = (below + hist * 0.5) / flat.size
    return mid[key]


def paint_cap(ref, kind, tile_key, density, nu, nv, size=1024, shell=None, out=None):
    """HK.PaintCap in numpy (nearest tile sampling): the tile repeated nu x nv over the cap UV, alpha = tile alpha
    thresholded by its rank as the coverage falls (skull.json's Kit.Cut grid for the kind); a shell variant
    remaps the coverage below shell.cov to none and keeps only texels ranked above shell.rank"""
    tile8 = np.asarray(Image.open(os.path.join(TEX, f"hair_{tile_key}.png")).convert("RGBA"))
    rank = tile_rank(tile8)
    tile = tile8.astype(np.float64) / 255
    th_, tw_ = tile.shape[:2]
    j, i = np.mgrid[0:size, 0:size]
    u = (i + 0.5) / size
    v = (j + 0.5) / size
    c = np.clip(ref.grid_at(ref.cov[kind], v * THETA_MAX, u * TAU), 0, 1) * density
    sc, sr = (shell["cov"], shell["rank"]) if shell else (0.0, 0.0)
    if sc > 0:
        c = (c - sc) / (1 - sc)
    tu = ((u * nu * tw_) % tw_).astype(int)
    tv = ((v * nv * th_) % th_).astype(int)
    K = CAP_FADE_K
    inv = 1.0 / K
    t = np.where(c >= 1, -inv, (1 - c) * (1 + inv) - inv)
    t = np.maximum(t, sr) if sr > 0 else t
    q = np.clip((rank[tv, tu] - t) * K, 0, 1)
    keep = q * q * (3 - 2 * q)
    keep = np.where(c <= 0.002, 0.0, keep)
    g = tile[tv, tu, 0]
    a = tile[tv, tu, 3] * keep
    img = np.dstack([g, g, g, a])
    tag = f"_{sr:.2f}_{sc:.2f}" if shell else ""
    out = out or os.path.join(FAM_DIR, f"cap_{kind}_{tile_key}{tag}.png")
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(out)
    return out


def matte(ob):
    """Roblox Plastic / SmoothPlastic on short hair: a soft, low sheen (render.py's hair material is tuned for long
    glossy cards). Preview-only: a copy of the material per object."""
    m = ob.data.materials[0]
    if not m.name.endswith("#matte"):
        m2 = m.copy()
        m2.name = m.name[:50] + "#matte"
        ob.data.materials[0] = m2
        m = m2
    bs = m.node_tree.nodes["Principled BSDF"]
    bs.inputs["Roughness"].default_value = 0.75
    bs.inputs["Specular IOR Level"].default_value = 0.15
    try:
        bs.inputs["Anisotropic"].default_value = 0.0
    except KeyError:
        pass


VIEW_TOP = (0, 86, 1.05)  # straight down on the crown


def render_style(ref, e, pieces, capP, tint_name, views, res=(520, 620), samples=48, tag="", head="head_m",
                 standard=True):
    import render
    tint = HAIR_TINTS[tint_name]
    curly = e["types"] == CURLY
    tile_key = e.get("capTile") or ("shortcoil" if curly else "short")
    nu, nv = e.get("capTileRepeat") or TILE
    dens = DENSITY.get(e["key"], 1.0)
    capimg = paint_cap(ref, e["kind"], tile_key, min(1.0, dens), nu, nv)
    shells = {}
    for p in pieces:
        s = p.meta.get("capShell")
        if p.tex == "cap" and s:
            k = (s["rank"], s["cov"])
            if k not in shells:
                shells[k] = paint_cap(ref, e["kind"], tile_key, min(1.0, dens), nu, nv, size=512, shell=s)
    out = []
    for view in views:
        sc = render.Scene(res=res, samples=samples)
        if standard:
            sc.sc.view_settings.view_transform = "Standard"
            sc.sc.view_settings.look = "None"
        render.add_obj(sc, os.path.join(REF, f"{head}.obj"))
        matte(sc.add_piece(capP, texture=capimg, tint=tint))
        for p in pieces:
            if p.tex == "cap":
                s = p.meta.get("capShell")
                tex = shells[(s["rank"], s["cov"])] if s else capimg
            else:
                tex = os.path.join(TEX, f"hair_{p.tex}.png")
            matte(sc.add_piece(p, texture=tex, tint=tint))
        vname = view if isinstance(view, str) else "view"
        fn = os.path.join(FAM_DIR, f"{e['key']}{tag}_{tint_name}_{vname}.png")
        if view == "close":
            sc.render(fn, view="front", dist=1.75, focus=(0.0, 0.3, 0.0))
        elif view == "top":
            sc.render(fn, view=VIEW_TOP, focus=(0.0, 0.2, 0.05))
        elif view == "closeback":
            sc.render(fn, view="back", dist=1.75, focus=(0.0, 0.05, 0.1))
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
    return obj_from_arrays("RefHead (game head, nominal)", head.P, head.T)


def build_entry(e, cbs, capP, head, clr):
    reset_blend()
    add_head_obj(head)
    obj_from_arrays("HairCap (shared cap, out/cap)", np.asarray(capP.P), np.asarray(capP.T))
    spec = dict(e)
    t_full = profile(cbs, spec)
    if spec["shape"] == "fur":
        n, ts, name = 1, t_full, "HairFur"
    elif e["types"] == CURLY:
        n = max(2, int(math.ceil(float(t_full.max()) / SHELL_STEP_CURLY - 0.2)))
        ts, name = t_full, "HairTop"
    else:
        ts = np.minimum(t_full, SHELL_CAP_STRAIGHT)
        n = max(2, int(math.ceil(float(ts.max()) / 0.0105 - 0.2)))
        name = "HairTop"
    pieces, _ = build_shells(cbs, spec, name, n, ts, tufts=0.0015 if name == "HairFur" else (0.008 if e["types"] == CURLY else 0.005))
    if e.get("cards"):
        crop, _, ng = build_crop(cbs, spec, t_full, ts, seed=11 + len(e["key"]))
        if crop.nt:
            pieces.append(crop)
    assert len(pieces) <= 16
    checks = {"clearance": clr.measure(pieces)}
    sep = []
    lower = capP
    for p in pieces:
        if p.tex != "cap":
            continue
        sep.append(separation(lower, p))
        lower = p
    checks["separation"] = sep
    checks["seam"] = {p.name: seam_check(p) for p in pieces if p.tex == "cap"}
    entry = {"styles": e["styles"], "types": e["types"], "cap": {"cut": "style", "density": 1},
             "family": "fades", "checks": checks}
    for k in ("capTile", "capTileRepeat"):
        if e.get(k):
            entry[k] = e[k]
    for p in pieces:
        if p.tex == "cap":
            p.meta["material"] = e["material"]
    clean_out(e["key"])
    data = hairlib.export_style(e["key"], entry, pieces)
    save_blend(e["key"])
    return pieces, data, checks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--quick", action="store_true", help="renders: small, few samples")
    ap.add_argument("--only", default="")
    ap.add_argument("--skip-textures", action="store_true")
    ap.add_argument("--views", default="")
    ap.add_argument("--tint", default="")
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
    cbs = CapBase(ref, head, dth=4.2, nmax=48, fit=fit, margin=0.06)  # the shells' coarser grid (same UV mapping)
    print(f"cap grid: {len(cb.S)} verts, {len(cb.keepT)} tris kept; shell grid {len(cbs.keepT)} tris "
          f"({time.time() - t0:.1f}s)")

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
        if only and e["key"] not in only:
            continue
        t1 = time.time()
        pieces, data, checks = build_entry(e, cbs, capP, head, clr)
        report[e["key"]] = {"tris": data["tris"], "pieces": {p.name: [p.nt, p.meta.get("capShell")] for p in pieces},
                            **checks}
        print(f"{e['key']}: {len(pieces)} pieces, {data['tris']} tris, {checks} ({time.time() - t1:.1f}s)")
        built.append((e, pieces))
    print(f"build done in {time.time() - t0:.1f}s")
    with open(os.path.join(hairlib.OUT, "cap", "fades_report.json"), "w") as f:
        json.dump(report, f, indent=1)
    if not args.render:
        return report
    os.makedirs(FAM_DIR, exist_ok=True)
    import render
    tints = args.tint.split(",") if args.tint else ["black", "darkbrown", "blonde"]
    views = args.views.split(",") if args.views else ["34", "side", "back", "close", "top34", "top"]
    res, samples = ((300, 360), 16) if args.quick else ((520, 620), 48)
    for n, (e, pieces) in enumerate(built):
        tint = tints[n % len(tints)]
        paths = render_style(ref, e, pieces, capP, tint, views, res=res, samples=samples)
        out = os.path.join(FAM_DIR, f"sheet_{e['key']}.jpg")
        render.sheet(paths, out, cols=len(paths), labels=list(views),
                     title=f"{e['key']}: {', '.join(e['styles'])} [{'/'.join(e['types']) if e['types'] else 'all types'}] "
                           f"{sum(p.nt for p in pieces)} tris (+ cap {capP.nt}), {tint}")
        print("sheet", out, flush=True)
    return report


if __name__ == "__main__":
    rep = main()
    print(json.dumps(rep, indent=1, default=str))
