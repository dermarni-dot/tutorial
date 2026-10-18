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
