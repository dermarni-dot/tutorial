-- Ceremony: the celebration cutscene in the ring after a won tournament final or a new title (10.5 s, skippable).
-- The server owns it (FightEngine's Fight:Ceremony: places the winner, the referee and an official, sets their
-- poses on Shared.Tournaments.Ceremony's beats, sends t = "ceremony" once and t = "ceremonyEnd" at the end); this
-- module is the viewer's side:
--   * the camera (FightClient's own camera loop stands aside while the local player's "Ceremony" attribute is set):
--     the winner close-up as the referee raises his hand, an orbit while the official straps the belt on, a low
--     hero shot as he lifts it overhead, the crowd wide shot over his shoulder
--   * the belt: carried in by the official (between his hands), round the winner's waist from the strap beat,
--     between his hands overhead from the lift (BeltModel: client-local parts, placed every frame)
--   * confetti and streamers over the ring, spotlights on the winner, pyro / spark bursts from the posts at the
--     High graphics level (Perf), the crowd's cheer and the big screens (VenueFX hooks, when the venue has them)
--   * the announcer's banner in the WCB style ("AND THE NEW..." / the title / the name), a letterbox, SKIP
--     (touch / click, Space / Enter, a gamepad's B or A): the server is told (t = "ceremonySkip") and the camera is
--     handed back at once
-- Everything it makes is local and goes away at the end; the camera and the controls are given back (FightClient's
-- loop resumes, its finish() puts the town camera back).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local Config = require(Shared:WaitForChild("Config"))
local Tournaments = require(Shared:WaitForChild("Tournaments"))
local BeltModel = require(Shared:WaitForChild("BeltModel"))
local State = require(script.Parent:WaitForChild("State"))
local T = UI.Theme

local function optional(name)
	local ok, mod = pcall(function()
		return require(script.Parent:WaitForChild(name, 5))
	end)
	return ok and type(mod) == "table" and mod or nil
end
-- the poses (installed into AnimGym's table on require), the belt badge, graphics level, the venue's crowd
local AnimCeremony = optional("AnimCeremony")
local TourneyUI = optional("TourneyUI")
local Perf = optional("Perf")
local VenueFX -- resolved when a scene starts (FightClient started it for the venue)

local Ceremony = {}
local V3 = Vector3.new
local CF = CFrame.new
local UP = Vector3.yAxis

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function vfx(name, ...)
	if VenueFX == nil then
		VenueFX = optional("VenueFX") or false
	end
	local fn = VenueFX and VenueFX[name]
	if type(fn) == "function" then
		local ok, r = pcall(fn, ...)
		return ok and r or nil
	end
	return nil
end

local function level()
	local ok, l = pcall(function()
		return Perf and Perf.Level() or 2
	end)
	return ok and tonumber(l) or 2
end

------------------------------------------------------------------------
-- The banner (WCB style): the kicker, the title in the display face with the gold ramp, the name, the event
------------------------------------------------------------------------
local function buildGui(spec)
	local sg = UI.New("ScreenGui", { Name = "CeremonyUI", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 32,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	local root = UI.MountRoot(sg, "Root")
	local canvas = UI.CanvasSize(root)
	local short = canvas.Y < 560
	local ui = { sg = sg, root = root }
	-- the letterbox (decorative: slides in from the edges)
	local barH = short and 0.07 or 0.09
	ui.top = UI.Frame(root, { Name = "LetterTop", BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, barH, 0), Position = UDim2.fromScale(0, -barH) })
	ui.bottom = UI.Frame(root, { Name = "LetterBottom", BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, barH, 0), Position = UDim2.fromScale(0, 1) })
	UI.Tween(ui.top, { Position = UDim2.fromScale(0, 0) }, TweenInfo.new(0.5, Enum.EasingStyle.Quad))
	UI.Tween(ui.bottom, { Position = UDim2.fromScale(0, 1 - barH) }, TweenInfo.new(0.5, Enum.EasingStyle.Quad))
	-- the banner: a glass band in the lower third
	local w = math.min(short and 640 or 860, canvas.X - 40)
	local h = short and 112 or 150
	local band = UI.Frame(root, { Name = "Banner", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1 - barH, -10), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = T.bg, BackgroundTransparency = 1 })
	UI.Glass(band, { transparency = 0.12, radius = UI.R.lg })
	ui.band = band
	local stripe = UI.Frame(band, { Name = "Stripe", Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = T.gold })
	UI.Gradient(stripe, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) }))
	local iconW = 0
	if TourneyUI and TourneyUI.BeltIcon then
		local bs = short and 76 or 104
		local okI, icon = pcall(TourneyUI.BeltIcon, band, spec.belt, bs, { Name = "BeltIcon", Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
		if okI and icon then
			iconW = bs + 22
		end
	end
	local x = 14 + iconW
	local tw = w - x - 14
	ui.kicker = UI.Text(band, spec.kicker or "AND THE NEW...", { Name = "Kicker", Face = "displayMed", TextSize = short and 15 or 19, TextColor3 = T.gold, Position = UDim2.fromOffset(x, short and 8 or 12),
		Size = UDim2.fromOffset(tw, short and 18 or 24), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTransparency = 1 })
	ui.title = UI.Title(band, string.upper(spec.title or "CHAMPION"), { Name = "Title", TextSize = short and 30 or 42, Position = UDim2.fromOffset(x, short and 26 or 36),
		Size = UDim2.fromOffset(tw, short and 34 or 48), AutomaticSize = Enum.AutomaticSize.None, TextScaled = true, TextTransparency = 1 })
	UI.New("UITextSizeConstraint", { MaxTextSize = short and 30 or 42, MinTextSize = 14, Parent = ui.title })
	UI.GoldText(ui.title)
	ui.name = UI.Text(band, string.upper(spec.name or ""), { Name = "WinnerName", Face = "displayMed", TextSize = short and 18 or 24, TextColor3 = T.text, Position = UDim2.fromOffset(x, short and 62 or 86),
		Size = UDim2.fromOffset(tw, short and 22 or 30), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextScaled = true, TextTransparency = 1 })
	UI.New("UITextSizeConstraint", { MaxTextSize = short and 18 or 24, MinTextSize = 12, Parent = ui.name })
	ui.event = UI.Text(band, string.upper(spec.event or ""), { Name = "Event", Font = T.semi, TextSize = 12, TextColor3 = T.sub, Position = UDim2.fromOffset(x, short and 86 or 118),
		Size = UDim2.fromOffset(tw, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextTransparency = 1 })
	-- SKIP: top right, under the letterbox's edge (finger-sized on touch)
	local sh = math.max(40, UI.MinHit(root))
	ui.skip = UI.Button(root, "SKIP", { Name = "Skip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 12), Size = UDim2.fromOffset(math.max(120, sh * 2.4), sh),
		BackgroundColor3 = T.panel2, TextSize = 16, icon = UI.HasIcon("play") and "play" or nil })
	local hint = UI.Text(ui.skip, "", { Name = "Hint", Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 1, 4),
		Size = UDim2.fromOffset(160, 14), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	UI.BindHint(hint, UI.KeyHint("SPACE", Enum.KeyCode.ButtonB, "TAP"))
	return ui
end

local function fadeIn(obj, delay)
	task.delay(delay or 0, function()
		if obj and obj.Parent then
			UI.Tween(obj, { TextTransparency = 0 }, TweenInfo.new(0.35, Enum.EasingStyle.Quad))
		end
	end)
end

------------------------------------------------------------------------
-- Effects (local parts in a folder of their own)
------------------------------------------------------------------------
local CONFETTI = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 212, 92)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 40, 52)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 130, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 212, 92)),
})

