-- CityClient (LocalScript) — StarterPlayer.StarterPlayerScripts.CityClient
-- AI City on your screen. Starts the HUD, the windows, the world effects and
-- the citizens' body language, and routes everything the server sends.
--
-- Children: UI (look and helpers), Hud (always-on screen), Panels (windows),
-- World (nameplates, bubbles, prompts, waypoints, effects).
-- Shared: Poses (citizens' poses, props and faces), Faces, Atmosphere.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- 🏙️ The loading screen. The server builds the whole city when the game
-- starts, and the parts around you then stream in. Until that's done the
-- screen stays covered (an opaque card: nothing half-built pops in behind it,
-- and the 3D view isn't fighting the download for the frame time).
--------------------------------------------------------------------------------
local loading = {}
do
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CityLoading"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(34, 40, 78), Color3.fromRGB(12, 12, 20))
	grad.Rotation = 90
	grad.Parent = bg
	local function text(t, size, y, color, font)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.new(0.8, 0, 0, size + 10)
		l.Font = font or Enum.Font.GothamBlack
		l.TextSize = size
		l.TextColor3 = color
		l.Text = t
		l.Parent = bg
		return l
	end
	text("🏙️", 64, 0.36, Color3.new(1, 1, 1), Enum.Font.Gotham)
	text("AI CITY", 56, 0.46, Color3.fromRGB(255, 205, 80))
	local status = text("Building the city...", 20, 0.56, Color3.fromRGB(190, 196, 220), Enum.Font.GothamBold)
	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0.5, 0.5)
	barBack.Position = UDim2.fromScale(0.5, 0.62)
	barBack.Size = UDim2.fromOffset(320, 8)
	barBack.BackgroundColor3 = Color3.fromRGB(50, 56, 90)
	barBack.BorderSizePixel = 0
	barBack.Parent = bg
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0.05, 1)
	bar.BackgroundColor3 = Color3.fromRGB(255, 205, 80)
	bar.BorderSizePixel = 0
	bar.Parent = barBack
	for _, f in ipairs({ barBack, bar }) do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	end
	gui.Parent = pg
	loading.Gui, loading.Bg, loading.Status, loading.Bar = gui, bg, status, bar
	pcall(function()
		game:GetService("ReplicatedFirst"):RemoveDefaultLoadingScreen()
	end)
	function loading.Set(t, fraction)
		status.Text = t
		bar.Size = UDim2.fromScale(math.clamp(fraction, 0.05, 1), 1)
	end
	function loading.Done()
		if loading.Finished then
			return
		end
		loading.Finished = true
		loading.Set("Welcome!", 1)
		task.spawn(function()
			for k = 1, 10 do
				bg.BackgroundTransparency = k / 10
				for _, d in ipairs(bg:GetDescendants()) do
					if d:IsA("TextLabel") then
						d.TextTransparency = k / 10
					elseif d:IsA("Frame") then
						d.BackgroundTransparency = k / 10
					end
				end
				task.wait(0.03)
			end
			gui:Destroy()
		end)
	end
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local remotes = ReplicatedStorage:WaitForChild("CityRemotes")
local info = ReplicatedStorage:WaitForChild("CityInfo")
ReplicatedStorage:WaitForChild("CityState")
loading.Set("Moving in the citizens...", 0.45)

local UI = require(script:WaitForChild("UI"))
local Hud = require(script:WaitForChild("Hud"))
local Panels = require(script:WaitForChild("Panels"))
local World = require(script:WaitForChild("World"))
local Moves = require(script:WaitForChild("Moves"))
local Gamepad = require(script:WaitForChild("Gamepad"))
local Water = require(script:WaitForChild("Water"))
local Traffic = require(script:WaitForChild("Traffic"))
local Rides = require(script:WaitForChild("Rides"))
local Pets = require(script:WaitForChild("Pets"))
local Drive = require(script:WaitForChild("Drive"))
local Ambient = require(script:WaitForChild("Ambient"))
local Emotes = require(script:WaitForChild("Emotes"))
local Race = require(script:WaitForChild("Race"))
local Poses = require(Shared:WaitForChild("Poses"))
local C = UI.C

local ctx = {
	Remotes = { Event = remotes:WaitForChild("Event"), Request = remotes:WaitForChild("Request") },
	Hud = Hud,
	Panels = Panels,
	World = World,
	Moves = Moves,
	Poses = Poses,
	Gamepad = Gamepad,
	UI = UI,
	Player = player,
	SpeechSpot = info:GetAttribute("SpeechSpot"),
	Drive = Drive,
}
ctx.Emotes = Emotes

