-- Tutorial: the guided fights. Shared and pure (no Roblox services), so the server (FightEngine, Main), the client
-- (the step card) and tools/sim load the same rules. Two bouts use it:
--   * the DEBUT (the main first-time flow): a new player's first career fight, offered right after the creator. A
--     real Career bout with his own boxer (Career.DebutOffer: a weak amateur from his world, the community centre);
--     it counts for the career like any other. The step card guides it, the rules are forgiving for that one
--     bout (Tutorial.Debut) and the win still has to be earned. Who: Tutorial.ShouldOfferDebut (profile.debut =
--     "offer", set by CreateBoxer for a player with no past careers; old saves never have it). Leaving or a reset
--     mid-bout calls it off: nothing is recorded and it is offered again (Tutorial.MarkDebut).
--   * the PRACTICE ROUND (optional, Settings > PRACTICE ROUND): a short bout with a random boxer against a random
--     opponent (TutorialFight). The career is never touched: only profile.tutorialDone is ever written.
--     Tutorial.ShouldOffer / Backfill keep the old flag's rules (no longer offered on its own at the first join:
--     the debut replaced it as the first-time flow).
-- Both share the guided steps (Tutorial.Steps, the tracker: Tutorial.Feed, the round clock: Tutorial.Phase) and the
-- prompt's key caps for the device in use, from the real control map (Tutorial.Caps).
local Tutorial = {}

Tutorial.ROUNDS = 2
Tutorial.ROUND_SECONDS = 60
Tutorial.REST_SECONDS = 6
-- the special move the practice boxer owns (a plain two-jab burst: no set-up to explain)
Tutorial.SPECIAL = "doublejab"
-- round 1 teaches the punches and ends a few seconds after this step; round 2 the defence and the finish
Tutorial.LAST_ROUND1 = "combo"
Tutorial.BREAK_SECONDS = 3
Tutorial.MOVE_DIST = 4 -- studs of footwork for "move"
Tutorial.BLOCK_TIME = 1 -- seconds of guard held for "block"
Tutorial.STAM_LOW = 0.75 -- "drain": stamina at or under this share of the tank
Tutorial.STAM_REFILL = 0.12 -- "refill": this much of the tank back from the lowest point
Tutorial.STAM_TIMEOUT = 30 -- the stamina step moves on by itself after this long
-- a player who walks away: after this long the clock runs whatever step is up (the bout ends on its own)
Tutorial.MAX_HOLD = 480
-- the practice round's forgiving fight: what the player's punches and the opponent's do, the knockdown odds on
-- the opponent once the last step is up, and the opponent's defensive reactions
Tutorial.DAMAGE_TAKEN = 0.2
Tutorial.DAMAGE_DEALT = 1.35
Tutorial.KO_MUL = 2.5
Tutorial.AI_DEFENSE = 0.3
-- the debut's rules: honest, only gentler. Half the damage coming in, the player's own punches as they are, the
-- opponent's defence softer while a step is being learned (and nearly normal after), no stoppage of the player
-- (no knockdown, no referee or doctor stoppage) before the final round, the opponent only droppable once the last
-- step is up; the opponent is a weak amateur from the career's world (OPP_BELOW: his overall this far under the
-- player's), in a small venue with a modest crowd
Tutorial.Debut = {
	DAMAGE_TAKEN = 0.5, DAMAGE_DEALT = 1.0, KO_MUL = 1.0,
	AI_DEFENSE = 0.55, AI_DEFENSE_DONE = 0.85, AI_WORK_DONE = 0.85,
	OPP_BELOW = { 16, 6 }, VENUE = "CommunityCenter", IMPORTANCE = 0.2, SUPPORTERS = 0.35,
}

