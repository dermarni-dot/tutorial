-- AnimLoco: locomotion and feet for the procedural Animator.
--  * senses the root's real motion every frame (velocity / acceleration / turn rate from the root's
--    own position, so server-moved NPCs, PivotTo glides and replicated players all work; teleports
--    reset, server nudges glide; a start from a standstill at a low frame rate is real motion)
--  * outside the ring, a real walk / jog / run / sprint: human gait numbers scaled to the rig's leg
--    (same Froude number): cadence, stride and duty factor from the ground speed (the feet never
--    slide), the walk -> run switch with hysteresis, heel strike -> foot flat -> toe off, a stance
--    knee designed per phase (nearly straight at heel strike, the loading flex, locked again by
--    mid-stance; a runner lands softly bent and sinks to mid-stance) with the pelvis height following
--    the legs (the vertical bob, lowest in double support / at a runner's mid-stance, comes from
--    them), pelvis rotation and drop, shoulder counter-rotation, relaxed arms that hang from the
--    shoulders and swing opposite the legs (their swing is applied after the joint filters, so it
--    stays in step), lean from acceleration (not speed), a narrow track, ground rays under the feet
--    (ramps, stairs), toe-first backward steps, no crossed feet when strafing, quiet arms sideways,
--    and a personality per character (seed, body, style) so a crowd never walks in step
--  * boxing footwork inside the ring (step-drag shuffle where the
--    foot on the side of travel moves first and the other follows, a gallop at speed, the feet never
--    cross or touch), a short irregular stagger when dazed or stumbling
--  * planted feet: a foot on the ground is locked in the world (ground point + yaw); the heel lifts
--    about the ball and the toes about the heel with exact geometry (AnimRig.ankleOf), spins pivot
--    on the ball, so the contact point never slides; the pelvis sinks when a foot would be out of
--    reach, and a foot about to be out of reach steps instead of being dragged
--  * steps: scheduled by the gait phase while moving, triggered by error when standing (turning in
--    place, drift), or requested by the motion modules (step jab, catch steps of a stumble, a
--    style's restless feet) with a hold time, after which the foot returns by itself
--  * weight and momentum: lean into acceleration, settle (with a little overshoot) on stopping,
--    lean into turns
local K = require(script.Parent:WaitForChild("AnimKit"))
local R = require(script.Parent:WaitForChild("AnimRig"))

local AnimLoco = {}

local A = CFrame.Angles
local CF = CFrame.new
local V3 = Vector3.new
local PI = math.pi
local sin, cos, abs, max, min, exp, sqrt, atan2, floor = math.sin, math.cos, math.abs, math.max, math.min, math.exp, math.sqrt, math.atan2, math.floor
local clamp = math.clamp
local smooth, lerp = K.smooth, K.lerp
local SIDES = R.SIDES
local ZERO = Vector3.zero

-- speeds (studs/s)
local MOVE_ON, MOVE_OFF = 0.9, 0.45 -- start / stop the gait cycle (hysteresis)
-- closest the feet may come side by side in footwork (studs between the ankle lines)
local FOOT_GAP = 0.6
-- the most a planted fighting foot pitches up onto its ball (rad; a cross's pivot reaches about 0.6)
local FIGHT_PITCH_MAX = 0.68
-- the fastest a punch's pivot (rad/s) or heel lift (rad/s of foot pitch) may turn a planted ankle
local PIVOT_RATE, HEEL_RATE = 9, 8
-- a foot stays down at least this long before it lifts again (no one-frame touchdowns)
local MIN_STANCE = 0.08
-- walking / running: the pelvis never sinks more than WALK_DROP under its height to keep a planted foot
-- reachable, and never faster than DROP_RATE studs/s either way; a runner's foot that would need more
-- than TOE_OFF_DROP toes off early instead (a walker's only past 0.2)
local WALK_DROP, DROP_RATE, TOE_OFF_DROP = 0.38, 4, 0.1
-- walkers: the pelvis follows the stance leg's designed knee, so it may also rise (up to WALK_RAISE) over
-- the pose's own height (stand()'s settle, a stop); their IK's soft-reach band (a share of the leg) is
-- narrow, so a walking knee straightens; a trailing foot that would hold the pelvis more than
-- WALK_EXCESS under where the leading leg wants it toes off early instead (the leading leg carries the
-- body: no plunge into the double support); WALK_GAP = the closest two walking feet come side by side
-- (no scissoring when strafing)
local WALK_RAISE, WALK_SOFT, WALK_EXCESS, WALK_GAP, WALK_RELEASE, WALK_CATCH = 0.1, 0.006, 0.06, 0.32, 0.12, 22
-- real gait scaled to the rig: LREF = hip joint to sole of the reference 1.80 m boxer (studs); VH turns
-- studs/s into the m/s of a 0.9 m human leg at the same Froude number (so human numbers apply)
local LREF, VH = 3.06, 0.2793
-- the walk -> run switch and back (human-equivalent m/s; Froude ~0.5), with hysteresis
local RUN_ON, RUN_OFF = 2.1, 1.85
local RAD = PI / 180
-- how far ahead (s) a walker's pelvis aims: the lag of its drop spring (2 / its rate)
local PELVIS_LEAD = 2 / 28
-- a ground ray under a landing walker's foot: from STEP_UP above the root's floor down to STEP_DOWN under it
local STEP_UP, STEP_DOWN = 1.7, 2.2

-- the walk's personality by boxing style (the Style attribute: fighters, their ring walks): cadence,
-- arm swing, bounce, width of the track, pelvis sway, forward carriage (rad), elbow carry (rad)
local STYLE_GAIT = {
	OutBoxer = { cad = 1.04, swing = 1.08, bob = 1.25, width = 0.92, roll = 0.95, lean = 0, el = -0.04 },
	Slugger = { cad = 0.94, swing = 0.88, bob = 0.8, width = 1.2, roll = 1.25, lean = 0.025, el = 0.06 },
	Swarmer = { cad = 1.02, swing = 0.95, bob = 1.0, width = 1.05, roll = 1.0, lean = 0.04, el = 0.1 },
	CounterPuncher = { cad = 0.98, swing = 0.95, bob = 0.95, width = 1.0, roll = 1.08, lean = 0, el = 0 },
	BoxerPuncher = { cad = 1, swing = 1, bob = 1, width = 1, roll = 1, lean = 0.012, el = 0.03 },
}
local NO_STYLE = { cad = 1, swing = 1, bob = 1, width = 1, roll = 1, lean = 0, el = 0 }

function AnimLoco.newFoot()
	return {
		-- the pose's foot spec (cleared every frame by AnimRig.clearPose)
		x = 0, z = 0, yaw = 0, heel = 0, lift = 0, knee = 0, pivot = 0, free = false, ox = 0, oz = 0,
		-- world state
		P = nil, yawW = 0, swing = false, t0 = 0, dur = 0.2, fromP = nil, fromYaw = 0, liftH = 0.2,
		lastStep = -10, cycle = 0, want = false, cur = nil, curYaw = 0, curLift = 0, curPitch = 0, home = nil,
		heelS = 0, pivotS = 0, kneeS = 0, pitchS = 0, liftPitch = 0, spinT = -10, landT = -10,
		-- voluntary step request (body-relative offset held until vUntil)
		vox = 0, voz = 0, vUntil = -10, vNow = false, vDur = 0.2, vLift = 0.15,
		stepKind = nil,
		-- a walker's ground under the landing spot (ray) and the slope's pitch along the foot
		gY = nil, gRay = -10, slopeP = 0, landSlope = 0, excess = 0,
	}
end

-- a stable number per character (the model's name hashed with its seed): the walk's personality
local function gaitSeed(rig)
	local name = rig.model and rig.model.Name or ""
	local h = 5381
	for i = 1, #name do
		h = (h * 33 + string.byte(name, i)) % 1000003
	end
	return (h + (rig.seed or 0) * 7919) % 100003
end

function AnimLoco.init(rig)
	rig.foot = rig.foot or { L = AnimLoco.newFoot(), R = AnimLoco.newFoot() }
	rig.loco = {
		pos = nil, vel = ZERO, acc = ZERO, lv = ZERO, la = ZERO, speed = 0, yaw = 0, yawRate = 0,
		moving = false, moveT = 0, stopT = -10, phase = 0, T = 0.5, duty = 0.6, lead = "L",
		offL = 0, offR = 0.5, swL = 0.4, swR = 0.4,
		leanP = 0, leanPV = 0, leanR = 0, leanRV = 0, inP = 0, inPV = 0, drop = 0,
		gaitW = 0, armPhase = 0, stride = 0, run = 0, jumpOff = nil, jumpYaw = 0,
		turnL = 0, headP = 0, headPV = 0, headR = 0, headRV = 0,
		-- walking: run mode (hysteresis), human-equivalent speed, forward-ness (-1 back .. 1 forward),
		-- backward blend, vertical speed, the arms' swing weight, the stop's knee dip
		runMode = false, vh = 0, fwd = 1, back = 0, side = 0, vy = 0, armW = 0, stopV = 0,
		gseed = gaitSeed(rig), prof = nil, softK = 0.06,
	}
end

------------------------------------------------------------------------
-- Sensing the root's motion
------------------------------------------------------------------------
function AnimLoco.sense(rig, dt)
	local lo = rig.loco
	local root = rig.root
	local cf = root.CFrame
	local p = cf.Position
	local look = cf.LookVector
	local yaw = atan2(-look.X, -look.Z)
	lo.teleported = false
	if lo.pos == nil or (p - lo.pos).Magnitude > 6 then
		lo.pos, lo.yaw = p, yaw
		lo.vel, lo.acc, lo.yawRate, lo.speed = ZERO, ZERO, 0, 0
		lo.lv, lo.la = ZERO, ZERO
		lo.jumpOff, lo.jumpYaw = nil, 0
		lo.teleported = true
		lo.vy = 0
		return
	end
	local d = p - lo.pos
	local raw = V3(d.X, 0, d.Z) / dt
	-- the physics velocity is a good hint for client-simulated characters (no frame jitter)
	local av = root.AssemblyLinearVelocity
	local phys = V3(av.X, 0, av.Z)
	-- a server nudge / pivot teleport (PivotTo a stud or two away in one frame): the body glides
	-- there instead of popping, and no velocity spike reaches the gait (the feet step after it)
	-- (the travel this update is expected from the sensed OR the physics speed: a run started from a
	-- standstill at a low frame rate - or on a far rig's 2-4 frame step - is real motion, not a nudge)
	local flatD = V3(d.X, 0, d.Z).Magnitude
	if flatD > max(0.9, lo.speed * dt * 3 + 0.5, phys.Magnitude * dt * 1.8 + 0.5) then
		lo.jumpOff = (lo.jumpOff or ZERO) - V3(d.X, 0, d.Z)
		lo.jumpYaw = (lo.jumpYaw or 0) + K.wrap(lo.yaw - yaw)
		raw = lo.vel
	elseif abs(K.wrap(yaw - lo.yaw)) > 0.35 then
		lo.jumpYaw = (lo.jumpYaw or 0) + K.wrap(lo.yaw - yaw)
	end
	local kd = exp(-dt * 9)
	if lo.jumpOff then
		lo.jumpOff *= kd
		if lo.jumpOff.Magnitude < 1e-3 then
			lo.jumpOff = nil
		end
	end
	if lo.jumpYaw ~= 0 then
		lo.jumpYaw *= kd
		if abs(lo.jumpYaw) < 1e-3 then
			lo.jumpYaw = 0
		end
	end
	if phys.Magnitude > raw.Magnitude * 0.6 and phys.Magnitude < raw.Magnitude * 1.6 + 1 then
		raw = raw:Lerp(phys, 0.5)
	end
	local k = 1 - exp(-dt * 20)
	local vel = lo.vel + (raw - lo.vel) * k
	local acc = (vel - lo.vel) / dt
	lo.acc = lo.acc + (acc - lo.acc) * (1 - exp(-dt * 9))
	lo.vel = vel
	lo.speed = vel.Magnitude
	-- (vertical: a walker on a ramp or stairs; clamped so a teleport-sized hop never spikes it)
	lo.vy += (clamp(d.Y / dt, -40, 40) - lo.vy) * (1 - exp(-dt * 8))
	local dyaw = K.wrap(yaw - lo.yaw)
	lo.yawRate += (dyaw / dt - lo.yawRate) * (1 - exp(-dt * 12))
	lo.pos, lo.yaw = p, yaw
	lo.lv = cf:VectorToObjectSpace(vel)
	lo.la = cf:VectorToObjectSpace(lo.acc)
end

------------------------------------------------------------------------
-- Voluntary steps: offset (body space: +x right, -z forward) held for `hold` seconds, then the
-- foot steps back home by itself
------------------------------------------------------------------------
function AnimLoco.request(rig, s, ox, oz, dur, lift, hold, t)
	local f = rig.foot[s]
	if not f then
		return
	end
	f.vox, f.voz = ox, oz
	f.vUntil = t + (hold or 0.3)
	f.vNow = true
	f.vDur = dur or 0.18
	f.vLift = lift or 0.14
end

-- is a foot free to be asked for a step (on the ground and not just landed)?
function AnimLoco.ready(rig, s, t)
	local f = rig.foot[s]
	return f and not f.swing and t - f.lastStep > 0.06
end

------------------------------------------------------------------------
-- Gait context: the pose functions declare what kind of gait they want this frame:
--  "walk" (outside the ring: walk / jog / run / sprint by speed), "shuffle" (boxing footwork),
--  "stagger" (dazed / stumbling: short irregular steps), nil (no gait: steps only on error)
-- Returns how much the rig is moving (0..1) so the pose can blend arm swing etc.
------------------------------------------------------------------------
function AnimLoco.gait(rig, kind)
	rig.gaitKind = kind
	return rig.loco.gaitW
end

------------------------------------------------------------------------
-- The walk's numbers
------------------------------------------------------------------------
-- the personality of this character's walk (seed + body + style), cached until those change
local function profileOf(rig)
	local a = rig.a
	local lo = rig.loco
	local pr = lo.prof
	local style, frame, bulk, fem = a.Style, a.Frame, a.Bulk, a.Female
	if pr and pr.style == style and pr.frame == frame and pr.bulk == bulk and pr.fem == fem then
		return pr
	end
	pr = pr or {}
	pr.style, pr.frame, pr.bulk, pr.fem = style, frame, bulk, fem
	local gs = lo.gseed
	local st = STYLE_GAIT[style] or NO_STYLE
	local b = R.bulkOf(rig)
	local female = fem == true
	local function r(i)
		return K.rand3(gs, i, 7.7) * 2 - 1
	end
	-- (women: quicker steps, more pelvis; big men: slower, wider, quieter arms)
	pr.cad = st.cad * (1 + 0.035 * r(1)) * (female and 1.045 or 1) * (1 - 0.04 * b)
	pr.swing = st.swing * (1 + 0.14 * r(2)) * (1 - 0.15 * b)
	pr.elbow = st.el + 0.07 * r(3)
	pr.bob = st.bob * (1 + 0.12 * r(4))
	pr.width = st.width * (1 + 0.1 * r(5)) * (female and 0.86 or 1) * (1 + 0.3 * b)
	pr.toe = 0.04 * r(6) + 0.03 * b
	pr.lean = st.lean + 0.012 * r(7)
	pr.pelvis = st.roll * (female and 1.22 or 1) * (1 + 0.1 * r(8))
	pr.out = 0.025 * r(9) + (female and -0.015 or 0)
	pr.knee = 0.035 * (r(10) + 1)
	pr.lag = 0.02 * r(11)
	return pr
end
AnimLoco.profileOf = profileOf

-- the leg from the hip joint to the sole (studs)
local function soleLeg(g)
	return (g.ok and g.legLen or 2.4) + (g.ok and g.L and g.L.ah or 0.33)
end

-- stride period (s, two steps) and duty factor for a walker / runner at v studs/s
local function walkTiming(lo, v, Ls, kL, vh, prof)
	local run = lo.run
	-- cadence (steps/min): a walk 98 (stroll) .. 138 (brisk), a run 163 (jog) .. 200 (sprint)
	local spm = lerp(72 + 33 * vh, 150 + 3 * vh + 0.6 * vh * vh, run) * kL * prof.cad
	-- backward: shorter, quicker steps; sideways: shorter and quicker still (a leg reaches less to the side,
	-- and the trailing foot closes up beside the leading one without crossing it: a quick side shuffle)
	spm *= 1 + 0.2 * lo.back + 0.5 * lo.side
	local T = 120 / clamp(spm, 70, 240)
	-- stance share of the stride: walking ~0.6 (double support), running 0.4 (jog) .. 0.25 (sprint);
	-- never a contact longer than the leg can sweep (this rig's legs and short forefoot reach less than a
	-- person's: a walker takes up to 15 % quicker steps first, then shortens the stance)
	local duty = lerp(0.685 - 0.053 * vh, 0.47 - 0.032 * vh, run)
	local reach = Ls * lerp(clamp(0.62 + 0.24 * vh, 0.8, 1.12), 0.8, run) * (1 - 0.5 * lo.side)
	if run < 0.5 and v * T * duty > reach then
		-- (a quick man's own tempo still shows when the reach sets the step: shorter, quicker steps; a slow
		-- one cannot step further than his legs reach)
		T = max(T * 0.87, reach / max(0.1, v * duty)) / max(1, prof.cad) ^ 0.8
	end
	duty = min(duty, reach / max(0.1, v * T))
	duty = clamp(duty, lerp(0.53, 0.14, run), 0.68)
	return T, duty
end

-- the knee a walker's / runner's stance leg is designed to show (rad) at sigma (0 touchdown .. 1
-- lift-off): walking nearly straight at heel strike, the loading flex, locked again by mid-stance;
-- running lands softly bent and sinks to mid-stance
local function stanceKnee(sigma, run, vh, prof)
	local kw
	local lr = (8 + 5 * vh) * prof.bob * RAD
	if sigma < 0.16 then
		kw = lerp(4 * RAD, lr, smooth(sigma / 0.16))
	elseif sigma < 0.5 then
		kw = lerp(lr, 5 * RAD, smooth((sigma - 0.16) / 0.34))
	else
		kw = 5 * RAD
	end
	if run < 0.01 then
		return kw
	end
	local pk = (29 + 2 * vh) * (0.85 + 0.15 * prof.bob) * RAD
	local kr
	if sigma < 0.45 then
		kr = lerp(20 * RAD, pk, smooth(sigma / 0.45))
	else
		kr = lerp(pk, 24 * RAD, smooth((sigma - 0.45) / 0.55))
	end
	return lerp(kw, kr, run)
end

-- a walker's / runner's foot pitch through the stance (+ heel up about the ball, - toes up about the heel)
local function stancePitch(sigma, run, back)
	-- heel strike -> foot flat (a backward step: ball -> heel down)
	local strike = lerp(lerp(-0.28, 0.02, run), 0.3, back)
	local roll = strike * (1 - smooth(sigma / 0.18))
	-- the heel rises from mid-stance and the foot rolls over the ball to toe-off (backward: the toes come
	-- up at the end and the foot leaves heel last)
	local off2 = lerp(0.62, 0.75, run) * smooth((sigma - 0.45) / 0.55)
	-- (pre-swing, both feet down: the trailing foot rolls up onto its toes, the leading leg takes the weight)
	off2 += 0.35 * (1 - run) * smooth((sigma - 0.78) / 0.2)
	off2 = lerp(off2, -0.25 * smooth((sigma - 0.7) / 0.3), back)
	return roll + off2
end

-- the gait's per-frame phase / parameters (call once per frame before the feet)
local function updateGait(rig, t, dt)
	local lo = rig.loco
	local kind = rig.gaitKind
	local v = lo.speed
	lo.gaitT = t
	if kind == nil or not rig.plant then
		lo.moving = false
		lo.gaitW += (0 - lo.gaitW) * (1 - exp(-dt * 8))
		return
	end
	local was = lo.moving
	-- (the pace of the last second or so)
	lo.peakV = max(v, (lo.peakV or 0) - dt * 8)
	if lo.moving then
		if v < MOVE_OFF then
			lo.moving = false
			lo.stopT = t
			-- (how hard he was going: the knees' dip on the stop)
			lo.stopV = lo.peakV or 0
		end
	elseif v > MOVE_ON then
		lo.moving = true
		lo.moveT = t
	end
	lo.gaitW += ((lo.moving and 1 or 0) - lo.gaitW) * (1 - exp(-dt * 7))
	if not lo.moving then
		if kind == "walk" then
			lo.runMode = false
			lo.run += (0 - lo.run) * (1 - exp(-dt * 4))
		end
		return
	end
	local g = rig.geo
	local legLen = g.ok and g.legLen or 2.4
	local dir = lo.lv.Magnitude > 1e-3 and lo.lv.Unit or V3(0, 0, -1)
	if kind == "walk" then
		local prof = profileOf(rig)
		local Ls = soleLeg(g)
		local kL = sqrt(LREF / Ls)
		local vh = v * VH * kL
		-- forward / backward / sideways: the arms' swing and the backward step follow it
		local fz = v > 0.3 and -lo.lv.Z / v or 1
		lo.fwd += (fz - lo.fwd) * (1 - exp(-dt * 8))
		lo.back = smooth((-lo.fwd - 0.25) / 0.45)
		local fx = v > 0.3 and abs(lo.lv.X) / v or 0
		lo.side += (fx - lo.side) * (1 - exp(-dt * 8))
		-- walk or run: people switch at about Froude 0.5; hysteresis so a speed near it never flickers
		-- (a ring walk may stride out further before it breaks into a jog: rig.walkMax)
		local wm = rig.walkMax or 1
		if lo.runMode then
			if vh < RUN_OFF * wm then
				lo.runMode = false
			end
		elseif vh > RUN_ON * wm then
			lo.runMode = true
		end
		lo.run += ((lo.runMode and 1 or 0) - lo.run) * (1 - exp(-dt * 7))
		local T, duty = walkTiming(lo, v, Ls, kL, vh, prof)
		-- (no two strides alike: the cadence drifts a few per cent, per walker)
		T *= 1 + 0.03 * K.noise1(t * 0.55 + lo.gseed % 97, 3.3)
		lo.T, lo.duty, lo.vh = T, duty, vh
		lo.offL, lo.offR = 0, 0.5
		lo.swL, lo.swR = 1 - duty, 1 - duty
		lo.stride = v * T
	elseif kind == "stagger" then
		-- short, quick, irregular steps (dazed legs): alternating, a little uneven
		local S = clamp(0.4 + 0.12 * v, 0.5, 1.6)
		lo.T = clamp(S / max(v, 0.1), 0.3, 0.6)
		lo.run = 0
		lo.duty = 0.55
		lo.offL, lo.offR = 0, 0.47
		lo.swL, lo.swR = 0.42, 0.42
		lo.stride = v * lo.T
	else
		-- boxing footwork: the foot on the side of travel leads (orthodox: left is the front foot)
		local fL, fR = rig.foot.L, rig.foot.R
		local hx, hz = (-fL.x - fR.x) - 0.5, fL.z - fR.z -- rough vector R -> L in body space
		local dLead = dir.X * hx + dir.Z * hz
		if dLead > 0.12 then
			lo.lead = "L"
		elseif dLead < -0.12 then
			lo.lead = "R"
		end
		-- step length per cycle grows with speed; the cycle shortens to a floor, then the steps grow
		-- and the second foot leaves before the first lands (a gallop)
		local S = clamp((0.3 + 0.19 * v) * (rig.strideK or 1), 0.4, 2.8)
		lo.T = clamp(S / max(v, 0.1), 0.25, 0.5)
		lo.run = smooth((v - 6.5) / 4)
		local sw = lerp(0.36, 0.44, lo.run)
		lo.duty = 1 - sw
		lo.stride = v * lo.T
		local trail = lerp(sw + 0.06, 0.22, lo.run)
		if lo.lead == "L" then
			lo.offL, lo.offR = 0, trail
		else
			lo.offR, lo.offL = 0, trail
		end
		lo.swL, lo.swR = sw, sw
	end
	if not was then
		-- start: the leading foot goes now, the other follows on its schedule
		local first = lo.offL <= lo.offR and "L" or "R"
		lo.phase = (first == "L" and lo.offL or lo.offR) - 0.001
		for _, s in ipairs(SIDES) do
			local off = s == "L" and lo.offL or lo.offR
			rig.foot[s].cycle = floor(lo.phase - off)
			rig.foot[s].want = false
		end
	end
	lo.phase += dt / lo.T
end
AnimLoco.updateGait = updateGait

------------------------------------------------------------------------
-- Gait body motion: pelvis bob / sway / rotation, shoulder counter-rotation, lean. Returned as
-- offsets applied AFTER the pose filters (so they stay in step with the feet).
------------------------------------------------------------------------
function AnimLoco.bodyOffsets(rig, dt, t)
	local lo = rig.loco
	local kind = rig.gaitKind
	local w = lo.gaitW
	local amp = R.ampOf(rig)
	local rootY, rootX, yawP, rollP, pitchP, wYaw, wPitch, wRoll, nYaw = 0, 0, 0, 0, 0, 0, 0, 0, 0
	-- momentum: lean into acceleration, settle back with overshoot when stopping
	local fwdV, fwdA, latA = -lo.lv.Z, -lo.la.Z, lo.la.X
	local walking = kind == "walk"
	local prof = walking and profileOf(rig) or NO_STYLE
	local tgtP
	if walking then
		-- a walker / runner leans into ACCELERATION (the chest well past atan(a / g), as a sprinter's
		-- drive phase); at a steady pace only a little, more for a runner (with the pose's own waist lean: walk ~2, run ~6-8, sprint ~9 degrees);
		-- braking tips him back a few degrees, never a backward plunge
		local vh = lo.vh or 0
		local steady = (prof.lean + lerp(0.012 + 0.004 * vh, 0.004 + 0.01 * vh, lo.run)) * w * max(0, lo.fwd)
		tgtP = clamp(-steady - 0.014 * fwdA, -0.26, 0.12)
	else
		tgtP = clamp(-0.004 * fwdV * w - 0.012 * fwdA, -0.3, 0.2)
	end
	-- (into a turn: about the centripetal tilt, atan(v w / g))
	local tgtR = clamp(0.008 * latA - 0.01 * lo.speed * lo.yawRate * (walking and 0.6 or 0.4), -0.25, 0.25)
	lo.leanP, lo.leanPV = K.spring2(lo.leanP, lo.leanPV, tgtP, walking and 11 or 9, 0.55, dt)
	lo.leanR, lo.leanRV = K.spring2(lo.leanR, lo.leanRV, tgtR, 9, 0.6, dt)
	-- the upper body's inertia: a nod forward when braking hard, then settle
	local tgtI = clamp(0.01 * fwdA, -0.18, 0.18)
	lo.inP, lo.inPV = K.spring2(lo.inP, lo.inPV, tgtI, 7, 0.35, dt)
	pitchP = lo.leanP
	rollP = lo.leanR
	wPitch = lo.inP
	if w > 0.01 and kind then
		local ph = lo.phase
		local duty = lo.duty
		if walking then
			local run = lo.run
			-- L swings during [0, 1 - duty), lands at 1 - duty; mid-stance at 1 - duty / 2
			-- (no designed bob: the pelvis height follows the stance leg's knee in AnimLoco.feet, so it is
			-- lowest in double support / at a runner's mid-stance by construction)
			local landL = 1 - duty
			local midL = 1 - duty * 0.5
			local fw = lo.fwd
			-- sway over the stance leg
			rootX = -lerp(0.072, 0.035, run) * amp * prof.pelvis * cos(2 * PI * (ph - midL)) * w
			-- pelvis rotation (the stepping leg's hip goes with the step), shoulders counter-rotate
			local c1 = cos(2 * PI * (ph - landL)) * fw
			local pyA = lerp(0.075, 0.13, run) * amp * prof.pelvis
			yawP = -pyA * c1 * w
			wYaw = pyA * lerp(1.45, 1.7, run) * c1 * w
			-- the swing side's hip drops (pelvic obliquity: ~4 degrees, the stance hip takes the weight)
			rollP += -lerp(0.065, 0.05, run) * prof.pelvis * cos(2 * PI * (ph - midL)) * w
			-- the head stays level and on its line
			nYaw = -(yawP + wYaw) * 0.85
			lo.armPhase = ph - landL
		else
			-- footwork: a small rise on the push-off, settle on the landing; quicker / bouncier at speed
			local up = sin(2 * PI * ph)
			rootY = (0.035 + 0.02 * lo.run) * up * w * amp * (rig.bobK or 1)
			lo.armPhase = ph
		end
	end
	-- stopping: knees absorb, pelvis dips and comes back up (a walker's dip is in his knees: feet)
	if not lo.moving and kind and not walking then
		local el = t - lo.stopT
		if el < 0.45 then
			rootY -= 0.07 * K.attackDecay(el, 0.12, 0.45) * min(1, lo.stride / 1.2)
		end
	end
	-- turning: the head leads into the turn, the chest follows, the hips lag behind (the feet step round
	-- after them) - never the whole body turning as one block on the root
	-- (only on his feet: a fall, a seat or keyed legs own the whole body)
	local yr = kind and clamp(lo.yawRate, -4, 4) or 0
	lo.turnL += (yr - lo.turnL) * (1 - exp(-dt * 10))
	local tl = lo.turnL
	nYaw += clamp(0.17 * tl, -0.5, 0.5)
	wYaw += clamp(0.1 * tl, -0.3, 0.3)
	yawP += clamp(-0.05 * tl, -0.15, 0.15)
	-- the head keeps the eyes level: it counters the trunk's pitch and roll on a soft spring, so it trails
	-- the body's bob and sway a beat late (overlapping action) instead of riding it rigidly
	local tP = kind and -(pitchP + wPitch) * 0.5 or 0
	local tR = kind and -(rollP + wRoll) * 0.65 or 0
	lo.headP, lo.headPV = K.spring2(lo.headP, lo.headPV, tP, 7, 0.55, dt)
	lo.headR, lo.headRV = K.spring2(lo.headR, lo.headRV, tR, 7, 0.5, dt)
	return rootX, rootY, yawP, rollP, pitchP, wYaw, wPitch, wRoll, nYaw, lo.headP, lo.headR
end

------------------------------------------------------------------------
-- Arms of a walker / runner (outside the ring). The shape by pace (rad, relative to the hanging arm):
-- shoulder swing centre / half-amplitude, elbow at the back / front of the swing.
--  walk: the arm hangs and swings mostly behind the body (-24..+8 deg), the elbow barely bends (8 -> 25)
--  brisk walk: -30..+15, elbow 15 -> 45
--  jog / run: the elbow bends to ~90 and pumps (55 -> 105), the hand passes the hip on the back swing
--  sprint: -60..+40, elbow ~60 -> 110 (the back swing opens: the hand well behind the hip)
------------------------------------------------------------------------
local function armShape(lo, prof)
	local vh = lo.vh or 0
	local run = lo.run
	local swing = prof.swing
	local cw, aw = -(5 + 2 * vh), 4 + 8.5 * vh
	local ebw, efw = 6 + 4 * vh, 12 + 12 * vh
	local cr, ar = -(10 + 0.5 * vh), 17 + 4.4 * vh
	local ebr, efr = 60 - 1.6 * vh, 92 + 3 * vh
	local c = lerp(cw, cr, run) * RAD
	local a = lerp(aw, ar, run) * RAD * swing
	local eb = lerp(ebw, ebr, run) * RAD + prof.elbow
	local ef = lerp(efw, efr, run) * RAD + prof.elbow
	return c, a, max(0.05, eb), ef
end

-- the carriage (the swing's centre and the mean elbow) goes into the pose (filtered, it changes
-- slowly); the swing itself is AnimLoco.armOffsets, after the filters. k = blend (the gait weight)
function AnimLoco.armSwing(p, rig, k)
	local lo = rig.loco
	rig.armSwing = k
	if k <= 0.01 then
		return
	end
	local prof = profileOf(rig)
	local c, _, eb, ef = armShape(lo, prof)
	-- (walking backward / sideways the arms hang quieter)
	c *= 0.4 + 0.6 * max(0, lo.fwd)
	local em = (eb + ef) * 0.5
	-- arms hang close: out just enough for big lats / arms to clear the hips
	local out = 0.035 + 0.11 * R.bulkOf(rig) + prof.out
	p.LS = p.LS:Lerp(A(c, 0, -out), k)
	p.RS = p.RS:Lerp(A(c, 0, out), k)
	p.LE = p.LE:Lerp(A(em, 0, 0), k)
	p.RE = p.RE:Lerp(A(em, 0, 0), k)
end

-- the arm swing, applied by the Animator after the joint filters (in step with the legs, never lagging
-- them): shoulder pitch / elbow flex / shoulder roll deltas for the left and right arm, or nil.
-- Opposite the legs: the left arm is furthest back at the left heel strike (walking backward the other
-- way round, sideways quiet). hold = something else owns the arms (a gesture): the swing fades out
function AnimLoco.armOffsets(rig, dt, hold)
	local lo = rig.loco
	local want = hold and 0 or (rig.armSwing or 0) * (rig.armScale or 1)
	lo.armW += (want - lo.armW) * (1 - exp(-dt * 10))
	local w = lo.armW
	if w < 0.005 then
		return nil
	end
	local prof = profileOf(rig)
	local _, a, eb, ef = armShape(lo, prof)
	local fw = lo.fwd
	-- (the arm is furthest back when the same side's thigh is furthest forward: at a walker's heel strike;
	-- a runner's thigh drives through earlier, two thirds into the swing)
	local ph = 2 * PI * (lo.phase - (1 - lo.duty) + prof.lag + 0.35 * (1 - lo.duty) * lo.run)
	local cs = cos(ph)
	-- (the forearm trails the upper arm: overlapping action)
	local ce = cos(ph - lerp(0.35, 0.22, lo.run))
	-- (no two people swing alike: one arm a little bigger, per seed; hashed once per rig)
	local asym = lo.swingAsym
	if not asym then
		asym = (K.rand3(rig.seed or 0, 5.1, 2.7) - 0.5) * 0.18
		lo.swingAsym = asym
	end
	local sA = a * fw * w
	local eA = (ef - eb) * 0.5 * fw * w
	local sL = -sA * (1 + asym) * cs
	local sR = sA * (1 - asym) * cs
	local eL = -eA * ce
	local eR = eA * ce
	-- a runner's forearm swings across a touch as it comes forward
	local inK = 0.25 * lo.run
	return sL, eL, inK * max(0, sL), sR, eR, -inK * max(0, sR)
end

------------------------------------------------------------------------
-- Feet: planting, stepping, roll, pivots, then the leg IK
------------------------------------------------------------------------
local function rootYawOf(cf)
	local look = cf.LookVector
	return atan2(-look.X, -look.Z)
end

local function fwdOf(yaw)
	return V3(-sin(yaw), 0, -cos(yaw))
end

-- world ground point under the ankle at home (+ body-space offset); kx narrows the track (walkers)
local function homeOf(rig, s, rootCF, ox, oz, kx)
	local f = rig.foot[s]
	local leg = rig.geo[s]
	local sx = s == "L" and -1 or 1
	local a = leg.ankle0
	return rootCF:PointToWorldSpace(V3(a.X * kx + sx * f.x + ox, rig.geo.groundY, a.Z + f.z + oz))
end

local function startSwing(f, t, dur, liftH, kind)
	-- (what this foot asked of a walker's pelvis as it leaves, and how fast that was growing: released
	-- gradually)
	f.liftNeed = f.needDrop
	f.liftRate = f.needDrop and f.needPrev and clamp((f.needDrop - f.needPrev) / max(1 / 240, f.lastDt or 1 / 60), -4, 4) or 0
	f.swing = true
	f.t0 = t
	f.dur = max(0.08, dur)
	-- (a foot that was pivoting on its ball leaves from where it visibly is, turned)
	f.fromP = f.visP or f.P
	f.fromYaw = f.visYaw or f.yawW
	f.visP, f.visYaw, f.pivA = nil, nil, 0
	f.liftH = liftH
	f.cur, f.curYaw, f.curLift = f.fromP, f.fromYaw, 0
	f.liftPitch = f.pitchS
	f.stepKind = kind
	f.want = false
	f.gY, f.gRay = nil, -10
end

-- the floor under a walker's landing spot: a ray straight down (ramps, stairs, kerbs). Returns the
-- height and the slope's pitch along the foot (+ = uphill), or nil (keep the root's floor). Other
-- characters, furniture tops and anything further than a stair's rise from the root's floor are ignored
local function groundAt(rig, pos, floorY, F)
	local params = rig.rayP
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { rig.model }
		params.RespectCanCollide = true
		rig.rayP = params
	end
	local ok, hit = pcall(workspace.Raycast, workspace, V3(pos.X, floorY + STEP_UP, pos.Z), V3(0, -(STEP_UP + STEP_DOWN), 0), params)
	if not ok or not hit then
		return nil
	end
	local inst = hit.Instance
	local m = inst and inst:FindFirstAncestorOfClass("Model")
	if m and m:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	local n = hit.Normal
	if n.Y < 0.6 then
		return nil -- a wall / the side of a step: keep the root's floor
	end
	return hit.Position.Y, atan2(-(n.X * F.X + n.Z * F.Z), n.Y)
end

-- the feet: called after the output filter with this frame's Root Transform (rootT)
function AnimLoco.feet(rig, p, rootT, t, dt, lock)
	local lo = rig.loco
	local g = rig.geo
	local root = rig.root
	local trueCF = root.CFrame
	-- feet go where the body visibly is: during a teleport glide that is behind the true root
	local rootCF = trueCF
	if lo.jumpOff or lo.jumpYaw ~= 0 then
		local lj = lo.jumpOff and trueCF:VectorToObjectSpace(lo.jumpOff) or ZERO
		rootCF = trueCF * CF(lj) * A(0, lo.jumpYaw, 0)
	end
	local rootYaw = rootYawOf(rootCF)
	local trueYaw = rootYawOf(trueCF)
	local vel = lo.vel
	local speed = lo.speed
	local kind = rig.gaitKind
	rig.foot.L.lastDt, rig.foot.R.lastDt = dt, dt
	if lo.gaitT ~= t then
		updateGait(rig, t, dt)
	end
	local moving = lo.moving and kind ~= nil
	local walking = kind == "walk"
	local prof = walking and profileOf(rig) or NO_STYLE
	local run = lo.run
	local back = walking and lo.back or 0
	-- a runner's heel kick scales with the leg
	local runLegK = (g.ok and g.legLen or 2.45) / 2.45
	local legLen = g.legLen
	-- a walker's track: the feet land closer to the line of travel than the hips (narrower running)
	local kx = 1
	if walking then
		kx = 1 - (1 - clamp(lerp(0.66, 0.52, run) * prof.width, 0.4, 1)) * lo.gaitW
	end
	-- per-foot desired ground point and yaw
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		-- voluntary offset expired: come back home with a step
		if f.vUntil < t and (f.vox ~= 0 or f.voz ~= 0) then
			f.vox, f.voz = 0, 0
			f.vNow = true
			f.vDur = 0.16
			f.vLift = 0.1
		end
		local ox, oz = f.ox + f.vox, f.oz + f.voz
		f.home = homeOf(rig, s, rootCF, ox, oz, kx)
		f.homeYaw = rootYaw + f.yaw + (walking and (s == "L" and prof.toe or -prof.toe) or 0)
		if not lock or f.free or not f.P or lo.teleported then
			f.P, f.yawW, f.swing, f.curLift = f.home, f.homeYaw, false, 0
			f.pitchS = f.heel
			f.want = false
			f.slopeP = 0
		end
	end
	-- moving gait: lift each foot when its phase window opens (or as soon as it may, inside it)
	local walkLift = lerp(0.2 + 0.015 * speed, min(1.1, 0.25 + 0.04 * speed) * runLegK, run)
	if moving then
		for _, s in ipairs(SIDES) do
			local f = rig.foot[s]
			local o = rig.foot[s == "L" and "R" or "L"]
			local off = s == "L" and lo.offL or lo.offR
			local sw = s == "L" and lo.swL or lo.swR
			local cyc = floor(lo.phase - off)
			if cyc > f.cycle then
				f.cycle = cyc
				f.want = true
			end
			if f.want and not f.swing and t - f.lastStep >= MIN_STANCE then
				local x = (lo.phase - off) % 1
				if x <= sw then
					-- the other foot must be down (or about to land) unless running / galloping
					local overlap = walking or lo.run > 0.3 or (o.swing and o.t0 + o.dur - t < 0.035)
					if not o.swing or overlap then
						local liftH
						if walking then
							liftH = walkLift
						elseif kind == "stagger" then
							liftH = 0.12 + 0.02 * speed
						else
							liftH = (0.1 + 0.025 * speed) * rig.liftK
						end
						-- (a foot that lifts late in its window - it had to stay down MIN_STANCE first - takes
						-- a shorter, lower step, never a 0.08 s flick to full height)
						local full = sw * lo.T
						local dur = max((sw - x) * lo.T, 0.55 * full)
						startSwing(f, t, dur, liftH * clamp(dur / max(0.05, full) + 0.1, 0.4, 1), kind)
					end
				else
					f.want = false
				end
			end
		end
	end
	-- error-driven steps (standing: turning in place, drift; or a foot left far behind), and the
	-- reach safety: a planted foot nearly out of the leg's reach steps instead of being dragged
	local needL, needR = 0, 0
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		if not f.swing and f.P then
			local dx, dz = f.P.X - f.home.X, f.P.Z - f.home.Z
			local err = sqrt(dx * dx + dz * dz)
			local yerr = abs(K.wrap(f.yawW - f.homeYaw))
			local leg = g[s]
			local hip = rootCF:PointToWorldSpace(leg.hip0)
			local hx, hz = f.P.X - hip.X, f.P.Z - hip.Z
			local reach = sqrt(hx * hx + hz * hz)
			-- (a walker's foot left so far behind that it would hold the pelvis well under where the other
			-- leg carries it toes off now: no plunge, no dragged toe)
			local tooFar
			if walking then
				-- (and whatever the other foot does, a foot that would drag the pelvis down a long way - an
				-- explosive start, a hard turn - goes now)
				-- (or a foot the pelvis can no longer bring within reach: it would be dragged - it steps)
				local nd = f.needDrop or 0
				tooFar = moving and (((f.sigma or 0) > 0.6 and (f.excess or 0) > lerp(WALK_EXCESS, 0.05, run))
					or nd + max(0, nd - (f.needPrev or nd)) > lerp(0.22, 0.32, run)
					or (nd - lo.drop > 0.06 and t - f.lastStep > 0.15)
					-- (a runner is lowest at mid-stance: a push-off that would take the pelvis further down leaves)
					or (run > 0.5 and (f.sigma or 0) > 0.6 and nd > (f.midNeed or 1e9) + 0.04))
			else
				tooFar = false
			end
			if err > 5 then
				f.P, f.yawW = f.home, f.homeYaw -- teleported (Poser.Place, PivotTo)
			elseif f.vNow then
				if s == "L" then
					needL = 99
				else
					needR = 99
				end
			elseif reach > legLen * 0.84 or tooFar then
				if s == "L" then
					needL = 50 + reach
				else
					needR = 50 + reach
				end
			else
				-- spin on the ball for small turns instead of stepping
				if yerr > 0.08 and err < rig.stepDist * 0.8 and not moving then
					local want = K.wrap(f.homeYaw - f.yawW)
					local step = clamp(want, -dt * 3.2, dt * 3.2)
					local B = f.P + fwdOf(f.yawW) * leg.bz
					f.yawW += step
					f.P = B - fwdOf(f.yawW) * leg.bz
					f.spinT = t
					yerr = abs(K.wrap(f.yawW - f.homeYaw))
				end
				local limit = moving and (walking and 0.9 * lo.stride + 0.6 or rig.stepDist + 0.6 * lo.stride) or rig.stepDist
				if err > limit or yerr > 0.65 then
					if s == "L" then
						needL = err + yerr
					else
						needR = err + yerr
					end
				end
			end
		end
	end
	if needL > 0 or needR > 0 then
		-- boxers move the foot on the side of travel first and never cross the feet; otherwise the
		-- foot furthest from home goes first. Requested / reach steps go now.
		local s
		if needL >= 50 or needR >= 50 then
			s = needL >= needR and "L" or "R"
		else
			local lvx = lo.lv.X
			if abs(lvx) > 1.5 and needL > 0 and needR > 0 then
				s = lvx > 0 and "R" or "L"
			else
				s = needL >= needR and "L" or "R"
			end
		end
		local f = rig.foot[s]
		local o = rig.foot[s == "L" and "R" or "L"]
		local urgent = (s == "L" and needL or needR) >= 50
		if not f.swing and (not o.swing or urgent or (t - o.t0) > o.dur * 0.55) and t - f.lastStep >= MIN_STANCE then
			local dur = f.vNow and f.vDur or clamp(0.24 - speed * 0.015, 0.12, 0.24) * rig.stepTime
			local liftH = f.vNow and f.vLift or clamp(0.1 + speed * 0.012, 0.08, 0.3) * rig.liftK
			local sk = f.vNow and "req" or (urgent and "reach" or "fix")
			if urgent and moving and kind then
				-- a foot left behind by an accelerating body joins the gait (lands with its lead); a
				-- swing cut short lifts the foot less (the knee never snaps up in a frame)
				local full = (1 - lo.duty) * lo.T
				dur = max(0.16, full * 0.8)
				if walking then
					-- (a walker's early toe-off IS this cycle's step: it lands when the schedule says, and
					-- the schedule does not lift the foot a second time)
					local off = s == "L" and lo.offL or lo.offR
					local sw = 1 - lo.duty
					local x = (lo.phase - off) % 1
					if x > sw then
						dur = max(full * 0.8, (1 - x + sw) * lo.T)
						f.cycle = floor(lo.phase - off) + 1
					else
						dur = max(0.16, (sw - x) * lo.T)
						f.cycle = floor(lo.phase - off)
					end
				end
				liftH = walking and walkLift or liftH
				liftH *= clamp(dur / max(0.05, full), 0.35, 1)
				sk = kind
			end
			startSwing(f, t, dur, liftH, sk)
			f.vNow = false
		end
	end
	-- the heel / pivot / knee specs come from the pose and acts frame by frame: low-pass them so an
	-- interrupted act never makes a foot jump
	-- (and rate-limit them: a pivot or a heel never turns the ankle faster than PIVOT_RATE / HEEL_RATE)
	local fk = 1 - exp(-dt * 26)
	local pvMax, hlMax = PIVOT_RATE * dt, HEEL_RATE * dt
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		f.heelS += clamp((f.heel - f.heelS) * fk, -hlMax, hlMax)
		f.pivotS += clamp((f.pivot - f.pivotS) * fk, -pvMax, pvMax)
		f.kneeS += (f.knee - f.kneeS) * fk
		-- the pivot a planted foot actually shows: a foot in the air does not pivot, it lands square
		-- and then turns on the ball (no snap at touchdown)
		if f.swing then
			f.pivA = 0
		else
			local pa = f.pivA or 0
			f.pivA = pa + clamp(f.pivotS - pa, -pvMax, pvMax)
		end
	end
	-- swings: aim where home will be when the foot lands (+ the gait's lead), arc, roll the foot
	local fight = not walking
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		if f.swing then
			local o = rig.foot[s == "L" and "R" or "L"]
			local u = (t - f.t0) / f.dur
			local remain = max(0, f.t0 + f.dur - t)
			local lead = 0
			local d = speed > 0.05 and vel / speed or ZERO
			local sk = f.stepKind
			if moving and (sk == "walk" or sk == "shuffle" or sk == "stagger") then
				if sk == "walk" then
					-- walkers plant the heel a little ahead of the hip (about 0.4 of the contact) and push
					-- off further behind it; runners land closer under the body
					lead = lo.duty * lo.stride * lerp(0.4, 0.4, lo.run)
				elseif sk == "stagger" then
					lead = lo.stride * 0.25
				else
					lead = (s == lo.lead) and lo.stride * 0.42 or -lo.stride * 0.06
				end
			end
			-- where home will be at touchdown: velocity and (clamped) acceleration over the remaining swing
			local acc = lo.acc
			local am = acc.Magnitude
			if am > 30 then
				acc = acc * (30 / am)
			end
			local tgt = f.home + vel * remain + V3(acc.X, 0, acc.Z) * (0.5 * remain * remain) + d * lead
			-- footwork: the feet never come closer side by side than FOOT_GAP (no crossing, no clipping);
			-- a walker's feet keep WALK_GAP (strafing never scissors the legs)
			local oP = o.swing and o.cur or o.P
			if oP and (fight or walking) then
				local lt = rootCF:PointToObjectSpace(tgt)
				local lo2 = rootCF:PointToObjectSpace(oP)
				local gap = walking and WALK_GAP or FOOT_GAP * (kind == "stagger" and 0.6 or 1)
				if s == "L" and lt.X > lo2.X - gap then
					lt = V3(lo2.X - gap, lt.Y, lt.Z)
					tgt = rootCF:PointToWorldSpace(lt)
				elseif s == "R" and lt.X < lo2.X + gap then
					lt = V3(lo2.X + gap, lt.Y, lt.Z)
					tgt = rootCF:PointToWorldSpace(lt)
				end
			end
			local landYaw = f.homeYaw
			-- a walker's floor under the landing spot (a ray at the start of the swing and again half-way,
			-- the spot moves with the body), and the slope along the foot
			local gy = f.home.Y
			if walking then
				if (u >= 0.5 and f.gRay < f.t0 + f.dur * 0.5) or f.gRay < f.t0 then
					f.gRay = t
					local y, sl = groundAt(rig, tgt, f.home.Y, fwdOf(landYaw))
					f.gY, f.landSlope = y, sl or 0
				end
				gy = f.gY or gy
			end
			-- the touchdown spot as seen from where the body is now (for the pelvis height)
			f.landRel = tgt - vel * remain - V3(acc.X, 0, acc.Z) * (0.5 * remain * remain)
			f.landRel = V3(f.landRel.X, gy, f.landRel.Z)
			f.landYaw = landYaw
			if u >= 1 then
				f.swing, f.P, f.yawW, f.lastStep, f.curLift = false, V3(tgt.X, gy, tgt.Z), landYaw, t, 0
				f.landT = t
				f.dropH = nil
				f.pitchS = f.curPitch
				f.slopeP = walking and (f.gY and f.landSlope or 0) or 0
			else
				-- horizontal travel: zero speed at lift-off and touchdown (the foot leaves and meets the
				-- canvas without a skid); runners cruise and brake late (no hovering reach ahead)
				local e = K.smoother(u)
				if sk == "walk" and lo.run > 0.01 then
					e = lerp(e, K.cruise(u), lo.run)
				end
				local pos = f.fromP:Lerp(tgt, e)
				-- (up a step the foot rises to the new height early, down one it stays high, then drops)
				local y0 = f.fromP.Y
				local ey = gy > y0 and smooth(u / 0.55) or smooth((u - 0.35) / 0.65)
				f.cur = V3(pos.X, walking and lerp(y0, gy, ey) or f.home.Y, pos.Z)
				f.curYaw = f.fromYaw + K.wrap(landYaw - f.fromYaw) * e
				-- the arc: walking clears the ground early in the swing (the knee's peak flexion) and skims
				-- in to the heel strike; running kicks the heel up early behind the body, then the knee
				-- unfolds as the foot reaches forward. A smooth skewed bump u^a (1-u)^b (zero slope at
				-- lift-off and touchdown: no knee snap)
				-- (a runner kicks the heel up early behind the body, then the knee unfolds as the foot reaches)
				local a = sk == "walk" and lerp(1.6, 1.2, lo.run) or 2
				local b = sk == "walk" and lerp(2.4, 1.9, lo.run) or 2
				f.curLift = f.liftH * K.skewBump(u, a, b) + (f.dropH or 0) * (1 - K.smoother(u))
				-- foot roll through the swing: toe-off -> level -> landing attitude
				local landP, mid
				if sk == "walk" then
					-- (heel first; a backward step lands on the ball of the foot)
					landP = lerp(lerp(-0.28, 0.02, lo.run), 0.3, back) - (f.gY and f.landSlope or 0)
					mid = lerp(-0.08, 0.35, lo.run)
				else
					landP = f.heelS + 0.12 -- boxers land on the balls of the feet
					mid = f.heelS + 0.05
				end
				f.landPitch = landP
				local pt
				if u < 0.45 then
					pt = lerp(f.liftPitch, mid, smooth(u / 0.45))
				else
					pt = lerp(mid, landP, smooth((u - 0.45) / 0.55))
				end
				f.curPitch = pt
			end
		end
	end
	-- stance pitch: the gait's heel-strike roll and toe-off, else the pose's heel spec
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		if not f.swing then
			local want = f.heelS
			if moving and walking then
				local off = s == "L" and lo.offL or lo.offR
				local sw = 1 - lo.duty
				local sigma = ((lo.phase - off - sw) % 1) / lo.duty -- 0 at landing .. 1 at lift-off
				-- (a foot that landed off its schedule - a pace change, a step out of turn - counts its stance
				-- from its own touchdown; it never jumps back to an earlier part of the stance)
				local sa = (t - f.landT) / max(0.05, lo.duty * lo.T)
				sigma = sigma <= 1.02 and max(sigma, min(sa, 1)) or min(sa, 1)
				f.sigma = sigma
				want = stancePitch(sigma, run, back)
			elseif moving then
				-- footwork: up on the balls just before the push-off
				local off = s == "L" and lo.offL or lo.offR
				local x = (lo.phase - off) % 1
				want = f.heelS + 0.25 * smooth((x - 0.82) / 0.18)
			end
			if walking then
				-- (on a slope the flat foot lies along it: toes up going uphill)
				want -= f.slopeP or 0
			end
			if t - f.spinT < 0.1 then
				want += 0.12
			end
			-- (a boxer's planted foot never goes past the ball onto the toes: the heel lifts so far and the
			-- knee and the pelvis take the rest)
			if not walking then
				want = min(want, FIGHT_PITCH_MAX)
			end
			-- just landed: settle from the landing attitude
			f.pitchS += (want - f.pitchS) * (1 - exp(-dt * 18))
			f.curPitch = f.pitchS
		end
	end
	-- feet into the root's space; the pelvis sinks if a foot would be out of reach
	local targets = rig.ftmp or {}
	rig.ftmp = targets
	local drop = 0
	-- walkers: the pelvis height follows the legs (signed: it may rise a little over the pose's height)
	local wNeed, wCap = nil, WALK_DROP
	-- (a walker standing still: relaxed, nearly straight knees, a stop's dip)
	local standKnee = 0
	if walking and not moving then
		local el = t - lo.stopT
		standKnee = (5 * RAD + prof.knee)
		if el < 0.6 then
			standKnee += 0.38 * K.attackDecay(el, 0.14, 0.6) * min(1, (lo.stopV or 0) / 12)
		end
	end
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		local leg = g[s]
		local P = f.swing and f.cur or f.P
		local yawW = f.swing and f.curYaw or f.yawW
		-- pivot on the ball: rotate the ground point about the ball by the act's pivot
		local pv = f.pivA or 0
		if abs(pv) > 1e-3 and not f.swing then
			local B = P + fwdOf(yawW) * leg.bz
			yawW += pv
			P = B - fwdOf(yawW) * leg.bz
			f.visP, f.visYaw = P, yawW
		elseif not f.swing then
			f.visP, f.visYaw = nil, nil
		end
		local pitch = f.curPitch
		local lift = f.swing and f.curLift or 0
		local ank = R.ankleOf(leg, P, fwdOf(yawW), pitch) + V3(0, lift + f.lift, 0)
		-- into the TRUE root's space (the IK and rootT live there)
		local tgt = trueCF:PointToObjectSpace(ank)
		targets[s] = tgt
		targets[s .. "yaw"] = K.wrap(yawW - trueYaw)
		targets[s .. "pitch"] = pitch
		if walking then
			-- the stance leg's knee by design (heel strike nearly straight, loading flex, locked by mid-stance;
			-- a runner softly bent); from mid-stance on the leg is let go (slack ~1: the heel rises, the
			-- other leg carries the pelvis), so a trailing foot never holds the pelvis down by its knee
			if not f.swing then
				local slack
				if moving and f.sigma then
					slack = R.slackFor(leg, stanceKnee(f.sigma, run, lo.vh, prof), WALK_SOFT)
					slack = lerp(slack, 1.0, smooth((f.sigma - lerp(0.55, 0.6, run)) / 0.3))
				else
					slack = R.slackFor(leg, standKnee, WALK_SOFT)
				end
				local need = R.needFor(rig, s, rootT, tgt, slack, WALK_DROP + 0.3)
				f.needPrev = f.needDrop or need
				f.needDrop = need
				-- (a runner's deepest mid-stance need this stance)
				if f.sigma and f.sigma >= 0.3 and f.sigma <= 0.55 then
					f.midNeed = max(f.midNeed or -1e9, need)
				elseif not f.sigma or f.sigma < 0.3 then
					f.midNeed = nil
				end
				-- (a just-landed leg is about to give into its loading flex: what it will let the pelvis do)
				f.needLoad = need
				if moving and f.sigma and f.sigma < 0.16 and run < 0.5 then
					local lr = stanceKnee(0.16, run, lo.vh, prof)
					f.needLoad = max(need, R.needFor(rig, s, rootT, tgt, R.slackFor(leg, lr, WALK_SOFT), WALK_DROP + 0.3))
				end
				-- (the pelvis spring trails a moving target by about PELVIS_LEAD: it is aimed at this foot's
				-- need that far ahead - the body moved on over the planted foot, the stance further along - so a
				-- runner's pelvis rides with his legs instead of lagging them)
				-- (a walker's legs move slowly enough to be followed as they are: runners only)
				local ahead = need
				if moving and f.sigma and run > 0.01 then
					-- (never past this foot's toe-off: it will not be holding the pelvis then)
					local stT = max(0.05, lo.duty * lo.T)
					local lead = min(PELVIS_LEAD * run, max(0, 1 - f.sigma) * stT)
					local sa = min(1, f.sigma + lead / stT)
					local sl = R.slackFor(leg, stanceKnee(sa, run, lo.vh, prof), WALK_SOFT)
					sl = lerp(sl, 1.0, smooth((sa - lerp(0.55, 0.6, run)) / 0.3))
					-- (the ankle where the foot's roll will have it then)
					local pa = stancePitch(sa, run, back) - (f.slopeP or 0)
					local aa = trueCF:PointToObjectSpace(R.ankleOf(leg, P, fwdOf(yawW), pa) + V3(0, f.lift, 0))
					ahead = R.needFor(rig, s, rootT, aa - lo.lv * lead, sl, WALK_DROP + 0.3)
				end
				f.ahead = ahead
				wNeed = max(wNeed or -1e9, ahead)
				-- (a foot on lower ground than the root's floor - stairs down, a ramp - may take the pelvis
				-- further down)
				wCap = max(wCap, WALK_DROP + clamp(f.home.Y - P.Y, 0, 0.9))
			else
				f.needDrop, f.needPrev = nil, nil
				local u = (t - f.t0) / f.dur
				if u > 0.6 and f.landRel then
					local la = R.ankleOf(leg, f.landRel, fwdOf(f.landYaw), f.landPitch or 0)
					local lt = trueCF:PointToObjectSpace(V3(la.X, la.Y + f.lift, la.Z))
					local kn = moving and stanceKnee(0, run, lo.vh, prof) or standKnee
					-- (a landing spot far out of reach - a hard turn, a lunge - never drags the pelvis down for it)
					f.landNeed = min(0.22, R.needFor(rig, s, rootT, lt, R.slackFor(leg, kn, WALK_SOFT), WALK_DROP + 0.3))
					f.landWgt = smooth((u - 0.6) / 0.4)
					wCap = max(wCap, WALK_DROP + clamp(f.home.Y - f.landRel.Y, 0, 0.9))
				else
					f.landWgt = 0
				end
			end
		else
			-- a swinging foot may tuck (the IK bends the knee): planted feet pull the pelvis down, a
			-- landing foot starts to as it comes down (no pop when it plants)
			-- fighters keep their knees
			local slack = 0.965
			if not f.swing then
				local need = R.dropFor(rig, s, rootT, tgt, slack)
				-- (and last frame's, to see where it is heading: the toe-off goes a frame early, not late)
				f.needPrev = f.needDrop or need
				f.needDrop = need
				drop = max(drop, need)
			else
				f.needDrop, f.needPrev = 0, 0
				-- (measured at the touchdown spot: a reaching swing leg simply straightens)
				local u = (t - f.t0) / f.dur
				if u > 0.6 and f.landRel then
					local la = R.ankleOf(leg, f.landRel, fwdOf(f.landYaw), f.landPitch or 0)
					local lt = trueCF:PointToObjectSpace(V3(la.X, la.Y + f.lift, la.Z))
					drop = max(drop, R.dropFor(rig, s, rootT, lt, slack) * smooth((u - 0.6) / 0.4))
				end
			end
		end
	end
	-- a fighter sinks at once (a planted foot is never dragged) and rises gently (no pelvis pumping);
	-- a walker or runner never plunges: his pelvis drop is capped and rate-limited (the foot that
	-- would need more toes off early instead, above)
	if walking then
		-- (no foot on the ground - a runner's flight: the pelvis rises toward the pose's height, and the
		-- landing foot reaches for the ground as it comes down: lowest at mid-stance, highest in the air)
		local free = 0
		local base = wNeed or free
		local tgtD = base
		for _, s in ipairs(SIDES) do
			local f = rig.foot[s]
			if f.swing and (f.landWgt or 0) > 0 then
				tgtD = max(tgtD, lerp(base, f.landNeed, f.landWgt))
			end
			-- (a foot that just toed off lets the pelvis go over a moment, not in one frame: the bottom of
			-- the step is round)
			-- (it carries on the way it was going and eases to a stop: no V at the bottom of the step)
			if f.swing and f.liftNeed and t - f.t0 < WALK_RELEASE and run < 0.5 then
				local e = t - f.t0
				local g = f.liftNeed + 0.35 * (f.liftRate or 0) * (e - e * e / (2 * WALK_RELEASE))
				local k = smooth(e / WALK_RELEASE)
				tgtD = max(tgtD, lerp(g, base, k * k))
			end
		end
		-- (each planted foot's excess: how far under the other planted leg's wish it would hold the
		-- pelvis; a runner's also against the landing foot - a walker always waits for the heel strike)
		for _, s in ipairs(SIDES) do
			local f = rig.foot[s]
			f.excess = 0
			if not f.swing and f.needDrop then
				local o = rig.foot[s == "L" and "R" or "L"]
				if not o.swing and o.needDrop then
					f.excess = f.needDrop - (o.needLoad or o.needDrop)
				elseif o.swing and (o.landWgt or 0) > 0.5 and run > 0.5 then
					f.excess = f.needDrop - o.landNeed
				end
			end
		end
		drop = clamp(tgtD, -WALK_RAISE, moving and wCap or 0.75)
		-- (a critically damped spring, its speed capped: the pelvis eases into and out of a dip, never
		-- a V that turns round in one frame - nor a jolt when he stops and his knees unlock)
		-- (it comes down quickly - a planted foot must stay reachable - and a runner's rises more softly when
		-- his leg lets go: no pelvis jolt at the take-off)
		local v0 = lo.dropV or 0
		local x0 = lo.drop
		local x, v = K.spring2(x0, v0, drop, drop > x0 and 28 or lerp(26, 20, run), 1, dt)
		v = clamp(v, -DROP_RATE * 1.6, DROP_RATE * 1.6)
		-- (as the trailing foot toes off, a walker's body coming down is caught by the leading leg over a
		-- moment - its upward acceleration bounded, about a third of g - so the bottom of each step is
		-- round; a pelvis still sinking only bends the knees a touch more. A runner's legs push hard)
		local lastOff = max(rig.foot.L.t0, rig.foot.R.t0)
		local catch = (t - lastOff < WALK_RELEASE and run < 0.5) and WALK_CATCH or 1e9
		if v < v0 - catch * dt then
			v = v0 - catch * dt
			x = x0 + v * dt
		end
		lo.drop, lo.dropV = x, v
	else
		lo.dropV = 0
		drop = min(drop, 0.75)
		if drop > lo.drop then
			lo.drop = drop
		else
			lo.drop += (drop - lo.drop) * (1 - exp(-dt * 6))
		end
	end
	if abs(lo.drop) > 1e-3 then
		rootT = CF(0, -lo.drop, 0) * rootT
	end
	-- (a walker's narrow soft-reach band, eased in / out when the gait kind changes: no knee pop)
	lo.softK += ((walking and WALK_SOFT or 0.06) - lo.softK) * (1 - exp(-dt * 6))
	local soft = lo.softK
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		R.solveLeg(rig, p, s, rootT, targets[s], targets[s .. "yaw"], targets[s .. "pitch"], f.kneeS, soft)
	end
	return rootT
end

-- far away (no foot IK): a cheap procedural stride in step with the gait (the gait keeps running here:
-- moving / phase / weight follow the speed, so the arms swing and a stopped walker stands), or bent
-- standing legs
-- a far leg's sweep at x = phase since its toe-off: it swings forward (and lifts), then sweeps back at a
-- constant rate through the stance so the foot stays put on the ground; the swing leaves and lands with
-- part of the stance's backward speed (the foot slows to the ground's speed before it lands)
local function farSweep(x, duty)
	local sw = 1 - duty
	if x < sw then
		local u = x / sw
		local m = -min(3.5, 1.4 * sw / duty)
		local u2, u3 = u * u, u * u * u
		return -(2 * u3 - 3 * u2 + 1) + (u3 - 2 * u2 + u) * m + (3 * u2 - 2 * u3) + (u3 - u2) * m, sin(PI * u)
	end
	return 1 - 2 * (x - sw) / duty, 0
end

-- a far boxer's (or a staggering man's) legs: as the fight build had them, on their own clock with a plain
-- sine swing (the gait state of a ring footwork is left for the near legs)
local function fighterFarLegs(p, rig, rootT, dt)
	local lo = rig.loco
	local g = rig.geo
	local len = g.legLen or 2.3
	local depth = max(0, -rootT.Position.Y)
	local a = math.acos(clamp(1 - depth / len, -1, 1))
	local v = lo.speed
	local k = (lo.moving and rig.gaitKind) and smooth((v - 0.4) / 1.2) or 0
	if k > 0 then
		local cad = v < 6 and (1.55 + 0.09 * v) or (2.33 + 0.062 * min(v, 30))
		lo.farPh = ((lo.farPh or 0) + dt / min(2 / cad, 0.85)) % 1
	end
	local ph = 2 * PI * (lo.farPh or 0)
	local s, c = sin(ph), cos(ph)
	local swing = (0.22 + 0.025 * min(v, 20)) * k
	local fold = (0.3 + 0.9 * (lo.run or 0)) * k
	p.LH = A(a + swing * s, 0, 0)
	p.RH = A(a - swing * s, 0, 0)
	p.LK = A(-2 * a - fold * max(0, c), 0, 0)
	p.RK = A(-2 * a - fold * max(0, -c), 0, 0)
	p.LA = A(a - swing * s * 0.5, 0, 0)
	p.RA = A(a + swing * s * 0.5, 0, 0)
end

function AnimLoco.farLegs(p, rig, rootT, t, dt)
	local lo = rig.loco
	if rig.gaitKind ~= "walk" then
		fighterFarLegs(p, rig, rootT, dt)
		return
	end
	if lo.gaitT ~= t then
		updateGait(rig, t, dt)
	end
	local g = rig.geo
	local len = g.legLen or 2.3
	local depth = max(0, -rootT.Position.Y)
	local a = math.acos(clamp(1 - depth / len, -1, 1))
	local v = lo.speed
	local k = lo.gaitW * smooth((v - 0.4) / 1.2)
	local duty = clamp(lo.duty or 0.6, 0.15, 0.7)
	local run = lo.run or 0
	-- the stance foot travels v * duty * T under the hip: the thigh sweeps that arc (about the hip-to-sole
	-- length), in the direction of travel (backward and sideways steps too)
	local Lh = max(1, soleLeg(g) - depth)
	local half = clamp(v * duty * (lo.T or 0.6) / (2 * Lh), 0, 0.62)
	-- (this already follows the speed: no ramp, or a far start skates while the gait weight comes in)
	local th = math.asin(half) * smooth((v - 0.2) / 0.6)
	local lv = lo.lv
	local dx, dz = 0, -1
	if lv and v > 0.3 then
		dx, dz = lv.X / v, lv.Z / v
	end
	local fx, fz = -dz * th, dx * th
	-- the knee folds while the leg swings through (more for runners)
	local fold = (0.5 + 0.9 * run) * k
	local sl, ll = farSweep(lo.phase % 1, duty)
	local sr, lr = farSweep((lo.phase - 0.5) % 1, duty)
	local hl, hr = a + fx * sl, a + fx * sr
	local kl, kr = -2 * a - fold * ll, -2 * a - fold * lr
	p.LH = A(hl, 0, fz * sl)
	p.RH = A(hr, 0, fz * sr)
	p.LK = A(kl, 0, 0)
	p.RK = A(kr, 0, 0)
	-- (the feet stay level with the ground)
	p.LA = A(-(hl + kl), 0, -fz * sl)
	p.RA = A(-(hr + kr), 0, -fz * sr)
	lo.armPhase = lo.phase - (1 - duty)
end

-- planting starts after keyed legs (a get-up, a landing, leaving a seat): each foot starts where the
-- keyed legs left it and steps home from there, instead of sliding over to its stance spot
function AnimLoco.seedFeet(rig, t)
	local g = rig.geo
	if not (g.ok and g.jc0 and g.jc0.Root) then
		return
	end
	local p = rig.seedP or {}
	rig.seedP = p
	for _, k in ipairs(R.KEYS) do
		local j = rig.joints[k]
		p[k] = j and j.cur or CFrame.identity
	end
	local out = R.fk(rig, p, rig.seedOut or {})
	rig.seedOut = out
	local rc = rig.root.CFrame
	for _, s in ipairs(SIDES) do
		local key = s .. "A"
		local fcf = out[key]
		local f = rig.foot[s]
		if fcf then
			-- the ankle joint (the foot part's frame back through the ankle's C1) and the foot's pitch
			-- (+ heel up about the ball): P is put where the exact roll model has this ankle, so the foot
			-- keeps its contact point while it settles flat
			local leg = g[s]
			local ankW = rc:PointToWorldSpace((fcf * g.jc1i[key]:Inverse()).Position)
			local look = rc:VectorToWorldSpace(fcf.LookVector)
			local th = math.asin(clamp(-look.Y, -0.9, 0.9))
			local yaw = atan2(-look.X, -look.Z)
			local F = V3(-sin(yaw), 0, -cos(yaw))
			local P = ankW - (R.ankleOf(leg, ZERO, F, th))
			local groundW = rc:PointToWorldSpace(V3(0, g.groundY, 0)).Y
			f.P = V3(P.X, groundW, P.Z)
			f.yawW = yaw
			f.swing, f.curLift, f.want = false, 0, false
			f.pitchS = th
			f.lastStep = t
			f.dropH = nil
			f.slopeP = 0
			-- a foot the keyed legs left off the canvas (the back foot of a kneel) is not planted in
			-- the air: it comes down in a short step from where it is, onto its stance spot
			local up = ankW.Y - groundW - leg.ah
			if up > 0.1 then
				startSwing(f, t, clamp(0.12 + up * 0.25, 0.14, 0.3), 0.04, "shuffle")
				f.dropH = up
			end
		end
	end
end

-- the feet stop being managed (keyed legs): forget the planted state
function AnimLoco.release(rig)
	rig.foot.L.P, rig.foot.R.P = nil, nil
	rig.foot.L.swing, rig.foot.R.swing = false, false
	rig.loco.drop = 0
end

return AnimLoco
