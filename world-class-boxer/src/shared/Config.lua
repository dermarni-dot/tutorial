-- Config: core tunable data for "Become a World Class Boxer"
local Config = {}

Config.GameName = "Become a World Class Boxer"
Config.DataStoreName = "WorldClassBoxer_v2"
Config.DataVersion = 2
Config.RoundSeconds = 60 -- real-time length of one fight round
Config.RestSeconds = 7 -- between rounds
Config.SparRoundSeconds = 45
Config.StatCap = 99
Config.WorldPerClass = 30 -- AI boxers per weight class (9 classes = 270 boxers)
Config.GainScale = 1.35 -- global training gain multiplier

Config.StatKeys = {
	"PunchSpeed", "Power", "Endurance", "Stamina", "Footwork", "HeadMovement",
	"Blocking", "Countering", "RingIQ", "Chin", "Reflexes", "Recovery",
}
Config.StatNames = {
	PunchSpeed = "Punch Speed", Power = "Knockout Power", Endurance = "Endurance",
	Stamina = "Stamina", Footwork = "Footwork", HeadMovement = "Head Movement",
	Blocking = "Blocking", Countering = "Countering", RingIQ = "Ring IQ",
	Chin = "Chin", Reflexes = "Reflexes", Recovery = "Recovery",
}
Config.MentalKeys = { "Confidence", "Discipline", "Aggression", "Focus", "Composure" }

Config.MuscleKeys = { "chest", "shoulders", "arms", "back", "legs", "core", "neck" }
Config.MuscleNames = {
	chest = "Chest", shoulders = "Shoulders", arms = "Arms", back = "Back",
	legs = "Legs", core = "Core", neck = "Neck",
}

-- Sub-muscles. Each belongs to one coarse group above; the group value is the share-weighted
-- sum of its parts (Config.SyncGroups), so everything that reads the 7 groups (weight, fight
-- power, Builder.Scales, Hub bars, lift loads) keeps working. Parts are stored as FLAT numeric
-- keys in profile.body next to the groups (Career.Summary rounds every body value, so no
-- nested tables there). Part ids never equal a group id.
Config.MuscleParts = {
	{ id = "pecs", group = "chest", share = 0.65, name = "Chest (Lower/Mid Pecs)" },
	{ id = "upperChest", group = "chest", share = 0.35, name = "Upper Chest" },
	{ id = "frontDelt", group = "shoulders", share = 0.35, name = "Front Delts" },
	{ id = "sideDelt", group = "shoulders", share = 0.4, name = "Side Delts" },
	{ id = "rearDelt", group = "shoulders", share = 0.25, name = "Rear Delts" },
	{ id = "biceps", group = "arms", share = 0.4, name = "Biceps" },
	{ id = "triceps", group = "arms", share = 0.4, name = "Triceps" },
	{ id = "forearms", group = "arms", share = 0.2, name = "Forearms" },
	{ id = "lats", group = "back", share = 0.4, name = "Lats" },
	{ id = "traps", group = "back", share = 0.25, name = "Traps" },
	{ id = "upperBack", group = "back", share = 0.2, name = "Upper Back" },
	{ id = "lowerBack", group = "back", share = 0.15, name = "Lower Back" },
	{ id = "abs", group = "core", share = 0.4, name = "Abs" },
	{ id = "lowerAbs", group = "core", share = 0.2, name = "Lower Abs" },
	{ id = "obliques", group = "core", share = 0.3, name = "Obliques" },
	{ id = "serratus", group = "core", share = 0.1, name = "Serratus" },
	{ id = "quads", group = "legs", share = 0.4, name = "Quads" },
	{ id = "hamstrings", group = "legs", share = 0.2, name = "Hamstrings" },
	{ id = "glutes", group = "legs", share = 0.2, name = "Glutes" },
	{ id = "calves", group = "legs", share = 0.2, name = "Calves" },
	{ id = "neckSCM", group = "neck", share = 1.0, name = "Neck" },
}
Config.MusclePartNames = {} -- part id -> display name
Config.MusclePartGroup = {} -- part id -> coarse group key
Config.MuscleGroupParts = {} -- group key -> { part defs in display order }
for _, k in ipairs(Config.MuscleKeys) do
	Config.MuscleGroupParts[k] = {}
end
for _, p in ipairs(Config.MuscleParts) do
	Config.MusclePartNames[p.id] = p.name
	Config.MusclePartGroup[p.id] = p.group
	table.insert(Config.MuscleGroupParts[p.group], p)
end

-- a sub-muscle's development in a build table; falls back to its group (old saves, NPC builds)
function Config.PartValue(build, id)
	local v = build and build[id]
	if type(v) == "number" then
		return v
	end
	local g = Config.MusclePartGroup[id] or id
	v = build and build[g]
	return type(v) == "number" and v or 8
end

-- fill every missing sub-muscle from its group (idempotent; used by save migration and NPC builds)
function Config.FillParts(body)
	for _, p in ipairs(Config.MuscleParts) do
		if type(body[p.id]) ~= "number" then
			body[p.id] = type(body[p.group]) == "number" and body[p.group] or 8
		end
	end
	return body
end

-- recompute the 7 coarse groups from their parts (a group with no parts present is left alone)
function Config.SyncGroups(body)
	for _, g in ipairs(Config.MuscleKeys) do
		local total, any = 0, false
		for _, p in ipairs(Config.MuscleGroupParts[g]) do
			local v = body[p.id]
			if type(v) == "number" then
				any = true
			else
				v = type(body[g]) == "number" and body[g] or 8
			end
			total += p.share * v
		end
		if any then
			body[g] = total
		end
	end
	return body
end

Config.WeightClasses = {
	{ name = "Flyweight", limit = 112, min = 105 },
	{ name = "Bantamweight", limit = 118, min = 113 },
	{ name = "Featherweight", limit = 126, min = 119 },
	{ name = "Lightweight", limit = 135, min = 127 },
	{ name = "Welterweight", limit = 147, min = 136 },
	{ name = "Middleweight", limit = 160, min = 148 },
	{ name = "Light Heavyweight", limit = 175, min = 161 },
	{ name = "Cruiserweight", limit = 200, min = 176 },
	{ name = "Heavyweight", limit = 280, min = 201 },
}

-- ai.range = preferred distance as a share of the fighter's jab range
Config.Styles = {
	{
		id = "OutBoxer", name = "Out-Boxer", desc = "Fast movement, strong jab, high stamina",
		mods = { PunchSpeed = 5, Footwork = 8, Stamina = 6, Endurance = 3, Power = -6 },
		fight = { jab = 1.3, combo = 1.0, inside = 0.9, power = 0.92, counter = 1.0, move = 1.2 },
		ai = { range = 0.94, aggression = 0.35, jabRate = 0.55 },
	},
	{
		id = "Swarmer", name = "Swarmer", desc = "Aggressive pressure, fast combinations, strong inside",
		mods = { PunchSpeed = 5, Endurance = 6, Chin = 4, HeadMovement = 3, Footwork = -2, Blocking = -2 },
		fight = { jab = 0.9, combo = 1.3, inside = 1.15, power = 1.0, counter = 0.9, move = 1.05 },
		ai = { range = 0.72, aggression = 0.8, jabRate = 0.2 },
	},
	{
		id = "Slugger", name = "Slugger", desc = "Huge knockout power, lower speed",
		mods = { Power = 12, Chin = 6, PunchSpeed = -6, Footwork = -6, HeadMovement = -2 },
		fight = { jab = 0.85, combo = 0.9, inside = 1.08, power = 1.22, counter = 0.9, move = 0.9 },
		ai = { range = 0.8, aggression = 0.65, jabRate = 0.2 },
	},
	{
		id = "BoxerPuncher", name = "Boxer-Puncher", desc = "Balanced offense and defense",
		mods = { Power = 3, Blocking = 3, PunchSpeed = 3, RingIQ = 3 },
		fight = { jab = 1.1, combo = 1.1, inside = 1.0, power = 1.08, counter = 1.1, move = 1.05 },
		ai = { range = 0.86, aggression = 0.55, jabRate = 0.4 },
	},
	{
		id = "CounterPuncher", name = "Counter Puncher", desc = "Reads opponents, big timing bonuses",
		mods = { Countering = 10, Reflexes = 6, RingIQ = 4, Power = -2, Endurance = -1 },
		fight = { jab = 1.0, combo = 0.95, inside = 0.95, power = 1.0, counter = 1.6, move = 1.05 },
		ai = { range = 0.9, aggression = 0.3, jabRate = 0.35 },
	},
}

-- AI personalities in the ring. Each maps to a style and defensive habits.
Config.Archetypes = {
	{ id = "Pressure", name = "Aggressive Pressure Fighter", style = "Swarmer",
		ai = { aggr = 0.15, block = 0.25, slip = 0.2, roll = 0.3, parry = 0.05, pivot = 0.05, body = 0.22, overhand = 0.05, adapt = 1.0 } },
	{ id = "Counter", name = "Fast Counter Puncher", style = "CounterPuncher",
		ai = { aggr = -0.1, block = 0.2, slip = 0.45, roll = 0.15, parry = 0.35, pivot = 0.15, body = 0.05, overhand = 0.03, adapt = 1.2 } },
	{ id = "Technician", name = "Technical Genius", style = "BoxerPuncher",
		ai = { aggr = 0.0, block = 0.3, slip = 0.3, roll = 0.2, parry = 0.2, pivot = 0.25, body = 0.12, overhand = 0.05, adapt = 1.6 } },
	{ id = "KO", name = "Knockout Artist", style = "Slugger",
		ai = { aggr = 0.05, block = 0.3, slip = 0.1, roll = 0.1, parry = 0.02, pivot = 0.02, body = 0.1, overhand = 0.25, adapt = 0.8 } },
	{ id = "Defensive", name = "Defensive Specialist", style = "OutBoxer",
		ai = { aggr = -0.2, block = 0.45, slip = 0.35, roll = 0.25, parry = 0.25, pivot = 0.35, body = 0.02, overhand = 0.0, adapt = 1.1 } },
}

Config.Specialties = {
	{ id = "Speed", stats = { PunchSpeed = 8 } },
	{ id = "Strength", stats = { Power = 5, Chin = 3 } },
	{ id = "Agility", stats = { Footwork = 4, HeadMovement = 4 } },
	{ id = "Endurance", stats = { Endurance = 5, Stamina = 3 } },
	{ id = "Chin", stats = { Chin = 8 } },
	{ id = "Defense", stats = { Blocking = 5, HeadMovement = 3 } },
	{ id = "Reflexes", stats = { Reflexes = 8 } },
	{ id = "Power Punching", stats = { Power = 8 } },
	{ id = "Footwork", stats = { Footwork = 8 } },
	{ id = "Ring IQ", stats = { RingIQ = 5, Countering = 3 } },
}

-- Body types set the frame (bone structure) and how much muscle the boxer can build.
-- Everyone starts lean with low muscle mass; training does the rest.
Config.BodyTypes = {
	{ id = "Lean", width = 0.92, depth = 0.92, potential = 0.8, mods = { Footwork = 3, PunchSpeed = 2, Power = -2 } },
	{ id = "Athletic", width = 1.0, depth = 1.0, potential = 0.95, mods = { Stamina = 2, Footwork = 1 } },
	{ id = "Muscular", width = 1.05, depth = 1.03, potential = 1.05, mods = { Power = 2, Chin = 1 } },
	{ id = "Power Build", width = 1.1, depth = 1.07, potential = 1.15, mods = { Power = 3, Chin = 2, PunchSpeed = -1, Footwork = -2 } },
	{ id = "Heavyweight Build", width = 1.18, depth = 1.14, potential = 1.25, mods = { Power = 4, Chin = 3, PunchSpeed = -2, Footwork = -3, Stamina = -2 } },
}

