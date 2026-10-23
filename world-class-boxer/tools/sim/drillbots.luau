--!nocheck
-- drillbots.luau: simulated players for every DrillScore / DrillWorkouts judge (test_drills.luau,
-- test_training.luau, drillmeasure.luau).
-- A bot sees what the player sees (the judge's live state the stage draws) and answers with inputs:
--   Bots.Act(seg, j, t, M, mem, skill, rng) -> { { id, down }, ... } to send at drill time t
-- skill: one of Bots.SKILLS. Every policy is written for the perfect player and the average one, and
-- the skill's `k` mixes between them (0 = perfect, 1 = average: their numbers are exactly the old ones,
-- so the tests play the same way; 0.5 = a high-skill player, 1.5 = a low-skill one with slower
-- reactions, more timing error, more wrong presses and more skipped beats). `mem` is the bot's own
-- memory for this segment.
local Bots = {}

local TWO_PI = 2 * math.pi

-- k scales the timing (reactions, timing error, how often the player looks); w the slips of the mind
-- (a wrong move, a skipped beat, biting on a feint) - a slow player is not that much more wrong
Bots.SKILLS = {
	perfect = { name = "perfect", k = 0, w = 0 },
	high = { name = "high", k = 0.5, w = 0.5 },
	average = { name = "average", k = 1, w = 1 },
	low = { name = "low", k = 1.5, w = 1.25 },
	idle = { name = "idle", k = 1, w = 1, idle = true },
}
-- a human-like number between the perfect player's (a) and the average one's (b)
local function mix(sk, a, b)
	return a + (b - a) * sk.k
end

local function tap(out, id)
	table.insert(out, { id, true })
	table.insert(out, { id, false })
end
local function hold(out, mem, id, want)
	mem.held = mem.held or {}
	if (mem.held[id] == true) ~= want then
		mem.held[id] = want
		table.insert(out, { id, want })
	end
end
-- a tap-or-hold control: tap to toggle until it is in the wanted state (once per gap seconds)
local function toggle(out, mem, id, isOn, want, t, gap)
	mem.tg = mem.tg or {}
	if isOn ~= want and t - (mem.tg[id] or -1) >= (gap or 0.05) then
		mem.tg[id] = t
		tap(out, id)
	end
end
local function every(mem, key, t, period)
	mem.ev = mem.ev or {}
	if t - (mem.ev[key] or -math.huge) >= period then
		mem.ev[key] = t
		return true
	end
	return false
end
local function needle(el, sweep)
	local u = (math.max(0, el) * sweep) % 2
	return u < 1 and u or 2 - u
end

local A = {}

-- sequences: the next id after a beat (on the heavy bag's rhythm combos the perfect player keeps the
-- beat exactly; the average one is slower, with a wrong press now and then)
A.seq = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local gap = mix(sk, seg.beat or 0.1, 0.34 + rng:NextNumber() * 0.2)
	mem.at = mem.at or (M + mix(sk, 0.12, 0.5))
	if t >= mem.at and j.idx <= #seg.ids then
		mem.at = t + gap
		local id = seg.ids[j.idx]
		if rng:NextNumber() < 0.15 * sk.w then
			-- a wrong press: another move of the same sequence (if it has one)
			for _, other in ipairs(seg.ids) do
				if other ~= id then
					id = other
					break
				end
			end
		end
		tap(out, id)
	end
	return out
end
-- the wrong answers a drill has a button for
local WRONG = { punch = "slipL", slipL = "slipR", slipR = "slipL", roll = "slipL", F = "B", B = "F", L = "R", R = "L", jab = "cross", cross = "jab", leadhook = "jab",
	rearhook = "leadhook", uppercut = "cross", overhand = "jab", pivotL = "slipL", parry = "jab" }
