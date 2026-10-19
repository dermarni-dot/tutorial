"""Classic-style face textures for the R15 head (original designs in the spirit of the classic smiley decal:
simple dark eyes, brows and mouth on a transparent background).

    python3 tools/body/faces.py [--sheet PATH]

Outputs
    tools/body/out/faces/face_<key>.png   512 x 512 RGBA, dark features on alpha (a Decal on the head's front:
                                          the whole image spans the head's front face, like the classic face)
    tools/body/out/faces/faces.json       keys / names / expressions (read by publish_body.py)
    tools/body/out/faces/contact_sheet.png  every face on a skin-tone head front, labelled
    tools/body/out/faces/face_wcb_<k>[_v2].png  the user's "Boxer" face pack (PACK below): 1254 x 1254 RGBA, the
                                          full square canvas kept, only re-registered (see register_pack)

The Boxer pack is not drawn here: it is the user's own art (faces/<k>.png of their faces + hair hand-off), added
with `--pack DIR` (DIR = that faces/ folder). Its entries stay in faces.json on every later run (from the files
already in out/faces), so a plain re-run never drops them. `--pack-only` registers the pack and rewrites
faces.json without redrawing the classic faces (their PNGs, and so their uploaded ids, stay byte-identical).

FACES (order = the creator's order; "smile" is the default) and EXPRESSIONS (fight / gym mood -> face key,
None = the boxer's own chosen face) are the data publish_body.py writes into src/shared/BodyAssetData.lua.
"""
import argparse
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "out", "faces")
SCRATCH = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/body"

FACES = [
    ("smile", "Smile"), ("grin", "Grin"), ("smirk", "Smirk"), ("confident", "Confident"), ("cool", "Cool"),
    ("happy", "Happy"), ("wink", "Wink"), ("determined", "Determined"), ("focused", "Focused"),
    ("stern", "Stern"), ("angry", "Angry"), ("grit", "Grit"), ("surprised", "Surprised"), ("tired", "Tired"),
    ("hurt", "Hurt"), ("dazed", "Dazed"), ("ko", "KO"),
]
# the faces a player can pick in the creator (the rest are mood faces the game swaps in)
CREATOR = ["smile", "grin", "smirk", "confident", "cool", "happy", "wink", "determined", "focused", "stern"]

# the user's Boxer face pack (key, name, source file): the drawn face STYLE set (look.face.style; BodyTiers.STYLE_KEYS),
# offered in the creator as a whole-face alternative to the built face, and swapped among by mood (FaceFX)
PACK = [("wcb_neutral", "Boxer Neutral", "neutral.png"), ("wcb_focused", "Boxer Focused", "focused.png"),
        ("wcb_smirk", "Boxer Smirk", "smirk.png"), ("wcb_grit", "Boxer Grit", "grit.png")]
PACK_REF = "wcb_neutral"  # the registration reference (its file is kept as it came)

# fight / gym moods -> face key; None = keep the boxer's own chosen face
EXPRESSIONS = {
    "neutral": None,        # walking around, menus, idle
    "guard": "focused",     # in the ring, hands up
    "attack": "determined", # throwing a combination / special
    "block": "determined",
    "effort": "grit",       # heavy lift, sprint, last reps, clinch
    "hurt": "hurt",         # took a big hit (short flash)
    "stunned": "dazed",     # wobbled / knocked down, counting
    "dazed": "dazed",
    "ko": "ko",             # knocked out
    "tired": "tired",       # low stamina, end of a hard session
    "angry": "angry",       # hit after the bell, taunted
    "surprised": "surprised",
    "taunt": "smirk",
    "confident": "confident",  # walkout, faceoff
    "happy": "grin",        # win, level up, new gear
    "celebrate": "happy",   # belt, round won by KO
    "rest": "smile",        # corner between rounds when ahead, shower, sleep
    "train": "focused",     # bag / pads / skipping
    "lose": "tired",
}

INK = (24, 19, 17, 255)
WHITE = (250, 248, 244, 255)
TONGUE = (176, 62, 66, 255)
SS = 2048  # supersampled canvas, downsampled to 512
FACE_CY, FACE_HALF = 0.47, 0.36  # the zoom window (unit coords) saved as the 512 image


