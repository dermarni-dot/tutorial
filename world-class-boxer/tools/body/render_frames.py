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

VIEWS = {"front": (0, 3, 1.0), "back": (180, 3, 1.0), "side": (90, 2, 1.0), "34": (-38, 4, 1.0)}
ORDER = ["Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build"]


def lineup(scene_dir, out_dir, clips, tier, view, samples, tag):
    clips = sorted(clips, key=lambda c: ORDER.index(c["frame"]) if c["frame"] in ORDER else 99)
    n = len(clips)
    gap = 3.9
    width = (n - 1) * gap + 3.4
    H = 7.4
    res_y = 820
    res_x = int(res_y * width / H)
    sc = v8.V8Scene(res=(min(res_x, 3600), res_y), samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
    labels = []
    for i, c in enumerate(clips):
        data = json.load(open(os.path.join(scene_dir, c["file"])))
        fr = data["frames"][0]
        d = {"meshes": fr["meshes"], "head": fr["head"], "parts": fr.get("parts", []), "hair": []}
        root = fr.get("root") or [0, 0, 0]
        k = i - (n - 1) / 2
        # the figures stand along X; a yawed view turns the whole row, so each figure is drawn at its own spot in the
        # row and the camera orbits the row's centre
        off = (-k * gap - root[0], 0, -root[2])
        v8.add_boxer(sc, scene_dir, d, offset=off)
        labels.append("%s  T%d" % (c["frame"], tier))
    cam = sc.cam
    cam.data.type = "ORTHO"
    yaw, pitch, _ = VIEWS[view]
    if view in ("front", "back"):
        cam.data.ortho_scale = max(width, H * res_x / res_y)
    else:
        cam.data.ortho_scale = max(width, H * res_x / res_y)
    focus = (0, H / 2 - 0.3, 0)
    sc.rig(focus, 6.0)
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
    dr.text((12, 9), "Body frames in the game (Builder.Cosmetics: tier bodies, trunks, gloves, boots): tier %d, %s view" % (tier, view),
            fill=(235, 235, 235), font=tfont)
    if view in ("front", "back", "34"):
        order = labels if view != "back" else labels[::-1]
        for i, t in enumerate(order):
            tw = dr.textlength(t, font=font)
            dr.text(((i + 0.5) * W / n - tw / 2, Hh + 44), t, fill=(215, 215, 215), font=font)
    else:
        dr.text((12, Hh + 44), "left to right (nearest first): " + ", ".join(labels[::-1]), fill=(215, 215, 215), font=font)
    final = os.path.join(out_dir, "%s_t%d_%s.jpg" % (tag, tier, view))
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
