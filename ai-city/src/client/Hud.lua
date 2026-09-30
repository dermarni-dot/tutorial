-- Hud (ModuleScript) — StarterPlayerScripts.CityClient.Hud
-- The always-on screen: the clock and calendar, the city's mood and stats,
-- a rotating minimap, coins, wanted stars, the mayor and the next election,
-- the action bar, notifications and the news ticker.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UI = require(script.Parent:WaitForChild("UI"))
local C = UI.C

local Hud = {}
local player = Players.LocalPlayer
local ctx
local screen
local cityState

--------------------------------------------------------------------------------
-- Drawing the city (used by the minimap and the big map)
--------------------------------------------------------------------------------
-- Draws blocks, roads, the lake and place pins into `frame` at `scale`
-- pixels per stud, centered on the frame's (0, 0). Returns { [placeId] = pin }.
function Hud.DrawCity(frame, scale, opts)
	opts = opts or {}
	local info = ReplicatedStorage:WaitForChild("CityInfo")
	local extent = info:GetAttribute("Extent") or 450
	local spacing = info:GetAttribute("Spacing") or 100
	local n = info:GetAttribute("Blocks") or 4
	local block = spacing - 16
	local function px(x)
		return x * scale
	end
	-- grass and roads under everything
	local ground = UI.new("Frame", { BackgroundColor3 = UI.rgb(70, 120, 70), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(px(extent * 2 + 500), px(extent * 2 + 500)), ZIndex = 1, Parent = frame })
	local roads = UI.new("Frame", { BackgroundColor3 = UI.rgb(58, 60, 68), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(px(extent * 2 + 16), px(extent * 2 + 16)), ZIndex = 2, Parent = frame })
	UI.corner(roads, 4)
	-- which block holds which place
	local kinds = {}
	for _, v in ipairs(info:GetChildren()) do
		if v:IsA("Vector3Value") then
			local i, j = math.floor(v.Value.X / spacing + 0.5), math.floor(v.Value.Z / spacing + 0.5)
			if math.abs(i) <= n and math.abs(j) <= n then
				kinds[i .. "," .. j] = kinds[i .. "," .. j] or v:GetAttribute("Kind")
			end
		end
	end
	for i = -n, n do
		for j = -n, n do
			local kind = kinds[i .. "," .. j]
			local color = if kind then (UI.KIND_COLORS[kind] or C.Sub):Lerp(UI.rgb(210, 210, 200), 0.55) else UI.rgb(196, 214, 176)
			local b = UI.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(px(i * spacing), px(j * spacing)), Size = UDim2.fromOffset(px(block), px(block)), ZIndex = 3, Parent = frame })
			UI.corner(b, math.max(2, px(6)))
		end
	end
	local lx, lz, lr = info:GetAttribute("LakeX"), info:GetAttribute("LakeZ"), info:GetAttribute("LakeRadius")
	if lx then
		local lake = UI.new("Frame", { BackgroundColor3 = UI.rgb(70, 150, 220), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(px(lx), px(lz)), Size = UDim2.fromOffset(px(lr * 2), px(lr * 2)), ZIndex = 3, Parent = frame })
		UI.corner(lake, UDim.new(0.5, 0))
	end
	local pins = {}
	for _, v in ipairs(info:GetChildren()) do
		if v:IsA("Vector3Value") then
			local placeInfo = Config.PlaceById[v.Name]
			local pin = UI.new("TextButton", {
				Name = v.Name,
				AutoButtonColor = false,
				BackgroundColor3 = UI.KIND_COLORS[v:GetAttribute("Kind")] or C.Sub,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(px(v.Value.X), px(v.Value.Z)),
				Size = UDim2.fromOffset(opts.PinSize or 18, opts.PinSize or 18),
				Text = placeInfo and placeInfo.emoji or v:GetAttribute("Emoji") or "📍",
				TextSize = (opts.PinSize or 18) - 5,
				Font = UI.Font,
				ZIndex = 6,
				Parent = frame,
			})
			UI.corner(pin, UDim.new(0.5, 0))
			UI.stroke(pin, C.White, 1.5, 0.1)
			if opts.Labels then
				local label = UI.text(pin, v:GetAttribute("Label") or v.Name, 12, UI.Bold, C.White, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1), Size = UDim2.fromOffset(120, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
				UI.new("UIStroke", { Thickness = 1.5, Transparency = 0.2, Parent = label })
			end
			pins[v.Name] = pin
		end
	end
	return pins
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------
local toastHolder
function Hud.Toast(icon, title, text, color)
	if not toastHolder then
		return
	end
	color = color or C.Gold
	local toast = UI.panel(toastHolder, { Size = UDim2.fromOffset(310, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.05, Radius = 12, ClipsDescendants = true })
	local strip = UI.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 5, 1, 0), Parent = toast })
	local inner = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = toast })
	UI.pad(inner, 8, 8, 10, 8, 40)
	UI.text(toast, icon or "🔔", 24, UI.Font, C.White, { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(32, 32), TextXAlignment = Enum.TextXAlignment.Center })
	UI.list(inner, Enum.FillDirection.Vertical, 2)
	UI.text(inner, title or "", 15, UI.Bold, color:Lerp(C.White, 0.35), { AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 1 })
	if text and text ~= "" then
		UI.text(inner, text, 13, UI.Font, C.Sub, { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 16), TextWrapped = true, LayoutOrder = 2 })
	end
	local scale = UI.new("UIScale", { Scale = 0.5, Parent = toast })
	UI.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	UI.sound("notify", 0.2, 1.3)
	-- keep at most five
	local items = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(items, child)
		end
	end
	if #items > 5 then
		items[1]:Destroy()
	end
	task.delay(6, function()
		if toast.Parent then
			UI.tween(scale, 0.2, { Scale = 0.6 })
			UI.tween(toast, 0.2, { BackgroundTransparency = 1 })
			task.wait(0.2)
			toast:Destroy()
		end
	end)
	return strip
