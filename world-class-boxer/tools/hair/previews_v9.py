"""v9 hair previews on the classic head (Blender Cycles, CPU), the asset hair as the game places it.

    /opt/bpyenv/bin/python tools/hair/previews_v9.py after  [--only key,key] [--samples N]
    HAIR_REF=organic /opt/bpyenv/bin/python tools/hair/previews_v9.py before --src DIR [--only ...]
    /opt/bpyenv/bin/python tools/hair/previews_v9.py sheets

* after: every out/<key>/style.json entry on the classic head (ref/classic/head_m.obj: the Head SpecialMesh's
  rounded cylinder with the built face's ears, brows, eyes, nose and lips; skin tinted), placed as HairAssetKit does
  on a classic head with a classic fit0 (the identity in nominal space, k = Head.Size / 1.2 left out), the cap
  painted with the style's own coverage (build_fades.paint_cap: the game's Kit.Cut grid of ref/classic), the card
  textures tinted. Views front, 34, side, back.
* before: the v7 meshes (--src, a copy of the v7 out/) on the same classic head through the fit the game gives
  them today (HairAssetKit.Fit with the organic fit0 and CLASSIC_FIT: x 1.661, y 1.218 - 0.06, z 1.469 - 0.03,
  tools/sim/fit_classic_hair.luau), the cap painted on the organic reference (run with HAIR_REF=organic).
* sheets: per style a 4-view sheet, the lineup of every style (front + 34) and the before / after sheets, into
  previews/final/v9/hair/.
"""
import argparse
import glob
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))
OUTV9 = os.path.join(ROOT, "previews", "final", "v9", "hair")
WORK = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/v9/renders"
CLASSIC_REF = os.path.join(HERE, "ref", "classic")

import numpy as np  # noqa: E402

import hairlib as hl  # noqa: E402

VIEWS = ["front", "34", "side", "back"]
# the v7 meshes' placement on the classic head today (HairAssetKit.Fit: organic fit0 x CLASSIC_FIT)
V7_FIT = dict(ax=1.661, ay=1.218, az=1.469, dy=-0.06, dz=-0.03)
SKIN = (0.46, 0.29, 0.19)
TINTS = {"black": (0.085, 0.075, 0.07), "darkbrown": (0.2, 0.135, 0.095), "brown": (0.32, 0.21, 0.13),
         "blonde": (0.72, 0.56, 0.33)}
# per entry: the cap's coverage kind (the style's Kit.Cut; "none" = the natural hairline) and the preview tint
LONGISH = ("long", "long_wavy", "dreadlocks", "twists", "braids", "box_braids")


def read_mesh(path, name, tex):
    with open(path, "rb") as f:
        data = f.read()
    i = data.index(b"\n") + 1
    hs, vs, fs, nv, nt = struct.unpack_from("<HBBII", data, i)
    i += hs
    p = hl.Piece(name, tex)
    for k in range(nv):
        x, y, z, nx, ny, nz, u, v = struct.unpack_from("<3f3f2f", data, i + k * vs)
        r, g, b, a = struct.unpack_from("<4B", data, i + k * vs + 36)
        p.vert((x, y, z), (nx, ny, nz), (u, v), (r / 255, g / 255, b / 255, a / 255))
    i += nv * vs
    for k in range(nt):
        p.tri(*struct.unpack_from("<3I", data, i + k * fs))
    return p


def entry_info(key, st):
    import build_fades as bf
    kind, curly, earline, tile = "none", False, False, None
    for e in bf.entries():
        if e["key"] == key:
            kind = e.get("capFade") or e["kind"]
            earline = True
    if key == "hightop":
        kind = "high"
    types = st.get("types")
    curly = bool(types) and all(t in ("Curly", "Kinky", "Coiled") for t in types)
    if key in ("afro", "hightop", "dreadlocks", "twists", "short_dreads", "braids", "box_braids", "cornrows",
               "buzz", "waves360"):
        curly = True
    tile = st.get("capTile") or ("shortcoil" if curly else "short")
    nu, nv = st.get("capTileRepeat") or bf.TILE
    dens = st.get("cap", {}).get("density", 1.0) if st.get("cap") else 1.0
    if key in bf.DENSITY:
        dens = bf.DENSITY[key]
    cut = (st.get("cap") or {}).get("cut", "full")
    tint = "brown" if key in ("long", "caesar", "crew", "fade_low", "fade_mid", "fade_high", "fade_taper",
                              "fade_burst") else ("darkbrown" if key in ("long_wavy", "box_braids") else "black")
    if key == "long":
        tint = "blonde"
    return dict(kind=kind, tile=tile, nu=nu, nv=nv, density=dens, cut=cut, earline=earline, tint=tint)


