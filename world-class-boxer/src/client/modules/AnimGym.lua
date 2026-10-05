-- AnimGym: training poses that work the right muscles, flex poses, gym life and the people who
-- watch (coaches, ringside fans, cornermen, the referee's stance), other players' training
-- re-synthesized locally (AutoAct), sparring members who trade shots, the jump-rope visual.
-- POSE[name](p, rig, t, d, w, model, dt): d = drive (0..1 rep position: 1 = contracted / top),
-- w = cycle speed. Moved out of the Animator in round 2; walking / running members now use the
-- real gait (AnimLoco) instead of a synthetic cycle.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local K = require(script.Parent:WaitForChild("AnimKit"))
local R = require(script.Parent:WaitForChild("AnimRig"))
local L = require(script.Parent:WaitForChild("AnimLoco"))
local Fight = require(script.Parent:WaitForChild("AnimFight"))

local AnimGym = {}

local okConfig, Config = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
end)
if not okConfig then
	Config = {}
end

local player = Players.LocalPlayer
local A = CFrame.Angles
local CF = CFrame.new
local V3 = Vector3.new
local PI = math.pi
local sin, cos, abs, max, min, exp, atan2, floor = math.sin, math.cos, math.abs, math.max, math.min, math.exp, math.atan2, math.floor
local clamp = math.clamp
local smooth, lerp = K.smooth, K.lerp
local KEYS = R.KEYS
local num = R.num
local flex, flexAct, plant, legs, legAngles, seated, guardArm = R.flex, R.flexAct, R.plant, R.legs, R.legAngles, R.seated, R.guardArm
local bulkOf = R.bulkOf
local PUNCHES = { jab = true, cross = true, hook = true, leadhook = true, rearhook = true, uppercut = true, overhand = true }
AnimGym.PUNCHES = PUNCHES

-- the Animator's rig table (watchers, mitt holders, sparring partners look each other up)
local rigs = {}
function AnimGym.init(rigTable)
	rigs = rigTable
end

-- relaxed standing: breathing, a slow weight shift that never repeats (noise), feet planted,
-- the walk / run gait when the root moves
local function stand(p, rig, t, dt, breathe, shift)
	local amp = R.ampOf(rig)
	-- arms hang out from the body (+Z on the right shoulder = hand away from the hip): more with bulk,
	-- so big lats / arms clear the hips and lat overlays
	local out = 0.03 + 0.12 * bulkOf(rig)
	rig.breathPhase += dt * (0.25 + 0.1 * (breathe or 1))
	local b = K.breath(rig.breathPhase) * 0.03 * (breathe or 1)
	local ns = rig.persona and rig.persona.ns or 0
	local mv = rig.loco and rig.loco.gaitW or 0
	-- weight shift: hips drift over one leg, the torso counter-rolls (contrapposto)
	local ws = (shift or 1) * K.noise1(t * 0.21, ns + 90) * amp * (1 - mv)
	p.Root = CF(0.07 * ws, -0.03 - 0.02 * abs(ws), 0) * A(0, 0.04 * ws, -0.035 * ws)
	p.W = A(b - 0.02, 0, 0.03 * ws)
	p.Neck = A(-b * 0.6 + K.noise1(t * 0.31, ns + 91) * 0.03, K.noise1(t * 0.17, ns + 92) * 0.07 * (1 - mv), -0.02 * ws)
	p.RS = A(0.04 + b, 0, out + b * 0.5)
	p.RE = A(0.18, 0, 0)
	p.LS = A(0.04 + b, 0, -out - b * 0.5)
	p.LE = A(0.18, 0, 0)
	plant(rig, 0.1, 0.02, 0.12, -0.12, 0, 0)
	-- the unweighted leg relaxes: knee forward, heel light
	if ws > 0.3 then
		rig.foot.L.heel = 0.08 * ws
	elseif ws < -0.3 then
		rig.foot.R.heel = -0.08 * ws
	end
	L.gait(rig, "walk")
	return p
end
AnimGym.stand = stand

------------------------------------------------------------------------
-- Training poses & gym loops.  POSE[name](p, rig, t, d, w, model, dt)
-- d = drive (0..1 rep position: 1 = contracted / top), w = cycle speed
------------------------------------------------------------------------
local POSE = {}

local function stanceTraining(p, rig, t, d, w, model, dt)
	Fight.stance(p, rig, t, dt)
	local eff = num(rig.a.Effort, 0)
	rig.breath = max(rig.breath, eff * 0.8)
	return p
end
POSE.guard = stanceTraining
-- the station's use point is ~3.6 studs from the bag's axis (MapBuilder / Ambient), beyond the reach
-- of most punches: the boxer steps in to punching range (the HRP stays at the use point, the foot IK
-- keeps the feet planted and walks them in); punchAct then lands every punch on the bag's surface
POSE.heavybag = function(p, rig, t, d, w, model, dt)
	stanceTraining(p, rig, t, d, w, model, dt)
	local want = (rig.bagPart and rig.bagPart.Parent and rig.geo.ok) and (rig.bagWant or 0) or 0
	-- ease in / out (a couple of shuffle steps, not a teleport)
	local s = (rig.stepIn or 0) + (want - (rig.stepIn or 0)) * (1 - exp(-dt * 3))
	rig.stepIn = s
	if s > 0.01 then
		rig.foot.L.z -= s
		rig.foot.R.z -= s
		p.Root = CF(0, 0, -s) * p.Root
	end
	return p
end
POSE.spar = stanceTraining
POSE.shadow = stanceTraining

POSE.speedbag = function(p, rig, t, d, w, model, dt)
	local x = t * 16 * w
	-- small fast circles of the fists at eye height, elbows up, the shoulders do the work
	p.RS = A(1.55 + 0.14 * sin(x), 0, -0.42)
	p.RE = A(1.95 + 0.25 * cos(x), 0, 0)
	p.LS = A(1.55 - 0.14 * sin(x), 0, 0.42)
	p.LE = A(1.95 - 0.25 * cos(x), 0, 0)
	p.RW = A(0.25 * sin(x), 0, 0)
	p.LW = A(-0.25 * sin(x), 0, 0)
	p.W = A(0.02, 0, 0)
	p.Neck = A(0.08, 0, 0)
	p.Root = CF(0, -0.12 - abs(sin(x / 2)) * 0.03, 0)
	plant(rig, 0.45, 0.08, 0.1, -0.35, 0.15, 0.2)
	local beat = abs(sin(x))
	flex(rig, "sideDelt", 0.5 + 0.4 * beat)
	flex(rig, "frontDelt", 0.4 + 0.3 * beat)
	flex(rig, "forearms", 0.6 + 0.3 * beat)
	flex(rig, "rearDelt", 0.3)
	return p
end

