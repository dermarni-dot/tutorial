-- DrillWorkouts: the judges and plans of the exercise-specific workouts (the weight room, the cardio
-- machines, the recovery stations) and the extra boxing rounds (double-end rebounds, shadow footwork).
-- DrillScore installs them next to its own judges (DrillScore.Install at the end of DrillScore.lua);
-- Training.DrillPlan draws their plans with DrillWorkouts.Plan. Like DrillScore: no Roblox services,
-- the same code on the client (which plays the drill) and on the server (which replays the inputs).
--
-- The continuous drills (the bar's tilt, a swing, a cadence, a cold meter...) run on a fixed step of
-- TICK seconds counted from the segment's start: an input at t first brings the state up to t, then
-- changes what is held. The client's frames and the server's replay call advance() at different
-- moments; the fixed steps make both land on the same numbers.
--
-- Every judge closes on its own (a rep nobody starts closes after seg.wait), so an idle player always
-- reaches the end of the session.
local W = {}

local TICK = 1 / 30
W.TICK = TICK
-- a tap on a hold-to-correct control (the bar's sides, the chamber's valves) still counts for this long
local NUDGE = 0.15
W.NUDGE = NUDGE
local RT_FLOOR = 0.1

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- the fixed-step clock: s.advance(t) runs step(T) for every tick M + k * TICK <= t (until closed)
local function stepper(s, M, step)
	s.k = 0
	function s.advance(t)
		if t ~= t then
			return s
		end
		local n = math.floor((t - M) / TICK + 1e-6)
		while s.k < n and not s.closed do
			s.k += 1
			step(M + s.k * TICK)
		end
		return s
	end
end

-- a hold with a minimum length (a tap or a stick flick still nudges): held(id, T)
local function holds(s)
	s.hold, s.holdUntil = {}, {}
	function s.held(id, T)
		return s.hold[id] == true or (s.holdUntil[id] or -1) >= T
	end
	function s.setHold(id, down, t)
		s.hold[id] = down == true
		if down then
			s.holdUntil[id] = t + NUDGE
		end
	end
end

-- the power-shot style needle (0 -> 1 -> 0 at `sweep` crossings a second)
local function needle(el, sweep)
	local u = (math.max(0, el) * sweep) % 2
	return u < 1 and u or 2 - u
end
W.Needle = needle

local function finishOf(s)
	return function(t)
		s.advance(t)
		s.closed = true
	end
end

------------------------------------------------------------------------
-- Judges
------------------------------------------------------------------------
local J = {}

-- BENCH PRESS: PRESS (tap or hold) drives the bar up; the bar tilts on its own (seg.drift: two sine
-- waves and a weak side) and LEFT / RIGHT push that end up. x > 0: the LEFT end dips. Tilted past
-- tiltMax the spotter grabs it; SPOT asks for the spotter (an assisted rep); a rep that stalls for
-- seg.limit is taken by the spotter too. Released mid-rep, the bar sinks back.
J.bench = function(seg, M, TapHold)
	local s = { closed = false, p = 0, x = 0, press = {}, sum = 0, n = 0, maxX = 0 }
	holds(s)
	local d = seg.drift
	function s.driftAt(el)
		return d[1] * math.sin(d[2] * el + d[3]) + d[4] * math.sin(d[5] * el + d[6]) + (seg.bias or 0)
	end
	local function close(T, v)
		s.closed, s.endT, s.verdict = true, T, v
	end
	stepper(s, M, function(T)
		if not s.started then
			if T - M >= seg.wait then
				close(T, "none")
			end
			return
		end
		local stick = s.p >= seg.stickLo and s.p <= seg.stickHi
		if s.press.on then
			local v = seg.speed * (stick and seg.stickMult or 1) * (1 - 0.5 * math.min(1, math.abs(s.x) / seg.tiltMax))
			s.p = math.min(1, s.p + v * TICK)
		else
			s.p = math.max(0, s.p - seg.sink * TICK)
		end
		s.x += s.driftAt(T - s.startT) * TICK
		if s.held("L", T) then
			s.x -= seg.corr * TICK
		end
		if s.held("R", T) then
			s.x += seg.corr * TICK
		end
		local ax = math.abs(s.x)
		s.sum += ax
		s.n += 1
		s.maxX = math.max(s.maxX, ax)
		if ax >= seg.tiltMax then
			close(T, "tilted")
		elseif s.p >= 1 then
			close(T, "lockout")
		elseif T - s.startT >= seg.limit then
			close(T, "stalled")
		end
	end)
	function s.input(id, down, t)
		if s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if id == "press" then
			local flip = TapHold(s.press, down, t)
			if flip == "on" and not s.started then
				s.started, s.startT = true, t
			end
			return flip and { press = flip == "on" } or nil
		elseif id == "L" or id == "R" then
			s.setHold(id, down, t)
		elseif id == "spot" and down and s.started then
			close(t, "assisted")
			return { spot = true }
		end
		return nil
	end
	s.finish = finishOf(s)
	function s.result()
		local v = s.verdict or (s.started and "stalled" or "none")
		local q = 0
		local avg = s.sum / math.max(1, s.n)
		if v == "lockout" then
			-- (a level bar: the mean tilt under 0.12 is full marks, 0.47 the floor of a locked-out rep)
			q = clamp(1 - math.max(0, avg - 0.12) / 0.35, 0.5, 1)
			if s.maxX > 0.85 * seg.tiltMax then
				q *= 0.9
			end
		elseif v == "assisted" then
			q = 0.45 + 0.2 * s.p
		elseif v == "tilted" then
			q = 0.3
		elseif v == "stalled" then
			q = 0.25 + 0.2 * s.p
		end
		return { q = q, verdict = v, p = s.p, avgTilt = avg, maxTilt = s.maxX, pressed = s.started == true }
	end
	function s.endsAt()
		return s.endT or (not s.started and (M + seg.wait)) or nil
	end
	s.minTime = 1 / seg.speed
	return s
end

-- DEADLIFT: SET YOUR BACK - the back-angle needle swings between rounded and over-arched; the LIFT press
-- sets it where the needle is (neutral = the gold band) and starts the pull. LIFT held (or tapped on)
-- drives the bar; let go and it drops back. Off the floor the GRIP meter drains (faster through the
-- sticking point at the knees); GRIP squeezes it back up. Grip at zero: the bar slips.
J.deadlift = function(seg, M, TapHold)
	local s = { closed = false, phase = "set", p = 0, g = 1, minG = 1, lift = {}, grips = 0 }
	local function close(T, v)
		s.closed, s.endT, s.verdict = true, T, v
	end
	function s.needleAt(t)
		return needle(t - M, seg.sweep)
	end
	stepper(s, M, function(T)
		if s.phase == "set" then
			if T - M >= seg.wait then
				close(T, "none")
			end
			return
		end
		local stick = s.p >= seg.stickLo and s.p <= seg.stickHi
		if s.lift.on then
			s.p = math.min(1, s.p + seg.speed * (stick and seg.stickMult or 1) * TICK)
		else
			s.p = math.max(0, s.p - seg.drop * TICK)
		end
		if s.p > 0 then
			s.g -= seg.drain * (stick and 1.4 or 1) * TICK
			s.minG = math.min(s.minG, s.g)
			if s.g <= 0 then
				s.g = 0
				close(T, "grip")
				return
			end
		end
		if s.p >= 1 then
			close(T, "lockout")
		elseif T - s.setT >= seg.limit then
			close(T, "stalled")
		end
	end)
	function s.input(id, down, t)
		if s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if id == "lift" then
			local flip = TapHold(s.lift, down, t)
			if flip == "on" and s.phase == "set" then
				s.phase, s.setT = "drive", t
				local pos = s.needleAt(t)
				local dd, w = math.abs(pos - seg.c), seg.w
				if dd <= w then
					s.setQ = 1 - 0.1 * dd / w
				elseif dd <= 2.5 * w then
					s.setQ = 0.85 - 0.35 * (dd - w) / (1.5 * w)
				else
					s.setQ = 0.45
				end
				s.setPos = pos
				return { set = true, pos = pos, d = dd, setQ = s.setQ }
			end
			return flip and { lift = flip == "on" } or nil
		elseif id == "grip" and down and s.phase == "drive" then
			s.g = math.min(1, s.g + seg.gripTap)
			s.grips += 1
			return { grip = s.g }
		end
		return nil
	end
	s.finish = finishOf(s)
	function s.result()
		local v = s.verdict or (s.phase == "drive" and "stalled" or "none")
		local q = 0
		local setQ = s.setQ or 0
		if v == "lockout" then
			local band = seg.stickHi - seg.stickLo
			local ideal = band / (seg.speed * seg.stickMult) + (1 - band) / seg.speed
			local tq = clamp(ideal / math.max(0.01, s.endT - s.setT), 0.7, 1)
			local gq = clamp(0.5 + s.minG * 1.5, 0.5, 1)
			q = 0.4 * setQ + 0.35 * gq + 0.25 * tq
		elseif v == "grip" then
			q = 0.3 + 0.15 * s.p
		elseif v == "stalled" then
			q = 0.25 + 0.2 * s.p
		end
		return { q = q, verdict = v, p = s.p, setQ = setQ, minGrip = s.minG, grips = s.grips, pressed = s.phase == "drive" }
	end
	function s.endsAt()
		return s.endT or (s.phase == "set" and (M + seg.wait)) or nil
	end
	s.minTime = RT_FLOOR + 1 / seg.speed
	return s
end

-- SQUAT: SIT (tap or hold) starts the descent - it speeds up as you sink (v0 + acc * t); let go to stop
-- at the bottom: the depth is judged against the depth zone (parallel). Then SIT again inside the
-- bounce window (seg.bounce .. seg.pause after the bottom) and keep it on to drive up; letting go on the
-- way up stalls (the bar sinks a little). Sink all the way (depth 1) and you dive-bombed the hole.
J.squat = function(seg, M, TapHold)
	local s = { closed = false, phase = "ready", z = 0, u = 0, sit = {}, stalls = 0 }
	local function close(T, v)
		s.closed, s.endT, s.verdict = true, T, v
	end
	stepper(s, M, function(T)
		local ph = s.phase
		if ph == "ready" then
			if T - M >= seg.wait then
				close(T, "none")
			end
		elseif ph == "descend" then
			s.z += (seg.v0 + seg.acc * (T - s.descT)) * TICK
			if s.z >= 1 then
				s.z = 1
				s.phase, s.bottomT, s.bottomZ = "bottom", T, 1
			end
		elseif ph == "bottom" then
			if T - s.bottomT >= seg.lost then
				close(T, "stuck")
			end
		elseif ph == "drive" then
			if s.sit.on then
				s.u = math.min(1, s.u + seg.rise * TICK)
			else
				s.u = math.max(0, s.u - 0.3 * TICK)
			end
			if s.u >= 1 then
				close(T, "stand")
			elseif T - s.driveT >= seg.limit then
				close(T, "stalled")
			end
		end
	end)
	function s.depth()
		return s.phase == "drive" and (s.bottomZ or s.z) * (1 - s.u) or s.z
	end
	function s.input(id, down, t)
		if s.closed or t < M or id ~= "sit" then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		local flip = TapHold(s.sit, down, t)
		if not flip then
			return nil
		end
		local ph = s.phase
		if ph == "ready" and flip == "on" then
			s.phase, s.descT = "descend", t
			return { descend = true }
		elseif ph == "descend" and flip == "off" then
			s.phase, s.bottomT, s.bottomZ = "bottom", t, s.z
			return { bottom = true, z = s.z }
		elseif ph == "bottom" and flip == "on" then
			s.phase, s.driveT = "drive", t
			s.pressDt = t - s.bottomT
			return { drive = true, dt = s.pressDt }
		elseif ph == "drive" and flip == "off" then
			s.stalls += 1
			return { stall = true }
		end
		return nil
	end
	s.finish = finishOf(s)
	function s.result()
		local v = s.verdict or ((s.phase == "drive" and "stalled") or (s.phase == "ready" and "none") or "stuck")
		local z, lo, hi = s.bottomZ or s.z, seg.lo, seg.hi
		local depthQ, depth
		if z >= 1 then
			depthQ, depth = 0.45, "dive"
		elseif z >= lo and z <= hi then
			depthQ, depth = 1 - 0.1 * math.abs(z - (lo + hi) / 2) / ((hi - lo) / 2), "zone"
		elseif z < lo then
			depthQ, depth = 0.5 + 0.3 * clamp(1 - (lo - z) / 0.2, 0, 1), "high"
		else
			depthQ, depth = 0.7, "deep"
		end
		local driveQ, drive = 0, "none"
		local dt = s.pressDt
		if dt then
			if dt < seg.bounce then
				driveQ, drive = 0.7, "bounce"
			elseif dt <= seg.pause then
				driveQ, drive = 1, "good"
			else
				driveQ, drive = clamp(1 - (dt - seg.pause) * 0.4, 0.6, 0.9), "pause"
			end
		end
		local q = 0
		if v == "stand" then
			q = 0.5 * depthQ + 0.3 * driveQ + 0.2 * math.max(0.5, 1 - 0.15 * s.stalls)
		elseif v == "stalled" then
			q = 0.25 + 0.2 * s.u
		elseif v == "stuck" then
			q = 0.3 * depthQ
		end
		return { q = q, verdict = v, z = z, depth = depth, depthQ = depthQ, drive = drive, pressDt = dt, stalls = s.stalls, pressed = v ~= "none" }
	end
	function s.endsAt()
		return s.endT or (s.phase == "ready" and (M + seg.wait)) or nil
	end
	s.minTime = 0.5 + 1 / seg.rise
	return s
end

-- PULL-UPS (hold and release, grip stamina): one segment is a set of seg.reps reps. PULL held climbs
-- (seg.speed a second, slower as the grip tires: x(0.6 + 0.4 grip)); RELEASE with the chin over the bar -
-- the height inside [seg.lo, 1] - is a rep (SWEET inside [seg.perfLo, seg.perfHi]); a release below it is
-- SHORT (no rep, nothing else lost). After a release the body lowers under control (seg.sink a second)
-- and the next pull starts from the bottom (h <= seg.ready). The GRIP drains while you pull (seg.drain, more
-- held at the top: seg.topDrain) and comes back while you hang (seg.regen): pace the set. A grip that runs
-- out drops you off the bar (a SLIP: no rep, the grip back to seg.slipGrip). The set closes on its reps or
-- at seg.limit; a set nobody starts closes after seg.wait.
J.pullup = function(seg, M, TapHold)
	local s = { closed = false, h = 0, grip = 1, pull = false, lowering = false, done = 0, perfect = 0, good = 0, short = 0, slips = 0, topT = 0, reps = {} }
	local function close(T, v)
		s.closed, s.endT, s.verdict = true, T, v
	end
	stepper(s, M, function(T)
		if not s.started then
			s.grip = 1
			if T - M >= seg.wait then
				close(T, "none")
			end
			return
		end
		if s.pull then
			s.h = math.min(1, s.h + seg.speed * (0.6 + 0.4 * s.grip) * TICK)
			s.grip -= (seg.drain + (s.h >= 1 and seg.topDrain or 0)) * TICK
			if s.h >= 1 then
				s.topT += TICK
			end
			if s.grip <= 0 then
				-- the grip gave out: off the bar
				s.grip, s.pull, s.lowering = seg.slipGrip, false, true
				s.slips += 1
				s.last = { verdict = "slip", T = T }
			end
		else
			s.grip = math.min(1, s.grip + seg.regen * (s.h <= seg.ready and 1.5 or 1) * TICK)
			if s.lowering then
				s.h = math.max(0, s.h - seg.sink * TICK)
				if s.h <= seg.ready then
					s.lowering = false
				end
			end
		end
		if s.done >= seg.reps then
			close(T, "set")
		elseif T - s.startT >= seg.limit then
			close(T, "time")
		end
	end)
	function s.ready()
		return not s.lowering and s.h <= seg.ready
	end
	function s.input(id, down, t)
		if s.closed or t < M or id ~= "pull" then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if down then
			if s.pull or not s.ready() then
				return nil
			end
			if not s.started then
				s.started, s.startT = true, t
			end
			s.pull, s.topT = true, 0
			return { pull = true }
		end
		if not s.pull then
			return nil
		end
		-- the release: where the chin is decides the rep
		s.pull, s.lowering = false, true
		local h = s.h
		local v
		if h >= seg.perfLo and h <= seg.perfHi and s.topT <= 0.25 then
			v = "sweet"
			s.perfect += 1
			s.done += 1
		elseif h >= seg.lo then
			v = "rep"
			s.good += 1
			s.done += 1
		else
			v = "short"
			s.short += 1
		end
		table.insert(s.reps, { verdict = v, h = h, t = t })
		s.last = { verdict = v, h = h, T = t }
		if s.done >= seg.reps then
			close(t, "set")
		end
		return { verdict = v, h = h, done = s.done }
	end
	s.finish = finishOf(s)
	function s.result()
		-- (a sweet rep 1, a rep 0.75; a short pull or a slip costs a little - a cheap failure, never a reset)
		local q = (s.perfect + 0.75 * s.good) / math.max(1, seg.reps) - 0.08 * s.short - 0.1 * s.slips
		return { q = clamp(q, 0, 1), verdict = s.verdict or (s.started and "time" or "none"), perfect = s.perfect, good = s.good, short = s.short, slips = s.slips,
			done = s.done, reps = seg.reps, h = s.h, grip = s.grip, pressed = s.started == true }
	end
	function s.endsAt()
		return s.endT or (not s.started and (M + seg.wait)) or nil
	end
	s.minTime = seg.reps * (seg.lo / seg.speed + (seg.lo - seg.ready) / seg.sink) * 0.8
	return s
end

-- DUMBBELL CURLS on a tempo: each curl is a hold note on its arm's lane (LEFT / RIGHT) - press as it
-- reaches the line (curl up), keep holding through the squeeze, let go as its tail passes (lower).
-- Both arms held at once is swinging the weight (a cheat, counted).
J.tempo = function(seg, M)
	local notes = {}
	local t0 = M + seg.lead
	for i, nd in ipairs(seg.notes) do
		notes[i] = { lane = nd[1], ts = t0 + nd[2] * seg.beat, te = t0 + nd[3] * seg.beat }
	end
	local last = notes[#notes]
	local endT = (last and last.te or M) + seg.relW
	local s = { notes = notes, closed = false, active = {}, down = {}, stray = 0, swings = 0, sum = 0, perfect = 0, missed = 0, endT = endT }
	local function judge(n, at, how)
		n.judged, n.at = true, at
		local sq = n.startErr and ((math.abs(n.startErr) < seg.perfW and 1) or (math.abs(n.startErr) < seg.hitW * 0.65 and 0.85) or 0.6) or 0
		local eq
		if how == "release" then
			local e = at - n.te
			if e < -seg.relW then
				eq = 0.3 + 0.3 * clamp((at - n.ts) / math.max(0.01, n.te - n.ts), 0, 1)
				n.endText = "early"
			else
				eq = 1 - 0.5 * math.abs(e) / seg.relW
				n.endText = "good"
			end
		elseif how == "held" then
			eq, n.endText = 0.55, "late"
		else
			eq, n.endText = 0, "miss"
		end
		n.q = how == "miss" and 0 or (0.5 * sq + 0.5 * eq)
		s.sum += n.q
		if n.q >= 0.9 then
			s.perfect += 1
		end
		if how == "miss" then
			s.missed += 1
		end
		return n
	end
	function s.advance(t)
		local out
		for _, n in ipairs(notes) do
			if not n.judged then
				local how
				if not n.startT and t - n.ts > seg.hitW then
					how = "miss"
				elseif n.startT and t - n.te > seg.relW then
					how = "held"
				end
				if how then
					judge(n, how == "miss" and (n.ts + seg.hitW) or (n.te + seg.relW), how)
					if s.active[n.lane] == n then
						s.active[n.lane] = nil
					end
					out = out or {}
					table.insert(out, n)
				end
			end
		end
		if t >= endT then
			s.closed = true
		end
		return out
	end
	function s.input(id, down, t)
		if s.closed or t < M or (id ~= "L" and id ~= "R") then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		s.down[id] = down
		if down then
			local other = id == "L" and "R" or "L"
			local swing = s.down[other] == true
			if swing then
				s.swings += 1
			end
			local best, bestDt
			for _, n in ipairs(notes) do
				if not n.judged and not n.startT and n.lane == id then
					local dt = t - n.ts
					if math.abs(dt) < seg.hitW and (not best or math.abs(dt) < math.abs(bestDt)) then
						best, bestDt = n, dt
					end
				end
			end
			if not best then
				if t >= t0 - seg.hitW and t <= endT then
					s.stray += 1
				end
				return { id = id, stray = true, swing = swing }
			end
			best.startT, best.startErr = t, bestDt
			s.active[id] = best
			return { id = id, start = best, dt = bestDt, swing = swing }
		end
		local n = s.active[id]
		if not n then
			return nil
		end
		s.active[id] = nil
		judge(n, t, "release")
		return { id = id, release = n }
	end
	s.finish = finishOf(s)
	function s.result()
		return { sum = s.sum, count = #notes, perfect = s.perfect, missed = s.missed, stray = s.stray, swings = s.swings }
	end
	function s.endsAt()
		local e = M
		for _, n in ipairs(notes) do
			e = math.max(e, n.at or (n.te + seg.relW))
		end
		return e
	end
	s.minTime = math.max(0, (last and last.te or M) - M)
	return s
end

-- the time-on-target drills (treadmill, bike, chamber): s.acc counts the ticks' credit (0..1 each)
local function timed(seg, M)
	local s = { closed = false, acc = 0, duration = seg.duration }
	s.finish = function(t)
		s.advance(t)
		s.closed = true
	end
	function s.endsAt()
		return M + seg.duration
	end
	s.minTime = seg.duration
	return s
end
-- the program step in force el seconds in (a list of { t = start, ... })
local function stepAt(list, el)
	local cur = list[1]
	for _, p in ipairs(list) do
		if el + 1e-9 >= p.t then
			cur = p
		end
	end
	return cur
end
W.StepAt = stepAt

-- TREADMILL: the console follows a program of speed / incline targets; SPEED + / - and INCLINE + / -
-- step the belt (seg.stepMph, one % of incline). A tick on both targets is full credit, on one half.
-- A button held repeats (after REPEAT_DELAY, every REPEAT_EVERY): no mashing for a big change of pace.
local REPEAT_DELAY, REPEAT_EVERY = 0.35, 0.2
J.treadmill = function(seg, M)
	local s = timed(seg, M)
	s.mph, s.incl, s.onBoth = seg.mph0, seg.incl0, 0
	s.rep = {}
	function s.target(t)
		return stepAt(seg.program, t - M)
	end
	local function press(id)
		if id == "spdUp" then
			s.mph = math.min(seg.mphMax, s.mph + seg.stepMph)
		elseif id == "spdDn" then
			s.mph = math.max(seg.mphMin, s.mph - seg.stepMph)
		elseif id == "incUp" then
			s.incl = math.min(seg.inclMax, s.incl + 1)
		elseif id == "incDn" then
			s.incl = math.max(0, s.incl - 1)
		end
	end
	stepper(s, M, function(T)
		for id, nextT in pairs(s.rep) do
			if T + 1e-9 >= nextT then
				press(id)
				s.rep[id] = nextT + REPEAT_EVERY
			end
		end
		local tg = stepAt(seg.program, T - M)
		-- on target is full credit; just off (inside 1.5x the tolerance) half; the incline counts half
		local dS, dI = math.abs(s.mph - tg.mph), math.abs(s.incl - tg.incl)
		local okS, okI = dS <= seg.tolMph + 1e-6, dI <= seg.tolIncl + 1e-6
		local cs = okS and 1 or (dS <= 1.5 * seg.tolMph + 1e-6 and 0.5 or 0)
		local ci = okI and 1 or (dI <= 1.5 * seg.tolIncl + 1e-6 and 0.5 or 0)
		s.acc += cs * (0.5 + 0.5 * ci)
		if okS and okI then
			s.onBoth += 1
		end
		if T - M >= seg.duration - 1e-6 then
			s.closed = true
		end
	end)
	function s.input(id, down, t)
		if s.closed or t < M or not (id == "spdUp" or id == "spdDn" or id == "incUp" or id == "incDn") then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if not down then
			s.rep[id] = nil
			return nil
		end
		press(id)
		s.rep[id] = t + REPEAT_DELAY
		return { mph = s.mph, incl = s.incl }
	end
	function s.result()
		return { acc = s.acc * TICK, onBoth = s.onBoth * TICK, duration = seg.duration }
	end
	return s
end

-- BIKE: pedal LEFT / RIGHT in turn (the cadence comes from the time between strokes) and shift GEAR up /
-- down for the hill profile. The gear the gradient wants turns your strokes into the cadence band; too
-- high a gear bogs the cadence down, too low spins it out.
function W.IdealGear(grade, gears)
	return clamp(math.floor(4.5 - 0.45 * grade + 0.5), 1, gears or 6)
end
J.bike = function(seg, M)
	local s = timed(seg, M)
	s.gear, s.strokes, s.inBand = seg.gear0, 0, 0
	function s.hill(t)
		return stepAt(seg.hill, t - M)
	end
	function s.rpm(t)
		if not s.lastTap then
			return 0
		end
		local iv = math.max(s.lastIv or 1, t - s.lastTap)
		local ideal = W.IdealGear(stepAt(seg.hill, t - M).grade, seg.gears)
		local k = clamp(1 + 0.13 * (ideal - s.gear), 0.45, 1.7)
		return 30 / iv * k
	end
	stepper(s, M, function(T)
		local rpm = s.rpm(T)
		local ideal = W.IdealGear(stepAt(seg.hill, T - M).grade, seg.gears)
		local band = rpm >= seg.lo and rpm <= seg.hi
		local gearOk = math.abs(s.gear - ideal) <= 1
		s.acc += (band and gearOk) and 1 or (band and 0.7 or 0)
		if band then
			s.inBand += 1
		end
		if T - M >= seg.duration - 1e-6 then
			s.closed = true
		end
	end)
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if id == "gearUp" or id == "gearDn" then
			s.gear = clamp(s.gear + (id == "gearUp" and 1 or -1), 1, seg.gears)
			return { gear = s.gear }
		elseif id == "L" or id == "R" then
			if id == s.lastFoot then
				return { alt = false }
			end
			if s.lastTap then
				s.lastIv = clamp(t - s.lastTap, 0.12, 2)
			end
			s.lastTap, s.lastFoot = t, id
			s.strokes += 1
			return { alt = true }
		end
		return nil
	end
	function s.result()
		return { acc = s.acc * TICK, inBand = s.inBand * TICK, strokes = s.strokes, duration = seg.duration }
	end
	return s
end

-- ROWER: ROW (tap or hold) is the drive - the handle comes from the catch to the finish in seg.drive
-- seconds; let go at the finish (past finishLo), the handle runs back to the catch on its own at the
-- piece's stroke rate (the recovery), and ROW again as it reaches the catch. A catch taken early rushes
-- the slide, one left waiting is a pause; a drive let go short is a short stroke, one held at the body
-- is hanging at the finish. Every stroke is graded (catch half, finish half).
J.rower = function(seg, M, TapHold)
	local s = { closed = false, x = 0, phase = "catch", reachedAt = M, row = {}, strokes = {}, sum = 0, hang = 0 }
	function s.piece(t)
		return stepAt(seg.pieces, t - M)
	end
	local function recT(T)
		return math.max(0.55, 60 / stepAt(seg.pieces, T - M).spm - seg.drive)
	end
	local function stroke(t, x)
		local fq
		if x >= seg.finishLo then
			fq = 1 - math.min(0.4, math.max(0, s.hang - 0.45) * 1.0)
		else
			fq = 0.35 + 0.5 * x / seg.finishLo
		end
		local q = 0.5 * s.cq + 0.5 * fq
		s.sum += q
		local st = { t = t, q = q, cq = s.cq, fq = fq, catch = s.catchText, finish = x < seg.finishLo and "short" or (s.hang > 0.3 and "hang" or "clean") }
		table.insert(s.strokes, st)
		s.last = st
		s.phase = "recover"
		return st
	end
	stepper(s, M, function(T)
		if s.phase == "drive" then
			if s.x < 1 then
				s.x = math.min(1, s.x + TICK / seg.drive)
			else
				s.hang += TICK
				if s.hang >= 1.2 then
					stroke(T, 1)
				end
			end
		elseif s.phase == "recover" then
			s.x = math.max(0, s.x - TICK / recT(T))
			if s.x <= 0 then
				s.phase, s.reachedAt = "catch", T
			end
		end
		if T - M >= seg.duration - 1e-6 then
			s.closed = true
		end
	end)
	function s.input(id, down, t)
		if s.closed or t < M or id ~= "row" then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		local flip = TapHold(s.row, down, t)
		if flip == "on" and (s.phase == "catch" or s.phase == "recover") then
			if s.phase == "catch" then
				local w = t - s.reachedAt
				s.cq = w <= 0.45 and 1 or math.max(0.4, 1 - (w - 0.45) * 0.9)
				s.catchText = w <= 0.45 and "clean" or "pause"
			elseif s.x <= seg.catchW then
				s.cq, s.catchText = 1, "clean"
			else
				s.cq, s.catchText = math.max(0.35, 1 - s.x * 2), "rushed"
			end
			s.phase, s.hang = "drive", 0
			return { catch = s.catchText }
		elseif flip == "off" and s.phase == "drive" then
			return { stroke = stroke(t, s.x) }
		end
		return nil
	end
	s.finish = finishOf(s)
	-- the strokes a clean crew rows in the session (the catch taken at once)
	function s.expected()
		local n = 0
		for i, p in ipairs(seg.pieces) do
			local nextT = seg.pieces[i + 1] and seg.pieces[i + 1].t or seg.duration
			n += (nextT - p.t) / (seg.drive + math.max(0.55, 60 / p.spm - seg.drive))
		end
		return n
	end
	function s.result()
		return { sum = s.sum, strokes = #s.strokes, expected = s.expected(), duration = seg.duration }
	end
	function s.endsAt()
		return M + seg.duration
	end
	s.minTime = seg.duration
	return s
end

-- ICE BATH: BREATHE in (tap or hold) fills the lungs over seg.inhale seconds, letting go empties them over
-- seg.exhale. The cold meter climbs all the time (faster in the cold waves); a long, full exhale after a
-- full breath taken from empty brings it down; empty lungs left waiting (air hunger) push it up. Under
-- 0.5 is calm, past 0.8 you shiver.
J.icebath = function(seg, M, TapHold)
	local s = { closed = false, l = 0, S = seg.s0, br = {}, calmT = 0, breaths = 0, good = 0, emptyAt = M, duration = seg.duration }
	function s.wave(t)
		local el = t - M
		for _, w in ipairs(seg.waves) do
			if el >= w[1] and el < w[1] + w[2] then
				return true
			end
		end
		return false
	end
	stepper(s, M, function(T)
		local on = s.br.on
		if on then
			s.l = math.min(1, s.l + TICK / seg.inhale)
		else
			local was = s.l
			s.l = math.max(0, s.l - TICK / seg.exhale)
			if was > 0 and s.l <= 0 then
				s.emptyAt = T
			end
		end
		local dS = seg.cold * (s.wave(T) and seg.waveMult or 1)
		if not on and s.calm and s.l > 0.05 then
			dS -= seg.calmRate * s.calm
		end
		if not on and s.l <= 0 and T - s.emptyAt > 2.5 then
			dS += 0.03
		end
		if on and s.l >= 1 and T - (s.fullAt or T) > 1.5 then
			dS += 0.02
		end
		if on and s.l >= 1 and not s.fullAt then
			s.fullAt = T
		end
		s.S = clamp(s.S + dS * TICK, 0, 1)
		s.calmT += s.S < 0.5 and 1 or (s.S < 0.8 and 0.5 or 0)
		if T - M >= seg.duration - 1e-6 then
			s.closed = true
		end
	end)
	function s.input(id, down, t)
		if s.closed or t < M or id ~= "breathe" then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		local flip = TapHold(s.br, down, t)
		if flip == "on" then
			s.startL, s.fullAt = s.l, nil
			return { inhale = true, from = s.l }
		elseif flip == "off" then
			-- how calming the breath was: how full (0.38 .. 0.88) times how empty it started (0.68 .. 0.18):
			-- a breath begun with a little air left is still a fair one
			local full, fromEmpty = s.l >= 0.8, (s.startL or 1) <= 0.3
			local q = clamp((s.l - 0.38) / 0.5, 0, 1) * clamp((0.68 - (s.startL or 1)) / 0.5, 0, 1)
			local good = q >= 0.75
			s.breaths += 1
			s.calm = q > 0 and q or nil
			s.good += q
			return { exhale = true, good = good, full = full, fromEmpty = fromEmpty }
		end
		return nil
	end
	s.finish = finishOf(s)
	function s.result()
		return { calm = s.calmT * TICK, duration = seg.duration, breaths = s.breaths, good = s.good, expected = seg.duration / (seg.inhale + seg.exhale) }
	end
	function s.endsAt()
		return M + seg.duration
	end
	s.minTime = seg.duration
	return s
end

-- STRETCH: one pose. SINK (tap or hold) eases deeper, letting go backs off; the target range creeps
-- deeper through the hold as the muscle lets go. In range is the score; past the top of it is an
-- overstretch (each one costs), and too long over it tweaks the muscle.
J.stretch = function(seg, M, TapHold)
	local s = { closed = false, z = 0, sink = {}, inT = 0, overs = 0, overT = 0, duration = seg.dur }
	function s.band(t)
		local k = clamp((t - M) / seg.dur, 0, 1)
		return seg.lo + seg.slide * k, seg.hi + seg.slide * k
	end
	stepper(s, M, function(T)
		if s.sink.on then
			s.z = math.min(1, s.z + seg.sinkRate * TICK)
		else
			s.z = math.max(0, s.z - seg.ease * TICK)
		end
		local lo, hi = s.band(T)
		local over = s.z > hi + seg.overMargin
		if over then
			s.overT += TICK
			if not s.wasOver then
				s.overs += 1
			end
		elseif s.z >= lo and s.z <= hi then
			s.inT += 1
		end
		s.wasOver = over
		if T - M >= seg.dur - 1e-6 then
			s.closed = true
		end
	end)
	function s.input(id, down, t)
		if s.closed or t < M or id ~= "sink" then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		local flip = TapHold(s.sink, down, t)
		return flip and { sink = flip == "on" } or nil
	end
	s.finish = finishOf(s)
	function s.result()
		local reach = seg.lo / seg.sinkRate
		local share = s.inT * TICK / math.max(0.5, (seg.dur - reach - 0.3) * 0.9)
		local q = clamp(share, 0, 1) - 0.12 * s.overs
		local tweaked = s.overT > 1.0
		if tweaked then
			q *= 0.6
		end
		return { q = clamp(q, 0, 1), inRange = s.inT * TICK, overs = s.overs, tweaked = tweaked, duration = seg.dur }
	end
	function s.endsAt()
		return M + seg.dur
	end
	s.minTime = seg.dur
	return s
end

-- MASSAGE: rounds of CHOOSE (move the cursor over the muscle groups - their soreness is on the body map
-- - and pick one; picking the sorest group left is full marks) then WORK (the therapist's strokes come
-- on a slow beat: RELAX (the same button) on each stroke). seg.groups / seg.sore: the groups in order
-- and how sore each is (the player's own soreness, Training.MinigameParams).
J.massage = function(seg, M)
	local G = seg.groups
	local sore = {}
	for i, g in ipairs(G) do
		sore[g] = seg.sore[i] or 0
	end
	local s = { closed = false, phase = "choose", round = 1, cursor = 1, chooseAt = M, worked = {}, picks = {}, pickSum = 0, relax = 0, strokesTotal = 0, stray = 0, sore = sore }
	local function remainingMax()
		local m = 0
		for _, g in ipairs(G) do
			if not s.worked[g] then
				m = math.max(m, sore[g])
			end
		end
		return m
	end
	local function pick(g, t, timedOut)
		local m = remainingMax()
		-- (a spot nearly as sore as the worst one - 80% of it - is a full pick)
		local q = timedOut and 0 or (m > 0 and clamp(sore[g] / m / 0.8, 0, 1) or 1)
		s.pickSum += q
		s.worked[g] = true
		local p = { group = g, q = q, timedOut = timedOut == true, sore = sore[g] }
		table.insert(s.picks, p)
		s.phase, s.strokes = "work", {}
		for k = 1, seg.strokes do
			s.strokes[k] = { t = t + seg.firstStroke + (k - 1) * seg.beat }
		end
		s.strokesTotal += seg.strokes
		s.workEnd = s.strokes[#s.strokes].t + seg.hitW
		return p
	end
	function s.advance(t)
		local out
		if s.phase == "choose" and t - s.chooseAt >= seg.chooseT then
			local g = G[s.cursor]
			if s.worked[g] then
				for _, gg in ipairs(G) do
					if not s.worked[gg] then
						g = gg
						break
					end
				end
			end
			out = { picked = pick(g, s.chooseAt + seg.chooseT, true) }
		end
		if s.phase == "work" then
			for _, st in ipairs(s.strokes) do
				if not st.judged and t - st.t > seg.hitW then
					st.judged, st.grade = true, "miss"
					out = out or {}
					out.missed = (out.missed or 0) + 1
				end
			end
			if t >= s.workEnd then
				if s.round >= seg.rounds then
					s.closed, s.endT = true, s.workEnd
				else
					s.round += 1
					s.phase, s.chooseAt = "choose", s.workEnd
				end
			end
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
		if s.phase == "choose" then
			if id == "prev" or id == "next" then
				s.cursor = (s.cursor - 1 + (id == "next" and 1 or -1)) % #G + 1
				return { cursor = s.cursor }
			elseif id == "ok" then
				local g = G[s.cursor]
				if s.worked[g] then
					return { already = true }
				end
				return { picked = pick(g, t, false) }
			end
			return nil
		end
		if id ~= "ok" then
			return nil
		end
		local best, bestDt
		for _, st in ipairs(s.strokes) do
			if not st.judged and math.abs(t - st.t) < seg.hitW and (not best or math.abs(t - st.t) < math.abs(bestDt)) then
				best, bestDt = st, t - st.t
			end
		end
		if not best then
			s.stray += 1
			return { stray = true }
		end
		best.judged = true
		best.grade = math.abs(bestDt) < seg.perfW and "perfect" or "good"
		s.relax += best.grade == "perfect" and 1 or 0.6
		return { stroke = best }
	end
	s.finish = finishOf(s)
	function s.result()
		return { pickSum = s.pickSum, picks = #s.picks, rounds = seg.rounds, relax = s.relax, strokes = seg.rounds * seg.strokes, stray = s.stray }
	end
	function s.endsAt()
		return s.endT
	end
	s.minTime = seg.rounds * (RT_FLOOR + seg.firstStroke + (seg.strokes - 1) * seg.beat)
	return s
end

-- RECOVERY CHAMBER: follow the pressure profile (up to depth, hold, back up to the surface): PRESSURISE
-- and VENT are held; the chamber leaks a little on its own. Every change of pressure loads the ears;
-- EQUALIZE clears them. Ears full: pain - you can't pressurise and nothing counts for two seconds.
J.chamber = function(seg, M)
	local s = timed(seg, M)
	s.P, s.ear, s.eqs, s.pains, s.painUntil = 1, 0, 0, 0, -math.huge
	holds(s)
	function s.target(t)
		local el, pts = t - M, seg.profile
		for i = 2, #pts do
			if el <= pts[i][1] then
				local a, b = pts[i - 1], pts[i]
				return a[2] + (b[2] - a[2]) * clamp((el - a[1]) / math.max(1e-6, b[1] - a[1]), 0, 1)
			end
		end
		return pts[#pts][2]
	end
	stepper(s, M, function(T)
		local pain = T < s.painUntil
		local dp = 0
		if s.held("up", T) and not pain then
			dp += seg.rise * TICK
		end
		if s.held("down", T) then
			dp -= seg.vent * TICK
		end
		if s.P > 1 then
			-- (the seal breathes: the leak comes and goes - top the pressure up as it sags)
			dp -= seg.leak * (1 + (seg.leakWave or 0) * math.sin(1.3 * (T - M))) * TICK
		end
		local P0 = s.P
		s.P = clamp(s.P + dp, 1, seg.maxP)
		s.ear = math.max(0, s.ear + seg.earRate * math.abs(s.P - P0) - 0.02 * TICK)
		if s.ear >= 1 and not pain then
			s.ear = 1
			s.pains += 1
			s.painUntil = T + 1.2
			pain = true
		end
		if not pain then
			local d = math.abs(s.P - s.target(T))
			s.acc += d <= seg.tol and 1 or (d <= 1.5 * seg.tol and 0.5 or 0)
		end
		if T - M >= seg.duration - 1e-6 then
			s.closed = true
		end
	end)
	function s.input(id, down, t)
		if s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if id == "up" or id == "down" then
			s.setHold(id, down, t)
		elseif id == "eq" and down then
			local before = s.ear
			s.ear = math.max(0, s.ear - 0.6)
			s.eqs += 1
			return { eq = true, cleared = before - s.ear }
		end
		return nil
	end
	function s.result()
		return { acc = s.acc * TICK, pains = s.pains, eqs = s.eqs, duration = seg.duration }
	end
	return s
end

-- SAUNA (weight cut): inside, the core temperature climbs and the water comes off faster the hotter you
-- run; STEP OUT cools you down (and the cut all but stops), STEP IN goes back. SIP (every 2 s at most)
-- takes the edge off the heat and puts a little water back. Past 0.85 is the danger zone; at 1 you go
-- light-headed and the coach pulls you out for 4 s. The score: the water cut against the goal, safely.
J.sauna = function(seg, M)
	local s = { closed = false, T = seg.t0, w = 0, inside = true, forcedUntil = -math.huge, lastSip = -math.huge, sips = 0, faints = 0, danger = 0, duration = seg.duration }
	stepper(s, M, function(T)
		if s.inside then
			s.T += seg.heat * TICK
			s.w += (seg.lossBase + seg.lossT * s.T) * TICK
		else
			s.T = math.max(seg.t0 * 0.8, s.T - seg.cool * TICK)
			s.w += 0.01 * TICK
		end
		if s.T > 0.85 then
			s.danger += TICK
		end
		if s.T >= 1 then
			s.faints += 1
			s.inside = false
			s.forcedUntil = T + 4
			s.T = 0.9
		end
		if T - M >= seg.duration - 1e-6 then
			s.closed = true
		end
	end)
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if id == "door" then
			if t < s.forcedUntil then
				return { forced = true }
			end
			s.inside = not s.inside
			return { inside = s.inside }
		elseif id == "sip" then
			if t - s.lastSip < 2 then
				return { wait = true }
			end
			s.lastSip = t
			s.sips += 1
			s.w = math.max(0, s.w - 0.12)
			s.T = math.max(seg.t0 * 0.8, s.T - 0.08)
			return { sip = true }
		end
		return nil
	end
	s.finish = finishOf(s)
	function s.result()
		return { w = s.w, goal = seg.goal, danger = s.danger, faints = s.faints, sips = s.sips, duration = seg.duration }
	end
	function s.endsAt()
		return M + seg.duration
	end
	s.minTime = seg.duration
	return s
end

-- DOUBLE-END REBOUND: PUNCH the bag, then slip its return: it comes back seg.ret seconds after the punch
-- and the slip (seg.want) must land inside +-seg.w of that moment. Too soon and you are back in its path.
J.rebound = function(seg, M)
	local s = { closed = false, step = 1 }
	local function close(t)
		s.closed, s.endT = true, t
	end
	function s.returnAt()
		return s.punchT and (s.punchT + seg.ret) or nil
	end
	function s.advance(t)
		if s.closed then
			return
		end
		if s.step == 1 and t - M >= seg.window then
			close(M + seg.window)
		elseif s.step == 2 and t > s.punchT + seg.ret + seg.w then
			s.hit = true
			close(s.punchT + seg.ret + seg.w)
		end
	end
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if s.step == 1 then
			if id == "punch" and t - M >= RT_FLOOR then
				s.step, s.punchT = 2, t
				return { step = 2, punch = true }
			end
			s.failed = true
			close(t)
			return { step = 1, ok = false }
		end
		local dt = t - (s.punchT + seg.ret)
		close(t)
		if id == seg.want and math.abs(dt) <= seg.w then
			s.ok, s.dt = true, dt
			return { step = 3, ok = true, dt = dt }
		end
		s.failed, s.early, s.dt = true, id == seg.want and dt < 0, dt
		return { step = 2, ok = false, early = s.early }
	end
	s.finish = finishOf(s)
	function s.result()
		return { step = s.ok and 3 or s.step, ok = s.ok == true, dt = s.dt, early = s.early == true, hit = s.hit == true, punched = s.punchT ~= nil }
	end
	function s.endsAt()
		return s.endT or (s.step == 2 and (s.punchT + seg.ret + seg.w)) or (M + seg.window)
	end
	s.minTime = RT_FLOOR + seg.ret - seg.w
	return s
end

-- PLANK (the medicine ball's core set): the ball is under your hands and it wants to roll - the balance
-- drifts (seg.drift: two sine waves and a lean) and LEFT / RIGHT taps shove it back by seg.kick. In the
-- green (|x| <= band) is full credit, inside twice the band half; rolled to the edge (|x| = 1) is a slip
-- (counted, the ball is caught there: nothing resets). The time in the green is the score.
J.wobble = function(seg, M)
	local s = timed(seg, M)
	s.x, s.inBand, s.lost, s.taps = 0, 0, 0, 0
	local d = seg.drift
	function s.driftAt(el)
		return d[1] * math.sin(d[2] * el + d[3]) + d[4] * math.sin(d[5] * el + d[6]) + (seg.bias or 0)
	end
	stepper(s, M, function(T)
		local x = s.x + s.driftAt(T - M) * TICK
		if math.abs(x) >= 1 then
			x = x > 0 and 1 or -1
			if not s.atEdge then
				s.lost += 1
			end
			s.atEdge = true
		else
			s.atEdge = false
		end
		s.x = x
		local ax = math.abs(x)
		s.acc += ax <= seg.band and 1 or (ax <= 2 * seg.band and 0.5 or 0)
		if ax <= seg.band then
			s.inBand += 1
		end
		if T - M >= seg.duration - 1e-6 then
			s.closed = true
		end
	end)
	function s.input(id, down, t)
		if not down or s.closed or t < M or (id ~= "L" and id ~= "R") then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		s.taps += 1
		s.x = clamp(s.x + (id == "L" and -seg.kick or seg.kick), -1, 1)
		return { x = s.x, id = id }
	end
	function s.result()
		return { acc = s.acc * TICK, inBand = s.inBand * TICK, lost = s.lost, taps = s.taps, duration = seg.duration }
	end
	return s
end

-- SLED PUSH (mash bursts): seg.bursts drives of seg.push seconds, each followed by a seg.reset breather
-- (the sled settles; presses then do nothing). In a drive LEFT / RIGHT in turn are the steps - the same
-- leg twice is no step - and seg.target steps make a full drive (the sled's metres). Every drive is its own
-- grade: a slow one costs that drive, nothing carries over.
J.mash = function(seg, M)
	local period = seg.push + seg.reset
	local dur = seg.bursts * period - seg.reset
	local s = { closed = false, steps = {}, wrong = 0, early = 0, duration = dur }
	for k = 1, seg.bursts do
		s.steps[k] = 0
	end
	-- the drive at t (1..bursts) and whether it is pushing (false: the reset after it)
	function s.burstAt(t)
		local el = t - M
		local k = math.floor(el / period) + 1
		return math.clamp(k, 1, seg.bursts), (el - (k - 1) * period) < seg.push and el >= 0
	end
	function s.advance(t)
		if t >= M + dur then
			s.closed = true
		end
		return s
	end
	function s.input(id, down, t)
		if not down or s.closed or t < M or (id ~= "L" and id ~= "R") then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		local k, pushing = s.burstAt(t)
		if not pushing then
			s.early += 1
			return { reset = true }
		end
		if id == s.last then
			s.wrong += 1
			return { same = true, k = k }
		end
		s.last = id
		s.steps[k] += 1
		return { step = true, k = k, n = s.steps[k] }
	end
	function s.finish(t)
		s.closed = true
	end
	function s.result()
		local sum, grades = 0, {}
		for k = 1, seg.bursts do
			local g = math.min(1, s.steps[k] / math.max(1, seg.target))
			grades[k] = g
			sum += g
		end
		return { q = sum / seg.bursts, grades = grades, steps = table.clone(s.steps), wrong = s.wrong, bursts = seg.bursts, target = seg.target, duration = dur }
	end
	function s.endsAt()
		return M + dur
	end
	s.minTime = dur
	return s
end

-- HOLD GAUGE (the neck harness, the forearm squeeze): SQUEEZE held raises the force (seg.rise a second),
-- let go and it falls (seg.fall); the force wavers on its own (two sines, seg.amp growing with the
-- seconds held: seg.grow - the tremor of a tiring muscle) and only the steady band [seg.lo, seg.hi]
-- counts. seg.need seconds in the band inside seg.dur is a full hold. A tap still nudges (W.NUDGE).
J.gauge = function(seg, M)
	local s = { closed = false, f = 0, acc = 0, heldT = 0, duration = seg.dur }
	holds(s)
	local w = seg.wave
	function s.tremor(T)
		local el = T - M
		return (seg.amp + seg.grow * s.heldT) * (math.sin(w[1] * el + w[2]) + 0.6 * math.sin(w[3] * el + w[4]))
	end
	function s.shown(T)
		return clamp(s.f + s.tremor(T), 0, 1.2)
	end
	stepper(s, M, function(T)
		if T - M > seg.dur then
			s.closed = true
			return
		end
		if s.held("sq", T) then
			s.f = math.min(1.1, s.f + seg.rise * TICK)
			s.heldT += TICK
		else
			s.f = math.max(0, s.f - seg.fall * TICK)
		end
		local v = s.shown(T)
		if v >= seg.lo and v <= seg.hi then
			s.acc += TICK
		end
	end)
	function s.input(id, down, t)
		if s.closed or t < M or id ~= "sq" then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		s.setHold("sq", down, t)
		return { sq = down }
	end
	s.finish = finishOf(s)
	function s.result()
		return { q = clamp(s.acc / seg.need, 0, 1), acc = s.acc, need = seg.need, duration = seg.dur }
	end
	function s.endsAt()
		return M + seg.dur
	end
	s.minTime = seg.dur
	return s
end

-- ROADWORK PACE (the treadmill's road lane): STRIDE taps push the runner's pace up (seg.kick), it eases
-- off on its own (seg.decay a second); the pacer's band moves through seg.legs ({ t, lo, hi, name }) and
-- the time inside it counts. BREATHE taps on the breathing cues (seg.breaths, seconds in) from seg.breathW
-- before to 1.4 x seg.breathW after (a reaction to a cue is late more often than early) are breaths in
-- rhythm; a breath tap with no cue near is just a breath (nothing lost).
J.road = function(seg, M)
	local s = { closed = false, v = seg.v0, acc = 0, duration = seg.duration, breathHit = {}, hits = 0, sweet = 0 }
	function s.legAt(T)
		return stepAt(seg.legs, T - M)
	end
	stepper(s, M, function(T)
		if T - M > seg.duration then
			s.closed = true
			return
		end
		s.v = math.max(0, s.v - seg.decay * TICK)
		local leg = s.legAt(T)
		if leg and s.v >= leg.lo and s.v <= leg.hi then
			s.acc += TICK
		end
	end)
	-- the next breathing cue not yet taken (index, seconds to it; negative: just passed)
	function s.nextBreath(t)
		for i, b in ipairs(seg.breaths) do
			if not s.breathHit[i] and (t - M) <= b + 1.4 * seg.breathW then
				return i, b - (t - M)
			end
		end
		return nil
	end
	function s.input(id, down, t)
		if not down or s.closed or t < M then
			return nil
		end
		s.advance(t)
		if s.closed then
			return nil
		end
		if id == "stride" then
			s.v = math.min(1, s.v + seg.kick)
			return { v = s.v }
		elseif id == "breathe" then
			local i, dt = s.nextBreath(t)
			if i and dt <= seg.breathW and dt >= -1.4 * seg.breathW then
				s.breathHit[i] = true
				s.hits += 1
				local sweet = math.abs(dt) <= seg.breathW * 0.4
				if sweet then
					s.sweet += 1
				end
				return { breath = true, sweet = sweet }
			end
			return { breath = false }
		end
		return nil
	end
	s.finish = finishOf(s)
	function s.result()
		local n = #seg.breaths
		local q = 0.7 * clamp(s.acc / seg.duration / W.TIMED_FULL, 0, 1) + 0.3 * s.hits / math.max(1, n)
		return { q = q, acc = s.acc, duration = seg.duration, hits = s.hits, sweet = s.sweet, breaths = n }
	end
	function s.endsAt()
		return M + seg.duration
	end
	s.minTime = seg.duration
	return s
end

W.Judges = J

------------------------------------------------------------------------
-- Session scores (plan.kind -> 0..1)
------------------------------------------------------------------------
local AGG = {}
local function avgQ(plan, res)
	local sum = 0
	for i in ipairs(plan.segs) do
		sum += res[i] and res[i].q or 0
	end
	return sum / math.max(1, #plan.segs)
end
AGG.bench, AGG.pullup, AGG.stretch = avgQ, avgQ, avgQ
-- a lift's reps with a finisher of another kind (the squat's sled push, the deadlift's neck harness):
-- the reps' mean and the finisher's grade, weighted (the finisher: share of the session score)
local function withFinisher(main, share)
	return function(plan, res)
		local sum, n, fin, has = 0, 0, 0, false
		for i, seg in ipairs(plan.segs) do
			if seg.j == main then
				n += 1
				sum += res[i] and res[i].q or 0
			else
				has = true
				fin += res[i] and res[i].q or 0
			end
		end
		local reps = sum / math.max(1, n)
		return has and ((1 - share) * reps + share * fin) or reps
	end
end
AGG.squat = withFinisher("squat", 0.4)
AGG.deadlift = withFinisher("deadlift", 0.25)
AGG.curls = function(plan, res)
	local sum, n, grip, has = 0, 0, 0, false
	for i, seg in ipairs(plan.segs) do
		local r = res[i]
		if seg.j == "gauge" then
			has = true
			grip = r and r.q or 0
		else
			n += #seg.notes
			if r then
				sum += r.sum - 0.1 * (r.swings or 0) - 0.15 * (r.stray or 0)
			end
		end
	end
	local curls = clamp(sum / math.max(1, n), 0, 1)
	return has and (0.75 * curls + 0.25 * grip) or curls
end
-- this share of a time-on-target drill is full marks (nobody is on target the moment a step changes)
W.TIMED_FULL = 0.8
local function accShare(plan, res)
	local r, seg = res[1], plan.segs[1]
	return r and clamp(r.acc / seg.duration / W.TIMED_FULL, 0, 1) or 0
end
AGG.bike = accShare
-- the chamber's profile is slow and always in view: full marks want nearly all of it on target
W.CHAMBER_FULL = 0.92
AGG.chamber = function(plan, res)
	local r, seg = res[1], plan.segs[1]
	return r and clamp(r.acc / seg.duration / W.CHAMBER_FULL, 0, 1) or 0
end
-- the console's program, then the road lane (J.road) when the plan has one
AGG.treadmill = function(plan, res)
	local console = accShare(plan, res)
	local i = #plan.segs
	if i >= 2 and plan.segs[i].j == "road" then
		return 0.6 * console + 0.4 * (res[i] and res[i].q or 0)
	end
	return console
end
-- the strokes' mean grade, times the share of the pieces' strokes rowed (rushing the slide for extra
-- strokes earns nothing: their grade drops)
AGG.rower = function(plan, res)
	local r = res[1]
	if not r or r.strokes == 0 then
		return 0
	end
	return clamp(r.sum / r.strokes, 0, 1) * clamp(r.strokes / math.max(1, 0.8 * r.expected), 0, 1)
end
AGG.icebath = function(plan, res)
	local r = res[1]
	if not r then
		return 0
	end
	return 0.6 * clamp(r.calm / r.duration / W.TIMED_FULL, 0, 1) + 0.4 * clamp(r.good / math.max(1, 0.85 * r.expected), 0, 1)
end
AGG.massage = function(plan, res)
	local r = res[1]
	if not r then
		return 0
	end
	return 0.6 * r.pickSum / math.max(1, r.rounds) + 0.4 * clamp((r.relax - 0.5 * r.stray) / math.max(1, r.strokes), 0, 1)
end
function W.SaunaScore(r)
	local cut = clamp(r.w / math.max(0.1, r.goal), 0, 1)
	local safe = 1 - clamp(r.danger / 5, 0, 1)
	return (0.7 * cut + 0.3 * safe) * (0.5 ^ r.faints)
end
AGG.sauna = function(plan, res)
	return res[1] and W.SaunaScore(res[1]) or 0
end
W.Agg = AGG

-- the extra boxing rounds' share of their drills (DrillScore's own AGG.reaction / AGG.shadow call these)
function W.ReboundScore(seg, r)
	if not r then
		return 0
	end
	if r.ok then
		return 1 - 0.4 * math.abs(r.dt or 0) / seg.w
	end
	return r.punched and 0.25 or 0
end

------------------------------------------------------------------------
-- Plans (Training.DrillPlan draws these; r = a Random)
------------------------------------------------------------------------
local FOOTWORK = {
	{ name = "BOX STEP", steps = { "F", "R", "B", "L" } },
	{ name = "IN & OUT", steps = { "F", "B", "F", "B" } },
	{ name = "CIRCLE LEFT", steps = { "L", "L", "F", "L" } },
	{ name = "CIRCLE RIGHT", steps = { "R", "R", "F", "R" } },
	{ name = "L-STEP", steps = { "F", "L", "F", "L" } },
	{ name = "ANGLE OUT", steps = { "F", "R", "R", "B" } },
}
W.Footwork = FOOTWORK
W.MassageGroups = { "back", "shoulders", "legs", "arms", "chest", "core", "neck" }

-- 0 at station level 1 .. 1 at level 5
local function lvf(lv)
	return clamp((lv - 1) / 4, 0, 1)
end
W.LevelFrac = lvf

local function repGap(Wt, set, rep)
	if rep > 1 then
		return Wt.lower + Wt.rerack
	end
	return set == 1 and Wt.intro or (Wt.lower + Wt.rerack + Wt.rest + Wt.round)
end
W.RepGap = repGap

local PLAN = {}
-- (every workout: 20-35 s of work, two short sets where there are sets; the zones and tolerances are
-- generous at level 1 and tighten with the level, never past a comfortable floor)
PLAN.bench = function(segs, lv, r, Wt)
	local f = lvf(lv)
	for set = 1, 2 do
		local weak = r:NextNumber() < 0.5 and -1 or 1
		for rep = 1, 3 do
			-- (the drift: gentle on the first bench, a real fight up top; the correction always outpaces it)
			local amp = 0.18 + 0.1 * f + rep * 0.015 + (set - 1) * 0.03
			table.insert(segs, { j = "bench", set = set, rep = rep, speed = 0.5 - 0.06 * f, sink = 0.15,
				drift = { amp, 1.6 + r:NextNumber() * 1.2, r:NextNumber() * 6.28, amp * 0.6, 3.1 + r:NextNumber() * 1.5, r:NextNumber() * 6.28 },
				bias = weak * (0.05 + 0.03 * rep + 0.05 * (set - 1)), corr = 1.0, tiltMax = 1.2,
				stickLo = 0.42, stickHi = 0.6, stickMult = 0.65 - 0.05 * rep - 0.05 * (set - 1), wait = 4, limit = 6, gap = repGap(Wt, set, rep) })
		end
	end
end
PLAN.deadlift = function(segs, lv, r, Wt)
	local f = lvf(lv)
	for set = 1, 2 do
		for rep = 1, 3 do
			table.insert(segs, { j = "deadlift", set = set, rep = rep, sweep = 0.5 + 0.25 * f + 0.03 * rep, c = 0.5, w = 0.13 - 0.04 * f,
				speed = 0.5, stickLo = 0.32, stickHi = 0.58, stickMult = 0.5 - 0.04 * (set - 1), drop = 0.5,
				drain = 0.22 + 0.08 * f + 0.015 * rep + 0.03 * (set - 1), gripTap = 0.35, wait = 4, limit = 6, gap = repGap(Wt, set, rep) })
		end
	end
	-- the finisher: the NECK HARNESS - a short steady hold (the traps and the neck the deadlift loads)
	table.insert(segs, W.GaugeSeg("NECK HARNESS", f, r, Wt.lower + Wt.rerack + Wt.rest + Wt.round))
end
-- a short hold gauge (the neck harness, the forearm squeeze): the band is wide on the first station and
-- narrows with the level; the tremor grows the longer you hold (a full hold is 60% of the time in it)
function W.GaugeSeg(name, f, r, gap)
	local mid = 0.55 + r:NextNumber() * 0.15
	local half = 0.16 - 0.04 * f
	return { j = "gauge", name = name, dur = 6, need = 3.6, lo = mid - half, hi = mid + half, rise = 0.9, fall = 0.7, amp = 0.03 + 0.02 * f, grow = 0.012 + 0.008 * f,
		wave = { 2.2 + r:NextNumber() * 0.8, r:NextNumber() * 6.28, 5.1 + r:NextNumber() * 1.2, r:NextNumber() * 6.28 }, gap = gap }
end
PLAN.squat = function(segs, lv, r, Wt)
	local f = lvf(lv)
	-- set 1: back squats; set 2: the SLED PUSH (four drives, the legs alternating as fast as they go)
	for set = 1, 1 do
		for rep = 1, 3 do
			local width = math.max(0.1, 0.22 - 0.08 * f - 0.006 * rep)
			local lo = 0.6 + r:NextNumber() * 0.14
			table.insert(segs, { j = "squat", set = set, rep = rep, v0 = 0.28, acc = 0.45 + 0.1 * f, lo = lo, hi = lo + width,
				bounce = 0.12, pause = 0.75 - 0.2 * f, lost = 2.5, rise = 0.7 - 0.03 * rep, wait = 4, limit = 5, gap = repGap(Wt, set, rep) })
		end
	end
	-- (a full drive: 4.5 steps a second on the first station, 5.5 on the top one; the reset is part of the
	-- rhythm: drive, settle, drive)
	table.insert(segs, { j = "mash", name = "SLED PUSH", bursts = 4, push = 2.0, reset = 0.8, target = math.floor(9 + 2 * f + 0.5), gap = repGap(Wt, 2, 1) })
end
PLAN.pullup = function(segs, lv, r, Wt)
	local f = lvf(lv)
	-- two sets of three: overhand pull-ups, then close-grip chin-ups (a little quicker to the bar, the
	-- grip drains faster); the chin zone and the sweet band narrow with the level, never past a comfortable
	-- floor (the zone stays ~0.4 s of climb wide, the sweet band ~0.2 s)
	for set = 1, 2 do
		table.insert(segs, { j = "pullup", set = set, rep = 1, reps = 3, name = set == 1 and "PULL-UPS" or "CHIN-UPS",
			speed = 0.6 - 0.05 * f + 0.04 * (set - 1), lo = 0.74 + 0.04 * f, perfLo = 0.87, perfHi = 0.97 - 0.015 * f, ready = 0.12, sink = 1.1,
			drain = 0.2 + 0.06 * f + 0.03 * (set - 1), topDrain = 0.5, regen = 0.35, slipGrip = 0.35, wait = 4, limit = 11 - f,
			gap = set == 1 and Wt.intro or (Wt.lower + Wt.rest + Wt.round) })
	end
end
PLAN.curls = function(segs, lv, r, Wt)
	local f = lvf(lv)
	-- set 1: alternating curls, up one beat (hold) and a beat to lower; set 2: tempo curls (two-beat squeeze)
	-- (six and four curls: with the grip finisher the session stays near half a minute)
	local bpm1 = math.floor(72 + 12 * f)
	local notes1, lane = {}, r:NextNumber() < 0.5 and "L" or "R"
	for k = 0, 5 do
		table.insert(notes1, { lane, k * 2, k * 2 + 1 })
		lane = lane == "L" and "R" or "L"
	end
	table.insert(segs, { j = "tempo", name = "ALTERNATING CURLS", bpm = bpm1, beat = 60 / bpm1, lead = 1.2, notes = notes1, hitW = 0.32, perfW = 0.13 - 0.04 * f, relW = 0.32 - 0.07 * f, gap = Wt.intro })
	local bpm2 = math.floor(78 + 14 * f)
	local notes2 = {}
	local at = 0
	for k = 1, 4 do
		local hold = (k == 3 and lv >= 3) and 3 or 2
		table.insert(notes2, { lane, at, at + hold })
		lane = lane == "L" and "R" or "L"
		at += hold + 1
	end
	table.insert(segs, { j = "tempo", name = "TEMPO CURLS", bpm = bpm2, beat = 60 / bpm2, lead = 1.2, notes = notes2, hitW = 0.3, perfW = 0.12 - 0.04 * f, relW = 0.3 - 0.07 * f, gap = Wt.rest + Wt.round })
	-- the finisher: a FOREARM GRIP squeeze (the grip the curls tired) held steady
	table.insert(segs, W.GaugeSeg("FOREARM GRIP", f, r, Wt.rest + Wt.round))
end
PLAN.treadmill = function(segs, lv, r, Wt)
	local f = lvf(lv)
	local program = {}
	local t, mph, incl = 0, 4, 0
	-- (whole-mph steps: a change of pace is a few presses, not a dozen)
	local names = { "WARM-UP", "TEMPO", "HILL", "SPRINT" }
	for k = 1, 4 do
		local name = names[k]
		if name == "WARM-UP" then
			mph, incl = 5, 1
		elseif name == "TEMPO" then
			mph, incl = 7 + math.floor(r:NextNumber() * 2), 1
		elseif name == "HILL" then
			mph, incl = 6, 4 + math.floor(r:NextNumber() * 2 + 2 * f)
		elseif name == "SPRINT" then
			mph, incl = 9 + math.floor(r:NextNumber() * 2 + 2 * f), 0
		elseif name == "RECOVER" then
			mph, incl = 5, 0
		else
			mph, incl = 10 + math.floor(2 * f + r:NextNumber() * 2), 2
		end
		table.insert(program, { t = t, mph = mph, incl = incl, name = name })
		t += 5 - 0.4 * f
	end
	-- (a change of pace is a few presses: the tolerances keep a comfortable floor of 0.75 mph / 1.25 %)
	table.insert(segs, { j = "treadmill", duration = t, program = program, mph0 = 3, incl0 = 0, stepMph = 1, tolMph = 1.0 - 0.25 * f, tolIncl = 1.75 - 0.5 * f,
		mphMin = 1, mphMax = 14, inclMax = 12, gap = Wt.intro })
	-- then the ROAD PACE lane: stride with the pacer's band, breathe on the cues (every ~2.4 s)
	local legs, breaths = {}, {}
	local band = 0.13 - 0.03 * f
	for k, ph in ipairs({ { 0, 0.45, "EASY" }, { 3.5, 0.62, "PICK IT UP" }, { 7, 0.5, "SETTLE" } }) do
		legs[k] = { t = ph[1], lo = ph[2] - band, hi = ph[2] + band, name = ph[3] }
	end
	for b = 1.5, 9.6, 2.4 do
		table.insert(breaths, math.floor(b * 100 + 0.5) / 100)
	end
	table.insert(segs, { j = "road", name = "ROAD PACE", duration = 10, legs = legs, breaths = breaths, breathW = 0.4 - 0.08 * f, v0 = 0.35, kick = 0.07, decay = 0.22,
		gap = Wt.rest + Wt.round })
end
PLAN.bike = function(segs, lv, r, Wt)
	local f = lvf(lv)
	local hill = {}
	local t = 0
	local profile = { { 0, "FLAT" }, { 4 + math.floor(3 * f + r:NextNumber() * 2), "CLIMB" }, { 7 + math.floor(4 * f), "STEEP" }, { -4, "DESCENT" }, { 6 + math.floor(r:NextNumber() * 3), "FINAL CLIMB" } }
	for _, p in ipairs(profile) do
		table.insert(hill, { t = t, grade = p[1], name = p[2] })
		t += 5
	end
	table.insert(segs, { j = "bike", duration = t, hill = hill, gears = 6, gear0 = 4, lo = 58, hi = 100 - 6 * f, gap = Wt.intro })
end
PLAN.rower = function(segs, lv, r, Wt)
	local f = lvf(lv)
	local pieces = { { t = 0, spm = 20, name = "STEADY STATE" }, { t = 8, spm = 24 + math.floor(2 * f), name = "RATE UP" }, { t = 16, spm = 28 + math.floor(4 * f), name = "SPRINT FINISH" } }
	table.insert(segs, { j = "rower", duration = 24, pieces = pieces, drive = 0.8 - 0.1 * f, finishLo = 0.8 + 0.08 * f, catchW = 0.15, gap = Wt.intro })
end
PLAN.icebath = function(segs, lv, r, Wt)
	local f = lvf(lv)
	local w1 = 5 + math.floor(r:NextNumber() * 3)
	table.insert(segs, { j = "icebath", duration = 26, inhale = 3, exhale = 5, s0 = 0.35, cold = 0.045 + 0.02 * f, calmRate = 0.16, waveMult = 2.4,
		waves = { { w1, 3 }, { w1 + 10 + math.floor(r:NextNumber() * 3), 3 } }, gap = Wt.intro })
end
PLAN.stretch = function(segs, lv, r, Wt, params)
	local f = lvf(lv)
	local names = params.stretchNames or {}
	for k = 1, 4 do
		local width = 0.24 - 0.08 * f
		local lo = 0.45 + r:NextNumber() * 0.15
		table.insert(segs, { j = "stretch", name = names[k], pose = (k - 1) % 3, dur = 5, lo = lo, hi = lo + width, slide = 0.1 + 0.06 * f,
			sinkRate = 0.4, ease = 0.26, overMargin = 0.08, gap = k == 1 and Wt.intro or Wt.round })
	end
end
PLAN.massage = function(segs, lv, r, Wt, params)
	local G = W.MassageGroups
	local given = type(params.sore) == "table" and params.sore or {}
	local sore, lit = {}, 0
	for i, g in ipairs(G) do
		sore[i] = clamp(tonumber(given[g]) or 0, 0, 1)
		if sore[i] >= 0.08 then
			lit += 1
		end
	end
	-- nothing sore enough to tell apart: the therapist finds the tight spots (still on the map)
	if lit < 3 then
		for _ = 1, 4 do
			local i = r:NextInteger(1, #G)
			sore[i] = math.max(sore[i], 0.2 + r:NextNumber() * 0.6)
		end
	end
	for i = 1, #sore do
		sore[i] = math.floor(sore[i] * 100 + 0.5) / 100
	end
	table.insert(segs, { j = "massage", groups = table.clone(G), sore = sore, rounds = 3, chooseT = 6, strokes = 4, beat = 0.9, firstStroke = 0.8,
		hitW = 0.45, perfW = 0.2, gap = Wt.intro })
end
PLAN.chamber = function(segs, lv, r, Wt)
	local f = lvf(lv)
	local depth = 1.3 + 0.1 * f
	-- down to depth, a deeper stage in the middle, back to depth, then up to the surface
	table.insert(segs, { j = "chamber", duration = 26, profile = { { 0, 1 }, { 6, depth }, { 9, depth }, { 11, depth + 0.12 }, { 15, depth + 0.12 }, { 17, depth }, { 20, depth }, { 26, 1 } },
		rise = 0.12, vent = 0.1, leak = 0.025 + 0.01 * f, leakWave = 0.8,
		earRate = 2.0 + 0.5 * f, tol = 0.08 - 0.02 * f, maxP = 1.6, gap = Wt.intro })
end
PLAN.sauna = function(segs, lv, r, Wt)
	local f = lvf(lv)
	table.insert(segs, { j = "sauna", duration = 26, t0 = 0.3, heat = 0.04 + 0.01 * f, cool = 0.07, lossBase = 0.055, lossT = 0.06, goal = 1.4 + 0.2 * f, gap = Wt.intro })
end

-- the segments of a new-style drill (nil for a kind this module doesn't draw)
function W.Plan(kind, lv, params, r, Wt)
	local make = PLAN[kind]
	if not make then
		return nil
	end
	local segs = {}
	make(segs, math.max(1, lv), r, Wt, type(params) == "table" and params or {})
	return segs
end

-- DrillScore wires these in (its judges, aggregates and minimum times)
function W.Install(DrillScore, JT, AT)
	local tapHold = DrillScore.TapHold
	for name, make in pairs(J) do
		JT[name] = function(seg, M)
			return make(seg, M, tapHold)
		end
	end
	for kind, fn in pairs(AGG) do
		AT[kind] = fn
	end
end

-- the shortest honest length of a segment of these judges (DrillScore.MinTime)
function W.MinTime(seg)
	local make = J[seg.j]
	if not make then
		return nil
	end
	local ok, s = pcall(make, seg, 0, function()
		return nil
	end)
	return ok and s and s.minTime or 0
end

return W
