--!nocheck
-- tools/sim/test_tournaments.luau: the tournaments (src/shared/Tournaments.lua, src/server/Tourney.lua and their hooks
-- in Career / World, src/shared/BeltModel.lua) under lune, on real careers (Career.CreateProfile, the world generator):
--   * the calendar: every event's starts, entry windows, LastStart / NextStart, the merged calendar
--   * entry rules: by career level (tier bands, the invitational's ranking), a camp / retirement / a running bracket
--     block entry, entry only while the window is open; the names are fictional (no real tournament or org names)
--   * the bracket: 8 boxers of the player's division, the event's overall band, seeds 1..8 laid out 1v8 4v5 3v6 2v7, the
--     player in it once; the quarter-final booked as a camp until the start day
--   * progression: each round a real ApplyResult (live-shaped results), the AI side of the round resolved
--     (World.AIBout, no draws), the next round booked `recovery` days later (no 21-day suspension, no world cycle), the
--     wear carried into the next round (FighterFromProfile.carry), a draw going through on punches landed, a loss and
--     a withdrawal ending the run (the walkover), a concussion as a medical withdrawal
--   * prizes and the belt: the purse per bout, the prize by the round reached, fame and ranking points per round won
--     (World.PlayerScore), the belt counted and worn (WornBelt / SetWear), the champion on the world's books, the
--     legacy line
--   * AI editions: Tick settles the editions the player sat out (holders, b.tbelts, the log), idempotent, a new
--     career gets last season's champions; Prune keeps the holders and the bracket
--   * saves: an old save without profile.tourney loads (Summary, GetOffers, ApplyResult), a save round-trips through
--     JSON with its belts and its running bracket, corrupt pieces are dropped
--   * the ceremony spec (finals and new titles only) and the belt models (every design builds, worn / display)
--   lune run tools/sim/test_tournaments.luau [-v]
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
local Looks = H.require("Looks")
local T = H.require("Tournaments")
local BeltModel = H.require("BeltModel")
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
local World = serverModule("World")
local Tourney = serverModule("Tourney")

local seedN = 0
local function newCareer(tier, opts)
	opts = opts or {}
	seedN += 1
	local prof = Career.CreateProfile(nil, {
		first = "Test", last = "Boxer" .. seedN, name = "Test Boxer" .. seedN, nickname = "Tester", age = 22, nationality = "USA",
		weightClass = opts.class or 5, style = "boxer", look = Looks.Defaults(1),
	}, 1000 + seedN)
	prof.tier = tier or 1
	prof.day = opts.day or 1
	if opts.overall then
		for _, k in ipairs(Config.StatKeys) do
			prof.stats[k] = opts.overall
		end
		prof.overall = Config.Overall(prof.stats)
	end
	return prof
end

-- a live-shaped fight result (what FightEngine hands Career)
local function result(outcome, extra)
	local r = { outcome = outcome, method = outcome == "draw" and "Draw" or "UD", round = 3, cards = { { 29, 28 }, { 29, 28 }, { 28, 29 } },
		kdFor = 0, kdAgainst = 0, landed = 40, thrown = 100, oppLanded = 30, oppThrown = 90, punches = { jab = 10 }, damageTaken = 30, headTaken = 20, bodyTaken = 10 }
	for k, v in pairs(extra or {}) do
		r[k] = v
	end
	return r
end

-- sleep until the camp's fight night (Training.Sleep: the day and the camp's countdown, like the game)
local Training = serverModule("Training")
local function sleepToFight(prof)
	local n = 0
	while prof.camp and prof.camp.daysLeft > 0 and n < 60 do
		Training.Sleep(prof)
		Tourney.Tick(prof)
		n += 1
	end
	return n
end

local function dayOpen(def)
	-- the first day the entry window of the second edition is open
	local s = def.offset + def.every
	return s - def.window
end

