-- Entrance: the pre-fight ring walk's rules, shared by the server (RingWalk runs the beats) and the client
-- (EntranceFX films them, AnimEntrance animates them, EntrancePicker lets the player choose).
--   * Entrance.CELEBS / Entrance.ById: the entrance celebrations (walk = done in the tunnel or down the aisle, ring =
--     done in the corner once he is through the ropes; belt = needs a belt he owns)
--   * Entrance.Sanitize(choice) -> { walk1, walk2, ring, carry }: a saved / sent choice made safe (old saves: nil ->
--     the defaults); Entrance.View(profile) -> what the client's picker shows
--   * Entrance.AIPick(personality, belts, seed): an AI boxer's celebrations by his ring personality
--   * Entrance.ShouldCarry(ctx) / Entrance.CarryAfterWin(ctx): when the crowd carries him to the ring (or round the
--     ring after a big win) on their shoulders
--   * Entrance.Plan(ctx): one walk's plan (what the server sends with the "entrance" message)
--   * Entrance.Timeline(plan) -> beats, total: the beats of one walk in seconds from its message. The server waits
--     exactly this long (RingWalk) and the client cuts the camera on the same beats, so the fight starts when it
--     always would have after the last beat, and a skip ends both sides together.
-- Pure: no services, no Instances (tests require it under lune).
local Entrance = {}

------------------------------------------------------------------------
-- The celebrations
------------------------------------------------------------------------
-- dur = how long the gesture runs (s); ringDur = the time the ring beat gives it after he reaches his corner;
-- move = it plays while walking (upper body only); keyed = it owns the legs (AnimEntrance keys them)
Entrance.CELEBS = {
	{ id = "fistpump", name = "Fist Pump", desc = "Throws a glove up to the crowd and pumps it.", walk = true, ring = true, move = true, dur = 1.6, ringDur = 1.4 },
	{ id = "point", name = "Point at the Crowd", desc = "Picks out his fans and points at them.", walk = true, ring = true, move = true, dur = 1.8, ringDur = 1.4 },
	{ id = "shadowbox", name = "Shadowbox", desc = "Throws quick combinations down the aisle.", walk = true, ring = true, move = true, dur = 2.2, ringDur = 1.6 },
	{ id = "chestbeat", name = "Chest Beat", desc = "Pounds his chest with both gloves.", walk = true, ring = true, move = true, dur = 1.6, ringDur = 1.4 },
	{ id = "bow", name = "Gloves-Together Bow", desc = "Touches his gloves together and bows to the room.", walk = true, ring = true, dur = 1.6, ringDur = 1.5 },
	{ id = "shakeout", name = "Hop & Shake Out", desc = "Bounces on his toes and shakes the arms loose.", walk = true, ring = true, dur = 1.6, ringDur = 1.4 },
	{ id = "comeatme", name = "Come at Me", desc = "Arms wide, chest out: bring it on.", walk = true, ring = true, move = true, dur = 1.6, ringDur = 1.4 },
	{ id = "beltlift", name = "Belt Lift", desc = "Raises his championship belt over his head.", walk = true, ring = true, move = true, belt = true, dur = 2.0, ringDur = 1.6 },
	{ id = "stare", name = "Stare-Walk", desc = "A slow, cold walk. Eyes locked on the ring.", walk = true, move = true, dur = 3.0 },
	{ id = "turnitup", name = "Turn It Up", desc = "Palms up, pumping: louder!", walk = true, ring = true, move = true, dur = 1.6, ringDur = 1.4 },
	{ id = "victorylap", name = "Champion's Lap", desc = "Jogs a lap of his corner with a glove raised.", ring = true, keyed = true, dur = 2.2, ringDur = 2.2 },
	{ id = "turnbuckle", name = "Turnbuckle Salute", desc = "Climbs onto the ropes in his corner and salutes.", ring = true, keyed = true, dur = 2.0, ringDur = 2.0 },
}
Entrance.ById = {}
for i, c in ipairs(Entrance.CELEBS) do
	c.order = i
	Entrance.ById[c.id] = c
end
Entrance.WALK, Entrance.RING = {}, {}
for _, c in ipairs(Entrance.CELEBS) do
	if c.walk then
		table.insert(Entrance.WALK, c.id)
	end
	if c.ring then
		table.insert(Entrance.RING, c.id)
	end
