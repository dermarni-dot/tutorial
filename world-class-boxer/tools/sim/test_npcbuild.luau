--!nocheck
-- tools/sim/test_npcbuild.luau: an NPC's build order and the rig diagnostic.
--   * Builder.CreateNPC parents the model into the staging container (Builder.Services.Stage; ServerStorage in the
--     game) BEFORE any Humanoid rig operation: every ReplaceBodyPartR15 (the tier parts, the classic head) sees a model
--     inside the DataModel (the fake engine flags one on an unparented model), and the model comes back unparented,
--     its root un-anchored, as every caller expects
--   * a swap the engine refuses (the part is not where it should be afterwards) is counted and warned once with a
--     [Boxer] line; the classic head swap the same
--   * the build record: HeadSizeAtBuild / HipHeightAtBuild on the model; FixHipHeight puts the tier legs' value back
--   * Shared.Diag reports a player rig, an NPC and a referee without an error, with the expected VERDICT lines, and
--     catches a head that is still a MeshPart, a HipHeight that drifted, a joint off its attachment
--   lune run tools/sim/test_npcbuild.luau
local roblox = require("@lune/roblox")
local ltask = require("@lune/task")
local process = require("@lune/process")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, Color3, CFrame, Enum = roblox.Vector3, roblox.Color3, roblox.CFrame, roblox.Enum

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local warns = {}
local function capture(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	table.insert(warns, table.concat(parts, " "))
end
local function warned(pattern)
	for _, w in ipairs(warns) do
		if string.find(w, pattern, 1, true) then
			return w
		end
	end
	return nil
end

local E = FE.new()
local H = Host.new({ server = true, globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace, warn = capture } })
E.install(H)
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderGear = H.require("BuilderGear")
local BuilderHead = H.require("BuilderHead")
local Builder = H.require("Builder")
local Looks = H.require("Looks")
local Officials = H.require("Officials")
local Diag = H.require("Diag")
local REAL = BodyTiers.Data()
local GEAR = BuilderGear.Data()

------------------------------------------------------------------------
-- the fake rig (test_referee.luau's: engine mode, a MeshPart head); the Humanoid's ReplaceBodyPartR15 records whether the
-- model was inside a container when it was called (the engine warns and misbehaves outside the DataModel)
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

local swapLog = {} -- every ReplaceBodyPartR15: { name, staged = the model was inside a container }
local refuse = {} -- part names the fake engine refuses to swap (does nothing)
local function newRig(scale, parent)
	local model = E.new("Model")
	model.Name = "Boxer"
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1) * scale
	hrp.Anchored = false
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
		return p
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
	hum.WalkSpeed = 16
	hum.ReplaceBodyPartR15 = function(_, enum, part)
		local name = enum.Name
		table.insert(swapLog, { name = name, staged = model.Parent ~= nil })
		if refuse[name] then
			return false
		end
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
	if parent then
		model.Parent = parent
	end
	return model, hum
end

local function fakeAssets()
	local AS = { calls = 0 }
	function AS.CreateMeshPartAsync(_, content)
		AS.calls += 1
		local id = tonumber(tostring(content):match("(%d+)%s*$"))
		local mp = E.new("MeshPart")
		mp.MeshId = "rbxassetid://" .. tostring(id)
		return mp
	end
	return AS
end
local Content = { fromUri = function(u)
	return u
end }
BodyTiers.SetData(REAL)
BuilderTiers.Reset()
BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
BuilderGear.SetData(GEAR)
BuilderGear.Reset()
BuilderGear.Services = { AssetService = fakeAssets(), Content = Content }

-- the engine's CreateHumanoidModelFromDescription: an UNPARENTED rig at the description's scale
local lastDesc
H.Service("Players")._props.CreateHumanoidModelFromDescription = function(_, desc)
	lastDesc = desc
	local sc = Vector3.new(desc.WidthScale or 1, desc.HeightScale or 1, desc.DepthScale or 1)
	local model = newRig(sc, nil)
	return model
end

