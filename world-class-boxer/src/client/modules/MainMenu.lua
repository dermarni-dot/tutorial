-- MainMenu: the title screen. Your boxer stands in the real gym in front of the ring while the camera
-- drifts on a slow dolly (key + rim lights, depth of field, a warm grade, dust in the light); the logo
-- reveals and a shine sweeps across it; a broadcast-style menu sits on the left.
--   CONTINUE / NEW CAREER   back to the gym  /  the character creator
--   CAREER      your professional fighter card (FighterCard)
--   CHARACTER   barber, locker room, physique, stats (Services / Career Hub)
--   GYM         walk into the gym (TravelPlace "gym")
--   RANKINGS    world rankings by weight class and sanctioning body (GetRankings / GetBoxer)
--   STORE       the Career Hub shop
--   SETTINGS    UI scale, screen effects, camera shake, music / sound, graphics detail (Settings)
-- Shown at join (Settings.menuAtStart) and from the HUD (MENU, key M). Keyboard / gamepad: up / down,
-- Enter / A to select, Backspace / B to go back.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local Modules = script.Parent
local State = require(Modules:WaitForChild("State"))
local Settings = require(Modules:WaitForChild("Settings"))
local Flags = require(Modules:WaitForChild("Flags"))
local FighterCard = require(Modules:WaitForChild("FighterCard"))
local T = UI.Theme
local K = Enum.KeyCode

local MainMenu = {}
local player = Players.LocalPlayer

local gui, root
local layers = {} -- backdrop, home, screen, wipe
local view = "home"
local isOpen = false
local closing = false
local conns = {}
local items, sel = {}, 1
local itemFrames = {}
local indicator
local scene
local canvasW, canvasH = 1600, 900
local intro = true -- the logo / menu entrance plays once per open (not on a rebuild)

local function track(c)
	table.insert(conns, c)
	return c
end

local function compact()
	return canvasH < 680
end

------------------------------------------------------------------------
-- Camera scene: the boxer in the gym
------------------------------------------------------------------------
local function ringCenter()
	local gym = workspace:FindFirstChild("Gym")
	local ring = gym and gym:FindFirstChild("GymRing")
	local canvas = ring and ring:FindFirstChild("Canvas")
	if canvas and canvas:IsA("BasePart") then
		return canvas.Position
	end
	return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function light(parent, class, props)
	local l = Instance.new(class)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function sceneStart()
	local char, hum, rootPart = State.char()
	local cam = workspace.CurrentCamera
	scene = { t0 = os.clock(), parts = {}, fx = {}, mode = "home", blur = 0 }
	if not cam then
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	-- post: shallow depth of field, a warm contrasty grade, soft bloom, a blur for the sub screens
	scene.fx.dof = light(cam, "DepthOfFieldEffect", { Name = "MenuDOF", FarIntensity = 0.42, NearIntensity = 0, FocusDistance = 9, InFocusRadius = 5 })
	scene.fx.grade = light(cam, "ColorCorrectionEffect", { Name = "MenuGrade", Contrast = 0.14, Saturation = -0.06, Brightness = -0.02, TintColor = Color3.fromRGB(255, 244, 232) })
	scene.fx.bloom = light(cam, "BloomEffect", { Name = "MenuBloom", Intensity = 0.55, Size = 28, Threshold = 1.4 })
	scene.fx.blur = light(cam, "BlurEffect", { Name = "MenuBlur", Size = 0 })
	if not (char and hum and rootPart) then
		return
	end
	scene.char, scene.hum, scene.root = char, hum, rootPart
	scene.walk, scene.jump = hum.WalkSpeed, hum.JumpHeight
	hum.WalkSpeed, hum.JumpHeight = 0, 0
	State.SetAnimate(false)
	-- the Animator gives a Preview-tagged rig a proud, relaxed stance; sceneStep raises the guard now
	-- and then (Pose, client-local)
	CollectionService:AddTag(char, "Preview")
	char:SetAttribute("ExprPreview", "confident")
	scene.home = rootPart.CFrame
	-- in the gym the boxer steps onto a mark in front of the ring (it fills the background); anywhere
	-- else he stays put and the shot is framed around him
	local rc = ringCenter()
	local p = rootPart.Position
	local fromRing = rc and Vector3.new(p.X - rc.X, 0, p.Z - rc.Z) or Vector3.zero
	if rc and fromRing.Magnitude < 160 then
		local mark = rc + Vector3.new(0, 0, 28)
		rayParams.FilterDescendantsInstances = { char }
		local floor = workspace:Raycast(mark + Vector3.new(0, 12, 0), Vector3.new(0, -30, 0), rayParams)
		if floor then
			scene.facing = Vector3.new(0, 0, 1)
			local y = floor.Position.Y + hum.HipHeight + rootPart.Size.Y / 2
			local spot = Vector3.new(mark.X, y, mark.Z)
			rootPart.CFrame = CFrame.lookAt(spot, spot + scene.facing)
			rootPart.AssemblyLinearVelocity = Vector3.zero
			scene.staged = true
		end
	end
	if not scene.staged then
		local away = rc and fromRing or Vector3.zero
		if away.Magnitude > 4 then
			scene.facing = away.Unit
			rootPart.CFrame = CFrame.lookAt(p, p + scene.facing)
		else
			local lv = rootPart.CFrame.LookVector
			scene.facing = Vector3.new(lv.X, 0, lv.Z).Magnitude > 0.1 and Vector3.new(lv.X, 0, lv.Z).Unit or Vector3.new(0, 0, 1)
		end
	end
	-- key light (front-left, warm), rim light (behind, gold), cool fill near the lens
	local rig = Instance.new("Part")
	rig.Name = "MenuLightRig"
	rig.Anchored, rig.CanCollide, rig.CanQuery, rig.CanTouch, rig.CastShadow = true, false, false, false, false
	rig.Transparency = 1
	rig.Size = Vector3.new(0.2, 0.2, 0.2)
	rig.Parent = cam
	scene.parts.key = rig
	scene.key = light(rig, "SpotLight", { Brightness = 2.2, Range = 26, Angle = 48, Color = Color3.fromRGB(255, 232, 206), Face = Enum.NormalId.Front, Shadows = true })
	local rim = rig:Clone()
	rim.Name = "MenuRimRig"
	rim:ClearAllChildren()
	rim.Parent = cam
	scene.parts.rim = rim
	scene.rim = light(rim, "SpotLight", { Brightness = 4.5, Range = 22, Angle = 55, Color = Color3.fromRGB(255, 196, 120), Face = Enum.NormalId.Front })
	scene.fill = light(rig, "PointLight", { Brightness = 0.35, Range = 12, Color = Color3.fromRGB(170, 196, 255) })
end

-- camera presets per view: distance, side offset, height, how far left of the boxer the lens aims
local SHOTS = {
	home = { d = 9.2, side = 2.6, h = 1.0, aim = 2.0, fov = 38, blur = 0 },
	career = { d = 7.5, side = -2.0, h = 0.8, aim = -1.2, fov = 34, blur = 16 },
	rankings = { d = 11, side = 3.4, h = 1.6, aim = 3.0, fov = 40, blur = 18 },
	settings = { d = 10, side = 2.8, h = 1.3, aim = 2.6, fov = 40, blur = 18 },
	character = { d = 6.2, side = -1.6, h = 0.6, aim = -1.4, fov = 34, blur = 10 },
}

