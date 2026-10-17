"""Braids family hair: "Braids" (about two dozen thick three-strand plaits to the shoulders), "Box Braids"
(~90 thin plaits from square box partings, to mid back; the family's female default) and "Cornrows" (flat
plaited rows from the front hairline to the nape, scalp showing between them, short tails at the nape).
Modelled in Blender (bpy 4.2), exported with hairlib.

    /opt/bpyenv/bin/python tools/hair/build_braids.py [--render DIR] [--only braids,box_braids,cornrows]
                                                      [--no-tex] [--samples N] [--quick]

Writes tools/hair/textures/hair_braid.png + hair_cornrow.png (braids_tex.py), tools/hair/out/<key>/ (meshes +
style.json), tools/hair/blend/<key>.blend; renders self-check sheets with --render (default: the family's
scratchpad folder when run with no arguments).

How it is built (game nominal head space, numerically; CONTRACT.md):
* Partings. Box braids / braids: the scalp inside the natural hairline is split into concentric rings of
  constant distance from the hairline (offset curves of the hairline, traced on the skull from the point deepest
  inside it), each ring cut into boxes of the style's size, alternate rings offset by half a box (brick lay).
  One braid roots at every box centre; the gaps between the braids' flared roots are the partings, over the
  game's low-density cap.
* Guides. Every braid's guide is traced over the scalp along a combing field (straight back over the top,
  back over the ears and down behind them), rising as it travels (braids from the front lie over the ones
  rooted behind them), until the skull turns under (the occiput, behind the ears); from there it hangs.
* Drape (Blender mathutils: BVH trees of the game head mesh and both torsos, a KD tree of the braids). On the
  scalp, where two braids cross the one that has come further from its root rides over the other, braids side
  by side are pushed apart over the scalp, all kept 0.02+ above the head mesh and the skull table and clear of
  the ears (a braid that would cross an ear is left out). Where a braid leaves the head it bends to vertical
  and falls, sliding out / back past the neck, the shoulders and the back (the male torso, the female torso
  through the inverse of the female skull fit, and the Kit.Scalp body proxy: neck capsule, trapezius, torso
  box) without returning inward under a bulge it passed, as a stiff braid would not; hanging braids are then
  pushed apart sideways / back (the one nearer the body stays) and the guides smoothed.
* Geometry. The guides are kept as Blender curve objects in the .blend; they are resampled by curvature and
  swept into slightly flattened tubes (6 sides for the thick braids, 4 for box braids): the flat face against
  the scalp, a flat flared knot at the root, a tapered sealed tip, the plait texture wrapped twice round (u, the
  strip covers half the circumference) and tiled by arc length (v, square texels). A Shrinkwrap modifier
  ("outside" mode, limited by a vertex group to the vertices that need it, away from the ears) against the
  game head mesh guarantees the clearance, and ambient occlusion is baked into the vertex colours by BVH ray
  casts against all the hair, the head and the torso.
* Cornrows: rows lie in planes through an axis deep under the head (parallel front to back, the outer ones
  over the ears and behind them), clipped to the hairline; each row is a ribbon with an arched cross-section
  (the plait's crown), narrow where it starts at the hairline, full in the middle, narrowing into the nape where
  it turns into a short hanging plaited tail. Ribbon alpha (texture "cornrow") leaves the partings' skin.
* Pieces: a static scalp piece (HairTop: every braid's scalp part down to where it leaves the head) and the
  hanging parts in swing chains by sector round the head (HairBraidNN, HairBraidNNb = the lower half), as the
  generated hair does; each chain's pivot / tip are the means of its braids' joint points.
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
BABY = hl.ATLAS["cornrow"]["baby"]

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


# ------------------------------------------------------------------------------------------- partings
def ring_layout(box, kind="Natural", inset=None, brick=True, max_rings=12, seed=3):
    """box-parting roots: rings of constant distance from the hairline, each cut into boxes of size `box`,
    alternate rings offset by half a box. Returns a list of (point, ring index, along-ring tangent)."""
    rng = np.random.default_rng(seed)
    inset = box * 0.5 if inset is None else inset
    # the point deepest inside the hairline
    best, bestd = None, -1
    for th in np.radians(np.arange(0, 120, 3)):
        for az in np.radians(np.arange(0, 360, 6)):
            p = SK.point(th, az)
            d = hair_inside(p, kind)[0]
            if d > bestd:
                best, bestd = (th, az), d
    dM = SK.direction(*best)
    ref = np.array([1.0, 0, 0]) if abs(dM[0]) < 0.9 else np.array([0, 0, 1.0])
    e1 = unit(np.cross(dM, ref))
    e2 = np.cross(dM, e1)
    n_phi = 240
    phis = np.linspace(0, TAU, n_phi, endpoint=False)
    rhos = np.radians(np.linspace(0, 150, 600))
    # distance along each ray
    D = np.zeros((n_phi, len(rhos)))
    PTS = np.zeros((n_phi, len(rhos), 3))
    for i, ph in enumerate(phis):
        ax = unit(np.cos(ph) * e2 - np.sin(ph) * e1)  # rotation axis for this ray
        dirs = np.array([rotate(dM, ax, r) for r in rhos])
        pts = np.array([SK.point(*SK.angles(d)) for d in dirs])
        PTS[i] = pts
        D[i] = hair_inside(pts, kind)
    roots = []
    k = 0
    while k < max_rings:
        target = inset + k * box
        if target > bestd - box * 0.35:
            break
        ring = []
        for i in range(n_phi):
            d = D[i]
            j = np.where((d[:-1] >= target) & (d[1:] < target))[0]
            if len(j) == 0:
                continue
            j = j[0]
            t = (d[j] - target) / max(1e-9, d[j] - d[j + 1])
            ring.append(PTS[i, j] * (1 - t) + PTS[i, j + 1] * t)
        if len(ring) < 8:
            break
        ring = np.array(ring)
        seg = np.linalg.norm(np.roll(ring, -1, 0) - ring, axis=1)
        L = seg.sum()
        n = max(1, int(round(L / box)))
        cum = np.concatenate([[0], np.cumsum(seg)])
        off = (0.5 if (brick and k % 2) else 0.0) + rng.uniform(-0.1, 0.1)
        for m in range(n):
            s = ((m + off) / n % 1.0) * L
            j = int(np.searchsorted(cum, s) - 1)
            j = max(0, min(len(ring) - 1, j))
            t = (s - cum[j]) / max(1e-9, seg[j])
            a, b = ring[j], ring[(j + 1) % len(ring)]
            p = a * (1 - t) + b * t
            roots.append((p, k, unit(b - a)))
        k += 1
    # the last few at the centre
    if bestd - (inset + k * box) > -box * 0.35:
        roots.append((SK.point(*best), k, e1))
    return roots


# ------------------------------------------------------------------------------------------- combing field
def comb(p, n):
    """the direction a braid runs over the scalp at p (outward normal n): straight back over the top (round
    the X axis), back over the ears, down behind them"""
    r = p - C
    sag = np.cross(np.array([1.0, 0, 0]), r)
    ax = abs(p[0])
    side = float(smooth(0.12, 0.34, ax))
    ear = side * float(1 - smooth(0.2, 0.32, p[2])) * float(1 - smooth(0.16, 0.34, p[1]))
    back = np.array([0, 0, 1.0])
    down = np.array([0, -1.0, 0])
    d = unit(sag) * (1 - 0.6 * side) + side * (back * (0.9 + 1.4 * ear) + down * (0.7 * (1 - 0.9 * ear)))
    d = d - n * np.dot(d, n)
    return unit(d)


# ------------------------------------------------------------------------------------------- braids
class BraidSpec:
    def __init__(self, key, box, r, length_y, count_hint, sides, flatten, seed, lift, groups, stiff, mass,
                 root_flare, end_jitter, hang_ds, ds_top=(0.02, 0.06), ds_hang=0.14):
        self.__dict__.update(locals())
        del self.__dict__["self"]


BRAIDS = BraidSpec("braids", box=0.235, r=0.05, length_y=(-1.12, -1.3), count_hint=24, sides=6, flatten=0.82,
                   seed=11, lift=0.025, groups=6, stiff=0.45, mass=1.3, root_flare=1.3, end_jitter=0.06,
                   hang_ds=0.035)
BOX = BraidSpec("box_braids", box=0.13, r=0.022, length_y=(-1.62, -1.74), count_hint=90, sides=4, flatten=0.85,
                seed=23, lift=0.012, groups=7, stiff=0.4, mass=1.2, root_flare=1.35, end_jitter=0.05,
                hang_ds=0.04, ds_top=(0.04, 0.12), ds_hang=0.3)


def root_shape(spec, s, r=None):
    """(across radius, thickness) of the braid at arc length s from its root. The braid starts at the
    upstream edge of its box as a wide flat fan lying on the scalp (the box's hair gathered into the first
    crossings of the plait) and narrows to the full round-ish braid by ROOT_LEN(box)"""
    r = spec.r if r is None else r
    L = root_len(spec)
    k = float(smooth(0.0, L, s)) ** 0.8
    across = r * (spec.root_flare * (1 - k) + k)
    thick = r * (0.42 * (1 - k) + spec.flatten * k)
    return across, thick


def root_len(spec):
    return 0.03 + spec.r * 1.2


def lift_of(spec, s):
    return spec.lift * float(smooth(0.05, 0.6, s))


def trace_scalp(root, spec, rng, r=None):
    """the braid's path over the scalp from its root along the combing field; returns (points, normals,
    leave) where leave says it hangs from the last point"""
    r = spec.r if r is None else r

    def h_at(s):
        return CLEAR + 0.005 + root_shape(spec, s, r)[1] + lift_of(spec, s)
    # start at the box's upstream edge
    p0, n0 = on_scalp(root, 0)
    up = -comb(p0, n0)
    root = root + up * spec.r * 0.8
    p, n = on_scalp(root, h_at(0.0))
    pts, nrm = [p], [n]
    s = 0.0
    ds = 0.018
    leave = False
    jit = rng.normal(0, 0.12)
    for _ in range(400):
        d = comb(p, n)
        d = unit(d + np.cross(n, d) * jit * 0.3)
        q = p + d * ds
        s += ds
        q, n = on_scalp(q, h_at(s))
        q, _hit = ear_push(q, r * 1.15)
        pts.append(q)
        nrm.append(n)
        p = q
        # the skull turns under (the occiput, behind the ears, the nape): from here the braid hangs
        if s > 0.06 and (n[1] < -0.3 or (d[1] < -0.85 and n[1] < 0.05)):
            leave = True
            break
        if p[1] < -0.3:
            leave = True
            break
    return np.array(pts), np.array(nrm), s


def resample(P, ds):
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    L = seg.sum()
    n = max(2, int(math.ceil(L / ds)) + 1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    s = np.linspace(0, L, n)
    out = np.stack([np.interp(s, cum, P[:, k]) for k in range(3)], axis=1)
    return out


class Strand:
    def __init__(self, idx, root, ring, spec, rng):
        self.idx = idx
        self.ring = ring
        self.r = spec.r * rng.uniform(0.92, 1.08)
        sp, sn, s = trace_scalp(root, spec, rng, self.r)
        self.sp = resample(sp, 0.02)
        self.n_scalp = len(self.sp)
        self.scalp_s = s
        self.y_end = rng.uniform(min(spec.length_y), max(spec.length_y)) + rng.normal(0, spec.end_jitter * 0.3)
        self.s_al = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(self.sp, axis=0), axis=1))])
        self.th = np.array([root_shape(spec, sa, self.r)[1] for sa in self.s_al])
        self.sway = (rng.uniform(0, TAU), rng.uniform(2.0, 4.0), rng.uniform(0.006, 0.016), rng.uniform(0, TAU))


def point_clear(p, r, colliders, th=None, level=False):
    """p pushed out of the head mesh (ears too), both torsos and the body proxy. level: keep its height (a
    hanging braid only moves sideways / back as it passes the body), stepping back behind a ledge it lands on"""
    head = colliders["head"]
    y0 = p[1]
    for _ in range(6):
        moved = False
        q, hit = head.push(p, (th if th is not None else r) + CLEAR + 0.005)
        if hit:
            p, moved = q, True
        for tc in colliders["torsos"]:
            q, hit = tc.push(p, r + 0.012)
            if hit:
                p, moved = q, True
        d = float(body_sdf(p)[0])
        need = r + 0.014
        if d < need:
            e = 0.004
            gg = unit(np.array([body_sdf(p + [e, 0, 0])[0] - body_sdf(p - [e, 0, 0])[0],
                                body_sdf(p + [0, e, 0])[0] - body_sdf(p - [0, e, 0])[0],
                                body_sdf(p + [0, 0, e])[0] - body_sdf(p - [0, 0, e])[0]]))
            p, moved = p + gg * (need - d), True
        q, hit = ear_push(p, r)
        if hit:
            p, moved = q, True
        # the skull table too (the runtime fit is made on it): hanging hair near the head keeps r + 0.02 off it
        th_, az_ = SK.angles(p - C)
        if th_ < SK.th[-1] - 0.02:
            hh = SK.height(p)
            need = (th if th is not None else r) + 0.026
            if hh < need:
                p, moved = p + unit(p - C) * (need - hh), True
        if level and moved:
            dy = p[1] - y0
            if dy > 0.002:  # pushed up by a ledge (shoulder top): go behind it instead
                p = p + np.array([0, 0, 1.0]) * dy * 0.8 + np.array([math.copysign(dy * 0.15, p[0]), 0, 0])
            p[1] = y0
        if not moved:
            break
    return p


def drape(strands, colliders, spec, label=""):
    """the braids' final guides. Scalp parts: where two cross, the one that has come further from its root
    is lifted over the other (KD tree contacts, radial only), braids side by side are pushed apart over
    the scalp. Hanging parts: from where each leaves the head it bends to vertical and falls, sliding out
    / back past the head, the neck, the shoulders and the back (both torsos and the body proxy: it never
    returns inward under a bulge it passed, as a stiff braid would not), then braid-braid contacts push
    the hanging braids apart sideways and back (the one nearer the body stays), and the guides are smoothed"""
    t0 = time.time()
    # --- scalp layering
    for it in range(10):
        X = np.concatenate([s.sp for s in strands])
        own = np.concatenate([np.full(len(s.sp), i) for i, s in enumerate(strands)])
        loc = np.concatenate([np.arange(len(s.sp)) for s in strands])
        S = np.concatenate([s.s_al for s in strands])
        TH = np.concatenate([s.th for s in strands])
        R = np.concatenate([np.full(len(s.sp), s.r) for s in strands])
        kd = KDTree(len(X))
        for i, p in enumerate(X):
            kd.insert(V(p), i)
        kd.balance()
        push = np.zeros_like(X)
        for i in range(len(X)):
            if loc[i] < 2:
                continue
            for (_co, j, dist) in kd.find_range(V(X[i]), float(R.max()) * 2.1):
                if own[j] == own[i]:
                    continue
                rd = unit(X[i] - C)
                dv = X[i] - X[j]
                h = float(np.dot(dv, rd))
                lat = dv - rd * h
                ll = float(np.linalg.norm(lat))
                need_l = (R[i] + R[j]) * 0.92
                if ll > need_l:
                    continue
                need = (TH[i] + TH[j]) * 0.95
                if h > need:
                    continue
                if S[i] > S[j] + 0.03 and ll < 0.45 * need_l:
                    # crossing nearly on top: the one that has come further rides over
                    push[i] += rd * (need - h) * 0.5
                elif ll > 1e-6:
                    # side by side: spread over the scalp
                    push[i] += lat / ll * (need_l - ll) * 0.35
        k = 0
        for s in strands:
            n = len(s.sp)
            sp = s.sp + push[k:k + n]
            # at most about half a braid of extra lift over the combed height, never under it
            for i in range(2, n):
                hmin = CLEAR + 0.005 + s.th[i] + lift_of(spec, s.s_al[i])
                q, _ = on_scalp(sp[i], 0)
                hh = float(np.dot(sp[i] - q, unit(sp[i] - C)))
                hh2 = min(max(hh, hmin), hmin + 0.9 * s.r)
                if abs(hh2 - hh) > 1e-6:
                    sp[i] = sp[i] + unit(sp[i] - C) * (hh2 - hh)
            s.sp = sp
            k += n
    for s in strands:
        # smooth the heights along the braid (no kinks where it rides over another) and re-clear the head
        sp = s.sp.copy()
        for _ in range(4):
            sp[2:-1] = sp[2:-1] * 0.5 + (sp[1:-2] + sp[3:]) * 0.25
        for i in range(2, len(sp)):
            sp[i] = point_clear(sp[i], s.r, colliders, th=s.th[i])
        s.sp = sp
    # --- hang
    ds = spec.hang_ds
    for s in strands:
        p = s.sp[-1].copy()
        d = unit(s.sp[-1] - s.sp[-2])
        hang = [p.copy()]
        n_tr = 0
        while d[1] > -0.985 and n_tr < 14:
            d = unit(d + np.array([0, -1.0, 0]) * 0.3)
            p = point_clear(p + d * ds, s.r, colliders)
            hang.append(p.copy())
            n_tr += 1
        ph, fr, amp, ph2 = s.sway
        y_top = p[1]
        while p[1] > s.y_end:
            t = (y_top - p[1])
            q = p + np.array([0, -ds, 0])
            q[0] += amp * ds * 1.0 * math.cos(ph + t * fr) * min(1.0, t * 2)
            q[2] += amp * ds * 0.5 * math.cos(ph2 + t * fr * 0.7) * min(1.0, t * 2)
            p = point_clear(q, s.r, colliders, level=True)
            hang.append(p.copy())
        s.hang = np.array(hang)
        s.n_tr = n_tr
    # --- hanging braid-braid contacts (sideways / back only)
    for it in range(12):
        X = np.concatenate([s.hang[1:] for s in strands])
        own = np.concatenate([np.full(len(s.hang) - 1, i) for i, s in enumerate(strands)])
        R = np.concatenate([np.full(len(s.hang) - 1, s.r) for s in strands])
        kd = KDTree(len(X))
        for i, p in enumerate(X):
            kd.insert(V(p), i)
        kd.balance()
        push = np.zeros_like(X)
        axis_d = np.linalg.norm((X - np.array([0, 0, 0.03]))[:, [0, 2]], axis=1)
        for i in range(len(X)):
            for (_co, j, dist) in kd.find_range(V(X[i]), float(R.max()) * 2.0):
                if own[j] == own[i]:
                    continue
                need = (R[i] + R[j]) * 0.93
                dv = X[i] - X[j]
                dv[1] = 0
                ll = float(np.linalg.norm(dv))
                if ll >= need:
                    continue
                if ll < 1e-6:
                    dv, ll = np.array([0, 0, 1.0]), 1.0
                w = 0.7 if axis_d[i] >= axis_d[j] else 0.3  # the outer one gives way
                push[i] += dv / ll * (need - ll) * w
        k = 0
        for s in strands:
            n = len(s.hang) - 1
            h = s.hang.copy()
            # a push spreads along the braid (it is stiff): smooth the push, fade it in from the joint
            pu = push[k:k + n]
            for _ in range(30):
                pu[1:-1] = pu[1:-1] * 0.5 + (pu[:-2] + pu[2:]) * 0.25
                pu[-1] = pu[-2]
            fade = np.clip(np.arange(1, n + 1) / 6.0, 0, 1)[:, None]
            h[1:] = h[1:] + pu * fade
            for i in range(1, len(h)):
                h[i] = point_clear(h[i], s.r, colliders, level=i > s.n_tr)
            s.hang = h
            k += n
    for s in strands:
        h = s.hang
        for _ in range(14):
            h[1:-1] = h[1:-1] * 0.5 + (h[:-2] + h[2:]) * 0.25
        for i in range(1, len(h)):
            h[i] = point_clear(h[i], s.r, colliders)
        s.P = np.concatenate([s.sp, h[1:]])
    print(f"  drape {label}: {len(strands)} braids, {time.time() - t0:.1f}s")


# ------------------------------------------------------------------------------------------- tube sweep
def adaptive(P, ds_min, ds_max, ang=math.radians(7)):
    """resample a polyline: dense where it bends, sparse where it runs straight"""
    P = resample(P, ds_min * 0.5)
    keep = [0]
    acc_a, acc_s = 0.0, 0.0
    for i in range(1, len(P) - 1):
        a = P[i] - P[i - 1]
        b = P[i + 1] - P[i]
        cosv = np.dot(a, b) / max(1e-12, np.linalg.norm(a) * np.linalg.norm(b))
        acc_a += math.acos(max(-1, min(1, cosv)))
        acc_s += np.linalg.norm(a)
        if (acc_a > ang and acc_s >= ds_min) or acc_s >= ds_max:
            keep.append(i)
            acc_a, acc_s = 0.0, 0.0
    keep.append(len(P) - 1)
    return P[keep]


def sweep_tube(piece, pts, ups, radius_fn, sides, flatten, strip, v_tile, shade_fn, v0=0.0, cap_tip=True,
               cap_root=False, nrm0=None):
    """a flattened tube along pts (the flat face against `ups`, the scalp normal near the root), the plait
    strip wrapped twice round (seam vertices at 0 and half way), v by arc length / v_tile"""
    n = len(pts)
    u0, u1 = strip
    tan = np.zeros_like(pts)
    tan[0] = pts[1] - pts[0]
    tan[-1] = pts[-1] - pts[-2]
    tan[1:-1] = pts[2:] - pts[:-2]
    tan = unit(tan)
    # frame: up projected off the tangent, parallel-transported where no up is given
    frames = []
    nrm = None if nrm0 is None else np.asarray(nrm0, dtype=np.float64)
    for i in range(n):
        t = tan[i]
        if ups[i] is not None:
            u = np.asarray(ups[i]) - t * np.dot(ups[i], t)
            if np.linalg.norm(u) > 1e-6:
                u = unit(u)
                if nrm is not None:
                    # blend toward transported to avoid flips
                    tr = nrm - t * np.dot(nrm, t)
                    tr = unit(tr)
                    u = unit(u * 0.7 + tr * 0.3)
                nrm = u
        if nrm is None:
            ref = np.array([0, 0, 1.0]) if abs(t[2]) < 0.9 else np.array([1.0, 0, 0])
            nrm = unit(np.cross(np.cross(t, ref), t))
        else:
            nrm = unit(nrm - t * np.dot(nrm, t))
        frames.append((nrm.copy(), unit(np.cross(t, nrm))))
    acc = v0
    rings = []
    half = sides // 2
    for i in range(n):
        if i > 0:
            acc += float(np.linalg.norm(pts[i] - pts[i - 1]))
        v = acc / v_tile
        nr, bi = frames[i]
        rad, fl = radius_fn(i / (n - 1), i)
        sh = shade_fn(i / (n - 1), i)
        ring = []
        for k in range(sides + 2):
            # k = 0..half: first copy (u 0..1), k = half+1 .. sides+1: second copy
            if k <= half:
                kk, uu = k, k / half
            else:
                kk, uu = k - 1, (k - 1 - half) / half
            a = TAU * kk / sides + math.pi / 2  # seams at the tube's sides (the flat face's edges)
            dvec = nr * math.cos(a) * fl + bi * math.sin(a)
            dn = unit(nr * math.cos(a) / max(0.3, fl) + bi * math.sin(a))
            vid = piece.vert(pts[i] + dvec * rad, dn, (u0 + (u1 - u0) * uu, v), sh(dn) if callable(sh) else sh)
            ring.append(vid)
        rings.append(ring)
    for i in range(n - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(sides + 1):
            if k == half:
                continue  # the seam (duplicated vertices)
            piece.quad(r0[k], r0[k + 1], r1[k + 1], r1[k])  # counter-clockwise from outside
    if cap_tip:
        tip = pts[-1] + tan[-1] * radius_fn(1.0, n - 1)[0] * 0.5
        sh = shade_fn(1.0, n - 1)
        c = piece.vert(tip, tan[-1], ((u0 + u1) / 2, acc / v_tile), sh(tan[-1]) if callable(sh) else sh)
        r = rings[-1]
        for k in range(sides + 1):
            if k == half:
                continue
            piece.tri(r[k], r[k + 1], c)
    if cap_root:
        root = pts[0] - tan[0] * radius_fn(0.0, 0)[0] * 0.35
        sh = shade_fn(0.0, 0)
        c = piece.vert(root, -tan[0], ((u0 + u1) / 2, v0 / v_tile), sh(-tan[0]) if callable(sh) else sh)
        r = rings[0]
        for k in range(sides + 1):
            if k == half:
                continue
            piece.tri(r[k + 1], r[k], c)
    piece._last_nrm = frames[-1][0]
    return rings


# ------------------------------------------------------------------------------------------- pieces
def sector_of(p, G):
    a = math.atan2(p[0], p[2])  # 0 at the back, + toward the right
    u = (a + math.pi) / TAU  # 0 = left front .. 0.5 back .. 1 right front
    return min(G - 1, int(u * G))


def build_braids(spec, colliders, coll):
    rng = np.random.default_rng(spec.seed)
    t0 = time.time()
    roots = ring_layout(spec.box, inset=0.04 + spec.r, seed=spec.seed)
    # (no braids in front of the ears: their hair is too short to plait over the ear; the cap covers it)
    keep = []
    for (p, k, t) in roots:
        da = da_of(p)[0]
        if 1.15 < da < 2.15 and p[1] < 0.12 + 1.6 * spec.r:
            continue
        keep.append((p, k, t))
    roots = keep
    print(f"  {spec.key}: {len(roots)} roots in {max(k for _, k, _ in roots) + 1} rings ({time.time() - t0:.1f}s)")
    strands = [Strand(i, p, k, spec, rng) for i, (p, k, t) in enumerate(roots)]
    drape(strands, colliders, spec, label=spec.key)
    # a braid whose path over the scalp would run across an ear is left out (the ears stay visible)
    keep = []
    for s in strands:
        bad = False
        for lo, hi in EARS:
            m = s.r * 0.6
            if np.any(np.all((s.P[:s.n_scalp] > lo - m) & (s.P[:s.n_scalp] < hi + m), axis=1)):
                bad = True
        if not bad:
            keep.append(s)
    if len(keep) < len(strands):
        print(f"  {spec.key}: {len(strands) - len(keep)} braids over the ears left out")
    strands = keep
    return strands


def make_bases(spec, strands):
    """HairBase: the box under every braid's root, the hair of the box gathered toward the root (a trapezoid
    lying on the scalp, wide at the box's upstream edge, braid-wide at the root, a short plait start: the
    cornrow row strip); the gaps between them are the partings"""
    piece = hl.Piece("HairBase", "cornrow", material="Fabric", castShadow=False)
    box = spec.box
    for s in strands:
        root = s.P[0]
        _q, n = on_scalp(root, 0)
        d = s.P[min(3, len(s.P) - 1)] - root
        d = unit(d - n * np.dot(d, n))
        side = unit(np.cross(n, d))
        s0, s1 = -0.5 * box * 0.84, 0.03 + box * 0.12
        rows, cols = 4, 3
        ids = []
        knot = 2 * s.r * 0.6
        for i in range(rows + 1):
            t = i / rows
            sa = s0 + (s1 - s0) * t
            w = max(knot, box * 0.82 * (1 - 0.75 * t ** 2.2))
            row = []
            for j in range(cols + 1):
                c = j / cols - 0.5
                p = root + d * sa + side * c * w
                p, nn = on_scalp(p, CLEAR + 0.0005)
                occ = 1.0 - 0.3 * t - 0.15 * (2 * abs(c)) ** 2
                row.append(piece.vert(p, nn, (ROW[0] + (ROW[1] - ROW[0]) * (j / cols), (sa - s0) / (box * 1.4)),
                                      (occ, occ, occ)))
            ids.append(row)
        for i in range(rows):
            for j in range(cols):
                a, b, c_, e = ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]
                # counter-clockwise seen from outside (normal = n): a(left,up) e(left,down) c(right,down) b
                piece.quad(a, e, c_, b) if np.dot(np.cross(np.subtract(piece.P[e], piece.P[a]),
                                                            np.subtract(piece.P[b], piece.P[a])), n) > 0 \
                    else piece.quad(a, b, c_, e)
    return piece


def guide_curves(strands, coll, name):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    for s in strands:
        sp = cu.splines.new("POLY")
        sp.points.add(len(s.P) - 1)
        for i, p in enumerate(s.P):
            sp.points[i].co = (p[0], p[1], p[2], 1.0)
            sp.points[i].radius = s.r * 20
    ob = bpy.data.objects.new(name, cu)
    cu.bevel_depth = 0.0
    coll.objects.link(ob)
    return ob


def make_pieces(spec, strands, colliders):
    """HairTop (every scalp part) + per sector a swing chain HairBraidNN (upper hang) / HairBraidNNb (lower)"""
    G = spec.groups
    top = hl.Piece("HairTop", "braid", material="Fabric", castShadow=True)
    segs = {}
    joint = {}
    v_tile = 6.4 * spec.r  # square texels: the strip spans half the circumference (pi r) over 512 px
    # chains: equal-count sectors of the hanging azimuths (left front .. back .. right front)
    azs = np.array([math.atan2(s.P[s.n_scalp - 1][0], s.P[s.n_scalp - 1][2]) for s in strands])
    order = np.argsort(azs)
    group_of = {}
    for rank, si in enumerate(order):
        group_of[int(si)] = min(G - 1, rank * G // len(strands))
    for si, s in enumerate(strands):
        n_sc = s.n_scalp
        P = s.P
        # split: scalp part | upper hang | lower hang
        hang = P[n_sc - 1:]
        hs = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(hang, axis=0), axis=1))])
        Lh = hs[-1]
        mid = int(np.searchsorted(hs, Lh * 0.48))
        mid = max(1, min(len(hang) - 2, mid))
        parts = [("top", P[:n_sc]), ("s1", hang[: mid + 1]), ("s2", hang[mid:])]
        g = group_of[si]
        L_total = float(np.sum(np.linalg.norm(np.diff(P, axis=0), axis=1)))
        acc = 0.0
        r = s.r
        flare = spec.root_flare
        L_sc = float(np.sum(np.linalg.norm(np.diff(P[:n_sc], axis=0), axis=1)))
        last_nrm = None
        # (scalp normals for the flat face)
        for pi_, (kind, pts) in enumerate(parts):
            if len(pts) < 2:
                continue
            pts = adaptive(pts, spec.ds_top[0] if kind == "top" else 0.03, spec.ds_top[1] if kind == "top" else spec.ds_hang)
            # (resampling cuts corners: keep the sampled centre line clear of the ears by the braid's radius)
            for _ in range(2):
                pts = np.array([ear_push(q, r * 1.6 + 0.006)[0] for q in pts])
            seg_len = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
            s_abs = acc + seg_len
            ups = []
            for p in pts:
                if kind == "top":
                    ups.append(on_scalp(p, 0)[1])
                else:
                    ups.append(None)
            if kind != "top":
                ups[0] = None

            def radius_fn(t, i, s_abs=s_abs):
                sa = s_abs[i]
                # flared knot at the root, full, then a taper over the last 9%
                across, thick = root_shape(spec, sa, r)
                tip = 1.0 - 0.45 * float(smooth(L_total * 0.9, L_total, sa))
                return across * tip, thick / across

            def shade_fn(t, i, s_abs=s_abs, pts=pts, kind=kind):
                return (1.0, 1.0, 1.0)

            piece = top if kind == "top" else None
            if piece is None:
                name = f"HairBraid{g + 1:02d}" + ("" if kind == "s1" else "b")
                piece = segs.get(name)
                if piece is None:
                    piece = hl.Piece(name, "braid", material="Fabric", castShadow=True)
                    segs[name] = piece
                    joint[name] = dict(piv=[], tip=[], g=g, seg=1 if kind == "s1" else 2)
                joint[name]["piv"].append(pts[0])
                joint[name]["tip"].append(pts[-1])
            sweep_tube(piece, pts, ups, radius_fn, spec.sides, 1.0, PLAIT, v_tile, shade_fn, v0=acc / 1.0,
                       cap_tip=(kind == "s2"), cap_root=(kind == "top"), nrm0=last_nrm)
            last_nrm = piece._last_nrm
            acc = s_abs[-1]
    pieces = [top]
    for name in sorted(segs):
        p = segs[name]
        j = joint[name]
        piv = np.mean(j["piv"], axis=0)
        tip = np.mean(j["tip"], axis=0)
        parent = f"HairBraid{j['g'] + 1:02d}" if j["seg"] == 2 else None
        p.meta["hairfx"] = {"kind": "swing", "chain": f"HairBraid{j['g'] + 1}", "seg": j["seg"], "parent": parent,
                            "stiff": spec.stiff, "mass": spec.mass,
                            "pivot": [round(float(x), 4) for x in piv], "tip": [round(float(x), 4) for x in tip]}
        p.meta["length"] = "hang"
        p.meta["hideUnder"] = {"headgear": False, "hood": True}
        pieces.append(p)
    return pieces


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
def clearance(pieces, head, fit=None, sample=3000):
    """min distance of any vertex to the head surface and how many are inside it (optionally after a fit)"""
    mind, inside = 9.0, 0
    for p in pieces:
        P = np.asarray(p.P)
        if fit is not None:
            P = P * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]
        for q in P[:: max(1, len(P) // sample)]:
            sd, _, _ = head.signed(q)
            if sd < 0:
                inside += 1
            mind = min(mind, abs(sd) if sd >= 0 else -abs(sd))
    return mind, inside


def skull_height(pieces, skull, fit=None, sample=3000, ymin=-0.32):
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
CORN = dict(n=10, axis=1.5, tan_max=0.205, width=0.07, ridge=0.021, v_tile=0.15, across=7, tail=(0.12, 0.2),
            tail_r=0.021, seed=31)


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


def build_cornrows(spec, colliders, coll):
    rng = np.random.default_rng(spec["seed"])
    n = spec["n"]
    top = hl.Piece("HairTop", "cornrow", material="Fabric", castShadow=True)
    tails = {"HairBraid01": [], "HairBraid02": []}
    guides = []
    rows = []
    for i in range(n):
        tp = -spec["tan_max"] + 2 * spec["tan_max"] * i / (n - 1)
        rows.append((tp, row_path(tp, spec, rng)))
    A = spec["axis"]
    for i, (tp, P) in enumerate(rows):
        L = float(np.sum(np.linalg.norm(np.diff(P, axis=0), axis=1)))
        s_al = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
        Pc = adaptive(P, 0.016, 0.03, ang=math.radians(5))
        sc = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(Pc, axis=0), axis=1))])
        guides.append(Pc)
        ids = []
        k = spec["across"]
        for j, p in enumerate(Pc):
            s = sc[j]
            q, nn = on_scalp(p, 0)
            t = Pc[min(j + 1, len(Pc) - 1)] - Pc[max(j - 1, 0)]
            t = unit(t - nn * np.dot(t, nn))
            side = unit(np.cross(t, nn))
            # width: narrow at the hairline start, full, narrowing where the rows converge toward the nape
            w = spec["width"] * min(1.0, (p[1] + A) / (0.32 + A)) ** 1.5
            w *= 0.4 + 0.6 * float(smooth(0.0, 0.08, s))
            w *= 1.0 - 0.35 * float(smooth(L - 0.08, L, s))
            ridge = spec["ridge"] * (w / spec["width"])
            row = []
            for c in range(k):
                cc = c / (k - 1) * 2 - 1
                arch = (1 - cc * cc) ** 0.6
                pp, n2 = on_scalp(q + side * cc * w * 0.5, CLEAR + 0.001 + ridge * arch)
                nrm = unit(n2 + side * cc * 0.85)
                occ = 0.62 + 0.38 * arch
                uu = ROW[0] + (ROW[1] - ROW[0]) * (c / (k - 1))
                row.append(top.vert(pp, nrm, (uu, s / spec["v_tile"]), (occ, occ, occ)))
            ids.append(row)
        for j in range(len(ids) - 1):
            for c in range(k - 1):
                a_, b_ = ids[j][c], ids[j][c + 1]
                d_, c_ = ids[j + 1][c], ids[j + 1][c + 1]
                # outward-facing: check against the scalp normal
                pa, pb, pd = (np.asarray(top.P[x]) for x in (a_, b_, d_))
                if np.dot(np.cross(pb - pa, pd - pa), unit(pa - C)) > 0:
                    top.quad(a_, b_, c_, d_)
                else:
                    top.quad(a_, d_, c_, b_)
        # the nape end: a short plaited tail hanging from the row's end
        end = Pc[-1]
        d = unit(Pc[-1] - Pc[-3])
        Lt = rng.uniform(*spec["tail"])
        r = spec["tail_r"] * (spec["width"] * min(1.0, (end[1] + A) / (0.32 + A)) ** 1.5) / spec["width"] * 1.2
        p = point_clear(end.copy(), r, colliders)
        tail = [p.copy()]
        while float(np.sum(np.linalg.norm(np.diff(np.array(tail), axis=0), axis=1))) < Lt if len(tail) > 1 else True:
            d = unit(d + np.array([-0.3 * math.copysign(1, p[0]), -1.0, 0.1]) * 0.45)
            p = point_clear(p + d * 0.02, r, colliders)
            tail.append(p.copy())
        tails["HairBraid01" if tp < 0 else "HairBraid02"].append((np.array(tail), r, L))
    # baby hairs: at each row's start, a few short laid edge hairs swept back into the row (softens the start)
    for i, (tp, P) in enumerate(rows):
        q0, nn = on_scalp(P[0], 0)
        t0 = unit(P[3] - P[0])
        t0 = unit(t0 - nn * np.dot(t0, nn))
        A_ = spec["axis"]
        w0 = spec["width"] * min(1.0, (P[0][1] + A_) / (0.32 + A_)) ** 1.5
        pts_c = []
        for t in np.linspace(0, 1, 4):
            pp, _n = on_scalp(q0 - t0 * 0.008 + t0 * 0.034 * t, CLEAR + 0.0012)
            pts_c.append(pp)
        ups = [on_scalp(pp, 0)[1] for pp in pts_c]
        top.card(pts_c, [w0 * 1.25] * 4, ups, BABY, v0=0.0, v1=0.55, shade=lambda t: (0.85, 0.85, 0.85), double=False)
    pieces = [top]
    v_tile = 6.4 * spec["tail_r"]
    for name, lst in tails.items():
        if not lst:
            continue
        piece = hl.Piece(name, "braid", material="Fabric", castShadow=False)
        pivs, tips = [], []
        for (tp_pts, r, L) in lst:
            Lt = float(np.sum(np.linalg.norm(np.diff(tp_pts, axis=0), axis=1)))
            sa = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(tp_pts, axis=0), axis=1))])

            def radius_fn(t, i, sa=sa, Lt=Lt, r=r):
                return r * (1 - 0.5 * float(smooth(Lt * 0.75, Lt, sa[i]))), 0.85

            sweep_tube(piece, tp_pts, [None] * len(tp_pts), radius_fn, 4, 1.0, PLAIT, v_tile,
                       lambda t, i: (0.85, 0.85, 0.85), cap_tip=True, cap_root=True)
            pivs.append(tp_pts[0])
            tips.append(tp_pts[-1])
        piece.meta["hairfx"] = {"kind": "swing", "chain": name, "seg": 1, "parent": None, "stiff": 0.6, "mass": 0.6,
                                "pivot": [round(float(x), 4) for x in np.mean(pivs, axis=0)],
                                "tip": [round(float(x), 4) for x in np.mean(tips, axis=0)]}
        piece.meta["length"] = "hang"
        piece.meta["hideUnder"] = {"headgear": False, "hood": True}
        pieces.append(piece)
    return pieces, guides


# ------------------------------------------------------------------------------------------- styles / main
STYLES = {
    "braids": dict(kind="braids", spec=BRAIDS, head="f",
                   entry=dict(styles=["Braids"], types=None, cap={"cut": "full", "density": 0.35})),
    "box_braids": dict(kind="braids", spec=BOX, head="f",
                       entry=dict(styles=["Box Braids"], types=None, cap={"cut": "full", "density": 0.35})),
    "cornrows": dict(kind="cornrows", spec=CORN, head="m",
                     entry=dict(styles=["Cornrows"], types=None, cap={"cut": "full", "density": 0.15})),
}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_style(key, colliders):
    st = STYLES[key]
    clear_scene()
    coll = bpy.data.collections.new("guides (Blender curves: braid centre lines)")
    bpy.context.scene.collection.children.link(coll)
    work = bpy.data.collections.new("work")
    bpy.context.scene.collection.children.link(work)
    t0 = time.time()
    if st["kind"] == "braids":
        strands = build_braids(st["spec"], colliders, coll)
        guide_curves(strands, coll, f"{key}_guides")
        pieces = make_pieces(st["spec"], strands, colliders)
    else:
        pieces, guides = build_cornrows(st["spec"], colliders, coll)

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
    return pieces, coll


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", default=SCRATCH, help="folder for the self-check renders ('' = none)")
    ap.add_argument("--only", default="")
    ap.add_argument("--no-tex", action="store_true")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--looks", type=int, default=2, help="looks (hair colour / skin) rendered per style")
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
    skf = hl.Skull(SKF_PATH)
    keys = [k for k in STYLES if not args.only or k in args.only.split(",")]
    report = {}
    for key in keys:
        print(f"style {key}")
        pieces, coll = build_style(key, colliders)
        st = STYLES[key]
        cm, ci = clearance(pieces, colliders["head"])
        cf, cfi = clearance(pieces, head_f, FIT_F)
        sm = skull_height(pieces, SK)
        sf = skull_height(pieces, skf, FIT_F)
        sf_n = skull_height(pieces, SK, dict(ax=0.965, ay=1.0, az=1.0, dz=0.0))
        eh = ear_hits(pieces)
        bm = body_min(pieces)
        entry = dict(st["entry"])
        entry["notes"] = (f"braids family (build_braids.py). min clearance: head mesh male {cm:.4f}, female (fit) "
                          f"{cf:.4f}; skull table male {sm:.4f}, female (fit) {sf:.4f}, male skull 0.965x narrow "
                          f"{sf_n:.4f}")
        data = hl.export_style(key, entry, pieces)
        save_blend(key, pieces, coll, os.path.join(BLEND_DIR, f"{key}.blend"), head_name=st["head"])
        rep = dict(styles=entry["styles"], types=entry["types"], cap=entry["cap"], tris=data["tris"],
                   pieces={p.name: dict(nt=p.nt, tex=p.tex, hairfx=(p.meta.get("hairfx") or {}).get("kind"))
                           for p in pieces},
                   clear_head_m=round(cm, 4), inside_m=ci, clear_head_f=round(cf, 4), inside_f=cfi,
                   skull_m=round(sm, 4), skull_f=round(sf, 4), skull_m_narrow=round(sf_n, 4), ear_hits=eh,
                   body_min=round(bm, 4))
        rep["per_piece"] = {p.name: dict(head_m=round(clearance([p], colliders["head"])[0], 4),
                                         skull_m=round(skull_height([p], SK), 4),
                                         skull_f=round(skull_height([p], skf, FIT_F), 4),
                                         ears=ear_hits([p])) for p in pieces}
        report[key] = rep
        if os.environ.get("BRAIDS_DUMP"):
            import pickle
            with open(os.path.join(SCRATCH, f"{key}.pkl"), "wb") as f:
                pickle.dump(pieces, f)
        print(json.dumps(rep))
        if args.render:
            looks_all = {
                "f": [("f", "darkbrown", "deep", ["34", "side", "back", "close", "top34"]),
                      ("f", "blonde", "light", ["34", "close"] if args.looks < 3 else ["34", "side", "back", "close", "top34"]),
                      ("f", "black", "mid", ["34", "side", "back", "close", "top34"])],
                "m": [("m", "black", "deep", ["34", "side", "back", "close", "top34"]),
                      ("m", "blonde", "light", ["34", "close"] if args.looks < 3 else ["34", "side", "back", "close", "top34"]),
                      ("m", "darkbrown", "mid", ["34", "side", "back", "close", "top34"])],
            }[st["head"]][: max(1, args.looks)]
            cap = (st["entry"]["cap"]["density"], "Natural")
            sheet = render_style(key, pieces, cap, os.path.join(args.render, "renders"), args.samples, looks_all,
                                 title=f"{key}: {', '.join(st['entry']['styles'])}  ({data['tris']} tris, "
                                       f"{len(pieces)} pieces)")
            rep["sheet"] = sheet
            print("sheet", sheet)
    with open(os.path.join(args.render or SCRATCH, "report.json"), "w") as f:
        json.dump(report, f, indent=1)
    print(json.dumps(report, indent=1))
    print(f"total {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