end

Entrance.DEFAULT = { walk1 = "fistpump", walk2 = "point", ring = "turnbuckle", carry = true }
Entrance.NONE = "none"

local function valid(id, slot)
	if type(id) ~= "string" or #id > 24 then
		return nil
	end
	local c = Entrance.ById[id]
	if not c then
		return nil
	end
	if slot == "walk" and not c.walk then
		return nil
	end
	if slot == "ring" and not c.ring then
		return nil
	end
	return id
end
Entrance.Valid = valid

-- a choice from a save (nil on an old save) or from the client, made safe: unknown / wrong-slot ids and junk fall
-- back to the defaults, the second walk celebration may be "none" (never the same as the first), carry is on unless
-- it is explicitly false
function Entrance.Sanitize(e)
	e = type(e) == "table" and e or {}
	local D = Entrance.DEFAULT
	local out = {
		walk1 = valid(e.walk1, "walk") or D.walk1,
		walk2 = e.walk2 == Entrance.NONE and Entrance.NONE or (valid(e.walk2, "walk") or D.walk2),
		ring = valid(e.ring, "ring") or D.ring,
		carry = e.carry ~= false,
	}
	if out.walk2 == out.walk1 then
		out.walk2 = Entrance.NONE
	end
	return out
end

-- how many belts a profile holds, read defensively (the world belts, the regional / national titles, and any
-- tournament belts a newer save keeps: a table of truthy values or a list)
function Entrance.BeltCount(profile)
	if type(profile) ~= "table" then
		return 0
	end
	local n = 0
	local function count(t)
		if type(t) ~= "table" then
			return
		end
		for _, v in pairs(t) do
			if v == true or (type(v) == "table" and next(v) ~= nil) or (type(v) == "string" and v ~= "") then
				n += 1
			end
		end
	end
	count(profile.belts)
	count(profile.regional)
	count(profile.tournamentBelts)
	if type(profile.tournaments) == "table" then
		count(profile.tournaments.belts)
	end
	return n
end

-- the picker's view of a profile (Main's summary)
function Entrance.View(profile)
	local p = type(profile) == "table" and profile or {}
	return { choice = Entrance.Sanitize(p.entrance), belts = Entrance.BeltCount(p) }
end

