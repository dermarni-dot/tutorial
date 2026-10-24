"""THE LITE DETAIL SET (v9): the muscle-tier body builder as it was before the v10 detail pass (1536e0f^), kept so the
lite meshes (Config.Detail meshes "lite": crowd NPCs) can be rebuilt; run unchanged it reproduces the published v9
meshes byte for byte. Since v11 it takes the slim pass (SLIM / BULK / ARM_DX / dome) from ../build_body.py, so both
detail sets are slimmed the same way and share the joint pivots. Writes tools/body/out/lite/tier<N>/ +
tools/body/out/lite/body_tiers.json (no .blend; the sheets go to the scratch dir):
    /opt/bpyenv/bin/python tools/body/lite/build_body_v9.py --no-render --tiers 1,2,3,4,5
    /opt/bpyenv/bin/python tools/body/lite/build_gear_v9.py --no-render     # then the lite gear on these bodies
    /opt/bpyenv/bin/python tools/body/build_official.py --only lite         # and the officials' lite clothes

The v9 docstring follows.

Muscle-tier R15 body parts: the standard smooth Roblox R15 body with muscles added in 5 tiers (1 lean,
2 toned, 3 athletic, 4 muscular, 5 elite), at the game's athletic proportions (CONTRACT.md), plus a plain
"default body" reconstruction (tier 0) for comparison.

Run with Blender's Python (Cycles CPU renders); faces.py draws the face textures the renders use:
    python3 tools/body/faces.py
    /opt/bpyenv/bin/python tools/body/build_body.py                 # build + export + 5 sheets
    /opt/bpyenv/bin/python tools/body/build_body.py --no-render     # build + export only
    /opt/bpyenv/bin/python tools/body/build_body.py --samples 24 --sheets 1,4

Outputs
    tools/body/out/tier<N>/<Part>.mesh   Roblox mesh v2.00, vertices relative to the part's bbox centre
                                         (= the MeshPart origin Roblox gives an imported mesh)
    tools/body/out/tier<N>/parts.json    per part: size (bbox = OriginalSize), attachments (part space: every R15
                                         RigAttachment, the body accessory attachments, Grip on hands), tris;
                                         per tier: fit (gear girths / widths at fixed heights)
    tools/body/out/body_tiers.json       unit (the unscaled rig the meshes are modelled for) + all tiers
    tools/body/blend/body_tiers.blend    rest-pose parts per tier + the lineup scene
    <scratch>/lineup_front.png, views_34_back.png, compare_proportions_t3.png, guard_pose.png, faces_heads.png

Coordinates: game space, numerically (no axis conversion): studs, +X = the character's right, +Y up,
-Z forward. Each part is modelled on the R15 Classic Block rig's joint pivots (SKELETON below, the approved
prototype), then mapped into the game's proportions (game_joints / to_game: the Rthro blend x SLIM_W / SLIM_D the
game builds today), every part scaled about the joint it hangs from so the pivots stay shared. Feet on Y = 0.
Every part is its own closed shell. At a joint both neighbours carry the same
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
sys.path.insert(0, os.path.join(HERE, "..", "..", "hair"))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import hairlib as hl  # noqa: E402  (Piece, write_mesh_v2)
import build_body as v11  # noqa: E402  (the slim pass: SLIM, BULK, ARM_DX, Slim, dome)

OUT = os.path.join(HERE, "..", "out", "lite")
BLEND = None  # (the lite set saves no .blend)
SCRATCH = os.path.join(v11.SCRATCH, "lite")

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


# the shoulder pivot (v9): on the arm's own axis, where the upper arm's top dome is centred, a little under the R15
# height (the dome is a ball joint: it turns in place, never swinging out through the chest or up past the neck).
# The R15 position (x = +-1, Y_LT + 1.563) is kept as R15_SHOULDER: the elbow / wrist chain still hangs from it, so the
# arm's place and length stay what they were
YS_PIVOT = 3.53
R15_SHOULDER = (1.0, Y_LT + 1.563, 0.0)


def tier_joints(tr):
    Jt = dict(J)
    ax = arm_x(tr)
    for side, sg in (("Right", 1), ("Left", -1)):
        Jt[side + "Shoulder"] = (sg * ax, YS_PIVOT, 0.0)
        for jn in ("Elbow", "Wrist"):
            x, y, z = J[side + jn]
            Jt[side + jn] = (sg * ax, y, z)
        # the hand's grip point: palm centre, a little inside the wrist axis
        Jt[side + "Grip"] = (sg * (ax - 0.06), 1.98, 0.0)
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

# ------------------------------------------------------------------------------------------ game proportions
# Every part is modelled above on the Classic R15 block skeleton (the approved prototype's style), then mapped
# into the game's proportions: the athletic rig Builder.Scales builds for a 70-inch Athletic man today = the
# engine's Classic -> Rthro part factors at BodyTypeScale 1 (ProportionScale 0) x SLIM_W / SLIM_D (Width /
# Depth) x Height 1. Each part is scaled about the joint it hangs from (as the engine scales a part and its
# attachments) and the joints are chained from the root, so every joint pivot stays exactly shared. The game
# then applies the description with BodyTypeScale = 0 / ProportionScale = 0 and only Height / Width / Depth /
# Head scales: Width 1 / Depth 1 / Height 1 reproduce this rig.
RTHRO = {  # Classic -> Rthro Normal (x, y, z) per part, the engine's scaling at BodyTypeScale 1
    "UpperTorso": (1.033, 1.309, 1.140), "LowerTorso": (1.033, 1.309, 1.140),
    "UpperArm": (1.129, 1.342, 1.132), "LowerArm": (1.129, 1.342, 1.132), "Hand": (1.066, 1.174, 1.231),
    "UpperLeg": (1.023, 1.506, 1.023), "LowerLeg": (1.023, 1.506, 1.023), "Foot": (1.079, 1.267, 1.129),
    "Head": (0.942, 0.942, 0.942),
}
SLIM_W, SLIM_D = 0.77, 0.84         # Builder.lua
HEAD_FRAME = 0.82                   # Builder FRAME_PROPORTIONS.Athletic.head
HEAD_SIZE = 1.2 * HEAD_FRAME * RTHRO["Head"][0]  # 0.927: today's head; the game's HeadScale = 0.82 x 0.942
ANCHOR = {"UpperTorso": "Waist", "LowerTorso": "Root", "UpperArm": "Elbow", "LowerArm": "Elbow",
          "Hand": "Wrist", "UpperLeg": "Hip", "LowerLeg": "Knee", "Foot": "Ankle"}
# per tier: the arm axis' extra x in game space so the upper arm's inner side rests on the torso's side
# (the arm fix, re-measured at the new proportions; see arm_gap() in the build log)
ARM_DX = v11.ARM_DX  # (v11 slim pass: the arm axis comes in with the slimmer torso)


def game_scale(base):
    rx, ry, rz = RTHRO[base]
    return np.array([rx * SLIM_W, ry, rz * SLIM_D])


def game_joints(tr, n=None):
    """prototype joints -> game rest space (feet on Y = 0): chained from the root, each segment scaled by the
    part it lies in. Returns (G, Jo): game joints, prototype joints (both with Left / Right / Grip)."""
    Jo = {k: np.array(v, float) for k, v in tier_joints(tr).items()}
    ST, SA, SH = game_scale("UpperTorso"), game_scale("UpperArm"), game_scale("Hand")
    SL, SF = game_scale("UpperLeg"), game_scale("Foot")
    G = {"Root": np.zeros(3)}
    r = Jo["Root"]
    for k in ("Waist", "Neck"):
        G[k] = ST * (Jo[k] - r)
    dx = ARM_DX.get(n, 0.0) if n is not None else 0.0
    for side, sg in (("Right", 1), ("Left", -1)):
        G[side + "Hip"] = ST * (Jo[side + "Hip"] - r)
        G[side + "Knee"] = G[side + "Hip"] + SL * (Jo[side + "Knee"] - Jo[side + "Hip"])
        G[side + "Ankle"] = G[side + "Knee"] + SL * (Jo[side + "Ankle"] - Jo[side + "Knee"])
        s15 = np.array([sg * R15_SHOULDER[0], R15_SHOULDER[1], R15_SHOULDER[2]])
        G[side + "Elbow"] = ST * (s15 - r) + SA * (Jo[side + "Elbow"] - s15)
        G[side + "Elbow"][0] += sg * dx
        G[side + "Wrist"] = G[side + "Elbow"] + SA * (Jo[side + "Wrist"] - Jo[side + "Elbow"])
        G[side + "Grip"] = G[side + "Wrist"] + SH * (Jo[side + "Grip"] - Jo[side + "Wrist"])
        # the shoulder pivot on the arm's axis (the upper arm is mapped about the elbow: this is where its dome lands)
        G[side + "Shoulder"] = G[side + "Elbow"] + SA * (Jo[side + "Shoulder"] - Jo[side + "Elbow"])
    floor = G["RightAnkle"][1] - SF[1] * Jo["RightAnkle"][1]  # the foot's sole is at prototype Y = 0
    for k in G:
        G[k] = G[k] - np.array([0.0, floor, 0.0])
    return G, Jo


def to_game(lp, base, key, Jo, G):
    """maps one prototype part into game space about its anchor joint `key`; normals by the inverse transpose"""
    S = game_scale(base)
    P = G[key] + (lp["P"] - Jo[key]) * S
    N = lp["N"] / S
    N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    return {"P": P, "N": N, "U": lp["U"], "T": lp["T"]}


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
    # (v11 slim) the muscle bells' mass term is cut to BULK, as the full set's
    return f * tr["f"] + m * tr["m"] * (v11.BULK if m > 0 else 1.0) + d * tr["d"]


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


# ------------------------------------------------------------------------------------------ joints
# the height (prototype units along the bone) of the domes that close each limb part at a joint. Every dome is a
# near-sphere ABOUT ITS PIVOT in game space (height x the part's game Y scale ~ its game radius there), so turning
# the joint turns the dome in place: nothing swings out through the neighbour (the v8 domes reached 1.5-2 radii past
# the pivot and showed through the seat, the back of the knee, the elbow and the chest on every step and punch).
# shoulder: 0.30 / 1.342 (upper arm Y scale); elbow 0.26 / 1.342; wrist 0.155 / 1.342; hip 0.35 / 1.506 (upper
# leg); knee 0.25 / 1.506
JOINT_DOME = {"shoulder": 0.224, "elbow": 0.194, "wrist": 0.115, "hip": 0.232, "knee": 0.166}


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
    return loft(v11.Slim(torso_prof(), "Torso"), tr["m"], YW, 3.54, (0.22, 1.0, 2, 0.88), (0.33, 0.85, 6), nb=22, nseg=30, bias=0.5,
                sdens=sd, bumps=sym(b))


def lower_torso(tr):
    b = [
        Bp((0.36, 1.99, 0.30), (0.34, 0.36, 0.17, 0.24, 0.30, 0.36), amp(tr, 0.03, 0.06, 0.0)),  # glutes
        Bp((0.0, 2.10, -0.42), (0.22, 0.22, 0.14, 0.10, 0.3, 0.3), amp(tr, 0.0, 0.012, 0.01)),  # lower abs
        Bp((0.0, 2.0, 0.45), (0.04, 0.04, 0.17, 0.15, 0.3, 0.3), amp(tr, -0.015, -0.01, 0.0)),  # cleft
    ]
    # the child of the waist joint: a touch thinner near it so the UpperTorso's dome dives cleanly under
    return loft(v11.Slim(torso_prof(), "Torso"), tr["m"], 1.82, 2.30, (0.26, 1.0, 5, 0.9), (0.18, 1.0, 2), nb=7, nseg=24, bias=0.2,
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
        Bp((X - 0.17, 3.58, 0.0), (0.18, 0.22, 0.24, 0.16, 0.34, 0.34), amp(tr, 0.01, 0.025, 0.0)),  # delt wrap over the shoulder
        Bp((X - 0.02, 3.48, 0.20), (0.26, 0.24, 0.30, 0.25, 0.25, 0.20), amp(tr, 0.0, 0.035, 0.0)),  # rear delt
        Bp((X, 3.08, -0.22), (0.24, 0.24, 0.22, 0.32, 0.26, 0.26), amp(tr, 0.008, 0.08, 0.008)),  # biceps
        Bp((X + 0.04, 3.20, 0.22), (0.20, 0.24, 0.30, 0.24, 0.25, 0.25), amp(tr, 0.008, 0.075, 0.005)),  # triceps
        Bp((X + 0.22, 3.22, 0.0), (0.06, 0.08, 0.10, 0.08, 0.25, 0.25), amp(tr, 0, 0, -0.008)),  # delt insertion
    ]
    # (both ends are ball joints: the elbow dome and the shoulder dome are near-spheres about their pivots in game
    # space - JOINT_DOME - so the arm turns in place at both)
    return loft(v11.Slim(pr, "UpperArm"), tr["m"], YE, YS_PIVOT, (v11.dome("elbow", "UpperArm", YE, tr), 1.0, 2, 0.88),
                (v11.dome("shoulder", "UpperArm", YS_PIVOT, tr), 1.0, 4), nb=8,
                nseg=16, frame=VERT(X), bumps=b)


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
    return loft(v11.Slim(pr, "LowerArm"), tr["m"], YWR, YE, (v11.dome("wrist", "LowerArm", YWR, tr), 1.0, 2, 0.9),
                (v11.dome("elbow", "LowerArm", YE, tr), 1.0, 2), nb=8, nseg=14,
                frame=VERT(X), shrink=[(YE, 0.10, 0.06)], bumps=b)


def hand(tr):
    X = arm_x(tr)
    # (the back of the hand narrows into the wrist, a little thinner than the forearm's tucked rim there, so the seam
    # is the forearm's clean ring, never the two surfaces crossing)
    pr = Prof([1.93, 2.05, YWR],
              ax=([0.135, 0.165, 0.132], [0.01, 0.01, 0.006]),
              af=([0.215, 0.212, 0.158], [0.01, 0.01, 0.004]),
              p=[3.0, 3.0, 2.4], cx=[-0.02, 0.0, 0.0])
    shells = [loft(pr, tr["m"], 1.93, YWR, (0.06, 1.0, 2), (0.12, 1.0, 2), nb=4, nseg=12, frame=VERT(X))]
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
    # (the top is a ball joint centred on the hip pivot - JOINT_DOME: the thigh turns inside the pelvis without its
    # top swinging out through the seat; the knee end the same)
    return loft(v11.Slim(pr, "UpperLeg"), tr["m"], YK, YH, (v11.dome("knee", "UpperLeg", YK, tr), 1.0, 2, 0.88),
                (v11.dome("hip", "UpperLeg", YH, tr), 1.0, 3), nb=10, nseg=14,
                frame=VERT(X), shrink=[(YH, 0.16, 0.06)], bumps=b)


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
    return loft(v11.Slim(pr, "LowerLeg"), tr["m"], YA, YK, (0.18, 1.0, 3), (v11.dome("knee", "LowerLeg", YK, tr), 1.0, 2),
                nb=8, nseg=14, frame=VERT(X),
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


def head_mesh(center=None, size=1.2):
    """a classic Roblox-style head: rounded cylinder-block (1.2 studs nominal, scaled to `size`), planar face UVs
    across the whole front (like a Decal on the head's Front face)"""
    HC = np.array(center if center is not None else HEAD_C, float)
    k = size / 1.2
    a, b, c = 0.6 * k, 0.6 * k, 0.58 * k
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
    P = np.array(P) + HC
    T = []
    for i in range(nv):
        for j in range(nu):
            a0, b0 = i * nu + j, i * nu + (j + 1) % nu
            a1, b1 = (i + 1) * nu + j, (i + 1) * nu + (j + 1) % nu
            T += [(a0, b0, b1), (a0, b1, a1)]
    T = np.array(T)
    Q = (P - HC) / k
    UVv = np.where(Q[:, 2:3] < 0.05, np.stack([0.5 - Q[:, 0] / 1.2, 0.5 - Q[:, 1] / 1.2], axis=1), [[0.002, 0.002]])
    UV = UVv[T]
    D = Dense(P, T, UV)
    D.orient(HC)
    return D


FACES_DIR = os.path.join(OUT, "faces")


def face_png(key):
    """tools/body/out/faces/face_<key>.png (faces.py draws any that are missing)"""
    p = os.path.join(FACES_DIR, "face_%s.png" % key)
    if not os.path.exists(p):
        import faces
        f = faces.Face()
        faces.DRAW[key](f)
        os.makedirs(FACES_DIR, exist_ok=True)
        f.save(p)
    return p


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


def build_tier(bpy, n, proto=False):
    """the tier's 14 parts in game rest space (feet on Y = 0) + "_J" (game joints) / "_J0" (prototype joints).
    proto=True keeps the prototype's Classic block proportions (comparison renders only)"""
    tr = TIERS[n]
    G, Jo = game_joints(tr, n)
    if proto:
        G = Jo
    parts = {}
    for base, fn in BUILDERS.items():
        lp = fn(tr)
        if base in ("UpperTorso", "LowerTorso"):
            parts[base] = lp if proto else to_game(lp, base, ANCHOR[base], Jo, G)
        else:
            lp = lp if proto else to_game(lp, base, "Right" + ANCHOR[base], Jo, G)
            parts["Right" + base] = lp
            parts["Left" + base] = mirror_lp(lp)
    parts["_J"] = {k: tuple(float(x) for x in v) for k, v in G.items()}
    parts["_J0"] = {k: tuple(float(x) for x in v) for k, v in Jo.items()}
    return parts


def joint_pos(name, Jt):
    return Jt[name]


def raycast(lp, o, d):
    """distance along d from o to the nearest hit on the part's triangles (Moller-Trumbore), None if missed"""
    P, T = lp["P"], lp["T"]
    o, d = np.asarray(o, float), np.asarray(d, float)
    v0, v1, v2 = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    pv = np.cross(d, e2)
    det = np.einsum("ij,ij->i", e1, pv)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    tv = o - v0
    u = np.einsum("ij,ij->i", tv, pv) * inv
    qv = np.cross(tv, e1)
    v = (qv @ d) * inv
    t = np.einsum("ij,ij->i", e2, qv) * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    return float(t[hit].min()) if hit.any() else None


def surface(lp, x, y, z, d):
    """the surface point hit from far outside along direction d through (x, y, z)"""
    d = np.asarray(d, float)
    o = np.array([x, y, z], float) - d * 10
    t = raycast(lp, o, d)
    return o + d * t if t is not None else np.array([x, y, z], float)


# accessory attachments (rest space) per part: the body accessory points Roblox's R15 rig carries
def accessory_points(name, lp, Jt):
    side = "Right" if name.startswith("Right") else ("Left" if name.startswith("Left") else "")
    sg = -1 if side == "Left" else 1
    out = {}
    if name == "UpperTorso":
        yc = (Jt["Waist"][1] + Jt["Neck"][1]) / 2  # the UpperTorso box centre (the default's BodyFront height)
        out["BodyFrontAttachment"] = surface(lp, 0, yc, 0, (0, 0, 1))
        out["BodyBackAttachment"] = surface(lp, 0, yc, 0, (0, 0, -1))
        out["NeckAttachment"] = np.array(Jt["Neck"], float)
        c = surface(lp, Jt["RightShoulder"][0] * 0.82, 0, 0, (0, -1, 0))
        out["RightCollarAttachment"] = c
        out["LeftCollarAttachment"] = c * np.array([-1.0, 1.0, 1.0])
    elif name == "LowerTorso":
        y = Jt["Root"][1]
        out["WaistCenterAttachment"] = np.array(Jt["Root"], float)
        out["WaistFrontAttachment"] = surface(lp, 0, y, 0, (0, 0, 1))
        out["WaistBackAttachment"] = surface(lp, 0, y, 0, (0, 0, -1))
    elif name.endswith("UpperArm"):
        out[side + "ShoulderAttachment"] = surface(lp, Jt[side + "Elbow"][0], 0, 0, (0, -1, 0))
    elif name.endswith("Foot"):
        a = Jt[side + "Ankle"]
        out[side + "FootAttachment"] = np.array([a[0], float(lp["P"][:, 1].min()), a[2]])
    return out


def section(lp, y):
    """the convex hull of the part's cross-section at height y: (perimeter, width x, depth z)"""
    P, T = lp["P"], lp["T"]
    pts = []
    for a, b in ((0, 1), (1, 2), (2, 0)):
        pa, pb = P[T[:, a]], P[T[:, b]]
        m = (pa[:, 1] - y) * (pb[:, 1] - y) < 0
        t = (y - pa[m, 1]) / (pb[m, 1] - pa[m, 1])
        q = pa[m] + (pb[m] - pa[m]) * t[:, None]
        pts.append(q[:, [0, 2]])
    Q = np.unique(np.round(np.vstack(pts), 6), axis=0)
    if len(Q) < 3:
        return 0.0, 0.0, 0.0
    Q = Q[np.lexsort((Q[:, 1], Q[:, 0]))]

    def half(R):
        h = []
        for p in R:
            while len(h) >= 2 and ((h[-1][0] - h[-2][0]) * (p[1] - h[-2][1])
                                   - (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0])) <= 0:
                h.pop()
            h.append(p)
        return h
    hull = half(Q)[:-1] + half(Q[::-1])[:-1]
    H = np.array(hull)
    per = float(np.linalg.norm(np.roll(H, -1, axis=0) - H, axis=1).sum())
    return per, float(np.ptp(Q[:, 0])), float(np.ptp(Q[:, 1]))


