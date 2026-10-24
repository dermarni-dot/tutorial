"""Uploads the world's detail textures (tools/world/out, from build_textures.py) to Roblox as Image assets with
Open Cloud, checks their moderation and writes src/shared/WorldAssetData.lua.

    python3 tools/world/publish_world.py            # upload what changed, check moderation, write the manifest
    python3 tools/world/publish_world.py --check    # only re-read the moderation state of every cached upload
    python3 tools/world/publish_world.py --zero     # write the manifest with every id 0 (the game skips them)

Creator / key as tools/ui/publish_icons.py (ROBLOX_CREATOR_ID / ROBLOX_CREATOR_TYPE; the proxy injects the key).
Every upload is cached by the PNG's SHA-256 in tools/world/uploaded.json, so a re-run uploads only what changed.
An image whose moderation is not Approved is written with id 0: the game draws the part-built fallback instead.
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "hair"))
import publish as hair  # noqa: E402  (the shared Open Cloud upload code: _request, upload, sha)

OUT = os.path.join(HERE, "out")
CACHE = os.path.join(HERE, "uploaded.json")
MANIFEST = os.path.join(ROOT, "src", "shared", "WorldAssetData.lua")
API = "https://apis.roblox.com/assets/v1"

# key -> (file, display name, description)
IMAGES = [
    ("rubberTiles", "rubber_tiles.png", "WCB Gym Rubber Tiles", "Tileable rubber gym floor tiles (tinted in game)."),
    ("sidewalk", "sidewalk.png", "WCB Sidewalk Slabs", "Tileable concrete sidewalk slabs (tinted in game)."),
    ("canvasWeave", "canvas_weave.png", "WCB Ring Canvas", "Tileable boxing ring canvas weave (tinted in game)."),
    ("scuffs", "scuffs.png", "WCB Floor Scuffs", "Shoe scuffs and rubber marks decal for gym floors."),
    ("grime", "grime.png", "WCB Wall Grime", "Water stains running down a wall (decal)."),
    ("cracks", "cracks.png", "WCB Pavement Cracks", "Sidewalk cracks and an oil stain (decal)."),
    ("manhole", "manhole.png", "WCB Manhole Cover", "A cast iron manhole cover for the city streets."),
    ("posterFightNight", "poster_fightnight.png", "WCB Poster Fight Night", "World Class Boxer fight night poster."),
    ("posterUndisputed", "poster_undisputed.png", "WCB Poster Undisputed", "World Class Boxer poster: the road to undisputed."),
    ("posterRules", "poster_rules.png", "WCB Poster Gym Rules", "World Class Boxer gym rules poster."),
    ("posterChampion", "poster_champion.png", "WCB Poster Champion", "World Class Boxer world champion poster."),
    ("bannerWCB", "banner_wcb.png", "WCB Hanging Banner", "World Class Boxer hanging gym banner."),
    ("posterWall", "poster_wall.png", "WCB Gym Poster Wall", "A strip of old fight bills for the gym wall (made-up bouts)."),
    ("clippings", "clippings.png", "WCB Gym Clippings Board", "A cork board of newspaper clippings for the gym (made-up headlines)."),
    ("hallChampions", "hall_champions.png", "WCB Hall of Champions", "The gym's Hall of Champions photo wall (made-up names)."),
    ("blockWall", "block_wall.png", "WCB Painted Block Wall", "Tileable painted concrete block wall (tinted in game)."),
    ("whiteboard", "whiteboard.png", "WCB Gym Whiteboard", "A whiteboard with a hand-drawn weekly training schedule."),
    ("tvFight", "tv_fight.png", "WCB Gym TV Fight", "Four frames of a fight broadcast for the gym TVs."),
    ("stencilOutwork", "stencil_outwork.png", "WCB Stencil Outwork", "Spray stencil gym slogan: outwork everyone."),
    ("stencilShortcuts", "stencil_shortcuts.png", "WCB Stencil Shortcuts", "Spray stencil gym slogan: no shortcuts."),
    ("stencilNoDays", "stencil_nodays.png", "WCB Stencil No Days Off", "Spray stencil gym slogan: no days off."),
    ("paintChips", "paint_chips.png", "WCB Paint Chips", "Chipped paint flakes (wall decal)."),
    ("puddle", "puddle.png", "WCB Floor Puddle", "A water puddle on the gym floor (decal)."),
    ("floorWear", "floor_wear.png", "WCB Floor Wear", "Worn floor path where feet keep landing (decal)."),
    ("backdropWCB", "backdrop_wcb.png", "WCB Weigh-In Backdrop", "Tileable step-and-repeat backdrop with the WCB emblem."),
]


def load_cache():
    if os.path.exists(CACHE):
        with open(CACHE) as fh:
            return json.load(fh)
    return {}


def save_cache(c):
    with open(CACHE, "w") as fh:
        json.dump(c, fh, indent=1, sort_keys=True)


def moderation(asset_id):
    r = hair._request("GET", f"{API}/assets/{asset_id}?readMask=moderationResult,state")
    return (r.get("moderationResult") or {}).get("moderationState", "?"), r.get("state", "?")


def ensure(cache, path, name, desc):
    h = hair.sha(path)
    e = cache.get(h)
    if e and e.get("id"):
        return e
    aid, state = hair.upload(path, "Image", name, desc, "image/png")
    e = {"id": aid, "file": os.path.relpath(path, ROOT), "moderation": state, "uploaded": time.strftime("%Y-%m-%d %H:%M:%S")}
    cache[h] = e
    save_cache(cache)
    print(f"uploaded {os.path.basename(path)} -> {aid} ({state})")
    return e


def lua_manifest(rows):
    L = [
        "-- WorldAssetData: the world's detail textures as uploaded Image assets. GENERATED by",
        "-- tools/world/publish_world.py from tools/world/out (tools/world/build_textures.py) - do not edit by hand.",
        "-- images[key] = asset id (0 = not uploaded / not approved: the detail layer leaves that texture out).",
        "-- Tileable surfaces (rubberTiles, canvasWeave, blockWall) are mid-grey / white: tint them with Texture.Color3.",
        "-- Decals (scuffs, grime, cracks) are dark on transparent. Posters are 2 : 3, the banner 1 : 3.",
        "-- posterWall 4 : 1, clippings / hallChampions / whiteboard 2 : 1, stencils 8 : 1 (white: tint them), tvFight 2 x 2 frames.",
        "local WorldAssetData = {}",
        "WorldAssetData.images = {",
    ]
    for key, aid, st in rows:
        L.append(f"\t{key} = {aid}, -- {st}")
    L.append("}")
    L.append("function WorldAssetData.Id(key)")
    L.append("\tlocal id = WorldAssetData.images[key]")
    L.append('\treturn (type(id) == "number" and id > 0) and ("rbxassetid://" .. id) or nil')
    L.append("end")
    L.append("return WorldAssetData")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--zero", action="store_true")
    a = ap.parse_args()
    cache = load_cache()
    if a.check:
        for h, e in cache.items():
            st, state = moderation(e["id"])
            e["moderation"] = st
            print(f"{e['file']}: {e['id']}  moderation {st}  state {state}")
        save_cache(cache)
    rows = []
    if a.zero:
        rows = [(k, 0, "zero") for k, *_ in IMAGES]
    else:
        entries = []
        for key, fname, name, desc in IMAGES:
            entries.append((key, os.path.join(OUT, fname), ensure(cache, os.path.join(OUT, fname), name, desc)))
        states = {}
        for _ in range(20):
            pending = False
            for key, path, e in entries:
                st, _s = moderation(e["id"])
                e["moderation"] = st
                states[key] = st
                pending = pending or st not in ("Approved", "Rejected")
            save_cache(cache)
            if not pending:
                break
            time.sleep(8)
        for key, path, e in entries:
            st = states.get(key, "?")
            print(f"{os.path.basename(path)}: {e['id']}  moderation {st}")
            rows.append((key, e["id"] if st == "Approved" else 0, st))
    with open(MANIFEST, "w") as fh:
        fh.write(lua_manifest(rows))
    print(f"wrote {os.path.relpath(MANIFEST, ROOT)}")


if __name__ == "__main__":
    main()
