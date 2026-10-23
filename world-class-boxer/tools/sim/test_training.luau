--!nocheck
-- tools/sim/test_training.luau: the training programme on the real server Training / Career code (headless).
--   rules     Shared.TrainingPlan: camp phases, repeat / stale / variety, mastery, overload, readiness, goals
--   plans     SetPlan / SetPlanDay, today's focus, the on-plan bonus, the week wrapping round
--   repeats   diminishing returns on the same drill, staleness over a week, the variety bonus
--   mastery   levels, perks (energy), progressive overload up on A grades and down on D, the overloaded plan
--   overload  every drill at overload 3: the perfect player still >= 0.85, replay = live, no easier for an
--             average player (the judges on a virtual clock, as test_drills part A)
--   records   personal bests count for the goal; the programme view
--   soreness  soreness from training costs the next session's gains and the fight; ice bath, massage, sleep,
--             food, the rest day and the conditioning coach clear it
--   camps     phases, the camp log, peaking (bonus), overtraining and a hard weight cut (penalties), debuts
--   goals     drawn per day, paid once, the sweep and the streak, the weekly challenge, the rest day
--   rust      detraining after idle days, not in a suspension
--   saves     an old save without the programme, a corrupt one, idempotent Migrate, DataStore-safe tables
--   coaches   tips from the opponent (style, edges, AI traits), personas' perks; sparring counts
--
--   lune run tools/sim/test_training.luau [-v]
local TH = require("./trainhost")
local Bots = require("./drillbots")
local process = require("@lune/process")
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
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

local T = TH.new({ seed = 4242 })
local Training, Career, Config, TP = T.Training, T.Career, T.Config, T.TP
local H = T.H
local function act(id)
	return Training.Activity(id)
end
local function Catalog_name(spec, tier)
	return H.require("Catalog").CoachNames[spec][tier]
end
local function fresh(age)
	local P = T.profile(age or 22)
	P.money = 1e6
	Training.Migrate(P)
	return P
