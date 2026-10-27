"""Writes tools/body/frames_anim.luau from tools/sim/v9_anim.luau: the same host, fake rig, Builder.Cosmetics and export,
with the rest clip made frame-aware (--frames "Lean,Power Build": one boxer per (frame, tier); the body parts' mesh
files resolved through the part's BodyFrame family, tools/body/out/frames/<key>/tier<N>) and the sim modules required
from ../sim. Re-run after v9_anim.luau changes:

    python3 tools/body/make_frames_anim.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "sim", "v9_anim.luau")
DST = os.path.join(HERE, "frames_anim.luau")

EDITS = [
    ('''--!nocheck
-- v9_anim.luau: the REAL client Animator''', '''--!nocheck
-- frames_anim.luau (tools/body): a frame-aware copy of tools/sim/v9_anim.luau's REST clip for the body-frame previews
-- (previews/final/v10/bodies): the same host, fake rig, Builder.Cosmetics and export, with `--frames Lean,Power Build`
-- building one boxer per (frame, tier) and the body parts' mesh files resolved through the frame's family
-- (tools/body/out/frames/<key>/tier<N>). Generated from v9_anim.luau by tools/body/make_frames_anim.py: do not edit.
--
--   lune run tools/body/frames_anim.luau --out DIR --tiers 1,5 --frames "Lean,Athletic,Muscular,Power Build,Heavyweight Build"
--                                       [--body MANIFEST.lua] [--hands gloves|bare] [--clips rest]
--
-- (the original header follows)
-- v9_anim.luau: the REAL client Animator'''),
    ('require("./host")', 'require("../sim/host")'),
    ('require("./assetsim")', 'require("../sim/assetsim")'),
    ('require("./fakeengine")', 'require("../sim/fakeengine")'),
    ('require("./meshv2")', 'require("../sim/meshv2")'),
    ('''local function fileOf(p)
	local id = p:GetAttribute("GearMesh") or p:GetAttribute("BodyMesh")
	local tier = p:GetAttribute("BodyTier")
	if p:GetAttribute("GearMesh") then
		return MESH_FILES[id]
	elseif tier then
		return string.format("%s/out/tier%d/%s.mesh", MESHROOT, tier, p.Name)
	end
	return nil
end
''', '''local function fileOf(p)
	local id = p:GetAttribute("GearMesh") or p:GetAttribute("BodyMesh")
	local tier = p:GetAttribute("BodyTier")
	if p:GetAttribute("GearMesh") then
		return MESH_FILES[id]
	elseif tier then
		-- (the frame's family: BodyFrame on the part; the default family's folder for Athletic / the lite set)
		local fr = p:GetAttribute("BodyFrame")
		local key = (not p:GetAttribute("BodyLite")) and BodyTiers.FrameKey(fr, REAL) or nil
		if key then
			return string.format("%s/out/frames/%s/tier%d/%s.mesh", MESHROOT, key, tier, p.Name)
		end
		return string.format("%s/out/tier%d/%s.mesh", MESHROOT, tier, p.Name)
	end
	return nil
end
'''),
    ('''local function restClip(tier)
	local model = makeBoxer(tier)
''', '''local function restClip(tier, frameId)
	local model = makeBoxer(tier, { frame = frameId })
'''),
    ('''	local out = { clip = "rest", tier = tier, frames = { exportFrame(model, VT) } }
	out.frames[1].root = cfList(model:FindFirstChild("HumanoidRootPart").CFrame)
	local file = string.format("rest_t%d.json", tier)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("rest_t%d", tier), file = file, clip = "rest", tier = tier, n = 1 })
''', '''	local out = { clip = "rest", tier = tier, frame = frameId, height = HEIGHT, frames = { exportFrame(model, VT) } }
	out.frames[1].root = cfList(model:FindFirstChild("HumanoidRootPart").CFrame)
	out.frames[1].bodyFrame = model:GetAttribute("BodyFrame")
	out.frames[1].scales = { model:FindFirstChild("UpperTorso").Size.X, model:FindFirstChild("UpperTorso").Size.Y }
	local fkey = (frameId or "Athletic"):gsub("[^%w]", ""):lower()
	local file = string.format("rest_%s_t%d.json", fkey, tier)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("rest_%s_t%d", fkey, tier), file = file, clip = "rest", tier = tier, frame = frameId,
		bodyFrame = model:GetAttribute("BodyFrame"), n = 1 })
	print(string.format("rest %-18s T%d  body frame %s  scales %.3f", tostring(frameId), tier, tostring(model:GetAttribute("BodyFrame")),
		model:FindFirstChild("UpperTorso").Size.X))
'''),
    ('''for _, tier in ipairs(TIERS) do
	if CLIPS.rest then
		restClip(tier)
	end
''', '''local FRAMES_ARG = {}
for f in (args.frames or "Athletic"):gmatch("[^,]+") do
	table.insert(FRAMES_ARG, f)
end
for _, tier in ipairs(TIERS) do
	if CLIPS.rest then
		for _, fid in ipairs(FRAMES_ARG) do
			restClip(tier, fid)
		end
	end
'''),
    ('local NFRAMES = tonumber(args.frames) or 8', 'local NFRAMES = tonumber(args.nframes) or 8'),
]


def main():
    s = open(SRC).read()
    for a, b in EDITS:
        if s.count(a) != 1:
            raise SystemExit("v9_anim.luau changed: %r found %d times" % (a[:60], s.count(a)))
        s = s.replace(a, b)
    open(DST, "w").write(s)
    print("wrote", DST, len(s), "bytes")


if __name__ == "__main__":
    main()
