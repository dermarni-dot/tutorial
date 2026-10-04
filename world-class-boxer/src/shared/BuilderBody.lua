-- BuilderBody: everything built on the body below the head (server side), split out of Builder.
-- * body evolution: layered anatomical muscles for every Config.MuscleParts id (mass layer + peak /
--   head layer) that grow with training, physique archetypes, body fat, definition, veins (Beams)
-- * colours: skin, satin trunks, shoes, referee / cornerman outfits on the R15 parts
-- * attire: trunks (sized around the muscles), sponsor patches, socks, trainers / boxing boots by
--   brand (sole types, laces with swinging tails), referee and cornerman outfits, robe
-- * gloves with brand signatures (shape, oz, lace / velcro closure, piping, stitching, palm panel,
--   wordmark, plates, fight-night tape), visible wear and sweat; layered hand wraps
-- * level of detail (Config.DetailLevel) and per-folder rebuild caching (Kit.cached / Kit.seal)
-- Builder.Cosmetics runs Colors first, then (after the head) Muscles, Attire and Hands; Builder
-- forwards SetRobe here and uses Resolve / frameOf / avgDev / Gear for scales and model attributes.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))

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
-- Muscles: data-driven anatomical overlays
------------------------------------------------------------------------
-- Every muscle is an Ellipsoid that sits on one face of its R15 anchor part and protrudes past it by
-- p0 + p1 * level (fraction of the anchor size along the face normal), so an untrained boxer's
-- muscles are near-flush with the limb and grow out of it smoothly instead of floating on top.
--   on   = anchor (UT/LT torso, UA/LA arm, UL/LL leg; arm/leg entries are built once per side)
--   ax   = face: F front (-Z), B back (+Z), O outer side, I inner side, T top
--   u, v = centre on that face as fractions of the anchor size: F/B (u = X outward, v = Y),
--          O/I (u = Z, front negative, v = Y), T (u = X outward, v = Z)
--   a, b = ellipsoid size along u / v (fractions), ga / gb = growth per level, t = thickness along the normal
--   r    = degrees {x, y, z}, y / z mirrored for the left side; L = layer (1 mass, 2 peak / head)
--   lod  = lowest detail level that builds it (1 low, 2 medium, 3 full); mirror = torso pair
--   sex  = "m" / "f" only; cond(sp) = extra gate; col = "peak" (highlight) / "trunks"; fade = abs fade-in
local function defAbove(x)
	return function(sp)
		return sp.def > x
	end
end
local SPEC = {
	-- chest: sternal mass + clavicular head (upper chest shelf), tilted up toward the armpit
	{ n = "PecSternal", id = "pecs", on = "UT", L = 1, lod = 1, mirror = true, sex = "m", ax = "F", u = 0.24, v = 0.12, a = 0.4, b = 0.3, ga = 0.06, gb = 0.05, t = 0.5, p0 = 0.012, p1 = 0.17, r = { 0, 0, 10 } },
	{ n = "PecClavicular", id = "upperChest", on = "UT", L = 2, lod = 2, mirror = true, sex = "m", ax = "F", u = 0.22, v = 0.33, a = 0.36, b = 0.15, ga = 0.04, gb = 0.03, t = 0.35, p0 = 0.008, p1 = 0.11, r = { 0, 0, 5 } },
	{ n = "Bust", id = "pecs", on = "UT", L = 1, lod = 1, mirror = true, sex = "f", ax = "F", u = 0.23, v = 0.14, a = 0.42, b = 0.32, t = 0.5, p0 = 0.1, p1 = 0.04, r = { 0, 0, 6 } },
	-- abdominals: three rows that fade in with definition, the lower abs and an 8-pack row when shredded
	{ n = "Ab", id = "abs", on = "UT", L = 1, lod = 1, mirror = true, sex = "m", ax = "F", u = 0.105, v = -0.05, a = 0.17, b = 0.125, t = 0.2, p0 = 0.006, p1 = 0.05, fade = true, cond = defAbove(0.12), col = "peak" },
	{ n = "Ab", id = "abs", on = "UT", L = 1, lod = 1, mirror = true, ax = "F", u = 0.105, v = -0.2, a = 0.16, b = 0.125, t = 0.2, p0 = 0.006, p1 = 0.05, fade = true, cond = defAbove(0.12), col = "peak" },
	{ n = "Ab", id = "abs", on = "UT", L = 1, lod = 1, mirror = true, ax = "F", u = 0.105, v = -0.34, a = 0.155, b = 0.12, t = 0.2, p0 = 0.006, p1 = 0.05, fade = true, cond = defAbove(0.12), col = "peak" },
	{ n = "LowerAbs", id = "lowerAbs", on = "UT", L = 1, lod = 3, ax = "F", u = 0, v = -0.45, a = 0.26, b = 0.13, ga = 0.03, t = 0.25, p0 = 0.006, p1 = 0.05 },
	{ n = "AbRow4", id = "lowerAbs", on = "UT", L = 2, lod = 3, mirror = true, ax = "F", u = 0.1, v = -0.46, a = 0.14, b = 0.09, t = 0.2, p0 = 0.008, p1 = 0.045, fade = true, col = "peak",
		cond = function(sp)
			return sp.def >= Config.BodyFat.absRow4Def
		end },
	-- obliques round the lower front corners; serratus fingers show only when lean
	{ n = "Oblique", id = "obliques", on = "UT", L = 1, lod = 2, mirror = true, ax = "F", u = 0.41, v = -0.3, a = 0.2, b = 0.42, ga = 0.03, t = 0.5, p0 = 0.008, p1 = 0.07, r = { 0, 0, -14 } },
	{ n = "Serratus", id = "serratus", on = "UT", L = 1, lod = 3, mirror = true, sex = "m", ax = "F", u = 0.43, v = 0.02, a = 0.14, b = 0.26, t = 0.4, p0 = 0.006, p1 = 0.06, r = { 0, 0, -20 },
		cond = function(sp)
			return sp.def <= 0.35
		end },
	{ n = "SerratusFinger", id = "serratus", on = "UT", L = 2, lod = 3, mirror = true, sex = "m", ax = "F", u = 0.43, v = 0.07, a = 0.12, b = 0.06, t = 0.2, p0 = 0.008, p1 = 0.045, r = { 0, 0, 22 }, cond = defAbove(0.35), col = "peak" },
	{ n = "SerratusFinger", id = "serratus", on = "UT", L = 2, lod = 3, mirror = true, sex = "m", ax = "F", u = 0.44, v = -0.06, a = 0.115, b = 0.055, t = 0.2, p0 = 0.008, p1 = 0.04, r = { 0, 0, 22 }, cond = defAbove(0.35), col = "peak" },
	-- back: lats flare out the sides (V-taper), upper back (rhomboids / teres), erectors, upper traps
	{ n = "Lat", id = "lats", on = "UT", L = 1, lod = 1, mirror = true, ax = "O", u = 0.1, v = 0.05, a = 0.72, b = 0.6, gb = 0.06, t = 0.25, p0 = 0.0, p1 = 0.06, r = { 0, 0, -8 } },
	{ n = "UpperBack", id = "upperBack", on = "UT", L = 1, lod = 3, mirror = true, ax = "B", u = 0.22, v = 0.25, a = 0.36, b = 0.38, ga = 0.04, t = 0.4, p0 = 0.008, p1 = 0.13 },
	{ n = "Erector", id = "lowerBack", on = "UT", L = 1, lod = 3, mirror = true, ax = "B", u = 0.09, v = -0.42, a = 0.13, b = 0.48, t = 0.3, p0 = 0.008, p1 = 0.09 },
	{ n = "Trap", id = "traps", on = "UT", L = 1, lod = 1, mirror = true, ax = "T", u = 0.22, v = 0.08, a = 0.38, b = 0.62, ga = 0.04, t = 0.3, p0 = 0.01, p1 = 0.1, r = { 0, 0, -16 } },
	-- glutes push the trunks out at the back
	{ n = "Glute", id = "glutes", on = "LT", L = 1, lod = 2, mirror = true, ax = "B", u = 0.25, v = -1.2, a = 0.42, b = 2.4, ga = 0.03, t = 0.55, p0 = 0.03, p1 = 0.17, col = "trunks" },
	-- shoulders: three delt heads capping the arm
	{ n = "DeltSide", id = "sideDelt", on = "UA", L = 1, lod = 1, ax = "O", u = 0, v = 0.27, a = 0.92, b = 0.56, ga = 0.06, gb = 0.04, t = 0.6, p0 = 0.015, p1 = 0.2 },
	{ n = "DeltFront", id = "frontDelt", on = "UA", L = 1, lod = 1, ax = "F", u = 0.1, v = 0.29, a = 0.72, b = 0.5, ga = 0.05, t = 0.5, p0 = 0.015, p1 = 0.15, r = { -8, 0, 0 } },
	{ n = "DeltRear", id = "rearDelt", on = "UA", L = 1, lod = 2, ax = "B", u = 0.1, v = 0.29, a = 0.7, b = 0.46, t = 0.5, p0 = 0.012, p1 = 0.12 },
	-- arms: biceps mass + peak, triceps long + lateral head (the horseshoe)
	{ n = "Biceps", id = "biceps", on = "UA", L = 1, lod = 1, ax = "F", u = -0.02, v = -0.08, a = 0.64, b = 0.56, ga = 0.06, gb = 0.03, t = 0.5, p0 = 0.012, p1 = 0.2 },
	{ n = "BicepPeak", id = "biceps", on = "UA", L = 2, lod = 3, ax = "F", u = -0.06, v = -0.06, a = 0.4, b = 0.28, t = 0.35, p0 = 0.015, p1 = 0.26, col = "peak" },
	{ n = "Triceps", id = "triceps", on = "UA", L = 1, lod = 1, ax = "B", u = -0.06, v = 0.0, a = 0.62, b = 0.64, t = 0.5, p0 = 0.012, p1 = 0.19 },
	{ n = "TricepLateral", id = "triceps", on = "UA", L = 2, lod = 3, ax = "B", u = 0.24, v = 0.1, a = 0.36, b = 0.42, t = 0.35, p0 = 0.015, p1 = 0.2 },
	-- forearms: flexor mass and the brachioradialis along the top
	{ n = "ForearmFlexor", id = "forearms", on = "LA", L = 1, lod = 1, ax = "F", u = -0.05, v = 0.2, a = 0.78, b = 0.62, t = 0.5, p0 = 0.015, p1 = 0.15 },
	{ n = "Brachioradialis", id = "forearms", on = "LA", L = 2, lod = 2, ax = "O", u = -0.12, v = 0.27, a = 0.6, b = 0.56, t = 0.45, p0 = 0.015, p1 = 0.14 },
	-- legs: quad mass, teardrop (VMO) above the knee, hamstrings (the trunks cover the outer sweep)
	{ n = "Quad", id = "quads", on = "UL", L = 1, lod = 1, ax = "F", u = 0.04, v = -0.02, a = 0.84, b = 0.8, ga = 0.05, t = 0.5, p0 = 0.015, p1 = 0.2 },
	{ n = "Teardrop", id = "quads", on = "UL", L = 2, lod = 2, ax = "F", u = -0.22, v = -0.35, a = 0.42, b = 0.28, t = 0.4, p0 = 0.015, p1 = 0.17, col = "peak" },
	{ n = "Hamstring", id = "hamstrings", on = "UL", L = 1, lod = 3, ax = "B", u = 0, v = -0.08, a = 0.8, b = 0.8, t = 0.5, p0 = 0.012, p1 = 0.17 },
	-- calves: the two gastrocnemius heads; placed above a boot shaft (tall boots) or lower (low tops)
	{ n = "CalfMedial", id = "calves", on = "LL", L = 1, lod = 1, ax = "B", u = -0.14, v = 0.25, vLow = 0.15, a = 0.55, b = 0.42, bLow = 0.5, t = 0.5, p0 = 0.015, p1 = 0.2 },
	{ n = "CalfLateral", id = "calves", on = "LL", L = 2, lod = 2, ax = "B", u = 0.16, v = 0.28, vLow = 0.18, a = 0.44, b = 0.34, bLow = 0.42, t = 0.45, p0 = 0.012, p1 = 0.15 },
}