def paint(ref, info, shell=None, tag=""):
    import build_fades as bf
    os.makedirs(WORK, exist_ok=True)
    d = 0.0 if info["cut"] == "none" else min(1.0, info["density"])
    out = os.path.join(WORK, f"cap_{tag}_{info['kind']}_{info['tile']}_{d:.2f}"
                             f"{'_%.2f_%.2f' % (shell['rank'], shell['cov']) if shell else ''}.png")
    if not os.path.exists(out):
        bf.paint_cap(ref, info["kind"], info["tile"], max(d, 0.0), info["nu"], info["nv"],
                     size=1024 if shell is None else 512, shell=shell, out=out, earline=info["earline"])
    return out


def load_entry(src, key):
    with open(os.path.join(src, key, "style.json")) as f:
        st = json.load(f)
    pieces = [read_mesh(os.path.join(src, key, rec["mesh_file"]), name, rec["tex"])
              for name, rec in sorted(st["pieces"].items())]
    for p, (name, rec) in zip(pieces, sorted(st["pieces"].items())):
        p.meta = dict(rec)
    return st, pieces


def placed(piece, fit):
    if fit is None:
        return piece
    P = np.asarray(piece.P)
    P = P * [fit["ax"], fit["ay"], fit["az"]] + [0, fit["dy"], fit["dz"]]
    q = hl.Piece(piece.name, piece.tex)
    q.P, q.N, q.U, q.C, q.T = [tuple(x) for x in P], piece.N, piece.U, piece.C, piece.T
    q.meta = piece.meta
    return q


def render_entry(key, src, mode, samples, res=(420, 500), views=None):
    import bpy
    import build_fades as bf
    import render
    ref = bf.Ref()
    st, pieces = load_entry(src, key)
    cap_st, cap_p = load_entry(src, "cap")
    info = entry_info(key, st)
    fit = V7_FIT if mode == "before" else None
    tint = TINTS[info["tint"]]
    capimg = paint(ref, info, tag=mode)
    long_ = key in LONGISH
    if long_:
        focus, dist = (0.0, -0.3, 0.0), 6.8
    elif key in ("afro", "afro_curly", "hightop"):
        focus, dist = (0.0, 0.2, 0.0), 5.9
    else:
        focus, dist = (0.0, 0.12, 0.0), 5.2
    paths = []
    for view in views or VIEWS:
        sc = render.Scene(res=res, samples=samples, focus=focus, dist=dist)
        sc.sc.view_settings.view_transform = "Standard"
        render.add_obj(sc, os.path.join(CLASSIC_REF, "head_m.obj"), tint=SKIN)
        if long_:
            render.add_obj(sc, os.path.join(CLASSIC_REF, "torso_m.obj"), tint=SKIN)
        if st.get("cap", {}).get("cut") in ("style", "full"):
            cob = sc.add_piece(placed(cap_p[0], fit), texture=capimg, tint=tint)
            bf.matte(cob)
            cull_backfaces(cob)
        for p in pieces:
            q, two = dedup_twins(placed(p, fit))
            if p.tex == "cap":
                s = p.meta.get("capShell")
                tex = paint(ref, info, shell=s, tag=mode) if s else capimg
            else:
                tex = os.path.join(HERE, "textures", f"hair_{p.tex}.png")
            ob = sc.add_piece(q, texture=tex, tint=tint)
            bf.matte(ob)
            if p.tex != "cap":
                bf.roblox_normals(ob, q)
            cull_backfaces(ob, two)
            if not p.meta.get("castShadow", True):
                ob.visible_shadow = False
        fn = os.path.join(WORK, f"{mode}_{key}_{view}.png")
        sc.render(fn, view=view)
        paths.append(fn)
        bpy.ops.wm.read_factory_settings(use_empty=True)
    return paths


def dedup_twins(piece):
    """a render copy without the reversed twins of two-sided card triangles (coplanar twins: a Cycles ray passes
    both or doubles the alpha); returns the copy and per kept triangle 1 = it had a twin (drawn from both sides)"""
    q = hl.Piece(piece.name, piece.tex)
    q.P, q.N, q.U, q.C = piece.P, piece.N, piece.U, piece.C
    q.meta = getattr(piece, "meta", {})
    first, two = {}, []
    for t in piece.T:
        k = tuple(sorted(t))
        if k in first:
            two[first[k]] = 1.0
            continue
        first[k] = len(q.T)
        q.T.append(t)
        two.append(0.0)
    return q, two


