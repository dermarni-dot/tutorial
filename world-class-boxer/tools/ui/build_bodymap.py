#!/usr/bin/env python3
"""Pre-renders the Body tab's muscle map (src/client/modules/BodyMap.lua) as one image sheet, so the screen is
composed from plain ImageLabels instead of an EditableImage painted at run time:

  * the silhouette of each view (front, back): the body as a soft union of its pieces, anti-aliased, a rim
    light along the outline, white on transparent (tinted ImageColor3 = the skin colour)
  * one mask per muscle region per view: the belly's coverage with its volume shading, white on transparent,
    cropped to its box (tinted per development level, ImageTransparency for intensity)

The geometry is BodyMap.lua's (BODY / FRONT / BACK, in view fractions) ported here; the distance fields are
the same ones BodyMap's EditableImage painter computes. Writes tools/ui/out/bodymap.png (1024 x 1024) and
src/shared/BodyMapData.lua (the cells: sheet rect + the view box of every mask; id 0 until published).

    python3 tools/ui/build_bodymap.py               # the sheet + the manifest (id kept from the cache)
    python3 tools/ui/publish_icons.py --bodymap     # upload it (Open Cloud) and write the id into the manifest
"""
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")
SHEET = os.path.join(OUT, "bodymap.png")
MANIFEST = os.path.join(ROOT, "src", "shared", "BodyMapData.lua")
CACHE = os.path.join(HERE, "uploaded.json")

VIEW_W, VIEW_H = 300, 340  # px of one view on the sheet (the figure is drawn at most ~330 x 374 design px)
SHEET_SIZE = 1024

# silhouette pieces: x, y, w, h, rot (view fractions), tag
BODY = [
    (0.5, 0.075, 0.2, 0.1, 0, "head"), (0.5, 0.145, 0.13, 0.05, 0, None),
    (0.5, 0.235, 0.56, 0.15, 0, None), (0.5, 0.35, 0.4, 0.12, 0, None), (0.5, 0.455, 0.42, 0.1, 0, None),
    (0.235, 0.27, 0.11, 0.17, 4, None), (0.765, 0.27, 0.11, 0.17, -4, None),
    (0.2, 0.405, 0.09, 0.14, 6, None), (0.8, 0.405, 0.09, 0.14, -6, None),
    (0.185, 0.5, 0.08, 0.06, 6, "hand"), (0.815, 0.5, 0.08, 0.06, -6, "hand"),
    (0.41, 0.61, 0.17, 0.24, 2, None), (0.59, 0.61, 0.17, 0.24, -2, None),
    (0.405, 0.825, 0.12, 0.2, 0, None), (0.595, 0.825, 0.12, 0.2, 0, None),
    (0.4, 0.95, 0.12, 0.04, 0, "foot"), (0.6, 0.95, 0.12, 0.04, 0, "foot"),
]
FRONT = [
    ("neckSCM", 0.46, 0.15, 0.04, 0.045, 18), ("neckSCM", 0.54, 0.15, 0.04, 0.045, -18),
    ("traps", 0.385, 0.172, 0.13, 0.03, -16), ("traps", 0.615, 0.172, 0.13, 0.03, 16),
    ("frontDelt", 0.285, 0.205, 0.1, 0.075, 0), ("frontDelt", 0.715, 0.205, 0.1, 0.075, 0),
    ("sideDelt", 0.215, 0.215, 0.065, 0.08, 6), ("sideDelt", 0.785, 0.215, 0.065, 0.08, -6),
    ("upperChest", 0.42, 0.203, 0.15, 0.04, 0), ("upperChest", 0.58, 0.203, 0.15, 0.04, 0),
    ("pecs", 0.42, 0.248, 0.16, 0.062, 0), ("pecs", 0.58, 0.248, 0.16, 0.062, 0),
    ("serratus", 0.34, 0.3, 0.045, 0.06, 0), ("serratus", 0.66, 0.3, 0.045, 0.06, 0),
    ("biceps", 0.232, 0.29, 0.08, 0.1, 4), ("biceps", 0.768, 0.29, 0.08, 0.1, -4),
    ("forearms", 0.198, 0.405, 0.072, 0.12, 6), ("forearms", 0.802, 0.405, 0.072, 0.12, -6),
    ("abs", 0.465, 0.298, 0.06, 0.03, 0), ("abs", 0.535, 0.298, 0.06, 0.03, 0),
    ("abs", 0.465, 0.334, 0.06, 0.03, 0), ("abs", 0.535, 0.334, 0.06, 0.03, 0),
    ("abs", 0.465, 0.37, 0.06, 0.03, 0), ("abs", 0.535, 0.37, 0.06, 0.03, 0),
    ("obliques", 0.39, 0.36, 0.05, 0.1, 6), ("obliques", 0.61, 0.36, 0.05, 0.1, -6),
    ("lowerAbs", 0.5, 0.42, 0.11, 0.05, 0),
    ("quads", 0.41, 0.6, 0.14, 0.2, 2), ("quads", 0.59, 0.6, 0.14, 0.2, -2),
    ("calves", 0.395, 0.82, 0.07, 0.13, 0), ("calves", 0.605, 0.82, 0.07, 0.13, 0),
]
BACK = [
    ("traps", 0.5, 0.18, 0.3, 0.06, 0), ("traps", 0.5, 0.235, 0.1, 0.07, 0),
    ("rearDelt", 0.25, 0.208, 0.1, 0.07, 0), ("rearDelt", 0.75, 0.208, 0.1, 0.07, 0),
    ("upperBack", 0.4, 0.24, 0.12, 0.045, -10), ("upperBack", 0.6, 0.24, 0.12, 0.045, 10),
    ("lats", 0.375, 0.305, 0.13, 0.15, 10), ("lats", 0.625, 0.305, 0.13, 0.15, -10),
    ("lowerBack", 0.465, 0.4, 0.05, 0.1, 0), ("lowerBack", 0.535, 0.4, 0.05, 0.1, 0),
    ("triceps", 0.232, 0.29, 0.08, 0.1, 4), ("triceps", 0.768, 0.29, 0.08, 0.1, -4),
    ("forearms", 0.198, 0.405, 0.072, 0.12, 6), ("forearms", 0.802, 0.405, 0.072, 0.12, -6),
    ("glutes", 0.43, 0.5, 0.14, 0.085, 0), ("glutes", 0.57, 0.5, 0.14, 0.085, 0),
    ("hamstrings", 0.41, 0.625, 0.13, 0.17, 2), ("hamstrings", 0.59, 0.625, 0.13, 0.17, -2),
    ("calves", 0.408, 0.815, 0.1, 0.14, 0), ("calves", 0.592, 0.815, 0.1, 0.14, 0),
]


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def grid(W, H):
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    return xs + 0.5, ys + 0.5