-- separation lines: thin dark ellipsoids that sit just above the bare surface, so they only show in
-- the valleys between muscles (the muscles cover them where they bulge). Full detail, lean bodies.
local GROOVES = {
	{ n = "Midline", on = "UT", sex = "m", ax = "F", u = 0, v = -0.18, a = 0.028, b = 0.62, t = 0.06, p = 0.008 },
	{ n = "PecLine", on = "UT", mirror = true, sex = "m", ax = "F", u = 0.25, v = -0.05, a = 0.36, b = 0.03, t = 0.06, p = 0.008, r = { 0, 0, 10 } },
	{ n = "Iliac", on = "UT", mirror = true, ax = "F", u = 0.2, v = -0.42, a = 0.04, b = 0.26, t = 0.06, p = 0.008, r = { 0, 0, -28 }, min = 0.6 },
	{ n = "DeltGroove", on = "UA", ax = "F", u = 0.36, v = 0.06, a = 0.06, b = 0.36, t = 0.06, p = 0.01, r = { 0, 0, -15 } },
}

local ANCHOR = { UT = "UpperTorso", LT = "LowerTorso", UA = "UpperArm", LA = "LowerArm", UL = "UpperLeg", LL = "LowerLeg" }
local LIMB = { UA = true, LA = true, UL = true, LL = true }

-- ellipsoid frame on a face of the anchor (see SPEC). lvl = development, k = { soft, flat, elong }
local function place(anchor, side, m, lvl, k)
	local s = anchor.Size
	local a = (m.a + (m.ga or 0) * lvl) * k.soft
	local b = (m.b + (m.gb or 0) * lvl) * k.soft * k.elong
	local pr = ((m.p0 or m.p or 0) + (m.p1 or 0) * lvl) * k.flat
	local ax = m.ax
	local sg = side == 0 and 1 or side
	local pos, size
	if ax == "F" or ax == "B" then
		local n = ax == "F" and -1 or 1
		local t = m.t * s.Z
		pos = V3(side * m.u * s.X, m.v * s.Y, n * (s.Z / 2 + pr * s.Z - t / 2))
		size = V3(a * s.X, b * s.Y, t)
	elseif ax == "O" or ax == "I" then
		local n = (ax == "O" and 1 or -1) * sg
		local t = m.t * s.X
		pos = V3(n * (s.X / 2 + pr * s.X - t / 2), m.v * s.Y, m.u * s.Z)
		size = V3(t, b * s.Y, a * s.Z)
	else
		local t = m.t * s.Y
		pos = V3(side * m.u * s.X, s.Y / 2 + pr * s.Y - t / 2, m.v * s.Z)
		size = V3(a * s.X, t, b * s.Z)
	end
	local cf = anchor.CFrame * CF(pos)
	if m.r then
		cf *= ANG(RAD(m.r[1]), RAD(m.r[2] * sg), RAD(m.r[3] * sg))
	end
	return cf, size, pos
end

local function tagMuscle(p, id, side, layer)
	p:SetAttribute("Part", id)
	p:SetAttribute("Group", Config.MusclePartGroup[id] or id)
	p:SetAttribute("Side", side)
	p:SetAttribute("Layer", layer)
	p:SetAttribute("BaseScale", V3(1, 1, 1))
end