local function holder(folder, name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p.Parent = folder
	return p
end

local function confetti(folder, center, lv)
	local sky = holder(folder, "Confetti", V3(16, 0.5, 16), CF(center + UP * 17))
	local c = Instance.new("ParticleEmitter")
	c.Name = "Confetti"
	c.Enabled = false
	c.EmissionDirection = Enum.NormalId.Bottom
	c.Color = CONFETTI
	c.Size = NumberSequence.new(0.22)
	c.Lifetime = NumberRange.new(5, 7)
	c.Speed = NumberRange.new(1, 4)
	c.SpreadAngle = Vector2.new(35, 35)
	c.Acceleration = V3(0, -5, 0)
	c.Drag = 0.6
	c.Rotation = NumberRange.new(0, 360)
	c.RotSpeed = NumberRange.new(-260, 260)
	c.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	c.LightEmission = 0.25
	c.Rate = lv >= 3 and 140 or (lv >= 2 and 80 or 40)
	c.Parent = sky
	local s = Instance.new("ParticleEmitter")
	s.Name = "Streamers"
	s.Enabled = false
	s.EmissionDirection = Enum.NormalId.Bottom
	s.Color = ColorSequence.new(Color3.fromRGB(255, 212, 92), Color3.fromRGB(255, 255, 255))
	s.Size = NumberSequence.new(0.16)
	s.Squash = NumberSequence.new(-2.6)
	s.Lifetime = NumberRange.new(6, 8)
	s.Speed = NumberRange.new(0.5, 2)
	s.Acceleration = V3(0, -3.2, 0)
	s.Drag = 0.4
	s.Rotation = NumberRange.new(-30, 30)
	s.RotSpeed = NumberRange.new(-90, 90)
	s.LightEmission = 0.35
	s.Rate = lv >= 3 and 30 or (lv >= 2 and 16 or 6)
	s.Parent = sky
	return c, s
end

local function sparks(folder, posts, lv)
	local list = {}
	if lv < 3 then
		return list
	end
	for i, pos in ipairs(posts) do
		local p = holder(folder, "Pyro" .. i, V3(0.6, 0.6, 0.6), CF(pos))
		local e = Instance.new("ParticleEmitter")
		e.Enabled = false
		e.EmissionDirection = Enum.NormalId.Top
		e.Color = ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(255, 140, 40))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(26, 40)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Acceleration = V3(0, -40, 0)
		e.LightEmission = 1
		e.Squash = NumberSequence.new(-1.5)
		e.Parent = p
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 80)
		light.Range = 18
		light.Brightness = 0
		light.Parent = p
		table.insert(list, { e = e, light = light })
	end
	return list
