--!nocheck
-- tools/sim/test_meshfallback.luau: a mesh that does not arrive never shows as a box, BaldMode leaves no hair, and every
-- built piece on every NPC kind is welded to its body part and sits on it.
--   * Kit.MeshLoaded: an empty MeshId / a zero MeshSize is no mesh; a stub without the properties is trusted
--   * BuilderGear: CreateMeshPartAsync returning a part with no geometry, or failing with "Asset content representation is
--     being generated": the gloves are the part-built rounded gloves (Sphere meshes, no MeshPart), the retry is
--     scheduled on Kit.ASSET_BACKOFF; when the mesh answers, the template loads, Kit.AssetReady fires and Builder
--     rebuilds the boxer with the mesh gloves (Builder.RetryBuilds); BuilderTiers the same with the default part kept
--   * MeshGuard (client): a tagged gear MeshPart whose fetch status is Failure is hidden and a welded Sphere stand-in of its
--     size drawn; thin pieces are hidden only; an empty MeshId falls back at once; the retry is scheduled; Success
--     restores the part and removes the stand-in
--   * BaldMode: no Hair / Beard parts and no hair accessory on anyone; the avatar's HairAccessory never enters the
--     description; the venues' cheap figures carry no Hair blob
--   * fit audit (Kit.FitAudit, as the diagnostic's hands / headgear / attire blocks): gym members (gloves, wraps, bare),
--     sparring partners in headgear, coaches, the referee, the cornerman / cutman, a fight-night opponent and a player's
--     boxer: every piece welded to a live part of the model, the weld reproducing its place, the piece on its part; and
--     a headgear pad moved off its C0 is caught
--   lune run tools/sim/test_meshfallback.luau
local roblox = require("@lune/roblox")
local ltask = require("@lune/task")
local process = require("@lune/process")
local fs = require("@lune/fs")
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

local E = FE.new()
local H = Host.new({ server = true, globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace,
	warn = function() end } })
E.install(H)
local Config = H.require("Config")
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderGear = H.require("BuilderGear")
local Kit = H.require("BuilderKit")
local Builder = H.require("Builder")
local BuilderHead = H.require("BuilderHead")
local Looks = H.require("Looks")
local Officials = H.require("Officials")
local MeshGuard = H.require("MeshGuard")

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

-- the asset service: mode[id] = nil (loads) | "empty" (a part with no geometry) | "generating" (the error Studio printed)
local mode = {}
local defaultMode = nil
local calls = 0
local AS = {}
function AS.CreateMeshPartAsync(_, content)
	calls += 1
	local id = tonumber(tostring(content):match("(%d+)%s*$"))
	local m = mode[id] or defaultMode
	if m == "generating" then
		error("ContentId: rbxassetid://" .. id .. " failed due to: Asset content representation is being generated", 0)
	end
	local mp = E.new("MeshPart")
	mp.MeshId = m == "empty" and "" or ("rbxassetid://" .. tostring(id))
	if m == "empty" then
		mp.MeshSize = Vector3.zero
	end
	return mp
end
local Content = { fromUri = function(u)
	return u
end }
local scheduled = {}
Kit.Services.schedule = function(delay, fn)
	table.insert(scheduled, { delay = delay, fn = fn })
	return true
end
local function runScheduled()
	local list = scheduled
	scheduled = {}
	for _, s in ipairs(list) do
		s.fn()
	end
	return #list
end
local function reset()
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = AS, Content = Content }
	BuilderGear.Reset()
	BuilderGear.Services = { AssetService = AS, Content = Content }
	table.clear(mode)
	defaultMode = nil
	scheduled = {}
end
Builder.RETRY_SETTLE = 0

