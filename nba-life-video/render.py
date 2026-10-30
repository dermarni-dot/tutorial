"""Builds the full animated video: TTS narration, music, cartoon animation, subtitles.

Usage: python3 render.py [out_dir]
Requires: espeak-ng + mbrola-us2, ffmpeg, Pillow, numpy.
"""
import math
import os
import random
import subprocess
import sys
import textwrap
import wave
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from story import CHANNEL, SCENES, TITLE

W, H = 1280, 720
FPS = 24
SR = 44100
GROUND = 545
VOICE = "mb-us2"
SPEED = int(os.environ.get("TTS_SPEED", "165"))
LEAD_IN, LINE_GAP, TAIL = 1.2, 0.45, 0.8

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "build")
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_R = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
_fonts = {}


def font(size, bold=True):
    key = (size, bold)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT_B if bold else FONT_R, size)
    return _fonts[key]


SKIN = (139, 90, 55)
HAIR = (30, 20, 15)
NAVY = (22, 40, 98)
ORANGE = (245, 130, 32)
WHITE = (245, 245, 245)
BALL = (226, 110, 30)

# Outfits: (shirt, shorts, number color, number or None)
OUTFITS = {
    "kid": ((200, 40, 40), (40, 40, 60), WHITE, "23"),
    "hs": ((30, 120, 60), (30, 120, 60), WHITE, "4"),
    "college": ((120, 20, 30), (120, 20, 30), (240, 200, 60), "11"),
    "comets": (NAVY, NAVY, ORANGE, "0"),
    "suit": ((25, 30, 60), (25, 30, 60), None, None),
    "agent": ((110, 110, 120), (110, 110, 120), None, None),
    "hoodie": ((90, 90, 100), (50, 60, 90), None, None),
    "gown": ((170, 200, 220), (170, 200, 220), None, None),
    "train": ((60, 60, 60), (20, 20, 20), ORANGE, "0"),
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
    d.ellipse([x - r, y - r, x + r, y + r], fill=BALL, outline=(60, 30, 10), width=2)
    d.line([x - r, y, x + r, y], fill=(60, 30, 10), width=2)
    d.arc([x - r * 0.5, y - r, x + r * 1.5, y + r], 120, 240, fill=(60, 30, 10), width=2)
    d.arc([x - r * 1.5, y - r, x + r * 0.5, y + r], 300, 60, fill=(60, 30, 10), width=2)


def draw_hoop(d, net_swish=0.0):
    rx, ry = RIM
    d.rectangle([rx + 40, ry - 10, rx + 60, GROUND], fill=(90, 90, 100))  # pole
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


def seg(d, a, b, w, color):
    d.line([a, b], fill=color, width=int(w))
    r = w / 2
    d.ellipse([b[0] - r, b[1] - r, b[0] + r, b[1] + r], fill=color)


def person(d, x, hip_y, s=1.0, outfit="comets", pose=None, facing=1, mouth=0.0,
           mood="happy", eyes_closed=False, head_drop=0.0, skin=SKIN, hair=HAIR):
    """Draws a cartoon person. Angles: 0 = straight down, positive = toward facing."""
    p = dict(fu=15, ff=35, bu=-10, bf=-5, ft=5, fs=0, bt=-5, bs=0)
    if pose:
        p.update(pose)
    shirt, shorts, numc, num = OUTFITS[outfit]
    f = facing
    hip = (x, hip_y)
    sh = (x, hip_y - 72 * s)
    lw = 15 * s
    pants = shorts if outfit not in ("kid", "hs", "college", "comets", "train") else skin
    # back leg + arm
    k = limb(hip, p["bt"], 50 * s, f); seg(d, hip, k, lw, shorts if pants != skin else shorts)
    a = limb(k, p["bs"], 48 * s, f); seg(d, k, a, lw * 0.9, pants)
    d.ellipse([a[0] - 6 * s, a[1] - 5 * s, a[0] + 16 * s * f if f > 0 else a[0] + 6 * s, a[1] + 6 * s] if f > 0
              else [a[0] - 16 * s, a[1] - 5 * s, a[0] + 6 * s, a[1] + 6 * s], fill=(240, 240, 240))
    e = limb(sh, p["bu"], 38 * s, f); seg(d, sh, e, lw * 0.85, shirt if outfit in ("suit", "agent", "hoodie", "gown") else skin)
    h_back = limb(e, p["bf"], 36 * s, f); seg(d, e, h_back, lw * 0.8, skin)
    # front leg
    k2 = limb(hip, p["ft"], 50 * s, f); seg(d, hip, k2, lw, shorts)
    a2 = limb(k2, p["fs"], 48 * s, f); seg(d, k2, a2, lw * 0.9, pants)
    d.ellipse([a2[0] - 6 * s, a2[1] - 5 * s, a2[0] + 16 * s, a2[1] + 6 * s] if f > 0
              else [a2[0] - 16 * s, a2[1] - 5 * s, a2[0] + 6 * s, a2[1] + 6 * s], fill=(240, 240, 240))
    # shorts block + torso
    d.rounded_rectangle([x - 20 * s, hip_y - 14 * s, x + 20 * s, hip_y + 22 * s], 5, fill=shorts)
    d.polygon([(x - 24 * s, sh[1] - 4 * s), (x + 24 * s, sh[1] - 4 * s),
               (x + 20 * s, hip_y + 2 * s), (x - 20 * s, hip_y + 2 * s)], fill=shirt)
    if outfit in ("suit", "agent"):
        d.polygon([(x - 6 * s, sh[1] - 4 * s), (x + 6 * s, sh[1] - 4 * s), (x, sh[1] + 26 * s)], fill=WHITE)
        d.polygon([(x - 3 * s, sh[1]), (x + 3 * s, sh[1]), (x + 4 * s, sh[1] + 22 * s), (x, sh[1] + 28 * s),
                   (x - 4 * s, sh[1] + 22 * s)], fill=(200, 40, 40))
    if num:
        fs = font(max(10, int(26 * s)))
        d.text((x, sh[1] + 30 * s), num, font=fs, fill=numc, anchor="mm")
    # front arm
    e2 = limb(sh, p["fu"], 38 * s, f); seg(d, sh, e2, lw * 0.85, shirt if outfit in ("suit", "agent", "hoodie", "gown") else skin)
    hand = limb(e2, p["ff"], 36 * s, f); seg(d, e2, hand, lw * 0.8, skin)
    # head
    hx = x + f * head_drop * 8 * s
    hy = sh[1] - 30 * s + head_drop * 10 * s
    r = 24 * s
    d.rectangle([x - 6 * s, sh[1] - 12 * s, x + 6 * s, sh[1]], fill=skin)
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=skin)
    d.chord([hx - r, hy - r - 2 * s, hx + r, hy + r * 0.4], 180, 360, fill=hair)
    d.ellipse([hx - f * r - 4 * s, hy - 4 * s, hx - f * r + 4 * s, hy + 6 * s], fill=skin)  # ear
    ex = hx + f * 10 * s
    ey = hy - 2 * s + head_drop * 3 * s
    if eyes_closed:
        d.line([ex - 5 * s, ey, ex + 5 * s, ey], fill=(20, 20, 20), width=max(1, int(2 * s)))
    else:
        d.ellipse([ex - 4 * s, ey - 4 * s, ex + 4 * s, ey + 4 * s], fill=WHITE)
        d.ellipse([ex + f * 1 * s - 2 * s, ey - 2 * s, ex + f * 1 * s + 2.5 * s, ey + 2.5 * s], fill=(20, 20, 20))
        d.line([ex - 6 * s, ey - 9 * s - (3 * s if mood == "sad" else 0) * 0, ex + 6 * s,
                ey - 8 * s + (2 * s if mood == "sad" else 0)], fill=hair, width=max(1, int(2 * s)))
    mx, my = hx + f * 9 * s, hy + 12 * s
    if mouth > 0.08:
        mh = 2 + mouth * 9 * s
        d.ellipse([mx - 6 * s, my - mh / 2, mx + 6 * s, my + mh / 2], fill=(90, 20, 30))
    elif mood == "sad":
        d.arc([mx - 6 * s, my, mx + 6 * s, my + 8 * s], 200, 340, fill=(60, 20, 20), width=max(1, int(2 * s)))
    else:
        d.arc([mx - 7 * s, my - 6 * s, mx + 7 * s, my + 4 * s], 20, 160, fill=(60, 20, 20), width=max(1, int(2 * s)))
    return dict(hand=hand, back_hand=h_back, head=(hx, hy), sh=sh)


