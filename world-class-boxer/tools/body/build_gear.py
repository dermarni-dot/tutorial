"""Boxing gear for the muscle-tier R15 body, in the same smooth stylised style as the tier parts (build_body.py):
trunks (waistband, seat, shorts legs, side stripe, hem trim), gloves (glove, cuff, strap), hand wraps, boots /
low-top shoes (foot, sole, laces, shaft, sock / collar) and the women's sports top, each FITTED to the tier body
part it is welded to.

Run with Blender's Python (Cycles CPU renders of the check sheets):
    /opt/bpyenv/bin/python tools/body/build_gear.py                  # build + export + check sheets
    /opt/bpyenv/bin/python tools/body/build_gear.py --no-render      # build + export only
    /opt/bpyenv/bin/python tools/body/build_gear.py --sheets 1,3 --samples 24

Outputs
    tools/body/out/gear/tier<N>/<Piece>.mesh   pieces fitted to one tier (Roblox mesh v2.00, vertices relative to
                                               the piece's bbox centre = the MeshPart origin)
    tools/body/out/gear/shared/<Piece>.mesh    pieces the same at every tier (hands and feet do not change)
    tools/body/out/gear/gear.json              per tier, per piece: the mesh file, the body part it welds to, its
                                               offset (the piece's centre in that part's space, rest pose, unscaled:
                                               the game welds it at part.CFrame * CFrame.new(offset * ratio)), its
                                               size (bbox = the MeshPart's unscaled Size), tris; per piece: colour
                                               slot, group; the sets (which pieces each trunk / shoe style wears)
    <scratch>/gear/*.png                       check sheets

Method (as the body): every piece lives in game rest space (studs, +Y up, -Z forward, feet on Y = 0), built from
the tier bodies of build_body.build_tier. Cloth is a loft of rings whose radius in every direction is the CONVEX HULL
of the body's cross-section there (cloth bridges hollows: the glutes' cleft, the gap between the thighs) plus an
offset (snug for the waistband, loose and flared for the satin legs). Where a piece reaches over a part whose tier
can differ (the waistband over the UpperTorso, the seat over both thighs, the cuff over the glove), the hull takes
the union of that part over ALL tiers, so it never clips whatever tier the neighbour shows. Every opening ends in a
rolled lip that turns inward (looking into a shorts leg or a cuff shows cloth, never a culled back face); every
end that dives into the body or under another piece closes on itself.
"""
import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "hair"))
sys.path.insert(0, HERE)
import hairlib as hl  # noqa: E402  (Piece, write_mesh_v2)
import build_body as bb  # noqa: E402  (tiers, loft, tube, posing, Stage)

OUT = os.path.join(HERE, "out", "gear")
SCRATCH = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/gear"
TIER_IDS = (1, 2, 3, 4, 5)

# ------------------------------------------------------------------------------------------ the gear's heights
# (game rest space, tier-independent: every tier shares the torso / leg joint pivots)
Y_BAND = (3.03, 3.37)       # waistband: from just below the waist seam to the navel line (high boxing trunks)
Y_SEAT = (2.46, 3.12)       # trunk seat: the bottom edge just under the crotch, the top hidden in the band
Y_LEG_TOP = 2.80            # shorts leg top (closed, inside the seat)
Y_HEM = {"short": 1.99, "long": 1.62}   # mid-thigh / just above the knee
Y_TOP = (4.12, 4.66)        # sports top: underband to the armpit line (the straps go on over the shoulders)

# pieces worn by the HIGHEST tier among several body parts (BuilderGear: the entry of that tier, its offset moved
# onto the part's own tier by the RootRigAttachment's - the LowerTorso's rest frame is the same at every tier)
TIER_OF = {"Waistband": ["LowerTorso", "UpperTorso", "LeftUpperLeg", "RightUpperLeg"],
           "TrunkSeat": ["LowerTorso", "UpperTorso", "LeftUpperLeg", "RightUpperLeg"]}

SLOTS = ["trunks", "trim", "gloves", "gloveTrim", "wraps", "wraps2", "shoes", "soles", "laces", "socks", "top",
         "topTrim"]

# piece name -> (body part base, colour slot, group, sided, shared over tiers)
PIECES = {
    "Waistband": ("LowerTorso", "trim", "trunks", False, False),
    "TrunkSeat": ("LowerTorso", "trunks", "trunks", False, False),
    "TrunkLeg": ("UpperLeg", "trunks", "trunks", True, False),
    "TrunkLegLong": ("UpperLeg", "trunks", "trunks", True, False),
    "TrunkStripe": ("UpperLeg", "trim", "trunks", True, False),
    "TrunkHem": ("UpperLeg", "trim", "trunks", True, False),
    "TrunkHemLong": ("UpperLeg", "trim", "trunks", True, False),
    "Glove": ("Hand", "gloves", "gloves", True, True),
    "GloveCuff": ("LowerArm", "gloves", "gloves", True, False),
    "GloveStrap": ("LowerArm", "gloveTrim", "gloves", True, False),
    "Wrap": ("Hand", "wraps", "wraps", True, True),
    "WrapWrist": ("LowerArm", "wraps2", "wraps", True, False),
    "BootFoot": ("Foot", "shoes", "shoes", True, True),
    "Sole": ("Foot", "soles", "shoes", True, True),
    "ShoeLaces": ("Foot", "laces", "shoes", True, True),
    "BootShaft": ("LowerLeg", "shoes", "shoes", True, False),
    "BootLaces": ("LowerLeg", "laces", "shoes", True, False),
    "BootSock": ("LowerLeg", "socks", "shoes", True, False),
    "ShoeCollar": ("LowerLeg", "shoes", "shoes", True, False),
    "AnkleSock": ("LowerLeg", "socks", "shoes", True, False),
    "Top": ("UpperTorso", "top", "top", False, False),
    "TopBand": ("UpperTorso", "topTrim", "top", False, False),
}

# what each look wears (piece names; sided pieces stand for both _L and _R)
SETS = {
    "trunks": {
        "Classic": ["Waistband", "TrunkSeat", "TrunkLeg"],
        "Striped": ["Waistband", "TrunkSeat", "TrunkLeg", "TrunkStripe"],
        "Pro": ["Waistband", "TrunkSeat", "TrunkLeg", "TrunkStripe", "TrunkHem"],
        "Long": ["Waistband", "TrunkSeat", "TrunkLegLong", "TrunkHemLong"],
    },
    "shoes": {
        "High-Top": ["BootFoot", "Sole", "ShoeLaces", "BootShaft", "BootLaces", "BootSock"],
        "Low-Top": ["BootFoot", "Sole", "ShoeLaces", "ShoeCollar", "AnkleSock"],
    },
    "gloves": {"Gloves": ["Glove", "GloveCuff", "GloveStrap"]},
    "wraps": {"Wraps": ["Wrap", "WrapWrist"]},
    "top": {"Top": ["Top", "TopBand"]},
}


# ------------------------------------------------------------------------------------------ sections
def sec_pts(lp, y):
    """(k, 2) [x, z] points where the mesh's edges cross height y"""
    P, T = lp["P"], lp["T"]
    out = []
    for a, b in ((0, 1), (1, 2), (2, 0)):
        pa, pb = P[T[:, a]], P[T[:, b]]
        m = (pa[:, 1] - y) * (pb[:, 1] - y) < 0
        if not m.any():
            continue
        t = (y - pa[m, 1]) / (pb[m, 1] - pa[m, 1])
        q = pa[m] + (pb[m] - pa[m]) * t[:, None]
        out.append(q[:, [0, 2]])
    return np.vstack(out) if out else np.zeros((0, 2))


def hull2(Q):
    """convex hull (counter-clockwise in x, z) by the monotone chain"""
    Q = np.unique(np.round(np.asarray(Q, float), 6), axis=0)
    if len(Q) < 3:
        return Q
    Q = Q[np.lexsort((Q[:, 1], Q[:, 0]))]

    def half(R):
        h = []
        for p in R:
            while len(h) >= 2 and ((h[-1][0] - h[-2][0]) * (p[1] - h[-2][1])
                                   - (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0])) <= 0:
                h.pop()
            h.append(tuple(p))
        return h
    return np.array(half(Q)[:-1] + half(Q[::-1])[:-1])


def dirs(phis):
    """phi = 0 points forward (-Z), +90 deg to +X (build_body's ring convention)"""
    return np.stack([np.sin(phis), -np.cos(phis)], axis=1)


