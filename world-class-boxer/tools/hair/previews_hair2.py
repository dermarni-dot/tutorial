"""v10 stylised hair previews (Blender Cycles, CPU) on the classic head with the game's built face (ref/classic/head_m.obj,
from face_m.json), the cap painted as the game paints it for each entry (its capFade / cut, tile, density, ear line):

    /opt/bpyenv/bin/python tools/hair/previews_hair2.py render [--only key,key] [--samples N] [--views front,34]
    /opt/bpyenv/bin/python tools/hair/previews_hair2.py before [--only key,key]     # the v9 meshes (scratchpad copy)
    /opt/bpyenv/bin/python tools/hair/previews_hair2.py sheets

Sheets into previews/final/v9/hair2/: per entry a 4-view strip (front, 3/4, side, back), the six reference styles
laid out like the user's reference sheet (3 x 2, 3/4 view, captions), the same in front / side / back, and the
before (v9) / after (v10) pairs.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))
SP = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad"
OUT2 = os.path.join(ROOT, "previews", "final", "v9", "hair2")
WORK2 = os.path.join(SP, "hair2", "renders")
BEFORE_SRC = os.path.join(SP, "out_v9_before")

import previews_v9 as pv  # noqa: E402
import hairlib as hl  # noqa: E402

SIX = [("fade_taper_c", "LOW TAPER"), ("waves360", "360 WAVES"), ("twists", "TWISTS"),
       ("short_dreads", "SHORT LOCS"), ("cornrows", "CORNROWS"), ("afro", "AFRO")]
_orig_info = pv.entry_info


def entry_info(key, st):
    """the cap as the game paints it for this style.json (HK.CapCoverage): capFade on a natural hairline, else the
    style's own cut (the fades' kinds), else the natural hairline at the entry's density"""
    info = _orig_info(key, st)
    if st.get("family") != "stylised":
        return info
    cap = st.get("cap") or {}
    if st.get("capFade"):
        info["kind"] = st["capFade"]
    elif cap.get("cut") == "style":
        import build_fades as bf
        kinds = {e["key"]: e["kind"] for e in bf.entries()}
        info["kind"] = kinds.get(key, "high" if key == "hightop" else "none")
    else:
        info["kind"] = "none"
    info["density"] = cap.get("density", 1.0)
    info["earline"] = bool(st.get("capEarLine"))
    info["tint"] = "black"
    return info


def setup(work):
    pv.entry_info = entry_info
    pv.WORK = work
    pv.LONGISH = ("long", "long_wavy", "dreadlocks", "braids", "box_braids")


def sheets():
    import render
    os.makedirs(OUT2, exist_ok=True)
    src = hl.OUT
    keys = pv.keys_of(src)
    views = pv.VIEWS
    for k in keys:
        paths = [os.path.join(WORK2, f"after_{k}_{v}.png") for v in views]
        if all(os.path.exists(p) for p in paths):
            lab, tris = pv.styles_label(src, k)
            render.sheet(paths, os.path.join(OUT2, f"{k}.jpg"), cols=4, labels=views,
                         title=f"v10 {lab}: {tris} tris on the classic head")
    # the user's reference layout: 3 x 2, captions, one sheet per view
    for v, name in (("34", "six_styles_34"), ("front", "six_styles_front"), ("side", "six_styles_side"),
                    ("back", "six_styles_back")):
        cells = [os.path.join(WORK2, f"after_{k}_{v}.png") for k, _ in SIX]
        if all(os.path.exists(c) for c in cells):
            render.sheet(cells, os.path.join(OUT2, f"{name}.jpg"), cols=3, labels=[lab for _, lab in SIX],
                         cell=(480, 571), title=f"BOXER HAIR COLLECTION (game meshes on the classic head, {v} view)")
    # all four views of the six on one sheet
    cells, labels = [], []
    for k, lab in SIX:
        for v in views:
            p = os.path.join(WORK2, f"after_{k}_{v}.png")
            if os.path.exists(p):
                cells.append(p)
                labels.append(f"{lab} {v}")
    if cells:
        render.sheet(cells, os.path.join(OUT2, "six_styles_all_views.jpg"), cols=4, labels=labels, cell=(300, 357),
                     title="the six reference styles: front, 3/4, side, back")
    # before (v9) / after (v10)
    pairs = []
    for k in keys:
        b = [os.path.join(WORK2, f"before_{k}_{v}.png") for v in ("34", "side")]
        a = [os.path.join(WORK2, f"after_{k}_{v}.png") for v in ("34", "side")]
        if all(os.path.exists(x) for x in a + b):
            pairs.append((k, b, a))
    for n0 in range(0, len(pairs), 6):
        cells, labels = [], []
        for k, b, a in pairs[n0:n0 + 6]:
            cells += [b[0], b[1], a[0], a[1]]
            labels += [f"{k} v9 3/4", f"{k} v9 side", f"{k} v10 3/4", f"{k} v10 side"]
        render.sheet(cells, os.path.join(OUT2, f"before_after_{n0 // 6 + 1}.jpg"), cols=4, labels=labels,
                     cell=(300, 357), title="before (v9 meshes) | after (v10 stylised clumps)")
    print("sheets in", OUT2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["render", "before", "sheets"])
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=32)
    ap.add_argument("--views", default="")
    ap.add_argument("--res", default="420x500")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    setup(WORK2)
    os.makedirs(WORK2, exist_ok=True)
    if args.mode == "sheets":
        return sheets()
    src = hl.OUT if args.mode == "render" else BEFORE_SRC
    mode = "after" if args.mode == "render" else "before"
    if mode == "before":
        pv.entry_info = _orig_info
        pv.WORK = os.path.join(WORK2, "before_tmp")  # (its own folder: an "after" run may be going on)
        os.makedirs(pv.WORK, exist_ok=True)
    res = tuple(int(x) for x in args.res.split("x"))
    keys = [k for k in pv.keys_of(src) if not args.only or k in args.only.split(",")]
    for k in keys:
        print("render", mode, k, flush=True)
        pv.render_entry(k, src, "after", args.samples, res=res, views=args.views.split(",") if args.views else None)
        if mode == "before":
            for v in (args.views.split(",") if args.views else pv.VIEWS):
                a = os.path.join(pv.WORK, f"after_{k}_{v}.png")
                os.replace(a, os.path.join(WORK2, f"before_{k}_{v}.png"))


if __name__ == "__main__":
    main()