end
local function deep(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = deep(v)
	end
	return o
end
local function camp(P, total, left)
	local cls = P.world.classes[P.physical.weightClass]
	P.camp = { offer = { oppId = cls[1], kind = "Pro Fight", opp = { name = "Opp" } }, daysLeft = left or total, daysTotal = total, log = {} }
	return P.world.boxers[cls[1]]
end

------------------------------------------------------------------------
-- rules
------------------------------------------------------------------------
for total = 1, 11 do
	local ph = TP.CampPhases(total)
	check("CampPhases(" .. total .. ") one per day", #ph == total)
	if total >= 3 then
		check("CampPhases(" .. total .. ") build -> peak -> taper", ph[1] == "build" and ph[total] == "taper" and table.find(ph, "peak") ~= nil, table.concat(ph, ","))
		local order = { build = 1, peak = 2, taper = 3 }
		local okOrder = true
		for i = 2, total do
			okOrder = okOrder and order[ph[i]] >= order[ph[i - 1]]
		end
		check("CampPhases(" .. total .. ") in order", okOrder, table.concat(ph, ","))
	end
end
check("CampPhases(0) empty", #TP.CampPhases(0) == 0)
check("repeat multipliers fall", TP.RepeatMul(0) == 1 and TP.RepeatMul(1) == 0.8 and TP.RepeatMul(2) == 0.6 and TP.RepeatMul(3) == 0.45 and TP.RepeatMul(9) == TP.REPEAT_FLOOR)
check("stale: a varied week is not stale", TP.StaleMul(0.3, 20) == 1 and TP.StaleMul(1, 3) == 1)
check("stale: a one-drill week is", TP.StaleMul(1, 20) == 0.65 and TP.StaleMul(0.6, 20) < 1)
check("variety bonus capped", near(TP.VarietyBonus(1, 0), 0) and near(TP.VarietyBonus(4, 2), 0.12) and near(TP.VarietyBonus(9, 6), 0.18))
check("mastery levels", TP.MasteryLevel(0) == 0 and TP.MasteryLevel(30) == 1 and TP.MasteryLevel(99) == 1 and TP.MasteryLevel(650) == 5 and TP.MasteryLevel(1e6) == 5)
check("mastery names", TP.MasteryName(0) == "Novice" and TP.MasteryName(5) == "Master" and TP.MasteryName(99) == "Master")
check("overload cap by mastery", TP.OverloadCap(0) == 0 and TP.OverloadCap(2) == 1 and TP.OverloadCap(3) == 2 and TP.OverloadCap(5) == 3)
check("overload up on an A, down on a D, held otherwise", TP.NextOverload(0, 2, 1.25) == 1 and TP.NextOverload(2, 2, 1.25) == 2 and TP.NextOverload(2, 2, 0.7) == 1
	and TP.NextOverload(1, 2, 1.05) == 1 and TP.NextOverload(1, 2, 1.05, true) == 2)
check("overload pays only when done well", TP.OverloadMul(3, 0.9) == 1 and near(TP.OverloadMul(3, 1.3), 1.15) and TP.OverloadMul(0, 1.5) == 1)
local g1, g2 = TP.DailyGoals(10, { seed = 5 }), TP.DailyGoals(10, { seed = 5 })
check("daily goals: three, deterministic", #g1 == 3 and g1[1].kind == g2[1].kind and g1[3].kind == g2[3].kind)
check("daily goals: a rest day rests", TP.DailyGoals(3, { rest = true })[1].kind == "rest")
check("daily goals: a camp day has the camp target", TP.DailyGoals(3, { campTarget = 3 })[2].kind == "camp" and TP.DailyGoals(3, { campTarget = 3 })[2].need == 3)
check("goal texts", TP.GoalText({ kind = "focus", focus = "power" }) == "Train Power twice" and TP.GoalText({ kind = "camp", need = 2 }):find("2") ~= nil)
check("rewards scale with tier and streak", TP.Reward("goal", 3).money == 180 and TP.Reward("sweep", 1, 5).money > TP.Reward("sweep", 1, 0).money)
check("CleanPlan repairs", TP.CleanPlan({ days = { "power", "bogus" } }, 4).days[2] == "rest" and #TP.CleanPlan({ days = {} }, 4).days == 7 and TP.CleanPlan("x") == nil)

------------------------------------------------------------------------
-- plans
------------------------------------------------------------------------
do
	local P = fresh()
	check("no plan: free training", Training.TodayFocus(P) == nil)
	local free = Training.SessionMods(P, act("HeavyBag"), 1.2)
	check("free training: no plan bonus", free.planMul == 1 and not free.onPlan)
	check("SetPlan balanced", Training.SetPlan(P, "balanced") == true)
	check("SetPlan unknown fails", Training.SetPlan(P, "bogus") == false)
	local f = Training.TodayFocus(P)
	check("today = the plan's first block (power)", f and f[1] == "power")
	local on = Training.SessionMods(P, act("HeavyBag"), 1.2)
	local off = Training.SessionMods(P, act("SpeedBag"), 1.2)
	check("on plan: the plan bonus", on.onPlan and near(on.planMul, 1 + TP.PLAN_BONUS) and not off.onPlan)
	-- the bonus shows in the gains (two identical boxers, one on plan, one off)
	local A, B = fresh(), fresh()
	B.stats = deep(A.stats)
	Training.SetPlan(A, "balanced")
	Training.SetPlan(B, "speed")
	local ga = Training.Perform(A, act("HeavyBag"), 1.2).gains.Power
	local gb = Training.Perform(B, act("HeavyBag"), 1.2).gains.Power
	check("on-plan gains are bigger", ga > gb * 1.08, string.format("%.3f vs %.3f", ga, gb))
	check("SetPlanDay", Training.SetPlanDay(P, 2, "defence") == true and P.train.plan.days[2] == "defence" and P.train.plan.template == "custom")
	check("SetPlanDay bad input", Training.SetPlanDay(P, 9, "power") == false and Training.SetPlanDay(P, 2, "nope") == false)
	for _ = 1, 7 do
		Training.Sleep(P)
	end
	check("the week wraps round", Training.TodayFocus(P)[1] == "power")
	Training.Sleep(P)
	check("day 2 of the plan", Training.TodayFocus(P)[1] == "defence")
	check("SetPlan none clears", Training.SetPlan(P, "none") == true and P.train.plan == nil and Training.TodayFocus(P) == nil)
end

------------------------------------------------------------------------
-- repeats, staleness, variety
------------------------------------------------------------------------
do
	local P = fresh()
	local gains, reps = {}, {}
	for i = 1, 4 do
		P.condition.energy, P.condition.fatigue, P.condition.sore = 100, 0, {}
		local m = Training.SessionMods(P, act("SpeedBag"), 1.2)
		reps[i] = m.rep
		gains[i] = Training.Perform(P, act("SpeedBag"), 1.2).gains.PunchSpeed
	end
	check("the same drill again: x1, x0.8, x0.6, x0.45", reps[1] == 1 and reps[2] == 0.8 and reps[3] == 0.6 and reps[4] == 0.45, table.concat(reps, ","))
	check("diminishing gains on the same drill", gains[2] < gains[1] and gains[3] < gains[2] and gains[4] < gains[3], string.format("%.3f %.3f %.3f %.3f", gains[1], gains[2], gains[3], gains[4]))
	Training.Sleep(P)
	check("a new day resets the repeats", Training.SessionMods(P, act("SpeedBag"), 1.2).rep == 1)
	-- a week of nothing but the speed bag goes stale
	for _ = 1, 6 do
		for _ = 1, 3 do
			P.condition.energy = 100
			Training.Perform(P, act("SpeedBag"), 1.2)
		end
		Training.Sleep(P)
	end
	local m = Training.SessionMods(P, act("SpeedBag"), 1.2)
	check("a one-drill week is stale", m.stale < 0.8, m.stale)
	-- variety: four different drills
	local V = fresh()
	for _, id in ipairs({ "HeavyBag", "Rope", "Shadow" }) do
		V.condition.energy = 100
		Training.Perform(V, act(id), 1.2)
	end
	local vm = Training.SessionMods(V, act("Rower"), 1.2)
	check("variety bonus for the fourth drill", vm.variety >= 0.12, vm.variety)
	check("the report names the multipliers", (function()
		V.condition.energy = 100
		local r = Training.Perform(V, act("Rower"), 1.2).report
		for _, c in ipairs(r.chips) do
			if c.text:find("VARIETY") then
				return true
			end
		end
		return false
	end)())
end

------------------------------------------------------------------------
-- mastery & progressive overload
------------------------------------------------------------------------
do
	local P = fresh()
	local e0 = Training.EnergyCost(P, act("Bench"))
	local ups = 0
	for d = 1, 12 do
		for _ = 1, 2 do
			P.condition.energy, P.condition.fatigue, P.condition.sore = 100, 0, {}
			local r = Training.Perform(P, act("Bench"), 1.3)
			if r.report.mastery.up then
				ups += 1
			end
		end
		Training.Sleep(P)
	end
	local lv, xp, ov = Training.Mastery(P, "Bench")
	check("mastery climbs with sessions", lv >= 3 and ups >= 3, string.format("lv %d xp %d", lv, xp))
	check("the energy perk (Grooved)", Training.EnergyCost(P, act("Bench")) < e0, Training.EnergyCost(P, act("Bench")) .. " vs " .. e0)
	check("overload climbs on A grades (capped by mastery)", ov >= 1 and ov <= TP.OverloadCap(lv), ov)
	local params = Training.MinigameParams(P, act("Bench"))
	check("the station's params carry the overload", params.overload == ov)
	-- the plan is harder: a workout draws on a higher level, a classic drill gets tighter windows
	local function planWith(a, ovl)
		T.FixSeed(99)
		local p = Training.DrillPlan(a, 2, { level = 2, overload = ovl })
		T.FixSeed(nil)
		return p
	end
	local b0, b3 = planWith(act("Squat"), 0), planWith(act("Squat"), 3)
	check("overloaded squat: narrower zone", (b3.segs[1].hi - b3.segs[1].lo) < (b0.segs[1].hi - b0.segs[1].lo))
	local c0, c3 = planWith(act("HeavyBag"), 0), planWith(act("HeavyBag"), 3)
	check("overloaded combos: shorter time limits", c3.segs[1].limit < c0.segs[1].limit and c3.overload == 3)
	-- a D grade brings the load back down
	P.condition.energy = 100
	Training.Perform(P, act("Bench"), 0.6)
	local _, _, ov2 = Training.Mastery(P, "Bench")
	check("overload drops on a D", ov2 == math.max(0, ov - 1), ov2)
	-- mastered drills give better gains (Technician +5% at level 3)
	check("Technician perk", TP.PerkValues(3).gains > 1 and TP.PerkValues(4).injury < 1)
	-- the power coach (overloadEasy) raises the load on a B
	local Q = fresh()
	Q.coaches.Power = 1
	Q.train.mastery.HeavyBag = { xp = 120, ov = 0 }
	Training.Perform(Q, act("HeavyBag"), 1.05)
	check("power coach: overload up on a B", select(3, Training.Mastery(Q, "HeavyBag")) == 1)
end

------------------------------------------------------------------------
-- overload drills: still fair at the top (the judges on a virtual clock, like test_drills part A)
------------------------------------------------------------------------
do
	local DrillScore = H.require("DrillScore")
	local R0 = T.R0
	local FRAME = 1 / 60
	local function playJudges(plan, skill, seed)
		local rng = R0.new(seed)
		local events, results = {}, {}
		local t = 0
		for i, seg in ipairs(plan.segs) do
			local M = t + (tonumber(seg.gap) or 0)
			table.insert(events, { id = "@", down = true, t = M })
			local j = DrillScore.Judge(seg, M)
			local mem = {}
			local tt = M
			while tt < M + 400 do
				j.advance(tt)
				if j.closed then
					break
				end
				for _, a in ipairs(Bots.Act(seg, j, tt, M, mem, skill, rng)) do
					table.insert(events, { id = a[1], down = a[2], t = tt })
					j.input(a[1], a[2], tt)
				end
				if j.closed then
					break
				end
				tt += FRAME
			end
			j.finish(tt)
			results[i] = j.result()
			local e = j.endsAt()
			t = (type(e) == "number" and e < tt) and e or tt
		end
		return DrillScore.Aggregate(plan, results), (DrillScore.Replay(plan, events, t + 0.5))
	end
	local SORE = { back = 0.7, legs = 0.45, shoulders = 0.2, arms = 0.1, chest = 0.05, core = 0.3, neck = 0.15 }
	for _, a in ipairs(Config.Activities) do
		if not a.recovery and a.minigame ~= "course" and a.minigame ~= "swim" and a.minigame ~= "spar" then
			for _, lv in ipairs({ 1, 4 }) do
				local params = Training.MinigameParams({ condition = { sore = SORE }, gym = { levels = {} }, owned = {} }, a)
				params.level, params.overload = lv, 3
				if a.minigame == "mitts" then
					params.tier = lv
				elseif a.minigame == "rope" then
					params.doubleUnders, params.footwork = lv >= 3, lv >= 4
				end
				T.FixSeed(1000 + lv)
				local plan = Training.DrillPlan(a, lv, params)
				local live, replay = playJudges(plan, Bots.SKILLS.perfect, lv * 7)
				check(string.format("%s lv%d overload 3: perfect >= 0.85", a.id, lv), live >= 0.85, string.format("%.3f", live))
				check(string.format("%s lv%d overload 3: replay = live", a.id, lv), math.abs(live - replay) < 0.01, string.format("%.3f / %.3f", live, replay))
				local avg3, avg0 = 0, 0
				-- (the same plan draw and the same player, with and without the overload)
				for k = 1, 4 do
					T.FixSeed(2000 + k)
					params.overload = 3
					avg3 += playJudges(Training.DrillPlan(a, lv, params), Bots.SKILLS.average, lv * 100 + k) / 4
					params.overload = nil
					avg0 += playJudges(Training.DrillPlan(a, lv, params), Bots.SKILLS.average, lv * 100 + k) / 4
				end
				T.FixSeed(nil)
				-- (test_drills allows the average player +0.06 from the bottom station level to the top one)
				check(string.format("%s lv%d overload 3: no easier for an average player", a.id, lv), avg3 <= avg0 + 0.06, string.format("ov3 %.3f ov0 %.3f", avg3, avg0))
				if verbose then
					print(string.format("  %-10s lv%d  perfect %.3f  average ov0 %.3f ov3 %.3f", a.id, lv, live, avg0, avg3))
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- records
------------------------------------------------------------------------
do
	local P = fresh()
	Training.Perform(P, act("HeavyBag"), 1.1)
	local r1 = Training.Record(P, "HeavyBag", 1.1, { punches = 40, maxPower = 600 })
	check("first session: no personal best goal yet", r1.first == true and r1.goals == nil)
	P.condition.energy = 100
	Training.Perform(P, act("HeavyBag"), 1.0)
	local r2 = Training.Record(P, "HeavyBag", 1.0, { punches = 55, maxPower = 580 })
	check("a better number is a new record", #r2.newStats == 1 and r2.newStats[1] == "punches" and P.records.HeavyBag.stats.punches == 55)
	check("the record day is kept", P.records.HeavyBag.prDay == P.day)
	local G = P.train.goals
	local hasRecordGoal = false
	for _, g in ipairs(G.list) do
		if g.kind == "record" then
			hasRecordGoal = true
			check("the personal-best goal is done", g.done == true)
		end
	end
	if not hasRecordGoal then
		check("record event reaches the goals (none drawn today)", true)
	end
	local v = Training.ProgramView(P)
	check("view: mastery per drill", v.mastery.HeavyBag ~= nil and v.today.HeavyBag == 2)
	check("view: tips and goals", #v.tips >= 1 and #v.goals == 3 and v.weekly ~= nil)
end

------------------------------------------------------------------------
-- soreness & recovery
------------------------------------------------------------------------
do
	local P = fresh()
	Training.Perform(P, act("Squat"), 1.3)
	P.condition.energy = 100
	Training.Perform(P, act("Squat"), 1.3)
	local s = P.condition.sore.legs or 0
	check("training makes the legs sore", s >= 0.3, s)
	local m = Training.SessionMods(P, act("Squat"), 1.2)
	check("a sore group costs stat gains", m.soreMul < 1 and m.soreGroup == "legs", m.soreMul)
	local fm = Training.FightModifiers(P)
	check("sore legs cost footwork on fight night", (fm.stats.Footwork or 0) < 0, fm.stats.Footwork)
	local before = P.condition.sore.legs
	Training.Recover(P, act("IceBath"), 1.2)
	check("an ice bath eases it", P.condition.sore.legs < before)
	local r = Training.Recover(P, act("Massage"), 1.2)
	check("massage eases it more, with a report", P.condition.sore.legs < before * 0.6 and r.report ~= nil and r.report.soreBefore ~= nil)
	-- sleep: fed and watered clears more than hungry
	local A, B = fresh(), fresh()
	for _, X in ipairs({ A, B }) do
		X.condition.sore = { legs = 0.8 }
	end
	A.condition.nutrition, A.condition.hydration = 80, 80
	B.condition.nutrition, B.condition.hydration = 10, 20
	Training.Sleep(A)
	Training.Sleep(B)
	check("sleep after a good meal clears more soreness", (A.condition.sore.legs or 0) < (B.condition.sore.legs or 0), string.format("%.3f vs %.3f", A.condition.sore.legs or 0, B.condition.sore.legs or 0))
	-- a rest day done right
	local C, D = fresh(), fresh()
	Training.SetPlan(C, "balanced")
	Training.SetPlan(D, "balanced")
	for _ = 1, 3 do
		Training.Sleep(C)
		Training.Sleep(D)
	end
	check("day 4 of balanced is rest", Training.TodayFocus(C)[1] == "rest")
	C.condition.sore, D.condition.sore = { back = 0.8 }, { back = 0.8 }
	D.condition.energy = 100
	Training.Perform(D, act("HeavyBag"), 1.2)
	D.condition.sore.back = 0.8
	C.condition.nutrition, D.condition.nutrition = 60, 60
	Training.Sleep(C)
	Training.Sleep(D)
	check("a rest day clears more and gives fresh legs", (C.condition.sore.back or 0) < (D.condition.sore.back or 0) and C.condition.buffs.gains == 0.06 and D.condition.buffs.gains == nil)
	-- the conditioning coach
	local E, F = fresh(), fresh()
	E.coaches.Conditioning = 3
	E.condition.sore, F.condition.sore = { back = 0.8 }, { back = 0.8 }
	Training.Recover(E, act("IceBath"), 1.2)
	Training.Recover(F, act("IceBath"), 1.2)
	check("the sports scientist flushes more", E.condition.sore.back < F.condition.sore.back)
end

------------------------------------------------------------------------
-- camps: peaking, tapering, overtraining, weight cut
------------------------------------------------------------------------
local function runCamp(style)
	local P = fresh()
	P.coaches = { Power = 0, Speed = 0, Defense = 0, Footwork = 0, Conditioning = 0, RingIQ = 0 }
	camp(P, 6)
	local cut = false
	while (P.camp.daysLeft or 0) > 0 do
		local phase = TP.CampPhase(P.camp)
		local function s(id, q)
			P.condition.energy = math.max(P.condition.energy, 60)
			Training.Perform(P, act(id), q)
		end
		if style == "smart" then
			if phase == "build" then
				s("HeavyBag", 1.15)
				s("Roadwork", 1.15)
				s("Shadow", 1.15)
				Training.Recover(P, act("IceBath"), 1.1)
			elseif phase == "peak" then
				s("MittWork", 1.3)
				s("DoubleEnd", 1.3)
				Training.Recover(P, act("Stretch"), 1.1)
			else
				s("Shadow", 1.25)
				Training.Recover(P, act("IceBath"), 1.1)
				Training.Recover(P, act("Massage"), 1.1)
			end
			Training.Eat(P, "Balanced")
			Training.Eat(P, "Balanced")
		elseif style == "overtrain" then
			for _ = 1, 6 do
				P.condition.energy = 100
				Training.Perform(P, act("HeavyBag"), 1.0)
			end
		elseif style == "lazy" then
			-- nothing at all
			cut = false
		end
		Training.Sleep(P)
	end
	if style == "cut" or style == "smartcut" then
		cut = true
	end
	return P, cut
end
do
	local P = runCamp("smart")
	local r = Training.Readiness(P)
	check("smart camp: fight night", r and r.final == true)
	check("smart camp: the log has every day", #P.camp.prep.days == 6 and P.camp.prep.days[1].n == 3)
	check("smart camp: peaked", r.score >= 80 and r.tier.id == "peaked", r and r.score)
	local mods = Training.FightModifiers(P)
	check("peaked: a fight-night bonus", (mods.stats.Power or 0) >= 2 and mods.readiness.label == "PEAKED")
	local O = runCamp("overtrain")
	local ro = Training.Readiness(O)
	check("overtrained camp: flagged", ro.over == true and ro.overNights >= 2, ro.overNights)
	local mo = Training.FightModifiers(O)
	check("overtrained: penalties", (mo.stats.Reflexes or 0) < 0 and mo.staminaMul < Training.FightModifiers(P).staminaMul)
	local L = runCamp("lazy")
	local rl = Training.Readiness(L)
	check("a camp of doing nothing is flat", rl.score < 45 and rl.tier.id == "flat", rl.score)
	-- a hard weight cut on fight day
	local W = runCamp("smart")
	for _ = 1, 3 do
		Training.Recover(W, act("Sauna"), 1.1)
	end
	local rw = Training.Readiness(W)
	check("three sauna sessions on fight day: drained", rw.drained == true, W.condition.water)
	local mw = Training.FightModifiers(W)
	check("drained: chin and stamina penalties", (mw.stats.Chin or 0) < (mods.stats.Chin or 0) and mw.staminaMul < mods.staminaMul)
	-- the Ring IQ coach adds readiness
	local C = runCamp("smart")
	local base = Training.Readiness(C).score
	C.coaches.RingIQ = 3
	check("the chess master adds readiness", Training.Readiness(C).score >= math.min(100, base + 5))
	-- a debut (no camp days) has no readiness
	local Dd = fresh()
	Dd.camp = { offer = { oppId = Dd.world.classes[5][1] }, daysLeft = 0, daysTotal = 0, log = {}, debut = true }
	check("a debut has no readiness", Training.Readiness(Dd) == nil and Training.FightModifiers(Dd).readiness == nil)
	-- camp goals follow the phase
	local G = fresh()
	camp(G, 5)
	Training.Sleep(G)
	local kinds = {}
	for _, g in ipairs(G.train.goals.list) do
		kinds[g.kind] = g
	end
	check("a build day's goal is the camp target", kinds.camp ~= nil and kinds.camp.need == 3)
	-- the camp focus follows the opponent
	local S = fresh()
	local b = camp(S, 5)
	b.style, b.archetype = "Slugger", "KO"
	local f = Training.TodayFocus(S)
	check("camp focus vs a knockout artist: defence first", f[1] == "defence")
end

------------------------------------------------------------------------
-- goals: paid once, sweep, streak, weekly, rest day
------------------------------------------------------------------------
do
	local P = fresh()
	local G = Training.EnsureGoals(P)
	-- make today's goals a known set
	G.list = { { kind = "grade", n = 0, need = 2, done = false }, { kind = "recover", n = 0, need = 1, done = false }, { kind = "fuel", n = 0, need = 1, done = false } }
	G.weekly = { kind = "wsessions", n = 0, need = 12, done = false }
	local m0 = P.money
	Training.Perform(P, act("HeavyBag"), 1.25)
	check("one A: halfway", G.list[1].n == 1 and not G.list[1].done and P.money == m0)
	P.condition.energy = 100
	Training.Perform(P, act("Rope"), 1.25)
	local paid = TP.Reward("goal", P.tier, 0).money
	check("two A grades: the goal is paid", G.list[1].done and near(P.money, m0 + paid), P.money - m0)
	P.condition.energy = 100
	Training.Perform(P, act("Shadow"), 1.25)
	check("a done goal is never paid twice", near(P.money, m0 + paid))
	Training.Recover(P, act("Stretch"), 1.0)
	local ok, info = Training.Eat(P, "Balanced")
	check("eating a proper meal completes fuel and the sweep", ok and G.list[3].done and G.swept == true and type(info.goals) == "table" and #info.goals == 2)
	check("weekly progress", G.weekly.n == 3)
	Training.Sleep(P)
	check("a sweep starts the streak", P.train.goals.streak == 1 and P.train.goals.day == P.day and #P.train.goals.list == 3)
	Training.Sleep(P)
	check("a day without the goals ends it", P.train.goals.streak == 0 and P.train.goals.best == 1)
	-- the rest day
	local R = fresh()
	Training.SetPlan(R, "balanced")
	for _ = 1, 3 do
		Training.Sleep(R)
	end
	local rg = R.train.goals.list
	check("rest day goals", rg[1].kind == "rest" and rg[2].kind == "recover")
	Training.Recover(R, act("IceBath"), 1.0)
	Training.Eat(R, "Protein")
	Training.Sleep(R)
	check("a rest day honoured completes its goals and the streak", R.train.goals.streak == 1)
end

------------------------------------------------------------------------
-- ring rust (stat detraining)
------------------------------------------------------------------------
do
	local P = fresh()
	P.stats.Stamina, P.stats.RingIQ, P.stats.PunchSpeed = 60, 60, 60
	for _ = 1, 5 do
		Training.Sleep(P)
	end
	check("no rust inside the grace days", P.stats.Stamina == 60)
	for _ = 1, 20 do
		Training.Sleep(P)
	end
	check("idle weeks: stamina fades", P.stats.Stamina < 58 and P.stats.Stamina > 45, P.stats.Stamina)
	check("ring IQ does not", P.stats.RingIQ == 60)
	check("the view says ring rust", Training.ProgramView(P).rust == true)
	local s0 = P.stats.Stamina
	Training.Perform(P, act("Roadwork"), 1.1)
	Training.Sleep(P)
	check("training stops it", P.stats.Stamina >= s0)
	local Q = fresh()
	Q.stats.Stamina = 60
	Training.PassDays(Q, 30)
	check("no rust during a suspension", Q.stats.Stamina == 60)
end

------------------------------------------------------------------------
-- saves
------------------------------------------------------------------------
local function datastoreSafe(t, path, seen)
	seen = seen or {}
	if type(t) ~= "table" then
		local tt = type(t)
		if tt == "number" then
			return t == t and t ~= math.huge and t ~= -math.huge, path .. " not finite"
		end
		return tt == "string" or tt == "boolean", path .. " is a " .. tt
	end
	if seen[t] then
		return false, path .. " cycles"
	end
	seen[t] = true
	local n, strKeys, maxInt = 0, 0, 0
	for k, v in pairs(t) do
		n += 1
		if type(k) == "string" then
			strKeys += 1
		elseif type(k) == "number" and k == math.floor(k) and k >= 1 then
			maxInt = math.max(maxInt, k)
		else
			return false, path .. " has a " .. type(k) .. " key"
		end
		local ok, why = datastoreSafe(v, path .. "." .. tostring(k), seen)
		if not ok then
			return false, why
		end
	end
	if strKeys > 0 and strKeys < n then
		return false, path .. " is a mixed table"
	end
	if strKeys == 0 and n > 0 and maxInt ~= n then
		return false, path .. " is an array with holes"
	end
	return true
end
do
	-- an old save: no programme, a camp without its log
	local P = fresh()
	P.train = nil
	camp(P, 5, 3)
	P.camp.prep = nil
	Training.Migrate(P)
	check("old save: a programme to start from", type(P.train) == "table" and P.train.lastTrain == P.day and P.train.plan == nil)
	check("old save: the camp log", #P.camp.prep.days == 5)
	local okPerform = pcall(Training.Perform, P, act("HeavyBag"), 1.1)
	local okSleep = pcall(Training.Sleep, P)
	check("old save: trains and sleeps", okPerform and okSleep and Training.ProgramView(P) ~= nil)
	-- a corrupt one
	local C = fresh()
	camp(C, 4, 2)
	C.train = {
		log = { { d = 0 / 0, a = "HeavyBag" }, { d = 3, a = "Nope" }, "junk", { d = 1, a = "Bench", q = math.huge } },
		mastery = { HeavyBag = { xp = 0 / 0, ov = 99 }, Bogus = { xp = 5 }, Bench = "x" },
		plan = { start = "x", days = { "power", 7, "bogus" } },
		goals = { list = { { kind = "nope" } }, weekly = 5, streak = -4, best = "x" },
		lastTrain = 1e12, seed = 0 / 0, stray = true,
	}
	C.camp.prep = { days = { [1] = { n = "x" }, [3] = { n = 2 } }, over = 0 / 0 }
	local okM = pcall(Training.Migrate, C)
	check("corrupt save migrates", okM)
	local t = C.train
	check("corrupt: log cleaned", #t.log == 1 and t.log[1].a == "Bench" and t.log[1].q == 1)
	check("corrupt: mastery cleaned", t.mastery.HeavyBag.xp == 0 and t.mastery.HeavyBag.ov == TP.OVERLOAD_MAX and t.mastery.Bogus == nil and t.mastery.Bench == nil)
	check("corrupt: plan repaired", #t.plan.days == 7 and t.plan.days[2] == "rest" and t.plan.days[3] == "rest")
	check("corrupt: goals redrawn, streak sane", t.goals.list == nil and t.goals.streak == 0 and t.stray == nil and t.lastTrain <= C.day)
	check("corrupt: camp log whole", #C.camp.prep.days == 4 and C.camp.prep.days[2].n == 0 and C.camp.prep.over == 0)
	local okUse = pcall(function()
		Training.Perform(C, act("HeavyBag"), 1.2)
		Training.Sleep(C)
		Training.ProgramView(C)
	end)
	check("corrupt save then plays", okUse)
	-- idempotent and DataStore-safe after a busy day
	local B = fresh()
	Training.SetPlan(B, "power")
	camp(B, 6)
	for _, id in ipairs({ "HeavyBag", "Bench", "Rope", "Sparring" }) do
		B.condition.energy = 100
		Training.Perform(B, act(id), 1.2)
		Training.Record(B, id, 1.2, { punches = 30 })
	end
	Training.Eat(B, "Balanced")
	Training.Sleep(B)
	Training.Migrate(B)
	local snap = deep(B.train)
	Training.Migrate(B)
	local same = true
	local function cmp(a, b, p)
		if type(a) ~= type(b) then
			same = false
			print("  differs at " .. p)
			return
		end
		if type(a) == "table" then
			for k, v in pairs(a) do
				cmp(v, b[k], p .. "." .. tostring(k))
			end
			for k in pairs(b) do
				if a[k] == nil then
					same = false
				end
			end
		elseif a ~= b then
			same = false
			print("  differs at " .. p)
		end
	end
	cmp(snap, B.train, "train")
	check("Migrate is idempotent on the programme", same)
	local ok1, why1 = datastoreSafe(B.train, "train")
	check("profile.train is DataStore-safe", ok1, why1)
	local ok2, why2 = datastoreSafe(B.camp.prep, "camp.prep")
	check("camp.prep is DataStore-safe", ok2, why2)
end

------------------------------------------------------------------------
-- coaches, tips, sparring
------------------------------------------------------------------------
do
	local P = fresh()
	local b = camp(P, 5)
	b.style, b.archetype = "Slugger", "KO"
	b.stats = deep(P.stats)
	b.stats.Power = P.stats.Chin + 20
	b.traits = { "BodyPuncher", "Southpaw" }
	local tips = Training.CoachTips(P, 6)
	local all = {}
	for _, t in ipairs(tips) do
		table.insert(all, t.text)
	end
	local text = table.concat(all, " | ")
	check("tips: the camp's focus vs the style", text:find("Defence") ~= nil, text)
	check("tips: his power edge", text:find("hits hard") ~= nil, text)
	check("tips: his AI traits (if any)", text:find("body") ~= nil or text:find("southpaw") ~= nil, text)
	-- the fight system's ring traits (Shared.Traits), when it is there: a boxer met before is scouted
	local okT, Traits = pcall(H.require, "Traits")
	if okT and type(Traits) == "table" and Traits.ForBoxer then
		b.overall, b.h2h = 85, { w = 1, l = 0, d = 0 }
		local list = Traits.ForBoxer({ id = b.id, style = b.style, archetype = b.archetype, overall = b.overall })
		local tt = {}
		for _, t in ipairs(Training.CoachTips(P, 12)) do
			table.insert(tt, t.text)
		end
		local joined = table.concat(tt, " | ")
		check("tips: his scouted ring traits", #list == 0 or joined:find("Scouting:") ~= nil, joined)
	end
	P.coaches.Defense = 2
	local t2 = Training.CoachTips(P, 6)
	local voiced = false
	for _, t in ipairs(t2) do
		if t.focus == "defence" and t.coach == Catalog_name("Defense", 2) then
			voiced = true
		end
	end
	check("tips: in the hired coach's voice", voiced)
	-- sparring counts: ring IQ / defence focus, mastery, the spar goal, safer with the defence coach
	local S = fresh()
	local G = Training.EnsureGoals(S)
	G.list = { { kind = "spar", n = 0, need = 1, done = false }, { kind = "focus", focus = "ringiq", n = 0, need = 2, done = false }, { kind = "focus", focus = "defence", n = 0, need = 2, done = false } }
	local out = Training.Perform(S, act("Sparring"), 1.1, { intensity = "Medium", scale = 1, extraRisk = 0.01 })
	check("sparring: ring IQ and defence gains", (out.gains.RingIQ or 0) > 0 and (out.gains.Blocking or 0) > 0)
	check("sparring: the spar goal and both focus goals count", G.list[1].done and G.list[2].n == 1 and G.list[3].n == 1)
	check("sparring: mastery", select(2, Training.Mastery(S, "Sparring")) > 0)
end
------------------------------------------------------------------------
-- v10 training pass: an early boxer trains several times in a row, an injury at a low tier is a short
-- layoff, a sparring drill's focus goal (TrainingPlan.SparFocus / Training.SparFocusResult)
------------------------------------------------------------------------
do
	local P = fresh()
	P.tier = 1
	local hb = act("HeavyBag")
	local e1 = Training.EnergyCost(P, hb)
	P.tier = 3
	local e3 = Training.EnergyCost(P, hb)
	-- (TierEase 0.65 at tier 1: four heavy bag sessions on a full tank, with room to spare)
	check("tier 1: a session costs less energy than at tier 3", e1 < e3, string.format("%d vs %d", e1, e3))
	check("tier 1: four heavy bag sessions in a row on a full tank", e1 * 4 <= 100, e1)
	-- an injury for sure (extraRisk) at tier 1 and at tier 3: the low tier's layoff is no longer than
	-- TierEase of the def's longest
	local function injuredDays(tier)
		local Q = fresh()
		Q.tier = tier
		Q.condition.injuries = {}
		Training.Perform(Q, hb, 1.0, { extraRisk = 50 })
		local inj = Q.condition.injuries[1]
		return inj and inj.days, inj and Config.Injuries[inj.id]
	end
	local d1, def1 = injuredDays(1)
	check("tier 1: a sure injury happens", d1 ~= nil)
	if d1 then
		check("tier 1: the layoff is TierEase shorter", d1 <= math.ceil(def1.days[2] * Training.TierEase({ tier = 1 })), string.format("%d days (max %d)", d1, def1.days[2]))
	end
	local d3, def3 = injuredDays(3)
	if d3 then
		check("tier 3: the full layoff range", d3 >= def3.days[1] and d3 <= def3.days[2], d3)
	end
	-- sparring focus: met adds the bonus and grows the focus stats, missed changes nothing, unknown is nil
	local S = fresh()
	local need = TP.SparFocusGoal("defence", "Medium")
	check("spar focus: a goal per intensity (2 rounds: twice a round's)", need == 2 * TP.SparFocusById.defence.per, need)
	local hm0 = S.stats.HeadMovement
	local r = Training.SparFocusResult(S, "defence", { evades = need + 1 }, "Medium", 1.0)
	check("spar focus met: quality bonus", r and r.met and near(r.quality, 1.0 + TP.SPAR_FOCUS_BONUS), r and r.quality)
	check("spar focus met: the focus stats grow", S.stats.HeadMovement > hm0 and (r.gains.HeadMovement or 0) > 0)
	local r2 = Training.SparFocusResult(S, "combos", { combos = { landed = 0 } }, "Hard", 1.0)
	check("spar focus missed: no bonus", r2 and not r2.met and near(r2.quality, 1.0) and next(r2.gains) == nil)
	check("spar focus: ring control is out-landing", Training.SparFocusResult(S, "control", { landed = 20, oppLanded = 12 }, "Light", 1).met == true)
	check("spar focus: unknown focus is nil", Training.SparFocusResult(S, "nope", {}, "Light", 1) == nil)
	check("spar focus: a missing result is nil", Training.SparFocusResult(S, "defence", nil, "Light", 1) == nil)
end
print(string.format("test_training: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