def ray_hull(H, c, phis):
    """distance from c (inside H) to the hull's boundary along each direction"""
    D = dirs(phis)
    A = H - c
    E = np.roll(H, -1, axis=0) - H
    # c + t d = H_i + u E_i  ->  t = cross(A, E) / cross(d, E), u = cross(A, d) / cross(d, E)
    cr = lambda a, b: a[..., 0] * b[..., 1] - a[..., 1] * b[..., 0]  # noqa: E731
    den = cr(D[:, None, :], E[None, :, :])
    with np.errstate(divide="ignore", invalid="ignore"):
        t = cr(A[None, :, :], E[None, :, :]) / den
        u = cr(A[None, :, :], D[:, None, :]) / den
    ok = (np.abs(den) > 1e-12) & (u >= -1e-9) & (u <= 1 + 1e-9) & (t > 0)
    t = np.where(ok, t, np.inf)
    r = t.min(axis=1)
    r[~np.isfinite(r)] = 0.0
    return r


def rot_xz(Q, c, deg):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    q = Q - c
    return np.stack([q[:, 0] * ca - q[:, 1] * sa, q[:, 0] * sa + q[:, 1] * ca], axis=1) + c


def env_pts(sources, y):
    """union of section points of several sources at height y. A source = lp, or (lp, dict(ymin, ymax, yaw, c))"""
    pts = []
    for s in sources:
        lp, o = (s, {}) if isinstance(s, dict) and "P" in s else s
        if o.get("ymin") is not None and y < o["ymin"]:
            continue
        if o.get("ymax") is not None and y > o["ymax"]:
            continue
        Q = sec_pts(lp, y)
        if not len(Q):
            continue
        pts.append(Q)
        for yaw in o.get("yaw", ()):
            pts.append(rot_xz(Q, np.asarray(o.get("c", (0.0, 0.0))), yaw))
    return np.vstack(pts) if pts else np.zeros((0, 2))


def smooth_circ(r, sigma):
    """circular Gaussian smoothing of a radial function (sigma in samples)"""
    if sigma <= 0:
        return r
    n = len(r)
    k = np.arange(-int(3 * sigma) - 1, int(3 * sigma) + 2)
    w = np.exp(-0.5 * (k / sigma) ** 2)
    w /= w.sum()
    out = np.zeros_like(r)
    for kk, ww in zip(k, w):
        out += ww * np.roll(r, -kk)
    return out


def max_circ(r, k):
    out = r.copy()
    for kk in range(1, k + 1):
        out = np.maximum(out, np.maximum(np.roll(r, kk), np.roll(r, -kk)))
    return out


def radial(sources, y, c, phis, sigma=1.5, rmin=0.0, nfin=24):
    """the hull's radius from c in each direction, never inside the hull: a circular max filter before the
    smoothing (which would pull the corners in), and the chord sag of the final nfin-gon added back"""
    Q = env_pts(sources, y)
    if len(Q) < 3:
        return np.full(len(phis), rmin)
    H = hull2(Q)
    if len(H) < 3:
        return np.full(len(phis), rmin)
    r = ray_hull(H, np.asarray(c, float), phis)
    if sigma > 0:
        r = smooth_circ(max_circ(r, int(math.ceil(2 * sigma))), sigma)
    r = r / math.cos(math.pi / nfin)
    return np.maximum(r, rmin)


def centroid(sources, y):
    Q = env_pts(sources, y)
    if len(Q) < 3:
        return None
    H = hull2(Q)
    return H.mean(axis=0)


# ------------------------------------------------------------------------------------------ sheets
def sheet(G, pole_lo=None, pole_hi=None, nref=None):
    """a (R, n, 3) ring grid (wrapping in u) -> lp {P, N, U, T}: smooth vertex normals from the welded grid,
    oriented outward (away from each ring's centre, over the rings listed in nref, default all), a duplicated seam
    column for the UVs, optional pole points closing either end"""
    G = np.asarray(G, float)
    R, n = G.shape[:2]
    V = G.reshape(-1, 3)
    iv = lambda i, j: i * n + (j % n)  # noqa: E731
    T = []
    for i in range(R - 1):
        for j in range(n):
            a, b, c, d = iv(i, j), iv(i, j + 1), iv(i + 1, j + 1), iv(i + 1, j)
            T += [(a, b, c), (a, c, d)]
    extra = []
    if pole_lo is not None:
        p = R * n + len(extra)
        extra.append(pole_lo)
        T += [(p, iv(0, j + 1), iv(0, j)) for j in range(n)]
    if pole_hi is not None:
        p = R * n + len(extra)
        extra.append(pole_hi)
        T += [(p, iv(R - 1, j), iv(R - 1, j + 1)) for j in range(n)]
    if extra:
        V = np.vstack([V, np.array(extra, float)])
    T = np.array(T, np.int64)
    N = bb.vnormals(V, T)
    Ng = N[: R * n].reshape(R, n, 3)
    rows = range(R) if nref is None else nref
    s = 0.0
    for i in rows:
        cen = G[i].mean(axis=0)
        d = G[i] - cen
        d[:, 1] = 0
        s += float(np.einsum("ij,ij->", Ng[i], d))
    if s < 0:
        N = -N
        T = T[:, ::-1]
        Ng = N[: R * n].reshape(R, n, 3)
    # output with a duplicated seam column
    P = np.concatenate([G, G[:, :1]], axis=1).reshape(-1, 3)
    NN = np.concatenate([Ng, Ng[:, :1]], axis=1).reshape(-1, 3)
    uu = np.arange(n + 1) / n
    vv = np.linspace(0, 1, R)
    U = np.stack(np.meshgrid(uu, vv), axis=-1).reshape(-1, 2)
    m = n + 1
    jv = lambda i, j: i * m + j  # noqa: E731
    TT = []
    for i in range(R - 1):
        for j in range(n):
            a, b, c, d = jv(i, j), jv(i, j + 1), jv(i + 1, j + 1), jv(i + 1, j)
            TT += [(a, b, c), (a, c, d)]
    k = R * m
    eP, eN, eU = [], [], []
    if pole_lo is not None:
        eP.append(V[R * n]); eN.append(N[R * n]); eU.append((0.5, 0.0))
        TT += [(k, jv(0, j + 1), jv(0, j)) for j in range(n)]
        k += 1
    if pole_hi is not None:
        q = R * n + (1 if pole_lo is not None else 0)
        eP.append(V[q]); eN.append(N[q]); eU.append((0.5, 1.0))
        TT += [(k, jv(R - 1, j), jv(R - 1, j + 1)) for j in range(n)]
    if eP:
        P = np.vstack([P, eP]); NN = np.vstack([NN, eN]); U = np.vstack([U, eU])
    TT = np.array(TT, np.int64)
    g = np.cross(P[TT[:, 1]] - P[TT[:, 0]], P[TT[:, 2]] - P[TT[:, 0]])
    flip = np.einsum("ij,ij->i", g, NN[TT].sum(axis=1)) < 0
    TT[flip] = TT[flip][:, ::-1]
    return {"P": P, "N": NN, "U": U, "T": TT}


def ring(c, r, phis, y):
    D = dirs(phis)
    return np.stack([c[0] + r * D[:, 0], np.full(len(phis), y), c[1] + r * D[:, 1]], axis=1)


def inward(Rg, c):
    """horizontal unit vectors from each ring point toward the axis point c (x, z)"""
    d = np.stack([c[0] - Rg[:, 0], np.zeros(len(Rg)), c[1] - Rg[:, 2]], axis=1)
    return d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)


def lip(edge, c, along, t, back=1.6):
    """the rolled lip after an opening's edge ring: round over (along = the direction past the edge, e.g. -Y at a
    hem) and back inside the cloth by `back` x t -> 3 rings"""
    w = inward(edge, c)
    a = np.asarray(along, float)
    r1 = edge + a * t * 0.55 + w * t * 0.6
    r2 = edge - a * t * back + w * t * 1.05
    return [r1, r2]


def tuck(edge, c, along, t, k=0.75):
    """a closed end diving under: one ring a little past the edge pulled in, then the pole"""
    w = inward(edge, c)
    a = np.asarray(along, float)
    r1 = edge + a * t + w * t * 1.2
    ctr = np.array([c[0], float(np.mean(edge[:, 1])) + a[1] * t * 1.6, c[1]])
    r2 = ctr + (r1 - ctr) * k
    r2[:, 1] = r1[:, 1] + a[1] * t * 0.6
    return [r1, r2], ctr + a * t * 0.6


def merge(lps):
    return bb.merge_lp(lps)


