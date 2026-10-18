-- AvatarLook: a player's own Roblox avatar hair and face on their boxer (server side; Config.AvatarLook).
-- * Request(userId, onReady): the avatar record from the cache, or nil while it is fetched in the background
--   (Players:GetHumanoidDescriptionFromUserId, pcall'd, never blocking the caller); onReady(rec) runs when a
--   fetch that was still pending succeeds. A failed fetch is retried after Config.AvatarLook.retry seconds,
--   doubling up to maxRetry. Forget(userId) when the player leaves.
-- * FromDescription(desc) -> rec = { useHair, hair = "id,id" (normalised, at most maxHair), face, head }:
--   the only fields copied into the boxer's HumanoidDescription (never body parts, scales, clothes, other
--   accessories). Key(rec) is what Builder puts in the ScaleKey and the AvatarLook model attribute;
--   State(key) reads it back ({ hair = bool, face = bool, dynamic = bool }).
-- * ApplyFailed(userId): ApplyDescription refused the avatar's items (offsale / deleted): the game look for
--   maxRetry seconds, then the avatar is tried again.
-- * ParseIds(v): asset ids from a number, "123", "rbxassetid://123", catalog / asset URLs or a comma list.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local AvatarLook = {}

-- tests replace these (a fake Players with GetHumanoidDescriptionFromUserId, a clock)
AvatarLook.Services = {}
local function players()
	return AvatarLook.Services.Players or game:GetService("Players")
end
local function now()
	return AvatarLook.Services.clock and AvatarLook.Services.clock() or os.clock()
end
local function cfg()
	return Config.AvatarLook or {}
end

------------------------------------------------------------------------
-- Ids
------------------------------------------------------------------------
local function idOf(s)
	s = string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
	if s == "" then
		return nil
	end
	local n = string.match(s, "^(%d+)$")
		or string.match(s, "^rbxassetid://(%d+)$")
		or string.match(s, "[?&]id=(%d+)")
		or string.match(s, "roblox%.com/catalog/(%d+)")
		or string.match(s, "roblox%.com/library/(%d+)")
		or string.match(s, "create%.roblox%.com/store/asset/(%d+)")
	n = tonumber(n)
	return (n and n > 0) and n or nil
end

-- every asset id in v (number, string, comma-separated string, or a list of those), in order, no repeats
function AvatarLook.ParseIds(v)
	local out, seen = {}, {}
	local function add(n)
		if n and not seen[n] then
			seen[n] = true
			table.insert(out, n)
		end
	end
	local function one(x)
		if type(x) == "number" then
			add((x == x and x > 0 and x % 1 == 0) and x or nil)
		elseif type(x) == "string" then
			-- (a URL has no commas; a list of ids does)
			for piece in string.gmatch(x, "[^,]+") do
				add(idOf(piece))
			end
		end
	end
	if type(v) == "table" then
		for _, x in ipairs(v) do
			one(x)
		end
	else
		one(v)
	end
	return out
end

------------------------------------------------------------------------
-- Records
------------------------------------------------------------------------
function AvatarLook.Enabled(app)
	local c = cfg()
	return c.enabled ~= false and (c.hair ~= false or c.face ~= false) and not (type(app) == "table" and app.avatar == false)
end

function AvatarLook.FromDescription(desc)
	local c = cfg()
	local ids = AvatarLook.ParseIds(desc and desc.HairAccessory or "")
	local cap = tonumber(c.maxHair) or 8
	while #ids > cap do
		table.remove(ids)
	end
	local strs = {}
	for i, n in ipairs(ids) do
		strs[i] = string.format("%d", n)
	end
	local face = c.face ~= false and math.max(0, math.floor(tonumber(desc and desc.Face) or 0)) or 0
	local head = c.face ~= false and math.max(0, math.floor(tonumber(desc and desc.Head) or 0)) or 0
	return { useHair = c.hair ~= false, hair = c.hair ~= false and table.concat(strs, ",") or "", face = face, head = head }
