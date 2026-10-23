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
--   j.endsAt()            when the segment was over for the player (the client moves on then), nil
--                         while that still depends on inputs to come
--   j.result()            the segment's numbers; DrillScore.Aggregate turns them into the 0..1 score
-- No Roblox services: it loads on both sides and in plain Luau tests.
local DrillScore = {}
-- the exercise-specific workouts' judges and plans (installed at the end of this file)
local Workouts = require(script.Parent:WaitForChild("DrillWorkouts"))

local TAP_HOLD = 0.35 -- a press held this long is a hold (released on let-go); shorter is a tap toggle
local RT_FLOOR = 0.1 -- an answer faster than this jumped the cue: nobody reacts in under a tenth
local TWO_PI = 2 * math.pi
DrillScore.TAP_HOLD = TAP_HOLD
DrillScore.BOUNCE = 0.2
DrillScore.RT_FLOOR = RT_FLOOR
-- the most inputs one session keeps (an honest drill sends a few hundred at most)
DrillScore.MAX_EVENTS = 1200
-- the drill's pacing: what the client waits between one segment's end and the next one's start (the
-- round banners, the rests, the beat after each combination / rep). Activities.lua waits exactly these,
-- Training.DrillPlan writes each segment's sum into seg.gap and the replay holds the stream to it.
-- (kept short on purpose: a workout is 20-40 s of input, the banners flash and the breathers are a
-- second - the dead time between reps and sets is what made the sessions feel slow)
DrillScore.WAIT = {
	intro = 0.6, -- the first round's banner (ctx.round)
	round = 0.5, -- a later round's / set's banner
	rest = 1.0, -- the breather between rounds and sets (ctx.rest)
	restLong = 1.2, -- the mitt coach's breather
	restShort = 1.0, -- the rope's and the ladder's breather
	combo = 0.4, -- after a heavy bag combination
	shot = 0.5, -- after a power shot
	react = 0.25, -- after a double-end cue
	counter = 0.3, -- after a slip & counter
	mitt = 0.45, -- after a called mitt combination
	move = 0.2, -- after a shadow boxing cue
	flow = 0.4, -- after a shadow boxing flow
	lower = 0.3, -- lowering the weight after a rep
	rerack = 0.15, -- the beat before the next rep
	slam = 0.2, -- the ball driven down after a slam
	catch = 0.25, -- the catch off the bounce
	ladder = 0.4, -- after a ladder drill
	rebound = 0.3, -- after a double-end rebound
	steps = 0.3, -- after the shadow boxing footwork pattern
}
-- an "@" may come this much before the plan's pacing allows (clock rounding); earlier, the segment
-- starts at the allowed time and what the client did before it counts for nothing
DrillScore.GAP_SLACK = 0.05
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

