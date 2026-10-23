"""Frame x muscle-tier R15 body parts (v12): five body FRAMES (Config.BodyTypes: Lean, Athletic, Muscular, Power Build,
Heavyweight Build), each in 5 muscle tiers (1 lean, 2 toned, 3 athletic, 4 muscular, 5 elite), at the game's
proportions (CONTRACT.md), plus a plain "default body" reconstruction (tier 0) for comparison.

Run with Blender's Python (Cycles CPU renders); faces.py draws the face textures the renders use:
    python3 tools/body/faces.py
    /opt/bpyenv/bin/python tools/body/build_body.py                 # build + export every frame + sheets
    /opt/bpyenv/bin/python tools/body/build_body.py --no-render     # build + export only
    /opt/bpyenv/bin/python tools/body/build_body.py --frames lean,power --tiers 1,5 --sheets frames --samples 24

Outputs
    tools/body/out/tier<N>/<Part>.mesh                 the Athletic frame (the default family: what BodyAssetData.tiers
                                                       carries, what the gear is fitted on), Roblox mesh v2.00, vertices
                                                       relative to the part's bbox centre
    tools/body/out/tier<N>/parts.json                  per part: size (bbox = OriginalSize), attachments (part space:
                                                       every R15 RigAttachment, the body accessory attachments, Grip on
                                                       hands), tris; per tier: fit (gear girths / widths at fixed heights)
    tools/body/out/frames/<frame>/tier<N>/...          the other four frames (lean, muscular, power, heavy), the same files
    tools/body/out/body_tiers.json                     unit (the unscaled rig the meshes are modelled for) + all tiers + frames
    tools/body/blend/body_tiers.blend                  rest-pose parts per tier + the lineup scene (Athletic)
    <scratch>/frames_t<N>_<view>.png, lineup_front.png, views_34_back.png, guard_pose.png, faces_heads.png

Coordinates: game space, numerically (no axis conversion): studs, +X = the character's right, +Y up,
-Z forward. Each part is modelled on the R15 Classic Block rig's joint pivots (SKELETON below, the approved
prototype), then mapped into the game's proportions (game_joints / to_game: the Rthro blend x SLIM_W / SLIM_D the
game builds today), every part scaled about the joint it hangs from so the pivots stay shared. Feet on Y = 0.
Every part is its own closed shell. At a joint both neighbours carry the same cross-section and end in a dome
centred on the pivot (a near-sphere in game space), so each part's rounded end hides inside its neighbour and no
gap opens when a joint turns.

Modelling (v12): each part is a low-res loft (super-elliptic rings along the bone, domed ends) whose vertices are
exactly every 4th vertex of a refined loft. The MUSCLES are a smooth displacement field over the loft's own
parameter plane (height along the bone s, azimuth round the bone): every muscle is a lobe with a longitudinal
envelope (where its belly sits, how it tapers toward its tendons) and an angular lobe (where it sits round the limb
and how far it wraps), added to the ring radius before the ring is placed. Neighbouring lobes overlap and sum, so
the deltoid wraps over the biceps / triceps origins, the pec plate runs into the front delt, the lats widen the back
toward the armpit, the forearm mass sits toward the elbow: the cross-section itself changes shape along the bone
(no ellipsoid bumps glued onto a tube). Narrow negative lobes are the separations (sternum, linea alba, the
deltopectoral line, biceps / triceps). The refined surface's normals are what the low-res mesh carries (Roblox
meshes store per-vertex normals), so the forms read at game triangle counts with clean quad topology. Bony
landmarks (knuckles, ankle bones, kneecap) stay small local bumps (bell).

Frames: the FRAMES table. The silhouette lives in the base profiles (the ribcage's width and depth, the shoulder
top, the trapezius slope into a real neck column, the arm and calf girths) and in the arm axis: the shoulder pivot
sits where the frame's upper arm rests against the frame's torso (arm_x), so a Lean frame's shoulders are narrow
and a Power frame's wide, whatever the HumanoidDescription scales. The gear is fitted on the Athletic frame
(build_gear.py): under the trunks (the LowerTorso, the UpperTorso's hem, the thighs) and at the wrist and ankle
every frame keeps the Athletic (legacy v11) section, so the band, seat, shorts legs, gloves, wraps and boots fit
every frame; the frame's own mass is carried by the HumanoidDescription Width / Depth (Config.BodyTypes).
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
ARM_X, LEG_X = 1.5, 0.5  # ARM_X: the R15 Block arm axis (reference only; the frames use arm_x below)

# the shoulder pivot (v9): on the arm's own axis, where the upper arm's top dome is centred, a little under the R15
# height (the dome is a ball joint: it turns in place, never swinging out through the chest or up past the neck).
# The R15 position (x = +-1, Y_LT + 1.563) is kept as R15_SHOULDER: the elbow / wrist chain still hangs from it, so the
# arm's place and length stay what they were
YS_PIVOT = 3.53
R15_SHOULDER = (1.0, Y_LT + 1.563, 0.0)

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

# ------------------------------------------------------------------------------------------ frames
# One entry per Config.BodyTypes id. key = the out/frames/<key> folder (Athletic is out/tier<N>, the default family).
# Torso rows are multipliers on the legacy (v11 Athletic) section at the UpperTorso knots s = 2.45, 2.75, 3.05, 3.30,
# 3.48, 3.58 (prototype heights: the hem row 2.45 must stay <= 1: the trunks' band is hulled on it); neck = (ax, af,
# ab) at s = 3.66 (the trapezius slope), 3.74 and 3.84 (the neck column, which enters the head at 3.811); arm / fore /
# calf = girth multipliers along those bones (1 at the elbow row's neighbour, the wrist and the ankle); p = the torso's
# super-ellipse exponent shift (rounder < 0 < blockier); gain = the muscle lobes' mass / definition gains per group;
# soft = a subcutaneous layer (rounds the forms: the heavyweight).
FRAMES = {
    "Lean": dict(
        key="lean",
        skel=dict(torso=1.02, leg=1.08, lowerleg=1.10, arm=1.03, forearm=1.08, armw=0.92, hand=0.90, lower=(0.90, 0.92), foot=0.90),
        tx=[0.95, 0.90, 0.92, 0.93, 0.92, 0.90], tf=[0.95, 0.90, 0.93, 0.95, 0.96, 0.98], tb=[0.95, 0.92, 0.95, 0.96, 0.97, 0.98],
        neck=([0.58, 0.38, 0.36], [0.28, 0.25, 0.25], [0.30, 0.28, 0.28]), p=-0.45,
        arm=[1.0, 0.98, 0.97, 0.97, 0.97], fore=[1.0, 0.99, 0.97, 0.96, 0.97], thigh=[1.0, 1.0, 1.0, 1.0, 1.0],
        calf=[1.0, 0.98, 0.95, 0.95, 0.97, 1.0], calf_pk=0.82,
        gain=dict(pec=0.7, delt=0.8, lat=0.85, trap=0.5, arm=0.8, fore=0.9, calf=0.85, abs=1.2, leg=1.0, defin=1.35),
        soft=0.0, fat=0.0, ribs=1.0, knobs=1.0),
    "Athletic": dict(
        key="athletic",
        skel=dict(torso=1.0, leg=1.0, lowerleg=1.0, arm=1.0, forearm=1.0, armw=1.0, hand=1.0, lower=(1.0, 1.0), foot=1.0),
        tx=[0.97, 0.95, 1.02, 1.07, 1.07, 1.05], tf=[0.98, 0.97, 1.02, 1.04, 1.03, 1.0], tb=[0.98, 0.98, 1.03, 1.05, 1.04, 1.0],
        neck=([0.72, 0.45, 0.42], [0.32, 0.29, 0.29], [0.34, 0.32, 0.32]), p=-0.3,
        arm=[1.0, 1.0, 1.0, 1.0, 1.0], fore=[1.0, 1.0, 1.0, 1.0, 1.0], thigh=[1.0, 1.0, 1.0, 1.0, 1.0],
        calf=[1.0, 1.0, 1.0, 1.0, 1.0, 1.0], calf_pk=0.75,
        gain=dict(pec=1.0, delt=1.0, lat=1.0, trap=1.0, arm=1.0, fore=1.0, calf=1.0, abs=1.0, leg=1.0, defin=1.0),
        soft=0.0, fat=0.0, ribs=0.3, knobs=0.3),
    "Muscular": dict(
        key="muscular",
        skel=dict(torso=1.0, leg=1.02, lowerleg=1.0, arm=1.0, forearm=1.0, armw=1.10, hand=1.06, lower=(1.06, 1.04), foot=1.04),
        tx=[0.98, 0.96, 1.08, 1.17, 1.19, 1.16], tf=[1.0, 1.0, 1.08, 1.12, 1.10, 1.03], tb=[1.0, 1.02, 1.10, 1.14, 1.12, 1.04],
        neck=([0.82, 0.52, 0.47], [0.34, 0.31, 0.31], [0.37, 0.35, 0.35]), p=-0.2,
        arm=[1.0, 1.03, 1.05, 1.05, 1.04], fore=[1.0, 1.01, 1.03, 1.04, 1.04], thigh=[1.0, 1.0, 1.0, 1.0, 1.0],
        calf=[1.0, 1.02, 1.07, 1.09, 1.05, 1.0], calf_pk=0.74,
        gain=dict(pec=1.3, delt=1.4, lat=1.4, trap=1.3, arm=1.35, fore=1.15, calf=1.15, abs=1.0, leg=1.0, defin=1.0),
        soft=0.0, fat=0.0, ribs=0.0, knobs=0.0, built=1.0),
    "Power Build": dict(
        key="power",
        skel=dict(torso=0.98, leg=0.93, lowerleg=0.92, arm=0.94, forearm=0.96, armw=1.16, hand=1.12, lower=(1.10, 1.14), foot=1.06),
        tx=[1.0, 1.06, 1.12, 1.16, 1.17, 1.17], tf=[1.02, 1.12, 1.20, 1.22, 1.16, 1.06], tb=[1.02, 1.10, 1.18, 1.20, 1.16, 1.06],
        neck=([1.00, 0.74, 0.64], [0.40, 0.37, 0.36], [0.46, 0.43, 0.41]), p=-0.1,
        arm=[1.0, 1.04, 1.06, 1.06, 1.05], fore=[1.0, 1.05, 1.12, 1.14, 1.12], thigh=[1.0, 1.0, 1.0, 1.0, 1.0],
        calf=[1.0, 1.02, 1.08, 1.10, 1.05, 1.0], calf_pk=0.70,
        gain=dict(pec=1.2, delt=1.4, lat=1.3, trap=2.0, arm=1.3, fore=1.6, calf=1.2, abs=0.7, leg=1.0, defin=0.75),
        soft=0.2, fat=0.25, ribs=0.0, knobs=0.0, built=0.6),
    "Heavyweight Build": dict(
        key="heavy",
        skel=dict(torso=1.0, leg=0.98, lowerleg=0.97, arm=0.98, forearm=0.98, armw=1.10, hand=1.12, lower=(1.16, 1.14), foot=1.12),
        tx=[1.0, 1.10, 1.12, 1.12, 1.10, 1.08], tf=[1.02, 1.16, 1.20, 1.16, 1.10, 1.04], tb=[1.02, 1.10, 1.14, 1.14, 1.10, 1.04],
        neck=([0.92, 0.62, 0.56], [0.40, 0.37, 0.37], [0.44, 0.40, 0.39]), p=-0.35,
        arm=[1.0, 1.03, 1.05, 1.05, 1.04], fore=[1.0, 1.02, 1.05, 1.06, 1.05], thigh=[1.0, 1.0, 1.0, 1.0, 1.0],
        calf=[1.0, 1.02, 1.09, 1.10, 1.05, 1.0], calf_pk=0.70,
        gain=dict(pec=1.1, delt=1.0, lat=1.1, trap=1.2, arm=1.1, fore=1.1, calf=1.15, abs=0.35, leg=1.0, defin=0.35),
        soft=0.7, fat=1.0, ribs=0.0, knobs=0.0, built=0.3),
}
FRAME_ORDER = ["Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build"]
DEFAULT_FRAME = "Athletic"
FRAME_BY_KEY = {v["key"]: k for k, v in FRAMES.items()}


def part_extra(fr, base):
    """the frame's extra scale (game space, x / y / z) on a part, from its skeleton factors: limb lengths along the
    bones, the lower body's width / depth (the pelvis, thighs, calves and feet together, so the trunks and boots fitted
    on the Athletic frame fit when scaled by the same factors: BodyAssetData.frames[id].gearScale), the arms' girth
    and the hands' size"""
    k = fr["skel"]
    lx, lz = k["lower"]
    return {
        "UpperTorso": (1.0, k["torso"], 1.0), "LowerTorso": (lx, 1.0, lz),
        "UpperLeg": (lx, k["leg"], lz), "LowerLeg": (lx, k["lowerleg"], lz), "Foot": (k["foot"], k["foot"], k["foot"]),
        "UpperArm": (k["armw"], k["arm"], k["armw"]), "LowerArm": (k["armw"], k["forearm"], k["armw"]),
        "Hand": (k["hand"], k["hand"], k["hand"]),
    }[base]


