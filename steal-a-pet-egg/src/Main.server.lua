-- Main (Script) — ServerScriptService.Main
-- Boots the game: builds the map, starts the systems, loads and saves players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Modules = script.Parent:WaitForChild("Modules")
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local DataService = require(Modules:WaitForChild("DataService"))
local GameService = require(Modules:WaitForChild("GameService"))
local Monetization = require(Modules:WaitForChild("Monetization"))
local AdminService = require(Modules:WaitForChild("AdminService"))
local DailyRewardService = require(Modules:WaitForChild("DailyRewardService"))
local CodesService = require(Modules:WaitForChild("CodesService"))
local LeaderboardService = require(Modules:WaitForChild("LeaderboardService"))

-- Remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local notify = Instance.new("RemoteEvent")
notify.Name = "Notify"
notify.Parent = remotes
local treadmill = Instance.new("RemoteEvent")
treadmill.Name = "Treadmill"
treadmill.Parent = remotes
local admin = Instance.new("RemoteEvent")
admin.Name = "Admin"
admin.Parent = remotes
local codes = Instance.new("RemoteEvent")
codes.Name = "Codes"
codes.Parent = remotes
local treats = Instance.new("RemoteEvent")
treats.Name = "Treats"
treats.Parent = remotes
local hatched = Instance.new("RemoteEvent")
hatched.Name = "Hatched"
hatched.Parent = remotes
local slapped = Instance.new("RemoteEvent")
slapped.Name = "Slapped"
slapped.Parent = remotes
local daily = Instance.new("RemoteEvent")
daily.Name = "DailyReward"
daily.Parent = remotes
remotes.Parent = ReplicatedStorage

-- World + systems
local map = MapBuilder.Build()
GameService.Init(map, notify, treadmill)
Monetization.Init(GameService)
AdminService.Init(GameService, notify, admin)
DailyRewardService.Init(GameService, daily, notify)
CodesService.Init(GameService, codes)
LeaderboardService.Init(GameService, workspace.Map.Town:FindFirstChild("Leaderboards"))
treats.OnServerEvent:Connect(function(player, action, key)
	if action == "Buy" and type(key) == "string" then
		GameService.BuyTreat(player, key)
	end
end)

-- Players
local function onPlayerAdded(player)
	local profile = DataService.Load(player)
	if not player.Parent then
		return -- left while loading
	end
	GameService.AddPlayer(player, profile)
	DailyRewardService.PlayerReady(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	task.spawn(LeaderboardService.SavePlayer, player) -- reads their stats right away, saves in the background
	local profile = GameService.RemovePlayer(player)
	if profile then
		DataService.Save(player, profile)
	end
	DataService.Forget(player)
end)

-- Autosave
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = GameService.Snapshot(player)
			if profile then
				task.spawn(DataService.Save, player, profile)
			end
		end
	end
end)

-- Save everyone when the server shuts down
game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = GameService.Snapshot(player)
		if profile then
			pending += 1
			task.spawn(function()
				DataService.Save(player, profile)
				pending -= 1
			end)
		end
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end)
