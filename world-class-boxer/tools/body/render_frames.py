"""Cycles lineups of the body frames (previews/final/v10/bodies): the rest clips tools/body/frames_anim.luau records
(complete boxers built by the real Builder: tier bodies, classic head, mesh gear) side by side, one image per view, at
each tier. Geometry exactly as tools/sim/v9_render.py draws a rest clip (v8_render.add_boxer).

    /opt/bpyenv/bin/python tools/body/render_frames.py SCENE_DIR OUT_DIR [--samples N] [--views front,back,side,34]
                                                      [--tiers 1,5] [--tag bodies] [--frames "Lean,Power Build"]
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SIM = os.path.join(os.path.dirname(HERE), "sim")
sys.path.insert(0, SIM)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hair"))
import v8_render as v8  # noqa: E402
import render  # noqa: E402

VIEWS = {"front": (0, 3, 1.0), "back": (180, 3, 1.0), "side": (90, 2, 1.0), "34": (-38, 4, 1.0), "silhouette": (0, 0, 1.0)}
import bpy  # noqa: E402
ROT90 = np.array([[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]])  # a yaw of 90 deg about Y (the side fill)


def rot_cf(cf):
    """a v9 cf list [x, y, z, r00..r22] turned by ROT90 about the origin"""
    p = np.array(cf[:3])
    R = np.array(cf[3:]).reshape(3, 3)
    p2 = ROT90 @ p
    R2 = ROT90 @ R
    return [float(v) for v in p2] + [float(v) for v in R2.ravel()]
ORDER = ["Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build"]


def lineup(scene_dir, out_dir, clips, tier, view, samples, tag):
    clips = sorted(clips, key=lambda c: ORDER.index(c["frame"]) if c["frame"] in ORDER else 99)
    n = len(clips)
    gap = 3.9
    width = (n - 1) * gap + 4.6
    H = 7.4
    res_y = 820
    res_x = int(res_y * width / H)
    sil = view == "silhouette"
    sc = v8.V8Scene(res=(min(res_x, 3600), res_y), samples=8 if sil else samples, lens=50, bg=(1, 1, 1) if sil else (0.11, 0.115, 0.125))
    labels = []
    for i, c in enumerate(clips):
        data = json.load(open(os.path.join(scene_dir, c["file"])))
        fr = data["frames"][0]
        d = {"meshes": fr["meshes"], "head": fr["head"], "parts": fr.get("parts", []), "hair": []}
        root = fr.get("root") or [0, 0, 0]
        k = i - (n - 1) / 2
        # the row runs along X for the front / back / 3-4 views; the side view (the camera on +X) spreads it along Z,
        # the nearest figure (the last of the order) toward the viewer's right as v9_render's filmstrips do
        if view == "side":
            off = (-root[0], 0, -k * gap - root[2])
        else:
            off = (-k * gap - root[0], 0, -root[2])
        if sil:
            # front and side fills side by side per frame
            v8.add_boxer(sc, scene_dir, d, offset=(off[0] - 0.95, 0, off[2]))
            dd = dict(d)
            dd["meshes"] = [dict(m, p=(np.asarray(m["p"]).reshape(-1, 3) @ ROT90.T).ravel().tolist(),
                                 n=(np.asarray(m["n"]).reshape(-1, 3) @ ROT90.T).ravel().tolist()) for m in d["meshes"]]
            dd["head"] = dict(d["head"], cf=rot_cf(d["head"]["cf"]))
            dd["parts"] = [dict(g, cf=rot_cf(g["cf"])) for g in d["parts"]]
            v8.add_boxer(sc, scene_dir, dd, offset=(off[0] + 0.95, 0, off[2]))
        else:
            v8.add_boxer(sc, scene_dir, d, offset=off)
        labels.append("%s  T%d" % (c["frame"], tier))
    if sil:
        black = bpy.data.materials.new("black")
        black.use_nodes = True
        em = black.node_tree.nodes.new("ShaderNodeEmission")
        em.inputs[0].default_value = (0, 0, 0, 1)
        black.node_tree.links.new(em.outputs[0], black.node_tree.nodes["Material Output"].inputs[0])
        for ob in sc.sc.objects:
            if ob.type == "MESH":
                if ob.name.startswith("floor"):
                    ob.hide_render = True
                else:
                    ob.data.materials.clear()
                    ob.data.materials.append(black)
        sc.sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
        try:
            sc.sc.view_settings.view_transform = "Standard"
        except TypeError:
            pass
    cam = sc.cam
    cam.data.type = "ORTHO"
    yaw, pitch, _ = VIEWS[view]
    if view in ("front", "back"):
        cam.data.ortho_scale = max(width, H * res_x / res_y)
    else:
        cam.data.ortho_scale = max(width, H * res_x / res_y)
    focus = (0, H / 2 - 0.3, 0)
    sc.rig(focus, 6.0)
    if sil:
        p = os.path.join(out_dir, "_sil_t%d.png" % tier)
    else:
        p = os.path.join(out_dir, "_%s_t%d_%s.png" % (tag, tier, view))
    sc.render(p, view=(yaw, pitch, 1.0), dist=40, focus=focus)
    from PIL import Image, ImageDraw, ImageFont
    im = Image.open(p).convert("RGB")
    W, Hh = im.size
    out = Image.new("RGB", (W, Hh + 70), (26, 27, 30))
    out.paste(im, (0, 40))
    dr = ImageDraw.Draw(out)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    tfont = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 21)
    dr.text((12, 9), "Body frames in the game (Builder.Cosmetics: tier bodies, trunks, gloves, boots): tier %d, %s" % (tier,
            "silhouettes (front, side)" if sil else view + " view"), fill=(235, 235, 235), font=tfont)
    if view in ("front", "back", "34", "silhouette"):
        order = labels if view != "back" else labels[::-1]
        for i, t in enumerate(order):
            tw = dr.textlength(t, font=font)
            dr.text(((i + 0.5) * W / n - tw / 2, Hh + 44), t, fill=(215, 215, 215), font=font)
    else:
        dr.text((12, Hh + 44), "left to right (nearest first): " + ", ".join(labels[::-1]), fill=(215, 215, 215), font=font)
    final = os.path.join(out_dir, "silhouettes_t%d.png" % tier if sil else "%s_t%d_%s.jpg" % (tag, tier, view))
    out.save(final, quality=92)
    os.remove(p)
    print("rendered", final, flush=True)
    return final


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    scene_dir, out_dir = argv[0], argv[1]
    opts = {}
    i = 2
    while i < len(argv):
        opts[argv[i]] = argv[i + 1]
        i += 2
    os.makedirs(out_dir, exist_ok=True)
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    samples = int(opts.get("--samples", 24))
    views = opts.get("--views", "front,back,side,34").split(",")
    tiers = [int(x) for x in opts.get("--tiers", "1,5").split(",")]
    tag = opts.get("--tag", "bodies")
    only = set(opts["--frames"].split(",")) if "--frames" in opts else None
    for tier in tiers:
        clips = [c for c in idx["clips"] if c["clip"] == "rest" and c["tier"] == tier and (only is None or c["frame"] in only)]
        if not clips:
            continue
        for view in views:
            lineup(scene_dir, out_dir, clips, tier, view, samples, tag)


if __name__ == "__main__":
    main()
