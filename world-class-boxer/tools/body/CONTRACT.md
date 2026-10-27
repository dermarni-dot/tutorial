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
* THE SURFACE: the lofts are 52 x 56 (UpperTorso), 14 x 40, 24 x 40 (upper arm, an 8-ring shoulder cap: a round delt), 16 x 28, 22 x 32 (thigh), 18 x 28,
  12 x 22 (foot), 8 x 20 (hand) rings x segments (every vertex still a sample of the 4x refined loft that carries the
  muscles and the normals): 24,432 triangles per body in the full set (v14: 29,744, see Muscle definition) (UpperTorso 6,272, UpperArm 2,720; the 10k per-mesh limit and
  the ~40k body budget hold), the hem row blend 2.45..2.90 so the band row is no crease; the lite set stays the v9 one.
  Sheets: `bare_t<N>_<view>.png`, `arms_t<N>.png` (two strips: straight in a front 3/4, bent 110 from the side),
  `heads_necks.png` (close-up strips of every frame's head on its neck, front and side, tiers 1 and 5;
  `build_body.py --sheets closeups` renders only these two), `height_lineup_6ft.png` (the five frames at 72 in with the crown line: `render_frames.py --headline`).

### Muscle definition (v14)

* Geometry only (the body MeshParts carry no SurfaceAppearance): the definition is the lobe field of each loft, sampled
  by the low-res vertices and their refined normals. Two rules the lobes keep: a groove's half-width is at least ~1.2x
  the loft's segment spacing (UpperTorso 76 segments ~ 4.7 deg: grooves >= 6 deg; the limbs 36..40 ~ 9..10 deg:
  grooves 11 deg), or only one vertex dips and it shades flat; and a diagonal (drifted) lobe is never narrow (>= 10
  deg), or it aliases into a dashed staircase across the columns. Azimuth is not width: the torso's front is flat, so
  phi lands at x = af tan(phi) (the rectus spans ~+-42 deg, the pecs ~0..65).
* The forms, every separation a tier-grown groove (the m / d terms: none at tier 1, the frame's `defin` gain on the d
  term: Lean 1.35, Muscular 1.25, Athletic 1, Power 0.75, Heavyweight 0.35): the pec plate with a steep lower edge,
  the pec line and its outer edge rising to the armpit, the clavicular head, the sternum split, the deltopectoral
  line; the rectus as one plate cut into a six-pack by the linea alba, three tendinous inscriptions and the
  semilunaris, the V-lines into the trunks (grooves only under the band), serratus slips, the oblique and the flank
  edge; on the back the lat mass, sweep and edge (the V), erector columns either side of the spine groove, the traps'
  diamond (three stacked lobes narrowing down the spine), infraspinatus / teres and their line; the deltoid's three
  heads rising to the top ring (no corner under the shoulder dome) with grooves between them, the insertion V and its
  tuck under the pec; the biceps peak and the biceps / brachialis groove, the triceps' long / lateral heads with the
  horseshoe round the tendon plate; the brachioradialis ridge and the flexor / extensor lines; the forearm's top 3 %
  inside the upper arm's lower end (FORE_TAPER: no step at a straight elbow); the VMO teardrop and its edge, the ITB
  line, the hamstrings' split, the back of the knee; the calf's two gastrocnemius heads with crisp lower edges over
  the soleus flare, the Achilles' hollows, the tibialis / shin line.
* Resolution where the definition needs it: UpperTorso 56 x 76 (9,120 tris), LowerArm 18 x 36, UpperLeg 22 x 40,
  LowerLeg 18 x 36: 29,744 triangles per body (the 10k per-mesh limit holds). Gear: the trunks / boots are not
  refitted; nothing rises under the band, and the calf's added mass stays inside the boot shaft's 0.04 clearance.
* Close-ups: `build_body.py --sheets muscles --tiers 1,3,5 --frames lean,muscular,power --muscle-tag before|after`
  (`MUSCLE_SHEETS`: chest + delts front, back, the right arm side / back, the legs front / back), `compose_muscles()`
  -> `previews/final/v10/bodies/muscles/compare_<sheet>_t5.png` (before over after) and `tiers_<sheet>.png`.

### Smoothing: no muscle pokes out (v15)