def stand_hip(s):
    return GROUND - 96 * s


# ----------------------------------------------------------------- backgrounds

def sky(d, top, bot, y1=GROUND):
    for y in range(0, y1, 4):
        t = y / y1
        c = tuple(int(lerp(top[i], bot[i], t)) for i in range(3))
        d.rectangle([0, y, W, y + 4], fill=c)


def bg_image(bg, idx):
    img = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(img)
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
        d.ellipse([150, GROUND - 40, 520, GROUND + 40], fill=WHITE)  # table
        d.rectangle([150, GROUND, 520, GROUND + 110], fill=(230, 230, 230))
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
        d.rectangle([60, 260, 80, GROUND], fill=(120, 80, 50))
        for a in range(0, 360, 60):
            r = math.radians(a)
            d.line([70, 260, 70 + 110 * math.cos(r), 260 + 50 * math.sin(r) + 20], fill=(40, 140, 50), width=18)
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
    return img


def draw_dynamic_bg(d, bg, t, idx, look):
    if bg == "arena" or bg == "intro":
        rnd = random.Random(int(t * 8) + idx * 1000)
        for _ in range(10):
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
            x = 40 + i * 300
            d.rounded_rectangle([x, 330, x + 120, GROUND - 40], 20, fill=(120, 70, 40))
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
        p = tri(t, 9.0)
        x = 640 - span / 2 + span * p
        facing = 1 if ((t / 9.0) % 1.0) < 0.5 else -1
        w = math.sin(t * 6)
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
        cyc = 2.6
        p = t % cyc
        x = base_x + 40
        net = 0.0
        if p < 0.7:
            k = ease(p / 0.7)
            pose = dict(fu=lerp(30, 160, k), ff=lerp(80, 150, k), bu=lerp(-10, 150, k), bf=lerp(20, 170, k),
                        ft=lerp(25, 5, k), fs=lerp(-25, 0, k), bt=lerp(15, -5, k), bs=lerp(-25, 0, k))
            dy = lerp(14, -10, k) * s
            r = person(d, x, hip_y + dy, s, outfit, pose=pose, mouth=speaking)
            draw_ball(d, r["hand"][0], r["hand"][1] - 12 * s, 13 * s)
        else:
            jump = max(0, math.sin(min(1, (p - 0.7) / 0.6) * math.pi)) * 30 * s
            pose = dict(fu=170, ff=200, bu=150, bf=175, ft=5, fs=10, bt=-8, bs=5)
            r = person(d, x, hip_y - jump, s, outfit, pose=pose, mouth=speaking)
            q = (p - 0.7) / 1.1
            sx, sy = x + 30 * s, hip_y - 190 * s
            if q < 1:
                bx = lerp(sx, RIM[0] - 6, q)
                by = lerp(sy, RIM[1] - 14, q) - math.sin(q * math.pi) * 170
                draw_ball(d, bx, by)
            else:
                q2 = (p - 1.8) / 0.8
                draw_ball(d, RIM[0] - 6 + q2 * 10, lerp(RIM[1] - 10, GROUND - 13, q2 * q2) if q2 < 1 else GROUND - 13)
                net = max(0, 1 - q2)
        draw_hoop(d, net)
        return
    elif action == "dunk":
        cyc = 3.2
        p = t % cyc
        net = 0.0
        x0, x1 = 380, RIM[0] - 45 * s
        if p < 1.3:
            k = p / 1.3
            x = lerp(x0, x1 - 40, ease(k))
            w = math.sin(t * 9)
            pose = dict(ft=30 * w, fs=30 * w - 20, bt=-30 * w, bs=-30 * w - 20, fu=40, ff=70, bu=25 * w, bf=40)
            r = person(d, x, hip_y, s, outfit, pose=pose, mouth=speaking)
            draw_ball(d, r["hand"][0], r["hand"][1], 13 * s)
        elif p < 2.0:
            k = (p - 1.3) / 0.7
            x = lerp(x1 - 40, x1, k)
            lift = math.sin(k * math.pi / 2) * (hip_y - (RIM[1] + 140 * s) + 0)
            pose = dict(fu=lerp(60, 175, k), ff=lerp(90, 178, k), bu=-20, bf=-10, ft=40, fs=-30, bt=-10, bs=-40)
            r = person(d, x, hip_y - lift, s, outfit, pose=pose, mouth=speaking)
            draw_ball(d, r["hand"][0], r["hand"][1] - 12, 13 * s)
        elif p < 2.4:
            lift = hip_y - (RIM[1] + 140 * s)
            pose = dict(fu=178, ff=178, bu=-20, bf=-10, ft=10, fs=-10, bt=-5, bs=-20)
            draw_ball(d, RIM[0] - 6, RIM[1] + 30 + (p - 2.0) * 300)
            draw_hoop(d, 1.0)
            person(d, x1, hip_y - lift + 10, s, outfit, pose=pose, mouth=speaking)
            return
        else:
            k = (p - 2.4) / 0.8
            lift = (hip_y - (RIM[1] + 140 * s)) * (1 - ease(k * 1.6))
            pose = dict(fu=150, ff=170, bu=150, bf=170, ft=10, fs=0, bt=-10, bs=0)
            person(d, x1 - 20, hip_y - max(0, lift), s, outfit, pose=pose, mouth=speaking)
            draw_ball(d, RIM[0] + 20 + k * 60, GROUND - 13 - abs(math.sin(k * 8)) * 60 * (1 - k))
            net = max(0, 1 - k)
        draw_hoop(d, net)
        return
    elif action == "sit":
        cx = base_x if bg != "stage" else 330
        if bg not in ("stage", "press", "plane"):
            d.rectangle([cx - 35, GROUND - 105, cx + 30, GROUND - 92], fill=(110, 70, 40))
            d.rectangle([cx - 35, GROUND - 92, cx - 25, GROUND], fill=(110, 70, 40))
            d.rectangle([cx + 20, GROUND - 92, cx + 30, GROUND], fill=(110, 70, 40))
        if bg == "plane":
            d.rounded_rectangle([cx - 60, GROUND - 220, cx - 10, GROUND - 40], 15, fill=(120, 70, 40))
            d.rounded_rectangle([cx - 60, GROUND - 110, cx + 50, GROUND - 60], 15, fill=(120, 70, 40))
        hy = GROUND - 100 * s
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
            d.rounded_rectangle([cx - 60, GROUND - 220, cx - 10, GROUND - 40], 15, fill=(120, 70, 40))
            pose = dict(ft=85, fs=0, bt=80, bs=-5, fu=60, ff=110, bu=50, bf=100)
            person(d, cx, GROUND - 100 * s, s, outfit, pose=pose, eyes_closed=True, head_drop=0.6)
            zx, zy = cx + 30, GROUND - 280
        else:
            bx = 200
            d.rectangle([bx, GROUND - 120, bx + 420, GROUND - 60], fill=(110, 70, 40))
            d.rectangle([bx, GROUND - 200, bx + 25, GROUND], fill=(110, 70, 40))
            d.rectangle([bx + 395, GROUND - 160, bx + 420, GROUND], fill=(110, 70, 40))
            d.ellipse([bx + 25, GROUND - 160, bx + 120, GROUND - 115], fill=WHITE)
            hx, hy = bx + 80, GROUND - 150
            d.ellipse([hx - 24, hy - 24, hx + 24, hy + 24], fill=SKIN)
            d.chord([hx - 24, hy - 26, hx + 24, hy + 10], 180, 360, fill=HAIR)
            d.line([hx + 4, hy, hx + 14, hy], fill=(20, 20, 20), width=2)
            breathe = math.sin(t * 2) * 4
            d.rounded_rectangle([bx + 100, GROUND - 150 - breathe, bx + 400, GROUND - 105], 20, fill=(60, 90, 160))
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


