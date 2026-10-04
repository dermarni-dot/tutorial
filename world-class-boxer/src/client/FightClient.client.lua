-- FightClient: fight-night presentation and controls (also used for gym sparring).
-- TV broadcast overlay, weigh-in + tale of the tape, ring walks with music, pyro and
-- sweeping spotlights, crowd reactions, venue lighting, live commentary ticker,
-- defense call-outs, knockdown get-up meter, corner advice between rounds.
-- Controls: 1/J jab, 2/K cross, 3/L lead hook, 4 rear hook, 5/U uppercut, 6/O overhand,
-- hold SHIFT = to the body, hold F block, R parry, Q/E slip, C roll, Z/X pivot, G clinch.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme
local FightRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fight")

local gui = UI.New("ScreenGui", { Name = "FightUI", ResetOnSpawn = false, IgnoreGuiInset = false, Enabled = false, DisplayOrder = 5, Parent = player:WaitForChild("PlayerGui") })

local Debris = game:GetService("Debris")
local F = {} -- current fight state

-- built-in Roblox sounds (no uploaded assets needed)
local function sfx(part, speed, volume, id)
	if not part then
		return
	end
	local snd = Instance.new("Sound")
	snd.SoundId = id or "rbxasset://sounds/action_jump_land.mp3"
	snd.PlaybackSpeed = speed or 1
	snd.Volume = volume or 0.5
	snd.RollOffMaxDistance = 90
	snd.Parent = part
	snd:Play()
	Debris:AddItem(snd, 2)
end
local camConn, fxConn
local music
local savedLighting

local function send(msg)
	FightRemote:FireServer(msg)
end

------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------
local bug = UI.Frame(gui, { Size = UDim2.fromOffset(200, 28), Position = UDim2.fromOffset(16, 6), BackgroundColor3 = T.red })
UI.Corner(bug, 4)
local bugText = UI.Text(bug, "LIVE  -  WCB SPORTS", { Font = T.bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None })

local function fighterPanel(side)
	local f = UI.Frame(gui, { Size = UDim2.new(0.34, 0, 0, 92), Position = side == "L" and UDim2.new(0, 16, 0, 40) or UDim2.new(1, -16, 0, 40),
		AnchorPoint = side == "L" and Vector2.new(0, 0) or Vector2.new(1, 0), BackgroundColor3 = T.bg, BackgroundTransparency = 0.2 })
	UI.Corner(f, 8)
	UI.Stroke(f, side == "L" and T.red or T.blue, 2)
	local name = UI.Text(f, "", { Font = T.bold, TextSize = 16, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 22), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = side == "L" and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right })
	local function bar(y, color, label)
		UI.Text(f, label, { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(10, y - 1), Size = UDim2.fromOffset(52, 14), AutomaticSize = Enum.AutomaticSize.None })
		local bg = UI.Frame(f, { Position = UDim2.new(0, 62, 0, y), Size = UDim2.new(1, -72, 0, 12), BackgroundColor3 = Color3.fromRGB(60, 10, 10) })
		UI.Corner(bg, 3)
		local _, set = UI.Bar(bg, { Size = UDim2.fromScale(1, 1) }, color)
		return set
	end
	return {
		frame = f, name = name, setHp = bar(30, T.green, "HEAD"), setBody = bar(50, T.orange, "BODY"), setStam = bar(70, T.blue, "STAMINA"),
	}
end
local L = fighterPanel("L")
local R = fighterPanel("R")

local clock = UI.Frame(gui, { Size = UDim2.fromOffset(150, 70), Position = UDim2.new(0.5, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = T.bg, BackgroundTransparency = 0.15 })
UI.Corner(clock, 8)
UI.Stroke(clock, T.gold, 2)
local roundText = UI.Text(clock, "ROUND 1", { Font = T.bold, TextSize = 14, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 4), AutomaticSize = Enum.AutomaticSize.None })
local timeText = UI.Text(clock, "1:00", { Font = T.bold, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.None })
local angleTag = UI.Text(gui, "ANGLE! +ACCURACY", { Font = T.bold, TextSize = 14, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(200, 20), Position = UDim2.new(0.5, -100, 0, 114), Visible = false, AutomaticSize = Enum.AutomaticSize.None })

