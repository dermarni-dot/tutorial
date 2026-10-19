"""Builds the game's icon set and title logo (white-on-transparent glyphs the game tints with ImageColor3).

    python3 tools/ui/build_icons.py            # -> tools/ui/out/icons_<n>.png, logo.png, icons.json, previews
    python3 tools/ui/build_icons.py --only gloves,belt   # just re-render a few cells into out/single/

Style: flat, bold, filled glyphs on a 256 px cell with a 20 px safe margin, details knocked out as 12 px
gaps (so one colour reads at 16 px and at 96 px), round caps and joins, the stroke icons (chevron, close,
check ...) at a 30 px stroke. Each glyph is authored as SVG on a black ground: white = ink, black = knock-out;
the render's luminance becomes the alpha of a pure white PNG.

Sheets: Roblox scales an uploaded image down to 1024 x 1024, so the 256 px cells go 4 x 4 into 1024 px sheets
(icons_1.png ...). icons.json lists every icon's sheet and rect; publish_icons.py uploads the sheets and the
logo and writes src/shared/IconData.lua.

The logo (logo.png, 1024 x 1024): the full-colour "BECOME A WORLD CLASS BOXER" lockup in the top half
(1024 x 512) and its white silhouette in the bottom half (the title screen's shine sweeps a band of it).

Needs cairosvg (pip install cairosvg; uses the system libcairo) and Pillow. Fonts: Inter / Inter Display
(fontconfig).
"""
import argparse
import io
import json
import math
import os
import sys

import cairosvg
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
CELL = 256
PER_ROW = 4
PER_SHEET = PER_ROW * PER_ROW
W, K = "#fff", "#000"
FONT = "Inter Display"


# ---------------------------------------------------------------------------------------------- helpers
def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def pts(points):
    return " ".join(f"{f(x)},{f(y)}" for x, y in points)


def poly(points, fill=W, stroke=None, sw=0, join="round"):
    s = f'<polygon points="{pts(points)}" fill="{fill}"'
    if stroke:
        s += f' stroke="{stroke}" stroke-width="{f(sw)}" stroke-linejoin="{join}"'
    return s + "/>"


def line(points, sw=30, color=W, cap="round", join="round"):
    return (f'<polyline points="{pts(points)}" fill="none" stroke="{color}" stroke-width="{f(sw)}" '
            f'stroke-linecap="{cap}" stroke-linejoin="{join}"/>')


def path(d, fill=W, stroke=None, sw=0, cap="round", join="round", rule="nonzero"):
    s = f'<path d="{d}" fill="{fill}" fill-rule="{rule}"'
    if stroke:
        s += f' stroke="{stroke}" stroke-width="{f(sw)}" stroke-linecap="{cap}" stroke-linejoin="{join}"'
    return s + "/>"


def stroke(d, sw=30, color=W, cap="round", join="round"):
    return path(d, fill="none", stroke=color, sw=sw, cap=cap, join=join)


def circle(cx, cy, r, fill=W, stroke=None, sw=0):
    s = f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="{fill}"'
    if stroke:
        s += f' stroke="{stroke}" stroke-width="{f(sw)}"'
    return s + "/>"


def ellipse(cx, cy, rx, ry, fill=W, rot=0):
    t = f' transform="rotate({f(rot)} {f(cx)} {f(cy)})"' if rot else ""
    return f'<ellipse cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}" fill="{fill}"{t}/>'


def rect(x, y, w, h, r=0, fill=W, rot=None, stroke=None, sw=0):
    t = f' transform="rotate({f(rot[0])} {f(rot[1])} {f(rot[2])})"' if rot else ""
    s = f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(r)}" fill="{fill}"{t}'
    if stroke:
        s += f' stroke="{stroke}" stroke-width="{f(sw)}"'
    return s + "/>"


def text(x, y, s, size, fill=K, weight=900, anchor="middle", italic=False, spacing=0, family=FONT):
    st = ' font-style="italic"' if italic else ""
    ls = f' letter-spacing="{f(spacing)}"' if spacing else ""
    return (f'<text x="{f(x)}" y="{f(y)}" font-family="{family}" font-weight="{weight}" font-size="{f(size)}"'
            f' text-anchor="{anchor}" fill="{fill}"{st}{ls}>{s}</text>')