def mirror(lp):
    return bb.mirror_lp(lp)


def offset_lp(lp, d):
    out = dict(lp)
    out["P"] = lp["P"] + lp["N"] * d
    return out


def ntris(lp):
    return int(len(lp["T"]))


# ------------------------------------------------------------------------------------------ the bodies
class Bodies:
    def __init__(self):
        self.t = {n: bb.build_tier(None, n) for n in TIER_IDS}

    def part(self, n, name):
        return self.t[n][name]

    def all_tiers(self, name, **o):
        return [(self.t[n][name], dict(o)) for n in TIER_IDS]

    def J(self, n, k):
        return np.array(self.t[n]["_J"][k], float)

    def centre(self, n, name):
        P = self.t[n][name]["P"]
        return (P.min(0) + P.max(0)) / 2


# ------------------------------------------------------------------------------------------ trunks
NSEG_DENSE = 96


def band_and_seat(B, n):
    """the waistband and the seat on the LowerTorso of tier n"""
    phis = 2 * math.pi * (np.arange(NSEG_DENSE) / NSEG_DENSE - 0.5)
    lt = B.part(n, "LowerTorso")
    c = np.array([0.0, float((lt["P"][:, 2].min() + lt["P"][:, 2].max()) / 2)])
    # (v9) the band and the seat of tier n are worn when the HIGHEST tier among the LowerTorso, the UpperTorso and
    # both thighs is n (BuilderGear: the piece's tierOf), so they hull those parts of tier n and every tier under it -
    # never a tier-5 thigh round a tier-1 boxer's hips (v8 hulled all five: the trunks hung loose on every body)
    lower = [k for k in TIER_IDS if k <= n]
    # (the chest turns over the hips in a punch: v9_anim.luau measures the waist up to 32 deg of twist, 12 of side bend
    # and 13 forward; the UpperTorso's hem under the band is hulled through that, about the waist pivot)
    wj = B.J(n, "Waist")
    ut_all = []
    for k in lower:
        ut = B.part(k, "UpperTorso")
        ut_all.append((ut, dict(ymin=3.05, yaw=(-12, 12), c=(0.0, 0.0))))
        for yw, rl, pt in WAIST_TURNS:
            R = bb.roty(yw) @ bb.rotz(rl) @ bb.rotx(pt)
            ut_all.append(({"P": (ut["P"] - wj) @ R.T + wj, "T": ut["T"]}, dict(ymin=3.05)))
    legs_all = [(B.part(k, s + "UpperLeg"), {}) for k in lower for s in ("Right", "Left")]
    # (and the thighs of tier n swung through the walk, the seat cut round them: walking never pushes a thigh - or the
    # shorts leg over it - out through the seat's lower edge)
    for s in ("Right", "Left"):
        ul = B.part(n, s + "UpperLeg")
        hip = B.J(n, s + "Hip")
        for deg in SEAT_SWING:
            legs_all.append(({"P": swung(ul["P"], hip, deg) + np.array([0, 0, 0]), "T": ul["T"]}, dict(ymin=Y_SEAT[0] - 0.05)))
    srcs = [lt] + ut_all + legs_all
    s0, s1 = Y_SEAT

    def seat_off(y):
        # snug where the band covers it, loose satin toward the bottom
        tt = np.clip((Y_BAND[0] + 0.02 - y) / (Y_BAND[0] + 0.02 - s0), 0, 1)
        return 0.012 + 0.016 * tt ** 1.1
    # ---- the waistband: snug elastic, a little rounded out in the middle
    y0, y1 = Y_BAND
    ys = np.linspace(y0, y1, 4)
    rings = []
    for i, y in enumerate(ys):
        tt = i / (len(ys) - 1)
        r = radial(srcs, y, c, phis, sigma=2.5)
        rings.append(ring(c, r + 0.030 + 0.008 * math.sin(math.pi * tt), phis, y))
    top = lip(rings[-1], c, (0, 1, 0), 0.035)
    bot = lip(rings[0], c, (0, -1, 0), 0.03)
    G = bot[::-1] + rings + top
    band = sheet(np.array(G)[:, ::4], nref=range(len(bot), len(bot) + len(rings)))
    # ---- the seat: from inside the band down to under the crotch, looser toward the bottom
    ys = [s1, y0, 2.92, 2.72, 2.56, s0]
    rings = []
    for y in ys:
        r = radial(srcs, y, c, phis, sigma=3.0) + seat_off(y)
        if y >= y0 - 0.001:
            # (inside the band, clear of its rolled-in bottom lip: the seat never shows through the elastic)
            r = np.minimum(r, radial(srcs, y, c, phis, sigma=2.5) + 0.030 - 0.032)
        rings.append(ring(c, r, phis, y))
    # under the crotch: a short roll inward, then a flat close (between the legs, under the leg tubes)
    e = rings[-1]
    w = inward(e, c)
    r1 = e + np.array([0, -0.018, 0]) + w * 0.022
    r2 = e + np.array([0, -0.035, 0]) + w * 0.16
    ctr = np.array([c[0], s0 - 0.035, c[1]])
    G = rings + [r1, r2]
    seat = sheet(np.array(G)[:, ::4], pole_hi=ctr, nref=range(len(rings)))
    seat_fn = (lambda y, ph, _c=c: radial(srcs, y, _c, ph, sigma=3.0) + seat_off(y))
    return band, seat, c, seat_fn


class SeatField:
    """the seat's radius (min over every LowerTorso tier) on a (y, phi) grid, for fast inside tests"""

    def __init__(self, fns, c):
        self.c = np.asarray(c, float)
        self.ys = np.arange(Y_SEAT[0], Y_SEAT[1] + 0.001, 0.01)
        self.ph = 2 * math.pi * (np.arange(NSEG_DENSE) / NSEG_DENSE - 0.5)
        self.R = np.array([np.min([f(y, self.ph) for f in fns], axis=0) for y in self.ys])

    def radius(self, y, ang):
        yi = np.clip((np.asarray(y) - self.ys[0]) / 0.01, 0, len(self.ys) - 1.001)
        i0 = np.floor(yi).astype(int)
        fy = yi - i0
        a = (np.asarray(ang) + math.pi) / (2 * math.pi) * NSEG_DENSE
        j0 = np.floor(a).astype(int) % NSEG_DENSE
        j1 = (j0 + 1) % NSEG_DENSE
        fa = a - np.floor(a)
        r0 = self.R[i0, j0] * (1 - fa) + self.R[i0, j1] * fa
        r1 = self.R[i0 + 1, j0] * (1 - fa) + self.R[i0 + 1, j1] * fa
        return r0 * (1 - fy) + r1 * fy

    def inside(self, P, clr):
        d = P[:, [0, 2]] - self.c
        ang = np.arctan2(d[:, 0], -d[:, 1])
        dist = np.linalg.norm(d, axis=1)
        above = P[:, 1] >= Y_SEAT[0]
        return ~above | (dist <= self.radius(P[:, 1], ang) - clr)


# the waist turns (yaw, side bend, forward bend; deg) the band is cut round
WAIST_TURNS = ((22, 0, 0), (-22, 0, 0), (16, 8, 5), (-16, -8, 5), (0, 9, 0), (0, -9, 0), (0, 0, 10), (0, 0, -5))
# the thigh swings the seat is cut round (its hull): the walk's
SEAT_SWING = (-14, 16)
# thigh pitch (deg, + = knee forward) the leg top must stay hidden through: the town walk's -23..+33 (v9_anim.luau
# measures it) and the stance / punches; a jog's and a run's high knee goes further and creases the seat
HIP_SWING = (-28, -18, -9, 0, 9, 18, 27, 36)


def swung(P, hip, deg):
    R = bb.rotx(deg)
    return (P - hip) @ R.T + hip