local banner = UI.Text(gui, "", { Font = T.bold, TextSize = 60, TextColor3 = T.gold, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 80), Position = UDim2.new(0, 0, 0.3, 0), Visible = false, AutomaticSize = Enum.AutomaticSize.None })
local flash = UI.Text(gui, "", { Font = T.bold, TextSize = 26, TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0.5, 40), Visible = false, AutomaticSize = Enum.AutomaticSize.None })
local defFlash = UI.Text(gui, "", { Font = T.bold, TextSize = 22, TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.5, 78), Visible = false, AutomaticSize = Enum.AutomaticSize.None })
local ticker = UI.Frame(gui, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -30), BackgroundColor3 = T.bg, BackgroundTransparency = 0.1 })
local tickerTag = UI.Frame(ticker, { Size = UDim2.fromOffset(110, 30), BackgroundColor3 = T.red })
UI.Text(tickerTag, "COMMENTARY", { Font = T.bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None })
local tickerText = UI.Text(ticker, "", { TextSize = 15, Font = T.semi, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(120, 0), Size = UDim2.new(1, -130, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
local controls = UI.Text(gui, "1/J Jab  2/K Cross  3/L Lead Hook  4 Rear Hook  5/U Uppercut  6/O Overhand  |  SHIFT body  F block  R parry  Q/E slip  C roll  Z/X pivot  G clinch",
	{ TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -50), AutomaticSize = Enum.AutomaticSize.None })

local function showBanner(text, color, dur)
	banner.Text = text
	banner.TextColor3 = color or T.gold
	banner.Visible = true
	local id = os.clock()
	banner:SetAttribute("Id", id)
	task.delay(dur or 1.6, function()
		if banner:GetAttribute("Id") == id then
			banner.Visible = false
		end
	end)
end

local function showFlash(label, text, color, dur)
	label.Text = text
	label.TextColor3 = color or T.text
	label.Visible = true
	local id = os.clock()
	label:SetAttribute("Id", id)
	task.delay(dur or 0.8, function()
		if label:GetAttribute("Id") == id then
			label.Visible = false
		end
	end)
end

local function setTicker(text)
	tickerText.Text = text
end

-- overlay panel used for the tale of the tape / corner
local overlay = UI.Frame(gui, { Size = UDim2.new(0.94, 0, 0, 420), Position = UDim2.fromScale(0.5, 0.55), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = T.bg, BackgroundTransparency = 0.08, Visible = false })
UI.Corner(overlay, 12)
UI.Stroke(overlay, T.gold, 2)
UI.Pad(overlay, 14)
UI.List(overlay, 3)
UI.New("UISizeConstraint", { MaxSize = Vector2.new(660, 440), Parent = overlay })

local function overlayLines(lines)
	UI.Clear(overlay)
	for _, l in ipairs(lines) do
		UI.Text(overlay, l[1], { Font = l.bold and T.bold or T.font, TextSize = l.size or 16, TextColor3 = l.color or T.text,
			TextXAlignment = l.left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
	end
	overlay.Visible = true
end

-- get-up meter
local getup = UI.Frame(gui, { Size = UDim2.fromOffset(420, 90), Position = UDim2.new(0.5, 0, 0.62, 0), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = T.bg, Visible = false })
UI.Corner(getup, 10)
UI.Stroke(getup, T.red, 2)
UI.Text(getup, "YOU'RE DOWN!  MASH SPACE / TAP TO GET UP", { Font = T.bold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.red, AutomaticSize = Enum.AutomaticSize.None })
local _, setGetup = UI.Bar(getup, { Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -32, 0, 22) }, T.gold)
local getupBtn = UI.Button(getup, "", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, function()
	if F.down then
		F.mash += 1
		send({ t = "mash" })
		setGetup(F.mash / math.max(1, F.target))
	end
end)
getupBtn.Text = ""

-- touch controls
local touchPad
local function buildTouch()
	if touchPad or not UserInputService.TouchEnabled then
		return
	end
	touchPad = UI.Frame(gui, { BackgroundTransparency = 1, Size = UDim2.fromOffset(380, 186), Position = UDim2.new(1, -12, 1, -56), AnchorPoint = Vector2.new(1, 1) })
	UI.Grid(touchPad, 70, 56, 6)
	local function tb(label, color, down, up)
		local b = UI.Button(touchPad, label, { BackgroundColor3 = color or T.panel2, BackgroundTransparency = 0.15, TextSize = 13 })
		b.MouseButton1Down:Connect(down)
		if up then
			b.MouseButton1Up:Connect(up)
		end
		return b
	end
	local function punch(p)
		return function()
			send({ t = "punch", p = p, body = F.bodyMod == true and p ~= "overhand" })
		end
	end
	tb("JAB", T.red, punch("jab"))
	tb("CROSS", T.red, punch("cross"))
	tb("L.HOOK", T.red, punch("leadhook"))
	tb("R.HOOK", T.red, punch("rearhook"))
	tb("UPPER", T.red, punch("uppercut"))
	tb("OVER\nHAND", T.red, punch("overhand"))
	local bodyBtn
	bodyBtn = tb("BODY", T.orange, function()
		F.bodyMod = not F.bodyMod
		bodyBtn.BackgroundColor3 = F.bodyMod and T.gold or T.orange
		showFlash(flash, F.bodyMod and "BODY SHOTS" or "HEAD SHOTS", T.gold)
	end)
	tb("BLOCK", T.blue, function()
		send({ t = "block", on = true })
	end, function()
		send({ t = "block", on = false })
	end)
	tb("PARRY", T.blue, function()
		send({ t = "parry" })
	end)
	tb("SLIP L", T.blue, function()
		send({ t = "slip", dir = -1 })
	end)
	tb("SLIP R", T.blue, function()
		send({ t = "slip", dir = 1 })
	end)
	tb("ROLL", T.blue, function()
		send({ t = "roll" })
	end)
	tb("PIVOT L", T.green, function()
		send({ t = "pivot", dir = -1 })
	end)
	tb("PIVOT R", T.green, function()
		send({ t = "pivot", dir = 1 })
	end)
	tb("CLINCH", T.green, function()
		send({ t = "clinch" })
	end)
end

------------------------------------------------------------------------
-- Venue presentation: lighting, crowd, spotlights, pyro, screens
------------------------------------------------------------------------
local VENUE_LIGHT = {
	Stadium = { ClockTime = 21, Brightness = 1.2, Ambient = Color3.fromRGB(50, 50, 60), OutdoorAmbient = Color3.fromRGB(40, 40, 55), Exposure = 0.2 },
	Arena = { ClockTime = 21, Brightness = 0.6, Ambient = Color3.fromRGB(38, 38, 46), OutdoorAmbient = Color3.fromRGB(30, 30, 40), Exposure = 0.3 },
	ClubArena = { ClockTime = 21, Brightness = 0.6, Ambient = Color3.fromRGB(46, 44, 50), OutdoorAmbient = Color3.fromRGB(35, 35, 42), Exposure = 0.25 },
	CommunityCenter = { ClockTime = 19, Brightness = 1, Ambient = Color3.fromRGB(80, 80, 86), OutdoorAmbient = Color3.fromRGB(70, 70, 80), Exposure = 0 },
	Gym = { ClockTime = 14, Brightness = 0.9, Ambient = Color3.fromRGB(78, 78, 86), OutdoorAmbient = Color3.fromRGB(95, 95, 105), Exposure = -0.1 },
}

-- the gym's outdoor look (sun rays, warm grade, hazy atmosphere) is switched off for fight
-- nights in the venues and put back afterwards
local GYM_EFFECTS = { "GymSunRays", "GymGrade" }
local function setVenueLighting(venue)
	if not savedLighting then
		savedLighting = { ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Exposure = Lighting.ExposureCompensation, effects = {} }
		if venue ~= "Gym" then
			for _, n in ipairs(GYM_EFFECTS) do
				local e = Lighting:FindFirstChild(n)
				if e and e:IsA("PostEffect") then
					savedLighting.effects[e] = e.Enabled
					e.Enabled = false
				end
			end
			local atm = Lighting:FindFirstChildOfClass("Atmosphere")
			if atm then
				savedLighting.atm = { inst = atm, Density = atm.Density, Haze = atm.Haze }
				atm.Density = 0.12
				atm.Haze = 0.4
			end
		end
	end
	local v = VENUE_LIGHT[venue] or VENUE_LIGHT.Arena
	Lighting.ClockTime = v.ClockTime
	Lighting.Brightness = v.Brightness
	Lighting.Ambient = v.Ambient
	Lighting.OutdoorAmbient = v.OutdoorAmbient
	Lighting.ExposureCompensation = v.Exposure
end

local function restoreLighting()
	if savedLighting then
		Lighting.ClockTime = savedLighting.ClockTime
		Lighting.Brightness = savedLighting.Brightness
		Lighting.Ambient = savedLighting.Ambient
		Lighting.OutdoorAmbient = savedLighting.OutdoorAmbient
		Lighting.ExposureCompensation = savedLighting.Exposure
		for e, on in pairs(savedLighting.effects or {}) do
			if e.Parent then
				e.Enabled = on
			end
		end
		local a = savedLighting.atm
		if a and a.inst.Parent then
			a.inst.Density = a.Density
			a.inst.Haze = a.Haze
		end
		savedLighting = nil
	end
end

local crowd = {}
local spots = {}
local tallies = {}
local excitement = 0.2
local sweeping = 0

local function startVenueFx(arena)
	crowd, spots, tallies = {}, {}, {}
	if not arena then
		return
	end
	local folder = arena:FindFirstChild("Crowd")
	if folder then
		for _, fan in ipairs(folder:GetChildren()) do
			if fan:IsA("BasePart") then
				local head = fan:FindFirstChild("Head")
				table.insert(crowd, { fan = fan, head = head, base = fan.CFrame, hbase = head and head.CFrame, phase = math.random() * 6.28, speed = 6 + math.random() * 4 })
			end
		end
	end
	local sf = arena:FindFirstChild("Spots")
	if sf then
		for i, s in ipairs(sf:GetChildren()) do
			table.insert(spots, { p = s, base = s.Position, phase = i })
		end
	end
	for _, d in ipairs(arena:GetDescendants()) do
		if d.Name == "TallyLight" then
			table.insert(tallies, d)
		end
	end
	if fxConn then
		fxConn:Disconnect()
	end
	local frame = 0
	local center = F.center or Vector3.zero
	fxConn = RunService.Heartbeat:Connect(function(dt)
		excitement = math.max(0.15, excitement - dt * 0.35)
		sweeping = math.max(0, sweeping - dt)
		frame += 1
		local t = os.clock()
		if frame % 2 == 0 then
			for _, c in ipairs(crowd) do
				local up = math.max(0, math.sin(t * c.speed + c.phase)) * excitement * 1.2
				local off = CFrame.new(0, up, 0)
				c.fan.CFrame = c.base * off
				if c.head then
					c.head.CFrame = c.hbase * off
				end
			end
		end
		-- spotlights: sweep the crowd at big moments, otherwise lock onto the ring
		for _, s in ipairs(spots) do
			local target
			if sweeping > 0 then
				local a = t * 1.3 + s.phase * 1.1
				target = center + Vector3.new(math.cos(a) * 45, 0, math.sin(a * 0.8) * 45)
			else
				target = center + Vector3.new(math.cos(t * 0.6 + s.phase) * 4, 0, math.sin(t * 0.5 + s.phase) * 4)
			end
			s.p.CFrame = CFrame.lookAt(s.base, target)
		end
		for _, tl in ipairs(tallies) do
			tl.Transparency = (math.floor(t * 2) % 2 == 0) and 0 or 0.7
		end
	end)
end

local function cheer(amount)
	excitement = math.min(1.6, excitement + amount)
end

local function screens(text)
	if not F.arena then
		return
	end
	for _, name in ipairs({ "Jumbotron", "BigScreen" }) do
		for _, screen in ipairs(F.arena:GetChildren()) do
			if screen.Name == name then
				for _, d in ipairs(screen:GetDescendants()) do
					if d:IsA("TextLabel") then
						d.Text = text
					end
				end
			end
		end
	end
end

local function pyro(side)
	local folder = F.arena and F.arena:FindFirstChild("Pyro")
	if not folder then
		return
	end
	for _, p in ipairs(folder:GetChildren()) do
		if p.Name == (side == "red" and "PyroRed" or "PyroBlue") then
			local pe = p:FindFirstChildOfClass("ParticleEmitter")
			if pe then
				pe.Enabled = true
				task.delay(1.6, function()
					pe.Enabled = false
				end)
			end
		end
	end
	sweeping = 4
end

------------------------------------------------------------------------
-- Camera
------------------------------------------------------------------------
local shake = 0
local camMode = "fight" -- fight | entrance | wide | tape
local camTarget

local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

-- ropes, posts and pads that sit between the camera and the fighters fade out so they never block the action
local ringParts, faded, fadeClock = {}, {}, 0
local function collectRingParts()
	table.clear(ringParts)
	for p in pairs(faded) do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	table.clear(faded)
	if not F.arena then
		return
	end
	for _, d in ipairs(F.arena:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Rope" or d.Name == "Post" or d.Name == "Pad") then
			table.insert(ringParts, d)
		end
	end
end
-- closest distance between segments p1-q1 and p2-q2, plus how far along the first segment it happens (0..1)
local function segSegDist(p1, q1, p2, q2)
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	local s, t
	if a <= 1e-6 then
		s, t = 0, (e > 1e-6) and math.clamp(f / e, 0, 1) or 0
	else
		local c = d1:Dot(r)
		if e <= 1e-6 then
			t, s = 0, math.clamp(-c / a, 0, 1)
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			s = denom > 1e-6 and math.clamp((b * f - c * e) / denom, 0, 1) or 0
			t = (b * s + f) / e
			if t < 0 then
				t, s = 0, math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t, s = 1, math.clamp((b - c) / a, 0, 1)
			end
		end
	end
	return ((p1 + d1 * s) - (p2 + d2 * t)).Magnitude, s
end

local function updateOccluders(camPos, targets)
	if #ringParts == 0 then
		return
	end
	local hitNow = {}
	for _, p in ipairs(ringParts) do
		if p.Parent then
			-- ropes run along their length (Z); posts and pads stand upright (Y)
			local axis, half, thr
			if p.Name == "Rope" then
				axis, half, thr = p.CFrame.LookVector, p.Size.Z / 2, 1.9
			else
				axis, half, thr = p.CFrame.UpVector, p.Size.Y / 2, 1.6
			end
			local a, b = p.Position - axis * half, p.Position + axis * half
			for _, target in ipairs(targets) do
				local d, s = segSegDist(camPos, target, a, b)
				if d < thr and s < 0.93 then
					hitNow[p] = true
					break
				end
			end
		end
	end
	for p in pairs(faded) do
		if not hitNow[p] then
			p.LocalTransparencyModifier = 0
			faded[p] = nil
		end
	end
	for p in pairs(hitNow) do
		p.LocalTransparencyModifier = 0.8
		faded[p] = true
	end
end

local function startCamera()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	if camConn then
		camConn:Disconnect()
	end
	collectRingParts()
	local t0 = os.clock()
	camConn = RunService.RenderStepped:Connect(function(dt)
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local me = getRoot(player.Character)
		local opp = getRoot(F.opp)
		if not me then
			return
		end
		shake = math.max(0, shake - dt * 3)
		local sh = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake
		local goal
		if camMode == "entrance" and camTarget then
			local r = getRoot(camTarget)
			if r then
				local p = r.Position
				goal = CFrame.lookAt(p + r.CFrame.LookVector * 10 + Vector3.new(2.5, 3, 0), p + Vector3.new(0, 1.5, 0))
			end
		elseif camMode == "wide" or camMode == "tape" then
			local center = F.center or me.Position
			local a = (os.clock() - t0) * 0.15
			local dist = F.spar and 22 or 30
			goal = CFrame.lookAt(center + Vector3.new(math.cos(a) * dist, 14, math.sin(a) * dist), center + Vector3.new(0, 3, 0))
		elseif opp then
			local dir = Vector3.new(opp.Position.X - me.Position.X, 0, opp.Position.Z - me.Position.Z)
			if dir.Magnitude < 0.1 then
				dir = Vector3.new(0, 0, -1)
			end
			dir = dir.Unit
			local right = dir:Cross(Vector3.yAxis)
			local mid = (me.Position + opp.Position) / 2 + Vector3.new(0, 1.2, 0)
			-- high 3/4 view from behind your shoulder; pick the side nearer the ring centre
			local center = F.center or mid
			-- a 3/4 angle (about 40 degrees off the fight line) keeps both fighters readable instead of stacked
			local function camPos(side)
				return me.Position - dir * 6.6 + right * (side * 5.8) + Vector3.new(0, 5.4, 0)
			end
			local function flatDist(a, b)
				return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
			end
			F.camSide = F.camSide or 1
			local pos = camPos(F.camSide)
			local other = camPos(-F.camSide)
			if flatDist(other, center) + 3 < flatDist(pos, center) then
				F.camSide = -F.camSide
				pos = other
			end
			goal = CFrame.lookAt(pos, mid)
		end
		if goal then
			cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 8, 0, 1)) + sh
		end
		fadeClock += dt
		if fadeClock > 0.08 then
			fadeClock = 0
			local targets = { me.Position + Vector3.new(0, 1.5, 0), me.Position, me.Position - Vector3.new(0, 1.2, 0) }
			if opp then
				table.insert(targets, opp.Position + Vector3.new(0, 1.5, 0))
				table.insert(targets, opp.Position)
			end
			updateOccluders(cam.CFrame.Position, targets)
		end
	end)
end

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------
local keyPunch = {
	[Enum.KeyCode.One] = "jab", [Enum.KeyCode.J] = "jab",
	[Enum.KeyCode.Two] = "cross", [Enum.KeyCode.K] = "cross",
	[Enum.KeyCode.Three] = "leadhook", [Enum.KeyCode.L] = "leadhook",
	[Enum.KeyCode.Four] = "rearhook", [Enum.KeyCode.Semicolon] = "rearhook",
	[Enum.KeyCode.Five] = "uppercut", [Enum.KeyCode.U] = "uppercut",
	[Enum.KeyCode.Six] = "overhand", [Enum.KeyCode.O] = "overhand",
}

UserInputService.InputBegan:Connect(function(input, gp)
	if not F.active or gp then
		return
	end
	if F.down and (input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton1) then
		F.mash += 1
		send({ t = "mash" })
		setGetup(F.mash / math.max(1, F.target))
		return
	end
	local body = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) or F.bodyMod == true
	local p = keyPunch[input.KeyCode]
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		p = "jab"
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		p = "cross"
	end
	local k = input.KeyCode
	if p then
		send({ t = "punch", p = p, body = body and p ~= "overhand" })
	elseif k == Enum.KeyCode.F then
		send({ t = "block", on = true })
	elseif k == Enum.KeyCode.R then
		send({ t = "parry" })
	elseif k == Enum.KeyCode.Q then
		send({ t = "slip", dir = -1 })
	elseif k == Enum.KeyCode.E then
		send({ t = "slip", dir = 1 })
	elseif k == Enum.KeyCode.C then
		send({ t = "roll" })
	elseif k == Enum.KeyCode.Z then
		send({ t = "pivot", dir = -1 })
	elseif k == Enum.KeyCode.X then
		send({ t = "pivot", dir = 1 })
	elseif k == Enum.KeyCode.G then
		send({ t = "clinch" })
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if F.active and input.KeyCode == Enum.KeyCode.F then
		send({ t = "block", on = false })
	end
end)

------------------------------------------------------------------------
-- Animate script control for the local character during a fight
------------------------------------------------------------------------
local function setAnimate(on)
	local char = player.Character
	if not char then
		return
	end
	local animate = char:FindFirstChild("Animate")
	if animate then
		animate.Disabled = not on
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator and not on then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0.1)
		end
	end