end

-- "" for no record: the ScaleKey / attribute of a boxer on the game look are exactly what they were
function AvatarLook.Key(rec)
	if type(rec) ~= "table" then
		return ""
	end
	return string.format("A%s|f%d|d%d", rec.useHair and ("h" .. (rec.hair or "")) or "-", rec.face or 0, rec.head or 0)
end

-- what a key applied: hair = the avatar's hair replaces the game hair (even none: bald), face = the avatar's
-- face / head replaces the classic face, dynamic = a Dynamic Head
function AvatarLook.State(key)
	if type(key) ~= "string" or string.sub(key, 1, 1) ~= "A" then
		return { hair = false, face = false, dynamic = false }
	end
	local h, f, d = string.match(key, "^A([^|]*)|f(%d+)|d(%d+)$")
	f, d = tonumber(f) or 0, tonumber(d) or 0
	return { hair = h ~= nil and string.sub(h, 1, 1) == "h", face = f > 0 or d > 0, dynamic = d > 0 }
end

------------------------------------------------------------------------
-- Fetching (per user, cached for the session)
------------------------------------------------------------------------
local cache = {} -- userId -> { rec, pending, tries, nextTry, badUntil, waiters, gen }

function AvatarLook.Get(userId)
	local e = cache[userId]
	if not (e and e.rec) then
		return nil
	end
	if e.badUntil and now() < e.badUntil then
		return nil
	end
	return e.rec
end

local fetch
local function schedule(userId, e, delay)
	local gen = e.gen
	task.delay(delay, function()
		if cache[userId] == e and e.gen == gen and not e.rec and not e.pending then
			fetch(userId, e)
		end
	end)
end

function fetch(userId, e)
	e.pending = true
	local ok, desc = pcall(function()
		return players():GetHumanoidDescriptionFromUserId(userId)
	end)
	e.pending = false
	if cache[userId] ~= e then
		return -- forgotten (the player left) while the request was out
	end
	if ok and desc then
		local okR, rec = pcall(AvatarLook.FromDescription, desc)
		if okR and rec then
			e.rec = rec
			local waiters = e.waiters
			e.waiters = {}
			for _, fn in ipairs(waiters) do
				task.spawn(fn, rec)
			end
			return
		end
		desc = rec
	end
	e.tries += 1
	local c = cfg()
	local wait = math.min((tonumber(c.retry) or 20) * 2 ^ (e.tries - 1), tonumber(c.maxRetry) or 600)
	e.nextTry = now() + wait
	warn(string.format("[Boxer] avatar look for %s not loaded (retry in %ds):", tostring(userId), math.floor(wait)), desc)
	schedule(userId, e, wait)
end

-- the record now, or nil (and a background fetch, once; onReady(rec) when it arrives)
function AvatarLook.Request(userId, onReady)
	if type(userId) ~= "number" or userId <= 0 then
		return nil -- (Studio test players / NPCs: no avatar)
	end
	local e = cache[userId]
	if not e then
		e = { tries = 0, nextTry = 0, waiters = {}, gen = 0 }
		cache[userId] = e
	end
	if e.rec then
		return AvatarLook.Get(userId)
	end
	if onReady and not table.find(e.waiters, onReady) then
		table.insert(e.waiters, onReady)
	end
	if not e.pending and now() >= e.nextTry then
		task.spawn(fetch, userId, e)
	end
	return nil
end

function AvatarLook.ApplyFailed(userId)
	local e = cache[userId]
	if e and e.rec then
		e.badUntil = now() + (tonumber(cfg().maxRetry) or 600)
	end
end

function AvatarLook.Forget(userId)
	local e = cache[userId]
	if e then
		e.gen += 1
	end
	cache[userId] = nil
end

-- tests
function AvatarLook.Reset()
	for _, e in pairs(cache) do
		e.gen += 1
	end
	table.clear(cache)
end

return AvatarLook