def arc_pts(cx, cy, r, a0, a1, n=48):
    """points on a circle from angle a0 to a1 (degrees, 0 = +x, clockwise on screen)."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def star_pts(cx, cy, ro, ri, n=5, rot=-90):
    out = []
    for i in range(n * 2):
        r = ro if i % 2 == 0 else ri
        a = math.radians(rot + i * 180 / n)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def star(cx, cy, ro, ri=None, fill=W, n=5, round_=8):
    ri = ri or ro * 0.45
    return poly(star_pts(cx, cy, ro, ri, n), fill=fill, stroke=fill, sw=round_)


def g(body, transform):
    return f'<g transform="{transform}">{body}</g>'


# ---------------------------------------------------------------------------------------------- glyphs
# every glyph: SVG body in a 256 x 256 box, white ink on black
I = {}


def icon(name):
    def deco(fn):
        I[name] = fn
        return fn
    return deco


# --- interface ---------------------------------------------------------------------------------------
@icon("close")
def _():
    return line([(64, 64), (192, 192)]) + line([(192, 64), (64, 192)])


@icon("chevron")  # points right; UI.Icon rotates it for left / up / down
def _():
    return line([(100, 52), (176, 128), (100, 204)], sw=34)


@icon("check")
def _():
    return line([(50, 136), (104, 190), (208, 72)], sw=34)


@icon("plus")
def _():
    return line([(128, 52), (128, 204)]) + line([(52, 128), (204, 128)])


@icon("minus")
def _():
    return line([(52, 128), (204, 128)])


@icon("play")
def _():
    return poly([(86, 52), (200, 128), (86, 204)], stroke=W, sw=26)


@icon("menu")
def _():
    return "".join(line([(48, y), (208, y)], sw=26) for y in (72, 128, 184))


@icon("reset")
def _():
    a0, a1, cx, cy, r = -60, 200, 128, 134, 80
    pts_ = arc_pts(cx, cy, r, a0, a1, 64)
    ex, ey = pts_[-1]
    t = math.radians(a1)
    dx, dy = -math.sin(t), math.cos(t)  # the arc's direction at its end
    nx, ny = -dy, dx
    tip = (ex + dx * 34, ey + dy * 34)
    b1 = (ex - dx * 8 + nx * 36, ey - dy * 8 + ny * 36)
    b2 = (ex - dx * 8 - nx * 36, ey - dy * 8 - ny * 36)
    return line(pts_[:-4], sw=30) + poly([tip, b1, b2], stroke=W, sw=10)


@icon("lock")
def _():
    return (stroke("M84 118 V90 A44 44 0 0 1 172 90 V118", sw=26)
            + rect(48, 108, 160, 124, 22)
            + circle(128, 156, 17, K) + rect(119, 160, 18, 40, 8, K))


@icon("info")
def _():
    return circle(128, 128, 108) + circle(128, 76, 17, K) + rect(112, 106, 32, 98, 12, K)


@icon("warning")
def _():
    return (poly([(128, 30), (230, 214), (26, 214)], stroke=W, sw=28)
            + line([(128, 92), (128, 150)], sw=26, color=K) + circle(128, 186, 15, K))


@icon("star")
def _():
    return star(128, 136, 112, 48, round_=14)


@icon("eye")
def _():
    return (path("M16 128 Q128 22 240 128 Q128 234 16 128 Z", stroke=W, sw=8)
            + circle(128, 128, 52, K) + circle(128, 128, 32) + circle(116, 116, 9, K))


@icon("gear")  # settings
def _():
    teeth, ro, ri = 8, 116, 88
    p = []
    for i in range(teeth):
        a = i * 360 / teeth
        for da, r in ((-15, ri), (-9, ro), (9, ro), (15, ri)):
            t = math.radians(a + da)
            p.append((128 + r * math.cos(t), 128 + r * math.sin(t)))
    return poly(p, stroke=W, sw=6) + circle(128, 128, 92) + circle(128, 128, 38, K)


# --- boxing ------------------------------------------------------------------------------------------
GLOVE = ("M100 186 C74 170 60 132 64 96 C68 48 102 20 148 20 C196 20 226 56 224 104 C222 146 202 176 174 188 Z")


def glove(fill=W, ko=K, detail=True):
    """the WCB glove: thumb on the right (as UI.Icon's Frame-drawn glove and the emblem), mirrored from _glove."""
    return g(_glove(fill, ko, detail), "translate(256 0) scale(-1 1)")


def _glove(fill=W, ko=K, detail=True):
    """a boxing glove, fist up: the big padded fist, the thumb bulging out on its left side (the notch in the
    silhouette is what reads as a glove at 16 px), the laced cuff under a gap."""
    s = path(GLOVE, fill=fill)
    s += ellipse(64, 138, 34, 46, fill=fill, rot=-18)
    if detail:
        s += stroke("M90 96 C80 126 86 158 104 182", sw=11, color=ko)
        s += stroke("M126 56 C158 42 194 56 206 88", sw=10, color=ko)
    s += path("M92 196 H190 L186 232 C186 236 182 240 176 240 H104 C98 240 94 236 94 232 Z", fill=fill)
    if detail:
        s += line([(108, 216), (174, 216)], sw=9, color=ko)
    return s


@icon("glove")
def _():
    return glove()


@icon("belt")
def _():
    s = rect(14, 100, 228, 56, 18)
    s += line([(34, 128), (62, 128)], sw=10, color=K) + line([(194, 128), (222, 128)], sw=10, color=K)
    # side plates
    s += rect(56, 92, 30, 72, 10, fill=K) + rect(62, 98, 18, 60, 6)
    s += rect(170, 92, 30, 72, 10, fill=K) + rect(176, 98, 18, 60, 6)
    # the centre plate: an octagon with a star
    oc = [(128 + 78 * math.cos(math.radians(22.5 + i * 45)), 128 + 78 * math.sin(math.radians(22.5 + i * 45))) for i in range(8)]
    s += poly(oc, fill=K, stroke=K, sw=24) + poly(oc, stroke=W, sw=10)
    oc2 = [(128 + 56 * math.cos(math.radians(22.5 + i * 45)), 128 + 56 * math.sin(math.radians(22.5 + i * 45))) for i in range(8)]
    s += poly(oc2, fill=K, stroke=K, sw=6) + star(128, 132, 44, 19, fill=W, round_=6)
    return s


@icon("heavybag")
def _():
    s = line([(128, 18), (92, 58)], sw=10) + line([(128, 18), (164, 58)], sw=10) + circle(128, 20, 12)
    s += rect(76, 54, 104, 22, 10)
    s += rect(80, 66, 96, 172, 38)
    s += line([(80, 98), (176, 98)], sw=10, color=K) + line([(80, 204), (176, 204)], sw=10, color=K)
    s += line([(102, 122), (102, 180)], sw=10, color=K)
    return s


@icon("bell")
def _():
    s = circle(128, 38, 16) + rect(118, 38, 20, 22)
    s += path("M54 182 C54 98 82 54 128 54 C174 54 202 98 202 182 Z")
    s += rect(30, 176, 196, 28, 14)
    s += circle(128, 222, 20)
    s += stroke("M86 160 C86 116 98 92 118 82", sw=11, color=K)
    return s


@icon("ring")
def _():
    s = rect(30, 44, 22, 160, 8) + rect(204, 44, 22, 160, 8)
    for y in (80, 116, 152):
        s += line([(48, y), (208, y)], sw=12)
    s += poly([(18, 196), (238, 196), (226, 232), (30, 232)], stroke=W, sw=8)
    s += line([(56, 214), (200, 214)], sw=8, color=K)
    return s


@icon("ko")
def _():
    p = []
    n = 12
    for i in range(n * 2):
        r = (120 if i % 4 == 0 else 104) if i % 2 == 0 else 70
        a = math.radians(-90 + i * 180 / n)
        p.append((128 + r * math.cos(a), 128 + r * math.sin(a) * 0.96))
    return poly(p, stroke=W, sw=6) + text(130, 154, "KO", 78, italic=True)


@icon("shield")  # gear: the WCB shield with its slot
def _():
    return (path("M128 22 L214 54 V122 C214 182 178 216 128 238 C78 216 42 182 42 122 V54 Z")
            + rect(114, 62, 28, 104, 8, fill=K))


@icon("target")
def _():
    return circle(128, 128, 110) + circle(128, 128, 84, K) + circle(128, 128, 62) + circle(128, 128, 38, K) + circle(128, 128, 18)


@icon("fist")  # power
def _():
    s = rect(76, 182, 104, 54, 10)
    s += rect(54, 92, 156, 116, 34)
    for i, x in enumerate((54, 92, 130, 168)):
        s += rect(x, 44, 40, 86, 20)
    for x in (93, 131, 169):
        s += line([(x, 52), (x, 116)], sw=8, color=K)
    # the thumb across the fingers
    s += rect(62, 122, 112, 46, 22, fill=K)
    s += rect(68, 128, 100, 34, 17)
    s += line([(84, 214), (172, 214)], sw=8, color=K)
    return s


@icon("trunks")
def _():
    s = rect(46, 32, 164, 40, 10)
    s += poly([(50, 80), (206, 80), (228, 214), (146, 214), (128, 152), (110, 214), (28, 214)], stroke=W, sw=12)
    s += line([(60, 96), (196, 96)], sw=0.01, color=K)
    s += line([(72, 52), (184, 52)], sw=8, color=K)
    s += line([(58, 120), (40, 200)], sw=10, color=K) + line([(198, 120), (216, 200)], sw=10, color=K)
    return s


@icon("robe")
def _():
    s = path("M60 56 L102 30 L128 70 L154 30 L196 56 L230 230 H26 Z", stroke=W, sw=10)
    s += line([(102, 34), (128, 120), (154, 34)], sw=10, color=K)
    s += line([(128, 120), (128, 226)], sw=8, color=K)
    s += line([(70, 150), (186, 150)], sw=12, color=K)
    s += line([(114, 150), (100, 196)], sw=8, color=K) + line([(142, 150), (156, 196)], sw=8, color=K)
    return s


@icon("wraps")
def _():
    s = rect(96, 168, 140, 44, 8)
    s += line([(150, 168), (150, 212)], sw=8, color=K) + line([(200, 168), (200, 212)], sw=8, color=K)
    s += circle(100, 118, 84)
    s += circle(100, 118, 56, K) + circle(100, 118, 44) + circle(100, 118, 20, K)
    return s


@icon("jumprope")
def _():
    s = stroke("M72 160 C60 20 196 20 184 160", sw=14)
    s += rect(52, 150, 40, 90, 18) + rect(164, 150, 40, 90, 18)
    s += line([(52, 176), (92, 176)], sw=8, color=K) + line([(164, 176), (204, 176)], sw=8, color=K)
    return s


@icon("stopwatch")
def _():
    s = rect(104, 18, 48, 22, 8) + rect(118, 34, 20, 24)
    s += rect(184, 50, 30, 18, 6, rot=(45, 199, 59))
    s += circle(128, 146, 96) + circle(128, 146, 74, K)
    s += line([(128, 146), (128, 94)], sw=16) + circle(128, 146, 16)
    s += line([(128, 146), (164, 168)], sw=12)
    return s


@icon("versus")
def _():
    return (poly([(30, 40), (226, 40), (226, 216), (30, 216)], stroke=W, sw=40)
            + text(124, 166, "VS", 128, italic=True))


@icon("laurel")
def _():
    s = ""
    for side in (-1, 1):
        cx, cy, r = 128, 124, 92
        s += stroke(" ".join(
            ("M" if i == 0 else "L") + f"{f(128 + side * (r * math.sin(math.radians(a))))} {f(cy + r * math.cos(math.radians(a)))}"
            for i, a in enumerate(range(20, 160, 10))), sw=10)
        for k, a in enumerate(range(36, 160, 22)):
            t = math.radians(a)
            x, y = 128 + side * r * math.sin(t), cy + r * math.cos(t)
            # leaf pointing outward and up
            ang = (-math.degrees(t) + 90) * side + (0 if side > 0 else 180)
            s += ellipse(x + side * 14 * math.cos(t), y - 14 * math.sin(t) * 0.2, 28, 13, rot=ang - side * 40)
    s += star(128, 92, 34, 15, round_=6)
    return s


# --- body and condition ------------------------------------------------------------------------------
HEART = ("M128 222 C46 166 20 120 20 84 C20 48 48 26 80 26 C104 26 120 40 128 58 C136 40 152 26 176 26 "
         "C208 26 236 48 236 84 C236 120 210 166 128 222 Z")


@icon("heart")
def _():
    return path(HEART)


@icon("bolt")
def _():
    return poly([(156, 18), (52, 146), (118, 146), (98, 238), (204, 104), (138, 104)], stroke=W, sw=12)


@icon("brain")
def _():
    s = ""
    for side in (-1, 1):
        for cx, cy, r in ((76, 84, 44), (60, 132, 42), (82, 178, 42), (112, 62, 38), (110, 196, 30), (104, 128, 40)):
            s += circle(128 + side * (128 - cx), cy, r)
    s += line([(128, 36), (128, 222)], sw=12, color=K)
    for side in (-1, 1):
        def X(x):
            return 128 + side * (128 - x)
        s += stroke(f"M{f(X(62))} 110 C{f(X(80))} 100 {f(X(96))} 108 {f(X(104))} 124", sw=10, color=K)
        s += stroke(f"M{f(X(92))} 64 C{f(X(98))} 80 {f(X(94))} 92 {f(X(84))} 98", sw=10, color=K)
        s += stroke(f"M{f(X(66))} 162 C{f(X(82))} 170 {f(X(100))} 164 {f(X(110))} 150", sw=10, color=K)
    return s


@icon("jaw")  # chin: a profile taking a shot on the chin
def _():
    head = ("M54 238 L56 200 C32 180 22 146 24 112 C28 56 72 24 124 24 C166 26 192 52 196 92 L214 132 "
            "C216 138 212 142 206 142 L198 144 L200 166 C200 176 194 182 184 182 L172 184 L170 198 "
            "C168 210 158 216 144 216 L124 216 L124 238 Z")
    s = path(head) + circle(146, 92, 11, K) + stroke("M70 116 C66 98 76 86 92 90 C100 100 98 116 86 124", sw=10, color=K)
    for a in (-20, 15, 50):
        t = math.radians(a)
        x0, y0 = 168 + 40 * math.cos(t), 206 + 40 * math.sin(t)
        s += line([(x0, y0), (x0 + 24 * math.cos(t), y0 + 24 * math.sin(t))], sw=11)
    return s


@icon("speed")
def _():
    s = poly([(118, 52), (194, 128), (118, 204)], stroke=W, sw=26)
    s += poly([(180, 52), (240, 128), (180, 204)], stroke=W, sw=18)
    s += poly([(118, 52), (194, 128), (118, 204)], fill="none", stroke=K, sw=0.01)
    for y, x0 in ((84, 24), (128, 12), (172, 24)):
        s += line([(x0, y), (88, y)], sw=20)
    return s


@icon("muscle")
def _():
    arm = ("M20 238 L20 198 C20 150 58 116 104 118 C128 119 144 128 152 142 L150 102 C134 94 128 74 134 56 "
           "C140 36 162 22 188 24 C216 26 236 46 236 74 C236 92 230 104 226 112 L232 156 C238 206 214 238 164 238 Z")
    return (path(arm) + stroke("M58 182 C76 158 108 152 132 164", sw=12, color=K)
            + stroke("M148 64 C162 58 176 60 188 68", sw=9, color=K) + stroke("M150 86 C164 80 178 82 190 90", sw=9, color=K))


@icon("pulse")
def _():
    return line([(14, 136), (74, 136), (98, 66), (138, 206), (166, 104), (184, 136), (242, 136)], sw=24)


@icon("water")
def _():
    return (path("M128 20 C128 20 46 112 46 162 C46 206 82 238 128 238 C174 238 210 206 210 162 C210 112 128 20 128 20 Z")
            + stroke("M86 166 C86 190 102 204 124 206", sw=13, color=K))


@icon("food")
def _():
    s = rect(64, 30, 12, 70, 6) + rect(86, 30, 12, 70, 6) + rect(108, 30, 12, 70, 6)
    s += path("M60 86 H124 V108 C124 124 112 132 100 134 V226 C100 236 84 236 84 226 V134 C72 132 60 124 60 108 Z")
    s += path("M170 30 C204 46 212 98 208 136 L190 140 V226 C190 236 172 236 172 226 V36 C172 30 170 30 170 30 Z")
    return s


@icon("sleep")
def _():
    s = circle(112, 146, 92) + circle(160, 104, 78, K)
    s += line([(150, 34), (186, 34), (150, 70), (186, 70)], sw=12, join="round")
    s += line([(198, 92), (226, 92), (198, 120), (226, 120)], sw=10)
    return s


@icon("injury")  # a plaster
def _():
    body = rect(18, 86, 220, 84, 42, rot=(-40, 128, 128))
    pad = rect(88, 92, 80, 72, 10, fill=K, rot=(-40, 128, 128))
    s = body + pad
    for dx, dy in ((-14, -14), (14, -14), (-14, 14), (14, 14), (0, 0)):
        s += circle(128 + dx, 128 + dy, 6.5)
    return s


@icon("energy")  # battery
def _():
    s = rect(18, 74, 196, 108, 22) + rect(214, 104, 24, 48, 8)
    s += rect(36, 92, 160, 72, 10, fill=K)
    for x in (48, 96, 144):
        s += rect(x, 104, 38, 48, 6)
    return s


# --- career and life ---------------------------------------------------------------------------------
@icon("money")
def _():
    s = rect(14, 58, 228, 140, 18)
    s += rect(32, 76, 192, 104, 10, fill="none", stroke=K, sw=8)
    s += circle(128, 128, 42, K)
    s += text(128, 155, "$", 78, fill=W)
    s += circle(66, 128, 9, K) + circle(190, 128, 9, K)
    return s


@icon("calendar")
def _():
    s = rect(28, 46, 200, 186, 24)
    s += rect(44, 100, 168, 116, 10, fill=K)
    s += rect(70, 22, 22, 50, 10) + rect(164, 22, 22, 50, 10)
    for r_ in range(2):
        for c in range(3):
            s += rect(60 + c * 50, 116 + r_ * 48, 36, 32, 6)
    return s


@icon("trophy")
def _():
    s = stroke("M66 66 H38 C30 66 26 74 28 84 C34 112 52 128 76 132", sw=16)
    s += stroke("M190 66 H218 C226 66 230 74 228 84 C222 112 204 128 180 132", sw=16)
    s += path("M60 30 H196 V92 C196 140 166 168 128 168 C90 168 60 140 60 92 Z")
    s += rect(114, 160, 28, 36)
    s += rect(70, 194, 116, 38, 10)
    return s


@icon("podium")
def _():
    s = rect(90, 92, 76, 140, 8) + rect(20, 142, 66, 90, 8) + rect(170, 168, 66, 64, 8)
    s += text(128, 160, "1", 64, fill=K) + text(53, 202, "2", 48, fill=K) + text(203, 220, "3", 40, fill=K)
    s += star(128, 50, 32, 14, round_=5)
    return s


@icon("medal")
def _():
    s = poly([(64, 16), (110, 16), (142, 104), (106, 120)], stroke=W, sw=8)
    s += poly([(192, 16), (146, 16), (114, 104), (150, 120)], stroke=W, sw=8)
    s += line([(128, 24), (128, 74)], sw=0.01, color=K)
    s += circle(128, 164, 76, K) + circle(128, 164, 68)
    s += circle(128, 164, 50, K) + star(128, 168, 38, 16, round_=5)
    return s


@icon("chart")
def _():
    s = rect(30, 140, 46, 86, 10) + rect(105, 92, 46, 134, 10) + rect(180, 40, 46, 186, 10)
    return s


@icon("trend")
def _():
    return (line([(26, 196), (96, 126), (136, 166), (206, 96)], sw=28)
            + poly([(232, 62), (232, 140), (154, 62)], stroke=W, sw=14))


@icon("whistle")
def _():
    s = circle(48, 82, 22, fill="none", stroke=W, sw=10)
    s += path("M86 104 H226 C234 104 238 110 238 118 V140 C238 148 232 152 224 152 H184 "
              "A84 84 0 1 1 86 104 Z")
    s += circle(104, 170, 28, K) + circle(104, 170, 12)
    s += rect(150, 92, 30, 22, 6, fill=K)
    return s


@icon("contract")  # sponsor deal
def _():
    s = path("M48 18 H162 L210 66 V224 C210 234 204 240 194 240 H48 C38 240 32 234 32 224 V34 C32 24 38 18 48 18 Z")
    s += poly([(158, 18), (158, 72), (210, 72)], fill=K, stroke=K, sw=6) + poly([(166, 34), (166, 64), (196, 64)], stroke=W, sw=4)
    for y in (88, 120, 152):
        s += line([(64, y), (176 if y > 88 else 136, y)], sw=12, color=K)
    s += stroke("M64 200 C78 176 88 216 104 196 C114 182 120 206 132 200 L176 200", sw=9, color=K)
    return s


@icon("home")
def _():
    s = poly([(128, 22), (240, 122), (16, 122)], stroke=W, sw=18)
    s += rect(44, 108, 168, 126, 12)
    s += rect(104, 152, 48, 82, 8, fill=K)
    s += rect(178, 32, 28, 58, 4)
    return s


@icon("car")
def _():
    body = ("M18 170 V136 C18 124 26 116 38 114 L70 108 L102 70 C108 62 116 58 126 58 H170 C180 58 188 62 194 70 "
            "L222 108 C232 112 238 120 238 132 V170 C238 178 232 184 224 184 H32 C24 184 18 178 18 170 Z")
    s = path(body)
    s += path("M92 108 L114 80 H142 V108 Z", fill=K) + path("M158 108 V80 H178 L198 108 Z", fill=K)
    for x in (70, 186):
        s += circle(x, 184, 36, K) + circle(x, 184, 26) + circle(x, 184, 9, K)
    return s


@icon("pin")
def _():
    return (path("M128 240 C128 240 40 154 40 100 C40 50 80 16 128 16 C176 16 216 50 216 100 C216 154 128 240 128 240 Z")
            + circle(128, 98, 36, K))


@icon("bag")  # the shop: a shopping bag
def _():
    s = stroke("M88 104 V74 C88 46 106 32 128 32 C150 32 168 46 168 74 V104", sw=18)
    s += path("M48 86 H208 L222 226 C222 234 216 240 208 240 H48 C40 240 34 234 34 226 Z")
    s += circle(88, 118, 11, K) + circle(168, 118, 11, K)
    return s


@icon("scissors")  # the barber
def _():
    s = ""
    s += poly([(122, 140), (210, 22), (222, 30), (140, 150)], stroke=W, sw=10)
    s += poly([(134, 140), (46, 22), (34, 30), (116, 150)], stroke=W, sw=10)
    s += circle(76, 192, 40, fill="none", stroke=W, sw=20) + circle(180, 192, 40, fill="none", stroke=W, sw=20)
    s += line([(104, 166), (118, 150)], sw=20) + line([(152, 166), (138, 150)], sw=20)
    s += circle(128, 132, 9, K)
    return s


@icon("user")
def _():
    return (circle(128, 82, 58) + circle(128, 82, 72, fill="none", stroke=K, sw=14)
            + path("M30 236 C30 176 74 152 128 152 C182 152 226 176 226 236 Z")
            + circle(128, 82, 52))


@icon("gamepad")
def _():
    body = ("M66 64 H190 C222 64 240 92 244 132 L248 176 C250 206 230 222 208 214 L176 194 H80 L48 214 C26 222 6 206 8 176 "
            "L12 132 C16 92 34 64 66 64 Z")
    s = path(body)
    s += line([(76, 108), (76, 156)], sw=16, color=K, cap="butt") + line([(52, 132), (100, 132)], sw=16, color=K, cap="butt")
    s += circle(178, 112, 11, K) + circle(204, 136, 11, K) + circle(178, 160, 11, K) + circle(152, 136, 11, K)
    return s


@icon("crown")
def _():
    s = poly([(30, 190), (42, 74), (92, 128), (128, 50), (164, 128), (214, 74), (226, 190)], stroke=W, sw=14)
    s += circle(42, 66, 16) + circle(128, 40, 18) + circle(214, 66, 16)
    s += rect(30, 196, 196, 36, 10)
    s += circle(80, 214, 8, K) + circle(128, 214, 8, K) + circle(176, 214, 8, K)
    return s


@icon("flame")
def _():
    outer = ("M128 238 C70 238 38 198 38 152 C38 104 76 74 94 22 C120 50 126 84 120 106 C142 94 152 72 150 48 "
             "C192 82 218 124 218 162 C218 206 186 238 128 238 Z")
    inner = ("M128 218 C100 218 84 198 84 176 C84 150 104 134 114 112 C130 128 138 144 136 160 C148 154 156 142 158 130 "
             "C170 146 174 162 174 176 C174 200 156 218 128 218 Z")
    return path(outer) + path(inner, fill=K)


@icon("skull")
def _():
    s = path("M128 20 C66 20 28 62 28 116 C28 148 42 170 64 182 V212 C64 226 74 236 88 236 H168 C182 236 192 226 192 212 "
             "V182 C214 170 228 148 228 116 C228 62 190 20 128 20 Z")
    s += ellipse(86, 124, 28, 30, K) + ellipse(170, 124, 28, 30, K)
    s += poly([(128, 154), (112, 182), (144, 182)], fill=K, stroke=K, sw=6)
    for x in (104, 128, 152):
        s += line([(x, 202), (x, 236)], sw=9, color=K)
    return s


@icon("dumbbell")
def _():
    s = rect(60, 116, 136, 24, 6)
    for side in (-1, 1):
        def X(x, w):
            return x if side < 0 else 256 - x - w
        s += rect(X(22, 30), 98, 30, 60, 10)
        s += rect(X(46, 34), 58, 34, 140, 12)
        s += rect(X(76, 24), 80, 24, 96, 10)
    return s


@icon("shoe")
def _():
    s = path("M24 182 L24 104 C24 92 32 84 44 84 H70 C80 84 88 92 92 100 C100 116 116 122 134 122 H160 "
             "C190 126 216 138 230 152 C238 160 242 170 240 182 Z")
    s += rect(30, 70, 34, 22, 8)
    s += rect(14, 182, 234, 34, 14)
    s += line([(30, 199), (232, 199)], sw=7, color=K)
    for x0, y0 in ((106, 106), (126, 112), (146, 118)):
        s += line([(x0, y0), (x0 + 12, y0 + 20)], sw=8, color=K)
    s += stroke("M44 162 C90 150 136 146 196 154", sw=10, color=K)
    return s


@icon("emblem")  # the WCB badge: rounded frame, tilted glove, the ribbon with WCB knocked out
def _():
    s = rect(14, 14, 228, 228, 52, fill="none", stroke=W, sw=16)
    s += g(glove(), "translate(128 104) rotate(-12) scale(0.62) translate(-128 -128)")
    s += rect(30, 170, 196, 54, 10)
    s += text(128, 213, "WCB", 50, fill=K, weight=900)
    return s


@icon("coin")  # money, the WCB coin: a ring with a plus-shaped mark
def _():
    return (circle(128, 128, 104) + circle(128, 128, 80, K)
            + rect(113, 72, 30, 112, 10) + rect(80, 113, 96, 30, 10))


@icon("people")  # the corner team: two figures
def _():
    s = circle(100, 76, 42) + path("M28 232 C28 166 58 136 100 136 C142 136 172 166 172 232 Z")
    s += circle(190, 92, 30) + path("M182 232 C182 196 176 168 160 150 C170 144 180 142 190 142 C220 142 240 170 240 212 V232 Z")
    s += circle(100, 76, 54, fill="none", stroke=K, sw=10)
    return s


ORDER = [
    # interface
    "close", "chevron", "check", "plus", "minus", "play", "menu", "reset", "lock", "info", "warning", "star", "eye", "gear",
    # boxing
    "glove", "belt", "heavybag", "bell", "ring", "ko", "shield", "target", "fist", "trunks", "robe", "wraps", "jumprope",
    "stopwatch", "versus", "laurel",
    # body and condition
    "heart", "bolt", "brain", "jaw", "speed", "muscle", "pulse", "water", "food", "sleep", "injury", "energy",
    # career and life
    "money", "calendar", "trophy", "podium", "medal", "chart", "trend", "whistle", "contract", "home", "car", "pin", "bag",
    "scissors", "user", "gamepad", "crown", "flame", "skull", "dumbbell", "shoe", "emblem", "coin", "people",
]


# ---------------------------------------------------------------------------------------------- render
def render_svg(svg, w, h):
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=w, output_height=h)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def render_icon(name, size=CELL):
    body = I[name]()
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 256 256">'
           f'<rect width="256" height="256" fill="#000"/>{body}</svg>')
    im = render_svg(svg, size, size)
    lum = im.convert("L")
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(lum)
    return out