def proto_y(part_base, y0, parts):
    """a prototype height on one part -> game height (that part's mapping)"""
    G, Jo = parts["_J"], parts["_J0"]
    key = ANCHOR[part_base] if part_base in ("UpperTorso", "LowerTorso") else "Right" + ANCHOR[part_base]
    return G[key][1] + (y0 - Jo[key][1]) * game_scale(part_base)[1]


# gear fit: girths (convex hull, studs) at fixed anatomical heights, from the prototype's muscle centres
FIT_AT = {
    "chest": ("UpperTorso", 3.23), "waist": ("UpperTorso", 2.42), "hips": ("LowerTorso", 1.99),
    "upperArm": ("UpperArm", 3.10), "forearm": ("LowerArm", 2.62), "wrist": ("LowerArm", 2.22),
    "thigh": ("UpperLeg", 1.45), "knee": ("UpperLeg", 1.05), "calf": ("LowerLeg", 0.72), "ankle": ("LowerLeg", 0.40),
}


def fit_sizes(parts):
    out = {}
    for k, (base, y0) in FIT_AT.items():
        name = base if base in ("UpperTorso", "LowerTorso") else "Right" + base
        y = proto_y(base, y0, parts)
        per, w, d = section(parts[name], y)
        out[k] = {"y": round(float(y), 3), "girth": round(per, 3), "width": round(w, 3), "depth": round(d, 3)}
    # silhouette widths: shoulders (outside of both delts), the whole body's widest point
    ua = parts["RightUpperArm"]["P"]
    out["shoulderSpan"] = round(2 * float(ua[:, 0].max()), 3)
    out["chestDepth"] = round(float(np.ptp(parts["UpperTorso"]["P"][:, 2])), 3)
    return out


