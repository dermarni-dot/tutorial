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
--   lune run tools/sim/test_walkstable.luau            (~20 s; the clips land in tools/sim/out/walkstable)
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
		local ok, r = pcall(process.spawn, cand, { "--version" }, { stdio = "default" })
		if ok and r.ok then
			return cand
		end
	end
	return "lune"
end

local TIMINGS = { "steady", "studio", "wander", "hz240", "spike" }
local args = { "run", "tools/sim/v9_anim.luau", "--tiers", "3", "--clips", "walk,snapturn,turn,curve,startstop", "--no-mesh", "--nopen",
	"--frames", "1", "--timing", table.concat(TIMINGS, ","), "--out", OUT }
local r = process.spawn(luneBin(), args, { cwd = root, stdio = "default" })
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
	wander = { pitch = 0.6, roll = 1.6, yaw = 1.8, headPitch = 0.5, headRoll = 0.35, headX = 0.008, ltX = 0.02, ltY = 0.09 },
	studio = { pitch = 0.6, roll = 1.6, yaw = 1.8, headPitch = 0.5, headRoll = 0.35, headX = 0.008, ltX = 0.02, ltY = 0.09 },
	spike = { pitch = 1.0, roll = 4.0, yaw = 9.0, headPitch = 0.9, headRoll = 0.6, headX = 0.015, ltX = 0.05, ltY = 0.16 },
}
local steady = byKey.walk_steady
check("steady walk recorded", steady ~= nil)
for _, timing in ipairs(TIMINGS) do
	local m = byKey["walk_" .. timing]
	check("walk " .. timing .. " recorded", m ~= nil)
	if m then
		local j = m.jitter
		check("walk " .. timing .. ": no NaN", j.nan == false)
		check("walk " .. timing .. string.format(": head sway %.3f, pelvis sway %.3f, pelvis roll %.1f", m.headSwayX, m.pelvisSwayX, m.pelvisRollDeg),
			m.headSwayX <= 0.06 and m.pelvisSwayX <= 0.14 and m.pelvisRollDeg <= 11)
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

print(string.format("test_walkstable: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
