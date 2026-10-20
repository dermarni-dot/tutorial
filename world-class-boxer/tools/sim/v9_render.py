"""Cycles filmstrips of the clips tools/sim/v9_anim.luau records (the client Animator on tier boxers).

    /opt/bpyenv/bin/python tools/sim/v9_render.py SCENE_DIR OUT_DIR [--only id,id] [--samples N] [--tag before|after]
                                                 [--views front,side]

Per clip (walk_t3, jog_t5, punch_t1, ...): every recorded frame side by side in ONE scene under an orthographic camera
(so a sway or a reach reads in studs against the column's red centre line: the HumanoidRootPart's line), one image per
view: <OUT>/<tag>_<clip>_<view>.jpg. Punch clips: windup / mid / peak per punch, the opponent drawn at the peaks.
Geometry exactly as v8_render.add_boxer draws a v8 scene (tier meshes, classic head + decal, gear meshes, Kit parts).
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


def add_line(sc, x, z, h=7.2, col=(0.55, 0.08, 0.08), along="y", w=0.025):
    P, T = v8.box(w, h, w)
    P = P + np.array([x, h / 2, z])
    sc.add_world(P, T, "line", mat=sc.gear_mat(col, "Neon", 0), smooth=False)


def frame_dict(fr):
    d = {"meshes": fr["meshes"], "head": fr["head"], "parts": fr.get("parts", []), "hair": []}
    return d


def render_clip(scene_dir, out_dir, clip, samples, views, tag):
    data = json.load(open(os.path.join(scene_dir, clip["file"])))
    frames = data["frames"]
    n = len(frames)
    punch = clip["clip"] == "punch"
    gap = float(os.environ.get("V9_GAP") or (3.2 if punch else 2.7))
    paths = []
    for view in views:
        width = (n - 1) * gap + (3.4 if punch else 2.6)
        H = 7.6
        res_y = int(opts_res) if (opts_res := os.environ.get("V9_RES")) else 820
        res_x = int(res_y * width / H)
        sc = v8.V8Scene(res=(min(res_x, 3600), res_y), samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
        for i, fr in enumerate(frames):
            root = fr.get("root") or [0, 0, 0]
            rz = root[2]
            rx = root[0]
            k = i - (n - 1) / 2
            if view == "front":
                off = (-k * gap - rx, 0, -rz)
            else:
                # side: seen from the character's right (+X), forward (-Z) to the viewer's right
                off = (-rx, 0, -k * gap - rz)
            v8.add_boxer(sc, scene_dir, frame_dict(fr), offset=off)
            if fr.get("opp") and view == "side":
                v8.add_boxer(sc, scene_dir, frame_dict(fr["opp"]), offset=off)
            if view == "front":
                add_line(sc, off[0] + rx, off[2] + rz + 1.4)
            else:
                add_line(sc, off[0] + rx - 1.4, off[2] + rz)
        cam = sc.cam
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = max(width, H * res_x / res_y)
        focus = (0, H / 2 - 0.2, 0 if not punch else -1.7)
        sc.rig(focus, 6.0)
        p = os.path.join(out_dir, f"_{tag}_{clip['id']}_{view}.png")
        if view == "front":
            sc.render(p, view=(0, 0.01, 1.0), dist=30, focus=focus)
        else:
            sc.render(p, view=(90, 0.01, 1.0), dist=30, focus=focus)
        labels = [fr.get("label") or f"{i + 1}/{n}" for i, fr in enumerate(frames)]
        if view == "side" and not punch:
            labels = labels  # (left to right = frame order)
        from PIL import Image, ImageDraw, ImageFont
        im = Image.open(p).convert("RGB")
        W = Image.new("RGB", (im.width, im.height + 70), (26, 27, 30))
        W.paste(im, (0, 40))
        dr = ImageDraw.Draw(W)
        tf = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
        title = f"{tag}: {clip['id']} ({view}, orthographic; red line = HumanoidRootPart centre line)"
        if clip["clip"] in ("walk", "jog", "run", "sprint"):
            title += f", v = {data.get('speed')} studs/s, one gait cycle"
        dr.text((10, 9), title, fill=(235, 235, 235), font=tf)
        colw = im.width / n
        for i, lab in enumerate(labels):
            # front view: frame 0 is at the viewer's left (offset -k * gap: +X = viewer's left)
            ci = i if view == "front" else i
            cx = (ci + 0.5) * colw
            dr.text((cx - dr.textlength(lab, font=f) / 2, im.height + 46), lab, fill=(210, 210, 210), font=f)
        out = os.path.join(out_dir, f"{tag}_{clip['id']}_{view}.jpg")
        W.save(out, quality=88)
        os.remove(p)
        paths.append(out)
        print("rendered", out, flush=True)
    return paths


def render_gif(scene_dir, out_dir, clip, samples, view, tag, ms=None):
    """every recorded frame on its own, the camera following the root (the boxer stays in the middle), as an animated
    GIF: <OUT>/<tag>_<clip>_<view>.gif. Floor marks every stud stay put in the world, so a planted foot that slides
    shows against them; the red line is the root's centre line. ms = the GIF's frame time (default: the clip's own
    frame spacing, from the frames' t)"""
    from PIL import Image, ImageDraw, ImageFont
    data = json.load(open(os.path.join(scene_dir, clip["file"])))
    frames = data["frames"]
    imgs = []
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    for i, fr in enumerate(frames):
        root = fr.get("root") or [0, 0, 0]
        rx, rz = root[0], root[2]
        sc = v8.V8Scene(res=(420, 560), samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
        off = (-rx, 0, -rz)
        v8.add_boxer(sc, scene_dir, frame_dict(fr), offset=off)
        # floor marks (world-fixed): thin bars across the walking line every stud
        for k in range(-6, 7):
            if view == "side":
                zz = math.floor(rz) + k - rz
                P, T = v8.box(1.6, 0.012, 0.035)
                P = P + np.array([-0.9, 0.006, zz])
            else:
                xx = math.floor(rx) + k - rx
                P, T = v8.box(0.035, 0.012, 1.6)
                P = P + np.array([xx, 0.006, 0.9])
            sc.add_world(P, T, "mark", mat=sc.gear_mat((0.45, 0.45, 0.48), "SmoothPlastic", 0), smooth=False)
        if view == "front":
            add_line(sc, 0, 1.4)
        else:
            add_line(sc, -1.4, 0)
        cam = sc.cam
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 7.4
        focus = (0, 3.6, 0)
        sc.rig(focus, 6.0)
        p = os.path.join(out_dir, f"_{tag}_{clip['id']}_{view}_{i}.png")
        sc.render(p, view=(0, 0.01, 1.0) if view == "front" else (90, 0.01, 1.0), dist=30, focus=focus)
        im = Image.open(p).convert("RGB")
        dr = ImageDraw.Draw(im)
        lab = f"{tag}: {clip['id']} {view}  {fr.get('label') or f'{i + 1}/{len(frames)}'}"
        dr.text((8, 8), lab, fill=(230, 230, 230), font=f)
        imgs.append(im)
        os.remove(p)
    if ms is None:
        ts = [fr.get("t") for fr in frames]
        ms = 60
        if len(ts) > 1 and all(t is not None for t in ts):
            ms = max(20, int(round(1000 * (ts[-1] - ts[0]) / (len(ts) - 1))))
    out = os.path.join(out_dir, f"{tag}_{clip['id']}_{view}.gif")
    pal = [im.quantize(colors=128, method=Image.Quantize.MEDIANCUT) for im in imgs]
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=ms, loop=0, optimize=True)
    print("rendered", out, flush=True)
    return out


def part_pos(fr, name):
    for m in fr["meshes"]:
        if m["name"] == name:
            P = np.asarray(m["p"]).reshape(-1, 3)
            return (P.min(0) + P.max(0)) / 2
    return None


def render_punches(scene_dir, out_dir, clip, samples, tag, views=("side", "34")):
    """one panel per recorded frame (windup / mid / peak per punch), the opponent drawn at the peaks; per view one
    sheet: side (from the puncher's right) and 3/4 from behind the opponent's shoulder (the punch coming at you)"""
    data = json.load(open(os.path.join(scene_dir, clip["file"])))
    frames = data["frames"]
    outs = []
    for view in views:
        paths, labels = [], []
        for i, fr in enumerate(frames):
            sc = v8.V8Scene(res=(420, 470), samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
            root = fr.get("root") or [0, 0, 0]
            v8.add_boxer(sc, scene_dir, frame_dict(fr))
            if fr.get("opp"):
                v8.add_boxer(sc, scene_dir, frame_dict(fr["opp"]))
            # the boxer stands at z = +1.7 facing -Z, the opponent at z = -1.7
            focus = (0, 4.3, 0.0)
            sc.rig(focus, 4.0)
            p = os.path.join(out_dir, f"_{tag}_{clip['id']}_{view}_{i}.png")
            if view == "side":
                sc.render(p, view=(90, 4, 1.0), dist=14.0, focus=(0, 3.6, 0.0))
            else:
                # from behind the puncher's rear shoulder, above: the punch's path to the target
                sc.render(p, view=(55, 12, 1.0), dist=12.0, focus=(0, 4.0, 0.0))
            paths.append(p)
            labels.append(fr.get("label") or str(i))
        out = os.path.join(out_dir, f"{tag}_{clip['id']}_{view}.jpg")
        render.sheet(paths, out, cols=6, labels=labels, title=f"{tag}: {clip['id']} punches ({view}; tier {clip['tier']} boxer in black, a tier 3 opponent 4 studs away)",
                     cell=(300, 336))
        for p in paths:
            os.remove(p)
        print("rendered", out, flush=True)
        outs.append(out)
    return outs


def render_arm_closeups(scene_dir, out_dir, clip, samples, tag):
    """the puncher's arms close up: the guard (a punch's first frame) and the jab / cross / hook peaks, from the
    outside and from above-behind the shoulder: the shoulder ball, the elbow, the wrist under the glove"""
    data = json.load(open(os.path.join(scene_dir, clip["file"])))
    want = ["jab start", "jab peak", "cross peak", "leadhook peak", "rearhook peak", "uppercut peak"]
    frames = [fr for fr in data["frames"] if fr.get("label") in want]
    paths, labels = [], []
    for fr in frames:
        sc = v8.V8Scene(res=(420, 470), samples=samples, lens=85, bg=(0.11, 0.115, 0.125))
        v8.add_boxer(sc, scene_dir, frame_dict(fr))
        hand = "Left" if fr["label"].startswith(("jab", "leadhook")) else "Right"
        el = part_pos(fr, hand + "UpperArm")
        f = tuple(el + np.array([0, -0.2, 0]))
        sc.rig(f, 1.5)
        for nm, v in (("out", (-80 if hand == "Left" else 80, 10, 1.0)), ("top", (160, 40, 1.0))):
            p = os.path.join(out_dir, f"_{tag}_{clip['id']}_arm_{len(paths)}.png")
            sc.render(p, view=v, dist=2.9 / math.tan(math.atan(18 / 85)), focus=f)
            paths.append(p)
            labels.append(f"{fr['label']} ({hand.lower()} arm, {nm})")
    out = os.path.join(out_dir, f"{tag}_{clip['id']}_arms.jpg")
    render.sheet(paths, out, cols=4, labels=labels, title=f"{tag}: {clip['id']} arms close up (guard and punch peaks)", cell=(360, 403))
    for p in paths:
        os.remove(p)
    print("rendered", out, flush=True)
    return [out]


def render_rest(scene_dir, out_dir, clip, samples, tag):
    """the standing boxer: full body front / side / back / 3/4, and close-ups of the right arm, the hands, the hips"""
    data = json.load(open(os.path.join(scene_dir, clip["file"])))
    fr = data["frames"][0]
    d = frame_dict(fr)
    root = fr.get("root") or [0, 0, 0]
    off = (-root[0], 0, -root[2])
    sc = v8.V8Scene(res=(520, 820), samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
    v8.add_boxer(sc, scene_dir, d, offset=off)
    top = d["head"]["cf"][1] + d["head"]["size"][1] / 2 + 0.1
    body_focus = (0, top / 2, 0)
    body_dist = (top / 2 + 0.45) / math.tan(math.atan(18 / 50))
    paths, labels = [], []
    def shot(name, view, focus, dist, lens, label, scale=3.0, res=None):
        sc.cam.data.lens = lens
        if res:
            sc.sc.render.resolution_x, sc.sc.render.resolution_y = res
        sc.rig(focus, scale)
        p = os.path.join(out_dir, f"_{tag}_{clip['id']}_{name}.png")
        sc.render(p, view=view, dist=dist, focus=focus)
        paths.append(p)
        labels.append(label)
    for name, view, lab in (("front", (0, 4, 1.0), "front"), ("34", (35, 6, 1.0), "3/4"), ("side", (90, 2, 1.0), "side (right)"),
                            ("back", (180, 6, 1.0), "back")):
        shot(name, view, body_focus, body_dist, 50, lab, res=(520, 820))
    def rel(name):
        q = part_pos(fr, name)
        return None if q is None else tuple(q + np.array(off))
    el = rel("RightUpperArm")
    hd = rel("RightHand")
    hl = rel("LeftHand")
    lt = rel("LowerTorso")
    if el is not None:
        shot("arm_front", (20, 2, 1.0), el, 2.2 / math.tan(math.atan(18 / 85)) * 0.6, 85, "right arm (front 3/4)", 1.2, (520, 820))
        shot("arm_back", (150, 4, 1.0), el, 2.2 / math.tan(math.atan(18 / 85)) * 0.6, 85, "right arm (back 3/4)", 1.2, (520, 820))
    if hd is not None:
        for nm, v in (("hand_out", (90, 4, 1.0)), ("hand_front", (0, 6, 1.0)), ("hand_in", (-60, 6, 1.0))):
            shot(nm, v, hd, 0.9 / math.tan(math.atan(18 / 85)), 85, "right hand " + nm[5:], 0.6, (520, 820))
    if lt is not None:
        shot("hips_front", (25, 2, 1.0), lt, 1.9 / math.tan(math.atan(18 / 85)), 85, "hips (front 3/4)", 1.2, (520, 820))
    out = os.path.join(out_dir, f"{tag}_{clip['id']}.jpg")
    render.sheet(paths, out, cols=6, labels=labels, title=f"{tag}: {clip['id']} standing (tier {clip['tier']})", cell=(390, 615))
    for p in paths:
        os.remove(p)
    print("rendered", out, flush=True)
    return [out]


FIGHT_VIEWS = {
    # side: from the puncher's (A's) right, both men in profile; 34: behind A's right shoulder, the punch going away
    "side": dict(view=(90, 3, 1.0), dist=30, ortho=8.8, focus=(0, 3.25, 0.0)),
    "34": dict(view=(142, 12, 1.0), dist=16.5, ortho=None, focus=(0, 3.1, 0.2)),
}


def fight_scene(scene_dir, fr, samples, view, res):
    vw = FIGHT_VIEWS[view]
    sc = v8.V8Scene(res=res, samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
    v8.add_boxer(sc, scene_dir, frame_dict(fr))
    if fr.get("opp"):
        v8.add_boxer(sc, scene_dir, frame_dict(fr["opp"]))
    if fr.get("ref"):
        v8.add_boxer(sc, scene_dir, frame_dict(fr["ref"]))
    # floor marks every stud along both axes (world-fixed: a skating foot shows against them)
    for k in range(-5, 6):
        P, T = v8.box(0.03, 0.012, 9.0)
        sc.add_world(P + np.array([k, 0.006, 0]), T, "markx", mat=sc.gear_mat((0.42, 0.42, 0.45), "SmoothPlastic", 0), smooth=False)
        P, T = v8.box(9.0, 0.012, 0.03)
        sc.add_world(P + np.array([0, 0.006, k]), T, "markz", mat=sc.gear_mat((0.42, 0.42, 0.45), "SmoothPlastic", 0), smooth=False)
    # (motion previews: fewer bounces and samples - a GIF frame is on screen for 50 ms)
    if os.environ.get("V9_FAST", "1") == "1":
        sc.sc.cycles.max_bounces = 3
        sc.sc.cycles.transparent_max_bounces = 8
    cam = sc.cam
    if vw["ortho"]:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = vw["ortho"]
    sc.rig(vw["focus"], 5.0)
    return sc, vw


def render_fight(scene_dir, out_dir, clip, samples, views, tag, gif=False, ms=None, strip=8):
    """a fight scenario (both fighters, the referee when he is in it): a GIF of every recorded frame and / or a
    filmstrip of `strip` frames spread over it, per view (side, 3/4)"""
    from PIL import Image, ImageDraw, ImageFont
    data = json.load(open(os.path.join(scene_dir, clip["file"])))
    frames = data["frames"]
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    outs = []
    for view in views:
        if gif:
            imgs = []
            # (the GIF plays the action window, a little either side: --window 0 = every frame)
            fo = data.get("focus")
            if fo and os.environ.get("V9_WINDOW", "1") == "1":
                gframes = [fr for fr in frames if fo[0] - 0.25 <= fr.get("t", 0) <= fo[1] + 0.35] or frames
            else:
                gframes = frames
            for i, fr in enumerate(gframes):
                sc, vw = fight_scene(scene_dir, fr, samples, view, (400, 333))
                p = os.path.join(out_dir, f"_{tag}_{clip['id']}_{view}_{i}.png")
                sc.render(p, view=vw["view"], dist=vw["dist"], focus=vw["focus"])
                im = Image.open(p).convert("RGB")
                ImageDraw.Draw(im).text((8, 8), f"{tag}: {data.get('id')} {view}  {fr.get('label') or ''}", fill=(230, 230, 230), font=f)
                imgs.append(im)
                os.remove(p)
            if ms is None:
                ts = [fr.get("t") for fr in gframes]
                ms = max(20, int(round(1000 * (ts[-1] - ts[0]) / max(1, len(ts) - 1)))) if len(ts) > 1 else 60
            out = os.path.join(out_dir, f"{tag}_{clip['id']}_{view}.gif")
            pal = [im.quantize(colors=128, method=Image.Quantize.MEDIANCUT) for im in imgs]
            pal[0].save(out, save_all=True, append_images=pal[1:], duration=ms, loop=0, optimize=True)
            print("rendered", out, flush=True)
            outs.append(out)
        else:
            # (the strip spreads over the scenario's action window: the harness's focus [t0, t1])
            fo = data.get("focus")
            idx = [i for i, fr in enumerate(frames) if not fo or fo[0] - 1e-6 <= fr.get("t", 0) <= fo[1] + 1e-6] or list(range(len(frames)))
            n = len(idx)
            pick = sorted(set(idx[int(round(i * (n - 1) / max(1, strip - 1)))] for i in range(strip)))
            paths, labels = [], []
            for i in pick:
                fr = frames[i]
                sc, vw = fight_scene(scene_dir, fr, samples, view, (420, 360))
                p = os.path.join(out_dir, f"_{tag}_{clip['id']}_{view}_s{i}.png")
                sc.render(p, view=vw["view"], dist=vw["dist"], focus=vw["focus"])
                paths.append(p)
                labels.append(fr.get("label") or str(i))
            out = os.path.join(out_dir, f"{tag}_{clip['id']}_{view}.jpg")
            render.sheet(paths, out, cols=len(paths), labels=labels, title=f"{tag}: {data.get('id')} ({view})", cell=(300, 257))
            for p in paths:
                os.remove(p)
            print("rendered", out, flush=True)
            outs.append(out)
    return outs


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
    samples = int(opts.get("--samples", 24))
    views = opts.get("--views", "front,side").split(",")
    tag = opts.get("--tag", "after")
    for c in idx["clips"]:
        if only and c["id"] not in only:
            continue
        if c["clip"] == "fight":
            fv = [v for v in views if v in FIGHT_VIEWS] or ["side", "34"]
            render_fight(scene_dir, out_dir, c, samples, fv, tag, gif="--gif" in opts, ms=int(opts["--ms"]) if "--ms" in opts else None,
                         strip=int(opts.get("--strip", 8)))
        elif c["clip"] == "punch":
            render_punches(scene_dir, out_dir, c, samples, tag)
            render_arm_closeups(scene_dir, out_dir, c, samples, tag)
        elif c["clip"] == "rest":
            render_rest(scene_dir, out_dir, c, samples, tag)
        elif "--gif" in opts:
            for v in views:
                render_gif(scene_dir, out_dir, c, samples, v, tag, ms=int(opts["--ms"]) if "--ms" in opts else None)
        else:
            render_clip(scene_dir, out_dir, c, samples, views, tag)
