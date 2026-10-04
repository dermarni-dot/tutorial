-- Animator: motion-capture-feeling procedural animation for everyone in the game, no animation
-- assets. Drives the R15 joints' Transform (classic Motor6D joints and AnimationConstraint avatar
-- joints) every frame in PreSimulation.
--  * tag "Fighter": style / physique stances, directional footwork with planted feet, kinetic-chain
--    punches (feet -> hips -> shoulders -> fist, pivot on the ball of the foot, weight transfer,
--    arm IK onto the opponent), defence, damage-scaled directional hit reactions on springs,
--    dazed / rubber-legged / out-on-his-feet body language, stumbles, knockdown falls by DownPose,
--    beating the count, get-ups, KO limpness, fatigue breathing, walkout / corner / win / lose
--    (attributes Guard, Act, ActId, Style, Frame, Bulk, Stam, Daze, Conc, DownPose, Count, Expr ...)
--  * tag "Trainee": training poses that work the right muscles (attribute Pose; local minigames add
--    PoseDrive / PoseSpeed / RepCount / Act / TwistSide / Effort / LivePump), flex poses
--  * tag "Ambient": gym members' loops (attribute Loop): bag work in combos, sparring pairs that
--    trade shots, coaches who watch, point, clap and shout, ringside watchers, cornermen
--  * tag "Referee": the fight referee (Loop "referee", acts refcount|n / waveoff)
--  * tag "Preview": the Creator's local preview character
-- Other players' training punches are re-synthesized locally and published as client-local
-- AutoAct / AutoActId so the gym's bags react (CONTRACTS section 7).
-- Faces (blinks, gaze, expressions), muscles (contraction, pump, jiggle, veins) and hair (spring
-- physics) live in BoxerClient.FaceFX / BodyFX / HairFX; this script drives them every frame.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = script.Parent:WaitForChild("BoxerClient")
local K = require(Modules:WaitForChild("AnimKit"))

-- the FX modules are optional: the body animation must keep running if one of them fails
local function optional(name)
	local ok, mod = pcall(function()
		return require(Modules:WaitForChild(name, 10))
	end)
	if ok and type(mod) == "table" then
		return mod
	end
	warn("[Animator] " .. name .. " unavailable: " .. tostring(mod))
	return nil
end
local BodyFX = optional("BodyFX")
local FaceFX = optional("FaceFX")
local HairFX = optional("HairFX")
local okConfig, Config = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
end)
if not okConfig then
	Config = {}
end

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local PI = math.pi
local sin, cos, abs, max, min, exp, sqrt, atan2, floor = math.sin, math.cos, math.abs, math.max, math.min, math.exp, math.sqrt, math.atan2, math.floor
local clamp = math.clamp
local smooth, easeOut, easeInOut, lerp = K.smooth, K.easeOut, K.easeInOut, K.lerp

local JOINTS = {
	Root = { "LowerTorso", "Root" }, W = { "UpperTorso", "Waist" }, Neck = { "Head", "Neck" },
	RS = { "RightUpperArm", "RightShoulder" }, RE = { "RightLowerArm", "RightElbow" }, RW = { "RightHand", "RightWrist" },
	LS = { "LeftUpperArm", "LeftShoulder" }, LE = { "LeftLowerArm", "LeftElbow" }, LW = { "LeftHand", "LeftWrist" },
	RH = { "RightUpperLeg", "RightHip" }, RK = { "RightLowerLeg", "RightKnee" }, RA = { "RightFoot", "RightAnkle" },
	LH = { "LeftUpperLeg", "LeftHip" }, LK = { "LeftLowerLeg", "LeftKnee" }, LA = { "LeftFoot", "LeftAnkle" },
}
local KEYS = { "Root", "W", "Neck", "RS", "RE", "RW", "LS", "LE", "LW", "RH", "RK", "RA", "LH", "LK", "LA" }
local LEG_KEYS = { RH = true, RK = true, RA = true, LH = true, LK = true, LA = true }
local TAGS = { "Fighter", "Trainee", "Ambient", "Preview", "Referee" }
local rigs = {}

-- LOD bands (studs from the camera)
local NEAR, MID, FAR, CULL = 45, 110, 170, 230

local SIDES = { "L", "R" }
-- joint keys per side, precomputed so the per-frame IK never builds strings
local LEG_OF = { L = { "LH", "LK", "LA" }, R = { "RH", "RK", "RA" } }
local ARM_OF = { L = { "LS", "LE", "armL" }, R = { "RS", "RE", "armR" } }
local PUNCHES = { jab = true, cross = true, hook = true, leadhook = true, rearhook = true, uppercut = true, overhand = true }
local PUNCH_HAND = { jab = "L", cross = "R", leadhook = "L", rearhook = "R", hook = "R", uppercut = "R", overhand = "R" }

-- which exercise (Config.ExerciseTargets / Activities id) a pose works: BodyFX contraction + LivePump
local POSE_ACT = {
	bench = "Bench", curl = "Dumbbells", deadlift = "Barbell", squat = "Squat", pullup = "PullUps", medball = "MedBall",
	row = "Rower", run = "Treadmill", bike = "Bike", rope = "Rope", ladder = "Ladder", heavybag = "HeavyBag",
	speedbag = "SpeedBag", guard = "Shadow", shadow = "Shadow", spar = "Sparring",
}

------------------------------------------------------------------------
-- Joints and rig geometry
------------------------------------------------------------------------
-- Motor6D or AnimationConstraint: C0 / C1 equivalents
local function jointC0(m)
	if m:IsA("Motor6D") then
		return m.C0
	end
	local a = m.Attachment0
	return a and a.CFrame or I
end
local function jointC1(m)
	if m:IsA("Motor6D") then
		return m.C1
	end
	local a = m.Attachment1
	return a and a.CFrame or I
end

local function findJoint(model, key)
	local path = JOINTS[key]
	local p = model:FindFirstChild(path[1])
	local m = p and p:FindFirstChild(path[2])
	if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then
		return m
	end
	return nil
end

-- (re)resolve joint motors: the Builder's head swap (ReplaceBodyPartR15) replaces the Neck, body
-- rescales replace C0 / C1, respawns replace everything
local function resolveJoints(rig)
	local model = rig.model
	for _, key in ipairs(KEYS) do
		local j = rig.joints[key]
		local m = findJoint(model, key)
		if m then
			if not j then
				j = { key = key, motor = m, base = I, cur = I }
				rig.joints[key] = j
			elseif j.motor ~= m then
				j.motor = m
			end
		elseif j then
			rig.joints[key] = nil
		end
	end
end

-- bind-pose geometry in HumanoidRootPart space: leg lengths, rest ankles, ground height, arm lengths
local function computeGeo(rig)
	local J = rig.joints
	local g = rig.geo
	g.ok = false
	local root = rig.root
	if not (root and J.Root and J.W and J.RH and J.RK and J.RA and J.LH and J.LK and J.LA) then
		return
	end
	local rootC0 = jointC0(J.Root.motor)
	local rootC1inv = jointC1(J.Root.motor):Inverse()
	g.rootC0, g.rootC1inv = rootC0, rootC1inv
	g.waistC0 = jointC0(J.W.motor)
	g.waistC1inv = jointC1(J.W.motor):Inverse()
	local lt0 = rootC0 * rootC1inv
	local lowest = math.huge
	for _, s in ipairs(SIDES) do
		local hipM, kneeM, ankleM = J[s .. "H"].motor, J[s .. "K"].motor, J[s .. "A"].motor
		local leg = g[s] or {}
		g[s] = leg
		leg.hipC0 = jointC0(hipM)
		leg.hipC1inv = jointC1(hipM):Inverse()
		leg.kneeC0 = jointC0(kneeM)
		leg.kneeC1inv = jointC1(kneeM):Inverse()
		leg.ankleC0 = jointC0(ankleM)
		local ankleC1 = jointC1(ankleM)
		leg.ankleC1rot = ankleC1.Rotation
		leg.l1 = max(0.3, (leg.hipC1inv * leg.kneeC0).Position.Magnitude)
		leg.l2 = max(0.3, (leg.kneeC1inv * leg.ankleC0).Position.Magnitude)
		local ankleCF = lt0 * leg.hipC0 * leg.hipC1inv * leg.kneeC0 * leg.kneeC1inv * leg.ankleC0
		leg.ankle0 = ankleCF.Position
		leg.footRest = (ankleCF * ankleC1:Inverse()).Rotation
		local foot = ankleM.Part1
		local fs = foot and foot.Size or V3(0.7, 0.4, 1)
		local footC = (ankleCF * ankleC1:Inverse()).Position
		lowest = min(lowest, footC.Y - fs.Y / 2)
		leg.ball = fs.Z * 0.42
	end
	g.groundY = lowest
	g.rootY = rootC0.Position.Y
	g.floorH = g.rootY - g.groundY -- height of the root joint above the floor when standing
	g.legLen = (g.L.l1 + g.L.l2 + g.R.l1 + g.R.l2) / 2
	-- torso size: guard targets are authored for a 2 x 1.6 x 1 UpperTorso and scale with the body
	local utPart = J.W.motor.Part1
	local us = utPart and utPart.Size or V3(2, 1.6, 1)
	g.utScale = V3(us.X / 2, us.Y / 1.6, us.Z)
	-- arms (for punch IK)
	for _, s in ipairs(SIDES) do
		local sh, el, wr = J[s .. "S"], J[s .. "E"], J[s .. "W"]
		local arm = g["arm" .. s] or {}
		g["arm" .. s] = arm
		arm.ok = false
		if sh and el and wr then
			arm.c0 = jointC0(sh.motor)
			arm.c1inv = jointC1(sh.motor):Inverse()
			arm.elbowC0 = jointC0(el.motor)
			-- rest bone vectors (the R15 shoulder joint sits at the arm's inner edge, so the upper
			-- arm does not hang straight below it): the IK rotates these onto the solved points
			arm.u0 = (arm.c1inv * arm.elbowC0).Position
			arm.a = max(0.3, arm.u0.Magnitude)
			arm.elbowRot = (arm.c1inv * arm.elbowC0).Rotation
			local hand = wr.motor.Part1
			local f0 = (jointC1(el.motor):Inverse() * jointC0(wr.motor)).Position
			local ext = hand and hand.Size.Y * 0.55 or 0.35
			arm.v0 = f0.Magnitude > 1e-3 and f0 + f0.Unit * ext or V3(0, -0.8, 0) -- elbow frame
			arm.b = max(0.3, arm.v0.Magnitude)
			-- hinge geometry for solveArm: the hinge axis in the shoulder frame, the bones split into
			-- their parts along the hinge (kk) and in the bending plane (ap, bp, angles phiU / phiV)
			arm.hinge = arm.elbowRot.RightVector
			local u0e = arm.elbowRot:VectorToObjectSpace(arm.u0)
			arm.kk = u0e.X + arm.v0.X
			arm.ap = max(0.05, sqrt(u0e.Y * u0e.Y + u0e.Z * u0e.Z))
			arm.bp = max(0.05, sqrt(arm.v0.Y * arm.v0.Y + arm.v0.Z * arm.v0.Z))
			arm.phiU = atan2(u0e.Z, -u0e.Y)
			arm.phiV = atan2(arm.v0.Z, -arm.v0.Y)
			arm.dMax = sqrt((arm.ap + arm.bp) ^ 2 + arm.kk * arm.kk) * 0.998
			arm.dMin = sqrt((arm.ap - arm.bp) ^ 2 + arm.kk * arm.kk) * 1.02 + 0.02
			arm.ok = true
		end
	end
	g.ok = true
end

------------------------------------------------------------------------
-- Rig registry: tags, cached attributes (signals, not per-frame polling), act parsing
------------------------------------------------------------------------
local function hasAnyTag(model)
	for _, tag in ipairs(TAGS) do
		if CollectionService:HasTag(model, tag) then
			return true
		end
	end
	return false
end

local function newFoot()
	return { x = 0, z = 0, yaw = 0, heel = 0, lift = 0, knee = 0, free = false,
		pos = nil, yawW = 0, swing = false, from = nil, t0 = 0, dur = 0.2, liftH = 0.2, lastStep = 0, fromYaw = 0, cur = nil, curLift = 0 }
end

local onAct -- forward declaration (acts section)

local function readTags(rig)
	local m = rig.model
	rig.isFighter = CollectionService:HasTag(m, "Fighter")
	rig.isTrainee = CollectionService:HasTag(m, "Trainee")
	rig.isAmbient = CollectionService:HasTag(m, "Ambient")
	rig.isPreview = CollectionService:HasTag(m, "Preview")
	rig.isReferee = CollectionService:HasTag(m, "Referee")
end

local function onAttr(rig, name)
	local model = rig.model
	local v = model:GetAttribute(name)
	local old = rig.a[name]
	rig.a[name] = v
	local now = os.clock()
	if name == "ActId" then
		if v ~= nil and v ~= rig.lastActId then
			rig.lastActId = v
			onAct(rig, model:GetAttribute("Act"), now, false)
		end
	elseif name == "PredActId" then
		if v ~= nil and v ~= rig.predId then
			rig.predId = v
			onAct(rig, model:GetAttribute("PredAct"), now, true)
		end
	elseif name == "Guard" then
		if v ~= old then
			rig.prevGuard = old
			rig.guardT = now
		end
	elseif name == "Pose" or name == "Loop" then
		if v ~= old then
			rig.poseT = now
			rig.combo = nil
			rig.nextLook = 0 -- re-target now (bag on / off, watchers)
		end
	elseif name == "Count" then
		rig.countT = now
	end
end

