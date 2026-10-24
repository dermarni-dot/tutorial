-- BuilderBody: everything built on the body below the head (server side), split out of Builder.
-- * the body itself is the standard R15 rig with the muscle-tier parts (BuilderTiers, BodyTiers): the round-1
--   part-built muscles, hull, veins and fat layers are retired (Muscles only clears what an older build left)
-- * body resolution (Resolve): physique archetype, per-muscle levels, fat, definition, veins, detail level
--   (the model attributes, LookData and the training screens read it)
-- * colours: skin, satin trunks, shoes, referee / cornerman outfits on the R15 parts
-- * the gear is the Blender-modelled meshes of BuilderGear (tools/body/build_gear.py) fitted to every muscle tier:
--   trunks per style (waistband, seat, legs, side stripe, hem), boots / low-tops (foot, sole, laces, shaft, sock),
--   the women's sports top, gloves (glove, cuff, strap) and hand wraps, coloured from the look's gear colours.
--   Whatever is not available (a default part, an id 0, a failed load) falls back to the part-built gear below:
-- * attire: trunks, sponsor patches, socks, trainers / boxing boots by brand (sole types, laces with swinging
--   tails), referee and cornerman outfits, robe: sized from the parts' own boxes (the tier meshes' bounding
--   boxes, BodyAssetData sizes x the description's scales), so they fit every tier
-- * gloves with brand signatures (shape, oz, lace / velcro closure, piping, stitching, palm tone,
--   wordmark, plates, fight-night tape), visible wear and sweat; layered hand wraps
-- * level of detail (Config.DetailLevel) and per-folder rebuild caching (Kit.cached / Kit.seal)
-- Builder.Cosmetics runs Colors first, then (after the head) Muscles, Attire and Hands; Builder
-- forwards SetRobe here and uses Resolve / frameOf / Gear for scales and model attributes.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))
local BodyTiers = require(script.Parent:WaitForChild("BodyTiers"))
local Hair = require(script.Parent:WaitForChild("BuilderHair")) -- (IsHairAccessory: the avatar's hair stays)
local Gear = require(script.Parent:WaitForChild("BuilderGear")) -- the Blender-modelled gear meshes

local Body = {}

local V3, CF, ANG, SMOOTH = Kit.V3, Kit.CF, Kit.ANG, Kit.SMOOTH
local lerpColor, darken, contrast, rgb = Kit.lerpColor, Kit.darken, Kit.contrast, Kit.rgb
local mk, textPatch, getFolder, part = Kit.mk, Kit.textPatch, Kit.getFolder, Kit.part
local RAD = math.rad
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 40)
local FABRIC, LEATHER, RUBBER = Enum.Material.Fabric, Enum.Material.Leather, Enum.Material.Rubber

local LOD = { low = 1, medium = 2, full = 3 }

local function q(v, step)
	return math.floor(v / step + 0.5) * step
end

------------------------------------------------------------------------
-- Frame / training helpers (also used by Builder.Scales)
------------------------------------------------------------------------
local function frameOf(app)
	return Config.FindById(Config.BodyTypes, app.body and app.body.frame or "Athletic") or Config.BodyTypes[2]
end

local function avgDev(build, keys)
	local t = 0
	for _, k in ipairs(keys) do
		t += (build and tonumber(build[k]) or 10)
	end
	return t / #keys / 100
end

-- gear table with the CONTRACTS section 4 defaults filled in (never mutates the caller's table)
local GEAR_DEFAULTS = { gloves = "Worn", wraps = "OldWraps", shoes = "Sneakers", mouthguard = "BoilBite", glovesCond = 100, wrapsCond = 100, shoesCond = 100 }
local function gearOf(gear)
	local out = {}
	if type(gear) == "table" then
		for k, v in pairs(gear) do
			out[k] = v
		end
	end
	for k, v in pairs(GEAR_DEFAULTS) do
		if out[k] == nil then
			out[k] = v
		end
	end
	return out
end

------------------------------------------------------------------------
-- Physique & body resolution (one table every body layer reads)
------------------------------------------------------------------------
-- body sliders that scale a muscle group (back follows half the shoulder slider)
local GROUP_SLIDER = { chest = "chest", shoulders = "shoulders", arms = "arms", legs = "legs", neck = "neck", back = "shoulders" }
local GROUP_SLIDER_K = { back = 0.5 }

-- silhouette knobs per physique on top of Config.Physiques (shape / defBonus / width are data there):
-- elong = muscle length (long and wiry vs short and round), flat = protrusion, groove = separation
-- lines, waist = love handles / hip width, taper = lat flare (V-taper)
local PV = {
	BeginnerLean = { elong = 1.0, flat = 0.85, groove = 0.6, waist = 1.0, taper = 0.9 },
	LeanTechnical = { elong = 1.08, flat = 0.9, groove = 1.15, waist = 0.92, taper = 1.0 },
	Balanced = { elong = 1.0, flat = 1.0, groove = 1.0, waist = 1.0, taper = 1.0 },
	PowerPuncher = { elong = 0.95, flat = 1.12, groove = 0.95, waist = 1.05, taper = 1.1 },
	Heavyweight = { elong = 0.94, flat = 1.0, groove = 0.55, waist = 1.2, taper = 0.95 },
	EliteChampion = { elong = 1.03, flat = 1.06, groove = 1.35, waist = 0.95, taper = 1.2 },
}

-- visual archetype: opts.physique (players always get it from Training.PhysiqueInfo via LookOpts) >
-- a pinned app.body.physique > classification of the build (NPCs and previews only)
local function physiqueOf(app, build, opts)
	local id = opts and opts.physique
	if type(id) ~= "string" or not Config.FindById(Config.Physiques, id) then
		local pinned = app.body and app.body.physique
		if type(pinned) == "string" and pinned ~= "Auto" and Config.FindById(Config.Physiques, pinned) then
			id = pinned
		else
			local ok, res = pcall(Config.ClassifyPhysique, build or {}, { frame = app.body and app.body.frame, tier = opts and opts.tier })
			id = ok and res or "Balanced"
		end
	end
	return Config.FindById(Config.Physiques, id) or Config.FindById(Config.Physiques, "Balanced") or Config.Physiques[1]
end

-- (app, build, opts, model?) -> spec: physique, per-part levels, fat, definition, veins, detail level.
-- model (optional) supplies the Grime attribute when opts.grime is not given.
local function resolve(app, build, opts, model)
	app = app or {}
	opts = opts or {}
	build = type(build) == "table" and build or {}
	local frame = frameOf(app)
	local ph = physiqueOf(app, build, opts)
	local pv = PV[ph.id] or PV.Balanced
	local sl = app.body or {}
	local female = app.gender == 2
	local BF = Config.BodyFat
	-- quantised so the small fat / water changes of every session do not defeat the rebuild cache
	local fat = q(math.clamp(tonumber(build.fat) or BF.default, BF.min, BF.max), 0.5)
	local dry = q(math.clamp(tonumber(opts.dry) or 0, 0, 1), 0.1)
	-- a weight cut strips water: reads ~1.5% leaner and drier than the scale says
	local def = Config.Definition(fat - 1.5 * dry, (ph.defBonus or 0) + 0.15 * dry)
	local fatK = math.clamp((fat - 12) / 14, 0, 1)
	-- part values are capped at 100 * potential by training; normalise half of that back out so a
	-- maxed Lean frame still looks trained while a Heavyweight frame still out-sizes it
	local norm = 0.55 + 0.45 / (frame.potential or 1)
	local lv = {}
	for _, p in ipairs(Config.MuscleParts) do
		local g = p.group
		local slider = tonumber(sl[GROUP_SLIDER[g] or ""]) or 0
		local v = Config.PartValue(build, p.id) / 100 * norm * ((ph.shape and ph.shape[g]) or 1) * (1 + 0.3 * slider * (GROUP_SLIDER_K[g] or 1))
		if female then
			v *= 0.7
		end
		-- 0.04 of a level is < 0.01 stud of muscle: invisible, but it keeps rebuilds rare
		lv[p.id] = q(math.clamp(v, 0, 1.35), 0.04)
	end
	local vasc = math.clamp(tonumber(build.vasc) or 0, 0, 100) / 100
	local arm = (lv.forearms + lv.biceps) / 2
	local vein = 0.5 * vasc + 0.4 * math.clamp((def - BF.veinDef) / (1 - BF.veinDef), 0, 1) + 0.25 * math.clamp(arm - 0.35, 0, 1)
	vein *= (ph.vein or 1) * (1 + 0.3 * dry) * (1 - math.clamp((fat - 15) / 6, 0, 1))
	local bulk = (lv.pecs + lv.upperChest + lv.frontDelt + lv.sideDelt + lv.biceps + lv.triceps + lv.lats + lv.traps) / 8
	local d, cfg = Config.DetailLevel(opts)
	local grime = tonumber(opts.grime) or (model and tonumber(model:GetAttribute("Grime"))) or 0
	grime = math.clamp(grime, 0, 1)
	return {
		frame = frame, ph = ph, pv = pv, female = female, fat = fat, fatK = fatK, dry = dry,
		def = q(def, 0.05), lv = lv, vein = q(math.clamp(vein, 0, 1), 0.05), bulk = q(math.clamp(bulk, 0, 1), 0.05),
		detail = d, cfg = cfg, lod = LOD[d] or 3, outfit = opts.outfit, grime = q(grime, 0.1),
		skin = Looks.Color(Looks.SkinTones[app.skin or 5]),
	}
end

------------------------------------------------------------------------
-- Muscles: retired (the muscle-tier body parts carry the muscle)
------------------------------------------------------------------------
-- attire / robe clipping envelope: how far (ratio of the half size) the body reaches past each part's box. The
-- tier meshes fill their parts' boxes (Size = the mesh's bounding box), so it is 1 everywhere now; an older
-- build's Muscles folder attributes are still read until Muscles clears it
local ENV_FAMS = { "UT", "UA", "UL", "LL", "LA", "LT" }
local function readEnv(model)
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild("Muscles")
	local env = {}
	for _, fam in ipairs(ENV_FAMS) do
		local v = f and f:GetAttribute("Env" .. fam)
		local top = f and f:GetAttribute("EnvTop" .. fam)
		env[fam] = { x = v and v.X or 1, zf = v and v.Y or 1, zb = v and v.Z or 1, y = top or 1 }
	end
	return env
end

