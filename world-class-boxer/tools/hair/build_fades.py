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
pushed clear of the game's head mesh with a mathutils BVHTree. Each shell is the cap's own surface lifted along
the scalp normal by a height proportional to the style's hair height there (shell_heights), so the stack grows
with the fade's coverage over the whole fade band, comes down to the cap within HL_TAPER of the natural hairline
and round the ears, and never stands off the scalp as a ledge; where the hair is tall the shells are >= 0.0045
apart. The height profile (profile) is the cut's shape (top length where the scalp faces up, a wall length on the
sides, the weight line at each fade's FADE_TOP or the burst's arc round the ear) x the fade's coverage x the
hairline / ear taper. Clump unevenness comes from a Displace modifier (Clouds) read back through the depsgraph.
The shells thin outward in the game: each names a capShell { rank, cov } variant of the painted cap
(HairAssetKit.PaintCap: only the tile's higher-ranked texels; coverage below cov counts as none). The crop-top
cards are swept along Bezier guide curves (one curve object, evaluated by Blender) that follow a combed flow field
(forward and to one side on top, down the back, down and forward on the sides; the crew's front brushed up),
lifted 20-35 deg off the scalp and clipped to the style's smooth outer envelope.

The painted cap's crown (cap style.json "pole"): below ~40 deg from the crown the tile is sampled by a planar
projection (no 8-spoke star from the polar UV's wedges); the runtime change is fades_paintcap_pole.diff
(HairAssetKit.PaintCap's pole argument, HK.CapPole), tested by fades_test_pole.luau, mirrored by paint_cap here.
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
SHELL_SEP = 0.0052  # gap between a shell and the layer under it, along the scalp normal (>= 0.004: no z-fighting)
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
        # a lightly blurred copy (the shells' height ramps follow the fade band itself)
        self.covr = {k: self._blur(v, 0.8) for k, v in self.cov.items()}
        self._hl_kd = None
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

    def dist_to_hairline(self, P):
        """each point's distance to the natural hairline (0 for points outside it): a KD tree of the skull's points
        just outside the natural hairline (1 x 2 deg grid)"""
        from mathutils import Vector
        from mathutils.kdtree import KDTree
        if self._hl_kd is None:
            pts = []
            for th in np.radians(np.arange(4, 150, 1.0)):
                for az in np.radians(np.arange(0, 360, 2.0)):
                    p = self.sk.point(th, az, 0.0)
                    if not self.inside(p, 0.0, which="nat"):
                        pts.append(p)
            kd = KDTree(len(pts))
            for i, p in enumerate(pts):
                kd.insert(Vector(tuple(p)), i)
            kd.balance()
            self._hl_kd = kd
        out = np.zeros(len(P))
        for i, p in enumerate(P):
            if self.inside(p, 0.0, which="nat"):
                out[i] = self._hl_kd.find(Vector(tuple(p)))[2]
        return out

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
        if not out and not self.inside_parity(p):
            # (the nearest face's normal lies about points over a fold, e.g. above an ear's top: confirmed by ray
            # parity that the point is outside)
            out = True
        return dist if out else -dist

    def inside_parity(self, p):
        from mathutils import Vector
        votes = 0
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0, -1)):
            o, dv, hits = Vector(tuple(p)), Vector(d), 0
            for _ in range(40):
                loc, _, _, _ = self.bvh.ray_cast(o, dv)
                if loc is None:
                    break
                hits += 1
                o = loc + dv * 1e-5
            votes += hits % 2
        return votes >= 3


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
        # the shells' lift direction: the scalp normal (so stacked shells keep their gap where the skull slopes),
        # blended into the radial ray round the crown's pole (every pole-fan vertex then moves alike: no pinhole)
        w = np.clip(1.0 - th / 0.18, 0, 1)[:, None]
        Dn = N * (1 - w) + D * w
        self.Dn = Dn / np.linalg.norm(Dn, axis=1, keepdims=True)
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
        # distance (over the scalp, chord) inside the natural hairline: the shells taper to the cap over its last
        # ~3.5 cm (no lip at the front edge or the temple corners); 0 outside it
        self.dist_hl = ref.dist_to_hairline(S)
        self.covr = {k: ref.grid_at(g, th, az) for k, g in ref.covr.items()}

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
    P = cap_layer(cb)
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
        # CAP_OFF along the skull ray, a little more toward the sides: on a 0.965x narrower skull (the female fit,
        # ax = 0.965) a sideways offset shrinks with the width, and it must still be >= CLEAR there
        k = np.linalg.norm(cb.D * np.array([0.965, 1.0, 1.0]), axis=1)
        cb._capP = cb.layer(CAP_OFF / k + 0.0001)
    return cb._capP


# =============================================================================================
# Fur shells (tex "cap"): the cap's surface lifted, sparser outward (capShell variants of the painted cap)
# =============================================================================================
# the painted cap's variants the shells use (at most 4 per entry: each costs one half-size image per boxer). The
# coverage floors are low: down a fade every shell thins with the cap over the whole band (the shells' own height
# converges there, so they never stand off the scalp where the hair is short); outer shells only a little sooner
VAR_1 = {"rank": 0.0, "cov": 0.12}  # the inner shells: the cap's own strands
VAR_A = {"rank": 0.25, "cov": 0.25}
VAR_B = {"rank": 0.42, "cov": 0.38}
VAR_C = {"rank": 0.58, "cov": 0.5}
# a buzz / waves cut's one fur shell: its UV shifted 4 cap texels across the strands (u), so its hairs fall between
# the cap's (the stubble reads denser and even, not the same strands twice). (u up to 1.004 at the seam: the
# texture wraps; were it clamped, a 0.4 % strip would show the edge texel)
VAR_FUR = {"rank": 0.3, "cov": 0.0, "shift": [0.004, 0.0]}


def shell_variant(k, n):
    """the painted cap's variant shell k of n draws with: sparser outward (only the tile's higher-ranked texels: the
    tips), the coverage floor a little higher outward"""
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


HL_TAPER = 0.035  # the shells come down to the cap over this distance inside the natural hairline


def profile(cb, spec):
    """the style's hair height above the cap (studs) at every grid vertex. Three factors, each smooth:
    * the cut's shape H: the top's length on the crown and the top (by the scalp normal's up component: so the
      side walls carry only the shorter wall length, no mushroom overhang), the wall length on the sides above the
      fade (the burst keeps a longer back, the crew none: sides cap-only), a slight dome;
    * the fade g: a smoothstep of the cut's own coverage (Kit.Cut grid for its kind, lightly blurred), so the
      volume grows over the whole fade band, from the skin up to the fade top, with the painted cap;
    * the hairline taper e: down to the cap over HL_TAPER inside the natural hairline (front, temples, nape)."""
    kind = spec["kind"]
    S, N = cb.S, cb.N
    x, y, z = S[:, 0], S[:, 1], S[:, 2]
    ny = N[:, 1]
    shape = spec["shape"]
    T = spec["top"]
    e = sstep(0.0, HL_TAPER, cb.dist_hl) ** 0.8
    # and down to the cap round the ears (the stack slopes in behind and above each ear, never cut off there)
    de = np.full(len(S), 9.0)
    for lo, hi in cb.ref.ears:
        dd = np.linalg.norm(np.maximum(np.maximum(lo - S, S - hi), 0.0), axis=1)
        de = np.minimum(de, dd)
    e = e * sstep(0.015, 0.075, de)
    c = np.clip(cb.covr[spec.get("capFade") or kind], 0, 1)
    g = sstep(0.02, 1.0, c) ** 0.9
    up = sstep(0.12, 0.72, ny)
    dome = 0.85 + 0.15 * sstep(0.2, 0.55, y)
    if shape == "fur":
        return np.full(len(S), T) * np.clip(e * 1.5, 0, 1) * spec.get("scale", 1.0)
    wall = spec.get("side", 0.032)
    if shape == "burst":
        # the back keeps its length: the burst's half-circle round each ear is the only fade
        wall = wall + (spec.get("back", wall) - wall) * sstep(0.05, 0.3, z)
    if shape == "crew":
        top = T * (1 - sstep(-0.38, 0.25, z)) + spec["crown"] * sstep(-0.38, 0.25, z)
        H = top * sstep(0.3, 0.8, ny)  # the parietal ridge: sides and back cap-only (clippered short)
    else:
        H = (wall + (T - wall) * up) * dome
        # the cut's weight line: below its FADE_TOP (skull.json) the sides are clippered short (SHORT_SIDE, the
        # runtime's own side length); the length grows in over ~0.12 above it (no shelf), so the low, mid and high
        # fades put their volume at clearly different heights. The burst's line is its arc round the ear (the back
        # keeps its length), the taper's sits low (full sides)
        ft = cb.ref.fade_top.get(kind)
        if ft is not None:
            if shape == "burst":
                r = np.sqrt((y - 0.01) ** 2 + (z - 0.02) ** 2)
                w = sstep(0.2, 0.34, np.abs(x)) * (1 - sstep(0.24, 0.42, z))
                ramp = 1 - w * (1 - sstep(0.15, 0.33, r))
            else:
                ramp = sstep(ft - 0.05, ft + 0.08, y)
            H = SHORT_SIDE + (H - SHORT_SIDE) * ramp
    t = H * g * e
    return np.maximum(t, 0.0) * spec.get("scale", 1.0)


SHORT_SIDE = 0.012


def shell_footprint(cb, spec):
    """the cap's footprint less the triangles where this style never has coverage (well below its fade: the
    shell's edge lies where the painted cap is already fully transparent)"""
    kind = spec.get("capFade") or spec["kind"]
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


SHELL_FLOOR = 0.0006  # the shells' smallest spacing (where the hair is ~0: at the hairline, the fade's bottom)
SHELL_BASE = 0.0035  # every shell at least this far over the cap (its own push-out and chord sag aside)


def shell_heights(t, k, n):
    """shell k's height above the cap: proportional to the hair's height (so the stack converges onto the cap where
    the hair is short: no step, no ledge), plus the coarse grid's sag. Where the hair is taller than n * 0.0045 the
    shells are >= 0.0045 apart; below that they close up, with the same tone (vertex colour by height, not by
    index) and the same texels (lean by height), so coincident shells draw alike"""
    return SHELL_SAG + SHELL_BASE + k * (t / n + SHELL_FLOOR)


def build_shells(cb, spec, name, n, ts, tufts=0.006, lean=0.9, seed=5):
    """n shells over the cap's own surface (shell_heights); a Displace modifier (Clouds, global coordinates:
    coherent through the stack) raises clumps, weighted by a vertex group that grows with k and with ts and is 0
    round the crown's pole. Shading normals wander a little by clump (no smooth helmet highlight); vertex colours
    darken toward the scalp (by height)."""
    bpy = bl()
    from mathutils import Vector, noise as mnoise
    Pc = cap_layer(cb)
    T0 = shell_footprint(cb, spec)
    tsmax = max(1e-6, float(ts.max()))
    # the outermost shell (plus its clumps) must clear the head mesh too: where it would run into an ear, no
    # shell at all (the same footprint for every shell of the stack: no edge between them)
    dmax = shell_heights(ts, n, n) + tufts
    bad = np.zeros(len(Pc), bool)
    for i in np.unique(T0.ravel()):
        q = Pc[i] + cb.Dn[i] * dmax[i]
        bad[i] = cb.head.signed(q) < CLEAR or cb.ref.in_ear(q, 0.01)
    T0 = T0[~bad[T0].any(axis=1)]
    tex = bpy.data.textures.get("TuftNoise") or bpy.data.textures.new("TuftNoise", "CLOUDS")
    tex.noise_scale = 0.04
    tex.noise_depth = 2
    tex.noise_basis = "BLENDER_ORIGINAL"
    tex.contrast = 1.3
    pieces, obs = [], []
    material = spec.get("material", "Plastic")
    lean_w = sstep(0.5, 0.9, cb.th)  # (no lean round the crown: the painter samples it flat, POLE)
    for k in range(1, n + 1):
        d = shell_heights(ts, k, n)
        P = Pc + cb.Dn * d[:, None]
        T = orient_outward(P, T0, cb.ref.sk.c)
        T2, (P2, N2, U2, V2, t2, d2, th2, D2, lw2) = compact(T, P, cb.N, cb.U, cb.V, ts, d, cb.th, cb.Dn, lean_w)
        nm = f"{name}{k}" if n > 1 else name
        ob = obj_from_arrays(nm, P2, T2)
        PE = P2
        if tufts > 0:
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
        var = shell_variant(k, n) if spec.get("shell_var") is None else spec["shell_var"]
        piece = Piece(nm, "cap", material=material, castShadow=False)
        if var:
            piece.meta["capShell"] = {kk: vv for kk, vv in var.items() if kk != "shift"}
        su, sv = (var or {}).get("shift", (0.0, 0.0))
        for i in range(len(PE)):
            hgt = d2[i] - SHELL_SAG - SHELL_BASE
            q = Vector(tuple(PE[i] * 70.0))
            nv = np.array(mnoise.noise_vector(q))
            amp = float(np.clip(t2[i] / tsmax, 0, 1)) * float(np.clip(hgt / 0.03, 0, 1))
            nn = N2[i] + nv * spec.get("nrm_noise", 0.16) * amp
            # occlusion by height above the cap (shells that close up keep one tone), a little clump variation
            occ = 0.72 + 0.28 * float(sstep(0.0, 0.075, hgt))
            c = occ * (1 - 0.1 * amp * (0.5 + 0.5 * mnoise.noise(Vector(tuple(PE[i] * 14.0 + 3.1)))))
            # the hair leans back: the shell shows the cap's texels from nearer the crown (strands lie along +v)
            # (never more than half its v: round the crown no texel row collapses onto the pole's)
            vv = V2[i] - min(0.5 * V2[i], lean * hgt * lw2[i] / (0.45 * THETA_MAX))
            uu = U2[i] + su
            piece.vert(PE[i], nn, (uu, vv + sv * lw2[i]), (c, c, c, 1.0))
        for tt in T2:
            piece.T.append(tuple(int(x) for x in tt))
        piece._t = t2 / n  # (the nominal spacing to the layer below at each vertex: the separation check)
        piece._shift = su
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

    from mathutils import Vector
    from mathutils.kdtree import KDTree
    kd = KDTree(len(cb.S))
    for j, s in enumerate(cb.S):
        kd.insert(Vector(tuple(s)), j)
    kd.balance()

    def t_at(q):
        """the profile at a scalp point: inverse-distance blend of the 4 nearest grid vertices (smooth envelope)"""
        hits = kd.find_n(Vector(tuple(q)), 4)
        w = np.array([1.0 / (h[2] + 0.004) ** 2 for h in hits])
        idx = [h[1] for h in hits]
        w /= w.sum()
        return float((t_full[idx] * w).sum()), float((t_shell[idx] * w).sum())

    nwant = spec.get("cards", 500)
    # (denser toward the top region's edge, where the cards are shorter: no sparse spikes on the silhouette)
    wsel = 1.0 + 1.2 * (1 - np.clip(t_full[cand] / peak, 0, 1))
    wsel /= wsel.sum()
    crew = spec["shape"] == "crew"
    sweep = np.array([0.27, 0.0, -1.0]) / math.hypot(0.27, 1.0)  # the comb: forward, a little to the right
    guides = []
    tries = 0
    while len(guides) < nwant and tries < nwant * 30:
        tries += 1
        i = int(rng.choice(cand, p=wsel))
        th = cb.th[i] + rng.normal(0, 0.014)
        az = cb.az[i] + rng.normal(0, 0.035)
        p = sk.point(th, az, 0.0)
        n = sk.normal(max(th, 0.03), az)
        grow = sk.point(th + 0.02, az, 0.0) - p
        grow /= np.linalg.norm(grow) + 1e-9
        # a combed flow field, not radial from the crown: the top combed forward and to one side; behind and below
        # the crown it falls down the back; on the sides down and forward along the head
        wb = smoothstep(0.08, 0.3, p[2]) * smoothstep(0.6, 0.38, p[1])
        ws = smoothstep(0.2, 0.34, abs(p[0])) * (1 - wb)
        down_fwd = grow + np.array([0, 0, -0.6])
        flow = sweep * (1 - wb - ws) + grow * wb + down_fwd * ws
        flow -= n * np.dot(flow, n)
        flow /= np.linalg.norm(flow) + 1e-9
        side = np.cross(n, flow)
        flow = flow + side * rng.normal(0, 0.12)
        flow /= np.linalg.norm(flow)
        tf0, ts0 = t_at(p)
        tfrac = float(np.clip(tf0 / peak, 0, 1))
        lo, hi = spec.get("card_len", (0.045, 0.085))
        L = (lo + (hi - lo) * tfrac ** 1.5) * rng.uniform(0.85, 1.1)
        # lift off the scalp: 20-35 deg (the crew's front brushed up: up to ~50 deg at the hairline)
        lift = math.radians(rng.uniform(20, 35))
        fr = 0.0
        if crew:
            fr = smoothstep(0.08, 0.0, float(cb.dist_hl[i])) * smoothstep(-0.15, -0.32, p[2])
            lift = lift * (1 - fr) + math.radians(rng.uniform(40, 52)) * fr
            if fr > 0.3:
                flow = flow * 0.6 + n * 0.0 + np.array([0, 0, -0.4])
                flow -= n * np.dot(flow, n)
                flow /= np.linalg.norm(flow) + 1e-9
        if caesar:
            lift = math.radians(rng.uniform(8, 16))
        root_h = CAP_OFF + rng.uniform(0.35, 0.65) * ts0
        # march over the scalp along the flow
        qs = [p.copy()]
        q = p.copy()
        ns = 3
        for s in range(ns):
            _, _, nq = surface_frame(sk, q)
            fl = flow - nq * np.dot(flow, nq)
            fl /= np.linalg.norm(fl) + 1e-9
            q = sk.point(*Skull.angles(q + fl * L / ns - sk.c), 0.0)
            qs.append(q.copy())
        tip = qs[-1]
        tft, _ = t_at(tip)
        if not ref.inside(tip, -0.02, which="min"):
            continue
        if tft < peak * spec.get("tip_min", 0.3):
            continue
        tip_h = root_h + L * math.tan(lift)
        pts = []
        for s, x in enumerate(qs):
            f = s / (len(qs) - 1)
            th_q, az_q, _ = surface_frame(sk, x)
            h = root_h + (tip_h - root_h) * math.sin(f * math.pi / 2) ** 0.85
            # the smooth outer envelope: the style's own top profile, at most ~8 mm... 0.008 past it
            tq, _ = t_at(x)
            h = min(h, CAP_OFF + tq + 0.003 + 0.004 * f + 0.02 * fr * f)  # (the crew's front stands up)
            pts.append(sk.point(th_q, az_q, max(h, CLEAR + 0.003)))
        guides.append((np.array(pts), root_h, False))
    if caesar:
        guides += caesar_fringe(cb, spec, t_shell, rng)
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
        # (3 points a tuft, 4 for the fringe's longer, curving cards: 8 / 12 triangles each)
        idx = np.linspace(0, per - 1, 4 if guides[g][2] else 3).round().astype(int)
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
        w0 = rng.uniform(0.016, 0.026) if not guides[g][2] else rng.uniform(0.022, 0.032)
        taper = 0.08 if guides[g][2] else 0.3  # (the fringe is cut blunt: nearly as wide at its tip)
        npt = len(pts)
        widths = [w0 * (1.0 - taper * (i / (npt - 1)) ** 1.5) for i in range(npt)]
        # (strip 0 is the blunt-cut tuft: the Caesar's fringe and much of its top; the others end in points)
        # (the fringe: mostly the blunt tuft, some pointed ones, so its line is soft, not a broom)
        if guides[g][2]:
            s = 0 if rng.random() < 0.65 else int(rng.integers(1, CROP_STRIPS))
        else:
            s = 0 if (caesar and rng.random() < 0.4) else int(rng.integers(1, CROP_STRIPS))
        # occlusion: dark at the root (inside the shells), the tips no brighter than the outer shell's own tone
        base, tipv = rng.uniform(0.58, 0.7), rng.uniform(0.8, 0.9)
        if guides[g][2]:
            base = rng.uniform(0.45, 0.55)  # (the fringe's roots sink into the shells' shade)
        # (a mix of facings: flat tufts read from above, turned ones from the side, so no view sees only card
        # edges; the fringe stays flat over the forehead)
        tw = rng.normal(0, 0.08) if guides[g][2] else rng.uniform(-0.35, 0.35)
        piece.card(list(pts), widths, ups, (s / CROP_STRIPS, (s + 1) / CROP_STRIPS),
                   shade=lambda t, b=base, c=tipv: (b + (c - b) * t,) * 3, twist=[tw] * npt)
    return piece, gob, len(guides)


def caesar_fringe(cb, spec, t_shell, rng):
    """The Caesar's fringe: tufts combed straight forward over the front, rooted ~1.5 cm behind the hairline and
    ending on one straight line across the forehead (FRINGE_Y, just under the natural hairline: about 6 mm at the
    centre; never lower than 0.022 under the hairline toward the temples), lying close over the cap and the brow
    edge. Each guide runs at a near-constant azimuth (the comb direction is straight forward, a slight sway)."""
    ref, sk = cb.ref, cb.ref.sk
    nf = int(spec.get("fringe_cards", 120))

    def y_at(th, az):
        return float(sk.point(th, az, 0.0)[1])

    def theta_for_y(az, y):
        lo, hi = 0.2, 1.6  # y falls as theta grows at the front
        for _ in range(40):
            m = (lo + hi) / 2
            if y_at(m, az) > y:
                lo = m
            else:
                hi = m
        return (lo + hi) / 2

    out = []
    tries = 0
    while len(out) < nf and tries < nf * 6:
        tries += 1
        az = math.pi + rng.uniform(-0.78, 0.78)
        p_hl = sk.point(theta_for_y(az, 0.3), az, 0.0)
        hl = float(np.interp(ref.da_of(p_hl), ref.hl_da, ref.hl_nat))
        yf = min(FRINGE_Y, hl - 0.022) + rng.uniform(-0.004, 0.004)  # (the blunt line a little staggered)
        th_tip = theta_for_y(az, yf)
        R = float(np.linalg.norm(sk.point(th_tip, az, 0.0) - sk.c))
        arc = rng.uniform(0.07, 0.1)
        th_root = th_tip - arc / R
        sway = rng.normal(0, 0.035)
        pts = []
        j = int(np.argmin(((cb.S - sk.point(th_root, az, 0.0)) ** 2).sum(1)))
        root_h = CAP_OFF + rng.uniform(0.45, 0.75) * float(t_shell[j])
        tip_h = CAP_OFF + 0.0035 + rng.uniform(0, 0.003)
        bulge = rng.uniform(0.004, 0.008)
        for f in np.linspace(0, 1, 4):
            th = th_root + (th_tip - th_root) * f
            a2 = az + sway * f
            h = root_h + (tip_h - root_h) * f ** 1.5 + bulge * math.sin(f * math.pi)
            pts.append(sk.point(th, a2, max(h, CLEAR + 0.003)))
        out.append((np.array(pts), root_h, True))
    return out


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
    ("buzz", ["Buzz Cut"], "none", dict(shape="fur", top=0.006)),
    ("waves360", ["360 Waves"], "none", dict(shape="fur", top=0.0055, capTile="waves", capTileRepeat=[1, 1])),
    # (heights in nominal studs above the cap: 0.052 ~ 1 cm on a 1.2-stud, ~23 cm head). side: the wall length on
    # the sides above the fade (the top's length only where the scalp faces up): the low fade keeps the fullest
    # sides, the high fade the least (a boxier top)
    ("fade_low", ["Low Fade"], "low", dict(shape="fade", top=0.088, side=0.036)),
    ("fade_mid", ["Fade", "Mid Fade"], "mid", dict(shape="fade", top=0.088, side=0.03)),
    ("fade_high", ["High Fade"], "high", dict(shape="fade", top=0.094, side=0.024)),
    ("fade_taper", ["Taper Fade"], "taper", dict(shape="taper", side=0.04, top=0.084)),
    ("fade_burst", ["Burst Fade"], "burst", dict(shape="burst", side=0.03, back=0.052, top=0.088)),
    # the crew: brushed up at the front, flat toward the crown, sides and back cap-only below the parietal ridge,
    # the sides and back tapered (capFade "fade": the runtime paints its cap with Kit.FADES.fade's coverage, a
    # gradient from the ear top / nape up to y 0.21 / 0.08 that leaves 12 % at the hairline: clippered, not skin)
    ("crew", ["Crew Cut"], "none", dict(shape="crew", top=0.1, crown=0.056, capFade="fade")),
    ("caesar", ["Caesar Cut"], "none", dict(shape="caesar", side=0.026, top=0.05, card_len=(0.05, 0.075),
                                            root_min=0.55, tip_min=0.45, fringe_cards=170)),
]
SHELL_CAP_STRAIGHT = 0.07  # straight / wavy tops: the shells carry this much (the silhouette), the cards the rest
SHELL_STEP_STRAIGHT = 0.0135
SHELL_STEP_CURLY = 0.0105  # curly / coily tops: shells only, about this far apart
CURLY_SCALE = 0.92


def entries():
    out = []
    for key, styles, kind, spec in FAMILY:
        base = dict(spec, kind=kind)
        if spec["shape"] == "fur":
            out.append(dict(base, key=key, styles=styles, types=None, cards=0, material="Plastic"))
            continue
        out.append(dict(base, key=key, styles=styles, types=STRAIGHT, cards=540 if spec["shape"] != "caesar" else 360,
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


def separation(lower, upper, min_step=None):
    """the smallest gap between two stacked layers: every vertex of each to the other's surface (both ways, so
    a coarse layer's chord sag between its vertices counts too). min_step: only the upper layer's vertices whose
    nominal spacing (upper._t) is at least this (where the hair is tall enough for the shells to stand apart)"""
    from mathutils import Vector
    bl_, bu = bvh_of(lower), bvh_of(upper)
    up_used = set(i for t in upper.T for i in t)
    lo_used = set(i for t in lower.T for i in t)
    if min_step is not None:
        up_used = set(i for i in up_used if upper._t[i] >= min_step)
        lo_used = set()
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
    U = np.asarray(piece.U)[:, 0] - getattr(piece, "_shift", 0.0)
    a = [i for i in used if U[i] < 1e-6 and np.asarray(piece.U)[i, 1] > 1e-6]
    b = [i for i in used if U[i] > 1 - 1e-6 and np.asarray(piece.U)[i, 1] > 1e-6]
    pa, pb = P[a] if a else np.zeros((0, 3)), P[b] if b else np.zeros((0, 3))
    # outer-border corners: a seam vertex on a border edge running off the seam (the footprint's own edge,
    # where the painted cap is already transparent) may lack its twin without opening a crack
    from collections import Counter
    ec = Counter()
    for t in piece.T:
        for e in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            ec[tuple(sorted(e))] += 1
    corner = set()
    for (i, j), c in ec.items():
        if c == 1:
            for x, y in ((i, j), (j, i)):
                if 1e-6 < U[y] < 1 - 1e-6:
                    corner.add(x)
    miss = corner_miss = 0
    miss_v = []
    for i, x in zip(a, pa):
        if len(pb) == 0 or np.min(np.linalg.norm(pb - x, axis=1)) > 1e-5:
            if i in corner:
                corner_miss += 1
            else:
                miss += 1
                miss_v.append(round(float(np.asarray(piece.U)[i, 1]), 3))
    for i, x in zip(b, pb):
        if len(pa) == 0 or np.min(np.linalg.norm(pa - x, axis=1)) > 1e-5:
            if i in corner:
                corner_miss += 1
            else:
                miss += 1
                miss_v.append(round(float(np.asarray(piece.U)[i, 1]), 3))
    out = {"u0": len(a), "u1": len(b), "unmatched": miss, "border_corner": corner_miss}
    if miss_v:
        out["unmatched_v"] = miss_v  # (v of each: where on the cap)
    return out


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


# The crown pole: the polar UV squeezes the tile's nu repeats into wedges round theta = 0 (an 8-spoke star from
# above). Below POLE[1] the painter samples the tile by an azimuthal-equidistant (planar) projection of the
# texel's scalp direction instead, (X, Z) = theta * (sin az, cos az), one tile spanning (su, sv) radians, and
# crossfades to the polar sampling between POLE[0] and POLE[1] (smoothstep). su matches the polar tile's width at
# the crossfade's middle (2 pi / nu * sin 32.5 deg) and sv its height (thetaMax / nv), so the strands keep their
# size through the blend. Only for tiled caps (nu > 1: the waves' whole-cap image has its own calm crown).
POLE = (math.radians(25.0), math.radians(40.0))


def pole_spec(nu=TILE[0], nv=TILE[1]):
    return {"theta0": round(POLE[0], 5), "theta1": round(POLE[1], 5),
            "su": round(TAU / nu * math.sin((POLE[0] + POLE[1]) / 2), 5), "sv": round(THETA_MAX / nv, 5)}


def _bilinear(tile, rank, tu, tv):
    """the runtime's tile sample (PaintCap: bilinear, wrapping, texel centres at +0.5): grey, alpha, rank"""
    th_, tw_ = tile.shape[:2]
    tu = (tu - 0.5) % tw_
    tv = (tv - 0.5) % th_
    x0 = np.floor(tu).astype(int)
    y0 = np.floor(tv).astype(int)
    fx, fy = tu - x0, tv - y0
    x1, y1 = (x0 + 1) % tw_, (y0 + 1) % th_
    w = [(1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy]
    idx = [(y0, x0), (y0, x1), (y1, x0), (y1, x1)]
    g = sum(wi * tile[yy, xx, 0] for wi, (yy, xx) in zip(w, idx))
    a = sum(wi * tile[yy, xx, 3] for wi, (yy, xx) in zip(w, idx))
    r = sum(wi * rank[yy, xx] for wi, (yy, xx) in zip(w, idx))
    return g, a, r


def paint_cap(ref, kind, tile_key, density, nu, nv, size=1024, shell=None, out=None, pole=True):
    """HK.PaintCap in numpy (bilinear tile sampling, plus the crown's planar sampling: POLE / pole_spec): the
    tile repeated nu x nv over the cap UV, alpha = tile alpha thresholded by its rank as the coverage falls
    (skull.json's Kit.Cut grid for the kind); a shell variant remaps the coverage below shell.cov to none and
    keeps only texels ranked above shell.rank"""
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
    g, al, rk = _bilinear(tile, rank, u * nu * tw_, v * nv * th_)
    if pole and nu > 1:
        ps = pole_spec(nu, nv)
        th = v * THETA_MAX
        az = u * TAU
        wp = 1 - sstep(ps["theta0"], ps["theta1"], th)
        m = wp > 0
        X, Z = th[m] * np.sin(az[m]), th[m] * np.cos(az[m])
        g2, a2, r2 = _bilinear(tile, rank, X / ps["su"] * tw_, Z / ps["sv"] * th_)
        w = wp[m]
        g[m] = g[m] * (1 - w) + g2 * w
        al[m] = al[m] * (1 - w) + a2 * w
        rk[m] = rk[m] * (1 - w) + r2 * w
    K = CAP_FADE_K
    inv = 1.0 / K
    t = np.where(c >= 1, -inv, (1 - c) * (1 + inv) - inv)
    t = np.maximum(t, sr) if sr > 0 else t
    q = np.clip((rk - t) * K, 0, 1)
    keep = q * q * (3 - 2 * q)
    keep = np.where((c >= 1) & (sr <= 0), 1.0, keep)
    keep = np.where(c <= 0.002, 0.0, keep)
    a = al * keep
    img = np.dstack([g, g, g, a])
    tag = f"_{sr:.2f}_{sc:.2f}" if shell else ""
    out = out or os.path.join(FAM_DIR, f"cap_{kind}_{tile_key}{tag}{'' if pole else '_nopole'}.png")
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(out)
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
    bs.inputs["Specular IOR Level"].default_value = 0.1
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
    kind = e.get("capFade") or e["kind"]
    capimg = paint_cap(ref, kind, tile_key, min(1.0, dens), nu, nv)
    shells = {}
    for p in pieces:
        s = p.meta.get("capShell")
        if p.tex == "cap" and s:
            k = (s["rank"], s["cov"])
            if k not in shells:
                shells[k] = paint_cap(ref, kind, tile_key, min(1.0, dens), nu, nv, size=512, shell=s)
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
        n = max(2, int(math.ceil(float(ts.max()) / SHELL_STEP_STRAIGHT - 0.2)))
        name = "HairTop"
    if e["types"] == STRAIGHT:
        spec["nrm_noise"] = 0.07  # (straight crops: a smoother sheen under the combed cards, no cauliflower)
    pieces, _ = build_shells(cbs, spec, name, n, ts, tufts=0.0 if name == "HairFur" else (0.006 if e["types"] == CURLY else 0.0012))
    if e.get("cards"):
        crop, _, ng = build_crop(cbs, spec, t_full, ts, seed=11 + len(e["key"]))
        if crop.nt:
            pieces.append(crop)
    assert len(pieces) <= 16
    checks = {"clearance": clr.measure(pieces)}
    sep, sep_tall = [], []
    lower = capP
    for p in pieces:
        if p.tex != "cap":
            continue
        sep.append(separation(lower, p))
        if lower is not capP and (p._t >= 0.0045).any():
            sep_tall.append(separation(lower, p, min_step=0.0045))
        lower = p
    checks["separation"] = sep  # (everywhere: the stack closes up where the hair is short, by design)
    checks["separation_tall"] = sep_tall  # (where the hair's height gives the shells >= 0.0045 nominal spacing)
    checks["seam"] = {p.name: seam_check(p) for p in pieces if p.tex == "cap"}
    entry = {"styles": e["styles"], "types": e["types"], "cap": {"cut": "style", "density": 1},
             "family": "fades", "checks": checks}
    for k in ("capTile", "capTileRepeat", "capFade"):
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
    ap.add_argument("--no-compare", action="store_true", help="renders: skip the fade-heights comparison sheets")
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
    cbs = CapBase(ref, head, dth=5.0, nmax=40, fit=fit, margin=0.06)  # the shells' coarser grid (same UV mapping)
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
        # the crown's planar sampling (PaintCap, tiled caps only): see POLE / fades_paintcap_pole.diff
        "pole": pole_spec(),
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
    # every fade height side by side, same tint and angles (a viewer should rank them at a glance)
    if not args.no_compare:
        byk = {e["key"]: (e, pieces) for e, pieces in built}
        for suffix, label in (("_c", "Curly/Kinky/Coiled"), ("", "Straight/Wavy")):
            keys = [k + suffix for k in ("fade_low", "fade_mid", "fade_high", "fade_taper", "fade_burst")]
            if not all(k in byk for k in keys):
                continue
            paths, labels = [], []
            for cv in ("side", "back"):
                for k in keys:
                    e, pieces = byk[k]
                    paths += render_style(ref, e, pieces, capP, "black", [cv], res=res, samples=samples, tag="_cmp")
                    labels.append(f"{e['styles'][-1]} {cv}")
            out = os.path.join(FAM_DIR, f"sheet_heights{suffix}.jpg")
            render.sheet(paths, out, cols=len(keys), labels=labels, title=f"fade heights side by side [{label}], black")
            print("sheet", out, flush=True)
    return report


if __name__ == "__main__":
    rep = main()
    print(json.dumps(rep, indent=1, default=str))
