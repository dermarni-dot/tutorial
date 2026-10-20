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
* waves360 (360 Waves) - a thin shell hugging the scalp (troughs 0.024 over the head, the cap 0.020 under it) with
  the waves sculpted in its geometry: fades_tex.waves_field's ridges (rings rippling out from a whorl at the back of
  the crown, snaking up and down round the head, tighter toward the hairline), rows laid along every ridge (trough,
  rise, crest, back slope) so each crest catches the light; a low dome over the classic head's flat top, a fan at the
  pole. The relief comes down to the cap's height at the painted coverage's edge (no rim), the front stopping on a
  crisp line-up, the temples, sides and nape the painted cap's low fade (tex "cap", capFade "low").
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

v10: the other 14 styles in the same chunky, clumped look (they replace the v9 fur shells, cards and smooth tubes):
* buzz (Buzz Cut, every type) - a close, even shell of small faceted pebbles over the painted cap.
* fade_low / fade_mid / fade_high / fade_taper / fade_burst, crew, caesar (straight and wavy types) - the curly fades'
  knob surface with its knobs drawn out into combed tufts (forward on top, down the sides and the back), a finer
  pebbling on each tuft, over the painted cap's own fade; the crew and the caesar lower and flatter.
* hightop (High Top) - a faceted box column (a superellipsoid: straight sides, a flat top, rounded edges) rising from a
  high fade line, pebbled by round knobs.
* dreadlocks - long, thick, irregular faceted locs in stacked segments from a knotted root mass, over the ears and the
  nape onto the shoulders (kept off the torso: ref/classic/torso_m.obj as a height field).
* braids - thick plaited rows (faceted herringbone lobes) from the forehead to the nape, each carrying on into a
  hanging plait; box_braids - plaits from square-parted roots all over the head, a knotted root at each.
* long / long_wavy - a combed top (tufts swept back from the hairline) and chunky faceted locks (a lens section,
  tapering) falling round the head in two layers; the wavy ones swing side to side (kept off the face).
  The hanging styles split every strand at y ~-0.5: the part above in static pieces, the part below in swinging chains
  by sector (hairfx swing, length "hang", the interval across the cut in both pieces), as the v9 chains did.
v10 also adds a finer pebbling (micro knobs) to the six styles' knob surfaces (the curls within a knot).

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
    # (v10) combed clumps: spec["comb"] = (stretch, dir_fn): each knob drawn out along the comb direction at its
    # centre (dir_fn(K, KN) -> unit tangents), its tip end narrowing (a tuft lying the way the hair is combed)
    comb = spec.get("comb")
    Kd = comb[1](K, KN) if comb else None
    bump = np.zeros(len(S))
    tone = np.ones(len(S))
    for i0 in range(0, len(S), 2048):
        blk = S[i0:i0 + 2048]
        D = blk[:, None, :] - K[None, :, :]
        if comb:
            al = np.einsum("nkc,kc->nk", D, Kd)
            ac2 = (D ** 2).sum(-1) - al ** 2
            e = comb[0]
            # forward of the centre the tuft is long and narrows; behind it a short round root
            ea = np.where(al > 0, e, 1.0)
            narrow = 1 + 0.6 * np.clip(al / (Kr[None, :] * e), 0, 1)
            d2 = (al / ea) ** 2 + ac2 * narrow ** 2
        else:
            d2 = (D ** 2).sum(-1)
        b = np.sqrt(np.clip(1 - d2 / (Kr[None, :] ** 2), 0, 1))
        j = np.argmax(b, axis=1)
        bump[i0:i0 + 2048] = b[np.arange(len(blk)), j]
        tone[i0:i0 + 2048] = Ktone[j]
    # (v10) a second, finer pebbling on the knobs (the curls within a clump): spec["micro"] = (spacing k, height k)
    if spec.get("micro"):
        mk_, mh_ = spec["micro"]
        rng2 = np.random.default_rng(seed + 91)
        K2, _, Kt2 = poisson_on_scalp(thick, lambda P, w: sp * mk_ * (0.75 + 0.5 * np.clip(w / tmax, 0, 1)), rng2,
                                      wmin=tmin * 0.7)
        Kr2 = sp * mk_ * (0.75 + 0.5 * np.clip(Kt2 / tmax, 0, 1)) * 0.8
        micro = np.zeros(len(S))
        for i0 in range(0, len(S), 2048):
            blk = S[i0:i0 + 2048]
            d2 = ((blk[:, None, :] - K2[None, :, :]) ** 2).sum(-1)
            micro[i0:i0 + 2048] = np.sqrt(np.clip(1 - d2 / (Kr2[None, :] ** 2), 0, 1)).max(axis=1)
        bump = np.clip(bump * (1 - mh_) + mh_ * bump * micro + 0.35 * mh_ * micro, 0, 1.2)
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
WAVES_LEVELS = (0.0, 0.2, 0.44, 0.72)  # the rows across every ridge: trough, rise, crest, back slope
WAVES_TROUGH = 0.024  # the shell's height over the head in the troughs (the cap is at CAP_H 0.020 under it)
WAVES_DEPTH = 0.026  # crest over trough
WAVES_DOME = 0.024  # extra at the crown over the flat top of the classic head (the waves round over it)