A.cue = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	mem.rt = mem.rt or mix(sk, 0.18, 0.35 + rng:NextNumber() * 0.5)
	if not mem.done and t - M >= mem.rt then
		mem.done = true
		local id = seg.want
		if rng:NextNumber() < 0.2 * sk.w then
			id = WRONG[id] or id
		end
		tap(out, id)
	end
	return out
end
-- call & response: each call answered a reaction after it; the average player bites on some feints,
-- throws a wrong move or nothing now and then
A.call = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	mem.plan = mem.plan or {}
	for k, c in ipairs(j.calls) do
		local p = mem.plan[k]
		if not p then
			p = { rt = mix(sk, 0.16, 0.3 + rng:NextNumber() * 0.4), wrong = rng:NextNumber() < 0.12 * sk.w, bite = rng:NextNumber() < 0.3 * sk.w, skip = rng:NextNumber() < 0.08 * sk.w }
			mem.plan[k] = p
		end
		if not p.done and t >= c.t + p.rt then
			p.done = true
			if c.feint then
				if p.bite then
					tap(out, "jab")
				end
			elseif not p.skip then
				tap(out, p.wrong and (WRONG[c.id] or c.id) or c.id)
			end
		end
	end
	return out
end
A.counter = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local rt = mix(sk, 0.16, 0.42)
	if j.step == 1 and not mem.d1 and t - M >= rt then
		mem.d1 = true
		tap(out, (rng:NextNumber() < 0.15 * sk.w) and (seg.want == "slipL" and "slipR" or "slipL") or seg.want)
	elseif j.step == 2 and not mem.d2 and t - j.shown2 >= rt then
		mem.d2 = true
		tap(out, "punch")
	end
	return out
end
A.rebound = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if j.step == 1 and not mem.d1 and t - M >= mix(sk, 0.15, 0.35) then
		mem.d1 = true
		tap(out, "punch")
	elseif j.step == 2 and not mem.d2 then
		mem.err = mem.err or mix(sk, 0, rng:NextNumber() * 0.36 - 0.16)
		if t >= j.punchT + seg.ret + mem.err - 0.005 then
			mem.d2 = true
			tap(out, seg.want)
		end
	end
	return out
end
A.needle = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	-- (the timing error is in time - up to ~0.12 s either way for the average player - and the needle
	-- turns it into a distance: a faster sweep, a bigger miss)
	mem.off = mem.off or mix(sk, 0, (rng:NextNumber() * 2 - 1) * 0.12 * seg.sweep)
	if not mem.done and t - M > 0.2 then
		local pos = needle(t - M, seg.sweep)
		if math.abs(pos - (seg.c + mem.off)) < mix(sk, 0.012, 0.03) then
			mem.done = true
			tap(out, "power")
		end
	end
	return out
end
A.burst = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if every(mem, "p", t, mix(sk, 1 / 7.5, 1 / 3.6)) then
		mem.side = mem.side == "L" and "R" or "L"
		tap(out, mem.side)
	end
	return out
end
-- beats: each note at its time (average: early / late by up to ~0.12 s, a few missed)
A.notes = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	mem.plan = mem.plan or {}
	for i, n in ipairs(j.notes) do
		if not n.judged then
			local p = mem.plan[i]
			if not p then
				p = { off = mix(sk, 0, rng:NextNumber() * 0.28 - 0.12), skip = rng:NextNumber() < 0.12 * sk.w }
				mem.plan[i] = p
			end
			if not p.done and not p.skip and t >= n.t + p.off - 0.004 then
				p.done = true
				tap(out, n.lane)
			end
		end
	end
	return out
end
A.lift = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if not mem.down and t - M >= 0.2 then
		mem.down = t
		table.insert(out, { "lift", true })
	end
	if mem.down and not mem.up then
		-- (the release is early or late by a human moment: up to 0.14 s for the average player)
		mem.target = mem.target or (seg.lo + seg.width / 2 + mix(sk, 0, (rng:NextNumber() * 2 - 1) * 0.14) * seg.speed)
		local f = seg.speed * (t - mem.down)
		if f >= mem.target - seg.speed / 120 then
			mem.up = true
			table.insert(out, { "lift", false })
		end
	end
	return out