end

--------------------------------------------------------------------------------
-- The news ticker
--------------------------------------------------------------------------------
local ticker, tickerText
function Hud.News(text, kind)
	if not ticker then
		return
	end
	tickerText.Text = "<b>" .. (if kind == "Crime" then "🚨 BREAKING" elseif kind == "Election" then "🗳️ ELECTION" elseif kind == "Birth" then "👶 NEW BABY" else "📰 CITY NEWS") .. "</b>   " .. text
	ticker.Visible = true
	ticker.BackgroundTransparency = 0.05
	local scale = ticker:FindFirstChildOfClass("UIScale")
	scale.Scale = 0.85
	UI.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	local token = {}
	Hud.NewsToken = token
	task.delay(14, function()
		if Hud.NewsToken == token then
			UI.tween(ticker, 0.5, { BackgroundTransparency = 0.6 })
		end
	end)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
local refs = {}

local function statRow(parent, icon, name, color, order)
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order, Parent = parent })
	UI.Icons.Glyph(row, icon, 17, { Color = color, Hole = C.Panel })
	UI.text(row, name, 12, UI.Bold, C.Sub, { Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(74, 18) })
	local bar, set = UI.bar(row, color, 8, { Position = UDim2.new(0, 98, 0.5, -4), Size = UDim2.new(1, -134, 0, 8) })
	local value = UI.text(row, "50", 12, UI.Bold, C.Text, { Position = UDim2.new(1, -32, 0, 0), Size = UDim2.fromOffset(32, 18), TextXAlignment = Enum.TextXAlignment.Right })
	return set, value
end

