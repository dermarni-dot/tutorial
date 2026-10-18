-- Moves: the special moves (data only; FightEngine runs them, FightAI picks them, FightClient /
-- ControlsMenu show them). Each is a real set-up (a shoulder roll, a pull, a step back, a leap, a bob and
-- weave) followed by one or two of the ordinary punches, landed on the FightMotion.SpecialHits schedule
-- with the ordinary hit / hitbody acts, so the Animator's reactions play as for any punch.
--
-- Unlocks: a move is unlocked by STYLE and career TIER (its home styles get it early, everyone gets it a
-- few tiers later), by a TRAINING milestone (session count on one exercise) or by a FIGHT milestone (bouts
-- fought, wins or KO wins over the whole career, amateur and pro: Moves.FIGHT_STATS). Every move has a
-- fight milestone, so fighting alone opens them all; the fight moves (no home style: double jab, feint-cross,
-- body-head hook, jab-cross-hook, shovel hook) open only that way. Nothing is stored: the set is computed
-- from the profile whenever it is needed (old saves need no new field: the records are already there).
--   Moves.Unlocked(info)        { id = true } for info = { style, tier, sessions = { actId = n }, fights, wins, kos }
--   Moves.Info(profileOrSummary) that info, nil-safe (profile.records[act].sessions / summary.records,
--                                profile.record + profile.amateurRecord { w, l, d, ko })
--   Moves.ForAI(data)            an AI boxer's set: its style's home moves once it is good enough, and the
--                                fight moves its record and tier have earned
--   Moves.UnlockText(id, info?)  how to unlock it, for the menu (with info: the progress, "Win 15 fights (9/15)")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Moves = {}

Moves.List = {
	"checkhook", "phillyshell", "pullcounter", "livershot", "gazelle", "peekaboo", "stepback", "overhand", "leaduppercut",
	-- the fight moves (unlocked only by fighting), in ladder order
	"doublejab", "feintcross", "bodyhead", "onetwothree", "shovelhook",
}

-- the fight milestones' counters (Moves.Info): bouts fought (w + l + d), wins, wins inside the distance
Moves.FIGHT_STATS = { "fights", "wins", "kos" }