class Face:
    def __init__(self):
        self.im = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def px(p):
        return (p[0] * SS, p[1] * SS)

    # ------------------------------------------------------------------ primitives (unit square, y down)
    def ellipse(self, cx, cy, rx, ry, fill=INK):
        self.d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=fill)

    def ring(self, cx, cy, rx, ry, w, fill=INK):
        self.d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], outline=fill,
                       width=int(w * SS))

    def stroke(self, pts, w, fill=INK):
        P = [self.px(p) for p in pts]
        self.d.line(P, fill=fill, width=int(w * SS), joint="curve")
        r = w * SS / 2
        for x, y in (P[0], P[-1]):
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def poly(self, pts, fill=INK):
        self.d.polygon([self.px(p) for p in pts], fill=fill)

    def masked(self, draw_shape, clip_poly, fill=INK):
        """draws a shape (callable on an ImageDraw in px) only inside clip_poly (unit coords)"""
        m1 = Image.new("L", (SS, SS), 0)
        draw_shape(ImageDraw.Draw(m1))
        m2 = Image.new("L", (SS, SS), 0)
        ImageDraw.Draw(m2).polygon([self.px(p) for p in clip_poly], fill=255)
        m = ImageChops.multiply(m1, m2)
        layer = Image.new("RGBA", (SS, SS), fill)
        self.im.paste(layer, (0, 0), m)

    # ------------------------------------------------------------------ features
    def eye(self, cx, cy, rx=0.03, ry=0.062, lid=None, under=None):
        """oval eye; lid = (height fraction cut from the top 0..1, tilt: + = the outer corner lower) gives a
        heavy upper lid with a lid line; under = fraction cut from the bottom (a squint)"""
        if lid is None and under is None:
            self.ellipse(cx, cy, rx, ry)
            return
        top = cy - ry + 2 * ry * (lid[0] if lid else 0.0)
        # tilt > 0: the inner corner (toward the nose) lower (angry); < 0: the outer corner lower (tired)
        k = (lid[1] if lid else 0.0) * (1 if cx > 0.5 else -1) * 0.03
        bot = cy + ry - 2 * ry * (under or 0.0)
        e = 0.0
        clip = [(cx - rx * 1.6, top + k), (cx + rx * 1.6, top - k), (cx + rx * 1.6, bot), (cx - rx * 1.6, bot)]
        self.masked(lambda d: d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255),
                    clip)
        if lid:
            self.stroke([(cx - rx * 1.55, clip[0][1] - 0.004), (cx + rx * 1.55, clip[1][1] - 0.004)], 0.014)

    def brow(self, cx, cy, half=0.06, tilt=0.0, arch=0.0, w=0.02):
        """tilt > 0: inner end (toward the nose) lower = angry / determined; < 0: worried. arch bows it up"""
        sg = 1 if cx > 0.5 else -1
        pts = []
        for i in range(9):
            t = i / 8  # 0 inner -> 1 outer
            x = cx + sg * (t - 0.5) * 2 * half
            y = cy + tilt * (0.5 - t) - arch * math.sin(math.pi * t)
            pts.append((x, y))
        self.stroke(pts, w)

    def arc(self, cx, cy, rx, ry, a0, a1, w=0.024, n=40):
        pts = [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
                cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
        self.stroke(pts, w)
        return pts

    def curve(self, pts, w=0.024, n=48):
        """smooth Catmull-Rom through the points"""
        P = [pts[0]] + list(pts) + [pts[-1]]
        out = []
        for i in range(1, len(P) - 2):
            p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
            for k in range(n // (len(P) - 3)):
                t = k / (n // (len(P) - 3))
                out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j])
                                        * t * t + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in range(2)))
        out.append(pts[-1])
        self.stroke(out, w)
        return out

    def open_smile(self, cx, cy, half, depth, teeth=True, tongue=False, top_curve=0.0):
        """D-shaped open smile: top edge (slightly curved up by top_curve), lower half ellipse"""
        n = 40
        top = [(cx - half + 2 * half * i / n, cy - top_curve * math.sin(math.pi * i / n) * -1) for i in range(n + 1)]
        bot = [(cx + half * math.cos(math.pi * i / n), cy + depth * math.sin(math.pi * i / n)) for i in range(n + 1)]
        shape = top + bot
        self.poly(shape)
        # round the corners
        r = 0.012
        for x, y in (top[0], top[-1]):
            self.ellipse(x, y, r, r)
        if tongue:
            self.masked(lambda d: d.ellipse([(cx - half * 0.55) * SS, (cy + depth * 0.45) * SS,
                                             (cx + half * 0.55) * SS, (cy + depth * 1.35) * SS], fill=255),
                        [(cx + 0.92 * (x - cx), cy + 0.88 * (y - cy)) for x, y in shape], TONGUE)
        if teeth:
            band = depth * 0.42
            clip = [(cx + 0.9 * (x - cx), cy + 0.86 * (y - cy) + 0.008) for x, y in shape]
            self.masked(lambda d: d.rectangle([0, (cy - 0.05) * SS, SS, (cy + band) * SS], fill=255), clip, WHITE)

    def teeth_clench(self, cx, cy, half, h, tilt=0.0):
        """effort: a wide rounded box of clenched teeth (outline, white fill, tooth lines)"""
        x0, x1, y0, y1 = cx - half, cx + half, cy - h / 2, cy + h / 2
        r = int(h * 0.45 * SS)
        self.d.rounded_rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], radius=r, fill=INK)
        i = 0.016
        self.d.rounded_rectangle([(x0 + i) * SS, (y0 + i) * SS, (x1 - i) * SS, (y1 - i) * SS],
                                 radius=max(1, r - int(i * SS)), fill=WHITE)
        self.stroke([(x0 + i, cy), (x1 - i, cy)], 0.010)
        for k in range(1, 6):
            x = x0 + (x1 - x0) * k / 6
            self.stroke([(x, y0 + i), (x, y1 - i)], 0.009)

    def spiral(self, cx, cy, r, turns=2.3, w=0.012, sgn=1):
        n = 90
        pts = [(cx + sgn * r * (i / n) * math.cos(2 * math.pi * turns * i / n),
                cy + r * (i / n) * math.sin(2 * math.pi * turns * i / n)) for i in range(n + 1)]
        self.stroke(pts, w)

    def cross(self, cx, cy, r, w=0.022):
        self.stroke([(cx - r, cy - r), (cx + r, cy + r)], w)
        self.stroke([(cx - r, cy + r), (cx + r, cy - r)], w)

    def save(self, path):
        # the features are drawn on a 1.4x smaller layout and zoomed about the face centre (0.5, 0.47), so
        # they fill the head's front like the classic face (eyes at ~0.36 / 0.64, mouth ~0.6 down)
        c, h = (0.5 * SS, FACE_CY * SS), FACE_HALF * SS
        self.im.crop((int(c[0] - h), int(c[1] - h), int(c[0] + h), int(c[1] + h))).resize(
            (512, 512), Image.LANCZOS).save(path)


