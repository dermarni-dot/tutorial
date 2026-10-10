-- PvP: player vs player boxing in the same server.
--   * Challenges: one player challenges another (proximity prompt on his character or the PvP panel);
--     the other gets an accept / decline popup for 20 s. Sparring (no record, headgear, lighter damage)
--     or a Ranked Bout (3 or 6 rounds).
--   * Queue: "Find Match" pairs players by PvP rating; the allowed rating gap widens with the wait and
--     after ~30 s anybody in the queue is a match.
--   * Records: profile.pvp = { rating, peak, w, l, d, ko, koLoss, bouts, spars, recent = { [userId] = { os.time ... } } },
--     created lazily (old saves have none; DataVersion never changes). Ranked results move an Elo-style rating
--     and pay a small purse / a little fame. The same pair farming each other gets less and less (rematch
--     cooldown, diminishing rewards and rating over 24 hours). Career camps, injuries and the career record
--     are never touched by PvP.
-- Main.server.lua owns busy states, characters and the fight itself; it hands this module three hooks
-- (PvP.Init): canFight(player) -> ok, err; startMatch(a, b, mode, rounds); send(player, msg).
local Players = game:GetService("Players")

local PvP = {}

PvP.CHALLENGE_TIMEOUT = 20 -- seconds the challenged player has to answer
PvP.CHALLENGE_GAP = 4 -- seconds between two challenges from the same player
PvP.DECLINE_COOLDOWN = 30 -- a declined challenger waits this long before asking the same player again
PvP.REMATCH_COOLDOWN = 90 -- seconds before the same pair can start another ranked bout
PvP.QUEUE_WIDE_AFTER = 30 -- seconds in the queue after which any opponent is fine
PvP.START_RATING = 1000
PvP.RECENT_WINDOW = 24 * 3600 -- the farming window for diminishing rewards
PvP.MODES = { spar = true, ranked = true }
PvP.ROUNDS = { [3] = true, [6] = true }

local hooks = {}
local challenges = {} -- id -> { id, from, to, mode, rounds, at }
local outgoing = {} -- player -> challenge id
local lastChallengeAt = {} -- player -> os.clock()
local declinedAt = {} -- "fromId:toId" -> os.clock()
local pairLast = {} -- "lowId:highId" -> os.clock() of the last ranked bout
local queue = {} -- player -> { at = os.clock(), rating }
local seq = 0

function PvP.Init(h)
	hooks = h or {}
end

local function send(player, msg)
	if hooks.send and player and player.Parent then
		hooks.send(player, msg)
	end
end

local function canFight(player)
	if not (player and player.Parent) then
		return false, "That player left."
	end
	if hooks.canFight then
		return hooks.canFight(player)
	end
	return true
end

local function pairKey(a, b)
	local x, y = a.UserId, b.UserId
	if x > y then
		x, y = y, x
	end
	return tostring(x) .. ":" .. tostring(y)
end

------------------------------------------------------------------------
-- Profile data (lazy, nil-safe)
------------------------------------------------------------------------
function PvP.Ensure(profile)
	if type(profile) ~= "table" then
		return nil
	end
	local p = profile.pvp
	if type(p) ~= "table" then
		p = {}
		profile.pvp = p
	end
	p.rating = tonumber(p.rating) or PvP.START_RATING
	p.peak = math.max(tonumber(p.peak) or p.rating, p.rating)
	for _, k in ipairs({ "w", "l", "d", "ko", "koLoss", "bouts", "spars" }) do
		p[k] = math.max(0, math.floor(tonumber(p[k]) or 0))
	end
	if type(p.recent) ~= "table" then
		p.recent = {}
	end
	return p
end