def export_tier(n, parts):
    outdir = os.path.join(OUT, "tier%d" % n)
    os.makedirs(outdir, exist_ok=True)
    rec = {}
    total = 0
    Jt = parts["_J"]
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
            p = np.array(joint_pos(jn, Jt)) - cen
            atts[jn + ("RigAttachment" if not jn.endswith("Grip") else "Attachment")] = [round(float(x), 4) for x in p]
        for an, p in accessory_points(name, lp, Jt).items():
            atts[an] = [round(float(x), 4) for x in (np.asarray(p) - cen)]
        rec[name] = {"mesh_file": name + ".mesh", "size": [round(float(x), 4) for x in hi - lo],
                     "rest_center": [round(float(x), 4) for x in cen],
                     "attachments": atts, "nv": pc.nv, "nt": pc.nt}
        total += pc.nt
    data = {"tier": n, "name": TIERS[n]["name"], "params": TIERS[n], "tris": total, "fit": fit_sizes(parts),
            "parts": rec}
    with open(os.path.join(outdir, "parts.json"), "w") as f:
        json.dump(data, f, indent=1)
    return data


def unit_rig(tiers):
    """the unscaled rig the meshes are modelled for (game rest space, studs, feet on Y = 0, -Z forward)"""
    G = tiers[3]["_J"]
    box = {"UpperTorso": (2, 1.6, 1), "LowerTorso": (2, 0.4, 1), "UpperArm": (1, 1.169, 1), "LowerArm": (1, 1.052, 1),
           "Hand": (1, 0.3, 1), "UpperLeg": (1, 1.217, 1), "LowerLeg": (1, 1.193, 1), "Foot": (1, 0.3, 1)}
    j = {k: [round(float(x), 4) for x in v] for k, v in G.items() if not k.startswith("Left")}
    return {
        "description": {"BodyTypeScale": 0, "ProportionScale": 0, "HeightScale": 1, "WidthScale": 1,
                        "DepthScale": 1, "HeadScale": round(HEAD_FRAME * RTHRO["Head"][0], 4)},
        "basis": "R15 Classic block x Rthro(BodyTypeScale 1) x (SLIM_W %.2f, 1, SLIM_D %.2f): Builder.Scales' "
                 "70-inch Athletic man" % (SLIM_W, SLIM_D),
        "partScale": {k: [round(float(x), 4) for x in game_scale(k)] for k in box},
        "rigBox": {k: [round(float(a * b), 4) for a, b in zip(box[k], game_scale(k))] for k in box},
        "head": round(HEAD_SIZE, 4),
        "joints": j,
        "armAxisX": {str(n): round(float(tiers[n]["_J"]["RightElbow"][0]), 4) for n in sorted(tiers) if n >= 1},
        "rootHeight": round(float(G["Root"][1]), 4),
        "hipHeight": round(float(G["RightHip"][1]), 4),
        "neckHeight": round(float(G["Neck"][1]), 4),
        "shoulderHeight": round(float(G["RightShoulder"][1]), 4),
        "wristHeight": round(float(G["RightWrist"][1]), 4),
        "standingHeight": round(float(G["Neck"][1] + HEAD_SIZE), 4),
    }


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
        self.headmats = {}
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

    def headmat(self, face):
        if face not in self.headmats:
            self.headmats[face] = self.material("head_" + face, SKIN, face_png(face))
        return self.headmats[face]

    def figure(self, tag, parts, x, yaw=0.0, guard=False, face="smile", z=0.0, only=None):
        place = M4(roty(yaw), (x, 0, z))
        pm = pose_mats(parts.get("_J"), guard=guard)
        for name, lp in parts.items():
            if name.startswith("_") or (only and name not in only):
                continue
            self.add("%s_%s" % (tag, name), lp, place @ pm[name], self.skin)
        # the classic head sits on the neck pivot (no neck lift), at today's head size
        neck = np.array(parts["_J"]["Neck"])
        self.add(tag + "_Head", None, place, self.headmat(face),
                 D=head_mesh(neck + np.array([0, HEAD_SIZE / 2, 0]), HEAD_SIZE))

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
    CY = 3.25  # frame centre height (a 70-inch boxer stands ~6.2 studs)
    if 1 in which:
        st = Stage(bpy, (1600, 800), samples)
        st.floor()
        sp = 3.4
        faces = ("smile", "confident", "determined", "grin", "focused")
        for i, n in enumerate((1, 2, 3, 4, 5)):
            st.figure("T%d" % n, tiers[n], -(i - 2) * sp, face=faces[i])  # game +X shows on the viewer's left
        p = st.shoot(os.path.join(SCRATCH, "lineup_front.png"), 0, CY, 5 * sp + 0.4, elev=3)
        label(p, ["1 lean / smile", "2 toned / confident", "3 athletic / determined", "4 muscular / grin",
                  "5 elite / focused"], "Muscle tiers at the game's athletic proportions (front, relaxed A-pose)")
        paths.append(p)
    if 2 in which:
        st = Stage(bpy, (1600, 800), samples)
        st.floor()
        order = [(1, -38, "smirk"), (3, -38, "cool"), (5, -38, "stern"), (1, 180, "smile"), (3, 180, "smile"),
                 (5, 180, "smile")]
        sp2 = 3.1
        for i, (n, yaw, fc) in enumerate(order):
            st.figure("V%d_%d" % (i, n), tiers[n], -(i - 2.5) * sp2, yaw=yaw, face=fc)
        p = st.shoot(os.path.join(SCRATCH, "views_34_back.png"), 0, CY, 6 * sp2 + 0.3, elev=6)
        label(p, ["1 lean 3/4", "3 athletic 3/4", "5 elite 3/4", "1 lean back", "3 athletic back", "5 elite back"],
              "Tiers 1 / 3 / 5: three-quarter and back views")
        paths.append(p)
    if 3 in which:
        st = Stage(bpy, (1600, 800), samples)
        st.floor()
        old = build_tier(bpy, 3, proto=True)
        order = [(old, 0), (tiers[3], 0), (old, -38), (tiers[3], -38), (old, 90), (tiers[3], 90)]
        sp2 = 3.1
        for i, (pt, yaw) in enumerate(order):
            st.figure("C%d" % i, pt, -(i - 2.5) * sp2, yaw=yaw)
        p = st.shoot(os.path.join(SCRATCH, "compare_proportions_t3.png"), 0, CY, 6 * sp2 + 0.3, elev=5)
        label(p, ["prototype (Classic)", "game proportions", "prototype 3/4", "game 3/4", "prototype side",
                  "game side"], "Tier 3: the prototype's Classic block proportions vs the game's athletic rig")
        paths.append(p)
    if 4 in which:
        st = Stage(bpy, (1600, 800), samples)
        st.floor()
        order = [(1, 0, "focused"), (3, 0, "determined"), (5, 0, "grit"), (1, -38, "focused"), (3, -38, "determined"),
                 (5, -38, "grit")]
        sp2 = 3.1
        for i, (n, yaw, fc) in enumerate(order):
            st.figure("G%d_%d" % (i, n), tiers[n], -(i - 2.5) * sp2, yaw=yaw, guard=True, face=fc)
        p = st.shoot(os.path.join(SCRATCH, "guard_pose.png"), 0, CY, 6 * sp2 + 0.3, elev=5)
        label(p, ["1 lean guard", "3 athletic guard", "5 elite guard", "1 lean 3/4", "3 athletic 3/4", "5 elite 3/4"],
              "Boxing guard check (upper arms forward 48 deg / in 38 deg, elbows 112 deg)")
        paths.append(p)
    if 5 in which:
        st = Stage(bpy, (1800, 560), samples)
        faces = ("smile", "grin", "determined", "grit", "hurt", "dazed", "ko")
        sp2 = 1.95
        for i, fc in enumerate(faces):
            st.figure("F%d" % i, tiers[3], -(i - 3) * sp2, face=fc, only=("UpperTorso",))
        p = st.shoot(os.path.join(SCRATCH, "faces_heads.png"), 0, 5.15, 7 * sp2 + 0.1, elev=4)
        label(p, list(faces), "Classic head (0.927 studs) wearing the faces, tier 3")
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
    ap.add_argument("--sheets", default="1,2,3,4,5")
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
        unit = unit_rig(tiers)
        with open(os.path.join(OUT, "body_tiers.json"), "w") as f:
            json.dump({"unit": unit, "prototype_skeleton": {k: list(v) for k, v in J.items()},
                       "r15_block_reference": R15_BLOCK,
                       "tiers": {str(k): v for k, v in summary.items()}}, f, indent=1)
        print("unit", json.dumps({k: unit[k] for k in ("rootHeight", "hipHeight", "shoulderHeight", "neckHeight",
                                                       "standingHeight", "armAxisX")}))
    if not a.no_render:
        for p in render_sheets(bpy, tiers, [int(x) for x in a.sheets.split(",")], a.samples):
            print("sheet", p)
    # (the lite set saves no .blend)


if __name__ == "__main__":
    main()
