"""Cycles renders of the tournaments' belts and the celebration cutscene's storyboard exported by
tools/sim/v9_ceremony.luau (world space, studs, +Y up; the ring canvas at y = 0).

    /opt/bpyenv/bin/python tools/sim/v9_ceremony_render.py SCENE_DIR OUT_DIR [--samples N] [--only belts,story]
                                                           [--res 960x540] [--frames f1_closeup,f5_hero]

belts: every design BeltModel builds (the five tournament belts, the title belts) on a dark studio set, front, 3/4 and
the worn loop -> belts_tournaments.jpg, belts_titles.jpg and one belt_<key>.jpg each.
story: each storyboard frame through the game's own camera (Shared.Tournaments.CeremonyShot: position, look, vertical
field of view) in a stand-in arena (the ring, the apron, a crowd on risers), with the frame's effects (confetti,
streamers, pyro streaks from the posts, spotlights on the winner) and the cutscene's 2D layer composited the way
BoxerClient.Ceremony draws it (the letterbox, the WCB banner with the belt badge, SKIP) -> story_<id>.jpg and the
sheet storyboard.jpg. Geometry and materials: v8_render.py (the boxers' tier meshes, gear, the classic head + decal).
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hair"))
import v8_render as v8  # noqa: E402
import render  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from PIL import Image, ImageDraw, ImageFont, ImageFilter  # noqa: E402

FONTS = "/usr/share/fonts/opentype/inter"
GOLD = (255, 212, 92)
GOLD_DEEP = (226, 160, 40)


def font(kind, px):
    f = {"display": "InterDisplay-Black.otf", "displayMed": "InterDisplay-Bold.otf", "body": "Inter-Medium.otf",
         "semi": "Inter-Bold.otf"}[kind]
    return ImageFont.truetype(os.path.join(FONTS, f), px)


# ---------------------------------------------------------------------------------------------- geometry
def add_parts(sc, fig, emissive=None):
    """a parts-only figure (a belt): v8's part shapes, BeltModel's materials"""
    for g in fig["parts"]:
        sx, sy, sz = g["size"]
        sh = g["shape"]
        smooth = True
        if sh == "Block":
            P, T = v8.box(sx, sy, sz)
            smooth = False
        elif sh == "Ball":
            r = min(sx, sy, sz) / 2
            P, T = v8.uv_sphere(r, r, r)
        elif sh == "Cylinder":
            r = min(sy, sz) / 2
            P, T = v8.cylinder_x(sx, r, r, n=40)
        elif sh == "Wedge":
            P, T = v8.wedge(sx, sy, sz)
            smooth = False
        else:
            P, T = v8.box(sx, sy, sz)
            smooth = False
        mat = sc.gear_mat(g["color"], g["material"], g.get("reflectance", 0))
        if g["material"] == "Glass":
            mat = glass_mat(sc, g["color"])
        elif g["material"] == "Neon":
            mat = emission_mat(sc, g["color"], 3.0)
        ob = sc.add_world(v8.place(P, g["cf"], np.zeros(3)), T, g["name"], mat=mat, smooth=smooth)
        if not smooth:
            for poly in ob.data.polygons:
                poly.use_smooth = False


_extra = {}


def glass_mat(sc, color):
    key = ("glass", tuple(round(c, 3) for c in color))
    if key in _extra:
        return _extra[key]
    m = bpy.data.materials.new("jewel")
    m.use_nodes = True
    bs = m.node_tree.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = (*v8.srgb2lin(color), 1)
    bs.inputs["Roughness"].default_value = 0.05
    bs.inputs["Metallic"].default_value = 0.2
    try:
        bs.inputs["Coat Weight"].default_value = 1.0
    except KeyError:
        pass
    _extra[key] = m
    return m


def emission_mat(sc, color, strength):
    key = ("emit", tuple(round(c, 3) for c in color), strength)
    if key in _extra:
        return _extra[key]
    m = bpy.data.materials.new("emit")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*v8.srgb2lin(color), 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    _extra[key] = m
    return m


def drop_floor(sc):
    for ob in list(sc.sc.collection.objects):
        if ob.name.startswith("floor"):
            bpy.data.objects.remove(ob, do_unlink=True)


def new_scene(res, samples, lens=50, bg=(0.11, 0.115, 0.125)):
    _extra.clear()
    return v8.V8Scene(res=res, samples=samples, lens=lens, bg=bg)


# ---------------------------------------------------------------------------------------------- belts
def render_belts(scene_dir, out_dir, samples):
    data = json.load(open(os.path.join(scene_dir, "belts.json")))
    by = {}
    for b in data["belts"]:
        by.setdefault(b["key"], {})[b["mode"]] = b
    cells = {}
    for key, modes in by.items():
        paths, labels = [], []
        disp = modes.get("display")
        if disp:
            for vname, view, dist in (("front", (0, 4, 1.0), 12.5), ("3/4", (35, 16, 1.0), 12.0), ("plate", (12, 8, 1.0), 4.6)):
                sc = new_scene((560, 340), samples, lens=50, bg=(0.07, 0.072, 0.08))
                add_parts(sc, disp["figure"])
                sc.rig((0, 0, 0), 3.2)
                p = os.path.join(out_dir, f"_belt_{key}_{vname.replace('/', '')}.png")
                sc.render(p, view=view, dist=dist, focus=(0, 0, 0.4) if vname != "plate" else (0, 0.05, 0))
                paths.append(p)
                labels.append(f"{disp['name']}  {vname}")
        worn = modes.get("worn")
        if worn:
            sc = new_scene((560, 340), samples, lens=50, bg=(0.07, 0.072, 0.08))
            add_parts(sc, worn["figure"])
            sc.rig((0, 0, 0), 1.6)
            p = os.path.join(out_dir, f"_belt_{key}_worn.png")
            sc.render(p, view=(30, 24, 1.0), dist=3.6, focus=(0, 0, -0.1))
            paths.append(p)
            labels.append("worn (round a waist)")
        out = os.path.join(out_dir, f"belt_{key}.jpg")
        d = (disp or {}).get("design", {})
        render.sheet(paths, out, cols=len(paths), labels=labels,
                     title=f"{(disp or worn)['name']}  -  plate {d.get('shape')}, emblem {d.get('emblem')}, side plates {d.get('sides')} a side, {(disp or {}).get('parts')} parts")
        cells[key] = paths
        print("rendered", out, flush=True)
    tkeys = [k for k in ("novice", "city", "regional", "national", "world") if k in cells]
    okeys = [k for k in by if k not in tkeys]
    for name, keys in (("belts_tournaments.jpg", tkeys), ("belts_titles.jpg", okeys)):
        paths, labels = [], []
        for k in keys:
            for i, p in enumerate(cells[k]):
                if i in (0, 1, 3):
                    paths.append(p)
                    labels.append(f"{by[k].get('display', by[k].get('worn'))['name']}  {('front', '3/4', '', 'worn')[i]}")
        render.sheet(paths, os.path.join(out_dir, name), cols=3, labels=labels,
                     title="tournament belts (BeltModel: strap, centre plate, side plates, emblem)" if name.startswith("belts_t") else "title belts")
        print("rendered", os.path.join(out_dir, name), flush=True)
    for paths in cells.values():
        for p in paths:
            if os.path.exists(p):
                os.remove(p)


# ---------------------------------------------------------------------------------------------- the arena
def arena(sc, rng, wide):
    h = 11.0
    # canvas, apron skirt, posts, ropes (as v9_referee_render's ring, ring half 11)
    P = np.array([(-h - 1, 0.005, -h - 1), (h + 1, 0.005, -h - 1), (h + 1, 0.005, h + 1), (-h - 1, 0.005, h + 1)], float)
    T = np.array([(0, 2, 1), (0, 3, 2)])
    sc.add_world(P, T, "canvas", mat=sc.gear_mat((0.78, 0.8, 0.84), "Fabric", 0), smooth=False)
    Pa, Ta = v8.box(2 * h + 2, 4.0, 2 * h + 2)
    sc.add_world(Pa + np.array([0, -2.01, 0]), Ta, "apron", mat=sc.gear_mat((0.06, 0.06, 0.08), "Fabric", 0), smooth=False)
    post = sc.gear_mat((0.75, 0.75, 0.78), "Metal", 0)
    pad = sc.gear_mat((0.75, 0.08, 0.1), "SmoothPlastic", 0)
    rope = sc.gear_mat((0.85, 0.85, 0.88), "SmoothPlastic", 0)
    posts = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            Pp, Tp = v8.box(0.35, 4.8, 0.35)
            sc.add_world(Pp + np.array([sx * h, 2.4, sz * h]), Tp, "post", mat=post, smooth=False)
            Pq, Tq = v8.box(0.6, 3.2, 0.6)
            sc.add_world(Pq + np.array([sx * h, 2.6, sz * h]), Tq, "pad", mat=pad, smooth=False)
            posts.append(np.array([sx * h, 4.9, sz * h]))
    for y in (1.6, 2.7, 3.8):
        for (x0, z0, x1, z1) in ((-h, -h, h, -h), (-h, h, h, h), (-h, -h, -h, h), (h, -h, h, h)):
            length = math.hypot(x1 - x0, z1 - z0)
            Pc, Tc = v8.cylinder_x(length, 0.07, 0.07, n=12)
            ang = math.atan2(z1 - z0, x1 - x0)
            R = np.array([[math.cos(ang), 0, -math.sin(ang)], [0, 1, 0], [math.sin(ang), 0, math.cos(ang)]])
            c = np.array([(x0 + x1) / 2, y, (z0 + z1) / 2])
            sc.add_world(Pc @ R.T + c, Tc, "rope", mat=rope)
    # the arena floor and the crowd on risers round the ring
    Pf = np.array([(-90, -4.0, -90), (90, -4.0, -90), (90, -4.0, 90), (-90, -4.0, 90)], float)
    sc.add_world(Pf, T, "arenafloor", mat=sc.gear_mat((0.03, 0.03, 0.035), "Plastic", 0), smooth=False)
    shirts = [(0.75, 0.1, 0.12), (0.12, 0.2, 0.6), (0.85, 0.85, 0.85), (0.1, 0.1, 0.12), (0.8, 0.6, 0.15), (0.2, 0.45, 0.25)]
    skins = [(0.86, 0.66, 0.52), (0.6, 0.42, 0.3), (0.38, 0.25, 0.17), (0.95, 0.78, 0.64)]
    groups = {}
    sb, st = v8.box(0.9, 1.3, 0.6)
    hb, ht = v8.uv_sphere(0.32, 0.36, 0.32, nu=8, nv=6)
    riser = sc.gear_mat((0.05, 0.05, 0.06), "Plastic", 0)
    for row in range(8):
        r = 17.0 + row * 2.3
        y = -4.0 + row * 1.35
        Pr, Tr = v8.box(2 * r + 2.3, 1.35 * (row + 1), 2 * r + 2.3)
        # (the risers: a hollow step ring drawn as four slabs)
        for (cx, cz, lx, lz) in ((0, -r, 2 * r, 2.3), (0, r, 2 * r, 2.3), (-r, 0, 2.3, 2 * r), (r, 0, 2.3, 2 * r)):
            Ps, Ts = v8.box(lx + 2.3, 1.35, lz)
            sc.add_world(Ps + np.array([cx, y - 0.67 + 1.35, cz]), Ts, "riser", mat=riser, smooth=False)
        n = int(8 * r / 1.25)
        for k in range(n):
            u = k / n * 8 * r
            side = int(u // (2 * r))
            s = u - side * 2 * r - r
            x, z = [(s, -r), (r, s), (-s, r), (-r, -s)][side]
            if rng.random() < 0.12:
                continue
            base = np.array([x, y + 1.35, z]) + rng.normal(0, 0.08, 3)
            shirt = shirts[rng.integers(len(shirts))]
            skin = skins[rng.integers(len(skins))]
            lift = 0.25 if wide and rng.random() < 0.5 else 0.0
            for (P0, T0, col, off) in ((sb, st, shirt, 0.65 + lift), (hb, ht, skin, 1.65 + lift)):
                g = groups.setdefault(col, [[], []])
                b = sum(len(p) for p in g[0])
                g[0].append(P0 + base + np.array([0, off, 0]))
                g[1].append(T0 + b)
    for col, (Ps, Ts) in groups.items():
        sc.add_world(np.concatenate(Ps), np.concatenate(Ts), "crowd", mat=sc.gear_mat(col, "Fabric", 0), smooth=False)
    # phone flashes in the stands
    if wide:
        Ps, Ts = [], []
        for _ in range(140):
            a = rng.uniform(0, 2 * math.pi)
            rr = rng.uniform(17, 33)
            p = np.array([math.cos(a) * rr, -2.0 + (rr - 17) * 0.6 + 2.2, math.sin(a) * rr])
            P0, T0 = v8.box(0.12, 0.12, 0.12)
            Ts.append(T0 + sum(len(q) for q in Ps))
            Ps.append(P0 + p)
        sc.add_world(np.concatenate(Ps), np.concatenate(Ts), "flashes", mat=emission_mat(sc, (1, 1, 1), 25), smooth=False)
    return posts


CONFETTI = [(1.0, 0.83, 0.36), (1, 1, 1), (0.86, 0.16, 0.2), (0.24, 0.5, 1.0), (1.0, 0.7, 0.2)]


def confetti(sc, rng, n, streamers):
    groups = {}
    for _ in range(n):
        a = rng.uniform(0, 2 * math.pi)
        rr = math.sqrt(rng.uniform(0, 1)) * 11
        p = np.array([math.cos(a) * rr, rng.uniform(0.6, 15), math.sin(a) * rr])
        col = CONFETTI[rng.integers(len(CONFETTI))]
        w, h = (0.1, 1.1) if streamers else (0.24, 0.24)
        q = np.array([(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)])
        ax = rng.normal(size=3)
        ax /= np.linalg.norm(ax)
        ang = rng.uniform(0, math.pi)
        K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
        R = np.eye(3) + math.sin(ang) * K + (1 - math.cos(ang)) * (K @ K)
        g = groups.setdefault(col, [[], []])
        b = sum(len(x) for x in g[0])
        g[0].append(q @ R.T + p)
        g[1].append(np.array([(0, 1, 2), (0, 2, 3), (0, 2, 1), (0, 3, 2)]) + b)
    for col, (Ps, Ts) in groups.items():
        m = sc.gear_mat(col, "Foil" if col[0] > 0.9 and col[2] < 0.5 else "SmoothPlastic", 0.1)
        sc.add_world(np.concatenate(Ps), np.concatenate(Ts), "confetti", mat=m, smooth=False)


def pyro(sc, rng, posts):
    m = emission_mat(sc, (1.0, 0.72, 0.3), 30)
    for p in posts:
        Ps, Ts = [], []
        for _ in range(26):
            d = np.array([rng.normal(0, 0.18), 1, rng.normal(0, 0.18)])
            d /= np.linalg.norm(d)
            start = p + d * rng.uniform(0.3, 6.5)
            L = rng.uniform(0.5, 1.4)
            P0, T0 = v8.box(0.05, L, 0.05)
            Ts.append(T0 + sum(len(q) for q in Ps))
            Ps.append(P0 + start)
        sc.add_world(np.concatenate(Ps), np.concatenate(Ts), "sparks", mat=m, smooth=False)
        ld = bpy.data.lights.new("pyro", "POINT")
        ld.energy = 9000
        ld.color = (1.0, 0.65, 0.3)
        ld.shadow_soft_size = 1.0
        ob = bpy.data.objects.new("pyro", ld)
        bpy.context.view_layer.update()
        ob.location = sc.root.matrix_world @ Vector(tuple(p + np.array([0, 2.0, 0])))
        sc.sc.collection.objects.link(ob)


def spots(sc, target, wide, t):
    bpy.context.view_layer.update()
    M = sc.root.matrix_world
    for i in range(3):
        a = i / 3 * 2 * math.pi + 0.4
        pos = np.array([math.cos(a) * 9, 26, math.sin(a) * 9])
        aim = np.array(target)
        if wide and i > 0:
            b = a + t * 0.9
            aim = np.array([math.cos(b) * 30, -2, math.sin(b) * 30])
        ld = bpy.data.lights.new("spot", "SPOT")
        ld.energy = 60000 if i == 0 else 38000
        ld.spot_size = math.radians(26)
        ld.spot_blend = 0.35
        ld.color = (1.0, 0.96, 0.88) if i == 0 else (1.0, 0.88, 0.62)
        ld.shadow_soft_size = 0.6
        ob = bpy.data.objects.new("spot", ld)
        ob.location = M @ Vector(tuple(pos))
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = (M @ Vector(tuple(aim)) - ob.location).to_track_quat("-Z", "Y")
        sc.sc.collection.objects.link(ob)
    # the house lights over the stands (dim)
    ld = bpy.data.lights.new("house", "AREA")
    ld.energy = 26000
    ld.size = 60
    ld.color = (0.8, 0.82, 1.0)
    ob = bpy.data.objects.new("house", ld)
    ob.location = M @ Vector((0, 34, 0))
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = (M @ Vector((0, 0, 0)) - ob.location).to_track_quat("-Z", "Y")
    sc.sc.collection.objects.link(ob)


def set_camera(sc, cf, fov):
    bpy.context.view_layer.update()
    M = sc.root.matrix_world
    M3 = M.to_3x3()
    p = Vector(tuple(cf[:3]))
    r = cf[3:]
    right = M3 @ Vector((r[0], r[3], r[6]))
    up = M3 @ Vector((r[1], r[4], r[7]))
    back = M3 @ Vector((r[2], r[5], r[8]))
    R = Matrix((right, up, back)).transposed()
    sc.cam.location = M @ p
    sc.cam.rotation_mode = "QUATERNION"
    sc.cam.rotation_quaternion = R.to_quaternion()
    cam = sc.cam.data
    cam.sensor_fit = "VERTICAL"
    cam.sensor_height = 24
    cam.lens = 12 / math.tan(math.radians(fov) / 2)
    cam.clip_end = 400


# ---------------------------------------------------------------------------------------------- the 2D layer
def belt_badge(design_png, size):
    if design_png and os.path.exists(design_png):
        im = Image.open(design_png).convert("RGB")
        w, h = im.size
        im = im.crop((int(w * 0.12), int(h * 0.18), int(w * 0.88), int(h * 0.82)))
        im.thumbnail(size)
        return im
    return None


def overlay(path, frame, badge):
    im = Image.open(path).convert("RGBA")
    W, H = im.size
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bar = int(H * 0.09)
    d.rectangle((0, 0, W, bar), fill=(0, 0, 0, 255))
    d.rectangle((0, H - bar, W, H), fill=(0, 0, 0, 255))
    k = W / 1600
    b = frame.get("banner") or {}
    if b.get("kicker"):
        bw, bh = int(min(860, 1560) * k * 1.0), int(150 * k)
        x0, y1 = (W - bw) // 2, H - bar - int(10 * k)
        y0 = y1 - bh
        glass = Image.new("RGBA", (bw, bh), (12, 13, 18, 214))
        layer.alpha_composite(glass, (x0, y0))
        d.rectangle((x0, y0, x0 + bw, y0 + max(2, int(4 * k))), fill=(*GOLD, 255))
        tx = x0 + int(14 * k)
        if badge is not None:
            bb = badge.copy()
            bb.thumbnail((int(104 * k), int(104 * k)))
            layer.alpha_composite(bb.convert("RGBA"), (tx, y0 + (bh - bb.size[1]) // 2))
            tx += int(122 * k)
        d.text((tx, y0 + int(12 * k)), b["kicker"], font=font("displayMed", max(10, int(19 * k))), fill=(*GOLD, 255))
        if b.get("title"):
            d.text((tx, y0 + int(34 * k)), b["title"], font=font("display", max(14, int(42 * k))), fill=(*GOLD, 255))
        if b.get("name"):
            d.text((tx, y0 + int(86 * k)), b["name"], font=font("displayMed", max(10, int(24 * k))), fill=(240, 240, 244, 255))
        if b.get("event"):
            d.text((tx, y0 + int(118 * k)), b["event"].upper(), font=font("semi", max(8, int(12 * k))), fill=(150, 154, 166, 255))
    # SKIP (top right, under the top letterbox's edge)
    sw, sh = int(120 * k), int(44 * k)
    sx, sy = W - int(16 * k) - sw, int(12 * k) + int(36 * k)
    d.rounded_rectangle((sx, sy, sx + sw, sy + sh), radius=int(8 * k), fill=(36, 39, 48, 235), outline=(90, 94, 106, 255))
    f = font("displayMed", max(9, int(18 * k)))
    tw = d.textlength("SKIP", font=f)
    d.text((sx + (sw - tw) / 2, sy + sh * 0.2), "SKIP", font=f, fill=(240, 240, 244, 255))
    d.text((sx + sw - d.textlength("SPACE", font=font("semi", max(8, int(11 * k)))), sy + sh + int(4 * k)), "SPACE",
           font=font("semi", max(8, int(11 * k))), fill=(150, 154, 166, 255))
    im.alpha_composite(layer)
    im.convert("RGB").save(path.replace(".png", ".jpg"), quality=92)
    os.remove(path)
    return path.replace(".png", ".jpg")


def render_story(scene_dir, out_dir, samples, res, only_frames):
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    badge = belt_badge(os.path.join(out_dir, "_badge.png"), (220, 120))
    outs, labels = [], []
    for fr_ in idx["frames"]:
        if only_frames and fr_["id"] not in only_frames:
            continue
        frame = json.load(open(os.path.join(scene_dir, fr_["file"])))
        rng = np.random.default_rng(int(frame["t"] * 1000))
        sc = new_scene(res, samples, lens=50, bg=(0.012, 0.012, 0.016))
        drop_floor(sc)
        fx = frame["fx"]
        wide = frame["shot"] == "wide"
        posts = arena(sc, rng, wide)
        winner = None
        for f in frame["figures"]:
            if f["role"] == "belt":
                add_parts(sc, f)
            else:
                d = dict(f)
                d.setdefault("hair", [])
                d.setdefault("parts", [])
                v8.add_boxer(sc, scene_dir, d)
                if f["role"] == "winner":
                    winner = f
        hp = np.array(winner["head"]["cf"][:3])
        # the studio rig, scaled round the winner (the key / fill / rims), then the arena's own lights
        sc.rig(tuple(hp - np.array([0, 1.2, 0])), 2.6)
        spots(sc, tuple(hp - np.array([0, 1.5, 0])), wide, frame["t"])
        if fx.get("confetti"):
            confetti(sc, rng, 1100 if wide else 700, False)
        if fx.get("streamers"):
            confetti(sc, rng, 180, True)
        if fx.get("pyro"):
            pyro(sc, rng, posts)
        set_camera(sc, frame["camera"]["cf"], frame["camera"]["fov"])
        p = os.path.join(out_dir, f"story_{frame['id']}.png")
        sc.sc.render.filepath = os.path.abspath(p)
        bpy.ops.render.render(write_still=True)
        out = overlay(p, frame, badge)
        outs.append(out)
        labels.append(f"t = {frame['t']:.1f} s  ·  {frame['shot']}  ·  {fr_.get('pose')}")
        print("rendered", out, flush=True)
    if outs:
        render.sheet(outs, os.path.join(out_dir, "storyboard.jpg"), cols=2, labels=labels,
                     title="celebration cutscene storyboard (10.5 s): close-up + hand raised, orbit + the belt strapped on, hero lift, crowd wide")
        print("rendered", os.path.join(out_dir, "storyboard.jpg"), flush=True)


def render_badge(scene_dir, out_dir, samples):
    data = json.load(open(os.path.join(scene_dir, "belts.json")))
    for b in data["belts"]:
        if b["key"] == "world" and b["mode"] == "display":
            sc = new_scene((440, 260), samples, lens=50, bg=(0.05, 0.052, 0.06))
            add_parts(sc, b["figure"])
            sc.rig((0, 0, 0), 3.2)
            sc.render(os.path.join(out_dir, "_badge.png"), view=(0, 4, 1.0), dist=12.0, focus=(0, 0, 0.4))


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
    samples = int(opts.get("--samples", 24))
    only = set(opts.get("--only", "belts,story").split(","))
    res = tuple(int(x) for x in opts.get("--res", "960x540").split("x"))
    frames = set(opts["--frames"].split(",")) if "--frames" in opts else None
    if "belts" in only:
        render_belts(scene_dir, out_dir, samples)
    if "story" in only:
        render_badge(scene_dir, out_dir, samples)
        render_story(scene_dir, out_dir, samples, res, frames)
        if os.path.exists(os.path.join(out_dir, "_badge.png")):
            os.remove(os.path.join(out_dir, "_badge.png"))
