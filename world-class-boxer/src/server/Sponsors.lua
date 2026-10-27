-- Sponsors: brand deals with fictional brands (Shared Catalog.Sponsors), server-authoritative.
--   * offers: a short list of brands that want you, rolled weighted-random from the brands your career
--     qualifies for (scope Local -> Regional -> National -> Global by tier, popularity, pro wins and
--     ranking). Each offer has negotiated money (mult 0.85..1.2) and expires after a few fights; after
--     every fight the list counts down, drops what expired and is topped up again. A declined or dropped
--     brand stays away for a few fights.
--   * deals: one per slot (trunks | robe | corner | gear) and one per category (the exclusivity clause:
--     two energy drinks can never both be signed). A deal pays a signing bonus once per brand, then per
--     fight with win / KO / title-fight bonuses, for its contract length in fights. Clauses: a social
--     post per fight (post), the logo seen (wear = "robe" | "gloves"), a performance clause (maxLosses
--     straight losses and the brand walks). Perks while a deal runs: training XP, morning energy, gear /
--     meal discounts, fan growth from wins (Sponsors.Perk; Training and Career read them).
-- Saved as profile.sponsors = {
--   v = 2, seed, rolls, fights (fights seen),
--   deals = { [slot] = { id, fightsLeft, signedDay, mult, losses, strikes, posted, earned } },
--   signed = { [id] = true }  (signing bonus + announcement only once per brand),
--   offers = { { id, left, mult } } | nil (nil: never rolled; the next summary rolls them),
--   cool = { [id] = fight number the brand comes back after },
-- }
-- A v1 save ({ deals = { [slot] = { id, fightsLeft, signedDay } }, signed }) migrates in place (Sponsors.State).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local Sponsors = {}

Sponsors.VERSION = 2
Sponsors.MAX_OFFERS = 3 -- (+1 once National brands are interested)
Sponsors.DECLINE_COOL = 3 -- fights a declined brand stays away
Sponsors.DROP_COOL = 4 -- fights a brand that dropped you (or you dropped) stays away
Sponsors.MISSED = 0.5 -- share of the base pay a fight keeps when a post or the logo was missing
Sponsors.STRIKES = 2 -- missed posts that end a deal
Sponsors.POST_FAME = 0.3
Sponsors.PERK_CAP = { xp = 0.3, recovery = 20, discount = 0.4, fans = 0.6 }
Sponsors.TITLE_KINDS = { ["Regional Title"] = true, ["National Title"] = true, ["World Title"] = true, ["Unification"] = true, ["Title Defense"] = true }

local function finite(v, default)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

local function round(n)
	return math.floor(n + 0.5)
end

local function money(n)
	return Config.Money and Config.Money(n) or ("$" .. tostring(n))
end

