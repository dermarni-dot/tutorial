"""Gear fit check (numpy only): every trunks piece of build_gear.build_all against the body it covers, at rest and
with the thighs swung through the walk's range, as radial sections (angular bins round the piece's axis): where the
body (or an inner piece) stands out of the piece that should cover it, by how much.

    python3 tools/body/check_gear.py [--tiers 1,3,5] [--swing -25,0,30]
"""
import argparse
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_body as bb  # noqa: E402
import build_gear as bg  # noqa: E402

NB = 72


def sec(P, T, y):
    return bg.sec_pts({"P": P, "T": T}, y)


def radial_max(Q, c):
    """max distance from c per angular bin (nan where empty)"""
    r = np.full(NB, np.nan)
    if not len(Q):
        return r
    d = Q - c
    a = np.arctan2(d[:, 0], -d[:, 1])
    b = ((a + math.pi) / (2 * math.pi) * NB).astype(int) % NB
    dist = np.linalg.norm(d, axis=1)
    for i in range(NB):
        m = b == i
        if m.any():
            r[i] = dist[m].max()
    return r


def poke(cover, inner, ys, c):
    """worst (inner radius - cover radius) over heights ys and bins where both exist; count of poking bins"""
    worst, n = -1.0, 0
    for y in ys:
        rc = radial_max(sec(cover["P"], cover["T"], y), c)
        for P, T in inner:
            ri = radial_max(sec(P, T, y), c)
            m = ~np.isnan(rc) & ~np.isnan(ri)
            if m.any():
                dd = ri[m] - rc[m]
                worst = max(worst, float(dd.max()))
                n += int((dd > 0.003).sum())
    return worst, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiers", default="1,3,5")
    ap.add_argument("--swing", default="-25,0,30")
    a = ap.parse_args()
    B = bg.Bodies()
    gear, _ = bg.build_all(B)
    swings = [float(x) for x in a.swing.split(",")]
    for n in (int(x) for x in a.tiers.split(",")):
        g = gear[n]
        band, seat = g["Waistband"][0], g["TrunkSeat"][0]
        c = np.array([0.0, float((B.part(n, "LowerTorso")["P"][:, 2].min() + B.part(n, "LowerTorso")["P"][:, 2].max()) / 2)])
        lt, ut = B.part(n, "LowerTorso"), B.part(n, "UpperTorso")
        # band over the seat top, the LowerTorso and the UpperTorso's hem
        ys = np.linspace(bg.Y_BAND[0] + 0.02, bg.Y_BAND[1] - 0.02, 6)
        for nm, src in (("seat", seat), ("LT", lt), ("UT", ut)):
            w1 = poke(band, [(src["P"], src["T"])], ys, c)
            print(f"T{n} band over {nm:4s}  worst {w1[0]:+.3f} ({w1[1]} bins)")
        for sw in swings:
            legs = []
            for s in ("Right", "Left"):
                ul = B.part(n, s + "UpperLeg")
                hip = B.J(n, s + "Hip")
                legs.append((bg.swung(ul["P"], hip, sw if s == "Right" else -sw), ul["T"]))
            ys = np.linspace(bg.Y_SEAT[0] + 0.02, bg.Y_SEAT[1] - 0.04, 8)
            w2 = poke(seat, [(lt["P"], lt["T"])] + legs, ys, c)
            # the shorts legs (their own axis: the leg) over the thigh, swung together
            worst3 = -1.0
            for s, key in (("Right", "TrunkLeg_R"), ("Left", "TrunkLeg_L")):
                ul = B.part(n, s + "UpperLeg")
                hip = B.J(n, s + "Hip")
                deg = sw if s == "Right" else -sw
                leg = g[key][0]
                LP = bg.swung(leg["P"], hip, deg)
                UP = bg.swung(ul["P"], hip, deg)
                for y in np.linspace(bg.Y_HEM["short"] + 0.05, bg.Y_SEAT[0] - 0.02, 5):
                    # (approximately: sections at world heights of the swung leg)
                    cc = bg.centroid([{"P": UP, "T": ul["T"]}], y)
                    if cc is None:
                        continue
                    rc = radial_max(sec(LP, leg["T"], y), cc)
                    ri = radial_max(sec(UP, ul["T"], y), cc)
                    m = ~np.isnan(rc) & ~np.isnan(ri)
                    if m.any():
                        worst3 = max(worst3, float((ri[m] - rc[m]).max()))
            print(f"T{n} swing {sw:+5.0f}: seat over LT+thighs worst {w2[0]:+.3f} ({w2[1]} bins)   leg over thigh worst {worst3:+.3f}")


if __name__ == "__main__":
    main()