def build_sheets(names):
    sheets, meta = [], {}
    for i, name in enumerate(names):
        si, k = divmod(i, PER_SHEET)
        if si >= len(sheets):
            sheets.append(Image.new("RGBA", (CELL * PER_ROW, CELL * PER_ROW), (255, 255, 255, 0)))
        row, col = divmod(k, PER_ROW)
        sheets[si].alpha_composite(render_icon(name), (col * CELL, row * CELL))
        meta[name] = {"sheet": si + 1, "x": col * CELL, "y": row * CELL, "w": CELL, "h": CELL}
    return sheets, meta


# ---------------------------------------------------------------------------------------------- logo
FONT_FILE = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
CAP = 0.727  # Inter's cap height (em)


def fit_text(s, x, baseline, width, cap_h, fill, spacing_em=0.0, skew=-9, sx_max=1.0, weight=900, extra="", align="center"):
    """s set in Inter Display Black with its caps cap_h tall, squeezed (or letter-spaced) to exactly `width`
    from x: a condensed broadcast face from a regular one. Returns the SVG and the horizontal scale used."""
    size = cap_h / CAP
    ft = ImageFont.truetype(FONT_FILE, 200)
    natural = ft.getlength(s) * size / 200 + spacing_em * size * (len(s) - 1)
    sx = min(sx_max, width / natural)
    sp = f' letter-spacing="{f(spacing_em * size)}"' if spacing_em else ""
    t = (f'<text x="0" y="0" font-family="{FONT}" font-weight="{weight}" font-size="{f(size)}" fill="{fill}"{sp} {extra}>{s}</text>')
    off = (width - natural * sx) / 2 if align == "center" else 0
    return f'<g transform="translate({f(x + off)} {f(baseline)}) skewX({skew}) scale({f(sx)} 1)">{t}</g>', sx


