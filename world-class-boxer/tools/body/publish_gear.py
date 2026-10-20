"""Uploads the boxing gear meshes (build_gear.py) to Roblox with Open Cloud and writes the game's manifest
src/shared/GearAssetData.lua.

    python3 tools/body/publish_gear.py --dry-run          # list what would go up, write nothing
    python3 tools/body/publish_gear.py                    # upload what changed, check moderation, write manifest
    python3 tools/body/publish_gear.py --check            # also re-query the moderation state of every id
    python3 tools/body/publish_gear.py --local [OUT.lua]  # offline: fake ids, nothing uploaded

* Input: tools/body/out/gear/gear.json + the .mesh files it names (tier<N>/ and shared/).
* Creator: ROBLOX_CREATOR_ID / ROBLOX_CREATOR_TYPE (group | user). API key: injected by the proxy for
  apis.roblox.com (or ROBLOX_API_KEY when set).
* Meshes go up as assetType "Mesh" (model/x-file-mesh-data) through publish_body.py's helpers (tools/hair/publish.py's
  upload / cache / manifest code) and the same hash cache, tools/body/uploaded.json (SHA-256 of the file -> id,
  moderation state): a re-run uploads only what changed, a mesh shared by every tier goes up once.
* --local [PATH] uploads nothing and leaves the cache and src/ alone: it writes the manifest to PATH (default
  /tmp/claude-0/GearAssetData_local.lua) with FAKE ids and a PATH.ids.json sidecar mapping each id to its file.

GearAssetData.lua:
    return {
        version = 1,
        slots = { "trunks", "trim", ... },              -- colour slots (BuilderGear maps each to a look colour)
        sets = { trunks = { Classic = { "Waistband", "TrunkSeat", "TrunkLeg" }, ... }, shoes = {...}, ... },
                                                        -- piece names; a sided piece stands for _L and _R
        pieces = { Glove_R = { part = "RightHand", slot = "gloves", group = "gloves" }, ... },
        tiers = {                                       -- [n] = the pieces for a body part of tier n
            { Glove_R = { mesh = id, offset = { x, y, z }, size = { x, y, z }, nt = tris }, ... },
            ...
        },
    }
offset = the piece's centre in its body part's space (rest pose, unscaled studs: the game welds it at
part.CFrame * CFrame.new(offset * ratio), ratio = the part's Size / OriginalSize), size = the mesh bbox = the
MeshPart's unscaled Size. An id of 0 = not uploaded: the game keeps the part-built gear.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import publish_body as pb  # noqa: E402  (hp = tools/hair/publish.py pointed at tools/body, moderation, check_all)

hp = pb.hp
GEAR = os.path.join(HERE, "out", "gear")
MANIFEST = os.path.join(ROOT, "src", "shared", "GearAssetData.lua")
LOCAL_DEFAULT = "/tmp/claude-0/GearAssetData_local.lua"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--check", action="store_true", help="re-query the moderation state of every id used")
    ap.add_argument("--wait", type=int, default=180, help="seconds to wait for assets still under review")
    ap.add_argument("--local", nargs="?", const=LOCAL_DEFAULT, default=None, metavar="OUT.lua")
    args = ap.parse_args()
    local = hp.LocalIds() if args.local else None
    cache = {} if local else hp.load_cache()
    dry = args.dry_run
    uploaded_before = set(v["id"] for v in cache.values())

    with open(os.path.join(GEAR, "gear.json")) as f:
        gj = json.load(f)
    ids = {}  # file -> id (a shared mesh is listed by every tier)
    lite_gj = None
    lite_path = os.path.join(pb.LITE, "gear", "gear.json")
    if os.path.exists(lite_path):
        with open(lite_path) as f:
            lite_gj = json.load(f)
    tiers = []
    for n in sorted(gj["tiers"], key=int):
        rec = {}
        for key, e in sorted(gj["tiers"][n].items()):
            path = os.path.join(GEAR, e["file"])
            if e["file"] not in ids:
                shared = e["file"].startswith("shared/")
                label = key if shared else f"T{n} {key}"
                ids[e["file"]] = hp.ensure(cache, path, "Mesh", f"WCB Gear {label}",
                                           "Become a World Class Boxer: boxing gear piece %s (%s)"
                                           % (key, "every tier" if shared else "muscle tier %s" % n),
                                           "model/x-file-mesh-data", dry, local)
            rec[key] = {"mesh": ids[e["file"]], "offset": e["offset"], "size": e["size"], "nt": e["nt"]}
            # the lite detail set (the v9 piece fitted to the v9 body: tools/body/out/lite/gear; cached ids)
            le = lite_gj and lite_gj["tiers"].get(n, {}).get(key)
            if le:
                lf = "lite/" + le["file"]
                if lf not in ids:
                    shared = le["file"].startswith("shared/")
                    label = key if shared else f"T{n} {key}"
                    ids[lf] = hp.ensure(cache, os.path.join(pb.LITE, "gear", le["file"]), "Mesh",
                                        f"WCB Gear {label} lite", "Become a World Class Boxer: boxing gear piece %s "
                                        "(%s), the light detail set" % (key, "every tier" if shared else "muscle tier %s" % n),
                                        "model/x-file-mesh-data", dry, local)
                rec[key]["lite"] = {"mesh": ids[lf], "offset": le["offset"], "size": le["size"], "nt": le["nt"]}
        tiers.append(rec)
    used = list(ids.values())
    if dry:
        print("dry run: %d gear meshes referenced, nothing uploaded, manifest not written" % len(used))
        return
    if not local:
        new = [i for i in used if i and i not in uploaded_before]
        check = used if args.check else new
        if check:
            counts = pb.check_all(cache, check, args.wait)
            print("moderation (%s ids): %s" % ("all" if args.check else "new", counts))
        states = {}
        for i in used:
            for v in cache.values():
                if v["id"] == i:
                    states[v.get("moderation")] = states.get(v.get("moderation"), 0) + 1
                    break
        print("gear meshes:", len(used), "moderation:", states)

    data = {
        "version": 1,
        "slots": gj["slots"],
        "sets": gj["sets"],
        "pieces": {k: dict({"part": v["part"], "slot": v["slot"], "group": v["group"]},
                           **({"tierOf": v["tierOf"]} if v.get("tierOf") else {})) for k, v in gj["pieces"].items()},
        "tiers": tiers,
    }
    head = ("-- GENERATED by tools/body/publish_gear.py from tools/body/out/gear (build_gear.py) and the upload cache\n"
            "-- tools/body/uploaded.json. Do not edit by hand: rebuild and re-run publish_gear.py.\n"
            "-- The boxing gear (Mesh assets) fitted to the muscle-tier body: tiers[n][piece] = the piece for a body part\n"
            "-- of tier n (mesh id, offset = its centre in the body part's space, rest pose, unscaled; size = the mesh\n"
            "-- bbox = the MeshPart's unscaled Size; nt = tris). pieces[piece] = the body part it welds to, its colour\n"
            "-- slot and group; sets = the pieces each style wears (a sided name stands for _L and _R). An id of 0 =\n"
            "-- not uploaded: BuilderGear falls back to the part-built gear. tiers[n][piece].lite = the piece of the lite\n"
            "-- detail set (Config.Detail.meshes \"lite\": the v9 mesh, worn on the lite body parts).\n")
    if local:
        head = ("-- LOCAL manifest from tools/body/publish_gear.py --local: FAKE asset ids (nothing uploaded), for\n"
                "-- offline simulation only. Each id's file is in the .ids.json sidecar next to this file.\n")
    out = os.path.abspath(args.local) if local else MANIFEST
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        f.write(head + "return " + hp.lua(data) + "\n")
    if local:
        side = os.path.splitext(out)[0] + ".ids.json"
        with open(side, "w") as f:
            json.dump({"ids": local.files, "manifest": out}, f, indent=1, sort_keys=True)
        print("wrote", out, "(fake ids);", side, len(local.files), "files")
    else:
        zero = sum(1 for i in used if not i)
        print("wrote", os.path.relpath(MANIFEST, ROOT), "%d tiers, %d meshes, %d ids missing" % (len(tiers), len(used), zero))


if __name__ == "__main__":
    sys.exit(main())
