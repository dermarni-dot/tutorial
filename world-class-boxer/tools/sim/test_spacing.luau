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
--   * the referee also: in his orbit zone (REF.orbitMin..orbitMax from the midpoint, the far side from the hard
--     camera) most of the open play, never walking across between the men, at a walk but for the knockdown (the
--     count, the catch); a knockdown held off while the fall plays (REF.fallLand), then the count from about
--     REF.count studs, never on the standing man, who is waved to the neutral corner; a foul (Fight:RefWarn)
--     walked in on to MinSep + REF.warnGap and backed off from
--   * RouteAround: a walk to a spot behind the other man goes round him (the line outside his body)
--   * every frame pairing (15) over whole fights: the minimum root distance against the pair's MinSep
--   * PostFight.Layout: two heavyweights and the referee spaced from their frames (no shoulder overlap), a fallen
--     man at the centre stepped off, the ropes respected
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
-- RouteAround: a walk to a spot behind the other man goes round him, never through him
------------------------------------------------------------------------
do
	local CF = S.H.globals.CFrame
	local f = S.NewFight(S.Boxer({ frame = "Heavyweight Build" }, Random.new(1)), S.Boxer({ frame = "Heavyweight Build" }, Random.new(2)), 3, 1)
	local P, O = f.P, f.O
	P.root.CFrame = CF.new(V3.new(-3.6, 3.2, 0))
	O.root.CFrame = CF.new(V3.new(0, 3.2, 0))
	local r = f:SepRadius()
	local function segClear(a, b, c)
		local seg = flat(b - a)
		local t = math.clamp(flat(c - a):Dot(seg) / math.max(seg:Dot(seg), 1e-6), 0, 1)
		return flat(a + seg * t - c).Magnitude
	end
	local behind = V3.new(3.6, 3.2, 0.3)
	local way = f:RouteAround(P, behind)
	check("RouteAround: a spot behind the other man is walked round to", (flat(way - behind)).Magnitude > 0.5, way)
	check("RouteAround: the way round stays outside his body (SepRadius)", segClear(P.root.Position, way, O.root.Position) >= r - 1e-3, segClear(P.root.Position, way, O.root.Position))
	local side = V3.new(-3.6, 3.2, 3)
	check("RouteAround: a clear line is walked straight", (f:RouteAround(P, side) - side).Magnitude < 1e-6)
	local atRange = V3.new(-r, 3.2, 0)
	check("RouteAround: a straight step in to his range is not detoured", (f:RouteAround(P, atRange) - atRange).Magnitude < 1e-6)
	-- from on the circle: a step round it, the chord outside the body
	P.root.CFrame = CF.new(V3.new(-r, 3.2, 0))
	local way2 = f:RouteAround(P, behind)
	check("RouteAround: from his range the step round keeps outside him", segClear(P.root.Position, way2, O.root.Position) >= r - 0.05, segClear(P.root.Position, way2, O.root.Position))
end

------------------------------------------------------------------------
-- whole fights: the roots, the referee
------------------------------------------------------------------------
local H_TOL = 0.1
local function segHit(a, b, c, d)
	-- do the flat segments a-b and c-d cross?
	local function cr(o, p, q)
		return (p.X - o.X) * (q.Z - o.Z) - (p.Z - o.Z) * (q.X - o.X)
	end
	local d1, d2, d3, d4 = cr(c, d, a), cr(c, d, b), cr(a, b, c), cr(a, b, d)
	return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
