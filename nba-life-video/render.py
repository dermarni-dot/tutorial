"""Builds the full animated video: TTS narration, music, cartoon animation, subtitles.

Usage: python3 render.py [out_dir]
Requires: espeak-ng + mbrola-us2, ffmpeg, Pillow, numpy.
"""
import inspect
import math
import os
import random
import subprocess
import sys
import textwrap
import wave
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from story import CHANNEL, SCENES, TITLE

W, H = 1280, 720
FPS = 30
SS = 2  # supersampling: the world is drawn at 2x and scaled down for smooth edges and sub-pixel motion
SR = 44100
GROUND = 545
VOICE = "mb-us2"
SPEED = int(os.environ.get("TTS_SPEED", "165"))
LEAD_IN, LINE_GAP, TAIL = 1.2, 0.45, 0.8

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "build")
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_R = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
_fonts = {}


def _sc(v):
    if isinstance(v, (list, tuple)):
        return [_sc(i) for i in v]
    return v * SS


_big_fonts = {}


class SDraw:
    """ImageDraw wrapper that takes 1280x720 coordinates and draws them on the 2x canvas."""

    def __init__(self, img):
        self.d = ImageDraw.Draw(img, "RGBA")

    @staticmethod
    def _kw(kw, need_width=False):
        if "width" in kw:
            kw["width"] = max(1, int(round(kw["width"] * SS)))
        elif need_width or kw.get("outline") is not None:
            kw["width"] = SS
        return kw

    def line(self, xy, **kw):
        self.d.line(_sc(xy), **self._kw(kw, True))

    def ellipse(self, xy, **kw):
        self.d.ellipse(_sc(xy), **self._kw(kw))

    def rectangle(self, xy, **kw):
        self.d.rectangle(_sc(xy), **self._kw(kw))

    def polygon(self, xy, **kw):
        self.d.polygon([tuple(p) for p in _sc([tuple(p) for p in xy])], **self._kw(kw))

    def rounded_rectangle(self, xy, radius=0, **kw):
        self.d.rounded_rectangle(_sc(xy), radius * SS, **self._kw(kw))

    def arc(self, xy, start, end, **kw):
        self.d.arc(_sc(xy), start, end, **self._kw(kw, True))

    def chord(self, xy, start, end, **kw):
        self.d.chord(_sc(xy), start, end, **self._kw(kw))

    def text(self, xy, text, font=None, **kw):
        key = (font.path, font.size)
        if key not in _big_fonts:
            _big_fonts[key] = ImageFont.truetype(font.path, font.size * SS)
        if "stroke_width" in kw:
            kw["stroke_width"] = kw["stroke_width"] * SS
        self.d.text(_sc(xy), text, font=_big_fonts[key], **kw)


def font(size, bold=True):
    key = (size, bold)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT_B if bold else FONT_R, size)
    return _fonts[key]


INK = (45, 38, 38)
SKIN = (196, 142, 104)
HAIR = (70, 45, 30)
NAVY = (48, 82, 165)
ORANGE = (245, 130, 32)
WHITE = (245, 245, 245)
BALL = (226, 110, 30)

# Outfits: (shirt, shorts, number color, number or None)
OUTFITS = {
    "kid": ((215, 80, 70), (70, 80, 120), WHITE, "23"),
    "hs": ((245, 245, 245), (245, 245, 245), (48, 82, 165), "12"),
    "college": ((165, 50, 60), (165, 50, 60), (245, 205, 90), "11"),
    "comets": (NAVY, NAVY, ORANGE, "0"),
    "suit": ((25, 30, 60), (25, 30, 60), None, None),
    "agent": ((110, 110, 120), (110, 110, 120), None, None),
    "mom": ((165, 135, 200), (60, 75, 120), None, None),
    "hoodie": ((90, 90, 100), (50, 60, 90), None, None),
    "gown": ((170, 200, 220), (170, 200, 220), None, None),
    "train": ((110, 115, 125), (70, 75, 85), ORANGE, "0"),
}

# Per-scene look: outfit, scale, hoop present, extras
SCENE_LOOK = [
    ("comets", 1.0), ("kid", 0.72), ("kid", 0.8), ("hs", 1.0), ("college", 1.0),
    ("suit", 1.0), ("comets", 1.0), ("comets", 1.0), ("hoodie", 1.0), ("train", 1.0),
    ("hoodie", 1.0), ("hoodie", 1.0), ("gown", 1.0), ("train", 1.0), ("comets", 1.0),
    ("train", 1.0), ("suit", 1.0), ("hoodie", 1.0),
]
HOOP_BGS = {"driveway", "gym", "arena", "weights", "intro"}
RIM = (1060, 250)  # rim front-center


def lerp(a, b, t):
    return a + (b - a) * t


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def tri(t, period):
    """Triangle wave 0..1..0"""
    p = (t / period) % 1.0
    return 2 * p if p < 0.5 else 2 - 2 * p


# --------------------------------------------------------------------- drawing

def draw_ball(d, x, y, r=13):
    d.ellipse([x - r, y - r, x + r, y + r], fill=BALL, outline=INK, width=3)
    d.line([x - r, y, x + r, y], fill=(60, 30, 10), width=2)
    d.arc([x - r * 0.5, y - r, x + r * 1.5, y + r], 120, 240, fill=(60, 30, 10), width=2)
    d.arc([x - r * 1.5, y - r, x + r * 0.5, y + r], 300, 60, fill=(60, 30, 10), width=2)


def draw_hoop(d, net_swish=0.0):
    rx, ry = RIM
    d.rectangle([rx + 44, ry - 62, rx + 58, GROUND], fill=(90, 90, 100), outline=INK, width=2)  # pole
    d.rectangle([rx + 32, ry - 56, rx + 46, ry - 44], fill=(90, 90, 100), outline=INK, width=2)  # arm
    d.rectangle([rx + 30, GROUND - 6, rx + 72, GROUND + 4], fill=(70, 70, 80), outline=INK, width=2)  # base
    d.rectangle([rx + 20, ry - 105, rx + 34, ry + 20], fill=WHITE, outline=(40, 40, 40), width=3)
    d.rectangle([rx + 20, ry - 60, rx + 34, ry - 10], outline=(220, 40, 40), width=3)
    sway = math.sin(net_swish * 20) * 6 * net_swish
    for i in range(6):
        x0 = rx - 30 + i * 12
        d.line([x0, ry, rx - 20 + i * 8 + sway, ry + 42], fill=WHITE, width=2)
    d.line([rx - 20 + sway, ry + 42, rx + 20 + sway, ry + 42], fill=WHITE, width=2)
    d.line([rx - 32, ry, rx + 22, ry], fill=(230, 70, 20), width=6)


def limb(p, a, L, f):
    r = math.radians(a)
    return (p[0] + f * L * math.sin(r), p[1] + L * math.cos(r))


def chain(d, pts, widths, color, ink=True):
    """Two-segment limb: thin ink outline pass first, then colour, so joints stay seamless."""
    passes = ((INK, 4), (color, 0)) if ink else ((color, 0),)
    for c, extra in passes:
        for i in range(len(pts) - 1):
            w = widths[i] + extra
            d.line([pts[i], pts[i + 1]], fill=c, width=int(w))
            for p in (pts[i], pts[i + 1]):
                r = w / 2
                d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=c)


def seg(d, a, b, w, color):
    chain(d, [a, b], [w], color)


def shoe(d, a, s, f):
    box = [a[0] - 8 * s, a[1] - 5 * s, a[0] + 19 * s, a[1] + 8 * s] if f > 0 else \
          [a[0] - 19 * s, a[1] - 5 * s, a[0] + 8 * s, a[1] + 8 * s]
    d.rounded_rectangle(box, 6 * s, fill=(250, 250, 250), outline=INK, width=2)
    d.line([box[0] + 2, box[3] - 3 * s, box[2] - 2, box[3] - 3 * s], fill=(210, 70, 70), width=max(1, int(2 * s)))


def hair_shape(d, hx, hy, r, s, f, color):
    """Fluffy spiky hair like a storybook illustration."""
    pts = []
    n = 13
    for i in range(n + 1):
        ang = math.radians(165 + 210 * i / n)
        rr = r * (1.18 if i % 2 else 1.02)
        pts.append((hx + rr * math.cos(ang) - f * 2 * s, hy - 4 * s + rr * math.sin(ang) * 0.95))
    pts += [(hx + r * 0.95, hy - r * 0.05), (hx + r * 0.45, hy - r * 0.42), (hx - r * 0.1, hy - r * 0.28),
            (hx - r * 0.55, hy - r * 0.45), (hx - r * 0.95, hy - r * 0.05)]
    d.polygon(pts, fill=color, outline=INK, width=2)


POSE_DEFAULT = dict(fu=15, ff=35, bu=-10, bf=-5, ft=5, fs=0, bt=-5, bs=0)
TWEEN = None  # set by render_scene while blending one action into the next
TWEEN_TIME = 0.7


def person(d, *args, **kwargs):
    """Draws a person; while TWEEN is active the first (main) person is blended between two actions."""
    global TWEEN
    tw = TWEEN
    if tw is None or not tw["active"]:
        return draw_person(d, *args, **kwargs)
    tw["active"] = False
    p = inspect.signature(draw_person).bind(d, *args, **kwargs)
    p.apply_defaults()
    p = dict(p.arguments)
    pose = dict(POSE_DEFAULT)
    pose.update(p["pose"] or {})
    p["pose"] = pose
    if tw["mode"] == "record":
        tw["rec"] = p
        return draw_person(**p)
    a, k = tw["rec"], tw["k"]
    if a is not None:
        for key in ("x", "hip_y", "head_drop"):
            p[key] = lerp(a[key], p[key], k)
        p["pose"] = {n: lerp(a["pose"][n], pose[n], k) for n in pose}
        if k < 0.5:
            p["facing"] = a["facing"]
    return draw_person(**p)


