-- ClientMain: wires the client together - main menu at join, the gym HUD (player plate, condition
-- meters, quick actions), gym prompts, profile updates, fight / sparring results, retirement, the
-- city dressing and the time of day (your energy is your daylight).
-- The trophy case is drawn by GymVisuals.Refresh (GymFacility's LocalTrophies).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme
local Modules = script.Parent:WaitForChild("BoxerClient")
local State = require(Modules:WaitForChild("State"))
local Settings = require(Modules:WaitForChild("Settings"))
Settings.Start(State)
local GymVisuals = require(Modules:WaitForChild("GymVisuals"))
local Creator = require(Modules:WaitForChild("Creator"))
local Hub = require(Modules:WaitForChild("Hub"))
local Activities = require(Modules:WaitForChild("Activities"))
local Services = require(Modules:WaitForChild("Services"))
local Ambience = require(Modules:WaitForChild("Ambience"))
local Flags = require(Modules:WaitForChild("Flags"))
-- the title screen is optional too: without it a new player goes straight to the creator
local okMenu, MainMenu = pcall(function()
	return require(Modules:WaitForChild("MainMenu", 10))
end)
if not (okMenu and type(MainMenu) == "table") then
	warn("[ClientMain] MainMenu unavailable:", MainMenu)
	MainMenu = nil
end
Ambience.Start()
-- city dressing (homes, fans, billboards, stores): optional, so a broken city never takes the HUD
-- and the gym prompts down with it
local okCityMod, CityVisuals = pcall(function()
	return require(Modules:WaitForChild("CityVisuals", 10))
end)
if okCityMod and type(CityVisuals) == "table" then
	pcall(CityVisuals.Start)
else
	warn("[ClientMain] CityVisuals unavailable:", CityVisuals)
	CityVisuals = nil
end
-- anatomy meshes (EditableMesh characters, ANATOMY_CONTRACTS.md): optional; any failure keeps the
-- part-built look
local okAnatomy, AnatomyClient = pcall(function()
	return require(Modules:WaitForChild("AnatomyClient", 10))
end)
if okAnatomy and type(AnatomyClient) == "table" then
	pcall(AnatomyClient.Start)
else
	warn("[ClientMain] AnatomyClient unavailable:", AnatomyClient)
end
-- PvP (challenges, Find Match, the PvP record): optional like the city, a failure never takes the HUD down
local okPvP, PvPClient = pcall(function()
	return require(Modules:WaitForChild("PvP", 10))
end)
if okPvP and type(PvPClient) == "table" then
	local okStart, errStart = pcall(PvPClient.Start)
	if not okStart then
		warn("[ClientMain] PvP start:", errStart)
	end
else
	warn("[ClientMain] PvP unavailable:", PvPClient)
	PvPClient = nil
end
local gui = State.gui
local rec = State.rec

------------------------------------------------------------------------
-- HUD: the player plate (top left)
------------------------------------------------------------------------
local hud = UI.Frame(gui, { Name = "HUD", Size = UDim2.new(0, 360, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(20, 16), Visible = false })
UI.Glass(hud, { transparency = 0.16 })
UI.New("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = hud })
UI.List(hud, 6)
local stripe = UI.Frame(hud, { Name = "Stripe", Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = T.gold, LayoutOrder = 0 })
UI.Gradient(stripe, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }))
local head = UI.Frame(hud, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
local flagHolder = UI.Frame(head, { Name = "FlagHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(30, 20), Position = UDim2.fromOffset(0, 10) })
local hudName = UI.Title(head, "", { Name = "Name", TextSize = 28, Position = UDim2.fromOffset(40, 2), Size = UDim2.new(1, -112, 0, 34), TextTruncate = Enum.TextTruncate.AtEnd })
local ovrBox = UI.Frame(head, { Name = "OVR", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(62, 40), BackgroundColor3 = T.ink, BackgroundTransparency = 0.3 })
UI.Corner(ovrBox, UI.R.md)
UI.Stroke(ovrBox, T.gold, 1, 0.35)
local hudOvr = UI.Text(ovrBox, "", { Face = "number", TextSize = 24, TextColor3 = T.gold, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 1), AutomaticSize = Enum.AutomaticSize.None,
	TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
UI.Text(ovrBox, "OVR", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -14), AutomaticSize = Enum.AutomaticSize.None,
	TextXAlignment = Enum.TextXAlignment.Center })
local hudTier = UI.Text(hud, "", { Name = "Tier", Font = T.semi, TextSize = 12, TextColor3 = T.gold, LayoutOrder = 2, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
local nums = UI.Frame(hud, { Name = "Numbers", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 3 })
UI.List(nums, 8, true)
local _, recVal, recCap = UI.Stat(nums, "0-0-0", "RECORD", { Size = UDim2.new(0.5, -4, 1, 0), valueSize = 24, order = 1, scaled = true })
local _, moneyVal = UI.Stat(nums, "$0", "PURSE", { Size = UDim2.new(0.5, -4, 1, 0), valueSize = 24, order = 2, valueColor = T.gold, scaled = true })
local bars = UI.Frame(hud, { Name = "Meters", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
UI.List(bars, 5)
local function miniBar(label, color, order)
	local f = UI.Frame(bars, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order })
	UI.Text(f, label, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Size = UDim2.new(0, 84, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local _, set = UI.Bar(f, { Position = UDim2.new(0, 86, 0.5, -3), Size = UDim2.new(1, -126, 0, 6) }, color)
	local val = UI.Text(f, "", { Face = "number", TextSize = 15, Position = UDim2.new(1, -34, 0, 0), Size = UDim2.new(0, 34, 1, 0), TextXAlignment = Enum.TextXAlignment.Right,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	return function(v, c)
		set(v / 100, c)
		val.Text = tostring(math.floor(v))
	end
end
local setEnergy = miniBar("ENERGY", T.gold, 1)
local setHydration = miniBar("HYDRATION", T.cyan, 2)
local setNutrition = miniBar("NUTRITION", T.green, 3)
local setFatigue = miniBar("FATIGUE", T.orange, 4)
-- the phone plate: the four meters as one line of chips under the name
local condStrip = UI.Frame(hud, { Name = "CondStrip", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 4, Visible = false })
UI.List(condStrip, 6, true)
local condChips = {}
for i, k in ipairs({ "ENERGY", "WATER", "FOOD", "FATIGUE" }) do
	local f, t = UI.Chip(condStrip, k, T.sub, { order = i, h = 26, TextSize = 13 })
	condChips[k] = { frame = f, text = t }
end
local function setCond(k, v, color)
	local c = condChips[k]
	c.text.Text = string.format("%s %d", k, math.floor(v))
	c.text.TextColor3 = color
	c.frame.BackgroundColor3 = T.bg:Lerp(color, 0.12)
	local st = c.frame:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = color
	end
end
local campBox = UI.Frame(hud, { Name = "Camp", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.4, LayoutOrder = 5 })
UI.Corner(campBox, UI.R.md)
UI.New("UIPadding", { PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = campBox })
local hudCamp = UI.Text(campBox, "", { Font = T.semi, TextSize = 12, TextColor3 = T.sub })
local hudWarn = UI.Text(hud, "", { Font = T.semi, TextSize = 12, TextColor3 = T.red, LayoutOrder = 6, Visible = false })

-- quick actions under the plate
local hudButtons = UI.Frame(gui, { Name = "HudButtons", BackgroundTransparency = 1, Size = UDim2.fromOffset(360, 40), Position = UDim2.fromOffset(20, 16), Visible = false })
UI.List(hudButtons, 6, true)
-- key: the keyboard key's cap; padKey: the gamepad button shown on the cap instead while a pad is in use
-- (the button widens to fit the longer name, "D-DOWN")
local function hudButton(text, key, w, color, fn, order, padKey)
	local b = UI.Button(hudButtons, "", { Name = text, Size = UDim2.fromOffset(w, 40), BackgroundColor3 = color or T.panel2, BackgroundTransparency = color and 0 or 0.15, LayoutOrder = order }, fn)
	local dark = color == T.gold
	local label = UI.Text(b, text, { Face = "displayMed", TextSize = 17, TextColor3 = dark and T.ink or T.text, Size = UDim2.new(1, key and -26 or 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	if key then
		local cap = UI.Frame(b, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = dark and T.ink or T.panel, BackgroundTransparency = 0.2 })
		UI.Corner(cap, 4)
		local capText = UI.Text(cap, key, { Font = T.semi, TextSize = 11, TextColor3 = dark and T.gold or T.sub, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
		if padKey then
			UI.BindHint(capText, function(mode)
				local t = key
				if mode == "gamepad" and UI.Gamepad then
					t = UI.Gamepad.Short(padKey)
				end
				local capW = math.max(20, 8 + 7 * #t)
				cap.Size = UDim2.fromOffset(capW, 20)
				label.Size = UDim2.new(1, -(capW + 6), 1, 0)
				b.Size = UDim2.fromOffset(w + capW - 20, 40)
				return t
			end)
		end
	end
	return b
end
hudButton("MENU", "M", 92, nil, function()
	if MainMenu then
		MainMenu.Open()
	end
end, 1, Enum.KeyCode.DPadDown)
hudButton("CAREER HUB", "H", 140, T.gold, function()
	Hub.Toggle()
end, 2, Enum.KeyCode.DPadUp)
hudButton("TRAIN", nil, 60, nil, function()
	Hub.Open("Training")
end, 3)
hudButton("SLEEP", nil, 56, nil, function()
	State.open.Sleep()
end, 4)
if PvPClient then
	hudButton("PVP", "P", 72, T.red, function()
		PvPClient.Toggle()
	end, 5, Enum.KeyCode.DPadRight)
end
local hint = UI.Frame(gui, { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = T.bg, BackgroundTransparency = 0.25, Visible = false })
UI.Corner(hint, 16)
UI.Stroke(hint, Color3.new(1, 1, 1), 1, 0.88)
local hintText = UI.Text(hint, "Walk up to any gym station and press E (or tap) to train.", { Font = T.semi, TextSize = 13, TextColor3 = T.text, Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
UI.Pad(hintText, 0, 18)

-- the first-sessions hint names the prompt button of the device in use (ProximityPrompts take E on a
-- keyboard and X / SQUARE on a gamepad by default)
local hudCompact = nil
local function gymHint(mode)
	if mode == "gamepad" and UI.Gamepad then
		return string.format("Walk up to any gym station and press %s to train.  %s: Career Hub", UI.Gamepad.Label(Enum.KeyCode.ButtonX), UI.Gamepad.Short(Enum.KeyCode.DPadUp))
	elseif mode == "touch" or hudCompact then
		return "Walk up to a gym station and tap (or press E) to train."
	end
	return "Walk up to any gym station and press E (or tap) to train."
end

-- a phone (short canvas): the plate collapses to the name, OVR and one line of condition chips; the
-- quick actions sit on the bottom edge (above the device's safe area) with the hint above them
local function layoutHud()
	local s = UI.ScaleOf(hud)
	local canvas = UI.CanvasSize(gui)
	local compact = canvas.Y < 640
	if compact ~= hudCompact then
		hudCompact = compact
		hud.Size = UDim2.new(0, compact and 440 or 360, 0, 0)
		hudTier.Visible = not compact
		nums.Visible = not compact
		bars.Visible = not compact
		campBox.Visible = not compact
		condStrip.Visible = compact
		UI.BindHint(hintText, gymHint)
	end
	if compact then
		local bottom = 8
		local ok, _, br = pcall(function()
			return GuiService:GetGuiInset()
		end)
		if ok and typeof(br) == "Vector2" then
			bottom += br.Y / math.max(0.1, s)
		end
		hudButtons.AnchorPoint = Vector2.new(0, 1)
		hudButtons.Position = UDim2.new(0, 16, 1, -bottom)
		hint.AnchorPoint = Vector2.new(0, 1)
		hint.Position = UDim2.new(0, 16, 1, -(bottom + 40 + 8))
	else
		hudButtons.AnchorPoint = Vector2.new(0, 0)
		hudButtons.Position = UDim2.new(0, 20, 0, 16 + hud.AbsoluteSize.Y / s + 10)
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -18)
	end
end
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
gui:GetAttributeChangedSignal("UIScale"):Connect(layoutHud)

------------------------------------------------------------------------
-- Time of day follows your energy (morning after sleep, night when you're spent)
------------------------------------------------------------------------
local clockTween
local function updateDaylight(P)
	local busy = State.busy()
	if State.inFight() or busy == "fight" or busy == "spar" or not P.condition then
		return
	end
	local goal = 7 + (1 - math.clamp(P.condition.energy / 100, 0, 1)) * 14
	if clockTween then
		clockTween:Cancel()
	end
	clockTween = TweenService:Create(Lighting, TweenInfo.new(2.5, Enum.EasingStyle.Sine), { ClockTime = goal })
	clockTween:Play()
end

------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------
local METHOD = { KO = "Knockout", TKO = "Technical Knockout", RTD = "Corner Retirement", UD = "Unanimous Decision", SD = "Split Decision", MD = "Majority Decision", Draw = "Draw", Stopped = "Stopped by the coach" }

-- a two-sided comparison row: value | caption | value, with bars growing toward the middle
-- you (red corner, left) against the opponent (blue corner, right): the corner colours of the HUD,
-- the tape and the scorecards
local function versusRow(parent, caption, a, b, fmt, order)
	local f = UI.Frame(parent, { Name = "Versus", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order })
	local total = math.max(1, (tonumber(a) or 0) + (tonumber(b) or 0))
	local na, nb = tonumber(a) or 0, tonumber(b) or 0
	UI.Text(f, fmt and fmt(a) or tostring(a), { Face = "number", TextSize = 22, TextColor3 = na > nb and T.text or T.sub, Size = UDim2.new(0.18, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	UI.Text(f, fmt and fmt(b) or tostring(b), { Face = "number", TextSize = 22, TextColor3 = nb > na and T.text or T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.18, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	UI.Text(f, caption, { Font = T.semi, TextSize = 12, TextColor3 = T.sub, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.3, 0, 0, 14),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	local la = UI.Frame(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -4, 0, 19), Size = UDim2.new(0.3 * na / total, 0, 0, 5), BackgroundColor3 = T.red })
	UI.Corner(la, 2)
	local lb = UI.Frame(f, { Position = UDim2.new(0.5, 4, 0, 19), Size = UDim2.new(0.3 * nb / total, 0, 0, 5), BackgroundColor3 = T.blue })
	UI.Corner(lb, 2)
	return f
end

local function showResult(data)
	local res = data.result
	local shade
	local function close()
		State.windows.Result = nil
		if shade then
			shade:Destroy()
		end
	end
	local win, body
	shade, win, body = UI.Window(gui, "Result", 760, 700, nil, { footer = 64, onClose = close, accent = res.outcome == "win" and T.gold or (res.outcome == "loss" and T.red or T.sub) })
	-- a modal result: the HUD plate stays out of the picture until it is dismissed
	State.HideHud("Result", true)
	State.windows.Result = close -- another big window (Hub, barber...) closes it
	shade.Destroying:Connect(function()
		State.HideHud("Result", false)
	end)
	local col = res.outcome == "win" and T.gold or (res.outcome == "loss" and T.red or T.text)
	local title = res.outcome == "win" and "VICTORY" or (res.outcome == "loss" and "DEFEAT" or "DRAW")
	body.Position = UDim2.fromOffset(28, 150)
	body.Size = UDim2.new(1, -56, 1, -222)
	UI.Kicker(win, (data.venue and data.venue ~= "") and ("FIGHT NIGHT  ·  " .. data.venue) or "FIGHT NIGHT", T.sub, { Position = UDim2.fromOffset(28, 22), Size = UDim2.new(1, -56, 0, 18) })
	local big = UI.Title(win, title, { TextSize = 84, TextColor3 = col, Position = UDim2.fromOffset(24, 38), Size = UDim2.new(1, -48, 0, 88), TextTransparency = 1 })
	UI.Tween(big, { TextTransparency = 0 }, UI.Motion.slow)
	if res.outcome == "win" then
		-- a gradient multiplies the text colour: white text takes the gold ramp as is
		big.TextColor3 = Color3.new(1, 1, 1)
		UI.Gradient(big, { Color3.fromRGB(255, 240, 190), T.gold, T.goldDeep }, 90)
	end
	UI.Text(win, string.format("%s  ·  ROUND %d  ·  vs %s", string.upper(METHOD[res.method] or tostring(res.method)), res.round or 0, string.upper(data.opp or "?")),
		{ Font = T.semi, TextSize = 15, TextColor3 = T.text, Position = UDim2.fromOffset(28, 122), Size = UDim2.new(1, -56, 0, 20), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd })
	if res.reason then
		UI.Line(body, res.reason, { TextColor3 = T.sub, TextSize = 14 })
	end
	-- the three judges
	if res.cards and res.cards[1] and (res.cards[1][1] + res.cards[1][2]) > 0 then
		UI.Kicker(body, "SCORECARDS  (YOU - OPPONENT)", T.sub)
		local row = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64) })
		UI.List(row, 10, true)
		for j, c in ipairs(res.cards) do
			-- the corner that took the judge's card: red (you) or blue (the opponent)
			local f = UI.Stat(row, string.format("%d-%d", c[1], c[2]), "JUDGE " .. j, { Size = UDim2.new(1 / #res.cards, -8, 1, 0), order = j, valueSize = 30,
				valueColor = T.text, align = Enum.TextXAlignment.Center })
			if c[1] ~= c[2] then
				local mark = UI.Frame(f, { Name = "Corner", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -24, 0, 3), BackgroundColor3 = c[1] > c[2] and T.red or T.blue })
				UI.Corner(mark, 2)
			end
		end
	end
	if res.landed then
		UI.Kicker(body, "FIGHT STATS  ·  RED = YOU, BLUE = OPPONENT", T.sub)
		local stats = UI.Card(body, { pad = 16 })
		versusRow(stats, "PUNCHES LANDED", res.landed or 0, res.oppLanded or 0, nil, 1)
		versusRow(stats, "PUNCHES THROWN", res.thrown or res.landed or 0, res.oppThrown or 0, nil, 2)
		local accA = (res.thrown or 0) > 0 and math.floor((res.landed or 0) / res.thrown * 100 + 0.5) or 0
		local accB = (res.oppThrown or 0) > 0 and math.floor((res.oppLanded or 0) / res.oppThrown * 100 + 0.5) or 0
		versusRow(stats, "ACCURACY", accA, accB, function(v)
			return v .. "%"
		end, 3)
		versusRow(stats, "KNOCKDOWNS", res.kdFor or 0, res.kdAgainst or 0, nil, 4)
	end
	if res.weighIn and res.weighIn.over and res.weighIn.over > 0 then
		UI.Line(body, string.format("Missed weight by %.1f lbs.", res.weighIn.over), { TextColor3 = T.red, TextSize = 14, Font = T.semi })
	end
	if res.simulated then
		UI.Line(body, "Simulated fight", { TextColor3 = T.sub, TextSize = 13 })
	end
	local purse = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58) })
	UI.Kicker(purse, "EARNINGS", T.green, { Size = UDim2.new(1, 0, 0, 18) })
	UI.Title(purse, Config.Money(data.earnings or 0), { TextSize = 38, TextColor3 = T.green, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 42) })
	for _, n in ipairs(data.notes or {}) do
		local bigNote = n:find("CHAMPION") or n:find("PRO") or n:find("LEGEND") or n:find("TOP 10") or n:find("Promoted")
		UI.Line(body, n, { TextColor3 = bigNote and T.gold or T.text, Font = bigNote and T.semi or T.font, TextSize = 14 })
	end
	UI.PadStart(UI.Button(win, "CONTINUE", { Size = UDim2.new(0, 260, 0, 48), Position = UDim2.new(0.5, -130, 1, -62), BackgroundColor3 = T.gold }, close))
end
State.open.Result = showResult

local function showSparResult(data)
	local res = data.result
	local tr = data.training or {}
	local shade
	local function close()
		State.windows.SparResult = nil
		if shade then
			shade:Destroy()
		end
	end
	local win, body
	shade, win, body = UI.Window(gui, "SparResult", 620, 560, "SPARRING  ·  " .. string.upper(data.intensity or ""), { footer = 60, kicker = "SESSION COMPLETE", accent = T.blue, onClose = close })
	State.HideHud("SparResult", true)
	State.windows.SparResult = close
	shade.Destroying:Connect(function()
		State.HideHud("SparResult", false)
	end)
	-- the session's verdict first: a spar can be won, lost (on the coach's card or stopped) or even
	local verdict = res.outcome == "win" and "YOU WON THE SESSION" or (res.outcome == "loss" and (res.method == "Stopped" and "STOPPED BY THE COACH" or "YOU LOST THE SESSION") or "AN EVEN SESSION")
	UI.Line(body, verdict, { Name = "Verdict", Font = T.bold, TextSize = 22, TextColor3 = res.outcome == "win" and T.gold or (res.outcome == "loss" and T.red or T.blue) })
	UI.Line(body, string.format("Partner: %s  ·  %s", data.partner or "?", res.outcome == "win" and "you got the better of it" or (res.outcome == "loss" and "they got the better of it" or "an even session")),
		{ Font = T.semi, TextSize = 15 })
	if res.reason and res.reason ~= "Session complete" then
		UI.Line(body, tostring(res.reason), { TextColor3 = T.sub, TextSize = 13 })
	end
	local stats = UI.Card(body, { pad = 16 })
	versusRow(stats, "PUNCHES LANDED", res.landed or 0, res.oppLanded or 0, nil, 1)
	versusRow(stats, "PUNCHES THROWN", res.thrown or 0, res.oppThrown or 0, nil, 2)
	versusRow(stats, "KNOCKDOWNS", res.kdFor or 0, res.kdAgainst or 0, nil, 3)
	UI.StatRow(body, "SESSION QUALITY", math.floor((data.quality or 1) / 1.45 * 100), 100, T.gold, string.format("%d%%", math.floor((data.quality or 1) / 1.45 * 100)))
	local parts = {}
	for _, k in ipairs(Config.StatKeys) do
		local g = tr.gains and tr.gains[k]
		if g and g > 0.001 then
			table.insert(parts, string.format("+%.2f %s", g, Config.StatNames[k]))
		end
	end
	if #parts > 0 then
		UI.Line(body, table.concat(parts, "   "), { TextColor3 = T.green, Font = T.semi, TextSize = 14 })
	end
	for _, n in ipairs(tr.notes or {}) do
		UI.Line(body, n, { TextColor3 = n:find("INJURY") and T.red or T.sub, TextSize = 13 })
	end
	UI.PadStart(UI.Button(win, "CONTINUE", { Size = UDim2.new(0, 240, 0, 46), Position = UDim2.new(0.5, -120, 1, -58), BackgroundColor3 = T.gold }, close))
end

State.FightRemote.OnClientEvent:Connect(function(msg)
	if msg.t == "result" then
		task.delay(0.5, showResult, msg)
	elseif msg.t == "sparResult" then
		task.delay(0.4, showSparResult, msg)
	elseif msg.t == "aborted" then
		State.toast(msg.spar and "Sparring session ended." or "The fight was called off.", T.red)
	end
end)

------------------------------------------------------------------------
-- Retirement
------------------------------------------------------------------------
local wasRetired = false
local function showRetired()
	local res = State.req("GetLegacy")
	if not res.ok then
		return
	end
	local P = State.P
	local shade
	local win, body
	shade, win, body = UI.Window(gui, "Retired", 820, 680, (res.legacy.hallOfFame and "HALL OF FAME INDUCTION" or "CAREER OVER"), { footer = 64, kicker = "THE FINAL BELL" })
	local c = UI.Card(body, { stroke = T.gold })
	UI.Line(c, string.format("%s \"%s\" retires at %d", P.identity.name, P.identity.nickname, P.identity.age), { Font = T.bold, TextSize = 26 })
	UI.Line(c, string.format("Final record %s  ·  Amateur %s", rec(P.record), rec(P.amateurRecord)), { TextSize = 15 })
	UI.Line(c, string.format("World titles won %d  ·  Title defenses %d  ·  Peak tier: %s", P.titlesWon, P.defenses, P.tierName), { TextSize = 15 })
	if res.legacy.hallOfFame then
		UI.Line(c, "The boxing world honors you as one of the all-time greats. Welcome to the Hall of Fame.", { TextColor3 = T.gold, Font = T.semi })
	end
	Hub.LegacyBody(body, res.legacy, res.pastCareers)
	local newCareer = UI.Button(win, "START A NEW CAREER", { Size = UDim2.new(0, 300, 0, 48), Position = UDim2.new(0.5, -150, 1, -62), BackgroundColor3 = T.gold }, function()
		local r = State.req("NewCareer")
		if r.ok then
			shade:Destroy()
			wasRetired = false
		end
	end)
	UI.PadStart(newCareer)
end

------------------------------------------------------------------------
-- Profile updates
------------------------------------------------------------------------
local menuShownOnce = false
local lastFlag
-- the server is retrying a failed DataStore read: say so once (the career is not lost)
local loadRetryShown = false
local function refresh()
	local P = State.P
	if not P or P.loading then
		if P and P.loadRetry and not loadRetryShown then
			loadRetryShown = true
			State.toast("Couldn't reach Roblox's save servers. Retrying... your career is safe.", T.red, 8)
		end
		return
	end
	local fight = State.inFight()
	if not P.created then
		hud.Visible, hudButtons.Visible, hint.Visible = false, false, false
		if not Creator.IsOpen() and not gui:FindFirstChild("Retired") then
			-- a new player meets the title screen first (NEW CAREER opens the creator)
			if MainMenu and not menuShownOnce then
				menuShownOnce = true
				MainMenu.Open()
			elseif not (MainMenu and MainMenu.IsOpen()) then
				Creator.Open()
			end
		end
		return
	end
	if P.retired then
		hud.Visible, hudButtons.Visible, hint.Visible = false, false, false
		Hub.Close()
		if MainMenu and MainMenu.IsOpen() then
			MainMenu.Close()
		end
		if not wasRetired or not gui:FindFirstChild("Retired") then
			wasRetired = true
			showRetired()
		end
		return
	end
	wasRetired = false
	if not menuShownOnce then
		menuShownOnce = true
		-- the saved settings first (Settings listens to State.Changed too, but handler order is not
		-- guaranteed): "show the menu at start" must be the player's saved choice
		Settings.Load(P)
		if MainMenu and Settings.Get("menuAtStart") and not fight then
			task.defer(MainMenu.Open)
		end
	end
	local busy = State.busy()
	local show = not fight and busy ~= "fight" and busy ~= "spar" and not State.HudHidden()
	hud.Visible, hudButtons.Visible = show, show
	hint.Visible = show and (P.sessions or 0) < 3 and not Activities.Busy()
	hudName.Text = string.upper(P.identity.name)
	hudOvr.Text = tostring(P.overall)
	hudTier.Text = string.format("%s  ·  %s  ·  DAY %d", string.upper(P.className), string.upper(P.tierName), P.day)
	if lastFlag ~= P.identity.nationality then
		lastFlag = P.identity.nationality
		UI.Clear(flagHolder)
		Flags.Draw(flagHolder, P.identity.nationality, { Size = UDim2.fromOffset(30, 20) })
	end
	local r = P.tier == 1 and P.amateurRecord or P.record
	recVal.Text = string.format("%d-%d-%d", r.w, r.l, r.d)
	recCap.Text = P.tier == 1 and "AMATEUR RECORD" or string.format("PRO RECORD  ·  %d KO", r.ko)
	moneyVal.Text = Config.Money(P.money)
	local c = P.condition
	setEnergy(c.energy, c.energy < 25 and T.red or T.gold)
	setHydration(c.hydration, c.hydration < 30 and T.red or T.cyan)
	setNutrition(c.nutrition, c.nutrition < 30 and T.red or T.green)
	setFatigue(c.fatigue, c.fatigue > 70 and T.red or (c.fatigue > 40 and T.orange or T.green))
	setCond("ENERGY", c.energy, c.energy < 25 and T.red or T.gold)
	setCond("WATER", c.hydration, c.hydration < 30 and T.red or T.cyan)
	setCond("FOOD", c.nutrition, c.nutrition < 30 and T.red or T.green)
	setCond("FATIGUE", c.fatigue, c.fatigue > 70 and T.red or (c.fatigue > 40 and T.orange or T.green))
	if P.camp then
		hudCamp.Text = P.camp.daysLeft > 0 and string.format("FIGHT CAMP vs %s  ·  %d DAY%s  ·  %.1f / %d LBS", string.upper(P.camp.offer.opp.name), P.camp.daysLeft, P.camp.daysLeft == 1 and "" or "S", P.weight, P.weightLimit)
			or string.format("FIGHT NIGHT vs %s - OPEN THE CAREER HUB", string.upper(P.camp.offer.opp.name))
		hudCamp.TextColor3 = P.camp.daysLeft > 0 and T.text or T.gold
		campBox.BackgroundColor3 = T.redDeep
	else
		hudCamp.Text = string.format("NO FIGHT BOOKED  ·  %.1f / %d LBS", P.weight, P.weightLimit)
		hudCamp.TextColor3 = T.sub
		campBox.BackgroundColor3 = T.panel2
	end
	local warns = {}
	for _, inj in ipairs(c.injuries or {}) do
		table.insert(warns, inj.name .. " (" .. inj.days .. "d)")
	end
	if c.fatigue > 70 then
		table.insert(warns, "OVERTRAINED")
	end
	hudWarn.Text = table.concat(warns, "  ·  ")
	hudWarn.Visible = #warns > 0
	task.defer(layoutHud)
	GymVisuals.Refresh(P) -- also draws the trophy case, career wall and facility tier (GymFacility)
	if CityVisuals then
		local okCity, errCity = pcall(CityVisuals.Refresh, P)
		if not okCity then
			warn("[ClientMain] city:", errCity)
		end
	end
	updateDaylight(P)
	if Hub.IsOpen() and not Activities.Busy() then
		Hub.Render()
	end
end

State.Changed:Connect(refresh)
State.ProfileRemote.OnClientEvent:Connect(function(data)
	State.SetProfile(data)
end)

player:GetAttributeChangedSignal("InFight"):Connect(function()
	if State.inFight() then
		State.closeAll()
		-- fight night lighting takes over from the gym's time of day
		if clockTween then
			clockTween:Cancel()
			clockTween = nil
		end
	end
	refresh()
end)
player:GetAttributeChangedSignal("Busy"):Connect(function()
	local b = State.busy()
	State.UpdatePrompts()
	if (b == "fight" or b == "spar") and clockTween then
		clockTween:Cancel()
		clockTween = nil
	end
	refresh()
end)

------------------------------------------------------------------------
-- Gym prompts
------------------------------------------------------------------------
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local P = State.P
	if not (P and P.created) or P.retired or State.inFight() then
		return
	end
	local activity = prompt:GetAttribute("Activity")
	local action = prompt:GetAttribute("Action")
	if activity then
		State.open.Activity(activity)
	elseif action == "CareerHub" then
		Hub.Open("Career")
	elseif action == "Barber" then
		Services.Barber()
	elseif action == "Locker" then
		Services.Locker()
	elseif action == "Nutrition" then
		Services.Nutrition()
	elseif action == "Sleep" then
		Services.Sleep()
	elseif action == "Water" then
		Services.Water()
	elseif action == "Flex" then
		-- flex in the gym mirror: each press strikes the next pose of Config.Pump.poses (E's Flex
		-- handler plays it for 3.2 s); you turn to face the glass so the live mirror shows it
		local poses = (Config.Pump and Config.Pump.poses) or { "flex_most" }
		local n = (prompt:GetAttribute("FlexIdx") or 0) % #poses + 1
		prompt:SetAttribute("FlexIdx", n) -- client-side only: remembers where the cycle is
		local faceAt = prompt:GetAttribute("FaceAt")
		task.spawn(function()
			local r = State.req("Flex", poses[n])
			if type(r) == "table" and r.ok then
				local ch = player.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				if root and typeof(faceAt) == "Vector3" then
					local look = Vector3.new(faceAt.X, root.Position.Y, faceAt.Z)
					if (look - root.Position).Magnitude > 0.5 then
						root.CFrame = CFrame.lookAt(root.Position, look)
					end
				end
			elseif type(r) == "table" then
				State.toast(r.err or "Can't flex right now", T.red)
			end
		end)
	elseif action and CityVisuals then
		-- city prompts (Home, LeaveHome, LeaveCamp, Autograph, Diner, Supplements, ProShop, Motors,
		-- Museum, EliteCenter): CityVisuals / CityStores; unknown actions stay ignored
		task.spawn(function()
			local ok, err = pcall(CityVisuals.Prompt, action, prompt)
			if not ok then
				warn("[ClientMain] prompt " .. tostring(action) .. ":", err)
			end
		end)
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	local k = input.KeyCode
	-- the Moves & Controls window is open: a press there is a binding being captured or its own navigation,
	-- not a hotkey (a capture sinks the key through ContextActionService too; this is the belt to those braces)
	if State.windows.Controls then
		return
	end
	-- gamepad: D-pad up = Career Hub, D-pad down = main menu. They only open (B closes): while Roblox's
	-- UI selection is up the D-pad is navigating a window. (A default control binding can mark a pad
	-- button processed, so gp alone does not tell for a pad.)
	if k == Enum.KeyCode.DPadUp or k == Enum.KeyCode.DPadDown or (k == Enum.KeyCode.DPadRight and PvPClient) then
		if GuiService.SelectedObject ~= nil or UserInputService:GetFocusedTextBox() or State.inFight() or Activities.Busy() or (MainMenu and MainMenu.IsOpen()) then
			return
		end
		local P = State.P
		if not (P and P.created and not P.retired) or Creator.IsOpen() then
			return
		end
		if k == Enum.KeyCode.DPadUp then
			Hub.Open()
		elseif k == Enum.KeyCode.DPadRight then
			PvPClient.Open()
		elseif MainMenu then
			MainMenu.Open()
		end
		return
	end
	if gp then
		return
	end
	if k == Enum.KeyCode.H and not State.inFight() and not Activities.Busy() and not (MainMenu and MainMenu.IsOpen()) then
		Hub.Toggle()
	elseif k == Enum.KeyCode.P and PvPClient and not State.inFight() and not Activities.Busy() and not (MainMenu and MainMenu.IsOpen()) then
		local P = State.P
		if P and P.created and not P.retired and not Creator.IsOpen() then
			PvPClient.Toggle()
		end
	elseif k == Enum.KeyCode.M and MainMenu and not State.inFight() and not Activities.Busy() then
		local P = State.P
		if P and P.created and not P.retired and not Creator.IsOpen() then
			MainMenu.Toggle()
		end
	end
end)

player.CharacterAdded:Connect(function()
	local P = State.P
	if P and not P.created and Creator.IsOpen() then
		task.wait(1)
		Creator.Refresh()
	end
end)

-- initial fetch
task.spawn(function()
	for _ = 1, 30 do
		local res = State.req("GetProfile")
		if res and not res.loading and res.created ~= nil then
			State.SetProfile(res)
			return
		end
		task.wait(1)
	end
end)