local function sceneStep(dt)
	local cam = workspace.CurrentCamera
	if not (scene and cam) then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local shot = SHOTS[view] or SHOTS.home
	local t = os.clock() - scene.t0
	local rootPart = scene.root
	if not (rootPart and rootPart.Parent) then
		return
	end
	-- life: every few seconds the boxer raises his guard and bounces, then relaxes again
	local guardUp = (t % 11) > 7 and not scene.relax
	if guardUp ~= scene.guard and scene.char then
		scene.guard = guardUp
		scene.char:SetAttribute("Pose", guardUp and "guard" or nil)
	end
	local p = rootPart.Position
	local f = scene.facing or Vector3.new(0, 0, 1)
	local right = f:Cross(Vector3.yAxis).Unit
	-- the slow dolly: an orbit that sways +-9 degrees, breathing in and out, plus a little handheld drift
	local sway = math.sin(t * 0.21) * 0.16
	local dir = (f * math.cos(sway) + right * math.sin(sway)).Unit
	local r2 = dir:Cross(Vector3.yAxis).Unit
	local d = shot.d + math.sin(t * 0.13) * 0.6
	local shake = Settings.Get("shake") or 1
	local hand = Vector3.new(math.sin(t * 1.3) * 0.03, math.sin(t * 0.9 + 1) * 0.025, 0) * shake
	local chest = p + Vector3.new(0, 1.3, 0)
	local want = chest + dir * d - r2 * shot.side + Vector3.new(0, shot.h + math.sin(t * 0.17) * 0.15, 0)
	-- keep a wall from cutting into the shot
	rayParams.FilterDescendantsInstances = { scene.char, cam }
	local hit = workspace:Raycast(chest, want - chest, rayParams)
	if hit then
		want = chest + (want - chest).Unit * math.max(2.5, hit.Distance - 0.6)
	end
	local aim = chest + r2 * shot.aim
	local goal = CFrame.lookAt(want, aim) * CFrame.new(hand)
	cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 2.2, 0, 1))
	cam.FieldOfView += (shot.fov - cam.FieldOfView) * math.clamp(dt * 2, 0, 1)
	-- lights ride with the shot; the rim breathes like a hanging lamp swinging a little
	if scene.parts.key then
		scene.parts.key.CFrame = CFrame.lookAt(chest + dir * 6 - r2 * 3 + Vector3.new(0, 3.2, 0), chest)
	end
	if scene.parts.rim then
		scene.parts.rim.CFrame = CFrame.lookAt(chest - dir * 5 + r2 * 2 + Vector3.new(0, 4, 0), chest)
		scene.rim.Brightness = 4 + math.sin(t * 0.7) * 0.6
	end
	if scene.fx.dof then
		scene.fx.dof.FocusDistance = (want - chest).Magnitude
	end
	if scene.fx.blur then
		scene.blur += (shot.blur - scene.blur) * math.clamp(dt * 5, 0, 1)
		scene.fx.blur.Size = scene.blur
	end
end

local function sceneStop()
	local s = scene
	scene = nil
	if not s then
		return
	end
	for _, fx in pairs(s.fx) do
		fx:Destroy()
	end
	for _, part in pairs(s.parts) do
		part:Destroy()
	end
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
	end
	local char = s.char
	if char and char.Parent then
		CollectionService:RemoveTag(char, "Preview")
		if char:GetAttribute("Pose") == "guard" then
			char:SetAttribute("Pose", nil)
		end
		char:SetAttribute("ExprPreview", nil)
		-- back to where you were standing (the mark was only for the shot)
		if s.staged and s.home and s.root and s.root.Parent and not s.keepSpot then
			s.root.CFrame = s.home
		end
	end
	if s.hum and s.hum.Parent then
		s.hum.WalkSpeed = (s.walk and s.walk > 0) and s.walk or 16
		s.hum.JumpHeight = (s.jump and s.jump > 0) and s.jump or 7.2
	end
	State.SetAnimate(true)
end

------------------------------------------------------------------------
-- Backdrop: vignettes, a drifting light leak, dust motes
------------------------------------------------------------------------
local function gradientFrame(parent, props, rot, tseq, color)
	local f = UI.Frame(parent, props)
	f.BackgroundColor3 = color or T.ink
	UI.Gradient(f, Color3.new(1, 1, 1), rot, tseq)
	return f
end