local function setup(model)
	if not model:IsA("Model") then
		return
	end
	local rig = rigs[model]
	if rig then
		readTags(rig)
		return
	end
	local seed = model:GetAttribute("AmbientSeed") or (#model.Name * 97 + 13)
	rig = {
		model = model, joints = {}, geo = { ok = false }, a = {}, p = {}, kp = {}, kp2 = {},
		rng = Random.new(seed), seed = seed, phase = (seed % 100) / 100 * 6.28,
		root = model:FindFirstChild("HumanoidRootPart"), head = model:FindFirstChild("Head"),
		lastActId = model:GetAttribute("ActId"), predId = model:GetAttribute("PredActId"),
		act = nil, autoAct = nil, pending = nil, predKind = nil, predHand = nil, predT = -10,
		sx = table.create(10, 0), sv = table.create(10, 0),
		foot = { L = newFoot(), R = newFoot() }, plant = false, stepDist = 0.45, stepTime = 1,
		cxL = {}, cxR = {}, poseAct = nil, exprHint = nil, breath = 0,
		lookPos = nil, lookPart = nil, lookYaw = 0, lookPitch = 0, nextLook = 0, lookW = 0,
		guardT = os.clock(), prevGuard = nil, poseT = os.clock(), countT = 0,
		breathPhase = 0, bouncePhase = 0, nextAuto = 0, autoId = 0, sbCount = 0, combo = nil, comboI = 0,
		gesture = nil, nextGesture = os.clock() + 3, watch = nil, watchAct = nil,
		lastT = os.clock(), nextGeo = 0, nextResolve = 0, frameSkip = 0, impactT = -10,
		koTilt = (seed % 7) / 7 - 0.5, partner = nil, nextPartner = 0, curlCycle = 0, lod = 3,
		guardL = nil, guardR = nil, guardSink = 0,
	}
	rig.isLocal = model == player.Character
	readTags(rig)
	for name, v in pairs(model:GetAttributes()) do
		rig.a[name] = v
	end
	rig.a.Act = nil -- an act that happened before we saw the model is not replayed
	rig.conn = model.AttributeChanged:Connect(function(name)
		onAttr(rig, name)
	end)
	resolveJoints(rig)
	computeGeo(rig)
	rigs[model] = rig
	if BodyFX then
		BodyFX.Track(model)
	end
end

local function teardown(model)
	local rig = rigs[model]
	if not rig then
		return
	end
	if model.Parent and hasAnyTag(model) then
		readTags(rig)
		return
	end
	for _, j in pairs(rig.joints) do
		if j.motor and j.motor.Parent then
			j.motor.Transform = I
		end
	end
	if rig.rope then
		rig.rope.beam:Destroy()
		rig.rope.a0:Destroy()
		rig.rope.a1:Destroy()
	end
	if rig.conn then
		rig.conn:Disconnect()
	end
	-- players keep their pump visible after training; NPC rigs are done
	if BodyFX and not Players:GetPlayerFromCharacter(model) then
		BodyFX.Untrack(model)
	end
	rigs[model] = nil
end

------------------------------------------------------------------------
-- Pose building blocks
------------------------------------------------------------------------
-- reset the per-frame pose table, foot spec, muscle contraction and face hints (no allocation)
local function clearPose(rig)
	local p = rig.p
	for _, k in ipairs(KEYS) do
		p[k] = I
	end
	p.snap = false
	p.rate = nil
	p.override = false
	rig.plant = false
	rig.stepDist, rig.stepTime, rig.liftK = 0.45, 1, 1
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		f.x, f.z, f.yaw, f.heel, f.lift, f.knee, f.pivot, f.free = 0, 0, 0, 0, 0, 0, 0, false
	end
	local cl, cr = rig.cxL, rig.cxR
	for k in pairs(cl) do
		cl[k] = 0
	end
	for k in pairs(cr) do
		cr[k] = 0
	end
	rig.exprHint = nil
	rig.breath = 0
	rig.lookW = 0
	rig.poseAct = nil
	rig.guardL, rig.guardR = nil, nil
end

-- muscle contraction for BodyFX: side -1 left, 1 right, nil both
local function flex(rig, id, v, side)
	if v <= 0.001 then
		return
	end
	if side ~= 1 and (rig.cxL[id] or 0) < v then
		rig.cxL[id] = v
	end
	if side ~= -1 and (rig.cxR[id] or 0) < v then
		rig.cxR[id] = v
	end
end

-- contract every muscle an exercise trains, weighted by Config.ExerciseTargets
local function flexAct(rig, actId, level, side)
	local T = BodyFX and BodyFX.Targets[actId]
	if not T or level <= 0.001 then
		return
	end
	for id, w in pairs(T) do
		flex(rig, id, w * level, side)
	end
end

-- leg angles only (no Root change) for a hip drop of `depth`: the cheap far-LOD / non-planted solver
local function legAngles(p, depth, stagger, len)
	depth = max(0, depth)
	len = len or 2.3
	local a = math.acos(clamp(1 - depth / len, -1, 1))
	stagger = stagger or 0
	p.LH = A(a + stagger, 0, 0)
	p.LK = A(-2 * a, 0, 0)
	p.LA = A(a - stagger, 0, 0)
	p.RH = A(a - stagger, 0, 0)
	p.RK = A(-2 * a, 0, 0)
	p.RA = A(a + stagger, 0, 0)
end

-- drop the hips by depth and bend the legs to keep the feet down (poses that do not plant)
local function legs(p, depth, stagger, rig)
	depth = max(0, depth)
	p.Root = p.Root * CF(0, -depth, 0)
	legAngles(p, depth, stagger, rig and rig.geo.ok and rig.geo.legLen or 2.3)
	return p
end

-- plant both feet (IK runs after the acts): stagger = lead (left) foot forward / rear back (studs),
-- width = extra stance width, yawL / yawR = toe directions (+ = turned left), heel lifts
local function plant(rig, stagger, width, yawL, yawR, heelL, heelR)
	rig.plant = true
	local fL, fR = rig.foot.L, rig.foot.R
	stagger = stagger or 0
	fL.z, fR.z = -stagger * 0.5, stagger * 0.5
	fL.x, fR.x = width or 0, width or 0
	fL.yaw, fR.yaw = yawL or 0, yawR or 0
	fL.heel, fR.heel = heelL or 0, heelR or 0
end

-- physique: big lats and arms hang further from the body; heavy frames move less
local FRAME_AMP = { Lean = 1.12, Athletic = 1, Muscular = 0.92, ["Power Build"] = 0.82, ["Heavyweight Build"] = 0.66 }
local function bulkOf(rig)
	local b = rig.a.Bulk
	return type(b) == "number" and clamp(b, 0, 1) or 0.3
end
local function ampOf(rig)
	return (FRAME_AMP[rig.a.Frame] or 1) * (1 - 0.22 * bulkOf(rig))
end

-- relaxed standing with breathing and a slow weight shift; plants the feet
local function stand(p, rig, t, dt, breathe, shift)
	local amp = ampOf(rig)
	-- arms hang out from the body (+Z on the right shoulder = hand away from the hip): more with bulk,
	-- so big lats / arms clear the hips and lat overlays
	local out = 0.03 + 0.12 * bulkOf(rig)
	rig.breathPhase += dt * (0.25 + 0.1 * (breathe or 1))
	local b = K.breath(rig.breathPhase) * 0.03 * (breathe or 1)
	-- weight shift: hips drift over one leg, the torso counter-rolls (contrapposto)
	local ws = (shift or 1) * sin(t * 0.45 + rig.phase) * amp
	p.Root = CF(0.07 * ws, -0.03 - 0.02 * abs(ws), 0) * A(0, 0.04 * ws, -0.035 * ws)
	p.W = A(b - 0.02, 0, 0.03 * ws)
	p.Neck = A(-b * 0.6, 0, -0.02 * ws)
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
	return p
end

local function seated(p, lean)
	lean = lean or 0
	p.Root = A(-lean, 0, 0)
	p.RH = A(PI / 2 + lean, 0, 0.06)
	p.LH = A(PI / 2 + lean, 0, -0.06)
	p.RK = A(-PI / 2, 0, 0)
	p.LK = A(-PI / 2, 0, 0)
	return p
end

------------------------------------------------------------------------
-- Planted feet: world-locked footfalls with stepping, then two-bone leg IK (AnimKit.legIK)
------------------------------------------------------------------------
local function footHome(rig, s, rootCF)
	local f = rig.foot[s]
	local leg = rig.geo[s]
	local sx = s == "L" and -1 or 1
	return rootCF:PointToWorldSpace(leg.ankle0 + V3(sx * f.x, 0, f.z))
end

local function solveLeg(rig, p, s, rootT, targetHRP, footYaw, heel, knee)
	local g = rig.geo
	local leg = g[s]
	local hipFrame = g.rootC0 * rootT * g.rootC1inv * leg.hipC0
	local d = hipFrame:PointToObjectSpace(targetHRP)
	-- a foot target level with or above the hip (extreme poses) would flip the leg: keep it below
	local floorY = -0.3 * (leg.l1 + leg.l2)
	if d.Y > floorY then
		d = V3(d.X, floorY, d.Z)
	end
	-- soft reach: the knee eases straight instead of snapping when a foot is stretched out
	local full = (leg.l1 + leg.l2) * 0.999
	local dm = d.Magnitude
	local soft = K.softReach(dm, full, full * 0.08)
	if soft < dm and dm > 1e-6 then
		d = d * (soft / dm)
	end
	local pitch, roll, flexK = K.legIK(d.X, d.Y, d.Z, leg.l1, leg.l2)
	-- the knee tracks over the toes: twist the leg about the hip -> ankle line
	local look = hipFrame.LookVector
	local tw = clamp(K.wrap(footYaw - atan2(-look.X, -look.Z)) * 0.55 + knee, -0.8, 0.8)
	local hipT = A(0, 0, roll) * A(pitch, 0, 0)
	if abs(tw) > 1e-3 and d.Magnitude > 1e-3 then
		hipT = CFrame.fromAxisAngle(d.Unit, tw) * hipT
	end
	local kneeT = A(-flexK, 0, 0)
	-- the foot stays flat (or up on its toes) at its planted yaw, whatever the leg does
	local chain = (hipFrame * hipT * leg.hipC1inv * leg.kneeC0 * kneeT * leg.kneeC1inv * leg.ankleC0).Rotation
	local want = A(0, footYaw, 0) * A(-heel, 0, 0) * leg.footRest
	local keys = LEG_OF[s]
	p[keys[1]] = hipT
	p[keys[2]] = kneeT
	p[keys[3]] = chain:Inverse() * want * leg.ankleC1rot
end

local function plantFeet(rig, p, rootT, t, lock)
	local root = rig.root
	local rootCF = root.CFrame
	local look = rootCF.LookVector
	local rootYaw = atan2(-look.X, -look.Z)
	local vel = root.AssemblyLinearVelocity
	local hv = V3(vel.X, 0, vel.Z)
	local speed = hv.Magnitude
	local needL, needR = 0, 0
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		local home = footHome(rig, s, rootCF)
		local homeYaw = rootYaw + f.yaw
		f.home = home
		if not lock or f.free or not f.pos then
			f.pos, f.yawW, f.swing, f.curLift = home, homeYaw, false, 0
		elseif f.swing then
			local u = (t - f.t0) / f.dur
			-- aim where the home will be when the foot lands
			local tgt = home + hv * (f.dur * max(0, 1 - u) * 0.6)
			if u >= 1 then
				f.swing, f.pos, f.yawW, f.lastStep, f.curLift = false, tgt, homeYaw, t, 0
			else
				local e = smooth(u)
				f.cur = f.from:Lerp(tgt, e)
				f.curYaw = f.fromYaw + K.wrap(homeYaw - f.fromYaw) * e
				f.curLift = f.liftH * sin(PI * u)
			end
		else
			local dx, dz = f.pos.X - home.X, f.pos.Z - home.Z
			local err = sqrt(dx * dx + dz * dz)
			if err > 5 then
				f.pos, f.yawW = home, homeYaw -- teleported (Poser.Place, PivotTo)
			else
				local yerr = abs(K.wrap(f.yawW - homeYaw))
				if err > rig.stepDist or yerr > 0.6 then
					if s == "L" then
						needL = err + yerr
					else
						needR = err + yerr
					end
				end
			end
		end
	end
	-- start a step: boxers move the foot on the side of travel first and never cross the feet
	-- (moving right, the right foot leads); otherwise the foot furthest from home goes first.
	-- At speed the second foot may leave before the first has landed (a shuffle, not a walk).
	if needL > 0 or needR > 0 then
		local lvx = rootCF:VectorToObjectSpace(hv).X
		local s
		if abs(lvx) > 1.5 and needL > 0 and needR > 0 then
			s = lvx > 0 and "R" or "L"
		elseif abs(lvx) > 1.5 and (lvx > 0 and needL > 0 and not rig.foot.R.swing and t - rig.foot.R.lastStep > 0.12) then
			s = "R" -- the trailing foot wants to go first: lead with the other one instead
			if needR == 0 then
				s = nil
				if t - rig.foot.R.lastStep > 0.35 then
					s = "L"
				end
			end
		elseif abs(lvx) > 1.5 and (lvx < 0 and needR > 0 and not rig.foot.L.swing and t - rig.foot.L.lastStep > 0.12) then
			s = "L"
			if needL == 0 then
				s = nil
				if t - rig.foot.L.lastStep > 0.35 then
					s = "R"
				end
			end
		else
			s = needL >= needR and "L" or "R"
		end
		local f = s and rig.foot[s]
		local o = s and rig.foot[s == "L" and "R" or "L"]
		if f and not f.swing then
			local overlap = speed > 3 and o.swing and (t - o.t0) > o.dur * 0.45
			if (not o.swing or overlap) and t - o.lastStep > 0.04 * rig.stepTime then
				f.swing, f.t0, f.from, f.fromYaw = true, t, f.pos, f.yawW
				f.dur = clamp(0.26 - speed * 0.02, 0.11, 0.26) * rig.stepTime
				f.liftH = clamp(0.1 + speed * 0.012, 0.1, 0.3) * rig.liftK
				f.cur, f.curYaw, f.curLift = f.pos, f.yawW, 0
			end
		end
	end
	-- pivots / heel lifts / knee turns come from acts frame by frame: low-pass them so an
	-- interrupted act never makes a foot jump
	local fk = 1 - exp(-(rig.dt or 1 / 60) * 30)
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		f.heelS = (f.heelS or 0) + (f.heel - (f.heelS or 0)) * fk
		f.pivotS = (f.pivotS or 0) + (f.pivot - (f.pivotS or 0)) * fk
		f.kneeS = (f.kneeS or 0) + (f.knee - (f.kneeS or 0)) * fk
	end
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		local leg = rig.geo[s]
		local pos = f.swing and f.cur or f.pos
		local yawW = f.swing and f.curYaw or f.yawW
		local heel = f.heelS + (f.swing and 0.3 * f.curLift / max(0.05, f.liftH) or 0)
		local tgt = rootCF:PointToObjectSpace(V3(pos.X, f.home.Y, pos.Z)) + V3(0, f.curLift + f.lift + leg.ball * sin(heel), 0)
		solveLeg(rig, p, s, rootT, tgt, K.wrap(yawW - rootYaw) + f.pivotS, heel, f.kneeS)
	end
end

------------------------------------------------------------------------
-- Arm IK: punches land where the target is (AnimKit.chainPoints), blended onto the authored arc
------------------------------------------------------------------------
-- rotation that takes the orthonormal frame built from (a, b) onto the one built from (c, d)
-- (a -> c exactly, b -> d as closely as the angle between them allows)
local function frameOf(a, b)
	local x = a.Unit
	local y = b - x * b:Dot(x)
	if y.Magnitude < 1e-6 then
		y = math.abs(x.Y) < 0.9 and V3(0, 1, 0) or V3(1, 0, 0)
		y -= x * y:Dot(x)
	end
	y = y.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end
local function pairRotation(a, b, c, d)
	return frameOf(c, d) * frameOf(a, b):Inverse()
end

-- Exact arm IK for any rest geometry: the elbow is a hinge about its local X axis (positive =
-- flexion, as on R15), the hinge angle comes from the law of cosines on the real bone vectors
-- (the R15 shoulder joint sits off the arm's centre line, so the bones are not collinear), and the
-- shoulder rotation maps (arm line, hinge axis) onto (target line, pole-oriented hinge) - continuous
-- for any pole, including elbows above the shoulder. d = fist target, n = pole, both in the
-- shoulder joint's frame. Returns the shoulder and elbow Transforms.
local function solveArm(arm, d, nx, ny, nz)
	local D = clamp(K.softReach(d.Magnitude, arm.dMax, arm.dMax * 0.07), arm.dMin, arm.dMax)
	local dn = D > 1e-6 and d.Unit or V3(0, -1, 0)
	-- hinge angle: |u0e + Rx(alpha) v0| = D, solved in the elbow's YZ plane
	local Dp2 = max(1e-6, D * D - arm.kk * arm.kk)
	local C = clamp((Dp2 - arm.ap * arm.ap - arm.bp * arm.bp) / (2 * arm.ap * arm.bp), -1, 1)
	local alpha = math.acos(C) - arm.phiU + arm.phiV
	-- the fist vector of that bent arm in the shoulder's rest frame, and its hinge axis
	local V = arm.u0 + arm.elbowRot:VectorToWorldSpace(A(alpha, 0, 0) * arm.v0)
	local c = V.Unit:Dot(arm.hinge)
	-- hinge axis in the solved pose: same angle to the arm line, turned so the elbow points at the pole
	local n = V3(nx, ny, nz)
	-- a pole close to the arm line is ill-defined: fade in a down-and-back pole before it flips
	local perp = (n - dn * n:Dot(dn)).Magnitude / max(1e-6, n.Magnitude)
	if perp < 0.45 then
		n += V3(0, -1, 0.35) * ((0.45 - perp) * 4)
	end
	local side = n:Cross(dn)
	if side.Magnitude < 1e-4 then
		side = V3(0, 0, 1):Cross(dn)
		if side.Magnitude < 1e-4 then
			side = V3(1, 0, 0)
		end
	end
	local w = dn * c + side.Unit * sqrt(max(0, 1 - c * c))
	return pairRotation(V, arm.hinge, dn, w), A(alpha, 0, 0)
end

local function armIK(rig, p, s, target, w)
	local g = rig.geo
	local keys = ARM_OF[s]
	local arm = g[keys[3]]
	if not (arm and arm.ok and g.ok) or w <= 0.01 then
		return
	end
	local ut = rig.root.CFrame * g.rootC0 * p.Root * g.rootC1inv * g.waistC0 * p.W * g.waistC1inv
	local d = (ut * arm.c0):PointToObjectSpace(target)
	if d.Magnitude > (arm.a + arm.b) * 1.6 then
		return -- out of range: keep the authored punch (a miss looks like a miss)
	end
	-- the elbow bends down and a little out (the natural line of a straight punch)
	local shT, elT = solveArm(arm, d, s == "L" and -0.35 or 0.35, -1, 0.1)
	p[keys[1]] = p[keys[1]]:Lerp(shT, w)
	p[keys[2]] = p[keys[2]]:Lerp(elT, w)
end

-- put a glove at (x, y, z) in UpperTorso space (authored for a standard torso, scaled to this one);
-- elbows tucked down. Returns false when the rig is too far / has no arm geometry (keep authored)
local function guardArm(rig, p, s, x, y, z, w, elbowFwd, poleOut, poleUp)
	local g = rig.geo
	local keys = ARM_OF[s]
	local arm = g[keys[3]]
	if not (g.ok and arm and arm.ok and rig.lod >= 2) or w <= 0.01 then
		return false
	end
	local sc = g.utScale
	local d = arm.c0:PointToObjectSpace(V3(x * sc.X, y * sc.Y, z * sc.Z))
	local out = poleOut or 0.2
	local shT, elT = solveArm(arm, d, s == "L" and -out or out, poleUp or -1, -(elbowFwd or 0.1))
	if w >= 1 then
		p[keys[1]], p[keys[2]] = shT, elT
	else
		p[keys[1]] = p[keys[1]]:Lerp(shT, w)
		p[keys[2]] = p[keys[2]]:Lerp(elT, w)
	end
	return true
end

------------------------------------------------------------------------
-- Hit reactions: damped springs (overshoot = whiplash), kicked by impulses
------------------------------------------------------------------------
-- 1 head pitch (+ face up), 2 head yaw (+ left), 3 head roll, 4 torso pitch (+ back), 5 torso yaw,
-- 6 torso roll, 7 hips back (studs, +Z), 8 hips sideways (+X), 9 knee drop (studs), 10 cover-up
local SPR_K = { 170, 150, 150, 110, 110, 110, 60, 60, 45, 80 }
local SPR_Z = { 0.3, 0.3, 0.35, 0.45, 0.45, 0.45, 0.75, 0.75, 0.55, 0.9 }
local SPR_MAX = { 1.0, 1.1, 0.8, 0.7, 0.6, 0.6, 1.2, 1.2, 0.9, 1.2 }

local function stepSprings(rig, dt)
	local x, v = rig.sx, rig.sv
	local daze = rig.a.Daze
	local soft = 1 - 0.15 * (type(daze) == "number" and daze or 0) -- a hurt neck is a weak neck
	local active = false
	for i = 1, 10 do
		local xi, vi = x[i], v[i]
		if xi ~= 0 or vi ~= 0 then
			local k = SPR_K[i] * soft
			xi, vi = K.spring(xi, vi, 0, k, K.damping(k, SPR_Z[i]), dt)
			if abs(xi) < 1e-4 and abs(vi) < 1e-3 then
				xi, vi = 0, 0
			else
				active = true
			end
			x[i], v[i] = clamp(xi, -SPR_MAX[i], SPR_MAX[i]), vi
		end
	end
	return active
end

local function applySprings(rig, p)
	local x = rig.sx
	if x[1] ~= 0 or x[2] ~= 0 or x[3] ~= 0 then
		p.Neck = p.Neck * A(x[1], x[2], x[3])
	end
	if x[4] ~= 0 or x[5] ~= 0 or x[6] ~= 0 then
		p.W = p.W * A(x[4], x[5], x[6])
	end
	if x[7] ~= 0 or x[8] ~= 0 or x[9] ~= 0 then
		p.Root = CF(x[8], -x[9], x[7]) * p.Root
	end
	local c = clamp(x[10], 0, 1)
	if c > 0.01 then
		p.LS = p.LS:Lerp(A(1.75, 0, 0.45), c)
		p.LE = p.LE:Lerp(A(2.35, 0, 0), c)
		p.RS = p.RS:Lerp(A(1.75, 0, -0.45), c)
		p.RE = p.RE:Lerp(A(2.35, 0, 0), c)
	end
end

local function kick(rig, hp, hy, hr, tp, ty, tr, back, side, drop, cover)
	local v = rig.sv
	v[1] += hp or 0
	v[2] += hy or 0
	v[3] += hr or 0
	v[4] += tp or 0
	v[5] += ty or 0
	v[6] += tr or 0
	v[7] += back or 0
	v[8] += side or 0
	v[9] += drop or 0
	v[10] += cover or 0
	-- a spring at rest needs a nudge to be integrated
	for i = 1, 10 do
		if v[i] ~= 0 and rig.sx[i] == 0 then
			rig.sx[i] = 1e-4
		end
	end
end

------------------------------------------------------------------------
-- Fight stances: style (Style attribute) x physique (Frame / Bulk) x stamina (Stam) x daze (Daze)
------------------------------------------------------------------------
-- stagger / width in studs, foot yaw (+ = toes turned left; the rear foot turns out), heel lift,
-- hip = blade angle of the pelvis, wyaw = extra shoulder turn, tuck = chin, lead / rear = shoulder
-- pitch, shoulder roll (+ = in), elbow; weave = bob-and-weave amplitude, roll = shoulder roll rhythm
-- leadT / rearT = where the gloves sit (UpperTorso space: x right, y up, -z forward; the head is
-- at about y 1.3 and its front at z -0.6 on a standard rig)
local STYLE = {
	BoxerPuncher = { depth = 0.25, bounce = 1, freq = 7, stagger = 1.0, width = 0.06, yawL = -0.22, yawR = -0.78, heel = 0.1,
		hip = -0.3, wyaw = -0.08, tuck = -0.15, lead = { 0.95, 0.25, 1.78 }, rear = { 0.78, 0.3, 2.08 }, weave = 0, roll = 0,
		leadT = { -0.3, 0.95, -1.4 }, rearT = { 0.38, 1.02, -0.78 } },
	OutBoxer = { depth = 0.19, bounce = 1.35, freq = 7.6, stagger = 1.15, width = 0.02, yawL = -0.15, yawR = -0.85, heel = 0.2,
		hip = -0.4, wyaw = -0.1, tuck = -0.1, lead = { 0.72, 0.18, 1.45 }, rear = { 0.78, 0.3, 2.05 }, weave = 0, roll = 0,
		leadT = { -0.42, 0.5, -1.5 }, rearT = { 0.38, 0.98, -0.8 } },
	Swarmer = { depth = 0.38, bounce = 0.65, freq = 6.2, stagger = 0.82, width = 0.1, yawL = -0.3, yawR = -0.6, heel = 0.1,
		hip = -0.18, wyaw = -0.04, tuck = -0.28, lead = { 1.18, 0.4, 2.3 }, rear = { 1.12, 0.4, 2.32 }, weave = 0.2, roll = 0,
		leadT = { -0.28, 1.08, -0.95 }, rearT = { 0.3, 1.08, -0.85 } },
	Slugger = { depth = 0.29, bounce = 0.32, freq = 5.2, stagger = 1.05, width = 0.14, yawL = -0.25, yawR = -0.8, heel = 0.02,
		hip = -0.3, wyaw = -0.06, tuck = -0.2, lead = { 0.88, 0.32, 1.85 }, rear = { 0.82, 0.32, 2.0 }, weave = 0, roll = 0,
		leadT = { -0.36, 0.86, -1.3 }, rearT = { 0.42, 0.92, -0.8 } },
	CounterPuncher = { depth = 0.24, bounce = 0.8, freq = 6.6, stagger = 1.0, width = 0.05, yawL = -0.25, yawR = -0.8, heel = 0.12,
		hip = -0.46, wyaw = -0.12, tuck = -0.2, lead = { 0.42, 0.62, 1.55 }, rear = { 1.25, 0.38, 2.32 }, weave = 0, roll = 1,
		leadT = { -0.15, 0.1, -1.0 }, rearT = { 0.3, 1.02, -0.76 } },
}

local function num(v, default)
	return type(v) == "number" and v or default
end

local function fightStance(p, rig, t, dt)
	local a = rig.a
	local st = STYLE[a.Style] or STYLE.BoxerPuncher
	local amp = ampOf(rig)
	local stam = clamp(num(a.Stam, 1), 0, 1)
	local tired = 1 - stam
	local root = rig.root
	local lv = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
	local moving = clamp(sqrt(lv.X * lv.X + lv.Z * lv.Z) / 8, 0, 1)
	-- the bounce: slower, lower and flatter-footed when tired or heavy
	rig.bouncePhase += dt * st.freq * (0.78 + 0.22 * stam) * (0.85 + 0.15 * amp)
	local b = sin(rig.bouncePhase) * 0.055 * st.bounce * amp * (0.4 + 0.6 * stam) * (1 - 0.5 * moving)
	local depth = st.depth + b + 0.08 * tired
	-- bob and weave (swarmer) / Philly-shell shoulder roll (counter puncher)
	local wv = st.weave * amp * (0.5 + 0.5 * stam)
	local wx = wv * sin(t * 2.6 + rig.phase)
	local wdip = wv * 0.45 * abs(cos(t * 2.6 + rig.phase))
	local sroll = st.roll * 0.07 * sin(t * 1.4 + rig.phase)
	-- breathing: faster and deeper as the tank empties, shoulders heave
	rig.breathPhase += dt * (0.3 + 0.55 * tired)
	local br = K.breath(rig.breathPhase) * (0.018 + 0.05 * tired)
	rig.breath = tired
	-- hips bladed, leaning into the direction of travel
	p.Root = CF(wx, -(depth + wdip), 0) * A(lv.Z * 0.012 - 0.02, st.hip, -lv.X * 0.01 - wx * 0.3)
	p.W = A(-0.04 + br, st.wyaw + sroll * 0.5, wx * 0.35 + sroll)
	p.Neck = A(st.tuck - br * 0.5, -(st.hip + st.wyaw) * 0.85, -wx * 0.25 - sroll)
	-- the guard sags as the arms get heavy
	local sag = 0.35 * tired
	local Ld, Rr = st.lead, st.rear
	p.LS = A(Ld[1] - sag + br * 0.4, 0, Ld[2] + sroll)
	p.LE = A(Ld[3] - 0.25 * tired, 0, 0)
	p.RS = A(Rr[1] - sag + br * 0.4, 0, -Rr[2] + sroll * 0.5)
	p.RE = A(Rr[3] - 0.2 * tired, 0, 0)
	p.LW = A(0, 0.22, 0)
	p.RW = A(0, -0.22, 0)
	-- near rigs: the gloves go exactly where this style keeps them, whatever the body proportions;
	-- they sink and drift forward as the arms tire, rise and fall with the breath
	local sinkY, sinkZ = 0.45 * tired - br * 0.4, 0.2 * tired
	local lt, rt = st.leadT, st.rearT
	rig.guardL = lt
	rig.guardR = rt
	rig.guardSink = sinkY
	guardArm(rig, p, "L", lt[1], lt[2] - sinkY, lt[3] + sinkZ, 1)
	guardArm(rig, p, "R", rt[1] + sroll * 0.5, rt[2] - sinkY, rt[3] + sinkZ, 1)
	local up = max(0, b) * 2
	plant(rig, st.stagger, st.width, st.yawL, st.yawR, st.heel * 0.6 + up, st.heel * 1.5 + up)
	rig.stepDist = 0.3 -- boxers reset their feet constantly
	rig.liftK = 0.6 -- and keep them close to the canvas
	-- a fighter's muscles never fully switch off in the stance
	flex(rig, "forearms", 0.15)
	flex(rig, "frontDelt", 0.12)
	flex(rig, "abs", 0.12)
	flex(rig, "calves", 0.1 + up)
	return st
end

-- Daze 1: dazed (knee dips, lagging guard, head shakes); 2: rubber legs (buckles, drift, arms half
-- down); 3: out on his feet (drunken sway, arms dangling)
local function dazeOverlay(p, rig, t, dt, daze, conc)
	if daze <= 0 and conc < 0.3 then
		return
	end
	local d = clamp(daze + conc * 0.6, 0, 3.5)
	local sw = sin(t * 1.7 + rig.phase)
	p.Root = CF(0.08 * d * sw, -0.05 * d * abs(sin(t * 3.1)), 0) * p.Root * A(0.02 * d * sin(t * 0.9), 0, 0.03 * d * sin(t * 1.3 + 1))
	p.Neck = p.Neck * A(-0.06 * d, 0, 0.07 * d * sin(t * 1.25 + 2))
	local drop = clamp((d - 0.5) * 0.28, 0, 0.9)
	p.LS = p.LS * A(-drop, 0, 0)
	p.RS = p.RS * A(-drop, 0, 0)
	p.LE = p.LE * A(-drop * 0.9, 0, 0)
	p.RE = p.RE * A(-drop * 0.9, 0, 0)
	p.rate = 9 - 1.5 * min(daze, 3) -- the guard follows late
	-- head shake (trying to clear it) every few seconds
	if t >= (rig.nextShake or 0) then
		rig.nextShake = t + rig.rng:NextNumber(2.2, 4.2)
		rig.shakeT = t
	end
	local se = t - (rig.shakeT or -10)
	if se < 0.5 and daze <= 2 then
		p.Neck = p.Neck * A(0, 0.22 * sin(se * 30) * (1 - se / 0.5), 0)
	end
	-- rubber legs: random knee buckles that the springs carry
	if daze >= 2 and t >= (rig.nextBuckle or 0) then
		rig.nextBuckle = t + rig.rng:NextNumber(0.6, 1.5) / (daze - 1)
		local s = rig.rng:NextNumber() < 0.5 and -1 or 1
		kick(rig, -0.4, 0, 0.5 * s, -0.3, 0, 0.9 * s, 0, 0.6 * s, 1.0 + 0.4 * daze, 0)
	end
	if daze >= 3 then
		-- out on his feet: arms hang, the body sways from the ankles
		p.LS = p.LS:Lerp(A(0.25, 0, 0.12), 0.7)
		p.RS = p.RS:Lerp(A(0.2, 0, -0.12), 0.7)
		p.LE = p.LE:Lerp(A(0.6, 0, 0), 0.7)
		p.RE = p.RE:Lerp(A(0.5, 0, 0), 0.7)
		p.W = p.W * A(0.1 * sin(t * 0.8), 0, 0.12 * sin(t * 0.9 + 0.5))
	end
	rig.stepDist = 0.22
	rig.stepTime = 1 + 0.25 * daze
end

------------------------------------------------------------------------
-- Knockdowns: falls by DownPose (Config.KO.falls), the count, get-ups
------------------------------------------------------------------------
-- settled pose on the canvas
local function downSettled(p, rig, fall, t, ko)
	local g = rig.geo
	local fh = g.ok and g.floorH or 3
	local l2 = g.ok and g.L.l2 or 1.1
	for _, k in ipairs(KEYS) do
		p[k] = I
	end
	local breathe = ko and 0.01 or 0.04
	local bt = sin(t * (ko and 1.2 or 3)) * breathe
	if fall == "face" then
		p.Root = CF(0, -(fh - 0.42), -0.9) * A(-1.5, 0.3, 0)
		p.W = A(-0.05 + bt * 0.5, 0, 0)
		p.Neck = A(0.25, 1.15, 0)
		p.LS = A(2.5, 0, -0.45)
		p.LE = A(0.6, 0, 0)
		p.RS = A(0.15, 0, 0.3)
		p.RE = A(0.2, 0, 0)
		p.LH = A(-0.05, 0, -0.15)
		p.LK = A(-0.9, 0, 0)
		p.RH = A(0, 0, 0.1)
		p.RK = A(-0.2, 0, 0)
		p.LA = A(-0.5, 0, 0)
		p.RA = A(-0.5, 0, 0)
	elseif fall == "side" then
		p.Root = CF(0.75, -(fh - 0.55), 0.1) * A(0.15, 0, -1.45)
		p.W = A(0.12 + bt, 0, 0)
		p.Neck = A(-0.15, 0, 0.35)
		p.RS = A(1.45, 0, 0.15)
		p.RE = A(0.5, 0, 0)
		p.LS = A(0.85, 0, 0.35)
		p.LE = A(1.25, 0, 0)
		p.LH = A(0.95, 0, 0)
		p.LK = A(-1.3, 0, 0)
		p.RH = A(0.6, 0, 0)
		p.RK = A(-1.05, 0, 0)
	elseif fall == "sit" then
		p.Root = CF(0, -(fh - 0.5), 0.35) * A(0.3, 0, 0)
		p.W = A(-0.25 + bt, 0, 0)
		p.Neck = A(-0.35, 0, 0.15)
		p.LS = A(-0.55, 0, -0.28)
		p.LE = A(0.15, 0, 0)
		p.RS = A(-0.5, 0, 0.28)
		p.RE = A(0.15, 0, 0)
		p.LH = A(1.2, 0, -0.12)
		p.LK = A(-0.5, 0, 0)
		p.RH = A(1.05, 0, 0.1)
		p.RK = A(-0.95, 0, 0)
	elseif fall == "knee" then
		-- flash knockdown: one knee, a glove on the canvas, head bowed
		p.Root = CF(0, -(fh - (l2 + 0.35)), 0.1) * A(-0.12, 0, 0)
		p.W = A(-0.2 + bt, 0, 0)
		p.Neck = A(-0.45, 0, 0)
		p.LS = A(0.75, 0, -0.05)
		p.LE = A(0.2, 0, 0)
		p.RS = A(0.9, 0, -0.2)
		p.RE = A(1.5, 0, 0)
		p.LH = A(1.6, 0, 0)
		p.LK = A(-1.6, 0, 0)
		p.LA = A(0.1, 0, 0)
		p.RH = A(0.05, 0, 0)
		p.RK = A(-1.55, 0, 0)
		p.RA = A(0.6, 0, 0)
	else -- back
		p.Root = CF(0, -(fh - 0.45), 0.9) * A(1.5, 0, 0)
		p.W = A(bt, 0, 0)
		p.Neck = A(0.15, 0, 0)
		p.LS = A(0.3, 0, -1.2)
		p.LE = A(0.4, 0, 0)
		p.RS = A(0.2, 0, 1.35)
		p.RE = A(0.3, 0, 0)
		p.LH = A(0.35, 0, -0.12)
		p.LK = A(-0.75, 0, 0)
		p.LA = A(0.3, 0, 0)
		p.RH = A(0.12, 0, 0.1)
		p.RK = A(-0.25, 0, 0)
	end
	if ko then
		-- out cold: limp, head lolled to one side, arms splayed wider
		p.Neck = p.Neck * A(0.1, 0.9 * rig.koTilt, 0.4 * rig.koTilt)
		p.LS = p.LS * A(0, 0, -0.2)
		p.RS = p.RS * A(0, 0, 0.2)
	end
end

-- the buckle: knees give, guard drops (first 0.2 s of a knockdown)
local function downBuckle(p, rig, fall)
	for _, k in ipairs(KEYS) do
		p[k] = I
	end
	local back = fall == "back" or fall == "sit"
	p.Root = CF(0, -0.55, back and 0.15 or -0.1) * A(back and 0.15 or -0.2, 0, fall == "side" and -0.2 or 0)
	p.W = A(back and 0.1 or -0.25, 0, 0)
	p.Neck = A(back and 0.5 or -0.3, 0, 0.2)
	p.LS = A(0.4, 0, -0.3)
	p.RS = A(0.35, 0, 0.3)
	p.LE = A(0.6, 0, 0)
	p.RE = A(0.5, 0, 0)
	legAngles(p, 0.55, 0.1, rig.geo.ok and rig.geo.legLen or 2.3)
end

-- beating the count: from 3 on, the head lifts and a glove plants; by 8 he is on a knee
local function countStir(p, rig, fall, count, t)
	local k = clamp((count - 2) / 5, 0, 1)
	if k <= 0 then
		return
	end
	if fall == "back" then
		p.Neck = p.Neck:Lerp(A(-0.55, 0, 0), k)
		p.Root = p.Root * A(-0.35 * k, 0, -0.5 * k)
		p.LS = p.LS:Lerp(A(0.6, 0, -0.45), k)
		p.LE = p.LE:Lerp(A(1.3, 0, 0), k)
		p.LH = p.LH:Lerp(A(0.9, 0, 0), k)
		p.LK = p.LK:Lerp(A(-1.6, 0, 0), k)
	elseif fall == "face" then
		p.Root = p.Root * A(0.4 * k, 0, 0)
		p.LS = p.LS:Lerp(A(1.4, 0, -0.25), k)
		p.LE = p.LE:Lerp(A(0.6, 0, 0), k)
		p.RS = p.RS:Lerp(A(1.4, 0, 0.25), k)
		p.RE = p.RE:Lerp(A(0.6, 0, 0), k)
		p.Neck = p.Neck:Lerp(A(0.35, 0.2, 0), k)
	else
		p.Neck = p.Neck:Lerp(A(-0.1, 0.15 * sin(t * 2), 0), k)
		p.W = p.W * A(0.15 * k, 0, 0)
	end
end

-- one knee down, a glove on the knee: the middle of every get-up
local function kneelPose(p, rig)
	downSettled(p, rig, "knee", 0, false)
	p.Neck = A(-0.15, 0, 0)
	p.LS = A(0.9, 0, 0.1)
	p.LE = A(1.1, 0, 0)
end

-- the full fight pose for a Guard value (unknown values fall back to the stance)
local function fightPose(p, rig, t, dt)
	local a = rig.a
	local guard = a.Guard or "stance"
	local daze = num(a.Daze, 0)
	local conc = num(a.Conc, 0)
	local el = t - rig.guardT
	rig.poseAct = "Sparring"
	if guard == "down" then
		local fall = a.DownPose or "back"
		local ko = a.Expr == "ko"
		p.rate = 30 -- quick, but the buckle still reads as motion, not a pop
		if el < 0.2 then
			downBuckle(p, rig, fall)
		else
			downBuckle(rig.kp, rig, fall)
			downSettled(rig.kp2, rig, fall, t, ko)
			local x = clamp((el - 0.18) / 0.42, 0, 1)
			x *= x -- gravity
			for _, k in ipairs(KEYS) do
				p[k] = rig.kp[k]:Lerp(rig.kp2[k], x)
			end
			-- canvas bounce
			if el > 0.6 and el < 1.0 then
				local u = (el - 0.6) / 0.4
				p.Root = CF(0, 0.07 * sin(u * PI) * (1 - u), 0) * p.Root
			end
			if not ko then
				countStir(p, rig, fall, num(a.Count, 0), t)
				if fall == "knee" and el < 2.5 then
					p.Neck = p.Neck * A(0, 0.25 * sin(el * 22) * max(0, 1 - (el - 0.6) / 1.2), 0)
				end
			end
		end
		rig.exprHint = ko and "ko" or nil
		return guard
	end
	if guard == "block" then
		fightStance(p, rig, t, dt)
		-- the shell: forearms over the face, chin down, knees bent
		p.Root = CF(0, -0.18, 0.05) * p.Root
		p.LS = A(1.85, 0, 0.5)
		p.LE = A(2.4, 0, 0)
		p.RS = A(1.85, 0, -0.5)
		p.RE = A(2.4, 0, 0)
		guardArm(rig, p, "L", -0.32, 1.32, -0.72, 1, 0.6)
		guardArm(rig, p, "R", 0.32, 1.32, -0.72, 1, 0.6)
		p.W = p.W * A(-0.12, 0, 0)
		p.Neck = p.Neck * A(-0.15, 0, 0)
		flex(rig, "forearms", 0.6)
		flex(rig, "abs", 0.5)
		flex(rig, "frontDelt", 0.4)
	elseif guard == "clinch" then
		fightStance(p, rig, t, dt)
		-- tie him up: arms over his, weight leaning on him, head on his shoulder, pummel jitter
		local j = sin(t * 6.5) * 0.08
		p.Root = CF(0, -0.15, -0.38) * p.Root * A(-0.12, 0, 0)
		p.W = A(-0.32, 0.12, 0.05)
		p.Neck = A(-0.2, 0.45, 0.15)
		p.LS = A(1.45 + j, 0, 0.35)
		p.LE = A(1.1, 0, 0)
		p.RS = A(1.45 - j, 0, -0.35)
		p.RE = A(1.0, 0, 0)
		flex(rig, "lats", 0.7)
		flex(rig, "biceps", 0.6)
		flex(rig, "forearms", 0.8)
		flex(rig, "neckSCM", 0.6)
		rig.exprHint = "effort"
	elseif guard == "hurt" then
		fightStance(p, rig, t, dt)
		-- covering up and sagging: knees dip, guard closes, head down
		local w = sin(t * 4)
		p.Root = CF(0.06 * w, -0.12 - 0.06 * abs(sin(t * 3)), 0.1) * p.Root
		p.LS = p.LS:Lerp(A(1.5, 0, 0.45), 0.6)
		p.LE = p.LE:Lerp(A(2.3, 0, 0), 0.6)
		p.RS = p.RS:Lerp(A(1.5, 0, -0.45), 0.6)
		p.RE = p.RE:Lerp(A(2.3, 0, 0), 0.6)
		guardArm(rig, p, "L", -0.3, 1.12, -0.78, 0.8, 0.4)
		guardArm(rig, p, "R", 0.3, 1.12, -0.78, 0.8, 0.4)
		p.Neck = p.Neck * A(-0.12, 0, 0.1 * sin(t * 4.5))
		dazeOverlay(p, rig, t, dt, max(daze, 1), conc)
	elseif guard == "walkout" then
		local root = rig.root
		local v = root.AssemblyLinearVelocity
		local speed = sqrt(v.X * v.X + v.Z * v.Z)
		if speed > 1.2 then
			return "walk", speed
		end
		-- waiting in the corner / at the steps: warm-up bounce, shoulder rolls, neck rolls
		fightStance(p, rig, t, dt)
		p.Root = CF(0, 0.06 * abs(sin(t * 4.5)), 0) * p.Root
		local sr = sin(t * 2.2)
		p.LS = A(0.55 + 0.25 * sr, 0, 0.2)
		p.RS = A(0.55 - 0.25 * sr, 0, -0.2)
		p.LE = A(1.6, 0, 0)
		p.RE = A(1.6, 0, 0)
		p.Neck = A(-0.05 + 0.15 * sin(t * 1.3), 0.35 * sin(t * 0.7), 0.2 * cos(t * 1.3))
	elseif guard == "rest" then
		-- between rounds in the corner: leaning back on the ropes, arms along them, chest heaving
		local stam = clamp(num(a.Stam, 1), 0, 1)
		stand(p, rig, t, dt, 1.5 + 2 * (1 - stam), 0.3)
		rig.breathPhase += dt * (0.3 + 0.4 * (1 - stam))
		local br = K.breath(rig.breathPhase) * (0.04 + 0.05 * (1 - stam))
		p.Root = CF(0, -0.12, 0.12) * A(0.1, 0, 0)
		p.W = A(0.08 + br, 0, 0)
		p.Neck = A(0.22 - br, 0.1 * sin(t * 0.3), 0)
		p.LS = A(0.3 + br, 0, -1.35)
		p.LE = A(0.35, 0, 0)
		p.RS = A(0.3 + br, 0, 1.35)
		p.RE = A(0.35, 0, 0)
		plant(rig, 0.1, 0.25, 0.25, -0.25, 0, 0)
		rig.breath = 1 - stam
	elseif guard == "win" then
		-- arms up, a little hop, then a flex for the crowd
		local cyc = (el % 6)
		stand(p, rig, t, dt, 1.5, 0)
		if cyc < 3.6 then
			local pump = abs(sin(t * 3.2))
			p.Root = CF(0, -0.08 + 0.1 * pump, 0)
			p.LS = A(2.9 - 0.2 * pump, 0, -0.3)
			p.RS = A(2.9 - 0.2 * pump, 0, 0.3)
			p.LE = A(0.25 + 0.3 * pump, 0, 0)
			p.RE = A(0.25 + 0.3 * pump, 0, 0)
			p.Neck = A(0.3, 0.3 * sin(t * 0.8), 0)
			p.W = A(0.12, 0, 0)
			rig.foot.L.heel, rig.foot.R.heel = 0.2 * pump, 0.2 * pump
		else
			p.LS = A(0, 0, -1.5)
			p.RS = A(0, 0, 1.5)
			p.LE = A(2.2, 0, 0)
			p.RE = A(2.2, 0, 0)
			-- twist the upper arms so the elbow flexion lifts the forearms (double biceps)
			p.LS = p.LS * A(0, 1.3, 0)
			p.RS = p.RS * A(0, -1.3, 0)
			p.Neck = A(0.15, 0, 0)
			flex(rig, "biceps", 1)
			flex(rig, "frontDelt", 0.6)
			flex(rig, "sideDelt", 0.8)
			flex(rig, "lats", 0.6)
		end
		rig.exprHint = "happy"
	elseif guard == "lose" then
		-- head down, hands on the hips, slow heavy breaths
		stand(p, rig, t, dt, 2, 0.4)
		p.Neck = A(-0.5, 0.15 * sin(t * 0.25), 0)
		p.W = A(-0.1, 0, 0)
		p.LS = A(-0.25, 0, -0.55)
		p.RS = A(-0.25, 0, 0.55)
		p.LE = A(1.6, 0, 0)
		p.RE = A(1.6, 0, 0)
		-- forearms turned in so the fists land on the hips
		p.LS = p.LS * A(0, -0.9, 0)
		p.RS = p.RS * A(0, 0.9, 0)
	else
		fightStance(p, rig, t, dt)
		if guard == "dazed" or daze > 0 or conc >= 0.3 then
			dazeOverlay(p, rig, t, dt, max(daze, guard == "dazed" and 1 or 0), conc)
		end
	end
	return guard
end

------------------------------------------------------------------------
-- Acts: punches as a kinetic chain, defence, reactions (Act / ActId, PredAct, AutoAct)
------------------------------------------------------------------------
-- hip = pelvis turn (+ = rear side forward), sho = shoulders past the hips, fwd / side = weight
-- transfer (studs; side + = to the right), dip = level change at impact (- rises), load = wind-up
-- dip, lean / roll = torso, pivot = foot that turns on its ball, sp / sr / el = punching shoulder
-- pitch, roll (+ = out), elbow, wr = fist corkscrew, ik = how much the fist is aimed at the target
local KIN = {
	-- turns are added to the bladed stance (pelvis ~-0.3, shoulders ~-0.38): a jab turns the lead
	-- shoulder in ~15 degrees, a cross squares up and past, hooks turn ~30 degrees either way
	jab = { hip = -0.06, sho = -0.2, fwd = 0.16, side = -0.03, dip = 0.04, load = 0.03, lean = -0.06, roll = 0.04,
		sp = 1.6, sr = -0.1, el = 0.05, wr = 1.2, ik = 0.85, straight = true },
	cross = { hip = 0.36, sho = 0.32, fwd = 0.28, side = -0.08, dip = 0.06, load = 0.06, lean = -0.1, roll = -0.08, pivot = "R",
		sp = 1.58, sr = -0.12, el = 0.05, wr = 1.2, ik = 0.85, straight = true },
	leadhook = { hip = -0.24, sho = -0.22, fwd = 0.04, side = 0.12, dip = 0.12, load = 0.08, lean = -0.04, roll = 0.12, pivot = "L",
		sp = 1.42, sr = 0.85, el = 1.62, wr = 0.2, ik = 0 },
	rearhook = { hip = 0.42, sho = 0.4, fwd = 0.08, side = -0.12, dip = 0.12, load = 0.08, lean = -0.04, roll = -0.12, pivot = "R",
		sp = 1.42, sr = 0.85, el = 1.62, wr = -0.2, ik = 0 },
	uppercut = { hip = 0.3, sho = 0.2, fwd = 0.1, side = -0.02, dip = -0.08, load = 0.3, lean = 0.06, roll = -0.06, pivot = "R",
		sp = 1.85, sr = -0.12, el = 1.45, wr = 0, ik = 0, rise = true },
	overhand = { hip = 0.42, sho = 0.35, fwd = 0.26, side = -0.04, dip = 0.15, load = 0.05, lean = -0.18, roll = -0.2, pivot = "R",
		sp = 2.15, sr = -0.4, el = 0.55, wr = 1.0, ik = 0.5, straight = true },
}

-- the fist's path in UpperTorso space (standard torso units; x = towards the centre line, y up,
-- z forward = negative): from the guard to the peak, bulging by `arc` (out, up, back) halfway;
-- pole = where the elbow points (out, up, back). Straights reach past full extension (the IK
-- clamps to the arm's length), hooks swing wide with the elbow at shoulder height, uppercuts
-- scoop from below, the overhand loops over the top.
local PEAK = {
	jab = { x = 0.28, y = 1.0, z = -2.6, by = 0.12, arc = { 0, 0.05, 0 }, pole = { 0.35, -1, 0.1 } },
	cross = { x = 0.72, y = 1.0, z = -2.6, by = 0.12, arc = { 0, 0.05, 0 }, pole = { 0.3, -1, 0.1 } },
	leadhook = { x = 0.1, y = 1.0, z = -0.9, by = 0.1, arc = { 0.5, 0.05, 0.25 }, pole = { 1, 0.25, 0.3 } },
	rearhook = { x = 0.1, y = 1.0, z = -0.9, by = 0.1, arc = { 0.5, 0.05, 0.25 }, pole = { 1, 0.25, 0.3 } },
	uppercut = { x = 0.15, y = 1.05, z = -0.85, by = 0.35, arc = { 0.05, -0.5, 0.1 }, pole = { 0.35, -1, 0.35 } },
	overhand = { x = 0.62, y = 1.18, z = -2.3, by = 0.3, arc = { 0.35, 0.5, 0.2 }, pole = { 0.9, 0.3, 0.6 } },
}
PEAK.hook = PEAK.rearhook

-- head-shot reaction impulses: head pitch / yaw / roll, torso pitch / yaw / roll, back, side, drop
-- (a lead hook lands on the defender's right: his head snaps to his left = + yaw)
local HIT = {
	jab = { 2.6, 0, 0, 0.8, 0, 0, 0.9, 0, 0 },
	cross = { 4.2, 0, 0.5, 1.3, 0, 0.2, 1.5, 0, 0.3 },
	leadhook = { 0.6, 6.4, 3.2, 0.3, 1.6, 1.0, 0.2, -1.0, 0.5 },
	rearhook = { 0.6, -6.6, -3.3, 0.3, -1.7, -1.0, 0.2, 1.0, 0.5 },
	uppercut = { 7.4, 0, 0.8, 2.0, 0, 0.3, 0.8, 0, -0.9 },
	overhand = { -3.0, -2.6, -3.6, -0.6, -0.8, -1.0, 0.5, 0.6, 1.3 },
}
HIT.hook = HIT.rearhook
-- which way the hair is flung (head space x right, z back) per punch
local HAIR_FLING = {
	jab = { 0, -1 }, cross = { 0.2, -1 }, leadhook = { 1, -0.2 }, rearhook = { -1, -0.2 }, hook = { -1, -0.2 },
	uppercut = { 0, -0.6 }, overhand = { -0.7, 0.4 },
}

local function reactHit(rig, kind, ptype, flag, sev)
	local model = rig.model
	local daze = num(rig.a.Daze, 0)
	sev = clamp(sev or 0.5, 0, 1.5)
	rig.hitT = os.clock()
	rig.hitSev = sev
	if kind == "hit" then
		local h = HIT[ptype] or HIT.cross
		local m = (0.45 + sev) * (flag == "counter" and 1.35 or (flag == "heavy" and 1.25 or 1)) * (1 + 0.2 * daze)
		local rs = rig.rng:NextNumber() < 0.5 and -1 or 1 -- straight shots tilt the head either way
		local roll = h[3] * ((ptype == "cross" or ptype == "uppercut" or ptype == "jab") and rs or 1)
		kick(rig, h[1] * m, h[2] * m, roll * m, h[4] * m, h[5] * m, h[6] * m * rs, h[7] * m, h[8] * m, h[9] * m, 0)
		if FaceFX then
			FaceFX.Hit(model, sev)
		end
		if HairFX then
			local f = HAIR_FLING[ptype] or HAIR_FLING.cross
			HairFX.Impulse(model, f[1], f[2], 0.5 + sev * 0.6)
		end
		if BodyFX then
			BodyFX.Jiggle(model, "chest", 0.2 + 0.3 * sev)
		end
	elseif kind == "hitbody" then
		-- body shots fold him: hunch, knees buckle, crunch towards the side that was hit; a hook to
		-- the right side is a liver shot (bigger, slower to recover)
		local side = flag == "L" and -1 or 1
		local liver = side == 1 and (ptype == "leadhook" or ptype == "hook" or ptype == "uppercut")
		local m = (0.45 + sev) * (liver and 1.45 or 1) * (1 + 0.15 * daze)
		kick(rig, -1.2 * m, 0.4 * side * m, 0, -3.2 * m, 0.5 * side * m, -2.0 * side * m, 0.5 * m, 0.3 * side * m, 1.7 * m, 0)
		if FaceFX then
			FaceFX.Hit(model, sev * 0.8 + (liver and 0.3 or 0))
		end
		if BodyFX then
			BodyFX.Jiggle(model, "core", 0.5 * m)
		end
		if HairFX then
			HairFX.Impulse(model, 0, -0.6, 0.3 + sev * 0.3)
		end
	elseif kind == "blockhit" then
		kick(rig, 0.8, 0, 0, 0.6, 0, 0, 1.5, 0, 0.2, 5)
		if FaceFX then
			FaceFX.Effort(model, 0.5, 0.3)
		end
		if BodyFX then
			BodyFX.Jiggle(model, "arms", 0.3)
		end
	end
end

onAct = function(rig, s, now, predicted)
	local k, f2, f3, f4, f5 = K.parseAct(s)
	if not k then
		return
	end
	-- the local fighter's punch already started on the key press: skip the server echo
	if not predicted and rig.predKind == k and now - rig.predT < 0.25 and (f2 == "" or f2 == rig.predHand) then
		rig.predKind = nil
		return
	end
	local act = { kind = k, start = now, f2 = f2, f3 = f3, dur = 0.4 }
	if PUNCHES[k] then
		act.hand = (f2 == "L" or f2 == "R") and f2 or PUNCH_HAND[k] or "R"
		act.zone = f3 == "body" and "body" or "head"
		act.windup = clamp(tonumber(f4) or 0.2, 0.08, 0.9)
		act.power = clamp(tonumber(f5) or 0.6, 0, 1.5)
		act.dur = act.windup * 2.05 + 0.045
		if predicted then
			rig.predKind, rig.predHand, rig.predT = k, act.hand, now
		end
		if FaceFX then
			FaceFX.Effort(rig.model, 0.35 + 0.3 * act.power, act.windup + 0.25)
		end
	elseif k == "hit" or k == "hitbody" or k == "blockhit" then
		reactHit(rig, k, f2, f3, tonumber(f4))
		act.sev = clamp(tonumber(f4) or 0.5, 0, 1.5)
		act.dur = 0.5
	elseif k == "parryhit" then
		act.dur = 0.25
	elseif k == "slip" then
		act.dur = 0.42
	elseif k == "roll" then
		act.dur = 0.55
	elseif k == "parry" then
		act.dur = 0.3
	elseif k == "pivot" then
		act.dur = 0.4
	elseif k == "step" then
		act.dur = 0.36
	elseif k == "jump" then
		act.dur = clamp(tonumber(f4) or 0.32, 0.15, 0.8)
	elseif k == "stumble" then
		act.sev = clamp(tonumber(f3) or 0.6, 0, 1.5)
		act.dur = clamp(tonumber(f4) or 0.7, 0.2, 2)
		kick(rig, 1.2 * act.sev, 0, 0, 0.8 * act.sev, 0, 0, 0, 0, 0.6 * act.sev, 0)
	elseif k == "getup" then
		act.fall = f2 ~= "" and f2 or "back"
		act.dur = clamp(tonumber(f4) or 0.9, 0.4, 3) + 0.45
	elseif k == "refcount" then
		act.n = tonumber(f2) or 1
		act.dur = 0.95
	elseif k == "waveoff" then
		act.dur = 1.8
	else
		return -- unknown acts are ignored safely
	end
	-- a combination: the new act cuts the last one short, so ease from where the body is
	local prev = rig.act
	if prev and now - prev.start < (prev.dur or 0.4) then
		rig.actBlendT = now
	end
	rig.act = act
end

local function punchAct(p, rig, act, el, near)
	local w = act.windup
	local hold = 0.045
	local rec = w * 1.05
	if el >= w + hold + rec then
		return false
	end
	local kind = act.kind
	local L = act.hand == "L"
	local kin = KIN[kind]
	if kind == "hook" or not kin then
		kin = L and KIN.leadhook or KIN.rearhook
	end
	local mirror = (kind == "uppercut" and L) and -1 or 1
	local u = el / w
	local anti, hipT, shoT, armT = 0, 1, 1, 1
	if el < w then
		-- 1) anticipation: load the hips the other way; 2) drive: legs and hips lead, shoulders
		-- follow, the fist comes last and ACCELERATES into the target (fastest at contact)
		anti = u < 0.35 and sin(PI * u / 0.35) or 0
		hipT = easeOut((u - 0.06) / 0.6)
		shoT = easeOut((u - 0.14) / 0.66)
		armT = clamp((u - 0.2) / 0.8, 0, 1) ^ 1.6
	elseif el >= w + hold then
		-- 3) recoil: the fist comes home first, the body unwinds after it
		local r = (el - w - hold) / rec
		armT = 1 - smooth(r / 0.85)
		shoT = 1 - smooth((r - 0.05) / 0.9)
		hipT = 1 - smooth((r - 0.12) / 0.88)
	else
		-- 2b) contact: the fist stops dead and drives through a touch
		armT = 1 + 0.05 * (1 - (el - w) / hold)
		if not act.impacted then
			act.impacted = true
			if BodyFX then
				BodyFX.Jiggle(rig.model, "arms", 0.15 + 0.2 * act.power)
			end
		end
	end
	local pw = 0.8 + 0.4 * clamp(act.power or 0.6, 0, 1.5)
	local body = act.zone == "body"
	local hip = kin.hip * mirror * pw
	local sho = kin.sho * mirror * pw
	local dip = kin.dip + (body and 0.26 or 0)
	local lean = kin.lean - (body and 0.14 or 0)
	p.Root = CF(kin.side * mirror * pw * hipT, -(dip * pw * hipT + kin.load * anti), -kin.fwd * pw * hipT)
		* p.Root * A(0, hip * hipT - 0.18 * kin.hip * mirror * anti, 0)
	p.W = p.W * A(lean * pw * shoT, sho * shoT - 0.12 * sho * anti, kin.roll * mirror * pw * shoT)
	-- eyes stay on the target: the neck undoes most of the turn, chin tucked behind the shoulder
	p.Neck = p.Neck * A(-0.1 * shoT, -(hip * hipT + sho * shoT) * 0.78, -kin.roll * mirror * 0.6 * shoT)
	local S, E, Wr = L and "LS" or "RS", L and "LE" or "RE", L and "LW" or "RW"
	local ac = clamp(armT, 0, 1)
	local pk = PEAK[kind] or PEAK.cross
	local guard = L and rig.guardL or rig.guardR
	local pathed = false
	if guard and armT > 0.001 then
		-- inward = towards the centre line; the guard is where the fist leaves from and returns to
		local inward = L and 1 or -1
		local gx, gy, gz = guard[1], guard[2] - (rig.guardSink or 0), guard[3]
		local px, py, pz = inward * pk.x, body and pk.by or pk.y, pk.z
		-- aim at the opponent (or sparring partner) when there is one in front
		local tgt = near and (body and rig.oppTorso or rig.oppHead)
		local g = rig.geo
		if tgt and tgt.Parent and g.ok and g.utScale then
			local ut = rig.root.CFrame * g.rootC0 * p.Root * g.rootC1inv * g.waistC0 * p.W * g.waistC1inv
			local sc = g.utScale
			local isBag = tgt == rig.bagPart
			local lp
			if isBag then
				-- a hanging bag (5 studs tall): land on its near surface, at the chin / rib height this
				-- punch would find on a man; the glove's padding sinks in, so the hand centre stops just
				-- outside the cover. The side facing this shoulder, so hooks meet the bag's flank.
				local arm = g[ARM_OF[act.hand][3]]
				local shW = ut:PointToWorldSpace(arm and arm.c0.Position or V3())
				local hY = ut:PointToWorldSpace(V3(0, (body and pk.by or pk.y) * sc.Y, 0)).Y
				local c = tgt.Position
				local dx, dz = shW.X - c.X, shW.Z - c.Z
				local dm = sqrt(dx * dx + dz * dz)
				local r = min(tgt.Size.Y, tgt.Size.Z) * 0.5 + 0.1
				if dm > r then
					lp = ut:PointToObjectSpace(V3(c.X + dx / dm * r, hY, c.Z + dz / dm * r))
				end
			else
				lp = ut:PointToObjectSpace(tgt.Position - V3(0, body and 0.3 or 0, 0))
			end
			if lp then
				lp = V3(lp.X / sc.X, lp.Y / sc.Y, lp.Z / sc.Z)
			end
			if lp and lp.Z < -0.8 and lp.Magnitude < 6 then
				if isBag then
					-- every punch type lands ON the surface point (no follow-through past it)
					px, py, pz = lerp(px, lp.X, 0.85), lerp(py, lp.Y, 0.85), lerp(pz, lp.Z, 0.85)
				else
					-- straights go through the target, hooks / uppercuts land on its near side
					local k = kin.straight and 1 or 0.55
					local aim = kin.ik > 0 and 0.85 or 0.5
					px = lerp(px, lp.X, aim)
					py = lerp(py, lp.Y, aim)
					pz = lerp(pz, kin.straight and lp.Z - 0.4 or max(lp.Z * k, pk.z * 1.15), aim)
				end
			end
		end
		-- the peak sits just past full extension from this shoulder, so the elbow straightens at
		-- contact and bends back over the whole recoil (no lock-out-then-snap)
		local arm = rig.geo[ARM_OF[act.hand][3]]
		local sc = rig.geo.utScale
		if arm and arm.ok and sc then
			local sh = arm.c0.Position
			local vx, vy, vz = px - sh.X / sc.X, py - sh.Y / sc.Y, pz - sh.Z / sc.Z
			local vm = sqrt(vx * vx + vy * vy + vz * vz)
			local reach = arm.dMax / max(0.2, sc.Y) * 1.1
			if vm > reach then
				local k = reach / vm
				px, py, pz = sh.X / sc.X + vx * k, sh.Y / sc.Y + vy * k, sh.Z / sc.Z + vz * k
			end
		end
		local u = armT
		local bulge = sin(PI * clamp(u, 0, 1))
		local arc = pk.arc
		local x = gx + (px - gx) * u - inward * arc[1] * bulge
		local y = gy + (py - gy) * u + arc[2] * bulge
		local z = gz + (pz - gz) * u + arc[3] * bulge
		-- launch / return: the elbow pole and the IK weight blend from the guard's, so leaving and
		-- re-entering the guard is continuous
		local kb = smooth(clamp(u * 3, 0, 1))
		-- the elbow rises into the punch over the whole drive (a hook's elbow comes up late)
		local kp = smooth(clamp(u / 0.85, 0, 1))
		local pole = pk.pole
		local zb = lerp(-0.1, pole[3], kp)
		pathed = guardArm(rig, p, act.hand, x, y, z, kb, -zb, lerp(0.2, pole[1], kp), lerp(-1, pole[2], kp))
	end
	if not pathed then
		-- far away / no guard to start from: authored joint angles
		local sp = kin.sp - (body and (kin.el > 1 and 0.3 or 0.45) or 0)
		p[S] = p[S]:Lerp(A(sp, 0, L and -kin.sr or kin.sr), armT)
		p[E] = p[E]:Lerp(A(kin.el, 0, 0), ac)
	end
	p[Wr] = p[Wr] * A(0, (L and 1 or -1) * kin.wr * ac, 0)
	-- the other glove stays home on the chin
	local oS, oE = L and "RS" or "LS", L and "RE" or "LE"
	local gk = max(shoT, ac) * 0.7
	local home = L and rig.guardR or rig.guardL
	local tucked = false
	if home then
		-- the chin is covered: the guard hand pulls in tight while the other one is out
		local sx = L and 1 or -1
		tucked = guardArm(rig, p, L and "R" or "L", sx * 0.3, 1.02 - (rig.guardSink or 0) * 0.5, -0.74, gk)
	end
	if not tucked then
		p[oS] = p[oS]:Lerp(A(1.2, 0, L and -0.42 or 0.42), gk)
		p[oE] = p[oE]:Lerp(A(2.35, 0, 0), gk)
	end
	-- pivot on the ball of the foot, the knee turns in with the hip
	local pv = kin.pivot
	if kind == "uppercut" then
		pv = L and "L" or "R"
	end
	if pv then
		local f = rig.foot[pv]
		local sgn = hip >= 0 and 1 or -1
		f.heel = max(f.heel, 0.5 * hipT)
		f.pivot += sgn * 0.6 * hipT
		f.knee += sgn * 0.25 * hipT
	end
	if kin.rise then
		rig.foot.L.heel = max(rig.foot.L.heel, 0.22 * hipT)
		rig.foot.R.heel = max(rig.foot.R.heel, 0.22 * hipT)
	end
	-- authored punches far away still aim roughly at the target
	if not pathed and near and kin.ik > 0 and ac > 0.05 then
		local tgt = body and rig.oppTorso or rig.oppHead
		if tgt and tgt.Parent then
			armIK(rig, p, L and "L" or "R", tgt.Position, kin.ik * ac * 0.85)
		end
	end
	-- muscles: the punching side fires, the core turns, the pivot calf pushes
	local side = L and -1 or 1
	local imp = ac * ac
	flex(rig, "frontDelt", imp, side)
	flex(rig, "sideDelt", imp * (kin.straight and 0.5 or 0.9), side)
	flex(rig, "triceps", imp * (kin.straight and 0.95 or 0.4), side)
	flex(rig, "biceps", imp * (kin.straight and 0.2 or 0.75), side)
	flex(rig, "pecs", imp * 0.7, side)
	flex(rig, "upperChest", imp * 0.6, side)
	flex(rig, "lats", imp * 0.55, side)
	flex(rig, "forearms", imp * 0.85, side)
	flex(rig, "serratus", imp * 0.5, side)
	flex(rig, "obliques", hipT * 0.65)
	flex(rig, "abs", hipT * 0.4)
	flex(rig, "glutes", hipT * 0.35)
	flex(rig, "quads", hipT * 0.3)
	if pv then
		flex(rig, "calves", hipT * 0.7, pv == "L" and -1 or 1)
	end
	act.armT = ac
	return true
end

-- the get-up: from the canvas to one knee, then up through a squat onto planted feet
local function getupAct(p, rig, act, el, t)
	local u = el / act.dur
	if u >= 1 then
		return false
	end
	p.override = true -- the base pose continues from here when the get-up ends
	if u < 0.55 then
		rig.plant = false -- on the canvas / one knee: the legs are keyed, not planted
		downSettled(rig.kp, rig, act.fall, t, false)
		kneelPose(rig.kp2, rig)
		local x = smooth(u / 0.4)
		for _, k in ipairs(KEYS) do
			p[k] = rig.kp[k]:Lerp(rig.kp2[k], x)
		end
		if u > 0.35 then
			-- push off the knee
			p.LS = p.LS:Lerp(A(0.75, 0, 0.15), (u - 0.35) / 0.2)
		end
	else
		local x = smooth((u - 0.55) / 0.45)
		local g = rig.geo
		local kneelDrop = g.ok and (g.floorH - (g.L.l2 + 0.35)) or 1.5
		local rise = lerp(kneelDrop * 0.85, 0.25, x)
		p.Root = CF(0, -rise, 0.1 * (1 - x)) * A(-0.35 * (1 - x), -0.25 * x, 0)
		p.W = A(-0.3 * (1 - x), 0, 0)
		p.Neck = A(-0.2 + 0.1 * x, 0, 0)
		p.LS = A(lerp(0.75, 0.9, x), 0, lerp(0.15, 0.25, x))
		p.LE = A(lerp(1.1, 1.75, x), 0, 0)
		p.RS = A(lerp(0.9, 0.75, x), 0, lerp(-0.2, -0.3, x))
		p.RE = A(lerp(1.5, 2.05, x), 0, 0)
		plant(rig, 0.9, 0.08, -0.2, -0.7, 0, 0.1)
		flex(rig, "quads", 0.9 * (1 - x))
		flex(rig, "glutes", 0.8 * (1 - x))
		rig.exprHint = "effort"
	end
	return true
end

-- applies a timed action on top of the pose; returns false once it is finished
local function applyAct(p, rig, act, t, near)
	local el = t - act.start
	local k = act.kind
	if PUNCHES[k] then
		return punchAct(p, rig, act, el, near)
	end
	if el >= act.dur then
		return false
	end
	local pulse = K.pulse(el, act.dur) or 0
	if k == "hit" or k == "hitbody" then
		-- the guard is knocked loose for a moment (the springs carry head and torso)
		local s = pulse * clamp(act.sev or 0.5, 0, 1.2)
		p.LS = p.LS * A(-0.35 * s, 0, -0.1 * s)
		p.RS = p.RS * A(-0.35 * s, 0, 0.1 * s)
		p.LE = p.LE * A(-0.3 * s, 0, 0)
		p.RE = p.RE * A(-0.3 * s, 0, 0)
		if k == "hitbody" then
			-- the elbow on the hit side clamps down over the ribs
			local L = act.f3 == "L"
			local S = L and "LS" or "RS"
			p[S] = p[S]:Lerp(A(0.55, 0, L and 0.35 or -0.35), pulse * 0.6)
			flex(rig, "abs", pulse)
			flex(rig, "obliques", pulse)
		end
		rig.exprHint = "pain"
	elseif k == "blockhit" then
		flex(rig, "forearms", pulse)
		flex(rig, "frontDelt", pulse * 0.6)
	elseif k == "slip" then
		local L = act.f2 == "L"
		local s = pulse
		-- head offline over the slip-side knee; the IK bends that knee, the feet stay put
		p.Root = CF((L and -0.32 or 0.32) * s, -0.2 * s, -0.05 * s) * p.Root * A(0, (L and 0.12 or -0.12) * s, 0)
		p.W = p.W * A(-0.08 * s, (L and 0.15 or -0.15) * s, (L and 0.4 or -0.4) * s)
		p.Neck = p.Neck * A(0, 0, (L and 0.12 or -0.12) * s)
		flex(rig, "obliques", s * 0.8)
	elseif k == "roll" then
		local x = el / act.dur
		local s = sin(PI * x)
		-- U under the punch: dip, shift across, come up on the other side
		p.Root = CF(-cos(PI * x) * 0.32 * s * 1.4, -0.55 * s, 0) * p.Root
		p.W = p.W * A(-0.32 * s, 0, cos(PI * x) * 0.45 * s)
		p.Neck = p.Neck * A(-0.15 * s, 0, 0)
		flex(rig, "quads", s * 0.7)
		flex(rig, "obliques", s * 0.7)
	elseif k == "parry" then
		local L = act.f2 == "L"
		local S, E = L and "LS" or "RS", L and "LE" or "RE"
		p[S] = p[S]:Lerp(A(1.5, 0, L and -0.55 or 0.55), pulse)
		p[E] = p[E]:Lerp(A(1.5, 0, 0), pulse)
		p.W = p.W * A(0, (L and -0.12 or 0.12) * pulse, 0)
		flex(rig, "forearms", pulse, L and -1 or 1)
	elseif k == "parryhit" then
		p.LS = p.LS:Lerp(A(1.45, 0, -0.7), pulse)
		p.W = p.W * A(0, -0.25 * pulse, 0)
	elseif k == "pivot" then
		local L = act.f2 == "L"
		p.W = p.W * A(0, (L and 0.5 or -0.5) * pulse, 0)
		p.Root = p.Root * A(0, (L and 0.3 or -0.3) * pulse, 0)
		-- turning on the lead foot: it spins on its ball while the rear foot swings round
		local f = rig.foot.L
		f.heel = max(f.heel, 0.4 * pulse)
		f.pivot += (L and 0.6 or -0.6) * pulse
		rig.foot.R.lift = 0.1 * pulse
	elseif k == "step" then
		-- trainee footwork (the root is anchored): lead foot steps, rear follows, hips ride over
		local dir = act.f2
		local fwd = dir == "F" and 1 or (dir == "B" and -1 or 0)
		local side = dir == "R" and 1 or (dir == "L" and -1 or 0)
		local x = el / act.dur
		-- the foot nearest the direction of travel moves first (never cross the feet)
		local leadS = (dir == "R" or dir == "B") and "R" or "L"
		local lead, trail = rig.foot[leadS], rig.foot[leadS == "L" and "R" or "L"]
		local e1 = sin(PI * clamp(x / 0.55, 0, 1))
		local e2 = sin(PI * clamp((x - 0.35) / 0.65, 0, 1))
		local sx = leadS == "L" and -1 or 1
		lead.free, trail.free = true, true
		lead.z -= fwd * 0.45 * e1
		lead.x += side * sx * 0.4 * e1
		lead.lift = 0.14 * e1
		trail.z -= fwd * 0.25 * e2
		trail.x -= side * sx * 0.2 * e2
		trail.lift = 0.08 * e2
		p.Root = CF(side * 0.3 * pulse, 0.03 * pulse, -fwd * 0.3 * pulse) * p.Root
		flex(rig, "calves", pulse)
	elseif k == "jump" then
		rig.foot.L.free, rig.foot.R.free = true, true
		rig.foot.L.lift, rig.foot.R.lift = 0.5 * pulse, 0.5 * pulse
		p.Root = CF(0, 0.5 * pulse, 0) * p.Root
		flex(rig, "calves", pulse)
		flex(rig, "quads", pulse * 0.6)
	elseif k == "stumble" then
		-- thrown off balance: torso lags, arms fling out, short choppy recovery steps
		local dir = act.f2
		local s = K.attackDecay(el, 0.08, act.dur) * clamp(act.sev or 0.6, 0.2, 1.3)
		local wob = sin(el * 9) * 0.06 * s
		if dir == "B" then
			p.Root = p.Root * A(0.22 * s, 0, wob)
			p.W = p.W * A(0.15 * s, 0, 0)
			p.LS = p.LS:Lerp(A(1.0, 0, -1.0), s)
			p.RS = p.RS:Lerp(A(1.0, 0, 1.0), s)
		else
			local sd = dir == "R" and 1 or -1
			p.Root = p.Root * A(wob, 0, -0.25 * s * sd)
			p.W = p.W * A(0, 0, -0.12 * s * sd)
			p[sd > 0 and "LS" or "RS"] = p[sd > 0 and "LS" or "RS"]:Lerp(A(1.4, 0, sd > 0 and -1.2 or 1.2), s)
		end
		p.LE = p.LE:Lerp(A(0.5, 0, 0), s)
		p.RE = p.RE:Lerp(A(0.5, 0, 0), s)
		p.Root = CF(0, -0.15 * s, 0) * p.Root
		rig.stepDist = 0.18
		rig.stepTime = 1.35
		rig.liftK = 0.5
		rig.exprHint = "pain"
	elseif k == "getup" then
		return getupAct(p, rig, act, el, t)
	elseif k == "refcount" then
		-- arm up, then chops down for the number, leaning towards the downed fighter
		local x = el / act.dur
		local up = x < 0.35 and smooth(x / 0.35) or 1 - smooth((x - 0.35) / 0.25)
		p.RS = A(lerp(1.15, 2.5, up), 0, 0.35 * up)
		p.RE = A(0.25, 0, 0)
		p.W = p.W * A(-0.22, 0, 0)
		p.Root = CF(0, -0.2, 0) * p.Root
		p.LS = A(0.55, 0, 0.3)
		p.LE = A(0.7, 0, 0)
		p.Neck = p.Neck * A(-0.2, 0, 0)
	elseif k == "waveoff" then
		-- it's over: arms crossing back and forth overhead
		local x = sin(el * 7.5)
		local e = min(1, el / 0.2) * (1 - smooth((el - act.dur + 0.3) / 0.3))
		p.LS = p.LS:Lerp(A(2.6, 0, -0.55 + 0.75 * x), e)
		p.RS = p.RS:Lerp(A(2.6, 0, 0.55 - 0.75 * x), e)
		p.LE = p.LE:Lerp(A(0.2, 0, 0), e)
		p.RE = p.RE:Lerp(A(0.2, 0, 0), e)
	end
	return true
end

------------------------------------------------------------------------
-- Training poses & gym loops.  POSE[name](p, rig, t, d, w, model, dt)
-- d = drive (0..1 rep position: 1 = contracted / top), w = cycle speed
------------------------------------------------------------------------
local POSE = {}

local function stanceTraining(p, rig, t, d, w, model, dt)
	fightStance(p, rig, t, dt)
	local eff = num(rig.a.Effort, 0)
	rig.breath = max(rig.breath, eff * 0.8)
	return p
end
POSE.guard = stanceTraining
POSE.heavybag = stanceTraining
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
		if BodyFX then
			BodyFX.Jiggle(model, "chest", 0.25)
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
		if BodyFX then
			BodyFX.Jiggle(model, "all", 0.6)
		end
		if HairFX then
			HairFX.Impulse(model, 0, -0.5, 0.6)
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

POSE.walk = function(p, rig, t, d, w, model, dt)
	rig.walkPhase = (rig.walkPhase or 0) + dt * 7 * w
	local x = rig.walkPhase
	local s, c = sin(x), cos(x)
	local out = 0.07 + 0.12 * bulkOf(rig)
	-- hips sway over the stance leg and rotate with the stride; shoulders counter-rotate
	p.Root = CF(0.04 * s, 0.05 * abs(c) - 0.04, 0) * A(-0.03, 0.08 * s, 0.03 * s)
	p.W = A(0.02, -0.13 * s, -0.02 * s)
	p.Neck = A(0, 0.05 * s, 0)
	p.RS = A(-0.38 * s, 0, out)
	p.RE = A(0.25 + 0.2 * max(0, -s), 0, 0)
	p.LS = A(0.38 * s, 0, -out)
	p.LE = A(0.25 + 0.2 * max(0, s), 0, 0)
	p.RH = A(0.45 * s, 0, 0)
	p.RK = A(-0.6 * max(0, -c), 0, 0)
	p.RA = A(0.2 * max(0, s) - 0.15 * max(0, -c), 0, 0)
	p.LH = A(-0.45 * s, 0, 0)
	p.LK = A(-0.6 * max(0, c), 0, 0)
	p.LA = A(0.2 * max(0, -s) - 0.15 * max(0, c), 0, 0)
	return p
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
	rig.lookW = 0.8
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
	local act = wr and (wr.act or wr.autoAct)
	if act and PUNCHES[act.kind] then
		local el = t - act.start - act.windup
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
	if kind == "shout" and FaceFX then
		FaceFX.Shout(rig.model, (dur or 1.2) * 0.85)
	end
end

local function gestureOverlay(p, rig, t)
	local g = rig.gesture
	if not g then
		return
	end
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
		local act = wr.act or wr.autoAct
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
	return p
end

------------------------------------------------------------------------
-- Who looks at whom (every ~0.5 s): opponents, athletes, the local player, LookAt
------------------------------------------------------------------------
local function isFighterRig(r)
	return r.isFighter
end
local function isAthleteRig(r)
	if r.isFighter or r.isTrainee then
		return true
	end
	local loop = r.a.Loop
	return r.isAmbient and (loop == "heavybag" or loop == "spar" or loop == "shadow" or loop == "rope" or loop == "curl")
end
local function isTraineeRig(r)
	return r.isTrainee
end

local function nearestRig(rig, pos, maxD, filter)
	local best, bd = nil, maxD
	for _, r in pairs(rigs) do
		if r ~= rig and r.root and r.root.Parent and filter(r) then
			local d = (r.root.Position - pos).Magnitude
			if d < bd then
				best, bd = r, d
			end
		end
	end
	return best, bd
end

-- the hanging bag in front of a bag worker: the local gym's station bag (GymVisuals builds it in
-- workspace.LocalGym.Visual_<Station>, segment "Bag" = the middle of the bag) or a members' bag
-- (MapBuilder: model tagged MemberBag, part "MemberBag"); flat distance from the root under 6 studs
local BAG_RANGE = 6
local function findBag(rig, pos)
	local function flat(part)
		local d = part.Position - pos
		return sqrt(d.X * d.X + d.Z * d.Z)
	end
	if rig.isTrainee then
		local st = rig.a.Station
		local lg = workspace:FindFirstChild("LocalGym")
		local vm = lg and lg:FindFirstChild("Visual_" .. (type(st) == "string" and st or "heavybag"))
		local bag = vm and vm:FindFirstChild("Bag", true)
		if bag and bag:IsA("BasePart") and flat(bag) < BAG_RANGE then
			return bag
		end
	end
	local best, bd = nil, BAG_RANGE
	for _, m in ipairs(CollectionService:GetTagged("MemberBag")) do
		local bp = m:FindFirstChild("MemberBag", true)
		if bp and bp:IsA("BasePart") then
			local d = flat(bp)
			if d < bd then
				best, bd = bp, d
			end
		end
	end
	return best
