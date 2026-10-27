-- TrainingPlan: the rules of the training system both sides read (pure: nothing here touches a
-- profile; server Training keeps the state, the Hub and the session report show it).
--   * focus blocks (power, speed, endurance, defence, ring IQ, conditioning, weight cut, rest) and the
--     weekly plan templates: training today's block earns the on-plan bonus; free training still works
--   * fight camps: build / peak / taper phases over the camp days, the fight-night readiness and what
--     it does in the ring (peaked, sharp, flat, overcooked, drained)
--   * drill mastery (levels, perks) and progressive overload (the drill's difficulty and its gains)
--   * repeat / staleness / variety multipliers
--   * daily goals and the weekly challenge (small money / fame / XP rewards, the streak)
--   * the coaches' personas and the opponent counters the coach tips use
local Shared = script.Parent
local Config = require(Shared:WaitForChild("Config"))

local TP = {}

local function clamp(v, a, b)
	return math.clamp(v, a, b)
end

local function num(v, default)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end
TP.Num = num

------------------------------------------------------------------------
-- Focus blocks
------------------------------------------------------------------------
-- acts = the drills that train the block; stats = what the block is about (the coach tips and the
-- weakest-area pick read them). The on-plan bonus applies to every stat the session gains.
TP.Focus = {
	{ id = "power", name = "Power", icon = "fist", rgb = { 243, 65, 76 }, stats = { "Power", "Chin" },
		acts = { "HeavyBag", "Bench", "Barbell", "Squat", "MedBall" }, desc = "Heavy bag, the big lifts, core power" },
	{ id = "speed", name = "Speed", icon = "speed", rgb = { 255, 205, 83 }, stats = { "PunchSpeed", "Reflexes", "Footwork" },
		acts = { "SpeedBag", "DoubleEnd", "Rope", "Ladder", "MittWork" }, desc = "Hand speed, reactions, quick feet" },
	{ id = "endurance", name = "Endurance", icon = "pulse", rgb = { 58, 142, 255 }, stats = { "Stamina", "Endurance" },
		acts = { "Roadwork", "Treadmill", "Bike", "Rower", "Swimming" }, desc = "Roadwork and the cardio machines" },
	{ id = "defence", name = "Defence", icon = "shield", rgb = { 70, 214, 232 }, stats = { "Blocking", "HeadMovement" },
		acts = { "DoubleEnd", "Shadow", "Sparring", "Dumbbells" }, desc = "Slips, rolls, a tight guard" },
	{ id = "ringiq", name = "Ring IQ", icon = "brain", rgb = { 176, 122, 255 }, stats = { "RingIQ", "Countering" },
		acts = { "MittWork", "Sparring", "Shadow" }, desc = "Mitts, sparring, ring craft" },
	{ id = "conditioning", name = "Conditioning", icon = "heart", rgb = { 50, 214, 126 }, stats = { "Recovery", "Endurance", "Chin" },
		acts = { "MedBall", "Swimming", "PullUps", "Rope", "Rower" }, desc = "Engine, core, recovery between rounds" },
	{ id = "weightcut", name = "Weight Cut", icon = "flame", rgb = { 255, 148, 48 }, stats = {},
		acts = { "Roadwork", "Treadmill", "Rope", "Bike", "Sauna" }, fatMul = 1.3, desc = "Burn fat, sweat down to the limit" },
	{ id = "rest", name = "Rest", icon = "sleep", rgb = { 137, 151, 172 }, stats = {}, acts = {}, rest = true,
		desc = "Recovery only: ice bath, stretching, massage, sleep" },
}
TP.FocusById = {}
TP.ActFocus = {} -- actId -> { focus ids }
for _, f in ipairs(TP.Focus) do
	TP.FocusById[f.id] = f
	for _, a in ipairs(f.acts) do
		TP.ActFocus[a] = TP.ActFocus[a] or {}
		table.insert(TP.ActFocus[a], f.id)
	end
end
-- the six areas the weekly breadth challenge counts (not weight cut / rest)
TP.Areas = { "power", "speed", "endurance", "defence", "ringiq", "conditioning" }

function TP.OnFocus(actId, focusId)
	local f = TP.FocusById[focusId]
	return f ~= nil and table.find(f.acts, actId) ~= nil
end

-- the stat gain bonus for a session on today's block (the plan or the camp)
TP.PLAN_BONUS = 0.15

-- weekly templates: seven blocks from the day the plan is set
TP.Templates = {
	{ id = "balanced", name = "Balanced Week", desc = "A bit of everything, one rest day",
		days = { "power", "speed", "endurance", "rest", "defence", "ringiq", "conditioning" } },
	{ id = "power", name = "Power Block", desc = "Heavy hands and strong legs",
		days = { "power", "endurance", "power", "rest", "speed", "power", "conditioning" } },
	{ id = "speed", name = "Speed Block", desc = "Faster hands, faster feet",
		days = { "speed", "defence", "speed", "rest", "ringiq", "speed", "endurance" } },
	{ id = "engine", name = "Engine Block", desc = "Twelve hard rounds of gas",
		days = { "endurance", "conditioning", "endurance", "rest", "speed", "endurance", "power" } },
	{ id = "craft", name = "Ring Craft", desc = "Defence, timing and reading the fight",
		days = { "defence", "ringiq", "defence", "rest", "speed", "ringiq", "conditioning" } },
	{ id = "cut", name = "Weight Cut Week", desc = "Cardio and the sauna, power kept ticking",
		days = { "weightcut", "power", "weightcut", "rest", "speed", "weightcut", "conditioning" } },
}
TP.TemplateById = {}
for _, t in ipairs(TP.Templates) do
	TP.TemplateById[t.id] = t
end
TP.WEEK = 7

-- which of the plan's seven days `day` is (1..7), counted from the day the plan was set
function TP.PlanDayIndex(plan, day)
	local start = math.floor(num(type(plan) == "table" and plan.start or nil, day))
	return (math.floor(num(day, start)) - start) % TP.WEEK + 1
end

function TP.PlanFocus(plan, day)
	if type(plan) ~= "table" or type(plan.days) ~= "table" then
		return nil
	end
	local id = plan.days[TP.PlanDayIndex(plan, day)]
	return TP.FocusById[id] and id or nil
end

-- a clean plan from anything (a save, a client request): { start, days[7] of focus ids, template }
function TP.CleanPlan(p, day)
	if type(p) ~= "table" or type(p.days) ~= "table" then
		return nil
	end
	local days = {}
	for i = 1, TP.WEEK do
		local id = p.days[i]
		days[i] = (type(id) == "string" and TP.FocusById[id]) and id or "rest"
	end
	local tpl = type(p.template) == "string" and TP.TemplateById[p.template] and p.template or "custom"
	return { start = math.floor(num(p.start, day or 1)), days = days, template = tpl }
end

------------------------------------------------------------------------
-- Fight camps: build -> peak -> taper
------------------------------------------------------------------------
TP.Phases = {
	build = { name = "BUILD", icon = "dumbbell", rgb = { 58, 142, 255 },
		desc = "Volume. Three solid sessions a day lay the base.", target = 3 },
	peak = { name = "PEAK", icon = "flame", rgb = { 243, 65, 76 },
		desc = "Sharpen. Fewer, harder sessions graded A or better.", target = 2 },
	taper = { name = "TAPER", icon = "sleep", rgb = { 50, 214, 126 },
		desc = "Ease off. Light work, recover, go in fresh.", target = 1 },
}

-- the phase of each camp day (1..total): the last day (two in a long camp) tapers, about a third
-- before it peaks, the rest builds
function TP.CampPhases(total)
	total = math.floor(num(total, 0))
	local out = {}
	if total <= 0 then
		return out
	end
	local taper = total >= 6 and 2 or (total >= 2 and 1 or 0)
	local peak = total >= 3 and math.max(1, math.floor(total * 0.3 + 0.5)) or (total - taper)
	local build = math.max(0, total - taper - peak)
	for i = 1, total do
		out[i] = i <= build and "build" or (i <= build + peak and "peak" or "taper")
	end
	return out
end

-- today's camp day (1..total), total + 1 on fight night; nil without a camp
function TP.CampDay(camp)
	if type(camp) ~= "table" then
		return nil
	end
	local total = math.floor(num(camp.daysTotal, 0))
	local left = math.floor(num(camp.daysLeft, 0))
	return clamp(total - left + 1, 1, total + 1), total
end

function TP.CampPhase(camp)
	local i, total = TP.CampDay(camp)
	if not i or total <= 0 then
		return nil
	end
	if i > total then
		return "fight"
	end
	return TP.CampPhases(total)[i]
end

-- the training a fight calls for: two focus blocks against the opponent's style / archetype
TP.Counters = {
	Slugger = { focus = { "defence", "conditioning" }, why = "He hits hard. Make him miss and be ready to take one." },
	KO = { focus = { "defence", "conditioning" }, why = "A knockout artist: tight defence and a strong core." },
	Swarmer = { focus = { "endurance", "speed" }, why = "He'll walk you down all night. Have the gas and the feet to turn him." },
	Pressure = { focus = { "endurance", "speed" }, why = "Pressure fighter: conditioning and angles beat pressure." },
	OutBoxer = { focus = { "speed", "ringiq" }, why = "He moves. Cut the ring off and beat him to the punch." },
	Defensive = { focus = { "ringiq", "speed" }, why = "Hard to hit: feints, timing and quick hands." },
	CounterPuncher = { focus = { "ringiq", "defence" }, why = "He waits for your mistakes. Feint, and don't stay in front of him." },
	Counter = { focus = { "ringiq", "defence" }, why = "A counter puncher: throw with purpose and move your head." },
	BoxerPuncher = { focus = { "ringiq", "power" }, why = "He does everything well. Sharpen your craft and your power." },
	Technician = { focus = { "ringiq", "power" }, why = "A technician: out-think him in sparring, then hurt him." },
}
function TP.CampFocus(styleId, archetypeId)
	local c = TP.Counters[archetypeId or ""] or TP.Counters[styleId or ""]
	if c then
		return { c.focus[1], c.focus[2] }, c.why
	end
	return { "ringiq", "conditioning" }, "Sharpen your craft and your engine."
end

TP.READINESS = {
	{ id = "peaked", min = 80, name = "PEAKED", rgb = { 255, 205, 83 }, all = 2, stamina = 0.04, text = "Peaked for fight night" },
	{ id = "sharp", min = 65, name = "SHARP", rgb = { 50, 214, 126 }, all = 1, stamina = 0.02, text = "Sharp from a good camp" },
	{ id = "ready", min = 45, name = "READY", rgb = { 178, 188, 205 }, all = 0, stamina = 0, text = nil },
	{ id = "flat", min = -1, name = "FLAT", rgb = { 255, 148, 48 }, all = 0, stamina = -0.02, flat = true, text = "Flat after a poor camp" },
}

-- camp.prep (server Training keeps it): { days = { [i] = { n, q, hard } }, over = nights in bed with
-- fatigue >= 75 }. cond = the boxer's condition now (fatigue, sore, water, hydration).
-- -> { score 0..100, tier (TP.READINESS entry), parts = { build, peak, taper } (0..1 or nil),
--      over (bool), drained (bool), final (fight night), day, total }
function TP.Readiness(camp, cond, bonus)
	local day, total = TP.CampDay(camp)
	if not day or total <= 0 then
		return nil
	end
	cond = type(cond) == "table" and cond or {}
	local prep = type(camp.prep) == "table" and camp.prep or {}
	local days = type(prep.days) == "table" and prep.days or {}
	local phases = TP.CampPhases(total)
	local acc = { build = { 0, 0 }, peak = { 0, 0 }, taper = { 0, 0 } }
	local taperN, taperDays = 0, 0
	-- only the camp days already behind you count (today counts once you train)
	for i = 1, math.min(total, day) do
		local ph = phases[i]
		local d = type(days[i]) == "table" and days[i] or {}
		local n = math.max(0, num(d.n, 0))
		local done = i < day or n > 0
		if done then
			if ph == "build" then
				acc.build[1] += math.min(1, n / TP.Phases.build.target) * (0.85 + 0.15 * clamp(((n > 0 and num(d.q, 0) / n) or 0) - 0.6, 0, 1))
				acc.build[2] += 1
			elseif ph == "peak" then
				local avgQ = n > 0 and num(d.q, 0) / n or 0
				acc.peak[1] += clamp((avgQ - 0.85) / 0.4, 0, 1) * math.min(1, n / TP.Phases.peak.target)
				acc.peak[2] += 1
			elseif ph == "taper" then
				taperN += n
				taperDays += 1
			end
		end
	end
	-- freshness: fatigue and soreness now (on fight night, what you walk out with)
	local fatigue = num(cond.fatigue, 0)
	local maxSore = 0
	for _, v in pairs(type(cond.sore) == "table" and cond.sore or {}) do
		maxSore = math.max(maxSore, num(v, 0))
	end
	local fresh = clamp((70 - fatigue) / 45, 0, 1) * 0.6 + clamp((0.6 - maxSore) / 0.4, 0, 1) * 0.4
	local perDay = taperDays > 0 and taperN / taperDays or 0
	local volume = taperDays == 0 and 1 or (perDay <= 2 and 1 or (perDay <= 3 and 0.8 or 0.5))
	local parts = {
		build = acc.build[2] > 0 and acc.build[1] / acc.build[2] or nil,
		peak = acc.peak[2] > 0 and acc.peak[1] / acc.peak[2] or nil,
		taper = fresh * volume,
	}
	-- weights over the phases this camp has (a three-day camp still has all three)
	local W = { build = 0.35, peak = 0.35, taper = 0.3 }
	local sum, wsum = 0, 0
	local counts = {}
	for _, ph in ipairs(phases) do
		counts[ph] = true
	end
	for ph, w in pairs(W) do
		if counts[ph] then
			-- a phase still ahead of you counts as an average one in the forecast
			local v = parts[ph]
			if v == nil then
				v = 0.6
			end
			sum += w * v
			wsum += w
		end
	end
	local over = math.max(0, math.floor(num(prep.over, 0)))
	local score = clamp(100 * (wsum > 0 and sum / wsum or 0.6) - 12 * over + num(bonus, 0), 0, 100)
	local tier = TP.READINESS[#TP.READINESS]
	for _, t in ipairs(TP.READINESS) do
		if score >= t.min then
			tier = t
			break
		end
	end
	local water = num(cond.water, 0)
	return {
		score = math.floor(score + 0.5), tier = tier, parts = parts, day = day, total = total, final = day > total,
		over = fatigue >= 65 or over >= 2, drained = water <= -5 and num(cond.hydration, 80) < 60,
		overNights = over,
	}
end

-- what the readiness does in the ring: { stats = { stat = delta }, stamina = delta, notes }
function TP.ReadinessMods(r)
	local out = { stats = {}, stamina = 0, notes = {} }
	if type(r) ~= "table" or type(r.tier) ~= "table" then
		return out
	end
	local t = r.tier
	if t.all ~= 0 then
		for _, k in ipairs(Config.StatKeys) do
			if k ~= "Chin" then
				out.stats[k] = t.all
			end
		end
	end
	if t.flat and r.total >= 3 then
		out.stats.PunchSpeed = -1
		out.stats.Reflexes = -1
		out.stamina += t.stamina
	elseif not t.flat then
		out.stamina += t.stamina
	end
	if t.text and (not t.flat or r.total >= 3) then
		table.insert(out.notes, t.text)
	end
	if r.over then
		out.stats.Reflexes = (out.stats.Reflexes or 0) - 3
		out.stats.PunchSpeed = (out.stats.PunchSpeed or 0) - 2
		out.stats.Power = (out.stats.Power or 0) - 1
		out.stamina -= 0.05
		table.insert(out.notes, "Overtrained: heavy legs and slow hands")
	end
	if r.drained then
		out.stats.Chin = (out.stats.Chin or 0) - 3
		out.stamina -= 0.04
		table.insert(out.notes, "Drained by the weight cut")
	end
	return out
end

------------------------------------------------------------------------
-- Mastery & progressive overload
------------------------------------------------------------------------
-- total mastery XP for levels 1..5 (a session gives about 6..20)
TP.MasteryXP = { 30, 100, 220, 400, 650 }
local MASTERY_NAMES = { "Novice", "Apprentice", "Skilled", "Expert", "Elite", "Master" }
-- the name of a mastery level 0..5
function TP.MasteryName(level)
	return MASTERY_NAMES[math.floor(clamp(num(level, 0), 0, 5)) + 1]
end
TP.Perks = {
	{ level = 1, text = "Grooved: 5% less energy" },
	{ level = 2, text = "Efficient: 8% less fatigue" },
	{ level = 3, text = "Technician: +5% stat gains" },
	{ level = 4, text = "Iron form: 25% lower injury risk" },
	{ level = 5, text = "Master: +5% more gains, faster mastery of the rest" },
}

function TP.MasteryLevel(xp)
	xp = math.max(0, num(xp, 0))
	local lv = 0
	for i, need in ipairs(TP.MasteryXP) do
		if xp >= need then
			lv = i
		end
	end
	local from = lv > 0 and TP.MasteryXP[lv] or 0
	local to = TP.MasteryXP[lv + 1]
	return lv, xp - from, to and (to - from) or 0
end

-- the perks of a mastery level as multipliers
function TP.PerkValues(level)
	level = num(level, 0)
	return {
		energy = level >= 1 and 0.95 or 1,
		fatigue = level >= 2 and 0.92 or 1,
		gains = 1 + (level >= 3 and 0.05 or 0) + (level >= 5 and 0.05 or 0),
		injury = level >= 4 and 0.75 or 1,
	}
end

-- the mastery XP of one session (quality 0.4..1.5, the repeat multiplier)
function TP.MasteryGain(quality, repeatMul, boost)
	quality = clamp(num(quality, 1), 0.4, 1.5)
	return math.max(1, math.floor(12 * quality * quality * clamp(num(repeatMul, 1), 0.3, 1) * (1 + num(boost, 0)) + 0.5))
end

TP.OVERLOAD_MAX = 3
-- how far the overload may go at a mastery level
function TP.OverloadCap(level)
	level = num(level, 0)
	return level >= 4 and 3 or (level >= 3 and 2 or (level >= 2 and 1 or 0))
end

-- after a session: up a step on an A or better (on a B or better with `easy`), down on a D
function TP.NextOverload(ov, cap, quality, easy)
	ov = clamp(math.floor(num(ov, 0)), 0, TP.OVERLOAD_MAX)
	quality = num(quality, 1)
	if quality >= (easy and 1.0 or 1.2) and ov < cap then
		return ov + 1
	elseif quality < 0.8 and ov > 0 then
		return ov - 1
	end
	return math.min(ov, math.max(cap, 0))
end

-- the stat-gain multiplier of an overloaded session: the harder drill pays when it is done well
function TP.OverloadMul(ov, quality)
	return 1 + 0.05 * clamp(num(ov, 0), 0, TP.OVERLOAD_MAX) * clamp((num(quality, 1) - 0.9) / 0.4, 0, 1)
end

------------------------------------------------------------------------
-- Repeating the same drill, variety
------------------------------------------------------------------------
TP.REPEAT = { 1, 0.8, 0.6, 0.45 }
TP.REPEAT_FLOOR = 0.35
-- nPrior = sessions of this drill already done today
function TP.RepeatMul(nPrior)
	nPrior = math.max(0, math.floor(num(nPrior, 0)))
	return TP.REPEAT[nPrior + 1] or TP.REPEAT_FLOOR
end

-- one drill's share of the last week's training sessions (total of them): a grind goes stale
function TP.StaleMul(share, total)
	share, total = num(share, 0), num(total, 0)
	if total < 6 or share <= 0.4 then
		return 1
	end
	return clamp(1 - (share - 0.4) * 0.6, 0.65, 1)
end

-- distinct drills today (this one included), focus areas covered over the last week
function TP.VarietyBonus(distinctToday, areasWeek, extra)
	local today = clamp(0.04 * (math.max(1, num(distinctToday, 1)) - 1), 0, 0.12)
	local week = clamp(0.015 * (num(areasWeek, 0) - 2), 0, 0.06)
	return today + week + num(extra, 0)
end

------------------------------------------------------------------------
-- Goals
------------------------------------------------------------------------
TP.GoalDefs = {
	grade = { text = "Finish 2 sessions graded A or better", need = 2, icon = "star" },
	variety = { text = "Train 3 different drills", need = 3, icon = "dumbbell" },
	recover = { text = "Do a recovery session", need = 1, icon = "heart" },
	plan = { text = "Train today's plan focus twice", need = 2, icon = "calendar" },
	focus = { text = "Train %s twice", need = 2, icon = "target" },
	record = { text = "Set a personal best", need = 1, icon = "trophy" },
	fuel = { text = "Eat a proper meal (balanced or better)", need = 1, icon = "food" },
	spar = { text = "Spar a session", need = 1, icon = "glove" },
	rest = { text = "Take your rest day (no hard training)", need = 1, icon = "sleep", atSleep = true },
	camp = { text = "Hit today's camp target (%d sessions)", need = 3, icon = "flame" },
	-- the weekly challenge
	wsessions = { text = "Log 12 sessions graded B or better", need = 12, icon = "chart", weekly = true },
	wmastery = { text = "Raise a drill's mastery level", need = 1, icon = "medal", weekly = true },
	woverload = { text = "Raise the overload on 2 drills", need = 2, icon = "trend", weekly = true },
	wplan = { text = "Follow your plan on 5 days", need = 5, icon = "calendar", weekly = true },
	wbreadth = { text = "Train all 6 focus areas", need = 6, icon = "target", weekly = true },
}
TP.GOOD_MEALS = { Balanced = true, Protein = true, Athlete = true, Chef = true }

-- a small deterministic hash (day, seed) -> 0..1
local function hash(a, b)
	local x = (math.floor(num(a, 0)) * 73856093 + math.floor(num(b, 0)) * 19349663) % 2147483647
	x = (x * 48271) % 2147483647
	x = (x * 48271) % 2147483647
	return x / 2147483647
end
TP.Hash = hash

local function goal(kind, extra)
	local def = TP.GoalDefs[kind]
	local g = { kind = kind, n = 0, need = def.need, done = false }
	for k, v in pairs(extra or {}) do
		g[k] = v
	end
	return g
end

-- three goals for a day. ctx = { seed, rest (a plan rest day), taper (a camp's taper day), planFocus,
-- weakFocus, campTarget, canSpar }
function TP.DailyGoals(day, ctx)
	ctx = type(ctx) == "table" and ctx or {}
	local seed = num(ctx.seed, 1)
	if ctx.rest then
		return { goal("rest"), goal("recover"), goal("fuel") }
	elseif ctx.taper then
		-- a camp's taper: sharp, light and fresh
		return { goal(hash(day, seed) < 0.5 and "grade" or "record"), goal("recover"), goal("fuel") }
	end
	local list = {}
	-- 1. how well: the grades, or the variety
	table.insert(list, goal(hash(day, seed) < 0.5 and "grade" or "variety"))
	-- 2. what: today's camp target, the plan's block or your weakest area
	if ctx.campTarget then
		table.insert(list, goal("camp", { need = ctx.campTarget }))
	elseif ctx.planFocus then
		table.insert(list, goal("plan", { focus = ctx.planFocus }))
	else
		table.insert(list, goal("focus", { focus = ctx.weakFocus or TP.Areas[1 + math.floor(hash(day + 7, seed) * #TP.Areas) % #TP.Areas] }))
	end
	-- 3. the rest of the job
	local pool = { "recover", "fuel", "record" }
	if ctx.canSpar then
		table.insert(pool, "spar")
	end
	table.insert(list, goal(pool[1 + math.floor(hash(day + 13, seed) * #pool) % #pool]))
	return list
end

function TP.WeeklyGoal(week, ctx)
	ctx = type(ctx) == "table" and ctx or {}
	local pool = { "wsessions", "wmastery", "woverload", "wbreadth" }
	if ctx.plan then
		table.insert(pool, "wplan")
	end
	return goal(pool[1 + math.floor(hash(week + 101, num(ctx.seed, 1)) * #pool) % #pool])
end

-- the goal's line ("Train Power twice")
function TP.GoalText(g)
	local def = type(g) == "table" and TP.GoalDefs[g.kind]
	if not def then
		return ""
	end
	if g.kind == "focus" then
		local f = TP.FocusById[g.focus]
		return string.format(def.text, f and f.name or "your weakest area")
	elseif g.kind == "camp" then
		return string.format(def.text, num(g.need, 3))
	end
	return def.text
end

-- the rewards: one daily goal, the day's sweep (all of them, times the streak), the weekly challenge
function TP.Reward(kind, tier, streak)
	tier = clamp(math.floor(num(tier, 1)), 1, 10)
	local mult = 1 + 0.1 * clamp(math.floor(num(streak, 0)), 0, 5)
	if kind == "weekly" then
		return { money = 120 * tier * tier, fame = 0.25, xp = 150 }
	elseif kind == "sweep" then
		return { money = math.floor(20 * tier * tier * mult + 0.5), fame = 0.05, xp = math.floor(40 * mult + 0.5) }
	end
	return { money = 20 * tier * tier, fame = 0, xp = 30 }
end

------------------------------------------------------------------------
-- Coaches: personas (Catalog.CoachSpecialties ids) and what each one adds
------------------------------------------------------------------------
-- perk ids (server Training reads them, the Coaches tab shows the line):
--  overloadEasy: overload climbs on a B (q >= 1.0) in this coach's drills
--  mastery: +10% mastery XP per tier in this coach's drills
--  sparSafe: sparring injury risk -12% per tier
--  variety: +1% variety bonus per tier
--  recovery: soreness clears 5% faster per tier (recovery sessions and sleep)
--  readiness: +2 camp readiness per tier, opponent scouting in the tips
TP.CoachPersonas = {
	Power = { persona = "Old-school taskmaster", focus = "power", perk = "overloadEasy",
		perkText = "Raises the load on power drills after a B grade, not just an A",
		says = { "More weight. You're ready.", "Sit down on your punches.", "Power is built, not born." } },
	Speed = { persona = "Drill sergeant", focus = "speed", perk = "mastery",
		perkText = "Speed drills master faster (+10% mastery XP per tier)",
		says = { "Faster. Again.", "Hands back quicker than they went out.", "Speed kills. Train it every day." } },
	Defense = { persona = "Wise old hand", focus = "defence", perk = "sparSafe",
		perkText = "Safer sparring (-12% injury risk per tier)",
		says = { "Don't get hit. That's the whole game.", "Chin down, eyes up.", "Slip it and make him pay." } },
	Footwork = { persona = "Ring dancer", focus = "speed", perk = "variety",
		perkText = "Rewards varied training (+1% variety bonus per tier)",
		says = { "Feet first, then hands.", "Angles, angles, angles.", "Never let him set his feet." } },
	Conditioning = { persona = "Sports scientist", focus = "conditioning", perk = "recovery",
		perkText = "Soreness clears 5% faster per tier (sleep and recovery)",
		says = { "Recovery is training.", "Sleep, eat, repeat.", "The engine wins the late rounds." } },
	RingIQ = { persona = "Chess master", focus = "ringiq", perk = "readiness",
		perkText = "Camps peak better (+2 readiness per tier) and he scouts every opponent",
		says = { "Think two punches ahead.", "Make him guess.", "Every round is a puzzle." } },
}
-- the coach id that speaks for a focus block
TP.FocusCoach = { power = "Power", speed = "Speed", endurance = "Conditioning", conditioning = "Conditioning", defence = "Defense", ringiq = "RingIQ", weightcut = "Conditioning" }

-- which focus block trains a stat best (the weakest-area pick)
function TP.FocusForStat(stat)
	for _, f in ipairs(TP.Focus) do
		if table.find(f.stats, stat) then
			return f.id
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Sparring drills: a focus goal for a spar (SparPicker shows them; TP.SparFocusCheck reads the fight
-- result FightEngine hands back: res.evades, res.combos.landed, res.landed, res.oppLanded). The need scales
-- with the rounds of the intensity (Light 1, Medium 2, Hard 3). A goal met adds TP.SPAR_FOCUS_BONUS to the
-- session quality and tilts the gains toward the focus stats (Training.SparFocusResult).
------------------------------------------------------------------------
TP.SPAR_ROUNDS = { Light = 1, Medium = 2, Hard = 3 }
TP.SPAR_FOCUS_BONUS = 0.1
TP.SparFocus = {
	{ id = "defence", name = "DEFENCE", goal = "Make %d punches miss: slip, roll, block", per = 5, stats = { "HeadMovement", "Blocking" },
		value = function(res)
			return tonumber(res.evades) or 0
		end },
	{ id = "combos", name = "COMBINATIONS", goal = "Land %d combinations", per = 2, stats = { "PunchSpeed", "RingIQ" },
		value = function(res)
			return type(res.combos) == "table" and tonumber(res.combos.landed) or 0
		end },
	{ id = "volume", name = "WORK RATE", goal = "Land %d punches", per = 12, stats = { "Endurance", "PunchSpeed" },
		value = function(res)
			return tonumber(res.landed) or 0
		end },
	{ id = "control", name = "RING CONTROL", goal = "Out-land your partner", per = nil, stats = { "RingIQ", "Countering" },
		value = function(res)
			return (tonumber(res.landed) or 0) - (tonumber(res.oppLanded) or 0)
		end },
}
TP.SparFocusById = {}
for _, f in ipairs(TP.SparFocus) do
	TP.SparFocusById[f.id] = f
end
-- the goal's numbers for an intensity: need, the goal line
function TP.SparFocusGoal(focusId, intensity)
	local f = TP.SparFocusById[focusId]
	if not f then
		return nil
	end
	local rounds = TP.SPAR_ROUNDS[intensity] or 2
	local need = f.per and f.per * rounds or 1
	return need, f.per and string.format(f.goal, need) or f.goal
end
-- did the spar meet its focus? -> met, value, need (nil for an unknown focus or no result)
function TP.SparFocusCheck(focusId, res, intensity)
	local f = TP.SparFocusById[focusId]
	if not f or type(res) ~= "table" then
		return nil
	end
	local need = TP.SparFocusGoal(focusId, intensity)
	local ok, v = pcall(f.value, res)
	v = ok and tonumber(v) or 0
	return v >= need, v, need
end

return TP