def silhouette(W, H):
    """body coverage (0..1) and rim (0..1) of one view"""
    xs, ys = grid(W, H)
    dist = np.full((H, W), 1e6, dtype=np.float32)
    k = 0.045 * W
    for (x, y, w, h, rot, _tag) in BODY:
        cx, cy = x * W, y * H
        hw, hh = w * W / 2, h * H / 2
        r = min(hw, hh)
        a = np.radians(rot)
        cr, sr = np.cos(a), np.sin(a)
        dx, dy = xs - cx, ys - cy
        lx, ly = np.abs(dx * cr + dy * sr), np.abs(-dx * sr + dy * cr)
        qx, qy = lx - hw + r, ly - hh + r
        d = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - r
        dist = smin(dist, d, k)
    body = np.clip(0.5 - dist, 0, 1)
    rim = np.where((dist < 0) & (dist > -2.5), 1 - (-dist / 2.5), 0)
    return body, rim


def region_mask(W, H, spec):
    """coverage (0..1) and shade (0..1) of one muscle belly, plus its pixel box"""
    _id, x, y, w, h, rot = spec
    xs, ys = grid(W, H)
    cx, cy = x * W, y * H
    a, b = max(1.0, w * W / 2), max(1.0, h * H / 2)
    ang = np.radians(rot)
    cr, sr = np.cos(ang), np.sin(ang)
    minor = min(a, b)
    dx, dy = xs - cx, ys - cy
    lx, ly = dx * cr + dy * sr, -dx * sr + dy * cr
    px, py = lx / a, ly / b
    k0 = np.sqrt(px * px + py * py)
    k1 = np.sqrt((lx / (a * a)) ** 2 + (ly / (b * b)) ** 2)
    d = np.where(k1 > 1e-6, k0 * (k0 - 1) / np.maximum(k1, 1e-6), -minor)
    cov = np.clip(0.5 - d, 0, 1)
    depth = np.clip(-d / (0.55 * minor), 0, 1)
    light = 0.82 - 0.18 * np.clip(py, -1, 1)
    shade = np.clip((0.5 + 0.5 * depth) * light, 0, 1)
    ys_, xs_ = np.nonzero(cov > 0.002)
    if len(xs_) == 0:
        return None
    x0, x1, y0, y1 = int(xs_.min()), int(xs_.max()) + 1, int(ys_.min()), int(ys_.max()) + 1
    return cov[y0:y1, x0:x1], shade[y0:y1, x0:x1], (x0, y0, x1 - x0, y1 - y0)


