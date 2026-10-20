--!nocheck
-- tools/sim/test_referee.luau: the ring officials as the server builds them (Officials.Look -> Builder.Cosmetics on the
-- fake R15 rig of test_gear.luau, the real GearAssetData):
--   * Officials.Look: the referee / the spar coach (outfit, bare hands, medium detail, a drawn neutral / stern face),
--     Officials.Colors (the venue's light-blue shirt, white for a title fight, the coach's team colour)
--   * the referee wears his outfit pieces (every piece of GearAssetData's official.Referee set: shirt, collar, placket,
--     buttons, pocket, badge, bow tie, sleeves, belt and buckle, trousers, dress shoes), each a MeshPart welded to its
--     body part, painted from the colours; NO boxing gear anywhere (no gloves, wraps, trunks, boots, mouthguard); one
--     face decal on the head; the same at every muscle tier, on mixed tiers and on the lite detail set
--   * the coach: the Coach set (polo, towel), no bow tie / badge
--   * the headgear follows Config.HeadgearOfficials; ids 0 -> the part-built outfit, still no boxing gear
--   * FightEngine builds its referee through Officials.Look
--   lune run tools/sim/test_referee.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, Color3, Enum = roblox.Vector3, roblox.Color3, roblox.Enum

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end
local function cnear(a, b, tol)
	return a and b and math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) <= (tol or 0.01)
end