-- surface height of a face at anchor-local (x, y) including the muscles built on it (ellipsoids are
-- treated as axis-aligned; their tilts are small). Used to lay veins on top of the bulges.
local function faceHeight(rec, s, ax, x, y)
	local h = 0
	for _, e in ipairs(rec) do
		if e.ax == ax then
			local cu, cv, cn, hu, hv, hn
			if ax == "F" or ax == "B" then
				cu, cv, cn, hu, hv, hn = e.pos.X, e.pos.Y, e.pos.Z, e.size.X / 2, e.size.Y / 2, e.size.Z / 2
			else
				cu, cv, cn, hu, hv, hn = e.pos.Z, e.pos.Y, e.pos.X, e.size.Z / 2, e.size.Y / 2, e.size.X / 2
			end
			local du, dv = (x - cu) / hu, (y - cv) / hv
			local r = du * du + dv * dv
			if r < 1 then
				local outward = math.abs(cn) + hn * math.sqrt(1 - r)
				local half = (ax == "F" or ax == "B") and s.Z / 2 or s.X / 2
				h = math.max(h, outward - half)
			end
		end
	end
	return h
end

-- Veins (full detail): Beams on the muscle parts, tag "Vein", attributes Part + BaseTransparency.
-- pts are anchor-face fractions (F/B: x outward, y; I/O: z, y); k = how much VeinLevel shows it.
local VEINS = {
	{ host = "ForearmFlexor", id = "forearms", on = "LA", ax = "F", k = 1.0, w = 0.05, pts = { { 0.18, -0.48 }, { 0.1, -0.05 }, { 0.22, 0.42 } } },
	{ host = "ForearmFlexor", id = "forearms", on = "LA", ax = "F", k = 0.9, w = 0.045, pts = { { -0.22, -0.46 }, { -0.17, 0.0 }, { -0.25, 0.4 } } },
	{ host = "ForearmFlexor", id = "forearms", on = "LA", ax = "F", k = 0.8, w = 0.04, pts = { { -0.17, 0.0 }, { 0.12, 0.3 } } },
	{ host = "Biceps", id = "biceps", on = "UA", ax = "F", k = 0.8, w = 0.045, pts = { { 0.3, -0.46 }, { 0.33, 0.0 }, { 0.27, 0.36 } } },
	{ host = "Biceps", id = "biceps", on = "UA", ax = "F", k = 0.65, w = 0.04, pts = { { -0.12, -0.38 }, { 0.02, -0.06 }, { 0.2, 0.2 } } },
	{ host = "DeltFront", id = "frontDelt", on = "UA", ax = "F", k = 0.5, w = 0.04, pts = { { 0.3, 0.3 }, { 0.0, 0.47 } } },
	{ host = "LowerAbs", id = "lowerAbs", on = "UT", ax = "F", mirror = true, k = 0.6, w = 0.04, pts = { { 0.24, -0.34 }, { 0.12, -0.49 } }, maxFat = 10 },
	{ host = "CalfMedial", id = "calves", on = "LL", ax = "I", k = 0.6, w = 0.04, pts = { { -0.05, 0.44 }, { 0.06, 0.16 }, { -0.02, 0.02 } } },
}

local function veinBeam(host, at0, at1, width, curve, color, base, id)
	local a0 = Instance.new("Attachment")
	a0.Name = "VeinA"
	a0.Position = at0
	a0.Parent = host
	local a1 = Instance.new("Attachment")
	a1.Name = "VeinB"
	a1.Position = at1
	a1.Parent = host
	local beam = Instance.new("Beam")
	beam.Name = "Vein"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width * 0.8
	beam.FaceCamera = true
	beam.Segments = 6
	beam.CurveSize0 = curve
	beam.CurveSize1 = -curve * 0.6
	beam.Color = ColorSequence.new(color)
	beam.LightInfluence = 1
	beam.Transparency = NumberSequence.new(base)
	beam:SetAttribute("Part", id)
	beam:SetAttribute("BaseTransparency", base)
	beam.Parent = host
	CollectionService:AddTag(beam, "Vein")
	return beam
end

-- attire / robe clipping envelope: how far (ratio of the half size) the muscles reach past each anchor
local ENV_FAMS = { "UT", "UA", "UL", "LL", "LA" }
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
local BODY_PARTS = { "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftUpperLeg", "LeftLowerLeg", "Head" }

local function shoeOf(gear)
	return Catalog.Find(Catalog.Shoes, gear.shoes) or Catalog.Shoes[1]
end

local function outfitColors(app, outfit)
	if outfit == "referee" then
		return Color3.fromRGB(242, 242, 240), Color3.fromRGB(24, 24, 28)
	elseif outfit == "cornerman" then
		return Looks.Color(app.attire and app.attire.trim, Color3.fromRGB(30, 30, 34)), Color3.fromRGB(44, 44, 50)
	end
	return nil
end

