"""The classic-head reference set the v9 hair is modelled on (tools/hair/ref/classic), from the game's own data:

    lune run tools/sim/export_classic.luau          # skull_game.json / skull_game_f.json (the game's Kit)
    /opt/bpyenv/bin/python tools/hair/classic_ref.py

* The head: the classic Roblox head (a Part with the Head SpecialMesh), the game's model of it
  (AnatomyHairKit.CLASSIC: a vertical cylinder r 0.6 filling its 1.2 box, top and bottom edges rounded by 0.24,
  nominal), revolved finely. Kit.Scalp's classic field is the same shape, so the runtime fit, the cap's painted
  UV and this mesh agree exactly.
* The built face on it: the game's own (BuilderHead Head.Face at the default face, full detail, nominal = real / k),
  every part as its ellipsoid, from a v9_faces scene kept as ref/classic/face_m.json; refresh it after a face change:
      lune run tools/sim/v9_faces.luau --only m_classic_neutral --out /tmp/claude-0/v9faces
      /opt/bpyenv/bin/python tools/hair/classic_ref.py --scene /tmp/claude-0/v9faces/m_classic_neutral.json
  The ears (shell + concha; scaled 1.1 about their middle for the clearance boxes so a bigger ear still clears),
  the brows (inner / body / tail), the eyes and lids, the nose and the lips; skin sculpt parts go in FaceSkin. The ears are part of the "Head" collider object (the builders
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
import sys

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


# the built face is not approximated here: it is the game's own (BuilderHead.Head.Face at the default face, full detail),
# exported by tools/sim/v9_faces.luau and kept as a snapshot in nominal head space (FACE_SNAPSHOT)
FACE_SNAPSHOT = os.path.join(REF, "face_m.json")
# which object each built part goes to (the renderer keeps the own colours of Brow* / Sclera* / Iris* / Pupil* / Lips* /
# Lashes* / Nostril*; the rest is tinted as skin)
GROUPS = [
    (("Ear", "EarHelix", "Cauliflower"), "Ear"),
    (("Brow", "BrowInner", "BrowOuter", "BrowGap"), "Brow"),
    (("Sclera",), "Sclera"),
    (("Limbal", "Iris"), "Iris"),
    (("Pupil", "Glint"), "Pupil"),
    (("Lashes",), "Lashes"),
    (("Nose", "NoseTip", "NoseWing", "NoseBump"), "Nose"),
    (("Nostril",), "Nostril"),
    (("UpperLip", "LowerLip", "MouthLine", "MouthCorner", "MouthInside", "TeethUpper", "TeethLower"), "Lips"),
]
SIDED = {"Ear", "Brow", "Sclera", "Iris", "Pupil", "Lashes"}
HIDDEN = {"BlinkLid", "EyeBall", "TempleVein", "ForeheadVein"}  # (shown only while blinking / straining)


def snapshot_from_scene(scene_path):
    """a v9_faces scene (world space) -> the Face folder's visible parts in nominal head space"""
    d = json.load(open(scene_path))
    hc = np.array(d["head"]["cf"][:3])
    HR = np.array(d["head"]["cf"][3:]).reshape(3, 3)
    k = d["head"]["size"][0] / S
    parts = []
    for p in d["parts"]:
        if p["folder"] != "Face" or p["name"] in HIDDEN or p.get("transparency", 0) >= 0.99 or p["shape"] != "Ellipsoid":
            continue
        c = HR.T @ (np.array(p["cf"][:3]) - hc) / k
        M = HR.T @ np.array(p["cf"][3:]).reshape(3, 3)
        parts.append({"name": p["name"], "c": [round(float(x), 5) for x in c], "m": [round(float(x), 5) for x in M.flatten()],
                      "half": [round(x / 2 / k, 5) for x in p["size"]], "rgb": p["color"], "t": p.get("transparency", 0)})
    return {"about": "BuilderHead's built face at the default face (full detail), nominal head space (1.2 box), from "
                     + os.path.basename(scene_path) + " (tools/sim/v9_faces.luau)", "parts": parts}


