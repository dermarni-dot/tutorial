"""Cycles renders of the v9 face scenes exported by tools/sim/v9_faces.luau (world space, studs, +Y up, face -Z).

    /opt/bpyenv/bin/python tools/sim/v9_faces_render.py SCENE_DIR OUT_DIR [--only id,id] [--samples N] [--views front,34]
                                                       [--sheets SPEC.json] [--res 360] [--hair id:key,id:key]

Per entry: head close-ups (front, 3/4 by default) as <id>_<view>.png. Then the sheets in SPEC (a JSON list of
{ "file": "name.jpg", "title": "...", "cols": n, "items": [[id, view, label, dir?], ...] }; dir = another render
folder, e.g. the "before" set), when given; --render 0 only lays out the sheets.
Geometry is exactly what the scene file says (v8_render.py's shapes and studio rig): the tier meshes, the classic head
(AnatomyHairKit.CLASSIC revolved; its decal on an older src), and every Kit.mk part by shape, colour, material,
reflectance and TRANSPARENCY (a translucent part is drawn translucent: the sweat sheen, the grime, the bruises).
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hair"))
import v8_render as V  # noqa: E402
import render  # noqa: E402
import bpy  # noqa: E402


def part_mat(sc, color, material, refl, transp):
    key = ("p", tuple(round(c, 3) for c in color), material, round(refl, 2), round(transp, 2))
    if key in sc._gmats:
        return sc._gmats[key]
    m = bpy.data.materials.new("p" + str(len(sc._gmats)))
    m.use_nodes = True
    bs = m.node_tree.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = (*V.srgb2lin(color), 1)
    r = V.ROUGH.get(material, 0.5)
    if refl > 0.05:
        r = min(r, 0.22)
    bs.inputs["Roughness"].default_value = r
    if material in ("Metal", "Foil"):
        bs.inputs["Metallic"].default_value = 0.8
    if transp > 0.001:
        bs.inputs["Alpha"].default_value = max(0.0, 1.0 - transp)
        m.blend_method = "BLEND"
    sc._gmats[key] = m
    return m


def add_scene(sc, scene_dir, d):
    for m in d["meshes"]:
        P = np.asarray(m["p"]).reshape(-1, 3)
        T = np.asarray(m["t"]).reshape(-1, 3) - 1
        col = m["color"]
        skin = d["head"]["color"]
        skinlike = m["material"] in ("SmoothPlastic", "Plastic") and max(abs(a - b) for a, b in zip(col, skin)) < 0.02
        if skinlike:
            sc.add_world(P, T, m["name"], material="skin", tint=V.srgb2lin(col), normals=m["n"])
        else:
            sc.add_world(P, T, m["name"], mat=sc.gear_mat(col, m["material"], m.get("reflectance", 0)), normals=m["n"])
    hd = d["head"]
    P, T = V.classic_head(hd["classic"], hd["size"])
    sc.add_world(V.place(P, hd["cf"], 0), T, "Head", material="skin", tint=V.srgb2lin(hd["color"]))
    dec = hd.get("decal")
    if dec and dec.get("file"):
        P, U, T = V.face_decal(hd["classic"], hd["size"])
        sc.add_world(V.place(P, hd["cf"], 0), T, "face", uv=U, texture=dec["file"], material="plastic", alpha=True, smooth=True)
    for g in d["parts"]:
        sx, sy, sz = g["size"]
        sh = g["shape"]
        smooth = True
        if sh == "Block":
            P, T = V.box(sx, sy, sz)
            smooth = False
        elif sh == "Ball":
            r = min(sx, sy, sz) / 2
            P, T = V.uv_sphere(r, r, r)
        elif sh == "Cylinder":
            r = min(sy, sz) / 2
            P, T = V.cylinder_x(sx, r, r)
        elif sh == "Ellipsoid":
            P, T = V.uv_sphere(sx / 2, sy / 2, sz / 2)
        elif sh == "Wedge":
            P, T = V.wedge(sx, sy, sz)
            smooth = False
        else:
            continue
        ob = sc.add_world(V.place(P, g["cf"], 0), T, g["name"], smooth=smooth,
                          mat=part_mat(sc, g["color"], g["material"], g.get("reflectance", 0), g.get("transparency", 0)))
        if not smooth:
            for poly in ob.data.polygons:
                poly.use_smooth = False


def add_hair(sc, d, key):
    """the v9 asset hair (tools/hair/out/<key>) on the scene's head, placed as tools/hair/previews_v9.py places it
    (nominal head space, the classic fit0 = the identity) and scaled to the head (k = Head.Size / 1.2)"""
    import previews_v9 as PV
    import build_fades as bf
    import hairlib as hl
    st, pieces = PV.load_entry(hl.OUT, key)
    _, cap_p = PV.load_entry(hl.OUT, "cap")
    info = PV.entry_info(key, st)
    tint = PV.TINTS[info["tint"]]
    ref = bf.Ref()
    capimg = PV.paint(ref, info, tag="after")
    k = d["head"]["size"][0] / 1.2
    cf = d["head"]["cf"]

    def put(piece, tex, two_sided=True):
        q, two = PV.dedup_twins(piece)
        P = V.place(np.asarray(q.P, dtype=float) * k, cf, 0)
        R = np.array(cf[3:]).reshape(3, 3)
        md = {"p": P.ravel(), "t": np.asarray(q.T).ravel(), "uv": np.asarray(q.U).ravel(), "c": np.asarray(q.C).ravel(),
              "n": (np.asarray(q.N, dtype=float) @ R.T).ravel(), "base": 0}
        ob = sc.add_mesh(md, texture=tex, material="hair", tint=tint, alpha=True, name=q.name)
        bf.matte(ob)
        if two_sided:
            bf.roblox_normals(ob, q)
        PV.cull_backfaces(ob, two)
        return ob

    if st.get("cap", {}).get("cut") in ("style", "full"):
        put(cap_p[0], capimg, two_sided=False)
    for p in pieces:
        if p.tex == "cap":
            s_ = p.meta.get("capShell")
            put(p, PV.paint(ref, info, shell=s_, tag="after") if s_ else capimg, two_sided=False)
        else:
            put(p, os.path.join(os.path.dirname(HERE), "hair", "textures", f"hair_{p.tex}.png"))


VIEWS = {"front": (0, 2, 1.0), "34": (32, 4, 1.0), "side": (80, 2, 1.0),
         "body": (0, 6, 1.0), "body34": (35, 8, 1.0), "bodyside": (90, 4, 1.0)}


def render_entry(scene_dir, out_dir, look, samples, views, res, hair=None):
    d = json.load(open(os.path.join(scene_dir, look["file"])))
    sc = V.V8Scene(res=(res, res), samples=samples, lens=85, bg=(0.11, 0.115, 0.125))
    add_scene(sc, scene_dir, d)
    if hair:
        add_hair(sc, d, hair)
    f = tuple(np.array(d["head"]["cf"][:3]) + np.array([0, -0.04, 0]))
    sc.rig(f, 1.0)
    out = []
    top = d["head"]["cf"][1] + d["head"]["size"][1] / 2 + 0.1
    for v in views:
        p = os.path.join(out_dir, f"{look['id']}{'__' + hair if hair else ''}_{v}.png")
        if v.startswith("body"):
            # the whole boxer (the robe previews): head to feet
            bf = (0, top / 2, 0)
            sc.rig(bf, 3.0)
            sc.render(p, view=VIEWS[v], dist=(top / 2 + 0.35) / math.tan(math.atan(18 / 85)), focus=bf)
        else:
            sc.rig(f, 1.0)
            sc.render(p, view=VIEWS[v], dist=0.78 / math.tan(math.atan(18 / 85)), focus=f)
        out.append(p)
    print("rendered", look["id"], flush=True)
    return out


def sheets(out_dir, spec):
    for sh in spec:
        paths, labels = [], []
        for it in sh["items"]:
            p = os.path.join(it[3] if len(it) > 3 else out_dir, f"{it[0]}_{it[1]}.png")
            if os.path.isfile(p):
                paths.append(p)
                labels.append(it[2])
        if paths:
            dst = sh["file"] if os.path.isabs(sh["file"]) else os.path.join(out_dir, sh["file"])
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            render.sheet(paths, dst, cols=sh.get("cols", 4), labels=labels, title=sh.get("title"))
            print("sheet", dst, flush=True)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" in sys.argv:
        argv = sys.argv[sys.argv.index("--") + 1:]
    scene_dir, out_dir = argv[0], argv[1]
    opts = {}
    i = 2
    while i < len(argv):
        opts[argv[i]] = argv[i + 1]
        i += 2
    os.makedirs(out_dir, exist_ok=True)
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    only = set(opts["--only"].split(",")) if "--only" in opts else None
    looks = [l for l in idx["looks"] if not only or l["id"] in only or l.get("look") in only]
    samples = int(opts.get("--samples", 32))
    views = opts.get("--views", "front,34").split(",")
    res = int(opts.get("--res", 360))
    # --hair id:key,id:key : those entries again with the v9 asset hair (files <id>__<key>_<view>.png)
    hair = [h.split(":") for h in opts["--hair"].split(",")] if "--hair" in opts else []
    if opts.get("--render", "1") != "0":
        if hair:
            byid = {l["id"]: l for l in idx["looks"]}
            for i, key in hair:
                render_entry(scene_dir, out_dir, byid[i], samples, views, res, hair=key)
        else:
            for l in looks:
                render_entry(scene_dir, out_dir, l, samples, views, res)
    if "--sheets" in opts:
        sheets(out_dir, json.load(open(opts["--sheets"])))
