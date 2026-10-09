-- Moves: the special moves (data only; FightEngine runs them, FightAI picks them, FightClient /
-- ControlsMenu show them). Each is a real set-up (a shoulder roll, a pull, a step back, a leap, a bob and
-- weave) followed by one or two of the ordinary punches, landed on the FightMotion.SpecialHits schedule
-- with the ordinary hit / hitbody acts, so the Animator's reactions play as for any punch.
--
-- Unlocks: a move is unlocked by STYLE and career TIER (its home styles get it early, everyone gets it a
-- few tiers later) or by a TRAINING milestone (session count on one exercise). Nothing is stored: the set
-- is computed from the profile whenever it is needed (old saves need no new field).
--   Moves.Unlocked(info)        { id = true } for info = { style, tier, sessions = { actId = n } }
--   Moves.Info(profileOrSummary) that info, nil-safe (profile.records[act].sessions / summary.records)
--   Moves.ForAI(data)            an AI boxer's set: its style's home moves once it is good enough
--   Moves.UnlockText(id)         how to unlock it, for the menu
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Moves = {}

Moves.List = { "checkhook", "phillyshell", "pullcounter", "livershot", "gazelle", "peekaboo", "stepback", "overhand", "leaduppercut" }

-- punch = the Config.Punches kind each hit is scored as (the second entry for a two-punch move), hand = the
-- act's hand for an orthodox fighter, body = to the body, stam = stamina cost, dmg / hit / range = multipliers
-- and additions on the ordinary punch, kd = knockdown-odds multiplier, counter = a counter move (the set-up
-- evades: shell = "straight" | "head" | "all", shellText = the HUD's call-out), liver = the liver-shot delayed knockdown, lunge = root travel
-- over the set-up (studs, negative = back), power = the act's power field, cooldown = seconds before the next
Moves.Data = {
	checkhook = {
		id = "checkhook", name = "Check hook", short = "CHECK HOOK", punch = { "leadhook" }, hand = "L", body = false,
		stam = 7, dmg = 1.1, hit = 0.04, range = 1.0, kd = 1.15, power = 1.0, cooldown = 1.6, pivotOut = true,
		styles = { "OutBoxer", "CounterPuncher" }, tier = 2, anyTier = 5, training = { activity = "Ladder", sessions = 10 },
		desc = "A lead hook thrown as he steps in, then a pivot out of his line.",
		how = "Throw it as he comes forward: it counts as a counter when it catches him punching, and the pivot leaves you at an angle for the next shot.",
	},
	phillyshell = {
		id = "phillyshell", name = "Philly shell counter", short = "SHELL COUNTER", punch = { "cross" }, hand = "R", body = false,
		stam = 8, dmg = 1.15, hit = 0.03, range = 1.05, kd = 1.1, power = 1.1, cooldown = 1.8, counter = true, shell = "head", shellText = "SHOULDER ROLL",
		styles = { "CounterPuncher", "BoxerPuncher" }, tier = 3, anyTier = 6, training = { activity = "Shadow", sessions = 12 },
		desc = "Shoulder roll: his head shot slides off the shoulder, and the right hand comes back over it.",
		how = "Start it as his punch leaves. The roll covers the head for a third of a second; whatever it rolls makes the cross a counter.",
	},
	pullcounter = {
		id = "pullcounter", name = "Pull counter", short = "PULL COUNTER", punch = { "cross" }, hand = "R", body = false,
		stam = 7, dmg = 1.2, hit = 0.02, range = 1.1, kd = 1.15, power = 1.1, cooldown = 1.8, counter = true, shell = "straight", shellText = "PULLED BACK",
		styles = { "CounterPuncher", "OutBoxer" }, tier = 3, anyTier = 6, training = { activity = "DoubleEnd", sessions = 10 },
		desc = "Lean back out of his jab and land the right hand as he resets.",
		how = "Only straight punches miss the pull. Time it on his jab, not on a hook.",
	},
	livershot = {
		id = "livershot", name = "Liver shot", short = "LIVER SHOT", punch = { "leadhook" }, hand = "L", body = true,
		stam = 8, dmg = 1.2, hit = 0.02, range = 0.95, kd = 1.0, power = 1.1, cooldown = 2.0, liver = true,
		styles = { "Swarmer", "Slugger" }, tier = 2, anyTier = 5, training = { activity = "HeavyBag", sessions = 12 },
		desc = "A dipping left hook under the right elbow, straight to the liver.",
		how = "Inside range, under a high guard. A clean one folds a man up a beat after it lands, the more so when his body is already worn.",
	},
	gazelle = {
		id = "gazelle", name = "Gazelle punch", short = "GAZELLE", punch = { "leadhook" }, hand = "L", body = false,
		stam = 10, dmg = 1.3, hit = -0.04, range = 1.45, kd = 1.25, power = 1.2, cooldown = 2.4, lunge = 1.2,
		styles = { "Slugger", "Swarmer" }, tier = 4, anyTier = 7, training = { activity = "Rope", sessions = 10 },
		desc = "A leaping lead hook from outside jab range: the legs cover the distance, the hips bring the power.",
		how = "From long range, when he thinks he is safe. Slow and easy to see coming: feint first.",
	},
	peekaboo = {
		id = "peekaboo", name = "Peek-a-boo rush", short = "RUSH", punch = { "leadhook", "rearhook" }, hand = "L", body = false,
		stam = 12, dmg = 1.0, hit = 0.06, range = 1.3, kd = 1.0, power = 0.95, cooldown = 2.6, lunge = 1.5, shell = "head", shellText = "WEAVED",
		styles = { "Swarmer" }, tier = 4, anyTier = 7, training = { activity = "MittWork", sessions = 15 },
		desc = "Bob and weave in behind a tight guard, then a left hook and a right hook on arrival.",
		how = "Pressure. The weave slips head shots on the way in; the two hooks land on the inside.",
	},
	stepback = {
		id = "stepback", name = "Step-back counter", short = "STEP-BACK", punch = { "cross" }, hand = "R", body = false,
		stam = 7, dmg = 1.15, hit = 0.03, range = 1.3, kd = 1.1, power = 1.1, cooldown = 1.8, counter = true, shell = "all", shellText = "STEPPED BACK", lunge = -0.8,
		styles = { "OutBoxer", "BoxerPuncher" }, tier = 3, anyTier = 6, training = { activity = "Treadmill", sessions = 10 },
		desc = "Two quick steps back out of range, and the cross meets him as he follows.",
		how = "Everything misses while you step; the cross reaches further than usual. The ropes stop it: use it from the middle of the ring.",
	},
	overhand = {
		id = "overhand", name = "Overhand right", short = "OVERHAND RIGHT", punch = { "overhand" }, hand = "R", body = false,
		stam = 10, dmg = 1.2, hit = -0.02, range = 1.0, kd = 1.2, power = 1.2, cooldown = 2.0, overGuard = 0.65,
		styles = { "Slugger", "BoxerPuncher" }, tier = 1, anyTier = 4, training = { activity = "HeavyBag", sessions = 8 },
		desc = "The slugger's overhand: a looping right with the whole body behind it, over the top of the guard.",
		how = "On a man who shells up or stands still. Two thirds of it lands through a block.",
	},
	leaduppercut = {
		id = "leaduppercut", name = "Lead uppercut", short = "LEAD UPPERCUT", punch = { "uppercut" }, hand = "L", body = false,
		stam = 7, dmg = 1.05, hit = 0.03, range = 0.9, kd = 1.1, power = 1.0, cooldown = 1.4,
		styles = { "BoxerPuncher", "Swarmer" }, tier = 2, anyTier = 5, training = { activity = "SpeedBag", sessions = 10 },
		desc = "A short left uppercut from the stance: no wind-up to see.",
		how = "Inside, on a man who ducks or rolls (it lands bigger on a rolling head), or to open a tight guard.",
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

-- how a move unlocks (for the menu)
function Moves.UnlockText(id)
	local m = Moves.Data[Moves.Id(id) or ""]
	if not m then
		return ""
	end
	local names = {}
	for _, s in ipairs(m.styles) do
		table.insert(names, Moves.StyleName(s))
	end
	local who = table.concat(names, " or ")
	local parts = { string.format("%s from %s", who, tierName(m.tier)) }
	if m.anyTier then
		table.insert(parts, string.format("any style from %s", tierName(m.anyTier)))
	end
	if m.training then
		table.insert(parts, string.format("%d %s sessions", m.training.sessions, activityName(m.training.activity)))
	end
	return table.concat(parts, "  ·  ")
end

-- the plain condition a fighter meets, or nil: "Slugger at Local Pro", "12 Heavy Bag sessions"
function Moves.UnlockedBy(id, info)
	local m = Moves.Data[Moves.Id(id) or ""]
	if not (m and type(info) == "table") then
		return nil
	end
	local tier = tonumber(info.tier) or 1
	local home = table.find(m.styles, info.style) ~= nil
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

-- the info a profile (server) or the summary the client holds (State.P) gives: nil-safe for old saves
function Moves.Info(P)
	local info = { style = nil, tier = 1, sessions = {} }
	if type(P) ~= "table" then
		return info
	end
	info.style = type(P.style) == "string" and P.style or nil
	local tier = tonumber(P.tier)
	info.tier = (tier and tier == tier) and math.clamp(math.floor(tier), 1, #Config.Tiers) or 1
	local records = type(P.records) == "table" and P.records or {}
	for act, r in pairs(records) do
		local n = type(r) == "table" and tonumber(r.sessions) or tonumber(r)
		if type(act) == "string" and n and n == n then
			info.sessions[act] = math.max(0, math.floor(n))
		end
	end
	return info
end

-- an AI boxer's moves: its style's home moves once it is good enough (an overall of 55 is a Local Pro,
-- 65 Regional, 75 Top 10, 85 a champion), and every move at the top
function Moves.ForAI(data)
	if type(data) ~= "table" then
		return {}
	end
	local tier = tonumber(data.tier)
	if not tier then
		local ov = type(data.stats) == "table" and Config.Overall(data.stats) or 50
		tier = ov >= 85 and 8 or (ov >= 75 and 6 or (ov >= 65 and 4 or (ov >= 55 and 2 or 1)))
	end
	return Moves.Unlocked({ style = data.style, tier = tier, sessions = {} })
end

-- the number of the Keymap action for a move, in the special list's order (the keyboard's 1..9)
function Moves.Index(id)
	return table.find(Moves.List, Moves.Id(id) or "")
end

return Moves
