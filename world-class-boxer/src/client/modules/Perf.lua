-- Perf: the one performance level every client system reads (optimization pass).
--   Perf.Level()                  1 (Low), 2 (Medium) or 3 (High): the level in force right now
--   Perf.Pick(low, medium, high)  the value for the current level
--   Perf.AtLeast(n)               Perf.Level() >= n
--   Perf.Changed                  RBXScriptSignal fired with the new level when it changes
--   Perf.Fps()                    the measured frame rate (2 s window, hitches left out): the Settings readout
--   Perf.Auto()                   true while Graphics is on Auto (the frame rate decides)
--   Perf.Capped()                 true while Auto reads the frames as held back by a frame-rate cap (a 30 FPS
--                                 limit, a phone's battery saver) rather than by load: it keeps the level
--   Perf.Name(level?)             "Low" | "Medium" | "High" (the current level by default)
--   Perf.Hold(seconds)            Auto passes no judgement for that long (a loading screen, a big build)
--   Perf.Refresh()                re-read the Graphics choice now (Settings calls it: attribute signals
--                                 may run deferred)
-- The player chooses Graphics in Settings (client attribute GfxDetail: Auto | High | Medium | Low).
-- Auto starts from the device and then follows the measured frame rate: it steps down while frames
-- stay slow (sooner when they are very slow) and back up when there is plenty of headroom, with
-- hysteresis, a settle time after each step and a cool-down that grows when a climb fails, so it never
-- flickers between levels; a level whose climbs keep failing is not tried again until the scene changes.
-- Frames longer than a quarter second (loading, a big build, the app in the background) are hitches, not
-- a frame rate: they are left out, and a window made mostly of them (or one while the window is unfocused
-- or held) is not judged, unless window after window is made of nothing else (a device crawling under
-- 4 FPS). Slow frames are judged by what they cost, not by their rate alone: when the frame's work (the
-- scripts' span from PreRender to the end of Heartbeat, the render thread's CPU and GPU time) would fit a
-- 50 FPS frame and the frames come evenly paced, a frame-rate cap is holding them back and the level
-- stays (without the render times, the scripts' span alone keeps Auto at Medium or above). The resolved
-- level is also published as the client-local player attribute GfxLevel, so scripts that load before this
-- module (or cannot require it) read the same number.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local Perf = {}
Perf.LOW, Perf.MEDIUM, Perf.HIGH = 1, 2, 3

local player = Players.LocalPlayer
local NAMES = { Low = 1, Medium = 2, High = 3 }
local LEVEL_NAMES = { "Low", "Medium", "High" }
local WINDOW = 2 -- seconds per frame-rate sample
local HITCH = 0.25 -- a frame longer than this is a hitch, not a frame rate
local SLOW_FPS, SLOW_WINDOWS = 40, 3 -- 6 s under 40 fps: one step down
local VERY_SLOW_FPS, VERY_SLOW_WINDOWS = 25, 2 -- 4 s under 25 fps (a struggling phone): one step down sooner
local CRAWL_FPS = 15 -- one window under 15 fps: one step down at once
local FAST_FPS, FAST_WINDOWS = 57, 10 -- 20 s at a steady 57+: one step up
local SETTLE = 6 -- after a step, the systems get this long to shed (or take on) work before the next judgement
local UP_COOLDOWN, UP_COOLDOWN_MAX = 60, 480 -- no climb this long after a step down; doubles per failed climb
local FAILED_CLIMB = 90 -- a step down this soon after a climb means the climb failed
local FAILED_CLIMBS = 2 -- climbs to a level that failed this often: no more tries until the scene changes
local SCENE_JUMP = 1000 -- the camera moving this far between windows is a new scene (gym, arena, city, menu)
local START_HOLD = 3 -- after the game has loaded: the join's snapshot and script start-up are not a frame rate
local CRAWL_WINDOWS = 3 -- this many windows in a row of nothing but hitches (6+ s, under 4 FPS): one step down
local CAP_BUSY = 1 / 50 -- slow frames whose work fits in 20 ms are held back by a cap (a 30 FPS limit), not load
local CAP_STEADY = 0.25 -- ... and come evenly paced, as a cap paces them (spread of the frame times / their mean)
local CAP_FRAMES = 10 -- the fewest frame costs in a window to judge a cap by

local level = 3
local fps = 60
local changed = Instance.new("BindableEvent")
Perf.Changed = changed.Event

local auto = true
local ceiling = 3 -- Auto never climbs above where the device started (unless that was High)
local slow, verySlow, fast, crawl = 0, 0, 0, 0
local lastDown, lastUp = -math.huge, -math.huge
local upCooldown = UP_COOLDOWN
local failedClimbs = {} -- [level] = climbs to it that had to be undone (since the scene last changed)
local holdUntil = math.huge -- set once the game has loaded (the end of this file)
local focused = true
local capped = false -- the last judged window: slow frames held back by a cap, with time to spare

local function publish(l, now)
	l = math.clamp(math.floor(l), 1, 3)
	if player then
		player:SetAttribute("GfxLevel", l)
	end
	if l ~= level then
		level = l
		-- every system reacts to the change: judge the result only once it has settled
		holdUntil = math.max(holdUntil, (now or os.clock()) + SETTLE)
		slow, verySlow, fast, crawl = 0, 0, 0, 0
		changed:Fire(l)
	end
end

function Perf.Level()
	return level
end

function Perf.Pick(low, medium, high)
	if level <= 1 then
		return low
	elseif level == 2 then
		return medium
	end
	return high
end

function Perf.AtLeast(n)
	return level >= n
end

function Perf.Fps()
	return fps
end

function Perf.Auto()
	return auto
end

function Perf.Capped()
	return auto and capped
end

function Perf.Name(l)
	return LEVEL_NAMES[l or level] or "High"
end

function Perf.Hold(seconds)
	holdUntil = math.max(holdUntil, os.clock() + (tonumber(seconds) or 0))
	slow, verySlow, fast, crawl = 0, 0, 0, 0
end

-- where Auto starts: phones and small tablets begin at Medium, everything else at High; the frame
-- rate decides from there
local function deviceStart()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return 2, math.min(vp.X, vp.Y) < 500 and 2 or 3
	end
	return 3, 3
end

local function chosen()
	local d = player and player:GetAttribute("GfxDetail")
	return NAMES[d], d
end

function Perf.Refresh()
	local fixed = chosen()
	if fixed then
		auto = false
		publish(fixed)
		return
	end
	local start, cap = deviceStart()
	ceiling = cap
	if not auto then
		-- back to Auto: restart from the device's level with a clean slate
		auto = true
		upCooldown = UP_COOLDOWN
		lastDown, lastUp = -math.huge, -math.huge
		table.clear(failedClimbs)
		publish(start)
		return
	end
	-- already on Auto (every settings change re-applies Graphics): keep the level Auto has reached, inside
	-- the device's ceiling; clamping to the start knocked a tablet that had climbed to High back to Medium
	publish(math.min(level, ceiling))
end

local function stepDown(now)
	if now - lastUp < FAILED_CLIMB then
		-- the last climb did not hold: wait longer before the next one (no ping-pong), and after
		-- FAILED_CLIMBS of them leave that level alone until the scene changes
		upCooldown = math.min(upCooldown * 2, UP_COOLDOWN_MAX)
		failedClimbs[level] = (failedClimbs[level] or 0) + 1
	end
	lastDown = now
	publish(level - 1, now)
end

-- floor: the lowest level a slow window may step down to (the level itself when a cap holds the frames
-- back; Medium when the frames look capped but the render times are not there to prove it)
local function judge(now, smooth, floor)
	if fps < SLOW_FPS and level > floor then
		slow += 1
		verySlow = fps < VERY_SLOW_FPS and verySlow + 1 or 0
		fast = 0
		if slow >= SLOW_WINDOWS or verySlow >= VERY_SLOW_WINDOWS or fps < CRAWL_FPS then
			stepDown(now)
		end
	elseif fps >= FAST_FPS and smooth then
		-- headroom means smooth frames: a window with a hitch in it never counts toward a climb
		fast += 1
		slow, verySlow = 0, 0
		if fast >= FAST_WINDOWS and level < ceiling and now - lastDown > upCooldown and (failedClimbs[level + 1] or 0) < FAILED_CLIMBS then
			lastUp = now
			publish(level + 1, now)
		end
	else
		-- in between, or slow frames with nothing to step down from (a cap holds them back, or Low already)
		slow, verySlow, fast = 0, 0, 0
	end
end

-- What a frame costs, so a frame-rate cap is not read as a slow device. The scripts' span runs from
-- PreRender to the end of Heartbeat: a deferred resume runs after every Heartbeat handler (one thread,
-- resumed each frame: nothing allocated). The render thread's CPU and GPU times come from Stats (seconds;
-- a value over 1 can only be milliseconds). Sampled only while Auto is on.
local function readStat(name)
	local v = tonumber(Stats[name]) or 0
	return v > 1 and v / 1000 or v
