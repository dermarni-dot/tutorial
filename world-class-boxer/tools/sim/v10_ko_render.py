"""Knockdown / knockout fall sheets at fixed times after the knockdown (v10: the rebuilt AnimDown).

    /opt/bpyenv/bin/python tools/sim/v10_ko_render.py SCENE_DIR OUT_DIR [--only id,id] [--times 0,0.2,0.5,1,2]
                                                     [--views side,high,34] [--samples N] [--tag v10]

Per fight scenario of tools/sim/v9_anim.luau (--clips fight): the recorded frame nearest to each time after the
knockdown (the frame Guard went "down": `kdAt` in the clip's JSON, else the scenario's punch contact), one sheet per
view: <OUT>/<tag>_<id>_<view>.jpg. "high" is a raised side view (a body lying on the canvas reads against the floor
marks). Also prints and writes <OUT>/<tag>_<id>_ground.json: per picked frame the lowest vertex of the body meshes
against the floor (Y = 0: negative = sunk, positive = floating), the pelvis and head centre heights, and the pelvis'
horizontal travel per recorded frame after the last picked time (the slide once he is down).
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hair"))
import v9_render as v9  # noqa: E402
import render  # noqa: E402

# the knockdown time of the v9_anim scenarios without kdAt in their JSON (older harness): 0.3 + the punch's windup
WIND = {"jab": 0.16, "cross": 0.24, "leadhook": 0.26, "rearhook": 0.3, "uppercut": 0.3, "overhand": 0.42}
KIND = {
    "kd_back": "cross", "kd_sit": "jab", "kd_side": "leadhook", "kd_face": "overhand", "kd_knee": "leadhook",
    "ko_oneshot_back": "cross", "ko_oneshot_face": "rearhook", "ko_crumple_side": "leadhook", "ko_crumple_back": "uppercut",
    "ko_delayed_face": "overhand", "ko_body": "leadhook", "ko_uppercut": "uppercut", "ko_hook_face": "leadhook",
    "ko_standing": "rearhook",
}

v9.FIGHT_VIEWS["high"] = dict(view=(90, 28, 1.0), dist=30, ortho=9.6, focus=(0, 2.2, 0.0))
v9.FIGHT_VIEWS["front"] = dict(view=(0, 6, 1.0), dist=30, ortho=9.0, focus=(0, 3.0, 0.0))

BODY_PARTS = {"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
              "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"}


def ko_scene(scene_dir, fr, samples, view, res):
    """v9_render.fight_scene with the whole scene shifted so the fallen man's pelvis sits under the camera's focus
    (he goes a body length away from his root as he falls: the fixed framing lost him)"""
    _, _, pelvis, _ = mesh_stats(fr)
    root = fr.get("root") or [0, 0, 0]
    cx, cz = (float(pelvis[0]), float(pelvis[2])) if pelvis is not None else (root[0], root[2])
    off = (-cx, 0, -cz)
    vw = v9.FIGHT_VIEWS[view]
    sc = v9.v8.V8Scene(res=res, samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
    v9.v8.add_boxer(sc, scene_dir, v9.frame_dict(fr), offset=off)
    if fr.get("opp"):
        v9.v8.add_boxer(sc, scene_dir, v9.frame_dict(fr["opp"]), offset=off)
    if fr.get("ref"):
        v9.v8.add_boxer(sc, scene_dir, v9.frame_dict(fr["ref"]), offset=off)
    for k in range(-6, 7):
        P, T = v9.v8.box(0.03, 0.012, 12.0)
        sc.add_world(P + np.array([k - (cx - round(cx)), 0.006, 0]), T, "markx", mat=sc.gear_mat((0.42, 0.42, 0.45), "SmoothPlastic", 0), smooth=False)
        P, T = v9.v8.box(12.0, 0.012, 0.03)
        sc.add_world(P + np.array([0, 0.006, k - (cz - round(cz))]), T, "markz", mat=sc.gear_mat((0.42, 0.42, 0.45), "SmoothPlastic", 0), smooth=False)
    if os.environ.get("V9_FAST", "1") == "1":
        sc.sc.cycles.max_bounces = 3
        sc.sc.cycles.transparent_max_bounces = 8
    cam = sc.cam
    if vw["ortho"]:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = vw["ortho"]
    sc.rig(vw["focus"], 5.0)
    return sc, vw


def mesh_stats(fr):
    """lowest vertex (name, y) over the body meshes, the pelvis and head centres"""
    low, lowName = 99.0, None
    pelvis, head = None, None
    for m in fr.get("meshes", []):
        if m.get("gear"):
            continue
        P = np.asarray(m["p"], dtype=float).reshape(-1, 3)
        if P.size == 0:
            continue
        y = float(P[:, 1].min())
        if y < low:
            low, lowName = y, m["name"]
        if m["name"] == "LowerTorso":
            pelvis = P.mean(axis=0)
        elif m["name"] == "Head":
            head = P.mean(axis=0)
    if head is None and fr.get("head"):
        head = np.asarray(fr["head"]["cf"][:3], dtype=float)
        low = min(low, float(head[1]) - fr["head"]["size"][1] * 0.5)
    return low, lowName, pelvis, head


def pick_frames(frames, t0, times):
    out = []
    for dt in times:
        want = t0 + dt
        i = min(range(len(frames)), key=lambda k: abs(frames[k].get("t", 0) - want))
        out.append((dt, i))
    return out


def render_scenario(scene_dir, out_dir, clip, times, views, samples, tag):
    data = json.load(open(os.path.join(scene_dir, clip["file"])))
    frames = data["frames"]
    sid = data.get("id")
    t0 = data.get("kdAt")
    if t0 is None:
        t0 = 0.3 + WIND.get(KIND.get(sid, "cross"), 0.24)
    picks = pick_frames(frames, t0, times)
    # ground report
    rep = {"id": sid, "kdAt": t0, "frames": []}
    for dt, i in picks:
        fr = frames[i]
        low, lowName, pelvis, head = mesh_stats(fr)
        rep["frames"].append({"dt": dt, "t": fr.get("t"), "lowest": round(low, 3), "lowestPart": lowName,
                              "pelvisY": None if pelvis is None else round(float(pelvis[1]), 3),
                              "headY": None if head is None else round(float(head[1]), 3)})
    # the slide once down: pelvis travel per recorded frame from the last picked time to the end of the clip
    lastI = picks[-1][1]
    travel, maxStep = 0.0, 0.0
    prev = None
    for fr in frames[lastI:]:
        _, _, pelvis, _ = mesh_stats(fr)
        if pelvis is None:
            continue
        if prev is not None:
            d = float(np.hypot(pelvis[0] - prev[0], pelvis[2] - prev[2]))
            travel += d
            maxStep = max(maxStep, d)
        prev = pelvis
    rep["slideAfter"] = round(travel, 3)
    rep["slideMaxStep"] = round(maxStep, 3)
    line = " ".join("%+.2fs low %+.3f(%s) pelvis %.2f head %.2f" % (f["dt"], f["lowest"], f["lowestPart"], f["pelvisY"] or 0, f["headY"] or 0)
                    for f in rep["frames"])
    print("ground %-18s kd@%.2f | %s | slide after %.3f (max step %.3f)" % (sid, t0, line, travel, maxStep), flush=True)
    json.dump(rep, open(os.path.join(out_dir, f"{tag}_{sid}_ground.json"), "w"), indent=1)
    outs = []
    for view in views:
        paths, labels = [], []
        for dt, i in picks:
            fr = frames[i]
            sc, vw = ko_scene(scene_dir, fr, samples, view, (420, 360))
            p = os.path.join(out_dir, f"_{tag}_{sid}_{view}_{i}.png")
            sc.render(p, view=vw["view"], dist=vw["dist"], focus=vw["focus"])
            paths.append(p)
            labels.append("+%.1f s (%.2f)" % (dt, fr.get("t", 0)))
        out = os.path.join(out_dir, f"{tag}_{sid}_{view}.jpg")
        render.sheet(paths, out, cols=len(paths), labels=labels, title=f"{tag}: {sid} ({view}) from the knockdown", cell=(300, 257))
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
    only = set(opts["--only"].split(",")) if "--only" in opts else None
    samples = int(opts.get("--samples", 16))
    views = opts.get("--views", "side,high").split(",")
    times = [float(x) for x in opts.get("--times", "0,0.2,0.5,1,2").split(",")]
    tag = opts.get("--tag", "v10")
    index = json.load(open(os.path.join(scene_dir, "index.json")))
    for c in index["clips"]:
        if c["clip"] != "fight":
            continue
        sid = c["id"].rsplit("_t", 1)[0]
        if sid.startswith("fight_"):
            sid = sid[6:]
        if only and sid not in only and c["id"] not in only:
            continue
        render_scenario(scene_dir, out_dir, c, times, views, samples, tag)