end
A.pace = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local ph = seg.phases[j.phaseOf(t)]
	if sk.k == 0 then
		if j.v < ph[1] + (ph[2] - ph[1]) * 0.35 and every(mem, "p", t, 0.06) then
			tap(out, "push")
		end
	elseif every(mem, "p", t, 0.45) and j.v < (ph[1] + ph[2]) / 2 + (rng:NextNumber() - 0.5) * 0.35 * sk.k then
		tap(out, "push")
	end
	return out
end
A.breath = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local lag = mix(sk, 0, 0.45)
	hold(out, mem, "breathe", j.inPhase(t - lag))
	return out
end
A.rope = function(seg, j, t, M, mem, sk, rng)
	-- hold and release: JUMP goes down ahead of the pass (longer ahead for a double under: the charge)
	-- and comes up as the rope reaches the feet; the foot calls are presses of the called foot. Like a
	-- player, the bot crouches for the next jump as soon as it has released the last one (the next pass is
	-- estimated until the judge has moved on to it)
	local out = {}
	if t < j.tripped or not j.w then
		if mem.down then
			mem.down = nil
			table.insert(out, { "jump", false })
		end
		mem.plan = {}
		return out
	end
	local a = j.angle(t)
	local k = math.floor(a / TWO_PI) + 1
	local toPass = (TWO_PI * k - a) / j.w
	mem.plan = mem.plan or {}
	-- the jump this pass is: the judged count, plus one while the last jump's pass is still to be judged
	local prev = mem.plan[j.done]
	local key = j.done
	local passT = t + toPass
	if j.pending or (prev and prev.done and prev.passT and t < prev.passT + 0.2) then
		key = j.done + 1
		local cue = seg.cues[j.ci + 1] or "jump"
		local base = j.pending or (prev and prev.passT) or passT
		passT = base + TWO_PI / (j.omega * (cue == "double" and 1.5 or 1))
	end
	local p = mem.plan[key]
	if not p then
		local charge = j.charge or 0.3
		local cue = key == j.done and j.cue or (seg.cues[j.ci + 1] or "jump")
		-- (nobody jumps more than half a second before the rope: the slow player's error is capped)
		p = { lead = math.min(0.5, mix(sk, 0.05, rng:NextNumber() * 0.42)), skip = rng:NextNumber() < 0.12 * sk.w, cue = cue }
		p.hold = cue == "double" and (charge + mix(sk, 0.06, -0.02 + rng:NextNumber() * 0.22)) or mix(sk, 0.12, 0.06 + rng:NextNumber() * 0.2)
		mem.plan[key] = p
	end
	p.passT = passT
	if p.skip then
		return out
	end
	local left = passT - t
	if p.cue == "footL" or p.cue == "footR" then
		if not p.done and left <= p.lead then
			p.done = true
			tap(out, p.cue)
		end
		return out
	end
	if not p.pressed and not mem.down and left <= p.lead + p.hold then
		p.pressed = true
		mem.down = true
		table.insert(out, { "jump", true })
	end
	if p.pressed and not p.done and left <= p.lead then
		p.done = true
		mem.down = nil
		table.insert(out, { "jump", false })
	end
	return out
end
A.lights = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if j.lit then
		mem.litAt = mem.litAt or t
		if t - mem.litAt >= mix(sk, 0.15, 0.45) then
			mem.litAt = nil
			tap(out, seg.ids[j.idx])
		end
	else
		mem.litAt = nil
	end
	return out
end

-- the weight room ------------------------------------------------------
A.bench = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if t - M < 0.2 then
		return out
	end
	toggle(out, mem, "press", j.press.on == true, true, t, 0.5)
	if every(mem, "look", t, mix(sk, 0, 0.4)) then
		local th = mix(sk, 0.03, 0.3)
		hold(out, mem, "L", j.x > th)
		hold(out, mem, "R", j.x < -th)
	end
	return out
end
A.deadlift = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if j.phase == "set" then
		mem.tol = mem.tol or mix(sk, seg.w * 0.25, seg.w * (0.5 + rng:NextNumber() * 2))
		if t - M > 0.2 and math.abs(j.needleAt(t) - seg.c) <= mem.tol then
			tap(out, "lift")
		end
		return out
	end
	if every(mem, "g", t, mix(sk, 0.12, 0.35)) and j.g < mix(sk, 0.45, 0.3) then
		tap(out, "grip")
	end
	return out
end
A.squat = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local ph = j.phase
	if ph == "ready" and t - M >= 0.2 then
		table.insert(out, { "sit", true })
		mem.down = true
	elseif ph == "descend" and mem.down then
		mem.target = mem.target or ((seg.lo + seg.hi) / 2 + mix(sk, 0, (rng:NextNumber() * 2 - 1) * 0.16))
		local v = seg.v0 + seg.acc * (t - j.descT)
		if j.z + v / 120 >= mem.target then
			mem.down = false
			table.insert(out, { "sit", false })
		end
	elseif ph == "bottom" then
		mem.wait = mem.wait or mix(sk, 0.25, 0.05 + rng:NextNumber() * 0.9)
		if t - j.bottomT >= mem.wait and not mem.drive then
			mem.drive = true
			table.insert(out, { "sit", true })
		end
	end
	return out
end
A.pullup = function(seg, j, t, M, mem, sk, rng)
	-- hold PULL from the bottom, let go with the chin in the sweet band (a reaction late: the climb goes on
	-- a little after the decision); the average player aims less well, now and then lets go short, and
	-- does not rest the grip
	local out = {}
	if t - M < 0.15 then
		return out
	end
	if not j.pull then
		if j.ready() then
			if not mem.waitT then
				mem.waitT = t + mix(sk, 0, 0.15 + rng:NextNumber() * 0.3)
			end
			-- (the perfect player hangs a moment for the grip when it is low)
			local rest = sk.k == 0 and j.grip < 0.3
			if t >= mem.waitT and not rest then
				mem.waitT = nil
				local mid = (seg.perfLo + seg.perfHi) / 2
				local short = rng:NextNumber() < 0.08 * sk.w
				mem.target = short and (seg.lo - 0.12) or (mid + mix(sk, 0, (rng:NextNumber() - 0.5) * 0.14))
				mem.lag = mix(sk, 0, 0.04 + rng:NextNumber() * 0.12)
				mem.relAt = nil
				table.insert(out, { "pull", true })
			end
		end
		return out
	end
	if not mem.relAt and j.h >= mem.target - seg.speed * mem.lag * 0.5 then
		mem.relAt = t + mem.lag
	end
	if mem.relAt and t >= mem.relAt then
		mem.relAt = nil
		table.insert(out, { "pull", false })
	end
	return out
end
A.tempo = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	mem.plan = mem.plan or {}
	for i, n in ipairs(j.notes) do
		local p = mem.plan[i]
		if not p then
			local early = rng:NextNumber() < 0.15 * sk.w
			p = { a = mix(sk, 0, rng:NextNumber() * 0.26 - 0.12), b = early and -((n.te - n.ts) * 0.5) or mix(sk, 0, rng:NextNumber() * 0.3 - 0.12) }
			mem.plan[i] = p
		end
		if not p.down and not n.judged and t >= n.ts + p.a - 0.004 then
			p.down = true
			table.insert(out, { n.lane, true })
		elseif p.down and not p.up and t >= n.te + p.b - 0.004 then
			p.up = true
			table.insert(out, { n.lane, false })
		end
	end
	return out
end
-- the plank on the ball: a look at the balance now and then, a shove back once it is clearly off
A.wobble = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if every(mem, "look", t, mix(sk, 0.05, 0.5)) then
		local th = seg.band * mix(sk, 0.3, 0.7)
		if j.x > th then
			tap(out, "L")
		elseif j.x < -th then
			tap(out, "R")
		end
	end
	return out
end
-- the sled push: the legs in turn while the drive is on (the average player is slower and now and then
-- steps with the same leg twice); nothing in the reset
A.mash = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local _, pushing = j.burstAt(t)
	if not pushing then
		return out
	end
	mem.at = mem.at or t
	if t >= mem.at then
		mem.at = t + mix(sk, 0.1, 0.17 + rng:NextNumber() * 0.06)
		local leg = mem.leg == "L" and "R" or "L"
		if rng:NextNumber() < 0.06 * sk.w then
			leg = mem.leg or "L"
		end
		mem.leg = leg
		tap(out, leg)
	end
	return out
end
-- the hold gauge: squeeze while the needle is under the band's middle, ease off over it (the average
-- player looks less often and corrects later)
A.gauge = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if every(mem, "look", t, mix(sk, 0.03, 0.16 + rng:NextNumber() * 0.08)) then
		local mid, half = (seg.lo + seg.hi) / 2, (seg.hi - seg.lo) / 2
		local v = j.shown(t)
		local m = half * mix(sk, 0.15, 0.45)
		if v < mid - m then
			hold(out, mem, "sq", true)
		elseif v > mid + m then
			hold(out, mem, "sq", false)
		end
	end
	return out
