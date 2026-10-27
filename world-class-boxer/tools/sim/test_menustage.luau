--!nocheck
-- tools/sim/test_menustage.luau: the main menu's boxer (MenuStage) on a fake R15 character (fakeengine)
--   * Ready: a character mid-swap (a body part missing) is not staged
--   * Place: the copy carries the server's non-Archivable parts (tier MeshParts, gear) and the character's own
--     Archivable flags are put back; the copy stands on the set, tagged Preview, client hair folder dropped,
--     LocalTransparencyModifier reset; a part no joint ties to the root is held at its place by a weld
--   * Place again (a re-stage) replaces the previous copy
--   * AnatomyClient in Config.BaldMode: no hair generator, no EditableMesh (not even the probe), a quiet status
--   * the set's size per Graphics level (parts, lights, shadow casters) and its per-frame Step / Shot cost
--   * BuilderTiers.Preload is paced and loads only the current frame's family (the default at start, another frame's
--     the first time a boxer is built on it), never all 5 frames x 5 tiers x 14 meshes up front
--   * the Creator's live preview (guisim, the real client code): the window is built once (a step change keeps its
--     chrome), a slider change and a swatch pick create no GUI instances, a DRAG of a whole-body slider (height)
--     sends one full preview when it is let go (not two a second), a head slider's drag sends head-only previews
--     at the client's cap, a colour swatch sends one preview
--   * the Creator's steps: the one on screen is built in the open's frame, the others behind the window (FrameBudget,
--     a few ms a frame: no slice far past the median), then a step change rebuilds nothing (no instance, no preview
--     but for the hands); a burst of [+] presses is one (debounced) full preview; a body-type pick updates the step
--     in place; a face drag is not a preview per move and starts no page rebuild
--   * a colour swatch (gear or skin tone) sends a colour-only preview (only.Colors), quick picks are coalesced; the
--     server's colour path (Builder.Cosmetics only.Colors) runs no tier swap, muscles or hair, rebuilds only the layers
--     a full build would (under 80 instances) and ends where a full build would (a full Cosmetics after it: nothing)
--   * behind the menu stage (the LocalPlayer's MenuStage flag) WorldLOD switches the world's lights off, back on after
--   * MainMenu re-stages the boxer once after a burst of character changes (one pending re-stage, not a timer per
--     changed descendant); the home layer is built once and toggled under the other screens; the fighter card's
--     posed master is cached across career visits; closing parks the set and reopening reuses it and the boxer's copy
--   lune run tools/sim/test_menustage.luau
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local process = require("@lune/process")
local fs = require("@lune/fs")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

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
local H = Host.new({ globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
local MenuStage = H.require("Client/MenuStage")
local CS = E.CollectionService

local R15 = {
	{ "LowerTorso", "HumanoidRootPart", "Root", Vector3.new(0, 0, 0) },
	{ "UpperTorso", "LowerTorso", "Waist", Vector3.new(0, 1, 0) },
	{ "Head", "UpperTorso", "Neck", Vector3.new(0, 2.5, 0) },
	{ "LeftUpperArm", "UpperTorso", "LeftShoulder", Vector3.new(-1.5, 1.4, 0) },
	{ "RightUpperArm", "UpperTorso", "RightShoulder", Vector3.new(1.5, 1.4, 0) },
	{ "LeftLowerArm", "LeftUpperArm", "LeftElbow", Vector3.new(-1.5, 0.4, 0) },
	{ "RightLowerArm", "RightUpperArm", "RightElbow", Vector3.new(1.5, 0.4, 0) },
	{ "LeftUpperLeg", "LowerTorso", "LeftHip", Vector3.new(-0.5, -1.2, 0) },
	{ "RightUpperLeg", "LowerTorso", "RightHip", Vector3.new(0.5, -1.2, 0) },
}

-- a character at (20, 3, 40) in the world: root + joints, tier parts not Archivable (as server-made parts may be)
local function character(opts)
	opts = opts or {}
	local char = E.new("Model")
	char.Name = "Boxer"
	char.Archivable = false -- (a player's character)
	local hum = E.new("Humanoid", char)
	hum.Name = "Humanoid"
	hum.HipHeight = 2
	local base = CFrame.new(20, 3, 40)
	local root = E.new("Part", char)
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = base
	root.Transparency = 1
	local parts = { HumanoidRootPart = root }
	for _, r in ipairs(R15) do
		if not (opts.missing == r[1]) then
			local p = E.new("MeshPart", char)
			p.Name = r[1]
			p.CFrame = base * CFrame.new(r[4])
			p.LocalTransparencyModifier = 1 -- (e.g. the camera fading the live character)
			p:SetAttribute("BodyTier", 3)
			if r[1] ~= "Head" then
				p.Archivable = false -- the tier MeshParts (the head stays as made)
			end
			parts[r[1]] = p
			local parent = parts[r[2]]
			if parent and not (opts.unjointed == r[1]) then
				local m = E.new("Motor6D", p)
				m.Name = r[3]
				m.Part0, m.Part1 = parent, p
			end
		end
	end
	-- gear: a modelled glove welded to the forearm, not Archivable either
	local look = E.new("Folder", char)
	look.Name = "BoxerLook"
	local glove = E.new("MeshPart", look)
	glove.Name = "GloveR"
	glove.Archivable = false
	glove:SetAttribute("GearPiece", "GloveR")
	glove.CFrame = base * CFrame.new(1.5, -0.6, 0)
	if parts.RightLowerArm then
		local w = E.new("Weld", glove)
		w.Name = "GearWeld"
		w.Part0, w.Part1 = parts.RightLowerArm, glove
	end
	-- the client's hair pieces (AnatomyClient) on the live character
	local anat = E.new("Folder", char)
	anat.Name = "Anatomy"
	E.new("MeshPart", anat).Name = "AnatomyHairCap"
	char.Parent = E.workspace
	CS:AddTag(char, "Anatomy")
	return char, parts
end

local st = MenuStage.Build("Low")
check("Build: a stage folder in the workspace", st.folder ~= nil and st.folder.Parent == E.workspace)

do
	local char = character({ missing = "UpperTorso" })
	local ok, why = MenuStage.Ready(char)
	check("Ready: a part mid-swap is not ready", ok == false and type(why) == "string" and why:find("UpperTorso") ~= nil, why)
	local clone, why2 = MenuStage.Place(st, char)
	check("Place: nothing staged, a reason", clone == nil and why2 ~= nil, why2)
	char:Destroy()
	check("Ready: no character", MenuStage.Ready(nil) == false)
end

local char, parts = character()
local clone, why = MenuStage.Place(st, char)
check("Place: staged", clone ~= nil, why)
if clone then
	check("clone in the set", clone.Parent == st.folder and clone.Name == "MenuBoxer")
	for _, r in ipairs(R15) do
		check("non-Archivable tier part copied: " .. r[1], clone:FindFirstChild(r[1]) ~= nil)
	end
	local gl = clone:FindFirstChild("BoxerLook") and clone.BoxerLook:FindFirstChild("GloveR")
	check("non-Archivable gear copied", gl ~= nil)
	check("gear weld points at the copy", gl and gl.GearWeld and gl.GearWeld.Part0 == clone.RightLowerArm)
	check("live character's flags put back", char.Archivable == false and parts.LeftUpperArm.Archivable == false and parts.Head.Archivable == nil)
	check("client hair folder dropped", clone:FindFirstChild("Anatomy") == nil)
	check("tagged Preview only", CS:HasTag(clone, "Preview") and not CS:HasTag(clone, "Anatomy"))
	check("LocalTransparencyModifier reset", clone.UpperTorso.LocalTransparencyModifier == 0)
	local root = clone.HumanoidRootPart
	check("root anchored on the mark", root.Anchored == true and (root.Position - (MenuStage.Origin + Vector3.new(0, 3, 0))).Magnitude < 1e-3, root.Position)
	check("every limb joined: no hold welds", (st.loose or 0) == 0, st.loose)
	check("st.clone / st.root", st.clone == clone and st.root == root)
end

-- a re-stage while a part has no joint (copied mid-swap): the loose part is held next to the root
do
	local char2 = character({ unjointed = "LeftUpperLeg" })
	local old = st.clone
	local c2 = MenuStage.Place(st, char2)
	check("re-stage: the old copy is gone", old ~= nil and old.Parent == nil)
	check("re-stage: staged", c2 ~= nil and st.clone == c2)
	if c2 then
		check("loose part held by a weld", st.loose == 1 and c2.LeftUpperLeg:FindFirstChild("MenuHold") ~= nil, st.loose)
		local rel = c2.HumanoidRootPart.CFrame:ToObjectSpace(c2.LeftUpperLeg.CFrame).Position
		check("loose part kept its offset from the root", (rel - Vector3.new(-0.5, -1.2, 0)).Magnitude < 1e-3, rel)
	end
end

MenuStage.Destroy(st)
check("Destroy: set gone", st.folder == nil and st.clone == nil)

------------------------------------------------------------------------
-- AnatomyClient with every boxer bald (Config.BaldMode): idle, nothing Editable is made
------------------------------------------------------------------------
do
	local E2 = FE.new()
	local H2 = Host.new({ globals = { Instance = E2.Instance, workspace = E2.workspace, Workspace = E2.workspace } })
	E2.install(H2)
	local made = 0
	H2.Service("AssetService")._props = {
		CreateEditableMesh = function()
			made += 1
			return nil
		end,
		CreateEditableImage = function()
			made += 1
			return nil
		end,
	}
	for _, name in ipairs({ "Perf", "State", "AnatomyStatus" }) do
		local n = H2.client._kids[name]
		if n then
			H2.client._kids[name] = nil
			table.remove(H2.client._order, table.find(H2.client._order, n))
		end
	end
	H2.require("Config").BaldMode = true
	local LookData = H2.require("LookData")
	local AC = H2.require("Client/AnatomyClient")
	AC.Settings.profileWait = 0
	AC.Start()
	E2.step(5)
	for i, tag in ipairs({ "Preview", "Ambient" }) do
		local m = E2.new("Model")
		m.Name = "Bald" .. i
		local hrp = E2.new("Part", m)
		hrp.Name = "HumanoidRootPart"
		hrp.CFrame = CFrame.new(0, 3, -6 - i * 2)
		local head = E2.new("Part", m)
		head.Name = "Head"
		head.CFrame = CFrame.new(0, 5.5, -6 - i * 2)
		m.Parent = E2.workspace
		E2.CollectionService:AddTag(m, tag)
		LookData.Publish(m, H2.Look({ g = 1, hair = { style = "Afro", type = "Kinky", color = 1 } }))
	end
	E2.step(120)
	local state, reason, kind = AC.MeshState()
	check("BaldMode: status off as a setting (no player notice)", state == "off" and kind == "setting", tostring(state) .. " " .. tostring(reason) .. " " .. tostring(kind))
	check("BaldMode: no EditableMesh / EditableImage made", made == 0, made)
	for _, m in ipairs(E2.workspace:GetChildren()) do
		if m:IsA("Model") then
			check("BaldMode: no hair pieces on " .. m.Name, AC.GetPieces(m, "Hair") == nil)
		end
	end
	AC.Stop()
end

------------------------------------------------------------------------
-- The set's size per level, and the per-frame cost of Step / Shot
------------------------------------------------------------------------
do
	local E3 = FE.new()
	local madeN = 0
	local Inst = { new = function(cls, parent)
		madeN += 1
		return E3.Instance.new(cls, parent)
	end }
	local H3 = Host.new({ globals = { Instance = Inst, workspace = E3.workspace, Workspace = E3.workspace } })
	E3.install(H3)
	local MS = H3.require("Client/MenuStage")
	local sizes = {}
	for _, lvl in ipairs({ "Low", "Medium", "High" }) do
		madeN = 0
		local t0 = os.clock()
		local s = MS.Build(lvl)
		local built = os.clock() - t0
		local parts, lights, casters = 0, 0, 0
		for _, d in ipairs(s.folder:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			elseif d.ClassName == "SpotLight" or d.ClassName == "PointLight" or d.ClassName == "SurfaceLight" then
				lights += 1
				if d.Shadows then
					casters += 1
				end
			end
		end
		sizes[lvl] = { inst = madeN, parts = parts, lights = lights, casters = casters }
		local t1 = os.clock()
		for i = 1, 600 do
			MS.Step(s, i / 60)
			MS.Shot(s, "home", i / 60, 1)
		end
		local per = (os.clock() - t1) / 600
		print(string.format("  MenuStage.Build(%s): %d instances, %d parts, %d lights (%d shadow casters), built in %.1f ms; Step+Shot %.3f ms a frame",
			lvl, madeN, parts, lights, casters, built * 1000, per * 1000))
		check("Build(" .. lvl .. "): under 1200 instances", madeN < 1200, madeN)
		check("Step+Shot(" .. lvl .. "): under 1 ms a frame in the sim", per < 0.001, per)
		MS.Destroy(s)
	end
	check("shadow casters follow the level: Low none, Medium two, High four", sizes.Low.casters == 0 and sizes.Medium.casters == 2 and sizes.High.casters == 4,
		string.format("%d / %d / %d", sizes.Low.casters, sizes.Medium.casters, sizes.High.casters))
end

------------------------------------------------------------------------
-- Behind the set: the world's lights (WorldLOD) switch off while a set is up (the MenuStage flag) and back on after
------------------------------------------------------------------------
do
	local E4 = FE.new()
	local function fakeTypeof(v)
		if type(v) == "table" and rawget(v, "_class") ~= nil then
			return "Instance"
		end
		return typeof(v)
	end
	local H4 = Host.new({ globals = { Instance = E4.Instance, workspace = E4.workspace, Workspace = E4.workspace, typeof = fakeTypeof } })
	E4.install(H4)
	local hb = FE.Signal()
	H4.Service("RunService")._props.Heartbeat = hb
	local me = E4.new("Folder")
	me.Name = "LocalPlayer"
	H4.Service("Players")._props.LocalPlayer = me
	local cam = E4.new("Camera", E4.workspace)
	cam.CFrame = CFrame.new(0, 6, 30)
	E4.workspace.CurrentCamera = cam
	local MS4 = H4.require("Client/MenuStage")
	local WL = H4.require("Client/WorldLOD")
	-- the gym's lights: a lamp over the ring, a fill, an accent (all on, all in range of the gym camera)
	local gym = E4.new("Folder")
	gym.Name = "Gym"
	local lightsList = {}
	for i, r in ipairs({ 40, 30, 12 }) do
		local p = E4.new("Part", gym)
		p.Name = "Lamp" .. i
		p.Position = Vector3.new(i * 4, 12, 0)
		local l = E4.new("PointLight", p)
		l.Range = r
		l.Enabled = true
		local isA = l.IsA
		rawset(l, "IsA", function(o, cls) -- (fakeengine has no Light base class)
			return cls == "Light" or isA(o, cls)
		end)
		table.insert(lightsList, l)
	end
	gym.Parent = E4.workspace
	WL.Start()
	WL.Watch(gym, { keep = true })
	local function frames(n)
		for _ = 1, n do
			hb:Fire(1 / 60)
		end
	end
	local function onCount()
		local n = 0
		for _, l in ipairs(lightsList) do
			if l.Enabled then
				n += 1
			end
		end
		return n
	end
	frames(30)
	check("world lights: on at the gym", onCount() == 3, onCount())
	local st = MS4.Build("High")
	cam.CFrame = CFrame.new(0, 1404, 10) -- the menu's lens, right above the town (inside High's 2000-stud light reach)
	frames(30)
	check("behind the menu stage: the world's lights are off (MenuStage flag " .. tostring(me:GetAttribute("MenuStage")) .. ")", onCount() == 0 and me:GetAttribute("MenuStage") == true, onCount())
	MS4.Park(st)
	cam.CFrame = CFrame.new(0, 6, 30)
	frames(30)
	check("menu closed (set parked): the flag is gone and the lights are back on", onCount() == 3 and me:GetAttribute("MenuStage") == nil, onCount())
	MS4.Unpark(st)
	check("Unpark: the flag again", me:GetAttribute("MenuStage") == true)
	MS4.Destroy(st)
	check("Destroy: the flag gone", me:GetAttribute("MenuStage") == nil)
end

------------------------------------------------------------------------
-- BuilderTiers.Preload: paced, only the current frame's family (the default family at start, another frame's the
-- first time a boxer is built on it), never all the families up front
------------------------------------------------------------------------
do
	local BuilderTiers = H.require("BuilderTiers")
	local BodyTiers = H.require("BodyTiers")
	local keys = {}
	local function keyOf(e, tier, name)
		return tier .. ":" .. name .. ":" .. e.id
	end
	local defN, allOther = 0, 0
	for _, lite in ipairs({ false, true }) do
		for tier = 1, BodyTiers.TIERS do
			for _, name in ipairs(BodyTiers.PARTS) do
				local e = BodyTiers.PartEntry(tier, name, nil, lite)
				if e and not keys[keyOf(e, tier, name)] then
					keys[keyOf(e, tier, name)] = true
					defN += 1
				end
			end
		end
	end
	-- the other frames' families, and one of them (the frame a boxer is built on below)
	local otherFrame, frameN = nil, 0
	for _, frame in ipairs(BodyTiers.Frames()) do
		if frame ~= BodyTiers.DEFAULT_FRAME then
			local n = 0
			for tier = 1, BodyTiers.TIERS do
				for _, name in ipairs(BodyTiers.PARTS) do
					local e = BodyTiers.PartEntry(tier, name, nil, false, frame)
					if e and not keys[keyOf(e, tier, name)] then
						keys[keyOf(e, tier, name)] = true
						n += 1
					end
				end
			end
			allOther += n
			if n > 0 and not otherFrame then
				otherFrame, frameN = frame, n
			end
		end
	end
	local AS = { calls = 0, at = {} }
	function AS.CreateMeshPartAsync(_, _content)
		AS.calls += 1
		AS.at[AS.calls] = os.clock()
		return E.new("MeshPart")
	end
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = AS, Content = { fromUri = function(u)
		return u
	end } }
	local t0 = os.clock()
	BuilderTiers.Preload({ gap = 0.01 })
	check("Preload: returns at once (one load in flight at most)", AS.calls <= 1, AS.calls)
	task.wait(0.12)
	check("Preload: paced, not all at once (" .. AS.calls .. " of " .. defN .. " default loads after 0.12 s)", AS.calls >= 2 and AS.calls < defN, AS.calls)
	local tDef = os.clock()
	while AS.calls < defN and os.clock() - tDef < 20 do
		task.wait(0.02)
	end
	check("Preload: the default family (full + lite) loads: " .. defN .. " loads", AS.calls == defN, AS.calls)
	local startN = AS.calls
	task.wait(0.6)
	check("Preload: no other frame's family is loaded up front (was " .. allOther .. " more loads)", AS.calls == defN, AS.calls - defN)
	-- a boxer built on another frame: that frame's family loads behind him, paced, and only that one
	check("a second frame to build on", otherFrame ~= nil)
	local m = E.new("Model")
	E.new("Humanoid", m)
	local before = AS.calls
	BuilderTiers.Apply(m, { frame = otherFrame }, Vector3.new(1, 1, 1), false)
	task.wait(0.05)
	check("Apply on a new frame: its family preloads in the background (paced)", AS.calls > before and AS.calls < before + frameN, AS.calls - before)
	local tF = os.clock()
	while AS.calls < before + frameN and os.clock() - tF < 20 do
		task.wait(0.02)
	end
	task.wait(0.2)
	check("Apply on a new frame: exactly that frame's family (" .. frameN .. " loads), no other", AS.calls == before + frameN, AS.calls - before)
	before = AS.calls
	BuilderTiers.Apply(m, { frame = otherFrame }, Vector3.new(1, 1, 1), false)
	check("PreloadFrame once per frame (a second boxer on it queues nothing)", BuilderTiers.PreloadFrame(otherFrame) == false and AS.calls == before, AS.calls - before)
	print(string.format("  Preload: %d loads at start (the default family + lite set), %d for frame %s when first used; the old preload queued %d (every family) at start",
		startN, frameN, tostring(otherFrame), defN + allOther))
	BuilderTiers.Reset()
	BuilderTiers.Services = {}
end

------------------------------------------------------------------------
-- The server's colour-only preview (Builder.Cosmetics with only.Colors): no full Cosmetics on a colour change
------------------------------------------------------------------------
do
	local ES = FE.new()
	local HS = Host.new({ server = true, globals = { Instance = ES.Instance, workspace = ES.workspace, Workspace = ES.workspace, warn = function() end } })
	ES.install(HS)
	local BodyTiers = HS.require("BodyTiers")
	local BuilderTiers = HS.require("BuilderTiers")
	local BuilderGear = HS.require("BuilderGear")
	local Builder = HS.require("Builder")
	local Body = HS.require("BuilderBody")
	local Hair = HS.require("BuilderHair")
	local Looks = HS.require("Looks")
	local Vector3s, Color3s = roblox.Vector3, roblox.Color3
	-- the fake R15 rig test_npcbuild builds on (OriginalSize / OriginalPosition, motors, ReplaceBodyPartR15)
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
		return Vector3s.new(t[1], t[2], t[3])
	end
	local function newRig(scale, parent)
		local model = ES.new("Model")
		model.Name = "Boxer"
		local hrp = ES.new("Part", model)
		hrp.Name = "HumanoidRootPart"
		hrp.Size = Vector3s.new(2, 2, 1) * scale
		local ra = ES.new("Attachment", hrp)
		ra.Name = "RootRigAttachment"
		local function addPart(name, size, orig, atts)
			local p = ES.new("MeshPart", model)
			p.Name = name
			p.Size = size
			p.Color = Color3s.new(1, 1, 1)
			local o = ES.new("Vector3Value", p)
			o.Name = "OriginalSize"
			o.Value = orig
			for an, pos in pairs(atts) do
				local a = ES.new("Attachment", p)
				a.Name = an
				a.Position = pos.cur
				local op = ES.new("Vector3Value", a)
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
		addPart("Head", Vector3s.new(0.927, 0.927, 0.927), Vector3s.new(1.2, 1.2, 1.2), { NeckRigAttachment = { cur = Vector3s.new(0, -0.46, 0), orig = Vector3s.new(0, -0.6, 0) } })
		for jn, pp in pairs(JOINTS) do
			local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
			local m = ES.new("Motor6D", p1)
			m.Name = jn
			m.Part0, m.Part1 = p0, p1
			m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
			m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
			m.Transform = CFrame.new()
		end
		local hum = ES.new("Humanoid", model)
		hum.HipHeight = 2 * scale.Y
		hum.ReplaceBodyPartR15 = function(_, enum, part)
			local name = enum.Name
			local old = model:FindFirstChild(name)
			if name ~= "Head" then
				local o = part:FindFirstChild("OriginalSize")
				if o then
					part.Size = o.Value * scale
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
		model.Parent = parent
		return model
	end
	local function fakeAssets()
		local AS = {}
		function AS.CreateMeshPartAsync(_, content)
			local mp = ES.new("MeshPart")
			mp.MeshId = "rbxassetid://" .. tostring(tonumber(tostring(content):match("(%d+)%s*$")))
			return mp
		end
		return AS
	end
	local Content = { fromUri = function(u)
		return u
	end }
	BodyTiers.SetData(BodyTiers.Data())
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
	BuilderGear.SetData(BuilderGear.Data())
	BuilderGear.Reset()
	BuilderGear.Services = { AssetService = fakeAssets(), Content = Content }
	local stageF = ES.new("Folder", ES.workspace)
	stageF.Name = "BoxerStaging"
	Builder.Services.Stage = stageF
	local build = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		build[id] = 70
	end
	local app = Looks.Random(4242, 1, { age = 26, class = 5 })
	local gear = { gloves = "Competition", glovesCond = 70, wraps = "OldWraps", wrapsCond = 80 }
	-- what each Cosmetics run creates and which layers it runs (the spies: the tier swap, the muscles, the hair)
	local made, counting = 0, false
	local baseNew = ES.Instance.new
	ES.Instance.new = function(cls, parent)
		if counting then
			made += 1
		end
		return baseNew(cls, parent)
	end
	local calls = {}
	local function spy(tbl, key, label)
		local f = tbl[key]
		tbl[key] = function(...)
			calls[label] = (calls[label] or 0) + 1
			return f(...)
		end
	end
	spy(BuilderTiers, "Apply", "Tiers")
	spy(Body, "Muscles", "Muscles")
	spy(Hair, "Build", "Hair")
	local sc = Builder.Scales(app, build, {})
	local pm = newRig(Vector3s.new(sc.width, sc.height, sc.depth), ES.workspace)
	local FULL = { hands = "wraps", name = "", nick = "", waistText = "", detail = "full" }
	local COLOR = table.clone(FULL)
	COLOR.only = { Colors = true }
	check("server: the first full build", (pcall(Builder.Cosmetics, pm, app, build, gear, FULL)))
	local function folders()
		local out = {}
		for _, f in ipairs(pm.BoxerLook:GetChildren()) do
			out[f.Name] = f
		end
		return out
	end
	local function run(opts)
		local before = folders()
		table.clear(calls)
		made, counting = 0, true
		local t0 = os.clock()
		local ok = pcall(Builder.Cosmetics, pm, app, build, gear, opts)
		counting = false
		local rebuilt = {}
		for n, f in pairs(folders()) do
			if before[n] ~= f then
				table.insert(rebuilt, n)
			end
		end
		table.sort(rebuilt)
		return ok, made, table.concat(rebuilt, ","), os.clock() - t0, table.clone(calls)
	end
	local _, idleN, _, _, fullCalls = run(FULL)
	check("server spies: a full Cosmetics runs the tier swap, the muscles and the hair", (fullCalls.Tiers or 0) > 0 and (fullCalls.Muscles or 0) > 0 and (fullCalls.Hair or 0) > 0)
	local seq = 0
	local function c3()
		seq += 1
		return { (seq * 53) % 256, (seq * 97) % 256, (seq * 31) % 256 }
	end
	local KEYS = {
		{ "trunks", function(a)
			local c = c3()
			a.attire.trunks, a.attire.robe = c, c
		end },
		{ "gloves", function(a)
			a.gloves.color = c3()
		end },
		{ "skin", function(a)
			a.skin = (a.skin % #Looks.SkinTones) + 1
		end },
	}
	for _, k in ipairs({ "headgear", "trim", "socks", "shoes", "laces", "wraps", "mouthguard", "robeTrim" }) do
		table.insert(KEYS, { k, function(a)
			a.attire[k] = c3()
		end })
	end
	local maxColor, maxFull, tColor, tFull = 0, 0, 0, 0
	for _, kv in ipairs(KEYS) do
		local function change()
			app = table.clone(app)
			app.attire, app.gloves = table.clone(app.attire), table.clone(app.gloves)
			kv[2](app)
		end
		change()
		local okF, nF, rF, dtF = run(FULL)
		change()
		local okC, nC, rC, dtC, cC = run(COLOR)
		maxColor, maxFull = math.max(maxColor, nC), math.max(maxFull, nF)
		tColor, tFull = tColor + dtC, tFull + dtF
		check("colour " .. kv[1] .. ": the colour path runs", okF and okC)
		check("colour " .. kv[1] .. ": no full Cosmetics (no tier swap, no muscles, no hair)", (cC.Tiers or 0) == 0 and (cC.Muscles or 0) == 0 and (cC.Hair or 0) == 0,
			string.format("tiers %d muscles %d hair %d", cC.Tiers or 0, cC.Muscles or 0, cC.Hair or 0))
		check("colour " .. kv[1] .. ": rebuilds only the layers a full build would (" .. rC .. ")", rC == rF, rC .. " vs " .. rF)
		check("colour " .. kv[1] .. ": under 80 instances (" .. nC .. ")", nC < 80, nC)
		local _, nAfter, rAfter = run(FULL)
		check("colour " .. kv[1] .. ": the result is the full build's (a full Cosmetics after it rebuilds nothing)", rAfter == "" and nAfter <= idleN, rAfter .. " / " .. nAfter)
	end
	print(string.format("  colour previews (%d keys): at most %d instances (full path: %d), %.1f vs %.1f ms in all; no tier swap / muscles / hair",
		#KEYS, maxColor, maxFull, tColor * 1000, tFull * 1000))
	BuilderTiers.Reset()
	BuilderTiers.Services = {}
end

------------------------------------------------------------------------
-- The Creator's live preview (guisim: the real client, a fake server)
------------------------------------------------------------------------
do
	local GS = require("./guisim")
	local S = GS.new("desktop")
	-- real input signals (the sim's defaults are inert stubs): a slider drag is InputBegan on its hit area, then
	-- UserInputService.InputChanged moves and InputEnded
	local uis = S.host.Service("UserInputService")._props
	uis.InputBegan, uis.InputChanged, uis.InputEnded = FE.Signal(), FE.Signal(), FE.Signal()
	local made = 0
	local baseNew = S.Instance.new
	S.Instance.new = function(cls, parent)
		made += 1
		return baseNew(cls, parent)
	end
	local reqs = {}
	S.onInvokeServer = function(_, action, ...)
		table.insert(reqs, { action = action, args = table.pack(...) })
		if action == "GetProfile" then
			return { created = false }
		end
		return { ok = true }
	end
	S.loadScript("client/ClientMain.client.lua")
	S.settle(0.6)
	local Creator = S.require("Client/Creator")
	local UI = S.require("UI")
	local Enum = roblox.Enum
	local Vector2 = roblox.Vector2
	-- PreviewLook requests: full, head-only (Face / Hair / Beard), colour-only (Colors and nothing else)
	local function previews()
		local full, head, colors = 0, 0, 0
		for _, r in ipairs(reqs) do
			if r.action == "PreviewLook" then
				local popts = r.args[3]
				local only = type(popts) == "table" and type(popts.only) == "table" and popts.only or nil
				if not only then
					full += 1
				elseif only.Colors and not (only.Face or only.Hair or only.Beard) then
					colors += 1
				else
					head += 1
				end
			end
		end
		return full, head, colors
	end
	-- on screen: it and every GUI ancestor visible (the Creator keeps its other steps' pages hidden under the window)
	local function shown(d)
		local o = d
		while o and o ~= S.playerGui do
			if o.Visible == false then
				return false
			end
			o = o.Parent
		end
		return o == S.playerGui
	end
	local function named(name)
		for _, d in ipairs(S.playerGui:GetDescendants()) do
			if d.Name == name and shown(d) then
				return d
			end
		end
		return nil
	end
	local function press(name)
		local b = named(name)
		if b then
			S.signal(b, "MouseButton1Click"):Fire()
		end
		return b ~= nil
	end
	local function sliders()
		local out = {}
		for _, d in ipairs(S.playerGui:GetDescendants()) do
			if d:GetAttribute("Slider") and d:FindFirstChild("Label") and shown(d) then
				out[d.Label.Text] = d
				table.insert(out, d)
			end
		end
		return out
	end
	-- a pointer drag across a slider's track: n moves over `seconds`, then let go
	local function drag(f, n, seconds)
		local hit, track = f:FindFirstChild("Hit"), f:FindFirstChild("Track")
		local x0, w, y = track.AbsolutePosition.X, track.AbsoluteSize.X, track.AbsolutePosition.Y + 4
		local MB1, MOVE = Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseMovement
		local press0 = { UserInputType = MB1, Position = Vector3.new(x0 + w * 0.2, y, 0) }
		S.signal(hit, "InputBegan"):Fire(press0)
		for i = 1, n do
			uis.InputChanged:Fire({ UserInputType = MOVE, Position = Vector3.new(x0 + w * (0.2 + 0.6 * i / n), y, 0) }, false)
			S.settle(seconds / n)
		end
		uis.InputEnded:Fire(press0, false)
	end
	if Creator.IsOpen() then
		Creator.Close()
		S.settle(0.2)
	end
	-- the steps not on screen are built behind the window (FrameBudget jobs, a few ms a frame): settled = none left
	local FB = S.require("Client/FrameBudget")
	local function idle(cap)
		local t = 0
		while FB.Busy() and t < (cap or 20) do
			S.settle(0.1)
			t += 0.1
		end
		return not FB.Busy()
	end
	local function pages()
		local n = 0
		for _, d in ipairs(S.playerGui:GetDescendants()) do
			if d.Name == "Page" and d.Parent and d.Parent:IsA("ScrollingFrame") then
				n += 1
			end
		end
		return n
	end
	idle()
	FB.Stats.slices, FB.Stats.over = 0, 0
	table.clear(FB.Stats.recent)
	made = 0
	Creator.Open()
	local built = made
	check("Creator.Open: the window and its first step built at once (under 900 instances)", built > 50 and built < 900, built)
	S.settle(0.8)
	check("Creator.Open: the other steps are built behind the window, not in the open's frame", made > built and FB.Busy() or pages() == 7, made .. " / " .. pages())
	check("... and they all get built (7 pages under the list, one on show)", idle() and pages() == 7, pages())
	-- spread over frames (at least 20 slices), each about the budget: no slice past twice the median one (the sim's
	-- clock is the wall's, so the median stands in for this machine's speed: a step too big for a frame is the outlier)
	local slices = FB.Stats.slices
	local list = table.clone(FB.Stats.recent)
	table.sort(list)
	local median = list[math.max(1, math.floor(#list / 2))] or 0
	local long = 0
	for _, ms in ipairs(list) do
		if ms > math.max(2.5 * median, FB.BUDGET * 2000) then
			long += 1
		end
	end
	print(string.format("  Creator: the steps behind the window in %d FrameBudget slices (median %.2f ms, %d past 2.5x)", slices, median, long))
	check(string.format("... a few ms a frame: %d slices (median %.1f ms), under 5%% of them past 2.5x the median", slices, median), slices >= 20 and long <= math.max(1, #list * 0.05), long .. "/" .. #list)
	local chrome = { named("Tools"), named("StepBar"), named("Nav"), named("FighterPlate"), named("Turntable") }
	check("Creator.Open: the chrome is there", chrome[1] and chrome[2] and chrome[3] and chrome[4] and chrome[5])
	-- every step change once the pages are built: a kept page is shown, nothing is rebuilt (no instance made) and no
	-- preview is sent but for the hands (gloves on the Gear step)
	local tabMade, tabFull = 0, 0
	for i = 1, 7 do
		made = 0
		table.clear(reqs)
		press("Step" .. i)
		S.settle(0.35)
		tabMade += made
		tabFull += (previews())
	end
	press("Step1")
	S.settle(0.35)
	check("step changes (all 7, built): no page rebuilt, no GUI instance made", tabMade == 0, tabMade)
	check("step changes: a full preview only for the hands (into and out of Gear)", tabFull <= 2, tabFull)
	-- the Body step: a whole-body slider
	made = 0
	table.clear(reqs)
	check("Step5 (Body)", press("Step5"))
	S.settle(0.4)
	local tab = made
	local same = named("Tools") == chrome[1] and named("StepBar") == chrome[2] and named("Nav") == chrome[3] and named("FighterPlate") == chrome[4] and named("Turntable") == chrome[5]
	check("GUI built once: a step change keeps the window's chrome (only the page body is rebuilt)", same)
	local height = sliders()["Height"]
	check("the Height slider is on the Body step", height ~= nil)
	made = 0
	table.clear(reqs)
	UI.Nudge(height, 1)
	S.settle(0.4)
	local f1, h1 = previews()
	check("a slider step creates no GUI instances (" .. made .. ")", made <= 2, made)
	check("a slider step previews once (full: the body changed)", f1 == 1 and h1 == 0, f1 .. "/" .. h1)
	made = 0
	table.clear(reqs)
	drag(height, 12, 0.6)
	local fMid = previews()
	S.settle(0.4)
	local f2, h2 = previews()
	check("a Height DRAG previews once, when it is let go (was: a full rebuild every 0.25 s of the drag)", fMid == 0 and f2 == 1 and h2 == 0, string.format("during %d, after %d/%d", fMid, f2, h2))
	check("a Height drag creates no GUI instances", made == 0, made)
	check("the drag moved the value (the value text updates live)", (height:GetAttribute("Value") or 0) > 60, height:GetAttribute("Value"))
	-- a burst of [+] presses (four in 0.1 s): debounced to one full rebuild, not one per press
	table.clear(reqs)
	for _ = 1, 4 do
		UI.Nudge(height, 1)
		S.settle(0.025)
	end
	S.settle(0.6)
	local fb = previews()
	check("four quick Height steps: one full preview (debounced)", fb == 1, fb)
	-- a body type pick: the outline and the traits panel move in place (no rebuild of the step), one full preview
	made = 0
	table.clear(reqs)
	check("a body type pick", press("Preset_Muscular"))
	S.settle(0.6)
	local fbt = previews()
	check("a body type pick updates the step in place (the traits panel only: under 120 instances)", made < 120, made)
	check("a body type pick: one full preview", fbt == 1, fbt)
	idle()
	-- the Face step: a head slider stays live (a partial rebuild, at the client's cap)
	check("Step2 (Face)", press("Step2"))
	S.settle(0.4)
	local list = sliders()
	local faceSlider
	for _, f in ipairs(list) do
		if f.Label.Text ~= "Age" then
			faceSlider = faceSlider or f
		end
	end
	check("a face slider is on the Face step", faceSlider ~= nil)
	made = 0
	table.clear(reqs)
	local fbs0, fbo0 = FB.Stats.slices, FB.Stats.over
	drag(faceSlider, 12, 0.8)
	S.settle(0.4)
	local f3, h3 = previews()
	check("a face slider drag previews live, head-only, at most 4 a second (" .. h3 .. " in ~0.8 s)", f3 == 0 and h3 >= 1 and h3 <= 5, f3 .. "/" .. h3)
	check("a face slider drag: not a preview per move (12 moves, " .. h3 .. " previews)", h3 < 12, h3)
	check("a face slider drag creates no GUI instances", made == 0, made)
	check("a face slider drag starts no page rebuild behind the window", FB.Stats.slices == fbs0 and FB.Stats.over == fbo0, FB.Stats.slices - fbs0)
	-- the Gear step: a colour swatch
	check("Step6 (Gear)", press("Step6"))
	S.settle(0.4)
	made = 0
	table.clear(reqs)
	check("Trunks swatch", press("Swatch3"))
	S.settle(0.6)
	local f4, h4, c4 = previews()
	check("a colour swatch creates no GUI instances", made == 0, made)
	check("a colour swatch previews once, colour-only (no full Cosmetics on the server)", f4 == 0 and h4 == 0 and c4 == 1, f4 .. "/" .. h4 .. "/" .. c4)
	-- three swatches in quick succession: one preview (the client's send cap coalesces them), still colour-only
	table.clear(reqs)
	press("Swatch4")
	press("Swatch5")
	press("Swatch6")
	S.settle(0.6)
	local f4b, h4b, c4b = previews()
	check("three quick swatch picks: debounced to at most two colour-only previews", f4b == 0 and h4b == 0 and c4b >= 1 and c4b <= 2, f4b .. "/" .. h4b .. "/" .. c4b)
	-- the skin tone (Skin & Eyes): colour-only too (the server's colour path rebuilds the face for it)
	check("Step3 (Skin)", press("Step3"))
	S.settle(0.4)
	made = 0
	table.clear(reqs)
	check("a skin tone swatch", press("Swatch2"))
	S.settle(0.6)
	local f6, h6, c6 = previews()
	check("a skin tone swatch: one colour-only preview", f6 == 0 and h6 == 0 and c6 == 1, f6 .. "/" .. h6 .. "/" .. c6)
	check("a skin tone swatch creates no GUI instances", made == 0, made)
	-- the Face step: a face chip is a head-only preview (the page is rebuilt for the pick: a hitch, not lag)
	check("Step2 (Face) again", press("Step2"))
	S.settle(0.4)
	table.clear(reqs)
	check("a face chip", press("Chip_wcb_grit"))
	S.settle(0.6)
	local f5, h5 = previews()
	check("a face chip previews head-only", f5 == 0 and h5 == 1, f5 .. "/" .. h5)
	print(string.format("  Creator: open %d instances, step change %d, slider step / drag / swatch 0; a 0.6 s height drag: 1 full preview (was 3)", built, tab))
	Creator.Close()
	S.settle(0.2)

	--------------------------------------------------------------------
	-- MainMenu: a burst of character changes is one re-stage
	--------------------------------------------------------------------
	-- (a second client: a created boxer, as the menu needs; the profile from the real server code, as test_ui_layout)
	local S1 = S
	S = GS.new("desktop")
	do
		local folder = Host.NewNode("Server", "Folder", S.host.Service("ServerScriptService"))
		for _, f in ipairs(fs.readDir(S.host.src .. "/server")) do
			local base = f:match("^(.-)%.lua$")
			if base and not f:find("%.server%.") then
				local n = Host.NewNode(base, "ModuleScript", folder)
				rawset(n, "_file", S.host.src .. "/server/" .. f)
			end
		end
		local Career = S.host.requireNode(folder._kids.Career)
		local Looks = S.require("Looks")
		local prof = Career.CreateProfile(nil, { first = "Marcus", last = "Reed-Okonkwo", name = "Marcus Reed-Okonkwo", nickname = "The Hammer", age = 24, nationality = "USA",
			weightClass = 5, style = "boxer", look = Looks.Defaults(1) }, 1)
		prof.record = { w = 18, l = 2, d = 1, ko = 12 }
		local P = Career.Summary(prof, true)
		P.settings = P.settings or {}
		P.settings.ui = { menuAtStart = false }
		S.P = P
		S.onInvokeServer = function(_, action)
			if action == "GetProfile" then
				return P
			end
			return { ok = false }
		end
		S.loadScript("client/ClientMain.client.lua")
		S.settle(0.6)
	end
	local MM = S.require("Client/MainMenu")
	local MS = S.require("Client/MenuStage")
	local places = 0
	local realPlace = MS.Place
	MS.Place = function(...)
		places += 1
		return realPlace(...)
	end
	-- a character for the menu's clone (as above: root + joints)
	local char2 = S.E.new("Model")
	char2.Name = "Boxer"
	local hum2 = S.E.new("Humanoid", char2)
	hum2.HipHeight = 2
	local base2 = CFrame.new(20, 3, 40)
	local root2 = S.E.new("Part", char2)
	root2.Name = "HumanoidRootPart"
	root2.Size = Vector3.new(2, 2, 1)
	root2.CFrame = base2
	local parts2 = { HumanoidRootPart = root2 }
	for _, r in ipairs(R15) do
		local p = S.E.new("MeshPart", char2)
		p.Name = r[1]
		p.CFrame = base2 * CFrame.new(r[4])
		parts2[r[1]] = p
		local m = S.E.new("Motor6D", p)
		m.Name = r[3]
		m.Part0, m.Part1 = parts2[r[2]], p
		m.C0 = parts2[r[2]].CFrame:ToObjectSpace(p.CFrame)
		m.C1 = CFrame.new()
	end
	local look2 = S.E.new("Folder", char2)
	look2.Name = "BoxerLook"
	char2.Parent = S.E.workspace
	S.player.Character = char2
	MM.Open()
	S.settle(0.5)
	check("MainMenu: the boxer staged once on open", places == 1 and MS ~= nil, places)
	-- a server rebuild of the look: hundreds of parts added under BoxerLook in a burst, attributes flipped
	places = 0
	local t0 = os.clock()
	for i = 1, 300 do
		local p = S.E.new("MeshPart", look2)
		p.Name = "Piece" .. i
		p:SetAttribute("GearPiece", "Trunks")
	end
	char2:SetAttribute("LookSig", "abc")
	char2:SetAttribute("BodyTiers", "1111")
	local burst = os.clock() - t0
	S.settle(0.3)
	check("MainMenu: no re-stage before the changes settle", places == 0, places)
	S.settle(0.9)
	check("MainMenu: one re-stage after a burst of 300 changes", places == 1, places)
	print(string.format("  MainMenu: 302 change signals in %.1f ms -> 1 re-stage (one pending timer; was 302 task.delay threads)", burst * 1000))
	-- GUI built once and toggled: the home layer is hidden under a screen and shown again as it was
	local FC = S.require("Client/FighterCard")
	local hb, m0, s0 = MM.Stats().homeBuilds, FC.masters, FC.shots
	MM.Show("career")
	S.settle(0.6)
	check("the career screen builds (the fighter card's portrait)", named("Card") ~= nil or S.playerGui:FindFirstChild("Card", true) ~= nil)
	MM.Show("home")
	S.settle(0.3)
	MM.Show("rankings")
	S.settle(0.6)
	MM.Show("home")
	S.settle(0.3)
	MM.Show("career")
	S.settle(0.6)
	MM.Show("home")
	S.settle(0.3)
	check("two career visits: one posed master (cached), a copy per photo (" .. (FC.masters - m0) .. " masters, " .. (FC.shots - s0) .. " shots)",
		FC.masters - m0 <= 1 and FC.shots - s0 == 2, (FC.masters - m0) .. "/" .. (FC.shots - s0))
	check("GUI built once: home -> career -> home -> rankings -> home builds the home layer no more times (" .. (MM.Stats().homeBuilds - hb) .. ")",
		MM.Stats().homeBuilds == hb, MM.Stats().homeBuilds - hb)
	check("the set up: the LocalPlayer carries MenuStage", S.player:GetAttribute("MenuStage") == true)
	-- the stage parked on close, the flag gone, the light back on
	local stage0 = MM.Stats().stage
	local clone0 = stage0 and stage0.clone
	MM.Close()
	S.settle(0.6)
	check("closed: the set is parked (kept out of the world, not destroyed)", MM.Stats().parked and stage0 and stage0.folder ~= nil and stage0.folder.Parent == nil)
	check("closed: MenuStage cleared", S.player:GetAttribute("MenuStage") == nil)
	-- open again: the same set and the same copy (the character has not changed), nothing built
	local builds = 0
	local realBuild = MS.Build
	MS.Build = function(...)
		builds += 1
		return realBuild(...)
	end
	places = 0
	MM.Open()
	S.settle(0.5)
	local stage1 = MM.Stats().stage
	check("reopen: the parked set is reused (no MenuStage.Build)", builds == 0 and stage1 == stage0, builds)
	check("reopen: the boxer's copy is reused (the character did not change)", stage1 and stage1.clone == clone0 and clone0 ~= nil and clone0.Parent == stage1.folder)
	check("reopen: MenuStage set again", S.player:GetAttribute("MenuStage") == true)
	MM.Close()
	S.settle(0.4)
	MS.Build = realBuild
	S = S1
end

print(string.format("test_menustage: %d passed, %d failed", pass, fail))
-- (the client sim leaves scheduled threads behind: an explicit exit, as test_ui_layout)
process.exit(fail == 0 and 0 or 1)