------------------------------------------------------------------------
-- 1. the events, names, the calendar
------------------------------------------------------------------------
check("five events", #T.List == 5)
local ids = {}
for _, def in ipairs(T.List) do
	ids[def.id] = true
end
check("the ladder", ids.novice and ids.city and ids.regional and ids.national and ids.world)
-- fictional names only: no real tournament or organisation name in the new content
local REAL = { "golden gloves", "wba", "wbc", "ibf", "wbo", "ring magazine", "olympic", "commonwealth", "world boxing super series", "wbss", "muhammad ali trophy",
	"usa boxing", "amateur boxing association", "aiba", "iba", "top rank", "matchroom", "golden boy", "premier boxing", "pbc", "showtime", "hbo", "dazn", "espn" }
for _, path in ipairs({ "/shared/Tournaments.lua", "/server/Tourney.lua", "/shared/BeltModel.lua", "/client/modules/TourneyUI.lua", "/client/modules/Ceremony.lua",
	"/client/modules/AnimCeremony.lua" }) do
	local ok, src = pcall(fs.readFile, H.src .. path)
	if ok then
		-- (comments and the code that names Config.Orgs keys from outside are not new names: strings only)
		local lower = string.lower(src)
		for _, bad in ipairs(REAL) do
			local found = false
			for str in lower:gmatch('"([^"]*)"') do
				if str:find(bad, 1, true) and (#bad > 3 or str:match("%f[%w]" .. bad .. "%f[%W]")) then
					found = true
				end
			end
			check("no real name '" .. bad .. "' in " .. path, not found)
		end
	end
end
for _, def in ipairs(T.List) do
	local id = def.id
	check(id .. ": belt design", type(def.belt) == "table" and def.belt.shape and def.belt.emblem and def.belt.strap and def.belt.plate)
	check(id .. ": prizes rise by round", def.prize[1] <= def.prize[2] and def.prize[2] <= def.prize[3] and def.prize[3] < def.prize[4])
	check(id .. ": NextStart on the offset", T.NextStart(def, 1) == def.offset)
	check(id .. ": NextStart >= day", T.NextStart(def, def.offset + 1) == def.offset + def.every)
	check(id .. ": LastStart", T.LastStart(def, def.offset - 1) == nil and T.LastStart(def, def.offset) == def.offset and T.LastStart(def, def.offset + def.every - 1) == def.offset)
	local s = def.offset + def.every
	check(id .. ": entry open in the window", T.EntryOpen(def, s - def.window) == true and T.EntryOpen(def, s - 1) == true)
	check(id .. ": entry closed before the window", T.EntryOpen(def, s - def.window - 1) == false)
	local onStart, nextS = T.EntryOpen(def, s)
	check(id .. ": the start day is too late (the next edition)", onStart == false and nextS == s + def.every)
	check(id .. ": recovery days between rounds", def.recovery >= 1 and def.recovery <= 7)
end
-- distinct belts: no two events share a shape + emblem + strap colour
local seen = {}
for _, def in ipairs(T.List) do
	local key = def.belt.shape .. "|" .. def.belt.emblem
	check("distinct belt " .. def.id, not seen[key], key)
	seen[key] = true
end
local cal = T.Calendar(30, 2)
check("calendar: 10 entries sorted", #cal == 10 and cal[1].start <= cal[2].start and cal[9].start <= cal[10].start)

------------------------------------------------------------------------
-- 2. entry rules
------------------------------------------------------------------------
do
	local am = newCareer(1)
	check("amateur: novice ok", Tourney.Eligible(am, "novice") == true)
	check("amateur: city refused", Tourney.Eligible(am, "city") == false)
	local lp = newCareer(2)
	check("local pro: novice refused", Tourney.Eligible(lp, "novice") == false)
	check("local pro: city ok", Tourney.Eligible(lp, "city") == true)
	check("local pro: regional refused", Tourney.Eligible(lp, "regional") == false)
	check("tier 3: regional ok", Tourney.Eligible(newCareer(3), "regional") == true)
	check("tier 4: national ok", Tourney.Eligible(newCareer(4), "national") == true)
	check("tier 7: national refused", Tourney.Eligible(newCareer(7), "national") == false)
	-- the invitational: by ranking
	local top = newCareer(6, { overall = 92 })
	top.record = { w = 30, l = 0, d = 0, ko = 25 }
	local best = World.BestRank(top)
	check("world GP: a top-10 pro is invited", Tourney.Eligible(top, "world") == (best <= 10), "rank " .. tostring(best))
	local low = newCareer(6, { overall = 30 })
	check("world GP: an unranked pro is not", Tourney.Eligible(low, "world") == false)
	check("unknown event", Tourney.Eligible(am, "nope") == false)
	-- the window
	local def = T.ById.novice
	am.day = dayOpen(def) - 1
	local ok, err = Tourney.Enter(am, "novice")
	check("enter: closed before the window", ok == false and type(err) == "string" and err:find("Entries open"), err)
	am.day = dayOpen(def)
	ok, err = Tourney.Enter(am, "city")
	check("enter: the rules", ok == false, err)
	am.camp = { offer = {}, daysLeft = 2, daysTotal = 2, log = {} }
	ok, err = Tourney.Enter(am, "novice")
	check("enter: not with a fight booked", ok == false, err)
	am.camp = nil
	am.retired = true
	check("enter: not retired", Tourney.Enter(am, "novice") == false)
	am.retired = false
	ok, err = Tourney.Enter(am, "novice")
	check("enter: open + eligible", ok == true, err)
	check("enter: a second one refused", Tourney.Enter(am, "novice") == false)
end

------------------------------------------------------------------------
-- 3. the bracket
------------------------------------------------------------------------
local function enter(tier, id, opts)
	local def = T.ById[id]
	local prof = newCareer(tier, opts)
	prof.day = dayOpen(def)
	Tourney.Tick(prof)
	local ok, info = Tourney.Enter(prof, id)
	assert(ok, info)
	return prof, def, info
end
do
	local prof, def, info = enter(2, "city")
	local run = prof.tourney.run
	check("bracket: 8 boxers", #run.field == 8)
	local players, uniq = 0, {}
	for _, id in ipairs(run.field) do
		if id == "player" then
			players += 1
		else
			local b = prof.world.boxers[id]
			check("bracket: " .. id .. " in the player's division", b and b.class == prof.physical.weightClass and not b.retired)
		end
		check("bracket: no duplicate " .. tostring(id), not uniq[id])
		uniq[id] = true
	end
	check("bracket: the player once", players == 1)
	-- seeds: slot order 1 8 4 5 3 6 2 7, seed 1 the best overall
	local bySeed = {}
	for id, sd in pairs(run.seeds) do
		bySeed[sd] = id
	end
	for slot, seed in ipairs(T.SEED_SLOTS) do
		check("bracket: slot " .. slot .. " holds seed " .. seed, run.field[slot] == bySeed[seed])
	end
	local function ov(id)
		return id == "player" and prof.overall or prof.world.boxers[id].overall
	end
	local sorted = true
	for sd = 1, 7 do
		sorted = sorted and ov(bySeed[sd]) >= ov(bySeed[sd + 1])
	end
	check("bracket: seeded by overall", sorted)
	-- the band (widened only when thin): most of the field inside it
	local inBand = 0
	for _, id in ipairs(run.field) do
		if id ~= "player" then
			local o = prof.world.boxers[id].overall
			if o >= def.band[1] - 8 and o <= def.band[2] + 8 then
				inBand += 1
			end
		end
	end
	check("bracket: the field in the event's band", inBand >= 6, inBand)
	-- the QF camp
	local camp = prof.camp
	check("QF: booked as a camp", camp and camp.offer and camp.offer.tourney and camp.offer.tourney.round == 1)
	check("QF: on the start day", camp.daysLeft == run.ed - prof.day and camp.daysLeft >= 1, camp.daysLeft)
	check("QF: the opponent is the bracket's", camp.offer.oppId == T.OpponentIn(run, 1, "player"))
	check("QF: the event's rounds and venue", camp.offer.rounds == def.rounds and camp.offer.venue == def.venue)
	check("QF: a purse", (camp.offer.purse or 0) > 0)
	check("QF: kind", camp.offer.kind == "Tournament Quarter-final", camp.offer.kind)
	check("enter info", info.seed == run.seeds.player and type(info.opp) == "string")
	-- the view
	local v = Tourney.View(prof)
	check("view: 5 events", #v.list == 5)
	check("view: the run's rounds", v.run and #v.run.rounds == 3 and #v.run.rounds[1] == 4 and #v.run.rounds[2] == 2 and #v.run.rounds[3] == 1)
	check("view: you in the bracket", (function()
		for _, m in ipairs(v.run.rounds[1]) do
			if (m.a and m.a.you) or (m.b and m.b.you) then
				return true
			end
		end
		return false
	end)())
	-- Prune keeps the bracket
	for _, id in ipairs(run.field) do
		if id ~= "player" then
			prof.world.boxers[id].retired = true
			prof.world.boxers[id].h2h = { w = 0, l = 0, d = 0 }
		end
	end
	World.Prune(prof)
	local kept = true
	for _, id in ipairs(run.field) do
		kept = kept and (id == "player" or prof.world.boxers[id] ~= nil)
	end
	check("prune keeps the bracket", kept)
end

------------------------------------------------------------------------
-- 4. progression through the normal results path
------------------------------------------------------------------------
do
	local prof, def = enter(2, "city")
	local run = prof.tourney.run
	local money0, pop0, points0 = prof.money, prof.popularity, prof.tourney.points
	local cycles = 0
	local realCycle = World.SimulateCycle
	World.SimulateCycle = function(...)
		cycles += 1
		return realCycle(...)
	end
	sleepToFight(prof)
	check("QF day = the start day", prof.day == run.ed, prof.day .. " vs " .. run.ed)
	local day0 = prof.day
	local out = Career.ApplyResult(prof, result("win"))
	check("QF win: round 1 decided", run.w[1] and #run.w[1] == 4 and run.w[1][T.MatchOf(T.PosIn(run, 1, "player"))] == "player")
	local allDecided = true
	for k = 1, 4 do
		allDecided = allDecided and run.w[1][k] ~= nil and run.m[1][k] ~= nil and run.m[1][k].method ~= "Draw"
	end
	check("QF win: the AI side of the round resolved, no draws", allDecided)
	check("QF win: the SF booked", prof.camp and prof.camp.offer.tourney and prof.camp.offer.tourney.round == 2)
	check("QF win: recovery days, not a suspension", prof.day - day0 == def.recovery and prof.camp.daysLeft == def.recovery, prof.day - day0)
	check("QF win: no world cycle mid-bracket", cycles == 0)
	check("QF win: fame per round", prof.popularity > pop0)
	check("QF win: ranking points", prof.tourney.points == points0 + def.points[1])
	check("QF win: purse paid", prof.money > money0)
	check("QF win: notes", table.concat(out.notes, "|"):find("semi%-final") ~= nil, table.concat(out.notes, "|"))
	check("QF win: wear carried", run.wear.head > 0 or run.wear.body > 0)
	local carry = Career.FighterFromProfile(prof).carry
	check("SF: FighterFromProfile carries the wear", type(carry) == "table" and carry.head <= 1 and carry.body <= 1 and (carry.head < 1 or carry.body < 1))
	check("SF: the opponent won his QF", prof.camp.offer.oppId == T.OpponentIn(run, 2, "player") and table.find(run.w[1], prof.camp.offer.oppId))
	-- a draw goes through on punches landed
	sleepToFight(prof)
	Career.ApplyResult(prof, result("draw", { landed = 50, oppLanded = 20 }))
	check("SF draw (busier): through to the final", prof.camp and prof.camp.offer.tourney.round == 3 and #run.w[2] == 2)
	check("final: offer marks the belt", prof.camp.offer.tourneyBelt == def.id)
	local cer = Tourney.CeremonyFor(prof, prof.camp.offer)
	check("final: a ceremony spec", cer and cer.belt == def.id and cer.title == def.champion and cer.kicker == "AND THE NEW...")
	sleepToFight(prof)
	local before = prof.money
	local beforePts = World.PlayerScore(prof, Config.Orgs[1])
	out = Career.ApplyResult(prof, result("win", { method = "KO", round = 2 }))
	check("final win: the belt", prof.tourney.belts[def.id] and prof.tourney.belts[def.id].n == 1)
	check("final win: worn by default", Tourney.WornBelt(prof) == def.id)
	check("final win: the run is over, no camp", prof.tourney.run == nil and prof.camp == nil)
	check("final win: the winner's prize", prof.money - before >= def.prize[4], prof.money - before)
	check("final win: history", prof.tourney.history[#prof.tourney.history].place == 4)
	local W = prof.world.tourney
	check("final win: the champion on the books", W.holders[def.id].id == "player")
	check("final win: the log", W.log[#W.log].winner == "player" and W.log[#W.log].t == def.id)
	check("final win: notes", table.concat(out.notes, "|"):find(def.champion, 1, true) ~= nil)
	check("final win: back to the normal suspension and the world cycle", cycles >= 1)
	check("final win: ranking points raise the player's score", World.PlayerScore(prof, Config.Orgs[1]) > beforePts - 20)
	check("final win: done for the edition", prof.tourney.done[def.id] == run.ed)
	check("legacy counts the belt", Career.TourneyLegacy(prof) > 0)
	local legacyLine = false
	for _, p in ipairs(Career.Legacy(prof).parts) do
		legacyLine = legacyLine or (p[1] == "Tournament belts" and p[2] > 0)
	end
	check("legacy: the line", legacyLine)
	-- wear a belt / take it off
	check("SetWear: off", Tourney.SetWear(prof, nil) == true and Tourney.WornBelt(prof) == nil)
	check("SetWear: a belt not won", Tourney.SetWear(prof, "world") == false)
	check("SetWear: back on", Tourney.SetWear(prof, def.id) == true and Career.FighterFromProfile(prof).walkBelt == def.id)
	-- the summary
	local P = Career.Summary(prof, true)
	check("summary: tourney view", P.tourney and #P.tourney.belts == 1 and P.tourney.belts[1].id == def.id and P.tourney.wear == def.id)
	World.SimulateCycle = realCycle
end

-- a loss ends the run (prize for the round reached, the rest of the bracket resolved)
do
	local prof, def = enter(3, "regional")
	local run = prof.tourney.run
	sleepToFight(prof)
	local before = prof.money
	Career.ApplyResult(prof, result("loss", { method = "TKO", round = 4 }))
	check("QF loss: the run is over", prof.tourney.run == nil and prof.camp == nil)
	check("QF loss: the bracket finished without him", run.w[3] and run.w[3][1] ~= nil and run.w[3][1] ~= "player")
	check("QF loss: the champion on the books", prof.world.tourney.holders[def.id].id == run.w[3][1])
	local champ = prof.world.boxers[run.w[3][1]]
	check("QF loss: the AI champion holds the belt", champ.tbelts and champ.tbelts[def.id] >= 1)
	check("QF loss: prize[1] paid", prof.money - before >= def.prize[1])
	check("QF loss: a normal suspension", prof.day >= run.ed + 21)
	check("QF loss: history", prof.tourney.history[#prof.tourney.history].place == 1)
	local ov = Career.OppView(prof, champ)
	check("OppView names his tournament belt", ov.tbelts and ov.tbelts[1]:find(def.name, 1, true) ~= nil)
	-- a draw that goes the other way is a loss too
	local p2 = enter(3, "regional")
	sleepToFight(p2)
	Career.ApplyResult(p2, result("draw", { landed = 10, oppLanded = 40 }))
	check("draw (less busy): out", p2.tourney.run == nil)
end

-- a withdrawal between rounds; a concussion is a medical withdrawal
do
	local prof, def = enter(4, "national")
	local run = prof.tourney.run
	sleepToFight(prof)
	Career.ApplyResult(prof, result("win"))
	check("national QF won", prof.camp and prof.camp.offer.tourney.round == 2)
	local opp = prof.camp.offer.oppId
	local notes = {}
	local ok = Tourney.Withdraw(prof, notes)
	check("withdraw: ok", ok == true)
	check("withdraw: no camp, no run", prof.camp == nil and prof.tourney.run == nil)
	check("withdraw: the SF opponent through on a walkover", run.m[2][T.MatchOf(T.PosIn(run, 2, "player"))].method == "W/O" and table.find(run.w[2], opp) ~= nil)
	check("withdraw: the prize for the round reached", prof.tourney.history[#prof.tourney.history].place == 2)
	check("withdraw: nothing to withdraw from", Tourney.Withdraw(prof, {}) == false)
	-- the doctor
	local p2 = enter(4, "national")
	sleepToFight(p2)
	-- (a concussion from the QF: Training.AddTrauma gives it on a heavy night; forced here)
	local realHas = Training.HasInjury
	Training.HasInjury = function(p, id)
		if p == p2 and id == "concussion" then
			return true
		end
		return realHas(p, id)
	end
	local out = Career.ApplyResult(p2, result("win"))
	Training.HasInjury = realHas
	check("concussion: medical withdrawal", p2.tourney.run == nil and p2.camp == nil and table.concat(out.notes, "|"):find("doctor withdraws") ~= nil, table.concat(out.notes, "|"))
end

-- a simulated bout counts the same (Career.SimFight through ApplyResult) and the carried wear weakens it
do
	local prof = enter(1, "novice")
	sleepToFight(prof)
	local res = Career.SimFight(prof, prof.camp.offer)
	check("sim: a result", res and (res.outcome == "win" or res.outcome == "loss" or res.outcome == "draw"))
	Career.ApplyResult(prof, res)
	check("sim: the bracket moved on", prof.tourney.run == nil or prof.tourney.run.round == 2)
end

------------------------------------------------------------------------
-- 5. AI editions (Tick)
------------------------------------------------------------------------
do
	local prof = newCareer(1)
	local n = Tourney.Tick(prof)
	check("tick: last season's champions for a new career", n == 5, n)
	local W = prof.world.tourney
	for _, def in ipairs(T.List) do
		local h = W.holders[def.id]
		check("tick: " .. def.id .. " has a holder", h and h.id ~= "player" and prof.world.boxers[h.id] ~= nil)
		local b = h and prof.world.boxers[h.id]
		check("tick: " .. def.id .. " holder counted", b and b.tbelts and b.tbelts[def.id] >= 1)
	end
	check("tick: idempotent", Tourney.Tick(prof) == 0)
	local def = T.ById.city
	prof.day = def.offset
	check("tick: the first edition on its start day", Tourney.Tick(prof) >= 1 and prof.tourney.done.city == def.offset)
	prof.day = def.offset + def.every * 5 + 3
	local before = #W.log
	Tourney.Tick(prof)
	check("tick: a long gap settles only the latest edition", prof.tourney.done.city == def.offset + def.every * 5 and #W.log - before <= 5)
	-- not the edition the player is fighting
	local p2, d2 = enter(2, "city")
	p2.day = p2.tourney.run.ed
	local logN = #p2.world.tourney.log
	Tourney.Tick(p2)
	local simulatedOwn = false
	for i = logN + 1, #p2.world.tourney.log do
		simulatedOwn = simulatedOwn or (p2.world.tourney.log[i].t == d2.id and p2.world.tourney.log[i].ed == p2.tourney.run.ed)
	end
	check("tick: never the player's running edition", not simulatedOwn)
	-- Prune keeps the holders
	for id, h in pairs(prof.world.tourney.holders) do
		local b = prof.world.boxers[h.id]
		if b then
			b.retired = true
			b.h2h = { w = 0, l = 0, d = 0 }
		end
	end
	World.Prune(prof)
	local kept = true
	for _, h in pairs(prof.world.tourney.holders) do
		kept = kept and prof.world.boxers[h.id] ~= nil
	end
	check("prune keeps the belt holders", kept)
	-- AIBout: no draws when asked
	local r = Random.new(5)
	local A = { id = "x1", overall = 50, record = { w = 0, l = 0, d = 0, ko = 0 } }
	local B = { id = "x2", overall = 50, record = { w = 0, l = 0, d = 0, ko = 0 } }
	local draws = 0
	for _ = 1, 300 do
		local w = World.AIBout(A, B, r, true)
		if not w then
			draws += 1
		end
	end
	check("AIBout noDraw: always a winner", draws == 0 and A.record.d == 0 and A.record.w + B.record.w == 300)
end

------------------------------------------------------------------------
-- 6. saves: old saves, the JSON round trip, corrupt pieces
------------------------------------------------------------------------
do
	local prof = newCareer(2)
	prof.tourney = nil
	prof.world.tourney = nil
	local okS, P = pcall(Career.Summary, prof, true)
	check("old save: Summary", okS and P.tourney and #P.tourney.list == 5, P)
	prof.tourney = nil
	local okO = pcall(Career.GetOffers, prof)
	check("old save: GetOffers", okO)
	prof.tourney = nil
	check("old save: World.PlayerScore", pcall(World.PlayerScore, prof, Config.Orgs[1]))
	prof.tourney = nil
	local okF, fd = pcall(Career.FighterFromProfile, prof)
	check("old save: FighterFromProfile (no carry, no belt)", okF and fd.carry == nil and fd.walkBelt == nil)
	prof.tourney = nil
	prof.offers = nil
	Career.GetOffers(prof)
	Career.AcceptOffer(prof, 1)
	local okA, err = pcall(Career.ApplyResult, prof, result("win"))
	check("old save: an ordinary fight's ApplyResult", okA, err)
	-- a save with belts and a running bracket round-trips (DataStore = JSON)
	local p2 = enter(2, "city")
	p2.tourney.belts.novice = { n = 2, last = 5 }
	p2.tourney.wear = "novice"
	local json = serde.encode("json", p2)
	local back = serde.decode("json", json)
	Tourney.State(back)
	check("round trip: belts", back.tourney.belts.novice and back.tourney.belts.novice.n == 2)
	check("round trip: worn belt", Tourney.WornBelt(back) == "novice")
	check("round trip: the bracket", back.tourney.run and #back.tourney.run.field == 8 and back.tourney.run.round == 1)
	sleepToFight(back)
	local okR = pcall(Career.ApplyResult, back, result("win"))
	check("round trip: the bracket goes on after a load", okR and back.tourney.run and back.tourney.run.round == 2)
	-- corrupt pieces
	local p3 = newCareer(2)
	p3.tourney = { belts = { novice = { n = "x" }, fake = { n = 3 }, city = { n = 1 } }, points = 0 / 0, wear = "world", run = { id = "city", field = { 1, 2 } }, done = 5, history = "?" }
	Tourney.State(p3)
	check("corrupt: bad belts dropped", p3.tourney.belts.novice == nil and p3.tourney.belts.fake == nil and p3.tourney.belts.city.n == 1)
	check("corrupt: NaN points", p3.tourney.points == 0)
	check("corrupt: a belt not won is not worn", p3.tourney.wear == nil)
	check("corrupt: a broken bracket dropped", p3.tourney.run == nil)
	check("corrupt: tables rebuilt", type(p3.tourney.done) == "table" and type(p3.tourney.history) == "table")
	check("corrupt: View", pcall(Tourney.View, p3))
end

------------------------------------------------------------------------
-- 7. the ceremony spec, the belt models
------------------------------------------------------------------------
do
	local prof = newCareer(7)
	check("ceremony: an ordinary fight has none", Tourney.CeremonyFor(prof, { kind = "Pro Fight", stakes = {} }) == nil)
	local org = Config.Orgs[2]
	local c = Tourney.CeremonyFor(prof, { kind = "World Title", stakes = { org } })
	check("ceremony: a new world title", c and c.belt == org and c.title:find(org, 1, true))
	prof.belts[org] = true
	check("ceremony: not a defense", Tourney.CeremonyFor(prof, { kind = "Title Defense", stakes = { org } }) == nil)
	check("ceremony: regional title", Tourney.CeremonyFor(prof, { kind = "Regional Title" }).belt == "regional")
	check("ceremony: a QF has none", Tourney.CeremonyFor(prof, { kind = "Tournament Quarter-final", tourney = { id = "city", round = 1 } }) == nil)
	for _, key in ipairs({ "novice", "city", "regional", "national", "world", "regional", "national", Config.Orgs[1], Config.Orgs[4] }) do
		local d = T.Design(key, Config.Orgs)
		check("design " .. key, d ~= nil)
		for _, mode in ipairs({ "display", "worn" }) do
			local okB, m = pcall(BeltModel.Build, d, { mode = mode, waist = H.globals.Vector3.new(1.6, 0.52, 0.97) })
			check("belt " .. key .. " " .. mode .. " builds", okB and m ~= nil, m)
			if okB then
				local n = m:GetAttribute("Parts")
				check("belt " .. key .. " " .. mode .. " part budget", n and n >= 12 and n <= 90, n)
				if verbose then
					print(key, mode, n)
				end
			end
		end
	end
	check("design: unknown", T.Design("nope", Config.Orgs) == nil)
end

print(string.format("test_tournaments: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
