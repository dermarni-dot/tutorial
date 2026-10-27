--!nocheck
-- tools/sim/drillpreview.luau: every training drill's board mid-session, dumped for tools/ui/render_mock.py.
-- The real client drill (Activities.Start through drillsim.luau: the server's real plan, a virtual clock) is
-- played by drillbots' average player up to the segment a board belongs to, a few frames into it, and the
-- screen is written with GS.WriteBoxes; plus the sparring picker (its drill focus) and a drill's end-of-session
-- report (the short summary).
--
--   lune run tools/sim/drillpreview.luau [--out tools/sim/out/training] [--only pullup,sled] [--devices phone,desktop]
--   python3 tools/ui/render_mock.py --all tools/sim/out/training --out previews/final/v10/training
local Host = require("./host")
local Bots = require("./drillbots")
local GS = require("./guisim")
local DrillSim = require("./drillsim")
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local args = process.args
local function argAfter(flag)
	local at = table.find(args, flag)
	return at and args[at + 1] or nil
end
local outDir = argAfter("--out") or (Host.FindRoot() .. "/tools/sim/out/training")
local function list(flag, default)
	local v = argAfter(flag)
	if not v then
		return default
	end
	local out = {}
	for s in v:gmatch("[^,]+") do
		out[s] = true
	end
	return out
end
local only = list("--only", nil)
local devices = list("--devices", { phone = true, desktop = true })

-- { screen, activity, the judge to stop in, frames into it, level, predicate(seg) }
local BOARDS = {
	{ "heavybag_combo", "HeavyBag", "seq", 40, 3 },
	{ "heavybag_power", "HeavyBag", "needle", 50, 3 },
	{ "heavybag_burst", "HeavyBag", "burst", 90, 3 },
	{ "speedbag_rhythm", "SpeedBag", "notes", 220, 3 },
	{ "doubleend_reaction", "DoubleEnd", "cue", 30, 3 },
	{ "doubleend_counter", "DoubleEnd", "counter", 40, 3 },
	{ "doubleend_rebound", "DoubleEnd", "rebound", 40, 3 },
	{ "mitts_call", "MittWork", "call", 70, 3, function(seg)
		return table.find(seg.ids, "feint") ~= nil
	end },
	{ "shadow_mirror", "Shadow", "cue", 20, 3 },
	{ "shadow_flow", "Shadow", "seq", 40, 3 },
	{ "bench", "Bench", "bench", 60, 3 },
	{ "deadlift", "Barbell", "deadlift", 60, 3 },
	{ "neck_harness", "Barbell", "gauge", 100, 3 },
	{ "squat", "Squat", "squat", 50, 3 },
	{ "sled_push", "Squat", "mash", 80, 3 },
	{ "pullup_grip", "PullUps", "pullup", 70, 3 },
	{ "curls_tempo", "Dumbbells", "tempo", 150, 3 },
	{ "forearm_grip", "Dumbbells", "gauge", 120, 3 },
	{ "medball_slam", "MedBall", "lift", 30, 3 },
	{ "core_plank", "MedBall", "wobble", 150, 3 },
	{ "treadmill_console", "Treadmill", "treadmill", 200, 3 },
	{ "roadwork_pace", "Treadmill", "road", 200, 3 },
	{ "bike", "Bike", "bike", 200, 3 },
	{ "rower", "Rower", "rower", 160, 3 },
	{ "ladder_steps", "Ladder", "notes", 150, 3 },
	{ "ladder_lights", "Ladder", "lights", 60, 5 },
	{ "rope_doubles", "Rope", "rope", 100, 3, function(seg)
		return seg.mode == "doubles"
	end },
	{ "icebath", "IceBath", "icebath", 150, 3 },
	{ "stretch", "Stretch", "stretch", 90, 3 },
	{ "massage", "Massage", "massage", 60 * 8, 3 },
	{ "chamber", "Chamber", "chamber", 400, 3 },
	{ "sauna", "Sauna", "sauna", 300, 3 },
	{ "spar_picker", "Sparring", nil, 0, 3 },
	{ "session_summary", "PullUps", nil, 0, 3 },
}
local SORE = { back = 0.7, legs = 0.45, shoulders = 0.2, arms = 0.1, chest = 0.05, core = 0.3, neck = 0.15 }

local function clientProfile(S)
	local Career = DrillSim.ServerModule(S.host, "Career")
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, { first = "Marcus", last = "Reed", name = "Marcus Reed", nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1) }, 1)
	prof.condition.sore = table.clone(SORE)
	local P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = false }
	return P, prof
end

local function paramsFor(Config, act, lv)
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

