-- Training: the advanced training system.
-- Condition (energy, hydration, nutrition, sleep, fatigue), overtraining & injuries,
-- days and sleep, meals, gym equipment levels/condition/repairs, gear wear,
-- coaches, body evolution (21 sub-muscles -> 7 groups, soreness, supercompensation,
-- detraining, vascularity, pump, body fat, weight, physique), weigh-ins, fight-night
-- modifiers from the build, persistent face damage / head trauma, and save migration.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))

local Training = {}
local rng = Random.new()
local MG = Config.MuscleGrowth
local FD = Config.FaceDamage

local function clamp(v, a, b)
	return math.clamp(v, a, b)
end

local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

-- a finite number or the default: NaN / inf / strings from a corrupt save never reach the math
-- (one NaN in profile.body would spread through SyncGroups, weight and every fight)
local function finite(v, default)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

-- share of each sub-muscle in its group (group = sum(share * part))
local PART_SHARE = {}
for _, p in ipairs(Config.MuscleParts) do
	PART_SHARE[p.id] = p.share
end

-- the body type (bone structure) sets the muscle cap: 100 * potential for every part and group
function Training.Frame(profile)
	local app = profile.appearance
	local id = type(app) == "table" and type(app.body) == "table" and app.body.frame or nil
	return Config.FindById(Config.BodyTypes, id) or Config.BodyTypes[2]
end

function Training.MuscleCap(profile)
	return 100 * Training.Frame(profile).potential
end

-- lazily created C-only tables (old saves and fresh careers may not have them yet)
local function conditionTable(profile, key)
	local c = profile.condition
	if type(c[key]) ~= "table" then
		c[key] = {}
	end
	return c[key]
end

local function muscleLog(profile)
	if type(profile.muscleLog) ~= "table" then
		profile.muscleLog = {}
	end
	return profile.muscleLog
end