POSE.bench = function(p, rig, t, d, w, model, dt)
	-- d: 0 = bar on the chest, 1 = locked out. Bar path: elbows ~45 degrees out at the bottom,
	-- arched back, leg drive through the floor, breath held at the bottom
	local drive = sin(PI * clamp(d, 0, 1))
	p.Root = A(PI / 2, 0, 0)
	p.W = A(0.12 + 0.05 * (1 - d), 0, 0)
	p.Neck = A(-0.12, 0, 0)
	local sp, el = lerp(0.32, 1.57, d), lerp(1.75, 0.05, d)
	p.RS = A(sp, 0, lerp(0.55, 0.08, d))
	p.RE = A(el, 0, 0)
	p.LS = A(sp, 0, lerp(-0.55, -0.08, d))
	p.LE = A(el, 0, 0)
	-- Poser welds the bar along the right hand's X axis: undo the elbow flare at the wrists so both
	-- hands' X axes stay on the torso's X and the bar stays level through both palms
	p.RW = (p.RS * p.RE):Inverse() * A(sp + el, 0, 0)
	p.LW = (p.LS * p.LE):Inverse() * A(sp + el, 0, 0)
	p.RH = A(0.05 - 0.08 * drive, 0, 0.22)
	p.RK = A(-1.75 + 0.12 * drive, 0, 0)
	p.RA = A(0.4, 0, 0)
	p.LH = A(0.05 - 0.08 * drive, 0, -0.22)
	p.LK = A(-1.75 + 0.12 * drive, 0, 0)
	p.LA = A(0.4, 0, 0)
	flexAct(rig, "Bench", 0.35 + 0.65 * drive)
	flex(rig, "triceps", d * d)
	flex(rig, "quads", 0.3 * drive)
	-- lockout: a little settle of the chest
	if d > 0.97 and not rig.lockout then
		rig.lockout = true
		if R.FX.BodyFX then
			R.FX.BodyFX.Jiggle(model, "chest", 0.25)
		end
	elseif d < 0.8 then
		rig.lockout = false
	end
	rig.exprHint = drive > 0.6 and "effort" or nil
	return p
end

POSE.deadlift = function(p, rig, t, d, w, model, dt)
	-- hinge: hips back, flat back, bar close; lockout with the chest up and a shrug
	local h = 1 - d
	local hinge = 1.0 * h
	p.Root = CF(0, -0.78 * h, 0.38 * h) * A(-hinge, 0, 0)
	p.W = A(-0.08 * h + 0.06 * d, 0, 0)
	p.Neck = A(0.35 * h, 0, 0)
	-- the arms hang plumb from the shoulders whatever the torso does
	local hang = hinge + 0.08 * h + 0.05
	p.RS = A(hang, 0, -0.06)
	p.LS = A(hang, 0, 0.06)
	p.RE = A(0.05, 0, 0)
	p.LE = A(0.05, 0, 0)
	plant(rig, 0, 0.1, 0.15, -0.15, 0, 0)
	flexAct(rig, "Barbell", 0.3 + 0.7 * sin(PI * d))
	flex(rig, "traps", d * d * d)
	flex(rig, "forearms", 0.9)
	rig.exprHint = (d > 0.15 and d < 0.85) and "effort" or nil
	return p
end

POSE.squat = function(p, rig, t, d, w, model, dt)
	-- brace, sit back between the heels (knees track over the toes), hips drive out of the hole
	-- first and the chest follows
	local h = 1 - d
	local depth = 1.42 * h
	local lean = 0.5 * h ^ 1.2
	p.Root = CF(0, -depth, 0.42 * h) * A(-lean, 0, 0)
	p.W = A(0.1 * h - 0.04, 0, 0)
	p.Neck = A(0.22 * h, 0, 0)
	p.RS = A(-0.25, 0, 1.25)
	p.RE = A(1.7, 0, 0)
	p.LS = A(-0.25, 0, -1.25)
	p.LE = A(1.7, 0, 0)
	-- hands on the bar Poser puts behind the neck (UpperTorso y 0.42 * Size.Y = 0.67 guard units,
	-- z +0.62 * Size.Z): fists just under the bar axis; the authored arms above stay the fallback for
	-- far rigs / rigs without arm geometry
	guardArm(rig, p, "R", 1.3, 0.62, 0.62, 1, -0.3, 0.3, -1)
	guardArm(rig, p, "L", -1.3, 0.62, 0.62, 1, -0.3, 0.3, -1)
	plant(rig, 0, 0.22, 0.35, -0.35, 0, 0)
	flexAct(rig, "Squat", 0.3 + 0.7 * sin(PI * clamp(d * 1.1, 0, 1)))
	flex(rig, "abs", 0.6)
	rig.exprHint = (h > 0.4) and "effort" or nil
	return p
end

-- dumbbells: alternating curls with supination, then shoulder presses and lateral raises, so the
-- biceps, forearms AND the delts get worked (RepCount buckets; remote viewers use the auto cycle)
POSE.curl = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1.2, 0.15)
	local rep = rig.curlCycle or 0
	local mode = floor(rep / 3) % 4
	local eff = num(rig.a.Effort, 0)
	if mode <= 1 then
		local right = rep % 2 == 0
		local S, E, Wr = right and "RS" or "LS", right and "RE" or "LE", right and "RW" or "LW"
		local side = right and 1 or -1
		-- elbow pinned at the side: just clear of the hip, wider with bulk (+Z right = outward)
		local tuck = 0.02 + 0.08 * bulkOf(rig)
		p[S] = A(0.1 + 0.28 * d * d, 0, right and tuck or -tuck)
		p[E] = A(lerp(0.15, 2.35, d), 0, 0)
		p[Wr] = A(-0.2 * d, side * -lerp(0, 0.85, d), 0)
		if eff > 0.7 then
			-- cheating the last reps: a hip swing gets the bell moving
			p.W = p.W * A(0.14 * (eff - 0.7) / 0.3 * sin(PI * d), 0, 0)
		end
		flex(rig, "biceps", 0.3 + 0.7 * d, side)
		flex(rig, "forearms", 0.5 + 0.4 * d, side)
		flex(rig, "frontDelt", 0.25 * d, side)
		flex(rig, "forearms", 0.4, -side)
	elseif mode == 2 then
		-- standing shoulder press: from the shoulders (forearms vertical) to straight overhead
		local ab = lerp(1.45, 2.85, d)
		p.RS = A(0, 0, ab) * A(0, -1.3 * (1 - d), 0)
		p.LS = A(0, 0, -ab) * A(0, 1.3 * (1 - d), 0)
		p.RE = A(lerp(1.6, 0.1, d), 0, 0)
		p.LE = A(lerp(1.6, 0.1, d), 0, 0)
		p.W = p.W * A(0.04, 0, 0)
		flex(rig, "frontDelt", 0.6 + 0.4 * d)
		flex(rig, "sideDelt", 0.5 + 0.5 * d)
		flex(rig, "triceps", 0.3 + 0.7 * d)
		flex(rig, "traps", 0.4 * d)
		flex(rig, "upperChest", 0.3)
	else
		-- lateral raise: soft elbows, lead with the elbows to shoulder height
		local ab = lerp(0.12, 1.5, d)
		p.RS = A(0.12, 0, ab)
		p.LS = A(0.12, 0, -ab)
		p.RE = A(0.28, 0, 0)
		p.LE = A(0.28, 0, 0)
		p.RW = A(0, 0, -0.1 * d)
		p.LW = A(0, 0, 0.1 * d)
		flex(rig, "sideDelt", 0.4 + 0.6 * d)
		flex(rig, "traps", 0.35 * d)
		flex(rig, "frontDelt", 0.3 * d)
	end
	rig.exprHint = d > 0.7 and eff > 0.5 and "effort" or nil
	return p