end

local function burst(list, n)
	for _, s in ipairs(list) do
		s.e:Emit(n)
		s.light.Brightness = 4
		TweenService:Create(s.light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	end
end

local function spotlights(folder, center, lv)
	local out = {}
	local n = lv >= 2 and 3 or 1
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2
		local p = holder(folder, "Spot" .. i, V3(0.5, 0.5, 0.5), CF(center + V3(math.cos(a) * 9, 26, math.sin(a) * 9)))
		local s = Instance.new("SpotLight")
		s.Face = Enum.NormalId.Front
		s.Angle = 22
		s.Range = 40
		s.Brightness = 6
		s.Color = i == 1 and Color3.fromRGB(255, 244, 220) or Color3.fromRGB(255, 220, 150)
		s.Shadows = lv >= 3 and i == 1
		s.Parent = p
		table.insert(out, { part = p, base = p.Position, a = a })
	end
	return out
end

------------------------------------------------------------------------
-- The scene
------------------------------------------------------------------------
local active -- the running scene (one at a time)

local function partOf(model, name)
	local p = model and model.Parent and model:FindFirstChild(name)
	return p and p:IsA("BasePart") and p or nil
end

local function finish(scene, skipped)
	if not scene or scene.done then
		return
	end
	scene.done = true
	if active == scene then
		active = nil
	end
	if skipped and not scene.serverEnded then
		pcall(function()
			State.FightRemote:FireServer({ t = "ceremonySkip" })
		end)
	end
	if scene.conn then
		scene.conn:Disconnect()
	end
	pcall(ContextActionService.UnbindAction, ContextActionService, "CeremonySkip")
	for _, c in ipairs(scene.conns) do
		c:Disconnect()
	end
	if scene.folder then
		scene.folder:Destroy()
	end
	if scene.ui and scene.ui.sg then
		scene.ui.sg:Destroy()
	end
	local cam = workspace.CurrentCamera
	if cam and scene.fov then
		cam.FieldOfView = scene.fov
	end
	-- the fight HUD comes back as it was; FightClient's camera loop takes over again (its finish() puts the
	-- town camera back), and outside a fight the camera is handed straight back
	local fightUI = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("FightUI")
	if fightUI and scene.fightUIEnabled ~= nil then
		fightUI.Enabled = scene.fightUIEnabled
	end
	player:SetAttribute("Ceremony", nil)
	if cam and player:GetAttribute("InFight") ~= true then
		cam.CameraType = Enum.CameraType.Custom
	end
end
Ceremony.Finish = function(skipped)
	finish(active, skipped)
end