------------------------------------------------------------------------
-- New-career defaults
------------------------------------------------------------------------
-- Everyone starts lean: each sub-muscle sits near a low group seed with mild genetic asymmetry
-- (+-15%) and one naturally gifted part, so no two new boxers are built exactly alike.
function Training.NewBody(frameId)
	local frame = Config.FindById(Config.BodyTypes, frameId) or Config.BodyTypes[2]
	local body = {}
	for _, k in ipairs(Config.MuscleKeys) do
		local seed = (6 + rng:NextNumber(0, 5)) * frame.potential
		for _, p in ipairs(Config.MuscleGroupParts[k]) do
			body[p.id] = math.floor(seed * (1 + rng:NextNumber(-0.15, 0.15)) * 10) / 10
		end
	end
	local gifted = Config.MuscleParts[rng:NextInteger(1, #Config.MuscleParts)]
	body[gifted.id] = math.floor(body[gifted.id] * 12.5) / 10
	body.fat = 14 + rng:NextNumber(-1, 1.5)
	body.vasc = 0
	Config.SyncGroups(body)
	return body
end

-- Per-part detraining floor: what the boxer started with, so neglect can never leave a muscle
-- smaller than a brand-new boxer's (CreateProfile records the real seed with fromBody = true).
-- Saves from before it get 6 * potential, the low end of NewBody's seed. C only, never sent.
function Training.MuscleBase(profile, fromBody)
	local base = profile.muscleBase
	if type(base) ~= "table" then
		base = {}
		profile.muscleBase = base
	end
	local def = 6 * Training.Frame(profile).potential
	local cap = Training.MuscleCap(profile)
	local body = type(profile.body) == "table" and profile.body or {}
	for k in pairs(base) do
		if not PART_SHARE[k] then
			base[k] = nil
		end
	end
	for _, p in ipairs(Config.MuscleParts) do
		local v = finite(base[p.id], nil)
		if v == nil then
			v = fromBody and finite(body[p.id], def) or def
		end
		base[p.id] = clamp(v, 0, cap)
	end
	return base
end

function Training.NewCondition()
	-- sore = { [group] = 0..1 }, pending = { [partId] = growth due tonight }, trauma 0..100,
	-- face = persistent dmg table or nil (Config.FaceDamage)
	return {
		energy = 100, hydration = 80, nutrition = 70, fatigue = 0, sleepQ = 0.8, injuries = {}, buffs = {}, water = 0, flexible = false,
		sore = {}, pending = {}, trauma = 0,
	}
end

function Training.NewGym()
	local gym = { levels = {}, cond = {} }
	for id, st in pairs(Catalog.Stations) do
		gym.levels[id] = 1
		gym.cond[id] = (id == "heavybag" or id == "speedbag" or id == "doubleend") and 60 or 80
		if st.levels[1].cost > 0 then
			gym.levels[id] = 0
		end
	end
	return gym
end

function Training.NewGear()
	local gear = {
		owned = { gloves = { Worn = true }, shoes = { Sneakers = true }, wraps = { OldWraps = true }, mouthguard = { BoilBite = true }, robe = { None = true } },
		equipped = { gloves = "Worn", shoes = "Sneakers", wraps = "OldWraps", mouthguard = "BoilBite", robe = "None" },
		cond = {},
	}
	gear.cond["gloves:Worn"] = Catalog.Find(Catalog.Gloves, "Worn").startCondition
	gear.cond["shoes:Sneakers"] = Catalog.Find(Catalog.Shoes, "Sneakers").startCondition
	gear.cond["wraps:OldWraps"] = Catalog.Find(Catalog.Wraps, "OldWraps").startCondition
	return gear
end

function Training.NewCoaches()
	local c = {}
	for _, spec in ipairs(Catalog.CoachSpecialties) do
		c[spec.id] = 0
	end
	return c
end

------------------------------------------------------------------------
-- Lookups
------------------------------------------------------------------------
function Training.Activity(id)
	-- strings only: FindById matches the first entry without a name for a nil id
	if type(id) ~= "string" then
		return nil
	end
	return Config.FindById(Config.Activities, id)
end

function Training.StationLevel(profile, stationId)
	local st = Catalog.Stations[stationId]
	if not st then
		return 1, nil
	end
	local lv = math.max(1, profile.gym.levels[stationId] or 1)
	return lv, st.levels[math.min(lv, #st.levels)]
end

function Training.GearItem(profile, kind)
	local id = profile.gear.equipped[kind]
	return Catalog.Find(Catalog.GearList(kind) or {}, id), id
end

function Training.GearCondition(profile, kind)
	local id = profile.gear.equipped[kind]
	if kind == "mouthguard" or kind == "robe" then
		return 100
	end
	return profile.gear.cond[kind .. ":" .. tostring(id)] or 100
end

function Training.Owned(profile, id)
	return type(profile.owned) == "table" and profile.owned[id] == true
end

-- extra share from the Home Gym add-on (Catalog.Shop HomeGym.gains): stat gains AND muscle growth
local function homeGymBonus(profile)
	if Training.Owned(profile, "HomeGym") then
		local item = Catalog.Find(Catalog.Shop, "HomeGym")
		return item and tonumber(item.gains) or 0
	end
	return 0
end

-- the derived gym facility tier (Config.GymTiers): index, def. Never saved.
function Training.GymTier(profile)
	local ok, idx, def = pcall(Catalog.GymTier, profile.gym and profile.gym.levels, profile.owned, profile.tier)
	if ok and type(def) == "table" then
		return idx, def
	end
	return 1, Config.GymTiers[1]
end

local function activeInjury(profile, id)
	for _, inj in ipairs(profile.condition.injuries or {}) do
		if inj.id == id and (tonumber(inj.days) or 0) > 0 then
			return inj
		end
	end
	return nil
end

-- is an injury of this id running? (fight hand-off: pData.concussed / pData.injuryCut)
function Training.HasInjury(profile, id)
	return activeInjury(profile, id) ~= nil
end

-- adds an injury (or extends a running one); sev 0..1 picks the length inside the def's range.
-- healed = days it has already been healing (an injury dated in the past; x1.5 with the Physio like
-- Training.Heal). Returns the injury name, whether it is new and the days left (0 = already over).
local function addInjury(profile, id, sev, healed)
	local def = Config.Injuries[id]
	if not def then
		return nil, false, 0
	end
	local c = profile.condition
	if type(c.injuries) ~= "table" then
		c.injuries = {}
	end
	local days = math.floor(def.days[1] + (def.days[2] - def.days[1]) * clamp(finite(sev, 0.5), 0, 1) + 0.5)
	healed = math.max(0, finite(healed, 0)) * (Training.Owned(profile, "Physio") and 1.5 or 1)
	days = math.max(0, days - healed)
	if days <= 0 then
		return def.name, false, 0
	end
	local cur = activeInjury(profile, id)
	if cur then
		cur.days = math.max(cur.days, days)
		return def.name, false, cur.days
	end
	table.insert(c.injuries, { id = id, days = days })
	return def.name, true, days
end

function Training.ActiveInjuries(profile)
	local list = {}
	for _, inj in ipairs(profile.condition.injuries) do
		if inj.days > 0 then
			table.insert(list, inj)
		end
	end
	return list
end

function Training.BlockedBy(profile, actId)
	for _, inj in ipairs(Training.ActiveInjuries(profile)) do
		local def = Config.Injuries[inj.id]
		if def and table.find(def.blocks, actId) then
			return def.name
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Body: weight & development
------------------------------------------------------------------------
function Training.MuscleTotal(profile)
	local t = 0
	for _, k in ipairs(Config.MuscleKeys) do
		t += profile.body[k] or 0
	end
	return t
end

function Training.Weight(profile)
	local b = profile.body
	return profile.physical.baseWeight + Training.MuscleTotal(profile) * 0.03 + ((b.fat or 14) - 14) * 1.1 + (profile.condition.water or 0)
end

function Training.SetBaseWeight(profile, targetWeight)
	profile.physical.baseWeight = targetWeight - Training.MuscleTotal(profile) * 0.03 - ((profile.body.fat or 14) - 14) * 1.1
end

-- The one source of truth for a player's physique (Hub badge AND the rendered body, via
-- Career.LookOpts opts.physique): a pinned appearance.body.physique wins, otherwise the build is
-- classified by the shared Config rule. -> { id, name, desc, pinned }
function Training.PhysiqueInfo(profile)
	local app = type(profile.appearance) == "table" and profile.appearance or {}
	local appBody = type(app.body) == "table" and app.body or {}
	local pin = appBody.physique
	local def = type(pin) == "string" and pin ~= "Auto" and Config.FindById(Config.Physiques, pin) or nil
	local pinned = def ~= nil
	if not def then
		local champion = false
		for _, held in pairs(type(profile.belts) == "table" and profile.belts or {}) do
			if held == true then
				champion = true
			end
		end
		-- the last classified id gives the rule its hysteresis (a 0.1% fat change or one session must
		-- not flip the badge and the rendered body back and forth at a threshold)
		local c = type(profile.condition) == "table" and profile.condition or nil
		local prev = c and type(c.physiqueId) == "string" and c.physiqueId or nil
		local ok, id = pcall(Config.ClassifyPhysique, profile.body, {
			frame = Training.Frame(profile).id, tier = profile.tier, overall = profile.overall, champion = champion,
			weightClass = type(profile.physical) == "table" and profile.physical.weightClass or nil, prev = prev,
		})
		def = ok and Config.FindById(Config.Physiques, id) or nil
		if def and c then
			c.physiqueId = def.id
		end
		def = def or Config.FindById(Config.Physiques, prev or "Balanced") or Config.FindById(Config.Physiques, "Balanced")
	end
	return { id = def.id, name = def.name, desc = def.desc, pinned = pinned }
end

-- display name (Hub: P.physique)
function Training.Physique(profile)
	return Training.PhysiqueInfo(profile).name
end

------------------------------------------------------------------------
-- Gains
------------------------------------------------------------------------
function Training.CoachBoost(profile, statKey)
	local boost = 0
	for _, spec in ipairs(Catalog.CoachSpecialties) do
		local tier = profile.coaches[spec.id] or 0
		if tier > 0 and table.find(spec.stats, statKey) then
			boost += Catalog.CoachTiers[tier].boost
		end
	end
	return boost
end

function Training.ConditionMultiplier(profile)
	local c = profile.condition
	local m = 1
	if c.hydration < 15 then
		m *= 0.6
	elseif c.hydration < 30 then
		m *= 0.8
	end
	if c.nutrition < 15 then
		m *= 0.6
	elseif c.nutrition < 30 then
		m *= 0.8
	end
	if c.fatigue > 80 then
		m *= 0.5
	elseif c.fatigue > 60 then
		m *= 0.7
	elseif c.fatigue > 40 then
		m *= 0.85
	end
	if c.energy < 25 then
		m *= 0.8
	end
	m *= 0.85 + 0.2 * (c.sleepQ or 0.8)
	return m
end

function Training.GainMultiplier(profile, statKey, act)
	local m = 1 + Training.CoachBoost(profile, statKey)
	if Training.Owned(profile, "SmartSystem") then
		m += 0.1
	end
	if Training.Owned(profile, "EliteCamp") then
		m += 0.1
	end
	if Training.Owned(profile, "MountainCamp") and (statKey == "Stamina" or statKey == "Endurance") then
		m += 0.1
	end
	-- Home Gym: extra reps at home add up (next to SmartSystem / EliteCamp)
	m += homeGymBonus(profile)
	local _, lv = Training.StationLevel(profile, act.station)
	m *= lv and lv.mult or 1
	if (profile.gym.cond[act.station] or 100) < 30 then
		m *= 0.8
	end
	local spec = Config.FindById(Config.Specialties, profile.specialty)
	if spec and spec.stats[statKey] then
		m *= 1.25
	end
	local age = profile.identity.age
	if age < 24 then
		m *= 1.2
	elseif age >= 34 then
		m *= 0.5
	elseif age >= 30 then
		m *= 0.75
	end
	m *= 0.8 + profile.mental.Discipline / 250
	m *= 1 + (profile.condition.buffs.gains or 0)
	return m
end

-- Muscle growth multiplier for a session (stat gains use GainMultiplier): better equipment loads
-- the muscle better (station level), a strength coach programs the lifting (half of the Power
-- coach boost), young bodies build faster, the facility tier (recovery, sports science) and the
-- Home Gym add a little. Worn-out equipment costs some.
function Training.MuscleMultiplier(profile, act)
	local m = 1
	local _, lv = Training.StationLevel(profile, act.station)
	m *= lv and lv.mult or 1
	if act.station and (profile.gym.cond[act.station] or 100) < 30 then
		m *= 0.85
	end
	m *= 1 + 0.5 * Training.CoachBoost(profile, "Power")
	local age = tonumber(profile.identity.age) or 22
	if age < 24 then
		m *= 1.15
	elseif age >= 34 then
		m *= 0.6
	elseif age >= 30 then
		m *= 0.8
	end
	local _, tierDef = Training.GymTier(profile)
	m *= tonumber(tierDef.growth) or 1
	m *= 1 + homeGymBonus(profile)
	return m
end

-- { [partId] = weight } an activity trains: act.parts (Config.ExerciseTargets), else each
-- act.muscle group weight spread evenly over that group's parts (same group pace).
function Training.Targets(act)
	if type(act.parts) == "table" and next(act.parts) ~= nil then
		return act.parts
	end
	local t = {}
	for grp, w in pairs(act.muscle or {}) do
		local parts = Config.MuscleGroupParts[grp]
		if parts then
			for _, p in ipairs(parts) do
				t[p.id] = (t[p.id] or 0) + w
			end
		elseif PART_SHARE[grp] then
			t[grp] = (t[grp] or 0) + w
		end
	end
	return t
end

local function injuryRoll(profile, act, extraRisk)
	local c = profile.condition
	if not act.injuries or #act.injuries == 0 then
		return nil
	end
	local risk = 0
	if c.fatigue > 50 then
		risk += (c.fatigue - 50) / 220
	end
	if c.hydration < 25 then
		risk += 0.04
	end
	if c.energy < 20 then
		risk += 0.04
	end
	risk += extraRisk or 0
	if risk <= 0 then
		return nil
	end
	risk *= 1.2 - profile.stats.Recovery / 200
	if c.flexible then
		risk *= 0.6
	end
	local wraps = Training.GearItem(profile, "wraps")
	local punching = (act.wear and act.wear.gloves) ~= nil
	if punching and wraps then
		risk *= wraps.injury
		if Training.GearCondition(profile, "gloves") < 30 then
			risk *= 1.3
		end
	end
	if act.wear and act.wear.shoes and Training.GearCondition(profile, "shoes") < 30 then
		risk *= 1.3
	end
	if rng:NextNumber() >= risk then
		return nil
	end
	local id = act.injuries[rng:NextInteger(1, #act.injuries)]
	local def = Config.Injuries[id]
	local days = rng:NextInteger(def.days[1], def.days[2])
	for _, inj in ipairs(c.injuries) do
		if inj.id == id and inj.days > 0 then
			inj.days += math.ceil(days / 2)
			return def.name
		end
	end
	table.insert(c.injuries, { id = id, days = days })
	c.fatigue = clamp(c.fatigue + 10, 0, 100)
	return def.name
end

function Training.WearGear(profile, kind, amount)
	local item, id = Training.GearItem(profile, kind)
	if not item or kind == "mouthguard" or kind == "robe" then
		return
	end
	local key = kind .. ":" .. id
	local cur = profile.gear.cond[key] or 100
	profile.gear.cond[key] = clamp(cur - amount / (item.durability or 1), 0, 100)
end

------------------------------------------------------------------------
-- Activities
------------------------------------------------------------------------
function Training.EnergyCost(profile, act, intensity)
	local e = act.energy or 0
	if act.id == "Sparring" then
		e = ({ Light = 25, Medium = 35, Hard = 45 })[intensity or "Medium"] or 35
	end
	if Training.Owned(profile, "Nutritionist") then
		e *= 0.9
	end
	return math.floor(e)
end

-- a day's water cut is bounded (Sleep resets condition.water); below this hydration the sauna is refused
local MAX_WATER_CUT = -8
local SAUNA_MIN_HYDRATION = 10

function Training.CanDo(profile, act, intensity)
	if not act then
		return false, "Unknown activity"
	end
	if profile.retired then
		return false, "You're retired."
	end
	local block = Training.BlockedBy(profile, act.id)
	if block then
		return false, "You can't do that with a " .. block .. ". Rest, ice baths and massage help it heal."
	end
	if act.requires and not Training.Owned(profile, act.requires) then
		return false, "You need the " .. act.name .. " (Shop > Elite Equipment)."
	end
	if act.station and Catalog.Stations[act.station] and (profile.gym.levels[act.station] or 1) < 1 then
		return false, "This station isn't unlocked yet."
	end
	if act.recovery then
		if act.price and not (act.station == "massage" and Training.StationLevel(profile, "massage") >= 2) and profile.money < act.price then
			return false, "A massage costs " .. Config.Money(act.price) .. "."
		end
		if (act.recovery.energy or 0) < 0 and profile.condition.energy < -act.recovery.energy then
			return false, "Too exhausted. Sleep first."
		end
		if (act.recovery.water or 0) < 0 then
			if finite(profile.condition.hydration, 80) <= SAUNA_MIN_HYDRATION then
				return false, "Too dehydrated for the sauna. Drink water first."
			end
			if finite(profile.condition.water, 0) <= MAX_WATER_CUT + 0.05 then
				return false, "You can't sweat out any more today. Sleep, then cut again tomorrow."
			end
		end
		return true
	end
	local cost = Training.EnergyCost(profile, act, intensity)
	if profile.condition.energy < cost then
		return false, string.format("Not enough energy (%d needed, %d left). Eat, recover or sleep.", cost, math.floor(profile.condition.energy))
	end
	return true
end

------------------------------------------------------------------------
-- Muscle growth: per sub-muscle targeting, soreness, supercompensation, pump
------------------------------------------------------------------------
local VASC_PER_SESSION = 1.5 -- body.vasc gained per point of act.vasc at quality 1 (diminishing toward 100)
local PUMP_MAX_PARTS = 6

-- Grows the parts an activity targets (Training.Targets) and re-derives the 7 groups.
-- quality 0.4..1.5, scale = session share/intensity, condMult = Training.ConditionMultiplier.
-- Per part: g = base * weight * quality * condMult * muscleBuff * MuscleMultiplier * room * scale
-- * (1 - sorePenalty * sore[group]); room = 1 - (part + pending) / cap. `immediate` of g lands now,
-- the rest goes to condition.pending (applied by Sleep). Returns
-- { parts = {id = g}, groups = {grp = share-weighted g}, total, sore = {grp = value}, pump = {parts, level} | nil,
--   vasc = gain | nil, soreBefore = max soreness of the trained groups before the session, soreGroup }
function Training.GrowMuscles(profile, act, quality, scale, condMult)
	local c = profile.condition
	local body = profile.body
	quality = clamp(finite(quality, 1), 0, 1.5)
	scale = clamp(finite(scale, 1), 0, 2)
	condMult = finite(condMult, nil) or Training.ConditionMultiplier(profile)
	local cap = Training.MuscleCap(profile)
	local muscleBuff = 1 + (type(c.buffs) == "table" and finite(c.buffs.muscle, 0) or 0)
	local mult = Training.MuscleMultiplier(profile, act)
	local sore = conditionTable(profile, "sore")
	local pending = conditionTable(profile, "pending")
	local log = muscleLog(profile)
	local day = finite(profile.day, 1)
	local targets = Training.Targets(act)

	-- share-weighted group load of this session (bench: chest 1.3) drives soreness
	local groupLoad, soreBefore, soreGroup = {}, 0, nil
	for id, w in pairs(targets) do
		local grp = Config.MusclePartGroup[id]
		if grp and finite(w, 0) > 0 then
			groupLoad[grp] = (groupLoad[grp] or 0) + PART_SHARE[id] * w
		end
	end
	for grp in pairs(groupLoad) do
		local s = finite(sore[grp], 0)
		if s > soreBefore then
			soreBefore, soreGroup = s, grp
		end
	end

	local out = { parts = {}, groups = {}, total = 0, soreBefore = soreBefore, soreGroup = soreGroup }
	for id, w in pairs(targets) do
		local grp = Config.MusclePartGroup[id]
		w = finite(w, 0)
		if grp and w > 0 then
			local cur = finite(body[id], Config.PartValue(body, id))
			local pend = math.max(0, finite(pending[id], 0))
			local room = clamp(1 - (cur + pend) / cap, 0, 1)
			local soreMul = 1 - MG.sorePenalty * clamp(finite(sore[grp], 0), 0, 1)
			local g = MG.base * w * quality * condMult * muscleBuff * mult * room * scale * soreMul
			if g > 0 then
				local now = g * MG.immediate
				body[id] = math.min(cap, cur + now)
				pending[id] = pend + (g - now)
				out.parts[id] = g
				out.groups[grp] = (out.groups[grp] or 0) + PART_SHARE[id] * g
				out.total += PART_SHARE[id] * g
			end
			-- incidental work (a little calf on shadow boxing) does not hold off detraining
			if w >= 0.25 then
				log[id] = day
			end
		end
	end
	-- punching (any gloved work: bag, mitts, pads, sparring) keeps the neck braced against the
	-- recoil: it holds off neck detraining without growing it (growth stays with Config targets).
	-- Without this a pure bag-and-weights boxer ended up with a neck thinner than on day one.
	if type(act.wear) == "table" and finite(act.wear.gloves, 0) > 0 then
		log.neckSCM = day
	end

	-- soreness: the harder the session hits a group, the sorer it gets (0..1)
	out.sore = {}
	for grp, load in pairs(groupLoad) do
		sore[grp] = clamp(finite(sore[grp], 0) + load * quality * MG.sorePerWeight * math.min(scale, 1.35), 0, 1)
		out.sore[grp] = r2(sore[grp])
	end

	-- vascularity: vein-building lifts (act.vasc) and grip-heavy work (forearms) raise body.vasc
	local vascW = act.vasc == true and MG.vascGain or finite(act.vasc, 0)
	if vascW <= 0 and finite(targets.forearms, 0) > 0 then
		vascW = targets.forearms * 0.25
	end
	if vascW > 0 then
		local v = clamp(finite(body.vasc, 0), 0, 100)
		local gain = vascW * VASC_PER_SESSION * quality * math.min(scale, 1.2) * (1 - v / 100)
		body.vasc = clamp(v + gain, 0, 100)
		out.vasc = gain
	end

	-- pump: the most heavily worked parts (>= 45% of the top weight), level from the top weight
	local maxW = 0
	for id, w in pairs(targets) do
		if Config.MusclePartGroup[id] then
			maxW = math.max(maxW, finite(w, 0))
		end
	end
	if maxW > 0 then
		local list = {}
		for id, w in pairs(targets) do
			if Config.MusclePartGroup[id] and finite(w, 0) >= maxW * 0.45 then
				table.insert(list, id)
			end
		end
		table.sort(list, function(a, b)
			if targets[a] ~= targets[b] then
				return targets[a] > targets[b]
			end
			return a < b
		end)
		while #list > PUMP_MAX_PARTS do
			table.remove(list)
		end
		out.pump = { parts = list, level = r2(clamp(maxW / 2 * quality * math.min(scale, 1.2), 0.15, 1)) }
	end

	Config.SyncGroups(body)
	return out
end

-- Turns condition.pending (supercompensation) into muscle. factor = sleep & food quality.
-- Returns { [partId] = gain }, share-weighted total.
local function applyPending(profile, factor)
	local c = profile.condition
	local pending = type(c.pending) == "table" and c.pending or nil
	c.pending = {}
	local grew, total = {}, 0
	if not pending then
		return grew, total
	end
	local body, cap = profile.body, Training.MuscleCap(profile)
	factor = clamp(finite(factor, 1), 0, 1.5)
	for id, g in pairs(pending) do
		g = finite(g, 0) * factor
		if PART_SHARE[id] and g > 0 then
			local cur = finite(body[id], Config.PartValue(body, id))
			local new = math.min(cap, cur + g)
			if new > cur then
				body[id] = new
				grew[id] = new - cur
				total += PART_SHARE[id] * (new - cur)
			end
		end
	end
	Config.SyncGroups(body)
	return grew, total
end

-- names of the parts that grew most, for notes ("Chest (Lower/Mid Pecs), Triceps")
local function topPartNames(map, n)
	local ids = {}
	for id in pairs(map) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		if map[a] ~= map[b] then
			return map[a] > map[b]
		end
		return a < b
	end)
	local names = {}
	for i = 1, math.min(n, #ids) do
		table.insert(names, Config.MusclePartNames[ids[i]] or ids[i])
	end
	return table.concat(names, ", ")
end

-- Sets the post-workout pump on a character (attributes only; E's BodyFX swells the meshes
-- client-side and fades it over Config.Pump.duration). Back-to-back sessions stack with
-- diminishing returns instead of resetting. Safe to call with anything.
function Training.ApplyPump(character, result)
	local pump = type(result) == "table" and result.pump or nil
	if type(pump) ~= "table" or type(pump.parts) ~= "table" or #pump.parts == 0 then
		return false
	end
	local ok, err = pcall(function()
		if typeof(character) ~= "Instance" or not character:IsA("Model") then
			return false
		end
		local now = workspace:GetServerTimeNow()
		local level = clamp(finite(pump.level, 0), 0, 1)
		local prev = clamp(finite(character:GetAttribute("Pump"), 0), 0, 1)
		local prevAt = finite(character:GetAttribute("PumpAt"), 0)
		local left = prev * clamp(1 - (now - prevAt) / Config.Pump.duration, 0, 1)
		local combined = clamp(math.max(level, left) + 0.25 * math.min(level, left), 0, 1)
		local parts, seen = {}, {}
		local function add(id)
			if type(id) == "string" and PART_SHARE[id] and not seen[id] and #parts < 8 then
				seen[id] = true
				table.insert(parts, id)
			end
		end
		for _, id in ipairs(pump.parts) do
			add(id)
		end
		local old = character:GetAttribute("PumpParts")
		if left > 0.05 and type(old) == "string" then
			for id in string.gmatch(old, "[^,]+") do
				add(id)
			end
		end
		character:SetAttribute("Pump", math.floor(combined * 20 + 0.5) / 20)
		character:SetAttribute("PumpParts", table.concat(parts, ","))
		character:SetAttribute("PumpAt", now)
		return true
	end)
	if not ok then
		warn("[Boxer] ApplyPump failed:", err)
	end
	return ok and err == true
end

------------------------------------------------------------------------
-- Training XP and the muscle history (the Muscle Progression screen)
------------------------------------------------------------------------
-- XP is a feel-good counter for the session toasts: it never feeds the fight math. Level n needs
-- XP_LEVEL * n^2 in total, so the early levels come fast and a veteran still sees one now and then.
local XP_LEVEL = 150
function Training.XPInfo(xp)
	xp = math.max(0, math.floor(finite(xp, 0)))
	local level = math.floor(math.sqrt(xp / XP_LEVEL)) + 1
	local from = XP_LEVEL * (level - 1) ^ 2
	local to = XP_LEVEL * level ^ 2
	return { level = level, xp = xp, into = xp - from, need = to - from }
end

-- one snapshot of the seven groups per career day (profile.muscleHist, capped, created lazily; an
-- old save starts logging the day it loads). Career.Summary does not carry it: Main serves it on
-- request (GetMuscleHistory) when the screen opens.
local HISTORY_MAX = 90
local function logMuscleHistory(profile)
	local body = profile.body
	if type(body) ~= "table" then
		return
	end
	local hist = profile.muscleHist
	if type(hist) ~= "table" then
		hist = {}
		profile.muscleHist = hist
	end
	local day = math.floor(finite(profile.day, 1))
	local entry = { d = day }
	for _, g in ipairs(Config.MuscleKeys) do
		entry[g] = math.floor(finite(body[g], 0) * 10 + 0.5) / 10
	end
	local last = hist[#hist]
	if type(last) == "table" and last.d == day then
		hist[#hist] = entry
	else
		table.insert(hist, entry)
	end
	while #hist > HISTORY_MAX do
		table.remove(hist, 1)
	end
end
Training.LogMuscleHistory = logMuscleHistory

-- the history as a clean list for the client: { { d = day, chest = v, ... }, ... } oldest first
function Training.MuscleHistory(profile)
	local out = {}
	local hist = type(profile) == "table" and profile.muscleHist or nil
	if type(hist) ~= "table" then
		return out
	end
	for _, e in ipairs(hist) do
		if type(e) == "table" and type(e.d) == "number" and e.d == e.d then
			local row = { d = math.floor(e.d) }
			for _, g in ipairs(Config.MuscleKeys) do
				row[g] = r2(finite(e[g], 0))
			end
			table.insert(out, row)
		end
	end
	return out
end

-- Apply a completed training session. quality 0.5..1.5 from the minigame.
function Training.Perform(profile, act, quality, opts)
	opts = opts or {}
	quality = clamp(tonumber(quality) or 1, 0.4, 1.5)
	local c = profile.condition
	local result = { gains = {}, muscle = {}, notes = {} }
	local condMult = Training.ConditionMultiplier(profile)
	local scale = opts.scale or 1
	-- stat gains
	for stat, weight in pairs(act.gains or {}) do
		local cur = finite(profile.stats[stat], 10)
		local dim = clamp(1 - (cur - 25) / 78, 0.05, 1.1)
		local g = Config.GainScale * weight * Training.GainMultiplier(profile, stat, act) * quality * condMult * dim * scale
		-- NaN-safe: math.min(cap, NaN) is the cap, so a NaN gain would max the stat out
		local new = clamp(finite(cur + g, cur), 1, Config.StatCap)
		result.gains[stat] = new - cur
		profile.stats[stat] = new
	end
	-- muscle growth per sub-muscle, diminishing toward the frame's potential. Only part of it shows
	-- at once: the rest is supercompensation (condition.pending) that Sleep turns into muscle,
	-- scaled by sleep quality and food. Sore groups grow less and get hurt more easily.
	local grown = Training.GrowMuscles(profile, act, quality, scale, condMult)
	result.muscle, result.parts, result.sore, result.pump = grown.groups, grown.parts, grown.sore, grown.pump
	if grown.vasc then
		result.vasc = grown.vasc
	end
	if act.fat then
		local f = act.fat * 0.4 * quality * scale
		profile.body.fat = clamp((profile.body.fat or 14) + f, 7, 30)
		result.fat = f
	end
	-- condition costs
	local energy = Training.EnergyCost(profile, act, opts.intensity) * (opts.energyScale or 1)
	c.energy = clamp(c.energy - energy, 0, 100)
	c.hydration = clamp(c.hydration - (act.hydration or 0) * scale, 0, 100)
	c.nutrition = clamp(c.nutrition - (act.nutrition or 0) * scale, 0, 100)
	local fat = (act.fatigue or 10) * scale * (Training.Owned(profile, "Nutritionist") and 0.85 or 1)
	c.fatigue = clamp(c.fatigue + fat, 0, 100)
	-- equipment & gear wear
	if act.station and profile.gym.cond[act.station] then
		profile.gym.cond[act.station] = clamp(profile.gym.cond[act.station] - rng:NextNumber(0.8, 1.8), 0, 100)
	end
	for kind, amount in pairs(act.wear or {}) do
		Training.WearGear(profile, kind, amount * scale)
	end
	-- injuries from overtraining (loading a still-sore muscle adds risk)
	local inj = injuryRoll(profile, act, (opts.extraRisk or 0) + MG.soreInjuryRisk * grown.soreBefore)
	if inj then
		result.injury = inj
		table.insert(result.notes, "INJURY: " .. inj .. ". Rest, ice baths and massage speed up healing.")
	end
	if grown.soreBefore >= 0.6 and grown.soreGroup then
		table.insert(result.notes, string.format("Your %s was still sore: less growth and a higher injury risk. Recover (ice bath, massage, sleep) or train something else.",
			string.lower(Config.MuscleNames[grown.soreGroup] or grown.soreGroup)))
	end
	if c.fatigue > 70 then
		table.insert(result.notes, "You're overtraining. Gains are dropping and injury risk is high.")
	end
	if c.hydration < 25 then
		table.insert(result.notes, "You're dehydrated. Grab water from the cooler.")
	end
	if c.nutrition < 25 then
		table.insert(result.notes, "You're running on empty. Eat something at the Nutrition Bar.")
	elseif c.nutrition < 40 and grown.total > 0.05 then
		table.insert(result.notes, "Muscle is built overnight from food: eat before you sleep or tonight's growth is reduced.")
	end
	-- how sweaty the session leaves you (I sets the Sweat attribute through Builder.SetSweat)
	result.sweat = math.floor(clamp((act.fatigue or 10) / 24 * quality * math.min(scale, 1.2), 0, 1) * 20 + 0.5) / 20
	profile.mental.Discipline = clamp(profile.mental.Discipline + 0.3, 0, 100)
	if act.id == "Sparring" then
		profile.mental.Composure = clamp(profile.mental.Composure + 0.6, 0, 100)
		profile.mental.Focus = clamp(profile.mental.Focus + 0.3, 0, 100)
	end
	profile.sessions = (profile.sessions or 0) + 1
	profile.overall = Config.Overall(profile.stats)
	if profile.camp then
		table.insert(profile.camp.log, act.name)
	end
	-- training XP (the result screen's toast): the session's stat and muscle gains plus a base for
	-- showing up, scaled by the grade
	local statTotal = 0
	for _, g in pairs(result.gains) do
		statTotal += math.max(0, finite(g, 0))
	end
	local xp = math.floor((18 + statTotal * 45 + finite(grown.total, 0) * 24) * quality * math.min(scale, 1.5) + 0.5)
	local before = Training.XPInfo(profile.xp)
	profile.xp = before.xp + xp
	local after = Training.XPInfo(profile.xp)
	result.xp, result.xpTotal, result.level = xp, after.xp, after
	result.levelUp = after.level > before.level
	logMuscleHistory(profile)
	return result
end

-- A paid recovery the player could not pay for at the finish (Recover returned unpaid = true):
-- the very next Training.Record for that activity stores nothing, as if noStore had been passed,
-- so an unpaid session never counts towards sessions / best grade. Weak keys, never saved.
local unpaidSession = setmetatable({}, { __mode = "k" })

function Training.Recover(profile, act, quality)
	quality = clamp(tonumber(quality) or 1, 0.5, 1.5)
	local c = profile.condition
	local r = act.recovery
	local _, lv = Training.StationLevel(profile, act.station)
	local mult = (lv and lv.mult or 1) * (0.8 + 0.2 * quality)
	local result = { notes = {} }
	if act.price and not (act.station == "massage" and Training.StationLevel(profile, "massage") >= 2) then
		-- CanDo checked the price at the start, but food can be bought mid-session: never go below 0
		if finite(profile.money, 0) < act.price then
			table.insert(result.notes, "You couldn't pay the " .. Config.Money(act.price) .. " at the end, so the session didn't count.")
			result.unpaid = true
			result.fatigue = c.fatigue
			unpaidSession[profile] = act.id
			return result
		end
		profile.money -= act.price
		table.insert(result.notes, "Paid " .. Config.Money(act.price) .. " for the session.")
	end
	c.fatigue = clamp(c.fatigue + (r.fatigue or 0) * ((r.fatigue or 0) < 0 and mult or 1), 0, 100)
	c.energy = clamp(c.energy + (r.energy or 0) * ((r.energy or 0) > 0 and mult or 1), 0, 100)
	if r.hydration then
		c.hydration = clamp(c.hydration + r.hydration, 0, 100)
	end
	if r.water then
		-- bounded per day: stacked sauna sessions cannot cut more than MAX_WATER_CUT before Sleep
		local cur = finite(c.water, 0)
		local w = r.water * mult
		if w < 0 then
			w = math.max(w, math.min(0, MAX_WATER_CUT - cur))
		end
		c.water = cur + w
		if r.water < 0 and w > -0.05 then
			table.insert(result.notes, "You can't sweat out any more today.")
		else
			table.insert(result.notes, string.format("Sweated out %.1f lbs of water weight. Rehydrate after the weigh-in.", -w))
		end
	end
	if r.heal then
		local healed = Training.Heal(profile, r.heal * mult)
		for _, n in ipairs(healed) do
			table.insert(result.notes, n)
		end
	end
	if r.flexible then
		c.flexible = true
		table.insert(result.notes, "Loose and limber: lower injury risk for the rest of the day.")
	end
	-- recovery work flushes soreness in proportion to the fatigue it removes (ice bath ~40%, chamber 80%)
	local relief = (r.fatigue or 0) < 0 and clamp(-r.fatigue / 60 * mult, 0, 0.8) or 0
	if relief > 0 and type(c.sore) == "table" then
		local eased = false
		for grp, v in pairs(c.sore) do
			v = finite(v, 0) * (1 - relief)
			c.sore[grp] = v >= 0.02 and v or nil
			eased = eased or v > 0.1
		end
		if eased then
			table.insert(result.notes, "Muscle soreness eased.")
		end
		result.sore = table.clone(c.sore)
	end
	result.fatigue = c.fatigue
	return result
end

function Training.Heal(profile, days)
	local notes = {}
	local mult = Training.Owned(profile, "Physio") and 1.5 or 1
	for _, inj in ipairs(profile.condition.injuries) do
		if inj.days > 0 then
			inj.days -= days * mult
			if inj.days <= 0 then
				inj.days = 0
				table.insert(notes, (Config.Injuries[inj.id] and Config.Injuries[inj.id].name or "Injury") .. " has healed.")
			end
		end
	end
	local keep = {}
	for _, inj in ipairs(profile.condition.injuries) do
		if inj.days > 0 then
			table.insert(keep, inj)
		end
	end
	profile.condition.injuries = keep
	return notes
end

------------------------------------------------------------------------
-- Session records: grade, personal best and session count per activity
------------------------------------------------------------------------
local MAX_STAT_KEYS = 8

-- drill numbers reported by the client (punches, max power, reps, distance...). They are only
-- shown back to the player as "best numbers" and never feed the gains: numbers only, finite,
-- clamped, short identifier keys, at most 8 of them.
function Training.SanitizeStats(stats)
	if type(stats) ~= "table" then
		return nil
	end
	local out, n, seen = {}, 0, 0
	for k, v in pairs(stats) do
		seen += 1
		if seen > 32 or n >= MAX_STAT_KEYS then
			break
		end
		if type(k) == "string" and #k <= 20 and string.match(k, "^%a[%w_]*$") and type(v) == "number"
			and v == v and v > -math.huge and v < math.huge then
			out[k] = r2(math.clamp(v, 0, 1000000))
			n += 1
		end
	end
	return n > 0 and out or nil
end

-- Records a finished session (quality = the server's final quality, 0.4..1.5) and returns what the
-- result screen shows. noStore = the session doesn't count (e.g. finished impossibly fast).
-- profile.records[actId] = { best, sessions, last, stats = { key = best number } }
function Training.Record(profile, actId, quality, stats, noStore)
	if unpaidSession[profile] ~= nil then
		noStore = noStore or unpaidSession[profile] == actId
		unpaidSession[profile] = nil
	end
	local q = tonumber(quality) or 0
	if q ~= q then
		q = 0
	end
	q = math.clamp(q, 0, 1.5)
	if type(profile.records) ~= "table" then
		profile.records = {}
	end
	local r = profile.records[actId]
	if type(r) ~= "table" then
		r = nil
	end
	local prevBest = r and tonumber(r.best) or 0
	local prevSessions = r and tonumber(r.sessions) or 0
	if noStore then
		return {
			grade = Config.GradeFor(q), best = prevBest, prevBest = prevBest, sessions = prevSessions,
			newBest = false, first = false, uncounted = true, newStats = {},
			bests = r and type(r.stats) == "table" and table.clone(r.stats) or nil,
		}
	end
	if not r then
		r = { best = 0, sessions = 0, last = 0 }
		profile.records[actId] = r
	end
	local hadRecord = prevSessions > 0
	r.sessions = prevSessions + 1
	r.last = r2(q)
	local improved = q > prevBest + 0.0001
	if improved then
		r.best = r2(q)
	end
	local newStats = {}
	if type(stats) == "table" then
		local bests = type(r.stats) == "table" and r.stats or {}
		local count = 0
		for _ in pairs(bests) do
			count += 1
		end
		for k, v in pairs(stats) do
			local old = tonumber(bests[k])
			if old == nil and count >= MAX_STAT_KEYS then
				continue
			end
			if old == nil then
				count += 1
				bests[k] = v
			elseif v > old then
				bests[k] = v
				if hadRecord then
					table.insert(newStats, k)
				end
			end
		end
		table.sort(newStats)
		r.stats = bests
	end
	return {
		grade = Config.GradeFor(q), best = r.best, prevBest = prevBest, sessions = r.sessions,
		newBest = improved and hadRecord, first = not hadRecord, newStats = newStats,
		bests = type(r.stats) == "table" and table.clone(r.stats) or nil,
	}
end

------------------------------------------------------------------------
-- Food & sleep
------------------------------------------------------------------------
function Training.Eat(profile, mealId)
	local meal = type(mealId) == "string" and Config.FindById(Config.Meals, mealId) or nil
	if not meal then
		return false, "Unknown item"
	end
	if meal.requires and not Training.Owned(profile, meal.requires) then
		return false, "Hire a Nutritionist (Shop) to unlock this."
	end
	if profile.money < meal.price then
		return false, "Not enough money."
	end
	local c = profile.condition
	local boost = Training.Owned(profile, "Nutritionist") and 1.25 or 1
	profile.money -= meal.price
	local before = c.nutrition
	c.nutrition = c.nutrition + meal.nutrition * boost
	if c.nutrition > 100 then
		-- overeating turns into body fat
		profile.body.fat = clamp(profile.body.fat + (c.nutrition - 100) * 0.012, 7, 30)
		c.nutrition = 100
	end
	c.hydration = clamp(c.hydration + meal.hydration * (meal.hydration > 0 and boost or 1), 0, 100)
	c.energy = clamp(c.energy + meal.energy, 0, 100)
	profile.body.fat = clamp(profile.body.fat + meal.fat, 7, 30)
	if meal.gainsBuff then
		c.buffs.gains = math.max(c.buffs.gains or 0, meal.gainsBuff)
	end
	if meal.muscleBuff then
		c.buffs.muscle = math.max(c.buffs.muscle or 0, meal.muscleBuff)
	end
	return true, { nutrition = c.nutrition - before, hydration = c.hydration, energy = c.energy }
end

function Training.SleepQuality(profile)
	local c = profile.condition
	local q = 0.62
	for _, id in ipairs({ "Apartment", "House", "Mansion" }) do
		if Training.Owned(profile, id) then
			local item = Catalog.Find(Catalog.Shop, id)
			q = math.max(q, 0.62 + (item and item.sleep or 0))
		end
	end
	if c.hydration > 50 then
		q += 0.05
	elseif c.hydration < 20 then
		q -= 0.08
	end
	if c.nutrition > 50 then
		q += 0.05
	elseif c.nutrition < 20 then
		q -= 0.08
	end
	if c.fatigue > 70 then
		q -= 0.1
	end
	if #Training.ActiveInjuries(profile) > 0 then
		q -= 0.05
	end
	-- home recovery suite (Catalog.Shop RecoverySuite.sleepBonus)
	if Training.Owned(profile, "RecoverySuite") then
		local item = Catalog.Find(Catalog.Shop, "RecoverySuite")
		q += item and tonumber(item.sleepBonus) or 0
	end
	return clamp(q, 0.4, 1)
end

------------------------------------------------------------------------
-- Persistent face damage & head trauma (fight -> profile -> Builder / next fight)
------------------------------------------------------------------------
local FACE_FIELDS = FD.fields

local function faceMax(k)
	return (k == "cut" or k == "cut2") and 1.2 or 1
end

-- a clean dmg table (Config.FaceDamage shape) from anything: unknown keys / NaN / strings dropped,
-- values x scale and clamped, below clearBelow removed. nil when nothing shows.
local function cleanFace(f, scale)
	if type(f) ~= "table" then
		return nil
	end
	scale = scale or 1
	local out, any = {}, false
	for _, k in ipairs(FACE_FIELDS) do
		local v = finite(f[k], 0) * scale
		if v >= FD.clearBelow then
			out[k] = clamp(v, 0, faceMax(k))
			any = true
		end
	end
	if f.nose == true then
		out.nose = true
		any = true
	end
	if not any then
		return nil
	end
	if out.cut then
		out.cutSide = finite(f.cutSide, 1) < 0 and -1 or 1
	end
	if out.cut2 then
		out.cutSide2 = finite(f.cutSide2, -1) < 0 and -1 or 1
	end
	out.age = clamp(math.floor(finite(f.age, 0)), 0, 999)
	return out
end

-- the persistent residual (condition.face) for Builder opts.damage / the next fight's seed; nil = clean.
-- Values rounded to 0.01 so the look signature does not churn.
function Training.FaceView(profile)
	local c = type(profile) == "table" and profile.condition
	local f = type(c) == "table" and cleanFace(c.face) or nil
	if not f then
		return nil
	end
	for _, k in ipairs(FACE_FIELDS) do
		if f[k] then
			f[k] = r2(f[k])
		end
	end
	return f
end

-- Was the nose still broken (not yet set) when the fight that is being applied started?
-- FightEngine seeds each fight's damage from the healing face (CONTRACTS 8.6), so its res.face /
-- res.noseBroken carry an old, unset break over. Career.ApplyResult runs PassDays (which may set
-- that old nose) before AddFaceDamage / AddTrauma, so PassDays snapshots the pre-fight state here
-- for those two to read. Weak keys: per running profile, never saved.
local preFightNose = setmetatable({}, { __mode = "k" })

-- Merges a fight's (or spar's) face damage into the profile, field by field by max, times scale
-- (Config.FaceDamage.postFightCarry / sparCarry). The residual's age restarts at 0 (fresh bruises)
-- only when something actually got worse: a light spar must not restart the nose-setting clock.
-- A broken nose that was already broken when the fight started is the old break carried over by
-- the engine's seed, not a new one. Fields that got worse are flagged for the permanent-mark check
-- on the next night (HealFace).
function Training.AddFaceDamage(profile, face, scale)
	local add = cleanFace(face, clamp(finite(scale, 1), 0, 2))
	if not add then
		return Training.FaceView(profile)
	end
	local c = profile.condition
	local cur = cleanFace(c.face) or {}
	local marks = type(c.faceMarks) == "table" and c.faceMarks or {}
	local worse = false
	for _, k in ipairs(FACE_FIELDS) do
		local v = add[k]
		if v and v > (cur[k] or 0) then
			cur[k] = v
			worse = true
			if k == "cut" then
				cur.cutSide = add.cutSide
				marks.cut = true
			elseif k == "cut2" then
				cur.cutSide2 = add.cutSide2
				marks.cut2 = true
			elseif k == "earL" or k == "earR" then
				marks[k] = true
			end
		end
	end
	if add.nose and not cur.nose and not preFightNose[profile] then
		cur.nose = true
		worse = true
	end
	if worse or cur.age == nil then
		cur.age = 0
	end
	c.face = cleanFace(cur)
	c.faceMarks = next(marks) ~= nil and marks or nil
	return Training.FaceView(profile)
end

-- appearance.battle (server-only permanent wear), created if an odd save lacks it
local function battleOf(profile)
	local app = profile.appearance
	if type(app) ~= "table" then
		return { scars = {}, ears = 0, nose = 0 } -- nowhere to keep it; marks are simply lost
	end
	if type(app.battle) ~= "table" then
		app.battle = { scars = {}, ears = 0, nose = 0 }
	end
	local b = app.battle
	if type(b.scars) ~= "table" then
		b.scars = {}
	end
	b.ears = clamp(finite(b.ears, 0), 0, 1)
	b.nose = clamp(finite(b.nose, 0), 0, 1)
	return b
end

-- a deep cut closes into a permanent scar; when all slots are taken a deeper cut replaces the faintest
local function addScar(battle, kind, side, depth)
	local size = r2(clamp(0.35 + (depth - FD.scarAt) / math.max(0.05, 1.2 - FD.scarAt) * 0.6, 0.3, 1))
	local scar = { kind = kind, side = (side or 1) < 0 and -1 or 1, at = r2(rng:NextNumber(0.25, 0.75)), size = size }
	local list = battle.scars
	if #list < FD.maxScars then
		table.insert(list, scar)
		return true
	end
	local minI, minS
	for i, sc in ipairs(list) do
		local sz = type(sc) == "table" and finite(sc.size, 0.5) or 0
		if not minS or sz < minS then
			minI, minS = i, sz
		end
	end
	if minI and size > minS then
		list[minI] = scar
		return true
	end
	return false
end

-- Heals the persistent face damage by `days` nights (dayTick calls it with 1): swelling shrinks by
-- a factor, cuts and bruises close linearly (Config.FaceDamage.heal; x physioHeal with the Physio),
-- bruises age (colour), and on the first night after a fight the worst injuries leave their
-- permanent marks in appearance.battle (scars, cauliflower ear, bent nose). Returns notes.
function Training.HealFace(profile, days)
	local notes = {}
	local c = profile.condition
	local f = cleanFace(c.face)
	if not f then
		c.face, c.faceMarks = nil, nil
		return notes
	end
	days = clamp(math.floor(finite(days, 1)), 0, 120)
	local physio = Training.Owned(profile, "Physio") and FD.physioHeal or 1
	local marks = type(c.faceMarks) == "table" and c.faceMarks or {}
	local battle = battleOf(profile)
	for _ = 1, days do
		-- permanent marks are decided once per new injury, from its full depth
		if marks.cut then
			if (f.cut or 0) >= FD.scarAt and addScar(battle, "brow", f.cutSide, f.cut) then
				table.insert(notes, "The cut over your eye closed into a scar. It's part of your story now.")
			end
			marks.cut = nil
		end
		if marks.cut2 then
			if (f.cut2 or 0) >= FD.scarAt and addScar(battle, "cheek", f.cutSide2, f.cut2) then
				table.insert(notes, "The cut on your cheek left a scar.")
			end
			marks.cut2 = nil
		end
		for _, ear in ipairs({ "earL", "earR" }) do
			if marks[ear] then
				local v = f[ear] or 0
				-- a badly swollen ear hardens into cauliflower ear more often the worse it was
				if v >= FD.cauliflowerAt and rng:NextNumber() < clamp(0.4 + (v - FD.cauliflowerAt) * 1.5, 0, 1) and battle.ears < 1 then
					battle.ears = math.min(1, battle.ears + FD.cauliflowerStep)
					table.insert(notes, "Your swollen ear hardened: a touch of cauliflower ear.")
				end
				marks[ear] = nil
			end
		end
		-- heal
		for _, k in ipairs(FACE_FIELDS) do
			local v = f[k]
			if v then
				local rule = FD.heal[k] or { mul = 0.6 }
				if rule.sub then
					v -= rule.sub * physio
				else
					v *= (rule.mul or 0.6) ^ physio
				end
				f[k] = v >= FD.clearBelow and v or nil
			end
		end
		f.age = (f.age or 0) + 1
		-- a broken nose is set once the injury is over (or after 10 days when no injury was logged)
		if f.nose and not activeInjury(profile, "nose") and f.age >= 10 then
			f.nose = nil
			if rng:NextNumber() < FD.noseBendChance and battle.nose < 1 then
				battle.nose = math.min(1, battle.nose + FD.noseBendStep)
				table.insert(notes, "Your nose healed with a slight bend.")
			end
		end
	end
	if not f.cut then
		f.cutSide = nil
	end
	if not f.cut2 then
		f.cutSide2 = nil
	end
	local before = c.face ~= nil
	c.face = cleanFace(f)
	c.faceMarks = c.face and next(marks) ~= nil and marks or nil
	if before and not c.face then
		table.insert(notes, "Your face has fully healed.")
	end
	return notes
end

-- After a fight (Career.ApplyResult, after PassDays): head trauma accumulates from head damage and
-- knockdowns (it decays slowly and costs Chin in FightModifiers), a bad concussion or a broken nose
-- becomes an injury. res = the fight result (concPeak, kdAgainst, noseBroken, headTaken | damageTaken,
-- outcome, method, face). elapsed = days since fight night (the medical suspension PassDays just ran):
-- the injuries date from the fight, so they have already healed that long. Returns notes.
function Training.AddTrauma(profile, res, elapsed)
	local notes = {}
	if type(res) ~= "table" then
		return notes
	end
	local CC = Config.Concussion
	local c = profile.condition
	local kd = math.max(0, math.floor(finite(res.kdAgainst, 0)))
	-- head damage taken: D's res.headTaken when present, else most of damageTaken (body shots count half there)
	local head = math.max(0, finite(res.headTaken, math.max(0, finite(res.damageTaken, 0)) * 0.8))
	local before = clamp(finite(c.trauma, 0), 0, 100)
	c.trauma = clamp(before + head * CC.traumaPerDamage + kd * CC.traumaPerKnockdown, 0, 100)
	local peak = res.concPeak ~= nil and clamp(finite(res.concPeak, 0), 0, 1) or nil
	local stopped = res.outcome == "loss" and (res.method == "KO" or res.method == "TKO")
	local concussed
	if peak then
		concussed = peak >= CC.injuryAt and kd > 0
	else
		-- simulated fights have no concussion meter: being stopped after a knockdown is enough
		concussed = stopped and kd > 0
	end
	if concussed then
		local sev = peak and clamp((peak - CC.injuryAt) / math.max(0.05, 1 - CC.injuryAt), 0, 1) or 0.5
		local name, _, left = addInjury(profile, "concussion", sev, elapsed)
		if name and left > 0 then
			table.insert(notes, string.format("DOCTOR: %s. No sparring or bag work for %d more days.", name, math.ceil(left)))
		elseif name then
			table.insert(notes, "DOCTOR: " .. name .. ". It cleared during the medical suspension.")
		end
	end
	-- a new break only: D's explicit flag wins (the face table is the fallback for older results),
	-- and a nose that was already broken when the fight started cannot break again (the engine
	-- seeds it; FightEngine never re-breaks a flagged nose) - otherwise every fight before the nose
	-- set re-created the injury and re-rolled the bend
	local face = type(res.face) == "table" and res.face or nil
	local seeded = preFightNose[profile] == true
	preFightNose[profile] = nil
	local broke = res.noseBroken == true or (res.noseBroken == nil and face ~= nil and face.nose == true)
	if broke and not seeded then
		local name, new, left = addInjury(profile, "nose", rng:NextNumber(), elapsed)
		if name and new then
			table.insert(notes, "DOCTOR: " .. name .. ". Keep the mitts and sparring away from it.")
		elseif name and left <= 0 then
			-- the break healed during the suspension: set the nose now (as HealFace does once the
			-- injury is over) - AddFaceDamage just flagged it with a fresh age, which would otherwise
			-- keep it broken (and seeded into the next fight) for another 10 days
			table.insert(notes, "DOCTOR: " .. name .. ". It knitted during the medical suspension.")
			local f = cleanFace(c.face)
			if f and f.nose then
				f.nose = nil
				local battle = battleOf(profile)
				if rng:NextNumber() < FD.noseBendChance and battle.nose < 1 then
					battle.nose = math.min(1, battle.nose + FD.noseBendStep)
					table.insert(notes, "Your nose healed with a slight bend.")
				end
				c.face = cleanFace(f)
				if not c.face then
					c.faceMarks = nil
				end
			end
		end
	end
	if c.trauma >= 40 and before < 40 then
		table.insert(notes, "The doctors warn about accumulated head trauma: your chin is not what it was. Time between fights helps.")
	end
	return notes
end

------------------------------------------------------------------------
-- Days: growth, healing, detraining, aging, popularity
------------------------------------------------------------------------
-- Neglected muscle fades: a part not trained for detrainGraceDays loses
-- value * detrainRate * min(3, (idle - grace) / 7) per day (x2 from detrainAgeFrom), never below the
-- part's starting size (Training.MuscleBase) or detrainFloor. mul < 1 = active rest (fight suspension). Parts with no log entry start their clock now.
-- detraining multiplier during a post-fight medical suspension (enforced rest, light work only)
local SUSPENSION_DETRAIN = 0.1

local function detrain(profile, mul)
	local body, log = profile.body, muscleLog(profile)
	local base = type(profile.muscleBase) == "table" and profile.muscleBase or Training.MuscleBase(profile)
	local day = finite(profile.day, 1)
	local age = type(profile.identity) == "table" and finite(profile.identity.age, 25) or 25
	local ageMul = age >= MG.detrainAgeFrom and 2 or 1
	for _, p in ipairs(Config.MuscleParts) do
		local last = finite(log[p.id], nil)
		if not last then
			log[p.id] = day
		else
			local idle = day - last
			if idle > MG.detrainGraceDays then
				local v = finite(body[p.id], Config.PartValue(body, p.id))
				-- never below the part's starting size (Training.MuscleBase): an untargeted muscle
				-- fades back to where the career began, not to half of a beginner's
				local floor = math.max(MG.detrainFloor, finite(base[p.id], MG.detrainFloor))
				if v > floor then
					local loss = v * MG.detrainRate * math.min(3, (idle - MG.detrainGraceDays) / 7) * ageMul * (mul or 1)
					body[p.id] = math.max(floor, v - loss)
				end
			end
		end
	end
	-- veins: fat hides them, and they fade when the arms are not worked
	local vasc = clamp(finite(body.vasc, 0), 0, 100)
	if vasc > 0 then
		if finite(body.fat, 14) > MG.vascFatFade then
			vasc -= 0.05
		end
		local armIdle = math.min(day - finite(log.forearms, day), day - finite(log.biceps, day))
		if armIdle > MG.detrainGraceDays then
			vasc -= 0.02 * (mul or 1)
		end
		body.vasc = math.max(0, vasc)
	end
end

-- Fans forget a boxer who stops fighting: after 30 days without a fight, -0.15 popularity per day,
-- never below tier * 3. Paused during a camp (the fight is announced) and the post-fight suspension.
local POP_IDLE_DAYS, POP_DECAY = 30, 0.15
local function popularityDecay(profile, notes)
	if profile.camp then
		return
	end
	local last = finite(profile.lastFightDay, nil)
	if not last and type(profile.history) == "table" then
		local h = profile.history[#profile.history]
		last = type(h) == "table" and finite(h.day, nil) or nil
	end
	local idle = finite(profile.day, 1) - (last or 1)
	local pop = finite(profile.popularity, 0)
	local floor = finite(profile.tier, 1) * 3
	if idle > POP_IDLE_DAYS and pop > floor then
		profile.popularity = math.max(floor, pop - POP_DECAY)
		if (idle - POP_IDLE_DAYS) % 10 == 1 then
			table.insert(notes, "The fans are starting to forget you. Get back in the ring.")
		end
	end
end

-- passes one day; returns notes. ctx (optional) = { detrainMul, suspension }
local function dayTick(profile, ctx)
	ctx = ctx or {}
	local c = profile.condition
	local notes = {}
	profile.day = (profile.day or 1) + 1
	profile.ageDays = (profile.ageDays or 0) + 1
	-- hair & beard grow (the barber resets them)
	local app = profile.appearance
	if type(app) == "table" then
		if type(app.hair) == "table" then
			app.hair.growth = clamp(finite(app.hair.growth, 0) + Config.HairGrowthPerDay, 0, 1.5)
		end
		if type(app.beard) == "table" then
			app.beard.growth = clamp(finite(app.beard.growth, 0) + Config.BeardGrowthPerDay, 0, 1)
		end
	end
	for _, n in ipairs(Training.Heal(profile, 1)) do
		table.insert(notes, n)
	end
	-- the face heals a little every night; head trauma fades very slowly
	for _, n in ipairs(Training.HealFace(profile, 1)) do
		table.insert(notes, n)
	end
	if c.trauma then
		c.trauma = math.max(0, finite(c.trauma, 0) - Config.Concussion.traumaDecayPerDay)
	end
	detrain(profile, ctx.detrainMul)
	if not ctx.suspension then
		popularityDecay(profile, notes)
	end
	-- aging: a birthday every 365 days
	while profile.ageDays >= 365 do
		profile.ageDays -= 365
		profile.identity.age += 1
		table.insert(notes, string.format("Happy birthday! You are now %d.", profile.identity.age))
		if profile.identity.age >= 31 then
			local loss = profile.identity.age >= 35 and 3 or 1.5
			for _, k in ipairs({ "PunchSpeed", "Reflexes", "Footwork", "Stamina", "Recovery", "Chin" }) do
				profile.stats[k] = math.max(10, profile.stats[k] - rng:NextNumber(0.5, loss))
			end
			profile.stats.RingIQ = math.min(Config.StatCap, profile.stats.RingIQ + 1)
			table.insert(notes, "Father Time: your physical attributes declined slightly. Ring IQ improved.")
		end
	end
	Config.SyncGroups(profile.body)
	return notes
end

function Training.Sleep(profile)
	local c = profile.condition
	local q = Training.SleepQuality(profile)
	local notes = dayTick(profile)
	c.sleepQ = q
	-- supercompensation: yesterday's training becomes muscle overnight, if you slept and ate well
	local food = c.nutrition >= 40 and 1 or c.nutrition >= 20 and 0.6 or 0.35
	local grew, total = applyPending(profile, (0.7 + 0.3 * q) * food)
	if total >= 0.05 then
		table.insert(notes, string.format("Overnight recovery: +%.1f muscle (%s).", total, topPartNames(grew, 3)))
		if food < 1 then
			table.insert(notes, "You went to bed hungry, so part of that growth was lost. Eat after training.")
		end
	end
	-- eating well above your needs adds fat; running on empty burns fat and some muscle
	if c.nutrition > 75 then
		profile.body.fat = clamp(profile.body.fat + 0.06, 7, 30)
	elseif c.nutrition < 30 then
		profile.body.fat = clamp(profile.body.fat - 0.08, 7, 30)
		for _, p in ipairs(Config.MuscleParts) do
			profile.body[p.id] = math.max(3, finite(profile.body[p.id], Config.PartValue(profile.body, p.id)) - 0.15)
		end
		Config.SyncGroups(profile.body)
	end
	-- soreness fades with sleep (better sleep, faster)
	if type(c.sore) == "table" then
		local keep = clamp(MG.soreSleepKeep - MG.soreSleepQ * q, 0, 1)
		for grp, v in pairs(c.sore) do
			v = finite(v, 0) * keep
			c.sore[grp] = v >= 0.02 and v or nil
		end
	end
	c.energy = clamp(55 + 45 * q, 0, 100)
	c.fatigue = clamp(c.fatigue - (12 + 30 * q), 0, 100)
	c.nutrition = clamp(c.nutrition - 30, 0, 100)
	c.hydration = clamp(c.hydration - 22, 0, 100)
	c.water = 0
	c.buffs = {}
	c.flexible = false
	logMuscleHistory(profile) -- the new day's starting point (after tonight's growth)
	local result = { quality = q, notes = notes, day = profile.day, grew = grew, growth = total }
	if profile.camp then
		profile.camp.daysLeft = math.max(0, profile.camp.daysLeft - 1)
		result.daysLeft = profile.camp.daysLeft
		if profile.camp.daysLeft == 0 then
			table.insert(notes, "Camp is over. It's FIGHT NIGHT!")
		end
	end
	if profile.offersDay and profile.day - profile.offersDay >= 7 then
		profile.offers = nil -- new week, new fight offers
	end
	return result
end

-- time passing after a fight (medical suspension / recovery)
function Training.PassDays(profile, days)
	local notes = {}
	days = math.max(0, math.floor(finite(days, 0)))
	-- the fight that sends us here started on this face: remember whether its nose was still broken
	local f0 = profile.condition and profile.condition.face
	preFightNose[profile] = type(f0) == "table" and f0.nose == true
	-- the camp's last sessions still turn into muscle (rest is all a fighter does now)
	applyPending(profile, 0.9)
	for _ = 1, days do
		-- light work during the suspension: untrained muscle fades at a tenth of the rate (a 45-day
		-- KO suspension costs ~3% of a part, close to the original per-group 0.02/day; at 0.35 every
		-- loss cost ~11% and frequent fights kept the physique near beginner level)
		for _, n in ipairs(dayTick(profile, { detrainMul = SUSPENSION_DETRAIN, suspension = true })) do
			table.insert(notes, n)
		end
	end
	local c = profile.condition
	c.energy, c.fatigue, c.hydration, c.nutrition = 100, 0, 75, 70
	c.water, c.buffs, c.flexible, c.sleepQ = 0, {}, false, 0.85
	c.sore, c.pending = {}, {}
	-- a month off softens the physique a little (muscle loss is the per-part detraining above)
	if days >= 14 then
		profile.body.fat = clamp(profile.body.fat + days * 0.02, 7, 30)
	end
	-- back in the gym: every part gets a short grace window before detraining resumes
	local log = muscleLog(profile)
	local resume = profile.day - math.floor(MG.detrainGraceDays / 2)
	for _, p in ipairs(Config.MuscleParts) do
		log[p.id] = math.max(finite(log[p.id], resume), resume)
	end
	-- the fight just happened: popularity decay counts from the end of the suspension
	profile.lastFightDay = profile.day
	Config.SyncGroups(profile.body)
	logMuscleHistory(profile)
	return notes
end

------------------------------------------------------------------------
-- Weigh-in & fight modifiers
------------------------------------------------------------------------
function Training.WeighIn(profile)
	local wc = Config.WeightClasses[profile.physical.weightClass]
	local weight = Training.Weight(profile)
	local over = math.max(0, weight - wc.limit)
	local penalty = math.min(0.3, over * 0.025)
	return { weight = weight, limit = wc.limit, over = over, penalty = penalty, fine = over > 2 and 0.2 or 0 }
end

-- What the build itself does in a fight (pure, nil-safe; works on group-only NPC builds through
-- Config.PartValue). Core muscle absorbs body shots, a thick neck steadies the chin, calves add
-- spring to the footwork, glutes + lats drive the hips and the rotation of a punch.
-- -> { bodyArmor (body-damage multiplier), chinAdd, moveMul, powerMul, stats = { Chin = chinAdd } }
-- (stats is for callers that add stat deltas; FightModifiers adds chinAdd itself)
function Training.FightModifiersFromBuild(build)
	build = type(build) == "table" and build or {}
	local function v(id)
		return clamp(finite(Config.PartValue(build, id), 8), 0, 130)
	end
	local chinAdd = v("neck") / 100 * 4
	return {
		bodyArmor = clamp(1 - v("core") / 100 * 0.15, 0.8, 1),
		chinAdd = chinAdd,
		moveMul = 1 + v("calves") / 100 * 0.03,
		powerMul = 1 + (v("glutes") + v("lats")) / 200 * 0.03,
		stats = { Chin = chinAdd },
	}
end

-- modifiers the fight engine applies to the player's fighter
function Training.FightModifiers(profile)
	local c = profile.condition
	local mods = { stats = {}, staminaMul = 1, notes = {} }
	for _, inj in ipairs(Training.ActiveInjuries(profile)) do
		local def = Config.Injuries[inj.id]
		for stat, v in pairs(def and def.fight or {}) do
			mods.stats[stat] = (mods.stats[stat] or 0) + v
		end
		table.insert(mods.notes, "Fighting through a " .. def.name)
	end
	-- condition on fight night
	if c.hydration < 30 then
		mods.staminaMul -= 0.08
		table.insert(mods.notes, "Dehydrated")
	end
	if c.nutrition < 30 then
		mods.staminaMul -= 0.05
		table.insert(mods.notes, "Under-fueled")
	end
	if c.energy < 40 then
		mods.staminaMul -= 0.06
		table.insert(mods.notes, "Low energy")
	end
	local wi = Training.WeighIn(profile)
	mods.staminaMul -= wi.penalty
	mods.weighIn = wi
	-- physique: muscle adds pop, excess fat costs gas
	local upper = ((profile.body.chest or 0) + (profile.body.shoulders or 0) + (profile.body.arms or 0) + (profile.body.back or 0)) / 400
	local fromBuild = Training.FightModifiersFromBuild(profile.body)
	mods.powerMul = 1 + upper * 0.08 + (fromBuild.powerMul - 1)
	mods.bodyArmor = fromBuild.bodyArmor
	mods.stats.Chin = (mods.stats.Chin or 0) + fromBuild.chinAdd
	if (profile.body.fat or 14) > 18 then
		mods.staminaMul -= ((profile.body.fat or 14) - 18) * 0.015
	end
	-- career head trauma: every war leaves the chin a little weaker
	local trauma = clamp(finite(c.trauma, 0), 0, 100)
	mods.trauma = trauma
	if trauma > 0 then
		mods.stats.Chin -= trauma / Config.Concussion.traumaChinDiv
		if trauma >= 15 then
			table.insert(mods.notes, "Carrying head trauma")
		end
	end
	-- heavy legs and arms from yesterday's lifting
	local maxSore = 0
	for _, v in pairs(type(c.sore) == "table" and c.sore or {}) do
		maxSore = math.max(maxSore, finite(v, 0))
	end
	if maxSore >= 0.5 then
		mods.staminaMul -= 0.03
		table.insert(mods.notes, "Sore from training")
	end
	-- gear
	local gloves = Training.GearItem(profile, "gloves")
	if gloves then
		mods.powerMul *= 1 + (gloves.power or 0) * (Training.GearCondition(profile, "gloves") < 40 and 0.5 or 1)
		mods.speedMul = 1 + (gloves.speed or 0)
	end
	local shoes = Training.GearItem(profile, "shoes")
	mods.moveMul = (1 + (shoes and shoes.footwork or 0) - (Training.GearCondition(profile, "shoes") < 25 and 0.03 or 0)) * fromBuild.moveMul
	local guard = Training.GearItem(profile, "mouthguard")
	if guard and guard.chin and guard.chin > 0 then
		mods.stats.Chin = (mods.stats.Chin or 0) + guard.chin
	end
	mods.staminaMul = clamp(mods.staminaMul, 0.5, 1.1)
	return mods
end

------------------------------------------------------------------------
-- Equipment, gear, coaches (purchases)
------------------------------------------------------------------------
function Training.UpgradeStation(profile, stationId)
	local st = Catalog.Stations[stationId]
	if not st then
		return false, "Unknown station"
	end
	local cur = profile.gym.levels[stationId] or 1
	local nxt = st.levels[cur + 1]
	if not nxt then
		return false, "Already at the top level."
	end
	if nxt.requiresTier and profile.tier < nxt.requiresTier then
		return false, "Elite equipment unlocks when you become a World Champion."
	end
	if profile.money < nxt.cost then
		return false, "Not enough money."
	end
	profile.money -= nxt.cost
	profile.gym.levels[stationId] = cur + 1
	profile.gym.cond[stationId] = 100
	return true, nxt.name
end

function Training.RepairStation(profile, stationId)
	local lv = profile.gym.levels[stationId]
	if not lv then
		return false, "Unknown station"
	end
	if (profile.gym.cond[stationId] or 100) >= 99 then
		return false, "Already in perfect condition."
	end
	local cost = Catalog.RepairCost(stationId, lv)
	if profile.money < cost then
		return false, "Repair costs " .. Config.Money(cost) .. "."
	end
	profile.money -= cost
	profile.gym.cond[stationId] = 100
	return true, cost
end

function Training.BuyGear(profile, kind, id)
	local list = Catalog.GearList(kind)
	local item = list and Catalog.Find(list, id)
	if not item then
		return false, "Unknown item"
	end
	if profile.gear.owned[kind][id] then
		-- replacing worn gear with a fresh one
		if kind == "mouthguard" or kind == "robe" then
			return false, "Already owned."
		end
	end
	if item.requiresTier and profile.tier < item.requiresTier then
		return false, "Unlocks when you become a World Champion."
	end
	if profile.money < item.price then
		return false, "Not enough money."
	end
	profile.money -= item.price
	profile.gear.owned[kind][id] = true
	profile.gear.equipped[kind] = id
	if kind ~= "mouthguard" and kind ~= "robe" then
		profile.gear.cond[kind .. ":" .. id] = 100
	end
	if kind == "robe" and item.pop then
		profile.popularity = clamp(profile.popularity + item.pop, 0, 100)
	end
	return true
end

function Training.Equip(profile, kind, id)
	if not profile.gear.owned[kind] or not profile.gear.owned[kind][id] then
		return false, "You don't own that."
	end
	profile.gear.equipped[kind] = id
	return true
end

function Training.RepairGear(profile, kind)
	local item, id = Training.GearItem(profile, kind)
	if not item then
		return false, "Nothing equipped"
	end
	local key = kind .. ":" .. id
	if (profile.gear.cond[key] or 100) >= 99 then
		return false, "Already in great shape."
	end
	local cost = Catalog.RepairGearCost(kind, item)
	if profile.money < cost then
		return false, "Repair costs " .. Config.Money(cost) .. "."
	end
	profile.money -= cost
	profile.gear.cond[key] = 100
	return true, cost
end

-- coach specialties by id only (Config.FindById also matches display names, and the first entry
-- for a nil id): every key written to profile.coaches must be a CoachSpecialties id
local function coachSpec(specId)
	if type(specId) ~= "string" then
		return nil
	end
	return Catalog.Find(Catalog.CoachSpecialties, specId)
end

function Training.HireCoach(profile, specId, tier)
	tier = math.floor(finite(tier, 0))
	local spec = coachSpec(specId)
	local def = Catalog.CoachTiers[tier]
	local names = spec and Catalog.CoachNames[spec.id]
	local name = type(names) == "table" and names[tier] or nil
	if not spec or not def or not name then
		return false, "Unknown coach"
	end
	if (profile.coaches[spec.id] or 0) >= tier then
		return false, "You already have a coach at that level."
	end
	if profile.money < def.cost then
		return false, "Signing fee is " .. Config.Money(def.cost) .. "."
	end
	-- pay last: every lookup above has already succeeded
	profile.money -= def.cost
	profile.coaches[spec.id] = tier
	return true, name
end

function Training.FireCoach(profile, specId)
	local spec = coachSpec(specId)
	if not spec or (profile.coaches[spec.id] or 0) == 0 then
		return false, "No coach to release."
	end
	profile.coaches[spec.id] = 0
	return true
end

function Training.TeamSalary(profile)
	local total = 0
	for specId, tier in pairs(profile.coaches) do
		if tier > 0 then
			total += Catalog.CoachTiers[tier].salary
		end
	end
	return total
end

function Training.EliteCorner(profile)
	return (profile.coaches.RingIQ or 0) >= 3 or (profile.coaches.Defense or 0) >= 3
end

function Training.CampDays(profile)
	local d = Config.Tiers[profile.tier].campDays
	if Training.Owned(profile, "MountainCamp") then
		d += 1
	end
	if Training.Owned(profile, "EliteCamp") then
		d += 2
	end
	return d
end

-- minigame difficulty/params for an activity
function Training.MinigameParams(profile, act)
	local lv = Training.StationLevel(profile, act.station)
	local p = {
		level = lv, smart = (act.station == "heavybag" and lv >= 5) or Training.Owned(profile, "SmartSystem"),
		elite = Catalog.Stations[act.station] and Catalog.Stations[act.station].levels[lv] and Catalog.Stations[act.station].levels[lv].elite or false,
	}
	if act.minigame == "mitts" then
		p.tier = lv
	elseif act.minigame == "rope" then
		p.doubleUnders = lv >= 3
		p.footwork = lv >= 4
	end
	return p
end

------------------------------------------------------------------------
-- Save migration (DataManager.Load). Never bump Config.DataVersion: a mismatch wipes careers.
------------------------------------------------------------------------
local function numIn(t, k, lo, hi, default)
	t[k] = clamp(finite(t[k], default), lo, hi)
	return t[k]
end

local function tableIn(t, k, default)
	if type(t[k]) ~= "table" then
		t[k] = default or {}
	end
	return t[k]
end

-- An old save only knows the 7 groups. Each group with no parts yet is split across its parts by
-- the player's own training history (profile.records sessions x each exercise's targeting), so a
-- bench-heavy career migrates with fuller pecs and front delts. Each part gets a bias b in
-- [-lim, lim] (lim <= 20%) and the share-weighted sum is re-balanced to exactly the old group value
-- (part = gv * (1 + b - mean b)): weight, power and lift loads do not move. lim shrinks with the
-- headroom to the frame cap, so no part ends above it (gv * (1 + 2 lim) <= cap) on veteran saves.
local function seedPartsFromHistory(profile, body)
	local records = type(profile.records) == "table" and profile.records or {}
	local cap = Training.MuscleCap(profile)
	local affinity = {}
	for _, act in ipairs(Config.Activities) do
		local r = records[act.id]
		local n = type(r) == "table" and math.max(0, finite(r.sessions, 0)) or 0
		if n > 0 and not act.recovery then
			for id, w in pairs(Training.Targets(act)) do
				affinity[id] = (affinity[id] or 0) + n * finite(w, 0)
			end
		end
	end
	for _, g in ipairs(Config.MuscleKeys) do
		local parts = Config.MuscleGroupParts[g]
		local missing = true
		for _, p in ipairs(parts) do
			if type(body[p.id]) == "number" then
				missing = false
			end
		end
		if missing then
			local gv = body[g]
			local lim = math.min(0.2, math.max(0, (cap / math.max(gv, 1e-6) - 1) / 2))
			local mean = 0
			for _, p in ipairs(parts) do
				mean += p.share * (affinity[p.id] or 0)
			end
			local sum = 0
			for _, p in ipairs(parts) do
				local rel = mean > 0 and (affinity[p.id] or 0) / mean or 1
				body[p.id] = gv * (1 + clamp((rel - 1) * 0.2, -lim, lim))
				sum += p.share * body[p.id]
			end
			local delta = gv - sum
			for _, p in ipairs(parts) do
				body[p.id] = math.max(0, body[p.id] + delta)
			end
		end
	end
	return records
end

-- Brings any created save up to the current shape, in place. Idempotent (safe on every join),
-- additive (fills what is missing) and defensive (NaN / wrong types / out-of-range values are
-- repaired so one corrupt value can never crash Sleep, Summary or a fight). Returns the profile.
function Training.Migrate(profile)
	if type(profile) ~= "table" or not profile.created then
		return profile
	end
	-- identity / numbers the math depends on
	local identity = tableIn(profile, "identity")
	identity.age = math.floor(clamp(finite(identity.age, 22), 16, 70))
	-- the names Career.Summary formats (a non-string errored the join's push)
	for _, k in ipairs({ "first", "last", "name", "nickname", "nationality" }) do
		if type(identity[k]) ~= "string" then
			identity[k] = nil
		end
	end
	identity.first = identity.first or "Boxer"
	identity.last = identity.last or ""
	identity.name = identity.name or (identity.first .. " " .. identity.last)
	identity.nickname = identity.nickname or ""
	identity.nationality = identity.nationality or "USA"
	local physical = tableIn(profile, "physical")
	physical.weightClass = math.floor(clamp(finite(physical.weightClass, 5), 1, #Config.WeightClasses))
	physical.baseWeight = finite(physical.baseWeight, Config.WeightClasses[physical.weightClass].limit)
	local stats = tableIn(profile, "stats")
	for _, k in ipairs(Config.StatKeys) do
		numIn(stats, k, 1, Config.StatCap, 30)
	end
	-- derived from the (now finite) stats: a NaN overall saves as null and the client formats it
	profile.overall = Config.Overall(stats)
	local mental = tableIn(profile, "mental")
	for k in pairs(mental) do
		if not table.find(Config.MentalKeys, k) then
			mental[k] = nil -- a stray entry (Career.Summary rounds every value)
		end
	end
	for _, k in ipairs(Config.MentalKeys) do
		numIn(mental, k, 0, 100, 50)
	end
	-- belts and regional titles: one boolean per org / level
	local belts = tableIn(profile, "belts")
	for k in pairs(belts) do
		if not table.find(Config.Orgs, k) then
			belts[k] = nil
		end
	end
	for _, org in ipairs(Config.Orgs) do
		belts[org] = belts[org] == true
	end
	local regional = tableIn(profile, "regional")
	regional.regional = regional.regional == true
	regional.national = regional.national == true
	numIn(profile, "day", 1, 1e7, 1)
	numIn(profile, "ageDays", 0, 365, 0)
	numIn(profile, "popularity", 0, 100, 1)
	numIn(profile, "money", -1e12, 1e12, 0)
	profile.tier = math.floor(clamp(finite(profile.tier, 1), 1, #Config.Tiers))
	tableIn(profile, "owned")
	tableIn(profile, "history")

	-- appearance: every v2 look field (face sliders, hairline, battle wear...) with neutral defaults
	profile.appearance = Looks.Fill(profile.appearance)
	local app = profile.appearance
	if type(app.hair) == "table" then
		app.hair.growth = clamp(finite(app.hair.growth, 0), 0, 1.5)
	end
	if type(app.beard) == "table" then
		app.beard.growth = clamp(finite(app.beard.growth, 0), 0, 1)
	end
	battleOf(profile)

	-- body: only finite numbers (Career.Summary rounds every value), groups -> parts, vascularity
	local body = profile.body
	if type(body) ~= "table" then
		body = Training.NewBody(Training.Frame(profile).id)
		profile.body = body
	end
	for k, v in pairs(body) do
		if type(k) ~= "string" or finite(v, nil) == nil then
			body[k] = nil
		end
	end
	for _, g in ipairs(Config.MuscleKeys) do
		numIn(body, g, 0, 130, 8)
	end
	numIn(body, "fat", Config.BodyFat.min, Config.BodyFat.max, Config.BodyFat.default)
	local records = seedPartsFromHistory(profile, body)
	Config.FillParts(body)
	-- no part above the frame's cap (CONTRACTS 2: 0..100*potential): a corrupt value or a frame
	-- changed to a smaller one is brought back under it; a cap clamp keeps this idempotent
	local partCap = Training.MuscleCap(profile)
	for _, p in ipairs(Config.MuscleParts) do
		numIn(body, p.id, 0, partCap, 8)
	end
	if body.vasc == nil then
		-- veterans of the dumbbell rack start with some veins
		local r = records.Dumbbells
		body.vasc = math.min(25, (type(r) == "table" and math.max(0, finite(r.sessions, 0)) or 0) * 0.5)
	end
	numIn(body, "vasc", 0, 100, 0)
	Config.SyncGroups(body)

	-- condition
	local c = tableIn(profile, "condition", Training.NewCondition())
	numIn(c, "energy", 0, 100, 100)
	numIn(c, "hydration", 0, 100, 80)
	numIn(c, "nutrition", 0, 100, 70)
	numIn(c, "fatigue", 0, 100, 0)
	numIn(c, "sleepQ", 0.4, 1, 0.8)
	numIn(c, "water", -20, 20, 0)
	numIn(c, "trauma", 0, 100, 0)
	tableIn(c, "buffs")
	local injuries = {}
	for _, inj in ipairs(type(c.injuries) == "table" and c.injuries or {}) do
		if type(inj) == "table" and Config.Injuries[inj.id] and finite(inj.days, 0) > 0 then
			table.insert(injuries, { id = inj.id, days = clamp(finite(inj.days, 0), 0, 365) })
		end
	end
	c.injuries = injuries
	local sore = {}
	for grp, v in pairs(type(c.sore) == "table" and c.sore or {}) do
		v = finite(v, 0)
		if Config.MuscleGroupParts[grp] and v > 0 then
			sore[grp] = clamp(v, 0, 1)
		end
	end
	c.sore = sore
	local pending = {}
	for id, v in pairs(type(c.pending) == "table" and c.pending or {}) do
		v = finite(v, 0)
		if PART_SHARE[id] and v > 0 then
			pending[id] = clamp(v, 0, 20)
		end
	end
	c.pending = pending
	-- last classified physique (Training.PhysiqueInfo hysteresis); unknown ids are dropped
	if type(c.physiqueId) ~= "string" or not Config.FindById(Config.Physiques, c.physiqueId) then
		c.physiqueId = nil
	end
	c.face = cleanFace(c.face)
	if not c.face or type(c.faceMarks) ~= "table" then
		c.faceMarks = nil
	end

	-- detraining clock: unknown parts start counting from today
	local log = muscleLog(profile)
	for k, v in pairs(log) do
		if not PART_SHARE[k] or finite(v, nil) == nil then
			log[k] = nil
		end
	end
	for _, p in ipairs(Config.MuscleParts) do
		if log[p.id] == nil then
			log[p.id] = profile.day
		end
	end
	-- detraining floor per part (saves from before it: 6 * potential)
	Training.MuscleBase(profile)

	-- gym: every station (the medicine ball is new) with the level / condition a new career gets
	local gym = tableIn(profile, "gym", Training.NewGym())
	local levels, cond = tableIn(gym, "levels"), tableIn(gym, "cond")
	for id in pairs(cond) do
		if not Catalog.Stations[id] then
			cond[id] = nil -- a stray entry (Career.Summary rounds every value)
		end
	end
	for id, st in pairs(Catalog.Stations) do
		if levels[id] == nil then
			levels[id] = st.levels[1].cost > 0 and 0 or 1
		end
		levels[id] = math.floor(clamp(finite(levels[id], 1), 0, #st.levels))
		if cond[id] == nil then
			cond[id] = (id == "heavybag" or id == "speedbag" or id == "doubleend") and 60 or 80
		end
		numIn(cond, id, 0, 100, 80)
	end

	-- gear & coaches
	local fresh = Training.NewGear()
	local gear = tableIn(profile, "gear", fresh)
	local owned, equipped = tableIn(gear, "owned"), tableIn(gear, "equipped")
	tableIn(gear, "cond")
	for kind, id in pairs(fresh.equipped) do
		tableIn(owned, kind)
		if equipped[kind] == nil then
			owned[kind][id] = true
			equipped[kind] = id
		end
	end
	local coaches = tableIn(profile, "coaches")
	-- only specialty ids: an old HireCoach bug saved display-name keys ('Ring IQ') that cost a
	-- salary every fight (TeamSalary) and never gave a boost (CoachBoost)
	for k in pairs(coaches) do
		if type(k) ~= "string" or not Catalog.Find(Catalog.CoachSpecialties, k) then
			coaches[k] = nil
		end
	end
	for _, spec in ipairs(Catalog.CoachSpecialties) do
		coaches[spec.id] = math.floor(clamp(finite(coaches[spec.id], 0), 0, #Catalog.CoachTiers))
	end
	-- career counters Career.Summary / legacyParts multiply (a wrong type there errored the join's
	-- push, leaving the player on the loading screen): both records and every tally, whole and finite
	for _, k in ipairs({ "record", "amateurRecord" }) do
		local rec = tableIn(profile, k)
		for _, f in ipairs({ "w", "l", "d", "ko" }) do
			rec[f] = math.floor(numIn(rec, f, 0, 1e6, 0))
		end
	end
	for _, k in ipairs({ "titlesWon", "defenses", "undisputedReigns", "qualityWins", "knockdownsScored", "sessions", "tierWins" }) do
		profile[k] = math.floor(numIn(profile, k, 0, 1e6, 0))
	end
	-- gear condition values: Career.Summary floors each one; a non-finite entry is dropped (the gear
	-- then reads as new), the rest clamped to 0..100
	for key, v in pairs(gear.cond) do
		if type(key) ~= "string" or finite(v, nil) == nil then
			gear.cond[key] = nil
		else
			gear.cond[key] = clamp(v, 0, 100)
		end
	end
	-- training XP and the muscle history (both created lazily; a corrupt history is dropped)
	numIn(profile, "xp", 0, 1e9, 0)
	if type(profile.muscleHist) ~= "table" then
		profile.muscleHist = nil
	end
	logMuscleHistory(profile)
	return profile
end

return Training