def trunk_leg(B, n, length, field):
    """one shorts leg (right side) on the UpperLeg of tier n: loose satin, flared, ending at the hem with a rolled
    lip; the top closed inside the seat. Returns (leg, hem trim, side stripe) lps"""
    phis = 2 * math.pi * (np.arange(NSEG_DENSE) / NSEG_DENSE - 0.5)
    ul = B.part(n, "RightUpperLeg")
    hip = B.J(n, "RightHip")
    yh = Y_HEM[length]
    ys = [Y_LEG_TOP, 2.47, 2.40] + list(np.linspace(2.31, yh, 3 if length == "short" else 5))
    rings, cs = [], []
    for y in ys:
        cc = centroid([ul], min(y, 2.75))
        cc = np.array([hip[0], 0.0]) if cc is None else cc
        cs.append(cc)
    cs = np.array(cs)
    # smooth the axis along the leg
    for _ in range(2):
        cs[1:-1] = 0.25 * cs[:-2] + 0.5 * cs[1:-1] + 0.25 * cs[2:]
    side = np.sin(phis)  # +1 outer (+X), -1 inner
    for i, y in enumerate(ys):
        c = cs[i]
        r = radial([ul], min(y, 2.75), c, phis, nfin=16, sigma=3.0)
        tt = np.clip((2.50 - y) / (2.50 - yh), 0, 1)  # 0 at the crotch line .. 1 at the hem
        # (v9: fitted - a little ease over the thigh, the outer side a touch fuller toward the hem, the leg opening
        # close to the thigh; v8's 0.05-0.11 hung like a skirt)
        off = 0.026 + 0.022 * tt ** 1.2 + 0.012 * np.maximum(side, 0) * (0.5 + tt) - 0.012 * np.maximum(-side, 0)
        rr = r + off
        Rg = ring(c, rr, phis, y)
        # under the seat the leg stays inside it (every LowerTorso tier) through the thigh's swing in the stance
        # and the punches (HIP_SWING about the hip joint); just under the seat's edge it flares out toward the edge
        # wherever the seat runs close (outer side, front, back), so the seat ends in a seam, not an overhang
        ys_ = Y_SEAT[0]
        d = Rg[:, [0, 2]] - c
        if y > ys_ - 0.16:
            ds = Rg[:, [0, 2]] - field.c
            ang = np.arctan2(ds[:, 0], -ds[:, 1])
            lim = field.radius(max(y, ys_), ang)
            dist = np.linalg.norm(ds, axis=1)
            if y <= ys_ - 0.01:
                w = np.clip(1 - (ys_ - y) / 0.16, 0, 1) ** 1.5
                gap = lim - dist
                # (v9: front and back too - only the inner side, between the legs, keeps its line)
                near = np.clip(1 - (gap - 0.02) / 0.18, 0, 1) * np.clip(1.0 + side * 1.4, 0, 1)
                want = np.maximum(dist, dist + (lim - 0.018 - dist) * w * near)
                kk = want / np.maximum(dist, 1e-9)
                Rg[:, 0] = field.c[0] + ds[:, 0] * kk
                Rg[:, 2] = field.c[1] + ds[:, 1] * kk
                d = Rg[:, [0, 2]] - c
        if y > ys_ - 0.16:
            # shrink each point toward the leg's axis until it is inside the seat at every swing (a point the swing
            # keeps under the seat's edge is free)
            kbest = np.ones(len(Rg))
            done = np.zeros(len(Rg), bool)
            for kk in np.arange(1.0, 0.39, -0.02):
                Q = Rg.copy()
                Q[:, 0] = c[0] + d[:, 0] * kk
                Q[:, 2] = c[1] + d[:, 1] * kk
                ok = np.ones(len(Rg), bool)
                for deg in HIP_SWING:
                    ok &= field.inside(swung(Q, hip, deg), 0.012 if y > ys_ - 0.01 else 0.0)
                new = ok & ~done
                kbest[new] = kk
                done |= ok
                if done.all():
                    break
            kbest[~done] = 0.4
            # (never inside the thigh itself: under the seat's edge the leg stays over the skin it covers - a seat
            # creased by a high knee is better than skin between the seat and the leg)
            kfloor = (r + 0.008) / np.maximum(np.linalg.norm(d, axis=1), 1e-9)
            kbest = np.minimum(1.0, np.maximum(kbest, kfloor))
            Rg[:, 0] = c[0] + d[:, 0] * kbest
            Rg[:, 2] = c[1] + d[:, 1] * kbest
        rings.append(Rg)
    rest = rings
    hem_lip = lip(rings[-1], cs[-1], (0, -1, 0), 0.035)
    topc, pole = tuck(rings[0][::-1][::-1], cs[0], (0, 1, 0), 0.03)
    G = topc[::-1] + rings + hem_lip
    Gd = np.array(G)
    # (the top closes on a pole above the tuck rings, hidden in the seat / thigh)
    leg = sheet(Gd[:, ::6], pole_lo=pole, nref=range(2, 2 + len(rings)))
    # ---- the hem trim: the last ~0.08 of the leg plus its lip, 0.008 out
    L = sheet(Gd, nref=range(2, 2 + len(rings)))
    Nd = L["N"].reshape(len(G), NSEG_DENSE + 1, 3)[:, :NSEG_DENSE]
    ih = len(topc) + len(rings) - 1  # the hem ring
    # rows: a ring 0.08 above the hem (interpolated on the leg), the hem ring, the lip rings
    yb = yh + 0.085
    j = max(i for i, y in enumerate(ys) if y >= yb)
    t = (ys[j] - yb) / (ys[j] - ys[j + 1])
    a = len(topc) + j
    up = Gd[a] * (1 - t) + Gd[a + 1] * t
    nu = Nd[a] * (1 - t) + Nd[a + 1] * t
    hrows = [up + nu * 0.009] + [Gd[k] + Nd[k] * 0.009 for k in range(ih, len(G))]
    top_tuck = up + nu * 0.009 + np.array([0, 0.012, 0]) - nu * 0.012
    hem = sheet(np.array([top_tuck] + hrows)[:, ::6], nref=[1, 2])
    # ---- the side stripe: the outer side (phi 90 +- 8 deg), hem to under the seat edge
    cols = np.where(np.abs(phis - math.pi / 2) <= math.radians(8.5))[0]
    rows = [k for k in range(len(topc), ih + 1) if Gd[k][0, 1] <= Y_SEAT[0] + 0.06]
    S = np.array([Gd[k][cols] + Nd[k][cols] * 0.007 for k in rows])
    stripe = strip_patch(S, [Nd[k][cols] for k in rows])
    return leg, hem, stripe


def strip_patch(S, Ns):
    """an open grid patch (rows x cols) -> lp, normals from the given cloth normals, with its two long edges folded
    down onto the cloth (a thin tape, not a floating card)"""
    S = np.asarray(S, float)
    Ns = np.asarray(Ns, float)
    R, C = S.shape[:2]
    # fold the outer columns 0.006 back toward the cloth
    S2 = np.concatenate([S[:, :1] - Ns[:, :1] * 0.006, S, S[:, -1:] - Ns[:, -1:] * 0.006], axis=1)
    N2 = np.concatenate([Ns[:, :1], Ns, Ns[:, -1:]], axis=1)
    C2 = C + 2
    P = S2.reshape(-1, 3)
    N = N2.reshape(-1, 3)
    U = np.stack(np.meshgrid(np.linspace(0, 1, C2), np.linspace(0, 1, R)), axis=-1).reshape(-1, 2)
    T = []
    for i in range(R - 1):
        for j in range(C2 - 1):
            a, b, c, d = i * C2 + j, i * C2 + j + 1, (i + 1) * C2 + j + 1, (i + 1) * C2 + j
            T += [(a, b, c), (a, c, d)]
    T = np.array(T, np.int64)
    g = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    flip = np.einsum("ij,ij->i", g, N[T].sum(axis=1)) < 0
    T[flip] = T[flip][:, ::-1]
    return {"P": P, "N": N / np.linalg.norm(N, axis=1, keepdims=True), "U": U, "T": T}


# ------------------------------------------------------------------------------------------ gloves / wraps
def glove(B):
    """the right glove on the tier-3 hand (rest pose: hanging, palm toward the body = -X, thumb forward = -Z):
    a padded fist ~1.5 x the hand's knuckle span, its striking face the end dome, the curled fingers bulging to the
    palm side, the thumb a sewn-on roll on the front / palm corner, the wrist rising into the cuff"""
    X = B.J(3, "RightWrist")[0]
    zc = -0.045
    s = [2.44, 2.56, 2.72, 2.88, 3.00, 3.10, 3.20]
    pr = bb.Prof(s,
                 ax=[0.235, 0.29, 0.30, 0.262, 0.21, 0.192, 0.19],
                 af=[0.31, 0.39, 0.41, 0.345, 0.262, 0.238, 0.235],
                 ab=[0.29, 0.37, 0.39, 0.33, 0.252, 0.228, 0.225],
                 p=[2.4, 2.55, 2.6, 2.5, 2.25, 2.05, 2.0],
                 cx=[-0.035, -0.04, -0.035, -0.02, -0.005, 0.0, 0.0],
                 cz=[zc + 0.005, zc, zc, zc, zc + 0.01, zc + 0.02, zc + 0.02])
    body = bb.loft(pr, 0.0, s[0], s[-1], (0.13, 1.0, 3), (0.06, 1.0, 2), nb=7, nseg=16, frame=bb.VERT(X), sub=2)
    pts = [(X - 0.10, 3.00, zc - 0.17), (X - 0.175, 2.87, zc - 0.29), (X - 0.19, 2.72, zc - 0.315),
           (X - 0.135, 2.60, zc - 0.27)]
    thumb = bb.tube(pts, [0.095, 0.115, 0.11, 0.088], nside=8, kcap=2)
    return merge([body, thumb]), X


