"""Cycles renders of the ring officials exported by tools/sim/v9_referee.luau (world space, studs, +Y up).

    /opt/bpyenv/bin/python tools/sim/v9_referee_render.py SCENE_DIR OUT_DIR [--tag before] [--only id,id]
                                                          [--samples N] [--views front,34,side,back] [--ring 1]
                                                          [--closeups 1] [--heads 0|1|2]

Per shot: the official in front / 3/4 / side (and back) views framed on him, the two boxers behind him for scale, in a
simple ring (canvas, corner posts, three ropes; half 12); a sheet <tag>_<shot>.jpg. Then <tag>_closeup.jpg: the stance shots'
upper body (shirt, collar, bow tie, badge) and shoes; with --heads 1, <tag>_heads.jpg: the stand shots' heads (the caps;
--heads 2 adds a boxer's head in his headgear). Geometry, materials, the classic head and its decal: v8_render.py.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hair"))
import v8_render as v8  # noqa: E402
import render  # noqa: E402
import bpy  # noqa: E402

VIEWS = {"front": (0, 6, 1.0), "34": (38, 8, 1.0), "side": (90, 4, 1.0), "back": (180, 6, 1.0),
         "34back": (145, 8, 1.0)}
LABEL = {"front": "front", "34": "3/4", "side": "side", "back": "back", "34back": "back 3/4"}


def ring(sc):
    """canvas, corner posts and three ropes (ring half 12 studs, about the game's RingHalf 11, centred on the
    referee's spot: the cameras, about 10 studs out, stay inside the ropes)"""
    cz = 0.0
    h = 12.0
    P = np.array([(-h, 0.005, cz - h), (h, 0.005, cz - h), (h, 0.005, cz + h), (-h, 0.005, cz + h)], float)
    T = np.array([(0, 2, 1), (0, 3, 2)])
    canvas = sc.gear_mat((0.80, 0.82, 0.86), "Fabric", 0)
    sc.add_world(P, T, "canvas", mat=canvas, smooth=False)
    post = sc.gear_mat((0.75, 0.75, 0.78), "Metal", 0)
    rope = sc.gear_mat((0.75, 0.06, 0.06), "SmoothPlastic", 0)
    for sx in (-1, 1):
        for sz in (-1, 1):
            Pp, Tp = v8.box(0.35, 4.6, 0.35)
            sc.add_world(Pp + np.array([sx * h, 2.3, cz + sz * h]), Tp, "post", mat=post, smooth=False)
    for y in (1.6, 2.7, 3.8):
        for (x0, z0, x1, z1) in ((-h, -h, h, -h), (-h, h, h, h), (-h, -h, -h, h), (h, -h, h, h)):
            length = math.hypot(x1 - x0, z1 - z0)
            Pc, Tc = v8.cylinder_x(length, 0.07, 0.07, n=12)
            ang = math.atan2(z1 - z0, x1 - x0)
            R = np.array([[math.cos(ang), 0, -math.sin(ang)], [0, 1, 0], [math.sin(ang), 0, math.cos(ang)]])
            c = np.array([(x0 + x1) / 2, y, cz + (z0 + z1) / 2])
            sc.add_world(Pc @ R.T + c, Tc, "rope", mat=rope)


def add_fig(sc, scene_dir, f):
    d = dict(f)
    d.setdefault("hair", [])
    d.setdefault("parts", [])
    v8.add_boxer(sc, scene_dir, d)


def official_of(shot):
    for f in shot["figures"]:
        if f["role"] in ("referee", "cornerman"):
            return f
    return shot["figures"][-1]


def body_focus(f):
    hd = f["head"]
    p = np.array(hd["cf"][:3])
    top = p[1] + hd["size"][1] / 2 + 0.15
    return np.array([p[0], top / 2, p[2]]), top


def render_shot(scene_dir, out_dir, shot, tag, samples, views, with_ring):
    sc = v8.V8Scene(res=(440, 720), samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
    if with_ring:
        ring(sc)
    for f in shot["figures"]:
        add_fig(sc, scene_dir, f)
    ref = official_of(shot)
    focus, top = body_focus(ref)
    dist = (top / 2 + 0.5) / math.tan(math.atan(18 / 50)) * 1.05
    paths, labels = [], []
    for v in views:
        p = os.path.join(out_dir, f"_{tag}_{shot['id']}_{v}.png")
        sc.rig(tuple(focus), 3.0)
        sc.render(p, view=VIEWS[v], dist=dist, focus=tuple(focus))
        paths.append(p)
        labels.append(LABEL[v])
    title = f"{tag}: {shot['id']} - {shot['label']}"
    r = shot.get("ref") or {}
    if r:
        title += f"   [{r.get('kind')} seed {r.get('seed')}, tiers {r.get('tiers')}, face {r.get('face')}]"
    out = os.path.join(out_dir, f"{tag}_{shot['id']}.jpg")
    render.sheet(paths, out, cols=len(paths), labels=labels, title=title)
    for p in paths:
        os.remove(p)
    print("rendered", out, flush=True)
    return out


def render_closeups(scene_dir, out_dir, shots, tag, samples):
    paths, labels = [], []
    for shot in shots:
        sc = v8.V8Scene(res=(420, 420), samples=samples, lens=85, bg=(0.11, 0.115, 0.125))
        ref = official_of(shot)
        add_fig(sc, scene_dir, ref)
        hp = np.array(ref["head"]["cf"][:3])
        for name, f, v, dist in (("chest", hp + np.array([0, -1.25, 0]), (20, 6, 1.0), 1.9),
                                 ("shoulder", hp + np.array([0, -1.2, 0]), (70, 10, 1.0), 1.9),
                                 ("back", hp + np.array([0, -1.4, 0]), (180, 8, 1.0), 2.2),
                                 ("waist", hp + np.array([0, -2.9, 0]), (25, 8, 1.0), 2.0),
                                 ("shoes", np.array([hp[0], 0.45, hp[2]]), (30, 18, 1.0), 2.0)):
            p = os.path.join(out_dir, f"_{tag}_{shot['id']}_c_{name}.png")
            sc.rig(tuple(f), 1.4)
            sc.render(p, view=v, dist=dist / math.tan(math.atan(18 / 85)) / 2.2, focus=tuple(f))
            paths.append(p)
            labels.append(f"{shot['id']} {name}")
    out = os.path.join(out_dir, f"{tag}_closeup.jpg")
    render.sheet(paths, out, cols=5, labels=labels, title=f"{tag}: close-ups (shirt, collar / bow tie, badge, belt, shoes)")
    for p in paths:
        os.remove(p)
    print("rendered", out, flush=True)


def render_heads(scene_dir, out_dir, shots, tag, samples, views, boxers=False):
    """<tag>_heads.jpg: each stand shot's head and shoulders (the officials' cap on the drawn face) in the given views;
    boxers=True adds the first boxer of each shot (his headgear)"""
    paths, labels = [], []
    for shot in shots:
        figs = [official_of(shot)]
        if boxers:
            figs += [f for f in shot["figures"] if f["role"] == "boxer"][:1]
        for fig in figs:
            sc = v8.V8Scene(res=(420, 420), samples=samples, lens=85, bg=(0.11, 0.115, 0.125))
            if fig["role"] == "boxer":
                # his guard would hide the head: no arms, hands or gloves in the close-up
                arm = ("Arm", "Hand", "Glove", "Wrap", "Cuff", "Knuckle")
                fig = dict(fig, meshes=[m for m in fig["meshes"] if not any(k in m["name"] for k in arm)],
                           parts=[g for g in fig.get("parts", []) if not any(k in g["name"] for k in arm)])
            add_fig(sc, scene_dir, fig)
            hp = np.array(fig["head"]["cf"][:3])
            f = hp + np.array([0, -0.05, 0])
            for v in views:
                p = os.path.join(out_dir, f"_{tag}_{shot['id']}_{fig['role']}_h_{v}.png")
                sc.rig(tuple(f), 1.2)
                sc.render(p, view=VIEWS[v], dist=1.5 / math.tan(math.atan(18 / 85)) / 2.2, focus=tuple(f))
                paths.append(p)
                labels.append(f"{shot['id']} {fig['role']} {LABEL[v]}")
    out = os.path.join(out_dir, f"{tag}_heads.jpg")
    render.sheet(paths, out, cols=len(views), labels=labels, title=f"{tag}: head close-ups (the officials' caps)")
    for p in paths:
        os.remove(p)
    print("rendered", out, flush=True)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" in sys.argv:
        argv = sys.argv[sys.argv.index("--") + 1:]
    scene_dir, out_dir = argv[0], argv[1]
    opts = {}
    i = 2
    while i < len(argv):
        opts[argv[i]] = argv[i + 1]
        i += 2
    os.makedirs(out_dir, exist_ok=True)
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    only = set(opts["--only"].split(",")) if "--only" in opts else None
    tag = opts.get("--tag", "after")
    samples = int(opts.get("--samples", 24))
    views = opts.get("--views", "front,34,side,back").split(",")
    with_ring = opts.get("--ring", "1") != "0"
    shots = []
    for s in idx["shots"]:
        if only and s["id"] not in only:
            continue
        shot = json.load(open(os.path.join(scene_dir, s["file"])))
        shot["ref"] = s.get("ref")
        shots.append(shot)
        render_shot(scene_dir, out_dir, shot, tag, samples, views, with_ring)
    stands = [s for s in shots if s["id"].startswith(("stand_", "coach_"))]
    if stands and opts.get("--closeups", "1") != "0":
        render_closeups(scene_dir, out_dir, stands, tag, samples)
    if stands and opts.get("--heads", "0") != "0":
        render_heads(scene_dir, out_dir, stands, tag, samples, views, boxers=opts.get("--heads") == "2")