def draw_person(d, x, hip_y, s=1.0, outfit="comets", pose=None, facing=1, mouth=0.0,
           mood="happy", eyes_closed=False, head_drop=0.0, skin=SKIN, hair=HAIR, long_hair=False):
    """Storybook-style cartoon person. Angles: 0 = straight down, positive = toward facing."""
    p = dict(fu=15, ff=35, bu=-10, bf=-5, ft=5, fs=0, bt=-5, bs=0)
    if pose:
        p.update(pose)
    shirt, shorts, numc, num = OUTFITS[outfit]
    f = facing
    hip = (x, hip_y)
    sh = (x, hip_y - 68 * s)
    lw = 17 * s
    long_sleeves = outfit in ("suit", "agent", "hoodie", "gown", "mom")
    long_pants = outfit not in ("kid", "hs", "college", "comets", "train")
    k = limb(hip, p["bt"], 48 * s, f); a = limb(k, p["bs"], 46 * s, f)
    e = limb((x - f * 15 * s, sh[1] + 4 * s), p["bu"], 35 * s, f); h_back = limb(e, p["bf"], 33 * s, f)
    k2 = limb(hip, p["ft"], 48 * s, f); a2 = limb(k2, p["fs"], 46 * s, f)
    e2 = limb((x + f * 15 * s, sh[1] + 4 * s), p["fu"], 35 * s, f); hand = limb(e2, p["ff"], 33 * s, f)
    lift = max(0.0, GROUND - max(a[1], a2[1]) - 6 * s)
    sw = 46 * s * max(0.35, 1 - lift / 260)
    d.ellipse([x - sw, GROUND - 5 * s, x + sw, GROUND + 7 * s], fill=(60, 40, 30, 45))
    sleeve = shirt if long_sleeves else skin

    def leg(hp, kn, an):
        chain(d, [hp, kn, an], [lw, lw * 0.9], shorts if long_pants else skin)
        if not long_pants:
            mid = (lerp(hp[0], kn[0], 0.85), lerp(hp[1], kn[1], 0.85))
            chain(d, [hp, mid], [lw * 1.55], shorts)
            sock = (lerp(kn[0], an[0], 0.72), lerp(kn[1], an[1], 0.72))
            chain(d, [sock, an], [lw * 0.85], (250, 250, 250))

    def arm(shp, el, hd):
        chain(d, [shp, el, hd], [lw * 0.85, lw * 0.75], sleeve)
        d.ellipse([hd[0] - 7 * s, hd[1] - 7 * s, hd[0] + 7 * s, hd[1] + 7 * s], fill=skin, outline=INK, width=2)

    leg(hip, k, a); shoe(d, a, s, f)
    arm((x - f * 15 * s, sh[1] + 4 * s), e, h_back)
    leg(hip, k2, a2); shoe(d, a2, s, f)
    # torso
    d.rounded_rectangle([x - 25 * s, hip_y - 12 * s, x + 25 * s, hip_y + 18 * s], 7 * s, fill=shorts, outline=INK, width=2)
    top = sh[1] - 6 * s
    body = [(x - 27 * s, top + 4 * s), (x - 11 * s, top), (x + 11 * s, top), (x + 27 * s, top + 4 * s),
            (x + 28 * s, hip_y + 2 * s), (x - 28 * s, hip_y + 2 * s)]
    d.polygon(body, fill=shirt, outline=INK, width=2)
    bx0 = x - f * 28 * s
    d.polygon([(bx0, top + 4 * s), (bx0 + f * 10 * s, top + 2 * s), (bx0 + f * 8 * s, hip_y), (bx0, hip_y)], fill=(0, 0, 0, 35))
    if not long_sleeves:
        trim = numc or WHITE
        d.polygon([(x - 9 * s, top), (x + 9 * s, top), (x, top + 14 * s)], fill=skin, outline=INK, width=2)
        d.line([(x - 9 * s, top), (x, top + 14 * s), (x + 9 * s, top)], fill=trim, width=max(2, int(3 * s)))
        for sd in (-1, 1):
            d.arc([x + sd * 27 * s - 9 * s, top + 2 * s, x + sd * 23 * s + 9 * s, top + 30 * s],
                  90 if sd > 0 else -90, 270 if sd > 0 else 90, fill=trim, width=max(2, int(3 * s)))
        d.line([x - 25 * s, hip_y - 4 * s, x - 23 * s, hip_y + 16 * s], fill=trim, width=max(2, int(3 * s)))
        d.line([x + 25 * s, hip_y - 4 * s, x + 23 * s, hip_y + 16 * s], fill=trim, width=max(2, int(3 * s)))
    if outfit in ("suit", "agent"):
        d.polygon([(x - 8 * s, top), (x + 8 * s, top), (x, top + 30 * s)], fill=WHITE, outline=INK, width=1)
        d.polygon([(x - 3 * s, top + 4 * s), (x + 3 * s, top + 4 * s), (x + 4 * s, top + 24 * s), (x, top + 30 * s),
                   (x - 4 * s, top + 24 * s)], fill=(200, 60, 60), outline=INK)
    if outfit == "hoodie":
        d.arc([x - 14 * s, top - 6 * s, x + 14 * s, top + 14 * s], 0, 180, fill=INK, width=2)
    if num:
        d.text((x, top + 34 * s), num, font=font(max(10, int(26 * s))), fill=numc, anchor="mm",
               stroke_width=max(1, int(2 * s)), stroke_fill=INK if numc != WHITE else (80, 80, 90))
    arm((x + f * 15 * s, sh[1] + 4 * s), e2, hand)
    # head
    hx = x + f * head_drop * 8 * s
    hy = sh[1] - 31 * s + head_drop * 10 * s
    r = 26 * s
    if long_hair:
        d.ellipse([hx - r * 1.12, hy - r * 1.1, hx + r * 1.12, hy + r * 0.6], fill=hair, outline=INK, width=2)
        for sd in (-1, 1):
            d.rounded_rectangle([hx + sd * r * 0.62 - r * 0.5, hy - r * 0.2, hx + sd * r * 0.62 + r * 0.5, sh[1] + 20 * s],
                                12 * s, fill=hair, outline=INK, width=2)
    d.rectangle([x - 7 * s, sh[1] - 16 * s, x + 7 * s, sh[1] - 2 * s], fill=skin, outline=INK, width=2)
    d.ellipse([hx - f * r - 5 * s, hy - 2 * s, hx - f * r + 7 * s, hy + 12 * s], fill=skin, outline=INK, width=2)
    d.chord([hx - r, hy - r, hx + r, hy + r * 1.02], 0, 360, fill=skin, outline=INK, width=2)
    if long_hair:
        d.chord([hx - r * 1.05, hy - r * 1.12, hx + r * 1.05, hy + r * 0.35], 180, 360, fill=hair, outline=INK, width=2)
        d.chord([hx - r * 0.9, hy - r * 0.9, hx + r * 0.3, hy + r * 0.1], 180, 300, fill=hair)
    else:
        hair_shape(d, hx, hy, r, s, f, hair)
    hl = tuple(min(255, c + 45) for c in hair)
    d.arc([hx - r * 0.7, hy - r * 1.0, hx + r * 0.5, hy - r * 0.2], 200, 260, fill=hl, width=max(2, int(3 * s)))
    fs_ = s * 0.82  # facial features scale with the head
    ex = hx + f * 8 * fs_
    ey = hy + 3 * fs_ + head_drop * 2 * fs_
    # cheeks
    for ox in (-15 * fs_, 15 * fs_):
        d.ellipse([ex + ox - 6 * fs_, ey + 9 * fs_, ex + ox + 6 * fs_, ey + 15 * fs_], fill=(235, 120, 110, 70))
    for ox in (-10 * fs_, 10 * fs_):
        cx = ex + ox
        if eyes_closed:
            d.arc([cx - 5 * fs_, ey - 3 * fs_, cx + 5 * fs_, ey + 5 * fs_], 20, 160, fill=INK, width=max(2, int(2 * fs_)))
        else:
            d.ellipse([cx - 3.6 * fs_, ey - 5.5 * fs_, cx + 3.6 * fs_, ey + 5.5 * fs_], fill=INK)
            d.ellipse([cx - 2 * fs_, ey - 4.2 * fs_, cx + 0.2 * fs_, ey - 1.8 * fs_], fill=WHITE)
        # brows: sad raises the inner end (the end nearer the middle of the face)
        y_l = y_r = ey - 11 * fs_
        if mood == "sad":
            if ox < 0:
                y_r -= 3.5 * fs_
            else:
                y_l -= 3.5 * fs_
        d.line([cx - 5 * fs_, y_l, cx + 5 * fs_, y_r], fill=INK, width=max(2, int(2 * fs_)))
    nx, ny = ex + f * 3 * fs_, ey + 8 * fs_
    d.arc([nx - 3 * fs_, ny, nx + 3 * fs_, ny + 5 * fs_], 300 if f > 0 else 60, 120 if f > 0 else 240,
          fill=INK, width=max(1, int(2 * fs_)))
    mx, my = ex + f * 2 * fs_, hy + 24 * fs_
    if mouth > 0.12:
        mh = (5 + 7 * min(1.0, mouth)) * fs_
        mw = (7 + 2 * min(1.0, mouth)) * fs_
        box = [mx - mw, my - mh * 0.45, mx + mw, my + mh * 0.55]
        d.chord([box[0], box[1] - mh * 0.55, box[2], box[3]], 0, 180, fill=(120, 40, 50), outline=INK, width=2)
        d.chord([mx - mw * 0.55, my + mh * 0.05, mx + mw * 0.55, my + mh * 0.5], 180, 360, fill=(230, 120, 120))
        d.line([box[0] + 2, box[1] + 1, box[2] - 2, box[1] + 1], fill=INK, width=2)
    elif mood == "sad":
        d.arc([mx - 6 * fs_, my - 1 * fs_, mx + 6 * fs_, my + 7 * fs_], 200, 340, fill=INK, width=max(2, int(2 * fs_)))
    else:
        d.arc([mx - 7 * fs_, my - 7 * fs_, mx + 7 * fs_, my + 3 * fs_], 25, 155, fill=INK, width=max(2, int(2 * fs_)))
    return dict(hand=hand, back_hand=h_back, head=(hx, hy), sh=sh)


def sit_hip(s):
    return GROUND - 56 * s


def chair(d, cx, s, facing=1, color=(150, 100, 65), back_h=75):
    """Chair under a seated person at cx (feet on the floor, seat under the hips)."""
    f = facing
    seat = sit_hip(s) + 16 * s
    x0, x1 = sorted((cx - f * 30 * s, cx + f * 34 * s))
    bx = cx - f * 30 * s
    d.rectangle([min(bx, bx - f * 10 * s), seat - back_h * s, max(bx, bx - f * 10 * s), seat], fill=color, outline=INK, width=2)
    for lx in (x0 + 3 * s, x1 - 9 * s):
        d.rectangle([lx, seat, lx + 6 * s, GROUND], fill=color, outline=INK, width=2)
    d.rounded_rectangle([x0, seat, x1, seat + 9 * s], 3, fill=color, outline=INK, width=2)


def plane_seat(d, cx, s=1.0):
    seat = sit_hip(s) + 16 * s
    c = (120, 70, 40)
    d.rectangle([cx - 10 * s, seat + 18 * s, cx + 10 * s, GROUND], fill=(70, 70, 80), outline=INK, width=2)
    d.rounded_rectangle([cx - 62 * s, seat - 150 * s, cx - 18 * s, seat + 10 * s], 16, fill=c, outline=INK, width=2)
    d.rounded_rectangle([cx - 62 * s, seat - 4 * s, cx + 44 * s, seat + 22 * s], 10, fill=c, outline=INK, width=2)
    d.rounded_rectangle([cx - 58 * s, seat - 150 * s, cx - 22 * s, seat - 125 * s], 8, fill=WHITE, outline=INK, width=1)


def stand_hip(s):
    return GROUND - 96 * s


# ----------------------------------------------------------------- backgrounds