end
-- the road lane: stride when the pace drops under the pacer's band (a reaction late on a new leg),
-- breathe on the cues (the average player a little off the beat, now and then a cue missed)
A.road = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local lag = mix(sk, 0, 0.5)
	local leg = j.legAt(math.max(M, t - lag))
	if leg and every(mem, "look", t, mix(sk, 0.05, 0.2 + rng:NextNumber() * 0.12)) then
		local mid = (leg.lo + leg.hi) / 2
		if j.v < mid - (leg.hi - leg.lo) * mix(sk, 0.1, 0.25) then
			tap(out, "stride")
		end
	end
	mem.br = mem.br or {}
	for i, b in ipairs(seg.breaths) do
		local p = mem.br[i]
		if not p then
			p = { at = M + b + mix(sk, 0, (rng:NextNumber() - 0.35) * 0.5), skip = rng:NextNumber() < 0.08 * sk.w }
			mem.br[i] = p
		end
		if not p.done and not p.skip and t >= p.at then
			p.done = true
			tap(out, "breathe")
		end
	end
	return out
end
-- cardio -----------------------------------------------------------------
A.treadmill = function(seg, j, t, M, mem, sk, rng)
	-- the perfect player taps each step; the others hold a button down until the readout reaches the
	-- target (they look every `period`: a late look holds one step too many now and then)
	local out = {}
	local lag = mix(sk, 0, 0.9)
	local tg = j.target(t - lag)
	if sk.k == 0 then
		if every(mem, "s", t, 0.06) then
			if j.mph < tg.mph - 0.01 then
				tap(out, "spdUp")
			elseif j.mph > tg.mph + 0.01 then
				tap(out, "spdDn")
			end
			if j.incl < tg.incl then
				tap(out, "incUp")
			elseif j.incl > tg.incl then
				tap(out, "incDn")
			end
		end
		return out
	end
	if every(mem, "s", t, mix(sk, 0.06, 0.2)) then
		hold(out, mem, "spdUp", j.mph < tg.mph - 0.01)
		hold(out, mem, "spdDn", j.mph > tg.mph + 0.01)
		hold(out, mem, "incUp", j.incl < tg.incl)
		hold(out, mem, "incDn", j.incl > tg.incl)
	end
	return out
