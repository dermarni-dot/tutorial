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
				Text = placeInfo and placeInfo.emoji or "📍",
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
	UI.text(row, icon, 13, UI.Font, C.Text, { Size = UDim2.fromOffset(18, 18), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(row, name, 12, UI.Bold, C.Sub, { Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(74, 18) })
	local bar, set = UI.bar(row, color, 8, { Position = UDim2.new(0, 98, 0.5, -4), Size = UDim2.new(1, -134, 0, 8) })
	local value = UI.text(row, "50", 12, UI.Bold, C.Text, { Position = UDim2.new(1, -32, 0, 0), Size = UDim2.fromOffset(32, 18), TextXAlignment = Enum.TextXAlignment.Right })
	return set, value
end

local function actionButton(parent, emoji, label, key, order, onClick, color)
	local button = UI.button(parent, "", { Size = UDim2.fromOffset(66, 62), Color = color or C.Panel2, LayoutOrder = order }, onClick)
	UI.text(button, emoji, 24, UI.Font, C.White, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 5), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(button, label, 11, UI.Bold, C.Sub, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 36), TextXAlignment = Enum.TextXAlignment.Center })
	if key and not UserInputService.TouchEnabled then
		local keycap = UI.new("TextLabel", { BackgroundColor3 = C.Bg, Text = key, TextColor3 = C.Gold, Font = UI.Black, TextSize = 10, Size = UDim2.fromOffset(16, 16), Position = UDim2.new(1, -18, 0, 2), Parent = button })
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
	local card = UI.panel(screen, { Name = "Clock", Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = 16 })
	UI.pad(card, 12, 10, 14, 12, 14)
	UI.list(card, Enum.FillDirection.Vertical, 6)
	local top = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, Parent = card })
	refs.Time = UI.text(top, "8:00", 36, UI.Title, C.White, { Size = UDim2.fromOffset(110, 40), AutomaticSize = Enum.AutomaticSize.X })
	refs.AmPm = UI.text(top, "AM", 15, UI.Bold, C.Sub, { Position = UDim2.fromOffset(100, 6), Size = UDim2.fromOffset(40, 18) })
	refs.Sky = UI.text(top, "☀️", 30, UI.Font, C.White, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(40, 36), TextXAlignment = Enum.TextXAlignment.Right })
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
	UI.text(coins, "🪙", 22, UI.Font, C.White, { Size = UDim2.fromOffset(26, 30), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	refs.Coins = UI.text(coins, "100", 22, UI.Title, C.Gold, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), LayoutOrder = 2 })
	local wanted = UI.panel(right, { Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Radius = 18, Visible = false })
	UI.pad(wanted, 0, 0, 12, 0, 12)
	UI.list(wanted, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	refs.Wanted, refs.Stars = wanted, {}
	refs.WantedEye = UI.text(wanted, "👀", 16, UI.Font, C.White, { Size = UDim2.fromOffset(22, 26), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 0 })
	for k = 1, 5 do
		refs.Stars[k] = UI.text(wanted, "★", 22, UI.Black, C.Dim, { Size = UDim2.fromOffset(22, 26), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = k })
	end
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
	actionButton(bar, "🗺️", "Map", "M", 1, function()
		ctx.Panels.Map.Toggle()
	end)
	actionButton(bar, "👥", "People", "P", 2, function()
		ctx.Panels.Directory.Toggle()
	end)
	actionButton(bar, "🗳️", "Vote", "V", 3, function()
		ctx.Panels.Vote.Toggle()
	end)
	refs.SpeechButton = actionButton(bar, "🎤", "Speech", "B", 4, function()
		ctx.Panels.Speech.Toggle()
	end, C.Panel2)
	refs.MayorButton = actionButton(bar, "🏛️", "Mayor", "N", 5, function()
		ctx.Panels.Mayor.Toggle()
	end, UI.rgb(120, 90, 30))
	refs.MayorButton.Visible = false
	actionButton(bar, "👊", "Punch", "F", 6, function()
		ctx.World.Punch()
	end, UI.rgb(110, 40, 48))
	actionButton(bar, "⚙️", "Settings", nil, 7, function()
		ctx.Panels.Settings.Toggle()
	end)
	actionButton(bar, "❓", "Help", "H", 8, function()
		ctx.Panels.Help.Toggle()
	end)

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
	refs.Sky.Text = skyIcon(h)
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
		refs.WantedEye.Text = if seen then "👀" else "🫥"
		for k = 1, stars do
			refs.Stars[k].TextColor3 = if seen and math.floor(t * 5) % 2 == 0 then C.Red else C.Gold
		end
	else
		refs.EdgeStroke.Transparency = 1
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
	refs.Hint.Visible = root ~= nil and podium ~= nil and (root.Position - podium).Magnitude < 14 and not ctx.Panels.Speech.IsOpen()
	refs.SpeechButton.BackgroundColor3 = if refs.Hint.Visible then UI.rgb(130, 95, 20) else C.Panel2
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

function Hud.Start(context)
	ctx = context
	cityState = ReplicatedStorage:WaitForChild("CityState")
	build()
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