def sky(d, top, bot, y1=GROUND):
    for y in range(0, y1, 4):
        t = y / y1
        c = tuple(int(lerp(top[i], bot[i], t)) for i in range(3))
        d.rectangle([0, y, W, y + 4], fill=c)


def bg_image(bg, idx):
    img = Image.new("RGB", (W * SS, H * SS), (0, 0, 0))
    d = SDraw(img)
    rnd = random.Random(idx * 7 + 3)
    night = idx in (17,)
    if bg == "driveway":
        if night:
            sky(d, (20, 25, 60), (230, 120, 80))
        else:
            sky(d, (110, 170, 240), (200, 230, 255))
            d.ellipse([90, 60, 170, 140], fill=(255, 225, 90))
        for i in range(5):
            cx = rnd.randint(200, 1200); cy = rnd.randint(40, 160)
            for j in range(3):
                d.ellipse([cx + j * 30 - 40, cy - 20, cx + j * 30 + 30, cy + 25], fill=(255, 255, 255) if not night else (90, 80, 120))
        d.rectangle([0, GROUND - 10, W, H], fill=(90, 160, 70))
        d.polygon([(250, GROUND + 10), (1280, GROUND + 10), (1280, H), (100, H)], fill=(150, 150, 150))
        for i in range(8):
            x = rnd.randint(300, 1200)
            d.line([x, GROUND + 20 + rnd.randint(0, 100), x + 40, GROUND + 40 + rnd.randint(0, 100)], fill=(110, 110, 110), width=2)
        d.rectangle([780, 150, 1280, GROUND + 10], fill=(90, 140, 200))  # house
        d.polygon([(760, 150), (1030, 40), (1300, 150)], fill=(120, 60, 50))
        d.rectangle([900, 300, 1220, GROUND + 10], fill=(220, 220, 225))  # garage door
        for y in range(320, GROUND, 40):
            d.line([900, y, 1220, y], fill=(180, 180, 190), width=2)
        d.rectangle([800, 220, 870, 300], fill=(250, 230, 150) if night else (180, 210, 240), outline=WHITE, width=4)
        lamp = (120, 120, 120)
        d.rectangle([60, 180, 70, GROUND], fill=lamp)
        d.rectangle([60, 180, 130, 190], fill=lamp)
        d.ellipse([115, 185, 145, 205], fill=(255, 240, 150) if night else (200, 200, 200))
        if night:
            d.polygon([(130, 200), (60, GROUND), (210, GROUND)], fill=(150, 130, 90))
    elif bg in ("gym", "intro", "arena"):
        wall = {"gym": (170, 60, 50), "intro": (15, 15, 35), "arena": (12, 12, 25)}[bg]
        d.rectangle([0, 0, W, GROUND], fill=wall)
        if bg == "gym":
            for y in range(40, GROUND - 120, 26):
                d.line([0, y, W, y], fill=(150, 50, 45), width=2)
            d.rectangle([0, 300, 700, GROUND - 20], fill=(120, 90, 60))
            for y in range(310, GROUND - 20, 40):
                d.rectangle([0, y, 700, y + 8], fill=(160, 120, 80))
            d.rectangle([80, 60, 460, 130], fill=(30, 120, 60))
            d.text((270, 95), "GO EAGLES!", font=font(40), fill=WHITE, anchor="mm")
            if idx == 2:
                d.rectangle([520, 150, 660, 340], fill=(140, 100, 60), outline=(70, 50, 30), width=5)
                d.rectangle([550, 180, 630, 270], fill=WHITE)
                d.text((590, 192), "TEAM", font=font(14), fill=(0, 0, 0), anchor="mm")
                for k in range(6):
                    d.line([558, 210 + k * 10, 622, 210 + k * 10], fill=(80, 80, 80), width=2)
        else:
            for row in range(9):
                y = 110 + row * 34
                for i in range(90):
                    x = i * 15 + (row % 2) * 7 + rnd.randint(-2, 2)
                    c = rnd.choice([(200, 60, 60), (60, 80, 200), (230, 200, 160), (120, 90, 60), (245, 130, 32), (240, 240, 240), (70, 50, 40)])
                    d.ellipse([x, y, x + 11, y + 11], fill=tuple(int(v * (0.45 + row * 0.06)) for v in c))
                    d.rectangle([x + 1, y + 10, x + 10, y + 26], fill=tuple(int(v * 0.4) for v in c))
            d.rectangle([0, 420, W, GROUND], fill=(30, 30, 50))
            for i in range(0, W, 160):
                d.rectangle([i + 10, 440, i + 150, 520], fill=NAVY)
                d.text((i + 80, 480), "COMETS", font=font(22), fill=ORANGE, anchor="mm")
            d.rectangle([480, 0, 800, 90], fill=(20, 20, 20), outline=(90, 90, 90), width=4)
        floor = (205, 150, 90)
        d.rectangle([0, GROUND, W, H], fill=floor)
        for x in range(-200, W, 70):
            d.line([x, GROUND, x - 120, H], fill=(185, 132, 78), width=2)
        d.line([0, GROUND + 30, W, GROUND + 30], fill=WHITE, width=4)
        d.ellipse([200, GROUND + 50, 600, GROUND + 140], outline=WHITE, width=4)
        if bg == "arena":
            d.ellipse([500, GROUND + 40, 780, GROUND + 140], fill=NAVY)
            d.text((640, GROUND + 90), "C", font=font(56), fill=ORANGE, anchor="mm")
    elif bg == "campus":
        sky(d, (120, 180, 240), (220, 235, 255))
        d.rectangle([0, GROUND - 10, W, H], fill=(80, 150, 70))
        d.rectangle([700, 120, 1200, GROUND], fill=(170, 80, 60))
        d.polygon([(680, 120), (950, 30), (1220, 120)], fill=(90, 90, 100))
        for c in range(5):
            for r in range(3):
                d.rectangle([730 + c * 95, 160 + r * 110, 790 + c * 95, 240 + r * 110], fill=(230, 230, 200))
        d.rectangle([900, 420, 1000, GROUND], fill=(90, 50, 30))
        d.rectangle([760, 60, 1140, 100], fill=(120, 20, 30))
        d.text((950, 80), "STATE UNIVERSITY", font=font(26), fill=(240, 200, 60), anchor="mm")
        for tx in (120, 520):
            d.rectangle([tx - 12, 330, tx + 12, GROUND], fill=(100, 70, 40))
            d.ellipse([tx - 90, 180, tx + 90, 360], fill=(50, 130, 60))
        d.polygon([(380, GROUND), (620, GROUND), (760, H), (240, H)], fill=(200, 190, 170))
    elif bg == "stage":
        d.rectangle([0, 0, W, H], fill=(15, 10, 30))
        for x in range(0, W, 60):
            d.rectangle([x, 0, x + 50, GROUND], fill=(90, 15, 30))
            d.rectangle([x + 50, 0, x + 60, GROUND], fill=(60, 10, 20))
        d.rectangle([0, GROUND, W, H], fill=(40, 40, 60))
        for x in (200, 640, 1080):
            d.polygon([(x - 20, 0), (x + 20, 0), (x + 160, GROUND + 60), (x - 160, GROUND + 60)], fill=(50, 40, 70))
        d.rectangle([300, 40, 980, 120], fill=(10, 10, 40), outline=(200, 170, 60), width=4)
        d.text((640, 80), "THE DRAFT", font=font(50), fill=(230, 200, 90), anchor="mm")
        d.rectangle([900, 380, 1010, GROUND], fill=(60, 40, 30))  # podium
        d.rectangle([920, 400, 990, 450], fill=(200, 170, 60))
    elif bg == "locker":
        d.rectangle([0, 0, W, GROUND], fill=(60, 70, 90))
        for i in range(10):
            x = 20 + i * 126
            d.rectangle([x, 80, x + 116, GROUND - 20], fill=NAVY, outline=(10, 20, 50), width=4)
            d.text((x + 58, 115), str((i * 7 + 3) % 50), font=font(24), fill=ORANGE, anchor="mm")
            d.rectangle([x + 20, 160, x + 96, 300], fill=(240, 240, 240))
        d.rectangle([0, GROUND, W, H], fill=(70, 70, 75))
        d.rectangle([100, GROUND - 60, 1180, GROUND - 40], fill=(140, 100, 60))
        d.rectangle([1050, GROUND - 130, 1180, GROUND - 60], fill=(250, 220, 180))
        d.text((1115, GROUND - 95), "DONUTS", font=font(20), fill=(200, 80, 120), anchor="mm")
    elif bg == "bedroom":
        d.rectangle([0, 0, W, GROUND], fill=(120, 150, 190))
        d.rectangle([0, GROUND, W, H], fill=(140, 100, 70))
        d.rectangle([900, 100, 1150, 300], fill=(250, 220, 150), outline=WHITE, width=10)
        d.line([1025, 100, 1025, 300], fill=WHITE, width=8)
        d.rectangle([150, 90, 330, 330], fill=NAVY)
        d.text((240, 150), "COMETS", font=font(28), fill=ORANGE, anchor="mm")
        draw_ball(d, 240, 240, 40)
        d.rectangle([730, GROUND - 90, 830, GROUND], fill=(100, 70, 50))
        d.rectangle([745, GROUND - 130, 815, GROUND - 90], fill=(30, 30, 30))
        d.text((780, GROUND - 110), "7:00", font=font(22), fill=(255, 60, 60), anchor="mm")
    elif bg == "weights":
        d.rectangle([0, 0, W, GROUND], fill=(80, 85, 95))
        d.rectangle([0, 60, 620, 330], fill=(150, 180, 200), outline=(200, 200, 200), width=6)
        d.text((310, 195), "WORK", font=font(90), fill=(120, 150, 170), anchor="mm")
        d.rectangle([0, GROUND, W, H], fill=(50, 50, 55))
        for i in range(6):
            x = 60 + i * 80
            d.rectangle([x, GROUND - 40, x + 50, GROUND - 30], fill=(40, 40, 40))
            d.ellipse([x - 10, GROUND - 50, x + 10, GROUND - 20], fill=(30, 30, 30))
            d.ellipse([x + 40, GROUND - 50, x + 60, GROUND - 20], fill=(30, 30, 30))
        d.rectangle([700, 50, 980, 110], fill=NAVY)
        d.text((840, 80), "COMETS TRAINING", font=font(22), fill=ORANGE, anchor="mm")
    elif bg == "plane":
        d.rectangle([0, 0, W, H], fill=(225, 215, 195))
        d.rectangle([0, 0, W, 60], fill=(200, 190, 170))
        d.rectangle([0, GROUND, W, H], fill=(60, 50, 80))
    elif bg == "mansion":
        sky(d, (90, 160, 240), (200, 230, 255))
        d.rectangle([0, GROUND - 10, W, H], fill=(90, 170, 80))
        d.rectangle([520, 140, 1240, GROUND], fill=(245, 240, 230))
        d.polygon([(500, 140), (880, 50), (1260, 140)], fill=(80, 80, 90))
        for c in range(5):
            d.rectangle([560 + c * 135, 190, 640 + c * 135, 290], fill=(150, 200, 240))
            d.rectangle([560 + c * 135, 340, 640 + c * 135, 440], fill=(150, 200, 240))
        d.rectangle([830, 420, 930, GROUND], fill=(120, 80, 50))
        d.ellipse([20, GROUND + 30, 460, GROUND + 140], fill=(60, 180, 230), outline=WHITE, width=6)
        d.ellipse([60, GROUND + 50, 420, GROUND + 120], outline=(150, 220, 250), width=3)
        for i in range(12):  # curved palm trunk
            ty = GROUND - i * 24
            tx = 70 + math.sin(i / 4) * 18
            d.ellipse([tx - 14, ty - 16, tx + 14, ty + 6], fill=(150, 105, 65), outline=INK, width=2)
        top = (70 + math.sin(11 / 4) * 18, GROUND - 270)
        for a in (-160, -120, -60, -20, 200, 240):
            r = math.radians(a)
            tip = (top[0] + 120 * math.cos(r), top[1] + 50 * math.sin(r) + 60)
            mid = (top[0] + 70 * math.cos(r), top[1] - 25 + 30 * math.sin(r))
            d.polygon([top, mid, tip, (mid[0], mid[1] + 18)], fill=(70, 150, 70), outline=INK, width=2)
        for cx_ in (60, 85):
            d.ellipse([cx_ - 10, top[1] - 4, cx_ + 10, top[1] + 16], fill=(120, 80, 40), outline=INK)
        d.polygon([(950, GROUND), (1230, GROUND), (1280, H), (900, H)], fill=(175, 175, 175), outline=INK)
        d.polygon([(840, GROUND), (920, GROUND), (960, H), (800, H)], fill=(225, 215, 195), outline=INK)
        d.rounded_rectangle([960, GROUND - 10, 1200, GROUND + 60], 25, fill=(200, 30, 40))
        d.rounded_rectangle([1000, GROUND - 50, 1150, GROUND], 20, fill=(170, 20, 30))
        for wx in (1000, 1160):
            d.ellipse([wx - 25, GROUND + 35, wx + 25, GROUND + 85], fill=(20, 20, 20))
    elif bg == "hospital":
        d.rectangle([0, 0, W, GROUND], fill=(215, 235, 230))
        d.rectangle([0, GROUND, W, H], fill=(190, 200, 205))
        d.rectangle([80, 100, 380, 320], fill=(160, 200, 240), outline=WHITE, width=10)
        d.rectangle([800, GROUND - 120, 1200, GROUND - 70], fill=WHITE, outline=(150, 150, 150), width=3)
        d.rectangle([800, GROUND - 70, 815, GROUND], fill=(150, 150, 150))
        d.rectangle([1185, GROUND - 70, 1200, GROUND], fill=(150, 150, 150))
        d.rectangle([1190, GROUND - 200, 1210, GROUND - 120], fill=(150, 150, 150))
        d.rectangle([700, 200, 708, GROUND], fill=(160, 160, 160))
        d.rounded_rectangle([680, 190, 730, 260], 10, fill=(200, 230, 255), outline=(150, 150, 150), width=2)
        d.rectangle([450, 120, 600, 220], fill=(30, 30, 30))
        d.line([460, 170, 490, 170, 505, 140, 520, 200, 535, 170, 590, 170], fill=(60, 240, 90), width=3)
    elif bg == "press":
        d.rectangle([0, 0, W, H], fill=(235, 235, 240))
        for r in range(6):
            for c in range(9):
                x, y = 40 + c * 150 + (r % 2) * 75, 40 + r * 75
                d.text((x, y), "COMETS", font=font(20), fill=NAVY if (r + c) % 2 else ORANGE)
        d.rectangle([0, GROUND, W, H], fill=(60, 60, 70))
    details(d, bg, idx, rnd)
    return img


