"""More drawn Boxer faces, in the style of the user's four (wcb_neutral / focused / smirk / grit).

    python3 tools/body/wcb_faces_draw.py [--sheet PATH] [--only key,key]

Writes tools/body/out/faces/face_wcb_<key>.png (1254 x 1254 RGBA, transparent) for every DRAWN face and rewrites
faces.json (faces.write_json, which lists DRAWN after the user's pack). Nothing here touches the user's four files.

The style, measured from the user's PNGs (tools/body/out/faces/face_wcb_*.png):
  * ink RGB ~(24, 25, 29) (+-2 per pixel), opaque alpha 252..253 (never 255), a 1-2 px antialiased rim
  * eyes: upright filled ovals 72 x 127 px, centres x 443 / 807, y 575 (the registration of wcb_neutral)
  * brows: one solid stroke ~30 px thick with round ends, ~166 px long, centre ~ (442 / 810, 437)
  * mouths: a ~30 px round-capped line / curve around x 626, y 840..860; teeth (grit): a rounded box with a ~19 px
    ink border, white (250, 247, 242) inside and a ~9 px ink line between the rows
  * every pixel of ink inside x 326..928 (= +-0.24 of the head width about its centre: the front's safe area that
    does not wrap round the classic head's sides) and y 390..925
"""
import argparse
import math
import os
import sys

import cairocffi as cairo
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "out", "faces")
N = 1254
INK = (24, 25, 29)
WHITE = (250, 247, 242)
ALPHA = 253
EL, ER, EY = 443, 807, 575       # eye centres (wcb_neutral)
ERX, ERY = 36, 63.5              # eye semi-axes
MX = 626                         # mouth centre x
BW = 30                          # brow / mouth stroke
SAFE_X = (326, 928)
SAFE_Y = (390, 925)

# key, display name, creator (True = a resting face players pick; False = a mood face only)
DRAWN = [
    ("wcb_confident", "Boxer Confident", True),
    ("wcb_grin", "Boxer Grin", True),
    ("wcb_cool", "Boxer Cool", True),
    ("wcb_wink", "Boxer Wink", True),
    ("wcb_stern", "Boxer Stern", True),
    ("wcb_determined", "Boxer Determined", True),
    ("wcb_toothy", "Boxer Toothy Grin", True),
    ("wcb_scarred", "Boxer Scarred", True),
    ("wcb_shout", "Boxer Shout", False),
    ("wcb_hurt", "Boxer Hurt", False),
    ("wcb_dazed", "Boxer Dazed", False),
    ("wcb_ko", "Boxer KO", False),
    ("wcb_tired", "Boxer Tired", False),
    ("wcb_surprised", "Boxer Surprised", False),
]


