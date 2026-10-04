-- DataManager: loads/saves each player's career with DataStoreService.
-- If Studio API access is off, the game still runs (progress lasts for the session only).
-- Old-version saves start a fresh career but keep the list of past careers.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local DataManager = {}
DataManager.Profiles = {}
DataManager.StoreAvailable = true
local lastSave = {}
local pending = {}

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		DataManager.StoreAvailable = false
		warn("[Boxer] DataStore unavailable (enable Studio API access to save):", result)
	end
end

function DataManager.Blank(pastCareers)
	return { v = Config.DataVersion, created = false, pastCareers = pastCareers or {} }
end

function DataManager.Load(player)
	local data
	if store then
		local ok, result
		for attempt = 1, 3 do
			ok, result = pcall(function()
				return store:GetAsync("u_" .. player.UserId)
			end)
			if ok then
				break
			end
			task.wait(attempt)
		end
		if ok then
			data = result
		else
			warn("[Boxer] Load failed:", result)
			DataManager.StoreAvailable = false
		end
	end
	if type(data) ~= "table" then
		data = DataManager.Blank()
	elseif data.v ~= Config.DataVersion then
		-- a save from an older version of the game: keep the hall of past careers
		data = DataManager.Blank(type(data.pastCareers) == "table" and data.pastCareers or {})
	end
	data.pastCareers = data.pastCareers or {}
	if player.Parent then
		DataManager.Profiles[player] = data
	end
	return data
end

function DataManager.Get(player)
	return DataManager.Profiles[player]
end

function DataManager.Set(player, profile)
	DataManager.Profiles[player] = profile
end

function DataManager.Save(player, force)
	local data = DataManager.Profiles[player]
	if not data or not store then
		return
	end
	local now = os.clock()
	if not force and lastSave[player] and now - lastSave[player] < 7 then
		-- DataStore write budget: at most one save every few seconds per player; save again shortly
		if not pending[player] then
			pending[player] = true
			task.delay(7 - (now - lastSave[player]) + 0.1, function()
				pending[player] = nil
				if DataManager.Profiles[player] then
					DataManager.Save(player)
				end
			end)
		end
		return
	end
	lastSave[player] = now
	local ok, err = pcall(function()
		store:UpdateAsync("u_" .. player.UserId, function()
			return data
		end)
	end)
	if not ok then
		warn("[Boxer] Save failed:", err)
	end
end

function DataManager.Release(player)
	DataManager.Save(player, true)
	DataManager.Profiles[player] = nil
	lastSave[player] = nil
end

return DataManager