local function buildBackdrop(layer)
	-- the left third darkens for the menu, the floor darkens toward the bottom
	gradientFrame(layer, { Name = "LeftShade", Size = UDim2.new(0.7, 0, 1, 0), BackgroundTransparency = 0 }, 0,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(0.45, 0.45), NumberSequenceKeypoint.new(1, 1) }))
	gradientFrame(layer, { Name = "BottomShade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.42, 0) }, 90,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.12) }))
	gradientFrame(layer, { Name = "TopShade", Size = UDim2.new(1, 0, 0.22, 0) }, 90,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }))
	-- an elliptical vignette around the whole frame
	local vig = gradientFrame(layer, { Name = "Vignette", Size = UDim2.fromScale(1, 1) }, 0,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.62, 1), NumberSequenceKeypoint.new(1, 0.35) }))
	pcall(function()
		vig:FindFirstChildOfClass("UIGradient").Type = Enum.GradientType.Elliptical
	end)
	-- a warm light shaft drifting across the lens
	local leak = UI.Frame(layer, { Name = "LightLeak", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.68, 0.3), Size = UDim2.fromScale(0.22, 1.6), Rotation = 24,
		BackgroundColor3 = Color3.fromRGB(255, 206, 140) })
	UI.Gradient(leak, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.86), NumberSequenceKeypoint.new(1, 1) }))
	-- dust motes floating up through the light
	local dust = UI.Frame(layer, { Name = "Dust", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	local motes = {}
	local rng = Random.new(7)
	for i = 1, 34 do
		local s = rng:NextNumber(2, 5)
		local m = UI.Frame(dust, { Name = "Mote", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(s, s), BackgroundColor3 = Color3.fromRGB(255, 236, 210),
			BackgroundTransparency = rng:NextNumber(0.35, 0.85), Position = UDim2.fromScale(rng:NextNumber(0.35, 1), rng:NextNumber(0, 1)) })
		UI.Corner(m, 4)
		motes[i] = { f = m, x = m.Position.X.Scale, y = m.Position.Y.Scale, v = rng:NextNumber(0.006, 0.02), ph = rng:NextNumber(0, 6.28), amp = rng:NextNumber(0.004, 0.015) }
	end
	local t0 = os.clock()
	track(RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		for _, mo in ipairs(motes) do
			mo.y -= mo.v * dt
			if mo.y < -0.02 then
				mo.y = 1.02
			end
			mo.f.Position = UDim2.fromScale(mo.x + math.sin(t * 0.5 + mo.ph) * mo.amp, mo.y)
		end
		leak.Position = UDim2.fromScale(0.68 + math.sin(t * 0.12) * 0.06, 0.3)
		leak.BackgroundTransparency = 0.15 + math.sin(t * 0.4) * 0.1
	end))
end

------------------------------------------------------------------------
-- Logo
------------------------------------------------------------------------
local function buildLogo(layer)
	local small = compact()
	-- on short screens the logo sits below the engine's top bar buttons (no kicker line)
	local logo = UI.Frame(layer, { Name = "Logo", BackgroundTransparency = 1, Position = UDim2.fromOffset(small and 52 or 84, small and 60 or 74), Size = UDim2.fromOffset(640, small and 120 or 250) })
	local kicker = UI.Text(logo, "THE ROAD TO UNDISPUTED", { Name = "Kicker", Font = T.semi, TextSize = 15, TextColor3 = T.gold, Size = UDim2.new(1, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTransparency = 1, Visible = not small })
	local world = UI.Title(logo, "WORLD CLASS", { Name = "World", TextSize = small and 32 or 64, Position = UDim2.fromOffset(small and -2 or -16, small and 0 or 22), Size = UDim2.new(1, 0, 0, small and 36 or 70),
		TextTransparency = 1 })
	local boxerY = small and 26 or 80
	local boxerSize = small and 78 or 156
	local boxer = UI.Title(logo, "BOXER", { Name = "Boxer", TextSize = boxerSize, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(-16, boxerY), Size = UDim2.new(1, 0, 0, boxerSize + 6),
		TextTransparency = 1 })
	UI.Gradient(boxer, { Color3.fromRGB(255, 236, 170), T.gold, T.goldDeep }, 90)
	-- the shine: a white copy masked to a narrow moving band
	local shine = UI.Title(logo, "BOXER", { Name = "Shine", TextSize = boxerSize, TextColor3 = Color3.new(1, 1, 1), Position = boxer.Position, Size = boxer.Size, TextTransparency = 1, ZIndex = 2 })
	local shineGrad = UI.Gradient(shine, Color3.new(1, 1, 1), 20, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.44, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(0.56, 1), NumberSequenceKeypoint.new(1, 1),
	}), { offset = Vector2.new(-1, 0) })
	local barY = boxerY + boxerSize + (small and 0 or 6)
	local bar = UI.Frame(logo, { Name = "Bar", Position = UDim2.fromOffset(0, barY), Size = UDim2.fromOffset(0, small and 4 or 6), BackgroundColor3 = T.red })
	UI.Gradient(bar, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1) }))
	local tag = UI.Text(logo, "FROM UNKNOWN AMATEUR TO BOXING LEGEND", { Name = "Tagline", Font = T.semi, TextSize = small and 11 or 13, TextColor3 = T.sub, Position = UDim2.fromOffset(small and 128 or 200, barY - (small and 6 or 4)),
		Size = UDim2.fromOffset(420, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTransparency = 1 })
	-- reveal: kicker, WORLD CLASS slides in, BOXER punches up, the bar wipes, the shine sweeps
	local function slide(obj, dx, delay, extra)
		local goal = obj.Position
		if not intro then
			obj.TextTransparency = 0
			return
		end
		obj.Position = goal + UDim2.fromOffset(dx, 0)
		task.delay(delay, function()
			if obj.Parent then
				local props = { Position = goal, TextTransparency = 0 }
				for k, v in pairs(extra or {}) do
					props[k] = v
				end
				UI.Tween(obj, props, UI.Motion.slow)
			end
		end)
	end
	slide(kicker, -20, 0.1)
	slide(world, -40, 0.25)
	slide(boxer, -60, 0.42)
	task.delay(intro and 0.42 or 0, function()
		if shine.Parent then
			shine.TextTransparency = 0
		end
	end)
	task.delay(intro and 0.75 or 0, function()
		if bar.Parent then
			UI.Tween(bar, { Size = UDim2.fromOffset(small and 110 or 180, bar.Size.Y.Offset) }, UI.Motion.slow)
			UI.Tween(tag, { TextTransparency = 0 }, UI.Motion.slow)
		end
	end)
	task.spawn(function()
		task.wait(1.1)
		while shine.Parent do
			shineGrad.Offset = Vector2.new(-1, 0)
			UI.Tween(shineGrad, { Offset = Vector2.new(1, 0) }, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut))
			task.wait(5.5)
		end
	end)
	return logo
end

------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------
local ITEMS = {
	{ id = "continue", label = "CONTINUE", desc = "Back to the gym floor", need = "created" },
	{ id = "new", label = "NEW CAREER", desc = "Create your boxer and start as an amateur", only = "new" },
	{ id = "career", label = "CAREER", desc = "Fighter card, record, belts and rankings", need = "created" },
	{ id = "character", label = "CHARACTER", desc = "Barber, locker room, physique and stats", need = "created" },
	{ id = "gym", label = "GYM", desc = "Walk into the gym and train", need = "created" },
	{ id = "rankings", label = "RANKINGS", desc = "World rankings by division and sanctioning body", need = "created" },
	{ id = "store", label = "STORE", desc = "Gear, homes, cars and upgrades", need = "created" },
	{ id = "settings", label = "SETTINGS", desc = "Display, effects, audio and graphics" },
}

local function created()
	local P = State.P
	return P ~= nil and P.created == true and not P.retired
end

local activate -- forward
local show -- forward

local function itemMetrics()
	local small = compact()
	return small and 36 or 54, small and 2 or 4, small and 24 or 36
end

