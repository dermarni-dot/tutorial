--!nocheck
-- tools/sim/test_fightfixes.luau: the combo / dodge / debut fixes, pinned (FightEngine on stub rigs through
-- tools/sim/fightsim; the client modules on guisim).
--   * a dodge that WON is over: the next punch is no "CAUGHT MID-DODGE" hit (no catch bonus, no Punish, no
--     announce) - the player's dodges and the AI's alike
--   * the guided debut: the doctor and the "corner retires him" path never stop it before the final round; in the
--     final round both men can be dropped (the opponent's protection ends with the player's); the last rest
--     heals the player to his cap
--   * the debut offer: a refused StartDebut keeps the offer up, an accepted one closes it; a called-off debut
--     clears ClientMain's once-a-session flag and the Fight Board offers it while summary.debut.offer is true;
--     the debut's step card goes on "final"
--   * Shift held to sprint and a Q / E pressed later is a slip, not a weave (a modifier with its own action is
--     a chord only within FightClient's CHORD_FRESH of its press)
--   lune run tools/sim/test_fightfixes.luau
local process = require("@lune/process")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local FS = require("./fightsim")
local GS = require("./guisim")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local S = FS.new()
local Config, Tutorial = S.Config, S.H.require("Tutorial")
local Random = S.H.globals.Random

local function data(style)
	local d = S.Boxer({ style = style or "BoxerPuncher", level = 60 }, Random.new(5))
	for _, k in ipairs(Config.StatKeys) do
		d.stats[k] = 60
	end
	return d
end
local function fight()
	S.setClock(500)
	local f = S.NewFight(data(), data("Swarmer"), 3, 3)
	f.round, f.live, f.roundEnd = 1, true, S.now() + 60
	f.Distance = function()
		return 3.3
	end
	return f
end
local function hitsOf(f)
	local out = {}
	local orig = f.Send
	f.Send = function(self, m)
		if m.t == "hit" or m.t == "defense" then
			table.insert(out, m)
		end
		return orig(self, m)
	end
	return out
end

------------------------------------------------------------------------
-- a dodge that won is over
------------------------------------------------------------------------
for _, who in ipairs({ "player", "ai" }) do
	local f = fight()
	local A, D = f.P, f.O -- (D dodges A's hook)
	if who == "ai" then
		A, D = f.O, f.P
	end
	local ev = hitsOf(f)
	f.rng = Random.new(4)
	f:Dodge(D, "weave", -1)
	f:Punch(A, "leadhook", false)
	S.advance(Config.Punches.leadhook.windup + 0.01)
	local def = ev[#ev]
	check(who .. ": the weave beats the hook", def and def.t == "defense" and def.dodge == "weave", def and def.t)
	check(who .. ": a dodge that won is over", D.dodgeKind == nil and D.dodgeEnd <= S.now() + 1e-9)
	-- the next punch, after the weave's window but inside its old recovery: an ordinary hit, not a catch
	S.advance(math.max(0, A.busyUntil - S.now()) + 0.01)
	f:Update(0)
	D.counterUntil = 0
	f.Distance = function()
		return 2.8 -- (in the uppercut's reach)
	end
	local LOW = { NextNumber = function(_, a, b)
		return a and (a + (b - a) * 0.5) or 0.001
	end, NextInteger = function(_, a)
		return a
	end }
	f.rng = LOW
	local d0 = D.damageTaken
	f:Punch(A, "uppercut", false)
	S.advance(Config.Punches.uppercut.windup + 0.01)
	local h = ev[#ev]
	check(who .. ": no CAUGHT MID-DODGE after a won dodge", h and h.t == "hit" and h.caught == nil, h and tostring(h.caught))
	-- the same uppercut on a fresh man (no dodge at all) does the same damage: no Punish x1.35
	local won = D.damageTaken - d0
	local g = fight()
	local A2, D2 = g.P, g.O
	if who == "ai" then
		A2, D2 = g.O, g.P
	end
	g.rng = Random.new(4)
	g:Dodge(D2, "weave", -1)
	g:Punch(A2, "leadhook", false)
	S.advance(Config.Punches.leadhook.windup + 0.01)
	S.advance(math.max(0, A2.busyUntil - S.now()) + 0.01)
	g:Update(0)
	D2.dodgeKind, D2.dodgeEnd = nil, 0 -- (a man not dodging at all)
	D2.counterUntil = 0
	g.Distance = function()
		return 2.8
	end
	g.rng = LOW
	local e0 = D2.damageTaken
	g:Punch(A2, "uppercut", false)
	S.advance(Config.Punches.uppercut.windup + 0.01)
	local plain = D2.damageTaken - e0
	check(who .. ": no Punish multiplier after a won dodge", won > 0 and math.abs(won - plain) < plain * 0.05, won .. " vs " .. plain)
end
-- a dodge that LOST still catches him (the old rule kept)
do
	local f = fight()
	local ev = hitsOf(f)
	f.rng = Random.new(4)
	f:Dodge(f.O, "duck")
	S.advance(f.O.dodgeUntil - S.now() + 0.01)
	f:Punch(f.P, "cross", false)
	S.advance(0.01)
	f.O.dodgeEnd = S.now() + 1
	S.advance(Config.Punches.cross.windup)
	local h = ev[#ev]
	check("a punch after the window still catches him", h and h.t == "hit" and h.caught == true)
end

------------------------------------------------------------------------
-- the guided debut
------------------------------------------------------------------------
local function debut()
	local f = fight()
	f.rounds = 3
	f.debut = true
	f.tutorial = Tutorial.NewTracker({ debut = true, rounds = 3 })
	f.P.isPlayer = true
	return f
end
do
	local f = debut()
	f.round = 2 -- (the rest before the final round)
	f.P.dmg.cut = 1.1
	f:DoctorCheck()
	check("debut: the doctor never stops the player before the final round", not f.finished)
	f.P.conc, f.P.kdTotal = 0.95, 2
	f:DoctorCheck()
	check("debut: nor for a concussion", not f.finished)
	f.round = 3
	f:DoctorCheck()
	check("debut: in the final round he can be stopped", f.finished == true and f.winner == f.O)
end
do
	local f = debut()
	f.round = 1
	f.rng = { NextNumber = function()
		return 0
	end, NextInteger = function(_, a)
		return a
	end }
	f.O.healthCap, f.O.conc = 30, 0.9
	f.roundCards = { { { 10, 8 }, { 10, 8 }, { 10, 8 } }, { { 10, 8 }, { 10, 8 }, { 10, 8 } }, { { 10, 8 }, { 10, 8 }, { 10, 8 } } }
	f:DoctorCheck()
	check("debut: his corner never retires him before the final round", not f.finished)
	local g = fight()
	g.rng = f.rng
	g.O.healthCap, g.O.conc = 30, 0.9
	g.roundCards = f.roundCards
	g:DoctorCheck()
	check("a career bout: the corner may retire a beaten man (unchanged)", g.finished == true and g.method == "RTD")
end
do
	local f = debut()
	f.round = 2
	check("debut: the opponent is protected before the last step", f:Protected(f.O) == true)
	f.round = 3
	check("debut: in the final round he can be dropped too (the guide ran out)", f:Protected(f.O) == false and f:Protected(f.P) == false)
	local p = fight()
	p.tutorial = Tutorial.NewTracker()
	p.rounds = 2
	p.round = 2
	check("practice round: unchanged (the opponent only once the last step is up)", p:Protected(p.O) == true)
	-- the last rest heals the player to his cap
	f.round = 2
	f.P.healthCap, f.P.health, f.P.conc = 85, 30, 0.5
	f:DebutFinalRest()
	check("debut: the final rest heals him to his cap", f.P.health == 85 and f.P.conc <= 0.2 + 1e-9)
	local fe = fs.readFile(S.H.src .. "/server/FightEngine.lua")
	check("debut: Run calls the final rest", fe:find("self:DebutFinalRest()", 1, true) ~= nil)
end

------------------------------------------------------------------------
-- the debut offer (the real client module on guisim)
------------------------------------------------------------------------
local function findIn(node, name)
	for _, d in ipairs(node:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end
do
	local G = GS.new("tablet")
	local P = { created = true, pastCareers = {}, debut = { offer = true, rounds = 3, venue = "Community Center" }, settings = {} }
	local answer = { ok = false, err = "Your character isn't ready" }
	local asked = 0
	G.onInvokeServer = function(_, action)
		if action == "GetProfile" then
			return P
		elseif action == "StartDebut" then
			asked += 1
			return answer
		end
		return { ok = true }
	end
	local TC = G.require("Client/Tutorial")
	TC.Start()
	local pg = G.playerGui
	TC.OfferDebut(P.debut)
	G.settle(0.2)
	G.signal(findIn(pg, "StartDebut"), "MouseButton1Click"):Fire()
	G.settle(0.3)
	check("debut offer: a refused start keeps the offer up", asked == 1 and findIn(pg, "DebutOffer") ~= nil and TC.Busy())
	answer = { ok = true }
	G.signal(findIn(pg, "StartDebut"), "MouseButton1Click"):Fire()
	G.settle(0.3)
	check("debut offer: an accepted start closes it", asked == 2 and findIn(pg, "DebutOffer") == nil)
	-- the step card goes on "final" (the debut ends like a career bout)
	G.loadScript("client/FightClient.client.lua")
	G.settle(0.3)
	local fr = G.remotes.FightEvent
	fr:Fire({ t = "start", rounds = 3, tape = { you = { name = "Jo Novak", record = {} }, opp = { name = "Sam Doe", record = {} } }, kind = "Amateur Bout", venue = "CommunityCenter",
		venueName = "Community Center", moves = {}, tutorial = { total = 11, debut = true } })
	fr:Fire(Tutorial.View(Tutorial.NewTracker({ debut = true, rounds = 3 })))
	G.settle(0.3)
	check("debut: the step card is up", findIn(pg, "Prompt") ~= nil)
	fr:Fire({ t = "final", result = { outcome = "win", method = "UD" }, oppName = "Sam Doe" })
	G.settle(0.3)
	check("debut: the step card goes on final (the cleanup runs)", findIn(pg, "Prompt") == nil and not TC.Busy())
end
-- the controls on a keyboard: Shift held to sprint, a Q later is a slip; Shift + Q together is the weave
do
	local G = GS.new("desktop")
	local sent = {}
	G.onInvokeServer = function(_, action)
		if action == "GetProfile" then
			return { created = true, pastCareers = {}, settings = {} }
		end
		return { ok = true }
	end
	G.onFireServer = function(_, msg)
		table.insert(sent, msg)
	end
	local uis = G.host.Service("UserInputService")
	local props = rawget(uis, "_props")
	rawset(props, "InputBegan", G.signal(uis, "InputBegan"))
	rawset(props, "InputEnded", G.signal(uis, "InputEnded"))
	G.loadScript("client/FightClient.client.lua")
	G.settle(0.3)
	local fr = G.remotes.FightEvent
	fr:Fire({ t = "start", rounds = 3, tape = { you = { name = "Jo Novak", record = {} }, opp = { name = "Sam Doe", record = {} } }, kind = "Pro Fight", venue = "Arena",
		venueName = "Arena", moves = {} })
	fr:Fire({ t = "round", n = 1, total = 3 })
	fr:Fire({ t = "countdown", n = 0, round = 1 })
	G.settle(0.2)
	local KC, UT = roblox.Enum.KeyCode, roblox.Enum.UserInputType
	local function key(k, down)
		G.signal(uis, down and "InputBegan" or "InputEnded"):Fire({ UserInputType = UT.Keyboard, KeyCode = KC[k] }, false)
	end
	local function lastOf()
		for i = #sent, 1, -1 do
			if type(sent[i]) == "table" and (sent[i].t == "slip" or sent[i].t == "dodge") then
				return sent[i]
			end
		end
		return nil
	end
	key("LeftShift", true)
	G.settle(0.6) -- (sprinting a while)
	table.clear(sent)
	key("Q", true)
	key("Q", false)
	G.settle(0.05)
	local m = lastOf()
	check("controls: Shift held to sprint + Q later = a slip, not a weave", m and m.t == "slip", m and (m.t .. " " .. tostring(m.kind)) or #sent)
	key("LeftShift", false)
	G.settle(0.05)
	table.clear(sent)
	key("LeftShift", true)
	key("Q", true)
	key("Q", false)
	key("LeftShift", false)
	G.settle(0.05)
	m = lastOf()
	check("controls: Shift + Q together = the weave", m and m.t == "dodge" and m.kind == "weave", m and (m.t .. " " .. tostring(m.kind)) or #sent)
end
do
	local cm = fs.readFile(S.H.src .. "/client/ClientMain.client.lua")
	check("ClientMain: a debutEnd clears the once-a-session offer flag", cm:find('msg.t == "debutEnd" then\n\t\tdebutOffered = false', 1, true) ~= nil)
	local hub = fs.readFile(S.H.src .. "/client/modules/Hub.lua")
	check("Fight Board: the debut while summary.debut.offer is true", hub:find("P.debut.offer == true and State.open.Debut", 1, true) ~= nil)
end

print(string.format("test_fightfixes: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
