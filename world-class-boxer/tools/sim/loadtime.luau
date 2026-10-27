--!nocheck
-- tools/sim/loadtime.luau: what a join waits for before the menu, measured on the real server modules under lune.
--   * the profile (DataManager.Load) in Studio with API access off: a DataStore whose every call answers HTTP 403 after
--     --ds seconds (the menu opens when the profile arrives)
--   * the player's own boxer (Builder.Apply: the 14 muscle-tier parts and the mesh gear) while the server boots: the
--     tier preload (BuilderTiers.Preload), the gear preload (BuilderGear.Preload) and the gym's members built one after
--     another (Ambient: Builder.CreateNPC) all ask the same asset pipeline: a fake AssetService whose
--     CreateMeshPartAsync takes --lat seconds and serves at most --slots requests at a time (FIFO), so every
--     background load the player's loads queue behind costs him time
-- Prints the two times and the menu time (the later of the two: the menu's boxer is dressed); the loads each
-- party made before the player's build finished.
--   lune run tools/sim/loadtime.luau [--src DIR] [--lat 0.04] [--slots 2] [--ds 0.4] [--members 8] [--join 0.5]
--   before / after a change:  git archive HEAD src | tar -x -C /tmp/before && lune run tools/sim/loadtime.luau --src /tmp/before/src
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local ltask = require("@lune/task")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, Color3, CFrame = roblox.Vector3, roblox.Color3, roblox.CFrame

local args = {}
do
	local a = process.args
	for i = 1, #a, 2 do
		args[(a[i]:gsub("^%-%-", ""))] = a[i + 1]
	end
end
local LAT = tonumber(args.lat) or 0.04
local SLOTS = tonumber(args.slots) or 2
local DS = tonumber(args.ds) or 0.4
local MEMBERS = tonumber(args.members) or 8
local JOIN = tonumber(args.join) or 0.5
local root = Host.FindRoot()
local SRC = args.src or (root .. "/src")
local SCRATCH = process.env.TMPDIR or "/tmp"

------------------------------------------------------------------------
-- 1. the profile: DataManager.Load in Studio, API access off
------------------------------------------------------------------------
local function profileTime()
	-- a tree the host can mount: shared/ is the real one, client/modules holds DataManager and a Training stub
	local dir = string.format("%s/wcb_loadtime_%d", SCRATCH, math.floor(os.clock() * 1e6) % 1e9)
	fs.writeDir(dir .. "/client/modules")
	process.exec("ln", { "-s", SRC .. "/shared", dir .. "/shared" })
	fs.writeFile(dir .. "/client/modules/DataManager.lua", fs.readFile(SRC .. "/server/DataManager.lua"))
	fs.writeFile(dir .. "/client/modules/Training.lua", "return { Migrate = function() end }")
	local calls = 0
	local store = {
		UpdateAsync = function()
			calls += 1
			ltask.wait(DS)
			error("HTTP 403 (Studio access to APIs is not allowed.)", 0)
		end,
	}
	local H = Host.new({ server = true, src = dir, globals = { warn = function() end } })
	-- the shared folder from SRC (the module looks Config / Tutorial up there)
	H.Service("DataStoreService")._props = { GetDataStore = function()
		return store
	end }
	local okLoad, DM = pcall(function()
		return H.require("DataManager")
	end)
	if not okLoad then
		print("DataManager did not load: " .. tostring(DM))
		return nil
	end
	local player = { UserId = 1, Name = "Player1", Parent = H.Service("Players") }
	local t0 = os.clock()
	local prof = DM.Load(player)
	local dt = os.clock() - t0
	pcall(fs.removeDir, dir)
	return dt, calls, prof ~= nil
end

------------------------------------------------------------------------
-- 2. the player's boxer under the boot's asset traffic
------------------------------------------------------------------------
local E = FE.new()
local H = Host.new({ server = true, src = SRC, globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace,
	warn = function() end, print = function() end } })
E.install(H)
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderGear = H.require("BuilderGear")
local Builder = H.require("Builder")
local Looks = H.require("Looks")

