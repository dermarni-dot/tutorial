"""Approximate screenshots of the game's 2D UI from guisim's layout dumps (tools/sim/test_ui_layout.luau --previews,
or any GS.WriteBoxes JSON): every object drawn with its real colour, transparency, corner radius, stroke, gradient,
text (Inter standing in for Gotham, Inter Display squeezed to Oswald's width) and image (the icon sheets / logo
from tools/ui/out, looked up by their asset ids). The 3D world behind the UI is a dark arena gradient.

    python3 tools/ui/render_mock.py tools/sim/out/ui/menu_desktop.json [...] --out previews/final/v9/ui2
    python3 tools/ui/render_mock.py --all tools/sim/out/ui --only menu,hub,creator --out DIR

Approximate: no blur, no 3D viewports (a placeholder silhouette), rich text drawn plain, UIScale-less fonts.
"""
import argparse
import glob
import json
import math
import os
import re

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")
FONTS = "/usr/share/fonts/opentype/inter"
SS = 2  # supersampling of each object's tile (smooth corners and text)

_font_cache = {}


def font(kind, px):
    px = max(6, int(round(px)))
    key = (kind, px)
    if key not in _font_cache:
        f = {"display": "InterDisplay-Black.otf", "displayMed": "InterDisplay-Bold.otf", "heavy": "Inter-Bold.otf",
             "body": "Inter-Medium.otf"}[kind]
        _font_cache[key] = ImageFont.truetype(os.path.join(FONTS, f), px)
    return _font_cache[key]


# asset id -> image file (the icon sheets and logo, from publish_icons.py's cache)
def load_assets():
    ids = {}
    cache = os.path.join(HERE, "uploaded.json")
    if os.path.exists(cache):
        with open(cache) as fh:
            for e in json.load(fh).values():
                ids[str(e["id"])] = os.path.join(ROOT, e["file"])
    return ids


ASSETS = load_assets()
_img_cache = {}


def asset(img):
    m = re.search(r"(\d+)", img or "")
    if not m:
        return None
    f = ASSETS.get(m.group(1))
    if not f or not os.path.exists(f):
        return None
    if f not in _img_cache:
        _img_cache[f] = Image.open(f).convert("RGBA")
    return _img_cache[f]


def gradient_field(w, h, rot):
    """the UIGradient parameter t (0..1) over a w x h box for a rotation in degrees (0 = left to right)."""
    a = math.radians(rot)
    dx, dy = math.cos(a), math.sin(a)
    ys, xs = np.mgrid[0:h, 0:w]
    u = (xs + 0.5) / max(w, 1) - 0.5
    v = (ys + 0.5) / max(h, 1) - 0.5
    t = u * dx + v * dy
    span = abs(dx) * 0.5 + abs(dy) * 0.5
    return np.clip((t + span) / (2 * span), 0, 1)


def interp(keys, t):
    xs = np.array([k[0] for k in keys], dtype=float)
    return xs, t


def apply_gradient(tile, g):
    w, h = tile.size
    arr = np.asarray(tile).astype(np.float32)
    t = gradient_field(w, h, g.get("rot", 0) or 0)
    if g.get("off"):
        t = np.clip(t - g["off"][0] * 0.5 - g["off"][1] * 0.5, 0, 1)
    if g.get("c"):
        ks = g["c"]
        xs = [k[0] for k in ks]
        for ch in range(3):
            ys = [k[1][ch] / 255.0 for k in ks]
            arr[..., ch] *= np.interp(t, xs, ys)
    if g.get("t"):
        ks = g["t"]
        xs = [k[0] for k in ks]
        ys = [1 - k[1] for k in ks]
        arr[..., 3] *= np.interp(t, xs, ys)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def strip_rich(s):
    return re.sub(r"<[^>]+>", "", s or "")


def wrap(draw, text, fnt, width, sx):
    lines = []
    for para in text.split("\n"):
        words = para.split(" ")
        cur = ""
        for w_ in words:
            trial = (cur + " " + w_).strip()
            if draw.textlength(trial, font=fnt) * sx <= width or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = w_
        lines.append(cur)
    return lines


