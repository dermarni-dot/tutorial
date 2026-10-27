--!nocheck
-- tools/sim/loadframes.luau: how smooth the client's start-up is (the join, the world coming up, the menu opening),
-- measured on the REAL client scripts (ClientMain, FightClient, Animator and every module they start) on guisim.
-- A frame cannot be drawn while Lua runs, so every frame's Lua is what the loading screen / the menu's first seconds
-- wait for: the longest frames and the longest single slices (one thread from its resume to its next yield, or one
-- RenderStepped / Heartbeat handler) are printed, with what ran in them.
--   * the server's gym and city first (MapBuilder.BuildGym: what the join replicates before the scripts run)
--   * the three LocalScripts each in a thread of their own (as the engine starts them), then FRAMES frames at 60 Hz:
--     RenderStepped, the task.wait / task.delay threads that are due (they resume on a frame, as on a Heartbeat),
--     Heartbeat; every script compiled up front (H.bytecode: the sim's compile is not a frame's)
--   * GetProfile answers after --lat seconds: a returning boxer (menuAtStart: the title screen with his boxer on the
--     menu stage) or, with --new 1, a first join (the title screen, no career)
--   lune run tools/sim/loadframes.luau [--seconds 6] [--new 1] [--lat 0.3] [--top 8] [--debug 1] [--src DIR] [--world 0]
--   before / after a change: a copy of src without it, run with --src DIR (the last line, SUMMARY, is for tables)
-- Simulated: the engine (fakeengine / guisim instances are Lua tables, slower to make than the engine's, and guisim
-- lays the whole GUI out on an AbsoluteSize read), no rendering, no replication; the Lua times compare one version
-- of the client with another, not with a device; the instance counts are exact.
local process = require("@lune/process")
local ltask = require("@lune/task")
local GS = require("./guisim")
local DrillSim = require("./drillsim")

local args = {}
do
	local a = process.args
	for i = 1, #a, 2 do
		args[(a[i]:gsub("^%-%-", ""))] = a[i + 1]
	end
