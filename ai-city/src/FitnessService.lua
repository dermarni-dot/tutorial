-- FitnessService (ModuleScript) — ServerScriptService.Modules.FitnessService
-- Your fitness level (saved): sprinting earns XP (reported by your client, with
-- a limit), and the gym's treadmills give a proper workout (press E: you run
-- for a few seconds). Each level: more stamina, faster recovery, faster sprint
-- (see Shared.Fitness). Stamina itself lives on the client so running feels instant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fitness = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Fitness"))

local FitnessService = {}
local S
local lastReport = {} -- [player] = os.clock() of their last sprint report
local onTreadmill = {} -- [player] = belt

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function data(player)
	local pd = S.City.Data(player)
	if not pd then
		return nil
	end
	pd.Fitness = pd.Fitness or { Level = 1, XP = 0 }
	return pd.Fitness
end

local function publish(player)
	local f = data(player)
	if f then
		player:SetAttribute("FitLevel", f.Level)
		player:SetAttribute("FitXP", math.floor(f.XP))
		player:SetAttribute("FitNext", Fitness.XPFor(f.Level))
	end
end

function FitnessService.AddXP(player, amount)
	local f = data(player)
	if not f or amount <= 0 then
		return
	end
	f.XP += amount
	while f.Level < Fitness.MAX_LEVEL and f.XP >= Fitness.XPFor(f.Level) do
		f.XP -= Fitness.XPFor(f.Level)
		f.Level += 1
		local st = Fitness.Stats(f.Level)
		S.City.Toast(player, "💪", "Fitness level " .. f.Level .. "!", string.format("Stamina %d · sprint speed %.1f. Keep training!", st.MaxStamina, st.Sprint), rgb(80, 200, 140))
	end
	if f.Level >= Fitness.MAX_LEVEL then
		f.XP = math.min(f.XP, Fitness.XPFor(f.Level))
	end
	publish(player)
end

-- the client says "I sprinted for N seconds" (never more than the time since the last report)
local function trained(player, info)
	local now = os.clock()
	local since = now - (lastReport[player] or (now - 5))
	lastReport[player] = now
	local seconds = math.clamp(tonumber(info.Seconds) or 0, 0, math.min(12, since * 1.1))
	FitnessService.AddXP(player, seconds * Fitness.SPRINT_XP)
	return { Ok = true }
end

-- the gym's treadmills
local function workout(player, belt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or onTreadmill[player] or (S.Crime and (S.Crime.IsJailed(player) or S.Crime.IsHiding(player))) then
		return
	end
	if (player:GetAttribute("Wanted") or 0) > 0 then
		S.City.Toast(player, "🚨", "No time for that!", "You're wanted by the police.", rgb(230, 60, 60))
		return
	end
	onTreadmill[player] = belt
	local back = root.CFrame
	-- stand on the belt, facing the screen (the rail is at the belt's -Z end)
	local facing = belt.CFrame.LookVector
	local rail = belt.Parent and belt.Parent:FindFirstChild("TreadmillRail")
	if rail then
		local d = rail.Position - belt.Position
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.1 then
			facing = d.Unit
		end
	end
	local pos = belt.Position + Vector3.new(0, 3.1, 0)
	root.CFrame = CFrame.lookAt(pos, pos + facing)
	root.Anchored = true
	character:SetAttribute("Treadmill", true)
	S.City.Toast(player, "🏃", "Running on the treadmill...", "Training your stamina.", rgb(80, 200, 140))
	task.delay(Fitness.TREADMILL_SECONDS, function()
		onTreadmill[player] = nil
		if character.Parent then
			character:SetAttribute("Treadmill", nil)
			if root.Parent then
				root.Anchored = false
				root.CFrame = CFrame.lookAt(pos - facing * 4, pos) + Vector3.new(0, 0.2, 0)
			end
		end
		if player.Parent then
			FitnessService.AddXP(player, Fitness.TREADMILL_XP)
			S.City.Send(player, { Type = "Food", Energy = 1000 }) -- a workout leaves you ready to go
			S.City.Toast(player, "💪", "Good workout! +" .. Fitness.TREADMILL_XP .. " XP", "Your stamina is full again.", rgb(80, 200, 140))
			S.City.Progress(player, "train", 1)
		end
	end)
	return back
end

local function addTreadmills()
	local gym = S.Map.Places.Gym
	if not gym or not gym.Model then
		return
	end
	for _, belt in ipairs(gym.Model:GetDescendants()) do
		if belt:IsA("BasePart") and belt.Name == "TreadmillBelt" then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "TrainPrompt"
			prompt.ActionText = "Run on the treadmill"
			prompt.ObjectText = "💪 Train stamina"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = 7
			prompt.RequiresLineOfSight = false
			prompt.Style = Enum.ProximityPromptStyle.Custom
			prompt:SetAttribute("Kind", "Train")
			prompt.Parent = belt
			prompt.Triggered:Connect(function(player)
				workout(player, belt)
			end)
		end
	end
end

function FitnessService.Start(services)
	S = services
	S.City.Handle("Trained", trained)
	addTreadmills()
	local function onPlayer(player)
		task.spawn(function()
			for _ = 1, 50 do
				if S.City.Data(player) then
					break
				end
				task.wait(0.2)
			end
			publish(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastReport[player] = nil
		onTreadmill[player] = nil
	end)
end

return FitnessService