local function musclesBuild(model, app, build, opts, sp, gear)
	opts = opts or {}
	sp = sp or resolve(app, build, opts)
	gear = gearOf(gear)
	local sl = app.body or {}
	local a = app.attire or {}
	local skin = sp.skin
	local smoothSkin = (app.face and app.face.smooth or 0.5) >= 0.5
	local skinMat = smoothSkin and SMOOTH or Enum.Material.Plastic
	local trunks = Looks.Color(a.trunks, Color3.fromRGB(200, 25, 30))
	local top = Looks.Color(a.trim, WHITE)
	local shirt, trousers = outfitColors(app, sp.outfit)
	local lowCalf = a.shoeStyle == "Low-Top" or shoeOf(gear).style == "trainer"
	local key = Kit.sig("M3", sp.ph.id, sp.detail, sp.female, sp.lv, sp.fat, sp.def, sp.vein, sp.dry, sp.grime, app.skin, smoothSkin,
		sl, a.trunks, a.trim, lowCalf, sp.outfit, sizesOf(model, BODY_PARTS))
	if Kit.cached(model, "Muscles", key) then
		return readEnv(model)
	end
	local folder = getFolder(model, "Muscles")
	local cfg, lod, pv, ph = sp.cfg, sp.lod, sp.pv, sp.ph
	local def, fatK, fat = sp.def, sp.fatK, sp.fat
	local BF = Config.BodyFat
	local k = {
		soft = 1 + BF.softK * fatK * (ph.soft or 1), -- fat rounds muscles out...
		flat = pv.flat * (1 - 0.25 * fatK), -- ...and hides their shape
		elong = pv.elong,
	}
	local peakColor = lerpColor(skin, WHITE, 0.025 + 0.03 * def)
	local shadows = cfg.shadows and ph.shadows
	local made, recs, env = {}, {}, {}
	for _, fam in ipairs(ENV_FAMS) do
		env[fam] = { x = 1, zf = 1, zb = 1, y = 1 }
	end
	local function anchorFor(on, side)
		if LIMB[on] then
			return part(model, (side < 0 and "Left" or "Right") .. ANCHOR[on])
		end
		return part(model, ANCHOR[on])
	end
	local function record(name, side, on, anchor, ax, p, pos, size)
		made[name .. side] = p
		recs[anchor] = recs[anchor] or {}
		table.insert(recs[anchor], { ax = ax, pos = pos, size = size })
		local e = env[on]
		if e then
			local s = anchor.Size
			e.x = math.max(e.x, (math.abs(pos.X) + size.X / 2) / (s.X / 2))
			e.y = math.max(e.y, (pos.Y + size.Y / 2) / (s.Y / 2))
			e.zf = math.max(e.zf, (size.Z / 2 - pos.Z) / (s.Z / 2))
			e.zb = math.max(e.zb, (size.Z / 2 + pos.Z) / (s.Z / 2))
		end
	end
	-- colour / material of an overlay: shirts and trousers drape over the muscles, the female sports
	-- top covers everything on the upper torso above the midriff
	local function dress(on, pos, anchor, col)
		if shirt and (on == "UT" or on == "UA") then
			return shirt, FABRIC, true
		elseif trousers and (on == "UL" or on == "LL" or on == "LT") then
			return trousers, FABRIC, true
		elseif col == "trunks" then
			return trunks, SMOOTH, true
		elseif sp.female and on == "UT" and pos.Y > -0.18 * anchor.Size.Y then
			return top, SMOOTH, true
		end
		return col == "peak" and peakColor or skin, skinMat, false
	end
	local function sidesOf(m)
		if LIMB[m.on] or m.mirror then
			return { -1, 1 }
		end
		return { 0 }
	end

	-- 1) muscles
	for _, m in ipairs(SPEC) do
		local lvl = sp.lv[m.id] or 0
		local ok = lod >= m.lod and (m.L == 1 or cfg.muscleLayers >= 2)
			and (m.sex == nil or (m.sex == "f") == sp.female)
			and (m.cond == nil or m.cond(sp))
			-- peaks / heads only exist on a developed muscle; outfits hide the fine layers
			and (m.L == 1 or (lvl >= 0.25 and not shirt))
			and not (shirt and m.fade)
		if ok then
			for _, side in ipairs(sidesOf(m)) do
				local anchor = anchorFor(m.on, side)
				if anchor then
					local mm = m
					if m.vLow and lowCalf then
						mm = table.clone(m)
						mm.v, mm.b = m.vLow, m.bLow or m.b
					end
					local kk = k
					if m.id == "lats" then
						kk = { soft = k.soft, flat = k.flat * pv.taper, elong = k.elong }
					end
					local cf, size, pos = place(anchor, side, mm, lvl, kk)
					local color, mat, cloth = dress(m.on, pos, anchor, m.col)
					local trans
					if m.fade then
						trans = math.clamp(1 - def * 0.88, 0.12, 0.95)
					end
					local p = mk(folder, anchor, m.n, size, cf, color, "Ellipsoid", mat, trans)
					tagMuscle(p, m.id, side, m.L)
					if cloth then
						p:SetAttribute("Cloth", true)
					end
					if shadows and m.L == 1 and m.lod == 1 and not cloth then
						p.CastShadow = true -- elite champions: real self-shadowing separation
					end
					record(m.n, side, m.on, anchor, m.ax, p, pos, size)
				end
			end
		end
	end

	-- 2) neck column + sternocleidomastoids (girth follows the neck work and the traps)
	local ut, head = part(model, "UpperTorso"), part(model, "Head")
	if ut and head then
		local s = ut.Size
		local d = (0.5 + 0.22 * sp.lv.neckSCM + 0.06 * sp.lv.traps + 0.08 * (tonumber(sl.neck) or 0)) * head.Size.X * (sp.female and 0.9 or 1)
		local neck = mk(folder, ut, "Neck", V3(0.4, d, d), ut.CFrame * CF(0, s.Y * 0.5 + 0.08, 0.02) * ANG(0, 0, RAD(90)), skin, "Cylinder", skinMat)
		neck:SetAttribute("Base", true)
		if sp.female and not shirt then
			-- sports top with a bare midriff (the upper torso itself is coloured as the top)
			local mid = mk(folder, ut, "Midriff", V3(s.X * 1.01, s.Y * 0.32, s.Z * 1.02), ut.CFrame * CF(0, -0.34 * s.Y, 0), skin, "Block", skinMat)
			mid:SetAttribute("Base", true)
		end
		if lod >= 3 and not sp.female then
			local lvl = sp.lv.neckSCM
			for side = -1, 1, 2 do
				local size = V3(0.2 * d * (1 + 0.5 * lvl), 0.46, 0.22 * d * (1 + 0.5 * lvl))
				local cf = ut.CFrame * CF(side * 0.28 * d, s.Y * 0.5 + 0.1, -0.39 * d + 0.02) * ANG(RAD(24), 0, RAD(-16 * side))
				local p = mk(folder, ut, "NeckSCM", size, cf, skin, "Ellipsoid", skinMat)
				tagMuscle(p, "neckSCM", side, 1)
				made["NeckSCM" .. side] = p
			end
		end
		-- collarbones: a lean boxer's clavicles catch the light
		if lod >= 3 and fat < 13 and not sp.female and not shirt then
			for side = -1, 1, 2 do
				local cf = ut.CFrame * CF(side * 0.25 * s.X, 0.47 * s.Y, -s.Z / 2 + 0.006) * ANG(0, 0, RAD(6 * side))
				local p = mk(folder, ut, "Clavicle", V3(0.4 * s.X, 0.05 * s.Y, 0.05), cf, lerpColor(skin, WHITE, 0.07), "Ellipsoid", skinMat, math.clamp(0.9 - (13 - fat) * 0.08, 0.35, 0.9))
				p:SetAttribute("Groove", true)
			end
		end
	end

	-- 3) separation grooves (full detail, lean): stronger on elite / lean physiques, fade with fat
	if cfg.grooves and def > 0.3 and not shirt then
		local alpha = math.clamp(1 - 0.55 * def * pv.groove, 0.3, 0.95)
		local gcol = darken(skin, 0.74)
		for _, g in ipairs(GROOVES) do
			if (g.sex == nil or (g.sex == "f") == sp.female) and def > (g.min or 0) then
				for _, side in ipairs(sidesOf(g)) do
					local anchor = anchorFor(g.on, side)
					if anchor then
						local cf, size, pos = place(anchor, side, g, 0, { soft = 1, flat = 1, elong = 1 })
						if not (sp.female and g.on == "UT" and pos.Y > -0.18 * anchor.Size.Y) then
							local p = mk(folder, anchor, g.n, size, cf, gcol, "Ellipsoid", skinMat, alpha)
							p:SetAttribute("Groove", true)
						end
					end
				end
			end
		end
		if ut and lod >= 3 then
			local s = ut.Size
			local p = mk(folder, ut, "Navel", V3(0.04 * s.X, 0.05 * s.Y, 0.05), ut.CFrame * CF(0, -0.5 * s.Y, -s.Z / 2 + 0.004), darken(skin, 0.6), "Ellipsoid", skinMat, 0.25)
			p:SetAttribute("Groove", true)
		end
	end

	-- 4) fat layers: love handles, soft chest, arm fat, belly (physique bellyAt), hip shape slider
	local function fatPart(name, anchor, side, m, kk, color, mat)
		local cf, size, pos = place(anchor, side, m, kk, { soft = 1, flat = 1, elong = 1 })
		local p = mk(folder, anchor, name, size, cf, color or skin, "Ellipsoid", mat or skinMat)
		p:SetAttribute("Fat", true)
		return p, pos, size
	end
	local function fatColor(on, pos, anchor)
		local c, mat = dress(on, pos, anchor, nil)
		return c, mat
	end
	if ut then
		local s = ut.Size
		if fat >= BF.loveHandlesAt then
			local kk = math.clamp((fat - BF.loveHandlesAt) / 10, 0, 1)
			for side = -1, 1, 2 do
				local m = { ax = "O", u = 0.1, v = -0.44, a = 0.85, b = 0.3, t = 0.3, p0 = 0.006, p1 = 0.07 * pv.waist }
				local c, mat = fatColor("UT", V3(0, -0.44 * s.Y, 0), ut)
				local _, pos, size = fatPart("LoveHandle", ut, side, m, kk, c, mat)
				env.UT.x = math.max(env.UT.x, (math.abs(pos.X) + size.X / 2) / (s.X / 2))
			end
		end
		if fat >= BF.softChestAt and not sp.female then
			local kk = math.clamp((fat - BF.softChestAt) / 8, 0, 1)
			for side = -1, 1, 2 do
				local m = { ax = "F", u = 0.24, v = 0.0, a = 0.38, b = 0.22, t = 0.4, p0 = 0.02, p1 = 0.08, r = { 0, 0, 8 } }
				local c, mat = fatColor("UT", V3(0, 0, 0), ut)
				fatPart("ChestSoft", ut, side, m, kk, c, mat)
			end
		end
		local bellyAt = ph.bellyAt or BF.bellyAt
		if fat >= bellyAt then
			local kk = math.clamp((fat - bellyAt) / 8, 0, 1)
			local m = { ax = "F", u = 0, v = -0.36, a = 0.78, b = 0.56, t = 0.6, p0 = 0.03, p1 = 0.32 }
			local c, mat = fatColor("UT", V3(0, -0.36 * s.Y, 0), ut)
			local _, pos, size = fatPart("Belly", ut, 0, m, kk, c, mat)
			env.UT.zf = math.max(env.UT.zf, (size.Z / 2 - pos.Z) / (s.Z / 2))
		end
	end
	if fat >= BF.armFatAt then
		local kk = math.clamp((fat - BF.armFatAt) / 8, 0, 1)
		for side = -1, 1, 2 do
			local ua = anchorFor("UA", side)
			if ua then
				local c, mat = fatColor("UA", V3(), ua)
				fatPart("ArmFat", ua, side, { ax = "B", u = 0, v = -0.12, a = 0.66, b = 0.5, t = 0.5, p0 = 0.02, p1 = 0.08 }, kk, c, mat)
			end
		end
	end
	-- the waist slider used to add a trunk-coloured "Oblique"; it is a hip shape (anatomical obliques above)
	local lt = part(model, "LowerTorso")
	local waist = tonumber(sl.waist) or 0
	if lt and waist > 0.2 then
		local s = lt.Size
		for side = -1, 1, 2 do
			local p = mk(folder, lt, "HipShape", V3(0.3 * s.X * waist * pv.waist, s.Y * 1.4, 0.8 * s.Z), lt.CFrame * CF(side * 0.48 * s.X, 0.25 * s.Y, 0), trousers or trunks, "Ellipsoid", trousers and FABRIC or SMOOTH)
			p:SetAttribute("Fat", true)
			p:SetAttribute("Cloth", true)
		end
	end

	-- 5) road grime on the shins and forearms (cleared by the shower: the attribute drops to 0)
	if sp.grime >= 0.1 and lod >= 2 then
		local dirt = Color3.fromRGB(96, 80, 60)
		for side = -1, 1, 2 do
			for _, on in ipairs({ "LL", "LA" }) do
				local anchor = anchorFor(on, side)
				if anchor and not (trousers and on == "LL") then
					local cf, size = place(anchor, side, { ax = "F", u = 0, v = on == "LL" and 0.1 or -0.1, a = 0.95, b = 0.7, t = 0.3, p = 0.012 }, 0, { soft = 1, flat = 1, elong = 1 })
					local p = mk(folder, anchor, "Grime", size, cf, dirt, "Ellipsoid", SMOOTH, math.clamp(1 - 0.5 * sp.grime, 0.5, 0.95))
					p:SetAttribute("Grime", true)
				end
			end
		end
	end

	-- 6) veins (Beams; no parts). Base transparency from VeinLevel; the client lowers it with pump / strain.
	if cfg.veins and not shirt then
		local vcol = darken(lerpColor(skin, Color3.fromRGB(70, 90, 140), 0.3), 0.82)
		for _, v in ipairs(VEINS) do
			if not (v.maxFat and fat >= v.maxFat) then
				for _, side in ipairs((LIMB[v.on] or v.mirror) and { -1, 1 } or { 0 }) do
					local anchor = anchorFor(v.on, side)
					local host = made[v.host .. side] or made[v.host .. "0"]
					if anchor and host then
						local s = anchor.Size
						local rec = recs[anchor] or {}
						local pts = {}
						for i, pt in ipairs(v.pts) do
							local local3
							if v.ax == "F" or v.ax == "B" then
								local x, y = side * pt[1] * s.X, pt[2] * s.Y
								local n = v.ax == "F" and -1 or 1
								local h = faceHeight(rec, s, v.ax, x, y)
								local3 = V3(x, y, n * (s.Z / 2 + h + 0.022))
							else
								local z, y = pt[1] * s.Z, pt[2] * s.Y
								local n = (v.ax == "O" and 1 or -1) * (side == 0 and 1 or side)
								local h = faceHeight(rec, s, v.ax, z, y)
								local3 = V3(n * (s.X / 2 + h + 0.022), y, z)
							end
							pts[i] = host.CFrame:Inverse() * (anchor.CFrame * local3)
						end
						local base = math.clamp(1 - sp.vein * v.k * 0.85, 0.15, 1)
						for i = 1, #pts - 1 do
							veinBeam(host, pts[i], pts[i + 1], v.w, (i % 2 == 0) and -0.04 or 0.04, vcol, base, v.id)
						end
					end
				end
			end
		end
		-- jugular over each SCM: shows under strain (clinch, hurt, get-up) and big efforts
		for side = -1, 1, 2 do
			local scm = made["NeckSCM" .. side]
			if scm then
				local sz = scm.Size
				local base = math.clamp(1 - sp.vein * 0.3, 0.6, 1)
				veinBeam(scm, V3(side * sz.X * 0.15, sz.Y * 0.38, -sz.Z * 0.5 - 0.012), V3(-side * sz.X * 0.1, -sz.Y * 0.38, -sz.Z * 0.5 - 0.012), 0.04, 0.03, vcol, base, "neckSCM")
			end
		end
	end

	-- envelope for attire / robe sizing (read back by readEnv when this folder is cached)
	for _, fam in ipairs(ENV_FAMS) do
		local e = env[fam]
		folder:SetAttribute("Env" .. fam, V3(q(e.x, 0.01), q(e.zf, 0.01), q(e.zb, 0.01)))
		folder:SetAttribute("EnvTop" .. fam, q(e.y, 0.01))
	end
	Kit.seal(model, "Muscles", key)
	return readEnv(model)
