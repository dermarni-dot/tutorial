"""Muscle-tier R15 body parts (PROTOTYPE for visual sign-off): the standard smooth Roblox R15 body with
muscles added in 5 tiers (1 lean, 2 toned, 3 athletic, 4 muscular, 5 elite), plus a plain "default body"
reconstruction (tier 0) for comparison.

Run with Blender's Python (Cycles CPU renders):
    /opt/bpyenv/bin/python tools/body/build_body.py                 # build + export + 3 sheets
    /opt/bpyenv/bin/python tools/body/build_body.py --no-render     # build + export only
    /opt/bpyenv/bin/python tools/body/build_body.py --samples 24 --sheets 1

Outputs
    tools/body/out/tier<N>/<Part>.mesh   Roblox mesh v2.00, vertices relative to the part's bbox centre
                                         (= the MeshPart origin Roblox gives an imported mesh)
    tools/body/out/tier<N>/parts.json    per part: size (bbox), attachments (part space), tris, verts
    tools/body/out/body_tiers.json       all tiers + the skeleton it was built on
    tools/body/blend/body_tiers.blend    rest-pose parts per tier + the lineup scene
    <scratch>/lineup_front.png, views_34_back.png, compare_default_t3.png

Coordinates: game space, numerically (no axis conversion): studs, +X = the character's right, +Y up,
-Z forward. The body is modelled in one "rest" space (feet on Y = 0) around the R15 Block rig's joint
pivots (SKELETON below), every part as its own closed shell. At a joint both neighbours carry the same
cross-section and end in a dome centred near the pivot, so each part's rounded end hides inside its
neighbour (the default body's ball-joint trick) and no gap opens when a joint turns.

Modelling: each part is a low-res loft (super-elliptic rings along the bone, domed ends) whose vertices are
exactly every 4th vertex of a refined loft. Smooth ellipsoidal "muscle" bells (growing with the tier) displace
the refined surface, and its normals are what the low-res mesh carries (Roblox meshes store per-vertex
normals), so soft muscle forms read at game triangle counts with clean quad topology (no decimation).
Joints: the parent's end (UpperTorso at the waist, UpperArm at the elbow, UpperLeg at the knee, LowerTorso
at its hem) finishes on a clean ring and tucks inward ("tucked rim"), the child is a few % thinner there, so
the seam is a crisp line like the default body's instead of two surfaces crossing.
"""
import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "hair"))
import hairlib as hl  # noqa: E402  (Piece, write_mesh_v2)

OUT = os.path.join(HERE, "out")
BLEND = os.path.join(HERE, "blend", "body_tiers.blend")
SCRATCH = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/body"

# ------------------------------------------------------------------------------------------ skeleton
# R15 "Block" rig (Studio Rig Builder / the default R15 avatar before scaling). Part sizes and the
# RigAttachment positions in each part's space; the joint pivots below are those chained from a LowerTorso
# centre at Y = 2.011 (feet on the floor). VERIFY against Studio (Avatar > Rig Builder > R15 Block) before
# production: every mesh and attachment below is regenerated from this table.
R15_BLOCK = {
    "sizes": {
        "UpperTorso": (2, 1.6, 1), "LowerTorso": (2, 0.4, 1),
        "UpperArm": (1, 1.169, 1), "LowerArm": (1, 1.052, 1), "Hand": (1, 0.3, 1),
        "UpperLeg": (1, 1.217, 1), "LowerLeg": (1, 1.193, 1), "Foot": (1, 0.3, 1), "Head": (1.2, 1.2, 1.2),
    },
    "attachments": {  # right side; the left side mirrors X
        "UpperTorso": {"Neck": (0, 0.8, 0), "Waist": (0, -0.8, 0), "RightShoulder": (1, 0.563, 0)},
        "LowerTorso": {"Waist": (0, 0.2, 0), "RightHip": (0.5, -0.2, 0)},
        "RightUpperArm": {"RightShoulder": (-0.5, 0.394, 0), "RightElbow": (0, -0.334, 0)},
        "RightLowerArm": {"RightElbow": (0, 0.192, 0), "RightWrist": (0, -0.501, 0)},
        "RightHand": {"RightWrist": (0, 0.125, 0)},
        "RightUpperLeg": {"RightHip": (0, 0.421, 0), "RightKnee": (0, -0.408, 0)},
        "RightLowerLeg": {"RightKnee": (0, 0.2, 0), "RightAnkle": (0, -0.547, 0)},
        "RightFoot": {"RightAnkle": (0, 0.085, 0)},
    },
}
Y_LT = 2.011
J = {
    "Waist": (0.0, Y_LT + 0.2, 0.0),
    "Neck": (0.0, Y_LT + 1.8, 0.0),
    "RightShoulder": (1.0, Y_LT + 1.563, 0.0),   # 3.574
    "RightElbow": (1.5, Y_LT + 0.835, 0.0),      # 2.846
    "RightWrist": (1.5, Y_LT + 0.142, 0.0),      # 2.153
    "RightHip": (0.5, Y_LT - 0.2, 0.0),          # 1.811
    "RightKnee": (0.5, Y_LT - 1.029, 0.0),       # 0.982
    "RightAnkle": (0.5, Y_LT - 1.776, 0.0),      # 0.235
}
for _k in list(J):
    if _k.startswith("Right"):
        x, y, z = J[_k]
        J["Left" + _k[5:]] = (-x, y, z)
J["Root"] = (0.0, Y_LT, 0.0)  # the block LowerTorso centre (RootRigAttachment: copy from the live rig)
HEAD_C = (0.0, J["Neck"][1] + 0.6, 0.0)
ARM_X, LEG_X = 1.5, 0.5  # ARM_X: the R15 Block arm axis (reference only; the tiers use arm_x below)


def arm_x(tr):
    """the arm's axis per tier: the upper arm's inner side sits against the torso's side in the relaxed pose.
    The Shoulder pivot stays at the R15 position (x = +-1); the Elbow / Wrist pivots lie on this axis."""
    return 1.20 + 0.22 * tr["m"]


def tier_joints(tr):
    Jt = dict(J)
    ax = arm_x(tr)
    for side, sg in (("Right", 1), ("Left", -1)):
        for jn in ("Elbow", "Wrist"):
            x, y, z = J[side + jn]
            Jt[side + jn] = (sg * ax, y, z)
    return Jt
YW, YN, YS = J["Waist"][1], J["Neck"][1], J["RightShoulder"][1]
YE, YWR, YH, YK, YA = J["RightElbow"][1], J["RightWrist"][1], J["RightHip"][1], J["RightKnee"][1], J["RightAnkle"][1]

PART_JOINTS = {
    "UpperTorso": ["Neck", "Waist", "RightShoulder", "LeftShoulder"],
    "LowerTorso": ["Waist", "RightHip", "LeftHip", "Root"],
    "UpperArm": ["Shoulder", "Elbow"], "LowerArm": ["Elbow", "Wrist"], "Hand": ["Wrist", "Grip"],
    "UpperLeg": ["Hip", "Knee"], "LowerLeg": ["Knee", "Ankle"], "Foot": ["Ankle"],
}
PARTS = ["UpperTorso", "LowerTorso"] + [s + p for s in ("Right", "Left") for p in
                                        ("UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot")]
# triangles come from each part's loft resolution (nb rings x nseg segments, caps); ~6.7k per body

# ------------------------------------------------------------------------------------------ tiers
# f = base features on (0 for the plain default-body reconstruction), m = muscle mass 0..1,
# d = definition (separation: six-pack, teardrop, ...) 0..1
TIERS = {
    0: dict(name="default", f=0.0, m=0.0, d=0.0),
    1: dict(name="lean", f=1.0, m=0.0, d=0.0),
    2: dict(name="toned", f=1.0, m=0.25, d=0.35),
    3: dict(name="athletic", f=1.0, m=0.5, d=0.7),
    4: dict(name="muscular", f=1.0, m=0.75, d=0.88),
    5: dict(name="elite", f=1.0, m=1.0, d=1.0),
}