Hud.Start(ctx)
World.Start(ctx)
Panels.Start(ctx)
Moves.Start(ctx)
Gamepad.Start(ctx)
Water.Start()
Rides.Start(ctx)
Drive.Start(ctx)
Emotes.Start(ctx)
Race.Start(ctx)
-- the busy things (traffic, pets, birds, flags, the surf...) wait until you
-- start playing, so the welcome screen stays smooth
local busyStarted = false
local function startBusy()
	if busyStarted then
		return
	end
	busyStarted = true
	Traffic.Start()
	Pets.Start()
	Ambient.Start()
end
Panels.OnStart = startBusy
task.delay(20, startBusy)
loading.Set("Loading the streets...", 0.6)

-- the citizens' poses, props and faces, every frame (after animations)
local step = RunService.PreSimulation or RunService.Stepped
step:Connect(function(a, b)
	local dt = if type(b) == "number" then b else a
	Poses.Step(dt)
end)

--------------------------------------------------------------------------------
-- Messages from the server
--------------------------------------------------------------------------------
local IMPORTANT_NEWS = { Birth = "👶", Election = "🗳️", Crime = "🚨", Policy = "🏛️", Expecting = "🍼", GrewUp = "🎂", Retired = "🎉", Speech = "🎤", Day = "☀️" }
local handlers = {}

handlers.Toast = function(d)
	Hud.Toast(d.Icon, d.Title, d.Text, d.Color)
end
handlers.News = function(d)
	Hud.News(d.Text, d.Kind)
	if IMPORTANT_NEWS[d.Kind] and d.Kind ~= "Speech" then
		local text = string.gsub(d.Text, "^[^%w]*", "")
		Hud.Toast(IMPORTANT_NEWS[d.Kind], if d.Kind == "Day" then "A new day" elseif d.Kind == "Crime" then "Breaking news" else "City news", text, if d.Kind == "Crime" then C.Red elseif d.Kind == "Birth" or d.Kind == "Expecting" then C.Pink else C.Gold)
	end
end
handlers.Bubble = function(d)
	World.Bubble(d.Model, d.Text, d.Seconds)
end
handlers.Speech = function(d)
	if d.Character then
		World.Bubble(d.Character, "📣 " .. d.Text, 7, "speech")
	end
	if d.UserId ~= player.UserId then
		Hud.Toast("🎤", d.Name .. " is giving a speech!", "Head to the plaza to listen.", C.Gold)
	end
end
handlers.Election = function(d)
	Panels.ShowResults(d)
	Hud.Banner(if d.WinnerUserId == player.UserId then "👑 YOU ARE THE MAYOR!" else "🗳️ " .. d.Winner .. " WINS!", C.Gold, 4)
end
handlers.Dialogue = function(d)
	Panels.OpenDialogue(d)
end
handlers.DialogueEnd = function()
	Panels.EndDialogue(false)
end
handlers.Waypoint = function(d)
	if d.Clear then
		World.ClearWaypoint(d.CitizenId)
		return
	end
	World.Waypoint(d.Position, d.Label, d.Emoji, d.Model, d.CitizenId)
end
handlers.FishBite = function(d)
	World.FishBite(d.Position)
	Water.Bite(d.Position)
	Gamepad.Rumble(0.5, 0.2)
end
handlers.Shot = function(d)
	World.Shot(d.From, d.To, d.Weapon)
end
handlers.Hit = function(d)
	World.Hit(d.Position, d.Damage, d.KO, d.Player, d.Blocked, d.Weapon)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if d.Player and root and (root.Position - d.Position).Magnitude < 5 then
		Hud.Hurt()
		World.Shake(0.5, 0.2)
		Gamepad.Rumble(if d.Blocked then 0.25 else 0.6, 0.18)
	end
end
handlers.Goals = function(d)
	Hud.SetGoals(d.Goals, d.Done)
end
handlers.Shop = function(d)
	Panels.OpenShop(d)
end
handlers.Store = function(d)
	Panels.OpenStore(d)
end
handlers.Race = function(d)
	Race.Show(d)
end
handlers.Pop = function(d)
	World.Pop(d.Position, d.Color)
end
handlers.FoodMenu = function(d)
	Panels.OpenFood(d)
end
handlers.Job = function(d)
	Hud.SetJob(d)
end
handlers.Food = function(d)
	Moves.AddStamina(d.Energy)