def glove_section_sources(gl, X3, Xt):
    lp = dict(gl)
    lp["P"] = gl["P"] + np.array([Xt - X3, 0, 0])
    return lp


def cuff_and_strap(B, n, gl, X3):
    phis = 2 * math.pi * (np.arange(NSEG_DENSE) / NSEG_DENSE - 0.5)
    la = B.part(n, "RightLowerArm")
    Xt = B.J(n, "RightWrist")[0]
    g = glove_section_sources(gl, X3, Xt)
    c = np.array([Xt, -0.02])
    ys = [2.99, 3.13, 3.34, 3.54]
    rings = []
    rads = []
    for i, y in enumerate(ys):
        r_arm = radial([la], y, c, phis, nfin=16, sigma=3.0) + 0.045
        r_gl = radial([g], y, c, phis, nfin=16, sigma=3.0) + 0.016 if y <= 3.22 else 0 * phis
        r = np.maximum(r_arm, r_gl)
        r = np.maximum(r, smooth_circ(r, 6))  # rounder: padded leather
        r = r + 0.022 * max(0.0, (y - 3.3) / 0.24) ** 2  # the opening flares a little
        rads.append(r)
        rings.append(ring(c, r, phis, y))
    top = lip(rings[-1], c, (0, 1, 0), 0.04)
    bot, pole = tuck(rings[0], c, (0, -1, 0), 0.03, k=0.8)
    G = bot[::-1] + rings + top
    cuff = sheet(np.array(G)[:, ::6], pole_lo=pole, nref=range(2, 2 + len(rings)))
    # the strap: a hook-and-loop band round the cuff, y 3.17 .. 3.37, 0.014 proud, rounded edges
    sy = np.linspace(3.17, 3.37, 2)
    srings = []
    for y in sy:
        r = np.array([np.interp(y, ys, [rr[k] for rr in rads]) for k in range(len(phis))])
        srings.append(ring(c, r + 0.016, phis, y))
    G = lip(srings[0], c, (0, -1, 0), 0.016, back=0.4)[::-1] + srings + lip(srings[-1], c, (0, 1, 0), 0.016, back=0.4)
    strap = sheet(np.array(G)[:, ::6], nref=range(2, 2 + len(srings)))
    return cuff, strap


def wrap_hand(B):
    """the hand wrap on the tier-3 hand: palm, back and knuckles, the fingers free"""
    phis = 2 * math.pi * (np.arange(NSEG_DENSE) / NSEG_DENSE - 0.5)
    hd = B.part(3, "RightHand")
    ys = [3.15, 3.06, 2.97, 2.89, 2.82, 2.765]
    rings, cs = [], []
    for y in ys:
        cc = centroid([hd], y)
        cs.append(cc)
    cs = np.array(cs)
    cs[1:-1] = 0.25 * cs[:-2] + 0.5 * cs[1:-1] + 0.25 * cs[2:]
    for i, y in enumerate(ys):
        r = radial([hd], y, cs[i], phis, nfin=16, sigma=2.0) + 0.022
        rings.append(ring(cs[i], r, phis, y))
    G = tuck(rings[0], cs[0], (0, 1, 0), 0.02)[0][::-1] + rings + lip(rings[-1], cs[-1], (0, -1, 0), 0.025)
    _, pole = tuck(rings[0], cs[0], (0, 1, 0), 0.02)
    return sheet(np.array(G)[:, ::6], pole_lo=pole, nref=range(2, 2 + len(rings)))


def wrap_wrist(B, n, wrap, X3):
    phis = 2 * math.pi * (np.arange(NSEG_DENSE) / NSEG_DENSE - 0.5)
    la = B.part(n, "RightLowerArm")
    Xt = B.J(n, "RightWrist")[0]
    w = glove_section_sources(wrap, X3, Xt)
    hd = B.part(n, "RightHand")
    c = np.array([Xt, 0.0])
    ys = np.linspace(3.0, 3.44, 7)
    rings = []
    for i, y in enumerate(ys):
        r = radial([la], y, c, phis, nfin=16, sigma=2.5) + 0.024
        if y <= 3.17:
            r = np.maximum(r, radial([w, hd], y, c, phis, nfin=16, sigma=2.5) + 0.012)
        r = r + 0.008 * (i % 2)  # the layers of the wrap
        rings.append(ring(c, r, phis, y))
    bot, pole = tuck(rings[0], c, (0, -1, 0), 0.02)
    G = bot[::-1] + rings + lip(rings[-1], c, (0, 1, 0), 0.022)
    return sheet(np.array(G)[:, ::6], pole_lo=pole, nref=range(2, 2 + len(rings)))


# ------------------------------------------------------------------------------------------ boots
def boot_foot(B):
    """the boot's foot: the tier foot (the same at every tier) inflated 0.034 along its normals, the sole flat"""
    ft = B.part(3, "RightFoot")
    lp = offset_lp(ft, 0.034)
    P = lp["P"].copy()
    P[:, 1] = np.maximum(P[:, 1], 0.004)
    lp["P"] = P
    return lp


def sole(B):
    ft = B.part(3, "RightFoot")
    nseg = 32
    phis = 2 * math.pi * (np.arange(nseg * 3) / (nseg * 3) - 0.5)
    c = centroid([ft], 0.07)
    r = radial([ft], 0.07, c, phis, sigma=2.0) + 0.05
    hs = [(-0.014, -0.028), (0.004, 0.0), (0.072, -0.004), (0.088, -0.05)]
    rings = [ring(c, r + dr, phis, h) for h, dr in hs]
    ctr_lo = np.array([c[0], -0.014, c[1]])
    ctr_hi = np.array([c[0], 0.088, c[1]])
    return sheet(np.array(rings)[:, ::4], pole_lo=ctr_lo, pole_hi=ctr_hi, nref=[1, 2])


def raycast_lp(lp, o, d):
    return bb.raycast(lp, o, d)


def lace_bars(surf, points, normals_dir, width, r=0.02):
    """criss-cross laces: for each (left, right) pair of rows, two bars crossing; points lie on the surface"""
    out = []
    for a, b in points:
        out.append(bb.tube([a, b], [r, r], nside=4, kcap=1))
    return merge(out)


def surf_hit(lp, o, d, lift):
    o = np.asarray(o, float)
    d = np.asarray(d, float) / np.linalg.norm(d)
    t = raycast_lp(lp, o - d * 2, d)
    if t is None:
        return None
    return o - d * 2 + d * t - d * lift


def shoe_laces(B, foot_lp):
    """three crossed lace pairs over the instep of the boot foot"""
    X = B.J(3, "RightAnkle")[0]
    zs = [-0.06, -0.15, -0.24, -0.33]
    rows = []
    for z in zs:
        L = surf_hit(foot_lp, (X - 0.075, 1.0, z), (0, -1, 0), 0.012)
        R = surf_hit(foot_lp, (X + 0.075, 1.0, z), (0, -1, 0), 0.012)
        rows.append((L, R))
    pairs = []
    for i in range(len(rows) - 1):
        pairs.append((rows[i][0], rows[i + 1][1]))
        pairs.append((rows[i][1], rows[i + 1][0]))
    return lace_bars(foot_lp, pairs, None, 0.0, r=0.018)


