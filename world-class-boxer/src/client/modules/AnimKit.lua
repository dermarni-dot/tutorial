-- AnimKit: the pure math behind the procedural animation (no Instances, no Roblox services), so it
-- can be unit-tested outside Roblox. Used by the Animator, BodyFX, FaceFX and HairFX.
--  * easing curves and pulses
--  * act string parser (kind|f2|f3|f4|f5, CONTRACTS section 8; old 4-field strings still parse)
--  * analytic two-bone IK for legs (planted feet) and arms (punch aim)
--  * damped springs (semi-implicit Euler with sub-steps, stable at low frame rates)
--  * cheap smooth noise for idle life (no tables, no allocation)
local AnimKit = {}

local sqrt, atan2, acos, sin, cos, abs, floor = math.sqrt, math.atan2, math.acos, math.sin, math.cos, math.abs, math.floor
local PI = math.pi

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end
AnimKit.clamp = clamp

function AnimKit.clamp01(x)
	return clamp(x, 0, 1)
end

-- smoothstep
function AnimKit.smooth(x)
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- fast start, soft landing: the drive phase of a punch
function AnimKit.easeOut(x)
	x = 1 - clamp(x, 0, 1)
	return 1 - x * x * x
end

function AnimKit.easeIn(x)
	x = clamp(x, 0, 1)
	return x * x
end

function AnimKit.easeInOut(x)
	x = clamp(x, 0, 1)
	if x < 0.5 then
		return 4 * x * x * x
	end
	local f = -2 * x + 2
	return 1 - f * f * f / 2
end

-- overshoots by about `s` * 10% before settling at 1 (the snap at the end of a punch)
function AnimKit.easeOutBack(x, s)
	x = clamp(x, 0, 1)
	s = s or 1.2
	local c3 = s + 1
	local y = x - 1
	return 1 + c3 * y * y * y + s * y * y
end

-- 0 -> 1 -> 0 half-sine over `dur`; nil once finished
function AnimKit.pulse(el, dur)
	if el >= dur or dur <= 0 then
		return nil
	end
	if el <= 0 then
		return 0
	end
	return sin(PI * el / dur)
end

-- quick rise, slow decay (impact envelopes): 0 at el=0, 1 at el=rise, 0 at el=dur
function AnimKit.attackDecay(el, rise, dur)
	if el <= 0 or el >= dur then
		return 0
	end
	if el < rise then
		return AnimKit.smooth(el / rise)
	end
	return 1 - AnimKit.smooth((el - rise) / (dur - rise))
end

function AnimKit.lerp(a, b, t)
	return a + (b - a) * t
end

-- frame-rate independent exponential approach
function AnimKit.approach(cur, target, rate, dt)
	return target + (cur - target) * math.exp(-rate * dt)
end

-- wrap an angle into -pi..pi
function AnimKit.wrap(a)
	a = (a + PI) % (2 * PI)
	return a - PI
end

------------------------------------------------------------------------
-- Act strings: "kind|f2|f3|f4|f5". Returns the five fields (missing ones are "").
------------------------------------------------------------------------
function AnimKit.parseAct(s)
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local a, b, c, d, e = string.match(s, "^([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)")
	if not a or a == "" then
		return nil
	end
	return a, b or "", c or "", d or "", e or ""
end