def frame_of(f):
    """a frame id, key or dict -> the FRAMES entry (with its id under 'id')"""
    if isinstance(f, dict):
        return f
    f = f or DEFAULT_FRAME
    fid = f if f in FRAMES else FRAME_BY_KEY.get(f)
    if fid is None:
        raise KeyError("unknown frame %r" % (f,))
    fr = dict(FRAMES[fid])
    fr["id"] = fid
    return fr


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
# (v11) the arm axis' extra x per tier in game space, kept for the lite builders (tools/body/lite); the v12 frames put
# the arm where it rests against the frame's torso (arm_x) and use no extra shift
ARM_DX = {0: 0.0, 1: -0.085, 2: -0.098, 3: -0.11, 4: -0.122, 5: -0.13}


def game_scale(base):
    rx, ry, rz = RTHRO[base]
    return np.array([rx * SLIM_W, ry, rz * SLIM_D])


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


# ------------------------------------------------------------------------------------------ muscle lobes
def kern(u):
    """C1 bump: 1 at 0, 0 at |u| >= 1 with zero slope there"""
    u = np.clip(np.abs(u), 0, 1)
    return (1 - u * u) ** 2


def Lb(phi, w, s_lo, s_pk, s_hi, a, drift=0.0, sym=True, k=1.0):
    """a muscle lobe on a part's (s, azimuth) plane: centred at azimuth `phi` (deg: 0 front, +90 = +X, +-180 back),
    half-width `w` deg; along the bone it rises from s_lo to its belly at s_pk and falls to s_hi; `a` = the radius it
    adds at the belly (prototype studs, < 0 for a separation); drift = deg per unit s the centre moves with height
    (diagonal muscles); sym = mirrored at -phi (torso lobes; a lobe at 0 / 180 stays single); k = the kernel's
    sharpening (k > 1 narrows the crest, the foot stays where it is)"""
    return dict(phi=float(phi), w=float(w), s_lo=float(s_lo), s_pk=float(s_pk), s_hi=float(s_hi), a=float(a),
                drift=float(drift), sym=sym, k=float(k))


def lobe_field(S, ANG, lobes):
    """radius displacement (R, nseg) from the lobes at ring heights S (R,) and azimuths ANG (R, nseg) in degrees"""
    D = np.zeros_like(ANG)
    for L in lobes:
        if abs(L["a"]) < 1e-9:
            continue
        s = S[:, None]
        lo, pk, hi = L["s_lo"], L["s_pk"], L["s_hi"]
        E = np.where(s < pk, kern((s - pk) / max(pk - lo, 1e-6)), kern((s - pk) / max(hi - pk, 1e-6)))
        E = np.where((s <= lo) | (s >= hi), 0.0, E)
        centres = [L["phi"]]
        if L["sym"] and abs(L["phi"]) > 1e-6 and abs(abs(L["phi"]) - 180) > 1e-6:
            centres.append(-L["phi"])
        for c in centres:
            cc = c + L["drift"] * (s - pk) * (1 if c >= 0 else -1)
            d = (ANG - cc + 180.0) % 360.0 - 180.0
            G = kern(d / L["w"])
            if L["k"] != 1.0:
                G = G ** L["k"]
            D += L["a"] * E * G
    return D


def _grid(prof, m, rings, phis, frame, shrink, lobes=()):
    O, A, X, Z = [np.asarray(v, float) for v in frame]
    S = np.array([r[0] for r in rings])
    SC = np.array([r[1] for r in rings])
    PS = np.array([r[2] for r in rings])
    pr = prof(PS, m)
    sh = _shrink(PS, shrink)
    nseg = len(phis)
    R = np.empty((len(rings), nseg))
    for i in range(len(rings)):
        R[i] = superr(phis, pr["ax"][i], pr["af"][i], pr["ab"][i], pr["p"][i])
    if lobes:
        x = R * np.sin(phis)[None, :]
        z = -R * np.cos(phis)[None, :]
        ANG = np.degrees(np.arctan2(x, -z))
        R = np.maximum(R + lobe_field(S, ANG, lobes), 0.02)
    R = R * SC[:, None] * sh[:, None]
    P = np.empty((len(rings), nseg, 3))
    C = np.empty((len(rings), 3))
    for i in range(len(rings)):
        c = O + A * S[i] + X * pr["cx"][i] + Z * pr["cz"][i]
        C[i] = c
        P[i] = c[None, :] + np.outer(R[i] * np.sin(phis), X) + np.outer(-R[i] * np.cos(phis), Z)
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
         bumps=(), sub=4, lobes=()):
    """Low-res loft whose vertices are exactly every `sub`-th vertex of a refined loft; the muscle lobes shape the
    refined rings (lobe_field), the bumps (bell) displace the refined surface along its normals, and its normals are
    what the low-res mesh carries (a vertex-density "normal map"). cap = (height, exponent, rings). Returns lp
    {P, N, U, T} with a duplicated UV seam column at the back (phi = +-pi) and single pole vertices."""
    frame = frame or ((0, 0, 0), (0, 1, 0), (1, 0, 0), (0, 0, 1))
    k = sub
    rd = _ring_specs(s_lo, s_hi, cap_lo, cap_hi, nb, sdens, k)
    rl = _ring_specs(s_lo, s_hi, cap_lo, cap_hi, nb, sdens, 1)
    # low ring i -> refined ring index
    key = {(round(r[0], 9), round(r[1], 9)): i for i, r in enumerate(rd)}
    ridx = [key[(round(r[0], 9), round(r[1], 9))] for r in rl]
    phd = _phis(nseg * k, bias)
    Pd, Cd, Sd = _grid(prof, m, rd, phd, frame, shrink, lobes)
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


