--[[
	SPEED VS BRAINROT  -  World effects (LocalScript)
	Put this in: StarterPlayer > StarterPlayerScripts

	Everything here only changes what YOU see, so it's smooth (it runs every frame on
	your screen instead of being sent from the server):
	  - moving obstacles (sliders, spinners, swinging logs, crushers), lasers, fire jets
	    and strikes follow the server clock, so they're exactly where the server checks them
	  - cash piles and eggs spin and bob
	  - zone gates glow green when your Speed is enough, red when it isn't
	  - running: a fast run animation that speeds up with you (capped so it never
	    looks frantic), a forward lean, a speed trail and a wider camera view
	  - getting hit: you tumble, stars spin around your head, the screen flashes red
	  - lighting changes a little on every map
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("SVB_Remotes")
local HitRemote = remotes:WaitForChild("Hit")

local TAU = math.pi * 2
local WHITE = Color3.new(1, 1, 1)

local function now()
	return workspace:GetServerTimeNow()
end

local function myRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------------
-- MOVING OBSTACLES (same math as the server's moverCF)
------------------------------------------------------------------------
local movers = {}

local function moverCF(m, t)
	local u = t / m.period + m.phase
	if m.kind == "slide" then
		return m.base * CFrame.new(math.sin(u * TAU) * m.amp, 0, 0)
	elseif m.kind == "spin" then
		return m.base * CFrame.Angles(0, u * TAU, 0)
	elseif m.kind == "swing" then
		return m.base * CFrame.Angles(0, 0, math.sin(u * TAU) * m.amp) * CFrame.new(0, -m.len, 0)
	elseif m.kind == "pound" then
		local f = u % 1
		local h
		if f < 0.55 then
			h = 1
		elseif f < 0.62 then
			h = 1 - (f - 0.55) / 0.07
		elseif f < 0.8 then
			h = 0
		else
			h = (f - 0.8) / 0.2
		end
		return m.base * CFrame.new(0, h * m.amp, 0)
	end
	return m.base
end

local function addMover(part)
	local base = part:GetAttribute("BaseCF")
	if typeof(base) ~= "CFrame" then return end
	movers[part] = {
		part = part,
		kind = part:GetAttribute("MoveKind"),
		base = base,
		amp = part:GetAttribute("Amp") or 0,
		period = part:GetAttribute("Period") or 3,
		phase = part:GetAttribute("Phase") or 0,
		len = part:GetAttribute("Len") or 0,
	}
end

-- lasers + fire jets that blink, and strikes (a circle flashes, then a bolt)
local blinkers, strikes = {}, {}

local function addBlinker(part)
	blinkers[part] = {
		on = part.Transparency,
		offset = part:GetAttribute("BlinkOffset") or 0,
		period = part:GetAttribute("BlinkPeriod") or 2,
		onTime = part:GetAttribute("BlinkOn") or 1,
	}
end

local function addStrike(part)
	strikes[part] = {
		role = part:GetAttribute("StrikeRole"),
		offset = part:GetAttribute("StrikeOffset") or 0,
		period = part:GetAttribute("StrikePeriod") or 4,
	}
end

local function watchTag(tag, add, list)
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do add(inst) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst) list[inst] = nil end)
end

------------------------------------------------------------------------
-- SPINNING CASH + EGGS
------------------------------------------------------------------------
local spinners = {} -- [model] = { base, phase, speed, bob }

local function addCash(model)
	local spin = model:WaitForChild("Spin", 5)
	if not spin or not spin.Parent then return end
	local base = spin:GetAttribute("BaseCF")
	if typeof(base) ~= "CFrame" then base = spin:GetPivot() end
	spinners[spin] = { base = base, phase = math.random() * TAU, speed = 1.6, bob = 0.35 }
end

local function addEgg(model)
	local base = model:GetAttribute("BaseCF")
	if typeof(base) ~= "CFrame" then base = model:GetPivot() end
	spinners[model] = { base = base, phase = math.random() * TAU, speed = 0.7, bob = 0.5 }
end