local function selectItem(i, instant)
	if #items == 0 then
		return
	end
	sel = math.clamp(i, 1, #items)
	local h, pad = itemMetrics()
	for j, fr in ipairs(itemFrames) do
		local on = j == sel
		local it = items[j]
		local locked = it.locked
		UI.Tween(fr.title, { TextTransparency = on and 0 or (locked and 0.72 or 0.32), Position = UDim2.fromOffset(on and 62 or 48, 0) }, instant and 0 or UI.Motion.base)
		fr.title.TextColor3 = on and T.white or T.text
		fr.index.TextColor3 = on and T.gold or T.dim
		UI.Tween(fr.glow, { BackgroundTransparency = on and 0 or 1 }, instant and 0 or UI.Motion.base)
		fr.desc.Visible = on
	end
	if indicator then
		local goal = UDim2.fromOffset(0, (sel - 1) * (h + pad) + math.floor(h * 0.18))
		if instant then
			indicator.Position = goal
		else
			UI.Tween(indicator, { Position = goal }, UI.Motion.base)
		end
	end
end

local function buildMenu(layer)
	local h, pad, size = itemMetrics()
	local small = compact()
	local isNew = not created()
	items = {}
	for _, it in ipairs(ITEMS) do
		if it.only == "new" then
			if isNew then
				table.insert(items, it)
			end
		elseif not (it.id == "continue" and isNew) then
			local copy = table.clone(it)
			copy.locked = it.need == "created" and isNew
			table.insert(items, copy)
		end
	end
	local top = small and 192 or 372
	local menu = UI.Frame(layer, { Name = "Menu", BackgroundTransparency = 1, Position = UDim2.fromOffset(small and 52 or 68, top), Size = UDim2.fromOffset(520, #items * (h + pad)) })
	local list = UI.Frame(menu, { Name = "Items", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	UI.List(list, pad)
	indicator = UI.Frame(menu, { Name = "Indicator", Size = UDim2.fromOffset(5, math.floor(h * 0.64)), BackgroundColor3 = T.gold, ZIndex = 3 })
	UI.Gradient(indicator, { Color3.new(1, 1, 1), Color3.fromRGB(255, 160, 80) }, 90)
	itemFrames = {}
	for i, it in ipairs(items) do
		local b = UI.New("TextButton", { Name = "Item_" .. it.id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h), LayoutOrder = i, Parent = list })
		local glow = UI.Frame(b, { Name = "Glow", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.85, 0, 1, 0), BackgroundColor3 = T.gold, BackgroundTransparency = 1 })
		UI.Gradient(glow, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(0.6, 0.96), NumberSequenceKeypoint.new(1, 1) }))
		local index = UI.Text(b, string.format("%02d", i), { Name = "Index", Face = "number", TextSize = small and 13 or 15, TextColor3 = T.dim, Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(26, h),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		local title = UI.Title(b, it.label, { Name = "Title", TextSize = size, Position = UDim2.fromOffset(48, 0), Size = UDim2.fromOffset(300, h), TextYAlignment = Enum.TextYAlignment.Center,
			TextTransparency = 1 })
		local desc = UI.Text(b, it.locked and "Create your boxer first" or it.desc, { Name = "Desc", Font = T.font, TextSize = small and 11 or 13, TextColor3 = T.sub, Position = UDim2.fromOffset(small and 210 or 270, 0),
			Size = UDim2.fromOffset(240, h), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = true, Visible = false })
		if it.locked then
			UI.Icon(b, "lock", small and 12 or 14, T.dim, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, small and 176 or 228, 0.5, 0) })
		end
		itemFrames[i] = { button = b, title = title, index = index, glow = glow, desc = desc }
		b.MouseEnter:Connect(function()
			if sel ~= i then
				selectItem(i)
			end
		end)
		b.MouseButton1Click:Connect(function()
			selectItem(i)
			activate(it)
		end)
	end
	sel = 1
	selectItem(1, true)
	if intro then
		-- staggered entrance (the selected look is restored by the tween targets)
		for i, fr in ipairs(itemFrames) do
			local it = items[i]
			local goal = fr.title.Position
			fr.title.TextTransparency = 1
			fr.title.Position = goal + UDim2.fromOffset(-30, 0)
			task.delay(0.55 + i * 0.05, function()
				if fr.title.Parent then
					UI.Tween(fr.title, { TextTransparency = (i == sel) and 0 or (it.locked and 0.72 or 0.32), Position = goal }, UI.Motion.slow)
				end
			end)
		end
	end
	return menu
end

------------------------------------------------------------------------
-- Home extras: profile plate, status chips, hints
------------------------------------------------------------------------
local function chip(parent, label, value, color, order)
	local f = UI.Frame(parent, { Name = "Status", Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.bg, BackgroundTransparency = 0.25, LayoutOrder = order })
	UI.Corner(f, UI.R.md)
	UI.Stroke(f, Color3.new(1, 1, 1), 1, 0.88)
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = f })
	UI.List(f, 8, true)
	UI.Text(f, label, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, LayoutOrder = 1 })
	UI.Text(f, value, { Face = "number", TextSize = 22, TextColor3 = color or T.text, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, LayoutOrder = 2 })
	return f
end