local function shoot(board, dev)
	local name, actId, judge, frames, lv, pred = board[1], board[2], board[3], board[4], board[5], board[6]
	local S = GS.new(dev)
	local Hh = S.host
	DrillSim.SeedRandom(Hh)
	local P, prof = clientProfile(S)
	S.P = P
	S.onInvokeServer = function(_, action)
		if action == "GetProfile" then
			return P
		end
		return { ok = false }
	end
	S.loadScript("client/ClientMain.client.lua")
	S.settle(0.3)
	local Config = S.require("Config")
	local act = Config.FindById(Config.Activities, actId)
	if name == "spar_picker" then
		local Activities = Hh.require("Client/Activities")
		local State = Hh.require("Client/State")
		State.sparFocus = "defence"
		Activities.SparPicker()
		S.settle(0.4)
		return S
	end
	local Training = DrillSim.ServerModule(Hh, "Training")
	local finish
	if name == "session_summary" then
		finish = function(quality, stats)
			local q = 0.5 + 0.95 * math.clamp(((quality or 1) - 0.5) / 0.95, 0, 1)
			local result = Training.Perform(prof, act, q)
			local record = Training.Record(prof, act.id, q, Training.SanitizeStats(stats) or {})
			return { ok = true, result = result, quality = q, act = act.id, record = record }
		end
	end
	local D = DrillSim.Attach(S, { act = act, lv = lv, params = paramsFor(Config, act, lv), P = P, finish = finish })
	D.start()
	local rng = Hh.globals.Random.new(77)
	local mem = {}
	local function play()
		local ctx = D.ctx()
		if ctx and ctx.segI > 0 and not ctx.resting then
			local j = ctx.judges[ctx.segI]
			if j and not j.closed then
				local seg = ctx.plan.segs[ctx.segI]
				mem[ctx.segI] = mem[ctx.segI] or {}
				for _, a in ipairs(Bots.Act(seg, j, ctx.now(), ctx.segAt, mem[ctx.segI], Bots.SKILLS.average, rng)) do
					D.send(a[1], a[2])
				end
			end
		end
	end
	if name == "session_summary" then
		-- the whole session, then the report card (its kicker and the summary lines)
		local function named(nm)
			for _, d in ipairs(S.playerGui:GetDescendants()) do
				if d.Name == nm and d.Visible ~= false then
					return d
				end
			end
			return nil
		end
		for _ = 1, 60 * 200 do
			D.frame()
			play()
			if named("ReportKicker") then
				break
			end
		end
		for _ = 1, 150 do
			D.frame()
		end
		return S
	end
	local reached = false
	for _ = 1, 60 * 240 do
		D.frame()
		play()
		local ctx = D.ctx()
		local seg = ctx and ctx.plan.segs[ctx.segI]
		if seg and seg.j == judge and ctx.judges[ctx.segI] ~= nil and not ctx.resting and (pred == nil or pred(seg)) then
			reached = true
			break
		end
		if D.finished or D.cancelled then
			break
		end
	end
	assert(reached, name .. ": the drill never reached its " .. judge .. " segment")
	for _ = 1, frames do
		D.frame()
		play()
	end
	return S
end

local childAt = table.find(args, "--child")
if childAt then
	local name, dev = args[childAt + 1], args[childAt + 2]
	local board
	for _, b in ipairs(BOARDS) do
		if b[1] == name then
			board = b
		end
	end
	local ok, S = pcall(shoot, board, dev)
	if not ok then
		print("ERROR " .. tostring(S))
		process.exit(1)
	end
	local items = S.collect()
	local file = string.format("%s/%s_%s.json", outDir, name, dev)
	GS.WriteBoxes(file, S, items, { title = name .. "  ·  " .. dev })
	print("WROTE " .. file)
	process.exit(0)
end

fs.writeDir(outDir)
local jobs = {}
for _, b in ipairs(BOARDS) do
	if not only or only[b[1]] then
		for dev in pairs(devices) do
			table.insert(jobs, { b[1], dev })
		end
	end
end
local self = Host.FindRoot() .. "/tools/sim/drillpreview.luau"
local nextJob, running, failed = 1, 0, 0
local function worker()
	while nextJob <= #jobs do
		local job = jobs[nextJob]
		nextJob += 1
		local r = process.exec("lune", { "run", self, "--child", job[1], job[2], "--out", outDir })
		local outp = (r.stdout or "") .. (r.stderr or "")
		local wrote = outp:match("WROTE ([^\n]+)")
		if wrote then
			print(wrote)
		else
			failed += 1
			print(string.format("FAILED %s@%s: %s", job[1], job[2], outp:sub(-500)))
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
print(string.format("drillpreview: %d screens, %d failed", #jobs - failed, failed))
process.exit(failed == 0 and 0 or 1)
