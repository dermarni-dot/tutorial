"""Braids family hair: "Braids" (two dozen thick three-strand plaits to the shoulders), "Box Braids" (~100 thin
plaits from square box partings, to mid back; the family's female default) and "Cornrows" (flat plaited rows from
the front hairline to the nape, scalp showing between them, tucked at the nape). Modelled in Blender (bpy 4.2),
exported with hairlib.

    /opt/bpyenv/bin/python tools/hair/build_braids.py [--render DIR|''] [--only braids,box_braids,cornrows]
                                                      [--no-tex] [--samples N] [--looks N] [--views 34,side]

Writes tools/hair/textures/hair_braid.png + hair_cornrow.png (braids_tex.py), tools/hair/out/<key>/ (meshes +
style.json), tools/hair/blend/<key>.blend and self-check render sheets (default: the family's scratchpad folder).

How it is built (game nominal head space, numerically; CONTRACT.md):
* Partings. The scalp inside the natural hairline is split into rings of constant distance from the hairline,
  the first ON the hairline (inset 0.013 + 0.4 r) from the centre front round the temples, the sideburns, over and
  behind the ears to the nape; each ring is cut into boxes, alternate rings offset by half a box (brick lay).
  One braid roots in every box. HairBase: a square patch of short hair per box (strands running toward its braid,
  darker edges) lying flat at 0.025; the skin lines between the patches (the low-density cap) are the partings.
* Guides (traced on the skull table). Over the top the braids run straight back (round the X axis); at the
  sides back and down, held above the ear (centre >= ear top + 0.025 + r) until behind it, then down behind it;
  braids rooted in front of the ear run straight down past its front edge. Every root starts tangent to the
  scalp along that flow, flat (flatten 0.6), at 40 % radius growing to full over the first 0.08-0.11.
* Stacking: braids are laid inner ring first; one that runs over a braid already laid rises just enough to
  ride over it (mathutils KD tree), ramped, and never more than r + 0.03 above the skull over its first 0.25.
* Hanging: each braid falls from where the skull turns under as a gravity rope (its direction bends toward
  straight down), resting 0.02-0.03 off the head mesh, the ears, both torsos (the female one through the inverse
  of the female skull fit) and the Kit.Scalp body proxy (BVH trees + the proxy SDF), and on the braids laid
  before it: it only moves outward over them, sideways at most half a radius; then smoothed.
* Geometry: the guides are kept as Blender curve objects; each is swept into a flattened tube: thick braids get
  a real plait silhouette (alternating lobes on the two edges, pinched between, rings every quarter period), the
  texture once round (front half left->right, mirrored at the back) with its lobe period locked to the geometry.
  A Shrinkwrap modifier ("outside" mode, vertex group) against the head mesh guarantees the clearance and AO is
  baked into the vertex colours with BVH ray casts.
* Cornrows: rows in planes through an axis deep under the head, clipped to the hairline; each an arched ribbon
  (texture "cornrow": alpha 0 at the row edges), thin where it feeds in at the hairline with crisp baby hairs
  over its start, narrowing and tucked just above the nape hairline.
* Pieces: HairTop (all the scalp parts), HairBase (partings), and the hanging parts as swing chains by azimuth
  round the neck (chain BraidNN: HairBraidNN upper, HairBraidNNb lower, parent / pivot / tip, length "hang").
"""
import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402
from mathutils.kdtree import KDTree  # noqa: E402

import braids_tex  # noqa: E402
import hairlib as hl  # noqa: E402

TEX_DIR = os.path.join(HERE, "textures")
BLEND_DIR = os.path.join(HERE, "blend")
REF = hl.REF
SCRATCH = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/fam/braids"
CLEAR = 0.023  # minimum height of any scalp-hugging vertex above the head mesh / skull table (nominal)
EAR_CLEAR = 0.025
TAU = 2 * math.pi
PLAIT = hl.ATLAS["braid"]["plait"]
ROW = hl.ATLAS["cornrow"]["row"]
BABY = (0.75, 0.875)  # (hairlib's baby range 0.75-1 is split: baby hairs | parting patches)
PAD = (0.875, 1.0)

SK = hl.Skull()
C = SK.c.copy()
SKD = SK.data
SKF_PATH = os.path.join(REF, "skull_f.json")


