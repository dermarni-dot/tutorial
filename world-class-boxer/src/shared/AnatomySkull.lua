-- AnatomySkull: the skull both mesh sections share (ANATOMY_CONTRACTS section 6). The Head section builds
-- the head's cranium from this field (its scalp IS the field's zero set; the face may add detail only below
-- the hairline) and the Hair section lays shells, clumps and strands on it.
-- Pure and deterministic (no Instances): server, client, luaurun tests and the offline renderer agree.
-- Reads ONLY Hair-section look paths: rig.parts.Head, face.seed, face.shape, face.forehead, face.skullWidth,
-- face.skullLength, face.crown, face.browRidge, face.asym, g, age (so the Hair signature covers it).
--
-- AnatomySkull.Field(look)    -> fn(x, y, z) signed distance in studs, Head part space (+X right, +Y up,
--                                -Z forward), < 0 inside the scalp skin. Close to a true distance near the
--                                surface (|gradient| ~ 1), cheap enough for strand collision.
-- AnatomySkull.Hairline(look) -> fn(x, y, z) signed distance (studs, measured along the scalp) to the
--                                natural hairline: > 0 on the hair side (crown, sides above the ears,
--                                back down to the nape), < 0 on the face / ears / neck.
-- AnatomySkull.Params(look)   -> the parameter table both use (nominal space: a 1.2-stud head, scaled to
--                                the real head by P.kx / P.ky / P.kz); AnatomyHead builds on it.
-- AnatomySkull.Nominal(P)     -> fn(x, y, z) the same field in nominal space (AnatomyHead's base shape).
local AnatomySkull = {}

local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor
local sin, cos, atan2, pi = math.sin, math.cos, math.atan2, math.pi

AnatomySkull.NOMINAL = 1.2 -- the head size every nominal number below is written for

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

local function smoothstep(e0, e1, x)
	local t = clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- polynomial smooth min / max (k = blend width)
local function smin(a, b, k)
	local h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
	return b + (a - b) * h - k * h * (1 - h)
end
local function smax(a, b, k)
	return -smin(-a, -b, k)
end
AnatomySkull.smin, AnatomySkull.smax = smin, smax

-- ellipsoid distance (Quilez' bound: exact on the surface, close nearby)
local function sdE(x, y, z, rx, ry, rz)
	local px, py, pz = x / rx, y / ry, z / rz
	local k0 = sqrt(px * px + py * py + pz * pz)
	local qx, qy, qz = px / rx, py / ry, pz / rz
	local k1 = sqrt(qx * qx + qy * qy + qz * qz)
	if k1 < 1e-9 then
		return -min(rx, ry, rz)
	end
	return k0 * (k0 - 1) / k1
end
AnatomySkull.sdEllipsoid = sdE

-- superellipsoid (exponent n: 2 = ellipsoid, > 2 squarer) as an approximate distance (f - 1) / |grad f|
local function sdSuperE(x, y, z, rx, ry, rz, n)
	local ax, ay, az = abs(x) / rx + 1e-9, abs(y) / ry + 1e-9, abs(z) / rz + 1e-9
	local px, py, pz = ax ^ n, ay ^ n, az ^ n
	local s = px + py + pz
	local f = s ^ (1 / n)
	-- d f / d x = f^(1-n) * ax^(n-1) / rx ...
	local k = f / s
	local gx, gy, gz = k * px / ax / rx, k * py / ay / ry, k * pz / az / rz
	local g = sqrt(gx * gx + gy * gy + gz * gz)
	return (f - 1) / max(g, 1e-6)
end
AnatomySkull.sdSuperEllipsoid = sdSuperE

-- capsule (round cone) between two points on a vertical-ish segment: radius ra at a, rb at b
local function sdCapsule(x, y, z, ax, ay, az, bx, by, bz, ra, rb)
	local abx, aby, abz = bx - ax, by - ay, bz - az
	local px, py, pz = x - ax, y - ay, z - az
	local l2 = abx * abx + aby * aby + abz * abz
	local h = clamp((px * abx + py * aby + pz * abz) / l2, 0, 1)
	local dx, dy, dz = px - abx * h, py - aby * h, pz - abz * h
	return sqrt(dx * dx + dy * dy + dz * dz) - (ra + (rb - ra) * h)
end
AnatomySkull.sdCapsule = sdCapsule

-- deterministic hash in [0, 1) (no Random: the same numbers everywhere)
local M31 = 2147483647
local function hash(n, seed)
	local h = (n * 73856093 + (seed or 0) * 19349663 + 83492791) % M31
	h = (h * 16807) % M31
	h = (h * 48271 + 12345) % M31
	return h / M31
end
AnatomySkull.Hash = hash

local SHAPES = {
	-- forehead / temple width, crown, back fullness by face shape (the jaw and cheeks live in AnatomyHead)
	Oval = { fw = 0, crown = 0, back = 0 },
	Square = { fw = 0.03, crown = -0.01, back = 0.01 },
	Diamond = { fw = -0.05, crown = 0.02, back = 0 },
	Round = { fw = 0.02, crown = -0.02, back = 0.02 },
	Long = { fw = -0.02, crown = 0.03, back = -0.01 },
	Heart = { fw = 0.05, crown = 0.01, back = 0 },
}

------------------------------------------------------------------------
-- Parameters
------------------------------------------------------------------------
local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then
		return d
	end
	return v
end

-- the visible neck (nominal): radius r (sideways; front-back r / 0.97), centre z, a straight column from yTop
-- down to yJoin, a dome above yTop (hTop high, running up into the skull base) and a taper below yJoin (hBot
-- long, inside the Body's column). r = 0.2625 / 0.2375 x the head's X size: a Body neck column kept inside it
-- (r - 0.012 studs, AnatomySkull.Neck) is still at least the contract's minimum (0.25 / 0.225 x the head,
-- ANATOMY_CONTRACTS section 6) for any head wider than 0.96 studs, and the Body's own thinnest column today
-- (1.08 x that minimum) still wraps it
function AnatomySkull.NeckParams(female)
	return { r = female and 0.285 or 0.315, z = 0.03, yTop = -0.36, hTop = 0.26, yJoin = -0.6, hBot = 0.22 }
end

local function neckSD(N, x, y, z)
	local R = N.r
	local ez = (z - N.z) * 0.97
	local r = sqrt(x * x + ez * ez)
	if y > N.yTop then
		local q = (y - N.yTop) / N.hTop * R
		return sqrt(r * r + q * q) - R
	elseif y < N.yJoin then
		local q = (N.yJoin - y) / N.hBot * R
		return sqrt(r * r + q * q) - R
	end
	return r - R
end
AnatomySkull.NeckSD = neckSD

function AnatomySkull.Params(look)
	look = type(look) == "table" and look or {}
	local rig = type(look.rig) == "table" and look.rig or {}
	local parts = type(rig.parts) == "table" and rig.parts or {}
	local s = type(parts.Head) == "table" and parts.Head or { 1.2, 1.2, 1.2 }
	local f = type(look.face) == "table" and look.face or {}
	local female = look.g == 2
	local N = AnatomySkull.NOMINAL
	local P = {
		sx = num(s[1], N), sy = num(s[2], N), sz = num(s[3], N),
		female = female, age = num(look.age, 26), seed = floor(abs(num(f.seed, 7))) % 1000000,
	}
	P.kx, P.ky, P.kz = P.sx / N, P.sy / N, P.sz / N
	P.k = min(P.kx, P.ky, P.kz)
	local sh = SHAPES[f.shape] or SHAPES.Oval
	P.shape = SHAPES[f.shape] and f.shape or "Oval"
	local sw = clamp(num(f.skullWidth, 0), -1, 1)
	local sl = clamp(num(f.skullLength, 0), -1, 1)
	local cr = clamp(num(f.crown, 0), -1, 1)
	local fh = clamp(num(f.forehead, 0), -1, 1)
	local br = clamp(num(f.browRidge, female and 0.1 or 0.35), 0, 1)
	P.asym = clamp(num(f.asym, 0), 0, 1)
	P.browRidge = br
	P.foreheadK = fh
	-- every face is a little uneven: a baseline asymmetry plus the slider
	local a = 0.25 + P.asym
	P.skew = (hash(11, P.seed) - 0.5) * 0.012 * a -- one parietal side fuller
	P.tilt = (hash(12, P.seed) - 0.5) * 0.01 * a -- crown leaning a touch to one side
	-- cranium (nominal: a 1.2 head is 1.15 tall chin to vertex, 0.76 wide, 0.95 deep glabella to the back:
	-- the adult proportions, breadth / height ~0.66, length / height ~0.83)
	local g = female and 0.965 or 1
	P.cw = (0.382 + 0.02 * sw + 0.011 * sh.fw) * g -- half width (parietal)
	P.ch = (0.435 + 0.016 * cr + sh.crown * 0.6) * (female and 0.985 or 1) -- half height of the vault
	P.cd = (0.455 + 0.02 * sl) * g -- half depth
	P.cy = 0.15 + 0.006 * cr -- vault centre height
	P.cz = 0.035 + 0.012 * sl
	-- frontal bone: forehead fullness / slope (a bigger forehead slider = higher, more upright forehead;
	-- women: a rounder, more upright brow, the frontal bosses)
	P.fw = (0.34 + 0.023 * sh.fw + 0.011 * sw) * g
	P.fz = -0.105 - 0.008 * fh - (female and 0.008 or 0)
	P.fd = 0.345 + 0.008 * fh
	-- occipital fullness (rounded back of the head)
	P.ow = (0.305 + 0.014 * sw) * g
	P.oz = 0.235 + 0.014 * sl + 0.01 * sh.back
	P.od = 0.27 + 0.01 * sl
	-- temporal hollows (a lean adult shows them more; boxers' temples are firm)
	P.tempD = 0.012 + (female and 0 or 0.004)
	-- brow ridge share the skull carries (the face adds the rest below the hairline)
	P.ridge = 0.004 + 0.012 * br * (female and 0.3 or 1)
	-- the neck the Head section shows (AnatomySkull.Neck): a column from under the skull base down to the
	-- junction just under the neck pivot (y -0.6), then tapering away inside the Body's neck column
	P.neck = AnatomySkull.NeckParams(female)
	P.neckR = P.neck.r
	P.neckZ = P.neck.z
	-- hairline (natural: Hair styles the line itself): trichion height, temple recession with age
	local recede = clamp((P.age - 24) / 30, 0, 1) * (female and 0.15 or 0.75)
	P.hairFront = 0.335 + 0.04 * fh + 0.012 * cr + 0.02 * recede
	P.hairTemple = P.hairFront - (female and 0.035 or 0.06) - 0.06 * recede
	P.recede = recede
	return P
end

------------------------------------------------------------------------
-- The field (nominal space)
------------------------------------------------------------------------
-- cranium vault + frontal bone + occiput, temporal hollows, a mild brow ridge, the face mass and the neck
-- stub. AnatomyHead adds jaw / cheekbones / nose ... below the hairline only.
function AnatomySkull.Nominal(P)
	local cw, ch, cd, cy, cz = P.cw, P.ch, P.cd, P.cy, P.cz
	local fw, fz, fd = P.fw, P.fz, P.fd
	local ow, oz, od = P.ow, P.oz, P.od
	local skew, tilt = P.skew, P.tilt
	local tempD, ridge = P.tempD, P.ridge
	local neck = P.neck
	return function(x, y, z)
		-- a touch of asymmetry: one side of the vault fuller, the crown leaning
		local xs = x * (1 - skew * (x > 0 and 1 or -1)) - tilt * (y - 0.1)
		local d = sdSuperE(xs, y - cy, z - cz, cw, ch, cd, 2.45)
		-- frontal bone: an upright forehead
		d = smin(d, sdE(xs, y - 0.2, z - fz, fw, 0.37, fd), 0.09)
		-- occiput
		d = smin(d, sdE(xs, y - 0.02, z - oz, ow, 0.31, od), 0.11)
		-- the neck: the skull base runs into it at the back (its dome top ends at y -0.1; evaluated from well
		-- above it, so the blend never stops at a height: a cut there would crease the nape)
		if y < 0.02 then
			d = smin(d, neckSD(neck, x, y, z), 0.09)
		end
		-- the midface under the forehead (generic; the Head section refines the face below the hairline)
		d = smin(d, sdE(xs, y + 0.1, z + 0.11, 0.32, 0.36, 0.33), 0.07)
		-- temporal hollows above the zygomatic arch, behind the brow
		local tx = abs(xs) - 0.43
		local td = (tx * tx) / 0.0121 + ((y - 0.07) ^ 2) / 0.0169 + ((z + 0.17) ^ 2) / 0.03
		if td < 1 then
			local w = 1 - td
			d += tempD * w * w
		end
		-- the supraorbital ridge the skull carries (soft; the face sharpens it)
		local by = (y - 0.085) / 0.045
		local bz = (z + 0.42) / 0.09
		local bx = abs(x) / 0.33
		local bw = by * by + bz * bz + bx * bx * bx * bx
		if bw < 1 then
			local w = 1 - bw
			d -= ridge * w * w
		end
		return d
	end
end

-- head part space wrapper (scales the nominal field; distances scale by the smallest factor)
local function wrap(P, fn)
	local kx, ky, kz, k = P.kx, P.ky, P.kz, P.k
	if abs(kx - 1) < 1e-9 and abs(ky - 1) < 1e-9 and abs(kz - 1) < 1e-9 then
		return fn
	end
	return function(x, y, z)
		return fn(x / kx, y / ky, z / kz) * k
	end
end

-- the visible neck in the Head part's space (studs): { r = side radius, rz = front-back half depth, z = centre,
-- yTop / yJoin (the straight column between them), hTop, hBot }. The Body keeps its neck column inside
-- r - 0.012 above yJoin (the Head's neck is what shows there); below yJoin the Body's column takes over
function AnatomySkull.Neck(look)
	local P = AnatomySkull.Params(look)
	local N = P.neck
	return {
		r = N.r * P.kx, rz = N.r / 0.97 * P.kz, z = N.z * P.kz, yTop = N.yTop * P.ky, yJoin = N.yJoin * P.ky,
		hTop = N.hTop * P.ky, hBot = N.hBot * P.ky,
	}
end

function AnatomySkull.Field(look)
	local P = AnatomySkull.Params(look)
	return wrap(P, AnatomySkull.Nominal(P))
end

------------------------------------------------------------------------
-- Hairline (nominal space): the line where the natural hair stops, as a height per angle around the head
------------------------------------------------------------------------
-- azimuth a around the vertical axis: 0 = +X (right), pi/2 = front (-Z), pi = left, 3pi/2 = back. Key heights
-- (front centre, temple corner, sideburn, above the ear, behind the ear, nape) on a closed loop, smoothed.
function AnatomySkull.HairlineHeights(P)
	local front, temple = P.hairFront, P.hairTemple
	local fem = P.female
	local rec = P.recede
	-- angles from the front centre (radians, either side; the ear spans ~1.45 .. 1.95) and heights
	return {
		{ 0.0, front },
		{ 0.35, front - 0.012 - 0.02 * rec }, -- the forehead line rounds down a little
		{ 0.64, temple }, -- temple corner (recedes with age)
		{ 0.98, temple - 0.04 }, -- temple flank
		{ 1.2, temple - 0.09 }, -- top of the sideburn's front edge
		{ 1.3, fem and 0.0 or -0.07 }, -- sideburn bottom (in front of the ear)
		{ 1.42, fem and 0.03 or -0.02 }, -- sideburn back edge, at the front of the ear
		{ 1.52, 0.1 }, -- over the ear
		{ 1.74, 0.125 },
		{ 1.95, 0.1 },
		{ 2.08, -0.06 }, -- behind the ear, down the mastoid
		{ 2.45, -0.17 },
		{ pi, -0.27 }, -- nape centre
	}
end

local function hairlineAt(K, da)
	-- piecewise smooth (cosine) interpolation over |angle from the front|
	local n = #K
	if da <= K[1][1] then
		return K[1][2], 0
	end
	for i = 1, n - 1 do
		local a0, a1 = K[i][1], K[i + 1][1]
		if da <= a1 then
			local t = (da - a0) / (a1 - a0)
			local s = (1 - cos(t * pi)) * 0.5
			local h = K[i][2] + (K[i + 1][2] - K[i][2]) * s
			local slope = (K[i + 1][2] - K[i][2]) * 0.5 * pi * sin(t * pi) / (a1 - a0)
			return h, slope
		end
	end
	return K[n][2], 0
end

function AnatomySkull.NominalHairline(P)
	local K = AnatomySkull.HairlineHeights(P)
	local seed = P.seed
	local skew = P.skew
	return function(x, y, z)
		-- angle from the front centre around a vertical axis through the head
		local a = atan2(-(z - 0.05), x) -- 0 = right, pi/2 = front
		local da = abs(a - pi / 2)
		if da > pi then
			da = 2 * pi - da
		end
		local h, slope = hairlineAt(K, da)
		-- an irregular natural edge (a few millimetres), a little uneven left / right
		local wob = 0.006 * sin(da * 9 + seed % 7) + 0.004 * sin(da * 23 + seed % 11)
		h += wob + (x > 0 and skew or -skew) * 0.6
		-- radius of the head at this height (arc length per radian of angle)
		local r = sqrt(x * x + (z - 0.05) ^ 2)
		local ds = max(r, 0.15)
		-- distance perpendicular to the line on the unrolled scalp: (y - h) / sqrt(1 + (dh/ds)^2)
		local sl = slope / ds
		return (y - h) / sqrt(1 + sl * sl)
	end
end

function AnatomySkull.Hairline(look)
	local P = AnatomySkull.Params(look)
	return wrap(P, AnatomySkull.NominalHairline(P))
end

return AnatomySkull