EL, ER, EY = 0.40, 0.60, 0.405  # eye centres
MY = 0.555                      # mouth line


def f_smile(f):
    f.eye(EL, EY)
    f.eye(ER, EY)
    f.arc(0.5, 0.465, 0.125, 0.125, 32, 148)


def f_grin(f):
    f.eye(EL, EY - 0.005, ry=0.058)
    f.eye(ER, EY - 0.005, ry=0.058)
    f.open_smile(0.5, 0.53, 0.125, 0.10, teeth=True, top_curve=0.012)


def f_smirk(f):
    f.eye(EL, EY)
    f.eye(ER, EY, lid=(0.22, 0.0))
    f.brow(ER, 0.31, 0.055, tilt=0.01, arch=0.012)
    f.curve([(0.42, 0.575), (0.50, 0.585), (0.57, 0.57), (0.615, 0.53)])
    f.stroke([(0.605, 0.515), (0.632, 0.548)], 0.014)  # dimple


def f_confident(f):
    f.eye(EL, EY, ry=0.056)
    f.eye(ER, EY, ry=0.056)
    f.brow(EL, 0.318, 0.058, tilt=0.012, arch=0.0)
    f.brow(ER, 0.302, 0.058, tilt=-0.004, arch=0.02)
    f.curve([(0.40, 0.548), (0.46, 0.585), (0.54, 0.588), (0.605, 0.54)])


