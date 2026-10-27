--!nocheck
-- tools/sim/test_walkstable.luau: the walk under Studio's conditions, through the real Animator (v9_anim.luau):
--   * frame timing: a 60 Hz client with wandering frame times whose physics advances in whole 240 Hz steps (studio),
--     the same frame times with exact travel (wander), a 240 Hz client, and 60 Hz with 0.1 / 0.25 s hitches (spike):
--     no NaN, the head and pelvis sway stay small, and the frame-to-frame roughness of the trunk, head and pelvis stays
--     near the steady 60 Hz walk's (the gait's own motion), never a jitter
--   * Roblox's own animation: the Animate script on the local character is switched off and every track it starts is
--     stopped (ProcAnim on the model); released (climbing) it comes back; on the ground again it is off again
--   * a Humanoid's AutoRotate snap turns (the snapturn clip: quarter turns at 18 rad/s on WASD, a reversal): no bank into
--     them, the head's lead, the chest / pelvis twist and the pelvis' lag behind the root bounded; a held curve still
--     banks and the head still leads a turn in place; a start's forward lean bounded
--   * [Studio] the run as /wcbdiag sampled it (W held at 6.5 studs/s, then Shift: 16 in one frame) on a rig of the
--     user's leg (2.67 studs), at 30 Hz, on Studio's wandering frames and on scattered 1/80..1/28 s frames: a regular
--     cadence and alternating steps with a flight between them from the first stride on, no swing held for a stride,
--     the hip / knee / foot clearance of a person's run at ~5 m/s, no planted-foot slide (the sim's contact and the
--     diagnostic's own 10 Hz verdict), a small pelvis bounce, a slight lean, swinging arms
--   * [Studio] strafing (the strafe / strafe16 / strafering / strafeturn clips): the feet never cross, the planted ones
--     hold, the pelvis stays level and the trunk upright, alternating regular contacts, a side step's legs (abducted,
--     no fore-aft swing), the foot turned with the shin, and no joint pops as the direction flips, under jittery frames
--   * [Studio] the walk as a gait lab reads it, its start and stop, the run's instant stop, Shift let go, steering a walk
--     and a run (no side-step / flip handling), and the pure forward run against 6bb9a68's recorded run (the stance,
--     the pelvis, the trunk, the arms and the contact timing as they were, the swing's clearance under 30 % of the leg),
--     on the 78-inch rig and on heightScale 1.00
--   lune run tools/sim/test_walkstable.luau            (~90 s; the clips land in tools/sim/out/walkstable)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Host = require("./host")

local root = Host.FindRoot()
local OUT = root .. "/tools/sim/out/walkstable"

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

