-- Training: the advanced training system.
-- Condition (energy, hydration, nutrition, sleep, fatigue), overtraining & injuries,
-- days and sleep, meals, gym equipment levels/condition/repairs, gear wear,
-- coaches, body evolution (muscle groups, body fat, weight) and weigh-ins.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local Training = {}
local rng = Random.new()

local function clamp(v, a, b)
	return math.clamp(v, a, b)
end

------------------------------------------------------------------------
-- New-career defaults
------------------------------------------------------------------------
function Training.NewBody(frameId)
	local frame = Config.FindById(Config.BodyTypes, frameId) or Config.BodyTypes[2]
	local body = {}
	for _, k in ipairs(Config.MuscleKeys) do
		body[k] = math.floor((6 + rng:NextNumber(0, 5)) * frame.potential * 10) / 10
	end
	body.fat = 14 + rng:NextNumber(-1, 1.5)
	return body
end

function Training.NewCondition()
	return { energy = 100, hydration = 80, nutrition = 70, fatigue = 0, sleepQ = 0.8, injuries = {}, buffs = {}, water = 0, flexible = false }
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
	return profile.owned[id] == true
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

function Training.Physique(profile)
	local b = profile.body
	local upper = ((b.chest or 0) + (b.shoulders or 0) + (b.arms or 0) + (b.back or 0)) / 4
	local fat = b.fat or 14
	if upper < 18 and fat < 17 then
		return "Lean"
	elseif fat >= 21 then
		return "Heavy"
	elseif upper >= 55 and fat <= 12 then
		return "Shredded Power Physique"
	elseif upper >= 45 then
		return "Muscular"
	elseif fat <= 11 then
		return "Lean & Defined"
	end
	return "Athletic"
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
		return true
	end
	local cost = Training.EnergyCost(profile, act, intensity)
	if profile.condition.energy < cost then
		return false, string.format("Not enough energy (%d needed, %d left). Eat, recover or sleep.", cost, math.floor(profile.condition.energy))
	end
	return true
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
		local cur = profile.stats[stat]
		local dim = clamp(1 - (cur - 25) / 78, 0.05, 1.1)
		local g = Config.GainScale * weight * Training.GainMultiplier(profile, stat, act) * quality * condMult * dim * scale
		local new = math.min(Config.StatCap, cur + g)
		result.gains[stat] = new - cur
		profile.stats[stat] = new
	end
	-- muscle growth (diminishing toward the frame's potential)
	local frame = Config.FindById(Config.BodyTypes, profile.appearance.body.frame) or Config.BodyTypes[2]
	local cap = 100 * frame.potential
	local muscleBuff = 1 + (c.buffs.muscle or 0)
	for grp, weight in pairs(act.muscle or {}) do
		local cur = profile.body[grp] or 0
		local room = clamp(1 - cur / cap, 0, 1)
		local g = 1.3 * weight * quality * condMult * muscleBuff * room * scale
		profile.body[grp] = math.min(cap, cur + g)
		result.muscle[grp] = g
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
	-- injuries from overtraining
	local inj = injuryRoll(profile, act, opts.extraRisk)
	if inj then
		result.injury = inj
		table.insert(result.notes, "INJURY: " .. inj .. ". Rest, ice baths and massage speed up healing.")
	end
	if c.fatigue > 70 then
		table.insert(result.notes, "You're overtraining. Gains are dropping and injury risk is high.")
	end
	if c.hydration < 25 then
		table.insert(result.notes, "You're dehydrated. Grab water from the cooler.")
	end
	if c.nutrition < 25 then
		table.insert(result.notes, "You're running on empty. Eat something at the Nutrition Bar.")
	end
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
	return result
end

function Training.Recover(profile, act, quality)
	quality = clamp(tonumber(quality) or 1, 0.5, 1.5)
	local c = profile.condition
	local r = act.recovery
	local _, lv = Training.StationLevel(profile, act.station)
	local mult = (lv and lv.mult or 1) * (0.8 + 0.2 * quality)
	local result = { notes = {} }
	if act.price and not (act.station == "massage" and Training.StationLevel(profile, "massage") >= 2) then
		profile.money -= act.price
		table.insert(result.notes, "Paid " .. Config.Money(act.price) .. " for the session.")
	end
	c.fatigue = clamp(c.fatigue + (r.fatigue or 0) * ((r.fatigue or 0) < 0 and mult or 1), 0, 100)
	c.energy = clamp(c.energy + (r.energy or 0) * ((r.energy or 0) > 0 and mult or 1), 0, 100)
	if r.hydration then
		c.hydration = clamp(c.hydration + r.hydration, 0, 100)
	end
	if r.water then
		local w = r.water * mult
		c.water = (c.water or 0) + w
		table.insert(result.notes, string.format("Sweated out %.1f lbs of water weight. Rehydrate after the weigh-in.", -w))
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

local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

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
	local meal = Config.FindById(Config.Meals, mealId)
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
	return clamp(q, 0.4, 1)
end

-- passes one day; returns notes
local function dayTick(profile)
	local c = profile.condition
	local notes = {}
	profile.day = (profile.day or 1) + 1
	profile.ageDays = (profile.ageDays or 0) + 1
	-- hair & beard grow
	local app = profile.appearance
	app.hair.growth = clamp((app.hair.growth or 0) + 0.004, 0, 1.5)
	app.beard.growth = clamp((app.beard.growth or 0) + 0.02, 0, 1)
	for _, n in ipairs(Training.Heal(profile, 1)) do
		table.insert(notes, n)
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
	return notes
end

function Training.Sleep(profile)
	local c = profile.condition
	local q = Training.SleepQuality(profile)
	local notes = dayTick(profile)
	c.sleepQ = q
	-- eating well above your needs adds fat; running on empty burns fat and some muscle
	if c.nutrition > 75 then
		profile.body.fat = clamp(profile.body.fat + 0.06, 7, 30)
	elseif c.nutrition < 30 then
		profile.body.fat = clamp(profile.body.fat - 0.08, 7, 30)
		for _, k in ipairs(Config.MuscleKeys) do
			profile.body[k] = math.max(3, profile.body[k] - 0.15)
		end
	end
	c.energy = clamp(55 + 45 * q, 0, 100)
	c.fatigue = clamp(c.fatigue - (12 + 30 * q), 0, 100)
	c.nutrition = clamp(c.nutrition - 30, 0, 100)
	c.hydration = clamp(c.hydration - 22, 0, 100)
	c.water = 0
	c.buffs = {}
	c.flexible = false
	-- untrained muscle slowly fades; fat creeps up if you're not burning it
	local result = { quality = q, notes = notes, day = profile.day }
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
	for _ = 1, days do
		for _, n in ipairs(dayTick(profile)) do
			table.insert(notes, n)
		end
	end
	local c = profile.condition
	c.energy, c.fatigue, c.hydration, c.nutrition = 100, 0, 75, 70
	c.water, c.buffs, c.flexible, c.sleepQ = 0, {}, false, 0.85
	-- a month off softens the physique a little
	if days >= 14 then
		profile.body.fat = clamp(profile.body.fat + days * 0.02, 7, 30)
		for _, k in ipairs(Config.MuscleKeys) do
			profile.body[k] = math.max(3, profile.body[k] - days * 0.02)
		end
	end
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
	mods.powerMul = 1 + upper * 0.08
	if (profile.body.fat or 14) > 18 then
		mods.staminaMul -= ((profile.body.fat or 14) - 18) * 0.015
	end
	-- gear
	local gloves = Training.GearItem(profile, "gloves")
	if gloves then
		mods.powerMul *= 1 + (gloves.power or 0) * (Training.GearCondition(profile, "gloves") < 40 and 0.5 or 1)
		mods.speedMul = 1 + (gloves.speed or 0)
	end
	local shoes = Training.GearItem(profile, "shoes")
	mods.moveMul = 1 + (shoes and shoes.footwork or 0) - (Training.GearCondition(profile, "shoes") < 25 and 0.03 or 0)
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

function Training.HireCoach(profile, specId, tier)
	tier = math.floor(tonumber(tier) or 0)
	local spec = Config.FindById(Catalog.CoachSpecialties, specId)
	local def = Catalog.CoachTiers[tier]
	if not spec or not def then
		return false, "Unknown coach"
	end
	if (profile.coaches[specId] or 0) >= tier then
		return false, "You already have a coach at that level."
	end
	if profile.money < def.cost then
		return false, "Signing fee is " .. Config.Money(def.cost) .. "."
	end
	profile.money -= def.cost
	profile.coaches[specId] = tier
	return true, Catalog.CoachNames[specId][tier]
end

function Training.FireCoach(profile, specId)
	if (profile.coaches[specId] or 0) == 0 then
		return false, "No coach to release."
	end
	profile.coaches[specId] = 0
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

return Training