local function actionButton(parent, emoji, label, key, order, onClick, color)
	local button = UI.button(parent, "", { Size = UDim2.fromOffset(66, 62), Color = color or C.Panel2, LayoutOrder = order }, onClick)
	UI.Icons.Glyph(button, emoji, 30, { Name = "ActionIcon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Hole = color or C.Panel2 })
	UI.text(button, label, 11, UI.Bold, C.Sub, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 36), TextXAlignment = Enum.TextXAlignment.Center })
	if key and not UserInputService.TouchEnabled then
		local w = math.max(16, #key * 6 + 4)
		local keycap = UI.new("TextLabel", { BackgroundColor3 = C.Bg, Text = key, TextColor3 = C.Gold, Font = UI.Black, TextSize = 10, Size = UDim2.fromOffset(w, 16), Position = UDim2.new(1, -w - 2, 0, 2), Parent = button })
		UI.corner(keycap, 5)
	end
	return button
end

local function build()
	screen = UI.new("ScreenGui", { Name = "CityHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5, Parent = player:WaitForChild("PlayerGui") })
	Hud.Screen = screen
	local uiScale = UI.new("UIScale", { Parent = screen })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.62, 1.15)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- the clock card
	-- the left column: the clock card, then today's goals under it
	local column = UI.new("Frame", { Name = "LeftColumn", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = screen })
	UI.list(column, Enum.FillDirection.Vertical, 10)
	local card = UI.panel(column, { Name = "Clock", Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = 16, LayoutOrder = 1 })
	UI.pad(card, 12, 10, 14, 12, 14)
	UI.list(card, Enum.FillDirection.Vertical, 6)
	local top = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, Parent = card })
	refs.Time = UI.text(top, "8:00", 36, UI.Title, C.White, { Size = UDim2.fromOffset(110, 40), AutomaticSize = Enum.AutomaticSize.X })
	refs.AmPm = UI.text(top, "AM", 15, UI.Bold, C.Sub, { Position = UDim2.fromOffset(100, 6), Size = UDim2.fromOffset(40, 18) })
	refs.Sky = UI.Icons.Glyph(top, "sun", 38, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 1), Hole = C.Panel })
	refs.Day = UI.text(card, "Monday · Day 1", 14, UI.Bold, C.Sub, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 18) })
	local stateRow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, Parent = card })
	UI.list(stateRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	refs.State = UI.chip(stateRow, "🙂 Stable", C.Blue, { LayoutOrder = 1, TextSize = 14, Size = UDim2.fromOffset(0, 26) })
	refs.Pop = UI.chip(stateRow, "👥 90", C.Panel3, { LayoutOrder = 2 })
	refs.AvgMood = UI.chip(stateRow, "🙂 60", C.Panel3, { LayoutOrder = 3 })
	refs.StateDesc = UI.text(card, "", 12, UI.Font, C.Dim, { LayoutOrder = 4, TextWrapped = true, Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y })
	refs.Economy, refs.EconomyValue = statRow(card, "💰", "Economy", C.Gold, 5)
	refs.Safety, refs.SafetyValue = statRow(card, "🛡️", "Safety", C.Blue, 6)
	refs.Happiness, refs.HappinessValue = statRow(card, "😊", "Happiness", C.Pink, 7)

	-- the minimap
	local mini = UI.new("CanvasGroup", { Name = "Minimap", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(186, 186), BackgroundColor3 = UI.rgb(70, 120, 70), Parent = screen })
	UI.corner(mini, UDim.new(0.5, 0))
	local ring = UI.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(186, 186), BackgroundTransparency = 1, Parent = screen })
	UI.corner(ring, UDim.new(0.5, 0))
	UI.stroke(ring, C.White, 3, 0.15)
	local pivot = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), Parent = mini })
	local world = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Parent = pivot })
	local MINI_SCALE = 0.42
	refs.MiniPins = Hud.DrawCity(world, MINI_SCALE, { PinSize = 16 })
	refs.MiniWorld, refs.MiniPivot = world, pivot
	refs.MiniDots = {}
	for k = 1, 40 do
		local dot = UI.new("Frame", { BackgroundColor3 = C.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 5), Visible = false, ZIndex = 8, Parent = world })
		UI.corner(dot, UDim.new(0.5, 0))
		refs.MiniDots[k] = dot
	end
	refs.MiniWaypoint = UI.text(world, "📍", 20, UI.Font, C.White, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(24, 24), Visible = false, ZIndex = 9, TextXAlignment = Enum.TextXAlignment.Center })
	local arrow = UI.text(mini, "▲", 18, UI.Black, C.Gold, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 10 })
	UI.new("UIStroke", { Thickness = 1.5, Parent = arrow })
	refs.North = UI.new("TextLabel", { BackgroundColor3 = C.Red, Text = "N", TextColor3 = C.White, Font = UI.Black, TextSize = 12, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), ZIndex = 11, Parent = mini })
	UI.corner(refs.North, UDim.new(0.5, 0))

	-- coins, wanted, mayor, election (under the minimap)
	local right = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 208), Size = UDim2.fromOffset(250, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = screen })
	UI.list(right, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
	local coins = UI.panel(right, { Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Radius = 20 })
	UI.pad(coins, 0, 0, 16, 0, 12)
	UI.list(coins, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	UI.Icons.Glyph(coins, "coin", 26, { LayoutOrder = 1 })
	refs.Coins = UI.text(coins, "100", 22, UI.Title, C.Gold, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), LayoutOrder = 2 })
	local wanted = UI.panel(right, { Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Radius = 18, Visible = false })
	UI.pad(wanted, 0, 0, 12, 0, 12)
	UI.list(wanted, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	refs.Wanted, refs.Stars = wanted, {}
	refs.WantedEye = UI.text(wanted, "👀", 16, UI.Font, C.White, { Size = UDim2.fromOffset(22, 26), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 0 })
	for k = 1, 5 do
		refs.Stars[k] = UI.text(wanted, "★", 22, UI.Black, C.Dim, { Size = UDim2.fromOffset(22, 26), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = k })
	end
	-- what the police are doing: chasing you, searching for you, or you're hidden
	refs.Police = UI.chip(right, "", C.Red, { LayoutOrder = 2, TextSize = 13, Size = UDim2.fromOffset(0, 28), Visible = false })
	refs.PoliceTip = UI.text(right, "", 12, UI.Font, C.Sub, { LayoutOrder = 2, Size = UDim2.fromOffset(250, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right, Visible = false })
	refs.Notoriety = UI.chip(right, "", UI.rgb(120, 60, 30), { LayoutOrder = 2, TextSize = 12, Size = UDim2.fromOffset(0, 24), Visible = false })
	-- your disguise: how hidden you are right now
	refs.Disguise = UI.chip(right, "", UI.rgb(88, 60, 140), { LayoutOrder = 2, TextSize = 12, Size = UDim2.fromOffset(0, 24), Visible = false })
	refs.Mayor = UI.chip(right, "🏛️ Mayor: —", C.Panel2, { LayoutOrder = 3, TextSize = 13, Size = UDim2.fromOffset(0, 28) })
	refs.Election = UI.chip(right, "🗳️ Election in 8:00", C.Panel2, { LayoutOrder = 4, TextSize = 13, Size = UDim2.fromOffset(0, 28) })
	toastHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = right })
	UI.list(toastHolder, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
	UI.pad(toastHolder, 0, 6, 0, 0, 0)

	-- the action bar
	local bar = UI.panel(screen, { Name = "ActionBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(0, 76), AutomaticSize = Enum.AutomaticSize.X, Radius = 18 })
	UI.pad(bar, 7)
	UI.list(bar, Enum.FillDirection.Horizontal, 7, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	refs.Bar = bar
	refs.PhoneButton = actionButton(bar, "📱", "Phone", "Tab", 0, function()
		ctx.Panels.Phone.Toggle()
	end, UI.rgb(70, 50, 130))
	actionButton(bar, "🗺️", "Map", "M", 1, function()
		ctx.Panels.Map.Toggle()
	end)
	refs.SpeechButton = actionButton(bar, "🎤", "Speech", "B", 4, function()
		ctx.Panels.Speech.Toggle()
	end, C.Panel2)
	refs.MayorButton = actionButton(bar, "🏛️", "Mayor", "N", 5, function()
		ctx.Panels.Mayor.Toggle()
	end, UI.rgb(120, 90, 30))
	refs.MayorButton.Visible = false
	refs.AttackButton = actionButton(bar, "👊", "Attack", "F", 6, function()
		ctx.World.Attack()
	end, UI.rgb(110, 40, 48))
	refs.AttackEmoji = refs.AttackButton:FindFirstChild("ActionIcon")
	-- sprint: hold the button (or Shift)
	local sprintButton = actionButton(bar, "run", "Sprint", "Shift", 7, nil, UI.rgb(30, 90, 80))
	sprintButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ctx.Moves.SetSprint(true)
		end
	end)
	sprintButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ctx.Moves.SetSprint(false)
		end
	end)
	-- block: hold the button (or X)
	local blockButton = actionButton(bar, "🛡️", "Block", "X", 6, nil, UI.rgb(40, 60, 110))
	blockButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ctx.World.SetBlock(true)
		end
	end)
	blockButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ctx.World.SetBlock(false)
		end
	end)

	-- health (bottom left)
	local health = UI.panel(screen, { Name = "Health", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(250, 44), Radius = 14 })
	UI.Icons.Glyph(health, "heart", 28, { Position = UDim2.fromOffset(11, 8) })
	local hb, hset, hfill = UI.bar(health, C.Green, 12, { Position = UDim2.fromOffset(46, 16), Size = UDim2.new(1, -100, 0, 12) })
	refs.HealthSet, refs.HealthFill = hset, hfill
	refs.HealthText = UI.text(health, "100", 16, UI.Title, C.White, { Position = UDim2.new(1, -50, 0, 4), Size = UDim2.fromOffset(42, 36), TextXAlignment = Enum.TextXAlignment.Right })
	refs.HealthPanel = health
	-- stamina (above the health bar): the bar, your fitness level and XP to the next one
	local stam = UI.panel(screen, { Name = "Stamina", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -66), Size = UDim2.fromOffset(250, 40), Radius = 14 })
	refs.StaminaIcon = UI.Icons.Glyph(stam, "bolt", 24, { Position = UDim2.fromOffset(13, 8) })
	local sb, sset, sfill = UI.bar(stam, C.Teal, 10, { Position = UDim2.fromOffset(46, 11), Size = UDim2.new(1, -112, 0, 10) })
	refs.StaminaSet, refs.StaminaFill, refs.StaminaPanel = sset, sfill, stam
	local xpBack = UI.new("Frame", { BackgroundColor3 = C.Bg, BorderSizePixel = 0, Position = UDim2.fromOffset(46, 26), Size = UDim2.new(1, -112, 0, 4), Parent = stam })
	UI.corner(xpBack, 2)
	refs.FitXP = UI.new("Frame", { BackgroundColor3 = C.Gold, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = xpBack })
	UI.corner(refs.FitXP, 2)
	refs.FitLevel = UI.text(stam, "Lv 1", 14, UI.Title, C.Gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 2), Size = UDim2.fromOffset(56, 36), TextXAlignment = Enum.TextXAlignment.Right })
	refs.BlockIcon = UI.chip(screen, "🛡️ BLOCKING", C.Blue, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -112), Visible = false })

	-- the news ticker (just above the action bar)
	ticker = UI.panel(screen, { Name = "News", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Radius = 16, Visible = false })
	UI.pad(ticker, 0, 0, 16, 0, 16)
	UI.new("UIScale", { Parent = ticker })
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(760, 32), Parent = ticker })
	tickerText = UI.text(ticker, "", 14, UI.Font, C.Text, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), TextTruncate = Enum.TextTruncate.AtEnd })

	-- the speech hint (near the podium)
	refs.Hint = UI.panel(screen, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -136), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Radius = 18, Visible = false, BackgroundColor3 = UI.rgb(90, 70, 20) })
	UI.pad(refs.Hint, 0, 0, 16, 0, 16)
	UI.text(refs.Hint, "🎤 You're at the podium! Press <b>B</b> (or 🎤) to give a speech", 15, UI.Bold, C.Gold, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36) })

	-- wanted: a red glow around the screen
	refs.Edge = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = screen })
	refs.EdgeStroke = UI.stroke(refs.Edge, C.Red, 14, 1)
	refs.Banner = UI.text(screen, "", 40, UI.Title, C.Red, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(600, 50), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, ZIndex = 30 })
	refs.BannerStroke = UI.new("UIStroke", { Thickness = 3, Transparency = 1, Parent = refs.Banner })

	-- jail: a bar with the time left
	refs.Jail = UI.panel(screen, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(360, 64), Visible = false, BackgroundColor3 = UI.rgb(60, 20, 26), Radius = 16 })
	UI.pad(refs.Jail, 10, 8, 16, 8, 16)
	refs.JailText = UI.text(refs.Jail, "🔒 In jail", 18, UI.Title, C.White, { Size = UDim2.new(1, 0, 0, 24) })
	local jb
	jb, refs.JailSet = UI.bar(refs.Jail, C.Red, 10, { Position = UDim2.fromOffset(0, 32) })