def bush(d, x, y, w, h, c=(95, 160, 80)):
    for i in range(3):
        ox = x + (i - 1) * w * 0.32
        d.ellipse([ox - w * 0.3, y - h, ox + w * 0.3, y], fill=c, outline=INK, width=2)
    d.rectangle([x - w * 0.55, y - h * 0.45, x + w * 0.55, y], fill=c)
    d.line([x - w * 0.55, y, x + w * 0.55, y], fill=INK, width=2)


def flowers(d, x0, x1, y, rnd):
    for _ in range(int((x1 - x0) / 14)):
        x = rnd.uniform(x0, x1); yy = y - rnd.uniform(0, 10)
        d.line([x, yy, x, yy + 10], fill=(70, 120, 60), width=2)
        d.ellipse([x - 4, yy - 4, x + 4, yy + 4], fill=rnd.choice([(240, 120, 140), (250, 220, 90), WHITE, (190, 140, 230)]))


def frame_pic(d, x, y, w, h, inner):
    d.rectangle([x, y, x + w, y + h], fill=(150, 105, 70), outline=INK, width=2)
    d.rectangle([x + 8, y + 8, x + w - 8, y + h - 8], fill=inner, outline=INK, width=1)


def plant(d, x, y, sc=1.0):
    for a in (-50, -25, 0, 25, 50):
        r = math.radians(a)
        d.ellipse([x + math.sin(r) * 40 * sc - 12 * sc, y - 60 * sc - math.cos(r) * 20 * sc - 22 * sc,
                   x + math.sin(r) * 40 * sc + 12 * sc, y - 60 * sc - math.cos(r) * 20 * sc + 22 * sc],
                  fill=(90, 150, 80), outline=INK, width=2)
    d.polygon([(x - 22 * sc, y - 40 * sc), (x + 22 * sc, y - 40 * sc), (x + 16 * sc, y), (x - 16 * sc, y)],
              fill=(200, 120, 80), outline=INK, width=2)


def shingles(d, ax, ay, by, half, color):
    """Rows of roof shingles inside a triangle roof (apex ax,ay; eave at by with half-width half)."""
    for row, y in enumerate(range(int(ay) + 14, int(by), 13)):
        hw = half * (y - ay) / (by - ay)
        d.line([ax - hw, y, ax + hw, y], fill=color, width=2)
        off = 0 if row % 2 else 14
        for x in range(int(ax - hw) + off, int(ax + hw), 28):
            d.line([x, y, x, y - 12], fill=color, width=2)


def window(d, x0, y0, x1, y1, glass=(170, 210, 240), shutters=None, night=False):
    if shutters:
        sw = (x1 - x0) * 0.28
        for sx in (x0 - sw - 3, x1 + 3):
            d.rectangle([sx, y0, sx + sw, y1], fill=shutters, outline=INK, width=2)
            for yy in range(int(y0) + 8, int(y1), 10):
                d.line([sx + 3, yy, sx + sw - 3, yy], fill=tuple(max(0, c - 30) for c in shutters), width=1)
    d.rectangle([x0, y0, x1, y1], fill=(250, 230, 150) if night else glass, outline=WHITE, width=5)
    d.rectangle([x0, y0, x1, y1], outline=INK, width=2)
    d.line([(x0 + x1) / 2, y0, (x0 + x1) / 2, y1], fill=WHITE, width=4)
    d.line([x0, (y0 + y1) / 2, x1, (y0 + y1) / 2], fill=WHITE, width=4)
    d.line([x0 + 8, y0 + 8, x0 + 22, y0 + 22], fill=(255, 255, 255, 140), width=3)
    d.rectangle([x0 - 6, y1, x1 + 6, y1 + 8], fill=(240, 240, 240), outline=INK, width=2)


