# Muscle-tier body contract

The format shared by the Blender builder (`tools/body/build_body.py`), the uploader
(`tools/body/publish_body.py`) and the game (`src/shared/BodyAssetData.lua`, generated).

## The body

Every boxer is the standard Roblox R15 rig built from a HumanoidDescription (empty body-part ids:
the engine's default body). The server then swaps each of the 14 non-head body parts for a muscle-tier
MeshPart (`Humanoid:ReplaceBodyPartR15`) and gives the head a face texture. The generated organic
bodies and faces (AnatomyBody, AnatomyHead) are retired; the asset hair stays.

- Parts: UpperTorso, LowerTorso, LeftUpperArm, LeftLowerArm, LeftHand, RightUpperArm, RightLowerArm,
  RightHand, LeftUpperLeg, LeftLowerLeg, LeftFoot, RightUpperLeg, RightLowerLeg, RightFoot.
- Tiers 1-5: 1 lean, 2 toned, 3 athletic, 4 muscular, 5 elite. Every tier has the same joint pivots
  for the torso and legs; the arm axis moves out a little per tier (parts.json has every attachment).
- Joints (v9): every limb end that meets a neighbour is a near-sphere about its joint pivot in game space (the hip, knee,
  shoulder, elbow and wrist domes, build_body.JOINT_DOME), so a turning joint turns its dome in place and nothing swings
  out through the neighbour. The shoulder pivot sits on the arm's own axis (x = armAxisX of the tier, y =
  shoulderHeight 4.92), the centre of the upper arm's top dome; the elbow / wrist chain hangs where it did.
  `tools/body/check_joints.py` measures each joint through the Animator's ranges.
- Modelled at the game's proportions (the athletic rig `Builder.Scales` makes today), so the
  description that applies them uses `BodyTypeScale = 0, ProportionScale = 0` and only Height / Width /
  Depth / Head scales for the frame, height and gender. Training never widens the frame: the tiers
  carry the muscle.

## Body frames (v12)

Every `Config.BodyTypes` frame (Lean, Athletic, Muscular, Power Build, Heavyweight Build) has its own family of the 5
tiers x 14 parts (`tools/body/build_body.py` FRAMES, 350 meshes): the silhouette lives in the meshes, not only in the
description's Width / Depth. The shoulder width (the arm axis `arm_x` is where the frame's upper arm rests against the
frame's ribcage: narrow on Lean, wide on Power Build), the ribcage's width and depth, the trapezius slope into a real
neck column (the UpperTorso now ends in the neck under the head instead of a dome), the arm, forearm and calf girths
and the muscle gains (traps, delts, lats, forearms per frame; the heavyweight's softer layer) all differ per frame; the
muscles are smooth lobe fields over each loft's (height, azimuth) plane that overlap and sum (the delt wraps over the
biceps / triceps, the pecs run into the front delt, the lats widen into the armpit, the forearm mass sits toward the
elbow) instead of ellipsoid bumps. The pivots, the domes (now sized from each frame's own section so they stay spheres
about the pivots) and the elbow / wrist / hip / knee / ankle heights are unchanged; the arm axis is per frame and tier
(`frames[id].tiers[n].armAxisX`).

* Second pass: every frame also has its own SKELETON (`FRAMES[id].skel`, `part_extra`): limb lengths (torso, upper /
  lower leg, upper arm / forearm), the lower body's width and depth (pelvis, thighs, calves and feet together), the
  arms' girth and the hands' size, applied as an extra per-part scale about each part's joint when the prototype is
  mapped into game space, so the pivots differ per frame (Lean stands ~6.45 studs with longer legs, Power Build ~6.0 on
  short thick legs). `frames[id].unit` carries the frame's joints / hipHeight / shoulderHeight (Diag compares against
  it, `BodyTiers.Unit(frame)`); `frames[id].gearScale[<part base>]` = those factors, and `BuilderGear` multiplies a
  piece's ratio by its part's gear scale (the frame's part IS the Athletic part scaled by them wherever the gear
  touches: the trunks, gloves, wraps and boots fit without a refit; `BodyTiers.GearScale(frame, base)`). The torso
  sections carry a fat layer (belly, love handles, a soft neck) that shrinks with the tier on the heavyweight, rib /
  sternum lines on the lean frame, a built chest / lats at tier 1 on the naturally built frames, and a rounder
  ribcage tapering to the waist on all of them. Arms: a biceps / triceps belly tapering to the elbow and a forearm
  tapering from the flexor mass to the wrist are in the base sections (every tier), the shoulder dome is sized with
  the deltoid cap (`dome_r(..., lobes)`), the hands are thicker and curled.