end

local WATCHERS = { coachwatch = true, ringside = true, cornerman = true, sitwatch = true, idle = true, mittidle = true, mitts = true }

local function chooseLook(rig, t)
	if t < rig.nextLook then
		return
	end
	rig.nextLook = t + 0.45 + rig.rng:NextNumber() * 0.35
	local a = rig.a
	local pos = rig.root.Position
	rig.lookPart, rig.lookA, rig.lookB, rig.watch = nil, nil, nil, nil
	if rig.bagPart then
		-- left the bag (re-found below while still on it)
		if rig.oppHead == rig.bagPart then
			rig.oppHead, rig.oppTorso = nil, nil
		end
		rig.bagPart = nil
	end
	if rig.isFighter then
		local o = nearestRig(rig, pos, 40, isFighterRig)
		rig.oppHead = o and o.model:FindFirstChild("Head") or nil
		rig.oppTorso = o and o.model:FindFirstChild("UpperTorso") or nil
		rig.lookPart = rig.oppHead
		rig.watch = o and o.model or nil
		return
	end
	local loop = a.Loop
	if rig.isReferee or loop == "referee" then
		-- the downed man, else the middle of the two fighters
		local f1, f2
		for _, r in pairs(rigs) do
			if r.isFighter and r.root and (r.root.Position - pos).Magnitude < 30 then
				if r.a.Guard == "down" then
					rig.lookPart = r.model:FindFirstChild("Head")
					return
				end
				if not f1 then
					f1 = r
				elseif not f2 then
					f2 = r
				end
			end
		end
		rig.lookA = f1 and f1.model:FindFirstChild("Head")
		rig.lookB = f2 and f2.model:FindFirstChild("Head")
		return
	end
	if loop == "spar" and not a.Pose then
		local partner = rig.partner
		if partner and partner.model.Parent then
			rig.lookPart = partner.model:FindFirstChild("Head")
			rig.oppHead = rig.lookPart
			rig.oppTorso = partner.model:FindFirstChild("UpperTorso")
			rig.watch = partner.model
		end
		return
	end
	-- bag work: the bag is the target the punches land on (punchAct), eyes on it
	if (rig.isTrainee and a.Pose == "heavybag") or (rig.isAmbient and not a.Pose and loop == "heavybag") then
		local bag = findBag(rig, pos)
		if bag then
			rig.bagPart, rig.oppHead, rig.oppTorso = bag, bag, bag
		end
		return
	end
	if rig.isTrainee or rig.isPreview then
		return -- eyes on the work (FaceFX looks at the camera in the Creator)
	end
	local name = a.Pose or loop
	if WATCHERS[name] or rig.isAmbient then
		local o
		if name == "mitts" or name == "mittidle" or name == "coachwatch" then
			o = nearestRig(rig, pos, 30, isTraineeRig)
		end
		o = o or nearestRig(rig, pos, 45, isFighterRig) or nearestRig(rig, pos, 30, isAthleteRig)
		if o then
			rig.lookPart = o.model:FindFirstChild("Head")
			rig.watch = o.model
			return
		end
		-- people look at you when you walk past
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		if head and (head.Position - pos).Magnitude < 18 then
			rig.lookPart = head
		end
	end
