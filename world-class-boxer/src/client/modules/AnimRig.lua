-- AnimRig: rig geometry, inverse kinematics and the pose building blocks shared by the Animator
-- and its motion modules (AnimLoco, AnimFight, AnimDown, AnimGym).
--  * joints: R15 Motor6D or AnimationConstraint joints, resolved and re-resolved by name
--  * bind-pose geometry in HumanoidRootPart space (legs, feet contact points, arms, torso)
--  * two-bone leg IK with an exact foot roll model (the heel lifts about the ball, the toes lift
--    about the heel, so the contact point never slides), exact arm IK for any rest geometry
--  * pose table helpers (clear, plant the feet, muscle contraction hints, simple keyed legs)
--  * reaction springs (head / torso / hips / knees / arms) kicked by impulses
-- Everything works on the rig table the Animator keeps per character; nothing here allocates
-- tables per frame.
local K = require(script.Parent:WaitForChild("AnimKit"))

local AnimRig = {}

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local sin, cos, abs, max, min, sqrt, atan2 = math.sin, math.cos, math.abs, math.max, math.min, math.sqrt, math.atan2
local clamp = math.clamp

local JOINTS = {
	Root = { "LowerTorso", "Root" }, W = { "UpperTorso", "Waist" }, Neck = { "Head", "Neck" },
	RS = { "RightUpperArm", "RightShoulder" }, RE = { "RightLowerArm", "RightElbow" }, RW = { "RightHand", "RightWrist" },
	LS = { "LeftUpperArm", "LeftShoulder" }, LE = { "LeftLowerArm", "LeftElbow" }, LW = { "LeftHand", "LeftWrist" },
	RH = { "RightUpperLeg", "RightHip" }, RK = { "RightLowerLeg", "RightKnee" }, RA = { "RightFoot", "RightAnkle" },
	LH = { "LeftUpperLeg", "LeftHip" }, LK = { "LeftLowerLeg", "LeftKnee" }, LA = { "LeftFoot", "LeftAnkle" },
}
local KEYS = { "Root", "W", "Neck", "RS", "RE", "RW", "LS", "LE", "LW", "RH", "RK", "RA", "LH", "LK", "LA" }
-- the joint each joint hangs from (KEYS lists parents before children); "HRP" = the HumanoidRootPart
local PARENT = { Root = "HRP", W = "Root", Neck = "W", RS = "W", RE = "RS", RW = "RE", LS = "W", LE = "LS", LW = "LE",
	RH = "Root", RK = "RH", RA = "RK", LH = "Root", LK = "LH", LA = "LK" }
local LEG_KEYS = { RH = true, RK = true, RA = true, LH = true, LK = true, LA = true }
local SIDES = { "L", "R" }
local LEG_OF = { L = { "LH", "LK", "LA" }, R = { "RH", "RK", "RA" } }
local ARM_OF = { L = { "LS", "LE", "armL" }, R = { "RS", "RE", "armR" } }
AnimRig.JOINTS, AnimRig.KEYS, AnimRig.LEG_KEYS, AnimRig.SIDES = JOINTS, KEYS, LEG_KEYS, SIDES
AnimRig.LEG_OF, AnimRig.ARM_OF = LEG_OF, ARM_OF

-- the FX modules are optional; the Animator hands them over (nil-safe everywhere)
AnimRig.FX = {}
function AnimRig.setFX(fx)
	AnimRig.FX = fx or {}
end

local function num(v, default)
	return type(v) == "number" and v or default
end
AnimRig.num = num

------------------------------------------------------------------------
-- Joints
------------------------------------------------------------------------
-- limb part -> the joint at its far end (resting capsules for the ground solve) and the radius trim
local CAP_CHILD = { RS = "RE", LS = "LE", RH = "RK", LH = "LK", RK = "RA", LK = "LA" }
local CAP_PAD = { RS = -0.2, LS = -0.2 }
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
function AnimRig.resolveJoints(rig)
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