end

--------------------------------------------------------------------------------
-- Live updates
--------------------------------------------------------------------------------
local function skyIcon(h)
	if h >= 5.5 and h < 7.5 then
		return "🌅"
	elseif h >= 7.5 and h < 17.5 then
		return "☀️"
	elseif h >= 17.5 and h < 19.5 then
		return "🌇"
	end
	return "🌙"
end

local lastStats = {}
local function refreshCity()
	local s = cityState
	local h = game:GetService("Lighting").ClockTime
	local time, ampm = UI.formatHour(h)
	refs.Time.Text = time
	refs.AmPm.Text = ampm
	refs.AmPm.Position = UDim2.fromOffset(refs.Time.TextBounds.X + 6, 6)
	UI.Icons.Set(refs.Sky, skyIcon(h))
	refs.Day.Text = (s:GetAttribute("Weekday") or "Monday") .. " · Day " .. ((s:GetAttribute("Day") or 0) + 1) .. (if s:GetAttribute("Weekend") then "  ·  🎉 Weekend" else "")
	local color = s:GetAttribute("StateColor") or C.Blue
	refs.State.Text = (s:GetAttribute("StateEmoji") or "🙂") .. " " .. (s:GetAttribute("StateLabel") or "Stable")
	refs.State.BackgroundColor3 = color
	refs.StateDesc.Text = s:GetAttribute("StateDesc") or ""
	refs.Pop.Text = "👥 " .. (s:GetAttribute("Population") or 0)
	local avg = s:GetAttribute("AverageMood") or 60
	refs.AvgMood.Text = UI.moodEmoji(avg) .. " " .. avg
	for _, stat in ipairs({ "Economy", "Safety", "Happiness" }) do
		local v = s:GetAttribute(stat) or 50
		if lastStats[stat] ~= v then
			lastStats[stat] = v
			refs[stat](v / 100)
			refs[stat .. "Value"].Text = tostring(v)
		end
	end
	local mayor = s:GetAttribute("Mayor") or "—"
	local isMe = s:GetAttribute("MayorUserId") == player.UserId
	refs.Mayor.Text = "🏛️ Mayor: " .. (if isMe then "YOU! 👑" else mayor)
	refs.Mayor.BackgroundColor3 = if isMe then UI.rgb(130, 95, 20) else C.Panel2
	refs.MayorButton.Visible = isMe
	local left = s:GetAttribute("ElectionIn") or 0
	refs.Election.Text = string.format("🗳️ Election in %d:%02d", math.floor(left / 60), left % 60)
	refs.Election.BackgroundColor3 = if left <= 60 then UI.rgb(40, 80, 170) else C.Panel2
