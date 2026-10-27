"""Cycles renders of the ring walk exported by tools/sim/v9_entrance.luau, in the Grand Arena of tools/sim/world_scene.luau.

    /opt/bpyenv/bin/python tools/sim/v9_entrance_render.py SCENE_DIR WORLD_JSON OUT_DIR [--only story,gif]
                                                           [--samples N] [--res 1280x720] [--shots id,id]

story: every shot of index.json through the game's own camera for it (EntranceFX.Shot: position, look, 70 degree vertical
field of view), the venue's parts / GUIs / lights near it (world_render.Builder), the figures (v8_render.add_boxer: tier
meshes, classic head + decal, gear, kit parts), EntranceFX's carriers and belt; the walkout's follow spot over the walker.
<OUT>/<id>.jpg and the sheet <OUT>/storyboard.jpg.
gif: each celebration's frames in a studio light rig, <OUT>/<gif id>.gif (12 fps) and a contact strip <OUT>/<gif id>_strip.jpg.
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
import world_render as WR  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402


def frame_dict(fr):
    return {"meshes": fr.get("meshes", []), "head": fr.get("head"), "parts": fr.get("parts", []), "hair": []}


def add_parts(sc, parts):
    for g in parts:
        sx, sy, sz = g["size"]
        sh = g["shape"]
        smooth = True
        if sh == "Ball":
            P, T = v8.uv_sphere(sx / 2, sy / 2, sz / 2)
        elif sh == "Cylinder":
            r = min(sy, sz) / 2
            P, T = v8.cylinder_x(sx, r, r)
        else:
            P, T = v8.box(sx, sy, sz)
            smooth = False
        ob = sc.add_world(v8.place(P, g["cf"], np.zeros(3)), T, g["name"], mat=sc.gear_mat(g["color"], g["material"], g.get("reflectance", 0)),
                          smooth=smooth)
        if not smooth:
            for poly in ob.data.polygons:
                poly.use_smooth = False


def add_figures(sc, scene_dir, figs):
    for f in figs:
        if f.get("head"):
            v8.add_boxer(sc, scene_dir, frame_dict(f))
        else:
            add_parts(sc, f.get("parts", []))


def game_scene(res, samples, keep_studio=False, bg=(0.01, 0.01, 0.014)):
    sc = v8.V8Scene(res=res, samples=samples, lens=35, bg=bg)
    # game space -> Blender exactly as world_render.to_b: (x, y, z) -> (x, -z, y)
    sc.root.rotation_euler = (math.pi / 2, 0, 0)
    for ob in list(sc.sc.collection.objects):
        if ob.name.startswith("floor") or (ob.type == "LIGHT" and not keep_studio):
            bpy.data.objects.remove(ob, do_unlink=True)
    if not keep_studio:
        sc.lights = []
    return sc


def camera(sc, cf, fov, res):
    cd = sc.cam.data
    cd.lens_unit = "FOV"
    vf = math.radians(fov)
    cd.angle = 2 * math.atan(math.tan(vf / 2) * res[0] / res[1])
    cd.clip_start = 0.2
    cd.clip_end = 3000
    pos = np.array(cf[:3])
    R = np.array(cf[3:]).reshape(3, 3)
    look = -R[:, 2]
    WR.look_at(sc.cam, tuple(pos), tuple(pos + look * 10))


def spot(name, pos, target, energy, color=(1.0, 0.95, 0.88), angle=16, blend=0.35, size=0.6):
    ld = bpy.data.lights.new(name, "SPOT")
    ld.energy = energy
    ld.color = color
    ld.spot_size = math.radians(angle)
    ld.spot_blend = blend
    ld.shadow_soft_size = size
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    WR.look_at(ob, pos, target)
    return ob


def area(name, pos, target, energy, color=(1, 1, 1), size=4):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy = energy
    ld.color = color
    ld.size = size
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    WR.look_at(ob, pos, target)
    return ob


def venue(world, floor_y, centre, radius, tmpdir):
    B = WR.Builder(tmpdir)
    n = 0
    for rname in ("venue_Arena", "VenueDetail_Arena"):
        root = world["roots"].get(rname)
        if not root:
            continue
        parts = [dict(p, cf=[p["cf"][0], p["cf"][1] - floor_y] + list(p["cf"][2:])) for p in root["parts"]]
        keep = [WR.near(p, centre, radius) for p in parts]
        for p, k in zip(parts, keep):
            if k:
                B.add_part(p, True)
                n += 1
        for g in root.get("guis", []):
            if keep[g["part"] - 1]:
                B.add_gui(g, parts[g["part"] - 1])
        for dc in root.get("decals", []):
            if keep[dc["part"] - 1]:
                B.add_decal(dc, parts[dc["part"] - 1])
        for bm in root.get("beams", []):
            a = np.array(bm["a"]) - np.array([0, floor_y, 0])
            if np.linalg.norm(a - centre) <= radius:
                B.add_beam(dict(bm, a=list(a), b=list(np.array(bm["b"]) - np.array([0, floor_y, 0]))))
        for L in root.get("lights", []):
            if keep[L["part"] - 1]:
                WR.add_light(L, parts[L["part"] - 1], True, 2.0)
    B.flush()
    return n


def render_story(scene_dir, world, out_dir, samples, res, shots_only):
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    floor_y = idx["venue"]["floorY"]
    tmpdir = os.path.join(out_dir, "_gui")
    os.makedirs(tmpdir, exist_ok=True)
    paths, labels = [], []
    for s in sorted(idx["shots"], key=lambda s: s["id"]):
        if shots_only and s["id"] not in shots_only:
            continue
        d = json.load(open(os.path.join(scene_dir, s["file"])))
        sc = game_scene(res, samples)
        WR.setup_world("night", 0)
        bpy.context.scene.view_settings.exposure = 1.4
        cam = d["camera"]
        eye = np.array(cam["cf"][:3])
        focus = np.array(d["focus"])
        mid = (eye + focus) / 2
        n = venue(world, floor_y, mid, max(70.0, np.linalg.norm(eye - focus) + 50), tmpdir)
        add_figures(sc, scene_dir, d["figures"])
        # the walkout's lighting (VenueFX): a follow spot on the walker from the rig, a warm key from the camera
        # side, the corner's red wash
        spot("follow", tuple(focus + np.array([3, 38, 6])), tuple(focus + np.array([0, 1.5, 0])), 26000, angle=11)
        spot("follow2", tuple(focus + np.array([-14, 30, -10])), tuple(focus + np.array([0, 2, 0])), 14000, (1.0, 0.86, 0.8), angle=13)
        to_cam = eye - focus
        to_cam[1] = 0
        to_cam = to_cam / max(1e-3, np.linalg.norm(to_cam))
        area("key", tuple(focus + to_cam * 9 + np.array([2, 6, 0])), tuple(focus + np.array([0, 2.5, 0])), 900, (1.0, 0.93, 0.85), 5)
        area("wash", tuple(focus + np.array([0, 9, 0]) - to_cam * 6), tuple(focus), 500, (1.0, 0.25, 0.22), 8)
        camera(sc, cam["cf"], cam.get("fov", 70), res)
        path = os.path.join(out_dir, s["id"] + ".jpg")
        sc.sc.render.image_settings.file_format = "JPEG"
        sc.sc.render.image_settings.quality = 90
        sc.sc.render.filepath = os.path.abspath(path)
        print("render", s["id"], "venue parts", n, flush=True)
        bpy.ops.render.render(write_still=True)
        paths.append(path)
        labels.append(s["id"] + "  " + s["label"])
    if paths and not shots_only:
        render.sheet(paths, os.path.join(out_dir, "storyboard.jpg"), 2, labels=labels, title="v9 ring walk: the entrance cinematic (EntranceFX shots)",
                     cell=(res[0] // 2, res[1] // 2))


def render_gifs(scene_dir, out_dir, samples):
    from PIL import Image
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    res = (420, 520)
    for g in idx.get("gifs", []):
        frames = []
        for i, fname in enumerate(g["frames"]):
            d = json.load(open(os.path.join(scene_dir, fname)))
            sc = game_scene(res, samples, keep_studio=True, bg=(0.07, 0.072, 0.08))
            focus = np.array(d["focus"])
            yaw = d.get("yaw", 0)
            look = np.array([-math.sin(yaw), 0, -math.cos(yaw)])
            right = np.array([math.cos(yaw), 0, -math.sin(yaw)])
            floor = focus[1] - 3.05
            P = np.array([(focus[0] - 14, floor, focus[2] - 14), (focus[0] + 14, floor, focus[2] - 14), (focus[0] + 14, floor, focus[2] + 14),
                          (focus[0] - 14, floor, focus[2] + 14)])
            sc.add_world(P, np.array([(0, 2, 1), (0, 3, 2)]), "floorq", mat=sc.gear_mat((0.16, 0.16, 0.18), "Fabric", 0), smooth=False)
            add_figures(sc, scene_dir, d["figures"])
            eye = focus + look * 17 + right * 5 + np.array([0, 1.6, 0])
            tgt = focus + np.array([0, 1.3, 0])
            bpy.context.view_layer.update()
            sc.rig(tuple(focus + np.array([0, 1.2, 0])), 2.6)
            area("key2", tuple(focus + look * 6 + right * 4 + np.array([0, 5, 0])), tuple(tgt), 700, (1, 0.95, 0.9), 4)
            area("rim2", tuple(focus - look * 5 + np.array([0, 6, 0])), tuple(tgt), 500, (0.9, 0.95, 1), 3)
            cd = sc.cam.data
            cd.lens_unit = "FOV"
            vf = math.radians(34)
            cd.angle = 2 * math.atan(math.tan(vf / 2) * res[0] / res[1])
            cd.clip_start = 0.2
            WR.look_at(sc.cam, tuple(eye), tuple(tgt))
            path = os.path.join(out_dir, "_%s_%03d.png" % (g["id"], i))
            sc.sc.render.image_settings.file_format = "PNG"
            sc.sc.render.filepath = os.path.abspath(path)
            bpy.ops.render.render(write_still=True)
            frames.append(path)
        ims = [Image.open(p).convert("RGB") for p in frames]
        if not ims:
            continue
        pal = [im.quantize(colors=200, method=Image.Quantize.MEDIANCUT) for im in ims]
        pal[0].save(os.path.join(out_dir, g["id"] + ".gif"), save_all=True, append_images=pal[1:], duration=83, loop=0)
        # a strip of every third frame
        pick = ims[::3]
        W = Image.new("RGB", (len(pick) * res[0] // 2, res[1] // 2), (20, 20, 22))
        for k, im in enumerate(pick):
            W.paste(im.resize((res[0] // 2, res[1] // 2)), (k * res[0] // 2, 0))
        W.save(os.path.join(out_dir, g["id"] + "_strip.jpg"), quality=88)
        for p in frames:
            os.remove(p)
        print("gif", g["id"], len(ims), flush=True)


def main():
    argv = sys.argv[1:]
    scene_dir, world_path, out_dir = argv[0], argv[1], argv[2]
    only, samples, res, shots = {"story", "gif"}, 48, (1280, 720), None
    i = 3
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            only = set(argv[i + 1].split(","))
            i += 1
        elif a == "--samples":
            samples = int(argv[i + 1])
            i += 1
        elif a == "--res":
            res = tuple(int(x) for x in argv[i + 1].split("x"))
            i += 1
        elif a == "--shots":
            shots = set(argv[i + 1].split(","))
            i += 1
        i += 1
    os.makedirs(out_dir, exist_ok=True)
    if "story" in only:
        world = json.load(open(world_path))
        render_story(scene_dir, world, out_dir, samples, res, shots)
    if "gif" in only:
        render_gifs(scene_dir, out_dir, max(8, samples // 3))


if __name__ == "__main__":
    main()