def smooth(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def V(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


# ------------------------------------------------------------------------------------------- reference
def load_obj_mesh(path, obj, scale=None):
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
    P = np.asarray(P, dtype=np.float64)
    if scale is not None:
        P = P * np.asarray(scale[:3]) + np.asarray(scale[3:])
    return P, F


class Collider:
    """a closed-ish mesh with outward normals: nearest point, inside test, push-out"""

    def __init__(self, P, F, name="", radial=None):
        self.P, self.F = P, F
        self.name = name
        self.radial = radial  # a centre: inside = nearer than the outermost surface on the ray from it
        self.bvh = BVHTree.FromPolygons([tuple(p) for p in P], F)
        self.lo, self.hi = P.min(0) - 0.3, P.max(0) + 0.3

    def signed(self, p):
        loc, n, _i, d = self.bvh.find_nearest(V(p))
        if loc is None:
            return 9.0, None, None
        if self.radial is not None:
            # (the nearest face's normal is unreliable in the creases round the ears: a point behind an ear
            # would read as inside; the ray from the skull centre decides instead)
            dv = np.asarray(p) - self.radial
            L = float(np.linalg.norm(dv))
            u = dv / max(L, 1e-9)
            hit = self.bvh.ray_cast(V(self.radial + u * 3.0), V(-u), 3.0)
            inside = hit[0] is not None and L < 3.0 - hit[3]
            s = -1.0 if inside else 1.0
            nn = np.array(n) if (V(p) - loc).dot(n) * s >= 0 else -np.array(n)
            return s * d, np.array(loc), nn
        s = 1.0 if (V(p) - loc).dot(n) >= 0 else -1.0
        return s * d, np.array(loc), np.array(n)

    def push(self, p, margin):
        """p moved out to margin above the surface if it is closer (or inside)"""
        if np.any(p < self.lo) or np.any(p > self.hi):
            return p, False
        sd, q, n = self.signed(p)
        if q is None or sd >= margin:
            return p, False
        if sd < 0:
            return q + n * margin, True
        d = unit(p - q)
        return q + d * margin, True


def fit_of(skull_path):
    s = hl.Skull(skull_path)

    def plane_point(az, y_target):
        best = None
        for th in np.linspace(0.3, 2.6, 900):
            p = s.point(th, math.radians(az))
            if best is None or abs(p[1] - y_target) < abs(best[1] - y_target):
                best = p
        return best
    W = plane_point(90, 0.15)[0]
    T = s.c[1] + s.radius(0.0, 0.0)
    Fz = plane_point(180, 0.2)[2]
    Bz = plane_point(0, 0.1)[2]
    return dict(W=W, T=T, Fz=Fz, Bz=Bz)


FIT0 = dict(W=0.383, T=0.591, Fz=-0.460, Bz=0.520)


def female_fit():
    ff = fit_of(SKF_PATH)
    fm = FIT0
    return dict(ax=ff["W"] / fm["W"], ay=ff["T"] / fm["T"], az=(ff["Bz"] - ff["Fz"]) / (fm["Bz"] - fm["Fz"]),
                dz=(ff["Bz"] + ff["Fz"]) / 2 - (fm["Bz"] + fm["Fz"]) / 2)


FIT_F = female_fit()


def inv_fit_scale(fit):
    """the map taking the female's real head space back into the model's nominal space (p' = (p - o) / s)"""
    return (1 / fit["ax"], 1 / fit["ay"], 1 / fit["az"], 0.0, 0.0, -fit["dz"] / fit["az"])


# ------------------------------------------------------------------------------------------- body proxy
BODY = SKD["body"]


def _smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def body_sdf(P):
    """Kit.Scalp's body proxy (neck capsule, trapezius ellipsoid, torso round box), vectorised"""
    P = np.atleast_2d(P)
    nc = BODY["neckCapsule"]
    a, b, r = np.array(nc["a"]), np.array(nc["b"]), nc["r"]
    ba = b - a
    t = np.clip(((P - a) @ ba) / (ba @ ba), 0, 1)
    d_neck = np.linalg.norm(P - (a + t[:, None] * ba), axis=1) - r
    tr = BODY["trapezius"]
    q = (P - np.array(tr["centre"])) / np.array(tr["radii"])
    k0 = np.linalg.norm(q, axis=1)
    d_trap = (k0 - 1) * min(tr["radii"])
    tb = BODY["torsoBox"]
    q = np.abs(P - np.array(tb["centre"])) - (np.array(tb["half"]) - tb["round"])
    d_box = np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(np.max(q, axis=1), 0) - tb["round"]
    return _smin(_smin(d_neck, d_trap, tr["blend"]), d_box, tb["blend"])


def body_push(P, margin):
    d = body_sdf(P)
    bad = d < margin
    if not bad.any():
        return P, bad
    e = 0.004
    Q = P[bad]
    g = np.stack([(body_sdf(Q + [e, 0, 0]) - body_sdf(Q - [e, 0, 0])),
                  (body_sdf(Q + [0, e, 0]) - body_sdf(Q - [0, e, 0])),
                  (body_sdf(Q + [0, 0, e]) - body_sdf(Q - [0, 0, e]))], axis=1) / (2 * e)
    g = unit(g)
    P = P.copy()
    P[bad] = Q + g * (margin - d[bad])[:, None]
    return P, bad


# ------------------------------------------------------------------------------------------- hairline
def _line(kind):
    ln = SKD["hairline"]["lines"][kind]
    hgt = np.array([e for e in ln["height"] if e], dtype=np.float64)
    pts = []
    for side in ("right", "left"):
        for e in ln[side]:
            if e and len(e) >= 4:
                pts.append(e[1:4])
    return hgt, np.array(pts, dtype=np.float64)


HL = {k: _line(k) for k in ("Natural", "Straight")}


def da_of(p):
    p = np.atleast_2d(p)
    return np.arctan2(np.abs(p[:, 0]), -(p[:, 2] - 0.05))


def hairline_y(da, kind="Natural"):
    hgt = HL[kind][0]
    return np.interp(np.abs(da), hgt[:, 0], hgt[:, 1])


def hair_inside(P, kind="Natural"):
    """signed distance (nominal studs) inside the hairline: + inside the hair region"""
    P = np.atleast_2d(P)
    pts = HL[kind][1]
    d = np.sqrt(((P[:, None, :] - pts[None, :, :]) ** 2).sum(-1)).min(1)
    inside = P[:, 1] > hairline_y(da_of(P), kind)
    return np.where(inside, d, -d)


EARS = [(np.array(SKD["ears"][s]["min"]) - EAR_CLEAR, np.array(SKD["ears"][s]["max"]) + EAR_CLEAR)
        for s in ("left", "right")]


def ear_push(p, r=0.0):
    """out of either ear's (grown) box (and r more): up over it or back behind it, whichever is nearer"""
    for lo, hi in EARS:
        lo, hi = lo - r, hi + r
        if np.all(p > lo) and np.all(p < hi):
            up = hi[1] - p[1]
            back = hi[2] - p[2]
            q = p.copy()
            # (never out sideways: that would cover the ear) up over it or back behind it
            if back < up:
                q[2] = hi[2]
            else:
                q[1] = hi[1]
            return q, True
    return p, False


# ------------------------------------------------------------------------------------------- scalp
def scalp_dir(d):
    th, az = SK.angles(d)
    return th, az


def on_scalp(p, off):
    """the point at height off above the skull under p (radially from the centre), and the outward normal"""
    th, az = SK.angles(p - C)
    th = min(th, SK.th[-1])
    return SK.point(th, az, off), SK.normal(th, az)


def rotate(v, axis, a):
    axis = unit(axis)
    return v * math.cos(a) + np.cross(axis, v) * math.sin(a) + axis * np.dot(axis, v) * (1 - math.cos(a))


# ------------------------------------------------------------------------------------------- ears
_EL, _ER = SKD["ears"]["left"], SKD["ears"]["right"]
EAR_TOP = max(_EL["max"][1], _ER["max"][1])
EAR_FRONT = min(_EL["min"][2], _ER["min"][2])
EAR_BACK = max(_EL["max"][2], _ER["max"][2])
EAR_RAW = [(np.array(_EL["min"]), np.array(_EL["max"])), (np.array(_ER["min"]), np.array(_ER["max"]))]


def y_over(r):
    """the lowest a braid's centre may run where it passes over an ear"""
    return EAR_TOP + EAR_CLEAR + r + 0.012


def z_pass(r):
    """behind this a braid may turn down behind the ear"""
    return EAR_BACK + EAR_CLEAR + r + 0.02


def ear_avoid(q, r, cls):
    """out of either (grown) ear box: forward for the braids in front of the ear, else up over it (front half)
    or back behind it (back half). Never out sideways (that would cover the ear)."""
    for lo, hi in EARS:
        lo2, hi2 = lo - r, hi + r
        if np.all(q > lo2) and np.all(q < hi2):
            q = q.copy()
            if cls == "front":
                q[2] = lo2[2]
            elif q[2] < (lo2[2] + hi2[2]) * 0.5 + 0.03:
                q[1] = hi2[1]
            else:
                q[2] = hi2[2]
    return q


def ear_dist(P):
    """min distance of points to either raw ear AABB (0 inside)"""
    P = np.atleast_2d(P)
    m = 9.0
    for lo, hi in EAR_RAW:
        d = np.linalg.norm(np.maximum(np.maximum(lo - P, P - hi), 0), axis=1)
        m = min(m, float(d.min()))
    return m




def resample(P, ds):
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    L = seg.sum()
    n = max(2, int(math.ceil(L / ds)) + 1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    s = np.linspace(0, L, n)
    return np.stack([np.interp(s, cum, P[:, k]) for k in range(3)], axis=1)


def arclen(P):
    return np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])


def at_s(P, S, s):
    return np.stack([np.interp(s, S, P[:, k]) for k in range(3)], axis=-1)


def adaptive_s(P, s0, s1, ds_min, ds_max, ang=math.radians(8)):
    """arc-length samples in [s0, s1] of the polyline P: dense where it bends, sparse where it runs straight"""
    S = arclen(P)
    ss = np.arange(s0, s1, ds_min * 0.5)
    if len(ss) < 2:
        return np.array([s0, s1])
    Q = at_s(P, S, ss)
    keep = [s0]
    acc_a, last = 0.0, s0
    for i in range(1, len(Q) - 1):
        a = Q[i] - Q[i - 1]
        b = Q[i + 1] - Q[i]
        cosv = np.dot(a, b) / max(1e-12, np.linalg.norm(a) * np.linalg.norm(b))
        acc_a += math.acos(max(-1, min(1, cosv)))
        if (acc_a > ang and ss[i] - last >= ds_min) or ss[i] - last >= ds_max:
            keep.append(ss[i])
            acc_a, last = 0.0, ss[i]
    if s1 - keep[-1] < ds_min * 0.4 and len(keep) > 1:
        keep[-1] = s1
    else:
        keep.append(s1)
    return np.array(keep)


# ------------------------------------------------------------------------------------------- braids
class BraidSpec:
    def __init__(self, **kw):
        self.__dict__.update(kw)


# box: parting size along the flow (same-lane roots are 2 boxes apart: brick lay); lane: lane spacing over the
# crown (a box is 2 lanes wide); s_pin: the length of every braid pinned flat to the scalp
BRAIDS = BraidSpec(key="braids", box=0.26, front_y_end=-0.74, lane=0.104, r=0.047, length_y=(-0.75, -0.85), flatten=0.8,
                   root_flat=0.5, sides=6, lobes=True, amp=0.28, back_groups=6, n_front=1, stiff=0.45, mass=1.3,
                   seed=11, root_len=0.04, slope=0.5, s_pin=0.34, ride=0.75, grav_back=0.0, hang_need=0.65, hang_side=1.5, fan_deg=40, lane_ymin=0.2, root_ymin=0.05)
BOX = BraidSpec(key="box_braids", box=0.13, front_y_end=-9.0, lane=0.064, r=0.0205, length_y=(-1.6, -1.74), flatten=0.84,
                root_flat=0.55, sides=4, lobes=False, amp=0.0, back_groups=5, n_front=3, stiff=0.4, mass=1.2,
                seed=23, root_len=0.025, slope=0.5, s_pin=0.19, ride=0.75, grav_back=0.1, hang_need=0.8, hang_side=1.0, fan_deg=80, lane_ymin=0.17, root_ymin=-0.05)
FAN_A = 1.6  # the parting lanes are the scalp's sections by planes through the line (0, -FAN_A, z)
DOWN = np.array([0, -1.0, 0])
DEBUG = bool(os.environ.get("BRAIDS_DEBUG"))
CHAIN_SPREAD = 0.35  # no swing chain's joint points may spread more than this in x or z


class Braid:
    pass


class Lane:
    pass


def plane_section(tp, A=FAN_A):
    """the skull table's section by the plane x = (y + A) tp, front (beta -150) over the top to the nape"""
    psi = math.atan(tp)
    up = np.array([math.sin(psi), math.cos(psi), 0.0])
    nrm = np.array([math.cos(psi), -math.sin(psi), 0.0])
    O = C - nrm * np.dot(C - np.array([0, -A, 0]), nrm)
    pts = []
    for beta in np.radians(np.linspace(-150, 200, 700)):
        d = up * math.cos(beta) + np.array([0, 0, 1.0]) * math.sin(beta)
        p = surface_on_ray(O, d)
        pts.append(p if p is not None else np.full(3, np.nan))
    return np.array(pts)


def lane_run(tp, ref, r):
    """the stretch of the plane section inside the natural hairline (inset 0.012), clear of the (grown) ears,
    that passes nearest ref; resampled at 0.01, ordered front to back"""
    pts = plane_section(tp)
    ok = ~np.isnan(pts[:, 0])
    ins = np.zeros(len(pts), bool)
    ins[ok] = hair_inside(pts[ok]) > 0.012
    for lo, hi in EARS:
        ins &= ~np.all((pts > lo - r - 0.004) & (pts < hi + r + 0.004), axis=1)
    best, bd = None, 9.0
    i = 0
    while i < len(pts):
        if not ins[i]:
            i += 1
            continue
        j = i
        while j + 1 < len(pts) and ins[j + 1]:
            j += 1
        seg = pts[i:j + 1]
        if len(seg) > 3:
            d = float(np.linalg.norm(seg - ref, axis=1).min())
            if d < bd:
                best, bd = seg, d
        i = j + 1
    if best is None or bd > 0.05:
        return None
    return resample(best, 0.01)


def fan_lanes(spec):
    """parting lanes: plane sections through the fan axis, spaced spec.lane apart along the coronal arc over
    the crown (lane 0 on the midline), down each side as far as lane_ymin (the lowest passes over the ear)"""
    phis = np.radians(np.linspace(0, 120, 1200))
    ref = np.array([SK.point(f, math.pi / 2) for f in phis])
    S = arclen(ref)
    lanes = {}
    k = 0
    while True:
        s = k * spec.lane
        if s > S[-1]:
            break
        p = at_s(ref, S, s)
        if p[1] < spec.lane_ymin:
            break
        for sg in ((1,) if k == 0 else (1, -1)):
            q = p * np.array([sg, 1, 1])
            tp = q[0] / (q[1] + FAN_A)
            P = lane_run(tp, q, spec.r)
            if P is None or arclen(P)[-1] < spec.box * 0.6:
                continue
            ln = Lane()
            ln.k, ln.tp, ln.P, ln.S = k * sg, tp, P, arclen(P)
            ln.N = np.array([on_scalp(x, 0)[1] for x in P])
            lanes[ln.k] = ln
        k += 1
    return lanes


def leave_index(ln, i0):
    """where a braid running down lane ln from sample i0 leaves the scalp: the skull turns under (normal
    pointing down) or it reaches the nape hairline"""
    for i in range(i0, len(ln.P)):
        if ln.S[i] - ln.S[i0] > 0.05 and (ln.N[i][1] < -0.3 or ln.P[i][1] < -0.25):
            return i
    return len(ln.P) - 1


def front_roots(spec):
    """sideburn roots (in front of the ear, inside the natural hairline): braids that hang straight down"""
    out = []
    n = spec.n_front
    if n <= 0:
        return out
    ys = np.linspace(0.13, 0.0, n) if n > 1 else [0.09]
    for sx in (1, -1):
        for y in ys:
            zmax = EAR_FRONT - EAR_CLEAR - spec.r - 0.006
            best = None
            for z in np.linspace(-0.2, zmax, 60):
                p, _n = on_scalp(np.array([sx * 0.38, y, z]) - C + C, 0)
                d = hair_inside(p)[0]
                if d > 0.012 + 0.3 * spec.r:
                    best = p if best is None or p[2] < best[2] else best
            if best is not None:
                q = best.copy()
                q[2] = min(zmax, best[2] + 0.004 + 0.4 * spec.r)
                out.append(on_scalp(q, 0)[0])
    return out


def profile(spec, s, r, L):
    """(across radius, flatten) at arc length s: the root is a small flat knot (55 % radius, flatter) reaching
    the full braid over root_len; the tip tapers over the last 0.1"""
    k = float(smooth(0.0, spec.root_len, s))
    w = r * (0.55 + 0.45 * k) * (1 - 0.45 * float(smooth(L - 0.1, L, s)))
    fl = spec.root_flat * (1 - k) + spec.flatten * k
    return w, fl


def trace_front(root, spec, r):
    """a sideburn braid: straight down the scalp in front of the ear (centre line on the skull surface)"""
    p, n = on_scalp(root, 0)
    pts = [p]
    for _ in range(200):
        g = np.array([0, -1.0, -0.06])
        d = unit(g - n * np.dot(g, n))
        q, n = on_scalp(p + d * 0.01, 0)
        q = ear_avoid(q, r, "front")
        q, n = on_scalp(q, 0)
        pts.append(q)
        p = q
        if p[1] < -0.1:
            break
    return resample(np.array(pts), 0.01)


def _pinned_pts(b, s_pin):
    S = arclen(b.surf)
    return b.surf[S <= s_pin]


def layout_braids(spec, rng):
    """roots on the parting grid: lane k carries rows of the same parity as k (brick lay), row i at
    s = s_first + i box from the lane's front hairline end; every braid runs back down its own lane (planes of
    one fan never cross) to where it leaves the scalp; plus the sideburn braids. Candidates are accepted front
    rows first; one whose pinned span (the first s_pin) would touch an accepted braid's pinned span (where the
    lanes converge: the temples, the nape) is moved back along its lane by a quarter box (twice at most) or
    dropped, so no braid has to stack over another inside its pinned span."""
    lanes = fan_lanes(spec)
    s_first = 0.013 + 0.6 * spec.r
    cands = []
    for k in sorted(lanes):
        ln = lanes[k]
        for row in range(abs(k) % 2, 40, 2):
            s = s_first + row * spec.box
            if s > ln.S[-1] - 0.05:
                break
            q = at_s(ln.P, ln.S, s)
            if q[1] < spec.root_ymin and abs(q[0]) < 0.2:
                continue  # (low on the back: covered by the braids hanging over it; they would pile up)
            cands.append((row, abs(k), k, s))
    cands.sort()

    def make(k, row, s):
        ln = lanes[k]
        i0 = int(np.searchsorted(ln.S, s))
        i1 = leave_index(ln, i0)
        b = Braid()
        b.cls, b.lane, b.row, b.s_root = "back", k, row, s
        b.r = spec.r * rng.uniform(0.94, 1.06)
        b.root = at_s(ln.P, ln.S, s)
        P = np.concatenate([[b.root], ln.P[i0:i1 + 1]])
        b.surf = P if len(P) > 2 else ln.P[max(0, i1 - 2):i1 + 1]
        return b

    braids, kd_pts, kd_r = [], [], []
    for p in front_roots(spec):
        b = Braid()
        b.cls, b.lane, b.row, b.s_root = "front", None, 50, 0.0
        b.r = spec.r * rng.uniform(0.94, 1.06)
        b.root = p
        b.surf = trace_front(p, spec, b.r)
        braids.append(b)
    dropped = 0
    for row, _ak, k, s in cands:
        ok = None
        for shift in (0.0, 0.25, 0.5):
            ss = s + shift * spec.box
            if ss > lanes[k].S[-1] - 0.05:
                break
            b = make(k, row, ss)
            mine = _pinned_pts(b, spec.s_pin)
            clash = False
            for o in braids:
                theirs = _pinned_pts(o, spec.s_pin)
                if len(theirs) == 0 or np.linalg.norm(o.root - b.root) > spec.s_pin * 2 + 0.2:
                    continue
                d = np.linalg.norm(mine[:, None, :] - theirs[None, :, :], axis=2).min()
                if d < 0.9 * (b.r + o.r):
                    clash = True
                    break
            if not clash:
                ok = b
                break
        if ok is None:
            dropped += 1
        else:
            braids.append(ok)
    for i, b in enumerate(braids):
        b.idx = i
        b.y_end = rng.uniform(min(spec.length_y), max(spec.length_y))
        if b.cls == "front":
            b.y_end = max(b.y_end, spec.front_y_end)
        b.s_off = rng.uniform(0, 1)  # plait phase (fraction of the texture's v repeat)
    print(f"  layout: {len(cands)} grid candidates, {dropped} dropped (pinned spans would touch)")
    return lanes, braids


def stack_scalp(braids, spec):
    """heights over the scalp. Every braid's first s_pin is pinned flat: its centre at clearance + its own half
    thickness (no stacking). After that, laid back rows first, a braid that runs over one already laid rises
    (ramped at `slope`) just enough to lie on it (ride: how far it may settle into it). Returns the number of
    pinned samples that overlap a braid laid before (they would intersect)."""
    order = sorted(braids, key=lambda b: (b.cls != "front", -b.s_root, b.idx))
    LQ, LH, LT, LW = [], [], [], []
    kd = None
    conflicts = 0
    for b in order:
        S = arclen(b.surf)
        TH, AZ, Q, N = [], [], [], []
        for p in b.surf:
            th, az = SK.angles(p - C)
            th = min(th, SK.th[-1])
            TH.append(th)
            AZ.append(az)
            Q.append(SK.point(th, az))
            N.append(SK.normal(th, az))
        Q, N = np.array(Q), np.array(N)
        L_guess = S[-1] + 1.0
        prof = [profile(spec, s, b.r, L_guess) for s in S]
        w = np.array([x[0] for x in prof])
        t = np.array([x[0] * x[1] for x in prof])
        base = CLEAR + 0.004 + t
        req = base.copy()
        if kd is not None:
            wmax = max(LW)
            for i in range(len(Q)):
                for (_co, j, _d) in kd.find_range(V(Q[i]), float(w[i] + wmax)):
                    dv = Q[i] - LQ[j]
                    lat = dv - N[i] * np.dot(dv, N[i])
                    ll = float(np.linalg.norm(lat))
                    lim = (w[i] + LW[j]) * 0.9
                    if ll < lim:
                        f = math.sqrt(max(0.0, 1 - (ll / lim) ** 2))
                        req[i] = max(req[i], LH[j] + (t[i] + LT[j]) * spec.ride * f)
        pinned = S < spec.s_pin
        conflicts += int(((req - base) > 0.35 * t)[pinned].sum())
        h = np.where(pinned, base, req)
        for _ in range(2):
            for i in range(1, len(h)):
                h[i] = max(h[i], h[i - 1] - spec.slope * (S[i] - S[i - 1]))
            for i in range(len(h) - 2, -1, -1):
                if not pinned[i]:
                    h[i] = max(h[i], h[i + 1] - spec.slope * (S[i + 1] - S[i]))
        h = np.minimum(h, base + 2.0 * (t + spec.r * spec.flatten) * spec.ride)
        for _ in range(3):
            hs = h.copy()
            hs[1:-1] = h[1:-1] * 0.5 + (h[:-2] + h[2:]) * 0.25
            h = np.where(pinned, base, np.maximum(hs, base))
        b.h = h
        b.sp = np.array([SK.point(TH[i], AZ[i], h[i]) for i in range(len(Q))])
        b.ring = b.row
        for i in range(len(Q)):
            LQ.append(Q[i])
            LH.append(h[i])
            LT.append(t[i])
            LW.append(w[i])
        kd = KDTree(len(LQ))
        for i, q in enumerate(LQ):
            kd.insert(V(q), i)
        kd.balance()
    return conflicts


def point_clear(p, r, colliders):
    """p pushed out of the head mesh, the ears, both torsos (r + 0.02), the body proxy (r + 0.025) and the
    skull table"""
    head = colliders["head"]
    for _ in range(6):
        moved = False
        q, hit = head.push(p, r + CLEAR + 0.004)
        if hit:
            p, moved = q, True
        for tc in colliders["torsos"]:
            q, hit = tc.push(p, r + 0.02)
            if hit:
                p, moved = q, True
        d = float(body_sdf(p)[0])
        need = r + 0.025
        if d < need:
            e = 0.004
            gg = unit(np.array([body_sdf(p + [e, 0, 0])[0] - body_sdf(p - [e, 0, 0])[0],
                                body_sdf(p + [0, e, 0])[0] - body_sdf(p - [0, e, 0])[0],
                                body_sdf(p + [0, 0, e])[0] - body_sdf(p - [0, 0, e])[0]]))
            p, moved = p + gg * (need - d), True
        for lo, hi in EARS:
            lo2, hi2 = lo - r, hi + r
            if np.all(p > lo2) and np.all(p < hi2):
                p = p.copy()
                if p[2] < (lo2[2] + hi2[2]) * 0.5:
                    p[2] = lo2[2]
                else:
                    p[2] = hi2[2]
                moved = True
        th_, az_ = SK.angles(p - C)
        if th_ < SK.th[-1] - 0.02:
            hh = SK.height(p)
            if hh < r + CLEAR + 0.004:
                p, moved = p + unit(p - C) * (r + CLEAR + 0.004 - hh), True
        if not moved:
            break
    return p


def front_clear(p, r, colliders):
    """a sideburn braid's hang: cleared like any other, but never pushed out sideways (no hook over the
    shoulder): x stays put and it slides forward and up over the collarbone instead"""
    q = point_clear(p, r, colliders)
    if np.allclose(q, p):
        return p
    q = q.copy()
    q[0] = p[0] if abs(q[0]) > abs(p[0]) else q[0]
    d = unit(np.array([0.0, 0.25, -1.0]))
    for _ in range(80):
        need = body_sdf(q)[0] < r + 0.025 or any(tc.signed(q)[0] < r + 0.02 for tc in colliders["torsos"])
        if not need:
            break
        q = q + d * 0.004
    return point_clear(q, r, colliders)


def outward(p):
    o = np.array([p[0], 0.0, p[2] - 0.03])
    return unit(o)


def hang_all(braids, spec, colliders):
    """each braid's hanging part as a gravity rope from where it leaves the scalp: its direction bends toward
    straight down (stiff braid: about 0.15 radius), it rests on the head, neck, shoulders and back 0.02-0.03 off
    them, and on the braids laid before it (inner rings first): a later braid only moves outward from the
    body over an earlier one, sideways at most half a radius; then the curve is smoothed"""
    order = sorted(braids, key=lambda b: (-b.ring, b.idx))
    # fan-out targets: the back braids, ranked by the azimuth (round the neck) where they leave the scalp, are
    # given evenly spread target azimuths over the back and shoulders, so they hang side by side (about two deep)
    # instead of piling up behind the neck
    back = [b for b in braids if b.cls != "front"]
    phi0 = {b.idx: math.atan2(b.sp[-1][0], b.sp[-1][2] - 0.03) + 1e-4 * b.row for b in back}
    ranked = sorted(back, key=lambda b: phi0[b.idx])
    pm = math.radians(spec.fan_deg)
    target = {b.idx: (-pm + 2 * pm * (i + 0.5) / len(ranked)) for i, b in enumerate(ranked)}
    HP, HR = [], []
    kd = None
    ds = 0.03
    for b in order:
        r = b.r
        p = b.sp[-1].copy()
        y_leave = p[1]
        t = unit(b.sp[-1] - b.sp[-3])
        pts = [p.copy()]
        L = 0.0
        Lmax = 1.6 * (p[1] - b.y_end) + 0.3
        rmax = max(HR) if HR else r
        gdir = unit(DOWN + np.array([0, 0, -0.08 if b.cls == "front" else spec.grav_back]))
        while p[1] > b.y_end and L < Lmax:
            t = unit(t + gdir * 0.2)
            if b.idx in target:
                phi = math.atan2(p[0], p[2] - 0.03)
                e = max(-0.6, min(0.6, target[b.idx] - phi))
                wgt = float(smooth(0.0, 0.25, y_leave - p[1]))
                tang = np.array([math.cos(phi), 0.0, -math.sin(phi)])
                t = unit(t + tang * e * 0.35 * wgt)
            q = p + t * ds
            for _it in range(4):
                q = front_clear(q, r, colliders) if b.cls == "front" else point_clear(q, r, colliders)
                if kd is not None:
                    push = np.zeros(3)
                    side_used = 0.0
                    for (_co, j, _d) in kd.find_range(V(q), float(r + rmax)):
                        pj = HP[j]
                        need = (r + HR[j]) * spec.hang_need
                        if abs(q[1] - pj[1]) > need:
                            continue
                        dv = q - pj
                        dv[1] = 0
                        ll = float(np.linalg.norm(dv))
                        if ll >= need:
                            continue
                        o = outward(q)
                        dn = dv / ll if ll > 1e-6 else o
                        rad = float(np.dot(dn, o))
                        tang = dn - o * rad
                        push += o * (need - ll) * max(rad, 0.45) * 0.75
                        tn = float(np.linalg.norm(tang))
                        if tn > 1e-6 and side_used < spec.hang_side * r:
                            st = min((need - ll) * tn, spec.hang_side * r - side_used)
                            push += tang / tn * st
                            side_used += st
                    q = q + push
                q = p + unit(q - p) * ds
            t = unit(q - p)
            p = q
            pts.append(p.copy())
            L += ds
        H = np.array(pts)
        for _ in range(10):
            H[2:-1] = H[2:-1] * 0.5 + (H[1:-2] + H[3:]) * 0.25
            H[-1] = H[-1] * 0.5 + H[-2] * 0.5 + (H[-1] - H[-2]) * 0.5
            for i in range(2, len(H)):
                H[i] = front_clear(H[i], r, colliders) if b.cls == "front" else point_clear(H[i], r, colliders)
        b.hang = H
        for q in H[1:]:
            HP.append(q)
            HR.append(r)
        kd = KDTree(len(HP))
        for i, q in enumerate(HP):
            kd.insert(V(q), i)
        kd.balance()


def build_braids(spec, colliders):
    rng = np.random.default_rng(spec.seed)
    t0 = time.time()
    lanes, braids = layout_braids(spec, rng)
    n_front = sum(b.cls == "front" for b in braids)
    print(f"  {spec.key}: {len(lanes)} lanes, {len(braids)} braids ({n_front} sideburn) ({time.time() - t0:.1f}s)")
    conflicts = stack_scalp(braids, spec)
    for b in braids:
        S = arclen(b.sp)
        b.sp = np.array([point_clear(q, b.r * spec.flatten, colliders) if S[i] > spec.s_pin else q
                         for i, q in enumerate(b.sp)])
    print(f"  scalp stacking {time.time() - t0:.1f}s, pinned-span overlaps {conflicts}")
    hang_all(braids, spec, colliders)
    for b in braids:
        b.P = np.concatenate([b.sp, b.hang[1:]])
        b.n_scalp = len(b.sp)
    print(f"  hang {time.time() - t0:.1f}s")
    return lanes, braids, conflicts


# ------------------------------------------------------------------------------------------- tube sweep
def u_of(a):
    """single wrap, mirrored at the back: the front half (a in -pi/2..pi/2 from the outward axis) maps the
    plait strip across once (left edge u 0 .. right edge u 1), the back half mirrors it"""
    a = (a + math.pi / 2) % TAU - math.pi / 2
    return (a + math.pi / 2) / math.pi if a <= math.pi / 2 else 1 - (a - math.pi / 2) / math.pi


def braid_rings(spec, b):
    """ring samples (arc lengths) of the whole braid and the indices where it splits into pieces: thick plaits
    a ring every quarter plait period over the scalp, every third along the hang; thin braids adaptive"""
    P = b.P
    S = arclen(P)
    L = S[-1]
    s_leave = S[b.n_scalp - 1]
    s_mid = s_leave + (L - s_leave) * 0.48
    if spec.lobes:
        per = math.pi * b.r
        a = np.arange(0, s_leave, per / 4)
        bb = np.arange(s_leave, L, per / 3)
        ss = np.concatenate([a, bb, [L]])
        ss = np.unique(np.round(ss, 6))
        if L - ss[-2] < per / 8:
            ss = np.delete(ss, -2)
        cut0 = int(np.argmin(np.abs(ss - s_leave)))
        ss[cut0] = s_leave
        cut1 = int(np.argmin(np.abs(ss - s_mid)))
        if cut1 <= cut0:
            cut1 = cut0 + 1
        ss[cut1] = s_mid
        cut = [cut0, cut1]
    else:
        a = adaptive_s(P, 0, s_leave, 0.04, 0.13, ang=math.radians(10))
        a = np.unique(np.concatenate([a, [min(spec.root_len, s_leave * 0.5)]]))
        bb = adaptive_s(P, s_leave, s_mid, 0.05, 0.42, ang=math.radians(14))
        c = adaptive_s(P, s_mid, L, 0.05, 0.42, ang=math.radians(14))
        ss = np.concatenate([a, bb[1:], c[1:]])
        cut = [len(a) - 1, len(a) + len(bb) - 2]
    return ss, cut, L


def emit_braid(spec, b, pieces_by_part, strip, base_shade=1.0):
    """sweeps braid b into the pieces (scalp part, upper hang, lower hang), one flattened tube: flat side against
    the scalp / body, plait lobes in the silhouette (thick braids: alternate sides, notch = amp x radius, the
    texture's lobes locked to them, a random phase per braid), u once round (mirrored), v by arc length (v repeat =
    2 plait periods), a small flat knot at the root that dips to the scalp, a sealed tapered tip"""
    ss, cut, L = braid_rings(spec, b)
    P = b.P
    S = arclen(P)
    C_ = at_s(P, S, ss)
    n = len(ss)
    T = np.zeros_like(C_)
    T[0] = C_[1] - C_[0]
    T[-1] = C_[-1] - C_[-2]
    T[1:-1] = C_[2:] - C_[:-2]
    T = unit(T)
    s_leave = ss[cut[0]]
    per = math.pi * b.r
    v_tile = 2 * per
    s_off = b.s_off * v_tile
    sides = spec.sides
    ring_data = []
    for i in range(n):
        s = ss[i]
        th, az = SK.angles(C_[i] - C)
        Us = SK.normal(min(th, SK.th[-1]), az)
        if s <= s_leave + 1e-9:
            U = Us
        else:
            k = float(smooth(s_leave, s_leave + 0.18, s))
            U = unit(Us * (1 - k) + outward(C_[i]) * k)
        nr = unit(U - T[i] * np.dot(U, T[i]))
        bi = unit(np.cross(T[i], nr))
        w, fl = profile(spec, s, b.r, L)
        if spec.lobes:
            psi = math.pi * (s + s_off) / per
            amp = spec.amp * float(smooth(0.02, spec.root_len + 0.04, s)) * (1 - float(smooth(L - 0.08, L, s)))
            eL = 1 - amp + amp * abs(math.sin(psi))
            eR = 1 - amp + amp * abs(math.cos(psi))
            w = w / (1 - 0.36 * spec.amp)
        else:
            eL = eR = 1.0
        verts = []
        for k in range(sides):
            a = -math.pi / 2 + TAU * k / sides
            sa, ca = math.sin(a), math.cos(a)
            E = eL * (1 - sa) / 2 + eR * (1 + sa) / 2
            pos = C_[i] + nr * ca * w * fl + bi * sa * w * E
            nn = unit(nr * ca / fl + bi * sa)
            uu = u_of(a)
            uu = strip[0] + 0.006 + (strip[1] - strip[0] - 0.012) * uu
            sh = base_shade * (0.78 + 0.22 * (ca * 0.5 + 0.5))
            verts.append((pos, nn, (uu, (s + s_off) / v_tile), (sh, sh, sh)))
        ring_data.append(verts)
    parts = [(0, cut[0]), (cut[0], cut[1]), (cut[1], n - 1)]
    for pi_, (i0, i1) in enumerate(parts):
        piece = pieces_by_part[pi_]
        if piece is None or i1 <= i0:
            continue
        ids = []
        for i in range(i0, i1 + 1):
            ids.append([piece.vert(*vd) for vd in ring_data[i]])
        for i in range(len(ids) - 1):
            r0, r1 = ids[i], ids[i + 1]
            for k in range(sides):
                k2 = (k + 1) % sides
                piece.quad(r0[k], r0[k2], r1[k2], r1[k])
        if pi_ == 0:
            # root: the knot closes onto a point lying on the scalp just in front of the first ring
            w0 = profile(spec, 0.0, b.r, L)[0]
            c0 = C_[0] - T[0] * w0 * 0.7
            th, az = SK.angles(c0 - C)
            c0 = SK.point(th, az, CLEAR + 0.003)
            sh = 0.72 * base_shade
            nrm0 = SK.normal(min(th, SK.th[-1]), az)
            ci = piece.vert(c0, unit(nrm0 - T[0] * 0.5), ((strip[0] + strip[1]) / 2, (s_off - w0) / v_tile),
                            (sh, sh, sh))
            for k in range(sides):
                piece.tri(ids[0][(k + 1) % sides], ids[0][k], ci)
        if pi_ == 2:
            we = profile(spec, L, b.r, L)[0]
            ce = C_[-1] + T[-1] * we * 0.7
            sh = base_shade
            ci = piece.vert(ce, T[-1], ((strip[0] + strip[1]) / 2, (L + s_off + we) / v_tile), (sh, sh, sh))
            for k in range(sides):
                piece.tri(ids[-1][k], ids[-1][(k + 1) % sides], ci)
    return C_[cut[0]], C_[cut[1]], C_[-1]


def lane_point(lanes, k, j, s):
    """the scalp point at arc length s on lane j (the neighbour of lane k), or, where lane j does not exist or
    is shorter, the point mirrored across lane k from its other neighbour / offset sideways; s is clamped to
    lane k's length"""
    ln = lanes[k]
    s = min(s, ln.S[-1])
    pk = at_s(ln.P, ln.S, s)
    if j in lanes and s <= lanes[j].S[-1]:
        return at_s(lanes[j].P, lanes[j].S, s)
    jo = 2 * k - j
    if jo in lanes and s <= lanes[jo].S[-1]:
        q = 2 * pk - at_s(lanes[jo].P, lanes[jo].S, s)
    else:
        i = min(len(ln.P) - 2, int(np.searchsorted(ln.S, s)))
        t = unit(ln.P[i + 1] - ln.P[max(0, i - 1)])
        n = on_scalp(pk, 0)[1]
        side = unit(np.cross(n, t)) * (1 if j > k else -1)
        q = pk + side * (abs(j - k) * 0.5 * LANE_W[0])
    q = on_scalp(q, 0)[0]
    for _ in range(10):
        if hair_inside(q)[0] > 0.01 and ear_dist(q) > EAR_CLEAR + 0.004:
            break
        q = on_scalp(q + (pk - q) * 0.25, 0)[0]
    return q


LANE_W = [0.1]


def make_pads(spec, lanes, braids):
    """HairBase: the box partings. Every braid of the grid owns the box of its lane (two lanes wide, from the
    neighbouring lanes' centre lines) and its row (spec.box along the lane): a 3 x 3 patch lying flat at 0.024
    textured with one rounded-square pad of uniform short hair (texture "cornrow" pad strip, alpha feathered at
    its border), so the thin skin lines between neighbouring pads are the partings. The front row's boxes start
    on the hairline (inset 0.012, the lanes' ends); baby hairs (the baby strip) lie over that edge. Sideburn
    braids get a pad round their root. Triangles: pads first, then the baby hairs."""
    piece = hl.Piece("HairBase", "cornrow", material="Fabric", castShadow=False)
    rng = np.random.default_rng(spec.seed + 7)
    LANE_W[0] = spec.lane
    m = 3
    for b in braids:
        ids = []
        patch = int(rng.integers(0, 4))
        flip = bool(rng.integers(0, 2))
        if b.cls == "back":
            k = b.lane
            s0 = b.row * spec.box
            s1 = s0 + spec.box
            grid = []
            for i in range(m):
                s = s0 + (s1 - s0) * i / (m - 1)
                grid.append([lane_point(lanes, k, k - 1, s), at_s(lanes[k].P, lanes[k].S, min(s, lanes[k].S[-1])),
                             lane_point(lanes, k, k + 1, s)])
        else:
            q0, n0 = on_scalp(b.root, 0)
            d = unit(b.surf[min(4, len(b.surf) - 1)] - b.surf[0])
            side = unit(np.cross(n0, d))
            size = spec.box * 0.9
            grid = []
            for i in range(m):
                row = []
                for j in range(m):
                    p = q0 + d * (i / (m - 1) - 0.3) * size + side * (j / (m - 1) - 0.5) * size
                    for _ in range(10):
                        if hair_inside(p)[0] > 0.01 and ear_dist(p) > EAR_CLEAR + 0.004:
                            break
                        p = p + (q0 - p) * 0.25
                    row.append(p)
                grid.append(row)
        for i in range(m):
            row = []
            for j in range(m):
                pp, nn = on_scalp(grid[i][j], CLEAR + 0.0012)
                uu = PAD[0] + 0.004 + (PAD[1] - PAD[0] - 0.008) * (1 - j / (m - 1) if flip else j / (m - 1))
                vv = (patch + 0.01 + 0.98 * i / (m - 1)) / 4
                edge = max(abs(i / (m - 1) - 0.5), abs(j / (m - 1) - 0.5)) * 2
                sh = 0.8 - 0.1 * edge
                row.append(piece.vert(pp, nn, (uu, vv), (sh, sh, sh)))
            ids.append(row)
        for i in range(m - 1):
            for j in range(m - 1):
                piece.quad(ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j])
    # baby hairs along the front hairline (forehead and temples): at every lane's front end, cards lying flat,
    # roots just inside the pad edge, tips forward over it
    for k in sorted(lanes):
        ln = lanes[k]
        if ln.P[0][2] > -0.18:
            continue
        q0, nn = on_scalp(ln.P[0], 0)
        t0 = unit(ln.P[3] - ln.P[0])
        t0 = unit(t0 - nn * np.dot(t0, nn))
        side = unit(np.cross(t0, nn))
        for kk in (-1, 0, 1):
            ang = kk * 0.35 + rng.uniform(-0.15, 0.15)
            dirn = unit(-t0 * math.cos(ang) + side * math.sin(ang))
            base = q0 + t0 * 0.014 + side * kk * spec.lane * 0.33
            pts_c, ups = [], []
            for tt in np.linspace(0, 1, 3):
                p = base + dirn * 0.026 * tt
                hi = hair_inside(p)[0]
                if hi < 0.0:
                    p = p + t0 * (-hi)
                pp, n2 = on_scalp(p, CLEAR + 0.0022)
                pts_c.append(pp)
                ups.append(n2)
            u0 = BABY[0] + rng.uniform(0.002, 0.004)
            piece.card(pts_c, [spec.lane * 0.42] * 3, ups, (u0, u0 + 0.118), v0=0.02, v1=0.55,
                       shade=lambda t: (0.85, 0.85, 0.85), double=False)
    return piece