-- lune itself (the one running this test, when it is on the PATH; else cargo's)
local function luneBin()
	for _, cand in ipairs({ "lune", (process.env.HOME or "/root") .. "/.cargo/bin/lune", "/root/.cargo/bin/lune" }) do
		local ok, r = pcall(process.exec, cand, { "--version" })
		if ok and r.ok then
			return cand
		end
	end
	return "lune"
end

local TIMINGS = { "steady", "studio", "wander", "hz240", "hz30", "spike" }
local args = { "run", "tools/sim/v9_anim.luau", "--tiers", "3", "--clips", "walk,snapturn,turn,curve,startstop", "--no-mesh", "--nopen",
	"--frames", "1", "--timing", table.concat(TIMINGS, ","), "--out", OUT }
local r = process.exec(luneBin(), args, { cwd = root })
check("v9_anim runs", r.ok, (r.stderr or "") .. (r.stdout or ""):sub(-600))
if not r.ok then
	print(string.format("test_walkstable: %d passed, %d failed", pass, fail))
	process.exit(1)
end
local metrics = serde.decode("json", fs.readFile(OUT .. "/metrics.json"))
local byKey = {}
for _, m in ipairs(metrics) do
	byKey[m.clip .. (m.timing and ("_" .. m.timing) or "")] = m
end

------------------------------------------------------------------------
-- the walk at every frame timing
------------------------------------------------------------------------
-- roughness per 1/60 s (degrees; studs for the offsets): the steady walk's own numbers are about trunk roll 0.5,
-- yaw 0.55, head pitch 0.1, head x 0.0016, pelvis y 0.04; studio's about twice that (the root's travel comes in 240 Hz
-- quanta); a hitch of 0.25 s moves the whole gait 0.3 of a cycle in one frame
local CAP = {
	steady = { pitch = 0.5, roll = 1.0, yaw = 1.0, headPitch = 0.4, headRoll = 0.3, headX = 0.006, ltX = 0.012, ltY = 0.07 },
	hz240 = { pitch = 0.5, roll = 1.0, yaw = 1.0, headPitch = 0.4, headRoll = 0.3, headX = 0.006, ltX = 0.012, ltY = 0.07 },
	-- (a 30 Hz phone: every frame is two 60 Hz ones, the roughness per 1/60 s window reads a whole frame's motion)
	hz30 = { pitch = 0.8, roll = 2.0, yaw = 2.0, headPitch = 0.8, headRoll = 0.6, headX = 0.012, ltX = 0.024, ltY = 0.14 },
	wander = { pitch = 0.6, roll = 1.6, yaw = 1.8, headPitch = 0.5, headRoll = 0.35, headX = 0.008, ltX = 0.02, ltY = 0.09 },
	studio = { pitch = 0.6, roll = 1.6, yaw = 1.8, headPitch = 0.5, headRoll = 0.35, headX = 0.008, ltX = 0.02, ltY = 0.09 },
	-- (the single 0.25 s hitch: whatever gait phase it lands on, the pelvis never dips more than the per-frame cap of
	-- AnimLoco.feet, 0.21 studs, in that frame)
	spike = { pitch = 1.0, roll = 4.0, yaw = 9.0, headPitch = 0.9, headRoll = 0.6, headX = 0.02, ltX = 0.05, ltY = 0.16 },
}
local steady = byKey.walk_steady
check("steady walk recorded", steady ~= nil)
for _, timing in ipairs(TIMINGS) do
	local m = byKey["walk_" .. timing]
	check("walk " .. timing .. " recorded", m ~= nil)
	if m then
		local j = m.jitter
		check("walk " .. timing .. ": no NaN", j.nan == false)
		-- ([Studio] "sways side to side": the pelvis offset is capped at 0.06 peak to peak and its roll at 4 degrees + the
		-- bank; the head stays on its line)
		check("walk " .. timing .. string.format(": head sway %.3f, pelvis sway %.3f, pelvis roll %.1f", m.headSwayX, m.pelvisSwayX, m.pelvisRollDeg),
			m.headSwayX <= 0.06 and m.pelvisSwayX <= 0.07 and m.pelvisRollDeg <= 5)
		local cap = CAP[timing]
		local bad = {}
		for k, lim in pairs(cap) do
			if (j[k] or math.huge) > lim then
				table.insert(bad, string.format("%s %.4f > %.4f", k, j[k] or -1, lim))
			end
		end
		check("walk " .. timing .. ": roughness per 1/60 s within caps", #bad == 0, table.concat(bad, ", "))
		if steady and timing ~= "steady" and timing ~= "spike" then
			-- never more than two and a half times the steady walk's own frame-to-frame motion
			local worse = {}
			for _, k in ipairs({ "roll", "yaw", "headPitch", "headRoll", "headX" }) do
				if j[k] > 2.6 * steady.jitter[k] + 0.05 then
					table.insert(worse, string.format("%s %.3f vs %.3f", k, j[k], steady.jitter[k]))
				end
			end
			check("walk " .. timing .. ": roughness near the steady walk's", #worse == 0, table.concat(worse, ", "))
		end
		-- Roblox's own tracks
		local an = m.animate or {}
		check("walk " .. timing .. ": Animate script off, no track playing, ProcAnim", an.disabled == true and an.playing == 0 and an.procAnim == true
			and (an.started or 0) >= 1, string.format("disabled %s playing %s started %s procAnim %s", tostring(an.disabled), tostring(an.playing),
			tostring(an.started), tostring(an.procAnim)))
		if timing == "steady" then
			check("released (climbing): Animate back on, its track left playing", an.climbEnabled == true and (an.climbPlaying or 0) >= 1,
				string.format("%s %s", tostring(an.climbEnabled), tostring(an.climbPlaying)))
			check("on the ground again: Animate off, tracks stopped", an.backDisabled == true)
		end
	end
end

------------------------------------------------------------------------
-- turns: a Humanoid's snap turns, a held curve, a turn in place, a start
------------------------------------------------------------------------
local function within(range, lo, hi)
	return range ~= nil and range[1] >= lo and range[2] <= hi
end
local snap = byKey.snapturn
check("snapturn recorded", snap ~= nil)
if snap then
	local g, st = snap.gait, snap.maxFrameStep
	check(string.format("snap turns: no bank (trunk roll %.1f..%.1f)", g.trunkRoll[1], g.trunkRoll[2]), within(g.trunkRoll, -9, 9))
	check(string.format("snap turns: the head's lead bounded (%.1f..%.1f)", g.headYaw[1], g.headYaw[2]), within(g.headYaw, -26, 26))
	check(string.format("snap turns: chest / pelvis twist bounded (%.1f..%.1f)", g.twist[1], g.twist[2]), within(g.twist, -32, 32))
	check(string.format("snap turns: the pelvis follows the root (lag %.1f..%.1f)", g.pelvisYaw[1], g.pelvisYaw[2]), within(g.pelvisYaw, -26, 26))
	check(string.format("snap turns: per-frame twist %.1f roll %.2f", st.twist, st.trunkRoll), st.twist <= 8 and st.trunkRoll <= 0.9)
	check(string.format("snap turns: the forward lean bounded (trunk pitch %.1f)", g.trunkPitch[1]), g.trunkPitch[1] >= -11)
	local nan = false
	for k, v in pairs(st) do
		if v ~= v then
			nan = true
		end
	end
	check("snap turns: no NaN", not nan)
end
local curve = byKey.curve
check("curve recorded", curve ~= nil)
if curve then
	local g = curve.gait
	check(string.format("held curve: still banks into it (trunk roll %.1f)", g.trunkRoll[1]), g.trunkRoll[1] <= -3 and g.trunkRoll[1] >= -10)
	check(string.format("held curve: the head still leads (%.1f)", g.headYaw[2]), g.headYaw[2] >= 10 and g.headYaw[2] <= 26)
	check(string.format("held curve: per-frame knee step %.1f", curve.maxFrameStep.knee), curve.maxFrameStep.knee <= 18)
end
local turn = byKey.turn
check("turn recorded", turn ~= nil)
if turn then
	local g = turn.gait
	check(string.format("turn in place: the head leads, bounded (%.1f)", g.headYaw[2]), g.headYaw[2] >= 10 and g.headYaw[2] <= 26)
	check(string.format("turn in place: no bank (trunk roll %.1f..%.1f)", g.trunkRoll[1], g.trunkRoll[2]), within(g.trunkRoll, -2, 2))
end
local ss = byKey.startstop
check("startstop recorded", ss ~= nil)
if ss then
	local g = ss.gait
	check(string.format("start: the forward lean bounded (trunk pitch %.1f)", g.trunkPitch[1]), g.trunkPitch[1] >= -10 and g.trunkPitch[1] <= -3)
	check(string.format("start / stop: no bank (trunk roll %.1f..%.1f)", g.trunkRoll[1], g.trunkRoll[2]), within(g.trunkRoll, -1.5, 1.5))
end

------------------------------------------------------------------------
-- [Studio] dt independence: the same walk at 30, 60 and 240 Hz (Studio runs at 240 Hz with the frame rate uncapped, a
-- phone at 30): every filter is exp(-k dt), so the stride, the sway and the roll come out the same
------------------------------------------------------------------------
do
	local a, b, c = byKey.walk_hz30, byKey.walk_steady, byKey.walk_hz240
	if a and b and c then
		local function near(k, tol)
			return math.abs(a[k] - b[k]) <= tol and math.abs(c[k] - b[k]) <= tol
		end
		check(string.format("dt independence: period %.3f / %.3f / %.3f (30 / 60 / 240 Hz)", a.period, b.period, c.period), near("period", 0.03))
		check(string.format("dt independence: pelvis sway %.3f / %.3f / %.3f", a.pelvisSwayX, b.pelvisSwayX, c.pelvisSwayX), near("pelvisSwayX", 0.01))
		check(string.format("dt independence: pelvis roll %.1f / %.1f / %.1f", a.pelvisRollDeg, b.pelvisRollDeg, c.pelvisRollDeg), near("pelvisRollDeg", 0.8))
		check(string.format("dt independence: head sway %.3f / %.3f / %.3f", a.headSwayX, b.headSwayX, c.headSwayX), near("headSwayX", 0.015))
		check(string.format("dt independence: knee range %.0f..%.0f / %.0f..%.0f / %.0f..%.0f", a.gait.kneeL[1], a.gait.kneeL[2], b.gait.kneeL[1],
			b.gait.kneeL[2], c.gait.kneeL[1], c.gait.kneeL[2]),
			math.abs(a.gait.kneeL[2] - b.gait.kneeL[2]) <= 4 and math.abs(c.gait.kneeL[2] - b.gait.kneeL[2]) <= 4)
	else
		check("dt independence: the three timings recorded", false)
	end
end

------------------------------------------------------------------------
-- [Studio] a server-moved NPC (an Ambient walker on MoveTo) as a client sees it: the root's position arrives in
-- replication steps (held two frames, then three frames' travel at once) while its replicated velocity reads steady.
-- The gait must run on a smooth speed - no spikes, no fast jitter - with the planted feet holding and the knees bending
------------------------------------------------------------------------
local OUT_NPC = OUT .. "_npc"
local rN = process.exec(luneBin(), { "run", "tools/sim/v9_anim.luau", "--tiers", "3", "--clips", "walk", "--no-mesh", "--nopen", "--frames", "1",
	"--timing", "replicated,steady", "--npc", "--out", OUT_NPC }, { cwd = root })
check("v9_anim runs the NPC walk on a replicated root", rN.ok, (rN.stderr or "") .. (rN.stdout or ""):sub(-600))
if rN.ok then
	local byT = {}
	for _, m in ipairs(serde.decode("json", fs.readFile(OUT_NPC .. "/metrics.json"))) do
		if m.clip == "walk" then
			byT[m.timing] = m
		end
	end
	local m, ms = byT.replicated, byT.steady
	check("NPC replicated walk recorded", m ~= nil and ms ~= nil)
	if m and ms then
		local v = m.speed
		check(string.format("NPC: the sensed speed never spikes (%.2f..%.2f at %.1f, largest step %.2f / frame)", m.sensedMin, m.sensedMax, v, m.sensedStep),
			m.sensedMax <= v * 1.12 and m.sensedMin >= v * 0.85 and m.sensedStep <= 0.35)
		check(string.format("NPC: a smooth gait (sensed step %.2f on the steady root)", ms.sensedStep), ms.sensedStep <= 0.2)
		check(string.format("NPC: the knees bend (%.0f..%.0f)", m.gait.kneeL[1], m.gait.kneeL[2]), m.gait.kneeL[2] > 40)
		check(string.format("NPC: head sway %.3f, pelvis roll %.1f on the stepping root", m.headSwayX, m.pelvisRollDeg), m.headSwayX <= 0.07 and m.pelvisRollDeg <= 5.5)
		check(string.format("NPC: roughness on the stepping root (trunk roll %.2f yaw %.2f head x %.4f)", m.jitter.roll, m.jitter.yaw, m.jitter.headX),
			m.jitter.roll <= 2.0 and m.jitter.yaw <= 2.5 and m.jitter.headX <= 0.012 and m.jitter.nan == false)
		check(string.format("NPC: the same stride as a steady root (period %.3f vs %.3f)", m.period, ms.period), math.abs(m.period - ms.period) <= 0.05)
	end
end

------------------------------------------------------------------------
-- [Studio] the Avatar Joint Upgrade's rig: AnimationConstraints between the RigAttachments instead of Motor6Ds (what
-- Studio built for the player and every NPC: the Animator's joint reads threw and nobody was driven - feet sliding 0.6
-- studs a tick, knees never bending). The same walk on that rig must come out the same as on the Motor6D rig
------------------------------------------------------------------------
local OUT_AC = OUT .. "_ac"
local rAC = process.exec(luneBin(), { "run", "tools/sim/v9_anim.luau", "--tiers", "3", "--clips", "walk", "--no-mesh", "--nopen", "--frames", "1",
	"--joints", "ac", "--out", OUT_AC }, { cwd = root })
check("v9_anim runs on an AnimationConstraint rig", rAC.ok, (rAC.stderr or "") .. (rAC.stdout or ""):sub(-600))
if rAC.ok then
	local mAC
	for _, m in ipairs(serde.decode("json", fs.readFile(OUT_AC .. "/metrics.json"))) do
		if m.clip == "walk" then
			mAC = m
		end
	end
	check("AC rig: walk recorded", mAC ~= nil)
	if mAC and steady then
		local g, gs = mAC.gait, steady.gait
		check(string.format("AC rig: the knees bend as on the Motor6D rig (%.0f..%.0f vs %.0f..%.0f)", g.kneeL[1], g.kneeL[2], gs.kneeL[1], gs.kneeL[2]),
			math.abs(g.kneeL[1] - gs.kneeL[1]) < 1.5 and math.abs(g.kneeL[2] - gs.kneeL[2]) < 1.5 and g.kneeL[2] > 40)
		check(string.format("AC rig: the same stride (period %.3f vs %.3f)", mAC.period, steady.period), math.abs(mAC.period - steady.period) < 0.01)
		check(string.format("AC rig: the same sway / roll (%.3f / %.1f vs %.3f / %.1f)", mAC.pelvisSwayX, mAC.pelvisRollDeg, steady.pelvisSwayX, steady.pelvisRollDeg),
			math.abs(mAC.pelvisSwayX - steady.pelvisSwayX) < 0.005 and math.abs(mAC.pelvisRollDeg - steady.pelvisRollDeg) < 0.3)
		check(string.format("AC rig: the planted feet hold (slide %.3f / %.3f)", g.slideL, g.slideR), g.slideL < 0.03 and g.slideR < 0.03)
	end
end

------------------------------------------------------------------------
-- [Studio] the run: "the running is still messed up". /wcbdiag on the user's rig (R15, HipHeight 3.03, legLen 2.67,
-- heightScale 1.13, lod 3) holding W, then Shift (6.5 -> 16 studs/s in a frame), sampled at 10 Hz: the hip swinging
-- -20 .. 75 in jumps, the knee folded to 134, the feet kicked up 1.3 studs (half the leg), one foot in the air for
-- 0.7 s after the switch and "BAD the planted feet slide". The sim reproduced every one of those numbers on a 2.69-stud
-- leg (the swing timed to the schedule's next touchdown after an early toe-off; a 1.3-stud lift peaking under the hip;
-- the foot brought to rest in the world at the touchdown, a stud past the spot). A person running at ~5 m/s, scaled
-- to the leg: ~165-180 steps / min, hip flexion to ~45-55 relative to the pelvis, swing knee ~100-120, the foot well
-- under half the leg off the ground, a flight phase between alternating steps, the pelvis bouncing ~a tenth of the leg
------------------------------------------------------------------------
local OUT_RUN = OUT .. "_run"
local RUN_TIMINGS = { "hz30", "studio", "rough" }
local rR = process.exec(luneBin(), { "run", "tools/sim/v9_anim.luau", "--tiers", "3", "--clips", "shift", "--no-mesh", "--nopen", "--frames", "1",
	"--height", "78", "--timing", table.concat(RUN_TIMINGS, ","), "--out", OUT_RUN }, { cwd = root })
check("v9_anim runs the walk -> run switch", rR.ok, (rR.stderr or "") .. (rR.stdout or ""):sub(-600))
if rR.ok then
	local byT = {}
	for _, m in ipairs(serde.decode("json", fs.readFile(OUT_RUN .. "/metrics.json"))) do
		if m.clip == "shift" then
			byT[m.timing] = m
		end
	end
	local function median(xs)
		local c = table.clone(xs)
		table.sort(c)
		return #c > 0 and c[math.floor((#c + 1) / 2)] or 0
	end
	for _, timing in ipairs(RUN_TIMINGS) do
		local m = byT[timing]
		check("run " .. timing .. " recorded", m ~= nil)
		if m then
			local tag = "run " .. timing .. ": "
			local L = m.legLen or 2.67
			check(tag .. string.format("the rig's leg is the user's (%.2f studs, lod %s)", L, tostring(m.lod)), L > 2.55 and L < 2.8 and m.lod == 3)
			-- the contacts from the switch on: swings, stances, touchdowns in order
			local up, swings, stances, touch, flights = {}, {}, {}, {}, {}
			local lastUp, lastDown = {}, {}
			for _, e in ipairs(m.contacts or {}) do
				if e.down then
					if lastUp[e.s] then
						table.insert(swings, { t = lastUp[e.s], d = e.t - lastUp[e.s] })
					end
					table.insert(touch, e)
					-- (the other foot left before this one came down: both in the air between)
					local o = e.s == "L" and "R" or "L"
					if lastUp[o] and (not lastDown[o] or lastDown[o] < lastUp[o]) then
						table.insert(flights, e.t - lastUp[o])
					else
						table.insert(flights, 0)
					end
					lastDown[e.s] = e.t
				else
					if lastDown[e.s] then
						table.insert(stances, e.t - lastDown[e.s])
					end
					lastUp[e.s] = e.t
				end
				up[e.s] = true
			end
			local swD = {}
			local longest, longestAt = 0, 0
			for _, sw in ipairs(swings) do
				table.insert(swD, sw.d)
				if sw.d > longest then
					longest, longestAt = sw.d, sw.t
				end
			end
			local mSw = median(swD)
			check(tag .. string.format("no swing held for a stride after the switch (longest %.3f s at %.2f, median %.3f)", longest, longestAt, mSw),
				#swD >= 6 and longest <= 1.15 * mSw and longest <= 0.6)
			-- (contacts and steps quantised to the frame: 33 ms at 30 Hz)
			local stLo, stHi = math.huge, 0
			for i, d in ipairs(stances) do
				if i > 1 then
					stLo, stHi = math.min(stLo, d), math.max(stHi, d)
				end
			end
			check(tag .. string.format("short, even contacts (%.3f..%.3f s)", stLo, stHi), stLo >= 0.13 and stHi <= 0.26 and stHi - stLo <= 0.075)
			-- alternating steps at a regular interval, half the period each: the first two after the switch settle the
			-- feet's half-cycle (within a fifth), every later one within 12 % (a 30 Hz frame is 9 % of a step)
			local alt, steps = true, {}
			for i = 2, #touch do
				alt = alt and touch[i].s ~= touch[i - 1].s
				table.insert(steps, touch[i].t - touch[i - 1].t)
			end
			local mStep = median(steps)
			local worst, worst0 = 0, 0
			for i, d in ipairs(steps) do
				if i <= 2 then
					worst0 = math.max(worst0, math.abs(d - mStep) / mStep)
				else
					worst = math.max(worst, math.abs(d - mStep) / mStep)
				end
			end
			check(tag .. string.format("alternating steps of %.3f s: the first two within %.0f %%, every later one within %.0f %%", mStep, worst0 * 100,
				worst * 100), alt and #steps >= 6 and worst0 <= 0.2 and worst <= 0.12)
			local spm = 120 / m.period
			check(tag .. string.format("cadence %.0f steps / min (period %.3f, steps %.3f)", spm, m.period, mStep), spm >= 160 and spm <= 185
				and math.abs(mStep - m.period / 2) <= 0.05 * m.period)
			local fLo = math.huge
			for i, f in ipairs(flights) do
				if i > 1 then
					fLo = math.min(fLo, f)
				end
			end
			check(tag .. string.format("a flight before every touchdown after the first (shortest %.3f s)", fLo), fLo >= 0.04 and fLo < 0.25)
			-- the run's angles: the steady run (1.5 s after the switch) and the switch itself
			-- (the swing's clearance held to under a third of the leg - [Studio] 0.9 studs, 38 % of a 2.37-stud leg, read as
			-- a sprinter's heel kick: the knee folds a little less with it)
			for _, part in ipairs({ { "steady", m.gait, 62, 0.3 }, { "switch", m.shift, 66, 0.33 } }) do
				local g, nm, hipCap, soleCap = part[2], part[1], part[3], part[4]
				local hip = math.max(g.hipL[2], g.hipR[2])
				local knee = math.max(g.kneeL[2], g.kneeR[2])
				local sole = math.max(g.soleL[2], g.soleR[2])
				check(tag .. string.format("%s: peak hip flexion %.0f (a person's ~45-55; it was 75-90)", nm, hip), hip >= 40 and hip <= hipCap)
				check(tag .. string.format("%s: peak swing knee %.0f (a person's ~90-120; it was 134-136)", nm, knee), knee >= 85 and knee <= 122)
				check(tag .. string.format("%s: foot clearance %.2f studs = %.0f %% of the leg (it was 50 %%)", nm, sole, 100 * sole / L), sole >= 0.15 * L
					and sole <= soleCap * L)
				check(tag .. string.format("%s: the planted feet hold (slide %.3f / %.3f studs)", nm, g.slideL, g.slideR), g.slideL <= 0.08 and g.slideR <= 0.08)
			end
			local g = m.gait
			local bob = g.pelvisY[2] - g.pelvisY[1]
			check(tag .. string.format("the pelvis bounces %.3f studs (%.0f %% of the leg)", bob, 100 * bob / L), bob >= 0.04 * L and bob <= 0.12 * L)
			check(tag .. string.format("a slight forward lean (trunk pitch %.1f..%.1f)", g.trunkPitch[1], g.trunkPitch[2]), g.trunkPitch[1] >= -11
				and g.trunkPitch[2] <= -2)
			check(tag .. string.format("the arms swing (shoulder %.0f..%.0f)", g.shoulderL[1], g.shoulderL[2]), g.shoulderL[2] - g.shoulderL[1] >= 40)
			-- the diagnostic's own 10 Hz verdict, as Studio prints it
			local v = table.concat(m.diag and m.diag.verdicts or {}, "\n")
			check(tag .. "/wcbdiag: planted feet hold", v:find("OK   planted feet hold", 1, true) ~= nil, v:match("[^\n]*planted[^\n]*"))
		end
	end
end

------------------------------------------------------------------------
-- [Studio] "moving side to side still looks weird": the body kept facing (Shift Lock / first person, a boxer facing his
-- man, the AI circling) while he goes off sideways, on the diagonals and backward, the direction flipping (D to A, W to
-- A, a back-diagonal into D), at the town walk (6.5) and at Shift's pace (16), a fighter's footwork in the stance, and
-- with AutoRotate on (the root snapping round toward the new way: sideways to his facing for a moment), each on a 30 Hz
-- phone, Studio's wandering frames and scattered 1/80..1/28 s frames. Before, a side step was the forward walk turned
-- sideways - each foot swept 1.4 studs across under the body, the trailing leg left 2.2 studs out (abducted 42
-- degrees), the leading one crossing under the pelvis, the knees folding to 69, the pelvis bobbing a third of a stud; at
-- 16 the legs splayed to 50-70 degrees; an AutoRotate snap left the planted foot twisted 90-180 degrees under its shin
-- and a landing foot skidded 0.7 studs
------------------------------------------------------------------------
local OUT_ST = OUT .. "_strafe"
local ST_TIMINGS = { "hz30", "studio", "rough" }
local rS = process.exec(luneBin(), { "run", "tools/sim/v9_anim.luau", "--tiers", "3", "--clips", "strafe,strafe16,strafering,strafeturn", "--no-mesh",
	"--nopen", "--frames", "1", "--height", "78", "--timing", table.concat(ST_TIMINGS, ","), "--out", OUT_ST }, { cwd = root })
check("v9_anim runs the strafing clips", rS.ok, (rS.stderr or "") .. (rS.stdout or ""):sub(-600))
if rS.ok then
	local byCT = {}
	for _, m in ipairs(serde.decode("json", fs.readFile(OUT_ST .. "/metrics.json"))) do
		if m.segs then
			byCT[m.clip .. "_" .. m.timing] = m
		end
	end
	local SIDEWAYS = { D = true, A = true, stop = true }
	-- per clip: the lateral gap the feet keep (studs, ankle to ankle across the pelvis), a side step's legs (the most a hip
	-- abducts, the swing knee's peak, the thigh's fore-aft swing; side = the clip steps sideways to its facing), the gap
	-- through a change between sideways ways (D <-> A, a stop), the planted feet's slide and the frame-to-frame floors of
	-- the joints' change. Through a change to or from a forward / diagonal way the pelvis turns with the legs (by up to 43
	-- degrees in a fifth of a second) and the feet are measured across a turning frame: slide, pops and twist only; with
	-- AutoRotate the snap's pivot steps cross under the turning body for a moment, as a person's do
	local SPEC = {
		strafe = { gap = 0.35, side = true, abd = 42, knee = 75, flex = 50, flipGap = 0.2, slide = 0.08, segSlide = 0.08, floor = { knee = 20, hip = 15, abd = 15 } },
		-- (16 studs/s across: a side gallop at a pace no person shuffles at - the legs spread further, the swing knee folds
		-- as a runner's, a reversal brings the feet closer for a frame; a change between it and the forward run folds or
		-- opens the knee as fast as the run's own swing)
		strafe16 = { gap = 0.35, side = true, abd = 56, knee = 90, flex = 50, flipGap = 0.15, slide = 0.08, segSlide = 0.08, floor = { knee = 70, hip = 50, abd = 40 } },
		strafering = { gap = 1.2, side = true, abd = 46, knee = 90, flex = 65, flipGap = 0.9, slide = 0.08, segSlide = 0.08, floor = { knee = 30, hip = 20, abd = 20 } },
		-- (AutoRotate: the body faces the way he goes once the snap is over - a forward walk, whose start from rest and
		-- toe-off after a snap scuff 0.08-0.12 studs (the forward walk's own, untouched here); the snap's pivot steps)
		strafeturn = { gap = 0.35, slide = 0.08, segSlide = 0.13, floor = { knee = 32, hip = 22, abd = 24 } },
	}
	for _, clip in ipairs({ "strafe", "strafe16", "strafering", "strafeturn" }) do
		for _, timing in ipairs(ST_TIMINGS) do
			local m = byCT[clip .. "_" .. timing]
			local tag = clip .. " " .. timing .. ": "
			check(tag .. "recorded", m ~= nil)
			if m then
				local sp = SPEC[clip]
				-- the gait's own frame-to-frame motion, on the clip's steadiest stretch (the forward walk / run, or the first
				-- sideways one): a flip may move a joint no faster than 1.5 times that, and 6 degrees
				local ref = { kneeL = 0, hipL = 0, abdL = 0 }
				for _, sg in ipairs(m.segs) do
					for k in pairs(ref) do
						local r = k:sub(1, -2)
						ref[k] = math.max(ref[k], sg.pops[r .. "L"], sg.pops[r .. "R"])
					end
				end
				for _, sg in ipairs(m.segs) do
					local st = tag .. sg.dir .. " "
					local c = sg.contacts
					check(st .. string.format("feet never cross (gap %.2f studs across the pelvis, the left foot to %.2f, the right to %.2f)", sg.gapMin,
						sg.xLmax, sg.xRmin), sg.gapMin >= sp.gap)
					check(st .. string.format("planted feet hold (slide %.3f / %.3f studs)", sg.slideL, sg.slideR), sg.slideL <= sp.segSlide and sg.slideR <= sp.segSlide)
					check(st .. string.format("pelvis level (roll %.1f..%.1f), little sway (%.3f studs)", sg.roll[1], sg.roll[2], sg.swayX),
						sg.roll[2] - sg.roll[1] <= 8 and math.max(-sg.roll[1], sg.roll[2]) <= 7 and sg.swayX <= 0.2)
					check(st .. string.format("trunk upright (roll %.1f..%.1f)", sg.trunkRoll[1], sg.trunkRoll[2]), sg.trunkRoll[1] >= -6 and sg.trunkRoll[2] <= 6)
					-- (a forward walk's stretch between the changes holds two or three steps: alternating; a sideways one four or more,
					-- each foot's stride regular)
					check(st .. string.format("alternating contacts, a regular stride (%d steps, each foot every %.3f..%.3f s)", c.n, c.strideMin, c.strideMax),
						c.alternating and c.n >= 1 and (not sp.side or c.n < 4 or (c.strideMin > 0 and c.strideMax <= 1.4 * c.strideMin + 0.04)))
					check(st .. string.format("the foot turned with the shin (twist %.0f)", sg.footTwist), sg.footTwist <= 25)
					if sp.side and SIDEWAYS[sg.dir] then
						check(st .. string.format("a side step: hip abducts to %.0f, knee peaks %.0f, the thigh swings fore-aft %.0f..%.0f", sg.abd[2],
							sg.knee[2], sg.flex[1], sg.flex[2]), sg.abd[2] <= sp.abd and sg.knee[2] <= sp.knee and sg.flex[2] - sg.flex[1] <= sp.flex)
					end
				end
				for _, fl in ipairs(m.flips) do
					local ft = tag .. string.format("%s -> %s ", tostring(fl.from), fl.to)
					local p = fl.pops
					check(ft .. string.format("planted feet hold (slide %.3f / %.3f studs)", fl.slideL, fl.slideR), fl.slideL <= sp.slide and fl.slideR <= sp.slide)
					local worst = {}
					for k in pairs(ref) do
						local r = k:sub(1, -2)
						local v, cap = math.max(p[r .. "L"], p[r .. "R"]), math.max(1.5 * ref[k] + 6, sp.floor[r])
						if v > cap then
							table.insert(worst, string.format("%s %.1f > %.1f", r, v, cap))
						end
					end
					check(ft .. "no joint pops (per 1/60 s, against the gait's own)", #worst == 0, table.concat(worst, ", "))
					-- (into a diagonal the pelvis turns with the legs: a runner's forward tilt reads partly as roll in the body's frame)
					check(ft .. string.format("pelvis roll %.1f..%.1f, %.2f a frame", fl.roll[1], fl.roll[2], p.pRoll), math.max(-fl.roll[1], fl.roll[2]) <= 15
						and p.pRoll <= 2)
					check(ft .. string.format("the foot turned with the shin (twist %.0f; it was 120-180 in a snap)", fl.footTwist), fl.footTwist <= 40)
					if sp.flipGap and SIDEWAYS[fl.from] and SIDEWAYS[fl.to] then
						check(ft .. string.format("feet never cross (gap %.2f)", fl.gapMin), fl.gapMin >= sp.flipGap)
					end
					if clip == "strafering" and (fl.to == "D" or fl.to == "A") and SIDEWAYS[fl.from] then
						-- (a boxer's footwork: once the way he goes has turned over, the foot on the side of travel moves first)
						local want = (fl.to == "D") and "R" or "L"
						check(ft .. string.format("the lead foot steps first (%s)", tostring(fl.contacts.firstUp)), fl.contacts.firstUp == want)
					end
				end
				if clip == "strafering" then
					local hi = 0
					for _, sg in ipairs(m.segs) do
						hi = math.max(hi, sg.pelvisY[2] - sg.pelvisY[1])
					end
					check(tag .. string.format("a low bounce (pelvis %.3f studs at most over a stretch)", hi), hi <= 0.28)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- [Studio] "the walk is still messed up" (it swayed side to side before), "the run is messed up again" since the
-- sideways rework (e8bcb8f), and the stop (a Humanoid stops in a frame: a foot hung 0.9 studs up for 0.2-0.3 s, the
-- knees bent 25 degrees for half a second, at rest after 0.8 s). On the 78-inch rig and on heightScale 1.00 (Studio's
-- trace: legLen 2.37), on a 30 Hz phone, Studio's wandering frames and scattered 1/80..1/28 s frames:
--   * the walk at 6.5 as a gait lab reads it (1 stud = 0.9 / legLen m). A person's 105-120 steps / min and +25-30 /
--     -10 degrees of hip are a 1.3 m/s walk; 6.5 studs/s is ~1.9-2.1 m/s on these legs (Froude ~0.45), where nobody
--     walks below ~125 steps / min without overstriding or sliding: a stance of ~0.6 of the cycle sweeps
--     6.5 x 0.6 x T studs under the hip, so the cadence and the hip's range are set by the pace and are held to a
--     person's at that pace; the rest - the knee's strike / loading / swing, the heel-to-toe roll, the clearance,
--     the pelvis bob and sway, the arms, the trunk and the head - to a person's walk
--   * the start, the stop (W let go: 6.5 -> 0 and 16 -> 0 in one frame), Shift let go at a run (16 -> 6.5), steering a
--     walk and a run with the camera (never the side step's or the flip's handling)
--   * the pure forward run against the recorded run of 6bb9a68 (tools/sim/ref_run16_6bb9a68.json), cycle by cycle:
--     the stance, the pelvis, the trunk, the arms and the contact timing as they were; the swing leg folding a little
--     less (its clearance under 30 % of the leg - [Studio] 38 %), the knee over the toes (6bb9a68 turned it 14-20
--     degrees in, away from the toes: e8bcb8f's sign fix in AnimRig.solveLeg)
------------------------------------------------------------------------
local LAB_TIMINGS = { "hz30", "studio", "rough" }
local LAB_RIGS = { { h = "78", tag = "78 in" }, { h = "70", tag = "heightScale 1.00" } }
local REF_RUN = serde.decode("json", fs.readFile(root .. "/tools/sim/ref_run16_6bb9a68.json"))
-- a cycle's profile: NB bins from one left touchdown to the next, each the mean over the cycles from t0 on
local NB = 24
local PKEYS = { "hipL", "hipR", "kneeL", "kneeR", "ankleL", "footPitchL", "shoulderL", "shoulderR", "elbowL", "elbowR", "pelvisY", "headY",
	"trunkPitch", "soleL", "soleR", "kneeDirL", "footYawL" }
local function profileOf(rows, t0)
	local td = {}
	for i = 2, #rows do
		if rows[i].t >= t0 and rows[i - 1].soleL >= 0.03 and rows[i].soleL < 0.03 then
			table.insert(td, i)
		end
	end
	local P, n = {}, 0
	for c = 1, #td - 1 do
		local a, b = td[c], td[c + 1]
		local ta, tb = rows[a].t, rows[b].t
		n += 1
		local j = a
		for bin = 1, NB do
			local tt = ta + (bin - 0.5) / NB * (tb - ta)
			while j < b - 1 and rows[j + 1].t < tt do
				j += 1
			end
			local r0, r1 = rows[j], rows[j + 1]
			local w = math.clamp((tt - r0.t) / math.max(1e-9, r1.t - r0.t), 0, 1)
			for _, k in ipairs(PKEYS) do
				if r0[k] ~= nil and r1[k] ~= nil then
					P[k] = P[k] or table.create(NB, 0)
					P[k][bin] += r0[k] * (1 - w) + r1[k] * w
				end
			end
		end
	end
	for _, v in pairs(P) do
		for i = 1, NB do
			v[i] /= math.max(1, n)
		end
	end
	local period = #td > 1 and (rows[td[#td]].t - rows[td[1]].t) / (#td - 1) or 0
	return P, n, period
end
-- the swinging foot's rise (the foot part's centre, as /wcbdiag reads it) over its planted height: each swing's peak
local function swingRises(rows, t0)
	local planted = {}
	for _, x in ipairs(rows) do
		if x.t >= t0 then
			for _, k in ipairs({ "L", "R" }) do
				if x["sole" .. k] < 0.01 then
					table.insert(planted, x["ankleY" .. k])
				end
			end
		end
	end
	table.sort(planted)
	local base = planted[math.max(1, math.floor((#planted + 1) / 2))] or 0
	local peaks = {}
	for _, k in ipairs({ "L", "R" }) do
		local up, pk = false, -math.huge
		for _, x in ipairs(rows) do
			if x.t >= t0 then
				if x["sole" .. k] > 0.03 then
					up, pk = true, math.max(pk, x["ankleY" .. k])
				elseif up then
					table.insert(peaks, pk - base)
					up, pk = false, -math.huge
				end
			end
		end
	end
	table.sort(peaks)
	return peaks
end
local function seriesOfFile(path)
	local ok, data = pcall(function()
		return serde.decode("json", fs.readFile(path))
	end)
	return ok and data and data.series or nil
end
for _, rg in ipairs(LAB_RIGS) do
	local out = OUT .. "_lab" .. rg.h
	local rL = process.exec(luneBin(), { "run", "tools/sim/v9_anim.luau", "--tiers", "3", "--clips", "walk,run,walkgo,runstop,runwalk,runsteer,walksteer",
		"--no-mesh", "--nopen", "--frames", "1", "--height", rg.h, "--timing", table.concat(LAB_TIMINGS, ","), "--out", out }, { cwd = root })
	check("v9_anim runs the walk / run / stop / steering clips (" .. rg.tag .. ")", rL.ok, (rL.stderr or "") .. (rL.stdout or ""):sub(-600))
	if rL.ok then
		local by = {}
		for _, m in ipairs(serde.decode("json", fs.readFile(out .. "/metrics.json"))) do
			by[m.clip .. "_" .. (m.timing or "steady")] = m
		end
		for _, timing in ipairs(LAB_TIMINGS) do
			local pre = rg.tag .. " " .. timing .. ": "
			-- the walk
			local m = by["walk_" .. timing]
			check(pre .. "walk recorded", m ~= nil and m.walk ~= nil)
			if m and m.walk then
				local w, tag = m.walk, pre .. "walk: "
				check(tag .. string.format("cadence %.0f steps / min (a person's at ~2 m/s; HEAD 129-144)", w.cadence or -1), (w.cadence or 0) >= 120
					and (w.cadence or 0) <= 150)
				check(tag .. string.format("stance %.0f %% of the cycle, double support %.0f %%, no flight (%.1f %%)", 100 * w.stance, 100 * w.doubleSupport,
					100 * w.flight), w.stance >= 0.5 and w.stance <= 0.62 and w.doubleSupport >= 0.025 and w.flight <= 0.005)
				check(tag .. string.format("heel strike on a near-straight knee (%.0f), a loading flex of %.0f, straight by mid-stance (%.0f)", w.kneeStrike,
					w.kneeLoad, w.kneeMid), w.kneeStrike <= 16 and w.kneeLoad >= 14 and w.kneeLoad <= 26 and w.kneeMid <= 12)
				check(tag .. string.format("swing knee %.0f (a person's ~60-65)", w.kneeSwing), w.kneeSwing >= 55 and w.kneeSwing <= 68)
				check(tag .. string.format("hip +%.0f / %.0f (HEAD +38 / -23..-27)", w.hipFlex, w.hipExt), w.hipFlex <= 41 and w.hipExt >= -31)
				check(tag .. string.format("heel first (toes up %.0f at the strike), rolled onto the toes to leave (%.0f)", w.pitchStrike, w.pitchOff),
					w.pitchStrike >= 8 and w.pitchOff <= -35)
				check(tag .. string.format("a small foot clearance (%.1f cm; HEAD 10-12)", w.clearanceCm), w.clearanceCm <= 11)
				check(tag .. string.format("pelvis bob %.1f cm (a person's ~4-5; HEAD 5.1-6.5), sway %.1f cm (~2-4)", w.bobCm, w.swayCm), w.bobCm >= 3
					and w.bobCm <= 6 and w.swayCm >= 1.2 and w.swayCm <= 4)
				check(tag .. string.format("a steady head (bob %.1f cm, sway %.1f cm), an upright trunk (pitch %.1f..%.1f)", w.headBobCm, w.headSwayCm,
					w.trunkPitch[1], w.trunkPitch[2]), w.headBobCm <= 6.5 and w.headSwayCm <= 2 and w.trunkPitch[1] >= -5 and w.trunkPitch[2] <= 2)
				check(tag .. string.format("arms swing +-%.0f (+%.0f / %.0f; HEAD +-20, +12 / -29), the elbow slightly bent (%.0f..%.0f; HEAD 16..44)",
					w.armSwing, w.armFwd, w.armBack, w.elbowMin, w.elbowMax), w.armSwing >= 12 and w.armSwing <= 20 and w.armFwd <= 20 and w.armBack >= -26
					and w.elbowMin >= 8 and w.elbowMax <= 36)
				check(tag .. string.format("no slide (%.3f / %.3f studs)", w.slideL, w.slideR), w.slideL <= 0.06 and w.slideR <= 0.06)
				-- the arms against the legs: at each left heel strike the left arm is back
				local rows = seriesOfFile(string.format("%s/gait_walk_t3_h%s_%s.json", out, rg.h, timing))
				if rows then
					local n, ok = 0, 0
					for i = 2, #rows do
						if rows[i].t > 2.5 and rows[i - 1].soleL >= 0.03 and rows[i].soleL < 0.03 then
							n += 1
							if rows[i].shoulderL < rows[i].shoulderR - 5 then
								ok += 1
							end
						end
					end
					check(tag .. string.format("the arms swing against the legs (left arm back at %d of %d left heel strikes)", ok, n), n >= 2 and ok == n)
				end
			end
			-- the start and the stop of a walk (W pressed and let go: 0 -> 6.5 -> 0, a frame each)
			local wg = by["walkgo_" .. timing]
			check(pre .. "walk start / stop recorded", wg ~= nil and wg.start ~= nil and wg.stop ~= nil)
			if wg and wg.start and wg.stop then
				local st, sp = wg.start, wg.stop
				check(pre .. string.format("walk start: the first foot lifts at +%.3f s, smoothly (knee %.0f, pelvis %.3f a frame), no slide (%.3f / %.3f)",
					st.firstLift, st.pops.knee, st.pops.pelvisY, st.slideL, st.slideR), st.firstLift >= 0 and st.firstLift <= 0.2 and st.pops.knee <= 32
					and st.pops.pelvisY <= 0.08 and st.slideL <= 0.05 and st.slideR <= 0.05)
				check(pre .. string.format("walk stop: the foot in the air down at +%.3f s, a closing step done by +%.3f s, at rest at +%.3f s", sp.downT,
					sp.airT, sp.settleT), sp.downT >= 0 and sp.downT <= 0.25 and sp.airT <= 0.36 and sp.settleT <= 0.55)
				local kf = math.max(sp.final.kneeL, sp.final.kneeR)
				check(pre .. string.format("walk stop: the knees straight again by +0.6 s (%.0f, at rest %.0f), the pelvis eased (%.3f a frame), no slide (%.3f / %.3f)",
					sp.kneeAt["0.6"] or -1, kf, sp.pops.pelvisY, sp.slideL, sp.slideR), (sp.kneeAt["0.6"] or 99) <= kf + 6 and sp.pops.pelvisY <= 0.06
					and sp.slideL <= 0.03 and sp.slideR <= 0.03)
				if wg.mid then
					check(pre .. string.format("walk between the start and the stop: no slide (%.3f / %.3f)", wg.mid.slideL, wg.mid.slideR), wg.mid.slideL <= 0.06
						and wg.mid.slideR <= 0.06)
				end
			end
			-- the stop out of a run (16 -> 0 in a frame): a quick catch step, a balanced stance, then the knees and arms
			local rs = by["runstop_" .. timing]
			check(pre .. "run stop recorded", rs ~= nil and rs.stop ~= nil)
			if rs and rs.stop then
				local sp = rs.stop
				check(pre .. string.format("run stop: both feet down at +%.3f s, nothing in the air after +%.3f s ([Studio] a foot 0.9 studs up for 0.2-0.3 s)",
					sp.downT, sp.airT), sp.downT >= 0 and sp.downT <= 0.25 and sp.airT <= 0.3)
				local kf = math.max(sp.final.kneeL, sp.final.kneeR)
				check(pre .. string.format("run stop: at rest at +%.3f s ([Studio] ~0.8 s), knees %.0f at +0.4 s (at rest %.0f), the pelvis eased (%.3f a frame), no slide (%.3f / %.3f)",
					sp.settleT, sp.kneeAt["0.4"] or -1, kf, sp.pops.pelvisY, sp.slideL, sp.slideR), sp.settleT <= 0.5 and (sp.kneeAt["0.4"] or 99) <= kf + 12
					and sp.pops.pelvisY <= 0.06 and sp.slideL <= 0.03 and sp.slideR <= 0.03)
			end
			-- Shift let go at a run: 16 -> 6.5 in a frame (the pelvis comes down out of the run's flight to the walk's height
			-- in a few frames: HEAD's steps of 0.05-0.12 studs a frame)
			local rw = by["runwalk_" .. timing]
			check(pre .. "run -> walk recorded", rw ~= nil and rw.slow ~= nil)
			if rw and rw.slow then
				local sl = rw.slow
				check(pre .. string.format("run -> walk: %d steps in 1.2 s, the longest swing %.3f s, no slide (%.3f / %.3f), the pelvis eased (%.3f a frame)",
					sl.steps, sl.longestSwing, sl.slideL, sl.slideR, sl.pops.pelvisY), sl.steps >= 3 and sl.longestSwing <= 0.45 and sl.slideL <= 0.06
					and sl.slideR <= 0.06 and sl.pops.pelvisY <= 0.12)
			end
			-- steering with the camera: never the side step's or the flip's handling
			for _, clip in ipairs({ "walksteer", "runsteer" }) do
				local ms = by[clip .. "_" .. timing]
				check(pre .. clip .. " recorded", ms ~= nil and ms.steer ~= nil)
				if ms and ms.steer then
					local sr = ms.steer
					check(pre .. string.format("%s: no side step (blend %.2f), no flip (%.2f), the pace kept ahead of him (%.2f)", clip, sr.sideKMax, sr.flipKMax,
						sr.latKMax), sr.sideKMax <= 0.05 and sr.flipKMax <= 0.05 and sr.latKMax <= 0.2)
					-- (a walker's toe-off scuffs a few centimetres as the turning legs swing over the toe: HEAD's 0.05-0.18)
					local cap = clip == "runsteer" and 0.08 or 0.25
					check(pre .. string.format("%s: the planted feet hold (slide %.3f / %.3f), no swing held (longest %.3f s)", clip, sr.gait.slideL,
						sr.gait.slideR, sr.longestSwing), sr.gait.slideL <= cap and sr.gait.slideR <= cap and sr.longestSwing <= (clip == "runsteer" and 0.6 or 0.55))
				end
			end
			-- the pure forward run against 6bb9a68's
			local rows = seriesOfFile(string.format("%s/gait_run_t3_h%s_%s.json", out, rg.h, timing))
			local refRows = REF_RUN.clips["h" .. rg.h .. "_" .. timing]
			check(pre .. "run and its 6bb9a68 reference recorded", rows ~= nil and refRows ~= nil)
			if rows and refRows then
				local rr = {}
				for _, a in ipairs(refRows) do
					local x = { t = a[1] }
					for i, k in ipairs(REF_RUN.keys) do
						x[k] = a[i + 1]
					end
					table.insert(rr, x)
				end
				local P, n, per = profileOf(rows, 2.0)
				local Q, nq, perQ = profileOf(rr, 2.0)
				local tag = pre .. "run vs 6bb9a68: "
				check(tag .. string.format("cycles compared (%d / %d)", n, nq), n >= 2 and nq >= 2)
				if n >= 2 and nq >= 2 then
					check(tag .. string.format("the same cadence (period %.3f vs %.3f s)", per, perQ), math.abs(per - perQ) <= 0.02 * perQ)
					local function share(T)
						local c = 0
						for i = 1, NB do
							c += T.soleL[i] < 0.03 and 1 or 0
						end
						return c / NB
					end
					check(tag .. string.format("the same contact (left foot down %.0f %% vs %.0f %% of the cycle)", 100 * share(P), 100 * share(Q)),
						math.abs(share(P) - share(Q)) <= 0.05)
					local worst = {}
					local function cmp(k, i, lo, hi, what)
						local d = P[k][i] - Q[k][i]
						if d < lo or d > hi then
							table.insert(worst, string.format("%s %s bin %d: %+.2f", what, k, i, d))
						end
					end
					for i = 1, NB do
						cmp("pelvisY", i, -0.05, 0.05, "body")
						cmp("headY", i, -0.05, 0.05, "body")
						cmp("trunkPitch", i, -3, 3, "body")
						for _, k in ipairs({ "shoulderL", "shoulderR", "elbowL", "elbowR" }) do
							cmp(k, i, -8, 8, "arm")
						end
						for _, sd in ipairs({ "L", "R" }) do
							if Q["sole" .. sd][i] < 0.03 then
								-- (the leg on the floor: as it was)
								cmp("hip" .. sd, i, -8, 8, "stance")
								cmp("knee" .. sd, i, -8, 8, "stance")
								cmp("sole" .. sd, i, -0.05, 0.05, "stance")
							else
								-- (the swing: lower, never higher, its knee folding up to 30 degrees less at the heel kick - and a
								-- little more as the foot leaves: drawn in after the body, never the straight leg flung back)
								cmp("knee" .. sd, i, -30, 12, "swing")
								cmp("hip" .. sd, i, -16, 14, "swing")
								cmp("sole" .. sd, i, -0.3, 0.03, "swing")
							end
						end
						if Q.soleL[i] < 0.03 then
							cmp("ankleL", i, -8, 8, "stance")
							cmp("footPitchL", i, -8, 8, "stance")
						end
					end
					check(tag .. "the stance, the pelvis, the trunk and the arms as they were; the swing lower", #worst == 0, table.concat(worst, ", "))
					-- the knee over the toes through the stance (6bb9a68's turned 14-20 degrees away from them)
					local kt = 0
					for i = 1, NB do
						if P.soleL[i] < 0.03 and P.kneeDirL and P.footYawL then
							kt = math.max(kt, math.abs(P.kneeDirL[i] - P.footYawL[i]))
						end
					end
					check(tag .. string.format("the planted knee points over the toes (within %.0f degrees)", kt), P.kneeDirL ~= nil and kt <= 12)
				end
				-- the swing's clearance: [Studio] 0.9 studs, 38 % of a 2.37-stud leg
				local L = by["run_" .. timing] and by["run_" .. timing].legLen or 2.6
				local pk = swingRises(rows, 2.0)
				local med, mx = pk[math.max(1, math.floor((#pk + 1) / 2))] or 99, pk[#pk] or 99
				check(tag .. string.format("the swinging foot rises %.0f %% of the leg (%.2f studs; the highest %.0f %%; 6bb9a68 / HEAD 35-38 %%)", 100 * med / L,
					med, 100 * mx / L), #pk >= 6 and med <= 0.3 * L and mx <= 0.31 * L)
			end
		end
	end
end

print(string.format("test_walkstable: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