def cov_field(kind, sig_deg=(3.0, 5.0)):
    """the cap's painted coverage (kind, with the ear line) on a fine (theta, az) grid, blurred by sig_deg (theta,
    az) degrees; returns a sampler (theta, az) -> (sharp, blurred)"""
    R = ref()
    ths = np.radians(np.arange(0.0, math.degrees(THETA_MAX) + 1.01, 1.0))
    azs = np.radians(np.arange(0.0, 360.0, 2.0))
    TH, AZ = np.meshgrid(ths, azs, indexing="ij")
    c = R.cov_at(kind, TH.reshape(-1), AZ.reshape(-1)).reshape(TH.shape)
    b = c.copy()
    for ax, sg, step, wrap in ((0, sig_deg[0], 1.0, False), (1, sig_deg[1], 2.0, True)):
        s = sg / step
        r = int(math.ceil(3 * s))
        k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
        k /= k.sum()
        if wrap:
            b = sum(w * np.roll(b, o, axis=1) for o, w in zip(range(-r, r + 1), k))
        else:
            pad = np.pad(b, ((r, r), (0, 0)), mode="edge")
            b = sum(w * pad[i:i + b.shape[0]] for i, w in enumerate(k))

    def at(th, az):
        th = np.clip(np.asarray(th, np.float64), ths[0], ths[-1])
        fi = th / np.radians(1.0)
        i0 = np.clip(np.floor(fi).astype(int), 0, len(ths) - 2)
        ti = fi - i0
        fa = (np.asarray(az, np.float64) % TAU) / np.radians(2.0)
        j0 = np.floor(fa).astype(int) % len(azs)
        tj = fa - np.floor(fa)
        j1 = (j0 + 1) % len(azs)
        out = []
        for g in (c, b):
            a = g[i0, j0] * (1 - tj) + g[i0, j1] * tj
            bb = g[i0 + 1, j0] * (1 - tj) + g[i0 + 1, j1] * tj
            out.append(a * (1 - ti) + bb * ti)
        return out
    return at


def waves_shell(seed=71, ncol=58, kind="low", levels=WAVES_LEVELS, trough=WAVES_TROUGH, depth=WAVES_DEPTH,
                dome=WAVES_DOME, lineup_pull=4.5, lineup_cov=0.2):
    """the 360 waves: a close shell on the cap's polar UV sculpted with the ridge field (fades_tex.waves_field), its
    rows laid along every ridge's levels (trough, rise, crest, back slope, fall: the grooves are real geometry, with
    ncol vertices round every ridge, so each crest catches the light and each trough shades), a fan at the crown's
    pole (no pinched ring). The ridges' relief rides on the painted coverage (kind): full where the hair is full,
    coming down to the cap's height over the last ~0.05 studs inside the hairline and through the fade (the shell's
    edge tapers to nothing: no rim standing off the head; the faded sides are the painted cap's, as the game paints
    every fade); trimmed where no look paints hair. Vertex colours: the troughs' occlusion."""
    R = ref()
    cov = cov_field(kind)
    vv = np.linspace(0.0, 1.0, 2001)
    cols = []
    for j in range(ncol + 1):
        u = (j % ncol) / ncol
        ph, ridge, am, calm = fades_tex.waves_field(np.full_like(vv, u), vv, seed)
        cols.append((np.maximum.accumulate(ph), am))
    lo_phase = max(c[0][0] for c in cols)
    hi_phase = max(c[0][-1] for c in cols)
    lv = np.array([k + f for k in range(int(math.floor(lo_phase)), int(math.ceil(hi_phase)) + 1) for f in levels])
    lv = lv[lv > lo_phase + 0.08]
    nr = len(lv)
    V = np.zeros((nr, ncol + 1))
    A = np.zeros((nr, ncol + 1))
    for j, (ph, am) in enumerate(cols):
        V[:, j] = np.interp(lv, ph, vv, right=1.0)
        A[:, j] = np.interp(V[:, j], vv, am)
    V = np.minimum(np.maximum.accumulate(V, axis=0), 1.0)
    PR = np.tile(fades_tex.waves_profile(lv - np.floor(lv))[:, None], (1, ncol + 1))
    TH = V * THETA_MAX
    AZ = np.tile(np.arange(ncol + 1) / ncol * TAU, (nr, 1))
    # the shell's edge: the rows stop on the painted coverage's edge line (th_edge, per column). Across the forehead
    # (wf) that is the line-up (the coverage's lineup_cov line), its edge band sampling the painted image a little
    # inside it (solid hair to a crisp edge); at the temples, the sides and the nape it is the coverage's 0.01 line
    # (the painted fade shows through the flattened shell there; nothing of the shell where no look paints hair,
    # the ears clear)
    azc = np.arange(ncol + 1) / ncol * TAU
    da = np.abs((azc % TAU) - math.pi)
    wf = 1 - sstep(0.75, 1.1, da)
    tf = np.radians(np.arange(0.0, math.degrees(THETA_MAX) + 0.01, 0.25))
    th_edge = np.zeros(ncol + 1)
    for j, a in enumerate(azc):
        c = cov(tf, np.full_like(tf, a))[0]
        out = np.nonzero(c < lineup_cov * wf[j] + 0.01 * (1 - wf[j]))[0]
        th_edge[j] = tf[out[0]] if len(out) else THETA_MAX
    THc = np.minimum(TH, th_edge[None, :])
    pull = math.radians(lineup_pull)
    THuv = THc - wf[None, :] * pull * sstep(0, 1, (THc - (th_edge[None, :] - 2.5 * pull)) / (2.5 * pull))
    TH = THc
    V = THuv / THETA_MAX
    # the pole: one vertex, fanned to the first ring
    TH = np.concatenate([[0.0], TH.reshape(-1)])
    AZ = np.concatenate([[0.0], AZ.reshape(-1)])
    Vf = np.concatenate([[0.0], V.reshape(-1)])
    PRf = np.concatenate([[PR[0, 0] * 0.5], PR.reshape(-1)])
    Af = np.concatenate([[0.0], A.reshape(-1)])
    sharp, blur = cov(TH, AZ)
    # how much of the relief stands: the blurred coverage from 0.5 (the sharp edge itself) to ~0.95 (2-3 degrees in)
    e = sstep(0.45, 0.93, blur) * (sharp > 0.0)
    S = ray_hit(dirs(TH, AZ))  # the exact classic head (the radial table's bilinear chords sag up to ~1 mm)
    Nh = head_n(S)
    # the flat top of the classic head rounded over: a low dome, 0 where the top's rounded edge begins
    rxz = np.hypot(S[:, 0], S[:, 2] - 0.02)
    top = np.clip(1 - (rxz / 0.42) ** 2, 0, 1) * sstep(0.3, 0.5, S[:, 1])
    hgt = CAP_H + 0.003 + e * (trough - CAP_H - 0.003 + depth * PRf * np.clip(Af, 0, 1) + dome * top)
    P = S + Nh * hgt[:, None]
    # rows with no relief anywhere (the fade's and the nape's, below the weight line) keep only their troughs
    E = e[1:].reshape(nr, ncol + 1) * (sharp[1:].reshape(nr, ncol + 1) > 0)
    fr = lv - np.floor(lv)
    rows = [i for i in range(nr) if fr[i] < 1e-6 or E[i].max() > 0.03 or i == 0 or i == nr - 1]
    T = [(0, 1 + j + 1, 1 + j) for j in range(ncol)]
    for i0, i1 in zip(rows[:-1], rows[1:]):
        for j in range(ncol):
            a, b = 1 + i0 * (ncol + 1) + j, 1 + i0 * (ncol + 1) + j + 1
            d, c = 1 + i1 * (ncol + 1) + j, 1 + i1 * (ncol + 1) + j + 1
            T += [(a, b, c), (a, c, d)]
    T = np.array(T)
    # (normals out: the grid runs theta down, az round toward +X; orient by the head's normal)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    if np.einsum("ij,ij->i", fn, Nh[T[:, 0]]).mean() < 0:
        T = T[:, [0, 2, 1]]
    Pa, Pb, Pc = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    area = np.linalg.norm(np.cross(Pb - Pa, Pc - Pa), axis=1)
    keep = (area > 1e-8) & (sharp[T] > 0.0).any(axis=1)
    brow = (P[:, 2] < -0.35) & (np.abs(P[:, 0]) < 0.38) & (P[:, 1] < 0.345)
    keep &= ~brow[T].any(axis=1)
    T = T[keep]
    used = np.unique(T)
    remap = -np.ones(len(P), np.int64)
    remap[used] = np.arange(len(used))
    Pu = push_clear(P[used])
    UV = np.stack([AZ[used] / TAU, Vf[used]], -1)
    UV[used == 0, 0] = 0.5
    # occlusion: dark in the troughs (where the relief stands), lit on the crests
    occ = 1.0 - 0.55 * e[used] * np.clip(Af[used] * 1.4, 0, 1) * (1 - PRf[used]) ** 1.6
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    pc = Piece("HairFur", "cap", material="Plastic", castShadow=False, hideUnder=dict(HIDE))
    emit(pc, Pu, remap[T], UV, COL, Pu - head_n(Pu), flat=False)
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
                                  dome=0.0, hl_margin=0.022), tmax=top, knob=0.075, kh=0.4, tmin=0.026, level=4,
                micro=(0.5, 0.2))
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


