-- Traits: the AI boxers' ring traits (resistances to a way of fighting), the scouting of them, and the player's
-- "fighting type" (what he actually does in a fight). Shared and pure (no Roblox services): FightEngine applies
-- the effects, FightAI leans on them, the offer card / boxer card / tale of the tape show the scouting, and
-- tools/sim/test_fightai checks the numbers.
--
-- WHO HAS WHAT. Traits come from the boxer's seed (a hash of his id) and his style / archetype, and their count
-- and strength from his level (overall): under MIN_OVERALL none, then one for some, one for most, and two for
-- the elite (Traits.COUNT). Each trait's strength s = 0.35 + 0.65 x the level share (40 -> 90 overall), in
-- steps of 0.05; every effect is its trait's `max` x s and every kind of effect is capped (Traits.CAP) however
-- the traits stack, so a fight stays winnable: a trait takes a slice off one way of fighting, never all of it.
--
-- THE TRAITS (effect at full strength; the counter is the way round it):
--   IronChin           power head shots (cross, hooks, uppercut, overhand) -30% head damage, -35% knockdown odds.
--                      Cracks as his body goes (the effect scales down with his body HP and his gas).
--                      Counter: go to the body; jabs and volume still score.
--   BodyArmor          body shots -35% body damage and -35% of the stamina they drain. Counter: head-hunt,
--                      uppercuts and the jab up top.
--   Slick              straights to the head -14 points of accuracy. Not for a moment after he bites on a feint.
--                      Counter: hooks, body shots, feints.
--   Weaver             hooks / overhands to the head -14 points; uppercuts find him dipping (+6). Counter: straights
--                      and uppercuts.
--   CounterSpecialist  times a flurry: from the 3rd punch of a combination (or a busy spell of 7 punches in 4 s) he
--                      reads it (+25 points of defence for his AI) and his counters land +30% harder. Counter:
--                      single shots, feints, make him lead.
--   Granite            -45% knockdown odds, -40% balance loss; but slow: -8% foot speed, +6% wind-up. Counter:
--                      out-work him on points, angles, volume.
--   PressureProof      doesn't wilt under pressure (no pressured penalty) and counters a swarmer harder (+10
--                      points). Counter: box from range, jab and move.
--   RingGeneral        hard to corner (the ropes / corner penalty halved, slides off the ropes); it fades as the
--                      body work slows his legs. Counter: cut off the ring, attack the body, feint.
--
-- SCOUTING. Traits.Scout: everything is known once the player has fought him (h2h); otherwise his main trait is
-- on the tapes once he has SCOUT_FIGHTS pro bouts, the second is hidden, and an elite corner finds one more. A
-- hidden trait is revealed the first time it triggers in the fight (FightEngine sends `trait` with reveal = true).
--
-- FIGHTING TYPE. Traits.FightingType(stats): the player's style plus what he did in the fight (punch mix, head /
-- body, volume, counters, time pressing) -> HeadHunter | BodyPuncher | Volume | Power | Counter | Pressure |
-- Balanced, and Traits.Resists(trait, type) says which traits take the edge off which type.
local Traits = {}

Traits.MIN_OVERALL = 40
Traits.LEVEL_LO, Traits.LEVEL_HI = 40, 90
Traits.SCOUT_FIGHTS = 6
-- caps across every trait a boxer has (shares): damage taken off, accuracy taken off, knockdown odds off,
-- defence read bonus, counter damage bonus
Traits.CAP = { dmg = 0.35, hit = 0.15, kd = 0.5, read = 0.3, counter = 0.3, balance = 0.4 }

