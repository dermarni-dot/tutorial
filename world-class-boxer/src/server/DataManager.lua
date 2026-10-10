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
--
-- Session lock: the stored value also carries `lock = { job, at }`, the server playing the career and the
-- time of its last save. The load is an UpdateAsync that takes the lock in the same step it reads, and it
-- leaves the value untouched while another server's lock is fresh: a player who hops servers while the
-- previous server is still retrying their leave save waits on the loading screen (polling) until that save
-- lands (the leave save clears the lock) instead of playing a copy that would later be refused. A lock that
-- never clears (the previous server died) is taken over after LOCK_WAIT, and one older than LOCK_TTL is dead
-- and ignored outright. Every save refreshes the lock, and a lock-only heartbeat keeps it fresh while a player
-- goes minutes without a save (Main's autosave skips busy players: a pro fight runs up to ~13 minutes); the
-- leave save and the shutdown saves clear it, and so does a server whose player left before playing the
-- career it read (gave up on the loading screen), so the next server never waits for a lock nobody uses.
-- The leave save is the session's last write: once it is under way no other save of the player is sent (a
-- write retry, the 15 s retry of a failed save, a late Save from Main; the leave save stores the same
-- profile). A save sent before it but served during or after it never takes the lock back: it leaves the lock
-- as it is while the leave is under way, clears it once the session here is over, and stores nothing once the
-- next server has taken the career (a save counter moved under that server would get its first save refused).
-- Should a newer save still land after this server read the career (the previous server's write stuck for
-- longer than the wait), the refused save re-reads the stored copy and the player plays on from it (only
-- what was done here since the join is lost) rather than being kicked; the kick stays as the last resort. A
-- save of the dropped copy that was still retrying never writes it over the newer one.
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
-- optional, set by Main: called instead of OnLoaded when a refused save replaced the profile with the
-- newer stored copy (push the new state and tell the player); falls back to OnLoaded
DataManager.OnRefreshed = nil
local lastSave = {}
local pending = {}
local canSave = {} -- player -> true once the stored career was read (or found empty)
local loadFailed = {} -- player -> true while the read keeps failing (no profile, retrying)
local seqOf = {} -- player -> save counter of the copy this server holds (only raised after a write lands)
local session = {} -- player -> id stamped on this server's writes (overlapping saves of one session never conflict)
local dirty = {} -- player -> true after a failed write (the next autosave must not be skipped)
local releasing = {} -- userId -> true while the leave save is in flight (a quick rejoin waits for it)
local joinedAt = {} -- player -> os.clock() of the join (how long a load may wait for another server's lock)
local lockAt = {} -- player -> os.clock() of this server's last stored lock for the career (load, save, heartbeat)
local beating = {} -- player -> true while a heartbeat write is in flight
local closing = false -- true once the server is shutting down (the shutdown saves hand the careers over)

local LOAD_TRIES = 3 -- quick attempts during the join
local RETRY_DELAYS = { 5, 10, 15, 20, 30, 40 } -- background re-reads before giving up (2 minutes)
local SAVE_BACKOFF = { 1, 2, 4 } -- waits between write attempts (4 attempts)
local RELEASE_BUDGET = 20 -- seconds a leave save keeps retrying
local LOCK_TTL = 180 -- s: a lock last refreshed longer ago belongs to a dead server (see LOCK_BEAT)
-- s without a lock write before the heartbeat refreshes it: just over Main's 2-minute autosave, so a player
-- who is saved regularly costs no extra write; a live lock is then at most ~135 s old, and a failed beat is
-- retried every BEAT_RETRY s (twice before the lock would pass LOCK_TTL)
local LOCK_BEAT = 130
local BEAT_CHECK = 5 -- s between the heartbeat's looks at the players
local BEAT_RETRY = 15
local LOCK_WAIT = RELEASE_BUDGET + 10 -- s a join waits for another server's fresh lock (its leave save, retries included)
local LOCK_POLL = 3 -- s between the polls of a held lock
local SIZE_WARN = 3 * 1024 * 1024 -- bytes: a career this big is heading for the 4 MB DataStore limit
local LOAD_FAIL_KICK = "We couldn't load your saved career (Roblox's data servers are not responding). Nothing was lost - please rejoin in a minute."
local CONFLICT_KICK = "Your career was saved from another server. Please rejoin to continue with the latest save."

-- this server's name in the locks (Studio and the test runner have no JobId)
local SERVER_ID = type(game.JobId) == "string" and game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)

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

