--!nocheck
-- tools/sim/test_drills.luau: every training drill, played by simulated players (tools/sim/drillbots.luau).
--
-- Part A (the judges, a few seconds): for every activity with a drill and station levels 1, 3 and 5, the
-- server's plan (Training.DrillPlan) is played by a perfect, an average and an idle player through the shared
-- judges (DrillScore / DrillWorkouts) on a virtual clock, with the client's pacing (each segment's gap). The
-- input stream goes through the server's replay (DrillScore.Replay) and must give the same score the judges
-- gave live; perfect >= 0.85, idle <= 0.15 (the sauna's coach pull-out: <= 0.3), average in between and clear
-- of both; a perfect session is never "too quick" (plan.minTime); the average player does no better on the
-- top level than on the first (difficulty scales).
--
-- Part B (the real client, one process per activity): Activities.Start on guisim with a fake server
-- (StartActivity hands over the real plan; ActivityInput is recorded; FinishActivity replays it) and a virtual
-- clock stepped at 60 Hz. The bot plays through the drill's own inputs on keyboard (UserInputService keys from
-- the drill's key map), gamepad (its pad buttons) and touch (its on-screen buttons): every action a bot uses
-- must be reachable on all three. Checks: the session ends and hands in, the client's score equals the
-- server's replay, the score bands as in part A, the drill's numbers (ctx.out) are a valid stats table for
-- Training.SanitizeStats / Record (at most 8 keys), and the pose attributes the animation follows move.
--
--   lune run tools/sim/test_drills.luau                 # both parts
--   lune run tools/sim/test_drills.luau --judges        # part A only
--   lune run tools/sim/test_drills.luau --only Bench,Sauna [-v]
local Host = require("./host")
local Bots = require("./drillbots")
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local args = process.args
local judgesOnly = table.find(args, "--judges") ~= nil
local verbose = table.find(args, "-v") ~= nil
local only
do
	local at = table.find(args, "--only")
	if at and args[at + 1] then
		only = {}
		for s in args[at + 1]:gmatch("[^,]+") do
			only[s] = true
		end
	end
end

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
local DrillScore = H.require("DrillScore")
local Random = H.globals.Random
-- the server draws its plans with an unseeded Random: seeded here, so every run plays the same plans
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

-- the drills (course / swim are measured by the server's own tracking, sparring is a fight)
local ACTS = {}
for _, act in ipairs(Config.Activities) do
	if act.minigame ~= "course" and act.minigame ~= "swim" and act.minigame ~= "spar" and (not only or only[act.id]) then
		table.insert(ACTS, act)
	end
end
-- the soreness the massage plan reads (a profile's condition.sore)
local SORE = { back = 0.7, legs = 0.45, shoulders = 0.2, arms = 0.1, chest = 0.05, core = 0.3, neck = 0.15 }
local function paramsFor(act, lv)
	local p = { level = lv }
	if act.minigame == "mitts" then
		p.tier = lv
	elseif act.minigame == "rope" then
		p.doubleUnders, p.footwork = lv >= 3, lv >= 4
	elseif act.minigame == "massage" then
		p.sore = SORE
	elseif act.minigame == "stretch" then
		p.stretchNames = { "HAMSTRINGS", "HIP FLEXORS", "SHOULDERS", "CALVES" }
	end
	return p
end
-- the server's own params (Training.MinigameParams on a profile) for a level-lv station
local function serverParams(act, lv)
	local prof = { condition = { sore = SORE }, gym = { levels = {} }, owned = {} }
	local ok, p = pcall(Training.MinigameParams, prof, act)
	if ok and type(p) == "table" then
		p.level = lv
		if act.minigame == "mitts" then
			p.tier = lv
		elseif act.minigame == "rope" then
			p.doubleUnders, p.footwork = lv >= 3, lv >= 4
		end
		return p
	end
	return paramsFor(act, lv)
end

local LIMITS = { idle = 0.15, perfect = 0.85 }
local IDLE_MAX = { Sauna = 0.3 }

------------------------------------------------------------------------
-- Part A: the judges on a virtual clock
------------------------------------------------------------------------
local FRAME = 1 / 60
local function playJudges(plan, skill, seed)
	local rng = Random.new(seed)
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
		check(string.format("%s seg %d (%s) closes", plan.kind, i, seg.j), tt < M + 400)
	end
	local live = DrillScore.Aggregate(plan, results)
	local replay, _, pacing = DrillScore.Replay(plan, events, t + 0.5)
	return live, replay, t, pacing
end

local isChild = table.find(args, "--child") ~= nil
local scores = {}
for _, act in ipairs(isChild and {} or ACTS) do
	scores[act.id] = {}
	for _, lv in ipairs({ 1, 3, 5 }) do
		local plan = Training.DrillPlan(act, lv, serverParams(act, lv))
		check(act.id .. " plan", plan ~= nil and #plan.segs > 0)
		if plan then
			local row = {}
			for _, sk in ipairs({ "perfect", "average", "idle" }) do
				-- the average player over four plans and seeds (one unlucky draw says little)
				local runs = sk == "average" and 4 or 1
				local sum, sumR = 0, 0
				for k = 1, runs do
					if k > 1 then
						plan = Training.DrillPlan(act, lv, serverParams(act, lv))
					end
					local live, replay, dur, pacing = playJudges(plan, Bots.SKILLS[sk], lv * 1000 + k)
					sum += live
					sumR += replay
					check(string.format("%s lv%d %s: replay = live", act.id, lv, sk), math.abs(live - replay) < 0.01, string.format("live %.3f replay %.3f", live, replay))
					check(string.format("%s lv%d %s: pacing kept", act.id, lv, sk), pacing.late == 0, pacing.late)
					if sk == "perfect" then
						check(string.format("%s lv%d perfect not too quick", act.id, lv), dur >= 0.8 * (plan.minTime or 0), string.format("%.1f s vs min %.1f", dur, plan.minTime or 0))
					end
				end
				row[sk] = sum / runs
			end
			scores[act.id][lv] = row
			local idleMax = IDLE_MAX[act.id] or LIMITS.idle
			check(string.format("%s lv%d perfect >= %.2f", act.id, lv, LIMITS.perfect), row.perfect >= LIMITS.perfect, string.format("%.3f", row.perfect))
			check(string.format("%s lv%d idle <= %.2f", act.id, lv, idleMax), row.idle <= idleMax, string.format("%.3f", row.idle))
			check(string.format("%s lv%d average between", act.id, lv), row.average >= row.idle + 0.1 and row.average <= row.perfect - 0.08 and row.average >= 0.2 and row.average <= 0.85,
				string.format("idle %.3f average %.3f perfect %.3f", row.idle, row.average, row.perfect))
			if verbose then
				print(string.format("  %-10s lv%d  perfect %.3f  average %.3f  idle %.3f", act.id, lv, row.perfect, row.average, row.idle))
			end
		end
	end
	local s = scores[act.id]
	if s[1] and s[5] then
		check(act.id .. " harder at the top level (average player)", s[5].average <= s[1].average + 0.06, string.format("lv1 %.3f lv5 %.3f", s[1].average, s[5].average))
	end
end
if not isChild then
	print(string.format("test_drills part A: %d passed, %d failed", pass, fail))
end
if judgesOnly then
	process.exit(fail == 0 and 0 or 1)
end

------------------------------------------------------------------------
-- Part B: the real client drill (Activities.Start) on guisim, a virtual clock and a fake server
------------------------------------------------------------------------
local GS = require("./guisim")

-- the runs per activity: the perfect player on every device (each action reachable on each), the average
-- player on a phone, the idle player on a controller
local RUNS = { { "desktop", "perfect" }, { "console", "perfect" }, { "phone", "perfect" }, { "phone", "average" }, { "console", "idle" } }
-- the pose attributes each kind must drive (the animation follows the drill's own phases)
local POSE_NEEDS = {
	bench = { "PoseDrive", "PoseTilt" }, deadlift = { "PoseDrive", "PoseGrip" }, squat = { "PoseDrive" }, pullup = { "PoseDrive", "PoseSwing" },
	curls = { "PoseDrive", "CurlSide" }, treadmill = { "PoseSpeed", "PoseIncline" }, bike = { "PoseSpeed" }, rower = { "PoseDrive" },
	icebath = { "PoseLungs", "PoseShiver" }, stretch = { "PoseDrive", "PoseStretch" }, sauna = { "PoseHeat" },
}
local WATCH = { "PoseDrive", "PoseTilt", "PoseGrip", "PoseSwing", "CurlSide", "PoseSpeed", "PoseIncline", "PoseLungs", "PoseShiver", "PoseStretch", "PoseHeat" }

local DrillSim = require("./drillsim")

local function clientProfile(S)
	local Career = DrillSim.ServerModule(S.host, "Career")
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, { first = "Marcus", last = "Reed", name = "Marcus Reed", nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1) }, 1)
	prof.condition.sore = table.clone(SORE)
	local P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = false }
	return P
end

local function clientRun(actId, dev, skillName, lv)
	local act = Config.FindById(Config.Activities, actId)
	local S = GS.new(dev)
	local Hh = S.host
	DrillSim.SeedRandom(Hh)
	local P = clientProfile(S)
	S.P = P
	S.onInvokeServer = function(_, action)
		if action == "GetProfile" then
			return P
		end
		return { ok = false }
	end
	S.loadScript("client/ClientMain.client.lua")
	S.settle(0.3)
	local D = DrillSim.Attach(S, { act = act, lv = lv, params = paramsFor(act, lv), P = P })
	local SDrill = Hh.require("DrillScore")
	D.start()
	local rng = Random.new(4242)
	local skill = Bots.SKILLS[skillName]
	local mem, seen, lastAttr = {}, {}, {}
	local infoBad
	local frame = 0
	while frame < 60 * 400 and not D.finished and not D.cancelled do
		frame = D.frame()
		local ctx = D.ctx()
		if ctx and ctx.segI > 0 and not ctx.resting then
			local j = ctx.judges[ctx.segI]
			if j and not j.closed then
				local seg = ctx.plan.segs[ctx.segI]
				mem[ctx.segI] = mem[ctx.segI] or {}
				-- the drill's prompts name this device's controls (no raw {tokens}; no keyboard keys on touch / pad)
				if not infoBad and ctx.info then
					local txt = ctx.info.Text or ""
					if txt:find("[{}]") or (dev ~= "desktop" and (txt:find("SPACE") or txt:find("W/A/S/D"))) then
						infoBad = txt
					end
				end
				for _, a in ipairs(Bots.Act(seg, j, ctx.now(), ctx.segAt, mem[ctx.segI], skill, rng)) do
					D.send(a[1], a[2])
				end
			end
		end
		for _, name in ipairs(WATCH) do
			local v = D.char:GetAttribute(name)
			if v ~= nil and v ~= lastAttr[name] then
				lastAttr[name] = v
				seen[name] = (seen[name] or 0) + 1
			end
		end
	end
	local out = { finished = D.finished, cancelled = D.cancelled, frames = frame, unreachable = D.unreachable, infoBad = infoBad, seen = seen, plan = D.plan }
	if D.finished and D.plan then
		out.client = math.clamp(((D.finished.quality or 0.5) - 0.5) / 0.95, 0, 1)
		out.server = SDrill.Replay(D.plan, D.events, D.finished.tEnd + 0.05)
		out.stats = D.finished.stats
		out.events = #D.events
	end
	return out
end

local childAt = table.find(args, "--child")
if childAt then
	pass, fail = 0, 0
	local actId = args[childAt + 1]
	local act = Config.FindById(Config.Activities, actId)
	local lv = 3
	for _, run in ipairs(RUNS) do
		local dev, sk = run[1], run[2]
		local tag = string.format("%s@%s %s", actId, dev, sk)
		local ok, r = pcall(clientRun, actId, dev, sk, lv)
		check(tag .. " runs", ok, r)
		if ok then
			check(tag .. " hands the session in", r.finished ~= nil, r.cancelled and "cancelled" or ("frames " .. r.frames))
			local miss = {}
			for id, why in pairs(r.unreachable) do
				table.insert(miss, id .. " (" .. why .. ")")
			end
			check(tag .. " every action reachable", #miss == 0, table.concat(miss, ", "))
			check(tag .. " prompts name this device's controls", r.infoBad == nil, r.infoBad)
			if r.finished then
				check(tag .. " client score = server replay", math.abs(r.client - r.server) < 0.02, string.format("client %.3f server %.3f (%d inputs)", r.client, r.server, r.events or 0))
				local stats = r.stats or {}
				local n, okStats = 0, true
				for k, v in pairs(stats) do
					n += 1
					if type(k) ~= "string" or #k > 20 or not k:match("^%a[%w_]*$") or type(v) ~= "number" or v ~= v then
						okStats = false
					end
				end
				check(tag .. " drill numbers are a valid stats table", okStats and n <= 8, string.format("%d keys", n))
				if sk == "perfect" then
					check(tag .. " perfect >= 0.85", r.server >= 0.85, string.format("%.3f", r.server))
					for _, name in ipairs(POSE_NEEDS[act.minigame] or {}) do
						check(tag .. " drives " .. name, (r.seen[name] or 0) >= 2, r.seen[name] or 0)
					end
				elseif sk == "idle" then
					check(tag .. " idle low", r.server <= (IDLE_MAX[actId] or LIMITS.idle), string.format("%.3f", r.server))
				else
					check(tag .. " average in between", r.server >= 0.2 and r.server <= 0.9, string.format("%.3f", r.server))
				end
				if verbose then
					print(string.format("  %-28s client %.3f server %.3f  %d inputs  %.0f s", tag, r.client, r.server, r.events or 0, r.frames / 60))
				end
			end
		end
	end
	print(string.format("CHILD %d %d", pass, fail))
	process.exit(0)
end

-- one process per activity (a client leaves threads and instances behind), four at a time
local jobs = {}
for _, act in ipairs(ACTS) do
	table.insert(jobs, act.id)
end
local self = Host.FindRoot() .. "/tools/sim/test_drills.luau"
local nextJob, running = 1, 0
local function worker()
	while nextJob <= #jobs do
		local id = jobs[nextJob]
		nextJob += 1
		local cmd = { "run", self, "--child", id }
		if verbose then
			table.insert(cmd, "-v")
		end
		local r = process.exec("lune", cmd)
		local outp = r.stdout or ""
		local p, f = outp:match("CHILD (%d+) (%d+)")
		if not p then
			fail += 1
			print(string.format("FAIL %s: the child process did not finish (%s)", id, ((r.stderr or "") .. outp):sub(-600)))
		else
			pass += tonumber(p)
			fail += tonumber(f)
			for line in outp:gmatch("[^\n]+") do
				if line:match("^FAIL ") or line:match("^      ") or (verbose and line:match("^  ")) then
					print(line)
				end
			end
		end
	end
	running -= 1
end
for _ = 1, 4 do
	running += 1
	task.spawn(worker)
end
while running > 0 do
	task.wait(0.1)
end
print(string.format("test_drills: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