class Face:
    """two cairo layers: ink (black) and white (teeth), composited to one RGBA at save"""

    def __init__(self):
        self.ink = cairo.ImageSurface(cairo.FORMAT_A8, N, N)
        self.wht = cairo.ImageSurface(cairo.FORMAT_A8, N, N)
        self.ci = cairo.Context(self.ink)
        self.cw = cairo.Context(self.wht)
        for c in (self.ci, self.cw):
            c.set_antialias(cairo.ANTIALIAS_BEST)
            c.set_line_cap(cairo.LINE_CAP_ROUND)
            c.set_line_join(cairo.LINE_JOIN_ROUND)

    # ---------------------------------------------------------------- primitives
    def _ctx(self, white):
        return self.cw if white else self.ci

    def ellipse(self, cx, cy, rx, ry, rot=0.0, white=False, erase=False):
        c = self._ctx(white)
        c.save()
        if erase:
            c.set_operator(cairo.OPERATOR_CLEAR)
        c.translate(cx, cy)
        c.rotate(math.radians(rot))
        c.scale(rx, ry)
        c.arc(0, 0, 1, 0, 2 * math.pi)
        c.restore()
        c.save()
        if erase:
            c.set_operator(cairo.OPERATOR_CLEAR)
        c.fill()
        c.restore()

    def path(self, pts, closed=False, c=None):
        c = c or self.ci
        c.move_to(*pts[0])
        for p in pts[1:]:
            c.line_to(*p)
        if closed:
            c.close_path()

    def stroke(self, pts, w=BW, white=False, erase=False, smooth=True):
        c = self._ctx(white)
        P = catmull(pts) if smooth and len(pts) > 2 else pts
        c.save()
        if erase:
            c.set_operator(cairo.OPERATOR_CLEAR)
        c.set_line_width(w)
        self.path(P, c=c)
        c.stroke()
        c.restore()

    def tapered(self, pts, w0, w1, wmid=None):
        """a brush stroke along a smooth curve whose width goes w0 -> (wmid) -> w1, round ends"""
        P = catmull(pts, 80)
        n = len(P)
        wmid = (w0 + w1) / 2 if wmid is None else wmid
        W = []
        for i in range(n):
            t = i / (n - 1)
            W.append((1 - t) ** 2 * w0 + 2 * t * (1 - t) * wmid + t * t * w1)
        L, R = [], []
        for i in range(n):
            a = P[max(i - 1, 0)]
            b = P[min(i + 1, n - 1)]
            dx, dy = b[0] - a[0], b[1] - a[1]
            d = math.hypot(dx, dy) or 1
            nx, ny = -dy / d, dx / d
            h = W[i] / 2
            L.append((P[i][0] + nx * h, P[i][1] + ny * h))
            R.append((P[i][0] - nx * h, P[i][1] - ny * h))
        c = self.ci
        self.path(L + R[::-1], closed=True)
        c.fill()
        for (x, y), w in ((P[0], W[0]), (P[-1], W[-1])):
            c.arc(x, y, w / 2, 0, 2 * math.pi)
            c.fill()

    def polygon(self, pts, white=False, erase=False, soft=0):
        """a filled shape; soft > 0 also strokes its outline that wide (round joins: rounded corners)"""
        c = self._ctx(white)
        c.save()
        if erase:
            c.set_operator(cairo.OPERATOR_CLEAR)
        self.path(pts, closed=True, c=c)
        if soft:
            c.fill_preserve()
            c.set_line_width(soft)
            c.stroke()
        else:
            c.fill()
        c.restore()

    # ---------------------------------------------------------------- features
    def eye(self, cx, cy=EY, rx=ERX, ry=ERY, cut=None, under=None, lid=None):
        """an upright oval eye. cut = (y at the inner end, y at the outer end): everything above that line is cut
        off (a lid); under = the same from below (a squint). lid = stroke width of a lid line drawn along the cut"""
        if cut is None and under is None:
            self.ellipse(cx, cy, rx, ry)
            return
        side = 1 if cx > N / 2 else -1  # +1 = the viewer's right eye: its outer end is at +x
        c = self.ci
        c.save()
        x_in, x_out = cx - side * rx * 2, cx + side * rx * 2
        clip = []
        if cut:
            clip += [(x_in, cut[0]), (x_out, cut[1])]
        else:
            clip += [(x_in, cy - ry - 10), (x_out, cy - ry - 10)]
        if under:
            clip += [(x_out, under[1]), (x_in, under[0])]
        else:
            clip += [(x_out, cy + ry + 10), (x_in, cy + ry + 10)]
        self.path(clip, closed=True)
        c.clip()
        c.translate(cx, cy)
        c.scale(rx, ry)
        c.arc(0, 0, 1, 0, 2 * math.pi)
        c.fill()
        c.restore()
        if lid and cut:
            # the lid line, a little wider than the eye at that height
            def at(y_in, y_out, t):
                return (x_in + (x_out - x_in) * t, y_in + (y_out - y_in) * t)
            p0, p1 = at(cut[0], cut[1], 0.5 - 0.5 * 1.25 * 0.5), at(cut[0], cut[1], 0.5 + 0.5 * 1.25 * 0.5)
            self.stroke([p0, p1], w=lid, smooth=False)

    def brow(self, cx, y_in, y_out, arch=0.0, half=83, w=(31, 27), wmid=32, shift=0.0):
        """a brow centred on cx (+shift toward the nose), inner end at y_in, outer end at y_out, bowed up by arch"""
        side = 1 if cx > N / 2 else -1
        pts = []
        for i in range(5):
            t = i / 4  # 0 inner -> 1 outer
            x = cx - side * shift + side * (t - 0.5) * 2 * (half - w[0] / 2)
            y = y_in + (y_out - y_in) * t - arch * math.sin(math.pi * t)
            pts.append((x, y))
        self.tapered(pts, w[0], w[1], wmid)
        return pts

    def save(self, path):
        ink = np.ndarray((N, self.ink.get_stride()), np.uint8, self.ink.get_data())[:, :N].astype(float) / 255
        wht = np.ndarray((N, self.wht.get_stride()), np.uint8, self.wht.get_data())[:, :N].astype(float) / 255
        # white sits under the ink (the ink border and lines are drawn over the teeth)
        a = ink + wht * (1 - ink)
        rgb = np.zeros((N, N, 3))
        with np.errstate(invalid="ignore", divide="ignore"):
            for k in range(3):
                rgb[..., k] = np.where(a > 0, (INK[k] * ink + WHITE[k] * wht * (1 - ink)) / a, 0)
        rng = np.random.default_rng(len(os.path.basename(path)) * 7919)
        rgb += rng.integers(-2, 3, (N, N, 1)) * (wht[..., None] < 0.5)  # the pack's slight ink grain
        out = np.zeros((N, N, 4), np.uint8)
        out[..., :3] = np.clip(np.round(rgb), 0, 255)
        out[..., 3] = np.clip(np.round(a * ALPHA), 0, 255)
        out[out[..., 3] == 0] = 0
        ys, xs = np.nonzero(out[..., 3] > 0)
        bad = []
        if xs.min() < SAFE_X[0] or xs.max() > SAFE_X[1]:
            bad.append("x %d..%d" % (xs.min(), xs.max()))
        if ys.min() < SAFE_Y[0] or ys.max() > SAFE_Y[1]:
            bad.append("y %d..%d" % (ys.min(), ys.max()))
        if bad:
            raise SystemExit("%s: ink outside the safe area (%s)" % (os.path.basename(path), ", ".join(bad)))
        Image.fromarray(out, "RGBA").save(path, optimize=True)
        return (int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max()))


