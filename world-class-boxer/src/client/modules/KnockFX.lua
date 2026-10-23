-- KnockFX: the local player's "lights going out" screen. FightClient calls it on its own knockdown /
-- knockout / getting rocked; everything here lives in its own instances (a ScreenGui, a BlurEffect and a
-- ColorCorrectionEffect on the camera, an EqualizerSoundEffect on SoundService.FightMix), never the
-- concussion effects or the camera's CFrame, so it stacks with whatever the fight camera does (a KO
-- slow-mo, a broadcast cut) and with the concussion blur / grade.
--
--   KnockFX.Hit("down" | "out" | "wobble")  -- the impact: a white flash, the picture blurs, drains and
--                                             -- washes out to white at the edges, the sound goes muffled
--   KnockFX.Progress(p)                     -- 0..1: the get-up meter filling (a knockdown clears with it)
--   KnockFX.Count(n)                        -- the referee's count (a knockdown also clears as it goes on)
--   KnockFX.Release(seconds)                -- fade out over seconds (stood up; a KO's walk to the result)
--   KnockFX.Clear()                         -- off now, every instance gone (round end, fight end, respawn)
--
-- It always cleans up: a respawn clears it, a wobble ends on its own, and a knockdown nobody released
-- clears itself after WATCHDOG seconds without a call (a lost message, an error upstream). One
-- RenderStepped connection, only while something shows.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local KnockFX = {}
KnockFX.WATCHDOG = 25

local player = Players.LocalPlayer
local S = {
	mode = "none", level = 0, goal = 0, rate = 3, flashA = 1, progress = 0, count = 0, clock = 0, touched = 0,
	gui = nil, haze = nil, flash = nil, edges = nil, blur = nil, grade = nil, eq = nil, conn = nil, vigKey = -1,
}
-- how heavy each kind is: the peak at the impact, then where it settles
-- (the impact flash itself is short and never a full white-out: the punch that landed stays readable)
local KIND = {
	wobble = { peak = 0.3, hold = 0, settle = 0, rate = 1.1 },
	down = { peak = 1, hold = 0.5, settle = 0.78, rate = 2.2 },
	out = { peak = 1, hold = 0.5, settle = 1, rate = 1.6 },
}

local function new(class, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	o.Parent = props.Parent
	return o
end

local function ensureGui()
	if S.gui and S.gui.Parent then
		return
	end
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	-- (DisplayOrder 4: over the fight's own screen FX, under the HUD, which stays sharp and readable)
	S.gui = new("ScreenGui", { Name = "KnockFX", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, Parent = pg })
	pcall(function()
		-- edge to edge, under the notch too (it is the picture going, not a panel)
		S.gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	-- a white haze over the whole picture (the washed-out, overexposed look)
	S.haze = new("Frame", { Name = "Haze", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(236, 238, 244), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1, Parent = S.gui })
	-- the soft white-grey vignette: four edge panels, opaque at the edge, clear toward the middle
	S.edges = {}
	for _, v in ipairs({
		{ UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0), 90 }, { UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0.58), 270 },
		{ UDim2.fromScale(0.34, 1), UDim2.fromScale(0, 0), 0 }, { UDim2.fromScale(0.34, 1), UDim2.fromScale(0.66, 0), 180 },
	}) do
		local fr = new("Frame", { Name = "Edge", Size = v[1], Position = v[2], BackgroundColor3 = Color3.fromRGB(214, 218, 228), BackgroundTransparency = 0, BorderSizePixel = 0,
			Visible = false, ZIndex = 2, Parent = S.gui })
		local g = new("UIGradient", { Rotation = v[3], Transparency = NumberSequence.new(1), Parent = fr })
		table.insert(S.edges, { frame = fr, grad = g })
	end
	-- the impact: a white flash
	S.flash = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = S.gui })
end

local function ensurePost()
	local cam = workspace.CurrentCamera
	if cam and not (S.blur and S.blur.Parent == cam) then
		S.blur = cam:FindFirstChild("KnockBlur") or new("BlurEffect", { Name = "KnockBlur", Size = 0, Parent = cam })
	end
	if cam and not (S.grade and S.grade.Parent == cam) then
		S.grade = cam:FindFirstChild("KnockGrade") or new("ColorCorrectionEffect", { Name = "KnockGrade", Saturation = 0, Brightness = 0, Contrast = 0, Parent = cam })
	end
	local mix = SoundService:FindFirstChild("FightMix")
	if mix and not (S.eq and S.eq.Parent == mix) then
		S.eq = mix:FindFirstChild("KnockEQ") or new("EqualizerSoundEffect", { Name = "KnockEQ", HighGain = 0, MidGain = 0, LowGain = 0, Priority = 5, Parent = mix })
	end
end