-- is this lock another live server's? (our own lock is simply re-taken: a quick rejoin here, or a leave save
-- that never landed)
local function heldElsewhere(lock, now)
	return type(lock) == "table" and lock.job ~= SERVER_ID and now - (tonumber(lock.at) or 0) < LOCK_TTL
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

-- one read that takes the session lock in the same UpdateAsync: returns ok, stored value, locked.
-- Another server's fresh lock leaves the value untouched (locked = true) unless `steal` is set; nothing
-- stored yet is left as nothing (the first save creates the record, lock included).
local function read(player, tries, steal)
	local key = keyOf(player)
	local ok, err
	for attempt = 1, tries do
		local raw, held = nil, false
		ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				-- the transform may run more than once: it only reads `old` and sets the locals
				raw, held = old, false
				if type(old) ~= "table" then
					return nil
				end
				local now = os.time()
				if not steal and heldElsewhere(old.lock, now) then
					held = true
					return nil
				end
				old.lock = { job = SERVER_ID, at = now }
				return old
			end)
		end)
		if ok then
			return true, raw, held
		end
		if attempt < tries then
			task.wait(attempt)
		end
	end
	return false, err, false
end

-- rough size of the stored value (the DataStore limit is 4 MB): checked at the two quiet moments of a
-- session so a career that keeps growing is noticed long before its saves start failing
local function checkSize(player, data)
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
	if ok and #encoded > SIZE_WARN then
		warn(string.format("[Boxer] Career of %s is %.1f MB (DataStore limit 4 MB)", player.Name, #encoded / 1048576))
	end
end

local function install(player, raw)
	local data = prepare(raw)
	seqOf[player] = seqField(raw)
	session[player] = HttpService:GenerateGUID(false)
	canSave[player] = true
	loadFailed[player] = nil
	-- the load wrote the lock: the next plain save keeps the DataStore's 6 s per-key write spacing
	lastSave[player] = type(raw) == "table" and os.clock() or nil
	lockAt[player] = lastSave[player]
	DataManager.Profiles[player] = data
	checkSize(player, data)
	return data
end

-- how long this player has been waiting for the career since the join
local function waited(player)
	return os.clock() - (joinedAt[player] or os.clock())
end

-- the player left before playing the career a read of ours just locked (gave up on the loading screen, or
-- left during a re-read): hand the lock back, or the player's next server would wait LOCK_WAIT for it.
-- Only this server's own lock is cleared; the career and its save counter are never touched.
local function unlock(player)
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(player), function(old)
			if type(old) == "table" and type(old.lock) == "table" and old.lock.job == SERVER_ID then
				old.lock = nil
				return old
			end
			return nil
		end)
	end)
	if not ok then
		warn("[Boxer] Lock hand-back failed (the next server waits for it):", err)
	end
end

-- the join-time read failed: keep the player profile-less and try again until it works or we give up
local function retryLoad(player)
	for _, delay in ipairs(RETRY_DELAYS) do
		task.wait(delay)
		if not (player.Parent and loadFailed[player]) then
			return
		end
		local ok, result, locked = read(player, 1, waited(player) >= LOCK_WAIT)
		if not player.Parent then
			if ok and not locked and type(result) == "table" then
				unlock(player)
			end
			return
		end
		if ok and not locked then
			install(player, result)
			print("[Boxer] Career loaded after a retry for", player.Name)
			if DataManager.OnLoaded then
				task.spawn(DataManager.OnLoaded, player)
			end
			return
		end
		warn("[Boxer] Load retry failed:", locked and "another server still holds the career" or result)
	end
	if player.Parent and loadFailed[player] then
		player:Kick(LOAD_FAIL_KICK)
	end
end