def catmull(pts, n=64):
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    seg = len(P) - 3
    per = max(2, n // seg)
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(per):
            t = k / per
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in range(2)))
    out.append(tuple(pts[-1]))
    return out


def neutral_brows(f, dy=0, arch=6):
    f.brow(EL, 442 + dy, 446 + dy, arch=arch)
    f.brow(ER, 442 + dy, 446 + dy, arch=arch)


def teeth_box(f, pts_outer, inset, line_y, line_w=9):
    """grit's teeth: an ink shape, the white inset inside it, one ink line between the rows"""
    f.polygon(pts_outer)
    inner = inset_poly(pts_outer, inset)
    f.polygon(inner, erase=True)
    f.polygon(inner, white=True)
    xs = [p[0] for p in inner]
    f.ci.save()
    f.path(inner, closed=True)
    f.ci.clip()
    f.ci.set_line_width(line_w)
    f.ci.move_to(min(xs) - 5, line_y)
    f.ci.line_to(max(xs) + 5, line_y)
    f.ci.stroke()
    f.ci.restore()


def inset_poly(P, d):
    """offsets a convex-ish closed polygon inward by d (miter; the shapes here are smooth)"""
    n = len(P)
    area = sum(P[i][0] * P[(i + 1) % n][1] - P[(i + 1) % n][0] * P[i][1] for i in range(n))
    s = 1 if area > 0 else -1
    out = []
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        def nrm(p, q):
            dx, dy = q[0] - p[0], q[1] - p[1]
            l = math.hypot(dx, dy) or 1
            return (-dy / l * s, dx / l * s)
        n1, n2 = nrm(a, b), nrm(b, c)
        m = (n1[0] + n2[0], n1[1] + n2[1])
        ml = math.hypot(*m) or 1
        m = (m[0] / ml, m[1] / ml)
        cosh = max(0.3, m[0] * n1[0] + m[1] * n1[1])
        out.append((b[0] + m[0] * d / cosh, b[1] + m[1] * d / cosh))
    return out