def draw_text(tile, it, st, W, H):
    text = strip_rich(it.get("text") or "")
    if not text.strip():
        return
    size = (it.get("textSize") or 14) * SS
    cond = st.get("cond")
    kind = ("display" if (st.get("heavy") and size >= 22 * SS) else "displayMed") if cond else ("heavy" if st.get("heavy") else "body")
    sx = 0.78 if cond else 1.0
    tmp = Image.new("RGBA", (1, 1))
    d0 = ImageDraw.Draw(tmp)
    if st.get("scaled"):
        size = min(H * 0.86, size if size > 0 else H)
        while size > 8:
            fnt = font(kind, size)
            if d0.textlength(text, font=fnt) * sx <= W * 0.98:
                break
            size -= 1
    fnt = font(kind, size)
    lines = wrap(d0, text, fnt, W, sx) if it.get("wrapped") else text.split("\n")
    asc, desc = fnt.getmetrics()
    lh = (asc + desc) * (1.0 if cond else 1.05)
    total = lh * len(lines)
    ya = st.get("ya") or "Center"
    y0 = 0 if ya == "Top" else (H - total if ya == "Bottom" else (H - total) / 2)
    col = tuple(st.get("tc") or (255, 255, 255))
    alpha = int(255 * (1 - (st.get("tt") or 0)))
    align = it.get("align") or "Left"
    for i, ln in enumerate(lines):
        tw = d0.textlength(ln, font=fnt)
        lw, lh_i = max(1, int(tw + 4)), max(1, int(lh + 4))
        li = Image.new("RGBA", (lw, lh_i), (0, 0, 0, 0))
        dl = ImageDraw.Draw(li)
        sT = st.get("strokeT")
        if sT is not None and sT < 0.9:
            dl.text((2, 2), ln, font=fnt, fill=col + (alpha,), stroke_width=max(1, int(size / 18)), stroke_fill=(0, 0, 0, int(alpha * (1 - sT))))
        else:
            dl.text((2, 2), ln, font=fnt, fill=col + (alpha,))
        if sx != 1.0:
            li = li.resize((max(1, int(lw * sx)), lh_i), Image.LANCZOS)
        ww = li.size[0] - 4
        x = 0 if align == "Left" else (W - ww if align == "Right" else (W - ww) / 2)
        tile.alpha_composite(li, (int(x) - 2, int(y0 + i * lh) - 2 + int(lh * 0.04)))


