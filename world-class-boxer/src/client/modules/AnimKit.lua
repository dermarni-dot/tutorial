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

------------------------------------------------------------------------
-- Gradient noise (1D Perlin): smooth (C2), deterministic per seed, never repeats like a sum of
-- sines does. Range about -1..1. No tables, no allocation.
------------------------------------------------------------------------
local function grad(i, seed)
	-- the classic shader hash: fract(sin(n) * 43758.5453) -> -1..1
	local s = sin(i * 12.9898 + seed * 78.233) * 43758.5453
	return (s - floor(s)) * 2 - 1
end

function AnimKit.noise1(x, seed)
	seed = seed or 0
	local i = floor(x)
	local f = x - i
	local g0, g1 = grad(i, seed), grad(i + 1, seed)
	-- quintic fade (C2: no visible kinks in velocity)
	local u = f * f * f * (f * (f * 6 - 15) + 10)
	return (g0 * f + (g1 * (f - 1) - g0 * f) * u) * 2
end

-- fractal noise: two octaves, the second a quarter as strong (organic drift with a little texture)
function AnimKit.fbm(x, seed)
	return (AnimKit.noise1(x, seed) + 0.35 * AnimKit.noise1(x * 2.13 + 7.1, seed + 19)) / 1.35
end

-- smooth window: 0 below a, 1 above b (smoothstep), works for a > b too (falling edge)
function AnimKit.ramp(x, a, b)
	if a == b then
		return x >= a and 1 or 0
	end
	return AnimKit.smooth((x - a) / (b - a))
end

-- 0 -> 1 -> 0 between a and b, peaking at the middle (smoothstep up, smoothstep down)
function AnimKit.bump(x, a, b)
	if x <= a or x >= b then
		return 0
	end
	local u = (x - a) / (b - a)
	return u < 0.5 and AnimKit.smooth(u * 2) or AnimKit.smooth(2 - u * 2)
end

-- quintic smootherstep (zero velocity AND acceleration at both ends)
function AnimKit.smoother(x)
	x = clamp(x, 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
end

-- accelerating drive that arrives with its highest speed: 0 -> 1, derivative grows with x
function AnimKit.drive(x, p)
	x = clamp(x, 0, 1)
	return x ^ (p or 1.8)
end

-- 0 -> 1 with zero speed at both ends but most of the travel early (velocity ~ u (1-u)^2): a
-- running foot leaves the ground and accelerates forward at once, then slows into touchdown
function AnimKit.earlyTravel(u)
	u = clamp(u, 0, 1)
	local u2 = u * u
	return 6 * u2 - 8 * u2 * u + 3 * u2 * u2
end

-- a smooth bump u^a (1-u)^b normalised to peak at 1 (at u = a / (a + b)); flat at both ends
function AnimKit.skewBump(u, a, b)
	if u <= 0 or u >= 1 then
		return 0
	end
	local m = a / (a + b)
	local peak = m ^ a * (1 - m) ^ b
	return (u ^ a * (1 - u) ^ b) / peak
end

-- cubic Bezier on vectors (p0 .. p3) and its derivative
function AnimKit.bezier(p0, p1, p2, p3, t)
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

-- scalar spring step toward target with a damping RATIO (1 = critical); returns x, v
function AnimKit.spring2(x, v, target, freq, zeta, dt)
	local k = freq * freq
	return AnimKit.spring(x, v, target, k, 2 * zeta * freq, dt)
end

-- deterministic 0..1 from (seed, a, b): per-boxer / per-punch choices that are stable
function AnimKit.rand3(seed, a, b)
	local s = sin(seed * 12.9898 + (a or 0) * 78.233 + (b or 0) * 37.719) * 43758.5453
	return s - floor(s)
end

-- pick an index 1..n by weights {w1, w2, ...} with a 0..1 roll
function AnimKit.weighted(weights, roll)
	local total = 0
	for _, w in ipairs(weights) do
		total += w
	end
	local x = roll * total
	for i, w in ipairs(weights) do
		x -= w
		if x <= 0 then
			return i
		end
	end
	return #weights
end

return AnimKit