def cull_backfaces(ob, two=None):
    """Roblox draws the front side of a triangle only: a one-sided triangle's back side is transparent here (Cycles:
    Geometry.Backfacing); a two-sided card's (its twin removed, dedup_twins) shows both. A copy of the material per
    object (bf.matte made one)."""
    mat = ob.data.materials[0]
    if mat.get("culled"):
        return
    nt = mat.node_tree
    out = nt.nodes["Material Output"]
    bs = nt.nodes["Principled BSDF"]
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    fac = geo.outputs["Backfacing"]
    if two is not None and any(two):
        me = ob.data
        at = me.attributes.new("two", "FLOAT", "FACE")
        at.data.foreach_set("value", [float(x) for x in two])
        an = nt.nodes.new("ShaderNodeAttribute")
        an.attribute_name = "two"
        mth = nt.nodes.new("ShaderNodeMath")
        mth.operation = "SUBTRACT"
        nt.links.new(geo.outputs["Backfacing"], mth.inputs[0])
        nt.links.new(an.outputs["Fac"], mth.inputs[1])
        mth.use_clamp = True
        fac = mth.outputs[0]
    nt.links.new(fac, mix.inputs[0])
    nt.links.new(bs.outputs[0], mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    mat["culled"] = 1


def keys_of(src):
    return sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(src, "*", "style.json"))
                  if os.path.basename(os.path.dirname(p)) != "cap")


def styles_label(src, key):
    with open(os.path.join(src, key, "style.json")) as f:
        st = json.load(f)
    t = st.get("types")
    return f"{key}: {', '.join(st['styles'])}" + (f" [{'/'.join(t)}]" if t else ""), st.get("tris")


def sheets():
    import render
    os.makedirs(OUTV9, exist_ok=True)
    src = hl.OUT
    keys = keys_of(src)
    v7 = os.path.join(os.path.dirname(WORK), "out_v7")
    for k in keys:
        paths = [os.path.join(WORK, f"after_{k}_{v}.png") for v in VIEWS]
        if all(os.path.exists(p) for p in paths):
            lab, tris = styles_label(src, k)
            render.sheet(paths, os.path.join(OUTV9, f"{k}.jpg"), cols=4, labels=VIEWS,
                         title=f"v9 {lab}: {tris} tris on the classic head")
    # the lineup: every style front + 3/4, three styles a row
    cells, labels = [], []
    for k in keys:
        for v in ("front", "34"):
            p = os.path.join(WORK, f"after_{k}_{v}.png")
            if os.path.exists(p):
                cells.append(p)
                labels.append(f"{k} {v}")
    render.sheet(cells, os.path.join(OUTV9, "lineup.jpg"), cols=8, labels=labels, cell=(250, 298),
                 title="v9 asset hair on the classic head: every entry (front, 3/4)")
    # before / after: v7 as the game places it today on the classic head vs v9, 3/4 and side
    pairs = []
    for k in keys:
        b = [os.path.join(WORK, f"before_{k}_{v}.png") for v in ("34", "side")]
        a = [os.path.join(WORK, f"after_{k}_{v}.png") for v in ("34", "side")]
        if all(os.path.exists(x) for x in a + b):
            pairs.append((k, b, a))
    for n0 in range(0, len(pairs), 7):
        cells, labels = [], []
        for k, b, a in pairs[n0:n0 + 7]:
            cells += [b[0], b[1], a[0], a[1]]
            labels += [f"{k} v7 3/4", f"{k} v7 side", f"{k} v9 3/4", f"{k} v9 side"]
        render.sheet(cells, os.path.join(OUTV9, f"before_after_{n0 // 7 + 1}.jpg"), cols=4, labels=labels,
                     cell=(300, 357), title="before (v7 meshes, today's classic fit) | after (v9, modelled on the classic head)")
    print("sheets in", OUTV9)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["after", "before", "sheets"])
    ap.add_argument("--src", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=32)
    ap.add_argument("--views", default="")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    if args.mode == "sheets":
        return sheets()
    src = args.src or hl.OUT
    if args.mode == "before":
        assert not hl.CLASSIC, "run the before renders with HAIR_REF=organic (the v7 cap's coverage)"
    keys = [k for k in keys_of(src) if not args.only or k in args.only.split(",")]
    for k in keys:
        print("render", args.mode, k, flush=True)
        render_entry(k, src, args.mode, args.samples, views=args.views.split(",") if args.views else None)


if __name__ == "__main__":
    main()