function Ceremony.Play(msg)
	if active then
		finish(active, false)
	end
	local spec = type(msg.spec) == "table" and msg.spec or {}
	local B = type(msg.beats) == "table" and msg.beats or Tournaments.Ceremony
	local winner = typeof(msg.winner) == "Instance" and msg.winner or player.Character
	local center = typeof(msg.center) == "Vector3" and msg.center or (partOf(winner, "HumanoidRootPart") and winner.HumanoidRootPart.Position or Vector3.zero)
	local face = typeof(msg.face) == "Vector3" and msg.face.Magnitude > 0.1 and msg.face.Unit or V3(0, 0, -1)
	local right = face:Cross(UP)
	local lv = level()
	local scene = { t0 = os.clock(), conns = {}, spec = spec, B = B, winner = winner, official = typeof(msg.official) == "Instance" and msg.official or nil }
	active = scene
	if AnimCeremony and AnimCeremony.Install then
		pcall(AnimCeremony.Install)
	end
	player:SetAttribute("Ceremony", true)
	local cam = workspace.CurrentCamera
	scene.fov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	local fightUI = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("FightUI")
	if fightUI then
		scene.fightUIEnabled = fightUI.Enabled
		fightUI.Enabled = false
	end
	-- local effects and belts
	local folder = Instance.new("Folder")
	folder.Name = "CeremonyFX"
	folder.Parent = workspace
	scene.folder = folder
	local design = Tournaments.Design(spec.belt, Config.Orgs) or Tournaments.Design("world")
	local held = BeltModel.Build(design, { mode = "display", scale = 0.42, name = "CeremonyBeltHeld" })
	held.Parent = folder
	local waist = partOf(winner, "LowerTorso")
	local worn = BeltModel.Build(design, { mode = "worn", waist = waist and waist.Size or nil, name = "CeremonyBeltWorn" })
	scene.held, scene.worn = held, worn
	local ok, conf, streamers = pcall(confetti, folder, center, lv)
	if not ok then
		conf, streamers = nil, nil
	end
	local half = 11
	local posts = {}
	for _, d in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		local dir = (face * d[1] + right * d[2]).Unit
		table.insert(posts, center + dir * half * 1.35 + UP * 5.5)
	end
	local pyro = sparks(folder, posts, lv)
	local spots = spotlights(folder, center, lv)
	-- the banner
	local okUI, ui = pcall(buildGui, spec)
	scene.ui = okUI and ui or nil
	if scene.ui then
		fadeIn(ui.kicker, 0.35)
		fadeIn(ui.title, 1.3)
		fadeIn(ui.name, 1.9)
		fadeIn(ui.event, 2.3)
		ui.skip.MouseButton1Click:Connect(function()
			finish(scene, true)
		end)
	end
	ContextActionService:BindActionAtPriority("CeremonySkip", function(_, st)
		if st == Enum.UserInputState.Begin then
			finish(scene, true)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonA)
	-- the beats this side times (the server's poses run on the same clock)
	local fired = {}
	local function once(key, t, fn)
		if not fired[key] and t >= 0 then
			fired[key] = true
			pcall(fn)
		end
	end
	vfx("Cheer", 1)
	vfx("Screens", string.upper(spec.title or "CHAMPION") .. "\n" .. string.upper(spec.name or ""))
	scene.conn = RunService.RenderStepped:Connect(function()
		if scene.done then
			return
		end
		local t = os.clock() - scene.t0
		if t > B.dur + 2 then
			-- (the server's end never came: hand the camera back anyway)
			finish(scene, false)
			return
		end
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local root = partOf(winner, "HumanoidRootPart")
		local head = partOf(winner, "Head")
		local wp = root and root.Position or center + UP * 3
		local hp = head and head.Position or wp + UP * 1.6
		-- beats
		once("raise", t - B.raise, function()
			vfx("Cheer", 1)
		end)
		once("strap", t - (B.strap + 0.5), function()
			vfx("Cheer", 1)
			burst(pyro, 40)
		end)
		once("lift", t - B.lift, function()
			vfx("Cheer", 1)
			if conf then
				conf:Emit(lv >= 3 and 260 or 140)
				conf.Enabled = true
			end
			burst(pyro, 60)
			if lv >= 3 then
				vfx("Pyro", "red")
				vfx("Pyro", "blue")
			end
		end)
		once("wide", t - B.wide, function()
			vfx("Cheer", 1)
			if streamers then
				streamers:Emit(lv >= 3 and 60 or 30)
				streamers.Enabled = true
			end
			burst(pyro, 80)
		end)
		-- the belt: with the official, round the waist, overhead
		local off = scene.official
		if t < B.strap + 0.5 then
			worn.Parent = nil
			local lh, rh = partOf(off, "LeftHand"), partOf(off, "RightHand")
			if lh and rh then
				local mid = (lh.Position + rh.Position) / 2
				local froot = partOf(off, "HumanoidRootPart")
				local look = froot and froot.CFrame.LookVector or -face
				held:PivotTo(CFrame.lookAt(mid + look * 0.25 - UP * 0.15, mid + look * 2) * CFrame.Angles(0, math.pi, 0))
				held.Parent = folder
			else
				held.Parent = nil
			end
		elseif t < B.lift then
			held.Parent = nil
			local lt = partOf(winner, "LowerTorso")
			if lt then
				worn:PivotTo(lt.CFrame * CF(0, 0.05, 0))
				worn.Parent = folder
			end
		else
			worn.Parent = nil
			local lh, rh = partOf(winner, "LeftHand"), partOf(winner, "RightHand")
			if lh and rh then
				local mid = (lh.Position + rh.Position) / 2 + UP * 0.2
				local across = rh.Position - lh.Position
				across = Vector3.new(across.X, 0, across.Z)
				across = across.Magnitude > 0.1 and across.Unit or right
				held:PivotTo(CFrame.fromMatrix(mid, across, UP))
				held.Parent = folder
			end
		end
		-- spotlights follow him (they sweep the crowd in the wide shot)
		for i, s in ipairs(spots) do
			local aim = wp
			if t >= B.wide and i > 1 then
				local a = s.a + t * 0.9
				aim = center + V3(math.cos(a) * 30, -2, math.sin(a) * 30)
			end
			s.part.CFrame = CFrame.lookAt(s.base, aim)
		end
		-- the camera: four shots, hard cuts between them
		local goal, fov
		if t < B.walkIn then
			local k = smooth(t / B.walkIn)
			local from = hp + face * (4.4 - 1.3 * k) + right * (1.1 - 0.4 * k) + UP * 0.15
			goal = CFrame.lookAt(from, hp - UP * (0.35 + 0.4 * (1 - k)))
			fov = 50
		elseif t < B.lift then
			local k = (t - B.walkIn) / (B.lift - B.walkIn)
			local a = math.rad(25 + 190 * smooth(k))
			local dir = (face * math.cos(a) + right * math.sin(a))
			local from = center + dir * 10.5 + UP * (4.6 + 1.2 * math.sin(k * math.pi))
			goal = CFrame.lookAt(from, wp + UP * 0.2)
			fov = 55
		elseif t < B.wide then
			local k = smooth((t - B.lift) / (B.wide - B.lift))
			local from = wp + face * (6.8 - 1.2 * k) + right * 1.4 - UP * (1.9 - 0.5 * k)
			goal = CFrame.lookAt(from, hp + UP * 1.3)
			fov = 58
		else
			local k = smooth((t - B.wide) / math.max(0.5, B.dur - B.wide))
			local from = center - face * (8 + 7 * k) + right * (2.5 + 2 * k) + UP * (5.5 + 4 * k)
			goal = CFrame.lookAt(from, center + face * 26 + UP * (5 - 2 * k))
			fov = 66
		end
		cam.CFrame = goal
		cam.FieldOfView = fov
	end)
	-- the server's end of the scene (or the character going away) closes it
	table.insert(scene.conns, player.CharacterRemoving:Connect(function()
		finish(scene, false)
	end))
	return scene
end

local started = false
function Ceremony.Start()
	if started then
		return
	end
	started = true
	State.FightRemote.OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" then
			return
		end
		if msg.t == "ceremony" then
			local ok, err = pcall(Ceremony.Play, msg)
			if not ok then
				warn("[Ceremony]", err)
				finish(active, true)
			end
		elseif msg.t == "ceremonyEnd" then
			if active then
				active.serverEnded = true
			end
			finish(active, false)
		elseif msg.t == "result" or msg.t == "aborted" then
			finish(active, false)
		end
	end)
end

function Ceremony.IsActive()
	return active ~= nil
end

return Ceremony
