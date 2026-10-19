"""The stylised clump hair (v10): chunky, intentional low-poly clumps on the classic head (Blender's Python, numpy):

    /opt/bpyenv/bin/python tools/hair/build_stylised.py [--only key,key] [--texture]

The user's reference sheet ("Boxer hair collection": low taper, 360 waves, twists, short locs, cornrows, afro) as
game meshes in the asset-hair contract (CONTRACT.md), modelled on the game's classic head (hairlib.REF = ref/classic:
the rounded cylinder r 0.6, half height 0.6, edges rounded 0.24; the built face's ears and brows):

* fade_taper_c (Taper Fade, curly types: the LOW TAPER) - a compact top of faceted curl knots (subdivided octahedra,
  jittered) over a dark base shell, inside the natural hairline above a low weight line; the sides and the nape are
  the scalp cap painted with the game's own taper (cap cut "style"), the front a crisp line on the hairline.
  The other curly fades (fade_low_c, fade_mid_c, fade_high_c, fade_burst_c, crew_c, caesar_c) are the same top with
  their own weight lines and heights.
* waves360 (360 Waves) - a close scalp shell sculpted with the waves' own ridges (fades_tex.waves_field: the ridge
  field the painted waves image is made of), rows laid along the ridges (trough, crest, back slope), on the cap's
  polar UV (tex "cap": the game paints it with the cap's image, so the fade and the hairline follow every look);
  the sides faded low (capFade "low").
* twists (Twists) - short chunky two-strand twists (a two-lobed section turning along the twist, smooth shaded) rooted
  over the top, standing out and falling a little, capped rounded ends; the front ones stop above the brows; the
  sides tapered (capFade "taper").
* short_dreads (Short Dreads: the SHORT LOCS) - fewer, thicker, irregular faceted locs in stacked segments that drape
  down round the forehead, the temples, over the ears and the back (a heavier, hanging silhouette than the twists'),
  the front ones ending above the brows (eyes clear).
* cornrows (Cornrows) - thick plaited rows (alternating faceted lobes: a herringbone) laid front to back along
  latitudes round the head's left-right axis (they fan round above the ears like the reference), skin channels
  between them, the rear ends tapering and tucked under at the nape.
* afro / afro_curly (Afro) - a compact rounded volume of large faceted clumps over a base shell that comes down to the
  scalp at a clean hairline (no floating shell), the temples tapered (capFade "taper"). Region pieces carry
  length "volume" (the volume slider), the base is fixed.
* hightop (High Top) - the afro's clumps on a flat-topped box.

Every vertex is kept >= CLEAR above the classic head and EAR_CLEAR outside the ears' ellipsoids (check_classic_fit.py
measures both). Textures: hair_clump.png (a greyscale, tileable fibre mottle; v runs root -> tip so the game's dyes
by v - Tips, Ombre - still work) for every clump piece; the waves shell is tex "cap". Vertex colours carry baked
occlusion (deep = dark). Output: out/<key>/ (meshes + style.json), like the other builders.
"""
import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import hairlib as hl  # noqa: E402
from hairlib import Piece  # noqa: E402
import build_fades as bf  # noqa: E402
import check_classic_fit as ccf  # noqa: E402
import fades_tex  # noqa: E402

TAU = 2 * math.pi
C = np.array([0.0, 0.05, 0.0])  # the cap's polar centre on the classic head
CLEAR = 0.017  # every vertex at least this far outside the head (nominal)
EAR_CLEAR = 0.014
CAP_H = 0.02  # the painted cap's height
HIDE = {"headgear": True, "hood": True}
TEX_PATH = os.path.join(HERE, "textures", "hair_clump.png")
THETA_MAX = bf.THETA_MAX


# ============================================================================== the classic head
def sd(P):
    return ccf.sd_classic(np.atleast_2d(P))


def grad(fn, P, e=1e-4):
    P = np.atleast_2d(P)
    g = np.zeros_like(P)
    for k in range(3):
        d = np.zeros(3)
        d[k] = e
        g[:, k] = (fn(P + d) - fn(P - d)) / (2 * e)
    n = np.linalg.norm(g, axis=1, keepdims=True)
    return g / np.maximum(n, 1e-9)


def head_n(P):
    return grad(sd, P)


def ear_d(P):
    return ccf.ear_dist(np.atleast_2d(P))


def dirs(th, az):
    th, az = np.asarray(th, np.float64), np.asarray(az, np.float64)
    s = np.sin(th)
    return np.stack([s * np.sin(az), np.cos(th), s * np.cos(az)], -1)


def angles(P):
    d = np.atleast_2d(P) - C
    r = np.linalg.norm(d, axis=1)
    th = np.arccos(np.clip(d[:, 1] / np.maximum(r, 1e-9), -1, 1))
    az = np.arctan2(d[:, 0], d[:, 2]) % TAU
    return th, az


def ray_hit(D):
    """the classic head's surface along rays from C (D: unit directions (n, 3))"""
    D = np.atleast_2d(D)
    lo = np.zeros(len(D))
    hi = np.full(len(D), 1.4)
    for _ in range(40):
        mid = (lo + hi) / 2
        out = sd(C + D * mid[:, None]) > 0
        hi = np.where(out, mid, hi)
        lo = np.where(out, lo, mid)
    return C + D * ((lo + hi) / 2)[:, None]


def scalp(th, az):
    """scalp points and outward normals at polar angles"""
    S = ray_hit(dirs(th, az).reshape(-1, 3))
    return S, head_n(S)


def da_of(P):
    P = np.atleast_2d(P)
    return np.arctan2(np.abs(P[:, 0]), -(P[:, 2] - 0.05))


def push_clear(P, margin=CLEAR, ear=EAR_CLEAR, iters=4):
    """every point at least `margin` outside the head and `ear` outside the ears"""
    P = np.array(P, np.float64)
    for _ in range(iters):
        d = sd(P)
        m = d < margin
        if m.any():
            P[m] += head_n(P[m]) * (margin - d[m])[:, None]
        e = ear_d(P)
        m = e < ear
        if m.any():
            P[m] += grad(ear_d, P[m]) * (ear - e[m])[:, None]
        if not (sd(P) < margin - 1e-4).any() and not (ear_d(P) < ear - 1e-4).any():
            break
    return P


# ============================================================================== fields shared by the styles
REF = None


def ref():
    global REF
    if REF is None:
        REF = bf.Ref()
    return REF


def in_hairline(S, margin=0.0, soft=0.03):
    """0..1: inside the natural hairline (the game's Kit.Cut "none" coverage, its ear line included), the line
    pulled in by `margin` studs (a vertical distance: the hairline height at the point's angle round the head)"""
    R = ref()
    da = da_of(S)
    h = np.interp(da, R.hl_da, R.hl_nat)
    f = np.clip((S[:, 1] - (h + margin)) / max(soft, 1e-4), 0, 1)
    th, az = angles(S)
    c = R.cov_at("none", th, az)
    return np.minimum(f, np.clip(c * 1.6, 0, 1))


