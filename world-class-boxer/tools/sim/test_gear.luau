--!nocheck
-- tools/sim/test_gear.luau: the Blender-modelled boxing gear (BuilderGear, GearAssetData) under lune.
--   * the manifest: every tier carries every piece (mesh id, offset, size), the sets name real pieces, sided pieces
--     come in pairs, colour slots are known, the shared meshes (glove, wrap, boot foot) are one id at every tier
--   * BuilderGear.Entry / SetPieces / Resolve: the piece for the tier each body part shows (mixed tiers), styles
--     (Classic / Striped / Pro / Long, High-Top / Low-Top), templates loaded once per id
--   * Builder.Cosmetics on a fake R15 rig (fakeengine, the engine-mode ReplaceBodyPartR15, a fake AssetService):
--     every piece a MeshPart sized template x the body part's scale ratio, welded at offset x ratio, painted from
--     the look (trunks / trim / gloves / strap / shoes / soles / laces / socks / top), gloves named GloveL / GloveR and
--     the hands hidden, wraps with the hands shown, the women's top over a skin torso, officials in their outfits,
--     a tier change swapping the pieces, the rebuild cache, sweat on the mesh gloves
--   * fallback: ids 0, failed loads, default (non-tier) body parts -> the part-built gear (and the top colour)
--   lune run tools/sim/test_gear.luau [--gear PATH]   (default: src/shared/GearAssetData.lua)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end
local function vnear(a, b, tol)
	return (a - b).Magnitude <= (tol or 1e-4)
end
local function cnear(a, b, tol)
	return a and b and math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) <= (tol or 0.01)
end

local args = {}
do
	local a = process.args
	for i = 1, #a, 2 do
		args[(a[i]:gsub("^%-%-", ""))] = a[i + 1]
	end
end

