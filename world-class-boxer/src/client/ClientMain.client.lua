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
local Combos = require(Shared:WaitForChild("Combos")) -- (the result screen's combo line)
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
-- the gym's and the city's extra detail layer (WorldDetail: streamed by Graphics level and distance): optional too
task.spawn(function()
	local ok, WorldDetail = pcall(function()
		return require(Modules:WaitForChild("WorldDetail", 10))
	end)
	if ok and type(WorldDetail) == "table" then
		pcall(WorldDetail.Start)
	else
		warn("[ClientMain] WorldDetail unavailable:", WorldDetail)
	end
end)
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
-- the first-time tutorial fight (its offer, step card and wrap-up): optional like the city
local okTut, TutorialClient = pcall(function()
	return require(Modules:WaitForChild("Tutorial", 10))
end)
if okTut and type(TutorialClient) == "table" then
	local okStart, errStart = pcall(TutorialClient.Start)
	if not okStart then
		warn("[ClientMain] Tutorial start:", errStart)
	end
else
	warn("[ClientMain] Tutorial unavailable:", TutorialClient)
	TutorialClient = nil
end
-- the rig diagnostic ("/wcbdiag" in chat, Settings -> GAME -> COPY DIAGNOSTIC TO OUTPUT): optional, runs only when invoked
task.spawn(function()
	local ok, DiagClient = pcall(function()
		return require(Modules:WaitForChild("DiagClient", 10))
	end)
	if ok and type(DiagClient) == "table" then
		local okStart, errStart = pcall(DiagClient.Start, State)
		if not okStart then
			warn("[ClientMain] DiagClient start:", errStart)
		end
	else
		warn("[ClientMain] DiagClient unavailable:", DiagClient)
	end
end)
-- the celebration cutscene after a won tournament final / a new title (camera, confetti, banner, SKIP): optional
task.spawn(function()
	local ok, CeremonyClient = pcall(function()
		return require(Modules:WaitForChild("Ceremony", 10))
	end)
	if ok and type(CeremonyClient) == "table" then
		pcall(CeremonyClient.Start)
	else
		warn("[ClientMain] Ceremony unavailable:", CeremonyClient)
	end
end)
-- [Entrance] the ring-walk cinematic (camera, crowd carry, reveal, SKIP) and the Locker's ENTRANCE picker: optional
task.spawn(function()
	local ok, err = pcall(function()
		require(Modules:WaitForChild("EntranceFX", 10)).Start()
		require(Modules:WaitForChild("EntrancePicker", 10))
	end)
	if not ok then
		warn("[ClientMain] Entrance unavailable:", err)
	end
end)
local gui = State.gui
local rec = State.rec

------------------------------------------------------------------------
-- HUD: the player plate (top left)
------------------------------------------------------------------------
local hud = UI.Frame(gui, { Name = "HUD", Size = UDim2.new(0, 360, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(20, 16), Visible = false })
UI.Glass(hud, { transparency = 0.16 })
UI.New("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = hud })
UI.List(hud, 6)
local brandRow = UI.Frame(hud, { Name = "BrandRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = -1 })
UI.Brand(brandRow, 24, { Position = UDim2.fromOffset(0, 0) })
UI.Text(brandRow, "WORLD CLASS BOXER", { Face = "displayMed", TextSize = 15, TextColor3 = T.sub,
	Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -34, 0, 24), AutomaticSize = Enum.AutomaticSize.None,
	TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })

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
UI.GoldText(hudOvr)
UI.Text(ovrBox, "OVR", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -14), AutomaticSize = Enum.AutomaticSize.None,
	TextXAlignment = Enum.TextXAlignment.Center })
local hudTier = UI.Text(hud, "", { Name = "Tier", Font = T.semi, TextSize = 12, TextColor3 = T.gold, LayoutOrder = 2, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
local nums = UI.Frame(hud, { Name = "Numbers", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 3 })
UI.List(nums, 8, true)
local _, recVal, recCap = UI.Stat(nums, "0-0-0", "RECORD", { Size = UDim2.new(0.5, -4, 1, 0), valueSize = 24, order = 1, scaled = true, icon = "glove", iconSize = 14 })
local _, moneyVal = UI.Stat(nums, "$0", "PURSE", { Size = UDim2.new(0.5, -4, 1, 0), valueSize = 24, order = 2, valueColor = T.gold, scaled = true, icon = "coin", iconSize = 14, iconColor = T.goldDeep })
local bars = UI.Frame(hud, { Name = "Meters", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
UI.List(bars, 5)
local function miniBar(label, color, order, icon)
	local f = UI.Frame(bars, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order })
	-- the meter's icon in its colour, then its caption
	UI.Icon(f, icon, 14, color, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
	UI.Text(f, label, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(20, 0), Size = UDim2.new(0, 96, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	-- the meter in the fight bars' finish (UI.Meter: rounded, the sheen, an eased fill, a ghost that drains
	-- when the value drops, a glow when it comes back)
	local meter = UI.Meter(f, { Position = UDim2.new(0, 118, 0.5, -4), Size = UDim2.new(1, -158, 0, 8) }, { color = color })
	local val = UI.Text(f, "", { Face = "number", TextSize = 15, Position = UDim2.new(1, -34, 0, 0), Size = UDim2.new(0, 34, 1, 0), TextXAlignment = Enum.TextXAlignment.Right,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	return function(v, c)
		meter:set(v / 100, c)
		val.Text = tostring(math.floor(v))
		val.TextColor3 = c == T.red and T.redLight or T.text
	end
end
local setEnergy = miniBar("ENERGY", T.gold, 1, "energy")
local setHydration = miniBar("HYDRATION", T.cyan, 2, "water")
local setNutrition = miniBar("NUTRITION", T.green, 3, "food")
local setFatigue = miniBar("FATIGUE", T.orange, 4, "pulse")
-- the phone plate: the four meters as one line of chips under the name
local condStrip = UI.Frame(hud, { Name = "CondStrip", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 4, Visible = false })
UI.List(condStrip, 6, true)
local condChips = {}
-- (each chip: the meter's icon and its number, tinted by how it stands: four words and four icons do not fit
-- the phone's plate, the icons say which meter it is)
local CHIP_ICONS = { ENERGY = "energy", WATER = "water", FOOD = "food", FATIGUE = "pulse" }
for i, k in ipairs({ "ENERGY", "WATER", "FOOD", "FATIGUE" }) do
	local f, t = UI.Chip(condStrip, k, T.sub, { order = i, h = 26, TextSize = 13, icon = CHIP_ICONS[k], radius = 13 })
	condChips[k] = { frame = f, text = t, icon = f:FindFirstChild("ChipIcon") }
end
local function setCond(k, v, color)
	local c = condChips[k]
	c.text.Text = c.icon and tostring(math.floor(v)) or string.format("%s %d", k, math.floor(v))
	c.text.TextColor3 = color
	c.frame.BackgroundColor3 = T.bg:Lerp(color, 0.12)
	local st = c.frame:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = color
	end
	if c.icon then
		UI.SetIconColor(c.icon, color)
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
-- the quick actions are a fingertip tall on touch (UI.MinHit: 57 design px on a phone), 40 with a mouse
local function hudBtnH()
	return math.max(40, UI.MinHit(gui))
end
-- key: the keyboard key's cap; padKey: the gamepad button shown on the cap instead while a pad is in use
-- (the button widens to fit the longer name, "D-DOWN")
local function hudButton(text, key, w, color, fn, order, padKey)
	local b = UI.Button(hudButtons, "", { Name = text, Size = UDim2.fromOffset(w, hudBtnH()), BackgroundColor3 = color or T.panel2, BackgroundTransparency = color and 0 or 0.15, LayoutOrder = order }, fn)
	b:SetAttribute("BaseW", w)
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
				-- a touch screen has no key to name: the cap goes and the label takes the button
				local touch = mode == "touch"
				cap.Visible = not touch
				local capW = touch and 0 or math.max(20, 8 + 7 * #t)
				cap.Size = UDim2.fromOffset(math.max(capW, 20), 20)
				label.Size = UDim2.new(1, touch and 0 or -(capW + 6), 1, 0)
				local bw = touch and math.max(w - 20, UI.MinHit(gui)) or (w + capW - 20)
				b:SetAttribute("BaseW", bw)
				b.Size = UDim2.fromOffset(bw, hudBtnH())
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
	elseif mode == "touch" then
		return "Walk up to a gym station and tap its prompt to train."
	elseif hudCompact then
		return "Walk up to a gym station and press E (or tap) to train."
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
	-- (a rotation or the UI scale setting can change what a fingertip is in design px)
	local bh = hudBtnH()
	if hudButtons.Size.Y.Offset ~= bh then
		hudButtons.Size = UDim2.fromOffset(360, bh)
		for _, b in ipairs(hudButtons:GetChildren()) do
			if b:IsA("GuiButton") then
				b.Size = UDim2.fromOffset(b:GetAttribute("BaseW") or b.Size.X.Offset, bh)
			end
		end
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
		hint.Position = UDim2.new(0, 16, 1, -(bottom + bh + 8))
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
	-- a phone's window is short: a smaller headline leaves the scorecards and stats the room
	local short = UI.CanvasSize(gui).Y < 560
	local bodyTop = short and 108 or 150
	body.Position = UDim2.fromOffset(28, bodyTop)
	body.Size = UDim2.new(1, -56, 1, -(bodyTop + 72))
	-- "FIGHT NIGHT" and the venue's badge (the sign's lockup; the name when the place is not known)
	local venueBadge = UI.LocationBadge(win, data.venue, 20, { sub = false, Position = UDim2.fromOffset(28 + 20 + UI.TextWidth("FIGHT NIGHT", 12, T.semi) + 10, short and 15 or 21) })
	UI.Kicker(win, (not venueBadge and data.venue and data.venue ~= "") and ("FIGHT NIGHT  ·  " .. data.venue) or "FIGHT NIGHT", T.sub, { Position = UDim2.fromOffset(28, short and 16 or 22), Size = UDim2.new(1, -120, 0, 18),
		icon = "bell" })
	-- the outcome's emblem (a trophy for a win, the KO burst for a stoppage, gloves for a decision / loss) beside the
	-- headline, left of the close button
	local stoppage = res.method == "KO" or res.method == "TKO" or res.method == "RTD"
	local emblem = res.outcome == "win" and (stoppage and "ko" or "trophy") or (res.outcome == "loss" and (stoppage and "ko" or "glove") or "versus")
	local es = short and 52 or 76
	local tile = UI.IconTile(win, emblem, es, col, { Name = "Emblem", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -84, 0, short and 30 or 40), iconScale = 0.62 })
	local tileScale = UI.New("UIScale", { Scale = 0.6, Parent = tile })
	UI.Tween(tileScale, { Scale = 1 }, UI.Motion.spring)
	-- (the poster face's capitals bounce above their cap line: the headline sits a little lower than the kicker's
	-- row would need for a flat face)
	local big = UI.Title(win, title, { TextSize = short and 48 or 76, TextColor3 = col, Position = UDim2.fromOffset(24, short and 36 or 44), Size = UDim2.new(1, -48, 0, short and 52 or 82),
		TextTransparency = 1 })
	UI.Tween(big, { TextTransparency = 0 }, UI.Motion.slow)
	if res.outcome == "win" then
		-- a gradient multiplies the text colour: white text takes the gold ramp as is
		big.TextColor3 = Color3.new(1, 1, 1)
		UI.Gradient(big, { Color3.fromRGB(255, 240, 190), T.gold, T.goldDeep }, 90)
	end
	UI.Text(win, string.format("%s  ·  ROUND %d  ·  vs %s", string.upper(METHOD[res.method] or tostring(res.method)), res.round or 0, string.upper(data.opp or "?")),
		{ Font = T.semi, TextSize = 15, TextColor3 = T.text, Position = UDim2.fromOffset(28, short and 84 or 122), Size = UDim2.new(1, -56, 0, 20), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd })
	if res.reason then
		UI.Line(body, res.reason, { TextColor3 = T.sub, TextSize = 14 })
	end
	-- the three judges
	if res.cards and res.cards[1] and (res.cards[1][1] + res.cards[1][2]) > 0 then
		UI.Kicker(body, "SCORECARDS  (YOU - OPPONENT)", T.sub, { icon = "contract" })
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
		UI.Kicker(body, "FIGHT STATS  ·  RED = YOU, BLUE = OPPONENT", T.sub, { icon = "chart" })
		local stats = UI.Card(body, { pad = 16 })
		versusRow(stats, "PUNCHES LANDED", res.landed or 0, res.oppLanded or 0, nil, 1)
		versusRow(stats, "PUNCHES THROWN", res.thrown or res.landed or 0, res.oppThrown or 0, nil, 2)
		local accA = (res.thrown or 0) > 0 and math.floor((res.landed or 0) / res.thrown * 100 + 0.5) or 0
		local accB = (res.oppThrown or 0) > 0 and math.floor((res.oppLanded or 0) / res.oppThrown * 100 + 0.5) or 0
		versusRow(stats, "ACCURACY", accA, accB, function(v)
			return v .. "%"
		end, 3)
		versusRow(stats, "KNOCKDOWNS", res.kdFor or 0, res.kdAgainst or 0, nil, 4)
		-- the combinations (FightEngine res.combos / oppCombos: named combos landed, the best chain)
		if type(res.combos) == "table" then
			local oc = type(res.oppCombos) == "table" and res.oppCombos or {}
			versusRow(stats, "COMBOS LANDED", tonumber(res.combos.landed) or 0, tonumber(oc.landed) or 0, nil, 5)
			versusRow(stats, "BEST COMBO (PUNCHES)", tonumber(res.combos.best) or 0, tonumber(oc.best) or 0, nil, 6)
		end
	end
	if type(res.combos) == "table" and Combos then
		local line = Combos.StatsText(res.combos)
		if line then
			UI.Line(body, line, { Name = "ComboLine", TextColor3 = T.gold, TextSize = 14, Font = T.semi })
		end
	end
	if res.weighIn and res.weighIn.over and res.weighIn.over > 0 then
		UI.Line(body, string.format("Missed weight by %.1f lbs.", res.weighIn.over), { TextColor3 = T.red, TextSize = 14, Font = T.semi })
	end
	if res.simulated then
		UI.Line(body, "Simulated fight", { TextColor3 = T.sub, TextSize = 13 })
	end
	local purse = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58) })
	UI.Kicker(purse, "EARNINGS", T.green, { Size = UDim2.new(1, 0, 0, 18), icon = "coin" })
	UI.Title(purse, Config.Money(data.earnings or 0), { TextSize = 38, TextColor3 = T.green, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 42) })
	for _, n in ipairs(data.notes or {}) do
		local bigNote = n:find("CHAMPION") or n:find("PRO") or n:find("LEGEND") or n:find("TOP 10") or n:find("Promoted") or n:find("SPECIAL MOVE")
		UI.Line(body, n, { TextColor3 = bigNote and T.gold or T.text, Font = bigNote and T.semi or T.font, TextSize = 14 })
	end
	local cbh = math.max(48, UI.MinHit(win))
	UI.PadStart(UI.Button(win, "CONTINUE", { Size = UDim2.new(0, 260, 0, cbh), Position = UDim2.new(0.5, -130, 1, -(14 + cbh)), BackgroundColor3 = T.gold }, close))
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
	local cbh = math.max(46, UI.MinHit(win))
	UI.PadStart(UI.Button(win, "CONTINUE", { Size = UDim2.new(0, 240, 0, cbh), Position = UDim2.new(0.5, -120, 1, -(12 + cbh)), BackgroundColor3 = T.gold }, close))
end

State.FightRemote.OnClientEvent:Connect(function(msg)
	if msg.t == "result" then
		task.delay(0.5, showResult, msg)
	elseif msg.t == "sparResult" then
		-- (a session left with "Return to gym" - FightClient / BoxerClient.SparExit set SparSkipCard - goes
		-- straight back to the floor: the training still counted, the card is skipped this once)
		if player:GetAttribute("SparSkipCard") then
			player:SetAttribute("SparSkipCard", nil)
			State.toast("Back in the gym. The session's work counted.", T.gold)
		else
			task.delay(0.4, showSparResult, msg)
		end
	elseif msg.t == "aborted" then
		State.toast(msg.spar and "Sparring session ended." or "The fight was called off.", T.red)
	end
end)

-- plain server notices on State.Notify (Activities listens there too, for its drill checkpoints)
State.Notify.OnClientEvent:Connect(function(msg)
	if type(msg) == "table" and msg.t == "toast" and type(msg.text) == "string" then
		State.toast(msg.text, T.gold, 8)
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
	local nbh = math.max(48, UI.MinHit(win))
	local newCareer = UI.Button(win, "START A NEW CAREER", { Size = UDim2.new(0, 300, 0, nbh), Position = UDim2.new(0.5, -150, 1, -(14 + nbh)), BackgroundColor3 = T.gold }, function()
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
local debutOffered = false -- the guided debut's offer was put up this session (a new boxer, right after the creator)
-- a debut called off (debutEnd) may be offered again: the once-a-session flag is cleared with it
State.FightRemote.OnClientEvent:Connect(function(msg)
	if type(msg) == "table" and msg.t == "debutEnd" then
		debutOffered = false
	end
end)
local lastFlag
local hubShownKey = nil -- the profile / state the open hub was last rebuilt for
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
		-- the tutorial's offer, bout or wrap-up is up: it decides what comes next (the creator, the title)
		if fight or State.busy() == "fight" or (TutorialClient and TutorialClient.Busy()) then
			return
		end
		if not Creator.IsOpen() and not gui:FindFirstChild("Retired") then
			-- (the first-time flow: the title screen, the creator, then the guided debut, the boxer's own first
			-- career fight. The random-boxer practice round is optional: Settings > PRACTICE ROUND)
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
	-- a new boxer (made in the creator, no bout yet): his guided debut is offered right away (once a session; a
	-- debut called off offers itself again: BoxerClient.Tutorial)
	local debutOfferedNow = false
	if TutorialClient and TutorialClient.OfferDebut and not debutOffered and type(P.debut) == "table" and P.debut.offer == true
		and not fight and State.busy() == nil and not Creator.IsOpen() and not TutorialClient.Busy() then
		debutOffered = true
		debutOfferedNow = true
		Hub.Close()
		if MainMenu and MainMenu.IsOpen() then
			MainMenu.Close()
		end
		TutorialClient.OfferDebut(P.debut)
	end
	if not menuShownOnce then
		menuShownOnce = true
		-- the saved settings first (Settings listens to State.Changed too, but handler order is not
		-- guaranteed): "show the menu at start" must be the player's saved choice
		Settings.Load(P)
		if MainMenu and Settings.Get("menuAtStart") and not fight and not debutOfferedNow then
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
	-- the hub is rebuilt (hundreds of GUI objects) for a new profile or a new busy / fight state, not for a
	-- refresh that only re-checks the HUD's visibility (a window opening or closing: State.Refresh)
	if Hub.IsOpen() and not Activities.Busy() then
		local key = tostring(P) .. "|" .. tostring(busy) .. "|" .. tostring(fight)
		if key ~= hubShownKey then
			hubShownKey = key
			Hub.Render()
		end
	end
end

State.Changed:Connect(refresh)

-- New special moves: the unlocked set (Moves.Unlocked of the summary) is compared with the last one this
-- session saw, so a move that comes with a promotion, a training milestone or a fight result is announced
-- with its key / chord for the device in use (held back to after the fight when it comes during one). The
-- first profile of the session only sets the baseline.
do
	local okMoves, Moves = pcall(function()
		return require(Shared:WaitForChild("Moves"))
	end)
	local okKeys, Keymap = pcall(function()
		return require(Shared:WaitForChild("Keymap"))
	end)
	local known, pending = nil, {}
	local function announce()
		if State.inFight() or #pending == 0 then
			return
		end
		local mode = UI.Gamepad and UI.Gamepad.Mode() or "keyboard"
		local device = mode == "gamepad" and "pad" or (mode == "touch" and "touch" or "kbd")
		if #pending > 2 then
			-- a big promotion unlocks several at once: one notice, not a column of them
			local names = {}
			for _, id in ipairs(pending) do
				table.insert(names, string.upper(Moves.Data[id] and Moves.Data[id].name or id))
			end
			State.toast(string.format("%d NEW SPECIAL MOVES: %s. Moves & Controls has their keys.", #pending, table.concat(names, ", ")), T.gold, 9)
		else
			for _, id in ipairs(pending) do
				local M = Moves.Data[id]
				local key = device == "touch" and "its gold pad in a fight" or (okKeys and Keymap.ActionText(Settings.Keymap(), "special_" .. id, device, UI.Gamepad) or "")
				State.toast(string.format("NEW SPECIAL MOVE: %s (%s). Moves & Controls has the details.", string.upper(M and M.name or id), key), T.gold, 8)
			end
		end
		table.clear(pending)
	end
	if okMoves and type(Moves) == "table" then
		State.Changed:Connect(function(P)
			if type(P) ~= "table" or not P.created then
				return
			end
			local now = Moves.Unlocked(Moves.Info(P))
			if known then
				for _, id in ipairs(Moves.List) do
					if now[id] and not known[id] and not table.find(pending, id) then
						table.insert(pending, id)
					end
				end
			end
			known = now
			announce()
		end)
		player:GetAttributeChangedSignal("InFight"):Connect(function()
			task.delay(1.5, announce)
		end)
	end
end

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