# ============================================================================== v10: the straight-hair styles
CROWN_COMB = np.array([0.0, 0.62, 0.16])  # the straight crops are combed out from a point at the back of the top


def comb_dir(origin=CROWN_COMB, fwd=0.55):
    """the comb's direction on the scalp at K (normals KN): out from `origin`, the top's tufts leaning forward"""
    def f(K, KN):
        d = K - origin
        d = d + np.array([0.0, 0.0, -fwd]) * np.clip(KN[:, 1:2], 0, 1)
        d = d - KN * np.einsum("ij,ij->i", d, KN)[:, None]
        n = np.linalg.norm(d, axis=1, keepdims=True)
        d = np.where(n > 1e-6, d / np.maximum(n, 1e-9), np.array([0.0, 0.0, -1.0]))
        return d
    return f


STRAIGHT = ["Straight", "Wavy"]


def comb_top_entry(key, styles, kind, types=STRAIGHT, top=0.13, front=0.1, side=0.05, back=0.07, knob=0.09,
                   seed=3, cap_extra=None, ramp=0.12, kh=0.6, stretch=2.8, micro=(0.45, 0.2), level=5, fwd=0.55):
    """a straight-hair crop in the stylised clump look: the knob surface of the curly fades (fade_top_entry) with
    its knobs drawn out into combed tufts (comb_dir: forward on the top, down the sides and the back), a finer
    pebbling on each tuft, over the painted cap's own fade"""
    spec = dict(thick=taper_thick(top=top, front=front, side=side, back=back, line=fade_line(kind), ramp=ramp),
                tmax=top, knob=knob, kh=kh, tmin=0.022, level=level, comb=(stretch, comb_dir(fwd=fwd)), micro=micro,
                kr=(0.8, 0.95))
    pieces = knob_volume(spec, seed)
    entry = dict(styles=styles, types=types, cap={"cut": "style", "density": 1}, family="stylised", capEarLine=True,
                 style="stylised combed tufts (build_stylised.py)")
    entry.update(cap_extra or {})
    return entry, pieces


def buzz_entry(seed=12):
    """the buzz: a close, even shell of small chunky pebbles over the painted cap (every type)"""
    spec = dict(thick=taper_thick(top=0.036, front=0.032, side=0.032, back=0.032, line=fade_line("none"), ramp=0.05,
                                  dome=0.0, hl_margin=0.012),
                tmax=0.036, knob=0.042, kh=0.55, tmin=0.02, level=5, micro=(0.55, 0.2), hmin=0.024)
    pieces = knob_volume(spec, seed)
    return dict(styles=["Buzz Cut"], types=None, cap={"cut": "style", "density": 1}, family="stylised",
                capEarLine=True, style="stylised close pebble shell (build_stylised.py)"), pieces


# ============================================================================== v10: hanging styles
_TORSO = None


def torso_floor(P):
    """the shoulders / neck / upper back under the head (ref/classic/torso_m.obj) as a height field: the highest
    torso point within 0.07 of each (x, z), -9 where there is none"""
    global _TORSO
    if _TORSO is None:
        V = np.array([l.split()[1:4] for l in open(os.path.join(HERE, "ref", "classic", "torso_m.obj"))
                      if l.startswith("v ")], np.float64)
        V = V[V[:, 1] > -1.6]
        _TORSO = V
    P = np.atleast_2d(P)
    V = _TORSO
    out = np.full(len(P), -9.0)
    for i0 in range(0, len(P), 512):
        blk = P[i0:i0 + 512]
        d2 = (blk[:, None, 0] - V[None, :, 0]) ** 2 + (blk[:, None, 2] - V[None, :, 2]) ** 2
        y = np.where(d2 < 0.07 ** 2, V[None, :, 1], -9.0)
        out[i0:i0 + 512] = y.max(axis=1)
    return out