end

local function updateLookPos(rig)
	local la = rig.a.LookAt
	if typeof(la) == "Vector3" then
		rig.lookPos = la
	elseif rig.lookPart and rig.lookPart.Parent then
		rig.lookPos = rig.lookPart.Position
	elseif rig.lookA and rig.lookA.Parent and rig.lookB and rig.lookB.Parent then
		rig.lookPos = (rig.lookA.Position + rig.lookB.Position) / 2
	else
		rig.lookPos = nil
	end
end

-- head and shoulders turn towards the look target (70% neck, 30% waist), never owl-like
local function applyLook(p, rig, dt)
	local ty, tp = 0, 0
	local wgt = rig.lookW
	if rig.lookPos and wgt > 0 then
		local lp = rig.root.CFrame:PointToObjectSpace(rig.lookPos)
		local yaw = atan2(-lp.X, -lp.Z)
		if abs(yaw) < 2.2 then
			ty = clamp(yaw, -1.25, 1.25) * wgt
			tp = clamp(atan2(lp.Y - 1.5, sqrt(lp.X * lp.X + lp.Z * lp.Z)), -0.5, 0.4) * wgt
		end
	end
	local k = 1 - exp(-dt * 4)
	rig.lookYaw += (ty - rig.lookYaw) * k
	rig.lookPitch += (tp - rig.lookPitch) * k
	if abs(rig.lookYaw) + abs(rig.lookPitch) > 1e-3 then
		p.W = p.W * A(0, rig.lookYaw * 0.3, 0)
		p.Neck = p.Neck * A(rig.lookPitch * 0.85, rig.lookYaw * 0.7, 0)
	end
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
		reactHit(rig, "blockhit")
		rig.autoAct = { kind = "blockhit", start = t, dur = 0.4 }
	elseif k == "hit" or k == "hitbody" then
		reactHit(rig, k, r.ptype, k == "hitbody" and r.side or "head", r.sev)
		rig.autoAct = { kind = k, start = t, dur = 0.5, sev = r.sev, f3 = r.side }
	else
		rig.autoAct = { kind = k, start = t, dur = k == "roll" and 0.55 or (k == "parry" and 0.3 or 0.42), f2 = r.dir }
	end
