"""Gait curves of v9_anim's gait_<clip>.json series (before / after) against a human walk cycle.

    python3 tools/sim/v9_gait_plot.py OUT.png BEFORE.json AFTER.json [--title T]

One gait cycle of each run (left heel strike to the next: the left sole coming down onto the floor), joint angles in
degrees over % of the cycle: knee flexion, thigh angle (from vertical, + forward), foot pitch (+ toes up), shoulder
(upper arm in the chest's frame, + forward), elbow flexion, pelvis / chest yaw, and the pelvis height. The grey
dots: a human walk cycle (Winter's normal-cadence data, rounded) where one applies.
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

HUMAN = {
    "kneeL": [(0, 5), (15, 18), (40, 5), (60, 38), (72, 62), (87, 30), (100, 5)],
    "thighL": [(0, 25), (30, 2), (50, -12), (60, -8), (75, 15), (88, 25), (100, 25)],
    "footPitchL": [(0, 22), (8, 0), (30, 0), (50, -12), (62, -45), (75, -10), (90, 8), (100, 22)],
    "shoulderL": [(0, -20), (50, 10), (100, -20)],
    "elbowL": [(0, 20), (50, 40), (100, 20)],
}


def cycle(path):
    d = json.load(open(path))
    S = [r for r in d["series"] if r["t"] > 2.4]
    # (heel strikes: the sole down under 0.02 after being up over 0.08 - hysteresis, a stance foot hovers by a hair)
    hs, up = [], False
    for i, r in enumerate(S):
        if r["soleL"] > 0.08:
            up = True
        elif up and r["soleL"] < 0.02:
            hs.append(i)
            up = False
    if len(hs) < 2:
        return None, d
    a, b = hs[-2], hs[-1]
    C = S[a:b + 1]
    x = [100 * i / (len(C) - 1) for i in range(len(C))]
    return (x, C), d


FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def panel(dr, box, title, series, human, font, small):
    """one chart in box (x0, y0, x1, y1): series = [(label, colour, xs, ys, dashed)], human = [(x, y)]"""
    x0, y0, x1, y1 = box
    dr.rectangle(box, outline=(200, 200, 200), fill=(255, 255, 255))
    dr.text((x0 + 6, y0 + 4), title, fill=(20, 20, 20), font=font)
    px0, py0, px1, py1 = x0 + 46, y0 + 26, x1 - 8, y1 - 24
    ys = [y for _, _, _, Y, _ in series for y in Y] + [y for _, y in human]
    if not ys:
        return
    lo, hi = min(ys), max(ys)
    pad = (hi - lo) * 0.08 + 1e-3
    lo, hi = lo - pad, hi + pad
    def P(x, y):
        return px0 + (px1 - px0) * x / 100, py1 - (py1 - py0) * (y - lo) / (hi - lo)
    for i in range(5):
        v = lo + (hi - lo) * i / 4
        _, yy = P(0, v)
        dr.line([(px0, yy), (px1, yy)], fill=(230, 230, 230))
        dr.text((x0 + 4, yy - 6), f"{v:.2f}" if hi - lo < 3 else f"{v:.0f}", fill=(90, 90, 90), font=small)
    for xv in (0, 25, 50, 75, 100):
        xx, _ = P(xv, lo)
        dr.line([(xx, py0), (xx, py1)], fill=(235, 235, 235))
        dr.text((xx - 8, py1 + 4), f"{xv}%", fill=(90, 90, 90), font=small)
    for x, y in human:
        cx, cy = P(x, y)
        dr.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(140, 140, 140))
    ly = y0 + 4
    for lab, col, X, Y, dashed in series:
        pts = [P(x, y) for x, y in zip(X, Y)]
        if dashed:
            for i in range(0, len(pts) - 1, 2):
                dr.line([pts[i], pts[i + 1]], fill=col, width=2)
        else:
            dr.line(pts, fill=col, width=3)
        tw = dr.textlength(lab, font=small)
        dr.text((x1 - tw - 8, ly), lab, fill=col, font=small)
        ly += 13


def main():
    args = sys.argv[1:]
    out = args[0]
    title = None
    if "--title" in args:
        i = args.index("--title")
        title = args[i + 1]
        args = args[:i] + args[i + 2:]
    runs = [("before", args[1], (192, 80, 77)), ("after", args[2], (46, 117, 182))]
    keys = [("kneeL", "knee flexion (deg)"), ("thighL", "thigh from vertical (deg, + forward)"), ("footPitchL", "foot pitch (deg, + toes up)"),
            ("shoulderL", "shoulder (deg, + forward)"), ("elbowL", "elbow flexion (deg)"), ("pelvisYaw", "pelvis (solid) / chest (dashed) yaw"),
            ("pelvisY", "pelvis height (studs)"), ("soleL", "left sole height (studs; < 0 = in the floor)")]
    cyc = {}
    for name, path, col in runs:
        cyc[name] = cycle(path)
    W, H = 1700, 760
    im = Image.new("RGB", (W, H), (246, 246, 246))
    dr = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT, 15)
    small = ImageFont.truetype(FONT, 11)
    dr.text((12, 8), (title or "gait cycle") + "   (grey dots: a human walk, Winter's normal cadence, rounded)", fill=(10, 10, 10), font=font)
    cw, ch = (W - 20) // 4, (H - 40) // 2
    for n, (k, lab) in enumerate(keys):
        bx, by = 10 + (n % 4) * cw, 34 + (n // 4) * ch
        series = []
        for name, path, col in runs:
            c, d = cyc[name]
            if not c:
                continue
            x, C = c
            series.append((f"{name} (T {d.get('period')} s)", col, list(x), [r[k] for r in C], False))
            if k == "pelvisYaw":
                series.append((f"{name} chest", col, list(x), [r["chestYaw"] for r in C], True))
        panel(dr, (bx, by, bx + cw - 8, by + ch - 8), lab, series, HUMAN.get(k, []), font, small)
    im.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