-- Physique archetypes: what the trained body LOOKS like (separate id space from
-- Config.Archetypes, which are AI ring personalities). Classified from the build by
-- Config.ClassifyPhysique; an appearance may pin one with app.body.physique (default "Auto").
-- shape = visual size multiplier per coarse group (Builder only), partBias = additive
-- development bias for AI builds (Looks.RandomBuild), defBonus adds to muscle definition,
-- fatBias shifts AI body fat, vein scales vascularity, width/depth add to the frame scale
-- (quantise before use), bellyAt = fat level where the belly shows.
Config.Physiques = {
	{ id = "BeginnerLean", name = "Beginner Lean", desc = "Untrained and narrow - everything is still to build",
		shape = { chest = 0.9, shoulders = 0.9, arms = 0.9, back = 0.9, legs = 0.95, core = 0.95, neck = 0.9 },
		-- vein 0.8, not lower: an untrained body already has few veins (no vascularity, little definition),
		-- and early dumbbell work should show on the forearms before the physique changes
		partBias = {}, defBonus = 0, fatBias = 0, vein = 0.8, width = -0.02, depth = -0.02, bellyAt = 19 },
	{ id = "LeanTechnical", name = "Lean Technical", desc = "Wiry and dry: long muscles, visible abs, built to move",
		shape = { chest = 0.85, shoulders = 0.95, arms = 0.85, back = 0.9, legs = 0.95, core = 1.15, neck = 0.85 },
		partBias = { calves = 4, obliques = 4, serratus = 4, abs = 3, pecs = -6, biceps = -6, traps = -6 },
		defBonus = 0.25, fatBias = -2, vein = 0.9, width = -0.03, depth = -0.02, bellyAt = 20 },
	{ id = "Balanced", name = "Balanced Pro", desc = "Athletic all-round boxer's build",
		shape = { chest = 1, shoulders = 1, arms = 1, back = 1, legs = 1, core = 1, neck = 1 },
		partBias = {}, defBonus = 0.05, fatBias = 0, vein = 1, width = 0, depth = 0, bellyAt = 19 },
	{ id = "PowerPuncher", name = "Power Puncher", desc = "Thick traps, big shoulders and back, heavy legs",
		shape = { chest = 1.15, shoulders = 1.25, arms = 1.1, back = 1.15, legs = 1.1, core = 1.0, neck = 1.3 },
		partBias = { traps = 12, lats = 10, sideDelt = 12, frontDelt = 8, glutes = 8, quads = 6, neckSCM = 10 },
		defBonus = 0, fatBias = 1, vein = 1, width = 0.04, depth = 0.03, bellyAt = 19 },
	{ id = "Heavyweight", name = "Heavyweight", desc = "Big, powerful frame carrying extra mass",
		shape = { chest = 1.2, shoulders = 1.15, arms = 1.15, back = 1.2, legs = 1.2, core = 0.9, neck = 1.3 },
		partBias = { traps = 10, neckSCM = 10, quads = 8, glutes = 8, pecs = 6 },
		defBonus = -0.3, fatBias = 5, vein = 0.7, width = 0.06, depth = 0.06, bellyAt = 16, soft = 1.5 },
	{ id = "EliteChampion", name = "Elite Champion", desc = "Complete, balanced, shredded - the body of a world champion",
		shape = { chest = 1.1, shoulders = 1.1, arms = 1.1, back = 1.1, legs = 1.1, core = 1.1, neck = 1.1 },
		partBias = { serratus = 6, obliques = 6, lats = 6, sideDelt = 6, calves = 4 },
		defBonus = 0.35, fatBias = -3, vein = 1.3, width = 0.03, depth = 0.02, bellyAt = 21, shadows = true },
}

-- Rule that names a build's physique from the SHAPE of the development, not its absolute size:
-- every group is read as a share of the frame's cap (100 * BodyTypes potential), so a Lean frame and a
-- Heavyweight Build that trained the same way get the same physique. body = profile.body / Builder build.
-- info = { frame = BodyTypes id, tier = career tier, weightClass = index, overall = OVR, champion = bool,
--   prev = the id this build had last time (optional: Training.PhysiqueInfo keeps it, so a 0.1% fat or a
--   one-session change cannot flip the label back and forth at a threshold) }
-- Signals (all frame-relative 0..1+):
--   dev   mean of the 6 trunk/limb groups (the neck is barely trained by anything, so it is left out)
--   upper mean of chest, shoulders, arms, back      lowCore mean of legs and core
--   power mean of chest, shoulders, back (upper-body mass)
--   mass  the heavy compound-lift muscles (pecs, upper chest, lats, traps, upper/lower back, quads, glutes)
--   agile the boxing / endurance muscles (calves, abs, obliques, serratus, side + rear delts, forearms)
-- mass / agile tells a lifter (bench, pull-ups, squat, deadlift) from a boxer or runner whatever the
-- overall size; for an evenly developed body it is 1, so even development stays Balanced.
-- Order: Elite Champion > Heavyweight (overfed) > Beginner Lean > lifter (Power Puncher, or Heavyweight
-- when he also eats big) > Heavyweight frame carrying fat > Lean Technical > Balanced.
local MASS_PARTS = { "pecs", "upperChest", "lats", "traps", "upperBack", "lowerBack", "quads", "glutes" }
local AGILE_PARTS = { "calves", "abs", "obliques", "serratus", "sideDelt", "rearDelt", "forearms" }
local TRUNK_GROUPS = { "chest", "shoulders", "arms", "back", "legs", "core" }
function Config.PhysiqueSignals(body, info)
	info = info or {}
	local frame = Config.FindById(Config.BodyTypes, info.frame or "Athletic") or Config.BodyTypes[2]
	local cap = 100 * frame.potential
	local function r(k)
		local v = tonumber(body and body[k])
		return (v and v == v and v or 8) / cap
	end
	local function partMean(list)
		local t = 0
		for _, id in ipairs(list) do
			local v = tonumber(Config.PartValue(body, id)) or 8
			t += (v == v and v or 8) / cap
		end
		return t / #list
	end
	local dev, maxR, minR = 0, 0, math.huge
	for _, k in ipairs(TRUNK_GROUPS) do
		local v = r(k)
		dev += v
		maxR = math.max(maxR, v)
		minR = math.min(minR, v)
	end
	dev /= #TRUNK_GROUPS
	local fat = tonumber(body and body.fat) or 14
	local mass, agile = partMean(MASS_PARTS), partMean(AGILE_PARTS)
	return {
		frame = frame, fat = fat ~= fat and 14 or fat, dev = dev, maxR = maxR, minR = minR,
		upper = (r("chest") + r("shoulders") + r("arms") + r("back")) / 4,
		lowCore = (r("legs") + r("core")) / 2,
		power = (r("chest") + r("shoulders") + r("back")) / 3,
		mass = mass, agile = agile, liftRatio = mass / math.max(agile, 0.02),
	}
end

-- tuning of the rule above (frame-relative shares; fat in %)
Config.PhysiqueRule = {
	beginnerDev = 0.2, beginnerMax = 0.3, -- untrained: nothing developed past these shares
	overfedFat = 20, -- anyone above reads as Heavyweight
	liftRatio = 1.17, liftPower = 0.28, liftMass = 0.31, -- lifter: mass/agile, upper-body mass, (mass+power)/2
	liftHeavyFat = 16, -- a lifter carrying this much fat is a Heavyweight-style mass build
	heavyFrameFat = 15, heavyFrameDev = 0.25, -- heavy frame / class carrying fat over some muscle
	leanFat = 12.5, leanSpread = 1.5, -- lean technical: lean, legs/core not behind the upper body, specialised
	eliteFat = 11.5, eliteMin = 0.45, -- titled / OVR 85+ boxers: every group at least this share
	elitePureFat = 10, elitePureDev = 0.7, elitePureMin = 0.55, -- untitled elite conditioning
	-- hysteresis while the build keeps its previous id
	keepFat = 0.6, keepShare = 0.025, keepRatio = 0.06,
}

function Config.ClassifyPhysique(body, info)
	info = info or {}
	local R = Config.PhysiqueRule
	local s = Config.PhysiqueSignals(body, info)
	local fat, prev = s.fat, info.prev
	-- staying in the previous class is a little easier than entering it
	local function k(id, amount)
		return prev == id and amount or 0
	end
	local elite = (info.tier or 1) >= 8 or (info.overall or 0) >= 85 or info.champion == true
	local kf, ks = k("EliteChampion", R.keepFat), k("EliteChampion", R.keepShare)
	if (elite and s.minR >= R.eliteMin - ks and fat <= R.eliteFat + kf)
		or (s.dev >= R.elitePureDev - ks and s.minR >= R.elitePureMin - ks and fat <= R.elitePureFat + kf) then
		return "EliteChampion"
	end
	if fat >= R.overfedFat - k("Heavyweight", R.keepFat) then
		return "Heavyweight"
	end
	ks = k("BeginnerLean", R.keepShare)
	if s.dev < R.beginnerDev + ks and s.maxR < R.beginnerMax + ks then
		return "BeginnerLean"
	end
	-- a lifter's build: the compound-lift muscles lead the boxing ones and the upper body carries mass.
	-- No lower fat bound: a lean lifter keeps his traps and neck and just gets sharper (Config.Definition).
	local wasLifter = prev == "PowerPuncher" or prev == "Heavyweight"
	local kr, kl = wasLifter and R.keepRatio or 0, wasLifter and R.keepShare or 0
	if s.liftRatio >= R.liftRatio - kr and s.power >= R.liftPower - kl and (s.mass + s.power) / 2 >= R.liftMass - kl then
		if fat >= R.liftHeavyFat + (prev == "PowerPuncher" and R.keepFat or -k("Heavyweight", R.keepFat)) then
			return "Heavyweight"
		end
		return "PowerPuncher"
	end
	if fat >= R.heavyFrameFat - k("Heavyweight", R.keepFat) and s.dev >= R.heavyFrameDev
		and ((info.weightClass or 0) >= 8 or s.frame.id == "Heavyweight Build") then
		return "Heavyweight"
	end
	-- wiry and dry: lean, the upper body does not lead the legs and core, and the development is
	-- specialised (runners, skippers, med-ball / bag boxers) rather than an all-round build
	ks = k("LeanTechnical", R.keepShare)
	if fat <= R.leanFat + k("LeanTechnical", R.keepFat) and s.upper <= s.lowCore + ks
		and s.maxR >= (R.leanSpread - 4 * ks) * s.dev then
		return "LeanTechnical"
	end
	return "Balanced"
end

-- Body fat & definition. Definition 0 = smooth, 1 = shredded: (defZero - fat) / (defZero - defFull).
Config.BodyFat = {
	min = 7, max = 30, default = 14,
	defZero = 16, defFull = 8, -- definition starts below 16% and peaks at 8%
	bellyAt = 19, -- belly overlay (physique bellyAt overrides)
	loveHandlesAt = 16, softChestAt = 18, armFatAt = 20, faceFatAt = 18, jowlsAt = 20,
	gauntBelow = 9, -- hollow cheeks (also after a hard weight cut: condition.water < 0)
	absRow4Def = 0.85, -- 8-pack row needs this definition
	veinDef = 0.5, -- veins start reading above this definition
	softK = 0.12, -- extra roundness per unit of fatK on muscle overlays (Builder)
}
function Config.Definition(fat, bonus)
	local f = Config.BodyFat
	local d = ((f.defZero - (tonumber(fat) or f.default)) / (f.defZero - f.defFull)) + (bonus or 0)
	return math.clamp(d, 0, 1)
end

-- Muscle growth / recovery model (server Training; shown by Hub)
Config.MuscleGrowth = {
	base = 1.3, -- gain = base * weight * quality * condition * room (room = 1 - cur/cap) * scale
	immediate = 0.65, -- share of a session's growth applied at once; the rest is condition.pending until sleep
	sorePerWeight = 0.25, -- condition.sore[group] += weight * quality * this
	sorePenalty = 0.45, -- growth x (1 - sorePenalty * sore)
	soreInjuryRisk = 0.03, -- extra injury risk per point of max soreness
	soreSleepKeep = 0.55, -- sleep: sore *= soreSleepKeep - soreSleepQ * sleepQ
	soreSleepQ = 0.25,
	detrainGraceDays = 6, -- a part untouched this long starts to fade
	detrainRate = 0.004, -- per day: lose value * rate * min(3, (idle - grace) / 7)
	detrainFloor = 4,
	detrainAgeFrom = 33, -- detraining doubles from this age
	vascGain = 0.6, -- default act.vasc for vein-building lifts (dumbbells)
	vascFatFade = 16, -- body.vasc fades 0.05/day while fat is above this
}
-- Post-workout pump & flexing (client visual only, driven by character attributes)
Config.Pump = {
	duration = 150, -- seconds for a pump to fade completely
	scale = 0.08, -- max extra SpecialMesh scale on a pumped part
	veinBoost = 0.4, -- extra vein opacity while pumped
	flexScale = 0.12, -- contraction while flexing
	poses = { "flex_biceps", "flex_lat", "flex_chest", "flex_most", "flex_abs" }, -- Pose attribute values
}