end

local function startAuto(rig, kind, hand, zone, windup, power, t)
	local act = { kind = kind, start = t, hand = hand, zone = zone, windup = windup, power = power,
		dur = windup * 2.05 + 0.045, f2 = hand, f3 = zone }
	local prev = rig.autoAct
	if prev and t - prev.start < (prev.dur or 0.4) then
		rig.actBlendT = t
	end
	rig.autoAct = act
	if rig.publish then
		-- client-local: GymVisuals swings the bag next to this athlete after the windup
		rig.autoId += 1
		rig.model:SetAttribute("AutoAct", string.format("%s|%s|%s|%.2f|%.2f", kind, hand, zone, windup, power))
		rig.model:SetAttribute("AutoActId", rig.autoId)
	end
	if rig.partner then
		scheduleReaction(rig, act, t)
	end
	if FaceFX then
		FaceFX.Effort(rig.model, 0.3 + 0.3 * power, windup + 0.2)
	end
end

local MOVES = { "slip", "roll", "step", "pivot" }
local DIRS = { "F", "B", "L", "R" }

local function ambientAct(rig, loop, t)
	if t < rig.nextAuto then
		return
	end
	local cur = rig.autoAct
	if cur and t - cur.start < (cur.windup or 0) + 0.05 then
		return
	end
	local r = rig.rng
	if rig.combo then
		rig.comboI += 1
		local ptype = rig.combo[rig.comboI]
		if ptype then
			local hand = PUNCH_HAND[ptype] or "R"
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