local function buildOf(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end
local function folder(model, name)
	local look = model:FindFirstChild("BoxerLook")
	return look and look:FindFirstChild(name)
end
local function partsOf(f)
	local out = {}
	for _, d in ipairs(f and f:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
local function meshCount(f)
	local n = 0
	for _, p in ipairs(partsOf(f)) do
		if p.ClassName == "MeshPart" then
			n += 1
		end
	end
	return n
end
-- a MeshPart under BoxerLook that would draw as a box: no mesh content
local function boxes(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "MeshPart" and (d.MeshId == "" or d.MeshId == nil) and d:GetAttribute("BodyTier") == nil and d:GetAttribute("GearPiece") ~= nil then
			n += 1
		end
		if d.ClassName == "MeshPart" and d:GetAttribute("BodyTier") ~= nil and d.MeshId == "" then
			n += 1
		end
	end
	return n
end
local function npc(seed, opts, gender)
	local app = Looks.Random(seed, gender or 1, { age = 30, class = 5 })
	local build = Looks.RandomBuild(seed, 0.55, 30, app.body.frame)
	local m = Builder.CreateNPC(app, build, { gloves = "Competition", wraps = "OldWraps" }, "NPC" .. seed, opts)
	if m then
		m.Parent = E.workspace
	end
	return m, app, build
end

------------------------------------------------------------------------
-- Kit.MeshLoaded
------------------------------------------------------------------------
do
	local a = E.new("MeshPart")
	a.MeshId = "rbxassetid://1"
	a.MeshSize = Vector3.new(1, 2, 1)
	check("MeshLoaded: a named mesh with a size", Kit.MeshLoaded(a) == true)
	local b = E.new("MeshPart")
	b.MeshId = ""
	check("MeshLoaded: an empty MeshId is no mesh", Kit.MeshLoaded(b) == false)
	local c = E.new("MeshPart")
	c.MeshId = "rbxassetid://1"
	c.MeshSize = Vector3.zero
	check("MeshLoaded: a zero MeshSize is no mesh", Kit.MeshLoaded(c) == false)
	check("MeshLoaded: a stub without the properties is trusted", Kit.MeshLoaded(E.new("MeshPart")) == true)
	check("Transient: 'being generated' is retried soon", Kit.Transient("Asset content representation is being generated"))
end

------------------------------------------------------------------------
-- gear meshes that do not arrive: rounded part-built gloves, the backoff, the swap when they load
------------------------------------------------------------------------
for _, how in ipairs({ "empty", "generating" }) do
	reset()
	-- the body loads; every gear mesh fails this way
	local gearIds = {}
	for _, q in ipairs(BuilderGear.PreloadList()) do
		gearIds[q.id] = true
	end
	for id in pairs(gearIds) do
		mode[id] = how
	end
	local m, mApp, mBuild = npc(4100, { hands = "gloves", detail = "medium", name = "Glover" })
	check(how .. ": the NPC is built", m ~= nil)
	if m then
		local hands = folder(m, "Hands")
		local g = hands and hands:FindFirstChild("GloveR")
		check(how .. ": the gloves are the part-built gloves (no MeshPart in Hands)", hands ~= nil and meshCount(hands) == 0, hands and meshCount(hands))
		check(how .. ": the glove is a rounded shape (Sphere mesh), not a block", g ~= nil and g.ClassName == "Part" and g:FindFirstChildOfClass("SpecialMesh") ~= nil)
		check(how .. ": no gear MeshPart without a mesh anywhere", boxes(m) == 0, boxes(m))
		check(how .. ": the attire is part-built too", meshCount(folder(m, "Attire")) == 0)
		check(how .. ": the failures are counted", BuilderGear.Failing() and BuilderGear.Stats().failed > 0)
		check(how .. ": the boxer waits for a rebuild", Builder.PendingRetries() >= 1, Builder.PendingRetries())
		local delays = {}
		for _, s in ipairs(scheduled) do
			delays[s.delay] = true
		end
		check(how .. ": retries scheduled on the first backoff step (" .. Kit.ASSET_BACKOFF[1] .. " s)", delays[Kit.ASSET_BACKOFF[1]] == true and #scheduled > 0, #scheduled)
		local c0 = calls
		Builder.Cosmetics(m, mApp, mBuild, { gloves = "Competition", wraps = "OldWraps" }, { hands = "gloves", detail = "medium", name = "Glover" })
		-- (the same boxer rebuilt before the backoff is due: no on-demand retry storm)
		check(how .. ": no reload before the backoff is due", calls == c0, calls - c0)
		-- still failing at the first retry: the next step is scheduled
		local n = runScheduled()
		local next2 = false
		for _, s in ipairs(scheduled) do
			if s.delay == Kit.ASSET_BACKOFF[2] then
				next2 = true
			end
		end
		check(how .. ": a failed retry schedules the next step (" .. Kit.ASSET_BACKOFF[2] .. " s)", n > 0 and next2)
		-- the meshes are ready now: the next retry loads them and the boxer is rebuilt with the mesh gloves
		table.clear(mode)
		runScheduled()
		ltask.wait(0.1)
		E.step(3)
		hands = folder(m, "Hands")
		g = hands and hands:FindFirstChild("GloveR")
		check(how .. ": loaded later: no gear mesh failing", not BuilderGear.Failing())
		check(how .. ": loaded later: the boxer was rebuilt with the mesh gloves", g ~= nil and g.ClassName == "MeshPart" and g:GetAttribute("GearMesh") ~= nil,
			g and g.ClassName)
		check(how .. ": loaded later: nothing pending", Builder.PendingRetries() == 0, Builder.PendingRetries())
		check(how .. ": loaded later: still no box", boxes(m) == 0)
	end
end

------------------------------------------------------------------------
-- body meshes that do not arrive: the default part stays, swapped in when they load
------------------------------------------------------------------------
do
	reset()
	defaultMode = "empty"
	local m = npc(4200, { hands = "wraps", detail = "low", name = "Bodyless" })
	check("body: built", m ~= nil)
	if m then
		check("body: no tier part swapped in (the default parts stay)", not tostring(m:GetAttribute("BodyTiers") or ""):find("[1-9]"), m:GetAttribute("BodyTiers"))
		check("body: no MeshPart without a mesh", boxes(m) == 0)
		check("body: failing, waiting for a rebuild", BuilderTiers.Failing() and Builder.PendingRetries() >= 1)
		defaultMode = nil
		runScheduled()
		ltask.wait(0.1)
		E.step(3)
		check("body: loaded later: the tier parts are swapped in", tostring(m:GetAttribute("BodyTiers") or ""):find("[1-9]") ~= nil, m:GetAttribute("BodyTiers"))
	end
	reset()
end

------------------------------------------------------------------------
-- MeshGuard: the client's stand-in for a mesh it cannot fetch
------------------------------------------------------------------------
do
	local function sig()
		local s = { fns = {} }
		function s:Connect(fn)
			table.insert(self.fns, fn)
			local c = {}
			function c.Disconnect()
				local i = table.find(s.fns, fn)
				if i then
					table.remove(s.fns, i)
				end
			end
			return c
		end
		function s:Fire(...)
			for _, fn in ipairs(table.clone(self.fns)) do
				fn(...)
			end
		end
		return s
	end
	local status, changed = {}, {}
	local stringPreloads = 0
	local CP = {
		GetAssetFetchStatus = function(_, id)
			return status[id] or "None"
		end,
		GetAssetFetchStatusChangedSignal = function(_, id)
			changed[id] = changed[id] or sig()
			return changed[id]
		end,
		PreloadAsync = function(_, list, cb)
			for _, item in ipairs(list) do
				-- (the engine fetches a bare string as an IMAGE: a mesh id asked for that way fails with "Asset
				-- type does not match"; given a MeshPart it fetches the MeshId as a mesh and reports that id)
				stringPreloads += 1
				local key = type(item) == "string" and item or item.MeshId
				if cb then
					cb(key, type(item) == "string" and "Failure" or (status[key] or "Loading"))
				end
			end
		end,
	}
	local added, tagged = sig(), {}
	local CS = {
		GetInstanceAddedSignal = function()
			return added
		end,
		GetInstanceRemovedSignal = function()
			return sig()
		end,
		GetTagged = function(_, tag)
			return tag == "WCBGearMesh" and tagged or {}
		end,
	}
	local gscheduled = {}
	MeshGuard.Reset()
	MeshGuard.Services = { ContentProvider = CP, CollectionService = CS, schedule = function(d, fn)
		table.insert(gscheduled, { delay = d, fn = fn })
		return true
	end }
	local f = E.new("Folder", E.workspace)
	local function piece(name, id, size)
		local p = E.new("MeshPart", f)
		p.Name = name
		p:SetAttribute("GearPiece", name)
		p.MeshId = id
		p.Size = size
		p.Color = Color3.fromRGB(200, 20, 20)
		p.CFrame = CFrame.new(1, 2, 3)
		return p
	end
	local glove = piece("GloveR", "rbxassetid://96507267130276", Vector3.new(0.6, 0.96, 0.83))
	local strap = piece("GloveStrap_R", "rbxassetid://79211211331902", Vector3.new(0.5, 0.23, 0.55))
	local fine = piece("BootFoot_R", "rbxassetid://5", Vector3.new(0.5, 0.4, 1))
	status["rbxassetid://96507267130276"] = "Failure"
	status["rbxassetid://79211211331902"] = "Failure"
	status["rbxassetid://5"] = "Success"
	table.insert(tagged, glove)
	MeshGuard.Start()
	added:Fire(strap)
	added:Fire(fine)
	ltask.wait()
	local fb = glove:FindFirstChild("MeshFallback")
	check("guard: the failed glove is hidden", glove.Transparency == 1)
	check("guard: a rounded stand-in of its size in its place", fb ~= nil and fb:FindFirstChildOfClass("SpecialMesh") ~= nil
		and fb:FindFirstChildOfClass("SpecialMesh").MeshType == Enum.MeshType.Sphere and (fb.Size - glove.Size).Magnitude < 1e-6)
	local w = fb and fb:FindFirstChildOfClass("Weld")
	check("guard: the stand-in is welded to the piece (follows every pose)", w ~= nil and w.Part0 == glove and w.Part1 == fb)
	check("guard: the stand-in wears the piece's colour", fb ~= nil and fb.Color == glove.Color)
	check("guard: a thin piece is hidden without a stand-in", strap.Transparency == 1 and strap:FindFirstChild("MeshFallback") == nil)
	check("guard: a mesh that loads is left alone", fine.Transparency == 0 and fine:FindFirstChild("MeshFallback") == nil)
	check("guard: retries scheduled on the backoff", #gscheduled >= 2 and gscheduled[1].delay == MeshGuard.BACKOFF[1], #gscheduled)
	-- still failing at the retry: the next step
	local list = gscheduled
	gscheduled = {}
	for _, s in ipairs(list) do
		s.fn()
	end
	ltask.wait()
	check("guard: a failed retry schedules the next step", #gscheduled >= 1 and gscheduled[1].delay == MeshGuard.BACKOFF[2], #gscheduled)
	-- the content is ready: the status signal turns Success
	status["rbxassetid://96507267130276"] = "Success"
	changed["rbxassetid://96507267130276"]:Fire("Success")
	check("guard: loaded: the glove shows again", glove.Transparency == 0)
	check("guard: loaded: the stand-in is gone", glove:FindFirstChild("MeshFallback") == nil)
	check("guard: never calls PreloadAsync (Studio logged 'Asset type does not match' for good meshes)", stringPreloads == 0, stringPreloads)
	-- a part that already has geometry (the server loaded its mesh) is never hidden, whatever a fetch status says
	local loaded = piece("Wrap_L", "rbxassetid://96507267130276", Vector3.new(0.4, 0.4, 0.6))
	loaded.MeshSize = Vector3.new(0.4, 0.44, 0.63)
	status["rbxassetid://96507267130276"] = "Failure"
	added:Fire(loaded)
	ltask.wait()
	check("guard: a part with loaded geometry is left alone on a stale Failure", loaded.Transparency == 0 and loaded:FindFirstChild("MeshFallback") == nil)
	-- an empty MeshId falls back at once
	local empty = piece("Glove_L", "", Vector3.new(0.6, 0.96, 0.83))
	added:Fire(empty)
	check("guard: an empty MeshId gets its stand-in at once", empty.Transparency == 1 and empty:FindFirstChild("MeshFallback") ~= nil)
	-- a body part with no mesh: its stand-in
	local leg = E.new("MeshPart", f)
	leg.Name = "LeftUpperLeg"
	leg:SetAttribute("BodyTier", 3)
	leg.MeshId = "rbxassetid://96507267130276x"
	leg.Size = Vector3.new(0.8, 1.6, 0.8)
	status["rbxassetid://96507267130276x"] = "TimedOut"
	added:Fire(leg)
	check("guard: a body part that timed out gets a stand-in", leg.Transparency == 1 and leg:FindFirstChild("MeshFallback") ~= nil)
	-- a piece the server destroys takes its stand-in along; Stop restores
	empty:Destroy()
	MeshGuard.Stop()
	check("guard: Stop restores the parts", strap.Transparency == 0 and leg.Transparency == 0 and leg:FindFirstChild("MeshFallback") == nil)
	MeshGuard.Services = {}
end

------------------------------------------------------------------------
-- BaldMode
------------------------------------------------------------------------
do
	reset()
	check("Config.BaldMode is on (the shipping setting)", Config.BaldMode == true)
	local app = Looks.Random(4300, 1, { age = 55, class = 5 })
	app.hair = app.hair or {}
	app.hair.style = "Afro"
	app.beard = { style = "None", growth = 1 }
	local m = npc(4300, { hands = "bare", detail = "full", name = "Hairy" })
	if m then
		-- an avatar hair accessory an ApplyDescription attached
		local acc = E.new("Accessory", m)
		acc.Name = "HairAcc"
		local h = E.new("Part", acc)
		h.Name = "Handle"
		local a = E.new("Attachment", h)
		a.Name = "HairAttachment"
		Builder.Cosmetics(m, app, buildOf(40), nil, { hands = "bare", detail = "full" })
		check("bald: no Hair parts", #partsOf(folder(m, "Hair")) == 0, #partsOf(folder(m, "Hair")))
		check("bald: no Beard parts (a full-grown beard)", #partsOf(folder(m, "Beard")) == 0, #partsOf(folder(m, "Beard")))
		check("bald: the avatar hair accessory is gone", m:FindFirstChild("HairAcc") == nil)
	end
	local desc = Builder.Description(app, buildOf(40), { avatar = { useHair = true, hair = "123,456", face = 0, head = 0 } })
	check("bald: the avatar's HairAccessory never enters the description", desc.HairAccessory == nil or desc.HairAccessory == "", desc.HairAccessory)
	for _, kind in ipairs({ "referee", "cornerman" }) do
		local a2, b2, g2, o2 = Officials.Look(77, kind, {})
		local off = Builder.CreateNPC(a2, b2, g2, kind, o2)
		check("bald: the " .. kind .. " has no hair or beard", off ~= nil and #partsOf(folder(off, "Hair")) == 0 and #partsOf(folder(off, "Beard")) == 0)
	end
	local venues = fs.readFile(Host.FindRoot() .. "/src/server/Venues.lua")
	check("bald: the venues' cheap figures draw no Hair blob in BaldMode", venues:find("and not Config.BaldMode", 1, true) ~= nil)
end

------------------------------------------------------------------------
-- fit audit over every NPC kind (mesh gear, then part-built gear)
------------------------------------------------------------------------
for _, gearMode in ipairs({ "mesh", "part-built" }) do
	reset()
	if gearMode == "part-built" then
		for _, q in ipairs(BuilderGear.PreloadList()) do
			mode[q.id] = "generating"
		end
	end
	local kinds = {}
	local function add(name, m)
		if m then
			table.insert(kinds, { name = name, model = m })
		else
			check(gearMode .. " " .. name .. ": built", false)
		end
	end
	add("gym member (gloves)", (npc(101, { hands = "gloves", detail = "low", name = "Rico" })))
	add("gym member (wraps)", (npc(202, { hands = "wraps", detail = "low", name = "Dee" }, 2)))
	add("coach (bare)", (npc(2222, { hands = "bare", detail = "low", name = "Coach Dre", age = 49 })))
	local spar = npc(1212, { hands = "gloves", detail = "low", name = "Jay" })
	if spar then
		Builder.SetHeadgear(spar, Color3.fromRGB(230, 200, 30), true)
	end
	add("sparring partner (headgear)", spar)
	for _, kind in ipairs({ "referee", "cornerman" }) do
		local a2, b2, g2, o2 = Officials.Look(31, kind, { venue = "ClubArena", team = { 230, 200, 30 } })
		local off = Builder.CreateNPC(a2, b2, g2, kind, o2)
		if off then
			off.Parent = E.workspace
		end
		add(kind, off)
	end
	add("fight-night opponent", (npc(5150, { hands = "gloves", mouthguard = true, detail = "full", fightNight = true, name = "Opp", nick = "The Opp" })))
	local char = newRig(Vector3.new(1, 1, 1))
	char.Parent = E.workspace
	Builder.Apply(char, Looks.Defaults(1), buildOf(35), { gloves = "Starter" }, { hands = "gloves", name = "Player1" })
	add("player", char)
	for _, k in ipairs(kinds) do
		local res = Kit.FitAudit(k.model)
		check(string.format("%s fit: %s: %d pieces, all welded and on their parts", gearMode, k.name, res.pieces), #res.problems == 0 and res.pieces > 5,
			res.pieces .. " pieces; " .. table.concat(res.problems, " | ", 1, math.min(#res.problems, 4)))
		check(string.format("%s: %s: no box", gearMode, k.name), boxes(k.model) == 0)
	end
	if gearMode == "mesh" and spar then
		-- the engine rescales the head after the build (its deferred scaling pass): the audit sees the headgear fitted to
		-- another head, and the late re-fit (Builder.OnPlaced -> RefitHeadgear) puts it right
		local head = spar:FindFirstChild("Head")
		head.Size = head.Size * 1.25
		local bad = Kit.FitAudit(spar)
		check("fit: headgear fitted to the old head size is caught", #bad.problems >= 1, #bad.problems)
		Builder.RefitHeadgear(spar)
		local good = Kit.FitAudit(spar)
		check("fit: after the re-fit the headgear sits on the rescaled head", #good.problems == 0, table.concat(good.problems, " | "))
		-- the audit catches a pad whose weld was computed for another head
		local hg = folder(spar, "Headgear")
		local pad = hg and hg:FindFirstChild("HGShell")
		local w = pad and pad:FindFirstChildOfClass("Weld")
		if w then
			w.C0 = w.C0 * CFrame.new(0, 0.6, 0.5)
			pad.CFrame = w.Part0.CFrame * w.C0 * CFrame.new(0, 0, 0)
			pad.CFrame = pad.CFrame * CFrame.new(0, 2, 0)
			local res = Kit.FitAudit(spar)
			check("fit: a headgear pad off its weld / off the head is caught", #res.problems >= 1, #res.problems)
		else
			check("fit: the sparring headgear has its shell pad", false)
		end
	end
end

print(string.format("test_meshfallback: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