------------------------------------------------------------------------
-- ZONE GATES: green when you're fast enough, red when you're not
------------------------------------------------------------------------
local gates = {}
local GATE_OK = Color3.fromRGB(110, 255, 120)
local GATE_NO = Color3.fromRGB(255, 70, 70)

local function paintGate(part)
	local need = part:GetAttribute("Need") or 0
	local ok = (player:GetAttribute("Speed") or 0) >= need
	part.Color = ok and GATE_OK or GATE_NO
	part.Transparency = ok and 0.85 or 0.6
end

local function addGate(part)
	gates[part] = true
	paintGate(part)
end

player:GetAttributeChangedSignal("Speed"):Connect(function()
	for part in pairs(gates) do paintGate(part) end
end)

------------------------------------------------------------------------
-- every frame: move what's near you
------------------------------------------------------------------------
local NEAR = 320
local CASH_NEAR = 160

local function startWorld()
	watchTag("SVB_Mover", addMover, movers)
	watchTag("SVB_Blink", addBlinker, blinkers)
	watchTag("SVB_Strike", addStrike, strikes)
	watchTag("SVB_EggSpin", addEgg, spinners)
	watchTag("SVB_SpeedGate", addGate, gates)
	local cashFolder = workspace:WaitForChild("SVB_Cash")
	for _, m in ipairs(cashFolder:GetChildren()) do task.spawn(addCash, m) end
	cashFolder.ChildAdded:Connect(addCash)
	cashFolder.ChildRemoved:Connect(function(m)
		local spin = m:FindFirstChild("Spin")
		if spin then spinners[spin] = nil end
	end)

	RunService.RenderStepped:Connect(function()
		local t = now()
		local root = myRoot()
		local here = root and root.Position or camera.CFrame.Position
		for part, m in pairs(movers) do
			if part.Parent and (m.base.Position - here).Magnitude < NEAR then
				part.CFrame = moverCF(m, t)
			end
		end
		for part, b in pairs(blinkers) do
			if part.Parent then
				part.Transparency = (((t + b.offset) % b.period) < b.onTime) and b.on or 0.88
			end
		end
		for part, s in pairs(strikes) do
			if part.Parent then
				local u = (t + s.offset) % s.period
				if s.role == "bolt" then
					part.Transparency = (u >= 1.4 and u < 1.8) and 0 or 1
				elseif u < 1.4 then
					part.Transparency = (math.floor(u * 6) % 2 == 0) and 0.3 or 0.65
				elseif u < 1.8 then
					part.Transparency = 0
				else
					part.Transparency = 1
				end
			end
		end
		local clock = os.clock()
		for model, s in pairs(spinners) do
			if model.Parent and (s.base.Position - here).Magnitude < CASH_NEAR then
				model:PivotTo(s.base * CFrame.new(0, math.sin(clock * 2 + s.phase) * s.bob, 0) * CFrame.Angles(0, clock * s.speed + s.phase, 0))
			end
		end
	end)
end
task.spawn(startWorld)

