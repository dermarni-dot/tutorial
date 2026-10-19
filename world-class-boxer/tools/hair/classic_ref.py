"""The classic-head reference set the v9 hair is modelled on (tools/hair/ref/classic), from the game's own data:

    lune run tools/sim/export_classic.luau          # skull_game.json / skull_game_f.json (the game's Kit)
    /opt/bpyenv/bin/python tools/hair/classic_ref.py

* The head: the classic Roblox head (a Part with the Head SpecialMesh), the game's model of it
  (AnatomyHairKit.CLASSIC: a vertical cylinder r 0.6 filling its 1.2 box, top and bottom edges rounded by 0.24,
  nominal), revolved finely. Kit.Scalp's classic field is the same shape, so the runtime fit, the cap's painted
  UV and this mesh agree exactly.
* The built face on it (BuilderHead.FaceLayout and Head.Face at the default face, nominal = real / k): the ears
  (shell + helix rim, at earSize +0.5 for the clearance boxes so a bigger ear still clears), the brows (inner /
  body / tail), the eyes, the nose and the lips. The ears are part of the "Head" collider object (the builders
  push hair clear of it); brows, eyes, nose and lips are separate objects (renders, the brow clearance check).
* skull.json / skull_f.json: the game export plus `ears` (AABBs of the ear vertices, as the organic reference had)
  and `face` (brow / eye / ear landmarks and the brow band the hair must stay above).
* head_m.obj = head_f.obj (every boxer has the same classic head; only its size differs, HeadScale), and the
  torso proxies (torso_m / torso_f.obj) carried over from the organic reference (the rig is unchanged).
"""
import json
import math
import os
import shutil

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REF0 = os.path.join(HERE, "ref")
REF = os.path.join(REF0, "classic")

R, HH, RR = 0.6, 0.6, 0.24  # AnatomyHairKit.CLASSIC
S = 1.2  # nominal head size (FaceLayout's s.X = s.Y = s.Z)


def sd_classic(p):
    p = np.atleast_2d(p)
    qx = np.sqrt(p[:, 0] ** 2 + p[:, 2] ** 2) - (R - RR)
    qy = np.abs(p[:, 1]) - (HH - RR)
    ox, oy = np.maximum(qx, 0), np.maximum(qy, 0)
    return np.sqrt(ox * ox + oy * oy) + np.minimum(np.maximum(qx, qy), 0) - RR


def profile(n_arc=28, n_wall=30, n_cap=14):
    """(rho, y) from the bottom pole to the top pole"""
    pts = []
    for i in range(n_cap):
        pts.append(((R - RR) * i / n_cap, -HH))
    for i in range(n_arc):
        a = -math.pi / 2 + (math.pi / 2) * i / n_arc
        pts.append((R - RR + RR * math.cos(a), -(HH - RR) + RR * math.sin(a)))
    for i in range(n_wall):
        pts.append((R, -(HH - RR) + 2 * (HH - RR) * i / n_wall))
    for i in range(n_arc):
        a = (math.pi / 2) * i / n_arc
        pts.append((R - RR + RR * math.cos(a), (HH - RR) + RR * math.sin(a)))
    for i in range(n_cap + 1):
        pts.append(((R - RR) * (1 - i / n_cap), HH))
    return pts


def revolve(prof, nseg=128):
    P, T = [], []
    m = len(prof)
    for i in range(nseg):
        a = 2 * math.pi * i / nseg
        for rho, y in prof:
            P.append((rho * math.sin(a), y, rho * math.cos(a)))
    for i in range(nseg):
        i2 = (i + 1) % nseg
        for j in range(m - 1):
            a, b = i * m + j, i * m + j + 1
            c, d = i2 * m + j, i2 * m + j + 1
            T += [(a, c, b), (b, c, d)]
    return np.array(P), np.array(T)


def ellipsoid(centre, half, rot_y=0.0, nu=28, nv=16, frame=None):
    """an ellipsoid (Roblox Part Shape Ball / SpecialMesh Sphere: the box's inscribed ellipsoid)"""
    P, T = [], []
    for i in range(nv + 1):
        v = math.pi * i / nv
        for j in range(nu):
            u = 2 * math.pi * j / nu
            P.append((half[0] * math.sin(v) * math.cos(u), half[1] * math.cos(v), half[2] * math.sin(v) * math.sin(u)))
    for i in range(nv):
        for j in range(nu):
            a, b = i * nu + j, i * nu + (j + 1) % nu
            c, d = (i + 1) * nu + j, (i + 1) * nu + (j + 1) % nu
            T += [(a, b, d), (a, d, c)]
    P = np.array(P)
    M = rot_y_m(rot_y) if frame is None else frame
    P = P @ M.T + np.asarray(centre)
    return P, np.array(T)


