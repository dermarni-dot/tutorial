"""BuilderBody's TORSO_SURF (the tier torsos' skin as a box-normalised radius table, for the marks lying on it:
Body.SurfaceMark - rib bruises, the body-shot flush): every tier's UpperTorso.mesh sampled per row v (-0.45 .. 0.45
of Size.Y by 0.1) and azimuth from the front (0) to the side (90 deg) by 15, both sides averaged.

    python3 tools/body/torso_surf.py [--src tools/body/out] [--write]    # --write: replace the table in BuilderBody
"""
import argparse
import os
import re
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LUA = os.path.join(ROOT, "src", "shared", "BuilderBody.lua")


def read_mesh(path):
    with open(path, "rb") as f:
        data = f.read()
    i = data.index(b"\n") + 1
    hs, vs, fs, nv, nt = struct.unpack_from("<HBBII", data, i)
    i += hs
    P = np.array([struct.unpack_from("<3f", data, i + k * vs) for k in range(nv)], np.float64)
    i += nv * vs
    T = np.array([struct.unpack_from("<3I", data, i + k * fs) for k in range(nt)], np.int64)
    return P, T


def ray(P, T, o, d):
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
    return float(t[hit].max()) if hit.any() else None


def table(src):
    out = {}
    for n in range(1, 6):
        P, T = read_mesh(os.path.join(src, "tier%d" % n, "UpperTorso.mesh"))
        S = P.max(0) - P.min(0)
        rows = []
        for v in np.arange(-0.45, 0.4501, 0.1):
            row = []
            for a in np.radians(np.arange(0, 91, 15)):
                rs = []
                for sg in (1, -1):
                    o = np.array([0.0, v * S[1], 0.0])
                    d = np.array([sg * np.sin(a) * S[0], 0.0, -np.cos(a) * S[2]])
                    L = np.linalg.norm(d)
                    t = ray(P, T, o, d / L)  # the outermost crossing
                    rs.append((t / L) if t is not None else 0.5)
                row.append(float(np.mean(rs)))
            rows.append(row)
        out[n] = rows
    return out


def lua(tab):
    lines = []
    for n in range(1, 6):
        rows = ", ".join("{ " + ", ".join("%.3f" % x for x in r) + " }" for r in tab[n])
        lines.append("\t[%d] = { %s }," % (n, rows))
    return "local TORSO_SURF = {\n" + "\n".join(lines) + "\n}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(HERE, "out"))
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    t = lua(table(a.src))
    if a.write:
        s = open(LUA).read()
        s2, k = re.subn(r"local TORSO_SURF = \{\n(?:\t\[\d\] = .*\n)+\}", lambda m: t, s)
        assert k == 1, k
        open(LUA, "w").write(s2)
        print("wrote", LUA)
    else:
        print(t)


if __name__ == "__main__":
    sys.exit(main())