def guide_curves(braids, coll, name, attr="P"):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    for b in braids:
        P = getattr(b, attr)
        sp = cu.splines.new("POLY")
        sp.points.add(len(P) - 1)
        for i, p in enumerate(P):
            sp.points[i].co = (p[0], p[1], p[2], 1.0)
            sp.points[i].radius = b.r * 20
    ob = bpy.data.objects.new(name, cu)
    cu.bevel_depth = 0.0
    coll.objects.link(ob)
    return ob



def _spread(pts):
    pts = np.asarray(pts)
    return float(max(np.ptp(pts[:, 0]), np.ptp(pts[:, 2])))


def chain_groups(braids, joints, n_back):
    """swing chains. The sideburn braids get one chain per side (pivot near their roots). The rest are cut into
    n_back chains of contiguous azimuth round the neck (by where they leave the scalp), the cut chosen (dynamic
    programming) to minimise the largest spread of a chain's joint points in x or z."""
    groups = []
    for sx in (-1, 1):
        g = [b.idx for b in braids if b.cls == "front" and np.sign(b.root[0]) == sx]
        if g:
            groups.append(g)
    back = [b for b in braids if b.cls != "front"]
    az = np.array([math.atan2(joints[b.idx][0][0], joints[b.idx][0][2] - 0.03) for b in back])
    order = [back[i].idx for i in np.argsort(az)]
    n = len(order)
    G = min(n_back, n)
    cost = {}

    def spread(i, j):
        if (i, j) not in cost:
            pts = [p for bi in order[i:j] for p in joints[bi]]
            cost[(i, j)] = _spread(pts)
        return cost[(i, j)]
    INF = 9.0
    best = [[INF] * (n + 1) for _ in range(G + 1)]
    cut = [[0] * (n + 1) for _ in range(G + 1)]
    best[0][0] = 0.0
    for g in range(1, G + 1):
        for j in range(g, n + 1):
            for i in range(g - 1, j):
                if best[g - 1][i] >= INF:
                    continue
                v = max(best[g - 1][i], spread(i, j))
                if v < best[g][j]:
                    best[g][j], cut[g][j] = v, i
    j = n
    segs = []
    for g in range(G, 0, -1):
        i = cut[g][j]
        segs.append(order[i:j])
        j = i
    groups += segs[::-1]
    return groups