end

local shownCoins
function Hud.SetCoins(n, animate)
	if shownCoins == nil or not animate then
		shownCoins = n
		refs.Coins.Text = UI.commas(n)
		return
	end
	local from = shownCoins
	shownCoins = n
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < 0.6 do
			local k = (os.clock() - start) / 0.6
			refs.Coins.Text = UI.commas(from + (n - from) * k)
			task.wait()
		end
		refs.Coins.Text = UI.commas(n)
	end)
	local scale = refs.Coins:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = refs.Coins })
	scale.Scale = 1.3
	UI.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	refs.Coins.TextColor3 = if n >= from then C.Gold else C.Red
	task.delay(0.8, function()
		refs.Coins.TextColor3 = C.Gold
	end)
end

function Hud.Banner(text, color, seconds)
	refs.Banner.Text = text
	refs.Banner.TextColor3 = color or C.Red
	refs.Banner.TextTransparency = 0
	refs.BannerStroke.Transparency = 0.2
	local scale = refs.Banner:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = refs.Banner })
	scale.Scale = 1.6
	UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	local token = {}
	refs.BannerToken = token
	task.delay(seconds or 2.5, function()
		if refs.BannerToken == token then
			UI.tween(refs.Banner, 0.5, { TextTransparency = 1 })
			UI.tween(refs.BannerStroke, 0.5, { Transparency = 1 })
		end
	end)
end

local function refreshWanted()
	local stars = player:GetAttribute("Wanted") or 0
	refs.Wanted.Visible = stars > 0
	for k = 1, 5 do
		refs.Stars[k].TextColor3 = if k <= stars then C.Gold else C.Dim
	end
end

