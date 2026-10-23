"""Cycles renders of the venue CROWD scenes dumped by tools/sim/crowd_scene.luau (previews/final/v10/crowd).

    /opt/bpyenv/bin/python tools/sim/crowd_render.py SCENE.json OUT_DIR [--only view,view] [--samples N] [--res 1280x720]

world_render.py does the drawing (parts, SurfaceGuis, decals, lights); this script adds what the crowd needs:
the drawn faces (the fans' head decals and the printed rows' ImageLabels come from tools/body/uploaded.json),
rotated GUI frames (the printed fans' arms) and RichText glyph rows (the upper bowl), and views framed on each
scene root's ring centre (scene.cameras[root]).
"""
import json
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import world_render as W  # noqa: E402

ROOT = W.ROOT

# the body / face uploads (the fans' faces)
_p = os.path.join(ROOT, "tools/body/uploaded.json")
if os.path.exists(_p):
    for e in json.load(open(_p)).values():
        if e.get("id") and e.get("file"):
            W.ASSETS[str(e["id"])] = os.path.join(ROOT, "tools/body", e["file"])

_orig_draw_gui = W.draw_gui
RT_RE = re.compile(r'<font\s+([^>]*)>(.*?)</font>', re.S)


def rich_segments(txt):
    """RichText -> [(text, color or None, transparent)]"""
    out = []
    pos = 0
    for m in RT_RE.finditer(txt):
        if m.start() > pos:
            out.append((txt[pos:m.start()], None, False))
        attrs, inner = m.group(1), m.group(2)
        col = None
        mc = re.search(r'color="#([0-9a-fA-F]{6})"', attrs)
        if mc:
            h = mc.group(1)
            col = (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255)
        tr = re.search(r'transparency="([\d.]+)"', attrs)
        out.append((inner, col, bool(tr and float(tr.group(1)) >= 0.99)))
        pos = m.end()
    if pos < len(txt):
        out.append((txt[pos:], None, False))
    return out


def draw_gui(g, W_, Hh):
    plain = [it for it in g["items"] if not it.get("rot") and not it.get("rt")]
    img = _orig_draw_gui({"items": plain}, W_, Hh)
    d = ImageDraw.Draw(img)
    for it in g["items"]:
        x0, y0 = it["x"] * W_, it["y"] * Hh
        w, h = it["w"] * W_, it["h"] * Hh
        if w <= 0 or h <= 0:
            continue
        if it.get("rot"):
            # a rotated frame: Roblox rotates clockwise about the centre
            cx, cy = x0 + w / 2, y0 + h / 2
            th = np.radians(it["rot"])
            c, s = np.cos(th), np.sin(th)
            pts = []
            for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
                pts.append((cx + dx * c - dy * s, cy + dx * s + dy * c))
            bt = it.get("bt", 0)
            if bt < 0.99:
                d.polygon(pts, fill=W.c255(it["bg"], int((1 - bt) * 255)))
        elif it.get("rt") and it.get("text"):
            segs = rich_segments(it["text"])
            n = sum(len(t) for t, _, _ in segs)
            if n == 0:
                continue
            fpath, fvar = W.face_for(it)
            px = min(h * 0.9, w / n * 1.9)
            f = W.font(fpath, max(4, px), fvar)
            gw = w / n
            x = x0
            ty = y0 + (h - px) / 2 - px * 0.15
            for t, col, transparent in segs:
                for ch in t:
                    if not transparent:
                        d.text((x + gw / 2 - px * 0.35, ty), ch, font=f, fill=W.c255(col or it["tc"], 255))
                    x += gw
    return img


W.draw_gui = draw_gui


def rel(scene, root, eye, target, **kw):
    cam = scene["cameras"].get(root)
    if not cam:
        return None
    c = np.array(cam[:3])
    v = {"roots": [root], "eye": tuple(c + np.array(eye)), "target": tuple(c + np.array(target)), "fov": 48, "mode": "night", "exposure": 1.2}
    v.update(kw)
    return v


def views_for(scene):
    V = {}
    # ringside: from the apron over the judges, the front rows, the VIP boxes behind (Stadium)
    V["01_stadium_ringside_max"] = rel(scene, "Stadium_max", (-6, 9, -10), (24, 3, 34), fov=52)
    V["02_stadium_wide_max"] = rel(scene, "Stadium_max", (-110, 70, 120), (0, 22, 0), fov=55)
    V["03_stadium_wide_low"] = rel(scene, "Stadium_low", (-110, 70, 120), (0, 22, 0), fov=55)
    V["04_stadium_react"] = rel(scene, "Stadium_max_react", (-6, 9, -10), (24, 3, 34), fov=52)
    V["05_arena_ringside_max"] = rel(scene, "Arena_max", (-44, 24, 50), (0, 6, 0), fov=48)
    V["06_arena_stands_max"] = rel(scene, "Arena_max", (8, 7, -6), (-30, 8, 30), fov=55)
    V["07_arena_stands_low"] = rel(scene, "Arena_low", (8, 7, -6), (-30, 8, 30), fov=55)
    V["08_club_ringside_low"] = rel(scene, "ClubArena_low", (-32, 16, 36), (0, 5, 0), fov=48)
    V["09_club_stands_max"] = rel(scene, "ClubArena_max", (6, 6, -4), (-26, 6, 26), fov=55)
    V["10_community_max"] = rel(scene, "CommunityCenter_max", (-26, 14, 30), (0, 4, 0), fov=48)
    V["11_arena_react_close"] = rel(scene, "Arena_max_react", (10, 6, 4), (-12, 6, 36), fov=50)
    V["12_arena_vip_max"] = rel(scene, "Arena_max", (-14, 8, 10), (-42, 10, 18), fov=50)
    return {k: v for k, v in V.items() if v}


def main():
    argv = sys.argv[1:]
    scene_path, out_dir = argv[0], argv[1]
    only = None
    samples, res = 48, (1280, 720)
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            only = argv[i + 1].split(",")
            i += 1
        elif a == "--samples":
            samples = int(argv[i + 1])
            i += 1
        elif a == "--res":
            res = tuple(int(x) for x in argv[i + 1].split("x"))
            i += 1
        i += 1
    scene = json.load(open(scene_path))
    os.makedirs(out_dir, exist_ok=True)
    tmpdir = os.path.join(os.path.dirname(os.path.abspath(scene_path)), "gui_png")
    os.makedirs(tmpdir, exist_ok=True)
    for name, view in views_for(scene).items():
        if only and name not in only:
            continue
        W.render_view(scene, view, os.path.join(out_dir, name + ".jpg"), samples, res, tmpdir)


if __name__ == "__main__":
    main()