def make_pieces(spec, lanes, braids):
    """HairTop (every scalp part) + HairBase (box partings, baby hairs) + per chain BraidNN: HairBraidNN (upper
    hang) / HairBraidNNb (lower hang). Asserts that no chain's joint points spread more than CHAIN_SPREAD in x or
    z and that the sideburn chains stay on one side of the head."""
    top = hl.Piece("HairTop", "braid", material="Fabric", castShadow=True)
    # first pass: joints of every braid (emitting into throwaway pieces)
    joints = {}
    for b in braids:
        tmp = [hl.Piece("t", "braid"), hl.Piece("t", "braid"), hl.Piece("t", "braid")]
        joints[b.idx] = emit_braid(spec, b, tmp, PLAIT)
    groups = chain_groups(braids, joints, spec.back_groups)
    for g in groups:
        J = np.array([p for bi in g for p in joints[bi]])
        print("   chain", len(g), "x", np.round([J[:, 0].min(), J[:, 0].max()], 2), "z",
              np.round([J[:, 2].min(), J[:, 2].max()], 2))
    segs, jn = {}, {}
    order_emit = sorted(braids, key=lambda b: (b.cls != "front", -b.s_root, b.idx))  # inner (laid first) first
    group_of = {bi: g for g, mem in enumerate(groups) for bi in mem}
    for b in order_emit:
        g = group_of[b.idx]
        n1, n2 = f"HairBraid{g + 1:02d}", f"HairBraid{g + 1:02d}b"
        single = b.cls == "front"  # the short sideburn braids swing as one segment
        for nm in ((n1,) if single else (n1, n2)):
            if nm not in segs:
                segs[nm] = hl.Piece(nm, "braid", material="Fabric", castShadow=True)
                jn[nm] = dict(piv=[], tip=[], g=g, seg=1 if nm == n1 else 2, side=set())
        if single:
            j0, j1, j2 = emit_braid(spec, b, [top, segs[n1], segs[n1]], PLAIT)
            jn[n1]["piv"].append(j0)
            jn[n1]["tip"].append(j2)
        else:
            j0, j1, j2 = emit_braid(spec, b, [top, segs[n1], segs[n2]], PLAIT)
            jn[n1]["piv"].append(j0)
            jn[n1]["tip"].append(j1)
            jn[n2]["piv"].append(j1)
            jn[n2]["tip"].append(j2)
        jn[n1]["side"].add(b.cls)
    pieces = [top, make_pads(spec, lanes, braids)]
    spreads = {}
    for nm in sorted(segs):
        p = segs[nm]
        j = jn[nm]
        sp = _spread(j["piv"] + j["tip"])
        spreads[nm] = round(sp, 3)
        assert DEBUG or sp <= CHAIN_SPREAD, f"{spec.key}: chain piece {nm} joint points spread {sp:.3f} > {CHAIN_SPREAD}"
        if "front" in jn[nm[:11]]["side"]:
            xs = np.array(j["piv"] + j["tip"])[:, 0]
            assert xs.min() > 0.05 or xs.max() < -0.05, f"{spec.key}: sideburn chain {nm} crosses the midline"
        fx = {"kind": "swing", "chain": f"Braid{j['g'] + 1:02d}", "seg": j["seg"], "stiff": spec.stiff,
              "mass": spec.mass if j["seg"] == 1 else round(spec.mass * 0.8, 3),
              "pivot": [round(float(x), 4) for x in np.mean(j["piv"], axis=0)],
              "tip": [round(float(x), 4) for x in np.mean(j["tip"], axis=0)]}
        if j["seg"] == 2:
            fx["parent"] = f"HairBraid{j['g'] + 1:02d}"
        p.meta["hairfx"] = fx
        p.meta["length"] = "hang"
        p.meta["hideUnder"] = {"headgear": False, "hood": True}
        pieces.append(p)
    assert len(pieces) <= 16, f"{spec.key}: {len(pieces)} pieces"
    return pieces, spreads