------------------------------------------------------------------------
-- Per-rig update
------------------------------------------------------------------------
local PUBLISH_POSE = { heavybag = "heavybag", guard = "shadow", speedbag = "speedbag" }

local function updateRig(rig, model, t, dt, lod)
	-- joints get replaced (head swap, rescale, respawn): re-resolve dead motors
	if t >= rig.nextResolve then
		rig.nextResolve = t + 1
		for _, k in ipairs(KEYS) do
			local j = rig.joints[k]
			if not j or not j.motor.Parent then
				resolveJoints(rig)
				rig.nextGeo = 0
				break
			end
		end
		rig.head = model:FindFirstChild("Head")
	end
	if t >= rig.nextGeo and lod >= 2 then
		rig.nextGeo = t + 2.5
		computeGeo(rig)
	end
	clearPose(rig)
	rig.lod = lod
	rig.dt = dt
	local p = rig.p
	local a = rig.a
	local pose, loop = a.Pose, a.Loop
	chooseLook(rig, t)
	updateLookPos(rig)
	local guard
	local ropeOn = false
	rig.publish = false
	if rig.isFighter then
		local speed
		guard, speed = fightPose(p, rig, t, dt)
		if guard == "walk" then
			-- the ring walk: robe, swagger, head nods
			POSE.walk(p, rig, t, 0, (speed or 7) / 7, model, dt)
			p.W = p.W * A(0, 0, 0.04 * sin(t * 3.5))
			p.Neck = p.Neck * A(0.06 * sin(t * 7), 0, 0)
		end
		rig.lookW = 0
	elseif (rig.isReferee or loop == "referee") and not pose then
		POSE.referee(p, rig, t, 0, 1, model, dt)
		local v = rig.root.AssemblyLinearVelocity
		rig.stepTime = sqrt(v.X * v.X + v.Z * v.Z) > 3 and 0.8 or 1
	else
		local name = pose or loop or (rig.isPreview and "preview") or "idle"
		local w = num(a.PoseSpeed, 1)
		local drive = a.PoseDrive
		if loop == "walk" or loop == "run" then
			local v = rig.root.AssemblyLinearVelocity
			local speed = sqrt(v.X * v.X + v.Z * v.Z)
			if speed > 1 and not pose then
				name = loop
				w = loop == "run" and speed / 14 or speed / 7
			elseif not pose then
				name = "idle"
			end
		end
		if type(drive) ~= "number" then
			-- automatic reps for other players and gym members
			local cyc = (t * 0.55 * w + rig.phase) % 1
			drive = cyc < 0.5 and smooth(cyc * 2) or smooth(2 - cyc * 2)
			if name == "curl" then
				rig.curlCycle = floor(t * 0.55 * w + rig.phase)
			end
		elseif name == "curl" then
			rig.curlCycle = num(a.RepCount, 0)
		end
		if name == "rope" then
			local spin = a.RopeSpin
			if type(spin) == "number" then
				rig.ropePhase = spin
			else
				rig.ropePhase = (rig.ropePhase or 0) + dt * 9 * w
			end
			rig.ropeFoot = a.RopeFoot
			ropeOn = true
		end
		local fn = POSE[name] or POSE.idle
		fn(p, rig, t, drive, w, model, dt)
		rig.poseAct = rig.poseAct or POSE_ACT[name]
		-- other players' bag / shadow / speed-bag work is re-synthesized here and published
		local autoLoop
		if rig.isTrainee and not rig.isLocal then
			autoLoop = PUBLISH_POSE[pose]
			rig.publish = autoLoop ~= nil
		elseif rig.isAmbient and not pose and (loop == "heavybag" or loop == "shadow" or loop == "spar") then
			autoLoop = loop
			rig.publish = loop ~= "shadow"
			if loop == "spar" then
				findPartner(rig, t)
			end
		end
		if autoLoop == "speedbag" then
			-- one strike per half circle of the fists
			local n = floor(t * 16 * w / PI)
			if n ~= rig.sbCount then
				rig.sbCount = n
				rig.autoId += 1
				model:SetAttribute("AutoAct", string.format("jab|%s|head|0.05|0.40", n % 2 == 0 and "L" or "R"))
				model:SetAttribute("AutoActId", rig.autoId)
			end
		elseif autoLoop then
			ambientAct(rig, autoLoop, t)
		end
		-- the strain of a hard set: a fine tremor in the working arms
		local eff = num(a.Effort, 0)
		if eff > 0.8 then
			local tr = (eff - 0.8) * 0.12
			p.RS = p.RS * A(tr * sin(t * 113), 0, tr * sin(t * 97))
			p.LS = p.LS * A(tr * sin(t * 107), 0, tr * sin(t * 89))
			p.RE = p.RE * A(tr * sin(t * 101), 0, 0)
			p.LE = p.LE * A(tr * sin(t * 103), 0, 0)
		end
	end
	-- base filter: poses glide, dazed guards lag
	local ab = p.snap and 1 or (1 - exp(-dt * (p.rate or 20)))
	local joints = rig.joints
	if rig.wasPlant and not rig.plant then
		-- leaving planted feet: the keyed legs start from where the IK left them
		for k in pairs(LEG_KEYS) do
			local j = joints[k]
			if j then
				j.base = j.cur
			end
		end
	end
	for _, k in ipairs(KEYS) do
		local j = joints[k]
		if j then
			j.base = j.base:Lerp(p[k], ab)
			p[k] = j.base
		end
	end
	-- overlays: reactions (springs), acts, gaze
	if stepSprings(rig, dt) then
		applySprings(rig, p)
	end
	local near = lod >= 3
	runPending(rig, t)
	if rig.autoAct and not applyAct(p, rig, rig.autoAct, t, near) then
		rig.autoAct = nil
	end
	if rig.act and (guard ~= "down" or rig.act.kind == "getup") then
		if not applyAct(p, rig, rig.act, t, near) then
			rig.act = nil
		end
	end
	if p.override then
		for _, k in ipairs(KEYS) do
			local j = joints[k]
			if j then
				j.base = p[k]
			end
		end
	end
	if not rig.isFighter then
		applyLook(p, rig, dt)
	end
	-- output filter (fast enough to keep the snap of a punch; softer for a moment when a new act
	-- cuts the last one short, e.g. combinations thrown before the recoil ends)
	local ao = 1 - exp(-dt * ((t - (rig.actBlendT or -10) < 0.12) and 14 or 40))
	local plantOn = rig.plant and rig.geo.ok and joints.Root ~= nil
	for _, k in ipairs(KEYS) do
		local j = joints[k]
		if j and not (plantOn and LEG_KEYS[k]) then
			j.cur = j.cur:Lerp(p[k], ao)
		end
	end
	if plantOn then
		if not rig.wasPlant then
			rig.plantT = t
		end
		if lod >= 2 then
			plantFeet(rig, p, joints.Root.cur, t, true)
		else
			legAngles(p, -joints.Root.cur.Position.Y, 0.15, rig.geo.legLen)
			rig.foot.L.pos, rig.foot.R.pos = nil, nil
		end
		-- blend into the IK legs when planting starts (get-up, leaving a seat)
		local bl = min(1, (t - (rig.plantT or 0)) / 0.25)
		local la = bl < 1 and (0.25 + 0.75 * bl) or 1
		for k in pairs(LEG_KEYS) do
			local j = joints[k]
			if j then
				j.cur = la < 1 and j.cur:Lerp(p[k], la) or p[k]
			end
		end
	else
		rig.foot.L.pos, rig.foot.R.pos = nil, nil
	end
	rig.wasPlant = plantOn
	for _, k in ipairs(KEYS) do
		local j = joints[k]
		if j and j.motor.Parent then
			j.motor.Transform = j.cur
		end
	end
	ropeVisual(rig, model, ropeOn, rig.ropePhase or 0)
