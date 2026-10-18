# tools/sim: the game's Luau generators under lune

Runs `src/shared` (and `src/client/modules`) unchanged outside Roblox, with
[lune](https://github.com/lune-org/lune) 0.11 (`/root/.cargo/bin/lune`).

```sh
lune run tools/sim/export_ref.luau                  # all of it (~1 min)
lune run tools/sim/export_ref.luau --no-before      # only tools/hair/ref
lune run tools/sim/export_ref.luau --before DIR --only afro_k,dreads_k --no-ref
# the generators of another commit (the "before" set of a change):
git archive 5ee2399 src | tar -x -C /tmp/v6 && lune run tools/sim/export_ref.luau --no-ref --src /tmp/v6/src
```

## host.luau

```lua
local Host = require("./host")          -- relative to your script
local H = Host.new()                    -- { root = ..., src = <dir with shared/, client/>, client = false, server = true, globals = {...} }
local Hair = H.require("AnatomyHair")   -- by name (src/shared first, then src/client/modules)
local look = H.Look({ g = 1, age = 26, skin = 6, hair = { style = "Afro", type = "Kinky", color = 1 } })
local res = Hair.Generate(look, "full", H.Ctx("Hair", "full"))   -- ctx as AnatomyClient passes it
local buf, w, h = Host.TextureOf(H, res.pieces.HairCap)           -- texture as AnatomyClient makes it
```

- Every file is a fake ModuleScript in a fake DataModel laid out like `default.project.json`
  (`game.ReplicatedStorage.Shared`, `game.StarterPlayer.StarterPlayerScripts.BoxerClient`), loaded with
  `luau.load` and a `script` of its own: `script.Parent:WaitForChild("X")`, `Shared.X`, `FindFirstChild`,
  `game:GetService("ReplicatedStorage").Shared.X` and `require(node)` all resolve (cached, once).
- Stubs: `game` / `workspace`, `GetService` (RunService, HttpService, CollectionService, Players,
  AssetService: inert), `task` (lune's), `tick`, `time`, `typeof` (nodes are `"Instance"`),
  `Instance.new` (inert), Roblox datatypes and `Enum` from `@lune/roblox`. No EditableMesh / EditableImage.
- `H.Look(spec)`: `LookData.FromBuilder` over `Looks.Defaults(g)` with `spec.hair` / `face` / `beard`
  merged in (`hair.color` may be a `Looks.HairColors` index), `age` 26, then `look.rig = Host.Rig(g)`
  and `look.scale`. `Host.Rig(g)` / `Host.RIG`: the default boxer's rig (comment in host.luau):

| | Head (uniform) | UpperTorso | LowerTorso | Neck C0 / C1 (y) |
|---|---|---|---|---|
| men | 0.927 | 1.59 x 2.08 x 0.97 | 1.59 x 0.52 x 0.97 | 1.04 / -0.705 |
| women | 0.899 | 1.42 x 1.96 x 0.91 | 1.45 x 0.49 x 0.91 | 0.98 / -0.647 |

  Head = 1.2 x HeadScale (0.82, women x 0.97) x 0.942 (Rthro head at BodyTypeScale 1); C1 = -(0.5 +
  NECK_LIFT) x head (Builder liftHead: 0.26 / 0.22). Limbs are left to the Body generator's defaults.

## export_ref.luau outputs

`tools/hair/ref/` (NOMINAL head space: 1.2-stud head, +X right, +Y up, -Z forward, origin = Head
centre; real = nominal x `k`):

- `skull.json` (men) / `skull_f.json` (women): `k`, `headSize`, `centre` (0, P.cy, P.cz);
  `radial {thetas, azimuths, r[i][j]}` (dir = (sin th sin az, cos th, sin th cos az), th 0..150 by 2.5,
  az 0..355 by 5, az 0 = +Z back, 90 = +X); `hairline {keys, soft, lines[kind] {right, left: [da,x,y,z],
  height: [da,y]}}` for Natural / Straight / Widow's Peak / Receding / Line-Up (da = angle from the front
  round the axis x = 0, z = 0.05, step 0.02); `fades {FADES, FADE_TOP, topLines[kind] {right, left},
  coverage[none|low|mid|high|fade|taper|burst][i][j]}` (Kit.Cut coverage on the radial grid);
  `ears {left, right: {min, max, verts}, clearance}`; `body` (Kit.Scalp's proxy: neckCapsule,
  trapezius, torsoBox, `surface.rows [y, [r per 10 deg]]`); `rig {parts, joints, headSpace}`
  (neck / shoulder pivots, torso centre and top, real and nominal); `neck`; `landmarks {head, hair}`; `P`.
- `head_m.obj` / `head_f.obj`: AnatomyHead full LOD, one `o` per piece (Head with ears, EyeL/R, LidL/R,
  LidLow, MouthUpper/Lower), `v x y z r g b`, `vt u 1-v`, `vn`.
- `torso_m.obj` / `torso_f.obj`: AnatomyBody UpperTorso (neck base, traps, shoulders) moved into head space
  (offset c1 - c0, no rotation).

`--before DIR` (default `tools/sim/out/before`, git-ignored; REAL head space, studs): `<id>.json` =
`{id, look, landmarks {hair, head}, pieces {name: P}, head {name: P}}` with
P = `{p, n, uv, c, a?, t, nv, nt, landmarks, material?, doubleSided?, castShadow?, reflectance?,
hideUnder?, hairfx?, texture? {file, w, h}}` (flat arrays as MeshKit.Export: `t` 1-based, CCW from outside;
uv v down; a piece with a texture is drawn with it, not its vertex colours); `<id>_<piece>.rgba` raw RGBA8,
rows top to bottom; `index.json {looks: [{id, file, style, type, g, look, hairPieces, hairVerts, hairTris}]}`.

## Asset hair: after scenes and the end-to-end client test

The asset hair (`tools/hair` outputs, `tools/hair/CONTRACT.md`) through the REAL client code, offline. Both
scripts first (re)write a local manifest with fake ids when it is missing or older than any
`tools/hair/out/*/style.json` or texture: `python3 tools/hair/publish.py --local` ->
`/tmp/claude-0/HairAssetData_local.lua` + `HairAssetData_local.ids.json` (fake id -> `.mesh` / `.png`); pass
`--no-regen` to keep it, `--manifest PATH` for another one.

```sh
lune run tools/sim/after_scene.luau [--before DIR] [--out DIR] [--only id,id] [--lod full] [--npc]
cd tools/hair && /opt/bpyenv/bin/python previews.py after <out> <render dir> highfade_k afro_k
lune run tools/sim/test_hairassets_e2e.luau      # ~20 s, exits non-zero on a failure
```

- `meshv2.luau`: `MeshV2.Read(path)` / `Decode(str)` reads a Roblox `.mesh` version 2.00 (12-byte header,
  36 / 40-byte vertices: position, normal, uv, int8 tangent, [rgba]; 3 x u32 faces) into
  `{P, N, U, C, A, T (1-based), nv, nt, bbox = {cx, cy, cz, sx, sy, sz}}`.
- `assetsim.luau`: a fake AssetService serving the local outputs: `CreateEditableImageAsync(rbxassetid)` -> an
  EditableImage-like object with the PNG's pixels (decoded once by `tools/hair/png2rgba.py` with
  `/opt/bpyenv/bin/python`, cached in `tools/sim/out/rgba/`), `CreateEditableImage`, `CreateMeshPartAsync` (a
  part stub remembering its mesh id; `MeshOf(id)` reads the `.mesh`), `CreateEditableMesh` (a recorder).
  Failure injection: `sim.fail.mesh[id]` / `sim.fail.image[id] = "error"`, `sim.nilImage`, `sim.onCall(kind, id)`.
  `AssetSim.Placed(mesh, size, centre)`: where the engine draws an uploaded mesh on a part of that Size welded
  at centre (recentred on the mesh's bbox, scaled to Size per axis). `AssetSim.UseManifest(H, path)` points
  `Shared.HairAssetData` at the manifest.
- `after_scene.luau`: for every look of a before set (same look table) runs `HairAssets.For` and
  `HairAssets.Build` (HK.Select, HK.Place, CapGrid / PaintCap, Tint, image sharing: the real code) and writes
  each built piece where the engine would draw it (`Placed`) with its tinted EditableImage as `.rgba`; the head
  is the before scene's. Same format as the before set plus `entry`, `fallback`, per piece `material`,
  `alpha = true`, `mesh`, `size`, `centre`. A look without a usable entry (or whose build fails) gets the
  before scene's generated hair, `fallback = true` in the index. Prints per look: entry, pieces, tris, image
  sizes, CPU ms of paint (CapGrid + PaintCap) / tint (Colors + Tint) / the whole build; warns when the manifest's
  bbox or nt disagrees with the `.mesh` file (stale manifest).
- `fakeengine.luau`: Instances with a hierarchy, attributes and firing signals, tags, a stepped Heartbeat, a
  camera and a local player without a character.
- `test_hairassets_e2e.luau`: starts AnatomyClient for real (boot, tracking by tag, the Heartbeat scheduler,
  the worker, runJob -> assetHair -> HairAssets.Build, the generated fallback through AnatomyHair + makePiece,
  attachPiece, Stop) on models carrying LookData (High Fade, Afro x2 sharing a tint, Dreadlocks, Long Hair, a
  Preview afro, a style with no entry). Checks every asset piece is welded to Head at HK.Place's centre with
  its Size, sits around the head, is textured, and that GetPieces gives HairFX points / hairfx; then a look
  change mid-build (cancel, the new look built), the model destroyed mid-build, a mesh 404 (generated hair, id
  failed for the session), every id 0 (generated hair, no image loaded) and CreateEditableImage returning nil
  (textures paused, generated hair), with no part / EditableMesh / EditableImage leaked after each, and
  nothing left after Stop. Simulated: the engine (welds as records, calls answer at once). Body / Head are
  registered as empty generators and Perf / State / AnatomyStatus left out; not covered: rendering, the
  engine's memory budget, real asset permissions, network latency.

## v8 previews and the gear

`v8_scene.luau` runs `Builder.Cosmetics` on a fake rig for the v8 cast (tier bodies, classic heads, the asset hair
and the mesh gear of `BuilderGear`: the gear manifest is `src/shared/GearAssetData.lua` when it has uploaded ids,
else `publish_gear.py --local`'s, `--gear PATH` to choose; ids map to `tools/body/out/gear` files through
`tools/body/uploaded.json` or the local sidecar). `v8_render.py SCENE OUT` renders the sheets and `lineup.jpg`
(`previews/final/v8/`).

`test_gear.luau [--gear PATH]`: the gear manifest (every piece at every tier, sets, sides, < 6k triangles an
outfit), the piece per body-part tier (mixed tiers, a tier change), styles, size x ratio / weld offsets, colours,
gloves / wraps / bare hands, the women's top, officials, sweat, the rebuild cache, and the fallback to the
part-built gear (ids 0, failed loads, default parts).

## v9: the client Animator on the tier boxers

`v9_anim.luau` runs the REAL `src/client/Animator.client.lua` (and every Anim* module) on complete boxers built by the
server's `Builder.Cosmetics` (v8_scene's fake rig: the tier swap, the classic head, the mesh gear), on a virtual clock
(`os.clock` / `time` are the simulator's; `RunService.PreSimulation` is stepped at 60 Hz; `workspace:Raycast` hits a
floor at Y = 0); the joints are solved from the Motor6D Transforms the Animator writes, every frame.

