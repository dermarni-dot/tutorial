"""Cycles renders of the post-fight scene staged by tools/sim/v10_postfight_scene.luau (world space, studs, +Y up;
the canvas at y = 0): two heavyweights and the referee at PostFight.Layout's places, before and after the hand goes up,
from straight above (top) and from the hard camera (BoxerClient.Ceremony's result shot).

    /opt/bpyenv/bin/python tools/sim/v10_postfight_render.py SCENE_DIR OUT_DIR [--samples N] [--res 960x540] [--only id,id]

-> <OUT>/<id>_top.jpg, <OUT>/<id>_hard.jpg and the sheet postfight_scene.jpg (with each frame's body gaps in the label).
Geometry and materials: v8_render.py (the tier meshes, gear, the classic head + decal); the arena from v9_ceremony_render.
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hair"))
import v8_render as v8  # noqa: E402
import v9_ceremony_render as cer  # noqa: E402
import render  # noqa: E402
import bpy  # noqa: E402


def render_frame(scene_dir, frame, view, out_path, samples, res):
    rng = np.random.default_rng(7)
    sc = cer.new_scene(res, samples, lens=50, bg=(0.02, 0.02, 0.026))
    cer.drop_floor(sc)
    cer.arena(sc, rng, True)
    heads = []
    for f in frame["figures"]:
        d = dict(f)
        d.setdefault("hair", [])
        d.setdefault("parts", [])
        v8.add_boxer(sc, scene_dir, d)
        if f.get("head"):
            heads.append(np.array(f["head"]["cf"][:3]))
    focus = np.mean(heads, axis=0) if heads else np.array([0, 5, 0])
    sc.rig(tuple(focus - np.array([0, 1.4, 0])), 3.2)
    cam = frame["cameras"][view]
    cer.set_camera(sc, cam["cf"], cam["fov"])
    if view == "top":
        # the centre line marks: the picture's facing (-Z) and the line of the men (X)
        for k in range(-6, 7):
            P, T = v8.box(0.03, 0.012, 12.0)
            sc.add_world(P + np.array([k, 0.006, 0]), T, "markx", mat=sc.gear_mat((0.42, 0.42, 0.45), "SmoothPlastic", 0), smooth=False)
            P, T = v8.box(12.0, 0.012, 0.03)
            sc.add_world(P + np.array([0, 0.006, k]), T, "markz", mat=sc.gear_mat((0.42, 0.42, 0.45), "SmoothPlastic", 0), smooth=False)
    sc.sc.render.filepath = os.path.abspath(out_path)
    bpy.ops.render.render(write_still=True)
    return out_path


def main():
    argv = sys.argv[1:]
    if "--" in sys.argv:
        argv = sys.argv[sys.argv.index("--") + 1:]
    scene_dir, out_dir = argv[0], argv[1]
    opts = {}
    i = 2
    while i < len(argv):
        opts[argv[i]] = argv[i + 1]
        i += 2
    samples = int(opts.get("--samples", "24"))
    w, h = (int(x) for x in opts.get("--res", "960x540").split("x"))
    only = set(opts["--only"].split(",")) if "--only" in opts else None
    os.makedirs(out_dir, exist_ok=True)
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    outs, labels = [], []
    for fr_ in idx["frames"]:
        if only and fr_["id"] not in only:
            continue
        frame = json.load(open(os.path.join(scene_dir, fr_["file"])))
        g = frame["gaps"]
        for view in ("top", "hard"):
            p = os.path.join(out_dir, f"{frame['id']}_{view}.png")
            render_frame(scene_dir, frame, view, p, samples, (w, h))
            jpg = p[:-4] + ".jpg"
            render.Image.open(p).convert("RGB").save(jpg, quality=90) if hasattr(render, "Image") else None
            if os.path.exists(jpg):
                os.remove(p)
                p = jpg
            outs.append(p)
            labels.append(f"{frame['scene']}  t = {frame['t']:.1f} s  {view}  ·  {frame['pose']}  ·  gaps red-ref {g['red_ref']:.2f}  blue-ref {g['blue_ref']:.2f}  red-blue {g['red_blue']:.2f}  (trunks: {g.get('core_red_ref', 0):.2f} / {g.get('core_blue_ref', 0):.2f})")
            print("rendered", p, flush=True)
    if outs:
        render.sheet(outs, os.path.join(out_dir, "postfight_scene.jpg"), cols=2, labels=labels,
                     title="post-fight scene: PostFight.Layout from the rigs' frames (top / hard camera, before and after the hand goes up)")
        print("rendered", os.path.join(out_dir, "postfight_scene.jpg"), flush=True)


if __name__ == "__main__":
    main()