# ------------------------------------------------------------------------------------------ maths
def pchip(xs, ys, x):
    """monotone cubic through the knots, zero slope at both ends (joint sections stay cylindrical)"""
    xs = np.asarray(xs, float)
    ys = np.asarray(ys, float)
    x = np.clip(np.asarray(x, float), xs[0], xs[-1])
    n = len(xs)
    h = np.diff(xs)
    d = np.diff(ys) / h
    m = np.zeros(n)
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    i = np.clip(np.searchsorted(xs, x) - 1, 0, n - 2)
    t = (x - xs[i]) / h[i]
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
            + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])


class Prof:
    """cross-section profile along a bone: keys ax (half width, local x), af / ab (half depth to the
    front / back), p (super-ellipse exponent), cx / cz (centre offsets). Each key = (base, delta at m=1)."""

    def __init__(self, s, **keys):
        self.s = s
        self.k = keys

    def __call__(self, s, m):
        out = {}
        for key, dflt in (("ax", 0.3), ("af", 0.3), ("ab", None), ("p", 2.0), ("cx", 0.0), ("cz", 0.0)):
            v = self.k.get(key)
            if v is None:
                out[key] = out["af"] if key == "ab" else np.full_like(np.asarray(s, float), dflt)
                continue
            base, dlt = v if isinstance(v, tuple) else (v, None)
            base = np.broadcast_to(np.asarray(base, float), (len(self.s),))
            val = pchip(self.s, base, s)
            if dlt is not None:
                val = val + m * pchip(self.s, np.broadcast_to(np.asarray(dlt, float), (len(self.s),)), s)
            out[key] = val
        return out


def superr(phi, ax, af, ab, p):
    s, c = np.sin(phi), np.cos(phi)
    B = np.where(c > 0, af, ab)
    return (np.abs(s / ax) ** p + np.abs(c / B) ** p + 1e-12) ** (-1.0 / p)


def vnormals(P, T):
    n = np.zeros_like(P)
    f = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    for k in range(3):
        np.add.at(n, T[:, k], f)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(ln, 1e-12)


class Dense:
    """welded dense mesh: P (n,3), T (m,3), UV per triangle corner (m,3,2), game convention (v down)"""

    def __init__(self, P, T, UV):
        self.P, self.T, self.UV = np.asarray(P, float), np.asarray(T, np.int64), np.asarray(UV, float)

    @staticmethod
    def merge(ms):
        P, T, UV, base = [], [], [], 0
        for m in ms:
            P.append(m.P)
            T.append(m.T + base)
            UV.append(m.UV)
            base += len(m.P)
        return Dense(np.vstack(P), np.vstack(T), np.vstack(UV))

    def orient(self, inside):
        """winds every shell outward: flip triangles whose normal points toward `inside` points"""
        N = np.cross(self.P[self.T[:, 1]] - self.P[self.T[:, 0]], self.P[self.T[:, 2]] - self.P[self.T[:, 0]])
        C = self.P[self.T].mean(axis=1)
        flip = np.einsum("ij,ij->i", N, C - inside) < 0
        self.T[flip] = self.T[flip][:, ::-1]
        self.UV[flip] = self.UV[flip][:, ::-1]


def _ring_specs(s_lo, s_hi, cap_lo, cap_hi, nb, sdens, k=1):
    """ring list [(s, scale, profile s)] bottom to top; k refines every interval k times (the low-res rings
    are then exactly every k-th ring of the refined list)"""
    rings = []
    if cap_lo:
        h, e, n = cap_lo[:3]
        st = cap_lo[3] if len(cap_lo) > 3 else 1.0
        for i in range(n * k - 1, 0, -1):
            a = i / (n * k) * math.pi / 2
            rings.append((s_lo - h * math.sin(a), math.cos(a) ** e * st, s_lo))
        if st < 1:  # tucked rim: the visible surface ends on a clean ring just outside the neighbour
            rings.append((s_lo - STEP_DS, st, s_lo))
    nbk = (nb - 1) * k + 1
    t = np.linspace(0, 1, nbk)
    if sdens is not None:
        xs = np.linspace(s_lo, s_hi, 400)
        dn = np.interp(xs, sdens[0], sdens[1])
        cum = np.concatenate([[0], np.cumsum((dn[1:] + dn[:-1]) / 2 * np.diff(xs))])
        cum /= cum[-1]
        S = np.interp(t, cum, xs)
    else:
        S = s_lo + (s_hi - s_lo) * t
    lo_step = cap_lo is not None and len(cap_lo) > 3 and cap_lo[3] < 1
    hi_step = cap_hi is not None and len(cap_hi) > 3 and cap_hi[3] < 1
    if lo_step:
        rings.append((s_lo, 1.0, s_lo))
        S = S[S > s_lo + STEP_DS * 1.5]
        rings.append((s_lo + STEP_DS, 1.0, s_lo + STEP_DS))
    for s in S:
        if hi_step and s >= s_hi - STEP_DS * 1.5:
            continue
        rings.append((float(s), 1.0, float(s)))
    if hi_step:
        rings.append((s_hi - STEP_DS, 1.0, s_hi - STEP_DS))
        rings.append((s_hi, 1.0, s_hi))
    if cap_hi:
        h, e, n = cap_hi[:3]
        st = cap_hi[3] if len(cap_hi) > 3 else 1.0
        if st < 1:
            rings.append((s_hi + STEP_DS, st, s_hi))
        for i in range(1, n * k):
            a = i / (n * k) * math.pi / 2
            rings.append((s_hi + h * math.sin(a), math.cos(a) ** e * st, s_hi))
    return rings


STEP_DS = 0.012  # rim: the last visible ring and the tuck-in ring sit this far from the joint end


def _phis(nseg, bias):
    u = np.arange(nseg) / nseg - 0.5
    return 2 * math.pi * u - bias * np.sin(2 * math.pi * u)


def _shrink(ps, shrink):
    f = np.ones_like(ps)
    for s_end, length, amount in shrink:
        if length > 0:  # joint at the top end: shrink over [s_end - length, s_end]
            t = np.clip((ps - (s_end - length)) / length, 0, 1)
        else:
            t = np.clip(((s_end - length) - ps) / -length, 0, 1)
        f *= 1 - amount * t * t * (3 - 2 * t)
    return f


def _grid(prof, m, rings, phis, frame, shrink):
    O, A, X, Z = [np.asarray(v, float) for v in frame]
    S = np.array([r[0] for r in rings])
    SC = np.array([r[1] for r in rings])
    PS = np.array([r[2] for r in rings])
    pr = prof(PS, m)
    sh = _shrink(PS, shrink)
    nseg = len(phis)
    P = np.empty((len(rings), nseg, 3))
    C = np.empty((len(rings), 3))
    for i in range(len(rings)):
        r = superr(phis, pr["ax"][i], pr["af"][i], pr["ab"][i], pr["p"][i]) * SC[i] * sh[i]
        c = O + A * S[i] + X * pr["cx"][i] + Z * pr["cz"][i]
        C[i] = c
        P[i] = c[None, :] + np.outer(r * np.sin(phis), X) + np.outer(-r * np.cos(phis), Z)
    return P, C, S