------------------------------------------------------------------------
-- State (and the save migration)
------------------------------------------------------------------------
-- profile.sponsors, created and cleaned: unknown brands, wrong slots, NaN numbers and stray entries
-- are dropped; a v1 save's deals get the v2 fields. Idempotent.
function Sponsors.State(profile)
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
	if type(s.cool) ~= "table" then
		s.cool = {}
	end
	s.fights = math.max(0, math.floor(finite(s.fights, 0)))
	s.rolls = math.max(0, math.floor(finite(s.rolls, 0)))
	if finite(s.seed, nil) == nil then
		s.seed = Random.new():NextInteger(1, 2 ^ 30)
	end
	s.seed = math.floor(s.seed)
	for slot, d in pairs(s.deals) do
		local def = type(d) == "table" and Catalog.Sponsor(d.id)
		local left = def and finite(d.fightsLeft, nil)
		if type(slot) ~= "string" or not def or def.slot ~= slot or not left or left <= 0 then
			s.deals[slot] = nil
		else
			d.fightsLeft = math.clamp(math.floor(left), 1, 99)
			d.signedDay = finite(d.signedDay, 1)
			d.mult = math.clamp(finite(d.mult, 1), 0.5, 2)
			d.losses = math.clamp(math.floor(finite(d.losses, 0)), 0, 99)
			d.strikes = math.clamp(math.floor(finite(d.strikes, 0)), 0, 99)
			d.posted = d.posted == true
			d.earned = math.max(0, math.floor(finite(d.earned, 0)))
		end
	end
	-- a save from before the exclusivity clause may carry two brands of one category: keep the first slot's
	local cats = {}
	for _, slot in ipairs(Catalog.SponsorSlots) do
		local d = s.deals[slot]
		local def = d and Catalog.Sponsor(d.id)
		if def and def.cat then
			if cats[def.cat] then
				s.deals[slot] = nil
			else
				cats[def.cat] = true
			end
		end
	end
	for id, v in pairs(s.signed) do
		if type(id) ~= "string" or v ~= true then
			s.signed[id] = nil
		end
	end
	for id, v in pairs(s.cool) do
		if not Catalog.Sponsor(id) or finite(v, nil) == nil then
			s.cool[id] = nil
		end
	end
	if s.offers ~= nil then
		if type(s.offers) ~= "table" then
			s.offers = nil
		else
			local clean, seen = {}, {}
			for _, o in ipairs(s.offers) do
				local def = type(o) == "table" and Catalog.Sponsor(o.id)
				if def and not seen[def.id] and finite(o.left, 0) >= 1 then
					seen[def.id] = true
					table.insert(clean, { id = def.id, left = math.clamp(math.floor(o.left), 1, 9), mult = math.clamp(finite(o.mult, 1), 0.5, 2) })
				end
			end
			s.offers = clean
		end
	end
	s.v = Sponsors.VERSION
	return s
end

-- the save migration (Training.Migrate calls it): the state cleaned / brought to v2
function Sponsors.Migrate(profile)
	if type(profile) == "table" and profile.created then
		Sponsors.State(profile)
	end
	return profile
end

-- what the brands see of the career; bestRank from World.BestRank (999 = unranked); a champion counts as #1
function Sponsors.Ctx(profile, bestRank)
	local rec = type(profile.record) == "table" and profile.record or {}
	local rank = finite(bestRank, 999)
	if finite(profile.tier, 1) >= 8 then
		rank = 1
	end
	return { tier = finite(profile.tier, 1), pop = finite(profile.popularity, 0), wins = finite(rec.w, 0), rank = rank }
end

local function activeIds(s)
	local out = {}
	for _, d in pairs(s.deals) do
		out[d.id] = true
	end
	return out
end

-- the running deal whose category the brand shares (the exclusivity clause) -> slot, deal, def
local function conflictOf(s, def)
	for _, slot in ipairs(Catalog.SponsorSlots) do
		local d = s.deals[slot]
		local cur = d and Catalog.Sponsor(d.id)
		if cur and Catalog.SponsorConflict(cur, def) then
			return slot, d, cur
		end
	end
	return nil
end

local function offerIndex(s, id)
	for i, o in ipairs(s.offers or {}) do
		if o.id == id then
			return i, o
		end
	end
	return nil
end

-- highest scope order the career has unlocked (0 = none yet)
local function topScope(ctx)
	local top = 0
	for _, id in ipairs(Catalog.SponsorScopeOrder) do
		local sc = Catalog.SponsorScopes[id]
		local ok = ctx.tier >= (sc.minTier or 1) and ctx.pop >= (sc.minPop or 0) and ctx.wins >= (sc.minWins or 0)
			and (not sc.minRank or ctx.rank <= sc.minRank)
		if ok then
			top = math.max(top, sc.order)
		end
	end
	return top
end