def hang_path(root, n, length, rng, radius, lift=0.25, stiff=0.3, gravity=1.0, front_y=0.36, side_y=None,
              ride=0.03, wander=0.05, step=0.02, body=0.05, sway=None, face_w=0.08):
    """grow_path for the hanging styles: the same scalp / ear / face guards, then down over the shoulders and the
    upper back kept `body` over the torso (torso_floor); sway(L) -> a sideways offset (waves)"""
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
            if p[1] < -0.5:
                fl = torso_floor(p[None])[0]
                if p[1] < fl + radius + body:
                    # over the shoulder: slide off it outward / backward, never into it
                    p = p.copy()
                    p[1] = fl + radius + body
                    out = np.array([p[0], 0.0, p[2] - 0.05])
                    out /= max(np.linalg.norm(out), 1e-6)
                    d = d + out * 0.5
                    d /= np.linalg.norm(d)
        if p[2] < -0.3 and abs(p[0]) < 0.44 and p[1] < front_y + radius:
            break
        if side_y is not None and p[1] < side_y + radius:
            break
        L += float(np.linalg.norm(p - pts[-1]))
        pts.append(p)
    P = np.array(pts)
    if sway is not None and len(P) > 3:
        s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
        T = np.gradient(P, axis=0)
        T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
        side = np.cross(T, np.array([0.0, 0.0, 1.0]) * np.sign(P[:, 2:3] + 1e-6) + np.array([1e-3, 0, 0]))
        side /= np.maximum(np.linalg.norm(side, axis=1, keepdims=True), 1e-9)
        off = sway(s)[:, None] * side
        Q = P + off
        # (the waves never into the head / the torso: a pass of the guards)
        for i in range(len(Q)):
            q = Q[i]
            s_ = sd(q[None])[0]
            if s_ < radius + CLEAR + 0.004:
                Q[i] = q + head_n(q[None])[0] * (radius + CLEAR + 0.004 - s_)
            # (and never swung in front of the face: the brows' span stays clear, check_classic_fit's brow test)
            q = Q[i]
            if q[2] < -0.3 and q[1] < 0.36 and q[1] > -0.68 and abs(q[0]) < 0.4 + face_w:
                Q[i][0] = math.copysign(0.4 + face_w, q[0] if abs(q[0]) > 1e-6 else P[i][0])
        P = np.vstack([P[:1], Q[1:]])
    return P


class Chains:
    """the hanging pieces: static upper pieces (`ntop` of them by the strands' root sector round the head, named
    top_name, top_name2 ...: no piece over the 20k triangle limit) and up to `n` swinging chains (hairfx swing, one
    segment, length "hang") by sector round the head. A strand that reaches below `cut` is split there: the part
    above in its upper piece, the part below in its sector's chain, the interval across the cut in both (a sleeve:
    the swinging part never opens a gap); the chain's pivot is the mean of its cut points, its tip the mean of its
    tips"""

    def __init__(self, prefix, chain, n, cut, stiff, mass, mat="Fabric", ntop=1, top_name="HairTop"):
        self.prefix, self.chain, self.n, self.cut, self.stiff, self.mass, self.mat = prefix, chain, n, cut, stiff, mass, mat
        self.ntop, self.top_name = ntop, top_name
        self.tops = {}
        self.ch = {}

    def top(self, g=0):
        if g not in self.tops:
            nm = self.top_name if g == 0 else f"{self.top_name}{g + 1}"
            self.tops[g] = Piece(nm, "clump", material=self.mat, castShadow=True, hideUnder=dict(HIDE))
        return self.tops[g]

    def top_of(self, root):
        a = math.atan2(root[0], -root[2]) % TAU  # 0 at the front
        return int(a / TAU * self.ntop) % self.ntop

    def piece(self, k):
        if k not in self.ch:
            nm = f"{self.prefix}{k + 1:02d}"
            self.ch[k] = [Piece(nm, "clump", material=self.mat, castShadow=True,
                                hideUnder={"headgear": False, "hood": True}), [], []]
        return self.ch[k]

    def split(self, pts):
        """index of the first point under the cut (None: the strand stays in its upper piece)"""
        below = np.nonzero(pts[:, 1] < self.cut)[0]
        if not len(below) or below[0] < 2 or below[0] > len(pts) - 3:
            return None
        return int(below[0])

    def add(self, pts, emit_fn):
        """emit_fn(piece, pts, part, (i0, i1)): part 'all' | 'upper' | 'lower'; the sector of the strand's cut"""
        top = self.top(self.top_of(pts[0]))
        k = self.split(pts)
        if k is None:
            emit_fn(top, pts, "all", (0, len(pts)))
            return
        a = math.atan2(pts[k][0], pts[k][2]) % TAU  # 0 at the back
        sec = int(a / TAU * self.n) % self.n
        c = self.piece(sec)
        emit_fn(top, pts, "upper", (0, k + 1))
        emit_fn(c[0], pts, "lower", (k - 1, len(pts)))
        c[1].append(pts[k - 1])
        c[2].append(pts[-1])

    def finish(self):
        out = [self.tops[g] for g in sorted(self.tops) if self.tops[g].nt]
        for k in sorted(self.ch):
            p, piv, tips = self.ch[k]
            if p.nt == 0:
                continue
            cid = f"{self.chain}{k + 1:02d}"
            p.meta["hairfx"] = dict(kind="swing", chain=cid, seg=1, stiff=self.stiff, mass=self.mass,
                                    pivot=[round(float(x), 4) for x in np.mean(piv, 0)],
                                    tip=[round(float(x), 4) for x in np.mean(tips, 0)])
            p.meta["length"] = "hang"
            out.append(p)
        return out