-- the steps. id, title, text, actions = the Keymap actions the card shows, goals = what completes the step (all of
-- them), aiWork = how busy the opponent is meanwhile (FightAI's punch rate), timeout = the step moves on by
-- itself after this long (seconds), final = the last step
local BASE = {
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
	{ id = "combo", title = "COMBINATIONS", text = "Punch in rhythm: throw the next one just as the last comes back. Try the 1-2 (jab, cross) or the 1-2-3.",
		actions = { "jab", "cross", "leadhook" }, goals = { "combo" }, aiWork = 0.25, timeout = 45 },
	{ id = "block", title = "BLOCK", text = "He is coming at you now. Raise your guard and hold it: a block eats most of a head shot.",
		actions = { "block" }, goals = { "block" }, aiWork = 1.1 },
	{ id = "slip", title = "SLIP & WEAVE", text = "Move your head: slip a straight to either side, weave or duck under a hook.",
		actions = { "slipL", "slipR", "weaveL", "duck" }, goals = { "dodge" }, aiWork = 1.1 },
	{ id = "counter", title = "DODGE & COUNTER", text = "Make him miss, then fire straight back: a punch right after a dodge is a counter.",
		actions = { "slipL", "weaveL", "jab", "cross" }, goals = { "counter" }, aiWork = 1.1, timeout = 40 },
	{ id = "stamina", title = "STAMINA", text = "Every punch costs stamina: watch the STAMINA bar under your HEAD and BODY bars. Throw a flurry, then ease off and let it refill.",
		actions = {}, goals = { "drain", "refill" }, aiWork = 0.5, timeout = Tutorial.STAM_TIMEOUT },
	{ id = "special", title = "SPECIAL MOVE", text = "Throw your special move, the Double jab. Specials have a cooldown: pick your moment.",
		actions = { "special_doublejab" }, goals = { "special" }, aiWork = 0.5 },
	{ id = "finish", title = "FINISH IT", text = "Put it all together: knock him down, or see the round out.",
		actions = { "jab", "cross", "leadhook", "uppercut" }, goals = { "finish" }, aiWork = 0.6, final = true },
}

-- the steps of a bout. opts = { debut = true, special = a Moves id or nil, specialName = its name }: the practice
-- round (no opts) has every step with the Double jab; the debut has the special step only when the boxer owns a
-- special move (his first unlocked one), and its last step is the rest of the fight
function Tutorial.Steps(opts)
	opts = type(opts) == "table" and opts or {}
	local out = {}
	for _, b in ipairs(BASE) do
		local s = table.clone(b)
		s.actions = table.clone(b.actions)
		s.goals = table.clone(b.goals)
		if s.id == "special" then
			if opts.debut then
				if type(opts.special) ~= "string" or opts.special == "" then
					s = nil
				else
					s.actions = { "special_" .. opts.special }
					s.text = string.format("Throw your special move, the %s. Specials have a cooldown: pick your moment.", tostring(opts.specialName or opts.special))
				end
			end
		elseif s.id == "finish" and opts.debut then
			s.title = "WIN IT"
			s.text = "That's everything. The rest is up to you: box smart and win your debut. The clock runs to the final bell."
		end
		if s then
			table.insert(out, s)
		end
	end
	for i, s in ipairs(out) do
		s.index = i
	end
	return out
end

Tutorial.STEPS = Tutorial.Steps()
Tutorial.ById = {}
for _, s in ipairs(Tutorial.STEPS) do
	Tutorial.ById[s.id] = s
end
-- the goals' checklist words (shown when a step has more than one)
Tutorial.GoalText = { hook = "A hook", uppercut = "An uppercut", drain = "Drain it below 75%", refill = "Let it refill" }
-- the captions beside the key caps
Tutorial.ActionText = {
	move = "MOVE", jab = "JAB", cross = "CROSS", leadhook = "LEAD HOOK", rearhook = "REAR HOOK", uppercut = "UPPERCUT",
	body = "BODY SHOT", bodyhook = "BODY HOOK", block = "BLOCK", slipL = "SLIP LEFT", slipR = "SLIP RIGHT", dodge = "DODGE",
	weaveL = "WEAVE", weaveR = "WEAVE RIGHT", duck = "DUCK", pull = "PULL BACK", sidestepL = "SIDE-STEP",
	special_doublejab = "DOUBLE JAB",
}

------------------------------------------------------------------------
-- Who gets it
------------------------------------------------------------------------
-- the practice round's old first-join rule: a new player: no boxer, no career behind him, the flag not set
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

-- the debut: a boxer made this session's creator marked (profile.debut = "offer"), not retired, nothing booked, no
-- bout fought yet
local function bouts(r)
	if type(r) ~= "table" then
		return 0
	end
	return (tonumber(r.w) or 0) + (tonumber(r.l) or 0) + (tonumber(r.d) or 0)
end
function Tutorial.ShouldOfferDebut(profile)
	if type(profile) ~= "table" or profile.debut ~= "offer" then
		return false
	end
	if profile.created ~= true or profile.retired == true or profile.camp ~= nil then
		return false
	end
	return bouts(profile.record) + bouts(profile.amateurRecord) == 0
end

-- CreateBoxer: a first-time player's new boxer is offered the guided debut (a player with past careers is not)
function Tutorial.NewBoxer(profile, pastCareers)
	if type(profile) ~= "table" then
		return false
	end
	if type(pastCareers) == "table" and #pastCareers > 0 then
		profile.debut = nil
		return false
	end
	profile.debut = "offer"
	return true
end

-- the end of a debut (how = "completed" (the result was recorded) | "skipped" | "left" | "aborted" | "crashed").
-- Only a recorded result or a skip ends the offer; a bout called off is offered again. Returns true when it wrote.
function Tutorial.MarkDebut(profile, how)
	if type(profile) ~= "table" then
		return false
	end
	if how == "completed" then
		profile.debut = "done"
		return true
	elseif how == "skipped" then
		profile.debut = "skipped"
		return true
	end
	return false
end

-- DataManager's load: `stored` is what the DataStore held (nil for a first join), `data` the playable profile
-- made from it. Anyone who already played (a saved career, or a save of an older version of the game) counts
-- as done; a first join and a blank save stay as they are. A debut that was under way when the session ended
-- (its camp is marked debut) is called off: no camp, offered again. Returns data.
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
	if type(data.camp) == "table" and data.camp.debut == true then
		data.camp = nil
		if data.debut ~= "done" and data.debut ~= "skipped" then
			data.debut = "offer"
		end
	end
	if data.debut ~= nil and data.debut ~= "offer" and data.debut ~= "done" and data.debut ~= "skipped" then
		data.debut = nil
	end
	if data.debut == "offer" and data.created ~= true then
		data.debut = nil
	end
	return data
end

-- the flag, once the practice round is over (how = "completed" | "skipped" | "crashed"; "left" / "aborted" set
-- nothing: the player is offered it again). The only field of a profile the practice round ever writes.
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
-- opts: Tutorial.Steps' (debut, special, specialName) and rounds (the bout's)
function Tutorial.NewTracker(opts)
	opts = type(opts) == "table" and opts or {}
	return {
		step = 1, goals = {}, moved = 0, blockTime = 0, stamLow = nil, stepAt = nil, startedAt = nil, done = false, timedOut = false,
		steps = Tutorial.Steps(opts), debut = opts.debut == true, special = opts.special, specialName = opts.specialName, rounds = tonumber(opts.rounds),
	}