-- bind-pose geometry in HumanoidRootPart space: leg lengths, rest ankles, foot contact points,
-- ground height, arm geometry, torso size
function AnimRig.computeGeo(rig)
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
		leg.hip0 = (lt0 * leg.hipC0).Position
		leg.footRest = (ankleCF * ankleC1:Inverse()).Rotation
		local foot = ankleM.Part1
		local fs = foot and foot.Size or V3(0.7, 0.4, 1)
		local footCF = ankleCF * ankleC1:Inverse()
		local sole = footCF.Position.Y - fs.Y / 2
		lowest = min(lowest, sole)
		-- contact points of the foot (R15 foot: -Z = toes): the ball just behind the toes, the heel
		-- at the back edge; distances along the foot from the ankle joint
		local fwd = footCF.LookVector
		local ball = footCF:PointToWorldSpace(V3(0, -fs.Y / 2, -fs.Z * 0.28))
		local heel = footCF:PointToWorldSpace(V3(0, -fs.Y / 2, fs.Z * 0.45))
		local ank = ankleCF.Position
		leg.bz = max(0.12, (ball - ank):Dot(fwd))
		leg.hz = max(0.08, (ank - heel):Dot(fwd))
		leg.soleY = sole
		leg.ball = leg.bz -- legacy name
	end
	g.groundY = lowest
	for _, s in ipairs(SIDES) do
		local leg = g[s]
		leg.ah = max(0.1, leg.ankle0.Y - lowest) -- ankle height above the sole (flat foot)
	end
	g.rootY = rootC0.Position.Y
	g.floorH = g.rootY - g.groundY -- height of the root joint above the floor when standing
	g.legLen = (g.L.l1 + g.L.l2 + g.R.l1 + g.R.l2) / 2
	g.hipW = abs(g.L.hip0.X - g.R.hip0.X)
	-- torso size: guard targets are authored for a 2 x 1.6 x 1 UpperTorso and scale with the body
	local utPart = J.W.motor.Part1
	local us = utPart and utPart.Size or V3(2, 1.6, 1)
	g.utScale = V3(us.X / 2, us.Y / 1.6, us.Z)
	g.utSize = us
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
			-- the forearm itself (punches keep it off the boxer's own head): the wrist's share of the elbow
			-- to fist line and a radius for the arm drawn over the (fatter) R15 box
			arm.fw = f0.Magnitude > 1e-3 and clamp(f0.Magnitude / arm.b, 0.5, 1) or 0.85
			local fa = el.motor.Part1
			local fs = fa and fa.Size or V3(0.6, 1, 0.6)
			arm.rf = clamp(min(fs.X, fs.Z) * 0.24, 0.12, 0.25)
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
	-- the head's centre in UpperTorso space (punch targets / look direction)
	if J.Neck then
		g.neckC0 = jointC0(J.Neck.motor)
	end
	-- forward kinematics (AnimRig.fk): every joint's C0 / C1 and the size of the part it drives
	g.jc0, g.jc1i, g.sz = g.jc0 or {}, g.jc1i or {}, g.sz or {}
	for _, key in ipairs(KEYS) do
		local j = J[key]
		if j then
			g.jc0[key] = jointC0(j.motor)
			g.jc1i[key] = jointC1(j.motor):Inverse()
			local part = j.motor.Part1
			g.sz[key] = part and part.Size or V3(1, 1, 1)
		else
			g.jc0[key] = nil
		end
	end
	-- a glove is far bigger than the hand it sits on: the contact sphere of each fist
	local look = rig.model:FindFirstChild("BoxerLook")
	local hands = look and look:FindFirstChild("Hands")
	for _, s in ipairs(SIDES) do
		local glove = hands and hands:FindFirstChild("Glove" .. s)
		local hs = g.sz[s .. "W"] or V3(0.5, 0.3, 0.5)
		g["fistR" .. s] = (glove and glove:IsA("BasePart")) and glove.Size.Magnitude * 0.3 or max(hs.X, hs.Z) * 0.5
	end
	local hd = g.sz.Neck
	g.headR = hd and hd.Y * 0.5 or 0.6
	-- the limbs' resting capsules (part space): the joint into the part, the joint out of it, radius (the
	-- R15 arm boxes are fatter than the arms drawn over them: lowest()'s PAD)
	g.armCap = g.armCap or {}
	for k, child in pairs(CAP_CHILD) do
		local sz = g.sz[k]
		if g.jc1i[k] and g.jc0[child] and sz then
			g.armCap[k] = { g.jc1i[k]:Inverse().Position, g.jc0[child].Position, max(0.15, min(sz.X, sz.Z) * 0.5 + (CAP_PAD[k] or 0)) }
		else
			g.armCap[k] = nil
		end
	end
	g.ok = true
end

------------------------------------------------------------------------
-- Forward kinematics and the canvas: lying, kneeling and getting-up poses are authored as joint
-- angles; where the body actually rests comes from its real part sizes
------------------------------------------------------------------------
-- out[key] = the CFrame (HumanoidRootPart space) of the part joint `key` drives, for the pose p
function AnimRig.fk(rig, p, out)
	local g = rig.geo
	out.HRP = I
	for _, k in ipairs(KEYS) do
		local c0 = g.jc0[k]
		local par = out[PARENT[k]]
		if c0 and par then
			out[k] = par * c0 * p[k] * g.jc1i[k]
		else
			out[k] = nil
		end
	end
	return out
end

-- lowest point of a box (centre CFrame cf, size sz), optionally grown by `pad`
local function boxLow(cf, sz, pad)
	pad = pad or 0
	return cf.Y - (abs(cf.XVector.Y) * (sz.X * 0.5 + pad) + abs(cf.YVector.Y) * sz.Y * 0.5 + abs(cf.ZVector.Y) * (sz.Z * 0.5 + pad))
end
AnimRig.boxLow = boxLow

-- what rests on the canvas: trunk, head, legs and the upper arms (a man on his side lies on his
-- shoulder); forearms and fists are laid on it separately (liftArms)
local SUPPORT = { "Root", "W", "Neck", "RH", "RK", "RA", "LH", "LK", "LA", "RS", "LS" }
-- box padding per part: the trunk's muscles and shorts stand a little proud of the R15 boxes, the
-- R15 arm boxes are fatter than the arms drawn over them, and a foot box's corners (a heel on the
-- canvas when he lies on his back) stand off the rounded heel and toe drawn in it - on the athletic
-- rigs' long feet enough to prop the whole body
local PAD = { Root = 0.05, W = 0.05, RS = -0.14, LS = -0.14, RA = -0.1, LA = -0.1 }
-- the lowest point of the body (HRP space) for the pose already in `out` (AnimRig.fk)
function AnimRig.lowest(rig, out, keys)
	local g = rig.geo
	local low, lowK = math.huge, nil
	for _, k in ipairs(keys or SUPPORT) do
		local cf = out[k]
		if cf then
			local y
			if k == "Neck" then
				-- the head is round: between its box and its sphere
				y = boxLow(cf, g.sz.Neck) * 0.6 + (cf.Y - g.headR) * 0.4
			elseif g.armCap and g.armCap[k] then
				-- a limb rests on its bone, joint to joint, not on its part box: the athletic rigs' arm and
				-- leg parts run well past their joints and would prop the body off the canvas
				local c = g.armCap[k]
				y = min(cf:PointToWorldSpace(c[1]).Y, cf:PointToWorldSpace(c[2]).Y) - c[3]
			else
				y = boxLow(cf, g.sz[k], PAD[k])
			end
			if y < low then
				low, lowK = y, k
			end
		end
	end
	return low, lowK
