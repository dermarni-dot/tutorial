"""Before / after preview renders of the hair, with the game's own head.

    /opt/bpyenv/bin/python previews.py before  SCENE_DIR OUT_DIR [ids...]
    /opt/bpyenv/bin/python previews.py after   SCENE_DIR OUT_DIR [ids...]
    /opt/bpyenv/bin/python previews.py compare BEFORE_DIR AFTER_DIR OUT_DIR [ids...]

SCENE_DIR holds one JSON per look, written by the lune host (tools/sim): `before` scenes come
from tools/sim/export_ref.luau (the generated hair), `after` scenes from tools/sim/after_scene.luau
(the asset hair as the game's HairAssets module places and tints it). Both are in real Head space:
{ head = { name = mesh }, pieces = { name = mesh } } where a mesh has p, n, uv, c, t (1-based),
an optional texture { file = *.rgba | *.png, w, h }, material, doubleSided, alpha.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

VIEWS = ["34", "side", "back", "front"]
RES = (440, 520)


def rgba_to_png(path, w, h):
    png = path[:-5] + ".png"
    if not os.path.exists(png) or os.path.getmtime(png) < os.path.getmtime(path):
        with open(path, "rb") as f:
            raw = f.read()
        Image.frombytes("RGBA", (w, h), raw).save(png)
    return png


def tex_path(scene_dir, tex):
    if not tex:
        return None
    f = os.path.join(scene_dir, tex["file"])
    if f.endswith(".rgba"):
        return rgba_to_png(f, tex["w"], tex["h"])
    return f


def build_scene(render, scene_dir, data):
    k = data.get("headSize", [0.927] * 3)[1]
    sc = render.Scene(res=RES, samples=56, focus=(0, 0.06 * k / 0.77, 0), dist=3.3 * k / 1.2 * 1.2)
    for name, md in data["head"].items():
        tex = tex_path(scene_dir, md.get("texture"))
        mat = "skin" if name in ("Head",) or name.startswith("Ear") else "plastic"
        md = dict(md, base=1)
        if tex:  # textured pieces carry their colour in the texture, not the vertex colours
            md["c"] = None
        sc.add_mesh(md, texture=tex, material=mat, alpha=False, name="head_" + name)
    for name, md in data["pieces"].items():
        tex = tex_path(scene_dir, md.get("texture"))
        md = dict(md, base=1)
        alpha = bool(md.get("alpha", tex is not None))
        if tex and not md.get("keepVertexColors"):
            md["c"] = None
        sc.add_mesh(md, texture=tex, material="hair", alpha=alpha, name=name)
    return sc


def render_dir(mode, scene_dir, out_dir, ids):
    import render
    os.makedirs(out_dir, exist_ok=True)
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    looks = [l for l in idx["looks"] if not ids or l["id"] in ids]
    for l in looks:
        data = json.load(open(os.path.join(scene_dir, l["file"])))
        sc = build_scene(render, scene_dir, data)
        paths = []
        for v in VIEWS:
            p = os.path.join(out_dir, f"{l['id']}_{v}.png")
            sc.render(p, v)
            paths.append(p)
        render.sheet(paths, os.path.join(out_dir, f"{l['id']}.jpg"), cols=len(VIEWS), labels=VIEWS,
                     title=f"{l['id']}  {l.get('style', '')} / {l.get('type', '')}  [{mode}]")
        print("rendered", l["id"])


def compare(before_dir, after_dir, out_dir, ids):
    """One row per look: BEFORE views then AFTER views, red / green tags."""
    from PIL import ImageDraw, ImageFont
    os.makedirs(out_dir, exist_ok=True)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
    names = sorted(f[:-4] for f in os.listdir(after_dir) if f.endswith(".jpg"))
    for name in names:
        if ids and name not in ids:
            continue
        b = os.path.join(before_dir, name + ".jpg")
        a = os.path.join(after_dir, name + ".jpg")
        if not os.path.exists(b):
            continue
        ib, ia = Image.open(b).convert("RGB"), Image.open(a).convert("RGB")
        W = Image.new("RGB", (max(ib.width, ia.width), ib.height + ia.height), (20, 20, 22))
        W.paste(ib, (0, 0))
        W.paste(ia, (0, ib.height))
        d = ImageDraw.Draw(W)
        for y, txt, col in ((ib.height - 34, "BEFORE", (200, 50, 50)), (W.height - 34, "AFTER", (40, 160, 70))):
            d.rectangle([8, y, 108, y + 26], fill=col)
            d.text((16, y + 3), txt, fill=(255, 255, 255), font=font)
        W.save(os.path.join(out_dir, f"hair_{name}.jpg"), quality=88)
        print("compared", name)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "compare":
        compare(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    else:
        render_dir(mode, sys.argv[2], sys.argv[3], sys.argv[4:])
