-- Career: character creation, fight offers, camps, economy, titles, promotions,
-- rivalries, simulated fights, legacy, retirement and the client summary.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))
local World = require(script.Parent.World)
local Training = require(script.Parent.Training)

local Career = {}
local rng = Random.new()

local function clamp(v, a, b)
	return math.clamp(v, a, b)
end

local function round(n)
	return math.floor(n + 0.5)
end

------------------------------------------------------------------------
-- Creation
------------------------------------------------------------------------
-- d = { first, last, name, nickname, age, nationality, music, voice, weightClass, weight, reachDelta, style, specialty, look }
function Career.CreateProfile(old, d, userId)
	local look = Looks.Sanitize(d.look)
	local ci = clamp(math.floor(tonumber(d.weightClass) or 5), 1, #Config.WeightClasses)
	local wc = Config.WeightClasses[ci]
	local age = clamp(math.floor(tonumber(d.age) or 20), 16, 35)
	local style = Config.FindById(Config.Styles, d.style) or Config.Styles[4]
	local spec = Config.FindById(Config.Specialties, d.specialty) or Config.Specialties[1]
	local frame = Config.FindById(Config.BodyTypes, look.body.frame) or Config.BodyTypes[2]
	local nat = table.find(Config.Nationalities, d.nationality) and d.nationality or "USA"
	local music = tostring(d.music or ""):gsub("%D", ""):sub(1, 20)
	local voice = table.find(Config.VoiceTypes, d.voice) and d.voice or "Calm"

	local base = 26 + (age - 16) * 0.75
	local stats = {}
	for _, k in ipairs(Config.StatKeys) do
		stats[k] = clamp(base + (style.mods[k] or 0) + (frame.mods[k] or 0) + (spec.stats[k] or 0), 10, 60)
	end
	local profile = {
		v = Config.DataVersion, created = true, retired = false,
		pastCareers = old and old.pastCareers or {},
		identity = {
			first = d.first, last = d.last, name = d.name, nickname = d.nickname, age = age, gender = look.gender,
			nationality = nat, music = music, voice = voice,
		},
		appearance = look,
		physical = {
			height = look.height, weightClass = ci,
			reach = look.height + clamp(math.floor(tonumber(d.reachDelta) or 2), -3, 6),
			baseWeight = wc.limit,
		},
		style = style.id, specialty = spec.id,
		stats = stats,
		mental = {
			Confidence = 50, Discipline = 55, Aggression = math.floor(style.ai.aggression * 100),
			Focus = 50, Composure = 45 + (age - 16) * 0.8,
		},
		body = Training.NewBody(frame.id),
		condition = Training.NewCondition(),
		gym = Training.NewGym(),
		gear = Training.NewGear(),
		coaches = Training.NewCoaches(),
		money = 500, popularity = 1, day = 1, ageDays = 0, sessions = 0,
		tier = 1, tierWins = 0,
		record = { w = 0, l = 0, d = 0, ko = 0 },
		amateurRecord = { w = 0, l = 0, d = 0, ko = 0 },
		belts = { WBA = false, WBC = false, IBF = false, WBO = false },
		regional = { regional = false, national = false },
		defenses = 0, titlesWon = 0, qualityWins = 0, undisputedReigns = 0, knockdownsScored = 0,
		owned = {}, camp = nil, offers = nil, history = {},
	}
	-- starting walk-around weight: what the player picked (inside the class range)
	local target = clamp(math.floor(tonumber(d.weight) or (wc.limit - 2)), wc.min, wc.limit)
	Training.SetBaseWeight(profile, target)
	profile.world = World.Generate((userId or 1) + os.time())
	profile.overall = Config.Overall(stats)
	return profile
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function Career.Owned(profile, id)
	return profile.owned[id] == true
end

function Career.OppView(profile, b)
	local ranks = {}
	if profile.tier >= 2 then
		for _, org in ipairs(Config.Orgs) do
			ranks[org] = World.RankOf(profile, b.id, org)
		end
	end
	local style = Config.FindById(Config.Styles, b.style)
	local arch = Config.FindById(Config.Archetypes, b.archetype)
	return {
		id = b.id, name = b.name, nick = b.nick, nat = b.nat, style = style and style.name or b.style,
		archetype = arch and arch.name or "", overall = b.overall, record = b.record, age = b.age,
		personality = b.personality, h2h = b.h2h, heat = b.heat, belts = b.belts, ranks = ranks,
	}
end

local function pickTalk(profile, b)
	local pname = profile.identity.name
	local total = b.h2h.w + b.h2h.l + b.h2h.d
	if total == 2 then
		return string.format(Config.TrilogyTalk[rng:NextInteger(1, #Config.TrilogyTalk)], pname)
	elseif b.h2h.w > b.h2h.l then
		return string.format(Config.RevengeTalk[rng:NextInteger(1, #Config.RevengeTalk)], pname)
	end
	local lines = Config.TrashTalk[b.personality] or Config.TrashTalk["Technician"]
	return string.format(lines[rng:NextInteger(1, #lines)], pname)
end

function Career.PlayerLine(profile, oppName)
	local lines = Config.VoiceLines[profile.identity.voice or "Calm"] or Config.VoiceLines.Calm
	return string.format(lines[rng:NextInteger(1, #lines)], oppName)
end

local function purseFor(profile, b, mult)
	local t = Config.Tiers[profile.tier]
	local lo, hi = t.purse[1], t.purse[2]
	local f = clamp((b.overall - profile.overall + 10) / 25, 0, 1)
	local p = lo + (hi - lo) * f
	p *= 1 + profile.popularity / 250
	return round(p * (mult or 1) / 50) * 50
end

local function makeOffer(profile, b, kind, extra)
	extra = extra or {}
	local tier = Config.Tiers[profile.tier]
	local rounds = tier.rounds
	if kind == "Regional Title" or kind == "National Title" then
		rounds = 10
	elseif kind == "World Title" or kind == "Unification" or kind == "Title Defense" then
		rounds = 12
	end
	local venue = Config.VenueFor(kind, profile.tier)
	return {
		oppId = b.id, kind = kind, rounds = rounds, venue = venue, venueName = Config.Venues[venue].name,
		purse = purseFor(profile, b, extra.purseMult),
		stakes = extra.stakes or {}, playerStakes = extra.playerStakes or {},
		opp = Career.OppView(profile, b), talk = pickTalk(profile, b),
	}
end

local function playerBelts(profile)
	local list = {}
	for _, org in ipairs(Config.Orgs) do
		if profile.belts[org] then
			table.insert(list, org)
		end
	end
	return list
end
Career.PlayerBelts = playerBelts

------------------------------------------------------------------------
-- Offers
------------------------------------------------------------------------
function Career.GetOffers(profile)
	if profile.camp or profile.retired then
		return profile.offers or {}
	end
	if profile.offers then
		return profile.offers
	end
	local world = profile.world
	local ci = profile.physical.weightClass
	local pOv = profile.overall
	local offers = {}
	local used = {}
	local function add(o)
		if o and not used[o.oppId] then
			used[o.oppId] = true
			table.insert(offers, o)
		end
	end

	for _, id in ipairs(world.classes[ci]) do
		local b = world.boxers[id]
		local total = b.h2h.w + b.h2h.l + b.h2h.d
		if not b.retired and total > 0 and b.heat >= 50 and math.abs(b.overall - pOv) <= 10 and #offers < 1 then
			local kind = total == 1 and "Rematch" or (total == 2 and "Trilogy" or "Grudge Match")
			add(makeOffer(profile, b, kind, { purseMult = 1.25 + b.heat / 200 }))
		end
	end

	local tier = profile.tier
	local belts = playerBelts(profile)
	local _, bestOrg = World.BestRank(profile)

	if tier == 2 and profile.tierWins >= 3 and not profile.regional.regional then
		local b = world.boxers[world.regional.regional[ci]]
		if b then
			add(makeOffer(profile, b, "Regional Title", { purseMult = 2 }))
		end
	elseif tier == 3 and profile.tierWins >= 3 and not profile.regional.national then
		local b = world.boxers[world.regional.national[ci]]
		if b then
			add(makeOffer(profile, b, "National Title", { purseMult = 2 }))
		end
	end

	if tier >= 7 then
		for _, org in ipairs(Config.Orgs) do
			if not profile.belts[org] then
				local champ = world.boxers[world.champions[org][ci]]
				local rank = World.PlayerRanks(profile)[org]
				if champ and (rank and rank ~= "C" and rank <= 5 or #belts > 0) then
					local stakes = table.clone(champ.belts)
					if #belts > 0 then
						add(makeOffer(profile, champ, "Unification", { stakes = stakes, playerStakes = belts, purseMult = 1.6 }))
					else
						add(makeOffer(profile, champ, "World Title", { stakes = stakes, purseMult = 1.3 }))
					end
				end
			end
		end
	end
	if #belts > 0 then
		for _, e in ipairs(World.Rankings(profile, ci, belts[1])) do
			if not e.isPlayer and e.rank ~= "C" then
				add(makeOffer(profile, world.boxers[e.id], "Title Defense", { playerStakes = belts, purseMult = 1.2 }))
				break
			end
		end
	end
	if tier == 6 and bestOrg then
		for _, e in ipairs(World.Rankings(profile, ci, bestOrg)) do
			if not e.isPlayer and e.rank ~= "C" and e.rank <= 5 and e.overall <= pOv + 8 then
				add(makeOffer(profile, world.boxers[e.id], "Title Eliminator", { purseMult = 1.3 }))
				break
			end
		end
	end

	local lo, hi = -8, 3
	if tier == 2 then
		lo, hi = -6, 5
	elseif tier == 3 or tier == 4 then
		lo, hi = -5, 6
	elseif tier >= 5 then
		lo, hi = -5, 8
	end
	local exclude = {}
	if tier < 7 then
		for _, org in ipairs(Config.Orgs) do
			local champ = world.champions[org][ci]
			if champ then
				exclude[champ] = true
			end
		end
	end
	local tries = 0
	while #offers < 4 and tries < 24 do
		tries += 1
		for id in pairs(used) do
			exclude[id] = true
		end
		local widen = math.floor(tries / 4) * 3
		local b = World.Pick(profile, ci, pOv + lo - widen, pOv + hi + widen, exclude, rng)
		if b then
			add(makeOffer(profile, b, tier == 1 and "Amateur Bout" or "Pro Fight"))
		end
	end
	profile.offers = offers
	profile.offersDay = profile.day
	return offers
end

function Career.AcceptOffer(profile, index)
	if profile.camp or profile.retired then
		return false, "Already in camp"
	end
	local offer = profile.offers and profile.offers[index]
	if not offer then
		return false, "Offer expired"
	end
	local days = Training.CampDays(profile)
	profile.camp = { offer = offer, daysLeft = days, daysTotal = days, log = {} }
	profile.offers = nil
	return true
end

function Career.ChangeWeightClass(profile, dir)
	if profile.camp then
		return false, "Finish your camp first."
	end
	local ci = profile.physical.weightClass + (dir == -1 and -1 or 1)
	if ci < 1 or ci > #Config.WeightClasses then
		return false, "No class that way."
	end
	local vacated = playerBelts(profile)
	for _, org in ipairs(vacated) do
		profile.belts[org] = false
		local cur = profile.physical.weightClass
		local list = profile.world.classes[cur]
		local best, bestOv = nil, -1
		for _, id in ipairs(list) do
			local b = profile.world.boxers[id]
			if not b.retired and b.overall > bestOv then
				best, bestOv = b, b.overall
			end
		end
		if best then
			profile.world.champions[org][cur] = best.id
			table.insert(best.belts, org)
		end
	end
	if profile.regional.regional or profile.regional.national then
		profile.regional = { regional = profile.tier >= 3, national = profile.tier >= 4 }
	end
	profile.physical.weightClass = ci
	profile.offers = nil
	if profile.tier >= 8 then
		profile.tier = 7
	end
	return true, Config.WeightClasses[ci].name, #vacated
end

------------------------------------------------------------------------
-- Shop
------------------------------------------------------------------------
function Career.Buy(profile, id)
	local item = Catalog.Find(Catalog.Shop, id)
	if not item then
		return false, "Unknown item"
	end
	if profile.owned[item.id] then
		return false, "Already owned"
	end
	if item.requiresTier and profile.tier < item.requiresTier then
		return false, "Elite equipment unlocks when you become a World Champion."
	end
	if profile.money < item.price then
		return false, "Not enough money"
	end
	profile.money -= item.price
	profile.owned[item.id] = true
	if item.conf then
		profile.mental.Confidence = clamp(profile.mental.Confidence + item.conf, 0, 100)
	end
	if item.pop then
		profile.popularity = clamp(profile.popularity + item.pop, 0, 100)
	end
	return true
end

------------------------------------------------------------------------
-- Fighters for the fight engine
------------------------------------------------------------------------
function Career.GearView(profile)
	local g = profile.gear
	return {
		gloves = g.equipped.gloves, glovesCond = Training.GearCondition(profile, "gloves"),
		wrapsCond = Training.GearCondition(profile, "wraps"), shoesCond = Training.GearCondition(profile, "shoes"), robe = g.equipped.robe,
	}
end

function Career.LookOpts(profile, extra)
	local o = {
		name = profile.identity.name, nick = profile.identity.nickname, nat = profile.identity.nationality,
		waistText = profile.identity.nickname, robe = profile.gear.equipped.robe,
	}
	for k, v in pairs(extra or {}) do
		o[k] = v
	end
	return o
end

function Career.FighterFromProfile(profile)
	local mods = Training.FightModifiers(profile)
	local stats = table.clone(profile.stats)
	for k, v in pairs(mods.stats) do
		stats[k] = clamp((stats[k] or 30) + v, 10, Config.StatCap)
	end
	return {
		isPlayer = true, name = profile.identity.name, nick = profile.identity.nickname,
		stats = stats, mental = table.clone(profile.mental), style = profile.style,
		class = profile.physical.weightClass, reach = profile.physical.reach, height = profile.physical.height,
		app = profile.appearance, build = profile.body, gear = Career.GearView(profile),
		fatigue = profile.condition.fatigue, mods = mods,
		record = profile.tier == 1 and profile.amateurRecord or profile.record, nat = profile.identity.nationality,
		music = profile.identity.music, voice = profile.identity.voice,
		eliteCorner = Training.EliteCorner(profile), nutrition = Training.Owned(profile, "Nutritionist"),
		lookOpts = Career.LookOpts(profile),
	}
end

function Career.FighterFromBoxer(b)
	local app, build, gear = World.Look(b)
	return {
		isPlayer = false, id = b.id, name = b.name, nick = b.nick, stats = table.clone(b.stats),
		mental = table.clone(b.mental), style = b.style, archetype = b.archetype, class = b.class,
		reach = (b.height or 70) + (#b.name % 5), height = b.height or 70, app = app, build = build, gear = gear,
		fatigue = 0, record = b.record, nat = b.nat, personality = b.personality,
		learned = table.clone(b.learned or {}), h2h = b.h2h,
		lookOpts = { name = b.name, nick = b.nick, nat = b.nat, waistText = b.nick, robe = "Classic" },
	}
end

------------------------------------------------------------------------
-- Simulated fight (for players who want to skip a bout)
------------------------------------------------------------------------
function Career.SimFight(profile, offer)
	local b = profile.world.boxers[offer.oppId]
	local p = Career.FighterFromProfile(profile)
	local pPow = (p.stats.Power + p.stats.PunchSpeed + p.stats.Countering + p.stats.RingIQ) / 4
	local pDef = (p.stats.Blocking + p.stats.HeadMovement + p.stats.Chin + p.stats.Reflexes) / 4
	local oPow = (b.stats.Power + b.stats.PunchSpeed + b.stats.Countering + b.stats.RingIQ) / 4
	local oDef = (b.stats.Blocking + b.stats.HeadMovement + b.stats.Chin + b.stats.Reflexes) / 4
	local fatPen = math.max(0, p.fatigue - 50) / 8 + (1 - p.mods.staminaMul) * 20
	local cards = { { 0, 0 }, { 0, 0 }, { 0, 0 } }
	local pDmg, oDmg, kdFor, kdAg = 0, 0, 0, 0
	local landed, oLanded = 0, 0
	local punches = { jab = 5, cross = 3, leadhook = 2, rearhook = 1, uppercut = 1 }
	for r = 1, offer.rounds do
		local edge = (profile.overall - b.overall) + ((pPow - oDef) - (oPow - pDef)) * 0.3 - fatPen + (profile.mental.Confidence - 50) / 20
		local pOut = math.max(1, 12 + edge * 0.35 + rng:NextNumber(-6, 6))
		local oOut = math.max(1, 12 - edge * 0.35 + rng:NextNumber(-6, 6))
		landed += round(pOut)
		oLanded += round(oOut)
		oDmg += pOut * (p.stats.Power / b.stats.Chin) * 0.9 * (p.mods.powerMul or 1)
		pDmg += oOut * (b.stats.Power / p.stats.Chin) * 0.9
		local pKD = oDmg > 60 and rng:NextNumber() < 0.25
		local oKD = pDmg > 60 and rng:NextNumber() < 0.25
		if pKD then
			kdFor += 1
			oDmg -= 25
		end
		if oKD then
			kdAg += 1
			pDmg -= 25
		end
		for j = 1, 3 do
			local diff = pOut - oOut + rng:NextNumber(-3, 3)
			local a, c = 10, 10
			if diff > 0.25 then
				c = 9
			elseif diff < -0.25 then
				a = 9
			end
			if pKD then
				c -= 1
			end
			if oKD then
				a -= 1
			end
			cards[j][1] += a
			cards[j][2] += c
		end
		if kdFor >= 2 and oDmg > 70 or kdFor >= 3 then
			return { outcome = "win", method = rng:NextNumber() < 0.5 and "KO" or "TKO", round = r, cards = cards,
				kdFor = kdFor, kdAgainst = kdAg, landed = landed, oppLanded = oLanded, punches = punches, simulated = true, damageTaken = pDmg }
		elseif kdAg >= 2 and pDmg > 70 or kdAg >= 3 then
			return { outcome = "loss", method = rng:NextNumber() < 0.5 and "KO" or "TKO", round = r, cards = cards,
				kdFor = kdFor, kdAgainst = kdAg, landed = landed, oppLanded = oLanded, punches = punches, simulated = true, damageTaken = pDmg }
		end
	end
	local res = Career.DecideCards(cards)
	res.round = offer.rounds
	res.cards = cards
	res.kdFor, res.kdAgainst, res.landed, res.oppLanded = kdFor, kdAg, landed, oLanded
	res.punches = punches
	res.simulated = true
	res.damageTaken = pDmg
	return res
end

function Career.DecideCards(cards)
	local pw, ow = 0, 0
	for _, c in ipairs(cards) do
		if c[1] > c[2] then
			pw += 1
		elseif c[2] > c[1] then
			ow += 1
		end
	end
	if pw == 3 then
		return { outcome = "win", method = "UD" }
	elseif ow == 3 then
		return { outcome = "loss", method = "UD" }
	elseif pw == 2 and ow == 1 then
		return { outcome = "win", method = "SD" }
	elseif ow == 2 and pw == 1 then
		return { outcome = "loss", method = "SD" }
	elseif pw == 2 then
		return { outcome = "win", method = "MD" }
	elseif ow == 2 then
		return { outcome = "loss", method = "MD" }
	end
	return { outcome = "draw", method = "Draw" }
end

------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------
local function fightRating(offer, res)
	local r = 2
	local diff = 0
	for _, c in ipairs(res.cards or {}) do
		diff += math.abs(c[1] - c[2])
	end
	r += math.max(0, 3 - diff / 4)
	r += (res.kdFor or 0) * 0.8 + (res.kdAgainst or 0) * 0.8
	if offer.kind ~= "Pro Fight" and offer.kind ~= "Amateur Bout" then
		r += 1.5
	end
	if res.method == "KO" or res.method == "TKO" then
		r += 1
	end
	r += (offer.opp.overall or 50) / 50
	return math.clamp(r, 1, 10)
end

function Career.ApplyResult(profile, res)
	local camp = profile.camp
	local offer = camp.offer
	local world = profile.world
	local ci = profile.physical.weightClass
	local b = world.boxers[offer.oppId]
	local notes = {}
	local win, loss, draw = res.outcome == "win", res.outcome == "loss", res.outcome == "draw"
	local isKO = res.method == "KO" or res.method == "TKO" or res.method == "RTD"
	local rec = profile.tier == 1 and profile.amateurRecord or profile.record

	if win then
		rec.w += 1
		if isKO then
			rec.ko += 1
		end
		b.record.l += 1
		b.h2h.w += 1
		profile.tierWins += 1
	elseif loss then
		rec.l += 1
		b.record.w += 1
		if isKO then
			b.record.ko += 1
		end
		b.h2h.l += 1
	else
		rec.d += 1
		b.record.d += 1
		b.h2h.d += 1
	end
	profile.knockdownsScored += res.kdFor or 0

	local meetings = b.h2h.w + b.h2h.l + b.h2h.d
	b.heat = math.clamp(b.heat + 18 + ((res.method == "SD" or res.method == "MD" or draw) and 20 or 0) + (win and 12 or 0)
		+ ((b.personality == "Trash Talker" or b.personality == "Hothead") and 12 or 0) + ((res.kdFor or 0) + (res.kdAgainst or 0)) * 4, 0, 100)
	if meetings >= 3 and math.abs(b.h2h.w - b.h2h.l) >= 2 then
		b.heat = math.max(0, b.heat - 45)
	end
	b.learned = b.learned or {}
	for k, v in pairs(res.punches or {}) do
		b.learned[k] = (b.learned[k] or 0) * 0.5 + v
	end
	if meetings >= 2 then
		table.insert(notes, string.format("Rivalry: %s %d-%d-%d (you-them-draws).", b.name, b.h2h.w, b.h2h.l, b.h2h.d))
	end

	-- money: purse, sponsors, TV, minus team salaries and weight fines
	local purse = offer.purse
	if win then
		purse = round(purse * 1.2)
	end
	local sponsor = 0
	if profile.tier >= 3 and profile.popularity >= 5 then
		sponsor = round((profile.popularity ^ 1.4) * 35 * profile.tier)
	end
	local tv = 0
	if profile.tier >= 5 then
		tv = round(offer.purse * 0.25 + profile.popularity * 1200)
	end
	local salary = Training.TeamSalary(profile)
	local fine = 0
	if res.weighIn and res.weighIn.fine and res.weighIn.fine > 0 then
		fine = round(purse * res.weighIn.fine)
		table.insert(notes, string.format("Missed weight by %.1f lbs: fined %s.", res.weighIn.over, Config.Money(fine)))
	end
	local total = purse + sponsor + tv - salary - fine
	profile.money += total
	table.insert(notes, string.format("Purse %s  Sponsors %s  TV %s  Team salaries -%s", Config.Money(purse), Config.Money(sponsor), Config.Money(tv), Config.Money(salary)))

	local m = profile.mental
	if win then
		profile.popularity = math.clamp(profile.popularity + 2 + (isKO and 2 or 0) + (offer.kind ~= "Pro Fight" and offer.kind ~= "Amateur Bout" and 6 or 0), 0, 100)
		m.Confidence = math.clamp(m.Confidence + 4 + (isKO and 2 or 0), 25, 100)
	elseif loss then
		profile.popularity = math.clamp(profile.popularity - 1, 0, 100)
		m.Confidence = math.clamp(m.Confidence - 4, 25, 100)
	end
	m.Focus = math.clamp(m.Focus + 1, 0, 100)
	m.Composure = math.clamp(m.Composure + 1 + ((res.kdAgainst or 0) > 0 and win and 3 or 0), 0, 100)
	if win and b.overall >= 70 then
		profile.qualityWins += 1
	end

	-- gear takes a beating on fight night
	Training.WearGear(profile, "gloves", 6)
	Training.WearGear(profile, "shoes", 3)
	Training.WearGear(profile, "wraps", 10)

	local function giveBelt(org)
		profile.belts[org] = true
		local prevB = world.boxers[world.champions[org][ci]]
		if prevB then
			local i = table.find(prevB.belts, org)
			if i then
				table.remove(prevB.belts, i)
			end
		end
		world.champions[org][ci] = "player"
		profile.titlesWon += 1
		table.insert(notes, "NEW " .. org .. " WORLD CHAMPION!")
	end
	if win then
		if offer.kind == "Regional Title" then
			profile.regional.regional = true
			world.regional.regional[ci] = "player"
			profile.tier = 3
			profile.tierWins = 0
			table.insert(notes, "You are the REGIONAL CHAMPION!")
		elseif offer.kind == "National Title" then
			profile.regional.national = true
			world.regional.national[ci] = "player"
			profile.tier = 4
			profile.tierWins = 0
			table.insert(notes, "You are the NATIONAL CHAMPION!")
		end
		for _, org in ipairs(offer.stakes or {}) do
			if not profile.belts[org] then
				giveBelt(org)
			end
		end
		if #(offer.playerStakes or {}) > 0 then
			profile.defenses += 1
			table.insert(notes, "Successful title defense #" .. profile.defenses)
		end
	elseif loss and #(offer.playerStakes or {}) > 0 then
		for _, org in ipairs(offer.playerStakes) do
			if profile.belts[org] then
				profile.belts[org] = false
				world.champions[org][ci] = b.id
				table.insert(b.belts, org)
				table.insert(notes, "You lost your " .. org .. " title.")
			end
		end
	end
	local nBelts = #playerBelts(profile)
	if nBelts == 4 and profile.tier < 9 then
		profile.tier = 9
		profile.undisputedReigns += 1
		table.insert(notes, "UNDISPUTED CHAMPION OF THE WORLD!")
	elseif nBelts > 0 and profile.tier < 8 then
		profile.tier = 8
	elseif nBelts < 4 and profile.tier >= 9 and nBelts > 0 then
		profile.tier = 8
	elseif nBelts == 0 and profile.tier >= 8 then
		profile.tier = 7
		table.insert(notes, "You're a former champion. Climb back to a title shot.")
	end

	-- time passes: medical suspension / recovery
	local suspension = 21
	if loss and isKO then
		suspension = 45
	elseif loss then
		suspension = 28
	elseif (res.kdAgainst or 0) > 0 then
		suspension = 28
	end
	for _, n in ipairs(Training.PassDays(profile, suspension)) do
		table.insert(notes, n)
	end
	table.insert(notes, string.format("%d days of recovery before your next camp.", suspension))
	World.SimulateCycle(profile, rng)
	for _, id in ipairs(world.classes[ci]) do
		local x = world.boxers[id]
		x.heat = math.max(0, x.heat - 4)
	end
	profile.overall = Config.Overall(profile.stats)

	if profile.tier == 1 and profile.amateurRecord.w >= 4 then
		profile.tier = 2
		profile.tierWins = 0
		table.insert(notes, "You turned PRO! You're now a Local Pro. Global rankings now include you.")
	elseif profile.tier == 4 and profile.tierWins >= 2 then
		profile.tier = 5
		profile.tierWins = 0
		table.insert(notes, "Promoted: International Contender.")
	end
	local best = World.BestRank(profile)
	if profile.tier == 5 and best <= 10 then
		profile.tier = 6
		table.insert(notes, "You broke into the TOP 10!")
	end
	if profile.tier == 6 and best <= 3 then
		profile.tier = 7
		table.insert(notes, "Title Challenger: world title shots are now available.")
	end
	if profile.tier == 9 and profile.defenses >= 2 and Career.Legacy(profile).score >= 500 then
		profile.tier = 10
		table.insert(notes, "You are now a BOXING LEGEND.")
	end

	local entry = {
		day = profile.day, opp = b.name, oppId = b.id, outcome = res.outcome, method = res.method, round = res.round,
		kind = offer.kind, rating = fightRating(offer, res), kdFor = res.kdFor or 0, kdAgainst = res.kdAgainst or 0,
		stakes = offer.stakes, cards = res.cards, amateur = offer.kind == "Amateur Bout", venue = offer.venueName,
	}
	table.insert(profile.history, entry)
	while #profile.history > 80 do
		table.remove(profile.history, 1)
	end
	profile.camp = nil
	profile.offers = nil
	return { notes = notes, earnings = total, entry = entry }
end

------------------------------------------------------------------------
-- Legacy
------------------------------------------------------------------------
function Career.Legacy(profile)
	local r = profile.record
	local parts = {
		{ "Pro wins", r.w * 3 },
		{ "Knockouts", r.ko * 1.5 },
		{ "Losses", -r.l * 3 },
		{ "World titles won", profile.titlesWon * 40 },
		{ "Title defenses", profile.defenses * 12 },
		{ "Undisputed reigns", profile.undisputedReigns * 80 },
		{ "Elite wins", profile.qualityWins * 6 },
		{ "Regional & national titles", (profile.regional.regional and 10 or 0) + (profile.regional.national and 20 or 0) },
		{ "Legend status", profile.tier >= 10 and 100 or 0 },
	}
	local score = 0
	for _, p in ipairs(parts) do
		score += p[2]
	end
	score = math.max(0, round(score))
	local list = table.clone(Config.Legends)
	table.insert(list, { name = profile.identity.name .. " (YOU)", score = score, you = true })
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	local goat = 0
	for i, e in ipairs(list) do
		if e.you then
			goat = i
		end
	end
	local fights = table.clone(profile.history)
	table.sort(fights, function(a, b)
		return a.rating > b.rating
	end)
	local top = {}
	for i = 1, math.min(5, #fights) do
		top[i] = fights[i]
	end
	return {
		score = score, parts = parts, goatRank = goat, goatList = list,
		hallOfFame = score >= Config.HallOfFameScore, greatest = top,
	}
end

function Career.Retire(profile)
	if profile.retired then
		return
	end
	profile.camp = nil
	profile.retired = true
	local lg = Career.Legacy(profile)
	profile.final = lg
	table.insert(profile.pastCareers, 1, {
		name = profile.identity.name, nick = profile.identity.nickname, record = profile.record,
		titles = profile.titlesWon, score = lg.score, goatRank = lg.goatRank, hof = lg.hallOfFame,
	})
	while #profile.pastCareers > 10 do
		table.remove(profile.pastCareers)
	end
end

------------------------------------------------------------------------
-- Client summary
------------------------------------------------------------------------
local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

function Career.Summary(profile, storeOk)
	if not profile.created then
		return { created = false, pastCareers = profile.pastCareers, storeOk = storeOk }
	end
	local stats = {}
	for k, v in pairs(profile.stats) do
		stats[k] = r2(v)
	end
	local mental = {}
	for k, v in pairs(profile.mental) do
		mental[k] = math.floor(v)
	end
	local body = {}
	for k, v in pairs(profile.body) do
		body[k] = r2(v)
	end
	local ranks = World.PlayerRanks(profile)
	local best, bestOrg = World.BestRank(profile)
	local hist = {}
	for i = #profile.history, math.max(1, #profile.history - 11), -1 do
		table.insert(hist, profile.history[i])
	end
	local camp
	if profile.camp then
		camp = { daysLeft = profile.camp.daysLeft, daysTotal = profile.camp.daysTotal, offer = profile.camp.offer, log = profile.camp.log }
	end
	local c = profile.condition
	local injuries = {}
	for _, inj in ipairs(Training.ActiveInjuries(profile)) do
		local def = Config.Injuries[inj.id]
		table.insert(injuries, { id = inj.id, name = def and def.name or inj.id, days = math.ceil(inj.days) })
	end
	local gearCond = {}
	for k, v in pairs(profile.gear.cond) do
		gearCond[k] = math.floor(v)
	end
	local gymCond = {}
	for k, v in pairs(profile.gym.cond) do
		gymCond[k] = math.floor(v)
	end
	local style = Config.FindById(Config.Styles, profile.style)
	local wi = Training.WeighIn(profile)
	-- training records per activity: best / last session quality, session count, best numbers
	local records = {}
	if type(profile.records) == "table" then
		for id, r in pairs(profile.records) do
			if type(id) == "string" and type(r) == "table" then
				records[id] = {
					best = r2(tonumber(r.best) or 0), last = r2(tonumber(r.last) or 0), sessions = tonumber(r.sessions) or 0,
					stats = type(r.stats) == "table" and table.clone(r.stats) or nil,
				}
			end
		end
	end
	return {
		created = true, retired = profile.retired, storeOk = storeOk,
		identity = profile.identity, appearance = profile.appearance, physical = profile.physical,
		style = style and style.name or profile.style, styleId = profile.style, specialty = profile.specialty,
		stats = stats, mental = mental, overall = profile.overall, money = profile.money,
		popularity = math.floor(profile.popularity), day = profile.day, tier = profile.tier,
		tierName = Config.Tiers[profile.tier].name, record = profile.record, amateurRecord = profile.amateurRecord,
		belts = profile.belts, regional = profile.regional, defenses = profile.defenses, titlesWon = profile.titlesWon,
		owned = profile.owned, camp = camp, ranks = ranks, bestRank = best < 999 and best or nil, bestOrg = bestOrg,
		history = hist, pastCareers = profile.pastCareers, final = profile.final,
		className = Config.WeightClasses[profile.physical.weightClass].name,
		body = body, physique = Training.Physique(profile), weight = r2(wi.weight), weightLimit = wi.limit, overWeight = r2(wi.over),
		condition = {
			energy = math.floor(c.energy), hydration = math.floor(c.hydration), nutrition = math.floor(c.nutrition),
			fatigue = math.floor(c.fatigue), sleepQ = r2(c.sleepQ or 0.8), injuries = injuries,
			buffs = c.buffs, flexible = c.flexible, water = r2(c.water or 0),
		},
		gym = { levels = profile.gym.levels, cond = gymCond },
		gear = { owned = profile.gear.owned, equipped = profile.gear.equipped, cond = gearCond },
		coaches = profile.coaches, salary = Training.TeamSalary(profile), sessions = profile.sessions or 0,
		records = records,
	}
end

return Career
