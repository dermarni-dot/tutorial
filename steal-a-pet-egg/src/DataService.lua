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
		Index = {}, -- [pet name] = true for every pet you've ever had
		Treat = nil, -- { Key, Until } while a treat is active (Until = os.time())
		Codes = {}, -- [code] = true for every code this player has used
		-- lifetime stats for the leaderboards
		Stats = { TimePlayed = 0, Hatched = 0, Stolen = 0, Collected = 0, Slapped = 0 },
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
		if type(data.Index) == "table" then
			for name, found in pairs(data.Index) do
				if type(name) == "string" and found == true then
					profile.Index[name] = true
				end
			end
		end
		if type(data.Treat) == "table" and Config.TreatByKey[data.Treat.Key] and (tonumber(data.Treat.Until) or 0) > os.time() then
			profile.Treat = { Key = data.Treat.Key, Until = math.floor(tonumber(data.Treat.Until)) }
		end
		if type(data.Codes) == "table" then
			for code, used in pairs(data.Codes) do
				if type(code) == "string" and used == true then
					profile.Codes[code] = true
				end
			end
		end
		if type(data.Stats) == "table" then
			for key in pairs(profile.Stats) do
				profile.Stats[key] = math.max(0, math.floor(tonumber(data.Stats[key]) or 0))
			end
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
		Index = profile.Index,
		Treat = profile.Treat,
		Codes = profile.Codes,
		Stats = profile.Stats,
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