# ------------------------------------------------------------------------------------------ bumps (landmarks)
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
    # (v11 slim) the muscle bells' MASS term is cut to BULK (the definition terms stay: leaner, not softer)
    return f * tr["f"] + m * tr["m"] * (BULK if m > 0 else 1.0) + d * tr["d"]


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


# ------------------------------------------------------------------------------------------ the slim pass (v11)
# Kept as the LEGACY section (the v11 Athletic bodies the gear was fitted on, tools/body/lite's builders import it):
# every part's cross-section narrowed along its bone, more at the waist and mid limbs, less at the ends, more with the
# tier's mass; 1 at the wrist and ankle. The v12 frames evaluate Slim(legacy profile) wherever the gear touches.
SLIM = {
    "Torso": dict(s=[1.58, 1.80, 2.00, 2.21, 2.45, 2.75, 3.05, 3.30, 3.48, 3.60],
                  x=([0.05, 0.05, 0.05, 0.07, 0.10, 0.10, 0.09, 0.08, 0.05, 0.04],
                     [0.00, 0.005, 0.01, 0.02, 0.03, 0.035, 0.045, 0.05, 0.03, 0.015]),
                  z=([0.05, 0.05, 0.05, 0.08, 0.10, 0.10, 0.10, 0.09, 0.06, 0.05],
                     [0.00, 0.005, 0.01, 0.02, 0.03, 0.035, 0.045, 0.05, 0.03, 0.015])),
    "UpperArm": dict(s=[2.846, 3.00, 3.20, 3.40, 3.53],
                     x=([0.06, 0.09, 0.10, 0.09, 0.06], [0.01, 0.05, 0.065, 0.05, 0.02]),
                     z=([0.06, 0.09, 0.10, 0.09, 0.06], [0.01, 0.05, 0.065, 0.05, 0.02])),
    "LowerArm": dict(s=[2.153, 2.30, 2.50, 2.70, 2.846],
                     x=([0.0, 0.04, 0.08, 0.08, 0.06], [0.0, 0.01, 0.025, 0.02, 0.01]),
                     z=([0.0, 0.04, 0.08, 0.08, 0.06], [0.0, 0.01, 0.025, 0.02, 0.01])),
    "UpperLeg": dict(s=[0.982, 1.15, 1.40, 1.65, 1.811],
                     x=([0.05, 0.07, 0.09, 0.07, 0.05], [0.01, 0.02, 0.03, 0.02, 0.01]),
                     z=([0.05, 0.07, 0.09, 0.07, 0.05], [0.01, 0.02, 0.03, 0.02, 0.01])),
    "LowerLeg": dict(s=[0.235, 0.35, 0.55, 0.75, 0.90, 0.982],
                     x=([0.0, 0.02, 0.06, 0.07, 0.06, 0.05], [0.0, 0.005, 0.02, 0.025, 0.015, 0.01]),
                     z=([0.0, 0.02, 0.06, 0.07, 0.06, 0.05], [0.0, 0.005, 0.02, 0.025, 0.015, 0.01])),
}
BULK = 0.82


def slim_k(base, s, m):
    """(kx, kz): the slim factors along the part's bone at prototype heights s, for tier mass m"""
    sp = SLIM.get(base)
    s = np.asarray(s, float)
    if sp is None:
        return np.ones_like(s), np.ones_like(s)
    out = []
    for ax in ("x", "z"):
        a, b = sp[ax]
        out.append(1.0 - (pchip(sp["s"], a, s) + m * pchip(sp["s"], b, s)))
    return out[0], out[1]


class Slim:
    """a Prof narrowed by the slim pass (ax by kx, af / ab by kz)"""

    def __init__(self, prof, base):
        self.prof, self.base = prof, base

    def __call__(self, s, m):
        out = dict(self.prof(s, m))
        kx, kz = slim_k(self.base, s, m)
        out["ax"] = out["ax"] * kx
        out["af"] = out["af"] * kz
        out["ab"] = out["ab"] * kz
        return out


def dome(key, base, s, tr):
    """(v11) a limb's joint dome height, shrunk with its section at the joint (it stays a near-sphere about the pivot)"""
    kx, kz = slim_k(base, [s], tr["m"])
    return JOINT_DOME[key] * float((kx[0] + kz[0]) / 2)


# ------------------------------------------------------------------------------------------ joints
# the height (prototype units along the bone) of the domes that close each limb part at a joint. Every dome is a
# near-sphere ABOUT ITS PIVOT in game space (height x the part's game Y scale ~ its game radius there), so turning
# the joint turns the dome in place: nothing swings out through the neighbour. shoulder: 0.30 / 1.342 (upper arm Y
# scale); elbow 0.26 / 1.342; wrist 0.155 / 1.342; hip 0.35 / 1.506 (upper leg); knee 0.25 / 1.506
JOINT_DOME = {"shoulder": 0.224, "elbow": 0.194, "wrist": 0.115, "hip": 0.232, "knee": 0.166}
# (v12) a dome's height from the section it closes: game radius = game height -> h = r x (x scale / y scale)
DOME_K = {"UpperArm": 0.869 / 1.342, "LowerArm": 0.869 / 1.342, "UpperLeg": 0.788 / 1.506, "LowerLeg": 0.788 / 1.506}


def dome_r(base, prof, s, m, lobes=None):
    """a dome height for the section prof gives at s (a near-sphere about the pivot in game space), the lobes' mean
    displacement round that row included (the deltoid cap over the shoulder dome: the sphere grows with it)"""
    pr = prof(np.array([s]), m)
    r = float((pr["ax"][0] + (pr["af"][0] + pr["ab"][0]) / 2) / 2)
    if lobes:
        ang = np.linspace(-180, 180, 73)[None, :-1]
        r += float(lobe_field(np.array([s]), ang, lobes).mean())
    return DOME_K[base] * r


# ------------------------------------------------------------------------------------------ legacy profiles (v11)
def torso_prof():
    """the v11 torso section (both torso parts), before the slim pass"""
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


LEGACY = {
    "Torso": Slim(torso_prof(), "Torso"),
    "UpperArm": Slim(Prof([YE, 3.00, 3.20, 3.40, 3.52],
                          ax=([0.29, 0.30, 0.32, 0.35, 0.37], [0.03, 0.05, 0.07, 0.09, 0.10]),
                          af=([0.28, 0.29, 0.31, 0.33, 0.35], [0.02, 0.04, 0.05, 0.06, 0.07]),
                          p=2.1, cx=[0.0, 0.0, 0.0, -0.01, -0.03]), "UpperArm"),
    "LowerArm": Slim(Prof([YWR, 2.30, 2.50, 2.70, YE],
                          ax=([0.15, 0.18, 0.23, 0.27, 0.29], [0.01, 0.02, 0.04, 0.05, 0.03]),
                          af=([0.19, 0.20, 0.235, 0.265, 0.28], [0.01, 0.02, 0.03, 0.04, 0.02]),
                          p=2.1), "LowerArm"),
    "UpperLeg": Slim(Prof([YK, 1.15, 1.40, 1.65, 1.82],
                          ax=([0.31, 0.34, 0.38, 0.41, 0.42], [0.02, 0.045, 0.05, 0.03, 0.01]),
                          af=([0.30, 0.33, 0.37, 0.40, 0.41], [0.02, 0.04, 0.06, 0.05, 0.02]),
                          ab=([0.30, 0.33, 0.37, 0.41, 0.44], [0.02, 0.03, 0.05, 0.05, 0.04]),
                          p=2.15, cx=([0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.02, 0.025, 0.015, 0.0])), "UpperLeg"),
    "LowerLeg": Slim(Prof([YA, 0.35, 0.55, 0.75, 0.90, YK],
                          ax=([0.17, 0.185, 0.225, 0.27, 0.295, 0.31], [0.01, 0.02, 0.03, 0.04, 0.03, 0.02]),
                          af=([0.18, 0.19, 0.22, 0.25, 0.28, 0.30], [0.01, 0.01, 0.02, 0.03, 0.02, 0.02]),
                          ab=([0.18, 0.20, 0.25, 0.29, 0.30, 0.30], [0.01, 0.02, 0.04, 0.05, 0.04, 0.02]),
                          p=2.1), "LowerLeg"),
}


class Scaled:
    """a profile = a legacy section x per-knot factors (pchip between the knots; x on ax, z on af / ab), with
    optional rows replaced outright above `cut` (the torso's neck) and a per-row exponent shift"""

    def __init__(self, base, knots, kx, kz=None, dp=0.0, soft=0.0, rows=None):
        self.base, self.knots, self.kx, self.kz, self.dp, self.soft = base, knots, kx, kz if kz is not None else kx, dp, soft
        self.rows = rows  # (s_knots, {key: (v0, v1)}) merged in above rows' first s

    def __call__(self, s, m):
        s = np.asarray(s, float)
        out = dict(self.base(s, m))
        kx = pchip(self.knots, self.kx, s)
        kz = pchip(self.knots, self.kz, s)
        out["ax"] = out["ax"] * kx + self.soft
        out["af"] = out["af"] * kz + self.soft
        out["ab"] = out["ab"] * kz + self.soft * 0.8
        out["p"] = out["p"] + self.dp
        if self.rows is not None:
            rs, rv = self.rows
            w = np.clip((s - rs[0]) / max(rs[1] - rs[0], 1e-6), 0, 1)
            w = w * w * (3 - 2 * w)
            for key, (v0, v1) in rv.items():
                val = pchip(rs, np.asarray(v0, float) + m * (np.asarray(v1, float) - np.asarray(v0, float)), s)
                out[key] = out[key] * (1 - w) + val * w
        return out