def tube_part(piece, pts, part, rng_, radius, sides, section, rng, flat, ao, up0, tone, v0=0.05, v1=1.0):
    """sweep() over the strand's points rng_ = (i0, i1) of `part`: the root cap only on the strand's own root, the
    tip cap only on its own tip; v kept on the whole strand's root (0) to tip (1)"""
    i0, i1 = rng_
    n = len(pts)
    P = pts[i0:i1]
    R = radius[i0:i1]
    va = v0 + (v1 - v0) * i0 / (n - 1)
    vb = v0 + (v1 - v0) * (i1 - 1) / (n - 1)
    sweep(piece, P, R, sides, lambda i, a: section(i + i0, a), rng, v0=va, v1=vb, flat=flat, ao=ao,
          tip_cap=part in ("all", "lower"), root_cap=part in ("all", "upper"), up0=up0, tone=tone)


def all_roots(rng, spacing, line, hl_margin=0.02, extra=None):
    return top_roots(rng, spacing, line, hl_margin=hl_margin, extra=extra)


def dreadlocks_entry(seed=57, spacing=0.19, r0=0.05):
    """long locs in the short locs' chunky style: thick, irregular, faceted locs in stacked segments (a bead every
    other ring) growing from a knotted root mass, falling over the ears and the nape onto the shoulders / upper back;
    the front ones stop above the brows. Swinging chains below the head (length "hang")"""
    rng = np.random.default_rng(seed)
    line = lambda da: np.interp(da, [0, 0.8, 1.3, 1.7, 2.3, math.pi], [0.36, 0.33, 0.31, 0.3, 0.12, -0.02])
    S, N, _ = top_roots(rng, spacing, line, hl_margin=0.022)
    ch = Chains("HairLoc", "Loc", 9, -0.52, 0.35, 1.4, ntop=3, top_name="HairLocs")
    sides = 5
    for s, n in zip(S, N):
        dc = float(np.linalg.norm((s - CROWN)[[0, 2]]))
        front = s[2] < -0.2 and abs(s[0]) < 0.45
        # long enough to fall past the jaw onto the shoulders from wherever the loc grows
        length = rng.uniform(0.3, 0.38) if front else (s[1] + 0.6) * 1.15 + rng.uniform(0.3, 0.5)
        pts = hang_path(s, n, length, rng, radius=r0, lift=0.22, stiff=0.3, gravity=1.0, front_y=0.36,
                        ride=BASE_RIDE + 0.04 * max(0.0, 1 - dc / 0.55), wander=0.05, step=0.02)
        if len(pts) < 4:
            continue
        pts, L = resample(pts, 0.042)
        m = len(pts)
        if m < 3:
            continue
        r = r0 * rng.uniform(0.85, 1.15)
        wob = rng.uniform(0, TAU, 3)
        tt = np.linspace(0, 1, m)
        radius = r * (1 + 0.07 * np.sin(tt * 9 + wob[0])) * (1 - 0.22 * tt ** 2)
        # the stacked segments: a bead on every other ring
        radius = radius * np.where(np.arange(m) % 2 == 0, 1.1, 0.88)
        radius[0] *= 0.85
        irr = rng.uniform(0.86, 1.12, sides)
        tone = rng.uniform(0.84, 1.02)

        def section(i, a, irr=irr):
            return irr[int(round(a / TAU * sides)) % sides]

        def ao(P, t):
            return 0.45 + 0.55 * np.clip(sd(P) / 0.14, 0, 1) ** 0.6

        ch.add(pts, lambda pc, P_, part, rg, radius=radius, section=section, n=n, tone=tone:
               tube_part(pc, P_, part, rg, radius, sides, section, rng, True, ao, n, tone))
    return root_mass(line, 0.055, seed) + ch.finish()


def plait(piece, pts, width, height, rng, pitch=0.07, tone=1.0, up0=None, taper=0.25, v0=0.2, v1=1.0, sides=3):
    """a plait along pts: faceted lobes alternating side to side (the three-strand braid's herringbone), tilted
    across the plait, narrowing toward the tip by `taper`"""
    pts = np.asarray(pts)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    L = s[-1]
    if L < pitch:
        return
    Tn, Nn, Bn = frames_along(pts, up0 if up0 is not None else head_n(pts[:1])[0])
    nl = int(L / (pitch / 2))
    for k in range(nl):
        sk = (k + 0.5) * pitch / 2
        t = sk / L
        p = np.array([np.interp(sk, s, pts[:, j]) for j in range(3)])
        i = min(len(pts) - 1, int(np.searchsorted(s, sk)))
        tan, nrm, bn = Tn[i], Nn[i], Bn[i]
        w = width * (1 - taper * t) * (0.94 + 0.08 * rng.random())
        h = height * (1 - taper * t)
        sg = 1 if k % 2 == 0 else -1
        ang = math.radians(34) * sg
        ax = tan * math.cos(ang) + bn * math.sin(ang)
        ax /= np.linalg.norm(ax)
        bx = np.cross(nrm, ax)
        c = p + bn * sg * w * 0.22
        spindle(piece, c, ax, bx, nrm, (pitch * 0.62, w * 0.5, h * 0.55), rng, tone=tone * rng.uniform(0.92, 1.03),
                vt=v0 + (v1 - v0) * t, sides=sides)
    # the tip: a small faceted knot
    q = pts[-1]
    lump(piece, q, Tn[-1], (width * 0.32, width * 0.32, width * 0.36), rng, kind="octa0", jitter=0.1, tone=tone)