def badge(x, y, size, silhouette):
    """UI.Brand as an image: the ink tile with its gold keyline, the gold glove tilted -12 degrees, the red WCB ribbon."""
    k = size / 256.0
    ink = W if silhouette else "#05060a"
    gold = W if silhouette else "url(#gold)"
    red = W if silhouette else "#f3414c"
    s = f'<g transform="translate({f(x)} {f(y)}) scale({f(k)})">'
    s += rect(4, 4, 248, 248, 56, fill=ink, stroke=gold, sw=8)
    if not silhouette:
        s += rect(4, 4, 248, 248, 56, fill="url(#inkSheen)")
    s += g(glove(fill=gold, ko=ink), "translate(128 100) rotate(-12) scale(0.62) translate(-128 -128)")
    s += rect(18, 180, 220, 56, 10, fill=red)
    s += text(128, 226, "WCB", 50, fill=ink if silhouette else "#ffffff", weight=900)
    return s + "</g>"


def logo_svg(silhouette=False):
    """The 1024 x 512 lockup, as the title screen draws it: the WCB badge, THE ROAD TO UNDISPUTED, WORLD CLASS
    (white) over BOXER (gold), a red rule and the tagline."""
    if silhouette:
        gold = white = red = gold_b = W
        defs = ""
    else:
        gold, white, red, gold_b = "#ffcd53", "#ffffff", "#f3414c", "url(#goldText)"
        defs = """<defs>
        <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#ffedb8"/><stop offset="0.5" stop-color="#ffcd53"/><stop offset="1" stop-color="#d0942b"/></linearGradient>
        <linearGradient id="goldText" gradientUnits="userSpaceOnUse" x1="0" y1="-190" x2="0" y2="0">
          <stop offset="0" stop-color="#ffedb8"/><stop offset="0.5" stop-color="#ffcd53"/><stop offset="1" stop-color="#d0942b"/></linearGradient>
        <linearGradient id="inkSheen" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#ffffff" stop-opacity="0.10"/><stop offset="1" stop-color="#99a6be" stop-opacity="0"/></linearGradient>
      </defs>"""
    out = [badge(24, 120, 272, silhouette)]
    x0, x1 = 336, 1000
    k, _ = fit_text("THE ROAD TO UNDISPUTED", x0 + 16, 104, 420, 22, gold, spacing_em=0.12, skew=0, weight=800, align="left")
    out.append(rect(x0, 82, 6, 24, 1, fill=gold))
    out.append(k)
    world, _ = fit_text("WORLD CLASS", x0, 214, x1 - x0, 92, white, skew=0, sx_max=0.86, align="left")
    boxer, _ = fit_text("BOXER", x0 - 4, 410, x1 - x0, 180, gold_b, skew=0, sx_max=0.86, align="left")
    if not silhouette:
        sh, _ = fit_text("BOXER", x0 + 2, 418, x1 - x0, 180, "#000", skew=0, sx_max=0.86, extra='opacity="0.45"', align="left")
        out.append(sh)
    out += [world, boxer]
    out.append(rect(24, 448, 272, 8, 2, fill=red))
    tag, _ = fit_text("TRAIN. FIGHT. BECOME UNDISPUTED.", x0, 462, 520, 24, "#b2bccd" if not silhouette else W, skew=0, weight=600, sx_max=1.0, align="left")
    out.append(tag)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="512" viewBox="0 0 1024 512">{defs}'
            + "".join(out) + "</svg>")


