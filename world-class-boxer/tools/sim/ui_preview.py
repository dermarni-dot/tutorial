#!/usr/bin/env python3
"""ui_preview.py: rough layout previews of guisim box dumps (GS.WriteBoxes JSON).

    python3 tools/sim/ui_preview.py <boxes.json> [<boxes.json> ...] --out DIR

Each JSON becomes DIR/<basename>.png at the device's screen size: the bounding box of every GUI object that
draws or takes input (buttons filled blue, text boxes outlined white with their text, frames grey), the Roblox
top bar (58 px, its button zone hatched) and the device's safe insets in orange, and anything a check flagged
("bad") in red. A rough picture of where things land, not a render.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, max(6, int(size)))
    return ImageFont.load_default()


def render(doc, out_path):
    w, h = int(doc["w"]), int(doc["h"])
    img = Image.new("RGB", (w, h), (26, 30, 38))
    d = ImageDraw.Draw(img, "RGBA")
    # the top bar and its buttons, the safe insets
    safe = doc.get("safe") or {}
    tb = doc.get("topbar", 58)
    d.rectangle([0, 0, w, tb], fill=(255, 255, 255, 18))
    bx0 = safe.get("l", 0)
    bx1 = bx0 + doc.get("topbarButtonsW", 200)
    for x in range(int(bx0), int(bx1), 8):
        d.line([x, 0, x + tb, tb], fill=(255, 255, 255, 40))
    d.text((bx0 + 4, 4), "top bar", fill=(255, 255, 255, 120), font=font(11))
    for side in ("l", "r", "b", "t"):
        v = safe.get(side, 0) or 0
        if v <= 0:
            continue
        box = {"l": [0, 0, v, h], "r": [w - v, 0, w, h], "b": [0, h - v, w, h], "t": [0, 0, w, v]}[side]
        d.rectangle(box, fill=(255, 150, 40, 40))
    # drawn in the order guisim collected them (DisplayOrder, then tree order)
    items = sorted(doc["items"], key=lambda it: it.get("seq", 0))
    for it in items:
        x0, y0 = it["x"], it["y"]
        x1, y1 = x0 + it["w"], y0 + it["h"]
        clip = it.get("clip")
        if clip:
            x0, y0 = max(x0, clip[0]), max(y0, clip[1])
            x1, y1 = min(x1, clip[2]), min(y1, clip[3])
            if x1 <= x0 or y1 <= y0:
                continue
        bad = it.get("bad")
        if it.get("button"):
            fill, line = (58, 142, 255, 70), (120, 180, 255, 200)
        elif it.get("text"):
            fill, line = None, (240, 240, 240, 90)
        else:
            # a panel: as solid as its background (a modal shade or a window hides what is under it)
            bg = it.get("bgT")
            alpha = 22 if bg is None else int(max(0.0, 1.0 - bg) * 170)
            fill, line = (52, 58, 72, max(alpha, 10)), (200, 205, 215, 70)
        if it.get("blocked"):
            # under a modal shade: an outline only
            fill = None
            line = (line[0], line[1], line[2], line[3] // 3)
        if bad:
            fill, line = (234, 48, 56, 90), (255, 80, 80, 255)
        d.rectangle([x0, y0, x1, y1], fill=fill, outline=line)
        txt = it.get("text")
        if txt and not it.get("blocked"):
            size = max(7, min(it.get("textSize") or 12, (y1 - y0) * 0.8, 40))
            t = txt.split("\n")[0] if not it.get("wrapped") else txt.replace("\n", " ")
            f = font(size)
            tw = d.textlength(t, font=f)
            # the preview face is not the game's: scale it to the width guisim measured for the line
            want = it.get("textW")
            if want and tw > 0 and not it.get("wrapped"):
                size = max(6, size * want / tw)
                f = font(size)
                tw = d.textlength(t, font=f)
            if it.get("truncate") and tw > (x1 - x0) and len(t) > 1:
                while len(t) > 1 and d.textlength(t + "...", font=f) > (x1 - x0):
                    t = t[:-1]
                t = t + "..."
                tw = d.textlength(t, font=f)
            align = it.get("align") or "Left"
            tx = x0 + 2 if align == "Left" else (x1 - 2 - tw if align == "Right" else (x0 + x1 - tw) / 2)
            d.text((tx, y0 + max(0, ((y1 - y0) - size) / 2 - 1)), t, fill=(250, 250, 250, 210), font=f)
    title = doc.get("title") or doc.get("device", "")
    d.text((8, h - 18), "%s  %dx%d" % (title, w, h), fill=(255, 220, 120, 220), font=font(12))
    img.save(out_path)


def main(argv):
    out = "."
    files = []
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 2
            continue
        files.append(argv[i])
        i += 1
    os.makedirs(out, exist_ok=True)
    for f in files:
        with open(f) as fh:
            doc = json.load(fh)
        name = os.path.splitext(os.path.basename(f))[0] + ".png"
        render(doc, os.path.join(out, name))
        print(os.path.join(out, name))


if __name__ == "__main__":
    main(sys.argv[1:])
