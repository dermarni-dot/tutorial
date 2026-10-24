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


def stack_gif(a, b, out, la, lb):
    """two GIFs side by side, frame for frame (the shorter one holds its last frame)"""
    from PIL import ImageSequence
    A = [f.convert("RGB") for f in ImageSequence.Iterator(Image.open(a))]
    B = [f.convert("RGB") for f in ImageSequence.Iterator(Image.open(b))]
    ms = Image.open(b).info.get("duration", 50)
    n = max(len(A), len(B))
    w, h = A[0].size
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    frames = []
    for i in range(n):
        W = Image.new("RGB", (w + B[0].size[0], max(h, B[0].size[1]) + 24), (18, 18, 20))
        W.paste(A[min(i, len(A) - 1)], (0, 24))
        W.paste(B[min(i, len(B) - 1)], (w, 24))
        d = ImageDraw.Draw(W)
        d.text((8, 4), la, fill=(240, 150, 120), font=f)
        d.text((w + 8, 4), lb, fill=(140, 230, 150), font=f)
        frames.append(W.quantize(colors=160, method=Image.Quantize.MEDIANCUT))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=ms, loop=0, optimize=True)
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
    la = os.environ.get("V9_LA", "BEFORE (v8 body, gear and animation)")
    lb = os.environ.get("V9_LB", "AFTER (v9: ball joints, fitted trunks, walk sway / track, straight punches' line)")
    for key, a, b in pairs:
        if a.endswith(".gif"):
            stack_gif(a, b, os.path.join(d, "compare_" + key + ".gif"), la.split(" (")[0], lb.split(" (")[0])
        else:
            stack(a, b, os.path.join(d, "compare_" + key + ".jpg"), la, lb)


if __name__ == "__main__":
    main()
