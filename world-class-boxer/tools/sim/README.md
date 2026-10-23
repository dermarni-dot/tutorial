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
lune run tools/sim/v9_anim.luau [--out DIR] [--tiers 1,3,5] [--clips rest,walk,jog,run,sprint,startstop,turn,curve,punch]
         [--frames 8] [--height IN] [--speeds walk=6.5,run=16] [--shotevery N]
         [--debugrig T] [--debugfoot 1]                 # foot state per frame from T s / the drawn boot's bounds
         [--bare 1] [--hands gloves|wraps|bare] [--gap 4.0] [--no-mesh]
         [--body BodyLocal.lua --gear GearLocal.lua]   # publish_body.py / publish_gear.py --local manifests
         [--src DIR --meshroot DIR]                     # another commit's src and its tools/body/out copy
/opt/bpyenv/bin/python tools/sim/v9_render.py SCENE_DIR OUT_DIR [--tag after] [--samples 20] [--only id,id]
         [--views front,side] [--gif 1 [--ms 50]]
```

- walk / jog / run / sprint: `Players.LocalPlayer.Character` glides along -Z at 6.5 / 11 / 16 / 22 studs/s (the town
  walk, the ring's pace, Shift's run, the roadwork pace; `--speeds walk=5,run=16` overrides); one gait cycle recorded
  (`--frames`), and printed: the pelvis / chest / head sway across the HumanoidRootPart's line, the pelvis roll, the
  hip flexion range, the LowerTorso surface the thighs cover (pelvis-in-thigh), and the gait numbers: knee / hip /
  thigh / ankle / foot pitch, shoulder / elbow / wrist ranges, pelvis and chest yaw, trunk pitch, the pelvis and head
  bob, the soles' lowest point against the floor (sink / clearance, over the drawn boot meshes), and the planted feet's
  slide (the sole point that touched the floor on one frame, where it is on the next: zero for a foot that rolls
  without slipping), for the steady pace and for the start. Per clip `gait_<clip>_t<tier>[_h<in>].json`: the summary
  and the per-frame series
- startstop / turn / curve (`--clips`): scripted clips - a 0.12 s ramp to the walk, 1.9 s of walking, a 0.12 s stop
  (a Humanoid's own pick-up); a 180 degree turn in place at 3.5 rad/s; a 90 degree walking turn. Printed: the slide,
  the sink and the largest one-frame change of the knee / hip / shoulder / elbow (snaps) and the pelvis / head
  height; `--shotevery N` records every Nth frame (an even clock for a GIF) instead of the clip's shots
- `--height IN` (60..84, Builder.Scales' 0.86..1.2) builds the boxer at that height; the clip ids carry `_h<IN>`
- punch: two "Fighter" models `--gap` studs apart; jab, cross, lead / rear hook, uppercut and a body jab (Act / ActId as
  FightEngine sends them), 6 frames each (start .. peak .. return); printed: the glove's reach, its distance and height
  to the target, the elbow angle, the waist's turn
- rest: one standing frame (front / 3/4 / side / back and close-ups of the arm, the hand, the hips)
- v9_render: walk clips as orthographic filmstrips (front, side; the red line = the root's centre line; `V9_GAP` = the
  spacing in studs), punches as panels (side, 3/4 front) plus arm close-ups, rest as a sheet; `--gif 1` renders every
  frame of a walking / scripted clip on its own, the camera following the root over world-fixed floor marks (a sliding
  foot shows against them), as an animated GIF (`--ms` = frame time; default the clip's own spacing)

### Fight scenarios: --clips fight

```sh
lune run tools/sim/v9_anim.luau --tiers 3 --clips fight [--only jab,combo123,ko_body] [--every 3] [--no-mesh] [--dbgfoot]
/opt/bpyenv/bin/python tools/sim/v9_render.py DIR OUT --tag after --views side,34 [--strip 8] [--gif 1]
python3 tools/sim/v9_fight_plot.py OUT.png BEFORE/fightseries_<id>_t3.json AFTER/fightseries_<id>_t3.json
```

- Two Fighters 4 studs apart in an "Arena" model (a CornerStool behind A for `rest_stool`), a third boxer tagged
  Referee off to the side for the knockdowns. Each scenario is a list of the server's own events: act strings (Act +
  ActId, as FightEngine / Evasion / Combos send them, "cross|R|head|0.21||2" for a chained punch), attributes (Guard,
  DownPose, DownDir, KOKind, Count, Daze, Stam, Style) and root glides (footwork, the side-step's 1.6 stud lunge, the
  referee walking in to catch). About 80 of them: the guard per style and tired, footwork, the pivot, the clinch, every
  punch head and body, combos, all 14 specials, slips / roll / weave / duck / pull / side-step / shoulder roll / parry /
  block and counters out of them, hits by severity and zone, the stagger, hurt and dazed legs, knockdowns with the
  count and the get-up, every KO kind (with the referee's wave-off and the winner's celebration), the stool, win / lose.
- Printed per scenario: the planted feet's slide while he stands (pelvis within 0.6 of the stance's height), per joint
  group (arms, trunk, neck, legs) the largest one-frame turn of a Motor6D Transform and the largest one-frame change of
  its turning speed (deg / frame^2: a snap) with the count of frames over 4, the root's translation jerk, at each punch's
  contact (act start + windup, when the server lands it) the glove's distance and height to the target, and for a KO the
  wall time until the client-local KOLanded (against FightMotion.KOFallWall). `fight_metrics_t<tier>.json` holds it all,
  `fightseries_<id>_t<tier>.json` the per-frame curves (joint angles, the hands and head in the root's frame, every
  joint's per-frame turn `w<key>`, the feet's slip).
- Swing styles: `sty_<id>` (boxerpuncher, outboxer, swarmer, slugger, counter, outboxer_heavy) throw the same jab, cross,
  lead hook, uppercut and overhand one second apart with their own Style, seed (the AnimSeed attribute) and PunchStyle;
  `python3 tools/sim/v9_style_sheet.py GIFS OUT` cuts the six 3/4 GIFs (`--tag style --views 34 --gif 1`,
  `V9_WINDOW=0`) into one side-by-side GIF per punch.
- With meshes, `fight_<id>_t<tier>.json` keeps every `--every`-th frame (both fighters and the referee) and its action
  window (`focus`): v9_render draws filmstrips over the window (side: from A's right; 34: behind A's rear shoulder) and,
  with `--gif 1`, a GIF of the window (`V9_WINDOW=0`: every frame) with world-fixed floor marks.

`tools/body/check_joints.py` (each joint of the tier bodies through the Animator's ranges: the parent's surface the child
covers / the parent's end it uncovers) and `tools/body/check_gear.py` (the trunks over the body, the thighs swung) are
the numeric side of the same checks, numpy only.

## UI layout: guisim and test_ui_layout

`guisim.luau` lays the game's 2D UI out under lune: the real LocalScripts (`S.loadScript("client/FightClient.client.lua")`)
and modules on fakeengine, with a GUI layout model (UDim2, AnchorPoint, UIScale, UIPadding, UIListLayout,
UIGridLayout, AutomaticSize, size / aspect constraints, ScrollingFrame clipping, text metrics for Gotham and the
condensed Oswald), the 58 px top bar and the device's safe insets, `AbsoluteSize` / `AbsolutePosition` /
`TextBounds` computed on demand, tweens landing on their goal. Devices: `phone` (844 x 390, notch insets),
`phone_small` (667 x 375), `tablet` (1024 x 768), `desktop` / `console` (1920 x 1080), `phone_pad`, `laptop`
(1366 x 650). `S.collect()` lists what is on the screen, `S.checks(items)` finds what runs off it, sits under the
top bar's buttons, is under a fingertip (44 px) on touch, overflows its box or draws under 10.5 px.

```sh
lune run tools/sim/test_ui_layout.luau [--only fight,menu] [--devices phone,tablet] [--previews DIR] [-v]
python3 tools/sim/ui_preview.py tools/sim/out/ui/*.json --out DIR    # rough box previews of the dumps
```

Each screen x device runs in its own lune process (four at a time). The previews draw every object's bounding
box (buttons blue, flagged ones red, the top bar hatched, the safe insets orange), not a render: the preview's
font is scaled to the width guisim measured, so text that looks cut there is cut by the layout.

### How much UI a screen builds: tools/ui/ui_profile.luau

```sh
lune run tools/ui/ui_profile.luau [--device desktop] [--tabs Career,Training] [--json OUT]
```

Opens the Career Hub on guisim and prints, per tab, the GUI objects it builds, the UI.Icon frames, text labels and
images, the change in live signal connections (fakeengine's `FE.Connections`: instance-owned signals drop their
connections on Destroy as the engine does, so what remains is a real leak) and the build time; then how many
rebuilds a burst of six profile pushes in one frame causes, and what three open / close cycles leave behind.
Numbers, not pass / fail (the Training tab's exercise cards build their body-map thumbnails only as they scroll
into the view: 4702 -> ~2100 objects on a desktop).

### Mock screenshots: tools/ui/render_mock.py

`GS.WriteBoxes` also writes each object's look (`style`: paint order key, colours, corner radius, stroke, gradient,
font, image asset id and rect). `tools/ui/render_mock.py` draws those dumps as approximate screenshots (Inter standing
in for Gotham / Oswald, the icon sheets and logo from `tools/ui/out` by their uploaded ids, a dark arena for the 3D
world):

```sh
lune run tools/sim/test_ui_layout.luau --only menu,hub
python3 tools/ui/render_mock.py --all tools/sim/out/ui --only menu,hub --devices desktop,phone --out DIR
```

The icon set and the logo: `python3 tools/ui/build_icons.py` (SVG through cairosvg -> `tools/ui/out`), then
`python3 tools/ui/publish_icons.py` (Open Cloud upload, hash cache `tools/ui/uploaded.json`, moderation check, writes
`src/shared/IconData.lua`). `test_ui_layout` fails a screen that shows an icon name neither the sheets nor UI.Icon's
Frame drawing know.

## The first-time tutorial fight: test_tutorial

`lune run tools/sim/test_tutorial.luau` (a few seconds) checks `src/shared/Tutorial.lua`, `src/server/TutorialFight.lua`
and `src/client/modules/Tutorial.lua`: who is offered the tutorial (`Tutorial.ShouldOffer`, and `Tutorial.Backfill` on
DataManager's load: an existing career or an older save counts as done), that `TutorialFight.Build` on a real career
(`Career.CreateProfile`) leaves the profile, its records, money, injuries and move unlocks (`Moves.Info` /
`Moves.Unlocked`) untouched while both corners are random boxers (`World.RandomBoxer`, the opponent weaker) in a fight
venue with a modest crowd, that the end writes only `tutorialDone`, the ten steps in order (each advancing only on its
own input; the round clock's hold / break / run; knockdowns only at the last step; the stamina step's drain, refill and
timeout), the prompts' keys per device against `Keymap.ActionText` (a remapped key follows), and, through the real
client module on guisim, the offer's and the step card's SKIP TUTORIAL and the wrap-up's way on (creator / menu).
`test_ui_layout` lays out the step card over the fight HUD (`fight_tutorial`, `fight_tutorial_keys`), the offer
(`tutorial_offer`) and the wrap-up (`tutorial_done`) on every device. The bout itself (FightEngine with
`opts.tutorial`) needs Studio.

## Whole fights headless: fightsim, balance, test_fightai, test_fightfixes

`tools/sim/fightsim.luau` runs whole bouts with the real `FightEngine` / `FightAI` on stub rigs in a 22-stud ring
(a fake clock and a coroutine scheduler: `task.delay` / `task.spawn` / `task.wait` run on it, so the knockdown count
really counts). The red corner is a second FightAI (AI vs AI) or a scripted player (`S.Bot`: spam, onetwo,
headhunter, body, volume, power, counter, pressure, smart, novice), which only reacts to the AI's punches after a
human reaction time. `S.Fight({ red = {...}, blue = { style, level, traits = { { id, s } } | noTraits }, rounds,
seed, onTick })`; `FS.new({ root = DIR })` runs another checkout (a `git archive` of an older commit: the "before").

- `lune run tools/sim/balance.luau [n] [styles|levels|bots|traits|adapt] [--root DIR]`: the balance tables (AI vs AI
  by style and by level gap, scripted players by level, each trait against the types it resists, the adapting player
  against each trait). About 0.5 s a fight.
- `lune run tools/sim/test_frametraits.luau [--quick] [--table]` (a few minutes): the body frames' ring traits
  (`Shared.FrameTraits`: the multipliers, Athletic the baseline, the orderings), where the engine applies them (the
  punch window and the client's mirror, the stamina a punch costs, the feet, the reach, the dodge windows, head and body
  damage taken, the get-up, the clinch, the tape), the AI fighting to its frame, and the balance at equal level
  (Heavyweight vs Lean about even, the heavyweight stopping more and the Lean winning on the cards more; every frame
  near even against Athletic). `--table` prints the whole frame x frame matrix. `fightsim` takes `frame = <BodyTypes id>`
  in a corner's spec.
- `lune run tools/sim/v10_frames.luau --out tools/sim/out/frames` then `python3 tools/ui/render_mock.py --all
  tools/sim/out/frames --out previews/final/v10/frames`: the creator's Body step with the frame's pros / cons panel, one
  screen per frame and device.
- `lune run tools/sim/test_fightai.luau [--quick]` (a few minutes): the ring traits (`Shared.Traits`: seed, style,
  level, caps, scouting, reveal, each effect and its counter), the fighting type, the read (`Shared.FightRead`),
  FightAI's perception delay / prediction / adaptation / mistakes / feints, the feint, the second wind, accuracy with
  fatigue / damage / eyes, the blind side, side-aware slips, the clinch's inside work and break, the momentum and the
  live score, and wide balance bounds.
- `lune run tools/sim/test_fightfixes.luau`: a dodge that won is over (no CAUGHT MID-DODGE after it), the debut's
  doctor / corner / protection / final rest, the debut offer kept on a refused start, Shift held + Q = a slip.

## Training drills: test_drills

`lune run tools/sim/test_drills.luau [--judges] [--only Bench,Sauna] [-v]` (~30 s) plays every training drill with
simulated players (`drillbots.luau`: a perfect, an average and an idle player for every DrillScore / DrillWorkouts
judge). Part A: the server's plan (`Training.DrillPlan`, levels 1 / 3 / 5) through the judges on a virtual clock;
the input stream through `DrillScore.Replay` must give the score the judges gave live; perfect >= 0.85, idle <= 0.15
(the sauna 0.3), average in between, never "too quick", no easier at the top level. Part B (`drillsim.luau`): the real
client drill (`Activities.Start`) on guisim with a fake server and a virtual clock, played through each device's own
path (keys, pad buttons / stick flicks, on-screen buttons): the session hands in, client score = server replay,
every action reachable, the prompts name the device's controls, the stats table is valid, the pose attributes move.
`test_ui_layout` lays the drills out mid-session (`drill_*` screens) through the same `drillsim.luau`.

## The world: world_scene, world_render, test_worlddetail

```sh
lune run tools/sim/world_scene.luau [--out DIR] [--level 1|2|3] [--only gym,city,venues,menu] [--src DIR] [--counts]
/opt/bpyenv/bin/python tools/sim/world_render.py DIR/scene.json OUT_DIR [--only view,view] [--samples N] [--res WxH]
lune run tools/sim/test_worlddetail.luau [--keep]      # ~1 min: builds the world at Low / Medium / High
```

- `world_scene.luau` builds the world offline on fakeengine with a permissive stub layer (signals, PivotTo / GetPivot /
  GetBoundingBox, TweenService, Remotes, a pinned Perf level): the server gym and city (`MapBuilder.BuildGym` ->
  GymDecor, CityMap), the client gym / city dressing (`GymVisuals.Refresh`, `CityVisuals.Refresh` on a level-3
  profile), the detail layer (`WorldDetail.BuildAll` at `--level`), every venue (`Venues.BuildTemplates` /
  `Venues.New` per kind, then `VenueDetail.Build`) and the title set (`MenuStage.Build`, plus a grey stand-in where the
  menu clones your boxer). `DIR/scene.json`: per root (`server_gym_and_city`, `server_city`, `LocalGym`, `LocalCity`,
  `WorldDetail_gym`, `WorldDetail_city`, `venue_<Kind>`, `VenueDetail_<Kind>`, `menu`) the parts (shape, size, CFrame,
  colour, material, transparency, SpecialMesh, tags, collision flags), lights, SurfaceGuis laid out to face
  fractions, decals / textures and beams; `counts` (instances, parts, lights, guis, decals, beams, particles) and
  `cells` (parts per detail cell tier). `--src` builds another commit's `src` (a `git archive` of it): the "before".
- The signage (Shared.Signage: every place's lockup - the icon tile, the wordmark, the sub line - on the shop
  fronts, the gym's entrance sign and lobby banner, the venue banners, and the same lockup as a badge in the menus)
  has its own views: `city_signs_day` / `city_signs_night` / `city_signs_east` (the shop fronts, close),
  `gym_banner` / `gym_motto` (the lobby's +Z wall and the north wall, from inside).
- `world_render.py` renders the views in its `VIEWS` table with Cycles: parts merged by material class with their
  colours, SurfaceGuis rasterised with PIL (frames, gradients, text, the uploaded images by id), decals / textures
  from the upload caches (`tools/world/uploaded.json`, `tools/ui/uploaded.json`), Point / Spot / Surface lights, Neon
  emission, `NightLight` / `NightLens` switched on in the night views. Approximate: no Roblox material textures.
- `test_worlddetail.luau`: every detail part never collides / queries / touches; no detail part (thicker than a floor
  decal) in a keep-out volume (station use points and equipment, prompts, the Ambient members' spots, the spawn pad,
  the doors, the entrance path, the lounge stair, the gym ring's canvas; Main Street's pedestrian and traffic lanes;
  the venue rings inside the ropes, the walkway lanes, the stool corners, the floor cameras); the detail builds without
  a warning; the part counts rise Low < Medium < High and stay under their caps. Overlaps of detail with solid props
  are printed (not failures).
- The gym's detail is two modules on one streamer: `GymDetail` (first pass) registers `GymDetail2` (second pass: print
  walls, wall kit, the weigh-in corner, the locker-room TV, wear). Close-up gym views for the second pass: `gym_corner`,
  `gym_kitwall`, `gym_bagwall`, `gym_weights2`, `gym_whiteboard`, `gym_cardio`, `gym_weighin`, `gym_desk`, `gym_lockers`,
  `gym_walls_n`, `gym_walls_w`, `gym_ceiling`. The keep-outs include each station camera's sight lines (the three
  `Activities.stationCamera` spots to the athlete), the ring apron, the zone doorways and the walkways.
- The textures the detail layer uses: `tools/world/build_textures.py` (PIL + numpy -> `tools/world/out`) and
  `tools/world/publish_world.py` (Open Cloud upload, hash cache, moderation, writes `src/shared/WorldAssetData.lua`).

## The ring officials: v9_referee, v9_referee_render, test_referee

```sh
lune run tools/sim/v9_referee.luau [--out DIR] [--src DIR] [--gear PATH] [--seeds 1,3] [--only stand,count]
/opt/bpyenv/bin/python tools/sim/v9_referee_render.py SCENE_DIR OUT_DIR [--tag after] [--only id,id] [--samples N]
         [--views front,34,side,back] [--ring 0] [--closeups 0]
lune run tools/sim/test_referee.luau          # a few seconds
```

- `v9_referee.luau`: the referee as FightEngine builds him (`Officials.Look` when the src has it, else the old inline
  SpawnReferee look) through `Builder.Cosmetics` on v9_anim's fake rig, with two boxers for scale, posed by the REAL
  client Animator (tag `Referee`, Loop `referee`): his stance, the catch / separate (`catch|t`), the count (`refcount|n`,
  arm up and the chop), the wave-off, two walking frames at his WalkSpeed 11; forced tier 1 and tier 5 referees
  (stance, count) and the spar coach (outfit `cornerman`). Prints each official's audit: tiers, face style, decals,
  headgear, the mesh / part-built outfit pieces and any boxing gear found on him. Shots in the v9_anim frame format.
- `v9_referee_render.py`: per shot front / 3/4 / side / back framed on the official in a simple ring (half 12), plus a
  close-up sheet (chest, shoulder, back, waist, shoes) of the stance shots: `previews/final/v9/referee`.
- `test_referee.luau`: Officials.Look / Colors (bare hands, a neutral / stern drawn face, the venue's shirt, white for a
  title fight), the referee's whole `official.Referee` set as welded mesh pieces painted from those colours, no boxing
  gear, one face decal, every tier / mixed tiers / the lite set, the coach's `Coach` set, `Config.HeadgearOfficials`
  either way, ids 0 -> the part-built outfit, FightEngine building through Officials.

## Tournaments: test_tournaments and the v9 ceremony previews

`lune run tools/sim/test_tournaments.luau [-v]` (a few seconds) checks `src/shared/Tournaments.lua` (the five events, their
calendar, rules, prizes, belt designs), `src/server/Tourney.lua` and its hooks in Career / World on real careers: the
calendar (starts, entry windows), entry rules by career level and division (the invitational by ranking), bracket
generation (8 of the division, seeded 1v8 4v5 3v6 2v7), every round through `Career.ApplyResult` (the AI side by
`World.AIBout` without draws, `recovery` days between rounds instead of a suspension, the wear carried into the next
round, a draw through on punches landed, a loss / a withdrawal / a concussion ending the run), prizes, fame, ranking
points and the belt (worn in ring walks), AI editions (`Tourney.Tick`: holders, `b.tbelts`, the log), saves (an old
save without `profile.tourney`, the JSON round trip, corrupt pieces), the cutscene spec and every `BeltModel` design.
`test_ui_layout` lays out `hub_tournaments`, `hub_bracket`, `hub_bracket_card`, `hub_tourney_belts` and `ceremony`.

## Places and their lockups: Shared.Signage

`src/shared/Signage.lua` lists every place (the gym, Main Street's shops by their CityMap sign text, the fight venues
by kind, the places you travel to) with its wordmark, sub line, icon (the `places` cells of the icon sheets:
burger, cup, washer, needle, bread, ticket, pizza, building, columns, bed, pump, arena, stadium, mountain) and colours.
`Signage.Board(part, face, loc, opts)` puts the lockup on a part's face (the pixel density follows the face's height:
the engine draws text at 100 px at most, so a tall board at 40 px per stud kept its name small), `Signage.Badge` /
`UI.LocationBadge` is the same lockup in the menus (the Life tab's shop guide and trips, the fight offers' venue, the
tournament cards, the city counters' header, the result window, the debut offer). `test_ui_layout` lays out
`hub_life`, `city_store` and `fight_busy` (the fight HUD with the step card, the combo counter, the momentum strip
and the live score up at once); the FightIntel pieces are in the HUD's keep-apart list.

```sh
lune run tools/sim/v9_ceremony.luau [--out DIR] [--times 1.3,2.9,4.3,5.0,6.6,9.4]
/opt/bpyenv/bin/python tools/sim/v9_ceremony_render.py DIR previews/final/v9/tournaments [--samples N] [--only belts,story]
```

`v9_ceremony.luau` (v9_referee's harness: the fake rig, Builder.Cosmetics, the real Animator) exports every belt design
(display and worn) and the storyboard frames of the cutscene: FightEngine's timeline replayed with AnimCeremony's poses,
the belt placed as BoxerClient.Ceremony places it, the camera from `Tournaments.CeremonyShot`. The render draws them in a
stand-in arena with the frame's confetti / streamers / pyro / spotlights and the cutscene's 2D layer (letterbox, banner,
SKIP) composited.

## The body in Studio: test_charphysics, test_walkstable

What the Humanoid's physics and Roblox's own animation do to a walking boxer, which the clips above do not model.

```sh
lune run tools/sim/test_charphysics.luau     # under a second
lune run tools/sim/test_walkstable.luau      # ~15 s; the clips land in tools/sim/out/walkstable
lune run tools/sim/v9_anim.luau --tiers 3 --clips walk,snapturn --no-mesh --nopen --timing steady,studio,hz240,spike
```

- `test_charphysics.luau`: `Builder.Cosmetics` on the fake rig at tiers 1 / 3 / 5, heights 60 / 70 / 84 in, both genders:
  every part the Builder welds on (gear, attire, headgear / caps, face, hair, belts, sweat) is Massless and never
  collides / queries / touches; the body parts keep their mass and the limbs never collide; the centre of mass of the
  R15 parts (box volumes x density) sits on the root's axis; `Humanoid.HipHeight` is exactly the tier legs' length
  (root -> hip -> knee -> ankle -> sole) and is put back after the engine's rescale (ApplyDescription) even when no
  tier changed.
- `v9_anim.luau --timing MODE,...`: the walk / jog / run clips under a frame timing - `steady` (60 Hz, the root gliding
  exactly dt x v), `studio` (frame times wandering +-15 % while the physics advances in whole 240 Hz steps, as a Studio
  client), `wander` (the same frame times with exact travel), `hz240`, `spike` (0.1 s / 0.25 s hitches) - with the
  frame-to-frame roughness of the trunk, head and pelvis in the metrics (`jitter`), and a fake Animate script / Animator
  on the walker (`animate`). `--nopen` skips the slow mesh interpenetration pass. The `snapturn` scripted clip is a
  player on WASD: the Humanoid's AutoRotate snapping the root a quarter turn at 18 rad/s and a reversal, with the trunk
  roll, head yaw, chest / pelvis twist and pelvis lag in the metrics.
- `test_walkstable.luau`: runs those through the real Animator and checks: no NaN; head / pelvis sway small and the
  roughness within caps and near the steady walk's at every timing; the Animate script switched off, every track it
  starts stopped, `ProcAnim` on the model, back on while the rig is released (climbing) and off again on the ground;
  snap turns without a bank, with the head's lead, the twist and the pelvis' lag bounded; a held curve still banked, the
  head still leading a turn in place, a start's forward lean bounded.

## Knockdowns and knockouts on the canvas: v10_ko_render

```sh
lune run tools/sim/v9_anim.luau --tiers 3 --clips fight --only kd_back,kd_flash,kd_ropes,kd_corner,ko_oneshot_back,ko_crumple_side,ko_crumple_back,ko_delayed_face,ko_ropes,ko_corner --out DIR
/opt/bpyenv/bin/python tools/sim/v10_ko_render.py DIR previews/final/v10/ko [--only id,id] [--times 0,0.2,0.5,1,2] [--views side,high] [--samples N] [--tag v10]
```

The fall of every knockdown / knockout scenario at fixed times after the knockdown (`kdAt` in the clip's JSON: the
frame Guard went "down"), one sheet per view (`high`: a raised side view, the body against the floor marks), and a
ground report (`<tag>_<id>_ground.json`, also printed): per picked frame the lowest vertex of the body meshes against
the canvas (Y = 0: negative = sunk, positive = floating), the pelvis and head heights, and the pelvis' travel per
recorded frame once he is down (the slide). The v10 scenarios: `kd_flash` (the flash knockdown), `kd_ropes` /
`kd_corner` / `ko_ropes` / `ko_corner` (the server's walk into the ropes / the corner as a root move, DownDist as
FightMotion.RopeTravel sets it). AnimDown v10: the canvas is measured by a ray every frame, every joint within human
range (AnimDown.LIMITS), nothing airborne (the final Transforms pulled onto the canvas in footLock), a landing slide
and a settle; the physics side (the root held, the limbs released to ball sockets after an out-cold KO) is
src/server/Ragdoll.lua + src/client/modules/Ragdoll.lua and can only be verified in Studio (no physics here).

## The crowd and the stands: crowd_scene, crowd_render, test_crowd

```sh
lune run tools/sim/crowd_scene.luau [--out DIR] [--level 1|2|3] [--only Stadium,Arena]
/opt/bpyenv/bin/python tools/sim/crowd_render.py DIR/scene.json OUT_DIR [--only view,view] [--samples N]
lune run tools/sim/test_crowd.luau [--keep]      # ~25 s
```

- `crowd_scene.luau` (world_scene's stub layer) runs `Venues.New` per venue at a 0.41 house and a packed world-title
  night (`Crowd.Apply`, the supporters' signs and banners), then the client's `CrowdFX` on the clone (the printed rows
  and the bowl drawn, every rig posed; a `_react` root 0.9 s into a knockdown wave). Dumps as world_scene (GUI items
  carry `rot` / `rt`), `crowd_counts.json` (`Crowd.Counts` per root), `cameras[root]` = the ring centre.
- `crowd_render.py` renders through world_render with the drawn faces (tools/body uploads), rotated frames and
  RichText rows: `previews/final/v10/crowd`.
- `test_crowd.luau`: the fill (fewer fans at the low house, the front rows first, standing room only when packed),
  the rigs (cheap, never physical, a head and two arms each, laps / legs, hats on some), the variety (builds, skin
  tones, several drawn faces, clothing prints), the stands (rake, stair lights, VIP boxes, media box, camera
  platforms, sponsor boards, printed rows, the bowl), the keep-outs (ring, lanes, stool corners, the venue's floor
  cameras), the part caps per venue, and the reaction (rigs up and arms up near the ring, printed arms swung, the
  wave outward, `Crowd.React`'s attribute).

## Spacing: test_spacing, v10_postfight_scene

```sh
lune run tools/sim/test_spacing.luau [-v]                 # ~8 s
lune run tools/sim/v10_postfight_scene.luau [--out DIR] [--frames heavy,mixed,down] [--times 1.2,4.0]
/opt/bpyenv/bin/python tools/sim/v10_postfight_render.py DIR previews/final/v10/postfight_scene [--samples N]
```

- `test_spacing.luau`: whole fights for every body-frame pairing (Lean .. Heavyweight Build, AI vs AI and bots) with a
  stub referee (`spec.ref`): the root-to-root distance never drops below the pair's `Fight:MinSep` (the clinch
  distance while they hold) minus one 20 Hz sim tick of walking; `MinSep` / `ClinchSep` / `ClinchRange` grow with the
  frames; `KeepOut` and `BodyMass`; the referee never inside a standing man's body and inside `MinSep` only on a few
  ticks (the fighters pass through him and cover 12 studs/s), inside 4.5 studs only for a reason (a clinch held
  `REF.clinchHold`, the count, the bell), out on his orbit for most of the open play; `PostFight.Layout` from the frames.
- `v10_postfight_scene.luau` (v9_ceremony's harness: the fake rig, Builder.Cosmetics, the real Animator): two
  heavyweights and a referee at `PostFight.Layout`'s places from `HitGeometry.Frame` off the built rigs, the pf* poses
  before and after the hand goes up; per frame the smallest body gaps and the deepest mesh-box overlap. The render:
  top view and the hard camera (Ceremony.resultShot) per frame, plus the sheet `postfight_scene.jpg`.