def shaft_parts(B, n, foot_lp):
    phis = 2 * math.pi * (np.arange(NSEG_DENSE) / NSEG_DENSE - 0.5)
    ll = B.part(n, "RightLowerLeg")
    ax = B.J(n, "RightAnkle")
    c = np.array([ax[0], 0.012])
    out = {}

    def rad(y, off, foot_off=None):
        r = radial([ll], y, c, phis, nfin=16, sigma=3.0) + off
        if foot_off is not None and y < 0.5:
            rf = radial([foot_lp], y, c, phis, nfin=16, sigma=3.0)
            r = np.maximum(r, np.where(rf > 0, rf + foot_off, 0))
        return r
    # ---- the boot shaft (high-top): ankle to mid-calf
    ys = [0.27, 0.40, 0.55, 0.70, 0.87]
    rads = [np.maximum(rad(y, 0.040), smooth_circ(rad(y, 0.040), 5)) for y in ys]
    rings = [ring(c, r, phis, y) for r, y in zip(rads, ys)]
    bot, pole = tuck(rings[0], c, (0, -1, 0), 0.03, k=0.85)
    G = bot[::-1] + rings + lip(rings[-1], c, (0, 1, 0), 0.035)
    shaft = sheet(np.array(G)[:, ::6], pole_lo=pole, nref=range(2, 2 + len(rings)))
    out["BootShaft"] = shaft
    # laces on its front: 4 crossings from y 0.38 to 0.80
    ly = [0.38, 0.52, 0.66, 0.80]
    rows = []
    for y in ly:
        L = surf_hit(shaft, (c[0] - 0.07, y, -2.0), (0, 0, 1), 0.012)
        R = surf_hit(shaft, (c[0] + 0.07, y, -2.0), (0, 0, 1), 0.012)
        rows.append((L, R))
    pairs = []
    for i in range(len(rows) - 1):
        pairs.append((rows[i][0], rows[i + 1][1]))
        pairs.append((rows[i][1], rows[i + 1][0]))
    out["BootLaces"] = lace_bars(shaft, pairs, None, 0.0, r=0.017)
    # ---- the sock showing above the shaft
    ys2 = [0.845, 0.95]
    rr = [rad(y, 0.016) for y in ys2]
    rings = [ring(c, r, phis, y) for r, y in zip(rr, ys2)]
    bot, pole = tuck(rings[0], c, (0, -1, 0), 0.015)
    G = bot[::-1] + rings + lip(rings[-1], c, (0, 1, 0), 0.016)
    out["BootSock"] = sheet(np.array(G)[:, ::6], pole_lo=pole, nref=range(2, 2 + len(rings)))
    # ---- the low-top: a padded collar round the ankle, an ankle sock above it
    ys3 = [0.31, 0.35, 0.39, 0.43]
    rr = [rad(y, 0.036 + 0.016 * math.sin(math.pi * i / 3)) for i, y in enumerate(ys3)]
    rings = [ring(c, r, phis, y) for r, y in zip(rr, ys3)]
    bot, pole = tuck(rings[0], c, (0, -1, 0), 0.02)
    G = bot[::-1] + rings + lip(rings[-1], c, (0, 1, 0), 0.025)
    out["ShoeCollar"] = sheet(np.array(G)[:, ::6], pole_lo=pole, nref=range(2, 2 + len(rings)))
    ys4 = [0.30, 0.40, 0.50, 0.57]
    rr = [rad(y, 0.014) for y in ys4]
    rings = [ring(c, r, phis, y) for r, y in zip(rr, ys4)]
    bot, pole = tuck(rings[0], c, (0, -1, 0), 0.015)
    G = bot[::-1] + rings + lip(rings[-1], c, (0, 1, 0), 0.014)
    out["AnkleSock"] = sheet(np.array(G)[:, ::6], pole_lo=pole, nref=range(2, 2 + len(rings)))
    return out


# ------------------------------------------------------------------------------------------ sports top
def sports_top(B, n):
    """the women's sports top on the UpperTorso of tier n: a crop top from the underband to the armpit line with
    a scooped front, a little fullness over the chest, racer straps over the shoulders. Returns (top, band)"""
    nseg = 20
    k = 3
    phis = 2 * math.pi * (np.arange(nseg * k) / (nseg * k) - 0.5)
    ut = B.part(n, "UpperTorso")
    c = np.array([0.0, float((ut["P"][:, 2].min() + ut["P"][:, 2].max()) / 2)])
    y0 = Y_TOP[0]
    # the top edge per direction: scooped at the front centre, high at the back, under the arms at the sides
    front = np.cos(phis)  # 1 front, -1 back
    ytop = Y_TOP[1] - 0.10 * np.clip(front, 0, 1) ** 3 + 0.12 * np.clip(-front, 0, 1) ** 1.5
    nr = 5
    rows = []
    for i in range(nr):
        t = i / (nr - 1)
        Y = y0 + (ytop - y0) * t
        Rg = np.zeros((len(phis), 3))
        for j, (ph, y) in enumerate(zip(phis, Y)):
            r = radial([ut], y, c, np.array([ph - 0.06, ph, ph + 0.06]), sigma=0, nfin=nseg)[1]
            Rg[j] = ring(c, np.array([r]), np.array([ph]), y)[0]
        # smooth the ring
        d = Rg[:, [0, 2]] - c
        rr = smooth_circ(np.linalg.norm(d, axis=1), 2.0)
        # fullness over the chest: two soft bells at the pecs
        ex = np.zeros(len(phis))
        for sx in (-1, 1):
            px = np.array([sx * 0.30, 4.43])
            dx = (Rg[:, 0] - px[0]) / 0.26
            dy = (Rg[:, 1] - px[1]) / 0.24
            w = np.clip(1 - dx * dx - dy * dy, 0, 1)
            ex += 0.032 * w * w * (3 - 2 * w) * np.clip(front, 0, 1)
        D = dirs(phis)
        rr = rr + 0.024 + ex
        Rg[:, 0] = c[0] + rr * D[:, 0]
        Rg[:, 2] = c[1] + rr * D[:, 1]
        rows.append(Rg)
    bot = lip(rows[0], c, (0, -1, 0), 0.025)
    topl = lip(rows[-1], c, (0, 1, 0), 0.025)
    G = bot[::-1] + rows + topl
    body = sheet(np.array(G)[:, ::k], nref=range(2, 2 + nr))
    # straps: from the front top edge over the trapezius to the back top edge, on the torso surface
    straps = []
    for sx in (-1, 1):
        path = []
        for t in np.linspace(0, 1, 13):
            # from inside the torso, rays sweeping front (a = 0) -> straight up -> back (a = pi), each hitting the
            # outer surface; x moves from above the pec over the trapezius to the racer back
            a = math.pi * t
            x = sx * (0.25 + 0.10 * math.sin(a) - 0.09 * t)
            o = np.array([x, 4.50, c[1]])
            dvec = np.array([0.0, math.sin(a), -math.cos(a)])
            h = surf_hit(ut, o, -dvec, 0.024)
            if h is not None:
                path.append(h)
        path = np.array(path)
        straps.append(ribbon(path, ut, 0.10))
    top = merge([body] + straps)
    # the underband trim: the bottom 0.09 of the top plus its lip, 0.008 out
    L = sheet(np.array(G), nref=range(2, 2 + nr))
    Nd = L["N"].reshape(len(G), len(phis) + 1, 3)[:, :len(phis)]
    Gd = np.array(G)
    t = 0.09 / float(np.mean(ytop - y0)) * (nr - 1)
    i0 = int(math.floor(t))
    f = t - i0
    up = Gd[2 + i0] * (1 - f) + Gd[2 + i0 + 1] * f
    nu = Nd[2 + i0] * (1 - f) + Nd[2 + i0 + 1] * f
    rowsb = [Gd[k2] + Nd[k2] * 0.009 for k2 in (0, 1, 2)]  # the lip rings, the bottom edge
    tuck_r = up + nu * 0.009 - nu * 0.012 + np.array([0, 0.012, 0])
    band = sheet(np.array(rowsb + [up + nu * 0.009, tuck_r])[:, ::k], nref=[2, 3])
    return top, band


def ribbon(path, lp, w):
    """a flat strap along a surface path (points already lifted off the surface), normals from the torso"""
    n = len(path)
    T_ = np.gradient(path, axis=0)
    T_ /= np.linalg.norm(T_, axis=1, keepdims=True)
    # surface normal ~ away from the torso's vertical axis and up over the shoulder
    cen = np.array([0.0, 4.4, 0.0])
    Nn = path - cen
    Nn /= np.linalg.norm(Nn, axis=1, keepdims=True)
    Nn = Nn - T_ * np.einsum("ij,ij->i", Nn, T_)[:, None]
    Nn /= np.linalg.norm(Nn, axis=1, keepdims=True)
    S = np.cross(T_, Nn)
    S /= np.linalg.norm(S, axis=1, keepdims=True)
    rows = [path - S * (w / 2) - Nn * 0.008, path - S * (w / 2), path + S * (w / 2), path + S * (w / 2) - Nn * 0.008]
    P = np.stack(rows, axis=1)  # (n, 4, 3)
    N = np.stack([Nn - S * 0.6, Nn, Nn, Nn + S * 0.6], axis=1)
    N /= np.linalg.norm(N, axis=2, keepdims=True)
    P = P.reshape(-1, 3)
    N = N.reshape(-1, 3)
    U = np.stack(np.meshgrid(np.linspace(0, 1, 4), np.linspace(0, 1, n)), axis=-1).reshape(-1, 2)
    T = []
    for i in range(n - 1):
        for j in range(3):
            a, b, c, d = i * 4 + j, i * 4 + j + 1, (i + 1) * 4 + j + 1, (i + 1) * 4 + j
            T += [(a, b, c), (a, c, d)]
    T = np.array(T, np.int64)
    g = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    flip = np.einsum("ij,ij->i", g, N[T].sum(axis=1)) < 0
    T[flip] = T[flip][:, ::-1]
    return {"P": P, "N": N, "U": U, "T": T}