------------------------------------------------------------------------
-- Offers: weighted random, refreshed after each fight
------------------------------------------------------------------------
-- top the offer list up from the brands that want you (tick = a fight was just fought: every offer counts
-- down and the expired ones go). rng optional (a Random); default: the career's own seeded stream.
-- -> the new offers' names, the expired offers' names
function Sponsors.Refresh(profile, ctx, tick, rng)
	local s = Sponsors.State(profile)
	ctx = ctx or Sponsors.Ctx(profile)
	s.offers = s.offers or {}
	local active = activeIds(s)
	local expired = {}
	for i = #s.offers, 1, -1 do
		local o = s.offers[i]
		local def = Catalog.Sponsor(o.id)
		if tick then
			o.left -= 1
		end
		if o.left <= 0 or active[o.id] or not Catalog.SponsorEligible(def, ctx) then
			if o.left <= 0 and def then
				table.insert(expired, def.name)
			end
			table.remove(s.offers, i)
		end
	end
	if profile.retired then
		return {}, expired
	end
	local top = topScope(ctx)
	local target = Sponsors.MAX_OFFERS + (top >= 3 and 1 or 0)
	if #s.offers >= target then
		return {}, expired
	end
	if not rng then
		s.rolls += 1
		rng = Random.new(s.seed + s.rolls * 7919)
	end
	local pool, total = {}, 0
	for _, def in ipairs(Catalog.Sponsors) do
		local order = (Catalog.SponsorScopes[def.scope] or Catalog.SponsorScopes.Local).order
		local cooled = (s.cool[def.id] or -1) > s.fights
		if not active[def.id] and not offerIndex(s, def.id) and not cooled and Catalog.SponsorEligible(def, ctx) then
			-- the career's own level is who calls most; the small fry still ring now and then
			local w = (def.weight or 1) * (order == top and 2.5 or (order == top - 1 and 0.6 or 0.25))
			table.insert(pool, { def = def, w = w })
			total += w
		end
	end
	local added = {}
	while #s.offers < target and #pool > 0 do
		local r = rng:NextNumber() * total
		local pick = #pool
		for i, e in ipairs(pool) do
			r -= e.w
			if r <= 0 then
				pick = i
				break
			end
		end
		local e = table.remove(pool, pick)
		total -= e.w
		local sc = Catalog.SponsorScopes[e.def.scope] or Catalog.SponsorScopes.Local
		table.insert(s.offers, {
			id = e.def.id, left = (sc.offerFights or 2) + rng:NextInteger(0, 1),
			mult = math.floor((0.85 + rng:NextNumber() * 0.35) * 100 + 0.5) / 100,
		})
		table.insert(added, e.def.name)
	end
	return added, expired
end

