"""Joint interpenetration check of the tier bodies (numpy only, no Blender): every part in game rest space from
build_body.build_tier, each joint turned through the range the Animator uses (walk / run / punch) about its pivot,
and per joint how much of the parent's surface ends up INSIDE the child (the child's skin then shows through the
parent: the thigh through the pelvis, the upper arm through the chest) and the reverse.

    python3 tools/body/check_joints.py [--tiers 1,3,5] [--joint hip,shoulder,elbow,knee,wrist]
"""
import argparse
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_body as bb  # noqa: E402


def rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "x":
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == "y":
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def inside(P, T, Q):
    """Q (m, 3) inside the closed mesh (P, T): parity of +X ray crossings (vectorised)"""
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    res = np.zeros(len(Q), bool)
    lo, hi = P.min(0), P.max(0)
    box = np.all((Q > lo) & (Q < hi), axis=1)
    idx = np.where(box)[0]
    if not len(idx):
        return res
    e1, e2 = b - a, c - a
    d = np.array([1.0, 0.0, 0.0])
    h = np.cross(d, e2)
    det = np.einsum("ij,ij->i", e1, h)
    ok = np.abs(det) > 1e-12
    f = np.where(ok, 1 / np.where(ok, det, 1), 0)
    for k0 in range(0, len(idx), 256):
        ii = idx[k0:k0 + 256]
        s = Q[ii][:, None, :] - a[None]
        u = f * np.einsum("mij,ij->mi", s, h)
        q = np.cross(s, e1[None])
        v = f * q[..., 0]
        t = f * np.einsum("ij,mij->mi", e2, q)
        hit = ok & (u >= 0) & (u <= 1) & (v >= 0) & (u + v <= 1) & (t > 0)
        res[ii] = hit.sum(1) % 2 == 1
    return res


def turned(lp, pivot, R):
    return (lp["P"] - pivot) @ R.T + pivot


PCT = False


def check(parts, parent, child, pivot, poses, label):
    pp, cp = parts[parent], parts[child]
    rest_in = inside(cp["P"], cp["T"], pp["P"])  # parent verts inside the child at rest (the tucked seam)
    rows = []
    for name, R in poses:
        Pc = turned(cp, pivot, R)
        pin = inside(Pc, cp["T"], pp["P"]) & ~rest_in
        hgt = (pp["P"][pin, 1] - pivot[1]).max() if pin.any() else 0.0
        # the parent's hidden end (its verts inside the child at rest) that the turn uncovers, and how far out of the
        # child it then is (the nearest child vertex: a lump / an exposed dome)
        exp = rest_in & ~inside(Pc, cp["T"], pp["P"])
        far = 0.0
        if exp.any():
            d = np.linalg.norm(pp["P"][exp][:, None, :] - Pc[None, :, :], axis=2).min(1)
            far = float(d.max())
        rows.append((name, int(pin.sum()), float(hgt), int(exp.sum()), far))
    print(f"{label:9s} " + "  ".join(f"{n}:{k:3d}@{h:+.2f}/{e:2d}~{f:.2f}" for n, k, h, e, f in rows))
    if PCT:
        # (the counts grow with the mesh's density: the same as a share of the parent's vertices)
        npv = max(1, len(pp["P"]))
        print(f"{'':9s} " + "  ".join(f"{n}:{100 * k / npv:4.1f}%/{100 * e / npv:4.1f}%" for n, k, h, e, f in rows))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiers", default="1,3,5")
    ap.add_argument("--joint", default="hip,shoulder,elbow,wrist,knee")
    ap.add_argument("--pct", action="store_true", help="also print the counts as a share of the parent's vertices")
    a = ap.parse_args()
    global PCT
    PCT = a.pct
    for n in (int(x) for x in a.tiers.split(",")):
        parts = bb.build_tier(None, n)
        J = {k: np.array(v) for k, v in parts["_J"].items()}
        print(f"--- tier {n}: parent verts newly inside the child (count @ highest above the pivot) / parent end uncovered (count ~ how far out)")
        if "hip" in a.joint:
            poses = [(f"f{d:+d}", rot("x", d)) for d in (-30, -15, 15, 30, 45, 60)]
            poses += [("ab+10", rot("z", 10)), ("ad-8", rot("z", -8))]
            check(parts, "LowerTorso", "RightUpperLeg", J["RightHip"], poses, "hip")
        if "knee" in a.joint:
            poses = [(f"k{d}", rot("x", -d)) for d in (20, 45, 70, 100)]
            check(parts, "RightUpperLeg", "RightLowerLeg", J["RightKnee"], poses, "knee")
        if "shoulder" in a.joint:
            poses = [(f"p{d:+d}", rot("x", d)) for d in (-30, 30, 60, 90)] + [("ab30", rot("z", 30)), ("ad-10", rot("z", -10))]
            check(parts, "UpperTorso", "RightUpperArm", J["RightShoulder"], poses, "shoulder")
        if "elbow" in a.joint:
            poses = [(f"e{d}", rot("x", d)) for d in (20, 60, 100, 140)]
            check(parts, "RightUpperArm", "RightLowerArm", J["RightElbow"], poses, "elbow")
        if "wrist" in a.joint:
            poses = [(f"w{d:+d}", rot("x", -d)) for d in (-30, 30)] + [("z+20", rot("z", 20)), ("z-20", rot("z", -20))]
            check(parts, "RightLowerArm", "RightHand", J["RightWrist"], poses, "wrist")


if __name__ == "__main__":
    main()
