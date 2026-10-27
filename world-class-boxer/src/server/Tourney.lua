-- Tourney: the career side of the tournaments (Shared.Tournaments has the events, their rules, prizes and belts).
--
-- Saved lazily as profile.tourney (an old save has none; nothing here bumps Config.DataVersion):
--   { belts = { [id] = { n = wins, last = day } },   the tournament belts won (the trophy case, the FighterCard)
--     points = n,                                    ranking points (World.PlayerScore adds them)
--     wear = id | nil,                               the belt worn in ring walks
--     run = { ... } | nil,                           the bracket being fought (below)
--     done = { [id] = start day },                   the last edition of each event already settled
--     history = { { id, ed, place, day, prize } } }  the player's finishes, newest last (capped)
-- and in the world: world.tourney = { holders = { [id] = { id = boxer id | "player", name, day, ci } },
--   log = { { t = id, ed, ci, winner, name, runnerUp, day } } } (AI editions and the player's alike, capped)
--
-- A run: { id, ed (the start day), ci, field = { 8 ids in bracket order, "player" among them }, seeds = { [id] = n },
--   w = { [r] = { winners of round r in bracket order } }, m = { [r] = { { a, b, win, method } } }, round = 1..3,
--   wear = { head, body } (0..40: what the last bout took out of him, recovered `heal` a day), prize = paid so far,
--   status = "active" }
-- The run's bouts are ordinary camps (profile.camp, offer.tourney = { id, ed, round }) fought through the normal
-- fight path; Career.ApplyResult hands each result to Tourney.AfterResult, which resolves the AI side of the round
-- (World.AIBout) and books the next round `recovery` days later, or ends the run (a loss, a withdrawal, the title).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local T = require(Shared:WaitForChild("Tournaments"))
local World = require(script.Parent.World)

local Tourney = {}
local rng = Random.new()

-- Career hands over its offer builder (makeOffer: purse, venue, opponent view, trash talk) at load
Tourney.makeOffer = nil

local HISTORY_MAX = 24
local LOG_MAX = 40
-- wear per bout (0..WEAR_MAX on each of head / body) and what a recovery day heals of it
local WEAR_MAX, WEAR_HEAL = 40, 8

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return d
	end
	return v
end

------------------------------------------------------------------------
-- State (old saves: created on first use; corrupt pieces dropped)
------------------------------------------------------------------------
function Tourney.State(profile)
	local s = profile.tourney
	if type(s) ~= "table" then
		s = {}
		profile.tourney = s
	end
	if type(s.belts) ~= "table" then
		s.belts = {}
	end
	for id, b in pairs(s.belts) do
		if not T.ById[id] or type(b) ~= "table" or not num(b.n, nil) or b.n < 1 then
			s.belts[id] = nil
		else
			b.n = math.floor(b.n)
			b.last = math.floor(num(b.last, 1))
		end
	end
	s.points = math.max(0, num(s.points, 0))
	if s.wear ~= nil and not (T.ById[s.wear] and s.belts[s.wear]) then
		s.wear = nil
	end
	if type(s.done) ~= "table" then
		s.done = {}
	end
	if type(s.history) ~= "table" then
		s.history = {}
	end
	local r = s.run
	if r ~= nil then
		if type(r) ~= "table" or not T.ById[r.id] or type(r.field) ~= "table" or #r.field ~= T.FIELD or not table.find(r.field, "player") then
			s.run = nil
		else
			r.w = type(r.w) == "table" and r.w or {}
			r.m = type(r.m) == "table" and r.m or {}
			r.round = math.clamp(math.floor(num(r.round, 1)), 1, T.ROUNDS)
			r.wear = type(r.wear) == "table" and r.wear or {}
			r.wear.head = math.clamp(num(r.wear.head, 0), 0, WEAR_MAX)
			r.wear.body = math.clamp(num(r.wear.body, 0), 0, WEAR_MAX)
			r.prize = num(r.prize, 0)
		end
	end
	return s
end

local function worldState(world)
	local w = world.tourney
	if type(w) ~= "table" then
		w = {}
		world.tourney = w
	end
	if type(w.holders) ~= "table" then
		w.holders = {}
	end
	if type(w.log) ~= "table" then
		w.log = {}
	end
	return w
end
Tourney.WorldState = worldState

------------------------------------------------------------------------
-- Entry rules
------------------------------------------------------------------------
-- -> ok, reason (the rule the player misses)
function Tourney.Eligible(profile, def)
	if type(def) == "string" then
		def = T.ById[def]
	end
	if not def then
		return false, "Unknown tournament."
	end
	if profile.retired then
		return false, "You're retired."
	end
	local tier = num(profile.tier, 1)
	if def.invite then
		local best = World.BestRank(profile)
		local champ = false
		for _, has in pairs(type(profile.belts) == "table" and profile.belts or {}) do
			champ = champ or has == true
		end
		if not champ and best > def.invite then
			return false, string.format("Invitation only: a world top %d ranking or a world title.", def.invite)
		end
		if tier < 5 then
			return false, "Invitation only: international contenders and up."
		end
		return true
	end
	if tier < def.minTier or tier > def.maxTier then
		return false, def.rule .. " (" .. (Config.Tiers[def.minTier] and Config.Tiers[def.minTier].name or "") ..
			(def.maxTier ~= def.minTier and (" to " .. (Config.Tiers[def.maxTier] and Config.Tiers[def.maxTier].name or "")) or "") .. ")."
	end
	return true
end

------------------------------------------------------------------------
-- The field
------------------------------------------------------------------------
local function activeIds(world, ci)
	local out = {}
	for _, id in ipairs(world.classes[ci] or {}) do
		local b = world.boxers[id]
		if b and not b.retired then
			table.insert(out, id)
		end
	end
	return out
end

-- n AI boxers of class ci for an event: inside its overall band (widened when the division is thin), the best
-- ranked ones for an invitational; never the ids in `exclude`
local function pickField(profile, def, ci, n, exclude, r)
	local world = profile.world
	local pool = activeIds(world, ci)
	local out = {}
	if def.invite then
		-- the division's best by ranking score (the world's own: World.Score over the orgs)
		table.sort(pool, function(a, b)
			local sa, sb = 0, 0
			for _, org in ipairs(Config.Orgs) do
				sa += World.Score(world.boxers[a], org)
				sb += World.Score(world.boxers[b], org)
			end
			return sa > sb
		end)
		for _, id in ipairs(pool) do
			if #out >= n then
				break
			end
			if not (exclude and exclude[id]) then
				table.insert(out, id)
			end
		end
		return out
	end
	for widen = 0, 40, 4 do
		table.clear(out)
		local lo, hi = def.band[1] - widen, def.band[2] + widen
		for _, id in ipairs(pool) do
			local b = world.boxers[id]
			if b.overall >= lo and b.overall <= hi and not (exclude and exclude[id]) then
				table.insert(out, id)
			end
		end
		if #out >= n then
			break
		end
	end
	-- n at random from the band
	for i = #out, 2, -1 do
		local j = r:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	while #out > n do
		table.remove(out)
	end
	return out