local function frame(dt)
	local t = os.clock()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	-- minimap: centered on you, turned with the camera
	if root and camera then
		local p = root.Position
		local scale = 0.42
		refs.MiniWorld.Position = UDim2.fromOffset(-p.X * scale, -p.Z * scale)
		local look = camera.CFrame.LookVector
		local yaw = math.deg(math.atan2(look.X, -look.Z))
		refs.MiniPivot.Rotation = -yaw
		local r = 80
		refs.North.Position = UDim2.new(0.5, math.sin(math.rad(-yaw)) * r, 0.5, -math.cos(math.rad(-yaw)) * r)
	end
	-- wanted: the edge pulses (fast when the police can see you)
	local stars = player:GetAttribute("Wanted") or 0
	if stars > 0 then
		local seen = player:GetAttribute("WantedSeen")
		local pulse = (math.sin(t * (if seen then 9 else 3)) + 1) / 2
		refs.EdgeStroke.Transparency = 0.45 + pulse * 0.45
		refs.EdgeStroke.Color = if math.floor(t * 4) % 2 == 0 and seen then C.Red else C.Blue
		local hidden = player:GetAttribute("Hiding")
		local state = player:GetAttribute("PoliceState")
		local near = player:GetAttribute("PoliceNear")
		local count = player:GetAttribute("PoliceCount") or 0
		local heli = player:GetAttribute("Helicopter")
		local force = "  ·  👮×" .. count .. (if heli then " 🚁" else "")
		local level = player:GetAttribute("PoliceLevel")
		refs.WantedEye.Text = if seen then "👀" elseif hidden then "🫥" else "🔎"
		for k = 1, stars do
			refs.Stars[k].TextColor3 = if seen and math.floor(t * 5) % 2 == 0 then C.Red else C.Gold
		end
		refs.Police.Visible = true
		refs.PoliceTip.Visible = true
		if seen then
			refs.Police.Text = "🚨 CHASING YOU" .. force .. (if near then "  ·  " .. near .. " studs" else "")
			refs.Police.BackgroundColor3 = C.Red
			refs.PoliceTip.Text = (if level then "<b>" .. level .. "</b>. " else "") .. "Break their line of sight: duck around a corner or into a building."
		elseif hidden then
			refs.Police.Text = "🫥 HIDDEN in " .. tostring(hidden) .. force .. (if near then "  ·  " .. near .. " studs" else "")
			refs.Police.BackgroundColor3 = C.Purple
			refs.PoliceTip.Text = "Stay still... your stars fade faster while you hide. Space to get out."
			refs.EdgeStroke.Color = C.Purple
			refs.EdgeStroke.Transparency = 0.75 + (math.sin(t * 2) + 1) / 2 * 0.2
		else
			refs.Police.Text = "🔎 THEY'RE SEARCHING" .. force .. (if near then "  ·  " .. near .. " studs" else "")
			refs.Police.BackgroundColor3 = C.Orange
			refs.PoliceTip.Text = (if level then "<b>" .. level .. "</b>. " else "") .. "They lost sight of you! Hide in a trash can, hedge or bush (Q)" .. (if heli then ", or get indoors away from the helicopter." else ", or keep running.")
		end
	else
		refs.EdgeStroke.Transparency = 1
		refs.Police.Visible = false
		refs.PoliceTip.Visible = false
	end
	-- disguise: how hidden you are, and whether the police are looking for your old look
	local hiddenNow = player:GetAttribute("Hidden")
	local disguise = player:GetAttribute("Disguise")
	refs.Disguise.Visible = disguise ~= nil
	if disguise then
		refs.Disguise.Text = "🥷 " .. math.floor((hiddenNow or 0) * 100 + 0.5) .. "% hidden" .. (if player:GetAttribute("Night") then " 🌙" else "") .. (if player:GetAttribute("Suspicious") then "  ·  👀 people are nervous" else "")
	end
	local look = player:GetAttribute("PoliceLook")
	if look and refs.PoliceTip.Visible and not player:GetAttribute("WantedSeen") then
		refs.PoliceTip.Text = "🕵️ They're looking for <b>" .. look .. "</b>. You changed your look, so they'll only know you up close."
	end
	-- notoriety: repeat offenders get more police, faster
	local notoriety = player:GetAttribute("Notoriety") or 0
	refs.Notoriety.Visible = notoriety >= 4
	refs.Notoriety.Text = if notoriety >= 12 then "🔥🔥🔥 Most wanted in the city" elseif notoriety >= 8 then "🔥🔥 The police know your face" else "🔥 Known to the police"
	-- health, and the weapon in your hand
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local hp = math.max(0, humanoid.Health)
		local frac = hp / math.max(1, humanoid.MaxHealth)
		if refs.LastHP ~= math.floor(hp) then
			if refs.LastHP and hp < refs.LastHP then
				-- hurt: flash red
				refs.HealthPanel.BackgroundColor3 = C.Red
				UI.tween(refs.HealthPanel, 0.5, { BackgroundColor3 = C.Panel })
			end
			refs.LastHP = math.floor(hp)
			refs.HealthSet(frac, if frac > 0.6 then C.Green elseif frac > 0.3 then C.Gold else C.Red)
			refs.HealthText.Text = tostring(math.ceil(hp))
		end
	end
	refs.BlockIcon.Visible = player:GetAttribute("Blocking") == true
	local weapon = ctx.World.Equipped and ctx.World.Equipped() or "Fists"
	if refs.AttackEmoji and refs.ShownWeapon ~= weapon then
		refs.ShownWeapon = weapon
		UI.Icons.Set(refs.AttackEmoji, if UI.Icons.Has(weapon) then weapon else "fist")
	end
	-- jail
	local jailUntil = player:GetAttribute("JailUntil")
	if jailUntil then
		local left = math.max(0, jailUntil - workspace:GetServerTimeNow())
		refs.Jail.Visible = true
		refs.JailText.Text = string.format("🔒 In jail — %d seconds left", math.ceil(left))
		refs.JailSet(left / math.max(1, refs.JailTotal or left))
	else
		refs.Jail.Visible = false
	end
	-- near the podium?
	local podium = ctx.SpeechSpot
	local nearPodium = root ~= nil and podium ~= nil and (root.Position - podium).Magnitude < 14
	refs.Hint.Visible = nearPodium and not ctx.Panels.Speech.IsOpen()
	refs.SpeechButton.Visible = nearPodium
	refs.SpeechButton.BackgroundColor3 = UI.rgb(130, 95, 20)
	Hud.UpdateExtras(dt, root)
end

local function dotsTick()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local k = 0
	for _, model in ipairs(CollectionService:GetTagged("Citizen")) do
		local r = model:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - root.Position).Magnitude < 220 then
			k += 1
			local dot = refs.MiniDots[k]
			if not dot then
				break
			end
			dot.Visible = true
			dot.Position = UDim2.fromOffset(r.Position.X * 0.42, r.Position.Z * 0.42)
			dot.BackgroundColor3 = if model:GetAttribute("Chasing") then C.Red elseif model:GetAttribute("KnockedOut") then C.Purple else C.White
		end
	end
	for j = k + 1, #refs.MiniDots do
		refs.MiniDots[j].Visible = false
	end
	local wp = workspace:FindFirstChild("CityWaypoint")
	local anchor = wp and wp:FindFirstChild("WaypointAnchor")
	refs.MiniWaypoint.Visible = anchor ~= nil
	if anchor then
		refs.MiniWaypoint.Position = UDim2.fromOffset(anchor.Position.X * 0.42, anchor.Position.Z * 0.42)
		refs.MiniWaypoint.Rotation = -refs.MiniPivot.Rotation
	end
end