# ------------------------------------------------------------------------------------------ build all
def build_all(B):
    """{tier: {piece name (with _R / _L): (lp, part name)}} in rest space; shared pieces appear in every tier,
    shifted to that tier's joints"""
    gl, X3 = glove(B)
    wr = wrap_hand(B)
    bf = boot_foot(B)
    so = sole(B)
    sl = shoe_laces(B, bf)
    shared = {"Glove": gl, "Wrap": wr, "BootFoot": bf, "Sole": so, "ShoeLaces": sl}
    seat_fns, seat_c = [], None
    seats = {}
    for n in TIER_IDS:
        band, seat, c, fn = band_and_seat(B, n)
        seats[n] = (band, seat)
        seat_fns.append(fn)
        seat_c = c
    # a shorts leg of tier n is worn under a seat of tier n or higher (the seat's tier is the highest of its parts)
    fields = {n: SeatField([f for k, f in zip(TIER_IDS, seat_fns) if k >= n], seat_c) for n in TIER_IDS}
    out = {}
    for n in TIER_IDS:
        d = {}
        field = fields[n]
        band, seat = seats[n]
        d["Waistband"] = (band, "LowerTorso")
        d["TrunkSeat"] = (seat, "LowerTorso")
        leg, hem, stripe = trunk_leg(B, n, "short", field)
        legL, hemL, _ = trunk_leg(B, n, "long", field)
        R = {"TrunkLeg": (leg, "UpperLeg"), "TrunkHem": (hem, "UpperLeg"), "TrunkStripe": (stripe, "UpperLeg"),
             "TrunkLegLong": (legL, "UpperLeg"), "TrunkHemLong": (hemL, "UpperLeg")}
        cuff, strap = cuff_and_strap(B, n, gl, X3)
        R["GloveCuff"] = (cuff, "LowerArm")
        R["GloveStrap"] = (strap, "LowerArm")
        R["WrapWrist"] = (wrap_wrist(B, n, wr, X3), "LowerArm")
        for k, v in shaft_parts(B, n, bf).items():
            R[k] = (v, "LowerLeg")
        dx = B.J(n, "RightWrist")[0] - X3
        for k in ("Glove", "Wrap"):
            lp = dict(shared[k])
            lp["P"] = shared[k]["P"] + np.array([dx, 0, 0])
            R[k] = (lp, "Hand")
        for k in ("BootFoot", "Sole", "ShoeLaces"):
            R[k] = (shared[k], "Foot")
        for k, (lp, base) in R.items():
            d[k + "_R"] = (lp, "Right" + base)
            d[k + "_L"] = (mirror(lp), "Left" + base)
        top, tband = sports_top(B, n)
        d["Top"] = (top, "UpperTorso")
        d["TopBand"] = (tband, "UpperTorso")
        out[n] = d
    return out, shared


def piece_base(name):
    return name[:-2] if name.endswith(("_R", "_L")) else name


def write_piece(path, lp):
    lo, hi = lp["P"].min(0), lp["P"].max(0)
    cen = (lo + hi) / 2
    pc = hl.Piece(os.path.basename(path), "gear")
    pc.P = [tuple(float(x) for x in p) for p in lp["P"] - cen]
    pc.N = [tuple(float(x) for x in hl.norm(nn)) for nn in lp["N"]]
    pc.U = [(float(u), float(v)) for u, v in lp["U"]]
    pc.C = [(1.0, 1.0, 1.0, 1.0)] * len(pc.P)
    pc.T = [tuple(int(i) for i in t) for t in lp["T"]]
    hl.write_mesh_v2(path, pc)
    return cen, hi - lo, pc.nt


def export(B, gear):
    os.makedirs(os.path.join(OUT, "shared"), exist_ok=True)
    data = {"version": 1, "slots": SLOTS, "pieces": {}, "sets": SETS, "tiers": {}}
    for name, (base, slot, group, sided, shared) in PIECES.items():
        for side in (("R", "L") if sided else ("",)):
            key = name + ("_" + side if side else "")
            data["pieces"][key] = {"part": (("Right" if side == "R" else "Left") + base) if side else base,
                                   "slot": slot, "group": group, "shared": shared}
            if name in TIER_OF:
                data["pieces"][key]["tierOf"] = TIER_OF[name]
    written = {}
    for n in TIER_IDS:
        td = os.path.join(OUT, "tier%d" % n)
        os.makedirs(td, exist_ok=True)
        rec = {}
        for key, (lp, part) in gear[n].items():
            base = piece_base(key)
            shared = PIECES[base][4]
            if shared:
                rel = "shared/%s.mesh" % key
                if rel not in written:
                    # the shared mesh is written once from the tier-3 placement (its shape is the same at every tier)
                    src = gear[3][key][0]
                    written[rel] = write_piece(os.path.join(OUT, rel), src)
                cen3, size, nt = written[rel]
                lo, hi = lp["P"].min(0), lp["P"].max(0)
                cen = (lo + hi) / 2
            else:
                rel = "tier%d/%s.mesh" % (n, key)
                cen, size, nt = write_piece(os.path.join(OUT, rel), lp)
            pc = B.centre(n, part)
            rec[key] = {"file": rel, "part": part, "offset": [round(float(x), 4) for x in cen - pc],
                        "size": [round(float(x), 4) for x in size], "nt": nt}
        data["tiers"][str(n)] = rec
    # worn tri counts per typical outfit
    worn = {}
    for look, sets in {"pro_hightop_gloves": [("trunks", "Pro"), ("shoes", "High-Top"), ("gloves", "Gloves")],
                       "long_lowtop_wraps_top": [("trunks", "Long"), ("shoes", "Low-Top"), ("wraps", "Wraps"),
                                                 ("top", "Top")],
                       "everything_max": [("trunks", "Pro"), ("shoes", "High-Top"), ("gloves", "Gloves"),
                                          ("top", "Top")]}.items():
        tot = 0
        for g, s in sets:
            for p in SETS[g][s]:
                for key in ([p + "_R", p + "_L"] if PIECES[p][3] else [p]):
                    tot += data["tiers"]["5"][key]["nt"]
        worn[look] = tot
    data["worn_tris_tier5"] = worn
    with open(os.path.join(OUT, "gear.json"), "w") as f:
        json.dump(data, f, indent=1)
    return data


# ------------------------------------------------------------------------------------------ check renders
COLORS = {  # linear-ish preview colours per slot
    "trunks": (0.55, 0.02, 0.02), "trim": (0.85, 0.85, 0.82), "gloves": (0.6, 0.015, 0.015),
    "gloveTrim": (0.85, 0.85, 0.82), "wraps": (0.85, 0.85, 0.82), "wraps2": (0.8, 0.8, 0.78),
    "shoes": (0.02, 0.02, 0.022), "soles": (0.8, 0.8, 0.78), "laces": (0.85, 0.85, 0.85),
    "socks": (0.85, 0.85, 0.85), "top": (0.05, 0.12, 0.5), "topTrim": (0.85, 0.85, 0.82),
}
ALT = {"trunks": (0.02, 0.06, 0.4), "trim": (0.7, 0.45, 0.02), "gloves": (0.02, 0.06, 0.4), "shoes": (0.5, 0.5, 0.5),
       "soles": (0.02, 0.02, 0.02)}


def stance_mats(Jt, guard=True, legs=True):
    M = bb.pose_mats(Jt, guard=guard)
    if legs:
        for side, sg, hip, knee, ank in (("Left", -1, 16, -20, 4), ("Right", 1, -10, -18, 26)):
            ul = bb.about(Jt[side + "Hip"], bb.rotx(hip) @ bb.rotz(sg * 4))
            ll = ul @ bb.about(Jt[side + "Knee"], bb.rotx(knee))
            ft = ll @ bb.about(Jt[side + "Ankle"], bb.rotx(ank - hip - knee))
            M[side + "UpperLeg"], M[side + "LowerLeg"], M[side + "Foot"] = ul, ll, ft
    return M


