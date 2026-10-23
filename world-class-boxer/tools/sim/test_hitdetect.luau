--!nocheck
-- tools/sim/test_hitdetect.luau: the hit detection off the rigs (Shared.HitGeometry) and its use in FightEngine
-- (tools/sim/fightsim: the real Fight methods on stub rigs), pinned:
--   * calibration: the unit rig against itself lands every punch at exactly the distance the fight was balanced on
--     (FightMotion.Spacing.base x Config.Punches[p].range), the unit pair's separation and clinch reach are the old
--     spacing's
--   * height: a short man's straights and hooks to a much taller head fall short where the tall man's land, and
--     fall to the body out at range; the tall man bent over (a duck, a roll) is reachable; uppercuts reach up
--     (the short man's lands on the tall chin from inside) and the longer man's jab reaches further than the
--     shorter man's; every punch type, short vs tall, tall vs short, the same height
--   * the frame scales at their limits (Builder.Scales' clamps) never break it: finite ranges, separation that
--     keeps the torsos apart, a clinch reach past the separation
--   * the engine: PunchRange is the geometry's (floored at the close spacing), Resolve misses "short" / lands /
--     turns a head shot into a body shot the way the geometry says, a leave mid-spar ends the session on the cards
--     with the share boxed
--   * the animation: every punch (head and body) thrown at every frame pairing from below the separation out to its
--     reach + 0.5 lands then misses once (a monotone boundary) and that boundary is within 0.25 stud of where
--     AnimFight's glove visibly reaches the target (tools/sim/anim_reach.json, measured by v9_anim --clips reach on
--     the tier-3 rigs; the frames the server reads off those rigs); MinSep + 0.3 < PunchRange(jab) both ways for
--     every pairing, the rigs' and the sims' scale frames at 60 / 70 / 84 inches
--   * the facing: a straight thrown off the line it faces goes wide, a hook finds a head well off it
--   * lag compensation at 80-150 ms against a man backing off (and circling): the hit his screen showed stands when
--     the live miss is movement within LAG_TOL; a press his screen showed short, one with no stamp and one the man
--     got a stud clear of stay misses
--   lune run tools/sim/test_hitdetect.luau
local process = require("@lune/process")
local FS = require("./fightsim")

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
local function finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local S = FS.new()
local HG = S.H.require("HitGeometry")
local Config = S.Config
local Random = S.H.globals.Random
local PUNCHES = { "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }

------------------------------------------------------------------------
-- the frames
------------------------------------------------------------------------
local U = HG.Unit()
check("unit: stands about 6.5 studs, 7 heads", U.stand > 6.3 and U.stand < 6.6 and near(U.stand / (U.headR * 2), 7, 0.4), U.stand)
check("unit: the arm from the shoulder to the glove's face", U.arm > 2.3 and U.arm < 2.9, U.arm)
check("unit: head over chest over waist", U.headY > U.chestY and U.chestY > U.shoulderY and U.shoulderY > U.waistY)

local function frame(hIn, frameId, extra)
	local sc = { height = math.clamp(hIn / 70, 0.86, 1.2), width = 1, depth = 1 }
	local bt = Config.FindById(Config.BodyTypes, frameId or "Athletic")
	if bt then
		sc.width, sc.depth = bt.width, bt.depth
	end
	local o = { height = hIn, reach = hIn }
	for k, v in pairs(extra or {}) do
		o[k] = v
	end
	return HG.FrameFromScales(sc, o)
end
local SHORT, MID, TALL = frame(60, "Lean"), frame(70), frame(84, "Heavyweight Build")
check("frames: taller is taller everywhere", TALL.stand > MID.stand and MID.stand > SHORT.stand and TALL.shoulderY > SHORT.shoulderY and TALL.headY > SHORT.headY)
check("frames: a heavyweight's chest is deeper and wider", TALL.torsoHalfD > MID.torsoHalfD and TALL.torsoHalfW > MID.torsoHalfW)
check("frames: the tape's reach stretches the arm a little", frame(70, nil, { reach = 76 }).arm > MID.arm and frame(70, nil, { reach = 76 }).arm < MID.arm * 1.1)
check("frames: a woman's frame is narrower", frame(70, nil, { female = true }).torsoHalfW < MID.torsoHalfW)

-- a fake rig: parts with sizes and positions, as FightEngine's geoFrame reads a character
local V3 = S.H.globals.Vector3
local function rig(hs)
	local parts = {}
	local function part(name, size, y)
		parts[name] = { Size = V3.new(size[1] * hs, size[2] * hs, size[3] * hs), Position = V3.new(0, y * hs + 100, 0) }
	end
	part("HumanoidRootPart", { 2, 2, 1 }, 3.67)
	part("Head", { 0.93, 0.93, 0.93 }, 5.99)
	part("UpperTorso", { 1.59, 2.08, 0.97 }, 4.25)
	part("LowerTorso", { 1.59, 0.52, 0.97 }, 2.95)
	part("LeftUpperArm", { 0.6, 1.0, 0.6 }, 4.4)
	part("LeftLowerArm", { 0.45, 0.93, 0.45 }, 3.5)
	part("LeftHand", { 0.3, 0.63, 0.55 }, 2.8)
	part("GloveL", { 0.59, 0.73, 0.61 }, 2.6)
	return { FindFirstChild = function(_, n)
		return parts[n]
	end }
end
local R1 = HG.Frame(rig(1), 100, U)
-- (the arm is the hanging chain, shoulder pivot (0.2 under the upper arm's top) to the glove's bottom: 4.7 - 2.235)
check("rig: a frame off the parts", R1.source == "rig" and R1.fallback == nil and near(R1.headY, 5.99, 0.01) and near(R1.torsoHalfD, 0.485, 0.01) and near(R1.arm, 4.7 - 2.235, 0.02) and near(R1.glove, 0.305, 0.01), R1.arm)
check("rig: the arm is never the sum of the part boxes", R1.arm < 1.0 + 0.93 + 0.73 - 0.1, R1.arm)
local R12 = HG.Frame(rig(1.2), 100, U)
check("rig: a 1.2 x rig is 1.2 x taller with 1.2 x the arm", near(R12.stand, R1.stand * 1.2, 0.02) and near(R12.arm, R1.arm * 1.2, 0.02))
check("rig: no root, the fallback", HG.Frame({ FindFirstChild = function()
	return nil
end }, 100, U).source == "scales")
check("rig: nonsense parts keep the fallback", HG.Frame({ FindFirstChild = function(_, n)
	return n == "HumanoidRootPart" and { Size = V3.new(2, 2, 1), Position = V3.new(0, 103, 0) } or (n == "Head" and { Size = V3.new(1, 1, 1), Position = V3.new(0, 0, 0) }) or nil
end }, 100, U).stand == U.stand)

------------------------------------------------------------------------
-- calibration and the same height
------------------------------------------------------------------------
-- (HitGeometry.TARGET: where the animation's glove visibly lands on the Athletic rig, tools/sim/v9_anim's reach clip;
-- the old balanced spacing BASE x range was 0.8-1.6 studs SHORT of it, so punches the player saw land came back
-- "short". HitGeometry.RIG is that rig as the server reads it; the sims' unit frame lands within a quarter stud)
local RIG = HG.RIG
for _, p in ipairs(PUNCHES) do
	local T = HG.TARGET[p]
	check("calibration: " .. p .. " lands at the animation's distance (the Athletic rig)", near(HG.Range(RIG, RIG, p, false), T.head, 0.01), HG.Range(RIG, RIG, p, false) .. " vs " .. T.head)
	local body = HG.Range(RIG, RIG, p, true)
	check("calibration: " .. p .. " to the body at its own", near(body, T.body, 0.01), body .. " vs " .. T.body)
	check("calibration: " .. p .. " reaches further than the old spacing did", T.head > HG.BASE * Config.Punches[p].range)
	check("calibration: the sims' unit frame's " .. p .. " within a quarter stud of the rig's", math.abs(HG.Range(U, U, p, false) - T.head) <= 0.25 and math.abs(HG.Range(U, U, p, true) - T.body) <= 0.25,
		string.format("%.2f / %.2f vs %.2f / %.2f", HG.Range(U, U, p, false), HG.Range(U, U, p, true), T.head, T.body))
end
check("calibration: the unit pair's separation is the old spacing", near(HG.MinSep(U, U), HG.MIN_SEP, 0.01), HG.MinSep(U, U))
check("calibration: the unit pair's clinch reach is the old spacing", near(HG.ClinchRange(U, U), HG.CLINCH, 0.01), HG.ClinchRange(U, U))
-- (the animation: the cross's hip turn carries it past the jab's flick; the lead hook and the uppercut are the
-- short punches; the rear hook comes through like the cross)
check("same height: the cross outreaches the jab, the jab the lead hook, the lead hook the uppercut", HG.Range(MID, MID, "cross", false) > HG.Range(MID, MID, "jab", false) and HG.Range(MID, MID, "jab", false) > HG.Range(MID, MID, "leadhook", false) and HG.Range(MID, MID, "leadhook", false) > HG.Range(MID, MID, "uppercut", false))
do
	local t = HG.Test(U, U, "jab", false, 4.0)
	check("test: a jab from 4.0 lands on the head, with margin", t.ok and t.zone == "head" and not t.redirected and t.margin > 0.3, t.margin)
	local m = HG.Test(U, U, "jab", false, 5.8)
	check("test: a jab from 5.8 is short", not m.ok and m.why == "short")
	local b = HG.Test(U, U, "leadhook", true, 3.4)
	check("test: a hook to the body from 3.4 lands", b.ok and b.zone == "body")
end

------------------------------------------------------------------------
-- height
------------------------------------------------------------------------
local M66, M76 = frame(66), frame(76, "Muscular")
for _, p in ipairs({ "jab", "cross" }) do
	local up, down, lvlS, lvlT = HG.Range(M66, M76, p, false), HG.Range(M76, M66, p, false), HG.Range(M66, M66, p, false), HG.Range(M76, M76, p, false)
	check("height: the shorter man's " .. p .. " to the head is cut (66 vs 76 in)", up < lvlS - 0.2 and up > lvlS * 0.8, up .. " vs " .. lvlS)
	check("height: the taller man's " .. p .. " down to the head is not", down >= lvlT - 0.05, down .. " vs " .. lvlT)
	check("height: the longer man's " .. p .. " reaches further", down > up + 0.5, down .. " vs " .. up)
	check("height: the shorter man's " .. p .. " to the body keeps its reach", HG.Range(M66, M76, p, true) >= HG.Range(M66, M66, p, true) - 0.05)
end
check("height: the shorter man's hook to the head is a close-range punch", HG.Range(M66, M76, "leadhook", false) < HG.Range(M66, M66, "leadhook", false) - 0.4)
check("height: the shorter man's overhand to a taller head is cut hard", HG.Range(M66, M76, "overhand", false) < HG.Range(M66, M66, "overhand", false) - 0.4)
check("height: the taller man's overhand comes down fine", HG.Range(M76, M66, "overhand", false) >= HG.Range(M76, M76, "overhand", false) - 0.1)
check("height: a bent (ducking) tall man is reachable", HG.Range(M66, M76, "jab", false, { bend = 1 }) > HG.Range(M66, M76, "jab", false) + 0.3)
-- the extreme pair (Builder.Scales' clamps: 60 vs 84 in)
do
	local floor = 3.4
	for _, p in ipairs({ "jab", "cross", "leadhook", "overhand" }) do
		local far = HG.Test(SHORT, TALL, p, false, 4.6, { floor = floor })
		check("extreme: the short man's " .. p .. " to the tall head from 4.6 falls to the body or misses", not far.ok or far.redirected, far.zone)
	end
	local inJab = HG.Test(SHORT, TALL, "jab", false, floor, { floor = floor })
	check("extreme: the short man's jab reaches the tall chin inside", inJab.ok and inJab.zone == "head", inJab.why)
	local inUp = HG.Test(SHORT, TALL, "uppercut", false, floor, { floor = floor })
	check("extreme: the short man's uppercut reaches the tall chin inside", inUp.ok and inUp.zone == "head", inUp.why)
	local inHook = HG.Test(SHORT, TALL, "leadhook", false, floor, { floor = floor })
	check("extreme: the short man's hook to the tall head falls to the body even inside", inHook.ok and inHook.zone == "body" and inHook.redirected, inHook.zone)
	local bent = HG.Test(SHORT, TALL, "leadhook", false, floor, { floor = floor, bend = 1 })
	check("extreme: ...unless the tall man is bent over", bent.ok and bent.zone == "head", bent.why)
	for _, p in ipairs(PUNCHES) do
		local d = HG.Test(TALL, SHORT, p, false, floor, { floor = floor })
		check("extreme: the tall man's " .. p .. " lands on the short head inside", d.ok and d.zone == "head", tostring(d.why))
	end
	local tb = HG.Test(TALL, SHORT, "jab", true, floor, { floor = floor })
	check("extreme: the tall man's jab to the short body lands inside", tb.ok and tb.zone == "body")
	check("extreme: uppercuts favour the shorter man (his punch weights)", (function()
		local p = HG.PunchPrefs(SHORT, TALL)
		local q = HG.PunchPrefs(TALL, SHORT)
		return p.uppercut > 1.1 and p.jab < 0.95 and q.jab > 1.1 and q.uppercut < 0.95
	end)())
	check("extreme: no preference at the same height and reach", (function()
		local p = HG.PunchPrefs(MID, MID)
		return p.jab == 1 and p.uppercut == 1
	end)())
	-- the ranges FightEngine would cache (level stance, the floor): finite, the floor at least, under the ring
	for _, p in ipairs(PUNCHES) do
		local a, b = HG.Range(SHORT, TALL, p, false, { floor = floor }), HG.Range(TALL, SHORT, p, false, { floor = floor })
		check("extreme: " .. p .. " ranges are sane", finite(a) and finite(b) and a >= 0 and b >= floor and b < 9, a .. " / " .. b)
	end
end

------------------------------------------------------------------------
-- the frame scales at their limits
------------------------------------------------------------------------
do
	local big = HG.FrameFromScales({ height = 1.2, width = 1.4, depth = 1.4, head = 0.85 }, { height = 84, reach = 90 })
	local small = HG.FrameFromScales({ height = 0.86, width = 0.7, depth = 0.7, head = 0.75 }, { height = 60, reach = 56, female = true })
	for _, pair in ipairs({ { big, big }, { small, small }, { big, small }, { small, big } }) do
		local A, B = pair[1], pair[2]
		local sep = HG.MinSep(A, B)
		check("scales: separation keeps the torsos apart", finite(sep) and sep > A.torsoHalfD + B.torsoHalfD + 2 * (A.glove + B.glove), sep)
		check("scales: the clinch reaches past the separation", finite(HG.ClinchRange(A, B)) and HG.ClinchRange(A, B) > sep)
		for _, p in ipairs(PUNCHES) do
			local r = HG.Range(A, B, p, false, { floor = 3.4 })
			check("scales: " .. p .. " range finite", finite(r) and r >= 0 and r < 10, r)
			local t = HG.Test(A, B, p, false, 3.0, { floor = 3.4, bend = 0.5 })
			check("scales: " .. p .. " test finite", type(t.ok) == "boolean" and finite(t.dy))
		end
	end
	check("scales: a big man's separation is bigger than a small pair's", HG.MinSep(big, big) > HG.MinSep(small, small) + 1)
end

------------------------------------------------------------------------
-- the engine
------------------------------------------------------------------------
local function data(style, hIn, rIn)
	local d = S.Boxer({ style = style or "BoxerPuncher", level = 60 }, Random.new(5))
	for _, k in ipairs(Config.StatKeys) do
		d.stats[k] = 60
	end
	d.height, d.reach = hIn, rIn or hIn
	return d
end
local function fight(red, blue)
	local f = S.NewFight(red, blue, 3, 11)
	f.sp = nil -- (the default spacing)
	for _, F in ipairs({ f.P, f.O }) do
		F.health, F.body, F.stamina, F.balance = 100, 100, F.maxStam, 100
	end
	f.live = true
	return f
end
do
	local f = fight(data("BoxerPuncher", 70), data("BoxerPuncher", 70))
	local P, O = f.P, f.O
	check("engine: a stub rig's frame comes from the tape", f:Geo(P) and f:Geo(P).source == "scales")
	for _, p in ipairs(PUNCHES) do
		-- (PunchRange is where the punch LANDS: the further of the head's and the body's reach, an overhand the head's -
		-- the geometry's number on the pair's frames, and the animation's within a quarter stud)
		local want = math.max(f:Floor(), HG.Reach(f:Geo(P), f:Geo(O), p, { floor = f:Floor() }))
		local anim = p == "overhand" and HG.TARGET[p].head or math.max(HG.TARGET[p].head, HG.TARGET[p].body)
		check("engine: PunchRange " .. p .. " is the geometry's reach at 70 / 70", near(f:PunchRange(P, p), want, 0.02), f:PunchRange(P, p) .. " vs " .. want)
		check("engine: PunchRange " .. p .. " is the animation's number within a quarter stud", math.abs(f:PunchRange(P, p) - anim) <= 0.25, f:PunchRange(P, p) .. " vs " .. anim)
	end
	check("engine: the floor is the separation plus the air a jab needs", near(f:Floor(), math.max(S.H.require("FightMotion").Spacing.min, f:MinSep() + 0.3), 1e-6), f:Floor())
	check("engine: MinSep is the fight spacing for the unit pair", near(f:MinSep(), S.H.require("FightMotion").Spacing.minSep, 0.02), f:MinSep())
	check("engine: the clinch reach is the old spacing for the unit pair", near(f:ClinchRange(P), 4.8, 0.01), f:ClinchRange(P))
	check("engine: a longer tape reaches further", (function()
		local g = fight(data("BoxerPuncher", 70, 78), data("BoxerPuncher", 70))
		return g:PunchRange(g.P, "jab") > f:PunchRange(P, "jab") + 0.05
	end)())
	-- the hit test through Resolve: in range lands or misses by the roll, out of range is "short"
	local function place(d)
		local V = S.H.globals.Vector3
		local CF = S.H.globals.CFrame
		P.root.CFrame = CF.lookAt(V.new(-d / 2, 3.2, 0), V.new(d / 2, 3.2, 0))
		O.root.CFrame = CF.lookAt(V.new(d / 2, 3.2, 0), V.new(-d / 2, 3.2, 0))
	end
	local shorts, lands = 0, 0
	f.Send = function(_, m)
		if m.t == "miss" and m.why == "short" then
			shorts += 1
		end
	end
	place(6)
	for _ = 1, 10 do
		f:Resolve(P, O, "jab", false, 1)
	end
	check("engine: a jab from 6 studs is short", shorts == 10, shorts)
	place(4.2)
	local before = P.totals.landed
	for _ = 1, 40 do
		f:Resolve(P, O, "jab", false, 1)
	end
	lands = P.totals.landed - before
	check("engine: a jab from 4.2 lands (the roll decides)", shorts == 10 and lands > 10, lands)
end
do
	-- a short man against a tall one: his jab from range goes to the body, the tall man's lands upstairs
	local f = fight(data("BoxerPuncher", 60), data("BoxerPuncher", 84))
	local P, O = f.P, f.O
	f.sp = { base = 4.3, min = 3.4, minSep = 3.25, inside = 3.65, clinch = 4.8, pivot = 3.9, cover = 5.8 }
	local V, CF = S.H.globals.Vector3, S.H.globals.CFrame
	local function place(d)
		P.root.CFrame = CF.lookAt(V.new(-d / 2, 3.2, 0), V.new(d / 2, 3.2, 0))
		O.root.CFrame = CF.lookAt(V.new(d / 2, 3.2, 0), V.new(-d / 2, 3.2, 0))
	end
	local redirects, bodyHits = 0, 0
	f.Send = function(_, m)
		if m.t == "redirect" then
			redirects += 1
		end
	end
	place(3.9)
	local b0 = P.tally.body
	for _ = 1, 30 do
		f:Resolve(P, O, "jab", false, 1)
	end
	bodyHits = P.tally.body - b0
	check("engine: the short man's jab from 3.9 is thrown to the tall man's body", redirects == 30 and bodyHits > 0 and bodyHits == P.totals.landed, redirects .. " / " .. bodyHits)
	check("engine: the short man's jab from 4.0 falls to the tall man's body", f:HitTest(P, O, "jab", false, 4.0).ok and f:HitTest(P, O, "jab", false, 4.0).redirected)
	check("engine: the short man's jab from 5.6 reaches nothing on the tall man", not f:HitTest(P, O, "jab", false, 5.6).ok and f:HitTest(P, O, "jab", false, 5.6).why == "short")
	check("engine: PunchRange is where the punch LANDS (the body included): the short man's jab is thrown from 4.0", f:PunchRange(P, "jab") > 4.0 and f:PunchRange(P, "jab") > HG.Range(f:Geo(P), f:Geo(O), "jab", false, { floor = f:Floor() }))
	check("engine: the tall man's jab from 4.4 is a head shot", f:HitTest(O, P, "jab", false, 4.4).ok and f:HitTest(O, P, "jab", false, 4.4).zone == "head")
	-- (Builder.Scales puts 2.6 studs between these two crowns: inside, the jab lands - on the chin when the angle
	-- allows, else it falls to the body; it never comes back "short")
	check("engine: the short man's jab inside lands (chin or body)", f:HitTest(P, O, "jab", false, 3.4).ok and f:HitTest(P, O, "jab", false, 3.4).why == nil)
	check("engine: a rolling tall man is a head target from closer than a standing one", (function()
		local G, OG = f:Geo(P), f:Geo(O)
		return HG.Range(G, OG, "jab", false, { bend = 1 }) > HG.Range(G, OG, "jab", false) + 0.3 and f:HitTest(P, O, "jab", false, 3.4).ok
	end)())
	check("engine: a Punch at a tall man from range is thrown to the body (the act says so)", (function()
		place(3.9)
		P.busyUntil, P.state = 0, "idle"
		P.stamina = P.maxStam
		f:Punch(P, "jab", false)
		return P.punchBody == true and tostring(P.model:GetAttribute("Act")):find("|body|", 1, true) ~= nil
	end)(), tostring(P.model:GetAttribute("Act")))
	check("engine: the AI's punch weights favour the short man's uppercut", (function()
		local p = f:GeoPrefs(P)
		return p and p.uppercut > 1.1 and p.jab < 1
	end)())
	check("engine: the pair's separation grows with the heavyweight", f:MinSep() > 3.25)
	check("engine: the short man's clinch reach is shorter than the tall man's", f:ClinchRange(P) < f:ClinchRange(O) and f:ClinchRange(P) > f:MinSep())
	-- the AI's Fits / Range stay inside sane numbers for the pair
	local ai = S.FightAI.new(O, P, f)
	check("engine: FightAI's range for the tall man is a reach, not a jump", ai:Range() > 3 and ai:Range() < 7, ai:Range())
	local ai2 = S.FightAI.new(P, O, f)
	check("engine: FightAI's range for the short man is shorter than the tall man's", ai2:Range() < ai:Range(), ai2:Range() .. " vs " .. ai:Range())
end
------------------------------------------------------------------------
-- the boundary against the animation, every frame pairing: each punch (head and body) thrown from below the pair's
-- separation out to its reach + 0.5 in 0.02 steps lands, then misses, once (a monotone boundary: never a miss
-- inside a hit), and the last distance it lands from is within 0.25 stud of where AnimFight's glove visibly
-- reaches the target (tools/sim/anim_reach.json: v9_anim --clips reach on the tier-3 rigs of the five frames, the
-- frames HitGeometry.Frame read off the same rigs - the server's frames in Studio). And the invariant the spacing
-- keeps: MinSep + 0.3 < PunchRange(jab) both ways, through the engine, for every pairing
------------------------------------------------------------------------
do
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local AR = serde.decode("json", fs.readFile(S.H.root .. "/tools/sim/anim_reach.json"))
	local KEYS = { "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand", "jab|body", "cross|body", "leadhook|body", "rearhook|body", "uppercut|body" }
	local worst, worstWhat, n, nonMono = 0, "", 0, 0
	local FE = S.FightEngine
	local pairsSeen = 0
	for _, pr in ipairs(AR.pairs) do
		local A, B = pr.geoA, pr.geoB
		pairsSeen += 1
		local sep = HG.MinSep(A, B)
		local floor = sep + FE.FLOOR_AIR
		for _, key in ipairs(KEYS) do
			local p, z = key:match("^(%a+)|?(%a*)$")
			local body = z == "body"
			local anim = pr.boundary[key]
			local reach = HG.Range(A, B, p, body, { floor = floor })
			local last, missed, mono = nil, false, true
			local d = sep - 0.4
			while d <= reach + 0.5 do
				local ok = HG.Test(A, B, p, body, d, { floor = floor, noRedirect = true }).ok
				if ok then
					if missed then
						mono = false
					end
					last = d
				else
					missed = true
				end
				d += 0.02
			end
			n += 1
			if not mono then
				nonMono += 1
				print(string.format("  non-monotone: %s -> %s %s", pr.frame, pr.oframe, key))
			end
			local e = last and math.abs(last - anim) or math.huge
			if e > worst then
				worst, worstWhat = e, string.format("%s -> %s %s: hit test %.2f, animation %.2f", pr.frame, pr.oframe, key, last or -1, anim)
			end
			check(string.format("boundary: %s -> %s %s lands out to the animation's reach (%.2f vs %.2f)", pr.frame, pr.oframe, key, last or -1, anim), last ~= nil and e <= 0.25)
		end
		-- the invariant, through the engine on these frames
		local f = fight(data("BoxerPuncher", 70), data("BoxerPuncher", 70))
		f.P.geo, f.O.geo = A, B
		f.minSepGeo = nil
		local s2 = f:MinSep()
		local jP, jO = f:PunchRange(f.P, "jab"), f:PunchRange(f.O, "jab")
		check(string.format("invariant: %s vs %s MinSep + 0.3 < PunchRange(jab) both ways (%.2f / %.2f / %.2f)", pr.frame, pr.oframe, s2, jP, jO), s2 + 0.3 < jP and s2 + 0.3 < jO)
	end
	check("boundary: all 25 frame pairings measured", pairsSeen == 25, pairsSeen)
	check("boundary: every punch's hit / miss boundary is monotone", nonMono == 0, nonMono)
	print(string.format("  boundary: worst |hit test - animation| %.3f stud over %d punches (%s)", worst, n, worstWhat))
end
-- the same invariant on the sims' frames (FrameFromScales: the five frames at 60, 70 and 84 inches, every pairing)
do
	local FRAMES = { "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build" }
	local bad, n = {}, 0
	for _, fa in ipairs(FRAMES) do
		for _, fb in ipairs(FRAMES) do
			for _, ha in ipairs({ 60, 70, 84 }) do
				for _, hb in ipairs({ 60, 70, 84 }) do
					local f = fight(data("BoxerPuncher", ha), data("BoxerPuncher", hb))
					f.P.geo, f.O.geo = frame(ha, fa), frame(hb, fb)
					f.minSepGeo = nil
					local sep = f:MinSep()
					local jP, jO = f:PunchRange(f.P, "jab"), f:PunchRange(f.O, "jab")
					n += 1
					if not (sep + 0.3 < jP and sep + 0.3 < jO) then
						table.insert(bad, string.format("%s %d vs %s %d: %.2f / %.2f / %.2f", fa, ha, fb, hb, sep, jP, jO))
					end
				end
			end
		end
	end
	check(string.format("invariant: MinSep + 0.3 < PunchRange(jab) on all %d scale-frame pairings", n), #bad == 0, bad[1])
end
------------------------------------------------------------------------
-- the facing: a straight goes where the shoulders point, a hook comes round to a head off the line
------------------------------------------------------------------------
do
	local R = HG.RIG
	check("facing: a jab 20 degrees off the line lands", HG.Test(R, R, "jab", false, 4.4, { facing = 20 }).ok)
	local w = HG.Test(R, R, "jab", false, 4.4, { facing = 45 })
	check("facing: a jab 45 degrees off the line goes wide", not w.ok and w.why == "wide" and w.margin < 0, w.why)
	check("facing: a lead hook 50 degrees off it still finds the head", HG.Test(R, R, "leadhook", false, 4.0, { facing = 50 }).ok)
	check("facing: a hook 75 degrees off it is wide", HG.Test(R, R, "leadhook", false, 4.0, { facing = 75 }).why == "wide")
	check("facing: the cones by kind (straight < uppercut < overhand < hook)", HG.FACING.straight < HG.FACING.uppercut and HG.FACING.uppercut < HG.FACING.overhand and HG.FACING.overhand < HG.FACING.hook)
	-- through the engine: P turned 45 degrees off O
	local f = fight(data("BoxerPuncher", 70), data("BoxerPuncher", 70))
	local P, O = f.P, f.O
	O.ai = nil
	local V, CF = S.H.globals.Vector3, S.H.globals.CFrame
	P.root.CFrame = CF.lookAt(V.new(0, 3.2, 0), V.new(4, 3.2, 4))
	O.root.CFrame = CF.lookAt(V.new(4.2, 3.2, 0), V.new(0, 3.2, 0))
	local why = nil
	f.Send = function(_, m)
		if m.t == "miss" then
			why = m.why
		end
	end
	f:Resolve(P, O, "jab", false, 1)
	check("facing: the engine calls a jab thrown 45 degrees off him wide", why == "wide" and P.lastHit and P.lastHit.why == "wide", why)
	f:Resolve(P, O, "leadhook", false, 1)
	check("facing: and lets the hook from there reach him", P.lastHit and P.lastHit.ok, P.lastHit and P.lastHit.why)
	-- /wcbdiag's FIGHT block shows the verdict (and the AI's read when there is a brain)
	O.ai = S.FightAI.new(O, P, f)
	local okD, lines = pcall(S.H.require("Diag").FightLines, f)
	local text = okD and table.concat(lines, "\n") or tostring(lines)
	check("diag: the FIGHT block prints the last punch's verdict and the AI's read", text:find("last punch leadhook", 1, true) ~= nil and text:find("AI read:", 1, true) ~= nil, text:sub(1, 200))
end

------------------------------------------------------------------------
-- lag compensation: a player's punch at 80-150 ms of one-way delay against a man moving away (and across). His
-- client pressed when its screen showed the opponent inside the reach; the server resolves it a delay and a
-- wind-up later, when the man has moved on. A miss by movement within LAG_TOL stands as the hit his client showed;
-- a punch his screen showed out of reach, or one the man got well clear of, stays a miss; an AI's punch is never
-- compensated. The server's clock is the scheduler's (the client stamps workspace:GetServerTimeNow())
------------------------------------------------------------------------
do
	S.H.Service("Workspace")._props.GetServerTimeNow = function()
		return S.now()
	end
	local FE = S.FightEngine
	local V, CF = S.H.globals.Vector3, S.H.globals.CFrame
	local INTERP = 0.1 -- (FightEngine's POSE_INTERP)
	-- one press: the opponent walks at vel (studs/s, flat: x = away along the line, z = across) the whole time; the
	-- client's screen at the press shows him `seenGap` past the jab's boundary (negative = inside it). Returns the
	-- engine's verdict on the punch (P.lastHit) and the live / press-time numbers
	local function press(lag, seenGap, vel, opts)
		opts = opts or {}
		S.setClock(2000)
		local f = fight(data("BoxerPuncher", 70), data("BoxerPuncher", 70))
		local P, O = f.P, f.O
		P.isPlayer = true
		O.ai = nil
		f.Send = function() end
		-- (the reach the engine gates on: the head's, or the body's where a head shot falls there)
		local R = f:PunchRange(P, "jab")
		local windup = Config.Punches.jab.windup * 1.0
		-- where O must be on the press's screen, and so where he is at every moment (his walk is a straight line)
		local tPress = 2000.5
		local tSeen = tPress - lag - INTERP
		local seenX = R + seenGap
		local function oAt(t)
			return V.new(seenX + vel.X * (t - tSeen), 3.2, vel.Z * (t - tSeen))
		end
		P.root.CFrame = CF.lookAt(V.new(0, 3.2, 0), oAt(tSeen))
		local resolved = false
		local arrive = tPress + lag
		local dt = 1 / 60
		while S.now() < arrive + 0.6 do
			local now = S.now()
			O.root.CFrame = CF.lookAt(oAt(now), V.new(0, 3.2, 0))
			f:RecordPose(P, now)
			f:RecordPose(O, now)
			if not resolved and now >= arrive then
				resolved = true
				P.busyUntil, P.state, P.stamina = 0, "idle", P.maxStam
				local stamp = tPress
				if opts.noStamp then
					stamp = nil
				end
				f:Punch(P, "jab", false, nil, nil, stamp)
				windup = P.busyUntil > now and tonumber(tostring(P.model:GetAttribute("Act")):match("^[^|]*|[^|]*|[^|]*|([%d%.]+)")) or windup
			end
			S.advance(dt)
		end
		local liveD = (oAt(arrive + windup) - V.new(0, 3.2, 0)).Magnitude
		return P.lastHit, R, liveD
	end
	for _, ms in ipairs({ 80, 100, 120, 150 }) do
		local lag = ms / 1000
		-- backing away at a walk: the press was 0.15 inside the reach, he drifts 0.15-0.35 past it by the contact
		local span = 2 * lag + INTERP + Config.Punches.jab.windup
		local v = (0.15 + 0.3) / span
		local h, R, live = press(lag, -0.15, V.new(v, 0, 0))
		R = R or 5
		check(string.format("lag %d ms: the jab his screen showed land on a man backing off lands (live %.2f > reach %.2f)", ms, live, R),
			h and h.ok and h.lagComp == true and h.liveWhy == "short", h and string.format("ok=%s comp=%s why=%s margin=%s", tostring(h.ok), tostring(h.lagComp), tostring(h.why), tostring(h.margin)))
		-- the same man moving across the line as well (circling at 2 studs/s while he backs off), 0.2 past the reach
		-- at the contact (the radial speed solved for it)
		local side = 2 * span
		local radial = (math.sqrt(math.max(0, (R + 0.2) ^ 2 - side * side)) - (R - 0.15)) / span
		local h2 = press(lag, -0.15, V.new(radial, 0, 2))
		check(string.format("lag %d ms: and on a man circling away", ms), h2 and h2.ok, h2 and tostring(h2.why))
		-- without the stamp (an old client) the same punch is the live miss
		local h3 = press(lag, -0.15, V.new(v, 0, 0), { noStamp = true })
		check(string.format("lag %d ms: no press stamp, no compensation (the live miss)", ms), h3 and not h3.ok and not h3.lagComp, h3 and string.format("ok=%s why=%s dist=%.2f zone=%s comp=%s lag=%s", tostring(h3.ok), tostring(h3.why), h3.dist or -1, tostring(h3.zone), tostring(h3.lagComp), tostring(h3.lag)))
		-- his screen showed him out of reach: a miss on both screens
		local h4 = press(lag, 0.25, V.new(v, 0, 0))
		check(string.format("lag %d ms: a press his screen showed short stays short", ms), h4 and not h4.ok and h4.why == "short", h4 and tostring(h4.ok))
		-- he got well clear (a stud past the reach by the contact): more than movement can excuse
		local vFar = (0.15 + 1.0) / span
		local h5 = press(lag, -0.15, V.new(vFar, 0, 0))
		check(string.format("lag %d ms: a man a stud clear at the contact is a miss (LAG_TOL %.2f)", ms, FE.LAG_TOL), h5 and not h5.ok and not h5.lagComp, h5 and tostring(h5.margin))
	end
	check("lag: the tolerance is about a third of a stud", FE.LAG_TOL >= 0.3 and FE.LAG_TOL <= 0.4, FE.LAG_TOL)
end
do
	-- leaving a spar: the cards so far, the share boxed, no stuck round
	local f = fight(data("BoxerPuncher", 70), data("BoxerPuncher", 70))
	f.spar, f.rounds, f.roundSeconds = "Medium", 2, 60
	f.P.isPlayer = true
	f.cards = { { 10, 9 }, { 10, 9 }, { 10, 9 } }
	f.round = 2
	f.roundEnd = f:Now() + 30
	local msgs = {}
	f.Send = function(_, m)
		table.insert(msgs, m.t)
	end
	check("leave: not from a fight", (function()
		local g = fight(data(), data())
		g.P.isPlayer = true
		return g:LeaveSpar(g.P) == false and not g.finished
	end)())
	check("leave: not by the AI side", f:LeaveSpar(f.O) == false and not f.finished)
	check("leave: ends the session on the cards", f:LeaveSpar(f.P) == true and f.finished and f.live == false and f.sparExit and f.sparExit.outcome == "win" and f.sparExit.method == "Ended")
	check("leave: the share boxed (a round and a half of two)", near(f.sparExit.partial, 0.75, 0.01), f.sparExit.partial)
	check("leave: the coach says so", table.find(msgs, "announce") ~= nil)
	check("leave: a second leave is nothing", f:LeaveSpar(f.P) == false)
	local res = f:ResultFor(f.P, f.sparExit)
	check("leave: the result carries the share", near(res.partial, 0.75, 0.01) and res.outcome == "win" and res.method == "Ended")
	local g = fight(data(), data())
	g.spar, g.rounds, g.P.isPlayer = "Light", 1, true
	g.round, g.live = 1, true
	g.roundEnd = g:Now() + g.roundSeconds
	g:LeaveSpar(g.P)
	check("leave: before anything happened it is a draw at the floor share", g.sparExit.outcome == "draw" and near(g.sparExit.partial, 0.1, 0.01), g.sparExit.partial)
end

print(string.format("test_hitdetect: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
