--!nocheck
-- tools/sim/test_sponsors.luau: the brand deals (src/shared/Catalog.lua Sponsors, src/server/Sponsors.lua and their
-- hooks in Career / Training / Main) under lune, on real careers (Career.CreateProfile):
--   * the catalog: fictional brands only, every scope (Local / Regional / National / Global) and the categories
--     filled, valid slots / perks / glove brands, rival brands in one category (the exclusivity clause)
--   * offer generation by tier: none for an amateur, Local brands for a local pro, the career's own level most
--     often, every offer one the career qualifies for, the list size, different careers different offers
--   * the exclusivity conflict: a same-category brand refused, REPLACE ends the rival; only offers on the table sign;
--     a bad / ineligible id refused
--   * payouts: per fight, win / KO / title bonuses with the negotiated mult, the signing bonus once per brand, a
--     missed social post (half the fee, strikes, the deal ended), the logo clause (robe, the brand's gloves)
--   * perks: summed and capped; the training XP, the morning energy, the gear / meal discounts at the counter, the
--     fan growth from a real ApplyResult
--   * expiry: offers count down after fights and go, a declined brand stays away, a contract runs out, the
--     performance clause (straight losses; a win resets it)
--   * save migration: a v1 save's deals get the v2 fields, corrupt pieces go, two brands of one category keep the
--     first, a JSON round trip, the summary rolls the first offers
--   lune run tools/sim/test_sponsors.luau [-v]
local Host = require("./host")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local verbose = table.find(process.args, "-v") ~= nil
local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local H = Host.new()
local Config = H.require("Config")
local Catalog = H.require("Catalog")
local Looks = H.require("Looks")
local Random = H.globals.Random

local function serverModule(name)
	local folder = rawget(H, "_serverFolder")
	if not folder then
		folder = Host.NewNode("Server", "Folder", H.Service("ServerScriptService"))
		for _, f in ipairs(fs.readDir(H.src .. "/server")) do
			local base = f:match("^(.-)%.lua$")
			if base and not f:find("%.server%.") then
				local n = Host.NewNode(base, "ModuleScript", folder)
				rawset(n, "_file", H.src .. "/server/" .. f)
			end
		end
		rawset(H, "_serverFolder", folder)
	end
	return H.requireNode(folder._kids[name])
end
local Career = serverModule("Career")
local Training = serverModule("Training")
local Sponsors = serverModule("Sponsors")

local seedN = 0
local function newCareer(tier, pop, wins, rank)
	seedN += 1
	local prof = Career.CreateProfile(nil, {
		first = "Test", last = "Boxer" .. seedN, name = "Test Boxer" .. seedN, nickname = "Tester", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1),
	}, 2000 + seedN)
	prof.tier = tier or 2
	prof.popularity = pop or 0
	prof.record = { w = wins or 0, l = 0, d = 0, ko = 0 }
	prof.money = 0
	local s = Sponsors.State(prof)
	s.seed = 77 + seedN
	return prof, Sponsors.Ctx(prof, rank or 999)
end

-- put exactly these brands on the table (mult 1) so a test can sign them
local function table_(prof, ids)
	local s = Sponsors.State(prof)
	s.offers = {}
	for _, id in ipairs(ids) do
		table.insert(s.offers, { id = id, left = 3, mult = 1 })
	end
end

local function sign(prof, id, replace, ctx)
	table_(prof, { id })
	return Sponsors.Sign(prof, id, replace, ctx)
end

