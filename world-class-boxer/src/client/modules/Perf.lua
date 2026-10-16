-- Perf: the one performance level every client system reads (optimization pass).
--   Perf.Level()                  1 (Low), 2 (Medium) or 3 (High): the level in force right now
--   Perf.Pick(low, medium, high)  the value for the current level
--   Perf.AtLeast(n)               Perf.Level() >= n
--   Perf.Changed                  RBXScriptSignal fired with the new level when it changes
--   Perf.Fps()                    the measured frame rate (2 s window)
-- The player chooses Graphics in Settings (client attribute GfxDetail: Auto | High | Medium | Low).
-- Auto starts from the device and then follows the measured frame rate: it steps down while frames
-- stay slow and back up when there is plenty of headroom, with hysteresis and a cool-down so it never
-- flickers between levels. The resolved level is also published as the client-local player attribute
-- GfxLevel, so scripts that load before this module (or cannot require it) read the same number.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Perf = {}
Perf.LOW, Perf.MEDIUM, Perf.HIGH = 1, 2, 3

local player = Players.LocalPlayer
local NAMES = { Low = 1, Medium = 2, High = 3 }
local WINDOW = 2 -- seconds per frame-rate sample
local SLOW_FPS, SLOW_WINDOWS = 40, 3 -- 6 s under 40 fps: one step down
local FAST_FPS, FAST_WINDOWS = 57, 10 -- 20 s at a steady 57+: one step up
local UP_COOLDOWN = 60 -- after a step down, no step up for a minute (no ping-pong)

local level = 3
local fps = 60
local changed = Instance.new("BindableEvent")
Perf.Changed = changed.Event

local function publish(l)
	l = math.clamp(math.floor(l), 1, 3)
	if player then
		player:SetAttribute("GfxLevel", l)
	end
	if l ~= level then
		level = l
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

local auto = true
local ceiling = 3 -- Auto never climbs above where the device started (unless that was High)
local slow, fast, lastDown = 0, 0, -math.huge

local function chosen()
	local d = player and player:GetAttribute("GfxDetail")
	return NAMES[d], d
end

local function refresh()
	local fixed = chosen()
	if fixed then
		auto = false
		publish(fixed)
		return
	end
	if not auto then
		-- back to Auto: restart from the device's level
		auto = true
		slow, fast = 0, 0
	end
	local start, cap = deviceStart()
	ceiling = cap
	publish(math.min(level, start))
end

local frames, elapsed = 0, 0
RunService.Heartbeat:Connect(function(dt)
	frames += 1
	elapsed += dt
	if elapsed < WINDOW then
		return
	end
	fps = frames / elapsed
	frames, elapsed = 0, 0
	if not auto then
		return
	end
	if fps < SLOW_FPS then
		slow += 1
		fast = 0
		if slow >= SLOW_WINDOWS and level > 1 then
			slow = 0
			lastDown = os.clock()
			publish(level - 1)
		end
	elseif fps >= FAST_FPS then
		fast += 1
		slow = 0
		if fast >= FAST_WINDOWS and level < ceiling and os.clock() - lastDown > UP_COOLDOWN then
			fast = 0
			publish(level + 1)
		end
	else
		slow, fast = 0, 0
	end
end)

if player then
	player:GetAttributeChangedSignal("GfxDetail"):Connect(refresh)
	level = select(1, deviceStart())
	refresh()
	player:SetAttribute("GfxLevel", level)
end

return Perf
