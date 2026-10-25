--!nocheck
-- tools/sim/test_selfcheck.luau: the real Animator (v9_anim.luau) on an engine that does NOT apply its joint writes - the
-- user's Studio video (the character walked in the bind pose, arms straight, knees never bending, no error). The
-- Animator must notice from the limbs' real pose and never leave anyone walking frozen:
--   * ac:      an AnimationConstraint rig whose constraint writes are ignored, the server not having rebuilt it: this
--              client rebuilds it on Motor6Ds (EnsureMotors) and the walk bends its knees; "Output" says so
--   * ac-check: the same with the client's own rebuild held off (--convert-after 1000): the self-check's first step does
--              it ("joint writes are not taking effect ... Rebuilt its joints as Motor6Ds"), then the writes are verified
--   * all:     no joint write applies at all (Motor6Ds too): the local player gets Roblox's Animate script back (enabled,
--              its tracks left playing, ProcAnim off) and a warning names the rig and its joint class
--   * all-npc: the same on an NPC: Roblox's stock R15 idle / walk / run loaded on its Animator, the walk weighted in
--   * normal:  a rig whose writes apply is verified and left procedural (no warning, no fallback)
--   and the startup heartbeat "[Animator] running: driving N rigs (Motor6D a / AnimationConstraint b)" is printed
--   lune run tools/sim/test_selfcheck.luau            (~40 s)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Host = require("./host")

local root = Host.FindRoot()
local OUT = root .. "/tools/sim/out/selfcheck"

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local function luneBin()
	for _, cand in ipairs({ "lune", (process.env.HOME or "/root") .. "/.cargo/bin/lune", "/root/.cargo/bin/lune" }) do
		local ok, r = pcall(process.exec, cand, { "--version" })
		if ok and r.ok then
			return cand
		end
	end
	return "lune"
end
local LUNE = luneBin()

local function run(tag, extra)
	local args = { "run", "tools/sim/v9_anim.luau", "--tiers", "3", "--clips", "walk", "--no-mesh", "--nopen", "--frames", "1", "--walksecs", "7",
		"--out", OUT .. "_" .. tag }
	for _, a in ipairs(extra) do
		table.insert(args, a)
	end
	local r = process.exec(LUNE, args, { cwd = root })
	check(tag .. ": v9_anim runs", r.ok, (r.stderr or "") .. (r.stdout or ""):sub(-800))
	if not r.ok then
		return nil
	end
	for _, m in ipairs(serde.decode("json", fs.readFile(OUT .. "_" .. tag .. "/metrics.json"))) do
		if m.clip == "walk" then
			return m
		end
	end
	check(tag .. ": walk recorded", false)
	return nil
end
local function logHas(m, pat)
	for _, l in ipairs(m.selfCheck.log or {}) do
		if l:find(pat, 1, true) then
			return l
		end
	end
	return nil
end

-- a rig whose writes apply: verified, procedural, quiet
local normal = run("normal", {})
if normal then
	local sc = normal.selfCheck
	check("normal: writes verified, no fallback", sc.writesOk == true and sc.fallback == nil, serde.encode("json", sc))
	check("normal: no 'not taking effect' warning", logHas(normal, "not taking effect") == nil)
	check("normal: the heartbeat line", logHas(normal, "[Animator] running: driving 1 rigs (Motor6D 1 / AnimationConstraint 0)") ~= nil,
		table.concat(sc.log, " | "))
	check(string.format("normal: the knees bend (%.0f..%.0f)", normal.gait.kneeL[1], normal.gait.kneeL[2]), normal.gait.kneeL[2] > 40)
end

-- AnimationConstraint writes ignored, the client rebuilds the rig before the self-check has to
local ac = run("ac", { "--joints", "ac", "--ignore-writes", "ac" })
if ac then
	local sc = ac.selfCheck
	check("ac: rebuilt on Motor6Ds on this client (15 / 0)", sc.motor6d == 15 and sc.ac == 0, serde.encode("json", sc))
	check("ac: the rebuild is in Output", logHas(ac, "the server had not rebuilt: rebuilt as Motor6Ds on this client") ~= nil, table.concat(sc.log, " | "))
	check("ac: writes verified, no fallback", sc.writesOk == true and sc.fallback == nil)
	check(string.format("ac: the knees bend (%.0f..%.0f)", ac.gait.kneeL[1], ac.gait.kneeL[2]), ac.gait.kneeL[2] > 40)
	check(string.format("ac: the planted feet hold once rebuilt (slide %.3f / %.3f)", ac.gait.slideL, ac.gait.slideR), ac.gait.slideL < 0.05 and ac.gait.slideR < 0.05)
	check("ac: Roblox's Animate stays off (the procedural walk drives)", ac.animate.disabled == true and ac.animate.playing == 0)
end

-- the same, the client's own rebuild held off: the self-check's first step rebuilds it
local acc = run("accheck", { "--joints", "ac", "--ignore-writes", "ac", "--convert-after", "1000" })
if acc then
	local sc = acc.selfCheck
	local w = logHas(acc, "joint writes are not taking effect on Walker (AnimationConstraint rig)")
	check("ac-check: the self-check warns, naming the rig and its joint class", w ~= nil, table.concat(sc.log, " | "))
	check("ac-check: the warning gives written vs actual numbers and the rebuild", w ~= nil and w:find("written vs actual pose off by", 1, true) ~= nil
		and w:find("Rebuilt its joints as Motor6Ds on this client", 1, true) ~= nil, w)
	check("ac-check: rebuilt, then verified, no fallback", sc.motor6d == 15 and sc.ac == 0 and sc.localMotors == true and sc.writesOk == true and sc.fallback == nil,
		serde.encode("json", sc))
	check(string.format("ac-check: the knees bend after it (%.0f..%.0f)", acc.gait.kneeL[1], acc.gait.kneeL[2]), acc.gait.kneeL[2] > 40)
end

-- nothing applies: the local player gets Roblox's Animate back
local all = run("all", { "--ignore-writes", "all" })
if all then
	local sc = all.selfCheck
	local w = logHas(all, "joint writes are not taking effect on Walker (Motor6D rig)")
	check("all: the self-check warns, naming the rig and its joint class", w ~= nil, table.concat(sc.log, " | "))
	check("all: the warning says it switched to Roblox's default animation", w ~= nil and w:find("Animate script is enabled again", 1, true) ~= nil, w)
	check("all: fallback = Animate", sc.fallback == "Animate", tostring(sc.fallback))
	check("all: the Animate script enabled, its tracks left playing, ProcAnim off", all.animate.disabled == false and all.animate.playing >= 1
		and all.animate.procAnim == false, serde.encode("json", all.animate))
	check("all: never a keyframe track loaded for the local player (Animate does it)", sc.loaded == 0, sc.loaded)
end

-- nothing applies on an NPC: Roblox's stock R15 tracks on its Animator
local npc = run("allnpc", { "--ignore-writes", "all", "--npc" })
if npc then
	local sc = npc.selfCheck
	check("all-npc: the self-check warns", logHas(npc, "joint writes are not taking effect on Walker (Motor6D rig)") ~= nil, table.concat(sc.log, " | "))
	check("all-npc: fallback = keyframe", sc.fallback == "keyframe", tostring(sc.fallback))
	check("all-npc: idle / walk / run loaded on its Animator", sc.loaded == 3, sc.loaded)
	check(string.format("all-npc: walking -> the walk track weighted in (%.2f)", sc.walkWeight), sc.walkWeight > 0.5)
end

print(string.format("test_selfcheck: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