def rounded_box(x0, y0, x1, y1, r, n=10):
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def d_shape(x0, x1, y_top, depth, top_bow=0.0, n=48):
    """an open smile: a top edge (bowed down at the middle by top_bow) and a half-ellipse below (depth < 0: above,
    an open frown)"""
    cx, half = (x0 + x1) / 2, (x1 - x0) / 2
    top = [(x0 + (x1 - x0) * i / n, y_top + top_bow * math.sin(math.pi * i / n)) for i in range(n + 1)]
    bot = [(cx + half * math.cos(math.pi * i / n), y_top + depth * math.sin(math.pi * i / n)) for i in range(1, n)]
    return top + bot


# ------------------------------------------------------------------------------------------------ the faces
def f_confident(f):
    f.brow(EL, 446, 448, arch=4)                    # level
    f.brow(ER, 436, 420, arch=14)                   # the raised one
    f.eye(EL)
    f.eye(ER)
    f.stroke([(548, 836), (590, 858), (646, 861), (694, 843), (716, 822)])  # small closed smile, up on the right


def f_grin(f):
    neutral_brows(f, dy=-6, arch=10)
    f.eye(EL)
    f.eye(ER)
    f.polygon(d_shape(522, 730, 814, 84, top_bow=12), soft=22)


def f_cool(f):
    f.brow(EL, 456, 452, arch=2)
    f.brow(ER, 456, 452, arch=2)
    f.eye(EL, cut=(566, 566), lid=28)
    f.eye(ER, cut=(566, 566), lid=28)
    f.stroke([(566, 852), (626, 860), (682, 851), (712, 834)])


def f_wink(f):
    f.brow(EL, 432, 428, arch=12)
    f.brow(ER, 460, 452, arch=4)                    # pulled down over the shut eye
    f.eye(EL)
    f.stroke([(756, 592), (807, 564), (858, 592)], w=30)  # the shut eye (a closed lid arc)
    f.stroke([(548, 832), (600, 862), (660, 862), (712, 830)])


def f_stern(f):
    f.tapered([(524, 470), (450, 462), (362, 458)], 38, 32, 38)  # heavy, flat, low
    f.tapered([(726, 470), (800, 462), (888, 458)], 38, 32, 38)
    f.eye(EL, cut=(520, 524))
    f.eye(ER, cut=(520, 524))
    f.stroke([(546, 858), (706, 858)], smooth=False)


def f_determined(f):
    f.brow(EL, 486, 428, arch=4, half=86)
    f.brow(ER, 486, 428, arch=4, half=86)
    f.eye(EL, cut=(548, 528))
    f.eye(ER, cut=(548, 528))
    f.stroke([(566, 862), (626, 856), (686, 862)], w=28)  # a short tight line


def f_toothy(f):
    neutral_brows(f, dy=-8, arch=12)
    f.eye(EL)
    f.eye(ER)
    shape = d_shape(506, 746, 800, 104, top_bow=10)
    teeth_box(f, shape, 19, 846)


def f_scarred(f):
    neutral_brows(f)
    f.eye(EL)
    f.eye(ER)
    f.stroke([(537, 855), (716, 855)], smooth=False)
    # a scar through the right brow: a clean gap with a thin slash in it
    a, b = (846, 402), (818, 486)
    f.stroke([a, b], w=40, erase=True, smooth=False)
    f.stroke([(841, 408), (823, 480)], w=12, smooth=False)