# ------------------------------------------------------------------------------------------ the frame's sections
T_KNOTS = [2.45, 2.75, 3.05, 3.30, 3.48, 3.58]
NECK_S = [3.58, 3.66, 3.74, 3.84]  # the shoulder top row, the trapezius slope, the neck column (into the head at 3.811)


class Sec:
    """a callable profile from a function"""

    def __init__(self, fn):
        self.fn = fn

    def __call__(self, s, m):
        return self.fn(s, m)


def torso_section(fr):
    """the UpperTorso's section for a frame: the legacy section under the trunks (<= 2.45), the frame's own ribcage
    and shoulder width above (tx / tf / tb at T_KNOTS), and from the shoulder top row (3.58) its trapezius slope into a
    neck column (neck: (ax, af, ab) at 3.66 / 3.74 / 3.84; the head's base is at 3.811), set back a little (cz)"""
    nx, nf, nb = fr["neck"]
    kn = [1.58] + T_KNOTS
    kx, kf, kb = [1.0] + list(fr["tx"]), [1.0] + list(fr["tf"]), [1.0] + list(fr["tb"])
    base = LEGACY["Torso"]
    soft = fr["soft"]
    dp = fr["p"]
    neck_p = [2.6, 2.3, 2.2]
    neck_cz = [0.015, 0.035, 0.04]

    lx, lz = fr["skel"]["lower"]
    fat = fr.get("fat", 0.0)

    def scaled(s, m):
        out = dict(base(s, m))
        # the hem rows (under the trunks' band, s <= 2.45) carry the pelvis scale the LowerTorso and the band wear;
        # above them the frame's own ribcage (tx / tf / tb), blended over 2.45..2.75
        w = np.clip((s - 2.45) / 0.30, 0, 1)
        w = w * w * (3 - 2 * w)
        out["ax"] = out["ax"] * (lx * (1 - w) + pchip(kn, kx, s) * w)
        out["af"] = out["af"] * (lz * (1 - w) + pchip(kn, kf, s) * w)
        out["ab"] = out["ab"] * (lz * (1 - w) + pchip(kn, kb, s) * w)
        # a rounder ribcage (the exponent drops from the hem to the chest), the frame's own shift on top
        out["p"] = out["p"] - 0.35 * np.clip((s - 2.5) / 0.5, 0, 1) + dp * np.clip((s - 2.3) / 0.3, 0, 1)
        def sm(x):
            x = np.clip(x, 0, 1)
            return x * x * (3 - 2 * x)
        if soft > 0:  # the heavyweight's layer: fuller above the hem (never under the band)
            ws = sm((s - 2.5) / 0.3) * sm((3.62 - s) / 0.2)
            out["ax"] = out["ax"] + 0.02 * soft * ws
            out["af"] = out["af"] + 0.03 * soft * ws
            out["ab"] = out["ab"] + 0.015 * soft * ws
        if fat > 0:  # the belly and the flanks: a fat layer that shrinks with the tier (above the band)
            k = fat * (1.0 - 0.75 * m)
            wb = sm((s - 2.42) / 0.2) * sm((3.15 - s) / 0.4)
            out["af"] = out["af"] + 0.10 * k * wb
            out["ax"] = out["ax"] + 0.05 * k * wb
            out["ab"] = out["ab"] + 0.02 * k * wb
        return out

    def call(s, m):
        s = np.asarray(s, float)
        out = scaled(s, m)
        top = scaled(np.array([NECK_S[0]]), m)
        hi = s > NECK_S[0]
        if hi.any():
            sh = s[hi]
            tier = 1.0 + 0.05 * m  # a trained neck is a little thicker
            chin = 0.03 * fat * (1.0 - 0.6 * m)  # the heavyweight's thick, soft neck
            for key, vals, k0 in (("ax", nx, 1.0), ("af", nf, 0.6), ("ab", nb, 0.8)):
                v = [float(top[key][0])] + [x * (1 + (tier - 1) * k0) + chin for x in vals]
                out[key][hi] = pchip(NECK_S, v, sh)
            out["p"][hi] = pchip(NECK_S, [float(top["p"][0])] + neck_p, sh)
            out["cz"][hi] = pchip(NECK_S, [0.0] + neck_cz, sh)
        return out
    return Sec(call)


def torso_sec(fr):
    return torso_section(fr)


ARM_TAPER = [1.02, 1.04, 1.07, 1.03, 0.98]     # elbow .. shoulder: the biceps / triceps belly, thinner into the delt
FORE_TAPER = [1.0, 0.95, 1.00, 1.08, 1.02]    # wrist .. elbow: a narrow wrist, the flexor mass under the elbow


def arm_section(fr):
    return Scaled(LEGACY["UpperArm"], [YE, 3.00, 3.20, 3.40, 3.52], [a * b for a, b in zip(fr["arm"], ARM_TAPER)])


def fore_section(fr):
    return Scaled(LEGACY["LowerArm"], [YWR, 2.30, 2.50, 2.70, YE], [a * b for a, b in zip(fr["fore"], FORE_TAPER)])


def thigh_section(fr):
    return Scaled(LEGACY["UpperLeg"], [YK, 1.15, 1.40, 1.65, 1.82], fr["thigh"])


def calf_section(fr):
    return Scaled(LEGACY["LowerLeg"], [YA, 0.35, 0.55, 0.75, 0.90, YK], fr["calf"])


def arm_x(tr, fr=None):
    """the arm's axis: where the frame's upper arm rests against the frame's torso side (in game space the arm's
    inner face sinks ARM_SINK into the torso at the armpit row s = 3.30); the Shoulder, Elbow and Wrist pivots lie on
    it. (v11's tiers: 1.20 + 0.22 m with ARM_DX, which this reproduces for the Athletic frame.)"""
    fr = frame_of(fr)
    m = tr["m"]
    ax_t = float(torso_sec(fr)(np.array([3.30]), m)["ax"][0])
    ax_a = float(arm_section(fr)(np.array([3.30]), m)["ax"][0])
    ST, SA = game_scale("UpperTorso")[0], game_scale("UpperArm")[0] * fr["skel"]["armw"]
    return 1.0 + (ST * (ax_t - 1.0) - ARM_SINK) / SA + ax_a


ARM_SINK = 0.025


def tier_joints(tr, fr=None):
    Jt = dict(J)
    ax = arm_x(tr, fr)
    for side, sg in (("Right", 1), ("Left", -1)):
        Jt[side + "Shoulder"] = (sg * ax, YS_PIVOT, 0.0)
        for jn in ("Elbow", "Wrist"):
            x, y, z = J[side + jn]
            Jt[side + jn] = (sg * ax, y, z)
        # the hand's grip point: palm centre, a little inside the wrist axis
        Jt[side + "Grip"] = (sg * (ax - 0.06), 1.98, 0.0)
    return Jt


def game_joints(tr, n=None, fr=None):
    """prototype joints -> game rest space (feet on Y = 0): chained from the root, each segment scaled by the
    part it lies in and by the frame's skeleton factors (part_extra: the frame's own limb lengths and hip width).
    Returns (G, Jo): game joints, prototype joints (both with Left / Right / Grip)."""
    fr = frame_of(fr)
    Jo = {k: np.array(v, float) for k, v in tier_joints(tr, fr).items()}
    X = lambda base: np.array(part_extra(fr, base), float)  # noqa: E731
    ST, SA, SH = game_scale("UpperTorso") * X("UpperTorso"), game_scale("UpperArm") * X("UpperArm"), game_scale("Hand") * X("Hand")
    SLT = game_scale("LowerTorso") * X("LowerTorso")
    SL, SLL, SF = game_scale("UpperLeg") * X("UpperLeg"), game_scale("LowerLeg") * X("LowerLeg"), game_scale("Foot") * X("Foot")
    SFA = game_scale("LowerArm") * X("LowerArm")
    G = {"Root": np.zeros(3)}
    r = Jo["Root"]
    for k in ("Waist", "Neck"):
        G[k] = ST * (Jo[k] - r)
    for side, sg in (("Right", 1), ("Left", -1)):
        G[side + "Hip"] = SLT * (Jo[side + "Hip"] - r)
        G[side + "Knee"] = G[side + "Hip"] + SL * (Jo[side + "Knee"] - Jo[side + "Hip"])
        G[side + "Ankle"] = G[side + "Knee"] + SLL * (Jo[side + "Ankle"] - Jo[side + "Knee"])
        s15 = np.array([sg * R15_SHOULDER[0], R15_SHOULDER[1], R15_SHOULDER[2]])
        G[side + "Elbow"] = ST * (s15 - r) + SA * (Jo[side + "Elbow"] - s15)
        G[side + "Wrist"] = G[side + "Elbow"] + SFA * (Jo[side + "Wrist"] - Jo[side + "Elbow"])
        G[side + "Grip"] = G[side + "Wrist"] + SH * (Jo[side + "Grip"] - Jo[side + "Wrist"])
        # the shoulder pivot on the arm's axis (the upper arm is mapped about the elbow: this is where its dome lands)
        G[side + "Shoulder"] = G[side + "Elbow"] + SA * (Jo[side + "Shoulder"] - Jo[side + "Elbow"])
    floor = G["RightAnkle"][1] - SF[1] * Jo["RightAnkle"][1]  # the foot's sole is at prototype Y = 0
    for k in G:
        G[k] = G[k] - np.array([0.0, floor, 0.0])
    return G, Jo


