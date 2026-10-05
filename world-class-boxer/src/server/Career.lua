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
	return type(profile.owned) == "table" and profile.owned[id] == true
end

-- the player's best home (Mansion > House > Apartment) or nil; homes are Catalog.Shop "Houses"
Career.HomeOrder = { "Mansion", "House", "Apartment" }
function Career.HomeOf(profile)
	for _, id in ipairs(Career.HomeOrder) do
		if Career.Owned(profile, id) then
			return id
		end
	end
	return nil
end

-- pcall wrapper for the Training calls the look / fight hand-off makes: one bad save value must
-- never stop applyLook (it runs outside its own pcall) or a fight from starting
local function safe(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	warn("[Career] " .. tostring(res))
	return nil
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
	-- home add-ons need somewhere to put them
	if type(item.requiresAny) == "table" then
		local has = false
		for _, need in ipairs(item.requiresAny) do
			if Career.Owned(profile, need) then
				has = true
			end
		end
		if not has then
			local names = {}
			for _, need in ipairs(item.requiresAny) do
				local def = Catalog.Find(Catalog.Shop, need)
				table.insert(names, def and def.name or need)
			end
			return false, "You need a home first: " .. table.concat(names, " / ") .. "."
		end
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
-- Sponsors: real deals with fictional brands (Catalog.Sponsors). One deal per slot
-- (trunks | robe | corner | gear); each pays per fight plus win / KO bonuses for a set number
-- of fights. Saved lazily as profile.sponsors = { deals = { [slot] = { id, fightsLeft, signedDay } },
-- signed = { [id] = true } } (signed: first-time signing bonus and popularity only once per brand).
------------------------------------------------------------------------
-- share of the old popularity formula paid as merch / appearance fees while you have NO deal
local ENDORSE_SHARE = 0.5

local function sponsorState(profile)
	local s = profile.sponsors
	if type(s) ~= "table" then
		s = {}
		profile.sponsors = s
	end
	if type(s.deals) ~= "table" then
		s.deals = {}
	end
	if type(s.signed) ~= "table" then
		s.signed = {}
	end
	-- drop corrupt or unknown deals (a sponsor removed from the catalog, a wrong slot, NaN fights)
	for slot, d in pairs(s.deals) do
		local def = type(d) == "table" and Catalog.Sponsor(d.id)
		local left = def and tonumber(d.fightsLeft)
		if not def or def.slot ~= slot or not left or left ~= left or left <= 0 then
			s.deals[slot] = nil
		else
			d.fightsLeft = clamp(math.floor(left), 1, 99)
			d.signedDay = tonumber(d.signedDay) or 1
		end
	end
	return s
end

-- { [slot] = sponsor id } of the running deals (Venues.New opts.sponsors, LookOpts patches)
function Career.ActiveSponsors(profile)
	local out = {}
	if type(profile) ~= "table" or not profile.created then
		return out
	end
	for slot, d in pairs(sponsorState(profile).deals) do
		out[slot] = d.id
	end
	return out
end

local function logoOf(def)
	local l = def and def.logo
	if type(l) ~= "table" then
		return nil
	end
	return { text = l.text, glyph = l.glyph, fg = l.fg, bg = l.bg }
end

local function sponsorView(def)
	return {
		id = def.id, name = def.name, scope = def.scope, slot = def.slot, perFight = def.perFight, winBonus = def.winBonus,
		koBonus = def.koBonus, fights = def.fights, minTier = def.minTier, minPop = def.minPop, logo = logoOf(def), shop = def.shop,
	}
end

-- deals the career qualifies for that are not running; `taken` names the deal already in that slot
function Career.SponsorOffers(profile)
	local s = sponsorState(profile)
	local active = {}
	for _, d in pairs(s.deals) do
		active[d.id] = true
	end
	local out = {}
	for _, def in ipairs(Catalog.SponsorsFor(profile.tier, profile.popularity)) do
		if not active[def.id] then
			local v = sponsorView(def)
			local cur = s.deals[def.slot]
			local curDef = cur and Catalog.Sponsor(cur.id)
			v.taken = curDef and curDef.name or nil
			v.signingBonus = not s.signed[def.id] and math.floor(def.perFight * 0.5) or 0
			table.insert(out, v)
		end
	end
	return out
end

-- sign a deal; replace = true swaps out whatever runs in that slot. -> ok, err | name
function Career.SignSponsor(profile, id, replace)
	if profile.retired then
		return false, "You're retired."
	end
	local def = Catalog.Sponsor(id)
	if not def then
		return false, "Unknown sponsor"
	end
	local eligible = false
	for _, e in ipairs(Catalog.SponsorsFor(profile.tier, profile.popularity)) do
		if e.id == def.id then
			eligible = true
		end
	end
	if not eligible then
		return false, string.format("%s wants a bigger name: %s and %d popularity.", def.name,
			Config.Tiers[def.minTier] and Config.Tiers[def.minTier].name or ("tier " .. def.minTier), def.minPop)
	end
	local s = sponsorState(profile)
	local cur = s.deals[def.slot]
	if cur and cur.id == def.id then
		return false, "Already signed."
	end
	if cur and replace ~= true then
		local curDef = Catalog.Sponsor(cur.id)
		return false, string.format("Your %s slot already carries %s.", def.slot, curDef and curDef.name or cur.id)
	end
	s.deals[def.slot] = { id = def.id, fightsLeft = def.fights, signedDay = profile.day }
	-- a brand's first deal: signing bonus and a popularity bump from the announcement
	if not s.signed[def.id] then
		s.signed[def.id] = true
		profile.money += math.floor(def.perFight * 0.5)
		profile.popularity = clamp(profile.popularity + 1, 0, 100)
	end
	return true, def.name
end

-- end a deal early (slot name or sponsor id)
function Career.DropSponsor(profile, key)
	local s = sponsorState(profile)
	for slot, d in pairs(s.deals) do
		if slot == key or d.id == key then
			s.deals[slot] = nil
			local def = Catalog.Sponsor(d.id)
			return true, def and def.name or d.id
		end
	end
	return false, "No such deal."
end

-- fight-night pay from every running deal; counts the contracts down. -> total, notes
function Career.SponsorIncome(profile, win, isKO)
	local s = sponsorState(profile)
	local total, notes, names = 0, {}, {}
	for _, slot in ipairs(Catalog.SponsorSlots) do
		local d = s.deals[slot]
		local def = d and Catalog.Sponsor(d.id)
		if def then
			local pay = def.perFight + (win and def.winBonus or 0) + ((win and isKO) and def.koBonus or 0)
			total += pay
			table.insert(names, def.name)
			d.fightsLeft -= 1
			if d.fightsLeft <= 0 then
				s.deals[slot] = nil
				table.insert(notes, string.format("Your %s deal is complete. Sign a new one in the Sponsors tab.", def.name))
			end
		end
	end
	if #names > 0 then
		table.insert(notes, 1, string.format("Sponsors (%s) paid %s.", table.concat(names, ", "), Config.Money(total)))
	end
	return total, notes
end

-- autograph session with the fans outside (once per day, small popularity bump)
function Career.Autograph(profile)
	if profile.lastAutographDay == profile.day then
		return false, "You already signed for the fans today."
	end
	if (profile.popularity or 0) < 3 then
		return false, "Nobody's asking for your autograph yet. Win some fights!"
	end
	profile.lastAutographDay = profile.day
	profile.popularity = clamp(profile.popularity + 0.2, 0, 100)
	return true
end

-- where the boxer wakes up after sleeping: "here" (default), "home" (bedroom) or "gym"
function Career.SetWakeAt(profile, where)
	if where ~= "home" and where ~= "gym" and where ~= "here" then
		return false, "Unknown place"
	end
	if where == "home" and not Career.HomeOf(profile) then
		return false, "Buy a home first."
	end
	if type(profile.settings) ~= "table" then
		profile.settings = {}
	end
	profile.settings.wakeAt = where ~= "here" and where or nil
	return true
end

------------------------------------------------------------------------
-- Fighters for the fight engine
------------------------------------------------------------------------
function Career.GearView(profile)
	local g = profile.gear
	local eq = g.equipped or {}
	return {
		gloves = eq.gloves, glovesCond = Training.GearCondition(profile, "gloves"),
		wraps = eq.wraps, wrapsCond = Training.GearCondition(profile, "wraps"),
		shoes = eq.shoes, shoesCond = Training.GearCondition(profile, "shoes"),
		mouthguard = eq.mouthguard, robe = eq.robe,
	}
end

-- a running deal's patch for Builder (opts.sponsorTrunks / sponsorRobe = { text, fg, bg })
local function sponsorPatch(profile, slot)
	local s = profile.sponsors
	local d = type(s) == "table" and type(s.deals) == "table" and s.deals[slot]
	local def = type(d) == "table" and Catalog.Sponsor(d.id)
	local l = def and def.logo
	if type(l) ~= "table" then
		return nil
	end
	return { text = l.text, fg = l.fg, bg = l.bg }
end

function Career.LookOpts(profile, extra)
	local o = {
		name = profile.identity.name, nick = profile.identity.nickname, nat = profile.identity.nationality,
		waistText = profile.identity.nickname, robe = profile.gear.equipped.robe,
		age = profile.identity.age, tier = profile.tier,
		sponsorTrunks = sponsorPatch(profile, "trunks"), sponsorRobe = sponsorPatch(profile, "robe"),
	}
	-- one physique source of truth (Hub badge == rendered body), residual fight damage
	local info = safe(Training.PhysiqueInfo, profile)
	o.physique = type(info) == "table" and info.id or nil
	o.damage = safe(Training.FaceView, profile)
	-- a hard weight cut (negative water) dries the physique out
	local water = type(profile.condition) == "table" and tonumber(profile.condition.water) or 0
	if water and water == water and water < 0 then
		o.dry = clamp(-water / 5, 0, 1)
	end
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
	local cond = profile.condition or {}
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
		-- damage persistence (section 8.5): the residual face, career head trauma, an open cut, a concussion
		face = safe(Training.FaceView, profile), trauma = tonumber(cond.trauma) or 0,
		injuryCut = safe(Training.HasInjury, profile, "cut") == true,
		concussed = safe(Training.HasInjury, profile, "concussion") == true,
		age = profile.identity.age,
	}