end

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------
local function fmtTime(s)
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function stopMusic()
	if music then
		local m = music
		music = nil
		TweenService:Create(m, TweenInfo.new(2), { Volume = 0 }):Play()
		task.delay(2.1, function()
			m:Destroy()
		end)
	end
end

local function finish()
	F.active = false
	F.down = false
	gui.Enabled = false
	overlay.Visible = false
	getup.Visible = false
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	for p in pairs(faded) do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	table.clear(faded)
	table.clear(ringParts)
	if fxConn then
		fxConn:Disconnect()
		fxConn = nil
	end
	stopMusic()
	setAnimate(true)
	restoreLighting()
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	player:SetAttribute("InFight", false)
end

local PUNCH_NAME = { jab = "JAB", cross = "CROSS", leadhook = "LEAD HOOK", rearhook = "REAR HOOK", uppercut = "UPPERCUT", overhand = "OVERHAND" }

local handlers = {}

function handlers.start(msg)
	F = { active = false, mash = 0, target = 10, arena = msg.arena, opp = msg.oppModel, rounds = msg.rounds, tape = msg.tape, kind = msg.kind,
		spar = msg.spar, venue = msg.venue, venueName = msg.venueName, weighIn = msg.weighIn, notes = msg.notes, talk = msg.talk, myLine = msg.myLine }
	player:SetAttribute("InFight", true)
	gui.Enabled = true
	L.frame.Visible, R.frame.Visible, clock.Visible, controls.Visible = false, false, false, false
	if F.arena then
		local center = F.arena:FindFirstChild("Anchors") and F.arena.Anchors:FindFirstChild("RingCenter")
		F.center = center and center.Position
	end
	L.name.Text = msg.tape.you.name
	R.name.Text = msg.tape.opp.name
	local stakes = {}
	for _, s in ipairs(msg.stakes or {}) do
		table.insert(stakes, s)
	end
	for _, s in ipairs(msg.playerStakes or {}) do
		if not table.find(stakes, s) then
			table.insert(stakes, s)
		end
	end
	if F.spar then
		bugText.Text = "SPARRING  -  " .. string.upper(F.spar)
		bug.BackgroundColor3 = T.blue
		F.stakesText = string.format("SPARRING (%s) vs %s", string.upper(F.spar), msg.tape.opp.name)
	else
		bugText.Text = "LIVE  -  WCB SPORTS"
		bug.BackgroundColor3 = T.red
		F.stakesText = #stakes > 0 and (table.concat(stakes, " - ") .. " WORLD TITLE" .. (#stakes > 1 and "S" or "") .. " ON THE LINE") or msg.kind:upper()
	end
	setTicker(string.format("%s vs %s  -  %d ROUND%s  -  %s%s", msg.tape.you.name:upper(), msg.tape.opp.name:upper(), msg.rounds, msg.rounds > 1 and "S" or "", F.stakesText,
		(msg.venueName and msg.venueName ~= "" and not F.spar) and ("  -  LIVE FROM THE " .. msg.venueName:upper()) or ""))
	screens(msg.tape.you.name:upper() .. "\nvs\n" .. msg.tape.opp.name:upper())
	setVenueLighting(F.spar and "Gym" or msg.venue)
	startVenueFx(F.arena)
	startCamera()
	camMode = F.spar and "wide" or "entrance"
	buildTouch()