def extras(d, bg, idx, t, look, action):
    """Background characters per scene."""
    if bg == "stage":
        g = math.sin(t * 2)
        person(d, 955, stand_hip(1.0) - 10, 1.0, "suit", pose=dict(fu=60 + 10 * g, ff=90), facing=-1,
               skin=(230, 190, 160), hair=(160, 160, 160), mouth=0.2 * (g > 0.6))
        person(d, 230, GROUND - 100, 0.95, "suit", pose=dict(ft=85, bt=80, fu=40, ff=70), skin=(120, 75, 45),
               hair=(20, 10, 10))
    elif bg == "locker" and action != "walk":
        person(d, 950, stand_hip(1.15), 1.15, "comets", pose=dict(fu=50, ff=120), facing=-1,
               skin=(90, 55, 35), hair=(10, 10, 10))
        d.text((950, stand_hip(1.15) - 140), "Big Tony", font=font(18), fill=WHITE, anchor="mm")
    elif bg == "arena" and action in ("dribble", "sad"):
        g = math.sin(t * 3)
        person(d, 820, stand_hip(1.0) + 8, 1.0, "college", pose=dict(fu=100 + 20 * g, ff=150, bu=80 - 20 * g, bf=120,
               ft=25, fs=-20, bt=-20, bs=10), facing=-1, skin=(220, 180, 150))
    elif bg == "driveway" and idx == 15:
        for i, kx in enumerate((150, 270, 390)):
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
        d.text((740, stand_hip(1.0) - 130), "Agent", font=font(18), fill=(30, 30, 30), anchor="mm")
    elif bg == "hospital" and action != "hurt":
        person(d, 1000, stand_hip(1.0), 1.0, "gown", pose=dict(fu=40, ff=90), facing=-1,
               skin=(230, 190, 160), hair=(90, 60, 30))
        d.text((1000, stand_hip(1.0) - 130), "Doctor", font=font(18), fill=(40, 40, 40), anchor="mm")