def f_cool(f):
    f.eye(EL, EY + 0.008, rx=0.034, ry=0.055, lid=(0.5, 0.0))
    f.eye(ER, EY + 0.008, rx=0.034, ry=0.055, lid=(0.5, 0.0))
    f.curve([(0.43, 0.572), (0.50, 0.582), (0.575, 0.565)], w=0.022)


def f_happy(f):
    f.arc(EL, EY + 0.025, 0.04, 0.04, 200, 340, w=0.022)
    f.arc(ER, EY + 0.025, 0.04, 0.04, 200, 340, w=0.022)
    f.open_smile(0.5, 0.515, 0.14, 0.125, teeth=False, tongue=True, top_curve=0.01)


def f_wink(f):
    f.eye(EL, EY)
    f.curve([(ER - 0.045, EY + 0.012), (ER, EY - 0.008), (ER + 0.045, EY + 0.012)], w=0.02)
    f.stroke([(ER + 0.04, EY + 0.006), (ER + 0.062, EY - 0.012)], 0.012)  # lash flick
    f.arc(0.5, 0.465, 0.12, 0.12, 30, 150)
    f.masked(lambda d: d.ellipse([0.53 * SS, 0.555 * SS, 0.6 * SS, 0.64 * SS], fill=255),
             [(0.5, 0.57), (0.7, 0.57), (0.7, 0.7), (0.5, 0.7)], TONGUE)


def f_determined(f):
    f.eye(EL, EY + 0.005, ry=0.052, lid=(0.18, 0.4))
    f.eye(ER, EY + 0.005, ry=0.052, lid=(0.18, 0.4))
    f.brow(EL, 0.318, 0.062, tilt=0.04, w=0.024)
    f.brow(ER, 0.318, 0.062, tilt=0.04, w=0.024)
    f.curve([(0.43, 0.59), (0.47, 0.578), (0.53, 0.578), (0.57, 0.59)], w=0.022)


def f_focused(f):
    f.eye(EL, EY + 0.01, ry=0.05, lid=(0.3, 0.2), under=0.12)
    f.eye(ER, EY + 0.01, ry=0.05, lid=(0.3, 0.2), under=0.12)
    f.brow(EL, 0.33, 0.06, tilt=0.018, w=0.022)
    f.brow(ER, 0.33, 0.06, tilt=0.018, w=0.022)
    f.stroke([(0.465, 0.58), (0.535, 0.58)], 0.02)


def f_stern(f):
    f.eye(EL, EY + 0.006, ry=0.05)
    f.eye(ER, EY + 0.006, ry=0.05)
    f.brow(EL, 0.325, 0.066, tilt=0.008, w=0.028)
    f.brow(ER, 0.325, 0.066, tilt=0.008, w=0.028)
    f.stroke([(0.43, 0.585), (0.57, 0.585)], 0.022)


def f_angry(f):
    f.eye(EL, EY + 0.012, ry=0.052, lid=(0.3, 0.9))
    f.eye(ER, EY + 0.012, ry=0.052, lid=(0.3, 0.9))
    f.brow(EL, 0.325, 0.066, tilt=0.07, w=0.026)
    f.brow(ER, 0.325, 0.066, tilt=0.07, w=0.026)
    f.arc(0.5, 0.64, 0.10, 0.07, 215, 325)


def f_grit(f):
    f.eye(EL, EY + 0.012, ry=0.048, lid=(0.3, 0.7), under=0.1)
    f.eye(ER, EY + 0.012, ry=0.048, lid=(0.3, 0.7), under=0.1)
    f.brow(EL, 0.322, 0.064, tilt=0.06, w=0.026)
    f.brow(ER, 0.322, 0.064, tilt=0.06, w=0.026)
    f.teeth_clench(0.5, 0.575, 0.11, 0.07)