-- what the client sees (Summary.pvp) and the other players (the PvPRating player attribute)
function PvP.View(profile)
	local p = type(profile) == "table" and type(profile.pvp) == "table" and profile.pvp or nil
	local rating = p and tonumber(p.rating) or PvP.START_RATING
	return {
		rating = math.floor(rating + 0.5), peak = math.floor((p and tonumber(p.peak) or rating) + 0.5),
		w = p and tonumber(p.w) or 0, l = p and tonumber(p.l) or 0, d = p and tonumber(p.d) or 0,
		ko = p and tonumber(p.ko) or 0, koLoss = p and tonumber(p.koLoss) or 0,
		bouts = p and tonumber(p.bouts) or 0, spars = p and tonumber(p.spars) or 0,
		rank = PvP.RankName(rating),
	}
end

local RANKS = { { 0, "Rookie" }, { 900, "Contender" }, { 1050, "Prospect" }, { 1200, "Veteran" }, { 1350, "Elite" }, { 1500, "Champion" } }
function PvP.RankName(rating)
	rating = tonumber(rating) or PvP.START_RATING
	local name = RANKS[1][2]
	for _, r in ipairs(RANKS) do
		if rating >= r[1] then
			name = r[2]
		end
	end
	return name
end

-- the record shown on the fight HUD's tale of the tape
function PvP.Record(profile)
	local v = PvP.View(profile)
	return { w = v.w, l = v.l, d = v.d, ko = v.ko }
end

------------------------------------------------------------------------
-- Rating & rewards (pure: unit-testable)
------------------------------------------------------------------------
-- Elo: expected score from the rating gap, K 40 for the first 10 ranked bouts, then 28
function PvP.Expected(ra, rb)
	return 1 / (1 + 10 ^ ((rb - ra) / 400))
end

function PvP.RatingDelta(ra, rb, score, bouts, factor)
	local k = ((tonumber(bouts) or 0) < 10) and 40 or 28
	local d = k * (score - PvP.Expected(ra, rb)) * (factor or 1)
	-- symmetric rounding: both sides of a bout move by the same amount
	local r = math.floor(math.abs(d) + 0.5)
	return d < 0 and -r or r
end

-- how many ranked bouts this profile had against that opponent in the farming window (pruning old ones)
function PvP.RecentCount(profile, oppUserId, now)
	local p = PvP.Ensure(profile)
	local key = tostring(oppUserId)
	local list = p.recent[key]
	if type(list) ~= "table" then
		return 0
	end
	local keep = {}
	for _, t in ipairs(list) do
		if type(t) == "number" and now - t < PvP.RECENT_WINDOW then
			table.insert(keep, t)
		end
	end
	p.recent[key] = #keep > 0 and keep or nil
	return #keep
end

-- 1st bout of the day vs that opponent: full; 2nd: half; 3rd: a quarter; 4th and later: nothing
function PvP.Diminish(n)
	if n <= 0 then
		return 1
	elseif n == 1 then
		return 0.5
	elseif n == 2 then
		return 0.25
	end
	return 0
end

local function prune(p, now)
	-- at most 20 opponents remembered (the oldest first out): a save never grows without bound
	local keys = {}
	for k, list in pairs(p.recent) do
		local last = 0
		if type(list) == "table" then
			for _, t in ipairs(list) do
				if type(t) == "number" then
					last = math.max(last, t)
				end
			end
		end
		if now - last >= PvP.RECENT_WINDOW then
			p.recent[k] = nil
		else
			table.insert(keys, { k = k, last = last })
		end
	end
	if #keys > 20 then
		table.sort(keys, function(a, b)
			return a.last > b.last
		end)
		for i = 21, #keys do
			p.recent[keys[i].k] = nil
		end
	end
end