end
A.bike = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local h = j.hill(t)
	local ideal = math.max(1, math.min(seg.gears, math.floor(4.5 - 0.45 * h.grade + 0.5)))
	if sk.k == 0 then
		if every(mem, "g", t, 0.1) and j.gear ~= ideal then
			tap(out, j.gear < ideal and "gearUp" or "gearDn")
		end
		local k = math.max(0.45, math.min(1.7, 1 + 0.13 * (ideal - j.gear)))
		local iv = 30 * k / ((seg.lo + seg.hi) / 2)
		if every(mem, "p", t, iv) then
			mem.side = mem.side == "L" and "R" or "L"
			tap(out, mem.side)
		end
	else
		if every(mem, "g", t, 1.2 * sk.k) and math.abs(j.gear - ideal) >= (sk.k > 1 and 2 or 1) then
			tap(out, j.gear < ideal and "gearUp" or "gearDn")
		end
		-- (the cadence readout is in view: now and then the player speeds up or eases off toward the band)
		mem.iv = mem.iv or (0.4 + rng:NextNumber() * 0.1)
		if every(mem, "look", t, mix(sk, 0.1, 0.8)) and j.lastTap then
			local rpm = j.rpm(t)
			local m = (seg.hi - seg.lo) * 0.2
			if rpm < seg.lo + m then
				mem.iv = math.max(0.22, mem.iv * 0.9)
			elseif rpm > seg.hi - m then
				mem.iv = math.min(0.7, mem.iv * 1.1)
			end
		end
		if every(mem, "p", t, mem.iv + rng:NextNumber() * 0.06 * sk.k) then
			mem.side = mem.side == "L" and "R" or "L"
			tap(out, mem.side)
		end
	end
	return out