-- the fake rig (test_npcbuild's): engine-mode ReplaceBodyPartR15 at the description's scale
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
local function newRig(scale)
	local model = E.new("Model")
	model.Name = "Boxer"
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	local ra = E.new("Attachment", hrp)
	ra.Name = "RootRigAttachment"
	ra.Position = Vector3.zero
	local function addPart(name, size, orig, atts)
		local p = E.new("MeshPart", model)
		p.Name = name
		p.Size = size
		p.Color = Color3.new(1, 1, 1)
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
	end
	for name, b in pairs(BLOCK) do
		local atts = {}
		for an, pos in pairs(b.att) do
			atts[an] = { cur = v3(pos) * scale, orig = v3(pos) }
		end
		addPart(name, v3(b.size) * scale, v3(b.size), atts)
	end
	addPart("Head", Vector3.new(0.927, 0.927, 0.927), Vector3.new(1.2, 1.2, 1.2),
		{ NeckRigAttachment = { cur = Vector3.new(0, -0.46, 0), orig = Vector3.new(0, -0.6, 0) } })
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		local m = E.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
		m.Transform = CFrame.new()
	end
	local hum = E.new("Humanoid", model)
	hum.HipHeight = 2 * scale.Y
	hum.ApplyDescription = function() end
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
			end
		end
		part.Parent = model
		old:Destroy()
		return true
	end
	return model, hum
end
H.Service("Players")._props.CreateHumanoidModelFromDescription = function(_, desc)
	return (newRig(Vector3.new(desc.WidthScale or 1, desc.HeightScale or 1, desc.DepthScale or 1)))
end
local stage = E.new("Folder", E.workspace)
stage.Name = "BoxerStaging"
Builder.Services.Stage = stage

-- the asset pipeline: SLOTS requests at a time, FIFO, LAT seconds each; every call tagged with who asked
local coTag = setmetatable({}, { __mode = "k" }) -- coroutine -> "npc" | "player" (anything else: the boot's preloads)
local queue, busy = {}, 0
local log = { boot = 0, npc = 0, player = 0 }
local T0 = os.clock()
local Pipeline = {}
function Pipeline.CreateMeshPartAsync(_, content)
	local tag = coTag[coroutine.running()] or "boot"
	log[tag] = (log[tag] or 0) + 1
	local me = {}
	table.insert(queue, me)
	while busy >= SLOTS or queue[1] ~= me do
		ltask.wait()
	end
	table.remove(queue, 1)
	busy += 1
	ltask.wait(LAT)
	busy -= 1
	local id = tonumber(tostring(content):match("(%d+)%s*$"))
	local mp = E.new("MeshPart")
	mp.MeshId = "rbxassetid://" .. tostring(id)
	return mp
end
local Content = { fromUri = function(u)
	return u
end }
BuilderTiers.Reset()
BuilderTiers.Services = { AssetService = Pipeline, Content = Content }
BuilderGear.Reset()
BuilderGear.Services = { AssetService = Pipeline, Content = Content }

local function buildOf(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end

local dtP, dsCalls, gotProfile = profileTime()

-- boot: the preloads, then the gym's members one after another (Ambient.Start)
BuilderTiers.Preload()
BuilderGear.Preload()
local membersDone = 0
ltask.spawn(function()
	for i = 1, MEMBERS do
		coTag[coroutine.running()] = "npc"
		local app = Looks.Random(100 + i * 101, i % 4 == 0 and 2 or 1, { age = 26, class = 5 })
		pcall(Builder.CreateNPC, app, Looks.RandomBuild(100 + i * 101, 0.55, 26, app.body.frame), { gloves = "Competition", wraps = "OldWraps" },
			"Member" .. i, { hands = i % 2 == 0 and "gloves" or "wraps", detail = "low", name = "Member" .. i })
		membersDone += 1
		ltask.wait()
	end
end)

-- the player joins JOIN s in: his character is dressed (Builder.Apply, as Main's onCharacter does)
ltask.wait(JOIN)
local char = newRig(Vector3.new(1, 1, 1))
char.Name = "Player1"
char.Parent = E.workspace
local tJoin = os.clock()
local before = table.clone(log)
local okApply, errApply
local done = false
ltask.spawn(function()
	okApply, errApply = pcall(function()
		-- (the player's loads are tagged; the tag is only read when a load starts, so the other threads keep theirs)
		local app = Looks.Defaults(1)
		coTag[coroutine.running()] = "player"
		Builder.Apply(char, app, buildOf(30), { gloves = "Starter" }, { hands = "gloves", name = "Player1" })
	end)
	done = true
end)
while not done and os.clock() - tJoin < 120 do
	ltask.wait(0.01)
end
local dtB = os.clock() - tJoin
local during = {}
for k, v in pairs(log) do
	during[k] = v - (before[k] or 0)
end
local tiers = char:GetAttribute("BodyTiers")
print(string.format("src: %s", SRC))
print(string.format("pipeline: %.3f s a mesh, %d at a time; DataStore %.2f s a call (HTTP 403)", LAT, SLOTS, DS))
print(string.format("profile ready (menu opens): %.2f s (%d DataStore calls, profile %s)", dtP or -1, dsCalls or -1, tostring(gotProfile)))
print(string.format("own boxer built (14 tier parts + gear): %.2f s after the join (%s%s)", dtB, okApply and "ok" or ("error " .. tostring(errApply)),
	tiers and (", tiers " .. tostring(tiers)) or ""))
print(string.format("  loads started meanwhile: player %d, gym NPCs %d, preloads %d", during.player or 0, during.npc or 0, during.boot or 0))
print(string.format("time to a dressed menu: %.2f s", math.max(dtP or 0, dtB)))
process.exit(0)
