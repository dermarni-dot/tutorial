--[[
	SPEED VS BRAINROT  -  World effects (LocalScript)
	Put this in: StarterPlayer > StarterPlayerScripts

	Everything here only changes what YOU see, so it's smooth (it runs every frame on
	your screen instead of being sent from the server):
	  - moving obstacles (sliders, spinners, swinging logs, crushers), lasers, fire jets
	    and strikes follow the server clock, so they're exactly where the server checks them
	  - cash piles and eggs spin and bob
	  - running: a fast run animation that speeds up with you (capped so it never
	    looks frantic), a forward lean, a speed trail and a wider camera view
	  - getting hit: you tumble, stars spin around your head, the screen flashes red
	  - every zone has its own sky: time of day, haze, fog and clouds blend in as you run
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
-- every frame: move what's near you
------------------------------------------------------------------------
local NEAR = 320
local CASH_NEAR = 160

local function startWorld()
	watchTag("SVB_Mover", addMover, movers)
	watchTag("SVB_Blink", addBlinker, blinkers)
	watchTag("SVB_Strike", addStrike, strikes)
	watchTag("SVB_EggSpin", addEgg, spinners)
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

-- you only ever see your own boss: everyone else's is hidden on your screen
local function hideBossPart(d)
	if d:IsA("BasePart") then
		d.LocalTransparencyModifier = 1
	elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("PointLight") then
		d.Enabled = false
	end
end
local function addBoss(model)
	local owner = model:GetAttribute("OwnerId")
	if owner and owner ~= player.UserId then
		for _, d in ipairs(model:GetDescendants()) do hideBossPart(d) end
		model.DescendantAdded:Connect(hideBossPart)
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root then return end
	local motors = {}
	for _, m in ipairs(root:GetChildren()) do
		if m:IsA("Motor6D") and (m.Name == "LegMotor" or m.Name == "ArmMotor") then
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
				if m.Name == "ArmMotor" then -- arms pump the other way from the legs
					m.Transform = CFrame.Angles(-math.sin(b.phase) * side * 0.8 * stride - 0.25 * stride, 0, 0)
				else
					m.Transform = CFrame.Angles(math.sin(b.phase) * side * 0.9 * stride, 0, 0)
				end
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
-- SKY + LIGHT PER ZONE: every zone has its own sky (time of day, haze color,
-- fog, clouds), blended smoothly as you run in. Islands use their map's look.
------------------------------------------------------------------------
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local LIGHT_SCALE = 0.6
local MAP_LOOKS = {
	{ clock = 14.6, atmo = rgb(200, 225, 255), decay = rgb(110, 150, 200), tint = rgb(255, 252, 245), density = 0.24, haze = 1.3, cover = 0.55, bright = 2.6 },
	{ clock = 16.9, atmo = rgb(255, 205, 175), decay = rgb(175, 95, 85), tint = rgb(255, 236, 220), density = 0.26, haze = 1.6, cover = 0.5, bright = 2.4 },
}
local ZONE_LOOKS = {
	meadow  = MAP_LOOKS[1],
	desert  = { clock = 13.2, atmo = rgb(255, 230, 190), decay = rgb(220, 170, 110), tint = rgb(255, 245, 225), density = 0.3, haze = 2.2, cover = 0.15, bright = 3 },
	ice     = { clock = 11.5, atmo = rgb(215, 235, 255), decay = rgb(150, 190, 235), tint = rgb(235, 245, 255), density = 0.32, haze = 1.4, cover = 0.7, bright = 2.8 },
	swamp   = { clock = 17.2, atmo = rgb(170, 200, 140), decay = rgb(80, 110, 60), tint = rgb(235, 255, 225), density = 0.4, haze = 2.6, cover = 0.8, bright = 2 },
	lava    = { clock = 18.2, atmo = rgb(255, 150, 100), decay = rgb(140, 50, 30), tint = rgb(255, 225, 205), density = 0.38, haze = 2.4, cover = 0.6, bright = 2.2 },
	candy   = { clock = 15, atmo = rgb(255, 210, 240), decay = rgb(230, 140, 200), tint = rgb(255, 240, 250), density = 0.26, haze = 1.4, cover = 0.45, bright = 2.7 },
	neon    = { clock = 21.5, atmo = rgb(90, 70, 160), decay = rgb(30, 20, 80), tint = rgb(225, 225, 255), density = 0.3, haze = 1.6, cover = 0.4, bright = 1.6 },
	crystal = { clock = 20, atmo = rgb(190, 150, 255), decay = rgb(90, 50, 160), tint = rgb(240, 230, 255), density = 0.3, haze = 1.8, cover = 0.35, bright = 1.9 },
	storm   = { clock = 16, atmo = rgb(140, 145, 165), decay = rgb(70, 72, 90), tint = rgb(225, 230, 240), density = 0.42, haze = 2.4, cover = 0.95, bright = 1.6 },
	void    = { clock = 0.5, atmo = rgb(120, 60, 200), decay = rgb(40, 10, 80), tint = rgb(235, 220, 255), density = 0.35, haze = 2, cover = 0.2, bright = 1.4 },
	jungle  = MAP_LOOKS[2],
	haunted = { clock = 22.5, atmo = rgb(120, 150, 130), decay = rgb(40, 60, 50), tint = rgb(220, 240, 230), density = 0.45, haze = 2.8, cover = 0.85, bright = 1.4 },
	factory = { clock = 17.5, atmo = rgb(200, 180, 150), decay = rgb(110, 90, 70), tint = rgb(255, 240, 220), density = 0.4, haze = 2.6, cover = 0.75, bright = 2 },
	space   = { clock = 0, atmo = rgb(60, 70, 140), decay = rgb(10, 10, 40), tint = rgb(225, 230, 255), density = 0.2, haze = 0.8, cover = 0, bright = 1.6 },
	rainbow = { clock = 12.5, atmo = rgb(240, 225, 255), decay = rgb(200, 170, 255), tint = rgb(255, 250, 255), density = 0.22, haze = 1.2, cover = 0.4, bright = 3 },
	inferno = { clock = 19, atmo = rgb(255, 110, 70), decay = rgb(120, 20, 10), tint = rgb(255, 220, 200), density = 0.45, haze = 3, cover = 0.7, bright = 2 },
}
local currentLook
local function applyLook(look)
	if look == currentLook then return end
	currentLook = look
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	-- LIGHT_SCALE tones every zone down together (raise it for a brighter game)
	local dim = look.bright / 3
	TweenService:Create(Lighting, info, {
		ClockTime = workspace:GetAttribute("AdminClock") or look.clock, -- admins can set the time for everyone
		Brightness = look.bright * LIGHT_SCALE,
		ExposureCompensation = -0.3,
		OutdoorAmbient = Color3.fromRGB(112, 112, 128):Lerp(look.decay, 0.25):Lerp(Color3.new(0, 0, 0), 0.35 * (1 - dim)),
	}):Play()
	local atmo = Lighting:FindFirstChild("SVB_Atmosphere")
	if atmo then TweenService:Create(atmo, info, { Color = look.atmo, Decay = look.decay, Density = look.density * 0.85, Haze = look.haze * 0.55, Glare = 0.1 }):Play() end
	local cc = Lighting:FindFirstChild("SVB_Color")
	if cc then TweenService:Create(cc, info, { TintColor = look.tint }):Play() end
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then TweenService:Create(clouds, info, { Cover = look.cover }):Play() end
end

-- an admin changed the time of day: blend to it right away
workspace:GetAttributeChangedSignal("AdminClock"):Connect(function()
	local look = currentLook
	currentLook = nil
	if look then applyLook(look) end
end)

-- which zone am I in? (zones are published by the server in ReplicatedStorage.SVB_Zones)
local zones = {}
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("SVB_Zones", 30)
	if not folder then return end
	local function add(c)
		table.insert(zones, { z0 = c:GetAttribute("Z0") or 0, z1 = c:GetAttribute("Z1") or 0, theme = c:GetAttribute("Theme"), map = c:GetAttribute("Map") or 1 })
	end
	for _, c in ipairs(folder:GetChildren()) do add(c) end
	folder.ChildAdded:Connect(add)
end)
task.spawn(function()
	while true do
		local root = myRoot()
		local look = MAP_LOOKS[math.clamp(player:GetAttribute("CurrentMap") or 1, 1, #MAP_LOOKS)]
		if root then
			local z = root.Position.Z
			for _, zn in ipairs(zones) do
				if z >= zn.z0 and z < zn.z1 then
					look = ZONE_LOOKS[zn.theme] or MAP_LOOKS[math.clamp(zn.map, 1, #MAP_LOOKS)]
					break
				end
			end
		end
		applyLook(look)
		task.wait(0.5)
	end
end)

------------------------------------------------------------------------
-- PETS THAT FOLLOW YOU: everyone's equipped pets float and hop along behind them.
-- Each kind of pet is built from parts with its own look (ears, tails, wings,
-- horns, beaks...). Golden pets are gold, Rainbow pets shift through the colours,
-- Legendary and Mythic pets sparkle. Built on each screen, so it costs the server nothing.
------------------------------------------------------------------------
do
	local PetInfo = ReplicatedStorage:WaitForChild("SVB_Pets", 10)
	local folder = Instance.new("Folder")
	folder.Name = "SVB_LocalPets"
	folder.Parent = workspace
	local BLACK = Color3.new(0, 0, 0)
	local MAX_PETS = 4
	local FLYERS = { bee = true, bird = true, bat = true, wisp = true, cloud = true, overlord = true, dragon = true }

	local function build(info, tier)
		local body = info:GetAttribute("Body") or WHITE
		local accent = info:GetAttribute("Accent") or BLACK
		local style = info:GetAttribute("Style") or "pup"
		local gold = tier == 2
		if gold then
			body, accent = Color3.fromRGB(255, 205, 60), Color3.fromRGB(255, 240, 160)
		end
		local model = Instance.new("Model")
		model.Name = info.Name
		local parts = {}
		local function part(shape, size, color, cf, material, oval)
			local p = Instance.new("Part")
			if shape then p.Shape = shape end
			p.Size = size
			p.Color = color
			p.Material = material or (gold and Enum.Material.Metal or Enum.Material.SmoothPlastic)
			if gold then p.Reflectance = 0.25 end
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.CFrame = cf
			if oval then
				local m = Instance.new("SpecialMesh")
				m.MeshType = Enum.MeshType.Sphere
				m.Parent = p
			end
			p.Parent = model
			table.insert(parts, { p = p, base = color, isBody = (color == body) })
			return p
		end
		local function ell(size, color, cf, material) return part(nil, size, color, cf, material, true) end
		local function ball(d, color, pos, material) return part(Enum.PartType.Ball, Vector3.one * d, color, CFrame.new(pos), material) end
		local C = CFrame.new
		local light, dark = body:Lerp(WHITE, 0.35), body:Lerp(BLACK, 0.25)
		-- eyes, cheeks, noses and bellies are painted onto the curve of the body (a thin oval
		-- bent to the same curve), so nothing sticks out of the pet
		local BR = (style == "slime") and Vector3.new(1.3, 0.95, 1.2) or Vector3.new(1.15, 1.1, 1.1)
		local function paint(x, y, w, h, color, o)
			o = o or {}
			local u, v = x / BR.X, y / BR.Y
			local wz = -math.sqrt(math.max(0.0004, 1 - u * u - v * v))
			local pnt = Vector3.new(u * BR.X, v * BR.Y, wz * BR.Z)
			local n = Vector3.new(u / BR.X, v / BR.Y, wz / BR.Z).Unit
			local th = o.t or math.max(0.05, math.max(w, h) ^ 2 / 2.2)
			local c = pnt + n * (0.01 + 0.012 * (o.layer or 0) + (o.raise or 0) - th / 2)
			local d = ell(Vector3.new(w, h, th), color, CFrame.lookAt(c, c + n) * CFrame.Angles(0, 0, o.roll or 0), o.material)
			if o.transparency then d.Transparency = o.transparency end
			return d
		end
		local function topY(z) -- the top of the body at depth z
			return BR.Y * math.sqrt(math.max(0, 1 - (z / BR.Z) ^ 2))
		end

		-- the round chibi body + a face (big shiny eyes, cheeks, a little mouth)
		local core
		if style == "robot" then
			core = part(nil, Vector3.new(2.3, 2.1, 2.1), body, C(0, 0, 0), Enum.Material.Metal)
			part(nil, Vector3.new(1.8, 0.7, 0.1), Color3.fromRGB(20, 25, 35), C(0, 0.25, -1.06))
			for _, sx in ipairs({ -1, 1 }) do
				part(nil, Vector3.new(0.45, 0.28, 0.05), accent, C(sx * 0.42, 0.25, -1.12), Enum.Material.Neon)
				ball(0.3, dark, Vector3.new(sx * 1.2, 0, 0), Enum.Material.Metal)
			end
			part(nil, Vector3.new(0.08, 0.7, 0.08), dark, C(0, 1.35, 0))
			ball(0.35, accent, Vector3.new(0, 1.75, 0), Enum.Material.Neon)
			part(nil, Vector3.new(1.2, 0.08, 0.05), accent, C(0, -0.45, -1.07), Enum.Material.Neon)
		else
			local squash = (style == "slime") and Vector3.new(2.6, 1.9, 2.4) or Vector3.new(2.3, 2.2, 2.2)
			core = ell(squash, body, C(0, 0, 0), (style == "wisp") and Enum.Material.Neon or nil)
			if style == "slime" then core.Transparency = 0.15 end
			if style == "wisp" then core.Transparency = 0.25 end
			if style ~= "slime" and style ~= "wisp" and style ~= "cloud" then
				paint(0, -0.4, 1.3, 1.0, light) -- lighter belly / muzzle
			end
			for _, sx in ipairs({ -1, 1 }) do
				paint(sx * 0.42, 0.22, 0.5, 0.58, WHITE, { layer = 1 })
				paint(sx * 0.43, 0.19, 0.32, 0.4, (style == "overlord") and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(25, 20, 30), { layer = 2, material = (style == "overlord") and Enum.Material.Neon or nil })
				paint(sx * 0.42 - 0.07, 0.3, 0.12, 0.12, WHITE, { layer = 3, material = Enum.Material.Neon })
				paint(sx * 0.7, -0.12, 0.3, 0.16, Color3.fromRGB(255, 130, 160), { layer = 1, transparency = 0.3 })
			end
			paint(0, -0.24, 0.26, 0.1, Color3.fromRGB(70, 25, 35), { layer = 1 })
		end

		-- what each kind of pet has
		if style == "bunny" then
			for _, sx in ipairs({ -1, 1 }) do
				ell(Vector3.new(0.45, 1.6, 0.3), body, C(sx * 0.4, 1.55, 0.05) * CFrame.Angles(0, 0, -sx * 0.15))
				ell(Vector3.new(0.25, 1.2, 0.1), Color3.fromRGB(255, 170, 190), C(sx * 0.4, 1.5, -0.08) * CFrame.Angles(0, 0, -sx * 0.15))
			end
			ball(0.6, light, Vector3.new(0, -0.3, 1.1))
		elseif style == "pup" or style == "bear" then
			for _, sx in ipairs({ -1, 1 }) do
				if style == "pup" then
					ell(Vector3.new(0.4, 0.9, 0.5), accent, C(sx * 1.05, 0.35, 0) * CFrame.Angles(0, 0, sx * 0.3))
				else
					ball(0.65, body, Vector3.new(sx * 0.75, 1.0, 0))
					ball(0.38, light, Vector3.new(sx * 0.75, 1.0, -0.15))
				end
			end
			paint(0, -0.02, 0.3, 0.2, BLACK, { layer = 2, raise = 0.06, t = 0.16 })
			if style == "pup" then ell(Vector3.new(0.25, 0.25, 0.8), accent, C(0, 0.2, 1.2) * CFrame.Angles(-0.7, 0, 0)) end
		elseif style == "cat" or style == "fox" or style == "wolf" then
			local earH = (style == "cat") and 0.7 or 0.9
			for _, sx in ipairs({ -1, 1 }) do
				local ear = C(sx * 0.55, 1.05, 0) * CFrame.Angles(0, 0, -sx * 0.25)
				local w = Instance.new("WedgePart")
				w.Size = Vector3.new(0.2, earH, 0.6)
				w.Color = (style == "cat") and body or accent
				w.Anchored, w.CanCollide, w.CanQuery, w.CastShadow = true, false, false, false
				w.CFrame = ear * CFrame.Angles(0, math.pi / 2, 0)
				w.Parent = model
				table.insert(parts, { p = w, base = w.Color })
				if style == "cat" then
					for k = -1, 1 do
						part(nil, Vector3.new(0.7, 0.03, 0.03), Color3.fromRGB(40, 40, 40), C(sx * 1.05, -0.12 + k * 0.1, -0.85) * CFrame.Angles(0, 0, sx * k * 0.15))
					end
				end
			end
			paint(0, -0.05, 0.18, 0.13, BLACK, { layer = 2, raise = 0.04, t = 0.1 })
			local tail = ell(Vector3.new(0.6, 0.6, 1.4), (style == "cat") and body or accent, C(0, 0.3, 1.3) * CFrame.Angles(-0.8, 0, 0))
			if style ~= "cat" then ball(0.5, WHITE, Vector3.new(0, 0.85, 1.85)) end
			_ = tail
		elseif style == "bee" then
			-- stripes wrapped around the body: thin slices that follow its curve
			for i = -1, 1 do
				for k = 0, 3 do
					local y = i * 0.5 - 0.105 + k * 0.07
					local d = 2 * BR.X * math.sqrt(math.max(0, 1 - (y / BR.Y) ^ 2)) + 0.03
					part(Enum.PartType.Cylinder, Vector3.new(0.075, d, d), accent, C(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2))
				end
			end
			for _, sx in ipairs({ -1, 1 }) do
				ell(Vector3.new(1.2, 0.08, 0.7), Color3.fromRGB(220, 240, 255), C(sx * 0.9, 1.0, 0.4) * CFrame.Angles(0, 0, sx * 0.5)).Transparency = 0.35
				part(nil, Vector3.new(0.06, 0.7, 0.06), BLACK, C(sx * 0.3, 1.28, -0.6) * CFrame.Angles(-0.4, 0, sx * 0.3))
				ball(0.18, BLACK, Vector3.new(sx * 0.4, 1.6, -0.74))
			end
		elseif style == "beetle" then
			for _, sx in ipairs({ -1, 1 }) do
				ell(Vector3.new(1.25, 1.5, 2.1), accent, C(sx * 0.55, 0.5, 0.25), Enum.Material.Glass)
				for k = -1, 1 do part(nil, Vector3.new(0.6, 0.08, 0.08), BLACK, C(sx * 0.9, -0.82, k * 0.5) * CFrame.Angles(0, 0, sx * 0.6)) end
			end
			part(nil, Vector3.new(0.15, 0.8, 0.15), accent, C(0, 1.15, -0.6) * CFrame.Angles(-0.5, 0, 0))
		elseif style == "penguin" then
			ell(Vector3.new(1.7, 1.8, 0.6), WHITE, C(0, -0.15, -0.8))
			ell(Vector3.new(0.4, 0.22, 0.5), Color3.fromRGB(255, 160, 40), C(0, -0.05, -1.25))
			for _, sx in ipairs({ -1, 1 }) do
				ell(Vector3.new(0.3, 1.1, 0.6), body, C(sx * 1.15, -0.1, 0) * CFrame.Angles(0, 0, sx * 0.35))
				ell(Vector3.new(0.5, 0.15, 0.7), Color3.fromRGB(255, 160, 40), C(sx * 0.45, -1.1, -0.3))
			end
		elseif style == "dragon" then
			for _, sx in ipairs({ -1, 1 }) do
				part(nil, Vector3.new(0.18, 0.7, 0.18), accent, C(sx * 0.5, 1.2, 0.1) * CFrame.Angles(0.4, 0, -sx * 0.3))
				ell(Vector3.new(1.4, 0.1, 0.9), accent, C(sx * 1.3, 0.6, 0.5) * CFrame.Angles(0, sx * 0.3, sx * 0.5))
			end
			for k = 0, 3 do
				local z = 0.15 + k * 0.24
				ball(0.32 - k * 0.04, accent, Vector3.new(0, topY(z) - 0.04, z))
			end
			ell(Vector3.new(0.5, 0.5, 1.4), body, C(0, -0.4, 1.3) * CFrame.Angles(-0.5, 0, 0))
		elseif style == "slime" then
			ell(Vector3.new(0.7, 0.35, 0.5), WHITE, C(-0.5, 0.65, -0.5)).Transparency = 0.5
			ell(Vector3.new(0.3, 0.5, 0.3), body, C(0.7, -0.75, -0.6)).Transparency = 0.15
		elseif style == "bird" then
			ell(Vector3.new(0.35, 0.25, 0.55), Color3.fromRGB(255, 180, 50), C(0, -0.05, -1.25))
			for _, sx in ipairs({ -1, 1 }) do
				ell(Vector3.new(0.3, 1.0, 1.2), accent, C(sx * 1.15, 0.1, 0.2) * CFrame.Angles(0, 0, sx * 0.5))
			end
			for k = -1, 1 do ell(Vector3.new(0.15, 0.6, 0.2), accent, C(k * 0.15, 1.3, 0) * CFrame.Angles(0, 0, k * 0.4)) end
		elseif style == "cloud" then
			for i = 0, 5 do
				local a = i * TAU / 6
				ball(1.2, body, Vector3.new(math.cos(a) * 1.0, 0.1 + (i % 2) * 0.25, math.sin(a) * 0.7 + 0.3))
			end
		elseif style == "unicorn" then
			for k = 0, 3 do
				part(Enum.PartType.Cylinder, Vector3.new(0.3, 0.42 - k * 0.09, 0.42 - k * 0.09), Color3.fromRGB(255, 215, 80), C(0, 0.92 + k * 0.27, -0.42 - k * 0.08) * CFrame.Angles(-0.3, 0, math.pi / 2), Enum.Material.Neon)
			end
			for k = 0, 4 do
				local z = 0.05 + k * 0.2
				ball(0.42, accent, Vector3.new(0, topY(z) - 0.08, z))
			end
			for _, sx in ipairs({ -1, 1 }) do ell(Vector3.new(0.3, 0.6, 0.3), body, C(sx * 0.55, 1.05, 0.1)) end
		elseif style == "bat" then
			for _, sx in ipairs({ -1, 1 }) do
				ell(Vector3.new(1.8, 0.1, 1.0), accent, C(sx * 1.6, 0.3, 0.3) * CFrame.Angles(0, 0, sx * 0.25))
				ell(Vector3.new(0.4, 0.8, 0.25), body, C(sx * 0.6, 1.1, 0) * CFrame.Angles(0, 0, -sx * 0.25))
				part(nil, Vector3.new(0.08, 0.15, 0.06), WHITE, C(sx * 0.1, -0.33, -1.1))
			end
		elseif style == "wisp" then
			for k = 0, 2 do
				local f = ball(1.1 - k * 0.3, accent, Vector3.new(0, 1.0 + k * 0.45, 0.2 + k * 0.15), Enum.Material.Neon)
				f.Transparency = 0.3 + k * 0.15
			end
		elseif style == "overlord" then
			part(Enum.PartType.Cylinder, Vector3.new(0.3, 1.3, 1.3), Color3.fromRGB(255, 215, 60), C(0, 1.15, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Neon)
			for i = 0, 4 do
				local a = i * TAU / 5
				part(nil, Vector3.new(0.18, 0.45, 0.18), Color3.fromRGB(255, 215, 60), C(math.cos(a) * 0.55, 1.45, math.sin(a) * 0.55), Enum.Material.Neon)
			end
			part(nil, Vector3.new(2.0, 2.2, 0.1), accent, C(0, -0.2, 1.1) * CFrame.Angles(0.15, 0, 0), Enum.Material.Fabric)
		end
		-- little feet for the walkers
		if not FLYERS[style] and style ~= "slime" then
			for _, sx in ipairs({ -1, 1 }) do
				ell(Vector3.new(0.55, 0.35, 0.7), dark, C(sx * 0.5, -1.05, -0.15))
			end
		end
		model.PrimaryPart = core
		-- rare pets sparkle
		local rarity = info:GetAttribute("RarityIndex") or 1
		if rarity >= 5 or tier >= 2 then
			local sp = Instance.new("ParticleEmitter")
			sp.Color = ColorSequence.new((info:GetAttribute("RarityColor") or WHITE):Lerp(WHITE, 0.3))
			sp.LightEmission = 1
			sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0) })
			sp.Lifetime = NumberRange.new(0.6, 1)
			sp.Speed = NumberRange.new(0.5, 1.5)
			sp.SpreadAngle = Vector2.new(180, 180)
			sp.Rate = 6
			sp.Parent = core
		end
		model.Parent = folder
		return { model = model, parts = parts, flyer = FLYERS[style] == true, rainbow = tier == 3 }
	end

	local owners = {} -- [player] = { key = "...", pets = { {pet...}, ... } }
	local function clear(plr)
		local o = owners[plr]
		if o then
			for _, p in ipairs(o.pets) do p.model:Destroy() end
		end
		owners[plr] = nil
	end
	local function refresh(plr)
		local key = plr:GetAttribute("EquippedPets") or ""
		if owners[plr] and owners[plr].key == key then return end
		clear(plr)
		local o = { key = key, pets = {} }
		local n = 0
		for item in string.gmatch(key, "[^,]+") do
			local name, tier = string.match(item, "^(.+)|(%d)$")
			local info = name and PetInfo and PetInfo:FindFirstChild(name)
			if info and n < MAX_PETS then
				n += 1
				local ok, pet = pcall(build, info, tonumber(tier) or 1)
				if ok and pet then
					pet.slot = n
					pet.cf = nil
					table.insert(o.pets, pet)
				end
			end
		end
		owners[plr] = o
	end
	local function watch(plr)
		refresh(plr)
		plr:GetAttributeChangedSignal("EquippedPets"):Connect(function() refresh(plr) end)
	end
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(watch, p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)

	-- where each pet sits behind its owner: a little fan
	local SLOTS = { Vector3.new(-3.6, 0, 4.2), Vector3.new(3.6, 0, 4.2), Vector3.new(-2, 0, 7.4), Vector3.new(2, 0, 7.4) }
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local cam = workspace.CurrentCamera
		for plr, o in pairs(owners) do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local far = root and cam and (root.Position - cam.CFrame.Position).Magnitude > 250
			for _, pet in ipairs(o.pets) do
				if not root or far then
					pet.model.Parent = nil
				else
					pet.model.Parent = folder
					local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
					if look.Magnitude < 0.01 then look = Vector3.zAxis end
					local flat = CFrame.lookAt(root.Position, root.Position + look)
					local off = SLOTS[pet.slot] or SLOTS[1]
					local moving = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 2
					local bob
					if pet.flyer then
						bob = 2.2 + math.sin(t * 3 + pet.slot) * 0.45
					else
						bob = -1.6 + (moving and math.abs(math.sin(t * 9 + pet.slot)) * 0.9 or math.sin(t * 2 + pet.slot) * 0.1)
					end
					local goal = flat * CFrame.new(off.X, bob, off.Z)
					local face = CFrame.lookAt(goal.Position, goal.Position + look)
					pet.cf = pet.cf and pet.cf:Lerp(face, math.min(1, dt * 10)) or face
					-- keep up even at huge speeds
					if (pet.cf.Position - face.Position).Magnitude > 40 then pet.cf = face end
					pet.model:PivotTo(pet.cf * CFrame.Angles(0, 0, pet.flyer and math.sin(t * 2 + pet.slot) * 0.08 or 0))
					if pet.rainbow then
						local c = Color3.fromHSV((t * 0.25 + pet.slot * 0.1) % 1, 0.55, 1)
						for _, e in ipairs(pet.parts) do
							if e.isBody then e.p.Color = c end
						end
					end
				end
			end
		end
	end)
end
