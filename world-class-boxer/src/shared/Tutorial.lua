-- Tutorial: the first-time tutorial fight. Shared and pure (no Roblox services), so the server (FightEngine,
-- Main), the client (the prompt card) and tools/sim load the same rules.
--   * who is offered it: Tutorial.ShouldOffer(profile) (a new player: no career, no past careers, the
--     profile flag tutorialDone not set) and Tutorial.Backfill (an existing save counts as done)
--   * the guided steps (Tutorial.STEPS) and their tracker: FightEngine feeds it what the player does
--     (Tutorial.Feed) and holds the round clock while a step is being learned (Tutorial.Phase)
--   * the prompt's key caps for the device in use, from the real control map (Tutorial.Caps)
-- The bout itself is a real FightEngine fight with a random boxer on both sides (TutorialFight on the
-- server); the career is never touched: only profile.tutorialDone is ever written.
local Tutorial = {}

Tutorial.ROUNDS = 2
Tutorial.ROUND_SECONDS = 60
Tutorial.REST_SECONDS = 6
-- the special move the tutorial boxer owns (a plain two-jab burst: no set-up to explain)
Tutorial.SPECIAL = "doublejab"
-- round 1 teaches the punches and ends a few seconds after this step; round 2 the defence and the finish
Tutorial.LAST_ROUND1 = "body"
Tutorial.BREAK_SECONDS = 3
Tutorial.MOVE_DIST = 4 -- studs of footwork for "move"
Tutorial.BLOCK_TIME = 1 -- seconds of guard held for "block"
Tutorial.STAM_LOW = 0.75 -- "drain": stamina at or under this share of the tank
Tutorial.STAM_REFILL = 0.12 -- "refill": this much of the tank back from the lowest point
Tutorial.STAM_TIMEOUT = 30 -- the stamina step moves on by itself after this long
-- a player who walks away: after this long the clock runs whatever step is up (the bout ends on its own)
Tutorial.MAX_HOLD = 480
-- the forgiving fight: what the player's punches and the opponent's do, the knockdown odds on the
-- opponent once the last step is up, and the opponent's defensive reactions
Tutorial.DAMAGE_TAKEN = 0.2
Tutorial.DAMAGE_DEALT = 1.35
Tutorial.KO_MUL = 2.5
Tutorial.AI_DEFENSE = 0.3

