"""Uploads the muscle-tier body meshes and the classic faces to Roblox with Open Cloud and writes the game's
manifest src/shared/BodyAssetData.lua (format: tools/body/CONTRACT.md).

    python3 tools/body/publish_body.py --dry-run          # list what would go up, write nothing
    python3 tools/body/publish_body.py                    # upload what changed, check moderation, write manifest
    python3 tools/body/publish_body.py --check            # also re-query the moderation state of every id
    python3 tools/body/publish_body.py --local [OUT.lua]  # offline: fake ids, nothing uploaded

* Inputs: tools/body/out/tier<N>/parts.json + <Part>.mesh (build_body.py: the Athletic frame, the default family),
  tools/body/out/frames/<key>/tier<N>/ (the other frames' families -> manifest `frames[<frame id>]`),
  tools/body/out/body_tiers.json (the unit rig), tools/body/out/faces/faces.json + face_<key>.png (faces.py).
* Creator: ROBLOX_CREATOR_ID / ROBLOX_CREATOR_TYPE (group | user). API key: injected by the proxy for
  apis.roblox.com (or ROBLOX_API_KEY when set).
* Meshes go up as assetType "Mesh" (model/x-file-mesh-data), faces as "Image" (image/png). The upload / cache /
  manifest helpers are tools/hair/publish.py's; the cache is a separate file, tools/body/uploaded.json (SHA-256 of
  the file -> id, moderation state), so a re-run uploads only what changed and ids stay stable.
* --local [PATH] uploads nothing and leaves the cache and src/ alone: it writes the manifest to PATH (default
  /tmp/claude-0/BodyAssetData_local.lua) with FAKE ids and a PATH.ids.json sidecar mapping each id to its file.
"""
import argparse
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "hair"))
import publish as hp  # noqa: E402  (upload, ensure, LocalIds, lua, cache helpers)

