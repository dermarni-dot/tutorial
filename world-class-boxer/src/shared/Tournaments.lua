-- Tournaments: the bracket events of the career (data + pure helpers, shared by the server's Tourney module,
-- the Career Hub's Tournaments tab, the belt models and the celebration cutscene). Every name here is
-- fictional.
--
--   * five events, a ladder by career level: an amateur open, a city championship, a regional grand prix, a
--     national cup and an invitational world grand prix for top-ranked pros
--   * each is an 8-boxer single-elimination bracket (quarter-final, semi-final, final) in the player's own
--     division; the field is filled from the world's boxers in that division
--   * each runs on the calendar every `every` days (first on day `offset`); entry opens `window` days before the
--     start (the quarter-finals are fought on the start day), the rounds are `recovery` days apart
--   * prizes by the round reached (`prize` = { lost QF, lost SF, runner-up, winner }), a purse per bout (the tier's
--     purse x `purse[r]`), fame and ranking points per round won (`fame` / `points`), the event's own belt for the
--     winner (`belt`: the design BeltModel builds and TourneyUI draws)
local Tournaments = {}

Tournaments.ROUNDS = 3
Tournaments.ROUND_NAMES = { "Quarter-final", "Semi-final", "Final" }
Tournaments.ROUND_SHORT = { "QF", "SF", "F" }
Tournaments.FIELD = 8
-- bracket slots by seed (1 v 8, 4 v 5, 3 v 6, 2 v 7: the top seeds meet in the final at the earliest)
Tournaments.SEED_SLOTS = { 1, 8, 4, 5, 3, 6, 2, 7 }

-- belt designs: strap / plate / trim colours, the centre plate's shape (round | shield | hexagon | octagon |
-- crown), the emblem on it (glove | tower | star | laurel | globe), side plates per side, the jewel colour
Tournaments.List = {
	{
		id = "novice", name = "Novice Gloves Open", short = "NOVICE OPEN", champion = "NOVICE GLOVES CHAMPION",
		blurb = "The city's amateur open: three bouts in a weekend for the best novices in the division.",
		rule = "Amateurs only", minTier = 1, maxTier = 1,
		every = 14, offset = 4, window = 6, recovery = 1, rounds = 3, venue = "CommunityCenter",
		band = { 26, 44 }, purse = { 1, 1.2, 1.6 }, prize = { 0, 150, 400, 1200 },
		fame = { 1, 1, 3 }, points = { 0, 0, 0 },
		belt = { strap = { 28, 48, 104 }, plate = { 214, 218, 226 }, trim = { 150, 156, 168 }, jewel = { 200, 40, 46 },
			shape = "round", emblem = "glove", sides = 1, label = "NOVICE" },
	},
	{
		id = "city", name = "Riverside City Championship", short = "CITY CHAMPIONSHIP", champion = "CITY CHAMPION",
		blurb = "Eight local pros, one city title. The club arena sells out for the final.",
		rule = "Local pros and regional champions", minTier = 2, maxTier = 3,
		every = 21, offset = 9, window = 8, recovery = 2, rounds = 4, venue = "ClubArena",
		band = { 34, 54 }, purse = { 1, 1.2, 1.6 }, prize = { 1000, 3000, 6000, 15000 },
		fame = { 1, 2, 4 }, points = { 4, 6, 10 },
		belt = { strap = { 150, 22, 32 }, plate = { 204, 128, 66 }, trim = { 120, 70, 34 }, jewel = { 255, 214, 92 },
			shape = "shield", emblem = "tower", sides = 2, label = "CITY" },
	},
	{
		id = "regional", name = "Regional Grand Prix", short = "REGIONAL GP", champion = "REGIONAL GRAND PRIX CHAMPION",
		blurb = "The region's contenders in one bracket: a fast lane to the national scene.",
		rule = "Regional champions to international contenders", minTier = 3, maxTier = 5,
		every = 28, offset = 16, window = 10, recovery = 3, rounds = 6, venue = "ClubArena",
		band = { 44, 64 }, purse = { 1, 1.25, 1.7 }, prize = { 5000, 12000, 25000, 60000 },
		fame = { 2, 3, 6 }, points = { 8, 12, 20 },
		belt = { strap = { 22, 98, 64 }, plate = { 226, 230, 236 }, trim = { 212, 168, 64 }, jewel = { 40, 190, 110 },
			shape = "hexagon", emblem = "star", sides = 2, label = "REGION" },
	},
	{
		id = "national", name = "National Cup", short = "NATIONAL CUP", champion = "NATIONAL CUP CHAMPION",
		blurb = "The country's best in the division, live on national TV.",
		rule = "National champions and ranked contenders", minTier = 4, maxTier = 6,
		every = 35, offset = 23, window = 12, recovery = 4, rounds = 8, venue = "Arena",
		band = { 54, 74 }, purse = { 1, 1.3, 1.8 }, prize = { 20000, 50000, 100000, 250000 },
		fame = { 2, 4, 8 }, points = { 14, 20, 32 },
		belt = { strap = { 74, 32, 124 }, plate = { 240, 196, 80 }, trim = { 168, 120, 30 }, jewel = { 230, 236, 255 },
			shape = "octagon", emblem = "laurel", sides = 3, label = "NATION" },
	},
	{
		id = "world", name = "Apex World Grand Prix", short = "WORLD GRAND PRIX", champion = "WORLD GRAND PRIX CHAMPION",
		blurb = "Invitation only: the division's top-ranked pros in the richest bracket in boxing.",
		rule = "Invitational: a world top 10 ranking (or a title)", minTier = 6, maxTier = 10, invite = 10,
		every = 56, offset = 40, window = 16, recovery = 5, rounds = 10, venue = "Stadium",
		band = { 66, 99 }, purse = { 1, 1.3, 1.9 }, prize = { 100000, 250000, 600000, 2000000 },
		fame = { 3, 5, 10 }, points = { 20, 30, 50 },
		belt = { strap = { 16, 16, 20 }, plate = { 255, 208, 84 }, trim = { 255, 246, 214 }, jewel = { 236, 244, 255 },
			shape = "crown", emblem = "globe", sides = 3, label = "WORLD" },
	},
}
Tournaments.ById = {}
for i, def in ipairs(Tournaments.List) do
	def.index = i
	Tournaments.ById[def.id] = def
