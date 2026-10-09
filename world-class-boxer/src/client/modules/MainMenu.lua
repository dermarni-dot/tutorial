-- MainMenu: the title screen. Your boxer stands in his corner of a ring in a gym at night (MenuStage: a
-- set built on this client, holding a clone of your character) while the camera drifts on a slow dolly
-- (key + rim lights, hanging lamps, a shaft of window light with dust, depth of field, a warm grade); the
-- logo reveals and a shine sweeps across it; a broadcast-style menu sits on the left.
--   CONTINUE / NEW CAREER   back to the gym  /  the character creator
--   CAREER      your professional fighter card (FighterCard)
--   CHARACTER   barber, locker room, physique, stats (Services / Career Hub)
--   GYM         walk into the gym (TravelPlace "gym")
--   RANKINGS    world rankings by weight class and sanctioning body (GetRankings / GetBoxer)
--   STORE       the Career Hub shop
--   CONTROLS    the Moves & Controls window: every move with its keys / buttons, remapping, console options
--   SETTINGS    UI scale, screen effects, camera shake, music / sound, graphics detail, controls (Settings)
-- Shown at join (Settings.menuAtStart) and from the HUD (MENU, key M). Keyboard / gamepad: up / down,
-- Enter / A to select, Backspace / B to go back.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local Modules = script.Parent
local State = require(Modules:WaitForChild("State"))
local Settings = require(Modules:WaitForChild("Settings"))
local Flags = require(Modules:WaitForChild("Flags"))
local FighterCard = require(Modules:WaitForChild("FighterCard"))
local MenuStage = require(Modules:WaitForChild("MenuStage"))
local ControlsMenu = require(Modules:WaitForChild("ControlsMenu"))
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
-- Camera scene: your boxer in the menu set (MenuStage)
------------------------------------------------------------------------
-- The set is built on this client far above the map and holds a clone of your character: your real
-- character never moves (only its controls are held while the menu is up, so W / S in the menu do not
-- walk it), nothing replicates, and no NPC, player or pillar of the real gym can get into the shot.
local function light(parent, class, props)
	local l = Instance.new(class)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function holdControls(hum)
	if scene.hum == hum then
		return
	end
	scene.hum = hum
	scene.walk, scene.jump = hum.WalkSpeed, hum.JumpHeight
	hum.WalkSpeed, hum.JumpHeight = 0, 0
end

local function releaseControls(s)
	local hum = s.hum
	if hum and hum.Parent then
		-- only undo our own hold (a server change made meanwhile stands)
		if hum.WalkSpeed == 0 then
			hum.WalkSpeed = (s.walk and s.walk > 0) and s.walk or 16
		end
		if hum.JumpHeight == 0 then
			hum.JumpHeight = (s.jump and s.jump > 0) and s.jump or 7.2
		end
	end
end

-- (re)stage the clone of the current character
local function stageBoxer()
	if not scene then
		return
	end
	local char, hum, rootPart = State.char()
	if char and hum and rootPart then
		holdControls(hum)
		-- hear the gym from where you stand, not from the set high above it
		if not scene.listener then
			scene.listener = pcall(function()
				SoundService:SetListener(Enum.ListenerType.ObjectCFrame, rootPart)
			end)
		end
		MenuStage.Place(scene.stage, char)
		scene.guard = nil
		-- a new look (barber, creator, a new career) re-stages the clone a moment later
		if scene.lookConn then
			scene.lookConn:Disconnect()
		end
		local token = 0
		scene.lookConn = char:GetAttributeChangedSignal("LookSig"):Connect(function()
			token += 1
			local mine = token
			task.delay(1, function()
				if mine == token and scene and isOpen then
					MenuStage.Place(scene.stage, char)
				end
			end)
		end)
	end
end