# ------------------------------------------------------------------ overlays

def subtitle(d, text):
    if not text:
        return
    lines = textwrap.wrap(text, 58)
    fs = font(30)
    lh = 40
    h = lh * len(lines) + 20
    y0 = H - h - 14
    d.rounded_rectangle([90, y0, W - 90, y0 + h], 14, fill=(10, 10, 15))
    for i, ln in enumerate(lines):
        d.text((W / 2, y0 + 10 + lh * i + lh / 2), ln, font=fs, fill=(255, 235, 120), anchor="mm")


def chapter_card(d, title, t):
    if not title or t > 4.5:
        return
    k = ease(t / 0.5) * (1 - ease((t - 4.0) / 0.5))
    w = 40 + font(44).getlength(title)
    x = lerp(-w, 0, k)
    d.rectangle([x, 120, x + w + 30, 200], fill=ORANGE)
    d.rectangle([x, 200, x + w + 30, 208], fill=NAVY)
    d.text((x + 30, 160), title, font=font(44), fill=WHITE, anchor="lm")


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

def render_scene(job):
    idx, scene, nframes, cues, env, path = job
    bg = scene["bg"]
    look = SCENE_LOOK[idx]
    base = bg_image(bg, idx)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "veryfast", "-crf", "24",
           "-pix_fmt", "yuv420p", path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    actions = scene["actions"]
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
        d = ImageDraw.Draw(img)
        draw_dynamic_bg(d, bg, t, idx, look)
        extras(d, bg, idx, t, look, action)
        mouth = min(1.0, env[min(fi, len(env) - 1)] * 6)
        act(d, action, t, look, bg, mouth, idx)
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