def f_surprised(f):
    for x in (EL, ER):
        f.ellipse(x, EY, 0.042, 0.052)
        f.ellipse(x - 0.012, EY - 0.018, 0.01, 0.012, WHITE)
    f.brow(EL, 0.305, 0.055, tilt=-0.008, arch=0.022, w=0.018)
    f.brow(ER, 0.305, 0.055, tilt=-0.008, arch=0.022, w=0.018)
    f.ellipse(0.5, 0.59, 0.042, 0.052)


def f_tired(f):
    f.eye(EL, EY + 0.012, ry=0.05, lid=(0.55, -0.35))
    f.eye(ER, EY + 0.012, ry=0.05, lid=(0.55, -0.35))
    f.brow(EL, 0.33, 0.058, tilt=-0.03, w=0.018)
    f.brow(ER, 0.33, 0.058, tilt=-0.03, w=0.018)
    f.arc(EL, EY + 0.05, 0.03, 0.016, 20, 160, w=0.009)  # bags
    f.arc(ER, EY + 0.05, 0.03, 0.016, 20, 160, w=0.009)
    f.curve([(0.44, 0.595), (0.5, 0.582), (0.56, 0.597)], w=0.02)
    # a sweat drop on the brow
    f.masked(lambda d: d.ellipse([0.665 * SS, 0.285 * SS, 0.705 * SS, 0.335 * SS], fill=255),
             [(0, 0), (1, 0), (1, 1), (0, 1)], (24, 19, 17, 255))
    f.poly([(0.668, 0.302), (0.685, 0.255), (0.702, 0.302)])
    f.ellipse(0.679, 0.305, 0.006, 0.009, (250, 248, 244, 255))


def f_hurt(f):
    # squeezed eyes: chevrons pointing at the nose
    f.stroke([(EL - 0.04, EY - 0.03), (EL + 0.03, EY + 0.0), (EL - 0.04, EY + 0.03)], 0.022)
    f.stroke([(ER + 0.04, EY - 0.03), (ER - 0.03, EY + 0.0), (ER + 0.04, EY + 0.03)], 0.022)
    f.brow(EL, 0.31, 0.055, tilt=-0.035, w=0.02)
    f.brow(ER, 0.31, 0.055, tilt=-0.035, w=0.02)
    # grimace: clenched teeth pulled to one side
    f.teeth_clench(0.51, 0.585, 0.105, 0.065)


def f_dazed(f):
    f.spiral(EL, EY, 0.058, w=0.015, sgn=1)
    f.spiral(ER, EY, 0.058, w=0.015, sgn=-1)
    pts = [(0.42 + 0.16 * i / 30, 0.585 + 0.012 * math.sin(i / 30 * 3 * math.pi) + 0.012 * i / 30)
           for i in range(31)]
    f.stroke(pts, 0.02)


def f_ko(f):
    f.cross(EL, EY, 0.04, w=0.024)
    f.cross(ER, EY, 0.04, w=0.024)
    f.ellipse(0.5, 0.585, 0.05, 0.04)
    f.masked(lambda d: d.ellipse([0.47 * SS, 0.585 * SS, 0.53 * SS, 0.65 * SS], fill=255),
             [(0.4, 0.595), (0.6, 0.595), (0.6, 0.7), (0.4, 0.7)], TONGUE)


DRAW = {k: globals()["f_" + k] for k, _ in FACES}