end
A.rower = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if sk.k == 0 then
		if j.phase == "catch" then
			hold(out, mem, "row", true)
		elseif j.phase == "drive" and j.x >= 0.97 then
			hold(out, mem, "row", false)
		elseif j.phase == "recover" then
			hold(out, mem, "row", false)
		end
	else
		if j.phase == "drive" then
			mem.fin = mem.fin or (0.7 + rng:NextNumber() * 0.35)
			if j.x >= math.min(1, mem.fin) and (j.x < 1 or j.hang > 0.25) then
				mem.fin = nil
				hold(out, mem, "row", false)
			end
		else
			-- a rushed catch (at x <= 0.25 on the way back) or a pause at the catch
			mem.cx = mem.cx or (rng:NextNumber() < 0.4 and 0.25 or -(0.2 + rng:NextNumber() * 0.5))
			local ready = (mem.cx > 0 and (j.phase == "catch" or j.x <= mem.cx)) or (mem.cx < 0 and j.phase == "catch" and t - j.reachedAt >= -mem.cx)
			if ready then
				mem.cx = nil
				-- (the hold flag may already read up from the last stroke)
				if mem.held and mem.held.row then
					mem.held.row = false
				end
				hold(out, mem, "row", true)
			end
		end
	end
	return out
end
-- recovery ---------------------------------------------------------------
A.icebath = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local on = j.br.on == true
	if sk.k == 0 then
		if not on and j.l <= 0.01 then
			toggle(out, mem, "breathe", on, true, t, 0.1)
		elseif on and j.l >= 0.99 then
			toggle(out, mem, "breathe", on, false, t, 0.1)
		end
	else
		if not on and j.l <= 0.3 + (mem.jit or 0) then
			mem.jit = rng:NextNumber() * 0.3
			toggle(out, mem, "breathe", on, true, t, 0.6)
		elseif on and j.l >= 0.75 + (mem.jit or 0) * 0.5 then
			toggle(out, mem, "breathe", on, false, t, 0.6)
		end
	end
	return out