-- Career tiers. rounds = fight length at that tier; campDays = days of training camp.
Config.Tiers = {
	{ name = "Amateur", rounds = 3, purse = { 50, 200 }, campDays = 3 },
	{ name = "Local Pro", rounds = 4, purse = { 1500, 5000 }, campDays = 4 },
	{ name = "Regional Champion", rounds = 6, purse = { 8000, 20000 }, campDays = 5 },
	{ name = "National Champion", rounds = 8, purse = { 30000, 80000 }, campDays = 5 },
	{ name = "International Contender", rounds = 10, purse = { 100000, 250000 }, campDays = 6 },
	{ name = "Top 10 Ranked", rounds = 10, purse = { 300000, 800000 }, campDays = 6 },
	{ name = "Title Challenger", rounds = 12, purse = { 800000, 1500000 }, campDays = 7 },
	{ name = "World Champion", rounds = 12, purse = { 2500000, 6000000 }, campDays = 7 },
	{ name = "Undisputed Champion", rounds = 12, purse = { 8000000, 20000000 }, campDays = 8 },
	{ name = "Boxing Legend", rounds = 12, purse = { 10000000, 30000000 }, campDays = 8 },
}

Config.Orgs = { "WBA", "WBC", "IBF", "WBO" }

-- Fight venues (ring system)
Config.Venues = {
	CommunityCenter = { name = "Community Center", kind = "Local Ring" },
	ClubArena = { name = "City Club Arena", kind = "Local Ring" },
	Arena = { name = "Grand Arena", kind = "Professional Ring" },
	Stadium = { name = "National Stadium", kind = "World Title Ring" },
}
function Config.VenueFor(kind, tier)
	if kind == "World Title" or kind == "Unification" or kind == "Title Defense" or tier >= 8 then
		return "Stadium"
	elseif kind == "Amateur Bout" or tier <= 1 then
		return "CommunityCenter"
	elseif tier <= 3 or kind == "Regional Title" then
		return "ClubArena"
	end
	return "Arena"
end