def f_shout(f):
    f.brow(EL, 500, 420, arch=-4, half=84)
    f.brow(ER, 500, 420, arch=-4, half=84)
    f.eye(EL, cut=(560, 528))
    f.eye(ER, cut=(560, 528))
    # a wide open roar: a rounded box, top teeth showing
    outer = rounded_box(532, 784, 720, 918, 56)
    f.polygon(outer)
    inner = inset_poly(outer, 19)
    f.ci.save()
    f.path(inner, closed=True)
    f.ci.clip()
    f.ci.set_operator(cairo.OPERATOR_CLEAR)
    f.ci.rectangle(0, 0, N, 826)
    f.ci.fill()
    f.ci.restore()
    f.cw.save()
    f.path(inner, closed=True, c=f.cw)
    f.cw.clip()
    f.cw.rectangle(0, 0, N, 826)
    f.cw.fill()
    f.cw.restore()


def f_hurt(f):
    f.brow(EL, 430, 458, arch=6)                    # worried: inner ends up
    f.brow(ER, 430, 458, arch=6)
    # squeezed shut: > <
    f.stroke([(406, 538), (478, 575), (406, 612)], w=30, smooth=False)
    f.stroke([(844, 538), (772, 575), (844, 612)], w=30, smooth=False)
    # the wince: clenched teeth pulled into a lopsided box
    outer = rounded_box(540, 808, 714, 892, 36)
    outer = [(x, y + (x - 627) * -0.12) for x, y in outer]
    teeth_box(f, outer, 18, 850, 9)


def f_dazed(f):
    f.brow(EL, 432, 436, arch=10)
    f.brow(ER, 464, 450, arch=2)                    # uneven
    for cx, sg in ((EL, 1), (ER, -1)):
        pts = []
        n = 140
        for i in range(n + 1):
            t = i / n
            r = 8 + 52 * t
            a = sg * 2 * math.pi * 1.9 * t
            pts.append((cx + r * math.cos(a), EY + r * 1.1 * math.sin(a)))
        f.stroke(pts, w=20, smooth=False)
    pts = [(548 + 160 * i / 40, 852 + 12 * math.sin(i / 40 * 3 * math.pi) + 10 * (i / 40 - 0.5)) for i in range(41)]
    f.stroke(pts, w=26, smooth=False)


def f_ko(f):
    f.brow(EL, 426, 446, arch=8)
    f.brow(ER, 426, 446, arch=8)
    for cx in (EL, ER):
        r = 42
        f.stroke([(cx - r, EY - r), (cx + r, EY + r)], w=30, smooth=False)
        f.stroke([(cx - r, EY + r), (cx + r, EY - r)], w=30, smooth=False)
    # slack open mouth: an upside-down D (a frown, open)
    shape = d_shape(560, 692, 880, -64, top_bow=-8)
    f.polygon(shape, soft=22)


def f_tired(f):
    f.brow(EL, 438, 466, arch=4)                    # drooping
    f.brow(ER, 438, 466, arch=4)
    f.eye(EL, cut=(572, 590), lid=28)               # heavy lids, outer ends lower
    f.eye(ER, cut=(572, 590), lid=28)
    # panting: a small open mouth
    f.ellipse(MX, 856, 52, 38)


def f_surprised(f):
    f.brow(EL, 426, 432, arch=16)
    f.brow(ER, 426, 432, arch=16)
    f.eye(EL, rx=44, ry=64)
    f.eye(ER, rx=44, ry=64)
    f.ellipse(MX, 856, 32, 42)


DRAW = {k: globals()["f_" + k[4:]] for k, _, _ in DRAWN}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None)
    ap.add_argument("--no-json", action="store_true")
    a = ap.parse_args()
    only = set(a.only.split(",")) if a.only else None
    for k, name, _ in DRAWN:
        if only and k not in only:
            continue
        f = Face()
        DRAW[k](f)
        bb = f.save(os.path.join(OUTDIR, "face_%s.png" % k))
        print("%-16s ink x %d..%d  y %d..%d" % ((k,) + bb))
    if not a.no_json:
        sys.path.insert(0, HERE)
        import faces
        faces.write_json()
        print("faces.json rewritten")


if __name__ == "__main__":
    main()