end

function handlers.entrance(msg)
	if msg.phase == "opp" then
		camMode = "entrance"
		camTarget = F.opp
		showBanner("INTRODUCING...", T.blue, 2.5)
		setTicker("Making the walk to the ring: " .. ((F.tape.opp.nick or "") ~= "" and ("\"" .. F.tape.opp.nick .. "\" ") or "") .. F.tape.opp.name)
		cheer(0.6)
		if msg.pyro then
			pyro("blue")
		end
	else
		camMode = "entrance"
		camTarget = player.Character
		showBanner("YOUR WALKOUT", T.red, 2.5)
		setTicker((msg.intro or "And now...") .. "  " .. F.tape.you.name:upper() .. " \"" .. (F.tape.you.nick or "") .. "\"!")
		cheer(1.2)
		if msg.pyro then
			pyro("red")
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and msg.target then
			hum.WalkSpeed = 10
			hum:MoveTo(msg.target)
		end
		if msg.music and msg.music ~= "" then
			music = Instance.new("Sound")
			music.SoundId = "rbxassetid://" .. msg.music
			music.Volume = 0.8
			music.Parent = SoundService
			music:Play()
		end
	end
end

function handlers.tape()
	camMode = "tape"
	local y, o = F.tape.you, F.tape.opp
	local function r(x)
		return string.format("%d-%d-%d (%d KO)", x.record.w, x.record.l, x.record.d, x.record.ko)
	end
	local lines = {
		{ "TALE OF THE TAPE", bold = true, size = 24, color = T.gold },
		{ F.stakesText, bold = true, size = 14, color = T.red },
		{ string.format("%s  vs  %s", y.name:upper(), o.name:upper()), bold = true, size = 21 },
		{ string.format("\"%s\"   -   \"%s\"", y.nick or "", o.nick or ""), color = T.sub },
		{ string.format("%s   RECORD   %s", r(y), r(o)) },
		{ string.format("%s   HEIGHT   %s", Config.HeightText(y.height), Config.HeightText(o.height)) },
		{ string.format("%d in   REACH   %d in", y.reach, o.reach) },
		{ string.format("%s   STYLE   %s", y.style, o.style) },
		{ string.format("%s   FROM   %s", y.nat, o.nat) },
		{ string.format("%d   OVERALL   %d", y.overall, o.overall), bold = true },
	}
	if o.archetype then
		table.insert(lines, { "Scouting report: " .. o.archetype, color = T.sub, size = 14 })
	end
	local wi = F.weighIn
	if wi then
		if wi.over > 0 then
			table.insert(lines, { string.format("WEIGH-IN: %.1f lbs (limit %d) - MISSED WEIGHT by %.1f lbs: stamina -%d%%%s", wi.weight, wi.limit, wi.over, math.floor(wi.penalty * 100), wi.fine > 0 and ", fined 20% of your purse" or ""), color = T.red, size = 14, bold = true })
		else
			table.insert(lines, { string.format("WEIGH-IN: %.1f lbs (limit %d) - MADE WEIGHT", wi.weight, wi.limit), color = T.green, size = 14 })
		end
	end
	if F.notes and #F.notes > 0 then
		table.insert(lines, { "Your condition: " .. table.concat(F.notes, ", "), color = T.orange, size = 13 })
	end
	if F.talk and F.talk ~= "" then
		table.insert(lines, { "\"" .. F.talk .. "\"  - " .. o.name, color = Color3.fromRGB(255, 160, 160), size = 14 })
	end
	if F.myLine and F.myLine ~= "" then
		table.insert(lines, { "\"" .. F.myLine .. "\"  - " .. y.name, color = Color3.fromRGB(160, 200, 255), size = 14 })
	end
	overlayLines(lines)
	stopMusic()
