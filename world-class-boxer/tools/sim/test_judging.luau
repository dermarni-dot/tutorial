--!nocheck
-- tools/sim/test_judging.luau: the three judges (src/server/Judging.lua) and FightEngine's use of them, under lune.
--   * the 10-point must system: 10-9 for the better work, 10-8 a knockdown, 10-7 two, 10-9 when the man who went
--     down won the rest of the round clearly, 10-10 only for an even round, equal knockdowns cancel, a foul's point
--     comes off after (9-9, 10-8 without a knockdown), never under 6
--   * the judges' tendencies: the aggression judge gives a busy, pressing round the clean judge does not; the
--     defence judge rewards the tighter defence and the centre of the ring; a clear round is 10-9 on all three cards
--   * the decision: unanimous, split, majority, draw (and the announcer's score strings winner-first)
--   * the announcer: a decision reads every card and ends on the winner; a stoppage gives the time and the round;
--     a title says "and NEW"; the hand goes up on the last line
--   * FightEngine: ScoreRound through Judging (cards and roundCards in the old shape, the scorecard message per
--     corner, the fight totals), the fallback MustScore, a whole fight on fightsim deciding by Judging.Decide
--   lune run tools/sim/test_judging.luau
local Host = require("./host")
local FS = require("./fightsim")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local H = Host.new()
local function serverModule(name)
	local folder = rawget(H, "_serverFolder")
	if not folder then
		folder = Host.NewNode("BoxerModules", "Folder", H.Service("ServerScriptService"))
		rawset(H, "_serverFolder", folder)
		local fs = require("@lune/fs")
		for _, f in ipairs(fs.readDir(H.src .. "/server")) do
			local base = f:match("^(.-)%.lua$")
			if base and not f:find("%.server%.") then
				local n = Host.NewNode(base, "ModuleScript", folder)
				rawset(n, "_file", H.src .. "/server/" .. f)
			end
		end
	end
	return H.requireNode(folder._kids[name])
end
local Judging = serverModule("Judging")

------------------------------------------------------------------------
-- the 10-point must system
------------------------------------------------------------------------
local function ms(...)
	local a, b = Judging.MustScore(...)
	return a .. "-" .. b
end
check("10-9 for the better work", ms(2, 0, 0) == "10-9")
check("9-10 the other way", ms(-2, 0, 0) == "9-10")
check("10-10 an even round", ms(0.1, 0, 0) == "10-10")
check("10-8 a knockdown", ms(0, 1, 0) == "10-8")
check("8-10 a knockdown against", ms(1, 0, 1) == "8-10")
check("10-7 two knockdowns", ms(0, 2, 0) == "10-7")
check("10-9 when the man who went down won the rest clearly", ms(-7, 1, 0) == "10-9")
check("equal knockdowns cancel and the work decides", ms(1, 1, 1) == "10-9")
check("a foul costs the point after the round is scored", ms(2, 0, 0, 1, 0) == "9-9")
check("a foul on the loser: 10-8 without a knockdown", ms(2, 0, 0, 0, 1) == "10-8")
check("never under 6", ms(0, 4, 0, 0, 2) == "10-6")

------------------------------------------------------------------------
-- the judges' tendencies
------------------------------------------------------------------------
local function side(o)
	local S = Judging.NewSide()
	for k, v in pairs(o or {}) do
		if type(v) == "table" then
			for t, n in pairs(v) do
				S[k][t] = n
			end
		else
			S[k] = v
		end
	end
	return S
end
local function cardsOf(r)
	local out = {}
	for j, c in ipairs(r.cards) do
		out[j] = c[1] .. "-" .. c[2]
	end
	return table.concat(out, " ")
end

-- a clear round: red lands twice as much, cleaner and busier
local clear = Judging.Score({ red = side({ landed = 24, thrown = 60, power = 14, body = 6, byType = { jab = 10, cross = 8, leadhook = 4, uppercut = 2 }, liveT = 180, centreT = 120, pressT = 70, blocked = 8, evaded = 5 }),
	blue = side({ landed = 11, thrown = 40, power = 5, body = 2, byType = { jab = 6, cross = 3, leadhook = 2 }, liveT = 180, centreT = 50, pressT = 20, blocked = 4, evaded = 2 }), seconds = 180 })
check("a clear round is 10-9 on all three cards", cardsOf(clear) == "10-9 10-9 10-9", cardsOf(clear))
check("the reasons name the better work", type(clear.judges[2].reason) == "string" and #clear.judges[2].reason > 3, clear.judges[2].reason)

-- the busy presser against the cleaner counter-puncher: judge 1 (aggression) and judge 2 (clean) disagree
local split = Judging.Score({
	red = side({ landed = 24, thrown = 95, power = 14, byType = { jab = 10, cross = 7, leadhook = 5, rearhook = 2 }, liveT = 180, centreT = 150, pressT = 140, blocked = 3, evaded = 1, mom = 0.6 }),
	blue = side({ landed = 20, thrown = 46, power = 12, counters = 7, heavy = 2, byType = { jab = 6, cross = 8, uppercut = 4, overhand = 2 }, liveT = 180, centreT = 25, pressT = 5, blocked = 22, evaded = 12, parried = 4, missed = 60 }),
	seconds = 180 })
check("the aggression judge gives the presser the round", split.cards[1][1] == 10 and split.cards[1][2] == 9, cardsOf(split))
check("the clean-punching judge gives it to the counter-puncher", split.cards[2][2] == 10 and split.cards[2][1] == 9, cardsOf(split))
check("the categories are reported", split.red.aggr > split.blue.aggr and split.blue.clean > split.red.clean and split.blue.def > split.red.def)

-- the same work with a knockdown for blue: all three 8-10 (the presser's edge is no dominance)
local kd = Judging.Score({ red = split.red and side({ landed = 20, thrown = 95, power = 12, liveT = 180, centreT = 150, pressT = 140 }), blue = side({ landed = 20, thrown = 46, power = 12, kd = 1, liveT = 180 }), seconds = 180 })
check("a knockdown wins the round on every card", cardsOf(kd) == "8-10 8-10 8-10", cardsOf(kd))

-- the flat tallies alone (a sim without the observer) still score a sensible round
local flat = Judging.Score({ red = side({ landed = 18, thrown = 50, power = 10, body = 4 }), blue = side({ landed = 9, thrown = 44, power = 4 }), seconds = 180 })
check("the flat tallies score the round", cardsOf(flat) == "10-9 10-9 10-9", cardsOf(flat))
check("an empty round is even", cardsOf(Judging.Score({ red = side(), blue = side() })) == "10-10 10-10 10-10")

-- the judges' noise: with an rng a close round can split the card, a clear one never does
local Random = H.globals.Random
local splits, clears = 0, 0
for seed = 1, 60 do
	local rng = Random.new(seed)
	local close = Judging.Score({ red = side({ landed = 15, thrown = 50, power = 8, liveT = 180, centreT = 90, pressT = 50 }), blue = side({ landed = 15, thrown = 50, power = 7, liveT = 180, centreT = 90, pressT = 50 }), seconds = 180 }, rng)
	local c = cardsOf(close)
	if c:find("9%-10") and c:find("10%-9") then
		splits += 1
	end
	local sure = Judging.Score({ red = side({ landed = 30, thrown = 70, power = 18, body = 6, liveT = 180, centreT = 120, pressT = 80 }), blue = side({ landed = 8, thrown = 40, power = 3, liveT = 180, centreT = 40 }), seconds = 180 }, Random.new(seed))
	if cardsOf(sure) == "10-9 10-9 10-9" then
		clears += 1
	end
end
check("a close round splits the card now and then", splits >= 3, splits)
check("a clear round never splits", clears == 60, clears)

------------------------------------------------------------------------
-- the decision
------------------------------------------------------------------------
local function dec(cards)
	local d = Judging.Decide(cards)
	return d.outcome .. "/" .. d.method
end
check("unanimous decision", dec({ { 116, 112 }, { 115, 113 }, { 117, 111 } }) == "win/UD")
check("unanimous loss", dec({ { 112, 116 }, { 113, 115 }, { 111, 117 } }) == "loss/UD")
check("split decision", dec({ { 115, 113 }, { 113, 115 }, { 115, 113 } }) == "win/SD")
check("majority decision", dec({ { 115, 113 }, { 114, 114 }, { 115, 113 } }) == "win/MD")
check("split draw", dec({ { 115, 113 }, { 113, 115 }, { 114, 114 } }) == "draw/Draw")
check("majority draw", Judging.Decide({ { 115, 113 }, { 114, 114 }, { 114, 114 } }).drawKind == "majority")
check("the scores read winner first", table.concat(Judging.Decide({ { 112, 116 }, { 113, 115 }, { 115, 113 } }).scores, " ") == "116-112 115-113 113-115")
check("the decision's text", Judging.Decide({ { 116, 112 }, { 115, 113 }, { 117, 111 } }).text == "unanimous decision")

------------------------------------------------------------------------
-- the announcer
------------------------------------------------------------------------
local names = { "Marcus Reed", "Dmitri Volkov" }
local ud = Judging.Announce({ outcome = "win", method = "UD", round = 10, cards = { { 97, 93 }, { 96, 94 }, { 98, 92 } }, scores = { "97-93", "96-94", "98-92" } }, names, { rounds = 10 })
local function texts(a)
	local t = {}
	for _, l in ipairs(a.lines) do
		table.insert(t, l.text)
	end
	return table.concat(t, " | ")
end
check("a decision reads the three cards", select(2, texts(ud):gsub("score", "")) == 4, texts(ud))
check("a decision ends on the winner by unanimous decision", texts(ud):find("UNANIMOUS DECISION") and texts(ud):find("MARCUS REED", 1, true) and ud.lines[#ud.lines].kind == "winner", texts(ud))
check("the hand goes up on the winner's line", ud.raiseAt == ud.lines[#ud.lines].at and ud.dur > ud.raiseAt)
check("the lines are in time order", (function()
	for i = 2, #ud.lines do
		if ud.lines[i].at <= ud.lines[i - 1].at then
			return false
		end
	end
	return true
end)())
local sd = Judging.Announce({ outcome = "loss", method = "SD", round = 12, cards = { { 115, 113 }, { 113, 115 }, { 113, 115 } } }, names, { rounds = 12 })
check("a split decision reads the dissenting card first, that man's total first", sd.lines[3].text:find("Marcus Reed", 1, true) ~= nil and sd.lines[3].text:find("115%-113") ~= nil, sd.lines[3].text)
check("...and names the other man the winner", texts(sd):find("SPLIT DECISION") and texts(sd):find("DMITRI VOLKOV", 1, true), texts(sd))
local ko = Judging.Announce({ outcome = "win", method = "KO", round = 3 }, names, { rounds = 10, time = 92 })
check("a knockout gives the time and the round", texts(ko):find("1:32 of round 3", 1, true) and texts(ko):find("KNOCKOUT") and ko.stoppage, texts(ko))
check("a stoppage reads no cards", not texts(ko):find("scores"))
local title = Judging.Announce({ outcome = "win", method = "MD", round = 12, cards = { { 115, 113 }, { 114, 114 }, { 116, 112 } } }, names, { rounds = 12, title = { title = "WBC World Champion" } })
check("a title fight says and NEW", texts(title):find("and NEW WBC WORLD CHAMPION", 1, true) ~= nil, texts(title))
local draw = Judging.Announce({ outcome = "draw", method = "Draw", drawKind = "majority", cards = { { 114, 114 }, { 114, 114 }, { 115, 113 } } }, names, { rounds = 12 })
check("a draw is declared", texts(draw):find("MAJORITY DRAW") and draw.winner == nil and draw.lines[#draw.lines].kind == "draw", texts(draw))

------------------------------------------------------------------------
-- the report
------------------------------------------------------------------------
local rep = Judging.Report({ clear, split }, { { 20, 18 }, { 19, 19 }, { 20, 18 } }, { red = clear.stats and clear.stats.red or side({ landed = 44 }), blue = side({ landed = 31 }) }, true)
check("the report flips for the blue corner", rep.cards[1][1] == 18 and rep.cards[1][2] == 20 and rep.rounds[1].cards[1][1] == 9 and rep.rounds[1].cards[1][2] == 10, rep.cards[1][1])
check("the report carries the judges' names and the totals", rep.judgeNames[3].lean == "Defence and ring control" and rep.totals.opp.landed == 44 and rep.totals.you.landed == 31)

------------------------------------------------------------------------
-- FightEngine through Judging
------------------------------------------------------------------------
local S = FS.new()
local FightEngine = S.FightEngine or S.H.require("FightEngine")
check("FightEngine.MustScore routes through Judging (fouls)", select(2, FightEngine.MustScore(2, 0, 0, 1, 0)) == 9 and FightEngine.MustScore(2, 0, 0, 1, 0) == 9)
local Random2 = S.H.globals.Random
local function data(style, level)
	return S.Boxer({ style = style or "BoxerPuncher", level = level or 60 }, Random2.new(5))
end
S.setClock(500)
local f = S.NewFight(data(), data("Swarmer"), 3, 3)
f.round, f.live, f.roundEnd = 1, true, S.now() + 60
-- the observer through the real Send: a hit by type, a block, a slip, a miss, and the centre of the ring
f.Send, f.SendEach = nil, nil -- (the sim's per-fight stubs off: the module's Send / SendEach run on the engine's own)
local sent = {}
local baseSendTo = f.SendTo
f.SendTo = function(_, _, m)
	table.insert(sent, m)
end
f.Viewers = function()
	return { f.P }
end
f.P.tally.landed, f.P.tally.thrown, f.P.tally.power = 12, 30, 6
f.O.tally.landed, f.O.tally.thrown, f.O.tally.power = 5, 28, 2
f:Send({ t = "hit", who = "you", punch = "cross", dmg = 4.2, heavy = true })
f:Send({ t = "hit", who = "you", punch = "jab", dmg = 1.1 })
f:Send({ t = "hit", who = "opp", punch = "uppercut", dmg = 3 })
f:Send({ t = "blocked", who = "you", punch = "cross" })
f:Send({ t = "defense", who = "you", move = "SLIPPED", dodge = "slip" })
f:Send({ t = "defense", who = "opp", move = "PARRIED" })
f:Send({ t = "miss", who = "opp", why = "range" })
-- the ring position: 5 Hz samples while live
for i = 1, 10 do
	S.setClock(500 + i * 0.2)
	f:SyncAttrs(f.P)
	f:SyncAttrs(f.O)
end
local stats = f:RoundStats()
check("the observer counts the punches by type", stats.red.byType.cross == 1 and stats.red.byType.jab == 1 and stats.blue.byType.uppercut == 1, stats.red.byType.cross)
check("the observer counts the defence", stats.red.blocked == 1 and stats.red.evaded >= 1 and stats.blue.parried == 1 and stats.red.missed == 1, stats.red.blocked)
check("the observer counts the heavy ones and the damage", stats.red.heavy == 1 and stats.red.damage > 5)
check("the ring position is sampled while live", stats.red.liveT > 1.5 and stats.red.centreT > 1.5, stats.red.liveT)
check("the tallies are the round's", stats.red.landed == 12 and stats.blue.thrown == 28)
sent = {}
local rc = f:ScoreRound()
check("ScoreRound keeps the old shape", #rc == 3 and #f.roundCards == 1 and f.cards[1][1] + f.cards[1][2] > 0 and rc[1][1] == f.cards[1][1])
check("the round goes to the busier, cleaner man", rc[1][1] == 10 and rc[1][2] == 9 and rc[2][1] == 10 and rc[3][1] == 10, rc[1][1] .. "-" .. rc[1][2])
local sc
for _, m in ipairs(sent) do
	if m.t == "scorecard" then
		sc = m
	end
end
check("the scorecard message goes to the corner", sc ~= nil and sc.n == 1 and #sc.round == 3 and sc.stats.you.landed == 12 and sc.stats.opp.landed == 5 and sc.totals.you.landed == 12 and sc.judges[1].reason ~= nil, sc and sc.n)
check("the next round starts clean", f.P.judge == nil and f.P.judgeSnap ~= nil)
f.SendTo = baseSendTo
-- the live card still works on RoundPoints
local live = f:LiveCard()
check("the live card still reads", type(live.d) == "number" and #live.cards == 3)

-- a whole fight on the sim decides through the judges (fightsim's own decision agrees with Judging.Decide)
local bout = S.Fight({ red = { style = "BoxerPuncher", level = 70 }, blue = { style = "OutBoxer", level = 60 }, rounds = 4, seed = 11 })
local fight = bout.fight
check("a whole fight keeps three cards", #fight.cards == 3 and #fight.roundCards == (fight.finished and fight.endRound - 1 or 4) or #fight.roundCards <= 4, #fight.roundCards)
if not fight.finished then
	local d = Judging.Decide(fight.cards)
	check("the decision is one of the four", d.method == "UD" or d.method == "SD" or d.method == "MD" or d.method == "Draw", d.method)
	check("the report covers every round", fight.judgeRounds and #fight.judgeRounds == 4 and fight.judgeTotals.red.landed == fight.P.totals.landed, fight.judgeTotals and fight.judgeTotals.red.landed)
	check("the sum of the round cards is the total", (function()
		local s = 0
		for _, r in ipairs(fight.roundCards) do
			s += r[2][1]
		end
		return s == fight.cards[2][1]
	end)())
else
	check("a stoppage keeps its path", fight.method == "KO" or fight.method == "TKO" or fight.method == "RTD", fight.method)
end

print(string.format("test_judging: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_judging failed")
end