end
local ALL = { worst = math.huge, worstName = "" }
local function run(name, spec)
	spec.rounds = spec.rounds or 2
	spec.ref = true
	local st = { minD = math.huge, ticks = 0, under = 0, refMinStand = math.huge, refUnder = 0, refClose = 0, refCloseBad = 0, refFar = 0, refTicks = 0, breaks = 0, evades = 0, underModes = {}, dips = {}, clinchTicks = 0, kd = 0, modes = {},
		zone = 0, camFar = 0, cross = 0, fast = 0, kdEp = 0, kdEarly = 0, kdCount = 0, kdCountOk = 0, kdStandBad = 0, waved = 0, crossAt = {} }
	local prevR, kdT0, kdD0, kdAt, kdWho, lastAct = nil, nil, nil, nil, nil, nil
	spec.onTick = function(fight, now)
		local P, O = fight.P, fight.O
		local R = fight.ref
		local down = (P.state == "down" and P) or (O.state == "down" and O) or nil
		-- the referee on every tick, the knockdowns included
		if R and R.root then
			local rp = R.root.Position
			local mode = R.mode or "orbit"
			local dt = 0.05
			-- a walk everywhere but the knockdown (the count's and the catch's jog)
			if mode ~= "count" and mode ~= "catch" and R.hum.WalkSpeed > REF.walk + 1e-3 then
				st.fast += 1
			end
			if prevR and mode ~= "count" and mode ~= "catch" and flat(rp - prevR).Magnitude > REF.walk * dt + 0.05 then
				st.fast += 1
			end
			-- never across the men's line between them (his own walk; the count's walk to the fallen man aside): his
			-- step crossing the line between them both where they stood and where they stand (the men swinging their
			-- line over a referee standing still is theirs, not his)
			if prevR and st.prevLP and not down and mode ~= "count" and mode ~= "catch" and segHit(prevR, rp, P.root.Position, O.root.Position)
				and segHit(prevR, rp, st.prevLP, st.prevLO) then
				st.cross += 1
				if #st.crossAt < 3 then
					table.insert(st.crossAt, string.format("t%.1f %s", now, mode))
				end
			end
			prevR = rp
			st.prevLP, st.prevLO = P.root.Position, O.root.Position
			if mode == "count" then
				st.sawCount = true
			end
			local act = R.model.attrs and R.model.attrs.Act
			if act ~= lastAct and act == "neutral" then
				st.waved += 1
			end
			lastAct = act
			if down then
				if kdWho ~= down then
					kdWho, kdT0, kdAt = down, now, down.root.Position
					kdD0 = flat(rp - kdAt).Magnitude
					st.kdEp += 1
				end
				local dd = flat(rp - down.root.Position).Magnitude
				local other = fight:Other(down)
				if now - kdT0 < REF.fallLand - 0.06 and mode ~= "catch" and not R.catching then
					-- the fall still playing: he holds his ground - no nearer the spot the man went down on (a step off
					-- a body that comes at him is allowed: the fall slides, the puncher backs off)
					if flat(rp - kdAt).Magnitude < kdD0 - 0.3 then
						st.kdEarly += 1
						st.kdEarlyWhy = st.kdEarlyWhy or string.format("t+%.2f mode %s %.2f -> %.2f (ep %d, ws %.1f)", now - kdT0, mode, kdD0, flat(rp - kdAt).Magnitude, st.kdEp, R.hum.WalkSpeed)
					end
				elseif now - kdT0 > REF.fallLand + 1.6 and mode == "count" then
					st.kdCount += 1
					if st.kdCount % 25 == 1 then
						st.kdDd = (st.kdDd or "") .. string.format(" %.2f", dd)
					end
					if math.abs(dd - REF.count) <= 0.6 then
						st.kdCountOk += 1
					end
					if flat(rp - other.root.Position).Magnitude < fight:MinSep() - 0.3 then
						st.kdStandBad += 1
					end
				end
			else
				kdWho = nil
			end
		end
		if down then
			st.prevP, st.prevO = P.root.Position, O.root.Position
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
				local function how(F, k)
					local pv = st["prev" .. k] or F.root.Position
					return string.format("%s:%s%s%s step %.2f ws %.1f", k, F.state, (now < (F.lungeUntil or 0)) and "+lunge" or "", (now < (F.stumbleUntil or 0)) and "+stumble" or "", flat(F.root.Position - pv).Magnitude, F.hum.WalkSpeed)
				end
				table.insert(st.dips, string.format("t%.1f %.2f %s %s (was %.2f)", now, m - floor, how(P, "P"), how(O, "O"), st.prevM or -1))
			end
		end
		st.prevP, st.prevO, st.prevM = P.root.Position, O.root.Position, m
		if R and R.root and fight.live then
			local rp = R.root.Position
			local dP, dO = flat(rp - P.root.Position).Magnitude, flat(rp - O.root.Position).Magnitude
			local near = math.min(dP, dO)
			local clinched = P.state == "clinch" or O.state == "clinch"
			local mode = R.mode or "orbit"
			st.modes[mode] = (st.modes[mode] or 0) + 1
			-- (fightsim stands the men back at +-3 on the centre line at each round's start, wherever the referee is: a
			-- teleport the game never makes - they come out of their corners - so its first ticks are not his doing)
			local teleported = fight.resumedAt ~= nil and now - fight.resumedAt < 0.2
			if mode ~= "count" and mode ~= "catch" and not teleported then
				if near < st.refMinStand then
					local F = dP < dO and P or O
					st.refMinWhy = string.format("t%.1f mode %s, %s %s ws %.1f%s%s", now, mode, F == P and "red" or "blue", F.state, F.hum.WalkSpeed, now < (F.stumbleUntil or 0) and " stumbling" or "", now < (F.lungeUntil or 0) and " lunging" or "")
				end
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
				-- the orbit zone: orbitMin..orbitMax from the midpoint (further for a pair standing far apart), on
				-- the far side from the hard camera
				local mid = (P.root.Position + O.root.Position) / 2
				local rel = flat(rp - mid)
				local half = m / 2
				local rmax = math.max(REF.orbitMax, REF.orbitMin, half + (REF.clearOf or 5) * 0.8)
				if rel.Magnitude >= REF.orbitMin - 0.6 and rel.Magnitude <= rmax + 0.6 then
					st.zone += 1
				end
				if rel.Magnitude > 0.1 and rel.Unit:Dot(fight:HardSide()) <= H_TOL then
					st.camFar += 1
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
		if spec.extra then
			spec.extra(fight, now, st)
		end
	end
	local res = S.Fight(spec)
	st.kd = (res.kd.red or 0) + (res.kd.blue or 0)
	local ms = res.fight:MinSep()
	if st.minD < ALL.worst then
		ALL.worst, ALL.worstName = st.minD, name
	end
	check(name .. ": roots never closer than MinSep - tol", st.minD >= -SEP_TOL, string.format("worst %.2f under the floor (MinSep %.2f)", -st.minD, ms))
	check(name .. ": under the floor on under 1% of the ticks", st.under <= st.ticks * 0.01, string.format("%d / %d", st.under, st.ticks))
	-- (the fighters pass through the referee - his own collision group - and a man charging straight at him gets
	-- inside MinSep for a tick or two before he is clear; never inside a body)
	check(name .. ": referee never inside a standing man's body (but the count)", st.refMinStand >= 1.0, string.format("nearest %.2f (%s)", st.refMinStand, tostring(st.refMinWhy)))
	check(name .. ": referee inside MinSep of a standing man on under 1.5% of the ticks", st.refUnder <= st.ticks * 0.015, string.format("%d / %d ticks, nearest %.2f", st.refUnder, st.ticks, st.refMinStand))
	check(name .. ": referee inside 4.5 studs only for a reason", st.refClose <= st.ticks * 0.05, string.format("%d / %d ticks on the orbit mode", st.refClose, st.ticks))
	check(name .. ": referee out on the orbit most of the open play", st.refTicks == 0 or st.refFar >= st.refTicks * 0.7, string.format("%d / %d", st.refFar, st.refTicks))
	check(name .. ": referee in the orbit zone (6-8 from the midpoint) most of the open play", st.refTicks == 0 or st.zone >= st.refTicks * 0.7, string.format("%d / %d", st.zone, st.refTicks))
	check(name .. ": referee on the far side from the hard camera most of the open play", st.refTicks == 0 or st.camFar >= st.refTicks * 0.75, string.format("%d / %d", st.camFar, st.refTicks))
	check(name .. ": referee never walks across between the men", st.cross == 0, string.format("%d (%s)", st.cross, table.concat(st.crossAt, ", ")))
	check(name .. ": referee at a walk but for the knockdown", st.fast == 0, st.fast)
	check(name .. ": a break only after the clinch has held", st.refCloseBad == 0, st.refCloseBad)
	if st.kdEp > 0 then
		check(name .. ": knockdown: he holds his ground while the fall plays", st.kdEarly == 0, string.format("%d (%s)", st.kdEarly, tostring(st.kdEarlyWhy)))
		check(name .. ": knockdown: the count from about REF.count studs", st.kdCount == 0 or st.kdCountOk >= st.kdCount * 0.9, string.format("%d / %d", st.kdCountOk, st.kdCount))
		check(name .. ": knockdown: the count never on the standing man", st.kdStandBad == 0, st.kdStandBad)
		-- (a count: a knockout out cold has none, and no neutral corner)
		if st.sawCount then
			check(name .. ": knockdown: the other man waved to the neutral corner", st.waved >= 1, st.waved)
		end
	end
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
		print(string.format("  %-34s %s %s R%d  worst %+.2f  under %d/%d  ref nearest %.2f (under by mode: %s)  orbit-far %d/%d zone %d cam %d  close %d  breaks %d (bad %d) evades %d clinch %d  kd %d (eps %d, count ok %d/%d)  modes %s%s",
			name, res.winner, tostring(res.method), res.round, st.minD, st.under, st.ticks, st.refMinStand, table.concat(um, " "), st.refFar, st.refTicks, st.zone, st.camFar, st.refClose, st.breaks, st.refCloseBad, st.evades, st.clinchTicks, st.kd, st.kdEp, st.kdCountOk, st.kdCount,
			table.concat(modes, " ") .. (st.kdDd and (" count dd:" .. st.kdDd) or ""), #st.dips > 0 and ("  dips: " .. table.concat(st.dips, " | ")) or ""))
	end
	return st
end

-- every frame pairing (both men's frames, Lean .. Heavyweight Build): the minimum root distance over whole fights
local seed = 11
local kdSeen = 0
for i, a in ipairs(FRAMES) do
	for j = i, #FRAMES do
		local b = FRAMES[j]
		seed += 1
		local st = run(a .. " v " .. b, { red = { frame = a, style = "Swarmer", level = 70 }, blue = { frame = b, style = "Slugger", level = 70 }, seed = seed })
		kdSeen += st.kdEp
	end
end
-- the world's height range (Config.BoxerHeightRange: 5'4" .. 6'9"): the shortest against the tallest both ways, two of the
-- tallest, the referee and the separation with them
for _, hp in ipairs({ { 64, 81, "Lean", "Heavyweight Build" }, { 81, 64, "Heavyweight Build", "Athletic" }, { 81, 81, "Heavyweight Build", "Heavyweight Build" } }) do
	seed += 1
	local st = run(string.format("%d in v %d in", hp[1], hp[2]), { red = { frame = hp[3], style = "Swarmer", level = 70, height = hp[1] },
		blue = { frame = hp[4], style = "Slugger", level = 70, height = hp[2] }, seed = seed })
	kdSeen += st.kdEp
end
do
	local f = S.NewFight(S.Boxer({ frame = "Heavyweight Build", height = 81 }, Random.new(1)), S.Boxer({ frame = "Heavyweight Build", height = 81 }, Random.new(2)), 3, 1)
	local g = S.NewFight(S.Boxer({ frame = "Heavyweight Build", height = 70 }, Random.new(1)), S.Boxer({ frame = "Heavyweight Build", height = 70 }, Random.new(2)), 3, 1)
	check(string.format("two 6'9\" men stand further apart than two 5'10\" ones (MinSep %.2f vs %.2f)", f:MinSep(), g:MinSep()), f:MinSep() > g:MinSep())
	check("ClinchRange > ClinchSep for two 6'9\" men", f:ClinchRange(f.P) > f:ClinchSep())
end
-- (and a mismatch, so the knockdown rules are exercised whatever the even fights above came to: the hooks land a stud
-- closer in than they did before the reach was measured off the animation, and even bouts see fewer knockdowns)
do
	local st = run("mismatch (Slugger 88 v 52)", { red = { style = "Slugger", level = 88 }, blue = { style = "OutBoxer", level = 52 }, seed = 47 })
	kdSeen += st.kdEp
end
run("pressure bot v Heavyweight", { red = { bot = "pressure", frame = "Athletic" }, blue = { frame = "Heavyweight Build", style = "Slugger", level = 75 }, seed = 31 })
run("smart bot v Lean", { red = { bot = "smart", frame = "Heavyweight Build" }, blue = { frame = "Lean", style = "OutBoxer", level = 65 }, seed = 32, rounds = 3 })
check("whole fights: the minimum root distance over every pairing within MinSep - tol", ALL.worst >= -SEP_TOL, string.format("%.2f (%s)", ALL.worst, ALL.worstName))
check("whole fights: the knockdown rules were exercised", kdSeen >= 3, kdSeen)
if verbose then
	print(string.format("  every pairing: worst root distance %+.2f against the floor (%s)", ALL.worst, ALL.worstName))
end

-- a foul: the referee walks in to the offender (MinSep + REF.warnGap), never onto him, and backs off after
do
	local fs = { called = nil, nearest = math.huge, seenFoul = false, under = 0, after = nil, backOut = false }
	run("foul call (Swarmer v Slugger)", { red = { frame = "Power Build", style = "Swarmer", level = 70 }, blue = { frame = "Muscular", style = "Slugger", level = 70 }, seed = 41, rounds = 1,
		extra = function(fight, now)
			local P, O, R = fight.P, fight.O, fight.ref
			if not fs.called and now - (fight.resumedAt or now) > 8 and P.state ~= "clinch" and O.state ~= "clinch" and fight.live and not fight.paused then
				fs.called = now
				fight:RefWarn(P)
			end
			if fs.called and now - fs.called <= REF.warnFor then
				local d = flat(R.root.Position - P.root.Position).Magnitude
				fs.nearest = math.min(fs.nearest, d)
				fs.seenFoul = fs.seenFoul or R.mode == "foul"
				if d < fight:MinSep() - 0.3 then
					fs.under += 1
				end
			elseif fs.called and now - fs.called > REF.warnFor + 2.5 and R.mode == "orbit" then
				fs.backOut = true
			end
		end })
	local ms = S.NewFight(S.Boxer({ frame = "Power Build" }, Random.new(1)), S.Boxer({ frame = "Muscular" }, Random.new(2)), 3, 1):MinSep()
	check("foul: the referee walks in on the call", fs.called ~= nil and fs.seenFoul, fs.called)
	check("foul: in to about MinSep + warnGap of the offender", fs.nearest <= ms + REF.warnGap + 0.8, string.format("nearest %.2f (MinSep %.2f)", fs.nearest, ms))
	check("foul: never onto him", fs.under == 0, fs.under)
	check("foul: back out on the orbit after", fs.backOut)
end

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
		-- the fallen man lying right at the centre: the group stepped off him
		local L4 = PostFight.Layout(center, face, { red = heavy, blue = heavy, ref = ref }, true, false, { downAt = center })
		local downR = (heavy.stand or 5.2) * PostFight.DOWN_REACH + PostFight.DOWN_GAP
		check("PostFight.Layout: a man down at the centre - the standing man clear of him", flat(L4.blue - center).Magnitude >= downR + heavy.shoulderHalf - 0.06, flat(L4.blue - center).Magnitude)
		check("PostFight.Layout: a man down at the centre - the referee clear of him", flat(L4.ref - center).Magnitude >= downR + ref.shoulderHalf - 0.06, flat(L4.ref - center).Magnitude)
		check("PostFight.Layout: a man down - the standing man and the referee keep their spacing", math.abs(along(L4.blue) - along(L4.ref)) >= heavy.shoulderHalf + ref.shoulderHalf + 0.5)
		-- inside the ropes: a clamp to +-5 holds every standing spot in
		local function clamp5(p)
			return V3.new(math.clamp(p.X, -5, 5), p.Y, math.clamp(p.Z, -5, 5))
		end
		local L5 = PostFight.Layout(V3.new(4.5, 0, 0), face, { red = heavy, blue = heavy, ref = ref }, nil, nil, { clamp = clamp5 })
		local inside = true
		for _, k in ipairs({ "red", "blue", "ref" }) do
			if math.abs(L5[k].X) > 5.01 or math.abs(L5[k].Z) > 5.01 then
				inside = false
			end
		end
		check("PostFight.Layout: the group stepped in off the ropes", inside, string.format("red %.2f blue %.2f", L5.red.X, L5.blue.X))
		if verbose then
			print(string.format("  layout heavy/heavy: red %.2f ref %.2f blue %.2f (shoulder halves %.2f / %.2f)", along(L.red), along(L.ref), along(L.blue), heavy.shoulderHalf, ref.shoulderHalf))
		end
	end
end

print(string.format("test_spacing: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
