--!nocheck
-- v9_faces.luau: boxers' faces as the game builds them, for the v9 face previews (tools/sim/v9_faces_render.py ->
-- previews/final/v9/faces, previews/final/v9/injuries). Nothing is placed by hand: for every entry below the
-- server's Builder.Cosmetics runs on the fake R15 rig of v8_scene.luau (fakeengine Instances, the tier swap, the
-- classic head, BuilderHead's face), then the entry's state is put on it the way the game does it:
--   * expr: the server's Expr attribute (+ Guard "down" for the KO), and the REAL client FaceFX.Update run for 1.5 s
--     of virtual time (the face rig's Motor6D.Transform and mesh scales; an older src: whatever its FaceFX does)
--   * damage: Builder.SetDamage with the Creator's damage presets (Light .. Severe)
--   * workout: the post-workout flow of Main.server finishActivity: the Grime attribute (roadwork), a rebuild with a
--     bigger build (applyLook -> Builder.Apply -> Cosmetics: a tier change), then Builder.SetSweat(0.85)
-- The rig's joints are solved like the engine (Motor6D: Part1 = Part0 * C0 * Transform * C1^-1; WeldConstraints keep
-- the offset they were made with, recorded the first time a solve sees them). Every visible part is written out
-- (shape, CFrame, size, colour, material, reflectance, transparency) with the tier meshes and the classic head (and
-- its decal on an older src).
--
--   lune run tools/sim/v9_faces.luau [--out DIR] [--src DIR] [--only id,id] [--detail full|medium|low] [--set wcb]
-- --set wcb: only the drawn Boxer face style entries (look.face.style, the head's front decal; previews/final/v9/wcb_faces):
-- light / mid / dark skin, the four faces, the smallest / default / largest head (female Lean, male Athletic, male
-- Heavyweight), the mood swaps through FaceFX (guard, effort, happy, KO), damage, the post-workout sweat and grime,
-- and the creator's choice (Built and the four on one boxer)
local fs = require("@lune/fs")
local task = require("@lune/task")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Host = require("./host")
local FE = require("./fakeengine")
local MeshV2 = require("./meshv2")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local SCRATCH = "/tmp/claude-0/v9faces"

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		args[a[i]:gsub("^%-%-", "")] = a[i + 1]
		i += 2
	end
end
local OUT = (args.out or SCRATCH):gsub("/$", "")
local only
if args.only then
	only = {}
	for id in args.only:gmatch("[^,]+") do
		only[id] = true
	end
end

------------------------------------------------------------------------
-- the entries
------------------------------------------------------------------------
-- face = the Creator's face presets (LookKit.FacePresets: shape + slider values over the gender default)
local PRESETS = {
	Classic = { shape = "Oval", set = {} },
	Chiselled = { shape = "Square", set = { jawWidth = 0.5, jawDef = 0.9, cheek = 0.5, chin = 0.3 } },
	Rugged = { shape = "Square", set = { jawWidth = 0.6, noseWidth = 0.4, noseBridge = 0.3, chin = 0.4, browThick = 0.4 } },
	["Baby Face"] = { shape = "Round", set = { jawWidth = -0.4, jawDef = 0.2, cheekFull = 0.6, chin = -0.3, eyeSize = 0.3, noseLength = -0.3, lips = 0.2 } },
	Heart = { shape = "Heart", set = { forehead = 0.3, chin = -0.3, jawWidth = -0.4, cheek = 0.4, lips = 0.3 } },
	Brawler = { shape = "Round", set = { noseWidth = 0.6, noseBridge = -0.4, lips = 0.4, jawWidth = 0.5, browThick = 0.5, noseBreak = 0.35 } },
}
local DAMAGE = {
	Light = { leftEye = 0.2, bruise = 0.25, redness = 0.6 },
	Moderate = { leftEye = 0.45, cheekL = 0.5, bruise = 0.35, noseBleed = 0.4, forehead = 0.3 },
	Heavy = { leftEye = 0.7, cut = 0.6, cutSide = -1, bruise = 0.5, lip = 0.5, noseBleed = 0.5, cheekL = 0.5 },
	Severe = { leftEye = 1, rightEye = 0.85, cut = 1.1, cutSide = -1, cut2 = 0.6, bruise = 0.9, lip = 1, noseBleed = 1, nose = true, cheekL = 1, cheekR = 0.7, forehead = 0.8, earL = 0.6 },
	-- three days after a heavy fight: the bruises gone blue-purple / yellow, no blood
	Healing = { leftEye = 0.6, cut = 0.5, cutSide = -1, bruise = 0.5, cheekL = 0.4, age = 3 },
	-- body shots: the rib bruises (Body.SetDamage) over a heavy face
	Body = { leftEye = 0.5, bruise = 0.4, ribsL = 0.9, ribsR = 0.45 },
}
local LOOKS = {
	{ id = "m_classic", label = "Classic, tier 2", g = 1, tier = 2, skin = 6, preset = "Classic", eye = 2 },
	{ id = "m_chiselled", label = "Chiselled, tier 4", g = 1, tier = 4, skin = 10, preset = "Chiselled", eye = 1, brow = "Thick" },
	{ id = "m_rugged", label = "Rugged + stubble, tier 3", g = 1, tier = 3, skin = 3, preset = "Rugged", eye = 4, beard = { style = "Stubble", growth = 0.6 } },
	{ id = "m_babyface", label = "Baby Face, tier 1", g = 1, tier = 1, skin = 2, preset = "Baby Face", eye = 3 },
	{ id = "f_heart", label = "Female, Heart, tier 2", g = 2, tier = 2, skin = 8, preset = "Heart", eye = 2, brow = "Soft Arch" },
	{ id = "m_veteran", label = "Veteran (age 38, fight wear), tier 5", g = 1, tier = 5, skin = 9, preset = "Brawler", eye = 1, age = 38,
		face = { cauliflower = 0.6, scars = 1, wrinkles = 0.3 }, battle = { ears = 0.5, nose = 0.6, scars = { { kind = "brow", side = 1, at = 0.4, size = 0.6 }, { kind = "cheek", side = -1, at = 0.5, size = 0.5 } } },
		beard = { style = "Short Boxed", growth = 0.5 } },
}
local ENTRIES = {}
local function entry(look, state, extra)
	local e = table.clone(extra or {})
	e.look = look
	e.state = state
	e.id = look.id .. "_" .. state
	table.insert(ENTRIES, e)
end
local byId = {}
for _, l in ipairs(LOOKS) do
	byId[l.id] = l
	entry(l, "neutral")
end
for _, ex in ipairs({ "anger", "pain", "happy", "confident", "effort", "fatigue", "ko" }) do
	entry(byId.m_classic, ex, { expr = ex })
end
-- a blink: FaceFX's own blink caught while the eye is shut (BlinkLid shown, the lids down)
entry(byId.m_classic, "blink", { blink = true })
entry(byId.f_heart, "blink", { blink = true })
entry(byId.m_rugged, "happy", { expr = "happy" })
entry(byId.m_rugged, "anger", { expr = "anger" })
-- the creator: every brow style, the eye / wear / skin sliders at their ends, the face shapes (face = overrides)
for _, b in ipairs({ "Natural", "Straight", "Soft Arch", "High Arch", "Thick", "Thin" }) do
	entry(byId.m_classic, "brow" .. b:gsub(" ", ""), { face = { browStyle = b } })
end
for _, f in ipairs({
	{ "eyeRound", { eyeShape = 0 } }, { "eyeAlmond", { eyeShape = 1 } }, { "eyeBig", { eyeSize = 1 } }, { "eyeSmall", { eyeSize = -1 } },
	{ "hooded", { lidHeavy = 1 } }, { "hetero", { eyeColor = 5, eyeColor2 = 4 } }, { "lashes", { lashes = 1 } }, { "tilt", { eyeTilt = 1 } },
	{ "browHigh", { browHeight = 1, browAngle = 1 } }, { "browThickMax", { browThick = 1 } }, { "noseBig", { noseWidth = 1, noseLength = 1, noseBridge = 1 } },
	{ "noseSmall", { noseWidth = -1, noseLength = -1, noseBridge = -1 } }, { "lipsFull", { lips = 1, mouthWidth = 1 } }, { "cheekHigh", { cheek = 1 } },
	{ "chinBig", { chin = 1, chinCleft = 1 } }, { "wear", { cauliflower = 1, noseBreak = 1 } }, { "scarred", { scars = 3, wrinkles = 1 } },
	{ "skin", { freckles = 1, moles = 3, marks = 1, acne = 0.6 } },
}) do
	entry(byId.m_classic, f[1], { face = f[2] })
end
for _, sh in ipairs({ "Square", "Diamond", "Round", "Long", "Heart" }) do
	entry(byId.m_classic, "shape" .. sh, { face = { shape = sh } })
end
for _, ex in ipairs({ "anger", "happy", "pain" }) do
	entry(byId.f_heart, ex, { expr = ex })
	entry(byId.m_chiselled, ex, { expr = ex })
end
for _, d in ipairs({ "Light", "Moderate", "Heavy", "Severe", "Healing" }) do
	entry(byId.m_classic, "dmg" .. d, { damage = d })
	entry(byId.m_chiselled, "dmg" .. d, { damage = d })
end
entry(byId.f_heart, "dmgHeavy", { damage = "Heavy" })
entry(byId.m_chiselled, "dmgBody", { damage = "Body" })
entry(byId.f_heart, "dmgBody", { damage = "Body" })
entry(byId.m_veteran, "dmgBody", { damage = "Body" })
for _, id in ipairs({ "m_classic", "m_chiselled", "f_heart", "m_babyface" }) do
	entry(byId[id], "workout", { workout = true })
end
entry(byId.m_classic, "workoutRoad", { workout = true, grime = 0.7 })
-- the drawn Boxer face styles (only with --set wcb)
local WCB = {
	{ id = "wcb_light", label = "Boxer Neutral, light skin", g = 1, tier = 2, skin = 2, preset = "Classic", style = "wcb_neutral" },
	{ id = "wcb_mid", label = "Boxer Neutral, mid skin", g = 1, tier = 2, skin = 6, preset = "Classic", style = "wcb_neutral" },
	{ id = "wcb_dark", label = "Boxer Neutral, dark skin", g = 1, tier = 2, skin = 11, preset = "Classic", style = "wcb_neutral" },
	{ id = "wcb_focused", label = "Boxer Focused", g = 1, tier = 2, skin = 6, preset = "Classic", style = "wcb_focused" },
	{ id = "wcb_smirk", label = "Boxer Smirk", g = 1, tier = 2, skin = 6, preset = "Classic", style = "wcb_smirk" },
	{ id = "wcb_grit", label = "Boxer Grit", g = 1, tier = 2, skin = 6, preset = "Classic", style = "wcb_grit" },
	{ id = "wcb_minhead", label = "smallest head (female, Lean)", g = 2, tier = 2, skin = 8, preset = "Classic", style = "wcb_neutral", frame = "Lean" },
	{ id = "wcb_maxhead", label = "largest head (Heavyweight)", g = 1, tier = 4, skin = 4, preset = "Classic", style = "wcb_neutral", frame = "Heavyweight Build" },
	{ id = "wcb_beard", label = "Boxer Smirk + short boxed beard", g = 1, tier = 3, skin = 9, preset = "Rugged", style = "wcb_smirk", beard = { style = "Short Boxed", growth = 0.6 } },
	{ id = "wcb_built", label = "Built (the default)", g = 1, tier = 2, skin = 6, preset = "Classic", style = "built" },
}
local WCB_ENTRIES = {}
do
	local n0 = #ENTRIES
	for _, l in ipairs(WCB) do
		byId[l.id] = l
		entry(l, "rest")
	end
	for _, ex in ipairs({ { "guard", { guard = true } }, { "effort", { expr = "effort" } }, { "happy", { expr = "happy" } }, { "anger", { expr = "anger" } }, { "ko", { expr = "ko" } } }) do
		entry(byId.wcb_mid, ex[1], ex[2])
	end
	for _, d in ipairs({ "Moderate", "Heavy", "Severe" }) do
		entry(byId.wcb_mid, "dmg" .. d, { damage = d })
	end
	entry(byId.wcb_dark, "dmgSevere", { damage = "Severe" })
	entry(byId.wcb_light, "dmgHeavy", { damage = "Heavy" })
	entry(byId.wcb_mid, "workout", { workout = true, grime = 0.7 })
	entry(byId.wcb_dark, "workout", { workout = true, grime = 0.7 })
	for i = n0 + 1, #ENTRIES do
		WCB_ENTRIES[ENTRIES[i].id] = true
	end
end
-- --set wcb2: every drawn Boxer face (the user's four + tools/body/wcb_faces_draw.py's) on light / mid / dark skin
-- (previews/final/v9/wcb_faces2). Each boxer is built with the style wcb_neutral (so the head carries the style decal
-- whatever the src's STYLE_KEYS list), then the exported decal file is that face's PNG from faces.json (decalKey).
local WCB2_ENTRIES = {}
do
	local keys = { "wcb_neutral", "wcb_focused", "wcb_smirk", "wcb_grit", "wcb_confident", "wcb_grin", "wcb_cool", "wcb_wink",
		"wcb_stern", "wcb_determined", "wcb_toothy", "wcb_scarred", "wcb_shout", "wcb_hurt", "wcb_dazed", "wcb_ko", "wcb_tired",
		"wcb_surprised" }
	for _, sk in ipairs({ { "light", 2 }, { "mid", 6 }, { "dark", 11 } }) do
		for _, k in ipairs(keys) do
			local L = { id = "f2_" .. sk[1] .. "_" .. k:sub(5), label = k .. ", " .. sk[1] .. " skin", g = 1, tier = 2, skin = sk[2], preset = "Classic",
				style = "wcb_neutral", bald = true }
			byId[L.id] = L
			entry(L, "rest", { decalKey = k })
			WCB2_ENTRIES[ENTRIES[#ENTRIES].id] = true
		end
	end
end
-- the walkout robe on every tier, the frames and the heights (body views; clearance metrics in the report)
local ROBES = {
	{ id = "robe_t1_lean_62", g = 1, tier = 1, skin = 6, frame = "Lean", height = 62, robe = "Classic" },
	{ id = "robe_t2_athletic_70", g = 1, tier = 2, skin = 3, frame = "Athletic", height = 70, robe = "Classic" },
	{ id = "robe_t3_muscular_74", g = 1, tier = 3, skin = 9, frame = "Muscular", height = 74, robe = "Champion" },
	{ id = "robe_t4_power_72", g = 1, tier = 4, skin = 10, frame = "Power Build", height = 72, robe = "Hooded" },
	{ id = "robe_t5_heavy_80", g = 1, tier = 5, skin = 6, frame = "Heavyweight Build", height = 80, robe = "Classic" },
	{ id = "robe_f3_athletic_66", g = 2, tier = 3, skin = 8, frame = "Athletic", height = 66, robe = "Classic" },
}
for _, r in ipairs(ROBES) do
	local L = { id = r.id, label = r.id, g = r.g, tier = r.tier, skin = r.skin, preset = "Classic", frame = r.frame, height = r.height }
	table.insert(ENTRIES, { id = r.id, look = L, state = "robe", robe = r.robe })
end

------------------------------------------------------------------------
-- host: the fake engine
------------------------------------------------------------------------
local root = Host.FindRoot()
local srcDir = args.src or (root .. "/src")
local E = FE.new()
local H = Host.new({ root = root, src = srcDir, globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
H.Service("AssetService")._props = { CreateMeshPartAsync = function()
	error("no mesh service here")
end }

local Looks = H.require("Looks")
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local Builder = H.require("Builder")
local Kit = H.require("AnatomyHairKit")
local okFX, FaceFX = pcall(H.require, "Client/FaceFX")
if not okFX then
	print("FaceFX not loaded: " .. tostring(FaceFX))
	FaceFX = nil
end
local okGear, BuilderGear = pcall(H.require, "BuilderGear")
if okGear and type(BuilderGear) == "table" and BuilderGear.SetData then
	BuilderGear.SetData({ tiers = {} }) -- the part-built gear (the face previews frame the head)
end
local REAL = BodyTiers.Data()

-- each uploaded face's local PNG (faces.json names the file: the drawn Boxer faces are versioned, face_<key>_v2.png)
local FACE_FILES = {}
local faceFile = {}
do
	local okJ, fj = pcall(function()
		return require("@lune/serde").decode("json", fs.readFile(root .. "/tools/body/out/faces/faces.json"))
	end)
	for _, f in ipairs(okJ and fj.faces or {}) do
		faceFile[f.key] = f.file
	end
end
for _, f in ipairs(REAL.faces or {}) do
	if f.id and f.id ~= 0 then
		FACE_FILES["rbxassetid://" .. f.id] = root .. "/tools/body/out/faces/" .. (faceFile[f.key] or ("face_" .. f.key .. ".png"))
	end
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

local weldOffsets = setmetatable({}, { __mode = "k" })
local function solve(model)
	local joints = {}
	for _, d in ipairs(model:GetDescendants()) do
		local c = d.ClassName
		if c == "WeldConstraint" and d.Part0 and d.Part1 and not weldOffsets[d] then
			-- first seen: the offset its parts were built with
			weldOffsets[d] = d.Part0.CFrame:Inverse() * d.Part1.CFrame
		end
		if c == "Motor6D" or c == "Weld" or (c == "WeldConstraint" and weldOffsets[d]) then
			table.insert(joints, d)
		end
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	hrp.CFrame = CFrame.new(0, hum.HipHeight + hrp.Size.Y / 2, 0)
	local done = { [hrp] = true }
	local progress = true
	while progress do
		progress = false
		for _, j in ipairs(joints) do
			local p0, p1 = j.Part0, j.Part1
			if p0 and p1 and done[p0] and not done[p1] then
				if j.ClassName == "WeldConstraint" then
					p1.CFrame = p0.CFrame * weldOffsets[j]
				else
					p1.CFrame = p0.CFrame * j.C0 * (j.ClassName == "Motor6D" and j.Transform or CFrame.new()) * j.C1:Inverse()
				end
				done[p1] = true
				progress = true
			end
		end
	end
end

local function newRig(scale, headSize)
	local model = E.new("Model")
	model.Name = "Boxer"
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1) * scale
	hrp.Transparency = 1
	local ra = E.new("Attachment", hrp)
	ra.Name = "RootRigAttachment"
	ra.Position = Vector3.zero
	local function addPart(name, size, orig, atts)
		local p = E.new("MeshPart", model)
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
		local m = E.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
	end
	local hum = E.new("Humanoid", model)
	hum.HipHeight = 2 * scale.Y
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
}
if okGear and type(BuilderGear) == "table" then
	BuilderGear.Services = BuilderTiers.Services
	if BuilderGear.Reset then
		BuilderGear.Reset()
	end
end

-- every build step sees the parts where the engine would have put them
local Head = H.require("BuilderHead")
local Body = H.require("BuilderBody")
local currentModel
local function solving(mod, key)
	local f = mod[key]
	if type(f) ~= "function" then
		return
	end
	mod[key] = function(model, ...)
		if model == currentModel then
			solve(model)
		end
		return f(model, ...)
	end
end
for _, k in ipairs({ "Colors", "Muscles", "Attire", "Hands" }) do
	solving(Body, k)
end
for _, k in ipairs({ "Face", "Beard", "SetDamage", "SetSweat" }) do
	solving(Head, k)
end

------------------------------------------------------------------------
-- helpers
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

local function appFor(L)
	local app = Looks.Defaults(L.g)
	app.skin = L.skin
	local p = PRESETS[L.preset] or PRESETS.Classic
	app.face.shape = p.shape
	for k, v in pairs(p.set) do
		app.face[k] = v
	end
	for k, v in pairs(L.face or {}) do
		app.face[k] = v
	end
	app.face.eyeColor = L.eye or app.face.eyeColor
	app.face.browStyle = L.brow or app.face.browStyle
	app.face.seed = #L.id * 977 + 13
	if L.beard then
		app.beard = { style = L.beard.style, growth = L.beard.growth }
	end
	app.battle = L.battle
	if L.style then
		app.face.style = L.style
	end
	if L.bald then
		app.hair.style = "Bald" -- the face previews: nothing over the brows
	end
	if L.frame then
		app.body.frame = L.frame
	end
	if L.height then
		app.height = L.height
	end
	return app
end

------------------------------------------------------------------------
-- one entry
------------------------------------------------------------------------
Host.MkDir(OUT)
local index = { about = "v9 faces: Builder.Cosmetics on a fake rig + the entry's state (FaceFX / SetDamage / workout), world space, studs, +Y up, face -Z",
	src = srcDir, looks = {} }
local report = {}

for _, e in ipairs(ENTRIES) do
	if only and not only[e.id] and not only[e.look.id] then
		continue
	end
	local inSet = (WCB_ENTRIES[e.id] and "wcb") or (WCB2_ENTRIES[e.id] and "wcb2") or nil
	if args.set ~= inSet then
		continue
	end
	local L = e.look
	local app = appFor(L)
	for k, v in pairs(e.face or {}) do
		app.face[k] = v
	end
	local tier = L.tier
	local _, b = buildFor(app, tier)
	local sc = Builder.Scales(app, b)
	local model = newRig(Vector3.new(sc.width, sc.height, sc.depth), 1.2 * sc.head)
	model.Parent = E.workspace
	currentModel = model
	local opts = { hands = "gloves", detail = args.detail or "full", age = L.age or 24 }
	local ok, err = pcall(Builder.Cosmetics, model, app, b, nil, opts)
	if not ok then
		error(e.id .. ": Cosmetics failed: " .. tostring(err))
	end
	solve(model)
	if e.workout then
		-- Main.server finishActivity: the Grime attribute (roadwork) BEFORE the rebuild, applyLook (Builder.Apply: same
		-- ScaleKey, so Cosmetics on the rig) with the session's bigger build (a tier up), then setSweat
		if e.grime then
			model:SetAttribute("Grime", e.grime)
		end
		local _, b2 = buildFor(app, math.min(5, tier + 1))
		local ok2, err2 = pcall(Builder.Cosmetics, model, app, b2, nil, opts)
		if not ok2 then
			error(e.id .. ": rebuild failed: " .. tostring(err2))
		end
		solve(model)
		Builder.SetSweat(model, app, 0.85)
		solve(model)
	end
	if e.damage then
		Builder.SetDamage(model, app, DAMAGE[e.damage])
		solve(model)
	end
	local robeReport
	if e.robe then
		Builder.SetRobe(model, app, true, { robe = e.robe, nick = "THE KID" })
		solve(model)
		-- clearance: every tier-mesh vertex of the part a shell is welded to, in the shell's box (inside = covered;
		-- the margin = how far the box stands off the body at its widest)
		local look = model:FindFirstChild("BoxerLook")
		local robe = look and look:FindFirstChild("Robe")
		local out = {}
		for _, shell in ipairs(robe and robe:GetChildren() or {}) do
			local w = shell:FindFirstChildOfClass("WeldConstraint")
			local p0 = w and w.Part0
			if not (p0 and p0:GetAttribute("BodyTier") and (shell.Name == "RobeTorso" or shell.Name == "Sleeve" or shell.Name == "SleeveLow" or shell.Name == "RobeSkirt")) then
				continue
			end
			local parts = { p0 }
			if shell.Name == "RobeSkirt" then
				parts = { model:FindFirstChild("LeftUpperLeg"), model:FindFirstChild("RightUpperLeg"), p0 }
			end
			local inside, total, gapX, gapZ = 0, 0, math.huge, math.huge
			local hs = shell.Size / 2
			for _, bp in ipairs(parts) do
				local m = MeshV2.Read(string.format("%s/tools/body/out/tier%d/%s.mesh", root, bp:GetAttribute("BodyTier"), bp.Name))
				local cx, cy, cz, bx, by, bz = MeshV2.Bounds(m)
				local ks = bp.Size
				for i = 1, #m.P, 3 do
					local wpos = bp.CFrame * Vector3.new((m.P[i] - cx) * ks.X / bx, (m.P[i + 1] - cy) * ks.Y / by, (m.P[i + 2] - cz) * ks.Z / bz)
					local lp = shell.CFrame:PointToObjectSpace(wpos)
					if math.abs(lp.Y) <= hs.Y then
						total += 1
						if math.abs(lp.X) <= hs.X and math.abs(lp.Z) <= hs.Z then
							inside += 1
						end
						gapX = math.min(gapX, hs.X - math.abs(lp.X))
						gapZ = math.min(gapZ, hs.Z - math.abs(lp.Z))
					end
				end
			end
			table.insert(out, string.format("%s %.0f%% inside, min gap x %+.3f z %+.3f", shell.Name, total > 0 and 100 * inside / total or 0, gapX, gapZ))
		end
		robeReport = table.concat(out, "; ")
	end
	local head = model:FindFirstChild("Head")
	if e.expr or FaceFX then
		-- the client: FaceFX on the face rig (1.5 s of virtual time at 30 Hz), the camera 3 studs in front
		if e.expr == "ko" then
			model:SetAttribute("Guard", "down")
		elseif e.guard then
			model:SetAttribute("Guard", "up")
		end
		if e.expr then
			model:SetAttribute("Expr", e.expr)
		end
		if e.workout then
			model:SetAttribute("Stam", 0.35)
		end
		if FaceFX then
			-- (fakeengine Instances carry no defaults: a SpecialMesh's Scale / Offset as the engine gives them)
			for _, d in ipairs(model:GetDescendants()) do
				if d.ClassName == "SpecialMesh" then
					d.Scale = d.Scale or Vector3.new(1, 1, 1)
					d.Offset = d.Offset or Vector3.zero
				end
			end
			local camPos = head.Position + Vector3.new(0, 0, -3)
			for i = 1, 45 do
				local okU, errU = pcall(FaceFX.Update, 1 / 30, i / 30, camPos, nil, 99)
				if not okU then
					print("FaceFX.Update failed: " .. tostring(errU))
					break
				end
			end
		end
		if e.blink and FaceFX then
			-- wait (real time: FaceFX times blinks by os.clock) for the eyes to shut, then stop there
			local camPos = head.Position + Vector3.new(0, 0, -3)
			local t0 = os.clock()
			local i = 45
			while os.clock() - t0 < 9 do
				i += 1
				pcall(FaceFX.Update, 1 / 30, i / 30, camPos, nil, 99)
				local d = FaceFX.Debug(model)
				if d and d.closed then
					break
				end
				task.wait(0.01)
			end
		else
			-- the still frame: never mid-blink
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == "BlinkLid" and d.Transparency < 1 then
					d.Transparency = 1
				end
			end
		end
		solve(model)
	end

	local scene = { id = e.id, label = L.label .. " - " .. e.state, parts = {}, meshes = {}, hair = {} }
	local counts = { parts = 0, face = 0, rig = 0 }
	local look = model:FindFirstChild("BoxerLook")
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "Motor6D" and d.Name == "FaceJoint" then
			counts.rig += 1
		end
	end
	for _, p in ipairs(model:GetDescendants()) do
		local cls = p.ClassName
		if not (cls == "Part" or cls == "MeshPart" or cls == "WedgePart") or p.Name == "HumanoidRootPart" then
			continue
		end
		local face = look and look:FindFirstChild("Face")
		if face and p:IsDescendantOf(face) then
			counts.face += 1
		end
		if (p.Transparency or 0) >= 0.99 then
			continue
		end
		local tierN = p:GetAttribute("BodyTier")
		if cls == "MeshPart" and tierN then
			local m = MeshV2.Read(string.format("%s/tools/body/out/tier%d/%s.mesh", root, tierN, p.Name))
			local cx, cy, cz, bx, by, bz = MeshV2.Bounds(m)
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
			table.insert(scene.meshes, { name = p.Name, tier = tierN, p = P, n = N, t = m.T, color = color(p.Color),
				material = enumName(p.Material), reflectance = p.Reflectance or 0 })
		elseif p.Name == "Head" and p.Parent == model and p:FindFirstChildOfClass("SpecialMesh") then
			local decal = p:FindFirstChild("face")
			scene.head = { cf = cfList(p.CFrame), size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = color(p.Color),
				material = enumName(p.Material), reflectance = p.Reflectance or 0, classic = Kit.CLASSIC,
				decal = decal and { texture = decal.Texture, file = FACE_FILES[decal.Texture], face = enumName(decal.Face) } or nil }
		elseif cls ~= "MeshPart" then
			local shape = cls == "WedgePart" and "Wedge" or "Block"
			local sm = p:FindFirstChildOfClass("SpecialMesh")
			local size = p.Size
			if sm then
				local mt = enumName(sm.MeshType)
				shape = mt == "Sphere" and "Ellipsoid" or mt
				-- FaceFX writes SpecialMesh.Scale (lids closing, the mouth opening, pupils): the drawn size
				local k = sm.Scale or Vector3.new(1, 1, 1)
				size = Vector3.new(size.X * k.X, size.Y * k.Y, size.Z * k.Z)
			elseif p.Shape then
				shape = enumName(p.Shape)
			end
			table.insert(scene.parts, { name = p.Name, folder = p.Parent and p.Parent.Name or "?", shape = shape, cf = cfList(p.CFrame),
				size = { r4(size.X), r4(size.Y), r4(size.Z) }, color = color(p.Color), material = enumName(p.Material),
				reflectance = p.Reflectance or 0, transparency = p.Transparency or 0 })
			counts.parts += 1
		end
	end
	if e.decalKey and scene.head and scene.head.decal then
		scene.head.decal.file = root .. "/tools/body/out/faces/" .. (faceFile[e.decalKey] or ("face_" .. e.decalKey .. ".png"))
		scene.head.decal.key = e.decalKey
	end
	Host.WriteJSON(OUT .. "/" .. e.id .. ".json", scene)
	table.insert(index.looks, { id = e.id, file = e.id .. ".json", label = scene.label, look = L.id, state = e.state, counts = counts })
	local ff = look and look:FindFirstChild("Face")
	counts.extra = ff and ff:GetAttribute("Extra")
	local bf = look and look:FindFirstChild("Beard")
	counts.beardExtra = bf and bf:GetAttribute("Extra")
	table.insert(report, string.format("%-24s face parts %3d (Extra %s)  rig joints %2d  drawn parts %3d  head %s", e.id, counts.face, tostring(counts.extra), counts.rig, counts.parts,
		scene.head and string.format("%.3f", scene.head.size[1]) or "?"))
	if robeReport then
		table.insert(report, "    " .. robeReport)
	end
	model:Destroy()
	currentModel = nil
end
Host.WriteJSON(OUT .. "/index.json", index, true)
for _, l in ipairs(report) do
	print(l)
end
print("scene:", OUT)