def to_game(lp, base, key, Jo, G, fr=None):
    """maps one prototype part into game space about its anchor joint `key` (x the frame's extra scale on the part);
    normals by the inverse transpose"""
    S = game_scale(base) * (np.array(part_extra(frame_of(fr), base), float) if fr is not None else 1.0)
    P = G[key] + (lp["P"] - Jo[key]) * S
    N = lp["N"] / S
    N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    return {"P": P, "N": N, "U": lp["U"], "T": lp["T"]}


# ------------------------------------------------------------------------------------------ the muscles
def A(tr, fr, g, f=0.0, m=0.0, d=0.0):
    """a lobe's amplitude: the base feature and the mass term by the frame's gain for the group, the definition term by
    its definition gain; the heavyweight's layer softens every separation"""
    G = fr["gain"]
    v = G.get(g, 1.0) * (f * tr["f"] + m * tr["m"]) + G["defin"] * d * tr["d"]
    if v < 0:
        v *= (1 - 0.5 * fr["soft"])
    return v


VERT = lambda x: ((x, 0, 0), (0, 1, 0), (1, 0, 0), (0, 0, 1))  # noqa: E731


def upper_torso(tr, fr):
    g = lambda *a, **k: A(tr, fr, *a, **k)  # noqa: E731
    L = [
        # ---- front: the pec plate (steep lower edge, soft above), its tie-in to the front delt, the sternum
        Lb(27, 40, 2.98, 3.22, 3.50, g("pec", 0.014, 0.085, 0.008), k=1.2),
        Lb(60, 24, 3.26, 3.40, 3.54, g("pec", 0.008, 0.045, 0.004)),            # pec -> delt tie-in
        Lb(0, 7, 2.98, 3.20, 3.44, g("pec", 0, -0.010, -0.012)),                # sternum line
        Lb(26, 30, 2.88, 2.95, 3.01, g("pec", 0, -0.006, -0.009)),              # the pec's lower edge
        Lb(62, 7, 3.28, 3.40, 3.52, g("pec", 0, -0.004, -0.006)),               # deltopectoral line
        # ---- abs: two columns, three rows, the linea alba, the tendinous lines, the semilunaris
        Lb(10, 13, 2.79, 2.90, 3.01, g("abs", 0.004, 0.012, 0.018)),
        Lb(10, 13, 2.58, 2.69, 2.80, g("abs", 0.004, 0.012, 0.018)),
        Lb(10, 12, 2.40, 2.48, 2.58, g("abs", 0.003, 0.010, 0.015)),
        Lb(0, 4, 2.38, 2.70, 3.02, g("abs", 0, -0.004, -0.009)),                # linea alba
        Lb(10, 18, 2.77, 2.795, 2.82, g("abs", 0, -0.002, -0.006)),             # ab row lines
        Lb(10, 18, 2.56, 2.585, 2.61, g("abs", 0, -0.002, -0.0055)),
        Lb(20, 4, 2.42, 2.70, 3.00, g("abs", 0, -0.003, -0.008), drift=-6),     # linea semilunaris
        # ---- side: serratus fingers (diagonal), obliques and the flank roll (the hem row 2.45 stays on the legacy hull)
        Lb(56, 9, 3.00, 3.04, 3.08, g("abs", 0.003, 0.009, 0.012)),
        Lb(58, 9, 2.91, 2.95, 2.99, g("abs", 0.003, 0.009, 0.012)),
        Lb(60, 9, 2.82, 2.86, 2.90, g("abs", 0.003, 0.008, 0.011)),
        Lb(62, 8, 2.73, 2.77, 2.81, g("abs", 0.002, 0.007, 0.009)),
        Lb(72, 22, 2.46, 2.56, 2.72, g("abs", 0.006, 0.026, 0.004)),            # external oblique
        Lb(86, 16, 2.50, 2.60, 2.74, g("abs", 0.003, 0.016, 0.006)),            # the flank roll
        # ---- back: the lats' V, the erectors, the spine groove, the traps' diamond and slope, infraspinatus / teres
        Lb(135, 40, 2.55, 3.05, 3.38, g("lat", 0.012, 0.085, 0.0), k=1.1),
        Lb(106, 20, 3.00, 3.22, 3.42, g("lat", 0.008, 0.05, 0.004)),            # the lat's outer sweep under the armpit
        Lb(168, 14, 2.34, 2.72, 3.12, g("lat", 0.005, 0.025, 0.004)),           # erector columns
        Lb(180, 5, 2.34, 2.90, 3.42, g("lat", -0.007, -0.012, -0.015)),         # spine groove (ends under the traps)
        Lb(180, 56, 3.16, 3.46, 3.74, g("trap", 0.010, 0.046, 0.0)),            # the traps' diamond, into the slope
        Lb(180, 48, 3.46, 3.60, 3.74, g("trap", 0.010, 0.035, 0.0)),            # the upper traps between the blades
        Lb(180, 14, 2.94, 3.14, 3.34, g("trap", 0.003, 0.012, 0.004)),          # its tail
        Lb(150, 22, 3.18, 3.34, 3.50, g("lat", 0.004, 0.028, 0.006)),           # infraspinatus
        Lb(118, 16, 3.14, 3.26, 3.40, g("lat", 0.003, 0.02, 0.005)),            # teres major
        Lb(112, 16, 3.38, 3.47, 3.58, g("delt", 0.006, 0.026, 0.0)),            # the rear delt's root on the back
        # ---- shoulders and neck: the girdle's rounding under the delt, the clavicles, the traps rising into the neck
        Lb(90, 46, 3.36, 3.56, 3.74, g("delt", 0.045, 0.04, 0.0)),
        Lb(30, 28, 3.58, 3.62, 3.67, g("pec", 0.006, 0.0, 0.004)),              # clavicle ridge
        Lb(0, 12, 3.60, 3.65, 3.72, g("pec", -0.010, -0.004, -0.004)),           # the notch at the throat
        Lb(180, 62, 3.56, 3.70, 3.86, g("trap", 0.02, 0.07, 0.0)),               # upper traps into the neck (the slope)
        Lb(22, 10, 3.68, 3.78, 3.90, g("trap", 0.008, 0.010, 0.006)),           # sternocleidomastoid
        Lb(180, 7, 3.72, 3.80, 3.90, g("trap", -0.002, -0.002, -0.003)),        # the nape's groove
    ]
    built = fr.get("built", 0.0) * tr["f"]  # the naturally built frames carry a chest / lats / delt roots at tier 1
    L += [
        Lb(27, 40, 2.98, 3.22, 3.50, 0.05 * built, k=1.2), Lb(135, 40, 2.55, 3.05, 3.38, 0.045 * built, k=1.1),
        Lb(90, 36, 3.42, 3.54, 3.68, 0.025 * built), Lb(180, 44, 3.18, 3.44, 3.70, 0.02 * built),
    ]
    ribs = fr.get("ribs", 0.0) * tr["f"] * (1.0 - 0.5 * tr["m"])  # the lean frame's ribs and sternum show
    L += [
        Lb(0, 6, 2.95, 3.20, 3.44, -0.010 * ribs), Lb(0, 5, 2.75, 2.90, 3.00, -0.006 * ribs),
        Lb(40, 5, 2.80, 2.90, 2.98, -0.005 * ribs, drift=-25), Lb(50, 5, 2.72, 2.82, 2.90, -0.005 * ribs, drift=-25),
        Lb(60, 5, 2.64, 2.74, 2.82, -0.004 * ribs, drift=-25),
    ]
    fat = fr.get("fat", 0.0) * tr["f"] * (1.0 - 0.75 * tr["m"])
    L += [
        Lb(0, 50, 2.36, 2.62, 2.98, 0.045 * fat, k=0.8),            # the belly's round
        Lb(85, 24, 2.34, 2.52, 2.70, 0.035 * fat),                  # love handles
        Lb(0, 40, 2.92, 3.03, 3.14, -0.004 * fat),                  # the fold under the chest
    ]
    sd = ([YW, 2.32, 2.36, 3.36, 3.42, 3.54, 3.57, 3.84], [0.6, 0.6, 1.3, 1.3, 0.9, 0.9, 1.7, 1.7])
    return loft(torso_sec(fr), tr["m"], YW, 3.84, (0.22, 1.0, 2, 0.88), (0.05, 1.0, 2), nb=36, nseg=42, bias=0.5,
                sdens=sd, lobes=L)


def lower_torso(tr, fr):
    g = lambda *a, **k: A(tr, fr, *a, **k)  # noqa: E731
    L = [
        Lb(148, 46, 1.84, 1.99, 2.17, g("leg", 0.03, 0.06, 0.0)),               # glutes
        Lb(180, 5, 1.84, 1.98, 2.14, g("leg", -0.010, -0.007, 0.0)),            # the cleft
        Lb(0, 32, 1.98, 2.10, 2.24, g("abs", 0.0, 0.012, 0.010)),               # lower abs
        Lb(150, 36, 2.06, 2.13, 2.22, g("leg", 0.006, 0.02, 0.004)),            # glute medius shelf
        Lb(96, 10, 1.90, 1.98, 2.08, g("leg", 0, -0.006, -0.008)),              # the side hollow
        Lb(166, 6, 2.15, 2.19, 2.24, g("leg", -0.002, -0.001, -0.005)),         # lumbar dimples
        Lb(24, 5, 1.98, 2.10, 2.24, g("abs", 0, -0.003, -0.008), drift=-30),    # the V-lines
    ]
    # the child of the waist joint: a touch thinner near it so the UpperTorso's dome dives cleanly under
    return loft(LEGACY["Torso"], tr["m"], 1.82, 2.30, (0.26, 1.0, 5, 0.9), (0.18, 1.0, 2), nb=9, nseg=32, bias=0.2,
                shrink=[(YW, 0.10, 0.04)], lobes=L)


