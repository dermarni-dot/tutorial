"""Side-by-side GIFs of the same punch thrown by different boxers (v9_anim's sty_<id> scenarios rendered as GIFs).

    python3 tools/sim/v9_style_sheet.py GIF_DIR OUT_DIR

GIF_DIR holds style_fight_sty_<id>_t3_34.gif (v9_render.py --tag style --views 34 --gif 1, V9_WINDOW=0: every frame,
one every 0.05 s from t = 0); each scenario throws a jab at 0.4 s, a cross at 1.4, a lead hook at 2.4, an uppercut at
3.4 and an overhand at 4.4 (FightEngine's windups). Writes OUT_DIR/styles_<punch>.gif: the six boxers in a 3 x 2 grid,
frame for frame over that punch's window.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageSequence

BOXERS = [("boxerpuncher", "Boxer-puncher"), ("outboxer", "Out-boxer"), ("swarmer", "Swarmer"), ("slugger", "Slugger"),
          ("counter", "Counter puncher"), ("outboxer_heavy", "Out-boxer, PunchStyle Heavy")]
PUNCHES = [("jab", 0.4), ("cross", 1.4), ("leadhook", 2.4), ("uppercut", 3.4), ("overhand", 4.4)]
STEP = 0.05


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    gifs = {}
    for key, _ in BOXERS:
        p = os.path.join(src, f"style_fight_sty_{key}_t3_34.gif")
        if os.path.exists(p):
            gifs[key] = [f.convert("RGB") for f in ImageSequence.Iterator(Image.open(p))]
    have = [(k, n) for k, n in BOXERS if k in gifs]
    if not have:
        print("no style GIFs in", src)
        return
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    w, h = gifs[have[0][0]][0].size
    cols = 3
    rows = (len(have) + cols - 1) // cols
    for name, t0 in PUNCHES:
        a, b = int(round((t0 - 0.1) / STEP)), int(round((t0 + 0.8) / STEP))
        frames = []
        for i in range(a, b + 1):
            W = Image.new("RGB", (cols * w, rows * (h + 22)), (18, 18, 20))
            d = ImageDraw.Draw(W)
            for j, (k, label) in enumerate(have):
                fr = gifs[k]
                im = fr[min(i, len(fr) - 1)]
                x, y = (j % cols) * w, (j // cols) * (h + 22)
                W.paste(im, (x, y + 22))
                d.text((x + 6, y + 3), label, fill=(235, 220, 150), font=f)
            frames.append(W.quantize(colors=160, method=Image.Quantize.MEDIANCUT))
        p = os.path.join(out, f"styles_{name}.gif")
        frames[0].save(p, save_all=True, append_images=frames[1:], duration=60, loop=0, optimize=True)
        print("wrote", p)


if __name__ == "__main__":
    main()