local function buildOf(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end

local stage = E.new("Folder", E.workspace)
stage.Name = "BoxerStaging"
Builder.Services.Stage = stage

------------------------------------------------------------------------
-- CreateNPC: staged inside a container for every rig operation, handed back unparented
------------------------------------------------------------------------
local app = Looks.Random(4242, 1, { age = 26, class = 5 })
local build = buildOf(70)
local gear = { gloves = "Competition", glovesCond = 70, wraps = "OldWraps", wrapsCond = 80 }
local npc
do
	swapLog = {}
	local ok, res = pcall(Builder.CreateNPC, app, build, gear, "Tasha Brooks", { hands = "wraps", detail = "medium", name = "Tasha Brooks" })
	check("CreateNPC runs", ok, res)
	npc = ok and res or nil
	check("CreateNPC returns a model", npc ~= nil)
	if npc then
		check("the NPC comes back unparented (the caller places it)", npc.Parent == nil, tostring(npc.Parent))
		check("its root is not left anchored by the staging", npc.HumanoidRootPart.Anchored == false)
		check("rig operations happened (" .. #swapLog .. " swaps)", #swapLog >= 10, #swapLog)
		local unstaged = 0
		for _, s in ipairs(swapLog) do
			if not s.staged then
				unstaged += 1
			end
		end
		check("every ReplaceBodyPartR15 saw the model inside a container", unstaged == 0, unstaged .. " swaps on an unparented model")
		check("the staging container is empty again", #stage:GetChildren() == 0, #stage:GetChildren())
		local head = npc:FindFirstChild("Head")
		check("the classic head swap took (Part + SpecialMesh)", head and head.ClassName == "Part" and head:FindFirstChildOfClass("SpecialMesh") ~= nil)
		check("the body is tiered", type(npc:GetAttribute("BodyTiers")) == "string" and npc:GetAttribute("BodyTiers"):find("[1-9]") ~= nil, npc:GetAttribute("BodyTiers"))
		check("no swap failure was warned", BuilderTiers.SwapFailures == 0 and BuilderHead.SwapFailures == 0, BuilderTiers.SwapFailures .. "/" .. BuilderHead.SwapFailures)
		check("HeadSizeAtBuild / HipHeightAtBuild are recorded", typeof(npc:GetAttribute("HeadSizeAtBuild")) == "Vector3" and type(npc:GetAttribute("HipHeightAtBuild")) == "number")
		npc.Parent = E.workspace
	end
end

-- without a container (none could be made: the old behaviour) it still builds, warned once
do
	Builder.Services.Stage = nil -- (the host's ServerStorage takes no fake Instances: the folder cannot be made)
	swapLog = {}
	local n0 = #warns
	local ok, m = pcall(Builder.CreateNPC, app, build, gear, "NoStage", { hands = "wraps", detail = "low" })
	check("CreateNPC without a container still builds", ok and m ~= nil, m)
	local unstaged = 0
	for _, s in ipairs(swapLog) do
		if not s.staged then
			unstaged += 1
		end
	end
	check("...and its swaps really ran on an unparented model (the thing the staging prevents)", unstaged > 0)
	check("...with a warning once", #warns == n0 + 1 and warned("no staging container"), #warns - n0)
	pcall(Builder.CreateNPC, app, build, gear, "NoStage2", { hands = "wraps", detail = "low" })
	check("...only once", #warns == n0 + 1, #warns - n0)
	if ok and m then
		m:Destroy()
	end
	Builder.Services.Stage = stage
end

------------------------------------------------------------------------
-- swap verification: a refused swap is counted and warned with a [Boxer] line
------------------------------------------------------------------------
do
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
	refuse = { LeftUpperLeg = true, Head = true }
	local n0 = #warns
	local ok, m = pcall(Builder.CreateNPC, app, build, gear, "Refused", { hands = "wraps", detail = "low" })
	check("CreateNPC runs when the engine refuses two swaps", ok and m ~= nil, m)
	check("the refused body part swap is counted", BuilderTiers.SwapFailures >= 1, BuilderTiers.SwapFailures)
	check("...and warned with a [Boxer] line naming the part", warned("[Boxer] body part swap did not take") and warned("LeftUpperLeg"), warns[n0 + 1])
	check("the refused head swap is counted", BuilderHead.SwapFailures >= 1, BuilderHead.SwapFailures)
	check("...and warned", warned("[Boxer] classic head swap did not take") ~= nil)
	if m then
		check("the refused part stays the default part (no BodyTier)", m.LeftUpperLeg:GetAttribute("BodyTier") == nil)
		check("the refused head stays a MeshPart", m.Head.ClassName == "MeshPart")
		-- the diagnostic says so
		m.Parent = E.workspace
		local okR, lines, verdicts = pcall(Diag.Report, m, { label = "NPC1", side = "server" })
		check("Diag.Report on the refused rig", okR, lines)
		if okR then
			local text = table.concat(lines, "\n")
			check("...flags the MeshPart head", text:find("BAD  Head is a MeshPart", 1, true) ~= nil)
			check("...flags the default part on a tiered body", text:find("default (untiered) parts on a tiered body: LeftUpperLeg", 1, true) ~= nil)
		end
		m:Destroy()
	end
	-- the same reason is warned once only
	local before = #warns
	pcall(Builder.CreateNPC, app, build, gear, "Refused2", { hands = "wraps", detail = "low" })
	local again = 0
	for i = before + 1, #warns do
		if warns[i]:find("swap did not take", 1, true) then
			again += 1
		end
	end
	check("a repeated failure for the same reason is not warned again", again == 0, again)
	refuse = {}
end

------------------------------------------------------------------------
-- FixHipHeight: the tier legs' value back after the engine changed it
------------------------------------------------------------------------
if npc then
	local hum = npc:FindFirstChildOfClass("Humanoid")
	local legs = BuilderTiers.HipHeight(npc)
	check("the built NPC's HipHeight is the legs' own", legs and math.abs(hum.HipHeight - legs) < 0.01, tostring(hum.HipHeight) .. " vs " .. tostring(legs))
	hum.HipHeight = hum.HipHeight + 0.4 -- the engine's deferred scaling pass
	local h = BuilderTiers.FixHipHeight(npc)
	check("FixHipHeight puts it back", h and math.abs(hum.HipHeight - legs) < 0.01, tostring(h))
	check("FixHipHeight is change-only", BuilderTiers.FixHipHeight(npc) == nil)
	-- the delayed re-fix Builder schedules after a build
	hum.HipHeight = hum.HipHeight + 0.4
	local app2, build2 = app, build
	pcall(Builder.Cosmetics, npc, app2, build2, gear, { hands = "wraps", detail = "medium" })
	hum.HipHeight = legs + 0.3
	ltask.wait(0.4)
	check("Builder re-fixes HipHeight a moment after a build", math.abs(hum.HipHeight - legs) < 0.01 and npc:GetAttribute("HipHeightRefixed") ~= nil,
		tostring(hum.HipHeight) .. " vs " .. tostring(legs))
end

------------------------------------------------------------------------
-- Diag: a player rig, the NPC, a referee
------------------------------------------------------------------------
local function reportOf(model, ctx)
	local ok, lines, verdicts = pcall(Diag.Report, model, ctx)
	check("Diag.Report on " .. model.Name .. " runs", ok, lines)
	if not ok then
		return "", {}
	end
	check("...ends its block", lines[#lines] == "== end " .. model.Name, lines[#lines])
	return table.concat(lines, "\n"), verdicts
end
do
	-- a player: the rig built in workspace by Builder.Cosmetics (as Builder.Apply does on a live character)
	local sc = Builder.Scales(app, build, {})
	local pm = newRig(Vector3.new(sc.width, sc.height, sc.depth), E.workspace)
	pm.Name = "Player1"
	local ok = pcall(Builder.Cosmetics, pm, app, build, gear, { hands = "gloves", detail = "full" })
	check("Cosmetics on the player rig", ok)
	local text, verdicts = reportOf(pm, { label = "LOCAL", side = "client", rig = { geo = { ok = false }, joints = {}, lod = 3, a = {} } })
	if process.args[1] == "--print" then
		print(Diag.Block(select(2, pcall(Diag.Report, pm, { label = "LOCAL", side = "client", rig = { geo = { ok = false }, joints = {}, lod = 3, a = {} } }))))
	end
	check("player report: parts listed", text:find("part Head", 1, true) ~= nil and text:find("part RightFoot", 1, true) ~= nil)
	check("player report: every motor listed with its attachments", select(2, text:gsub("motor %u", "")) == 15 and text:find("att0=", 1, true) ~= nil)
	check("player report: BodyAssetData's expected attachment printed for a tier part", text:find("exp1=", 1, true) ~= nil)
	check("player report: HipHeight OK", text:find("OK   HipHeight", 1, true) ~= nil, text:match("VERDICT[^\n]*HipHeight[^\n]*"))
	check("player report: soles at HipHeight", text:find("OK   soles at HipHeight", 1, true) ~= nil, text:match("VERDICT[^\n]*soles[^\n]*"))
	check("player report: classic head OK", text:find("OK   Head is a Part + SpecialMesh Head", 1, true) ~= nil)
	check("player report: tiers OK", text:find("OK   every body part is a tier part", 1, true) ~= nil)
	check("player report: headgear measured against the head", text:find("headgear HGShell", 1, true) ~= nil and text:find("Headgear HGShell", 1, true) ~= nil)
	check("player report: an unmeasured Animator rig is flagged", text:find("BAD  the Animator could not measure this rig", 1, true) ~= nil)
	check("player report: no Animate tracks", text:find("OK   no Animate tracks playing", 1, true) ~= nil)
	-- a joint knocked off its attachment and a HipHeight that drifted are caught
	local hum = pm:FindFirstChildOfClass("Humanoid")
	hum.HipHeight = hum.HipHeight + 0.5
	local knee = pm.RightLowerLeg.RightKnee
	knee.C0 = knee.C0 * CFrame.new(0, 0.3, 0)
	local text2 = reportOf(pm, { side = "server" })
	check("drifted HipHeight flagged", text2:find("BAD  HipHeight", 1, true) ~= nil and text2:find("BAD  HipHeight changed since the build", 1, true) ~= nil)
	check("a joint off its RigAttachment flagged", text2:find("BAD  RightKnee.C0 is 0.300 studs off", 1, true) ~= nil, text2:match("VERDICT[^\n]*RightKnee[^\n]*"))
	-- a head the engine rescaled after the build
	pm.Head.Size = pm.Head.Size * 1.1
	local text3 = reportOf(pm, { side = "server" })
	check("a head rescaled after the build flagged", text3:find("BAD  the Head changed size after the layers were built", 1, true) ~= nil)
	-- an Animate track playing: a conflicting writer
	local an = E.new("Animator", hum)
	an.GetPlayingAnimationTracks = function()
		return { { Name = "walk", Weight = 1 } }
	end
	local text4 = reportOf(pm, { side = "client" })
	check("a playing Animate track flagged", text4:find("BAD  Animate track(s) playing [walk:1.00]", 1, true) ~= nil, text4:match("VERDICT[^\n]*Animate[^\n]*"))
	-- the motion sample
	local S = Diag.NewSample()
	for i = 0, 20 do
		pm.HumanoidRootPart.CFrame = CFrame.new(i * 0.16, 3, 0)
		pm.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
		pm.LeftFoot.CFrame = CFrame.new(i * 0.16, 0.2, 0)
		pm.RightFoot.CFrame = CFrame.new(i * 0.16, 0.2 + (i % 2) * 0.3, 0)
		Diag.SampleTick(S, pm, i / 10)
	end
	local res = Diag.SampleLines(S)
	check("sample lines (21 ticks)", #res.lines == 22 and res.lines[1]:find("sample 21 ticks", 1, true) ~= nil, res.lines[1])
	check("sample: knees that never bent are flagged", table.concat(res.verdicts, "\n"):find("knees never bent", 1, true) ~= nil)
	check("sample: Animate tracks over the sample flagged", table.concat(res.verdicts, "\n"):find("Animate tracks were playing on 21 of 21", 1, true) ~= nil)
	pm:Destroy()
end
if npc then
	local text = reportOf(npc, { label = "NPC1", side = "server" })
	check("NPC report: in the DataModel line", text:find("side=server", 1, true) ~= nil)
	check("NPC report: humanoid line", text:find("humanoid HipHeight=", 1, true) ~= nil)
	check("NPC report: bind-pose heights with the unit rig's", text:find("bindpose heights above the sole", 1, true) ~= nil and text:find("(unit ", 1, true) ~= nil)
end
do
	local appR, bR, gearR, optsR = Officials.Look(11, "referee", { venue = "ClubArena" })
	local ok, ref = pcall(Builder.CreateNPC, appR, bR, gearR, "Referee", optsR)
	check("the referee builds", ok and ref ~= nil, ref)
	if ok and ref then
		ref.Parent = E.workspace
		local text = reportOf(ref, { label = "NPC2", side = "server" })
		check("referee report: the cap measured against the head", text:find("hat: ", 1, true) ~= nil, text:match("hat[^\n]*"))
		ref:Destroy()
	end
end
-- Diag.Pick: the own character first, then the nearest humanoid models
do
	local own = newRig(Vector3.one, E.workspace)
	own.Name = "Me"
	own.HumanoidRootPart.CFrame = CFrame.new(1000, 3, 0)
	local far = newRig(Vector3.one, E.workspace)
	far.Name = "Far"
	far.HumanoidRootPart.CFrame = CFrame.new(1050, 3, 0)
	local near = newRig(Vector3.one, E.workspace)
	near.Name = "Near"
	near.HumanoidRootPart.CFrame = CFrame.new(1005, 3, 0)
	local picked = Diag.Pick(Vector3.new(1000, 3, 0), own, 1, E.workspace)
	check("Diag.Pick: own first, then the nearest", #picked == 2 and picked[1] == own and picked[2] == near, #picked)
	local block = Diag.Block({ "a", "b" })
	check("Diag.Block prefixes every line", block == "[WCBDIAG] a\n[WCBDIAG] b", block)
end

------------------------------------------------------------------------
-- The headgear against what the engine does to the head AFTER the build (what the Studio diagnostic showed: every
-- gear part weld->NONE studs away, the Humanoid dead on a missing Neck; the MeshPart head conversion; a rescale):
--   * every head-worn part is joined by a Weld under the part (Part0 = Head, C0 = the part in head space)
--   * the Humanoid never dies on its Neck and never breaks its joints (RequiresNeck / BreakJointsOnDeath off)
--   * the head instance replaced by a MeshPart after the build -> the gear is rebuilt on and sized from the new head
--   * a Size change after the build -> rebuilt to the new size (the followHead watch, through the property signal)
--   * the late re-fit (Builder.RefitHeadgear / OnPlaced): a no-op while nothing changed; a rebuild, warned with one
--     "[Boxer] headgear refit" line, when every weld is gone (BreakJointsOnDeath) - the cap too, from its record
--   * Head.EnsureNeck: an AnimationConstraint neck (the avatar joint upgrade) is left alone, no neck at all is
--     rebuilt as a Motor6D from the RigAttachments
--   * Diag's HEADGEAR block: the head line, a line per part with its weld's Part0 / Part1, the folder's fit record,
--     "headgear detached" when the welds are gone, OK when they hold
------------------------------------------------------------------------
do
	local Head = BuilderHead
	local function gearParts(model, fname)
		local look = model:FindFirstChild("BoxerLook")
		local f = look and look:FindFirstChild(fname or "Headgear")
		local out = {}
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				out[#out + 1] = d
			end
		end
		return out, f
	end
	-- every part: a Weld under it, Part0 the model's live head, placed where its C0 says, no WeldConstraint
	local function weldedTo(model, fname)
		local head = model:FindFirstChild("Head")
		local parts = gearParts(model, fname)
		if #parts == 0 then
			return false, "no parts"
		end
		for _, p in ipairs(parts) do
			local w = p:FindFirstChildOfClass("Weld")
			if not (w and w.Parent == p and w.Part0 == head and w.Part1 == p) or p:FindFirstChildOfClass("WeldConstraint") then
				return false, p.Name .. " weld"
			end
			if ((head.CFrame * w.C0 * w.C1:Inverse()).Position - p.Position).Magnitude > 1e-3 then
				return false, p.Name .. " C0"
			end
		end
		return true
	end
	local function spanOf(model)
		local parts = gearParts(model)
		local head = model:FindFirstChild("Head")
		local hs = Head.HeadSpan(head)
		for _, p in ipairs(parts) do
			if p.Name == "HGShell" then
				return p.Size.X / hs, hs
			end
		end
		return nil, hs
	end
	local function refitWarns()
		local n = 0
		for _, w in ipairs(warns) do
			if w:find("[Boxer] headgear refit", 1, true) then
				n += 1
			end
		end
		return n
	end

	local a = Looks.Random(777, 1, { age = 24, class = 5 })
	local m = Builder.CreateNPC(a, buildOf(60), gear, "Refit", { hands = "wraps", detail = "full" })
	check("refit: the NPC builds", m ~= nil)
	m.Parent = E.workspace
	local hum = m:FindFirstChildOfClass("Humanoid")
	check("refit: RequiresNeck and BreakJointsOnDeath are off on a built character", hum.RequiresNeck == false and hum.BreakJointsOnDeath == false)
	local okW, why = weldedTo(m)
	check("refit: every headgear part joined by a Weld under it (Part0 the head, C0 the part in head space)", okW, why)
	local hg0, f0 = gearParts(m)
	check("refit: the folder records the head it was fitted to", f0:GetAttribute("HeadClass") == "Part" and (f0:GetAttribute("HeadSize") - m.Head.Size).Magnitude < 1e-6
		and tostring(f0:GetAttribute("HeadMesh")):find("SpecialMesh Head", 1, true) ~= nil, tostring(f0:GetAttribute("HeadMesh")))
	local ratio0 = spanOf(m)

	-- the late re-fit: a no-op while nothing changed
	local refits0, wn0 = Head.Refits, refitWarns()
	check("refit: GearStale is nil on an untouched rig", Head.GearStale(m, f0) == nil, Head.GearStale(m, f0))
	check("refit: RefitHeadgear is a no-op while nothing changed", Builder.RefitHeadgear(m) == nil and Head.Refits == refits0 and refitWarns() == wn0
		and gearParts(m)[1] == hg0[1] and m:GetAttribute("HeadgearRefits") == nil)

	-- every weld gone (the Humanoid died with BreakJointsOnDeath): Diag says so, the re-fit rebuilds and warns
	for _, p in ipairs(gearParts(m)) do
		for _, c in ipairs(p:GetChildren()) do
			if c.ClassName == "Weld" then
				c:Destroy()
			end
		end
		p.CFrame = p.CFrame * CFrame.new(0, -400, 0)
	end
	local okD, dlines, dverd = pcall(Diag.Report, m, {})
	local dtext, dv = okD and table.concat(dlines, "\n") or tostring(dlines), okD and table.concat(dverd, "\n") or ""
	check("refit: Diag on the detached gear runs", okD, dlines)
	check("refit: Diag VERDICT 'headgear detached: 11 parts with no weld'", dv:find("BAD  headgear detached: " .. Head.HEADGEAR_PARTS.full .. " parts with no weld", 1, true) ~= nil, dv:match("[^\n]*detached[^\n]*"))
	local hsz = m.Head.Size
	check("refit: Diag HEADGEAR lines: the head, the parts' welds, the fit record", dtext:find(string.format("HEADGEAR head Part size=(%.3f,%.3f,%.3f) span=%.3f", hsz.X, hsz.Y, hsz.Z, math.min(hsz.X, hsz.Y, hsz.Z)), 1, true) ~= nil
		and dtext:find("HEADGEAR Headgear HGShell", 1, true) ~= nil and dtext:find("weld=NONE Part0=nil", 1, true) ~= nil
		and dtext:find(string.format("HEADGEAR Headgear fitted to HeadSize=(%.2f,%.2f,%.2f) HeadClass=Part", hsz.X, hsz.Y, hsz.Z), 1, true) ~= nil, dtext:match("HEADGEAR head[^\n]*"))
	local wn2 = refitWarns()
	local res = Builder.RefitHeadgear(m)
	check("refit: RefitHeadgear rebuilds detached gear and says why", type(res) == "table" and tostring(res.Headgear):find("11 of 11 parts with no weld", 1, true) ~= nil
		and weldedTo(m) and refitWarns() == wn2 + 1 and warned("Headgear 11 of 11 parts with no weld") ~= nil, res and res.Headgear)
	local _, verd2 = Diag.Report(m, {})
	local v2 = table.concat(verd2, "\n")
	check("refit: Diag OK after the re-fit", v2:find("OK   headgear: 11 parts welded to the live head", 1, true) ~= nil, v2:match("[^\n]*headgear[^\n]*"))
	local f3 = select(2, gearParts(m))
	check("refit: the rebuilt folder is sealed again (the next Cosmetics keeps it)", f3:GetAttribute("Sig") ~= nil)
	local keep = gearParts(m)[1]
	pcall(Builder.Cosmetics, m, a, buildOf(60), gear, { hands = "wraps", detail = "full" })
	check("refit: ...and Cosmetics does keep it", gearParts(m)[1] == keep)

	-- the head instance replaced by a MeshPart after the build (the engine's MeshPart head conversion, a later swap)
	local wnA = refitWarns()
	local old = m.Head
	local mp = E.new("MeshPart")
	mp.Name = "Head"
	mp.Size = Vector3.new(1.2, 1.2, 1.2)
	mp.CFrame = old.CFrame
	mp.MeshId = "rbxassetid://1"
	for _, c in ipairs(old:GetChildren()) do
		if c.ClassName == "Attachment" or c.ClassName == "Motor6D" then
			c.Parent = mp
			if c.ClassName == "Motor6D" then
				c.Part1 = mp
			end
		end
	end
	mp.Parent = m
	old:Destroy()
	ltask.wait()
	ltask.wait()
	local hg1, f1 = gearParts(m)
	local ratio1, hs1 = spanOf(m)
	check("refit: a head replaced by a MeshPart rebuilds the headgear on the new head", f1 ~= f0 and hg1[1] ~= hg0[1] and #hg1 == #hg0 and weldedTo(m), select(2, weldedTo(m)))
	check("refit: ...sized from the new head (the same geometry in spans of a 1.2 head)", math.abs(hs1 - 1.2) < 1e-6 and ratio1 and math.abs(ratio1 - ratio0) < 1e-6,
		tostring(ratio1) .. " vs " .. tostring(ratio0))
	check("refit: ...the folder now records the MeshPart", f1:GetAttribute("HeadClass") == "MeshPart" and tostring(f1:GetAttribute("HeadMesh")):find("MeshPart 1", 1, true) ~= nil)
	check("refit: ...one [Boxer] headgear refit line naming the head change", refitWarns() == wnA + 1 and warned("headgear refit Refit: Headgear") ~= nil
		and (warned("no longer in the model") ~= nil or warned("Part -> MeshPart") ~= nil), warns[#warns])
	check("refit: ...counted on the model (Diag)", m:GetAttribute("HeadgearRefits") == 2 and tostring(m:GetAttribute("HeadgearRefitLast")):find("Headgear:", 1, true) ~= nil)

	-- a Size change after the build (the Humanoid's deferred scaling pass)
	local wn1 = refitWarns()
	m.Head.Size = Vector3.new(0.9, 0.9, 0.9)
	ltask.wait()
	ltask.wait()
	local hg2, f2 = gearParts(m)
	local ratio2, hs2 = spanOf(m)
	check("refit: a Size change after the build rebuilds the headgear to the new size", f2 ~= f1 and #hg2 == #hg0 and math.abs(hs2 - 0.9) < 1e-6 and ratio2
		and math.abs(ratio2 - ratio0) < 1e-6 and weldedTo(m), tostring(ratio2))
	check("refit: ...warned once, naming the sizes", refitWarns() == wn1 + 1 and warned("Head.Size (1.200,1.200,1.200) -> (0.900,0.900,0.900)") ~= nil, warns[#warns])
	check("refit: ...the same Size written again is silent", (function()
		m.Head.Size = Vector3.new(0.9, 0.9, 0.9)
		ltask.wait()
		return gearParts(m)[1] == hg2[1] and refitWarns() == wn1 + 1
	end)())

	-- Builder.OnPlaced: the delayed passes find and fix a head rescaled after the parent
	m.Head.Size = Vector3.new(1.0, 1.0, 1.0)
	-- (the watch is defeated here: a clone's parts carry no connections, so only the late re-fit can catch it)
	local c = m:Clone()
	c.Name = "RefitClone"
	c.Parent = E.workspace
	c.Head.Size = Vector3.new(1.1, 1.1, 1.1)
	c:SetAttribute("HeadgearRefits", nil)
	local cp0 = gearParts(c)[1]
	check("refit: the clone's gear is welded to the clone's head", weldedTo(c))
	Builder.OnPlaced(c)
	Builder.OnPlaced(c)
	ltask.wait(0.5)
	local cr1, chs1 = spanOf(c)
	check("refit: OnPlaced re-fits 0.3 s after the parent (once, not twice)", gearParts(c)[1] ~= cp0 and math.abs(chs1 - 1.1) < 1e-6 and cr1 and math.abs(cr1 - ratio0) < 1e-6
		and c:GetAttribute("HeadgearRefits") == 1, tostring(c:GetAttribute("HeadgearRefits")))
	local cp1 = gearParts(c)[1]
	ltask.wait(2)
	check("refit: the 2 s pass is a no-op when nothing changed since", gearParts(c)[1] == cp1 and c:GetAttribute("HeadgearRefits") == 1)
	c:Destroy()

	-- the Neck: an AnimationConstraint neck is left alone; none at all is rebuilt from the RigAttachments
	local neck = m.Head:FindFirstChild("Neck")
	check("neck: the built rig has its Motor6D Neck, EnsureNeck leaves it", neck ~= nil and Head.EnsureNeck(m) == "ok" and m.Head:FindFirstChild("Neck") == neck)
	neck.Parent = nil
	local ac = E.new("AnimationConstraint", m.Head)
	ac.Name = "Neck"
	ac.Attachment0 = m.UpperTorso:FindFirstChild("NeckRigAttachment")
	ac.Attachment1 = m.Head:FindFirstChild("NeckRigAttachment")
	check("neck: an AnimationConstraint neck (the avatar joint upgrade) counts, no Motor6D is added", Head.EnsureNeck(m) == "ok" and m.Head:FindFirstChildOfClass("Motor6D") == nil)
	ac:Destroy()
	check("neck: with no neck joint at all a Motor6D Neck is rebuilt from the RigAttachments", Head.EnsureNeck(m) == "rebuilt" and (function()
		local n = m.Head:FindFirstChild("Neck")
		return n and n.ClassName == "Motor6D" and n.Part0 == m.UpperTorso and n.Part1 == m.Head and n.C0 == m.UpperTorso.NeckRigAttachment.CFrame
			and n.C1 == m.Head.NeckRigAttachment.CFrame
	end)())
	check("neck: ...and is left alone after that", Head.EnsureNeck(m) == "ok")
	-- the swap path: a rig whose head swap drops the Neck gets it back and warns once
	do
		local a2 = Looks.Random(778, 2, { age = 24, class = 5 })
		local n0 = #warns
		local m2 = Builder.CreateNPC(a2, buildOf(60), gear, "NoNeck", { hands = "wraps", detail = "medium" })
		check("neck: a built NPC has exactly one Neck joint on the head", m2 and (function()
			local n = 0
			for _, ch in ipairs(m2.Head:GetChildren()) do
				if ch.ClassName == "Motor6D" or ch.ClassName == "AnimationConstraint" then
					n += 1
				end
			end
			return n == 1
		end)())
		check("neck: no Neck warning on a rig that keeps it", #warns == n0 or not warned("left no Neck joint"))
		if m2 then
			m2:Destroy()
		end
	end
	m:Destroy()

	-- the referee's cap: the same re-fit from its own record (style, colours, detail)
	local rapp, rbuild, rgear, ropts = Officials.Look(31, "referee", { venue = "ClubArena" })
	local ref = Builder.CreateNPC(rapp, rbuild, rgear, "Referee", ropts)
	check("cap refit: the referee builds", ref ~= nil)
	ref.Parent = E.workspace
	local okC, whyC = weldedTo(ref, "Hat")
	check("cap refit: every cap part joined by a Weld under it", okC, whyC)
	local hat0 = select(2, gearParts(ref, "Hat"))
	local crown0 = hat0:FindFirstChild("RCCrown")
	check("cap refit: a no-op while nothing changed", Builder.RefitHeadgear(ref) == nil and hat0:FindFirstChild("RCCrown") == crown0)
	for _, p in ipairs(gearParts(ref, "Hat")) do
		for _, ch in ipairs(p:GetChildren()) do
			if ch.ClassName == "Weld" then
				ch:Destroy()
			end
		end
	end
	local _, rverd = Diag.Report(ref, {})
	check("cap refit: Diag VERDICT 'hat detached'", table.concat(rverd, "\n"):find("BAD  hat detached: " .. #gearParts(ref, "Hat") .. " parts with no weld", 1, true) ~= nil)
	local rres = Builder.RefitHeadgear(ref)
	local hat1 = select(2, gearParts(ref, "Hat"))
	local crown1 = hat1 and hat1:FindFirstChild("RCCrown")
	check("cap refit: the cap is rebuilt from its record, the same style, colour and part count, welded again", type(rres) == "table" and rres.Hat ~= nil and hat1 ~= hat0
		and hat1:GetAttribute("Style") == "referee" and crown1 and crown1.Color == crown0.Color and #gearParts(ref, "Hat") == Head.CAP_PARTS.referee.medium and weldedTo(ref, "Hat")
		and hat1:GetAttribute("Sig") ~= nil and warned("headgear refit Referee: Hat") ~= nil, rres and rres.Hat)
	ref:Destroy()
end

print(string.format("test_npcbuild: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