end

POSE.pullup = function(p, rig, t, d, w, model, dt)
	-- 0..15% of the rep: scapular depression (shoulders down, straight arms); then the pull with the
	-- chin over the bar, ankles crossed, a little pendulum swing at the bottom
	local scap = smooth(d / 0.15)
	local pull = clamp((d - 0.1) / 0.9, 0, 1)
	local s1 = PI - (PI - 0.5) * pull
	local swing = sin(t * 1.3 + rig.phase) * 0.05 * (1 - pull)
	p.Root = CF(0, 1.9 * pull + 0.12 * scap, 0) * A(swing - 0.05, 0, 0)
	p.W = A(0.1 * pull, 0, 0)
	p.Neck = A(0.15 * pull, 0, 0)
	p.RS = A(s1 - 0.08 * scap, 0, -0.12 - 0.1 * scap)
	p.RE = A(2.6 * pull, 0, 0)
	p.LS = A(s1 - 0.08 * scap, 0, 0.12 + 0.1 * scap)
	p.LE = A(2.6 * pull, 0, 0)
	p.RH = A(0.2, 0, -0.1)
	p.RK = A(-1.15, 0, 0)
	p.RA = A(-0.3, 0, 0)
	p.LH = A(0.32, 0, 0.12)
	p.LK = A(-1.0, 0, 0)
	p.LA = A(-0.3, 0, 0)
	flexAct(rig, "PullUps", 0.35 + 0.65 * pull)
	flex(rig, "lats", 0.5 + 0.5 * scap)
	rig.exprHint = pull > 0.5 and "effort" or nil
	return p
end

