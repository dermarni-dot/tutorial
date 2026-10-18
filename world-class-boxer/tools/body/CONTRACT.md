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
- Modelled at the game's proportions (the athletic rig `Builder.Scales` makes today), so the
  description that applies them uses `BodyTypeScale = 0, ProportionScale = 0` and only Height / Width /
  Depth / Head scales for the frame, height and gender. Training never widens the frame: the tiers
  carry the muscle.

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
	pieces = { Glove_R = { part = "RightHand", slot = "gloves", group = "gloves" }, ... },  -- 40 pieces
	tiers = { { Glove_R = { mesh = id, offset = { x, y, z }, size = { x, y, z }, nt = tris }, ... }, ... },  -- [1..5]
}
```

`tiers[n][piece]` is the piece for a body part showing tier n (the game reads the part's `BodyTier`). `offset` = the
piece's bbox centre in that part's space (rest pose, unscaled), `size` = the mesh bbox; the game sizes a clone to
`size x ratio` and welds it at `part.CFrame * CFrame.new(offset x ratio)` (ratio = the part's Size / OriginalSize).
The glove, wrap, boot foot, sole and instep laces are one mesh at every tier (the hand and foot do not change), with
a per-tier offset. An id of 0 = not uploaded: `BuilderGear.Resolve` returns nil and BuilderBody builds the
part-built gear for that group.