* The Athletic frame is the DEFAULT FAMILY: `BodyAssetData.tiers` (as before, `tools/body/out/tier<N>`), with the lite
  set and the gear fit. The other four are `BodyAssetData.frames[<id>] = { key, tiers = { [1..5] = { parts, fit, tris,
  armAxisX } } }` from `tools/body/out/frames/<key>/tier<N>` (keys lean, muscular, power, heavy).
* The gear is fitted on the Athletic family (build_gear.py): wherever the gear touches - under the trunks' band and
  seat (the LowerTorso, the UpperTorso's hem rows s <= 2.45), the thighs under the shorts legs, the wrist, the ankle,
  the hands and the feet - every frame's part is the Athletic section scaled by the frame's gear scale, and BuilderGear
  scales the piece the same way. The description's Width / Depth (Config.BodyTypes) is the fine-tune on top. Not
  refitted per frame: the women's sports top and the officials' clothes on the UpperTorso (scaled by the UpperTorso's
  gear scale only; a bigger frame's chest may show through a tight top).
* The lite set (the v9 meshes) stays one per tier, the default family's: a crowd NPC of any frame at the low detail
  level wears it (`BodyTiers.PartEntry(..., lite, frame)` falls back to it).
* Game side: `BodyTiers.Tiers()` returns `tiers.frame` (BodyTiers.FrameOf: the frame id, else the BodyTypes entry with
  the potential Builder passes); `BuilderTiers.Apply` swaps a part whose tier, frame family or detail set changed (the
  parts carry `BodyFrame`, the model `BodyFrame`); `BuilderTiers.Preload` loads the default family and the lite set
  first, then the other frames. An unknown frame or one without meshes wears the default family.
* Previews: `tools/body/frames_anim.luau` (v9_anim's rest clip per frame, generated from it) and
  `tools/body/render_frames.py` -> `previews/final/v10/bodies/`; `check_joints.py --frames all`.

### The height, the head and the neck (v13)

* THE FRAME CHANGES THE BUILD, NOT THE HEIGHT. Every frame's unit (`frames[id].unit`, `BodyTiers.Unit(frame)`) carries
  its own `neckHeight`, `head` (studs) / `headScale` and `standingHeight = neckHeight + head`, and `Builder.Scales`
  normalises the description's HeightScale per frame: a boxer of `inches` is built `Builder.StandingHeight(inches)` =
  the Athletic unit's standingHeight (6.2161) x inches / 70 studs tall on every frame, with
  `HeightScale = (standing - 1.2 x HeadScale) / unit[frame].neckHeight` (the head sits on the Neck pivot and is not
  height-scaled). The frames' skeletons (`FRAMES[id].skel`) are solved so the Humanoid's HipHeight (HeightScale x (the
  root pivot's unit height - 1)) is the Athletic's within 0.3 % too; the eye line follows (the head's 0.1 x size).
  `tools/sim/test_frameheight.luau` builds every frame at 5'6" / 6'0" / 6'6" and checks all three within 1 %.
  Width / Depth: half of Config.BodyTypes' values (`Builder.FRAME_WIDTH_SHARE`); the mesh families carry the build.
* THE HEAD: `FRAMES[id].head` = `Builder.FRAME_PROPORTIONS[id].head` (Lean 0.79, Athletic 0.82, Muscular 0.835,
  Power Build 0.85, Heavyweight Build 0.865; the game's HeadScale is that x 0.942, the head 1.2 x the HeadScale:
  0.893 .. 0.978 studs). The neck column (`FRAMES[id].neck` at `neck_s`: the trapezius slope row, the column, its top)
  is modelled under that head: its width at the head's base is 0.68 (Lean) .. 0.85 (Power / Heavyweight) of the head,
  and it runs `NECK_TOP` = 0.065 game studs up INTO the head (a 0.03 cap on top), so the classic head's rounded underside
  closes over the neck's top ring from outside: no ledge where a thick neck met the head's flat base, no gap under a
  thin one. The SCM cords, the throat hollow and larynx, the collarbones and the nape's groove are lobes on the neck rows.
* The shoulder-to-neck roll (second v13 pass): the width / depth start rolling into the trapezius slope `ROLL` = 0.08
  prototype under the shoulder-top row, blended in with a smoothstep from a two-knot start that carries the chest's
  slope, and the neck rows are never deeper than the chest where the roll starts (monotone), so there is no crisp line
  across the chest at the shoulder top and no dip-and-rise crease across the Power / Heavyweight upper back; the neck's
  exponent is never squarer than the chest's. The collarbones are diagonal (rising outward from the sternum notch), the
  SCM cords run diagonally from the notch up behind the jaw (fixed sizes, not scaled by the trap gain), the upper traps
  are one broad slope from the neck down to the shoulders (peak at the shoulder-top row, not a hump behind the neck).
  Power Build's forearm no longer flares under the elbow (fore 1.04 / 1.08 / 1.06 / 1.02, fore gain 1.35, trap 1.7).
  On the back the shoulder blades' inner edges and spines are diagonal (no rectangular plate between the blades) and
  the upper traps' onsets are staggered (no fold across the upper back).
* THE SURFACE: the lofts are 52 x 56 (UpperTorso), 14 x 40, 20 x 32 (upper arm), 16 x 28, 22 x 32 (thigh), 18 x 28,
  12 x 22 (foot), 8 x 20 (hand) rings x segments (every vertex still a sample of the 4x refined loft that carries the
  muscles and the normals): 22,320 triangles per body in the full set (UpperTorso 6,272; the 10k per-mesh limit and
  the ~40k body budget hold), the hem row blend 2.45..2.90 so the band row is no crease; the lite set stays the v9 one.
  Sheets: `bare_t<N>_<view>.png`, `arms_t<N>.png` (two strips: straight in a front 3/4, bent 110 from the side),
  `heads_necks.png` (close-up strips of every frame's head on its neck, front and side, tiers 1 and 5;
  `build_body.py --sheets closeups` renders only these two), `height_lineup_6ft.png` (the five frames at 72 in with the crown line: `render_frames.py --headline`).

## BodyAssetData.lua (generated)

```lua
return {
	version = 1,
	unit = { ... },                -- the unscaled rig the meshes are modelled for (part sizes, root height)
	tiers = {
		[1] = { parts = {
			UpperTorso = {
				mesh = 0,          -- Mesh asset id
				size = { x, y, z },-- the mesh's bounding box = the MeshPart's unscaled Size (OriginalSize)
				attachments = { NeckRigAttachment = { x, y, z }, WaistRigAttachment = {...}, ... },
				                   -- part-space positions of every R15 RigAttachment (and Grip on hands)
			},
			...
		} },
		...
	},
	faces = {                      -- classic-style faces, Image assets (decal on the head's front)
		{ key = "smile", name = "Smile", id = 0 },
		...
	},
	expressions = { neutral = nil, hurt = "hurt", dazed = "dazed", ko = "ko", effort = "grit", happy = "grin", ... },
	                               -- fight / gym moods -> face key (nil = the boxer's own chosen face)
}
```

An id of 0 means "not uploaded": the game then keeps the default body part / the default smile.

The drawn Boxer face STYLES (`wcb_neutral`, `wcb_focused`, `wcb_smirk`, `wcb_grit`; BodyTiers.STYLE_KEYS) are
`faces` entries too (the user's 1254 px pack, registered and copied by `faces.py --pack DIR [--pack-only]`, ids
in `tools/body/wcb_faces_manifest.json`), but never a `face.key`: they are `look.face.style` values (default
`"built"`), the head's front Decal in place of the built eyes, brows, nose and lips, swapped by mood with
BodyTiers.STYLE_MOODS. A style whose id is 0 is not offered and reads as built.

As generated, besides the fields above: `tiers[n]` also has `name`, `tris` and `fit` (gear-fit girths /
widths / depths in unscaled studs at fixed heights: chest, waist, hips, upperArm, forearm, wrist, thigh, knee,
calf, ankle, plus shoulderSpan and chestDepth); each part has `nt`; each face has `creator` (true = offered in
the creator, false = a mood face only); `defaultFace = "smile"`. `unit` holds `description` (the scales that
reproduce it: BodyTypeScale 0, ProportionScale 0, Height / Width / Depth 1, HeadScale 0.7724), `partScale` (the
per-part factors applied to the Classic block), `rigBox` (the Classic R15 boxes at those factors), `joints` (rest
space, feet on Y = 0, right side; the left mirrors X), `armAxisX` per tier, `head`, `rootHeight`, `hipHeight`,
`shoulderHeight`, `neckHeight`, `wristHeight`, `standingHeight`. Attachment positions carry no rotation: every
one is axis-aligned with its part, except the Grip, which takes R15's usual orientation
(CFrame.Angles(-math.pi / 2, 0, 0)).

## The gear (GearAssetData.lua, generated)

`tools/body/build_gear.py` models the boxing gear on the tier bodies (rest space) and writes
`tools/body/out/gear/{tier<N>,shared}/<Piece>.mesh` + `gear.json`; `tools/body/publish_gear.py` uploads them (Mesh,
same hash cache `uploaded.json`) and writes `src/shared/GearAssetData.lua`:

```lua
return {
	version = 1,
	slots = { "trunks", "trim", "gloves", "gloveTrim", "wraps", "wraps2", "shoes", "soles", "laces", "socks", "top", "topTrim" },
	sets = { trunks = { Classic = {...}, Striped = {...}, Pro = {...}, Long = {...} }, shoes = { ["High-Top"] = {...},
	         ["Low-Top"] = {...} }, gloves = { Gloves = {...} }, wraps = { Wraps = {...} }, top = { Top = {...} } },
	                               -- piece names; a sided name (Glove) stands for Glove_L and Glove_R
	pieces = { Glove_R = { part = "RightHand", slot = "gloves", group = "gloves" }, ... },  -- 40 pieces (+ tierOf)
	tiers = { { Glove_R = { mesh = id, offset = { x, y, z }, size = { x, y, z }, nt = tris }, ... }, ... },  -- [1..5]
}
```

`tiers[n][piece]` is the piece for a body part showing tier n (the game reads the part's `BodyTier`). A piece with
`pieces[piece].tierOf = { part, ... }` (the trunks' Waistband and TrunkSeat: LowerTorso, UpperTorso and both UpperLegs)
is the one of the HIGHEST tier among those parts, modelled round those parts of that tier and every tier under it; its
offset is in the LowerTorso space of that tier, moved onto the LowerTorso the model shows by the difference of the two
tiers' RootRigAttachment positions (the LowerTorso's rest frame is the same at every tier). The trunks are cut round the
walk (thigh swing -14..+16 deg for the seat, the leg tops hidden through -28..+36) and the punches' waist turn
(`tools/body/check_gear.py`). `offset` = the
piece's bbox centre in that part's space (rest pose, unscaled), `size` = the mesh bbox; the game sizes a clone to
`size x ratio` and welds it at `part.CFrame * CFrame.new(offset x ratio)` (ratio = the part's Size / OriginalSize).
The glove, wrap, boot foot, sole and instep laces are one mesh at every tier (the hand and foot do not change), with
a per-tier offset. An id of 0 = not uploaded: `BuilderGear.Resolve` returns nil and BuilderBody builds the
part-built gear for that group.

The engine's side of this contract (what `tools/sim/test_gear.luau`'s "engine semantics" section pins down): the
MeshPart `CreateMeshPartAsync` returns has the mesh's bounding box as its Size, the mesh is drawn recentred on that box
and scaled to the part's Size per axis (so every `.mesh` file is written centred on its box, and `size` must be that
box: BuilderGear warns in the Output when the uploaded mesh's box is not the manifest's); `ReplaceBodyPartR15` scales the
new part from its OriginalSize by the humanoid's scale values, in the call or in the engine's own pass, re-aims the
joints and makes an OriginalSize for a part without one, and BuilderTiers' scale-once leaves nothing for that pass to
change; a later ApplyDescription rescales the body parts under the gear and the next Cosmetics rebuilds it (the cache
key carries the parts' sizes). In Studio: the Attire folder's attributes say per group `mesh` or `blocks: <reason>`, and
`BuilderGear.Audit(model, true)` prints every piece against the manifest.

## Detail sets (v10)

The body and the mesh gear come in two sets per tier, picked by the boxer's detail level (`Config.Detail[level].meshes`):
`"full"` (full and medium: players, the fight opponent, gym NPCs, officials) wears the v10 detailed meshes (11,472 body
triangles: the muscle forms, knuckles, ankle bones; ~12.6-13.4k for a whole outfit of gear: laces, eyelets, seams, the
glove's padding contours, piping, leg slits), `"lite"` (low: the crowd NPCs) the v9 meshes they replaced (6,768 body
triangles, <= 5,960 for an outfit), so a crowd costs what it did. The instances are the same either way.

* `BodyAssetData.tiers[n].parts[<Part>].lite = { mesh, size, attachments, nt }` (its own bbox and part-space
  attachments: the joint pivots are the same rest-space points in both sets) and `tiers[n].liteTris`.
* `GearAssetData.tiers[n][<piece>].lite = { mesh, offset, size, nt }`: the v9 piece, fitted to the v9 body.
* The lite meshes are kept in `tools/body/out/lite/` (`tier<N>/`, `gear/`, `body_tiers.json`); publish_body.py /
  publish_gear.py add them to the manifests (their hashes are in the cache: same ids, nothing uploaded again).
* `BodyTiers.PartEntry(tier, name, d, lite)` / `BuilderGear.Entry(tier, name, d, lite)` return the lite entry (the full
  one when there is none, `entry.lite` says which); `BuilderTiers.Apply(model, tiers, scale, lite)` swaps every part to
  its set (a part of the right tier in the other set is swapped too; attributes `BodyMesh`, `BodyLite`); the gear
  follows the body part it welds to (`BodyLite`), so a lite body always wears the lite gear fitted to it.
* The lite set is rebuilt with `tools/body/lite/build_body_v9.py` and `tools/body/lite/build_gear_v9.py` (the v9
  builders of 1536e0f^, which reproduce the published v9 meshes byte for byte when unslimmed), then
  `build_official.py --only lite`. They import the slim pass from `build_body.py`, so both sets carry the same shape.
* `tools/body/torso_surf.py --write` regenerates BuilderBody's TORSO_SURF (the marks lying on the torso) from the
  detailed torsos.

## The officials' clothes (v10, group "official")

`tools/body/build_official.py` models the ring officials' clothes in build_gear.py's conventions and record format,
both detail sets: `out/gear/{tier<N>,shared}/Off*.mesh` + `out/gear/official.json` (on the v10 bodies) and
`out/lite/gear/...` + `out/lite/gear/official.json` (on the v9 lite bodies). `publish_gear.py` merges official.json
into GearAssetData (more pieces, slots `shirt shirtTrim buttons badge bowtie trousers belt buckle dressShoes
dressSoles dressLaces towel`, and `sets.official = { Referee = {...}, Coach = {...} }`).

* Shirt (`OffShirt`, collar, placket + buttons, pocket, badge, bow tie; the coach: `OffPolo` + buttons, `OffTowel`) on
  the UpperTorso; short sleeves (`OffSleeve`, `OffSleeveHem`) on the UpperArms, their tops a sphere about the shoulder
  pivot; trousers: `OffWaist` / `OffBelt` / `OffBuckle` on the LowerTorso (tierOf LowerTorso, UpperTorso, both
  UpperLegs, like the trunks' band), `OffThigh` on the UpperLegs (closed in the seat through the walk, ending in a knee
  sphere of one radius for every tier), `OffShin` on the LowerLegs (its top a smaller sphere inside it, the hem over the
  shoe); `OffShoe` / `OffSole` / `OffLaces` on the feet (shared over tiers).
* BuilderBody builds the set for the official's outfit (`referee` -> Referee, `cornerman` -> Coach) and paints the slots
  from `opts.officialColors` (`src/shared/Officials.lua`: the venue's shirt, white for a title fight); with any id 0 or a
  failed load it keeps the old part-built outfit.

## The slim pass (v11)

`build_body.py` SLIM / BULK / ARM_DX (shared by the lite builders): every limb and torso cross-section is narrowed along
its bone (the waist and mid limbs most, the joint ends less, 1 at the wrist and ankle so the shared hands, feet, gloves
and boots are unchanged), more with the tier's mass; the muscle bells' mass term is cut to BULK = 0.82 and the definition
terms stay. The limb domes shrink with their sections (near-spheres about the same pivots). The torso and leg pivots,
the shoulder height and the elbow / wrist heights do not move; the arm axis (`unit.armAxisX`, ARM_DX) comes in 0.085
(tier 1) to 0.13 (tier 5) so the upper arm still rests against the slimmer torso. Girths before / after:
`tiers[n].fit`. Gear and officials' clothes are rebuilt on the slim bodies (build_gear.py, lite/build_gear_v9.py,
build_official.py) and BuilderBody's TORSO_SURF regenerated (torso_surf.py --write).