def box_braids_entry(seed=77, spacing=0.215, w=0.075):
    """box braids: plaits from square-parted roots all over the head (a knotted root at each), falling to the
    shoulders and the upper back, the front ones swept to the sides; swinging chains below the head"""
    rng = np.random.default_rng(seed)
    line = lambda da: np.interp(da, [0, 0.8, 1.3, 1.7, 2.3, math.pi], [0.36, 0.33, 0.31, 0.3, 0.12, -0.02])
    S, N, _ = top_roots(rng, spacing, line, hl_margin=0.025)
    ch = Chains("HairBraid", "Braid", 10, -0.52, 0.4, 1.2, ntop=2, top_name="HairBraids")
    # the scalp between the braids: a thin, dark, low knob shell (the parted sections)
    base = knob_volume(dict(thick=taper_thick(top=0.03, front=0.026, side=0.026, back=0.026, line=line, ramp=0.03,
                                              dome=0.0, hl_margin=0.02), tmax=0.03, knob=0.09, kh=0.35, tmin=0.02,
                            level=4, name="HairBase"), seed + 3)
    for s, n in zip(S, N):
        front = s[2] < -0.15 and abs(s[0]) < 0.4
        length = (s[1] + 0.6) * 1.15 + rng.uniform(0.35, 0.55)
        pts = hang_path(s, n, length, rng, radius=w * 0.5, lift=0.1 if front else 0.2, stiff=0.25, gravity=1.0,
                        front_y=0.4, ride=0.03, wander=0.04, step=0.02)
        if len(pts) < 4:
            continue
        pts, L = resample(pts, 0.02)
        tone = rng.uniform(0.86, 1.02)
        lump(ch.top(ch.top_of(s)), s + n * (CLEAR + 0.018), n, (w * 0.5, w * 0.5, 0.022), rng, kind="octa1", jitter=0.1, tone=tone)

        def em(pc, P_, part, rg, tone=tone, n=n, L=L):
            i0, i1 = rg
            seg_ = P_[i0:i1]
            m = len(P_)
            plait(pc, seg_, w, w * 0.8, rng, pitch=0.09, tone=tone, up0=n, taper=0.22,
                  v0=0.2 + 0.8 * i0 / (m - 1), v1=0.2 + 0.8 * (i1 - 1) / (m - 1))
        ch.add(pts, em)
    return base + ch.finish()


def braids_entry(seed=88, nrows=9, dlat=15.0, w=0.085):
    """braids: plaited rows along the scalp from the forehead over the top to the nape (cornrows' latitudes, fewer
    and thicker), each row carrying on into a hanging plait down the back; swinging chains below the head"""
    rng = np.random.default_rng(seed)
    ch = Chains("HairBraid", "Braid", 9, -0.52, 0.45, 1.3)
    half = (nrows - 1) / 2
    for i in range(nrows):
        lat = math.radians((i - half) * dlat)
        psis = np.radians(np.linspace(-20, 215, 700))
        D = np.stack([np.full_like(psis, math.sin(lat)), math.cos(lat) * np.sin(psis + math.radians(20)),
                      -math.cos(lat) * np.cos(psis + math.radians(20))], -1)
        D[:, 0] += math.sin(lat) * 0.18 * np.sin(np.clip((psis - 0.6) / 2.4, 0, 1) * math.pi)
        D /= np.linalg.norm(D, axis=1, keepdims=True)
        Ssc = ray_hit(D)
        inside = in_hairline(Ssc, 0.022, 0.001) > 0.5
        if not inside.any():
            continue
        idx = np.where(inside)[0]
        Ssc = Ssc[idx[0]:idx[-1] + 1]
        Nsc = head_n(Ssc)
        on = Ssc + Nsc * (CLEAR + w * 0.4)
        on, _ = resample(on, 0.02)
        # the hanging part: from the row's end at the nape, down
        n_end = head_n(on[-1:])[0]
        hang = hang_path(Ssc[-1], n_end, rng.uniform(0.75, 0.95), rng, radius=w * 0.5, lift=0.0, stiff=0.0,
                         gravity=1.0, ride=w * 0.4 - w * 0.45, wander=0.03, step=0.02)
        pts = np.vstack([on, hang[1:]]) if len(hang) > 2 else on
        pts, L = resample(pts, 0.02)
        tone = rng.uniform(0.88, 1.02)

        def em(pc, P_, part, rg, tone=tone):
            i0, i1 = rg
            m = len(P_)
            ups = head_n(P_[i0:i0 + 1])[0]
            plait(pc, P_[i0:i1], w, w * 0.7, rng, pitch=0.07, tone=tone, up0=ups, taper=0.3 * (i1 - i0) / m,
                  v0=0.2 + 0.8 * i0 / (m - 1), v1=0.2 + 0.8 * (i1 - 1) / (m - 1))
        ch.add(pts, em)
    return ch.finish()


def long_entry(key, wavy=False, seed=95):
    """long hair in the stylised clump look: a combed top (the knob surface drawn out into tufts swept back from the
    hairline, parted a little off centre) and chunky faceted locks (a lens-shaped section, tapering to a point)
    falling from round the head onto the shoulders and the upper back, a second layer over the first; the locks in
    front of the ears frame the face. Swinging chains below the head"""
    rng = np.random.default_rng(seed)
    part_x = 0.08

    def comb_back(K, KN):
        o = np.array([part_x, 0.62, -0.25])
        d = K - o
        d[:, 1] -= 0.4
        d = d - KN * np.einsum("ij,ij->i", d, KN)[:, None]
        return d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
    line = fade_line("none")
    top = knob_volume(dict(thick=taper_thick(top=0.06, front=0.055, side=0.05, back=0.05, line=line, ramp=0.04,
                                             dome=0.1, hl_margin=0.012), tmax=0.06, knob=0.085, kh=0.5, tmin=0.02,
                           level=5, comb=(2.6, comb_back), micro=(0.5, 0.2), kr=(0.8, 0.95), name="HairTop"), seed)
    ch = Chains("HairClump", "Clump", 10, -0.5, 0.3, 1.0, ntop=2, top_name="HairLocks", mat="SmoothPlastic")
    # roots: two rings round the head (the under layer low, the over layer higher), sides and back only
    roots = []
    for layer, (y0, n_, ride) in enumerate(((0.18, 24, 0.035), (0.4, 19, 0.075))):
        for j in range(n_):
            a = (j + 0.5 * layer) / n_ * TAU  # 0 at the back
            az = a
            if abs(((az + math.pi) % TAU) - math.pi) < 0.0:
                continue
            da = abs(((az % TAU) - math.pi))  # 0 at the front
            if da < 0.62:  # the face: no locks there
                continue
            th = math.acos(np.clip((y0 - 0.05) / 0.6, -1, 1))
            S_, N_ = scalp(np.array([th]), np.array([az]))
            roots.append((S_[0], N_[0], layer, ride))
    sway = (lambda s: 0.028 * np.sin(s * TAU / 0.32) * np.clip(s / 0.15, 0, 1)) if wavy else None
    for s, n, layer, ride in roots:
        is_front = s[2] < -0.1
        length = rng.uniform(0.95, 1.15) if not is_front else rng.uniform(0.8, 0.95)
        if layer == 1:
            length *= 0.92
        w = rng.uniform(0.12, 0.15) * (1.08 if layer == 1 else 1.0)
        th = w * rng.uniform(0.3, 0.36)
        pts = hang_path(s, n, length, rng, radius=th, lift=0.05, stiff=0.1, gravity=1.0, front_y=0.3, ride=ride,
                        wander=0.02, step=0.02, body=0.04, sway=sway)
        if len(pts) < 4:
            continue
        pts, L = resample(pts, 0.045 if not wavy else 0.04)
        m = len(pts)
        tt = np.linspace(0, 1, m)
        radius = np.full(m, 1.0) * (1 - 0.62 * tt ** 2.6) * (0.8 + 0.2 * sstep(0, 0.12, tt))
        tone = rng.uniform(0.82, 1.0) * (1.0 if layer == 1 else 0.88)
        sides = 6

        def section(i, a, w=w, th=th):
            # a lens: wide across the head's surface (the binormal), thin out from it; faceted
            return 1.0 / math.sqrt((math.cos(a) / th) ** 2 + (math.sin(a) / (w * 0.5)) ** 2)

        def ao(P, t):
            return 0.5 + 0.5 * np.clip(sd(P) / 0.1, 0, 1) ** 0.6 * (0.8 + 0.2 * t)

        ch.add(pts, lambda pc, P_, part, rg, radius=radius, section=section, n=n, tone=tone:
               tube_part(pc, P_, part, rg, radius, sides, section, rng, True, ao, n, tone))
    return top + ch.finish()


