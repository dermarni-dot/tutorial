"""Cycles previews of the v10 town (CityMap at real-world scale), on tools/sim/world_render.py's scene builder.

    /opt/bpyenv/bin/python tools/world/render_city_v10.py SCENE.json OUT_DIR [--only view,view] [--samples N]
                                                           [--res 1280x720] [--figure DIR/<id>.json]

SCENE.json is tools/sim/world_scene.luau's dump (--only city). Views: aerials of the whole map and downtown,
street-level shots of Main Street (day and night), Champion Ave, the gym forecourt, the park, the arena plaza,
Oak Street, the waterfront, the Elite / industrial quarter, and three SCALE shots that stand a real boxer
(tools/sim/v8_scene.luau's export, --figure) next to a parked car, a shop door and a street light.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "sim"))
sys.path.insert(0, os.path.join(ROOT, "tools", "hair"))
import world_render as WR  # noqa: E402
import v8_render as v8  # noqa: E402
import bpy  # noqa: E402

CITY = ["server_gym_and_city", "LocalCity", "WorldDetail_city"]

# (eye, target) in Roblox studs; fig = (x, z, yaw degrees) where the scale figure stands (facing -Z at yaw 0)
VIEWS = {
    "01_overview_aerial": {"eye": (-1250, 820, 1500), "target": (120, 0, -60), "fov": 48, "mode": "day"},
    "02_downtown_aerial": {"eye": (-420, 300, 820), "target": (40, 0, 260), "fov": 45, "mode": "day", "cull": ((0, 10, 250), 1100)},
    "03_main_street_day": {"eye": (-150, 7, 348), "target": (140, 10, 330), "fov": 55, "mode": "day", "cull": ((0, 10, 330), 900), "fig": (-132, 344, 70)},
    "04_main_street_night": {"eye": (-150, 7, 348), "target": (140, 10, 330), "fov": 55, "mode": "night", "cull": ((0, 10, 330), 700), "exposure": 1.0, "fig": (-132, 344, 70)},
    "05_champion_ave": {"eye": (-16, 7, 268), "target": (0, 14, 110), "fov": 55, "mode": "day", "cull": ((0, 10, 200), 800)},
    "06_gym_forecourt": {"eye": (-70, 10, 160), "target": (0, 14, 70), "fov": 55, "mode": "day", "cull": ((0, 10, 110), 600)},
    "07_scale_car": {"eye": (114, 5.5, 142), "target": (90, 3.5, 112), "fov": 50, "mode": "day", "cull": ((90, 5, 115), 400), "fig": (101, 124, 150)},
    "08_scale_door": {"eye": (-394, 6.5, 344), "target": (-410, 5, 357), "fov": 50, "mode": "day", "cull": ((-410, 5, 350), 400), "fig": (-405, 352.5, 160)},
    "09_scale_streetlight": {"eye": (-336, 6, 314), "target": (-350, 13, 298), "fov": 55, "mode": "day", "cull": ((-350, 10, 300), 500), "fig": (-345, 296, 160)},
    "10_park_fountain": {"eye": (400, 9, 120), "target": (480, 8, 40), "fov": 55, "mode": "day", "cull": ((480, 10, 40), 600)},
    "11_arena_plaza": {"eye": (-110, 14, -430), "target": (0, 32, -570), "fov": 55, "mode": "day", "cull": ((0, 20, -520), 700)},
    "12_oak_street": {"eye": (-448, 8, 90), "target": (-430, 12, -120), "fov": 55, "mode": "day", "cull": ((-440, 10, -20), 600)},
    "13_waterfront": {"eye": (836, 8, 170), "target": (920, 8, 40), "fov": 55, "mode": "day", "cull": ((900, 10, 60), 900)},
    "14_elite_industrial": {"eye": (330, 24, -300), "target": (560, 20, -460), "fov": 55, "mode": "day", "cull": ((480, 20, -430), 700)},
    "15_estates": {"eye": (-440, 10, -640), "target": (-440, 12, -840), "fov": 55, "mode": "day", "cull": ((-440, 10, -780), 600)},
    "16_plan_campus": {"eye": (0, 900, -60.01), "target": (0, 0, -60), "ortho": 1000, "mode": "day", "cull": ((0, 10, -60), 800)},
}


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def figure_material(name, col):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    lin = list(WR.srgb2lin(col)) + [1.0]
    bsdf.inputs["Base Color"].default_value = lin
    bsdf.inputs["Roughness"].default_value = 0.65
    return m


def add_mesh(P, T, name, col, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(WR.to_b(np.asarray(P, dtype=np.float64)).tolist(), [], [tuple(int(i) for i in t) for t in T])
    me.update()
    me.materials.append(figure_material(name, col))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for poly in me.polygons:
        poly.use_smooth = smooth
    return ob


def add_figure(d, at, yaw):
    """the exported boxer (tools/sim/v8_scene.luau: feet at y 0, facing -Z) standing at (x, z), turned by yaw"""
    R = rot_y(yaw)
    off = np.array([at[0], 0.0, at[1]])
    skin = d["head"]["color"]
    for m in d["meshes"]:
        P = np.asarray(m["p"]).reshape(-1, 3) @ R.T + off
        T = np.asarray(m["t"]).reshape(-1, 3) - 1
        add_mesh(P, T, m["name"], m["color"] if m.get("gear") else skin)
    hd = d["head"]
    P, T = v8.classic_head(hd["classic"], hd["size"])
    add_mesh(v8.place(P, hd["cf"], np.zeros(3)) @ R.T + off, T, "Head", hd["color"])
    for g in d["parts"]:
        sx, sy, sz = g["size"]
        sh = g["shape"]
        if sh == "Ball":
            P, T = v8.uv_sphere(min(sx, sy, sz) / 2, min(sx, sy, sz) / 2, min(sx, sy, sz) / 2)
        elif sh == "Cylinder":
            r = min(sy, sz) / 2
            P, T = v8.cylinder_x(sx, r, r)
        elif sh == "Ellipsoid":
            P, T = v8.uv_sphere(sx / 2, sy / 2, sz / 2)
        elif sh == "Wedge":
            P, T = v8.wedge(sx, sy, sz)
        elif sh == "Head":
            u = min(sx, sy, sz)
            P, T = v8.classic_head(d["head"]["classic"], (u, u, u))
        else:
            P, T = v8.box(sx, sy, sz)
        add_mesh(v8.place(P, g["cf"], np.zeros(3)) @ R.T + off, T, g["name"], g["color"], smooth=sh != "Block")


def render_view(scene, view, out, samples, res, tmpdir, figure):
    WR.reset()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 2
    sc.cycles.transparent_max_bounces = 8
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.image_settings.file_format = "JPEG"
    sc.render.image_settings.quality = 90
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.exposure = view.get("exposure", 0.0)
    mode = view.get("mode", "day")
    night = mode == "night"
    WR.setup_world(mode, view.get("sun", 3.5))
    B = WR.Builder(tmpdir)
    centre = np.array(view["cull"][0]) if view.get("cull") else None
    radius = view["cull"][1] if view.get("cull") else 0
    nparts = 0
    for rname in CITY:
        root = scene["roots"].get(rname)
        if not root:
            continue
        parts = root["parts"]
        keep = [WR.near(p, centre, radius, view.get("below")) for p in parts]
        for p, k in zip(parts, keep):
            if k:
                B.add_part(p, night)
                nparts += 1
        for g in root.get("guis", []):
            if keep[g["part"] - 1]:
                B.add_gui(g, parts[g["part"] - 1])
        for dc in root.get("decals", []):
            if keep[dc["part"] - 1]:
                B.add_decal(dc, parts[dc["part"] - 1])
        for L in root.get("lights", []):
            if keep[L["part"] - 1]:
                WR.add_light(L, parts[L["part"] - 1], night, view.get("light_k", 2.0))
    B.flush()
    if figure and view.get("fig"):
        fx, fz, yaw = view["fig"]
        add_figure(figure, (fx, fz), yaw)
    cd = bpy.data.cameras.new("cam")
    if view.get("ortho"):
        cd.type = "ORTHO"
        cd.ortho_scale = view["ortho"]
    cd.lens_unit = "FOV"
    vf = math.radians(view.get("fov", 60))
    cd.angle = 2 * math.atan(math.tan(vf / 2) * res[0] / res[1])
    cd.clip_start = 0.3
    cd.clip_end = 6000
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    WR.look_at(cam, view["eye"], view["target"])
    sc.render.filepath = out
    print("render", os.path.basename(out), "parts", nparts, "guis", B.gui_count, flush=True)
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[1:]
    scene_path, out_dir = argv[0], argv[1]
    only, samples, res, figure = None, 48, (1280, 720), None
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            only = argv[i + 1].split(",")
            i += 1
        elif a == "--samples":
            samples = int(argv[i + 1])
            i += 1
        elif a == "--res":
            res = tuple(int(x) for x in argv[i + 1].split("x"))
            i += 1
        elif a == "--figure":
            figure = json.load(open(argv[i + 1]))
            i += 1
        i += 1
    scene = json.load(open(scene_path))
    os.makedirs(out_dir, exist_ok=True)
    tmpdir = os.path.join(os.path.dirname(os.path.abspath(scene_path)), "gui_png")
    os.makedirs(tmpdir, exist_ok=True)
    for name, view in VIEWS.items():
        if only and name not in only:
            continue
        render_view(scene, view, os.path.join(out_dir, name + ".jpg"), samples, res, tmpdir, figure)


if __name__ == "__main__":
    main()