end

------------------------------------------------------------------------
-- Colours of the R15 parts (skin, trunks, shoes, outfits)
------------------------------------------------------------------------
local function shoeColorOf(app, gear)
	local a = app.attire or {}
	local c = Looks.Color(a.shoes, Color3.fromRGB(25, 25, 25))
	local cond = gear.shoesCond or 100
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
	local shirt, trousers = outfitColors(app, opts.outfit)
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
					-- officials wear polished black shoes, cornermen black trainers
					p.Color = Color3.fromRGB(20, 20, 22)
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
	if app.gender == 2 and not shirt then
		local ut = model:FindFirstChild("UpperTorso")
		if ut then
			ut.Color = Looks.Color(a.trim, WHITE)
			ut.Material = SMOOTH
		end
	end
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") or c:IsA("Accessory") then
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
				if lod >= 2 then
					for _, ex in ipairs({ -1, 1 }) do
						mk(folder, ll, "Eyelets", V3(0.035, s.Y * (h - 0.14), 0.03), ll.CFrame * CF(ex * s.X * 0.15, s.Y * (cy + 0.03), fz - 0.004), eyeletColor, "Block", metal)
					end
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
				if cfg.laces ~= "none" then
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

local function outfitBuild(folder, model, app, opts, sp)
	local outfit = sp.outfit
	local shirt = outfitColors(app, outfit)
	local lod = sp.lod
	local ut, lt, head = part(model, "UpperTorso"), part(model, "LowerTorso"), part(model, "Head")
	local black = Color3.fromRGB(16, 16, 18)
	if ut then
		local s = ut.Size
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
	local spT, spF, spB = sponsorOf(opts.sponsorTrunks)
	local key = Kit.sig("A3", a, opts.waistText or "", spT or "", spF or "", spB or "", sp.outfit, sp.detail, gear.shoes, gear.shoesCond >= 60, gear.shoesCond >= 40,
		eUL, topRel, opts.name or "", app.gender, sizesOf(model, ATTIRE_PARTS))
	if Kit.cached(model, "Attire", key) then
		return
	end
	local folder = getFolder(model, "Attire")
	if sp.outfit == "referee" or sp.outfit == "cornerman" then
		outfitBuild(folder, model, app, opts, sp)
		Kit.seal(model, "Attire", key)
		return
	end
	local trunks = Looks.Color(a.trunks, Color3.fromRGB(200, 25, 30))
	local trim = Looks.Color(a.trim, WHITE)
	if lt then
		local s = lt.Size
		local band = mk(folder, lt, "Waistband", V3(s.X * 1.1, s.Y * 0.55, s.Z * 1.18), lt.CFrame * CF(0, s.Y * 0.28, 0), trim, "Block", SMOOTH)
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
				mk(folder, ul, "Stripe", V3(0.05, us.Y * panelH, dZ * 0.38), ul.CFrame * CF(px, us.Y * panelY, zc), trim, "Block", SMOOTH)
			elseif a.trunkStyle == "Pro" then
				-- pro trunks: trim hem at the leg opening and a trim side panel with white stripes
				mk(folder, ul, "Hem", V3(us.X * (wX + 0.02), us.Y * 0.1, dZ + 0.024), ul.CFrame * CF(0, us.Y * (low + 0.05), zc), trim, "Block", SMOOTH)
				mk(folder, ul, "SidePanel", V3(0.05, us.Y * panelH, dZ * 0.52), ul.CFrame * CF(px, us.Y * panelY, zc), trim, "Block", SMOOTH)
				if sp.lod >= 2 then
					for k = -1, 1 do
						mk(folder, ul, "SideStripe", V3(0.062, us.Y * (panelH - 0.02), dZ * 0.07), ul.CFrame * CF(px + sign * 0.006, us.Y * panelY, zc + k * dZ * 0.16), white, "Block", SMOOTH)
					end
				end
			end
			-- sponsor patch on the front of the right leg (left leg carries the boxer's own colours)
			if spT and sign > 0 and sp.lod >= 2 then
				textPatch(folder, ul, "SponsorPatch", V3(us.X * 0.62, us.Y * 0.2, 0.02), ul.CFrame * CF(0, us.Y * (low + h * 0.42), zc - dZ / 2 - 0.012), spT, spF, Enum.NormalId.Front, "GothamBlack", spB)
			end
		end
		if ll and a.trunkStyle == "Long" then
			local s = ll.Size
			mk(folder, ll, "TrunkLeg", V3(s.X * 1.06, s.Y * 0.25, s.Z * 1.06), ll.CFrame * CF(0, s.Y * 0.38, 0), trunks, "Block", SMOOTH)
		end
	end
	shoesBuild(folder, model, app, opts, gear, sp, env)
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
			wet(mk(folder, hand, "Wrap", hs * V3(1.08, 1.4, 1.08), hand.CFrame, wc, "Block", FABRIC), "wrap")
			if lod >= 2 then
				-- knuckle padding: a thin cotton ridge, or a moulded gel pad on gel wraps
				local kp = gel and V3(hs.X * 0.95, 0.26, hs.Z * 1.06) or V3(hs.X * 0.9, 0.18, hs.Z * 1.02)
				local kc = gel and darken(wc, 0.72) or wc
				wet(mk(folder, hand, "WrapKnuckle", kp, hand.CFrame * CF(sign * 0.05, -hs.Y * 0.62, 0), kc, "Ellipsoid", gel and SMOOTH or FABRIC), "wrap")
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
			wet(mk(folder, la, "WrapWrist", V3(s.X * 1.06, s.Y * 0.3, s.Z * 1.06), la.CFrame * CF(0, -s.Y * 0.36, 0), wc, "Block", FABRIC), "wrap")
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
	local material, refl = LEATHER, 0
	if finish == "Matte" then
		material = SMOOTH
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
	local ozK = 0.88 + 0.015 * (oz - 8)
	local shape = brand.shape or {}
	local wK, lK, kK, cK = shape.width or 1, shape.len or 1, shape.knuckle or 1, shape.cuff or 1
	local wrapC = wrapColors(app, gear)
	local tape = opts.fightNight == true
	for _, side in ipairs({ "Left", "Right" }) do
		local sign = side == "Left" and -1 or 1
		local hand, la = part(model, side .. "Hand"), part(model, side .. "LowerArm")
		if hand then
			local base = math.max(hand.Size.X, hand.Size.Z)
			local gsize = V3(base * 1.38 * wK, base * 1.52 * lK, base * 1.46 * wK) * ozK
			local W, L, D = gsize.X, gsize.Y, gsize.Z
			local gcf = hand.CFrame * CF(0, -hand.Size.Y * 0.2, -0.05)
			local glove = mk(folder, hand, side == "Left" and "GloveL" or "GloveR", gsize, gcf, main, "Ellipsoid", material)
			glove.Reflectance = refl
			wet(glove, "glove", refl)
			-- bulbous striking surface over the knuckles
			local knuckle = mk(folder, hand, "KnucklePad", V3(W * 0.84, L * 0.6, D * 0.92) * V3(kK, 1, kK), gcf * CF(sign * W * 0.08, -L * 0.2, 0), main, "Ellipsoid", material)
			knuckle.Reflectance = refl
			wet(knuckle, "glove", refl)
			-- the thumb carries the brand's palm tone (the palm side of the glove)
			local thumb = mk(folder, hand, "Thumb", V3(W * 0.36, L * 0.48, D * 0.36), gcf * CF(-sign * W * 0.38, L * 0.04, -D * 0.3) * ANG(RAD(-10), 0, RAD(12 * sign)), lerpColor(main, palmColor, 0.6), "Ellipsoid", material)
			thumb.Reflectance = refl
			wet(thumb, "glove", refl)
			if lod >= 3 then
				-- piping / stitching: flattened discs in the seam plane between back and palm; only their rims
				-- show, as a welt line and a stitch line round the glove's outline
				if piping then
					mk(folder, hand, "Piping", V3(0.035, L * 1.06, D * 1.04), gcf * CF(-sign * W * 0.05, -L * 0.01, 0), piping, "Ellipsoid", SMOOTH)
				end
				if stitch ~= "Hidden" then
					mk(folder, hand, "StitchRing", V3(0.02, L * 1.035, D * 1.02), gcf * CF(sign * W * 0.03, -L * 0.005, 0), stitchColor, "Ellipsoid", SMOOTH)
				end
				-- a leather crease at the thumb as the glove breaks in
				if cond < 70 then
					mk(folder, hand, "Crease", V3(0.02, L * 0.26, 0.02), gcf * CF(-sign * W * 0.28, L * 0.06, -D * 0.47) * ANG(0, 0, RAD(25 * sign)), darken(main, 0.6), "Block", SMOOTH, 0.45)
				end
			end
			if (stitch == "Double" or (custom.stitching and g.stitching == "Double")) and lod >= 2 then
				mk(folder, hand, "Stitch", V3(0.03, 0.03, D * 0.72), gcf * CF(sign * W * 0.47, -L * 0.1, 0), stitchColor)
			end
			if brand.targetArea and lod >= 2 then
				-- amateur competition glove: white target area over the knuckles
				mk(folder, hand, "TargetArea", V3(W * 0.6, L * 0.34, D * 0.78), gcf * CF(sign * W * 0.16, -L * 0.3, 0), Color3.fromRGB(245, 245, 245), "Ellipsoid", SMOOTH)
			end
			-- logo on the back of the glove: the player's glyph, else the brand monogram
			local glyph
			if custom.logo and g.logo and g.logo ~= "None" then
				glyph = Catalog.LogoGlyphs[g.logo]
				if g.logo == "Initials" then
					glyph = initials(opts.name)
				elseif g.logo == "Flag" then
					glyph = tostring(opts.nat or "USA"):sub(1, 3):upper()
				end
			elseif cfg.wordmarks and (brand.glyph or "") ~= "" then
				glyph = brand.glyph
			end
			if glyph and glyph ~= "" and lod >= 2 then
				textPatch(folder, hand, "Logo", V3(0.02, L * 0.42, D * 0.55), gcf * CF(sign * (W * 0.5 + 0.012), L * 0.12, 0), glyph, trim,
					sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left, brand.font)
			end
			-- wear: a scuffed knuckle, torn foam and gym duct tape on beaten-up gloves, a sweat mark
			if cond < 70 and lod >= 2 then
				mk(folder, hand, "KnuckleScuff", V3(W * 0.45, L * 0.3, D * 0.62), gcf * CF(sign * W * 0.27, -L * 0.33, 0), lerpColor(main, Color3.fromRGB(205, 195, 180), 0.45), "Ellipsoid", SMOOTH, math.clamp(0.25 + cond / 140, 0.25, 0.75))
			end
			if cond < 35 and lod >= 2 then
				mk(folder, hand, "FoamTear", V3(W * 0.18, L * 0.12, D * 0.2), gcf * CF(sign * W * 0.4, -L * 0.34, D * 0.1), Color3.fromRGB(215, 195, 140), "Ellipsoid", Enum.Material.Sand)
			end
			if cond < 40 and (gloveDef.id == "Worn" or gloveDef.id == "Cheap") then
				mk(folder, hand, "DuctTape", V3(W * 0.88, 0.13, D * 0.88), gcf * CF(0, -L * 0.27, 0), Color3.fromRGB(150, 150, 155), "Ellipsoid", FABRIC)
			end
			if cond < 30 then
				local sm = mk(folder, hand, "SweatMark", gsize * V3(0.1, 0.45, 0.5), gcf * CF(sign * W * 0.44, -L * 0.2, 0), darken(main, 0.7), "Ellipsoid", material, 0.4)
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
			local cuffLen = s.Y * 0.45 * cK
			local cuffCF = la.CFrame * CF(0, -s.Y * 0.5 + cuffLen * 0.5 + s.Y * 0.03, 0)
			local cuff = mk(folder, la, "Cuff", V3(s.X * 1.12, cuffLen, s.Z * 1.12), cuffCF, main, "Block", material)
			wet(cuff, "glove", refl)
			mk(folder, la, "CuffTrim", V3(s.X * 1.15, s.Y * 0.13, s.Z * 1.15), cuffCF * CF(0, cuffLen * 0.5 - s.Y * 0.08, 0), trim, "Block", material)
			-- hand wraps peeking out above the cuff
			if lod >= 3 then
				mk(folder, la, "WrapPeek", V3(s.X * 1.04, 0.09, s.Z * 1.04), cuffCF * CF(0, cuffLen * 0.5 + 0.03, 0), wrapC, "Block", FABRIC)
			end
			local sideFace = sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left
			local ox = sign * (s.X * 0.56 + 0.012)
			if tape then
				-- fight night: laces / strap taped over and signed by the commission inspector
				mk(folder, la, "Tape", V3(s.X * 1.17, cuffLen * 0.5, s.Z * 1.17), cuffCF * CF(0, -cuffLen * 0.1, 0), Color3.fromRGB(246, 246, 242), "Block", FABRIC)
				if cfg.wordmarks then
					local h = 0
					for c in tostring(opts.name or "x"):gmatch(".") do
						h += string.byte(c)
					end
					local inspectors = { "R.M.", "J.T.", "D.K.", "L.V.", "A.O." }
					textPatch(folder, la, "Signature", V3(0.02, cuffLen * 0.36, s.Z * 0.8), cuffCF * CF(sign * (s.X * 0.585 + 0.012), -cuffLen * 0.1, 0),
						inspectors[h % #inspectors + 1] .. " ok", Color3.fromRGB(30, 40, 120), sideFace, "PermanentMarker")
				end
			elseif brand.closure == "lace" then
				-- lace-up: lace panel on the palm side with criss-crossed laces
				if lod >= 2 then
					mk(folder, la, "LacePanel", V3(0.03, cuffLen * 0.9, s.Z * 0.4), cuffCF * CF(-sign * (s.X * 0.56 + 0.008), 0, 0), darken(main, 0.85), "Block", material)
				end
				if cfg.laces == "full" then
					for _, rot in ipairs({ 1, -1 }) do
						mk(folder, la, "GloveLace", V3(0.03, cuffLen * 0.8, 0.035), cuffCF * CF(-sign * (s.X * 0.56 + 0.026), 0, 0) * ANG(rot * RAD(24), 0, 0), Color3.fromRGB(240, 240, 235), "Block", SMOOTH)
					end
				end
			elseif lod >= 2 then
				-- velcro: wide hook-and-loop strap round the cuff with a pull tab
				mk(folder, la, "Strap", V3(s.X * 1.17, cuffLen * 0.42, s.Z * 1.17), cuffCF * CF(0, -cuffLen * 0.05, 0), strapColor, "Block", SMOOTH)
				if lod >= 3 then
					mk(folder, la, "StrapTab", V3(0.05, cuffLen * 0.3, s.Z * 0.3), cuffCF * CF(sign * (s.X * 0.6 + 0.02), -cuffLen * 0.05, s.Z * 0.2), darken(strapColor, 0.7), "Block", SMOOTH)
				end
			end
			-- cuff branding: embroidery (outer side), maker's plate (front), wordmark
			local outerTaken = tape
			if custom.embroidery then
				local text = side == "Left" and (g.embName and opts.name or "") or (g.embNick and opts.nick or "")
				if text ~= "" and not tape then
					textPatch(folder, la, "Embroidery", V3(0.02, s.Y * 0.3, s.Z * 1.05), cuffCF * CF(ox, 0, 0), text:upper(), trim, sideFace)
					outerTaken = true
				end
			end
			if brand.plate and lod >= 2 then
				local big = brand.beltPlate == true
				local plateCF = cuffCF * CF(0, cuffLen * 0.05, -s.Z * 0.56 - 0.02)
				mk(folder, la, big and "BeltPlate" or "Plate", V3(s.X * (big and 0.72 or 0.52), cuffLen * (big and 0.46 or 0.32), 0.04), plateCF, big and GOLD or Color3.fromRGB(200, 200, 205), "Block", Enum.Material.Foil)
				if cfg.wordmarks then
					textPatch(folder, la, "PlateText", V3(s.X * 0.5, cuffLen * 0.26, 0.02), plateCF * CF(0, 0, -0.032), big and (brand.glyph or "") or initials(opts.name), big and Color3.fromRGB(60, 40, 10) or Color3.fromRGB(30, 30, 34), Enum.NormalId.Front, brand.font)
				end
			elseif cfg.wordmarks and (brand.wordmark or "") ~= "" and outerTaken then
				textPatch(folder, la, "Wordmark", V3(s.X * 0.95, cuffLen * 0.26, 0.02), cuffCF * CF(0, cuffLen * 0.12, -s.Z * 0.56 - 0.012), brand.wordmark, rgb(brand.wordColor, contrast(main)), Enum.NormalId.Front, brand.font)
			end
			if cfg.wordmarks and (brand.wordmark or "") ~= "" and not outerTaken then
				textPatch(folder, la, "Wordmark", V3(0.02, cuffLen * 0.26, s.Z * 0.95), cuffCF * CF(ox, cuffLen * 0.12, 0), brand.wordmark, rgb(brand.wordColor, contrast(main)), sideFace, brand.font)
			end
		end
	end
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
	local key = Kit.sig("H3", mode, sp.detail, gear.gloves, gear.wraps, q(gear.glovesCond or 100, 5), q(gear.wrapsCond or 100, 10), app.gloves, a.wraps, a.wrapPattern or "", a.trim, a.trunks,
		opts.name or "", opts.nick or "", opts.nat or "", opts.fightNight == true, sizesOf(model, HAND_PARTS))
	if Kit.cached(model, "Hands", key) then
		return
	end
	local folder = getFolder(model, "Hands")
	if mode == "wraps" then
		wrapsBuild(folder, model, app, gear, opts, sp)
	elseif mode ~= "bare" then
		glovesBuild(folder, model, app, gear, opts, sp)
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
	local env = readEnv(model)
	local color = Looks.Color(a.robe, Color3.fromRGB(200, 25, 30))
	local trim = robeId == "Champion" and GOLD or Looks.Color(a.robeTrim, WHITE)
	-- satin robes (a soft sheen); the hooded robe is heavier terry cloth
	local mat = robeId == "Hooded" and FABRIC or SMOOTH
	local refl = robeId == "Hooded" and 0 or 0.04
	local ut, lt = part(model, "UpperTorso"), part(model, "LowerTorso")
	-- the robe is sized around the muscles (pecs, lats, traps, delts) so nothing pokes through it
	local eUT, eUA = env.UT, env.UA
	if ut then
		local s = ut.Size
		local rx = math.max(1.16, eUT.x + 0.08)
		local rz = math.max(1.25, math.max(eUT.zf, eUT.zb) + 0.1)
		local ry = math.clamp(eUT.y + 0.04, 1.06, 1.32)
		local shell = mk(folder, ut, "RobeTorso", s * V3(rx, ry, rz), ut.CFrame * CF(0, s.Y * (ry - 1.06) * 0.25, 0), color, "Block", mat)
		shell.Reflectance = refl
		for _, side in ipairs({ -1, 1 }) do
			mk(folder, ut, "Lapel", V3(0.25, s.Y * 1.05, 0.05), ut.CFrame * CF(side * 0.15, 0, -s.Z * rz * 0.5 - 0.03) * ANG(0, 0, RAD(-12 * side)), trim, "Block", mat)
		end
		local nick = opts and opts.nick or ""
		if nick ~= "" then
			textPatch(folder, ut, "RobeName", V3(s.X * 1.0, s.Y * 0.35, 0.02), shell.CFrame * CF(0, s.Y * 0.15, s.Z * rz * 0.5 + 0.012), nick:upper(), trim, Enum.NormalId.Back)
		end
		local spT, spF, spB = sponsorOf(opts and opts.sponsorRobe)
		if spT then
			textPatch(folder, ut, "SponsorPatch", V3(s.X * 0.7, s.Y * 0.16, 0.02), shell.CFrame * CF(0, -s.Y * 0.22, s.Z * rz * 0.5 + 0.012), spT, spF, Enum.NormalId.Back, "GothamBlack", spB)
		end
		if robeId == "Hooded" or robeId == "Champion" then
			mk(folder, ut, "Hood", V3(s.X * 0.75, s.Y * 0.55, s.Z * 0.8), ut.CFrame * CF(0, s.Y * 0.55 + (ry - 1.06) * s.Y * 0.4, s.Z * 0.45), color, "Ellipsoid", mat)
		end
	end
	if lt then
		local s = lt.Size
		mk(folder, lt, "RobeSkirt", V3(s.X * 1.25, 2.2, s.Z * 1.35), lt.CFrame * CF(0, -1.0, 0), color, "Block", mat).Reflectance = refl
		mk(folder, lt, "RobeBelt", V3(s.X * 1.28, 0.22, s.Z * 1.38), lt.CFrame * CF(0, 0.1, 0), trim, "Block", mat)
	end
	local sx = math.max(1.2, eUA.x + 0.1)
	local sz = math.max(1.2, math.max(eUA.zf, eUA.zb) + 0.1)
	local sy = math.clamp(eUA.y, 1.02, 1.2)
	for _, side in ipairs({ "Left", "Right" }) do
		local ua, la = part(model, side .. "UpperArm"), part(model, side .. "LowerArm")
		if ua then
			mk(folder, ua, "Sleeve", ua.Size * V3(sx, sy, sz), ua.CFrame * CF(0, ua.Size.Y * (sy - 1.02) * 0.5, 0), color, "Block", mat).Reflectance = refl
		end
		if la then
			mk(folder, la, "SleeveLow", la.Size * V3(1.22, 0.7, 1.22), la.CFrame * CF(0, la.Size.Y * 0.12, 0), color, "Block", mat).Reflectance = refl
			mk(folder, la, "SleeveTrim", V3(la.Size.X * 1.25, 0.1, la.Size.Z * 1.25), la.CFrame * CF(0, -la.Size.Y * 0.22, 0), trim, "Block", mat)
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
	local hands = look:FindFirstChild("Hands")
	if hands then
		for _, p in ipairs(hands:GetChildren()) do
			if p:IsA("BasePart") then
				local kind = p:GetAttribute("Wet")
				local bc = p:GetAttribute("BaseColor")
				if kind == "glove" and typeof(bc) == "Color3" then
					-- sweat darkens leather and adds a little shine
					p.Color = bc:Lerp(darken(bc, 0.8), level * 0.7)
					p.Reflectance = math.min((p:GetAttribute("BaseRefl") or 0) + 0.05 * level, 0.27)
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

-- body shots: translucent bruising over the ribs (dmg.ribsL / ribsR). Adds to BoxerLook/Damage after
-- Head.SetDamage (which recreates the folder); never destroys the face damage. Partial tables are fine.
function Body.SetDamage(model, app, dmg)
	local look = model:FindFirstChild("BoxerLook")
	local ut = part(model, "UpperTorso")
	if not (look and ut) then
		return
	end
	local folder = look:FindFirstChild("Damage")
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name == "RibBruise" then
				c:Destroy()
			end
		end
	end
	if type(dmg) ~= "table" then
		return
	end
	local skin = Looks.Color(Looks.SkinTones[(app and app.skin) or 5])
	local s = ut.Size
	for _, e in ipairs({ { -1, "ribsL" }, { 1, "ribsR" } }) do
		local side, v = e[1], math.clamp(tonumber(dmg[e[2]]) or 0, 0, 1)
		if v > 0.08 then
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "Damage"
				folder.Parent = look
			end
			local c = lerpColor(skin, bruiseColor(skin, dmg.age), 0.75)
			-- the bruise wraps the lower ribs from the flank round to the front
			mk(folder, ut, "RibBruise", V3((0.28 + 0.1 * v) * s.X, (0.26 + 0.14 * v) * s.Y, s.Z * 1.06), ut.CFrame * CF(side * 0.38 * s.X, -0.14 * s.Y, -0.02), c, "Ellipsoid", SMOOTH, math.clamp(0.78 - 0.4 * v, 0.35, 0.8))
			if v > 0.5 then
				mk(folder, ut, "RibBruise", V3(0.16 * s.X, 0.14 * s.Y, s.Z * 1.08), ut.CFrame * CF(side * 0.42 * s.X, -0.18 * s.Y, -0.02), darken(c, 0.85), "Ellipsoid", SMOOTH, math.clamp(0.85 - 0.5 * v, 0.4, 0.8))
			end
		end
	end
end

------------------------------------------------------------------------
-- Build steps (called by Builder.Cosmetics) and helpers shared with Builder
------------------------------------------------------------------------
Body.Colors = colorBody -- (model, app, gear, opts)
Body.Muscles = musclesBuild -- (model, app, build, opts?, spec?, gear?) -> envelope
Body.Attire = attireBuild -- (model, app, opts, gear, spec?, envelope?)
Body.Hands = handsBuild -- (model, app, gear, opts, spec?)
Body.Resolve = resolve -- (app, build, opts, model?) -> spec { ph, lv, fat, def, vein, bulk, detail, ... }
Body.Gear = gearOf -- (gear) -> gear with the section 4 defaults
Body.PV = PV
Body.frameOf = frameOf -- (app)
Body.avgDev = avgDev -- (build, keys)

return Body