-- punch = the Config.Punches kind each hit is scored as (the second entry for a two-punch move), hand = the
-- act's hand for an orthodox fighter, body = to the body, stam = stamina cost, dmg / hit / range = multipliers
-- and additions on the ordinary punch, kd = knockdown-odds multiplier, counter = a counter move (the set-up
-- evades: shell = "straight" | "head" | "all", shellText = the HUD's call-out), liver = the liver-shot delayed knockdown, lunge = root travel
-- over the set-up (studs, negative = back), power = the act's power field, cooldown = seconds before the next.
-- hands / bodies (optional, per punch) = each punch's hand and body flag when they do not simply alternate
-- from `hand` and all share `body` (a double jab is two lefts; a body-head hook digs low, then goes high).
-- Unlocks: styles + tier (home styles), anyTier (every style), training = { activity, sessions },
-- fight = { stat = "fights" | "wins" | "kos", n } (Moves.FIGHT_STATS); aiTier = the career tier an AI boxer
-- needs for a fight move (Moves.ForAI)
Moves.Data = {
	checkhook = {
		id = "checkhook", name = "Check hook", short = "CHECK HOOK", punch = { "leadhook" }, hand = "L", body = false,
		stam = 7, dmg = 1.1, hit = 0.04, range = 1.0, kd = 1.15, power = 1.0, cooldown = 1.6, pivotOut = true,
		styles = { "OutBoxer", "CounterPuncher" }, tier = 2, anyTier = 5, training = { activity = "Ladder", sessions = 10 }, fight = { stat = "fights", n = 12 },
		desc = "A lead hook thrown as he steps in, then a pivot out of his line.",
		how = "Throw it as he comes forward: it counts as a counter when it catches him punching, and the pivot leaves you at an angle for the next shot.",
	},
	phillyshell = {
		id = "phillyshell", name = "Philly shell counter", short = "SHELL COUNTER", punch = { "cross" }, hand = "R", body = false,
		stam = 8, dmg = 1.15, hit = 0.03, range = 1.05, kd = 1.1, power = 1.1, cooldown = 1.8, counter = true, shell = "head", shellText = "SHOULDER ROLL",
		styles = { "CounterPuncher", "BoxerPuncher" }, tier = 3, anyTier = 6, training = { activity = "Shadow", sessions = 12 }, fight = { stat = "fights", n = 20 },
		desc = "Shoulder roll: his head shot slides off the shoulder, and the right hand comes back over it.",
		how = "Start it as his punch leaves. The roll covers the head for a third of a second; whatever it rolls makes the cross a counter.",
	},
	pullcounter = {
		id = "pullcounter", name = "Pull counter", short = "PULL COUNTER", punch = { "cross" }, hand = "R", body = false,
		stam = 7, dmg = 1.2, hit = 0.02, range = 1.1, kd = 1.15, power = 1.1, cooldown = 1.8, counter = true, shell = "straight", shellText = "PULLED BACK",
		styles = { "CounterPuncher", "OutBoxer" }, tier = 3, anyTier = 6, training = { activity = "DoubleEnd", sessions = 10 }, fight = { stat = "fights", n = 20 },
		desc = "Lean back out of his jab and land the right hand as he resets.",
		how = "Only straight punches miss the pull. Time it on his jab, not on a hook.",
	},
	livershot = {
		id = "livershot", name = "Liver shot", short = "LIVER SHOT", punch = { "leadhook" }, hand = "L", body = true,
		stam = 8, dmg = 1.2, hit = 0.02, range = 0.95, kd = 1.0, power = 1.1, cooldown = 2.0, liver = true,
		styles = { "Swarmer", "Slugger" }, tier = 2, anyTier = 5, training = { activity = "HeavyBag", sessions = 12 }, fight = { stat = "fights", n = 12 },
		desc = "A dipping left hook under the right elbow, straight to the liver.",
		how = "Inside range, under a high guard. A clean one folds a man up a beat after it lands, the more so when his body is already worn.",
	},
	gazelle = {
		id = "gazelle", name = "Gazelle punch", short = "GAZELLE", punch = { "leadhook" }, hand = "L", body = false,
		stam = 10, dmg = 1.3, hit = -0.04, range = 1.45, kd = 1.25, power = 1.2, cooldown = 2.4, lunge = 1.2,
		styles = { "Slugger", "Swarmer" }, tier = 4, anyTier = 7, training = { activity = "Rope", sessions = 10 }, fight = { stat = "wins", n = 20 },
		desc = "A leaping lead hook from outside jab range: the legs cover the distance, the hips bring the power.",
		how = "From long range, when he thinks he is safe. Slow and easy to see coming: feint first.",
	},
	peekaboo = {
		id = "peekaboo", name = "Peek-a-boo rush", short = "RUSH", punch = { "leadhook", "rearhook" }, hand = "L", body = false,
		stam = 12, dmg = 1.0, hit = 0.06, range = 1.3, kd = 1.0, power = 0.95, cooldown = 2.6, lunge = 1.5, shell = "head", shellText = "WEAVED",
		styles = { "Swarmer" }, tier = 4, anyTier = 7, training = { activity = "MittWork", sessions = 15 }, fight = { stat = "wins", n = 20 },
		desc = "Bob and weave in behind a tight guard, then a left hook and a right hook on arrival.",
		how = "Pressure. The weave slips head shots on the way in; the two hooks land on the inside.",
	},
	stepback = {
		id = "stepback", name = "Step-back counter", short = "STEP-BACK", punch = { "cross" }, hand = "R", body = false,
		stam = 7, dmg = 1.15, hit = 0.03, range = 1.3, kd = 1.1, power = 1.1, cooldown = 1.8, counter = true, shell = "all", shellText = "STEPPED BACK", lunge = -0.8,
		styles = { "OutBoxer", "BoxerPuncher" }, tier = 3, anyTier = 6, training = { activity = "Treadmill", sessions = 10 }, fight = { stat = "fights", n = 20 },
		desc = "Two quick steps back out of range, and the cross meets him as he follows.",
		how = "Everything misses while you step; the cross reaches further than usual. The ropes stop it: use it from the middle of the ring.",
	},
	overhand = {
		id = "overhand", name = "Loaded overhand", short = "LOADED OVERHAND", punch = { "overhand" }, hand = "R", body = false,
		stam = 10, dmg = 1.2, hit = -0.02, range = 1.0, kd = 1.2, power = 1.2, cooldown = 2.0, overGuard = 0.65,
		styles = { "Slugger", "BoxerPuncher" }, tier = 1, anyTier = 4, training = { activity = "HeavyBag", sessions = 8 }, fight = { stat = "fights", n = 10 },
		desc = "The slugger's big one: a dip to the right loads the back leg, then the overhand comes with the whole body behind it. Not the everyday overhand (Punches): heavier, and it drops men more often.",
		how = "On a man who shells up or stands still: two thirds of it lands through a block (the plain overhand gets half through).",
	},
	leaduppercut = {
		id = "leaduppercut", name = "Lead uppercut", short = "LEAD UPPERCUT", punch = { "uppercut" }, hand = "L", body = false,
		stam = 7, dmg = 1.05, hit = 0.03, range = 0.9, kd = 1.1, power = 1.0, cooldown = 1.4,
		styles = { "BoxerPuncher", "Swarmer" }, tier = 2, anyTier = 5, training = { activity = "SpeedBag", sessions = 10 }, fight = { stat = "fights", n = 12 },
		desc = "A short left uppercut from the stance: no wind-up to see.",
		how = "Inside, on a man who ducks or rolls (it lands bigger on a rolling head), or to open a tight guard.",
	},
	-- THE FIGHT MOVES: no home style, no tier, no drill. They come with ring time only (Moves.FIGHT_STATS)
	doublejab = {
		id = "doublejab", name = "Double jab", short = "DOUBLE JAB", punch = { "jab", "jab" }, hand = "L", hands = { "L", "L" }, body = false,
		stam = 5, dmg = 1.1, hit = 0.06, range = 1.05, kd = 1.0, power = 0.9, cooldown = 1.4, lunge = 0.35,
		styles = {}, fight = { stat = "fights", n = 3 }, aiTier = 2,
		desc = "Two lefts off one step: a long one to find the range, a short snap behind it before his guard resets.",
		how = "From the outside, to take the centre of the ring or set up the right hand. Cheap on the gas, light on damage.",
	},
	feintcross = {
		id = "feintcross", name = "Feint-cross", short = "FEINT-CROSS", punch = { "cross" }, hand = "R", body = false,
		stam = 7, dmg = 1.05, hit = 0.1, range = 1.05, kd = 1.05, power = 1.05, cooldown = 1.8, overGuard = 0.3,
		styles = {}, fight = { stat = "fights", n = 8 }, aiTier = 3,
		desc = "A twitch of the lead shoulder sells the jab; the cross comes down the middle while his guard reaches for it.",
		how = "On a man who blocks a lot: the feint pulls the gloves out of place, so it lands more often and a third of it gets through a high guard.",
	},
	bodyhead = {
		id = "bodyhead", name = "Body-head hook", short = "BODY-HEAD", punch = { "leadhook", "leadhook" }, hand = "L", hands = { "L", "L" },
		body = true, bodies = { true, false },
		stam = 10, dmg = 1.05, hit = 0.03, range = 0.95, kd = 1.1, power = 1.0, cooldown = 2.2,
		styles = {}, fight = { stat = "wins", n = 15 }, aiTier = 3,
		desc = "Double up the left hook: dig it into the ribs, and when his elbow drops to cover, the same hand comes back upstairs.",
		how = "Inside range. The body hook brings the guard down; the second hook finds the open jaw.",
	},
	onetwothree = {
		id = "onetwothree", name = "Jab-cross-hook", short = "1-2-3", punch = { "jab", "cross", "leadhook" }, hand = "L", body = false,
		stam = 13, dmg = 0.95, hit = 0.02, range = 1.0, kd = 1.0, power = 1.0, cooldown = 2.6, lunge = 0.3,
		styles = {}, fight = { stat = "fights", n = 25 }, aiTier = 4,
		desc = "The bread-and-butter three: jab to blind him, the cross down the pipe, the lead hook round the side as he slips it.",
		how = "From jab range stepping in: the hook has the shortest reach, so start it close enough for the third punch to land.",
	},
	shovelhook = {
		id = "shovelhook", name = "Shovel hook", short = "SHOVEL HOOK", punch = { "leadhook" }, hand = "L", body = false,
		stam = 9, dmg = 1.25, hit = 0.0, range = 0.85, kd = 1.3, power = 1.15, cooldown = 2.2,
		styles = {}, fight = { stat = "kos", n = 5 }, aiTier = 4,
		desc = "Half hook, half uppercut: the elbow tucked to the hip, the fist scooped up and in under the chin. A finisher's punch.",
		how = "Up close on a hurt man. Short, and it drops men more than any other special.",
	},
}

-- the special's canonical id (aliases of older names), or nil
local ALIAS = { phillycounter = "phillyshell", overhandright = "overhand" }
function Moves.Id(id)
	if type(id) ~= "string" then
		return nil
	end
	id = ALIAS[id] or id
	return Moves.Data[id] and id or nil
end

function Moves.StyleName(id)
	local s = Config.FindById(Config.Styles, id)
	return s and s.name or tostring(id)
end

local function tierName(n)
	local t = Config.Tiers[n]
	return t and t.name or ("tier " .. tostring(n))
end

local function activityName(id)
	local a = Config.FindById(Config.Activities, id)
	return a and a.name or tostring(id)
end
Moves.ActivityName = activityName

-- a fight milestone in words: "Fight 8 bouts", "Win 15 fights", "Win 5 fights by KO"
local FIGHT_GOAL = { fights = "Fight %d bouts", wins = "Win %d fights", kos = "Win %d fights by KO" }
-- the same once it is met: "8 bouts fought", "15 wins", "5 KO wins"
local FIGHT_DONE = { fights = "%d bouts fought", wins = "%d wins", kos = "%d KO wins" }

-- how far a fighter is along a move's fight milestone: have, need (nil when the move has none)
function Moves.FightProgress(id, info)
	local m = Moves.Data[Moves.Id(id) or ""]
	local f = m and m.fight
	if not f then
		return nil, nil
	end
	local have = type(info) == "table" and tonumber(info[f.stat]) or 0
	return math.max(0, math.floor(have or 0)), f.n
end

-- how a move unlocks (for the menu); with info (Moves.Info) the training and fight milestones carry the
-- progress: "Slugger or Swarmer from Local Pro  ·  any style from ...  ·  12 Heavy Bag sessions (4/12)  ·
-- Fight 12 bouts (5/12)". A fight move reads "Win 15 fights (9/15)".
function Moves.UnlockText(id, info)
	local m = Moves.Data[Moves.Id(id) or ""]
	if not m then
		return ""
	end
	local withInfo = type(info) == "table"
	local function progress(have, need)
		return withInfo and string.format(" (%d/%d)", math.min(have, need), need) or ""
	end
	local parts = {}
	if m.styles and #m.styles > 0 and m.tier then
		local names = {}
		for _, s in ipairs(m.styles) do
			table.insert(names, Moves.StyleName(s))
		end
		table.insert(parts, string.format("%s from %s", table.concat(names, " or "), tierName(m.tier)))
	end
	if m.anyTier then
		table.insert(parts, string.format("any style from %s", tierName(m.anyTier)))
	end
	if m.training then
		local n = withInfo and type(info.sessions) == "table" and tonumber(info.sessions[m.training.activity]) or 0
		table.insert(parts, string.format("%d %s sessions", m.training.sessions, activityName(m.training.activity)) .. progress(math.floor(n or 0), m.training.sessions))
	end
	if m.fight then
		local have, need = Moves.FightProgress(id, info)
		table.insert(parts, string.format(FIGHT_GOAL[m.fight.stat] or "%d fights", need) .. progress(have, need))
	end
	return table.concat(parts, "  ·  ")
end

-- the plain condition a fighter meets, or nil: "Slugger at Local Pro", "12 Heavy Bag sessions", "8 bouts fought"
function Moves.UnlockedBy(id, info)
	local m = Moves.Data[Moves.Id(id) or ""]
	if not (m and type(info) == "table") then
		return nil
	end
	local tier = tonumber(info.tier) or 1
	local home = m.styles ~= nil and m.tier ~= nil and table.find(m.styles, info.style) ~= nil
	if home and tier >= m.tier then
		return string.format("%s at %s", Moves.StyleName(info.style), tierName(m.tier))
	end
	if m.anyTier and tier >= m.anyTier then
		return tierName(m.anyTier)
	end
	local tr = m.training
	local n = tr and type(info.sessions) == "table" and tonumber(info.sessions[tr.activity]) or 0
	if tr and n >= tr.sessions then
		return string.format("%d %s sessions", tr.sessions, activityName(tr.activity))
	end
	local have, need = Moves.FightProgress(id, info)
	if need and have >= need then
		return string.format(FIGHT_DONE[m.fight.stat] or "%d fights", need)
	end
	return nil
end

-- the unlocked set { id = true } (always a table)
function Moves.Unlocked(info)
	local out = {}
	for _, id in ipairs(Moves.List) do
		if Moves.UnlockedBy(id, info) then
			out[id] = true
		end
	end
	return out
end

-- a whole, finite, non-negative count (0 for anything else)
local function count(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge then
		return 0
	end
	return math.max(0, math.floor(v))
end

-- the career fight counters from a { w, l, d, ko } record (or the sum of several): fights, wins, kos
function Moves.FightCounts(...)
	local fights, wins, kos = 0, 0, 0
	for i = 1, select("#", ...) do
		local r = select(i, ...)
		if type(r) == "table" then
			local w = count(r.w)
			fights += w + count(r.l) + count(r.d)
			wins += w
			kos += math.min(w, count(r.ko))
		end
	end
	return fights, wins, kos
end

-- the info a profile (server) or the summary the client holds (State.P) gives: nil-safe for old saves
function Moves.Info(P)
	local info = { style = nil, tier = 1, sessions = {}, fights = 0, wins = 0, kos = 0 }
	if type(P) ~= "table" then
		return info
	end
	-- the profile holds the style's id; the client's summary has its NAME in `style` and the id in `styleId`
	local st = (type(P.styleId) == "string" and P.styleId) or (type(P.style) == "string" and P.style) or nil
	local style = st and Config.FindById(Config.Styles, st) -- (finds a style by its id or its name)
	info.style = style and style.id or st
	local tier = tonumber(P.tier)
	info.tier = (tier and tier == tier) and math.clamp(math.floor(tier), 1, #Config.Tiers) or 1
	local records = type(P.records) == "table" and P.records or {}
	for act, r in pairs(records) do
		local n = type(r) == "table" and tonumber(r.sessions) or tonumber(r)
		if type(act) == "string" and n and n == n then
			info.sessions[act] = math.max(0, math.floor(n))
		end
	end
	-- the whole career's bouts: the amateur record and the pro one (both in the profile and the summary)
	info.fights, info.wins, info.kos = Moves.FightCounts(P.amateurRecord, P.record)
	return info
end

-- an AI boxer's moves: its style's home moves once it is good enough (an overall of 55 is a Local Pro,
-- 65 Regional, 75 Top 10, 85 a champion), and every move at the top. Amateurs (tier 1) keep it simple:
-- no special moves, even the ones a style gets from tier 1 (the player's own unlocks are unaffected).
-- The fight moves come with experience: the move's aiTier, and its fight milestone met by the boxer's
-- record when the data carries one ({ w, l, d, ko }; a partner without a record goes by the tier alone).
-- (The older moves' fight milestones are the player's way in only: an AI boxer's set keeps its style.)
function Moves.ForAI(data)
	if type(data) ~= "table" then
		return {}
	end
	local tier = tonumber(data.tier)
	if not tier then
		local ov = type(data.stats) == "table" and Config.Overall(data.stats) or 50
		tier = ov >= 85 and 8 or (ov >= 75 and 6 or (ov >= 65 and 4 or (ov >= 55 and 2 or 1)))
	end
	if tier <= 1 then
		return {}
	end
	local base = { style = data.style, tier = tier, sessions = {} }
	local out = {}
	for _, id in ipairs(Moves.List) do
		-- (UnlockedBy without the fight counters: style, tier and an empty training log)
		if Moves.UnlockedBy(id, base) then
			out[id] = true
		end
	end
	local rec = type(data.record) == "table" and data.record or nil
	local fights, wins, kos = Moves.FightCounts(rec)
	local have = { fights = fights, wins = wins, kos = kos }
	for _, id in ipairs(Moves.List) do
		local m = Moves.Data[id]
		if m.aiTier and m.fight and tier >= m.aiTier and (rec == nil or have[m.fight.stat] >= m.fight.n) then
			out[id] = true
		end
	end
	return out
end

-- the number of the Keymap action for a move, in the special list's order (the keyboard's 1..9, then 0 - = I P)
function Moves.Index(id)
	return table.find(Moves.List, Moves.Id(id) or "")
end

return Moves
