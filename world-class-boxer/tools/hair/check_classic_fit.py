"""Fit check: every asset-hair piece against the classic head (numpy only; python3 or /opt/bpyenv/bin/python).

    python3 tools/hair/check_classic_fit.py [--src tools/hair/out] [--v7-fit] [--json OUT]

For each entry of SRC/<key>/style.json and each of its pieces (.mesh 2.00 read directly), every vertex is placed as
HairAssetKit places it on a classic head (v9 meshes, classic fit0: the identity in nominal space; --v7-fit: the v7
meshes through today's fit, organic fit0 x CLASSIC_FIT) and measured against the classic head's exact surface
(AnatomyHairKit.CLASSIC: the rounded cylinder r 0.6, half height 0.6, round 0.24; signed distance, < 0 inside).

Reported per piece (nominal studs; x Head.Size / 1.2 for real studs):
* scalp layer: the vertices lying on the head (distance < 0.06 and over the head, y > -0.62): min, p5, median, max;
  for scalp-hugging layers (the cap, the fades' shells and fur, cornrows, the root / base pieces) this is the hug
  height the contract asks 0.012 .. 0.03 (+ the shells' stack) of.
* min: the smallest distance of any vertex (anything < 0 is inside the head).
* ears: the smallest distance to the built face's ear ellipsoids (shell + helix rim, earSize +0.5; < 0 inside an
  ear).
* brows: vertices in front of the face (z < -0.35) over the brows' span (|x| < 0.38) lower than the default
  face's brow top + 0.03 (ref/classic skull.json face: browTop 0.305; the creator's forehead slider moves the brows
  and the game's hairline together, +-0.03 / +-0.04): hair on or just above the brows.
"""
import argparse
import glob
import json
import math
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
R, HH, RR = 0.6, 0.6, 0.24
V7_FIT = dict(ax=1.661, ay=1.218, az=1.469, dy=-0.06, dz=-0.03)


def sd_classic(P):
    qx = np.sqrt(P[:, 0] ** 2 + P[:, 2] ** 2) - (R - RR)
    qy = np.abs(P[:, 1]) - (HH - RR)
    ox, oy = np.maximum(qx, 0), np.maximum(qy, 0)
    return np.sqrt(ox * ox + oy * oy) + np.minimum(np.maximum(qx, qy), 0) - RR


def ear_dist(P, ear_s=1.1):
    """approximate distance outside the ear ellipsoids (classic_ref.face_parts: shell + helix, earSize +0.5)"""
    S = 1.2
    best = np.full(len(P), 9.0)
    for side in (-1, 1):
        a = side * math.radians(6)
        c, s = math.cos(a), math.sin(a)
        M = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        cen = np.array([side * 0.5 * S, 0.02 * S, 0.04 * S])
        for off, half in (((0, 0, 0), (0.04 * S, 0.125 * S * ear_s, 0.085 * S * ear_s)),
                          ((side * 0.03 * S, 0.015 * S, 0.055 * S * ear_s), (0.0225 * S, 0.13 * S * ear_s, 0.03 * S * ear_s))):
            cc = cen + M @ np.array(off)
            Q = (P - cc) @ M  # into the ear's frame
            h = np.array(half)
            k = np.linalg.norm(Q / h, axis=1)
            best = np.minimum(best, (k - 1) * h.min())
    return best


def read_positions(path):
    with open(path, "rb") as f:
        data = f.read()
    i = data.index(b"\n") + 1
    hs, vs, fs, nv, nt = struct.unpack_from("<HBBII", data, i)
    i += hs
    P = np.array([struct.unpack_from("<3f", data, i + k * vs) for k in range(nv)], np.float64)
    return P, nt


def check(src, v7fit=False, browmax=0.305, browclear=0.03):
    rows = []
    for sj in sorted(glob.glob(os.path.join(src, "*", "style.json"))):
        key = os.path.basename(os.path.dirname(sj))
        with open(sj) as f:
            st = json.load(f)
        for name, rec in sorted(st["pieces"].items()):
            P, nt = read_positions(os.path.join(os.path.dirname(sj), rec["mesh_file"]))
            if v7fit:
                P = P * [V7_FIT["ax"], V7_FIT["ay"], V7_FIT["az"]] + [0, V7_FIT["dy"], V7_FIT["dz"]]
            d = sd_classic(P)
            over = (d < 0.06) & (P[:, 1] > -0.62)
            sc = d[over]
            e = ear_dist(P)
            fr = (P[:, 2] < -0.35) & (np.abs(P[:, 0]) < 0.38) & (P[:, 1] < browmax + browclear) & (P[:, 1] > -0.62)
            row = dict(key=key, piece=name, tris=nt, verts=len(P), min=float(d.min()),
                       scalp_n=int(over.sum()),
                       scalp_min=float(sc.min()) if len(sc) else None,
                       scalp_p5=float(np.percentile(sc, 5)) if len(sc) else None,
                       scalp_med=float(np.median(sc)) if len(sc) else None,
                       scalp_max=float(sc.max()) if len(sc) else None,
                       inside=int((d < 0).sum()), under_012=int((d < 0.012).sum()),
                       ear_min=float(e.min()), over_brows=int(fr.sum()))
            rows.append(row)
    return rows


def fmt(v):
    return "   -  " if v is None else f"{v:+.4f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(HERE, "out"))
    ap.add_argument("--v7-fit", action="store_true")
    ap.add_argument("--json", default="")
    args = ap.parse_args()
    rows = check(args.src, args.v7_fit)
    print(f"{'entry':14s} {'piece':13s} {'tris':>6s} | scalp layer: {'min':>7s} {'p5':>7s} {'med':>7s} {'max':>7s} "
          f"| {'all min':>7s} {'inside':>6s} {'<.012':>6s} | {'ear':>7s} {'brows':>5s}")
    worst = dict(min=9.0, scalp_min=9.0, ear=9.0, inside=0, brows=0)
    for r in rows:
        print(f"{r['key']:14s} {r['piece']:13s} {r['tris']:6d} | {'':12s} {fmt(r['scalp_min'])} {fmt(r['scalp_p5'])} "
              f"{fmt(r['scalp_med'])} {fmt(r['scalp_max'])} | {fmt(r['min'])} {r['inside']:6d} {r['under_012']:6d} | "
              f"{fmt(r['ear_min'])} {r['over_brows']:5d}")
        worst["min"] = min(worst["min"], r["min"])
        if r["scalp_min"] is not None:
            worst["scalp_min"] = min(worst["scalp_min"], r["scalp_min"])
        worst["ear"] = min(worst["ear"], r["ear_min"])
        worst["inside"] += r["inside"]
        worst["brows"] += r["over_brows"]
    by = {}
    for r in rows:
        b = by.setdefault(r["key"], dict(tris=0, min=9.0))
        b["tris"] += r["tris"]
        b["min"] = min(b["min"], r["min"])
    print("\nper entry: " + ", ".join(f"{k} {v['tris']} tris (min {v['min']:+.3f})" for k, v in by.items()))
    print(f"\nWORST: any vertex {worst['min']:+.4f}, scalp layer {worst['scalp_min']:+.4f}, ear {worst['ear']:+.4f}, "
          f"inside the head {worst['inside']}, over the brows {worst['brows']} (nominal studs)")
    if args.json:
        with open(args.json, "w") as f:
            json.dump(dict(rows=rows, worst=worst), f, indent=1)
    return rows


if __name__ == "__main__":
    main()