def details(d, bg, idx, rnd):
    """Extra props so scenes feel lived-in instead of plain."""
    if bg == "driveway":
        night = idx == 17
        # siding (skip the garage and window)
        for y in range(166, GROUND, 16):
            for xa, xb in ((780, 1280),):
                if y > 296:
                    xb = 900
                if 210 < y < 312:
                    d.line([xa, y, 772, y], fill=(70, 115, 175), width=1)
                    d.line([902, y, xb, y], fill=(70, 115, 175), width=1)
                else:
                    d.line([xa, y, xb, y], fill=(70, 115, 175), width=1)
        d.polygon([(1150, 50), (1190, 50), (1190, 105), (1150, 89)], fill=(160, 80, 60), outline=INK, width=2)
        d.rectangle([1144, 42, 1196, 52], fill=(120, 60, 45), outline=INK, width=2)
        shingles(d, 1030, 40, 150, 270, (100, 50, 40))
        d.rectangle([765, 148, 1295, 156], fill=(235, 235, 235), outline=INK, width=2)  # gutter
        d.ellipse([1012, 92, 1048, 128], fill=(250, 230, 150) if night else (170, 210, 240), outline=INK, width=3)
        d.line([1030, 92, 1030, 128], fill=WHITE, width=3); d.line([1012, 110, 1048, 110], fill=WHITE, width=3)
        window(d, 800, 220, 870, 300, shutters=(50, 70, 120), night=night)
        for i in range(5):
            d.rectangle([915 + i * 60, 312, 960 + i * 60, 336], fill=(170, 210, 240), outline=INK, width=2)
        d.rounded_rectangle([1040, GROUND - 26, 1080, GROUND - 18], 3, fill=(120, 120, 130), outline=INK)
        d.rectangle([900, 300, 1220, GROUND + 10], outline=INK, width=2)
        d.rectangle([882, 330, 894, 350], fill=(255, 240, 170), outline=INK, width=2)  # porch light
        d.rectangle([776, GROUND - 6, 900, GROUND + 10], fill=(150, 150, 155), outline=INK, width=2)  # foundation
        for fx in range(0, 760, 34):
            d.polygon([(fx, GROUND - 95), (fx + 12, GROUND - 110), (fx + 24, GROUND - 95), (fx + 24, GROUND - 10),
                       (fx, GROUND - 10)], fill=(250, 248, 240), outline=INK)
        d.rectangle([0, GROUND - 80, 760, GROUND - 72], fill=(250, 248, 240), outline=INK)
        bush(d, 820, GROUND + 8, 90, 60); bush(d, 1250, GROUND + 8, 70, 50)
        flowers(d, 20, 740, GROUND - 4, rnd)
        d.rectangle([300, GROUND - 70, 306, GROUND], fill=(110, 80, 50))
        d.rounded_rectangle([284, GROUND - 100, 324, GROUND - 70], 8, fill=(70, 110, 170), outline=INK, width=2)
        d.rectangle([308, GROUND - 112, 312, GROUND - 92], fill=(220, 60, 60))
        d.polygon([(803, 223), (822, 223), (812, 297), (803, 297)], fill=(230, 110, 110))
        d.polygon([(867, 223), (848, 223), (858, 297), (867, 297)], fill=(230, 110, 110))
        d.ellipse([400, GROUND + 60, 520, GROUND + 90], fill=(120, 120, 120, 60))
    elif bg == "gym":
        d.ellipse([950, 70, 1030, 150], fill=WHITE, outline=INK, width=4)
        d.line([990, 110, 990, 82], fill=INK, width=3); d.line([990, 110, 1012, 118], fill=INK, width=3)
        for i, c in enumerate([(30, 120, 60), (245, 205, 90), (48, 82, 165), (200, 60, 60)]):
            x = 520 + i * 90
            d.polygon([(x, 20), (x + 60, 20), (x + 30, 80)], fill=c, outline=INK, width=2)
        d.rectangle([1040, 300, 1140, GROUND], fill=(48, 82, 165), outline=INK, width=2)
        d.rectangle([760, GROUND - 70, 860, GROUND - 6], fill=(120, 120, 130), outline=INK, width=2)
        for i in range(3):
            draw_ball(d, 778 + i * 32, GROUND - 82, 14)
        d.rectangle([880, GROUND - 90, 920, GROUND], fill=(80, 140, 220), outline=INK, width=2)
        d.rectangle([886, GROUND - 120, 914, GROUND - 90], fill=(200, 230, 250), outline=INK, width=2)
    elif bg == "campus":
        for row, y in enumerate(range(128, GROUND, 14)):
            d.line([702, y, 1198, y], fill=(150, 70, 55), width=1)
            for x in range(702 + (0 if row % 2 else 15), 1198, 30):
                d.line([x, y, x, y + 14], fill=(150, 70, 55), width=1)
        shingles(d, 950, 30, 120, 270, (70, 70, 80))
        d.rectangle([760, 60, 1140, 100], fill=(120, 20, 30), outline=INK, width=2)
        d.text((950, 80), "STATE UNIVERSITY", font=font(26), fill=(240, 200, 60), anchor="mm")
        for c in range(5):
            for r in range(3):
                if c == 2 and r == 2:
                    continue
                window(d, 730 + c * 95, 160 + r * 110, 790 + c * 95, 240 + r * 110, glass=(220, 225, 200))
        d.chord([890, 380, 1010, 460], 180, 360, fill=(220, 225, 200), outline=INK, width=2)
        d.rectangle([900, 420, 1000, GROUND], fill=(90, 50, 30), outline=INK, width=2)
        d.line([950, 420, 950, GROUND], fill=INK, width=2)
        d.ellipse([938, 480, 946, 488], fill=(240, 200, 80)); d.ellipse([954, 480, 962, 488], fill=(240, 200, 80))
        for colx in (874, 1012):
            d.rectangle([colx, 380, colx + 14, GROUND], fill=(240, 235, 225), outline=INK, width=2)
        d.rectangle([862, GROUND - 8, 1038, GROUND + 2], fill=(200, 200, 200), outline=INK, width=2)
        bush(d, 640, GROUND, 130, 60); bush(d, 1230, GROUND, 120, 60)
        flowers(d, 560, 700, GROUND - 2, rnd); flowers(d, 1150, 1270, GROUND - 2, rnd)
        d.rectangle([250, GROUND - 50, 370, GROUND - 40], fill=(140, 95, 60), outline=INK, width=2)
        d.rectangle([250, GROUND - 70, 370, GROUND - 62], fill=(140, 95, 60), outline=INK, width=2)
        for lx in (258, 360):
            d.rectangle([lx, GROUND - 40, lx + 4, GROUND], fill=INK)
        d.rectangle([660, 260, 668, GROUND], fill=(60, 60, 70))
        d.ellipse([648, 236, 680, 268], fill=(255, 240, 180), outline=INK, width=2)
        for i in range(4):
            bx, by = rnd.randint(150, 600), rnd.randint(60, 180)
            d.arc([bx, by, bx + 14, by + 10], 200, 340, fill=INK, width=2)
            d.arc([bx + 12, by, bx + 26, by + 10], 200, 340, fill=INK, width=2)
    elif bg == "stage":
        for i in range(6):
            x = 560 + i * 55
            d.ellipse([x, 140, x + 44, 184], fill=[(220, 80, 60), (60, 120, 210), (245, 205, 90), (80, 170, 100),
                                                  (160, 90, 200), (245, 130, 32)][i], outline=INK, width=2)
        for cx in (90, 1200):
            d.line([cx, GROUND, cx - 30, GROUND + 80], fill=INK, width=4); d.line([cx, GROUND, cx + 30, GROUND + 80], fill=INK, width=4)
            d.rectangle([cx - 30, GROUND - 40, cx + 40, GROUND], fill=(50, 50, 55), outline=INK, width=2)
            d.ellipse([cx + 30, GROUND - 32, cx + 52, GROUND - 8], fill=(90, 120, 160), outline=INK, width=2)
    elif bg == "locker":
        for i in range(10):
            x = 20 + i * 126
            c = (48, 82, 165) if i % 2 else (245, 245, 245)
            d.polygon([(x + 30, 170), (x + 86, 170), (x + 92, 200), (x + 82, 200), (x + 82, 290), (x + 34, 290),
                       (x + 34, 200), (x + 24, 200)], fill=c, outline=INK, width=2)
            d.text((x + 58, 235), str((i * 7 + 3) % 50), font=font(20), fill=ORANGE, anchor="mm")
            d.rounded_rectangle([x + 30, GROUND - 32, x + 52, GROUND - 22], 4, fill=(250, 250, 250), outline=INK)
        d.rectangle([400, GROUND - 72, 470, GROUND - 60], fill=(250, 250, 250), outline=INK)
    elif bg == "bedroom":
        d.ellipse([350, GROUND + 30, 900, GROUND + 140], fill=(200, 110, 100), outline=INK, width=2)
        d.ellipse([400, GROUND + 45, 850, GROUND + 125], outline=(240, 200, 150), width=4)
        d.rectangle([380, 140, 640, 150], fill=(150, 105, 70), outline=INK, width=2)
        for bx_ in (400, 610):
            d.polygon([(bx_, 150), (bx_ + 22, 150), (bx_, 172)], fill=(120, 85, 55), outline=INK)
        for i, h in enumerate((40, 55, 35, 48)):
            d.rectangle([395 + i * 25, 140 - h, 415 + i * 25, 140], fill=[(200, 80, 80), (80, 120, 200), (90, 160, 90), (230, 190, 80)][i], outline=INK)
        d.rectangle([520, 105, 540, 140], fill=(245, 205, 90), outline=INK)
        d.ellipse([512, 88, 548, 112], fill=(245, 205, 90), outline=INK, width=2)
        frame_pic(d, 580, 60, 70, 70, (170, 210, 240))
        plant(d, 1210, GROUND)
        d.line([735, GROUND - 130, 735, GROUND - 170], fill=INK, width=3)
        d.polygon([(715, GROUND - 170), (755, GROUND - 170), (745, GROUND - 195), (725, GROUND - 195)], fill=(250, 230, 160), outline=INK)
    elif bg == "weights":
        for i in range(3):
            x = 700 + i * 70
            d.ellipse([x, GROUND - 40, x + 40, GROUND], fill=(60, 60, 65), outline=INK, width=2)
            d.arc([x + 8, GROUND - 56, x + 32, GROUND - 30], 180, 360, fill=(60, 60, 65), width=6)
        d.rounded_rectangle([660, GROUND - 6, 940, GROUND + 14], 6, fill=(90, 160, 200), outline=INK, width=2)
        d.rectangle([960, GROUND - 40, 976, GROUND], fill=(80, 170, 230), outline=INK, width=2)
        plant(d, 640, GROUND, 0.9)
    elif bg == "hospital":
        for y in range(110, 310, 22):
            d.line([90, y, 370, y], fill=(220, 230, 240), width=3)
        d.rectangle([66, 320, 394, 334], fill=(250, 250, 250), outline=INK, width=2)
        d.rectangle([180, 290, 220, 320], fill=(200, 220, 240), outline=INK, width=2)
        for i in range(5):
            fx = 186 + i * 7
            d.line([200, 290, fx, 265], fill=(70, 130, 70), width=2)
            d.ellipse([fx - 6, 258, fx + 6, 270], fill=[(240, 120, 140), (250, 220, 90)][i % 2], outline=INK)
        d.rounded_rectangle([240, 292, 330, 320], 6, fill=(250, 250, 250), outline=INK, width=2)
        d.text((285, 306), "GET WELL", font=font(13), fill=(200, 70, 90), anchor="mm")
        plant(d, 50, GROUND, 0.8)
    elif bg == "mansion":
        shingles(d, 880, 50, 140, 380, (60, 60, 70))
        for cx_ in (640, 1120):
            ry_ = 50 + 90 * abs(cx_ + 20 - 880) / 380
            d.polygon([(cx_, 30), (cx_ + 40, 30), (cx_ + 40, ry_ - 4), (cx_, ry_ + 6)], fill=(190, 110, 90), outline=INK, width=2)
        d.rectangle([505, 138, 1255, 146], fill=(235, 235, 235), outline=INK, width=2)
        for c in range(5):
            window(d, 560 + c * 135, 190, 640 + c * 135, 290, shutters=(60, 110, 80))
            if c != 2:
                window(d, 560 + c * 135, 340, 640 + c * 135, 440, shutters=(60, 110, 80))
        d.rectangle([800, 470, 960, 486], fill=(240, 240, 240), outline=INK, width=2)
        d.rectangle([520, 315, 1240, 322], fill=(230, 225, 210), outline=INK, width=1)
        # front door with portico
        d.chord([830, 380, 930, 460], 180, 360, fill=(170, 210, 240), outline=INK, width=2)
        d.rectangle([830, 420, 930, GROUND], fill=(120, 80, 50), outline=INK, width=2)
        d.line([880, 420, 880, GROUND], fill=INK, width=2)
        for px_ in (840, 890):
            d.rectangle([px_, 432, px_ + 30, 470], outline=(90, 60, 35), width=2)
            d.rectangle([px_, 480, px_ + 30, GROUND - 10], outline=(90, 60, 35), width=2)
        d.ellipse([868, 482, 876, 490], fill=(240, 200, 80)); d.ellipse([884, 482, 892, 490], fill=(240, 200, 80))
        d.polygon([(790, 375), (880, 335), (970, 375)], fill=(245, 240, 230), outline=INK, width=2)
        for colx in (800, 945):
            d.rectangle([colx, 375, colx + 15, GROUND], fill=(250, 250, 248), outline=INK, width=2)
        d.rectangle([790, GROUND - 6, 970, GROUND + 4], fill=(210, 210, 210), outline=INK, width=2)
        for hx in (580, 720):
            bush(d, hx, GROUND, 110, 50, (80, 150, 75))
        flowers(d, 520, 790, GROUND + 4, rnd)
        for lx in (500, 1250):
            d.rectangle([lx, GROUND - 120, lx + 6, GROUND], fill=INK)
            d.ellipse([lx - 10, GROUND - 140, lx + 16, GROUND - 114], fill=(255, 240, 180), outline=INK, width=2)
    elif bg == "plane":
        d.rectangle([0, 60, W, 100], fill=(210, 200, 182), outline=INK, width=2)
        for x in range(0, W, 160):
            d.line([x, 60, x, 100], fill=INK, width=2)
            d.ellipse([x + 70, 105, x + 86, 115], fill=(255, 240, 180))
        for x in range(0, W, 40):
            d.line([x, GROUND + 10, x + 20, H], fill=(80, 70, 100), width=2)
    elif bg == "press":
        plant(d, 120, GROUND, 1.3); plant(d, 1160, GROUND, 1.3)
        for px in (40, 1240):
            d.rectangle([px - 8, 0, px + 8, GROUND], fill=(48, 82, 165), outline=INK)