OUT = os.path.join(HERE, "out")
LITE = os.path.join(OUT, "lite")  # the lite detail set (the v9 meshes): lite/tier<N>/, lite/gear/
CACHE = os.path.join(HERE, "uploaded.json")
MANIFEST = os.path.join(ROOT, "src", "shared", "BodyAssetData.lua")
LOCAL_DEFAULT = "/tmp/claude-0/BodyAssetData_local.lua"
PARTS = ["UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
         "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]

# hair's helpers write their module's CACHE and print paths relative to their HERE: point both at tools/body
hp.CACHE = CACHE
hp.HERE = HERE


def moderation(aid):
    """(moderationState, state) of an asset, from GET assets/v1/assets/<id>"""
    r = hp._request("GET", f"{hp.API}/assets/{aid}?readMask=moderationResult,state")
    return (r.get("moderationResult") or {}).get("moderationState"), r.get("state")


def check_all(cache, ids, wait=0):
    """re-query moderation for the given ids (waiting up to `wait` s while any is still Reviewing); updates the
    cache and returns {state: count}"""
    by_id = {v["id"]: k for k, v in cache.items()}
    t0 = time.time()
    while True:
        counts, pending = {}, 0
        for aid in sorted(set(ids)):
            if not aid:
                continue
            try:
                ms, st = moderation(aid)
            except RuntimeError as e:
                ms, st = "error", str(e)[:80]
            counts[ms] = counts.get(ms, 0) + 1
            pending += ms in ("Reviewing", None)
            h = by_id.get(aid)
            if h:
                cache[h]["moderation"] = ms
                cache[h]["state"] = st
        hp.save_cache(cache)
        if not pending or time.time() - t0 > wait:
            return counts
        time.sleep(10)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--check", action="store_true", help="re-query the moderation state of every id used")
    ap.add_argument("--wait", type=int, default=120, help="seconds to wait for assets still under review")
    ap.add_argument("--local", nargs="?", const=LOCAL_DEFAULT, default=None, metavar="OUT.lua")
    args = ap.parse_args()
    local = hp.LocalIds() if args.local else None
    cache = {} if local else hp.load_cache()
    dry = args.dry_run
    uploaded_before = set(v["id"] for v in cache.values())

    with open(os.path.join(OUT, "body_tiers.json")) as f:
        bt = json.load(f)
    unit = bt["unit"]
    tiers = []
    used = []

    def tier_dirs(root):
        return sorted(glob.glob(os.path.join(root, "tier*", "parts.json")),
                      key=lambda p: int(os.path.basename(os.path.dirname(p))[4:]))

    def upload_parts(td, d, tag, label):
        parts = {}
        n = td["tier"]
        for name in PARTS:
            rec = td["parts"][name]
            mid = hp.ensure(cache, os.path.join(d, rec["mesh_file"]), "Mesh", f"WCB Body {tag}T{n} {name}",
                            f"Become a World Class Boxer: {label}muscle tier {n} ({td['name']}) R15 body part {name}",
                            "model/x-file-mesh-data", dry, local)
            used.append(mid)
            parts[name] = {"mesh": mid, "size": rec["size"], "attachments": rec["attachments"], "nt": rec["nt"]}
        return parts

    for pj in tier_dirs(OUT):
        with open(pj) as f:
            td = json.load(f)
        n = td["tier"]
        d = os.path.dirname(pj)
        parts = upload_parts(td, d, "", "")
        # the lite detail set (Config.Detail.meshes "lite": the v9 meshes, kept in tools/body/out/lite/tier<N>): their
        # hashes are in the cache, so they keep their ids and nothing is uploaded again
        lite_tris = None
        lpj = os.path.join(LITE, "tier%d" % n, "parts.json")
        if os.path.exists(lpj):
            with open(lpj) as f:
                ld = json.load(f)
            lite_tris = ld["tris"]
            for name in PARTS:
                rec = ld["parts"][name]
                lid = hp.ensure(cache, os.path.join(os.path.dirname(lpj), rec["mesh_file"]), "Mesh",
                                f"WCB Body T{n} {name} lite",
                                f"Become a World Class Boxer: muscle tier {n} ({ld['name']}) R15 body part {name}, "
                                "the light detail set", "model/x-file-mesh-data", dry, local)
                used.append(lid)
                parts[name]["lite"] = {"mesh": lid, "size": rec["size"], "attachments": rec["attachments"],
                                       "nt": rec["nt"]}
        tiers.append({"tier": n, "name": td["name"], "tris": td["tris"], "liteTris": lite_tris, "fit": td["fit"],
                      "parts": parts})
    if [t["tier"] for t in tiers] != [1, 2, 3, 4, 5]:
        raise SystemExit("expected tiers 1-5 in tools/body/out, got %s" % [t["tier"] for t in tiers])
    # the other frames' families: out/frames/<key>/tier<N> (build_body.FRAMES; the frame id is in parts.json)
    frames = {}
    for fdir in sorted(glob.glob(os.path.join(OUT, "frames", "*"))):
        key = os.path.basename(fdir)
        ftiers, fid = [], None
        for pj in tier_dirs(fdir):
            with open(pj) as f:
                td = json.load(f)
            fid = td.get("frame") or fid
            n = td["tier"]
            parts = upload_parts(td, os.path.dirname(pj), f"{key} ", f"{fid} frame, ")
            ftiers.append({"tier": n, "name": td["name"], "tris": td["tris"], "fit": td["fit"], "parts": parts,
                           "armAxisX": td.get("armAxisX"), "gearScale": td.get("gearScale"), "unit": td.get("unit")})
        if [t["tier"] for t in ftiers] != [1, 2, 3, 4, 5]:
            raise SystemExit("frame %s: expected tiers 1-5 in %s, got %s" % (key, fdir, [t["tier"] for t in ftiers]))
        t3 = next((t for t in ftiers if t["tier"] == 3), ftiers[0])
        frames[fid] = {"key": key, "tiers": ftiers, "gearScale": t3["gearScale"], "unit": t3["unit"]}

    with open(os.path.join(OUT, "faces", "faces.json")) as f:
        fj = json.load(f)
    faces = []
    for e in fj["faces"]:
        fid = hp.ensure(cache, os.path.join(OUT, "faces", e["file"]), "Image", f"WCB Face {e['name']}",
                        f"Become a World Class Boxer: classic-style face '{e['key']}' (decal, transparent)",
                        "image/png", dry, local)
        used.append(fid)
        faces.append({"key": e["key"], "name": e["name"], "id": fid, "creator": e["creator"]})

    if dry:
        print("dry run: %d meshes / %d faces referenced, nothing uploaded, manifest not written"
              % (len(used) - len(faces), len(faces)))
        return
    if not local:
        new = [i for i in used if i and i not in uploaded_before]
        ids = used if args.check else new
        if ids:
            counts = check_all(cache, ids, args.wait)
            print("moderation (%s ids): %s" % ("all" if args.check else "new", counts))
        states = {}
        for v in cache.values():
            states[v.get("moderation")] = states.get(v.get("moderation"), 0) + 1
        print("cache:", len(cache), "assets", states)

    data = {
        "version": 1,
        "unit": unit,
        "tiers": [dict({"name": t["name"], "tris": t["tris"], "fit": t["fit"], "parts": t["parts"]},
                       **({"liteTris": t["liteTris"]} if t["liteTris"] else {})) for t in tiers],
        "frames": {fid: {"key": fr["key"], "gearScale": fr["gearScale"], "unit": fr["unit"],
                         "tiers": [{"name": t["name"], "tris": t["tris"], "fit": t["fit"], "parts": t["parts"],
                                    "armAxisX": t["armAxisX"]} for t in fr["tiers"]]}
                   for fid, fr in frames.items()},
        "defaultFrame": "Athletic",
        "faces": faces,
        "defaultFace": fj.get("default", "smile"),
        "expressions": fj["expressions"],
    }
    head = ("-- GENERATED by tools/body/publish_body.py from tools/body/out (build_body.py, faces.py) and the upload\n"
            "-- cache tools/body/uploaded.json. Do not edit by hand: rebuild and re-run publish_body.py.\n"
            "-- Muscle-tier R15 body parts (Mesh assets, tiers[1..5].parts[<Part>]: mesh id, size = the mesh bbox =\n"
            "-- the MeshPart's unscaled Size / OriginalSize, part-space attachment positions) and classic-style\n"
            "-- faces (Image assets, a Decal on the head's front). unit = the unscaled rig the meshes are modelled\n"
            "-- for: apply the HumanoidDescription with BodyTypeScale 0 / ProportionScale 0 and only Height / Width /\n"
            "-- Depth / Head scales (Width = Depth = Height = 1 reproduce unit). An id of 0 = not uploaded: keep the\n"
            "-- default part / face. expressions: mood -> face key; a nil entry = the boxer's own chosen face.\n"
            "-- tiers[n].fit: gear-fit girths / widths (studs, unscaled, convex hull) at fixed heights (rest space).\n"
            "-- parts[<Part>].lite: the same part in the lite detail set (Config.Detail.meshes = \"lite\": the v9 mesh,\n"
            "-- its own size and attachments; liteTris = that set's triangles per body).\n"
            "-- frames[<Config.BodyTypes id>] = { key, tiers = { [1..5] = { parts, fit, tris, armAxisX } }, gearScale, unit }: that\n"
            "-- frame's own mesh family (v12; the Athletic frame is `tiers`, the default family, with the lite set and the gear\n"
            "-- fit); gearScale[<part base>] = the factors its parts are the default family's scaled by (BuilderGear scales the\n"
            "-- gear by them), unit = its rig heights (joints, hipHeight, shoulderHeight, neckHeight, the frame's head and\n"
            "-- standingHeight = neckHeight + head: Builder.Scales normalises the HeightScale from them, v13).\n")
    if local:
        head = ("-- LOCAL manifest from tools/body/publish_body.py --local: FAKE asset ids (nothing uploaded), for\n"
                "-- offline simulation only. Each id's file is in the .ids.json sidecar next to this file.\n")
    body = "return " + hp.lua(data) + "\n"
    # keep the documented nil entries visible (hp.lua sorts keys and writes None as nil)
    out = os.path.abspath(args.local) if local else MANIFEST
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        f.write(head + body)
    if local:
        side = os.path.splitext(out)[0] + ".ids.json"
        with open(side, "w") as f:
            json.dump({"ids": local.files, "manifest": out}, f, indent=1, sort_keys=True)
        print("wrote", out, "(fake ids);", side, len(local.files), "files")
    else:
        zero = sum(1 for i in used if not i)
        print("wrote", os.path.relpath(MANIFEST, ROOT), "%d tiers, %d frames, %d faces, %d ids missing"
              % (len(tiers), len(frames), len(faces), zero))


if __name__ == "__main__":
    sys.exit(main())