-- read with the lock, waiting while another server still holds the career (polling until its leave save
-- clears the lock, then taking the lock over LOCK_WAIT after `since`); returns ok, stored value, and whether
-- the read stored this server's lock. A player who leaves while it waits stops the polling: a poll after the
-- leave would take the lock for nobody.
local function acquire(player, since)
	local ok, result, locked = read(player, LOAD_TRIES)
	while ok and locked do
		task.wait(LOCK_POLL)
		if not player.Parent then
			return false, "player left", false
		end
		ok, result, locked = read(player, 1, os.clock() - since >= LOCK_WAIT)
	end
	return ok, result, ok and type(result) == "table"
end

function DataManager.Load(player)
	joinedAt[player] = os.clock()
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
	local ok, result, took = acquire(player, joinedAt[player])
	if not player.Parent then
		if took then
			unlock(player)
		end
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

-- a save was refused because the stored career moved on after this server read it (the previous server's
-- leave save landed late): play on from the newer copy, which must not be rolled back; only what was done
-- here since the join is lost. The kick remains for when the re-read fails too. A server that still holds
-- the career gets the same LOCK_WAIT as at a join (counted from now, not from the join).
local function refresh(player)
	local ok, result, took = acquire(player, os.clock())
	if not player.Parent then
		if took then
			unlock(player)
		end
		return
	end
	if canSave[player] then
		-- another refused save's re-read already installed the newer copy
		return
	end
	if ok then
		install(player, result)
		warn("[Boxer] Career refreshed from a newer save for", player.Name)
		local hook = DataManager.OnRefreshed or DataManager.OnLoaded
		if hook then
			task.spawn(hook, player)
		end
	elseif not RunService:IsStudio() then
		player:Kick(CONFLICT_KICK)
	end
end

-- one UpdateAsync with retries; returns true when the career is safely stored. `leaving` marks the leave
-- save: the only write that hands the lock over (with the shutdown saves) and the only one still retried
-- once the leave is under way.
local function write(player, data, leaving)
	local key = keyOf(player)
	local userId = player.UserId
	local conflict = false
	for attempt = 1, #SAVE_BACKOFF + 1 do
		-- seqOf only moves after a write is confirmed: a transform that ran but was not committed (the call
		-- errored, or Roblox re-ran it because another server wrote in between) must not claim the next number
		local base = seqOf[player] or 0
		local mine = session[player]
		local stamped = nil
		local moved = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				local stored = seqField(old)
				local ours = mine ~= nil and type(old) == "table" and old.saveSession == mine
				moved = false
				if stored > base and not ours then
					-- another server wrote a newer copy after ours was read: never roll it back
					conflict = true
					stamped = nil
					return nil
				end
				conflict = false
				-- a save of a session that is ending here (the leave save is under way, or over) other than
				-- the leave save itself: the leave save stores this same profile and hands the lock over
				local ending = not leaving and (releasing[userId] or not canSave[player])
				if ending and type(old) == "table" and heldElsewhere(old.lock, os.time()) then
					-- the next server already took the career over: a save counter moved under it now would
					-- get its first save refused
					moved = true
					stamped = nil
					return nil
				end
				stamped = stored + 1
				data.saveSeq = stamped
				data.saveSession = mine
				-- the lock travels with every save (a fresh stamp says this server is still playing the
				-- career); the leave save and the shutdown saves hand it over to the next server, and a write
				-- that lands once the session here is over (forget cleared canSave) never takes it back. One
				-- served while the leave is under way leaves the lock as it is: the leave save clears it
				-- (if that already landed the lock stays clear, if not the next server keeps waiting for it).
				if leaving or closing or not canSave[player] then
					data.lock = nil
				elseif releasing[userId] then
					data.lock = type(old) == "table" and old.lock or nil
				else
					data.lock = { job = SERVER_ID, at = os.time() }
				end
				return data
			end)
		end)
		if moved then
			return false
		end
		if ok then
			if not conflict and stamped then
				seqOf[player] = math.max(seqOf[player] or 0, stamped)
				if canSave[player] and not (releasing[userId] or closing) then
					lockAt[player] = os.clock()
				end
			end
			if conflict then
				if DataManager.Profiles[player] ~= data then
					-- a copy this server already dropped (a refresh installed the newer one meanwhile): the
					-- profile played now is not affected, so it keeps saving and nothing is re-read
					return false
				end
				warn("[Boxer] Save refused: a newer save exists for", player.Name)
				canSave[player] = nil
				if player.Parent and not releasing[userId] and not closing then
					task.spawn(refresh, player)
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
		-- the copy may have been dropped during the wait (another save was refused and the refresh installed
		-- the newer stored copy with its own counter): a retry would store the discarded table over it as the
		-- next save. Save() marks the player dirty, and its retry saves the profile played now. Once the
		-- leave is under way only the leave save retries (it stores this same profile, and a retry sent
		-- after it would land after it).
		if DataManager.Profiles[player] ~= data or not canSave[player] or (releasing[userId] and not leaving) then
			break
		end
	end
	return false