end

-- seed the 8 by overall (the player by his own) and lay them into the bracket: { ids in slot order }, seeds
local function seedBracket(profile, ids)
	local world = profile.world
	local function ovr(id)
		if id == "player" then
			return num(profile.overall, 40)
		end
		local b = world.boxers[id]
		return b and b.overall or 0
	end
	local sorted = table.clone(ids)
	table.sort(sorted, function(a, b)
		local oa, ob = ovr(a), ovr(b)
		if oa ~= ob then
			return oa > ob
		end
		return tostring(a) < tostring(b)
	end)
	local field, seeds = {}, {}
	for seed, id in ipairs(sorted) do
		seeds[id] = seed
		local slot = table.find(T.SEED_SLOTS, seed)
		field[slot] = id
	end
	return field, seeds
end
Tourney.SeedBracket = seedBracket

-- the AI bout of a bracket (World.AIBout, no draws: the judges' tiebreak picks a winner) -> winner id, method
local function aiMatch(profile, a, b, r)
	local world = profile.world
	local A, B = world.boxers[a], world.boxers[b]
	if not A then
		return b, "W/O"
	elseif not B then
		return a, "W/O"
	end
	local winner, _, ko = World.AIBout(A, B, r, true)
	return winner.id, ko and (r:NextNumber() < 0.5 and "KO" or "TKO") or (r:NextNumber() < 0.75 and "UD" or "SD")
end
Tourney.AIMatch = aiMatch

-- resolve every match of round r not yet decided (the player's is left alone unless `withPlayer`); fills run.w[r]
local function resolveRound(profile, run, r, rr, withPlayer)
	local list = T.Entrants(run, r)
	run.m[r] = run.m[r] or {}
	run.w[r] = run.w[r] or {}
	for k = 1, #list // 2 do
		local a, b = list[2 * k - 1], list[2 * k]
		if not run.w[r][k] then
			local isPlayer = a == "player" or b == "player"
			if isPlayer and withPlayer then
				-- the player withdrew: his opponent goes through on a walkover
				local other = a == "player" and b or a
				run.w[r][k] = other
				run.m[r][k] = { a = a, b = b, win = other, method = "W/O" }
			elseif not isPlayer then
				local win, method = aiMatch(profile, a, b, rr)
				run.w[r][k] = win
				run.m[r][k] = { a = a, b = b, win = win, method = method }
			end
		end
	end
end

local function nameOf(profile, id)
	if id == "player" then
		return profile.identity and profile.identity.name or "You"
	end
	local b = profile.world.boxers[id]
	return b and b.name or "?"
end

-- the champion of a finished bracket on the world's books (holders + the log); an AI winner gets the belt count
local function crown(profile, def, ed, ci, winner, runnerUp)
	local W = worldState(profile.world)
	local prev = W.holders[def.id]
	W.holders[def.id] = { id = winner, name = nameOf(profile, winner), day = ed, ci = ci }
	if winner ~= "player" then
		local b = profile.world.boxers[winner]
		if b then
			b.tbelts = type(b.tbelts) == "table" and b.tbelts or {}
			b.tbelts[def.id] = (tonumber(b.tbelts[def.id]) or 0) + 1
		end
	end
	table.insert(W.log, { t = def.id, ed = ed, ci = ci, winner = winner, name = nameOf(profile, winner), runnerUp = runnerUp and nameOf(profile, runnerUp) or nil, day = ed })
	while #W.log > LOG_MAX do
		table.remove(W.log, 1)
	end
	return prev
end

-- a whole edition fought by the AI in the player's division (he did not enter): the world's champion of it
local function simulateEdition(profile, def, ed, r)
	local ci = profile.physical.weightClass
	local ids = pickField(profile, def, ci, T.FIELD, nil, r)
	if #ids < T.FIELD then
		return nil
	end
	local field = seedBracket(profile, ids)
	local run = { field = field, w = {}, m = {} }
	for round = 1, T.ROUNDS do
		resolveRound(profile, run, round, r, false)
	end
	local champ = run.w[T.ROUNDS][1]
	local final = run.m[T.ROUNDS][1]
	crown(profile, def, ed, ci, champ, final and (final.win == final.a and final.b or final.a))
	return champ, run
end
Tourney.SimulateEdition = simulateEdition

-- the calendar moves on: every edition that started on or before today and that the player is not fighting is
-- settled by the AI (only the latest edition of each event: a long gap does not replay months of brackets). A new
-- career gets last season's champions on the first call. Idempotent; returns how many editions were settled.
function Tourney.Tick(profile, r)
	if type(profile) ~= "table" or not profile.created or type(profile.world) ~= "table" then
		return 0
	end
	r = r or rng
	local s = Tourney.State(profile)
	local n = 0
	for _, def in ipairs(T.List) do
		local last = T.LastStart(def, profile.day)
		local ed = last or (def.offset - def.every) -- (before the first edition: last season's)
		local running = s.run and s.run.id == def.id and s.run.ed == ed
		if s.done[def.id] ~= ed and not running and (num(s.done[def.id], -math.huge) < ed) then
			if simulateEdition(profile, def, ed, r) then
				n += 1
			end
			s.done[def.id] = ed
		end
	end
	return n
end

------------------------------------------------------------------------
-- The bouts
------------------------------------------------------------------------
local function boutOffer(profile, def, run)
	local r = run.round
	local oppId = T.OpponentIn(run, r, "player")
	local b = oppId and profile.world.boxers[oppId]
	if not (b and Tourney.makeOffer) then
		return nil
	end
	local offer = Tourney.makeOffer(profile, b, "Tournament " .. T.RoundName(r), { purseMult = def.purse[r] or 1 })
	offer.rounds = def.rounds
	offer.venue = def.venue
	offer.venueName = Config.Venues[def.venue] and Config.Venues[def.venue].name or offer.venueName
	offer.tourney = { id = def.id, ed = run.ed, round = r, name = def.name, roundName = T.RoundName(r), seed = run.seeds and run.seeds[oppId] or nil }
	-- (a final is fought for the event's belt: the Hub marks it FOR THE BELT, Tourney.CeremonyFor plays the cutscene)
	offer.tourneyBelt = r == T.ROUNDS and def.id or nil
	return offer
end

-- enter the event that is open now: builds the bracket and books the quarter-final as a camp. -> ok, err | info
function Tourney.Enter(profile, id)
	local def = T.ById[tostring(id)]
	if not def then
		return false, "Unknown tournament."
	end
	if profile.camp then
		return false, "You already have a fight booked."
	end
	local ok, why = Tourney.Eligible(profile, def)
	if not ok then
		return false, why
	end
	local open, start = T.EntryOpen(def, profile.day)
	if not open then
		return false, string.format("Entries open on day %d (the %s starts on day %d).", start - def.window, def.name, start)
	end
	local s = Tourney.State(profile)
	if s.run then
		return false, "Finish your tournament first."
	end
	local ci = profile.physical.weightClass
	local ids = pickField(profile, def, ci, T.FIELD - 1, nil, rng)
	if #ids < T.FIELD - 1 then
		return false, "Not enough boxers in your division for a bracket."
	end
	table.insert(ids, "player")
	local field, seeds = seedBracket(profile, ids)
	local run = { id = def.id, ed = start, ci = ci, field = field, seeds = seeds, w = {}, m = {}, round = 1, wear = { head = 0, body = 0 }, prize = 0,
		status = "active", entered = profile.day }
	s.run = run
	local offer = boutOffer(profile, def, run)
	if not offer then
		s.run = nil
		return false, "The bracket could not be drawn."
	end
	local days = math.max(1, start - profile.day)
	profile.camp = { offer = offer, daysLeft = days, daysTotal = days, log = {}, tourney = def.id }
	profile.offers = nil
	return true, { name = def.name, start = start, seed = seeds.player, opp = offer.opp.name }
end

-- the run's end: the prize for the round reached, the history line, the champion on the books
local function finish(profile, def, run, place, notes, res)
	local s = Tourney.State(profile)
	local prize = def.prize[place] or 0
	if prize > 0 then
		profile.money += prize
		run.prize += prize
	end
	local finalM = run.m[T.ROUNDS] and run.m[T.ROUNDS][1]
	local champ = run.w[T.ROUNDS] and run.w[T.ROUNDS][1]
	if champ then
		crown(profile, def, run.ed, run.ci, champ, finalM and (finalM.win == finalM.a and finalM.b or finalM.a))
	end
	local placeText = ({ "Quarter-finalist", "Semi-finalist", "Runner-up", "CHAMPION" })[place]
	table.insert(s.history, { id = def.id, ed = run.ed, place = place, day = profile.day, prize = run.prize, how = res })
	while #s.history > HISTORY_MAX do
		table.remove(s.history, 1)
	end
	if prize > 0 then
		table.insert(notes, string.format("%s prize money (%s): %s.", def.name, placeText, Config.Money(prize)))
	end
	s.done[def.id] = run.ed
	s.run = nil
	return place
end

-- the player's bout of round r is over (Career.ApplyResult, before the recovery days pass). -> info =
-- { continuing, recovery, nextCamp, won (the event), place, belt } (nil when the offer is not this run's)
function Tourney.AfterResult(profile, offer, res, notes)
	local tag = type(offer) == "table" and offer.tourney
	local s = Tourney.State(profile)
	local run = s.run
	local def = tag and T.ById[tag.id]
	if not (def and run and run.id == tag.id and run.ed == tag.ed and run.round == tag.round) then
		return nil
	end
	local r = run.round
	local won = res.outcome == "win"
	if res.outcome == "draw" then
		-- (no draws in a bracket: the tournament rule sends the busier man through)
		won = num(res.landed, 0) >= num(res.oppLanded, 0)
		table.insert(notes, won and "A draw on the cards: you go through on punches landed (tournament rule)."
			or "A draw on the cards: your opponent goes through on punches landed (tournament rule).")
	end
	local oppId = T.OpponentIn(run, r, "player")
	local pos = T.PosIn(run, r, "player")
	local k = T.MatchOf(pos)
	run.m[r] = run.m[r] or {}
	run.w[r] = run.w[r] or {}
	run.w[r][k] = won and "player" or oppId
	run.m[r][k] = { a = T.Entrants(run, r)[2 * k - 1], b = T.Entrants(run, r)[2 * k], win = run.w[r][k], method = res.method }
	resolveRound(profile, run, r, rng, false)
	-- fame and ranking points for each round won
	if won then
		profile.popularity = math.clamp(num(profile.popularity, 0) + (def.fame[r] or 0), 0, 100)
		s.points += def.points[r] or 0
	end
	local info = { place = nil }
	if not won then
		-- out: the remaining rounds go on without him
		for rr = r + 1, T.ROUNDS do
			resolveRound(profile, run, rr, rng, false)
		end
		local place = r -- (lost the QF = 1, the SF = 2, the final = 3)
		info.place = finish(profile, def, run, place, notes, "lost")
		table.insert(notes, string.format("Out of the %s in the %s.", def.name, T.RoundName(r):lower()))
		return info
	end
	if r == T.ROUNDS then
		-- the title
		local b = s.belts[def.id] or { n = 0 }
		b.n += 1
		b.last = profile.day
		s.belts[def.id] = b
		if not s.wear then
			s.wear = def.id
		end
		info.won, info.belt = true, def.id
		info.place = finish(profile, def, run, 4, notes, "won")
		table.insert(notes, 1, string.format("%s! You win the %s and its belt.", def.champion, def.name))
		profile.titlesWonT = (tonumber(profile.titlesWonT) or 0) + 1
		return info
	end
	-- through to the next round: what the bout took out of him carries over (less what the days heal)
	local head = math.clamp(num(res.headTaken, num(res.damageTaken, 0) * 0.5) * 0.35, 0, WEAR_MAX)
	local body = math.clamp(num(res.bodyTaken, 0) * 0.5, 0, WEAR_MAX)
	run.wear.head = math.clamp(math.max(run.wear.head - WEAR_HEAL * def.recovery, 0) + head, 0, WEAR_MAX)
	run.wear.body = math.clamp(math.max(run.wear.body - WEAR_HEAL * def.recovery, 0) + body, 0, WEAR_MAX)
	run.round = r + 1
	local offerNext = boutOffer(profile, def, run)
	if not offerNext then
		-- (the next opponent is gone from the world: a walkover is not a fight; the run ends here as a finalist)
		info.place = finish(profile, def, run, r + 1, notes, "walkover")
		return info
	end
	info.continuing = true
	info.recovery = def.recovery
	info.nextCamp = { offer = offerNext, daysLeft = def.recovery, daysTotal = def.recovery, log = {}, tourney = def.id }
	table.insert(notes, string.format("Through to the %s of the %s: %s in %d day%s.", T.RoundName(r + 1):lower(), def.name, offerNext.opp.name,
		def.recovery, def.recovery == 1 and "" or "s"))
	if run.wear.head + run.wear.body > 15 then
		table.insert(notes, string.format("You carry the last bout into the next one: %d%% head, %d%% body still to recover.", math.floor(run.wear.head), math.floor(run.wear.body)))
	end
	return info
end

-- after the recovery days passed (Career.ApplyResult): the doctor's look before the next round. A concussion
-- ends the run (a medical withdrawal). -> true when he was withdrawn
function Tourney.MedicalCheck(profile, concussed, notes)
	local s = Tourney.State(profile)
	local run = s.run
	if not run or not concussed then
		return false
	end
	Tourney.Withdraw(profile, notes, "medical")
	return true
end

-- pull out of the running tournament (between rounds): the next opponent goes through on a walkover, the prize is
-- the round reached. -> ok, err
function Tourney.Withdraw(profile, notes, why)
	notes = notes or {}
	local s = Tourney.State(profile)
	local run = s.run
	if not run then
		return false, "You're not in a tournament."
	end
	local def = T.ById[run.id]
	local r = run.round
	resolveRound(profile, run, r, rng, true)
	for rr = r + 1, T.ROUNDS do
		resolveRound(profile, run, rr, rng, false)
	end
	finish(profile, def, run, r, notes, why == "medical" and "medical" or "withdrew")
	table.insert(notes, why == "medical" and string.format("The doctor withdraws you from the %s: you're concussed.", def.name)
		or string.format("You withdrew from the %s.", def.name))
	if profile.camp and type(profile.camp.offer) == "table" and type(profile.camp.offer.tourney) == "table" then
		profile.camp = nil
	end
	return true
end

------------------------------------------------------------------------
-- Fight night helpers
------------------------------------------------------------------------
-- the carried wear as the fight engine reads it (FighterFromProfile: data.carry = { head, body } as 0..1 caps)
function Tourney.Carry(profile)
	local s = type(profile.tourney) == "table" and profile.tourney
	local run = s and s.run
	local camp = profile.camp
	if not (run and camp and type(camp.offer) == "table" and type(camp.offer.tourney) == "table" and camp.offer.tourney.id == run.id) then
		return nil
	end
	local h, b = num(run.wear and run.wear.head, 0), num(run.wear and run.wear.body, 0)
	if h <= 0 and b <= 0 then
		return nil
	end
	return { head = 1 - h / 100, body = 1 - b / 100 }
end

-- the belt he wears in ring walks (a tournament id), nil for none
function Tourney.WornBelt(profile)
	local s = type(profile.tourney) == "table" and profile.tourney
	local id = s and s.wear
	if id and T.ById[id] and type(s.belts) == "table" and s.belts[id] then
		return id
	end
	return nil
end

function Tourney.SetWear(profile, id)
	local s = Tourney.State(profile)
	if id == nil or id == false or id == "" then
		s.wear = nil
		return true
	end
	id = tostring(id)
	if not (T.ById[id] and s.belts[id]) then
		return false, "You haven't won that belt."
	end
	s.wear = id
	return true
end

-- the celebration cutscene for a bout, if he wins it: a tournament final, or a title the player does not hold yet
-- (world title stakes, the regional / national title). -> spec for FightEngine.Run (opts.ceremony) or nil
function Tourney.CeremonyFor(profile, offer)
	if type(offer) ~= "table" then
		return nil
	end
	local name = profile.identity and profile.identity.name or ""
	local tag = offer.tourney
	if type(tag) == "table" and tag.round == T.ROUNDS and T.ById[tag.id] then
		local def = T.ById[tag.id]
		return { belt = def.id, kicker = "AND THE NEW...", title = def.champion, event = def.name, name = name, kind = "tourney" }
	end
	local stakes = type(offer.stakes) == "table" and offer.stakes or {}
	for _, org in ipairs(stakes) do
		if not (type(profile.belts) == "table" and profile.belts[org]) then
			return { belt = org, kicker = "AND THE NEW...", title = org .. " WORLD CHAMPION", event = (offer.kind or "World Title"), name = name, kind = "title" }
		end
	end
	if offer.kind == "Regional Title" then
		return { belt = "titleRegional", kicker = "AND THE NEW...", title = "REGIONAL CHAMPION", event = "Regional Title", name = name, kind = "title" }
	elseif offer.kind == "National Title" then
		return { belt = "titleNational", kicker = "AND THE NEW...", title = "NATIONAL CHAMPION", event = "National Title", name = name, kind = "title" }
	end
	return nil
end

------------------------------------------------------------------------
-- Client view (Career.Summary: P.tourney)
------------------------------------------------------------------------
local function boxerView(profile, id, seeds)
	if id == nil then
		return nil
	end
	if id == "player" then
		return { id = "player", name = profile.identity.name, nat = profile.identity.nationality, overall = math.floor(num(profile.overall, 0)), you = true,
			seed = seeds and seeds.player or nil, record = profile.tier == 1 and profile.amateurRecord or profile.record }
	end
	local b = profile.world.boxers[id]
	if not b then
		return { id = id, name = "?", overall = 0 }
	end
	return { id = id, name = b.name, nat = b.nat, overall = math.floor(b.overall), seed = seeds and seeds[id] or nil, record = b.record }
end

function Tourney.View(profile)
	local s = Tourney.State(profile)
	local W = worldState(profile.world)
	local list = {}
	for _, def in ipairs(T.List) do
		local open, start = T.EntryOpen(def, profile.day)
		local ok, why = Tourney.Eligible(profile, def)
		local h = W.holders[def.id]
		table.insert(list, {
			id = def.id, name = def.name, short = def.short, blurb = def.blurb, rule = def.rule, rounds = def.rounds, recovery = def.recovery,
			start = start, opens = start - def.window, open = open, eligible = ok, why = why,
			prize = def.prize, venue = Config.Venues[def.venue] and Config.Venues[def.venue].name or def.venue,
			holder = h and { name = h.name, you = h.id == "player", day = h.day } or nil,
			won = s.belts[def.id] and s.belts[def.id].n or 0,
		})
	end
	local run
	if s.run then
		local R = s.run
		local def = T.ById[R.id]
		local rounds = {}
		for r = 1, T.ROUNDS do
			local entrants = T.Entrants(R, r)
			local matches = {}
			for k = 1, T.FIELD / 2 ^ r do
				local a, b = entrants[2 * k - 1], entrants[2 * k]
				local m = R.m[r] and R.m[r][k]
				table.insert(matches, { a = boxerView(profile, a, R.seeds), b = boxerView(profile, b, R.seeds), win = m and m.win or nil, method = m and m.method or nil })
			end
			rounds[r] = matches
		end
		run = { id = R.id, name = def.name, ed = R.ed, round = R.round, roundName = T.RoundName(R.round), rounds = rounds,
			wear = { head = math.floor(R.wear.head), body = math.floor(R.wear.body) }, prize = R.prize, seed = R.seeds and R.seeds.player }
	end
	local belts = {}
	for _, def in ipairs(T.List) do
		local b = s.belts[def.id]
		if b then
			table.insert(belts, { id = def.id, name = def.name, n = b.n, last = b.last })
		end
	end
	local hist = {}
	for i = #s.history, math.max(1, #s.history - 7), -1 do
		local e = s.history[i]
		local def = T.ById[e.id]
		table.insert(hist, { id = e.id, name = def and def.name or e.id, place = e.place, day = e.day, prize = e.prize, how = e.how })
	end
	local log = {}
	for i = #W.log, math.max(1, #W.log - 5), -1 do
		local e = W.log[i]
		local def = T.ById[e.t]
		if def and e.ci == profile.physical.weightClass then
			table.insert(log, { id = e.t, name = def.name, winner = e.name, runnerUp = e.runnerUp, day = e.day, you = e.winner == "player" })
		end
	end
	return { list = list, run = run, belts = belts, wear = Tourney.WornBelt(profile), points = s.points, history = hist, log = log, day = profile.day }
end

-- the ids the career still points at (World.Prune keeps them): the running bracket and the belt holders
function Tourney.Referenced(profile, mark)
	local s = type(profile.tourney) == "table" and profile.tourney
	if s and type(s.run) == "table" and type(s.run.field) == "table" then
		for _, id in ipairs(s.run.field) do
			mark(id)
		end
	end
	local W = type(profile.world) == "table" and type(profile.world.tourney) == "table" and profile.world.tourney
	if W and type(W.holders) == "table" then
		for _, h in pairs(W.holders) do
			if type(h) == "table" then
				mark(h.id)
			end
		end
	end
end

return Tourney