local E = FE.new()
local H = Host.new({ globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
local root = Host.FindRoot()
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderGear = H.require("BuilderGear")
local Builder = H.require("Builder")
local BuilderBody = H.require("BuilderBody")
local Looks = H.require("Looks")
local REAL = BodyTiers.Data()
local GEAR
if args.gear then
	GEAR = luau.load(fs.readFile(args.gear), { debugName = args.gear })()
	BuilderGear.SetData(GEAR)
else
	GEAR = BuilderGear.Data()
end
print("gear manifest:", args.gear or "src/shared/GearAssetData.lua")

local function build(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end

------------------------------------------------------------------------
-- the manifest
------------------------------------------------------------------------
local SLOTS = { trunks = true, trim = true, gloves = true, gloveTrim = true, wraps = true, wraps2 = true, shoes = true, soles = true,
	laces = true, socks = true, top = true, topTrim = true }
do
	check("manifest: 5 tiers", type(GEAR.tiers) == "table" and #GEAR.tiers == 5, GEAR.tiers and #GEAR.tiers)
	local names = {}
	for name, p in pairs(GEAR.pieces or {}) do
		table.insert(names, name)
		check("piece " .. name .. ": slot known", SLOTS[p.slot] == true, p.slot)
		check("piece " .. name .. ": an R15 part", type(p.part) == "string" and table.find(BodyTiers.PARTS, p.part) ~= nil, p.part)
		local side = name:match("_([LR])$")
		if side then
			local twin = name:sub(1, -2) .. (side == "L" and "R" or "L")
			check("piece " .. name .. ": its twin", GEAR.pieces[twin] ~= nil)
			check("piece " .. name .. ": on its side", p.part:sub(1, #(side == "L" and "Left" or "Right")) == (side == "L" and "Left" or "Right"), p.part)
		end
	end
	check("manifest: 40 pieces", #names == 40, #names)
	local missing, zero = {}, 0
	for tier = 1, 5 do
		for _, name in ipairs(names) do
			local e = GEAR.tiers[tier] and GEAR.tiers[tier][name]
			if not (e and e.size and e.offset and e.size[1] > 0) then
				table.insert(missing, tier .. ":" .. name)
			elseif (e.mesh or 0) <= 0 then
				zero += 1
			end
		end
	end
	check("manifest: every piece at every tier", #missing == 0, table.concat(missing, ","))
	check("manifest: every mesh uploaded (id > 0)", zero == 0, zero .. " ids are 0")
	for group, styles in pairs(GEAR.sets or {}) do
		for style, list in pairs(styles) do
			for _, base in ipairs(list) do
				check("set " .. group .. "." .. style .. ": " .. base .. " exists", GEAR.pieces[base] ~= nil or GEAR.pieces[base .. "_R"] ~= nil)
			end
		end
	end
	for _, style in ipairs(Looks.TrunkStyles) do
		check("trunk style " .. style .. " has a set", BuilderGear.SetPieces("trunks", style) ~= nil)
	end
	for _, style in ipairs(Looks.ShoeStyles) do
		check("shoe style " .. style .. " has a set", BuilderGear.SetPieces("shoes", style) ~= nil)
	end
	-- shared meshes: one id at every tier; fitted ones differ per tier
	local g1, g5 = BuilderGear.Entry(1, "Glove_R"), BuilderGear.Entry(5, "Glove_R")
	check("glove: the same mesh at every tier", g1 and g5 and g1.id == g5.id)
	check("glove: same size, offset follows the tier's hand", g1 and g5 and vnear(g1.size, g5.size) and not vnear(g1.offset, g5.offset, 1e-5))
	local c1, c5 = BuilderGear.Entry(1, "GloveCuff_R"), BuilderGear.Entry(5, "GloveCuff_R")
	check("cuff: fitted per tier (tier 5 forearm is bigger)", c1 and c5 and c1.id ~= c5.id and c5.size.X > c1.size.X)
	local l1, l5 = BuilderGear.Entry(1, "TrunkLeg_R"), BuilderGear.Entry(5, "TrunkLeg_R")
	check("trunk leg: fitted per tier (tier 5 thigh is bigger)", l1 and l5 and l5.size.Z > l1.size.Z)
	local ll = BuilderGear.Entry(3, "TrunkLegLong_R")
	local ls = BuilderGear.Entry(3, "TrunkLeg_R")
	check("Long trunks: longer legs", ll and ls and ll.size.Y > ls.size.Y + 0.2)
	local bl, br = BuilderGear.Entry(3, "BootFoot_L"), BuilderGear.Entry(3, "BootFoot_R")
	check("left / right mirrored", bl and br and bl.id ~= br.id and vnear(bl.size, br.size) and math.abs(bl.offset.X + br.offset.X) < 1e-3)
	check("Entry: unknown -> nil", BuilderGear.Entry(3, "Nope") == nil and BuilderGear.Entry(9, "Glove_R") == nil)
	check("SetPieces expands the sides", (function()
		local l = BuilderGear.SetPieces("gloves", "Gloves")
		return #l == 6 and table.find(l, "Glove_L") and table.find(l, "GloveCuff_R")
	end)())
	-- the whole worn outfit per detail set (Config.Detail.meshes): the lite set (the low level's crowd NPCs) under 6k
	-- triangles at every tier, as the v9 gear was; the detailed set (full / medium) under 14k
	local worst, worstLite, liteAll = 0, 0, true
	for tier = 1, 5 do
		for _, outfit in ipairs({ { "Pro", "High-Top", "gloves", true }, { "Long", "Low-Top", "wraps", true } }) do
			local t, tl = 0, 0
			local function add(group, style)
				for _, name in ipairs(BuilderGear.SetPieces(group, style)) do
					local e = GEAR.tiers[tier][name]
					t += e.nt
					liteAll = liteAll and e.lite ~= nil
					tl += (e.lite and e.lite.nt) or e.nt
				end
			end
			add("trunks", outfit[1])
			add("shoes", outfit[2])
			add(outfit[3], outfit[3] == "gloves" and "Gloves" or "Wraps")
			add("top", "Top")
			worst = math.max(worst, t)
			worstLite = math.max(worstLite, tl)
		end
	end
	print(string.format("worst outfit: %d tris (detailed set), %d (lite set)", worst, worstLite))
	check("a whole outfit < 14000 tris (detailed set)", worst < 14000, worst)
	check("a whole outfit < 6000 tris (lite set)", worstLite < 6000, worstLite)
	check("every real piece has a lite entry", liteAll)
	-- the lite set: Entry(..., lite) takes the piece's lite mesh, the full one when it has none
	local gl, gf = BuilderGear.Entry(3, "Glove_R", nil, true), BuilderGear.Entry(3, "Glove_R")
	if GEAR.tiers[3].Glove_R.lite then
		check("Entry lite: the lite mesh", gl and gf and gl.lite == true and gl.id ~= gf.id and not gf.lite)
	end
	check("Entry lite without a lite mesh: the full one", (function()
		local d = { pieces = { X = { part = "RightHand", slot = "gloves", group = "gloves" } },
			tiers = { { X = { mesh = 5, offset = { 0, 0, 0 }, size = { 1, 1, 1 } } } } }
		local e = BuilderGear.Entry(1, "X", d, true)
		return e and e.id == 5 and not e.lite
	end)())
end

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

local SCALE = Vector3.new(0.92, 1.05, 0.94) -- (not the description's real scale: checks the ratio is the part's own)
local function dress(app, b, opts, scale, gear)
	local model = newRig(scale or SCALE)
	local ok, err = pcall(Builder.Cosmetics, model, app, b, gear, opts or { hands = "gloves" })
	check("Cosmetics runs", ok, err)
	return model
end
local function folder(model, name)
	local look = model:FindFirstChild("BoxerLook")
	return look and look:FindFirstChild(name)
end
local function meshes(f)
	local out = {}
	for _, p in ipairs(f and f:GetChildren() or {}) do
		if p.ClassName == "MeshPart" and p:GetAttribute("GearPiece") then
			out[p:GetAttribute("GearPiece")] = p
		end
	end
	return out
end
local function count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

------------------------------------------------------------------------
-- detail sets: a low-detail boxer (the crowd) wears the lite body and the lite gear fitted to it, the same pieces
------------------------------------------------------------------------
do
	setup()
	local app = Looks.Defaults(1)
	local lowM = dress(app, build(50), { hands = "gloves", detail = "low" })
	local fullM = dress(app, build(50), { hands = "gloves", detail = "full" })
	local ut = lowM:FindFirstChild("UpperTorso")
	check("low detail: the lite body", ut and ut:GetAttribute("BodyLite") == true)
	check("full detail: the detailed body", fullM:FindFirstChild("UpperTorso"):GetAttribute("BodyLite") == nil)
	local la, fa = meshes(folder(lowM, "Attire")), meshes(folder(fullM, "Attire"))
	local lh, fh = meshes(folder(lowM, "Hands")), meshes(folder(fullM, "Hands"))
	local same, liteIds = true, true
	for name, p in pairs(fa) do
		local q = la[name]
		same = same and q ~= nil
		local e = GEAR.tiers[3][name]
		if q and e and e.lite then
			liteIds = liteIds and q:GetAttribute("GearMesh") == e.lite.mesh and p:GetAttribute("GearMesh") == e.mesh
		end
	end
	check("low detail: the same pieces (instances) as full", same and count(la) == count(fa) and count(lh) == count(fh),
		count(la) .. "/" .. count(fa))
	check("low detail: the lite gear meshes, full the detailed", liteIds)
end

-- the placement contract for one built piece
local function placed(p, model)
	local name = p:GetAttribute("GearPiece")
	local info = GEAR.pieces[name]
	local body = model:FindFirstChild(info.part)
	-- (the band and the seat: the highest tier among their tierOf parts, the offset moved onto the part's own tier)
	local tier, _, own = BuilderGear.PieceTier(model, info)
	local e = tier and BuilderGear.Entry(tier, name)
	if not e then
		return false, name .. ": no entry"
	end
	if tier ~= own then
		local BT = H.require("BodyTiers")
		local pa = BT.PartEntry(own, info.part).attachments.RootRigAttachment
		local pb = BT.PartEntry(tier, info.part).attachments.RootRigAttachment
		e.offset += Vector3.new(pa[1] - pb[1], pa[2] - pb[2], pa[3] - pb[3])
	end
	local ratio = BuilderTiers.RatioOf(body)
	if p:GetAttribute("GearMesh") ~= e.id then
		return false, name .. ": mesh " .. tostring(p:GetAttribute("GearMesh")) .. " ~= " .. e.id
	end
	if not vnear(p.Size, e.size * ratio, 1e-4) then
		return false, name .. ": size " .. tostring(p.Size)
	end
	local w = p:FindFirstChild("GearWeld")
	if not (w and w.ClassName == "Weld" and w.Part0 == body and w.Part1 == p and vnear(w.C0.Position, e.offset * ratio, 1e-4)) then
		return false, name .. ": weld"
	end
	if not vnear(p.CFrame.Position, (body.CFrame * w.C0).Position, 1e-4) then
		return false, name .. ": cframe"
	end
	return true
end

------------------------------------------------------------------------
-- a man, tier 3, Pro trunks, high-tops, gloves
------------------------------------------------------------------------
do
	local AS = setup()
	local app = Looks.Defaults(1)
	app.attire.trunkStyle = "Pro"
	app.attire.shoeStyle = "High-Top"
	app.attire.trunks = { 20, 60, 200 }
	app.attire.trim = { 240, 200, 40 }
	app.attire.shoes = { 30, 30, 30 }
	app.attire.socks = { 250, 250, 250 }
	app.attire.laces = { 200, 10, 10 }
	app.gloves.color = { 200, 20, 20 }
	local GEARSET = { shoes = "Boots" }
	local model = dress(app, build(50), nil, nil, GEARSET)
	check("tier 3 body", model:GetAttribute("BodyTiers") == string.rep("3", 14), model:GetAttribute("BodyTiers"))
	local att, hands = meshes(folder(model, "Attire")), meshes(folder(model, "Hands"))
	local want = { "Waistband", "TrunkSeat", "TrunkLeg_L", "TrunkLeg_R", "TrunkStripe_L", "TrunkStripe_R", "TrunkHem_L", "TrunkHem_R",
		"BootFoot_L", "BootFoot_R", "Sole_L", "Sole_R", "ShoeLaces_L", "ShoeLaces_R", "BootShaft_L", "BootShaft_R", "BootLaces_L",
		"BootLaces_R", "BootSock_L", "BootSock_R" }
	local miss = {}
	for _, n in ipairs(want) do
		if not att[n] then
			table.insert(miss, n)
		end
	end
	check("Pro + High-Top: every piece", #miss == 0 and count(att) == #want, table.concat(miss, ",") .. " / " .. count(att))
	check("no part-built trunks / boots", (function()
		for _, p in ipairs(folder(model, "Attire"):GetChildren()) do
			-- (the lettering patches on the band / the leg are parts: v10's WCB mark on a band without text)
			if p.ClassName == "Part" and p.Name ~= "WaistText" and p.Name ~= "SponsorPatch" then
				return false
			end
		end
		return true
	end)())
	check("the WCB mark on a band without lettering (full detail)", folder(model, "Attire"):FindFirstChild("WaistText") ~= nil)
	check("no long legs, no top on a man", att.TrunkLegLong_R == nil and att.Top == nil)
	local bad = {}
	for _, p in pairs(att) do
		local ok, why = placed(p, model)
		if not ok then
			table.insert(bad, why)
		end
	end
	for _, p in pairs(hands) do
		local ok, why = placed(p, model)
		if not ok then
			table.insert(bad, why)
		end
	end
	check("placement: mesh of the part's tier, size x ratio, welded at offset x ratio", #bad == 0, table.concat(bad, "; "))
	check("ratio is the part's own (non-uniform)", vnear(BuilderTiers.RatioOf(model.LowerTorso), SCALE, 1e-3))
	-- colours
	local trunks, trim = Looks.Color(app.attire.trunks), Looks.Color(app.attire.trim)
	check("trunks colour: seat and legs", cnear(att.TrunkSeat.Color, trunks) and cnear(att.TrunkLeg_L.Color, trunks))
	check("trim colour: waistband, stripe, hem", cnear(att.Waistband.Color, trim) and cnear(att.TrunkStripe_R.Color, trim) and cnear(att.TrunkHem_L.Color, trim))
	check("shoes colour: foot and shaft", cnear(att.BootFoot_R.Color, Looks.Color(app.attire.shoes)) and cnear(att.BootShaft_L.Color, Looks.Color(app.attire.shoes)))
	check("laces colour", cnear(att.ShoeLaces_R.Color, Looks.Color(app.attire.laces)) and cnear(att.BootLaces_L.Color, Looks.Color(app.attire.laces)))
	check("socks colour", cnear(att.BootSock_R.Color, Looks.Color(app.attire.socks)))
	check("boxing boots: leather, rubber soles in the trim colour", att.BootShaft_R.Material == Enum.Material.Leather and cnear(att.Sole_L.Color, trim)
		and att.Sole_L.Material == Enum.Material.Rubber)
	-- gloves
	check("gloves: 6 pieces", count(hands) == 6, count(hands))
	local gl = folder(model, "Hands"):FindFirstChild("GloveL")
	local gr = folder(model, "Hands"):FindFirstChild("GloveR")
	check("gloves named GloveL / GloveR (the fight animation's contact spheres)", gl ~= nil and gr ~= nil and gl.ClassName == "MeshPart"
		and gl:GetAttribute("GearPiece") == "Glove_L")
	check("glove colour = the look's glove colour", cnear(gr.Color, Looks.Color(app.gloves.color), 0.02), tostring(gr.Color))
	check("cuff in the glove colour, strap in the strap colour", cnear(hands.GloveCuff_R.Color, gr.Color) and hands.GloveStrap_R:GetAttribute("GearSlot") == "gloveTrim")
	check("glove on the hand, cuff on the forearm", hands.Glove_R:FindFirstChild("GearWeld").Part0 == model.RightHand
		and hands.GloveCuff_R:FindFirstChild("GearWeld").Part0 == model.RightLowerArm)
	check("hands hidden inside the gloves", model.LeftHand.Transparency == 1 and model.RightHand.Transparency == 1)
	check("gloves wet-ready (sweat)", gr:GetAttribute("Wet") == "glove" and typeof(gr:GetAttribute("BaseColor")) == "Color3")
	-- templates: one load per distinct id; a second Cosmetics reloads nothing and rebuilds nothing
	local loads = AS.calls
	local distinct = 0
	for _, n in pairs(AS.ids) do
		distinct += 1
		check("one load per id", n == 1, n)
	end
	check("loads = distinct ids", loads == distinct and BuilderGear.Stats().loads == distinct, loads .. "/" .. distinct)
	local sig = folder(model, "Attire"):GetAttribute("Sig")
	local before = folder(model, "Attire")
	Builder.Cosmetics(model, app, build(50), GEARSET, { hands = "gloves" })
	check("same look again: no loads, the cached folder kept", AS.calls == loads and folder(model, "Attire") == before and folder(model, "Attire"):GetAttribute("Sig") == sig)
	-- sweat darkens the mesh gloves like the part-built ones
	local c0 = gr.Color
	Builder.SetSweat(model, app, 1)
	check("sweat darkens the gloves", gr.Color.R < c0.R - 0.01, tostring(gr.Color))
	Builder.SetSweat(model, app, 0)
	check("dry again", cnear(gr.Color, c0))
	-- wraps in the gym: the hands show, wrap pieces on the hands and wrists
	Builder.Cosmetics(model, app, build(50), nil, { hands = "wraps" })
	local w = meshes(folder(model, "Hands"))
	check("wraps: 4 pieces, no gloves", count(w) == 4 and w.Wrap_L and w.WrapWrist_R and folder(model, "Hands"):FindFirstChild("GloveL") == nil, count(w))
	check("wraps: hands shown", model.LeftHand.Transparency == 0 and model.RightHand.Transparency == 0)
	check("wraps colour", cnear(w.Wrap_R.Color, Looks.Color(app.attire.wraps)) and w.Wrap_R:GetAttribute("Wet") == "wrap")
	local ok, why = placed(w.WrapWrist_L, model)
	check("wraps placed", ok, why)
	Builder.Cosmetics(model, app, build(50), nil, { hands = "bare" })
	check("bare hands: nothing", count(meshes(folder(model, "Hands"))) == 0)
	-- a tier change: the legs train past the band -> the shorts legs and boot shafts swap to the new tier's meshes
	local b = build(50)
	b.quads, b.hamstrings, b.calves = 95, 95, 95
	Builder.Cosmetics(model, app, b, nil, { hands = "gloves" })
	att = meshes(folder(model, "Attire"))
	local ulTier = model.RightUpperLeg:GetAttribute("BodyTier")
	check("thighs now tier 5", ulTier == 5, ulTier)
	check("shorts legs swapped to tier 5", att.TrunkLeg_R and att.TrunkLeg_R:GetAttribute("GearMesh") == BuilderGear.Entry(5, "TrunkLeg_R").id)
	check("boot shaft follows the calf's tier", att.BootShaft_L and att.BootShaft_L:GetAttribute("GearMesh") == BuilderGear.Entry(model.LeftLowerLeg:GetAttribute("BodyTier"), "BootShaft_L").id)
	local lt = model.LowerTorso:GetAttribute("BodyTier")
	check("mixed tiers: the lower torso stays under tier 5", lt < 5, lt)
	check("waistband / seat follow the highest tier of the hips, chest and thighs (mixed tiers)",
		att.Waistband:GetAttribute("GearMesh") == BuilderGear.Entry(5, "Waistband").id
			and att.TrunkSeat:GetAttribute("GearMesh") == BuilderGear.Entry(5, "TrunkSeat").id, lt)
	bad = {}
	for _, p in pairs(att) do
		local okp, whyp = placed(p, model)
		if not okp then
			table.insert(bad, whyp)
		end
	end
	check("placement after the swap", #bad == 0 and count(att) == #want, table.concat(bad, "; "))
	check("welds on the live parts", att.TrunkLeg_R:FindFirstChild("GearWeld").Part0 == model.RightUpperLeg and model.RightUpperLeg.Parent == model)
end

------------------------------------------------------------------------
-- styles
------------------------------------------------------------------------
do
	setup()
	local function has(style, shoeStyle)
		local app = Looks.Defaults(1)
		app.attire.trunkStyle = style
		app.attire.shoeStyle = shoeStyle
		local model = dress(app, build(30))
		return meshes(folder(model, "Attire")), model
	end
	local a = has("Classic", "High-Top")
	check("Classic: band, seat, legs; no stripe / hem", a.Waistband and a.TrunkSeat and a.TrunkLeg_L and a.TrunkLeg_R and not a.TrunkStripe_R and not a.TrunkHem_R)
	a = has("Striped", "High-Top")
	check("Striped: the side stripes", a.TrunkStripe_L and a.TrunkStripe_R and not a.TrunkHem_L)
	a = has("Long", "Low-Top")
	check("Long: long legs + long hem, no short legs", a.TrunkLegLong_L and a.TrunkHemLong_R and not a.TrunkLeg_L)
	check("sneakers (the starter shoes): fabric uppers, foam soles", a.BootFoot_R.Material == Enum.Material.Fabric and a.Sole_R.Color.R > 0.9)
	check("Low-Top: collar + ankle sock, no shaft", a.ShoeCollar_R and a.AnkleSock_L and a.BootFoot_L and a.Sole_R and not a.BootShaft_R and not a.BootSock_R)
	local app = Looks.Defaults(1)
	app.attire.trunkStyle = nil
	local model = dress(app, build(30))
	check("no trunk style (old save) -> Classic", meshes(folder(model, "Attire")).TrunkLeg_R ~= nil and meshes(folder(model, "Attire")).TrunkStripe_R == nil)
	-- officials: their outfit, no trunks
	model = dress(Looks.Defaults(1), build(30), { hands = "gloves", outfit = "referee" })
	check("referee: no mesh gear, the outfit parts", count(meshes(folder(model, "Attire"))) == 0 and folder(model, "Attire"):FindFirstChild("Belt") ~= nil
		and count(meshes(folder(model, "Hands"))) == 0)
end

------------------------------------------------------------------------
-- women: the sports top over a skin torso
------------------------------------------------------------------------
do
	setup()
	local app = Looks.Defaults(2)
	app.attire.trim = { 10, 200, 90 }
	app.attire.trunks = { 90, 10, 160 }
	local model = dress(app, build(40), nil, Vector3.new(0.92 * 0.92, 66 / 70, 0.94 * 0.94))
	local a = meshes(folder(model, "Attire"))
	check("top + band", a.Top and a.TopBand, count(a))
	check("top in the trim colour, band in the trunks colour", a.Top and cnear(a.Top.Color, Looks.Color(app.attire.trim)) and cnear(a.TopBand.Color, Looks.Color(app.attire.trunks)))
	local skin = Looks.Color(Looks.SkinTones[app.skin])
	check("torso is skin under the mesh top", cnear(model.UpperTorso.Color, skin), tostring(model.UpperTorso.Color))
	local ok, why = placed(a.Top, model)
	check("top placed on the UpperTorso", ok, why)
end

------------------------------------------------------------------------
-- fallback: ids 0, failed loads, default parts
------------------------------------------------------------------------
local function zeroed(d)
	local out = table.clone(d)
	out.tiers = {}
	for i, t in ipairs(d.tiers) do
		out.tiers[i] = {}
		for k, e in pairs(t) do
			local c = table.clone(e)
			c.mesh = 0
			out.tiers[i][k] = c
		end
	end
	return out
end
do
	-- every id 0: nothing loaded, the part-built gear, the top as the torso colour
	local AS = setup(zeroed(GEAR))
	local app = Looks.Defaults(2)
	local model = dress(app, build(40))
	check("ids 0: no loads", AS.calls == 0, AS.calls)
	check("ids 0: part-built trunks", folder(model, "Attire"):FindFirstChild("TrunkShell") ~= nil and folder(model, "Attire"):FindFirstChild("Waistband").ClassName == "Part")
	check("ids 0: part-built gloves", folder(model, "Hands"):FindFirstChild("GloveR") ~= nil and folder(model, "Hands"):FindFirstChild("GloveR").ClassName == "Part"
		and folder(model, "Hands"):FindFirstChild("Cuff") ~= nil)
	check("ids 0: no mesh gear at all", count(meshes(folder(model, "Attire"))) + count(meshes(folder(model, "Hands"))) == 0)
	check("ids 0: the woman's torso is the top colour", cnear(model.UpperTorso.Color, Looks.Color(app.attire.trim)))
	check("Available: false", BuilderGear.Available(model, "top", "Top") == false)
end
do
	-- every gear load fails: the part-built gear, the failures cached (no retry storm), the top colour restored
	local AS = setup(nil, true)
	local app = Looks.Defaults(2)
	local model = dress(app, build(40))
	check("failed loads: part-built trunks / shoes / gloves", folder(model, "Attire"):FindFirstChild("TrunkShell") ~= nil
		and folder(model, "Attire"):FindFirstChild("Midsole") ~= nil and folder(model, "Hands"):FindFirstChild("Cuff") ~= nil)
	check("failed loads: counted", BuilderGear.Stats().failed > 0)
	check("failed loads: the woman keeps a top (torso in the top colour)", cnear(model.UpperTorso.Color, Looks.Color(app.attire.trim)), tostring(model.UpperTorso.Color))
	local calls = AS.calls
	Builder.Cosmetics(model, app, build(40), nil, { hands = "gloves" })
	check("failed loads: not retried within RETRY", AS.calls == calls, AS.calls - calls)
	check("Available after a failure: false", BuilderGear.Available(model, "top", "Top") == false)
	-- one failed id (a single shorts leg): the whole set falls back, nothing half built
	local id = BuilderGear.Entry(3, "TrunkLeg_L").id
	setup(nil, { [id] = true })
	model = dress(Looks.Defaults(1), build(50))
	local a = meshes(folder(model, "Attire"))
	check("one failed leg: trunks part-built (no half set)", a.Waistband == nil and a.TrunkSeat == nil and folder(model, "Attire"):FindFirstChild("TrunkShell") ~= nil)
	check("one failed leg: boots still meshes", a.BootFoot_R ~= nil and a.BootShaft_L ~= nil)
	check("one failed leg: gloves still meshes", folder(model, "Hands"):FindFirstChild("GloveR").ClassName == "MeshPart")
end
do
	-- the body's tier meshes not uploaded: default parts (no BodyTier) -> the part-built gear
	local body0 = table.clone(REAL)
	body0.tiers = {}
	for i, t in ipairs(REAL.tiers) do
		local parts = {}
		for k, e in pairs(t.parts) do
			local c = table.clone(e)
			c.mesh = 0
			parts[k] = c
		end
		body0.tiers[i] = { parts = parts, fit = t.fit, name = t.name }
	end
	local AS = setup(nil, nil, body0)
	local model = dress(Looks.Defaults(1), build(50))
	check("default parts: no gear loads", AS.calls == 0, AS.calls)
	check("default parts: part-built gear", folder(model, "Attire"):FindFirstChild("TrunkShell") ~= nil and folder(model, "Hands"):FindFirstChild("GloveR").ClassName == "Part")
	local r, why = BuilderGear.Resolve(model, "trunks", "Pro")
	check("Resolve says why", r == nil and tostring(why):find("not a tier part") ~= nil, why)
end
BodyTiers.SetData(REAL)
BuilderGear.SetData(nil)

print(string.format("test_gear: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_gear failed")
end
