-- DataManager: loads/saves each player's career with DataStoreService.
-- If Studio API access is off, the game still runs (progress lasts for the session only).
-- Old-version saves start a fresh career but keep the list of past careers.
-- Saves of the current version are brought up to date in place by Training.Migrate
-- (new fields are added, never removed): Config.DataVersion must not be bumped for additions.
--
-- Save safety: a career is only ever WRITTEN after it was READ successfully (or found empty). When the
-- store fails at join, the player has no profile (the client stays on its loading screen), the read is
-- retried in the background, and after about two minutes of failures the player is kicked with a clear
-- message. A blank placeholder can therefore never overwrite a real career. Every write carries a save
-- counter (saveSeq): a server whose copy is older than the stored one (another server saved since)
-- refuses to write instead of rolling the career back. The counter this server holds only moves after a
-- write is confirmed, and each write is stamped with this session's id (saveSession) so overlapping saves
-- of one session never refuse each other. Failed writes are retried with backoff.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)
local Training = require(script.Parent:WaitForChild("Training"))

local DataManager = {}
DataManager.Profiles = {}
DataManager.StoreAvailable = true
-- set by Main: called (in its own thread) when a load that failed at join finally succeeds
DataManager.OnLoaded = nil
local lastSave = {}
local pending = {}
local canSave = {} -- player -> true once the stored career was read (or found empty)
local loadFailed = {} -- player -> true while the read keeps failing (no profile, retrying)
local seqOf = {} -- player -> save counter of the copy this server holds (only raised after a write lands)
local session = {} -- player -> id stamped on this server's writes (overlapping saves of one session never conflict)
local dirty = {} -- player -> true after a failed write (the next autosave must not be skipped)
local releasing = {} -- userId -> true while the leave save is in flight (a quick rejoin waits for it)

local LOAD_TRIES = 3 -- quick attempts during the join
local RETRY_DELAYS = { 5, 10, 15, 20, 30, 40 } -- background re-reads before giving up (2 minutes)
local SAVE_BACKOFF = { 1, 2, 4 } -- waits between write attempts (4 attempts)
local RELEASE_BUDGET = 20 -- seconds a leave save keeps retrying
local LOAD_FAIL_KICK = "We couldn't load your saved career (Roblox's data servers are not responding). Nothing was lost - please rejoin in a minute."
local CONFLICT_KICK = "Your career was saved from another server. Please rejoin to continue with the latest save."

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

local function keyOf(player)
	return "u_" .. player.UserId
end

local function seqField(data)
	return type(data) == "table" and tonumber(data.saveSeq) or 0
end

function DataManager.Blank(pastCareers)
	return { v = Config.DataVersion, created = false, pastCareers = pastCareers or {} }
end

-- stored value -> playable profile (blank, old version, migration)
local function prepare(data)
	if type(data) ~= "table" then
		data = DataManager.Blank()
	elseif data.v ~= Config.DataVersion then
		-- a save from an older version of the game: keep the hall of past careers
		data = DataManager.Blank(type(data.pastCareers) == "table" and data.pastCareers or {})
	end
	if type(data.pastCareers) ~= "table" then
		data.pastCareers = {}
	end
	if data.created then
		-- additive backfill (sub-muscles, soreness, face damage, medicine ball station, v2 looks...);
		-- a bug here must never cost a player the career, so it is guarded and the save kept as is
		local ok, err = pcall(Training.Migrate, data)
		if not ok then
			warn("[Boxer] Save migration failed, career loaded unchanged:", err)
		end
	end
	return data
end

local function read(player, tries)
	local ok, result
	for attempt = 1, tries do
		ok, result = pcall(function()
			return store:GetAsync(keyOf(player))
		end)
		if ok or attempt == tries then
			break
		end
		task.wait(attempt)
	end
	return ok, result
end

local function install(player, raw)
	local data = prepare(raw)
	seqOf[player] = seqField(raw)
	session[player] = HttpService:GenerateGUID(false)
	canSave[player] = true
	loadFailed[player] = nil
	DataManager.Profiles[player] = data
	return data
end

-- the join-time read failed: keep the player profile-less and try again until it works or we give up
local function retryLoad(player)
	for _, delay in ipairs(RETRY_DELAYS) do
		task.wait(delay)
		if not (player.Parent and loadFailed[player]) then
			return
		end
		local ok, result = read(player, 1)
		if not player.Parent then
			return
		end
		if ok then
			install(player, result)
			print("[Boxer] Career loaded after a retry for", player.Name)
			if DataManager.OnLoaded then
				task.spawn(DataManager.OnLoaded, player)
			end
			return
		end
		warn("[Boxer] Load retry failed:", result)
	end
	if player.Parent and loadFailed[player] then
		player:Kick(LOAD_FAIL_KICK)
	end
end

