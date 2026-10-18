"""Before / after pairs of the v9 sheets (tools/sim/v9_render.py outputs), stacked: <dir>/compare_<name>.jpg

    python3 tools/sim/v9_compare.py previews/final/v9 [name ...]     # default: every <before>_X with an <after>_X
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def stack(a, b, out, la, lb):
    A, B = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    w = max(A.width, B.width)
    if A.width != w:
        A = A.resize((w, int(A.height * w / A.width)))
    if B.width != w:
        B = B.resize((w, int(B.height * w / B.width)))
    bar = 34
    W = Image.new("RGB", (w, A.height + B.height + 2 * bar), (18, 18, 20))
    d = ImageDraw.Draw(W)
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    d.text((10, 5), la, fill=(240, 150, 120), font=f)
    W.paste(A, (0, bar))
    d.text((10, A.height + bar + 5), lb, fill=(140, 230, 150), font=f)
    W.paste(B, (0, A.height + 2 * bar))
    if W.width > 3000:
        W = W.resize((3000, int(W.height * 3000 / W.width)))
    W.save(out, quality=86)
    print("wrote", out)


def main():
    d = sys.argv[1]
    names = sys.argv[2:]
    files = set(os.listdir(d))
    pairs = []
    for f in sorted(files):
        for pre, post in (("before_bare_", "after_bare_"), ("before_", "after_")):
            if f.startswith(pre) and (post + f[len(pre):]) in files:
                rest = f[len(pre):]
                if pre == "before_" and rest.startswith("bare_"):
                    continue
                key = ("bare_" if "bare" in pre else "") + rest[:-4]
                if not names or key in names:
                    pairs.append((key, os.path.join(d, f), os.path.join(d, post + rest)))
                break
    for key, a, b in pairs:
        stack(a, b, os.path.join(d, "compare_" + key + ".jpg"), "BEFORE (v8 body, gear and animation)",
              "AFTER (v9: ball joints, fitted trunks, walk sway / track, straight punches' line)")


if __name__ == "__main__":
    main()