-- Apply a ranked result to both profiles. resA = the result from A's side ({ outcome, method }).
-- Returns { [A] = out, [B] = out } with out = { ratingBefore, rating, delta, money, fame, notes, factor }.
function PvP.ApplyRanked(profA, uidA, profB, uidB, resA, now)
	now = now or os.time()
	local a, b = PvP.Ensure(profA), PvP.Ensure(profB)
	local nA, nB = PvP.RecentCount(profA, uidB, now), PvP.RecentCount(profB, uidA, now)
	local factor = PvP.Diminish(math.max(nA, nB))
	local scoreA = resA.outcome == "win" and 1 or (resA.outcome == "loss" and 0 or 0.5)
	local ko = resA.method == "KO" or resA.method == "TKO"
	local ra, rb = a.rating, b.rating
	local dA = PvP.RatingDelta(ra, rb, scoreA, a.bouts, factor)
	local dB = PvP.RatingDelta(rb, ra, 1 - scoreA, b.bouts, factor)
	local outs = {}
	for _, x in ipairs({ { profA, a, uidB, dA, scoreA, ra }, { profB, b, uidA, dB, 1 - scoreA, rb } }) do
		local profile, p, opp, delta, score, before = x[1], x[2], x[3], x[4], x[5], x[6]
		p.rating = math.max(100, p.rating + delta)
		p.peak = math.max(p.peak, p.rating)
		p.bouts += 1
		if score == 1 then
			p.w += 1
			if ko then
				p.ko += 1
			end
		elseif score == 0 then
			p.l += 1
			if ko then
				p.koLoss += 1
			end
		else
			p.d += 1
		end
		local key = tostring(opp)
		p.recent[key] = type(p.recent[key]) == "table" and p.recent[key] or {}
		table.insert(p.recent[key], now)
		prune(p, now)
		-- a small purse and a little fame (the career is where the money is)
		local money = math.floor(((score == 1 and 400) or (score == 0.5 and 200) or 100) * factor)
		local fame = (score == 1 and 0.5 or (score == 0.5 and 0.2 or 0)) * factor
		profile.money = (tonumber(profile.money) or 0) + money
		if fame > 0 then
			profile.popularity = math.min(100, (tonumber(profile.popularity) or 0) + fame)
		end
		local notes = {}
		table.insert(notes, string.format("PvP rating %d -> %d (%s%d)", math.floor(before + 0.5), math.floor(p.rating + 0.5), delta >= 0 and "+" or "", delta))
		if factor < 1 then
			table.insert(notes, factor > 0 and string.format("Rematch today: rewards x%.2f", factor) or "Too many bouts with this opponent today: no rating or rewards")
		end
		outs[profile] = { ratingBefore = before, rating = p.rating, delta = delta, money = money, fame = fame, notes = notes, factor = factor }
	end
	return outs[profA], outs[profB]
end

function PvP.ApplySpar(profile)
	local p = PvP.Ensure(profile)
	if p then
		p.spars += 1
	end
end

------------------------------------------------------------------------
-- Challenges
------------------------------------------------------------------------
local function clearChallenge(id)
	local c = challenges[id]
	if not c then
		return nil
	end
	challenges[id] = nil
	if outgoing[c.from] == id then
		outgoing[c.from] = nil
	end
	return c
end

-- is this player part of a pending challenge (either side)?
function PvP.Pending(player)
	if outgoing[player] then
		return true
	end
	for _, c in pairs(challenges) do
		if c.to == player then
			return true
		end
	end
	return false
end