-- Punches: base damage, stamina cost, windup seconds (before speed scaling), hit chance, range mult
Config.PunchList = { "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }
Config.PunchNames = {
	jab = "Jab", cross = "Cross", leadhook = "Lead Hook", rearhook = "Rear Hook",
	uppercut = "Uppercut", overhand = "Overhand",
}
-- head = head-HP multiplier, body = body-HP multiplier, ko = knockdown-odds multiplier,
-- stun = balance damage (stumbles), face = which face zones a clean head shot marks
Config.Punches = {
	jab = { dmg = 3.0, stam = 2.5, windup = 0.16, hit = 0.82, range = 1.10, cutChance = 0.01, hand = "L", kind = "straight",
		head = 0.65, body = 0.8, ko = 0.25, stun = 6, face = { "eye", "nose", "lip" } },
	cross = { dmg = 6.5, stam = 5.0, windup = 0.24, hit = 0.70, range = 1.05, cutChance = 0.03, hand = "R", kind = "straight",
		head = 1.0, body = 1.0, ko = 1.0, stun = 12, face = { "eye", "nose", "lip" } },
	leadhook = { dmg = 7.5, stam = 5.5, windup = 0.26, hit = 0.64, range = 0.85, cutChance = 0.05, hand = "L", kind = "hook",
		head = 1.25, body = 1.25, ko = 1.35, stun = 18, face = { "cheek", "eye", "ear", "bruise" } },
	rearhook = { dmg = 8.5, stam = 6.5, windup = 0.30, hit = 0.60, range = 0.85, cutChance = 0.05, hand = "R", kind = "hook",
		head = 1.3, body = 1.3, ko = 1.45, stun = 20, face = { "cheek", "eye", "ear", "bruise" } },
	uppercut = { dmg = 9.0, stam = 6.5, windup = 0.30, hit = 0.58, range = 0.75, cutChance = 0.03, hand = "R", kind = "uppercut",
		head = 1.55, body = 1.15, ko = 1.8, stun = 24, face = { "lip", "nose", "bruise" } },
	overhand = { dmg = 10.5, stam = 8.5, windup = 0.42, hit = 0.52, range = 1.0, cutChance = 0.06, hand = "R", kind = "overhand", overGuard = 0.5,
		head = 1.4, body = 0.9, ko = 1.6, stun = 22, face = { "forehead", "eye", "bruise" } },
}

------------------------------------------------------------------------
-- Fight health model: head HP tiers, knockouts, concussion, face damage
------------------------------------------------------------------------
-- The fighter field F.health IS head HP (0..100, capped by F.healthCap); F.body is body HP.
-- Head tiers by head HP: 100-30 conscious, 30-15 dazed, 15-5 severe danger, <5 high KO chance.
Config.HeadTiers = {
	{ id = "conscious", min = 30, label = "", rgb = { 70, 200, 90 } },
	{ id = "dazed", min = 15, label = "DAZED", rgb = { 240, 200, 40 } },
	{ id = "danger", min = 5, label = "IN DANGER", rgb = { 240, 120, 30 } },
	{ id = "out", min = -math.huge, label = "OUT ON HIS FEET", rgb = { 230, 40, 40 } },
}
-- 0 = conscious, 1 = dazed, 2 = severe danger, 3 = high KO chance (index into HeadTiers is tier + 1)
function Config.HeadTier(hp)
	hp = tonumber(hp) or 100
	for i, t in ipairs(Config.HeadTiers) do
		if hp >= t.min then
			return i - 1
		end
	end
	return #Config.HeadTiers - 1
end

-- Knockdown odds per LANDED head shot. Every factor is a multiplier around 1:
--   chin          chinBase - Chin/100                      (defender Chin stat)
--   conditioning  condBase - (Endurance + Stamina)/400     (defender stats)
--   stamina       stamBase - stamK * stamPct               (defender stamina / maxStam)
--   power         powerBase + Power/330                    (attacker Power stat)
--   accuracy      accBase + accK * clean                   (clean 0..1 = how cleanly the hit roll landed; 0.5 through a block)
--   previous      1 + kdTotal*kdK + conc*concK + (100 - healthCap)/capDiv + trauma/traumaDiv
-- plus the punch's ko multiplier, a damage term clamp((hd/hdRef)^hdExp, hdMin, hdMax)
-- (hdRef = 6 * HEAD_SCALE * damageScale) and x counterMul on counters.
Config.KO = {
	base = { 0, 0.06, 0.22, 0.6 }, -- by head tier 0..3 (index tier + 1)
	flash = 0.035, -- tier 0: only a clean COUNTER can drop a fighter (a flash knockdown)
	flashMinHd = 1.0, -- ... and only when hd/hdRef is at least this
	hdExp = 1.2, hdMin = 0.2, hdMax = 2.5,
	counterMul = 1.6,
	chinBase = 1.45, condBase = 1.15, stamBase = 1.25, stamK = 0.45, powerBase = 0.85, accBase = 0.7, accK = 0.6,
	kdK = 0.25, concK = 0.8, capDiv = 150, traumaDiv = 200,
	composureK = 0.002, -- x (1 - composureK * (Composure - 50)) on the defender
	cap = 0.92,
	tierDamage = 0.1, -- incoming head damage x (1 + tierDamage * tier): hurt fighters take more
	severity = { heavyTier = 2, heavyHd = 1.8, outHd = 2.5 }, -- knockdown severity: flash | normal | heavy | out
	falls = { "back", "side", "knee", "sit", "face" }, -- DownPose attribute values
}

-- a = { tier, punch (Config.Punches id), hd, hdRef, counter, chin, endurance, stamina, stamPct,
--       power, clean, kdTotal, conc, healthCap, trauma, composure }  -> probability 0..cap, flash (bool)
function Config.KOChance(a)
	local K = Config.KO
	local tier = math.clamp(math.floor(tonumber(a.tier) or 0), 0, 3)
	local P = Config.Punches[a.punch or ""] or Config.Punches.cross
	local rel = (tonumber(a.hd) or 0) / math.max(0.01, tonumber(a.hdRef) or 3.3)
	local base = K.base[tier + 1]
	local flash = false
	if tier == 0 then
		if not (a.counter and rel >= K.flashMinHd) then
			return 0, false
		end
		base, flash = K.flash, true
	end
	local dmgTerm = math.clamp(rel ^ K.hdExp, K.hdMin, K.hdMax)
	local chin = K.chinBase - (a.chin or 50) / 100
	local cond = K.condBase - ((a.endurance or 50) + (a.stamina or 50)) / 400
	local stam = K.stamBase - K.stamK * math.clamp(a.stamPct or 1, 0, 1)
	local power = K.powerBase + (a.power or 50) / 330
	local acc = K.accBase + K.accK * math.clamp(a.clean or 0.5, 0, 1)
	local prev = 1 + (a.kdTotal or 0) * K.kdK + (a.conc or 0) * K.concK + (100 - (a.healthCap or 100)) / K.capDiv + (a.trauma or 0) / K.traumaDiv
	local comp = 1 - K.composureK * ((a.composure or 50) - 50)
	local p = base * (P.ko or 1) * dmgTerm * chin * cond * stam * power * acc * prev * comp * (a.counter and K.counterMul or 1)
	return math.clamp(p, 0, K.cap), flash
end

-- Concussion: F.conc 0..1 inside a fight; career-long condition.trauma 0..100 feeds the start value.
Config.Concussion = {
	startFromTrauma = 1 / 250, -- F.conc starts at trauma * this (+ activeInjury if a concussion injury is active)
	activeInjury = 0.15,
	perHeadDamage = 1 / 80, -- conc += hd * this * punch.ko * (1.3 - Chin/150)
	perKnockdown = 0.25, perFlashKnockdown = 0.1,
	decay = 0.006, decayPerRecovery = 0.00012, -- per second: decay + Recovery * decayPerRecovery
	restHeal = 0.12, restHealElite = 0.18, -- between rounds
	-- effect magnitudes at conc = 1 (scale linearly)
	windup = 0.35, -- punch windup x (1 + windup * conc)
	hitChance = 0.25, -- own hit chance x (1 - hitChance * conc)
	defense = 0.3, -- slip/roll/parry windows x (1 - defense * conc)
	speed = 0.3, -- movement x (1 - speed * conc)
	aiReact = 0.12, aiDefense = 0.35, -- AI reaction +aiReact*conc s, defense chance x (1 - aiDefense * conc)
	-- per head tier (on top of conc): windup +8%, hit chance -8%, defense -12%, movement -10% per tier
	tierWindup = 0.08, tierHitChance = 0.08, tierDefense = 0.12, tierSpeed = 0.1,
	-- after the fight (Training / Career)
	injuryAt = 0.5, -- concPeak above this with a knockdown against -> 'concussion' injury
	traumaPerDamage = 1 / 12, traumaPerKnockdown = 6, traumaDecayPerDay = 0.5, traumaChinDiv = 10,
	-- screen effects (client) at conc = 1 / per tier
	blurPerTier = 2, blurPerConc = 8, desatPerTier = 0.15, desatPerConc = 0.45, vignettePerTier = 0.15, vignettePerConc = 0.4,
}
Config.ScreenFX = 1 -- accessibility scale for blur / shake / colour effects (0 disables)

-- Facial damage. The dmg table (fight and persistent) uses these numeric fields, 0..1 unless noted:
--   leftEye, rightEye (swelling), cut (0..1.2), cutSide (-1|1), cut2, cutSide2, noseBleed, nose (bool: broken),
--   bruise, lip, cheekL, cheekR, forehead (lump), earL, earR, redness, ribsL, ribsR, age (days since the fight)
Config.FaceDamage = {
	fields = { "leftEye", "rightEye", "cut", "cut2", "noseBleed", "bruise", "lip", "cheekL", "cheekR", "forehead", "earL", "earR", "redness", "ribsL", "ribsR" },
	weights = { eyes = 0.35, cut = 0.25, bruise = 0.2, lip = 0.1, nose = 0.1, cheeks = 0.1 },
	stages = { -- score thresholds -> FaceDmgTier attribute 0..4
		{ id = "none", min = 0, label = "Fresh" },
		{ id = "light", min = 0.1, label = "Light marks" },
		{ id = "moderate", min = 0.3, label = "Moderate swelling" },
		{ id = "heavy", min = 0.55, label = "Heavy damage" },
		{ id = "severe", min = 0.8, label = "Severe damage" },
	},
	-- healing per in-game day (Training dayTick); mul = multiply, sub = subtract
	heal = {
		leftEye = { mul = 0.55 }, rightEye = { mul = 0.55 }, lip = { mul = 0.6 }, cheekL = { mul = 0.6 }, cheekR = { mul = 0.6 },
		forehead = { mul = 0.55 }, earL = { mul = 0.7 }, earR = { mul = 0.7 }, redness = { mul = 0.3 },
		ribsL = { mul = 0.6 }, ribsR = { mul = 0.6 }, noseBleed = { mul = 0 },
		bruise = { sub = 0.12 }, cut = { sub = 0.12 }, cut2 = { sub = 0.12 },
	},
	physioHeal = 1.5, -- owning the Physiotherapist speeds healing
	postFightCarry = 0.75, -- share of fight damage still visible after the suspension days (applied AFTER PassDays)
	sparCarry = 0.5, -- sparring res.face x this (res.face is already scaled by the engine's damageScale)
	seedFromResidual = 0.8, -- a fight starts with F.dmg = residual face * this
	clearBelow = 0.03, -- values below this snap to 0; the table is dropped when everything is 0
	scarAt = 0.6, maxScars = 6, -- a cut this deep leaves a permanent scar in appearance.battle.scars
	noseBendChance = 0.35, noseBendStep = 0.34, -- a broken nose may add to appearance.battle.nose
	cauliflowerAt = 0.6, cauliflowerStep = 0.2, -- an ear swollen this much may add to appearance.battle.ears
	-- bruise colour by age (days): fresh red-purple, blue-purple, yellow-green, then skin
	bruiseColors = { { day = 0, rgb = { 95, 25, 40 } }, { day = 1, rgb = { 70, 45, 95 } }, { day = 4, rgb = { 150, 150, 70 } }, { day = 8 } },
}
function Config.FaceDamageScore(dmg)
	if type(dmg) ~= "table" then
		return 0
	end
	local function n(k)
		return tonumber(dmg[k]) or 0
	end
	local w = Config.FaceDamage.weights
	local s = w.eyes * math.max(n("leftEye"), n("rightEye")) + w.cut * math.min(1, math.max(n("cut"), n("cut2")))
		+ w.bruise * n("bruise") + w.lip * n("lip") + w.nose * math.max(dmg.nose == true and 0.6 or 0, n("noseBleed"))
		+ w.cheeks * math.max(n("cheekL"), n("cheekR"), n("forehead"))
	return math.clamp(s, 0, 1)
end
-- stage index 0..4 (none, light, moderate, heavy, severe) and its definition
function Config.FaceDamageStage(dmg)
	local s = Config.FaceDamageScore(dmg)
	local stages = Config.FaceDamage.stages
	for i = #stages, 1, -1 do
		if s >= stages[i].min then
			return i - 1, stages[i]
		end
	end
	return 0, stages[1]
end

------------------------------------------------------------------------
-- Training
------------------------------------------------------------------------
-- minigame types: combo, rhythm, reaction, mitts, shadow, reps, pace, course, swim, ladder, rope, hold, spar
Config.Activities = {
	{ id = "HeavyBag", name = "Heavy Bag", area = "Boxing Area", station = "heavybag", minigame = "combo", pose = "heavybag",
		energy = 22, hydration = 8, nutrition = 6, fatigue = 16, fat = -0.08,
		gains = { Power = 1.0, Endurance = 0.5, PunchSpeed = 0.4, RingIQ = 0.25 },
		muscle = { shoulders = 0.7, arms = 0.4, core = 0.3 }, wear = { gloves = 1.0, wraps = 0.8 },
		injuries = { "wrist", "shoulder" }, desc = "Punch power, endurance, combination speed, technique" },
	{ id = "SpeedBag", name = "Speed Bag", area = "Boxing Area", station = "speedbag", minigame = "rhythm", pose = "speedbag",
		energy = 14, hydration = 5, nutrition = 3, fatigue = 9, fat = -0.04,
		gains = { PunchSpeed = 1.0, Reflexes = 0.5, RingIQ = 0.25 },
		muscle = { shoulders = 0.35, arms = 0.3 }, wear = { gloves = 0.3, wraps = 0.5 },
		injuries = { "wrist" }, desc = "Hand speed, rhythm, timing, coordination" },
	{ id = "DoubleEnd", name = "Double-End Bag", area = "Boxing Area", station = "doubleend", minigame = "reaction", pose = "guard",
		energy = 16, hydration = 6, nutrition = 4, fatigue = 11, fat = -0.05,
		gains = { Reflexes = 0.9, HeadMovement = 0.6, Countering = 0.8, Blocking = 0.3 },
		muscle = { shoulders = 0.25 }, wear = { gloves = 0.5, wraps = 0.3 },
		injuries = { "wrist" }, desc = "Defense, reflexes, counter punching" },
	{ id = "MittWork", name = "Mitt Work", area = "Boxing Area", station = "mitts", minigame = "mitts", pose = "guard",
		energy = 22, hydration = 8, nutrition = 5, fatigue = 14, fat = -0.07,
		gains = { PunchSpeed = 0.5, Countering = 0.6, Power = 0.3, RingIQ = 0.7 },
		muscle = { shoulders = 0.45, arms = 0.3, core = 0.2 }, wear = { gloves = 0.8, wraps = 0.5 },
		injuries = { "wrist", "shoulder" }, desc = "Coach-called combinations, timing, Ring IQ" },
	{ id = "Shadow", name = "Shadow Boxing", area = "Boxing Area", station = "mirror", minigame = "shadow", pose = "guard",
		energy = 12, hydration = 5, nutrition = 3, fatigue = 8, fat = -0.05,
		gains = { Footwork = 0.6, HeadMovement = 0.6, RingIQ = 0.45 },
		muscle = { shoulders = 0.2 }, wear = { shoes = 0.3 },
		injuries = {}, desc = "Footwork, head movement, ring craft" },
	{ id = "Sparring", name = "Sparring", area = "Boxing Area", station = "ring", minigame = "spar", pose = "guard",
		energy = 30, hydration = 12, nutrition = 8, fatigue = 24, fat = -0.1,
		gains = { RingIQ = 0.8, Countering = 0.6, Blocking = 0.6, HeadMovement = 0.5, Chin = 0.4 },
		muscle = { neck = 0.4, shoulders = 0.2 }, wear = { gloves = 1.2, wraps = 0.8, shoes = 0.4 },
		injuries = { "ribs", "cut" }, desc = "Live rounds: experience, timing, defense, Ring IQ" },
	{ id = "Bench", name = "Weight Bench", area = "Weight Room", station = "bench", minigame = "reps", pose = "bench",
		energy = 22, hydration = 5, nutrition = 8, fatigue = 15, fat = -0.04,
		gains = { Power = 0.8, Chin = 0.2 }, muscle = { chest = 1.3, shoulders = 0.5, arms = 0.4 },
		wear = { wraps = 0.2 }, injuries = { "shoulder" }, desc = "Upper body strength, punching power" },
	{ id = "Dumbbells", name = "Dumbbells", area = "Weight Room", station = "dumbbells", minigame = "reps", pose = "curl",
		energy = 16, hydration = 4, nutrition = 6, fatigue = 11, fat = -0.03,
		gains = { Power = 0.4, Blocking = 0.45 }, muscle = { arms = 1.4, shoulders = 0.4 }, vasc = 0.6,
		wear = {}, injuries = { "wrist" }, desc = "Arm strength, stability" },
	{ id = "Barbell", name = "Barbell Deadlifts", area = "Weight Room", station = "barbell", minigame = "reps", pose = "deadlift",
		energy = 26, hydration = 6, nutrition = 9, fatigue = 17, fat = -0.05,
		gains = { Power = 0.7, Endurance = 0.35 }, muscle = { back = 0.9, legs = 0.6, core = 0.5, neck = 0.3 },
		wear = {}, injuries = { "back" }, desc = "Total-body strength, traps and back" },
	{ id = "Squat", name = "Squat Rack", area = "Weight Room", station = "squat", minigame = "reps", pose = "squat",
		energy = 26, hydration = 6, nutrition = 9, fatigue = 18, fat = -0.05,
		gains = { Power = 0.5, Footwork = 0.5 }, muscle = { legs = 1.5, core = 0.3 },
		wear = { shoes = 0.2 }, injuries = { "hamstring", "back" }, desc = "Leg power, explosiveness" },
	{ id = "PullUps", name = "Pull-Up Station", area = "Weight Room", station = "pullup", minigame = "reps", pose = "pullup",
		energy = 18, hydration = 5, nutrition = 6, fatigue = 13, fat = -0.04,
		gains = { Endurance = 0.5, Power = 0.3 }, muscle = { back = 1.4, arms = 0.5 },
		wear = {}, injuries = { "shoulder" }, desc = "Back strength, endurance, posture" },
	-- Medicine ball: slams + seated Russian twists. Needs (wave 2): Catalog.Stations.medball (done),
	-- MapBuilder.StationDefs 'medball' (stand), GymVisuals B.medball, Activities GAMES.medball
	-- (alternating SLAM and TWIST sets; 'reps' is an acceptable MVP), Animator POSE.medball,
	-- Poser prop 'medball' (ball in both hands), Main PROP_FOR.medball and MIN_TIME.medball = 9.
	{ id = "MedBall", name = "Medicine Ball", area = "Weight Room", station = "medball", minigame = "medball", pose = "medball",
		energy = 18, hydration = 6, nutrition = 5, fatigue = 12, fat = -0.12,
		gains = { Endurance = 0.45, Chin = 0.25, Power = 0.25 }, muscle = { core = 1.4, shoulders = 0.2, back = 0.1 },
		wear = {}, injuries = { "back" }, desc = "Core power and rotation: abs, obliques, body-shot armour" },
	{ id = "Roadwork", name = "Roadwork Running", area = "Outdoors", station = "track", minigame = "course", pose = "none",
		energy = 26, hydration = 15, nutrition = 8, fatigue = 15, fat = -0.45,
		gains = { Stamina = 1.0, Endurance = 0.7, Recovery = 0.3 }, muscle = { legs = 0.45 },
		wear = { shoes = 1.5 }, injuries = { "hamstring", "ankle" }, desc = "Stamina, endurance, conditioning, burns fat" },
	{ id = "Treadmill", name = "Treadmill", area = "Cardio Room", station = "treadmill", minigame = "pace", pose = "run",
		energy = 18, hydration = 10, nutrition = 5, fatigue = 11, fat = -0.3,
		gains = { Stamina = 0.6, Recovery = 0.6 }, muscle = { legs = 0.3 },
		wear = { shoes = 0.8 }, injuries = { "hamstring" }, desc = "Fitness, recovery" },
	{ id = "Bike", name = "Bike", area = "Cardio Room", station = "bike", minigame = "pace", pose = "bike",
		energy = 16, hydration = 9, nutrition = 5, fatigue = 9, fat = -0.25,
		gains = { Stamina = 0.5, Endurance = 0.5, Recovery = 0.3 }, muscle = { legs = 0.5 },
		wear = {}, injuries = {}, desc = "Low-impact conditioning" },
	{ id = "Rower", name = "Row Machine", area = "Cardio Room", station = "rower", minigame = "pace", pose = "row",
		energy = 18, hydration = 9, nutrition = 6, fatigue = 12, fat = -0.3,
		gains = { Stamina = 0.5, Endurance = 0.6, Power = 0.2 }, muscle = { back = 0.6, legs = 0.3, arms = 0.2 },
		wear = {}, injuries = { "back" }, desc = "Full-body conditioning" },
	{ id = "Swimming", name = "Swimming Laps", area = "Pool", station = "pool", minigame = "swim", pose = "none",
		energy = 22, hydration = 6, nutrition = 8, fatigue = 10, fat = -0.35,
		gains = { Stamina = 0.8, Recovery = 0.9, Endurance = 0.5 },
		muscle = { shoulders = 0.5, back = 0.5, chest = 0.3, arms = 0.3, legs = 0.3, core = 0.3 },
		wear = {}, injuries = {}, desc = "Stamina, recovery, full-body development" },
	{ id = "Ladder", name = "Agility Ladder", area = "Cardio Room", station = "ladder", minigame = "ladder", pose = "ladder",
		energy = 14, hydration = 6, nutrition = 4, fatigue = 9, fat = -0.12,
		gains = { Footwork = 1.0, PunchSpeed = 0.2, Reflexes = 0.3 }, muscle = { legs = 0.3 },
		wear = { shoes = 1.0 }, injuries = { "ankle" }, desc = "Footwork, speed, movement" },
	{ id = "Rope", name = "Jump Rope", area = "Cardio Room", station = "rope", minigame = "rope", pose = "rope",
		energy = 16, hydration = 8, nutrition = 4, fatigue = 10, fat = -0.25,
		gains = { Stamina = 0.5, Footwork = 0.6, Reflexes = 0.3, PunchSpeed = 0.2 }, muscle = { legs = 0.4 },
		wear = { shoes = 0.8 }, injuries = { "ankle" }, desc = "Conditioning, rhythm, foot speed" },
	-- Recovery (no stat gains)
	{ id = "IceBath", name = "Ice Bath", area = "Recovery Area", station = "icebath", minigame = "hold", pose = "sit",
		recovery = { fatigue = -24, energy = 5, heal = 1 }, desc = "Cuts fatigue and soreness, speeds injury healing" },
	{ id = "Stretch", name = "Stretching", area = "Recovery Area", station = "stretch", minigame = "hold", pose = "stretch",
		recovery = { fatigue = -12, energy = 3, heal = 0.5, flexible = true }, desc = "Lowers injury risk for the rest of the day" },
	{ id = "Massage", name = "Massage Table", area = "Recovery Area", station = "massage", minigame = "hold", pose = "lie",
		recovery = { fatigue = -30, energy = 8, heal = 1 }, price = 100, desc = "Deep recovery (free with a therapist upgrade)" },
	{ id = "Chamber", name = "Elite Recovery Chamber", area = "Recovery Area", station = "chamber", minigame = "hold", pose = "lie",
		recovery = { fatigue = -50, energy = 25, heal = 2 }, requires = "RecoveryChamber", desc = "End-game recovery tech" },
	{ id = "Sauna", name = "Sauna (Weight Cut)", area = "Recovery Area", station = "sauna", minigame = "hold", pose = "sit",
		recovery = { fatigue = 4, energy = -10, hydration = -25, water = -2.5 }, desc = "Sweat out water weight before a weigh-in" },
}

Config.Injuries = {
	wrist = { name = "Sprained Wrist", days = { 3, 6 }, blocks = { "HeavyBag", "SpeedBag", "MittWork", "DoubleEnd", "Dumbbells", "Sparring" }, fight = { Power = -6, PunchSpeed = -4 } },
	shoulder = { name = "Shoulder Strain", days = { 4, 8 }, blocks = { "Bench", "PullUps", "HeavyBag", "Swimming", "Rower" }, fight = { Power = -5, Blocking = -3 } },
	hamstring = { name = "Pulled Hamstring", days = { 4, 8 }, blocks = { "Roadwork", "Squat", "Ladder", "Rope", "Treadmill" }, fight = { Footwork = -8 } },
	back = { name = "Back Spasm", days = { 3, 7 }, blocks = { "Barbell", "Squat", "PullUps", "Rower", "MedBall" }, fight = { Power = -4, Endurance = -4 } },
	ankle = { name = "Rolled Ankle", days = { 3, 6 }, blocks = { "Roadwork", "Ladder", "Rope", "Treadmill" }, fight = { Footwork = -6 } },
	ribs = { name = "Bruised Ribs", days = { 5, 10 }, blocks = { "Sparring", "Rower", "Swimming", "MedBall" }, fight = { Endurance = -6, Chin = -3 } },
	cut = { name = "Cut Eyebrow", days = { 6, 12 }, blocks = { "Sparring" }, fight = { Chin = -2 }, reopens = true },
	-- fight injuries (given by Training/Career after fights, see Config.Concussion / Config.FaceDamage)
	nose = { name = "Broken Nose", days = { 10, 18 }, blocks = { "Sparring", "MittWork" }, fight = { Chin = -2 } },
	concussion = { name = "Concussion", days = { 10, 30 }, blocks = { "Sparring", "HeavyBag", "MittWork" }, fight = { Chin = -5, Reflexes = -4 } },
}

-- Per-exercise sub-muscle targeting (act.parts). Weights are chosen so the share-weighted
-- group pace stays close to the old act.muscle values (act.muscle stays for old code and as
-- the group-level summary). Training.Perform grows these parts and re-derives the groups.
Config.ExerciseTargets = {
	HeavyBag = { frontDelt = 0.8, sideDelt = 0.8, rearDelt = 0.4, triceps = 0.5, forearms = 0.6, biceps = 0.2, obliques = 0.6, abs = 0.2, serratus = 0.3 },
	SpeedBag = { sideDelt = 0.4, frontDelt = 0.3, rearDelt = 0.3, forearms = 0.8, biceps = 0.2, triceps = 0.15 },
	DoubleEnd = { frontDelt = 0.3, sideDelt = 0.3, rearDelt = 0.1 },
	MittWork = { frontDelt = 0.5, sideDelt = 0.5, rearDelt = 0.3, triceps = 0.4, forearms = 0.5, biceps = 0.1, obliques = 0.5, abs = 0.15 },
	Shadow = { sideDelt = 0.25, frontDelt = 0.2, rearDelt = 0.1, calves = 0.2 },
	Sparring = { neckSCM = 0.4, frontDelt = 0.2, sideDelt = 0.2, rearDelt = 0.2, obliques = 0.2, abs = 0.2 },
	-- bench -> chest / front delts / triceps
	Bench = { pecs = 1.3, upperChest = 1.3, frontDelt = 1.2, sideDelt = 0.15, triceps = 1.0 },
	-- dumbbells -> biceps / forearms / side delts (+ veins via act.vasc)
	Dumbbells = { biceps = 2.0, forearms = 1.6, triceps = 0.7, sideDelt = 0.8, frontDelt = 0.3 },
	Barbell = { lowerBack = 1.6, traps = 1.4, upperBack = 0.8, lats = 0.4, hamstrings = 1.2, glutes = 1.2, quads = 0.3,
		abs = 0.5, obliques = 0.5, lowerAbs = 0.5, serratus = 0.5, forearms = 0.6, neckSCM = 0.3 },
	-- squat -> quads / calves / glutes
	Squat = { quads = 2.0, glutes = 1.6, calves = 1.0, hamstrings = 1.0, abs = 0.3, obliques = 0.3, lowerAbs = 0.3, lowerBack = 0.3 },
	-- pull-ups -> lats / upper back (V-taper) + the hanging core work that keeps the legs still
	PullUps = { lats = 2.0, upperBack = 1.6, traps = 0.8, lowerBack = 0.4, biceps = 0.9, forearms = 0.7, rearDelt = 0.5, serratus = 0.3,
		abs = 0.5, lowerAbs = 0.6, obliques = 0.35 },
	-- medicine ball -> abs / obliques / lower abs
	MedBall = { abs = 1.4, obliques = 1.8, lowerAbs = 1.2, serratus = 0.8, frontDelt = 0.4, sideDelt = 0.2, lats = 0.3 },
	Roadwork = { calves = 0.8, hamstrings = 0.5, quads = 0.3, glutes = 0.2 },
	Treadmill = { calves = 0.6, hamstrings = 0.3, quads = 0.2, glutes = 0.2 },
	Bike = { quads = 0.8, calves = 0.4, glutes = 0.3, hamstrings = 0.3 },
	Rower = { lats = 0.7, upperBack = 0.9, traps = 0.3, lowerBack = 0.5, rearDelt = 0.4, quads = 0.4, glutes = 0.3, hamstrings = 0.3, biceps = 0.3, forearms = 0.4 },
	Swimming = { frontDelt = 0.5, sideDelt = 0.6, rearDelt = 0.5, lats = 0.8, upperBack = 0.5, traps = 0.2, pecs = 0.3, upperChest = 0.3,
		triceps = 0.5, biceps = 0.2, forearms = 0.2, quads = 0.3, hamstrings = 0.3, glutes = 0.3, calves = 0.3,
		abs = 0.3, obliques = 0.3, lowerAbs = 0.3, serratus = 0.3 },
	Ladder = { calves = 0.8, quads = 0.2, hamstrings = 0.1, glutes = 0.2 },
	Rope = { calves = 1.2, quads = 0.2, hamstrings = 0.2, glutes = 0.2, forearms = 0.3 },
}
for _, a in ipairs(Config.Activities) do
	a.parts = a.parts or Config.ExerciseTargets[a.id]
end

Config.Meals = {
	{ id = "Water", name = "Water (Cooler)", price = 0, hydration = 35, nutrition = 0, energy = 0, fat = 0 },
	{ id = "SportsDrink", name = "Sports Drink", price = 6, hydration = 45, nutrition = 5, energy = 4, fat = 0 },
	{ id = "FastFood", name = "Fast Food Burger", price = 12, hydration = -5, nutrition = 35, energy = 4, fat = 0.35 },
	{ id = "Balanced", name = "Balanced Meal", price = 45, hydration = 5, nutrition = 40, energy = 6, fat = 0 },
	{ id = "Protein", name = "Protein Shake", price = 25, hydration = 10, nutrition = 20, energy = 3, fat = 0, muscleBuff = 0.15 },
	{ id = "Athlete", name = "Athlete Meal Plan", price = 160, hydration = 10, nutrition = 60, energy = 10, fat = -0.05, gainsBuff = 0.1 },
	{ id = "Chef", name = "Personal Chef Feast", price = 600, hydration = 15, nutrition = 75, energy = 15, fat = -0.1, gainsBuff = 0.2, requires = "Nutritionist" },
}

Config.MittCombos = {
	-- tier 1
	{ tier = 1, name = "1-2", keys = { "jab", "cross" } },
	{ tier = 1, name = "1-1-2", keys = { "jab", "jab", "cross" } },
	{ tier = 1, name = "1-2-3", keys = { "jab", "cross", "leadhook" } },
	-- tier 2
	{ tier = 2, name = "Jab-Hook-Cross", keys = { "jab", "leadhook", "cross" } },
	{ tier = 2, name = "2-3-2", keys = { "cross", "leadhook", "cross" } },
	{ tier = 2, name = "1-2-Slip-2", keys = { "jab", "cross", "slipL", "cross" } },
	-- tier 3
	{ tier = 3, name = "Slip-Cross-Hook", keys = { "slipR", "cross", "leadhook" } },
	{ tier = 3, name = "1-2-3-2", keys = { "jab", "cross", "leadhook", "cross" } },
	{ tier = 3, name = "Body Jab-Head Cross", keys = { "jab", "cross", "rearhook" } },
	-- tier 4
	{ tier = 4, name = "Roll-Hook-Hook", keys = { "roll", "leadhook", "rearhook" } },
	{ tier = 4, name = "1-2-Uppercut-Hook", keys = { "jab", "cross", "uppercut", "leadhook" } },
	{ tier = 4, name = "Slip-Slip-Overhand", keys = { "slipL", "slipR", "overhand" } },
	-- tier 5
	{ tier = 5, name = "Champion Flurry", keys = { "jab", "cross", "leadhook", "rearhook", "uppercut" } },
	{ tier = 5, name = "Pivot-Hook-Cross-Hook", keys = { "pivotL", "leadhook", "cross", "leadhook" } },
	{ tier = 5, name = "Parry-Cross-Roll-Hook", keys = { "parry", "cross", "roll", "leadhook" } },
}
Config.MittPraise = { "That's it!", "Beautiful!", "Sharp!", "Again!", "Good, good!", "Snap it back!", "Yes! Like that!" }
Config.MittCritique = {
	sloppy = { "Clean it up!", "Don't telegraph it!", "Hands back to the chin!", "Throw what I call!" },
	slow = { "Too slow - stay sharp!", "Finish the combo!", "Faster hands!", "Don't think, react!" },
}

------------------------------------------------------------------------
-- Training sessions: drill data, coaching, grades and records
------------------------------------------------------------------------
-- one real second of a drill counts as this many seconds of training for the
-- calorie / distance / time-in readouts (a 40 s session stands in for a few minutes of work)
Config.TrainingTimeScale = 6

-- working heart-rate target (bpm) while training hard at each activity
Config.TrainingHR = {
	HeavyBag = 170, SpeedBag = 150, DoubleEnd = 156, MittWork = 166, Shadow = 142,
	Bench = 128, Dumbbells = 120, Barbell = 140, Squat = 142, PullUps = 134, MedBall = 152,
	Roadwork = 172, Treadmill = 170, Bike = 166, Rower = 172, Swimming = 158,
	Ladder = 154, Rope = 166,
}
-- recovery sessions settle the heart rate around resting HR + this offset (the sauna's heat raises it)
Config.RecoveryHR = { IceBath = -4, Stretch = 2, Massage = -6, Chamber = -8, Sauna = 44 }

-- session grades from the server's session quality (0.4 .. 1.5)
Config.Grades = {
	{ id = "S", min = 1.35, rgb = { 255, 196, 40 } },
	{ id = "A", min = 1.2, rgb = { 60, 200, 110 } },
	{ id = "B", min = 1.0, rgb = { 70, 140, 255 } },
	{ id = "C", min = 0.8, rgb = { 240, 140, 40 } },
	{ id = "D", min = 0, rgb = { 220, 40, 45 } },
}

-- coach technique tips, shown during rests between rounds and sets
Config.TrainingTips = {
	HeavyBag = {
		"Turn your hip into the cross.", "Exhale on every shot.", "Hands back to the chin after every punch.",
		"Power starts in your back foot - push off the floor.", "Punch through the bag, not at it.",
		"Move after every combination - don't stand and admire it.",
	},
	SpeedBag = {
		"Small circles - let the bag do the work.", "Keep your fists at eye level.",
		"Relax your shoulders - tension kills rhythm.", "Listen to the rhythm. It's a drum, not a fight.",
		"Hit with the side of the fist, not the knuckles.",
	},
	DoubleEnd = {
		"Watch the bag, not your gloves.", "Slip just enough - an inch is as good as a mile.",
		"Counter the moment it comes back.", "Keep your chin tucked behind your shoulder.",
		"Short, sharp shots - this bag punishes wide punches.",
	},
	MittWork = {
		"Listen for the call, then snap it back.", "Hit the mitt and return on the same line.",
		"Stay in your stance between combos.", "Breathe out sharp on every punch.",
		"After a slip, the counter comes right away.",
	},
	Shadow = {
		"Picture an opponent in front of you.", "Never cross your feet.", "Move your head after you punch.",
		"Small steps keep you balanced.", "Check the mirror: chin down, hands up.",
	},
	Bench = {
		"Shoulder blades pinched, feet planted.", "Lower it under control, drive it up hard.",
		"Breathe in on the way down, out on the push.", "Touch mid-chest on every rep.",
	},
	Dumbbells = {
		"No swinging - make the arms do the work.", "Elbows pinned to your sides.",
		"Squeeze at the top, slow on the way down.", "Strong hands make strong punches.",
	},
	Barbell = {
		"Flat back, chest up.", "Push the floor away - don't yank the bar.", "Keep the bar close to your shins.",
		"Lock out with your hips, not your lower back.", "Brace your core before every pull.",
	},
	Squat = {
		"Knees track over your toes.", "Sit back and down, chest proud.", "Drive up through your heels.",
		"Brace like you're about to take a body shot.",
	},
	MedBall = {
		"Brace your core before every slam.", "Rotate from the ribs, not the arms.", "Exhale hard as the ball hits the floor.",
		"Twist like you're slipping and coming back with a hook.", "Abs are your body-shot armour.",
	},
	PullUps = {
		"Full hang at the bottom, chin over the bar at the top.", "Pull your elbows down to your ribs.",
		"No kipping - strict reps build a strong back.", "Squeeze your shoulder blades together.",
	},
	Roadwork = {
		"Run tall with relaxed shoulders.", "Find a steady breathing rhythm.", "Roadwork wins the late rounds.",
		"Push the hills, recover on the flats.",
	},
	Treadmill = {
		"Light, quick steps - land under your hips.", "Sprint hard, then really recover.", "Your arms drive your legs.",
		"Fight pace is intervals, not jogging.",
	},
	Bike = {
		"Smooth circles, not stomps.", "Push the sprints, spin easy to recover.", "Keep your upper body still.",
		"Low impact, big engine.",
	},
	Rower = {
		"Legs, then back, then arms.", "Fast drive, slow recovery.", "Sit tall at the catch - don't hunch.",
		"The power comes from your legs, not your arms.",
	},
	Swimming = {
		"Long strokes, steady breathing.", "Swimming builds lungs without pounding the joints.",
		"Push off the wall hard every length.", "Relax your neck when you breathe.",
	},
	Ladder = {
		"Stay on the balls of your feet.", "Quick feet, quiet feet.", "Eyes up - feel the ladder.",
		"Let your arms move with your feet.",
	},
	Rope = {
		"Small jumps - an inch off the floor.", "Turn the rope with your wrists, not your arms.",
		"Land soft on the balls of your feet.", "Stay relaxed and find the rhythm.",
		"Skipping builds the legs for twelve rounds.",
	},
	IceBath = {
		"Slow breaths - fight the urge to gasp.", "The cold flushes soreness out of the muscles.",
		"Relax your shoulders and let the cold work.",
	},
	Stretch = {
		"Never bounce a stretch - ease into it.", "Breathe out to sink deeper.", "Loose muscles get injured less.",
	},
	Massage = {
		"Let the tension go on every exhale.", "Deep tissue work speeds up recovery.", "Relax into the table.",
	},
	Chamber = {
		"Oxygen, compression and cold - elite recovery.", "Breathe deep and let the machine work.",
		"Champions recover like champions.",
	},
	Sauna = {
		"Sweat out water, not muscle.", "Rehydrate right after the weigh-in.",
		"Dizzy means get out - cutting weight is not a contest.", "Small sips only until you make weight.",
	},
}

-- the coach's verdict on the result screen
Config.GradeRemarks = {
	S = { "World-class session. That's how champions train.", "Perfect. I've got nothing to fix today.", "Championship work - bottle that." },
	A = { "Sharp work. Keep that standard.", "Really good session - just small details left.", "That's the level. Again tomorrow." },
	B = { "Solid work. Now clean up the details.", "Good session - next time make it great.", "Decent. More focus next time." },
	C = { "You got through it. I need more snap.", "Sloppy in places - concentrate.", "Average. Champions don't do average." },
	D = { "That wasn't good enough. Reset and go again.", "Your mind was somewhere else today.", "We're going back to basics." },
}
-- activity-specific remarks for great (hi) and poor (lo) sessions
Config.ActivityRemarks = {
	HeavyBag = { hi = "That bag felt every shot. Heavy hands!", lo = "You're pushing the bag, not punching it. Snap!" },
	SpeedBag = { hi = "Like a drum roll - beautiful rhythm.", lo = "You're chasing the bag. Find the rhythm first." },
	DoubleEnd = { hi = "Eyes like a hawk. Nothing got through.", lo = "That bag tagged you all day. Watch it!" },
	MittWork = { hi = "Crisp. You were reading my mind.", lo = "Listen to the call before you throw." },
	Shadow = { hi = "Smooth as silk in the mirror.", lo = "Your feet were stuck. Move with purpose." },
	Bench = { hi = "Strong press. That's real power.", lo = "Control the bar - don't let it control you." },
	Dumbbells = { hi = "Clean curls, no cheating. Good.", lo = "Too much swinging. Strict reps." },
	Barbell = { hi = "Textbook pulls. Strong back.", lo = "Watch that back - technique before weight." },
	Squat = { hi = "Deep and powerful. Those legs carry punches.", lo = "Too shallow. Sit into it." },
	PullUps = { hi = "Strict and strong. That back is coming along.", lo = "Half reps don't count. Full range." },
	MedBall = { hi = "Explosive slams, sharp twists. That core can take a shot.", lo = "You're throwing it with your arms. Use your core!" },
	Roadwork = { hi = "That's championship roadwork.", lo = "You jogged it. Push the pace." },
	Treadmill = { hi = "Every interval on the money.", lo = "Hit your zones - sprint means sprint." },
	Bike = { hi = "Big engine today. Great intervals.", lo = "Your cadence was all over the place." },
	Rower = { hi = "Powerful strokes. Great splits.", lo = "Hold your stroke rate steady." },
	Swimming = { hi = "Smooth lengths. Your lungs will thank you.", lo = "Steady strokes - you're fighting the water." },
	Ladder = { hi = "Fast feet! That's ring movement.", lo = "Heavy feet. Stay light and quick." },
	Rope = { hi = "The rope was singing today.", lo = "Too many trips. Find the rhythm." },
	IceBath = { hi = "Calm in the cold. That's discipline.", lo = "Control your breathing in there." },
	Stretch = { hi = "Loose and limber. Perfect.", lo = "Breathe into the stretch, don't fight it." },
	Massage = { hi = "Fully relaxed. Great recovery.", lo = "Let go - you're still holding tension." },
	Chamber = { hi = "Maximum recovery. Fresh legs tomorrow.", lo = "Breathe with the machine." },
	Sauna = { hi = "Controlled cut. Smart work.", lo = "Easy on the breathing - stay calm in the heat." },
}

-- strength stations: exercise name, believable load range and the muscle group (and sub-muscle part) that sets it
Config.LiftLoads = {
	Bench = { name = "BENCH PRESS", min = 95, max = 315, muscle = "chest", part = "pecs" },
	Dumbbells = { name = "DUMBBELL CURLS", min = 20, max = 80, muscle = "arms", part = "biceps", each = true },
	Barbell = { name = "DEADLIFT", min = 135, max = 495, muscle = "back", part = "lowerBack" },
	Squat = { name = "BACK SQUAT", min = 115, max = 405, muscle = "legs", part = "quads" },
	PullUps = { name = "PULL-UPS", min = 0, max = 45, muscle = "back", part = "lats", bodyweight = true },
	MedBall = { name = "MED BALL SLAMS", min = 6, max = 30, muscle = "core", part = "abs" },
}

-- agility ladder drills (F = up, B = down, L = left, R = right); lv = ladder level needed
Config.LadderDrills = {
	{ name = "QUICK FEET", lv = 1, steps = { "F", "F", "F", "F", "F", "F" } },
	{ name = "LATERAL SHUFFLE", lv = 1, steps = { "R", "R", "R", "L", "L", "L" } },
	{ name = "IN-OUT", lv = 1, steps = { "F", "L", "R", "F", "L", "R", "F" } },
	{ name = "ZIG-ZAG", lv = 1, steps = { "L", "F", "R", "F", "L", "F", "R" } },
	{ name = "HOPSCOTCH", lv = 2, steps = { "F", "F", "L", "R", "F", "F", "L", "R" } },
	{ name = "ICKY SHUFFLE", lv = 2, steps = { "R", "F", "L", "L", "F", "R", "R", "F" } },
	{ name = "CROSSOVER", lv = 2, steps = { "R", "F", "R", "L", "F", "L", "R", "F" } },
	{ name = "SPRINT & BACKPEDAL", lv = 2, steps = { "F", "F", "F", "B", "B", "F", "F", "F" } },
	{ name = "CARIOCA", lv = 3, steps = { "R", "B", "R", "F", "R", "B", "R", "F", "R" } },
	{ name = "BOX DRILL", lv = 3, steps = { "F", "R", "B", "L", "F", "R", "B", "L", "F" } },
	{ name = "SNAKE", lv = 3, steps = { "L", "F", "R", "F", "L", "F", "R", "F", "L", "F" } },
}

-- shadow-boxing flow chains (F/B/L/R = steps, slipL/slipR/roll = head movement, jab/cross/leadhook = punches)
Config.ShadowFlows = {
	{ "jab", "B", "slipR", "cross" },
	{ "F", "jab", "cross", "L" },
	{ "slipL", "leadhook", "cross", "B" },
	{ "jab", "jab", "roll", "leadhook" },
	{ "roll", "cross", "leadhook", "B" },
	{ "F", "cross", "slipL", "leadhook" },
	{ "slipR", "slipL", "cross", "R" },
	{ "jab", "R", "cross", "leadhook" },
	{ "B", "jab", "F", "cross" },
	{ "jab", "cross", "roll", "cross" },
}

-- recovery session context
Config.StretchNames = { "HAMSTRINGS", "HIP FLEXORS", "SHOULDERS", "CALVES", "LOWER BACK", "QUADS", "CHEST", "NECK" }
Config.IceBathTempC = { 12, 8, 3 } -- plastic tub, ice bath, cryo tub
Config.SaunaTempC = { 0, 90, 60 } -- sauna suit (no room), wooden sauna, infrared sauna

------------------------------------------------------------------------
-- World & flavor
------------------------------------------------------------------------
Config.Nationalities = {
	"USA", "Mexico", "United Kingdom", "Ireland", "Philippines", "Japan", "Cuba", "Puerto Rico",
	"Ukraine", "Kazakhstan", "Russia", "Nigeria", "Ghana", "South Africa", "Brazil", "Argentina",
	"Canada", "Australia", "France", "Germany", "Italy", "Spain", "Dominican Republic", "Jamaica",
	"Haiti", "Venezuela", "Colombia", "Thailand", "South Korea", "China", "India", "Uzbekistan",
	"Cameroon", "Kenya", "New Zealand", "Poland", "Sweden", "Turkey", "Egypt", "Morocco",
}
Config.Genders = { "Male", "Female" }
Config.VoiceTypes = { "Deep", "Raspy", "Smooth", "Hype", "Calm" }

Config.FirstNames = {
	"Marcus", "Diego", "Tyson", "Andre", "Kenji", "Aleksandr", "Oleksandr", "Manny", "Carlos", "Liam",
	"Darnell", "Rafael", "Viktor", "Kwame", "Tunde", "Jamal", "Mateo", "Sean", "Connor", "Hiroshi",
	"Luis", "Jorge", "Emmanuel", "Isaac", "Dmitri", "Ivan", "Nikolai", "Jose", "Miguel", "Terrence",
	"Devon", "Malik", "Andrzej", "Erik", "Lars", "Paulo", "Thiago", "Ricardo", "Omar", "Youssef",
	"Samuel", "Joshua", "Daniel", "Anthony", "Callum", "Ryota", "Naoya", "Jin", "Wei", "Arjun",
	"Bektemir", "Daulet", "Juan", "Felix", "Kofi", "Chidi", "Tremaine", "Xavier", "Gideon", "Shamar",
	"Rolando", "Errol", "Tobias", "Vasil", "Simon", "Dante", "Elijah", "Rocco", "Angelo", "Mikhail",
}
Config.FirstNamesF = {
	"Clara", "Katie", "Amanda", "Alicia", "Selena", "Mikayla", "Natasha", "Savannah", "Lauren",
	"Ebony", "Chantelle", "Maria", "Yolanda", "Rania", "Shannon", "Terri", "Jessica", "Erika",
	"Naoko", "Hana", "Lucia", "Camila", "Adaeze", "Zara", "Imani", "Sofia", "Elena", "Olena",
}
Config.LastNames = {
	"Alvarez", "Johnson", "Okafor", "Tanaka", "Petrov", "Kovalenko", "Ramirez", "Murphy", "Walsh",
	"Garcia", "Mendoza", "Reyes", "Santos", "Silva", "Williams", "Brooks", "Carter", "Mensah",
	"Adeyemi", "Boateng", "Nakamura", "Inoue", "Kim", "Park", "Zhang", "Singh", "Ivanov", "Volkov",
	"Smirnov", "Novak", "Kowalski", "Fischer", "Muller", "Rossi", "Bianchi", "Lopez", "Hernandez",
	"Cruz", "Torres", "Diaz", "Morales", "Ortiz", "Castillo", "Vargas", "Romero", "Haddad", "Benali",
	"Abdullaev", "Zhakupov", "Usmonov", "OConnor", "Fitzgerald", "Hughes", "Thompson", "Davis",
	"Jackson", "Harris", "Stone", "Steele", "Knox", "Rivers", "King", "Price", "Grant", "Banks",
	"Duarte", "Pacheco", "Okonkwo", "Ndlovu", "Kariuki", "Lindqvist", "Yilmaz", "Mahmoud", "Sato",
}
Config.Nicknames = {
	"The Hammer", "Iron Fist", "El Toro", "The Assassin", "Lightning", "The Monster", "Bad Intentions",
	"The Professor", "Smoke", "The Machine", "Hit Squad", "Golden Boy", "The Ghost", "Thunder",
	"Dynamite", "The Butcher", "Showtime", "Cobra", "The Truth", "Gravedigger", "Red Dragon",
	"The Surgeon", "Nightmare", "Pretty Boy", "The Problem", "Venom", "Hurricane", "The Viking",
	"Kid Dynamo", "Babyface", "The Bull", "Silk", "Razor", "King Kong", "The Saint", "Warrior",
	"Rocket", "Mad Dog", "The Wolf", "Diamond",
}

Config.Personalities = {
	"Trash Talker", "Respectful Veteran", "Showman", "Silent Assassin", "Hothead", "Technician",
}
Config.TrashTalk = {
	["Trash Talker"] = {
		"%s is a paper champion. I'm about to fold them up and mail them home.",
		"I've seen better footwork at a bus stop. %s is in over their head.",
		"Tell %s to bring a stretcher to the arena. They'll need it.",
	},
	["Respectful Veteran"] = {
		"%s is a fine young fighter, but experience wins fights like this.",
		"I respect %s. That respect ends when the bell rings.",
	},
	["Showman"] = {
		"The cameras love me, and after fight night they'll love watching %s fall.",
		"It's showtime, baby. %s is just my opening act.",
	},
	["Silent Assassin"] = {
		"...I'll do my talking in the ring.",
		"Nothing to say about %s. Fight night says it all.",
	},
	["Hothead"] = {
		"I can't stand %s. I'm going to hurt them. Simple as that.",
		"Get %s out of my face before the weigh-in turns into a fight!",
	},
	["Technician"] = {
		"%s drops the right hand after the jab. I've watched the tape. It's over.",
		"I've studied %s for months. Every habit, every tell.",
	},
}
Config.RevengeTalk = {
	"Last time was a fluke. This time %s goes to sleep.",
	"I've thought about that loss every day. %s owes me.",
	"Rematch clause, revenge mission. %s knows what's coming.",
}
Config.TrilogyTalk = {
	"One win each. This trilogy decides who the better fighter really is, %s.",
	"Rubber match. History remembers the winner of this one, %s.",
}
-- the player's press-conference lines, by voice type (%s = opponent)
Config.VoiceLines = {
	Deep = { "I don't talk much. Fight night, %s finds out why.", "Heavy hands, heavy heart. %s is in trouble." },
	Raspy = { "I've been through wars, %s. You're just another one.", "Listen close, %s. I'm coming for everything." },
	Smooth = { "No disrespect, %s, but this is my era.", "Stay calm, look good, win clean. Sorry, %s." },
	Hype = { "LET'S GO! %s picked the WRONG fighter!", "I'm the future, baby! %s is the past!" },
	Calm = { "I've prepared well. %s is a good fighter. I'm better.", "We trained for everything %s can do." },
}
Config.AnnouncerIntro = {
	Deep = "In the red corner... a quiet storm...",
	Raspy = "In the red corner... battle-tested and hungry...",
	Smooth = "In the red corner... the smoothest operator in the sport...",
	Hype = "In the red corner... the most electric fighter alive...",
	Calm = "In the red corner... composed, clinical, dangerous...",
}

-- Fictional all-time greats for the GOAT ranking
Config.Legends = {
	{ name = "\"Thunder\" Jack Monroe", score = 1400 },
	{ name = "Ray \"Silk\" Delacroix", score = 1320 },
	{ name = "Ivan \"The Bear\" Koslov", score = 1250 },
	{ name = "Benny \"Golden Hands\" Ortega", score = 1180 },
	{ name = "Marvin \"The Marvel\" Hayes", score = 1110 },
	{ name = "Kazuo \"Typhoon\" Mori", score = 1040 },
	{ name = "Sugar Lou Whitfield", score = 980 },
	{ name = "Archie \"Old Mongoose\" Banks", score = 900 },
	{ name = "Roberto \"Iron Palms\" Villa", score = 860 },
	{ name = "Joe \"The Bomber\" Lyle", score = 820 },
	{ name = "Percy \"Smooth\" Grant", score = 740 },
	{ name = "Henry \"Hammerin\" Armstead", score = 690 },
	{ name = "Manuel \"El Relampago\" Quezon", score = 650 },
	{ name = "Cesar \"El Brujo\" Zamora", score = 580 },
	{ name = "Tommy \"Tornado\" Hearne", score = 520 },
	{ name = "Ricky \"The Rocket\" Hart", score = 430 },
	{ name = "Wilfred \"Cannon\" Gamez", score = 380 },
	{ name = "Danny \"Red Fox\" Lowes", score = 300 },
	{ name = "Gus \"The Brick\" Pemberton", score = 220 },
	{ name = "Eddie \"The Eagle\" Tran", score = 150 },
}
Config.HallOfFameScore = 450

------------------------------------------------------------------------
-- Gym facility tiers (one per player; derived, never saved)
------------------------------------------------------------------------
-- Computed by Catalog.GymTier(gymLevels, owned, careerTier) from the average upgrade progress
-- over Catalog.StationOrder (frac 0..1), the career tier, and Shop ownership.
-- A tier is reached when frac >= minFrac AND careerTier >= minCareerTier (or the player owns
-- any orOwned item instead of the career tier) AND owns every needsOwned item. An orOwned item whose
-- shop requiresTier is at or above minCareerTier is no shortcut (only an admin grant can use it), so
-- Catalog.GymTierNeeds does not advertise it; lower that item's requiresTier to make it a real one.
-- growth multiplies muscle growth (stat gains already use each station's level mult).
-- facilities = what this tier ADDS (cumulative with the tiers below); visuals are client-only.
Config.GymTiers = {
	{ id = "Beginner", name = "Beginner Gym", minFrac = 0, minCareerTier = 1, growth = 1.0,
		desc = "Torn bags, taped ropes, flickering lights and water stains",
		facilities = { "wornRing", "freeWeights", "cardioCorner", "recoveryBasics" } },
	{ id = "Intermediate", name = "Intermediate Gym", minFrac = 0.25, minCareerTier = 2, growth = 1.04,
		desc = "Fresh paint, club ring, sponsor banners and LED strips",
		facilities = { "clubRing", "sponsorBanners", "ledStrips", "roundTimers", "careerPosters" } },
	{ id = "Elite", name = "Elite Training Center", minFrac = 0.55, minCareerTier = 5, orOwned = { "SmartSystem" }, growth = 1.08,
		desc = "Elite Performance wing: cryotherapy, recovery pools, sports science, motion tracking",
		facilities = { "eliteWing", "cryotherapy", "plungePools", "sportsScience", "motionTracking", "analyticsWall", "glassPartitions" } },
	{ id = "WorldChampion", name = "World Champion Facility", minFrac = 0.8, minCareerTier = 8, needsOwned = { "RecoveryChamber" }, growth = 1.12,
		desc = "Home of the champ: gold trim, title photos, media wall, fans at the door",
		facilities = { "championWall", "titlePhotos", "goldTrim", "mediaBackdrop", "redCarpet", "fanZone", "championBanner" } },
}
Config.FacilityNames = {
	wornRing = "Worn Gym Ring", freeWeights = "Free Weights", cardioCorner = "Cardio Corner", recoveryBasics = "Ice Tub & Stretch Mats",
	clubRing = "Club Ring", sponsorBanners = "Sponsor Banners", ledStrips = "LED Strips", roundTimers = "Round Timers", careerPosters = "Career Posters",
	eliteWing = "Elite Performance Wing", cryotherapy = "Cryotherapy Cabin", plungePools = "Hot & Cold Plunge Pools",
	sportsScience = "Sports Science Lab", motionTracking = "Motion Tracking Cameras", analyticsWall = "Analytics Wall", glassPartitions = "Glass Partitions",
	championWall = "Champion Wall", titlePhotos = "Championship Photos", goldTrim = "Gold Trim", mediaBackdrop = "Media Backdrop",
	redCarpet = "Red Carpet", fanZone = "Fan Zone", championBanner = "Champion Banner",
}

------------------------------------------------------------------------
-- Character detail levels (Builder opts.detail) and expressions
------------------------------------------------------------------------
-- full = players + fight opponent, medium = gym NPCs / referee, low = far or crowd NPCs.
-- Budgets are extra parts over the pre-BALD-MODE character WITH its old hair: full = A 60 (face rig,
-- eyes, skin, hair beyond the old hair) + B 60 (body/gear). Fight damage (<= 20, temporary) is counted
-- separately. Strands/veins are Beams (no parts).
Config.Detail = {
	full = { partBudget = 120, eyeExtras = true, freckles = 26, wrinkles = true, sweatBeads = true, strands = 80, hairBumps = 53,
		muscleLayers = 2, grooves = true, veins = true, wordmarks = true, laces = "full", shadows = true },
	medium = { partBudget = 20, eyeExtras = false, freckles = 8, wrinkles = true, sweatBeads = false, strands = 16, hairBumps = 18,
		muscleLayers = 1, grooves = false, veins = false, wordmarks = false, laces = "merged", shadows = false },
	low = { partBudget = 0, eyeExtras = false, freckles = 0, wrinkles = false, sweatBeads = false, strands = 0, hairBumps = 10,
		muscleLayers = 1, grooves = false, veins = false, wordmarks = false, laces = "none", shadows = false },
}
Config.DetailAliases = { hero = "full", npc = "medium", lite = "low" }
-- (opts) -> "full"|"medium"|"low", its Config.Detail entry. Missing/unknown -> full.
function Config.DetailLevel(opts)
	local d = type(opts) == "table" and (opts.detail or opts.lod) or opts
	d = Config.DetailAliases[d] or d
	if not Config.Detail[d] then
		d = "full"
	end
	return d, Config.Detail[d]
end

-- Anatomy meshes (EditableMesh characters built on each client from the server's LookData; the round-1
-- parts stay as the fallback). AnatomyClient reads these; ANATOMY_CONTRACTS.md is the full contract.
-- tris = triangle budgets per section and level of detail (the generators must stay under them).
Config.Anatomy = {
	enabled = true, -- master switch; false = everyone keeps the part-built look
	maxFull = 6, -- full-detail characters near the camera besides the local player and the fight opponent
	fullRange = 70, -- studs: full detail inside, medium beyond
	lodRange = 160, -- studs: no meshes beyond (round-1 parts)
	frameBudget = 0.0025, -- seconds of mesh generation per frame (time-sliced, never a hitch)
	textures = true, -- pieces may carry a generated colour texture (EditableImage)
	tris = {
		Body = { full = 9000, medium = 4000, low = 1500 },
		Head = { full = 5000, medium = 2000, low = 700 },
		Hair = { full = 10000, medium = 4000, low = 1200 },
	},
}

-- Expr model attribute values (face rig blend targets on the client)
Config.Expressions = { "neutral", "confident", "determined", "anger", "fear", "fatigue", "pain", "dazed", "effort", "happy", "ko" }

-- true = draw no hair at all (the old hard-coded BALD MODE); kept as a one-line debug toggle
Config.BaldMode = false

-- daily growth of hair / beard (0..1.5 / 0..1) used by Training.dayTick
Config.HairGrowthPerDay = 0.02
Config.BeardGrowthPerDay = 0.02

------------------------------------------------------------------------
-- Sounds
------------------------------------------------------------------------
-- Only these ship with every Roblox client and are safe to play anywhere.
Config.BuiltinSounds = {
	Thud = "rbxasset://sounds/action_jump_land.mp3",
	Footsteps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Falling = "rbxasset://sounds/action_falling.ogg",
	Jump = "rbxasset://sounds/action_jump.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	SwordHit = "rbxasset://sounds/swordhit.wav",
	SwordLunge = "rbxasset://sounds/swordlunge.wav",
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Button = "rbxasset://sounds/button.wav",
	Click = "rbxasset://sounds/clickfast.wav",
	Grunt = "rbxasset://sounds/uuhhh.mp3",
}
-- Optional uploaded assets. Every entry defaults to "" and is SKIPPED when empty: the game ships
-- silent-safe (no uploaded audio can be vouched for), and code falls back to a shaped built-in from
-- Config.SoundFallbacks or to silence. Read through Config.SoundId(key) (upload only) or
-- Config.SoundSpec(key) (upload, else the shaped stand-in).
--
-- FOR THE OWNER: paste an audio asset you own or that is public on the Creator Store (Roblox-made or
-- licensed for any experience), as "rbxassetid://123456789" or just the number. Test each in Studio:
-- an id the experience may not play stays silent and only warns in the output.
--   key            where it plays                                 what to upload (length, loop)
--   CrowdMurmur    arena crowd bed, all fight night (VenueFX)      indoor crowd chatter/walla, 30-90 s seamless loop
--   CrowdRoar      arena roar swell on big shots / KDs / walkout   stadium cheer, 10-30 s loop (volume is driven)
--   CrowdOoh       crowd reaction to a hard landed shot            short "ooooh!" gasp, 1-2 s one-shot
--   CrowdBoo       crowd reaction to holding / a dull round        short boo, 2-3 s one-shot
--   RingBell       round start / end bell (venues + gym timers)    single boxing-bell ding, < 1 s (code repeats it)
--   WalkoutMusic   fighter walkout to the ring                     hype hip-hop / rock instrumental, 60 s+ loop
--   ArenaMusic     arena between rounds / before the walkout       arena PA music bed, 60 s+ loop
--   GymMusic       wall speakers in the gym                        upbeat workout instrumental, 60 s+ loop
--   CoachShout     coaches shouting instructions in the gym        short male shout ("Hey!" / "Go!"), < 1 s one-shot
--   CornerShout    your corner shouting during rounds              short urgent shout, < 1 s one-shot
--   RefereeCount   referee count over a knockdown                  one count word or a clap-like call, < 1 s (repeated)
--   Announcer      ring announcer intro                            "Let's get ready..." style intro, 3-8 s one-shot
--   BagThud / BagChain / SpeedBag / PunchImpact / BodyShot         gym and fight impacts (built-in thuds already
--                  play when empty; uploads replace them)
--   GymAmbience    gym room tone (Ambience)                        quiet gym room tone, 30 s+ loop
--   CityAmbience   city streets                                    distant traffic / city bed, 30 s+ loop
--   Heartbeat      fight heartbeat when hurt                       single low heartbeat thump, < 0.5 s
--   Breathing      heavy breathing when gassed                     exhausted breathing, 2-4 s loop
--   CameraFlash    ringside photographers                          camera shutter click, < 0.3 s
Config.SoundIds = {
	CrowdRoar = "", CrowdMurmur = "", CrowdBoo = "", CrowdOoh = "", -- arena crowd bed / reactions
	RingBell = "", -- round bell
	WalkoutMusic = "", ArenaMusic = "", GymMusic = "", -- music beds
	CoachShout = "", CornerShout = "", RefereeCount = "", Announcer = "", -- voices
	BagThud = "", BagChain = "", SpeedBag = "", PunchImpact = "", BodyShot = "", -- impacts
	GymAmbience = "", CityAmbience = "", Heartbeat = "", Breathing = "", CameraFlash = "",
}

-- an upload id in a usable form, or nil: "" / anything that is not an asset reference is skipped, a bare
-- number (or numeric string) becomes "rbxassetid://n", so a mistyped entry never errors or plays junk
function Config.SoundId(key)
	local id = Config.SoundIds[key]
	if type(id) == "number" then
		id = id == id and id > 0 and string.format("rbxassetid://%d", id) or nil
	elseif type(id) == "string" then
		id = string.gsub(id, "^%s+", "")
		id = string.gsub(id, "%s+$", "")
		if string.match(id, "^%d+$") then
			id = "rbxassetid://" .. id
		elseif not (string.match(id, "^rbxassetid://%d+$") or string.match(id, "^rbxasset://%S+$")
			or string.match(id, "^https?://www%.roblox%.com/asset/%?id=%d+$")) then
			id = nil
		end
	else
		id = nil
	end
	return id
end

-- Shaped stand-ins built from Config.BuiltinSounds for slots where a built-in can pass for the real
-- thing at a distance; false = no believable stand-in (music, spoken lines): stay silent and let the
-- speech bubble / HUD text carry it. volume is a multiplier on the caller's own level, spread a
-- random +- PlaybackSpeed share per play.
Config.SoundFallbacks = {
	CrowdMurmur = { builtin = "Footsteps", speed = 0.42, volume = 0.45, looped = true }, -- low shuffling rumble
	CrowdRoar = { builtin = "Falling", speed = 0.55, volume = 0.6, looped = true }, -- slowed wind rush
	CrowdOoh = { builtin = "Grunt", speed = 0.72, volume = 0.7, spread = 0.06 }, -- pitched-down "uuhh" = "oooh"
	CrowdBoo = { builtin = "Grunt", speed = 0.52, volume = 0.6, spread = 0.05 }, -- low "uuh" = "booo"
	RingBell = { builtin = "SwordHit", speed = 0.62, volume = 0.35, spread = 0.01 }, -- metallic ding
	CoachShout = { builtin = "Grunt", speed = 1.0, volume = 0.3, spread = 0.1 }, -- a barked "huh!"
	CornerShout = { builtin = "Grunt", speed = 1.08, volume = 0.3, spread = 0.1 },
	RefereeCount = { builtin = "Click", speed = 0.8, volume = 0.45 }, -- a tick per count (FightClient's own stand-in)
	Announcer = false, -- spoken words: text only
	WalkoutMusic = false, ArenaMusic = false, GymMusic = false, -- no built-in music
	BagThud = { builtin = "Thud", speed = 1.0, volume = 0.55, spread = 0.07 },
	BodyShot = { builtin = "Thud", speed = 0.82, volume = 0.6, spread = 0.06 },
	PunchImpact = { builtin = "Thud", speed = 1.6, volume = 0.38, spread = 0.12 },
	SpeedBag = { builtin = "Thud", speed = 2.4, volume = 0.32, spread = 0.12 },
	BagChain = { builtin = "SwordHit", speed = 1.9, volume = 0.07, spread = 0.25 },
	GymAmbience = false, -- Ambience already runs a slowed-wind HVAC bed
	CityAmbience = { builtin = "Falling", speed = 0.4, volume = 0.08, looped = true }, -- distant wind / traffic hush
	Heartbeat = { builtin = "Thud", speed = 0.55, volume = 0.5 },
	Breathing = false,
	CameraFlash = { builtin = "Click", speed = 1.4, volume = 0.25, spread = 0.1 }, -- shutter click
}

-- slots that are beds (looped) whether uploaded or stood in for
local LOOPED_SOUNDS = {
	CrowdMurmur = true, CrowdRoar = true, WalkoutMusic = true, ArenaMusic = true, GymMusic = true,
	GymAmbience = true, CityAmbience = true, Breathing = true,
}

-- (key) -> { id, speed, volume, looped, spread, uploaded } or nil (stay silent). An upload plays
-- unshaped (speed 1, volume 1); otherwise the Config.SoundFallbacks stand-in. Never errors.
function Config.SoundSpec(key)
	local id = Config.SoundId(key)
	if id then
		return { id = id, speed = 1, volume = 1, spread = 0, looped = LOOPED_SOUNDS[key] == true, uploaded = true }
	end
	local fb = Config.SoundFallbacks[key]
	local bid = type(fb) == "table" and Config.BuiltinSounds[fb.builtin] or nil
	if not bid then
		return nil
	end
	return {
		id = bid, speed = tonumber(fb.speed) or 1, volume = tonumber(fb.volume) or 1, spread = tonumber(fb.spread) or 0,
		looped = fb.looped == true or LOOPED_SOUNDS[key] == true, uploaded = false,
	}
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function Config.FindById(list, id)
	for _, item in ipairs(list) do
		if item.id == id or item.name == id then
			return item
		end
	end
	return nil
end

function Config.WeightClassIndex(name)
	for i, wc in ipairs(Config.WeightClasses) do
		if wc.name == name then
			return i
		end
	end
	return 5
end

function Config.HeightText(inches)
	inches = math.floor(inches + 0.5)
	return string.format("%d'%d\"", math.floor(inches / 12), inches % 12)
end

function Config.Money(n)
	n = math.floor(n or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (n < 0 and "-$" or "$") .. out
end

-- grade letter (S/A/B/C/D) for a session quality
function Config.GradeFor(quality)
	local q = tonumber(quality) or 0
	for _, g in ipairs(Config.Grades) do
		if q >= g.min then
			return g.id
		end
	end
	return "D"
end

function Config.GradeInfo(id)
	for _, g in ipairs(Config.Grades) do
		if g.id == id then
			return g
		end
	end
	return Config.Grades[#Config.Grades]
end

-- session quality as the percentage the player sees (a perfect drill = 100%)
function Config.QualityPct(quality)
	local q = tonumber(quality) or 0
	if q ~= q then
		q = 0
	end
	return math.clamp(math.floor(q * 100 / 1.45 + 0.5), 0, 100)
end

function Config.Overall(stats)
	local total = 0
	for _, k in ipairs(Config.StatKeys) do
		total += stats[k] or 0
	end
	return math.floor(total / #Config.StatKeys + 0.5)
end

return Config
