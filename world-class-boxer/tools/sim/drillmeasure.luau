--!nocheck
-- tools/sim/drillmeasure.luau: how the training drills feel, measured. Every activity with a drill, at
-- station levels 1 / 3 / 5, played through the shared judges on a virtual clock (as test_drills part A)
-- by the simulated players of drillbots.luau at three skills - low (slow reactions, a human's timing
-- error and then some), average and high - over several plan draws. Per row: the session's length
-- (every gap the client paces plus the work itself), the session score, and the player's reps graded
-- perfect / good / miss by each judge's own idea of a rep (a combination, a call, a note, a lift, a
-- stroke, a timed piece's share in the zone...).
--
--   lune run tools/sim/drillmeasure.luau                       # the working tree
--   lune run tools/sim/drillmeasure.luau --src /tmp/before/src # another tree's src (the "before")
--   lune run tools/sim/drillmeasure.luau --only HeavyBag,Rope --runs 6 --skills low,high
--
-- Targets (the brief): a low-skill player gets good-or-better on >= 70% of reps and every session is
-- under 40 s. The summary at the end counts the rows against them.
local Host = require("./host")
local Bots = require("./drillbots")
local fs = require("@lune/fs")
local process = require("@lune/process")

local args = process.args
local function argAfter(flag)
	local at = table.find(args, flag)
	return at and args[at + 1] or nil
end
local srcDir = argAfter("--src")
local runs = tonumber(argAfter("--runs")) or 4
local only
do
	local list = argAfter("--only")
	if list then
		only = {}
		for s in list:gmatch("[^,]+") do
			only[s] = true
		end
	end
end
local skills = { "low", "average", "high" }
do
	local list = argAfter("--skills")
	if list then
		skills = {}
		for s in list:gmatch("[^,]+") do
			table.insert(skills, s)
		end
	end
end
local levels = { 1, 3, 5 }
do
	local list = argAfter("--levels")
	if list then
		levels = {}
		for s in list:gmatch("[^,]+") do
			table.insert(levels, tonumber(s))
		end
	end
end

local H = Host.new({ src = srcDir })
local Config = H.require("Config")
local DrillScore = H.require("DrillScore")
local Workouts = DrillScore.Workouts
local Random = H.globals.Random
do
	local seedN = 0
	H.globals.Random = setmetatable({
		new = function(seed)
			seedN += 1
			return Random.new(seed or (7919 * seedN))
		end,
	}, { __index = Random })
end
local function serverModule(Hh, name)
	local folder = rawget(Hh, "_serverFolder")
	if not folder then
		folder = Host.NewNode("Server", "Folder", Hh.Service("ServerScriptService"))
		for _, f in ipairs(fs.readDir(Hh.src .. "/server")) do
			local base = f:match("^(.-)%.lua$")
			if base and not f:find("%.server%.") then
				local n = Host.NewNode(base, "ModuleScript", folder)
				rawset(n, "_file", Hh.src .. "/server/" .. f)
			end
		end
		rawset(Hh, "_serverFolder", folder)
	end
	return Hh.requireNode(folder._kids[name])
end
local Training = serverModule(H, "Training")

local ACTS = {}
for _, act in ipairs(Config.Activities) do
	if act.minigame ~= "course" and act.minigame ~= "swim" and act.minigame ~= "spar" and (not only or only[act.id]) then
		table.insert(ACTS, act)
	end
end
local SORE = { back = 0.7, legs = 0.45, shoulders = 0.2, arms = 0.1, chest = 0.05, core = 0.3, neck = 0.15 }
local function serverParams(act, lv)
	local prof = { condition = { sore = SORE }, gym = { levels = {} }, owned = {} }
	local ok, p = pcall(Training.MinigameParams, prof, act)
	if not (ok and type(p) == "table") then
		p = {}
	end
	p.level = lv
	if act.minigame == "mitts" then
		p.tier = lv
	elseif act.minigame == "rope" then
		p.doubleUnders, p.footwork = lv >= 3, lv >= 4
	elseif act.minigame == "massage" then
		p.sore = p.sore or SORE
	elseif act.minigame == "stretch" then
		p.stretchNames = p.stretchNames or { "HAMSTRINGS", "HIP FLEXORS", "SHOULDERS", "CALVES" }
	end
	return p