end

-- the last word for a body on the canvas (after the filters and the spring overlays): if any of it
-- would sink below the floor, lift it (never lowers). `t` holds the final Transforms by key.
function AnimRig.floorClamp(rig, t, out)
	local g = rig.geo
	if not (g.ok and g.jc0 and g.jc0.Root) then
		return
	end
	AnimRig.fk(rig, t, out)
	local dy = g.groundY - AnimRig.lowest(rig, out)
	if dy > 1e-3 then
		t.Root = CF(0, dy, 0) * t.Root
	end
end

-- puts the body ON the canvas: shifts p.Root so the lowest point of the trunk / head / legs rests
-- `clear` studs above the floor (falls, lying poses, kneeling, the get-up). Returns the shift.
function AnimRig.groundSolve(rig, p, out, clear)
	local g = rig.geo
	if not (g.ok and g.jc0 and g.jc0.Root) then
		return 0
	end
	AnimRig.fk(rig, p, out)
	local dy = (g.groundY + (clear or 0.03)) - AnimRig.lowest(rig, out)
	if abs(dy) > 1e-4 then
		p.Root = CF(0, dy, 0) * p.Root
		-- (every part moves with the root: shift the solved frames too instead of solving again)
		local sh = CF(0, dy, 0)
		for _, k in ipairs(KEYS) do
			local cf = out[k]
			if cf then
				out[k] = sh * cf
			end
		end
	end
	return dy
