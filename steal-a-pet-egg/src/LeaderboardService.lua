-- LeaderboardService (ModuleScript) — ServerScriptService.Modules.LeaderboardService
-- Global leaderboards: every 90 seconds this server saves its players' stats to one
-- OrderedDataStore per board (Config.Leaderboards) and reads back the top 10,
-- then writes them onto the boards in town (built by MapBuilder).
-- If DataStores aren't available (Studio without API access), the boards rank
-- the players in this server instead.
-- Boards are read one at a time, a few seconds apart, to stay inside Roblox's
-- DataStore request limits.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local LeaderboardService = {}

local GameService
local boardsFolder
local stores = {} -- [key] = OrderedDataStore
local lastSaved = {} -- [userId] = { [key] = value }
local nameCache = {} -- [userId] = name
local globalOk = true

local MAX_VALUE = 2 ^ 53 -- OrderedDataStore needs whole numbers

local function format(info, value)
	if info.Format == "Money" then
		return Util.Money(value)
	elseif info.Format == "Time" then
		local minutes = math.floor(value / 60)
		if minutes < 60 then
			return minutes .. "m"
		end
		local hours = minutes // 60
		if hours < 100 then
			return hours .. "h " .. (minutes % 60) .. "m"
		end
		return Util.FormatNumber(hours) .. "h"
	end
	return Util.FormatNumber(value)
end

local function nameFor(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameCache[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = if ok and name then name else "Player"
	return nameCache[userId]
end

local function budget(requestType)
	local ok, left = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, requestType)
	return if ok then left else 0
end

-- Write rows onto one board. entries = { { UserId, Value } } sorted high to low.
local function draw(info, entries, note)
	local board = boardsFolder and boardsFolder:FindFirstChild(info.Key)
	local bg = board and board:FindFirstChild("Screen") and board.Screen:FindFirstChild("Board") and board.Screen.Board:FindFirstChild("Bg")
	if not bg then
		return
	end
	for r = 1, Config.LeaderboardSize do
		local row = bg:FindFirstChild("Row" .. r)
		if row then
			local entry = entries[r]
			row.PlayerName.Text = if entry then nameFor(entry.UserId) else "---"
			row.Value.Text = if entry then format(info, entry.Value) else ""
		end
	end
	bg.Updated.Text = note
end

-- Save the stats of everyone in this server (only values that changed).
local function saveAll()
	for _, player in ipairs(Players:GetPlayers()) do
		LeaderboardService.SavePlayer(player)
	end
end

function LeaderboardService.SavePlayer(player)
	if not globalOk then
		return
	end
	local stats = GameService.GetLeaderStats(player)
	if not stats then
		return
	end
	local saved = lastSaved[player.UserId] or {}
	lastSaved[player.UserId] = saved
	for _, info in ipairs(Config.Leaderboards) do
		local value = math.clamp(math.floor(tonumber(stats[info.Key]) or 0), 0, MAX_VALUE)
		local store = stores[info.Key]
		if store and value > 0 and saved[info.Key] ~= value and budget(Enum.DataStoreRequestType.SetIncrementSortedAsync) > 0 then
			local ok = pcall(store.SetAsync, store, tostring(player.UserId), value)
			if ok then
				saved[info.Key] = value
			end
		end
	end
end

-- This server's players only, for when the global boards can't be read.
local function localTop(info)
	local entries = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local stats = GameService.GetLeaderStats(player)
		if stats then
			table.insert(entries, { UserId = player.UserId, Value = math.floor(tonumber(stats[info.Key]) or 0) })
		end
	end
	table.sort(entries, function(a, b)
		return a.Value > b.Value
	end)
	return entries
end

local function refreshBoard(info)
	local store = stores[info.Key]
	if globalOk and store and budget(Enum.DataStoreRequestType.GetSortedAsync) > 0 then
		local ok, pages = pcall(store.GetSortedAsync, store, false, Config.LeaderboardSize)
		if ok and pages then
			local entries = {}
			for _, item in ipairs(pages:GetCurrentPage()) do
				table.insert(entries, { UserId = tonumber(item.key) or 0, Value = item.value })
			end
			-- players online right now show their live value if it's higher
			local byId = {}
			for _, e in ipairs(entries) do
				byId[e.UserId] = e
			end
			for _, e in ipairs(localTop(info)) do
				local existing = byId[e.UserId]
				if existing then
					existing.Value = math.max(existing.Value, e.Value)
				elseif e.Value > 0 then
					table.insert(entries, e)
				end
			end
			table.sort(entries, function(a, b)
				return a.Value > b.Value
			end)
			draw(info, entries, "🌍 All servers • updates every 90s")
			return
		end
	end
	draw(info, localTop(info), "🏠 This server • updates every 90s")
end

function LeaderboardService.Init(gameService, folder)
	GameService = gameService
	boardsFolder = folder
	for _, info in ipairs(Config.Leaderboards) do
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "Leaderboard_" .. info.Key)
		if ok then
			stores[info.Key] = store
		else
			globalOk = false
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastSaved[player.UserId] = nil
	end)

	task.spawn(function()
		task.wait(8) -- let the first players load in
		while true do
			saveAll()
			-- spread the board reads out across the refresh interval
			local gap = Config.LeaderboardRefresh / #Config.Leaderboards
			for _, info in ipairs(Config.Leaderboards) do
				refreshBoard(info)
				task.wait(gap)
			end
		end
	end)
end

return LeaderboardService