end
A.stretch = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local lo, hi = j.band(t)
	local on = j.sink.on == true
	if sk.k == 0 then
		local mid = (lo + hi) / 2
		toggle(out, mem, "sink", on, j.z < mid, t, 0.03)
	elseif every(mem, "s", t, 0.3) then
		-- a hand on the dial: in once it's clearly short, out once it's clearly deep (late both ways)
		if j.z < lo then
			toggle(out, mem, "sink", on, true, t, 0.3)
		elseif j.z > hi - 0.02 then
			toggle(out, mem, "sink", on, false, t, 0.3)
		end
	end
	return out
end
A.massage = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if j.phase == "choose" then
		local want
		if sk.k == 0 then
			local best = -1
			for i, g in ipairs(seg.groups) do
				if not j.worked[g] and j.sore[g] > best then
					best, want = j.sore[g], i
				end
			end
		else
			mem.pick = mem.pick or {}
			if not mem.pick[j.round] then
				-- the sorest spot left half the time (an average eye on the body map), else any free one
				local free, best, bestI = {}, -1, nil
				for i, g in ipairs(seg.groups) do
					if not j.worked[g] then
						table.insert(free, i)
						if j.sore[g] > best then
							best, bestI = j.sore[g], i
						end
					end
				end
				mem.pick[j.round] = (rng:NextNumber() < mix(sk, 1, 0.65)) and bestI or free[rng:NextInteger(1, #free)]
			end
			want = mem.pick[j.round]
			if t - j.chooseAt < 1.5 then
				return out
			end
		end
		if want and every(mem, "c", t, mix(sk, 0.08, 0.25)) then
			if j.cursor == want then
				tap(out, "ok")
			else
				tap(out, "next")
			end
		end
		return out
	end
	mem.st = mem.st or {}
	for k, st in ipairs(j.strokes or {}) do
		local key = j.round .. ":" .. k
		local p = mem.st[key]
		if not p then
			p = { off = mix(sk, 0, rng:NextNumber() * 0.5 - 0.22), skip = rng:NextNumber() < 0.2 * sk.w }
			mem.st[key] = p
		end
		if not st.judged and not p.done and not p.skip and t >= st.t + p.off - 0.004 then
			p.done = true
			tap(out, "ok")
		end
	end
	return out
end
A.chamber = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	if sk.k == 0 then
		local tg = j.target(t + 0.15)
		hold(out, mem, "up", j.P < tg - 0.008)
		hold(out, mem, "down", j.P > tg + 0.008)
		if j.ear > 0.5 and every(mem, "e", t, 0.3) then
			tap(out, "eq")
		end
	elseif every(mem, "look", t, mix(sk, 0, 0.5)) then
		local tg = j.target(t)
		-- (the player aims inside the band the gauge shows: a slower player settles for more of it)
		local db = seg.tol * math.min(1.2, mix(sk, 0.1, 0.8))
		hold(out, mem, "up", j.P < tg - db)
		hold(out, mem, "down", j.P > tg + db)
		if j.ear > 0.9 then
			tap(out, "eq")
		end
	end
	return out
end
A.sauna = function(seg, j, t, M, mem, sk, rng)
	local out = {}
	local outT, inT = math.min(0.95, mix(sk, 0.8, 0.95)), math.min(0.6, mix(sk, 0.45, 0.6))
	if t < j.forcedUntil then
		return out
	end
	if j.inside and j.T > outT and every(mem, "d", t, 0.3) then
		tap(out, "door")
	elseif not j.inside and j.T < inT and every(mem, "d", t, 0.3) then
		tap(out, "door")
	end
	if sk.k == 0 and j.inside and j.T > 0.68 and t - j.lastSip >= 2.05 then
		tap(out, "sip")
	end
	return out
end
Bots.Policies = A

function Bots.Act(seg, j, t, M, mem, skill, rng)
	if skill.idle then
		return {}
	end
	local p = A[seg.j]
	if not p then
		return {}
	end
	return p(seg, j, t, M, mem, skill, rng)
end

return Bots