--------------------------------------------------------------------------------
-- Daily goals (under the clock)
--------------------------------------------------------------------------------
local goalsPanel, goalsList, goalsOpen = nil, nil, true
function Hud.SetGoals(goals, done)
	if not goalsPanel then
		return
	end
	Hud.GoalData = goals
	for _, child in ipairs(goalsList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local finished = 0
	for k, g in ipairs(goals or {}) do
		if g.Done then
			finished += 1
		end
		local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = k, Parent = goalsList })
		UI.text(row, (if g.Done then "✅" else g.Emoji) .. "  " .. g.Text, 13, if g.Done then UI.Font else UI.Bold, if g.Done then C.Dim else C.Text, { Size = UDim2.new(1, -54, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		UI.text(row, if g.Done then "+" .. g.Reward .. "🪙" else g.Have .. "/" .. g.Need, 12, UI.Bold, if g.Done then C.Green else C.Gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(52, 16), TextXAlignment = Enum.TextXAlignment.Right })
		local _, set = UI.bar(row, if g.Done then C.Green else C.Gold, 5, { Position = UDim2.fromOffset(0, 20) })
		set(g.Have / math.max(1, g.Need))
	end
	goalsPanel.Title.Text = "🎯 Today's goals  <font color='#a0a8c6'>" .. finished .. "/" .. #(goals or {}) .. "</font>" .. (if goalsOpen then "  ▾" else "  ▸")
	if done then
		Hud.Banner("🎯 GOAL COMPLETE!  +" .. done.Reward .. " 🪙", C.Green, 2.5)
		Hud.Toast("🎯", "Goal complete: " .. done.Text, "+" .. done.Reward .. " coins", C.Green)
		local scale = goalsPanel.Frame:FindFirstChildOfClass("UIScale")
		scale.Scale = 1.08
		UI.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local function buildGoals(column)
	local frame = UI.panel(column, { Name = "Goals", LayoutOrder = 2, Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = 16 })
	UI.new("UIScale", { Parent = frame })
	UI.pad(frame, 10, 8, 14, 10, 14)
	UI.list(frame, Enum.FillDirection.Vertical, 6)
	local title = UI.new("TextButton", { BackgroundTransparency = 1, Text = "🎯 Today's goals", TextColor3 = C.Gold, Font = UI.Title, TextSize = 16, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0, Parent = frame })
	goalsList = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = frame })
	UI.list(goalsList, Enum.FillDirection.Vertical, 4)
	title.Activated:Connect(function()
		goalsOpen = not goalsOpen
		goalsList.Visible = goalsOpen
		Hud.SetGoals(Hud.GoalData)
	end)
	goalsPanel = { Frame = frame, Title = title }
end

--------------------------------------------------------------------------------
-- The weapon hotbar (bottom right): 1 = fists, 2+ = your weapons
--------------------------------------------------------------------------------
local hotbar, slots = nil, {}
local function tools()
	local list = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ player.Character, backpack }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("Weapon") then
					table.insert(list, t)
				end
			end
		end
	end
	local order = { Bat = 1, Hammer = 2, Knife = 3 }
	table.sort(list, function(a, b)
		return (order[a:GetAttribute("Weapon")] or 9) < (order[b:GetAttribute("Weapon")] or 9)
	end)
	return list
end

-- equip slot n (1 = fists)
function Hud.Equip(n)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	local list = tools()
	if n == 1 then
		humanoid:UnequipTools()
		return true
	end
	local tool = list[n - 1]
	if tool then
		if tool.Parent == player.Character then
			humanoid:UnequipTools()
		else
			humanoid:EquipTool(tool)
		end
		UI.sound("click", 0.25, 1.4)
		return true
	end
	return false
end

local function buildHotbar()
	hotbar = UI.new("Frame", { Name = "Hotbar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(0, 64), AutomaticSize = Enum.AutomaticSize.X, Visible = false, Parent = screen })
	UI.list(hotbar, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
end

local function refreshHotbar()
	local list = tools()
	hotbar.Visible = #list > 0
	local wanted = { "Fists" }
	for _, t in ipairs(list) do
		table.insert(wanted, t:GetAttribute("Weapon"))
	end
	local equipped = ctx.World.Equipped and ctx.World.Equipped() or "Fists"
	for k, id in ipairs(wanted) do
		local slot = slots[k]
		if not slot then
			local button = UI.button(hotbar, "", { Size = UDim2.fromOffset(60, 60), Color = C.Panel2, LayoutOrder = k }, function()
				Hud.Equip(k)
			end)
			local icon = UI.Icons.Glyph(button, "fist", 38, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Hole = C.Panel2 })
			local num = UI.new("TextLabel", { BackgroundColor3 = C.Bg, Text = tostring(k), TextColor3 = C.Gold, Font = UI.Black, TextSize = 11, Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(3, 3), Parent = button })
			UI.corner(num, 5)
			-- the cooldown sweeps down after each attack
			local cool = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BorderSizePixel = 0, Parent = button })
			UI.corner(cool, 10)
			slot = { Button = button, Icon = icon, Cool = cool }
			slots[k] = slot
		end
		slot.Button.Visible = true
		UI.Icons.Set(slot.Icon, id)
		slot.Id = id
		local selected = id == equipped
		slot.Button.BackgroundColor3 = if selected then UI.rgb(120, 40, 50) else C.Panel2
	end
	for k = #wanted + 1, #slots do
		slots[k].Button.Visible = false
	end
end