```sh
lune run tools/sim/v9_anim.luau [--out DIR] [--tiers 1,3,5] [--clips rest,walk,jog,run,punch] [--frames 8]
         [--bare 1] [--hands gloves|wraps|bare] [--gap 4.0] [--no-mesh]
         [--body BodyLocal.lua --gear GearLocal.lua]   # publish_body.py / publish_gear.py --local manifests
         [--src DIR --meshroot DIR]                     # another commit's src and its tools/body/out copy
/opt/bpyenv/bin/python tools/sim/v9_render.py SCENE_DIR OUT_DIR [--tag after] [--samples 20] [--only id,id]
```

- walk / jog / run: `Players.LocalPlayer.Character` glides along -Z at 5 / 11 / 16 studs/s; one gait cycle recorded
  (`--frames`), and printed: the pelvis / chest / head sway across the HumanoidRootPart's line, the pelvis roll, the
  hip flexion range, the LowerTorso surface the thighs cover (pelvis-in-thigh)
- punch: two "Fighter" models `--gap` studs apart; jab, cross, lead / rear hook, uppercut and a body jab (Act / ActId as
  FightEngine sends them), 6 frames each (start .. peak .. return); printed: the glove's reach, its distance and height
  to the target, the elbow angle, the waist's turn
- rest: one standing frame (front / 3/4 / side / back and close-ups of the arm, the hand, the hips)
- v9_render: walk clips as orthographic filmstrips (front, side; the red line = the root's centre line), punches as
  panels (side, 3/4 front) plus arm close-ups, rest as a sheet

`tools/body/check_joints.py` (each joint of the tier bodies through the Animator's ranges: the parent's surface the child
covers / the parent's end it uncovers) and `tools/body/check_gear.py` (the trunks over the body, the thighs swung) are
the numeric side of the same checks, numpy only.