end

function handlers.round(msg)
	overlay.Visible = false
	setAnimate(false)
	F.active = true
	camMode = "fight"
	L.frame.Visible, R.frame.Visible, clock.Visible, controls.Visible = true, true, true, true
	roundText.Text = string.format("ROUND %d / %d", msg.n, msg.total)
	timeText.Text = fmtTime(F.spar and Config.SparRoundSeconds or Config.RoundSeconds)
	showBanner("ROUND " .. msg.n, T.gold, 1.8)
	screens("ROUND " .. msg.n)
	cheer(0.5)
end

function handlers.state(msg)
	timeText.Text = fmtTime(msg.time)
	local function apply(panel, s)
		panel.setHp(s.hp / 100, s.hurt and T.red or T.green)
		panel.setBody(s.body / 100)
		panel.setStam(s.stam / s.max)
	end
	apply(L, msg.me)
	apply(R, msg.opp)
	angleTag.Visible = msg.me.angle == true
end

function handlers.hit(msg)
	local mine = msg.who == "you"
	local target = mine and F.opp or player.Character
	local part = target and target:FindFirstChild(msg.body and "UpperTorso" or "Head")
	sfx(part, (msg.body and 1.0 or 1.25) + math.random() * 0.15 - (msg.heavy and 0.2 or 0), math.clamp(0.35 + (msg.dmg or 3) / 12, 0.35, 1))
	if msg.heavy then
		cheer(0.5)
		if not mine then
			shake = 0.6
		end
	end
	local text = (msg.counter and "COUNTER " or "") .. (PUNCH_NAME[msg.punch] or msg.punch:upper()) .. (msg.body and " TO THE BODY" or "")
	if msg.heavy or msg.counter then
		showFlash(flash, text .. "!", mine and T.gold or T.red)
	end
	if not mine then
		shake = math.max(shake, 0.25)
	end