------------------------------------------------------------------------
-- Clauses and perks
------------------------------------------------------------------------
-- is the logo seen? (wear = "robe": a robe on the ring walk; "gloves": fighting in the brand's gloves)
function Sponsors.WearOk(profile, def)
	if type(def) ~= "table" or not def.wear then
		return true
	end
	local gear = type(profile.gear) == "table" and profile.gear or {}
	local eq = type(gear.equipped) == "table" and gear.equipped or {}
	if def.wear == "robe" then
		return type(eq.robe) == "string" and eq.robe ~= "None"
	elseif def.wear == "gloves" then
		local app = type(profile.appearance) == "table" and profile.appearance or {}
		local override = type(app.gloves) == "table" and app.gloves.brand or nil
		local ok, brand = pcall(Catalog.GearBrand, "gloves", eq.gloves, override)
		return ok and type(brand) == "table" and brand.id == def.gloveBrand
	end
	return true
end

-- the perks of every running deal, summed and capped (kind = xp | recovery | discount | fans; on = gear |
-- meals for a discount)
function Sponsors.Perk(profile, kind, on)
	local s = type(profile) == "table" and profile.sponsors
	if type(s) ~= "table" or type(s.deals) ~= "table" then
		return 0
	end
	local total = 0
	for _, d in pairs(s.deals) do
		local def = type(d) == "table" and Catalog.Sponsor(d.id)
		local p = def and def.perk
		if p and p.kind == kind and (on == nil or p.on == nil or p.on == on) then
			total += finite(p.amount, 0)
		end
	end
	return math.clamp(total, 0, Sponsors.PERK_CAP[kind] or 1)
end

-- a price with the running deals' discount on it (on = gear | meals)
function Sponsors.Price(profile, price, on)
	price = finite(price, 0)
	if price <= 0 then
		return price
	end
	return round(price * (1 - Sponsors.Perk(profile, "discount", on)))
end

function Sponsors.PerkText(p)
	if type(p) ~= "table" then
		return nil
	end
	if p.kind == "xp" then
		return string.format("+%d%% training XP", round(p.amount * 100))
	elseif p.kind == "recovery" then
		return string.format("+%d morning energy", round(p.amount))
	elseif p.kind == "discount" then
		return string.format("%d%% off %s", round(p.amount * 100), p.on == "meals" and "meals" or "gear")
	elseif p.kind == "fans" then
		return string.format("+%d%% fan growth from wins", round(p.amount * 100))
	end
	return nil
end

------------------------------------------------------------------------
-- Sign / decline / drop / post (validated: the Request handlers pass client input straight in)
------------------------------------------------------------------------
-- sign an offer on the table. replace = true also ends what blocks it (the slot's deal, a brand of the same
-- category). -> ok, err | name
function Sponsors.Sign(profile, id, replace, ctx)
	if profile.retired then
		return false, "You're retired."
	end
	local def = Catalog.Sponsor(id)
	if not def then
		return false, "Unknown sponsor"
	end
	local s = Sponsors.State(profile)
	local cur = s.deals[def.slot]
	if cur and cur.id == def.id then
		return false, "Already signed."
	end
	local i, offer = offerIndex(s, def.id)
	if not i then
		return false, def.name .. " has no offer on the table."
	end
	ctx = ctx or Sponsors.Ctx(profile)
	local ok, missing = Catalog.SponsorEligible(def, ctx)
	if not ok then
		return false, string.format("%s wants a bigger name: %s.", def.name, tostring(missing))
	end
	local cSlot, _, cDef = conflictOf(s, def)
	if replace ~= true then
		if cDef then
			return false, string.format("Exclusivity: you already rep %s (%s).", cDef.name, (Catalog.SponsorCats[def.cat] or def.cat):lower())
		end
		if cur then
			local curDef = Catalog.Sponsor(cur.id)
			return false, string.format("Your %s slot already carries %s.", def.slot, curDef and curDef.name or cur.id)
		end
	end
	-- the brands that make way (a dropped brand stays away a while)
	for _, slot in ipairs({ def.slot, cSlot }) do
		local d = slot and s.deals[slot]
		if d then
			s.cool[d.id] = s.fights + Sponsors.DROP_COOL
			s.deals[slot] = nil
		end
	end
	s.deals[def.slot] = {
		id = def.id, fightsLeft = def.fights, signedDay = profile.day, mult = offer.mult,
		losses = 0, strikes = 0, posted = false, earned = 0,
	}
	table.remove(s.offers, i)
	-- a brand's first deal: signing bonus and a popularity bump from the announcement
	if not s.signed[def.id] then
		s.signed[def.id] = true
		local bonus = round((def.signing or 0) * offer.mult)
		profile.money += bonus
		s.deals[def.slot].earned = bonus
		profile.popularity = math.clamp(finite(profile.popularity, 0) + 1, 0, 100)
	end
	return true, def.name
end

-- turn an offer down: it goes, and the brand stays away a few fights
function Sponsors.Decline(profile, id)
	local s = Sponsors.State(profile)
	local i = type(id) == "string" and offerIndex(s, id)
	if not i then
		return false, "No such offer."
	end
	table.remove(s.offers, i)
	s.cool[id] = s.fights + Sponsors.DECLINE_COOL
	local def = Catalog.Sponsor(id)
	return true, def and def.name or id
end

-- end a deal early (slot name or sponsor id)
function Sponsors.Drop(profile, key)
	local s = Sponsors.State(profile)
	for slot, d in pairs(s.deals) do
		if slot == key or d.id == key then
			s.deals[slot] = nil
			s.cool[d.id] = s.fights + Sponsors.DROP_COOL
			local def = Catalog.Sponsor(d.id)
			return true, def and def.name or d.id
		end
	end
	return false, "No such deal."
end

-- the social post a deal asks for before each fight (slot name or sponsor id): a little fame too
function Sponsors.Post(profile, key)
	local s = Sponsors.State(profile)
	for slot, d in pairs(s.deals) do
		if slot == key or d.id == key then
			local def = Catalog.Sponsor(d.id)
			if not (def and def.post) then
				return false, "This deal has no social posts."
			end
			if d.posted then
				return false, "Already posted for this fight."
			end
			d.posted = true
			profile.popularity = math.clamp(finite(profile.popularity, 0) + Sponsors.POST_FAME, 0, 100)
			return true, def.name
		end
	end
	return false, "No such deal."
end

------------------------------------------------------------------------
-- Fight night
------------------------------------------------------------------------
-- pay every running deal for a fight and run its clauses. fight = { win, loss, ko (a stoppage), title (a
-- title fight) }. -> total, notes, per-deal lines { name, pay }
function Sponsors.Payout(profile, fight)
	local s = Sponsors.State(profile)
	fight = type(fight) == "table" and fight or {}
	local win, loss = fight.win == true, fight.loss == true
	s.fights += 1
	local total, notes, names, lines = 0, {}, {}, {}
	for _, slot in ipairs(Catalog.SponsorSlots) do
		local d = s.deals[slot]
		local def = d and Catalog.Sponsor(d.id)
		if def then
			local mult = d.mult or 1
			local base = (def.perFight or 0) * mult
			if def.post and not d.posted then
				base *= Sponsors.MISSED
				d.strikes += 1
				table.insert(notes, string.format("%s: no social post before the fight (strike %d of %d), half the fee.", def.name, d.strikes, Sponsors.STRIKES))
			end
			if not Sponsors.WearOk(profile, def) then
				base *= Sponsors.MISSED
				table.insert(notes, string.format("%s: %s, half the fee.", def.name,
					def.wear == "robe" and "no robe on the walk-out, nobody saw the logo" or ("you didn't fight in " .. tostring(def.gloveBrand) .. " gloves")))
			end
			local bonus = 0
			if win then
				bonus += def.winBonus or 0
				if fight.ko then
					bonus += def.koBonus or 0
				end
				if fight.title then
					bonus += def.titleBonus or 0
				end
			end
			local pay = round(base + bonus * mult)
			total += pay
			d.earned += pay
			table.insert(names, def.name)
			table.insert(lines, { name = def.name, pay = pay })
			d.posted = false
			if loss then
				d.losses += 1
			elseif win then
				d.losses = 0
			end
			d.fightsLeft -= 1
			if def.maxLosses and d.losses >= def.maxLosses then
				s.deals[slot] = nil
				s.cool[def.id] = s.fights + Sponsors.DROP_COOL
				table.insert(notes, string.format("%s dropped you after %d straight losses (performance clause).", def.name, d.losses))
			elseif d.strikes >= Sponsors.STRIKES then
				s.deals[slot] = nil
				s.cool[def.id] = s.fights + Sponsors.DROP_COOL
				table.insert(notes, string.format("%s ended the deal: too many missed posts.", def.name))
			elseif d.fightsLeft <= 0 then
				s.deals[slot] = nil
				table.insert(notes, string.format("Your %s deal is complete. Sign a new one in the Sponsors tab.", def.name))
			end
		end
	end
	if #names > 0 then
		table.insert(notes, 1, string.format("Sponsors (%s) paid %s.", table.concat(names, ", "), money(total)))
	end
	return total, notes, lines
end

-- after the fight's result (and any promotion): offers count down, expire and are topped up -> notes
function Sponsors.AfterFight(profile, ctx, rng)
	local notes = {}
	local added, expired = Sponsors.Refresh(profile, ctx, true, rng)
	if #expired > 0 then
		table.insert(notes, "Offers expired: " .. table.concat(expired, ", ") .. ".")
	end
	if #added > 0 then
		table.insert(notes, "New sponsor interest: " .. table.concat(added, ", ") .. ". See the Sponsors tab.")
	end
	return notes
end

------------------------------------------------------------------------
-- Views (Career.Summary, Venues / Builder logos)
------------------------------------------------------------------------
-- { [slot] = sponsor id } of the running deals
function Sponsors.Active(profile)
	local out = {}
	if type(profile) ~= "table" or not profile.created then
		return out
	end
	for slot, d in pairs(Sponsors.State(profile).deals) do
		out[slot] = d.id
	end
	return out
end

-- a running deal's patch for Builder (opts.sponsorTrunks / sponsorRobe = { text, fg, bg })
function Sponsors.Patch(profile, slot)
	local s = profile.sponsors
	local d = type(s) == "table" and type(s.deals) == "table" and s.deals[slot]
	local def = type(d) == "table" and Catalog.Sponsor(d.id)
	local l = def and def.logo
	if type(l) ~= "table" then
		return nil
	end
	return { text = l.text, fg = l.fg, bg = l.bg }
end

local function logoOf(def)
	local l = def and def.logo
	if type(l) ~= "table" then
		return nil
	end
	return { text = l.text, glyph = l.glyph, fg = l.fg, bg = l.bg }
end

-- the terms as the Hub shows them (money already scaled by the negotiated mult)
function Sponsors.View(def, mult)
	mult = mult or 1
	local function m(v)
		return round((v or 0) * mult)
	end
	return {
		id = def.id, name = def.name, scope = def.scope, slot = def.slot, cat = def.cat, catName = Catalog.SponsorCats[def.cat],
		perFight = m(def.perFight), winBonus = m(def.winBonus), koBonus = m(def.koBonus), titleBonus = m(def.titleBonus),
		signing = m(def.signing), fights = def.fights, mult = mult, post = def.post == true, wear = def.wear, gloveBrand = def.gloveBrand,
		maxLosses = def.maxLosses, perk = def.perk and table.clone(def.perk) or nil, perkText = Sponsors.PerkText(def.perk),
		minTier = def.minTier, minPop = def.minPop, logo = logoOf(def), shop = def.shop,
	}
end

-- the offers as views; `taken` names the deal in that slot, `conflict` the brand of the same category
function Sponsors.OfferViews(profile)
	local s = Sponsors.State(profile)
	local out = {}
	for _, o in ipairs(s.offers or {}) do
		local def = Catalog.Sponsor(o.id)
		if def then
			local v = Sponsors.View(def, o.mult)
			local cur = s.deals[def.slot]
			local curDef = cur and Catalog.Sponsor(cur.id)
			v.taken = curDef and curDef.name or nil
			local _, _, cDef = conflictOf(s, def)
			v.conflict = cDef and cDef.name or nil
			v.left = o.left
			v.signingBonus = not s.signed[def.id] and v.signing or 0
			table.insert(out, v)
		end
	end
	return out
end

-- the Hub's Sponsors tab: deals, offers (rolled now on a save that never had any), perks in force
function Sponsors.Summary(profile, ctx)
	local s = Sponsors.State(profile)
	if s.offers == nil then
		Sponsors.Refresh(profile, ctx, false)
	end
	local deals = {}
	for slot, d in pairs(s.deals) do
		local def = Catalog.Sponsor(d.id)
		if def then
			local v = Sponsors.View(def, d.mult)
			v.fightsLeft, v.signedDay = d.fightsLeft, d.signedDay
			v.posted, v.strikes, v.losses, v.earned = d.posted, d.strikes, d.losses, d.earned
			v.wearOk = Sponsors.WearOk(profile, def)
			deals[slot] = v
		end
	end
	local perks = {}
	for _, k in ipairs({ { "xp" }, { "recovery" }, { "fans" }, { "discount", "gear" }, { "discount", "meals" } }) do
		local v = Sponsors.Perk(profile, k[1], k[2])
		if v > 0 then
			local text = Sponsors.PerkText({ kind = k[1], on = k[2], amount = v })
			table.insert(perks, text)
		end
	end
	return { deals = deals, offers = Sponsors.OfferViews(profile), perks = perks, fights = s.fights }
end

return Sponsors