end

------------------------------------------------------------------------
-- the reps of a segment, graded from its judge's result (and its live state where the result is a sum)
------------------------------------------------------------------------
local function band3(v, perfect, good)
	return v >= perfect and "perfect" or (v >= good and "good" or "miss")
end
local function units(seg, j, r)
	local out = {}
	local function add(g, n)
		for _ = 1, n or 1 do
			table.insert(out, g)
		end
	end
	local k = seg.j
	if k == "seq" then
		if r.complete and r.wrong == 0 then
			add((r.beatQ or r.frac / 0.6) >= 0.8 and "perfect" or "good")
		elseif r.complete and r.wrong <= 1 then
			add("good")
		else
			add("miss")
		end
	elseif k == "call" then
		add("perfect", r.perfect)
		add("good", r.good + r.held)
		add("miss", r.wrong + r.missed + r.bitten)
	elseif k == "cue" then
		add(r.correct and (r.rt < seg.window * 0.4 and "perfect" or "good") or "miss")
	elseif k == "counter" then
		add(r.step == 3 and r.rt and (r.rt < seg.cw * 0.4 and "perfect" or "good") or "miss")
	elseif k == "rebound" then
		add(r.ok and (math.abs(r.dt or 0) < seg.w * 0.4 and "perfect" or "good") or "miss")
	elseif k == "needle" then
		add(band3(r.timing, 0.9, 0.6))
	elseif k == "burst" then
		add(band3(r.count / seg.dur / seg.target, 0.95, 0.7))
	elseif k == "notes" then
		add("perfect", r.perfect)
		add("good", r.good)
		add("miss", r.count - r.perfect - r.good)
	elseif k == "tempo" then
		for _, n in ipairs(j.notes) do
			add(band3(n.q or 0, 0.9, 0.6))
		end
	elseif k == "rope" then
		add("good", r.clean)
		add("miss", r.jumps - r.clean)
	elseif k == "lights" then
		add("good", r.correct)
		add("miss", r.n - r.correct)
	elseif k == "rower" then
		for _, st in ipairs(j.strokes) do
			add(band3(st.q, 0.9, 0.6))
		end
		add("miss", math.max(0, math.floor(0.8 * r.expected + 0.5) - #j.strokes))
	elseif k == "massage" then
		for _, p in ipairs(j.picks) do
			add(band3(p.q, 0.99, 0.6))
		end
		add(band3((r.relax - 0.5 * r.stray) / math.max(1, r.strokes), 0.85, 0.55))
	elseif k == "pace" then
		add(band3(r.inZone / r.duration / DrillScore.PACE_FULL, 0.9, 0.6))
	elseif k == "breath" then
		add(band3(r.sync / r.duration, 0.9, 0.65))
	elseif k == "treadmill" or k == "bike" or k == "chamber" or k == "wobble" then
		add(band3(r.acc / r.duration / Workouts.TIMED_FULL, 0.9, 0.6))
	elseif k == "icebath" then
		add(band3(r.calm / r.duration / Workouts.TIMED_FULL, 0.9, 0.6))
		add(band3(r.good / math.max(1, 0.85 * r.expected), 0.9, 0.6))
	elseif k == "sauna" then
		add(band3(Workouts.SaunaScore(r), 0.9, 0.6))
	elseif r.q then
		add(band3(r.q, 0.9, 0.65))
	end
	return out
end

local FRAME = 1 / 60
local function play(plan, skill, seed)
	local rng = Random.new(seed)
	local results, t = {}, 0
	local grades = { perfect = 0, good = 0, miss = 0 }
	for i, seg in ipairs(plan.segs) do
		local M = t + (tonumber(seg.gap) or 0)
		local j = DrillScore.Judge(seg, M)
		local mem = {}
		local tt = M
		while tt < M + 400 do
			j.advance(tt)
			if j.closed then
				break
			end
			for _, a in ipairs(Bots.Act(seg, j, tt, M, mem, skill, rng)) do
				j.input(a[1], a[2], tt)
			end
			if j.closed then
				break
			end
			tt += FRAME
		end
		j.finish(tt)
		results[i] = j.result()
		for _, g in ipairs(units(seg, j, results[i])) do
			grades[g] += 1
		end
		local e = j.endsAt()
		t = (type(e) == "number" and e < tt) and e or tt
	end
	return DrillScore.Aggregate(plan, results), t, grades
end

local rows = {}
print(string.format("%-10s lv  %-8s %6s %6s %5s %5s %5s   (src %s)", "drill", "skill", "secs", "score", "perf", "good+", "miss", srcDir or "working tree"))
for _, act in ipairs(ACTS) do
	for _, lv in ipairs(levels) do
		for _, skName in ipairs(skills) do
			local sk = Bots.SKILLS[skName]
			local sumT, sumS, g = 0, 0, { perfect = 0, good = 0, miss = 0 }
			for k = 1, runs do
				local plan = Training.DrillPlan(act, lv, serverParams(act, lv))
				local score, dur, grades = play(plan, sk, lv * 1000 + k)
				sumT += dur
				sumS += score
				for key, v in pairs(grades) do
					g[key] += v
				end
			end
			local n = math.max(1, g.perfect + g.good + g.miss)
			local row = { act = act.id, lv = lv, skill = skName, secs = sumT / runs, score = sumS / runs, perfect = g.perfect / n, goodPlus = (g.perfect + g.good) / n, miss = g.miss / n }
			table.insert(rows, row)
			print(string.format("%-10s %d   %-8s %6.1f %6.3f %4d%% %4d%% %4d%%", act.id, lv, skName, row.secs, row.score, math.floor(row.perfect * 100 + 0.5), math.floor(row.goodPlus * 100 + 0.5), math.floor(row.miss * 100 + 0.5)))
		end
	end
end

-- the summary against the targets
local bySkill = {}
local over40, longest, longestRow = 0, 0, nil
for _, r in ipairs(rows) do
	local b = bySkill[r.skill]
	if not b then
		b = { n = 0, secs = 0, score = 0, perfect = 0, goodPlus = 0, miss = 0, under70 = {} }
		bySkill[r.skill] = b
	end
	b.n += 1
	b.secs += r.secs
	b.score += r.score
	b.perfect += r.perfect
	b.goodPlus += r.goodPlus
	b.miss += r.miss
	if r.goodPlus < 0.7 then
		table.insert(b.under70, string.format("%s lv%d %d%%", r.act, r.lv, math.floor(r.goodPlus * 100 + 0.5)))
	end
	if r.secs > 40 then
		over40 += 1
	end
	if r.secs > longest then
		longest, longestRow = r.secs, r
	end
end
print("")
for _, skName in ipairs(skills) do
	local b = bySkill[skName]
	if b then
		print(string.format("%-8s  avg %5.1f s  score %.3f  perfect %d%%  good-or-better %d%%  miss %d%%", skName, b.secs / b.n, b.score / b.n,
			math.floor(b.perfect / b.n * 100 + 0.5), math.floor(b.goodPlus / b.n * 100 + 0.5), math.floor(b.miss / b.n * 100 + 0.5)))
		if #b.under70 > 0 then
			print(string.format("          under 70%% good-or-better: %s", table.concat(b.under70, ", ")))
		end
	end
end
print(string.format("sessions over 40 s: %d of %d (longest %.1f s: %s lv%d %s)", over40, #rows, longest, longestRow and longestRow.act or "-", longestRow and longestRow.lv or 0, longestRow and longestRow.skill or "-"))