* Every loft's lobe field is shaped before it is added to the base section (`shape_lobes`, in `_grid`): each lobe is
  at least one low-res segment wide (half-width) and 1.5 rings long each side (`_widen`); the field gets TAUBIN = 2
  lambda / mu Laplacian passes on the refined grid (periodic round the ring); the raised part saturates softly,
  d' = dmax tanh(d / dmax) with dmax = SAT_POS (0.13) x the local base radius, the cut part at SAT_NEG (0.07); and
  VOL_BACK (0.6) of what the saturation took off a ring goes back to that whole ring (the girth stays, the lump goes).
  The base silhouette (the frames' sections) is untouched, so frames, joints and heights are unchanged.
* Definition is mostly grooves into a smooth base: the abs are low domes flush with the rib line (the rectus plate
  and pads cut back, soft inscriptions), the pec's underside is a long roll (no shelf), the biceps peak and the calf
  heads are unsharpened bellies, the shoulder girdle lobe starts low, the forearm under the elbow has no bulge-and-pinch
  (FORE_TAPER 1.0 / 0.95 / 1.01 / 1.04 / 0.98), the bony landmarks (kneecap, ankle bones) are broader and lower.
* `build_body.py --check-shape`: builds every frame at tiers 1 / 3 / 5 and reports per part the largest silhouette
  kink (the change of slope, degrees, between neighbouring rings of the four outlines: +-x from the front, +-z from
  the side, over the part's body rings; the caps, the waist-joint taper and the neck left out) and the largest raised
  lobe share of the radius; exit 1 over KINK_MAX (22 deg) / PROTRUDE_MAX (0.14). v14: up to 45 deg / 0.54; v15: 20.8 /
  0.13. Tris unchanged (29,744 per body).

### Skin surface maps (v16)

* What Roblox allows (Roblox-Client-Tracker API dump; Roblox creator-docs `SurfaceAppearance.yaml`,
  `art/modeling/surface-appearance.md`): SurfaceAppearance ColorMap / NormalMap / RoughnessMap / MetalnessMap (and their
  *Content forms) are PluginSecurity to write, "most SurfaceAppearance properties cannot be modified by scripts";
  `Color` and `AlphaMode` are script-writable. `Color` "applies as a multiplier" on the ColorMap ("texel color times
  SurfaceAppearance.Color"; near-white greyscale maps tint best; tinting "does not affect performance" and one map can
  serve many tints); it does not apply to MeshPart.Color. NormalMap: "OpenGL format - Tangent Space" only. Texture
  maps up to 1024 px are the practical maximum (4096 supported for uploads).
* So: the maps are authored by Rojo (`src/shared/BodySurfaceSet.model.json` -> ReplicatedStorage.Shared.BodySurfaceSet
  .T<n>.<Part>; Rojo 7.7 writes them as ColorMapContent / NormalMapContent / RoughnessMapContent) and cloned at run
  time by `BodySurfaces.Attach` (BuilderTiers.swap): the clone is named `BodySkin`, its `Color` = the part's Color and
  follows it (a Color-changed connection), AlphaMode Overlay with an opaque map. Lite (crowd) parts, the hands, the
  feet and the LowerTorso wear none. The skin tone path is the tint; the hands / head keep MeshPart.Color = the same
  skin, and the ColorMap is pure white where nothing is occluded, so the tones match.
* `tools/body/bake_skin.py`: per (surface tier 1-5, part type UpperTorso 1024 px / UpperArm / LowerArm / UpperLeg /
  LowerLeg 512 px) a tangent-space normal map, a greyscale ColorMap (AO + cavity: 1 - 0.32 x darkening) and a
  RoughnessMap (0.60 base, glossier on raised muscle, matte in creases), baked in UV space from the part's loft refined
  8x (the muscle fields, the bony bumps) plus fine detail (skin grain, pec / deltoid striations, forearm / biceps /
  calf veins at tiers 4-5, elbow / knee creases), on the Athletic frame. One set serves every frame (same UVs, the
  grooves at the same (phi, s)); BodySurfaceData.shift: Power Build one tier softer, Heavyweight Build two. Left limbs
  share the right limb's maps (mirrored mesh, same UVs, the tangent sign flips).
* The meshes now carry real per-vertex tangents (`build_body.vertex_tangents`, `write_mesh_tan`: tangent = +u, w so that
  cross(N, T) w points to the image top) instead of hairlib's constant, the frame the bake uses.
* `tools/body/publish_skin.py` uploads the 75 images (Image, the body cache) and writes `BodySurfaceData.lua` (ids,
  sizes, shift, budget) and the model. Budget: one boxer's maps 5.3 MB block-compressed (32 MB raw RGBA), all 25 sets
  26.7 MB (160 MB raw); a crowd costs nothing (lite).
* Previews: `bake_skin.py --no-bake --preview lean,muscular,power --preview-tiers 5 --lineups 1,3,5 --dest ...`
  (Cycles: base colour = skin x ColorMap, the RoughnessMap, a tangent-space normal map node).

### The shoulder junction (v17)

* The UpperTorso owns a shoulder cap per side (`build_body.shoulder_cap`, merged after the loft: `core_n` = the loft's
  vertex count): a 11 x 32 shell about the shoulder pivot covering the arm's dome from the trapezius out over the
  deltoid. Its radius per ray = a smooth envelope (dilated, blurred) of the dome's furthest reach over rest + CAP_POSES (pitch -30..90, abduction -10..60, the
  guard) x 1.015 + 0.004, smooth-maxed into the torso where the torso is near (CAP_SOFT), and toward the rim (from
  u 0.6) drawn in to 0.012 under the nearer of the arm (its closest over the poses) and the torso: the dome turns under
  it, the rim never shows. Height and depth stay inside the loft's box (only X widens); the normals near the rim are
  the surface it tucks under. UVs: the strip v > 0.86 of the UpperTorso map (the loft is squeezed to v 0..0.86), left
  half the right cap, right half the left; bake_skin fills it flat (normal 0,0,1, colour 1, the loft's mean roughness).
* The cap widens the UpperTorso's bounding box (MeshPart Size.X), not its body. BodyAssetData's UpperTorso records
  `core` = the loft's box (no cap; same centre, Y and Z, export asserts it); BuilderTiers sets
  `BodyCoreRatio = core / size` before the swap and, after it, the attribute `BodyCoreSize` (Vector3) = Size x ratio,
  kept current on Size changes. Every reader that means the body's width reads `BodyTiers.CoreSize(part)`
  (BodyCoreSize, else Size): HitGeometry (torso half width, shoulder span), AnimRig utScale, AnimFight clinch, Poser
  grip, HairFX, the officials' collar / towel / text, the surface marks, Ragdoll's UpperTorso collider. The swap also
  scales the part's density by core / box volume (CustomPhysicalProperties) so a Box-fidelity UpperTorso weighs its
  body, not its caps. Size/OriginalSize ratios (BuilderGear, Diag,
  Builder) stay valid (both include the cap); the robe keeps Size (it must cover the cap). The hit boundaries and
  MinSep of every frame pairing are unchanged (test_hitdetect / spacing / aiacts / fightai / frametraits /
  charphysics / gear / npcbuild / referee outputs identical).
* Gear: the referee shirt / coach polo sleeves (a sphere about the pivot + ease) cover every visible cap vertex at
  tiers 1-5; the sports top's straps stay medial of the cap (x 0.75 < 0.80).
* Also: the armpit hollow (s 3.16-3.44, under the widest ring: the core width equals v16's to 0.0005) and the lat's sweep (torso lobes), the coracobrachialis on the arm toward the armpit, the
  forearm's top matched to 0.99 x the upper arm's radius at the elbow in game space.
* `build_body.py --check-shape` also gates the junction: the armpit gap (GAP_MAX 0.06), the elbow ratio (ELBOW_MAX
  0.015), the cap over rest + CAP_POSES: dome poke (the dome's triangles past the cap's interior, CAP_POKE_MAX 0.004),
  rim exposure (a rim vertex outside both the posed arm and the torso, CAP_EXPOSE_MAX 0.010) and, apart, a poke where
  the cap is clamped to the box's top (CAP_CEIL_MAX 0.015: Power Build T5 pitched 90 deg, 0.0115).
* Sheets: `build_body.py --no-export --no-blend --sheets shoulders --tiers 1,5 --muscle-tag after` (front, side, back,
  3/4, guard front / 3/4; Lean, Muscular, Power, Heavyweight), composed into previews/final/v10/bodies/shoulders/.

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
				core = { x, y, z },-- (v17, UpperTorso only, when it differs) the body's box without the shoulder caps
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