end

function Career.FighterFromBoxer(b)
	local app, build, gear = World.Look(b)
	-- the same build bonuses players get (FightEngine folds mods.chinAdd into Chin once for AI fighters)
	local mods = safe(Training.FightModifiersFromBuild, build) or {}
	return {
		isPlayer = false, id = b.id, name = b.name, nick = b.nick, stats = table.clone(b.stats),
		mental = table.clone(b.mental), style = b.style, archetype = b.archetype, class = b.class,
		reach = (b.height or 70) + (#b.name % 5), height = b.height or 70, app = app, build = build, gear = gear,
		fatigue = 0, record = b.record, nat = b.nat, personality = b.personality,
		learned = table.clone(b.learned or {}), h2h = b.h2h, mods = mods, age = b.age,
		lookOpts = { name = b.name, nick = b.nick, nat = b.nat, waistText = b.nick, robe = "Classic", age = b.age },
	}
end

------------------------------------------------------------------------
-- Simulated fight (for players who want to skip a bout)
------------------------------------------------------------------------
-- A simulated fight has no punch-by-punch face model: turn the damage taken (and knockdowns
-- suffered) into the same dmg table a live fight returns (CONTRACTS section 8), so skipped fights
-- still leave a black eye, a cut or a broken nose that heals over the next days.
function Career.SimFace(damage, kdAgainst, r)
	r = r or rng
	local k = clamp((tonumber(damage) or 0) / 140 + (tonumber(kdAgainst) or 0) * 0.12, 0, 1)
	if k < 0.06 then
		return nil
	end
	local function v(lo, hi)
		return clamp(k * r:NextNumber(lo, hi), 0, 1)
	end
	local face = {
		leftEye = v(0.3, 1.1), rightEye = v(0.3, 1.1), bruise = v(0.6, 1.1), lip = v(0.2, 0.8),
		cheekL = v(0.2, 0.9), cheekR = v(0.2, 0.9), forehead = v(0, 0.6), redness = clamp(k * 1.3, 0, 1),
		noseBleed = k > 0.35 and v(0.4, 1) or 0, earL = v(0, 0.4), earR = v(0, 0.4), age = 0,
	}
	if k > 0.4 and r:NextNumber() < k then
		face.cut = clamp(k * r:NextNumber(0.5, 1.15), 0, 1.2)
		face.cutSide = r:NextNumber() < 0.5 and -1 or 1
	end
	if k > 0.8 and r:NextNumber() < 0.3 then
		face.cut2 = clamp(k * r:NextNumber(0.3, 0.8), 0, 1.2)
		face.cutSide2 = -(face.cutSide or 1)
	end
	if k > 0.7 and r:NextNumber() < 0.2 then
		face.nose = true
	end
	return face
end

function Career.SimFight(profile, offer)
	local function withFace(res)
		res.face = Career.SimFace(res.damageTaken, res.kdAgainst)
		res.noseBroken = res.face ~= nil and res.face.nose == true
		return res
	end
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
			return withFace({ outcome = "win", method = rng:NextNumber() < 0.5 and "KO" or "TKO", round = r, cards = cards,
				kdFor = kdFor, kdAgainst = kdAg, landed = landed, oppLanded = oLanded, punches = punches, simulated = true, damageTaken = pDmg })
		elseif kdAg >= 2 and pDmg > 70 or kdAg >= 3 then
			return withFace({ outcome = "loss", method = rng:NextNumber() < 0.5 and "KO" or "TKO", round = r, cards = cards,
				kdFor = kdFor, kdAgainst = kdAg, landed = landed, oppLanded = oLanded, punches = punches, simulated = true, damageTaken = pDmg })
		end
	end
	local res = Career.DecideCards(cards)
	res.round = offer.rounds
	res.cards = cards
	res.kdFor, res.kdAgainst, res.landed, res.oppLanded = kdFor, kdAg, landed, oLanded
	res.punches = punches
	res.simulated = true
	res.damageTaken = pDmg
	return withFace(res)
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
	-- sponsors are real deals now (Career.SponsorIncome) and their income REPLACES the old popularity
	-- formula (CONTRACTS s.16 H). Only a career with no deal at all still gets half of that formula as
	-- unsigned merch & appearance fees (the gap map's fallback), so not signing never pays more than
	-- signing: at tier 3+ even the smallest local deal outpays it within a few fights.
	local hadDeals = next(sponsorState(profile).deals) ~= nil -- before SponsorIncome expires any
	local sponsor, sponsorNotes = Career.SponsorIncome(profile, win, isKO)
	local endorse = 0
	if not hadDeals and profile.tier >= 3 and profile.popularity >= 5 then
		endorse = round((profile.popularity ^ 1.4) * 35 * profile.tier * ENDORSE_SHARE)
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
	local total = purse + sponsor + endorse + tv - salary - fine
	profile.money += total
	table.insert(notes, string.format("Purse %s  Sponsors %s  Endorsements %s  TV %s  Team salaries -%s", Config.Money(purse), Config.Money(sponsor),
		Config.Money(endorse), Config.Money(tv), Config.Money(salary)))
	for _, n in ipairs(sponsorNotes) do
		table.insert(notes, n)
	end

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
	elseif nBelts > 0 and (profile.tier < 8 or (nBelts < 4 and profile.tier >= 9)) then
		profile.tier = 8
	elseif nBelts == 0 and profile.tier >= 8 then
		profile.tier = 7
		table.insert(notes, "You're a former champion. Climb back to a title shot.")
	end

	-- time passes: medical suspension / recovery
	local suspension = 21
	if loss and isKO then
		suspension = 45
	elseif loss or (res.kdAgainst or 0) > 0 then
		suspension = 28
	end
	for _, n in ipairs(Training.PassDays(profile, suspension)) do
		table.insert(notes, n)
	end
	-- fight damage persists (CONTRACTS 8.3): what is left after the suspension heals over the next
	-- days; head trauma accumulates and a bad concussion / broken nose becomes an injury
	safe(Training.AddFaceDamage, profile, res.face, Config.FaceDamage.postFightCarry)
	for _, n in ipairs(safe(Training.AddTrauma, profile, res) or {}) do
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
local function legacyParts(profile)
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
	return parts, math.max(0, round(score))
end

-- where a legacy score ranks among the all-time greats (1 = the GOAT)
local function goatRank(score)
	local rank = 1
	for _, e in ipairs(Config.Legends) do
		if e.score > score then
			rank += 1
		end
	end
	return rank
end

function Career.Legacy(profile)
	local parts, score = legacyParts(profile)
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

-- residual face damage for the Hub: { stage 0..4, label, days until it reads as fresh } or nil
local function faceSummary(profile)
	local f = safe(Training.FaceView, profile)
	if type(f) ~= "table" then
		return nil
	end
	local FD = Config.FaceDamage
	local stage, def = Config.FaceDamageStage(f)
	-- the slowest field at its daily heal rate decides when the face is clean again
	local days = 0
	for _, k in ipairs(FD.fields) do
		local v, rule = tonumber(f[k]), FD.heal[k]
		if v and v > FD.clearBelow and rule then
			local d = 1
			if rule.sub and rule.sub > 0 then
				d = math.ceil((v - FD.clearBelow) / rule.sub)
			elseif rule.mul and rule.mul > 0 and rule.mul < 1 then
				d = math.ceil(math.log(FD.clearBelow / v) / math.log(rule.mul))
			end
			days = math.max(days, d)
		end
	end
	return {
		stage = stage, label = def and def.label or "", days = days, nose = f.nose == true,
		cut = math.max(tonumber(f.cut) or 0, tonumber(f.cut2) or 0) > 0.05,
		eyes = math.max(tonumber(f.leftEye) or 0, tonumber(f.rightEye) or 0),
	}
end

-- derived gym facility tier (CONTRACTS section 9): never saved
local function gymTierSummary(profile)
	local ok, idx, def, frac, needs = pcall(Catalog.GymTier, profile.gym and profile.gym.levels, profile.owned, profile.tier)
	if not ok or type(def) ~= "table" then
		return { index = 1, id = "Beginner", name = "Beginner Gym", frac = 0, needs = {} }
	end
	local nextDef = Config.GymTiers[idx + 1]
	return {
		index = idx, id = def.id, name = def.name, desc = def.desc, growth = def.growth, frac = r2(frac or 0),
		needs = needs or {}, nextName = nextDef and nextDef.name or nil,
	}
end

local function sponsorSummary(profile)
	local s = sponsorState(profile)
	local deals = {}
	for slot, d in pairs(s.deals) do
		local def = Catalog.Sponsor(d.id)
		if def then
			local v = sponsorView(def)
			v.fightsLeft, v.signedDay = d.fightsLeft, d.signedDay
			deals[slot] = v
		end
	end
	return { deals = deals, offers = Career.SponsorOffers(profile) }
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
	local physique = safe(Training.PhysiqueInfo, profile) or { id = "Balanced", name = Training.Physique(profile), desc = "" }
	local sore = {}
	for grp, v in pairs(type(c.sore) == "table" and c.sore or {}) do
		v = tonumber(v)
		if type(grp) == "string" and v and v == v and v > 0.01 then
			sore[grp] = r2(math.clamp(v, 0, 1))
		end
	end
	local _, lgScore = legacyParts(profile)
	local trauma = tonumber(c.trauma) or 0
	trauma = trauma == trauma and math.floor(math.clamp(trauma, 0, 100)) or 0
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
		body = body, physique = Training.Physique(profile), physiqueId = physique.id, physiqueDesc = physique.desc,
		physiquePinned = physique.pinned == true,
		weight = r2(wi.weight), weightLimit = wi.limit, overWeight = r2(wi.over),
		condition = {
			energy = math.floor(c.energy), hydration = math.floor(c.hydration), nutrition = math.floor(c.nutrition),
			fatigue = math.floor(c.fatigue), sleepQ = r2(c.sleepQ or 0.8), injuries = injuries,
			buffs = c.buffs, flexible = c.flexible, water = r2(c.water or 0),
			sore = sore, trauma = trauma, face = faceSummary(profile),
		},
		gym = { levels = profile.gym.levels, cond = gymCond },
		gymTier = gymTierSummary(profile),
		gear = { owned = profile.gear.owned, equipped = profile.gear.equipped, cond = gearCond },
		coaches = profile.coaches, salary = Training.TeamSalary(profile), sessions = profile.sessions or 0,
		records = records,
		-- city & career immersion (Hub Life / Sponsors tabs, CityVisuals)
		home = Career.HomeOf(profile), sponsors = sponsorSummary(profile),
		legacy = { score = lgScore, hof = lgScore >= Config.HallOfFameScore, goatRank = goatRank(lgScore) },
		settings = { wakeAt = type(profile.settings) == "table" and profile.settings.wakeAt or nil },
		autographReady = profile.lastAutographDay ~= profile.day and (profile.popularity or 0) >= 3,
		lastFightDay = tonumber(profile.lastFightDay),
	}
end

return Career