function PvP.Challenge(from, target, mode, rounds)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players then
		return { ok = false, err = "That player isn't here." }
	end
	if target == from then
		return { ok = false, err = "You can't challenge yourself." }
	end
	if not PvP.MODES[mode] then
		mode = "spar"
	end
	rounds = tonumber(rounds)
	if mode == "ranked" then
		rounds = PvP.ROUNDS[rounds] and rounds or 3
	else
		rounds = nil
	end
	local now = os.clock()
	if outgoing[from] then
		return { ok = false, err = "You already have a challenge out. Wait for the answer." }
	end
	if now - (lastChallengeAt[from] or -100) < PvP.CHALLENGE_GAP then
		return { ok = false, err = "Slow down - one challenge at a time." }
	end
	if now - (declinedAt[from.UserId .. ":" .. target.UserId] or -1000) < PvP.DECLINE_COOLDOWN then
		return { ok = false, err = target.DisplayName .. " just turned you down. Give it a moment." }
	end
	local ok, err = canFight(from)
	if not ok then
		return { ok = false, err = err }
	end
	ok, err = canFight(target)
	if not ok then
		return { ok = false, err = target.DisplayName .. " can't fight right now (" .. tostring(err) .. ")" }
	end
	if PvP.Pending(target) or queue[target] then
		return { ok = false, err = target.DisplayName .. " is busy with another challenge." }
	end
	if mode == "ranked" then
		local last = pairLast[pairKey(from, target)]
		if last and now - last < PvP.REMATCH_COOLDOWN then
			return { ok = false, err = string.format("Rematch cooldown: %d s", math.ceil(PvP.REMATCH_COOLDOWN - (now - last))) }
		end
	end
	seq += 1
	local id = "c" .. seq
	local c = { id = id, from = from, to = target, mode = mode, rounds = rounds, at = now }
	challenges[id] = c
	outgoing[from] = id
	lastChallengeAt[from] = now
	-- the ask carries the challenger's boxer, record and rating (the client shows them on the popup)
	local info = hooks.describe and hooks.describe(from) or {}
	send(target, { t = "challenge", id = id, from = from.UserId, fromName = from.DisplayName, fromUser = from.Name, mode = mode, rounds = rounds,
		timeout = PvP.CHALLENGE_TIMEOUT, boxer = info.boxer, record = info.record, rating = info.rating, rank = info.rank })
	task.delay(PvP.CHALLENGE_TIMEOUT + 0.5, function()
		if challenges[id] == c then
			clearChallenge(id)
			send(from, { t = "challengeEnd", id = id, why = "timeout", name = target.DisplayName })
			send(target, { t = "challengeEnd", id = id, why = "timeout", name = from.DisplayName })
		end
	end)
	return { ok = true, id = id, timeout = PvP.CHALLENGE_TIMEOUT }
end

function PvP.Respond(player, id, accept)
	local c = type(id) == "string" and challenges[id] or nil
	if not c or c.to ~= player then
		return { ok = false, err = "That challenge is gone." }
	end
	if os.clock() - c.at > PvP.CHALLENGE_TIMEOUT + 0.5 then
		clearChallenge(id)
		return { ok = false, err = "Too late - the challenge expired." }
	end
	clearChallenge(id)
	if accept ~= true then
		declinedAt[c.from.UserId .. ":" .. player.UserId] = os.clock()
		send(c.from, { t = "challengeEnd", id = id, why = "declined", name = player.DisplayName })
		return { ok = true, declined = true }
	end
	local ok, err = canFight(c.from)
	if not ok then
		send(c.from, { t = "challengeEnd", id = id, why = "unavailable", name = player.DisplayName })
		return { ok = false, err = c.from.DisplayName .. " can't fight right now (" .. tostring(err) .. ")" }
	end
	ok, err = canFight(player)
	if not ok then
		send(c.from, { t = "challengeEnd", id = id, why = "unavailable", name = player.DisplayName })
		return { ok = false, err = err }
	end
	PvP.LeaveQueue(c.from)
	PvP.LeaveQueue(player)
	if c.mode == "ranked" then
		pairLast[pairKey(c.from, player)] = os.clock()
	end
	if hooks.startMatch then
		task.spawn(hooks.startMatch, c.from, player, c.mode, c.rounds)
	end
	return { ok = true, accepted = true }
end

function PvP.Cancel(player)
	local id = outgoing[player]
	local c = id and clearChallenge(id)
	if c then
		send(c.to, { t = "challengeEnd", id = id, why = "cancelled", name = player.DisplayName })
		return { ok = true }
	end
	return { ok = false, err = "No challenge to cancel." }
end