def wear_list(trunks="Pro", shoes="High-Top", hands="gloves", female=False):
    keys = []

    def add(group, style):
        for p in SETS[group][style]:
            keys.extend([p + "_R", p + "_L"] if PIECES[p][3] else [p])
    add("trunks", trunks)
    add("shoes", shoes)
    if hands == "gloves":
        add("gloves", "Gloves")
    elif hands == "wraps":
        add("wraps", "Wraps")
    if female:
        add("top", "Top")
    return keys


def dressed(st, tag, B, gear, n, x, yaw=0.0, pose=None, face="smile", colors=None, skin=None, z=0.0, **wear):
    import bpy  # noqa: F401
    parts = B.t[n]
    place = bb.M4(bb.roty(yaw), (x, 0, z))
    Jt = parts["_J"]
    pm = stance_mats(Jt) if pose == "guard" else bb.pose_mats(Jt)
    hidden = set()
    if wear.get("hands", "gloves") == "gloves":
        hidden |= {"LeftHand", "RightHand"}
    skin_mat = st.skin if skin is None else skin
    for name, lp in parts.items():
        if name.startswith("_") or name in hidden:
            continue
        st.add("%s_%s" % (tag, name), lp, place @ pm[name], skin_mat)
    neck = np.array(Jt["Neck"])
    hm = place @ pm["UpperTorso"]
    st.add(tag + "_Head", None, hm, st.headmat(face), D=bb.head_mesh(neck + np.array([0, bb.HEAD_SIZE / 2, 0]),
                                                                   bb.HEAD_SIZE))
    cols = dict(COLORS)
    cols.update(colors or {})
    for key in wear_list(**wear):
        lp, part = gear[n][key]
        slot = PIECES[piece_base(key)][1]
        st.add("%s_%s" % (tag, key), lp, place @ pm[part], gear_mat(st, slot, cols[slot]))


_mats = {}


def gear_mat(st, slot, col):
    k = (slot, col)
    if k not in _mats:
        rough = {"trunks": 0.32, "trim": 0.35, "top": 0.5, "topTrim": 0.5, "gloves": 0.36, "gloveTrim": 0.45,
                 "wraps": 0.85, "wraps2": 0.85, "shoes": 0.42, "soles": 0.7, "laces": 0.6, "socks": 0.85}[slot]
        _mats[k] = st.material("g_%s_%d" % (slot, len(_mats)), col, rough=rough)
    return _mats[k]


def render_sheets(B, gear, which, samples):
    import bpy
    paths = []
    CY = 3.25
    _mats.clear()
    if 1 in which:  # lineup: tiers 1 / 3 / 5 men, tier 3 woman, tier 5 low-top + wraps, long trunks
        st = bb.Stage(bpy, (1700, 820), samples)
        _mats.clear()
        st.floor()
        sp = 3.0
        looks = [(1, {}, dict(trunks="Classic")), (3, {}, dict(trunks="Striped")), (5, {}, dict(trunks="Pro")),
                 (3, {"trunks": ALT["trunks"], "gloves": ALT["gloves"], "trim": ALT["trim"]},
                  dict(trunks="Pro", female=True)),
                 (5, {"trunks": ALT["trunks"], "shoes": ALT["shoes"], "trim": ALT["trim"]},
                  dict(trunks="Long", shoes="Low-Top", hands="wraps"))]
        for i, (n, cols, wear) in enumerate(looks):
            dressed(st, "L%d" % i, B, gear, n, -(i - 2) * sp, colors=cols, **wear)
        p = st.shoot(os.path.join(SCRATCH, "gear_lineup.png"), 0, CY, 5 * sp + 0.5, elev=4)
        bb.label(p, ["T1 Classic / high-top / gloves", "T3 Striped", "T5 Pro", "T3 woman: top, Pro",
                     "T5 Long / low-top / wraps"], "Gear on the tier bodies (rest pose, front)")
        paths.append(p)
    if 2 in which:  # 3/4 and back + side
        st = bb.Stage(bpy, (1700, 820), samples)
        _mats.clear()
        st.floor()
        sp = 2.9
        order = [(1, -38), (3, -38), (5, -38), (3, 90), (1, 180), (5, 180)]
        for i, (n, yaw) in enumerate(order):
            dressed(st, "V%d" % i, B, gear, n, -(i - 2.5) * sp, yaw=yaw, trunks="Pro")
        p = st.shoot(os.path.join(SCRATCH, "gear_views.png"), 0, CY, 6 * sp + 0.3, elev=6)
        bb.label(p, ["T1 3/4", "T3 3/4", "T5 3/4", "T3 side", "T1 back", "T5 back"], "Gear: 3/4, side and back")
        paths.append(p)
    if 3 in which:  # guard / stance
        st = bb.Stage(bpy, (1700, 820), samples)
        _mats.clear()
        st.floor()
        sp = 3.0
        order = [(1, 0), (3, 0), (5, 0), (1, -40), (5, -40), (5, 60)]
        for i, (n, yaw) in enumerate(order):
            dressed(st, "G%d" % i, B, gear, n, -(i - 2.5) * sp, yaw=yaw, pose="guard", face="determined",
                    trunks="Classic" if i % 2 else "Pro")
        p = st.shoot(os.path.join(SCRATCH, "gear_guard.png"), 0, CY - 0.2, 6 * sp + 0.3, elev=6)
        bb.label(p, ["T1 guard", "T3 guard", "T5 guard", "T1 3/4", "T5 3/4", "T5 side"],
                 "Guard + stance (hips 16 / -10 deg, knees bent): trunks stay continuous, gloves on the fists")
        paths.append(p)
    if 4 in which:  # close-ups: glove, trunks, boots
        st = bb.Stage(bpy, (1700, 700), samples)
        _mats.clear()
        st.floor()
        # three boxers, the camera on their mid section
        dressed(st, "C0", B, gear, 5, 2.6, yaw=-30, trunks="Pro")
        dressed(st, "C1", B, gear, 3, 0.0, yaw=150, trunks="Striped")
        dressed(st, "C2", B, gear, 1, -2.6, yaw=-70, trunks="Long", shoes="Low-Top", hands="wraps")
        p = st.shoot(os.path.join(SCRATCH, "gear_close_mid.png"), 0, 2.2, 7.6, elev=6)
        bb.label(p, ["T5 Pro, 3/4 front", "T3 Striped, back 3/4", "T1 Long + low-top + wraps"],
                 "Close-up: trunks, gloves at the hips, boots")
        paths.append(p)
        st = bb.Stage(bpy, (1700, 700), samples)
        _mats.clear()
        st.floor()
        dressed(st, "H0", B, gear, 5, 2.4, yaw=-90, pose="guard", trunks="Pro")
        dressed(st, "H1", B, gear, 3, 0.0, yaw=-35, pose="guard", trunks="Pro")
        dressed(st, "H2", B, gear, 3, -2.4, yaw=-120, trunks="Pro", hands="wraps")
        dressed(st, "H3", B, gear, 3, -4.6, yaw=170, trunks="Pro", female=True)
        p = st.shoot(os.path.join(SCRATCH, "gear_close_hands.png"), -1.1, 3.9, 8.6, elev=8)
        bb.label(p, ["T5 guard side", "T3 guard 3/4", "T3 wraps (hands at the hips)", "T3 woman, back"],
                 "Close-up: gloves (guard), wraps, the top's back")
        paths.append(p)
    return paths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--samples", type=int, default=32)
    ap.add_argument("--sheets", default="1,2,3,4")
    a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    os.makedirs(SCRATCH, exist_ok=True)
    B = Bodies()
    gear, _ = build_all(B)
    data = export(B, gear)
    for n in TIER_IDS:
        print("tier %d:" % n, " ".join("%s=%d" % (k, v["nt"]) for k, v in data["tiers"][str(n)].items()
                                       if not k.endswith("_L")))
    print("worn tris (tier 5):", data["worn_tris_tier5"])
    files = set(v["file"] for t in data["tiers"].values() for v in t.values())
    print("mesh files:", len(files))
    if not a.no_render:
        for p in render_sheets(B, gear, [int(x) for x in a.sheets.split(",")], a.samples):
            print("sheet", p)


if __name__ == "__main__":
    main()