end

-- an arm that would go through the canvas is lifted at the shoulder until the fist / elbow rests on
-- it (lying, falling, getting up). Needs `out` from AnimRig.fk / groundSolve for this pose.
local function armChain(rig, p, out, s)
	local g = rig.geo
	local kS, kE, kW = s .. "S", s .. "E", s .. "W"
	if not (out.W and g.jc0[kS] and g.jc0[kE] and g.jc0[kW]) then
		return false
	end
	out[kS] = out.W * g.jc0[kS] * p[kS] * g.jc1i[kS]
	out[kE] = out[kS] * g.jc0[kE] * p[kE] * g.jc1i[kE]
	out[kW] = out[kE] * g.jc0[kW] * p[kW] * g.jc1i[kW]
	return true
end
function AnimRig.liftArms(rig, p, out, clear)
	local g = rig.geo
	if not (g.ok and g.jc0) then
		return
	end
	local floorY = g.groundY + (clear or 0.04)
	for _, s in ipairs(SIDES) do
		local kS, kE, kW = s .. "S", s .. "E", s .. "W"
		for _ = 1, 2 do
			if not armChain(rig, p, out, s) then
				break
			end
			local pivotCF = out.W * g.jc0[kS]
			local piv = pivotCF.Position
			-- the two points that touch first: the fist (glove sphere) and the elbow
			local hand, r = out[kW].Position, g["fistR" .. s] or 0.4
			local elbow = (out[kE] * CF(0, (g.sz[kE] or V3(1, 1, 1)).Y * 0.5, 0)).Position
			local needH = floorY + r - hand.Y
			local needE = floorY + 0.28 - elbow.Y
			local pt, need = hand, needH
			if needE > needH then
				pt, need = elbow, needE
			end
			if need <= 0.002 then
				break
			end
			local v = pt - piv
			local L = v.Magnitude
			if L < 1e-3 then
				break
			end
			local h = V3(v.X, 0, v.Z)
			if h.Magnitude < 1e-3 then
				-- hanging straight down: swing it out to the side
				h = out.W.RightVector * (s == "L" and -1 or 1)
			end
			h = h.Unit
			local e = math.asin(clamp(v.Y / L, -1, 1))
			-- (from a shoulder too close to the canvas the arm cannot clear it: it lies flat out)
			local want = math.asin(clamp((v.Y + need) / L, -1, 0.95))
			local R = CFrame.fromAxisAngle(h:Cross(Vector3.yAxis), want - e)
			local pr = pivotCF.Rotation
			p[kS] = (pr:Inverse() * R * pr) * p[kS]
		end
	end
end

------------------------------------------------------------------------
-- Pose table
------------------------------------------------------------------------
-- reset the per-frame pose table, foot spec, muscle contraction and face hints (no allocation)
function AnimRig.clearPose(rig)
	local p = rig.p
	for _, k in ipairs(KEYS) do
		p[k] = I
	end
	p.snap = false
	p.rate = nil
	p.override = false
	rig.plant = false
	rig.stepDist, rig.stepTime, rig.liftK, rig.strideK, rig.bobK = 0.45, 1, 1, 1, 1
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		f.x, f.z, f.yaw, f.heel, f.lift, f.knee, f.pivot, f.free = 0, 0, 0, 0, 0, 0, 0, false
		f.ox, f.oz = 0, 0
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
	rig.gaitKind = nil
	rig.armSwing = 0
	-- (a pose may scale the walker's arm swing - gloves carried on a ring walk - or let him stride out
	-- further before he breaks into a jog; both per frame)
	rig.armScale, rig.walkMax = 1, nil
end

-- muscle contraction for BodyFX: side -1 left, 1 right, nil both
function AnimRig.flex(rig, id, v, side)
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
function AnimRig.flexAct(rig, actId, level, side)
	local BodyFX = AnimRig.FX.BodyFX
	local T = BodyFX and BodyFX.Targets and BodyFX.Targets[actId]
	if not T or level <= 0.001 then
		return
	end
	for id, w in pairs(T) do
		AnimRig.flex(rig, id, w * level, side)
	end
end

