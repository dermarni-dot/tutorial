--!nocheck
-- v9_anim.luau: the REAL client Animator (src/client/Animator.client.lua and its Anim* modules) driving complete
-- tier boxers built by the server's Builder.Cosmetics (as v8_scene.luau: the fake R15 rig, the tier swap, the classic
-- head, the mesh gear), on a virtual clock, recorded frame by frame in world space for tools/sim/v9_render.py, plus
-- numbers the eye cannot read off a frame (pelvis sway, thigh / pelvis interpenetration, glove reach).
--
--   lune run tools/sim/v9_anim.luau [--out DIR] [--tiers 1,3,5] [--clips walk,jog,punch] [--frames N]
--                                   [--src DIR] (another commit's src: the "before" set)
--                                   [--timing steady,studio,hz240,spike,rough] [--nopen] [--shiftat S]
-- --timing: the frame timing the walk / jog / run clips run under (test_walkstable.luau): steady = 60 Hz, the root
--   gliding exactly dt x v a frame (the default); studio = a 60 Hz client whose frame times wander +-15 % while the
--   physics advances in whole 240 Hz steps (what Studio does: the root's travel a frame is never dt x v); hz240 = a
--   240 Hz client; wander = the frame times of studio with the physics advancing exactly dt x v (the sensing alone);
--   spike = 60 Hz with a 0.1 s hitch every 47 frames and one 0.25 s hitch; rough = frame times scattered between 1/80
--   and 1/28 s (no period) on 240 Hz physics. The clips' ids carry the
--   mode (walk_t3_studio) and their metrics the per-1/60 s roughness of the trunk and head (jitter). --nopen skips
--   the mesh interpenetration pass (the slow part of a walk clip)
--
-- Clips
--   walk / jog / run: a player character (Players.LocalPlayer.Character) whose HumanoidRootPart glides along -Z at
--     5 / 11 / 16 studs/s on a flat floor (workspace:Raycast hits Y = 0), Humanoid state Running; recorded after a
--     settle, `frames` evenly spaced over one full gait cycle (two steps)
--   shift: the walk at 6.5 studs/s, then Shift - the pace jumps to 16 in one frame at --shiftat (2.5 s); its metrics
--     carry the switch's own summary (shift), the contacts after it and the /wcbdiag 10 Hz sample (diag)
--   strafe / strafe16 / strafering / strafeturn: the body kept facing -Z while he goes sideways, on the diagonals and
--     back, the direction flipping (strafeClip: the town walk, Shift's pace, a Fighter's footwork, and AutoRotate on); its
--     metrics carry each stretch's and each change's numbers (the feet across the pelvis, slide, roll, contacts, the
--     joints' frame-to-frame change). --dump A,B prints its frames between A and B s, --debugrig T [--debugwin S] the feet
--   punch: two "Fighter" models 3.4 studs apart facing each other; jab, cross, lead hook, rear hook, uppercut and a
--     body jab (Act / ActId as FightEngine sends them), recorded at the punch's peak (the frame of the glove's
--     furthest reach) plus a few in-between frames
-- Output: <out>/index.json { clips = [...] }, <out>/<clip>_t<tier>.json { frames = [{ t, meshes, head, parts }] },
-- <out>/metrics.json
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local ltask = require("@lune/task")
local Host = require("./host")
local AssetSim = require("./assetsim")
local FE = require("./fakeengine")
local MeshV2 = require("./meshv2")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local PI = math.pi
local SCRATCH = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad"

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		local k = a[i]
		if k == "--no-regen" or k == "--no-mesh" or k == "--dbgfoot" or k == "--nopen" or k == "--npc" then
			args[k:gsub("^%-%-", "")] = true
			i += 1
		else
			args[k:gsub("^%-%-", "")] = a[i + 1]
			i += 2
		end
	end
end
local OUT = (args.out or (SCRATCH .. "/v9anim")):gsub("/$", "")
local TIERS = {}
for s in (args.tiers or "1,3,5"):gmatch("[^,]+") do
	table.insert(TIERS, tonumber(s))
end
local CLIPS = {}
for s in (args.clips or "walk,jog,punch"):gmatch("[^,]+") do
	CLIPS[s] = true
end
local NFRAMES = tonumber(args.frames) or 8
local NOMESH = args["no-mesh"] == true
local BARE = args.bare ~= nil and args.bare ~= "0" -- hide the gear (the body's own surfaces)
local HANDS = args.hands or "gloves" -- gloves | wraps | bare
-- --height IN: the boxer's height in inches (Looks: 60..84; Builder.Scales clamps the scale to 0.86..1.2); the clip
-- ids carry it (walk_t3_h84)
local HEIGHT = tonumber(args.height)
local HTAG = HEIGHT and ("_h" .. tostring(HEIGHT)) or ""
-- --frame "Power Build": the boxers' body frame (Looks: Lean, Athletic, Muscular, Power Build, Heavyweight Build); the
-- clip ids carry it (walk_t3_powerbuild)
local FRAME = args.frame
local FTAG = FRAME and ("_" .. FRAME:lower():gsub("[^%w]", "")) or ""
-- --joints ac: the rig's joints are AnimationConstraints between the RigAttachments (Workspace.AvatarJointUpgrade: what
-- Studio builds for players and CreateHumanoidModelFromDescription), else Motor6Ds; the clip ids carry "_ac"
local JOINTS_AC = args.joints == "ac"
local JTAG = JOINTS_AC and "_ac" or ""
-- --ignore-writes ac | all: the engine does not apply the Transform written to AnimationConstraints (ac) or to any joint
-- (all) - the limbs stay in the rest pose whatever is written, as in the user's Studio place. The Animator's self-check
-- must notice: ac -> the rig rebuilt on Motor6Ds (then it walks), all -> Roblox's animation (Animate / keyframe tracks)
local IGNORE = args["ignore-writes"]
local IGNORE_AC = IGNORE == "ac" or IGNORE == "all"
local IGNORE_ALL = IGNORE == "all"
if IGNORE then
	JTAG = JTAG .. "_ign" .. IGNORE
end
local NTAG = args.npc ~= nil and "_npc" or ""
HTAG = HTAG .. FTAG .. JTAG .. NTAG

------------------------------------------------------------------------
-- host: fake engine, virtual clock, the asset simulator (Content)
------------------------------------------------------------------------
local root = Host.FindRoot()
-- --meshroot DIR: the folder holding out/tier<N>/ and out/gear/ (default tools/body: a copy of an older build for the
-- "before" set, with that commit's --src)
local MESHROOT = (args.meshroot or (root .. "/tools/body")):gsub("/$", "")
local srcDir = args.src or (root .. "/src")
local MANIFEST = AssetSim.LOCAL_MANIFEST
if not args["no-regen"] then
	AssetSim.EnsureManifest(root, MANIFEST)
end
local E = FE.new()
local sim = AssetSim.new({ root = root, manifest = MANIFEST, newPart = function()
	return E.new("MeshPart")
end })
local VT = 1000 -- the virtual clock (s)
local fakeOs = setmetatable({ clock = function()
	return VT
end }, { __index = os })
local RaycastParams = { new = function()
	return { FilterDescendantsInstances = {} }
end }
local OverlapParams = RaycastParams
local H = Host.new({ root = root, src = srcDir, globals = { Content = sim.Content, Instance = E.Instance, workspace = E.workspace,
	Workspace = E.workspace, os = fakeOs, RaycastParams = RaycastParams, OverlapParams = OverlapParams,
	time = function()
		return VT
	end } })
E.install(H)
H.Service("AssetService")._props = sim.AssetService
AssetSim.UseManifest(H, MANIFEST)

-- the floor: a ray down crossing Y = 0 hits it
local floorPart = E.new("Part", E.workspace)
floorPart.Name = "Floor"
floorPart.Size = Vector3.new(200, 1, 200)
floorPart.CFrame = CFrame.new(0, -0.5, 0)
floorPart.CanCollide = true
floorPart.Anchored = true
E.workspace.Raycast = function(_, origin, dir)
	if origin.Y >= 0 and origin.Y + dir.Y <= 0 and dir.Y < 0 then
		local k = origin.Y / -dir.Y
		return { Position = origin + dir * k, Normal = Vector3.new(0, 1, 0), Instance = floorPart, Material = roblox.Enum.Material.Plastic,
			Distance = (dir * k).Magnitude }
	end
	return nil
end
E.workspace.GetPartBoundsInRadius = function()
	return {}
end
E.workspace.GetPartBoundsInBox = function()
	return {}
end
E.workspace.GetPartsInPart = function()
	return {}
end
E.camera.WorldToViewportPoint = function(_, p)
	return Vector3.new(400, 300, 5), true
end
E.camera.ViewportSize = roblox.Vector2.new(800, 600)
E.camera.FieldOfView = 70

local Looks = H.require("Looks")
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderBody = H.require("BuilderBody")
local BuilderHair = H.require("BuilderHair")
local Builder = H.require("Builder")
local BuilderGear = H.require("BuilderGear")
local Kit = H.require("AnatomyHairKit")
-- --body PATH / --gear PATH: a local manifest (publish_body.py / publish_gear.py --local: fake ids + an .ids.json sidecar
-- mapping each id to its file) instead of src/shared's: the rebuilt meshes before they are uploaded
local REAL = args.body and luau.load(fs.readFile(args.body), { debugName = args.body })() or BodyTiers.Data()
BodyTiers.SetData(REAL)

-- mesh id -> file (tier parts and gear): through tools/body/uploaded.json
local MESH_FILES = {}
do
	local up = root .. "/tools/body/uploaded.json"
	if fs.isFile(up) then
		for _, e in pairs(serde.decode("json", fs.readFile(up))) do
			if type(e.file) == "string" and type(e.id) == "number" then
				MESH_FILES[e.id] = MESHROOT .. "/" .. e.file
			end
		end
	end
end
for _, path in ipairs({ args.body or "", args.gear or "" }) do
	local side = path:gsub("%.lua$", "") .. ".ids.json"
	if path ~= "" and fs.isFile(side) then
		for id, f in pairs(serde.decode("json", fs.readFile(side)).ids or {}) do
			MESH_FILES[tonumber(id)] = f
		end
	end
end
local FACE_FILES = {}
-- (the drawn faces' files carry their revision: faces.json names each key's file, e.g. face_wcb_grit_v2.png)
local FACE_JSON = {}
do
	local fj = root .. "/tools/body/out/faces/faces.json"
	if fs.isFile(fj) then
		for _, e in ipairs(serde.decode("json", fs.readFile(fj)).faces or {}) do
			FACE_JSON[e.key] = e.file
		end
	end
end
for _, f in ipairs(REAL.faces or {}) do
	if f.id and f.id ~= 0 then
		FACE_FILES["rbxassetid://" .. f.id] = root .. "/tools/body/out/faces/" .. (FACE_JSON[f.key] or ("face_" .. f.key .. ".png"))
	end
end
do
	local path = args.gear or (srcDir .. "/shared/GearAssetData.lua")
	BuilderGear.SetData(luau.load(fs.readFile(path), { debugName = path })())
end

------------------------------------------------------------------------
-- the fake R15 rig (v8_scene.luau's)
------------------------------------------------------------------------
local BLOCK = {
	UpperTorso = { size = { 2, 1.6, 1 }, att = { NeckRigAttachment = { 0, 0.8, 0 }, WaistRigAttachment = { 0, -0.8, 0 }, LeftShoulderRigAttachment = { -1, 0.563, 0 }, RightShoulderRigAttachment = { 1, 0.563, 0 } } },
	LowerTorso = { size = { 2, 0.4, 1 }, att = { WaistRigAttachment = { 0, 0.2, 0 }, LeftHipRigAttachment = { -0.5, -0.2, 0 }, RightHipRigAttachment = { 0.5, -0.2, 0 }, RootRigAttachment = { 0, -0.2, 0 } } },
}
for _, side in ipairs({ "Left", "Right" }) do
	local sx = side == "Left" and -1 or 1
	BLOCK[side .. "UpperArm"] = { size = { 1, 1.169, 1 }, att = { [side .. "ShoulderRigAttachment"] = { -0.5 * sx, 0.394, 0 }, [side .. "ElbowRigAttachment"] = { 0, -0.334, 0 } } }
	BLOCK[side .. "LowerArm"] = { size = { 1, 1.052, 1 }, att = { [side .. "ElbowRigAttachment"] = { 0, 0.192, 0 }, [side .. "WristRigAttachment"] = { 0, -0.501, 0 } } }
	BLOCK[side .. "Hand"] = { size = { 1, 0.3, 1 }, att = { [side .. "WristRigAttachment"] = { 0, 0.125, 0 } } }
	BLOCK[side .. "UpperLeg"] = { size = { 1, 1.217, 1 }, att = { [side .. "HipRigAttachment"] = { 0, 0.421, 0 }, [side .. "KneeRigAttachment"] = { 0, -0.408, 0 } } }
	BLOCK[side .. "LowerLeg"] = { size = { 1, 1.193, 1 }, att = { [side .. "KneeRigAttachment"] = { 0, 0.2, 0 }, [side .. "AnkleRigAttachment"] = { 0, -0.547, 0 } } }
	BLOCK[side .. "Foot"] = { size = { 1, 0.3, 1 }, att = { [side .. "AnkleRigAttachment"] = { 0, 0.085, 0 } } }
end
local JOINTS = {
	Root = { "HumanoidRootPart", "LowerTorso" }, Waist = { "LowerTorso", "UpperTorso" }, Neck = { "UpperTorso", "Head" },
	LeftShoulder = { "UpperTorso", "LeftUpperArm" }, RightShoulder = { "UpperTorso", "RightUpperArm" },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm" }, RightElbow = { "RightUpperArm", "RightLowerArm" },
	LeftWrist = { "LeftLowerArm", "LeftHand" }, RightWrist = { "RightLowerArm", "RightHand" },
	LeftHip = { "LowerTorso", "LeftUpperLeg" }, RightHip = { "LowerTorso", "RightUpperLeg" },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg" }, RightKnee = { "RightUpperLeg", "RightLowerLeg" },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot" }, RightAnkle = { "RightLowerLeg", "RightFoot" },
}
local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

-- the engine's joint solve from the HumanoidRootPart out (Motor6D: Part1 = Part0 * C0 * Transform * C1^-1)
local weldOffsets = setmetatable({}, { __mode = "k" })
local jointCache = setmetatable({}, { __mode = "k" })
local jointDirty = setmetatable({}, { __mode = "k" })
local jointHooked = setmetatable({}, { __mode = "k" })
local function solve(model, keepRoot)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not keepRoot then
		hrp.CFrame = CFrame.new(0, hum.HipHeight + hrp.Size.Y / 2, 0)
	end
	local joints = jointCache[model]
	-- (a joint replaced since the list was made - EnsureMotors' Motor6D for an AnimationConstraint: the list again)
	if joints and jointDirty[model] then
		joints = nil
	end
	if joints then
		for _, j in ipairs(joints) do
			if j.Parent == nil then
				joints = nil
				break
			end
		end
	end
	if not joints or not keepRoot then
		jointDirty[model] = nil
		if not jointHooked[model] then
			jointHooked[model] = true
			model.DescendantAdded:Connect(function(d)
				if d.ClassName == "Motor6D" or d.ClassName == "AnimationConstraint" or d.ClassName == "Weld" then
					jointDirty[model] = true
				end
			end)
		end
		joints = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d.ClassName == "Motor6D" or d.ClassName == "AnimationConstraint" or d.ClassName == "Weld" or (d.ClassName == "WeldConstraint" and weldOffsets[d]) then
				table.insert(joints, d)
			end
		end
		jointCache[model] = joints
	end
	local done = { [hrp] = true }
	local progress = true
	while progress do
		progress = false
		for _, j in ipairs(joints) do
			local p0, p1 = j.Part0, j.Part1
			local ac = j.ClassName == "AnimationConstraint"
			if ac then
				p0, p1 = j.Attachment0 and j.Attachment0.Parent, j.Attachment1 and j.Attachment1.Parent
			end
			if p0 and p1 and done[p0] and not done[p1] then
				if j.ClassName == "WeldConstraint" then
					p1.CFrame = p0.CFrame * weldOffsets[j]
				elseif ac then
					-- (child = parent * Attachment0.CFrame * Transform * Attachment1.CFrame^-1: the Motor6D's convention)
					p1.CFrame = p0.CFrame * j.Attachment0.CFrame * ((not IGNORE_AC and j.Transform) or CFrame.new()) * j.Attachment1.CFrame:Inverse()
				else
					local t = j.ClassName == "Motor6D" and not IGNORE_ALL and j.Transform or nil
					p1.CFrame = p0.CFrame * j.C0 * (t or CFrame.new()) * j.C1:Inverse()
				end
				done[p1] = true
				progress = true
			end
		end
	end
end
local function recordWelds(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "WeldConstraint" and d.Part0 and d.Part1 then
			weldOffsets[d] = d.Part0.CFrame:Inverse() * d.Part1.CFrame
		end
	end
	jointCache[model] = nil
end

local STATE = { Running = roblox.Enum.HumanoidStateType.Running }
local function newRig(scale, headSize)
	local model = E.new("Model")
	model.Name = "Boxer"
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1) * scale
	hrp.Transparency = 1
	hrp.AssemblyLinearVelocity = Vector3.zero
	local ra = E.new("Attachment", hrp)
	ra.Name = "RootRigAttachment"
	ra.Position = Vector3.zero
	local function addPart(name, size, orig, atts, cls)
		local p = E.new(cls or "MeshPart", model)
		p.Name = name
		p.Size = size
		p.Color = roblox.Color3.new(1, 1, 1)
		local o = E.new("Vector3Value", p)
		o.Name = "OriginalSize"
		o.Value = orig
		for an, pos in pairs(atts) do
			local a = E.new("Attachment", p)
			a.Name = an
			a.Position = pos.cur
			local op = E.new("Vector3Value", a)
			op.Name = "OriginalPosition"
			op.Value = pos.orig
		end
		return p
	end
	for name, b in pairs(BLOCK) do
		local atts = {}
		for an, pos in pairs(b.att) do
			atts[an] = { cur = v3(pos) * scale, orig = v3(pos) }
		end
		addPart(name, v3(b.size) * scale, v3(b.size), atts)
	end
	addPart("Head", Vector3.new(headSize, headSize, headSize), Vector3.new(1.2, 1.2, 1.2),
		{ NeckRigAttachment = { cur = Vector3.new(0, -0.5 * headSize, 0), orig = Vector3.new(0, -0.6, 0) } })
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		if JOINTS_AC then
			local m = E.new("AnimationConstraint", p1)
			m.Name = jn
			m.Attachment0 = p0:FindFirstChild(jn .. "RigAttachment")
			m.Attachment1 = p1:FindFirstChild(jn .. "RigAttachment")
			m.Enabled = true
			m.Transform = CFrame.new()
		else
			local m = E.new("Motor6D", p1)
			m.Name = jn
			m.Part0, m.Part1 = p0, p1
			m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
			m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
			m.Transform = CFrame.new()
		end
	end
	local hum = E.new("Humanoid", model)
	hum.HipHeight = 2 * scale.Y
	hum.Sit = false
	hum.MoveDirection = Vector3.zero
	hum.WalkSpeed = 16
	hum.GetState = function()
		return STATE.Running
	end
	hum.ReplaceBodyPartR15 = function(_, enum, part)
		local name = enum.Name
		local old = model:FindFirstChild(name)
		if name ~= "Head" then
			local o = part:FindFirstChild("OriginalSize")
			if o then
				part.Size = o.Value * scale
			end
			for _, a in ipairs(part:GetChildren()) do
				if a.ClassName == "Attachment" then
					local op = a:FindFirstChild("OriginalPosition")
					if op then
						a.Position = op.Value * scale
					end
				end
			end
		end
		for _, m in ipairs(model:GetDescendants()) do
			if m.ClassName == "Motor6D" then
				if m.Part0 == old then
					m.Part0 = part
				end
				if m.Part1 == old then
					m.Part1 = part
					m.Parent = part
				end
			elseif m.ClassName == "AnimationConstraint" then
				-- (the engine re-points the constraint at the new part's attachments of the same names)
				local a0, a1 = m.Attachment0, m.Attachment1
				if a0 and a0.Parent == old then
					m.Attachment0 = part:FindFirstChild(a0.Name)
				end
				if a1 and a1.Parent == old then
					m.Attachment1 = part:FindFirstChild(a1.Name)
					m.Parent = part
				end
			end
		end
		part.Parent = model
		old:Destroy()
		solve(model)
		return true
	end
	solve(model)
	return model, hum
end

BuilderTiers.Reset()
BuilderTiers.Services = {
	AssetService = { CreateMeshPartAsync = function(_, content)
		local u = type(content) == "table" and (content.uri or content.Uri) or tostring(content)
		local id = tonumber(tostring(u):match("(%d+)%s*$"))
		local mp = E.new("MeshPart")
		mp.MeshId = "rbxassetid://" .. tostring(id)
		return mp
	end },
	Content = sim.Content,
}
BuilderGear.Reset()
BuilderGear.Services = BuilderTiers.Services

local currentModel
local function solving(mod, key)
	local f = mod[key]
	mod[key] = function(model, ...)
		if model == currentModel then
			solve(model)
		end
		return f(model, ...)
	end
end
solving(BuilderBody, "Colors")
solving(BuilderBody, "Muscles")
solving(BuilderBody, "Attire")
solving(BuilderBody, "Hands")
solving(BuilderHair, "Build")

local function build(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end
local function buildFor(app, tier)
	for v = 0, 100 do
		local t = Builder.Tiers(app, build(v))
		if BodyTiers.Key(t) == string.rep(tostring(tier), 14) then
			return v + (tier > 1 and 2 or 0), build(v + (tier > 1 and 2 or 0))
		end
	end
	error("no build gives tier " .. tier)
end
local function pal(i)
	local c = Looks.Palette[i]
	return { c[1], c[2], c[3] }
end

-- a complete boxer of `tier` (male, Athletic frame): returns model, hum, app
local function makeBoxer(tier, spec)
	spec = spec or {}
	local app = Looks.Defaults(spec.g or 1)
	app.skin = spec.skin or 6
	app.body.frame = spec.frame or FRAME or "Athletic"
	app.face.key = "determined"
	app.gloves.color = pal(spec.gloves or 1)
	app.attire.trunks = pal(spec.trunks or 3)
	app.attire.trim = pal(spec.trim or 1)
	app.attire.trunkStyle = spec.trunkStyle or app.attire.trunkStyle
	app.attire.shoeStyle = spec.shoeStyle or app.attire.shoeStyle
	app.height = spec.height or HEIGHT or app.height
	local _, b = buildFor(app, tier)
	local sc = Builder.Scales(app, b)
	local model, hum = newRig(Vector3.new(sc.width, sc.height, sc.depth), 1.2 * sc.head)
	model.Parent = E.workspace
	currentModel = model
	local ok, err = pcall(Builder.Cosmetics, model, app, b, nil, { hands = spec.hands or HANDS, detail = "full" })
	if not ok then
		error("Cosmetics failed: " .. tostring(err))
	end
	solve(model)
	recordWelds(model)
	currentModel = nil
	return model, hum, app
end

------------------------------------------------------------------------
-- export (world space, as v8_scene)
------------------------------------------------------------------------
local function r4(x)
	return math.floor(x * 10000 + 0.5) / 10000
end
local function enumName(v)
	if v == nil then
		return nil
	end
	local ok, n = pcall(function()
		return v.Name
	end)
	return ok and n or tostring(v):match("([^%.]+)$")
end
local function cfList(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { r4(x), r4(y), r4(z), r4(r00), r4(r01), r4(r02), r4(r10), r4(r11), r4(r12), r4(r20), r4(r21), r4(r22) }
end
local function color(c)
	return c and { r4(c.R), r4(c.G), r4(c.B) } or { 0.8, 0.8, 0.8 }
end
local meshCache = {}
local function meshOf(file)
	local m = meshCache[file]
	if not m then
		m = MeshV2.Read(file)
		local cx, cy, cz, bx, by, bz = MeshV2.Bounds(m)
		m.b = { cx, cy, cz, bx, by, bz }
		meshCache[file] = m
	end
	return m
end
-- the part's mesh in world space (recentred on the bbox, scaled to Size, by its CFrame)
local function worldMesh(p, file)
	local m = meshOf(file)
	local cx, cy, cz, bx, by, bz = table.unpack(m.b)
	local s = p.Size
	local kx, ky, kz = s.X / bx, s.Y / by, s.Z / bz
	local cf = p.CFrame
	local P, N = table.create(#m.P), table.create(#m.N)
	for i = 1, #m.P, 3 do
		local w = cf * Vector3.new((m.P[i] - cx) * kx, (m.P[i + 1] - cy) * ky, (m.P[i + 2] - cz) * kz)
		P[i], P[i + 1], P[i + 2] = r4(w.X), r4(w.Y), r4(w.Z)
		local n = cf:VectorToWorldSpace(Vector3.new(m.N[i] / kx, m.N[i + 1] / ky, m.N[i + 2] / kz)).Unit
		N[i], N[i + 1], N[i + 2] = r4(n.X), r4(n.Y), r4(n.Z)
	end
	return P, N, m.T
end
local function fileOf(p)
	local id = p:GetAttribute("GearMesh") or p:GetAttribute("BodyMesh")
	local tier = p:GetAttribute("BodyTier")
	if p:GetAttribute("GearMesh") then
		return MESH_FILES[id]
	elseif tier then
		return string.format("%s/out/tier%d/%s.mesh", MESHROOT, tier, p.Name)
	end
	return nil
end

local function exportFrame(model, t)
	local fr = { t = r4(t), meshes = {}, parts = {} }
	for _, p in ipairs(model:GetDescendants()) do
		local cls = p.ClassName
		if not (cls == "Part" or cls == "MeshPart" or cls == "WedgePart") or p.Name == "HumanoidRootPart" then
			continue
		end
		if (p.Transparency or 0) >= 0.99 then
			continue
		end
		if BARE and not p:GetAttribute("BodyTier") and p.Name ~= "Head" then
			continue
		end
		local file = cls == "MeshPart" and fileOf(p)
		if file then
			local P, N, T = worldMesh(p, file)
			table.insert(fr.meshes, { name = p.Name, gear = p:GetAttribute("GearMesh") ~= nil, slot = p:GetAttribute("GearSlot"), p = P, n = N,
				t = T, color = color(p.Color), material = enumName(p.Material), reflectance = p.Reflectance or 0 })
		elseif p.Name == "Head" and p:FindFirstChildOfClass("SpecialMesh") then
			local decal = p:FindFirstChild("face")
			fr.head = { cf = cfList(p.CFrame), size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = color(p.Color),
				material = enumName(p.Material), classic = Kit.CLASSIC,
				decal = decal and { texture = decal.Texture, file = FACE_FILES[decal.Texture], face = enumName(decal.Face) } or nil }
		else
			local shape = cls == "WedgePart" and "Wedge" or "Block"
			if p:FindFirstChildOfClass("SpecialMesh") then
				local mt = enumName(p:FindFirstChildOfClass("SpecialMesh").MeshType)
				shape = mt == "Sphere" and "Ellipsoid" or mt
			elseif p.Shape then
				shape = enumName(p.Shape)
			end
			table.insert(fr.parts, { name = p.Name, shape = shape, cf = cfList(p.CFrame), size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) },
				color = color(p.Color), material = enumName(p.Material), reflectance = p.Reflectance or 0, transparency = p.Transparency or 0 })
		end
	end
	return fr
end

------------------------------------------------------------------------
-- interpenetration: how deep the thigh meshes go into the LowerTorso mesh (and the trunks), per frame
------------------------------------------------------------------------
-- part-space triangles of a part's mesh, scaled to its Size
local function localTris(p)
	local file = fileOf(p)
	if not file then
		return nil
	end
	local m = meshOf(file)
	local cx, cy, cz, bx, by, bz = table.unpack(m.b)
	local s = p.Size
	local kx, ky, kz = s.X / bx, s.Y / by, s.Z / bz
	local V = {}
	for i = 1, #m.P, 3 do
		table.insert(V, Vector3.new((m.P[i] - cx) * kx, (m.P[i + 1] - cy) * ky, (m.P[i + 2] - cz) * kz))
	end
	return V, m.T
end
-- point inside a closed mesh: parity of a +X ray's crossings
local function inside(V, T, q)
	local n = 0
	for i = 1, #T, 3 do
		local a, b, c = V[T[i]], V[T[i + 1]], V[T[i + 2]]
		-- (Moller-Trumbore against direction +X)
		local e1, e2 = b - a, c - a
		local h = Vector3.new(0, -e2.Z, e2.Y) -- dir x e2 with dir = (1, 0, 0)
		local det = e1:Dot(h)
		if math.abs(det) > 1e-12 then
			local f = 1 / det
			local s = q - a
			local u = f * s:Dot(h)
			if u >= 0 and u <= 1 then
				local qv = s:Cross(e1)
				local v = f * qv.X
				if v >= 0 and u + v <= 1 then
					local tt = f * e2:Dot(qv)
					if tt > 0 then
						n += 1
					end
				end
			end
		end
	end
	return n % 2 == 1
end
-- distance from q to the mesh surface (approximate: nearest vertex)
local function nearestV(V, q)
	local best = math.huge
	for _, v in ipairs(V) do
		local d = (v - q).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end
-- the vertices of part a inside part b's mesh: count and the deepest (studs)
local function penetration(pa, pb)
	local Va = localTris(pa)
	local Vb, Tb = localTris(pb)
	if not (Va and Vb) then
		return 0, 0
	end
	local rel = pb.CFrame:Inverse() * pa.CFrame
	local n, deep = 0, 0
	local bmin, bmax = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, v in ipairs(Vb) do
		bmin, bmax = bmin:Min(v), bmax:Max(v)
	end
	for _, v in ipairs(Va) do
		local q = rel * v
		if q.X > bmin.X and q.Y > bmin.Y and q.Z > bmin.Z and q.X < bmax.X and q.Y < bmax.Y and q.Z < bmax.Z and inside(Vb, Tb, q) then
			n += 1
			deep = math.max(deep, nearestV(Vb, q))
		end
	end
	return n, deep
end

------------------------------------------------------------------------
-- the Animator under the fake engine
------------------------------------------------------------------------
local CS = E.CollectionService
local player = E.localPlayer
local playersProps = H.Service("Players")._props
playersProps.GetPlayers = function()
	return { player }
end
playersProps.GetPlayerFromCharacter = function(_, m)
	return (m ~= nil and m == player.Character) and player or nil
end
player.CharacterAdded = FE.Signal()
local PreSim = FE.Signal()
local ANIM_LOG = {}
H.Service("RunService")._props.PreSimulation = PreSim
do
	local file = srcDir .. "/client/Animator.client.lua"
	local env = table.clone(H.globals)
	local SPS = H.client.Parent
	env.script = { Parent = SPS, Name = "Animator" }
	-- (its Output lines, for the self-check's metrics: the heartbeat, the "writes are not taking effect" warnings)
	local function capture(kind, real)
		return function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			local msg = table.concat(parts, " ")
			if msg:sub(1, 10) == "[Animator]" then
				table.insert(ANIM_LOG, kind .. " " .. msg)
			end
			real(...)
		end
	end
	env.warn = capture("W", warn)
	env.print = capture("P", print)
	local chunk = luau.load(fs.readFile(file), { debugName = "Animator.client.lua", environment = env })
	ltask.spawn(chunk)
	-- the Animator may yield while it loads (an optional module's WaitForChild with a timeout yields once):
	-- let it finish setting up (AnimRig.rigs) before any clip drives a frame
	-- (read the host's module cache, not H.require: asking for a module mid-load trips the cycle guard)
	local function rigsReady()
		local c = H.cache[H.files.AnimRig]
		return c ~= nil and type(c.value) == "table" and c.value.rigs ~= nil
	end
	local guard = 0
	while not rigsReady() and guard < 600 do
		guard += 1
		ltask.wait()
	end
	assert(rigsReady(), "v9_anim: the Animator did not finish loading")
end
-- --convert-after S: how long an upgrade constraint may stay before the Animator rebuilds it on this client (default
-- 1.5 s; a large value leaves it to the self-check's first step)
if args["convert-after"] then
	H.require("AnimRig").CONVERT_AFTER = tonumber(args["convert-after"])
end
local DT = 1 / 60
local NOPEN = args.nopen == true
local TIMINGS = {}
for m in (args.timing or "steady"):gmatch("[^,]+") do
	table.insert(TIMINGS, m)
end
-- the frame timing of a walk clip: fdt = the frame's time (PreSimulation's dt, the virtual clock), pdt = the time
-- the physics advanced the root by (studio: whole 240 Hz steps, the remainder carried to the next frame)
local function timingOf(mode)
	local n, acc = 0, 0
	local nominal = mode == "hz240" and 1 / 240 or (mode == "hz30" and 1 / 30 or 1 / 60)
	local function tick()
		n += 1
		if mode == "steady" or mode == "hz240" or mode == "hz30" then
			return nominal, nominal
		elseif mode == "replicated" then
			-- [Studio] a server-owned root as a client sees it: its position arrives in replication steps (~20 Hz), held
			-- for the frames between - two frames of no travel, then three frames' worth at once
			return nominal, (n % 3 == 0) and 3 * nominal or 0
		elseif mode == "rough" then
			-- [Studio] a busy client: frame times scattered between ~1/80 and ~1/28 s (a deterministic hash, no period),
			-- the physics in whole 240 Hz steps
			local h = (math.sin(n * 12.9898 + 78.233) * 43758.5453) % 1
			local fdt = 1 / 80 + h * h * (1 / 28 - 1 / 80)
			acc += fdt
			local steps = math.floor(acc * 240 + 1e-9)
			acc -= steps / 240
			return fdt, steps / 240
		elseif mode == "spike" then
			if n % 47 == 0 then
				return 0.1, 0.1
			elseif n == 160 then
				return 0.25, 0.25
			end
			return nominal, nominal
		end
		-- studio: a deterministic wander of a few periods (the Lua step lands at another point of every frame)
		local j = 0.15 * (0.6 * math.sin(n * 1.7) + 0.4 * math.sin(n * 0.37 + 1))
		local fdt = nominal * (1 + j)
		if mode == "wander" then
			return fdt, fdt
		end
		acc += fdt
		local steps = math.floor(acc * 240 + 1e-9)
		acc -= steps / 240
		return fdt, steps / 240
	end
	return tick, nominal
end
local function frame(models, dt)
	dt = dt or DT
	VT += dt
	PreSim:Fire(dt)
	for _, m in ipairs(models) do
		solve(m, true)
	end
	ltask.wait()
end

local metrics = {}
local index = { about = "v9: the client Animator on tier boxers (Builder.Cosmetics, fake rig), world space, studs, +Y up, face -Z", clips = {} }
Host.MkDir(OUT)

------------------------------------------------------------------------
-- gait numbers: joint angles from the solved parts, the soles against the floor, the planted feet's slide
------------------------------------------------------------------------
local deg, atan2 = math.deg, math.atan2
-- the pieces drawn on a foot (the part itself and whatever is welded to it): part-space points relative to the foot
local function footPoints(model, side)
	local foot = model:FindFirstChild(side .. "Foot")
	local pts = {}
	local function add(p)
		local rel = foot.CFrame:Inverse() * p.CFrame
		local file = p.ClassName == "MeshPart" and fileOf(p)
		if file then
			local V = localTris(p)
			for i = 1, #V, 7 do
				table.insert(pts, rel * V[i])
			end
		else
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						table.insert(pts, rel * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					end
				end
			end
		end
	end
	local drawn = false
	for _, d in ipairs(model:GetDescendants()) do
		local cls = d.ClassName
		if (cls == "Weld" or cls == "WeldConstraint" or cls == "Motor6D") and d.Part0 == foot and d.Part1 and d.Part1 ~= foot
			and (d.Part1.Transparency or 0) < 0.99 and d.Name ~= (side .. "Ankle") then
			add(d.Part1)
			drawn = true
		end
	end
	if not drawn or (foot.Transparency or 0) < 0.99 then
		add(foot)
	end
	return foot, pts
end
local function soleOf(foot, pts)
	local cf = foot.CFrame
	local lo, loPt, loI = math.huge, nil, 1
	for i, q in ipairs(pts) do
		local w = cf * q
		if w.Y < lo then
			lo, loPt, loI = w.Y, w, i
		end
	end
	return lo, loPt, loI
end
-- the signed angle of a direction in a frame's sagittal plane (from straight down, + = forward / -Z)
local function sag(cf, v)
	local d = cf:VectorToObjectSpace(v)
	return deg(atan2(-d.Z, -d.Y))
end
local function yawOf(cf)
	local l = cf.LookVector
	return deg(atan2(-l.X, -l.Z))
end
local function gaitSampler(model)
	local P = {}
	for _, n in ipairs({ "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg",
		"RightLowerLeg", "LeftFoot", "RightFoot", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand" }) do
		P[n] = model:FindFirstChild(n)
	end
	local feet = {}
	for _, s in ipairs({ "Left", "Right" }) do
		local f, pts = footPoints(model, s)
		feet[s] = { foot = f, pts = pts }
		if args.debugfoot then
			local mn, mx = Vector3.new(1e9, 1e9, 1e9), Vector3.new(-1e9, -1e9, -1e9)
			for _, q in ipairs(pts) do
				mn, mx = mn:Min(q), mx:Max(q)
			end
			local an = f:FindFirstChild(s .. "Ankle")
			print(string.format("foot %s size %s drawn min %s max %s ankle C1 %s", s, tostring(f.Size), tostring(mn), tostring(mx),
				an and tostring(an.C1.Position) or "?"))
		end
	end
	return function(t)
		local hrp = P.HumanoidRootPart.CFrame
		local lt, ut, head = P.LowerTorso.CFrame, P.UpperTorso.CFrame, P.Head.CFrame
		local s = { t = t, rootY = hrp.Y, rootZ = hrp.Z, rootX = hrp.X, rootYaw = yawOf(hrp) }
		s.pelvisY = lt.Y
		s.headY = head.Y
		s.headPitch = deg(math.asin(math.clamp(head.LookVector.Y, -1, 1)))
		s.headRoll = deg(math.asin(math.clamp(head.RightVector.Y, -1, 1)))
		s.headYaw = ((yawOf(head) - s.rootYaw + 540) % 360) - 180
		s.pelvisYaw = ((yawOf(lt) - s.rootYaw + 540) % 360) - 180
		s.chestYaw = ((yawOf(ut) - s.rootYaw + 540) % 360) - 180
		s.twist = s.chestYaw - s.pelvisYaw
		s.trunkPitch = deg(math.asin(math.clamp(ut.LookVector.Y, -1, 1)))
		s.trunkRoll = deg(math.asin(math.clamp(ut.RightVector.Y, -1, 1)))
		s.pelvisRoll = deg(math.asin(math.clamp(lt.RightVector.Y, -1, 1)))
		for _, sd in ipairs({ "Left", "Right" }) do
			local k = sd:sub(1, 1)
			local th, sh, ft = P[sd .. "UpperLeg"].CFrame, P[sd .. "LowerLeg"].CFrame, P[sd .. "Foot"].CFrame
			-- hip: the thigh against the pelvis (sagittal, + flexion) and against the vertical (the root's frame)
			s["hip" .. k] = sag(lt, -th.UpVector)
			s["thigh" .. k] = sag(hrp, -th.UpVector)
			-- knee: the shank against the thigh (+ = flexed back)
			s["knee" .. k] = -sag(th, -sh.UpVector)
			-- the foot's pitch in the world (+ = toes up) and against the shank (+ dorsiflexion, the rest pose's offset kept)
			s["footPitch" .. k] = deg(math.asin(math.clamp(ft.LookVector.Y, -1, 1)))
			s["ankle" .. k] = sag(sh, ft.LookVector) - 90
			local ua, la, hd = P[sd .. "UpperArm"].CFrame, P[sd .. "LowerArm"].CFrame, P[sd .. "Hand"].CFrame
			s["shoulder" .. k] = sag(ut, -ua.UpVector)
			s["elbow" .. k] = deg(math.acos(math.clamp(ua.UpVector:Dot(la.UpVector), -1, 1)))
			s["wrist" .. k] = deg(math.acos(math.clamp(la.UpVector:Dot(hd.UpVector), -1, 1)))
			s["handZ" .. k] = (hrp:PointToObjectSpace(hd.Position)).Z
			local F = feet[sd]
			local lo, pt, idx = soleOf(F.foot, F.pts)
			s["sole" .. k] = lo
			s["solePt" .. k] = pt
			s["soleI" .. k] = idx
			s["footCF" .. k] = ft
			s["pts" .. k] = F.pts
			s["ankleP" .. k] = ft.Position
		end
		return s
	end
end
-- summary of a sample run: ranges, the planted feet's slide (the lowest sole point while it is within 0.02 of the
-- floor, measured as the world travel of the foot's contact frame across consecutive frames), clearance
local function gaitSummary(S)
	local function range(key)
		local lo, hi = math.huge, -math.huge
		for _, s in ipairs(S) do
			lo, hi = math.min(lo, s[key]), math.max(hi, s[key])
		end
		return { r4(lo), r4(hi) }
	end
	local out = {}
	for _, k in ipairs({ "hipL", "hipR", "thighL", "kneeL", "kneeR", "ankleL", "footPitchL", "shoulderL", "shoulderR", "elbowL", "elbowR",
		"wristL", "handZL", "pelvisYaw", "chestYaw", "twist", "pelvisY", "headY", "headPitch", "headRoll", "headYaw", "trunkPitch", "trunkRoll",
		"pelvisRoll", "soleL", "soleR" }) do
		out[k] = range(k)
	end
	-- the planted feet: each frame a foot's lowest point is on the floor (< 0.03), how far its ankle moved in the
	-- world since the frame before (a planted, rolling foot's ankle moves; its contact must not: the sole
	-- point that is lowest on both frames, i.e. the contact, is compared)
	local slide, slideMax, contact = { L = 0, R = 0 }, 0, { L = 0, R = 0 }
	local sink = 0
	for i = 2, #S do
		local a, b = S[i - 1], S[i]
		for _, k in ipairs({ "L", "R" }) do
			if a["sole" .. k] < 0.012 and b["sole" .. k] < 0.012 then
				-- the material point of the sole that touched the floor on the frame before: where it is now (rolling
				-- without slip leaves it where it was; a slide carries it along the floor)
				local q = a["pts" .. k][a["soleI" .. k]]
				local pa, pb = a["footCF" .. k] * q, b["footCF" .. k] * q
				local d = pb.Y < 0.012 and Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z).Magnitude or 0
				slide[k] += d
				slideMax = math.max(slideMax, d / DT)
				contact[k] += 1
			end
			sink = math.min(sink, b["sole" .. k])
		end
	end
	out.slideL, out.slideR, out.slideMaxSpeed = r4(slide.L), r4(slide.R), r4(slideMax)
	out.contactFramesL, out.contactFramesR = contact.L, contact.R
	out.sinkMin = r4(sink)
	return out
end

local function partPen(model, rec)
	local lt = model:FindFirstChild("LowerTorso")
	for _, s in ipairs({ "Left", "Right" }) do
		local ul = model:FindFirstChild(s .. "UpperLeg")
		local n, d = penetration(ul, lt)
		rec[s .. "ThighInPelvis"] = { n = n, deep = r4(d) }
		local n2, d2 = penetration(lt, ul)
		rec[s .. "PelvisInThigh"] = { n = n2, deep = r4(d2) }
	end
end

-- per-frame series of a clip's samples (for plots / the report)
local function seriesOf(SALL)
	local keys = { "t", "v", "rootZ", "rootYaw", "pelvisY", "headY", "headPitch", "hipL", "hipR", "thighL", "thighR", "kneeL", "kneeR", "ankleL", "ankleR",
		"footPitchL", "footPitchR", "shoulderL", "shoulderR", "elbowL", "elbowR", "wristL", "pelvisYaw", "chestYaw", "trunkPitch", "soleL",
		"soleR", "handZL", "handZR" }
	local ser = {}
	for _, x in ipairs(SALL) do
		local row = {}
		for _, k in ipairs(keys) do
			row[k] = r4(x[k])
		end
		row.ankleZL, row.ankleZR = r4(x.anklePL.Z), r4(x.anklePR.Z)
		local pv = SALL[#ser]
		for _, k in ipairs({ "L", "R" }) do
			local slip = 0
			if pv and pv["sole" .. k] < 0.012 and x["sole" .. k] < 0.012 then
				local q = pv["pts" .. k][pv["soleI" .. k]]
				local pa, pb = pv["footCF" .. k] * q, x["footCF" .. k] * q
				slip = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z).Magnitude
			end
			row["slip" .. k] = r4(slip)
		end
		table.insert(ser, row)
	end
	return ser
end

------------------------------------------------------------------------
-- walking clips
------------------------------------------------------------------------
-- walk = Config.TownWalkSpeed (StarterPlayer.CharacterWalkSpeed), jog = the ring's base pace, run = Config.TownRunSpeed
-- (Shift), sprint = the roadwork pace (Main: 18 + Stamina x 0.06); --speeds walk=5,run=16 overrides
local SPEEDS = { walk = 6.5, jog = 11, run = 16, sprint = 22, shift = 16 }
-- shift: [Studio] W held at the town's walking pace, then Shift: the Humanoid's speed jumps from walk to run in one
-- frame (WalkSpeed 6.5 -> 16; AssemblyLinearVelocity follows within a physics step) at SHIFT_AT s; its steady numbers
-- are from 1.5 s after it, the switch's own (rec.shift) over the 1.5 s after it, and the diagnostic's 10 Hz sample
-- (Diag.SampleTick, as /wcbdiag reads Studio) from just before it (rec.diag: the lines and the verdicts)
local SHIFT_AT = tonumber(args.shiftat) or 2.5
for kv in (args.speeds or ""):gmatch("[^,]+") do
	local k, v = kv:match("(%a+)=([%d%.]+)")
	if k then
		SPEEDS[k] = tonumber(v)
	end
end
local function walkClip(clip, tier, timing)
	timing = timing or "steady"
	local tick, nominal = timingOf(timing)
	local TTAG = timing ~= "steady" and ("_" .. timing) or ""
	local model, hum = makeBoxer(tier)
	model.Name = "Walker"
	-- Roblox's Animate script and the Humanoid's Animator on the local character (fakes): the Animate script keeps
	-- starting walk tracks for as long as it is enabled; the Animator must switch it off and stop every track it started
	local animate = E.new("LocalScript", model)
	animate.Name = "Animate"
	animate.Disabled = false
	local animator = E.new("Animator", hum)
	local playing, started = {}, 0
	animator.AnimationPlayed = FE.Signal()
	animator.GetPlayingAnimationTracks = function()
		local out = {}
		for tr in pairs(playing) do
			table.insert(out, tr)
		end
		return out
	end
	local function playTrack()
		local tr = { Name = "walk" }
		tr.Stop = function(self)
			playing[self] = nil
		end
		playing[tr] = true
		started += 1
		animator.AnimationPlayed:Fire(tr)
	end
	playTrack()
	-- (LoadAnimation: the Animator's keyframe fallback loads Roblox's stock tracks on an NPC; recorded, not played)
	local loaded = {}
	animator.LoadAnimation = function(_, anim)
		local tr = { id = anim.AnimationId, weight = 0, speed = 1, playing = false }
		function tr:Play(_, w, sp)
			self.playing, self.weight, self.speed = true, w or 1, sp or 1
		end
		function tr:Stop()
			self.playing = false
		end
		function tr:AdjustWeight(w)
			self.weight = w
		end
		function tr:AdjustSpeed(sp)
			self.speed = sp
		end
		table.insert(loaded, tr)
		return tr
	end
	-- --npc: an Ambient gym member on Loop = walk (a server-moved NPC) instead of the local player's character: the
	-- Animator senses its gait from the replicated root (and the Humanoid's MoveDirection / WalkSpeed as the intent)
	local NPC = args.npc ~= nil
	if NPC then
		hum.WalkSpeed = SPEEDS[clip]
		model:SetAttribute("Loop", "walk")
		CS:AddTag(model, "Ambient")
	else
		player.Character = model
		player.CharacterAdded:Fire(model)
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local y0 = hrp.CFrame.Y
	local speed = SPEEDS[clip]
	-- settle standing, then accelerate over 0.5 s, then a steady pace
	local z = 0
	local v = 0
	local trace = {}
	local frames = {}
	local tStart = 0
	local total = tonumber(args.walksecs) or (clip == "shift" and SHIFT_AT + 3.5 or 4.5)
	local tSteady = clip == "shift" and SHIFT_AT + 1.5 or 2.5
	local Diag = H.require("Diag")
	local DS, nextDiag = Diag.NewSample(), SHIFT_AT - 0.1
	local nSteps = 0
	local hist = {}
	local sample = gaitSampler(model)
	local S, SALL = {}, {}
	local t = 0
	while t < total do
		local fdt, pdt = tick()
		t += fdt
		nSteps += 1
		local i = nSteps
		if clip == "shift" then
			if t > SHIFT_AT then
				v = speed
			elseif t > 1 then
				v = math.min(SPEEDS.walk, v + SPEEDS.walk / 0.5 * fdt)
			end
		elseif t > 1 then
			v = math.min(speed, v + speed / 0.5 * fdt)
		end
		z -= v * pdt
		hrp.CFrame = CFrame.new(0, y0, z)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, -v)
		hum.MoveDirection = v > 0 and Vector3.new(0, 0, -1) or Vector3.zero
		-- (the player's camera follows him: his rig stays in the Animator's near band, lod 3, as in Studio)
		E.camera.CFrame = CFrame.new(0, y0 + 3, z + 10)
		if animate.Disabled ~= true and i % 20 == 0 then
			playTrack()
		end
		frame({ model }, fdt)
		local smp = sample(t)
		smp.v = v
		-- the speed the Animator sensed this frame (the gait runs on it): its spikes are the NPC jitter
		do
			local rg = H.require("AnimRig").rigs[model]
			smp.sensed = rg and rg.loco.speed or 0
		end
		if args.debugrig and t > tonumber(args.debugrig) and t < tonumber(args.debugrig) + 0.4 then
			local rg = H.require("AnimRig").rigs[model]
			local f = rg and rg.foot.L
			if f then
				print(string.format("dbg %.3f L swing=%s plan=%s push=%s pushOn=%s u=%.2f kAct=%.1f kVel=%.1f sigma=%.2f pitch=%.2f knee=%.0f reachShort=%.3f k0=%s kpk?",
					t, tostring(f.swing), tostring(f.plan), tostring(f.push), tostring(f.pushOn), f.planU or -1, math.deg(f.kAct or 0), math.deg(f.kVel or 0),
					f.sigma or -1, f.pitchS or 0, smp.kneeL, f.reachShort or 0, tostring(f.k0 and math.deg(f.k0))))
				print(string.format("    curZ %.3f tgtZ %.3f PZ %.3f t0 %.3f dur %.3f uS %.3f kind %s", f.cur and f.cur.Z or 0, f.tgtW and f.tgtW.Z or 0,
					f.P and f.P.Z or 0, f.t0, f.dur, (t - f.t0) / f.dur, tostring(f.stepKind)))
			end
		end
		table.insert(SALL, smp)
		if t > tSteady then
			table.insert(S, smp)
		end
		if clip == "shift" and t >= nextDiag and t < SHIFT_AT + 2.5 then
			Diag.SampleTick(DS, model, nextDiag - SHIFT_AT + 0.5)
			nextDiag += 0.1
		end
		if t > tSteady then
			local lt = model:FindFirstChild("LowerTorso")
			local ut = model:FindFirstChild("UpperTorso")
			local head = model:FindFirstChild("Head")
			local rel = hrp.CFrame:Inverse() * lt.CFrame
			local relU = hrp.CFrame:Inverse() * ut.CFrame
			local relH = hrp.CFrame:Inverse() * head.CFrame
			local rx, ry, rz = rel:ToOrientation()
			local hx, _, hz = relH:ToOrientation()
			local ux = relU:ToOrientation()
			table.insert(trace, { t = t, ltX = rel.X, ltY = rel.Y, utX = relU.X, headX = relH.X, roll = rz, yaw = ry, pitch = rx,
				headPitch = hx, headRoll = hz, chestPitch = ux,
				lf = model:FindFirstChild("LeftFoot").Position, rf = model:FindFirstChild("RightFoot").Position })
			table.insert(hist, { t = t, i = i })
		end
		if t > tSteady and tStart == 0 then
			tStart = t
		end
	end
	-- one gait cycle: from the trace, the period of the left foot's height
	local rig
	for _, r in pairs(H.cache) do
		_ = r
	end
	-- (re-run: record NFRAMES frames over the last cycle; the cycle length from the left foot's lifts)
	local lifts = {}
	for k = 2, #trace do
		local a, b = trace[k - 1].lf.Y, trace[k].lf.Y
		local thr = 0.5 * (model:FindFirstChild("LeftFoot").Size.Y)
		if a <= thr + 0.06 and b > thr + 0.06 then
			table.insert(lifts, trace[k].t)
		end
	end
	local period = (#lifts >= 2) and (lifts[#lifts] - lifts[#lifts - 1]) or 1
	-- sway stats over the trace
	local minX, maxX, minR, maxR, minU, maxU, minH, maxH = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, s in ipairs(trace) do
		minX, maxX = math.min(minX, s.ltX), math.max(maxX, s.ltX)
		minR, maxR = math.min(minR, s.roll), math.max(maxR, s.roll)
		minU, maxU = math.min(minU, s.utX), math.max(maxU, s.utX)
		minH, maxH = math.min(minH, s.headX), math.max(maxH, s.headX)
	end
	-- roughness: the most any trunk / head angle or offset changes over 1/60 s (frame to frame at 60 Hz, four frames at
	-- 240 Hz), and the RMS of it, over the steady walk: a gait's own motion changes smoothly, a jitter does not
	local jit = { n = 0, nan = false }
	do
		local KEYS_J = { pitch = "deg", roll = "deg", yaw = "deg", headPitch = "deg", headRoll = "deg", chestPitch = "deg", headX = "stud", ltX = "stud", ltY = "stud" }
		local sq = {}
		for k in pairs(KEYS_J) do
			jit[k] = 0
			sq[k] = 0
		end
		local j = 1
		for i = 2, #trace do
			local s = trace[i]
			for k in pairs(KEYS_J) do
				if s[k] ~= s[k] then
					jit.nan = true
				end
			end
			while j < i and trace[j + 1].t <= s.t - 1 / 60 + 1e-6 do
				j += 1
			end
			local p = trace[j]
			if p.t <= s.t - 1 / 60 + 1e-6 then
				jit.n += 1
				for k, unit in pairs(KEYS_J) do
					local d = math.abs(s[k] - p[k])
					if unit == "deg" then
						d = math.deg(d)
					end
					jit[k] = math.max(jit[k], d)
					sq[k] += d * d
				end
			end
		end
		for k in pairs(KEYS_J) do
			jit[k .. "Rms"] = jit.n > 0 and r4(math.sqrt(sq[k] / jit.n)) or 0
			jit[k] = r4(jit[k])
		end
	end
	-- the sensed speed over the steady stretch: its peak over the true pace and its largest frame-to-frame step
	local spdMax, spdStep, spdMin, prevS = 0, 0, math.huge, nil
	for _, smp in ipairs(S) do
		local sv = smp.sensed or 0
		spdMax, spdMin = math.max(spdMax, sv), math.min(spdMin, sv)
		if prevS then
			spdStep = math.max(spdStep, math.abs(sv - prevS))
		end
		prevS = sv
	end
	local rec = { clip = clip, tier = tier, speed = speed, period = r4(period), pelvisSwayX = r4(maxX - minX), chestSwayX = r4(maxU - minU),
		headSwayX = r4(maxH - minH), pelvisRollDeg = r4(math.deg(maxR - minR)), hipHeight = r4(hum.HipHeight), worstPen = {}, timing = timing,
		jitter = jit, frames = nSteps, sensedMax = r4(spdMax), sensedMin = r4(spdMin), sensedStep = r4(spdStep), npc = NPC or nil }
	-- record NFRAMES frames over one more cycle
	local out = { clip = clip, tier = tier, speed = speed, frames = {} }
	local nCycle = math.max(1, math.floor(period / nominal + 0.5))
	local every = nCycle / NFRAMES
	local nextAt = 0
	local worst = { n = 0, deep = 0 }
	for k = 0, nCycle - 1 do
		local fdt, pdt = tick()
		t += fdt
		z -= v * pdt
		hrp.CFrame = CFrame.new(0, y0, z)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, -v)
		frame({ model }, fdt)
		local pr = {}
		if not NOPEN then
			partPen(model, pr)
		end
		do
			local ltp = model:FindFirstChild("LowerTorso")
			for _, sd in ipairs({ "Left", "Right" }) do
				local ul = model:FindFirstChild(sd .. "UpperLeg")
				local d = ltp.CFrame:VectorToObjectSpace(-ul.CFrame.UpVector)
				local flex = math.deg(math.atan2(-d.Z, -d.Y)) -- + = knee forward
				local abd = math.deg(math.atan2(d.X * (sd == "Right" and 1 or -1), -d.Y))
				rec.hipFlexMin = math.min(rec.hipFlexMin or 999, flex)
				rec.hipFlexMax = math.max(rec.hipFlexMax or -999, flex)
				rec.hipAbdMin = math.min(rec.hipAbdMin or 999, abd)
				rec.hipAbdMax = math.max(rec.hipAbdMax or -999, abd)
			end
		end
		for _, key in ipairs({ "LeftPelvisInThigh", "RightPelvisInThigh" }) do
			if pr[key] and pr[key].deep > worst.deep then
				worst = { n = pr[key].n, deep = pr[key].deep, key = key, phase = r4(k / nCycle) }
			end
		end
		if k >= nextAt - 1e-6 and #out.frames < NFRAMES then
			nextAt += every
			local fr = NOMESH and { t = r4(t) } or exportFrame(model, t)
			fr.root = cfList(hrp.CFrame)
			fr.pen = pr
			table.insert(out.frames, fr)
		end
	end
	rec.worstPen = worst
	rec.animate = { disabled = animate.Disabled == true, playing = #animator:GetPlayingAnimationTracks(), started = started,
		procAnim = model:GetAttribute("ProcAnim") == true }
	-- the self-check: how the rig ended up driven, its joints, the stock tracks a keyframe fallback loaded, the log
	do
		local AR = H.require("AnimRig")
		local RJ = H.require("RigJoints")
		local nm, na = RJ.Count(model)
		local walkW = 0
		for _, tr in ipairs(loaded) do
			if tostring(tr.id):find("507777826") then
				walkW = tr.weight
			end
		end
		local rg = AR.rigs[model]
		rec.selfCheck = { fallback = AR.fallbackOf and AR.fallbackOf(model) or nil, motor6d = nm, ac = na, loaded = #loaded, walkWeight = walkW,
			writesOk = rg and rg.writesOk == true or false, localMotors = rg and rg.localMotors == true or false, log = table.clone(ANIM_LOG),
			ignore = IGNORE, animateOn = animate.Disabled == false }
		print(string.format("      self-check: fallback %s, joints Motor6D %d / AC %d, writes verified %s, stock tracks loaded %d (walk weight %.2f)",
			tostring(rec.selfCheck.fallback), nm, na, tostring(rec.selfCheck.writesOk), #loaded, walkW))
		for _, l in ipairs(ANIM_LOG) do
			print("      log: " .. l)
		end
	end
	if timing == "steady" then
		-- released (climbing): Roblox's animation back; on the ground again: off again
		local HSTe = roblox.Enum.HumanoidStateType
		hum.GetState = function()
			return HSTe.Climbing
		end
		for _ = 1, 20 do
			frame({ model })
		end
		playTrack()
		rec.animate.climbEnabled = animate.Disabled == false and model:GetAttribute("ProcAnim") == nil
		rec.animate.climbPlaying = #animator:GetPlayingAnimationTracks()
		hum.GetState = function()
			return STATE.Running
		end
		for _ = 1, 20 do
			frame({ model })
		end
		rec.animate.backDisabled = animate.Disabled == true and #animator:GetPlayingAnimationTracks() == 0
	end
	rec.gait = gaitSummary(S)
	if clip == "shift" then
		rec.shift = gaitSummary((function()
			local o = {}
			for _, x in ipairs(SALL) do
				if x.t > SHIFT_AT and x.t <= SHIFT_AT + 1.5 then
					table.insert(o, x)
				end
			end
			return o
		end)())
		rec.diag = Diag.SampleLines(DS)
		for _, l in ipairs(rec.diag.lines) do
			print("      diag " .. l)
		end
		for _, l in ipairs(rec.diag.verdicts) do
			print("      diag " .. l)
		end
	end
	-- the feet's contacts (a sole within 0.03 of the floor) from the switch on (else from 2.5 s): every touchdown and
	-- toe-off, in order, and the rig as the Animator measured it
	do
		local from = clip == "shift" and SHIFT_AT or 2.5
		local ev, down = {}, {}
		for _, x in ipairs(SALL) do
			if x.t > from then
				for _, k in ipairs({ "L", "R" }) do
					local d = x["sole" .. k] < 0.03
					if down[k] ~= nil and d ~= down[k] then
						table.insert(ev, { t = r4(x.t), s = k, down = d })
					end
					down[k] = d
				end
			end
		end
		rec.contacts = ev
		local rg = H.require("AnimRig").rigs[model]
		local g = rg and rg.geo or {}
		rec.legLen, rec.lod = g.legLen and r4(g.legLen), rg and rg.lod
		print(string.format("      rig: HipHeight %.2f legLen %.2f hipW %.2f lod %s", hum.HipHeight, g.legLen or -1, g.hipW or -1, tostring(rg and rg.lod)))
	end
	rec.start = gaitSummary((function()
		local o = {}
		for _, x in ipairs(SALL) do
			if x.t > 0.9 and x.t <= 2.5 then
				table.insert(o, x)
			end
		end
		return o
	end)())
	do
		local g = rec.gait
		local function rg(k)
			return g[k][2] - g[k][1]
		end
		print(string.format("      knee %.0f..%.0f  hip %.0f..%.0f  thigh %.0f..%.0f  ankle %.0f..%.0f  footPitch %.0f..%.0f", g.kneeL[1], g.kneeL[2],
			g.hipL[1], g.hipL[2], g.thighL[1], g.thighL[2], g.ankleL[1], g.ankleL[2], g.footPitchL[1], g.footPitchL[2]))
		print(string.format("      shoulder %.0f..%.0f  elbow %.0f..%.0f  wrist %.0f..%.0f  pelvisYaw %.1f..%.1f  chestYaw %.1f..%.1f  trunkPitch %.1f..%.1f",
			g.shoulderL[1], g.shoulderL[2], g.elbowL[1], g.elbowL[2], g.wristL[1], g.wristL[2], g.pelvisYaw[1], g.pelvisYaw[2], g.chestYaw[1],
			g.chestYaw[2], g.trunkPitch[1], g.trunkPitch[2]))
		print(string.format("      bob pelvis %.3f head %.3f  head pitch %.1f..%.1f roll %.1f..%.1f  sole %.3f..%.3f  slide L %.3f R %.3f (max %.2f studs/s)  start slide %.3f/%.3f sink %.3f",
			rg("pelvisY"), rg("headY"), g.headPitch[1], g.headPitch[2], g.headRoll[1], g.headRoll[2], g.soleL[1], g.soleL[2], g.slideL, g.slideR,
			g.slideMaxSpeed, rec.start.slideL, rec.start.slideR, math.min(g.sinkMin, rec.start.sinkMin)))
	end
	do
		local ser = seriesOf(SALL)
		Host.WriteJSON(string.format("%s/gait_%s_t%d%s%s.json", OUT, clip, tier, HTAG, TTAG), { clip = clip, tier = tier, speed = speed, height = HEIGHT,
			period = rec.period, summary = rec.gait, start = rec.start, series = ser, timing = timing })
	end
	print(string.format("      hip flex %.0f..%.0f deg, abduction %.0f..%.0f deg", rec.hipFlexMin, rec.hipFlexMax, rec.hipAbdMin, rec.hipAbdMax))
	print(string.format("      Animate: %s, %d tracks playing (%d started), ProcAnim %s%s", rec.animate.disabled and "disabled" or "ENABLED",
		rec.animate.playing, rec.animate.started, tostring(rec.animate.procAnim), timing == "steady" and string.format(", climbing: %s, back: %s",
		rec.animate.climbEnabled and "enabled" or "STILL OFF", rec.animate.backDisabled and "disabled" or "STILL ON") or ""))
	print(string.format("      timing %s (%d frames): roughness per 1/60 s  trunk pitch %.2f (rms %.3f) roll %.2f yaw %.2f  head pitch %.2f roll %.2f  pelvis x %.4f y %.4f  head x %.4f%s  sensed speed %.2f..%.2f (step %.2f)",
		timing, nSteps, jit.pitch, jit.pitchRms, jit.roll, jit.yaw, jit.headPitch, jit.headRoll, jit.ltX, jit.ltY, jit.headX, jit.nan and "  NaN!" or "",
		spdMin, spdMax, spdStep))
	local file = string.format("%s_t%d%s%s.json", clip, tier, HTAG, TTAG)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("%s_t%d%s%s", clip, tier, HTAG, TTAG), file = file, clip = clip, tier = tier, n = #out.frames, timing = timing })
	rec.height = HEIGHT
	table.insert(metrics, rec)
	print(string.format("%-5s T%d v=%4.1f period %.3f  pelvis sway %.3f  chest sway %.3f  head sway %.3f  pelvis roll %.1f deg  hip %.3f  worst pelvis-in-thigh %d verts %.3f (%s @%.2f)",
		clip, tier, speed, period, rec.pelvisSwayX, rec.chestSwayX, rec.headSwayX, rec.pelvisRollDeg, rec.hipHeight, worst.n, worst.deep,
		tostring(worst.key), worst.phase or 0))
	if NPC then
		CS:RemoveTag(model, "Ambient")
	else
		player.Character = nil
	end
	model:Destroy()
	for _ = 1, 3 do
		frame({})
	end
end

------------------------------------------------------------------------
-- scripted clips: start / stop, turning in place, a walking turn. The root moves along its own facing at
-- speed(t), turning at yawRate(t) (rad/s, + = left); every frame sampled, frames recorded at the given times
------------------------------------------------------------------------
local SCRIPTS = {
	startstop = { total = 4.6, shots = { 0.95, 1.05, 1.15, 1.25, 1.35, 1.45, 1.55, 1.7, 2.95, 3.05, 3.15, 3.25, 3.35, 3.5, 3.7, 4.0, 4.5 }, speed = function(t)
		local W = SPEEDS.walk
		if t < 1 then
			return 0
		-- (a Humanoid on the ground gets to its WalkSpeed and back to rest in a few frames: a 0.12 s ramp)
		elseif t < 1.12 then
			return W * (t - 1) / 0.12
		elseif t < 3 then
			return W
		elseif t < 3.12 then
			return W * (1 - (t - 3) / 0.12)
		end
		return 0
	end, yaw = function()
		return 0
	end },
	turn = { total = 3.4, shots = { 0.95, 1.1, 1.25, 1.4, 1.55, 1.7, 1.85, 2.0, 2.2, 2.5, 2.9, 3.3 }, speed = function()
		return 0
	end, yaw = function(t)
		return (t > 1 and t < 1 + PI / 3.5) and 3.5 or 0
	end },
	curve = { total = 4.4, shots = { 1.8, 1.95, 2.1, 2.25, 2.4, 2.55, 2.7, 2.85, 3.0, 3.15, 3.3, 3.45 }, speed = function(t)
		return t < 1 and 0 or SPEEDS.walk * math.min(1, (t - 1) / 0.12)
	end, yaw = function(t)
		return (t > 1.8 and t < 1.8 + (PI / 2) / 1.6) and 1.6 or 0
	end },
	-- a player on WASD: the Humanoid's AutoRotate snaps the root round at ~18 rad/s (a quarter turn in 0.09 s) on every
	-- change of direction, and a reversal (W to S) spins it half way round; the body must take them as the pivots they
	-- are, never bank or twist as if into a held turn
	snapturn = { total = 5.4, shots = { 1.75, 1.85, 1.95, 2.1, 2.3, 2.55, 2.65, 2.75, 2.9, 4.15, 4.3, 4.45, 4.6, 4.9 }, speed = function(t)
		return t < 1 and 0 or SPEEDS.walk * math.min(1, (t - 1) / 0.12)
	end, yaw = function(t)
		local W = 18
		local q = (PI / 2) / W
		if (t > 1.8 and t < 1.8 + q) or (t > 3.4 and t < 3.4 + q) then
			return W
		elseif t > 2.6 and t < 2.6 + q then
			return -W
		elseif t > 4.2 and t < 4.2 + 2 * q then
			return W
		end
		return 0
	end },
}
local function scriptClip(clip, tier)
	local sc = SCRIPTS[clip]
	local model, hum = makeBoxer(tier)
	model.Name = "Walker"
	player.Character = model
	player.CharacterAdded:Fire(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local y0 = hrp.CFrame.Y
	local sample = gaitSampler(model)
	local x, z, yaw = 0, 0, 0
	local S = {}
	local out = { clip = clip, tier = tier, frames = {} }
	local shot = 1
	local maxJ = { knee = 0, hip = 0, shoulder = 0, elbow = 0, pelvisY = 0, headY = 0, trunkRoll = 0, headYaw = 0, twist = 0, trunkPitch = 0 }
	for i = 1, math.floor(sc.total / DT) do
		local t = i * DT
		local v, yr = sc.speed(t), sc.yaw(t)
		yaw += yr * DT
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		x += fx * v * DT
		z += fz * v * DT
		hrp.CFrame = CFrame.new(x, y0, z) * CFrame.Angles(0, yaw, 0)
		hrp.AssemblyLinearVelocity = Vector3.new(fx * v, 0, fz * v)
		hrp.AssemblyAngularVelocity = Vector3.new(0, yr, 0)
		hum.MoveDirection = v > 0.05 and Vector3.new(fx, 0, fz) or Vector3.zero
		frame({ model })
		local smp = sample(t)
		smp.v = v
		if args.debugrig and t > tonumber(args.debugrig) and t < tonumber(args.debugrig) + 0.3 then
			local rg = H.require("AnimRig").rigs[model]
			for _, sd in ipairs({ "L", "R" }) do
				local f = rg and rg.foot[sd]
				if f then
					print(string.format("dbg %.3f %s swing=%s push=%s sigma=%.2f pitch=%.2f knee=%.0f reachShort=%.3f excess=%.3f need=%.3f drop=%.3f run=%.2f",
						t, sd, tostring(f.swing), tostring(f.push), f.sigma or -1, f.pitchS or 0, smp["knee" .. sd], f.reachShort or 0, f.excess or 0,
						f.needDrop or -1, rg.loco.drop or 0, rg.loco.run))
				end
			end
		end
		local pv = S[#S]
		if pv then
			for k, key in pairs({ knee = "knee", hip = "hip", shoulder = "shoulder", elbow = "elbow" }) do
				for _, sd in ipairs({ "L", "R" }) do
					maxJ[k] = math.max(maxJ[k], math.abs(smp[key .. sd] - pv[key .. sd]))
				end
			end
			maxJ.pelvisY = math.max(maxJ.pelvisY, math.abs(smp.pelvisY - pv.pelvisY))
			maxJ.headY = math.max(maxJ.headY, math.abs(smp.headY - pv.headY))
			for _, k in ipairs({ "trunkRoll", "headYaw", "twist", "trunkPitch" }) do
				maxJ[k] = math.max(maxJ[k], math.abs(smp[k] - pv[k]))
			end
		end
		table.insert(S, smp)
		local every = tonumber(args.shotevery)
		if every then
			-- (--shotevery N: a frame every N frames from 0.9 s on - an even clock for a GIF)
			if t > 0.9 and i % every == 0 then
				local fr = NOMESH and { t = r4(t) } or exportFrame(model, t)
				fr.root = cfList(hrp.CFrame)
				fr.label = string.format("%.2f s  v %.1f", t, v)
				table.insert(out.frames, fr)
			end
		elseif sc.shots[shot] and t >= sc.shots[shot] - 1e-6 then
			shot += 1
			local fr = NOMESH and { t = r4(t) } or exportFrame(model, t)
			fr.root = cfList(hrp.CFrame)
			fr.label = string.format("%.2f s  v %.1f", t, v)
			table.insert(out.frames, fr)
		end
	end
	local g = gaitSummary(S)
	local rec = { clip = clip, tier = tier, height = HEIGHT, gait = g, maxFrameStep = {} }
	Host.WriteJSON(string.format("%s/gait_%s_t%d%s.json", OUT, clip, tier, HTAG), { clip = clip, tier = tier, height = HEIGHT, summary = g,
		series = seriesOf(S) })
	for k, v in pairs(maxJ) do
		rec.maxFrameStep[k] = r4(v)
	end
	print(string.format("%-9s T%d  slide L %.3f R %.3f  sink %.3f  max per-frame step: knee %.1f hip %.1f shoulder %.1f elbow %.1f deg, pelvis %.3f head %.3f",
		clip, tier, g.slideL, g.slideR, g.sinkMin, maxJ.knee, maxJ.hip, maxJ.shoulder, maxJ.elbow, maxJ.pelvisY, maxJ.headY))
	print(string.format("      trunk roll %.1f..%.1f pitch %.1f..%.1f  head yaw %.1f..%.1f  chest-pelvis twist %.1f..%.1f  pelvis yaw %.1f..%.1f deg; per frame: roll %.2f yaw %.2f twist %.2f",
		g.trunkRoll[1], g.trunkRoll[2], g.trunkPitch[1], g.trunkPitch[2], g.headYaw[1], g.headYaw[2], g.twist[1], g.twist[2], g.pelvisYaw[1], g.pelvisYaw[2],
		maxJ.trunkRoll, maxJ.headYaw, maxJ.twist))
	local file = string.format("%s_t%d%s.json", clip, tier, HTAG)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("%s_t%d%s", clip, tier, HTAG), file = file, clip = clip, tier = tier, n = #out.frames })
	table.insert(metrics, rec)
	player.Character = nil
	model:Destroy()
	for _ = 1, 3 do
		frame({})
	end
end

------------------------------------------------------------------------
-- strafing clips: the body kept facing -Z (Shift Lock / first person; a boxer facing his man) while he goes off to the
-- side, on the diagonals and backward, the direction flipping (D -> A, W -> A); the Humanoid's velocity reaches the new
-- direction in about a tenth of a second. strafe = the town walk (6.5), strafe16 = Shift (16), strafering = a Fighter's
-- footwork in the stance (the shuffle), strafeturn = AutoRotate on: the root turns toward the new way at a Humanoid's
-- ~18 rad/s, so for a moment he moves sideways to his facing. Under every --timing. Metrics per segment (its steady
-- part, from 0.9 s in) and per change of direction (the 0.7 s after it): the feet's lateral offsets from the pelvis
-- (crossing), the planted feet's slide, the pelvis' roll and sway, the contacts, the hip's flexion / abduction, and the
-- largest change of a joint angle in a frame (scaled to 1/60 s)
------------------------------------------------------------------------
local DIRS = { D = { 1, 0 }, A = { -1, 0 }, W = { 0, -1 }, S = { 0, 1 }, WD = { 0.7071, -0.7071 }, WA = { -0.7071, -0.7071 },
	SA = { -0.7071, 0.7071 }, SD = { 0.7071, 0.7071 } }
local STRAFES = {
	strafe = { speed = "walk", segs = { { 1, "D" }, { 3.4, "A" }, { 5.8, "WD" }, { 7.6, "W" }, { 9.0, "A" }, { 10.6, "SA" }, { 12.2, "D" }, { 13.8 } } },
	strafe16 = { speed = "run", segs = { { 1, "D" }, { 3.4, "A" }, { 5.8, "WD" }, { 7.6, "W" }, { 9.0, "A" }, { 10.6, "SA" }, { 12.2, "D" }, { 13.8 } } },
	strafering = { speed = "ring", fighter = true, segs = { { 1, "D" }, { 3.0, "A" }, { 5.0, "D" }, { 7.0, "WA" }, { 8.6, "A" }, { 10.2 } } },
	strafeturn = { speed = "walk", autorot = true, segs = { { 1, "W" }, { 2.6, "D" }, { 4.2, "A" }, { 5.8, "W" }, { 7.4, "SA" }, { 9.0 } } },
}
SPEEDS.ring = SPEEDS.ring or 6
local function strafeClip(clip, tier, timing)
	local sc = STRAFES[clip]
	local tick = timingOf(timing)
	local TTAG = timing ~= "steady" and ("_" .. timing) or ""
	local model, hum = makeBoxer(tier)
	model.Name = "Walker"
	if sc.fighter then
		model:SetAttribute("Guard", "stance")
		model:SetAttribute("Style", "BoxerPuncher")
		model:SetAttribute("Stam", 1)
		CS:AddTag(model, "Fighter")
	end
	player.Character = model
	player.CharacterAdded:Fire(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local lt = model:FindFirstChild("LowerTorso")
	local y0 = hrp.CFrame.Y
	local sample = gaitSampler(model)
	local speed = SPEEDS[sc.speed]
	local segs = sc.segs
	local total = segs[#segs][1] + 1
	local x, z, yaw, vx, vz = 0, 0, 0, 0, 0
	local S = {}
	local t = 0
	local function segAt(tt)
		local k = 0
		for i, s in ipairs(segs) do
			if tt >= s[1] then
				k = i
			end
		end
		return k
	end
	while t < total do
		local fdt, pdt = tick()
		t += fdt
		local si = segAt(t)
		local d = si > 0 and segs[si][2] and DIRS[segs[si][2]]
		-- (the wanted way in the body's frame; AutoRotate: in the world, the root turning toward it)
		local tx, tz = 0, 0
		if d then
			tx, tz = d[1] * speed, d[2] * speed
		end
		local kv = 1 - math.exp(-fdt * 30)
		vx += (tx - vx) * kv
		vz += (tz - vz) * kv
		local yr = 0
		if sc.autorot and (tx ~= 0 or tz ~= 0) then
			local want = math.atan2(-tx, -tz)
			local e = ((want - yaw + PI) % (2 * PI)) - PI
			yr = math.clamp(e / fdt, -18, 18)
			yaw += yr * fdt
		end
		x += vx * pdt
		z += vz * pdt
		hrp.CFrame = CFrame.new(x, y0, z) * CFrame.Angles(0, yaw, 0)
		hrp.AssemblyLinearVelocity = Vector3.new(vx, 0, vz)
		hrp.AssemblyAngularVelocity = Vector3.new(0, yr, 0)
		local vm = math.sqrt(vx * vx + vz * vz)
		hum.MoveDirection = (tx ~= 0 or tz ~= 0) and Vector3.new(tx, 0, tz).Unit or Vector3.zero
		E.camera.CFrame = CFrame.new(x, y0 + 3, z + 10)
		frame({ model }, fdt)
		local smp = sample(t)
		smp.v, smp.fdt, smp.seg = vm, fdt, si
		-- (the feet's offsets across the pelvis: in its own frame, levelled - on a diagonal it turns toward the way he goes)
		local rcf = hrp.CFrame
		local lk = lt.CFrame.LookVector
		local pcf = CFrame.lookAt(lt.Position, lt.Position + Vector3.new(lk.X, 0, lk.Z))
		local aL, aR = pcf:PointToObjectSpace(smp.anklePL), pcf:PointToObjectSpace(smp.anklePR)
		smp.xL, smp.xR, smp.pelX = aL.X, aR.X, rcf:PointToObjectSpace(lt.Position).X
		local rel = rcf:Inverse() * lt.CFrame
		local _, _, rz = rel:ToOrientation()
		smp.pRoll = math.deg(rz)
		for _, sd in ipairs({ "Left", "Right" }) do
			local ul = model:FindFirstChild(sd .. "UpperLeg")
			local dd = lt.CFrame:VectorToObjectSpace(-ul.CFrame.UpVector)
			smp["abd" .. sd:sub(1, 1)] = math.deg(math.atan2(dd.X * (sd == "Right" and 1 or -1), -dd.Y))
			-- (the foot turned against the shin: the toes pointing where the knee does, never twisted round it)
			-- (their hinge axes, the RightVectors: level whatever the foot's roll onto the toes or the shin's lean)
			local sl, fl = model:FindFirstChild(sd .. "LowerLeg").CFrame.RightVector, model:FindFirstChild(sd .. "Foot").CFrame.RightVector
			smp["twist" .. sd:sub(1, 1)] = math.deg(math.abs(((math.atan2(fl.Z, fl.X) - math.atan2(sl.Z, sl.X) + 3 * PI) % (2 * PI)) - PI))
		end
		table.insert(S, smp)
		if args.debugrig and t > tonumber(args.debugrig) and t < tonumber(args.debugrig) + (tonumber(args.debugwin) or 0.12) then
			local rg = H.require("AnimRig").rigs[model]
			local lo = rg and rg.loco
			if lo then
				print(string.format("dbg %.3f loco moving %s run %.2f side %.2f sideK %.2f lead %s offR %.2f T %.3f duty %.2f phase %.3f legYaw %.2f sideA %.2f sideB %.2f lv %s",
					t, tostring(lo.moving), lo.run, lo.side, lo.sideK or -1, tostring(lo.sideLead or lo.lead), lo.offR or -1, lo.T or -1, lo.duty or -1,
					lo.phase or -1, lo.legYaw or 0, lo.sideA or -1, lo.sideB or -1, tostring(lo.lv)))
			end
			for _, sd in ipairs({ "L", "R" }) do
				local f = rg and rg.foot[sd]
				if f then
					if f.dbgT then
						print("   tgt stages", sd, tostring(f.dbgT.base), tostring(f.dbgT.side), tostring(f.dbgT.gap), tostring(f.dbgT.aim))
					end
					print(string.format("dbg %.3f %s yawW %.0f home %.0f cur %.0f swing=%s kind=%s u=%.2f P=%s cur=%s tgt=%s push=%s sole=%.3f", t, sd, math.deg(f.yawW), math.deg(f.homeYaw or 0), math.deg(f.curYaw or 0), tostring(f.swing), tostring(f.stepKind),
						(t - f.t0) / f.dur, tostring(f.P), tostring(f.cur), tostring(f.tgtW), tostring(f.push), smp["sole" .. sd]))
				end
			end
		end
		-- (--dump A,B: the strafe's per-frame numbers between A and B s)
		local da, db = (args.dump or ""):match("([%d%.]+),([%d%.]+)")
		if da and t >= tonumber(da) and t <= tonumber(db) then
			print(string.format("dump %.3f yaw %.0f tw %.0f/%.0f v %.2f xL %.2f xR %.2f pelX %.3f roll %.1f soleL %.2f soleR %.2f abd %.0f/%.0f hip %.0f/%.0f knee %.0f/%.0f pelY %.3f",
				t, math.deg(yaw), smp.twistL, smp.twistR, vm, smp.xL, smp.xR, smp.pelX, smp.pRoll, smp.soleL, smp.soleR, smp.abdL, smp.abdR, smp.hipL, smp.hipR, smp.kneeL, smp.kneeR, smp.pelvisY))
		end
	end
	local function window(a, b)
		local o = {}
		for _, s in ipairs(S) do
			if s.t > a and s.t <= b then
				table.insert(o, s)
			end
		end
		return o
	end
	local function feetOf(W)
		local gapMin, xLmax, xRmin = math.huge, -math.huge, math.huge
		local rMin, rMax, pxMin, pxMax = math.huge, -math.huge, math.huge, -math.huge
		local abd, flex = { math.huge, -math.huge }, { math.huge, -math.huge }
		local twist = 0
		for _, s in ipairs(W) do
			twist = math.max(twist, s.twistL, s.twistR)
			gapMin = math.min(gapMin, s.xR - s.xL)
			xLmax, xRmin = math.max(xLmax, s.xL), math.min(xRmin, s.xR)
			rMin, rMax = math.min(rMin, s.pRoll), math.max(rMax, s.pRoll)
			pxMin, pxMax = math.min(pxMin, s.pelX), math.max(pxMax, s.pelX)
			for _, k in ipairs({ "L", "R" }) do
				abd[1], abd[2] = math.min(abd[1], s["abd" .. k]), math.max(abd[2], s["abd" .. k])
				flex[1], flex[2] = math.min(flex[1], s["hip" .. k]), math.max(flex[2], s["hip" .. k])
			end
		end
		return { gapMin = r4(gapMin), xLmax = r4(xLmax), xRmin = r4(xRmin), rollRange = r4(rMax - rMin), roll = { r4(rMin), r4(rMax) },
			swayX = r4(pxMax - pxMin), abd = { r4(abd[1]), r4(abd[2]) }, flex = { r4(flex[1]), r4(flex[2]) }, footTwist = r4(twist) }
	end
	local function contactsOf(W)
		-- (down under 0.02 studs, up over 0.045: a sole skimming a centimetre over the floor is no step)
		local ev, down = {}, {}
		for _, s in ipairs(W) do
			for _, k in ipairs({ "L", "R" }) do
				local h = s["sole" .. k]
				local dn = down[k]
				if dn == nil then
					dn = h < 0.03
				elseif dn and h > 0.045 then
					dn = false
				elseif not dn and h < 0.02 then
					dn = true
				end
				if down[k] ~= nil and dn ~= down[k] then
					table.insert(ev, { t = r4(s.t), s = k, down = dn })
				end
				down[k] = dn
			end
		end
		-- (a foot back down within 0.04 s of leaving the floor bounced - a scuff, not a step)
		local td, lastUp = {}, {}
		for _, e in ipairs(ev) do
			if e.down then
				if not (lastUp[e.s] and e.t - lastUp[e.s] < 0.04 and #td > 0) then
					table.insert(td, e)
				end
			else
				lastUp[e.s] = e.t
			end
		end
		local alt, steps = true, {}
		for i = 2, #td do
			alt = alt and td[i].s ~= td[i - 1].s
			table.insert(steps, td[i].t - td[i - 1].t)
		end
		local lo, hi = math.huge, 0
		for _, d in ipairs(steps) do
			lo, hi = math.min(lo, d), math.max(hi, d)
		end
		-- (each foot's own touchdowns: a regular stride, whatever the rhythm between the two - a gallop's is uneven)
		local last, sLo, sHi = {}, math.huge, 0
		for _, e in ipairs(td) do
			if last[e.s] then
				sLo, sHi = math.min(sLo, e.t - last[e.s]), math.max(sHi, e.t - last[e.s])
			end
			last[e.s] = e.t
		end
		local firstUp
		for _, e in ipairs(ev) do
			if not e.down then
				firstUp = e.s
				break
			end
		end
		return { n = #td, alternating = alt, stepMin = r4(#steps > 0 and lo or 0), stepMax = r4(hi), strideMin = r4(sHi > 0 and sLo or 0),
			strideMax = r4(sHi), firstUp = firstUp }
	end
	local KEYS_P = { "kneeL", "kneeR", "hipL", "hipR", "abdL", "abdR", "pRoll", "trunkRoll", "trunkPitch" }
	local function popsOf(W)
		local o = { pelvisY = 0 }
		for _, k in ipairs(KEYS_P) do
			o[k] = 0
		end
		for i = 2, #W do
			local a, b = W[i - 1], W[i]
			local sc60 = (1 / 60) / math.max(b.fdt, 1 / 240)
			for _, k in ipairs(KEYS_P) do
				o[k] = math.max(o[k], math.abs(((b[k] - a[k] + 540) % 360) - 180) * math.min(sc60, 1))
			end
			o.pelvisY = math.max(o.pelvisY, math.abs(b.pelvisY - a.pelvisY) * math.min(sc60, 1))
		end
		for k, v in pairs(o) do
			o[k] = r4(v)
		end
		return o
	end
	local rec = { clip = clip, tier = tier, timing = timing, speed = speed, height = HEIGHT, segs = {}, flips = {} }
	for i, s in ipairs(segs) do
		local t1 = segs[i + 1] and segs[i + 1][1] or total
		local name = s[2] or "stop"
		if s[2] then
			local W = window(s[1] + 0.9, t1)
			local g = gaitSummary(W)
			local seg = feetOf(W)
			seg.dir, seg.t0, seg.t1 = name, s[1], t1
			seg.slideL, seg.slideR = g.slideL, g.slideR
			seg.knee = { math.min(g.kneeL[1], g.kneeR[1]), math.max(g.kneeL[2], g.kneeR[2]) }
			seg.pelvisY = g.pelvisY
			seg.trunkRoll, seg.trunkPitch = g.trunkRoll, g.trunkPitch
			seg.contacts = contactsOf(W)
			seg.pops = popsOf(W)
			table.insert(rec.segs, seg)
		end
		if i > 1 then
			local W = window(s[1] - 0.05, s[1] + 0.7)
			local g = gaitSummary(W)
			local fl = feetOf(W)
			fl.from, fl.to, fl.t = segs[i - 1][2], name, s[1]
			fl.slideL, fl.slideR = g.slideL, g.slideR
			fl.pops = popsOf(W)
			-- (from the moment the way he goes has turned over: the Humanoid's velocity takes ~0.1 s)
			fl.contacts = contactsOf(window(s[1] + 0.06, s[1] + 0.7))
			table.insert(rec.flips, fl)
		end
	end
	rec.pops = popsOf(window(0.9, total))
	print(string.format("%s T%d %s v=%.1f", clip, tier, timing, speed))
	for _, sg in ipairs(rec.segs) do
		print(string.format("   seg %-3s gap %.2f twist %.0f bob %.3f (xL max %.2f xR min %.2f)  slide %.3f/%.3f  roll %.1f..%.1f  sway %.3f  abd %.0f..%.0f  flex %.0f..%.0f  knee %.0f..%.0f  steps %d alt %s (%.2f..%.2f)  trunk roll %.1f..%.1f",
			sg.dir, sg.gapMin, sg.footTwist, sg.pelvisY[2] - sg.pelvisY[1], sg.xLmax, sg.xRmin, sg.slideL, sg.slideR, sg.roll[1], sg.roll[2], sg.swayX, sg.abd[1], sg.abd[2], sg.flex[1], sg.flex[2],
			sg.knee[1], sg.knee[2], sg.contacts.n, tostring(sg.contacts.alternating), sg.contacts.stepMin, sg.contacts.stepMax, sg.trunkRoll[1], sg.trunkRoll[2]))
		print(string.format("        steady per-frame: knee %.1f/%.1f hip %.1f/%.1f abd %.1f/%.1f", sg.pops.kneeL, sg.pops.kneeR, sg.pops.hipL, sg.pops.hipR, sg.pops.abdL, sg.pops.abdR))
	end
	for _, fl in ipairs(rec.flips) do
		local p = fl.pops
		print(string.format("   flip %s->%s gap %.2f twist %.0f slide %.3f/%.3f  roll %.1f..%.1f  pops knee %.1f/%.1f hip %.1f/%.1f abd %.1f/%.1f roll %.2f trunk %.2f/%.2f pelvisY %.3f",
			tostring(fl.from), fl.to, fl.gapMin, fl.footTwist, fl.slideL, fl.slideR, fl.roll[1], fl.roll[2], p.kneeL, p.kneeR, p.hipL, p.hipR, p.abdL, p.abdR, p.pRoll,
			p.trunkRoll, p.trunkPitch, p.pelvisY))
	end
	Host.WriteJSON(string.format("%s/gait_%s_t%d%s%s.json", OUT, clip, tier, HTAG, TTAG), { clip = clip, tier = tier, timing = timing, rec = rec,
		series = seriesOf(S) })
	table.insert(metrics, rec)
	if sc.fighter then
		CS:RemoveTag(model, "Fighter")
	end
	player.Character = nil
	model:Destroy()
	for _ = 1, 3 do
		frame({})
	end
end

------------------------------------------------------------------------
-- punches
------------------------------------------------------------------------
local PUNCH_LIST = {
	{ "jab", "jab|L|head|0.16|0.8" }, { "cross", "cross|R|head|0.2|0.9" }, { "leadhook", "leadhook|L|head|0.2|0.9" },
	{ "rearhook", "rearhook|R|head|0.22|0.9" }, { "uppercut", "uppercut|R|head|0.22|0.9" }, { "bodyjab", "jab|L|body|0.16|0.8" },
}
local function punchClip(tier)
	local a, humA = makeBoxer(tier)
	a.Name = "BoxerA"
	local b, humB = makeBoxer(3, { gloves = 2, trunks = 4 })
	b.Name = "BoxerB"
	local GAP = tonumber(args.gap) or 4.0
	local ha, hb = a:FindFirstChild("HumanoidRootPart"), b:FindFirstChild("HumanoidRootPart")
	ha.CFrame = CFrame.new(0, ha.CFrame.Y, GAP / 2) -- faces -Z (towards B)
	hb.CFrame = CFrame.new(0, hb.CFrame.Y, -GAP / 2) * CFrame.Angles(0, math.pi, 0)
	-- (--style / --pstyle / --seed: the puncher's swing - AnimFight.swing's Style, PunchStyle and AnimSeed; the clip
	-- id carries the style so two boxers' punches can be rendered side by side)
	local style = args.style or "BoxerPuncher"
	for _, m in ipairs({ a, b }) do
		m:SetAttribute("Guard", "up")
		m:SetAttribute("Style", "BoxerPuncher")
	end
	a:SetAttribute("Style", style)
	a:SetAttribute("PunchStyle", args.pstyle)
	if tonumber(args.seed) then
		a:SetAttribute("AnimSeed", tonumber(args.seed))
	end
	for _, m in ipairs({ a, b }) do
		CS:AddTag(m, "Fighter")
	end
	for _ = 1, 150 do
		frame({ a, b })
	end
	local clipId = string.format("punch%s_t%d", args.style and ("_" .. string.lower(style)) or "", tier)
	local out = { clip = "punch", tier = tier, frames = {} }
	local recs = {}
	local actId = 0
	for _, pd in ipairs(PUNCH_LIST) do
		local name, act = pd[1], pd[2]
		local hand = act:match("^[^|]*|(%a)")
		local handPart = a:FindFirstChild(hand == "L" and "LeftHand" or "RightHand")
		local glove
		for _, d in ipairs(a:GetDescendants()) do
			if (d.ClassName == "MeshPart" or d.ClassName == "Part") and d.Name == "Glove" .. hand then
				glove = d
			end
		end
		glove = glove or handPart
		actId += 1
		a:SetAttribute("Act", act)
		a:SetAttribute("ActId", actId)
		local best, bestK, samples = -math.huge, 0, {}
		local nF = 60
		local wmax = { 0, 0, 0 }
		for k = 1, nF do
			frame({ a, b })
			do
				local rel = a:FindFirstChild("LowerTorso").CFrame:Inverse() * a:FindFirstChild("UpperTorso").CFrame
				local rx, ry, rz = rel:ToEulerAnglesYXZ()
				wmax[1] = math.max(wmax[1], math.abs(math.deg(rx)))
				wmax[2] = math.max(wmax[2], math.abs(math.deg(ry)))
				wmax[3] = math.max(wmax[3], math.abs(math.deg(rz)))
			end
			-- reach: how far the glove went toward B (along -Z from A's root)
			local reach = -(glove.Position.Z - ha.Position.Z)
			samples[k] = { reach = reach, t = VT, gp = glove.Position }
			if reach > best then
				best, bestK = reach, k
			end
		end
		-- replay to capture: windup / mid / peak frames
		actId += 1
		for _ = 1, 40 do
			frame({ a, b })
		end
		a:SetAttribute("Act", act)
		a:SetAttribute("ActId", actId)
		local capture = { [math.max(1, math.floor(bestK * 0.2))] = "start", [math.max(1, math.floor(bestK * 0.45))] = "windup",
			[math.max(1, math.floor(bestK * 0.7))] = "drive", [math.max(1, math.floor(bestK * 0.87))] = "extend", [bestK] = "peak",
			[math.min(nF, bestK + math.max(3, math.floor(bestK * 0.5)))] = "return" }
		local peakPen
		for k = 1, nF do
			frame({ a, b })
			if capture[k] then
				local fr = NOMESH and { t = r4(VT) } or exportFrame(a, VT)
				fr.label = name .. " " .. capture[k]
				fr.opp = (not NOMESH) and exportFrame(b, VT) or nil
				table.insert(out.frames, fr)
				if capture[k] == "peak" then
					local headB = b:FindFirstChild("Head")
					local ut = b:FindFirstChild("UpperTorso")
					local tgt = act:find("|body|") and ut.Position or headB.Position
					peakPen = { glove = { r4(glove.Position.X), r4(glove.Position.Y), r4(glove.Position.Z) },
						toTarget = r4((glove.Position - tgt).Magnitude), dy = r4(glove.Position.Y - tgt.Y),
						elbowDeg = nil }
					-- elbow angle (upper vs lower arm axis)
					local ua = a:FindFirstChild(hand == "L" and "LeftUpperArm" or "RightUpperArm")
					local la = a:FindFirstChild(hand == "L" and "LeftLowerArm" or "RightLowerArm")
					peakPen.elbowDeg = r4(math.deg(math.acos(math.clamp(ua.CFrame.UpVector:Dot(la.CFrame.UpVector), -1, 1))))
				end
			end
		end
		for _ = 1, 40 do
			frame({ a, b })
		end
		table.insert(recs, { punch = name, reach = r4(best), peakFrame = bestK, peak = peakPen })
		print(string.format("      waist max |pitch| %.0f |yaw| %.0f |roll| %.0f deg", wmax[1], wmax[2], wmax[3]))
		print(string.format("punch T%d %-9s reach %.3f (frame %d)  glove->target %.3f  dy %+.3f  elbow %.0f deg", tier, name, best, bestK,
			peakPen and peakPen.toTarget or -1, peakPen and peakPen.dy or 0, peakPen and peakPen.elbowDeg or -1))
	end
	local file = clipId .. ".json"
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = clipId, file = file, clip = "punch", tier = tier, n = #out.frames })
	table.insert(metrics, { clip = "punch", tier = tier, punches = recs })
	for _, m in ipairs({ a, b }) do
		CS:RemoveTag(m, "Fighter")
		m:Destroy()
	end
	for _ = 1, 3 do
		frame({})
	end
end

------------------------------------------------------------------------
-- fight scenarios (--clips fight [--only id,id] [--every N]): two Fighters in an arena (a corner stool behind A,
-- a referee off to the side), every scenario scripted on the server's own act strings and attributes; per frame the
-- Motor6D Transforms the Animator wrote (the snaps: the largest one-frame turn of a joint and the largest one-frame
-- change of its turning speed, per joint group), the planted feet's slide, the joint-angle curves; at each punch's
-- contact (act start + windup, when the server lands it) the glove against the target
------------------------------------------------------------------------
local FIGHT_ONLY
if args.only then
	FIGHT_ONLY = {}
	for s in args.only:gmatch("[^,]+") do
		FIGHT_ONLY[s] = true
	end
end
local FIGHT_EVERY = tonumber(args.every) or 3
local MOTORS = { Root = "Root", W = "Waist", Neck = "Neck", LS = "LeftShoulder", LE = "LeftElbow", LW = "LeftWrist", RS = "RightShoulder",
	RE = "RightElbow", RW = "RightWrist", LH = "LeftHip", LK = "LeftKnee", LA = "LeftAnkle", RH = "RightHip", RK = "RightKnee", RA = "RightAnkle" }
local GROUP = { Root = "trunk", W = "trunk", Neck = "neck", LS = "arms", LE = "arms", LW = "arms", RS = "arms", RE = "arms", RW = "arms",
	LH = "legs", LK = "legs", LA = "legs", RH = "legs", RK = "legs", RA = "legs" }
local WIND = { jab = 0.16, cross = 0.24, leadhook = 0.26, rearhook = 0.3, uppercut = 0.3, overhand = 0.42 }
local function P(kind, hand, zone, w, pow, extra)
	return string.format("%s|%s|%s|%.2f|%s%s", kind, hand, zone or "head", w or WIND[kind], pow and string.format("%.2f", pow) or "", extra or "")
end
-- events: { t, who ("A" / "B" / "ref"), what, value }; what = "act" (Act + ActId), an attribute name, "move" (the
-- root glides: value = { dx, dz, dur, dyaw }), "hitA" (B's punch lands on A at t: value = the hit act)
local function punchAt(t, who, kind, hand, zone, w, chain)
	return { t, who, "act", P(kind, hand, zone, w, nil, chain and ("|" .. chain) or nil),
		punch = { kind = kind, hand = hand, zone = zone or "head", w = w or WIND[kind] } }
end
local SCEN = {}
local function scen(id, dur, ev, opt)
	opt = opt or {}
	opt.id, opt.dur, opt.ev = id, dur, ev
	table.insert(SCEN, opt)
end
-- guard and stance life
scen("guard", 4, {}, { subject = "A" })
scen("guard_outboxer", 3, {}, { style = "OutBoxer" })
scen("guard_swarmer", 3, {}, { style = "Swarmer" })
scen("guard_counter", 3, {}, { style = "CounterPuncher" })
scen("guard_tired", 3, { { 0, "A", "Stam", 0.15 } })
-- footwork
scen("footwork", 3.6, { { 0.3, "A", "move", { 0, -1.0, 0.45 } }, { 1.1, "A", "move", { 0, 1.0, 0.5 } }, { 1.9, "A", "move", { -1.0, 0, 0.45 } },
	{ 2.7, "A", "move", { 1.0, 0, 0.45 } } })
scen("pivot", 2.2, { { 0.4, "A", "act", "pivot|L" }, { 0.4, "A", "move", { 0, 0, 0.05, -0.6, pivot = true } } })
scen("clinch", 2.8, { { 0.2, "A", "Guard", "clinch" }, { 0.2, "B", "Guard", "clinch" }, { 0.2, "A", "move", { 0, -0.9, 0.3 } },
	{ 2.2, "A", "Guard", "stance" }, { 2.2, "B", "Guard", "stance" }, { 2.2, "A", "move", { 0, 0.9, 0.4 } } })
-- the feint (FightEngine's: a short, light jab) and inside work in the clinch (short body uppercuts)
scen("feint", 1.4, { { 0.4, "A", "act", "jab|L|head|0.12|0.20" }, { 0.9, "A", "act", "jab|L|head|0.12|0.20" } })
scen("clinch_inside", 2.8, { { 0.2, "A", "Guard", "clinch" }, { 0.2, "B", "Guard", "clinch" }, { 0.2, "A", "move", { 0, -0.9, 0.3 } },
	punchAt(0.8, "A", "uppercut", "L", "body", 0.18), punchAt(1.25, "A", "uppercut", "R", "body", 0.18), punchAt(1.7, "A", "uppercut", "L", "body", 0.18),
	{ 2.3, "A", "Guard", "stance" }, { 2.3, "B", "Guard", "stance" }, { 2.3, "A", "move", { 0, 0.9, 0.4 } } })
-- punches
for _, pk in ipairs({ { "jab", "L" }, { "cross", "R" }, { "leadhook", "L" }, { "rearhook", "R" }, { "uppercut", "R" }, { "overhand", "R" } }) do
	scen(pk[1], 1.5, { punchAt(0.4, "A", pk[1], pk[2]) })
end
scen("bodyjab", 1.5, { punchAt(0.4, "A", "jab", "L", "body") })
scen("bodycross", 1.5, { punchAt(0.4, "A", "cross", "R", "body") })
scen("bodyhook", 1.5, { punchAt(0.4, "A", "leadhook", "L", "body") })
scen("bodyuppercut", 1.5, { punchAt(0.4, "A", "uppercut", "R", "body") })
-- combos (the server's 0.88 windup inside 0.7 s)
-- (FightEngine's combination format: the 2nd punch on carries its place, "cross|R|head|0.21||2")
scen("combo12", 1.8, { punchAt(0.4, "A", "jab", "L"), punchAt(0.62, "A", "cross", "R", "head", 0.21, 2) })
scen("combo123", 2.2, { punchAt(0.4, "A", "jab", "L"), punchAt(0.62, "A", "cross", "R", "head", 0.21, 2), punchAt(0.92, "A", "leadhook", "L", "head", 0.23, 3) })
scen("combo1234", 2.6, { punchAt(0.4, "A", "jab", "L"), punchAt(0.62, "A", "cross", "R", "head", 0.21, 2), punchAt(0.92, "A", "leadhook", "L", "head", 0.23, 3),
	punchAt(1.25, "A", "rearhook", "R", "head", 0.26, 4) })
scen("combo_body_head", 2.0, { punchAt(0.4, "A", "leadhook", "L", "body"), punchAt(0.78, "A", "leadhook", "L", "head", 0.23, 2) })
scen("combo_jab_jab_cross", 2.0, { punchAt(0.4, "A", "jab", "L"), punchAt(0.6, "A", "jab", "L", "head", 0.14, 2), punchAt(0.8, "A", "cross", "R", "head", 0.21, 3) })
-- specials
for _, id in ipairs({ "checkhook", "phillyshell", "pullcounter", "livershot", "gazelle", "peekaboo", "stepback", "overhand", "leaduppercut",
	"doublejab", "feintcross", "bodyhead", "onetwothree", "shovelhook" }) do
	scen("sp_" .. id, 2.6, { { 0.3, "A", "act", string.format("special|%s||0.24|1.00", id), special = id } })
end
-- defence (B throws, A defends)
scen("slipL", 1.4, { punchAt(0.3, "B", "jab", "L"), { 0.32, "A", "act", "slip|L" } })
scen("slipR", 1.4, { punchAt(0.3, "B", "cross", "R"), { 0.34, "A", "act", "slip|R" } })
scen("roll", 1.5, { punchAt(0.3, "B", "leadhook", "L"), { 0.33, "A", "act", "roll" } })
scen("parry", 1.3, { punchAt(0.3, "B", "jab", "L"), { 0.36, "A", "act", "parry|R" }, { 0.46, "B", "act", "parryhit" } })
scen("block", 2.2, { { 0.2, "A", "Guard", "block" }, punchAt(0.5, "B", "cross", "R"), { 0.74, "A", "act", "blockhit" }, punchAt(1.0, "B", "leadhook", "L"),
	{ 1.26, "A", "act", "blockhit" }, { 1.8, "A", "Guard", "stance" } })
scen("shoulderroll", 2.0, { { 0, "A", "Style", "CounterPuncher" }, punchAt(0.5, "B", "cross", "R"), { 0.52, "A", "act", "slip|R" } }, { style = "CounterPuncher" })
scen("pull_counter_special", 1.6, { punchAt(0.3, "B", "jab", "L"), { 0.28, "A", "act", "special|pullcounter||0.24|1.00", special = "pullcounter" } })
-- the dodges as Shared.Evasion sends them (Evasion.Act: the act's length last)
scen("weaveL", 1.5, { punchAt(0.3, "B", "rearhook", "R"), { 0.33, "A", "act", "weave|L|0.50" } })
scen("weaveR", 1.5, { punchAt(0.3, "B", "leadhook", "L"), { 0.33, "A", "act", "weave|R|0.50" } })
scen("duck", 1.4, { punchAt(0.3, "B", "leadhook", "L"), { 0.34, "A", "act", "duck|0.40" } })
scen("pull", 1.4, { punchAt(0.3, "B", "cross", "R"), { 0.34, "A", "act", "pull|0.45" } })
scen("sidestepL", 1.6, { punchAt(0.3, "B", "cross", "R"), { 0.33, "A", "act", "sidestep|L|0.55" }, { 0.35, "A", "move", { -1.6, 0, 0.22 } },
	{ 1.1, "A", "move", { 1.6, 0, 0.4 } } })
scen("shoulderroll_act", 1.6, { punchAt(0.3, "B", "cross", "R"), { 0.32, "A", "act", "shoulderroll|L|0.60" } })
scen("weave_counter", 1.9, { punchAt(0.3, "B", "rearhook", "R"), { 0.33, "A", "act", "weave|L|0.50" }, punchAt(0.68, "A", "leadhook", "L", "head", 0.23, 2) })
scen("duck_uppercut", 1.9, { punchAt(0.3, "B", "leadhook", "L"), { 0.34, "A", "act", "duck|0.40" }, punchAt(0.6, "A", "uppercut", "R", "head", 0.26, 2) })
scen("slip_counter", 1.7, { punchAt(0.3, "B", "jab", "L"), { 0.32, "A", "act", "slip|R" }, punchAt(0.55, "A", "cross", "R", "head", 0.21, 2) })
scen("dodge_chain", 2.4, { punchAt(0.3, "B", "jab", "L"), { 0.32, "A", "act", "slip|R" }, punchAt(0.75, "B", "leadhook", "L"), { 0.77, "A", "act", "weave|L|0.50" },
	punchAt(1.3, "B", "cross", "R"), { 1.32, "A", "act", "pull|0.45" } })
-- being hit (B's punch lands on A at its contact)
local function hitScen(id, kind, hand, zone, sev, flag, extra)
	local w = WIND[kind]
	local ev = { punchAt(0.3, "B", kind, hand, zone) }
	local s
	if zone == "body" then
		s = string.format("hitbody|%s|%s|%.2f", kind, hand == "L" and "R" or "L", sev)
	else
		s = string.format("hit|%s|%s|%.2f|%s", kind, flag or "head", sev, hand)
	end
	table.insert(ev, { 0.3 + w, "A", "act", s })
	for _, e in ipairs(extra or {}) do
		table.insert(ev, e)
	end
	scen(id, 1.9, ev)
end
hitScen("hit_light_jab", "jab", "L", "head", 0.25)
hitScen("hit_med_cross", "cross", "R", "head", 0.6)
hitScen("hit_heavy_hook", "leadhook", "L", "head", 1.0, "heavy")
hitScen("hit_heavy_rearhook", "rearhook", "R", "head", 0.95, "heavy")
hitScen("hit_crit_uppercut", "uppercut", "R", "head", 1.25, "heavy")
hitScen("hit_body_light", "jab", "L", "body", 0.3)
hitScen("hit_liver", "leadhook", "L", "body", 0.9)
scen("stagger", 2.0, { punchAt(0.3, "B", "rearhook", "R"), { 0.6, "A", "act", "hit|rearhook|heavy|0.90|R" }, { 0.75, "A", "act", "stumble|B|0.80|0.90" },
	{ 0.75, "A", "move", { 0.2, 1.1, 0.6 } } })
scen("hurt_wobbly", 3.0, { { 0, "A", "Daze", 2 }, { 0, "A", "Guard", "hurt" } })
scen("dazed3", 3.0, { { 0, "A", "Daze", 3 }, { 0, "A", "Guard", "dazed" } })
-- knockdowns: the server's order (DownPose & co, then Guard = down), the count, the get-up act, Guard back to stance
-- opts (v10): dir = DownDir, dist = DownDist, move = { dx, dz, dur } the server's walk into the ropes / the corner
local function kdScen(id, pose, kind, hand, sev, getup, count, ko, zone, opts)
	opts = opts or {}
	local w = WIND[kind]
	local tc = 0.3 + w
	local ev = { punchAt(0.3, "B", kind, hand, zone) }
	if zone == "body" then
		table.insert(ev, { tc, "A", "act", string.format("hitbody|%s|%s|%.2f", kind, hand == "L" and "R" or "L", sev) })
	else
		table.insert(ev, { tc, "A", "act", string.format("hit|%s|heavy|%.2f|%s", kind, sev, hand) })
	end
	table.insert(ev, { tc, "A", "DownPose", pose })
	table.insert(ev, { tc, "A", "DownDir", opts.dir or ((pose == "face" or pose == "forward" or pose == "knee") and 0.7 or math.pi) })
	if opts.dist then
		table.insert(ev, { tc, "A", "DownDist", opts.dist })
	end
	table.insert(ev, { tc, "A", "KOKind", ko or false })
	table.insert(ev, { tc, "A", "Count", 0 })
	table.insert(ev, { tc + 0.001, "A", "Guard", "down" })
	if opts.move then
		table.insert(ev, { tc + 0.002, "A", "move", opts.move })
	end
	local dur
	if ko then
		local wall = ({ oneshot = 1.75, crumple = 1.75, delayed = 2.6, standing = 0.6 })[ko] or 1.75
		if ko == "crumple" and pose == "back" then
			wall += 0.2
		elseif pose == "ropes" or pose == "corner" then
			wall += 0.35
		end
		if ko == "standing" then
			-- (the referee catches him: FightEngine RefCatch, CATCH_TIME later the wave-off)
			table.insert(ev, { tc + 0.1, "ref", "move", { 2.6, 1.2, 0.5 } })
			table.insert(ev, { tc + 0.55, "ref", "act", "catch|3.6" })
			wall = 2.2
		end
		table.insert(ev, { tc + wall, "B", "Guard", "win" })
		table.insert(ev, { tc + wall, "ref", "act", "waveoff" })
		dur = tc + wall + 2.4
	else
		for n = 1, count do
			table.insert(ev, { tc + 0.9 + n, "ref", "act", "refcount|" .. n })
			table.insert(ev, { tc + 0.9 + n, "A", "Count", n })
		end
		local up = tc + 0.9 + count + 0.3
		table.insert(ev, { up, "A", "act", string.format("getup|%s|0|%.2f", pose, getup) })
		table.insert(ev, { up + 0.02, "A", "Guard", "stance" })
		table.insert(ev, { up, "A", "KOKind", false })
		dur = up + getup + 1.2
	end
	scen(id, dur, ev, { ref = true, every = 4, focus = { 0.2, dur }, kdAt = tc })
end
kdScen("kd_back", "back", "cross", "R", 1.1, 2.4, 4)
kdScen("kd_sit", "sit", "jab", "L", 0.9, 1.3, 3)
kdScen("kd_side", "side", "leadhook", "L", 1.1, 2.3, 4)
kdScen("kd_face", "face", "overhand", "R", 1.2, 2.2, 4)
kdScen("kd_knee", "knee", "leadhook", "L", 1.0, 1.4, 3)
kdScen("ko_oneshot_back", "back", "cross", "R", 1.4, nil, nil, "oneshot")
kdScen("ko_oneshot_face", "face", "rearhook", "R", 1.4, nil, nil, "oneshot")
kdScen("ko_crumple_side", "side", "leadhook", "L", 1.4, nil, nil, "crumple")
kdScen("ko_crumple_back", "back", "uppercut", "R", 1.4, nil, nil, "crumple")
kdScen("ko_delayed_face", "face", "overhand", "R", 1.4, nil, nil, "delayed")
kdScen("ko_body", "knee", "leadhook", "L", 1.4, nil, nil, "crumple", "body")
kdScen("ko_uppercut", "back", "uppercut", "R", 1.4, nil, nil, "oneshot")
kdScen("ko_hook_face", "face", "leadhook", "L", 1.4, nil, nil, "oneshot")
kdScen("ko_standing", "standing", "rearhook", "R", 1.4, nil, nil, "standing")
-- v10: the flash knockdown, and the falls into the ropes / the corner (the server walks his root there over the
-- stagger: the move; DownDist as FightMotion.RopeTravel sets it)
kdScen("kd_flash", "flash", "jab", "L", 0.9, 1.1, 2)
kdScen("kd_ropes", "ropes", "cross", "R", 1.1, 2.0, 4, nil, nil, { dir = math.pi, dist = 1.5, move = { 0, 1.5, 0.45 } })
kdScen("kd_corner", "corner", "rearhook", "R", 1.1, 2.0, 4, nil, nil, { dir = math.pi * 0.75, dist = 1.2, move = { 0.85, 0.85, 0.45 } })
kdScen("ko_ropes", "ropes", "cross", "R", 1.4, nil, nil, "crumple", nil, { dir = math.pi, dist = 1.5, move = { 0, 1.5, 0.45 } })
kdScen("ko_corner", "corner", "rearhook", "R", 1.4, nil, nil, "crumple", nil, { dir = math.pi * 0.75, dist = 1.2, move = { 0.85, 0.85, 0.45 } })
-- between rounds and after
scen("rest_stool", 4, { { 0.2, "A", "Guard", "rest" }, { 0.2, "A", "Stam", 0.4 } }, { stool = true, every = 4 })
scen("win_lose", 5, { { 0.2, "A", "Guard", "win" }, { 0.2, "B", "Guard", "lose" } }, { every = 4 })

-- swing styles: the same five punches from six different boxers (AnimFight.swing: Style + the seed + PunchStyle)
for _, sb in ipairs({ { "boxerpuncher", "BoxerPuncher", 1101 }, { "outboxer", "OutBoxer", 2202 }, { "swarmer", "Swarmer", 3303 },
	{ "slugger", "Slugger", 4404 }, { "counter", "CounterPuncher", 5505 }, { "outboxer_heavy", "OutBoxer", 6606, "Heavy" } }) do
	scen("sty_" .. sb[1], 5.4, { punchAt(0.4, "A", "jab", "L"), punchAt(1.4, "A", "cross", "R"), punchAt(2.4, "A", "leadhook", "L"),
		punchAt(3.4, "A", "uppercut", "R"), punchAt(4.4, "A", "overhand", "R") }, { style = sb[2], seed = sb[3], pstyle = sb[4], focus = { 0, 5.4 } })
end

local function fightClip(tier)
	local arena = E.new("Model", E.workspace)
	arena.Name = "Arena"
	local a, humA = makeBoxer(tier)
	a.Name = "BoxerA"
	local b, humB = makeBoxer(3, { gloves = 2, trunks = 4 })
	b.Name = "BoxerB"
	local refM = makeBoxer(2, { gloves = 3, trunks = 5 })
	refM.Name = "RefereeM"
	a.Parent, b.Parent, refM.Parent = arena, arena, arena
	local GAP = tonumber(args.gap) or 4.0
	local ha, hb, hr = a:FindFirstChild("HumanoidRootPart"), b:FindFirstChild("HumanoidRootPart"), refM:FindFirstChild("HumanoidRootPart")
	local yA, yB, yR = ha.CFrame.Y, hb.CFrame.Y, hr.CFrame.Y
	local homeA = CFrame.new(0, yA, GAP / 2)
	local homeB = CFrame.new(0, yB, -GAP / 2) * CFrame.Angles(0, math.pi, 0)
	local homeR = CFrame.new(-5.5, yR, -2.2) * CFrame.Angles(0, -math.pi / 2, 0)
	-- the corner stool behind A
	local stool = E.new("Model", arena)
	stool.Name = "CornerStool"
	local seat = E.new("Part", stool)
	seat.Name = "Seat"
	seat.Size = Vector3.new(1.4, 0.25, 1.4)
	seat.CFrame = CFrame.new(0, 1.55, GAP / 2 + 1.0)
	local metricsF = {}
	local summary = {}
	for _, sc in ipairs(SCEN) do
		if FIGHT_ONLY and not FIGHT_ONLY[sc.id] then
			continue
		end
		-- reset: home, stance, the default attributes; settle
		ha.CFrame, hb.CFrame, hr.CFrame = homeA, homeB, homeR
		for _, m in ipairs({ a, b }) do
			m:SetAttribute("Guard", "stance")
			m:SetAttribute("Style", "BoxerPuncher")
			m:SetAttribute("Stam", 1)
			m:SetAttribute("Daze", 0)
			m:SetAttribute("Conc", 0)
			m:SetAttribute("KOKind", nil)
			m:SetAttribute("DownPose", nil)
			m:SetAttribute("Count", 0)
			m:SetAttribute("KOLanded", nil)
			m:SetAttribute("Chain", nil)
			if not CS:HasTag(m, "Fighter") then
				CS:AddTag(m, "Fighter")
			end
		end
		a:SetAttribute("Style", sc.style or "BoxerPuncher")
		a:SetAttribute("PunchStyle", sc.pstyle)
		if (sc.seed or 0) ~= (a:GetAttribute("AnimSeed") or 0) then
			-- (a boxer of his own: the rig is set up again with this seed)
			a:SetAttribute("AnimSeed", sc.seed)
			CS:RemoveTag(a, "Fighter")
			for _ = 1, 3 do
				frame({ a, b, refM })
			end
			CS:AddTag(a, "Fighter")
		end
		if sc.ref and not CS:HasTag(refM, "Referee") then
			CS:AddTag(refM, "Referee")
		end
		seat.Parent = sc.stool and stool or nil
		for _ = 1, 90 do
			frame({ a, b, refM })
		end
		local moves = {}
		local function step(model, hrp)
			local mv = moves[model]
			if not mv then
				hrp.AssemblyLinearVelocity = Vector3.zero
				return
			end
			local u = math.clamp((VT - mv.t0) / mv.dur, 0, 1)
			local e = u * u * (3 - 2 * u)
			local du = (u - mv.u) / DT
			mv.u = u
			local cf = mv.from * CFrame.new(mv.dx * e, 0, mv.dz * e) * CFrame.Angles(0, (mv.dyaw or 0) * e, 0)
			hrp.CFrame = cf
			local v = (mv.from:VectorToWorldSpace(Vector3.new(mv.dx, 0, mv.dz))) * (6 * u * (1 - u)) / mv.dur
			hrp.AssemblyLinearVelocity = mv.pivot and Vector3.zero or v
			if u >= 1 then
				moves[model] = nil
			end
			_ = du
		end
		local ids = { A = 0, B = 0, ref = 0 }
		local who = { A = a, B = b, ref = refM }
		local roots = { A = ha, B = hb, ref = hr }
		local ev = table.clone(sc.ev)
		table.sort(ev, function(x, y)
			return x[1] < y[1]
		end)
		local ei = 1
		local t0 = VT
		local out = { clip = "fight", id = sc.id, tier = tier, frames = {}, ref = sc.ref or false, kdAt = sc.kdAt }
		do
			-- the action window (the filmstrip's frames): from just before the first event to well after the last
			local lo, hi = math.huge, 0
			for _, e in ipairs(ev) do
				lo, hi = math.min(lo, e[1]), math.max(hi, e[1] + (e.punch and e.punch.w or 0))
			end
			out.focus = sc.focus or (lo < math.huge and { math.max(0, lo - 0.1), math.min(sc.dur, hi + 0.75) } or { 0, sc.dur })
		end
		local sampleA = gaitSampler(a)
		local S = {}
		local prevT, prevW = {}, {}
		local snap = { arms = { step = 0, acc = 0, pops = 0 }, trunk = { step = 0, acc = 0, pops = 0 }, neck = { step = 0, acc = 0, pops = 0 },
			legs = { step = 0, acc = 0, pops = 0 }, rootMove = { step = 0, acc = 0, pops = 0 } }
		local motorsA = {}
		for k, n in pairs(MOTORS) do
			for _, d in ipairs(a:GetDescendants()) do
				if (d.ClassName == "Motor6D" or d.ClassName == "AnimationConstraint") and d.Name == n then
					motorsA[k] = d
				end
			end
		end
		local impacts = {}
		local pendingImpact = {}
		local series = {}
		local every = sc.every or FIGHT_EVERY
		local nF = math.floor(sc.dur / DT)
		local prevRootP, prevRootV
		for i = 1, nF do
			local t = VT - t0 + DT
			while ev[ei] and ev[ei][1] <= t + 1e-6 do
				local e = ev[ei]
				ei += 1
				local m = who[e[2]]
				if e[3] == "act" then
					ids[e[2]] += 1
					m:SetAttribute("Act", e[4])
					m:SetAttribute("ActId", (m:GetAttribute("ActId") or 0) + 1)
					if e.punch and e[2] == "A" then
						table.insert(pendingImpact, { at = t + e.punch.w, p = e.punch })
					elseif e.special and e[2] == "A" then
						local FM = H.require("FightMotion")
						local hits = FM.SpecialHits(e.special, 0.24)
						local def = FM.Specials[FM.SpecialId(e.special)]
						for hi, ht in ipairs(hits) do
							local pu = def.punches[hi]
							table.insert(pendingImpact, { at = t + ht, p = { kind = pu.kind, hand = pu.hand or def.hand, zone = pu.zone or def.zone, special = e.special } })
						end
					end
				elseif e[3] == "move" then
					local v = e[4]
					moves[m] = { t0 = VT + DT, dur = v[3], dx = v[1], dz = v[2], dyaw = v[4], from = roots[e[2]].CFrame, u = 0, pivot = v.pivot }
				else
					m:SetAttribute(e[3], e[4] ~= false and e[4] or nil)
				end
			end
			step(a, ha)
			step(b, hb)
			step(refM, hr)
			frame({ a, b, refM })
			-- the Animator's output transforms: the largest one-frame turn and change of turning speed per group
			local curW = {}
			for k, mo in pairs(motorsA) do
				local T = mo.Transform
				local pT = prevT[k]
				if pT then
					local ax, ang = (pT:Inverse() * T):ToAxisAngle()
					local w = ax * ang
					local g = snap[GROUP[k]]
					local dg = math.deg(ang)
					curW[k] = dg
					if dg > g.step then
						g.step, g.stepAt, g.stepJ = dg, t, k
					end
					local pw = prevW[k]
					if pw then
						local acc = math.deg((w - pw).Magnitude)
						if acc > g.acc then
							g.acc, g.accAt, g.accJ = acc, t, k
						end
						if acc > 4 then
							g.pops += 1
						end
					end
					prevW[k] = w
				end
				prevT[k] = T
				if k == "Root" then
					local p = T.Position
					if prevRootP then
						local v = p - prevRootP
						local g = snap.rootMove
						g.step = math.max(g.step, v.Magnitude)
						if prevRootV then
							local acc = (v - prevRootV).Magnitude
							if acc > g.acc then
								g.acc, g.accAt = acc, t
							end
							if acc > 0.02 then
								g.pops += 1
							end
						end
						prevRootV = v
					end
					prevRootP = p
				end
			end
			local smp = sampleA(t)
			table.insert(S, smp)
			if args.dbgfoot then
				local rg = H.require("AnimRig").rigs[a]
				local fl, fr2 = rg.foot.L, rg.foot.R
				rg.dbgLock = true
				if not rg.dbgOnce then
					rg.dbgOnce = true
					for _, sd in ipairs({ "L", "R" }) do
						local lg = rg.geo[sd]
						local tt = {}
						for _, q in ipairs(lg.toe) do
							table.insert(tt, string.format("[%.3f %.3f %.3f %.3f]", q[1], q[2], q[3], q[4]))
						end
						print("dbg geo", sd, "bz", lg.bz, "boxToe", lg.boxToe, "toeX", lg.toeX, table.concat(tt, " "))
					end
				end
				local fls = rg.footLocks
				if fls then
					print(string.format("dbg3 %.3f lockL on=%s w=%.2f lockR on=%s w=%.2f", t, tostring(fls.L.on), fls.L.w, tostring(fls.R.on), fls.R.w))
				end
				print(string.format("dbg2 %.3f pitchS L %.3f R %.3f spinL %.2f spinR %.2f", t, fl.pitchS or -1, fr2.pitchS or -1, fl.spinT or -1, fr2.spinT or -1))
				print(string.format("dbg %.3f L heel %.3f piv %.3f knee %.3f sw %s | R heel %.3f piv %.3f knee %.3f sw %s | ankL %.1f ankR %.1f fpL %.1f fpR %.1f",
					t, fl.heel, fl.pivot, fl.knee, tostring(fl.swing), fr2.heel, fr2.pivot, fr2.knee, tostring(fr2.swing), smp.ankleL, smp.ankleR,
					smp.footPitchL, smp.footPitchR))
			end
			-- contact: the glove against the target the server lands it on
			for pi = #pendingImpact, 1, -1 do
				local pe = pendingImpact[pi]
				if t >= pe.at - 1e-6 then
					table.remove(pendingImpact, pi)
					local p = pe.p
					local glove
					for _, d in ipairs(a:GetDescendants()) do
						if (d.ClassName == "MeshPart" or d.ClassName == "Part") and d.Name == "Glove" .. p.hand then
							glove = d
						end
					end
					glove = glove or a:FindFirstChild(p.hand == "L" and "LeftHand" or "RightHand")
					local tgt = p.zone == "body" and b:FindFirstChild("UpperTorso") or b:FindFirstChild("Head")
					local other = a:FindFirstChild(p.hand == "L" and "RightHand" or "LeftHand")
					local headA = a:FindFirstChild("Head")
					table.insert(impacts, { kind = p.kind, hand = p.hand, zone = p.zone, special = p.special, t = r4(t),
						toTarget = r4((glove.Position - tgt.Position).Magnitude), dy = r4(glove.Position.Y - tgt.Position.Y),
						reachZ = r4(-(glove.Position.Z - ha.Position.Z)),
						guardHandY = r4(other.Position.Y - headA.Position.Y),
						headOffX = r4(ha.CFrame:PointToObjectSpace(headA.Position).X) })
				end
			end
			local row = { t = r4(t) }
			for _, k in ipairs({ "pelvisY", "headY", "headPitch", "headRoll", "pelvisYaw", "chestYaw", "trunkPitch", "kneeL", "kneeR", "hipL", "hipR",
				"shoulderL", "shoulderR", "elbowL", "elbowR", "footPitchL", "footPitchR", "soleL", "soleR", "handZL", "handZR" }) do
				row[k] = r4(smp[k])
			end
			do
				local pv = S[#S - 1]
				for _, k in ipairs({ "L", "R" }) do
					local slip = 0
					if pv and pv["sole" .. k] < 0.012 and smp["sole" .. k] < 0.012 then
						local q = pv["pts" .. k][pv["soleI" .. k]]
						local pa, pb = pv["footCF" .. k] * q, smp["footCF" .. k] * q
						slip = pb.Y < 0.012 and Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z).Magnitude or 0
					end
					row["slip" .. k] = r4(slip)
				end
			end
			local hp = ha.CFrame:PointToObjectSpace(a:FindFirstChild("Head").Position)
			row.headX, row.headZ = r4(hp.X), r4(hp.Z)
			for _, s in ipairs({ "L", "R" }) do
				local hd = a:FindFirstChild(s == "L" and "LeftHand" or "RightHand")
				local q = ha.CFrame:PointToObjectSpace(hd.Position)
				row["hand" .. s .. "x"], row["hand" .. s .. "y"] = r4(q.X), r4(q.Y)
			end
			for k, dg in pairs(curW) do
				row["w" .. k] = r4(dg)
			end
			table.insert(series, row)
			if (not NOMESH) and (i % every == 0 or i == 1) then
				local fr = exportFrame(a, VT)
				if sc.stool and seat.Parent then
					table.insert(fr.parts, { name = "Seat", shape = "Block", cf = cfList(seat.CFrame), size = { 1.4, 0.25, 1.4 }, color = { 0.55, 0.12, 0.1 },
						material = "SmoothPlastic", reflectance = 0, transparency = 0 })
				end
				fr.opp = exportFrame(b, VT)
				if sc.ref then
					fr.ref = exportFrame(refM, VT)
				end
				fr.root = cfList(ha.CFrame)
				fr.t = r4(t)
				fr.label = string.format("%.2f s", t)
				table.insert(out.frames, fr)
			end
		end
		local g = gaitSummary(S)
		-- the knockout's landing (the client-local KOLanded the Animator stamps) against the server's wait
		local koLand = a:GetAttribute("KOLanded")
		local koAt
		for _, e in ipairs(ev) do
			if e[3] == "Guard" and e[4] == "down" and e[2] == "A" then
				koAt = e[1]
			end
		end
		local landWall = (type(koLand) == "number" and koAt) and r4(koLand - t0 - koAt) or nil
		-- the slide while he is on his feet (the pelvis within 0.6 studs of the stance's height): a body lying or
		-- kneeling on the canvas drags its feet by design, a standing one must not skate
		local stand = {}
		local y0 = S[1] and S[1].pelvisY or 0
		for _, x in ipairs(S) do
			if x.pelvisY > y0 - 0.6 then
				table.insert(stand, x)
			elseif #stand > 0 and stand[#stand] ~= false then
				table.insert(stand, false)
			end
		end
		local runs, cur = {}, {}
		for _, x in ipairs(stand) do
			if x == false then
				table.insert(runs, cur)
				cur = {}
			else
				table.insert(cur, x)
			end
		end
		table.insert(runs, cur)
		local sL, sR = 0, 0
		for _, rn in ipairs(runs) do
			if #rn > 1 then
				local gs = gaitSummary(rn)
				sL += gs.slideL
				sR += gs.slideR
			end
		end
		g.slideL, g.slideR = r4(sL), r4(sR)
		local rec = { id = sc.id, tier = tier, koLandWall = landWall, slideL = g.slideL, slideR = g.slideR, slideMaxSpeed = g.slideMaxSpeed, sinkMin = g.sinkMin, snap = {},
			impacts = impacts, ranges = {} }
		for k, v in pairs(snap) do
			rec.snap[k] = { step = r4(v.step), acc = r4(v.acc), pops = v.pops, stepJ = v.stepJ, accJ = v.accJ, accAt = v.accAt and r4(v.accAt) }
		end
		for _, k in ipairs({ "pelvisYaw", "chestYaw", "headPitch", "headRoll", "pelvisY", "kneeL", "kneeR", "trunkPitch" }) do
			rec.ranges[k] = g[k]
		end
		table.insert(metricsF, rec)
		Host.WriteJSON(string.format("%s/fightseries_%s_t%d.json", OUT, sc.id, tier), { id = sc.id, series = series })
		if not NOMESH then
			local file = string.format("fight_%s_t%d.json", sc.id, tier)
			Host.WriteJSON(OUT .. "/" .. file, out)
			table.insert(index.clips, { id = string.format("fight_%s_t%d", sc.id, tier), file = file, clip = "fight", tier = tier, n = #out.frames,
				ref = sc.ref or false })
		end
		local imp = landWall and string.format(" [KO landed +%.2f s wall]", landWall) or ""
		for _, im in ipairs(impacts) do
			imp ..= string.format(" [%s%s %.2f dy%+.2f]", im.kind, im.zone == "body" and "/b" or "", im.toTarget, im.dy)
		end
		print(string.format("fight %-18s slide %.3f/%.3f  snap step arms %.1f trunk %.1f neck %.1f legs %.1f | acc arms %.1f trunk %.1f neck %.1f legs %.1f root %.3f | pops %d/%d/%d/%d%s",
			sc.id, g.slideL, g.slideR, snap.arms.step, snap.trunk.step, snap.neck.step, snap.legs.step, snap.arms.acc, snap.trunk.acc, snap.neck.acc,
			snap.legs.acc, snap.rootMove.acc, snap.arms.pops, snap.trunk.pops, snap.neck.pops, snap.legs.pops, imp))
		-- clear the scenario's state
		for _, m in ipairs({ a, b }) do
			m:SetAttribute("Guard", "stance")
			m:SetAttribute("KOKind", nil)
			m:SetAttribute("DownPose", nil)
			m:SetAttribute("Daze", 0)
		end
		if CS:HasTag(refM, "Referee") then
			CS:RemoveTag(refM, "Referee")
		end
		for _ = 1, 30 do
			frame({ a, b, refM })
		end
		-- (a fall leaves the rig down: rebuild the rigs' state by re-tagging)
		for _, m in ipairs({ a, b }) do
			CS:RemoveTag(m, "Fighter")
		end
		for _ = 1, 3 do
			frame({ a, b, refM })
		end
		for _, m in ipairs({ a, b }) do
			CS:AddTag(m, "Fighter")
		end
		for _ = 1, 3 do
			frame({ a, b, refM })
		end
		_ = summary
	end
	Host.WriteJSON(string.format("%s/fight_metrics_t%d.json", OUT, tier), metricsF, true)
	table.insert(metrics, { clip = "fight", tier = tier, scenarios = metricsF })
	for _, m in ipairs({ a, b }) do
		CS:RemoveTag(m, "Fighter")
	end
	arena:Destroy()
	for _ = 1, 3 do
		frame({})
	end
end

local function restClip(tier)
	local model = makeBoxer(tier)
	if args.debugfoot then
		gaitSampler(model)
		for _, d in ipairs(model:GetDescendants()) do
			if (d.ClassName == "Weld" or d.ClassName == "WeldConstraint") and d.Part0 and (d.Part0.Name == "LeftFoot") then
				local rel = d.Part0.CFrame:Inverse() * d.Part1.CFrame
				print("  on LeftFoot:", d.Part1.Name, d.Part1.ClassName, tostring(d.Part1.Size), tostring(rel.Position), d.Part1.Transparency)
			end
		end
	end
	model.Name = "Stander"
	player.Character = model
	player.CharacterAdded:Fire(model)
	for _ = 1, 120 do
		frame({ model })
	end
	local out = { clip = "rest", tier = tier, frames = { exportFrame(model, VT) } }
	out.frames[1].root = cfList(model:FindFirstChild("HumanoidRootPart").CFrame)
	local file = string.format("rest_t%d.json", tier)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("rest_t%d", tier), file = file, clip = "rest", tier = tier, n = 1 })
	player.Character = nil
	model:Destroy()
	for _ = 1, 3 do
		frame({})
	end
end

------------------------------------------------------------------------
-- reach: where the punch VISIBLY lands (--clips reach). A (--frame) throws every punch at B (--oframe, default A's)
-- from each gap of --gaps (root to root, default 4.2,5.0,5.8); per punch and gap the closest the glove's surface
-- came to the target's (the head sphere, the torso boxes for a body shot) over the punch. The boundary (the gap at
-- which the gap closes to CONTACT) is read off by interpolation; HitGeometry.Frame off the same rigs in their rest
-- pose rides along, so tools/sim/test_hitdetect can hold the server's hit test to the animation (--reachout FILE:
-- the JSON, default <out>/reach.json)
------------------------------------------------------------------------
local REACH_LIST = {
	{ "jab", "jab|L|head|0.16|0.8" }, { "cross", "cross|R|head|0.2|0.9" }, { "leadhook", "leadhook|L|head|0.2|0.9" },
	{ "rearhook", "rearhook|R|head|0.22|0.9" }, { "uppercut", "uppercut|R|head|0.22|0.9" }, { "overhand", "overhand|R|head|0.24|0.9" },
	{ "jab|body", "jab|L|body|0.16|0.8" }, { "cross|body", "cross|R|body|0.2|0.9" }, { "leadhook|body", "leadhook|L|body|0.2|0.9" },
	{ "rearhook|body", "rearhook|R|body|0.22|0.9" }, { "uppercut|body", "uppercut|R|body|0.22|0.9" },
}
local REPS = tonumber(args.reps) or 1
local function reachClip(tier)
	local HG = H.require("HitGeometry")
	local a = makeBoxer(tier)
	a.Name = "BoxerA"
	local b = makeBoxer(3, { gloves = 2, trunks = 4, frame = args.oframe or FRAME })
	b.Name = "BoxerB"
	-- the frames as the server's geoFrame reads them: the rest pose, the soles on the floor (Y = 0)
	local geoA, geoB = HG.Frame(a, 0), HG.Frame(b, 0)
	local gaps = {}
	for s in (args.gaps or "4.2,5.0,5.8"):gmatch("[^,]+") do
		table.insert(gaps, tonumber(s))
	end
	local ha, hb = a:FindFirstChild("HumanoidRootPart"), b:FindFirstChild("HumanoidRootPart")
	for _, m in ipairs({ a, b }) do
		m:SetAttribute("Guard", "up")
		m:SetAttribute("Style", "BoxerPuncher")
		CS:AddTag(m, "Fighter")
	end
	local function boxGap(p, part)
		local lp = part.CFrame:PointToObjectSpace(p)
		local s = part.Size / 2
		local q = Vector3.new(math.clamp(lp.X, -s.X, s.X), math.clamp(lp.Y, -s.Y, s.Y), math.clamp(lp.Z, -s.Z, s.Z))
		return (lp - q).Magnitude
	end
	local res = {}
	local actId = 0
	for _, gap in ipairs(gaps) do
		ha.CFrame = CFrame.new(0, ha.CFrame.Y, gap / 2)
		hb.CFrame = CFrame.new(0, hb.CFrame.Y, -gap / 2) * CFrame.Angles(0, math.pi, 0)
		for _ = 1, 90 do
			frame({ a, b })
		end
		for _, pd in ipairs(REACH_LIST) do
			local name, act = pd[1], pd[2]
			-- (--only jab|body,cross: just those punches)
			if args.only and not ("," .. args.only .. ","):find("," .. name .. ",", 1, true) then
				continue
			end
			local hand = act:match("^[^|]*|(%a)")
			local glove
			for _, d in ipairs(a:GetDescendants()) do
				if (d.ClassName == "MeshPart" or d.ClassName == "Part") and d.Name == "Glove" .. hand then
					glove = d
				end
			end
			glove = glove or a:FindFirstChild(hand == "L" and "LeftHand" or "RightHand")
			local body = act:find("|body|", 1, true) ~= nil
			-- (--reps N: the punch thrown N times from the gap - the client picks a variant per throw, a paw or a
			-- long jab, a tight or a wide hook - and the median of the closest each came is the visible reach)
			local surfs = {}
			for _ = 1, REPS do
			actId += 1
			a:SetAttribute("Act", act)
			a:SetAttribute("ActId", actId)
			local best = math.huge
			for _ = 1, 50 do
				frame({ a, b })
				local gp = glove.Position
				local gr = math.max(glove.Size.X, glove.Size.Z) / 2
				local s
				if body then
					s = math.min(boxGap(gp, b:FindFirstChild("UpperTorso")), boxGap(gp, b:FindFirstChild("LowerTorso"))) - gr
				else
					local hd = b:FindFirstChild("Head")
					s = (gp - hd.Position).Magnitude - math.max(hd.Size.X, hd.Size.Y) / 2 - gr
				end
				best = math.min(best, s)
			end
			-- (back to the guard and the roots where they were: a lunge moves A's root)
			a:SetAttribute("Act", "idle")
			for _ = 1, 40 do
				frame({ a, b })
			end
			ha.CFrame = CFrame.new(0, ha.CFrame.Y, gap / 2)
			hb.CFrame = CFrame.new(0, hb.CFrame.Y, -gap / 2) * CFrame.Angles(0, math.pi, 0)
			for _ = 1, 20 do
				frame({ a, b })
			end
			table.insert(surfs, best)
			end
			table.sort(surfs)
			local med = surfs[math.floor((#surfs + 1) / 2)]
			res[name] = res[name] or {}
			table.insert(res[name], { gap = gap, surf = r4(med), min = r4(surfs[1]), max = r4(surfs[#surfs]) })
			print(string.format("reach T%d %s->%s %-14s gap %.2f  glove surface %.3f (%.3f..%.3f)", tier, FRAME or "Athletic", args.oframe or FRAME or "Athletic", name, gap, med, surfs[1], surfs[#surfs]))
		end
	end
	local out = { tier = tier, frame = FRAME or "Athletic", oframe = args.oframe or FRAME or "Athletic", geoA = geoA, geoB = geoB, punches = res }
	Host.WriteJSON(args.reachout or (OUT .. "/reach.json"), out, true)
	for _, m in ipairs({ a, b }) do
		CS:RemoveTag(m, "Fighter")
		m:Destroy()
	end
	for _ = 1, 3 do
		frame({})
	end
end

for _, tier in ipairs(TIERS) do
	if CLIPS.rest then
		restClip(tier)
	end
	for _, clip in ipairs({ "walk", "jog", "run", "sprint", "shift" }) do
		if CLIPS[clip] then
			for _, timing in ipairs(TIMINGS) do
				walkClip(clip, tier, timing)
			end
		end
	end
	for _, clip in ipairs({ "startstop", "turn", "curve", "snapturn" }) do
		if CLIPS[clip] then
			scriptClip(clip, tier)
		end
	end
	for _, clip in ipairs({ "strafe", "strafe16", "strafering", "strafeturn" }) do
		if CLIPS[clip] then
			for _, timing in ipairs(TIMINGS) do
				strafeClip(clip, tier, timing)
			end
		end
	end
	if CLIPS.punch then
		punchClip(tier)
	end
	if CLIPS.reach then
		reachClip(tier)
	end
	if CLIPS.fight then
		fightClip(tier)
	end
end
Host.WriteJSON(OUT .. "/index.json", index, true)
Host.WriteJSON(OUT .. "/metrics.json", metrics, true)
print("out:", OUT)
process.exit(0)
