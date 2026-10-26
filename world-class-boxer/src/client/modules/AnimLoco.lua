-- AnimLoco: locomotion and feet for the procedural Animator.
--  * senses the root's real motion every frame (velocity / acceleration / turn rate from the root's
--    own position, so server-moved NPCs, PivotTo glides and replicated players all work; teleports
--    reset, server nudges glide; a start from a standstill at a low frame rate is real motion)
--  * outside the ring, a real walk / jog / run / sprint: human gait numbers scaled to the rig's leg
--    (same Froude number): cadence, stride and duty factor from the ground speed (the feet never
--    slide), the gait a function of the speed (walk -> run with a short settle band, never stuck), heel
--    strike -> foot flat -> the push-off up onto the toes (knee bending, double support), a stance
--    knee designed per phase (nearly straight at heel strike, the loading flex, locked again by
--    mid-stance; a runner lands softly bent), the pelvis height following the legs at a walk (the bob,
--    lowest in double support) and bouncing as a spring-mass at a run (it sinks into each stance,
--    lowest at mid-stance, and falls freely - g - through the flight), pelvis rotation and drop,
--    shoulder counter-rotation, relaxed arms that hang from the shoulders and swing opposite the legs (a
--    runner's bent near 90, from beside the hip to the chest, close to the body; applied after the joint
--    filters, so they stay in step), lean from acceleration (not speed), a narrow track, the whole shoe
--    on the ground (ramps; stairs: on one tread, off the risers), toe-first backward steps, no crossed
--    feet when strafing, quiet arms sideways, pivot steps with a foot down in a hard turn, and a
--    personality per character (seed, body, style) so a crowd never walks in step
--  * a walker's swing is the ankle's own planned path, carried on from the push-off's last frame (the knee still
--    folding, the hip already flexing: no kick back, no foot hanging behind, no whip through), with the knee by
--    design (~60 a third of the way, opening evenly onto the heel strike) and the pelvis brought to where that
--    knee lands the heel; a weight-bearing knee never jumps (kneeGovern); one foot is always down at a walk, in a
--    turn and pulling up out of a run (a step that cannot wait hurries the foot in the air down first); the first
--    steps from rest are no longer than the pace's own; pulling up out of a run takes braking steps to where he
--    comes to rest; a diagonal turns the pelvis and legs toward the way he goes (the chest kept facing)
--  * boxing footwork inside the ring (step-drag shuffle where the
--    foot on the side of travel moves first and the other follows, a gallop at speed, the feet never
--    cross or touch), a short irregular stagger when dazed or stumbling
--  * planted feet: a foot on the ground is locked in the world (ground point + yaw); it rolls over its
--    real sole (the organic shoe's heel and toe spring, or the box's edges) with exact geometry
--    (AnimRig.ankleOf, on a slope too), spins pivot on the ball, so the contact point never slides or
--    sinks; the pelvis sinks when a foot would be out of reach, and a foot about to be out of reach
--    steps instead of being dragged
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
-- reachable, and never faster than DROP_RATE studs/s either way
local WALK_DROP, DROP_RATE = 0.38, 4
-- walkers: the pelvis follows the weight-bearing leg's designed knee, so it may also rise (up to WALK_RAISE)
-- over the pose's own height (stand()'s settle, a stop); their IK's soft-reach band (a share of the leg) is
-- narrow, so a walking knee straightens; a weight-bearing foot that would hold the pelvis more than
-- WALK_EXCESS under where the other leg wants it toes off early instead (no plunge into the double support);
-- WALK_GAP = the closest two walking feet come side by side (no scissoring when strafing); WALK_RELEASE /
-- WALK_CATCH: as a foot toes off, the pelvis coming down is caught by the other leg over a moment
local WALK_RAISE, WALK_SOFT, WALK_EXCESS, WALK_GAP, WALK_RELEASE, WALK_CATCH = 0.1, 0.0025, 0.06, 0.32, 0.12, 22
-- the least the swinging ankle passes to the side of the planted one in a hard turn's pivot steps (studs)
local TURN_GAP = 0.55
-- a side step (the pace across the legs' frame: Shift Lock, first person, a fighter's player circling): the most the
-- leading leg is abducted at its touchdown (rad), the soft knee
-- a side-stepping stance leg keeps (rad), the foot's lift as a share of the walk's / the run's, and the stance share
-- of the stride (slow .. brisk side step, the shuffle at a run: a short flight between its steps)
local SIDE_ABD, SIDE_KNEE = 22 * PI / 180, 14 * PI / 180
-- (and the most a side shuffle's foot in the air is abducted, rad)
local SIDE_ABD_AIR = 30 * PI / 180
local SIDE_LIFT, SIDE_LIFT_RUN = 0.35, 0.2
-- (the shuffle's crouch at a run: how far the pelvis keeps under the pose's height, studs)
local SIDE_CROUCH = 0.2
local SIDE_DUTY_SLOW, SIDE_DUTY, SIDE_DUTY_RUN = 0.62, 0.5, 0.32
-- (and how far into the cycle the trailing foot lands after the leading one: half, evenly, slow; brisk, a little
-- sooner - the side shuffle's step-close, a moment's float before the next step; at a run, a gallop's close right
-- behind the step)
local SIDE_LAG, SIDE_LAG_RUN = 0.42, 0.22
-- the most a walker's foot is turned against the way his legs face (rad: the hip's and the shin's rotation together;
-- a Humanoid's AutoRotate snaps the root a quarter or half turn in a tenth of a second - the planted foot pivots on its
-- ball, the one in the air turns with the leg, never a foot twisted round under the shin)
local TWIST_MAX = 1.0
-- real gait scaled to the rig: LREF = hip joint to sole of the reference 1.80 m boxer (studs); VH turns
-- studs/s into the m/s of a 0.9 m human leg at the same Froude number (so human numbers apply)
local LREF, VH = 3.06, 0.2793
-- the walk -> run switch and back (human-equivalent m/s; Froude ~0.5): a narrow band against flicker, and a
-- pace held inside it settles on the nearer gait within RUN_SETTLE s (the gait is a function of the speed:
-- never a jog stuck on after a sprint)
local RUN_ON, RUN_OFF, RUN_SETTLE = 2.12, 1.98, 0.35
-- the switch's default scale (rig.walkMax overrides: the ring walk's 1.45)
local WALK_MAX = 1.15
-- pulling up out of a run: the fastest the run -> walk blend may move while he still moves (per second: the
-- handover takes about a sixth of a second, never a frame or two - the pelvis, the head and the knees would
-- pop), and how quickly the braking follows the deceleration (1/s: from the frame's raw deceleration it would
-- switch the braking steps on in a single frame)
local RUN_BLEND_MAX, BRAKE_RATE = 6, 12
-- how quickly a runner's schedule catches up with a foot that toed off out of its turn (1/s: runSync)
local PHASE_SYNC = 14
-- a runner's swing: the foot's peak height over the ground (a share of the leg: RUN_LIFT + RUN_LIFT_V x the
-- human-equivalent m/s; ~0.36 of it at 16 studs/s, a person's heel at 4.5 m/s), the share of it a late hump keeps
-- over the ground for the touchdown, and the foot's speed along the ground as it meets it (a share of the body's)
local RUN_LIFT, RUN_LIFT_V, RUN_LIFT_LATE, RUN_LAND_V = 0.14, 0.05, 0.25, 0.45
-- the least bend a runner's swing knee keeps as the foot reaches for the ground (rad; a person's ~15-20 at touchdown)
local RUN_REACH_KNEE = 16 * PI / 180
-- gravity in the rig's studs (9.81 m/s^2 at the gait's Froude scale: VH and LREF): a runner's flight falls at it
local GRAV = 8.829 / (VH * VH * LREF)
-- a pushing foot (AnimLoco.feet): the most it rolls up onto the toes (rad), and how fast
local PUSH_MAX, PUSH_RATE = 1.1, 20
-- a walker's push-off rolls the boot up to WALK_TOE (rad, ~57 deg: a person's toe-off) and no further
local WALK_TOE = 1.0
local RAD = PI / 180
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
		gY = nil, gRay = -10, slopeP = 0, landSlope = 0, excess = 0, gShift = 0, fromSl = 0,
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
		lo.vel, lo.acc, lo.accF, lo.rawV, lo.yawRate, lo.speed = ZERO, ZERO, ZERO, nil, 0, 0
		lo.lv, lo.la, lo.dispV, lo.dirLast, lo.dirRate = ZERO, ZERO, nil, nil, 0
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
	-- (a yaw pop is a pivot teleport only past what a Humanoid's AutoRotate turns in one frame - it spins the root
	-- round at tens of rad/s on a change of direction, and on a long frame that is a big angle: the whole body must
	-- not be counter-turned and glided back after every WASD tap or hitch)
	local yawPop = max(0.6, 30 * dt)
	if flatD > max(0.9, lo.speed * dt * 3 + 0.5, phys.Magnitude * dt * 1.8 + 0.5) then
		lo.jumpOff = (lo.jumpOff or ZERO) - V3(d.X, 0, d.Z)
		lo.jumpYaw = (lo.jumpYaw or 0) + K.wrap(lo.yaw - yaw)
		raw = lo.vel
	else
		if abs(K.wrap(yaw - lo.yaw)) > yawPop then
			lo.jumpYaw = (lo.jumpYaw or 0) + K.wrap(lo.yaw - yaw)
		end
		if rig.isLocal then
			-- the local character is simulated on this client: its physics velocity is exact, its travel over the frame
			-- is not (the physics advances in whole 240 Hz steps while the frame's time wanders; read as travel / dt the
			-- speed jittered by a tenth or more a frame in Studio, and with it the gait's phase, lean and sway)
			raw = phys
		end
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
	if not rig.isLocal then
		-- [Studio] a server-owned character (every NPC: MoveTo / Glide on the server; another player's character too)
		-- reaches this client as replicated positions at ~20 Hz, interpolated: the root's travel frame to frame comes in
		-- bursts and holds, and read as travel / dt (even blended with the replicated AssemblyLinearVelocity, which lags
		-- and steps) the speed jumped 30-60 % from one frame to the next - the gait's phase, lean and arm swing shook
		-- with it (the "fast jitter" on NPCs). The measured velocity is the displacement filtered over 0.15 s (longer
		-- than a replication interval, shorter than a step), and when the server says where it is sending him - the
		-- model's Gait attribute (a Vector3: the intended world velocity, set with MoveTo / Glide), else the Humanoid's
		-- replicated MoveDirection x WalkSpeed - that intent sets the direction and the pace, believed only while the
		-- body really travels (a walker stopped by a wall, a seat or a door shows intent and no travel: measured wins)
		local km = 1 - exp(-dt / 0.15)
		local dv = lo.dispV or raw
		dv += (raw - dv) * km
		lo.dispV = dv
		local meas = dv
		-- and the body is DRAWN where the smoothed root is: the travel the replication step did not deliver this frame
		-- (or delivered three frames of at once) goes into the glide offset the feet and the Root joint already follow
		-- for a server nudge (lo.jumpOff: it decays at 9/s, so a steady error never accumulates) - the invisible
		-- HumanoidRootPart steps, the pelvis, legs and planted feet glide; without it the planted feet were suddenly a
		-- step further from the hips on every replication frame and the pelvis dipped to reach them (the NPC bob)
		local errT = V3(d.X, 0, d.Z) - dv * dt
		if errT.Magnitude > 1e-4 and errT.Magnitude < 1.5 then
			lo.jumpOff = (lo.jumpOff or ZERO) - errT
		end
		local a = rig.a
		local iv = a and a.Gait
		local intent
		if typeof(iv) == "Vector3" and iv.Magnitude > 0.2 then
			intent = V3(iv.X, 0, iv.Z)
		else
			local hum = rig.hum
			if hum and hum.Parent then
				local md = hum.MoveDirection
				local ws = hum.WalkSpeed
				if md.Magnitude > 0.1 and ws > 0.1 then
					intent = V3(md.X, 0, md.Z).Unit * ws
				end
			end
		end
		if intent then
			local is, ms = intent.Magnitude, meas.Magnitude
			local trust = clamp((ms / max(is, 0.1) - 0.25) / 0.35, 0, 1)
			local tv = intent.Unit * min(is, ms * 1.5 + 0.6)
			raw = meas:Lerp(tv, trust)
		else
			raw = meas
		end
	end
	local k = 1 - exp(-dt * 20)
	local vel = lo.vel + (raw - lo.vel) * k
	local acc = (vel - lo.vel) / dt
	lo.acc = lo.acc + (acc - lo.acc) * (1 - exp(-dt * 9))
	-- (and a quicker one, from the raw velocity: pulling up is seen within a frame or two)
	local ar = (raw - (lo.rawV or raw)) / dt
	lo.rawV = raw
	lo.accF = (lo.accF or ZERO) + (ar - (lo.accF or ZERO)) * (1 - exp(-dt * 25))
	-- (how fast the way he goes swings round, rad/s, held a moment: a strafe reversed through a standstill reads as the
	-- half turn it is, measured from the last way he was going)
	local dr = 0
	if vel.Magnitude > 0.5 then
		local u = vel.Unit
		local dl = lo.dirLast
		if dl then
			dr = math.acos(clamp(u:Dot(dl), -1, 1)) / dt
		end
		lo.dirLast = u
	end
	lo.dirRate = max(dr, (lo.dirRate or 0) * exp(-dt * 6))
	lo.vel = vel
	lo.speed = vel.Magnitude
	-- (vertical: a walker on a ramp or stairs; clamped so a teleport-sized hop never spikes it)
	lo.vy += (clamp(rig.isLocal and av.Y or d.Y / dt, -40, 40) - lo.vy) * (1 - exp(-dt * 8))
	if abs(lo.vy) > 0.5 then
		lo.vyT = rig.clock or 0
	end
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

-- a boxer's foot already in the air (a fight step, not a walker's) is sent on to a new body-relative spot
-- without a jump: the swing's start is re-based so the foot carries on from where it is and lands on the new
-- spot at the swing's own time. False (nothing changed) when the foot is down, walking, past half its
-- swing or going the other way: the caller asks for a step instead (request) once it is down
function AnimLoco.reaim(rig, s, ox, oz, hold, t)
	local f = rig.foot[s]
	local root = rig.root
	if not (f and f.swing and f.fromP and root) or f.stepKind == "walk" then
		return false
	end
	-- (only in the first half of the swing, and only further the way it is already going: a foot turned
	-- round mid-air, or rushed the last bit, would jerk the leg and the body over it)
	local e = K.smoother(clamp((t - f.t0) / f.dur, 0, 1))
	if e > 0.5 or not f.home then
		return false
	end
	local d = root.CFrame:VectorToWorldSpace(V3(ox - f.vox, 0, oz - f.voz))
	local way = f.home - f.fromP
	if d.X * way.X + d.Z * way.Z < 0 then
		return false
	end
	f.fromP -= V3(d.X, 0, d.Z) * (e / (1 - e))
	f.vox, f.voz = ox, oz
	f.vUntil = t + (hold or 0.3)
	f.vNow = false
	return true
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
	pr.width = st.width * (1 + 0.1 * r(5)) * (female and 0.86 or 1) * (1 + 0.12 * b)
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
	-- backward: shorter, quicker steps (sideways: the side step's own timing, updateGait)
	spm *= 1 + 0.2 * lo.back
	-- (a hard turn at speed: quick, short pivot steps)
	local T = 120 / clamp(spm, 70, 240) * (1 - 0.3 * (lo.turnK or 0))
	-- stance share of the stride: walking ~0.6 (a fifth of it in double support), running 0.4 (jog), 0.33 (4 m/s)
	-- .. 0.26 (sprint), as a person's; never a contact longer than the leg can sweep (the heel rise of the push-off
	-- reaches behind: a walker sweeps about his leg's length, more when brisk, a runner a little more; past
	-- that a walker takes up to 15 % quicker steps first - so does anyone stepping sideways - then shortens the
	-- stance, never into a flight: one foot is always down at a walk)
	local duty = lerp(0.685 - 0.053 * vh, 0.48 - 0.032 * vh, run)
	-- [Studio] the sweep is capped at 0.9 of the leg only through a hard turn (turnK: a Humanoid's AutoRotate snap, a
	-- reversal): the feet re-plant round the snapped root with shorter steps and the trailing foot is never dragged a
	-- stud behind (measured: the reversal's slide 1.7 -> 0.66 studs). Not on a straight walk: a permanent cap only
	-- quickened the cadence (0.85 -> 0.78 s), flattened the pelvis bob by a third and doubled the dip a 0.25 s hitch
	-- frame leaves. The legs "into the body" came from a leg measured at the wrong length and a floor at the wrong
	-- height - AnimRig.computeGeo measures the leg from the RigAttachment chain and the floor from HipHeight when the
	-- soles' bind height disagrees - not from the sweep
	local rf = clamp(0.66 + 0.26 * vh, 0.8, 1.2)
	local reach = Ls * lerp(lerp(rf, min(rf, 0.9), lo.turnK or 0), 1.05, run)
	if run < 0.5 and v * T * duty > reach then
		-- (a quick man's own tempo still shows when the reach sets the step: shorter, quicker steps; a slow
		-- one cannot step further than his legs reach)
		T = max(T * 0.87, reach / max(0.1, v * duty)) / max(1, prof.cad) ^ 0.8
	end
	duty = min(duty, reach / max(0.1, v * T))
	duty = clamp(duty, lerp(0.55, 0.22, run), 0.68)
	-- (in a hard turn one foot stays down)
	duty = lerp(duty, max(duty, 0.56), lo.turnK or 0)
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
		kr = lerp(lerp(13, 17, clamp((vh - 4.5) / 2.5, 0, 1)) * RAD, pk, smooth(sigma / 0.45))
	else
		kr = lerp(pk, 24 * RAD, smooth((sigma - 0.45) / 0.55))
	end
	return lerp(kw, kr, run)
end

-- a side step's stance knee: the walker's, never straighter than SIDE_KNEE (the knees stay soft stepping sideways)
local function sideKnee(k, side)
	return (side or 0) > 0 and lerp(k, max(k, SIDE_KNEE), side) or k
end

-- a walker's / runner's foot pitch through the stance (+ heel up, rolling over the toes; - toes up on the heel)
local function stancePitch(sigma, run, back, side)
	-- heel strike -> foot flat (a runner lands nearly flat; a backward step: toes -> heel down; a side step lands flat,
	-- on the inside of the foot - no heel strike rolling a foot that travels across its own line)
	local strike = lerp(lerp(lerp(-0.28, -0.1, run), 0.3, back), 0.02, side)
	local roll = strike * (1 - smooth(sigma / lerp(0.18, 0.15, run)))
	-- the heel rises from mid-stance (a walker's a little in the single support, then up onto the toes in the
	-- double support: the push-off) - the least it shows: a pushing foot rolls further when its leg needs it
	-- (AnimLoco.feet); backward the toes come up at the end and the foot leaves heel last
	local rise = lerp(0.2 * smooth((sigma - 0.45) / 0.38) + 0.55 * smooth((sigma - 0.8) / 0.2), 0.8 * smooth((sigma - 0.45) / 0.55), run)
	rise = lerp(rise, -0.25 * smooth((sigma - 0.7) / 0.3), back)
	-- (a side step pushes off the inside of the foot: the heel only a little up)
	return roll + rise * (1 - 0.6 * side)
end

-- the knee a pushing foot's leg is given (rad): a walker's straight leg bends into the toe-off (~40 deg), quicker
-- and quicker - still folding at ~350 deg/s as the toes leave, the swing carries that on - a runner's extends from
-- mid-stance to a soft 20 at the toe-off
local function pushKnee(sigma, run)
	return lerp(5 + 35 * clamp((sigma - 0.65) / 0.35, 0, 1) ^ 1.7, lerp(38, 22, smooth((sigma - 0.45) / 0.55)), run) * RAD
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
			-- (a reversal - D to A, a strafe's W to S - passes through a standstill for a frame or two: while the Humanoid
			-- still has somewhere to go the gait carries on through it, a fifth of a second at most, instead of stopping
			-- and starting again - the feet's schedule reset, the stop's dip, a pop of the legs)
			lo.slowT = lo.slowT or t
			local hum = rig.hum
			local md = hum and hum.Parent and hum.MoveDirection
			if not (md and md.Magnitude > 0.1 and t - lo.slowT < 0.2) then
				lo.moving = false
				lo.stopT = t
				-- (how hard he was going: the knees' dip on the stop)
				lo.stopV = lo.peakV or 0
			end
		else
			lo.slowT = nil
		end
	elseif v > MOVE_ON then
		lo.moving = true
		lo.moveT = t
	end
	lo.gaitW += ((lo.moving and 1 or 0) - lo.gaitW) * (1 - exp(-dt * 7))
	-- braking (a walker / runner pulling up): the deceleration along the way he was going, 0..1 from about a third of
	-- g at the rig's scale; a hard stop out of a run steps down to a walk at once (no flight while he brakes)
	if kind == "walk" then
		local hv = v > 0.3 and lo.vel / v or lo.brakeDir or ZERO
		lo.brakeDir = hv
		local af = lo.accF or lo.acc
		local bw = clamp((-(af.X * hv.X + af.Z * hv.Z) - 14) / 22, 0, 1)
		lo.brake = (lo.brake or 0) + (bw - (lo.brake or 0)) * (1 - exp(-dt * BRAKE_RATE))
	else
		lo.brake = 0
	end
	if not lo.moving or kind ~= "walk" then
		lo.legYaw = (lo.legYaw or 0) * exp(-dt * 6)
	end
	if not lo.moving then
		lo.sideK = 0
		if kind == "walk" then
			lo.runMode = false
			lo.run += (0 - lo.run) * (1 - exp(-dt * 12))
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
		-- a diagonal (the body kept facing - Shift Lock, first person - while he goes off at an angle): the pelvis and
		-- the legs turn toward the way he goes, up to ~43 deg, the chest stays (bodyOffsets): he walks the diagonal
		-- forward (or backward), not a crab's side shuffle; from ~70 deg off it is a side step
		-- (and never while the root turns: a turn is not a diagonal. The filtered velocity trails a Humanoid's snap turn
		-- by a quarter second, and read against the new facing it had the legs and pelvis turned 20-40 degrees toward
		-- the OLD way after every WASD tap, untwisting over half a second; gated on the yaw rate the legs follow the
		-- root round and the lag that is left when the turn is over is a few degrees)
		local al = v > 0.3 and atan2(lo.lv.X, -lo.lv.Z) or 0
		local be = abs(al) > PI / 2 and al - (al > 0 and PI or -PI) or al
		local lyT = clamp(be, -0.75, 0.75) * (1 - smooth((abs(be) - 0.95) / 0.4)) * clamp(1 - abs(lo.yawRate) / 4, 0, 1)
		-- (quicker while the way he goes swings round under a body that keeps facing - Shift Lock's W to D, a back-diagonal
		-- run into a side shuffle: the legs untwisting from the old way over half a second left the feet a stride behind)
		-- (not while the root itself swings round - AutoRotate's snap: the way he goes turns with it, the legs follow the root)
		local qk = clamp((lo.dirRate or 0) / 6, 0, 1) * clamp(1 - abs(lo.yawRate) / 3, 0, 1)
		lo.legYaw = (lo.legYaw or 0) + (lyT - (lo.legYaw or 0)) * (1 - exp(-dt * lerp(6, 20, qk)))
		-- forward / backward / sideways (in the legs' frame): the arms' swing and the backward step follow it
		local cy, sy = cos(lo.legYaw), sin(lo.legYaw)
		local lx, lz = lo.lv.X * cy + lo.lv.Z * sy, lo.lv.Z * cy - lo.lv.X * sy
		local fz = v > 0.3 and -lz / v or 1
		lo.fwd += (fz - lo.fwd) * (1 - exp(-dt * lerp(8, 20, qk)))
		lo.back = smooth((-lo.fwd - 0.25) / 0.45)
		local fx = v > 0.3 and abs(lx) / v or 0
		lo.side += (fx - lo.side) * (1 - exp(-dt * lerp(8, 20, qk)))
		-- walk or run: people switch at about Froude 0.5; hysteresis so a speed near it never flickers
		-- (a ring walk may stride out further before it breaks into a jog: rig.walkMax; anyone else a little past
		-- Froude 0.5 - WALK_MAX: the town's walking pace, 6.5 studs/s, is Froude ~0.5 for the shortest boxer's legs,
		-- and a 5 ft man pressing W jogged)
		local wm = rig.walkMax or WALK_MAX
		if vh >= RUN_ON * wm then
			lo.runMode, lo.bandT = true, 0
		elseif vh <= RUN_OFF * wm then
			lo.runMode, lo.bandT = false, 0
		else
			-- (inside the band: the nearer gait once the pace has stayed there a moment)
			lo.bandT = (lo.bandT or 0) + dt
			if lo.bandT > RUN_SETTLE then
				lo.runMode = vh > (RUN_ON + RUN_OFF) * 0.5 * wm
			end
		end
		if lo.brake > 0.3 then
			lo.runMode, lo.bandT = false, 0
		end
		local dRun = ((lo.runMode and 1 or 0) - lo.run) * (1 - exp(-dt * (7 + 20 * lo.brake)))
		if lo.moving then
			dRun = clamp(dRun, -RUN_BLEND_MAX * dt, RUN_BLEND_MAX * dt)
		end
		lo.run += dRun
		-- a hard turn at speed (a reversal): quick pivot steps with a foot always down, not a flying lunge
		local tk = clamp((abs(lo.yawRate) * v - 30) / 50, 0, 1)
		lo.turnK = max(tk, (lo.turnK or 0) - dt * 3)
		-- the way he goes swung round under a body that keeps facing (Shift Lock's A to D, W to A, a run's back-diagonal into
		-- a side shuffle): the feet in the air come down soon on their new spots (AnimLoco.feet) - timed and aimed for the
		-- old way, a run's swing landed 2-6 studs off where the body went and its leg hung splayed out across the floor
		local fk = clamp(((lo.dirRate or 0) * v - 40) / 40, 0, 1) * (1 - tk)
		lo.flipK = max(fk, (lo.flipK or 0) - dt * 4)
		local T, duty = walkTiming(lo, v, Ls, kL, vh, prof)
		-- a side step (the pace across the legs' frame): the foot on the side of travel steps out, the other closes up
		-- beside it - never past it - so neither leg swings fore and aft under a body going sideways. A stride carries
		-- each foot S = |lx| T across; the trailing foot lands lag of a cycle after the leading one, gap N from it, and
		-- with the leading foot landing sideA out from the pelvis and the trailing one sideB in on its own side the two
		-- sweep evenly about the pelvis:
		--   sideA = (lag S + N + duty S) / 2, sideB = (lag S + N - duty S) / 2
		-- the stride no longer than leaves the leading leg abducted SIDE_ABD at its touchdown (a brisk side step quickens
		-- rather than spreading the legs). Slow, it is an even step-close with both feet down between the steps; brisk,
		-- the close comes a little sooner; at Shift's pace a gallop - the close right behind the step, the push, a flight
		-- (each foot down ~0.1 s, the legs never spread a stud past the hips). [Studio] Before, a side step was the
		-- forward walk turned sideways: each foot swept 1.4 studs across under the body, the trailing leg left 2.2 studs
		-- out (abducted 42 degrees) and the leading one crossing under the pelvis, the knees folding to 69 and the pelvis
		-- bobbing a third of a stud; at 16 studs/s the legs splayed to 50-70 degrees
		local sk = smooth((lo.side - 0.3) / 0.55)
		lo.sideK, lo.sideV = sk, lx
		-- (the leading foot: the side he goes to, held through a reversal's standstill)
		if lx > 0.3 then
			lo.sideLead = "R"
		elseif lx < -0.3 then
			lo.sideLead = "L"
		end
		local vx = abs(lx)
		local lagT = lerp(0.5, lerp(SIDE_LAG, SIDE_LAG_RUN, lo.run), sk)
		local sN, sDuty
		if sk > 0 then
			local hx = g.ok and g.R.hip0 and abs(g.R.hip0.X) or 0.45
			sN = max(0.47, (g.ok and g.footW or 0.35) + 0.12)
			sDuty = lerp(lerp(SIDE_DUTY_SLOW, SIDE_DUTY, clamp((vh - 0.8) / 1.2, 0, 1)), SIDE_DUTY_RUN, lo.run)
			local aMax = hx + Ls * sin(SIDE_ABD)
			local Ts = min(T * 0.87, (2 * aMax - sN) / (lagT + sDuty) / max(vx, 0.1))
			T, duty = lerp(T, Ts, sk), lerp(duty, sDuty, sk)
		end
		-- (no two strides alike: the cadence drifts a few per cent, per walker)
		T *= 1 + 0.03 * K.noise1(t * 0.55 + lo.gseed % 97, 3.3)
		lo.T, lo.duty, lo.vh = T, duty, vh
		-- (the right foot's place in the cycle: half a cycle after the left's, or the side step's lag either way - eased
		-- over a few frames when the lead changes sides, never a jump of the schedule)
		local offT = lo.sideLead == "R" and 1 - lagT or lagT
		local offR = lo.offRS or 0.5
		offR = (offR + clamp((offT - offR + 0.5) % 1 - 0.5, -3 * dt, 3 * dt)) % 1
		lo.offRS = offR
		lo.offL, lo.offR = 0, offR
		if sk > 0 then
			local S = vx * T
			local lag = clamp(lo.sideLead == "R" and 1 - offR or offR, 0, 1)
			-- (never past the abduction's reach: a stride still the old pace's length as he goes off sideways)
			local aCap = 1.15 * ((g.ok and g.R.hip0 and abs(g.R.hip0.X) or 0.45) + Ls * sin(SIDE_ABD))
			lo.sideA, lo.sideB = min(aCap, (lag * S + sN + duty * S) * 0.5), clamp((lag * S + sN - duty * S) * 0.5, -0.5, aCap)
		end
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
		local was0 = lo.lead
		if dLead > 0.12 then
			lo.lead = "L"
		elseif dLead < -0.12 then
			lo.lead = "R"
		end
		-- (a change of direction: the new lead foot goes first - the schedule carried on, and the foot that now trails
		-- was the next one due, so a boxer going right then left dragged his right foot before he stepped with the left)
		if was and was0 and lo.lead ~= was0 and not fL.swing and not fR.swing then
			lo.phase = floor(lo.phase) + 1
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
			local ft = rig.foot[s]
			ft.cycle = floor(lo.phase - off)
			ft.want = false
			-- (a foot that stood since he stopped counts its stance from where the schedule has it - not as a stance
			-- long over: it would be rolled straight up onto its toes, the knee bent 25 degrees in one frame)
			if not ft.swing then
				local sw = s == "L" and lo.swL or lo.swR
				local sg = (((lo.phase - off) % 1) - sw) % 1 / max(0.05, 1 - sw)
				ft.sigT = t - clamp(sg, 0.3, 0.9) * (1 - sw) * lo.T
			end
		end
	end
	lo.phase += dt / lo.T
	-- (a runner's schedule catching up with a foot that toed off out of its turn: runSync)
	local pc = lo.phaseCorr or 0
	if pc ~= 0 then
		local d = abs(pc) < 1e-3 and pc or pc * (1 - exp(-dt * PHASE_SYNC))
		lo.phase += d
		lo.phaseCorr = pc - d
	end
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
		tgtP = clamp(-steady - 0.014 * fwdA, -0.2, 0.12)
	else
		tgtP = clamp(-0.004 * fwdV * w - 0.012 * fwdA, -0.3, 0.2)
	end
	-- jammed in on the other man (AnimFight's rig.jam: his hips inside 4.3 studs, 1 at the bodies' floor): no
	-- momentum lean of the chest INTO him - the forward lean fades out with the room, a lean back stays
	local jam = rig.jam
	if jam and jam > 0 and tgtP < 0 then
		tgtP = tgtP * (1 - min(1, jam))
	end
	-- (into a turn: about the centripetal tilt, atan(v w / g) - of a HELD turn. A Humanoid's AutoRotate spins the root
	-- round at tens of rad/s on every change of direction, many times any human turn, and swings its velocity with it
	-- (a lateral acceleration of 40-80 studs/s^2 for a tenth of a second); read raw, those banked the body 14 degrees
	-- on every WASD tap. A walker leans into the yaw rate clamped to a human's (4 rad/s) and the lateral push, both
	-- averaged over a quarter second: a snap turn passes as the pivot it is, a held turn - a curve, a stick held over -
	-- banks him; a boxer's footwork keeps the quick read, its sidesteps are its own)
	local yrH = clamp(lo.yawRate, -4, 4)
	local tgtR
	if walking then
		local ks = 1 - exp(-dt * 4)
		lo.turnS = (lo.turnS or 0) + (yrH - (lo.turnS or 0)) * ks
		lo.latS = (lo.latS or 0) + (clamp(latA, -25, 25) - (lo.latS or 0)) * ks
		-- ([Studio] the bank into a held curve stays under 4 degrees: a Humanoid's velocity swings with its AutoRotate
		-- snaps and the lateral push read off a replicated root is noisy; read as a lean it was "the body tilts")
		tgtR = clamp(0.008 * lo.latS - 0.006 * lo.speed * lo.turnS, -0.07, 0.07)
	else
		lo.turnS, lo.latS = 0, 0
		tgtR = clamp(0.008 * latA - 0.004 * lo.speed * yrH, -0.25, 0.25)
	end
	lo.leanP, lo.leanPV = K.spring2(lo.leanP, lo.leanPV, tgtP, walking and 11 or 9, 0.55, dt)
	lo.leanR, lo.leanRV = K.spring2(lo.leanR, lo.leanRV, tgtR, 9, 0.6, dt)
	-- the upper body's inertia: a nod forward when braking hard, then settle (a walker or runner braking leans
	-- back into it: only a little nod)
	local tgtI = walking and clamp(0.004 * fwdA, -0.07, 0.07) or clamp(0.01 * fwdA, -0.18, 0.18)
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
			-- sway over the stance leg (a little: the tier body's hips are its own width apart and the feet track
			-- nearly under them, so the weight shifts less than on a line walk; v8's 0.072 swung the whole figure)
			-- ([Studio] and never more than 0.03 studs either way - 0.06 peak to peak - whatever the body and the style:
			-- the pelvis offset is applied on the Root joint, so on a tall tier body it swung the whole figure)
			rootX = clamp(-lerp(0.03, 0.02, run) * amp * prof.pelvis * cos(2 * PI * (ph - midL)) * w, -0.03, 0.03)
			-- pelvis rotation (the stepping leg's hip goes with the step), shoulders counter-rotate
			local c1 = cos(2 * PI * (ph - landL)) * fw
			local pyA = lerp(0.075, 0.13, run) * amp * prof.pelvis
			yawP = -pyA * c1 * w
			-- (the thorax turns against the pelvis about as far again in the world: ~4 degrees each way at a walk, the
			-- shoulders' swing with the arms - a chest held square over a turning pelvis reads as a mannequin's)
			wYaw = pyA * lerp(1.95, 1.85, run) * c1 * w
			-- the swing side's hip drops (pelvic obliquity: ~4 degrees, the stance hip takes the weight)
			-- (the spine bends back over it: the chest stays level, so the obliquity rolls the pelvis only and never
			-- rocks the shoulders and head side to side about the hips)
			-- ([Studio] capped at 2 degrees either way: with the lean's bank that keeps the pelvis roll under 4 degrees at
			-- a walk - the obliquity rides the Root joint and a bigger one read as the body rocking side to side)
			local obl = clamp(-lerp(0.065, 0.05, run) * prof.pelvis * cos(2 * PI * (ph - midL)) * w, -0.035, 0.035)
			-- (low-passed at its source, so the pelvis roll and the chest's counter-roll stay one motion: a replicated
			-- root's phase steps never twitch the hips; dt-correct)
			local os_ = lo.oblS or obl
			os_ += (obl - os_) * (1 - exp(-dt * 14))
			lo.oblS = os_
			rollP += os_
			wRoll -= os_ * 0.9
			-- (a diagonal: the pelvis turned toward the way he goes, the chest kept facing)
			local ly = lo.legYaw or 0
			yawP -= ly
			wYaw += ly
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
	-- (the lead builds over a sixth of a second and lets go quicker: a Humanoid's snap turn is over before it is
	-- half way there, a held turn gets all of it - a head turned 15-17 degrees ahead, as a walker's, never the 29
	-- degrees past the way he now faces that a raw read of the snap left him looking)
	local yr = kind and yrH or 0
	lo.turnL += (yr - lo.turnL) * (1 - exp(-dt * (abs(yr) > abs(lo.turnL) and 6 or 10)))
	local tl = lo.turnL
	nYaw += clamp(0.17 * tl, -0.3, 0.3)
	wYaw += clamp(0.1 * tl, -0.18, 0.18)
	yawP += clamp(-0.05 * tl, -0.1, 0.1)
	-- (a hard turn at speed - a reversal: the hips lag behind the shoulders and the legs untwist from the planted
	-- foot as he pivots, instead of the pelvis spinning round over it and crossing the thighs; about as far as a
	-- walker's shoulders ever turn against his hips, whatever the root's rate)
	local tk = walking and lo.turnK or 0
	if tk > 0 then
		local lag = clamp(-0.06 * yrH, -0.24, 0.24) * tk
		yawP += lag
		wYaw -= lag
	end
	-- [Studio] the offsets that turn or roll the body on the Root joint are rate-limited frame to frame and the pelvis
	-- obliquity low-passed: a Humanoid's AutoRotate snaps the root's yaw tens of degrees in one frame and a replicated root
	-- steps, and the counter-rotations computed from that frame's read (the pelvis against the step, the chest against
	-- the pelvis, the head's lead) jumped with it - a twitch of the whole trunk on every WASD tap or replication step.
	-- (dt-correct: exp(-k dt) and rate x dt, never a per-frame fraction - a 240 Hz Studio frame is a quarter of a 60 Hz one)
	local function limited(key, v, rate)
		local prev = lo[key]
		if prev then
			local m = rate * dt
			v = prev + clamp(v - prev, -m, m)
		end
		lo[key] = v
		return v
	end
	yawP = limited("yawPS", yawP, 4)
	wYaw = limited("wYawS", wYaw, 4)
	nYaw = limited("nYawS", nYaw, 4)
	if walking then
		rollP = clamp(rollP, -0.1, 0.1)
	else
		lo.oblS = nil
	end
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
--  jog / run: the elbow bent near 90 and pumping a little (65 -> 95): the hand swings from beside the hip
--  (behind it on the back swing) to the lower chest, close in to the body, the forearm brushing the
--  torso's line as it comes across
--  sprint: -60..+40, elbow ~60 -> 95 (the back swing opens: the hand well behind the hip)
------------------------------------------------------------------------
local function armShape(lo, prof)
	local vh = lo.vh or 0
	-- (the arms change between a walker's and a runner's carriage at their own pace: a run pulled up into a walk
	-- in a few frames never throws them)
	local run = lo.armRun or lo.run
	local swing = prof.swing
	local cw, aw = -(5 + 2 * vh), 5 + 9 * vh
	-- (a relaxed walker's elbow never hangs locked: ~15 at the back of the swing, ~45 at the front at the town pace)
	local ebw, efw = 9 + 3.5 * vh, 16 + 15 * vh
	local cr, ar = -(15 + 0.5 * vh), 27 + 5 * min(vh, 5)
	local ebr, efr = 67 - vh, 86 + vh
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
	-- arms hang close: out just enough for big lats / arms to clear the hips (a runner's elbows tucked in by
	-- his ribs)
	local b = R.bulkOf(rig)
	-- (a heavy man's hang out round his lats only a little: at a walk his hands pass by his thighs, not out in space)
	local out = lerp(0.015 + 0.045 * b, 0.01 + 0.05 * b, lo.run) + prof.out
	p.LS = p.LS:Lerp(A(c, 0, -out), k)
	p.RS = p.RS:Lerp(A(c, 0, out), k)
	p.LE = p.LE:Lerp(A(em, 0, 0), k)
	p.RE = p.RE:Lerp(A(em, 0, 0), k)
end

-- a walker's loose wrist (AnimLoco.armOffsets): the hand's flex against the forearm as a damped spring (~2 Hz) driven
-- by the forearm's swing (th = its swing angle, rad): the hand lags the forearm's acceleration. Sub-stepped so a long
-- frame never throws it; w = the swing's weight (the flop fades with it)
local WRIST_W, WRIST_Z, WRIST_MAX = 2 * PI * 2.1, 0.45, 0.32
local function wristFlop(lo, s, th, dt, w)
	local kT, kV, kH, kHV = "wT" .. s, "wTV" .. s, "wH" .. s, "wHV" .. s
	local th0 = lo[kT]
	if th0 == nil or dt <= 0 then
		lo[kT], lo[kV], lo[kH], lo[kHV] = th, 0, 0, 0
		return 0
	end
	local v = (th - th0) / dt
	local acc = clamp((v - lo[kV]) / dt, -400, 400)
	lo[kT], lo[kV] = th, v
	local h, hv = lo[kH], lo[kHV]
	local n = math.ceil(dt / (1 / 120))
	local sdt = dt / n
	for _ = 1, n do
		hv += (-WRIST_W * WRIST_W * h - 2 * WRIST_Z * WRIST_W * hv - 0.8 * acc) * sdt
		h += hv * sdt
	end
	h = clamp(h, -WRIST_MAX, WRIST_MAX)
	lo[kH], lo[kHV] = h, hv
	return h * min(1, w * 1.5)
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
	lo.armRun = (lo.armRun or lo.run) + (lo.run - (lo.armRun or lo.run)) * (1 - exp(-dt * 6))
	if w < 0.005 then
		lo.pSL, lo.pSR, lo.pEL, lo.pER = nil, nil, nil, nil
		lo.wTL, lo.wTR = nil, nil
		return nil
	end
	local prof = profileOf(rig)
	local _, a, eb, ef = armShape(lo, prof)
	-- (a hard turn's pivot steps: the arms swing in close, never thrown wide by the body turning under them)
	a *= 1 - 0.45 * (lo.turnK or 0)
	local fw = lo.fwd
	-- (the arm is furthest back when the same side's thigh is furthest forward: at a walker's heel strike;
	-- a runner's thigh drives through earlier, two thirds into the swing)
	local ph = 2 * PI * (lo.phase - (1 - lo.duty) + prof.lag + 0.35 * (1 - lo.duty) * lo.run)
	local cs = cos(ph)
	-- (the forearm trails the upper arm: overlapping action)
	local ce = cos(ph - lerp(0.35, 0.22, lo.run))
	-- pulling up and stopping - and walking backward - the gait's clock does not say where the legs are: the arms go
	-- with the feet themselves (the left arm back as the left foot is ahead), always against the legs
	local sk = max(lo.brake or 0, 1 - lo.gaitW, lo.back or 0)
	lo.armStop = (lo.armStop or 0) + (sk - (lo.armStop or 0)) * (1 - exp(-dt * 12))
	if lo.armStop > 0.01 and rig.foot.L.P and rig.foot.R.P then
		local rc = rig.root.CFrame
		local fL, fR = rig.foot.L, rig.foot.R
		local zL = rc:PointToObjectSpace(fL.swing and fL.cur or fL.P).Z
		local zR = rc:PointToObjectSpace(fR.swing and fR.cur or fR.P).Z
		local cf = clamp((zR - zL) / max(1, 0.45 * (lo.stride or 2)), -1, 1)
		cs = lerp(cs, cf, lo.armStop)
		ce = lerp(ce, cf, lo.armStop)
	end
	-- (no two people swing alike: one arm a little bigger, per seed; hashed once per rig)
	local asym = lo.swingAsym
	if not asym then
		asym = (K.rand3(rig.seed or 0, 5.1, 2.7) - 0.5) * 0.18
		lo.swingAsym = asym
	end
	-- (walking backward they swing nearly as much, still against the legs - the leg behind, the same arm in
	-- front: led by the feet, below; sideways a little still, fore-aft and out with the side step)
	local sideK = lo.side * (1 - lo.run)
	local dirA = (fw >= 0 and fw or -0.75 * fw) + 0.2 * sideK * (1 - abs(fw))
	local sA = a * dirA * w
	local eA = (ef - eb) * 0.5 * dirA * w
	local sL = -sA * (1 + asym) * cs
	local sR = sA * (1 - asym) * cs
	local eL = -eA * ce
	local eR = eA * ce
	-- a runner's forearm comes across toward the body's line as it swings forward (the upper arm turned in,
	-- the elbow in by the ribs): the hand reaches the lower chest in front of the body, never out wide
	-- (a big man's arms hang out round a wide chest: they turn in further)
	local b = R.bulkOf(rig)
	local inK = (0.35 + 0.15 * b) * lo.run
	local tw = (0.28 + 0.5 * b) * lo.run * w * max(0, fw)
	-- (a bulky walker's arms turned in a little all through the swing: the forearms hang by the thighs)
	local twW = 0.16 * b * (1 - lo.run) * w
	local yL, yR = -tw * max(0, -cs) - twW, tw * max(0, cs) + twW
	local sway = 0.07 * sideK * w * cs
	-- (and never faster than ~650 deg/s: a hard turn, a pull-up or a gait change eases the swing over instead of
	-- flinging an arm)
	local m = 11.5 * dt
	sL = (lo.pSL or sL) + clamp(sL - (lo.pSL or sL), -m, m)
	sR = (lo.pSR or sR) + clamp(sR - (lo.pSR or sR), -m, m)
	eL = (lo.pEL or eL) + clamp(eL - (lo.pEL or eL), -m, m)
	eR = (lo.pER or eR) + clamp(eR - (lo.pER or eR), -m, m)
	lo.pSL, lo.pSR, lo.pEL, lo.pER = sL, sR, eL, eR
	-- the hands ride the swing loosely: each wrist a damped spring the forearm's swing drives (the hand trails the
	-- forearm as it changes direction, follows through as it stops), a few degrees in a glove, never stiff
	local wL, wR = wristFlop(lo, "L", sL + eL, dt, w), wristFlop(lo, "R", sR + eR, dt, w)
	return sL, eL, inK * max(0, sL) + sway, sR, eR, -inK * max(0, sR) + sway, yL, yR, wL, wR
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
	f.gY, f.gRay, f.gShift, f.fromSl = nil, -10, 0, f.slopeP or 0
	-- (a walker's swing is planned from the push-off's last frame when its ankle is first wanted: rebaseSwing)
	f.planNew = true
	f.pushOn = false
	f.retimed = false
	f.reachOff = nil
	f.aimW = nil
end

-- a walker's swing (walk pace) is planned as the ankle's own path, carried on from the push-off's last frame:
-- where the ankle was, the speed the toe roll gave it and the knee still folding at its own rate (no frame where
-- the leg straightens back, no foot hanging behind), on to the heel strike with the knee by design
-- (f.aP0 / aV0 / aT0: the ankle's world position, velocity and time the plan starts from; k0 / kv0: the knee and
-- its rate per unit of the plan; kDone: the knee's peak is behind it - a plan re-based late in the swing)
local function rebaseSwing(f, t, kDone)
	if not (f.ankW and f.ankT and t - f.ankT < 0.1) then
		f.plan = false
		return
	end
	local D = max(1 / 60, f.t0 + f.dur - f.ankT)
	f.aP0, f.aT0 = f.ankW, f.ankT
	-- (never faster than it could travel the whole step in the time left: a frame's spike is not carried on)
	local v = f.ankV or ZERO
	local vm = v.Magnitude
	local cap = 3 + 2 * ((f.tgtW or f.ankW) - f.ankW).Magnitude / D
	f.aV0 = vm > cap and v * (cap / vm) or v
	f.k0 = f.kAct or 0.4
	f.kv0 = clamp(f.kVel or 0, -12, 12) * D
	f.kDone = kDone
	f.plan = true
end

-- a swing hurried (or its end moved) to land rem seconds from now, carrying on from where it is: the swing's
-- progress u stays, a planned one re-based from the ankle as it is (past its knee's peak: it opens from there)
local function retime(f, t, rem)
	local u0 = clamp((t - f.t0) / f.dur, 0, 0.95)
	f.dur = max(1 / 60, rem) / (1 - u0)
	f.t0 = t - u0 * f.dur
	if f.plan then
		rebaseSwing(f, t, u0 > 0.3)
	end
end

-- [Studio] a runner's foot that toes off away from the start of its swing window (the pelvis has left it out of
-- reach early, or it held on late: the walk's feet as Shift takes the pace from 6.5 to 16 in a frame, the pace still
-- blending, a hitch, a curve) takes the swing its pace has and the schedule follows it - its phase eased to that
-- foot's lift-off (lo.phaseCorr, over ~0.15 s; forward up to half a cycle, back up to half) and the other foot, in the
-- air, retimed to land half a cycle from this one's touchdown (alternating steps again within the stride). Timed to
-- the schedule's next touchdown instead, the swing ran on for 0.7-0.8 s (a whole stride: one foot hanging in the air,
-- the steps uneven for a second after every change of pace). Returns the swing's duration and the cycle it belongs
-- to, or nil (a walker, pulling up, or a foot leaving on time: the schedule's own)
local function runSync(rig, s, off, sw, t)
	local lo = rig.loco
	local x = (lo.phase + (lo.phaseCorr or 0) - off) % 1
	local c = x > 0.5 and 1 - x or -x
	if lo.run < 0.5 or (lo.brake or 0) > 0.3 or abs(c) < 0.04 then
		return nil
	end
	lo.phaseCorr = (lo.phaseCorr or 0) + c
	local o = rig.foot[s == "L" and "R" or "L"]
	if o.swing and (lo.turnK or 0) < 0.3 then
		-- (the other foot's touchdown: its own place in the cycle - half a cycle on, or a side step's lag; a side shuffle's
		-- foot in the air is only ever hurried down by it - the gallop's close is due right after the step, and timed to
		-- the schedule a foot caught out of turn hung in the air for most of a stride)
		local oOff = s == "L" and lo.offR or lo.offL
		local rem = ((oOff - off + sw) % 1) * lo.T
		local orem = o.t0 + o.dur - t
		if rem > 0.06 and abs(orem - rem) > 0.02 and ((lo.sideK or 0) < 0.5 or rem < orem) then
			retime(o, t, rem)
		end
	end
	return sw * lo.T, floor(lo.phase + lo.phaseCorr - off + 1e-6)
end

-- the swing's knee by design (rad) at u (0 = the plan's start .. 1 = heel strike): from the knee the push-off left,
-- still folding at its own rate, on to the peak (kpk) a third of the way, then opening evenly to the heel strike's
-- nearly straight knee (kEnd) a little before the touchdown; a plan re-based past its peak opens from where it is
local function swingKnee(f, u, kpk, kEnd)
	local sp, se = 0.3, 0.9
	if f.kDone then
		sp, kpk = 0, f.k0
	end
	if u < sp then
		local x = u / sp
		local k0 = f.k0
		-- (a tangent that never overshoots the peak)
		local m = clamp(f.kv0 * sp, 0, 3 * max(0, kpk - k0))
		local x2 = x * x
		local x3 = x2 * x
		return k0 * (2 * x3 - 3 * x2 + 1) + m * (x3 - 2 * x2 + x) + kpk * (3 * x2 - 2 * x3)
	elseif u < se then
		local x = (u - sp) / (se - sp)
		if f.kDone then
			-- (re-based while opening: carries on at the rate it had)
			local m = clamp(f.kv0 * se, min(0, 3 * (kEnd - kpk)), 0)
			local x2 = x * x
			local x3 = x2 * x
			return kpk * (2 * x3 - 3 * x2 + 1) + m * (x3 - 2 * x2 + x) + kEnd * (3 * x2 - 2 * x3)
		end
		return lerp(kpk, kEnd, smooth(x))
	end
	return kEnd
end

-- the planned ankle this frame, as the path alone has it (the root's space): a Hermite from the start's position
-- and velocity to the landing ankle A1 (world; arriving at rest); the leg's length the designed knee wants is kept
-- in f.planD for liftPlan
local function planAnkle(rig, f, s, t, trueCF, rootT, hipP, A1, soft, kpk, kEnd)
	local lo = rig.loco
	local leg = rig.geo[s]
	local D = max(1 / 60, f.t0 + f.dur - f.aT0)
	local u = clamp((t - f.aT0) / D, 0, 1)
	local u2 = u * u
	local u3 = u2 * u
	-- (the path's own height carries no speed up and comes down to the landing ankle's by mid-swing: the knee's
	-- design lifts the foot; the path only keeps the shoe - as it is pitched now - a little off the floor, and lands it)
	local v0 = f.aV0
	local P = f.aP0 * (2 * u3 - 3 * u2 + 1) + V3(v0.X, 0, v0.Z) * (D * (u3 - 2 * u2 + u)) + A1 * (3 * u2 - 2 * u3)
	local yb = A1.Y + (f.aP0.Y - A1.Y) * (1 - smooth(u / 0.5))
	local gY = lerp(f.fromP.Y, f.tgtW.Y, smooth(u))
	-- (the heel comes down onto the floor as the foot arrives, on a glide of about 14 degrees: it touches at the
	-- landing spot, never skims the last of the step along the floor - a heel skid of a quarter stud over the
	-- four frames before the plant)
	local rx, rz = A1.X - P.X, A1.Z - P.Z
	local glide = min(0.12, 0.25 * sqrt(rx * rx + rz * rz)) * smooth(u / 0.35)
	-- (and the toe comes up off the floor as it leaves - never scuffs forward along it for the first frames)
	local leave = 0.08 * smooth(min(1, u / 0.12)) * (1 - smooth((u - 0.25) / 0.25))
	-- (a side step lands flat - no heel glide: the sole stays a little up until the last frames, set down on its spot
	-- rather than on the floor a frame early with the last of the step still to go)
	local hover = 0.04 * (lo.sideK or 0) * (1 - smooth((u - 0.88) / 0.12))
	local yf = gY + R.ankleOf(leg, ZERO, fwdOf(f.curYaw or 0), f.curPitch or 0).Y + max(0.05 * K.skewBump(u, 1.2, 1.6), glide, leave, hover)
	P = V3(P.X, max(yb, yf), P.Z)
	-- (a quick step - hurried, or a short one - folds the knee less)
	kpk = max(f.k0 or 0, kpk * clamp(D / 0.3, 0.45, 1))
	f.planD = R.slackFor(leg, swingKnee(f, u, kpk, kEnd), soft) * (leg.l1 + leg.l2)
	f.planU, f.planT = u, t
	local Ph = trueCF:PointToObjectSpace(P)
	-- (from mid-swing the pelvis is brought to where the designed knee puts the foot on its path: the knee opens
	-- onto the heel strike as designed, never bent by a pelvis too low or locked by one too high - f.planNeed)
	f.planNeed = u > 0.45 and R.needFor(rig, s, rootT, Ph, f.planD / (leg.l1 + leg.l2), WALK_DROP + 0.3, hipP) or nil
	return Ph
end

-- the planned ankle raised where the designed knee (f.planD) puts it higher under the hip as it is (hipP, the
-- root's space; called again once the pelvis's drop is final - near straight a centimetre of pelvis is many
-- degrees of knee): the knee folds on behind the body, then opens as the foot reaches forward; a foot the plan
-- has out of reach for that knee is brought in a little (it lands a frame late rather than the knee slamming
-- straight on it)
local function liftPlan(f, Ph, hipP)
	local d, u = f.planD, f.planU
	local dx, dz = Ph.X - hipP.X, Ph.Z - hipP.Z
	local h2 = dx * dx + dz * dz
	local hm = d * 0.995
	if h2 > hm * hm then
		local k = hm / sqrt(h2)
		dx, dz, h2 = dx * k, dz * k, hm * hm
	end
	local y = Ph.Y
	local e = hipP.Y - sqrt(d * d - h2) - y
	-- (a smooth max: no kink in the leg's motion where the knee's height takes over; exact at the start and the
	-- touchdown)
	local k = 0.06 * min(1, u / 0.25) * (1 - smooth((u - 0.8) / 0.15))
	y += 0.5 * (e + sqrt(e * e + k * k))
	return V3(hipP.X + dx, y, hipP.Z + dz)
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

-- where along F (0..x) the floor under pos leaves the plane (y, slope tn): a step's edge, between a and b
-- (bisection; no hit = the root's floor)
local function edgeAt(rig, pos, floorY, F, y, tn, x)
	local a, b = 0, x
	for _ = 1, 5 do
		local m = (a + b) * 0.5
		local ym = groundAt(rig, pos + F * m, floorY, F) or floorY
		if abs(ym - (y + m * tn)) < 0.06 then
			a = m
		else
			b = m
		end
	end
	return a, b
end

-- the floor under a walker's whole landing shoe: the height and slope under the ankle (nil: the root's
-- floor), and how far to move the spot along F so that the whole sole is on one tread: never into the riser
-- of a step, never landing or rolling over the nosing in mid-air (the nearer of stopping short of the edge
-- and going onto the next step)
local function footGround(rig, leg, pos, floorY, F)
	local y, sl = groundAt(rig, pos, floorY, F)
	local y0, tn = y or floorY, math.tan(sl or 0)
	local tx, hx = leg.toeX or 0.5, leg.heelX or 0.2
	local sh
	local yt = groundAt(rig, pos + F * tx, floorY, F) or floorY
	if abs(yt - (y0 + tx * tn)) > 0.08 then
		local a, b = edgeAt(rig, pos, floorY, F, y0, tn, tx)
		local stay, go = a - tx - 0.05, b + hx + 0.05
		sh = go < -stay and go or stay
	else
		local yh = groundAt(rig, pos - F * hx, floorY, F) or floorY
		if abs(yh - (y0 - hx * tn)) > 0.08 then
			local a, b = edgeAt(rig, pos, floorY, -F, y0, -tn, hx)
			local stay, go = hx - a + 0.05, -(b + tx + 0.05)
			sh = -go < stay and go or stay
		end
	end
	if not sh then
		return y, sl or 0, 0
	end
	-- (the new spot's own floor: the same tread, or the next one)
	local y2, sl2 = groundAt(rig, pos + F * sh, floorY, F)
	return y2, sl2 or 0, sh
end

-- a walker's weight-bearing knee never jumps: near straight a millimetre of the pelvis is degrees of knee, so at a
-- heel strike (the leg suddenly carrying the body over it) or a change of support the pelvis gives way - or holds
-- up - only as fast as the knee may change its rate (KNEE_ACC rad/s^2): the knee bends into the loading over a few
-- frames instead of in one. Returns the drop x kept inside what every such knee allows
local KNEE_ACC = 200
local function kneeGovern(rig, rootT, targets, x, far, t, dt)
	local g = rig.geo
	local lo, hi = -1e9, 1e9
	local a = KNEE_ACC * dt
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		local tgt = targets[s]
		-- (a foot taking the weight: the heel strike's loading)
		if not f.swing and not f.push and f.kAct and f.ankT and tgt and t - f.landT < 0.25 then
			local leg = g[s]
			local hipP = (g.rootC0 * rootT * leg.rootHip).Position
			local kv = f.kVel or 0
			-- (it may always slow down: the bound only keeps it from setting off, or speeding up, in a jolt - never
			-- forces it on)
			local kHi = f.kAct + (max(kv, 0) + a) * dt
			local kLo = f.kAct + (min(kv, 0) - a) * dt
			local nHi = R.needFor(rig, s, rootT, tgt, R.slackFor(leg, clamp(kHi, 0, 2.5), WALK_SOFT), far, hipP)
			if nHi < far - 1e-3 then
				hi = min(hi, nHi)
			end
			if kLo > 0.02 then
				local nLo = R.needFor(rig, s, rootT, tgt, R.slackFor(leg, min(kLo, 2.5), WALK_SOFT), far, hipP)
				if nLo < far - 1e-3 then
					lo = max(lo, nLo)
				end
			end
		end
	end
	if lo > hi then
		return x
	end
	return clamp(x, lo, hi)
end

-- how far a planted foot's ankle, the foot rolled to pitch th, is from the hip (the root's space)
local function ankleDist(leg, P, F, lift, rootCF, hip, th, sl)
	return (rootCF:PointToObjectSpace(R.ankleOf(leg, P, F, th, sl) + V3(0, lift, 0)) - hip).Magnitude
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
	local legLen = g.legLen
	-- a walker's track: the feet land well inside the hips' width (a person's ~10 cm apart walking, nearly on one
	-- line running), not under the hip joints like pillars (sideways the side step keeps them apart)
	local kx = 1
	if walking then
		-- (pulling up, the braking steps already land at the width he will stand at: no shuffle sideways after)
		-- (a big man walks and runs on a wider track: his thick thighs pass, not through each other)
		local bk = clamp((R.bulkOf(rig) - 0.4) / 0.6, 0, 1)
		local kw = lerp(lerp(0.42 + 0.17 * bk, 0.27 + 0.36 * bk, run), 0.85, lo.side) * prof.width
		-- (never so narrow that the feet - the boots over them - overlap or the thighs rub through each other: the
		-- muscle-tier legs hang their own width apart; a runner's track may come a little closer)
		if g.ok and g.hipW and g.hipW > 0.1 then
			kw = max(kw, (g.footW * 1.12 + 0.1) / g.hipW * lerp(1, 0.88, run))
		end
		kx = 1 - (1 - clamp(kw, 0.2, 1)) * lo.gaitW * (1 - (lo.brake or 0))
	end
	-- per-foot desired ground point and yaw
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		-- voluntary offset expired: come back home with a step. (Not while that foot is in the air: a swing
		-- aims at the home point every frame, and moving it mid-step would jump the foot; and a long way
		-- back - a short fighter's big step in - takes a step its size, never a long one flicked in 0.16 s)
		if f.vUntil < t and (f.vox ~= 0 or f.voz ~= 0) and not f.swing then
			local d = sqrt(f.vox * f.vox + f.voz * f.voz)
			f.vox, f.voz = 0, 0
			f.vNow = true
			f.vDur = clamp(0.1 + 0.14 * d, 0.16, 0.3)
			f.vLift = 0.1
		end
		local ox, oz = f.ox + f.vox, f.oz + f.voz
		-- (a walker's legs in their own frame: turned toward a diagonal's way - updateGait's legYaw)
		local ly = walking and lo.legYaw or 0
		local legCF = ly ~= 0 and rootCF * A(0, -ly, 0) or rootCF
		rig.legCF = legCF
		f.home = homeOf(rig, s, legCF, ox, oz, kx)
		f.homeYaw = rootYaw - ly + f.yaw + (walking and (s == "L" and prof.toe or -prof.toe) or 0)
		if not lock or f.free or not f.P or lo.teleported then
			f.P, f.yawW, f.swing, f.curLift = f.home, f.homeYaw, false, 0
			f.pitchS = f.heel
			f.want = false
			f.slopeP = 0
		end
	end
	-- moving gait: lift each foot when its phase window opens (or as soon as it may, inside it)
	-- (low, quick pivot steps in a hard turn)
	-- ([Studio] a runner's by the leg and the human pace: 0.3 + 0.055 x studs/s - 1.3 studs at 16, half the leg - had
	-- the knee folded to 135 and the thigh raised to the horizontal on every stride)
	local walkLift = lerp(0.2 + 0.015 * speed, (RUN_LIFT + RUN_LIFT_V * (lo.vh or 4)) * (legLen or 2.45), run) * (1 - 0.75 * (lo.turnK or 0))
	-- (a side step skims: the hip lifts the leg out, the knee only softly bent)
	local sideK = walking and lo.sideK or 0
	walkLift *= lerp(1, lerp(SIDE_LIFT, SIDE_LIFT_RUN, run), sideK)
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
					-- the other foot must be down (or about to land) unless running / galloping - and in a hard
					-- turn: one foot stays on the floor and pivots while the other steps round
					local hard = (lo.turnK or 0) > 0.3
					-- (never at a walk - nor pulling up out of a run: one foot is always down, the lift waits for the
					-- other to land)
					local wr = walking and ((lo.run < 0.5 and back < 0.5 and lo.side < 0.6) or (lo.brake or 0) > 0.3)
					local overlap = (lo.run > 0.3 and not hard and not wr) or (o.swing and o.t0 + o.dur - t < (wr and 0.005 or 0.035))
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
						if hard then
							dur = min(dur, 0.2)
						end
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
			local leg = g[s]
			-- (a walker's planted foot is never left turned against his legs past TWIST_MAX: as the root snaps round it
			-- pivots on its ball - about the sole's toe once the heel is up: AnimRig.toeContact)
			if walking then
				local tw = K.wrap(f.yawW - f.homeYaw)
				if abs(tw) > TWIST_MAX then
					-- (about whatever is on the floor: the heel of a foot just struck, rolled back onto it; else the ball, the heel
					-- coming up off the floor first and the foot turning as it does - a pivot about the ball with the heel down
					-- dragged the heel round across the floor, one with the sole flat scraped the toe)
					local ps = f.pitchS or 0
					local rate = 30 * dt
					local bz
					if ps < -0.02 then
						bz = -(leg.heelX or 0.2)
					else
						ps = min(0.16, ps + 10 * dt)
						f.pitchS = max(f.pitchS or 0, ps)
						bz = R.toeContact(leg, ps)
						rate *= smooth((ps - 0.02) / 0.1)
					end
					local B = f.P + fwdOf(f.yawW) * bz
					f.yawW -= clamp(tw - (tw > 0 and TWIST_MAX or -TWIST_MAX), -rate, rate)
					f.P = B - fwdOf(f.yawW) * bz
					f.spinT = t
				end
			end
			local yerr = abs(K.wrap(f.yawW - f.homeYaw))
			local hip = (walking and rig.legCF or rootCF):PointToWorldSpace(leg.hip0)
			local hx, hz = f.P.X - hip.X, f.P.Z - hip.Z
			local reach = sqrt(hx * hx + hz * hz)
			-- (a walker's foot left so far behind that it would hold the pelvis well under where the other
			-- leg carries it toes off now: no plunge, no dragged toe)
			local tooFar
			if walking then
				-- (and whatever the other foot does, a foot behind the body that would drag the pelvis down a long
				-- way - an explosive start, a hard turn - goes now: never the leading foot that just took the weight)
				-- (or a foot the pelvis can no longer bring within reach: it would be dragged - it steps; a
				-- pushing foot, once even its toes cannot reach)
				local nd = f.needDrop or 0
				tooFar = moving and (((f.sigma or 0) > 0.6 and back < 0.5 and (f.excess or 0) > lerp(WALK_EXCESS, 0.05, run))
					or ((f.sigma or 1) > 0.5 and (run > 0.5 or not rig.foot[s == "L" and "R" or "L"].swing)
						and nd + max(0, nd - (f.needPrev or nd)) > lerp(0.22, 0.32, run))
					or (nd - lo.drop > 0.06 and t - f.lastStep > 0.15)
					or (f.reachShort or 0) > 0.02)
				-- (a side step's foot the body has carried past its lift-off - the leading one under the pelvis toward the
				-- other, the trailing one further out than the leading one lands - steps now: after a change of direction the
				-- feet stand where the old way left them, and waiting for the schedule the leading foot was swept a stud under
				-- the body past the other one's side)
				if moving and sideK > 0.5 and lo.sideA and t - f.lastStep > MIN_STANCE then
					local px = (rig.legCF or rootCF):PointToObjectSpace(f.P).X * (lo.sideLead == "L" and -1 or 1)
					local lead = (s == "R") == (lo.sideLead ~= "L")
					tooFar = tooFar or (lead and px < -0.3) or (not lead and px < -(lo.sideA + 0.35))
				end
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
			elseif reach > legLen * (f.push and 1.05 or 0.84) or tooFar then
				if s == "L" then
					needL = 50 + reach
				else
					needR = 50 + reach
				end
			else
				-- spin on the ball for small turns instead of stepping
				if yerr > 0.08 and err < rig.stepDist * 0.8 and (not moving or (lo.turnK or 0) > 0.3) then
					local want = K.wrap(f.homeYaw - f.yawW)
					local step = clamp(want, -dt * 3.2, dt * 3.2)
					-- (about the ball while the foot is flat; once the heel is up the weight is on the sole's toe
					-- where the roll model has it touching - a fighter's pivot turns on that, or the boot's tip
					-- skated round 0.6 studs out from the ball: AnimRig.toeContact)
					local bz = R.toeContact(leg, f.pitchS or 0)
					local B = f.P + fwdOf(f.yawW) * bz
					f.yawW += step
					f.P = B - fwdOf(f.yawW) * bz
					f.spinT = t
					yerr = abs(K.wrap(f.yawW - f.homeYaw))
				end
				-- (a walker just pulled up stands a moment as his braking steps left him - a little staggered - before
				-- he squares his feet)
				local limit = moving and (walking and 0.9 * lo.stride + 0.6 or rig.stepDist + 0.6 * lo.stride)
					or rig.stepDist * ((walking and t - lo.stopT < 1.2) and 1.7 or 1)
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
		-- (in a hard turn only a foot about to be dragged goes while the other is in the air: one foot pivots on the
		-- floor)
		local hardTurn = (lo.turnK or 0) > 0.5
		-- (a walker - or a runner pulling up - never has both feet in the air: a step that cannot wait hurries the
		-- foot in the air down first, then goes)
		local free = not o.swing or urgent or (not hardTurn and (t - o.t0) > o.dur * 0.55)
		if walking and o.swing and ((run < 0.5 and back < 0.5 and lo.side < 0.6) or (lo.brake or 0) > 0.3) then
			local orem = o.t0 + o.dur - t
			-- (only a foot the body has already left out of reach even on its toes goes at once: never dragged)
			free = orem < 0.005 or (f.reachShort or 0) > 0.04
			-- (sooner pulling up: the foot waiting is being left behind fast)
			local hurry = (lo.brake or 0) > 0.3 and 0.04 or 0.07
			if not free and urgent and orem > hurry then
				retime(o, t, hurry)
			end
		end
		if not f.swing and free and t - f.lastStep >= MIN_STANCE then
			local dur = f.vNow and f.vDur or clamp(0.24 - speed * 0.015, 0.12, 0.24) * rig.stepTime
			if walking and not moving and t - lo.stopT < 1 then
				-- (the step that brings a foot beside the other as a walker comes to rest: a short one)
				dur = min(dur, 0.17)
			end
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
					local rd, rc = runSync(rig, s, off, sw, t)
					if rd then
						dur, f.cycle = rd, rc
					elseif x > sw then
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
			-- (a hard turn at a run: a foot in the air while the other pushes off or flies comes down now - a foot on
			-- the floor pivots the body round, no flight through the turn - and a run's long swing turns into a quick
			-- pivot step; hurried, never cut short)
			if walking and (lo.turnK or 0) > 0.5 then
				local rem = f.t0 + f.dur - t
				-- (never quicker than a foot travels - 25 studs/s: [Studio] a step left 2.5 studs behind as AutoRotate swung
				-- the root three-eighths round flew there in two frames)
				local togo = f.cur and f.tgtW and V3(f.tgtW.X - f.cur.X, 0, f.tgtW.Z - f.cur.Z).Magnitude or 0
				local cap = max((o.swing or o.push) and 0.06 or 0.15, togo / 25)
				if rem > cap and (not o.swing or rem <= o.t0 + o.dur - t) then
					retime(f, t, cap)
				end
			elseif walking and moving and run > 0.5 and (lo.flipK or 0) > 0.5 and f.t0 + f.dur - t > 0.12 then
				-- (the way he goes swung round at a run: down within 0.12 s, on the new spot)
				retime(f, t, 0.12)
			end
			-- (a walker's step never runs on past its pace: a start from rest - the first swing timed at the first
			-- frame's crawl - or a turn's long step is hurried to at most 1.2 of the swing the pace now has; a foot in
			-- the air when he stops, or pulls up hard out of a run, comes down in a short step)
			if walking and f.stepKind == "walk" then
				local rem = f.t0 + f.dur - t
				local u0 = clamp((t - f.t0) / f.dur, 0, 0.95)
				local cap = 1e9
				if not moving or (lo.brake or 0) > 0.3 then
					-- (a runner's foot in the air as he pulls up lands at once when the other one has to go; the last
					-- one comes through beside it in a quick step)
					cap = ((o.push and moving and t - o.landT > 0.12) or (o.swing and moving and rem <= o.t0 + o.dur - t)) and 0.07 or 0.2
					if moving then
						-- (pulling up: never cut shorter than the walk's own swing at this pace - it shortens as the braking
						-- steps take over, so the swing hurries smoothly instead of snapping down in 0.07 s)
						cap = max(cap, (1 - lo.duty) * lo.T * (1 - u0))
					end
				elseif (run < 0.5 and back < 0.5 and lo.side < 0.6) or sideK > 0.5 or (lo.dirRate or 0) > 3 then
					-- (the first steps from rest: no longer than the pace's own swing; a side shuffle's too, and any step as
					-- the way he goes swings round under a body that keeps facing - a run's long swing still in the air as he
					-- goes off sideways, or back the other way, lands within the new pace's swing, never hangs behind him)
					cap = (t - lo.moveT < 0.8 and 1 or 1.2) * (1 - lo.duty) * lo.T * (1 - u0)
				end
				if rem > cap + 0.01 then
					retime(f, t, cap)
				end
			end
			local u = (t - f.t0) / f.dur
			local remain = max(0, f.t0 + f.dur - t)
			local lead = 0
			local d = speed > 0.05 and vel / speed or ZERO
			local sk = f.stepKind
			if moving and (sk == "walk" or sk == "shuffle" or sk == "stagger") then
				if sk == "walk" then
					-- walkers plant the heel a little ahead of the hip (about 0.4 of the contact) and push
					-- off further behind it; runners land a little closer under the body (0.3 of it: [Studio] at 0.17
					-- the stance swept further behind than the leg reaches and every foot toed off early, out of turn)
					-- (a hard turn's pivot steps land under the body)
					lead = lo.duty * lo.stride * lerp(0.36, 0.3, lo.run) * (1 - (lo.turnK or 0))
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
			-- (the landing frame overshoots the touchdown by up to a frame: the spot is where home was AT the touchdown,
			-- not a frame's travel further on - the foot would land and jump a quarter stud ahead at a run, every step)
			local remS = max(-dt, f.t0 + f.dur - t)
			local tgt = f.home + vel * remS + V3(acc.X, 0, acc.Z) * (0.5 * remS * abs(remS)) + d * lead
			-- (pulling up: a braking step lands where he will come to rest - ahead of the pelvis as it touches down, under
			-- it once he has stopped: the feet end side by side, no shuffle after)
			-- (never further ahead of where the pelvis will be at the touchdown than a braking step's ~25 cm)
			local brk = walking and moving and lo.brake or 0
			if brk > 0 and lo.brakeDir then
				local bd = lo.brakeDir
				local af = lo.accF or lo.acc
				local dec = max(20, -(af.X * bd.X + af.Z * bd.Z))
				local reach = max(0, speed * remain - 0.5 * dec * remain * remain) + 0.32 * soleLeg(g)
				tgt = tgt:Lerp(f.home + bd * min(speed * speed / (2 * dec), reach), brk)
			end
			-- a side step: the leading foot (on the side of travel) lands lo.sideA out from where the pelvis will be at the
			-- touchdown, the trailing one lo.sideB in on its own side (updateGait), across the legs' frame; along it the
			-- forward walk's spot (the diagonals blend: sideK)
			if sideK > 0 and moving and sk == "walk" and lo.sideA then
				local lcf = rig.legCF or rootCF
				local ahead = vel * remS + V3(acc.X, 0, acc.Z) * (0.5 * remS * abs(remS))
				local rel = lcf:PointToObjectSpace(tgt - ahead)
				local sg = lo.sideLead == "L" and -1 or 1
				local x = ((s == "R") == (sg > 0)) and sg * lo.sideA or -sg * lo.sideB
				tgt = lcf:PointToWorldSpace(V3(lerp(rel.X, x, sideK), rel.Y, rel.Z)) + ahead
			end
			-- footwork: the feet never come closer side by side than FOOT_GAP (no crossing, no clipping);
			-- a walker's feet keep WALK_GAP (strafing never scissors the legs)
			local oP = o.swing and o.cur or o.P
			-- (in a hard turn the other foot's swing sweeps round the body: kept clear of where it lands, not of it)
			if o.swing and walking and (lo.turnK or 0) > 0.5 then
				oP = nil
			end
			if oP and (fight or walking) then
				local lcf = rig.legCF or rootCF
				local lt = lcf:PointToObjectSpace(tgt)
				local lo2 = lcf:PointToObjectSpace(oP)
				-- (sideways a little more: the side shuffle's closing foot never brushes the other)
				local wg = max(WALK_GAP * lerp(1, 0.65, lo.run), g.ok and (g.footW or 0) + 0.06 or 0)
				local gap = walking and lerp(wg, max(0.47, wg), lo.side) or FOOT_GAP * (kind == "stagger" and 0.6 or 1)
				if s == "L" and lt.X > lo2.X - gap then
					lt = V3(lo2.X - gap, lt.Y, lt.Z)
					tgt = lcf:PointToWorldSpace(lt)
				elseif s == "R" and lt.X < lo2.X + gap then
					lt = V3(lo2.X + gap, lt.Y, lt.Z)
					tgt = lcf:PointToWorldSpace(lt)
				end
			end
			local landYaw = f.homeYaw
			-- a walker's floor under the landing spot (a ray at the start of the swing and again half-way,
			-- the spot moves with the body), and the slope along the foot
			local gy = f.home.Y
			if walking then
				-- (rays only where they can matter: a rig near the camera - a player's character, anyone
				-- within 25 studs, or anyone whose root went up or down in the last second and a half;
				-- elsewhere the root's floor will do)
				local probe = (rig.lod or 3) >= 3
					and (rig.isPlayer or (rig.camDist or 0) < 25 or t - (lo.vyT or -10) < 1.5)
				-- (again late in the swing: the spot has settled; under the whole shoe, which keeps off stair edges)
				if f.gRay < f.t0 or (probe and ((u >= 0.5 and f.gRay < f.t0 + f.dur * 0.5) or (u >= 0.85 and f.gRay < f.t0 + f.dur * 0.85))) then
					f.gRay = t
					if probe then
						f.gY, f.landSlope, f.gShift = footGround(rig, g[s], tgt, f.home.Y, fwdOf(landYaw))
					else
						f.gY, f.landSlope, f.gShift = nil, 0, 0
					end
				end
				gy = f.gY or gy
				if f.gShift ~= 0 then
					tgt += fwdOf(landYaw) * f.gShift
				end
			end
			-- (over the step's last frames, as the foot comes down, the spot moves no faster than the foot can follow it:
			-- [Studio] a Humanoid's AutoRotate snap swung the spot (home and the step's lead) round the root by 0.6-0.8 studs
			-- in the swing's last two frames and the foot landed there in one, a skid on the floor at every WASD turn; a
			-- strafe reversed, or a run's side shuffle turning into a diagonal, swung it half a stud; a side step's spot
			-- drifting with the root's 240 Hz travel had the flat-landing foot on the floor a frame early, skidding 0.01-0.04
			-- studs into it, and a side shuffle's kept clear of the other foot as that one leaves the floor chased its quick
			-- swing out to the side; pulling up, the spot swung in to where he comes to rest. Earlier in the step the spot
			-- moves freely - the foot in the air follows it - and a change of pace (Shift) is never held back)
			local aim = f.aimW
			if walking and aim and remain < 0.08 then
				local turnW = clamp((max(abs(lo.yawRate), lo.dirRate or 0) - 1.5) / 2, 0, 1)
				turnW = max(turnW, sideK, (run < 0.5 and (not moving or (lo.brake or 0) > 0.3)) and 1 or 0)
				if turnW > 0 then
					local dx, dz = tgt.X - aim.X, tgt.Z - aim.Z
					local dm = sqrt(dx * dx + dz * dz)
					local lim = lerp(1e3, 1 + 30 * remain, turnW) * dt
					if dm > lim then
						tgt = V3(aim.X + dx * lim / dm, tgt.Y, aim.Z + dz * lim / dm)
					end
				end
			end
			f.aimW = tgt
			-- (where a planned swing's ankle is headed: planAnkle)
			f.tgtW = V3(tgt.X, gy, tgt.Z)
			-- the touchdown spot as seen from where the body is now (for the pelvis height)
			f.landRel = tgt - vel * remS - V3(acc.X, 0, acc.Z) * (0.5 * remS * abs(remS))
			f.landRel = V3(f.landRel.X, gy, f.landRel.Z)
			f.landYaw = landYaw
			if u >= 1 then
				-- (a runner's foot lands where its reach brought it: AnimLoco.feet's RUN_REACH_KNEE)
				local ro = f.reachOff or ZERO
				f.reachOff = nil
				f.swing, f.P, f.yawW, f.lastStep, f.curLift = false, V3(tgt.X + ro.X, gy, tgt.Z + ro.Z), landYaw, t, 0
				f.landT = t
				f.sigT = t
				f.dropH = nil
				f.pitchS = f.curPitch
				f.slopeP = walking and (f.gY and f.landSlope or 0) or 0
			else
				-- horizontal travel: zero speed at lift-off and touchdown (the foot leaves and meets the
				-- canvas without a skid); runners cruise and brake late (no hovering reach ahead)
				-- (a runner's foot leaves the ground moving on already - it rises behind him as the knee folds
				-- instead of trailing straight - and slows into the touchdown: a Hermite start at half the swing's
				-- mean speed)
				-- ([Studio] and it still travels at RUN_LAND_V of the body's pace as it meets the ground - the swing leg's
				-- retraction - coming down onto it (the arc's late hump). Brought to rest in the world at the touchdown
				-- the ankle ran a stud past the landing spot - the thigh raised to 70-90 degrees, the leg straight and the
				-- foot hovering a fifth of a stud over the floor - and came back to it as the body caught up)
				local e = K.smoother(u)
				if sk == "walk" and lo.run > 0.01 then
					local span = (tgt - f.fromP).Magnitude
					local m1 = clamp(RUN_LAND_V * speed * f.dur / max(0.5, span), 0, 0.6)
					-- (a side shuffle's foot leaves at the swing's whole mean speed: at half, the body going sideways at
					-- 16 studs/s left the trailing foot drifting further out for the first frames - the leg splayed 40 degrees)
					-- (and comes down on its spot at rest: a run's swing meets the ground still moving at RUN_LAND_V of the pace,
					-- the leg's retraction, but a foot going sideways at it lands flat across its own line and skids)
					local m0 = lerp(0.5, 1, sideK)
					m1 *= 1 - sideK
					e = lerp(e, u * u * (3 - 2 * u) + m0 * u * (1 - u) * (1 - u) + m1 * u * u * (u - 1), lo.run)
				end
				local pos = f.fromP:Lerp(tgt, e)
				-- (up a step the foot rises to the new height early, down one it stays high, then drops)
				local y0 = f.fromP.Y
				local ey = gy > y0 and smooth(u / 0.55) or smooth((u - 0.35) / 0.65)
				-- (a side shuffle's foot in the air never strays further out across the body than SIDE_ABD_AIR from its hip: at
				-- 16 studs/s the body ran on from the trailing foot as it left the floor and the leg hung out to the side,
				-- abducted 50-70 degrees, for the first frames of its swing on a 30 Hz frame; taken up as it leaves the floor
				-- - a foot lifting from further out is never yanked in on the floor - and let go of as it comes down on its
				-- spot, which is inside that anyway)
				if walking and sideK > 0.5 and moving then
					local lcf = rig.legCF or rootCF
					local rel = lcf:PointToObjectSpace(pos)
					local lim = abs(g[s].hip0.X) + soleLeg(g) * sin(SIDE_ABD_AIR)
					local cx = clamp(rel.X, -lim, lim)
					if cx ~= rel.X then
						pos = lcf:PointToWorldSpace(V3(lerp(rel.X, cx, sideK * smooth(u / 0.25) * (1 - smooth((u - 0.6) / 0.3))), rel.Y, rel.Z))
					end
				end
				f.cur = V3(pos.X, walking and lerp(y0, gy, ey) or f.home.Y, pos.Z)
				f.curYaw = f.fromYaw + K.wrap(landYaw - f.fromYaw) * e
				-- (and in the air it turns with the leg: never twisted round under the shin - TWIST_MAX)
				if walking then
					local tw = K.wrap(f.curYaw - f.homeYaw)
					if abs(tw) > TWIST_MAX then
						f.curYaw = f.homeYaw + (tw > 0 and TWIST_MAX or -TWIST_MAX)
					end
				end
				-- the arc: walking clears the ground early in the swing (the knee's peak flexion) and skims
				-- in to the heel strike; running kicks the heel up early behind the body, then the knee
				-- unfolds as the foot reaches forward. A smooth skewed bump u^a (1-u)^b (zero slope at
				-- lift-off and touchdown: no knee snap)
				-- (a runner kicks the heel up early behind the body - the peak a quarter of the way, while the foot is
				-- still behind the hip - then the knee unfolds as the foot passes low under the body and reaches; a late
				-- hump (RUN_LIFT_LATE, highest at 0.83) holds it a few centimetres up and brings it DOWN onto the ground,
				-- as a runner's foot comes, not skimming in along the floor at the body's pace. [Studio] peaking at 0.4
				-- with a slow fall the foot was carried highest under and in front of the hip: the thigh raised to the
				-- horizontal, a sprinter's high knees at 16 studs/s)
				local a = sk == "walk" and lerp(1.6, 1.25, lo.run) or 2
				local b = sk == "walk" and lerp(2.4, 1.9, lo.run) or 2
				local bump = K.skewBump(u, a, b)
				if sk == "walk" and lo.run > 0.01 then
					bump = lerp(bump, (1 - RUN_LIFT_LATE) * K.skewBump(u, 1.1, 3.4) + RUN_LIFT_LATE * K.skewBump(u, 5, 1), lo.run)
				end
				f.curLift = f.liftH * bump * (1 - 0.75 * (lo.turnK or 0)) + (f.dropH or 0) * (1 - K.smoother(u))
				-- foot roll through the swing: toe-off -> level -> landing attitude
				local landP, mid
				if sk == "walk" then
					-- (heel first; a backward step lands on the ball of the foot)
					landP = lerp(lerp(lerp(-0.28, 0.02, lo.run), 0.3, back), 0.03, sideK) - (f.gY and f.landSlope or 0)
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
	-- stance pitch: the gait's heel-strike roll and heel rise, else the pose's heel spec. A walker's trailing
	-- foot in the double support (the other one down or landing) and a runner's past mid-stance PUSH: their
	-- pitch is solved below, against where the pelvis is (rolled up onto the toes as far as the leg needs)
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		f.push = false
		-- (the pitch the frame starts from: the solves below share one frame's PUSH_RATE between them)
		f.pitchF = f.pitchS
		if not f.swing then
			local want = f.heelS
			if moving and walking then
				local off = s == "L" and lo.offL or lo.offR
				local sw = 1 - lo.duty
				local sigma = ((lo.phase - off - sw) % 1) / lo.duty -- 0 at landing .. 1 at lift-off
				-- (a foot that landed off its schedule - a pace change, a step out of turn - counts its stance
				-- from its own touchdown; it never jumps back to an earlier part of the stance)
				local sa = (t - (f.sigT or f.landT)) / max(0.05, lo.duty * lo.T)
				sigma = sigma <= 1.02 and max(sigma, min(sa, 1)) or min(sa, 1)
				f.sigma = sigma
				want = stancePitch(sigma, run, back, sideK)
				local o = rig.foot[s == "L" and "R" or "L"]
				-- (walking backward the foot in front keeps its weight to the end - the time-reversed heel strike - and
				-- the one behind lands on its toes)
				f.push = back < 0.5 and lo.side < 0.6
					and ((run < 0.5 and sigma > 0.5 and (not o.swing or (o.landWgt or 0) > 0.5)) or (run >= 0.5 and sigma > 0.45))
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
			f.pitchLo = want
			-- just landed: settle from the landing attitude (a pushing foot: the solve below)
			if not f.push then
				f.pitchS += (want - f.pitchS) * (1 - exp(-dt * 18))
			end
			f.curPitch = f.pitchS
		end
	end
	-- feet into the root's space; the pelvis sinks if a foot would be out of reach
	local targets = rig.ftmp or {}
	rig.ftmp = targets
	local drop = 0
	-- walkers: the pelvis height follows the weight-bearing legs (signed: it may rise a little over the pose's
	-- height); wFloor = the least drop that leaves every weight-bearing foot within a straight leg's reach
	local wNeed, wFloor, wCap = nil, nil, WALK_DROP
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
			-- (about the ball while the foot is flat; with the heel up the weight is on the sole's toe, where the
			-- roll model has it touching - a punch's pivot turns on that point, or the boot's tip skated round the
			-- ball: AnimRig.toeContact)
			local bz = R.toeContact(leg, f.curPitch or 0)
			local B = P + fwdOf(yawW) * bz
			yawW += pv
			P = B - fwdOf(yawW) * bz
			f.visP, f.visYaw = P, yawW
		elseif not f.swing then
			f.visP, f.visYaw = nil, nil
		end
		-- (the ground point and heading the foot rolls about this frame)
		local F = fwdOf(yawW)
		f.tP, f.tF = P, F
		local pitch = f.curPitch
		local lift = f.swing and f.curLift or 0
		-- (the slope the foot rolls on: a swinging foot turns from the one it left to the one it lands on)
		local sl = f.slopeP or 0
		if f.swing then
			sl = lerp(f.fromSl or 0, f.gY and f.landSlope or 0, smooth((t - f.t0) / f.dur))
		end
		f.tSl = sl
		local ank = R.ankleOf(leg, P, F, pitch, sl) + V3(0, lift + f.lift, 0)
		-- a walker's swing at a walk: the ankle's planned path (rebaseSwing / planAnkle / liftPlan), from the push-off's last frame
		if f.planNew then
			f.planNew = false
			f.plan = false
			if walking and f.swing and f.stepKind == "walk" and run < 0.5 and back < 0.5 then
				rebaseSwing(f, t, false)
			end
		end
		local planned = walking and f.swing and f.plan and f.stepKind == "walk" and f.tgtW ~= nil
		if planned then
			-- (the swing's peak knee: ~60 at the town walk, less slow / backward / sideways / in a hard turn's pivot step)
			-- (a side step's: ~26, the leg lifted out from the hip)
			local kpk = lerp(lerp(lerp((50 + 6 * clamp(lo.vh or 1, 0, 2.2)) * RAD, 35 * RAD, back), 26 * RAD, sideK), 28 * RAD, lo.turnK or 0)
			local A1 = R.ankleOf(leg, f.tgtW, fwdOf(f.landYaw or yawW), f.landPitch or 0, f.gY and f.landSlope or 0)
			local hipP = (g.rootC0 * rootT * leg.rootHip).Position
			f.planPh = planAnkle(rig, f, s, t, trueCF, rootT, hipP, A1, lo.softK, kpk, sideKnee(stanceKnee(0, 0, lo.vh or 0, prof), lo.sideK))
			-- (the pelvis's drop predicted from its speed; liftPlan runs again with the final one)
			ank = trueCF:PointToWorldSpace(liftPlan(f, f.planPh, hipP - V3(0, lo.drop + (lo.dropV or 0) * dt, 0)))
		elseif f.swing and f.fromP and f.liftPitch then
			-- a foot that left rolled up onto its toes does not drop back onto its heel as it unrolls in the air:
			-- the ankle keeps the height the roll gave it while the swing lifts it, and the reach ahead fades into
			-- the step (no straight leg sliding back behind the body after the toe-off)
			local u = clamp((t - f.t0) / f.dur, 0, 1)
			local F0 = fwdOf(f.fromYaw)
			local D = R.ankleOf(leg, f.fromP, F0, f.liftPitch, sl) - R.ankleOf(leg, f.fromP, F0, pitch, sl)
			ank += V3(D.X * (1 - K.smoother(u)), max(0, D.Y) * (1 - smooth(u / 0.5)), D.Z * (1 - K.smoother(u)))
		end
		-- a turn's steps: the foot in the air goes round the planted one, never across it (the thighs would pass
		-- through each other): its ankle keeps TURN_GAP (scaled to the man) to the side of the planted foot, in the
		-- legs' frame, while the turn lasts - a hard turn's pivot steps, and a walk or run that curves
		-- (and a side shuffle reversed: the foot that now leads comes back past the other one)
		local tk = walking and f.swing and max(lo.turnK or 0, clamp((abs(lo.yawRate) * lo.speed - 8) / 12, 0, 1), sideK * (lo.flipK or 0)) or 0
		if tk > 0 then
			local o = rig.foot[s == "L" and "R" or "L"]
			-- (the other foot planted, or in the air too: a run's flight as the reversal starts)
			local oP = o.swing and o.tP or (o.visP or o.P)
			if oP then
				local lcf = rig.legCF or rootCF
				local a, b = lcf:PointToObjectSpace(ank), lcf:PointToObjectSpace(oP)
				local sx = s == "L" and -1 or 1
				local over = TURN_GAP * (g.utScale and g.utScale.X or 1) * smooth(tk / 0.4) - sx * (a.X - b.X)
				if over > 0 then
					-- (taken up over most of the step, the foot coming round: [Studio] at once, a foot lifting behind the
					-- other as AutoRotate snapped the root a quarter turn was thrown 1.9 studs sideways in its first frame)
					ank = lcf:PointToWorldSpace(V3(a.X + sx * over * smooth(clamp((t - f.t0) / f.dur, 0, 1) / 0.6), a.Y, a.Z))
				end
			end
		end
		-- into the TRUE root's space (the IK and rootT live there)
		local tgt = trueCF:PointToObjectSpace(ank)
		targets[s] = tgt
		targets[s .. "yaw"] = K.wrap(yawW - trueYaw)
		targets[s .. "pitch"] = pitch
		if walking then
			local hipP = (g.rootC0 * rootT * leg.rootHip).Position
			if f.swing and moving and f.stepKind == "walk" and not planned then
				-- just off the toes the knee keeps folding: a foot the body leaves behind faster than the swing
				-- lifts it rises behind him (the heel comes up) instead of the leg trailing straight
				local u = (t - f.t0) / f.dur
				if u < 0.6 then
					local want = R.slackFor(leg, lerp(35, 25, run) * RAD, WALK_SOFT) * (leg.l1 + leg.l2)
					-- (the hip where this frame's pelvis drop - about last frame's - will put it)
					local d = tgt - hipP + V3(0, lo.drop + (lo.dropV or 0) * dt, 0)
					local h2 = d.X * d.X + d.Z * d.Z
					if h2 < want * want then
						local up = -d.Y - sqrt(want * want - h2)
						if up > 0 then
							-- (taken up over the first frames: the knee never snaps from the push's extension)
							tgt += V3(0, up * smooth(u / 0.12) * (1 - smooth((u - 0.3) / 0.3)) * (1 - (lo.turnK or 0)), 0)
						end
					end
				end
				-- [Studio] a runner's foot reaching for the ground never locks the knee straight in the air: the ankle is
				-- kept where the leg reaches it with RUN_REACH_KNEE of bend (brought back under the body - the swing
				-- leg's retraction - not lifted), so it meets the ground softly bent. Past that the IK stretched the
				-- leg dead straight and the foot hovered a fifth of a stud over the floor for the last tenth of a second
				-- (and it touches down there: a foot set down on the spot further on would jump to it in the landing frame)
				f.reachOff = nil
				if run > 0.01 and u > 0.5 then
					local dMax = R.slackFor(leg, RUN_REACH_KNEE, WALK_SOFT) * (leg.l1 + leg.l2)
					local d = tgt - hipP + V3(0, lo.drop + (lo.dropV or 0) * dt, 0)
					local h2 = d.X * d.X + d.Z * d.Z
					if h2 + d.Y * d.Y > dMax * dMax and h2 > 1e-6 then
						local k = sqrt(max(0, dMax * dMax - d.Y * d.Y) / h2)
						-- (not a side shuffle's: its foot reaches out to the side for its spot - pulled in under the hip
						-- the leading foot landed a third of a stud short and the trailing one, kept clear of it, crossed
						-- under the pelvis; the shuffle's crouch gives the leg its reach)
						k = lerp(1, min(1, k), run * smooth((u - 0.5) / 0.15) * (1 - sideK))
						local t2 = V3(hipP.X + (tgt.X - hipP.X) * k, tgt.Y, hipP.Z + (tgt.Z - hipP.Z) * k)
						f.reachOff = trueCF:VectorToWorldSpace(t2 - tgt)
						tgt = t2
					end
				end
			end
			targets[s] = tgt
			-- the stance leg's knee by design (heel strike nearly straight, loading flex, locked by mid-stance;
			-- a runner softly bent); a pushing foot never holds the pelvis: it rolls to reach it
			if not f.swing and f.push then
				f.needDrop, f.needPrev = nil, nil
			elseif not f.swing then
				local slack = R.slackFor(leg, (moving and f.sigma) and sideKnee(stanceKnee(f.sigma, run, lo.vh, prof), lo.sideK) or standKnee, WALK_SOFT)
				local need = R.needFor(rig, s, rootT, tgt, slack, WALK_DROP + 0.3, hipP)
				local o = rig.foot[s == "L" and "R" or "L"]
				if moving and run < 0.5 and back < 0.5 and f.sigma and f.sigma > 0.5 and o.swing and need > lo.drop + 0.005 then
					-- a walker's single support past mid-stance: the heel rises rather than the pelvis falling as
					-- the body passes over the foot (the leg keeps its length; the landing foot then takes the
					-- pelvis down into the double support)
					local a, b = f.pitchS, PUSH_MAX
					local wantN = lo.drop + 0.005
					for _ = 1, 8 do
						local m = (a + b) * 0.5
						local am = trueCF:PointToObjectSpace(R.ankleOf(leg, P, F, m, sl) + V3(0, f.lift, 0))
						if R.needFor(rig, s, rootT, am, slack, WALK_DROP + 0.3, hipP) > wantN then
							a = m
						else
							b = m
						end
					end
					local th = max(f.pitchS, min(b, (f.pitchF or f.pitchS) + PUSH_RATE * dt))
					f.pitchS, f.curPitch = th, th
					tgt = trueCF:PointToObjectSpace(R.ankleOf(leg, P, F, th, sl) + V3(0, f.lift, 0))
					targets[s], targets[s .. "pitch"] = tgt, th
					need = R.needFor(rig, s, rootT, tgt, slack, WALK_DROP + 0.3, hipP)
				end
				f.needPrev = f.needDrop or need
				f.needDrop = need
				-- (a just-landed leg is about to give into its loading flex: what it will let the pelvis do)
				f.needLoad = need
				if moving and f.sigma and f.sigma < 0.16 and run < 0.5 then
					local lr = sideKnee(stanceKnee(0.16, run, lo.vh, prof), lo.sideK)
					f.needLoad = max(need, R.needFor(rig, s, rootT, tgt, R.slackFor(leg, lr, WALK_SOFT), WALK_DROP + 0.3, hipP))
				end
				wNeed = max(wNeed or -1e9, need)
				-- (the floor: this foot at the straightest the leg goes)
				wFloor = max(wFloor or -1e9, R.needFor(rig, s, rootT, tgt, R.slackFor(leg, 2 * RAD, WALK_SOFT), WALK_DROP + 0.3, hipP))
				-- (a foot on lower ground than the root's floor - stairs down, a ramp - may take the pelvis
				-- further down)
				wCap = max(wCap, WALK_DROP + clamp(f.home.Y - P.Y, 0, 0.9))
			else
				f.needDrop, f.needPrev = nil, nil
				local u = (t - f.t0) / f.dur
				if u > (run < 0.5 and 0.3 or 0.6) and f.landRel then
					local la = R.ankleOf(leg, f.landRel, fwdOf(f.landYaw), f.landPitch or 0, f.gY and f.landSlope or 0)
					local lt = trueCF:PointToObjectSpace(V3(la.X, la.Y + f.lift, la.Z))
					local kn = moving and sideKnee(stanceKnee(0, run, lo.vh, prof), lo.sideK) or standKnee
					-- (a landing spot far out of reach - a hard turn, a lunge - never drags the pelvis down for it)
					f.landNeed = min(0.22, R.needFor(rig, s, rootT, lt, R.slackFor(leg, kn, WALK_SOFT), WALK_DROP + 0.3, hipP))
					f.landWgt = run < 0.5 and smooth((u - 0.3) / 0.5) or smooth((u - 0.6) / 0.4)
					if planned then
						f.landNeed = min(0.26, f.planNeed or -1)
						f.landWgt = smooth((u - 0.45) / 0.25)
					end
					wCap = max(wCap, WALK_DROP + clamp(f.home.Y - f.landRel.Y, 0, 0.9))
					-- (a runner touches down at the height his landing leg wants: the bounce's base)
					if run > 0.01 then
						lo.runD0 = (lo.runD0 or f.landNeed) + (f.landNeed - (lo.runD0 or f.landNeed)) * (1 - exp(-dt * 15))
					end
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
					local la = R.ankleOf(leg, f.landRel, fwdOf(f.landYaw), f.landPitch or 0, f.gY and f.landSlope or 0)
					local lt = trueCF:PointToObjectSpace(V3(la.X, la.Y + f.lift, la.Z))
					drop = max(drop, R.dropFor(rig, s, rootT, lt, slack) * smooth((u - 0.6) / 0.4))
				end
			end
		end
	end
	-- a fighter sinks at once (a planted foot is never dragged) and rises gently (no pelvis pumping);
	-- a walker never plunges: his pelvis drop is capped and rate-limited (the foot that would need more
	-- toes off early instead, above); a runner's bounces
	if walking then
		-- (no weight on a foot: the pelvis rises toward the pose's height, and the landing foot reaches for the
		-- ground as it comes down)
		local base = wNeed or 0
		local tgtD = base
		lo.landW = 0
		for _, s in ipairs(SIDES) do
			local f = rig.foot[s]
			if f.swing and (f.landWgt or 0) > 0 then
				tgtD = max(tgtD, lerp(base, f.landNeed, f.landWgt))
				lo.landW = max(lo.landW, f.landWgt)
			end
		end
		-- (each weight-bearing foot's excess: how far under the other one's wish it would hold the pelvis)
		for _, s in ipairs(SIDES) do
			local f = rig.foot[s]
			f.excess = 0
			if not f.swing and f.needDrop then
				local o = rig.foot[s == "L" and "R" or "L"]
				if not o.swing and o.needDrop then
					f.excess = f.needDrop - (o.needLoad or o.needDrop)
				end
			end
		end
		-- (a side shuffle at speed keeps low - an athlete's crouch, the knees bent - so that the leading leg reaches its
		-- spot out to the side and the pelvis never rises into the flight between the steps)
		if sideK > 0 and moving then
			tgtD = max(tgtD, SIDE_CROUCH * sideK * run)
		end
		drop = clamp(tgtD, -WALK_RAISE, moving and wCap or 0.75)
		-- (a critically damped spring, its speed capped: the pelvis eases into and out of a dip, never
		-- a V that turns round in one frame - nor a jolt when he stops and his knees unlock)
		local v0 = lo.dropV or 0
		local x0 = lo.drop
		-- (stiffer down into a heel strike: the pelvis is where the landing leg reaches as the heel meets the floor)
		local x, v = K.spring2(x0, v0, drop, drop > x0 and lerp(28, 48, lo.landW * (1 - run)) or 26, 1, dt)
		v = clamp(v, -DROP_RATE * 1.6, DROP_RATE * 1.6)
		-- [Studio] and never more than a 30 Hz frame's worth of travel in ONE frame, however long the frame: a hitch
		-- (a 0.1-0.25 s frame when Studio compiles a shader or streams a venue in) moves the root a whole step and the
		-- feet with it, and the pelvis then dropped 0.4 studs in that single frame - a visible dip and a knee pop; it
		-- eases down over the next frames instead (the foot stretches a hair through its soft reach meanwhile)
		do
			local mx = DROP_RATE * 1.6 * min(dt, 1 / 30)
			x = x0 + clamp(x - x0, -mx, mx)
		end
		-- (as the trailing foot toes off, a walker's body coming down is caught by the leading leg over a
		-- moment - its upward acceleration bounded, about a third of g - so the bottom of each step is round)
		local lastOff = max(rig.foot.L.t0, rig.foot.R.t0)
		local catch = (t - lastOff < WALK_RELEASE and run < 0.5) and WALK_CATCH or 1e9
		if v < v0 - catch * dt then
			v = v0 - catch * dt
			x = x0 + v * dt
		end
		-- a runner's pelvis bounces like a spring-mass: it sinks over the stance (lowest at mid-stance), rises
		-- off it and FALLS FREELY in the flight (g), touching down where the landing leg wants it
		-- (eased: a hard turn or a stop takes the pelvis out of the bounce over a fifth of a second, no jolt)
		local rw = lo.bounceW or 0
		-- (a side shuffle's gallop has its own rhythm: its pelvis follows the legs, as a walker's)
		rw += ((moving and run * (1 - (lo.turnK or 0)) * (1 - sideK) or 0) - rw) * (1 - exp(-dt * 10))
		lo.bounceW = rw
		-- (a turn's quicker, longer-stance steps never re-time the bounce it is fading out of)
		if (lo.turnK or 0) < 0.01 then
			lo.bT, lo.bDuty = lo.T, lo.duty
		end
		if rw > 0.01 then
			local bT, bDuty = lo.bT or lo.T, lo.bDuty or lo.duty
			local half = bT * 0.5
			local ds = clamp(2 * bDuty, 0.2, 0.95) -- the stance's share of a step
			local psi = ((lo.phase - (1 - bDuty)) % 0.5) / 0.5 -- 0 at a touchdown
			local Tc, Tf = ds * half, (1 - ds) * half
			local y, vy
			if psi < ds then
				-- (the leg's push rises and fades as a half sine, over the step as a whole holding the body up: the
				-- pelvis meets the flight's speed and its free fall at touchdown and toe-off, lowest at mid-stance)
				-- (a runner's stiffer leg sinks less: toward a shallower curve that meets the flight the same way - all
				-- the way from ~4.5 m/s; [Studio] from 4.8 only, the pelvis bounced 0.36 studs at 16 studs/s, 13 % of
				-- the leg, and sank the stance knee to 60)
				local tc, w = psi * half, PI / Tc
				local kw = (Tc + Tf) * 0.5
				y = -GRAV * Tf * 0.5 * tc + GRAV * (kw * (tc - sin(w * tc) / w) - 0.5 * tc * tc)
				vy = -GRAV * Tf * 0.5 + GRAV * (kw * (1 - cos(w * tc)) - tc)
				local stiff = clamp((lo.vh - 3) / 1.5, 0, 1)
				if stiff > 0 then
					local A = GRAV * Tf * Tc / (2 * PI)
					local sn, cs = sin(w * tc), cos(w * tc)
					y = lerp(y, -A * sn * (1 - 0.4 * sn * sn), stiff)
					vy = lerp(vy, -A * w * cs * (1 - 1.2 * sn * sn), stiff)
				end
			else
				local tau = (psi - ds) * half
				y = GRAV * Tf * 0.5 * tau - 0.5 * GRAV * tau * tau
				vy = GRAV * (Tf * 0.5 - tau)
			end
			local d = clamp((lo.runD0 or 0.15) - y, -WALK_RAISE, wCap)
			x = lerp(x, d, rw)
			v = lerp(v, -vy, rw)
		end
		-- (never above where a weight-bearing leg reaches - no planted foot hovers - caught up with over a frame
		-- or two, the foot's roll covering the rest: no pelvis pop; side-stepping at once, no roll covers it there)
		if wFloor and x < wFloor then
			x += (min(wFloor, moving and wCap or 0.75) - x) * (1 - exp(-dt * lerp(35, 160, lo.side)))
			v = max(v, 0)
		end
		-- (a walker's: a runner's landing is his own spring)
		local xg = (run < 0.5 and back < 0.5) and clamp(kneeGovern(rig, rootT, targets, x, WALK_DROP + 0.3, t, dt), -WALK_RAISE, moving and wCap or 0.75) or x
		-- (never so high that a weight-bearing foot is left hovering)
		if wFloor and xg < x then
			xg = max(xg, min(x, wFloor))
		end
		if xg ~= x then
			x, v = xg, (xg - lo.drop) / dt
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
	-- a walker's planted feet against the pelvis as it now is: a pushing foot rolls up onto its toes until its
	-- leg has the knee the push-off wants (the heel rise IS the push-off: it gives the leg its reach, and the
	-- toes stay on the floor); any other planted foot the pelvis left out of reach rolls just enough to stay
	-- on the floor (heel up behind the hip, toes up ahead of it): no planted foot ever hovers
	if walking then
		for _, s in ipairs(SIDES) do
			local f = rig.foot[s]
			f.reachShort = 0
			if f.swing and f.planT == t and f.planPh then
				targets[s] = liftPlan(f, f.planPh, (g.rootC0 * rootT * g[s].rootHip).Position)
			elseif not f.swing and f.tP then
				local leg = g[s]
				local L2 = leg.l1 + leg.l2
				local hip = (g.rootC0 * rootT * leg.rootHip).Position
				local P, F, lf, sl = f.tP, f.tF, f.lift, f.tSl or 0
				local cur = f.pitchS
				local th = cur
				local dMax = R.slackFor(leg, 0, soft) * L2
				if f.push and moving and f.sigma then
					-- (bisection: behind the hip the ankle comes closer as the heel rises)
					-- (the push takes over from the knee the leg has: eased onto the design over a tenth of a second)
					local kp = pushKnee(f.sigma, run)
					if not f.pushOn then
						f.pushOn, f.pushT0, f.pushOff = true, t, (f.kAct or kp) - kp
					end
					kp += f.pushOff * (1 - smooth((t - f.pushT0) / 0.1))
					-- (and like a weight-bearing knee, it changes its rate only so fast: kneeGovern; a pushing knee
					-- already bending keeps bending - it never stops dead or springs back in a frame)
					if f.kAct and run < 0.5 then
						local kv, ka = f.kVel or 0, KNEE_ACC * dt
						kp = clamp(kp, f.kAct + (kv - ka) * dt, f.kAct + (max(kv, 0) + ka) * dt)
					end
					local want = R.slackFor(leg, kp, soft) * L2
					-- (the last moment of the push may stand the shoe on its tip: it is gone the next frame)
					-- (the stance's own heel rise is the least it rolls to - taken up at a heel's pace, never in a frame)
					local a = max(0, min(f.pitchLo or 0, (f.pitchF or cur) + 6 * dt))
					local b = PUSH_MAX + 0.25 * smooth((f.sigma - 0.85) / 0.15)
					-- (a walker's rigid boot never stands up on its tip: past WALK_TOE it toes off instead - below - once
					-- the other foot is down; until then it rolls on as far as it must: the leg never pulled straight)
					local o2 = rig.foot[s == "L" and "R" or "L"]
					if run < 0.5 then
						if not o2.swing then
							-- (never unrolled back to it either: a foot already further over goes as it is)
							b = min(b, max(lerp(WALK_TOE, b, run * 2), f.pitchF or cur))
						elseif (f.pitchF or cur) >= WALK_TOE - 0.15 and not o2.retimed then
							-- (the other foot still in the air as this one runs out of roll: it is brought down now)
							local rem = o2.t0 + o2.dur - t
							-- ([Studio] over 0.05 s at least: brought down in 0.034 s the knee straightened 25 degrees in one frame
							-- at a curve's exit - a pop; at 0.05 it opens over three)
							if rem > 0.05 then
								retime(o2, t, 0.05)
								o2.retimed = true
							end
						end
					end
					if ankleDist(leg, P, F, lf, trueCF, hip, a, sl) <= want then
						th = a
					elseif ankleDist(leg, P, F, lf, trueCF, hip, b, sl) >= want then
						th = b
					else
						for _ = 1, 9 do
							local m = (a + b) * 0.5
							if ankleDist(leg, P, F, lf, trueCF, hip, m, sl) > want then
								a = m
							else
								b = m
							end
						end
						th = (a + b) * 0.5
					end
					local p0 = f.pitchF or cur
					th = clamp(th, p0 - PUSH_RATE * dt, p0 + PUSH_RATE * dt)
				else
					f.pushOn = false
					local d0 = ankleDist(leg, P, F, lf, trueCF, hip, cur, sl)
					if d0 > dMax then
						-- (roll the way that brings the ankle in, at most a third of a radian)
						local dir = ankleDist(leg, P, F, lf, trueCF, hip, cur + 0.05, sl) < d0 and 1 or -1
						local a, b = cur, cur + 0.35 * dir
						if ankleDist(leg, P, F, lf, trueCF, hip, b, sl) > dMax then
							th = b
						else
							for _ = 1, 8 do
								local m = (a + b) * 0.5
								if ankleDist(leg, P, F, lf, trueCF, hip, m, sl) > dMax then
									a = m
								else
									b = m
								end
							end
							th = (a + b) * 0.5
						end
						local p0 = f.pitchF or cur
						th = clamp(th, p0 - PUSH_RATE * dt, p0 + PUSH_RATE * dt)
					end
				end
				if th ~= cur or f.push then
					f.pitchS, f.curPitch = th, th
					targets[s] = trueCF:PointToObjectSpace(R.ankleOf(leg, P, F, th, sl) + V3(0, f.lift, 0))
					targets[s .. "pitch"] = th
				end
				-- (still out of reach: the foot goes - AnimLoco's toe-off - instead of being dragged)
				f.reachShort = max(0, ankleDist(leg, P, F, lf, trueCF, hip, th, sl) - dMax)
				-- (a runner's push the pelvis has already left behind: the foot leaves now - this frame is the toe-off -
				-- rather than a frame hanging in the air before its window opens)
				-- (pulling up: not while the other is in the air - it is hurried down first)
				local oth = rig.foot[s == "L" and "R" or "L"]
				-- (pulling up, a walker's too, once even its toes are out of reach: it is never dragged)
				local brk = (lo.brake or 0) > 0.3
				local goes = f.reachShort > 0.005 and f.push and moving and (run > 0.5 or (brk and f.reachShort > 0.04))
				-- (a walker's push rolled as far as the boot goes: this is the toe-off - the knee bent ~25-30 and folding
				-- on into the swing - never a leg pulled straight behind him on the tip of the shoe for the last frames of
				-- the stance, the next frame; the other foot has taken the weight)
				if not goes and f.push and moving and run < 0.5 and not brk and (f.sigma or 0) > 0.5
					and (not oth.swing or oth.t0 + oth.dur - t < 0.035) and not f.swing
					and th + max(0, th - (f.pitchF or th)) >= WALK_TOE - 1e-3 then
					-- (at the rate it rolls it reaches the boot's limit by the next frame: it leaves now, while the knee
					-- still has its bend - one frame later the leg would already be pulled straight)
					goes = true
				end
				local hold = goes and brk and oth.swing and f.reachShort <= 0.04
				if hold and oth.t0 + oth.dur - t > 0.04 then
					retime(oth, t, 0.04)
				end
				if goes and not hold then
					local off = s == "L" and lo.offL or lo.offR
					local sw = s == "L" and lo.swL or lo.swR
					local x = (lo.phase - off) % 1
					local full = sw * lo.T
					local dur = max((sw + (x > 0.5 and 1 - x or -x)) * lo.T, 0.55 * full)
					f.cycle = floor(lo.phase - off) + (x > 0.5 and 1 or 0)
					local rd, rc = runSync(rig, s, off, sw, t)
					if rd then
						dur, f.cycle = rd, rc
					end
					startSwing(f, t, dur, walkLift * clamp(dur / max(0.05, full) + 0.1, 0.4, 1), "walk")
				end
			end
		end
	end
	for _, s in ipairs(SIDES) do
		local f = rig.foot[s]
		local kf = R.solveLeg(rig, p, s, rootT, targets[s], targets[s .. "yaw"], targets[s .. "pitch"], f.kneeS, soft)
		if walking then
			-- (the ankle and the knee as they are, frame to frame: a swing is planned on from them)
			local A = trueCF:PointToWorldSpace(targets[s])
			local dtA = t - (f.ankT or -1)
			if f.ankW and dtA > 0 and dtA < 0.1 then
				-- ([Studio] dt-correct: 0.7 a frame at 60 Hz is exp(-72 dt), the same settle at 240 Hz or on a long frame)
				local ka = 1 - exp(-72 * dtA)
				f.ankV = (f.ankV or ZERO):Lerp((A - f.ankW) / dtA, ka)
				f.kVel = lerp(f.kVel or 0, (kf - (f.kAct or kf)) / dtA, ka)
			else
				f.ankV, f.kVel = ZERO, 0
			end
			f.ankW, f.ankT, f.kAct = A, t, kf
		else
			f.ankT = nil
		end
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