def hightop_v10_thick():
    """the high top: a flat-topped column rising from a high fade line, straight sides a little flared, the
    corners rounded"""
    line = fade_line("high")

    def f(S):
        n = head_n(S)
        da = da_of(S)
        w = in_hairline(S, 0.012, 0.02) * sstep(0.0, 0.05, S[:, 1] - line(da))
        # the column's top at y ~1.0: the distance from the scalp point to it along the normal, the sides a slab
        up = np.clip(n[:, 1], 0, 1)
        top_h = np.clip(1.0 - S[:, 1], 0.0, 0.6) / np.maximum(up, 0.35)
        side_h = 0.11 + 0.05 * sstep(0.3, 0.55, S[:, 1])
        h = np.where(up > 0.55, np.minimum(top_h, 0.5), side_h + (np.minimum(top_h, 0.5) - side_h) * sstep(0.2, 0.55, up))
        return h * w
    return f


def hightop_box(seed=21, a=0.645, b=0.76, yc=0.3, pexp=5.0, level=5, knob=0.085, kh=0.035):
    """the high top as a faceted box column: rays from a point inside the head (0, yc, 0.02) to a superellipsoid (half
    widths a, b, a; exponent pexp: straight sides, a flat top, rounded edges), never under the scalp (CLEAR), kept
    above the high fade's weight line; pebbled by round knobs (kh studs) and flat shaded like the afro, a skirt
    down to the painted cap round its open edge"""
    rng = np.random.default_rng(seed)
    O = np.array([0.0, yc, 0.02])
    V, F = ico(level)
    # the head along each ray (bisection on the classic head's field)
    lo = np.zeros(len(V))
    hi = np.full(len(V), 1.4)
    for _ in range(40):
        mid = (lo + hi) / 2
        out = sd(O + V * mid[:, None]) > 0
        hi = np.where(out, mid, hi)
        lo = np.where(out, lo, mid)
    rh = (lo + hi) / 2
    S = O + V * rh[:, None]
    rb = (np.abs(V[:, 0] / a) ** pexp + np.abs(V[:, 1] / b) ** pexp + np.abs(V[:, 2] / a) ** pexp) ** (-1 / pexp)
    line = fade_line("high")
    da = da_of(S)
    ok = (in_hairline(S, 0.012, 0.02) > 0.5) & (S[:, 1] > line(da) + 0.02) & (rb > rh + 0.03)
    keep = ok[F].all(axis=1)
    F = F[keep]
    used = np.unique(F)
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    F = remap[F]
    V, S, rh, rb = V[used], S[used], rh[used], rb[used]
    r = np.maximum(rb, rh + CLEAR + 0.01)
    P0 = O + V * r[:, None]
    # knobs on the column's surface
    K = P0[rng.permutation(len(P0))]
    acc = []
    for q in K:
        if not acc or np.min(np.linalg.norm(np.array(acc) - q, axis=1)) > knob * 1.25:
            acc.append(q)
    K = np.array(acc)
    Kr = knob * rng.uniform(0.75, 0.95, len(K))
    Kt = rng.uniform(0.84, 1.04, len(K))
    bump = np.zeros(len(P0))
    tone = np.ones(len(P0))
    for i0 in range(0, len(P0), 2048):
        d2 = ((P0[i0:i0 + 2048, None, :] - K[None]) ** 2).sum(-1)
        bb = np.sqrt(np.clip(1 - d2 / Kr[None] ** 2, 0, 1))
        j = bb.argmax(1)
        bump[i0:i0 + 2048] = bb[np.arange(len(j)), j]
        tone[i0:i0 + 2048] = Kt[j]
    # (the edge ring hugs the cap: the relief fades in over the first ~0.05 of thickness)
    th = r - rh
    w = sstep(0.03, 0.09, th)
    P = O + V * (r + kh * (bump - 0.5) * w)[:, None]
    P = push_clear(P, margin=CLEAR + 0.006)
    az = np.arctan2(V[:, 0], V[:, 2]) % TAU
    UV = np.stack([(az / TAU * 6) % 1.0, np.clip(0.1 + 0.9 * (P[:, 1] - 0.2) / 0.85, 0, 1)], -1)
    occ = np.clip((0.4 + 0.6 * bump ** 0.55) * (0.72 + 0.28 * w) * tone, 0.25, 1)
    pc = Piece("HairAfro01", "clump", material="Fabric", castShadow=True, hideUnder=dict(HIDE))
    COL = np.stack([occ, occ, occ, np.ones_like(occ)], -1)
    emit(pc, P, F, UV, COL, np.broadcast_to(O, P.shape), flat=True)
    be = boundary_edges(F)
    if be:
        bv = sorted({v for e in be for v in e})
        idx = {v: i for i, v in enumerate(bv)}
        Nn = head_n(S[bv])
        low = push_clear(S[bv] + Nn * (CAP_H + 0.006), margin=CLEAR + 0.004)
        PP = np.concatenate([P[bv], low])
        nb = len(bv)
        TT = []
        for a_, b_ in be:
            i, j = idx[a_], idx[b_]
            TT += [(i, j, nb + j), (i, nb + j, nb + i)]
        UU = np.concatenate([UV[bv], np.stack([UV[bv][:, 0], np.full(nb, 0.05)], -1)])
        oc = np.concatenate([occ[bv] * 0.8, np.full(nb, 0.4)])
        CC = np.stack([oc, oc, oc, np.ones_like(oc)], -1)
        emit(pc, PP, np.array(TT), UU, CC, np.broadcast_to(O, PP.shape), flat=True)
    return [pc]