local function sceneStart()
	local cam = workspace.CurrentCamera
	scene = { t0 = os.clock(), fx = {}, blur = 0 }
	if not cam then
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	-- post: shallow depth of field, a warm contrasty grade, soft bloom, a blur for the sub screens
	scene.fx.dof = light(cam, "DepthOfFieldEffect", { Name = "MenuDOF", FarIntensity = 0.42, NearIntensity = 0, FocusDistance = 9, InFocusRadius = 5 })
	scene.fx.grade = light(cam, "ColorCorrectionEffect", { Name = "MenuGrade", Contrast = 0.14, Saturation = -0.06, Brightness = -0.02, TintColor = Color3.fromRGB(255, 244, 232) })
	scene.fx.bloom = light(cam, "BloomEffect", { Name = "MenuBloom", Intensity = 0.55, Size = 28, Threshold = 1.4 })
	scene.fx.blur = light(cam, "BlurEffect", { Name = "MenuBlur", Size = 0 })
	scene.stage = MenuStage.Build(Settings.Get("detail"))
	stageBoxer()
	-- the first frame sits on the shot (no swoop down from the gym)
	local cf, fov = MenuStage.Shot(scene.stage, view, 0, Settings.Get("shake") or 1)
	cam.CFrame = cf
	cam.FieldOfView = fov
end

local function sceneStep(dt)
	local cam = workspace.CurrentCamera
	local st = scene and scene.stage
	if not (st and cam) then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local t = os.clock() - scene.t0
	-- life: now and then the boxer raises his guard and bounces for a few seconds, then relaxes again
	-- (the first look at him is the relaxed, proud stance with his face in the light)
	local clone = st.clone
	local guardUp = view == "home" and t > 6 and (t % 14) > 10.5
	if clone and guardUp ~= scene.guard then
		scene.guard = guardUp
		clone:SetAttribute("Pose", guardUp and "guard" or nil)
	end
	MenuStage.Step(st, t)
	local goal, fov, focus, blur = MenuStage.Shot(st, view, t, Settings.Get("shake") or 1)
	cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 2.2, 0, 1))
	cam.FieldOfView += (fov - cam.FieldOfView) * math.clamp(dt * 2, 0, 1)
	if scene.fx.dof then
		scene.fx.dof.FocusDistance = focus
	end
	if scene.fx.blur then
		scene.blur += (blur - scene.blur) * math.clamp(dt * 5, 0, 1)
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
	if s.lookConn then
		s.lookConn:Disconnect()
	end
	MenuStage.Destroy(s.stage)
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
	end
	if s.listener then
		pcall(function()
			SoundService:SetListener(Enum.ListenerType.Camera)
		end)
	end
	releaseControls(s)
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
	{ id = "controls", label = "CONTROLS", desc = "Every move with its keys and buttons, remapping, console options" },
	{ id = "settings", label = "SETTINGS", desc = "Display, effects, audio, graphics and controls" },
}

-- the Moves & Controls window over the menu: the menu's own pad navigation steps aside while it is open
local function openControls(tabName)
	UI.PadHold("Menu", false)
	ControlsMenu.Open({ tab = tabName, onClose = function()
		if isOpen and not closing then
			UI.PadHold("Menu", true)
		end
	end })
end

local function created()
	local P = State.P
	return P ~= nil and P.created == true and not P.retired
end

local activate -- forward
local show -- forward
local openScout -- forward

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
		local small = compact()
		local card = UI.Frame(layer, { Name = "Welcome", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -48, 1, small and -48 or -64), Size = UDim2.fromOffset(440, 146), BackgroundColor3 = T.bg })
		UI.Glass(card, { transparency = 0.2 })
		UI.Frame(card, { Name = "Stripe", Size = UDim2.new(0, 5, 1, -24), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = T.gold })
		UI.Kicker(card, "A NEW CAREER", T.gold, { Position = UDim2.fromOffset(22, 16), Size = UDim2.new(1, -44, 0, 18) })
		UI.Title(card, "FROM NOBODY TO UNDISPUTED", { TextSize = 28, Position = UDim2.fromOffset(22, 36), Size = UDim2.new(1, -44, 0, 34) })
		UI.Text(card, "Create your boxer and start in a beginner gym. Train, fight, climb the rankings and become undisputed.", { TextSize = 14, TextColor3 = T.sub,
			Position = UDim2.fromOffset(22, 76), Size = UDim2.new(1, -44, 0, 54), AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Top })
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
	-- the photo is a posed portrait (FighterCard: gloves at the chest, chin level), not the live pose
	local card = FighterCard.Full(layer, P, { Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(small and 52 or 72, top), compact = small })
	card.Name = "Card"
	-- actions: bottom right; on phones they sit in the header row
	local actions = UI.Frame(layer, { Name = "Actions", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, small and 0 or 1),
		Position = small and UDim2.new(1, -40, 0, 66) or UDim2.new(1, -72, 1, -28), Size = UDim2.fromOffset(760, small and 40 or 46) })
	UI.List(actions, 10, true, Enum.HorizontalAlignment.Right)
	local bh = small and 38 or 44
	UI.PadStart(UI.Button(actions, "CAREER HUB", { Size = UDim2.fromOffset(small and 150 or 200, bh), BackgroundColor3 = T.gold, LayoutOrder = 3 }, function()
		MainMenu.Close(function()
			State.open.Hub("Career")
		end)
	end))
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
	local grid = UI.Frame(layer, { Name = "Tiles", BackgroundTransparency = 1, Position = UDim2.fromOffset(small and 52 or 72, small and 122 or 180), Size = UDim2.fromOffset(small and 640 or 760, small and 290 or 420) })
	UI.Grid(grid, UDim2.new(0.5, -8, 0.5, -8), nil, 16)
	for i, t in ipairs(TILES) do
		local b = UI.Button(grid, "", { Name = "Tile", LayoutOrder = i, BackgroundColor3 = T.bg, BackgroundTransparency = 0.15 }, function()
			MainMenu.Close(t[3])
		end)
		if i == 1 then
			UI.PadStart(b)
		end
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

