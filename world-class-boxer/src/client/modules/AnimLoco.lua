-- AnimLoco: locomotion and feet for the procedural Animator.
--  * senses the root's real motion every frame (velocity / acceleration / turn rate from the root's
--    own position, so server-moved NPCs, PivotTo glides and replicated players all work; teleports
--    reset, server nudges glide)
--  * gait cycles synced to that velocity: walk -> jog -> run -> sprint outside the ring (cadence and
--    stride from speed, duty factor, heel strike -> roll -> toe-off, pelvis bob / sway / rotation,
--    shoulder counter-rotation, arm swing), boxing footwork inside it (step-drag shuffle where the
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
	}
end

function AnimLoco.init(rig)
	rig.foot = rig.foot or { L = AnimLoco.newFoot(), R = AnimLoco.newFoot() }
	rig.loco = {
		pos = nil, vel = ZERO, acc = ZERO, lv = ZERO, la = ZERO, speed = 0, yaw = 0, yawRate = 0,
		moving = false, moveT = 0, stopT = -10, phase = 0, T = 0.5, duty = 0.6, lead = "L",
		offL = 0, offR = 0.5, swL = 0.4, swR = 0.4,
		leanP = 0, leanPV = 0, leanR = 0, leanRV = 0, inP = 0, inPV = 0, drop = 0,
		gaitW = 0, armPhase = 0, stride = 0, run = 0, jumpOff = nil, jumpYaw = 0,
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
		return
	end
	local d = p - lo.pos
	local raw = V3(d.X, 0, d.Z) / dt
	-- a server nudge / pivot teleport (PivotTo a stud or two away in one frame): the body glides
	-- there instead of popping, and no velocity spike reaches the gait (the feet step after it)
	local flatD = V3(d.X, 0, d.Z).Magnitude
	if flatD > max(0.9, lo.speed * dt * 3 + 0.5) then
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
	-- the physics velocity is a good hint for client-simulated characters (no frame jitter)
	local av = root.AssemblyLinearVelocity
	local phys = V3(av.X, 0, av.Z)
	if phys.Magnitude > raw.Magnitude * 0.6 and phys.Magnitude < raw.Magnitude * 1.6 + 1 then
		raw = raw:Lerp(phys, 0.5)
	end
	local k = 1 - exp(-dt * 20)
	local vel = lo.vel + (raw - lo.vel) * k
	local acc = (vel - lo.vel) / dt
	lo.acc = lo.acc + (acc - lo.acc) * (1 - exp(-dt * 9))
	lo.vel = vel
	lo.speed = vel.Magnitude
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

local function walkParams(v, legLen)
	-- cadence (steps per second) and the per-foot cycle
	local cad = v < 6 and (1.55 + 0.09 * v) or (2.33 + 0.062 * min(v, 30))
	-- starting / slow: quick short steps (the second foot must not wait half a second)
	local T = min(2 / cad, 0.85)
	-- duty factor: walk ~0.6, run ~0.35, sprint ~0.27; never a contact longer than the leg can sweep
	local run = smooth((v - 5) / 4)
	local duty = lerp(0.62 - 0.008 * v, 0.36 - 0.004 * max(0, v - 9), run)
	duty = min(duty, legLen * lerp(1.0, 0.95, run) / max(0.1, v * T))
	duty = clamp(duty, 0.22, 0.66)
	return T, duty, run
end

-- the gait's per-frame phase / parameters (call once per frame before the feet)
local function updateGait(rig, t, dt)
	local lo = rig.loco
	local kind = rig.gaitKind
	local v = lo.speed
	if kind == nil or not rig.plant then
		lo.moving = false
		lo.gaitW += (0 - lo.gaitW) * (1 - exp(-dt * 8))
		return
	end
	local was = lo.moving
	if lo.moving then
		if v < MOVE_OFF then
			lo.moving = false
			lo.stopT = t
		end
	elseif v > MOVE_ON then
		lo.moving = true
		lo.moveT = t
	end
	lo.gaitW += ((lo.moving and 1 or 0) - lo.gaitW) * (1 - exp(-dt * 7))
	if not lo.moving then
		return
	end
	local g = rig.geo
	local legLen = g.ok and g.legLen or 2.4
	local dir = lo.lv.Magnitude > 1e-3 and lo.lv.Unit or V3(0, 0, -1)
	if kind == "walk" then
		local T, duty, run = walkParams(v, legLen)
		lo.T, lo.duty, lo.run = T, duty, run
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
		local S = clamp(0.3 + 0.19 * v, 0.45, 2.8)
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
	-- momentum: lean into acceleration and speed, settle back with overshoot when stopping
	local fwdV, fwdA, latA = -lo.lv.Z, -lo.la.Z, lo.la.X
	local walking = kind == "walk"
	local tgtP = clamp(-(walking and 0.006 or 0.004) * fwdV * w - 0.012 * fwdA, -0.3, 0.2)
	local tgtR = clamp(0.008 * latA - 0.01 * lo.speed * lo.yawRate * (walking and 1 or 0.4), -0.25, 0.25)
	lo.leanP, lo.leanPV = K.spring2(lo.leanP, lo.leanPV, tgtP, 9, 0.55, dt)
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
		local v = lo.speed
		if walking then
			local run = lo.run
			-- L swings during [0, 1 - duty), lands at 1 - duty; mid-stance at 1 - duty / 2
			local landL = 1 - duty
			local midL = 1 - duty * 0.5
			local c2 = cos(4 * PI * (ph - midL))
			-- walking: highest over the stance leg (inverted pendulum); running: lowest there, and the
			-- whole body rides a little lower on bent knees
			local bobA = lerp(0.045 + 0.01 * v, 0.05 + 0.003 * v, run) * amp
			-- (a runner touches down on a slightly bent knee: ~7 % of the leg lower than standing)
			local legL = rig.geo.ok and rig.geo.legLen or 2.4
			rootY = (lerp(bobA * c2, -bobA * c2 + bobA * 0.6, run) - 0.07 * legL * run) * w
			-- sway over the stance leg
			rootX = -lerp(0.07, 0.025, run) * amp * cos(2 * PI * (ph - midL)) * w
			-- pelvis rotation (the swing leg's hip goes forward), shoulders counter-rotate
			local c1 = cos(2 * PI * (ph - landL))
			local pyA = lerp(0.09, 0.14, run) * amp
			yawP = -pyA * c1 * w
			wYaw = pyA * 1.7 * c1 * w
			-- the swing side's hip drops a little (pelvic obliquity)
			rollP += -lerp(0.04, 0.025, run) * cos(2 * PI * (ph - midL)) * w
			-- the head stays level and on its line
			nYaw = -(yawP + wYaw) * 0.85
			lo.armPhase = ph - landL
		else
			-- footwork: a small rise on the push-off, settle on the landing; quicker / bouncier at speed
			local up = sin(2 * PI * ph)
			rootY = (0.035 + 0.02 * lo.run) * up * w * amp
			lo.armPhase = ph
		end
	end
	-- stopping: knees absorb, pelvis dips and comes back up
	if not lo.moving and kind then
		local el = t - lo.stopT
		if el < 0.45 then
			rootY -= 0.07 * K.attackDecay(el, 0.12, 0.45) * min(1, lo.stride / 1.2)
		end
	end
	return rootX, rootY, yawP, rollP, pitchP, wYaw, wPitch, wRoll, nYaw
end

-- arm swing for walking / running (outside the ring): writes the shoulders / elbows; k = blend
function AnimLoco.armSwing(p, rig, k)
	local lo = rig.loco
	if k <= 0.01 then
		return
	end
	local run = lo.run
	local v = lo.speed
	local c = cos(2 * PI * lo.armPhase)
	local amp = lerp(0.32 + 0.03 * v, 0.5 + 0.01 * v, run)
	local out = 0.07 + 0.12 * R.bulkOf(rig)
	local el = lerp(0.3, 1.45, run)
	-- runners drive the elbows back past the hip: the swing is centred a little behind
	local base = lerp(0.05, -0.12, run)
	-- left arm back when the left leg is forward (c = 1 at the left foot's landing)
	local l = -amp * c
	local r = amp * c
	-- the elbow closes as the hand comes forward (and across a touch), opens on the back swing
	local inL, inR = max(0, l) * 0.15 * run, max(0, r) * 0.15 * run
	p.LS = p.LS:Lerp(A(base + l, 0, -out + inL), k)
	p.RS = p.RS:Lerp(A(base + r, 0, out - inR), k)
	p.LE = p.LE:Lerp(A(el + max(0, l) * 0.4 - max(0, -l) * 0.35 * run, 0, 0), k)
	p.RE = p.RE:Lerp(A(el + max(0, r) * 0.4 - max(0, -r) * 0.35 * run, 0, 0), k)
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

-- world ground point under the ankle at home (+ body-space offset)
local function homeOf(rig, s, rootCF, ox, oz)
	local f = rig.foot[s]
	local leg = rig.geo[s]
	local sx = s == "L" and -1 or 1
	local a = leg.ankle0
	return rootCF:PointToWorldSpace(V3(a.X + sx * f.x + ox, rig.geo.groundY, a.Z + f.z + oz))
end

local function startSwing(f, t, dur, liftH, kind)
	f.swing = true
	f.t0 = t
	f.dur = max(0.08, dur)
	f.fromP = f.P
	f.fromYaw = f.yawW
	f.liftH = liftH
	f.cur, f.curYaw, f.curLift = f.P, f.yawW, 0
	f.liftPitch = f.pitchS
	f.stepKind = kind
	f.want = false
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
	updateGait(rig, t, dt)
	local moving = lo.moving and kind ~= nil
	local walking = kind == "walk"
	-- a runner's heel kick scales with the leg
	local runLegK = (g.ok and g.legLen or 2.45) / 2.45
	local legLen = g.legLen
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
		f.home = homeOf(rig, s, rootCF, ox, oz)
		f.homeYaw = rootYaw + f.yaw
		if not lock or f.free or not f.P or lo.teleported then
			f.P, f.yawW, f.swing, f.curLift = f.home, f.homeYaw, false, 0
			f.pitchS = f.heel
			f.want = false
		end
	end
	-- moving gait: lift each foot when its phase window opens (or as soon as it may, inside it)
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
			if f.want and not f.swing then
				local x = (lo.phase - off) % 1
				if x <= sw then
					-- the other foot must be down (or about to land) unless running / galloping
					local overlap = walking or lo.run > 0.3 or (o.swing and o.t0 + o.dur - t < 0.035)
					if not o.swing or overlap then
						local liftH
						if walking then
							liftH = lerp(0.2 + 0.015 * speed, min(1.1, 0.25 + 0.04 * speed) * runLegK, lo.run)
						elseif kind == "stagger" then
							liftH = 0.12 + 0.02 * speed
						else
							liftH = (0.1 + 0.025 * speed) * rig.liftK
						end
						startSwing(f, t, (sw - x) * lo.T, liftH, kind)
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
			if err > 5 then
				f.P, f.yawW = f.home, f.homeYaw -- teleported (Poser.Place, PivotTo)
			elseif f.vNow then
				if s == "L" then
					needL = 99
				else
					needR = 99
				end
			elseif reach > legLen * 0.84 then
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
		if not f.swing and (not o.swing or urgent or (t - o.t0) > o.dur * 0.55) and t - f.lastStep > 0.05 then
			local dur = f.vNow and f.vDur or clamp(0.24 - speed * 0.015, 0.12, 0.24) * rig.stepTime
			local liftH = f.vNow and f.vLift or clamp(0.1 + speed * 0.012, 0.08, 0.3) * rig.liftK
			local sk = f.vNow and "req" or (urgent and "reach" or "fix")
			if urgent and moving and kind then
				-- a foot left behind by an accelerating body joins the gait (lands with its lead)
				dur = max(0.12, (1 - lo.duty) * lo.T * 0.8)
				liftH = walking and lerp(0.2 + 0.015 * speed, min(1.1, 0.25 + 0.04 * speed) * runLegK, lo.run) or liftH
				sk = kind
			end
			startSwing(f, t, dur, liftH, sk)
			f.vNow = false
		end
	end
	-- the heel / pivot / knee specs come from the pose and acts frame by frame: low-pass them so an
	-- interrupted act never makes a foot jump
	local fk = 1 - exp(-dt * 26)
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		f.heelS += (f.heel - f.heelS) * fk
		f.pivotS += (f.pivot - f.pivotS) * fk
		f.kneeS += (f.knee - f.kneeS) * fk
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
					-- walkers plant half a contact ahead of the hip; runners land closer under the body
					-- and push off further behind it
					lead = lo.duty * lo.stride * lerp(0.5, 0.37, lo.run)
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
			-- footwork: the feet never come closer side by side than FOOT_GAP (no crossing, no clipping)
			if fight then
				local oP = o.swing and o.cur or o.P
				if oP then
					local lt = rootCF:PointToObjectSpace(tgt)
					local lo2 = rootCF:PointToObjectSpace(oP)
					local gap = FOOT_GAP * (kind == "stagger" and 0.6 or 1)
					if s == "L" and lt.X > lo2.X - gap then
						lt = V3(lo2.X - gap, lt.Y, lt.Z)
						tgt = rootCF:PointToWorldSpace(lt)
					elseif s == "R" and lt.X < lo2.X + gap then
						lt = V3(lo2.X + gap, lt.Y, lt.Z)
						tgt = rootCF:PointToWorldSpace(lt)
					end
				end
			end
			local landYaw = f.homeYaw
			-- the touchdown spot as seen from where the body is now (for the pelvis height)
			f.landRel = tgt - vel * remain - V3(acc.X, 0, acc.Z) * (0.5 * remain * remain)
			f.landYaw = landYaw
			if u >= 1 then
				f.swing, f.P, f.yawW, f.lastStep, f.curLift = false, V3(tgt.X, f.home.Y, tgt.Z), landYaw, t, 0
				f.landT = t
				f.pitchS = f.curPitch
			else
				-- horizontal travel: zero speed at lift-off and touchdown (the foot leaves and meets the
				-- canvas without a skid); runners cruise and brake late (no hovering reach ahead)
				local e = K.smoother(u)
				if sk == "walk" and lo.run > 0.01 then
					e = lerp(e, K.cruise(u), lo.run)
				end
				local pos = f.fromP:Lerp(tgt, e)
				f.cur = V3(pos.X, f.home.Y, pos.Z)
				f.curYaw = f.fromYaw + K.wrap(landYaw - f.fromYaw) * e
				-- the arc: walking peaks mid-swing; running kicks the heel up early behind the body,
				-- then the knee unfolds as the foot reaches forward. A smooth skewed bump
				-- u^a (1-u)^b (zero slope at lift-off and touchdown: no knee snap)
				local a = sk == "walk" and lerp(2, 1.2, lo.run) or 2
				local b = sk == "walk" and lerp(2, 1.9, lo.run) or 2
				f.curLift = f.liftH * K.skewBump(u, a, b)
				-- foot roll through the swing: toe-off -> level -> landing attitude
				local landP, mid
				if sk == "walk" then
					landP = lerp(-0.28, 0.02, lo.run)
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
				f.sigma = sigma
				local strike = lerp(-0.28, 0.02, lo.run)
				local roll = strike * (1 - smooth(sigma / 0.18))
				local off2 = lerp(0.55, 0.75, lo.run) * smooth((sigma - lerp(0.6, 0.45, lo.run)) / lerp(0.4, 0.55, lo.run))
				want = roll + off2
			elseif moving then
				-- footwork: up on the balls just before the push-off
				local off = s == "L" and lo.offL or lo.offR
				local x = (lo.phase - off) % 1
				want = f.heelS + 0.25 * smooth((x - 0.82) / 0.18)
			end
			if t - f.spinT < 0.1 then
				want += 0.12
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
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		local leg = g[s]
		local P = f.swing and f.cur or f.P
		local yawW = f.swing and f.curYaw or f.yawW
		-- pivot on the ball: rotate the ground point about the ball by the act's pivot
		local pv = f.pivotS
		if abs(pv) > 1e-3 and not f.swing then
			local B = P + fwdOf(yawW) * leg.bz
			yawW += pv
			P = B - fwdOf(yawW) * leg.bz
		end
		local pitch = f.curPitch
		local lift = f.swing and f.curLift or 0
		local ank = R.ankleOf(leg, P, fwdOf(yawW), pitch) + V3(0, lift + f.lift, 0)
		-- into the TRUE root's space (the IK and rootT live there)
		local tgt = trueCF:PointToObjectSpace(ank)
		targets[s] = tgt
		targets[s .. "yaw"] = K.wrap(yawW - trueYaw)
		targets[s .. "pitch"] = pitch
		-- a swinging foot may tuck (the IK bends the knee): planted feet pull the pelvis down, a
		-- landing foot starts to as it comes down (no pop when it plants)
		-- walking legs straighten at heel strike / toe-off (little slack); fighters keep their knees
		local slack = walking and moving and 0.985 or 0.965
		if not f.swing then
			if walking and moving and f.sigma then
				-- the push-off leg is all but straight (the heel is up): no pelvis dip at toe-off
				slack = lerp(slack, 0.999, smooth((f.sigma - 0.55) / 0.35))
			end
			drop = max(drop, R.dropFor(rig, s, rootT, tgt, slack))
		else
			-- (measured at the touchdown spot: a reaching swing leg simply straightens)
			local u = (t - f.t0) / f.dur
			if u > 0.6 and f.landRel then
				local la = R.ankleOf(leg, f.landRel, fwdOf(f.landYaw), f.landPitch or 0)
				local lt = trueCF:PointToObjectSpace(V3(la.X, la.Y + f.lift, la.Z))
				drop = max(drop, R.dropFor(rig, s, rootT, lt, slack) * smooth((u - 0.6) / 0.4))
			end
		end
	end
	-- sink at once (a planted foot is never dragged), rise gently (no pelvis pumping)
	drop = min(drop, 0.75)
	if drop > lo.drop then
		lo.drop = drop
	else
		-- a runner's pelvis rides the geometry; a fighter's settles slowly (no pumping when he steps)
		local rise = (walking and moving) and lerp(9, 16, lo.run) or 6
		lo.drop += (drop - lo.drop) * (1 - exp(-dt * rise))
	end
	if lo.drop > 1e-3 then
		rootT = CF(0, -lo.drop, 0) * rootT
	end
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		R.solveLeg(rig, p, s, rootT, targets[s], targets[s .. "yaw"], targets[s .. "pitch"], f.kneeS)
	end
	return rootT
end

-- far away (no foot IK): a cheap procedural stride in step with the speed, or bent standing legs
function AnimLoco.farLegs(p, rig, rootT, dt)
	local lo = rig.loco
	local g = rig.geo
	local len = g.legLen or 2.3
	local depth = max(0, -rootT.Position.Y)
	local a = math.acos(clamp(1 - depth / len, -1, 1))
	local v = lo.speed
	local k = (lo.moving and rig.gaitKind) and smooth((v - 0.4) / 1.2) or 0
	if k > 0 then
		local T = walkParams(v, len)
		lo.farPh = ((lo.farPh or 0) + dt / T) % 1
	end
	local ph = 2 * PI * (lo.farPh or 0)
	local s, c = sin(ph), cos(ph)
	local run = lo.run or 0
	local swing = (0.22 + 0.025 * min(v, 20)) * k
	-- the knee folds while the thigh comes through (more for runners)
	local fold = (0.3 + 0.9 * run) * k
	p.LH = A(a + swing * s, 0, 0)
	p.RH = A(a - swing * s, 0, 0)
	p.LK = A(-2 * a - fold * max(0, c), 0, 0)
	p.RK = A(-2 * a - fold * max(0, -c), 0, 0)
	p.LA = A(a - swing * s * 0.5, 0, 0)
	p.RA = A(a + swing * s * 0.5, 0, 0)
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
			-- the ankle joint (the foot part's frame back through the ankle's C1), straight down to the canvas
			local ank = (fcf * g.jc1i[key]:Inverse()).Position
			local look = rc:VectorToWorldSpace(fcf.LookVector)
			f.P = rc:PointToWorldSpace(V3(ank.X, g.groundY, ank.Z))
			f.yawW = atan2(-look.X, -look.Z)
			f.swing, f.curLift, f.want = false, 0, false
			f.pitchS = 0
			f.lastStep = t
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
