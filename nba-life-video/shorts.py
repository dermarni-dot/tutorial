"""Builds a vertical YouTube Short (1080x1920, under 60s) from the same art as render.py.

Usage: python3 shorts.py [out_dir]
"""
import math
import os
import random
import subprocess
import sys
import wave
from multiprocessing import Pool

os.environ.setdefault("TTS_SPEED", "184")

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import render
from render import (FPS, INK, NAVY, ORANGE, RIM, SCENE_LOOK, SR, SS, W, H, WHITE, SDraw, act, bg_image,
                    crowd, draw_dynamic_bg, ease, extras, font, foreground, lerp, music, stylize, tts)

VW, VH = 1080, 1920
BOX = (40, 450, 1040, 1450)  # where the square scene sits
LEAD_IN, LINE_GAP, TAIL = 0.35, 0.18, 0.3
YELLOW = (255, 215, 60)
HOT_WORDS = {"LIKE", "SUBSCRIBE", "SWISH", "CHAMPION", "AIRBALL", "NBA", "YOU", "DUNK", "AGENT", "CUT", "LEGEND",
             "ELEVEN", "PART", "TWO"}
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "build_shorts")

# idx = which scene of the long video to borrow the look (background, outfit, extras) from
SHORT = [
    dict(idx=14, action="celebrate", level=0, name="EVERY LEVEL", cam=700, lines=[
        "Your NBA life, every level. Like, subscribe, and watch till the end.",
    ]),
    dict(idx=1, action="shoot", level=1, name="DRIVEWAY KID", lines=[
        "Level one. You shoot on a crooked hoop every night, until the street lights come on.",
    ]),
    dict(idx=2, action="sad", level=2, name="CUT FROM THE TEAM", lines=[
        "Level two. You get cut. Your mom says, paper does not decide who you become.",
    ]),
    dict(idx=3, action="dunk", level=3, name="HIGH SCHOOL STAR", lines=[
        "Level three. You grow six inches, and hit the game winner for a state title.",
    ]),
    dict(idx=4, action="meet", level=4, name="COLLEGE HOOPER", cam=650, lines=[
        "Level four. One day, an agent approaches you. He says you are ready for the league.",
    ]),
    dict(idx=5, action="celebrate", level=5, name="DRAFT PICK", lines=[
        "Level five. With the seventh pick, the Bay City Comets select. You.",
    ]),
    dict(idx=7, action="shoot", level=6, name="ROOKIE", lines=[
        "Level six. Your first NBA shot is an airball. Your second? Swish.",
    ]),
    dict(idx=12, action="hurt", level=7, name="INJURED", lines=[
        "Level seven. Torn ACL. Everybody says you are done.",
    ]),
    dict(idx=13, action="dunk", level=8, name="COMEBACK KID", lines=[
        "Level eight. Eleven months of rehab, and you dunk again.",
    ]),
    dict(idx=14, action="celebrate", level=9, name="NBA CHAMPION", cam=700, lines=[
        "Level nine. Game seven. Step back. Swish. You are a champion.",
    ]),
    dict(idx=16, action="talk", level=10, name="LEGEND", lines=[
        "Level ten. Your jersey hangs in the rafters forever.",
    ]),
    dict(idx=0, action="talk", level=11, name="LOCKED", cam=640, cta=True, tail=1.9, lines=[
        "But there is one more level.",
        "Level eleven only unlocks when you hit like, and subscribe.",
        "Part two is coming soon. Do not miss it.",
    ]),
]

# capture the main character's x so the vertical camera can follow them
CAP = {"x": None}
_orig_person = render.person


def _rec_person(d, *a, **k):
    if CAP["x"] is None:
        CAP["x"] = a[0] if a else k.get("x")
    return _orig_person(d, *a, **k)


render.person = _rec_person


# ------------------------------------------------------------------ helpers

def big_text(d, xy, text, size, fill=WHITE, stroke=8, anchor="mm"):
    d.text(xy, text, font=font(max(2, int(size))), fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=INK)


