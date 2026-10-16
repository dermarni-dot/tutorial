-- Perf: the one performance level every client system reads (optimization pass).
--   Perf.Level()                  1 (Low), 2 (Medium) or 3 (High): the level in force right now
--   Perf.Pick(low, medium, high)  the value for the current level
--   Perf.AtLeast(n)               Perf.Level() >= n
--   Perf.Changed                  RBXScriptSignal fired with the new level when it changes
--   Perf.Fps()                    the measured frame rate (2 s window, hitches left out): the Settings readout
--   Perf.Auto()                   true while Graphics is on Auto (the frame rate decides)
--   Perf.Name(level?)             "Low" | "Medium" | "High" (the current level by default)
--   Perf.Hold(seconds)            Auto passes no judgement for that long (a loading screen, a big build)
--   Perf.Refresh()                re-read the Graphics choice now (Settings calls it: attribute signals
--                                 may run deferred)
-- The player chooses Graphics in Settings (client attribute GfxDetail: Auto | High | Medium | Low).
-- Auto starts from the device and then follows the measured frame rate: it steps down while frames
-- stay slow (sooner when they are very slow) and back up when there is plenty of headroom, with
-- hysteresis, a settle time after each step and a cool-down that grows when a climb fails, so it never
-- flickers between levels. Frames longer than a quarter second (loading, a big build, the app in the
-- background) are hitches, not a frame rate: they are left out, and a window made mostly of them (or
-- one while the window is unfocused or held) is not judged. The resolved level is also published as the
-- client-local player attribute GfxLevel, so scripts that load before this module (or cannot require
-- it) read the same number.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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
local START_HOLD = 3 -- after the game has loaded: the join's snapshot and script start-up are not a frame rate

local level = 3
local fps = 60
local changed = Instance.new("BindableEvent")
Perf.Changed = changed.Event

local auto = true
local ceiling = 3 -- Auto never climbs above where the device started (unless that was High)
local slow, verySlow, fast = 0, 0, 0
local lastDown, lastUp = -math.huge, -math.huge
local upCooldown = UP_COOLDOWN
local holdUntil = math.huge -- set once the game has loaded (the end of this file)
local focused = true

local function publish(l, now)
	l = math.clamp(math.floor(l), 1, 3)
	if player then
		player:SetAttribute("GfxLevel", l)
	end
	if l ~= level then
		level = l
		-- every system reacts to the change: judge the result only once it has settled
		holdUntil = math.max(holdUntil, (now or os.clock()) + SETTLE)
		slow, verySlow, fast = 0, 0, 0
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

function Perf.Name(l)
	return LEVEL_NAMES[l or level] or "High"
end

function Perf.Hold(seconds)
	holdUntil = math.max(holdUntil, os.clock() + (tonumber(seconds) or 0))
	slow, verySlow, fast = 0, 0, 0
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
		publish(start)
		return
	end
	publish(math.min(level, start))
end

local function judge(now, smooth)
	if fps < SLOW_FPS then
		slow += 1
		verySlow = fps < VERY_SLOW_FPS and verySlow + 1 or 0
		fast = 0
		if level > 1 and (slow >= SLOW_WINDOWS or verySlow >= VERY_SLOW_WINDOWS or fps < CRAWL_FPS) then
			if now - lastUp < FAILED_CLIMB then
				-- the last climb did not hold: wait longer before the next one (no ping-pong)
				upCooldown = math.min(upCooldown * 2, UP_COOLDOWN_MAX)
			end
			lastDown = now
			publish(level - 1, now)
		end
	elseif fps >= FAST_FPS and smooth then
		-- headroom means smooth frames: a window with a hitch in it never counts toward a climb
		fast += 1
		slow, verySlow = 0, 0
		if fast >= FAST_WINDOWS and level < ceiling and now - lastDown > upCooldown then
			lastUp = now
			publish(level + 1, now)
		end
	else
		slow, verySlow, fast = 0, 0, 0
	end
end

local frames, elapsed, hitched = 0, 0, 0
RunService.Heartbeat:Connect(function(dt)
	if dt > HITCH then
		hitched += dt
	else
		frames += 1
		elapsed += dt
	end
	if elapsed + hitched < WINDOW then
		return
	end
	local mostlyHitches, smooth = hitched > elapsed, hitched == 0
	if frames > 0 and elapsed > 0 then
		fps = frames / elapsed
	end
	frames, elapsed, hitched = 0, 0, 0
	local now = os.clock()
	if not auto or mostlyHitches or not focused or now < holdUntil then
		return
	end
	judge(now, smooth)
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