------------------------------------------------------------------------
-- BOSSES: swing their legs while they run (faster when they're faster)
------------------------------------------------------------------------
local bosses = {} -- [model] = { motors = {...}, phase }

local function addBoss(model)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root then return end
	local motors = {}
	for _, m in ipairs(root:GetChildren()) do
		if m:IsA("Motor6D") and m.Name == "LegMotor" then
			table.insert(motors, m)
		end
	end
	bosses[model] = { root = root, motors = motors, phase = 0 }
end
watchTag("SVB_Boss", function(m) task.spawn(addBoss, m) end, bosses)

RunService.Stepped:Connect(function(_, dt)
	for model, b in pairs(bosses) do
		if model.Parent and b.root.Parent then
			local speed = (b.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			local stride = math.clamp(speed / 40, 0, 1)
			b.phase += dt * math.min(18, 4 + speed * 0.12)
			for _, m in ipairs(b.motors) do
				local side = m:GetAttribute("Side") or 1
				m.Transform = CFrame.Angles(math.sin(b.phase) * side * 0.9 * stride, 0, 0)
			end
		end
	end
end)

------------------------------------------------------------------------
-- RUNNING: our own run animation over the default one, a lean, a trail, a wider view
------------------------------------------------------------------------
-- Roblox's own animation packs (free for every game): a bouncy run, then a ninja dash
local RUN_ANIMS = {
	{ minSpeed = 26, id = "rbxassetid://742638842", maxRate = 1.8 },  -- Cartoony run
	{ minSpeed = 70, id = "rbxassetid://656118852", maxRate = 2.4 },  -- Ninja run
}

local runState = nil -- per character

local function setupRunning(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root then return end
	local animator = hum:WaitForChild("Animator", 10)
	local state = { hum = hum, root = root, tracks = {}, playing = nil, lean = 0 }
	runState = state

	-- load the run animations; only use the ones that actually load
	if animator then
		for i, def in ipairs(RUN_ANIMS) do
			task.spawn(function()
				local anim = Instance.new("Animation")
				anim.AnimationId = def.id
				local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
				if not ok or not track then return end
				track.Priority = Enum.AnimationPriority.Movement
				track.Looped = true
				local waited = 0
				while track.Length == 0 and waited < 5 do
					waited += task.wait(0.1)
				end
				if track.Length > 0 and runState == state then
					state.tracks[i] = { track = track, def = def }
				end
			end)
		end
	end

	-- speed trail from the hips
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, 0.4)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 220, 255))
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = root
	state.trail = trail

	-- the R15 root joint, so we can lean the body forward
	local lower = char:FindFirstChild("LowerTorso")
	local rootJoint = lower and lower:FindFirstChild("Root")
	if rootJoint and rootJoint:IsA("Motor6D") then
		state.joint = rootJoint
		state.c0 = rootJoint.C0
	end
end

local BASE_FOV = 70
RunService.RenderStepped:Connect(function(dt)
	local s = runState
	if not s or not s.hum.Parent then return end
	local hum, root = s.hum, s.root
	local flat = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local speed = flat.Magnitude
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local stunned = player:GetAttribute("Stunned") == true
	local moving = grounded and not stunned and hum.MoveDirection.Magnitude > 0.1 and speed > 4

	-- pick the run animation for this speed
	local want = nil
	if moving then
		for i, entry in pairs(s.tracks) do
			if speed >= entry.def.minSpeed and (not want or entry.def.minSpeed > s.tracks[want].def.minSpeed) then
				want = i
			end
		end
	end
	if want ~= s.playing then
		if s.playing and s.tracks[s.playing] then s.tracks[s.playing].track:Stop(0.2) end
		if want then s.tracks[want].track:Play(0.2) end
		s.playing = want
	end
	if want then
		local entry = s.tracks[want]
		entry.track:AdjustSpeed(math.clamp(speed / (entry.def.minSpeed * 1.4), 0.9, entry.def.maxRate))
	end

	-- lean into it (smoothed)
	local targetLean = moving and math.clamp((speed - 20) / 200, 0, 1) * math.rad(14) or 0
	s.lean += (targetLean - s.lean) * math.min(1, dt * 8)
	if s.joint and s.c0 then
		s.joint.C0 = s.c0 * CFrame.Angles(-s.lean, 0, 0)
	end

	if s.trail then s.trail.Enabled = moving and speed > 45 end

	-- wider view when you're fast
	local fov = BASE_FOV + math.clamp((speed - 30) / 220, 0, 1) * 20
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 4)
end)

player.CharacterAdded:Connect(setupRunning)
if player.Character then task.spawn(setupRunning, player.Character) end

------------------------------------------------------------------------
-- GETTING HIT: tumble, stars around your head, red flash, a little shake
------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "SVB_WorldFx"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Parent = gui
local vignette = Instance.new("UIGradient")
vignette.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 0.85),
	NumberSequenceKeypoint.new(0.7, 0.85),
	NumberSequenceKeypoint.new(1, 0),
})
vignette.Parent = flash

