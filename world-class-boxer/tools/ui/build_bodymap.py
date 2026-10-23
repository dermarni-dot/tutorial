#!/usr/bin/env python3
"""Pre-renders the Body screen's muscle map (src/client/modules/BodyMap.lua) as one image sheet, so the figure is
composed from plain ImageLabels (no EditableImage painted at run time, nothing that can fail into Studio's
magenta / cyan checkerboard):

  * the silhouette of each view (front, back): head, neck, torso, arms and legs as smooth outlines, one soft
    union, a faint top light; white on transparent (tinted ImageColor3 = the skin tone of the map)
  * one mask per muscle group and side per view: an anatomical outline (closed Catmull-Rom splines through
    hand-placed points, mirrored left / right) with a 1 px gap to its neighbours and a baked dome shade, white
    on transparent, cropped to its box (tinted per development level in game)

Every view is drawn on the same VIEW_W x VIEW_H canvas, so the game places a mask at its box fraction of the
view and the figure keeps its aspect (BodyMap fits the view into whatever space it gets).

    python3 tools/ui/build_bodymap.py               # the sheet + src/shared/BodyMapData.lua
    python3 tools/ui/publish_icons.py --bodymap     # upload it (Open Cloud); the id goes into IconData.bodyMap
    python3 tools/ui/build_bodymap.py --preview OUT  # also a tinted preview of both views
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")
SHEET = os.path.join(OUT, "bodymap.png")
MANIFEST = os.path.join(ROOT, "src", "shared", "BodyMapData.lua")

# design canvas of one view (units), drawn at SCALE px per unit; the figure's centre line is x = 0
DW, DH = 200, 440
SCALE = 1.16
VIEW_W, VIEW_H = int(round(DW * SCALE)), int(round(DH * SCALE))  # 232 x 510
SHEET_SIZE = 1024
SS = 4  # supersampling
GAP = 1.1  # px between two muscles (the silhouette shows through)

# ---------------------------------------------------------------- the silhouette (right half; x >= 0 is mirrored)
HEAD = (0, 31, 16.5, 22)  # centre x, y, rx, ry
NECK = [(-11, 48), (11, 48), (13.5, 70), (-13.5, 70)]
TORSO_R = [(0, 64), (13, 64), (27, 72), (44, 79), (51, 86), (50, 102), (44, 120), (43, 140), (39, 168), (34, 198),
           (35, 220), (40, 240), (42, 256), (2, 266), (0, 266)]
ARM_R = [(46, 81), (57, 85), (63, 99), (64, 120), (62, 148), (60, 176), (62, 194), (62, 218), (58, 242), (49, 244),
         (46, 222), (43, 198), (43, 176), (41, 150), (42, 124), (44, 100)]
HAND_R = (54.5, 256, 7.5, 13.5)
LEG_R = [(2, 262), (40, 242), (44, 262), (43, 296), (35, 326), (31, 346), (31, 370), (27, 398), (21, 418), (11, 418),
         (10, 398), (8, 372), (8, 348), (10, 330), (5, 300), (3, 280)]
FOOT_R = [(9, 413), (23, 413), (29, 426), (27, 431), (7, 431)]

# ---------------------------------------------------------------- the muscles: (id, [points of the right side])
FRONT = [
    ("neckSCM", [(10.5, 52), (13, 55), (6.5, 73), (2.5, 75), (3, 70)]),
    ("traps", [(13, 63), (25, 70), (43, 78.5), (40, 83), (24, 78), (13.5, 72)]),
    ("upperChest", [(3, 85), (22, 82), (37, 85), (41, 91), (33, 97), (16, 99), (3, 99)]),
    ("pecs", [(3, 101), (20, 100), (36, 98), (43, 103), (44, 114), (39, 126), (28, 133), (14, 135), (3, 131)]),
    ("frontDelt", [(40, 83), (48, 84), (53, 92), (53, 106), (49, 120), (45, 124), (44, 108), (43, 95)]),
    ("sideDelt", [(50, 85), (58, 89), (62, 101), (61, 116), (56, 126), (54, 112), (55, 97)]),
    ("serratus", [(38, 132), (43, 127), (44.5, 140), (41, 152), (36, 148)]),
    ("biceps", [(46, 127), (55, 129), (59, 146), (57, 168), (52, 180), (46, 176), (43.5, 154)]),
    ("forearms", [(45, 190), (56, 187), (61, 204), (59, 226), (55, 241), (49, 240), (46, 222), (43.5, 204)]),
    ("abs", [(3, 138), (15, 137), (16, 154), (3, 156)]),
    ("abs", [(3, 160), (16, 159), (16.5, 178), (3, 180)]),
    ("abs", [(3, 184), (16.5, 183), (16, 202), (3, 204)]),
    ("lowerAbs", [(3, 208), (16, 207), (15, 226), (8, 242), (3, 246)]),
    ("obliques", [(21, 146), (35, 145), (37, 172), (34, 200), (26, 222), (19, 214), (19, 182)]),
    ("quads", [(16, 260), (31, 248), (41, 258), (42, 288), (36, 318), (27, 332), (17, 330), (11, 312), (11, 284)]),
    ("calves", [(14, 352), (24, 347), (29, 366), (26, 392), (20, 400), (14, 386), (12, 366)]),
]
BACK = [
    ("traps", [(0, 58), (11, 62), (27, 71), (44, 80), (33, 90), (18, 106), (9, 132), (3, 150), (0, 152)]),
    ("rearDelt", [(43, 85), (55, 88), (62, 101), (60, 118), (54, 124), (48, 112), (42, 97)]),
    ("upperBack", [(19, 106), (32, 93), (41, 101), (42, 115), (31, 122), (19, 120)]),
    ("lats", [(14, 126), (31, 125), (43, 124), (42, 146), (37, 172), (28, 198), (16, 212), (12, 186), (11, 150)]),
    ("lowerBack", [(2.5, 158), (8.5, 158), (13, 196), (14, 230), (4, 234), (2.5, 200)]),
    ("triceps", [(46, 126), (56, 125), (60, 144), (58, 170), (52, 182), (46, 172), (43.5, 148)]),
    ("forearms", [(45, 190), (56, 187), (61, 204), (59, 226), (55, 241), (49, 240), (46, 222), (43.5, 204)]),
    ("glutes", [(3, 238), (24, 232), (39, 241), (42, 262), (33, 282), (15, 286), (3, 278)]),
    ("hamstrings", [(9, 292), (33, 287), (41, 298), (37, 324), (28, 336), (15, 333), (9, 314)]),
    ("calves", [(13, 346), (26, 342), (31, 360), (29, 384), (21, 400), (14, 390), (11, 366)]),
]


def catmull(points, steps=10):
    """a closed Catmull-Rom spline through the points"""
    n = len(points)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = points[(i - 1) % n], points[i], points[(i + 1) % n], points[(i + 2) % n]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    return out


def to_px(pts, mirror=False):
    k = SCALE * SS
    cx = DW / 2
    return [((cx + (-x if mirror else x)) * k, y * k) for (x, y) in pts]


def mirror_full(right):
    """a full outline from its right half (points from the top of the centre line down to the bottom of it)"""
    left = [(-x, y) for (x, y) in reversed(right)]
    return right + left


def canvas():
    return Image.new("L", (VIEW_W * SS, VIEW_H * SS), 0)


def ellipse(d, e, mirror=False):
    x, y, rx, ry = e
    k = SCALE * SS
    cx = DW / 2 + (-x if mirror else x)
    d.ellipse(((cx - rx) * k, (y - ry) * k, (cx + rx) * k, (y + ry) * k), fill=255)


def down(img):
    return img.resize((VIEW_W, VIEW_H), Image.LANCZOS)


def silhouette():
    big = canvas()
    d = ImageDraw.Draw(big)
    ellipse(d, HEAD)
    d.polygon(to_px(NECK), fill=255)
    d.polygon(to_px(catmull(mirror_full(TORSO_R), 6)), fill=255)
    for m in (False, True):
        d.polygon(to_px(catmull(ARM_R, 6), m), fill=255)
        ellipse(d, HAND_R, m)
        d.polygon(to_px(catmull(LEG_R, 6), m), fill=255)
        d.polygon(to_px(FOOT_R, m), fill=255)
    # a soft union: blur then re-threshold rounds the joints (armpits, the neck, the crotch)
    big = big.filter(ImageFilter.GaussianBlur(2.2 * SS))
    a = np.asarray(big).astype(np.float32) / 255.0
    a = np.clip((a - 0.5) * 6 + 0.5, 0, 1)
    sil = Image.fromarray((a * 255).astype(np.uint8), "L")
    return down(sil)


def muscle(points, mirror):
    big = canvas()
    d = ImageDraw.Draw(big)
    d.polygon(to_px(catmull(points, 10), mirror), fill=255)
    # the gap: shrink by GAP px (a min filter at the supersampled size)
    shrink = int(round(GAP * SS)) * 2 + 1
    big = big.filter(ImageFilter.MinFilter(shrink if shrink % 2 else shrink + 1))
    cov = np.asarray(down(big)).astype(np.float32) / 255.0
    # a dome: the coverage blurred, brighter toward the middle of the belly, plus a top light
    dome = np.asarray(down(big).filter(ImageFilter.GaussianBlur(3.2))).astype(np.float32) / 255.0
    ys = np.mgrid[0:VIEW_H, 0:VIEW_W][0].astype(np.float32)
    ys_cov = ys[cov > 0.02]
    y0, y1 = (ys_cov.min(), ys_cov.max()) if ys_cov.size else (0, 1)
    top = 1.0 - 0.16 * np.clip((ys - y0) / max(1.0, y1 - y0), 0, 1)
    shade = np.clip((0.62 + 0.38 * dome) * top, 0, 1)
    return cov, shade


def rgba(value, alpha):
    h, w = alpha.shape
    im = np.zeros((h, w, 4), dtype=np.uint8)
    v = np.clip(value * 255 + 0.5, 0, 255).astype(np.uint8)
    im[..., 0] = v
    im[..., 1] = v
    im[..., 2] = v
    im[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(im, "RGBA")


class Shelf:
    """a shelf packer over a list of regions (x0, y0, x1, y1) of the sheet, filled in turn"""

    def __init__(self, regions, pad=2):
        self.regions, self.pad, self.r = regions, pad, 0
        self._start()

    def _start(self):
        x0, y0, _x1, _y1 = self.regions[self.r]
        self.x, self.y, self.row_h = x0, y0, 0

    def put(self, w, h):
        while True:
            x0, _y0, x1, y1 = self.regions[self.r]
            if self.x + w > x1:
                self.x = x0
                self.y += self.row_h + self.pad
                self.row_h = 0
            if self.y + h <= y1:
                break
            self.r += 1
            if self.r >= len(self.regions):
                raise RuntimeError("the body map sheet is full")
            self._start()
        x, y = self.x, self.y
        self.x += w + self.pad
        self.row_h = max(self.row_h, h)
        return x, y


def build():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (SHEET_SIZE, SHEET_SIZE), (0, 0, 0, 0))
    cells = {"views": {}, "masks": {"front": [], "back": []}}
    sil = silhouette()
    a = np.asarray(sil).astype(np.float32) / 255.0
    ys = np.mgrid[0:VIEW_H, 0:VIEW_W][0].astype(np.float32)
    light = np.clip(1.0 - 0.14 * ys / VIEW_H, 0, 1)
    sil_im = rgba(light, a)
    for i, view in enumerate(("front", "back")):
        x, y = 2 + i * (VIEW_W + 2), 2
        sheet.alpha_composite(sil_im, (x, y))
        cells["views"][view] = {"x": x, "y": y, "w": VIEW_W, "h": VIEW_H}
    right = 2 + 2 * (VIEW_W + 2)  # the masks fill the column right of the two views, then the band below them
    pack = Shelf([(right, 2, SHEET_SIZE - 2, VIEW_H + 2), (2, VIEW_H + 6, SHEET_SIZE - 2, SHEET_SIZE - 2)])
    for view, specs in (("front", FRONT), ("back", BACK)):
        for mid, pts in specs:
            for side, mirror in (("r", False), ("l", True)):
                cov, shade = muscle(pts, mirror)
                ys_, xs_ = np.nonzero(cov > 0.004)
                if len(xs_) == 0:
                    continue
                x0, x1, y0, y1 = int(xs_.min()), int(xs_.max()) + 1, int(ys_.min()), int(ys_.max()) + 1
                im = rgba(shade[y0:y1, x0:x1], cov[y0:y1, x0:x1])
                px, py = pack.put(im.size[0], im.size[1])
                sheet.alpha_composite(im, (px, py))
                cells["masks"][view].append({"id": mid, "side": side, "x": px, "y": py, "w": im.size[0], "h": im.size[1],
                                              "bx": x0 / VIEW_W, "by": y0 / VIEW_H, "bw": (x1 - x0) / VIEW_W, "bh": (y1 - y0) / VIEW_H})
    sheet.save(SHEET, optimize=True)
    return cells, sheet


def write_manifest(cells):
    L = []
    L.append("-- BodyMapData: the Body screen's muscle map as one image sheet (tools/ui/out/bodymap.png). GENERATED by")
    L.append("-- tools/ui/build_bodymap.py - do not edit by hand. The sheet's asset id is IconData.bodyMap (publish_icons.py")
    L.append("-- --bodymap). views[view] = the silhouette's rect on the sheet (every view is `view.w` x `view.h` px: keep that")
    L.append("-- aspect); masks[view] = one entry per muscle and side: its rect on the sheet and its box in the view (fractions")
    L.append("-- bx, by, bw, bh). White (shaded) on transparent: tint with ImageColor3.")
    L.append("local BodyMapData = {}")
    L.append(f"BodyMapData.size = Vector2.new({SHEET_SIZE}, {SHEET_SIZE})")
    L.append(f"BodyMapData.view = {{ w = {VIEW_W}, h = {VIEW_H} }}")
    L.append("BodyMapData.views = {")
    for view, c in cells["views"].items():
        L.append(f"\t{view} = {{ x = {c['x']}, y = {c['y']}, w = {c['w']}, h = {c['h']} }},")
    L.append("}")
    L.append("BodyMapData.masks = {")
    for view in ("front", "back"):
        L.append(f"\t{view} = {{")
        for m in cells["masks"][view]:
            L.append(f"\t\t{{ id = \"{m['id']}\", side = \"{m['side']}\", x = {m['x']}, y = {m['y']}, w = {m['w']}, h = {m['h']}, "
                     f"bx = {m['bx']:.4f}, by = {m['by']:.4f}, bw = {m['bw']:.4f}, bh = {m['bh']:.4f} }},")
        L.append("\t},")
    L.append("}")
    L.append("return BodyMapData")
    with open(MANIFEST, "w") as fh:
        fh.write("\n".join(L) + "\n")


def preview(cells, sheet, path):
    """both views composed as the game does (a development ramp across the muscles), on the panel colour"""
    W = VIEW_W * 2 + 24
    img = Image.new("RGBA", (W, VIEW_H + 16), (22, 23, 27, 255))
    ramp = [(70, 77, 96), (150, 60, 50), (220, 120, 50), (236, 190, 76)]
    for i, view in enumerate(("front", "back")):
        ox = 8 + i * (VIEW_W + 8)
        v = cells["views"][view]
        sil = sheet.crop((v["x"], v["y"], v["x"] + v["w"], v["y"] + v["h"]))
        arr = np.asarray(sil).astype(np.float32)
        for c, k in enumerate((46, 51, 64)):
            arr[..., c] *= k / 255.0 * 1.3
        img.alpha_composite(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA"), (ox, 8))
        for j, m in enumerate(cells["masks"][view]):
            col = ramp[j % len(ramp)]
            cell = sheet.crop((m["x"], m["y"], m["x"] + m["w"], m["y"] + m["h"]))
            arr = np.asarray(cell).astype(np.float32)
            for c in range(3):
                arr[..., c] *= col[c] / 255.0
            img.alpha_composite(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA"),
                                (ox + int(round(m["bx"] * VIEW_W)), 8 + int(round(m["by"] * VIEW_H))))
    img.convert("RGB").save(path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", help="write a tinted preview of both views here")
    a = ap.parse_args()
    cells, sheet = build()
    write_manifest(cells)
    if a.preview:
        preview(cells, sheet, a.preview)
    n = sum(len(v) for v in cells["masks"].values())
    print(f"{SHEET}: 2 views of {VIEW_W} x {VIEW_H}, {n} masks; manifest {MANIFEST}")
