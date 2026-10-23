-- Judging: the three ringside judges (pure: no engine state, no Instances; tools/sim/test_judging.luau pins it).
--
-- Every round each judge weighs the same five things a real judge is told to, with his own leanings:
--   * clean punching: punches landed, each weighted by its type (a jab is worth less than an uppercut), body shots,
--     counters and the heavy ones (the damage done)
--   * ring generalship: time holding the centre of the ring, time walking the other man down (FightEngine's
--     position tracking: typeStats.pressT / the judge observer's centre time)
--   * effective aggression: the work rate that LANDS (thrown punches count for a little; the aggression judge
--     likes volume and pressure more than the others)
--   * defence: punches blocked, slipped, rolled under, parried and made to miss
--   * knockdowns: the 10-point must system (Judging.MustScore): the round's winner gets 10 and the loser 9; a
--     knockdown wins the round for the man who scored it and costs the man who went down one more point (10-8,
--     two knockdowns 10-7) unless he clearly won the rest of the round (10-9); 10-10 only for a truly even round
--     with no knockdown (judges are told to pick a winner, so it is rare); a foul's point deduction comes off after
--     (so 9-9 and 10-8 without a knockdown are possible, as on a real card)
-- Judge 1 favours aggression, judge 2 clean punching, judge 3 defence and ring control. Their totals decide a
-- fight that goes the distance (Judging.Decide): unanimous, split or majority decision, or a draw. A stoppage
-- (KO, TKO, RTD, the doctor) never comes here.
--
-- Judging.Score(roundStats [, rng]) -> round: roundStats = { red = S, blue = S, seconds = n } with S as
-- Judging.NewSide() (every field optional, missing = 0):
--   landed, thrown, power (non-jab landed), body, jabs, counters, heavy, byType = { jab = n, cross = n, ... } (landed
--   per type), blocked / evaded / parried (HIS defence: the other man's punches he stopped), missed (the other man's
--   misses), kd (knockdowns he SCORED), clinches, inside, fouls (points to deduct from him), pressT / centreT /
--   liveT (seconds pressing forward / in the centre / live), mom (the round's momentum his way, -1..1)
-- The rng (Random or a table with NextNumber) is each judge's eye: a little noise so close rounds can split the
-- card; nil = deterministic.
local Judging = {}

Judging.JUDGES = {
	{ id = "aggression", name = "Judge 1", lean = "Effective aggression", noise = 1.0,
		w = { clean = 0.9, ring = 0.8, aggr = 2.0, def = 0.3, press = 1.8 } },
	{ id = "clean", name = "Judge 2", lean = "Clean punching", noise = 0.8,
		w = { clean = 1.35, ring = 0.6, aggr = 0.6, def = 0.7, press = 0.6 } },
	{ id = "defence", name = "Judge 3", lean = "Defence and ring control", noise = 1.2,
		w = { clean = 0.95, ring = 1.5, aggr = 0.6, def = 1.3, press = 0.8 } },
}

-- what a landed punch of each type is worth to the judges (a jab scores, but a clean uppercut scores more)
Judging.PUNCH_W = { jab = 0.6, cross = 1.0, leadhook = 1.05, rearhook = 1.1, uppercut = 1.15, overhand = 1.2 }
Judging.POWER_TYPES = { cross = true, leadhook = true, rearhook = true, uppercut = true, overhand = true }

Judging.EVEN_ROUND = 0.35 -- |diff| under this (in judge points) is an even round
Judging.DOMINANT_ROUND = 6.0 -- a differential this big (clear domination) outweighs one knockdown point

local function num(v)
	return tonumber(v) or 0
end

function Judging.NewSide()
	return {
		landed = 0, thrown = 0, power = 0, body = 0, jabs = 0, counters = 0, heavy = 0,
		byType = { jab = 0, cross = 0, leadhook = 0, rearhook = 0, uppercut = 0, overhand = 0 },
		thrownByType = { jab = 0, cross = 0, leadhook = 0, rearhook = 0, uppercut = 0, overhand = 0 },
		blocked = 0, evaded = 0, parried = 0, missed = 0, kd = 0, clinches = 0, inside = 0, fouls = 0,
		pressT = 0, centreT = 0, liveT = 0, mom = 0, damage = 0,
	}
end

-- add side B's counters into A (the fight totals from the rounds)
function Judging.AddSide(A, B)
	for k, v in pairs(B) do
		if type(v) == "number" then
			A[k] = num(A[k]) + v
		elseif type(v) == "table" then
			A[k] = type(A[k]) == "table" and A[k] or {}
			for t, n in pairs(v) do
				A[k][t] = num(A[k][t]) + num(n)
			end
		end
	end
	return A
end

------------------------------------------------------------------------
-- the 10-point must system
------------------------------------------------------------------------
-- diff = the judge's differential (positive: the first fighter did the better work), kdA / kdB = knockdowns each
-- fighter SCORED, foulsA / foulsB = point deductions against each (optional).
function Judging.MustScore(diff, kdA, kdB, foulsA, foulsB)
	kdA, kdB = num(kdA), num(kdB)
	diff = num(diff)
	local net = kdA - kdB
	local a, b
	local aWins
	if net ~= 0 then
		aWins = net > 0
	elseif kdA == 0 and math.abs(diff) < Judging.EVEN_ROUND then
		a, b = 10, 10
	else
		aWins = diff >= 0
	end
	if a == nil then
		local down = math.abs(net)
		if down > 0 and (aWins and -diff or diff) >= Judging.DOMINANT_ROUND then
			down -= 1 -- the man who went down clearly won the rest of the round
		end
		local loser = math.max(6, 9 - down)
		if aWins then
			a, b = 10, loser
		else
			a, b = loser, 10
		end
	end
	a = math.max(6, a - num(foulsA))
	b = math.max(6, b - num(foulsB))
	return a, b
end

------------------------------------------------------------------------
-- a round
------------------------------------------------------------------------
-- a side's work in the round by category (the judges' raw material). other = the opponent's side (his misses and
-- his landed punches tell how good the defence was).
function Judging.Categories(S, other, seconds)
	S = S or {}
	other = other or {}
	seconds = math.max(30, num(seconds) > 0 and num(seconds) or 180)
	local landed, thrown = num(S.landed), num(S.thrown)
	-- clean punching: per-type weights when the observer saw the punches, the flat tally otherwise
	local clean = 0
	local byType = type(S.byType) == "table" and S.byType or nil
	local typed = 0
	if byType then
		for t, n in pairs(byType) do
			typed += num(n)
			clean += num(n) * (Judging.PUNCH_W[t] or 1)
		end
	end
	if typed < landed then
		-- (punches the observer did not see by type: the flat weights)
		local rest = landed - typed
		local power = math.max(0, num(S.power) - math.max(0, typed - num(byType and byType.jab)))
		clean += rest * 0.7 + math.min(rest, power) * 0.35
	end
	clean += num(S.body) * 0.3 + num(S.counters) * 0.45 + num(S.heavy) * 0.5 + num(S.inside) * 0.3 + num(S.damage) * 0.04
	-- ring generalship: the centre and walking him down (shares of the live time, so a short round weighs the same)
	local live = math.max(num(S.liveT), num(other.liveT), 1)
	local centre = num(S.centreT) / live
	local press = num(S.pressT) / live
	-- (clean punching is the big category, as on a real card: these are worth a couple of points a round at most)
	local ring = centre * 1.5 + press * 1.0 - num(S.clinches) * 0.2
	-- effective aggression: the work rate (per three minutes) that lands, the pressure and the momentum
	local rate = thrown / seconds * 180
	local acc = thrown > 0 and landed / thrown or 0
	local aggr = rate * 0.012 * (0.5 + acc) + press * 0.8 + math.clamp(num(S.mom), -1, 1) * 0.8
	-- defence: what he kept off himself, and what the other man wasted
	local def = num(S.blocked) * 0.08 + num(S.evaded) * 0.2 + num(S.parried) * 0.2 + num(S.missed) * 0.02
	local oppThrown = num(other.thrown)
	if oppThrown > 0 then
		def += (1 - math.clamp(num(other.landed) / oppThrown, 0, 1)) * 0.8
	end
	return { clean = clean, ring = ring, aggr = aggr, def = def, press = press * 1.5 }
