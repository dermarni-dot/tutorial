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
local Shared = ReplicatedStorage:WaitForChild("Shared")
local remotes = ReplicatedStorage:WaitForChild("CityRemotes")
local info = ReplicatedStorage:WaitForChild("CityInfo")
ReplicatedStorage:WaitForChild("CityState")

local UI = require(script:WaitForChild("UI"))
local Hud = require(script:WaitForChild("Hud"))
local Panels = require(script:WaitForChild("Panels"))
local World = require(script:WaitForChild("World"))
local Moves = require(script:WaitForChild("Moves"))
local Gamepad = require(script:WaitForChild("Gamepad"))
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
}

Hud.Start(ctx)
World.Start(ctx)
Panels.Start(ctx)
Moves.Start(ctx)
Gamepad.Start(ctx)

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
		World.ClearWaypoint()
		return
	end
	World.Waypoint(d.Position, d.Label, d.Emoji, d.Model)
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
