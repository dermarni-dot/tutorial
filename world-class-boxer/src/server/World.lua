-- World: generates and maintains the AI boxing world (270 boxers), rankings for
-- WBA / WBC / IBF / WBO, regional & national belts, and AI-vs-AI activity.
-- Every AI boxer has a unique look (generated from a seed), build, style,
-- in-ring archetype and personality.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))

local World = {}

local function hash(str)
	local h = 7
	for i = 1, #str do
		h = (h * 31 + string.byte(str, i)) % 1000003
	end
	return h
end

local function clampStat(v)
	return math.clamp(v, 10, Config.StatCap)
end

function World.MakeStats(rng, target, styleId)
	local style = Config.FindById(Config.Styles, styleId) or Config.Styles[4]
	local stats = {}
	for _, k in ipairs(Config.StatKeys) do
		stats[k] = clampStat(target + rng:NextNumber(-7, 7) + (style.mods[k] or 0))
	end
	-- each AI boxer gets one or two standout strengths
	for _ = 1, rng:NextInteger(1, 2) do
		local k = Config.StatKeys[rng:NextInteger(1, #Config.StatKeys)]
		stats[k] = clampStat(stats[k] + rng:NextNumber(5, 12))
	end
	return stats
end

local function aggressionFor(styleId)
	local s = Config.FindById(Config.Styles, styleId)
	return s and math.floor(s.ai.aggression * 100) or 50
end

local function newBoxer(world, rng, ci, target, usedNames, ageLo, ageHi)
	local id = "b" .. world.nextId
	world.nextId += 1
	local female = rng:NextNumber() < 0.15
	local name
	repeat
		local first = female and Config.FirstNamesF[rng:NextInteger(1, #Config.FirstNamesF)] or Config.FirstNames[rng:NextInteger(1, #Config.FirstNames)]
		name = first .. " " .. Config.LastNames[rng:NextInteger(1, #Config.LastNames)]
	until not (usedNames and usedNames[name])
	if usedNames then
		usedNames[name] = true
	end
	local arch = Config.Archetypes[rng:NextInteger(1, #Config.Archetypes)]
	local stats = World.MakeStats(rng, target, arch.style)
	if arch.id == "Defensive" then
		stats.Blocking = clampStat(stats.Blocking + 6)
		stats.HeadMovement = clampStat(stats.HeadMovement + 5)
	elseif arch.id == "KO" then
		stats.Power = clampStat(stats.Power + 6)
	elseif arch.id == "Technician" then
		stats.RingIQ = clampStat(stats.RingIQ + 7)
	elseif arch.id == "Counter" then
		stats.Reflexes = clampStat(stats.Reflexes + 5)
	end
	local frac = math.clamp((target - 26) / 64, 0, 1)
	return {
		id = id, name = name, nick = Config.Nicknames[rng:NextInteger(1, #Config.Nicknames)],
		nat = Config.Nationalities[rng:NextInteger(1, #Config.Nationalities)], gender = female and 2 or 1,
		class = ci, style = arch.style, archetype = arch.id,
		personality = Config.Personalities[rng:NextInteger(1, #Config.Personalities)],
		stats = stats, overall = Config.Overall(stats), age = rng:NextInteger(ageLo or 19, ageHi or 36),
		record = { w = 0, l = 0, d = 0, ko = 0 },
		mental = {
			Confidence = 40 + frac * 40, Discipline = rng:NextInteger(35, 90), Aggression = aggressionFor(arch.style),
			Focus = rng:NextInteger(35, 85), Composure = 35 + frac * 45,
		},
		lookSeed = rng:NextInteger(1, 2 ^ 30), height = math.clamp(60 + ci * 1.6 + rng:NextInteger(-3, 3), 60, 84),
		h2h = { w = 0, l = 0, d = 0 }, heat = 0, learned = {}, belts = {},
	}
end

-- full look + build + gear for an AI boxer (deterministic: the same boxer always looks the same).
-- Looks.Random gets the ring personality / champion status / career length so the physique
-- archetype and the boxer's battle wear (cauliflower ears, bent nose, scars) match who he is, and
-- RandomBuild gets that physique so the muscles agree with it (CONTRACTS 1, 4).
function World.Look(b)
	local frac = math.clamp(((tonumber(b.overall) or 50) - 26) / 64, 0, 1)
	local rec = type(b.record) == "table" and b.record or {}
	local fights = (rec.w or 0) + (rec.l or 0) + (rec.d or 0)
	local age = tonumber(b.age) or 25
	local seed = b.lookSeed or hash(tostring(b.id))
	local champion = type(b.belts) == "table" and #b.belts > 0
	local app = Looks.Random(seed, b.gender or 1, {
		-- veteran keeps its old definition: it changes how many legacy draws Looks.Random makes
		class = b.class, age = b.age, veteran = age >= 31 or ((rec.w or 0) + (rec.l or 0)) > 30, height = b.height,
		archetype = b.archetype, champion = champion, fights = fights,
	})
	local physique = app.body and app.body.physique
	if physique == "Auto" then
		physique = nil
	end
	local build = Looks.RandomBuild(seed, frac, age, app.body.frame, physique)
	-- kit follows the level: champions wear the best, prospects the basics (Catalog ids)
	local gloveTier = frac > 0.8 and "Championship" or (frac > 0.55 and "Professional" or (frac > 0.3 and "Competition" or "Cheap"))
	if champion and frac > 0.85 then
		gloveTier = "Custom"
	end
	local wraps = frac > 0.55 and "Gel" or (frac > 0.2 and "Cotton" or "OldWraps")
	local shoes = frac > 0.8 and "EliteBoots" or (frac > 0.55 and "ProBoots" or (frac > 0.2 and "Boots" or "Sneakers"))
	local gear = {
		gloves = gloveTier, glovesCond = 70 + frac * 30,
		wraps = wraps, wrapsCond = 80 + frac * 20,
		shoes = shoes, shoesCond = 75 + frac * 25,
		mouthguard = frac > 0.5 and "CustomFit" or "BoilBite",
		robe = champion and "Champion" or (frac > 0.6 and "Hooded" or "Classic"),
	}
	return app, build, gear
end

function World.Generate(seed)
	local rng = Random.new(seed)
	local world = { v = 2, boxers = {}, classes = {}, champions = {}, regional = { regional = {}, national = {} }, nextId = 1 }
	local usedNames = {}
	for ci, _ in ipairs(Config.WeightClasses) do
		local ids = {}
		for i = 1, Config.WorldPerClass do
			local frac = (i - 1) / (Config.WorldPerClass - 1)
			local target = 26 + (frac ^ 1.15) * 64 + rng:NextNumber(-3, 3)
			local b = newBoxer(world, rng, ci, target, usedNames)
			local fights = math.floor(frac * 38 + rng:NextInteger(0, 8))
			local winRate = math.clamp(0.45 + frac * 0.5 + rng:NextNumber(-0.1, 0.1), 0.3, 1)
			local w = math.floor(fights * winRate + 0.5)
			local d = rng:NextNumber() < 0.3 and rng:NextInteger(0, 2) or 0
			local l = math.max(0, fights - w - d)
			local koRate = math.clamp(0.25 + (b.stats.Power - 50) / 80, 0.1, 0.9)
			b.record = { w = w, l = l, d = d, ko = math.floor(w * koRate) }
			world.boxers[b.id] = b
			table.insert(ids, b.id)
		end
		world.classes[ci] = ids
		world.regional.regional[ci] = ids[rng:NextInteger(8, 11)]
		world.regional.national[ci] = ids[rng:NextInteger(14, 17)]
	end
	for _, org in ipairs(Config.Orgs) do
		world.champions[org] = {}
	end
	for ci, ids in ipairs(world.classes) do
		local sorted = table.clone(ids)
		table.sort(sorted, function(a, b)
			return world.boxers[a].overall > world.boxers[b].overall
		end)
		for oi, org in ipairs(Config.Orgs) do
			local pickIdx = ((oi - 1) % 3) + 1
			if rng:NextNumber() < 0.25 then
				pickIdx = 1
			end
			local champ = sorted[pickIdx]
			world.champions[org][ci] = champ
			table.insert(world.boxers[champ].belts, org)
		end
	end
	return world
end

function World.Score(b, org)
	local r = b.record
	local base = b.overall * 6 + r.w * 4 - r.l * 10 + r.ko * 1.5 + (#b.belts * 40)
	return base + (hash(b.id .. org) % 40) - 20
end

function World.PlayerScore(profile, org)
	local r = profile.record
	local base = profile.overall * 6 + r.w * 4 - r.l * 10 + r.ko * 1.5 + (profile.qualityWins or 0) * 12
	local belts = 0
	for _, has in pairs(profile.belts) do
		if has then
			belts += 1
		end
	end
	return base + belts * 40 + (hash("player" .. org) % 30) - 15
end

function World.Rankings(profile, ci, org)
	local world = profile.world
	local list = {}
	local champId = world.champions[org][ci]
	local playerChamp = profile.belts[org] and profile.physical.weightClass == ci
	for _, id in ipairs(world.classes[ci]) do
		local b = world.boxers[id]
		if not b.retired then
			table.insert(list, {
				id = id, name = b.name, nick = b.nick, record = b.record, overall = b.overall,
				nat = b.nat, style = b.style, score = World.Score(b, org),
				isChamp = (not playerChamp) and champId == id,
			})
		end
	end
	if profile.tier >= 2 and profile.physical.weightClass == ci then
		table.insert(list, {
			id = "player", name = profile.identity.name, nick = profile.identity.nickname, record = profile.record,
			overall = profile.overall, nat = profile.identity.nationality, style = profile.style,
			score = World.PlayerScore(profile, org), isPlayer = true, isChamp = playerChamp,
		})
	end
	table.sort(list, function(a, b)
		if a.isChamp ~= b.isChamp then
			return a.isChamp
		end
		return a.score > b.score
	end)
	local rank = 0
	for _, e in ipairs(list) do
		if e.isChamp then
			e.rank = "C"
		else
			rank += 1
			e.rank = rank
		end
	end
	return list
end

function World.PlayerRanks(profile)
	local out = {}
	if profile.tier < 2 then
		return out
	end
	for _, org in ipairs(Config.Orgs) do
		for _, e in ipairs(World.Rankings(profile, profile.physical.weightClass, org)) do
			if e.isPlayer then
				out[org] = e.rank
				break
			end
		end
	end
	return out
end

function World.BestRank(profile)
	local best, bestOrg = 999, nil
	for org, r in pairs(World.PlayerRanks(profile)) do
		if r ~= "C" and r < best then
			best, bestOrg = r, org
		end
	end
	return best, bestOrg
end

function World.RankOf(profile, id, org)
	for _, e in ipairs(World.Rankings(profile, profile.physical.weightClass, org)) do
		if e.id == id then
			return e.rank
		end
	end
	return nil
end

local function aiBout(a, b, rng)
	local pa = a.overall + rng:NextNumber(-12, 12)
	local pb = b.overall + rng:NextNumber(-12, 12)
	local ko = rng:NextNumber() < 0.4
	if math.abs(pa - pb) < 1.5 then
		a.record.d += 1
		b.record.d += 1
		return nil
	end
	local winner, loser = a, b
	if pb > pa then
		winner, loser = b, a
	end
	winner.record.w += 1
	loser.record.l += 1
	if ko then
		winner.record.ko += 1
	end
	return winner, loser
end

-- AI boxers keep fighting and developing between the player's fights
function World.SimulateCycle(profile, rng)
	local world = profile.world
	rng = rng or Random.new()
	for ci, ids in ipairs(world.classes) do
		local active = {}
		for _, id in ipairs(ids) do
			local b = world.boxers[id]
			if not b.retired then
				table.insert(active, b)
			end
		end
		table.sort(active, function(x, y)
			return x.overall < y.overall
		end)
		local bouts = ci == profile.physical.weightClass and 6 or 2
		for _ = 1, bouts do
			local i = rng:NextInteger(1, #active - 1)
			local a, b = active[i], active[math.min(#active, i + rng:NextInteger(1, 3))]
			if a ~= b then
				local winner, loser = aiBout(a, b, rng)
				if winner then
					for _, org in ipairs(Config.Orgs) do
						if world.champions[org][ci] == loser.id and not (profile.belts[org] and profile.physical.weightClass == ci) then
							if rng:NextNumber() < 0.5 then
								world.champions[org][ci] = winner.id
								local bi = table.find(loser.belts, org)
								if bi then
									table.remove(loser.belts, bi)
								end
								table.insert(winner.belts, org)
							end
						end
					end
				end
			end
		end
		for _, b in ipairs(active) do
			if rng:NextNumber() < 0.2 then
				b.age += 1
			end
			local delta = 0
			if b.age < 27 then
				delta = rng:NextNumber(0, 1.2)
			elseif b.age > 33 then
				delta = -rng:NextNumber(0, 1.5)
			end
			if delta ~= 0 then
				for _, k in ipairs(Config.StatKeys) do
					b.stats[k] = clampStat(b.stats[k] + delta * rng:NextNumber(0.3, 1.2))
				end
				b.overall = Config.Overall(b.stats)
			end
			if b.age >= 38 and #b.belts == 0 and b.heat < 30 and rng:NextNumber() < 0.3 then
				b.retired = true
				local nb = newBoxer(world, rng, ci, rng:NextNumber(28, 45), nil, 18, 22)
				world.boxers[nb.id] = nb
				table.insert(ids, nb.id)
			end
		end
		for _, kind in ipairs({ "regional", "national" }) do
			local holderId = world.regional[kind][ci]
			local holder = world.boxers[holderId]
			if holderId ~= "player" and (not holder or holder.retired) then
				world.regional[kind][ci] = active[kind == "regional" and 9 or 15].id
			end
		end
	end
end

function World.Pick(profile, ci, minOv, maxOv, exclude, rng)
	local world = profile.world
	local pool = {}
	for _, id in ipairs(world.classes[ci]) do
		local b = world.boxers[id]
		if not b.retired and b.overall >= minOv and b.overall <= maxOv and not (exclude and exclude[id]) then
			table.insert(pool, b)
		end
	end
	if #pool == 0 then
		local best, bestD = nil, math.huge
		for _, id in ipairs(world.classes[ci]) do
			local b = world.boxers[id]
			local d = math.abs(b.overall - (minOv + maxOv) / 2)
			if not b.retired and d < bestD and not (exclude and exclude[id]) then
				best, bestD = b, d
			end
		end
		return best
	end
	return pool[(rng or Random.new()):NextInteger(1, #pool)]
end

return World