end

-- one judge's differential (A - B) in his points
function Judging.JudgeDiff(judge, catA, catB)
	local d = 0
	for k, w in pairs(judge.w) do
		d += w * (num(catA[k]) - num(catB[k]))
	end
	return d
end

local function noiseOf(rng, k)
	if rng == nil then
		return 0
	end
	local ok, v = pcall(function()
		return rng:NextNumber(-1, 1)
	end)
	return ok and (num(v) * 1.4 * k) or 0
end

local function fmtRound(a, b)
	return string.format("%d-%d", a, b)
end

-- why a judge saw it his way (the scorecard's one-liner)
local function reason(judge, a, b, kdA, kdB, catA, catB)
	if a == b then
		return (kdA == 0 and kdB == 0) and "An even round" or "Even after the knockdowns"
	end
	local redWon = a > b
	local kd = redWon and kdA or kdB
	if kd >= 2 then
		return "Two knockdowns"
	elseif kd == 1 then
		return "The knockdown"
	end
	local A, B = redWon and catA or catB, redWon and catB or catA
	local best, bestK = -1, "clean"
	for k, w in pairs(judge.w) do
		local gain = w * (num(A[k]) - num(B[k]))
		if gain > best then
			best, bestK = gain, k
		end
	end
	local TEXT = { clean = "The cleaner punching", ring = "Controlled the ring", aggr = "The busier man", def = "The tighter defence", press = "Walked him down" }
	return TEXT[bestK] or "The better work"
end

-- the three cards for a round. Returns { cards = {{a,b},{a,b},{a,b}} (red first), judges = { {a, b, diff, reason} },
-- red = categories, blue = categories, kd = {red, blue}, fouls = {red, blue} }
function Judging.Score(stats, rng)
	stats = stats or {}
	local R, B = stats.red or {}, stats.blue or {}
	local catR = Judging.Categories(R, B, stats.seconds)
	local catB = Judging.Categories(B, R, stats.seconds)
	local out = { cards = {}, judges = {}, red = catR, blue = catB, kd = { num(R.kd), num(B.kd) }, fouls = { num(R.fouls), num(B.fouls) } }
	for j, judge in ipairs(Judging.JUDGES) do
		local diff = Judging.JudgeDiff(judge, catR, catB) + noiseOf(rng, judge.noise)
		local a, b = Judging.MustScore(diff, R.kd, B.kd, R.fouls, B.fouls)
		out.cards[j] = { a, b }
		out.judges[j] = { a, b, diff = math.floor(diff * 100) / 100, id = judge.id, reason = reason(judge, a, b, num(R.kd), num(B.kd), catR, catB) }
	end
	return out
end

------------------------------------------------------------------------
-- the decision
------------------------------------------------------------------------
Judging.METHOD_TEXT = { UD = "unanimous decision", SD = "split decision", MD = "majority decision", Draw = "draw",
	KO = "knockout", TKO = "technical knockout", RTD = "retirement", DQ = "disqualification", Tutorial = "decision" }

-- cards = the three totals { {red, blue} x 3 } -> { outcome = "win" | "loss" | "draw" (the red corner's), method =
-- "UD" | "SD" | "MD" | "Draw", scores = { "116-112", ... } (the winner's total first on every card), text = "unanimous
-- decision", drawKind = "majority" | "split" | "unanimous" (a draw only) }
function Judging.Decide(cards)
	cards = type(cards) == "table" and cards or {}
	local pw, ow, even = 0, 0, 0
	for _, c in ipairs(cards) do
		local a, b = num(c[1]), num(c[2])
		if a > b then
			pw += 1
		elseif b > a then
			ow += 1
		else
			even += 1
		end
	end
	local n = #cards
	local res
	if n > 0 and pw == n then
		res = { outcome = "win", method = "UD" }
	elseif n > 0 and ow == n then
		res = { outcome = "loss", method = "UD" }
	elseif pw > n / 2 then
		res = { outcome = "win", method = ow > 0 and "SD" or "MD" }
	elseif ow > n / 2 then
		res = { outcome = "loss", method = pw > 0 and "SD" or "MD" }
	else
		res = { outcome = "draw", method = "Draw", drawKind = (even == n) and "unanimous" or (even >= 1 and "majority" or "split") }
	end
	res.text = Judging.METHOD_TEXT[res.method]
	res.scores = Judging.ScoreStrings(cards, res.outcome)
	return res
end

-- the cards as the announcer reads them: the winner's total first ("116-112"); a draw reads the red corner first
function Judging.ScoreStrings(cards, outcome)
	local list = {}
	for _, c in ipairs(cards or {}) do
		local a, b = num(c[1]), num(c[2])
		if outcome == "loss" then
			a, b = b, a
		elseif outcome ~= "win" and b > a then
			a, b = b, a
		end
		table.insert(list, fmtRound(a, b))
	end
	return list
end

------------------------------------------------------------------------
-- the ring announcer (PostFight's script; the client shows the same lines on the same beats)
------------------------------------------------------------------------
local function mmss(sec)
	sec = math.max(0, math.floor(num(sec)))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- res = the red corner's result ({ outcome, method, round, reason, cards, kdFor/kdAgainst }), names = { red, blue },
-- info = { rounds = n, time = seconds into the end round (a stoppage), title = ceremony spec or nil, champion =
-- "red" | "blue" | nil (the belt holder coming in), kind = the bout's kind }
-- -> { lines = { { at = seconds, text = "...", kind = "intro" | "card" | "method" | "winner" | "draw" } }, dur = seconds,
--      raiseAt = the beat the hand goes up, winner = "red" | "blue" | nil, stoppage = bool }
function Judging.Announce(res, names, info)
	res = res or {}
	names = names or {}
	info = info or {}
	local red, blue = names[1] or names.red or "the red corner", names[2] or names.blue or "the blue corner"
	local winner = res.outcome == "win" and "red" or (res.outcome == "loss" and "blue" or nil)
	local wName = winner == "red" and red or blue
	local lName = winner == "red" and blue or red
	local method = res.method or "UD"
	local stoppage = method == "KO" or method == "TKO" or method == "RTD" or method == "DQ"
	local lines = {}
	local t = 0.4
	local function say(text, kind, dt)
		table.insert(lines, { at = t, text = text, kind = kind or "intro" })
		t += dt or 3.0
	end
	local rounds = num(info.rounds)
	say("Ladies and gentlemen...", "intro", 2.0)
	if stoppage then
		local when = info.time and mmss(info.time) or nil
		local rnd = num(res.round) > 0 and num(res.round) or rounds
		if method == "KO" then
			say(string.format("The referee stops the contest at %s of round %d.", when or "the count", rnd), "method", 3.2)
			say(string.format("The winner, by KNOCKOUT... %s!", string.upper(wName)), "winner", 4.0)
		elseif method == "TKO" then
			local why = (res.reason and res.reason ~= "" and res.reason:find("octor")) and "on the advice of the ringside physician" or "to save his man"
			say(string.format("The referee stops the contest at %s of round %d, %s.", when or "the bell", rnd, why), "method", 3.6)
			say(string.format("The winner, by TECHNICAL KNOCKOUT... %s!", string.upper(wName)), "winner", 4.0)
		elseif method == "RTD" then
			say(string.format("%s retires on his stool at the end of round %d.", lName, rnd), "method", 3.2)
			say(string.format("The winner, by RETIREMENT... %s!", string.upper(wName)), "winner", 4.0)
		else
			say(string.format("The referee disqualifies %s in round %d.", lName, rnd), "method", 3.2)
			say(string.format("The winner, by DISQUALIFICATION... %s!", string.upper(wName)), "winner", 4.0)
		end
	else
		say(string.format("After %d rounds of boxing, we go to the judges' scorecards.", rounds > 0 and rounds or num(res.round)), "intro", 3.0)
		local scores = res.scores or Judging.ScoreStrings(res.cards or {}, res.outcome)
		local cards = res.cards or {}
		if res.outcome == "draw" then
			for j, s in ipairs(scores) do
				local c = cards[j] or { 0, 0 }
				local who = num(c[1]) > num(c[2]) and red or (num(c[2]) > num(c[1]) and blue or nil)
				say(string.format("Judge %d scores the bout %s%s.", j, s, who and (" for " .. who) or ", even"), "card", 2.6)
			end
			say(string.format("This bout is declared a %s DRAW.", string.upper(res.drawKind or "")), "draw", 4.0)
		else
			local pre = {}
			for j = 1, math.max(#cards, #scores) do
				local c = cards[j]
				local a, b = c and num(c[1]) or 0, c and num(c[2]) or 0
				local forWinner, even
				if c then
					forWinner = (winner == "red" and a > b) or (winner == "blue" and b > a)
					even = a == b
				else
					forWinner = true
					even = false
				end
				-- the card is read with the named man's total first (the loser's on a card he won)
				local s
				if c then
					local w1, w2 = (winner == "red") and a or b, (winner == "red") and b or a
					s = forWinner and fmtRound(w1, w2) or fmtRound(w2, w1)
				else
					s = scores[j]
				end
				pre[j] = { s = s, forWinner = forWinner, even = even }
			end
			-- the announcer reads the dissenting card first and saves the winner's name for the end
			local order = {}
			for j = 1, #pre do
				table.insert(order, j)
			end
			table.sort(order, function(x, y)
				local ax, ay = pre[x].forWinner and 1 or 0, pre[y].forWinner and 1 or 0
				if ax ~= ay then
					return ax < ay
				end
				return x < y
			end)
			local read = 0
			for _, j in ipairs(order) do
				local p = pre[j]
				read += 1
				local last = read == #order
				local text
				if p.even then
					text = string.format("Judge %d scores it %s, even.", j, p.s)
				elseif not p.forWinner then
					text = string.format("Judge %d scores the bout %s for %s.", j, p.s, lName)
				elseif last then
					text = string.format("%s %s, for the winner...", method == "UD" and "All three judges score it" or ("And judge " .. j .. " scores it"), p.s)
				else
					text = string.format("Judge %d scores it %s...", j, p.s)
				end
				say(text, "card", last and 3.0 or 2.6)
			end
			local how = method == "UD" and "UNANIMOUS DECISION" or (method == "SD" and "SPLIT DECISION" or "MAJORITY DECISION")
			local title = ""
			if info.title and info.title.title and winner then
				title = (info.champion == winner) and (" ...and STILL " .. string.upper(info.title.title) .. "...") or (" ...and NEW " .. string.upper(info.title.title) .. "...")
			end
			say(string.format("...by %s%s %s!", how, title, string.upper(wName)), "winner", 4.0)
		end
	end
	local raiseAt = t - 4.0
	for _, l in ipairs(lines) do
		if l.kind == "winner" or l.kind == "draw" then
			raiseAt = l.at
		end
	end
	return { lines = lines, dur = t + 1.0, raiseAt = raiseAt, winner = winner, stoppage = stoppage }
end

------------------------------------------------------------------------
-- the fight's report (the results screen): the per-round cards and the stats
------------------------------------------------------------------------
-- rounds = { Judging.Score results in order }, totals = { red = side, blue = side } -> a plain table safe to send
function Judging.Report(rounds, cards, totals, flip)
	local rep = { rounds = {}, cards = {}, totals = {} }
	for r, round in ipairs(rounds or {}) do
		local entry = { cards = {}, judges = {}, kd = { num(round.kd and round.kd[1]), num(round.kd and round.kd[2]) } }
		for j, c in ipairs(round.cards or {}) do
			entry.cards[j] = flip and { c[2], c[1] } or { c[1], c[2] }
			local jd = round.judges and round.judges[j]
			entry.judges[j] = jd and { id = jd.id, reason = jd.reason, diff = flip and -num(jd.diff) or num(jd.diff) } or nil
		end
		if flip then
			entry.kd = { entry.kd[2], entry.kd[1] }
		end
		rep.rounds[r] = entry
	end
	for j, c in ipairs(cards or {}) do
		rep.cards[j] = flip and { num(c[2]), num(c[1]) } or { num(c[1]), num(c[2]) }
	end
	local function plain(S)
		local o = {}
		for k, v in pairs(S or {}) do
			if type(v) == "number" then
				o[k] = math.floor(v * 100) / 100
			elseif type(v) == "table" then
				o[k] = table.clone(v)
			end
		end
		return o
	end
	rep.totals.you = plain(flip and totals.blue or totals.red)
	rep.totals.opp = plain(flip and totals.red or totals.blue)
	for j, judge in ipairs(Judging.JUDGES) do
		rep.judgeNames = rep.judgeNames or {}
		rep.judgeNames[j] = { name = judge.name, lean = judge.lean }
	end
	return rep
end

return Judging