def draw_dynamic_bg(d, bg, t, idx, look):
    if bg == "arena" or bg == "intro":
        rnd = random.Random(int(t * 5) + idx * 1000)
        for _ in range(6):
            x = rnd.randint(0, W); y = rnd.randint(110, 400)
            d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=(255, 255, 240))
        if bg == "arena":
            home = 80 + int(t / 6)
            away = 82 + int((t + 3) / 6.5)
            d.text((560, 30), "HOME", font=font(18), fill=(200, 200, 200), anchor="mm")
            d.text((720, 30), "AWAY", font=font(18), fill=(200, 200, 200), anchor="mm")
            d.text((560, 62), str(home), font=font(34), fill=(255, 70, 60), anchor="mm")
            d.text((720, 62), str(away), font=font(34), fill=(255, 70, 60), anchor="mm")
            q = max(0, 720 - int(t * 4) % 720)
            d.text((640, 62), f"{q // 60}:{q % 60:02d}", font=font(20), fill=(255, 200, 60), anchor="mm")
    elif bg == "plane":
        for i in range(4):
            x = 120 + i * 300
            d.rounded_rectangle([x, 120, x + 140, 300], 50, fill=(130, 190, 250), outline=(170, 160, 140), width=8)
            for j in range(3):
                cx = x + 20 + ((j * 97 - t * 180) % 180) - 20
                cy = 170 + j * 40
                if x + 10 < cx < x + 130:
                    d.ellipse([cx - 25, cy - 10, cx + 25, cy + 10], fill=WHITE)
        for i in range(5):
            if i == 2:
                continue
            plane_seat(d, 60 + i * 290 + 60, 1.0)
    elif bg == "intro":
        pass


# ------------------------------------------------------------------- actions

def confetti(d, t, seed=1):
    rnd = random.Random(seed)
    for i in range(70):
        x0 = rnd.randint(0, W); sp = rnd.uniform(60, 140); ph = rnd.uniform(0, 10)
        y = ((t + ph) * sp) % (GROUND + 50) - 20
        x = x0 + math.sin(t * 2 + i) * 20
        c = rnd.choice([ORANGE, WHITE, (60, 120, 230), (250, 220, 60), (230, 60, 90)])
        d.rectangle([x, y, x + 7, y + 11], fill=c)


def act(d, action, t, look, bg, mouth, idx):
    outfit, s = look
    hip_y = stand_hip(s)
    has_hoop = bg in HOOP_BGS
    if action in ("shoot", "dunk") and not has_hoop:
        action = "dribble"
    base_x = 560 if has_hoop else 640
    if action == "meet":
        action, base_x = "talk", 560
    speaking = mouth

    if action == "idle":
        b = math.sin(t * 2) * 2
        person(d, base_x, hip_y + b, s, outfit, mouth=speaking)
    elif action == "talk":
        g = math.sin(t * 2.7)
        pose = dict(fu=40 + 25 * g, ff=90 + 30 * math.sin(t * 3.1 + 1), bu=-15, bf=10 + 10 * g)
        person(d, base_x, hip_y + math.sin(t * 2) * 2, s, outfit, pose=pose, mouth=speaking)
    elif action == "sad":
        sway = math.sin(t * 0.8) * 3
        person(d, base_x + sway, hip_y + 4, s, outfit, pose=dict(fu=3, ff=0, bu=-3, bf=0),
               mouth=speaking, mood="sad", head_drop=1.0)
    elif action == "walk":
        span = 420
        ph = 2 * math.pi * t / 11.0 - math.pi / 2
        x = 640 + span / 2 * math.sin(ph)
        vel = math.cos(ph)
        facing = 1 if vel >= 0 else -1
        w = math.sin(t * 6) * min(1.0, abs(vel) * 2.5)
        pose = dict(ft=25 * w, fs=25 * w - 15 * max(0, -w), bt=-25 * w, bs=-25 * w - 15 * max(0, w),
                    fu=-25 * w, ff=-10 * w + 15, bu=25 * w, bf=25 * w + 15)
        person(d, x, hip_y - abs(w) * 3 * s, s, outfit, pose=pose, facing=facing, mouth=speaking)
    elif action == "dribble":
        crouch = 8 * s
        x = base_x - 60 + math.sin(t * 0.7) * 120
        bounce = abs(math.sin(t * math.pi * 2.2))
        pose = dict(fu=25, ff=50 + 30 * bounce, bu=-20, bf=10, ft=20, fs=-10, bt=-15, bs=5)
        r = person(d, x, hip_y + crouch, s, outfit, pose=pose, mouth=speaking)
        hx, hy = r["hand"]
        by = lerp(GROUND - 13 * s, hy + 12 * s, bounce)
        draw_ball(d, hx + 6 * s, by, 13 * s)
    elif action == "shoot":
        cyc = 3.4
        p = t % cyc
        x = base_x + 40
        net = 0.0
        gather = dict(fu=30, ff=80, bu=-10, bf=20, ft=25, fs=-25, bt=15, bs=-25)
        up = dict(fu=160, ff=150, bu=150, bf=170, ft=5, fs=0, bt=-5, bs=0)
        follow = dict(fu=170, ff=200, bu=150, bf=175, ft=5, fs=10, bt=-8, bs=5)
        if p < 0.7:
            k = ease(p / 0.7)
            pose = {n: lerp(gather[n], up[n], k) for n in gather}
            r = person(d, x, hip_y + lerp(14, -10, k) * s, s, outfit, pose=pose, mouth=speaking)
            draw_ball(d, r["hand"][0], r["hand"][1] - 12 * s, 13 * s)
        else:
            jump = max(0, math.sin(min(1, (p - 0.7) / 0.6) * math.pi)) * 30 * s
            k = ease((p - 0.7) / 0.15)
            pose = {n: lerp(up[n], follow[n], k) for n in up}
            dy = -jump - lerp(10, 0, min(1, (p - 0.7) / 0.6)) * s
            if p > 2.4:
                k2 = ease((p - 2.4) / 1.0)
                pose = {n: lerp(follow[n], gather[n], k2) for n in follow}
                dy = lerp(0, 14, k2) * s
            r = person(d, x, hip_y + dy, s, outfit, pose=pose, mouth=speaking)
            q = (p - 0.7) / 1.1
            sx, sy = x + 30 * s, hip_y - 190 * s
            if q < 1:
                bx = lerp(sx, RIM[0] - 6, q)
                by = lerp(sy, RIM[1] - 14, q) - math.sin(q * math.pi) * 170
                draw_ball(d, bx, by)
            elif p < 2.4:
                q2 = (p - 1.8) / 0.6
                draw_ball(d, RIM[0] - 6 + q2 * 10, lerp(RIM[1] - 10, GROUND - 13, q2 * q2))
                net = max(0, 1 - q2)
            else:
                k3 = (p - 2.4) / 1.0
                hx, hy = r["hand"][0], r["hand"][1] - 12 * s
                bx = lerp(RIM[0] + 4, hx, ease(k3))
                by = lerp(GROUND - 13, hy, k3) - abs(math.sin(k3 * math.pi * 1.5)) * 70 * (1 - k3)
                draw_ball(d, bx, min(by, GROUND - 13))
        draw_hoop(d, net)
        return
    elif action == "dunk":
        cyc = 4.8
        p = t % cyc
        net = 0.0
        x0, x1 = 380, RIM[0] - 45 * s
        top = hip_y - (RIM[1] + 140 * s)
        dribble = dict(fu=40, ff=70, bu=0, bf=40)
        if p < 1.3:
            k = p / 1.3
            x = lerp(x0, x1 - 40, ease(k))
            w = math.sin(t * 9) * min(1.0, math.sin(k * math.pi) * 3)
            pose = dict(ft=30 * w, fs=30 * w - 20, bt=-30 * w, bs=-30 * w - 20, bu=25 * w, **{n: dribble[n] for n in ("fu", "ff", "bf")})
            r = person(d, x, hip_y, s, outfit, pose=pose, mouth=speaking)
            bounce = abs(math.sin(t * math.pi * 2.4))
            draw_ball(d, r["hand"][0] + 6 * s, lerp(GROUND - 13 * s, r["hand"][1] + 12 * s, bounce), 13 * s)
        elif p < 2.0:
            k = (p - 1.3) / 0.7
            x = lerp(x1 - 40, x1, k)
            lift = math.sin(k * math.pi / 2) * top
            pose = dict(fu=lerp(40, 175, k), ff=lerp(70, 178, k), bu=lerp(0, -20, k), bf=lerp(40, -10, k),
                        ft=lerp(0, 40, k), fs=lerp(-20, -30, k), bt=lerp(0, -10, k), bs=lerp(-20, -40, k))
            r = person(d, x, hip_y - lift, s, outfit, pose=pose, mouth=speaking)
            draw_ball(d, r["hand"][0], r["hand"][1] - 12, 13 * s)
        elif p < 2.4:
            k = (p - 2.0) / 0.4
            pose = dict(fu=178, ff=178, bu=-20, bf=-10, ft=lerp(40, 10, k), fs=lerp(-30, -10, k), bt=-5, bs=-20)
            draw_ball(d, RIM[0] - 6, RIM[1] + 30 + k * 120)
            draw_hoop(d, 1.0)
            person(d, x1, hip_y - top + 10 * math.sin(k * math.pi), s, outfit, pose=pose, mouth=speaking)
            return
        elif p < 3.3:
            k = (p - 2.4) / 0.9
            lift = top * (1 - ease(min(1, k * 1.8)))
            hang = dict(fu=178, ff=178, bu=-20, bf=-10, ft=10, fs=-10, bt=-5, bs=-20)
            land = dict(fu=40, ff=70, bu=0, bf=40, ft=20, fs=-25, bt=-15, bs=-20)
            pose = {n: lerp(hang[n], land[n], ease(k)) for n in hang}
            r = person(d, x1, hip_y - max(0.0, lift) + 10 * (1 - k), s, outfit, pose=pose, mouth=speaking)
            hx, hy = r["hand"][0] + 6 * s, r["hand"][1] + 12 * s
            bx = lerp(RIM[0] - 6, hx, ease(k))
            by = lerp(RIM[1] + 78, hy, k) + abs(math.sin(k * math.pi)) * (GROUND - 13 - RIM[1] - 78) * (1 - k * 0.5)
            draw_ball(d, bx, min(by, GROUND - 13))
            net = max(0, 1 - k)
        else:
            k = (p - 3.3) / 1.5
            x = lerp(x1, x0, ease(k))
            w = math.sin(t * 8) * min(1.0, math.sin(k * math.pi) * 3)
            pose = dict(ft=25 * w, fs=25 * w - 15, bt=-25 * w, bs=-25 * w - 15, bu=20 * w, fu=40, ff=70, bf=40)
            r = person(d, x, hip_y, s, outfit, pose=pose, facing=-1 if k < 0.97 else 1, mouth=speaking)
            bounce = abs(math.sin(t * math.pi * 2.4))
            draw_ball(d, r["hand"][0] - 6 * s, lerp(GROUND - 13 * s, r["hand"][1] + 12 * s, bounce), 13 * s)
        draw_hoop(d, net)
        return
    elif action == "sit":
        cx = base_x if bg != "stage" else 330
        if bg == "plane":
            plane_seat(d, cx, s)
        elif bg != "press":
            chair(d, cx, s)
        hy = sit_hip(s) if bg != "press" else GROUND - 100 * s  # tall chair hidden behind the press table
        leg = math.sin(t * 12) * 3 if bg == "stage" else 0
        g = math.sin(t * 2.5)
        pose = dict(ft=85, fs=0 + leg, bt=80, bs=-5, fu=30 + 15 * g, ff=80 + 15 * g, bu=10, bf=40)
        person(d, cx, hy, s, outfit, pose=pose, mouth=speaking)
        if bg == "press":
            d.rectangle([300, GROUND - 60, 980, GROUND + 120], fill=NAVY)
            d.text((640, GROUND + 20), "COMETS", font=font(40), fill=ORANGE, anchor="mm")
            for mx in (560, 620, 680, 740):
                d.line([mx, GROUND - 60, mx - 20 + (mx - 640) * 0.1, GROUND - 120], fill=(30, 30, 30), width=4)
                d.ellipse([mx - 32 + (mx - 640) * 0.1, GROUND - 135, mx - 10 + (mx - 640) * 0.1, GROUND - 113], fill=(40, 40, 40))
    elif action == "sleep":
        if bg == "plane":
            cx = base_x
            plane_seat(d, cx, s)
            pose = dict(ft=85, fs=0, bt=80, bs=-5, fu=60, ff=110, bu=50, bf=100)
            person(d, cx, sit_hip(s), s, outfit, pose=pose, eyes_closed=True, head_drop=0.6)
            zx, zy = cx + 30, GROUND - 280
        else:
            bx = 200
            d.rectangle([bx, GROUND - 120, bx + 420, GROUND - 60], fill=(110, 70, 40))
            d.rectangle([bx, GROUND - 200, bx + 25, GROUND], fill=(110, 70, 40))
            d.rectangle([bx + 395, GROUND - 160, bx + 420, GROUND], fill=(110, 70, 40))
            d.ellipse([bx + 25, GROUND - 160, bx + 120, GROUND - 115], fill=WHITE)
            hx, hy = bx + 80, GROUND - 150
            d.ellipse([hx - 28, hy - 28, hx + 28, hy + 28], fill=SKIN, outline=INK, width=2)
            hair_shape(d, hx, hy, 28, 0.9, 1, HAIR)
            for ox in (-2, 18):
                d.arc([hx + ox - 5, hy + 2, hx + ox + 5, hy + 9], 20, 160, fill=INK, width=2)
            d.arc([hx + 2, hy + 12, hx + 14, hy + 20], 25, 155, fill=INK, width=2)
            breathe = math.sin(t * 2) * 4
            d.rounded_rectangle([bx + 100, GROUND - 150 - breathe, bx + 400, GROUND - 105], 20, fill=(60, 90, 160), outline=INK, width=2)
            d.line([bx + 110, GROUND - 135 - breathe, bx + 390, GROUND - 135 - breathe], fill=(240, 240, 240), width=3)
            zx, zy = hx + 20, hy - 40
        for i in range(3):
            ph = (t * 0.6 + i / 3) % 1.0
            d.text((zx + ph * 60, zy - ph * 90), "z", font=font(int(20 + ph * 30)), fill=(40, 40, 120), anchor="mm")
        return
    elif action == "lift":
        x = 300 if has_hoop else 640
        k = (math.sin(t * 2.4) + 1) / 2
        pose = dict(fu=lerp(100, 175, k), ff=lerp(170, 180, k), bu=lerp(100, 175, k), bf=lerp(170, 180, k),
                    ft=12, fs=0, bt=-12, bs=0)
        r = person(d, x, hip_y, s, outfit, pose=pose, mouth=speaking)
        hx, hy = r["hand"]
        d.line([x - 110, hy, x + 110, hy], fill=(60, 60, 60), width=6)
        for px in (x - 100, x + 100):
            d.rectangle([px - 8, hy - 34, px + 8, hy + 34], fill=(25, 25, 25))
    elif action == "hurt":
        x = base_x + math.sin(t * 0.5) * 100
        step = math.sin(t * 2)
        pose = dict(fu=20 + 5 * step, ff=20, bu=-20, bf=-20, ft=10 * step, fs=10 * step, bt=-30, bs=-90)
        r = person(d, x, hip_y, s, outfit, pose=pose, mouth=speaking, mood="sad")
        for side in (-1, 1):
            d.line([x + side * 30, hip_y - 60 * s, x + side * 45 + step * 10, GROUND], fill=(160, 160, 170), width=6)
            d.line([x + side * 22, hip_y - 62 * s, x + side * 40, hip_y - 62 * s], fill=(90, 90, 90), width=8)
        d.rounded_rectangle([x - 12, hip_y + 30, x + 12, hip_y + 60], 5, fill=(40, 40, 50))
    elif action == "celebrate":
        j = abs(math.sin(t * 4)) * 35 * s
        wave = math.sin(t * 8) * 15
        pose = dict(fu=165 + wave, ff=175 + wave, bu=160 - wave, bf=170 - wave, ft=15, fs=-20, bt=-15, bs=-20)
        person(d, base_x, hip_y - j, s, outfit, pose=pose, mouth=max(speaking, 0.0))
        confetti(d, t, idx)
    if has_hoop:
        draw_hoop(d)