end
handlers.Wardrobe = function(d)
	Panels.OpenWardrobe(d)
end
handlers.Down = function(d)
	Panels.Down(d)
end
handlers.Alarm = function(d)
	World.Alarm(d.Position, d.Seconds)
end
handlers.Wanted = function(d)
	if d.Up then
		Hud.Banner(string.rep("⭐", d.Stars) .. "  WANTED!", C.Red, 2.5)
		UI.sound("notify", 0.5, 0.7)
	elseif d.Lost then
		Hud.Banner("😮‍💨 You lost them", C.Green, 2)
	end
end
handlers.Busted = function(d)
	Panels.Busted(d)
end
handlers.Elevator = function(d)
	Panels.OpenElevator(d)
end
handlers.Coins = function(d)
	if math.abs(d.Amount) >= 50 or d.Amount < 0 then
		Hud.Toast(if d.Amount >= 0 then "🪙" else "💸", (if d.Amount >= 0 then "+" else "") .. d.Amount .. " coins", d.Reason or "", if d.Amount >= 0 then C.Gold else C.Red)
	end
end
handlers.Welcome = function(d)
	-- wait for the city around the welcome view (and you) to stream in
	loading.Set("Loading your neighborhood...", 0.8)
	pcall(function()
		player:RequestStreamAroundAsync(Vector3.new(0, 20, 0), 6)
	end)
	loading.Done()
	Panels.Welcome()
	task.delay(1, function()
		Hud.Toast("🏙️", "Welcome to AI City!", "It's " .. tostring(d.Weekday) .. ". The mayor is " .. tostring(d.Mayor or "nobody yet") .. ". Press H for help.", C.Gold)
	end)
end

ctx.Remotes.Event.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	local handler = handlers[data.Type]
	if handler then
		local ok, err = pcall(handler, data)
		if not ok then
			warn("[CityClient] " .. tostring(data.Type) .. ": " .. tostring(err))
		end
	end
end)

-- our own health bar replaces Roblox's
pcall(function()
	local StarterGui = game:GetService("StarterGui")
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) -- our own weapon hotbar
end)
-- the first goals (in case they arrived before the HUD was ready)
task.spawn(function()
	local ok, result = pcall(function()
		return ctx.Remotes.Request:InvokeServer({ Action = "Goals" })
	end)
	if ok and result and result.Goals then
		Hud.SetGoals(result.Goals)
	end
end)

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------
local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
}
UserInputService.InputBegan:Connect(function(input, processed)
	if (input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonL3) and not UserInputService:GetFocusedTextBox() then
		Moves.SetSprint(true)
		return
	end
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	local key = input.KeyCode
	if (key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA) and player:GetAttribute("Hiding") then
		task.spawn(function()
			ctx.Remotes.Request:InvokeServer({ Action = "Unhide" })
		end)
		return
	end
	if NUMBER_KEYS[key] and Panels.InDialogue() then
		Panels.DialogueKey(NUMBER_KEYS[key])
	elseif NUMBER_KEYS[key] then
		Hud.Equip(NUMBER_KEYS[key])
	elseif key == Enum.KeyCode.Tab then
		Panels.Phone.Toggle()
	elseif key == Enum.KeyCode.M then
		Panels.Map.Toggle()
	elseif key == Enum.KeyCode.P then
		Panels.Directory.Toggle()
	elseif key == Enum.KeyCode.V then
		Panels.Vote.Toggle()
	elseif key == Enum.KeyCode.B then
		Panels.Speech.Toggle()
	elseif key == Enum.KeyCode.N then
		Panels.Mayor.Toggle()
	elseif key == Enum.KeyCode.H then
		Panels.Help.Toggle()
	elseif key == Enum.KeyCode.C then
		task.spawn(Panels.ToggleWardrobe)
	elseif key == Enum.KeyCode.F then
		World.Attack()
	elseif key == Enum.KeyCode.X then
		World.SetBlock(true)
	elseif key == Enum.KeyCode.Z then
		-- hands up (the police cuff you without a fight)
		task.spawn(function()
			ctx.Remotes.Request:InvokeServer({ Action = "Surrender" })
		end)
	elseif key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace then
		if Panels.InDialogue() then
			Panels.EndDialogue(true)
		elseif Panels.Phone.IsOpen() then
			Panels.Phone.Close()
		else
			UI.closeAll()
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.X then
		World.SetBlock(false)
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
		Moves.SetSprint(false)
	end
end)