local ouch = Instance.new("TextLabel")
ouch.AnchorPoint = Vector2.new(0.5, 0.5)
ouch.Position = UDim2.fromScale(0.5, 0.38)
ouch.Size = UDim2.fromOffset(320, 90)
ouch.BackgroundTransparency = 1
ouch.Font = Enum.Font.FredokaOne
ouch.Text = "OUCH!"
ouch.TextScaled = true
ouch.TextColor3 = Color3.fromRGB(255, 235, 90)
ouch.Visible = false
ouch.Parent = gui
local ouchStroke = Instance.new("UIStroke")
ouchStroke.Color = Color3.fromRGB(120, 20, 20)
ouchStroke.Thickness = 5
ouchStroke.Parent = ouch
local ouchScale = Instance.new("UIScale")
ouchScale.Parent = ouch

local shakeUntil, shakePower = 0, 0
RunService:BindToRenderStep("SVB_HitShake", Enum.RenderPriority.Camera.Value + 1, function()
	local left = shakeUntil - os.clock()
	if left > 0 then
		local p = shakePower * left
		camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * p, (math.random() - 0.5) * p, 0)
	end
end)

local function spinStars(head, duration)
	local stars = {}
	for i = 1, 5 do
		local star = Instance.new("Part")
		star.Name = "HitStar"
		star.Shape = Enum.PartType.Ball
		star.Size = Vector3.one * 0.55
		star.Color = (i % 2 == 0) and Color3.fromRGB(255, 240, 120) or WHITE
		star.Material = Enum.Material.Neon
		star.Anchored = true
		star.CanCollide = false
		star.CanQuery = false
		star.CastShadow = false
		star.Parent = workspace
		stars[i] = star
	end
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > duration or not head.Parent then
			conn:Disconnect()
			for _, s in ipairs(stars) do s:Destroy() end
			return
		end
		for i, s in ipairs(stars) do
			local a = t * 7 + i * TAU / #stars
			s.CFrame = CFrame.new(head.Position + Vector3.new(math.cos(a) * 1.6, 1.3 + math.sin(t * 9 + i) * 0.15, math.sin(a) * 1.6))
		end
	end)
end

HitRemote.OnClientEvent:Connect(function(_message)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	if not hum or not root then return end

	-- tumble: knocked up and backwards, spinning
	hum.PlatformStand = true
	local back = -root.CFrame.LookVector
	root.AssemblyLinearVelocity = back * 28 + Vector3.new(0, 34, 0)
	root.AssemblyAngularVelocity = root.CFrame.RightVector * -12 + Vector3.new(0, math.random(-6, 6), 0)
	task.delay(0.75, function()
		if hum.Parent then
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
	if head then spinStars(head, 1.4) end

	-- red flash + "OUCH!" + shake
	flash.BackgroundTransparency = 0.2
	TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	ouch.Rotation = math.random(-12, 12)
	ouch.Visible = true
	ouchScale.Scale = 0.3
	TweenService:Create(ouchScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.9, function() ouch.Visible = false end)
	shakeUntil, shakePower = os.clock() + 0.45, 2.2
end)

------------------------------------------------------------------------
-- LIGHTING PER MAP: Map 1 is a bright sunny day, Map 2 a warm late afternoon
------------------------------------------------------------------------
local LOOKS = {
	{ clock = 14.6, atmosphere = Color3.fromRGB(200, 225, 255), decay = Color3.fromRGB(110, 150, 200), tint = Color3.fromRGB(255, 252, 245) },
	{ clock = 16.9, atmosphere = Color3.fromRGB(255, 205, 175), decay = Color3.fromRGB(175, 95, 85), tint = Color3.fromRGB(255, 236, 220) },
}
local function applyLook()
	local m = player:GetAttribute("CurrentMap") or 1
	local look = LOOKS[math.clamp(m, 1, #LOOKS)]
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, { ClockTime = look.clock }):Play()
	local atmo = Lighting:FindFirstChild("SVB_Atmosphere")
	if atmo then TweenService:Create(atmo, info, { Color = look.atmosphere, Decay = look.decay }):Play() end
	local cc = Lighting:FindFirstChild("SVB_Color")
	if cc then TweenService:Create(cc, info, { TintColor = look.tint }):Play() end
end
player:GetAttributeChangedSignal("CurrentMap"):Connect(applyLook)
task.defer(applyLook)
