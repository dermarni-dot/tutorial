"""Uploads the hair meshes and textures to Roblox with Open Cloud and writes the game's manifest.

    python publish.py [--dry-run] [--no-manifest] [--only key,key] [--textures DIR]
    python publish.py --local [OUT.lua]     # offline: fake ids, nothing uploaded (see below)

* Creator: ROBLOX_CREATOR_ID / ROBLOX_CREATOR_TYPE (group | user) from the environment.
* API key: x-api-key from ROBLOX_API_KEY, unless a proxy injects it (then leave it unset).
* Meshes go up as assetType "Mesh" (Roblox .mesh 2.00 files, out/<key>/*.mesh), textures as
  assetType "Image" (PNG). Every upload is cached by the file's SHA-256 in uploaded.json, so a re-run
  uploads only what changed and the game's ids stay stable.
* Writes src/shared/HairAssetData.lua from out/*/style.json + the cache.
* --local [PATH] uploads nothing and leaves the cache and the game's manifest alone: it writes the manifest to
  PATH (default /tmp/claude-0/HairAssetData_local.lua) with FAKE positive ids (LOCAL_ID0 + index, one per
  file) and a JSON sidecar next to it (PATH with .ids.json) mapping each fake id to the local .mesh / .png file,
  so a simulator can draw the real outputs offline.
"""
import argparse
import glob
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")
CACHE = os.path.join(HERE, "uploaded.json")
MANIFEST = os.path.join(ROOT, "src", "shared", "HairAssetData.lua")
API = "https://apis.roblox.com/assets/v1"
LOCAL_DEFAULT = "/tmp/claude-0/HairAssetData_local.lua"
LOCAL_ID0 = 9000000000
# tileable textures (one flat colour, wrap both ways): the scalp cap's tiles. Every other key is a card texture
# (roots at v = 0, tips at v = 1), crop included
TILE_TEXTURES = {"short", "shortcoil", "waves"}
# entry-level style.json fields carried into the manifest
ENTRY_FIELDS = ("styles", "types", "cap", "capTile", "capTileRepeat", "capFade", "capEarLine")
# the cap entry's fields carried into data.cap (besides its one piece's mesh, bbox, points, nt, material, ...)
CAP_FIELDS = ("thetaMax", "tile", "tiles", "pole", "earLine")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def load_cache():
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            return json.load(f)
    return {}


def save_cache(c):
    with open(CACHE, "w") as f:
        json.dump(c, f, indent=1, sort_keys=True)


def _headers(extra=None):
    h = {"User-Agent": "wcb-hair-publish/1"}
    key = os.environ.get("ROBLOX_API_KEY")
    if key:
        h["x-api-key"] = key
    h.update(extra or {})
    return h


def _request(method, url, body=None, headers=None, tries=5):
    delay = 2
    for i in range(tries):
        req = urllib.request.Request(url, data=body, method=method, headers=_headers(headers))
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            txt = e.read().decode(errors="replace")
            if e.code in (429, 500, 502, 503, 504) and i < tries - 1:
                time.sleep(delay)
                delay *= 2
                continue
            raise RuntimeError(f"{method} {url} -> HTTP {e.code}: {txt[:400]}")
        except urllib.error.URLError as e:
            if i < tries - 1:
                time.sleep(delay)
                delay *= 2
                continue
            raise


def creator():
    cid = os.environ["ROBLOX_CREATOR_ID"]
    kind = os.environ.get("ROBLOX_CREATOR_TYPE", "group").lower()
    return {"groupId": cid} if kind == "group" else {"userId": cid}