end

function handlers.blocked(msg)
	local target = msg.who == "you" and player.Character or F.opp
	sfx(target and target:FindFirstChild("LeftHand"), 1.9, 0.25)
	if msg.who == "you" then
		showFlash(flash, "BLOCKED", T.blue, 0.5)
	end
end

local DEF_TEXT = { SLIPPED = "SLIPPED", ["ROLLED UNDER"] = "ROLLED UNDER", PARRIED = "PARRIED", PIVOT = "PIVOTED OFF" }
function handlers.defense(msg)
	local mine = msg.who == "you"
	if mine then
		showFlash(defFlash, (DEF_TEXT[msg.move] or msg.move) .. "! COUNTER NOW!", T.gold, 0.8)
	else
		showFlash(defFlash, "OPPONENT " .. (DEF_TEXT[msg.move] or msg.move), T.sub, 0.6)
	end
end

function handlers.miss(msg)
	if msg.who == "you" and msg.why == "short" then
		showFlash(flash, "OUT OF RANGE", T.sub, 0.5)
	end
end

function handlers.comment(msg)
	setTicker(msg.text)
end

function handlers.announce(msg)
	setTicker(msg.text)
	showFlash(flash, msg.text, T.gold, 1.2)
end

function handlers.kd(msg)
	local target = msg.who == "you" and player.Character or F.opp
	sfx(target and target:FindFirstChild("HumanoidRootPart"), 0.7, 1, "rbxasset://sounds/action_falling.ogg")
	cheer(1.6)
	shake = 1
	sweeping = 3
	camMode = "wide"
	showBanner(msg.who == "you" and "YOU'RE DOWN!" or "DOWN GOES " .. F.tape.opp.name:upper() .. "!", msg.who == "you" and T.red or T.gold, 2.5)
	screens("KNOCKDOWN!")
	if msg.who == "you" then
		F.down = true
		F.mash = 0
	end