end

local function stepsOf(tr)
	return tr.steps or Tutorial.STEPS
end

function Tutorial.Current(tr)
	return stepsOf(tr)[tr.step]
end

-- the index of a step id in this bout (nil when it has no such step)
function Tutorial.IndexOf(tr, id)
	for i, s in ipairs(stepsOf(tr)) do
		if s.id == id then
			return i
		end
	end
	return nil
end

local function advance(tr)
	tr.step += 1
	tr.goals = {}
	tr.stepAt = nil
	tr.stamLow = nil
	tr.timedOut = false
	if tr.step > #stepsOf(tr) then
		tr.step = #stepsOf(tr)
		tr.done = true
	end
end

-- mark a goal of the current step; returns true when anything changed (the step may have advanced)
local function reach(tr, goal)
	local s = stepsOf(tr)[tr.step]
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
--   move { dist }   punch { p, body }   block { dt }   blocked   slip   roll   dodge { kind }   special { id }
--   combo { id, counter } (a named combination thrown in rhythm; counter = out of a dodge)
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
	local s = stepsOf(tr)[tr.step]
	local k = ev.k
	local id = s.id
	-- a step with a timeout moves on by itself (the stamina step, the combo and the counter steps)
	if k == "tick" and s.timeout and now and tr.stepAt and now - tr.stepAt >= s.timeout then
		tr.timedOut = true
		local changed = false
		for _, g in ipairs(table.clone(s.goals)) do
			changed = reach(tr, g) or changed
		end
		return changed
	end
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
	elseif id == "combo" then
		if k == "combo" and ev.counter ~= true then
			return reach(tr, "combo")
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
		if k == "slip" or k == "roll" or k == "dodge" then
			return reach(tr, "dodge")
		end
	elseif id == "counter" then
		if k == "combo" and ev.counter == true then
			return reach(tr, "counter")
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
-- seconds from now) or "run". now = the fight clock (the MAX_HOLD safety: an idle player's bout ends). The
-- debut's final round always runs (its steps are a guide, not a gate on the result)
function Tutorial.Phase(tr, round, now)
	if tr.done then
		return "run"
	end
	if now and tr.startedAt and now - tr.startedAt >= Tutorial.MAX_HOLD then
		return "run"
	end
	round = tonumber(round) or 1
	if tr.debut and tr.rounds and round >= tr.rounds then
		return "run"
	end
	local last = Tutorial.IndexOf(tr, Tutorial.LAST_ROUND1) or 0
	if round <= 1 then
		return tr.step > last and "break" or "hold"
	end
	return stepsOf(tr)[tr.step].final and "run" or "hold"
end

-- may the opponent be knocked down / stopped yet? (only once the last step is up)
function Tutorial.CanDrop(tr)
	return tr.done or stepsOf(tr)[tr.step].final == true
end

-- may the PLAYER be knocked down / stopped? Never in the practice round; in the debut only in the final round
function Tutorial.PlayerCanDrop(tr, round)
	if not tr.debut then
		return false
	end
	return tr.rounds ~= nil and (tonumber(round) or 1) >= tr.rounds
end

function Tutorial.AiWork(tr)
	if tr.done then
		return tr.debut and Tutorial.Debut.AI_WORK_DONE or 0.6
	end
	return stepsOf(tr)[tr.step].aiWork or 0.5
end

-- the opponent's defence (FightAI: engine.aiDefense)
function Tutorial.AiDefense(tr)
	if tr.debut then
		return (tr.done or stepsOf(tr)[tr.step].final) and Tutorial.Debut.AI_DEFENSE_DONE or Tutorial.Debut.AI_DEFENSE
	end
	return Tutorial.AI_DEFENSE
end

-- the damage rules (O = the man being hit is the player?)
function Tutorial.DamageMul(tr, targetIsPlayer)
	if tr.debut then
		return targetIsPlayer and Tutorial.Debut.DAMAGE_TAKEN or Tutorial.Debut.DAMAGE_DEALT
	end
	return targetIsPlayer and Tutorial.DAMAGE_TAKEN or Tutorial.DAMAGE_DEALT
end
function Tutorial.KoMul(tr)
	return tr.debut and Tutorial.Debut.KO_MUL or Tutorial.KO_MUL
end

-- the message the client's prompt card draws (FightRemote t = "tutorial")
function Tutorial.View(tr)
	local steps = stepsOf(tr)
	return {
		t = "tutorial", step = tr.step, total = #steps, id = steps[tr.step].id, goals = table.clone(tr.goals), done = tr.done, timedOut = tr.timedOut,
		debut = tr.debut or nil, special = tr.special, specialName = tr.specialName,
	}
end

-- the step a view describes (the client: the same step list the server built)
function Tutorial.StepOf(view)
	if type(view) ~= "table" then
		return Tutorial.STEPS[1]
	end
	local steps = view.debut and Tutorial.Steps({ debut = true, special = view.special, specialName = view.specialName }) or Tutorial.STEPS
	return steps[tonumber(view.step) or 1] or Tutorial.ById[view.id] or steps[1]
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
