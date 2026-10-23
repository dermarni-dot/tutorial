--!nocheck
-- tools/sim/test_menustage.luau: the main menu's boxer (MenuStage) on a fake R15 character (fakeengine)
--   * Ready: a character mid-swap (a body part missing) is not staged
--   * Place: the copy carries the server's non-Archivable parts (tier MeshParts, gear) and the character's own
--     Archivable flags are put back; the copy stands on the set, tagged Preview, client hair folder dropped,
--     LocalTransparencyModifier reset; a part no joint ties to the root is held at its place by a weld
--   * Place again (a re-stage) replaces the previous copy
--   * AnatomyClient in Config.BaldMode: no hair generator, no EditableMesh (not even the probe), a quiet status
--   * the set's size per Graphics level (parts, lights, shadow casters) and its per-frame Step / Shot cost
--   * BuilderTiers.Preload is paced: the default family first, one load per gap, the other families deferred
--   * the Creator's live preview (guisim, the real client code): the window is built once (a step change keeps its
--     chrome), a slider change and a swatch pick create no GUI instances, a DRAG of a whole-body slider (height)
--     sends one full preview when it is let go (not two a second), a head slider's drag sends head-only previews
--     at the client's cap, a colour swatch sends one preview
--   * MainMenu re-stages the boxer once after a burst of character changes (one pending re-stage, not a timer per
--     changed descendant)
--   lune run tools/sim/test_menustage.luau
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local process = require("@lune/process")
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
-- BuilderTiers.Preload: paced, the default family first, the other families deferred
------------------------------------------------------------------------
do
	local BuilderTiers = H.require("BuilderTiers")
	local BodyTiers = H.require("BodyTiers")
	local keys = {}
	local function keyOf(e, tier, name)
		return tier .. ":" .. name .. ":" .. e.id
	end
	local defN, otherN = 0, 0
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
	for _, frame in ipairs(BodyTiers.Frames()) do
		if frame ~= BodyTiers.DEFAULT_FRAME then
			for tier = 1, BodyTiers.TIERS do
				for _, name in ipairs(BodyTiers.PARTS) do
					local e = BodyTiers.PartEntry(tier, name, nil, false, frame)
					if e and not keys[keyOf(e, tier, name)] then
						keys[keyOf(e, tier, name)] = true
						otherN += 1
					end
				end
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
	BuilderTiers.Preload({ gap = 0.01, defer = 0.4 })
	check("Preload: returns at once (one load in flight at most)", AS.calls <= 1, AS.calls)
	task.wait(0.12)
	check("Preload: paced, not all at once (" .. AS.calls .. " of " .. defN .. " default loads after 0.12 s)", AS.calls >= 2 and AS.calls < defN, AS.calls)
	local tDef = os.clock()
	while AS.calls < defN and os.clock() - tDef < 20 do
		task.wait(0.02)
	end
	check("Preload: the default family (full + lite) loads first: " .. defN .. " loads", AS.calls == defN, AS.calls)
	local doneAt = os.clock()
	task.wait(0.2)
	check("Preload: the other families wait for the defer", AS.calls == defN, AS.calls)
	local tOth = os.clock()
	while AS.calls < defN + otherN and os.clock() - tOth < 30 do
		task.wait(0.02)
	end
	check("Preload: then the other families (" .. otherN .. " loads)", AS.calls == defN + otherN, AS.calls)
	check("Preload: the first other-family load came after the defer", (AS.at[defN + 1] or 0) - doneAt >= 0.3, AS.at[defN + 1] and (AS.at[defN + 1] - doneAt))
	print(string.format("  Preload: %d + %d loads over %.1f s (gap 0.01, defer 0.4); the old preload fired all %d back to back", defN, otherN, os.clock() - t0, defN + otherN))
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
	local function previews()
		local full, head = 0, 0
		for _, r in ipairs(reqs) do
			if r.action == "PreviewLook" then
				local popts = r.args[3]
				if type(popts) == "table" and type(popts.only) == "table" then
					head += 1
				else
					full += 1
				end
			end
		end
		return full, head
	end
	local function named(name)
		for _, d in ipairs(S.playerGui:GetDescendants()) do
			if d.Name == name and d.Visible ~= false then
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
			if d:GetAttribute("Slider") and d:FindFirstChild("Label") then
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
	made = 0
	Creator.Open()
	S.settle(0.8)
	local built = made
	check("Creator.Open: the window built (under 900 instances)", built > 50 and built < 900, built)
	local chrome = { named("Tools"), named("StepBar"), named("Nav"), named("FighterPlate"), named("Turntable") }
	check("Creator.Open: the chrome is there", chrome[1] and chrome[2] and chrome[3] and chrome[4] and chrome[5])
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
	drag(faceSlider, 12, 0.8)
	S.settle(0.4)
	local f3, h3 = previews()
	check("a face slider drag previews live, head-only, at most 4 a second (" .. h3 .. " in ~0.8 s)", f3 == 0 and h3 >= 1 and h3 <= 5, f3 .. "/" .. h3)
	check("a face slider drag creates no GUI instances", made == 0, made)
	-- the Gear step: a colour swatch
	check("Step6 (Gear)", press("Step6"))
	S.settle(0.4)
	made = 0
	table.clear(reqs)
	check("Trunks swatch", press("Swatch3"))
	S.settle(0.6)
	local f4, h4 = previews()
	check("a colour swatch creates no GUI instances", made == 0, made)
	check("a colour swatch previews once", f4 + h4 == 1, f4 .. "/" .. h4)
	-- the Hair step: a hair colour swatch is a head-only preview
	check("Step4 (Hair)", press("Step4"))
	S.settle(0.4)
	table.clear(reqs)
	check("Hair colour swatch", press("Swatch2"))
	S.settle(0.6)
	local f5, h5 = previews()
	check("a hair colour swatch previews head-only", f5 == 0 and h5 == 1, f5 .. "/" .. h5)
	print(string.format("  Creator: open %d instances, step change %d, slider step / drag / swatch 0; a 0.6 s height drag: 1 full preview (was 3)", built, tab))
	Creator.Close()
	S.settle(0.2)

	--------------------------------------------------------------------
	-- MainMenu: a burst of character changes is one re-stage
	--------------------------------------------------------------------
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
	end
	local look2 = S.E.new("Folder", char2)
	look2.Name = "BoxerLook"
	char2.Parent = S.E.workspace
	S.player.Character = char2
	S.P = { created = true, identity = { name = "Marcus Reed-Okonkwo", nationality = "USA" }, record = { w = 1, l = 0, d = 0, ko = 1 } }
	local State = S.require("Client/State")
	State.P = S.P
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
	MM.Close()
	S.settle(0.4)
end

print(string.format("test_menustage: %d passed, %d failed", pass, fail))
-- (the client sim leaves scheduled threads behind: an explicit exit, as test_ui_layout)
process.exit(fail == 0 and 0 or 1)