end
local SECONDS = tonumber(args.seconds) or 6
local NEW = args.new == "1"
local TOP = tonumber(args.top) or 8
local LAT = tonumber(args.lat) or 0.3 -- seconds GetProfile takes (the round trip and the server's DataStore read)

local S = GS.new("desktop", { src = args.src })
local Hh = S.host
local E = S.E
DrillSim.SeedRandom(Hh)

------------------------------------------------------------------------
-- slices: exclusive Lua time per label, per frame
------------------------------------------------------------------------
local frame = 0 -- 0 = before the first frame (the scripts' start, until each first yields)
local frameMs = {} -- [frame] = ms of Lua
local frameBy = {} -- [frame] = { [label] = ms }
local frameNew = {} -- [frame] = Instance.new calls
local newBy = {} -- [label] = Instance.new calls (the whole run)
local frameNewBy = {} -- [frame] = { [label] = Instance.new calls }
local slices = {} -- { ms, label, frame }
local stack = {} -- { label, t0, excl } running slices (a spawn runs its child inside its parent's slice)

local function now()
	return os.clock()
end
local function record(e, ms)
	frameMs[frame] = (frameMs[frame] or 0) + ms
	local by = frameBy[frame] or {}
	frameBy[frame] = by
	by[e.label] = (by[e.label] or 0) + ms
	slices[#slices + 1] = { ms, e.label, frame }
end
local function push(label)
	local top = stack[#stack]
	local t = now()
	if top then
		top.excl += t - top.t0
	end
	local e = { label = label, t0 = t, excl = 0 }
	stack[#stack + 1] = e
	return e
end
-- e's slice ends. Entries above it on the stack are threads that
-- yielded where the sim cannot see (a fake signal's Wait): their slice ended at their last pause
local function pop(e)
	local t = now()
	local i = table.find(stack, e)
	if not i then
		return
	end
	while #stack > i do
		local x = table.remove(stack)
		record(x, x.excl * 1000)
	end
	table.remove(stack)
	local ms = (e.excl + (t - e.t0)) * 1000
	record(e, ms)
	local top = stack[#stack]
	if top then
		top.t0 = t
	end
end
-- a frame starts: nothing but the harness runs, every entry left is a thread suspended unseen
local function flush()
	while #stack > 0 do
		local x = table.remove(stack)
		record(x, x.excl * 1000)
	end
end

local function labelOf(f, kind)
	if type(f) ~= "function" then
		return kind
	end
	local src, line = debug.info(f, "sl")
	src = tostring(src):gsub("^.*/", "")
	return string.format("%s %s:%d", kind, src, line or 0)
end

-- each thread's label while it runs (wait / defer yields end its slice, the resume starts the next)
local threadLabel = setmetatable({}, { __mode = "k" })
local threadEntry = setmetatable({}, { __mode = "k" }) -- the thread's current slice after a resume
local function wrapAs(f, label)
	return function(...)
		threadLabel[coroutine.running()] = label
		threadEntry[coroutine.running()] = push(label)
		local ok, err = pcall(f, ...)
		pop(threadEntry[coroutine.running()])
		threadEntry[coroutine.running()] = nil
		if not ok then
			warn("[loadframes] " .. label .. ": " .. tostring(err))
		end
	end
end
local function wrap(f, kind)
	if type(f) ~= "function" then
		return f -- (a thread: resumed as is)
	end
	return wrapAs(f, labelOf(f, kind))
end
local T = Hh.globals.task
local base = { spawn = T.spawn, defer = T.defer, delay = T.delay, wait = T.wait }
local taskLib = table.clone(T)
taskLib.spawn = function(f, ...)
	return base.spawn(wrap(f, "spawn"), ...)
end
taskLib.defer = function(f, ...)
	return base.defer(wrap(f, "defer"), ...)
end
-- task.wait / task.delay resume on a frame of the harness, as the engine resumes them on a Heartbeat (lune's own
-- would resume a task.wait() at once, many "frames" inside one of ours)
local waiting = {} -- { thread | fn, at, t0, args }
local function resumeDue()
	local t = now()
	local due = {}
	for i = #waiting, 1, -1 do
		local w = waiting[i]
		if t >= w.at then
			table.remove(waiting, i)
			table.insert(due, 1, w)
		end
	end
	for _, w in ipairs(due) do
		if type(w.th) == "thread" then
			base.spawn(w.th, t - w.t0)
		else
			base.spawn(w.th, table.unpack(w.args, 1, w.args.n))
		end
	end
end
taskLib.delay = function(t, f, ...)
	table.insert(waiting, { th = wrap(f, "delay"), at = now() + (tonumber(t) or 0), t0 = now(), args = table.pack(...) })
end
taskLib.wait = function(t)
	local th = coroutine.running()
	local label = threadLabel[th]
	local e = label and threadEntry[th]
	if e then
		pop(e)
	end
	table.insert(waiting, { th = th, at = now() + (tonumber(t) or 0), t0 = now() })
	local dt = coroutine.yield()
	if label then
		threadEntry[th] = push(label)
	end
	return dt
end
Hh.globals.task = taskLib
Hh.globals.wait = taskLib.wait
Hh.globals.spawn = taskLib.spawn
Hh.globals.delay = taskLib.delay

-- every script compiled up front (the engine compiles before a script runs; the sim's compile would be a frame's)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Host = require("./host")
local bytecode = {} -- [file] = bytecode
do
	local function walk(dir)
		for _, f in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. f
			if fs.isDir(path) then
				walk(path)
			elseif f:match("%.luau?$") then
				bytecode[path] = luau.compile(fs.readFile(path), { optimizationLevel = 1, debugLevel = 1 })
			end
		end
	end
	walk(Hh.src)
	Hh.bytecode = function(file)
		return bytecode[file]
	end
end
-- a LocalScript run as guisim's S.loadScript runs it, from its bytecode
local function loadScript(rel)
	local file = Hh.src .. "/" .. rel
	local name = rel:match("([^/]+)%.client%.luau?$") or rel:match("([^/]+)%.luau?$")
	local node = Host.NewNode(name, "LocalScript", Hh.client and rawget(Hh.client, "Parent"))
	rawset(node, "_file", file)
	local env = table.clone(Hh.globals)
	env.script = node
	luau.load(bytecode[file] or fs.readFile(file), { debugName = rel, environment = env, codegenEnabled = true })()
end

-- module requires (a first require: the module's top-level run)
do
	local req0 = Hh.globals.require
	Hh.globals.require = function(target)
		local file = type(target) == "table" and Hh.cache[target] == nil and rawget(target, "_file")
		if file then
			local e = push("require " .. tostring(rawget(target, "Name")))
			local ok, r = pcall(req0, target)
			pop(e)
			if not ok then
				error(r, 0)
			end
			return r
		end
		return req0(target)
	end
end

-- instances made per frame (the engine's cost of a build: what a real frame pays besides the Lua)
do
	local new0 = S.Instance.new
	S.Instance.new = function(...)
		frameNew[frame] = (frameNew[frame] or 0) + 1
		local top = stack[#stack]
		local l = top and top.label or "(harness)"
		newBy[l] = (newBy[l] or 0) + 1
		local fb = frameNewBy[frame] or {}
		frameNewBy[frame] = fb
		fb[l] = (fb[l] or 0) + 1
		local o = new0(...)
		-- a BindableEvent's handlers (State.Changed: every system's profile listener) are slices of their own
		if (...) == "BindableEvent" then
			local ev = o.Event
			local connect = ev.Connect
			ev.Connect = function(self, fn)
				local label = labelOf(fn, "Event")
				return connect(self, function(...)
					local e = push(label)
					local ok, err = pcall(fn, ...)
					pop(e)
					if not ok then
						warn("[loadframes] " .. label .. ": " .. tostring(err))
					end
				end)
			end
		end
		return o
	end
end

-- the frame signals' handlers, each a slice
for _, name in ipairs({ "RenderStepped", "Heartbeat", "Stepped", "PreSimulation", "PostSimulation", "PreRender", "PreAnimation" }) do
	local sig = E[name]
	if sig and sig.Connect then
		local connect = sig.Connect
		sig.Connect = function(self, fn)
			local label = labelOf(fn, name)
			return connect(self, function(...)
				local e = push(label)
				local ok, err = pcall(fn, ...)
				pop(e)
				if not ok then
					warn("[loadframes] " .. label .. ": " .. tostring(err))
				end
			end)
		end
	end
end

------------------------------------------------------------------------
-- the profile
------------------------------------------------------------------------
local P
if NEW then
	P = { created = false }
else
	local Career = DrillSim.ServerModule(Hh, "Career")
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, { first = "Marcus", last = "Reed", name = "Marcus Reed", nickname = "The Hammer", age = 24,
		nationality = "USA", weightClass = 5, style = "boxer", look = Looks.Defaults(1) }, 1)
	P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = true }
end
S.onInvokeServer = function(_, action)
	if action == "GetProfile" then
		if LAT > 0 then
			taskLib.wait(LAT)
		end
		return P
	end
	return { ok = false }
end

------------------------------------------------------------------------
-- the run
------------------------------------------------------------------------
-- the world the join replicates before the client's scripts run (StreamingEnabled is off): the server's gym and
-- city (MapBuilder.BuildGym), so the client's dressing (GymVisuals, CityVisuals, WorldDetail) has its anchors
if args.world ~= "0" then
	local a = now()
	local ok, err = pcall(function()
		DrillSim.ServerModule(Hh, "MapBuilder").BuildGym()
	end)
	print(string.format("[loadframes] the server's world: %s (%.0f ms, not counted)", ok and "built" or ("failed: " .. tostring(err)), (now() - a) * 1000))
	table.clear(frameMs)
	table.clear(frameBy)
	table.clear(frameNew)
	table.clear(slices)
	table.clear(newBy)
	table.clear(frameNewBy)
end

local t0 = now()
-- each LocalScript in a thread of its own (as the engine starts them: one after another, each until it yields)
local scriptsDone = {}
for _, rel in ipairs({ "client/ClientMain.client.lua", "client/FightClient.client.lua", "client/Animator.client.lua" }) do
	base.spawn(wrapAs(function()
		loadScript(rel)
		scriptsDone[rel] = frame
	end, "top-level " .. rel:gsub("^client/", "")))
end
local FRAMES = math.floor(SECONDS * 60)
local intervals = {}
local MenuMain = Hh.require("Client/MainMenu")
local menuAt, menuFrame
for i = 1, FRAMES do
	flush()
	frame = i
	local a = now()
	E.RenderStepped:Fire(1 / 60)
	resumeDue()
	E.Heartbeat:Fire(1 / 60)
	ltask.wait(1 / 60)
	intervals[i] = (now() - a) * 1000
	if not menuAt and MenuMain.IsOpen() then
		menuAt, menuFrame = (now() - t0) * 1000, i
	end
end
local total = (now() - t0) * 1000

------------------------------------------------------------------------
-- report
------------------------------------------------------------------------
-- (the two signal wrappers count only their own bookkeeping: the handlers are slices of their own)
local function frameList()
	local out = {}
	for f = 0, FRAMES do
		out[#out + 1] = { f, frameMs[f] or 0 }
	end
	table.sort(out, function(a, b)
		return a[2] > b[2]
	end)
	return out
end
local function topOf(by, n)
	local list = {}
	for k, v in pairs(by or {}) do
		list[#list + 1] = { k, v }
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	local parts = {}
	for i = 1, math.min(n, #list) do
		parts[#parts + 1] = string.format("%s %.1f", list[i][1], list[i][2])
	end
	return table.concat(parts, "; ")
end
local frames = frameList()
local over8, over16, over33 = 0, 0, 0
for f = 1, FRAMES do
	local ms = frameMs[f] or 0
	over8 += ms > 8 and 1 or 0
	over16 += ms > 16.7 and 1 or 0
	over33 += ms > 33.3 and 1 or 0
end
local maxRun = 0
for f = 1, FRAMES do
	maxRun = math.max(maxRun, frameMs[f] or 0)
end
print(string.format("loadframes (%s): %d frames, total Lua %.0f ms (wall %.0f ms)", NEW and "first join" or "returning boxer", FRAMES,
	(function()
		local s = 0
		for f = 0, FRAMES do
			s += frameMs[f] or 0
		end
		return s
	end)(), total))
print(string.format("  the scripts' start (before the first frame): %.1f ms; their top-level runs ended in frames %s", frameMs[0] or 0,
	(function()
		local o = {}
		for rel, f in pairs(scriptsDone) do
			o[#o + 1] = rel:gsub("^client/", ""):gsub("%.client%.lua$", "") .. " " .. f
		end
		table.sort(o)
		return table.concat(o, ", ")
	end)()))
print(string.format("  longest frame after it: %.1f ms; frames over 8 / 16.7 / 33.3 ms: %d / %d / %d", maxRun, over8, over16, over33))
local maxNew, maxNewF = 0, 0
for f = 1, FRAMES do
	if (frameNew[f] or 0) > maxNew then
		maxNew, maxNewF = frameNew[f], f
	end
end
print(string.format("  instances made: %d in the top-level run, at most %d in one frame after it (frame %d)", frameNew[0] or 0, maxNew, maxNewF))
local wall = table.clone(intervals)
table.sort(wall, function(a, b)
	return a > b
end)
local wall50 = 0
for _, ms in ipairs(intervals) do
	wall50 += ms > 50 and 1 or 0
end
print(string.format("  frame wall time (the harness's 60 Hz loop, Lua and the sim's scheduler): longest %.0f / %.0f / %.0f ms, %d frames over 50 ms",
	wall[1] or 0, wall[2] or 0, wall[3] or 0, wall50))
print("  longest frames:")
for i = 1, math.min(TOP, #frames) do
	local f, ms = frames[i][1], frames[i][2]
	print(string.format("    frame %4d  %7.1f ms  %5d new  %s", f, ms, frameNew[f] or 0, topOf(frameBy[f], 4)))
	if args.debug and (frameNew[f] or 0) > 100 then
		print("                 instances: " .. topOf(frameNewBy[f], 4):gsub("(%d)%.0", "%1"))
	end
end
table.sort(slices, function(a, b)
	return a[1] > b[1]
end)
print("  longest slices:")
for i = 1, math.min(TOP, #slices) do
	print(string.format("    %7.1f ms  frame %4d  %s", slices[i][1], slices[i][3], slices[i][2]))
end
if args.debug then
	print("  frame 0 by: " .. topOf(frameBy[0], 40))
	print("  instances made by: " .. (function()
		local l = {}
		for k, v in pairs(newBy) do
			l[#l + 1] = { k, v }
		end
		table.sort(l, function(a, b)
			return a[2] > b[2]
		end)
		local o = {}
		for i = 1, math.min(15, #l) do
			o[i] = l[i][1] .. " " .. l[i][2]
		end
		return table.concat(o, "; ")
	end)())
end
print(string.format("  the title screen open after %s ms (frame %s; GetProfile answers after %.0f ms)", menuAt and string.format("%.0f", menuAt) or "-",
	tostring(menuFrame or "-"), LAT * 1000))
-- one line for before / after tables
local maxAll = 0
for f = 0, FRAMES do
	maxAll = math.max(maxAll, frameNew[f] or 0)
end
print(string.format("SUMMARY longest_frame_ms=%.1f frames_over_16ms=%d frames_over_33ms=%d longest_slice_ms=%.1f max_instances_in_a_frame=%d menu_open_ms=%s",
	math.max(maxRun, frameMs[0] or 0), over16 + ((frameMs[0] or 0) > 16.7 and 1 or 0), over33 + ((frameMs[0] or 0) > 33.3 and 1 or 0), slices[1] and slices[1][1] or 0, maxAll,
	menuAt and string.format("%.0f", menuAt) or "-"))
process.exit(0)
