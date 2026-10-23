--!nocheck
-- tools/sim/test_spacing.luau: the bodies never go into each other (FightEngine on stub rigs through tools/sim/fightsim).
--   * whole fights for every body-frame pairing (Lean .. Heavyweight Build, AI vs AI and a pressure bot against a
--     heavyweight): the root-to-root distance never drops below the pair's MinSep minus a small tolerance (one
--     sim tick of walking: Separate resolves what a step or a lunge left), and MinSep / ClinchSep / ClinchRange
--     grow with the frames (a Heavyweight pair stands further apart than a Lean one; the clinch is held outside
--     MinSep; a clinch can start from outside the clinch distance)
--   * the referee (a stub the engine's UpdateReferee moves): never nearer than MinSep to either fighter except
--     over a knockdown (the count) or a knockout on the feet; inside 4.5 studs of a fighter only for a reason
--     (a clinch that has held REF.clinchHold, the count, the bell); mostly out on his orbit
--   * PostFight.Layout: two heavyweights and the referee spaced from their frames (no shoulder overlap)
--   lune run tools/sim/test_spacing.luau [-v]
local process = require("@lune/process")
local FS = require("./fightsim")

local verbose = table.find(process.args, "-v") ~= nil
local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local S = FS.new()
local FightEngine = S.FightEngine
local V3 = S.H.globals.Vector3
local Random = S.H.globals.Random
local REF = FightEngine.REF or { orbit = 7, clinchHold = 1.5 }

local function flat(v)
	return V3.new(v.X, 0, v.Z)
end

local FRAMES = { "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build" }
local SEP_TOL = 0.5 -- (one 20 Hz sim tick of two men walking at once, ~0.7 studs each in the game's 60 Hz terms 0.23: Separate takes it out next tick)

-- the pair's spacing numbers, by frame
do
	local sep = {}
	for _, fr in ipairs(FRAMES) do
		local f = S.NewFight(S.Boxer({ frame = fr }, Random.new(1)), S.Boxer({ frame = fr }, Random.new(2)), 3, 1)
		sep[fr] = { min = f:MinSep(), clinch = f:ClinchSep(), range = f:ClinchRange(f.P) }
		check("ClinchSep >= MinSep (" .. fr .. ")", sep[fr].clinch >= sep[fr].min, string.format("%.2f < %.2f", sep[fr].clinch, sep[fr].min))
		check("ClinchRange > ClinchSep (" .. fr .. ")", sep[fr].range > sep[fr].clinch, string.format("%.2f <= %.2f", sep[fr].range, sep[fr].clinch))
		if verbose then
			print(string.format("  %-18s MinSep %.2f  ClinchSep %.2f  ClinchRange %.2f", fr, sep[fr].min, sep[fr].clinch, sep[fr].range))
		end
	end
	check("MinSep grows with the frame (Lean < Athletic < Power < Heavyweight)", sep.Lean.min <= sep.Athletic.min and sep.Athletic.min < sep["Power Build"].min and sep["Power Build"].min < sep["Heavyweight Build"].min)
	check("MinSep: a Heavyweight pair at least 0.2 further apart than the unit pair", sep["Heavyweight Build"].min - sep.Athletic.min >= 0.2, sep["Heavyweight Build"].min - sep.Athletic.min)
	-- a mixed pair sits between
	local f = S.NewFight(S.Boxer({ frame = "Heavyweight Build" }, Random.new(1)), S.Boxer({ frame = "Lean" }, Random.new(2)), 3, 1)
	check("MinSep: Heavyweight v Lean between the two pairs", f:MinSep() > sep.Lean.min and f:MinSep() < sep["Heavyweight Build"].min, f:MinSep())
	-- KeepOut: a spot inside the other man comes out to MinSep, read where he is heading
	local P, O = f.P, f.O
	local ms = f:MinSep()
	local kept = f:KeepOut(P, O.root.Position + V3.new(0.5, 0, 0))
	check("KeepOut: a spot on the other man comes out to MinSep", math.abs(flat(kept - O.root.Position).Magnitude - ms) < 0.01, flat(kept - O.root.Position).Magnitude)
	check("KeepOut: a spot already outside is left alone", (f:KeepOut(P, O.root.Position + V3.new(ms + 1, 0, 0)) - (O.root.Position + V3.new(ms + 1, 0, 0))).Magnitude < 1e-6)
	-- a lighter man gives more ground
	check("BodyMass: the Heavyweight outweighs the Lean man", f:BodyMass(P) > f:BodyMass(O) * 1.15, f:BodyMass(P) / f:BodyMass(O))
end

------------------------------------------------------------------------
-- whole fights: the roots, the referee
------------------------------------------------------------------------
local function run(name, spec)
	spec.rounds = spec.rounds or 2
	spec.ref = true
	local st = { minD = math.huge, ticks = 0, under = 0, refMinStand = math.huge, refUnder = 0, refClose = 0, refCloseBad = 0, refFar = 0, refTicks = 0, breaks = 0, evades = 0, underModes = {}, dips = {}, clinchTicks = 0, kd = 0, modes = {} }
	spec.onTick = function(fight, now)
		local P, O = fight.P, fight.O
		if P.state == "down" or O.state == "down" then
			return
		end
		local m = flat(O.root.Position - P.root.Position).Magnitude
		local floor = (P.state == "clinch" or O.state == "clinch") and fight:ClinchSep() or fight:MinSep()
		-- (the tie-up's slide opens a pair out to the clinch distance over half a second: judge it by MinSep then)
		if fight.tieUntil and now < fight.tieUntil then
			floor = fight:MinSep()
		end
		st.ticks += 1
		st.minD = math.min(st.minD, m - floor)
		if m < floor - SEP_TOL then
			st.under += 1
			if #st.dips < 4 then
				table.insert(st.dips, string.format("t%.1f %.2f P:%s%s O:%s%s", now, m - floor, P.state, (now < (P.lungeUntil or 0)) and "+lunge" or "", O.state, (now < (O.lungeUntil or 0)) and "+lunge" or ""))
			end
		end
		local R = fight.ref
		if R and R.root and fight.live then
			local dP, dO = flat(R.root.Position - P.root.Position).Magnitude, flat(R.root.Position - O.root.Position).Magnitude
			local near = math.min(dP, dO)
			local clinched = P.state == "clinch" or O.state == "clinch"
			local mode = R.mode or "orbit"
			st.modes[mode] = (st.modes[mode] or 0) + 1
			if mode ~= "count" and mode ~= "catch" then
				st.refMinStand = math.min(st.refMinStand, near)
				if near < fight:MinSep() - 0.3 then
					st.refUnder += 1
					st.underModes[mode] = (st.underModes[mode] or 0) + 1
				end
			end
			if not clinched and mode == "orbit" then
				st.refTicks += 1
				if near >= REF.orbit - 1.5 then
					st.refFar += 1
				end
			end
			if near < 4.5 and mode == "orbit" then
				st.refClose += 1
			end
			if clinched then
				st.clinchTicks += 1
			end
			if mode == "break" then
				st.breaks += 1
				-- (judged when the mode was set: a break outlives the clinch by a re-plan tick)
				local held = (R.modeAt or now) - math.max(P.clinchAt or 0, O.clinchAt or 0)
				if held < REF.clinchHold - 0.2 then
					st.refCloseBad += 1
				end
			end
			if mode == "evade" then
				st.evades += 1
			end
		end
	end
	local res = S.Fight(spec)
	st.kd = (res.kd.red or 0) + (res.kd.blue or 0)
	local ms = res.fight:MinSep()
	check(name .. ": roots never closer than MinSep - tol", st.minD >= -SEP_TOL, string.format("worst %.2f under the floor (MinSep %.2f)", -st.minD, ms))
	check(name .. ": under the floor on under 1% of the ticks", st.under <= st.ticks * 0.01, string.format("%d / %d", st.under, st.ticks))
	-- (the fighters pass through the referee - his own collision group - and cover 12 studs/s against his jog: a
	-- man charging straight at him gets inside MinSep for a tick or two before he is clear; never inside a body)
	check(name .. ": referee never inside a standing man's body (but the count)", st.refMinStand >= 1.0, string.format("nearest %.2f", st.refMinStand))
	check(name .. ": referee inside MinSep of a standing man on under 1.5% of the ticks", st.refUnder <= st.ticks * 0.015, string.format("%d / %d ticks, nearest %.2f", st.refUnder, st.ticks, st.refMinStand))
	check(name .. ": referee inside 4.5 studs only for a reason", st.refClose <= st.ticks * 0.1, string.format("%d / %d ticks on the orbit mode", st.refClose, st.ticks))
	check(name .. ": referee out on the orbit most of the open play", st.refTicks == 0 or st.refFar >= st.refTicks * 0.6, string.format("%d / %d", st.refFar, st.refTicks))
	check(name .. ": a break only after the clinch has held", st.refCloseBad == 0, st.refCloseBad)
	if verbose then
		local modes = {}
		for k, v in pairs(st.modes) do
			table.insert(modes, k .. "=" .. v)
		end
		table.sort(modes)
		local um = {}
		for k, v in pairs(st.underModes) do
			table.insert(um, k .. "=" .. v)
		end
		table.sort(um)
		print("    ref under MinSep by mode: " .. table.concat(um, " ") .. "  dips: " .. table.concat(st.dips, " | "))
		print(string.format("  %-34s %s %s R%d  worst %+.2f  under %d/%d  ref nearest %.2f  orbit-far %d/%d  close %d  breaks %d (bad %d) evades %d clinch %d  kd %d  modes %s",
			name, res.winner, tostring(res.method), res.round, st.minD, st.under, st.ticks, st.refMinStand, st.refFar, st.refTicks, st.refClose, st.breaks, st.refCloseBad, st.evades, st.clinchTicks, st.kd, table.concat(modes, " ")))
	end
	return st
end

local seed = 11
for i, a in ipairs(FRAMES) do
	for j = i, #FRAMES do
		local b = FRAMES[j]
		if a == b or (a == "Lean" and b == "Heavyweight Build") or (a == "Athletic" and b == "Power Build") then
			seed += 1
			run(a .. " v " .. b, { red = { frame = a, style = "Swarmer", level = 70 }, blue = { frame = b, style = "Slugger", level = 70 }, seed = seed })
		end
	end
end
run("pressure bot v Heavyweight", { red = { bot = "pressure", frame = "Athletic" }, blue = { frame = "Heavyweight Build", style = "Slugger", level = 75 }, seed = 31 })
run("smart bot v Lean", { red = { bot = "smart", frame = "Heavyweight Build" }, blue = { frame = "Lean", style = "OutBoxer", level = 65 }, seed = 32, rounds = 3 })

------------------------------------------------------------------------
-- the post-fight scene's places
------------------------------------------------------------------------
do
	local okPF, PostFight = pcall(S.H.requireNode, S.server._kids.PostFight)
	check("PostFight loads under the sim", okPF and type(PostFight) == "table" and type(PostFight.Layout) == "function", PostFight)
	if okPF and type(PostFight) == "table" and PostFight.Layout then
		local HG = S.H.require("HitGeometry")
		local Builder = S.H.require("Builder")
		local function frameOf(id)
			local sc = Builder.Scales({ gender = 1, height = 74, body = { frame = id } }, nil, nil)
			return HG.FrameFromScales(sc, { height = 74 })
		end
		local heavy, ref = frameOf("Heavyweight Build"), HG.Unit()
		local center, face = V3.new(0, 0, 0), V3.new(0, 0, -1)
		local L = PostFight.Layout(center, face, { red = heavy, blue = heavy, ref = ref })
		local right = face:Cross(V3.new(0, 1, 0))
		local function along(p)
			return flat(p - center):Dot(right)
		end
		local gapR = along(L.ref) - along(L.red) - heavy.shoulderHalf - ref.shoulderHalf
		local gapB = along(L.blue) - along(L.ref) - heavy.shoulderHalf - ref.shoulderHalf
		check("PostFight.Layout: red at the referee's left, blue at his right", along(L.red) < along(L.ref) and along(L.ref) < along(L.blue))
		check("PostFight.Layout: clear air between the heavyweights' shoulders and the referee's (>= 0.5)", gapR >= 0.5 and gapB >= 0.5, string.format("%.2f / %.2f", gapR, gapB))
		check("PostFight.Layout: the men's roots a full torso width + gloves apart from the referee's", along(L.ref) - along(L.red) >= heavy.shoulderHalf + ref.shoulderHalf + 0.5)
		local lean = frameOf("Lean")
		local L2 = PostFight.Layout(center, face, { red = lean, blue = lean, ref = ref })
		check("PostFight.Layout: a lean pair stands closer in than the heavyweights", along(L2.blue) - along(L2.red) < along(L.blue) - along(L.red))
		-- a man down: the other at the referee's side, both clear of each other
		local L3 = PostFight.Layout(center, face, { red = heavy, blue = heavy, ref = ref, redDown = true })
		check("PostFight.Layout: one man down, the standing man beside the referee with clear air", along(L3.blue) - along(L3.ref) >= heavy.shoulderHalf + ref.shoulderHalf + 0.5)
		if verbose then
			print(string.format("  layout heavy/heavy: red %.2f ref %.2f blue %.2f (shoulder halves %.2f / %.2f)", along(L.red), along(L.ref), along(L.blue), heavy.shoulderHalf, ref.shoulderHalf))
		end
	end
end

print(string.format("test_spacing: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