--------------------------------------------------------------------------------
-- The target card: who you're facing up close
--------------------------------------------------------------------------------
local card
local function buildTargetCard()
	card = UI.panel(screen, { Name = "Target", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(320, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Radius = 16 })
	UI.new("UIScale", { Parent = card })
	UI.pad(card, 10, 8, 14, 10, 14)
	UI.list(card, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center)
	refs.TargetName = UI.text(card, "", 18, UI.Title, C.White, { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	refs.TargetSub = UI.text(card, "", 12, UI.Font, C.Sub, { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2 })
	local hpRow
	hpRow, refs.TargetHPSet = UI.bar(card, C.Red, 8, { LayoutOrder = 3 })
	refs.TargetHP = hpRow
	refs.TargetKeys = UI.text(card, "", 12, UI.Bold, C.Gold, { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4 })
end

local lastTarget
local function updateTarget(root)
	if not root or ctx.Panels.InDialogue() or player:GetAttribute("JailUntil") then
		card.Visible = false
		lastTarget = nil
		return
	end
	local look = root.CFrame.LookVector
	local best, bestScore = nil, math.huge
	for _, model in ipairs(CollectionService:GetTagged("Citizen")) do
		local r = model:FindFirstChild("HumanoidRootPart")
		if r then
			local d = r.Position - root.Position
			local flat = Vector3.new(d.X, 0, d.Z)
			if flat.Magnitude < 11 and flat.Magnitude > 0.1 and look:Dot(flat.Unit) > 0.45 then
				local score = flat.Magnitude - look:Dot(flat.Unit) * 3
				if score < bestScore then
					best, bestScore = model, score
				end
			end
		end
	end
	card.Visible = best ~= nil
	if not best then
		lastTarget = nil
		return
	end
	if best ~= lastTarget then
		lastTarget = best
		local scale = card:FindFirstChildOfClass("UIScale")
		scale.Scale = 0.85
		UI.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	local stage = best:GetAttribute("Stage") or ""
	local job = best:GetAttribute("Job") or ""
	local role = if job ~= "" then job elseif (best:GetAttribute("School") or "") ~= "" then best:GetAttribute("School") else stage
	refs.TargetName.Text = UI.moodEmoji(best:GetAttribute("Mood") or 60) .. "  " .. (best:GetAttribute("DisplayName") or best.Name)
	refs.TargetSub.Text = (best:GetAttribute("Age") or "?") .. " · " .. role .. "  ·  " .. (best:GetAttribute("Activity") or "")
	local hp, maxHp = best:GetAttribute("HP"), best:GetAttribute("MaxHP")
	refs.TargetHP.Visible = hp ~= nil and maxHp ~= nil
	if hp and maxHp then
		refs.TargetHPSet(hp / maxHp, if hp / maxHp > 0.5 then C.Gold else C.Red)
	end
	local kid = stage == "Baby" or stage == "Toddler" or stage == "Child" or stage == "Teen"
	local ko = best:GetAttribute("KnockedOut")
	refs.TargetKeys.Text = if ko then "💫 Knocked out" elseif kid then "[E] Talk" else "[E] Talk   [G] Pickpocket   [F] Attack"
	card.Position = UDim2.new(0.5, 0, 0, if refs.Jail.Visible then 90 else 16)
end

--------------------------------------------------------------------------------
-- Low health: the screen glows red
--------------------------------------------------------------------------------
local lastHurt = 0
function Hud.Hurt()
	lastHurt = os.clock()
end

local slowExtras = 0
function Hud.UpdateExtras(dt, root)
	slowExtras += dt
	-- cooldown sweep on the selected weapon
	local w = ctx.World.Cooldown and ctx.World.Cooldown()
	for _, slot in ipairs(slots) do
		if slot.Button.Visible then
			slot.Cool.Size = UDim2.fromScale(1, if w and slot.Id == w.Id then w.Left else 0)
		end
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local frac = if humanoid then humanoid.Health / math.max(1, humanoid.MaxHealth) else 1
	local stars = player:GetAttribute("Wanted") or 0
	if stars == 0 and not player:GetAttribute("Hiding") then
		local hurt = math.max(0, 1 - (os.clock() - lastHurt) / 0.4)
		local low = if frac < 0.35 and frac > 0 then 0.35 + (math.sin(os.clock() * 4) + 1) * 0.15 else 0
		local glow = math.max(hurt * 0.8, low)
		refs.EdgeStroke.Color = C.Red
		refs.EdgeStroke.Transparency = 1 - glow
	end
	if slowExtras >= 0.1 then
		slowExtras = 0
		refreshHotbar()
		updateTarget(root)
	end
end

-- the stamina bar (called by Moves every frame)
local lastStam = -1
function Hud.SetStamina(frac, level, xpFrac, sprinting, exhausted, boosted)
	if not refs.StaminaFill then
		return
	end
	frac = math.clamp(frac, 0, 1)
	if math.abs(frac - lastStam) > 0.004 then
		lastStam = frac
		refs.StaminaFill.Size = UDim2.fromScale(frac, 1)
	end
	refs.StaminaFill.BackgroundColor3 = if exhausted then C.Red elseif boosted then C.Gold elseif sprinting then UI.rgb(90, 230, 210) else C.Teal
	refs.FitLevel.Text = "Lv " .. level
	refs.FitXP.Size = UDim2.fromScale(math.clamp(xpFrac, 0, 1), 1)
	local pulse = exhausted and (os.clock() * 4) % 1 < 0.5
	refs.StaminaPanel.BackgroundTransparency = if pulse then 0.35 else 0.08
end

function Hud.Start(context)
	ctx = context
	cityState = ReplicatedStorage:WaitForChild("CityState")
	build()
	buildGoals(screen:FindFirstChild("LeftColumn"))
	buildHotbar()
	buildTargetCard()
	Hud.SetCoins(player:GetAttribute("Coins") or 0)
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		Hud.SetCoins(player:GetAttribute("Coins") or 0, true)
	end)
	player:GetAttributeChangedSignal("Wanted"):Connect(refreshWanted)
	player:GetAttributeChangedSignal("JailUntil"):Connect(function()
		local j = player:GetAttribute("JailUntil")
		refs.JailTotal = if j then j - workspace:GetServerTimeNow() else nil
	end)
	refreshWanted()
	refreshCity()
	local slow, dots = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		frame(dt)
		slow += dt
		dots += dt
		if slow >= 0.25 then
			slow = 0
			refreshCity()
		end
		if dots >= 0.5 then
			dots = 0
			pcall(dotsTick)
		end
	end)
end

return Hud