end

-- the other title belts, for the cutscene's strapping and the trophy case: the old regional / national belts, and
-- the world titles by their place in Config.Orgs (the label is the org's own key, passed in)
Tournaments.TitleBelts = {
	regional = { strap = { 40, 40, 46 }, plate = { 205, 210, 220 }, trim = { 150, 150, 160 }, jewel = { 196, 30, 36 }, shape = "round", emblem = "star", sides = 1, label = "REGIONAL" },
	national = { strap = { 120, 20, 28 }, plate = { 205, 127, 50 }, trim = { 140, 84, 30 }, jewel = { 255, 214, 92 }, shape = "shield", emblem = "star", sides = 2, label = "NATIONAL" },
}
local WORLD_BELTS = {
	{ strap = { 20, 20, 22 }, shape = "round", emblem = "globe", jewel = { 196, 30, 36 }, sides = 2 },
	{ strap = { 30, 120, 60 }, shape = "round", emblem = "laurel", jewel = { 255, 255, 255 }, sides = 3 },
	{ strap = { 176, 26, 32 }, shape = "shield", emblem = "globe", jewel = { 255, 255, 255 }, sides = 2 },
	{ strap = { 30, 56, 160 }, shape = "octagon", emblem = "globe", jewel = { 255, 255, 255 }, sides = 2 },
}

-- a belt design by key: a tournament id, "regional" / "national", or a world title (orgs = Config.Orgs: the key's
-- place in it picks the design); nil for anything else
function Tournaments.Design(key, orgs)
	local def = Tournaments.ById[key]
	if def then
		return def.belt
	end
	if Tournaments.TitleBelts[key] then
		return Tournaments.TitleBelts[key]
	end
	local i = type(orgs) == "table" and table.find(orgs, key)
	local w = i and WORLD_BELTS[(i - 1) % #WORLD_BELTS + 1]
	if w then
		return { strap = w.strap, plate = { 255, 208, 84 }, trim = { 180, 130, 30 }, jewel = w.jewel, shape = w.shape, emblem = w.emblem, sides = w.sides, label = tostring(key) }
	end
	return nil
end

------------------------------------------------------------------------
-- Calendar
------------------------------------------------------------------------
local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return d
	end
	return v
end

-- the first start day >= day
function Tournaments.NextStart(def, day)
	day = math.floor(num(day, 1))
	if day <= def.offset then
		return def.offset
	end
	return def.offset + math.ceil((day - def.offset) / def.every) * def.every
end

-- the last start day <= day (nil before the first edition)
function Tournaments.LastStart(def, day)
	day = math.floor(num(day, 1))
	if day < def.offset then
		return nil
	end
	return def.offset + math.floor((day - def.offset) / def.every) * def.every
end

-- entry is open from `window` days before the start until the day before it (the QF is on the start day)
function Tournaments.EntryOpen(def, day)
	day = math.floor(num(day, 1))
	local s = Tournaments.NextStart(def, day)
	if s == day then
		-- (today is a start day: too late for this one, the next edition is the one on the calendar)
		s += def.every
	end
	return day >= s - def.window and day < s, s
end

-- the next `n` starts of every event from `day` on, soonest first: { { def, start, open } }
function Tournaments.Calendar(day, n)
	local out = {}
	for _, def in ipairs(Tournaments.List) do
		local open, s = Tournaments.EntryOpen(def, day)
		for k = 0, (n or 2) - 1 do
			table.insert(out, { def = def, start = s + k * def.every, open = k == 0 and open })
		end
	end
	table.sort(out, function(a, b)
		if a.start ~= b.start then
			return a.start < b.start
		end
		return a.def.index < b.def.index
	end)
	return out
end

------------------------------------------------------------------------
-- Bracket helpers (slot indices 1..8; round r's matches pair consecutive survivors)
------------------------------------------------------------------------
-- the boxers of round r (1..3) in bracket order, from the field and the winners lists: round 1 = the field,
-- round r = the winners of round r - 1
function Tournaments.Entrants(run, r)
	if r <= 1 then
		return run.field
	end
	return run.w and run.w[r - 1] or {}
end

-- the match index (1..4 / 1..2 / 1) of position i in a round
function Tournaments.MatchOf(i)
	return math.floor((i - 1) / 2) + 1
end

-- where `id` stands in round r (index into Entrants), or nil when he is out
function Tournaments.PosIn(run, r, id)
	return table.find(Tournaments.Entrants(run, r), id)
end

-- the opponent of `id` in round r (nil when out or no opponent decided yet)
function Tournaments.OpponentIn(run, r, id)
	local list = Tournaments.Entrants(run, r)
	local i = table.find(list, id)
	if not i then
		return nil
	end
	local j = i % 2 == 1 and i + 1 or i - 1
	return list[j]
end

function Tournaments.RoundName(r)
	return Tournaments.ROUND_NAMES[r] or ("Round " .. tostring(r))
end

-- the cutscene's beats (seconds from its start; FightEngine's server timeline and Ceremony's camera share them)
Tournaments.Ceremony = {
	dur = 10.5, -- the whole scene (8-12 s)
	raise = 0.7, -- the referee raises the winner's hand
	walkIn = 2.0, -- the official walks in with the belt
	strap = 3.4, -- the belt goes round the winner's waist
	lift = 5.5, -- the winner lifts it overhead
	wide = 7.6, -- the crowd wide shot, the confetti
}

-- the cutscene's camera at time t (BoxerClient.Ceremony every frame; tools/sim/v9_ceremony.luau's storyboard): four
-- shots with hard cuts. B = the beats, center = the ring centre, face = the way the winner faces (unit, flat), wp /
-- hp = the winner's root / head positions now. -> CFrame, vertical field of view (degrees), shot name
local function smooth01(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
function Tournaments.CeremonyShot(t, B, center, face, wp, hp)
	B = B or Tournaments.Ceremony
	local UP = Vector3.yAxis
	local right = face:Cross(UP)
	if t < B.walkIn then
		-- the winner close-up as the referee raises his hand: a slow push in on the face
		local k = smooth01(t / B.walkIn)
		local from = hp + face * (4.4 - 1.3 * k) + right * (1.1 - 0.4 * k) + UP * 0.15
		return CFrame.lookAt(from, hp - UP * (0.35 + 0.4 * (1 - k))), 50, "closeup"
	elseif t < B.lift then
		-- the orbit while the official walks in and straps the belt on
		local k = (t - B.walkIn) / (B.lift - B.walkIn)
		local a = math.rad(25 + 190 * smooth01(k))
		local dir = face * math.cos(a) + right * math.sin(a)
		local from = center + dir * 10.5 + UP * (4.6 + 1.2 * math.sin(k * math.pi))
		return CFrame.lookAt(from, wp + UP * 0.2), 55, "orbit"
	elseif t < B.wide then
		-- the low hero shot: the belt overhead
		local k = smooth01((t - B.lift) / (B.wide - B.lift))
		local from = wp + face * (5.0 - 0.8 * k) + right * 0.9 - UP * (1.7 - 0.4 * k)
		return CFrame.lookAt(from, hp + UP * 1.1), 52, "hero"
	end
	-- the crowd wide shot over his shoulder, craning up and back
	local k = smooth01((t - B.wide) / math.max(0.5, B.dur - B.wide))
	local from = center - face * (8 + 7 * k) + right * (2.5 + 2 * k) + UP * (5.5 + 4 * k)
	return CFrame.lookAt(from, center + face * 26 + UP * (5 - 2 * k)), 66, "wide"
end

return Tournaments