def upper_arm(tr, fr):
    g = lambda *a, **k: A(tr, fr, *a, **k)  # noqa: E731
    sec = arm_section(fr)
    X = arm_x(tr, fr)
    # (right arm: 0 front, +90 outer, -90 inner against the torso, 180 back)
    L = [
        # the deltoid: one cap wrapping front, side and back (not the inner face), its three heads as crests, the
        # grooves between them and the insertion V over the biceps / brachialis
        Lb(55, 150, 3.18, 3.44, 3.64, g("delt", 0.03, 0.05, 0.0), sym=False),
        Lb(-32, 30, 3.26, 3.42, 3.56, g("delt", 0.006, 0.028, 0.004), sym=False),
        Lb(88, 32, 3.26, 3.44, 3.58, g("delt", 0.008, 0.034, 0.004), sym=False),
        Lb(150, 30, 3.24, 3.40, 3.56, g("delt", 0.004, 0.02, 0.003), sym=False),
        Lb(26, 6, 3.28, 3.40, 3.52, g("delt", 0, -0.002, -0.006), sym=False),
        Lb(122, 6, 3.28, 3.40, 3.52, g("delt", 0, -0.002, -0.005), sym=False),
        Lb(80, 24, 3.12, 3.19, 3.27, g("delt", 0, -0.005, -0.008), sym=False),       # the insertion V
        # the biceps (front, a little inward), its peak, the brachialis under its outer edge
        Lb(-18, 50, 2.92, 3.10, 3.34, g("arm", 0.010, 0.07, 0.008), sym=False, k=1.15),
        Lb(-24, 22, 3.02, 3.10, 3.20, g("arm", 0.002, 0.022, 0.012), sym=False),
        Lb(56, 20, 2.94, 3.04, 3.18, g("arm", 0.003, 0.024, 0.006), sym=False),
        Lb(-14, 4, 3.00, 3.14, 3.28, g("arm", 0, 0, -0.004), sym=False),             # the biceps' mid line
        # the triceps: long head (back, inward), lateral head (back, outward), the flat tendon above the elbow
        Lb(-150, 32, 3.00, 3.20, 3.44, g("arm", 0.008, 0.06, 0.006), sym=False),
        Lb(150, 32, 2.98, 3.20, 3.40, g("arm", 0.008, 0.058, 0.006), sym=False),
        Lb(180, 16, 2.90, 2.99, 3.08, g("arm", 0, -0.004, -0.010), sym=False),
        # the separations between the biceps and the triceps (outer and inner)
        Lb(100, 7, 2.94, 3.12, 3.32, g("arm", 0, -0.004, -0.008), sym=False),
        Lb(-104, 7, 2.96, 3.12, 3.30, g("arm", 0, -0.003, -0.006), sym=False),
    ]
    m = tr["m"]
    return loft(sec, m, YE, YS_PIVOT, (dome_r("UpperArm", sec, YE, m), 1.0, 2, 0.97),
                (dome_r("UpperArm", sec, YS_PIVOT, m, L), 1.0, 4), nb=12, nseg=22, frame=VERT(X), lobes=L)


def lower_arm(tr, fr):
    g = lambda *a, **k: A(tr, fr, *a, **k)  # noqa: E731
    sec = fore_section(fr)
    X = arm_x(tr, fr)
    L = [
        Lb(36, 46, 2.42, 2.66, 2.85, g("fore", 0.008, 0.055, 0.0), sym=False, k=1.1),   # brachioradialis (toward the elbow)
        Lb(-56, 46, 2.34, 2.60, 2.80, g("fore", 0.006, 0.045, 0.0), sym=False),         # the flexor mass
        Lb(-70, 22, 2.50, 2.64, 2.76, g("fore", 0.002, 0.022, 0.008), sym=False),       # flexor belly
        Lb(126, 36, 2.40, 2.60, 2.80, g("fore", 0.004, 0.036, 0.006), sym=False),       # extensors
        Lb(82, 6, 2.36, 2.56, 2.76, g("fore", 0, -0.003, -0.006), sym=False),           # brachioradialis / extensor line
        Lb(-20, 5, 2.20, 2.30, 2.40, g("fore", 0.003, 0.0, 0.004), sym=False),          # the wrist's tendons
    ]
    kn = fr.get("knobs", 0.0) * tr["f"]
    b = [Bp((X + 0.11, 2.21, 0.10), (0.05, 0.05, 0.05, 0.05, 0.08, 0.08), 0.006 * tr["f"] + 0.012 * kn),  # ulna's knob
         Bp((X + 0.0, YE - 0.02, 0.22), (0.10, 0.10, 0.07, 0.07, 0.08, 0.08), 0.014 * kn)]   # the elbow's point (olecranon)
    m = tr["m"]
    return loft(sec, m, YWR, YE, (dome_r("LowerArm", sec, YWR, m), 1.0, 2, 0.9),
                (dome_r("LowerArm", sec, YE, m), 1.0, 2), nb=10, nseg=20, frame=VERT(X), shrink=[(YE, 0.10, 0.0)],
                bumps=b, lobes=L)


def hand(tr, fr=None):
    X = arm_x(tr, fr)
    # (the back of the hand narrows into the wrist, a little thinner than the forearm's tucked rim there, so the seam
    # is the forearm's clean ring, never the two surfaces crossing). The hand is the same on every frame: the gloves
    # and wraps are one mesh for all
    pr = Prof([1.93, 2.05, YWR],
              ax=([0.165, 0.19, 0.132], [0.01, 0.01, 0.006]),
              af=([0.215, 0.212, 0.158], [0.01, 0.01, 0.004]),
              p=[2.8, 2.9, 2.4], cx=[-0.03, -0.01, 0.0])
    b = []
    b.append(Bp((X + 0.13, 1.985, 0.0), (0.06, 0.06, 0.05, 0.045, 0.22, 0.22), 0.014))  # the knuckle ridge
    for z, k in ((-0.15, 1.0), (-0.05, 1.08), (0.05, 1.0), (0.148, 0.85)):
        b.append(Bp((X + 0.12, 1.985, z), (0.06, 0.06, 0.045, 0.04, 0.042, 0.042), 0.018 * k))  # knuckle
        b.append(Bp((X + 0.13, 2.07, z * 0.8), (0.04, 0.04, 0.08, 0.06, 0.016, 0.016), 0.004))  # tendon
    b += [
        Bp((X - 0.12, 2.05, -0.12), (0.07, 0.07, 0.08, 0.07, 0.09, 0.08), 0.024),  # thenar (the thumb's pad)
        Bp((X - 0.13, 2.03, 0.13), (0.06, 0.06, 0.07, 0.06, 0.06, 0.06), 0.012),  # hypothenar
        Bp((X - 0.15, 2.0, 0.0), (0.05, 0.05, 0.07, 0.06, 0.12, 0.12), -0.008),  # the palm's hollow
    ]
    shells = [loft(pr, tr["m"], 1.93, YWR, (0.06, 1.0, 2), (0.12, 1.0, 2), nb=6, nseg=16, frame=VERT(X), bumps=b)]
    # fingers: index at the front (-Z), relaxed curl toward the body (-X for the right hand); four joints each
    for i, (z, Lf, r) in enumerate(((-0.158, 0.17, 0.0495), (-0.053, 0.185, 0.0515), (0.052, 0.175, 0.0495),
                                    (0.152, 0.145, 0.046))):
        y0 = 1.975
        pts = [(X - 0.005, y0, z), (X - 0.04, y0 - 0.45 * Lf, z), (X - 0.085, y0 - 0.76 * Lf, z * 1.01),
               (X - 0.14, y0 - 0.96 * Lf, z * 1.02)]
        shells.append(tube(pts, [r * 1.02, r * 1.05, r * 0.97, r * 0.86], nside=8, kcap=2,
                           uvbox=(0.2 * i, 0.8, 0.2 * i + 0.2, 1.0)))
    pts = [(X - 0.03, 2.10, -0.16), (X - 0.065, 2.03, -0.225), (X - 0.10, 1.965, -0.25), (X - 0.128, 1.925, -0.256)]
    shells.append(tube(pts, [0.068, 0.066, 0.06, 0.053], nside=8, kcap=2, uvbox=(0.8, 0.8, 1.0, 1.0)))
    # palm UVs live in the top 80 %
    shells[0]["U"] = shells[0]["U"] * np.array([1.0, 0.8])
    return merge_lp(shells)