def vertical_bg(world):
    """Blurred, darkened copy of the scene filling the 9:16 frame, plus the card shadow."""
    small = world.resize((W // 2, H // 2), Image.BILINEAR)
    sc = VH / small.height
    cover = small.resize((int(small.width * sc), VH), Image.BILINEAR)
    x0 = (cover.width - VW) // 2
    img = cover.crop((x0, 0, x0 + VW, VH)).filter(ImageFilter.GaussianBlur(14))
    arr = np.asarray(img).astype(np.float32) * 0.45 + np.array(NAVY, np.float32) * 0.25
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle([BOX[0] + 10, BOX[1] + 16, BOX[2] + 10, BOX[3] + 16], 44, fill=(0, 0, 0, 120))
    return img


def box_mask():
    m = Image.new("L", (BOX[2] - BOX[0], BOX[3] - BOX[1]), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, m.width - 1, m.height - 1], 40, fill=255)
    return m


def chunks(cues):
    """Split each narration line into 2-3 word caption chunks timed by length."""
    out = []
    for a, b, text in cues:
        words = text.upper().replace(",", "").split()
        groups, i = [], 0
        while i < len(words):
            n = 2 if len(" ".join(words[i:i + 3])) > 16 else 3
            groups.append(words[i:i + n]); i += n
        total = sum(len(" ".join(g)) + 2 for g in groups)
        t = a
        for g in groups:
            dur = (b - a) * (len(" ".join(g)) + 2) / total
            out.append((t, t + dur, g))
            t += dur
    return out


def caption(d, chunk, t0, t):
    if not chunk:
        return
    pop = 1 + 0.18 * (1 - ease((t - t0) / 0.12))
    size = 82 * pop
    words = chunk
    f = font(int(size))
    widths = [f.getlength(w) for w in words]
    gap = f.getlength(" ")
    total = sum(widths) + gap * (len(words) - 1)
    if total > 980:
        size *= 980 / total
        f = font(int(size)); widths = [f.getlength(w) for w in words]; gap = f.getlength(" ")
        total = sum(widths) + gap * (len(words) - 1)
    x = VW / 2 - total / 2
    for w, wd in zip(words, widths):
        hot = w.strip(".!?") in HOT_WORDS
        d.text((x, 1585), w, font=f, fill=YELLOW if hot else WHITE, anchor="lm", stroke_width=9, stroke_fill=INK)
        x += wd + gap


def header(d, sc, t, unlocked):
    lvl, name = sc["level"], sc["name"]
    k = ease(t / 0.35)
    pop = 1 + 0.35 * (1 - k)
    if lvl == 0:
        big_text(d, (VW / 2, 170), "YOUR LIFE AS AN NBA PLAYER", 50)
        big_text(d, (VW / 2, 285), name, 120 * pop, ORANGE, 10)
        pulse = 1 + 0.06 * math.sin(t * 8)
        w = 520 * pulse
        d.rounded_rectangle([VW / 2 - w / 2, 350, VW / 2 + w / 2, 420], 35, fill=(230, 40, 40), outline=INK, width=4)
        big_text(d, (VW / 2, 385), "WATCH TILL THE END", 40 * pulse, WHITE, 4)
        return
    big_text(d, (VW / 2, 150), f"LEVEL {lvl}", 120 * pop, ORANGE, 10)
    if lvl == 11:
        label = "UNLOCKED!" if unlocked else "LOCKED"
        big_text(d, (VW / 2, 265), label, 66, (120, 230, 120) if unlocked else WHITE, 7)
        lock(d, VW / 2 + 345, 140, unlocked)
    else:
        big_text(d, (VW / 2, 265), name, 66 if len(name) < 14 else 58, WHITE, 7)
    # level progress dots
    for i in range(1, 12):
        x = VW / 2 + (i - 6) * 70
        on = i <= lvl and (i < 11 or unlocked)
        r = 17 if i == lvl else 13
        d.ellipse([x - r, 375 - r, x + r, 375 + r], fill=ORANGE if on else (70, 70, 90), outline=INK, width=3)


def lock(d, x, y, unlocked):
    d.rounded_rectangle([x - 34, y - 6, x + 34, y + 50], 10, fill=(245, 205, 90), outline=INK, width=4)
    if unlocked:
        d.arc([x - 24, y - 52, x + 24, y + 4], 180, 300, fill=INK, width=9)
    else:
        d.arc([x - 24, y - 46, x + 24, y + 10], 180, 360, fill=INK, width=9)
    d.ellipse([x - 7, y + 12, x + 7, y + 26], fill=INK)


def thumbs_up(d, cx, cy, s, filled):
    col = WHITE if not filled else (60, 140, 255)
    d.rounded_rectangle([cx - 46 * s, cy - 6 * s, cx - 26 * s, cy + 46 * s], 6 * s, fill=col, outline=INK, width=4)
    d.rounded_rectangle([cx - 22 * s, cy - 10 * s, cx + 40 * s, cy + 46 * s], 14 * s, fill=col, outline=INK, width=4)
    d.rounded_rectangle([cx - 14 * s, cy - 56 * s, cx + 8 * s, cy - 4 * s], 10 * s, fill=col, outline=INK, width=4)
    for i in range(3):
        d.line([cx + 4 * s, cy + (6 + i * 13) * s, cx + 38 * s, cy + (6 + i * 13) * s], fill=INK, width=3)


def cta_overlay(d, t, t_like, t_click):
    """Like button pop, then a cursor taps SUBSCRIBE and it turns gray."""
    if t > t_like:
        k = ease((t - t_like) / 0.3)
        s = 0.2 + 1.0 * k + 0.12 * math.sin(min(1, (t - t_like) / 0.5) * math.pi)
        liked = t > t_like + 0.5
        d.ellipse([170 - 95 * s, 1120 - 95 * s, 170 + 95 * s, 1120 + 95 * s], fill=(255, 255, 255, 235), outline=INK, width=5)
        thumbs_up(d, 170, 1130, s * 0.9, liked)
        big_text(d, (170, 1250), "LIKE", 44 * s, YELLOW if liked else WHITE, 5)
    if t > t_click - 1.2:
        k = ease((t - (t_click - 1.2)) / 0.35)
        done = t > t_click
        y = lerp(1600, 1270, k)
        squash = 0.92 if t_click < t < t_click + 0.12 else 1.0
        w, h = 560 * squash, 120 * squash
        cx = 620
        d.rounded_rectangle([cx - w / 2, y - h / 2, cx + w / 2, y + h / 2], 60,
                            fill=(90, 90, 95) if done else (230, 30, 35), outline=INK, width=5)
        big_text(d, (cx + 30, y), "SUBSCRIBED" if done else "SUBSCRIBE", 56 * squash, WHITE, 5)
        bx, by = cx - w / 2 + 62, y  # bell
        ring = math.sin((t - t_click) * 30) * 14 * max(0, 1 - (t - t_click) / 0.8) if done else 0
        d.pieslice([bx - 26, by - 30, bx + 26, by + 26], 180 + ring, 360 + ring, fill=WHITE, outline=INK, width=3)
        d.rectangle([bx - 26, by - 4, bx + 26, by + 14], fill=WHITE, outline=INK, width=3)
        d.ellipse([bx - 7, by + 12, bx + 7, by + 26], fill=WHITE, outline=INK, width=3)
        # tapping hand cursor
        if t < t_click + 0.6:
            m = ease((t - (t_click - 0.9)) / 0.8)
            hx, hy = lerp(980, cx + 120, m), lerp(1760, y + 25, m)
            press = 10 if abs(t - t_click) < 0.1 else 0
            d.ellipse([hx - 30 + press, hy - 30 + press, hx + 30 - press, hy + 30 - press], fill=(255, 255, 255, 90))
            d.rounded_rectangle([hx - 10, hy - 4, hx + 10, hy + 50], 9, fill=(250, 220, 190), outline=INK, width=3)
            d.rounded_rectangle([hx - 4, hy + 30, hx + 46, hy + 92], 18, fill=(250, 220, 190), outline=INK, width=3)
    if t > t_click + 0.4:
        a = ease((t - t_click - 0.4) / 0.4)
        big_text(d, (VW / 2, 600), "PART 2", 110 * a, YELLOW, 10)
        big_text(d, (VW / 2, 700), "COMING SOON", 64 * a, WHITE, 7)


# ------------------------------------------------------------------- render

def render_segment(job):
    si, sc, nframes, cues, env, path, t_like, t_click = job
    idx = sc["idx"]
    look = SCENE_LOOK[idx]
    bg = render.SCENES[idx]["bg"]
    base = stylize(bg_image(bg, idx))
    vbg = vertical_bg(base.resize((W, H), Image.BILINEAR))
    mask = box_mask()
    caps = chunks(cues)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{VW}x{VH}",
           "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "veryfast", "-crf", "21",
           "-pix_fmt", "yuv420p", path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    cam = None
    total = nframes / FPS
    for fi in range(nframes):
        t = fi / FPS
        img = base.copy()
        d = SDraw(img)
        draw_dynamic_bg(d, bg, t, idx, look)
        extras(d, bg, idx, t, look, sc["action"])
        CAP["x"] = None
        act(d, sc["action"], t, look, bg, min(1.0, env[min(fi, len(env) - 1)] * 6), idx)
        foreground(d, bg)
        px = CAP["x"] if CAP["x"] is not None else 640
        target = sc.get("cam") or ((px + RIM[0]) / 2 if sc["action"] in ("shoot", "dunk") else px)
        cam = target if cam is None else cam + (target - cam) * (1 - 0.92 ** (60 / FPS))
        k = ease(t / max(total, 1e-6))
        side = lerp(700, 630, k)
        cy = lerp(355, 385, k)
        cx = min(max(cam, side / 2), W - side / 2)
        box = tuple(v * SS for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))
        square = img.resize((BOX[2] - BOX[0], BOX[3] - BOX[1]), Image.BILINEAR, box=box)
        frame = vbg.copy()
        frame.paste(square, (BOX[0], BOX[1]), mask)
        fd = ImageDraw.Draw(frame, "RGBA")
        fd.rounded_rectangle(BOX, 40, outline=ORANGE, width=8)
        unlocked = sc.get("cta") and t > t_click
        header(fd, sc, t, unlocked)
        cur = next((c for c in caps if c[0] <= t < c[1] + 0.05), None)
        if cur:
            caption(fd, cur[2], cur[0], t)
        if sc.get("cta"):
            cta_overlay(fd, t, t_like, t_click)
        proc.stdin.write(frame.tobytes())
    proc.stdin.close()
    proc.wait()
    return path