def sstep(e0, e1, x):
    t = np.clip((np.asarray(x, np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ============================================================================== mesh emission
def smooth_normals(P, T):
    P = np.asarray(P)
    T = np.asarray(T)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    N = np.zeros_like(P)
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    # weld by position (seams)
    key = np.round(P / 1e-6).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    acc = np.zeros((inv.max() + 1, 3))
    np.add.at(acc, inv, N)
    N = acc[inv]
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def emit(piece, P, T, UV, COL, inner, flat=False):
    """adds an indexed mesh to piece; normals face away from `inner` (a point per vertex known to be inside the
    primitive: a lump's centre, a tube's axis); flat: one vertex per triangle corner with the face normal"""
    P = np.asarray(P, np.float64)
    T = np.asarray(T, np.int64)
    inner = np.asarray(inner, np.float64)
    if inner.ndim == 1:
        inner = np.broadcast_to(inner, P.shape)
    if flat:
        A, B, Cc = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
        fn = np.cross(B - A, Cc - A)
        fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
        cen = (A + B + Cc) / 3
        ic = (inner[T[:, 0]] + inner[T[:, 1]] + inner[T[:, 2]]) / 3
        flip = np.einsum("ij,ij->i", fn, cen - ic) < 0
        fn[flip] *= -1
        for t, n, fl in zip(T, fn, flip):
            ids = [piece.vert(P[i], n, UV[i], COL[i]) for i in t]
            if fl:
                piece.tri(ids[0], ids[2], ids[1])
            else:
                piece.tri(ids[0], ids[1], ids[2])
        return
    N = smooth_normals(P, T)
    flip = np.einsum("ij,ij->i", N, P - inner) < 0
    N[flip] *= -1
    base = piece.nv
    for p, n, uv, c in zip(P, N, UV, COL):
        piece.vert(p, n, uv, c)
    for a, b, c in T:
        piece.tri(base + a, base + b, base + c)


# ============================================================================== primitives
def _subdiv(V, F, levels):
    V = [np.asarray(v, np.float64) for v in V]
    F = [tuple(f) for f in F]
    for _ in range(levels):
        mid = {}
        nf = []

        def m(a, b):
            k = (min(a, b), max(a, b))
            if k not in mid:
                p = V[a] + V[b]
                V.append(p / np.linalg.norm(p))
                mid[k] = len(V) - 1
            return mid[k]
        for a, b, c in F:
            ab, bc, ca = m(a, b), m(b, c), m(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        F = nf
    return np.array(V), np.array(F)


def octa(levels=1):
    V = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    F = [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)]
    return _subdiv(V, F, levels)


def ico(levels=1):
    t = (1 + 5 ** 0.5) / 2
    V = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    V = [np.array(v) / np.linalg.norm(v) for v in V]
    F = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    return _subdiv(V, F, levels)


SPHERES = {"octa1": octa(1), "ico1": ico(1), "octa0": octa(0), "ico0": ico(0)}


def frame_at(n, rng):
    n = n / np.linalg.norm(n)
    a = np.array([0.0, 1.0, 0.0]) if abs(n[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    t1 = np.cross(n, a)
    t1 /= np.linalg.norm(t1)
    t2 = np.cross(n, t1)
    ang = rng.uniform(0, TAU)
    t1, t2 = t1 * math.cos(ang) + t2 * math.sin(ang), -t1 * math.sin(ang) + t2 * math.cos(ang)
    return t1, t2, n


def lump(piece, c, n, radii, rng, kind="octa1", jitter=0.2, tone=1.0, vmap=None, ao=None, flat=True):
    """a faceted curl knot / clump: a jittered subdivided octahedron (or icosphere), radii (r1, r2, rn) with rn
    along n; vmap(P) -> v per vertex (root 0 .. tip 1); ao(P, local) -> occlusion per vertex"""
    V0, F = SPHERES[kind]
    V = V0 * (1 + jitter * rng.uniform(-1, 1, (len(V0), 1)))
    t1, t2, nn = frame_at(np.asarray(n, np.float64), rng)
    P = c + V[:, :1] * radii[0] * t1 + V[:, 1:2] * radii[1] * t2 + V[:, 2:3] * radii[2] * nn
    P = push_clear(P)
    u0 = rng.uniform(0.05, 0.75)
    UV = np.stack([u0 + 0.2 * (V0[:, 0] + 1) / 2, vmap(P) if vmap else (V0[:, 2] + 1) / 2], -1)
    local = (V0[:, 2] + 1) / 2
    occ = ao(P, local) if ao else 0.55 + 0.45 * local
    occ = np.clip(occ * tone, 0.25, 1.0)
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    emit(piece, P, F, UV, COL, c, flat=flat)


def frames_along(pts, up0):
    """parallel-transport frames (tangent, normal, binormal) along a polyline"""
    pts = np.asarray(pts)
    n = len(pts)
    T = np.zeros_like(pts)
    T[0] = pts[1] - pts[0]
    T[-1] = pts[-1] - pts[-2]
    T[1:-1] = pts[2:] - pts[:-2]
    T /= np.linalg.norm(T, axis=1, keepdims=True)
    N = np.zeros_like(pts)
    u = np.asarray(up0, np.float64)
    u = u - T[0] * np.dot(u, T[0])
    if np.linalg.norm(u) < 1e-6:
        u = np.cross(T[0], [1, 0, 0])
    N[0] = u / np.linalg.norm(u)
    for i in range(1, n):
        v = N[i - 1] - T[i] * np.dot(N[i - 1], T[i])
        N[i] = v / max(np.linalg.norm(v), 1e-9)
    B = np.cross(T, N)
    return T, N, B


def sweep(piece, pts, radius, sides, section, rng, v0=0.0, v1=1.0, flat=False, ao=None, tip_cap=True,
          root_cap=True, up0=None, tone=1.0):
    """a tube along pts: ring i has `sides` vertices at angle a_k and radius radius[i] * section(i, a_k);
    a rounded cap at the tip (two shrinking rings and a point), a flat fan at the root"""
    pts = np.asarray(pts, np.float64)
    n = len(pts)
    Tn, Nn, Bn = frames_along(pts, up0 if up0 is not None else head_n(pts[:1])[0])
    P, UV, IN = [], [], []
    u0 = rng.uniform(0, 1)
    rings = []
    for i in range(n):
        ring = []
        for k in range(sides + 1):
            a = TAU * (k % sides) / sides
            r = radius[i] * section(i, a)
            p = pts[i] + (Nn[i] * math.cos(a) + Bn[i] * math.sin(a)) * r
            ring.append(len(P))
            P.append(p)
            UV.append(((u0 + k / sides) % 1.0001, v0 + (v1 - v0) * i / (n - 1)))
            IN.append(pts[i])
        rings.append(ring)
    T = []
    for i in range(n - 1):
        for k in range(sides):
            a, b, c, d = rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]
            T += [(a, b, c), (a, c, d)]
    if tip_cap:
        last = rings[-1]
        prev = pts[-1]
        for j, (sc, adv) in enumerate(((0.72, 0.45), (0.32, 0.8))):
            ring = []
            for k in range(sides + 1):
                a = TAU * (k % sides) / sides
                r = radius[-1] * section(n - 1, a) * sc
                p = pts[-1] + Tn[-1] * radius[-1] * adv + (Nn[-1] * math.cos(a) + Bn[-1] * math.sin(a)) * r
                ring.append(len(P))
                P.append(p)
                UV.append(((u0 + k / sides) % 1.0001, v1))
                IN.append(prev)
            for k in range(sides):
                a, b, c, d = last[k], last[k + 1], ring[k + 1], ring[k]
                T += [(a, b, c), (a, c, d)]
            last = ring
        tip = len(P)
        P.append(pts[-1] + Tn[-1] * radius[-1] * 0.95)
        UV.append((u0, v1))
        IN.append(pts[-1])
        for k in range(sides):
            T.append((last[k], last[k + 1], tip))
    if root_cap:
        cen = len(P)
        P.append(pts[0] - Tn[0] * radius[0] * 0.15)
        UV.append((u0, v0))
        IN.append(pts[0] + Tn[0] * radius[0])
        for k in range(sides):
            T.append((rings[0][k + 1], rings[0][k], cen))
    P = push_clear(np.array(P))
    IN = np.array(IN)
    # the root's fan: its inner point is ahead of it (so it faces the scalp)
    t = np.array([UV[i][1] for i in range(len(P))])
    tt = (t - v0) / max(1e-6, (v1 - v0))
    occ = ao(P, tt) if ao else 0.5 + 0.5 * tt
    occ = np.clip(occ * tone, 0.25, 1.0)
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    emit(piece, P, T, np.array(UV), COL, IN, flat=flat)


# ============================================================================== sampling
def poisson_on_scalp(weight, spacing, rng, n_cand=40000, wmin=0.02, th_max=2.3):
    """points on the scalp where weight(S) > wmin, at least spacing(S, w) apart (dart throwing, uniform on the
    sphere of directions): returns S, N, w"""
    D = rng.normal(size=(n_cand, 3))
    D /= np.linalg.norm(D, axis=1, keepdims=True)
    D = D[np.arccos(np.clip(D[:, 1], -1, 1)) < th_max]
    S = ray_hit(D)
    w = weight(S)
    keep = w > wmin
    S, w = S[keep], w[keep]
    sp = spacing(S, w)
    acc = []
    for i in rng.permutation(len(S)):
        if acc:
            A = S[acc]
            dd = np.linalg.norm(A - S[i], axis=1)
            if (dd < np.minimum(sp[acc], sp[i])).any():
                continue
        acc.append(i)
    acc = np.array(acc)
    return S[acc], head_n(S[acc]), w[acc]


def polar_grid(th_max_deg, dth_deg, naz):
    ths = np.radians(np.arange(0.0, th_max_deg + 1e-6, dth_deg))
    ths[0] = np.radians(0.5)
    TH, AZ = np.meshgrid(ths, np.arange(naz + 1) * TAU / naz, indexing="ij")
    return TH, AZ


def grid_tris(nr, nc):
    T = []
    for i in range(nr - 1):
        for j in range(nc - 1):
            a, b, c, d = i * nc + j, i * nc + j + 1, (i + 1) * nc + j + 1, (i + 1) * nc + j
            T += [(a, b, c), (a, c, d)]
    return np.array(T)


def base_shell(piece, thick, frac=0.58, hmin=0.027, tmin=0.034, th_max=125, dth=5.0, naz=48, tone=0.62,
               lift=None):
    """the dark under-layer of a clump volume: the scalp lifted by frac x the volume's thickness (>= hmin), only
    where the thickness is >= tmin (it ends under the clumps, never over the bare cap)"""
    TH, AZ = polar_grid(th_max, dth, naz)
    S, N = scalp(TH.reshape(-1), AZ.reshape(-1))
    t = thick(S)
    h = np.maximum(hmin, frac * t) if lift is None else lift(S, t)
    P = S + N * h[:, None]
    T = grid_tris(*TH.shape)
    ok = (t[T] >= tmin).all(axis=1)
    T = T[ok]
    used = np.unique(T)
    remap = -np.ones(len(P), np.int64)
    remap[used] = np.arange(len(used))
    P = push_clear(P[used])
    S2 = S[used]
    T = remap[T]
    tt = t[used]
    UV = np.stack([AZ.reshape(-1)[used] / TAU * 4 % 1.0, np.clip(0.15 + 0.5 * tt / max(tt.max(), 1e-6), 0, 1)], -1)
    occ = np.full(len(P), tone)
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    emit(piece, P, T, UV, COL, S2, flat=False)


# ============================================================================== clump volumes (tapers, afros)
def clump_volume(key, spec, seed):
    """a top / afro volume: base shell + faceted knots on the envelope. spec: thick(S) -> thickness, r (min, max),
    spacing k (x radius), kind, squash, regions (n pieces by azimuth for the volume slider) or one HairTop"""
    rng = np.random.default_rng(seed)
    thick = spec["thick"]
    tmax = spec["tmax"]
    rmin, rmax = spec["r"]

    def rad_of(t):
        return np.clip(t * spec.get("rk", 0.42), rmin, rmax)

    def spacing(S, w):
        return rad_of(w) * spec.get("sk", 1.55)
    layers = []
    S, N, t = poisson_on_scalp(thick, spacing, rng, wmin=spec.get("tmin", 0.03))
    layers.append((S, N, t, 1.0))
    if spec.get("inner"):
        # a second, deeper layer of larger knots (no see-through between the outer ones)
        rng2 = np.random.default_rng(seed + 1)
        S2, N2, t2 = poisson_on_scalp(lambda P: thick(P) * (thick(P) > spec["inner"]), lambda P, w: rad_of(w) * 2.3,
                                      rng2, wmin=spec["inner"])
        layers.append((S2, N2, t2, 0.6))
    sq = spec.get("squash", 0.8)

    def vmap(P):
        return np.clip(0.08 + 0.92 * sd(P) / tmax, 0, 1)

    def ao_of(tl):
        def ao(P, local):
            h = sd(P)
            return 0.42 + 0.58 * np.clip(h / max(tl, 0.03), 0, 1) ** 0.8 * (0.75 + 0.25 * local)
        return ao
    pieces = {}
    nreg = spec.get("regions", 1)

    def region_of(p):
        if nreg <= 1:
            return 0
        a = math.atan2(p[0], p[2]) % TAU
        if p[1] > spec.get("crown_y", 0.55) and math.hypot(p[0], p[2]) < spec.get("crown_r", 0.28):
            return nreg  # the crown piece
        return int(a / TAU * nreg) % nreg

    def piece_for(i):
        if i not in pieces:
            name = spec.get("names", lambda j: f"HairClump{j + 1:02d}")(i)
            pieces[i] = Piece(name, "clump", material=spec.get("material", "Fabric"), castShadow=True,
                              hideUnder=dict(HIDE))
            if nreg > 1 and spec.get("volume", False):
                pieces[i].meta["length"] = "volume"
        return pieces[i]
    for (S, N, t, depth) in layers:
        for s, nrm, tt in zip(S, N, t):
            r = float(rad_of(tt)) * (1.0 if depth == 1.0 else 1.25) * rng.uniform(0.85, 1.15)
            rn = r * sq
            h = max(tt * depth - rn * 0.85, CLEAR + rn * 0.9)
            # a little lean along the flow (forward on top, down at the sides)
            c = s + nrm * h
            radii = (r * rng.uniform(0.9, 1.15), r * rng.uniform(0.85, 1.05), rn)
            tone = rng.uniform(0.86, 1.04) * (1.0 if depth == 1.0 else 0.8)
            lump(piece_for(region_of(c)), c, nrm, radii, rng, kind=spec.get("kind", "octa1"),
                 jitter=spec.get("jitter", 0.2), tone=tone, vmap=vmap, ao=ao_of(tt))
    base = Piece(spec.get("base_name", "HairTop"), "clump", material=spec.get("material", "Fabric"),
                 castShadow=True, hideUnder=dict(HIDE))
    base_shell(base, thick, frac=spec.get("base_frac", 0.58), tmin=spec.get("base_tmin", 0.034),
               lift=spec.get("base_lift"))
    out = [base] + [pieces[k] for k in sorted(pieces)]
    return [p for p in out if p.nt > 0]


def taper_thick(top=0.15, front=0.11, side=0.085, back=0.1, line=None, ramp=0.07, hl_margin=0.012, dome=0.32):
    """a short top's thickness: inside the natural hairline (pulled in by hl_margin), above the weight line
    line(da) -> y (the fade's top), ramping up over `ramp` above it; tallest on top (the scalp facing up), the
    front edge `front`, the sides above the weight line `side`, the back `back`"""
    line = line or (lambda da: np.interp(da, [0, 0.7, 1.2, 1.6, 2.2, math.pi], [0.36, 0.33, 0.30, 0.29, 0.24, 0.18]))

    def f(S):
        da = da_of(S)
        n = head_n(S)
        up = np.clip(n[:, 1], 0, 1)
        fr = np.clip(-n[:, 2], 0, 1) * (1 - up)
        sd_ = (1 - up) * (1 - fr)
        backf = np.clip(n[:, 2], 0, 1) * (1 - up)
        base = top * up + front * fr + side * np.clip(sd_ - backf, 0, 1) + back * backf
        base = base * (1 + dome * up * np.clip(1 - np.hypot(S[:, 0], S[:, 2]) / 0.6, 0, 1))
        az = np.arctan2(S[:, 0], S[:, 2])
        jag = 0.018 * (np.sin(az * 23 + 1.3) + 0.6 * np.sin(az * 41 + 0.4))
        w = in_hairline(S, hl_margin, 0.02) * sstep(0.0, ramp, S[:, 1] - line(da) + jag * (S[:, 1] < 0.4))
        return base * w
    return f


def afro_thick(top=0.27, side=0.17, front=0.13, back=0.2, edge=0.2, hl_margin=0.01, temple=0.55, dome=0.18):
    """the afro's thickness: a rounded volume, every side, ramping up from the natural hairline over `edge` (a
    clean line), lower at the temples / round the ears (temple x), none below the ear line"""
    def f(S):
        n = head_n(S)
        up = np.clip(n[:, 1], 0, 1)
        fr = np.clip(-n[:, 2], 0, 1) * (1 - up)
        bk = np.clip(n[:, 2], 0, 1) * (1 - up)
        sdw = np.clip(1 - up - fr - bk, 0, 1)
        base = top * up + front * fr + back * bk + side * sdw
        base = base * (1 + dome * up * np.clip(1 - np.hypot(S[:, 0], S[:, 2]) / 0.6, 0, 1))
        R = ref()
        da = da_of(S)
        h = np.interp(da, R.hl_da, R.hl_nat)
        dist = S[:, 1] - (h + hl_margin)
        th, az = angles(S)
        cov = np.clip(R.cov_at("none", th, az) * 1.4, 0, 1)
        # the temples and round the ears: tapered
        side_low = 1 - (1 - temple) * sstep(0.25, -0.05, S[:, 1]) * np.clip(np.abs(n[:, 0]) * 1.4, 0, 1)
        # the front's hairline is a clean, fairly steep line (the volume rises off it), the sides and the nape
        # curve in to the head (a rounded bottom, no helmet rim)
        e = edge * (0.45 + 0.55 * np.clip(1 - fr - up, 0, 1))
        # no sideburn tail: in front of the ear the volume ends above the ear's top
        burn = 1 - (1 - sstep(0.12, 0.3, S[:, 1])) * sstep(0.3, 0.45, np.abs(S[:, 0])) * (S[:, 2] < 0.05)
        return base * sstep(0.0, 1.0, dist / e) ** 0.7 * cov * side_low * burn
    return f


def boundary_edges(T):
    from collections import Counter
    c = Counter()
    for a, b, d in T:
        for e in ((a, b), (b, d), (d, a)):
            c[(min(e), max(e))] += 1
    out = []
    for a, b, d in T:
        for e in ((a, b), (b, d), (d, a)):
            if c[(min(e), max(e))] == 1:
                out.append(e)
    return out


def knob_volume(spec, seed):
    """a clump volume as one faceted surface: the scalp lifted by the style's thickness t(S) over an icosphere's
    directions, pebbled by round knobs (spherical caps on Poisson-disc centres, kh x t high: the curl clusters),
    flat shaded (every facet its own normal: the chunky low-poly look), creases dark; a skirt down to the cap
    round its open edge (no gap under the rim)"""
    rng = np.random.default_rng(seed)
    thick = spec["thick"]
    tmax = spec["tmax"]
    tmin = spec.get("tmin", 0.03)
    V, F = ico(spec.get("level", 5))
    th = np.arccos(np.clip(V[:, 1], -1, 1))
    S = ray_hit(V)
    N = head_n(S)
    t = thick(S)
    keep = (t[F] >= tmin).all(axis=1)
    F = F[keep]
    used = np.unique(F)
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    F = remap[F]
    S, N, t, th = S[used], N[used], t[used], th[used]
    # knobs
    sp = spec["knob"]
    K, KN, Kt = poisson_on_scalp(thick, lambda P, w: sp * (0.75 + 0.5 * np.clip(w / tmax, 0, 1)), rng, wmin=tmin * 0.7)
    Kr = sp * (0.75 + 0.5 * np.clip(Kt / tmax, 0, 1)) * rng.uniform(spec.get("kr", (0.68, 0.84))[0],
                                                                     spec.get("kr", (0.68, 0.84))[1], len(K))
    Ktone = rng.uniform(0.84, 1.04, len(K))
    bump = np.zeros(len(S))
    tone = np.ones(len(S))
    for i0 in range(0, len(S), 2048):
        blk = S[i0:i0 + 2048]
        d2 = ((blk[:, None, :] - K[None, :, :]) ** 2).sum(-1)
        b = np.sqrt(np.clip(1 - d2 / (Kr[None, :] ** 2), 0, 1))
        j = np.argmax(b, axis=1)
        bump[i0:i0 + 2048] = b[np.arange(len(blk)), j]
        tone[i0:i0 + 2048] = Ktone[j]
    kh = spec.get("kh", 0.3)
    h = t * (1 - kh) + t * kh * bump
    if spec.get("hmin"):
        h = np.maximum(h, spec["hmin"])
    P = push_clear(S + N * h[:, None], margin=CLEAR + 0.006)
    az = np.arctan2(S[:, 0], S[:, 2]) % TAU
    UV = np.stack([(az / TAU * 6) % 1.0, np.clip(0.1 + 0.9 * h / tmax, 0, 1)], -1)
    occ = (0.36 + 0.64 * bump ** 0.55) * (0.7 + 0.3 * np.clip(t / tmax, 0, 1)) * tone
    occ = np.clip(occ, 0.25, 1)
    pc = Piece(spec.get("name", "HairTop"), "clump", material=spec.get("material", "Fabric"), castShadow=True,
               hideUnder=dict(HIDE))
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    emit(pc, P, F, UV, COL, S, flat=True)
    # the skirt: every open edge carried down to just over the cap, facing away from the volume's middle
    be = boundary_edges(F)
    if be:
        bv = sorted({v for e in be for v in e})
        idx = {v: i for i, v in enumerate(bv)}
        top = P[bv]
        low = push_clear(S[bv] + N[bv] * (CAP_H + 0.006), margin=CLEAR + 0.004)
        G = S.mean(axis=0) + np.array([0, -0.25, 0])
        PP = np.concatenate([top, low])
        nb = len(bv)
        TT = []
        for a_, b_ in be:
            i, j = idx[a_], idx[b_]
            TT += [(i, j, nb + j), (i, nb + j, nb + i)]
        UU = np.concatenate([UV[bv], np.stack([UV[bv][:, 0], np.full(nb, 0.05)], -1)])
        oc = np.concatenate([occ[bv] * 0.8, np.full(nb, 0.4)])
        CC = np.stack([oc, oc, oc, np.ones_like(oc)], -1)
        emit(pc, PP, np.array(TT), UU, CC, G, flat=True)
    return [pc]


# ============================================================================== 360 waves
def waves_shell(seed=71, ncol=60, levels=(0.0, 0.25, 0.45, 0.72), base=0.026, amp=0.025, kind="low"):
    """the 360 waves: a close shell on the cap's polar UV, its rows along the ridge field's levels (trough, crest,
    back slope of every ridge), lifted base + amp x the ridge's profile; trimmed to the painted coverage"""
    R = ref()
    vv = np.linspace(0.0, 1.0, 1601)
    cols = []
    lo_phase, hi_phase = None, None
    for j in range(ncol + 1):
        u = j / ncol
        ph, ridge, am, calm = fades_tex.waves_field(np.full_like(vv, u % 1.0), vv, seed)
        ph = np.maximum.accumulate(ph)
        cols.append((ph, am * calm))
        lo_phase = ph[0] if lo_phase is None else max(lo_phase, ph[0])
        hi_phase = ph[-1] if hi_phase is None else min(hi_phase, ph[-1])
    # row levels: the crown's whorl rows (uniform v) then every ridge's levels
    lv = []
    k0 = int(math.floor(lo_phase))
    k1 = int(math.ceil(max(c[0][-1] for c in cols)))
    for k in range(k0, k1 + 1):
        for f in levels:
            lv.append(k + f)
    lv = np.array([x for x in lv if x > lo_phase + 0.05])
    nr = len(lv) + 4
    V = np.zeros((nr, ncol + 1))
    A = np.zeros((nr, ncol + 1))
    PR = np.zeros((nr, ncol + 1))
    for j, (ph, am) in enumerate(cols):
        vfirst = float(np.interp(lv[0], ph, vv))
        V[:4, j] = np.linspace(0.004, vfirst * 0.8, 4)
        V[4:, j] = np.interp(lv, ph, vv, right=1.0)
        fr = (lv - np.floor(lv))
        prof = np.where(fr < 0.4, np.sin(np.clip(fr / 0.4, 0, 1) * math.pi / 2) ** 1.3,
                        np.cos(np.clip((fr - 0.4) / 0.6, 0, 1) * math.pi / 2) ** 1.3)
        PR[4:, j] = prof
        A[:, j] = np.interp(V[:, j], vv, am)
    V = np.maximum.accumulate(V, axis=0)
    V = np.minimum(V, 1.0)
    TH = V * THETA_MAX
    AZ = np.tile(np.arange(ncol + 1) / ncol * TAU, (nr, 1))
    # radial lift above the skull table (the cap's own space: the cap is CAP_H out along the ray)
    h = base + amp * PR * np.clip(A, 0, 1)
    P = R.scalp_points(TH.reshape(-1), AZ.reshape(-1), 0.0).reshape(-1, 3)
    Nh = head_n(P)
    P = P + Nh * h.reshape(-1)[:, None]
    T = grid_tris(nr, ncol + 1)
    # drop degenerate triangles (rows clamped at the cap's edge) and those where no look paints hair
    Pa, Pb, Pc = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    area = np.linalg.norm(np.cross(Pb - Pa, Pc - Pa), axis=1)
    cov = np.maximum(R.cov_at(kind, TH.reshape(-1), AZ.reshape(-1)), R.cov_at("none", TH.reshape(-1), AZ.reshape(-1)))
    keep = (area > 1e-7) & (cov[T] > 0.0).any(axis=1)
    brow = (P[:, 2] < -0.35) & (np.abs(P[:, 0]) < 0.38) & (P[:, 1] < 0.345)
    keep &= ~brow[T].any(axis=1)
    T = T[keep]
    used = np.unique(T)
    remap = -np.ones(len(P), np.int64)
    remap[used] = np.arange(len(used))
    Pu = push_clear(P[used])
    UV = np.stack([AZ.reshape(-1)[used] / TAU, V.reshape(-1)[used]], -1)
    occ = 0.6 + 0.4 * PR.reshape(-1)[used]
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    pc = Piece("HairFur", "cap", material="Plastic", castShadow=False, hideUnder=dict(HIDE))
    emit(pc, Pu, remap[T], UV, COL, np.broadcast_to(C, Pu.shape), flat=False)
    return [pc]


# ============================================================================== twists and locs
def top_roots(rng, spacing, line, hl_margin=0.02, extra=None):
    def w(S):
        da = da_of(S)
        v = in_hairline(S, hl_margin, 0.02) * sstep(0.0, 0.03, S[:, 1] - line(da))
        return v if extra is None else v * extra(S)
    return poisson_on_scalp(w, lambda S, ww: np.full(len(S), spacing), rng, wmin=0.5)


CROWN = np.array([0.0, 0.6, 0.06])
BASE_RIDE = 0.03  # twists / locs lie on their root mass


def root_mass(line, top, seed):
    """the knotted mass the twists / locs grow from: a low knob surface over their roots (no scalp between them)"""
    spec = dict(thick=taper_thick(top=top, front=top * 0.7, side=top * 0.75, back=top * 0.85, line=line, ramp=0.05,
                                  dome=0.0, hl_margin=0.022), tmax=top, knob=0.075, kh=0.4, tmin=0.026, level=4)
    return knob_volume(spec, seed)


def radial_tangent(p, n):
    """the direction on the scalp away from the crown (the way hair combed out from the whorl lies)"""
    d = p - CROWN
    d = d - n * np.dot(d, n)
    if np.linalg.norm(d) < 1e-6:
        d = np.array([0.0, 0.0, -1.0]) - n * n[2] * -1
    return d / np.linalg.norm(d)


def grow_path(root, n, length, rng, stiff, gravity, lift, radius, front_y, step=0.016, side_y=None, ride=0.0,
              wander=0.06):
    """a strand's centre line from root: leaves the scalp between its normal and the comb direction (lift 1: straight
    out, 0: lying down), bends by gravity once past `stiff` x 0.08 of its length, kept outside the head (radius +
    clearance + ride: the crown's strands lie over the outer ones) and the ears; the front ones stop at front_y"""
    pts = [root + n * (radius * 0.9 + CLEAR + ride)]
    d = n * lift + radial_tangent(root, n) * (1 - lift)
    d /= np.linalg.norm(d)
    L = 0.0
    while L < length:
        g = np.array([0.0, -1.0, 0.0]) * gravity * (1 - stiff * math.exp(-L / 0.08))
        d = d + g * step / 0.05 + rng.normal(0, wander, 3)
        d /= np.linalg.norm(d)
        p = pts[-1] + d * step
        need = radius + CLEAR + 0.004 + ride
        for _ in range(3):
            s_ = sd(p[None])[0]
            if s_ < need:
                gn = head_n(p[None])[0]
                p = p + gn * (need - s_)
                d = d - gn * min(0.0, float(np.dot(d, gn)))
                d /= np.linalg.norm(d)
            e = ear_d(p[None])[0]
            if e < radius + EAR_CLEAR:
                ge = grad(ear_d, p[None])[0]
                p = p + ge * (radius + EAR_CLEAR - e)
        # the brows / eyes: in front of the face no lower than front_y
        if p[2] < -0.3 and abs(p[0]) < 0.42 and p[1] < front_y + radius:
            break
        if side_y is not None and p[1] < side_y + radius:
            break
        L += float(np.linalg.norm(p - pts[-1]))
        pts.append(p)
    return np.array(pts)


def resample(pts, step):
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    n = max(3, int(math.ceil(s[-1] / step)) + 1)
    t = np.linspace(0, s[-1], n)
    return np.stack([np.interp(t, s, pts[:, k]) for k in range(3)], -1), s[-1]


def group_pieces(prefix, nsec, mat, fx):
    pieces = {}

    def get(i, root=None, tip=None):
        if i not in pieces:
            pieces[i] = (Piece(f"{prefix}{i + 1:02d}", "clump", material=mat, castShadow=True, hideUnder=dict(HIDE)),
                         [], [])
        if root is not None:
            pieces[i][1].append(root)
            pieces[i][2].append(tip)
        return pieces[i][0]

    def finish():
        out = []
        for i in sorted(pieces):
            p, roots, tips = pieces[i]
            if p.nt == 0:
                continue
            if fx and roots:
                p.meta["hairfx"] = dict(fx, pivot=[round(float(x), 4) for x in np.mean(roots, 0)],
                                        tip=[round(float(x), 4) for x in np.mean(tips, 0)])
            out.append(p)
        return out
    return get, finish


def sector(p, nsec):
    a = math.atan2(p[0], -p[2]) % TAU  # 0 at the front
    return int(((a + math.pi / nsec) % TAU) / TAU * nsec) % nsec


def twists_entry(seed=31, spacing=0.095, r0=0.027):
    rng = np.random.default_rng(seed)
    line = lambda da: np.interp(da, [0, 0.8, 1.3, 1.7, 2.3, math.pi], [0.36, 0.33, 0.31, 0.3, 0.22, 0.14])
    S, N, _ = top_roots(rng, spacing, line, hl_margin=0.022)
    get, finish = group_pieces("HairTwist", 8, "Fabric", {"kind": "bounce", "stiff": 0.85, "mass": 1.0})
    sides = 7
    for s, n in zip(S, N):
        dc = float(np.linalg.norm((s - CROWN)[[0, 2]]))
        length = rng.uniform(0.17, 0.25)
        pts = grow_path(s, n, length, rng, stiff=0.55, gravity=0.55, lift=0.5, radius=r0, front_y=0.38,
                        ride=BASE_RIDE + 0.03 * max(0.0, 1 - dc / 0.55), wander=0.05)
        if len(pts) < 4:
            continue
        pts, L = resample(pts, 0.024)
        m = len(pts)
        r = r0 * rng.uniform(0.9, 1.12)
        radius = r * (1 - 0.12 * np.linspace(0, 1, m) ** 2)
        pitch = rng.uniform(0.06, 0.075)
        ph0 = rng.uniform(0, TAU)
        seglen = L / (m - 1)

        def section(i, a, ph0=ph0, pitch=pitch, seglen=seglen):
            rot = ph0 + TAU * i * seglen / pitch
            return 0.7 + 0.3 * abs(math.cos(a - rot))

        def ao(P, tt):
            return 0.5 + 0.5 * np.clip(sd(P) / 0.12, 0, 1) ** 0.7
        piece = get(sector(s, 8), s, pts[-1])
        sweep(piece, pts, radius, sides, section, rng, v0=0.05, v1=1.0, flat=False, ao=ao, up0=n,
              tone=rng.uniform(0.86, 1.04))
    return root_mass(line, 0.05, 31) + finish()


def locs_entry(seed=47, spacing=0.118, r0=0.039):
    rng = np.random.default_rng(seed)
    line = lambda da: np.interp(da, [0, 0.8, 1.3, 1.7, 2.3, math.pi], [0.36, 0.33, 0.31, 0.3, 0.2, 0.1])
    S, N, _ = top_roots(rng, spacing, line, hl_margin=0.02)
    get, finish = group_pieces("HairLoc", 8, "Fabric", {"kind": "bounce", "stiff": 0.75, "mass": 1.3})
    sides = 7
    for s, n in zip(S, N):
        dc = float(np.linalg.norm((s - CROWN)[[0, 2]]))
        length = rng.uniform(0.3, 0.4)
        pts = grow_path(s, n, length, rng, stiff=0.3, gravity=1.0, lift=0.25, radius=r0, front_y=0.36,
                        side_y=0.06 if abs(s[0]) > 0.3 else -0.02,
                        ride=BASE_RIDE + 0.04 * max(0.0, 1 - dc / 0.55),
                        wander=0.07)
        if len(pts) < 4:
            continue
        pts, L = resample(pts, 0.024)
        m = len(pts)
        r = r0 * rng.uniform(0.85, 1.18)
        seg = rng.uniform(0.036, 0.046)
        ph = rng.uniform(0, 1)
        seglen = L / (m - 1)
        wob = rng.uniform(0, TAU, 3)
        radius = r * (1 + 0.08 * np.sin(np.linspace(0, 1, m) * 7 + wob[0])) * (1 - 0.1 * np.linspace(0, 1, m))
        # stacked segments: a bead every `seg` (the ring grooves of the reference's locs)
        bead = 1 + 0.12 * np.cos(TAU * (np.arange(m) * seglen / seg + ph))
        radius = radius * bead
        irr = rng.uniform(0.86, 1.12, sides)

        def section(i, a, irr=irr):
            k = int(round(a / TAU * sides)) % sides
            return irr[k]

        def ao(P, tt):
            return 0.45 + 0.55 * np.clip(sd(P) / 0.14, 0, 1) ** 0.6
        piece = get(sector(s, 8), s, pts[-1])
        sweep(piece, pts, radius, sides, section, rng, v0=0.05, v1=1.0, flat=True, ao=ao, up0=n,
              tone=rng.uniform(0.84, 1.02))
    return root_mass(line, 0.055, 47) + finish()


# ============================================================================== cornrows
def cornrows_entry(seed=13, nrows=13, dlat=11.0, pitch=0.064, width=0.082, height=0.04):
    """plaited rows along latitudes round the X axis (centre row over the top, the outer rows fanning round
    above the ears), each a herringbone of faceted lobes, tapering and tucking under at the nape"""
    rng = np.random.default_rng(seed)
    R = ref()
    pc = Piece("HairTop", "clump", material="Fabric", castShadow=True, hideUnder=dict(HIDE))
    half = (nrows - 1) / 2
    for i in range(nrows):
        lat = math.radians((i - half) * dlat)
        # the path: psi round the X axis from the forehead (psi 0: toward -Z) over the top to the nape
        psis = np.radians(np.linspace(-20, 215, 900))
        D = np.stack([np.full_like(psis, math.sin(lat)), math.cos(lat) * np.sin(psis + math.radians(20)),
                      -math.cos(lat) * np.cos(psis + math.radians(20))], -1)
        # a gentle S-bend in the outer rows (the reference's rows curve back round the side)
        D[:, 0] += math.sin(lat) * 0.18 * np.sin(np.clip((psis - 0.6) / 2.4, 0, 1) * math.pi)
        D /= np.linalg.norm(D, axis=1, keepdims=True)
        S = ray_hit(D)
        inside = in_hairline(S, 0.022, 0.001) > 0.5
        # (a row's own hairline: from the first point inside to the nape's end)
        if not inside.any():
            continue
        idx = np.where(inside)[0]
        a0 = idx[0]
        # the rear end: the last inside point but no lower than the nape - small
        a1 = idx[-1]
        S = S[a0:a1 + 1]
        seg = np.linalg.norm(np.diff(S, axis=0), axis=1)
        s = np.concatenate([[0], np.cumsum(seg)])
        L = s[-1]
        nl = int(L / (pitch / 2))
        for k in range(nl):
            sk = (k + 0.5) * pitch / 2
            t = sk / L
            p = np.array([np.interp(sk, s, S[:, j]) for j in range(3)])
            q = np.array([np.interp(min(L, sk + 0.01), s, S[:, j]) for j in range(3)])
            q0 = np.array([np.interp(max(0, sk - 0.01), s, S[:, j]) for j in range(3)])
            tan = q - q0
            tan /= np.linalg.norm(tan)
            n = head_n(p[None])[0]
            side = np.cross(n, tan)
            side /= np.linalg.norm(side)
            # thicker on top, tapering over the last ~0.18 to a tucked end
            end = sstep(L, L - 0.2, sk)
            start = sstep(0.0, 0.05, sk)
            wk = width * (0.55 + 0.45 * end) * (0.8 + 0.2 * start)
            hk = height * (0.45 + 0.55 * end) * (0.8 + 0.2 * start)
            sgn = 1 if k % 2 == 0 else -1
            # a lobe: tilted across the row (the plait's chevron), offset to its side
            ang = math.radians(32) * sgn
            ax = tan * math.cos(ang) + side * math.sin(ang)
            ax /= np.linalg.norm(ax)
            bx = np.cross(n, ax)
            c = p + n * (CLEAR + hk * 0.5) + side * sgn * wk * 0.2
            # tuck: the very end dips under (lower) and narrows
            spindle(pc, c, ax, bx, n, (pitch * 0.78, wk * 0.5, hk * 0.55), rng, tone=rng.uniform(0.88, 1.02),
                    vt=0.2 + 0.8 * t)
    return [pc]


def spindle(piece, c, ax, bx, n, radii, rng, tone=1.0, vt=0.5, sides=4):
    """a plait lobe: two tips along ax and two rings of `sides` (20 faceted triangles)"""
    P = [c - ax * radii[0], c + ax * radii[0]]
    lv = [0.2, 0.2]
    for t in (-0.45, 0.4):
        s_ = math.sqrt(1 - t * t)
        for k in range(sides):
            a = TAU * k / sides + (0.0 if t < 0 else math.pi / sides)
            j = 1 + rng.uniform(-0.1, 0.1)
            P.append(c + ax * radii[0] * t + (bx * math.cos(a) * radii[1] + n * math.sin(a) * radii[2]) * s_ * j)
            lv.append(0.55 + 0.45 * max(0.0, math.sin(a)))
    T = []
    A0, B0 = 2, 2 + sides
    for k in range(sides):
        k1 = (k + 1) % sides
        T.append((0, A0 + k1, A0 + k))
        T.append((1, B0 + k, B0 + k1))
        T.append((A0 + k, A0 + k1, B0 + k))
        T.append((A0 + k1, B0 + k1, B0 + k))
    P = push_clear(np.array(P))
    UV = np.stack([rng.uniform(0.05, 0.9) + 0.05 * np.arange(len(P)) / len(P), np.full(len(P), vt)], -1)
    occ = np.clip(np.array(lv) * tone, 0.25, 1)
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    emit(piece, P, np.array(T), UV, COL, c, flat=True)


def lump_axes(piece, c, ax, bx, n, radii, rng, tone=1.0, vt=0.5, kind="octa1", jitter=0.12):
    V0, F = SPHERES[kind]
    V = V0 * (1 + jitter * rng.uniform(-1, 1, (len(V0), 1)))
    P = c + V[:, :1] * radii[0] * ax + V[:, 1:2] * radii[1] * bx + V[:, 2:3] * radii[2] * n
    P = push_clear(P)
    UV = np.stack([rng.uniform(0.05, 0.75) + 0.2 * (V0[:, 0] + 1) / 2, np.full(len(V0), vt)], -1)
    occ = np.clip((0.55 + 0.45 * (V0[:, 2] + 1) / 2) * tone, 0.25, 1)
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    emit(piece, P, F, UV, COL, c, flat=True)


# ============================================================================== the clump texture
def build_texture(path=TEX_PATH, size=256, seed=5):
    """a tileable greyscale fibre mottle: soft clumps of short strands (a value noise smeared along v), mean ~0.8,
    alpha 1 (the clump pieces are solid)"""
    rng = np.random.default_rng(seed)

    def wrap_noise(n, cells):
        g = rng.random((cells, cells))
        y, x = np.mgrid[0:n, 0:n] / n * cells
        x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
        fx, fy = x - x0, y - y0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = g[y0 % cells, x0 % cells]
        b = g[y0 % cells, (x0 + 1) % cells]
        c = g[(y0 + 1) % cells, x0 % cells]
        d = g[(y0 + 1) % cells, (x0 + 1) % cells]
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    L = 0.5 * wrap_noise(size, 4) + 0.3 * wrap_noise(size, 16) + 0.2 * wrap_noise(size, 64)
    # strands: fine noise smeared along v
    fine = rng.random((size, size))
    acc = np.zeros_like(fine)
    for k in range(-6, 7):
        acc += np.roll(fine, k, axis=0) * (1 - abs(k) / 7)
    acc = (acc - acc.mean()) / (acc.std() + 1e-9)
    L = (L - L.mean()) / (L.std() + 1e-9)
    lum = 0.8 + 0.06 * L + 0.025 * acc
    A = np.ones_like(lum)
    fades_tex.save_tex(path, lum, A, lo=0.55, hi=0.98)
    return path


# ============================================================================== entries
def fade_line(kind):
    """a curly fade's weight line (the y the top's knots start above, by the angle round the head from the front)"""
    lines = {
        "taper": [0.36, 0.33, 0.30, 0.29, 0.24, 0.18],
        "low": [0.36, 0.33, 0.30, 0.29, 0.25, 0.2],
        "mid": [0.36, 0.34, 0.33, 0.33, 0.3, 0.26],
        "high": [0.36, 0.36, 0.37, 0.38, 0.36, 0.34],
        "fade": [0.36, 0.34, 0.33, 0.33, 0.3, 0.26],
        "burst": [0.36, 0.32, 0.36, 0.40, 0.25, 0.14],
        "none": [0.36, 0.32, 0.28, 0.27, 0.12, -0.05],
    }[kind]
    return lambda da: np.interp(da, [0, 0.7, 1.2, 1.6, 2.2, math.pi], lines)


CURLY = ["Curly", "Kinky", "Coiled"]


def fade_top_entry(key, styles, kind, top=0.15, front=0.1, side=0.045, back=0.07, knob=0.07, seed=3,
                   cap_extra=None, ramp=0.13, kh=0.46):
    spec = dict(thick=taper_thick(top=top, front=front, side=side, back=back, line=fade_line(kind), ramp=ramp),
                tmax=top, knob=knob, kh=kh, tmin=0.03, level=5)
    pieces = knob_volume(spec, seed)
    entry = dict(styles=styles, types=CURLY, cap={"cut": "style", "density": 1}, family="stylised",
                 capEarLine=True, style="stylised clumps (build_stylised.py)")
    entry.update(cap_extra or {})
    return entry, pieces


def afro_entry(key, types, top=0.27, side=0.16, front=0.13, back=0.2, knob=0.11, seed=9, kh=0.42):
    spec = dict(thick=afro_thick(top=top, side=side, front=front, back=back), tmax=top, knob=knob, kh=kh, tmin=0.03,
                level=5, name="HairAfro01")
    pieces = knob_volume(spec, seed)
    entry = dict(styles=["Afro"], types=types, cap={"cut": "full", "density": 1}, capFade="taper", capEarLine=True,
                 family="stylised", style="stylised clumps (build_stylised.py)")
    return entry, pieces


def hightop_thick():
    base = afro_thick(top=0.36, side=0.12, front=0.12, back=0.13, edge=0.06)

    def f(S):
        t = base(S)
        # a flat top: the volume reaches y ~0.98 everywhere over the top, straight sides
        n = head_n(S)
        reach = np.clip(0.98 - S[:, 1], 0.0, 0.5)
        flat = np.where(n[:, 1] > 0.45, np.minimum(t * 1.4, reach), t)
        return np.where(S[:, 1] > 0.12, flat, t * sstep(-0.1, 0.12, S[:, 1]))
    return f


def hightop_entry(seed=21):
    spec = dict(thick=hightop_thick(), tmax=0.4, knob=0.1, kh=0.28, tmin=0.03, level=5, name="HairAfro01")
    pieces = knob_volume(spec, seed)
    return dict(styles=["High Top"], types=None, cap={"cut": "style", "density": 1}, family="stylised",
                capEarLine=True, style="stylised clumps (build_stylised.py)"), pieces


def entries():
    """key -> fn() -> (entry, pieces)"""
    E = {
        "fade_taper_c": lambda: fade_top_entry("fade_taper_c", ["Taper Fade"], "taper", seed=3),
        "waves360": lambda: (dict(styles=["360 Waves"], types=None, cap={"cut": "style", "density": 1},
                                  capTile="waves", capTileRepeat=[1, 1], capFade="low", capEarLine=True,
                                  family="stylised", style="sculpted ridge shell (build_stylised.py)"),
                             waves_shell()),
        "twists": lambda: (dict(styles=["Twists"], types=None, cap={"cut": "full", "density": 1},
                                capTile="shortcoil", capFade="taper", capEarLine=True, family="stylised",
                                style="chunky two-strand twists (build_stylised.py)"), twists_entry()),
        "short_dreads": lambda: (dict(styles=["Short Dreads"], types=None, cap={"cut": "full", "density": 1},
                                      capTile="shortcoil", capFade="taper", capEarLine=True, family="stylised",
                                      style="segmented short locs (build_stylised.py)"), locs_entry()),
        "cornrows": lambda: (dict(styles=["Cornrows"], types=None, cap={"cut": "none", "density": 0.0},
                                  family="stylised", style="plaited rows (build_stylised.py)"), cornrows_entry()),
        "afro": lambda: afro_entry("afro", ["Kinky", "Coiled", "Straight", "Wavy"], seed=9),
        "afro_curly": lambda: afro_entry("afro_curly", ["Curly"], top=0.22, side=0.14, front=0.11, back=0.17,
                                         knob=0.09, seed=19),
        "hightop": hightop_entry,
        "fade_low_c": lambda: fade_top_entry("fade_low_c", ["Low Fade"], "low", top=0.15, side=0.08, seed=4),
        "fade_mid_c": lambda: fade_top_entry("fade_mid_c", ["Fade", "Mid Fade"], "mid", top=0.15, side=0.07, seed=5),
        "fade_high_c": lambda: fade_top_entry("fade_high_c", ["High Fade"], "high", top=0.16, side=0.06, seed=6),
        "fade_burst_c": lambda: fade_top_entry("fade_burst_c", ["Burst Fade"], "burst", top=0.15, side=0.07,
                                               seed=7),
        "crew_c": lambda: fade_top_entry("crew_c", ["Crew Cut"], "none", top=0.1, front=0.08, side=0.05, back=0.05,
                                         knob=0.055, seed=8, cap_extra={"capFade": "fade"}),
        "caesar_c": lambda: fade_top_entry("caesar_c", ["Caesar Cut"], "none", top=0.07, front=0.06, side=0.045,
                                           back=0.045, knob=0.045, seed=10),
    }
    return E


OPT_IN = {"hightop"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--texture", action="store_true")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    if args.texture or not os.path.exists(TEX_PATH):
        print("texture", build_texture())
    E = entries()
    # hightop: the knob surface does not make a convincing flat-topped high top yet; the v9 mesh (build_afro.py)
    # stays unless it is asked for by name
    keys = [k for k in E if (k in args.only.split(",")) if args.only] or [k for k in E if k not in OPT_IN]
    for k in keys:
        entry, pieces = E[k]()
        assert len(pieces) <= 16, (k, len(pieces))
        # replace the entry's old meshes
        d = os.path.join(hl.OUT, k)
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".mesh"):
                    os.remove(os.path.join(d, f))
        data = hl.export_style(k, entry, pieces)
        print(f"{k}: {len(pieces)} pieces, {data['tris']} tris ({', '.join(f'{p.name} {p.nt}' for p in pieces)})",
              flush=True)


if __name__ == "__main__":
    main()
