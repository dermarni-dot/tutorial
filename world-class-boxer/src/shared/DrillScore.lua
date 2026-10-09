-- DrillScore: how a training drill is judged. Shared by the client, which plays the drill with these
-- judges, and the server, which replays the client's input stream through the same judges to score
-- the session (Main.server.lua finishActivity): the session quality is the server's number.
--
-- A drill is a list of segments (Training.DrillPlan draws them on the server - the combos, zones,
-- cues, beats and limits - and sends the plan with StartActivity). The client sends every input the
-- drill takes as { id, down, t } (t = seconds on the drill clock) and a marker "@" when a segment
-- starts. Each segment is a small state machine:
--   j.input(id, down, t)  an input; returns what happened (the client's feedback) or nil
--   j.advance(t)          the clock moved on (notes missed, a lift that went too far, rope passes)
--   j.finish(t)           the segment is over at t (whatever was not done by then is not done)
--   j.result()            the segment's numbers; DrillScore.Aggregate turns them into the 0..1 score
-- No Roblox services: it loads on both sides and in plain Luau tests.
local DrillScore = {}

local TAP_HOLD = 0.35 -- a press held this long is a hold (released on let-go); shorter is a tap toggle
local RT_FLOOR = 0.1 -- an answer faster than this jumped the cue: nobody reacts in under a tenth
local TWO_PI = 2 * math.pi
DrillScore.TAP_HOLD = TAP_HOLD
DrillScore.RT_FLOOR = RT_FLOOR
-- the most inputs one session keeps (an honest drill sends a few hundred at most)
DrillScore.MAX_EVENTS = 1200
-- the punches a power shot takes (POWER = a cross)
local NEEDLE_IDS = { power = true, jab = true, cross = true, leadhook = true, rearhook = true, uppercut = true, overhand = true }

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- the power-shot needle: 0 -> 1 -> 0 at `sweep` crossings a second
function DrillScore.NeedlePos(el, sweep)
	local u = (math.max(0, el) * sweep) % 2
	return u < 1 and u or 2 - u
end

local J = {}

-- a sequence (combinations, called mitt combos, shadow flows, named ladder drills): press the ids in
-- order before the limit; a wrong press is counted and the sequence waits for the right one
J.seq = function(seg, M)
	local ids, n = seg.ids, #seg.ids
	local endT = M + seg.limit
	local s = { idx = 1, wrong = 0, presses = 0, closed = false }
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		if t >= endT then
			s.closed = true
			return nil
		end
		s.presses += 1
		local at = s.idx
		if id == ids[at] then
			s.idx += 1
			if s.idx > n then
				s.doneAt = t
				s.closed = true
			end
			return { ok = true, idx = at }
		end
		s.wrong += 1
		return { ok = false, idx = at }
	end
	function s.advance(t)
		if t >= endT then
			s.closed = true
		end
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		local done = s.idx - 1
		local frac = (done == n and s.doneAt) and math.max(0, 1 - (s.doneAt - M) / seg.limit) or 0
		return { done = done, n = n, wrong = s.wrong, presses = s.presses, frac = frac, complete = done == n, time = s.doneAt and (s.doneAt - M) or nil }
	end
	return s
end

-- one cue: the first press inside the window answers it (too soon = jumped the cue)
J.cue = function(seg, M)
	local s = { closed = false }
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		if t - M >= seg.window then
			s.closed = true
			return nil
		end
		s.closed = true
		s.answered = true
		s.id = id
		s.rt = t - M
		s.early = s.rt < RT_FLOOR
		s.correct = id == seg.want and not s.early
		return { answered = true, correct = s.correct, early = s.early, rt = s.rt, id = id }
	end
	function s.advance(t)
		if t - M >= seg.window then
			s.closed = true
		end
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { answered = s.answered == true, correct = s.correct == true, early = s.early == true, rt = s.rt }
	end
	return s
end

-- slip & counter: the defensive move inside the window, then PUNCH inside the counter window
J.counter = function(seg, M)
	local s = { step = 1, closed = false }
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		if s.step == 1 then
			if t - M >= seg.window then
				s.closed = true
				return nil
			end
			if id == seg.want and t - M >= RT_FLOOR then
				s.step = 2
				s.shown2 = t
				return { step = 2, ok = true, id = id }
			end
			s.failed = true
			s.closed = true
			return { step = 1, ok = false, id = id, early = id == seg.want }
		end
		if t - s.shown2 >= seg.cw then
			s.closed = true
			return nil
		end
		s.closed = true
		if id == "punch" then
			s.rt = t - s.shown2
			s.step = 3
			return { step = 3, ok = true, id = id, rt = s.rt }
		end
		s.failed = true
		return { step = 2, ok = false, id = id }
	end
	function s.advance(t)
		if (s.step == 1 and t - M >= seg.window) or (s.step == 2 and t - s.shown2 >= seg.cw) then
			s.closed = true
		end
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { step = s.step, failed = s.failed == true, rt = s.rt }
	end
	return s
end

-- the power-shot needle: the first punch thrown is judged by where the needle is at that moment
J.needle = function(seg, M)
	local s = { closed = false }
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		if t - M >= seg.dur then
			s.closed = true
			return nil
		end
		if not NEEDLE_IDS[id] then
			return nil
		end
		s.closed = true
		local pos = DrillScore.NeedlePos(t - M, seg.sweep)
		local d, w = math.abs(pos - seg.c), seg.w
		local timing
		if d <= w then
			timing = 1 - 0.2 * d / w
		elseif d <= 2.5 * w then
			timing = 0.8 - 0.5 * (d - w) / (1.5 * w)
		else
			timing = math.max(0, 0.3 - (d - 2.5 * w) * 1.5)
		end
		s.thrown = { id = id, pos = pos, d = d, timing = timing }
		return s.thrown
	end
	function s.advance(t)
		if t - M >= seg.dur then
			s.closed = true
		end
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { thrown = s.thrown ~= nil, timing = s.thrown and s.thrown.timing or 0, d = s.thrown and s.thrown.d }
	end
	return s
end

-- the speed burst: alternating LEFT / RIGHT presses for seg.dur seconds
J.burst = function(seg, M)
	local s = { count = 0, closed = false }
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		if t - M >= seg.dur then
			s.closed = true
			return nil
		end
		if id ~= "L" and id ~= "R" then
			return nil
		end
		if id == s.last then
			return { alt = false, id = id }
		end
		s.last = id
		s.count += 1
		return { alt = true, id = id, count = s.count }
	end
	function s.advance(t)
		if t - M >= seg.dur then
			s.closed = true
		end
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { count = s.count }
	end
	return s
end

-- beats on two lanes (speed bag rhythm, russian twists): a press takes the nearest open note of its
-- lane inside hitW; |dt| under perfectW is perfect (the twists' "on the beat"), under goodW good. A
-- press with no note of its lane in reach is a stray (mashing both hands scores nothing)
J.notes = function(seg, M)
	local notes = {}
	for i, lane in ipairs(seg.lanes) do
		notes[i] = { t = M + seg.lead + (i - 1) * seg.interval, lane = lane }
	end
	local last = notes[#notes]
	local endT = (last and last.t or M) + seg.hitW
	local s = { notes = notes, perfect = 0, good = 0, off = 0, missed = 0, stray = 0, closed = false, endT = endT }
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		local best, bestDt
		for i, n in ipairs(notes) do
			if not n.judged and n.lane == id then
				local dt = t - n.t
				if math.abs(dt) < seg.hitW and (not best or math.abs(dt) < math.abs(bestDt)) then
					best, bestDt = i, dt
				end
			end
		end
		if not best then
			if t >= M + seg.lead - seg.hitW and t <= endT then
				s.stray += 1
				return { id = id, stray = true }
			end
			return { id = id }
		end
		notes[best].judged = true
		local a = math.abs(bestDt)
		local grade
		if a < seg.perfectW then
			grade = "perfect"
			s.perfect += 1
		elseif seg.goodW and a < seg.goodW then
			grade = "good"
			s.good += 1
		else
			grade = "off"
			s.off += 1
		end
		return { id = id, note = best, dt = bestDt, grade = grade }
	end
	-- the notes that went by unplayed (the client's MISS)
	function s.advance(t)
		local missed
		for i, n in ipairs(notes) do
			if not n.judged and t - n.t > seg.hitW then
				n.judged = true
				s.missed += 1
				missed = missed or {}
				table.insert(missed, i)
			end
		end
		if t >= endT then
			s.closed = true
		end
		return missed
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { perfect = s.perfect, good = s.good, off = s.off, stray = s.stray, count = #notes, hits = s.perfect + s.good }
	end
	return s
end

-- the tap-or-hold switch the hold drills share: a down starts (or, while on, ends) it; letting go of
-- a press held TAP_HOLD or longer ends it. Returns "on" / "off" when it flips.
local function tapHold(s, down, t)
	if down then
		if s.on then
			s.on = false
			s.at = nil
			return "off"
		end
		s.on = true
		s.at = t
		return "on"
	end
	local flip
	if s.at and t - s.at >= TAP_HOLD and s.on then
		s.on = false
		flip = "off"
	end
	s.at = nil
	return flip
end
DrillScore.TapHold = tapHold

-- one lift / slam: the bar rises at seg.speed per second from the press; let go inside [lo, lo + width];
-- at the top (f = 1) the rep fails
J.lift = function(seg, M)
	local s = { closed = false, f = 0 }
	local function release(t)
		s.closed = true
		local f = seg.speed * (t - s.holdStart)
		s.failed = f >= 1
		s.f = math.min(1, f)
		s.endT = s.failed and (s.holdStart + 1 / seg.speed) or t
	end
	function s.input(id, down, t)
		if s.closed or t < M then
			return nil
		end
		local flip = tapHold(s, down, t)
		if flip == "on" and not s.holdStart then
			s.holdStart = t
			return { holding = true }
		elseif flip == "off" and s.holdStart then
			release(t)
			return { holding = false }
		end
		return nil
	end
	-- the bar's height now (display) and the failure at the top
	function s.advance(t)
		if s.closed or not s.holdStart then
			return s.f
		end
		local f = seg.speed * (t - s.holdStart)
		if f >= 1 then
			s.closed = true
			s.failed = true
			s.f = 1
			s.endT = s.holdStart + 1 / seg.speed
		else
			s.f = math.max(0, f)
		end
		return s.f
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		local pressed = s.holdStart ~= nil and (s.failed or s.endT ~= nil)
		local f, lo, width = s.f, seg.lo, seg.width
		local q, verdict = 0, "none"
		if not pressed then
			q = 0
		elseif s.failed then
			q, verdict = seg.mode == "slam" and 0.35 or 0, "over"
		elseif f >= lo and f <= lo + width then
			local center = math.abs(f - (lo + width / 2)) / (width / 2)
			q, verdict = center < 0.35 and 1 or 0.85, center < 0.35 and "perfect" or "good"
		elseif f < lo then
			q, verdict = 0.45, "short"
		else
			q, verdict = seg.mode == "slam" and 0.4 or 0.3, "long"
		end
		return { pressed = pressed, f = f, failed = s.failed == true, q = q, verdict = verdict }
	end
	return s
end

-- the cardio pace: each press adds `kick` to the pace, which drains `decay` a second; the time spent
-- inside each interval's zone counts (integrated exactly, so both sides get the same number)
J.pace = function(seg, M)
	local phases, n = seg.phases, #seg.phases
	local dur = seg.duration
	local len = dur / n
	local s = { v = seg.v0, at = M, inZone = 0, closed = false }
	local function phaseOf(a)
		return math.min(n, math.floor((a - M) / len + 1e-7) + 1)
	end
	s.phaseOf = phaseOf
	local function integrate(a, b)
		local v = s.v
		while a < b - 1e-9 do
			local pi = phaseOf(a)
			local pe = pi >= n and b or math.min(b, M + pi * len)
			if pe <= a then
				pe = b
			end
			local lo, hi = phases[pi][1], phases[pi][2]
			-- v(x) = v - decay * (x - a) (until 0): inside [lo, hi] from a + (v - hi) / decay to a + (v - lo) / decay
			if v >= lo then
				local z0 = a + math.max(0, (v - hi) / seg.decay)
				local z1 = a + (v - lo) / seg.decay
				s.inZone += math.max(0, math.min(z1, pe) - math.max(z0, a))
			end
			v = math.max(0, v - seg.decay * (pe - a))
			a = pe
		end
		s.v = v
	end
	function s.advance(t)
		t = math.min(t, M + dur)
		if t > s.at then
			integrate(s.at, t)
			s.at = t
		end
		if t >= M + dur then
			s.closed = true
		end
		return s.v
	end
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		s.v = math.min(1, s.v + seg.kick)
		return { v = s.v }
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { inZone = s.inZone, duration = dur }
	end
	return s
end

-- guided breathing: hold (or tap on) through the inhale, release through the exhale; the time in
-- sync with the circle counts
J.breath = function(seg, M)
	local cycle = seg.inhale + seg.exhale
	local dur = seg.breaths * cycle
	local s = { clock = M, sync = 0, on = false, closed = false, duration = dur }
	-- time spent inhaling between the start and x seconds in
	local function inhaled(x)
		local full = math.floor(x / cycle)
		return full * seg.inhale + math.min(x - full * cycle, seg.inhale)
	end
	function s.inPhase(t)
		return ((t - M) % cycle) < seg.inhale
	end
	function s.advance(t)
		t = math.min(t, M + dur)
		if t > s.clock then
			local inh = inhaled(t - M) - inhaled(s.clock - M)
			s.sync += s.on and inh or ((t - s.clock) - inh)
			s.clock = t
		end
		if t >= M + dur then
			s.closed = true
		end
	end
	function s.input(id, down, t)
		if s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		local flip = tapHold(s, down, t)
		return flip and { holding = flip == "on" } or nil
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { sync = s.sync, duration = dur }
	end
	return s
end

-- the jump rope: the rope turns at omega (x1.9 on a double under) from overhead; it passes the feet at
-- every full turn and the pass is judged 0.1 s later on the presses from 0.32 s before to 0.1 s after
-- it (a press earlier than that, since the last pass, is a jump on nothing: mistimed - mashing the
-- button trips). A clean jump speeds the rope up; a trip stops it for 0.8 s and slows it.
J.rope = function(seg, M)
	local cues = seg.cues
	local s = { phase = math.pi, tau = M, omega = seg.omega, ci = 1, done = 0, clean = 0, doubles = 0, pressed = {}, tripped = M, closed = false }
	s.cue = cues[1] or "jump"
	local function rate()
		return s.omega * (s.cue == "double" and 1.9 or 1)
	end
	s.w = rate()
	-- judgements made since the last call (the client's feedback)
	local function judge(out)
		local pass = s.pending
		local J0 = pass + 0.1
		local count, good, early = 0, true, false
		local keep = {}
		for _, p in ipairs(s.pressed) do
			if p.t < pass - 0.32 then
				good, early = false, true
			elseif p.t <= pass + 0.1 then
				count += 1
				if s.passCue == "jump" or s.passCue == "double" then
					good = good and p.id == "jump"
				else
					good = good and p.id == s.passCue
				end
			end
			if p.t > J0 then
				table.insert(keep, p)
			end
		end
		s.pressed = keep
		s.phase += s.w * (J0 - s.tau)
		s.tau = J0
		s.done += 1
		local need = s.passCue == "double" and 2 or 1
		local clean = count >= need and good
		if clean then
			s.clean += 1
			if s.passCue == "double" then
				s.doubles += 1
			end
			s.omega = math.min(11.5, s.omega + 0.12)
		else
			s.tripped = J0 + 0.8
			s.omega = math.max(6, s.omega - 0.6)
			s.phase = math.pi
		end
		table.insert(out, { cue = s.passCue, clean = clean, count = count, early = early, t = J0 })
		s.pending = nil
		s.ci += 1
		s.cue = cues[s.ci] or "jump"
		s.w = rate()
	end
	function s.advance(t)
		local out = {}
		while s.done < seg.jumps do
			if s.tau < s.tripped then
				if t < s.tripped then
					break
				end
				s.tau = s.tripped
				local keep = {}
				for _, p in ipairs(s.pressed) do
					if p.t >= s.tripped then
						table.insert(keep, p)
					end
				end
				s.pressed = keep
			end
			if s.pending then
				if t < s.pending + 0.1 then
					break
				end
				judge(out)
			else
				local k = math.floor(s.phase / TWO_PI) + 1
				local tc = s.tau + (TWO_PI * k - s.phase) / s.w
				if t < tc then
					break
				end
				s.phase = TWO_PI * k
				s.tau = tc
				s.pending = tc
				s.passCue = s.cue
			end
		end
		if s.done >= seg.jumps then
			s.closed = true
		end
		return out
	end
	-- the rope's angle now (display)
	function s.angle(t)
		if t < s.tripped then
			return math.pi
		end
		return s.phase + s.w * (t - math.max(s.tau, s.tripped))
	end
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		local out = s.advance(t)
		if not s.closed and t >= s.tripped then
			table.insert(s.pressed, { id = id, t = t })
		end
		return out
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { clean = s.clean, done = s.done, doubles = s.doubles, jumps = seg.jumps }
	end
	return s
end

-- reaction lights (smart ladder): a pad lights after a short random gap; step to it (score by how
-- fast); a press with nothing lit does nothing
J.lights = function(seg, M)
	local ids, n = seg.ids, #seg.ids
	local s = { idx = 1, lit = false, nextLight = M + seg.first, score = 0, total = 0, correct = 0, closed = false }
	local function light(t)
		if not s.lit and s.idx <= n and t >= s.nextLight then
			s.lit = true
			s.lightAt = s.nextLight
			return true
		end
		return false
	end
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		if t - M >= seg.limit then
			s.closed = true
			return nil
		end
		light(t)
		if not s.lit then
			return nil
		end
		s.total += 1
		local rt = t - s.lightAt
		if id == ids[s.idx] and rt >= RT_FLOOR then
			s.correct += 1
			s.score += math.max(0.3, 1 - rt / 1.2)
			s.lit = false
			s.nextLight = t + (seg.delays[s.idx] or 0.2)
			s.idx += 1
			if s.idx > n then
				s.doneAt = t
				s.closed = true
			end
			return { ok = true, rt = rt }
		end
		return { ok = false, early = id == ids[s.idx] }
	end
	-- true when a pad lights up now (display)
	function s.advance(t)
		if t - M >= seg.limit then
			s.closed = true
			return false
		end
		return light(t)
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { score = s.score, total = s.total, correct = s.correct, complete = s.idx > n, n = n, time = s.doneAt and (s.doneAt - M) or seg.limit }
	end
	return s
end

DrillScore.Judges = J

-- the judge for one plan segment, started at M (drill clock)
function DrillScore.Judge(seg, M)
	local make = type(seg) == "table" and J[seg.j]
	if not make then
		return nil
	end
	return make(seg, M)
end

------------------------------------------------------------------------
-- Session score from the segments' results (missing = not played)
------------------------------------------------------------------------
local AGG = {}
AGG.combo = function(plan, res)
	local good, total, speed, combos, powerSum, shots, speedScore = 0, 0, 0, 0, 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "seq" then
			combos += 1
			total += #seg.ids
			if r then
				good += math.max(0, r.done - r.wrong * 0.5)
				speed += r.frac
			end
		elseif seg.j == "needle" then
			shots += 1
			powerSum += r and r.timing or 0
		elseif seg.j == "burst" and r then
			speedScore = clamp(r.count / seg.dur / seg.target, 0, 1)
		end
	end
	local comboScore = clamp(0.7 * good / math.max(1, total) + 0.3 * speed / math.max(1, combos) / 0.6, 0, 1)
	local powerScore = clamp(powerSum / math.max(1, shots), 0, 1)
	return 0.5 * comboScore + 0.25 * powerScore + 0.25 * speedScore
end
AGG.rhythm = function(plan, res)
	local sum = 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if r then
			sum += math.max(0, r.perfect + r.good * 0.65 - 0.5 * (r.stray or 0)) / math.max(1, #seg.lanes)
		end
	end
	return sum / math.max(1, #plan.segs)
end
AGG.reaction = function(plan, res)
	local s1, n1, s2, n2 = 0, 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "cue" then
			n1 += 1
			if r and r.correct then
				s1 += 1 - 0.4 * (r.rt / seg.window)
			end
		elseif seg.j == "counter" then
			n2 += 1
			if r and r.step == 3 and r.rt then
				s2 += 0.6 + 0.4 * clamp(1 - r.rt / seg.cw, 0, 1)
			elseif r and r.step == 2 then
				s2 += 0.3
			end
		end
	end
	return 0.55 * clamp(s1 / math.max(1, n1) / 0.85, 0, 1) + 0.45 * clamp(s2 / math.max(1, n2) / 0.9, 0, 1)
end
-- a called combination / a flow chain: how much of it, minus half a step per wrong press, plus speed
function DrillScore.SeqScore(r, partW, fastW, cap)
	if not r then
		return 0
	end
	local part = math.max(0, r.done - r.wrong * 0.5) / math.max(1, r.n)
	return math.min(cap, part * partW + r.frac * fastW)
end
AGG.mitts = function(plan, res)
	local sum = 0
	for i in ipairs(plan.segs) do
		sum += DrillScore.SeqScore(res[i], 0.8, 0.35, 1.15)
	end
	return sum / math.max(1, #plan.segs)
end
AGG.shadow = function(plan, res)
	local s1, n1, s2, n2 = 0, 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "cue" then
			n1 += 1
			if r and r.correct then
				s1 += 1 - 0.35 * r.rt / seg.window
			end
		else
			n2 += 1
			s2 += DrillScore.SeqScore(r, 0.8, 0.4, 1)
		end
	end
	return 0.5 * clamp(s1 / math.max(1, n1) / 0.85, 0, 1) + 0.5 * clamp(s2 / math.max(1, n2), 0, 1)
end
AGG.reps = function(plan, res)
	local sum = 0
	for i in ipairs(plan.segs) do
		sum += res[i] and res[i].q or 0
	end
	return sum / math.max(1, #plan.segs)
end
AGG.medball = function(plan, res)
	local slam, slams, twist = 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "lift" then
			slams += 1
			slam += r and r.q or 0
		elseif seg.j == "notes" and r then
			twist = math.max(0, r.perfect - 0.5 * (r.stray or 0)) / math.max(1, #seg.lanes)
		end
	end
	return 0.55 * slam / math.max(1, slams) + 0.45 * twist
end
AGG.pace = function(plan, res)
	local r, seg = res[1], plan.segs[1]
	return r and clamp(r.inZone / seg.duration / 0.85, 0, 1) or 0
end
AGG.ladder = function(plan, res)
	local score, total, completed = 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if r then
			if seg.j == "lights" then
				score += r.score
				total += r.total
			else
				score += r.done
				total += r.presses
			end
			if r.complete then
				completed += 1
			end
		end
	end
	return clamp(score / math.max(1, total), 0, 1) * (0.5 + 0.5 * completed / math.max(1, #plan.segs))
end
AGG.rope = function(plan, res)
	local clean, jumps = 0, 0
	for i, seg in ipairs(plan.segs) do
		jumps += seg.jumps
		clean += res[i] and res[i].clean or 0
	end
	return clean / math.max(1, jumps)
end
AGG.hold = function(plan, res)
	local r, seg = res[1], plan.segs[1]
	local dur = seg and seg.breaths * (seg.inhale + seg.exhale) or 1
	return r and r.sync / dur or 0
end

-- the session's 0..1 score from the segments' results (results[i] for plan.segs[i])
function DrillScore.Aggregate(plan, results)
	local agg = type(plan) == "table" and AGG[plan.kind]
	if not agg or type(plan.segs) ~= "table" then
		return 0
	end
	local ok, v = pcall(agg, plan, results or {})
	if not ok or type(v) ~= "number" or v ~= v then
		return 0
	end
	return clamp(v, 0, 1)
end

-- the server's replay: the recorded stream (in time order; "@" starts the next segment) through the
-- plan's judges up to tEnd (the drill clock when the session was handed in). Returns the score and
-- the results.
function DrillScore.Replay(plan, events, tEnd)
	if type(plan) ~= "table" or type(plan.segs) ~= "table" then
		return 0, {}
	end
	local results, i, judge = {}, 0, nil
	local function close(t)
		if judge then
			judge.finish(t)
			results[i] = judge.result()
			judge = nil
		end
	end
	for _, e in ipairs(events or {}) do
		if e.t > tEnd then
			break
		end
		if e.id == "@" then
			close(e.t)
			i += 1
			if not plan.segs[i] then
				break
			end
			judge = DrillScore.Judge(plan.segs[i], e.t)
		elseif judge then
			judge.input(e.id, e.down, e.t)
		end
	end
	close(tEnd)
	return DrillScore.Aggregate(plan, results), results
end

return DrillScore
