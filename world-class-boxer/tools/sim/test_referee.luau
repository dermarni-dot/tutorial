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
--   * no headgear on the officials (Config.HeadgearOfficials off): the referee's black peaked cap (band in the shirt
--     colour, gold WCB badge; welded, cached, cloned), the coach's team baseball cap; ids 0 -> the part-built outfit,
--     still no boxing gear
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
	-- no headgear on the officials (Config.HeadgearOfficials off): the referee's cap instead (Config.OfficialCaps)
	check("Config: officials wear no headgear, their caps instead", Config.HeadgearOfficials == false and Config.OfficialCaps == true)
	local hg = model.BoxerLook:FindFirstChild("Headgear")
	check("referee: no headgear", hg == nil or #hg:GetChildren() == 0)
	check("referee: no HeadgearColor / hidden-hair flag", model:GetAttribute("HeadgearColor") == nil and model:GetAttribute("HairHiddenHeadgear") == nil)
	local hat = model.BoxerLook:FindFirstChild("Hat")
	local Head = H.require("BuilderHead")
	local function hatParts(m)
		local f = m.BoxerLook:FindFirstChild("Hat")
		local out = {}
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				out[d.Name] = d
				out[#out + 1] = d
			end
		end
		return out
	end
	local hp = hatParts(model)
	check("referee: wears his cap (the medium set)", hat ~= nil and hat:GetAttribute("Style") == "referee" and #hp == Head.CAP_PARTS.referee.medium, #hp)
	check("referee: crown, band, visor, WCB badge", hp.RCCrown and hp.RCBand and hp.RCVisor and hp.RCBadge and hp.RCBadgeText)
	check("referee: a black cap", hp.RCCrown and hp.RCCrown.Color.R < 0.12 and hp.RCCrown.Color.B < 0.12)
	check("referee: the band in the club's blue shirt colour", hp.RCBand and cnear(hp.RCBand.Color, Color3.fromRGB(oc.shirt[1], oc.shirt[2], oc.shirt[3])))
	check("referee: the gold badge", hp.RCBadge and hp.RCBadge.Color.R > 0.7 and hp.RCBadge.Color.B < 0.4)
	local txt = hp.RCBadgeText and hp.RCBadgeText:FindFirstChildOfClass("SurfaceGui")
	local lbl = txt and txt:FindFirstChildOfClass("TextLabel")
	check("referee: the badge reads WCB", lbl ~= nil and lbl.Text == "WCB")
	local badW = {}
	for _, p in ipairs(hp) do
		local w = p:FindFirstChildOfClass("WeldConstraint")
		if not (w and w.Part0 == model.Head and w.Part1 == p) then
			table.insert(badW, p.Name)
		end
	end
	check("referee: every cap part welded to his head", #badW == 0, table.concat(badW, ","))
	check("referee: cap parts massless, no collisions", hp.RCCrown and hp.RCCrown.Massless and not hp.RCCrown.CanCollide)
	-- a rebuild with nothing changed keeps the same parts (cache); a new head (respawn / head swap) rebuilds it on that head
	local crown = hp.RCCrown
	local app0, b0, gear0, opts0 = Officials.Look(3, "referee", { venue = "ClubArena" })
	pcall(Builder.Cosmetics, model, app0, b0, gear0, opts0)
	check("referee: an unchanged rebuild keeps the cap", hatParts(model).RCCrown == crown)
	local c = model:Clone()
	c.Parent = E.workspace
	local cp = hatParts(c)
	local cw = cp.RCCrown and cp.RCCrown:FindFirstChildOfClass("WeldConstraint")
	check("referee: a clone carries the cap, welded to the clone's head", #cp == #hp and cw and cw.Part0 == c:FindFirstChild("Head"))
	c:Destroy()
	-- a title fight: white
	local m2 = official("referee", { kind = "World Title", seed = 3 })
	local w2 = worn(m2)
	check("title fight: a white shirt", w2.OffShirt and w2.OffShirt.Color.R > 0.94 and w2.OffShirt.Color.B > 0.94)
	local hp2 = hatParts(m2)
	check("title fight: the black cap with a white band", hp2.RCCrown and hp2.RCCrown.Color.R < 0.12 and hp2.RCBand and hp2.RCBand.Color.R > 0.94)
	-- the headgear flag back on: headgear, no cap (never both)
	local was = Config.HeadgearOfficials
	Config.HeadgearOfficials = true
	local m3 = official("referee", { seed = 3 })
	local hg3 = m3.BoxerLook:FindFirstChild("Headgear")
	check("HeadgearOfficials = true: headgear, no cap", hg3 ~= nil and #hg3:GetChildren() > 0 and #hatParts(m3) == 0)
	Config.HeadgearOfficials = was
	local wasC = Config.OfficialCaps
	Config.OfficialCaps = false
	local m4 = official("referee", { seed = 3 })
	check("OfficialCaps = false: bare-headed", #hatParts(m4) == 0 and (m4.BoxerLook:FindFirstChild("Headgear") == nil or #m4.BoxerLook.Headgear:GetChildren() == 0))
	Config.OfficialCaps = wasC
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
	local look = model:FindFirstChild("BoxerLook")
	local hg = look and look:FindFirstChild("Headgear")
	check("coach: no headgear", hg == nil or #hg:GetChildren() == 0)
	local hat = look and look:FindFirstChild("Hat")
	local n, crown, bill = 0, hat and hat:FindFirstChild("BCCrown"), hat and hat:FindFirstChild("BCBill")
	for _, d in ipairs(hat and hat:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	local _, _, _, copts = Officials.Look(4, "cornerman", {})
	local team = copts.officialColors.shirt
	check("coach: a team baseball cap (the medium set)", hat and hat:GetAttribute("Style") == "baseball" and n == H.require("BuilderHead").CAP_PARTS.baseball.medium, n)
	check("coach: the cap in his team colour, a darker bill", crown and cnear(crown.Color, Color3.fromRGB(team[1], team[2], team[3])) and bill
		and bill.Color.R <= crown.Color.R + 1e-3)
end

------------------------------------------------------------------------
-- the caps and the headgear on the head, as the engine renders them
------------------------------------------------------------------------
-- The engine scales a Head SpecialMesh uniformly by the part's smallest axis (it stretches a Sphere mesh to the
-- part's Size, never the Head mesh): every Head-mesh part must be a cube. Each cap / headgear part's CFrame and Size
-- relative to the head (in head spans: y up from the head's centre, -z the face) is dumped and checked against the
-- intended geometry: the referee's crown centred above the head's top, the band round the head just above the brows
-- and inside the crown, the visor ahead of the forehead (-z) from under the band and pitched down, the badge proud of
-- the crown's front, every part welded to the head, massless, no collisions / queries, nothing visible below
-- Head.CAP_CLEAR in front of the face; the coach's dome and bill the same way; the headgear's pads (no Head mesh) round
-- an explicit face opening: nothing in front of the face below the brow line.
do
	setup()
	local Head = H.require("BuilderHead")
	local function geom(model, folderName)
		local head = model:FindFirstChild("Head")
		local hs = Head.HeadSpan(head)
		local f = model.BoxerLook:FindFirstChild(folderName)
		local out = {}
		for _, p in ipairs(f and f:GetDescendants() or {}) do
			if p:IsA("BasePart") then
				local rel = head.CFrame:ToObjectSpace(p.CFrame)
				local sm = p:FindFirstChildOfClass("SpecialMesh")
				local shape = sm and tostring(sm.MeshType):match("(%w+)$") or (p.Shape and tostring(p.Shape):match("(%w+)$")) or "Block"
				local g = { part = p, name = p.Name, pos = rel.Position / hs, cf = rel, size = p.Size / hs, shape = shape }
				out[p.Name] = g
				out[#out + 1] = g
			end
		end
		return out, hs, head
	end
	local function dump(label, parts)
		print(label)
		for _, g in ipairs(parts) do
			local l = g.cf.LookVector
			print(string.format("  %-12s %-9s at (%6.3f %6.3f %6.3f)  size (%5.3f %5.3f %5.3f)  look (%5.2f %5.2f %5.2f)", g.name, g.shape,
				g.pos.X, g.pos.Y, g.pos.Z, g.size.X, g.size.Y, g.size.Z, l.X, l.Y, l.Z))
		end
	end
	local function flags(label, parts, head)
		local bad = {}
		for _, g in ipairs(parts) do
			local p = g.part
			local w = p:FindFirstChildOfClass("WeldConstraint")
			if not (w and w.Part0 == head and w.Part1 == p) then
				table.insert(bad, g.name .. ":weld")
			end
			if p.Massless ~= true then
				table.insert(bad, g.name .. ":massless")
			end
			if p.CanCollide ~= false or p.CanQuery ~= false or p.Anchored then
				table.insert(bad, g.name .. ":collide")
			end
			if g.shape == "Head" and (math.abs(g.size.X - g.size.Y) > 1e-6 or math.abs(g.size.X - g.size.Z) > 1e-6) then
				table.insert(bad, g.name .. ":Head mesh not a cube")
			end
		end
		check(label .. ": welded to the head, massless, no collisions, every Head mesh a cube", #bad == 0, table.concat(bad, ","))
	end
	-- the lowest visible point of the parts in front of the face (|x| < 0.3, outside the head), sampled over each
	-- part's shape (an ellipsoid, a drum, a box) in head spans
	local function lowest(parts, hs, head)
		local L = Head.FaceLayout(head, {})
		local worst, who = 10, nil
		for _, g in ipairs(parts) do
			if g.part.Transparency < 0.99 then
				local sz = g.part.Size
				for i = -5, 5 do
					for j = -5, 5 do
						for k = -5, 5 do
							local q = Vector3.new(i / 10, j / 10, k / 10)
							local inside = (g.shape == "Sphere" and q.Magnitude <= 0.5) or (g.shape == "Cylinder" and q.Y * q.Y + q.Z * q.Z <= 0.25)
								or (g.shape == "Block")
							if inside then
								local hp = head.CFrame:PointToObjectSpace(g.part.CFrame * Vector3.new(q.X * sz.X, q.Y * sz.Y, q.Z * sz.Z))
								if hp.Z < 0 and math.abs(hp.X) < 0.3 * hs and L.outside(hp) > 0.002 and hp.Y / hs < worst then
									worst, who = hp.Y / hs, g.name
								end
							end
						end
					end
				end
			end
		end
		return worst, who
	end

	-- the referee's cap (full: every part)
	local model = official("referee", { venue = "ClubArena", seed = 3 }, nil, "full")
	local parts, hs, head = geom(model, "Hat")
	dump("referee cap (full) relative to the head, in head spans (y up from its centre, -z the face):", parts)
	flags("cap", parts, head)
	local crown, band, visor, badge, text, cord = parts.RCCrown, parts.RCBand, parts.RCVisor, parts.RCBadge, parts.RCBadgeText, parts.RCCord
	check("cap: the full set", #parts == Head.CAP_PARTS.referee.full and crown and band and visor and badge and text and cord, #parts)
	check("cap: crown and band are drums (Cylinder parts stood on end), no Head mesh anywhere", crown.shape == "Cylinder" and band.shape == "Cylinder"
		and math.abs(crown.cf.RightVector.Y) > 0.999 and math.abs(band.cf.RightVector.Y) > 0.999 and crown.size.Y == crown.size.Z and band.size.Y == band.size.Z)
	local crownTop, crownBot = crown.pos.Y + crown.size.X / 2, crown.pos.Y - crown.size.X / 2
	check("cap: the crown's centre above the head's top, its flat top 0.1 .. 0.2 above it, a little wider than the head, centred",
		crown.pos.Y > 0.5 and crownTop > 0.6 and crownTop < 0.7 and crown.size.Y > 1.02 and crown.size.Y < 1.15
		and math.abs(crown.pos.X) < 1e-3 and math.abs(crown.pos.Z) < 1e-3, string.format("centre %.3f top %.3f dia %.3f", crown.pos.Y, crownTop, crown.size.Y))
	local bandTop, bandBot = band.pos.Y + band.size.X / 2, band.pos.Y - band.size.X / 2
	check("cap: the band round the head above the brows: its foot above CAP_CLEAR, its top inside the crown (no shared face), wider than the head (1.0 there), narrower than the crown",
		bandBot >= Head.CAP_CLEAR and bandBot < 0.3 and bandTop > crownBot + 0.005 and bandTop < crownBot + 0.03 and band.size.Y > 1.0 and band.size.Y < crown.size.Y,
		string.format("band %.3f .. %.3f dia %.3f, crown foot %.3f", bandBot, bandTop, band.size.Y, crownBot))
	-- the visor: an ellipsoid along its z; the tip = its centre + LookVector x half its length
	local function tipOf(g)
		return g.pos + g.cf.LookVector * (g.size.Z / 2)
	end
	local tip = tipOf(visor)
	check("cap: the visor is an ellipsoid reaching 0.15 .. 0.4 ahead of the forehead (-z) from under the band, below the crown, its tip pitched down and clear of the brows",
		visor.shape == "Sphere" and tip.Z < -0.65 and tip.Z > -0.9 and math.abs(tip.X) < 1e-3 and visor.pos.Y + visor.size.Y / 2 < bandTop
		and tip.Y < visor.pos.Y and tip.Y - visor.size.Y / 2 > Head.CAP_CLEAR - 0.012 and visor.cf.LookVector.Y < -0.02 and visor.cf.LookVector.Y > -0.15,
		string.format("tip (%.3f %.3f %.3f) root y %.3f look y %.3f", tip.X, tip.Y, tip.Z, visor.pos.Y, visor.cf.LookVector.Y))
	local sg = text.part:FindFirstChildOfClass("SurfaceGui")
	check("cap: the gold badge on the crown's front and proud of it, above the band, the WCB wordmark just in front of it facing the front",
		badge.shape == "Sphere" and badge.pos.Z < -crown.size.Y / 2 and badge.pos.Z - badge.size.Z / 2 < -crown.size.Y / 2 - 0.01 and badge.pos.Y > bandTop
		and badge.pos.Y + badge.size.Y / 2 < crownTop and text.pos.Z < badge.pos.Z - badge.size.Z / 2 and text.pos.Z > badge.pos.Z - badge.size.Z / 2 - 0.03
		and text.cf.LookVector.Z < -0.99 and sg and sg.Face == Enum.NormalId.Front and text.size.X <= badge.size.X and text.size.Y <= badge.size.Y,
		string.format("badge z %.3f (crown front %.3f) y %.3f, text z %.3f", badge.pos.Z, -crown.size.Y / 2, badge.pos.Y, text.pos.Z))
	check("cap: the gold cord across the band's front", cord.pos.Z < -0.4 and cord.pos.Y > bandBot and cord.pos.Y < bandTop and cord.size.X > 0.6)
	local lowY, lowWho = lowest(parts, hs, head)
	check("cap: nothing visible below Head.CAP_CLEAR in front of the face", lowY >= Head.CAP_CLEAR - 0.012, string.format("%s at y %.3f", tostring(lowWho), lowY))
	-- medium (the officials' detail) and low
	local mp = geom(official("referee", { venue = "ClubArena", seed = 3 }), "Hat")
	check("cap: medium: crown, band, visor, badge and wordmark (no cord)", #mp == Head.CAP_PARTS.referee.medium and mp.RCCrown and mp.RCBand and mp.RCVisor and mp.RCBadge and mp.RCBadgeText and not mp.RCCord, #mp)
	local lp = geom(official("referee", { venue = "ClubArena", seed = 3 }, nil, "low"), "Hat")
	check("cap: low: crown and visor, the crown coming down to the band's foot", #lp == 2 and lp.RCCrown and lp.RCVisor
		and math.abs((lp.RCCrown.pos.Y - lp.RCCrown.size.X / 2) - bandBot) < 1e-3, lp.RCCrown and (lp.RCCrown.pos.Y - lp.RCCrown.size.X / 2))

	-- the coach's ball cap (full)
	local coach = official("cornerman", { seed = 4 }, nil, "full")
	local cp, chs, chead = geom(coach, "Hat")
	dump("coach's ball cap (full) relative to the head:", cp)
	flags("ball cap", cp, chead)
	local dome, bill, logo, button = cp.BCCrown, cp.BCBill, cp.BCLogo, cp.BCButton
	check("ball cap: the full set", #cp == Head.CAP_PARTS.baseball.full and dome and bill and logo and button and cp.BCSeam, #cp)
	check("ball cap: the dome an ellipsoid (a Sphere mesh, which the engine stretches) over the head's top, wider than the head, centred",
		dome.shape == "Sphere" and dome.pos.Y + dome.size.Y / 2 > 0.55 and dome.pos.Y + dome.size.Y / 2 < 0.7 and dome.size.X > 1.0 and dome.size.Z > 1.0
		and dome.pos.Y > 0.25 and math.abs(dome.pos.X) < 1e-3)
	local btip = tipOf(bill)
	check("ball cap: the bill ahead of the forehead under the dome, pitched down, clear of the brows", bill.shape == "Sphere" and btip.Z < -0.75 and btip.Z > -1.0
		and bill.pos.Y < dome.pos.Y and btip.Y - bill.size.Y / 2 > Head.CAP_CLEAR - 0.012 and bill.cf.LookVector.Y < -0.02,
		string.format("tip (%.3f %.3f %.3f)", btip.X, btip.Y, btip.Z))
	check("ball cap: the WCB on the dome's front facing forward, the button on top", logo.pos.Z < -0.45 and logo.cf.LookVector.Z < -0.9 and logo.pos.Y > 0.3
		and button.pos.Y > dome.pos.Y + dome.size.Y / 2 - 0.06 and math.abs(button.pos.X) < 1e-3)
	local clowY, clowWho = lowest(cp, chs, chead)
	check("ball cap: nothing visible below Head.CAP_CLEAR in front of the face", clowY >= Head.CAP_CLEAR - 0.012, string.format("%s at y %.3f", tostring(clowWho), clowY))

	-- a boxer's headgear (full): the pads as the engine draws them
	local bm = newRig(Vector3.new(1, 1, 1))
	local bapp = Looks.Defaults(1)
	local okB, errB = pcall(Builder.Cosmetics, bm, bapp, buildOf(40), nil, { hands = "gloves", detail = "full" })
	check("headgear: a boxer builds (Config.AlwaysHeadgear)", okB and Config.AlwaysHeadgear == true, errB)
	local hg, _, bhead = geom(bm, "Headgear")
	dump("boxer's headgear (full) relative to the head:", hg)
	flags("headgear", hg, bhead)
	-- the pads (Head.HG, in head spans): no Head mesh anywhere (flags above), the brow roll a flat ring whose rim meets
	-- the forehead above HEADGEAR_OPENING.top, the crown cap over the head's top and flush with the forehead, the
	-- back shell (HGShell, the part Diag measures) behind the ears, the cheek rolls outside the eyes and never across
	-- the face, the ear pads flush on the side walls, the straps meeting under the chin
	local O = Head.HEADGEAR_OPENING
	local names = {}
	for _, g in ipairs(hg) do
		names[g.name] = (names[g.name] or 0) + 1
	end
	check("headgear: the full set: brow roll, crown cap, back shell, 2 cheek rolls, 2 ear pads, 2 ear holes, 2 straps; no Head mesh",
		#hg == Head.HEADGEAR_PARTS.full and names.HGBrow == 1 and names.HGTop == 1 and names.HGShell == 1 and names.HGCheek == 2 and names.HGSide == 2
		and names.HGEarHole == 2 and names.HGStrap == 2, #hg)
	local anyHeadMesh = false
	for _, g in ipairs(hg) do
		if g.shape == "Head" then
			anyHeadMesh = true
		end
	end
	check("headgear: no part carries the Head mesh", not anyHeadMesh)
	local br, top, back = hg.HGBrow, hg.HGTop, hg.HGShell
	-- the brow roll's rim on the forehead (z = -0.5): y = cy - hy sqrt(1 - ((0.5 + cz) / hz)^2)
	local rim = br and (br.pos.Y - br.size.Y / 2 * math.sqrt(math.max(1 - ((-0.5 - br.pos.Z) / (br.size.Z / 2)) ^ 2, 0)))
	check("headgear: the brow roll is a flat ring, 0.05 .. 0.12 proud of the forehead, its rim 0.03 .. 0.08 above HEADGEAR_OPENING.top",
		br and br.shape == "Sphere" and br.size.X > 1.1 and br.size.Y < 0.25 and -(br.pos.Z - br.size.Z / 2) - 0.5 > 0.05 and -(br.pos.Z - br.size.Z / 2) - 0.5 < 0.12
		and rim and rim > O.top + 0.03 and rim < O.top + 0.08, br and string.format("front %.3f rim %.3f", -(br.pos.Z - br.size.Z / 2), rim))
	check("headgear: the crown cap over the top (0.08 .. 0.15 above it), 0.03 .. 0.1 off the sides, its front flush with the forehead or behind it",
		top and top.shape == "Sphere" and top.pos.Y + top.size.Y / 2 > 0.58 and top.pos.Y + top.size.Y / 2 < 0.65 and top.size.X / 2 > 0.53 and top.size.X / 2 < 0.6
		and top.pos.Z - top.size.Z / 2 >= -0.5 - 1e-3, top and string.format("top %.3f half-width %.3f front %.3f", top.pos.Y + top.size.Y / 2, top.size.X / 2, top.pos.Z - top.size.Z / 2))
	check("headgear: the back shell behind the ears (front edge z > -0.3), 0.08 .. 0.2 proud of the back, over the sides",
		back and back.shape == "Sphere" and back.pos.Z - back.size.Z / 2 > -0.3 and back.pos.Z + back.size.Z / 2 > 0.58 and back.pos.Z + back.size.Z / 2 < 0.7
		and back.size.X / 2 > 0.55, back and string.format("front %.3f back %.3f", back.pos.Z - back.size.Z / 2, back.pos.Z + back.size.Z / 2))
	for _, g in ipairs(hg) do
		if g.name == "HGCheek" then
			check("headgear: a cheek roll upright beside the face, outside the eyes (|x| >= 0.36), never across it (z >= -0.32), from the brow roll to under the jaw",
				g.shape == "Sphere" and math.abs(g.pos.X) - g.size.X / 2 >= 0.36 and g.pos.Z - g.size.Z / 2 >= -0.32 and g.pos.Y + g.size.Y / 2 > 0.24 and g.pos.Y - g.size.Y / 2 < -0.3,
				string.format("x %.3f z %.3f y %.3f..%.3f", math.abs(g.pos.X) - g.size.X / 2, g.pos.Z - g.size.Z / 2, g.pos.Y - g.size.Y / 2, g.pos.Y + g.size.Y / 2))
		elseif g.name == "HGSide" then
			check("headgear: an ear pad flush on the side wall (sunk 0.03 .. 0.1, 0.05 .. 0.15 proud), round the ear",
				g.shape == "Sphere" and math.abs(g.pos.X) - g.size.X / 2 > 0.4 and math.abs(g.pos.X) - g.size.X / 2 < 0.47 and math.abs(g.pos.X) + g.size.X / 2 > 0.55
				and math.abs(g.pos.X) + g.size.X / 2 < 0.65 and math.abs(g.pos.Y) < 0.1 and math.abs(g.pos.Z) < 0.1,
				string.format("x %.3f..%.3f", math.abs(g.pos.X) - g.size.X / 2, math.abs(g.pos.X) + g.size.X / 2))
		elseif g.name == "HGEarHole" then
			check("headgear: an ear hole on the ear pad's outer face, dark", math.abs(g.pos.X) > 0.57 and g.part.Color.R < back.part.Color.R + 1e-3 and g.size.Y > 0.1)
		elseif g.name == "HGStrap" then
			local tip = g.pos + g.cf.LookVector * (g.size.Z / 2)
			local tail = g.pos - g.cf.LookVector * (g.size.Z / 2)
			check("headgear: a chin strap from under the ear pad to under the chin (|x| < 0.1, y < -0.5)", g.shape == "Block" and math.abs(tip.X) < 0.1 and tip.Y < -0.5
				and math.abs(tail.X) > 0.45 and tail.Y < -0.2, string.format("tip (%.2f %.2f %.2f) tail (%.2f %.2f %.2f)", tip.X, tip.Y, tip.Z, tail.X, tail.Y, tail.Z))
		end
	end
	-- nothing visible in front of the face: every part's volume sampled (as lowest() above) for points in front of
	-- the head (z < -0.35) with |x| < 0.36 between the chin and the brow line
	local function frontHits(parts, hs, head)
		local L = Head.FaceLayout(head, {})
		local hits = {}
		for _, g in ipairs(parts) do
			local sz = g.part.Size
			for i = -5, 5 do
				for j = -5, 5 do
					for k = -5, 5 do
						local q = Vector3.new(i / 10, j / 10, k / 10)
						local inside = (g.shape == "Sphere" and q.Magnitude <= 0.5) or (g.shape == "Cylinder" and q.Y * q.Y + q.Z * q.Z <= 0.25) or (g.shape == "Block")
						if inside then
							local hp = head.CFrame:PointToObjectSpace(g.part.CFrame * Vector3.new(q.X * sz.X, q.Y * sz.Y, q.Z * sz.Z)) / hs
							if hp.Z < -0.35 and math.abs(hp.X) < 0.36 and hp.Y > -0.45 and hp.Y < O.top and L.outside(hp * hs) > 0.002 then
								hits[g.name] = true
							end
						end
					end
				end
			end
		end
		local out = {}
		for n in pairs(hits) do
			out[#out + 1] = n
		end
		return out
	end
	local fh = frontHits(hg, _, bhead)
	check("headgear (full): nothing in front of the face below the brow line", #fh == 0, table.concat(fh, ","))
	for _, det in ipairs({ "medium", "low" }) do
		local dm = newRig(Vector3.new(1, 1, 1))
		pcall(Builder.Cosmetics, dm, Looks.Defaults(1), buildOf(40), nil, { hands = "gloves", detail = det })
		local dg, dhs, dhead = geom(dm, "Headgear")
		flags("headgear " .. det, dg, dhead)
		local hm = false
		for _, g in ipairs(dg) do
			if g.shape == "Head" then
				hm = true
			end
		end
		local dfh = frontHits(dg, dhs, dhead)
		check("headgear (" .. det .. "): the set, no Head mesh, nothing in front of the face", #dg == Head.HEADGEAR_PARTS[det] and not hm and #dfh == 0 and dg.HGBrow and dg.HGTop and dg.HGShell,
			#dg .. " " .. table.concat(dfh, ","))
		dm:Destroy()
	end
	for _, m in ipairs({ model, coach, bm }) do
		m:Destroy()
	end
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