def _grid_mesh(P, poles, closed_u=True):
    """welded triangles over a (R, nseg) grid wrapping in u, with optional pole points at both ends"""
    R, n = P.shape[:2]
    V = P.reshape(-1, 3)
    iv = lambda i, j: i * n + (j % n)  # noqa: E731
    T = []
    for i in range(R - 1):
        for j in range(n):
            a, b, c, d = iv(i, j), iv(i, j + 1), iv(i + 1, j + 1), iv(i + 1, j)
            T += [(a, b, c), (a, c, d)]
    extra = []
    lo, hi = poles
    if lo is not None:
        pi_ = len(V) + len(extra)
        extra.append(lo)
        T += [(pi_, iv(0, j + 1), iv(0, j)) for j in range(n)]
    if hi is not None:
        pi_ = len(V) + len(extra)
        extra.append(hi)
        T += [(pi_, iv(R - 1, j), iv(R - 1, j + 1)) for j in range(n)]
    if extra:
        V = np.vstack([V, np.array(extra)])
    return V, np.array(T, np.int64)


def _orient_out(V, T, centres):
    N = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    Cc = V[T].mean(axis=1)
    sub = centres[:: max(1, len(centres) // 60)]
    idx = np.argmin(((Cc[:, None, :] - sub[None, :, :]) ** 2).sum(-1), axis=1)
    flip = np.einsum("ij,ij->i", N, Cc - sub[idx]) < 0
    T = T.copy()
    T[flip] = T[flip][:, ::-1]
    return T


def loft(prof, m, s_lo, s_hi, cap_lo, cap_hi, nb, nseg, frame=None, bias=0.0, sdens=None, shrink=(),
         bumps=(), sub=4):
    """Low-res loft whose vertices are exactly every `sub`-th vertex of a refined loft; the muscle bumps
    displace the refined surface and its normals are what the low-res mesh carries (a vertex-density
    "normal map"). cap = (height, exponent, rings). Returns lp {P, N, U, T} with a duplicated UV seam
    column at the back (phi = +-pi) and single pole vertices."""
    frame = frame or ((0, 0, 0), (0, 1, 0), (1, 0, 0), (0, 0, 1))
    k = sub
    rd = _ring_specs(s_lo, s_hi, cap_lo, cap_hi, nb, sdens, k)
    rl = _ring_specs(s_lo, s_hi, cap_lo, cap_hi, nb, sdens, 1)
    # low ring i -> refined ring index
    key = {(round(r[0], 9), round(r[1], 9)): i for i, r in enumerate(rd)}
    ridx = [key[(round(r[0], 9), round(r[1], 9))] for r in rl]
    phd = _phis(nseg * k, bias)
    Pd, Cd, Sd = _grid(prof, m, rd, phd, frame, shrink)
    O, A, X, Z = [np.asarray(v, float) for v in frame]
    pr0, pr1 = prof(np.array([s_lo, s_hi]), m)["cx"], prof(np.array([s_lo, s_hi]), m)["cz"]
    pole_lo = (O + A * (s_lo - cap_lo[0]) + X * pr0[0] + Z * pr1[0]) if cap_lo else None
    pole_hi = (O + A * (s_hi + cap_hi[0]) + X * pr0[1] + Z * pr1[1]) if cap_hi else None
    V, T = _grid_mesh(Pd, (pole_lo, pole_hi))
    T = _orient_out(V, T, Cd)
    if bumps:
        N0 = vnormals(V, T)
        disp = np.zeros(len(V))
        for bp in bumps:
            disp += bp[2] * bell(V, bp[0], bp[1], *bp[3:])
        V = V + N0 * disp[:, None]
    N = vnormals(V, T)
    R, nd = Pd.shape[:2]
    Vg = V[: R * nd].reshape(R, nd, 3)
    Ng = N[: R * nd].reshape(R, nd, 3)
    # low-res grid
    cols = np.arange(nseg) * k
    PL = Vg[ridx][:, cols]
    NL = Ng[ridx][:, cols]
    # duplicate the seam column (u = 1)
    PL = np.concatenate([PL, PL[:, :1]], axis=1)
    NL = np.concatenate([NL, NL[:, :1]], axis=1)
    RL = len(rl)
    nL = nseg + 1
    S = np.array([r[0] for r in rl])
    acc = np.concatenate([[0], np.cumsum(np.abs(np.diff(S)))])
    vv = 1 - acc / max(acc[-1], 1e-9)
    uu = (_phis(nseg, bias) + math.pi) / (2 * math.pi)
    uu = np.concatenate([uu, [1.0]])
    P = PL.reshape(-1, 3)
    Nn = NL.reshape(-1, 3)
    U = np.stack(np.meshgrid(uu, vv), axis=-1).reshape(-1, 2)
    iv = lambda i, j: i * nL + j  # noqa: E731
    Tl = []
    for i in range(RL - 1):
        for j in range(nseg):
            Tl += [(iv(i, j), iv(i, j + 1), iv(i + 1, j + 1)), (iv(i, j), iv(i + 1, j + 1), iv(i + 1, j))]
    extraP, extraN, extraU = [], [], []
    if pole_lo is not None:
        pi_ = len(P)
        extraP.append(V[R * nd]); extraN.append(N[R * nd]); extraU.append((0.5, 1.0))
        Tl += [(pi_, iv(0, j + 1), iv(0, j)) for j in range(nseg)]
    if pole_hi is not None:
        q = R * nd + (1 if pole_lo is not None else 0)
        pi_ = len(P) + len(extraP)
        extraP.append(V[q]); extraN.append(N[q]); extraU.append((0.5, 0.0))
        Tl += [(pi_, iv(RL - 1, j), iv(RL - 1, j + 1)) for j in range(nseg)]
    if extraP:
        P = np.vstack([P, extraP]); Nn = np.vstack([Nn, extraN]); U = np.vstack([U, extraU])
    Tl = np.array(Tl, np.int64)
    # wind like the normals
    g = np.cross(P[Tl[:, 1]] - P[Tl[:, 0]], P[Tl[:, 2]] - P[Tl[:, 0]])
    flip = np.einsum("ij,ij->i", g, Nn[Tl].sum(axis=1)) < 0
    Tl[flip] = Tl[flip][:, ::-1]
    return {"P": P, "N": Nn, "U": U, "T": Tl}


def tube(pts, radii, nside=6, kcap=2, uvbox=(0, 0, 1, 1)):
    """closed round tube along a polyline (fingers), hemispherical ends; lp dict with own smooth normals"""
    pts = [np.asarray(p, float) for p in pts]
    n = len(pts)
    tan = [hl.norm(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]) for i in range(n)]
    ref = np.array([0.0, 0.0, 1.0]) if abs(tan[0][2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    nr = hl.norm(np.cross(np.cross(tan[0], ref), tan[0]))
    frames = []
    for i in range(n):
        if i:
            nr = hl.norm(nr - tan[i] * np.dot(nr, tan[i]))
        frames.append((nr, np.cross(tan[i], nr)))
    rings = []
    for i in range(kcap - 1, 0, -1):
        a = i / kcap * math.pi / 2
        rings.append((pts[0] - tan[0] * radii[0] * math.sin(a), math.cos(a), 0))
    for i in range(n):
        rings.append((pts[i], 1.0, i))
    for i in range(1, kcap):
        a = i / kcap * math.pi / 2
        rings.append((pts[-1] + tan[-1] * radii[-1] * math.sin(a), math.cos(a), n - 1))
    ang = 2 * math.pi * np.arange(nside + 1) / nside
    R = len(rings)
    P, N, U = [], [], []
    u0, v0, u1, v1 = uvbox
    for ri, (c, sc, fi) in enumerate(rings):
        nr_, bn = frames[fi]
        r = radii[fi] * sc
        for kk, a in enumerate(ang):
            d = nr_ * math.cos(a) + bn * math.sin(a)
            P.append(c + d * r)
            # sphere-like normals on the caps
            ax = tan[fi] * (-1 if ri < kcap - 1 else (1 if ri >= kcap - 1 + n else 0))
            sa = math.sqrt(max(0.0, 1 - sc * sc))
            N.append(hl.norm(d * sc + ax * sa))
            U.append((u0 + (u1 - u0) * kk / nside, v0 + (v1 - v0) * ri / max(1, R - 1)))
    p0, p1 = pts[0] - tan[0] * radii[0], pts[-1] + tan[-1] * radii[-1]
    P += [p0, p1]
    N += [-tan[0], tan[-1]]
    U += [((u0 + u1) / 2, v0), ((u0 + u1) / 2, v1)]
    m = nside + 1
    iv = lambda i, j: i * m + j  # noqa: E731
    T = []
    for i in range(R - 1):
        for j in range(nside):
            T += [(iv(i, j), iv(i, j + 1), iv(i + 1, j + 1)), (iv(i, j), iv(i + 1, j + 1), iv(i + 1, j))]
    a0, a1 = R * m, R * m + 1
    T += [(a0, iv(0, j + 1), iv(0, j)) for j in range(nside)]
    T += [(a1, iv(R - 1, j), iv(R - 1, j + 1)) for j in range(nside)]
    P, N, U, T = np.array(P), np.array(N), np.array(U), np.array(T, np.int64)
    g = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    flip = np.einsum("ij,ij->i", g, N[T].sum(axis=1)) < 0
    T[flip] = T[flip][:, ::-1]
    return {"P": P, "N": N, "U": U, "T": T}


def merge_lp(lps):
    P, N, U, T, base = [], [], [], [], 0
    for lp in lps:
        P.append(lp["P"]); N.append(lp["N"]); U.append(lp["U"]); T.append(lp["T"] + base)
        base += len(lp["P"])
    return {"P": np.vstack(P), "N": np.vstack(N), "U": np.vstack(U), "T": np.vstack(T)}


# ------------------------------------------------------------------------------------------ muscles
def bell(P, c, ext, rot=None, p=2.0, flat=0.0):
    """smooth ellipsoidal bump: 1 at the centre, 0 at the boundary, zero slope there.
    ext = (x-, x+, y-, y+, z-, z+) half extents per signed local axis; p > 2 squares the outline in the
    local xy plane (abs blocks); flat > 0 gives a plateau (the inner 'flat' share of the bump is level)."""
    Q = P - np.asarray(c, float)
    if rot is not None:
        Q = Q @ np.asarray(rot, float)
    e = np.empty_like(Q)
    for k in range(3):
        e[:, k] = np.where(Q[:, k] < 0, ext[2 * k], ext[2 * k + 1])
    q = np.abs(Q / e)
    d2 = (q[:, 0] ** p + q[:, 1] ** p) ** (2.0 / p) + q[:, 2] ** 2
    k = np.clip(1 - d2, 0, 1)
    if flat > 0:
        k = np.clip(k / (1 - flat), 0, 1)
    return k * k * (3 - 2 * k)


def roty(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rotz(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rotx(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def amp(tr, f=0.0, m=0.0, d=0.0):
    return f * tr["f"] + m * tr["m"] + d * tr["d"]


def Bp(c, ext, a, rot=None, p=2.0, flat=0.0):
    return (c, ext, a, rot, p, flat)


def sym(bumps):
    """bumps centred on x = 0 stay single, the rest get a mirrored twin"""
    out = []
    M = np.diag([-1.0, 1.0, 1.0])
    for c, ext, a, rot, p, flat in bumps:
        out.append((c, ext, a, rot, p, flat))
        if abs(c[0]) > 1e-6:
            rot2 = None if rot is None else M @ np.asarray(rot) @ M
            out.append(((-c[0], c[1], c[2]), (ext[1], ext[0]) + tuple(ext[2:]), a, rot2, p, flat))
    return out


# ------------------------------------------------------------------------------------------ parts
def torso_prof():
    s = [1.58, 1.80, 2.00, 2.21, 2.45, 2.75, 3.05, 3.30, 3.48, 3.60]
    return Prof(
        s,
        ax=([0.70, 0.935, 0.91, 0.83, 0.80, 0.83, 0.88, 0.93, 0.99, 1.00],
            [0.00, 0.02, 0.00, -0.06, -0.06, 0.00, 0.08, 0.10, 0.05, 0.04]),
        af=([0.34, 0.44, 0.43, 0.41, 0.40, 0.40, 0.42, 0.43, 0.41, 0.38],
            [0.00, 0.00, 0.00, -0.02, -0.02, 0.00, 0.02, 0.03, 0.03, 0.03]),
        ab=([0.36, 0.47, 0.44, 0.39, 0.39, 0.41, 0.43, 0.44, 0.42, 0.38],
            [0.00, 0.03, 0.01, 0.00, 0.00, 0.02, 0.05, 0.06, 0.06, 0.05]),
        p=[2.8, 3.2, 2.9, 2.7, 2.7, 2.8, 2.9, 3.0, 3.0, 3.0],
    )


VERT = lambda x: ((x, 0, 0), (0, 1, 0), (1, 0, 0), (0, 0, 1))  # noqa: E731


def upper_torso(tr):
    b = [
        # pecs: a broad plate with a defined lower edge rising toward the armpit
        Bp((0.40, 3.23, -0.40), (0.37, 0.46, 0.21, 0.42, 0.5, 0.5), amp(tr, 0.012, 0.10, 0.01), rotz(12), 2.4, 0.15),
        # sternum line between the pecs
        Bp((0.0, 3.16, -0.45), (0.06, 0.06, 0.26, 0.24, 0.3, 0.3), amp(tr, 0, -0.01, -0.012)),
        # linea alba
        Bp((0.0, 2.65, -0.45), (0.04, 0.04, 0.34, 0.34, 0.3, 0.3), amp(tr, 0, -0.004, -0.010)),
        # obliques
        Bp((0.70, 2.45, -0.18), (0.16, 0.16, 0.24, 0.26, 0.3, 0.3), amp(tr, 0.0, 0.03, 0.004)),
        # serratus (soft fingers under the armpit)
        Bp((0.76, 2.96, -0.24), (0.10, 0.10, 0.14, 0.14, 0.14, 0.14), amp(tr, 0, 0.015, 0.01), rotz(-25)),
        # lats: V taper
        Bp((0.84, 3.08, 0.18), (0.22, 0.20, 0.45, 0.32, 0.30, 0.30), amp(tr, 0.0, 0.07, 0.0)),
        Bp((0.55, 2.98, 0.42), (0.34, 0.34, 0.55, 0.40, 0.25, 0.25), amp(tr, 0.0, 0.06, 0.008), rotz(-18)),  # lat sweep
        Bp((0.15, 2.45, 0.40), (0.12, 0.14, 0.34, 0.32, 0.25, 0.25), amp(tr, 0.0, 0.025, 0.01)),  # erectors
        # traps: neck-to-shoulder slope, upper back
        Bp((0.34, 3.78, 0.08), (0.30, 0.42, 0.34, 0.18, 0.35, 0.30), amp(tr, 0.02, 0.095, 0.0)),
        Bp((0.42, 3.40, 0.40), (0.36, 0.38, 0.34, 0.30, 0.25, 0.25), amp(tr, 0.005, 0.055, 0.004)),  # upper back
        # shoulder cap: the torso's shoulder rounds into the deltoid (no notch from the front / 3/4)
        Bp((0.90, 3.56, 0.0), (0.24, 0.16, 0.22, 0.20, 0.36, 0.36), amp(tr, 0.025, 0.05, 0.0)),
        # spine groove
        Bp((0.0, 2.95, 0.45), (0.07, 0.07, 0.75, 0.65, 0.3, 0.3), amp(tr, -0.006, -0.014, -0.02)),
    ]
    # six-pack: 3 rows x 2 columns of soft pillows
    for y, ey, w in ((2.93, 0.125, 1.0), (2.695, 0.122, 1.0), (2.465, 0.118, 0.92)):
        b.append(Bp((0.165, y, -0.42), (0.15, 0.16 * w, ey, ey, 0.3, 0.3), amp(tr, 0.003, 0.012, 0.027),
                    rotz(-3), 2.2, 0.12))
    sd = ([YW, 2.32, 2.36, 3.36, 3.42, 3.54], [0.6, 0.6, 1.3, 1.3, 0.8, 0.8])
    return loft(torso_prof(), tr["m"], YW, 3.54, (0.22, 1.0, 2, 0.88), (0.33, 0.85, 6), nb=22, nseg=30, bias=0.5,
                sdens=sd, bumps=sym(b))


def lower_torso(tr):
    b = [
        Bp((0.36, 1.99, 0.30), (0.34, 0.36, 0.17, 0.24, 0.30, 0.36), amp(tr, 0.03, 0.06, 0.0)),  # glutes
        Bp((0.0, 2.10, -0.42), (0.22, 0.22, 0.14, 0.10, 0.3, 0.3), amp(tr, 0.0, 0.012, 0.01)),  # lower abs
        Bp((0.0, 2.0, 0.45), (0.04, 0.04, 0.17, 0.15, 0.3, 0.3), amp(tr, -0.015, -0.01, 0.0)),  # cleft
    ]
    # the child of the waist joint: a touch thinner near it so the UpperTorso's dome dives cleanly under
    return loft(torso_prof(), tr["m"], 1.82, 2.30, (0.26, 1.0, 5, 0.9), (0.18, 1.0, 2), nb=7, nseg=24, bias=0.2,
                shrink=[(YW, 0.10, 0.04)], bumps=sym(b))


def upper_arm(tr):
    pr = Prof([YE, 3.00, 3.20, 3.40, 3.52],
              ax=([0.29, 0.30, 0.32, 0.35, 0.37], [0.03, 0.05, 0.07, 0.09, 0.10]),
              af=([0.28, 0.29, 0.31, 0.33, 0.35], [0.02, 0.04, 0.05, 0.06, 0.07]),
              p=2.1, cx=[0.0, 0.0, 0.0, -0.01, -0.03])
    X = arm_x(tr)
    b = [
        Bp((X + 0.08, 3.50, 0.0), (0.32, 0.28, 0.40, 0.30, 0.36, 0.36), amp(tr, 0.012, 0.075, 0.0)),  # delt cap
        Bp((X - 0.02, 3.48, -0.20), (0.26, 0.24, 0.32, 0.25, 0.20, 0.25), amp(tr, 0.0, 0.05, 0.0)),  # front delt
        Bp((X - 0.17, 3.62, 0.0), (0.18, 0.22, 0.24, 0.20, 0.34, 0.34), amp(tr, 0.02, 0.05, 0.0)),  # delt wrap over the shoulder
        Bp((X - 0.02, 3.48, 0.20), (0.26, 0.24, 0.30, 0.25, 0.25, 0.20), amp(tr, 0.0, 0.035, 0.0)),  # rear delt
        Bp((X, 3.08, -0.22), (0.24, 0.24, 0.22, 0.32, 0.26, 0.26), amp(tr, 0.008, 0.08, 0.008)),  # biceps
        Bp((X + 0.04, 3.20, 0.22), (0.20, 0.24, 0.30, 0.24, 0.25, 0.25), amp(tr, 0.008, 0.075, 0.005)),  # triceps
        Bp((X + 0.22, 3.22, 0.0), (0.06, 0.08, 0.10, 0.08, 0.25, 0.25), amp(tr, 0, 0, -0.008)),  # delt insertion
    ]
    return loft(pr, tr["m"], YE, 3.52, (0.27, 1.0, 2, 0.88), (0.33, 0.7, 4), nb=8, nseg=16, frame=VERT(X), bumps=b)


def lower_arm(tr):
    pr = Prof([YWR, 2.30, 2.50, 2.70, YE],
              ax=([0.15, 0.18, 0.23, 0.27, 0.29], [0.01, 0.02, 0.04, 0.05, 0.03]),
              af=([0.19, 0.20, 0.235, 0.265, 0.28], [0.01, 0.02, 0.03, 0.04, 0.02]),
              p=2.1)
    X = arm_x(tr)
    b = [
        Bp((X + 0.07, 2.64, -0.08), (0.22, 0.22, 0.38, 0.22, 0.24, 0.24), amp(tr, 0.006, 0.045, 0.0)),  # brachioradialis
        Bp((X - 0.10, 2.62, -0.04), (0.18, 0.18, 0.32, 0.18, 0.22, 0.22), amp(tr, 0.004, 0.04, 0.0)),  # flexors
    ]
    return loft(pr, tr["m"], YWR, YE, (0.15, 1.0, 2), (0.27, 1.0, 2), nb=8, nseg=14, frame=VERT(X),
                shrink=[(YE, 0.10, 0.06)], bumps=b)


def hand(tr):
    X = arm_x(tr)
    pr = Prof([1.93, 2.05, 2.17],
              ax=([0.125, 0.15, 0.14], [0.01, 0.01, 0.01]),
              af=([0.215, 0.215, 0.18], [0.01, 0.01, 0.01]),
              p=[3.0, 3.0, 2.4], cx=[-0.02, 0.0, 0.0])
    shells = [loft(pr, tr["m"], 1.93, 2.17, (0.06, 1.0, 2), (0.13, 1.0, 2), nb=4, nseg=12, frame=VERT(X))]
    # fingers: index at the front (-Z), relaxed curl toward the body (-X for the right hand)
    for i, (z, L, r) in enumerate(((-0.15, 0.17, 0.056), (-0.05, 0.185, 0.058), (0.05, 0.175, 0.056),
                                   (0.148, 0.145, 0.052))):
        y0 = 1.97
        pts = [(X - 0.015, y0, z), (X - 0.035, y0 - 0.55 * L, z), (X - 0.095, y0 - L, z * 1.02)]
        shells.append(tube(pts, [r, r * 0.96, r * 0.9], nside=6, kcap=2, uvbox=(0.2 * i, 0.8, 0.2 * i + 0.2, 1.0)))
    pts = [(X - 0.03, 2.10, -0.16), (X - 0.07, 2.01, -0.235), (X - 0.12, 1.935, -0.255)]
    shells.append(tube(pts, [0.068, 0.063, 0.057], nside=6, kcap=2, uvbox=(0.8, 0.8, 1.0, 1.0)))
    # palm UVs live in the top 80 %
    shells[0]["U"] = shells[0]["U"] * np.array([1.0, 0.8])
    return merge_lp(shells)


def upper_leg(tr):
    pr = Prof([YK, 1.15, 1.40, 1.65, 1.82],
              ax=([0.31, 0.34, 0.38, 0.41, 0.42], [0.02, 0.045, 0.05, 0.03, 0.01]),
              af=([0.30, 0.33, 0.37, 0.40, 0.41], [0.02, 0.04, 0.06, 0.05, 0.02]),
              ab=([0.30, 0.33, 0.37, 0.41, 0.44], [0.02, 0.03, 0.05, 0.05, 0.04]),
              p=2.15, cx=([0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.02, 0.025, 0.015, 0.0]))
    X = LEG_X
    b = [
        Bp((X + 0.02, 1.42, -0.33), (0.24, 0.24, 0.40, 0.35, 0.30, 0.30), amp(tr, 0.008, 0.06, 0.0)),  # quads
        Bp((X - 0.15, 1.14, -0.24), (0.14, 0.15, 0.14, 0.22, 0.20, 0.20), amp(tr, 0.004, 0.05, 0.012)),  # teardrop
        Bp((X + 0.26, 1.36, -0.05), (0.16, 0.16, 0.36, 0.30, 0.30, 0.30), amp(tr, 0.0, 0.03, 0.0)),  # outer sweep
        Bp((X, 1.36, 0.32), (0.28, 0.28, 0.35, 0.30, 0.25, 0.25), amp(tr, 0.004, 0.04, 0.0)),  # hamstrings
        Bp((X - 0.02, 1.72, 0.36), (0.32, 0.30, 0.18, 0.09, 0.25, 0.25), amp(tr, 0.012, 0.035, 0.0)),  # glute fold (stays under the hem)
    ]
    return loft(pr, tr["m"], YK, 1.96, (0.29, 1.0, 2, 0.88), (0.22, 0.9, 3), nb=10, nseg=14, frame=VERT(X),
                shrink=[(1.96, 0.20, 0.12)], bumps=b)


def lower_leg(tr):
    pr = Prof([YA, 0.35, 0.55, 0.75, 0.90, YK],
              ax=([0.17, 0.185, 0.225, 0.27, 0.295, 0.31], [0.01, 0.02, 0.03, 0.04, 0.03, 0.02]),
              af=([0.18, 0.19, 0.22, 0.25, 0.28, 0.30], [0.01, 0.01, 0.02, 0.03, 0.02, 0.02]),
              ab=([0.18, 0.20, 0.25, 0.29, 0.30, 0.30], [0.01, 0.02, 0.04, 0.05, 0.04, 0.02]),
              p=2.1)
    X = LEG_X
    b = [
        Bp((X - 0.09, 0.70, 0.22), (0.17, 0.15, 0.24, 0.20, 0.20, 0.20), amp(tr, 0.008, 0.06, 0.0)),  # medial calf
        Bp((X + 0.09, 0.75, 0.22), (0.15, 0.17, 0.22, 0.20, 0.20, 0.20), amp(tr, 0.005, 0.045, 0.0)),  # lateral calf
        Bp((X + 0.06, 0.70, -0.20), (0.12, 0.14, 0.30, 0.20, 0.20, 0.20), amp(tr, 0.0, 0.02, 0.0)),  # tibialis
    ]
    return loft(pr, tr["m"], YA, YK, (0.18, 1.0, 3), (0.29, 1.0, 2), nb=8, nseg=14, frame=VERT(X),
                shrink=[(YK, 0.10, 0.06)], bumps=b)


def foot(tr):
    s = [-0.25, -0.12, 0.05, 0.25, 0.40]  # local s = -Z (forward) from the ankle
    pr = Prof(s, ax=[0.185, 0.205, 0.215, 0.235, 0.225],
              af=[0.20, 0.22, 0.17, 0.085, 0.055],  # "front" = up from yc
              ab=[0.15, 0.15, 0.15, 0.15, 0.15], p=[2.6, 2.6, 2.6, 2.8, 2.8])
    return loft(pr, tr["m"], s[0], s[-1], (0.10, 1.0, 2), (0.11, 1.0, 2), nb=6, nseg=12,
                frame=((LEG_X, 0.15, 0.0), (0, 0, -1), (1, 0, 0), (0, -1, 0)))


BUILDERS = {"UpperTorso": upper_torso, "LowerTorso": lower_torso, "UpperArm": upper_arm, "LowerArm": lower_arm,
            "Hand": hand, "UpperLeg": upper_leg, "LowerLeg": lower_leg, "Foot": foot}


def head_mesh():
    """a classic Roblox-style head: rounded cylinder-block, 1.2 studs, planar face UVs (front only)"""
    a, b, c = 0.6, 0.6, 0.58
    nu, nv = 64, 40
    P, U = [], []
    for i in range(nv + 1):
        v = -math.pi / 2 + math.pi * i / nv
        sv, cv = math.sin(v), math.cos(v)
        y = b * math.copysign(abs(sv) ** (2 / 6), sv)
        sc = abs(cv) ** (2 / 6)
        for j in range(nu):
            ph = 2 * math.pi * j / nu
            s, co = math.sin(ph), math.cos(ph)
            r = (abs(s) ** 2.6 + abs(co) ** 2.6) ** (-1 / 2.6)
            x, z = a * r * s * sc, -c * r * co * sc
            P.append((x, y, z))
    P = np.array(P) + np.array(HEAD_C)
    T = []
    for i in range(nv):
        for j in range(nu):
            a0, b0 = i * nu + j, i * nu + (j + 1) % nu
            a1, b1 = (i + 1) * nu + j, (i + 1) * nu + (j + 1) % nu
            T += [(a0, b0, b1), (a0, b1, a1)]
    T = np.array(T)
    Q = P - np.array(HEAD_C)
    UVv = np.where(Q[:, 2:3] < 0.05, np.stack([0.5 - Q[:, 0] / 1.3, 0.5 - Q[:, 1] / 1.3], axis=1), [[0.01, 0.01]])
    UV = UVv[T]
    D = Dense(P, T, UV)
    D.orient(np.array(HEAD_C))
    return D


def face_texture(path):
    from PIL import Image, ImageDraw
    W = 1024
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    k = (20, 16, 14, 255)
    for cx in (0.415, 0.585):
        d.ellipse([(cx - 0.026) * W, (0.405 - 0.06) * W, (cx + 0.026) * W, (0.405 + 0.06) * W], fill=k)
    # smile: lower arc, thick, rounded ends
    cx, cy, r, w = 0.5, 0.47, 0.135, 0.022
    a0, a1 = 25, 155
    d.arc([(cx - r) * W, (cy - r) * W, (cx + r) * W, (cy + r) * W], a0, a1, fill=k, width=int(w * W))
    for a in (a0, a1):
        rr = r - w / 2
        px, py = cx + rr * math.cos(math.radians(a)), cy + rr * math.sin(math.radians(a))
        d.ellipse([(px - w / 2) * W, (py - w / 2) * W, (px + w / 2) * W, (py + w / 2) * W], fill=k)
    im = im.resize((512, 512), Image.LANCZOS)
    im.save(path)
    return path


# ------------------------------------------------------------------------------------------ Blender
def bpy_mesh(bpy, name, D, smooth=True, normals=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in D.P], [], [tuple(int(i) for i in t) for t in D.T])
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    uvd = np.empty((len(D.T) * 3, 2))
    uvd[:] = D.UV.reshape(-1, 2)
    uvd[:, 1] = 1 - uvd[:, 1]
    # loops follow polygon order for from_pydata triangles
    uvl.data.foreach_set("uv", uvd.ravel())
    if smooth:
        me.shade_smooth()
    if normals is not None:
        me.normals_split_custom_set_from_vertices([tuple(n) for n in normals])
    ob = bpy.data.objects.new(name, me)
    return ob


def mirror_lp(lp):
    P = lp["P"].copy()
    N = lp["N"].copy()
    P[:, 0] *= -1
    N[:, 0] *= -1
    return {"P": P, "N": N, "U": lp["U"].copy(), "T": lp["T"][:, ::-1].copy()}


def side_joint(part, side):
    return [j if j in ("Neck", "Waist", "Root") or j.startswith(("Right", "Left")) else side + j
            for j in PART_JOINTS[part]]


def build_tier(bpy, n):
    tr = TIERS[n]
    parts = {}
    for base, fn in BUILDERS.items():
        lp = fn(tr)
        if base in ("UpperTorso", "LowerTorso"):
            parts[base] = lp
        else:
            parts["Right" + base] = lp
            parts["Left" + base] = mirror_lp(lp)
    parts["_J"] = tier_joints(tr)
    return parts


def joint_pos(name, Jt):
    if name.endswith("Grip"):
        sg = 1 if name.startswith("Right") else -1
        return (Jt[name.replace("Grip", "Wrist")][0] - sg * 0.06, 1.98, 0.0)
    return Jt[name]


def export_tier(n, parts):
    outdir = os.path.join(OUT, "tier%d" % n)
    os.makedirs(outdir, exist_ok=True)
    rec = {}
    total = 0
    for name in PARTS:
        lp = parts[name]
        lo, hi = lp["P"].min(0), lp["P"].max(0)
        cen = (lo + hi) / 2
        pc = hl.Piece(name, "skin")
        pc.P = [tuple(float(x) for x in p) for p in lp["P"] - cen]
        pc.N = [tuple(float(x) for x in hl.norm(nn)) for nn in lp["N"]]
        pc.U = [(float(u), float(v)) for u, v in lp["U"]]
        pc.C = [(1.0, 1.0, 1.0, 1.0)] * len(pc.P)
        pc.T = [tuple(int(i) for i in t) for t in lp["T"]]
        fn = os.path.join(outdir, name + ".mesh")
        hl.write_mesh_v2(fn, pc)
        base = name.replace("Right", "").replace("Left", "")
        side = "Right" if name.startswith("Right") else ("Left" if name.startswith("Left") else "")
        atts = {}
        for jn in (side_joint(base, side) if side else PART_JOINTS[base]):
            p = np.array(joint_pos(jn, parts["_J"])) - cen
            atts[jn + ("RigAttachment" if not jn.endswith("Grip") else "Attachment")] = [round(float(x), 4) for x in p]
        rec[name] = {"mesh_file": name + ".mesh", "size": [round(float(x), 4) for x in hi - lo],
                     "rest_center": [round(float(x), 4) for x in cen],
                     "attachments": atts, "nv": pc.nv, "nt": pc.nt}
        total += pc.nt
    data = {"tier": n, "name": TIERS[n]["name"], "params": TIERS[n], "tris": total, "parts": rec}
    with open(os.path.join(outdir, "parts.json"), "w") as f:
        json.dump(data, f, indent=1)
    return data


# ------------------------------------------------------------------------------------------ posing
def M4(R=None, t=(0, 0, 0)):
    M = np.eye(4)
    if R is not None:
        M[:3, :3] = R
    M[:3, 3] = t
    return M


def about(p, R):
    p = np.asarray(p, float)
    return M4(None, p) @ M4(R) @ M4(None, -p)


def pose_mats(Jt=None, sh=5.0, el=7.0, hip=3.0, guard=False):
    """relaxed A-pose: arms out `sh` deg, elbows bent `el` deg forward, legs out `hip` deg.
    guard: upper arms raised forward 48 deg and swung in 38 deg, elbows bent 112 deg (fists by the chin)"""
    Jt = Jt or J
    M = {"UpperTorso": np.eye(4), "LowerTorso": np.eye(4), "Head": np.eye(4)}
    for side, sg in (("Right", 1), ("Left", -1)):
        if guard:
            ua = about(Jt[side + "Shoulder"], roty(sg * 38) @ rotx(48) @ rotz(sg * 4))
            la = ua @ about(Jt[side + "Elbow"], rotx(112) @ roty(-sg * 10))
            hd = la @ about(Jt[side + "Wrist"], rotx(15))
        else:
            ua = about(Jt[side + "Shoulder"], rotz(sg * sh))
            la = ua @ about(Jt[side + "Elbow"], rotx(el) @ rotz(sg * 3))
            hd = la @ about(Jt[side + "Wrist"], rotz(-sg * 4))
        ul = about(Jt[side + "Hip"], rotz(sg * hip))
        ll = ul
        ft = ll @ about(Jt[side + "Ankle"], rotz(-sg * hip))
        M.update({side + "UpperArm": ua, side + "LowerArm": la, side + "Hand": hd, side + "UpperLeg": ul,
                  side + "LowerLeg": ll, side + "Foot": ft})
    return M


# ------------------------------------------------------------------------------------------ rendering
SKIN = (0.36, 0.155, 0.072)  # linear; ~sRGB (162, 110, 76), a mid brown


class Stage:
    def __init__(self, bpy, res, samples):
        self.bpy = bpy
        bpy.ops.wm.read_factory_settings(use_empty=True)
        sc = bpy.context.scene
        self.sc = sc
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = samples
        sc.cycles.use_denoising = True
        sc.cycles.max_bounces = 4
        sc.render.resolution_x, sc.render.resolution_y = res
        sc.render.resolution_percentage = 100
        try:
            sc.view_settings.view_transform = "AgX"
        except TypeError:
            sc.view_settings.view_transform = "Filmic"
        w = bpy.data.worlds.new("w")
        sc.world = w
        w.use_nodes = True
        bg = w.node_tree.nodes["Background"]
        bg.inputs[0].default_value = (0.16, 0.18, 0.21, 1)
        bg.inputs[1].default_value = 0.9
        self.root = bpy.data.objects.new("root", None)  # game -> Blender (Y up -> Z up, face toward -Y)
        sc.collection.objects.link(self.root)
        self.root.rotation_euler = (math.pi / 2, 0, math.pi)
        self.coll = bpy.data.collections.new("Lineup")
        sc.collection.children.link(self.coll)
        self.skin = self.material("skin", SKIN)
        self.face_png = os.path.join(SCRATCH, "face_smile.png")
        face_texture(self.face_png)
        self.headmat = self.material("head", SKIN, self.face_png)
        self.floormat = self.material("floor", (0.30, 0.31, 0.33), rough=0.9)
        self._lights()
        cam = bpy.data.cameras.new("cam")
        cam.type = "ORTHO"
        self.cam = bpy.data.objects.new("cam", cam)
        sc.collection.objects.link(self.cam)
        sc.camera = self.cam

    def material(self, name, col, tex=None, rough=0.48):
        bpy = self.bpy
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bs = nt.nodes["Principled BSDF"]
        bs.inputs["Roughness"].default_value = rough
        bs.inputs["Specular IOR Level"].default_value = 0.45
        if tex:
            img = bpy.data.images.load(tex)
            tx = nt.nodes.new("ShaderNodeTexImage")
            tx.image = img
            tx.extension = "CLIP"
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.inputs[6].default_value = (*col, 1)
            nt.links.new(tx.outputs["Alpha"], mix.inputs[0])
            nt.links.new(tx.outputs["Color"], mix.inputs[7])
            nt.links.new(mix.outputs[2], bs.inputs["Base Color"])
        else:
            bs.inputs["Base Color"].default_value = (*col, 1)
        return m

    def _lights(self):
        bpy = self.bpy

        def sun(name, energy, rot_deg, color, angle=8):
            ld = bpy.data.lights.new(name, "SUN")
            ld.energy = energy
            ld.color = color
            ld.angle = math.radians(angle)
            ob = bpy.data.objects.new(name, ld)
            ob.rotation_euler = tuple(math.radians(a) for a in rot_deg)
            self.sc.collection.objects.link(ob)

        # Blender: camera at -Y looking +Y. Sun points along its local -Z.
        sun("key", 3.2, (55, 0, -32), (1.0, 0.95, 0.88), 6)
        sun("fill", 0.9, (70, 0, 50), (0.80, 0.87, 1.0), 20)
        sun("rim", 2.2, (-60, 0, -150), (0.92, 0.96, 1.0), 6)
        sun("rim2", 1.4, (-65, 0, 155), (1.0, 0.95, 0.9), 6)

    def add(self, name, lp, M, mat, D=None):
        if D is not None:
            P, N, T, UV = D.P, vnormals(D.P, D.T), D.T, D.UV
        else:
            P, N, T = lp["P"], lp["N"], lp["T"]
            UV = lp["U"][T]
        Ph = np.c_[P, np.ones(len(P))] @ M.T
        Nn = N @ M[:3, :3].T
        ob = bpy_mesh(self.bpy, name, Dense(Ph[:, :3], T, UV), normals=Nn)
        ob.data.materials.append(mat)
        ob.parent = self.root
        self.coll.objects.link(ob)
        return ob

    def figure(self, tag, parts, x, yaw=0.0, guard=False):
        place = M4(roty(yaw), (x, 0, 0))
        pm = pose_mats(parts.get("_J"), guard=guard)
        for name, lp in parts.items():
            if name.startswith("_"):
                continue
            self.add("%s_%s" % (tag, name), lp, place @ pm[name], self.skin)
        self.add(tag + "_Head", None, place, self.headmat, D=head_mesh())

    def floor(self, w=60):
        D = Dense(np.array([(-w, -0.002, -w), (w, -0.002, -w), (w, -0.002, w), (-w, -0.002, w)]),
                  np.array([(0, 2, 1), (0, 3, 2)]), np.zeros((2, 3, 2)))
        ob = bpy_mesh(self.bpy, "floor", D, smooth=False)
        ob.data.materials.append(self.floormat)
        ob.parent = self.root
        self.coll.objects.link(ob)

    def shoot(self, path, cx, cy, width, elev=4.0):
        bpy = self.bpy
        from mathutils import Vector
        bpy.context.view_layer.update()
        Mr = self.root.matrix_world
        a = math.radians(elev)
        f = np.array([cx, cy, 0.0])
        cg = f + np.array([0, math.sin(a), -math.cos(a)]) * 40
        cb, fb = Mr @ Vector(tuple(cg)), Mr @ Vector(tuple(f))
        self.cam.location = cb
        self.cam.rotation_mode = "QUATERNION"
        self.cam.rotation_quaternion = (fb - cb).to_track_quat("-Z", "Y")
        self.cam.data.ortho_scale = width
        self.cam.data.clip_end = 200
        self.sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        return path


def label(path, labels, title=None, strip=44):
    from PIL import Image, ImageDraw, ImageFont
    im = Image.open(path).convert("RGB")
    W, H = im.size
    top = 40 if title else 0
    out = Image.new("RGB", (W, H + strip + top), (26, 27, 30))
    out.paste(im, (0, top))
    d = ImageDraw.Draw(out)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 19)
    tfont = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 21)
    if title:
        d.text((14, 9), title, fill=(235, 235, 235), font=tfont)
    n = len(labels)
    for i, t in enumerate(labels):
        tw = d.textlength(t, font=font)
        d.text(((i + 0.5) * W / n - tw / 2, top + H + 11), t, fill=(215, 215, 215), font=font)
    out.save(path)
    return path


def render_sheets(bpy, tiers, which, samples):
    paths = []
    sp = 4.3
    if 1 in which:
        st = Stage(bpy, (1600, 700), samples)
        st.floor()
        for i, n in enumerate((1, 2, 3, 4, 5)):
            st.figure("T%d" % n, tiers[n], -(i - 2) * sp)  # game +X shows on the viewer's left
        p = st.shoot(os.path.join(SCRATCH, "lineup_front.png"), 0, 2.75, 5 * sp + 0.2, elev=3)
        label(p, ["1 lean", "2 toned", "3 athletic", "4 muscular", "5 elite"],
              "Muscle tiers on the standard R15 body (front, relaxed A-pose)")
        paths.append(p)
    if 2 in which:
        st = Stage(bpy, (1600, 700), samples)
        st.floor()
        # 3/4: the figure turned so the camera sees its front-right (yaw -35 deg about +Y)
        order = [(1, -38), (3, -38), (5, -38), (1, 180), (3, 180), (5, 180)]
        sp2 = 3.9
        for i, (n, yaw) in enumerate(order):
            st.figure("V%d_%d" % (i, n), tiers[n], -(i - 2.5) * sp2, yaw=yaw)
        p = st.shoot(os.path.join(SCRATCH, "views_34_back.png"), 0, 2.75, 6 * sp2 + 0.2, elev=6)
        label(p, ["1 lean 3/4", "3 athletic 3/4", "5 elite 3/4", "1 lean back", "3 athletic back", "5 elite back"],
              "Tiers 1 / 3 / 5: three-quarter and back views")
        paths.append(p)
    if 3 in which:
        st = Stage(bpy, (1600, 700), samples)
        st.floor()
        order = [(0, 0), (3, 0), (0, -38), (3, -38), (0, 180), (3, 180)]
        sp2 = 3.9
        for i, (n, yaw) in enumerate(order):
            st.figure("C%d_%d" % (i, n), tiers[n], -(i - 2.5) * sp2, yaw=yaw)
        p = st.shoot(os.path.join(SCRATCH, "compare_default_t3.png"), 0, 2.75, 6 * sp2 + 0.2, elev=5)
        label(p, ["default body", "tier 3 athletic", "default 3/4", "tier 3 3/4", "default back", "tier 3 back"],
              "Plain default-body reconstruction vs tier 3")
        paths.append(p)
    if 4 in which:
        st = Stage(bpy, (1600, 700), samples)
        st.floor()
        order = [(1, 0), (3, 0), (5, 0), (1, -38), (3, -38), (5, -38)]
        sp2 = 3.9
        for i, (n, yaw) in enumerate(order):
            st.figure("G%d_%d" % (i, n), tiers[n], -(i - 2.5) * sp2, yaw=yaw, guard=True)
        p = st.shoot(os.path.join(SCRATCH, "guard_pose.png"), 0, 2.75, 6 * sp2 + 0.2, elev=5)
        label(p, ["1 lean guard", "3 athletic guard", "5 elite guard", "1 lean 3/4", "3 athletic 3/4", "5 elite 3/4"],
              "Boxing guard check (upper arms forward 48 deg / in 38 deg, elbows 112 deg)")
        paths.append(p)
    return paths


def save_blend(bpy, tiers):
    """rest-pose parts per tier (part space = rest space) + the lineup, as the review .blend"""
    st = Stage(bpy, (1600, 700), 32)
    st.floor()
    for i, n in enumerate((1, 2, 3, 4, 5)):
        st.figure("T%d" % n, tiers[n], (i - 2) * 3.7)
    for n in sorted(tiers):
        c = bpy.data.collections.new("Tier%d_rest" % n)
        st.sc.collection.children.link(c)
        c.hide_render = True
        for name, lp in tiers[n].items():
            if name.startswith("_"):
                continue
            ob = bpy_mesh(bpy, "tier%d_%s" % (n, name), Dense(lp["P"], lp["T"], lp["U"][lp["T"]]), normals=lp["N"])
            ob.data.materials.append(st.skin)
            ob.parent = st.root
            ob.location = (0, 0, 0)
            c.objects.link(ob)
        c.hide_viewport = n != 3
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--samples", type=int, default=40)
    ap.add_argument("--sheets", default="1,2,3,4")
    ap.add_argument("--tiers", default="0,1,2,3,4,5")
    a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    import bpy
    os.makedirs(SCRATCH, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tiers, summary = {}, {}
    for n in (int(x) for x in a.tiers.split(",")):
        tiers[n] = build_tier(bpy, n)
        if n >= 1:
            d = export_tier(n, tiers[n])
            summary[n] = d
            print("tier %d %-9s %5d tris" % (n, d["name"], d["tris"]), {k: v["nt"] for k, v in d["parts"].items()
                                                                      if not k.startswith("Left")})
    if summary:
        with open(os.path.join(OUT, "body_tiers.json"), "w") as f:
            json.dump({"skeleton": {k: list(v) for k, v in J.items()},
                       "arm_axis_x": {str(n): round(arm_x(TIERS[n]), 4) for n in summary}, "head_center": HEAD_C,
                       "r15_block_reference": R15_BLOCK,
                       "tiers": {str(k): v for k, v in summary.items()}}, f, indent=1)
    if not a.no_render:
        for p in render_sheets(bpy, tiers, [int(x) for x in a.sheets.split(",")], a.samples):
            print("sheet", p)
    if all(n in tiers for n in (1, 2, 3, 4, 5)):
        save_blend(bpy, tiers)
        print("blend", BLEND)


if __name__ == "__main__":
    main()