end

------------------------------------------------------------------------
-- Registration & main loop
------------------------------------------------------------------------
for _, tag in ipairs(TAGS) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(m)
		task.defer(setup, m)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(m)
		task.defer(teardown, m)
	end)
	for _, m in ipairs(CollectionService:GetTagged(tag)) do
		setup(m)
	end
end

local cam = workspace.CurrentCamera
local warned = {}
local fxWarned = {}

local function fxStep(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not fxWarned[name] then
		fxWarned[name] = true
		warn("[Animator] " .. name .. " failed: " .. tostring(err))
	end
end

RunService.PreSimulation:Connect(function(dt)
	local t = os.clock()
	dt = min(dt, 0.1)
	cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local localChar = player.Character
	for model, rig in pairs(rigs) do
		if not model.Parent then
			if rig.conn then
				rig.conn:Disconnect()
			end
			rigs[model] = nil
			continue
		end
		local root = rig.root
		if not root or not root.Parent then
			rig.root = model:FindFirstChild("HumanoidRootPart")
			root = rig.root
			if not root then
				continue
			end
			rig.nextGeo = 0
		end
		rig.isLocal = model == localChar
		local pos = root.Position
		local dist = (pos - camPos).Magnitude
		if dist > CULL then
			continue
		end
		local onScreen = true
		if cam and dist > 8 then
			local _, vis = cam:WorldToViewportPoint(pos)
			onScreen = vis
		end
		-- far and off-screen rigs update less often (time steps stay correct: dt is per rig)
		local step = dist > FAR and 3 or (dist > MID and 2 or 1)
		if not onScreen then
			step = max(step, 4)
		end
		rig.frameSkip += 1
		if rig.frameSkip < step then
			continue
		end
		rig.frameSkip = 0
		local rdt = clamp(t - rig.lastT, 1 / 240, 0.25)
		rig.lastT = t
		local lod = (dist < NEAR and onScreen) and 3 or (dist < MID and 2 or 1)
		local ok, err = pcall(updateRig, rig, model, t, rdt, lod)
		if not ok and not warned[model] then
			warned[model] = true
			warn("[Animator] " .. model.Name .. ": " .. tostring(err))
		end
	end
	if FaceFX then
		fxStep("FaceFX", FaceFX.Update, dt, t, camPos, rigs, 3)
	end
	if BodyFX then
		fxStep("BodyFX", BodyFX.Update, dt, t, camPos, rigs)
	end
	if HairFX then
		fxStep("HairFX", HairFX.Update, dt, t, camPos, cam)
	end
end)

-- the local player's own character needs to be re-registered after respawning
player.CharacterAdded:Connect(function(char)
	for _, tag in ipairs(TAGS) do
		if CollectionService:HasTag(char, tag) then
			setup(char)
		end
	end
end)
