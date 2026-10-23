--!nocheck
-- tools/sim/test_frametraits.luau: the body frames' ring traits (Shared.FrameTraits) and where FightEngine / FightAI
-- apply them (tools/sim/fightsim: the real engine on stub rigs).
--   * the data: every frame has every multiplier, Athletic is the baseline, the orderings the design promises (Lean
--     the fastest hands / feet / longest dodge windows, Heavyweight the most power / chin / clinch and the slowest)
--   * the engine: the frame from data.app.body.frame; the punch window (and the client's mirror), the stamina a punch
--     costs, the walking speed, the reach, the dodge windows, head and body damage taken, the get-up
--   * the AI: a heavyweight wants it closer and hooks inside, a Lean boxes at range with the straights
--   * balance at equal level (Boxer-Puncher vs Boxer-Puncher, no ring traits): Heavyweight vs Lean about even, the
--     heavyweight winning more by stoppage and the Lean more on the cards; every frame close to even against Athletic
--   lune run tools/sim/test_frametraits.luau [--quick] [--table]     (--table: the whole frame x frame matrix)
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new()
local FrameTraits = S.H.require("FrameTraits")
local FightAI = S.FightAI
local Random = S.H.globals.Random
local QUICK = table.find(process.args, "--quick") ~= nil
local TABLE = table.find(process.args, "--table") ~= nil

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end
local FRAMES = FrameTraits.Order
local LEAN, ATH, MUS, POW, HVY = "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build"

------------------------------------------------------------------------
-- the data
------------------------------------------------------------------------
do
	check("data: the five frames of Config.BodyTypes", #FRAMES == 5 and FrameTraits.Data[LEAN] and FrameTraits.Data[HVY])
	for _, id in ipairs(S.Config.BodyTypes) do
		check("data: a traits entry for " .. id.id, FrameTraits.Data[id.id] ~= nil)
	end
	for _, id in ipairs(FRAMES) do
		local t = FrameTraits.Data[id]
		for _, k in ipairs(FrameTraits.Keys) do
			check(id .. "." .. k .. " is a multiplier in 0.7..1.4", type(t[k]) == "number" and t[k] >= 0.7 and t[k] <= 1.4, t[k])
		end
		check(id .. ": pros and cons", #t.pros >= 2 and #t.cons >= 1)
		check(id .. ": ai block", type(t.ai) == "table" and type(t.ai.range) == "number" and type(t.ai.inside) == "number")
	end
	local A = FrameTraits.Data[ATH]
	for _, k in ipairs(FrameTraits.Keys) do
		check("Athletic is the baseline (" .. k .. " within 5%)", A[k] >= 0.95 and A[k] <= 1.06, A[k])
	end
	local function rising(key, order)
		for i = 2, #order do
			local a, b = FrameTraits.Data[order[i - 1]][key], FrameTraits.Data[order[i]][key]
			check(string.format("%s: %s <= %s", key, order[i - 1], order[i]), a <= b, a .. " > " .. b)
		end
	end
	rising("power", { LEAN, ATH, MUS, POW, HVY })
	rising("chin", { LEAN, ATH, MUS, POW, HVY })
	rising("kdResist", { LEAN, ATH, MUS, POW, HVY })
	rising("clinch", { LEAN, ATH, MUS, POW, HVY })
	rising("handSpeed", { HVY, POW, MUS, ATH, LEAN })
	rising("footSpeed", { HVY, POW, MUS, LEAN })
	rising("staminaRegen", { HVY, POW, MUS, ATH, LEAN })
	rising("dodgeWindow", { HVY, POW, MUS, ATH, LEAN })
	rising("getUpTime", { LEAN, ATH, MUS, POW, HVY })
	rising("bodyAbsorb", { LEAN, ATH, MUS, POW, HVY })
	check("the Power Build has the biggest single punch (kdPower)", FrameTraits.Data[POW].kdPower > FrameTraits.Data[HVY].kdPower and FrameTraits.Data[POW].kdPower > FrameTraits.Data[MUS].kdPower)
	check("the Power Build is the inside fighter (insideBonus)", FrameTraits.Data[POW].insideBonus >= FrameTraits.Data[HVY].insideBonus and FrameTraits.Data[POW].insideBonus > 1)
	check("the Lean frame has the long arms", FrameTraits.Data[LEAN].reachBonus > 1 and FrameTraits.Data[HVY].reachBonus == 1)
	check("the heavyweight is the biggest target, the Lean the smallest", FrameTraits.Data[HVY].target > 1 and FrameTraits.Data[LEAN].target < 1)
	check("the Muscular frame pays for its power punches", FrameTraits.Data[MUS].powerDrain > 1 and FrameTraits.Data[LEAN].powerDrain == 1)
	rising("tank", { HVY, POW, MUS, ATH, LEAN })
	check("growth: a Lean's hands grow quicker, a heavyweight's power (Training.GainMultiplier)", FrameTraits.GrowthMul(LEAN, "PunchSpeed") > 1 and FrameTraits.GrowthMul(HVY, "Power") > 1
		and FrameTraits.GrowthMul(HVY, "Footwork") < 1 and FrameTraits.GrowthMul(ATH, "Power") == 1 and FrameTraits.GrowthMul("x", "Power") == 1)
	for id, g in pairs(FrameTraits.Growth) do
		for k, v in pairs(g) do
			check("growth: " .. id .. "." .. k .. " is a small multiplier and a real stat", v >= 0.9 and v <= 1.1 and table.find(S.Config.StatKeys, k) ~= nil, v)
		end
	end
	-- helpers
	check("Get: an unknown id is Athletic", FrameTraits.Get("Nope") == FrameTraits.Data[ATH] and FrameTraits.Get(nil) == FrameTraits.Data[ATH])
	check("IdOf: the engine's data (app.body.frame)", FrameTraits.IdOf({ app = { body = { frame = LEAN } } }) == LEAN)
	check("IdOf: a profile summary (appearance.body.frame)", FrameTraits.IdOf({ appearance = { body = { frame = HVY } } }) == HVY)
	check("IdOf: nothing is Athletic", FrameTraits.IdOf(nil) == ATH and FrameTraits.IdOf({ app = { gender = 1 } }) == ATH and FrameTraits.IdOf({ app = { body = { frame = "Bogus" } } }) == ATH)
	check("Mul: 1 for an unknown id or key", FrameTraits.Mul(nil, "handSpeed") == 1 and FrameTraits.Mul(LEAN, "nope") == 1 and FrameTraits.Mul(LEAN, "handSpeed") == FrameTraits.Data[LEAN].handSpeed)
	check("Read: the short line", FrameTraits.Read(HVY):find("Heavyweight") ~= nil and FrameTraits.Read("x") == nil)
	check("ShortName: Build dropped", FrameTraits.ShortName(HVY) == "Heavyweight" and FrameTraits.ShortName(POW) == "Power" and FrameTraits.ShortName(LEAN) == "Lean")
	check("Pros / Cons are copies", FrameTraits.Pros(LEAN) ~= FrameTraits.Data[LEAN].pros and #FrameTraits.Cons(HVY) == #FrameTraits.Data[HVY].cons)
end

------------------------------------------------------------------------
-- the engine
------------------------------------------------------------------------
-- a live fight at the start of round 1, both men in range, the red corner of `frame`
local function liveFight(redFrame, blueFrame, seed)
	local rng = Random.new(seed or 1)
	S.setClock(1000)
	local red = S.Boxer({ frame = redFrame, style = "BoxerPuncher", level = 60 }, rng)
	local blue = S.Boxer({ frame = blueFrame or ATH, style = "BoxerPuncher", level = 60 }, Random.new(seed or 1))
	-- the same stats on both sides (the frames are the only difference)
	for k, v in pairs(red.stats) do
		blue.stats[k] = v
	end
	local fight = S.NewFight(red, blue, 6, seed or 1)
	fight.P.traits, fight.O.traits = {}, {}
	fight.round = 1
	fight.live, fight.paused, fight.kdHold, fight.menuHold = true, false, false, false
	fight.roundEnd = S.now() + 60
	fight.resumedAt = S.now()
	return fight
end
local V3, CF = S.H.globals.Vector3, S.H.globals.CFrame
-- the two men `gap` studs apart, square on (the stub rigs start 6 apart: out of range)
local function closeTo(fight, gap)
	fight.P.root.CFrame = CF.lookAt(V3.new(0, 3.2, 0), V3.new(gap, 3.2, 0))
	fight.O.root.CFrame = CF.lookAt(V3.new(gap, 3.2, 0), V3.new(0, 3.2, 0))
end
local function actWindup(F)
	local act = F.model:GetAttribute("Act") or ""
	return tonumber(act:match("^[^|]+|[^|]+|[^|]+|([%d%.]+)"))
end
do
	local f = liveFight(LEAN, HVY)
	check("engine: the frame comes from data.app.body.frame", f.P.frame == FrameTraits.Data[LEAN] and f.O.frame == FrameTraits.Data[HVY])
	check("engine: no frame is Athletic", liveFight(nil).P.frame == FrameTraits.Data[ATH])
	-- the punch window: the act's wind-up, divided by the frame's hand speed
	local w = {}
	local cost = {}
	for _, id in ipairs(FRAMES) do
		local ff = liveFight(id, ATH)
		local before = ff.P.stamina
		ff:Punch(ff.P, "cross", false)
		w[id] = actWindup(ff.P)
		cost[id] = before - ff.P.stamina
	end
	check("engine: a punch went out of every frame", w[LEAN] and w[ATH] and w[HVY], w[LEAN])
	check("engine: the Lean's hands are the fastest, the heavyweight's the slowest", w[LEAN] < w[ATH] and w[ATH] < w[MUS] and w[MUS] < w[POW] and w[POW] < w[HVY],
		string.format("%.3f %.3f %.3f %.3f %.3f", w[LEAN], w[ATH], w[MUS], w[POW], w[HVY]))
	check("engine: the window is divided by handSpeed (the client's predWindup mirror)",
		near(w[LEAN] / w[ATH], FrameTraits.Data[ATH].handSpeed / FrameTraits.Data[LEAN].handSpeed, 0.03) and near(w[HVY] / w[ATH], FrameTraits.Data[ATH].handSpeed / FrameTraits.Data[HVY].handSpeed, 0.03),
		string.format("%.3f %.3f", w[LEAN] / w[ATH], w[HVY] / w[ATH]))
	check("engine: a cross costs a Lean less gas than a heavyweight", cost[LEAN] < cost[ATH] and cost[ATH] < cost[HVY], string.format("%.2f %.2f %.2f", cost[LEAN], cost[ATH], cost[HVY]))
	check("engine: the heavyweight's tank is the smallest (tank)", liveFight(HVY).P.maxStam < liveFight(ATH).P.maxStam and liveFight(LEAN).P.maxStam >= liveFight(ATH).P.maxStam)
	check("engine: the Muscular frame's power punch costs more than Athletic's", cost[MUS] > cost[ATH])
	-- the jab is not a power punch: Muscular's jab costs Athletic's
	local fm, fa = liveFight(MUS, ATH), liveFight(ATH, ATH)
	local bm, ba = fm.P.stamina, fa.P.stamina
	fm:Punch(fm.P, "jab", false)
	fa:Punch(fa.P, "jab", false)
	check("engine: the jab is not a power punch (Muscular's costs only the frame's drain)", near((bm - fm.P.stamina) / (ba - fa.P.stamina), FrameTraits.Data[MUS].staminaDrain / FrameTraits.Data[ATH].staminaDrain, 1e-3),
		(bm - fm.P.stamina) / (ba - fa.P.stamina))
	-- the feet
	local speed = {}
	for _, id in ipairs(FRAMES) do
		local ff = liveFight(id, ATH)
		ff:UpdateMovement(ff.P, 0.05)
		speed[id] = ff.P.hum.WalkSpeed
	end
	check("engine: the Lean is the quickest on his feet, the heavyweight the slowest", speed[LEAN] > speed[ATH] and speed[ATH] >= speed[MUS] and speed[MUS] > speed[POW] and speed[POW] > speed[HVY],
		string.format("%.1f %.1f %.1f %.1f %.1f", speed[LEAN], speed[ATH], speed[MUS], speed[POW], speed[HVY]))
	-- the reach: the Lean's arm is longer for the hit geometry (the stub rigs: the tape's frame)
	-- (against the same man's frame built with Athletic's traits: the frames also stand at their own heights, Builder.Scales)
	local gl, ga = liveFight(LEAN, ATH), liveFight(ATH, ATH)
	local GL = gl:Geo(gl.P)
	gl.P.frame, gl.P.geo = FrameTraits.Data[ATH], nil
	local GL0 = gl:Geo(gl.P)
	gl.P.frame, gl.P.geo = FrameTraits.Data[LEAN], GL
	check("engine: the Lean's arm reaches further (reachBonus)", GL and GL0 and near(GL.arm / GL0.arm, FrameTraits.Data[LEAN].reachBonus, 0.002), GL and GL0 and GL.arm / GL0.arm)
	check("engine: an Athletic arm is the plain geometry", near(ga:Geo(ga.P).arm, GL0.arm * (ga:Geo(ga.P).hScale / GL0.hScale), 0.01))
	-- the dodge windows
	local gh = liveFight(HVY, ATH)
	check("engine: the Lean's dodge windows are the longest, the heavyweight's the shortest",
		near(gl:DefenseMul(gl.P) / ga:DefenseMul(ga.P), FrameTraits.Data[LEAN].dodgeWindow, 1e-6) and near(gh:DefenseMul(gh.P) / ga:DefenseMul(ga.P), FrameTraits.Data[HVY].dodgeWindow, 1e-6))
	-- head and body damage taken: the same punch, the same dice, against a Lean and a heavyweight
	local function damageTo(frame, body, seed)
		local ff = liveFight(ATH, frame, seed)
		ff.rng = Random.new(seed)
		closeTo(ff, 3.2)
		local h0, b0 = ff.O.health, ff.O.body
		ff:Resolve(ff.P, ff.O, "cross", body, 1, {})
		return h0 - ff.O.health, b0 - ff.O.body
	end
	local hits = 0
	for seed = 1, 12 do
		local hl = damageTo(LEAN, false, seed)
		local hh = damageTo(HVY, false, seed)
		if hl > 0 and hh > 0 then
			hits += 1
			check("engine: the same cross takes more off a Lean head than a heavyweight's (seed " .. seed .. ")", near(hl / hh, FrameTraits.Data[HVY].chin / FrameTraits.Data[LEAN].chin, 0.02), hl / hh)
		end
		local _, bl = damageTo(LEAN, true, seed)
		local _, bh = damageTo(HVY, true, seed)
		if bl > 0 and bh > 0 then
			hits += 1
			check("engine: the same body shot hurts a Lean body more (seed " .. seed .. ")", near(bl / bh, FrameTraits.Data[HVY].bodyAbsorb / FrameTraits.Data[LEAN].bodyAbsorb, 0.02), bl / bh)
		end
	end
	check("engine: the damage dice landed on both frames at least a few times", hits >= 4, hits)
	-- the power: the same cross out of a heavyweight against the same Athletic head
	local function damageFrom(frame, seed)
		local ff = liveFight(frame, ATH, seed)
		ff.rng = Random.new(seed)
		closeTo(ff, 3.2)
		local h0 = ff.O.health
		ff:Resolve(ff.P, ff.O, "cross", false, 1, {})
		return h0 - ff.O.health
	end
	local powered = 0
	for seed = 1, 12 do
		local dl, dh = damageFrom(LEAN, seed), damageFrom(HVY, seed)
		if dl > 0 and dh > 0 then
			powered += 1
			check("engine: the heavyweight's cross lands harder (seed " .. seed .. ")", near(dh / dl, FrameTraits.Data[HVY].power / FrameTraits.Data[LEAN].power, 0.02), dh / dl)
		end
	end
	check("engine: the power dice landed", powered >= 3, powered)
	-- the get-up: a heavyweight is slower up (the act's seconds, the busy clock), a Lean quicker
	local up = {}
	for _, id in ipairs({ LEAN, ATH, HVY }) do
		local ff = liveFight(ATH, id)
		ff.O.state = "down"
		ff.O.downSeverity = "normal"
		local now = ff:Now()
		coroutine.wrap(function()
			ff:GetUp(ff.O, 1)
		end)()
		up[id] = ff.O.busyUntil - now
	end
	check("engine: the get-up scales with getUpTime", near(up[HVY] / up[ATH], FrameTraits.Data[HVY].getUpTime, 1e-3) and near(up[LEAN] / up[ATH], FrameTraits.Data[LEAN].getUpTime, 1e-3),
		string.format("%.2f %.2f %.2f", up[LEAN], up[ATH], up[HVY]))
	-- the clinch: a heavyweight's hold lasts longer
	local function hold(frame)
		local ff = liveFight(frame, ATH)
		closeTo(ff, 3)
		local now = ff:Now()
		ff:Clinch(ff.P)
		return ff.P.state == "clinch" and (ff.O.clinchUntil - now) or nil
	end
	local hh, hl = hold(HVY), hold(LEAN)
	check("engine: a heavyweight's clinch holds the other man longer than a Lean's", hh and hl and hh > hl, tostring(hh) .. " / " .. tostring(hl))
	-- the tape
	local tape = nil
	local ft = liveFight(LEAN, HVY)
	ft.SendEach = function(_, fn)
		local m = fn(ft.P)
		if m and m.t == "start" then
			tape = m.tape
		end
	end
	ft.EnableTraits = function() end
	ft.SpawnReferee = function() end
	ft.ScoutTraits = function()
		return nil
	end
	ft.Entrance = function()
		coroutine.yield() -- (the start message is out: no ring walk on the stub rigs)
	end
	pcall(function()
		-- (Run goes on into the walkout: only the start message is wanted)
		local co = coroutine.create(function()
			ft:Run()
		end)
		coroutine.resume(co)
	end)
	check("engine: the start message's tape carries both frames (the client's windows and the tale of the tape)", tape and tape.you.frame == LEAN and tape.opp.frame == HVY, tape and tape.you.frame)
end

------------------------------------------------------------------------
-- the AI
------------------------------------------------------------------------
do
	local function ai(frame, oFrame)
		local ff = liveFight(frame, oFrame or ATH)
		ff.P.ai = FightAI.new(ff.P, ff.O, ff)
		ff.O.ai = FightAI.new(ff.O, ff.P, ff)
		return ff.P.ai, ff
	end
	local aL, aA, aP, aH = ai(LEAN), ai(ATH), ai(POW), ai(HVY)
	check("ai: a Lean boxes further out, a heavyweight wants it closer", aL.baseRange > aA.baseRange and aA.baseRange > aP.baseRange and aP.baseRange > aH.baseRange)
	check("ai: the heavy frames press", aH.baseAggr > aA.baseAggr and aP.baseAggr > aA.baseAggr and aH.baseAggr > aP.baseAggr)
	local pL, pA, pP = aL:PunchPrefs(), aA:PunchPrefs(), aP:PunchPrefs()
	check("ai: a Power Build hooks and uppercuts, a Lean works the straights", pP.leadhook / pP.jab > pA.leadhook / pA.jab and pL.leadhook / pL.jab < pA.leadhook / pA.jab)
	-- vs a Lean: the body
	local vsLean, _ = ai(ATH, LEAN)
	local vsHvy, _ = ai(ATH, HVY)
	vsLean:UpdateMode()
	vsHvy:UpdateMode()
	check("ai: it goes to a Lean man's body more than a heavyweight's", vsLean.bodyBias > vsHvy.bodyBias, vsLean.bodyBias .. " / " .. vsHvy.bodyBias)
end

------------------------------------------------------------------------
-- balance at equal level: the frame match-ups
------------------------------------------------------------------------
local N = QUICK and 12 or 40
local function run(n, a, b)
	local w, ko, dec, koW, decW, secs = 0, 0, 0, { red = 0, blue = 0 }, { red = 0, blue = 0 }, 0
	for i = 1, n do
		local r = S.Fight({ red = { style = "BoxerPuncher", level = 60, noTraits = true, frame = a }, blue = { style = "BoxerPuncher", level = 60, noTraits = true, frame = b }, rounds = 6, seed = i * 7919 + 13 })
		local stop = r.method == "KO" or r.method == "TKO" or r.method == "RTD"
		if r.winner == "red" then
			w += 1
		elseif r.winner == "draw" then
			w += 0.5
		end
		if stop then
			ko += 1
			if r.winner ~= "draw" then
				koW[r.winner] += 1
			end
		elseif r.winner ~= "draw" then
			dec += 1
			decW[r.winner] += 1
		end
		secs += r.seconds
	end
	return { win = w / n, ko = ko / n, koW = koW, decW = decW, secs = secs / n }
end
local function pct(x)
	return string.format("%3d%%", math.floor(x * 100 + 0.5))
end
local SHORT = { Lean = "LEAN", Athletic = "ATH", Muscular = "MUS", ["Power Build"] = "POW", ["Heavyweight Build"] = "HVY" }
if TABLE then
	print(string.format("\n== frame vs frame (Boxer-Puncher, level 60, no traits, 6 rounds; red win %% | stoppages | red KO wins / blue KO wins), %d a cell", N))
	local head = "red \\ blue  "
	for _, b in ipairs(FRAMES) do
		head ..= string.format("%-22s", SHORT[b])
	end
	print(head)
	for _, a in ipairs(FRAMES) do
		local line = string.format("%-12s", SHORT[a])
		for _, b in ipairs(FRAMES) do
			local st = run(N, a, b)
			line ..= string.format("%s ko %s %2d/%-2d       ", pct(st.win), pct(st.ko), st.koW.red, st.koW.blue)
		end
		print(line)
	end
end
-- both corners of a match-up pooled (the red corner's AI thinks first: the two orders are not the same fight)
local function pooled(n, a, b)
	local ab, ba = run(n, a, b), run(n, b, a)
	local A = { win = (ab.win + (1 - ba.win)) / 2, ko = ab.koW.red + ba.koW.blue, dec = ab.decW.red + ba.decW.blue }
	local B = { win = 1 - A.win, ko = ab.koW.blue + ba.koW.red, dec = ab.decW.blue + ba.decW.red }
	A.decShare = A.dec / math.max(1, A.ko + A.dec)
	B.decShare = B.dec / math.max(1, B.ko + B.dec)
	return A, B, (ab.ko + ba.ko) / 2, (ab.secs + ba.secs) / 2
end
local function line(a, b, A, B, stop, secs)
	print(string.format("%-4s vs %-4s: %s wins %s (KO %d, points %d; %.0f%% on points) - %s KO %d, points %d (%.0f%%); stoppages %s, %.0f s",
		SHORT[a], SHORT[b], SHORT[a], pct(A.win), A.ko, A.dec, A.decShare * 100, SHORT[b], B.ko, B.dec, B.decShare * 100, pct(stop), secs))
end
do
	local H, L, stop, secs = pooled(N, HVY, LEAN)
	line(HVY, LEAN, H, L, stop, secs)
	check("balance: Heavyweight vs Lean at equal skill is close to even (35..65%)", H.win >= 0.35 and H.win <= 0.65, H.win)
	check("balance: the heavyweight wins more by stoppage than the Lean does", H.ko > L.ko, H.ko .. " / " .. L.ko)
	check("balance: the Lean's wins come on the cards more often than the heavyweight's", L.decShare >= H.decShare, L.decShare .. " / " .. H.decShare)
	local Pw, L2, stop2, secs2 = pooled(N, POW, LEAN)
	line(POW, LEAN, Pw, L2, stop2, secs2)
	check("balance: Power Build vs Lean close to even (30..70%), the Power Build the stopper", Pw.win >= 0.3 and Pw.win <= 0.7 and Pw.ko >= L2.ko, Pw.win)
	for _, id in ipairs({ LEAN, MUS, POW, HVY }) do
		local X, A, st, sc = pooled(N, id, ATH)
		line(id, ATH, X, A, st, sc)
		check("balance: " .. id .. " vs Athletic at equal skill is close to even (30..70%)", X.win >= 0.3 and X.win <= 0.7, X.win)
	end
	local hh = run(QUICK and 8 or 20, HVY, HVY)
	local ll = run(QUICK and 8 or 20, LEAN, LEAN)
	print(string.format("mirror: Heavyweight vs Heavyweight stoppages %s, Lean vs Lean %s", pct(hh.ko), pct(ll.ko)))
	check("balance: two Leans go the distance at least as often as two heavyweights", ll.ko <= hh.ko + 0.1, ll.ko .. " / " .. hh.ko)
end

print(string.format("test_frametraits: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
