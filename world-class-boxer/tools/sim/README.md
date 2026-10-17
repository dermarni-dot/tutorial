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