def foreground(d, bg):
    """Objects that sit in front of the characters."""
    if bg == "stage":
        d.rectangle([150, GROUND - 34, 430, GROUND + 50], fill=(245, 245, 245), outline=INK, width=2)
        d.ellipse([140, GROUND - 50, 440, GROUND - 22], fill=WHITE, outline=INK, width=2)
        for x in range(170, 430, 40):
            d.line([x, GROUND - 20, x - 4, GROUND + 50], fill=(215, 215, 220), width=2)
        d.rectangle([270, GROUND - 74, 300, GROUND - 40], fill=(200, 230, 250), outline=INK, width=2)  # water glass


def extras(d, bg, idx, t, look, action):
    """Background characters per scene."""
    if bg == "stage":
        g = math.sin(t * 2)
        person(d, 955, stand_hip(1.0) - 10, 1.0, "suit", pose=dict(fu=60 + 10 * g, ff=90), facing=-1,
               skin=(230, 190, 160), hair=(160, 160, 160), mouth=0.2 * (g > 0.6))
        chair(d, 230, 0.95)
        person(d, 230, sit_hip(0.95), 0.95, "mom", pose=dict(ft=85, bt=80, fu=40, ff=70), skin=(185, 130, 95),
               hair=(95, 60, 40), long_hair=True)
    elif bg == "locker" and action != "walk":
        person(d, 950, stand_hip(1.15), 1.15, "comets", pose=dict(fu=50, ff=120), facing=-1,
               skin=(90, 55, 35), hair=(10, 10, 10))
    elif bg == "arena" and action in ("dribble", "sad"):
        g = math.sin(t * 3)
        person(d, 820, stand_hip(1.0) + 8, 1.0, "college", pose=dict(fu=100 + 20 * g, ff=150, bu=80 - 20 * g, bf=120,
               ft=25, fs=-20, bt=-20, bs=10), facing=-1, skin=(220, 180, 150))
    elif bg == "driveway" and idx in (1, 17):
        g = math.sin(t * 1.7)
        person(d, 860, stand_hip(0.95), 0.95, "mom", pose=dict(fu=60 + 30 * g, ff=150 + 20 * g), facing=-1,
               skin=(185, 130, 95), hair=(95, 60, 40) if idx == 1 else (150, 140, 135), long_hair=True)
    elif bg == "driveway" and idx == 15:
        for i, kx in enumerate((230, 320, 410)):
            b = abs(math.sin(t * 3 + i)) * 8
            person(d, kx, stand_hip(0.6) - b, 0.6, "comets", pose=dict(fu=150, ff=170, bu=140, bf=160),
                   skin=[(200, 150, 110), (110, 70, 40), (240, 200, 170)][i])
    elif bg == "campus" and action == "meet":
        g = math.sin(t * 2.2)
        r = person(d, 740, stand_hip(1.0), 1.0, "agent", pose=dict(fu=70 + 8 * g, ff=85, bu=-5, bf=-5), facing=-1,
                   skin=(225, 185, 150), hair=(60, 40, 25))
        hx, hy = r["hand"]
        d.rectangle([hx - 14, hy - 9, hx + 2, hy + 1], fill=WHITE, outline=(80, 80, 80))
        d.rounded_rectangle([760, GROUND - 95, 800, GROUND - 65], 4, fill=(70, 45, 25))
    elif bg == "hospital" and action != "hurt":
        person(d, 1000, stand_hip(1.0), 1.0, "gown", pose=dict(fu=40, ff=90), facing=-1,
               skin=(230, 190, 160), hair=(90, 60, 30))


# ------------------------------------------------------------------ overlays

def subtitle(d, text):
    if not text:
        return
    lines = textwrap.wrap(text, 52)
    fs = font(36)
    lh = 46
    y0 = H - lh * len(lines) - 22
    d.rectangle([0, y0 - 12, W, H], fill=(0, 0, 0, 120))
    for i, ln in enumerate(lines):
        d.text((W / 2, y0 + lh * i + lh / 2), ln, font=fs, fill=WHITE, anchor="mm", stroke_width=5, stroke_fill=INK)


def chapter_card(d, title, t):
    if not title or t > 4.5:
        return
    k = ease(t / 0.5) * (1 - ease((t - 4.0) / 0.5))
    w = 40 + font(44).getlength(title)
    x = lerp(-w, 0, k)
    d.polygon([(x, 120), (x + w + 60, 120), (x + w + 30, 200), (x, 200)], fill=ORANGE, outline=INK, width=4)
    d.rectangle([x, 200, x + w + 30, 208], fill=NAVY)
    d.text((x + 30, 160), title, font=font(44), fill=WHITE, anchor="lm", stroke_width=3, stroke_fill=INK)


def watermark(d):
    d.rounded_rectangle([14, 12, 260, 46], 8, fill=(0, 0, 0))
    d.ellipse([22, 18, 44, 40], fill=ORANGE)
    d.text((54, 29), CHANNEL.upper(), font=font(18), fill=WHITE, anchor="lm")