------------------------------------------------------------------------
-- Leg IK. The leg hangs along -Y of the hip joint frame with the knee bending backwards (+Z).
-- (dx, dy, dz) = ankle target relative to the hip joint, in the hip joint frame.
-- Returns hipPitch, hipRoll, kneeFlex (>= 0) such that
--   hip = CFrame.Angles(0, 0, hipRoll) * CFrame.Angles(hipPitch, 0, 0),  knee = CFrame.Angles(-kneeFlex, 0, 0)
-- puts the ankle on the target (clamped to the leg's reach), and a reach factor (1 = reached).
------------------------------------------------------------------------
function AnimKit.legIK(dx, dy, dz, l1, l2)
	local d = sqrt(dx * dx + dy * dy + dz * dz)
	local maxD = (l1 + l2) * 0.9995
	local minD = abs(l1 - l2) + 0.02
	local reach = 1
	if d < 1e-6 then
		dx, dy, dz, d = 0, -minD, 0, minD
	end
	if d > maxD then
		reach = maxD / d
		dx, dy, dz, d = dx * reach, dy * reach, dz * reach, maxD
	elseif d < minD then
		local k = minD / d
		dx, dy, dz, d = dx * k, dy * k, dz * k, minD
	end
	local cphi = clamp((d * d - l1 * l1 - l2 * l2) / (2 * l1 * l2), -1, 1)
	local phi = acos(cphi) -- knee flexion
	-- the bent leg vector before the hip turns it: thigh down, shin swung back by phi
	local vy = -l1 - l2 * cphi
	local vz = l2 * sin(phi)
	local rho = sqrt(dx * dx + dy * dy)
	local roll = atan2(dx, -dy)
	local thv = atan2(vz, -vy)
	local thw = atan2(dz, rho)
	return thv - thw, roll, phi, reach
end

------------------------------------------------------------------------
-- Arm IK (straight punches). The arm hangs along -Y of the shoulder frame and the elbow flexes
-- with a POSITIVE pitch (forearm swings forward, -Z). (dx, dy, dz) = fist target in the shoulder
-- frame. Returns shoulderYaw, shoulderPitch, elbowFlex such that
--   shoulder = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0),  elbow = CFrame.Angles(flex, 0, 0)
-- puts the fist on the target; the elbow points down (the natural line of a jab / cross).
------------------------------------------------------------------------
function AnimKit.armIK(dx, dy, dz, a, b)
	local d = sqrt(dx * dx + dy * dy + dz * dz)
	local maxD = (a + b) * 0.999
	local minD = abs(a - b) + 0.05
	local reach = 1
	if d < 1e-6 then
		dx, dy, dz, d = 0, 0, -minD, minD
	end
	if d > maxD then
		reach = maxD / d
		dx, dy, dz, d = dx * reach, dy * reach, dz * reach, maxD
	elseif d < minD then
		local k = minD / d
		dx, dy, dz, d = dx * k, dy * k, dz * k, minD
	end
	local cphi = clamp((d * d - a * a - b * b) / (2 * a * b), -1, 1)
	local phi = acos(cphi)
	local vy = -a - b * cphi
	local vz = -b * sin(phi)
	-- yaw swings the (y, z') plane around Y so that z' points at the target horizontally
	local h = sqrt(dx * dx + dz * dz)
	local yaw = 0
	if h > 1e-5 then
		-- the pitched arm lies in the (y, -h) half-plane; yaw turns that plane onto (dx, dz)
		yaw = atan2(-dx, -dz)
	end
	local thv = atan2(vz, -vy)
	local thw = atan2(-h, -dy)
	return yaw, thv - thw, phi, reach
end

------------------------------------------------------------------------
-- Two-bone chain by points (any rest geometry): shoulder at the origin, target (dx, dy, dz),
-- bone lengths a, b, and a pole direction (px, py, pz) the elbow bends towards.
-- Returns the elbow point and the (reach-clamped) end point.
------------------------------------------------------------------------
function AnimKit.chainPoints(dx, dy, dz, a, b, px, py, pz)
	local d = sqrt(dx * dx + dy * dy + dz * dz)
	local maxD = (a + b) * 0.999
	local minD = abs(a - b) + 0.05
	if d < 1e-6 then
		dx, dy, dz, d = 0, -minD, 0, minD
	end
	local k = 1
	if d > maxD then
		k = maxD / d
	elseif d < minD then
		k = minD / d
	end
	dx, dy, dz, d = dx * k, dy * k, dz * k, d * k
	local ux, uy, uz = dx / d, dy / d, dz / d
	-- distance along the shoulder->end line to the elbow's projection, and the elbow's offset
	local x = (a * a - b * b + d * d) / (2 * d)
	local h = sqrt(math.max(0, a * a - x * x))
	-- pole made perpendicular to the line
	local pd = px * ux + py * uy + pz * uz
	local nx, ny, nz = px - pd * ux, py - pd * uy, pz - pd * uz
	local nl = sqrt(nx * nx + ny * ny + nz * nz)
	if nl < 1e-6 then
		-- pole along the line: any perpendicular will do
		nx, ny, nz = -uy, ux, 0
		nl = sqrt(nx * nx + ny * ny)
		if nl < 1e-6 then
			nx, ny, nz, nl = 1, 0, 0, 1
		end
	end
	nx, ny, nz = nx / nl, ny / nl, nz / nl
	return ux * x + nx * h, uy * x + ny * h, uz * x + nz * h, dx, dy, dz
end

------------------------------------------------------------------------
-- Soft IK: the reach approaches full extension asymptotically, so a joint never snaps straight
-- (dAngle/dDistance blows up at full extension). maxD = full reach, soft = softening band.
------------------------------------------------------------------------
function AnimKit.softReach(d, maxD, soft)
	local start = maxD - soft
	if d <= start or soft <= 0 then
		return d
	end
	return start + soft * (1 - math.exp(-(d - start) / soft))
end

------------------------------------------------------------------------
-- Damped spring toward target. k = stiffness, c = damping. Sub-steps keep it stable at 20 fps.
------------------------------------------------------------------------
function AnimKit.spring(x, v, target, k, c, dt)
	local n = dt > 1 / 60 and math.min(6, math.ceil(dt * 60)) or 1
	local h = dt / n
	for _ = 1, n do
		local a = -k * (x - target) - c * v
		v += a * h
		x += v * h
	end
	return x, v
end

-- critical damping for a stiffness, scaled by a damping ratio
function AnimKit.damping(k, zeta)
	return 2 * (zeta or 1) * sqrt(k)
end

------------------------------------------------------------------------
-- Gravity in a joint frame whose rest axis is -Y: the X / Z rotations that would point -Y at the
-- vector (gx, gy, gz) (used by hair: how far gravity pulls a strand away from its built shape).
------------------------------------------------------------------------
function AnimKit.gravityAngles(gx, gy, gz)
	-- CFrame.Angles(ax, 0, 0) turns -Y towards -Z; CFrame.Angles(0, 0, az) turns -Y towards +X
	return atan2(-gz, -gy), atan2(gx, -gy)
end

------------------------------------------------------------------------
-- Smooth deterministic noise in -1..1 (sum of incommensurate sines; no tables, no allocation)
------------------------------------------------------------------------
function AnimKit.noise(t, seed)
	seed = seed or 0
	return (sin(t * 1.13 + seed * 1.7) * 0.5 + sin(t * 2.71 + seed * 3.1) * 0.3 + sin(t * 4.33 + seed * 0.37) * 0.2)
end

-- integer hash -> 0..1 (stable per seed/index)
function AnimKit.hash01(n)
	n = (n * 1103515245 + 12345) % 2147483648
	n = (n * 1103515245 + 12345) % 2147483648
	return (n % 100000) / 100000
end

-- deterministic per-index pick in [a, b]
function AnimKit.pick(seed, i, a, b)
	return a + (b - a) * AnimKit.hash01(floor(seed) * 131 + i * 977)
end

-- breathing curve: inhale quicker than exhale (more natural than a sine)
function AnimKit.breath(phase)
	local x = phase % 1
	if x < 0.4 then
		return AnimKit.smooth(x / 0.4)
	end
	return 1 - AnimKit.smooth((x - 0.4) / 0.6)
end

return AnimKit
