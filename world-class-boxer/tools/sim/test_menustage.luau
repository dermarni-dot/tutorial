--!nocheck
-- tools/sim/test_menustage.luau: the main menu's boxer (MenuStage) on a fake R15 character (fakeengine)
--   * Ready: a character mid-swap (a body part missing) is not staged
--   * Place: the copy carries the server's non-Archivable parts (tier MeshParts, gear) and the character's own
--     Archivable flags are put back; the copy stands on the set, tagged Preview, client hair folder dropped,
--     LocalTransparencyModifier reset; a part no joint ties to the root is held at its place by a weld
--   * Place again (a re-stage) replaces the previous copy
--   * AnatomyClient in Config.BaldMode: no hair generator, no EditableMesh (not even the probe), a quiet status
--   lune run tools/sim/test_menustage.luau
local roblox = require("@lune/roblox")
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

print(string.format("test_menustage: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_menustage failed")
end