def draw_image(tile, st, W, H):
    src = asset(st.get("img"))
    if src is None:
        if st.get("img"):
            # a 3D viewport / unknown image: a soft placeholder
            d = ImageDraw.Draw(tile)
            d.rounded_rectangle((0, 0, W - 1, H - 1), radius=min(W, H) // 8, fill=(60, 66, 84, 90))
        return
    r = st.get("rect")
    crop = src.crop((r[0], r[1], r[0] + r[2], r[1] + r[3])) if r and r[2] > 0 else src
    k = min(W / crop.size[0], H / crop.size[1])
    cw, ch = max(1, int(crop.size[0] * k)), max(1, int(crop.size[1] * k))
    im = crop.resize((cw, ch), Image.LANCZOS)
    arr = np.asarray(im).astype(np.float32)
    ic = st.get("ic") or [255, 255, 255]
    for c in range(3):
        arr[..., c] *= ic[c] / 255.0
    arr[..., 3] *= 1 - (st.get("it") or 0)
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    if st.get("rot"):
        im = im.rotate(-st["rot"], resample=Image.BICUBIC, expand=False)
    tile.alpha_composite(im, ((W - cw) // 2, (H - ch) // 2))


def render_item(it):
    st = it.get("style") or {}
    W, H = max(1, int(round(it["w"] * SS))), max(1, int(round(it["h"] * SS)))
    if W > 6000 or H > 6000:
        return None
    tile = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    rad = min((st.get("radius") or 0) * SS, min(W, H) / 2)
    bgT = it.get("bgT")
    if bgT is None:
        bgT = 0 if it["class"] == "Frame" else 1
    if bgT < 0.995 and st.get("bg"):
        a = int(255 * (1 - bgT))
        if rad > 0.5:
            d.rounded_rectangle((0, 0, W - 1, H - 1), radius=rad, fill=tuple(st["bg"]) + (a,))
        else:
            d.rectangle((0, 0, W - 1, H - 1), fill=tuple(st["bg"]) + (a,))
    if it["class"] in ("ImageLabel", "ImageButton"):
        draw_image(tile, st, W, H)
    if it.get("text") is not None:
        draw_text(tile, it, st, W, H)
    if st.get("grad"):
        tile = apply_gradient(tile, st["grad"])
        d = ImageDraw.Draw(tile)
    s = st.get("stroke")
    if s and s.get("border") and s["t"] < 0.99:
        sw = max(1, int(round(s["w"] * SS)))
        a = int(255 * (1 - s["t"]))
        if rad > 0.5:
            d.rounded_rectangle((0, 0, W - 1, H - 1), radius=rad, outline=tuple(s["c"]) + (a,), width=sw)
        else:
            d.rectangle((0, 0, W - 1, H - 1), outline=tuple(s["c"]) + (a,), width=sw)
    return tile


def backdrop(w, h, kind):
    """the 3D scene stand-in: a dark arena with a warm key light from above."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w * (0.62 if kind == "menu" else 0.5), h * 0.3
    r = np.sqrt(((xs - cx) / w) ** 2 * 2.2 + ((ys - cy) / h) ** 2)
    glow = np.clip(1 - r * 1.25, 0, 1) ** 2
    base = np.stack([14 + 60 * glow, 16 + 46 * glow, 22 + 30 * glow], -1)
    # a ring canvas floor and ropes in the lower half (just a hint)
    floor = (ys > h * 0.68).astype(np.float32)
    base += floor[..., None] * np.array([18, 16, 14]) * (1 - np.clip((ys - h * 0.68) / (h * 0.32), 0, 1))[..., None]
    for k, y in enumerate((0.5, 0.56, 0.62)):
        band = np.exp(-((ys - h * y) / 2.0) ** 2)
        base += band[..., None] * np.array([90, 22, 26]) * (0.6 if k else 0.8)
    im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    return im


def render(doc, out_path, label=True):
    w, h = int(doc["w"]), int(doc["h"])
    name = (doc.get("title") or "").split("  ")[0]
    canvas = backdrop(w * SS, h * SS, "menu" if name.startswith("menu") else "x")
    # draw order: ScreenGui DisplayOrder, then the gui's order of appearance, then the Sibling paint key
    gui_first = {}
    for i, it in enumerate(doc["items"]):
        g = it["path"].split(".")[0]
        gui_first.setdefault(g, i)
    items = sorted(doc["items"], key=lambda it: (it.get("order") or 0, gui_first[it["path"].split(".")[0]], (it.get("style") or {}).get("key", "")))
    for it in items:
        if it.get("w", 0) < 0.5 or it.get("h", 0) < 0.5:
            continue
        tile = render_item(it)
        if tile is None:
            continue
        x, y = int(round(it["x"] * SS)), int(round(it["y"] * SS))
        clip = it.get("clip")
        if clip:
            cx0, cy0, cx1, cy1 = [int(round(v * SS)) for v in clip]
            # crop the tile to the clip
            l, t_ = max(0, cx0 - x), max(0, cy0 - y)
            r_, b = min(tile.size[0], cx1 - x), min(tile.size[1], cy1 - y)
            if r_ <= l or b <= t_:
                continue
            tile = tile.crop((l, t_, r_, b))
            x, y = x + l, y + t_
        # paste with clipping to the canvas
        l, t_ = max(0, -x), max(0, -y)
        r_, b = min(tile.size[0], canvas.size[0] - x), min(tile.size[1], canvas.size[1] - y)
        if r_ <= l or b <= t_:
            continue
        canvas.alpha_composite(tile.crop((l, t_, r_, b)), (x + l, y + t_))
    canvas = canvas.resize((w, h), Image.LANCZOS)
    # the engine's top bar buttons (menu / chat), for scale
    d = ImageDraw.Draw(canvas)
    sl = (doc.get("safe") or {}).get("l", 0)
    for i in range(2):
        x0 = sl + 12 + i * 52
        d.rounded_rectangle((x0, 10, x0 + 44, 54), radius=22, fill=(18, 18, 22, 170))
    if label:
        d.text((w - 8, h - 6), doc.get("title") or "", font=font("heavy", 12), fill=(255, 255, 255, 120), anchor="rd")
    canvas.convert("RGB").save(out_path, quality=92)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--all", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--devices", default="")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    files = list(a.files)
    if a.all:
        files += sorted(glob.glob(os.path.join(a.all, "*.json")))
    only = set(filter(None, a.only.split(",")))
    devs = set(filter(None, a.devices.split(",")))
    os.makedirs(a.out, exist_ok=True)
    for f in files:
        base = os.path.splitext(os.path.basename(f))[0]
        scr, _, dev = base.rpartition("_")
        if only and scr not in only:
            continue
        if devs and dev not in devs:
            continue
        with open(f) as fh:
            doc = json.load(fh)
        out = os.path.join(a.out, base + ".jpg")
        render(doc, out)
        print(out)


if __name__ == "__main__":
    main()