def upper_leg(tr, fr):
    g = lambda *a, **k: A(tr, fr, *a, **k)  # noqa: E731
    sec = thigh_section(fr)
    X = LEG_X
    # (right leg: 0 front, +90 outer, -90 inner, 180 back). Under the trunks the section is the legacy one; the forms
    # that show under the hem are the teardrop, the kneecap and the hamstrings' lower bellies
    L = [
        Lb(-4, 30, 1.14, 1.42, 1.72, g("leg", 0.008, 0.045, 0.006), sym=False),       # rectus femoris
        Lb(58, 32, 1.10, 1.32, 1.64, g("leg", 0.006, 0.040, 0.004), sym=False),       # vastus lateralis (the sweep)
        Lb(-44, 28, 1.02, 1.12, 1.24, g("leg", 0.005, 0.03, 0.012), sym=False),       # the VMO teardrop
        Lb(22, 5, 1.10, 1.36, 1.62, g("leg", 0, -0.002, -0.006), sym=False),          # RF / VL line
        Lb(-26, 5, 1.12, 1.38, 1.60, g("leg", 0, -0.002, -0.005), sym=False),         # RF / VM line
        Lb(-60, 5, 1.20, 1.45, 1.70, g("leg", 0, -0.001, -0.004), sym=False, drift=40),  # sartorius
        Lb(-100, 28, 1.26, 1.50, 1.72, g("leg", 0.003, 0.02, 0.0), sym=False),        # adductors
        Lb(160, 30, 1.10, 1.34, 1.62, g("leg", 0.006, 0.03, 0.004), sym=False),       # biceps femoris
        Lb(-156, 30, 1.08, 1.32, 1.60, g("leg", 0.006, 0.03, 0.004), sym=False),      # semitendinosus
        Lb(180, 5, 1.08, 1.30, 1.56, g("leg", 0, -0.001, -0.005), sym=False),         # their line
        Lb(176, 34, 1.60, 1.72, 1.80, g("leg", 0.010, 0.03, 0.0), sym=False),         # the glute fold (under the hem)
    ]
    kn = fr.get("knobs", 0.0) * tr["f"]
    b = [Bp((X - 0.02, 1.00, -0.30), (0.09, 0.09, 0.08, 0.08, 0.08, 0.08), 0.012 * tr["f"] + 0.012 * kn),  # kneecap
         Bp((X + 0.16, 1.00, 0.0), (0.06, 0.06, 0.07, 0.07, 0.12, 0.12), 0.010 * kn),   # the knee's outer condyle
         Bp((X - 0.16, 1.00, 0.0), (0.06, 0.06, 0.07, 0.07, 0.12, 0.12), 0.010 * kn)]   # inner condyle
    m = tr["m"]
    return loft(sec, m, YK, YH, (dome_r("UpperLeg", sec, YK, m), 1.0, 2, 0.88),
                (dome_r("UpperLeg", sec, YH, m), 1.0, 3), nb=14, nseg=20, frame=VERT(X), shrink=[(YH, 0.16, 0.06)],
                bumps=b, lobes=L)


def lower_leg(tr, fr):
    g = lambda *a, **k: A(tr, fr, *a, **k)  # noqa: E731
    sec = calf_section(fr)
    X = LEG_X
    pk = fr["calf_pk"]  # where the calf's belly sits (high and small on the lean frame, low and full on the heavy)
    L = [
        Lb(-148, 44, 0.52, pk, 0.93, g("calf", 0.010, 0.065, 0.0), sym=False, k=1.1),  # gastrocnemius, medial head
        Lb(148, 40, 0.54, pk + 0.02, 0.93, g("calf", 0.007, 0.052, 0.0), sym=False),   # lateral head
        Lb(180, 6, 0.60, pk + 0.02, 0.90, g("calf", 0, -0.003, -0.007), sym=False),    # between the heads
        Lb(170, 64, 0.40, 0.52, 0.66, g("calf", 0.004, 0.028, 0.004), sym=False),      # soleus
        Lb(38, 30, 0.48, 0.68, 0.88, g("calf", 0.003, 0.024, 0.0), sym=False),         # tibialis anterior
        Lb(-6, 8, 0.44, 0.66, 0.92, g("calf", 0.004, 0.0, 0.004), sym=False),          # the shin's edge
        Lb(180, 14, 0.29, 0.37, 0.46, g("calf", 0.006, 0.0, 0.002), sym=False),        # Achilles
    ]
    b = [Bp((X - 0.17, 0.385, -0.01), (0.05, 0.05, 0.05, 0.045, 0.06, 0.06), 0.022 * tr["f"]),  # inner ankle bone
         Bp((X + 0.175, 0.36, 0.03), (0.05, 0.05, 0.045, 0.045, 0.06, 0.06), 0.02 * tr["f"])]   # outer ankle bone
    m = tr["m"]
    return loft(sec, m, YA, YK, (0.18, 1.0, 3), (dome_r("LowerLeg", sec, YK, m), 1.0, 2), nb=11, nseg=18,
                frame=VERT(X), shrink=[(YK, 0.10, 0.06)], bumps=b, lobes=L)


def foot(tr, fr=None):
    s = [-0.25, -0.12, 0.05, 0.25, 0.40]  # local s = -Z (forward) from the ankle
    pr = Prof(s, ax=[0.185, 0.205, 0.215, 0.235, 0.225],
              af=[0.20, 0.22, 0.17, 0.085, 0.055],  # "front" = up from yc
              ab=[0.15, 0.15, 0.15, 0.15, 0.15], p=[2.6, 2.6, 2.6, 2.8, 2.8])
    X = LEG_X
    b = [Bp((X, 0.11, 0.22), (0.12, 0.12, 0.09, 0.09, 0.08, 0.10), 0.012 * tr["f"]),  # heel
         Bp((X - 0.17, 0.05, -0.05), (0.06, 0.06, 0.05, 0.05, 0.14, 0.14), -0.012 * tr["f"]),  # arch
         Bp((X, 0.12, -0.28), (0.18, 0.18, 0.03, 0.03, 0.03, 0.03), 0.006 * tr["f"]),  # toes' knuckle line
         Bp((X - 0.06, 0.17, -0.06), (0.05, 0.05, 0.04, 0.06, 0.16, 0.14), 0.008 * tr["f"])]  # the instep's tendon
    return loft(pr, tr["m"], s[0], s[-1], (0.10, 1.0, 2), (0.11, 1.0, 2), nb=8, nseg=16,
                frame=((LEG_X, 0.15, 0.0), (0, 0, -1), (1, 0, 0), (0, -1, 0)), bumps=b)


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


def build_tier(bpy, n, proto=False, frame=DEFAULT_FRAME):
    """the (frame, tier)'s 14 parts in game rest space (feet on Y = 0) + "_J" (game joints) / "_J0" (prototype
    joints) / "_frame". proto=True keeps the prototype's Classic block proportions (comparison renders only)"""
    tr = TIERS[n]
    fr = frame_of(frame)
    G, Jo = game_joints(tr, n, fr)
    if proto:
        G = Jo
    parts = {}
    for base, fn in BUILDERS.items():
        lp = fn(tr, fr)
        if base in ("UpperTorso", "LowerTorso"):
            parts[base] = lp if proto else to_game(lp, base, ANCHOR[base], Jo, G, fr)
        else:
            lp = lp if proto else to_game(lp, base, "Right" + ANCHOR[base], Jo, G, fr)
            parts["Right" + base] = lp
            parts["Left" + base] = mirror_lp(lp)
    parts["_J"] = {k: tuple(float(x) for x in v) for k, v in G.items()}
    parts["_J0"] = {k: tuple(float(x) for x in v) for k, v in Jo.items()}
    parts["_frame"] = fr["id"]
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
    ex = part_extra(frame_of(parts.get("_frame")), part_base)[1]
    return G[key][1] + (y0 - Jo[key][1]) * game_scale(part_base)[1] * ex