------------------------------------------------------------------------
-- the catalog
------------------------------------------------------------------------
do
	local REAL = { "nike", "adidas", "everlast", "reebok", "puma", "under armour", "red bull", "monster", "gatorade", "rolex", "omega",
		"spotify", "netflix", "twitch", "youtube", "apple", "samsung", "beats", "mcdonald", "burger king", "kfc", "visa", "paypal",
		"chase", "ferrari", "lamborghini", "bmw", "mercedes", "emirates", "verizon", "playstation", "xbox", "nintendo", "dior", "chanel",
		"cleto", "winning", "title boxing", "hayabusa", "rival", "venum", "grant" }
	local ids, scopes, cats, catCount = {}, {}, {}, {}
	local okFields = true
	for _, s in ipairs(Catalog.Sponsors) do
		check("unique id " .. s.id, not ids[s.id])
		ids[s.id] = true
		scopes[s.scope] = (scopes[s.scope] or 0) + 1
		cats[s.cat] = true
		catCount[s.cat] = (catCount[s.cat] or 0) + 1
		local lname = s.name:lower()
		for _, r in ipairs(REAL) do
			if lname:find(r, 1, true) then
				check("fictional brand: " .. s.name, false, "looks like " .. r)
			end
		end
		local ok = table.find(Catalog.SponsorSlots, s.slot) ~= nil and Catalog.SponsorScopes[s.scope] ~= nil and Catalog.SponsorCats[s.cat] ~= nil
			and type(s.perFight) == "number" and s.perFight > 0 and type(s.fights) == "number" and s.fights >= 3 and type(s.logo) == "table"
			and (s.perk == nil or (Catalog.SponsorPerks[s.perk.kind] ~= nil and s.perk.amount > 0))
			and (s.wear ~= "gloves" or (Catalog.Brands[s.gloveBrand] ~= nil))
		if not ok then
			okFields = false
			print("  bad sponsor fields: " .. s.id)
		end
		check("Catalog.Sponsor finds " .. s.id, Catalog.Sponsor(s.id) == s)
	end
	check("every sponsor's fields are valid", okFields)
	check("at least 30 brands", #Catalog.Sponsors >= 30, #Catalog.Sponsors)
	for _, sc in ipairs(Catalog.SponsorScopeOrder) do
		check("scope " .. sc .. " has brands", (scopes[sc] or 0) >= 6, scopes[sc])
	end
	for _, c in ipairs({ "gloves", "sportswear", "energy", "supplements", "watches", "cars", "tech", "gaming", "food", "fastfood", "bank", "cologne", "streaming", "gym" }) do
		check("category " .. c, cats[c] == true)
	end
	local rivals = 0
	for _, n in pairs(catCount) do
		if n >= 2 then
			rivals += 1
		end
	end
	check("rival brands in many categories", rivals >= 8, rivals)
	check("Catalog.Sponsor(nil / table) is nil", Catalog.Sponsor(nil) == nil and Catalog.Sponsor({}) == nil)
	-- the deal types the catalog mixes
	local has = {}
	for _, s in ipairs(Catalog.Sponsors) do
		has.post = has.post or s.post
		has.robe = has.robe or s.wear == "robe"
		has.gloves = has.gloves or s.wear == "gloves"
		has.clause = has.clause or s.maxLosses ~= nil
		has.title = has.title or (s.titleBonus or 0) > 0
		has.noBonus = has.noBonus or ((s.winBonus or 0) == 0 and (s.koBonus or 0) == 0)
		if s.perk then
			has[s.perk.kind] = true
		end
	end
	for _, k in ipairs({ "post", "robe", "gloves", "clause", "title", "noBonus", "xp", "recovery", "discount", "fans" }) do
		check("catalog mixes deal type " .. k, has[k] == true)
	end
end

------------------------------------------------------------------------
-- offer generation by tier
------------------------------------------------------------------------
local function rollFor(tier, pop, wins, rank)
	local prof, ctx = newCareer(tier, pop, wins, rank)
	Sponsors.Refresh(prof, ctx, false)
	return prof, ctx, Sponsors.State(prof).offers
end
do
	local _, _, amateur = rollFor(1, 30, 0)
	check("an amateur gets no offers", #amateur == 0, #amateur)
	local scopeCount = {}
	local allEligible, allUnique, sizeOk = true, true, true
	for _, spec in ipairs({
		{ "local", 2, 6, 2, nil, 3 }, { "regional", 3, 16, 6, nil, 3 }, { "national", 5, 36, 14, 30, 4 }, { "global", 8, 85, 30, 1, 4 },
	}) do
		local name, tier, pop, wins, rank, size = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
		scopeCount[name] = {}
		for k = 1, 40 do
			local prof, ctx, offers = rollFor(tier, pop, wins, rank)
			if #offers ~= size then
				sizeOk = false
			end
			local seen = {}
			for _, o in ipairs(offers) do
				local def = Catalog.Sponsor(o.id)
				if not Catalog.SponsorEligible(def, ctx) then
					allEligible = false
				end
				if seen[o.id] then
					allUnique = false
				end
				seen[o.id] = true
				scopeCount[name][def.scope] = (scopeCount[name][def.scope] or 0) + 1
				check("offer mult in 0.85..1.2", o.mult >= 0.85 and o.mult <= 1.2, o.mult)
				check("offer expires in 2..4 fights", o.left >= 2 and o.left <= 4, o.left)
			end
			local _ = prof
		end
	end
	check("offer lists are full (3, 4 once National)", sizeOk)
	check("every offer is a brand the career qualifies for", allEligible)
	check("no brand offered twice", allUnique)
	local sc = scopeCount
	check("a local pro: Local brands only", (sc["local"].Local or 0) > 0 and (sc["local"].Regional or 0) == 0 and (sc["local"].National or 0) == 0)
	check("a regional pro: mostly Regional", (sc.regional.Regional or 0) > (sc.regional.Local or 0), serde.encode("json", sc.regional))
	check("a national contender: mostly National, no Global", (sc.national.National or 0) > (sc.national.Regional or 0) and (sc.national.Global or 0) == 0, serde.encode("json", sc.national))
	check("a world champion: mostly Global", (sc.global.Global or 0) > (sc.global.National or 0), serde.encode("json", sc.global))
	-- unranked at tier 6: no Global brand (the ranking gate)
	local _, _, unranked = rollFor(6, 60, 20, 999)
	local anyGlobal = false
	for _, o in ipairs(unranked) do
		anyGlobal = anyGlobal or Catalog.Sponsor(o.id).scope == "Global"
	end
	check("Global brands want a top-15 ranking", not anyGlobal)
	-- varies run to run: different careers (seeds) see different lists
	local lists = {}
	for k = 1, 12 do
		local _, _, offers = rollFor(3, 16, 6)
		local ids = {}
		for _, o in ipairs(offers) do
			table.insert(ids, o.id)
		end
		table.sort(ids)
		lists[table.concat(ids, ",")] = true
	end
	local distinct = 0
	for _ in pairs(lists) do
		distinct += 1
	end
	check("offers vary between careers", distinct >= 4, distinct)
	-- a summary on a save that never rolled rolls the first offers
	local prof = newCareer(2, 6, 2)
	Sponsors.State(prof).offers = nil
	local P = Career.Summary(prof, true)
	check("summary rolls the first offers", type(P.sponsors) == "table" and #P.sponsors.offers == 3, P.sponsors and #P.sponsors.offers)
	check("summary offer views carry the terms", P.sponsors.offers[1] and P.sponsors.offers[1].perFight > 0 and P.sponsors.offers[1].left ~= nil)
end

------------------------------------------------------------------------
-- signing, the exclusivity conflict, validation
------------------------------------------------------------------------
do
	local prof, ctx = newCareer(6, 40, 14, 20)
	local ok, err = Sponsors.Sign(prof, "ApexAthletics", false, ctx)
	check("a brand with no offer on the table won't sign", not ok and tostring(err):find("no offer") ~= nil, err)
	check("unknown brand", not Sponsors.Sign(prof, "NotABrand", false, ctx))
	check("non-string id", not Sponsors.Sign(prof, { id = "ApexAthletics" }, false, ctx))
	ok = sign(prof, "ApexAthletics", false, ctx)
	check("sign Apex (sportswear, trunks)", ok)
	check("signing bonus paid", prof.money == 12500, prof.money)
	table_(prof, { "Kinetiq" })
	local views = Sponsors.OfferViews(prof)
	check("the offer names the exclusivity conflict", views[1] and views[1].conflict == "Apex Athletics", views[1] and views[1].conflict)
	check("... and no slot clash (robe is free)", views[1] and views[1].taken == nil)
	ok, err = Sponsors.Sign(prof, "Kinetiq", false, ctx)
	check("a same-category brand is refused", not ok and tostring(err):find("Exclusivity") ~= nil, err)
	check("... Apex still signed", Sponsors.Active(prof).trunks == "ApexAthletics")
	ok = Sponsors.Sign(prof, "Kinetiq", true, ctx)
	local act = Sponsors.Active(prof)
	check("REPLACE signs Kinetiq and ends Apex", ok and act.robe == "Kinetiq" and act.trunks == nil, serde.encode("json", act))
	check("the ended rival stays away a few fights", (Sponsors.State(prof).cool.ApexAthletics or 0) > Sponsors.State(prof).fights)
	-- two brands of different categories sit side by side
	check("a different category signs next to it", sign(prof, "VoltaraEnergy", false, ctx) and Sponsors.Active(prof).corner == "VoltaraEnergy")
	-- slot clash without a category clash
	table_(prof, { "Glitchrift", "Reelstorm" })
	views = Sponsors.OfferViews(prof)
	check("a slot clash names the deal in the slot", views[2] and views[2].taken == "Kinetiq Sportswear" and views[2].conflict == nil)
	ok, err = Sponsors.Sign(prof, "Reelstorm", false, ctx)
	check("a slot clash needs REPLACE", not ok and tostring(err):find("slot") ~= nil, err)
	-- an ineligible brand never signs, even on the table
	table_(prof, { "HalcyonMotors" })
	ok, err = Sponsors.Sign(prof, "HalcyonMotors", false, ctx)
	check("an ineligible brand is refused", not ok and tostring(err):find("bigger name") ~= nil, err)
	-- the signing bonus once per brand
	local before = prof.money
	Sponsors.Drop(prof, "corner")
	Sponsors.State(prof).cool.VoltaraEnergy = nil
	sign(prof, "VoltaraEnergy", false, ctx)
	check("no second signing bonus for the same brand", prof.money == before, prof.money - before)
	-- retired
	prof.retired = true
	table_(prof, { "Hushwave" })
	check("retired careers can't sign", not Sponsors.Sign(prof, "Hushwave", false, ctx))
	-- Career wrappers (what Main's handlers call)
	local p2 = newCareer(2, 6, 2)
	table_(p2, { "TonysPizza", "CornerCafe" })
	check("Career.SignSponsor", Career.SignSponsor(p2, "TonysPizza", false))
	check("Career.DeclineSponsor", Career.DeclineSponsor(p2, "CornerCafe") and #Sponsors.State(p2).offers == 0)
	check("Career.DeclineSponsor bad id", not Career.DeclineSponsor(p2, "CornerCafe"))
	check("Career.DropSponsor", Career.DropSponsor(p2, "trunks") and Sponsors.Active(p2).trunks == nil)
end

------------------------------------------------------------------------
-- payouts and clauses
------------------------------------------------------------------------
do
	local prof, ctx = newCareer(6, 40, 14, 20)
	prof.gear.equipped.robe = "None"
	table_(prof, { "ApexAthletics" })
	Sponsors.State(prof).offers[1].mult = 1.1
	sign(prof, "ApexAthletics", false, ctx)
	Sponsors.State(prof).deals.trunks.mult = 1.1
	local def = Catalog.Sponsor("ApexAthletics")
	local total = Sponsors.Payout(prof, { win = true, ko = true, title = true })
	local want = math.floor((def.perFight + def.winBonus + def.koBonus + def.titleBonus) * 1.1 + 0.5)
	check("a KO title win pays every bonus (x mult)", total == want, string.format("%d vs %d", total, want))
	total = Sponsors.Payout(prof, { loss = true })
	check("a loss pays the base fee only", total == math.floor(def.perFight * 1.1 + 0.5), total)
	total = Sponsors.Payout(prof, { win = true })
	check("a decision win: base + win bonus", total == math.floor((def.perFight + def.winBonus) * 1.1 + 0.5), total)

	-- the social post
	local p2, c2 = newCareer(3, 20, 6)
	sign(p2, "ThunderheadEnergy", false, c2)
	local t = Catalog.Sponsor("ThunderheadEnergy")
	local pay, notes = Sponsors.Payout(p2, {})
	check("a missed post halves the fee", pay == math.floor(t.perFight * 0.5 + 0.5), pay)
	check("... and is a strike", Sponsors.State(p2).deals.corner.strikes == 1 and table.concat(notes, " "):find("strike") ~= nil)
	local popBefore = p2.popularity
	check("POST", Sponsors.Post(p2, "corner"))
	check("posting brings a little fame", p2.popularity > popBefore)
	check("one post per fight", not Sponsors.Post(p2, "corner"))
	pay = Sponsors.Payout(p2, {})
	check("a posted fight pays in full", pay == t.perFight, pay)
	check("the post resets after the fight", Sponsors.State(p2).deals.corner.posted == false)
	Sponsors.Payout(p2, {})
	check("two missed posts end the deal", Sponsors.Active(p2).corner == nil)
	check("a deal without posts can't post", (function()
		sign(p2, "Forgewell", false, c2)
		return not Sponsors.Post(p2, "robe")
	end)())

	-- the logo: a robe on the walk-out
	local f = Catalog.Sponsor("Forgewell")
	p2.gear.equipped.robe = "None"
	pay, notes = Sponsors.Payout(p2, {})
	check("no robe: half the fee", pay == math.floor(f.perFight * 0.5 + 0.5) and table.concat(notes, " "):find("robe") ~= nil, pay)
	p2.gear.equipped.robe = Catalog.Robes[2] and Catalog.Robes[2].id or "Satin"
	check("a robe on: the logo is seen", Sponsors.WearOk(p2, f))
	pay = Sponsors.Payout(p2, {})
	check("... full fee", pay == f.perFight, pay)

	-- the gloves
	local p3, c3 = newCareer(3, 20, 6)
	local rc = Catalog.Sponsor("Ringcraft")
	sign(p3, "Ringcraft", false, c3)
	p3.gear.equipped.gloves = "Worn"
	check("Gym Issue gloves: not Ringcraft", not Sponsors.WearOk(p3, rc))
	p3.gear.equipped.gloves = "Competition"
	check("Competition gloves are Ringcraft", Sponsors.WearOk(p3, rc))
	pay = Sponsors.Payout(p3, {})
	check("in their gloves: full fee", pay == rc.perFight, pay)

	-- Career.ApplyResult pays the sponsors (title kinds and losses from the offer / result)
	local p4 = newCareer(2, 6, 2)
	sign(p4, "SouthsideBC", false, Sponsors.Ctx(p4, 999))
	Career.GetOffers(p4)
	Career.AcceptOffer(p4, 1)
	local sb = Catalog.Sponsor("SouthsideBC")
	local out = Career.ApplyResult(p4, { outcome = "win", method = "KO", round = 2, cards = {}, kdFor = 1, kdAgainst = 0, landed = 40, oppLanded = 20,
		punches = {}, damageTaken = 10, headTaken = 6, bodyTaken = 4 })
	local joined = table.concat(out.notes, "\n")
	check("ApplyResult lists the sponsor pay", joined:find("Sponsors %(Southside Boxing Club%) paid " .. Config.Money(sb.perFight + sb.winBonus + sb.koBonus):gsub("%p", "%%%0")) ~= nil, joined)
	check("ApplyResult counts the contract down", Sponsors.State(p4).deals.trunks and Sponsors.State(p4).deals.trunks.fightsLeft == sb.fights - 1)
end

------------------------------------------------------------------------
-- perks
------------------------------------------------------------------------
do
	local prof, ctx = newCareer(3, 20, 6)
	check("no deals, no perks", Sponsors.Perk(prof, "xp") == 0 and Sponsors.Perk(prof, "fans") == 0)
	sign(prof, "Forgewell", false, ctx) -- xp 0.08
	sign(prof, "SouthsideBC", false, ctx) -- xp 0.08
	check("xp perks add up", math.abs(Sponsors.Perk(prof, "xp") - 0.16) < 1e-6, Sponsors.Perk(prof, "xp"))
	-- the cap
	local s = Sponsors.State(prof)
	s.deals.corner = { id = "Corelab", fightsLeft = 3, mult = 1, losses = 0, strikes = 0, posted = false, earned = 0 }
	Catalog.Sponsor("Corelab").slot = "corner"
	check("perks are capped", Sponsors.Perk(prof, "xp") <= Sponsors.PERK_CAP.xp + 1e-9)
	Catalog.Sponsor("Corelab").slot = "gear"
	s.deals.corner = nil

	-- the training XP: the same session on fresh careers, the perk forced to 0 and to the cap (Training
	-- reads Sponsors.Perk at the XP line; its gains have a little noise, so an average of a few sessions)
	local realPerk = Sponsors.Perk
	local function avgXP(perk)
		Sponsors.Perk = function(p, kind, on)
			if kind == "xp" then
				return perk
			end
			return realPerk(p, kind, on)
		end
		local sum, n = 0, 0
		for k = 1, 6 do
			local p = newCareer(2, 6, 2)
			local okP, res = pcall(Training.Perform, p, Training.Activity("HeavyBag"), 1)
			if okP and type(res) == "table" and type(res.xp) == "number" then
				sum += res.xp
				n += 1
			end
		end
		Sponsors.Perk = realPerk
		return n > 0 and sum / n or 0
	end
	local x0, x1 = avgXP(0), avgXP(0.3)
	check("training XP perk scales the session XP", x0 > 0 and x1 > x0 * 1.15, string.format("%.1f -> %.1f", x0, x1))

	-- the morning energy
	local p2 = newCareer(2, 6, 2)
	p2.condition.energy = 10
	Training.Sleep(p2)
	local plain = p2.condition.energy
	local p3 = newCareer(2, 6, 2)
	sign(p3, "CornerCafe", false, Sponsors.Ctx(p3, 999)) -- recovery 6
	p3.condition.energy = 10
	Training.Sleep(p3)
	check("recovery perk: more energy after sleep", p3.condition.energy > plain or p3.condition.energy == 100, string.format("%s vs %s", p3.condition.energy, plain))

	-- discounts at the counter
	local p4, c4 = newCareer(3, 20, 6)
	p4.money = 10000
	sign(p4, "Ringcraft", false, c4) -- gear -20%
	local glove = Catalog.Find(Catalog.Gloves, "Competition")
	local m0 = p4.money
	check("BuyGear with a sponsor", Training.BuyGear(p4, "gloves", "Competition"))
	check("gear discount charged", m0 - p4.money == math.floor(glove.price * 0.8 + 0.5), m0 - p4.money)
	check("Sponsors.Price gear", Sponsors.Price(p4, 1000, "gear") == 800)
	check("a gear discount doesn't touch meals", Sponsors.Price(p4, 1000, "meals") == 1000)
	local p5 = newCareer(2, 6, 2)
	sign(p5, "TonysPizza", false, Sponsors.Ctx(p5, 999)) -- meals -15%
	check("meal discount", Sponsors.Price(p5, 100, "meals") == 85)
	local meal
	for _, m in ipairs(Config.Meals) do
		if m.price and m.price >= 20 and not m.requires then
			meal = m
			break
		end
	end
	if meal then
		p5.money = 1000
		local _, info = Training.Eat(p5, meal.id)
		-- (a plan goal the meal completes pays its reward on top: add it back)
		local reward = 0
		for _, g in ipairs(type(info) == "table" and info.goals or {}) do
			reward += tonumber(g.money) or 0
		end
		check("Eat charges the discounted price", 1000 - p5.money + reward == math.floor(meal.price * 0.85 + 0.5), 1000 - p5.money + reward)
	end

	-- fan growth from a win (a real ApplyResult)
	local function winFame(withPerk)
		local p = newCareer(2, 10, 2)
		if withPerk then
			check("sign Ink & Iron", sign(p, "InkAndIron", false, Sponsors.Ctx(p, 999))) -- fans +12%
			p.popularity = 10
		end
		Career.GetOffers(p)
		Career.AcceptOffer(p, 1)
		p.camp.offer.kind = "Pro Fight"
		p.camp.offer.tourney = nil
		local before = p.popularity
		Career.ApplyResult(p, { outcome = "win", method = "KO", round = 2, cards = {}, kdFor = 1, kdAgainst = 0, landed = 40, oppLanded = 20,
			punches = {}, damageTaken = 10, headTaken = 6, bodyTaken = 4 })
		return p.popularity - before
	end
	local a, b = winFame(false), winFame(true)
	check("fan-growth perk: more fame from a win", b > a, string.format("%.2f vs %.2f", b, a))
	-- the summary lists the perks
	local P = Career.Summary(p5, true)
	check("summary lists the perks", type(P.sponsors.perks) == "table" and #P.sponsors.perks >= 1 and tostring(P.sponsors.perks[1]):find("meals") ~= nil)
end

------------------------------------------------------------------------
-- expiry and the performance clause
------------------------------------------------------------------------
do
	local prof, ctx = newCareer(3, 20, 6)
	table_(prof, { "Grillstack", "GridlineGaming" })
	local s = Sponsors.State(prof)
	s.offers[1].left = 1
	s.offers[2].left = 2
	local notes = Sponsors.AfterFight(prof, ctx)
	local ids = {}
	for _, o in ipairs(s.offers) do
		ids[o.id] = o
	end
	check("an offer at its last fight expires", ids.Grillstack == nil and table.concat(notes, " "):find("expired") ~= nil, table.concat(notes, " | "))
	check("the others count down", ids.GridlineGaming and ids.GridlineGaming.left == 1)
	check("the list is topped up again", #s.offers == 3, #s.offers)
	-- declined brands stay away
	local p2, c2 = newCareer(2, 6, 2)
	Sponsors.Refresh(p2, c2, false)
	local s2 = Sponsors.State(p2)
	local declined = s2.offers[1].id
	check("decline", Sponsors.Decline(p2, declined))
	check("decline twice fails", not Sponsors.Decline(p2, declined))
	local back = false
	for k = 1, Sponsors.DECLINE_COOL - 1 do
		Sponsors.Payout(p2, {})
		Sponsors.AfterFight(p2, c2)
		for _, o in ipairs(s2.offers) do
			back = back or o.id == declined
		end
	end
	check("a declined brand stays away while cooling down", not back)
	-- a contract runs out
	local p3, c3 = newCareer(2, 6, 2)
	sign(p3, "FreshFades", false, c3) -- 3 fights
	for k = 1, 3 do
		Sponsors.Post(p3, "robe")
		local _, n = Sponsors.Payout(p3, { win = true })
		if k == 3 then
			check("the last fight completes the deal", Sponsors.Active(p3).robe == nil and table.concat(n, " "):find("complete") ~= nil, table.concat(n, " | "))
		else
			check("contract counts down " .. k, Sponsors.State(p3).deals.robe and Sponsors.State(p3).deals.robe.fightsLeft == 3 - k)
		end
	end
	-- the performance clause: 2 straight losses at Southside, a win in between resets
	local p4, c4 = newCareer(2, 6, 2)
	sign(p4, "SouthsideBC", false, c4)
	Sponsors.Payout(p4, { loss = true })
	Sponsors.Payout(p4, { win = true })
	check("a win resets the losing streak", Sponsors.State(p4).deals.trunks and Sponsors.State(p4).deals.trunks.losses == 0)
	Sponsors.Payout(p4, { loss = true })
	check("one loss: still signed", Sponsors.Active(p4).trunks == "SouthsideBC")
	local _, n4 = Sponsors.Payout(p4, { loss = true })
	check("two straight losses: dropped (performance clause)", Sponsors.Active(p4).trunks == nil and table.concat(n4, " "):find("performance clause") ~= nil, table.concat(n4, " | "))
	check("a draw doesn't count as a loss", (function()
		local p5, c5 = newCareer(2, 6, 2)
		sign(p5, "SouthsideBC", false, c5)
		Sponsors.Payout(p5, { loss = true })
		Sponsors.Payout(p5, {})
		return Sponsors.State(p5).deals.trunks.losses == 1
	end)())
	-- an offer the career no longer qualifies for goes at the refresh
	local p6, c6 = newCareer(3, 20, 6)
	table_(p6, { "Grillstack" })
	c6.pop = 2
	Sponsors.Refresh(p6, c6, false)
	local still = false
	for _, o in ipairs(Sponsors.State(p6).offers) do
		still = still or o.id == "Grillstack"
	end
	check("an offer you no longer qualify for goes", not still)
end

------------------------------------------------------------------------
-- save migration
------------------------------------------------------------------------
do
	local prof = newCareer(5, 40, 14)
	-- a v1 save as the old Career wrote it
	prof.sponsors = {
		deals = {
			trunks = { id = "TonysPizza", fightsLeft = 3, signedDay = 4 },
			robe = { id = "NoSuchBrand", fightsLeft = 2, signedDay = 1 },
			corner = { id = "IronSupplements", fightsLeft = 2, signedDay = 1 }, -- the wrong slot
			gear = { id = "WCBProShop", fightsLeft = 0 / 0, signedDay = 1 },
		},
		signed = { TonysPizza = true, WCBProShop = true },
	}
	local json = serde.encode("json", prof.sponsors)
	prof.sponsors = serde.decode("json", json)
	local okM, errM = pcall(Training.Migrate, prof)
	check("v1 save migrates", okM, errM)
	local s = prof.sponsors
	check("migrated to v2", s.v == 2)
	check("a valid deal is kept", s.deals.trunks and s.deals.trunks.id == "TonysPizza" and s.deals.trunks.fightsLeft == 3)
	check("... with the v2 fields", s.deals.trunks and s.deals.trunks.mult == 1 and s.deals.trunks.losses == 0 and s.deals.trunks.strikes == 0 and s.deals.trunks.posted == false)
	check("an unknown brand is dropped", s.deals.robe == nil)
	check("a deal in the wrong slot is dropped", s.deals.corner == nil)
	check("a NaN contract is dropped", s.deals.gear == nil)
	check("signed brands kept", s.signed.TonysPizza == true and s.signed.WCBProShop == true)
	check("offers left to roll", s.offers == nil)
	check("a seed for the career", type(s.seed) == "number")
	local okS, P = pcall(Career.Summary, prof, true)
	check("the summary of a migrated save", okS and type(P.sponsors) == "table" and P.sponsors.deals.trunks ~= nil, P)
	check("... rolls the offers", okS and #P.sponsors.offers >= 3)
	-- idempotent and JSON-safe
	local before = serde.encode("json", prof.sponsors)
	Training.Migrate(prof)
	check("migration is idempotent", serde.encode("json", prof.sponsors) == before)
	local okJ = pcall(serde.encode, "json", prof.sponsors)
	check("the state saves as JSON", okJ)
	-- two brands of one category in an old save: the first slot's is kept
	local p2 = newCareer(6, 50, 20)
	p2.sponsors = { deals = { trunks = { id = "ApexAthletics", fightsLeft = 3 }, robe = { id = "Kinetiq", fightsLeft = 3 } } }
	Training.Migrate(p2)
	check("an old same-category pair keeps the first slot's", p2.sponsors.deals.trunks ~= nil and p2.sponsors.deals.robe == nil)
	-- garbage
	local p3 = newCareer(2)
	p3.sponsors = { deals = "x", signed = 5, offers = { { id = "TonysPizza", left = "a" }, "junk", { id = "CornerCafe", left = 2, mult = 99 } }, cool = { TonysPizza = "z" }, fights = -4 }
	local okG = pcall(Training.Migrate, p3)
	check("a corrupt sponsors table loads", okG)
	check("... cleaned", type(p3.sponsors.deals) == "table" and #p3.sponsors.offers == 1 and p3.sponsors.offers[1].mult == 2 and p3.sponsors.fights == 0 and next(p3.sponsors.cool) == nil)
	local p4 = newCareer(2)
	p4.sponsors = nil
	check("no sponsors table at all", pcall(Training.Migrate, p4) and type(p4.sponsors) == "table")
	check("Career.LookOpts with a deal patch", (function()
		local p5, c5 = newCareer(2, 6, 2)
		sign(p5, "TonysPizza", false, c5)
		local o = Career.LookOpts(p5)
		return o.sponsorTrunks and o.sponsorTrunks.text == "TONY'S"
	end)())
	check("ActiveSponsors before creation", next(Career.ActiveSponsors({ created = false })) == nil)
end

if verbose then
	print(string.format("%d brands", #Catalog.Sponsors))
end
print(string.format("test_sponsors: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