Traits.Data = {
	IronChin = {
		name = "Iron Chin", short = "IRON CHIN", max = { dmg = 0.3, kd = 0.35 },
		desc = "Walks through power shots to the head.",
		counter = "Go to the body. The chin cracks once the body and the gas tank are gone.",
		hint = "He's walking through your power shots! Go to the body!",
		resists = { Power = true, HeadHunter = true },
	},
	BodyArmor = {
		name = "Body Armor", short = "BODY ARMOR", max = { dmg = 0.35, drain = 0.35 },
		desc = "Body shots barely bother him.",
		counter = "Head-hunt: the jab up top, uppercuts through the middle.",
		hint = "Body shots aren't hurting him - go upstairs!",
		resists = { BodyPuncher = true, Pressure = true },
	},
	Slick = {
		name = "Slick", short = "SLICK", max = { hit = 0.14 },
		desc = "Hard to hit with straight punches.",
		counter = "Hooks and body shots; feint first and he is hittable for a moment.",
		hint = "He's slipping your straights! Hooks, body, feints!",
		resists = { HeadHunter = true, Volume = true },
	},
	Weaver = {
		name = "Weaver", short = "WEAVER", max = { hit = 0.14, upper = 0.06 },
		desc = "Bobs and weaves under hooks and overhands.",
		counter = "Straight down the middle, and the uppercut when he dips.",
		hint = "He's weaving under your hooks! Straights and uppercuts!",
		resists = { Power = true, Pressure = true },
	},
	CounterSpecialist = {
		name = "Counter Specialist", short = "COUNTER SPECIALIST", max = { read = 0.25, counter = 0.3 },
		desc = "Punishes volume and long combinations.",
		counter = "Single shots and feints. Make him lead, then fire back.",
		hint = "He's timing your combos! Single shots and feints!",
		resists = { Volume = true, Pressure = true },
	},
	Granite = {
		name = "Granite", short = "GRANITE", max = { kd = 0.45, balance = 0.4, slow = 0.08, windup = 0.06 },
		desc = "Almost impossible to drop, but slow.",
		counter = "Out-work him on points: angles, volume, and be gone before he answers.",
		hint = "He just won't go down! Out-work him on points!",
		resists = { Power = true },
	},
	PressureProof = {
		name = "Pressure-proof", short = "PRESSURE-PROOF", max = { hit = 0.1 },
		desc = "Doesn't wilt when a swarmer comes forward.",
		counter = "Box him from range: jab, move, make him come to you.",
		hint = "Pressure isn't working on him - box from range!",
		resists = { Pressure = true, Volume = true },
	},
	RingGeneral = {
		name = "Ring General", short = "RING GENERAL", max = { corner = 0.5, escape = 0.5 },
		desc = "Hard to corner: slides off the ropes.",
		counter = "Cut off the ring and attack the body to slow his legs.",
		hint = "He slides off the ropes! Cut him off, go to the body!",
		resists = { Pressure = true },
	},
}
Traits.List = { "IronChin", "BodyArmor", "Slick", "Weaver", "CounterSpecialist", "Granite", "PressureProof", "RingGeneral" }