-- every instance gone, the connection dropped
function KnockFX.Clear()
	if S.conn then
		S.conn:Disconnect()
		S.conn = nil
	end
	for _, k in ipairs({ "blur", "grade", "eq", "gui" }) do
		local o = S[k]
		if o then
			pcall(o.Destroy, o)
		end
		S[k] = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		for _, n in ipairs({ "KnockBlur", "KnockGrade" }) do
			local e = cam:FindFirstChild(n)
			if e then
				e:Destroy()
			end
		end
	end
	S.haze, S.flash, S.edges = nil, nil, nil
	S.mode, S.level, S.goal, S.flashA, S.progress, S.count, S.vigKey = "none", 0, 0, 1, 0, 0, -1
end

-- one frame: the level eases to its goal, then every effect follows the level
local function step(dt)
	dt = math.clamp(dt, 0, 0.1)
	S.clock += dt
	local k = KIND[S.mode]
	if k then
		if S.mode == "down" then
			-- the picture comes back as the meter fills and the count goes on (a bit either way)
			local back = math.max(S.progress, math.clamp((S.count - 1) / 9, 0, 1) * 0.45)
			if S.clock > k.hold then
				S.goal = math.min(S.goal, k.settle * (1 - 0.82 * back))
			end
		elseif S.mode == "out" then
			if S.clock > k.hold and S.goal > 0 then
				S.goal = k.settle
			end
		elseif S.mode == "wobble" and S.clock > 0.35 then
			S.goal = 0
		end
		if S.clock - S.touched > KnockFX.WATCHDOG then
			S.goal, S.rate = 0, 2
		end
	end
	local rate = S.goal < S.level and S.rate or 6
	S.level += (S.goal - S.level) * (1 - math.exp(-rate * dt))
	S.flashA = math.min(1, S.flashA + dt * 4.5)
	if S.goal <= 0 and S.level < 0.01 and S.flashA >= 1 then
		KnockFX.Clear()
		return
	end
	ensurePost()
	local s = S.level
	-- a slow swim (the eyes not quite focusing): the blur breathes, the edges sway with it
	local swim = math.sin(S.clock * 2.3) * 0.5 + 0.5
	if S.blur then
		local size = (S.mode == "out" and 26 or 20) * s + 4 * s * swim
		S.blur.Enabled = size > 0.05
		S.blur.Size = size
	end
	if S.grade then
		S.grade.Enabled = s > 0.003
		S.grade.Saturation = -0.8 * s
		S.grade.Brightness = 0.16 * s
		S.grade.Contrast = -0.22 * s
		S.grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(226, 232, 255), s)
	end
	if S.eq then
		S.eq.HighGain, S.eq.MidGain, S.eq.LowGain = -34 * s, -14 * s, 2 * s
	end
	if S.gui then
		S.haze.BackgroundTransparency = 1 - 0.14 * s
		-- (the flash is a brief lift of the picture, not a sheet of white over the arm that landed)
		S.flash.BackgroundTransparency = 0.55 + 0.45 * S.flashA
		local v = math.floor((0.82 * s + 0.08 * s * swim) * 40 + 0.5) / 40
		if v ~= S.vigKey then
			S.vigKey = v
			for _, e in ipairs(S.edges) do
				e.frame.Visible = v > 0.01
				if v > 0.01 then
					e.grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - v), NumberSequenceKeypoint.new(0.55, 1 - v * 0.3), NumberSequenceKeypoint.new(1, 1) })
				end
			end
		end
	end
end

local function run()
	if S.conn then
		return
	end
	S.conn = RunService.RenderStepped:Connect(function(dt)
		local ok = pcall(step, dt)
		if not ok then
			-- never leave the screen blurred behind an error
			KnockFX.Clear()
		end
	end)
end

function KnockFX.Hit(kind)
	local k = KIND[kind]
	if not k then
		return
	end
	-- a wobble never cuts a knockdown short; a knockout always takes over
	if kind == "wobble" and (S.mode == "down" or S.mode == "out") then
		return
	end
	ensureGui()
	ensurePost()
	S.mode, S.clock, S.touched = kind, 0, 0
	S.goal, S.rate = k.peak, k.rate
	S.level = math.max(S.level, kind == "wobble" and 0.12 or 0.5)
	S.progress, S.count = 0, 0
	-- (flashA runs 0 -> 1 in about 0.2 s: a wobble barely flashes, a knockdown / knockout a short pop)
	S.flashA = kind == "wobble" and 0.75 or (kind == "out" and 0.15 or 0.3)
	run()
end

function KnockFX.Progress(p)
	if S.mode == "none" then
		return
	end
	S.progress = math.clamp(tonumber(p) or 0, 0, 1)
	S.touched = S.clock
end

function KnockFX.Count(n)
	if S.mode == "none" then
		return
	end
	S.count = tonumber(n) or 0
	S.touched = S.clock
end

function KnockFX.Release(seconds)
	if S.mode == "none" then
		return
	end
	S.mode = "release"
	S.goal = 0
	S.rate = 3 / math.max(0.1, tonumber(seconds) or 1)
	S.touched = S.clock
	run()
end

function KnockFX.Active()
	return S.mode ~= "none", S.mode, S.level
end

if player then
	player.CharacterAdded:Connect(KnockFX.Clear)
end

return KnockFX