------------------------------------------------------------------------
-- AI picks by ring personality (Config.Personalities); a champion lifts his belt first
------------------------------------------------------------------------
Entrance.AI = {
	["Trash Talker"] = { "comeatme", "point", "chestbeat" },
	["Respectful Veteran"] = { "bow", nil, "fistpump" },
	["Showman"] = { "turnitup", "shadowbox", "turnbuckle" },
	["Silent Assassin"] = { "stare", nil, "shakeout" },
	["Hothead"] = { "chestbeat", "comeatme", "comeatme" },
	["Technician"] = { "shadowbox", nil, "shakeout" },
}
function Entrance.AIPick(personality, belts, seed)
	local row = Entrance.AI[personality]
	if not row then
		-- no known personality: one of the rows by the seed, the same every time for this boxer
		local keys = { "Trash Talker", "Respectful Veteran", "Showman", "Silent Assassin", "Hothead", "Technician" }
		row = Entrance.AI[keys[(math.floor(tonumber(seed) or 0) % #keys) + 1]]
	end
	local pick = { walk1 = row[1], walk2 = row[2] or Entrance.NONE, ring = row[3], carry = false }
	if (tonumber(belts) or 0) > 0 then
		pick.walk2 = pick.walk1 ~= "stare" and pick.walk1 or Entrance.NONE
		pick.walk1 = "beltlift"
	end
	return pick
end

------------------------------------------------------------------------
-- Carried by the crowd
------------------------------------------------------------------------
-- venues with a walkway and a house to carry him (the community centre's aisle is a gym floor with folding chairs)
Entrance.CARRY_VENUES = { ClubArena = true, Arena = true, Stadium = true }
Entrance.CARRY_POP = 75 -- a fan favourite is carried into any fight
Entrance.CARRY_POP_BIG = 50 -- a well-known boxer on a big night (a title fight, or importance >= BIG)
Entrance.CARRY_BIG = 0.8
Entrance.AFTER_WIN_POP = 60 -- carried round the ring after a big non-title win (title wins are the ceremony's)

-- ctx = { popularity 0..100, importance 0..1, title, venue, spar, tutorial, ai, pref (false = the player said no) }
function Entrance.ShouldCarry(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	if ctx.spar or ctx.tutorial or ctx.ai or ctx.pref == false then
		return false
	end
	if not Entrance.CARRY_VENUES[ctx.venue or ""] then
		return false
	end
	local pop = math.clamp(tonumber(ctx.popularity) or 0, 0, 100)
	local imp = math.clamp(tonumber(ctx.importance) or 0, 0, 1)
	if pop >= Entrance.CARRY_POP then
		return true
	end
	return pop >= Entrance.CARRY_POP_BIG and (ctx.title == true or imp >= Entrance.CARRY_BIG)
end

-- after the final bell: ctx as ShouldCarry plus won, method ("KO" / "TKO" / "UD" ...). A title win is the victory
-- ceremony's (another module, another trigger), never this.
function Entrance.CarryAfterWin(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	if not ctx.won or ctx.title or ctx.spar or ctx.tutorial or ctx.ai or ctx.pref == false then
		return false
	end
	if not Entrance.CARRY_VENUES[ctx.venue or ""] then
		return false
	end
	local pop = math.clamp(tonumber(ctx.popularity) or 0, 0, 100)
	local imp = math.clamp(tonumber(ctx.importance) or 0, 0, 1)
	local stoppage = ctx.method == "KO" or ctx.method == "TKO"
	return pop >= Entrance.AFTER_WIN_POP and (stoppage or imp >= 0.6)
end

------------------------------------------------------------------------
-- Plans and the timeline
------------------------------------------------------------------------
-- beat lengths (s). FULL = a player's walk; SHORT = an AI opponent's (no crowd shot, no carry, one walk
-- celebration). setdown only when carried; robe only on the night's last walk (both robes come off then).
-- ring = RING_WALK (to his corner) + the ring celebration's ringDur
Entrance.FULL = { tunnel = 1.6, aisle = 2.6, crowd = 1.2, setdown = 1.0, steps = 1.2, ropes = 0.9, robe = 1.2 }
Entrance.SHORT = { tunnel = 1.0, aisle = 2.0, steps = 1.0, ropes = 0.8 }
Entrance.RING_WALK = 1.1
Entrance.SHORT_RING_MAX = 1.2
Entrance.LEAD = 0.5 -- before the first walk (the commentary line)
Entrance.SPEED = { walk = 9, carried = 7, short = 10, ring = 8 }

-- ctx = { corner "Red"|"Blue", ai, short, choice (sanitized) | nil (AI: AIPick), personality, seed, belts, popularity,
-- importance, title, venue, spar, tutorial, last, pyro }
function Entrance.Plan(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	local belts = math.max(0, math.floor(tonumber(ctx.belts) or 0))
	local choice = ctx.ai and Entrance.AIPick(ctx.personality, belts, ctx.seed) or Entrance.Sanitize(ctx.choice)
	local short = ctx.ai == true or ctx.short == true
	-- the belt lift needs a belt: without one he pumps a fist instead (the choice is kept for when he wins one)
	local function resolve(id)
		if id == "beltlift" and belts <= 0 then
			return "fistpump"
		end
		return id
	end
	local walk = { resolve(choice.walk1) }
	if not short and choice.walk2 ~= Entrance.NONE then
		local w2 = resolve(choice.walk2)
		if w2 ~= walk[1] then
			table.insert(walk, w2)
		end
	end
	local ring = resolve(choice.ring)
	local carryCtx = { popularity = ctx.popularity, importance = ctx.importance, title = ctx.title, venue = ctx.venue, spar = ctx.spar,
		tutorial = ctx.tutorial, ai = ctx.ai, pref = choice.carry }
	local carry = (not short) and Entrance.ShouldCarry(carryCtx)
	local plan = {
		corner = ctx.corner == "Blue" and "Blue" or "Red",
		short = short, ai = ctx.ai == true, carry = carry, walk = walk, ring = ring,
		last = ctx.last == true, venue = ctx.venue, pyro = ctx.pyro == true, title = ctx.title == true,
		popularity = math.clamp(tonumber(ctx.popularity) or 0, 0, 100), importance = math.clamp(tonumber(ctx.importance) or 0, 0, 1),
		belt = belts > 0 and (walk[1] == "beltlift" or walk[2] == "beltlift" or ring == "beltlift"),
		pref = choice.carry, seed = math.floor(tonumber(ctx.seed) or 0),
	}
	plan.speed = short and Entrance.SPEED.short or (carry and Entrance.SPEED.carried or Entrance.SPEED.walk)
	-- eligible for the post-win carry (the client checks the result: Entrance.CarryAfterWin)
	plan.afterWin = Entrance.CarryAfterWin({ won = true, method = "KO", popularity = plan.popularity, importance = 1, title = plan.title,
		venue = plan.venue, spar = ctx.spar, tutorial = ctx.tutorial, ai = ctx.ai, pref = choice.carry })
	return plan
end

-- the ring beat's length: the walk to the corner and the celebration
function Entrance.RingTime(plan)
	local c = Entrance.ById[plan.ring] or Entrance.ById.fistpump
	local d = c.ringDur or 1.4
	if plan.short then
		d = math.min(d, Entrance.SHORT_RING_MAX)
	end
	return Entrance.RING_WALK + d
end

-- beats = { { id, t0, t1 } ... } in order, total = the walk's length. Shots and moves key off the ids:
-- tunnel (the reveal at the stage), aisle (tracking), crowd (the crowd shot), setdown (carried: put down at the
-- steps), steps (the climb), ropes (through the ropes), ring (to the corner + the ring celebration), robe
function Entrance.Timeline(plan)
	plan = type(plan) == "table" and plan or {}
	local D = plan.short and Entrance.SHORT or Entrance.FULL
	local order = { "tunnel", "aisle" }
	if not plan.short then
		table.insert(order, "crowd")
		if plan.carry then
			table.insert(order, "setdown")
		end
	end
	table.insert(order, "steps")
	table.insert(order, "ropes")
	table.insert(order, "ring")
	if plan.last then
		table.insert(order, "robe")
	end
	local beats, t = {}, 0
	for _, id in ipairs(order) do
		local d = id == "ring" and Entrance.RingTime(plan) or (D[id] or Entrance.FULL[id] or 1)
		table.insert(beats, { id = id, t0 = t, t1 = t + d })
		t += d
	end
	return beats, t
end

-- the beat at time el (s from the walk's start): beat, its index, seconds into it (nil past the end)
function Entrance.BeatAt(beats, el)
	for i, b in ipairs(beats) do
		if el < b.t1 then
			return b, i, math.max(0, el - b.t0)
		end
	end
	return nil
end

-- when each celebration plays inside a walk: { { id, t0, t1, beat } } (s from the walk's start)
function Entrance.Celebrations(plan, beats)
	local out = {}
	local function at(id)
		for _, b in ipairs(beats) do
			if b.id == id then
				return b
			end
		end
		return nil
	end
	local tb, ab, rb = at("tunnel"), at("aisle"), at("ring")
	if tb and plan.walk[1] then
		local c = Entrance.ById[plan.walk[1]]
		if c.id == "stare" then
			-- the stare is the whole walk's attitude: tunnel and aisle
			local e = at("crowd") or ab or tb
			table.insert(out, { id = c.id, t0 = tb.t0 + 0.15, t1 = e.t1, beat = "tunnel" })
		else
			table.insert(out, { id = c.id, t0 = tb.t0 + 0.15, t1 = math.min(tb.t1 + 0.3, tb.t0 + 0.15 + c.dur), beat = "tunnel" })
		end
	end
	if ab and plan.walk[2] then
		local c = Entrance.ById[plan.walk[2]]
		local e = at("crowd") or ab
		local t0 = ab.t0 + 0.5
		table.insert(out, { id = c.id, t0 = t0, t1 = c.id == "stare" and e.t1 or math.min(e.t1, t0 + c.dur), beat = "aisle" })
	end
	if rb then
		local c = Entrance.ById[plan.ring] or Entrance.ById.fistpump
		table.insert(out, { id = c.id, t0 = rb.t0 + Entrance.RING_WALK, t1 = rb.t1, beat = "ring" })
	end
	return out
end

-- the whole entrance on the server: the lead, the opponent's walk, the player's walk
function Entrance.Total(planFirst, planLast)
	local _, a = Entrance.Timeline(planFirst)
	local _, b = Entrance.Timeline(planLast)
	return Entrance.LEAD + a + b
end

return Entrance