function DataManager.Load(player)
	-- a quick rejoin on this server: let the leave save land first so the newest career is read
	local t0 = os.clock()
	while releasing[player.UserId] and os.clock() - t0 < RELEASE_BUDGET + 10 do
		task.wait(0.25)
	end
	if not store then
		-- no DataStore at all (Studio without API access): a session-only career, never written
		local data = prepare(nil)
		if player.Parent then
			DataManager.Profiles[player] = data
		end
		return data
	end
	local ok, result = read(player, LOAD_TRIES)
	if not player.Parent then
		return nil
	end
	if ok then
		return install(player, result)
	end
	warn("[Boxer] Load failed:", result)
	if RunService:IsStudio() then
		-- Studio with API access off fails every read: play session-only, nothing is ever written
		DataManager.StoreAvailable = false
		local data = prepare(nil)
		DataManager.Profiles[player] = data
		return data
	end
	-- never hand out a blank placeholder: a later save of it would wipe the real career
	loadFailed[player] = true
	task.spawn(retryLoad, player)
	return nil
end

-- true while the player's save could not be read yet (Main reports "loading" to the client)
function DataManager.LoadPending(player)
	return loadFailed[player] == true
end

-- can this player's progress be written? (Hub shows "saving is off" when not)
function DataManager.CanSave(player)
	return store ~= nil and canSave[player] == true
end

function DataManager.Get(player)
	return DataManager.Profiles[player]
end

function DataManager.Set(player, profile)
	DataManager.Profiles[player] = profile
end

-- one UpdateAsync with retries; returns true when the career is safely stored
local function write(player, data)
	local key = keyOf(player)
	local conflict = false
	for attempt = 1, #SAVE_BACKOFF + 1 do
		-- seqOf only moves after a write is confirmed: a transform that ran but was not committed (the call
		-- errored, or Roblox re-ran it because another server wrote in between) must not claim the next number
		local base = seqOf[player] or 0
		local mine = session[player]
		local stamped = nil
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				local stored = seqField(old)
				local ours = mine ~= nil and type(old) == "table" and old.saveSession == mine
				if stored > base and not ours then
					-- another server wrote a newer copy after ours was read: never roll it back
					conflict = true
					stamped = nil
					return nil
				end
				conflict = false
				stamped = stored + 1
				data.saveSeq = stamped
				data.saveSession = mine
				return data
			end)
		end)
		if ok then
			if not conflict and stamped then
				seqOf[player] = math.max(seqOf[player] or 0, stamped)
			end
			if conflict then
				warn("[Boxer] Save refused: a newer save exists for", player.Name)
				canSave[player] = nil
				if player.Parent and not releasing[player.UserId] and not RunService:IsStudio() then
					player:Kick(CONFLICT_KICK)
				end
				return false
			end
			return true
		end
		warn("[Boxer] Save failed (attempt " .. attempt .. "):", err)
		local wait = SAVE_BACKOFF[attempt]
		if not wait or DataManager.Profiles[player] ~= data then
			break
		end
		task.wait(wait)
	end
	return false
end

function DataManager.Save(player, force)
	local data = DataManager.Profiles[player]
	if not data or not store or not canSave[player] then
		return false
	end
	local now = os.clock()
	if not force and not dirty[player] and lastSave[player] and now - lastSave[player] < 7 then
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
		return false
	end
	lastSave[player] = now
	local ok = write(player, data)
	if ok then
		dirty[player] = nil
	elseif canSave[player] then
		-- still failing after the retries: keep trying in the background until a write lands
		dirty[player] = true
		if not pending[player] then
			pending[player] = true
			task.delay(15, function()
				pending[player] = nil
				if DataManager.Profiles[player] and dirty[player] then
					DataManager.Save(player, true)
				end
			end)
		end
	end
	return ok
end

local function forget(player)
	DataManager.Profiles[player] = nil
	lastSave[player] = nil
	canSave[player] = nil
	loadFailed[player] = nil
	seqOf[player] = nil
	session[player] = nil
	dirty[player] = nil
end

function DataManager.Release(player)
	local userId = player.UserId
	if not (store and canSave[player] and DataManager.Profiles[player]) then
		forget(player)
		return
	end
	releasing[userId] = true
	-- the last save of the session: keep retrying (a transient error must not lose the session)
	local t0 = os.clock()
	while not DataManager.Save(player, true) and canSave[player] and os.clock() - t0 < RELEASE_BUDGET do
		task.wait(2)
	end
	forget(player)
	releasing[userId] = nil
end

-- server shutdown: wait for the leave saves in flight (PlayerRemoving runs Release for everyone)
function DataManager.WaitForReleases(timeout)
	local t0 = os.clock()
	while next(releasing) and os.clock() - t0 < (timeout or 25) do
		task.wait(0.25)
	end
end

return DataManager