-- a sequence (combinations, shadow flows): press the ids in order before the limit; a wrong press is
-- counted and the sequence waits for the right one. With seg.beat (the heavy bag's rhythm combos) every
-- hit after the first is also timed against the one before it: a beat apart is on the beat (perfect
-- inside 30% of it, good inside 60%), the rest is off (the chain still goes on: nothing resets).
J.seq = function(seg, M)
	local ids, n = seg.ids, #seg.ids
	local endT = M + seg.limit
	local beat = tonumber(seg.beat)
	local s = { idx = 1, wrong = 0, presses = 0, perfectHits = 0, goodHits = 0, closed = false }
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		if t >= endT then
			s.closed = true
			return nil
		end
		local at = s.idx
		-- forgiving input: the punch just landed pressed again within BOUNCE (a key bounce, a double tap on
		-- a touch button) is not a wrong press
		if id ~= ids[at] and s.lastHit and id == ids[at - 1] and t - s.lastHit <= DrillScore.BOUNCE then
			return nil
		end
		s.presses += 1
		if id == ids[at] then
			s.idx += 1
			local tempo
			if beat and s.lastHit then
				local e = math.abs(t - s.lastHit - beat)
				tempo = e <= beat * 0.3 and "perfect" or (e <= beat * 0.6 and "good" or "off")
				if tempo == "perfect" then
					s.perfectHits += 1
				elseif tempo == "good" then
					s.goodHits += 1
				end
			end
			s.lastHit = t
			if s.idx > n then
				s.doneAt = t
				s.closed = true
			end
			return { ok = true, idx = at, tempo = tempo }
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
		-- the share of the timed hits on the beat (nil without a beat)
		local beatQ = beat and n > 1 and (s.perfectHits + 0.75 * s.goodHits) / (n - 1) or nil
		return { done = done, n = n, wrong = s.wrong, presses = s.presses, frac = frac, complete = done == n, time = s.doneAt and (s.doneAt - M) or nil,
			beatQ = beatQ, perfectHits = s.perfectHits, goodHits = s.goodHits }
	end
	function s.endsAt()
		return s.doneAt or endT
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
	function s.endsAt()
		return M + (s.answered and s.rt or seg.window)
	end
	return s
end

-- call & response (the mitts): the coach calls the moves one at a time - call k comes at
-- M + lead + (k - 1) * call and stays open for `window` - and each is answered with its move inside its
-- window (perfect inside half of it, good after). A FEINT call (id "feint") is one you must NOT bite on:
-- any press inside its window is bitten, nothing is a feint held. A wrong move answers (and spends)
-- the call; a press with no call open is a stray. Nothing resets: a missed call is just a missed call.
J.call = function(seg, M)
	local ids, n = seg.ids, #seg.ids
	local calls = {}
	for k, id in ipairs(ids) do
		calls[k] = { id = id, t = M + seg.lead + (k - 1) * seg.call, feint = id == "feint" }
	end
	local last = calls[n]
	local endT = (last and last.t or M) + seg.window
	local s = { calls = calls, closed = false, perfect = 0, good = 0, wrong = 0, missed = 0, held = 0, bitten = 0, stray = 0, feints = 0, endT = endT }
	for _, c in ipairs(calls) do
		if c.feint then
			s.feints += 1
		end
	end
	local function resolve(c, how, at)
		c.judged, c.how, c.at = true, how, at
		s[how] += 1
	end
	-- the calls whose window went by unanswered (the client's MISS / FEINT HELD)
	function s.advance(t)
		local out
		for k, c in ipairs(calls) do
			if not c.judged and t - c.t >= seg.window then
				resolve(c, c.feint and "held" or "missed", c.t + seg.window)
				out = out or {}
				table.insert(out, { k = k, how = c.how })
			end
		end
		if t >= endT then
			s.closed = true
		end
		return out
	end
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		-- the earliest open call for this move; failing that, the earliest open call (windows may overlap:
		-- the move of the next call, thrown while a missed one is still open, answers the next one)
		local c, k, first, firstK
		for i, cc in ipairs(calls) do
			if not cc.judged and t >= cc.t and t - cc.t < seg.window then
				if not first then
					first, firstK = cc, i
				end
				if cc.id == id then
					c, k = cc, i
					break
				end
			end
		end
		if not c then
			c, k = first, firstK
		end
		if not c then
			s.stray += 1
			return { stray = true, id = id }
		end
		local rt = t - c.t
		if c.feint then
			resolve(c, "bitten", t)
			return { k = k, how = "bitten", id = id, rt = rt }
		elseif id == c.id then
			local how = rt <= seg.window * 0.5 and "perfect" or "good"
			resolve(c, how, t)
			return { k = k, how = how, id = id, rt = rt }
		end
		resolve(c, "wrong", t)
		return { k = k, how = "wrong", id = id, rt = rt }
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { n = n, real = n - s.feints, perfect = s.perfect, good = s.good, wrong = s.wrong, missed = s.missed,
			feints = s.feints, held = s.held, bitten = s.bitten, stray = s.stray }
	end
	-- the last call resolved (answered, or its window gone)
	function s.endsAt()
		local e = M
		for _, c in ipairs(calls) do
			e = math.max(e, c.at or (c.t + seg.window))
		end
		return e
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
			s.endT = t
			return { step = 1, ok = false, id = id, early = id == seg.want }
		end
		if t - s.shown2 >= seg.cw then
			s.closed = true
			return nil
		end
		s.closed = true
		s.endT = t
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
	function s.endsAt()
		return s.endT or (s.step == 2 and s.shown2 + seg.cw) or (M + seg.window)
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
		s.thrownAt = t
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
	function s.endsAt()
		return s.thrownAt or (M + seg.dur)
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
	function s.endsAt()
		return M + seg.dur
	end
	return s
end

-- beats on two lanes (speed bag rhythm, russian twists): a press takes the nearest open note of its
-- lane inside hitW; |dt| under perfectW is perfect (the twists' "on the beat"), under goodW good. A
-- press with no note of its lane in reach is a stray (mashing both hands scores nothing)
-- With seg.accel (< 1) the tempo picks up: each gap is the last one times accel, never under
-- seg.minInterval (the speed bag's accelerating rhythm, the ladder's quickening feet).
J.notes = function(seg, M)
	local notes = {}
	local accel = tonumber(seg.accel) or 1
	local minIv = tonumber(seg.minInterval) or seg.interval * 0.5
	local at, iv = M + seg.lead, seg.interval
	for i, lane in ipairs(seg.lanes) do
		notes[i] = { t = at, lane = lane }
		at += iv
		iv = math.max(minIv, iv * accel)
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
		notes[best].at = t
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
				n.at = n.t + seg.hitW
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
	-- the client moves on once every note is played or gone by
	function s.endsAt()
		local e = M
		for _, n in ipairs(notes) do
			e = math.max(e, n.at or (n.t + seg.hitW))
		end
		return e
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
		-- (a rep nobody starts closes after seg.wait: an idle player still reaches the end of the set)
		if not s.closed and not s.holdStart and seg.wait and t - M >= seg.wait then
			s.closed = true
			s.endT = M + seg.wait
		end
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
		-- (a rep that misses the zone still counts for something: failing a rep costs little)
		if not pressed then
			q = 0
		elseif s.failed then
			q, verdict = seg.mode == "slam" and 0.4 or 0.25, "over"
		elseif f >= lo and f <= lo + width then
			local center = math.abs(f - (lo + width / 2)) / (width / 2)
			q, verdict = center < 0.5 and 1 or 0.85, center < 0.5 and "perfect" or "good"
		elseif f < lo then
			q, verdict = 0.55, "short"
		else
			q, verdict = seg.mode == "slam" and 0.5 or 0.45, "long"
		end
		return { pressed = pressed, f = f, failed = s.failed == true, q = q, verdict = verdict }
	end
	-- (a rep waits for its press: nobody knows its end before that)
	function s.endsAt()
		return s.endT or (s.holdStart and s.holdStart + 1 / seg.speed) or (seg.wait and M + seg.wait) or nil
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
	function s.endsAt()
		return M + dur
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
	function s.endsAt()
		return M + dur
	end
	return s
end

-- the jump rope: the rope turns at omega (x1.7 on a double under) from overhead; it passes the feet at
-- every full turn and the pass is judged seg.late (0.12 s) later on the jumps from seg.early (0.48 s)
-- before to seg.late after it. HOLD AND RELEASE: JUMP held is the crouch, its RELEASE is the jump (a
-- quick tap is a small hop and counts too); a DOUBLE UNDER is one jump loaded longer - JUMP held at
-- least seg.charge seconds before the release (the charge ring fills). The boxer skip's foot calls are
-- presses of the called foot. One jump earlier than the window since the last pass is forgiven (a
-- nervous hop); two or more are jumping on nothing: mistimed - mashing the button trips. A clean jump
-- speeds the rope up; a trip stops it for 0.45 s and slows it a little (the rhythm is lost, not the
-- progress: nothing resets). A clean jump released within seg.perfW of the pass is SWEET (perfect).
local ROPE_EARLY, ROPE_LATE, ROPE_TRIP, ROPE_CHARGE, ROPE_DOUBLE = 0.48, 0.12, 0.45, 0.26, 1.7
DrillScore.ROPE_CHARGE = ROPE_CHARGE
J.rope = function(seg, M)
	local cues = seg.cues
	local early, late, charge = seg.early or ROPE_EARLY, seg.late or ROPE_LATE, seg.charge or ROPE_CHARGE
	local perfW = seg.perfW or 0.08
	local s = { phase = math.pi, tau = M, omega = seg.omega, ci = 1, done = 0, clean = 0, sweet = 0, doubles = 0, pressed = {}, tripped = M, closed = false, charge = charge }
	s.cue = cues[1] or "jump"
	local function rate()
		return s.omega * (s.cue == "double" and ROPE_DOUBLE or 1)
	end
	s.w = rate()
	-- judgements made since the last call (the client's feedback)
	local function judge(out)
		local pass = s.pending
		local J0 = pass + late
		local count, good, wasEarly, earlyN, loaded, dt = 0, true, false, 0, false, math.huge
		local keep = {}
		for _, p in ipairs(s.pressed) do
			if p.t < pass - early then
				earlyN += 1
				if earlyN >= 2 then
					good, wasEarly = false, true
				end
			elseif p.t <= pass + late then
				count += 1
				if math.abs(p.t - pass) < math.abs(dt) then
					dt = p.t - pass
				end
				if s.passCue == "jump" or s.passCue == "double" then
					good = good and p.id == "jump"
					loaded = loaded or (p.held or 0) >= charge - 1e-6
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
		-- (a double under is one jump, loaded: the hold before its release reached the charge)
		local clean = count >= 1 and good and (s.passCue ~= "double" or loaded)
		local sweet = clean and math.abs(dt) <= perfW
		if clean then
			s.clean += 1
			if sweet then
				s.sweet += 1
			end
			if s.passCue == "double" then
				s.doubles += 1
			end
			s.omega = math.min(11.5, s.omega + 0.12)
		else
			s.tripped = J0 + ROPE_TRIP
			s.omega = math.max(6, s.omega - 0.35)
			s.phase = math.pi
		end
		table.insert(out, { cue = s.passCue, clean = clean, count = count, early = wasEarly, short = s.passCue == "double" and count >= 1 and not loaded, sweet = sweet, dt = clean and dt or nil, t = J0 })
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
				if t < s.pending + late then
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
	-- how long JUMP has been held (the crouch / the double under's charge), 0 when it is up
	function s.loading(t)
		return s.downAt and math.max(0, t - s.downAt) or 0
	end
	function s.input(id, down, t)
		if s.closed or t < M then
			return nil
		end
		local out = s.advance(t)
		if s.closed then
			return out
		end
		if id == "jump" then
			-- the press crouches, the release jumps (a press during a trip loads nothing)
			if down then
				s.downAt = t >= s.tripped and t or nil
			elseif s.downAt then
				table.insert(s.pressed, { id = id, t = t, held = t - s.downAt })
				s.downAt = nil
			end
		elseif down and t >= s.tripped then
			table.insert(s.pressed, { id = id, t = t })
		end
		return out
	end
	function s.finish(t)
		s.advance(t)
		s.closed = true
	end
	function s.result()
		return { clean = s.clean, sweet = s.sweet, done = s.done, doubles = s.doubles, jumps = seg.jumps }
	end
	-- the last jump judged (s.tau moves to each judgement)
	function s.endsAt()
		return s.done >= seg.jumps and s.tau or nil
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
			-- (a human half-second is a good step; only a real hesitation costs)
			s.score += math.max(0.4, 1 - math.max(0, rt - 0.25) / 1.4)
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
	function s.endsAt()
		return s.doneAt or (M + seg.limit)
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
-- a wrong press costs this much of a step (the chain itself never resets)
DrillScore.WRONG_COST = 0.35
AGG.combo = function(plan, res)
	local good, total, rhythm, combos, powerSum, shots, speedScore = 0, 0, 0, 0, 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "seq" then
			combos += 1
			total += #seg.ids
			if r then
				good += math.max(0, r.done - r.wrong * DrillScore.WRONG_COST)
				-- the rhythm of the hits (a combo without a beat: how quickly it came)
				rhythm += r.beatQ or clamp(r.frac / 0.6, 0, 1)
			end
		elseif seg.j == "needle" then
			shots += 1
			powerSum += r and r.timing or 0
		elseif seg.j == "burst" and r then
			speedScore = clamp(r.count / seg.dur / seg.target, 0, 1)
		end
	end
	local comboScore = clamp(0.7 * good / math.max(1, total) + 0.3 * rhythm / math.max(1, combos), 0, 1)
	local powerScore = clamp(powerSum / math.max(1, shots), 0, 1)
	return 0.5 * comboScore + 0.25 * powerScore + 0.25 * speedScore
end
-- a round of notes: perfect 1, good 0.75, a stray press -0.35 (mashing both hands scores nothing)
local function notesShare(seg, r)
	if not r then
		return 0
	end
	return clamp((r.perfect + r.good * 0.75 - 0.35 * (r.stray or 0)) / math.max(1, #seg.lanes), 0, 1)
end
DrillScore.NotesShare = notesShare
AGG.rhythm = function(plan, res)
	local sum = 0
	for i, seg in ipairs(plan.segs) do
		sum += notesShare(seg, res[i])
	end
	return sum / math.max(1, #plan.segs)
end
AGG.reaction = function(plan, res)
	local s1, n1, s2, n2, s3, n3 = 0, 0, 0, 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "rebound" then
			n3 += 1
			s3 += Workouts.ReboundScore(seg, r)
		elseif seg.j == "cue" then
			n1 += 1
			if r and r.correct then
				s1 += 1 - 0.3 * (r.rt / seg.window)
			end
		elseif seg.j == "counter" then
			n2 += 1
			if r and r.step == 3 and r.rt then
				s2 += 0.7 + 0.3 * clamp(1 - r.rt / seg.cw, 0, 1)
			elseif r and r.step == 2 then
				s2 += 0.4
			end
		end
	end
	local react, counter = clamp(s1 / math.max(1, n1) / 0.9, 0, 1), clamp(s2 / math.max(1, n2) / 0.9, 0, 1)
	if n3 == 0 then
		return 0.55 * react + 0.45 * counter
	end
	return 0.35 * react + 0.3 * counter + 0.35 * clamp(s3 / n3 / 0.9, 0, 1)
end
-- a called combination / a flow chain: how much of it, minus half a step per wrong press, plus speed
function DrillScore.SeqScore(r, partW, fastW, cap)
	if not r then
		return 0
	end
	local part = math.max(0, r.done - r.wrong * DrillScore.WRONG_COST) / math.max(1, r.n)
	return math.min(cap, part * partW + r.frac * fastW)
end
-- a called combination (J.call): the answers (perfect 1, good 0.85, a wrong move a quarter) over the real
-- calls, times the feints held (biting on half of them costs a quarter)
function DrillScore.CallScore(r)
	if not r then
		return 0
	end
	local answers = (r.perfect + 0.85 * r.good + 0.25 * r.wrong) / math.max(1, r.real)
	local feint = 1 - 0.5 * r.bitten / math.max(1, r.feints)
	return clamp(answers * feint - 0.1 * (r.stray or 0) / math.max(1, r.real), 0, 1)
end
AGG.mitts = function(plan, res)
	local sum = 0
	for i, seg in ipairs(plan.segs) do
		if seg.j == "call" then
			sum += DrillScore.CallScore(res[i])
		else
			sum += DrillScore.SeqScore(res[i], 0.8, 0.35, 1.15)
		end
	end
	return sum / math.max(1, #plan.segs)
end
AGG.shadow = function(plan, res)
	local s1, n1, s2, n2, s3, n3 = 0, 0, 0, 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "notes" then
			n3 += 1
			s3 += notesShare(seg, r)
		elseif seg.j == "cue" then
			n1 += 1
			if r and r.correct then
				s1 += 1 - 0.3 * r.rt / seg.window
			end
		else
			n2 += 1
			s2 += DrillScore.SeqScore(r, 0.8, 0.4, 1)
		end
	end
	local moves, flows = clamp(s1 / math.max(1, n1) / 0.9, 0, 1), clamp(s2 / math.max(1, n2), 0, 1)
	if n3 == 0 then
		return 0.5 * moves + 0.5 * flows
	end
	return 0.35 * moves + 0.3 * clamp(s3 / n3 / 0.9, 0, 1) + 0.35 * flows
end
AGG.reps = function(plan, res)
	local sum = 0
	for i in ipairs(plan.segs) do
		sum += res[i] and res[i].q or 0
	end
	return sum / math.max(1, #plan.segs)
end
AGG.medball = function(plan, res)
	local slam, slams, core = 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "lift" then
			slams += 1
			slam += r and r.q or 0
		elseif seg.j == "notes" then
			core = notesShare(seg, r)
		elseif seg.j == "wobble" and r then
			-- the plank: the time held in the green (Workouts.TIMED_FULL of it is full marks), a slip costs a tenth
			core = clamp(r.acc / math.max(0.1, r.duration) / Workouts.TIMED_FULL - 0.1 * (r.lost or 0), 0, 1)
		end
	end
	return 0.55 * slam / math.max(1, slams) + 0.45 * core
end
-- this share of the cardio session spent in the zone is full marks (Activities grades each interval
-- on the same scale for the live QUALITY tile)
DrillScore.PACE_FULL = 0.85
AGG.pace = function(plan, res)
	local r, seg = res[1], plan.segs[1]
	return r and clamp(r.inZone / seg.duration / DrillScore.PACE_FULL, 0, 1) or 0
end
AGG.ladder = function(plan, res)
	local score, total, completed = 0, 0, 0
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if r then
			if seg.j == "lights" then
				score += r.score
				total += r.total
				if r.complete then
					completed += 1
				end
			elseif seg.j == "notes" then
				-- the stepped pattern: the steps on the beat; a drill with most of its steps is run through
				score += math.max(0, r.perfect + 0.8 * r.good - 0.35 * (r.stray or 0))
				total += r.count
				if r.hits >= 0.6 * r.count then
					completed += 1
				end
			else
				score += r.done
				total += r.presses
				if r.complete then
					completed += 1
				end
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
-- plan's judges up to tEnd (the drill clock when the session was handed in). The plan's pacing holds:
-- segment i starts no sooner than seg.gap after segment i - 1 was over (the drill's start for the
-- first) - an earlier "@" starts it at that moment instead, so a stream that skips the rounds' banners,
-- the rests or the cues' lead-ins finds its inputs before the segment began (they count for nothing).
-- Returns the score, the results and the pacing ({ late = segments started early, lost = their seconds }).
function DrillScore.Replay(plan, events, tEnd)
	local pacing = { late = 0, lost = 0 }
	if type(plan) ~= "table" or type(plan.segs) ~= "table" then
		return 0, {}, pacing
	end
	local results, i, judge = {}, 0, nil
	-- the segment is over at t: when it ended for the player (never later than t, the next marker)
	local function close(t)
		if not judge then
			return t
		end
		judge.finish(t)
		results[i] = judge.result()
		local e = judge.endsAt()
		judge = nil
		return (type(e) == "number" and e == e) and math.min(e, t) or t
	end
	local over = 0
	for _, e in ipairs(events or {}) do
		if e.t > tEnd then
			break
		end
		if e.id == "@" then
			if i > 0 then
				over = close(e.t)
			end
			i += 1
			local seg = plan.segs[i]
			if not seg then
				break
			end
			local gap = tonumber(seg.gap) or 0
			local M = e.t
			local allowed = over + gap - DrillScore.GAP_SLACK
			if M < allowed then
				pacing.late += 1
				pacing.lost += allowed - M
				M = allowed
			end
			judge = DrillScore.Judge(seg, M)
		elseif judge then
			judge.input(e.id, e.down, e.t)
		end
	end
	close(tEnd)
	return DrillScore.Aggregate(plan, results), results, pacing
end

-- the least time the plan takes played perfectly: every gap plus each segment's shortest honest length
-- (Main.server.lua: a session handed in under 80% of it is too quick to count)
function DrillScore.MinTime(plan)
	local total = 0
	for _, seg in ipairs(type(plan) == "table" and type(plan.segs) == "table" and plan.segs or {}) do
		total += tonumber(seg.gap) or 0
		local j = seg.j
		if j == "cue" then
			total += RT_FLOOR
		elseif j == "counter" then
			total += 2 * RT_FLOOR
		elseif j == "burst" then
			total += seg.dur
		elseif j == "notes" then
			local notes = J.notes(seg, 0).notes
			total += math.max(0, (notes[#notes] and notes[#notes].t or 0) - seg.hitW)
		elseif j == "call" then
			total += seg.lead + (#seg.ids - 1) * seg.call + RT_FLOOR
		elseif j == "lift" then
			total += seg.lo / seg.speed
		elseif j == "pace" then
			total += seg.duration
		elseif j == "breath" then
			total += seg.breaths * (seg.inhale + seg.exhale)
		elseif j == "rope" then
			total += seg.jumps * TWO_PI / (11.5 * 1.9) -- the rope's top speed, every pass a double under
		elseif j == "lights" then
			total += seg.first + #seg.ids * RT_FLOOR
			for k = 1, #seg.ids - 1 do
				total += seg.delays[k] or 0
			end
		else
			total += Workouts.MinTime(seg) or 0
		end
	end
	return total
end

DrillScore.Workouts = Workouts
Workouts.Install(DrillScore, J, AGG)

return DrillScore