# ------------------------------------------------------------------------------------------- Blender passes
def piece_object(piece, coll, name=None):
    me = bpy.data.meshes.new(name or piece.name)
    me.from_pydata([tuple(p) for p in piece.P], [], [tuple(t) for t in piece.T])
    me.update()
    ob = bpy.data.objects.new(name or piece.name, me)
    coll.objects.link(ob)
    return ob


def head_object(coll, path=None, name="head_m (collider)"):
    P, F = load_obj_mesh(path or os.path.join(REF, "head_m.obj"), "Head")
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in P], [], F)
    me.update()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def shrinkwrap_clearance(piece, head_ob, coll, offset=CLEAR, head=None):
    """Blender Shrinkwrap (nearest surface point, "outside" mode) against the game head mesh: every
    vertex closer than `offset` to the head (or inside it) is moved out to `offset`; the rest stay. Limited by
    a vertex group to the vertices that need it, away from the ears (in the crease behind an ear the nearest
    surface is ambiguous and a vertex would be thrown onto the ear). Reads the evaluated positions back."""
    ob = piece_object(piece, coll, piece.name + "_sw")
    vg = ob.vertex_groups.new(name="needs_clearance")
    P0 = np.asarray(piece.P)
    sel = []
    for i, p in enumerate(P0):
        near_ear = any(np.all((p > lo - 0.06) & (p < hi + 0.06)) for lo, hi in EARS)
        if not near_ear and (head is None or head.signed(p)[0] < offset):
            sel.append(i)
    if not sel:
        bpy.data.objects.remove(ob)
        return 0
    vg.add(sel, 1.0, "REPLACE")
    m = ob.modifiers.new("clearance", "SHRINKWRAP")
    m.vertex_group = vg.name
    m.target = head_ob
    m.wrap_method = "NEAREST_SURFACEPOINT"
    m.wrap_mode = "OUTSIDE"
    m.offset = offset
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    P = np.array([v.co[:] for v in me.vertices])
    ev.to_mesh_clear()
    moved = int((np.linalg.norm(P - np.asarray(piece.P), axis=1) > 1e-6).sum())
    piece.P = [tuple(p) for p in P]
    bpy.data.objects.remove(ob)
    return moved


