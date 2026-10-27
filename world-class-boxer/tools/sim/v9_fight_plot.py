"""Joint curves of a v9_anim fight scenario (fightseries_<id>_t<tier>.json), before (dashed) and after (solid).

    python3 tools/sim/v9_fight_plot.py OUT.png BEFORE.json AFTER.json [--title T]

Panels over the scenario's time (s): the pelvis / chest yaw (the punch's turn from the floor), the elbows' bend, the
head's offset across the centre line (studs) and its pitch, the arms' and the trunk / neck's per-frame turn (deg per
frame: the snaps; the Motor6D Transforms the Animator wrote), the knees, and the planted feet's slip (studs per frame).
PIL only.
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

ARM = ["wLS", "wLE", "wLW", "wRS", "wRE", "wRW"]
TRUNK = ["wRoot", "wW", "wNeck"]
PANELS = [
    ("pelvis / chest yaw (deg)", [("pelvisYaw", (90, 160, 240)), ("chestYaw", (240, 150, 70))]),
    ("elbow bend L / R (deg)", [("elbowL", (90, 160, 240)), ("elbowR", (240, 110, 110))]),
    ("head across the line (studs x 100) / pitch (deg)", [("headX100", (120, 220, 140)), ("headPitch", (220, 200, 90))]),
    ("arms: largest joint turn per frame (deg)", [("armW", (240, 110, 110))]),
    ("trunk / neck: largest turn per frame (deg)", [("trunkW", (200, 140, 240))]),
    ("knees L / R (deg)", [("kneeL", (90, 160, 240)), ("kneeR", (240, 110, 110))]),
    ("planted feet: slip per frame (studs x 100)", [("slip100", (240, 200, 90))]),
]


def load(path):
    S = json.load(open(path))["series"]
    for r in S:
        r["headX100"] = 100 * r.get("headX", 0)
        r["armW"] = max(r.get(k, 0) for k in ARM)
        r["trunkW"] = max(r.get(k, 0) for k in TRUNK)
        r["slip100"] = 100 * (r.get("slipL", 0) + r.get("slipR", 0))
    return S


def main():
    out, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
    title = sys.argv[sys.argv.index("--title") + 1] if "--title" in sys.argv else out
    A, B = load(a), load(b)
    W, PH, L, R, T = 1100, 150, 70, 20, 40
    im = Image.new("RGB", (W, T + PH * len(PANELS) + 30), (24, 25, 28))
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    tf = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 17)
    d.text((10, 10), title + "   (dashed = before, solid = after)", fill=(235, 235, 235), font=tf)
    t1 = max(A[-1]["t"], B[-1]["t"])
    for pi, (name, keys) in enumerate(PANELS):
        y0 = T + pi * PH
        vals = [r[k] for S in (A, B) for r in S for k, _ in keys]
        lo, hi = min(vals), max(vals)
        if hi - lo < 1e-6:
            hi = lo + 1
        pad = (hi - lo) * 0.08
        lo, hi = lo - pad, hi + pad
        d.rectangle([L, y0 + 18, W - R, y0 + PH - 8], outline=(70, 70, 76))
        d.text((L + 4, y0 + 2), name, fill=(200, 200, 200), font=f)
        d.text((4, y0 + 18), "%.1f" % hi, fill=(150, 150, 150), font=f)
        d.text((4, y0 + PH - 24), "%.1f" % lo, fill=(150, 150, 150), font=f)

        def xy(r, k):
            x = L + (W - R - L) * r["t"] / t1
            y = y0 + PH - 8 - (PH - 26) * (r[k] - lo) / (hi - lo)
            return x, y
        for S, dash in ((A, True), (B, False)):
            for k, col in keys:
                pts = [xy(r, k) for r in S]
                for i in range(1, len(pts)):
                    if dash and (i // 2) % 2 == 1:
                        continue
                    c = col if not dash else tuple(int(v * 0.5 + 60) for v in col)
                    d.line([pts[i - 1], pts[i]], fill=c, width=2 if not dash else 3)
    for s in range(0, int(t1) + 1):
        x = L + (W - R - L) * s / t1
        d.text((x - 4, T + PH * len(PANELS) + 6), "%d s" % s, fill=(170, 170, 170), font=f)
    im.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