end

local function save(player, force, leaving)
	local data = DataManager.Profiles[player]
	if not data or not store or not canSave[player] then
		return false
	end
	if releasing[player.UserId] and not leaving then
		-- the leave save is under way and stores this same profile; a write sent now would land after it
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
	local ok = write(player, data, leaving)
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

function DataManager.Save(player, force)
	return save(player, force, false)
end

local function forget(player)
	DataManager.Profiles[player] = nil
	lastSave[player] = nil
	canSave[player] = nil
	loadFailed[player] = nil
	seqOf[player] = nil
	session[player] = nil
	dirty[player] = nil
	joinedAt[player] = nil
	lockAt[player] = nil
end

function DataManager.Release(player)
	local userId = player.UserId
	if not (store and canSave[player] and DataManager.Profiles[player]) then
		-- never played here (or a refused save's re-read is still out): no leave save, but a lock a read of
		-- ours stored must not outlive the player (a read still in flight hands its own back when it lands)
		local readOk = store and DataManager.StoreAvailable and not loadFailed[player]
		forget(player)
		if readOk then
			unlock(player)
		end
		return
	end
	releasing[userId] = true
	checkSize(player, DataManager.Profiles[player])
	-- the last save of the session: keep retrying (a transient error must not lose the session)
	local t0 = os.clock()
	while not save(player, true, true) and canSave[player] and os.clock() - t0 < RELEASE_BUDGET do
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

-- keep this server's lock fresh for a player who goes minutes without a save (Main's autosave skips busy
-- players, and a pro fight saves only at the result): a lock-only write that refreshes our own lock, or puts
-- it back if a hand-back cleared it, as long as the stored copy is still the one this server holds. It never
-- touches the career or its save counter, never takes a lock another server holds fresh, and stops for the
-- leave save and at shutdown (those clear the lock for the next server).
local function beat(player)
	local userId = player.UserId
	local base = seqOf[player] or 0
	beating[player] = true
	local wrote = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(player), function(old)
			wrote = false
			if type(old) ~= "table" or seqField(old) ~= base or releasing[userId] or closing or not canSave[player] then
				return nil
			end
			local now = os.time()
			if heldElsewhere(old.lock, now) then
				return nil
			end
			old.lock = { job = SERVER_ID, at = now }
			wrote = true
			return old
		end)
	end)
	beating[player] = nil
	if not lockAt[player] then
		return -- the player left meanwhile
	end
	if ok then
		lockAt[player] = os.clock()
		if wrote then
			lastSave[player] = os.clock() -- the DataStore's per-key write spacing, as after a save
		end
	else
		lockAt[player] = os.clock() - LOCK_BEAT + BEAT_RETRY
		warn("[Boxer] Lock heartbeat failed:", err)
	end
end

if store then
	task.spawn(function()
		while true do
			task.wait(BEAT_CHECK)
			if not closing then
				local now = os.clock()
				local due = {}
				for player, at in pairs(lockAt) do
					if now - at >= LOCK_BEAT and canSave[player] and not beating[player] and not releasing[player.UserId] then
						table.insert(due, player)
					end
				end
				for _, player in ipairs(due) do
					task.spawn(beat, player)
				end
			end
		end
	end)
end

-- the shutdown saves (Main's BindToClose saves everyone before the leave saves) already hand the careers
-- over: every write from now on clears the lock, so a player who lands on the next server never waits
pcall(function()
	game:BindToClose(function()
		closing = true
	end)
end)

return DataManager