def rot_y_m(a):
    c, s = math.cos(a), math.sin(a)
    # Roblox CFrame.Angles(0, a, 0): x' = x c + z s, z' = -x s + z c
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z_m(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def front(x):
    k = max(-0.97, min(0.97, x / (S * 0.5)))
    return -S * 0.5 * math.sqrt(1 - k * k)


def face_parts(ear_s=1.0):
    """{name: (P, T, rgb)} of the built face at the default face (BuilderHead.Head.Face, full detail)"""
    out = {}
    eyeX, eyeY = 0.19 * S, 0.1 * S
    browY = eyeY + 0.13 * S
    # ears: shell + helix rim (ecf = at(side 0.5 s.X, 0.02 s.Y, 0.04 s.Z) * ANG(0, side 6 deg, 0))
    for side, nm in ((-1, "L"), (1, "R")):
        M = rot_y_m(side * math.radians(6))
        c = np.array([side * 0.5 * S, 0.02 * S, 0.04 * S])
        P1, T1 = ellipsoid(c, (0.04 * S, 0.125 * S * ear_s, 0.085 * S * ear_s), frame=M)
        off = M @ np.array([side * 0.03 * S, 0.015 * S, 0.055 * S * ear_s])
        P2, T2 = ellipsoid(c + off, (0.0225 * S, 0.13 * S * ear_s, 0.03 * S * ear_s), frame=M)
        out["Ear" + nm] = (np.vstack([P1, P2]), np.vstack([T1, T2 + len(P1)]), None)
    bt = (0.028 + 0.02) * S
    blen = 0.21 * S
    for side, nm in ((-1, "L"), (1, "R")):
        bx = side * eyeX * 1.02
        parts = [(bx, browY, blen * 0.23, bt * 0.5, 0.0175 * S, 0.0, -0.012),
                 (bx - side * blen * 0.36, browY - bt * 0.1, blen * 0.18, bt * 0.56, 0.0175 * S, side * 0.12, -0.01),
                 (bx + side * blen * 0.36, browY - bt * 0.18, blen * 0.19, bt * 0.37, 0.015 * S, -side * 0.2, -0.01)]
        Ps, Ts, n = [], [], 0
        for x, y, hx, hy, hz, tilt, dz in parts:
            Pp, Tp = ellipsoid((x, y, front(x) + dz), (hx, hy, hz), frame=rot_z_m(tilt) @ rot_y_m(-side * 0.14))
            Ps.append(Pp)
            Ts.append(Tp + n)
            n += len(Pp)
        out["Brow" + nm] = (np.vstack(Ps), np.vstack(Ts), (0.045, 0.035, 0.03))
        # eye: sclera, iris, pupil (layered on the face front)
        ex = side * eyeX
        z0 = front(ex)
        out["Sclera" + nm] = ellipsoid((ex, eyeY, z0 + 0.004), (0.06, 0.045, 0.03)) + ((0.93, 0.92, 0.9),)
        out["Iris" + nm] = ellipsoid((ex, eyeY, z0 - 0.022), (0.03, 0.03, 0.012)) + ((0.28, 0.17, 0.08),)
        out["Pupil" + nm] = ellipsoid((ex, eyeY, z0 - 0.031), (0.014, 0.014, 0.006)) + ((0.02, 0.02, 0.02),)
    noseTop = eyeY - 0.02 * S
    noseLen = 0.2 * S
    noseBot = noseTop - noseLen
    nW, nB = 0.11 * S, 0.085 * S
    Pn, Tn = ellipsoid((0, (noseTop + noseBot) / 2 + noseLen * 0.04, front(0) - nB * 0.3 + 0.012),
                       (nW * 0.31, noseLen * 0.54, nB * 0.39), frame=np.array([[1, 0, 0], [0, math.cos(-0.17), -math.sin(-0.17)], [0, math.sin(-0.17), math.cos(-0.17)]]))
    Pt, Tt = ellipsoid((0, noseBot + nW * 0.25, front(0) - nB * 0.75), (nW * 0.56, nW * 0.35, nB * 0.33))
    out["Nose"] = (np.vstack([Pn, Pt]), np.vstack([Tn, Tt + len(Pn)]), None)
    mouthY = -0.21 * S
    mw = 0.26 * S
    out["Lips"] = ellipsoid((0, mouthY, front(0) + 0.004), (mw * 0.5, 0.03, 0.03)) + ((0.5, 0.27, 0.24),)
    return out


def write_obj(path, objs):
    """objs: [(name, P, T, rgb or None)] -> OBJ ('v x y z r g b', one 'o' per object, 1-based faces)"""
    lines = ["# classic Roblox head + the built face (tools/hair/classic_ref.py), nominal head space"]
    base = 0
    for name, P, T, rgb in objs:
        lines.append(f"o {name}")
        c = rgb or (0.8, 0.8, 0.8)
        for p in P:
            lines.append("v %.5f %.5f %.5f %.4f %.4f %.4f" % (p[0], p[1], p[2], c[0], c[1], c[2]))
        for t in T:
            lines.append("f %d %d %d" % (t[0] + 1 + base, t[1] + 1 + base, t[2] + 1 + base))
        base += len(P)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    os.makedirs(REF, exist_ok=True)
    Ph, Th = revolve(profile())
    parts = face_parts(ear_s=1.0)
    big = face_parts(ear_s=1.1)  # (earSize +0.5: the clearance boxes)
    # the collider "Head": the head + both ears (the hair goes round them)
    PH, TH = [Ph], [Th]
    n = len(Ph)
    for e in ("EarL", "EarR"):
        P, T, _ = parts[e]
        PH.append(P)
        TH.append(T + n)
        n += len(P)
    objs = [("Head", np.vstack(PH), np.vstack(TH), None)]
    for name, (P, T, rgb) in parts.items():
        if not name.startswith("Ear"):
            objs.append((name, P, T, rgb))
    for tag in ("m", "f"):
        write_obj(os.path.join(REF, f"head_{tag}.obj"), objs)
        shutil.copy(os.path.join(REF0, f"torso_{tag}.obj"), os.path.join(REF, f"torso_{tag}.obj"))
    ears = {"clearance": 0.02, "note": "AABB of the built face's ear vertices (shell + helix rim, earSize +0.5), "
            "nominal; keep hair cards at least `clearance` outside it (tuck behind / above)"}
    for side, nm in (("left", "EarL"), ("right", "EarR")):
        P = big[nm][0]
        ears[side] = {"min": [round(float(x), 4) for x in P.min(axis=0)],
                      "max": [round(float(x), 4) for x in P.max(axis=0)], "verts": int(len(P))}
    face = {"about": "the built face at the default face (BuilderHead.FaceLayout, nominal). browTop: the brows' top "
                     "edge (centre, outer); browTopMax: with forehead +1 and browHeight +1 (the highest brows the "
                     "creator makes); the hair's front edge stays above browTopMax + `browClear`",
            "eyeY": 0.12, "eyeX": 0.228, "browY": 0.276, "browTop": 0.305, "browTopMax": 0.371,
            "browClear": 0.03, "browX": [0.12, 0.35]}
    lm = {}
    for nm in ("BrowL", "BrowR", "EarL", "EarR", "Nose", "Lips"):
        P = parts[nm][0]
        lm[nm] = {"min": [round(float(x), 4) for x in P.min(axis=0)], "max": [round(float(x), 4) for x in P.max(axis=0)]}
    face["boxes"] = lm
    for src, dst in (("skull_game.json", "skull.json"), ("skull_game_f.json", "skull_f.json")):
        with open(os.path.join(REF, src)) as f:
            d = json.load(f)
        d["ears"] = ears
        d["face"] = face
        d["landmarks"] = {"head": {k: [round((v["min"][i] + v["max"][i]) / 2, 4) for i in range(3)] for k, v in lm.items()}}
        with open(os.path.join(REF, dst), "w") as f:
            json.dump(d, f)
    # a check: the revolved mesh against the field
    err = np.abs(sd_classic(Ph)).max()
    print("head verts %d tris %d, |sdf| on the mesh <= %.5f" % (len(Ph), len(Th), err))
    print("ears", json.dumps({k: ears[k] for k in ("left", "right")}))
    print("brows", lm["BrowR"])


if __name__ == "__main__":
    main()