def build_logo():
    colour = render_svg(logo_svg(False), 1024, 512)
    sil = render_svg(logo_svg(True), 1024, 512)
    # the silhouette: white, alpha = its coverage
    a = sil.split()[3]
    white = Image.new("RGBA", sil.size, (255, 255, 255, 0))
    white.putalpha(a)
    sheet = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    sheet.alpha_composite(colour, (0, 0))
    sheet.alpha_composite(white, (0, 512))
    return sheet


# ---------------------------------------------------------------------------------------------- previews
def preview(names, meta, sheets, path_out):
    """the icon sheet on the game's panel colours, tinted the way the UI uses them."""
    cols = 8
    cell = 132
    rows = math.ceil(len(names) / cols)
    W_, H_ = cols * cell + 40, rows * cell + 110
    im = Image.new("RGBA", (W_, H_), (10, 12, 17, 255))
    d = ImageDraw.Draw(im)
    try:
        ft = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-SemiBold.otf", 13)
        fh = ImageFont.truetype("/usr/share/fonts/opentype/inter/InterDisplay-Black.otf", 30)
    except OSError:
        ft = fh = ImageFont.load_default()
    d.text((20, 22), "WORLD CLASS BOXER  ·  ICON SET  ·  %d GLYPHS" % len(names), font=fh, fill=(247, 196, 66))
    tints = [(242, 244, 248), (247, 196, 66), (234, 48, 56), (58, 142, 255), (50, 214, 126)]
    for i, name in enumerate(names):
        r, c = divmod(i, cols)
        x0, y0 = 20 + c * cell, 80 + r * cell
        d.rounded_rectangle((x0 + 6, y0 + 6, x0 + cell - 6, y0 + cell - 6), 12, fill=(20, 23, 31), outline=(40, 45, 58))
        m = meta[name]
        tile = sheets[m["sheet"] - 1].crop((m["x"], m["y"], m["x"] + m["w"], m["y"] + m["h"])).resize((72, 72), Image.LANCZOS)
        tint = tints[(i // 1) % len(tints)] if name in ("heart", "bolt", "money", "trophy", "belt", "crown", "flame", "water", "injury", "warning") else tints[0]
        if name in ("money", "coin", "trophy", "belt", "crown", "star", "medal", "laurel", "emblem", "glove"):
            tint = tints[1]
        elif name in ("heart", "injury", "flame", "ko", "fist", "warning"):
            tint = tints[2]
        elif name in ("bolt", "water", "energy", "speed", "brain"):
            tint = tints[3]
        elif name in ("check", "trend", "food", "pulse"):
            tint = tints[4]
        col = Image.new("RGBA", tile.size, tint + (255,))
        col.putalpha(tile.split()[3])
        im.alpha_composite(col, (x0 + (cell - 72) // 2, y0 + 16))
        # a 20 px rendition (the smallest size the HUD uses) in the corner
        small = tile.resize((20, 20), Image.LANCZOS)
        col2 = Image.new("RGBA", small.size, (150, 158, 176, 255))
        col2.putalpha(small.split()[3])
        im.alpha_composite(col2, (x0 + 12, y0 + 12))
        tw = d.textlength(name, font=ft)
        d.text((x0 + (cell - tw) / 2, y0 + cell - 30), name, font=ft, fill=(150, 158, 176))
    im.convert("RGB").save(path_out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    missing = [n for n in ORDER if n not in I]
    extra = [n for n in I if n not in ORDER]
    if missing or extra:
        sys.exit(f"ORDER / glyphs mismatch: missing {missing} extra {extra}")
    if a.only:
        d = os.path.join(OUT, "single")
        os.makedirs(d, exist_ok=True)
        for n in a.only.split(","):
            render_icon(n).save(os.path.join(d, n + ".png"))
        return
    sheets, meta = build_sheets(ORDER)
    for i, s in enumerate(sheets):
        s.save(os.path.join(OUT, f"icons_{i + 1}.png"), optimize=True)
    logo = build_logo()
    logo.save(os.path.join(OUT, "logo.png"), optimize=True)
    doc = {"cell": CELL, "sheets": [f"icons_{i + 1}.png" for i in range(len(sheets))], "icons": meta, "order": ORDER,
           "logo": {"file": "logo.png", "colour": {"x": 0, "y": 0, "w": 1024, "h": 512}, "mask": {"x": 0, "y": 512, "w": 1024, "h": 512}}}
    with open(os.path.join(OUT, "icons.json"), "w") as fh:
        json.dump(doc, fh, indent=1)
    preview(ORDER, meta, sheets, a.preview or os.path.join(OUT, "icon_sheet_preview.png"))
    # the logo on the title screen's colours
    bg = Image.new("RGBA", (1024, 512), (10, 12, 17, 255))
    bg.alpha_composite(logo.crop((0, 0, 1024, 512)))
    bg.convert("RGB").save(os.path.join(OUT, "logo_preview.png"))
    print(f"{len(ORDER)} icons on {len(sheets)} sheets, logo -> {OUT}")


if __name__ == "__main__":
    main()