-- id, title, text, actions = the Keymap actions the card shows, goals = what completes the step (all of
-- them), aiWork = how busy the opponent is meanwhile (FightAI's punch rate), final = the last step
Tutorial.STEPS = {
	{ id = "move", title = "MOVE", text = "Step around the ring: walk in to close the distance, back off to make room.",
		actions = { "move" }, goals = { "move" }, aiWork = 0.15 },
	{ id = "jab", title = "THE JAB", text = "Throw a jab. It is fast and cheap: it measures the distance and starts every combination.",
		actions = { "jab" }, goals = { "jab" }, aiWork = 0.2 },
	{ id = "cross", title = "THE CROSS", text = "Now the cross: the straight right hand, your power punch behind the jab.",
		actions = { "cross" }, goals = { "cross" }, aiWork = 0.2 },
	{ id = "power", title = "HOOKS & UPPERCUTS", text = "Get close and throw a hook and an uppercut. They hit hardest from short range.",
		actions = { "leadhook", "rearhook", "uppercut" }, goals = { "hook", "uppercut" }, aiWork = 0.25 },
	{ id = "body", title = "BODY SHOTS", text = "Arm a body shot, then punch: it lands low and drains his stamina.",
		actions = { "body", "bodyhook" }, goals = { "body" }, aiWork = 0.25 },
	{ id = "block", title = "BLOCK", text = "He is coming at you now. Raise your guard and hold it: a block eats most of a head shot.",
		actions = { "block" }, goals = { "block" }, aiWork = 1.1 },
	{ id = "slip", title = "SLIP & DODGE", text = "Move your head: slip to either side, or roll under his punches.",
		actions = { "slipL", "slipR", "dodge" }, goals = { "dodge" }, aiWork = 1.1 },
	{ id = "stamina", title = "STAMINA", text = "Every punch costs stamina: watch the STAMINA bar under your HEAD and BODY bars. Throw a flurry, then ease off and let it refill.",
		actions = {}, goals = { "drain", "refill" }, aiWork = 0.5 },
	{ id = "special", title = "SPECIAL MOVE", text = "Throw your special move, the Double jab. Specials have a cooldown: pick your moment.",
		actions = { "special_doublejab" }, goals = { "special" }, aiWork = 0.5 },
	{ id = "finish", title = "FINISH IT", text = "Put it all together: knock him down, or see the round out.",
		actions = { "jab", "cross", "leadhook", "uppercut" }, goals = { "finish" }, aiWork = 0.6, final = true },
}
Tutorial.ById = {}
for i, s in ipairs(Tutorial.STEPS) do
	s.index = i
	Tutorial.ById[s.id] = s
end
-- the goals' checklist words (shown when a step has more than one)
Tutorial.GoalText = { hook = "A hook", uppercut = "An uppercut", drain = "Drain it below 75%", refill = "Let it refill" }
-- the captions beside the key caps
Tutorial.ActionText = {
	move = "MOVE", jab = "JAB", cross = "CROSS", leadhook = "LEAD HOOK", rearhook = "REAR HOOK", uppercut = "UPPERCUT",
	body = "BODY SHOT", bodyhook = "BODY HOOK", block = "BLOCK", slipL = "SLIP LEFT", slipR = "SLIP RIGHT", dodge = "DODGE",
	special_doublejab = "DOUBLE JAB",
}

------------------------------------------------------------------------
-- Who gets it
------------------------------------------------------------------------
-- a new player: no boxer, no career behind him, the flag not set (profile = the server's profile)
function Tutorial.ShouldOffer(profile)
	if type(profile) ~= "table" then
		return false
	end
	if profile.tutorialDone == true or profile.created == true or profile.retired == true or profile.final ~= nil then
		return false
	end
	if type(profile.pastCareers) == "table" and #profile.pastCareers > 0 then
		return false
	end
	return true
end

-- DataManager's load: `stored` is what the DataStore held (nil for a first join), `data` the playable profile
-- made from it. Anyone who already played (a saved career, or a save of an older version of the game) counts
-- as done; a first join and a blank save stay as they are. Returns data.
function Tutorial.Backfill(stored, data, version)
	if type(data) ~= "table" then
		return data
	end
	if type(stored) == "table" and (stored.created == true or stored.tutorialDone == true or (version ~= nil and stored.v ~= version)
		or (type(stored.pastCareers) == "table" and #stored.pastCareers > 0)) then
		data.tutorialDone = true
	end
	if data.created == true then
		data.tutorialDone = true
	end
	return data
end

-- the flag, once the tutorial is over (how = "completed" | "skipped" | "crashed"; "left" / "aborted" set
-- nothing: the player is offered it again). The only field of a profile the tutorial ever writes.
function Tutorial.MarkDone(profile, how)
	if type(profile) ~= "table" or how == "left" or how == "aborted" then
		return false
	end
	profile.tutorialDone = true
	return true
end

------------------------------------------------------------------------
-- The steps
------------------------------------------------------------------------
function Tutorial.NewTracker()
	return { step = 1, goals = {}, moved = 0, blockTime = 0, stamLow = nil, stepAt = nil, startedAt = nil, done = false, timedOut = false }
end

function Tutorial.Current(tr)
	return Tutorial.STEPS[tr.step]
end

local function advance(tr)
	tr.step += 1
	tr.goals = {}
	tr.stepAt = nil
	tr.stamLow = nil
	tr.timedOut = false
	if tr.step > #Tutorial.STEPS then
		tr.step = #Tutorial.STEPS
		tr.done = true
	end
end

-- mark a goal of the current step; returns true when anything changed (the step may have advanced)
local function reach(tr, goal)
	local s = Tutorial.STEPS[tr.step]
	if tr.goals[goal] or not table.find(s.goals, goal) then
		return false
	end
	tr.goals[goal] = true
	for _, g in ipairs(s.goals) do
		if not tr.goals[g] then
			return true
		end
	end
	if s.final then
		tr.goals = { finish = true }
		tr.done = true
	else
		advance(tr)
	end
	return true
end

-- what the player did (the fight engine's view). ev.k:
--   move { dist }   punch { p, body }   block { dt }   blocked   slip   roll   special { id }
--   stamina { pct } (share of the tank)   kd (the opponent went down)   bell   end   tick
-- ev.now = the fight clock (seconds), on every event. Returns true when the tracker changed.
function Tutorial.Feed(tr, ev)
	if tr.done or type(ev) ~= "table" then
		return false
	end
	local now = tonumber(ev.now)
	if now then
		tr.startedAt = tr.startedAt or now
		tr.stepAt = tr.stepAt or now
	end
	local s = Tutorial.STEPS[tr.step]
	local k = ev.k
	local id = s.id
	if id == "move" then
		if k == "move" then
			tr.moved += math.max(0, tonumber(ev.dist) or 0)
			if tr.moved >= Tutorial.MOVE_DIST then
				return reach(tr, "move")
			end
		end
	elseif id == "jab" then
		if k == "punch" and ev.p == "jab" then
			return reach(tr, "jab")
		end
	elseif id == "cross" then
		if k == "punch" and ev.p == "cross" then
			return reach(tr, "cross")
		end
	elseif id == "power" then
		if k == "punch" and (ev.p == "leadhook" or ev.p == "rearhook") then
			return reach(tr, "hook")
		elseif k == "punch" and ev.p == "uppercut" then
			return reach(tr, "uppercut")
		end
	elseif id == "body" then
		if k == "punch" and ev.body == true then
			return reach(tr, "body")
		end
	elseif id == "block" then
		if k == "blocked" then
			return reach(tr, "block")
		elseif k == "block" then
			tr.blockTime += math.max(0, tonumber(ev.dt) or 0)
			if tr.blockTime >= Tutorial.BLOCK_TIME then
				return reach(tr, "block")
			end
		end
	elseif id == "slip" then
		if k == "slip" or k == "roll" then
			return reach(tr, "dodge")
		end
	elseif id == "stamina" then
		if k == "stamina" then
			local pct = tonumber(ev.pct)
			if pct and pct == pct then
				if not tr.goals.drain then
					if pct <= Tutorial.STAM_LOW then
						tr.stamLow = pct
						return reach(tr, "drain")
					end
				else
					tr.stamLow = math.min(tr.stamLow or pct, pct)
					if pct >= tr.stamLow + Tutorial.STAM_REFILL then
						return reach(tr, "refill")
					end
				end
			end
		elseif k == "tick" and now and tr.stepAt and now - tr.stepAt >= Tutorial.STAM_TIMEOUT then
			tr.timedOut = true
			reach(tr, "drain")
			return reach(tr, "refill")
		end
	elseif id == "special" then
		if k == "special" then
			return reach(tr, "special")
		end
	elseif s.final then
		if k == "kd" or k == "bell" or k == "end" then
			return reach(tr, "finish")
		end
	end
	return false
end

-- the round clock: "hold" (frozen while a step is being learned), "break" (round 1 is done: end it a few
-- seconds from now) or "run". now = the fight clock (the MAX_HOLD safety: an idle player's bout ends)
function Tutorial.Phase(tr, round, now)
	if tr.done then
		return "run"
	end
	if now and tr.startedAt and now - tr.startedAt >= Tutorial.MAX_HOLD then
		return "run"
	end
	local last = Tutorial.ById[Tutorial.LAST_ROUND1].index
	if (tonumber(round) or 1) <= 1 then
		return tr.step > last and "break" or "hold"
	end
	return Tutorial.STEPS[tr.step].final and "run" or "hold"
end

-- may the opponent be knocked down / stopped yet? (only once the last step is up)
function Tutorial.CanDrop(tr)
	return tr.done or Tutorial.STEPS[tr.step].final == true
end

function Tutorial.AiWork(tr)
	return tr.done and 0.6 or (Tutorial.STEPS[tr.step].aiWork or 0.5)
end

-- the message the client's prompt card draws (FightRemote t = "tutorial")
function Tutorial.View(tr)
	return { t = "tutorial", step = tr.step, total = #Tutorial.STEPS, id = Tutorial.STEPS[tr.step].id, goals = table.clone(tr.goals), done = tr.done, timedOut = tr.timedOut }
end

------------------------------------------------------------------------
-- The prompt's key caps (device = "keyboard" | "gamepad" | "touch"; map = the control map in use,
-- Settings.Keymap() / Keymap.Resolve(saved); Gamepad = the button names module, optional)
------------------------------------------------------------------------
local function touchText(a)
	local t = a.touch
	if type(t) ~= "string" or t == "" or t == "-" then
		return "-"
	end
	if t == "Thumbstick" then
		return "LEFT STICK"
	end
	-- a pad's own name (JAB, HOOK, 2x JAB) is tapped; a gesture ("Swipe BLOCK left") reads as it is
	if not t:find("%l%l") then
		return "TAP " .. t
	end
	return string.upper(t)
end

function Tutorial.KeyText(actionId, device, map, Keymap, Gamepad)
	local a = Keymap.ById[actionId]
	if not a then
		return "-"
	end
	if device == "touch" then
		return touchText(a)
	end
	if device == "gamepad" or device == "pad" then
		return Keymap.ActionText(map, actionId, "pad", Gamepad)
	end
	return Keymap.ActionText(map, actionId, "kbd", Gamepad)
end

-- { { action, key, label } } for a step on a device
function Tutorial.Caps(step, device, map, Keymap, Gamepad)
	local s = type(step) == "table" and step or Tutorial.ById[step] or Tutorial.STEPS[tonumber(step) or 0]
	local out = {}
	if not s then
		return out
	end
	for _, id in ipairs(s.actions) do
		local key = Tutorial.KeyText(id, device, map, Keymap, Gamepad)
		table.insert(out, { action = id, key = key, label = Tutorial.ActionText[id] or string.upper(id) })
	end
	return out
end

return Tutorial