-- half the distance between the hand centres holding the medicine ball (Poser: ball diameter 1.1,
-- welded 0.55 along the right hand's -X): with the palms turned in the fists sit on the ball surface
local MEDBALL_HALF = 0.4
local PALM_KEYS = { { "RS", "RE", "RW" }, { "LS", "LE", "LW" } }
-- run both hands' X axes along the torso's X (palms facing each other across the ball), fingers
-- continuing the forearm: the ball Poser hangs off the right palm then lands against the left one
local function palmsIn(p)
	for _, k in ipairs(PALM_KEYS) do
		local fore = (p[k[1]] * p[k[2]]).Rotation
		local f = fore:VectorToWorldSpace(V3(0, -1, 0))
		p[k[3]] = fore:Inverse() * A(atan2(-f.Z, -f.Y), 0, 0)
	end
end

-- medicine ball: SLAM sets (reach overhead on the toes, hinge and drive it into the floor) and
-- seated RUSSIAN TWISTS (TwistSide = -1 / +1 from Activities); remote viewers alternate sets
POSE.medball = function(p, rig, t, d, w, model, dt)
	local tw = rig.a.TwistSide
	local twist = nil
	if type(tw) == "number" then
		twist = clamp(tw, -1, 1)
	elseif rig.a.PoseDrive == nil then
		local cyc = t * 0.55 * w + rig.phase
		if floor(cyc / 6) % 2 == 1 then
			twist = sin(cyc * PI)
		end
	end
	if twist then
		rig.twistX = (rig.twistX or 0) + (twist - (rig.twistX or 0)) * (1 - exp(-dt * 7))
		local x = rig.twistX
		local g = rig.geo
		local fh = g.ok and g.floorH or 3
		-- sitting on the floor, leaning back in a V, the ball goes from hip to hip
		p.Root = CF(0, -(fh - 0.42), 0.3) * A(0.55, 0, 0)
		p.W = A(-0.18, 0.75 * x, 0.08 * x)
		p.Neck = A(-0.2, -0.3 * x, 0)
		p.RS = A(1.05, 0, -0.38)
		p.RE = A(1.25, 0, 0)
		p.LS = A(1.05, 0, 0.38)
		p.LE = A(1.25, 0, 0)
		-- both hands on the ball (Poser's medball sits against the right palm), in front of the
		-- chest; the torso turn carries it from hip to hip
		local okR = guardArm(rig, p, "R", MEDBALL_HALF, 0.05, -0.95, 1, 0.3, 0.8, -0.6)
		local okL = guardArm(rig, p, "L", -MEDBALL_HALF, 0.05, -0.95, 1, 0.3, 0.8, -0.6)
		if okR and okL then
			palmsIn(p)
		end
		p.LH = A(1.55, 0, -0.08)
		p.LK = A(-1.4, 0, 0)
		p.LA = A(0.3, 0, 0)
		p.RH = A(1.55, 0, 0.08)
		p.RK = A(-1.4, 0, 0)
		p.RA = A(0.3, 0, 0)
		flexAct(rig, "MedBall", 0.5 + 0.5 * abs(x))
		flex(rig, "obliques", 0.6 + 0.4 * max(0, x), 1)
		flex(rig, "obliques", 0.6 + 0.4 * max(0, -x), -1)
		flex(rig, "lowerAbs", 0.9)
		rig.exprHint = "effort"
		return p
	end
	rig.twistX = 0
	local up = clamp(d, 0, 1)
	local h = 1 - up
	local hinge = 0.85 * h
	p.Root = CF(0, -0.85 * h ^ 1.3, 0.3 * h) * A(-hinge, 0, 0)
	p.W = A(-0.15 * h + 0.1 * up, 0, 0)
	p.Neck = A(0.3 * h, 0, 0)
	p.RS = A(lerp(hinge + 0.55, 2.95, up), 0, -0.3)
	p.LS = A(lerp(hinge + 0.55, 2.95, up), 0, 0.3)
	p.RE = A(lerp(0.3, 0.35, up), 0, 0)
	p.LE = A(lerp(0.3, 0.35, up), 0, 0)
	-- the ball travels overhead -> into the floor in front of the feet (UpperTorso space, which is
	-- hinged forward at the bottom), bulging forward on the way down; hands one ball-width apart
	local by = lerp(-0.75, 2.5, up)
	local bz = lerp(-1.05, -0.3, up) - 0.45 * sin(PI * up)
	local okR = guardArm(rig, p, "R", MEDBALL_HALF, by, bz, 1, -0.1, 1, 0)
	local okL = guardArm(rig, p, "L", -MEDBALL_HALF, by, bz, 1, -0.1, 1, 0)
	if okR and okL then
		palmsIn(p)
	end
	local toes = up * up * up * 0.35
	plant(rig, 0, 0.16, 0.2, -0.2, toes, toes)
	flexAct(rig, "MedBall", 0.4 + 0.6 * h)
	flex(rig, "lats", 0.7 * h)
	flex(rig, "serratus", 0.6 * up)
	-- the slam lands: everything shakes
	if up < 0.06 and rig.slamArmed then
		rig.slamArmed = false
		if R.FX.BodyFX then
			R.FX.BodyFX.Jiggle(model, "all", 0.6)
		end
		if R.FX.HairFX then
			R.FX.HairFX.Impulse(model, 0, -0.5, 0.6)
		end
	elseif up > 0.6 then
		rig.slamArmed = true
	end
	rig.exprHint = h > 0.5 and "effort" or nil
	return p
end

------------------------------------------------------------------------
-- Flex poses (Pose = flex_*; Main's Flex handler, Hub / result screen FLEX buttons)
------------------------------------------------------------------------
local FLEX_MUSCLES = {
	flex_biceps = { biceps = 1, forearms = 0.8, frontDelt = 0.6, sideDelt = 0.8, lats = 0.6, abs = 0.4, quads = 0.5, calves = 0.4 },
	flex_lat = { lats = 1, upperBack = 0.7, serratus = 0.7, rearDelt = 0.4, traps = 0.3, abs = 0.35, quads = 0.4, calves = 0.3 },
	flex_chest = { pecs = 1, upperChest = 1, frontDelt = 0.8, biceps = 0.7, triceps = 0.4, abs = 0.3, calves = 0.7, quads = 0.5 },
	flex_most = { traps = 1, pecs = 0.9, upperChest = 0.8, frontDelt = 0.8, sideDelt = 0.7, biceps = 0.6, forearms = 0.9,
		neckSCM = 0.9, abs = 0.5, quads = 0.6 },
	flex_abs = { abs = 1, lowerAbs = 1, obliques = 0.9, serratus = 0.8, quads = 1, calves = 0.5, biceps = 0.3 },
}

local function flexPose(kind)
	return function(p, rig, t, d, w, model, dt)
		local e = smooth((t - rig.poseT) / 0.55) -- hit the pose
		local sq = 0.82 + 0.18 * (0.5 + 0.5 * sin(t * 2.4)) -- squeeze, release, squeeze
		local trem = sin(t * 83) * 0.012 * e -- straining muscles shake a little
		stand(p, rig, t, dt, 0.6, 0)
		local base = rig.kp
		for _, k in ipairs(KEYS) do
			base[k] = p[k]
		end
		if kind == "flex_biceps" then
			p.LS = A(0, 0, -1.45) * A(0, 1.3, 0)
			p.RS = A(0, 0, 1.45) * A(0, -1.3, 0)
			p.LE = A(2.25 + trem, 0, 0)
			p.RE = A(2.25 - trem, 0, 0)
			p.LW = A(-0.55, 0, 0)
			p.RW = A(-0.55, 0, 0)
			p.W = A(0.08, 0, 0)
			p.Neck = A(0.1, 0.35 * sin(t * 0.4), 0)
			plant(rig, 0.4, 0.12, 0.3, -0.3, 0.25, 0)
		elseif kind == "flex_lat" then
			-- front lat spread: fists at the waist, elbows driven forward, chest up
			p.LS = A(0.25, 0, -0.7) * A(0, -1.0, 0)
			p.RS = A(0.25, 0, 0.7) * A(0, 1.0, 0)
			p.LE = A(1.95, 0, 0)
			p.RE = A(1.95, 0, 0)
			p.W = A(0.1, 0, 0)
			p.Neck = A(0.12, 0, 0)
			p.Root = CF(0, 0.02, 0)
			plant(rig, 0.1, 0.18, 0.35, -0.35, 0, 0)
		elseif kind == "flex_chest" then
			-- side chest: turned to the side, front arm bent across, the other hand grips its wrist
			p.Root = CF(0, -0.05, 0) * A(0, -0.55, 0)
			p.W = A(0.06, -0.15, 0)
			p.Neck = A(0.05, 0.75, 0)
			p.RS = A(0.6, 0.3, 0.1)
			p.RE = A(1.7, 0, 0)
			p.LS = A(0.65, -0.55, 0.35)
			p.LE = A(2.0, 0, 0)
			plant(rig, 0.25, 0.05, -0.2, -0.75, 0, 0.45)
			rig.foot.R.knee = 0.3
		elseif kind == "flex_most" then
			-- most muscular (crab): hunched forward, fists together at the waist, traps up
			p.Root = CF(0, -0.14, 0)
			p.W = A(-0.24, 0, 0)
			p.Neck = A(-0.08, 0, 0)
			p.LS = A(0.7, 0, 0.35) * A(0, -0.45, 0)
			p.RS = A(0.7, 0, -0.35) * A(0, 0.45, 0)
			p.LE = A(1.7 + trem, 0, 0)
			p.RE = A(1.7 - trem, 0, 0)
			plant(rig, 0.35, 0.16, 0.25, -0.25, 0, 0)
		else -- flex_abs: hands behind the head, crunch the abs, one thigh forward
			p.LS = A(2.55, 0, -0.55)
			p.RS = A(2.55, 0, 0.55)
			p.LE = A(2.35, 0, 0)
			p.RE = A(2.35, 0, 0)
			p.W = A(-0.15, 0, 0)
			p.Neck = A(-0.12, 0, 0)
			plant(rig, 0.65, 0.05, 0.2, -0.25, 0, 0)
		end
		for _, k in ipairs(KEYS) do
			p[k] = base[k]:Lerp(p[k], e)
		end
		for id, v in pairs(FLEX_MUSCLES[kind]) do
			flex(rig, id, v * e * sq)
		end
		rig.exprHint = e > 0.5 and "effort" or nil
		return p
	end
end
for kind in pairs(FLEX_MUSCLES) do
	POSE[kind] = flexPose(kind)
end

------------------------------------------------------------------------
-- Cardio & conditioning
------------------------------------------------------------------------
POSE.run = function(p, rig, t, d, w, model, dt)
	rig.runPhase = (rig.runPhase or 0) + dt * 10 * w
	local x = rig.runPhase
	local s, c = sin(x), cos(x)
	p.Root = CF(0, 0.12 * abs(c) - 0.06, 0) * A(-0.14, 0.1 * s, 0)
	p.W = A(-0.02, -0.16 * s, 0)
	p.Neck = A(0.12, 0.06 * s, 0)
	p.RS = A(-0.65 * s, 0, -0.1)
	p.RE = A(1.45 + 0.2 * max(0, s), 0, 0)
	p.LS = A(0.65 * s, 0, 0.1)
	p.LE = A(1.45 + 0.2 * max(0, -s), 0, 0)
	p.RH = A(0.14 + 0.8 * s, 0, 0)
	p.RK = A(-0.25 - 1.1 * max(0, -c), 0, 0)
	p.RA = A(0.15 * max(0, s) - 0.25 * max(0, -s), 0, 0)
	p.LH = A(0.14 - 0.8 * s, 0, 0)
	p.LK = A(-0.25 - 1.1 * max(0, c), 0, 0)
	p.LA = A(0.15 * max(0, -s) - 0.25 * max(0, s), 0, 0)
	flex(rig, "calves", 0.5 + 0.5 * abs(c))
	flex(rig, "quads", 0.4)
	rig.breath = 0.6
	return p
end

-- walking / running members (Loop walk / run): the real gait from the root's velocity (AnimLoco)
POSE.walk = function(p, rig, t, d, w, model, dt)
	return POSE.idle(p, rig, t, d, w, model, dt)
end

POSE.bike = function(p, rig, t, d, w, model, dt)
	local x = t * 7 * w
	p.W = A(-0.1, 0, 0)
	p.Neck = A(0.25, 0, 0)
	p.RS = A(1.25, 0, -0.1)
	p.RE = A(0.3, 0, 0)
	p.LS = A(1.25, 0, 0.1)
	p.LE = A(0.3, 0, 0)
	seated(p, 0.45)
	p.RH = A(PI / 2 + 0.1 + 0.35 * sin(x), 0, 0.05)
	p.LH = A(PI / 2 + 0.1 - 0.35 * sin(x), 0, -0.05)
	p.RK = A(-1.3 - 0.45 * cos(x), 0, 0)
	p.LK = A(-1.3 + 0.45 * cos(x), 0, 0)
	p.RA = A(0.2 * cos(x), 0, 0)
	p.LA = A(-0.2 * cos(x), 0, 0)
	flex(rig, "quads", 0.5 + 0.4 * max(0, sin(x)), 1)
	flex(rig, "quads", 0.5 + 0.4 * max(0, -sin(x)), -1)
	rig.breath = 0.5
	return p
end

POSE.row = function(p, rig, t, d, w, model, dt)
	-- legs drive first, then the back swings, then the arms pull (and the reverse on the recovery)
	local legsD = smooth(d / 0.55)
	local backD = smooth((d - 0.3) / 0.45)
	local armsD = smooth((d - 0.55) / 0.45)
	p.RS = A(lerp(1.5, 0.55, armsD), 0, -0.1)
	p.RE = A(lerp(0.05, 1.9, armsD), 0, 0)
	p.LS = A(lerp(1.5, 0.55, armsD), 0, 0.1)
	p.LE = A(lerp(0.05, 1.9, armsD), 0, 0)
	local lean = lerp(0.35, -0.3, backD)
	p.Root = A(-lean, 0, 0)
	p.RH = A(lerp(2.25, 1.5, legsD) + lean, 0, 0.06)
	p.LH = A(lerp(2.25, 1.5, legsD) + lean, 0, -0.06)
	p.RK = A(lerp(-2.2, -0.1, legsD), 0, 0)
	p.LK = A(lerp(-2.2, -0.1, legsD), 0, 0)
	flexAct(rig, "Rower", 0.3 + 0.7 * sin(PI * d))
	rig.breath = 0.5
	return p
end

POSE.rope = function(p, rig, t, d, w, model, dt)
	local x = rig.ropePhase or 0
	local hop = max(0, cos(x)) ^ 2 -- one hop per rope turn, peaking as the rope passes the feet
	p.W = A(0.02, 0, 0)
	p.Neck = A(-0.05, 0, 0)
	p.RS = A(0.25, 0, 0.32)
	p.RE = A(1.0, 0, 0)
	p.LS = A(0.25, 0, -0.32)
	p.LE = A(1.0, 0, 0)
	p.RW = A(0.4 * sin(x), 0, 0)
	p.LW = A(0.4 * sin(x), 0, 0)
	local land = 0.12 * (1 - hop)
	legAngles(p, land, 0, rig.geo.ok and rig.geo.legLen or 2.3)
	-- on the balls of the feet the whole time
	p.LA = p.LA * A(-0.3 * hop, 0, 0)
	p.RA = p.RA * A(-0.3 * hop, 0, 0)
	p.Root = CF(0, 0.32 * hop * (rig.ropeHop or 1) - land, 0)
	if rig.ropeFoot then
		local L = rig.ropeFoot == "L"
		p[L and "RK" or "LK"] = A(-0.9 * hop, 0, 0)
	end
	flex(rig, "calves", 0.4 + 0.6 * (1 - hop))
	flex(rig, "forearms", 0.4)
	rig.breath = 0.5
	return p
end

POSE.ladder = function(p, rig, t, d, w, model, dt)
	local x = t * 15 * w
	p.W = A(-0.1, 0, 0)
	p.Neck = A(0.15, 0, 0)
	p.RS = A(-0.5 * sin(x), 0, -0.1)
	p.RE = A(1.5, 0, 0)
	p.LS = A(0.5 * sin(x), 0, 0.1)
	p.LE = A(1.5, 0, 0)
	legs(p, 0.25, 0, rig)
	p.RH = p.RH * A(0.55 * max(0, sin(x)), 0, 0)
	p.RK = p.RK * A(-0.9 * max(0, sin(x)), 0, 0)
	p.LH = p.LH * A(0.55 * max(0, -sin(x)), 0, 0)
	p.LK = p.LK * A(-0.9 * max(0, -sin(x)), 0, 0)
	p.RA = p.RA * A(-0.3, 0, 0)
	p.LA = p.LA * A(-0.3, 0, 0)
	flex(rig, "calves", 0.7)
	rig.breath = 0.6
	return p
end

------------------------------------------------------------------------
-- Recovery & services
------------------------------------------------------------------------
POSE.longsit = function(p, rig, t)
	local shiver = sin(t * 40) * 0.015
	p.Root = A(0, 0, shiver)
	p.W = A(-0.1 + shiver, 0, 0)
	p.Neck = A(0.1, 0, 0)
	p.RS = A(0.25, 0, 0.55)
	p.RE = A(0.5, 0, 0)
	p.LS = A(0.25, 0, -0.55)
	p.LE = A(0.5, 0, 0)
	p.RH = A(PI / 2, 0, 0.08)
	p.LH = A(PI / 2, 0, -0.08)
	p.RK = A(-0.12, 0, 0)
	p.LK = A(-0.12, 0, 0)
	rig.exprHint = "pain"
	return p
end

POSE.sit = function(p, rig, t)
	local b = sin(t * 1.6) * 0.03
	p.W = A(-0.15 + b, 0, 0)
	p.Neck = A(0.35, 0, 0)
	p.RS = A(0.75, 0, 0.05)
	p.RE = A(0.55, 0, 0)
	p.LS = A(0.75, 0, -0.05)
	p.LE = A(0.55, 0, 0)
	return seated(p, 0)
end

POSE.sitwatch = function(p, rig, t, d, w, model, dt)
	POSE.sit(p, rig, t)
	p.Neck = A(0.05, 0, 0)
	p.W = A(-0.05, 0, 0)
	p.RS = A(0.9, 0, -0.35)
	p.RE = A(1.4, 0, 0)
	p.LS = A(0.9, 0, 0.35)
	p.LE = A(1.4, 0, 0)
	rig.lookW = 1
	return p
end

POSE.lie = function(p, rig, t)
	local b = sin(t * 1.4) * 0.02
	p.Root = A(-PI / 2, 0, 0)
	p.W = A(b, 0, 0)
	p.Neck = A(0.1, 0.6, 0)
	p.RS = A(0.05, 0, 0.12)
	p.RE = A(0.1, 0, 0)
	p.LS = A(0.05, 0, -0.12)
	p.LE = A(0.1, 0, 0)
	return p
end

POSE.lieup = function(p, rig, t)
	local b = sin(t * 1.2) * 0.02
	p.Root = A(PI / 2, 0, 0)
	p.W = A(b, 0, 0)
	p.Neck = A(-0.1, 0, 0)
	p.RS = A(0.05, 0, 0.1)
	p.RE = A(0.1, 0, 0)
	p.LS = A(0.05, 0, -0.1)
	p.LE = A(0.1, 0, 0)
	return p
end

POSE.stretch = function(p, rig, t, d, w, model, dt)
	local phase = floor((t + rig.phase) / 4) % 3
	local k = smooth(min(1, ((t + rig.phase) % 4) / 0.8))
	stand(p, rig, t, dt, 0.5, 0)
	if phase == 0 then
		-- arm across the chest
		p.RS = A(1.45, 0, -1.0):Lerp(p.RS, 1 - k)
		p.RE = A(0.1, 0, 0)
		p.LS = A(1.2, 0, 0.6):Lerp(p.LS, 1 - k)
		p.LE = A(1.6, 0, 0)
	elseif phase == 1 then
		-- overhead side bend
		p.RS = A(0, 0, 2.9):Lerp(p.RS, 1 - k)
		p.LS = A(0, 0, -2.9):Lerp(p.LS, 1 - k)
		p.RE = A(0.3, 0, 0)
		p.LE = A(0.3, 0, 0)
		p.W = A(0, 0, 0.35 * k)
	else
		-- quad stretch: the right foot pulled to the glutes, balancing on the left
		rig.foot.R.free = true
		rig.foot.R.lift = 0.9 * k
		rig.foot.R.z = 0.75 * k
		p.RS = A(-0.6 * k, 0, 0.1)
		p.RE = A(0.4, 0, 0)
		p.LS = A(0.2, 0, -0.5)
		p.Root = CF(-0.08 * k, 0, 0) * p.Root
	end
	return p
end

POSE.idle = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 1)
	-- walking / running: the arms swing with the legs (AnimLoco's gait phase)
	local mv = rig.loco.gaitW
	if mv > 0.01 then
		L.armSwing(p, rig, mv)
		-- a little forward lean when running, the gaze level
		local run = rig.loco.run * mv
		p.W = p.W * A(-0.06 * run, 0, 0)
		p.Neck = p.Neck * A(0.05 * run, 0, 0)
	end
	rig.lookW = 0.8 * (1 - 0.5 * mv)
	return p
end

-- the Creator's preview: a proud, relaxed boxer
POSE.preview = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 0.6)
	p.W = p.W * A(0.05, 0, 0)
	p.Neck = p.Neck * A(0.04, 0, 0)
	p.RS = p.RS * A(0, 0, 0.04)
	p.LS = p.LS * A(0, 0, -0.04)
	p.RE = A(0.35, 0, 0)
	p.LE = A(0.35, 0, 0)
	return p
end

POSE.mittidle = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 0.5)
	p.RS = A(0.45, 0, -0.1)
	p.RE = A(1.3, 0, 0)
	p.LS = A(0.45, 0, 0.1)
	p.LE = A(1.3, 0, 0)
	rig.lookW = 1
	return p
end

-- the mitt coach holds the pads up; MittCall (local) flashes the called target; the pads give
-- when a punch lands on them (the watched trainee's act)
POSE.mitts = function(p, rig, t, d, w, model, dt)
	p.RS = A(1.35, 0, -0.25)
	p.RE = A(1.65, 0, 0)
	p.LS = A(1.35, 0, 0.25)
	p.LE = A(1.65, 0, 0)
	p.W = A(-0.05, 0, 0)
	p.Neck = A(-0.05, 0, 0)
	p.Root = CF(0, -0.2 - sin(t * 6) * 0.04, 0)
	plant(rig, 0.6, 0.1, 0.1, -0.5, 0.05, 0.1)
	local call = rig.a.MittCall
	local callT = rig.a.MittCallT
	if call and type(callT) == "number" then
		local el = os.clock() - callT
		if el < 0.45 then
			local s = sin(PI * clamp(el / 0.45, 0, 1))
			if call == "L" then
				p.LS = p.LS:Lerp(A(1.55, 0, -0.1), s)
				p.LE = p.LE:Lerp(A(0.9, 0, 0), s)
			elseif call == "R" then
				p.RS = p.RS:Lerp(A(1.55, 0, 0.1), s)
				p.RE = p.RE:Lerp(A(0.9, 0, 0), s)
			elseif call == "D" then
				-- swing a pad over the boxer's head (slip / roll drills)
				p.RS = p.RS:Lerp(A(1.6, 0, 0.9), s)
				p.RE = p.RE:Lerp(A(0.4, 0, 0), s)
			end
		end
	end
	-- catching: the pad gives on impact (the trainee's punch arrives at the end of its windup)
	local wr = rig.watch and rigs[rig.watch]
	local act = wr and (wr.bodyAct or wr.act or wr.autoAct)
	if act and PUNCHES[act.kind] then
		-- (the trainee's act runs on the trainee's own clock: every rig keeps its own)
		local el = wr.clock - act.start - act.windup
		if el > -0.02 and el < 0.22 then
			local r = K.attackDecay(el + 0.02, 0.04, 0.24)
			-- same pad mapping as MittCall: a left-hand punch lands on the pad raised for "L"
			local S, E = act.hand == "L" and "LS" or "RS", act.hand == "L" and "LE" or "RE"
			p[S] = p[S] * A(-0.22 * r, 0, 0)
			p[E] = p[E] * A(0.3 * r, 0, 0)
			p.W = p.W * A(0, (act.hand == "L" and -0.08 or 0.08) * r, 0)
		end
	end
	rig.lookW = 1
	flex(rig, "forearms", 0.5)
	flex(rig, "frontDelt", 0.4)
	return p
end

POSE.barber = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 0.3)
	p.RS = A(1.35 + sin(t * 3) * 0.08, 0, -0.35 + sin(t * 2) * 0.1)
	p.RE = A(1.2, 0, 0)
	p.LS = A(1.1, 0, 0.25)
	p.LE = A(1.1, 0, 0)
	p.W = A(-0.2, 0.15, 0)
	p.Neck = A(0.25, 0, 0)
	return p
end

POSE.massage = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 0.2)
	local k = sin(t * 3)
	p.W = A(-0.45, 0, 0)
	p.Neck = A(0.3, 0, 0)
	p.RS = A(1.15 + 0.12 * k, 0, -0.15)
	p.RE = A(0.35, 0, 0)
	p.LS = A(1.15 - 0.12 * k, 0, 0.15)
	p.LE = A(0.35, 0, 0)
	p.Root = CF(0, -0.15, 0) * p.Root
	return p
end

------------------------------------------------------------------------
-- People who watch: coaches, ringside fans, cornermen, the referee
------------------------------------------------------------------------
local function startGesture(rig, kind, t, dur)
	rig.gesture = { kind = kind, start = t, dur = dur or 1.2 }
	if kind == "shout" and R.FX.FaceFX then
		R.FX.FaceFX.Shout(rig.model, (dur or 1.2) * 0.85)
	end
end

local function gestureOverlay(p, rig, t)
	local g = rig.gesture
	if not g then
		return
	end
	rig.gestureDrawnT = t
	local el = t - g.start
	if el > g.dur then
		rig.gesture = nil
		return
	end
	local e = K.attackDecay(el, 0.2, g.dur)
	local kind = g.kind
	if kind == "point" then
		p.RS = p.RS:Lerp(A(1.5, -0.2, -0.15), e) * A(0.08 * sin(el * 14) * e, 0, 0)
		p.RE = p.RE:Lerp(A(0.15, 0, 0), e)
	elseif kind == "clap" then
		local c = abs(sin(el * 9))
		p.LS = p.LS:Lerp(A(1.05, 0, 0.6 - 0.25 * c), e)
		p.RS = p.RS:Lerp(A(1.05, 0, -0.6 + 0.25 * c), e)
		p.LE = p.LE:Lerp(A(1.2, 0, 0), e)
		p.RE = p.RE:Lerp(A(1.2, 0, 0), e)
	elseif kind == "shout" then
		-- a cupped hand by the mouth, leaning in
		p.RS = p.RS:Lerp(A(1.95, 0.6, -0.35), e)
		p.RE = p.RE:Lerp(A(2.3, 0, 0), e)
		p.W = p.W * A(-0.1 * e, 0, 0)
		p.Neck = p.Neck * A(0.1 * e, 0, 0)
		rig.exprHint = "shout"
	elseif kind == "nod" then
		p.Neck = p.Neck * A(0.14 * sin(el * 9) * e, 0, 0)
	elseif kind == "pound" then
		-- a fist bangs on the apron
		p.RS = p.RS * A(-0.35 * abs(sin(el * 10)) * e, 0, 0)
		rig.exprHint = "anger"
	elseif kind == "mime" then
		-- miming the jab he wants to see
		local j = max(0, sin(el * 8))
		p.LS = p.LS:Lerp(A(1.45, 0, 0.12), e * j)
		p.LE = p.LE:Lerp(A(0.2, 0, 0), e * j)
	end
end

-- react to what the watched athlete does, and gesture now and then anyway
local function watchReact(rig, t, kinds)
	local wr = rig.watch and rigs[rig.watch]
	if wr then
		local act = wr.bodyAct or wr.act or wr.autoAct
		if act and act ~= rig.watchAct then
			rig.watchAct = act
			local hit = act.kind == "hit" or act.kind == "hitbody"
			if not rig.gesture and rig.rng:NextNumber() < (hit and 0.6 or 0.22) then
				startGesture(rig, hit and "shout" or kinds[rig.rng:NextInteger(1, #kinds)], t, hit and 1.1 or 1.3)
				rig.nextGesture = t + rig.rng:NextNumber(3, 6)
			end
		end
	end
	if t >= rig.nextGesture and not rig.gesture then
		rig.nextGesture = t + rig.rng:NextNumber(4, 9)
		startGesture(rig, kinds[rig.rng:NextInteger(1, #kinds)], t, rig.rng:NextNumber(0.9, 1.6))
	end
end

local COACH_GESTURES = { "point", "clap", "shout", "nod", "nod" }
local RINGSIDE_GESTURES = { "shout", "pound", "clap", "nod" }
local CORNER_GESTURES = { "shout", "mime", "point", "clap" }

POSE.coachwatch = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 0.6)
	-- arms crossed, weight on one leg
	p.LS = A(0.5, -0.65, 0.3)
	p.LE = A(1.85, 0, 0)
	p.RS = A(0.55, 0.65, -0.3)
	p.RE = A(1.8, 0, 0)
	rig.lookW = 1
	watchReact(rig, t, COACH_GESTURES)
	gestureOverlay(p, rig, t)
	return p
end

POSE.ringside = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 0.3)
	-- forearms on the top rope, leaning in
	p.Root = CF(0, -0.05, -0.08) * A(-0.2, 0, 0)
	p.W = A(-0.12, 0, 0)
	p.LS = A(1.3, -0.25, 0.2)
	p.LE = A(1.55, 0, 0)
	p.RS = A(1.3, 0.25, -0.2)
	p.RE = A(1.55, 0, 0)
	rig.lookW = 1
	watchReact(rig, t, RINGSIDE_GESTURES)
	gestureOverlay(p, rig, t)
	return p
end

POSE.cornerman = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 0.4)
	-- hands on the ropes, ready to climb in; crouches to talk to his fighter
	local crouch = 0.12 + 0.1 * max(0, sin(t * 0.35 + rig.phase))
	p.Root = CF(0, -crouch, 0) * A(-0.12, 0, 0)
	p.W = A(-0.1, 0, 0)
	p.LS = A(1.35, 0, -0.45)
	p.LE = A(0.6, 0, 0)
	p.RS = A(1.35, 0, 0.45)
	p.RE = A(0.6, 0, 0)
	rig.lookW = 1
	watchReact(rig, t, CORNER_GESTURES)
	gestureOverlay(p, rig, t)
	return p
end

POSE.referee = function(p, rig, t, d, w, model, dt)
	stand(p, rig, t, dt, 1, 0.2)
	-- athletic crouch, weight forward, hands ready to step in and separate
	p.Root = CF(0, -0.16, 0) * A(-0.06, 0, 0)
	p.W = A(-0.1, 0, 0)
	p.LS = A(0.75, 0, 0.25)
	p.LE = A(1.35, 0, 0)
	p.RS = A(0.75, 0, -0.25)
	p.RE = A(1.35, 0, 0)
	plant(rig, 0.35, 0.18, 0.2, -0.25, 0.05, 0.05)
	rig.stepDist = 0.35
	rig.lookW = 1
	L.gait(rig, "shuffle")
	return p
end

------------------------------------------------------------------------
-- Gym members (and other players' training, re-synthesized locally) throw real combinations;
-- sparring partners trade: a punch is blocked, slipped or lands on the other one
------------------------------------------------------------------------
local COMBOS = {
	{ "jab" }, { "jab", "jab" }, { "jab", "cross" }, { "jab", "jab", "cross" }, { "jab", "cross", "leadhook" },
	{ "cross", "leadhook", "cross" }, { "jab", "uppercut", "leadhook" }, { "leadhook", "rearhook" },
	{ "jab", "cross", "leadhook", "cross" }, { "uppercut", "uppercut" }, { "jab", "cross", "uppercut" },
}
local function windupOf(ptype)
	local P = Config.Punches and Config.Punches[ptype]
	return P and P.windup or 0.22
end

local function scheduleReaction(rig, act, t)
	local partner = rig.partner
	if not (partner and partner.model.Parent) then
		return
	end
	local r = partner.rng:NextNumber()
	-- "at" is read against the partner's own clock (runPending): every rig keeps its own
	t = partner.clock
	local hook = act.kind == "leadhook" or act.kind == "rearhook"
	local react
	if r < 0.45 then
		react = { kind = "blockhit", at = t + act.windup }
	elseif r < 0.63 then
		-- slips straights, rolls under hooks: starts before the punch arrives
		react = { kind = hook and "roll" or "slip", at = t + act.windup * 0.45, dir = partner.rng:NextNumber() < 0.5 and "L" or "R" }
	elseif r < 0.7 and act.kind == "jab" then
		react = { kind = "parry", at = t + act.windup * 0.5, dir = "R" }
	else
		react = { kind = act.zone == "body" and "hitbody" or "hit", at = t + act.windup, ptype = act.kind,
			sev = partner.rng:NextNumber(0.2, 0.55), side = act.hand == "L" and "R" or "L" }
	end
	partner.pending = react
end

local function runPending(rig, t)
	local r = rig.pending
	if not r or t < r.at then
		return
	end
	rig.pending = nil
	local k = r.kind
	if k == "blockhit" then
		Fight.react(rig, "blockhit", nil, nil, nil, t)
		rig.autoAct = { kind = "blockhit", start = t, dur = 0.4 }
	elseif k == "hit" or k == "hitbody" then
		Fight.react(rig, k, r.ptype, k == "hitbody" and r.side or "head", r.sev, t)
		rig.autoAct = { kind = k, start = t, dur = 0.5, sev = r.sev, f3 = r.side }
	else
		rig.autoAct = { kind = k, start = t, dur = k == "roll" and 0.55 or (k == "parry" and 0.3 or 0.42), f2 = r.dir }
	end
end

local function startAuto(rig, kind, hand, zone, windup, power, t)
	local act = { kind = kind, start = t, hand = hand, zone = zone, windup = windup, power = power,
		dur = windup * 2.05 + 0.045, f2 = hand, f3 = zone }
	Fight.startPunch(rig, act, t)
	if rig.publish then
		-- client-local: GymVisuals swings the bag next to this athlete after the windup
		rig.autoId += 1
		rig.model:SetAttribute("AutoAct", string.format("%s|%s|%s|%.2f|%.2f", kind, hand, zone, windup, power))
		rig.model:SetAttribute("AutoActId", rig.autoId)
	end
	if rig.partner then
		scheduleReaction(rig, act, t)
	end
end

local MOVES = { "slip", "roll", "step", "pivot" }
local DIRS = { "F", "B", "L", "R" }

local function ambientAct(rig, loop, t)
	if t < rig.nextAuto then
		return
	end
	local cur = rig.bodyAct or rig.autoAct
	if cur and t - cur.start < (cur.windup or 0) + 0.05 then
		return
	end
	local r = rig.rng
	if rig.combo then
		rig.comboI += 1
		local ptype = rig.combo[rig.comboI]
		if ptype then
			local hand = Fight.PUNCH_HAND[ptype] or "R"
			if ptype == "uppercut" then
				hand = rig.comboI % 2 == 0 and "L" or "R"
			end
			local w = windupOf(ptype) * r:NextNumber(0.9, 1.15)
			startAuto(rig, ptype, hand, r:NextNumber() < 0.2 and "body" or "head", w, r:NextNumber(0.5, 1), t)
			rig.nextAuto = t + w + r:NextNumber(0.06, 0.16)
			return
		end
		rig.combo = nil
		-- breathe between combinations
		rig.nextAuto = t + (loop == "heavybag" and r:NextNumber(0.5, 1.4) or r:NextNumber(0.7, 1.8))
		return
	end
	local roll = r:NextNumber()
	if loop == "spar" and roll < 0.18 then
		rig.autoAct = { kind = r:NextNumber() < 0.5 and "slip" or "roll", f2 = r:NextNumber() < 0.5 and "L" or "R", start = t, dur = 0.5 }
		rig.nextAuto = t + 0.6
	elseif loop == "shadow" and roll < 0.35 then
		local m = MOVES[r:NextInteger(1, #MOVES)]
		rig.autoAct = { kind = m, f2 = m == "step" and DIRS[r:NextInteger(1, 4)] or (r:NextNumber() < 0.5 and "L" or "R"),
			start = t, dur = m == "roll" and 0.55 or (m == "step" and 0.36 or 0.42) }
		rig.nextAuto = t + 0.55
	else
		rig.combo = COMBOS[r:NextInteger(1, #COMBOS)]
		rig.comboI = 0
		rig.nextAuto = t
	end
end

-- sparring partner (Ambient SparPartner attribute, else the nearest other sparring member)
local function findPartner(rig, t)
	if t < rig.nextPartner then
		return
	end
	rig.nextPartner = t + 2
	if rig.partner and rig.partner.model.Parent and rigs[rig.partner.model] then
		return
	end
	rig.partner = nil
	local want = rig.a.SparPartner
	local pos = rig.root.Position
	local best, bd = nil, 9
	for m, r in pairs(rigs) do
		if r ~= rig and r.isAmbient and r.root then
			if type(want) == "string" and m.Name == want then
				best = r
				break
			end
			if r.a.Loop == "spar" then
				local d = (r.root.Position - pos).Magnitude
				if d < bd then
					best, bd = r, d
				end
			end
		end
	end
	rig.partner = best
end

------------------------------------------------------------------------
-- Jump-rope visual (beam between the hands that swings around the body)
------------------------------------------------------------------------
local function ropeVisual(rig, model, on, phase)
	if not on then
		if rig.rope then
			rig.rope.beam.Enabled = false
		end
		return
	end
	local rh, lh = model:FindFirstChild("RightHand"), model:FindFirstChild("LeftHand")
	local root = rig.root
	if not (rh and lh and root) then
		return
	end
	if not rig.rope then
		local a0 = Instance.new("Attachment")
		a0.Name = "RopeA"
		a0.Parent = lh
		local a1 = Instance.new("Attachment")
		a1.Name = "RopeB"
		a1.Parent = rh
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0, beam.Width1 = 0.12, 0.12
		beam.Segments = 16
		beam.FaceCamera = true
		beam.LightInfluence = 1
		beam.Color = ColorSequence.new(Color3.fromRGB(60, 66, 84))
		beam.Parent = rh
		rig.rope = { a0 = a0, a1 = a1, beam = beam }
	end
	rig.rope.beam.Enabled = true
	-- rope direction: rotates around the boxer's left-right axis
	local rc = root.CFrame
	local dir = rc:VectorToWorldSpace(V3(0, -cos(phase), sin(phase)))
	local function aim(att, part)
		local axis = part.CFrame:VectorToObjectSpace(dir)
		att.CFrame = CFrame.lookAt(Vector3.zero, axis) * A(0, PI / 2, 0)
	end
	aim(rig.rope.a0, lh)
	aim(rig.rope.a1, rh)
	-- long enough for the loop to pass under the feet from hip-height hands
	rig.rope.beam.CurveSize0 = 4.3
	rig.rope.beam.CurveSize1 = -4.3
end

AnimGym.POSE = POSE
AnimGym.startGesture = startGesture
AnimGym.gestureOverlay = gestureOverlay
AnimGym.runPending = runPending
AnimGym.ambientAct = ambientAct
AnimGym.findPartner = findPartner
AnimGym.ropeVisual = ropeVisual
AnimGym.palmsIn = palmsIn

return AnimGym