-- grow = the panel is a scrolling frame (the phone overlay): the report grows downward in it
local function scoutPanel(panel, id, grow)
	UI.Clear(panel)
	local res = State.req("GetBoxer", id)
	if not (res and res.ok and res.boxer) then
		UI.Text(panel, "No scouting report available.", { TextColor3 = T.sub, TextSize = 14, Position = UDim2.fromOffset(20, 20), Size = UDim2.new(1, -40, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
		return
	end
	local b = res.boxer
	local body = UI.Frame(panel, { BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 20), Size = grow and UDim2.new(1, -44, 0, 0) or UDim2.new(1, -44, 1, -40),
		AutomaticSize = grow and Enum.AutomaticSize.Y or Enum.AutomaticSize.None })
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

-- the phone version of the scouting panel: a glass sheet over the rankings table with a back button
local scoutSheet
local function closeScout()
	if scoutSheet then
		scoutSheet:Destroy()
		scoutSheet = nil
		return true
	end
	return false
end
function openScout(layer, over, id)
	closeScout()
	local sheet = UI.Frame(layer, { Name = "ScoutSheet", Position = over.Position, Size = over.Size, ZIndex = 6 })
	-- opaque: the rankings rows under it must not bleed through the report's text
	UI.Glass(sheet, { transparency = 0 })
	scoutSheet = sheet
	local back = UI.Button(sheet, "BACK", { Name = "Back", Size = UDim2.fromOffset(110, 38), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), BackgroundColor3 = T.panel2,
		BackgroundTransparency = 0.15, ZIndex = 8 }, closeScout)
	back.ZIndex = 8
	local sc = UI.Scroll(sheet, { Name = "Report", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 7 })
	task.spawn(scoutPanel, sc, id, true)
	sheet.Destroying:Connect(function()
		if scoutSheet == sheet then
			scoutSheet = nil
		end
	end)
end

local function screenRankings(layer)
	local P = State.P
	local small = compact()
	rankClass = rankClass or (P and P.physical and P.physical.weightClass) or 5
	screenHeader(layer, "WORLD RANKINGS", string.upper(Config.WeightClasses[rankClass].name))
	local top = small and 120 or 156
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
			else
				-- phones: the report opens over the table, inside the menu (the Hub's card would sit
				-- under the menu's layers)
				openScout(layer, panel, entry.id)
			end
		end)
	end
end

-- SETTINGS
-- keyboard / gamepad focus over the setting rows: up / down picks a row, left / right steps it
-- (UI.Nudge), Enter flips a toggle or presses the button. A gamepad with Roblox's own UI selection on
-- moves between the [-] / [+] buttons instead (those inputs reach us as processed).
local settingsRows, settingsFocus, settingsBody = {}, 0, nil
local function focusSetting(i)
	if #settingsRows == 0 then
		return
	end
	settingsFocus = math.clamp(i, 1, #settingsRows)
	for j, r in ipairs(settingsRows) do
		local st = r.frame:FindFirstChild("Focus")
		if st then
			st.Enabled = j == settingsFocus
		end
	end
	-- keep the focused row in view
	local row = settingsRows[settingsFocus].frame
	local body = settingsBody
	if body and body.Parent then
		local s = UI.ScaleOf(body)
		local top = (row.AbsolutePosition.Y - body.AbsolutePosition.Y) / s + body.CanvasPosition.Y
		local h = body.AbsoluteSize.Y / s
		local y = body.CanvasPosition.Y
		if top < y + 8 then
			y = top - 8
		elseif top + row.AbsoluteSize.Y / s > y + h - 8 then
			y = top + row.AbsoluteSize.Y / s - h + 8
		end
		body.CanvasPosition = Vector2.new(0, math.max(0, y))
	end
end

local function screenSettings(layer)
	local small = compact()
	screenHeader(layer, "OPTIONS", "SETTINGS")
	local top = small and 122 or 160
	local w = math.min(1100, canvasW - (small and 104 or 144))
	local panel = UI.Frame(layer, { Name = "Panel", Position = UDim2.fromOffset(small and 52 or 72, top), Size = UDim2.fromOffset(w, canvasH - top - (small and 20 or 80)) })
	UI.Glass(panel, { transparency = 0.1 })
	local body = UI.Scroll(panel, { Position = UDim2.fromOffset(24, 18), Size = UDim2.new(1, -48, 1, -36) })
	settingsBody = body
	UI.List(body, 10)
	UI.Pad(body, 2, 4)
	table.clear(settingsRows)
	local order = 0
	local function add(f, activate)
		order += 1
		f.LayoutOrder = order
		if activate then
			UI.New("UIStroke", { Name = "Focus", Color = T.gold, Thickness = 2, Transparency = 0.1, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
			table.insert(settingsRows, { frame = f, activate = activate })
		end
		return f
	end
	-- dir 0 = Enter: flips a toggle, leaves a slider / cycler alone
	local function nudge(f, toggle)
		return function(dir)
			if dir ~= 0 or toggle then
				UI.Nudge(f, dir == 0 and 1 or dir)
			end
		end
	end
	local function header(text)
		add(UI.Header(body, text).Parent)
	end
	local v = Settings.Values
	local D = Settings.Defaults
	local function pct(x)
		return string.format("%d%%", math.floor(x * 100 + 0.5))
	end
	-- plain words beside the percentage; every slider has a reset to its default (its notch)
	local function amount(x)
		return x < 0.01 and "Off" or (x < 0.5 and "Low" or (x < 0.95 and "Medium" or (x <= 1.05 and "Normal" or "Strong")))
	end
	local function volume(x)
		return x < 0.01 and "Muted" or (x < 0.4 and "Quiet" or (x < 0.8 and "Medium" or "Loud"))
	end
	header("DISPLAY")
	-- the UI scale applies when the slider is let go: the screen it lives on is rebuilt at the new scale
	local scaleRow = UI.Slider(body, "UI scale", 0.8, 1.25, v.uiScale, 0.05, function(x)
		Settings.Set("uiScale", x)
	end, pct, { onRelease = true, default = D.uiScale, hint = "Bigger or smaller menus and text (applies when you let go)", words = function(x)
		return x < 0.95 and "Smaller" or (x <= 1.05 and "Normal" or "Larger")
	end })
	add(scaleRow, nudge(scaleRow))
	local detailRow = UI.Cycler(body, "Graphics detail", Settings.Details, v.detail, function(x)
		Settings.Set("detail", x)
	end, function(x)
		return x == "Auto" and "Auto (by distance and device)" or x
	end)
	add(detailRow, nudge(detailRow))
	local brightRow = UI.Slider(body, "Brightness", 0.5, 1.6, v.brightness, 0.05, function(x)
		Settings.Set("brightness", x)
	end, pct, { default = D.brightness, words = amount })
	add(brightRow, nudge(brightRow))
	header("CAMERA & EFFECTS")
	local fxRow = UI.Slider(body, "Screen effects", 0, 1.5, v.screenFx, 0.05, function(x)
		Settings.Set("screenFx", x)
	end, pct, { default = D.screenFx, words = amount })
	add(fxRow, nudge(fxRow))
	add(UI.Text(body, "Blur, colour drain, flashes and vignettes when you get hurt in a fight. Lower it if it gets too intense.", { TextSize = 13, TextColor3 = T.sub }))
	local shakeRow = UI.Slider(body, "Camera shake", 0, 1.5, v.shake, 0.05, function(x)
		Settings.Set("shake", x)
	end, pct, { default = D.shake, words = amount })
	add(shakeRow, nudge(shakeRow))
	header("AUDIO")
	local musicRow = UI.Slider(body, "Music", 0, 1, v.music, 0.05, function(x)
		Settings.Set("music", x)
	end, pct, { default = D.music, words = volume })
	add(musicRow, nudge(musicRow))
	local sfxRow = UI.Slider(body, "Sound effects", 0, 1, v.sfx, 0.05, function(x)
		Settings.Set("sfx", x)
	end, pct, { default = D.sfx, words = volume })
	add(sfxRow, nudge(sfxRow))
	header("GAME")
	local menuRow = UI.Toggle(body, "Show the main menu when I join", v.menuAtStart, function(on)
		Settings.Set("menuAtStart", on)
	end)
	add(menuRow, nudge(menuRow, true))
	local hintsRow = UI.Toggle(body, "Always show the fight controls strip", v.controlHints, function(on)
		Settings.Set("controlHints", on)
	end)
	add(hintsRow, nudge(hintsRow, true))
	header("CONTROLS")
	local movesBtn = UI.Button(body, "MOVES & CONTROLS  ·  REMAP KEYS AND BUTTONS", { Size = UDim2.fromOffset(420, 40) }, function()
		openControls("moves")
	end)
	add(movesBtn, function(dir)
		if dir == 0 then
			openControls("moves")
		end
	end)
	add(UI.Text(body, "Every move with its key, button and touch pad, what it does and how it unlocks; rebind anything on the keyboard or the controller.", { TextSize = 13, TextColor3 = T.sub }))
	local assistRow = UI.Cycler(body, "Aim assist (controller only)", Settings.AimAssists, v.aimAssist, function(x)
		Settings.Set("aimAssist", x)
	end)
	add(assistRow, nudge(assistRow))
	add(UI.Text(body, "The left stick is read relative to the opponent and punches from a pad get a small accuracy forgiveness (Low 3 points, High 6; the server applies it, never to a keyboard).", { TextSize = 13, TextColor3 = T.sub }))
	local vibRow = UI.Toggle(body, "Controller vibration", v.vibration, function(on)
		Settings.Set("vibration", on)
	end)
	add(vibRow, nudge(vibRow, true))
	local vibStrength = UI.Slider(body, "Vibration strength", 0, 1, v.vibrationStrength, 0.05, function(x)
		Settings.Set("vibrationStrength", x)
	end, pct, { default = D.vibrationStrength, words = function(x)
		return x < 0.01 and "Off" or (x < 0.4 and "Light" or (x < 0.8 and "Medium" or "Strong"))
	end })
	add(vibStrength, nudge(vibStrength))
	local function reset()
		for k, def in pairs(Settings.Defaults) do
			Settings.Set(k, def)
		end
		show("settings", true)
	end
	local resetBtn = UI.Button(body, "RESET TO DEFAULTS", { Size = UDim2.fromOffset(240, 40) }, reset)
	add(resetBtn, function(dir)
		if dir == 0 then
			reset()
		end
	end)
	if settingsFocus > 0 then
		task.defer(focusSetting, settingsFocus)
	end
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

-- CAREER / CHARACTER / RANKINGS on a pad: the home list and the settings rows navigate themselves (onInput),
-- the other screens are ordinary buttons, so Roblox's own selection drives them: the screen layer is a
-- SelectionGroup and gets a start selection (UI.PadStart marks the primary button; else the first in
-- reading order) once its content has a size. B puts the selection down and goes home in one press.
local function padSelectScreen()
	if not (UI.IsPad and UI.IsPad()) or view == "home" or view == "settings" then
		return
	end
	local layer = layers.screen
	task.defer(function()
		if isOpen and not closing and layer and layer.Parent and layer.Visible and not ControlsMenu.IsOpen() then
			UI.PadSelect(layer)
		end
	end)
end

function show(name, instant)
	if not (gui and gui.Parent) then
		return
	end
	local from = view
	view = name
	if name == "home" then
		UI.ClearSelection()
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
		padSelectScreen()
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
	elseif it.id == "controls" then
		openControls("moves")
	else
		show(it.id)
	end
end

local LEFT = { [K.Left] = true, [K.A] = true, [K.DPadLeft] = true }
local RIGHT = { [K.Right] = true, [K.D] = true, [K.DPadRight] = true }
local function onInput(input, gp)
	if not isOpen or closing or ControlsMenu.IsOpen() then
		return
	end
	local k = input.KeyCode
	-- B on a screen goes home whether or not Roblox's selection is up (it drops the selection on the same
	-- press, so the first B would otherwise only do that)
	if k == K.ButtonB and view ~= "home" and view ~= "settings" then
		UI.ClearSelection()
		if not closeScout() then
			show("home")
		end
		return
	end
	-- a gamepad's buttons can arrive "processed" only because a default control binding saw them (A is
	-- the jump action); they belong to the menu unless Roblox's own UI selection is driving it
	if gp and not (UI.Gamepad and UI.Gamepad.IsPadKey(k) and GuiService.SelectedObject == nil) then
		return
	end
	-- a D-pad press on a screen with nothing selected (the pad was picked up here): take the selection
	if UI.Gamepad and UI.Gamepad.IsPadKey(k) and view ~= "home" and view ~= "settings" and GuiService.SelectedObject == nil then
		padSelectScreen()
		return
	end
	if view == "home" then
		if k == K.Down or k == K.S or k == K.DPadDown then
			selectItem(sel % #items + 1)
		elseif k == K.Up or k == K.W or k == K.DPadUp then
			selectItem((sel - 2) % #items + 1)
		elseif k == K.Return or k == K.Space or k == K.ButtonA then
			local it = items[sel]
			if it and it.id == "settings" then
				settingsFocus = 1 -- arrived by keys: the first row takes the focus
			end
			activate(it)
		end
	elseif k == K.Backspace or k == K.ButtonB then
		if not closeScout() then
			show("home")
		end
	elseif view == "settings" then
		local r = settingsRows[settingsFocus]
		if k == K.Down or k == K.S or k == K.DPadDown then
			focusSetting(settingsFocus + 1)
		elseif k == K.Up or k == K.W or k == K.DPadUp then
			focusSetting(math.max(1, settingsFocus - 1))
		elseif LEFT[k] or RIGHT[k] then
			if r then
				r.activate(LEFT[k] and -1 or 1)
			else
				focusSetting(1)
			end
		elseif (k == K.Return or k == K.Space or k == K.ButtonA) and r then
			r.activate(0)
		end
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
	-- the menu navigates itself (D-pad / A / B): no window selection under it
	UI.PadHold("Menu", true)
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
	layers.screen = UI.Frame(root, { Name = "Screen", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, SelectionGroup = true })
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
	-- a new screen size (rotation, window resize, UI scale setting): rebuild in place, once the change
	-- settles and no pointer is held (a drag in progress keeps its widget)
	local rebuildToken = 0
	local builtW, builtH = canvasW, canvasH
	local function rebuildSoon()
		rebuildToken += 1
		local token = rebuildToken
		task.delay(0.15, function()
			if token ~= rebuildToken or not isOpen or closing then
				return
			end
			if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				rebuildSoon()
				return
			end
			measure()
			if math.abs(canvasW - builtW) < 1 and math.abs(canvasH - builtH) < 1 then
				return
			end
			builtW, builtH = canvasW, canvasH
			if view == "home" then
				buildHome()
			else
				show(view, true)
			end
		end)
	end
	track(root:GetAttributeChangedSignal("UIScale"):Connect(rebuildSoon))
	-- the canvas also changes at a constant scale (two phone sizes both at the 0.78 floor)
	track(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rebuildSoon))
	-- the character respawned under the menu: stage the new one
	track(player.CharacterAdded:Connect(function()
		task.wait(1)
		if isOpen and scene then
			stageBoxer()
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
		table.clear(settingsRows)
		settingsFocus, settingsBody, scoutSheet = 0, nil, nil
		isOpen, closing = false, false
		view = "home"
		UI.ClearSelection()
		UI.PadHold("Menu", false)
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