-- which traits a style / archetype tends to have (weights; every trait keeps a small base chance)
Traits.StyleWeights = {
	OutBoxer = { Slick = 3, RingGeneral = 3, Weaver = 1, CounterSpecialist = 1.2 },
	Swarmer = { PressureProof = 3, Weaver = 3, BodyArmor = 2, IronChin = 1 },
	Slugger = { IronChin = 3, Granite = 3, BodyArmor = 2, PressureProof = 1 },
	BoxerPuncher = { IronChin = 1.5, Slick = 1.5, CounterSpecialist = 1, RingGeneral = 1, BodyArmor = 1 },
	CounterPuncher = { CounterSpecialist = 4, Slick = 2, Weaver = 1, RingGeneral = 1 },
}
Traits.ArchWeights = {
	Defensive = { Slick = 1, RingGeneral = 1 }, KO = { IronChin = 1, Granite = 0.5 }, Counter = { CounterSpecialist = 1.5 },
	Pressure = { PressureProof = 1, BodyArmor = 0.5 }, Technician = { CounterSpecialist = 0.5, RingGeneral = 1 },
}
-- display names -> ids (the offer card has Config's names, the engine the ids)
local STYLE_IDS = { ["Out-Boxer"] = "OutBoxer", ["Swarmer"] = "Swarmer", ["Slugger"] = "Slugger", ["Boxer-Puncher"] = "BoxerPuncher", ["Counter Puncher"] = "CounterPuncher" }
local ARCH_IDS = { ["Aggressive Pressure Fighter"] = "Pressure", ["Fast Counter Puncher"] = "Counter", ["Technical Genius"] = "Technician",
	["Knockout Artist"] = "KO", ["Defensive Specialist"] = "Defensive" }

-- a stable 31-bit hash of a string (FNV-1a), and a small LCG over it: the same boxer always gets the same traits
function Traits.Hash(str)
	local h = 2166136261
	for i = 1, #str do
		h = bit32.bxor(h, string.byte(str, i))
		h = (h * 16777619) % 4294967296
	end
	return h % 2147483647
end
local function lcg(seed)
	local s = seed % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return function()
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

-- the level share 0..1 of an overall
function Traits.Level(overall)
	return math.clamp(((tonumber(overall) or 50) - Traits.LEVEL_LO) / (Traits.LEVEL_HI - Traits.LEVEL_LO), 0, 1)
end

-- how many traits a boxer of this overall has, from his roll (0..1)
function Traits.Count(overall, roll)
	local ov = tonumber(overall) or 50
	if ov < Traits.MIN_OVERALL then
		return 0
	elseif ov < 55 then
		return roll < 0.45 and 1 or 0
	elseif ov < 70 then
		return roll < 0.8 and 1 or 0
	elseif ov < 82 then
		return roll < 0.4 and 2 or 1
	end
	return 2
end

-- the traits of a boxer: { { id, s }, ... } (s = strength 0.35..1, the main trait first). b = { id, style,
-- archetype, overall } (style / archetype by id or by Config display name); nil id = none (a one-off boxer)
function Traits.ForBoxer(b)
	if type(b) ~= "table" or b.id == nil then
		return {}
	end
	local id = tostring(b.id)
	if id:sub(1, 3) == "tut" then
		return {} -- (the tutorial's one-off boxers)
	end
	local style = STYLE_IDS[b.style] or b.style
	local arch = ARCH_IDS[b.archetype] or b.archetype
	local rnd = lcg(Traits.Hash("traits:" .. id))
	local n = Traits.Count(b.overall, rnd())
	local out = {}
	if n <= 0 then
		return out
	end
	local sw = Traits.StyleWeights[style] or Traits.StyleWeights.BoxerPuncher
	local aw = Traits.ArchWeights[arch] or {}
	local pool = {}
	for _, t in ipairs(Traits.List) do
		pool[t] = 0.25 + (sw[t] or 0) + (aw[t] or 0)
	end
	local s = math.floor((0.35 + 0.65 * Traits.Level(b.overall)) * 20 + 0.5) / 20
	for k = 1, n do
		local total = 0
		for _, t in ipairs(Traits.List) do
			total += pool[t]
		end
		local pick = rnd() * total
		for _, t in ipairs(Traits.List) do
			pick -= pool[t]
			if pool[t] > 0 and pick <= 0 then
				-- (the second trait is a little weaker than the main one)
				table.insert(out, { id = t, s = k == 1 and s or math.max(0.35, s - 0.15) })
				pool[t] = 0
				break
			end
		end
	end
	return out
end

-- the strength of trait id in a list (0 = he doesn't have it)
function Traits.Strength(list, id)
	for _, t in ipairs(list or {}) do
		if t.id == id then
			return t.s
		end
	end
	return 0
end

-- an effect: trait id's `kind` at strength s, capped (Traits.CAP[kind] when there is one)
function Traits.Effect(id, kind, s)
	local D = Traits.Data[id]
	local v = (D and D.max[kind] or 0) * math.clamp(tonumber(s) or 0, 0, 1)
	local cap = Traits.CAP[kind]
	return cap and math.min(v, cap) or v
end

-- scouting: which traits the player knows before the bell. info = { fights = his pro bouts (or the record
-- table), h2h = { w, l, d } or a number, elite = an elite corner }. Returns { { id, s, known }, ... }
function Traits.Scout(list, info)
	info = type(info) == "table" and info or {}
	local fights = tonumber(info.fights) or 0
	if type(info.fights) == "table" then
		local r = info.fights
		fights = (tonumber(r.w) or 0) + (tonumber(r.l) or 0) + (tonumber(r.d) or 0)
	end
	local met = tonumber(info.h2h) or 0
	if type(info.h2h) == "table" then
		local h = info.h2h
		met = (tonumber(h.w) or 0) + (tonumber(h.l) or 0) + (tonumber(h.d) or 0)
	end
	local out = {}
	local extra = info.elite and 1 or 0
	for i, t in ipairs(list or {}) do
		local known = met > 0 or (i == 1 and fights >= Traits.SCOUT_FIGHTS)
		if not known and extra > 0 then
			known, extra = true, extra - 1
		end
		table.insert(out, { id = t.id, s = t.s, known = known })
	end
	return out
end

-- the scouting line for a card: "Iron Chin  ·  1 unknown trait" (nil when he has none)
function Traits.ScoutText(scouted)
	local names, hidden = {}, 0
	for _, t in ipairs(scouted or {}) do
		if t.known then
			table.insert(names, Traits.Data[t.id].name)
		else
			hidden += 1
		end
	end
	if #names == 0 and hidden == 0 then
		return nil
	end
	if hidden > 0 then
		table.insert(names, hidden == 1 and "1 unknown trait" or (hidden .. " unknown traits"))
	end
	return table.concat(names, "  ·  ")
end

-- the scouting of an offer card's opponent (Career.OppView: id, style / archetype names, overall, record, h2h)
function Traits.ScoutView(o, elite)
	if type(o) ~= "table" then
		return nil
	end
	local list = Traits.ForBoxer({ id = o.id, style = o.style, archetype = o.archetype, overall = o.overall })
	return Traits.Scout(list, { fights = o.record, h2h = o.h2h, elite = elite })
end

------------------------------------------------------------------------
-- The player's fighting type
------------------------------------------------------------------------
Traits.Types = {
	HeadHunter = { name = "Head-hunter", desc = "Lives on head shots." },
	BodyPuncher = { name = "Body-puncher", desc = "Invests downstairs." },
	Volume = { name = "Volume puncher", desc = "Out-works everybody." },
	Power = { name = "Power puncher", desc = "Loads up on every shot." },
	Counter = { name = "Counter-puncher", desc = "Makes them miss and pays them back." },
	Pressure = { name = "Pressure fighter", desc = "Walks them down and cuts off the ring." },
	Balanced = { name = "Balanced", desc = "A bit of everything." },
}
Traits.TypeList = { "HeadHunter", "BodyPuncher", "Volume", "Power", "Counter", "Pressure", "Balanced" }
-- the style's prior (the type a boxer of that style starts as before he has thrown anything)
Traits.StyleType = { OutBoxer = "Volume", Swarmer = "Pressure", Slugger = "Power", BoxerPuncher = "Balanced", CounterPuncher = "Counter" }

-- st = { style, thrown, minutes, jab, power (non-jab thrown), body (thrown to the body), heavy (hooks, uppercuts,
-- overhands thrown), counters (counters landed), landed, pressing (share of the time spent pressing, 0..1) }
-- -> type id, the scores
function Traits.FightingType(st)
	st = type(st) == "table" and st or {}
	local thrown = tonumber(st.thrown) or 0
	local prior = Traits.StyleType[st.style] or "Balanced"
	local scores = {}
	for _, t in ipairs(Traits.TypeList) do
		scores[t] = t == prior and 0.25 or 0
	end
	if thrown >= 12 then
		local n = math.max(1, thrown)
		local body = (tonumber(st.body) or 0) / n
		local heavy = (tonumber(st.heavy) or 0) / n
		local rate = thrown / math.max(0.5, tonumber(st.minutes) or 1)
		local counters = (tonumber(st.counters) or 0) / math.max(1, tonumber(st.landed) or 1)
		local pressing = math.clamp(tonumber(st.pressing) or 0, 0, 1)
		scores.BodyPuncher += math.max(0, body - 0.22) * 4
		scores.HeadHunter += math.max(0, 0.12 - body) * 6 + math.max(0, heavy - 0.15) * 1.2
		scores.Power += math.max(0, heavy - 0.3) * 4
		scores.Volume += math.max(0, rate - 22) / 10
		scores.Counter += math.max(0, counters - 0.12) * 5
		scores.Pressure += math.max(0, pressing - 0.35) * 3
		scores.Balanced += 0.35
	end
	local best, bestV = prior, -1
	for _, t in ipairs(Traits.TypeList) do
		if scores[t] > bestV + 1e-9 then
			best, bestV = t, scores[t]
		end
	end
	return best, scores
end

-- does this trait take the edge off this fighting type?
function Traits.Resists(id, typeId)
	local D = Traits.Data[id]
	return D ~= nil and D.resists[typeId] == true
end

return Traits
