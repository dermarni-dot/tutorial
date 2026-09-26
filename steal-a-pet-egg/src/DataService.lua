-- DataService (ModuleScript) — ServerScriptService.Modules.DataService
-- Loads and saves each player's cash, slot count and nest (eggs + creatures).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DataService = {}

local store = nil
local ok, err = pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)
if not ok then
	warn("[DataService] DataStores unavailable, progress won't save:", err)
end

-- Only save players whose data loaded correctly, so a failed load
-- never overwrites real progress with a fresh profile.
local canSave = {}

local function keyFor(player)
	return "player_" .. player.UserId
end

local function defaults()
	return {
		Cash = Config.StartingCash,
		Slots = Config.StartingSlots,
		Speed = Config.StartingSpeed,
		SpeedBuys = 0,
		TreadmillLevel = 1,
		Nest = {},
		Daily = { Streak = 0, LastDay = -1 },
	}
end

function DataService.Load(player)
	local profile = defaults()
	canSave[player.UserId] = false
	if not store then
		return profile
	end

	local success, data
	for _ = 1, 3 do
		success, data = pcall(store.GetAsync, store, keyFor(player))
		if success then
			break
		end
		task.wait(1)
	end

	if not success then
		warn("[DataService] Could not load data for", player.Name, "- saving disabled this session:", data)
		return profile
	end

	canSave[player.UserId] = true
	if type(data) == "table" then
		profile.Cash = tonumber(data.Cash) or profile.Cash
		profile.Slots = math.clamp(tonumber(data.Slots) or profile.Slots, Config.StartingSlots, Config.MaxSlots)
		profile.Speed = math.max(0, math.floor(tonumber(data.Speed) or profile.Speed))
		profile.SpeedBuys = math.max(0, math.floor(tonumber(data.SpeedBuys) or 0))
		profile.TreadmillLevel = math.clamp(math.floor(tonumber(data.TreadmillLevel) or 1), 1, #Config.TreadmillLevels)
		if type(data.Nest) == "table" then
			profile.Nest = data.Nest
		end
		if type(data.Daily) == "table" then
			profile.Daily.Streak = math.max(0, math.floor(tonumber(data.Daily.Streak) or 0))
			profile.Daily.LastDay = math.floor(tonumber(data.Daily.LastDay) or -1)
		end
	end
	return profile
end

function DataService.Save(player, profile)
	if not store or not canSave[player.UserId] then
		return false
	end
	local payload = {
		Cash = math.floor(profile.Cash),
		Slots = profile.Slots,
		Speed = profile.Speed,
		SpeedBuys = profile.SpeedBuys,
		TreadmillLevel = profile.TreadmillLevel,
		Nest = profile.Nest,
		Daily = profile.Daily,
		Version = 2,
	}
	for attempt = 1, 3 do
		local success, saveErr = pcall(store.SetAsync, store, keyFor(player), payload)
		if success then
			return true
		end
		warn("[DataService] Save failed for", player.Name, "attempt", attempt, saveErr)
		task.wait(1)
	end
	return false
end

function DataService.Forget(player)
	canSave[player.UserId] = nil
end

return DataService