def whoosh(rng):
    n = int(0.4 * SR)
    x = rng.standard_normal(n).astype(np.float32)
    x = np.convolve(x, np.ones(12) / 12, mode="same")
    env = np.sin(np.linspace(0, math.pi, n)) ** 2
    return x * env * 0.9


def ding():
    t = np.arange(int(0.8 * SR)) / SR
    return ((np.sin(2 * math.pi * 1320 * t) + 0.6 * np.sin(2 * math.pi * 1980 * t)) * np.exp(-t * 6) * 0.35).astype(np.float32)


def main():
    os.makedirs(os.path.join(OUT, "tts"), exist_ok=True)
    rng = np.random.default_rng(5)
    jobs, voice_parts, sfx_marks = [], [], []
    offset = 0.0
    for si, sc in enumerate(SHORT):
        clips = [tts(line, os.path.join(OUT, "tts", f"{si:02d}_{li}.wav")) for li, line in enumerate(sc["lines"])]
        t = LEAD_IN
        cues = []
        for c, line in zip(clips, sc["lines"]):
            cues.append((t, t + len(c) / SR, line))
            t += len(c) / SR + LINE_GAP
        total = t + sc.get("tail", TAIL)
        nframes = int(math.ceil(total * FPS))
        total = nframes / FPS
        voice = np.zeros(int(round(total * SR)), np.float32)
        for (a, _, _), c in zip(cues, clips):
            i = int(a * SR)
            voice[i:i + len(c)] += c[: len(voice) - i]
        spf = SR // FPS
        env = np.array([np.sqrt(np.mean(voice[k * spf:(k + 1) * spf] ** 2)) for k in range(nframes)])
        sm = np.zeros_like(env)
        for k in range(1, len(env)):
            rate = 1 - (1 - (0.55 if env[k] > sm[k - 1] else 0.3)) ** (30 / FPS)
            sm[k] = sm[k - 1] + (env[k] - sm[k - 1]) * rate
        t_like = t_click = 1e9
        if sc.get("cta"):
            t_like = cues[1][0] + 0.9
            t_click = cues[1][0] + 2.3
            sfx_marks.append((offset + t_click, "ding"))
        sfx_marks.append((offset, "whoosh"))
        jobs.append((si, sc, nframes, cues, sm, os.path.join(OUT, f"seg_{si:02d}.mp4"), t_like, t_click))
        voice_parts.append((render.SCENES[sc["idx"]]["bg"], voice))
        offset += total
        print(f"  {si:2d} level {sc['level']:2d} {total:5.2f}s")
    voice_all = np.concatenate([v for _, v in voice_parts])
    print(f"Total: {len(voice_all) / SR:.1f}s")

    bgm = music(len(voice_all) / SR + 1)[: len(voice_all)] * 0.12
    amb = np.zeros_like(voice_all)
    pos = 0
    for bg, v in voice_parts:
        if bg in ("arena", "intro"):
            amb[pos:pos + len(v)] = crowd(len(v), rng) * 0.08
        pos += len(v)
    sfx = np.zeros_like(voice_all)
    for when, kind in sfx_marks:
        s = whoosh(rng) * 0.25 if kind == "whoosh" else ding()
        i = int(when * SR)
        sfx[i:i + len(s)] += s[: max(0, len(sfx) - i)]
    fade = int(1.0 * SR)
    bgm[-fade:] *= np.linspace(1, 0, fade)
    mix = np.clip(voice_all * 0.95 + bgm + amb + sfx, -1, 1)
    wav_path = os.path.join(OUT, "audio.wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((mix * 32767).astype(np.int16).tobytes())

    with Pool(os.cpu_count()) as pool:
        for p in pool.imap_unordered(render_segment, sorted(jobs, key=lambda j: -j[2])):
            print("  done", os.path.basename(p), flush=True)
    lst = os.path.join(OUT, "segments.txt")
    with open(lst, "w") as f:
        for j in jobs:
            f.write(f"file '{j[5]}'\n")
    final = os.path.join(OUT, "your_life_as_an_nba_player_short.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-i", wav_path,
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", final],
                   check=True)
    print("Wrote", final)


if __name__ == "__main__":
    main()