end
local frameStart -- os.clock() at this frame's PreRender
local renderTime, rendered = 0, false -- this frame's render CPU / GPU time (the larger); both readable and > 0
local busySum, busyN, renderN = 0, 0, 0
local spanEnd = coroutine.create(function()
	while true do
		if frameStart then
			busySum += math.max(os.clock() - frameStart, renderTime)
			busyN += 1
			if rendered then
				renderN += 1
			end
			frameStart = nil
		end
		coroutine.yield()
	end
end)
RunService.PreRender:Connect(function()
	if auto then
		frameStart = os.clock()
	end
end)

local frames, elapsed, sq, hitched, hitches = 0, 0, 0, 0, 0
local stalls = 0 -- windows in a row made mostly of hitches (the readout counts every frame after two)
local sceneAt -- the camera's position at the last window (a jump is a new scene)
RunService.Heartbeat:Connect(function(dt)
	if dt > HITCH then
		hitched += dt
		hitches += 1
	else
		frames += 1
		elapsed += dt
		sq += dt * dt
	end
	if frameStart then
		local okC, cpu = pcall(readStat, "RenderCPUFrameTime")
		local okG, gpu = pcall(readStat, "RenderGPUFrameTime")
		rendered = okC and okG and cpu > 0 and gpu > 0
		renderTime = rendered and math.max(cpu, gpu) or 0
		task.defer(spanEnd)
	end
	if elapsed + hitched < WINDOW then
		return
	end
	local stalled, smooth = hitched > elapsed, hitched == 0
	stalls = stalled and stalls + 1 or 0
	if stalls >= 2 then
		-- a run of slow frames is the frame rate itself (a crawl): the readout counts every frame
		fps = (frames + hitches) / (elapsed + hitched)
	elseif frames > 0 and elapsed > 0 then
		fps = frames / elapsed
	end
	-- a cap: slow frames, evenly paced, whose work would fit a 50 FPS frame. With the render times it is
	-- proven (the level stays); with the scripts' span alone a GPU-bound device could look the same, so
	-- Auto only keeps from going below Medium
	local floor = 1
	capped = false
	if smooth and fps < SLOW_FPS and busyN >= CAP_FRAMES and frames >= CAP_FRAMES then
		local mean = elapsed / frames
		local spread = math.sqrt(math.max(sq / frames - mean * mean, 0))
		if spread <= CAP_STEADY * mean and busySum / busyN <= CAP_BUSY then
			capped = renderN >= busyN / 2
			floor = capped and level or 2
		end
	end
	frames, elapsed, sq, hitched, hitches = 0, 0, 0, 0, 0
	busySum, busyN, renderN = 0, 0, 0
	local cam = workspace.CurrentCamera
	local at = cam and cam.CFrame.Position
	if at and sceneAt and (at - sceneAt).Magnitude > SCENE_JUMP then
		-- a new scene (gym, arena, city, menu) has its own load: the climbs that failed elsewhere may hold here
		table.clear(failedClimbs)
		upCooldown = UP_COOLDOWN
	end
	sceneAt = at
	local now = os.clock()
	if not auto or not focused or now < holdUntil then
		crawl = 0
		return
	end
	if stalled then
		-- one stall is loading or a big build, not a frame rate; window after window of nothing else is
		-- a device crawling under 4 FPS
		crawl += 1
		if crawl >= CRAWL_WINDOWS and level > 1 then
			stepDown(now)
		end
		return
	end
	crawl = 0
	judge(now, smooth, floor)
end)

UserInputService.WindowFocusReleased:Connect(function()
	focused = false
end)
UserInputService.WindowFocused:Connect(function()
	focused = true
	Perf.Hold(WINDOW) -- the first window back may still hold the pause
end)

if game:IsLoaded() then
	holdUntil = os.clock() + START_HOLD
else
	task.spawn(function()
		game.Loaded:Wait()
		holdUntil = os.clock() + START_HOLD
	end)
end

if player then
	player:GetAttributeChangedSignal("GfxDetail"):Connect(Perf.Refresh)
	level = select(1, deviceStart())
	Perf.Refresh()
	player:SetAttribute("GfxLevel", level)
end

return Perf