def upload(path, asset_type, name, desc, content_type):
    boundary = uuid.uuid4().hex
    req = {"assetType": asset_type, "displayName": name[:50], "description": desc[:1000],
           "creationContext": {"creator": creator()}}
    with open(path, "rb") as f:
        data = f.read()
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n"
        f"Content-Type: application/json\r\n\r\n{json.dumps(req)}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; "
        f"filename=\"{os.path.basename(path)}\"\r\nContent-Type: {content_type}\r\n\r\n".encode(),
        data, f"\r\n--{boundary}--\r\n".encode(),
    ]
    op = _request("POST", f"{API}/assets", b"".join(parts),
                  {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    opid = op.get("operationId") or op["path"].split("/")[-1]
    for _ in range(90):
        if op.get("done"):
            break
        time.sleep(2)
        op = _request("GET", f"{API}/operations/{opid}")
    if not op.get("done"):
        raise RuntimeError(f"operation {opid} for {path} did not finish")
    if "error" in op:
        raise RuntimeError(f"upload {path} failed: {op['error']}")
    resp = op["response"]
    state = resp.get("moderationResult", {}).get("moderationState")
    return int(resp["assetId"]), state


class LocalIds:
    """--local: a fake positive id per file (stable within one run), and the id -> file map for the sidecar."""

    def __init__(self):
        self.files = {}
        self.by_path = {}

    def __call__(self, path):
        path = os.path.abspath(path)
        if path not in self.by_path:
            aid = LOCAL_ID0 + len(self.by_path) + 1
            self.by_path[path] = aid
            self.files[str(aid)] = path
        return self.by_path[path]


def ensure(cache, path, asset_type, name, desc, content_type, dry, local=None):
    if local is not None:
        return local(path)
    h = sha(path)
    hit = cache.get(h)
    if hit:
        return hit["id"]
    if dry:
        print(f"  would upload {asset_type:5} {os.path.relpath(path, HERE)}")
        return 0
    aid, state = upload(path, asset_type, name, desc, content_type)
    cache[h] = {"id": aid, "type": asset_type, "file": os.path.relpath(path, HERE), "name": name,
                "moderation": state, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    save_cache(cache)
    print(f"  uploaded {asset_type:5} {aid} {os.path.relpath(path, HERE)} ({state})")
    return aid


# ----------------------------------------------------------------------------------- manifest
def lua(v, ind=0):
    pad = "\t" * ind
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        s = f"{v:.5f}".rstrip("0").rstrip(".")
        return s if s not in ("-0", "") else "0"
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float)) for x in v):
            return "{ " + ", ".join(lua(x) for x in v) + " }" if v else "{}"
        return "{\n" + "".join(f"{pad}\t{lua(x, ind + 1)},\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        out = "{\n"
        for k in sorted(v, key=lambda k: (not isinstance(k, str), str(k))):
            key = k if isinstance(k, str) and k.isidentifier() else f"[{json.dumps(k)}]"
            out += f"{pad}\t{key} = {lua(v[k], ind + 1)},\n"
        return out + pad + "}"
    raise TypeError(type(v))


def read_style(sj):
    """out/<key>/style.json, checked: None (with a warning) when it is unreadable or a mesh it names is missing
    (a builder still writing it)."""
    try:
        with open(sj) as f:
            st = json.load(f)
    except (OSError, ValueError) as e:
        print(f"  skip {os.path.relpath(sj, HERE)}: {e}", file=sys.stderr)
        return None
    if not isinstance(st, dict) or not isinstance(st.get("pieces"), dict):
        print(f"  skip {os.path.relpath(sj, HERE)}: no pieces", file=sys.stderr)
        return None
    st.setdefault("key", os.path.basename(os.path.dirname(sj)))
    d = os.path.dirname(sj)
    for name, rec in st["pieces"].items():
        mf = rec.get("mesh_file") if isinstance(rec, dict) else None
        if not mf or not os.path.exists(os.path.join(d, mf)):
            print(f"  skip {st['key']}: piece {name} has no mesh file ({mf})", file=sys.stderr)
            return None
        if "bbox" not in rec:
            print(f"  skip {st['key']}: piece {name} has no bbox", file=sys.stderr)
            return None
    return st


def used_files():
    files = set(glob.glob(os.path.join(HERE, "textures", "hair_*.png")))
    for sj in glob.glob(os.path.join(OUT, "*", "style.json")):
        st = read_style(sj)
        if st:
            files |= {os.path.join(os.path.dirname(sj), r["mesh_file"]) for r in st["pieces"].values()}
    return files


def moderation():
    cache = load_cache()
    counts = {}
    bad = []
    for path in sorted(used_files()):
        hit = cache.get(sha(path))
        if not hit:
            bad.append((path, "not uploaded"))
            continue
        try:
            r = _request("GET", f"{API}/assets/{hit['id']}?readMask=moderationResult")
            state = (r.get("moderationResult") or {}).get("moderationState") or "?"
        except Exception as e:  # noqa: BLE001
            state = f"error {e}"
        hit["moderation"] = state
        counts[state] = counts.get(state, 0) + 1
        if state != "Approved":
            bad.append((path, state))
    save_cache(cache)
    print("moderation:", ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    for p, s_ in bad:
        print("  ", os.path.relpath(p, HERE), s_)
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--textures", default=os.path.join(HERE, "textures"))
    ap.add_argument("--no-manifest", action="store_true")
    ap.add_argument("--local", nargs="?", const=LOCAL_DEFAULT, default=None, metavar="OUT.lua",
                    help=f"write the manifest with fake ids to OUT.lua (default {LOCAL_DEFAULT}) and an id -> file "
                         "sidecar (OUT.ids.json); uploads nothing, touches neither the cache nor the game's manifest")
    ap.add_argument("--moderation", action="store_true",
                    help="re-read the moderation state of every cached upload the current out/ uses (Open Cloud "
                         "GET assets/{id}), update uploaded.json and list any that are not Approved")
    args = ap.parse_args()
    if args.moderation:
        return moderation()
    local = LocalIds() if args.local else None
    cache = {} if local else load_cache()
    only = set(filter(None, args.only.split(",")))

    tex_ids = {}
    tex_meta = {}
    for png in sorted(glob.glob(os.path.join(args.textures, "hair_*.png"))):
        key = os.path.basename(png)[5:-4]
        from PIL import Image
        with Image.open(png) as im:
            size = im.size[0]
        tex_ids[key] = ensure(cache, png, "Image", f"WCB Hair {key}",
                              f"Become a World Class Boxer: hair strand texture '{key}' (greyscale, alpha)",
                              "image/png", args.dry_run, local)
        tex_meta[key] = {"id": tex_ids[key], "size": size, "tile": key in TILE_TEXTURES}

    cap = None
    entries = []
    for sj in sorted(glob.glob(os.path.join(OUT, "*", "style.json"))):
        st = read_style(sj)
        if st is None:
            continue
        key = st["key"]
        if only and key not in only and key != "cap":
            continue
        d = os.path.dirname(sj)
        pieces = {}
        for name, rec in sorted(st["pieces"].items()):
            mid = ensure(cache, os.path.join(d, rec["mesh_file"]), "Mesh", f"WCB Hair {key} {name}",
                         f"Become a World Class Boxer: hair card mesh {key}/{name}", "model/x-file-mesh-data",
                         args.dry_run, local)
            # every piece field (tex, bbox, points, nt, hairfx, hideUnder, length, material, castShadow, ...)
            p = {k: v for k, v in rec.items() if k not in ("mesh_file", "nv")}
            p["mesh"] = mid
            pieces[name] = p
        if key == "cap":
            if len(pieces) != 1:
                raise SystemExit(f"out/cap/style.json: one piece expected, got {sorted(pieces)}")
            (name, p), = pieces.items()
            cap = dict(p)
            cap.pop("tex", None)
            for k in CAP_FIELDS:
                if k in st:
                    cap[k] = st[k]
            continue
        e = {"key": key, "pieces": pieces}
        for k in ENTRY_FIELDS:
            if k in st:
                e[k] = st[k]
        e.setdefault("styles", [])
        entries.append(e)

    if args.no_manifest:
        return
    # the reference the meshes are modelled on (hairlib.REF): the classic head (v9: ref/classic, fit0 with shape
    # "classic": HairAssetKit's fit is then the identity on a classic head) unless HAIR_REF=organic (v7: ref/)
    ref = os.path.join(HERE, "ref") if os.environ.get("HAIR_REF") == "organic" else os.path.join(HERE, "ref", "classic")
    with open(os.path.join(ref, "skull.json")) as f:
        fit0 = json.load(f).get("fit0")
    # the default male skull's four fit extents, measured on the game's field (CONTRACT.md)
    fit0 = fit0 or {"W": 0.383, "T": 0.591, "Fz": -0.460, "Bz": 0.520}
    data = {"version": 1, "flipV": False, "textures": tex_meta, "cap": cap, "fit0": fit0, "entries": entries}
    head = ("-- GENERATED by tools/hair/publish.py from tools/hair/out/*/style.json and the upload cache\n"
            "-- (tools/hair/uploaded.json). Do not edit by hand: re-run the builders and publish.py.\n"
            "-- Asset hair: hair-card meshes (Mesh assets) and strand textures (Image assets) owned by the\n"
            "-- game's group, in nominal head space (tools/hair/CONTRACT.md). An entry with a 0 id is unused\n"
            "-- and the generated hair draws that style instead.\n")
    if local:
        head = ("-- LOCAL manifest from tools/hair/publish.py --local: FAKE asset ids (nothing uploaded), for offline\n"
                "-- simulation only. Each id's file is in the .ids.json sidecar next to this file.\n")
    body = "return " + lua(data) + "\n"
    out = os.path.abspath(args.local) if local else MANIFEST
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        f.write(head + body)
    if local:
        side = os.path.splitext(out)[0] + ".ids.json"
        with open(side, "w") as f:
            json.dump({"ids": local.files, "manifest": out}, f, indent=1, sort_keys=True)
        print("wrote", out, len(entries), "entries (fake ids);", side, len(local.files), "files")
    else:
        print("wrote", os.path.relpath(MANIFEST, ROOT), len(entries), "entries")


if __name__ == "__main__":
    sys.exit(main())