def contact_sheet(paths, out, cols=6, cell=200, skin=(201, 146, 104)):
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 17)
    keys = list(paths)
    rows = (len(keys) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 28) + 44), (30, 31, 34))
    d = ImageDraw.Draw(sheet)
    d.text((12, 12), "Classic-style faces (tools/body/faces.py) - 512px decals on the head's front",
           fill=(235, 235, 235), font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18))
    for i, k in enumerate(keys):
        r, c = divmod(i, cols)
        x, y = c * cell, 44 + r * (cell + 28)
        tile = Image.new("RGBA", (cell - 12, cell - 12), (0, 0, 0, 0))
        ImageDraw.Draw(tile).rounded_rectangle([0, 0, cell - 13, cell - 13], radius=30, fill=skin + (255,))
        im = Image.open(paths[k]).resize((cell - 12, cell - 12), Image.LANCZOS)
        tile.alpha_composite(im)
        sheet.paste(tile, (x + 6, y + 6), tile)
        name = dict(FACES)[k] + (" *" if k in CREATOR else "")
        tw = d.textlength(name, font=font)
        d.text((x + cell / 2 - tw / 2, y + cell + 2), name, fill=(220, 220, 220), font=font)
    sheet.save(out)
    return out


# ---------------------------------------------------------------------------------------------- the Boxer pack
def _features(a, x0, x1, y0, y1):
    """the brow and the eye in one upper quarter of a face (alpha array, the box x0..x1, y0..y1): rows with ink
    split at the empty band between them; returns (brow rows, eye rows, alpha-weighted eye centre x, y)"""
    import numpy as np
    sub = a[y0:y1, x0:x1]
    rows = np.nonzero(sub.max(axis=1) > 128)[0]
    runs, start = [], rows[0]
    for r0, r1 in zip(rows[:-1], rows[1:]):
        if r1 - r0 > 1:
            runs.append((start, r0 + 1))
            start = r1
    runs.append((start, rows[-1] + 1))
    if len(runs) < 2:
        raise SystemExit("register_pack: brow and eye not separable in box %s" % ((x0, x1, y0, y1),))
    brow, eye = runs[0], runs[-1]
    e0, e1 = max(eye[0] - 2, 0), min(eye[1] + 2, sub.shape[0])  # (the antialiased rim)
    e = sub[e0:e1].astype(float)
    e[e < 5] = 0
    ys, xs = np.mgrid[e0:e1, 0:sub.shape[1]]
    w = e.sum()
    return brow, eye, x0 + (xs * e).sum() / w, y0 + (ys * e).sum() / w


def register_pack(src):
    """The pack's eyes sit at different heights and spacings (generated art: up to 42 px apart in a 1254 canvas),
    so swapping the four by mood would make the eyes jump. Each face's two upper quarters (brow + eye of a side,
    above the mouth) are moved by whole pixels so that side's eye centre lands on the reference face's; the mouth,
    the canvas, the alpha and every pixel's value are kept (a moved face is written as face_<key>_v2.png).
    Returns [(key, name, file, (dxL, dyL, dxR, dyR))]."""
    import numpy as np
    ims = {k: np.asarray(Image.open(os.path.join(src, f)).convert("RGBA")) for k, _, f in PACK}
    n = ims[PACK_REF].shape[0]
    for k, im in ims.items():
        if im.shape[:2] != (n, n):
            raise SystemExit("register_pack: %s is %s, the pack is square %d" % (k, im.shape, n))
    mid = n // 2

    def upper(a):
        # the upper face of one image: the rows above its mouth (the lowest run of ink rows, across the whole width)
        rows = np.nonzero(a.max(axis=1) > 128)[0]
        gaps = np.nonzero(np.diff(rows) > 1)[0]
        return int(rows[gaps[-1] + 1]) - 4

    boxes = {"L": (0, mid), "R": (mid, n)}
    rs = upper(ims[PACK_REF][..., 3])
    ref = {sd: _features(ims[PACK_REF][..., 3], bx[0], bx[1], 0, rs)[2:] for sd, bx in boxes.items()}
    out = []
    for k, name, f in PACK:
        im = ims[k]
        split = upper(im[..., 3])
        shift = []
        moved = im.copy()
        for sd, (x0, x1) in boxes.items():
            _, _, cx, cy = _features(im[..., 3], x0, x1, 0, split)
            dx, dy = int(round(ref[sd][0] - cx)), int(round(ref[sd][1] - cy))
            shift += [dx, dy]
            if dx or dy:
                # the brow + eye box (ink alpha >= 5, padded): the generator's stray alpha 1..4 specks elsewhere
                # in the canvas stay where they are
                q = im[0:split, x0:x1, 3]
                iy, ix = np.nonzero(q >= 5)
                bx0, bx1 = max(ix.min() - 6, 0), min(ix.max() + 7, x1 - x0)
                by0, by1 = max(iy.min() - 6, 0), min(iy.max() + 7, split)
                if bx0 + dx < 0 or bx1 + dx > x1 - x0 or by0 + dy < 0 or by1 + dy > split:
                    raise SystemExit("register_pack: %s %s would leave its quarter" % (k, sd))
                box = im[by0:by1, x0 + bx0:x0 + bx1].copy()
                moved[by0:by1, x0 + bx0:x0 + bx1] = 0
                dst_ = moved[by0 + dy:by1 + dy, x0 + bx0 + dx:x0 + bx1 + dx]
                keep = box[..., 3] > 0
                dst_[keep] = box[keep]
        fn = "face_%s%s.png" % (k, "_v2" if any(shift) else "")
        dst = os.path.join(OUTDIR, fn)
        if any(shift):
            Image.fromarray(moved, "RGBA").save(dst, optimize=True)
        else:
            import shutil
            shutil.copyfile(os.path.join(src, f), dst)  # the reference: the user's file, byte for byte
        # an older version of the same key is retired (its id stays in tools/body/uploaded.json)
        for old in ("face_%s.png" % k, "face_%s_v2.png" % k):
            if old != fn and os.path.isfile(os.path.join(OUTDIR, old)):
                os.remove(os.path.join(OUTDIR, old))
        out.append((k, name, fn, tuple(shift)))
    return out