# gear fit: girths (convex hull, studs) at fixed anatomical heights, from the prototype's muscle centres
FIT_AT = {
    "chest": ("UpperTorso", 3.23), "waist": ("UpperTorso", 2.42), "hips": ("LowerTorso", 1.99),
    "upperArm": ("UpperArm", 3.10), "forearm": ("LowerArm", 2.62), "wrist": ("LowerArm", 2.22),
    "thigh": ("UpperLeg", 1.45), "knee": ("UpperLeg", 1.05), "calf": ("LowerLeg", 0.72), "ankle": ("LowerLeg", 0.40),
    "neck": ("UpperTorso", 3.78),
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


def out_dir(n, frame=DEFAULT_FRAME):
    fr = frame_of(frame)
    if fr["id"] == DEFAULT_FRAME:
        return os.path.join(OUT, "tier%d" % n)
    return os.path.join(OUT, "frames", fr["key"], "tier%d" % n)


def export_tier(n, parts, frame=DEFAULT_FRAME):
    fr = frame_of(frame)
    outdir = out_dir(n, fr)
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
    data = {"tier": n, "name": TIERS[n]["name"], "frame": fr["id"], "frameKey": fr["key"], "params": TIERS[n],
            "tris": total, "fit": fit_sizes(parts), "armAxisX": round(float(Jt["RightElbow"][0]), 4), "parts": rec,
            "gearScale": {b: [round(float(x), 4) for x in part_extra(fr, b)] for b in
                          ("UpperTorso", "LowerTorso", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot")},
            "unit": frame_unit(parts)}
    with open(os.path.join(outdir, "parts.json"), "w") as f:
        json.dump(data, f, indent=1)
    return data


def frame_unit(parts):
    """the frame's rig heights (what unit_rig gives the Athletic frame): joints, hip / shoulder / neck heights"""
    G = parts["_J"]
    j = {k: [round(float(x), 4) for x in v] for k, v in G.items() if not k.startswith("Left")}
    return {"joints": j, "rootHeight": round(float(G["Root"][1]), 4), "hipHeight": round(float(G["RightHip"][1]), 4),
            "neckHeight": round(float(G["Neck"][1]), 4), "shoulderHeight": round(float(G["RightShoulder"][1]), 4),
            "wristHeight": round(float(G["RightWrist"][1]), 4), "standingHeight": round(float(G["Neck"][1] + HEAD_SIZE), 4)}


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
    def __init__(self, bpy, res, samples, silhouette=False):
        self.bpy = bpy
        self.silhouette = silhouette
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
            sc.view_settings.view_transform = "Standard" if silhouette else "AgX"
        except TypeError:
            sc.view_settings.view_transform = "Filmic"
        w = bpy.data.worlds.new("w")
        sc.world = w
        w.use_nodes = True
        bg = w.node_tree.nodes["Background"]
        bg.inputs[0].default_value = (1, 1, 1, 1) if silhouette else (0.16, 0.18, 0.21, 1)
        bg.inputs[1].default_value = 1.0 if silhouette else 0.9
        self.root = bpy.data.objects.new("root", None)  # game -> Blender (Y up -> Z up, face toward -Y)
        sc.collection.objects.link(self.root)
        self.root.rotation_euler = (math.pi / 2, 0, math.pi)
        self.coll = bpy.data.collections.new("Lineup")
        sc.collection.children.link(self.coll)
        self.skin = self.material("skin", SKIN) if not silhouette else self.black()
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

    def black(self):
        m = self.bpy.data.materials.new("black")
        m.use_nodes = True
        nt = m.node_tree
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs[0].default_value = (0, 0, 0, 1)
        nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs[0])
        return m

    def headmat(self, face):
        if self.silhouette:
            return self.skin
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


CY = 3.25  # frame centre height (a 70-inch boxer stands ~6.2 studs)


def render_frame_sheets(bpy, built, tiers, samples, views=("front", "back", "side", "34", "silhouette")):
    """the five frames side by side at each of `tiers`, one image per view: <scratch>/frames_t<N>_<view>.png;
    "silhouette" = black fills on white (front and side), the read from a distance"""
    paths = []
    frames = [f for f in FRAME_ORDER if any((f, n) in built for n in tiers)]
    yaws = {"front": 0, "back": 180, "side": 90, "34": -38}
    sp = 3.6
    for n in tiers:
        for view in views:
            sil = view == "silhouette"
            st = Stage(bpy, (1800, 760), 8 if sil else samples, silhouette=sil)
            if not sil:
                st.floor()
            fs = [f for f in frames if (f, n) in built]
            for i, f in enumerate(fs):
                if sil:
                    x = -(i - (len(fs) - 1) / 2) * sp
                    st.figure("F%d" % i, built[(f, n)], x - 0.95, yaw=0, face="determined")
                    st.figure("S%d" % i, built[(f, n)], x + 0.95, yaw=90, face="determined")
                else:
                    st.figure("F%d" % i, built[(f, n)], -(i - (len(fs) - 1) / 2) * sp, yaw=yaws[view], face="determined")
            p = st.shoot(os.path.join(SCRATCH, "frames_t%d_%s.png" % (n, view)), 0, CY, len(fs) * sp + 0.4, elev=0 if sil else 3)
            label(p, ["%s (T%d)" % (f, n) for f in fs], "Body frames, tier %d (%s): %s" % (n, TIERS[n]["name"],
                  "silhouettes (front, side)" if sil else view))
            paths.append(p)
    return paths


def render_arm_strip(bpy, built, tiers, samples):
    """<scratch>/arms_t<N>.png: the right arm of every frame, straight (A-pose) and bent 110 deg at the elbow"""
    paths = []
    frames = [f for f in FRAME_ORDER if any((f, n) in built for n in tiers)]
    only = ("UpperTorso", "RightUpperArm", "RightLowerArm", "RightHand")
    for n in tiers:
        st = Stage(bpy, (2000, 700), samples)
        fs = [f for f in frames if (f, n) in built]
        sp = 2.2
        labels = []
        for i, f in enumerate(fs):
            parts = built[(f, n)]
            for j, el in enumerate((7.0, 110.0)):
                x = -((2 * i + j) - (2 * len(fs) - 1) / 2) * sp
                place = M4(roty(-30), (x, 0, 0))
                pm = pose_mats(parts["_J"], sh=12.0, el=el)
                for name in only:
                    st.add("A%d_%d_%s" % (i, j, name), parts[name], place @ pm[name], st.skin)
                labels.append("%s %s" % (f.split(" ")[0], "straight" if j == 0 else "bent 110"))
        p = st.shoot(os.path.join(SCRATCH, "arms_t%d.png" % n), 0, 4.1, 2 * len(fs) * sp + 0.4, elev=4)
        label(p, labels, "Right arm close-ups, tier %d (%s): shoulder into delt, elbow seam, forearm taper, hand" % (n, TIERS[n]["name"]))
        paths.append(p)
    return paths


def render_sheets(bpy, tiers, which, samples):
    paths = []
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
    ap.add_argument("--sheets", default="frames,1,2,4,5", help="frames = the frame lineups; 1,2,4,5 = the Athletic tier sheets")
    ap.add_argument("--tiers", default="1,2,3,4,5")
    ap.add_argument("--frames", default=",".join(FRAMES[f]["key"] for f in FRAME_ORDER), help="frame keys (lean,athletic,...)")
    ap.add_argument("--frame-sheet-tiers", default="1,5")
    ap.add_argument("--no-blend", action="store_true")
    a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    import bpy
    os.makedirs(SCRATCH, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    want_tiers = [int(x) for x in a.tiers.split(",")]
    want_frames = [frame_of(k)["id"] for k in a.frames.split(",")]
    built, summary = {}, {}
    for fid in want_frames:
        for n in want_tiers:
            parts = build_tier(bpy, n, frame=fid)
            built[(fid, n)] = parts
            if n >= 1:
                d = export_tier(n, parts, fid)
                summary.setdefault(fid, {})[n] = d
                print("%-17s tier %d %-9s %5d tris  armX %.3f  span %.2f  chest %.2f  neck %.2f" % (
                    fid, n, d["name"], d["tris"], d["armAxisX"], d["fit"]["shoulderSpan"], d["fit"]["chest"]["width"],
                    d["fit"]["neck"]["width"]), flush=True)
    # body_tiers.json: unit from the Athletic frame (built here or read back from its parts.json)
    bt_path = os.path.join(OUT, "body_tiers.json")
    old = json.load(open(bt_path)) if os.path.exists(bt_path) else {}
    ath = summary.get(DEFAULT_FRAME) or {}
    if DEFAULT_FRAME in want_frames and all(n in ath for n in (1, 2, 3, 4, 5)):
        unit = unit_rig({n: built[(DEFAULT_FRAME, n)] for n in (1, 2, 3, 4, 5)})
    else:
        unit = old.get("unit")
    frames_rec = dict(old.get("frames") or {})
    for fid, tiers_d in summary.items():
        if fid == DEFAULT_FRAME:
            continue
        rec = frames_rec.get(FRAMES[fid]["key"]) or {"id": fid, "tiers": {}}
        rec["id"] = fid
        rec["tiers"] = dict(rec.get("tiers") or {})
        for n, d in tiers_d.items():
            rec["tiers"][str(n)] = d
        rec["armAxisX"] = {str(n): d["armAxisX"] for n, d in sorted(rec["tiers"].items(), key=lambda kv: int(kv[0]))}
        t3 = rec["tiers"].get("3") or next(iter(rec["tiers"].values()))
        rec["gearScale"], rec["unit"] = t3["gearScale"], t3["unit"]
        frames_rec[FRAMES[fid]["key"]] = rec
    tiers_rec = dict(old.get("tiers") or {})
    for n, d in ath.items():
        tiers_rec[str(n)] = d
    if unit is not None:
        with open(bt_path, "w") as f:
            json.dump({"unit": unit, "prototype_skeleton": {k: list(v) for k, v in J.items()},
                       "r15_block_reference": R15_BLOCK, "tiers": tiers_rec, "frames": frames_rec,
                       "frameOrder": FRAME_ORDER, "defaultFrame": DEFAULT_FRAME}, f, indent=1)
        print("unit", json.dumps({k: unit[k] for k in ("rootHeight", "hipHeight", "shoulderHeight", "neckHeight",
                                                       "standingHeight", "armAxisX")}))
    if not a.no_render:
        sheets = a.sheets.split(",")
        if "frames" in sheets:
            fst = [int(x) for x in a.frame_sheet_tiers.split(",") if int(x) in want_tiers]
            for p in render_frame_sheets(bpy, built, fst, a.samples):
                print("sheet", p)
            for p in render_arm_strip(bpy, built, fst, a.samples):
                print("sheet", p)
        num = [int(x) for x in sheets if x.isdigit()]
        ath_tiers = {n: built[(DEFAULT_FRAME, n)] for n in want_tiers if (DEFAULT_FRAME, n) in built}
        if num and all(n in ath_tiers for n in (1, 2, 3, 4, 5)):
            for p in render_sheets(bpy, ath_tiers, num, a.samples):
                print("sheet", p)
    if not a.no_blend and all((DEFAULT_FRAME, n) in built for n in (1, 2, 3, 4, 5)):
        save_blend(bpy, {n: built[(DEFAULT_FRAME, n)] for n in (1, 2, 3, 4, 5)})
        print("blend", BLEND)


if __name__ == "__main__":
    main()
