-- ClientMain: wires the client together - HUD, gym prompts, profile updates, results,
-- retirement, trophy case and the time of day (your energy is your daylight).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme
local Modules = script.Parent:WaitForChild("BoxerClient")
local State = require(Modules:WaitForChild("State"))
local GymVisuals = require(Modules:WaitForChild("GymVisuals"))
local Creator = require(Modules:WaitForChild("Creator"))
local Hub = require(Modules:WaitForChild("Hub"))
local Activities = require(Modules:WaitForChild("Activities"))
local Services = require(Modules:WaitForChild("Services"))
local Ambience = require(Modules:WaitForChild("Ambience"))
Ambience.Start()
local gui = State.gui
local rec = State.rec

------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------
local hud = UI.Frame(gui, { Name = "HUD", Size = UDim2.new(0, 330, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(12, 12), BackgroundColor3 = T.bg, BackgroundTransparency = 0.15, Visible = false })
UI.Corner(hud, 10)
UI.Stroke(hud, T.gold, 1)
UI.Pad(hud, 9)
UI.List(hud, 2)
local hudName = UI.Text(hud, "", { Font = T.bold, TextColor3 = T.gold, TextSize = 17, LayoutOrder = 1 })
local hudTier = UI.Text(hud, "", { TextSize = 13, LayoutOrder = 2 })
local hudRec = UI.Text(hud, "", { TextSize = 13, LayoutOrder = 3 })
local bars = UI.Frame(hud, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
UI.List(bars, 2)
local function miniBar(label, color, order)
	local f = UI.Frame(bars, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = order })
	UI.Text(f, label, { TextSize = 11, TextColor3 = T.sub, Size = UDim2.new(0, 70, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
	local _, set = UI.Bar(f, { Position = UDim2.new(0, 72, 0, 3), Size = UDim2.new(1, -110, 0, 8) }, color)
	local val = UI.Text(f, "", { TextSize = 11, Position = UDim2.new(1, -34, 0, 0), Size = UDim2.new(0, 34, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
	return function(v, c)
		set(v / 100, c)
		val.Text = tostring(math.floor(v))
	end
end
local setEnergy = miniBar("ENERGY", T.gold, 1)
local setHydration = miniBar("HYDRATION", T.blue, 2)
local setNutrition = miniBar("NUTRITION", T.green, 3)
local setFatigue = miniBar("FATIGUE", T.orange, 4)
local hudCamp = UI.Text(hud, "", { TextSize = 12, TextColor3 = T.sub, LayoutOrder = 5 })
local hudWarn = UI.Text(hud, "", { TextSize = 12, TextColor3 = T.red, LayoutOrder = 6, Visible = false })

local hudButtons = UI.Frame(gui, { Name = "HudButtons", BackgroundTransparency = 1, Size = UDim2.fromOffset(330, 38), Position = UDim2.fromOffset(12, 12), Visible = false })
UI.List(hudButtons, 6, true)
UI.Button(hudButtons, "CAREER HUB [H]", { Size = UDim2.fromOffset(150, 36), BackgroundColor3 = T.gold, TextColor3 = T.bg, TextSize = 14 }, function()
	Hub.Toggle()
end)
UI.Button(hudButtons, "TRAIN", { Size = UDim2.fromOffset(80, 36), TextSize = 14 }, function()
	Hub.Open("Training")
end)
UI.Button(hudButtons, "SLEEP", { Size = UDim2.fromOffset(80, 36), TextSize = 14 }, function()
	State.open.Sleep()
end)
local hint = UI.Text(gui, "Walk up to any gym station and press E (or tap) to train.", { Name = "Hint", TextSize = 13, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -24), TextStrokeTransparency = 0.6, Visible = false, AutomaticSize = Enum.AutomaticSize.None })

local function layoutHud()
	hudButtons.Position = UDim2.new(0, 12, 0, 12 + hud.AbsoluteSize.Y + 8)
end
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)

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

local function showResult(data)
	local res = data.result
	local shade
	local function close()
		if shade then
			shade:Destroy()
		end
	end
	local win, body
	shade, win, body = UI.Window(gui, "Result", 640, 620, nil, { footer = 56 })
	local col = res.outcome == "win" and T.gold or (res.outcome == "loss" and T.red or T.sub)
	local title = res.outcome == "win" and "VICTORY" or (res.outcome == "loss" and "DEFEAT" or "DRAW")
	body.Position = UDim2.fromOffset(16, 110)
	body.Size = UDim2.new(1, -32, 1, -176)
	UI.Text(win, title, { Font = T.bold, TextSize = 50, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 58), AutomaticSize = Enum.AutomaticSize.None })
	UI.Text(win, string.format("%s  -  Round %d  vs %s", METHOD[res.method] or res.method, res.round or 0, data.opp or "?"), { TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.None })
	if res.reason then
		UI.Line(body, res.reason .. ((data.venue and data.venue ~= "") and ("  -  " .. data.venue) or ""), { TextColor3 = T.sub })
	end
	if res.cards and (res.cards[1][1] + res.cards[1][2]) > 0 then
		local line = {}
		for j, c in ipairs(res.cards) do
			table.insert(line, string.format("Judge %d: %d-%d", j, c[1], c[2]))
		end
		UI.Line(body, "SCORECARDS (you-opponent): " .. table.concat(line, "   "), { Font = T.bold })
	end
	if res.landed then
		UI.Line(body, string.format("Punches landed: %d/%d   Opponent: %d/%d   Knockdowns: %d scored, %d suffered",
			res.landed, res.thrown or res.landed, res.oppLanded or 0, res.oppThrown or 0, res.kdFor or 0, res.kdAgainst or 0), { TextSize = 15 })
	end
	if res.weighIn and res.weighIn.over and res.weighIn.over > 0 then
		UI.Line(body, string.format("Missed weight by %.1f lbs.", res.weighIn.over), { TextColor3 = T.red, TextSize = 14 })
	end
	if res.simulated then
		UI.Line(body, "(Simulated fight)", { TextColor3 = T.sub, TextSize = 14 })
	end
	UI.Line(body, "Earnings: " .. Config.Money(data.earnings or 0), { Font = T.bold, TextColor3 = T.green })
	for _, n in ipairs(data.notes or {}) do
		local big = n:find("CHAMPION") or n:find("PRO") or n:find("LEGEND") or n:find("TOP 10") or n:find("Promoted")
		UI.Line(body, "- " .. n, { TextColor3 = big and T.gold or T.text, Font = big and T.bold or T.font })
	end
	UI.Button(win, "CONTINUE", { Size = UDim2.new(0, 220, 0, 44), Position = UDim2.new(0.5, -110, 1, -56), BackgroundColor3 = T.gold, TextColor3 = T.bg }, close)
end
State.open.Result = showResult

local function showSparResult(data)
	local res = data.result
	local tr = data.training or {}
	local shade
	local function close()
		if shade then
			shade:Destroy()
		end
	end
	local win, body
	shade, win, body = UI.Window(gui, "SparResult", 560, 520, "SPARRING - " .. string.upper(data.intensity or ""), { footer = 56 })
	UI.Line(body, string.format("Partner: %s   -   %s", data.partner or "?", res.outcome == "win" and "You got the better of it" or (res.outcome == "loss" and "They got the better of it" or "Even session")), { Font = T.semi })
	UI.Line(body, string.format("Punches landed %d/%d  -  Opponent %d/%d  -  Knockdowns %d/%d", res.landed or 0, res.thrown or 0, res.oppLanded or 0, res.oppThrown or 0, res.kdFor or 0, res.kdAgainst or 0), { TextSize = 14, TextColor3 = T.sub })
	UI.Line(body, string.format("Session quality %d%%", math.floor((data.quality or 1) / 1.45 * 100)), { TextSize = 14 })
	local parts = {}
	for _, k in ipairs(Config.StatKeys) do
		local g = tr.gains and tr.gains[k]
		if g and g > 0.001 then
			table.insert(parts, string.format("+%.2f %s", g, Config.StatNames[k]))
		end
	end
	if #parts > 0 then
		UI.Line(body, table.concat(parts, "   "), { TextColor3 = T.green, Font = T.semi })
	end
	for _, n in ipairs(tr.notes or {}) do
		UI.Line(body, n, { TextColor3 = n:find("INJURY") and T.red or T.sub, TextSize = 14 })
	end
	UI.Button(win, "CONTINUE", { Size = UDim2.new(0, 220, 0, 44), Position = UDim2.new(0.5, -110, 1, -56), BackgroundColor3 = T.gold, TextColor3 = T.bg }, close)
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
	shade, win, body = UI.Window(gui, "Retired", 780, 640, (res.legacy.hallOfFame and "HALL OF FAME INDUCTION" or "CAREER OVER"), { footer = 60 })
	local c = UI.Card(body)
	UI.Line(c, string.format("%s \"%s\" retires at %d", P.identity.name, P.identity.nickname, P.identity.age), { Font = T.bold, TextSize = 22 })
	UI.Line(c, string.format("Final record %s  -  Amateur %s", rec(P.record), rec(P.amateurRecord)))
	UI.Line(c, string.format("World titles won %d  -  Title defenses %d  -  Peak tier: %s", P.titlesWon, P.defenses, P.tierName))
	if res.legacy.hallOfFame then
		UI.Line(c, "The boxing world honors you as one of the all-time greats. Welcome to the Hall of Fame.", { TextColor3 = T.gold, Font = T.bold })
	end
	Hub.LegacyBody(body, res.legacy, res.pastCareers)
	UI.Button(win, "START A NEW CAREER", { Size = UDim2.new(0, 280, 0, 46), Position = UDim2.new(0.5, -140, 1, -58), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
		local r = State.req("NewCareer")
		if r.ok then
			shade:Destroy()
			wasRetired = false
		end
	end)
end

------------------------------------------------------------------------
-- Trophy case (your belts on display in the lobby)
------------------------------------------------------------------------
local trophyFolder
local trophyKey
local function updateTrophies(P)
	local list = {}
	if P.regional.regional then
		table.insert(list, { "REGIONAL", Color3.fromRGB(190, 190, 200) })
	end
	if P.regional.national then
		table.insert(list, { "NATIONAL", Color3.fromRGB(205, 127, 50) })
	end
	for _, org in ipairs(Config.Orgs) do
		if P.belts[org] then
			table.insert(list, { org, Color3.fromRGB(255, 205, 50) })
		end
	end
	local key = {}
	for _, b in ipairs(list) do
		table.insert(key, b[1])
	end
	local k = table.concat(key, ",")
	if k == trophyKey then
		return
	end
	trophyKey = k
	if trophyFolder then
		trophyFolder:Destroy()
	end
	local gym = workspace:FindFirstChild("Gym")
	local case = gym and gym:FindFirstChild("TrophyCase")
	if not case then
		return
	end
	trophyFolder = Instance.new("Folder")
	trophyFolder.Name = "LocalTrophies"
	trophyFolder.Parent = workspace
	for i, b in ipairs(list) do
		local x = -6 + (i - 1) * 2.4
		local strap = Instance.new("Part")
		strap.Anchored, strap.CanCollide = true, false
		strap.Size = Vector3.new(2, 0.6, 0.2)
		strap.Color = Color3.fromRGB(20, 20, 20)
		strap.CFrame = case.CFrame * CFrame.new(x, 2.2, 0)
		strap.Parent = trophyFolder
		local plate = Instance.new("Part")
		plate.Anchored, plate.CanCollide = true, false
		plate.Shape = Enum.PartType.Cylinder
		plate.Size = Vector3.new(0.2, 1.2, 1.2)
		plate.Material = Enum.Material.Foil
		plate.Color = b[2]
		plate.CFrame = case.CFrame * CFrame.new(x, 2.2, -0.15) * CFrame.Angles(0, math.rad(90), 0)
		plate.Parent = trophyFolder
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(80, 20)
		bb.StudsOffset = Vector3.new(0, 1, 0)
		bb.MaxDistance = 40
		bb.Parent = plate
		UI.Text(bb, b[1], { Size = UDim2.fromScale(1, 1), Font = T.bold, TextScaled = true, TextColor3 = b[2], TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None })
	end
end

------------------------------------------------------------------------
-- Profile updates
------------------------------------------------------------------------
local function refresh()
	local P = State.P
	if not P or P.loading then
		return
	end
	local fight = State.inFight()
	if not P.created then
		hud.Visible, hudButtons.Visible, hint.Visible = false, false, false
		if not Creator.IsOpen() and not gui:FindFirstChild("Retired") then
			Creator.Open()
		end
		return
	end
	if P.retired then
		hud.Visible, hudButtons.Visible, hint.Visible = false, false, false
		Hub.Close()
		if not wasRetired or not gui:FindFirstChild("Retired") then
			wasRetired = true
			showRetired()
		end
		return
	end
	wasRetired = false
	local busy = State.busy()
	local show = not fight and busy ~= "fight" and busy ~= "spar"
	hud.Visible, hudButtons.Visible = show, show
	hint.Visible = show and (P.sessions or 0) < 3 and not Activities.Busy()
	hudName.Text = string.format("%s \"%s\"", P.identity.name, P.identity.nickname)
	hudTier.Text = string.format("%s  -  %s  -  OVR %d  -  Day %d", P.tierName, P.className, P.overall, P.day)
	hudRec.Text = string.format("%s  -  %s", P.tier == 1 and ("Amateur " .. rec(P.amateurRecord)) or ("Pro " .. rec(P.record)), Config.Money(P.money))
	local c = P.condition
	setEnergy(c.energy, c.energy < 25 and T.red or T.gold)
	setHydration(c.hydration, c.hydration < 30 and T.red or T.blue)
	setNutrition(c.nutrition, c.nutrition < 30 and T.red or T.green)
	setFatigue(c.fatigue, c.fatigue > 70 and T.red or (c.fatigue > 40 and T.orange or T.green))
	if P.camp then
		hudCamp.Text = P.camp.daysLeft > 0 and string.format("CAMP vs %s: %d day%s left  -  %.1f/%d lbs", P.camp.offer.opp.name, P.camp.daysLeft, P.camp.daysLeft == 1 and "" or "s", P.weight, P.weightLimit)
			or string.format("FIGHT NIGHT vs %s! Open the Career Hub.", P.camp.offer.opp.name)
	else
		hudCamp.Text = string.format("No fight booked - visit the Fight Board.  %.1f/%d lbs", P.weight, P.weightLimit)
	end
	local warns = {}
	for _, inj in ipairs(c.injuries or {}) do
		table.insert(warns, inj.name .. " (" .. inj.days .. "d)")
	end
	if c.fatigue > 70 then
		table.insert(warns, "OVERTRAINED")
	end
	hudWarn.Text = table.concat(warns, "  -  ")
	hudWarn.Visible = #warns > 0
	task.defer(layoutHud)
	GymVisuals.Refresh(P)
	updateTrophies(P)
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
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.H and not State.inFight() and not Activities.Busy() then
		Hub.Toggle()
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