def intro_card(d, t):
    if t > 6:
        return
    k = ease(t / 0.8) * (1 - ease((t - 5.2) / 0.8))
    if k <= 0:
        return
    y = lerp(-200, 120, k)
    d.rounded_rectangle([240, y, 1040, y + 190], 30, fill=NAVY, outline=ORANGE, width=8)
    d.ellipse([270, y + 40, 380, y + 150], fill=BALL)
    d.line([270, y + 95, 380, y + 95], fill=(60, 30, 10), width=4)
    d.line([325, y + 40, 325, y + 150], fill=(60, 30, 10), width=4)
    d.text((700, y + 70), CHANNEL.upper(), font=font(58), fill=WHITE, anchor="mm")
    d.text((700, y + 140), TITLE, font=font(34, False), fill=ORANGE, anchor="mm")


# ------------------------------------------------------------------- render

def stylize(img):
    """Storybook look: soft pastel colours, thin ink lines, light paper grain."""
    edges = np.asarray(img.convert("L").filter(ImageFilter.FIND_EDGES)) > 40
    arr = np.asarray(img).astype(np.float32)
    arr = arr * 0.74 + np.array([252, 242, 226], np.float32) * 0.26
    m = edges[..., None]
    arr = np.where(m, arr * 0.35 + np.array(INK, np.float32) * 0.4, arr)
    ch, cw = arr.shape[:2]
    yy, xx = np.mgrid[0:ch, 0:cw].astype(np.float32)
    yy *= H / ch; xx *= W / cw
    light = 1.06 - 0.10 * (yy / H) - 0.05 * (xx / W) + 0.05 * np.exp(-((xx - 300) ** 2 + (yy - 80) ** 2) / 90000)
    arr *= light[..., None]
    grain = np.random.default_rng(3).normal(0, 3.5, (ch, cw, 1)).astype(np.float32)
    return Image.fromarray(np.clip(arr + grain, 0, 255).astype(np.uint8))


def camera(img, t, total, idx):
    """Slow push-in (or pull-out on odd scenes) toward the action."""
    k = ease(t / max(total, 1e-6))
    z = 1.18 + 0.12 * (k if idx % 2 == 0 else 1 - k)
    cx, cy = 680 + math.sin(t * 0.15 + idx) * 20, 350
    hw, hh = W / 2 / z, H / 2 / z
    cx = min(max(cx, hw), W - hw); cy = min(max(cy, hh), H - hh)
    return img.resize((W, H), Image.BILINEAR, box=tuple(v * SS for v in (cx - hw, cy - hh, cx + hw, cy + hh)))


def render_scene(job):
    idx, scene, nframes, cues, env, path = job
    bg = scene["bg"]
    look = SCENE_LOOK[idx]
    base = stylize(bg_image(bg, idx))
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "veryfast", "-crf", "24",
           "-pix_fmt", "yuv420p", path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    actions = scene["actions"]
    # start time of each run of identical actions, so every move begins at its own frame 0
    line_act = [actions[i % len(actions)] for i in range(len(cues))]
    starts = [0.0] * len(cues)
    for i in range(1, len(cues)):
        starts[i] = starts[i - 1] if line_act[i] == line_act[i - 1] else cues[i][0] - LINE_GAP * 0.5
    global TWEEN
    for fi in range(nframes):
        t = fi / FPS
        line_i = 0
        text = None
        for i, (a, b, txt) in enumerate(cues):
            if t >= a:
                line_i = i
            if a <= t < b + LINE_GAP * 0.8:
                text = txt
        action = actions[line_i % len(actions)]
        img = base.copy()
        d = SDraw(img)
        draw_dynamic_bg(d, bg, t, idx, look)
        extras(d, bg, idx, t, look, action)
        mouth = min(1.0, env[min(fi, len(env) - 1)] * 6)
        seg0 = starts[line_i]
        tl = t - seg0
        j = next((i for i in range(line_i, -1, -1) if starts[i] < seg0), None) if seg0 > 0 else None
        prev = line_act[j] if j is not None else None
        no_body = {"sleep"} if bg != "plane" else set()
        if prev and tl < TWEEN_TIME and prev not in no_body and action not in no_body:
            scratch = img.copy()
            TWEEN = dict(mode="record", active=True, rec=None)
            act(SDraw(scratch), prev, t - starts[j], look, bg, mouth, idx)
            TWEEN = dict(mode="blend", active=True, rec=TWEEN["rec"], k=ease(tl / TWEEN_TIME))
            act(d, action, tl, look, bg, mouth, idx)
            TWEEN = None
        else:
            act(d, action, tl, look, bg, mouth, idx)
        foreground(d, bg)
        img = camera(img, t, nframes / FPS, idx)
        d = ImageDraw.Draw(img, "RGBA")
        if idx == 0:
            intro_card(d, t)
        chapter_card(d, scene["title"], t)
        watermark(d)
        subtitle(d, text)
        proc.stdin.write(img.tobytes())
    proc.stdin.close()
    proc.wait()
    return path


# -------------------------------------------------------------------- audio

def tts(text, path):
    raw = path + ".raw.wav"
    subprocess.run(["espeak-ng", "-v", VOICE, "-s", str(SPEED), "-w", raw, text], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-ar", str(SR), "-ac", "1",
                    "-af", "highpass=f=70,acompressor=threshold=-18dB:ratio=3,volume=1.6", path], check=True)
    with wave.open(path) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    return data


def music(total):
    n = int(total * SR)
    out = np.zeros(n, dtype=np.float32)
    bpm = 84
    beat = 60 / bpm
    chords = [[57, 60, 64, 67], [53, 57, 60, 64], [48, 52, 55, 59], [55, 59, 62, 65]]
    bar = beat * 4
    tt = np.arange(int(bar * SR)) / SR
    rng = np.random.default_rng(1)
    pads = []
    for ch in chords:
        env = np.minimum(1, tt / 0.3) * np.minimum(1, (bar - tt) / 0.4)
        sig = sum(np.sin(2 * np.pi * 440 * 2 ** ((m - 69) / 12) * tt) for m in ch) / len(ch)
        bass = np.sin(2 * np.pi * 440 * 2 ** ((ch[0] - 24 - 69) / 12) * tt) * np.exp(-tt * 1.2)
        pads.append((sig * 0.35 + bass * 0.5) * env)
    kt = np.arange(int(0.35 * SR)) / SR
    kick = np.sin(2 * np.pi * (50 + 80 * np.exp(-kt * 30)) * kt) * np.exp(-kt * 9)
    hat = np.diff(rng.standard_normal(int(0.05 * SR)), prepend=0) * np.exp(-np.arange(int(0.05 * SR)) / SR * 80) * 0.15
    snare = rng.standard_normal(int(0.2 * SR)) * np.exp(-np.arange(int(0.2 * SR)) / SR * 22) * 0.3
    bi = 0
    t0 = 0.0
    while t0 < total:
        s0 = int(t0 * SR)
        p = pads[bi % 4][: max(0, n - s0)]
        out[s0:s0 + len(p)] += p
        for b in range(4):
            for which, sound in ((b in (0, 2), kick), (b in (1, 3), snare)):
                if which:
                    i = int((t0 + b * beat) * SR)
                    seg_ = sound[: max(0, n - i)]
                    out[i:i + len(seg_)] += seg_
            for hh in (0, 0.5):
                i = int((t0 + (b + hh) * beat) * SR)
                seg_ = hat[: max(0, n - i)]
                out[i:i + len(seg_)] += seg_
        t0 += bar
        bi += 1
    return out / (np.abs(out).max() + 1e-6)


def crowd(n, rng):
    x = rng.standard_normal(n).astype(np.float32)
    y = np.convolve(x, np.ones(40) / 40, mode="same")
    return y / (np.abs(y).max() + 1e-6)


def main():
    os.makedirs(OUT, exist_ok=True)
    tts_dir = os.path.join(OUT, "tts")
    os.makedirs(tts_dir, exist_ok=True)
    print("Generating narration...")
    scene_audio = []
    jobs = []
    for si, sc in enumerate(SCENES):
        clips = [tts(line, os.path.join(tts_dir, f"{si:02d}_{li:02d}.wav")) for li, line in enumerate(sc["lines"])]
        t = LEAD_IN
        cues = []
        for c, line in zip(clips, sc["lines"]):
            dur = len(c) / SR
            cues.append((t, t + dur, line))
            t += dur + LINE_GAP
        total = t + TAIL
        nframes = int(math.ceil(total * FPS))
        total = nframes / FPS
        voice = np.zeros(int(round(total * SR)), dtype=np.float32)
        for (a, _, _), c in zip(cues, clips):
            i = int(a * SR)
            voice[i:i + len(c)] += c[: len(voice) - i]
        spf = SR // FPS
        env = np.array([np.sqrt(np.mean(voice[k * spf:(k + 1) * spf] ** 2)) for k in range(nframes)])
        env = np.convolve(env, np.ones(3) / 3, mode="same")
        sm = np.zeros_like(env)
        for k in range(1, len(env)):
            rate = 0.55 if env[k] > sm[k - 1] else 0.3
            sm[k] = sm[k - 1] + (env[k] - sm[k - 1]) * rate
        env = sm
        scene_audio.append((sc["bg"], voice))
        jobs.append((si, sc, nframes, cues, env, os.path.join(OUT, f"seg_{si:02d}.mp4")))
        print(f"  scene {si:2d} {sc['bg']:9s} {total:6.1f}s")

    voice_all = np.concatenate([v for _, v in scene_audio])
    total = len(voice_all) / SR
    print(f"Total length: {total / 60:.1f} min")
    rng = np.random.default_rng(7)
    bgm = music(total + 1)[: len(voice_all)] * 0.10
    amb = np.zeros_like(voice_all)
    pos = 0
    for bg, v in scene_audio:
        if bg in ("arena", "intro"):
            amb[pos:pos + len(v)] = crowd(len(v), rng) * 0.10
        pos += len(v)
    fade = int(3 * SR)
    bgm[-fade:] *= np.linspace(1, 0, fade)
    mix = voice_all * 0.9 + bgm + amb
    mix = np.clip(mix, -1, 1)
    wav_path = os.path.join(OUT, "audio.wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((mix * 32767).astype(np.int16).tobytes())

    print("Rendering animation...")
    order = sorted(jobs, key=lambda j: -j[2])  # longest first
    with Pool(os.cpu_count()) as pool:
        for p in pool.imap_unordered(render_scene, order):
            print("  done", os.path.basename(p), flush=True)

    lst = os.path.join(OUT, "segments.txt")
    with open(lst, "w") as f:
        for j in jobs:
            f.write(f"file '{j[5]}'\n")
    final = os.path.join(OUT, "your_life_as_an_nba_player.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-i", wav_path,
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart", final],
                   check=True)
    print("Wrote", final)


if __name__ == "__main__":
    main()