-- leg angles only (no Root change) for a hip drop of `depth`: the cheap far-LOD / non-planted solver
function AnimRig.legAngles(p, depth, stagger, len)
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
function AnimRig.legs(p, depth, stagger, rig)
	depth = max(0, depth)
	p.Root = p.Root * CF(0, -depth, 0)
	AnimRig.legAngles(p, depth, stagger, rig and rig.geo.ok and rig.geo.legLen or 2.3)
	return p
end

local HEEL_MAX = 0.42
-- plant both feet (the foot solver runs after the acts): stagger = lead (left) foot forward / rear
-- back (studs), width = extra stance width, yawL / yawR = toe directions (+ = turned left), heel lifts
function AnimRig.plant(rig, stagger, width, yawL, yawR, heelL, heelR)
	rig.plant = true
	local fL, fR = rig.foot.L, rig.foot.R
	stagger = stagger or 0
	fL.z, fR.z = -stagger * 0.5, stagger * 0.5
	fL.x, fR.x = width or 0, width or 0
	fL.yaw, fR.yaw = yawL or 0, yawR or 0
	-- (a stance stands on the balls of the feet at most: past HEEL_MAX the long athletic feet read as
	-- tiptoe; a punch's pivot lifts the heel further on its own)
	fL.heel, fR.heel = min(heelL or 0, HEEL_MAX), min(heelR or 0, HEEL_MAX)
end

function AnimRig.seated(p, lean)
	lean = lean or 0
	p.Root = A(-lean, 0, 0)
	p.RH = A(math.pi / 2 + lean, 0, 0.06)
	p.LH = A(math.pi / 2 + lean, 0, -0.06)
	p.RK = A(-math.pi / 2, 0, 0)
	p.LK = A(-math.pi / 2, 0, 0)
	return p
end

-- physique: big lats and arms hang further from the body; heavy frames move less
local FRAME_AMP = { Lean = 1.12, Athletic = 1, Muscular = 0.95, ["Power Build"] = 0.9, ["Heavyweight Build"] = 0.82 }
function AnimRig.bulkOf(rig)
	local b = rig.a.Bulk
	return type(b) == "number" and clamp(b, 0, 1) or 0.3
end
function AnimRig.ampOf(rig)
	return (FRAME_AMP[rig.a.Frame] or 1) * (1 - 0.12 * AnimRig.bulkOf(rig))
end

------------------------------------------------------------------------
-- Feet: exact roll model. P = the ground point under the ankle when the foot is flat, F = the
-- foot's forward (horizontal unit), th = pitch (+ heel up about the ball, - toes up about the heel).
-- Returns the ankle joint position that keeps the pivot point exactly where it is.
------------------------------------------------------------------------
local UP = Vector3.yAxis
function AnimRig.ankleOf(leg, P, F, th)
	local ah, bz, hz = leg.ah, leg.bz, leg.hz
	if th >= 0 then
		local s, c = sin(th), cos(th)
		return P + F * (bz - bz * c + ah * s) + UP * (bz * s + ah * c)
	end
	local s, c = sin(-th), cos(-th)
	return P + F * (-hz + hz * c - ah * s) + UP * (hz * s + ah * c)
end

-- two-bone leg IK: ankle target (HRP space) -> hip / knee / ankle Transforms; the foot keeps its
-- yaw (relative to the root) and pitch whatever the leg does; `knee` turns the knee in / out;
-- `soft` = the soft-reach band as a share of the leg (default 0.06: a fighter's knee never locks; a
-- walker's is narrow so the leg straightens at heel strike and in mid-stance)
function AnimRig.solveLeg(rig, p, s, rootT, targetHRP, footYaw, pitch, knee, soft)
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
	local sr = K.softReach(dm, full, full * (soft or 0.06))
	if sr < dm and dm > 1e-6 then
		d = d * (sr / dm)
	end
	local hp, roll, flexK = K.legIK(d.X, d.Y, d.Z, leg.l1, leg.l2)
	-- the knee tracks over the toes: twist the leg about the hip -> ankle line
	local look = hipFrame.LookVector
	local tw = clamp(K.wrap(footYaw - atan2(-look.X, -look.Z)) * 0.55 + (knee or 0), -0.8, 0.8)
	local hipT = A(0, 0, roll) * A(hp, 0, 0)
	if abs(tw) > 1e-3 and d.Magnitude > 1e-3 then
		hipT = CFrame.fromAxisAngle(d.Unit, tw) * hipT
	end
	local kneeT = A(-flexK, 0, 0)
	-- the foot stays at its planted yaw and pitch, whatever the leg does
	local chain = (hipFrame * hipT * leg.hipC1inv * leg.kneeC0 * kneeT * leg.kneeC1inv * leg.ankleC0).Rotation
	local want = A(0, footYaw, 0) * A(-pitch, 0, 0) * leg.footRest
	local keys = LEG_OF[s]
	p[keys[1]] = hipT
	p[keys[2]] = kneeT
	p[keys[3]] = chain:Inverse() * want * leg.ankleC1rot
	return flexK
end

-- how far below its neutral height the pelvis must sit so that a foot at targetHRP is reachable
-- with a softly bent knee (0 when it already is)
function AnimRig.dropFor(rig, s, rootT, targetHRP, slack)
	local g = rig.geo
	local leg = g[s]
	local hip = (g.rootC0 * rootT * g.rootC1inv * leg.hipC0).Position
	local reach = (leg.l1 + leg.l2) * (slack or 0.965)
	local dx, dz = targetHRP.X - hip.X, targetHRP.Z - hip.Z
	local h2 = dx * dx + dz * dz
	if h2 >= reach * reach then
		return reach -- out of reach whatever the height: drop a lot (caller clamps)
	end
	local need = sqrt(reach * reach - h2)
	local dy = hip.Y - targetHRP.Y
	return max(0, dy - need)
end

-- the hip -> ankle distance, as a share of the leg (l1 + l2), that leaves the knee bent by `knee`
-- (rad) once solveLeg's soft reach (band `soft`) has pulled it in: the pelvis height that gives a
-- walker's stance leg exactly the knee the gait wants (inside the band the soft curve is inverted,
-- so the IK lands on that knee instead of a few degrees more)
function AnimRig.slackFor(leg, knee, soft)
	local l1, l2 = leg.l1, leg.l2
	local d = sqrt(l1 * l1 + l2 * l2 + 2 * l1 * l2 * cos(knee)) / (l1 + l2)
	local band = 0.999 * soft
	local start = 0.999 - band
	if d <= start or band <= 0 then
		return d
	end
	-- softReach(x) = start + band * (1 - exp(-(x - start) / band)) = d  ->  x
	return start - band * math.log(1 - min(0.995, (d - start) / band))
end

-- signed dropFor: how far the pelvis must come down (> 0) or may rise (< 0) for the foot at
-- targetHRP to sit at exactly `slack` of the leg's length; a foot out of reach at any height asks
-- for `far` (the caller clamps)
function AnimRig.needFor(rig, s, rootT, targetHRP, slack, far)
	local g = rig.geo
	local leg = g[s]
	local hip = (g.rootC0 * rootT * g.rootC1inv * leg.hipC0).Position
	local reach = (leg.l1 + leg.l2) * slack
	local dx, dz = targetHRP.X - hip.X, targetHRP.Z - hip.Z
	local h2 = dx * dx + dz * dz
	if h2 >= reach * reach then
		return far
	end
	return hip.Y - targetHRP.Y - sqrt(reach * reach - h2)
end

------------------------------------------------------------------------
-- Arm IK: punches land where the target is, guards sit where the style wants them
------------------------------------------------------------------------
-- rotation that takes the orthonormal frame built from (a, b) onto the one built from (c, d)
-- (a -> c exactly, b -> d as closely as the angle between them allows)
local function frameOf(a, b)
	local x = a.Unit
	local y = b - x * b:Dot(x)
	if y.Magnitude < 1e-6 then
		y = abs(x.Y) < 0.9 and V3(0, 1, 0) or V3(1, 0, 0)
		y -= x * y:Dot(x)
	end
	y = y.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end
local function pairRotation(a, b, c, d)
	return frameOf(c, d) * frameOf(a, b):Inverse()
end
AnimRig.pairRotation = pairRotation

-- Exact arm IK for any rest geometry: the elbow is a hinge about its local X axis (positive =
-- flexion, as on R15), the hinge angle comes from the law of cosines on the real bone vectors
-- (the R15 shoulder joint sits off the arm's centre line, so the bones are not collinear), and the
-- shoulder rotation maps (arm line, hinge axis) onto (target line, pole-oriented hinge) - continuous
-- for any pole, including elbows above the shoulder. d = fist target, n = pole, both in the
-- shoulder joint's frame. Returns the shoulder and elbow Transforms.
function AnimRig.solveArm(arm, d, nx, ny, nz)
	local D = clamp(K.softReach(d.Magnitude, arm.dMax, arm.dMax * 0.04), arm.dMin, arm.dMax)
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

-- the elbow and the fist of that solve (shoulder joint frame): for a caller that looks before it places
-- the arm (a punch keeping its forearm off its own head)
function AnimRig.armPoints(arm, d, nx, ny, nz)
	local shT, elT = AnimRig.solveArm(arm, d, nx, ny, nz)
	local e = shT:VectorToWorldSpace(arm.u0)
	return e, shT:VectorToWorldSpace(arm.u0 + arm.elbowRot:VectorToWorldSpace(elT * arm.v0))
end

-- the UpperTorso's world CFrame for a pose (root, waist transforms of this frame)
function AnimRig.torsoCF(rig, rootT, waistT)
	local g = rig.geo
	return rig.root.CFrame * g.rootC0 * rootT * g.rootC1inv * g.waistC0 * waistT * g.waistC1inv
end

-- arm IK onto a world target (blended by w)
function AnimRig.armIK(rig, p, s, target, w)
	local g = rig.geo
	local keys = ARM_OF[s]
	local arm = g[keys[3]]
	if not (arm and arm.ok and g.ok) or w <= 0.01 then
		return
	end
	local ut = AnimRig.torsoCF(rig, p.Root, p.W)
	local d = (ut * arm.c0):PointToObjectSpace(target)
	if d.Magnitude > (arm.a + arm.b) * 1.6 then
		return -- out of range: keep the authored punch (a miss looks like a miss)
	end
	-- the elbow bends down and a little out (the natural line of a straight punch)
	local shT, elT = AnimRig.solveArm(arm, d, s == "L" and -0.35 or 0.35, -1, 0.1)
	p[keys[1]] = p[keys[1]]:Lerp(shT, w)
	p[keys[2]] = p[keys[2]]:Lerp(elT, w)
end

-- put a glove at (x, y, z) in UpperTorso space (authored for a standard torso, scaled to this one);
-- elbows tucked down. Returns false when the rig is too far / has no arm geometry (keep authored)
function AnimRig.guardArm(rig, p, s, x, y, z, w, elbowFwd, poleOut, poleUp)
	local g = rig.geo
	local keys = ARM_OF[s]
	local arm = g[keys[3]]
	if not (g.ok and arm and arm.ok and rig.lod >= 2) or w <= 0.01 then
		return false
	end
	local sc = g.utScale
	local d = arm.c0:PointToObjectSpace(V3(x * sc.X, y * sc.Y, z * sc.Z))
	local out = poleOut or 0.2
	local shT, elT = AnimRig.solveArm(arm, d, s == "L" and -out or out, poleUp or -1, -(elbowFwd or 0.1))
	if w >= 1 then
		p[keys[1]], p[keys[2]] = shT, elT
	else
		p[keys[1]] = p[keys[1]]:Lerp(shT, w)
		p[keys[2]] = p[keys[2]]:Lerp(elT, w)
	end
	return true
end

------------------------------------------------------------------------
-- Reaction springs: damped springs (overshoot = whiplash), kicked by impulses
-- 1 head pitch (+ face up), 2 head yaw (+ left), 3 head roll, 4 torso pitch (+ back), 5 torso yaw,
-- 6 torso roll, 7 hips back (studs, +Z), 8 hips sideways (+X), 9 knee drop (studs), 10 cover-up,
-- 11 left arm drop, 12 right arm drop, 13 left arm out, 14 right arm out (radians)
-- They are applied AFTER the pose filters (the Animator composes them onto the output), so a snap is
-- never low-passed; the head is a stiff, fast spring (a head snap is out and back in ~0.2 s), the
-- torso a slower one (the chest follows through)
------------------------------------------------------------------------
local NSPR = 14
AnimRig.NSPR = NSPR
local SPR_K = { 900, 800, 700, 110, 110, 110, 60, 60, 45, 80, 90, 90, 80, 80 }
local SPR_Z = { 0.32, 0.32, 0.36, 0.45, 0.45, 0.45, 0.75, 0.75, 0.55, 0.9, 0.5, 0.5, 0.45, 0.45 }
local SPR_MAX = { 1.0, 1.1, 0.8, 0.7, 0.6, 0.6, 1.2, 1.2, 0.9, 1.2, 1.3, 1.3, 1.2, 1.2 }
-- kick() takes head impulses in the units of the old, softer head spring (same displacement for the
-- same number); react() asks for real angular speeds and divides by these
local HEAD_GAIN = { math.sqrt(900 / 170), math.sqrt(800 / 150), math.sqrt(700 / 150) }
AnimRig.HEAD_GAIN = HEAD_GAIN

function AnimRig.stepSprings(rig, dt)
	local x, v = rig.sx, rig.sv
	local daze = rig.a.Daze
	local soft = 1 - 0.15 * (type(daze) == "number" and daze or 0) -- a hurt neck is a weak neck
	local active = false
	for i = 1, NSPR do
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

-- before the filters: the cover-up (a pose blend, it may glide)
function AnimRig.applySpringsPre(rig, p)
	local c = clamp(rig.sx[10], 0, 1)
	if c > 0.01 then
		p.LS = p.LS:Lerp(A(1.75, 0, 0.45), c)
		p.LE = p.LE:Lerp(A(2.35, 0, 0), c)
		p.RS = p.RS:Lerp(A(1.75, 0, -0.45), c)
		p.RE = p.RE:Lerp(A(2.35, 0, 0), c)
	end
end

-- after the filters: the hips / knee-drop translation onto the root (before the foot IK, so planted
-- legs absorb it), or nil
function AnimRig.springRoot(rig)
	local x = rig.sx
	if x[7] ~= 0 or x[8] ~= 0 or x[9] ~= 0 then
		return CF(x[8], -x[9], x[7])
	end
	return nil
end

-- after the filters: compose the snaps onto a joint's output Transform (Neck, W, LS, RS)
function AnimRig.springOut(rig, k, v)
	local x = rig.sx
	if k == "Neck" then
		if x[1] ~= 0 or x[2] ~= 0 or x[3] ~= 0 then
			return v * A(x[1], x[2], x[3])
		end
	elseif k == "W" then
		if x[4] ~= 0 or x[5] ~= 0 or x[6] ~= 0 then
			return v * A(x[4], x[5], x[6])
		end
	elseif k == "LS" then
		-- arms knocked loose: drop (pitch down) and fling out (roll away from the body)
		if x[11] ~= 0 or x[13] ~= 0 then
			return A(-x[11], 0, -x[13]) * v
		end
	elseif k == "RS" then
		if x[12] ~= 0 or x[14] ~= 0 then
			return A(-x[12], 0, x[14]) * v
		end
	end
	return v
end

-- all of it straight onto a pose (tools / previews that have no output stage)
function AnimRig.applySprings(rig, p)
	AnimRig.applySpringsPre(rig, p)
	local st = AnimRig.springRoot(rig)
	if st then
		p.Root = st * p.Root
	end
	for _, k in ipairs({ "Neck", "W", "LS", "RS" }) do
		p[k] = AnimRig.springOut(rig, k, p[k])
	end
end

-- impulses (rad/s or studs/s) on the channels listed above
function AnimRig.kick(rig, hp, hy, hr, tp, ty, tr, back, side, drop, cover, lDrop, rDrop, lOut, rOut)
	local v = rig.sv
	v[1] += (hp or 0) * HEAD_GAIN[1]
	v[2] += (hy or 0) * HEAD_GAIN[2]
	v[3] += (hr or 0) * HEAD_GAIN[3]
	v[4] += tp or 0
	v[5] += ty or 0
	v[6] += tr or 0
	v[7] += back or 0
	v[8] += side or 0
	v[9] += drop or 0
	v[10] += cover or 0
	v[11] += lDrop or 0
	v[12] += rDrop or 0
	v[13] += lOut or 0
	v[14] += rOut or 0
	-- a spring at rest needs a nudge to be integrated
	for i = 1, NSPR do
		if v[i] ~= 0 and rig.sx[i] == 0 then
			rig.sx[i] = 1e-4
		end
	end
end

return AnimRig