local function buildStatus(layer)
	local P = State.P
	if not created() then
		return
	end
	local small = compact()
	local bar = UI.Frame(layer, { Name = "StatusBar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, small and -32 or -48, 0, small and 62 or 64), Size = UDim2.fromOffset(600, 40) })
	UI.List(bar, 8, true, Enum.HorizontalAlignment.Right)
	chip(bar, "DAY", tostring(P.day or 1), T.text, 1)
	chip(bar, "PURSE", Config.Money(P.money or 0), T.gold, 2)
	local c = P.condition or {}
	chip(bar, "ENERGY", tostring(c.energy or 0), (c.energy or 100) < 25 and T.red or T.green, 3)
end

local function buildProfile(layer)
	local P = State.P
	if not created() then
		-- a new player: the call to action
		local card = UI.Frame(layer, { Name = "Welcome", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -48, 1, -64), Size = UDim2.fromOffset(440, 118), BackgroundColor3 = T.bg })
		UI.Glass(card, { transparency = 0.2 })
		UI.Kicker(card, "A NEW CAREER", T.gold, { Position = UDim2.fromOffset(22, 18), Size = UDim2.new(1, -44, 0, 18) })
		UI.Text(card, "Create your boxer and start in a beginner gym. Train, fight, climb the rankings and become undisputed.", { TextSize = 14, TextColor3 = T.text,
			Position = UDim2.fromOffset(22, 44), Size = UDim2.new(1, -44, 0, 60), AutomaticSize = Enum.AutomaticSize.None })
		return
	end
	local small = compact()
	local id = P.identity or {}
	local w, h = small and 400 or 470, small and 116 or 150
	local card = UI.Frame(layer, { Name = "Profile", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -48, 1, small and -48 or -64), Size = UDim2.fromOffset(w, h), BackgroundColor3 = T.bg })
	UI.Glass(card, { transparency = 0.18 })
	local stripe = UI.Frame(card, { Name = "Stripe", Size = UDim2.new(0, 5, 1, -24), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = T.red })
	UI.Corner(stripe, 2)
	Flags.Draw(card, id.nationality, { Size = UDim2.fromOffset(36, 24), Position = UDim2.fromOffset(22, small and 14 or 20) })
	UI.Text(card, string.upper((P.className or "") .. "  ·  " .. (P.tierName or "")), { Font = T.semi, TextSize = 12, TextColor3 = T.gold, Position = UDim2.fromOffset(68, small and 18 or 24),
		Size = UDim2.new(1, -170, 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Title(card, string.upper(id.name or ""), { TextSize = small and 30 or 38, Position = UDim2.fromOffset(22, small and 40 or 50), Size = UDim2.new(1, -150, 0, small and 34 or 42),
		TextTruncate = Enum.TextTruncate.AtEnd })
	local nick = (id.nickname and id.nickname ~= "") and ('"' .. string.upper(id.nickname) .. '"') or ""
	UI.Text(card, nick, { Face = "displayMed", TextSize = small and 15 or 18, TextColor3 = T.sub, Position = UDim2.fromOffset(22, small and 76 or 94), Size = UDim2.new(1, -150, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	-- the record and OVR on the right
	local ri = FighterCard.RecordInfo(P)
	UI.Text(card, ri.text, { Face = "number", TextSize = small and 30 or 38, TextColor3 = T.text, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, small and 14 or 20),
		Size = UDim2.fromOffset(130, small and 34 or 42), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	UI.Text(card, string.format("%d KO  ·  OVR %d", ri.ko, P.overall or 0), { Font = T.semi, TextSize = 12, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, small and 50 or 64),
		Size = UDim2.fromOffset(140, 16), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	local camp = P.camp and P.camp.offer and P.camp.offer.opp
	local next = camp and string.format("FIGHT CAMP vs %s  ·  %d day%s", string.upper(camp.name or "?"), P.camp.daysLeft or 0, (P.camp.daysLeft or 0) == 1 and "" or "s")
		or "NO FIGHT BOOKED  ·  CHECK THE FIGHT BOARD"
	if not small then
		UI.Divider(card, { Position = UDim2.new(0, 22, 1, -34), Size = UDim2.new(1, -44, 0, 1) })
		UI.Text(card, next, { Font = T.semi, TextSize = 11, TextColor3 = camp and T.red or T.dim, Position = UDim2.new(0, 22, 1, -28), Size = UDim2.new(1, -44, 0, 16),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
end

local function keycap(parent, key, label, order)
	local f = UI.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order })
	UI.List(f, 8, true)
	local cap = UI.Frame(f, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.2, LayoutOrder = 1 })
	UI.Corner(cap, 4)
	UI.Stroke(cap, Color3.new(1, 1, 1), 1, 0.8)
	local t = UI.Text(cap, key, { Font = T.semi, TextSize = 11, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	UI.Pad(t, 0, 8)
	UI.Text(f, label, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, LayoutOrder = 2 })
	return f
end

local function buildHints(layer, list)
	local small = compact()
	if small then
		return nil -- phones: no keyboard hints, and the menu needs the room
	end
	local bar = UI.Frame(layer, { Name = "Hints", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, small and 52 or 72, 1, small and -16 or -30), Size = UDim2.fromOffset(700, 26) })
	UI.List(bar, 18, true)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		keycap(bar, "TAP", "SELECT", 1)
		return bar
	end
	for i, h in ipairs(list or { { "W / S", "NAVIGATE" }, { "ENTER", "SELECT" }, { "M", "MENU" } }) do
		keycap(bar, h[1], h[2], i)
	end
	return bar
end

------------------------------------------------------------------------
-- Sub screens
------------------------------------------------------------------------
local function screenHeader(layer, kicker, title)
	local small = compact()
	-- below the engine's top bar buttons on phones
	local head = UI.Frame(layer, { Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromOffset(small and 52 or 72, small and 52 or 56), Size = UDim2.new(1, -150, 0, small and 64 or 86) })
	local back = UI.Button(head, "", { Name = "Back", Size = UDim2.fromOffset(small and 40 or 46, small and 40 or 46), Position = UDim2.fromOffset(0, small and 14 or 20), BackgroundColor3 = T.panel2,
		BackgroundTransparency = 0.25 }, function()
		show("home")
	end)
	UI.Icon(back, "left", 14, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	UI.Kicker(head, kicker, T.gold, { Position = UDim2.fromOffset(small and 56 or 66, small and 6 or 12), Size = UDim2.fromOffset(600, 18) })
	UI.Title(head, title, { TextSize = small and 38 or 52, Position = UDim2.fromOffset(small and 54 or 64, small and 22 or 30), Size = UDim2.new(1, -70, 0, small and 42 or 58) })
	return head
end

-- CAREER: the fighter card
local function screenCareer(layer)
	local P = State.P
	local small = compact()
	screenHeader(layer, "MY CAREER", "FIGHTER CARD")
	local w = math.min(1260, canvasW - (small and 104 or 144))
	local top = small and 124 or 158
	local h = math.min(640, canvasH - top - (small and 14 or 78))
	-- the photo is a snapshot: let a raised guard drop first so the face and physique show
	if scene then
		scene.relax = true
		if scene.char and scene.char:GetAttribute("Pose") == "guard" then
			scene.char:SetAttribute("Pose", nil)
			scene.guard = false
			task.wait(0.45)
			if view ~= "career" then
				return
			end
		end
	end
	local card = FighterCard.Full(layer, P, { Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(small and 52 or 72, top), compact = small })
	card.Name = "Card"
	-- actions: bottom right; on phones they sit in the header row
	local actions = UI.Frame(layer, { Name = "Actions", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, small and 0 or 1),
		Position = small and UDim2.new(1, -40, 0, 66) or UDim2.new(1, -72, 1, -28), Size = UDim2.fromOffset(760, small and 40 or 46) })
	UI.List(actions, 10, true, Enum.HorizontalAlignment.Right)
	local bh = small and 38 or 44
	UI.Button(actions, "CAREER HUB", { Size = UDim2.fromOffset(small and 150 or 200, bh), BackgroundColor3 = T.gold, LayoutOrder = 3 }, function()
		MainMenu.Close(function()
			State.open.Hub("Career")
		end)
	end)
	UI.Button(actions, "PHYSIQUE", { Size = UDim2.fromOffset(small and 120 or 160, bh), LayoutOrder = 2 }, function()
		MainMenu.Close(function()
			State.open.Hub("Body")
		end)
	end)
	UI.Button(actions, "LEGACY", { Size = UDim2.fromOffset(small and 110 or 150, bh), LayoutOrder = 1 }, function()
		MainMenu.Close(function()
			State.open.Hub("Legacy")
		end)
	end)
end

-- CHARACTER: four tiles
local TILES = {
	{ "BARBER SHOP", "Cuts, fades, colour, beards. Your hair grows out over the weeks.", function()
		State.open.Barber()
	end },
	{ "LOCKER ROOM", "Trunks, robe, boots, wraps and glove customisation.", function()
		State.open.Locker()
	end },
	{ "PHYSIQUE", "Every muscle you have built, soreness, veins - and FLEX.", function()
		State.open.Hub("Body")
	end },
	{ "STATS", "Core and mental attributes, style and specialty.", function()
		State.open.Hub("Stats")
	end },
}
local function screenCharacter(layer)
	local small = compact()
	screenHeader(layer, "MY BOXER", "CHARACTER")
	local grid = UI.Frame(layer, { Name = "Tiles", BackgroundTransparency = 1, Position = UDim2.fromOffset(small and 52 or 72, small and 110 or 180), Size = UDim2.fromOffset(small and 640 or 760, small and 300 or 420) })
	UI.Grid(grid, UDim2.new(0.5, -8, 0.5, -8), nil, 16)
	for i, t in ipairs(TILES) do
		local b = UI.Button(grid, "", { Name = "Tile", LayoutOrder = i, BackgroundColor3 = T.bg, BackgroundTransparency = 0.15 }, function()
			MainMenu.Close(t[3])
		end)
		local accent = UI.Frame(b, { Size = UDim2.new(0, 4, 1, -28), Position = UDim2.fromOffset(0, 14), BackgroundColor3 = i % 2 == 1 and T.gold or T.red })
		UI.Corner(accent, 2)
		UI.Text(b, string.format("%02d", i), { Face = "number", TextSize = 16, TextColor3 = T.dim, Position = UDim2.fromOffset(22, small and 12 or 20), Size = UDim2.fromOffset(40, 18),
			AutomaticSize = Enum.AutomaticSize.None })
		UI.Title(b, t[1], { TextSize = small and 26 or 34, Position = UDim2.fromOffset(22, small and 30 or 42), Size = UDim2.new(1, -44, 0, small and 32 or 40) })
		UI.Text(b, t[2], { TextSize = small and 12 or 14, TextColor3 = T.sub, Position = UDim2.fromOffset(22, small and 66 or 90), Size = UDim2.new(1, -44, 0, 48), AutomaticSize = Enum.AutomaticSize.None })
		UI.Icon(b, "right", 16, T.gold, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -16) })
	end
end

-- RANKINGS: division x organisation table + a scouting panel
local rankClass, rankOrg = nil, "WBA"
local function rankRow(list, e, i, onPick)
	local champ = e.rank == "C"
	local row = UI.Button(list, "", { Name = "Row", Size = UDim2.new(1, -6, 0, 50), LayoutOrder = i, BackgroundColor3 = e.isPlayer and Color3.fromRGB(58, 46, 16) or T.panel,
		BackgroundTransparency = e.isPlayer and 0.05 or (i % 2 == 0 and 0.35 or 0.15) }, function()
		onPick(e)
	end)
	if e.isPlayer then
		UI.Stroke(row, T.gold, 1.5, 0.2)
	end
	local badge = UI.Frame(row, { Name = "Rank", Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(champ and 64 or 46, 32), BackgroundColor3 = champ and T.gold or T.panel2 })
	UI.Corner(badge, 6)
	UI.Text(badge, champ and "CHAMP" or tostring(e.rank), { Face = "number", TextSize = champ and 16 or 20, TextColor3 = champ and T.ink or T.text, Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
	local x = champ and 86 or 68
	Flags.Draw(row, e.nat, { Size = UDim2.fromOffset(30, 20), Position = UDim2.fromOffset(x, 15) })
	UI.Text(row, string.upper(e.name or "?"), { Face = "displayMed", TextSize = 21, TextColor3 = e.isPlayer and T.gold or T.text, Position = UDim2.fromOffset(x + 42, 4), Size = UDim2.new(0.5, -(x + 42), 0, 26),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Text(row, (e.nick and e.nick ~= "") and ('"' .. e.nick .. '"') or "", { TextSize = 12, TextColor3 = T.sub, Position = UDim2.fromOffset(x + 42, 28), Size = UDim2.new(0.5, -(x + 42), 0, 16),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local r = e.record or {}
	UI.Text(row, string.format("%d-%d-%d", r.w or 0, r.l or 0, r.d or 0), { Face = "number", TextSize = 22, Position = UDim2.new(0.52, 0, 0, 0), Size = UDim2.new(0.18, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	UI.Text(row, string.format("%d KO", r.ko or 0), { Font = T.semi, TextSize = 12, TextColor3 = T.sub, Position = UDim2.new(0.7, 0, 0, 0), Size = UDim2.new(0.1, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	-- overall as a number + a short bar
	UI.Text(row, tostring(e.overall or 0), { Face = "number", TextSize = 22, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.fromOffset(40, 50),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	local _, set = UI.Bar(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -64, 0.5, 0), Size = UDim2.new(0.1, 0, 0, 6) }, champ and T.gold or T.blue)
	set((e.overall or 0) / 99)
	return row
end

local function scoutPanel(panel, id)
	UI.Clear(panel)
	local res = State.req("GetBoxer", id)
	if not (res and res.ok and res.boxer) then
		UI.Text(panel, "No scouting report available.", { TextColor3 = T.sub, TextSize = 14, Position = UDim2.fromOffset(20, 20), Size = UDim2.new(1, -40, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
		return
	end
	local b = res.boxer
	local body = UI.Frame(panel, { BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 20), Size = UDim2.new(1, -44, 1, -40) })
	UI.List(body, 8)
	UI.Kicker(body, "SCOUTING REPORT", T.gold, { order = 1 })
	local nameRow = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2 })
	Flags.Draw(nameRow, b.nat, { Size = UDim2.fromOffset(36, 24), Position = UDim2.fromOffset(0, 10) })
	UI.Title(nameRow, string.upper(b.name or "?"), { TextSize = 36, Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -46, 0, 44), TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Text(body, string.format('"%s"  ·  %s  ·  Age %d', b.nick or "", b.nat or "", b.age or 0), { TextSize = 14, TextColor3 = T.gold, LayoutOrder = 3 })
	local strip = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 4 })
	UI.List(strip, 8, true)
	local r = b.record or {}
	UI.Stat(strip, string.format("%d-%d-%d", r.w or 0, r.l or 0, r.d or 0), "RECORD", { Size = UDim2.new(0.38, -8, 1, 0), order = 1, valueSize = 28, scaled = true })
	UI.Stat(strip, tostring(r.ko or 0), "KOS", { Size = UDim2.new(0.22, -8, 1, 0), order = 2, valueSize = 28, valueColor = T.red })
	UI.Stat(strip, tostring(b.overall or 0), "OVERALL", { Size = UDim2.new(0.4, -8, 1, 0), order = 3, valueSize = 28, valueColor = T.gold })
	UI.Text(body, string.format("%s  ·  %s", b.style or "?", (b.archetype and b.archetype ~= "") and b.archetype or "?"), { TextSize = 14, TextColor3 = T.text, LayoutOrder = 5 })
	UI.Text(body, "Personality: " .. tostring(b.personality or "?"), { TextSize = 13, TextColor3 = T.sub, LayoutOrder = 6 })
	if b.belts and #b.belts > 0 then
		UI.Text(body, "HOLDS: " .. table.concat(b.belts, "  ·  "), { Font = T.semi, TextSize = 13, TextColor3 = T.gold, LayoutOrder = 7 })
	end
	if b.h2h and (b.h2h.w + b.h2h.l + b.h2h.d) > 0 then
		UI.Text(body, string.format("HEAD TO HEAD: you %d - %d them (%d draws)", b.h2h.w, b.h2h.l, b.h2h.d), { Font = T.semi, TextSize = 13, TextColor3 = T.red, LayoutOrder = 8 })
	end
	local stats = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 9 })
	UI.List(stats, 2)
	for i, k in ipairs(Config.StatKeys) do
		local row = UI.StatRow(stats, Config.StatNames[k], b.stats and b.stats[k] or 0, 99, T.red)
		row.LayoutOrder = i
	end
end

local function screenRankings(layer)
	local P = State.P
	local small = compact()
	rankClass = rankClass or (P and P.physical and P.physical.weightClass) or 5
	screenHeader(layer, "WORLD RANKINGS", string.upper(Config.WeightClasses[rankClass].name))
	local top = small and 100 or 156
	-- division + organisation controls
	local controls = UI.Frame(layer, { Name = "Controls", BackgroundTransparency = 1, Position = UDim2.fromOffset(small and 52 or 72, top), Size = UDim2.fromOffset(900, 40) })
	UI.List(controls, 8, true)
	local prev = UI.Button(controls, "", { Size = UDim2.fromOffset(40, 38), LayoutOrder = 1 }, function()
		rankClass = math.max(1, rankClass - 1)
		show("rankings", true)
	end)
	UI.Icon(prev, "left", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	local wc = Config.WeightClasses[rankClass]
	UI.Chip(controls, string.format("%d LBS LIMIT  ·  DIVISION %d OF %d", wc.limit, rankClass, #Config.WeightClasses), T.text, { order = 2, h = 38, TextSize = 13 })
	local nextB = UI.Button(controls, "", { Size = UDim2.fromOffset(40, 38), LayoutOrder = 3 }, function()
		rankClass = math.min(#Config.WeightClasses, rankClass + 1)
		show("rankings", true)
	end)
	UI.Icon(nextB, "right", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	UI.Frame(controls, { BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 38), LayoutOrder = 4 })
	for i, org in ipairs(Config.Orgs) do
		local on = org == rankOrg
		UI.Button(controls, org, { Size = UDim2.fromOffset(78, 38), LayoutOrder = 4 + i, BackgroundColor3 = on and T.gold or T.panel2, BackgroundTransparency = on and 0 or 0.3 }, function()
			rankOrg = org
			show("rankings", true)
		end)
	end
	local listW = small and (canvasW - 104) or math.floor((canvasW - 144) * 0.6)
	local listTop = top + 52
	local panel = UI.Frame(layer, { Name = "Table", Position = UDim2.fromOffset(small and 52 or 72, listTop), Size = UDim2.fromOffset(listW, canvasH - listTop - (small and 20 or 70)) })
	UI.Glass(panel, { transparency = 0.12 })
	-- column captions
	local cap = UI.Frame(panel, { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 18) })
	for _, c in ipairs({ { "RANK", 0, 0.1 }, { "FIGHTER", 0.12, 0.3 }, { "RECORD", 0.52, 0.18, true }, { "KO", 0.7, 0.1, true }, { "OVR", 0.86, 0.14, false, true } }) do
		UI.Text(cap, c[1], { Font = T.semi, TextSize = 10, TextColor3 = T.dim, Position = UDim2.new(c[2], 0, 0, 0), Size = UDim2.new(c[3], 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = c[4] and Enum.TextXAlignment.Center or (c[5] and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left), TextWrapped = false })
	end
	local list = UI.Scroll(panel, { Name = "List", Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 1, -40) })
	UI.List(list, 4)
	local scout
	if not small then
		scout = UI.Frame(layer, { Name = "Scout", Position = UDim2.fromOffset(72 + listW + 20, listTop), Size = UDim2.fromOffset(canvasW - 144 - listW - 20, canvasH - listTop - 70) })
		UI.Glass(scout, { transparency = 0.12 })
		UI.Text(scout, "Select a fighter to see the scouting report.", { TextColor3 = T.sub, TextSize = 14, Position = UDim2.fromOffset(22, 22), Size = UDim2.new(1, -44, 0, 40), AutomaticSize = Enum.AutomaticSize.None })
	end
	local res = State.req("GetRankings", rankClass, rankOrg)
	if not (res and res.ok) then
		UI.Text(list, res and res.err or "Rankings unavailable.", { TextColor3 = T.sub, TextSize = 14 })
		return
	end
	if P and (P.tier or 1) < 2 then
		local note = UI.Frame(list, { BackgroundColor3 = T.panel2, BackgroundTransparency = 0.4, Size = UDim2.new(1, -6, 0, 40), LayoutOrder = 0 })
		UI.Corner(note, 6)
		UI.Text(note, "You're an amateur: win 4 amateur bouts to turn pro and enter the world rankings.", { TextSize = 13, TextColor3 = T.gold, Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
	end
	-- open on the champion's scouting report (or yours, once ranked)
	local first
	for _, e in ipairs(res.list or {}) do
		if not e.isPlayer then
			first = first or e
		end
	end
	if scout and first then
		task.spawn(scoutPanel, scout, first.id)
	end
	for i, e in ipairs(res.list or {}) do
		rankRow(list, e, i, function(entry)
			if entry.isPlayer then
				show("career")
				return
			end
			if scout then
				task.spawn(scoutPanel, scout, entry.id)
			elseif State.open.BoxerCard then
				State.open.BoxerCard(entry.id)
			end
		end)
	end
end

-- SETTINGS
local function screenSettings(layer)
	local small = compact()
	screenHeader(layer, "OPTIONS", "SETTINGS")
	local top = small and 100 or 160
	local w = math.min(1100, canvasW - (small and 104 or 144))
	local panel = UI.Frame(layer, { Name = "Panel", Position = UDim2.fromOffset(small and 52 or 72, top), Size = UDim2.fromOffset(w, canvasH - top - (small and 20 or 80)) })
	UI.Glass(panel, { transparency = 0.1 })
	local body = UI.Scroll(panel, { Position = UDim2.fromOffset(24, 18), Size = UDim2.new(1, -48, 1, -36) })
	UI.List(body, 10)
	UI.Pad(body, 2, 4)
	local v = Settings.Values
	local function pct(x)
		return string.format("%d%%", math.floor(x * 100 + 0.5))
	end
	UI.Header(body, "DISPLAY")
	UI.Slider(body, "UI scale", 0.8, 1.25, v.uiScale, 0.05, function(x)
		Settings.Set("uiScale", x)
	end, pct)
	UI.Cycler(body, "Graphics detail", Settings.Details, v.detail, function(x)
		Settings.Set("detail", x)
	end, function(x)
		return x == "Auto" and "Auto (by distance and device)" or x
	end)
	UI.Header(body, "CAMERA & EFFECTS")
	UI.Slider(body, "Screen effects", 0, 1.5, v.screenFx, 0.05, function(x)
		Settings.Set("screenFx", x)
	end, pct)
	UI.Text(body, "Blur, colour drain, flashes and vignettes when you get hurt in a fight. Lower it if it gets too intense.", { TextSize = 12, TextColor3 = T.sub })
	UI.Slider(body, "Camera shake", 0, 1.5, v.shake, 0.05, function(x)
		Settings.Set("shake", x)
	end, pct)
	UI.Header(body, "AUDIO")
	UI.Slider(body, "Music", 0, 1, v.music, 0.05, function(x)
		Settings.Set("music", x)
	end, pct)
	UI.Slider(body, "Sound effects", 0, 1, v.sfx, 0.05, function(x)
		Settings.Set("sfx", x)
	end, pct)
	UI.Header(body, "GAME")
	UI.Toggle(body, "Show the main menu when I join", v.menuAtStart, function(on)
		Settings.Set("menuAtStart", on)
	end)
	UI.Button(body, "RESET TO DEFAULTS", { Size = UDim2.fromOffset(220, 40) }, function()
		for k, def in pairs(Settings.Defaults) do
			Settings.Set(k, def)
		end
		show("settings", true)
	end)
end

local SCREENS = { career = screenCareer, character = screenCharacter, rankings = screenRankings, settings = screenSettings }

------------------------------------------------------------------------
-- Building, switching, wipes
------------------------------------------------------------------------
local function measure()
	local s = root and root:GetAttribute("UIScale") or 1
	local abs = gui and gui.AbsoluteSize or Vector2.new(1600, 900)
	if abs.X < 2 then
		local cam = workspace.CurrentCamera
		abs = cam and cam.ViewportSize or Vector2.new(1600, 900)
	end
	canvasW, canvasH = abs.X / s, abs.Y / s
end

-- a fast diagonal swoosh (red with a gold edge) across the screen between two views
local function wipe()
	local layer = layers.wipe
	if not layer then
		return
	end
	local band = UI.Frame(layer, { Name = "Swoosh", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.4, 0.5), Size = UDim2.fromScale(0.34, 2.2), Rotation = 14, BackgroundColor3 = T.red })
	UI.Gradient(band, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(0.7, 0.1), NumberSequenceKeypoint.new(1, 1) }))
	UI.Frame(band, { Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = T.gold })
	UI.Tween(band, { Position = UDim2.fromScale(1.4, 0.5) }, TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut))
	task.delay(0.45, function()
		band:Destroy()
	end)
end

local function buildHome()
	local home = layers.home
	UI.Clear(home)
	buildLogo(home)
	buildMenu(home)
	buildProfile(home)
	buildStatus(home)
	buildHints(home)
end

function show(name, instant)
	if not (gui and gui.Parent) then
		return
	end
	local from = view
	view = name
	if scene then
		scene.relax = name == "career"
	end
	if name == "home" then
		layers.screen.Visible = false
		UI.Clear(layers.screen)
		layers.home.Visible = true
		if from ~= "home" then
			buildHome()
		end
		return
	end
	if not instant and from ~= name then
		wipe()
	end
	local function swap()
		if view ~= name or not (gui and gui.Parent) then
			return
		end
		layers.home.Visible = false
		UI.Clear(layers.screen)
		layers.screen.Visible = true
		local fn = SCREENS[name]
		if fn then
			local ok, err = pcall(fn, layers.screen)
			if not ok then
				warn("[MainMenu] " .. name .. ": " .. tostring(err))
			end
		end
	end
	if instant or from == name then
		swap()
	else
		task.delay(0.16, swap)
	end
end
MainMenu.Show = show

function activate(it)
	if not it then
		return
	end
	if it.locked then
		State.toast("Create your boxer first.", T.red)
		return
	end
	if it.id == "continue" then
		MainMenu.Close()
	elseif it.id == "new" then
		MainMenu.Close(function()
			if State.open.Creator then
				State.open.Creator()
			end
		end)
	elseif it.id == "gym" then
		MainMenu.Close(function()
			local r = State.req("TravelPlace", "gym")
			if not (r and r.ok) then
				State.toast((r and r.err) or "Can't go there right now.", T.red)
			end
		end)
	elseif it.id == "store" then
		MainMenu.Close(function()
			State.open.Hub("Shop")
		end)
	else
		show(it.id)
	end
end

local function onInput(input, gp)
	if gp or not isOpen or closing then
		return
	end
	local k = input.KeyCode
	if view == "home" then
		if k == K.Down or k == K.S or k == K.DPadDown then
			selectItem(sel % #items + 1)
		elseif k == K.Up or k == K.W or k == K.DPadUp then
			selectItem((sel - 2) % #items + 1)
		elseif k == K.Return or k == K.Space or k == K.ButtonA then
			activate(items[sel])
		end
	elseif k == K.Backspace or k == K.ButtonB then
		show("home")
	end
end

------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------
function MainMenu.IsOpen()
	return isOpen
end

function MainMenu.Open(which)
	if isOpen then
		if which then
			show(which)
		end
		return
	end
	local P = State.P
	if State.inFight() or State.busy() == "fight" or State.busy() == "spar" or (P and P.retired) then
		return
	end
	if State.activity then
		return
	end
	isOpen, closing = true, false
	State.closeAll("Menu")
	State.windows.Menu = function()
		MainMenu.Close()
	end
	State.HideHud("Menu", true)
	State.HidePrompts("Menu", true)
	gui = UI.New("ScreenGui", { Name = "MainMenuUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui") })
	root = UI.MountRoot(gui)
	measure()
	layers.backdrop = UI.Frame(root, { Name = "Backdrop", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	layers.home = UI.Frame(root, { Name = "Home", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	layers.screen = UI.Frame(root, { Name = "Screen", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	layers.wipe = UI.Frame(root, { Name = "Wipe", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20 })
	-- fade up from black
	local black = UI.Frame(root, { Name = "Fade", BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 30 })
	UI.Tween(black, { BackgroundTransparency = 1 }, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	task.delay(1, function()
		black:Destroy()
	end)
	buildBackdrop(layers.backdrop)
	view = "home"
	intro = true
	buildHome()
	intro = false
	if which and which ~= "home" then
		show(which, true)
	end
	sceneStart()
	track(RunService.RenderStepped:Connect(sceneStep))
	track(UserInputService.InputBegan:Connect(onInput))
	-- a new screen size (rotation, window resize, UI scale setting): rebuild in place
	track(root:GetAttributeChangedSignal("UIScale"):Connect(function()
		measure()
		if view == "home" then
			buildHome()
		else
			show(view, true)
		end
	end))
	-- the character respawned under the menu: stage the new one
	track(player.CharacterAdded:Connect(function()
		task.wait(0.5)
		if isOpen then
			sceneStop()
			sceneStart()
		end
	end))
	-- live numbers on the home screen
	track(State.Changed:Connect(function()
		if isOpen and view == "home" and not closing then
			local home = layers.home
			for _, n in ipairs({ "Profile", "StatusBar", "Welcome" }) do
				local f = home and home:FindFirstChild(n)
				if f then
					f:Destroy()
				end
			end
			buildProfile(home)
			buildStatus(home)
		end
	end))
end

function MainMenu.Close(after)
	if not isOpen or closing then
		return
	end
	closing = true
	State.windows.Menu = nil
	local g = gui
	-- a quick fade to black and back hides the camera cut
	local black = g and root and UI.Frame(root, { Name = "Fade", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30 })
	if black then
		UI.Tween(black, { BackgroundTransparency = 0 }, TweenInfo.new(0.22, Enum.EasingStyle.Quad))
	end
	task.delay(black and 0.24 or 0, function()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		table.clear(conns)
		sceneStop()
		if g then
			g:Destroy()
		end
		gui, root = nil, nil
		table.clear(layers)
		isOpen, closing = false, false
		view = "home"
		State.HidePrompts("Menu", false)
		State.HideHud("Menu", false)
		if after then
			task.spawn(after)
		end
	end)
end

function MainMenu.Toggle()
	if isOpen then
		MainMenu.Close()
	else
		MainMenu.Open()
	end
end

State.open.Menu = MainMenu.Open
State.open.Rankings = function()
	MainMenu.Open("rankings")
end
State.open.Settings = function()
	MainMenu.Open("settings")
end
State.open.Career = function()
	MainMenu.Open("career")
end
return MainMenu