def hightop_v10_entry(seed=21):
    pieces = hightop_box(seed)
    return dict(styles=["High Top"], types=None, cap={"cut": "style", "density": 1}, family="stylised",
                capEarLine=True, style="stylised clumps (build_stylised.py)"), pieces


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
                tmax=top, knob=knob, kh=kh, tmin=0.03, level=5, micro=(0.5, 0.16))  # (v10: the curls within a knot)
    pieces = knob_volume(spec, seed)
    entry = dict(styles=styles, types=CURLY, cap={"cut": "style", "density": 1}, family="stylised",
                 capEarLine=True, style="stylised clumps (build_stylised.py)")
    entry.update(cap_extra or {})
    return entry, pieces


def afro_entry(key, types, top=0.27, side=0.16, front=0.13, back=0.2, knob=0.11, seed=9, kh=0.42):
    spec = dict(thick=afro_thick(top=top, side=side, front=front, back=back), tmax=top, knob=knob, kh=kh, tmin=0.03,
                level=5, name="HairAfro01", micro=(0.45, 0.16))  # (v10: the curls within a clump)
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
        "fade_low_c": lambda: fade_top_entry("fade_low_c", ["Low Fade"], "low", top=0.15, side=0.08, seed=4),
        "fade_mid_c": lambda: fade_top_entry("fade_mid_c", ["Fade", "Mid Fade"], "mid", top=0.15, side=0.07, seed=5),
        "fade_high_c": lambda: fade_top_entry("fade_high_c", ["High Fade"], "high", top=0.16, side=0.06, seed=6),
        "fade_burst_c": lambda: fade_top_entry("fade_burst_c", ["Burst Fade"], "burst", top=0.15, side=0.07,
                                               seed=7),
        "crew_c": lambda: fade_top_entry("crew_c", ["Crew Cut"], "none", top=0.1, front=0.08, side=0.05, back=0.05,
                                         knob=0.055, seed=8, cap_extra={"capFade": "fade"}),
        "caesar_c": lambda: fade_top_entry("caesar_c", ["Caesar Cut"], "none", top=0.07, front=0.06, side=0.045,
                                           back=0.045, knob=0.045, seed=10),
        # (v10) the 14 smoother styles in the same chunky clumped look
        "buzz": buzz_entry,
        "fade_low": lambda: comb_top_entry("fade_low", ["Low Fade"], "low", top=0.13, side=0.07, seed=41),
        "fade_mid": lambda: comb_top_entry("fade_mid", ["Fade", "Mid Fade"], "mid", top=0.13, side=0.06, seed=42),
        "fade_high": lambda: comb_top_entry("fade_high", ["High Fade"], "high", top=0.14, side=0.05, seed=43),
        "fade_taper": lambda: comb_top_entry("fade_taper", ["Taper Fade"], "taper", top=0.13, side=0.075, seed=44),
        "fade_burst": lambda: comb_top_entry("fade_burst", ["Burst Fade"], "burst", top=0.13, side=0.06, seed=45),
        "crew": lambda: comb_top_entry("crew", ["Crew Cut"], "none", top=0.08, front=0.07, side=0.035, back=0.035,
                                       knob=0.065, seed=46, cap_extra={"capFade": "fade"}, stretch=2.2, kh=0.5),
        "caesar": lambda: comb_top_entry("caesar", ["Caesar Cut"], "none", top=0.05, front=0.05, side=0.035,
                                         back=0.035, knob=0.05, seed=47, stretch=2.0, fwd=1.4, kh=0.4, ramp=0.06),
        "hightop": hightop_v10_entry,
        "dreadlocks": lambda: (dict(styles=["Dreadlocks"], types=None, cap={"cut": "full", "density": 0.45},
                                    capTile="shortcoil", capEarLine=True, family="stylised",
                                    style="segmented long locs (build_stylised.py)"), dreadlocks_entry()),
        "braids": lambda: (dict(styles=["Braids"], types=None, cap={"cut": "full", "density": 0.15}, family="stylised",
                                style="plaited rows into hanging plaits (build_stylised.py)"), braids_entry()),
        "box_braids": lambda: (dict(styles=["Box Braids"], types=None, cap={"cut": "full", "density": 0.15},
                                    family="stylised", style="faceted box braids (build_stylised.py)"),
                               box_braids_entry()),
        "long": lambda: (dict(styles=["Long Hair"], types=["Straight"], cap={"cut": "full", "density": 1},
                              family="stylised", style="chunky faceted locks (build_stylised.py)"), long_entry("long")),
        "long_wavy": lambda: (dict(styles=["Long Hair"], types=["Wavy"], cap={"cut": "full", "density": 1},
                                   family="stylised", style="chunky faceted wavy locks (build_stylised.py)"),
                              long_entry("long_wavy", wavy=True, seed=96)),
    }
    return E


OPT_IN = set()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--texture", action="store_true")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    if args.texture or not os.path.exists(TEX_PATH):
        print("texture", build_texture())
    E = entries()
    # (v10: every entry is built here, the high top too - hightop_v10_entry's flat-topped column)
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
