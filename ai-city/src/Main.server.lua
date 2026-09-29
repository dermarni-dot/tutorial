-- Main (Script) — ServerScriptService.Main
-- Builds AI City and runs the day/night cycle.
-- Your citizen, election and speech scripts can get the map with:
--   local map = require(ServerScriptService.Modules.MapBuilder).Build()
-- (Build only builds once; every later call returns the same map.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MapBuilder = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("MapBuilder"))

local RUN_DAY_CYCLE = true -- set to false if another script already moves Lighting.ClockTime
local START_HOUR = 8

local map = MapBuilder.Build()
print(string.format("[AI City] Built %d places, %d homes, %d walking points", #map.PlaceList, #map.Homes, #map.Nodes))

-- Day and night: one in-game day lasts Config.DAY_LENGTH real seconds.
-- Street lamps and windows light up between 18:30 and 6:30.
local function hourNow()
	return Lighting.ClockTime
end

local function refreshNight()
	local h = hourNow()
	MapBuilder.SetNight(h >= 18.5 or h < 6.5)
	if map.ClockFace then
		local hour = math.floor(h)
		local minute = math.floor((h - hour) * 60)
		map.ClockFace.Text = string.format("%02d:%02d", hour, minute)
	end
end

if RUN_DAY_CYCLE then
	Lighting.ClockTime = START_HOUR
	task.spawn(function()
		local hoursPerSecond = 24 / Config.DAY_LENGTH
		local last = os.clock()
		while true do
			task.wait(0.5)
			local now = os.clock()
			Lighting.ClockTime = (Lighting.ClockTime + (now - last) * hoursPerSecond) % 24
			last = now
			refreshNight()
		end
	end)
else
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(refreshNight)
end
refreshNight()

MapBuilder.SetNews("Welcome to AI City! Give a speech on the plaza stage and win the next election.")