def to_rgba(value, alpha):
    """white glyph: rgb = value (the shading, 0..1), alpha = coverage"""
    h, w = alpha.shape
    im = np.zeros((h, w, 4), dtype=np.uint8)
    v = np.clip(value * 255 + 0.5, 0, 255).astype(np.uint8)
    im[..., 0] = v
    im[..., 1] = v
    im[..., 2] = v
    im[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(im, "RGBA")


class Shelf:
    """a simple shelf packer onto the sheet"""

    def __init__(self, size, pad=2):
        self.size, self.pad = size, pad
        self.x, self.y, self.row_h = pad, pad, 0

    def put(self, w, h):
        if self.x + w + self.pad > self.size:
            self.x = self.pad
            self.y += self.row_h + self.pad
            self.row_h = 0
        if self.y + h + self.pad > self.size:
            raise RuntimeError("the body map sheet is full")
        x, y = self.x, self.y
        self.x += w + self.pad
        self.row_h = max(self.row_h, h)
        return x, y


def build():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (SHEET_SIZE, SHEET_SIZE), (0, 0, 0, 0))
    pack = Shelf(SHEET_SIZE)
    cells = {"views": {}, "masks": {"front": [], "back": []}}
    W, H = VIEW_W, VIEW_H
    body, rim = silhouette(W, H)
    # the skin: a touch lighter at the top, the rim light along the outline (as BodyMap's painter)
    ys = np.mgrid[0:H, 0:W][0].astype(np.float32)
    top = 1.08 - 0.16 * (ys / H)
    lift = np.clip((top + rim * 0.35) / 1.43, 0, 1)
    sil = to_rgba(lift, body)
    for view in ("front", "back"):
        x, y = pack.put(W, H)
        sheet.alpha_composite(sil, (x, y))
        cells["views"][view] = {"x": x, "y": y, "w": W, "h": H}
    for view, specs in (("front", FRONT), ("back", BACK)):
        for spec in specs:
            r = region_mask(W, H, spec)
            if r is None:
                continue
            cov, shade, box = r
            im = to_rgba(shade, cov)
            x, y = pack.put(im.size[0], im.size[1])
            sheet.alpha_composite(im, (x, y))
            cells["masks"][view].append({"id": spec[0], "x": x, "y": y, "w": im.size[0], "h": im.size[1],
                                          "bx": box[0] / W, "by": box[1] / H, "bw": box[2] / W, "bh": box[3] / H})
    sheet.save(SHEET)
    return cells


def cached_id():
    """the sheet's asset id from the upload cache (publish_icons.py --bodymap), 0 when not uploaded"""
    if not os.path.exists(CACHE):
        return 0
    import hashlib
    h = hashlib.sha256(open(SHEET, "rb").read()).hexdigest()
    with open(CACHE) as fh:
        e = json.load(fh).get(h)
    return int(e["id"]) if e and e.get("id") else 0


def write_manifest(cells, asset_id):
    L = []
    L.append("-- BodyMapData: the Body tab's muscle map as one uploaded image sheet (tools/ui/out/bodymap.png). GENERATED")
    L.append("-- by tools/ui/build_bodymap.py - do not edit by hand. views[view] = the silhouette's rect on the sheet; masks[view]")
    L.append("-- = one entry per muscle belly: its rect on the sheet and its box in the view (fractions bx, by, bw, bh). The")
    L.append("-- glyphs are white (shaded) on transparent: tint with ImageColor3. id 0 = not uploaded: BodyMap draws frames.")
    L.append("local BodyMapData = {}")
    L.append(f"BodyMapData.id = {asset_id}")
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
            L.append(f"\t\t{{ id = \"{m['id']}\", x = {m['x']}, y = {m['y']}, w = {m['w']}, h = {m['h']}, bx = {m['bx']:.4f}, by = {m['by']:.4f}, bw = {m['bw']:.4f}, bh = {m['bh']:.4f} }},")
        L.append("\t},")
    L.append("}")
    L.append("return BodyMapData")
    with open(MANIFEST, "w") as fh:
        fh.write("\n".join(L) + "\n")


if __name__ == "__main__":
    cells = build()
    aid = cached_id()
    write_manifest(cells, aid)
    n = sum(len(v) for v in cells["masks"].values())
    print(f"{SHEET}: 2 views, {n} masks; manifest {MANIFEST} (id {aid})")