------------------------------------------------------------------------
-- Queue ("Find Match": ranked, 3 rounds)
------------------------------------------------------------------------
function PvP.JoinQueue(player, rating)
	if queue[player] then
		return { ok = true, already = true }
	end
	local ok, err = canFight(player)
	if not ok then
		return { ok = false, err = err }
	end
	if outgoing[player] then
		return { ok = false, err = "Cancel your challenge first." }
	end
	queue[player] = { at = os.clock(), rating = tonumber(rating) or PvP.START_RATING }
	send(player, { t = "queue", on = true, size = PvP.QueueSize() })
	return { ok = true }
end

function PvP.LeaveQueue(player, why)
	if queue[player] then
		queue[player] = nil
		send(player, { t = "queue", on = false, why = why })
		return true
	end
	return false
end

function PvP.InQueue(player)
	return queue[player] ~= nil
end

function PvP.QueueSize()
	local n = 0
	for _ in pairs(queue) do
		n += 1
	end
	return n
end

-- the rating gap a player waiting `wait` seconds accepts: 150, +25 a second, anybody after QUEUE_WIDE_AFTER
function PvP.Window(wait)
	if wait >= PvP.QUEUE_WIDE_AFTER then
		return math.huge
	end
	return 150 + 25 * wait
end

-- one matchmaking pass: the longest-waiting player first, paired with the closest rating both accept.
-- Pure over its inputs so it can be unit-tested: entries = { { player, at, rating } }, returns pairs.
function PvP.Match(entries, now)
	table.sort(entries, function(a, b)
		return a.at < b.at
	end)
	local used, pairs_ = {}, {}
	for i, e in ipairs(entries) do
		if not used[i] then
			local best, bestGap
			for j, f in ipairs(entries) do
				if j ~= i and not used[j] then
					local gap = math.abs(e.rating - f.rating)
					if gap <= math.min(PvP.Window(now - e.at), PvP.Window(now - f.at)) and (not best or gap < bestGap) then
						best, bestGap = j, gap
					end
				end
			end
			if best then
				used[i], used[best] = true, true
				table.insert(pairs_, { entries[i].player, entries[best].player })
			end
		end
	end
	return pairs_
end

function PvP.MatchTick()
	local now = os.clock()
	local entries = {}
	for player, q in pairs(queue) do
		if not player.Parent then
			queue[player] = nil
		elseif canFight(player) and not PvP.Pending(player) then
			-- busy players (a drill, the barber) stay queued but are skipped until they are free
			table.insert(entries, { player = player, at = q.at, rating = q.rating })
		end
	end
	for _, pr in ipairs(PvP.Match(entries, now)) do
		local a, b = pr[1], pr[2]
		queue[a], queue[b] = nil, nil
		send(a, { t = "queue", on = false, why = "matched" })
		send(b, { t = "queue", on = false, why = "matched" })
		pairLast[pairKey(a, b)] = now
		if hooks.startMatch then
			task.spawn(hooks.startMatch, a, b, "ranked", 3)
		end
	end
end

function PvP.Start()
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, err = pcall(PvP.MatchTick)
			if not ok then
				warn("[PvP] matchmaking:", err)
			end
		end
	end)
end

-- a player left the server: drop his challenges and his queue spot
function PvP.Remove(player)
	queue[player] = nil
	lastChallengeAt[player] = nil
	for id, c in pairs(challenges) do
		if c.from == player or c.to == player then
			clearChallenge(id)
			local other = c.from == player and c.to or c.from
			send(other, { t = "challengeEnd", id = id, why = "left", name = player.DisplayName })
		end
	end
end

-- the rematch cooldown left for a pair (seconds), for the panel
function PvP.RematchLeft(a, b)
	local last = pairLast[pairKey(a, b)]
	if not last then
		return 0
	end
	return math.max(0, PvP.REMATCH_COOLDOWN - (os.clock() - last))
end

return PvP