def pack_entries():
    """the pack's faces.json entries from the files in out/faces (newest version of each key), then the faces drawn
    in its style by wcb_faces_draw.py (DRAWN: creator = a resting face, else a mood face only)"""
    out = []
    for k, name, _ in PACK:
        for fn in ("face_%s_v2.png" % k, "face_%s.png" % k):
            if os.path.isfile(os.path.join(OUTDIR, fn)):
                out.append({"key": k, "name": name, "file": fn, "creator": True})
                break
    from wcb_faces_draw import DRAWN
    for k, name, creator in DRAWN:
        fn = "face_%s.png" % k
        if os.path.isfile(os.path.join(OUTDIR, fn)):
            out.append({"key": k, "name": name, "file": fn, "creator": creator})
    return out


def write_json():
    with open(os.path.join(OUTDIR, "faces.json"), "w") as fh:
        json.dump({"faces": [{"key": k, "name": n, "file": "face_%s.png" % k, "creator": k in CREATOR}
                             for k, n in FACES] + pack_entries(),
                   "default": "smile", "expressions": EXPRESSIONS}, fh, indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default=os.path.join(SCRATCH, "faces_sheet.png"))
    ap.add_argument("--pack", default=None, metavar="DIR", help="the Boxer face pack's faces/ folder (PACK files)")
    ap.add_argument("--pack-only", action="store_true", help="only (re)register the pack and rewrite faces.json")
    a = ap.parse_args()
    os.makedirs(OUTDIR, exist_ok=True)
    if a.pack:
        for k, _, fn, sh in register_pack(a.pack):
            print("pack %-12s -> %-22s shift L (%+d, %+d) R (%+d, %+d)" % ((k, fn) + sh))
    if a.pack_only:
        write_json()
        print(len(pack_entries()), "pack faces ->", OUTDIR)
        return
    paths = {}
    for k, _ in FACES:
        f = Face()
        DRAW[k](f)
        paths[k] = os.path.join(OUTDIR, "face_%s.png" % k)
        f.save(paths[k])
    write_json()
    contact_sheet(paths, os.path.join(OUTDIR, "contact_sheet.png"))
    if a.sheet:
        os.makedirs(os.path.dirname(a.sheet), exist_ok=True)
        contact_sheet(paths, a.sheet)
    print(len(paths), "faces ->", OUTDIR)


if __name__ == "__main__":
    main()