end

function handlers.getupStart(msg)
	F.target = msg.target
	F.mash = 0
	setGetup(0)
	getup.Visible = true
end

function handlers.count(msg)
	showBanner(tostring(msg.n), Color3.new(1, 1, 1), 0.8)
	if msg.who == "you" then
		setGetup((msg.mash or F.mash) / math.max(1, msg.target or F.target))
	end
end

function handlers.getup(msg)
	F.down = false
	getup.Visible = false
	camMode = "fight"
	cheer(0.8)
	setTicker(msg.who == "you" and "You beat the count!" or (F.tape.opp.name .. " beats the count!"))
end

function handlers.bell(msg)
	F.active = false
	showBanner("DING DING DING", T.gold, 1.5)
	setTicker("End of round " .. msg.n)
end

function handlers.rest(msg)
	camMode = "wide"
	local lines = {
		{ "YOUR CORNER  -  END OF ROUND " .. msg.n, bold = true, size = 22, color = T.gold },
		{ string.format("Unofficial card: %d - %d   (this round %d-%d)", msg.unofficial[1], msg.unofficial[2], msg.card[1], msg.card[2]), bold = true },
		{ string.format("Punches: you %d/%d   opponent %d/%d", msg.stats.landed, msg.stats.thrown, msg.stats.oppLanded, msg.stats.oppThrown), color = T.sub },
	}
	for _, a in ipairs(msg.advice) do
		table.insert(lines, { "\"" .. a .. "\"", left = true })
	end
	overlayLines(lines)
end

function handlers.final(msg)
	F.active = false
	F.down = false
	getup.Visible = false
	local res = msg.result
	local text
	if res.method == "KO" or res.method == "TKO" or res.method == "RTD" then
		text = res.method .. "!"
	elseif F.spar then
		text = "TIME!"
	else
		text = "THE JUDGES' DECISION..."
	end
	camMode = "wide"
	sweeping = 4
	showBanner(text, res.outcome == "win" and T.gold or T.red, 3)
	screens(res.outcome == "win" and ("WINNER\n" .. F.tape.you.name:upper()) or (res.outcome == "loss" and ("WINNER\n" .. F.tape.opp.name:upper()) or "DRAW"))
	cheer(1.6)
end

function handlers.result()
	finish()
end

function handlers.sparResult()
	finish()
end

function handlers.aborted()
	finish()
end

FightRemote.OnClientEvent:Connect(function(msg)
	local h = handlers[msg.t]
	if h then
		local ok, err = pcall(h, msg)
		if not ok then
			warn("[FightClient]", msg.t, err)
		end
	end
end)

player.CharacterAdded:Connect(function()
	if F.active or gui.Enabled then
		finish()
	end
end)