def bake_ao(pieces, extra, rays=6, dist=0.16, lo=0.5, seed=5):
    """ambient occlusion into the vertex colours: rays from each vertex over its normal's hemisphere against
    every hair piece plus the head and torso (BVH); inner braids, the undersides against the neck and the
    scalp-side faces come out darker"""
    rng = np.random.default_rng(seed)
    allP, allF = [], []
    base = 0
    for p in pieces:
        allP += p.P
        allF += [(a + base, b + base, c + base) for a, b, c in p.T]
        base += p.nv
    for (P, F) in extra:
        allP += [tuple(x) for x in P]
        allF += [(a + base, b + base, c + base) for a, b, c in F]
        base += len(P)
    bvh = BVHTree.FromPolygons(allP, allF)
    dirs = unit(rng.normal(0, 1, (rays, 3)))
    for p in pieces:
        P = np.asarray(p.P)
        N = np.asarray(p.N)
        C_ = []
        for i in range(len(P)):
            n = N[i]
            o = P[i] + n * 0.004
            occ = 0.0
            for d in dirs:
                d2 = d if np.dot(d, n) > 0 else -d
                d2 = unit(d2 * 0.7 + n * 0.5)
                loc, _nn, _ii, dd = bvh.ray_cast(V(o), V(d2), dist)
                if loc is not None:
                    occ += 1.0 - dd / dist
            occ /= rays
            k = 1.0 - (1.0 - lo) * min(1.0, occ * 1.6)
            c = p.C[i]
            C_.append((c[0] * k, c[1] * k, c[2] * k, c[3]))
        p.C = C_