def face_parts(ear_s=1.0, snap=None):
    """{name: (P, T, rgb)} of the built face from the snapshot; ear_s scales the ears about their own middle"""
    snap = snap or json.load(open(FACE_SNAPSHOT))
    acc = {}
    for p in snap["parts"]:
        group = "FaceSkin"
        for names, g in GROUPS:
            if p["name"] in names:
                group = g
        if p["t"] > 0.6:
            continue  # (faint translucent marks: no clearance, no colour worth drawing)
        if group in SIDED:
            group += "L" if p["c"][0] < 0 else "R"
        M = np.array(p["m"]).reshape(3, 3)
        P, T = ellipsoid(p["c"], p["half"], nu=20, nv=12, frame=M)
        cols = np.tile(p["rgb"], (len(P), 1))
        acc.setdefault(group, []).append((P, T, cols))
    out = {}
    for g, lst in acc.items():
        Ps, Ts, Cs, n = [], [], [], 0
        for P, T, C in lst:
            Ps.append(P)
            Ts.append(T + n)
            Cs.append(C)
            n += len(P)
        P = np.vstack(Ps)
        if g.startswith("Ear") and ear_s != 1.0:
            m = P.mean(axis=0)
            P = m + (P - m) * ear_s
        out[g] = (P, np.vstack(Ts), np.vstack(Cs))
    return out


def write_obj(path, objs):
    """objs: [(name, P, T, rgb or None)] -> OBJ ('v x y z r g b', one 'o' per object, 1-based faces)"""
    lines = ["# classic Roblox head + the built face (tools/hair/classic_ref.py), nominal head space"]
    base = 0
    for name, P, T, rgb in objs:
        lines.append(f"o {name}")
        C = np.tile(rgb if rgb is not None else (0.8, 0.8, 0.8), (len(P), 1)) if rgb is None or np.ndim(rgb) == 1 else rgb
        for p, c in zip(P, C):
            lines.append("v %.5f %.5f %.5f %.4f %.4f %.4f" % (p[0], p[1], p[2], c[0], c[1], c[2]))
        for t in T:
            lines.append("f %d %d %d" % (t[0] + 1 + base, t[1] + 1 + base, t[2] + 1 + base))
        base += len(P)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    os.makedirs(REF, exist_ok=True)
    if "--scene" in sys.argv:
        snap = snapshot_from_scene(sys.argv[sys.argv.index("--scene") + 1])
        with open(FACE_SNAPSHOT, "w") as f:
            json.dump(snap, f, indent=0)
        print("face snapshot", FACE_SNAPSHOT, len(snap["parts"]), "parts")
    Ph, Th = revolve(profile())
    parts = face_parts(ear_s=1.0)
    big = face_parts(ear_s=1.1)  # (earSize +0.5: the clearance boxes)
    # the collider "Head": the head + both ears (the hair goes round them)
    PH, TH = [Ph], [Th]
    n = len(Ph)
    for e in ("EarL", "EarR"):
        P, T, _ = parts[e]  # (the head object is tinted as skin: the ears' own colours are dropped)
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
    bP = np.vstack([parts["BrowL"][0], parts["BrowR"][0]])
    bR = parts["BrowR"][0]
    browTop = float(bP[:, 1].max())
    face = {"about": "the built face at the default face (BuilderHead.FaceLayout, nominal). browTop: the brows' top "
                     "edge; browTopMax: with forehead +1 and browHeight +1 (the highest brows the creator makes: "
                     "+0.055 x 1.2); the hair's front edge stays above browTopMax + `browClear`",
            "eyeY": 0.12, "eyeX": 0.228, "browY": 0.276, "browTop": round(browTop, 4), "browTopMax": round(browTop + 0.066, 4),
            "browClear": 0.03, "browX": [round(float(bR[:, 0].min()), 3), round(float(bR[:, 0].max()), 3)]}
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