local E = FE.new()
local H = Host.new({ globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
local root = Host.FindRoot()
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderGear = H.require("BuilderGear")
local Builder = H.require("Builder")
local Looks = H.require("Looks")
local Config = H.require("Config")
local Officials = H.require("Officials")
local REAL = BodyTiers.Data()
local GEAR = BuilderGear.Data()

------------------------------------------------------------------------
-- the fake rig (test_bodytiers.luau's, engine mode, with a head)
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

local function newRig(scale)
	local model = E.new("Model")
	model.Name = "Boxer"
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1) * scale
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
		return true
	end
	model.Parent = E.workspace
	return model, hum
end

-- a fake AssetService: CreateMeshPartAsync -> a MeshPart remembering its id, or an error for the ids in failIds
local function fakeAssets(failIds)
	local AS = { calls = 0, ids = {} }
	function AS.CreateMeshPartAsync(_, content)
		AS.calls += 1
		local id = tonumber(tostring(content):match("(%d+)%s*$"))
		AS.ids[id] = (AS.ids[id] or 0) + 1
		if failIds and (failIds == true or failIds[id]) then
			error("HTTP 403 (Forbidden)")
		end
		local mp = E.new("MeshPart")
		mp.MeshId = "rbxassetid://" .. tostring(id)
		return mp
	end
	return AS
end
local Content = { fromUri = function(u)
	return u
end }

local function setup(gearData, failGear, bodyData)
	BodyTiers.SetData(bodyData or REAL)
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
	BuilderGear.SetData(gearData or GEAR)
	BuilderGear.Reset()
	local AS = fakeAssets(failGear)
	BuilderGear.Services = { AssetService = AS, Content = Content }
	return AS
end

-- a fake AssetService: CreateMeshPartAsync -> a MeshPart remembering its id
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
local function setup(gearData)
	BodyTiers.SetData(REAL)
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
	BuilderGear.SetData(gearData or GEAR)
	BuilderGear.Reset()
	BuilderGear.Services = { AssetService = fakeAssets(), Content = Content }
end

local function buildOf(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end
local function buildFor(app, tier)
	for v = 0, 100 do
		if BodyTiers.Key(Builder.Tiers(app, buildOf(v))) == string.rep(tostring(tier), 14) then
			return buildOf(v + (tier > 1 and 2 or 0))
		end
	end
	error("no build gives tier " .. tier)
end

local function official(kind, o, tier, detail)
	local app, b, gear, opts = Officials.Look(o and o.seed or 7, kind, o)
	if tier then
		b = buildFor(app, tier)
	end
	if detail then
		opts.detail = detail
	end
	local sc = Builder.Scales(app, b, opts)
	local model = newRig(Vector3.new(sc.width, sc.height, sc.depth))
	local ok, err = pcall(Builder.Cosmetics, model, app, b, gear, opts)
	check(kind .. ": Cosmetics runs", ok, err)
	return model, app, opts
end

-- every visible worn piece: { name = part }, and the boxing gear found anywhere on the model
local BOXING = { "Glove", "Wrap", "Trunk", "Waistband", "Boot", "ShoeLaces", "ShoeCollar", "AnkleSock", "Mouthguard", "Cuff", "Knuckle" }
local function worn(model)
	local out, boxing = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if (d.ClassName == "MeshPart" or d.ClassName == "Part") and d.Parent and d.Parent.ClassName == "Folder" then
			local piece = d:GetAttribute("GearPiece") or d.Name
			out[piece] = d
			local grp = d:GetAttribute("GearPiece") and GEAR.pieces[piece] and GEAR.pieces[piece].group
			if grp and grp ~= "official" then
				table.insert(boxing, piece)
			elseif not grp and d.Parent.Name ~= "Headgear" then
				for _, k in ipairs(BOXING) do
					if d.Name:find(k, 1, true) then
						table.insert(boxing, d.Parent.Name .. "/" .. d.Name)
					end
				end
			end
		end
	end
	return out, boxing
end
local function faceDecals(model)
	local head = model:FindFirstChild("Head")
	local n = 0
	for _, d in ipairs(head and head:GetDescendants() or {}) do
		if d.ClassName == "Decal" then
			n += 1
		end
	end
	return n
end
local function welded(p)
	for _, w in ipairs(p:GetChildren()) do
		if w.ClassName == "Weld" and w.Part1 == p and w.Part0 and w.Part0.Parent then
			return w.Part0
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Officials.Look / Colors
------------------------------------------------------------------------
do
	local app, _, gear, opts = Officials.Look(11, "referee", { venue = "ClubArena" })
	check("Look: referee outfit, bare hands, medium detail", opts.outfit == "referee" and opts.hands == "bare" and opts.detail == "medium"
		and type(gear) == "table")
	local faces = {}
	for s = 1, 40 do
		local a = Officials.Look(s, "referee", {})
		faces[a.face.style] = true
		check("Look: the referee's face is neutral or stern (seed " .. s .. ")", a.face.style == "wcb_neutral" or a.face.style == "wcb_stern", a.face.style)
	end
	check("Look: both faces turn up", faces.wcb_neutral and faces.wcb_stern)
	check("Look: a drawn face style", BodyTiers.IsDrawnStyle(app.face.style))
	local club = Officials.Colors("referee", { venue = "ClubArena" })
	local title = Officials.Colors("referee", { venue = "ClubArena", kind = "World Title" })
	local stadium = Officials.Colors("referee", { venue = "Stadium" })
	check("Colors: a light-blue shirt at a club", club.shirt[3] > club.shirt[1] + 40 and club.shirt[3] > 200)
	check("Colors: white for a title fight / the stadium", title.shirt[1] > 240 and title.shirt[3] > 240 and stadium.shirt[1] > 240)
	check("Colors: black trousers, bow tie and shoes", club.trousers[1] < 40 and club.bowtie[1] < 40 and club.shoes[1] < 40)
	local coach = Officials.Colors("cornerman", { team = { 200, 20, 30 } })
	check("Colors: the coach in his team colour", coach.shirt[1] == 200 and coach.towel ~= nil)
	check("Look: deterministic per seed", Officials.Look(5, "referee", {}).skin == Officials.Look(5, "referee", {}).skin)
end

------------------------------------------------------------------------
-- the referee: his outfit, no boxing gear, one face decal
------------------------------------------------------------------------
local REF_SET = BuilderGear.SetPieces("official", "Referee")
local COACH_SET = BuilderGear.SetPieces("official", "Coach")
check("the official sets exist", REF_SET and #REF_SET >= 20 and COACH_SET and #COACH_SET >= 15, REF_SET and #REF_SET)
do
	setup()
	local model, _, opts = official("referee", { venue = "ClubArena", seed = 3 })
	local w, boxing = worn(model)
	local missing = {}
	for _, name in ipairs(REF_SET or {}) do
		local p = w[name]
		if not (p and p.ClassName == "MeshPart" and p:GetAttribute("GearMesh")) then
			table.insert(missing, name)
		end
	end
	check("referee: every outfit piece, as a mesh", #missing == 0, table.concat(missing, ","))
	check("referee: no boxing gear", #boxing == 0, table.concat(boxing, ","))
	check("referee: no towel / polo", w.OffTowel == nil and w.OffPolo == nil)
	check("referee: one face decal on the head", faceDecals(model) == 1, faceDecals(model))
	local bad = {}
	for _, name in ipairs(REF_SET or {}) do
		local p = w[name]
		local want = GEAR.pieces[name].part
		if p and (welded(p) == nil or welded(p).Name ~= want) then
			table.insert(bad, name)
		end
	end
	check("referee: each piece welded to its body part", #bad == 0, table.concat(bad, ","))
	local oc = opts.officialColors
	check("referee: the venue's shirt", w.OffShirt and cnear(w.OffShirt.Color, Color3.fromRGB(oc.shirt[1], oc.shirt[2], oc.shirt[3])))
	check("referee: black bow tie and trousers", w.OffBowTie and w.OffBowTie.Color.R < 0.15 and w.OffThigh_L and w.OffThigh_L.Color.R < 0.15)
	check("referee: leather belt, metal buckle", w.OffBelt and w.OffBelt.Material == Enum.Material.Leather and w.OffBuckle.Material == Enum.Material.Metal)
	local hands = model:FindFirstChild("BoxerLook") and model.BoxerLook:FindFirstChild("Hands")
	check("referee: bare hands (nothing on them)", hands == nil or #hands:GetChildren() == 0, hands and #hands:GetChildren())
	check("referee: the hands are shown", model.LeftHand.Transparency < 0.5 and model.RightHand.Transparency < 0.5)
	-- the headgear: Config.HeadgearOfficials (the user's "all characters have the boxing headgear on")
	local hg = model.BoxerLook:FindFirstChild("Headgear")
	check("referee: headgear as Config.HeadgearOfficials says", (hg ~= nil and #hg:GetChildren() > 0) == (Config.AlwaysHeadgear == true and Config.HeadgearOfficials ~= false))
	-- a title fight: white
	local m2 = official("referee", { kind = "World Title", seed = 3 })
	local w2 = worn(m2)
	check("title fight: a white shirt", w2.OffShirt and w2.OffShirt.Color.R > 0.94 and w2.OffShirt.Color.B > 0.94)
	-- the flag off: no headgear on officials
	local was = Config.HeadgearOfficials
	Config.HeadgearOfficials = false
	local m3 = official("referee", { seed = 3 })
	local hg3 = m3.BoxerLook:FindFirstChild("Headgear")
	check("HeadgearOfficials = false: no headgear on the referee", hg3 == nil or #hg3:GetChildren() == 0)
	Config.HeadgearOfficials = was
end

------------------------------------------------------------------------
-- every tier, mixed tiers, the lite set
------------------------------------------------------------------------
do
	setup()
	for tier = 1, 5 do
		local model = official("referee", { seed = 3 }, tier)
		local w, boxing = worn(model)
		local n = 0
		for _, name in ipairs(REF_SET) do
			if w[name] and w[name]:GetAttribute("GearMesh") then
				n += 1
			end
		end
		check("tier " .. tier .. ": the whole outfit", n == #REF_SET, n)
		check("tier " .. tier .. ": no boxing gear", #boxing == 0, table.concat(boxing, ","))
		check("tier " .. tier .. ": the tier's own shirt", w.OffShirt and tonumber(GEAR.tiers[tier].OffShirt.mesh) == w.OffShirt:GetAttribute("GearMesh"))
		check("tier " .. tier .. ": one face decal", faceDecals(model) == 1, faceDecals(model))
	end
	-- random officials (mixed tiers)
	for s = 20, 26 do
		local model = official("referee", { seed = s })
		local w, boxing = worn(model)
		check("seed " .. s .. ": outfit + no boxing gear", w.OffShirt and w.OffShoe_R and w.OffWaist and #boxing == 0, table.concat(boxing, ","))
	end
	local lite = official("referee", { seed = 3 }, 3, "low")
	local w = worn(lite)
	local liteId = GEAR.tiers[3].OffShirt.lite and GEAR.tiers[3].OffShirt.lite.mesh
	check("low detail: the lite shirt", liteId ~= nil and w.OffShirt and w.OffShirt:GetAttribute("GearMesh") == liteId)
end

------------------------------------------------------------------------
-- the spar coach
------------------------------------------------------------------------
do
	setup()
	local model = official("cornerman", { seed = 4 })
	local w, boxing = worn(model)
	local missing = {}
	for _, name in ipairs(COACH_SET) do
		if not (w[name] and w[name]:GetAttribute("GearMesh")) then
			table.insert(missing, name)
		end
	end
	check("coach: every piece of his set", #missing == 0, table.concat(missing, ","))
	check("coach: polo + towel, no bow tie / badge / belt", w.OffPolo and w.OffTowel and not w.OffBowTie and not w.OffBadge and not w.OffBelt)
	check("coach: no boxing gear", #boxing == 0, table.concat(boxing, ","))
	check("coach: one face decal", faceDecals(model) == 1)
end

------------------------------------------------------------------------
-- ids 0: the part-built outfit
------------------------------------------------------------------------
do
	local z = table.clone(GEAR)
	z.tiers = {}
	for i, t in ipairs(GEAR.tiers) do
		z.tiers[i] = {}
		for k, e in pairs(t) do
			local c = table.clone(e)
			c.mesh = 0
			c.lite = nil
			z.tiers[i][k] = c
		end
	end
	setup(z)
	local model = official("referee", { seed = 3 })
	local w, boxing = worn(model)
	check("ids 0: the part-built outfit (belt, bow tie)", w.Belt and w.BowTie and not w.OffShirt)
	check("ids 0: still no boxing gear", #boxing == 0, table.concat(boxing, ","))
	check("ids 0: one face decal", faceDecals(model) == 1)
end

------------------------------------------------------------------------
-- the server builds its referee through Officials
------------------------------------------------------------------------
do
	local fe = fs.readFile(root .. "/src/server/FightEngine.lua")
	check("FightEngine: the referee from Officials.Look", fe:find("Officials.Look(", 1, true) ~= nil)
end

BodyTiers.SetData(REAL)
BuilderGear.SetData(nil)
print(string.format("test_referee: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_referee failed")
end