# ------------------------------------------------------------------------------------------- checks
def clearance(pieces, head, fit=None, sample=10**9, ymin=None):
    """min distance of any vertex to the head surface and how many are inside it (optionally after a fit)"""
    mind, inside = 9.0, 0
    for p in pieces:
        P = np.asarray(p.P)
        if fit is not None:
            P = P * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]
        if ymin is not None:
            P = P[P[:, 1] > ymin]
        for q in P[:: max(1, len(P) // sample)]:
            sd, _, _ = head.signed(q)
            if sd < 0:
                inside += 1
            mind = min(mind, abs(sd) if sd >= 0 else -abs(sd))
    return mind, inside


def skull_height(pieces, skull, fit=None, sample=10**9, ymin=-0.32):
    """min radial height above the skull table of the vertices over the scalp (y > ymin)"""
    m = 9.0
    for p in pieces:
        P = np.asarray(p.P)
        if fit is not None:
            P = P * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]
        P = P[P[:, 1] > ymin]
        for q in P[:: max(1, len(P) // sample)]:
            th, az = skull.angles(q - skull.c)
            if th > skull.th[-1]:
                continue
            m = min(m, skull.height(q))
    return m


def ear_hits(pieces, fit=None):
    n = 0
    for p in pieces:
        P = np.asarray(p.P)
        if fit is not None:
            P = P * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]
        for lo, hi in EARS:
            lo2, hi2 = lo + (EAR_CLEAR - 0.012), hi - (EAR_CLEAR - 0.012)
            n += int(np.all((P > lo2) & (P < hi2), axis=1).sum())
    return n


def body_min(pieces, ymax=-0.5):
    m = 9.0
    for p in pieces:
        P = np.asarray(p.P)
        P = P[P[:, 1] < ymax]
        if len(P):
            m = min(m, float(body_sdf(P).min()))
    return m


# ------------------------------------------------------------------------------------------- blend file
def hair_material(name, tex_path, tint=(0.19, 0.13, 0.095)):
    img = bpy.data.images.load(tex_path, check_existing=True)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = img
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1
    nt.links.new(tx.outputs[0], mix.inputs[6])
    nt.links.new(vc.outputs[0], mix.inputs[7])
    tn = nt.nodes.new("ShaderNodeMix")
    tn.data_type = "RGBA"
    tn.blend_type = "MULTIPLY"
    tn.inputs[0].default_value = 1
    tn.inputs[7].default_value = (*tint, 1)
    nt.links.new(mix.outputs[2], tn.inputs[6])
    nt.links.new(tn.outputs[2], bs.inputs["Base Color"])
    nt.links.new(tx.outputs[1], bs.inputs["Alpha"])
    bs.inputs["Roughness"].default_value = 0.6
    m.blend_method = "HASHED"
    return m


def save_blend(key, pieces, guides_coll, path, head_name="m"):
    root = bpy.data.objects.new("GameSpace (Y up, -Z face)", None)
    bpy.context.scene.collection.objects.link(root)
    root.rotation_euler = (math.pi / 2, 0, math.pi)
    for ob in list(guides_coll.objects):
        ob.parent = root
        ob.hide_render = True
    mats = {}
    hc = bpy.data.collections.new("hair (game pieces)")
    bpy.context.scene.collection.children.link(hc)
    for p in pieces:
        if p.tex not in mats:
            mats[p.tex] = hair_material(f"hair_{p.tex}", os.path.join(TEX_DIR, f"hair_{p.tex}.png"))
        ob = hl.to_blender(p, bpy, material=mats[p.tex], collection=hc)
        ob.parent = root
    ref = bpy.data.collections.new("reference")
    bpy.context.scene.collection.children.link(ref)
    for nm, obj in ((f"head_{head_name}.obj", "Head"), (f"torso_{head_name}.obj", "UpperTorso")):
        P, F = load_obj_mesh(os.path.join(REF, nm), obj)
        me = bpy.data.meshes.new(nm)
        me.from_pydata([tuple(p) for p in P], [], F)
        ob = bpy.data.objects.new(nm + " (reference)", me)
        ref.objects.link(ob)
        ob.parent = root
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


# ------------------------------------------------------------------------------------------- renders
TINTS = {"black": (0.09, 0.078, 0.07), "darkbrown": (48 / 255, 33 / 255, 24 / 255),
         "blonde": (196 / 255, 156 / 255, 92 / 255)}
SKINS = {"mid": None, "deep": (0.2, 0.12, 0.08), "light": (0.72, 0.52, 0.4)}


def cap_standin(key, density, outdir, kind="Natural"):
    """a preview stand-in for the game's scalp cap with cut "full": the short tile repeated 8 x 4, alpha =
    tile alpha x the natural hairline's soft coverage x density (HairAssetKit.CapCoverage)"""
    from PIL import Image
    gw, gh = 256, 128
    th = (np.arange(gh) + 0.5) / gh * 2.2
    az = (np.arange(gw) + 0.5) / gw * TAU
    S = np.array([SK.point(min(t, SK.th[-1]), a) for t in th for a in az])
    e = hair_inside(S, kind)
    cov = (smooth(-0.012, 0.01, e) * density).reshape(gh, gw)
    W, H = 1024, 512
    cov = np.asarray(Image.fromarray((cov * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255
    tile = Image.open(os.path.join(TEX_DIR, "hair_short.png")).convert("RGBA").resize((W // 8, H // 4), Image.LANCZOS)
    t = np.tile(np.asarray(tile, np.float32) / 255, (4, 8, 1))
    t[..., 3] *= cov
    path = os.path.join(outdir, f"capstandin_{key}.png")
    Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)
    p = hl.Piece("HairCap", "short")
    n_th, n_az = 60, 96
    ids = {}
    for i in range(n_th + 1):
        for j in range(n_az + 1):
            t_ = min(i / n_th * 2.2, SK.th[-1])
            a_ = j / n_az * TAU
            d = SK.direction(t_, a_)
            ids[(i, j)] = p.vert(SK.point(t_, a_, 0.016), d, (j / n_az, i / n_th), (0.6, 0.6, 0.6))
    for i in range(n_th):
        for j in range(n_az):
            p.tri(ids[(i, j)], ids[(i, j + 1)], ids[(i + 1, j + 1)])
            p.tri(ids[(i, j)], ids[(i + 1, j + 1)], ids[(i + 1, j)])
    return p, path


def single_sided(piece):
    q = hl.Piece(piece.name, piece.tex)
    q.P, q.N, q.U, q.C = piece.P, piece.N, piece.U, piece.C
    P, N = np.asarray(piece.P), np.asarray(piece.N)
    seen = {}
    for t in piece.T:
        k = tuple(sorted(t))
        ng = np.cross(P[t[1]] - P[t[0]], P[t[2]] - P[t[0]])
        good = float(np.dot(ng, N[list(t)].sum(0))) >= 0
        if k not in seen or (good and not seen[k][1]):
            seen[k] = (t, good)
    q.T = [v[0] for v in seen.values()]
    return q


def render_style(key, pieces, cap, outdir, samples, looks, title=None):
    import render
    os.makedirs(outdir, exist_ok=True)
    sheets = []
    cap_piece, cap_tex = (cap_standin(key, cap[0], outdir, cap[1]) if cap and cap[0] > 0 else (None, None))
    for (head_name, tint_name, skin_name, views) in looks:
        tint = TINTS[tint_name]
        sc = render.Scene(res=(520, 620), samples=samples, focus=(0.0, -0.05, 0.02), dist=4.9)
        # (speed: adaptive sampling, fewer diffuse / glossy bounces; the alpha stack keeps its 64 bounces)
        cy = sc.sc.cycles
        cy.use_adaptive_sampling = True
        cy.adaptive_threshold = 0.03
        cy.max_bounces = 4
        cy.diffuse_bounces = 2
        cy.glossy_bounces = 1
        cy.transmission_bounces = 2
        sc.sc.render.threads_mode = "AUTO"
        skin = SKINS[skin_name] or render.SKIN
        render.add_obj(sc, os.path.join(REF, f"head_{head_name}.obj"), tint=skin)
        for nm, md in render.load_obj(os.path.join(REF, f"torso_{head_name}.obj")).items():
            sc.add_mesh(dict(md, c=None), material="skin", tint=skin, name="torso")
        fit = FIT_F if head_name == "f" else None
        scl = (fit["ax"], fit["ay"], fit["az"]) if fit else (1, 1, 1)
        off = (0, 0, fit["dz"]) if fit else (0, 0, 0)
        if cap_piece is not None:
            sc.add_piece(cap_piece, texture=cap_tex, tint=tint, offset=off, scale=scl)
        for p in pieces:
            tex = os.path.join(TEX_DIR, f"hair_{p.tex}.png")
            ob = sc.add_piece(single_sided(p), texture=tex, tint=tint, offset=off, scale=scl)
            bs = ob.data.materials[0].node_tree.nodes["Principled BSDF"]
            # Roblox Fabric is matte: rough, low specular, no anisotropic streak
            bs.inputs["Roughness"].default_value = 0.72
            bs.inputs["Specular IOR Level"].default_value = 0.25
            bs.inputs["Anisotropic"].default_value = 0.0
        paths = []
        for v in views:
            path = os.path.join(outdir, f"{key}_{head_name}_{tint_name}_{v}.png")
            if v == "close":
                sc.render(path, view=(14, 6, 1.0), dist=2.3, focus=(0, 0.25, -0.2))
            elif v == "sideclose":
                sc.render(path, view=(70, 10, 1.0), dist=2.4, focus=(0, 0.25, -0.1))
            elif v == "top":
                sc.render(path, view=(0, 80, 1.0), dist=3.4, focus=(0, 0.3, 0.05))
            elif v == "top34":
                sc.render(path, view="top34", dist=3.6, focus=(0, 0.15, 0.02))
            else:
                sc.render(path, view=v)
            paths.append(path)
        sheets.append((paths, [f"{head_name} {tint_name} {v}" for v in views]))
    allp = [p for s in sheets for p in s[0]]
    alll = [lab for s in sheets for lab in s[1]]
    out = os.path.join(outdir, f"sheet_{key}.jpg")
    render.sheet(allp, out, cols=5, labels=alll,
                 title=title or f"{key} ({sum(p.nt for p in pieces)} tris, {len(pieces)} pieces)", cell=(312, 372))
    return out


def colliders_for(head="m"):
    hm = Collider(*load_obj_mesh(os.path.join(REF, "head_m.obj"), "Head"), name="head_m", radial=C)
    tm = Collider(*load_obj_mesh(os.path.join(REF, "torso_m.obj"), "UpperTorso"), name="torso_m")
    tf = Collider(*load_obj_mesh(os.path.join(REF, "torso_f.obj"), "UpperTorso", scale=inv_fit_scale(FIT_F)),
                  name="torso_f (model space)")
    return {"head": hm, "torsos": [tm, tf]}


# ------------------------------------------------------------------------------------------- cornrows
CORN = dict(n=10, axis=1.5, tan_max=0.205, width=0.07, ridge=0.021, v_tile=0.15, across=7, seed=31)


def surface_on_ray(o, d, t_hi=1.2):
    """the outermost skull point (radial table) on the ray o + t d"""
    t = t_hi
    if SK.height(o + d * t) < 0:
        return None
    step = 0.01
    while t > 0 and SK.height(o + d * t) > 0:
        t -= step
    if t <= 0:
        return None
    lo, hi = t, t + step
    for _ in range(30):
        m = (lo + hi) / 2
        if SK.height(o + d * m) > 0:
            hi = m
        else:
            lo = m
    return o + d * ((lo + hi) / 2)


def row_path(tpsi, spec, rng):
    """one row's centre line on the scalp: the plane x = (y + A) tan(psi) through the axis (0, -A, z),
    from the front hairline over the head to the nape hairline"""
    A = spec["axis"]
    psi = math.atan(tpsi)
    up = np.array([math.sin(psi), math.cos(psi), 0.0])
    nrm = np.array([math.cos(psi), -math.sin(psi), 0.0])  # plane normal
    O = C - nrm * np.dot(C - np.array([0, -A, 0]), nrm)  # skull centre projected into the plane
    pts = []
    for beta in np.radians(np.linspace(-140, 175, 640)):
        d = up * math.cos(beta) + np.array([0, 0, 1.0]) * math.sin(beta)
        p = surface_on_ray(O, d)
        if p is not None:
            pts.append(p)
    pts = np.array(pts)
    inside = hair_inside(pts, "Natural") > 0.012
    # the contiguous inside run through the top
    top = int(np.argmax(pts[:, 1]))
    a = top
    while a > 0 and inside[a - 1]:
        a -= 1
    b = top
    while b < len(pts) - 1 and inside[b + 1]:
        b += 1
    return resample(pts[a: b + 1], 0.012)


def build_cornrows(spec, colliders):
    """rows as arched ribbons on the scalp (texture "cornrow" row strip, alpha 0 at the row edges: the partings'
    skin shows between them). Each row starts at the hairline as a thin feed-in point (35 % width growing to full
    over 0.07, the v phase starting between two lobes) with a few crisp baby hairs laid over its start, and is
    tucked at the nape: it narrows to 30 % just above the nape hairline, no tails."""
    n = spec["n"]
    top = hl.Piece("HairTop", "cornrow", material="Fabric", castShadow=True)
    guides = []
    rows = []
    for i in range(n):
        tp = -spec["tan_max"] + 2 * spec["tan_max"] * i / (n - 1)
        rows.append((tp, row_path(tp, spec, None)))
    A = spec["axis"]
    k = spec["across"]
    for i, (tp, P) in enumerate(rows):
        S = arclen(P)
        L = S[-1]
        ss = adaptive_s(P, 0, L, 0.014, 0.03, ang=math.radians(5))
        Pc = at_s(P, S, ss)
        guides.append(Pc)
        ids = []
        v0 = 0.125 * spec["v_tile"]  # the row starts between two lobes
        for j, p in enumerate(Pc):
            s = ss[j]
            q, nn = on_scalp(p, 0)
            t = Pc[min(j + 1, len(Pc) - 1)] - Pc[max(j - 1, 0)]
            t = unit(t - nn * np.dot(t, nn))
            side = unit(np.cross(t, nn))
            w = spec["width"] * min(1.0, (p[1] + A) / (0.32 + A)) ** 1.5
            w *= 0.35 + 0.65 * float(smooth(0.0, 0.07, s))
            w *= 1.0 - 0.7 * float(smooth(L - 0.09, L, s))
            ridge = spec["ridge"] * (w / spec["width"])
            row = []
            for c in range(k):
                cc = c / (k - 1) * 2 - 1
                arch = (1 - cc * cc) ** 0.6
                pp, n2 = on_scalp(q + side * cc * w * 0.5, CLEAR + 0.004 + ridge * arch)
                nrm = unit(n2 + side * cc * 0.85)
                occ = 0.62 + 0.38 * arch
                uu = ROW[0] + 0.004 + (ROW[1] - ROW[0] - 0.008) * (c / (k - 1))
                row.append(top.vert(pp, nrm, (uu, (s + v0) / spec["v_tile"]), (occ, occ, occ)))
            ids.append(row)
        for j in range(len(ids) - 1):
            for c in range(k - 1):
                top.quad(ids[j][c], ids[j][c + 1], ids[j + 1][c + 1], ids[j + 1][c])
    # baby hairs: at each row's start two small cards lying flat on the skin, roots in the row, tips laid
    # forward over the hairline edge (crisp single strands from the baby strip)
    rng = np.random.default_rng(spec["seed"])
    for i, (tp, P) in enumerate(rows):
        q0, nn = on_scalp(P[0], 0)
        t0 = unit(P[4] - P[0])
        t0 = unit(t0 - nn * np.dot(t0, nn))
        side = unit(np.cross(t0, nn))
        w0 = spec["width"] * min(1.0, (P[0][1] + A) / (0.32 + A)) ** 1.5
        for kk in (-1, 1):
            ang = kk * rng.uniform(0.25, 0.45)
            dirn = unit(-t0 * math.cos(ang) + side * math.sin(ang))  # root -> tip: forward and a little out
            base = q0 + t0 * 0.02 + side * kk * w0 * 0.12
            pts_c, ups = [], []
            for tt in np.linspace(0, 1, 4):
                p = base + dirn * 0.028 * tt
                if hair_inside(p)[0] < 0.002:
                    p = p + t0 * (0.002 - hair_inside(p)[0])
                pp, n2 = on_scalp(p, CLEAR + 0.002)
                pts_c.append(pp)
                ups.append(n2)
            u0 = BABY[0] + rng.uniform(0.002, 0.004)
            top.card(pts_c, [w0 * 0.75] * 4, ups, (u0, u0 + 0.118), v0=0.02, v1=0.5,
                     shade=lambda t: (0.8, 0.8, 0.8), double=False)
    return [top], guides


# ------------------------------------------------------------------------------------------- styles / main
STYLES = {
    "braids": dict(kind="braids", spec=BRAIDS, head="f",
                   entry=dict(styles=["Braids"], types=None, cap={"cut": "full", "density": 0.15})),
    "box_braids": dict(kind="braids", spec=BOX, head="f",
                       entry=dict(styles=["Box Braids"], types=None, cap={"cut": "full", "density": 0.15})),
    "cornrows": dict(kind="cornrows", spec=CORN, head="m",
                     entry=dict(styles=["Cornrows"], types=None, cap={"cut": "full", "density": 0.15})),
}
NARROW = dict(ax=0.965, ay=1.0, az=1.0, dz=0.0)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def skull_collider(skull, sx=1.0):
    """the skull table as a closed-ish triangle mesh (x scaled by sx: the female-narrow skull) for true
    (euclidean) clearance measurements"""
    ths = np.radians(np.linspace(0, float(np.degrees(skull.th[-1])), 61))
    azs = np.radians(np.arange(0, 360, 3))
    P = [skull.point(0.0, 0.0)]
    for th in ths[1:]:
        for az in azs:
            P.append(skull.point(th, az))
    P = np.array(P) - skull.c
    P[:, 0] *= sx
    P += skull.c
    na = len(azs)
    F = [(0, 1 + (j + 1) % na, 1 + j) for j in range(na)]
    for i in range(len(ths) - 2):
        for j in range(na):
            a = 1 + i * na + j
            b = 1 + i * na + (j + 1) % na
            F.append((a, b, b + na))
            F.append((a, b + na, a + na))
    return Collider(P, F, name=f"skull x{sx}", radial=skull.c)


def build_style(key, colliders):
    st = STYLES[key]
    clear_scene()
    coll = bpy.data.collections.new("guides (Blender curves: braid centre lines)")
    bpy.context.scene.collection.children.link(coll)
    work = bpy.data.collections.new("work")
    bpy.context.scene.collection.children.link(work)
    t0 = time.time()
    info = {}
    if st["kind"] == "braids":
        lanes, braids, conflicts = build_braids(st["spec"], colliders)
        guide_curves(braids, coll, f"{key}_guides")
        pieces, spreads = make_pieces(st["spec"], lanes, braids)
        info.update(braids=len(braids), lanes=len(lanes), sideburn=sum(b.cls == "front" for b in braids),
                    pinned_overlaps=conflicts, chain_spread=spreads)
    else:
        pieces, guides = build_cornrows(st["spec"], colliders)

        class _G:
            def __init__(self, P):
                self.P, self.r = P, 0.03
        guide_curves([_G(g) for g in guides], coll, f"{key}_guides")
    head_ob = head_object(work)
    moved = {p.name: shrinkwrap_clearance(p, head_ob, work, head=colliders["head"]) for p in pieces}
    torso = load_obj_mesh(os.path.join(REF, "torso_m.obj"), "UpperTorso")
    head = load_obj_mesh(os.path.join(REF, "head_m.obj"), "Head")
    extra = [torso] + ([head] if st["kind"] == "braids" else [])
    bake_ao(pieces, extra, rays=6, dist=0.14 if st["kind"] == "braids" else 0.06, lo=0.5)
    bpy.data.collections.remove(work)
    print(f"  built {key}: {sum(p.nt for p in pieces)} tris, shrinkwrap moved {moved} ({time.time() - t0:.1f}s)")
    return pieces, coll, info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", default=SCRATCH, help="folder for the self-check renders ('' = none)")
    ap.add_argument("--only", default="")
    ap.add_argument("--no-tex", action="store_true")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--looks", type=int, default=2, help="looks (hair colour / skin) rendered per style")
    ap.add_argument("--views", default="", help="override the rendered views (comma list)")
    args = ap.parse_args()
    t0 = time.time()
    os.makedirs(TEX_DIR, exist_ok=True)
    if not args.no_tex or not all(os.path.exists(os.path.join(TEX_DIR, f"hair_{k}.png")) for k in ("braid", "cornrow")):
        braids_tex.build(TEX_DIR)
        print(f"textures braid, cornrow: {time.time() - t0:.1f}s")
    print("female fit", {k: round(v, 4) for k, v in FIT_F.items()})
    colliders = colliders_for()
    head_f = Collider(*load_obj_mesh(os.path.join(REF, "head_f.obj"), "Head"), name="head_f",
                      radial=np.array(hl.Skull(SKF_PATH).c))
    Pn, Fn = load_obj_mesh(os.path.join(REF, "head_m.obj"), "Head")
    head_n = Collider(Pn * [0.965, 1, 1], Fn, name="head_m x0.965", radial=C)
    skull_n = skull_collider(SK, 0.965)
    skf = hl.Skull(SKF_PATH)
    keys = [k for k in STYLES if not args.only or k in args.only.split(",")]
    report = {}
    for key in keys:
        print(f"style {key}")
        pieces, coll, info = build_style(key, colliders)
        st = STYLES[key]
        cm, ci = clearance(pieces, colliders["head"])
        cf, cfi = clearance(pieces, head_f, FIT_F)
        cn, cni = clearance(pieces, head_n, NARROW)
        sm = skull_height(pieces, SK)
        sf = skull_height(pieces, skf, FIT_F)
        sn, sni = clearance([p for p in pieces], skull_n, NARROW, ymin=-0.3)
        ed = min(ear_dist(np.asarray(p.P)) for p in pieces)
        eh = ear_hits(pieces)
        bm = body_min(pieces)
        entry = dict(st["entry"])
        entry["family"] = "braids"
        entry["texture_strips"] = {"braid": {"plait": list(PLAIT)}, "cornrow": {"row": list(ROW), "baby": list(BABY),
                                                                         "pad": list(PAD)}}
        entry["clearance"] = dict(head_m=round(cm, 4), head_f_fit=round(cf, 4), head_m_narrow=round(cn, 4),
                                  skull_m=round(sm, 4), skull_f_fit=round(sf, 4), skull_m_narrow=round(sn, 4),
                                  inside_m=ci, ear_box=round(ed, 4), body=round(bm, 4) if bm < 9 else None)
        entry["notes"] = "braids family (build_braids.py); clearance: nominal studs (narrow = x 0.965 head + fit)"
        od = os.path.join(hl.OUT, key)
        if os.path.isdir(od):  # (no stale meshes from an earlier piece layout)
            for fn in os.listdir(od):
                if fn.endswith(".mesh"):
                    os.remove(os.path.join(od, fn))
        data = hl.export_style(key, entry, pieces)
        save_blend(key, pieces, coll, os.path.join(BLEND_DIR, f"{key}.blend"), head_name=st["head"])
        rep = dict(styles=entry["styles"], types=entry["types"], cap=entry["cap"], tris=data["tris"],
                   pieces={p.name: dict(nt=p.nt, tex=p.tex, hairfx=p.meta.get("hairfx"))
                           for p in pieces}, clearance=entry["clearance"], inside_f=cfi, inside_narrow=cni,
                   skull_narrow_inside=sni, ear_hits=eh, **info)
        report[key] = rep
        print(json.dumps({k: v for k, v in rep.items() if k != "pieces"}))
        if args.render:
            views = args.views.split(",") if args.views else ["34", "side", "back", "close", "top34"]
            looks_all = {
                "f": [("f", "darkbrown", "deep", views), ("f", "blonde", "light", ["34"]),
                      ("f", "black", "mid", views)],
                "m": [("m", "black", "deep", views), ("m", "blonde", "light", ["34"]),
                      ("m", "darkbrown", "mid", views)],
            }[st["head"]][: max(1, args.looks)]
            cap = (st["entry"]["cap"]["density"], "Natural")
            sheet = render_style(key, pieces, cap, os.path.join(args.render, "renders"), args.samples, looks_all,
                                 title=f"{key}: {', '.join(st['entry']['styles'])}  ({data['tris']} tris, "
                                       f"{len(pieces)} pieces)")
            rep["sheet"] = sheet
            print("sheet", sheet)
    with open(os.path.join(args.render or SCRATCH, "report.json"), "w") as f:
        json.dump(report, f, indent=1)
    print(f"total {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