local function sizesOf(model, names)
	local out = {}
	for _, n in ipairs(names) do
		local p = part(model, n)
		out[#out + 1] = p and p.Size or false
	end
	return out
end
local function shoeOf(gear)
	return Catalog.Find(Catalog.Shoes, gear.shoes) or Catalog.Shoes[1]
end

-- an official's outfit colours: opts.officialColors (Officials.Colors: the venue's / a title fight's shirt) or the
-- defaults. -> shirt, trousers, the whole table (Color3 values) or nil for a boxer
local OFFICIAL_DEFAULTS = {
	referee = { shirt = { 150, 190, 226 }, trousers = { 22, 22, 26 }, shoes = { 14, 14, 16 } },
	cornerman = { shirt = nil, trousers = { 38, 38, 44 }, shoes = { 236, 236, 232 } },
}
local function outfitColors(app, outfit, opts)
	local def = OFFICIAL_DEFAULTS[outfit or ""]
	if not def then
		return nil
	end
	local oc = (opts and type(opts.officialColors) == "table") and opts.officialColors or {}
	local out = {}
	for k, v in pairs(oc) do
		out[k] = rgb(v, nil)
	end
	local fallbackShirt = outfit == "cornerman" and Looks.Color(app.attire and app.attire.trim, Color3.fromRGB(30, 30, 34))
		or rgb(def.shirt, WHITE)
	out.shirt = out.shirt or fallbackShirt
	out.trousers = out.trousers or rgb(def.trousers, Color3.fromRGB(24, 24, 28))
	out.shoes = out.shoes or rgb(def.shoes, Color3.fromRGB(20, 20, 22))
	return out.shirt, out.trousers, out
end

-- the R15 parts the retired hull hid (Transparency 1): shown again when an older build's folder is cleared
local HULL_PARTS = { "UpperTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }

-- (model, ...) -> the attire envelope. Clears the round-1 muscle layer an older build left (its folder, and the
-- R15 blocks its hull hid); the arguments of the old step are accepted and ignored
local function musclesBuild(model)
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild("Muscles")
	if f then
		f:Destroy()
		for _, n in ipairs(HULL_PARTS) do
			local p = part(model, n)
			if p and p:IsA("BasePart") and p.Transparency >= 1 then
				p.Transparency = 0
			end
		end
	end
	return readEnv(model)
end

------------------------------------------------------------------------
-- Colours of the R15 parts (skin, trunks, shoes, outfits)
------------------------------------------------------------------------
-- shoe wear in 5-point steps (60 = like new): the uncached R15 feet and the cached Attire overlays
-- (toe box, collar, boot shaft, tongue) both use this bucket, and the Attire key includes it, so the
-- two never drift into a clean toe and a grubby heel
local function shoeCond(gear)
	return math.min(60, q(tonumber(gear.shoesCond) or 100, 5))
end

local function shoeColorOf(app, gear)
	local a = app.attire or {}
	local c = Looks.Color(a.shoes, Color3.fromRGB(25, 25, 25))
	local cond = shoeCond(gear)
	if cond < 60 then
		-- worn-out shoes fade and get grubby
		c = lerpColor(c, Color3.fromRGB(95, 85, 70), (60 - cond) / 60 * 0.45)
	end
	return c
end

local function colorBody(model, app, gear, opts)
	opts = opts or {}
	gear = gearOf(gear)
	local skin = Looks.Color(Looks.SkinTones[app.skin or 5])
	local a = app.attire or {}
	local shoeColor = shoeColorOf(app, gear)
	local trainer = shoeOf(gear).style == "trainer"
	local trunks = Looks.Color(a.trunks, Color3.fromRGB(200, 25, 30))
	local shirt, trousers, oc = outfitColors(app, opts.outfit, opts)
	local bc = model:FindFirstChildOfClass("BodyColors")
	if bc then
		bc:Destroy()
	end
	local smooth = (app.face and app.face.smooth or 0.5) >= 0.5
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local n = p.Name
			if n == "LowerTorso" then
				p.Color = trousers or trunks
				p.Material = trousers and FABRIC or SMOOTH -- satin trunks (the Fabric texture reads as noise at play distance)
			elseif n:find("Foot") then
				if trousers then
					-- (under the officials' mesh shoes: their colour)
					p.Color = oc and oc.shoes or Color3.fromRGB(20, 20, 22)
					p.Material = SMOOTH
				else
					p.Color = shoeColor
					p.Material = trainer and FABRIC or LEATHER
				end
			elseif shirt and (n == "UpperTorso" or n:find("UpperArm")) then
				p.Color = shirt
				p.Material = FABRIC
			elseif trousers and (n:find("UpperLeg") or n:find("LowerLeg")) then
				p.Color = trousers
				p.Material = FABRIC
			elseif n == "Head" then
				-- the face step owns the head's material (skin pores / smoothness) and may be cached
				p.Color = skin
			else
				p.Color = skin
				p.Material = smooth and SMOOTH or Enum.Material.Plastic
			end
		end
	end
	-- women: the sports top. The mesh top (Attire) goes over a skin torso; without it the whole UpperTorso takes the
	-- top's colour (the part-built look; Attire repaints it should the mesh top fail to load)
	if app.gender == 2 and not shirt and not Gear.Available(model, "top", "Top") then
		local ut = model:FindFirstChild("UpperTorso")
		if ut then
			ut.Color = Looks.Color(a.trim, WHITE)
			ut.Material = SMOOTH
		end
	end
	-- (a player's avatar hair accessories stay: Builder's AvatarHair, the description put them on)
	local keepHair = model:GetAttribute("AvatarHair") == true
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") or (c:IsA("Accessory") and not (keepHair and Hair.IsHairAccessory(c))) then
			c:Destroy()
		end
	end
end

------------------------------------------------------------------------
-- Attire: trunks, sponsor patches, shoes / boots, officials' outfits
------------------------------------------------------------------------
-- swinging lace / wrap ends: a Motor6D chain tagged HairSway (the Animator's hair sway drives it)
local function tail(folder, anchor, startCF, look, segs, segLen, w, color, mat, stiff, mass, name)
	local parent = anchor
	local pos = startCF.Position
	for i = 1, segs do
		local orient = CFrame.lookAt(pos, pos + look) * ANG(RAD(90), 0, 0) -- -Y along the hanging direction
		local p = mk(folder, nil, name, V3(w, segLen, w * 0.6), orient * CF(0, -segLen / 2, 0), color, "Block", mat)
		local m = Instance.new("Motor6D")
		m.Name = "HairJoint"
		m.Part0 = parent
		m.Part1 = p
		m.C0 = parent.CFrame:Inverse() * orient
		m.C1 = p.CFrame:Inverse() * orient
		m:SetAttribute("Depth", i)
		m:SetAttribute("Stiff", stiff)
		m:SetAttribute("Mass", mass)
		m.Parent = p
		CollectionService:AddTag(m, "HairSway")
		parent = p
		pos = (orient * CF(0, -segLen, 0)).Position
		look = (look + V3(0, -0.8, 0)).Unit
	end
end

local function initials(name)
	local out = ""
	for w in tostring(name or ""):gmatch("%S+") do
		out ..= w:sub(1, 1):upper()
	end
	return out:sub(1, 3)
end

-- sponsor { text, fg = {r,g,b}, bg = {r,g,b} } (Career.LookOpts) -> text, fg, bg or nil
local function sponsorOf(s)
	if type(s) ~= "table" or type(s.text) ~= "string" or s.text == "" then
		return nil
	end
	return s.text:upper():sub(1, 14), rgb(s.fg, WHITE), rgb(s.bg, Color3.fromRGB(20, 20, 20))
end

local SOLE = {
	Foam = { h = 0.15, color = Color3.fromRGB(236, 236, 230), mat = SMOOTH },
	Rubber = { h = 0.13, mat = RUBBER }, -- colour = trim (boots: red laces, red soles)
	Gum = { h = 0.12, color = Color3.fromRGB(178, 124, 70), mat = RUBBER },
	Suede = { h = 0.07, color = Color3.fromRGB(52, 46, 40), mat = FABRIC },
	Split = { h = 0.11, mat = RUBBER },
}

local function soleBuild(folder, foot, kind, trim, lod)
	local fs = foot.Size
	local so = SOLE[kind] or SOLE.Rubber
	local color = so.color or trim
	local y = -fs.Y * 0.5 + so.h * 0.25
	if kind == "Split" and lod >= 2 then
		-- split sole: forefoot pad and heel pad with a flexible arch gap (elite footwork boots)
		mk(folder, foot, "Sole", V3(fs.X * 1.06, so.h, fs.Z * 0.6), foot.CFrame * CF(0, y, -fs.Z * 0.24), color, "Block", so.mat)
		mk(folder, foot, "SoleHeel", V3(fs.X * 1.04, so.h, fs.Z * 0.3), foot.CFrame * CF(0, y, fs.Z * 0.39), color, "Block", so.mat)
	else
		mk(folder, foot, "Sole", V3(fs.X * 1.06, so.h, fs.Z * 1.08), foot.CFrame * CF(0, y, 0), color, "Block", so.mat)
	end
end

local function shoesBuild(folder, model, app, opts, gear, sp, env)
	local a = app.attire or {}
	local lod, cfg = sp.lod, sp.cfg
	local shoe = shoeOf(gear)
	local brand = Catalog.GearBrand("shoes", shoe.id)
	local style = shoe.style or "boot"
	local trainer = style == "trainer"
	local tall = a.shoeStyle ~= "Low-Top"
	local cond = gear.shoesCond or 100
	local shoeColor = shoeColorOf(app, gear)
	local trim = Looks.Color(a.trim, WHITE)
	local socks = Looks.Color(a.socks, WHITE)
	local laceColor = Looks.Color(a.laces, Color3.fromRGB(240, 240, 240))
	if cond < 40 then
		laceColor = lerpColor(laceColor, Color3.fromRGB(170, 160, 140), 0.5)
	end
	local pal = brand.palette or {}
	local accent = rgb(pal.secondary, WHITE)
	if (accent.R + accent.G + accent.B) - (shoeColor.R + shoeColor.G + shoeColor.B) < 0.25 and (shoeColor.R + shoeColor.G + shoeColor.B) - (accent.R + accent.G + accent.B) < 0.25 then
		accent = rgb(pal.accent, contrast(shoeColor)) -- keep the brand stripe readable on a same-colour shoe
	end
	local soleKind = shoe.sole or brand.sole or "Rubber"
	local metal = style == "eliteBoot" and Enum.Material.Foil or Enum.Material.Metal
	local eyeletColor = style == "eliteBoot" and Color3.fromRGB(230, 190, 80) or Color3.fromRGB(210, 210, 216)
	for _, side in ipairs({ "Left", "Right" }) do
		local sign = side == "Left" and -1 or 1
		local ll, foot = part(model, side .. "LowerLeg"), part(model, side .. "Foot")
		local laceTop -- world CFrame where the bow sits
		if ll then
			local s = ll.Size
			if trainer then
				if tall then
					-- hi-top trainer collar round the ankle
					mk(folder, ll, "Collar", V3(s.X * 1.07, s.Y * 0.22, s.Z * 1.09), ll.CFrame * CF(0, -s.Y * 0.39, 0.01), shoeColor, "Block", FABRIC)
					laceTop = ll.CFrame * CF(0, -s.Y * 0.32, -s.Z * 0.56 - 0.02)
				else
					mk(folder, ll, "Sock", V3(s.X * 1.03, s.Y * 0.38, s.Z * 1.03), ll.CFrame * CF(0, -s.Y * 0.31, 0), socks, "Block", SMOOTH)
				end
			else
				-- boxing boot: laced leather shaft (to mid-calf, or the ankle for low-cut boots), sock above it
				local topY = tall and -0.02 or -0.3
				local h = 0.5 + topY
				local cy = -0.5 + h / 2
				local zb = 1.16 -- the calves sit above the shaft top, so the shaft never needs to grow
				mk(folder, ll, "BootShaft", V3(s.X * 1.1, s.Y * h, s.Z * zb), ll.CFrame * CF(0, s.Y * cy, s.Z * 0.02), shoeColor, "Block", LEATHER)
				mk(folder, ll, "Sock", V3(s.X * 1.05, s.Y * 0.09, s.Z * 1.08), ll.CFrame * CF(0, s.Y * (topY + 0.045), s.Z * 0.01), socks, "Block", SMOOTH)
				local fz = -s.Z * 0.56 - 0.012
				if lod >= 2 and cfg.laces ~= "full" then
					-- eyelet rows (the full criss-cross laces cover that line, so they are skipped there)
					for _, ex in ipairs({ -1, 1 }) do
						mk(folder, ll, "Eyelets", V3(0.035, s.Y * (h - 0.14), 0.03), ll.CFrame * CF(ex * s.X * 0.15, s.Y * (cy + 0.03), fz - 0.004), eyeletColor, "Block", metal)
					end
				end
				if lod >= 2 then
					-- padded tongue rising out of the shaft top
					mk(folder, ll, "Tongue", V3(s.X * 0.32, 0.16, 0.06), ll.CFrame * CF(0, s.Y * topY + 0.05, fz + 0.01), darken(shoeColor, 0.9), "Block", LEATHER)
				end
				if cfg.laces == "full" then
					local n = tall and 2 or 1
					local span = s.Y * (h - 0.16)
					for k = 0, n - 1 do
						local y = -s.Y * 0.5 + s.Y * 0.1 + (k + 0.5) * span / n
						for _, rot in ipairs({ 1, -1 }) do
							mk(folder, ll, "Lace", V3(s.X * 0.33, 0.035, 0.03), ll.CFrame * CF(0, y, fz - 0.01) * ANG(0, 0, rot * RAD(26)), laceColor, "Block", SMOOTH)
						end
					end
				elseif cfg.laces == "merged" then
					mk(folder, ll, "Laces", V3(s.X * 0.26, s.Y * (h - 0.16), 0.03), ll.CFrame * CF(0, s.Y * (cy + 0.03), fz - 0.01), laceColor, "Block", FABRIC)
				end
				laceTop = ll.CFrame * CF(0, s.Y * (topY - 0.04), fz - 0.02)
				if lod >= 2 and style == "proBoot" then
					-- pro boots: breathable mesh panel on the outside of the shaft
					mk(folder, ll, "MeshPanel", V3(0.03, s.Y * (h - 0.12), s.Z * 0.6), ll.CFrame * CF(sign * (s.X * 0.55 + 0.012), s.Y * cy, s.Z * 0.04), darken(shoeColor, 0.75), "Block", FABRIC)
				elseif lod >= 2 and style == "eliteBoot" then
					mk(folder, ll, "AccentStripe", V3(0.03, s.Y * (h - 0.08), 0.07), ll.CFrame * CF(sign * (s.X * 0.55 + 0.012), s.Y * cy, -s.Z * 0.12) * ANG(RAD(12), 0, 0), rgb(pal.accent, GOLD), "Block", Enum.Material.Foil)
				end
				if cfg.wordmarks and (brand.wordmark or "") ~= "" then
					textPatch(folder, ll, "Wordmark", V3(0.02, s.Y * math.min(0.12, h * 0.3), s.Z * 0.8), ll.CFrame * CF(sign * (s.X * 0.55 + 0.016), s.Y * (cy + h * 0.18), s.Z * 0.02),
						brand.wordmark, rgb(brand.wordColor, contrast(shoeColor)), sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left, brand.font)
				end
				if cfg.wordmarks and style == "eliteBoot" then
					-- elite boots: the boxer's initials on a heel nameplate
					local heel = initials(opts.name)
					if heel ~= "" then
						textPatch(folder, ll, "HeelMark", V3(s.X * 0.5, s.Y * math.min(0.14, h * 0.4), 0.02), ll.CFrame * CF(0, s.Y * (cy - h * 0.15), s.Z * zb * 0.5 + 0.03),
							heel, GOLD, Enum.NormalId.Back, brand.font)
					end
				end
			end
		end
		if foot then
			local fs = foot.Size
			if trainer then
				-- running-shoe build: foam midsole, rubber outsole, rounded toe box, brand stripe, heel tab
				local outsole = soleKind == "Gum" and SOLE.Gum.color or Color3.fromRGB(42, 42, 44)
				mk(folder, foot, "Midsole", V3(fs.X * 1.05, 0.13, fs.Z * 1.07), foot.CFrame * CF(0, -fs.Y * 0.5 + 0.03, 0), Color3.fromRGB(238, 238, 232), "Block", SMOOTH)
				if lod >= 2 then
					mk(folder, foot, "Outsole", V3(fs.X * 1.03, 0.045, fs.Z * 1.05), foot.CFrame * CF(0, -fs.Y * 0.5 - 0.045, 0), outsole, "Block", RUBBER)
					mk(folder, foot, "ToeBox", V3(fs.X * 1.0, fs.Y * 1.05, fs.Z * 0.5), foot.CFrame * CF(0, -0.01, -fs.Z * 0.3), shoeColor, "Ellipsoid", FABRIC)
				end
				if lod >= 3 then
					mk(folder, foot, "Stripe", V3(0.03, 0.09, fs.Z * 0.62), foot.CFrame * CF(sign * (fs.X * 0.5 + 0.012), 0, 0.04) * ANG(RAD(-18), 0, 0), accent, "Block", SMOOTH)
					mk(folder, foot, "HeelTab", V3(fs.X * 0.28, 0.16, 0.05), foot.CFrame * CF(0, fs.Y * 0.3, fs.Z * 0.5 + 0.02), accent, "Block", SMOOTH)
					mk(folder, foot, "Tongue", V3(fs.X * 0.34, 0.05, fs.Z * 0.34), foot.CFrame * CF(0, fs.Y * 0.5 + 0.02, -fs.Z * 0.08) * ANG(RAD(-12), 0, 0), lerpColor(shoeColor, WHITE, 0.08), "Block", FABRIC)
				end
				if cfg.laces == "full" then
					for k = 0, 1 do
						mk(folder, foot, "LaceBar", V3(fs.X * 0.3, 0.03, 0.045), foot.CFrame * CF(0, fs.Y * 0.5 + 0.035, -fs.Z * (0.3 - k * 0.16)), laceColor, "Block", SMOOTH)
					end
				elseif cfg.laces == "merged" then
					mk(folder, foot, "Laces", V3(0.25, 0.04, fs.Z * 0.4), foot.CFrame * CF(0, fs.Y * 0.5 + 0.01, -fs.Z * 0.2), laceColor, "Block", SMOOTH)
				end
				laceTop = laceTop or (foot.CFrame * CF(0, fs.Y * 0.5 + 0.05, -fs.Z * 0.06))
			else
				soleBuild(folder, foot, soleKind, trim, lod)
				if lod >= 2 then
					mk(folder, foot, "ToeBox", V3(fs.X * 1.0, fs.Y * 1.05, fs.Z * 0.5), foot.CFrame * CF(0, 0, -fs.Z * 0.3), shoeColor, "Ellipsoid", LEATHER)
				end
				-- foot lacing strip, unless the criss-cross laces are already drawn on the shaft
				if cfg.laces ~= "none" and not (cfg.laces == "full" and ll) then
					mk(folder, foot, "Laces", V3(0.25, 0.04, fs.Z * 0.5), foot.CFrame * CF(0, fs.Y * 0.5, -fs.Z * 0.1), laceColor, "Block", SMOOTH)
				end
			end
			if cond < 60 and lod >= 2 then
				-- creased toe box
				mk(folder, foot, "Crease", V3(fs.X * 0.6, 0.02, 0.03), foot.CFrame * CF(0, fs.Y * 0.5 + 0.005, -fs.Z * 0.28), darken(shoeColor, 0.6), "Block", SMOOTH, 0.3)
			end
			if cond < 40 then
				-- scuffed toes and a split sole
				mk(folder, foot, "Scuff", V3(fs.X * 0.7, fs.Y * 0.5, 0.05), foot.CFrame * CF(0, 0, -fs.Z * 0.5 - 0.01), Color3.fromRGB(120, 110, 95), "Ellipsoid", SMOOTH, 0.3)
				mk(folder, foot, "SoleSplit", V3(fs.X * 0.5, 0.05, 0.08), foot.CFrame * CF(0, -fs.Y * 0.45, -fs.Z * 0.35), Color3.fromRGB(30, 30, 30), "Block")
			end
		end
		-- bow with two swinging lace ends
		if laceTop and cfg.laces == "full" then
			local anchor = trainer and not tall and foot or ll
			if anchor then
				mk(folder, anchor, "LaceBow", V3(0.2, 0.06, 0.05), laceTop, laceColor, "Ellipsoid", SMOOTH)
				for _, dx in ipairs({ -1, 1 }) do
					local start = laceTop * CF(dx * 0.05, -0.01, -0.02)
					local look = anchor.CFrame:VectorToWorldSpace(V3(dx * 0.35, -1, -0.35)).Unit
					tail(folder, anchor, start, look, 1, 0.16, 0.03, laceColor, SMOOTH, 0.3, 0.5, "LaceTail")
				end
			end
		end
	end
end

-- the mesh boots / shoes (BuilderGear): upper in the shoe colour (leather boots, fabric trainers), the sole by its
-- kind (SOLE: foam, rubber in the trim colour, gum, suede, split), laces, socks
local function shoesMesh(folder, app, gear, pieces)
	local a = app.attire or {}
	local shoe = shoeOf(gear)
	local brand = Catalog.GearBrand("shoes", shoe.id)
	local trainer = shoe.style == "trainer"
	local soleKind = shoe.sole or brand.sole or "Rubber"
	local so = SOLE[soleKind] or SOLE.Rubber
	local soleColor = so.color or Looks.Color(a.trim, WHITE)
	if trainer and soleKind ~= "Gum" then
		soleColor = Color3.fromRGB(238, 238, 232) -- (a trainer's foam midsole)
	end
	local laceColor = Looks.Color(a.laces, Color3.fromRGB(240, 240, 240))
	if (gear.shoesCond or 100) < 40 then
		laceColor = lerpColor(laceColor, Color3.fromRGB(170, 160, 140), 0.5)
	end
	local shoeColor = shoeColorOf(app, gear)
	local socks = Looks.Color(a.socks, WHITE)
	return Gear.Build(folder, pieces, function(slot)
		if slot == "soles" then
			return soleColor, trainer and SMOOTH or so.mat, 0
		elseif slot == "laces" then
			return laceColor, SMOOTH, 0
		elseif slot == "socks" then
			return socks, FABRIC, 0
		end
		return shoeColor, trainer and FABRIC or LEATHER, 0
	end)
end

-- the officials' mesh outfit (BuilderGear group "official", tools/body/build_official.py): the referee's button shirt,
-- bow tie, belted dress trousers and leather shoes; the coach's polo, towel, trousers and white shoes. Painted per
-- slot from outfitColors (the venue's shirt)
local OFFICIAL_SLOTS = {
	shirt = { "shirt", FABRIC }, shirtTrim = { "trim", FABRIC }, buttons = { "buttons", SMOOTH }, badge = { "badge", Enum.Material.Metal },
	bowtie = { "bowtie", SMOOTH }, trousers = { "trousers", FABRIC }, belt = { "belt", LEATHER }, buckle = { "buckle", Enum.Material.Metal },
	dressShoes = { "shoes", SMOOTH }, dressSoles = { "soles", RUBBER }, dressLaces = { "laces", FABRIC }, towel = { "towel", FABRIC },
}
local function officialStyle(outfit)
	return outfit == "referee" and "Referee" or "Coach"
end
local function outfitMesh(folder, model, app, opts, sp, pieces)
	local shirt, trousers, oc = outfitColors(app, sp.outfit, opts)
	local made = Gear.Build(folder, pieces, function(slot)
		local e = OFFICIAL_SLOTS[slot]
		local c = e and oc[e[1]]
		if not c then
			c = (slot == "shirtTrim" and darken(shirt, 0.93)) or (slot == "buttons" and WHITE) or (slot == "towel" and WHITE)
				or (slot == "dressSoles" and Color3.fromRGB(30, 26, 24)) or (slot == "badge" and GOLD) or trousers
		end
		-- (polished leather shoes: a little sheen)
		return c, e and e[2] or FABRIC, slot == "dressShoes" and 0.06 or (slot == "buckle" and 0.2 or 0)
	end)
	for _, p in pairs(made) do
		if p:GetAttribute("GearSlot") ~= "buttons" and p:GetAttribute("GearSlot") ~= "buckle" then
			p:SetAttribute("Wet", "cloth")
			p:SetAttribute("BaseColor", p.Color)
			p:SetAttribute("BaseRefl", p.Reflectance)
		end
	end
	-- the coach's team lettering on the polo's back
	local back = made.OffShirt
	local ut = part(model, "UpperTorso")
	if sp.outfit == "cornerman" and back and ut and sp.cfg.wordmarks then
		local bs = back.Size
		textPatch(folder, ut, "TeamText", V3(bs.X * 0.5, bs.Y * 0.09, 0.02), back.CFrame * CF(0, bs.Y * 0.2, bs.Z * 0.5 + 0.01), "CORNER",
			contrast(shirt), Enum.NormalId.Back, "Oswald")
	end
	return made
end

local function outfitBuild(folder, model, app, opts, sp)
	local outfit = sp.outfit
	local shirt = outfitColors(app, outfit, opts)
	local lod = sp.lod
	local ut, lt, head = part(model, "UpperTorso"), part(model, "LowerTorso"), part(model, "Head")
	local black = Color3.fromRGB(16, 16, 18)
	if ut then
		local s = BodyTiers.CoreSize(ut) -- (v17: the torso's own width, not the shoulder caps')
		local d = 0.55 * (head and head.Size.X or 1.2)
		-- shirt collar round the neck, button placket down the front
		mk(folder, ut, "Collar", V3(0.14, d * 1.18, d * 1.18), ut.CFrame * CF(0, s.Y * 0.5 + 0.04, 0.02) * ANG(0, 0, RAD(90)), shirt, "Cylinder", FABRIC)
		if outfit == "referee" then
			mk(folder, ut, "BowTie", V3(0.34, 0.12, 0.06), ut.CFrame * CF(0, s.Y * 0.45, -s.Z * 0.5 - 0.06), black, "Ellipsoid", SMOOTH)
			mk(folder, ut, "BowKnot", V3(0.08, 0.09, 0.07), ut.CFrame * CF(0, s.Y * 0.45, -s.Z * 0.5 - 0.09), Color3.fromRGB(30, 30, 34), "Ellipsoid", SMOOTH)
			if lod >= 2 then
				mk(folder, ut, "Placket", V3(0.1, s.Y * 0.82, 0.02), ut.CFrame * CF(0, -s.Y * 0.06, -s.Z * 0.5 - 0.012), darken(shirt, 0.94), "Block", FABRIC)
			end
		else
			-- cornerman: team polo with a towel over the shoulder and CORNER on the back
			mk(folder, ut, "Towel", V3(0.5, 0.12, s.Z * 1.25), ut.CFrame * CF(s.X * 0.3, s.Y * 0.52, 0) * ANG(0, 0, RAD(-12)), Color3.fromRGB(235, 235, 230), "Block", FABRIC)
			if sp.cfg.wordmarks then
				textPatch(folder, ut, "TeamText", V3(s.X * 0.8, s.Y * 0.22, 0.02), ut.CFrame * CF(0, s.Y * 0.18, s.Z * 0.5 + 0.012), "CORNER", contrast(shirt), Enum.NormalId.Back, "Oswald")
			end
		end
	end
	for _, side in ipairs({ "Left", "Right" }) do
		local ua, foot = part(model, side .. "UpperArm"), part(model, side .. "Foot")
		if ua then
			-- short sleeve hem
			mk(folder, ua, "SleeveHem", V3(ua.Size.X * 1.08, 0.12, ua.Size.Z * 1.08), ua.CFrame * CF(0, -ua.Size.Y * 0.44, 0), darken(shirt, 0.95), "Block", FABRIC)
		end
		if foot then
			local fs = foot.Size
			mk(folder, foot, "Sole", V3(fs.X * 1.04, 0.06, fs.Z * 1.06), foot.CFrame * CF(0, -fs.Y * 0.5, 0), outfit == "referee" and black or Color3.fromRGB(235, 235, 235), "Block", RUBBER)
		end
	end
	if lt then
		local s = lt.Size
		mk(folder, lt, "Belt", V3(s.X * 1.06, s.Y * 0.4, s.Z * 1.08), lt.CFrame * CF(0, s.Y * 0.3, 0), black, "Block", LEATHER)
		if lod >= 2 then
			mk(folder, lt, "Buckle", V3(0.22, s.Y * 0.36, 0.03), lt.CFrame * CF(0, s.Y * 0.3, -s.Z * 0.54 - 0.012), Color3.fromRGB(200, 200, 205), "Block", Enum.Material.Metal)
		end
	end
end

-- the waistband: the top of the trunks at the waist joint, a little under half the waist-to-hip drop deep (the
-- default 0.4-stud block: 0.18 at +0.115, as before; a tier LowerTorso reaches down over the hips, so its box
-- size alone would put the band over the belly). -> height, centre (part space)
local function waistBand(lt)
	local s = lt.Size
	local wa, ha = lt:FindFirstChild("WaistRigAttachment"), lt:FindFirstChild("RightHipRigAttachment")
	local top = (wa and wa:IsA("Attachment")) and wa.Position.Y or s.Y * 0.5
	local hip = (ha and ha:IsA("Attachment")) and ha.Position.Y or -s.Y * 0.5
	local h = math.max(0.45 * (top - hip), 0.08)
	return h, top + 0.03 * h - h / 2
end

-- a tier part's measured girth (BodyAssetData tiers[n].fit[key]) at the part's scale: width (X), depth (Z), or nil
local function fitOf(p, key)
	local t = p and tonumber(p:GetAttribute("BodyTier"))
	local f = t and BodyTiers.Fit(t, key)
	if not f then
		return nil
	end
	local r = p:GetAttribute("BodyRatio")
	local kx, kz = 1, 1
	if typeof(r) == "Vector3" then
		kx, kz = r.X, r.Z
	end
	return f.width * kx, f.depth * kz
end

-- a joint's frame in world space from a part's rig attachment (the arm axis moves out per tier: gloves and wraps
-- follow the wrist joint, never a fixed offset), else the fallback offset
local function jointCF(p, attName, fallback)
	local a = p and p:FindFirstChild(attName)
	if a and a:IsA("Attachment") and p:GetAttribute("BodyTier") ~= nil then
		return p.CFrame * CF(a.Position)
	end
	return p.CFrame * fallback
end

local ATTIRE_PARTS = { "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftUpperArm", "UpperTorso", "Head" }

-- top of the trunk leg shells relative to the thigh (depends on the hip, so it goes in the signature)
local function trunkTop(model, lt, ul, low)
	if not (lt and ul) then
		return 0.5
	end
	return math.clamp(((lt.Position.Y - lt.Size.Y * 0.5) - ul.Position.Y) / ul.Size.Y + 0.03, low + 0.3, 0.5)
end

local function attireBuild(model, app, opts, gear, sp, env)
	opts = opts or {}
	gear = gearOf(gear)
	sp = sp or resolve(app, nil, opts)
	env = env or readEnv(model)
	local a = app.attire or {}
	local lt, ulL = part(model, "LowerTorso"), part(model, "LeftUpperLeg")
	local low = a.trunkStyle == "Long" and -0.5 or -0.2 -- trunk leg opening, in leg heights from the centre
	local topRel = q(trunkTop(model, lt, ulL, low), 0.02)
	-- the trunks only care about the thigh envelope, rounded UP (always covers) in coarse steps
	local function up(x)
		return math.ceil(x / 0.05 - 1e-6) * 0.05
	end
	local eUL = { x = up(env.UL.x), zf = up(env.UL.zf), zb = up(env.UL.zb) }
	local eLL = { x = up(env.LL.x), zf = up(env.LL.zf), zb = up(env.LL.zb) }
	local spT, spF, spB = sponsorOf(opts.sponsorTrunks)
	-- the Blender-modelled gear for the tiers the parts show (BuilderGear); nil = the part-built gear below
	local official = sp.outfit == "referee" or sp.outfit == "cornerman"
	local meshTrunks, meshShoes, meshTop, meshOutfit
	local whyTrunks, whyShoes, whyTop, whyOutfit
	if official then
		meshOutfit, whyOutfit = Gear.Resolve(model, "official", officialStyle(sp.outfit))
	else
		meshTrunks, whyTrunks = Gear.Resolve(model, "trunks", table.find(Looks.TrunkStyles, a.trunkStyle) and a.trunkStyle or "Classic")
		meshShoes, whyShoes = Gear.Resolve(model, "shoes", a.shoeStyle == "Low-Top" and "Low-Top" or "High-Top")
		if app.gender == 2 then
			meshTop, whyTop = Gear.Resolve(model, "top", "Top")
		end
	end
	-- (what each group is, readable on the folder in Studio: "mesh", or "blocks: <why the mesh gear was not built>")
	local function record(folder)
		local function state(pieces, why)
			return pieces and "mesh" or ("blocks: " .. tostring(why))
		end
		if official then
			folder:SetAttribute("Outfit", state(meshOutfit, whyOutfit))
		else
			folder:SetAttribute("Trunks", state(meshTrunks, whyTrunks))
			folder:SetAttribute("Shoes", state(meshShoes, whyShoes))
			if app.gender == 2 then
				folder:SetAttribute("Top", state(meshTop, whyTop))
			end
		end
	end
	local key = Kit.sig("A4", a, opts.waistText or "", spT or "", spF or "", spB or "", sp.outfit, sp.detail, gear.shoes, shoeCond(gear), gear.shoesCond >= 60, gear.shoesCond >= 40,
		eUL, a.trunkStyle == "Long" and eLL or false, topRel, opts.name or "", app.gender, sizesOf(model, ATTIRE_PARTS),
		Gear.Key(meshTrunks), Gear.Key(meshShoes), Gear.Key(meshTop), Gear.Key(meshOutfit), official and Kit.sig("OC", outfitColors(app, sp.outfit, opts)) or "")
	if Kit.cached(model, "Attire", key) then
		return
	end
	local folder = getFolder(model, "Attire")
	record(folder)
	if official then
		if meshOutfit then
			outfitMesh(folder, model, app, opts, sp, meshOutfit)
		else
			outfitBuild(folder, model, app, opts, sp)
		end
		Kit.seal(model, "Attire", key)
		return
	end
	local trunks = Looks.Color(a.trunks, Color3.fromRGB(200, 25, 30))
	local trim = Looks.Color(a.trim, WHITE)
	if app.gender == 2 then
		local ut = part(model, "UpperTorso")
		if meshTop then
			-- the sports top in the top colour (trim) with an underband in the trunks colour
			Gear.Build(folder, meshTop, function(slot)
				return slot == "topTrim" and trunks or trim, SMOOTH, 0
			end)
		elseif ut then
			ut.Color = trim -- (no mesh top: the whole torso is the top, as colorBody paints it without one)
			ut.Material = SMOOTH
		end
	end
	if meshTrunks then
		-- satin trunks: the seat and legs in the trunks colour, the waistband, side stripe and hem in the trim
		local made = Gear.Build(folder, meshTrunks, function(slot)
			if slot == "trim" then
				return trim, SMOOTH, 0.02
			end
			return trunks, SMOOTH, 0.03
		end)
		-- (v10) satin soaks a little darker with sweat (Body.SetSweat)
		for _, p in pairs(made) do
			p:SetAttribute("Wet", "cloth")
			p:SetAttribute("BaseColor", p.Color)
			p:SetAttribute("BaseRefl", p.Reflectance)
		end
		local band = made.Waistband
		local text = opts.waistText or ""
		if text == "" and sp.cfg.wordmarks then
			text = "WCB" -- (v10) the game's mark on the elastic when the boxer has no lettering of their own
		end
		if band and lt and text ~= "" then
			local bs = band.Size
			textPatch(folder, lt, "WaistText", V3(bs.X * 0.42, bs.Y * 0.55, 0.02), band.CFrame * CF(0, 0, -bs.Z / 2 - 0.012), text:upper(), contrast(trim))
		end
		local leg = made.TrunkLeg_R or made.TrunkLegLong_R
		local ul = part(model, "RightUpperLeg")
		if spT and leg and ul and sp.lod >= 2 then
			-- the sponsor on the front of the right leg (the left leg carries the boxer's own colours)
			local ls = leg.Size
			textPatch(folder, ul, "SponsorPatch", V3(ls.X * 0.5, math.min(0.2, ls.Y * 0.2), 0.02), leg.CFrame * CF(0, ls.Y * 0.08, -ls.Z / 2 - 0.012), spT, spF, Enum.NormalId.Front, "GothamBlack", spB)
		end
	end
	if meshShoes then
		shoesMesh(folder, app, gear, meshShoes)
	end
	if meshTrunks then
		if not meshShoes then
			shoesBuild(folder, model, app, opts, gear, sp, env)
		end
		Kit.seal(model, "Attire", key)
		return
	end
	if lt then
		local s = lt.Size
		local bh, by = waistBand(lt)
		-- a tier mesh fills its box, narrowest at the waist: the band hugs it; the default block takes the old margin
		local tier = lt:GetAttribute("BodyTier") ~= nil
		local band = mk(folder, lt, "Waistband", V3(s.X * (tier and 1.02 or 1.1), bh, s.Z * (tier and 1.08 or 1.18)), lt.CFrame * CF(0, by, 0), trim, "Block", SMOOTH)
		local text = opts.waistText or ""
		if text ~= "" then
			textPatch(folder, lt, "WaistText", V3(s.X * 0.8, s.Y * 0.45, 0.02), band.CFrame * CF(0, 0, -band.Size.Z / 2 - 0.012), text:upper(), contrast(trim))
		end
	end
	local white = Color3.fromRGB(240, 240, 240)
	for _, side in ipairs({ "Left", "Right" }) do
		local ul = part(model, side .. "UpperLeg")
		local ll = part(model, side .. "LowerLeg")
		local sign = side == "Left" and -1 or 1
		if ul then
			-- loose trunks over the thigh, ending above the knee (long trunks reach the knee).
			-- The shell tops out just above the bottom of the (trunk coloured) lower torso, well under the
			-- waistband: it turns with the thigh, and a high front edge would swing up over the band when
			-- the boxer bends at the hips. It is sized around the quads / hamstrings so muscle never clips.
			local us = ul.Size
			local top = trunkTop(model, lt, ul, low)
			local h = top - low
			local cy = (top + low) / 2
			local wX = math.max(1.12, eUL.x + 0.07)
			local front = math.max(0.63 * us.Z, eUL.zf * us.Z / 2 + 0.035)
			local back = math.max(0.57 * us.Z, eUL.zb * us.Z / 2 + 0.035)
			local zc = (back - front) / 2
			local dZ = front + back
			mk(folder, ul, "TrunkShell", V3(us.X * wX, us.Y * h, dZ), ul.CFrame * CF(0, us.Y * cy, zc), trunks, "Block", SMOOTH)
			local px = sign * (us.X * wX / 2 + 0.02)
			local panelH = top - low - 0.12
			local panelY = low + 0.08 + panelH / 2
			if a.trunkStyle == "Striped" then
				mk(folder, ul, "TrunkStripe", V3(0.05, us.Y * panelH, dZ * 0.38), ul.CFrame * CF(px, us.Y * panelY, zc), trim, "Block", SMOOTH)
			elseif a.trunkStyle == "Pro" then
				-- pro trunks: trim hem at the leg opening and a trim side panel with white stripes
				mk(folder, ul, "Hem", V3(us.X * (wX + 0.02), us.Y * 0.1, dZ + 0.024), ul.CFrame * CF(0, us.Y * (low + 0.05), zc), trim, "Block", SMOOTH)
				mk(folder, ul, "SidePanel", V3(0.05, us.Y * panelH, dZ * 0.52), ul.CFrame * CF(px, us.Y * panelY, zc), trim, "Block", SMOOTH)
				if sp.lod >= 2 then
					-- one broad white stripe down the panel (three thin ones cost 4 parts for little at range)
					mk(folder, ul, "SideStripe", V3(0.062, us.Y * (panelH - 0.02), dZ * 0.2), ul.CFrame * CF(px + sign * 0.006, us.Y * panelY, zc), white, "Block", SMOOTH)
				end
			end
			-- sponsor patch on the front of the right leg (left leg carries the boxer's own colours)
			if spT and sign > 0 and sp.lod >= 2 then
				textPatch(folder, ul, "SponsorPatch", V3(us.X * 0.62, us.Y * 0.2, 0.02), ul.CFrame * CF(0, us.Y * (low + h * 0.42), zc - dZ / 2 - 0.012), spT, spF, Enum.NormalId.Front, "GothamBlack", spB)
			end
		end
		if ll and a.trunkStyle == "Long" then
			-- the knee-length cuff, sized around the calf heads (the envelope, rounded up) so they never clip
			local s = ll.Size
			local wx = math.max(1.06, eLL.x + 0.06)
			local fr = math.max(0.53 * s.Z, eLL.zf * s.Z / 2 + 0.03)
			local bk = math.max(0.53 * s.Z, eLL.zb * s.Z / 2 + 0.03)
			mk(folder, ll, "TrunkLeg", V3(s.X * wx, s.Y * 0.25, fr + bk), ll.CFrame * CF(0, s.Y * 0.38, (bk - fr) / 2), trunks, "Block", SMOOTH)
		end
	end
	if not meshShoes then
		shoesBuild(folder, model, app, opts, gear, sp, env)
	end
	Kit.seal(model, "Attire", key)
end

------------------------------------------------------------------------
-- Gloves / wraps
------------------------------------------------------------------------
local function wearColor(c, cond)
	local t = math.clamp((80 - (cond or 100)) / 80, 0, 1)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s * (1 - 0.35 * t), v * (1 - 0.3 * t))
end

local function wet(p, kind, refl)
	p:SetAttribute("Wet", kind)
	p:SetAttribute("BaseColor", p.Color)
	p:SetAttribute("BaseRefl", refl or p.Reflectance)
end

local function wrapColors(app, gear)
	local a = app.attire or {}
	local wc = wearColor(Looks.Color(a.wraps, WHITE), gear.wrapsCond)
	if (gear.wrapsCond or 100) < 40 then
		wc = lerpColor(wc, Color3.fromRGB(150, 130, 100), 0.35) -- dirty wraps
	end
	local pattern = a.wrapPattern or "Solid"
	local c2, c3 = wc, wc
	if pattern == "TwoTone" then
		c2 = wearColor(Looks.Color(a.trim, WHITE), gear.wrapsCond)
		c3 = c2
	elseif pattern == "Flag" then
		-- tricolour bands: trunks / trim / the wrap colour
		c2 = wearColor(Looks.Color(a.trunks, Color3.fromRGB(200, 25, 30)), gear.wrapsCond)
		c3 = wearColor(Looks.Color(a.trim, WHITE), gear.wrapsCond)
	end
	return wc, c2, c3
end

local function wrapsBuild(folder, model, app, gear, opts, sp)
	local wrapDef = Catalog.Find(Catalog.Wraps, gear.wraps) or Catalog.Wraps[1]
	local brand = Catalog.GearBrand("wraps", wrapDef.id)
	local wc, c2, c3 = wrapColors(app, gear)
	local gel = wrapDef.style == "gel"
	local lod, cfg = sp.lod, sp.cfg
	for _, side in ipairs({ "Left", "Right" }) do
		local sign = side == "Left" and -1 or 1
		local hand, la = part(model, side .. "Hand"), part(model, side .. "LowerArm")
		if hand then
			local hs = hand.Size
			-- a tier hand's box holds the fingers too: the wrap covers the palm and the knuckles above them (the
			-- default block hand is all palm: the wrap reaches past it)
			local tierHand = hand:GetAttribute("BodyTier") ~= nil
			local wy, wk, ky = 1.4, 0, -0.62
			if tierHand then
				wy, wk, ky = 0.62, 0.12, -0.2
			end
			wet(mk(folder, hand, "Wrap", hs * V3(1.08, wy, 1.08), hand.CFrame * CF(0, hs.Y * wk, 0), wc, "Block", FABRIC), "wrap")
			if lod >= 2 then
				-- knuckle padding: a thin cotton ridge, or a moulded gel pad on gel wraps
				local kp = gel and V3(hs.X * 0.95, 0.26, hs.Z * 1.06) or V3(hs.X * 0.9, 0.18, hs.Z * 1.02)
				local kc = gel and darken(wc, 0.72) or wc
				wet(mk(folder, hand, "WrapKnuckle", kp, hand.CFrame * CF(sign * 0.05, hs.Y * ky, 0), kc, "Ellipsoid", gel and SMOOTH or FABRIC), "wrap")
			end
			if lod >= 3 then
				-- the X across the back of the hand
				for _, rot in ipairs({ 1, -1 }) do
					wet(mk(folder, hand, "WrapX", V3(0.03, 0.07, hs.Z * 1.12), hand.CFrame * CF(sign * (hs.X * 0.54 + 0.012), 0, 0) * ANG(rot * RAD(21), 0, 0), c2, "Block", FABRIC), "wrap")
				end
			end
		end
		if la then
			local s = la.Size
			local ww, wd = fitOf(la, "wrist")
			local wristSize = ww and V3(ww * 1.12, s.Y * 0.3, wd * 1.12) or V3(s.X * 1.06, s.Y * 0.3, s.Z * 1.06)
			wet(mk(folder, la, "WrapWrist", wristSize, jointCF(la, side .. "WristRigAttachment", CF(0, -s.Y * 0.5, 0)) * CF(0, s.Y * 0.14, 0), wc, "Block", FABRIC), "wrap")
			if lod >= 3 then
				-- stepped top layer and the velcro closure tab with the brand label
				wet(mk(folder, la, "WrapLayer", V3(s.X * 1.09, s.Y * 0.1, s.Z * 1.09), la.CFrame * CF(0, -s.Y * 0.25, 0), c3, "Block", FABRIC), "wrap")
				local tab = mk(folder, la, "WrapTab", V3(0.035, s.Y * 0.16, s.Z * 0.42), la.CFrame * CF(sign * (s.X * 0.545 + 0.018), -s.Y * 0.34, 0), darken(c2, 0.8), "Block", FABRIC)
				wet(tab, "wrap")
				if cfg.wordmarks and (brand.glyph or "") ~= "" then
					textPatch(folder, la, "WrapLabel", V3(0.02, s.Y * 0.12, s.Z * 0.36), tab.CFrame * CF(sign * 0.03, 0, 0), brand.glyph, contrast(tab.Color), sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left, brand.font)
				end
				if wrapDef.frayed then
					-- old wraps: a loose frayed end swinging from the wrist
					local start = la.CFrame * CF(sign * s.X * 0.5, -s.Y * 0.48, s.Z * 0.2)
					tail(folder, la, start, la.CFrame:VectorToWorldSpace(V3(sign * 0.3, -1, 0.2)).Unit, 2, 0.14, 0.07, lerpColor(wc, Color3.fromRGB(180, 165, 135), 0.3), FABRIC, 0.15, 0.4, "WrapFray")
				end
			end
		end
	end
end

local function glovesBuild(folder, model, app, gear, opts, sp)
	local g = app.gloves or {}
	local gloveDef = Catalog.Find(Catalog.Gloves, gear.gloves) or Catalog.Gloves[1]
	local brand = Catalog.GearBrand("gloves", gloveDef.id, g.brand)
	local custom = gloveDef.custom or {}
	local cond = gear.glovesCond or 100
	local lod, cfg = sp.lod, sp.cfg
	local pal = brand.palette or {}
	local main = wearColor(Looks.Color(g.color, rgb(pal.primary, Color3.fromRGB(200, 25, 30))), cond)
	-- a white band round the cuff (customisable on gloves that allow trim colours)
	local trim = custom.trim and Looks.Color(g.trim, WHITE) or wearColor(Color3.fromRGB(236, 234, 228), cond)
	local finish = custom.finish and (g.finish or brand.finish or "Leather") or (brand.finish or "Leather")
	if finish == "Metallic" and not (custom.metallic or brand.finish == "Metallic") then
		finish = "Patent"
	end
	-- leather has a soft sheen, matte none, patent a wet shine, metallic foil
	local material, refl = LEATHER, 0.04
	if finish == "Matte" then
		material, refl = LEATHER, 0
	elseif finish == "Patent" then
		material, refl = SMOOTH, 0.22
	elseif finish == "Metallic" then
		material, refl = Enum.Material.Foil, 0.35
	end
	if gloveDef.id == "WorldChampion" then
		trim = GOLD
	end
	-- seam piping and stitching: brand signature, overridable on gloves that allow custom stitching
	local piping = nil
	if brand.piping == "trim" then
		piping = trim
	elseif type(brand.piping) == "table" then
		piping = rgb(brand.piping)
	end
	local stitch = brand.stitch or "Single"
	if custom.stitching and g.stitching and g.stitching ~= "Classic" then
		stitch = g.stitching
	end
	local lum = 0.299 * main.R + 0.587 * main.G + 0.114 * main.B
	local stitchColor = lum < 0.15 and lerpColor(main, WHITE, 0.35) or darken(main, 0.55)
	if stitch == "Contrast" then
		stitchColor = trim
	elseif stitch == "Gold" then
		stitchColor = GOLD
	end
	local palmColor = darken(main, brand.palm or 0.9)
	local strapColor = custom.trim and trim or rgb(pal.secondary, trim)
	-- size: ounces (16oz bag gloves are big, 8oz fight gloves compact) and the brand's proportions
	local oz = gloveDef.oz or 16
	if opts.fightNight then
		oz = math.min(oz, 10)
	end
	local ozK = 0.86 + 0.014 * oz
	local shape = brand.shape or {}
	local wK, lK, kK, cK = shape.width or 1, shape.len or 1, shape.knuckle or 1, shape.cuff or 1
	local wrapC = wrapColors(app, gear)
	local tape = opts.fightNight == true
	-- worn leather: the striking face scuffs pale first
	local faceColor = main
	if cond < 70 then
		faceColor = lerpColor(main, Color3.fromRGB(205, 195, 180), 0.3 * (70 - cond) / 70)
	end
	if brand.targetArea then
		faceColor = Color3.fromRGB(245, 245, 245) -- amateur competition glove: white striking face
	end
	if cond < 30 then
		palmColor = darken(palmColor, 0.82) -- sweat soaked into the palm
	end
	for _, side in ipairs({ "Left", "Right" }) do
		local sign = side == "Left" and -1 or 1
		local hand, la = part(model, side .. "Hand"), part(model, side .. "LowerArm")
		-- the forearm's round cross-section: the hull cylinder (medium / full), else the R15 block's diagonal
		local dF = 0.8
		if la then
			local s = la.Size
			dF = lod >= 2 and 0.96 * math.max(s.X, s.Z) or math.sqrt(s.X * s.X + s.Z * s.Z)
			-- a tier forearm: its measured girth (the box holds the forearm's widest bulge)
			local fw, fd = fitOf(la, "forearm")
			if fw then
				dF = 1.04 * math.max(fw, fd)
			end
		end
		local dc = dF * (lod >= 2 and 1.1 or 1.02) -- the cuff: padding round the forearm
		if hand then
			-- glove frame: origin at the wrist, x = back of the hand (+) / palm (-), y = down the hand toward
			-- the knuckles, z = thumb side; a padded fist ~1.3 x the forearm wide, as deep as 0.92 x its
			-- width, ~1.15 x its width from the wrist to the striking face (a glove, not a ball or a mitten)
			local hs = hand.Size
			local base = jointCF(hand, side .. "WristRigAttachment", CF(0, hs.Y / 2, 0))
			local function at(x, y, z)
				return base * CF(sign * x, -y, -z)
			end
			local Wd = dF * 1.3 * ozK * wK * (sp.female and 0.93 or 1)
			local Dd = Wd * 0.92
			local Ln = Wd * 1.15 * lK
			local a0 = -0.12 * Wd
			local function glovePart(name, size, cf, color, shapeK)
				local p = mk(folder, hand, name, size, cf, color, shapeK or "Ellipsoid", material)
				p.Reflectance = refl
				wet(p, "glove", refl)
				return p
			end
			-- the fist: the main padding from the wrist to the front
			local mainY = (Ln - a0) * 0.94
			local mainC = (a0 + Ln) / 2 + 0.02 * Wd
			local mainX = -0.03 * Dd
			local glove = glovePart(side == "Left" and "GloveL" or "GloveR", V3(Dd, mainY, Wd * 0.96), at(mainX, mainC, 0), main)
			-- the wrist: rounds the hand compartment over the cuff's end
			glovePart("GloveWrist", V3(dc * 1.04, 0.42 * Wd, dc * 1.04), at(0, 0.07 * Wd, 0), main)
			-- the striking face over the knuckles: the broadest part, a little toward the back of the hand
			glovePart("KnucklePad", V3(Dd * 0.8 * kK, Ln * 0.52, Wd * 1.0 * kK), at(0.07 * Dd, Ln * 0.7, 0), faceColor)
			if lod >= 2 then
				-- the back panel: broad, flat-ish padding from the cuff to the knuckles
				glovePart("BackPad", V3(Dd * 0.56, Ln * 0.84, Wd * 0.92), at(0.2 * Dd, Ln * 0.42, 0), main)
				-- the curled fingers rolling under the knuckles, then the palm in the palm tone
				glovePart("FingerRoll", V3(Dd * 0.56, Ln * 0.42, Wd * 0.88), at(-0.27 * Dd, Ln * 0.66, 0), main)
				glovePart("Palm", V3(Dd * 0.5, Ln * 0.56, Wd * 0.78), at(-0.24 * Dd, Ln * 0.3, -0.03 * Wd), palmColor)
			end
			-- the thumb: a padded roll along the thumb side, palm half, its tip sewn to the finger roll
			local thumbC = lerpColor(main, palmColor, 0.35)
			glovePart("Thumb", V3(Wd * 0.33, Ln * 0.62, Wd * 0.33), at(-0.2 * Dd, Ln * 0.38, 0.43 * Wd) * ANG(RAD(10) * sign, 0, 0) * ANG(0, 0, RAD(-8) * sign), thumbC)
			if lod >= 2 then
				glovePart("ThumbTip", V3(Wd * 0.26, Ln * 0.26, Wd * 0.26), at(-0.3 * Dd, Ln * 0.66, 0.33 * Wd), thumbC)
			end
			if lod >= 3 then
				-- piping / stitching: thin discs in the main padding's middle plane, sized to its section there:
				-- only their rims show, as welt and stitch lines lying on the outline (nothing sticks out)
				local function ring(name, dx, grow, color)
					local k = math.sqrt(math.max(0, 1 - (dx / (Dd / 2)) ^ 2))
					local p = mk(folder, hand, name, V3(0.02, mainY * k * grow, Wd * 0.96 * k * grow), at(mainX + dx, mainC, 0), color, "Ellipsoid", SMOOTH)
					p:SetAttribute("Seam", true)
					return p
				end
				if piping then
					ring("Piping", 0, 1.012, piping)
				end
				if stitch ~= "Hidden" then
					ring("StitchRing", 0.05 * Dd, 1.006, stitchColor)
					if stitch == "Double" then
						ring("StitchRing", -0.05 * Dd, 1.006, stitchColor)
					end
				end
			end
			-- logo on the back panel: the player's glyph, else the brand monogram (a small plate on the flat
			-- middle of the back, so it lies on the leather)
			local glyph
			if custom.logo and g.logo and g.logo ~= "None" then
				glyph = Kit.IconText(Catalog.LogoIcons[g.logo]) or Catalog.LogoGlyphs[g.logo]
				if g.logo == "Initials" then
					glyph = initials(opts.name)
				elseif g.logo == "Flag" then
					glyph = tostring(opts.nat or "USA"):sub(1, 3):upper()
				end
			elseif cfg.wordmarks and (brand.glyph or "") ~= "" then
				glyph = brand.glyph
			end
			if glyph and glyph ~= "" and lod >= 2 then
				textPatch(folder, hand, "Logo", V3(0.02, Ln * 0.26, Wd * 0.3), at(0.48 * Dd + 0.012, Ln * 0.42, 0), glyph, trim,
					sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left, brand.font)
			end
			-- wear: torn foam on the striking face, gym duct tape round the knuckles, a sweat mark on the palm
			if cond < 35 and lod >= 2 then
				mk(folder, hand, "FoamTear", V3(Dd * 0.1, Ln * 0.1, Wd * 0.16), at(0.3 * Dd, Ln * 0.94, 0.1 * Wd), Color3.fromRGB(215, 195, 140), "Ellipsoid", Enum.Material.Sand)
			end
			if cond < 40 and (gloveDef.id == "Worn" or gloveDef.id == "Cheap") then
				mk(folder, hand, "DuctTape", V3(Dd * 0.8 * kK * 1.02, 0.12, Wd * kK * 1.02), at(0.07 * Dd, Ln * 0.7, 0), Color3.fromRGB(150, 150, 155), "Ellipsoid", FABRIC)
			end
			if cond < 30 and lod >= 2 then
				local sm = mk(folder, hand, "SweatMark", V3(Dd * 0.505, Ln * 0.565, Wd * 0.785), at(-0.24 * Dd, Ln * 0.3, -0.03 * Wd), darken(palmColor, 0.7), "Ellipsoid", material, 0.4)
				sm:SetAttribute("BaseTransparency", 0.4)
			end
			if gloveDef.aura then
				local sp2 = Instance.new("Sparkles")
				sp2.SparkleColor = Color3.fromRGB(255, 210, 60)
				sp2.Parent = glove
			end
		end
		if la then
			local s = la.Size
			local cuffLen = s.Y * 0.48 * cK
			local r = dc / 2
			-- cylinders along the forearm (a Part cylinder's axis is its X: turned up onto the arm)
			local wristCF = jointCF(la, side .. "WristRigAttachment", CF(0, -s.Y * 0.5, 0))
			local function band(y, len, grow)
				return V3(len, dc * grow, dc * grow), wristCF * CF(0, y, 0) * ANG(0, 0, RAD(90))
			end
			local function onSurface(y, ang, out)
				-- a point on the cuff's surface at height y, angle ang (0 = outer side, pi/2 = front), facing out
				return wristCF * CF(0, y, 0) * CFrame.Angles(0, -ang, 0) * CF(sign * (r + out), 0, 0)
			end
			local sz, cf = band(cuffLen / 2, cuffLen, 1)
			local cuff = mk(folder, la, "Cuff", sz, cf, main, "Cylinder", material)
			cuff.Reflectance = refl
			wet(cuff, "glove", refl)
			-- the rolled trim band at the top
			sz, cf = band(cuffLen - s.Y * 0.05, s.Y * 0.1, 1.05)
			wet(mk(folder, la, "CuffTrim", sz, cf, trim, "Cylinder", material), "glove", refl)
			-- hand wraps peeking out above the cuff
			if lod >= 3 then
				sz, cf = band(cuffLen + 0.03, 0.08, 0.97)
				mk(folder, la, "WrapPeek", sz, cf, wrapC, "Cylinder", FABRIC)
			end
			local sideFace = sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left
			if tape then
				-- fight night: laces / strap taped over and signed by the commission inspector
				sz, cf = band(cuffLen * 0.42, cuffLen * 0.5, 1.07)
				mk(folder, la, "Tape", sz, cf, Color3.fromRGB(246, 246, 242), "Cylinder", FABRIC)
				if cfg.wordmarks then
					local h = 0
					for c in tostring(opts.name or "x"):gmatch(".") do
						h += string.byte(c)
					end
					local inspectors = { "R.M.", "J.T.", "D.K.", "L.V.", "A.O." }
					textPatch(folder, la, "Signature", V3(0.02, cuffLen * 0.3, dc * 0.4), onSurface(cuffLen * 0.42, 0, dc * 0.035 + 0.012),
						inspectors[h % #inspectors + 1] .. " ok", Color3.fromRGB(30, 40, 120), sideFace, "PermanentMarker")
				end
			elseif brand.closure == "lace" then
				-- lace-up: a lace panel on the palm side with criss-crossed laces, lying on the cuff
				if lod >= 2 then
					mk(folder, la, "LacePanel", V3(0.02, cuffLen * 0.8, dc * 0.24), onSurface(cuffLen * 0.48, math.pi, 0.004), darken(main, 0.8), "Block", material)
				end
				if cfg.laces == "full" then
					for k = 0, 2 do
						for _, rot in ipairs({ 1, -1 }) do
							mk(folder, la, "GloveLace", V3(0.02, dc * 0.24, 0.03), onSurface(cuffLen * (0.22 + 0.24 * k), math.pi, 0.014) * ANG(rot * RAD(55), 0, 0), Color3.fromRGB(240, 240, 235), "Block", SMOOTH)
						end
					end
				end
			elseif lod >= 2 then
				-- velcro: a wide hook-and-loop strap round the cuff with a pull tab lying on it
				sz, cf = band(cuffLen * 0.42, cuffLen * 0.42, 1.05)
				mk(folder, la, "Strap", sz, cf, strapColor, "Cylinder", SMOOTH)
				if lod >= 3 then
					mk(folder, la, "StrapTab", V3(0.02, cuffLen * 0.3, dc * 0.18), onSurface(cuffLen * 0.42, math.pi * 0.7, dc * 0.025 + 0.008), darken(strapColor, 0.7), "Block", SMOOTH)
				end
			end
			-- cuff branding: embroidery (outer side), maker's plate (front), wordmark: small plates tangent to the
			-- round cuff (narrow enough to lie on it)
			local outerTaken = tape
			if custom.embroidery then
				local text = side == "Left" and (g.embName and opts.name or "") or (g.embNick and opts.nick or "")
				if text ~= "" and not tape then
					textPatch(folder, la, "Embroidery", V3(0.02, s.Y * 0.2, dc * 0.38), onSurface(cuffLen * 0.72, 0, 0.012), text:upper(), trim, sideFace)
					outerTaken = true
				end
			end
			local frontFace = Enum.NormalId.Front
			if brand.plate and lod >= 2 then
				local big = brand.beltPlate == true
				local plateCF = wristCF * CF(0, cuffLen * 0.55, -r - 0.02)
				mk(folder, la, big and "BeltPlate" or "Plate", V3(dc * (big and 0.4 or 0.3), cuffLen * (big and 0.4 or 0.28), 0.04), plateCF, big and GOLD or Color3.fromRGB(200, 200, 205), "Block", Enum.Material.Foil)
				if cfg.wordmarks then
					textPatch(folder, la, "PlateText", V3(dc * 0.28, cuffLen * 0.22, 0.02), plateCF * CF(0, 0, -0.032), big and (brand.glyph or "") or initials(opts.name), big and Color3.fromRGB(60, 40, 10) or Color3.fromRGB(30, 30, 34), frontFace, brand.font)
				end
			elseif cfg.wordmarks and (brand.wordmark or "") ~= "" and outerTaken then
				textPatch(folder, la, "Wordmark", V3(dc * 0.36, cuffLen * 0.22, 0.02), wristCF * CF(0, cuffLen * 0.72, -r - 0.012), brand.wordmark, rgb(brand.wordColor, contrast(main)), frontFace, brand.font)
			end
			if cfg.wordmarks and (brand.wordmark or "") ~= "" and not outerTaken then
				textPatch(folder, la, "Wordmark", V3(0.02, cuffLen * 0.22, dc * 0.36), onSurface(cuffLen * 0.72, 0, 0.012), brand.wordmark, rgb(brand.wordColor, contrast(main)), sideFace, brand.font)
			end
		end
	end
end

-- the glove's colours and finish (glovesBuild's derivation, shared by the mesh gloves)
local function gloveStyle(app, gear, opts)
	local g = app.gloves or {}
	local gloveDef = Catalog.Find(Catalog.Gloves, gear.gloves) or Catalog.Gloves[1]
	local brand = Catalog.GearBrand("gloves", gloveDef.id, g.brand)
	local custom = gloveDef.custom or {}
	local cond = gear.glovesCond or 100
	local pal = brand.palette or {}
	local main = wearColor(Looks.Color(g.color, rgb(pal.primary, Color3.fromRGB(200, 25, 30))), cond)
	local trim = custom.trim and Looks.Color(g.trim, WHITE) or wearColor(Color3.fromRGB(236, 234, 228), cond)
	local finish = custom.finish and (g.finish or brand.finish or "Leather") or (brand.finish or "Leather")
	if finish == "Metallic" and not (custom.metallic or brand.finish == "Metallic") then
		finish = "Patent"
	end
	local material, refl = LEATHER, 0.04
	if finish == "Matte" then
		material, refl = LEATHER, 0
	elseif finish == "Patent" then
		material, refl = SMOOTH, 0.22
	elseif finish == "Metallic" then
		material, refl = Enum.Material.Foil, 0.35
	end
	if gloveDef.id == "WorldChampion" then
		trim = GOLD
	end
	local strap = custom.trim and trim or rgb(pal.secondary, trim)
	if brand.closure == "lace" then
		strap = trim -- (lace-ups: the rolled trim band)
	end
	if opts and opts.fightNight then
		strap = Color3.fromRGB(246, 246, 242) -- fight night: the cuffs taped over
	end
	return { def = gloveDef, brand = brand, custom = custom, main = main, trim = trim, strap = strap, material = material, refl = refl }
end

-- the mesh gloves (BuilderGear): the glove (named GloveL / GloveR: the fight animation's contact spheres read them)
-- and its cuff in the glove colour and finish, the strap in the strap / trim colour; the logo on the back of the hand
local function glovesMesh(folder, model, app, gear, opts, sp, pieces)
	local st = gloveStyle(app, gear, opts)
	local made = Gear.Build(folder, pieces, function(slot)
		if slot == "gloveTrim" then
			return st.strap, st.material == Enum.Material.Foil and SMOOTH or st.material, math.min(st.refl, 0.1)
		end
		return st.main, st.material, st.refl
	end, { Glove_L = "GloveL", Glove_R = "GloveR" })
	for name, p in pairs(made) do
		wet(p, "glove", p.Reflectance)
		if st.def.aura and (name == "Glove_L" or name == "Glove_R") then
			local sp2 = Instance.new("Sparkles")
			sp2.SparkleColor = Color3.fromRGB(255, 210, 60)
			sp2.Parent = p
		end
	end
	local g = app.gloves or {}
	local glyph
	if st.custom.logo and g.logo and g.logo ~= "None" then
		glyph = Kit.IconText(Catalog.LogoIcons[g.logo]) or Catalog.LogoGlyphs[g.logo]
		if g.logo == "Initials" then
			glyph = initials(opts.name)
		elseif g.logo == "Flag" then
			glyph = tostring(opts.nat or "USA"):sub(1, 3):upper()
		end
	elseif sp.cfg.wordmarks and (st.brand.glyph or "") ~= "" then
		glyph = st.brand.glyph
	elseif sp.cfg.wordmarks then
		glyph = "WCB" -- (v10) the mesh glove's raised logo panel carries the game's mark when no brand has one
	end
	if glyph and glyph ~= "" and sp.lod >= 2 then
		for _, side in ipairs({ "Left", "Right" }) do
			local gl = made["Glove_" .. side:sub(1, 1)]
			local hand = part(model, side .. "Hand")
			if gl and hand then
				local sign = side == "Left" and -1 or 1
				local gs = gl.Size
				textPatch(folder, hand, "Logo", V3(0.02, gs.Y * 0.22, gs.Z * 0.3), gl.CFrame * CF(sign * (gs.X * 0.5 + 0.004), -gs.Y * 0.08, 0), glyph, st.trim,
					sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left, st.brand.font)
			end
		end
	end
	return made
end

-- the mesh wraps (BuilderGear): the hand in the wrap colour, the wrist turns in the pattern's second colour
local function wrapsMesh(folder, app, gear, pieces)
	local wc, c2 = wrapColors(app, gear)
	local made = Gear.Build(folder, pieces, function(slot)
		return slot == "wraps2" and c2 or wc, FABRIC, 0
	end)
	for _, p in pairs(made) do
		wet(p, "wrap")
	end
	return made
end

local HAND_PARTS = { "LeftHand", "LeftLowerArm", "RightHand", "RightLowerArm" }

local function handsBuild(model, app, gear, opts, sp)
	opts = opts or {}
	gear = gearOf(gear)
	sp = sp or resolve(app, nil, opts)
	local mode = opts.hands or "gloves"
	if sp.outfit == "referee" or sp.outfit == "cornerman" then
		mode = "bare" -- officials work bare-handed
	end
	local a = app.attire or {}
	-- the Blender-modelled gloves / wraps for the tiers the hands and forearms show (nil: the part-built ones)
	local mesh
	if mode == "wraps" then
		mesh = Gear.Resolve(model, "wraps", "Wraps")
	elseif mode ~= "bare" then
		mesh = Gear.Resolve(model, "gloves", "Gloves")
	end
	local key = Kit.sig("H5", mode, sp.female, sp.detail, gear.gloves, gear.wraps, q(gear.glovesCond or 100, 5), q(gear.wrapsCond or 100, 10), app.gloves, a.wraps, a.wrapPattern or "", a.trim, a.trunks,
		opts.name or "", opts.nick or "", opts.nat or "", opts.fightNight == true, sizesOf(model, HAND_PARTS), Gear.Key(mesh))
	if Kit.cached(model, "Hands", key) then
		return
	end
	local folder = getFolder(model, "Hands")
	-- the blocky R15 hand sits inside the glove: hidden so its corners never poke through the padding (it
	-- still carries the wrist joint and the welds); bare hands and wraps show it
	for _, n in ipairs({ "LeftHand", "RightHand" }) do
		local h = part(model, n)
		local t = (mode ~= "wraps" and mode ~= "bare") and 1 or 0
		if h and h:IsA("BasePart") and h.Transparency ~= t then
			h.Transparency = t
		end
	end
	if mode == "wraps" then
		if mesh then
			wrapsMesh(folder, app, gear, mesh)
		else
			wrapsBuild(folder, model, app, gear, opts, sp)
		end
	elseif mode ~= "bare" then
		if mesh then
			glovesMesh(folder, model, app, gear, opts, sp, mesh)
		else
			glovesBuild(folder, model, app, gear, opts, sp)
		end
	end
	Kit.seal(model, "Hands", key)
end

------------------------------------------------------------------------
-- Robe (toggled during walkouts)
------------------------------------------------------------------------
local function hairHidden(model, on)
	-- BuilderHead is required lazily (and directly, never through Builder) so there is no require cycle
	local ok, err = pcall(function()
		local Head = require(script.Parent:WaitForChild("BuilderHead"))
		if Head.SetHairHidden then
			Head.SetHairHidden(model, "hood", on)
		end
	end)
	if not ok then
		warn("[Boxer] SetHairHidden failed:", err)
	end
end

function Body.SetRobe(model, app, on, opts)
	local folder = getFolder(model, "Robe")
	-- BuilderHead keeps the hood state on the model (HairHiddenHood) so hair rebuilds stay hidden
	local hadHood = model:GetAttribute("HairHiddenHood") == true
	if not on then
		if hadHood then
			hairHidden(model, false)
		end
		return
	end
	local a = app.attire or {}
	local robeId = opts and opts.robe or "Classic"
	if robeId == "None" then
		if hadHood then
			hairHidden(model, false)
		end
		return
	end
	local color = Looks.Color(a.robe, Color3.fromRGB(200, 25, 30))
	local trim = robeId == "Champion" and GOLD or Looks.Color(a.robeTrim, WHITE)
	-- satin robes (a soft sheen); the hooded robe is heavier terry cloth
	local mat = robeId == "Hooded" and FABRIC or SMOOTH
	local refl = robeId == "Hooded" and 0 or 0.04
	local ut, lt = part(model, "UpperTorso"), part(model, "LowerTorso")
	-- Sized to the body it drapes: the tier MeshParts' Size IS the mesh's bounding box (BodyAssetData tiers[n].parts,
	-- scaled by the rig's height / width / depth), so a shell a few hundredths of a stud outside each part's box
	-- clears every muscle of every tier, height and frame without standing off it (the old shells were sized for
	-- the retired muscle hull: 16-25% over the box, and read a size too big on the tier bodies). Satin hangs
	-- closer than the terry-cloth hooded robe.
	local slack = robeId == "Hooded" and 1.4 or 1
	local MT, MA = 0.045 * slack, 0.03 * slack -- studs per side: torso / skirt, sleeves
	-- the rest offset of a limb in its parent's space (the joint's C0 * C1^-1: never the animated pose)
	local function restIn(child, jointName)
		local m = child and child:FindFirstChild(jointName)
		if m and m:IsA("Motor6D") then
			return m.C0 * m.C1:Inverse()
		end
		return nil
	end
	-- what the robe goes OVER besides the skin: the attire (trunks, waistband, the women's top) welded to these body
	-- parts (anchors: body part -> its rest frame in the space of the part the shell hangs on), as the x / z extents
	-- of their boxes between yMin and yMax in that space, grown from x0, x1, z0, z1
	local look = model:FindFirstChild("BoxerLook")
	local attire = look and look:FindFirstChild("Attire")
	local function bounds(anchors, x0, x1, z0, z1, yMin, yMax)
		if not attire then
			return x0, x1, z0, z1
		end
		for _, q in ipairs(attire:GetDescendants()) do
			if q:IsA("BasePart") and q.Transparency < 1 then
				local j = q:FindFirstChildOfClass("Weld") or q:FindFirstChildOfClass("WeldConstraint")
				local a = j and j.Part0
				local rest = a and anchors[a]
				if rest then
					local off
					if j:IsA("WeldConstraint") then
						off = a.CFrame:Inverse() * q.CFrame
					else
						off = j.C0 * j.C1:Inverse()
					end
					local cf = rest * off
					local h = q.Size / 2
					for _, c in ipairs({ V3(h.X, h.Y, h.Z), V3(-h.X, h.Y, h.Z), V3(h.X, -h.Y, h.Z), V3(h.X, h.Y, -h.Z),
						V3(-h.X, -h.Y, h.Z), V3(-h.X, h.Y, -h.Z), V3(h.X, -h.Y, -h.Z), V3(-h.X, -h.Y, -h.Z) }) do
						local p = cf * c
						if p.Y >= yMin and p.Y <= yMax then
							x0, x1 = math.min(x0, p.X), math.max(x1, p.X)
							z0, z1 = math.min(z0, p.Z), math.max(z1, p.Z)
						end
					end
				end
			end
		end
		return x0, x1, z0, z1
	end
	if ut then
		local s = ut.Size
		local x0, x1, z0, z1 = bounds({ [ut] = CF() }, -s.X / 2, s.X / 2, -s.Z / 2, s.Z / 2, -s.Y / 2, s.Y / 2)
		local rs = V3(x1 - x0 + 2 * MT, s.Y + 0.05, z1 - z0 + 2 * MT)
		local shell = mk(folder, ut, "RobeTorso", rs, ut.CFrame * CF((x0 + x1) / 2, 0.02, (z0 + z1) / 2), color, "Block", mat)
		shell.Reflectance = refl
		local front = rs.Z * 0.5 - (z0 + z1) / 2
		for _, side in ipairs({ -1, 1 }) do
			mk(folder, ut, "Lapel", V3(0.22 * math.min(1, s.X / 1.6), s.Y * 1.0, 0.04), ut.CFrame * CF(side * 0.14 * s.X / 1.6, 0.02, -front - 0.02) * ANG(0, 0, RAD(-12 * side)), trim, "Block", mat)
		end
		local nick = opts and opts.nick or ""
		if nick == "" then
			nick = opts and opts.name or "" -- (v10: the back carries the boxer's name when there is no nickname)
		end
		if nick ~= "" then
			textPatch(folder, ut, "RobeName", V3(s.X * 0.9, s.Y * 0.22, 0.02), shell.CFrame * CF(0, s.Y * 0.18, front + 0.012), nick:upper(), trim, Enum.NormalId.Back)
		end
		local spT, spF, spB = sponsorOf(opts and opts.sponsorRobe)
		if spT then
			textPatch(folder, ut, "SponsorPatch", V3(s.X * 0.62, s.Y * 0.1, 0.02), shell.CFrame * CF(0, -s.Y * 0.08, front + 0.012), spT, spF, Enum.NormalId.Back, "GothamBlack", spB)
		end
		if robeId == "Hooded" or robeId == "Champion" then
			-- the hood is UP for the walkout (BuilderHead hides the hair under it): a shell over the crown,
			-- sides and back, welded to the head so it turns with it. Its front edge sits at about -0.41 of
			-- the head depth: in front of A's hidden-hair line (-0.36), behind the face (-0.5), so the face
			-- stays open. The drape is the fabric falling from the hood onto the shoulders and upper back.
			mk(folder, ut, "HoodDrape", V3(s.X * 0.62, s.Y * 0.3, s.Z * 0.75), ut.CFrame * CF(0, s.Y * 0.42, s.Z * 0.32), color, "Ellipsoid", mat)
			-- (over a boxer's headgear, Builder HeadgearColor: the hood stays DOWN, only the drape. No ellipsoid hood can
			-- close over the headgear's shell without reaching in front of the face)
			local head = model:GetAttribute("HeadgearColor") == nil and part(model, "Head")
			if head then
				local hs = head.Size
				-- keep the name "Hood": Builder.Cosmetics checks for it before restoring hidden hair
				mk(folder, head, "Hood", V3(hs.X * 1.2, hs.Y * 1.14, hs.Z * 1.1), head.CFrame * CF(0, hs.Y * 0.08, hs.Z * 0.14), color, "Ellipsoid", mat)
				-- (v10) the trim round the face opening: the hood's shell a hair larger and 0.03 forward in the trim
				-- colour, so only its front sliver shows (still behind the face at -0.5)
				mk(folder, head, "HoodTrim", V3(hs.X * 1.215, hs.Y * 1.155, hs.Z * 1.1), head.CFrame * CF(0, hs.Y * 0.08, hs.Z * 0.14 - 0.03), trim, "Ellipsoid", mat)
			end
		end
	end
	if lt then
		-- skirt and belt: round the hips AND both thighs at rest (the hips' box alone is narrower than the legs'
		-- spread on the wider frames), from the waist to just above the knees
		local s = lt.Size
		local x0, x1, z0, z1 = -s.X / 2, s.X / 2, -s.Z / 2, s.Z / 2
		local bottom = -s.Y / 2 - 0.9
		local anchors = { [lt] = CF() }
		for _, side in ipairs({ "Left", "Right" }) do
			local ul = part(model, side .. "UpperLeg")
			local off = restIn(ul, side .. "Hip")
			if ul and off then
				local p, us = off.Position, ul.Size
				x0, x1 = math.min(x0, p.X - us.X / 2), math.max(x1, p.X + us.X / 2)
				z0, z1 = math.min(z0, p.Z - us.Z / 2), math.max(z1, p.Z + us.Z / 2)
				bottom = p.Y - us.Y * 0.28
				anchors[ul] = off
			end
		end
		local waist = restIn(ut, "Waist")
		local top = waist and waist.Position.Y or s.Y * 0.45
		-- the trunks under it (their seat and legs stand off the body's boxes), down to the skirt's hem
		x0, x1, z0, z1 = bounds(anchors, x0, x1, z0, z1, bottom, top + 0.3)
		local h = math.max(0.6, top - bottom)
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		local w, d = x1 - x0 + 2 * MT, z1 - z0 + 2 * MT
		mk(folder, lt, "RobeSkirt", V3(w, h, d), lt.CFrame * CF(cx, top - h / 2, cz), color, "Block", mat).Reflectance = refl
		mk(folder, lt, "RobeBelt", V3(w + 0.03, 0.18, d + 0.03), lt.CFrame * CF(cx, top - 0.16, cz), trim, "Block", mat)
		-- (v10) the belt's knot at the front and its two tails hanging from it
		local fz = cz - (d + 0.03) / 2
		mk(folder, lt, "BeltKnot", V3(0.24, 0.2, 0.08), lt.CFrame * CF(cx + 0.12, top - 0.16, fz - 0.03), trim, "Block", mat)
		for i, ang in ipairs({ -8, 10 }) do
			mk(folder, lt, "BeltTail", V3(0.13, 0.5, 0.035), lt.CFrame * CF(cx + 0.06 + 0.13 * i, top - 0.45, fz - 0.035) * ANG(0, 0, RAD(ang)), trim, "Block", mat)
		end
	end
	for _, side in ipairs({ "Left", "Right" }) do
		local ua, la = part(model, side .. "UpperArm"), part(model, side .. "LowerArm")
		if ua then
			local us = ua.Size
			mk(folder, ua, "Sleeve", V3(us.X + 2 * MA, us.Y + 0.03, us.Z + 2 * MA), ua.CFrame * CF(0, 0.015, 0), color, "Block", mat).Reflectance = refl
		end
		if la then
			-- forearm sleeve: the upper 70% of the forearm, the trim at its cuff
			local ls = la.Size
			local len = ls.Y * 0.7
			local cy = ls.Y * 0.5 - len / 2
			mk(folder, la, "SleeveLow", V3(ls.X + 2 * MA, len, ls.Z + 2 * MA), la.CFrame * CF(0, cy, 0), color, "Block", mat).Reflectance = refl
			mk(folder, la, "SleeveTrim", V3(ls.X + 2 * MA + 0.03, 0.08, ls.Z + 2 * MA + 0.03), la.CFrame * CF(0, cy - len / 2 + 0.04, 0), trim, "Block", mat)
		end
	end
	local hood = robeId == "Hooded" or robeId == "Champion"
	if hood or hadHood then
		hairHidden(model, hood)
	end
end

------------------------------------------------------------------------
-- Sweat (body side: muscles, gloves, wraps) and body bruising
------------------------------------------------------------------------
-- Builder.SetSweat calls Head.SetSweat (skin, hair, beard; writes the Sweat attribute) then this
function Body.SetSweat(model, app, level)
	level = math.clamp(tonumber(level) or 0, 0, 1)
	local look = model:FindFirstChild("BoxerLook")
	if not look then
		return
	end
	-- a subtle sheen: Reflectance mirrors the sky, so keep it low or skin glows white
	local base = (app and app.face and app.face.shine or 0) * 0.03
	local r = math.clamp(base + level * 0.05, 0, 0.08)
	local muscles = look:FindFirstChild("Muscles")
	if muscles then
		for _, p in ipairs(muscles:GetChildren()) do
			if p:IsA("BasePart") and not (p:GetAttribute("Groove") or p:GetAttribute("Fat") or p:GetAttribute("Cloth") or p:GetAttribute("Grime")) then
				p.Reflectance = r
			end
		end
	end
	-- (v10) the trunks' satin: a touch darker and a hint more sheen as it soaks
	local attire = look:FindFirstChild("Attire")
	if attire then
		for _, p in ipairs(attire:GetChildren()) do
			if p:IsA("BasePart") and p:GetAttribute("Wet") == "cloth" then
				local bc = p:GetAttribute("BaseColor")
				if typeof(bc) == "Color3" then
					p.Color = bc:Lerp(darken(bc, 0.86), level * 0.6)
					local br = p:GetAttribute("BaseRefl") or 0
					p.Reflectance = math.min(br + 0.03 * level, 0.08)
				end
			end
		end
	end
	local hands = look:FindFirstChild("Hands")
	if hands then
		for _, p in ipairs(hands:GetChildren()) do
			if p:IsA("BasePart") then
				local kind = p:GetAttribute("Wet")
				local bc = p:GetAttribute("BaseColor")
				if kind == "glove" and typeof(bc) == "Color3" then
					-- sweat darkens leather and adds a little shine
					p.Color = bc:Lerp(darken(bc, 0.8), level * 0.7)
					-- never below the build value: metallic (Foil, 0.35) gloves keep their designed shine
					local br = p:GetAttribute("BaseRefl") or 0
					p.Reflectance = math.max(br, math.min(br + 0.05 * level, 0.27))
				elseif kind == "wrap" and typeof(bc) == "Color3" then
					-- soaked cotton goes grey and darker
					p.Color = bc:Lerp(darken(bc, 0.84), level * 0.8)
				elseif p.Name == "SweatMark" then
					local bt = p:GetAttribute("BaseTransparency") or 0.4
					p.Transparency = bt + (0.2 - bt) * level
				end
			end
		end
	end
end

local function bruiseColor(skin, age)
	local list = Config.FaceDamage.bruiseColors
	age = tonumber(age) or 0
	local function col(e)
		return e and e.rgb and rgb(e.rgb) or skin
	end
	for i = #list, 1, -1 do
		if age >= list[i].day then
			local nxt = list[i + 1]
			if not nxt then
				return col(list[i])
			end
			return col(list[i]):Lerp(col(nxt), math.clamp((age - list[i].day) / (nxt.day - list[i].day), 0, 1))
		end
	end
	return col(list[1])
end

-- The tier torsos' skin (each tier's UpperTorso.mesh sampled into its box, the same for both genders: the women's
-- torso is the same mesh, scaled): per row v (-0.45 .. 0.45 of Size.Y by 0.1), per azimuth from the front (0) to the
-- side (90 deg) by 15, the radius r of the skin, box-normalised: the skin is at (sin a r, v, -cos a r) x Size
-- (both sides averaged). A torso without a tier is the plain box. Generated by tools/body/torso_surf.py --write from the
-- detailed (v10) meshes; the lite set's torsos (Config.Detail.meshes) differ by at most 0.023 of the box (a mark there
-- sinks or rises that little: SurfaceMark lenses are 0.004+ proud and translucent).
local TORSO_SURF = {
	[1] = { { 0.318, 0.324, 0.327, 0.314, 0.293, 0.275, 0.267 }, { 0.462, 0.471, 0.474, 0.456, 0.424, 0.397, 0.386 }, { 0.449, 0.460, 0.458, 0.438, 0.405, 0.379, 0.369 }, { 0.449, 0.460, 0.463, 0.445, 0.414, 0.387, 0.377 }, { 0.453, 0.464, 0.472, 0.458, 0.428, 0.400, 0.389 }, { 0.470, 0.483, 0.494, 0.481, 0.449, 0.420, 0.408 }, { 0.483, 0.510, 0.526, 0.508, 0.471, 0.440, 0.428 }, { 0.487, 0.515, 0.539, 0.536, 0.509, 0.484, 0.472 }, { 0.455, 0.470, 0.505, 0.523, 0.521, 0.503, 0.491 }, { 0.331, 0.341, 0.364, 0.381, 0.376, 0.361, 0.354 } },
	[2] = { { 0.294, 0.300, 0.305, 0.299, 0.282, 0.265, 0.258 }, { 0.427, 0.435, 0.442, 0.437, 0.411, 0.383, 0.372 }, { 0.410, 0.437, 0.427, 0.416, 0.392, 0.367, 0.356 }, { 0.411, 0.440, 0.434, 0.426, 0.401, 0.375, 0.366 }, { 0.421, 0.441, 0.447, 0.444, 0.421, 0.393, 0.385 }, { 0.436, 0.464, 0.473, 0.470, 0.448, 0.419, 0.411 }, { 0.449, 0.512, 0.530, 0.509, 0.469, 0.439, 0.431 }, { 0.461, 0.513, 0.541, 0.536, 0.507, 0.485, 0.475 }, { 0.432, 0.448, 0.488, 0.506, 0.514, 0.499, 0.489 }, { 0.290, 0.298, 0.324, 0.348, 0.351, 0.338, 0.335 } },
	[3] = { { 0.271, 0.277, 0.284, 0.283, 0.272, 0.255, 0.249 }, { 0.394, 0.402, 0.412, 0.419, 0.399, 0.371, 0.359 }, { 0.375, 0.416, 0.397, 0.392, 0.378, 0.355, 0.344 }, { 0.377, 0.423, 0.408, 0.407, 0.389, 0.364, 0.356 }, { 0.392, 0.424, 0.423, 0.429, 0.417, 0.388, 0.382 }, { 0.404, 0.451, 0.459, 0.458, 0.447, 0.419, 0.414 }, { 0.418, 0.512, 0.533, 0.510, 0.467, 0.439, 0.434 }, { 0.437, 0.509, 0.539, 0.532, 0.505, 0.486, 0.478 }, { 0.410, 0.424, 0.467, 0.489, 0.507, 0.494, 0.487 }, { 0.251, 0.258, 0.286, 0.321, 0.330, 0.322, 0.322 } },
	[4] = { { 0.255, 0.261, 0.269, 0.270, 0.263, 0.247, 0.241 }, { 0.367, 0.376, 0.387, 0.402, 0.388, 0.362, 0.348 }, { 0.347, 0.397, 0.373, 0.371, 0.365, 0.343, 0.332 }, { 0.351, 0.406, 0.386, 0.389, 0.377, 0.355, 0.346 }, { 0.370, 0.412, 0.404, 0.415, 0.413, 0.384, 0.380 }, { 0.380, 0.445, 0.452, 0.446, 0.444, 0.419, 0.418 }, { 0.395, 0.513, 0.536, 0.511, 0.465, 0.439, 0.436 }, { 0.418, 0.504, 0.537, 0.529, 0.503, 0.489, 0.482 }, { 0.390, 0.402, 0.447, 0.469, 0.502, 0.492, 0.485 }, { 0.213, 0.219, 0.256, 0.299, 0.313, 0.310, 0.311 } },
	[5] = { { 0.241, 0.246, 0.256, 0.258, 0.253, 0.240, 0.233 }, { 0.344, 0.352, 0.365, 0.383, 0.377, 0.352, 0.338 }, { 0.324, 0.378, 0.352, 0.352, 0.352, 0.332, 0.320 }, { 0.330, 0.390, 0.365, 0.374, 0.366, 0.346, 0.338 }, { 0.352, 0.399, 0.387, 0.402, 0.409, 0.380, 0.379 }, { 0.359, 0.445, 0.450, 0.437, 0.438, 0.419, 0.422 }, { 0.376, 0.513, 0.538, 0.511, 0.464, 0.440, 0.438 }, { 0.402, 0.499, 0.535, 0.526, 0.503, 0.492, 0.486 }, { 0.371, 0.383, 0.427, 0.451, 0.489, 0.489, 0.483 }, { 0.161, 0.166, 0.194, 0.280, 0.299, 0.301, 0.304 } },
}

local function torsoPoint(torso, a, v)
	local T = TORSO_SURF[torso:GetAttribute("BodyTier")]
	local r
	if T then
		local fv = math.clamp((v + 0.45) / 0.1, 0, 9)
		local i0 = math.floor(fv)
		local i1, tv = math.min(i0 + 1, 9), fv - i0
		local fa = math.clamp(math.abs(math.deg(a)) / 15, 0, 6)
		local j0 = math.floor(fa)
		local j1, ta = math.min(j0 + 1, 6), fa - j0
		local r0 = T[i0 + 1][j0 + 1] + (T[i0 + 1][j1 + 1] - T[i0 + 1][j0 + 1]) * ta
		local r1 = T[i1 + 1][j0 + 1] + (T[i1 + 1][j1 + 1] - T[i1 + 1][j0 + 1]) * ta
		r = r0 + (r1 - r0) * tv
	else
		r = 0.5 / math.max(math.abs(math.sin(a)), math.abs(math.cos(a)), 1e-3)
	end
	local s = BodyTiers.CoreSize(torso) -- (v17: TORSO_SURF is measured on the torso without its shoulder caps)
	return V3(math.sin(a) * r * s.X, v * s.Y, -math.cos(a) * r * s.Z)
end

-- a mark lying on the torso's skin (the face's lens: an ellipsoid sunk so a footprint w x h shows, rising `rise`): at u
-- across (fraction of Size.X, + = +X) and v up (fraction of Size.Y) on the front half; welded to the torso
function Body.SurfaceMark(folder, torso, name, u, v, w, h, color, transparency, rise, dk)
	rise = rise or 0.004
	local a = 0
	for _ = 1, 16 do
		local x = torsoPoint(torso, a, v).X / BodyTiers.CoreSize(torso).X
		a = math.clamp(a + (u - x) * 1.5, -1.5, 1.5)
	end
	local p = torsoPoint(torso, a, v)
	local ta = torsoPoint(torso, a + 0.02, v) - torsoPoint(torso, a - 0.02, v)
	local tv = torsoPoint(torso, a, v + 0.02) - torsoPoint(torso, a, v - 0.02)
	local nrm = ta:Cross(tv).Unit
	if nrm:Dot(V3(p.X, 0, p.Z)) < 0 then
		nrm = -nrm
	end
	local cf = CFrame.lookAt(p, p + nrm, tv.Unit)
	local function sagAt(da, dv)
		return math.max((p - torsoPoint(torso, a + da, v + dv)):Dot(nrm), 0)
	end
	local da = (w / 2) / math.max(ta.Magnitude / 0.04, 1e-3)
	local dv = (h / 2) / torso.Size.Y
	local sx = math.max(sagAt(da, 0), sagAt(-da, 0))
	local sy = math.max(sagAt(0, dv), sagAt(0, -dv))
	local D = math.max(rise / (1 - math.clamp(dk or 0.8, 0.05, 0.95)), 0.01)
	local c = D - rise
	local need = math.max(sx, sy) * 1.1 + 0.001
	if c < need then
		c = need
		D = rise + need
	end
	local fx = math.sqrt(math.max(1 - ((c - sx) / D) ^ 2, 0.04))
	local fy = math.sqrt(math.max(1 - ((c - sy) / D) ^ 2, 0.04))
	return mk(folder, torso, name, V3(w / fx, h / fy, 2 * D), torso.CFrame * cf * CF(0, 0, c), color, "Ellipsoid", SMOOTH, transparency)
end

-- body shots: soft translucent bruising lying on the ribs (dmg.ribsL / ribsR), from the flank round toward the front.
-- Adds to BoxerLook/Damage after Head.SetDamage (which recreates the folder); never destroys the face damage.
-- Partial tables are fine.
function Body.SetDamage(model, app, dmg)
	local look = model:FindFirstChild("BoxerLook")
	local ut = part(model, "UpperTorso")
	if not (look and ut) then
		return
	end
	local folder = look:FindFirstChild("Damage")
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name == "RibBruise" or c.Name == "BodyFlush" or c.Name == "AbBruise" then
				c:Destroy()
			end
		end
	end
	if type(dmg) ~= "table" then
		return
	end
	local skin = Looks.Color(Looks.SkinTones[(app and app.skin) or 5])
	local s = BodyTiers.CoreSize(ut) -- (v17: the ribs' width, not the shoulder caps')
	-- women: on the bare midriff, under the sports top (which ends at -0.18 Y)
	local female = app and app.gender == 2
	local cy, cy2, hMax = -0.2, -0.24, 0.36
	if female then
		cy, cy2, hMax = -0.34, -0.37, 0.2
	end
	for _, e in ipairs({ { -1, "ribsL" }, { 1, "ribsR" } }) do
		local side, v = e[1], math.clamp(tonumber(dmg[e[2]]) or 0, 0, 1)
		if v > 0.08 then
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "Damage"
				folder.Parent = look
			end
			local c = lerpColor(skin, bruiseColor(skin, dmg.age), 0.8)
			Body.SurfaceMark(folder, ut, "RibBruise", side * 0.29, cy, (0.26 + 0.08 * v) * s.X, math.min(0.18 + 0.1 * v, hMax) * s.Y, c,
				math.clamp(0.8 - 0.3 * v, 0.52, 0.84), 0.004, 0.8)
			if v > 0.5 then
				-- a darker core inside it, off its middle
				Body.SurfaceMark(folder, ut, "RibBruise", side * 0.31, cy2, 0.13 * s.X, math.min(0.1, hMax) * s.Y, darken(c, 0.85),
					math.clamp(0.84 - 0.34 * v, 0.55, 0.84), 0.0065, 0.75)
			end
			-- (v10) the fresh red flush where the shots land, a little in front of the bruise (fades with the bruise's age)
			local age = tonumber(dmg.age) or 0
			if v > 0.25 and age < 0.5 then
				Body.SurfaceMark(folder, ut, "BodyFlush", side * 0.22, cy + 0.04, 0.2 * s.X, math.min(0.16, hMax) * s.Y,
					lerpColor(skin, Color3.fromRGB(200, 70, 60), 0.45), math.clamp(0.9 - 0.25 * v, 0.68, 0.9), 0.003, 0.8)
			end
		end
	end
	-- (v10) heavy body work on both sides: a bruise over the lower abs too (one lens, translucent)
	local both = math.min(math.clamp(tonumber(dmg.ribsL) or 0, 0, 1), math.clamp(tonumber(dmg.ribsR) or 0, 0, 1))
	if both > 0.45 and folder then
		local c = lerpColor(skin, bruiseColor(skin, dmg.age), 0.7)
		Body.SurfaceMark(folder, ut, "AbBruise", 0.06, female and -0.4 or -0.32, 0.18 * s.X, math.min(0.12, hMax) * s.Y, c,
			math.clamp(0.86 - 0.3 * both, 0.6, 0.86), 0.004, 0.8)
	end
end

------------------------------------------------------------------------
-- Build steps (called by Builder.Cosmetics) and helpers shared with Builder
------------------------------------------------------------------------
------------------------------------------------------------------------
-- The gear's look for the anatomy meshes (look.attire.gear): AnatomyBody draws the gloves / wraps / shoes
-- itself when the meshes are on, from the same colours, styles and sizes the round-1 parts are built with
------------------------------------------------------------------------
local function c255(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function gearLook(app, gear, opts)
	opts = opts or {}
	gear = gearOf(gear)
	local a = app.attire or {}
	-- gloves (glovesBuild's derivation)
	local g = app.gloves or {}
	local gloveDef = Catalog.Find(Catalog.Gloves, gear.gloves) or Catalog.Gloves[1]
	local brand = Catalog.GearBrand("gloves", gloveDef.id, g.brand)
	local custom = gloveDef.custom or {}
	local cond = gear.glovesCond or 100
	local pal = brand.palette or {}
	local main = wearColor(Looks.Color(g.color, rgb(pal.primary, Color3.fromRGB(200, 25, 30))), cond)
	local trim = custom.trim and Looks.Color(g.trim, WHITE) or wearColor(Color3.fromRGB(236, 234, 228), cond)
	local finish = custom.finish and (g.finish or brand.finish or "Leather") or (brand.finish or "Leather")
	if finish == "Metallic" and not (custom.metallic or brand.finish == "Metallic") then
		finish = "Patent"
	end
	if gloveDef.id == "WorldChampion" then
		trim = GOLD
	end
	local piping = nil
	if brand.piping == "trim" then
		piping = trim
	elseif type(brand.piping) == "table" then
		piping = rgb(brand.piping)
	end
	local stitch = brand.stitch or "Single"
	if custom.stitching and g.stitching and g.stitching ~= "Classic" then
		stitch = g.stitching
	end
	local lum = 0.299 * main.R + 0.587 * main.G + 0.114 * main.B
	local stitchColor = lum < 0.15 and lerpColor(main, WHITE, 0.35) or darken(main, 0.55)
	if stitch == "Contrast" then
		stitchColor = trim
	elseif stitch == "Gold" then
		stitchColor = GOLD
	end
	local strapColor = custom.trim and trim or rgb(pal.secondary, trim)
	local oz = gloveDef.oz or 16
	if opts.fightNight then
		oz = math.min(oz, 10)
	end
	local shape = brand.shape or {}
	local glove = {
		c = c255(main), trim = c255(trim), palm = c255(darken(main, brand.palm or 0.9)), stitch = c255(stitchColor), stitchKind = stitch,
		piping = piping and c255(piping) or nil, strap = c255(strapColor), finish = finish, oz = oz, w = shape.width or 1, l = shape.len or 1,
		k = shape.knuckle or 1, cuff = shape.cuff or 1, closure = brand.closure or "velcro", tape = opts.fightNight == true,
		target = brand.targetArea == true, cond = q(cond, 10),
	}
	-- wraps
	local wc, c2, c3 = wrapColors(app, gear)
	local wrapDef = Catalog.Find(Catalog.Wraps, gear.wraps) or Catalog.Wraps[1]
	local wrap = { c = c255(wc), c2 = c255(c2), c3 = c255(c3), gel = wrapDef.style == "gel", cond = q(gear.wrapsCond or 100, 10) }
	-- shoes (shoesBuild's derivation)
	local shoe = shoeOf(gear)
	local sBrand = Catalog.GearBrand("shoes", shoe.id)
	local shoeColor = shoeColorOf(app, gear)
	local sPal = sBrand.palette or {}
	local accent = rgb(sPal.secondary, WHITE)
	if (accent.R + accent.G + accent.B) - (shoeColor.R + shoeColor.G + shoeColor.B) < 0.25 and (shoeColor.R + shoeColor.G + shoeColor.B) - (accent.R + accent.G + accent.B) < 0.25 then
		accent = rgb(sPal.accent, contrast(shoeColor))
	end
	local soleKind = shoe.sole or sBrand.sole or "Rubber"
	local so = SOLE[soleKind] or SOLE.Rubber
	local laceColor = Looks.Color(a.laces, Color3.fromRGB(240, 240, 240))
	if (gear.shoesCond or 100) < 40 then
		laceColor = lerpColor(laceColor, Color3.fromRGB(170, 160, 140), 0.5)
	end
	local shoeL = {
		c = c255(shoeColor), accent = c255(accent), sole = c255(so.color or Looks.Color(a.trim, WHITE)), soleKind = soleKind, lace = c255(laceColor),
		sock = c255(Looks.Color(a.socks, WHITE)), style = shoe.style or "boot", tall = a.shoeStyle ~= "Low-Top", cond = q(shoeCond(gear) / 60 * 100, 10),
	}
	return { glove = glove, wrap = wrap, shoe = shoeL }
end

Body.Colors = colorBody -- (model, app, gear, opts)
Body.GearLook = gearLook -- (app, gear, opts) -> look.attire.gear for the anatomy meshes
Body.Muscles = musclesBuild -- (model, app, build, opts?, spec?, gear?) -> envelope
Body.Attire = attireBuild -- (model, app, opts, gear, spec?, envelope?)
Body.Hands = handsBuild -- (model, app, gear, opts, spec?)
Body.Resolve = resolve -- (app, build, opts, model?) -> spec { ph, lv, fat, def, vein, bulk, detail, ... }
Body.Gear = gearOf -- (gear) -> gear with the section 4 defaults
Body.PV = PV
Body.frameOf = frameOf -- (app)
Body.avgDev = avgDev -- (build, keys)

return Body
