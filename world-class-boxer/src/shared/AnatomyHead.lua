-- AnatomyHead: organic head / face meshes for the Head section (ANATOMY_CONTRACTS.md).
-- The head is one closed surface: rays from a smooth family (crown cap, a horizontal face band, chin / neck
-- cap) hit the shared skull (AnatomySkull) blended with a face skeleton (lower-face contour slices, the
-- zygomatic arches) and are pushed out by the soft-tissue relief (brow ridge, orbits, nose by type, cheeks,
-- lips with the cupid's bow, philtrum, nasolabial folds, chin, jaw line, jowls); rows / columns crowd where
-- the features are. The eye sockets dive behind separate eyeball pieces; upper / lower lids are separate
-- shells (blinks are rigid turns); ears are closed pillows in the Head piece; the mouth interior (teeth,
-- tongue, throat) is two pieces, the lower one swinging with the jaw; beards are shells grown from the grid.
-- Colour: vertex colours (AnatomyHeadPaint) + a texture made on first use (pores, brow hairs, stubble,
-- lips, wrinkles, freckles, moles, scars). Motion: AnatomyHeadRig morphs (FaceFX channels, swelling).
local MeshKit = require(script.Parent:WaitForChild("MeshKit"))
local Skull = require(script.Parent:WaitForChild("AnatomySkull"))
local Paint = require(script.Parent:WaitForChild("AnatomyHeadPaint"))
local Rig = require(script.Parent:WaitForChild("AnatomyHeadRig"))

local Gen = {}
Gen.Section = "Head"
Gen.LODs = { full = true, medium = true, low = true }
-- the whole round-1 face (rig parts included: FaceFX drives the mesh lids / eyes / jaw / blend shapes), the
-- beard, face sweat / grime and the face damage parts (all positioned for the round-1 head; FaceFX draws
-- the damage on the mesh) are replaced; the round-1 neck would cut through the mesh jaw
Gen.Replaces = function()
	return { { r15 = "Head" }, { folder = "Face" }, { folder = "Beard" }, { folder = "FaceSweat" }, { folder = "FaceGrime" },
		{ folder = "Damage", except = { "BloodChest" } }, { folder = "Muscles", names = { "Neck", "NeckSCM" } } }
end

local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor
local sin, cos, pi, exp = math.sin, math.cos, math.pi, math.exp
local TAU = 2 * pi
local smin = Skull.smin
local sdE, sdCapsule, hash = Skull.sdEllipsoid, Skull.sdCapsule, Skull.Hash

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
local function lerp(a, b, t)
	return a + (b - a) * t
end
local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then
		return d
	end
	return v
end
-- smooth bump of a squared distance: 1 at 0, 0 at q2 >= 1, C2 at the edge (no shading line there)
local function bump(q2)
	if q2 >= 1 then
		return 0
	end
	local w = 1 - q2
	return w * w * w
end

------------------------------------------------------------------------
-- Layout: every feature position in nominal space (a 1.2-stud head)
------------------------------------------------------------------------
local SHAPE = {
	Oval = { jaw = 0, cheek = 0, chinW = 0, chinDrop = 0, len = 0, round = 0 },
	Square = { jaw = 0.5, cheek = 0.05, chinW = 0.3, chinDrop = 0, len = -0.01, round = -0.2 },
	Diamond = { jaw = -0.35, cheek = 0.6, chinW = -0.3, chinDrop = 0.005, len = 0.01, round = -0.1 },
	Round = { jaw = 0.25, cheek = -0.1, chinW = 0.1, chinDrop = -0.01, len = -0.02, round = 0.7 },
	Long = { jaw = -0.1, cheek = -0.2, chinW = -0.1, chinDrop = 0.03, len = 0.035, round = -0.2 },
	Heart = { jaw = -0.4, cheek = 0.25, chinW = -0.45, chinDrop = 0.01, len = 0.01, round = 0 },
}

-- nose types: bridge height (at the nasion / mid / tip), dorsal hump, tip projection / droop, bulb,
-- alar width, nostril flare, length scale
local NOSE = {
	Straight = { root = 0.0, hump = 0.0, scoop = 0.0, tip = 0.0, droop = 0.0, bulb = 0.0, ala = 0.0, len = 0.0, bridgeW = 0.0 },
	Roman = { root = 0.01, hump = 0.012, scoop = 0, tip = 0.005, droop = 0.01, bulb = -0.1, ala = 0.0, len = 0.03, bridgeW = 0.05 },
	Button = { root = -0.012, hump = 0, scoop = 0.006, tip = -0.012, droop = -0.012, bulb = 0.35, ala = -0.05, len = -0.06, bridgeW = -0.1 },
	Snub = { root = -0.008, hump = 0, scoop = 0.01, tip = -0.004, droop = -0.022, bulb = 0.1, ala = 0.0, len = -0.05, bridgeW = -0.05 },
	Hawk = { root = 0.014, hump = 0.02, scoop = 0, tip = 0.012, droop = 0.022, bulb = -0.2, ala = -0.05, len = 0.06, bridgeW = 0.0 },
	Wide = { root = -0.006, hump = 0, scoop = 0, tip = -0.004, droop = 0, bulb = 0.3, ala = 0.32, len = 0.0, bridgeW = 0.25 },
	Flat = { root = -0.02, hump = 0, scoop = 0.004, tip = -0.022, droop = 0, bulb = 0.2, ala = 0.38, len = -0.03, bridgeW = 0.35 },
	Nubian = { root = -0.012, hump = 0, scoop = 0, tip = -0.006, droop = -0.004, bulb = 0.35, ala = 0.42, len = 0.0, bridgeW = 0.22 },
	Greek = { root = 0.02, hump = 0, scoop = 0, tip = 0.006, droop = 0.0, bulb = -0.15, ala = -0.05, len = 0.02, bridgeW = 0.0 },
	Boxer = { root = -0.016, hump = 0.004, scoop = 0, tip = -0.016, droop = 0.006, bulb = 0.3, ala = 0.3, len = -0.02, bridgeW = 0.4 },
}

local function layout(look)
	local P = Skull.Params(look)
	local f = type(look.face) == "table" and look.face or {}
	local battle = type(look.battle) == "table" and look.battle or {}
	local body = type(look.body) == "table" and look.body or {}
	local female = P.female
	local sh = SHAPE[f.shape] or SHAPE.Oval
	local F = { P = P, female = female, seed = P.seed }
	local function fv(k, d, lo, hi)
		return clamp(num(f[k], d), lo or -1, hi or 1)
	end
	F.age = P.age
	F.fat = num(body.fat, 14)
	F.dry = clamp(num(body.dry, 0), 0, 1)
	-- fat in the face: full cheeks from ~18 %, jowls from ~20 %; lean / cut faces hollow out
	F.faceFat = clamp((F.fat - 17) / 9, 0, 1)
	F.jowl = clamp((F.fat - 20) / 8, 0, 1)
	-- lean fighters are lean, not hollow: a little hollowing below ~9 % fat or when dried out for a weigh-in
	F.gaunt = max(clamp((9 - F.fat) / 3, 0, 1) * 0.7, F.dry * 0.8)
	F.cheekFull = fv("cheekFull", 0)
	local asymA = 0.3 + P.asym
	local seed = P.seed
	local function rnd(i)
		return (hash(i, seed + 977) - 0.5) * 2 -- [-1, 1]
	end
	F.rnd = rnd
	-- eyes
	F.eyeSize = fv("eyeSize", 0)
	F.eyeR = 0.06 * (1 + 0.05 * F.eyeSize) * (female and 1.03 or 1)
	F.eyeX = 0.163 + 0.014 * fv("eyeDist", 0) + (female and -0.004 or 0)
	F.eyeY = 0.0 + 0.008 * sh.len
	F.eyeDepth = fv("eyeDepth", 0.3, 0, 1)
	F.eyeZ = -0.352 + 0.014 * F.eyeDepth
	F.eye = {}
	for side = -1, 1, 2 do
		F.eye[side] = { x = side * F.eyeX + rnd(1) * 0.004 * asymA * 0.5, y = F.eyeY + side * rnd(2) * 0.007 * asymA, z = F.eyeZ }
	end
	F.eyeShape = fv("eyeShape", 0.5, 0, 1) -- 0 round .. 1 almond
	F.tilt = fv("eyeTilt", 0) * 0.12 + 0.035 -- canthal tilt (radians, outer corner up)
	F.lidHeavy = fv("lidHeavy", 0, 0, 1)
	-- the eye opening in angles seen from the eyeball centre: canthi azimuths, margin elevations
	local es, ez = F.eyeShape, F.eyeSize
	F.aLat = math.rad(79 + 4 * es)
	F.aMed = -math.rad(64 + 3 * es)
	F.bUp = math.rad(21 + 2.5 * ez - 3 * es) * (1 - 0.2 * F.lidHeavy) -- upper margin at its peak (over the iris top)
	F.bDn = math.rad(22 + 1.5 * ez - 3 * es) -- lower margin (just over the iris bottom: relaxed, not staring)
	F.pUp = 0.45 + 0.35 * es -- corner sharpness
	F.pDn = 0.6 + 0.3 * es
	F.gUp = math.rad(15) * (1 - 0.65 * F.lidHeavy) + math.rad(3) * clamp((F.age - 35) / 25, 0, 1) -- visible upper lid (crease)
	F.gDn = math.rad(10)
	F.lidOut = 0.0105 -- upper lid outer surface (radius over the eyeball)
	F.lowOut = 0.0125 -- lower lid sits over the upper one where they meet
	F.lashes = fv("lashes", female and 0.8 or 0.2, 0, 1)
	-- brows
	F.browY = F.eyeY + 0.096 + 0.014 * fv("browHeight", 0) + 0.006 * fv("forehead", 0) + (female and 0.008 or 0)
	F.browAngle = fv("browAngle", 0)
	F.browThick = fv("browThick", 0)
	F.browRidge = P.browRidge
	F.browStyle = f.browStyle
	F.browAsym = { [-1] = rnd(8) * 0.006 * asymA, [1] = rnd(9) * 0.006 * asymA }
	-- nose
	local nt = NOSE[f.noseType] or NOSE.Straight
	F.noseType = NOSE[f.noseType] and f.noseType or "Straight"
	F.nt = nt
	F.noseBreak = max(fv("noseBreak", 0, 0, 1), clamp(num(battle.nose, 0), 0, 1))
	local nlen = 1 + 0.12 * fv("noseLength", 0) + nt.len
	F.nasionY = F.eyeY + 0.048
	F.noseBaseY = F.nasionY - 0.272 * nlen * (female and 0.94 or 1)
	F.noseTipY = F.noseBaseY + 0.045
	F.noseW = (0.088 + 0.016 * fv("noseWidth", 0)) * (1 + nt.ala * 0.45) * (1 + 0.15 * F.noseBreak) * (female and 0.9 or 1) -- alar half width
	F.nostrilFlare = fv("nostrilFlare", 0.3, 0, 1)
	F.bridge = fv("noseBridge", 0)
	F.noseTip = fv("noseTip", 0)
	F.noseDev = rnd(3) * 0.008 * asymA + F.noseBreak * 0.02 * (hash(303, seed) < 0.5 and -1 or 1)
	-- mouth
	F.mouthY = F.noseBaseY - 0.103 - 0.012 * sh.len
	F.mouthW = (0.128 + 0.012 * fv("mouthWidth", 0) + 0.004 * fv("lips", 0)) * (female and 0.95 or 1)
	F.lips = fv("lips", 0) + (female and 0.25 or 0)
	F.lipBow = fv("lipBow", female and 0.6 or 0.4, 0, 1)
	F.mouthTilt = rnd(4) * 0.03 * asymA
	-- the mouth line: corners a touch up when young, down with age
	F.mouthCurve = 0.25 - 0.9 * clamp((F.age - 30) / 30, 0, 1) + rnd(6) * 0.15
	do
		local mY, mW, mt, curve = F.mouthY, F.mouthW, F.mouthTilt, F.mouthCurve
		local lipK, bow = F.lips, F.lipBow
		-- the stomion line (where the lips meet) at x
		F.mouthLine = function(x)
			return mY + mt * x + curve * x * x
		end
		-- the lips at x: vermilion heights above / below the stomion (the upper lip carries the cupid's bow:
		-- two peaks and a dip; both taper to a point at the corners), their protrusions, and the tapers
		F.lipShape = function(x)
			local xr = abs(x) / mW
			local t1 = max(0, 1 - xr ^ 1.6)
			local t2 = max(0, 1 - xr * xr)
			local hu = (0.031 + 0.008 * lipK) * (t1 ^ 0.7) * (1 + 0.2 * bow * bump(((xr - 0.32) / 0.24) ^ 2) - 0.15 * bow * bump((x / 0.018) ^ 2))
			local hl = (0.04 + 0.01 * lipK) * (t2 ^ 0.55)
			local pu = (0.028 + 0.008 * lipK) * t1 ^ 0.55
			local pl = (0.032 + 0.009 * lipK) * t2 ^ 0.5
			return hu, hl, pu, pl, t1, t2
		end
		F.lipH = function(x)
			local hu, hl = F.lipShape(x)
			return hu, hl
		end
	end
	-- chin / jaw
	F.chin = fv("chin", 0)
	F.chinProject = fv("chinProject", 0)
	F.chinCleft = fv("chinCleft", 0, 0, 1)
	F.chinY = -0.512 - sh.chinDrop - 0.01 * F.chin + sh.len * 0.5 + (female and 0.008 or 0)
	F.chinW = (0.085 + 0.016 * F.chin + 0.025 * sh.chinW) * (female and 0.85 or 1)
	F.jawW = (0.24 + 0.025 * fv("jawWidth", 0) + 0.03 * sh.jaw + rnd(5) * 0.006 * asymA) * (female and 0.92 or 1)
	F.jawDef = clamp(fv("jawDef", 0.5, 0, 1) * 0.6 + fv("jawAngle", female and 0.3 or 0.55, 0, 1) * 0.4 - 0.25 * sh.round, 0, 1)
	F.gonionY = -0.39 + 0.02 * (1 - F.jawDef) + sh.len * 0.3
	-- cheeks
	F.cheek = fv("cheek", 0) + sh.cheek
	F.cheekH = fv("cheekHeight", 0)
	F.round = sh.round
	-- ears
	F.earSize = 1 + 0.1 * fv("earSize", 0)
	F.cauli = max(fv("cauliflower", 0, 0, 1), clamp(num(battle.ears, 0), 0, 1))
	F.scars = type(battle.scars) == "table" and battle.scars or {}
	-- skin sliders (paint)
	F.wrinkles = max(fv("wrinkles", 0, 0, 1), clamp((F.age - 30) / 26, 0, 1) * 0.85)
	return F
end
Gen.Layout = layout

------------------------------------------------------------------------
-- The base field: the shared skull + the face skeleton the face sliders shape
------------------------------------------------------------------------
-- Catmull-Rom over key rows { y, v1, v2, ... } sorted by descending y; returns column col at height y
local function keyed(K, y, col)
	local n = #K
	if y >= K[1][1] then
		return K[1][col]
	elseif y <= K[n][1] then
		return K[n][col]
	end
	local i = 1
	while K[i + 1][1] > y do
		i += 1
	end
	local u = (K[i][1] - y) / (K[i][1] - K[i + 1][1])
	local p0, p1, p2, p3 = K[max(i - 1, 1)][col], K[i][col], K[i + 1][col], K[min(i + 2, n)][col]
	return 0.5 * (2 * p1 + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (3 * p1 - p0 - 3 * p2 + p3) * u * u * u)
end

-- the lower face as horizontal contour slices (half width, front depth, squareness) cut by the jaw's
-- lower border, which slopes from the menton up to the gonion: one volume, one crisp jawline
local function lowerFaceSlices(F)
	local jw = F.jawW / 0.24 -- jaw width factor (1 = average)
	local fem = F.female
	local cy = F.chinY
	local mY = F.mouthY
	local cwk = F.chinW / 0.085
	local cp = F.chinProject
	local lipK = F.lips
	-- { y, half width, front z, front exponent }
	local K = {
		{ F.eyeY - 0.07, 0.345, -0.4, 2.0 },
		{ F.eyeY - 0.17, 0.33, -0.425, 2.1 },
		{ F.noseBaseY - 0.01, lerp(0.315, 0.312 * jw, 0.3), -0.437, 2.2 },
		{ mY, lerp(0.3, 0.3 * jw, 0.6) * (fem and 0.95 or 1.03), -0.449 - 0.004 * lipK, 2.35 },
		{ mY - 0.07, 0.285 * jw * (fem and 0.92 or 1.05), -0.438 - 0.005 * cp, 2.5 },
		{ cy + 0.03, lerp(0.24, 0.255 * jw, 0.7) * (fem and 0.88 or 1.04), -0.447 - 0.014 * cp, 2.8 },
		{ cy - 0.03, 0.17 * cwk * (fem and 0.9 or 1) + 0.04 * (jw - 1), -0.428 - 0.012 * cp, 3.2 },
		{ cy - 0.09, 0.1, -0.34, 3.2 },
	}
	-- the jaw's lower border: menton -> gonion, then up the ramus behind the angle
	local zM, yM = -0.378 - 0.012 * cp, cy - 0.055
	local zG, yG = 0.03, F.gonionY
	local z0 = 0.03
	local edge = lerp(0.045, 0.018, F.jawDef) -- jawline roundness
	-- the slice at a height (cached: band rays keep y constant along the ray)
	local lastY, ca, cf, cn = nil, 0, 0, 0
	return function(x, y, z)
		if y ~= lastY then
			lastY, ca, cf, cn = y, keyed(K, y, 2), keyed(K, y, 3), keyed(K, y, 4)
		end
		local a, front, n = ca, cf, cn
		local zf = z0 - front
		local ax = abs(x) / a + 1e-9
		local dz = z0 - z
		local d
		if dz > 0 then
			local az = dz / zf + 1e-9
			local px, pz = ax ^ n, az ^ n
			local r = (px + pz) ^ (1 / n)
			-- first-order distance: (r - 1) / |grad r|
			local k = r / (px + pz)
			local gx, gz = k * px / ax / a, k * pz / az / zf
			d = (r - 1) / max(sqrt(gx * gx + gz * gz), 1e-6)
		else
			-- the back half is a plain ellipse (inside the skull / neck anyway)
			local bz = -dz / 0.3
			d = (sqrt(ax * ax + bz * bz) - 1) * min(a, 0.3)
		end
		-- border cut: inside above the border line
		local t = clamp((z - zM) / (zG - zM), 0, 1)
		local yb = yM + (yG - yM) * (t ^ 0.85)
		if z > zG then
			yb = yG + (z - zG) * 3.5 -- the angle: the ramus' back edge rises steeply
		end
		local db = (yb - y) * 0.9
		-- smooth max (intersection) with the edge radius
		local h = clamp(0.5 - 0.5 * (db - d) / edge, 0, 1)
		return db + (d - db) * h + edge * h * (1 - h)
	end
end

local function baseField(F)
	local skull = Skull.Nominal(F.P)
	local lower = lowerFaceSlices(F)
	local zy = 0.33 + 0.012 * F.cheek -- zygomatic arch (centre line) half width
	return function(x, y, z)
		local d = skull(x, y, z)
		local ax = abs(x)
		-- the lower face: below the eyes (above, the skull's own face mass rules); faded in, never cut
		if y < F.eyeY + 0.03 then
			d = smin(d, lower(x, y, z) + 0.12 * smoothstep(F.eyeY - 0.09, F.eyeY + 0.03, y), 0.04)
		end
		-- zygomatic arches (the widest part of the face, in front of the ears): soft under the skin
		d = smin(d, sdCapsule(ax, y, z, 0.27, -0.055, -0.24, zy, -0.05, 0.02, 0.035, 0.025), 0.07)
		return d
	end
end

------------------------------------------------------------------------
-- Relief: the face's soft-tissue features as displacements along the ray (nominal studs, + = out)
------------------------------------------------------------------------
-- evaluated at the base surface point; each feature has a cheap bounding test first
local function reliefFn(F)
	local eyeY = F.eyeY
	local browY, ridge = F.browY, F.browRidge
	local fem = F.female
	local nt = F.nt
	local nasY, baseY, tipY = F.nasionY, F.noseBaseY, F.noseTipY
	local nW = F.noseW
	local dev = F.noseDev
	local brk = F.noseBreak
	local mY, mW = F.mouthY, F.mouthW
	local lips = F.lips
	local bow = F.lipBow
	local mt = F.mouthTilt
	local curve = F.mouthCurve or 0
	local cheek, cheekH = F.cheek, F.cheekH
	local cy, cw = F.chinY, F.chinW
	local cleft = F.chinCleft
	local fat, gaunt, jowl = F.faceFat, F.gaunt, F.jowl
	local cheekFull = F.cheekFull
	local jawDef, jw, gy = F.jawDef, F.jawW, F.gonionY
	local tipProj = 0.118 + nt.tip + 0.008 * F.bridge - 0.025 * brk
	local tipUp = F.noseTip * 0.012 - nt.droop
	local flare = F.nostrilFlare
	local femK = fem and 0.9 or 1
	local orbitD = 0.022 + 0.012 * F.eyeDepth + 0.006 * F.gaunt
	local hRoot = 0.006 + nt.root + 0.008 * F.bridge
	local hTip = tipProj
	local hump = nt.hump + 0.01 * brk
	local scoop = nt.scoop
	local bridgeW = nt.bridgeW
	local bulb = clamp(0.4 + nt.bulb, 0, 1.2)
	local tipW = (0.034 + 0.01 * nt.bulb + 0.006 * brk) * femK
	local alaX = nW * 0.72
	local alaR = nW * 0.42
	local alaH = (0.04 + 0.01 * flare + 0.008 * nt.ala) * femK
	return function(x, y, z)
		local D = 0
		local ax = abs(x)
		local front = -z -- how far forward (face points have front ~0.3 .. 0.6)
		if front < 0.05 then
			-- the back half of the head: nothing below the skull
			return 0
		end
		------------------------------------------------ brow ridge (supraorbital) + glabella
		do
			-- the ridge line: over the glabella, arching over each eye, dropping at the outer end
			local u = ax / 0.29
			local ry = browY - 0.006 + 0.008 * bump(((u - 0.55) / 0.5) ^ 2) - 0.035 * max(0, u - 0.6) ^ 2
			local dy = y - ry
			if dy > -0.06 and dy < 0.1 and u < 1.2 then
				local h = (0.012 + 0.024 * ridge) * (fem and 0.55 or 1)
				-- soft into the forehead above, a rounded edge over the orbit below
				local sy = dy > 0 and dy / 0.06 or -dy / 0.024
				D += h * bump(sy * sy + (u / 1.05) ^ 6)
			end
		end
		------------------------------------------------ orbits: the recess the eyes and lids sit in
		do
			for side = -1, 1, 2 do
				local ex, ey = F.eye[side].x, F.eye[side].y
				local dx2 = (x - ex) * side -- + = lateral
				local dy2 = y - ey - 0.008
				local rx = dx2 < 0 and 0.085 or 0.1
				local ry2 = dy2 > 0 and 0.078 or 0.06
				local q = (dx2 / rx) ^ 2 + (dy2 / ry2) ^ 2
				if q < 1 then
					D -= orbitD * bump(q)
				end
			end
		end
		------------------------------------------------ nasion: the dip between the brow and the bridge
		do
			local q = (x / 0.075) ^ 2 + ((y - nasY - 0.006) / 0.034) ^ 2
			if q < 1 then
				D -= 0.016 * bump(q)
			end
		end
		------------------------------------------------ nose
		do
			local tNorm = (nasY - y) / (nasY - tipY)
			if tNorm > -0.25 and y > baseY - 0.03 then
				local nx = x - dev * clamp(tNorm, 0, 1)
				local anx = abs(nx)
				if anx < nW + 0.05 then
					local t = clamp(tNorm, 0, 1)
					-- dorsum: height over the face and half width along the nose
					local H = hRoot + (hTip - hRoot) * (t ^ 1.15)
					H += hump * bump(((t - 0.42) / 0.28) ^ 2) - scoop * bump(((t - 0.62) / 0.3) ^ 2)
					local W = (0.024 + 0.012 * t + 0.008 * bridgeW + 0.004 * brk) * femK
					-- below the tip the dorsum gives way to the columella, gone at the subnasale
					if tNorm > 1 then
						local u = clamp((y - baseY) / (tipY - baseY), 0, 1) -- 1 at the tip .. 0 at the base
						H = hTip * smoothstep(0.0, 1.0, u) ^ 0.7
						W = lerp(0.014, W, u)
					end
					-- cross section: flat top, steep sides, a concave foot into the cheeks
					local sx = anx / W
					local g = 1 / (1 + sx ^ 4)
					g = max(0, (g - 0.04) / 0.96)
					if tNorm < 0 then
						g *= 1 - smoothstep(0, 0.25, -tNorm)
					end
					D += H * g
					-- tip lobule: a rounded ball (two soft domes on refined tips)
					local tyc = tipY + tipUp - 0.004
					local trx, try = tipW, 0.032 + 0.006 * bulb
					local tq = (anx / trx) ^ 2 + ((y - tyc) / try) ^ 2
					if tq < 1 then
						D += (0.016 + 0.01 * bulb) * bump(tq)
					end
					-- alar lobes: rounded wings either side of the tip, joined to it (one lower-nose mass);
					-- the alar groove only runs over the top and back of each wing
					local ay = y - (baseY + 0.022)
					local axx = anx - alaX
					local aq = (ay / 0.03) ^ 2 + (axx / alaR) ^ 2
					if aq < 1 then
						D += alaH * bump(aq)
					end
					-- the soft triangle between wing and tip keeps them one shape
					local sq = ((anx - alaX * 0.5) / (alaX * 0.6)) ^ 2 + ((y - (baseY + 0.03)) / 0.03) ^ 2
					if sq < 1 then
						D += alaH * 0.55 * bump(sq)
					end
					-- nostrils: the openings under the tip between the columella and the alar rims
					local ny = y - (baseY + 0.003)
					local nq = (ny / 0.009) ^ 2 + ((anx - alaX * 0.55) / (alaX * 0.36)) ^ 2
					if nq < 1 then
						D -= (0.006 + 0.004 * flare) * bump(nq)
					end
				end
			end
		end
		------------------------------------------------ cheekbones (malar) and cheeks
		do
			local cyy = eyeY - 0.085 + 0.02 * cheekH
			local cxx = 0.255 + 0.01 * cheek
			local q = ((ax - cxx) / 0.11) ^ 2 + ((y - cyy) / 0.075) ^ 2
			if q < 1 then
				D += (0.022 + 0.014 * cheek + 0.01 * gaunt) * bump(q)
			end
			-- buccal hollow under the cheekbone (lean / gaunt) or full cheeks (fat)
			local hy = y - (mY + 0.07)
			local hq = ((ax - 0.235) / 0.085) ^ 2 + (hy / 0.07) ^ 2
			if hq < 1 then
				local fill = (0.02 * fat + 0.012 * max(cheekFull, 0) + 0.006 * F.round) - (0.016 * gaunt + 0.01 * max(-cheekFull, 0)) - 0.004
				D += fill * bump(hq)
			end
		end
		------------------------------------------------ mouth: lips, philtrum, corners
		do
			local my = y - (mY + mt * x + curve * x * x)
			if my > -0.1 and my < (baseY - mY) + 0.01 and ax < mW + 0.07 then
				local xr = ax / mW -- 0 centre, 1 corner
				-- vermilion heights (the upper lip with its cupid's bow, the fuller lower lip) and protrusions
				local Hu, Hl, pu, pl, taper = F.lipShape(x)
				if my >= 0 then
					local h = my / max(Hu, 0.003)
					if h <= 1 then
						-- vermilion: curls in at the stomion, bulges, meets the border in front of the skin
						local prof = sqrt(max(0, 1 - ((h - 0.5) / 0.62) ^ 2))
						D += pu * (0.55 + 0.45 * prof) * (1 - 0.3 * h)
						-- the tubercle: a soft bead in the middle of the upper lip
						D += 0.004 * bow * bump((x / 0.035) ^ 2 + ((h - 0.35) / 0.5) ^ 2)
					else
						-- skin above the border: the philtrum slopes back up to the subnasale
						local up = (my - Hu) / max(0.01, (baseY - mY) - Hu)
						local wide = 1 - smoothstep(0.5, 1.6, xr) -- the upper lip's skin fades out past the corners
						local skin = (0.028 + 0.008 * lips) * 0.62 * wide
						-- start from where the vermilion ended (no step at the border), then slope to the subnasale
						local edge = pu * 0.571
						D += lerp(edge, skin, smoothstep(0, 0.35, up)) * (1 - smoothstep(0, 1, up))
						-- white roll along the vermilion border
						D += 0.003 * bump(((my - Hu) / 0.006) ^ 2) * taper
					end
				else
					local h = -my / max(Hl, 0.003)
					if h <= 1 then
						local prof = sqrt(max(0, 1 - ((h - 0.45) / 0.6) ^ 2))
						D += pl * (0.45 + 0.55 * prof)
					else
						-- below the lower lip: down into the mentolabial sulcus
						local dn = (-my - Hl) / 0.03
						D += (0.032 + 0.009 * lips) * (1 - smoothstep(0.5, 1.5, xr)) * 0.45 * (1 - smoothstep(0, 1, dn))
					end
				end
				-- the oral fissure: a narrow deep groove into the mouth (the lips touch at the front)
				local gq = (my / 0.0034) ^ 2
				if gq < 1 then
					D -= (0.055 + 0.015 * lips) * bump(gq) * (1 - smoothstep(0.8, 0.98, xr))
				end
				-- philtrum: a shallow groove between two columns
				if my > 0 then
					local hp = my / max(0.02, baseY - mY)
					local col = 0.015 + 0.006 * hp
					local g = bump((x / col) ^ 2)
					local c = bump(((ax - col) / 0.008) ^ 2)
					local fade = smoothstep(0.25, 0.5, hp) * (1 - smoothstep(0.85, 1.0, hp)) + smoothstep(0.05, 0.3, hp) * (1 - smoothstep(0.3, 0.5, hp))
					D += (-0.0035 * g + 0.002 * c) * fade
				end
				-- mouth corners: a small pocket; the modiolus bulge beside it
				local cq = ((ax - mW) / 0.014) ^ 2 + (my / 0.011) ^ 2
				if cq < 1 then
					D -= 0.008 * bump(cq)
				end
				local mq = ((ax - mW - 0.022) / 0.026) ^ 2 + ((my + 0.004) / 0.032) ^ 2
				if mq < 1 then
					D += 0.005 * bump(mq)
				end
			end
		end
		------------------------------------------------ nasolabial folds
		do
			-- from beside the ala down / out to beside the mouth corner
			local x0, y0 = nW + 0.012, baseY + 0.02
			local x1, y1 = mW + 0.03, mY - 0.03
			local vx, vy = x1 - x0, y1 - y0
			local l2 = vx * vx + vy * vy
			local u = clamp(((ax - x0) * vx + (y - y0) * vy) / l2, 0, 1)
			local dx, dy = ax - x0 - vx * u, y - y0 - vy * u
			local dd = sqrt(dx * dx + dy * dy)
			if dd < 0.05 then
				-- signed: + on the cheek side (lateral / above)
				local sgn = (dx * vy - dy * vx) < 0 and 1 or -1
				local depth = (0.006 + 0.01 * F.wrinkles + 0.007 * fat) * (1 - 0.4 * u) * smoothstep(0, 0.15, u)
				if sgn > 0 then
					D += depth * 1.2 * bump(((dd - 0.021) / 0.019) ^ 2) -- zero on the fold line itself
				end
				D -= depth * 0.8 * bump((dd / 0.013) ^ 2)
			end
		end
		------------------------------------------------ chin and mentolabial sulcus
		do
			local q = (x / (cw * 0.95)) ^ 2 + ((y - cy - 0.015) / 0.045) ^ 2
			if q < 1 then
				D += (0.014 + 0.008 * F.chin + 0.008 * F.chinProject) * bump(q)
			end
			local sy = y - (mY - 0.075)
			local sq = (sy / 0.016) ^ 2 + (x / (mW * 0.9)) ^ 2
			if sq < 1 then
				D -= 0.01 * bump(sq)
			end
			if cleft > 0.05 then
				local clq = (x / 0.007) ^ 2 + ((y - cy - 0.01) / 0.035) ^ 2
				if clq < 1 then
					D -= 0.007 * cleft * bump(clq)
				end
			end
		end
		------------------------------------------------ jaw line definition, jowls
		do
			if y < gy + 0.06 and y > cy - 0.06 then
				local x0, y0 = jw, gy
				local x1, y1 = cw * 0.6, cy - 0.01
				local vx, vy = x1 - x0, y1 - y0
				local l2 = vx * vx + vy * vy
				local u = clamp(((ax - x0) * vx + (y - y0) * vy) / l2, 0, 1)
				local dx, dy = ax - x0 - vx * u, y - y0 - vy * u
				local dd = sqrt(dx * dx + dy * dy)
				if dd < 0.05 then
					D += (0.004 + 0.01 * jawDef) * bump((dd / 0.035) ^ 2) * (1 - jowl * 0.6)
				end
			end
			if jowl > 0.02 then
				local jq = ((ax - (cw + 0.12)) / 0.07) ^ 2 + ((y - (cy + 0.07)) / 0.06) ^ 2
				if jq < 1 then
					D += 0.02 * jowl * bump(jq)
				end
			end
		end
		------------------------------------------------ forehead
		do
			if y > browY + 0.02 and y < 0.45 then
				local q = ((ax - 0.11) / 0.1) ^ 2 + ((y - 0.24) / 0.09) ^ 2
				if q < 1 then
					D += 0.004 * bump(q)
				end
			end
		end
		return D
	end
end

------------------------------------------------------------------------
-- Rays: a smooth family through the head (rows: crown cap, horizontal face band, chin / neck cap)
------------------------------------------------------------------------
local ZA = 0.04 -- axis depth
local GA, GB = 0.2, 0.075 -- guide ellipse: rays leave its normals, so the face front is near-orthographic

-- row = { kind = "top" | "band" | "bot", y (band height) | a (elevation 0..pi/2 for caps) }
local function ray(row, th, yT, yB)
	local c, s = cos(th), sin(th)
	local gx, gz = GA * c, -GB * s
	local nx, nz = GB * c, -GA * s
	local nl = sqrt(nx * nx + nz * nz)
	nx, nz = nx / nl, nz / nl
	if row.kind == "band" then
		return gx, row.y, ZA + gz, nx, 0, nz
	end
	local a = row.a
	local shrink = 1 - sin(a) -- the origin moves to the axis as the ray turns up / down
	local ca, sa = cos(a), sin(a)
	if row.kind == "top" then
		return gx * shrink, yT, ZA + gz * shrink, nx * ca, sa, nz * ca
	end
	return gx * shrink, yB, ZA + gz * shrink, nx * ca, -sa, nz * ca
end

-- outermost crossing of the field along the ray (sphere tracing inward from outside, then secant)
local function hit(field, ox, oy, oz, dx, dy, dz, tGuess, margin)
	local t = (tGuess or 0.5) + (margin or 0.06)
	local f = field(ox + dx * t, oy + dy * t, oz + dz * t)
	local n = 0
	while f < 0 and n < 30 do
		t += 0.08
		f = field(ox + dx * t, oy + dy * t, oz + dz * t)
		n += 1
	end
	local tPrev, fPrev = t, f
	for _ = 1, 40 do
		if f < 0.0004 then
			break
		end
		tPrev, fPrev = t, f
		t -= max(f * 0.9, 0.0003)
		f = field(ox + dx * t, oy + dy * t, oz + dz * t)
	end
	if f < 0 and fPrev > 0 then
		for _ = 1, 3 do
			local tm = t + (tPrev - t) * (-f) / (fPrev - f)
			local fm = field(ox + dx * tm, oy + dy * tm, oz + dz * tm)
			if fm > 0 then
				tPrev, fPrev = tm, fm
			else
				t, f = tm, fm
			end
		end
		t = t + (tPrev - t) * (-f) / (fPrev - f)
	else
		-- stopped just outside: finish with a Newton step along the ray (precise rows = smooth shading)
		for _ = 1, 1 do
			local e = 0.002
			local f1 = field(ox + dx * (t - e), oy + dy * (t - e), oz + dz * (t - e))
			local g = (f - f1) / e
			if g > 1e-4 then
				t -= f / g
				f = field(ox + dx * t, oy + dy * t, oz + dz * t)
			end
		end
	end
	return max(t, 0.02)
end

-- far intersection of a ray with a sphere (nil when missed)
local function raySphere(ox, oy, oz, dx, dy, dz, cx, cy, cz, r)
	local px, py, pz = ox - cx, oy - cy, oz - cz
	local b = px * dx + py * dy + pz * dz
	local c = px * px + py * py + pz * pz - r * r
	local disc = b * b - c
	if disc < 0 then
		return nil, -b
	end
	return -b + sqrt(disc), -b
end

------------------------------------------------------------------------
-- Eye frames: lateral L (toward the outer corner, tilted up by the canthal tilt), up U, forward -Z
------------------------------------------------------------------------
local function eyeFrame(F, side)
	local e = F.eye[side]
	local t = F.tilt
	return { cx = e.x, cy = e.y, cz = e.z, Lx = side * cos(t), Ly = sin(t), Ux = -side * sin(t), Uy = cos(t), side = side }
end

-- azimuth (+ toward the outer corner) and elevation of a point seen from the eyeball centre
local function eyeAngles(E, x, y, z)
	local vx, vy, vz = x - E.cx, y - E.cy, z - E.cz
	local l = vx * E.Lx + vy * E.Ly
	local u = vx * E.Ux + vy * E.Uy
	local f = -vz
	return math.atan2(l, f), math.atan2(u, sqrt(l * l + f * f))
end

local function eyePoint(E, a, b, r)
	local cb = cos(b)
	local l, u, f = r * cb * sin(a), r * sin(b), r * cb * cos(a)
	return E.cx + l * E.Lx + u * E.Ux, E.cy + l * E.Ly + u * E.Uy, E.cz - f
end

-- the lid margins (elevations) at azimuth a, and how far a is between the canthi (g: 0 at a corner)
local function marginAt(F, a)
	local c = (F.aLat + F.aMed) * 0.5
	local h = (F.aLat - F.aMed) * 0.5
	local x = clamp((a - c) / h, -1, 1)
	local g = max(0, 1 - x * x)
	local up = F.bUp * g ^ F.pUp * (1 - 0.14 * x)
	local dn = F.bDn * g ^ F.pDn * (1 + 0.1 * x)
	return up, -dn, g
end

-- the socket rim: where the head surface dives behind the eyeball. It runs a little past both canthi (the
-- lower lid wraps the corners there), so every edge of the opening is lid geometry, never the head's grid
local EXT_MED, EXT_LAT = math.rad(10), math.rad(15)
local function rimAt(F, a)
	local up, dn = marginAt(F, a)
	local a0, a1 = F.aMed - EXT_MED, F.aLat + EXT_LAT
	local x = clamp((a - (a0 + a1) * 0.5) / ((a1 - a0) * 0.5), -1, 1)
	local sg = sqrt(max(0, 1 - x * x))
	return up + F.gUp * sg, dn - F.gDn * sg, a0, a1
end

-- the lower lid's top edge: its margin inside the opening, beyond the canthi it rises over the rim (the
-- corner skin) so it covers the head's dive there
local function lowerEdge(F, a)
	local up, dn = marginAt(F, a)
	if a >= F.aMed and a <= F.aLat then
		return dn
	end
	local rUp = rimAt(F, a)
	local beyond = a > F.aLat and (a - F.aLat) or (F.aMed - a)
	return (rUp + math.rad(3.5)) * smoothstep(0, math.rad(3), beyond)
end

------------------------------------------------------------------------
-- Rows and columns (density follows the features)
------------------------------------------------------------------------
Gen.DENSITY = 1 -- debug: > 1 renders the true shape (sampling vs shape problems)
-- grid density per level (q = 1: ~3000 triangles); the budget may lower it (Generate)
Gen.GRID_Q = { full = 1, medium = 0.66, low = 0.36 }
local function rowList(F, q)
	q *= Gen.DENSITY
	local rows = {}
	local nTop = max(3, floor(7 * q + 0.5))
	for i = nTop - 1, 1, -1 do
		rows[#rows + 1] = { kind = "top", a = (pi / 2) * (i / nTop) ^ 0.9 }
	end
	local yT, yB = 0.22, -0.4
	local eY, bY = F.eyeY, F.browY
	local mY = F.mouthY
	local keys = {
		{ yT, 0.04 }, { bY + 0.03, 0.02 }, { eY + 0.05, 0.012 }, { eY - 0.045, 0.012 },
		{ F.noseTipY + 0.035, 0.02 }, { F.noseTipY + 0.01, 0.007 }, { F.noseBaseY - 0.002, 0.005 },
		{ mY + 0.036, 0.012 }, { mY + 0.008, 0.007 }, { mY + 0.0035, 0.0017 }, { mY - 0.0035, 0.0017 }, { mY - 0.01, 0.008 }, { mY - 0.05, 0.011 },
		{ yB, 0.02 },
	}
	local function spacing(y)
		for i = 1, #keys - 1 do
			local a, b = keys[i], keys[i + 1]
			if y <= a[1] and y >= b[1] then
				local t = (a[1] - y) / max(1e-6, a[1] - b[1])
				return lerp(a[2], b[2], t)
			end
		end
		return 0.02
	end
	local y = yT
	local band = {}
	while y > yB + 1e-6 do
		band[#band + 1] = y
		y -= spacing(y) / q
	end
	band[#band + 1] = yB
	-- the mouth line must be a row (the lips meet there)
	local best, bi = 1, nil
	for i, yy in ipairs(band) do
		if abs(yy - F.mouthY) < best then
			best, bi = abs(yy - F.mouthY), i
		end
	end
	if bi then
		band[bi] = F.mouthY
	end
	for _, yy in ipairs(band) do
		rows[#rows + 1] = { kind = "band", y = yy }
	end
	-- chin / jaw / under-jaw rows, then a coarse neck stub (hidden in the Body's neck)
	local nBot = max(3, floor(8 * q + 0.5))
	for i = 1, nBot do
		rows[#rows + 1] = { kind = "bot", a = math.rad(58) * (i / nBot) ^ 1.05 }
	end
	for _, aDeg in ipairs({ 70, 82 }) do
		rows[#rows + 1] = { kind = "bot", a = math.rad(aDeg) }
	end
	return rows, yT, yB
end

local function columnsFor(F, row, q, yApprox, N)
	q *= Gen.DENSITY
	-- feature weights vary smoothly from row to row (an abrupt change skews the stitched triangles)
	local eyeW = exp(-((yApprox - F.eyeY) / 0.06) ^ 2)
	local mouthW = exp(-((yApprox - F.mouthY) / 0.05) ^ 2)
	local mid = (F.nasionY + F.noseBaseY) * 0.5
	local noseW = exp(-((yApprox - mid) / ((F.nasionY - F.noseBaseY) * 0.6)) ^ 4)
	local faceW = 1
	if row.kind == "top" then
		faceW = cos(row.a) ^ 1.5
	elseif row.kind == "bot" then
		faceW = cos(row.a) ^ 1.2
	end
	local capK = 1
	if row.kind == "top" then
		capK = cos(row.a) ^ 0.7
	elseif row.kind == "bot" then
		capK = 0.5 + 0.5 * cos(row.a)
	end
	local function rho(th)
		local df = abs(((th - pi / 2 + pi) % TAU) - pi)
		local r = 0.16 + 0.9 * exp(-(df / 0.9) ^ 2) + 0.75 * faceW * exp(-(df / 0.5) ^ 2)
		r += 0.55 * eyeW * exp(-((df - 0.42) / 0.18) ^ 2)
		r += mouthW * (0.6 * exp(-((df - 0.3) / 0.12) ^ 2) + 0.9 * exp(-(df / 0.16) ^ 2))
		r += 1.5 * noseW * exp(-(df / 0.12) ^ 2)
		return r
	end
	N = N or 180
	local cdf = table.create(N + 1, 0)
	local acc = 0
	for i = 1, N do
		acc += rho(1.5 * pi + TAU * (i - 0.5) / N)
		cdf[i + 1] = acc
	end
	local total = acc
	local n = max(8, floor(lerp(36, 46, faceW) * q * capK * (total / N) + 0.5))
	local cols = table.create(n + 1)
	local k = 1
	for j = 0, n do
		local target = total * j / n
		while k < N and cdf[k + 1] < target do
			k += 1
		end
		local c0, c1 = cdf[k], cdf[k + 1]
		local frac = c1 > c0 and (target - c0) / (c1 - c0) or 0
		cols[j + 1] = 1.5 * pi + TAU * ((k - 1) + frac) / N
	end
	cols[1], cols[n + 1] = 1.5 * pi, 3.5 * pi
	return cols
end

local HEAD_V = 0.9 -- the head grid uses v in [0, 0.9] of the texture; the ears sit below it

-- texture u: the face (front) gets most of the atlas width. A fixed monotonic warp of the column angle, the
-- same for every row (so the stitching and the grid normals, which compare u across rows, stay valid)
local UW_N = 720
local UW = table.create(UW_N + 1, 0)
do
	local acc = 0
	for i = 1, UW_N do
		local th = 1.5 * pi + TAU * (i - 0.5) / UW_N
		local df = abs(((th - pi / 2 + pi) % TAU) - pi)
		acc += 0.12 + exp(-(df / 0.8) ^ 2)
		UW[i + 1] = acc
	end
	for i = 1, UW_N + 1 do
		UW[i] /= acc
	end
end
local function uOf(th)
	local fr = (th - 1.5 * pi) / TAU * UW_N
	if fr <= 0 then
		return 0
	elseif fr >= UW_N then
		return 1
	end
	local i = floor(fr)
	return UW[i + 1] + (UW[i + 2] - UW[i + 1]) * (fr - i)
end

------------------------------------------------------------------------
-- Head surface mesh
------------------------------------------------------------------------
local function rowApproxY(row, yT, yB)
	if row.kind == "band" then
		return row.y
	elseif row.kind == "top" then
		return yT + 0.4 * sin(row.a)
	end
	return yB - 0.3 * sin(row.a)
end

-- triangles of the head grid at density q (a coarse column CDF: an estimate within a few %)
local function gridTris(F, q)
	local rows, yT, yB = rowList(F, q)
	local total, prev = 0, 1
	for _, row in ipairs(rows) do
		local n = #columnsFor(F, row, q, rowApproxY(row, yT, yB), 48)
		total += (prev - 1) + (n - 1)
		prev = n
	end
	return total + prev - 1
end

-- sockets: false = no dive behind the eyes (low level: no eyeball pieces, the eyes are painted)
local function headSurface(F, q, sockets)
	local m = MeshKit.New("Head")
	local field = F.field
	local relief = F.relief
	local rows, yT, yB = rowList(F, q)
	local eR = F.eyeR
	local frames = { [-1] = eyeFrame(F, -1), [1] = eyeFrame(F, 1) }
	-- the skin just outside the rim: barely over the lower lid, a fold over the upper lid (the crease)
	local coverDn = eR + F.lowOut + 0.0012
	local coverUp = eR + F.lidOut + 0.0045
	-- how steeply the bowl rises from the rim: deep-set / older / lean eyes sit deeper
	local bowlK = 1.2 + 0.6 * F.eyeDepth + 0.3 * clamp((F.age - 35) / 25, 0, 1) + 0.25 * F.gaunt
	local rowStart, rowCount = {}, {}
	local prevTh, prevT = nil, nil
	do
		local t = hit(field, 0, yT, ZA, 0, 1, 0, 0.38)
		local i = MeshKit.Vertex(m, 0, yT + t, ZA, 0.5, 0)
		rowStart[0], rowCount[0] = i, 1
	end
	for r, row in ipairs(rows) do
		local yApprox
		if row.kind == "band" then
			yApprox = row.y
		elseif row.kind == "top" then
			yApprox = yT + 0.4 * sin(row.a)
		else
			yApprox = yB - 0.3 * sin(row.a)
		end
		local cols = columnsFor(F, row, q, yApprox)
		rowStart[r], rowCount[r] = m.nv + 1, #cols
		local tPrev = 0.5
		local v = 0 -- assigned by arc length once every row exists (assignV)
		local curT = table.create(#cols, 0)
		local k = 1
		local nPrev = prevTh and #prevTh or 0
		for ci, th in ipairs(cols) do
			local ox, oy, oz, dx, dy, dz = ray(row, th, yT, yB)
			-- the guess: the previous row's distance at this angle (rows are close), else the previous column's
			local guess, margin = tPrev, 0.06
			if nPrev > 1 then
				while k < nPrev - 1 and prevTh[k + 1] < th do
					k += 1
				end
				local a0, a1 = prevTh[k], prevTh[k + 1]
				local f = a1 > a0 and clamp((th - a0) / (a1 - a0), 0, 1) or 0
				guess, margin = lerp(prevT[k], prevT[k + 1], f), 0.02
			end
			local t = hit(field, ox, oy, oz, dx, dy, dz, guess, margin)
			tPrev = t
			curT[ci] = t
			local bx, by, bz = ox + dx * t, oy + dy * t, oz + dz * t
			local tt = t + relief(bx, by, bz)
			-- eye sockets: hidden behind the eyeball inside the rim, over the lids just outside it
			for side = -1, 1, 2 do
				if not sockets then
					break
				end
				local E = frames[side]
				local vx, vy, vz = bx - E.cx, by - E.cy, bz - E.cz
				local r2 = vx * vx + vy * vy + vz * vz
				if vz < 0.03 and r2 < 0.0169 then
					-- only skin near the eyeball belongs to the socket (the nose side is far in front at the
					-- same angle)
					local wR = 1 - smoothstep(0.1, 0.128, sqrt(r2))
					local a, b = eyeAngles(E, bx, by, bz)
					local rUp, rDn, a0, a1 = rimAt(F, a)
					local ca = cos(b)
					local d = max(b - rUp, rDn - b, (a0 - a) * ca, (a - a1) * ca) * 0.07
					if d < 0.04 then
						-- near the rim the skin is pulled in toward the lids (the crease, the tear trough, the
						-- inner corner), fading out within ~2.5 mm (never a cliff at the edge of the effect)
						local lidR = lerp(coverDn, coverUp, smoothstep(-0.05, 0.12, b))
						local dOut = max(0, d)
						local rB = lidR + bowlK * dOut
						local tB = raySphere(ox, oy, oz, dx, dy, dz, E.cx, E.cy, E.cz, rB)
						local wB = (1 - smoothstep(0.014, 0.03, dOut)) * wR
						if tB and tB < tt and wB > 0 then
							local k = 0.01
							local hh = clamp(0.5 + 0.5 * (tt - tB) / k, 0, 1)
							tt += ((tB - tt) * hh - k * hh * (1 - hh)) * wB
						end
						-- within the lids' reach the skin never sinks behind them (the eyeball's sides)
						local inReach = a > a0 - 0.1 and a < a1 + 0.1 and b > -1.0 and b < 1.4
						if inReach and d < 0.02 then
							local tC = raySphere(ox, oy, oz, dx, dy, dz, E.cx, E.cy, E.cz, lidR)
							if tC then
								local w = (1 - smoothstep(0.008, 0.02, d)) * wR
								local k = 0.006
								local hh = clamp(0.5 + 0.5 * (tC - tt) / k, 0, 1)
								tt += ((tC - tt) * hh + k * hh * (1 - hh)) * w
							end
						end
						-- a gradual dive: the crease is then where two smooth surfaces meet (pixel exact), not a
						-- cliff sampled by the grid
						local band = min(0.011, 0.45 * (b > 0 and F.gUp or F.gDn) * 0.07)
						local wh = (1 - smoothstep(-band, band, d)) * wR
						if wh > 0 then
							local tH, tc = raySphere(ox, oy, oz, dx, dy, dz, E.cx, E.cy, E.cz, eR - 0.006)
							tt = lerp(tt, tH or tc, wh)
						end
					end
				end
			end
			MeshKit.Vertex(m, ox + dx * tt, oy + dy * tt, oz + dz * tt, uOf(th), v)
		end
		-- the band / cap rays change family at the cap borders: guesses only within a family
		local nextRow = rows[r + 1]
		if nextRow and nextRow.kind == row.kind then
			prevTh, prevT = cols, curT
		else
			prevTh, prevT = nil, nil
		end
		-- each column is a ray cast through the field (several SDF evaluations)
		MeshKit.Step(#cols * 4)
	end
	do
		local t = hit(field, 0, yB, ZA, 0, -1, 0, 0.5)
		local i = MeshKit.Vertex(m, 0, yB - t, ZA, 0.5, HEAD_V)
		rowStart[#rows + 1], rowCount[#rows + 1] = i, 1
	end
	local function stitch(a0, na, b0, nb)
		if na == 1 then
			for j = 0, nb - 2 do
				MeshKit.Tri(m, a0, b0 + j, b0 + j + 1)
			end
			return
		elseif nb == 1 then
			for i = 0, na - 2 do
				MeshKit.Tri(m, a0 + i, b0, a0 + i + 1)
			end
			return
		end
		local i, j = 0, 0
		local U = m.U
		while i < na - 1 or j < nb - 1 do
			local advA
			if i >= na - 1 then
				advA = false
			elseif j >= nb - 1 then
				advA = true
			else
				advA = U[(a0 + i + 1) * 2 - 1] <= U[(b0 + j + 1) * 2 - 1]
			end
			if advA then
				MeshKit.Tri(m, a0 + i, b0 + j, a0 + i + 1)
				i += 1
			else
				MeshKit.Tri(m, a0 + i, b0 + j, b0 + j + 1)
				j += 1
			end
		end
	end
	for r = 0, #rows do
		stitch(rowStart[r], rowCount[r], rowStart[r + 1], rowCount[r + 1])
	end
	m.gridRows = { start = rowStart, count = rowCount, n = #rows + 1, rows = rows }
	return m
end

-- position on grid row r at texture u (linear between the row's columns)
local function rowPointAt(m, r, u)
	local G = m.gridRows
	local P, U = m.P, m.U
	local s0, n = G.start[r], G.count[r]
	if n == 1 then
		return P[s0 * 3 - 2], P[s0 * 3 - 1], P[s0 * 3]
	end
	local lo, hi = 0, n - 1
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if U[(s0 + mid) * 2 - 1] <= u then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = s0 + lo, s0 + hi
	local ua, ub = U[a * 2 - 1], U[b * 2 - 1]
	local t = ub > ua and clamp((u - ua) / (ub - ua), 0, 1) or 0
	return lerp(P[a * 3 - 2], P[b * 3 - 2], t), lerp(P[a * 3 - 1], P[b * 3 - 1], t), lerp(P[a * 3], P[b * 3], t)
end

-- texture v by surface distance down the face (the front and both cheeks), weighted by region (face 1,
-- forehead / under the chin less, scalp and neck least): texels on the face come out square
local function assignV(m, F)
	local G = m.gridRows
	local rows = G.rows
	local U = m.U
	local us = { 0.5, uOf(2.5 * pi - 0.55), uOf(2.5 * pi + 0.55) }
	local n = G.n
	local prev = {}
	for k, u in ipairs(us) do
		prev[k] = { rowPointAt(m, 0, u) }
	end
	local S, W = { [0] = 0 }, { [0] = 0 }
	local bY, cY = F.browY, F.chinY
	for r = 1, n do
		local ds, yF = 0, 0
		for k, u in ipairs(us) do
			local x, y, z = rowPointAt(m, r, u)
			local p = prev[k]
			ds += sqrt((x - p[1]) ^ 2 + (y - p[2]) ^ 2 + (z - p[3]) ^ 2)
			if k == 1 then
				yF = (y + p[2]) * 0.5
			end
			prev[k] = { x, y, z }
		end
		ds /= #us
		local rho
		local row = rows[r]
		if row and row.kind == "bot" and row.a > math.rad(45) then
			rho = lerp(0.75, 0.18, smoothstep(math.rad(45), math.rad(65), row.a))
		elseif r == n then
			rho = 0.18
		elseif yF > bY + 0.1 then
			rho = lerp(1.0, 0.3, smoothstep(bY + 0.1, bY + 0.24, yF))
		elseif yF < cY - 0.01 then
			rho = 0.8
		else
			rho = 1.0
		end
		S[r] = S[r - 1] + ds
		W[r] = W[r - 1] + ds * rho
		MeshKit.Step(8)
	end
	for r = 0, n do
		local v = HEAD_V * W[r] / W[n]
		local s0 = G.start[r]
		for j = 0, G.count[r] - 1 do
			U[(s0 + j) * 2] = v
		end
	end
	-- for the texture's noise: arc length at each row and the face's texels per stud (per unit of v)
	G.arcS, G.arcW, G.arcTotal = S, W, W[n]
end

-- noise lookup maps for a w x h texture: per texel column / row, an index that advances ~1 per texel on
-- the face and proportionally more where the atlas is sparser (scalp, back, neck), so grain is never
-- stretched into streaks
local function noiseMaps(m, w, h)
	local G = m.gridRows
	-- columns: u -> column angle (inverse of the warp), scaled so the face front advances 1 per texel
	local col = table.create(w, 0)
	local dUfront = (uOf(2.5 * pi + 0.01) - uOf(2.5 * pi - 0.01)) / 0.02
	local k = 1
	for px = 0, w - 1 do
		local u = (px + 0.5) / w
		while k < UW_N and UW[k + 1] < u do
			k += 1
		end
		local u0, u1 = UW[k], UW[k + 1]
		local th = ((k - 1) + (u1 > u0 and (u - u0) / (u1 - u0) or 0)) / UW_N * TAU
		col[px + 1] = floor(th * w * dUfront)
	end
	-- rows: v -> arc length (piecewise linear between grid rows), scaled the same way
	local row = table.create(h, 0)
	local S, W, total = G.arcS, G.arcW, G.arcTotal
	local kv = h * HEAD_V / total -- texels per stud of weighted arc (= per stud on the face)
	local r = 1
	for py = 0, h - 1 do
		local v = (py + 0.5) / h
		local wv = v / HEAD_V * total
		if wv >= total then
			row[py + 1] = floor(S[G.n] * kv + (wv - total) * kv)
		else
			while r < G.n and W[r] < wv do
				r += 1
			end
			local w0, w1 = W[r - 1], W[r]
			local t = w1 > w0 and (wv - w0) / (w1 - w0) or 0
			row[py + 1] = floor(lerp(S[r - 1], S[r], t) * kv)
		end
	end
	return col, row
end

-- normals from the grid's own parameterisation: along the row (prev / next column) and across rows (the
-- rows above / below interpolated at the same u). Smooth where the stitching makes skewed triangles.
local function gridNormals(m)
	local G = m.gridRows
	local P, U, N = m.P, m.U, m.N
	local function rowAt(r, u)
		local s0, n = G.start[r], G.count[r]
		if n == 1 then
			return P[s0 * 3 - 2], P[s0 * 3 - 1], P[s0 * 3]
		end
		-- binary search on u
		local lo, hi = 0, n - 1
		while hi - lo > 1 do
			local mid = (lo + hi) // 2
			if U[(s0 + mid) * 2 - 1] <= u then
				lo = mid
			else
				hi = mid
			end
		end
		local a, b = s0 + lo, s0 + hi
		local ua, ub = U[a * 2 - 1], U[b * 2 - 1]
		local t = ub > ua and clamp((u - ua) / (ub - ua), 0, 1) or 0
		-- Catmull-Rom through the neighbours (a chord would sag inside the curved row: shading stripes)
		local a0 = lo > 0 and a - 1 or (s0 + n - 2)
		local b1 = hi < n - 1 and b + 1 or (s0 + 1)
		local t2, t3 = t * t, t * t * t
		local c0 = -0.5 * t3 + t2 - 0.5 * t
		local c1 = 1.5 * t3 - 2.5 * t2 + 1
		local c2 = -1.5 * t3 + 2 * t2 + 0.5 * t
		local c3 = 0.5 * t3 - 0.5 * t2
		return P[a0 * 3 - 2] * c0 + P[a * 3 - 2] * c1 + P[b * 3 - 2] * c2 + P[b1 * 3 - 2] * c3,
			P[a0 * 3 - 1] * c0 + P[a * 3 - 1] * c1 + P[b * 3 - 1] * c2 + P[b1 * 3 - 1] * c3,
			P[a0 * 3] * c0 + P[a * 3] * c1 + P[b * 3] * c2 + P[b1 * 3] * c3
	end
	for r = 1, G.n - 1 do
		local s0, n = G.start[r], G.count[r]
		for j = 0, n - 1 do
			local i = s0 + j
			local jp, jn = j - 1, j + 1
			if jp < 0 then
				jp = n - 2
			end
			if jn > n - 1 then
				jn = 1
			end
			local a, b = s0 + jp, s0 + jn
			local tux, tuy, tuz = P[b * 3 - 2] - P[a * 3 - 2], P[b * 3 - 1] - P[a * 3 - 1], P[b * 3] - P[a * 3]
			local u = U[i * 2 - 1]
			local ax, ay, az = rowAt(r - 1, u)
			local bx, by, bz = rowAt(r + 1, u)
			local tvx, tvy, tvz = bx - ax, by - ay, bz - az
			local nx, ny, nz = tuy * tvz - tuz * tvy, tuz * tvx - tux * tvz, tux * tvy - tuy * tvx
			local l = sqrt(nx * nx + ny * ny + nz * nz)
			if l > 1e-12 then
				-- keep the side the face normals (ComputeNormals, run first) point to
				if nx * N[i * 3 - 2] + ny * N[i * 3 - 1] + nz * N[i * 3] < 0 then
					l = -l
				end
				N[i * 3 - 2], N[i * 3 - 1], N[i * 3] = nx / l, ny / l, nz / l
			end
		end
		MeshKit.Step(n)
	end
end

------------------------------------------------------------------------
-- Eyeballs (sphere + cornea, iris painted by angle from the gaze axis)
------------------------------------------------------------------------
local EYE_COLORS = {
	{ 60, 36, 22 }, { 96, 60, 34 }, { 120, 90, 48 }, { 72, 110, 60 }, { 70, 120, 180 }, { 110, 120, 130 }, { 160, 110, 40 },
}
local IRIS_A, PUPIL_A, LIMBUS_A = 0.45, 0.13, 0.5 -- angles from the gaze axis (radians)
Gen.IRIS = { iris = IRIS_A, pupil = PUPIL_A, limbus = LIMBUS_A }

-- polar UV map of the eyeball: the iris gets 60 % of the radius (texture detail where it is seen)
local function eyeUV(ang, ph)
	local r = ang < 0.55 and (ang / 0.55) * 0.3 or 0.3 + (ang - 0.55) / (2.6 - 0.55) * 0.19
	return 0.5 + r * cos(ph), 0.5 - r * sin(ph)
end

local function eyeColors(F, look, side)
	local f = type(look.face) == "table" and look.face or {}
	local ci = f.eyeColor
	if side == 1 and num(f.eyeColor2, 0) > 0 then
		ci = f.eyeColor2
	end
	local col = EYE_COLORS[clamp(floor(num(ci, 2)), 1, #EYE_COLORS)]
	local age = F.age
	local ak = clamp((age - 25) / 30, 0, 1)
	return { col[1] / 255, col[2] / 255, col[3] / 255 }, { lerp(0.93, 0.9, ak), lerp(0.9, 0.85, ak), lerp(0.86, 0.75, ak) }
end

local function eyeMesh(F, side, lod, look, m)
	local E = { cx = F.eye[side].x, cy = F.eye[side].y, cz = F.eye[side].z }
	m = m or MeshKit.New("Eye")
	local first = m.nv + 1
	local firstTri = m.nt + 1
	local R = F.eyeR
	local iris, scl = eyeColors(F, look, side)
	local ir, ig, ib = iris[1], iris[2], iris[3]
	-- rings by angle from the front pole: pupil, iris, limbus, sclera; open at the back (inside the head)
	local angs
	if lod == "full" then
		angs = { 0, PUPIL_A, 0.28, IRIS_A, LIMBUS_A, 0.66, 1.0, 1.45, 2.0, 2.6 }
	elseif lod == "medium" then
		angs = { 0, PUPIL_A, 0.3, IRIS_A, 0.6, 1.1, 1.8 }
	else
		angs = { 0, 0.25, LIMBUS_A, 1.2, 2.2 }
	end
	local sides = lod == "full" and 14 or (lod == "medium" and 9 or 7)
	local ringStart = {}
	for k, ang in ipairs(angs) do
		-- cornea bulge over the iris
		local r = R + 0.0055 * (1 - smoothstep(0.2, 0.62, ang))
		local cr, cg, cb
		if ang < PUPIL_A - 0.01 then
			cr, cg, cb = 0.015, 0.012, 0.012
		elseif ang < IRIS_A + 0.01 then
			-- iris: a lighter collarette near the pupil, darker toward the rim
			local t = (ang - PUPIL_A) / (IRIS_A - PUPIL_A)
			local k2 = 1.15 - 0.45 * t
			cr, cg, cb = ir * k2, ig * k2, ib * k2
		elseif ang < 0.56 then
			cr, cg, cb = lerp(ir * 0.35, scl[1], 0.35), lerp(ig * 0.35, scl[2], 0.35), lerp(ib * 0.35, scl[3], 0.35) -- limbus
		else
			cr, cg, cb = scl[1], scl[2], scl[3]
			if ang > 1.0 then
				cr, cg, cb = cr * 0.97, cg * 0.92, cb * 0.9 -- pinker toward the corners
			end
		end
		if ang < 1e-6 then
			local u, v = eyeUV(0, 0)
			ringStart[k] = MeshKit.Vertex(m, E.cx, E.cy, E.cz - r, u, v, cr, cg, cb)
		else
			ringStart[k] = m.nv + 1
			local lidUp, lidDn = sin(F.bUp), sin(F.bDn)
			for j = 0, sides - 1 do
				local ph = TAU * j / sides
				local sx, sy = sin(ang) * cos(ph), sin(ang) * sin(ph)
				local u, v = eyeUV(ang, ph)
				-- the lids' shadow on the top (and a little the bottom) of the eye
				local sh = 1 - 0.32 * smoothstep(lidUp - 0.32, lidUp - 0.02, sy) - 0.12 * smoothstep(-lidDn + 0.18, -lidDn - 0.02, sy)
				MeshKit.Vertex(m, E.cx + r * sx, E.cy + r * sy, E.cz - r * cos(ang), u, v, cr * sh, cg * sh, cb * sh)
			end
			-- the seam column again (u, v continuous round the ring for the texture)
			local sx = sin(ang)
			local u, v = eyeUV(ang, TAU)
			MeshKit.Vertex(m, E.cx + r * sx, E.cy, E.cz - r * cos(ang), u, v, cr, cg, cb)
		end
	end
	local n = #angs
	for k = 1, n - 1 do
		local a0, a1 = ringStart[k], ringStart[k + 1]
		for j = 0, sides - 1 do
			if k == 1 then
				MeshKit.Tri(m, a0, a1 + j, a1 + j + 1)
			else
				MeshKit.Quad(m, a0 + j, a1 + j, a1 + j + 1, a0 + j + 1)
			end
		end
	end
	MeshKit.OrientFrom(m, E.cx, E.cy, E.cz, firstTri, m.nt)
	return m, first
end

-- the iris / sclera texture of one eye (w x w): radial fibres, collarette, crypts, limbal ring, sclera tint
local function eyeTexture(m, F, look, side, w, pscale)
	local iris, scl = eyeColors(F, look, side)
	local ir, ig, ib = iris[1], iris[2], iris[3]
	local E = F.eye[side]
	local R = F.eyeR
	local seed = F.seed + side * 31
	-- the collarette tint: amber for hazel / green / blue eyes, a lighter brown for brown ones
	local lum = 0.3 * ir + 0.59 * ig + 0.11 * ib
	local cr, cg, cb = lerp(ir, 0.62, 0.35), lerp(ig, 0.45, 0.3), lerp(ib, 0.22, 0.4)
	if lum < 0.2 then
		cr, cg, cb = ir * 1.5, ig * 1.4, ib * 1.25
	end
	local psx, psy, psz = pscale[1], pscale[2], pscale[3]
	local noise = MeshKit.Noise
	local function base(px, py, r, g, b, x, y, z)
		local dx, dy, dz = x - E.x, y - E.y, z - E.z
		local l = sqrt(dx * dx + dy * dy + dz * dz)
		if l < 1e-6 then
			return r, g, b
		end
		local ang = math.acos(clamp(-dz / l, -1, 1))
		local ph = math.atan2(dy, dx)
		if ang < PUPIL_A then
			return 0.012, 0.01, 0.01
		elseif ang < LIMBUS_A + 0.02 then
			-- iris: radial fibres (noise along the angle), crypts, collarette, dark rim
			local t = (ang - PUPIL_A) / (IRIS_A - PUPIL_A)
			local fib = noise(ph * 14, t * 3, 0.5, seed)
			local fib2 = noise(ph * 37, t * 9, 1.5, seed + 3)
			local k = 0.9 + 0.22 * fib + 0.1 * fib2
			local rr, gg, bb = ir * k, ig * k, ib * k
			-- collarette: a ragged ring a third of the way out
			local cw = bump(((t - 0.32 - 0.05 * noise(ph * 6, 0, 2.5, seed)) / 0.13) ^ 2)
			rr, gg, bb = lerp(rr, cr * k, cw * 0.7), lerp(gg, cg * k, cw * 0.7), lerp(bb, cb * k, cw * 0.7)
			-- crypts: small dark pits
			if noise(ph * 22, t * 12, 3.5, seed + 7) > 0.55 then
				rr, gg, bb = rr * 0.72, gg * 0.72, bb * 0.72
			end
			-- dark pupil margin and the limbal ring at the edge
			local dk = 1 - 0.5 * bump((t / 0.1) ^ 2) - 0.55 * smoothstep(0.82, 1.02, t)
			rr, gg, bb = rr * dk, gg * dk, bb * dk
			if ang > IRIS_A then
				local f2 = smoothstep(IRIS_A, LIMBUS_A + 0.02, ang)
				rr, gg, bb = lerp(rr, scl[1] * 0.85, f2), lerp(gg, scl[2] * 0.82, f2), lerp(bb, scl[3] * 0.82, f2)
			end
			return rr, gg, bb
		end
		-- sclera: whiter at the front, greyer / pinker toward the corners, faint veins there
		local k = 1 - 0.06 * smoothstep(0.6, 1.4, ang)
		local rr, gg, bb = scl[1] * k, scl[2] * k, scl[3] * k
		local corner = abs(cos(ph)) * smoothstep(0.8, 1.3, ang)
		if corner > 0 then
			local vein = 1 - abs(noise(ph * 9, ang * 7, 4.5, seed + 11))
			local vk = smoothstep(0.9, 0.98, vein) * corner * 0.35
			rr, gg, bb = lerp(rr, 0.78, vk), lerp(gg, 0.42, vk), lerp(bb, 0.42, vk)
			rr, gg, bb = rr * (1 - 0.03 * corner), gg * (1 - 0.07 * corner), bb * (1 - 0.07 * corner)
		end
		return rr, gg, bb
	end
	-- the upper lid and lashes shade the top of the eye (the band just under the lid margin), the lower lid
	-- a little: the eye sits in its socket instead of glowing
	local up = sin(F.bUp)
	local dn = sin(F.bDn)
	local function shade(px, py, r, g, b, x, y, z)
		local rr, gg, bb = base(px, py, r, g, b, x, y, z)
		local h = (y - E.y) / R
		local k = 1 - 0.32 * smoothstep(up - 0.32, up - 0.02, h) - 0.12 * smoothstep(-dn + 0.18, -dn - 0.02, h)
		return rr * k, gg * k, bb * k
	end
	-- positions are in the mesh's scaled space: shade works in nominal space
	local P = m.P
	local nominal = { P = table.create(m.nv * 3, 0), U = m.U, C = m.C, T = m.T, nv = m.nv, nt = m.nt }
	for i = 1, m.nv do
		nominal.P[i * 3 - 2], nominal.P[i * 3 - 1], nominal.P[i * 3] = P[i * 3 - 2] * psx, P[i * 3 - 1] * psy, P[i * 3] * psz
	end
	return Paint.Rasterize(nominal, w, w, shade, 2, { scl[1], scl[2], scl[3] })
end

------------------------------------------------------------------------
-- Eyelids: shells over the eyeball from the margin to well past the socket rim (hidden there), so a
-- rigid turn about the fissure axis is a blink. Upper lid with a lash fringe; lower lid sits over it.
------------------------------------------------------------------------
local function lidMesh(F, side, lower, lod, skin, hairRGB, m)
	local E = eyeFrame(F, side)
	m = m or MeshKit.New(lower and "LidLow" or "Lid")
	local first = m.nv + 1
	local firstTri = m.nt + 1
	local R = F.eyeR
	local sg = lower and -1 or 1
	local rOut = R + (lower and F.lowOut or F.lidOut)
	local rIn = R + 0.0015
	local nA = lod == "full" and 11 or (lod == "medium" and 7 or 5)
	local deg = math.rad
	local sr, sgc, sb = skin[1], skin[2], skin[3]
	local dkS = Paint.Darkness(sr, sgc, sb)
	-- profile rows: (elevation offset from the margin, radius, colour kind)
	local prof
	if lower then
		prof = { { 0, rIn, "wet" }, { deg(0.8), R + 0.008, "rim" }, { deg(2.5), rOut, "lid" }, { deg(12), rOut - 0.0008, "lid" }, { deg(45), rOut - 0.003, "hid" } }
	else
		prof = { { 0, rIn, "wet" }, { deg(0.7), R + 0.0072, "line" }, { deg(2.2), rOut, "line2" }, { deg(10), rOut, "lid" }, { deg(25), rOut - 0.0008, "lid" }, { deg(42), rOut - 0.0016, "lid" }, { deg(62), rOut - 0.0024, "hid" }, { deg(84), rOut - 0.003, "hid" }, { deg(105), rOut - 0.0035, "hid" } }
	end
	if lod ~= "full" then
		local keep = {}
		for i, p in ipairs(prof) do
			if i ~= 2 and i ~= 4 then
				keep[#keep + 1] = p
			end
		end
		prof = keep
	end
	local np = #prof
	local cols = {}
	local aA, aB = F.aMed - deg(2), F.aLat + deg(2)
	if lower then
		aA, aB = F.aMed - EXT_MED - deg(5), F.aLat + EXT_LAT + deg(5)
		nA = floor(nA * 1.4 + 0.5)
	end
	for i = 0, nA do
		local a = lerp(aA, aB, i / nA)
		local up = marginAt(F, a)
		local bm = lower and lowerEdge(F, a) or up
		cols[i] = m.nv + 1
		for k, p in ipairs(prof) do
			local b = bm + sg * p[1]
			local x, y, z = eyePoint(E, a, b, p[2])
			local kind = p[3]
			local cr, cg, cb
			if kind == "wet" then
				cr, cg, cb = lerp(sr, lerp(0.84, 0.58, dkS), 0.5), lerp(sgc, lerp(0.5, 0.34, dkS), 0.5), lerp(sb, lerp(0.5, 0.32, dkS), 0.5)
			elseif kind == "rim" then
				cr, cg, cb = lerp(sr, 0.8, 0.3 - 0.15 * dkS) * 0.95, lerp(sgc, 0.52, 0.3 - 0.15 * dkS) * 0.95, lerp(sb, 0.5, 0.3 - 0.15 * dkS) * 0.95
			elseif kind == "line" then
				cr, cg, cb = sr * 0.38 + 0.02, sgc * 0.33 + 0.015, sb * 0.31 + 0.012
			elseif kind == "line2" then
				cr, cg, cb = sr * 0.75, sgc * 0.68, sb * 0.66
			else
				-- the lid skin: a little darker and warmer than the face, more so on the upper lid
				local k2 = lower and 0.88 or 0.85
				cr, cg, cb = sr * k2, sgc * k2 * 0.97, sb * k2 * 0.97
			end
			local vid = MeshKit.Vertex(m, x, y, z, 0.5, 0.5, cr, cg, cb)
			if kind ~= "wet" and kind ~= "line" then
				-- the lid's skin (FaceFX tints it with a black eye; never the lash line or the lashes)
				MeshKit.AddToGroup(m, "LidSkin", vid)
			end
		end
	end
	for i = 0, nA - 1 do
		local c0, c1 = cols[i], cols[i + 1]
		for k = 0, np - 2 do
			MeshKit.Quad(m, c0 + k, c0 + k + 1, c1 + k + 1, c1 + k)
		end
	end
	-- face away from the eyeball
	MeshKit.OrientFrom(m, E.cx, E.cy, E.cz, firstTri, m.nt)
	-- lashes: fine tapering ribbons in two staggered rows along the margin's front edge, leaving the lid
	-- forward and curling away from the eye (up on the upper lid, down on the lower); longest over the outer
	-- third. The lid pieces are double-sided, so each lash is one strip (3 triangles)
	local lashK = F.lashes
	if lod == "full" and (not lower or lashK > 0.15) then
		local dk = lower and 0.42 or 0.3
		local hr, hg, hb = lerp(hairRGB[1] * dk, 0.05, 0.45), lerp(hairRGB[2] * dk, 0.04, 0.45), lerp(hairRGB[3] * dk, 0.035, 0.45)
		local fem = F.female and 1 or 0
		local nL = lower and floor(10 + 8 * lashK) or floor(36 + 10 * fem + 14 * lashK)
		local len = lower and (0.006 + 0.004 * lashK) or (0.014 + 0.006 * fem + 0.01 * lashK)
		local seed = F.seed + (side > 0 and 7 or 3) + (lower and 11 or 0)
		local rootR = R + (lower and 0.0095 or 0.0082)
		for i = 0, nL - 1 do
			local u = (i + 0.5) / nL
			local jit = (hash(i, seed) - 0.5) * 0.8 / nL
			local uu = clamp(u + jit, 0, 1)
			local a = lerp(F.aMed + deg(12), F.aLat - deg(4), uu)
			local up, dn = marginAt(F, a)
			local row2 = i % 2 == 1
			local bm = (lower and dn or up) + sg * deg(row2 and 1.6 or 0.9)
			-- longest over the outer third, short at the inner corner
			local centre = clamp(1 - abs(uu - 0.65) * 1.6, 0.2, 1)
			local L = len * (0.45 + 0.75 * centre) * (0.7 + 0.5 * hash(i + 50, seed)) * (row2 and 0.85 or 1)
			local fan = deg(10) * (uu - 0.55) -- fan out toward the corners
			local curl = deg((lower and 4 or 9) + 6 * hash(i + 90, seed))
			local r0 = rootR + (row2 and 0.0005 or 0)
			local rx, ry, rz = eyePoint(E, a, bm, r0)
			local mx, my, mz = eyePoint(E, a + fan * 0.4, bm + sg * curl * 0.2, r0 + L * 0.55)
			local tx, ty, tz = eyePoint(E, a + fan, bm + sg * curl, r0 + L)
			-- width along the margin
			local wdt = (lower and 0.00045 or 0.0006) * (0.8 + 0.4 * hash(i + 130, seed))
			local ax2, ay2, az2 = eyePoint(E, a + wdt / R, bm, r0)
			local bx2, by2, bz2 = (ax2 - rx) * 0.5, (ay2 - ry) * 0.5, (az2 - rz) * 0.5
			local r1 = MeshKit.Vertex(m, rx - bx2, ry - by2, rz - bz2, 0.5, 0.5, hr, hg, hb)
			local r2 = MeshKit.Vertex(m, rx + bx2, ry + by2, rz + bz2, 0.5, 0.5, hr, hg, hb)
			local m1 = MeshKit.Vertex(m, mx - bx2 * 0.55, my - by2 * 0.55, mz - bz2 * 0.55, 0.5, 0.5, hr, hg, hb)
			local m2 = MeshKit.Vertex(m, mx + bx2 * 0.55, my + by2 * 0.55, mz + bz2 * 0.55, 0.5, 0.5, hr, hg, hb)
			local t1 = MeshKit.Vertex(m, tx, ty, tz, 0.5, 0.5, hr * 1.6, hg * 1.6, hb * 1.6)
			MeshKit.Tri(m, r1, r2, m2)
			MeshKit.Tri(m, r1, m2, m1)
			MeshKit.Tri(m, m1, m2, t1)
		end
	end
	return m, first
end

------------------------------------------------------------------------
-- Ears: a closed pillow; the outer face carries helix, scapha, antihelix, concha, tragus, lobule
------------------------------------------------------------------------
-- the ear's frame: centre, outward normal n, back p, up q, size (shared with Gen.Landmarks)
local function earFrame(F, side, lod)
	local s = F.earSize
	local H, W = 0.152 * s, 0.084 * s
	local cauli = F.cauli
	local rnd = F.rnd
	local asymA = 0.3 + F.P.asym
	local ey = F.eyeY - 0.092 + side * rnd(21) * 0.008 * asymA
	local ez = 0.085
	-- the head's side surface at the ear
	local tS = hit(F.field, 0, ey, ez, side, 0, 0, 0.4)
	-- a coarse grid's side surface lies inside the true one (chords): sink the ear so it never floats
	local inset = lod == "low" and 0.014 or (lod == "medium" and 0.006 or 0)
	local cx = side * (tS - 0.006 - inset)
	-- protrusion psi about the vertical, then the backward tilt tau about the outward normal
	local psi = math.rad(18 + 14 * cauli + 6 * rnd(22) * asymA)
	local tau = math.rad(14)
	local nx, nz = side * cos(psi), -sin(psi)
	local p1x, p1z = side * sin(psi), cos(psi)
	local qx, qy, qz = p1x * sin(tau), cos(tau), p1z * sin(tau)
	local px, py, pz = p1x * cos(tau), -sin(tau), p1z * cos(tau)
	-- the ear's centre sits out from its root: front edge on the head, back edge free
	local ocx, ocy, ocz = cx + nx * 0.012 + px * (W * 0.85), ey, ez + nz * 0.012 + pz * (W * 0.85)
	return { ocx, ocy, ocz }, nx, nz, px, py, pz, qx, qy, qz, H, W
end

local function earMesh(F, side, lod, skin, m, uvBox)
	m = m or MeshKit.New("Ear")
	local first = m.nv + 1
	local firstTri = m.nt + 1
	local cauli = F.cauli
	local c0, nx, nz, px, py, pz, qx, qy, qz, H, W = earFrame(F, side, lod)
	local ocx, ocy, ocz = c0[1], c0[2], c0[3]
	local function outline(w)
		-- w: 0 = back (+p), pi/2 = up, pi = front (toward the face), 3pi/2 = down (lobule)
		local r = 1 / sqrt((cos(w) / W) ^ 2 + (sin(w) / H) ^ 2)
		if sin(w) < 0 then
			r *= 1 - 0.18 * (-sin(w)) ^ 2 -- the lobule is narrower
		end
		if cos(w) < -0.3 then
			r *= 0.92 -- the front edge is straighter
		end
		return r
	end
	local function outer(rho, w)
		-- relief of the outer (lateral) face, studs along n
		local sw, cw = sin(w), cos(w)
		local h = 0.0
		-- helix rim, curled: high along the edge except the front / lobule
		local helixK = smoothstep(-0.6, 0.0, sw + 0.35 * cw)
		h += 0.017 * bump(((rho - 0.91) / 0.1) ^ 2) * helixK
		-- scapha groove inside the helix
		h -= 0.007 * bump(((rho - 0.77) / 0.07) ^ 2) * helixK
		-- antihelix ridge (Y shaped crura at the top)
		local ah = smoothstep(-0.7, -0.1, sw) * (1 - smoothstep(0.5, 0.95, -cw))
		h += 0.014 * bump(((rho - 0.6) / 0.09) ^ 2) * ah
		-- concha bowl: deep, front-centre
		local cq = ((rho * cw + 0.15) / 0.42) ^ 2 + ((rho * sw + 0.08) / 0.45) ^ 2
		h -= 0.024 * bump(cq)
		-- tragus (front) and antitragus (lower back)
		h += 0.012 * bump(((rho * cw + 0.62) / 0.16) ^ 2 + ((rho * sw + 0.12) / 0.2) ^ 2)
		h += 0.009 * bump(((rho * cw - 0.08) / 0.16) ^ 2 + ((rho * sw + 0.52) / 0.14) ^ 2)
		-- lobule: soft and flat
		h += 0.004 * bump(((rho * sw + 0.82) / 0.2) ^ 2 + (rho * cw / 0.4) ^ 2)
		-- cauliflower: the upper rim and scapha fill and lump up
		if cauli > 0.05 then
			local lump = 0.5 + 0.5 * sin(w * 5 + F.seed % 7) * cos(rho * 9)
			h += cauli * (0.012 * smoothstep(0.35, 0.8, rho) * smoothstep(-0.2, 0.6, sw) * (0.6 + 0.6 * lump))
		end
		return h
	end
	local nW = lod == "full" and 12 or (lod == "medium" and 9 or 6)
	local outerR = lod == "full" and { 0.0, 0.22, 0.4, 0.52, 0.62, 0.7, 0.78, 0.86, 0.92, 0.97 } or (lod == "medium" and { 0.0, 0.45, 0.7, 0.88 } or { 0.0, 0.6 })
	local backR = lod == "full" and { 0.6 } or { 0.6 }
	local thick = 0.008 + 0.01 * cauli
	local function place(rho, w, hOut)
		local r = rho * outline(w)
		local lp, lq = r * cos(w), r * sin(w)
		return ocx + px * lp + qx * lq + nx * hOut, ocy + py * lp + qy * lq, ocz + pz * lp + qz * lq + nz * hOut
	end
	local function uv(rho, w)
		local u = 0.5 + 0.5 * rho * cos(w) * side
		local v = 0.5 - 0.5 * rho * sin(w)
		return uvBox[1] + (uvBox[3] - uvBox[1]) * u, uvBox[2] + (uvBox[4] - uvBox[2]) * v
	end
	local cr, cg, cb = skin[1], skin[2], skin[3]
	-- rings: outer pole, outer rings, rim, back rings, back pole
	local rings = {}
	local pole = MeshKit.Vertex(m, 0, 0, 0)
	do
		local x, y, z = place(0, 0, outer(0, 0) + thick * 0.5)
		MeshKit.SetPosition(m, pole, x, y, z)
		local u, v = uv(0, 0)
		MeshKit.SetUV(m, pole, u, v)
		MeshKit.SetColor(m, pole, cr * 0.82, cg * 0.72, cb * 0.7)
	end
	rings[#rings + 1] = { pole = pole }
	local function ring(rho, hfn, back)
		local start = m.nv + 1
		for j = 0, nW - 1 do
			local w = TAU * j / nW
			local x, y, z = place(rho, w, hfn(rho, w))
			local u, v = uv(rho, w)
			-- ears redden at the rim and in the bowl
			local k = 1 - 0.1 * smoothstep(0.75, 1, rho) - (back and 0 or 0.22 * bump(((rho * cos(w) + 0.15) / 0.42) ^ 2 + ((rho * sin(w) + 0.08) / 0.45) ^ 2))
			MeshKit.Vertex(m, x, y, z, u, v, cr * k, cg * k * 0.94, cb * k * 0.92)
		end
		rings[#rings + 1] = { start = start }
		MeshKit.Step(nW * 2) -- the relief functions are not cheap: let AnatomyClient yield between rings
	end
	for i = 2, #outerR do
		ring(outerR[i], function(rho, w)
			return outer(rho, w) + thick * 0.5
		end)
	end
	ring(1.0, function()
		return 0
	end)
	for _, rb in ipairs(backR) do
		ring(rb, function(rho)
			-- the back bulges behind the concha (the bowl is deep)
			return -(thick * 0.5 + 0.016 * (1 - rho * rho) + 0.02 * bump((rho / 0.6) ^ 2))
		end, true)
	end
	local bp = MeshKit.Vertex(m, 0, 0, 0)
	do
		local x, y, z = place(0, 0, -(thick * 0.5 + 0.02))
		MeshKit.SetPosition(m, bp, x, y, z)
		local u, v = uv(0, 0)
		MeshKit.SetUV(m, bp, u, v)
		MeshKit.SetColor(m, bp, cr, cg, cb)
	end
	rings[#rings + 1] = { pole = bp }
	for i = 1, #rings - 1 do
		local A, B = rings[i], rings[i + 1]
		for j = 0, nW - 1 do
			local j1 = (j + 1) % nW
			if A.pole then
				MeshKit.Tri(m, A.pole, B.start + j, B.start + j1)
			elseif B.pole then
				MeshKit.Tri(m, A.start + j, B.pole, A.start + j1)
			else
				MeshKit.Quad(m, A.start + j, B.start + j, B.start + j1, A.start + j1)
			end
		end
	end
	-- outward: away from the ear's own centre plane
	MeshKit.OrientFrom(m, ocx, ocy, ocz, firstTri, m.nt)
	return m, first
end

------------------------------------------------------------------------
-- Generate
------------------------------------------------------------------------
local function scaleMesh(m, P)
	if abs(P.kx - 1) > 1e-9 or abs(P.ky - 1) > 1e-9 or abs(P.kz - 1) > 1e-9 then
		MeshKit.Transform(m, MeshKit.MatScale(P.kx, P.ky, P.kz))
	end
end

-- Without hair meshes (no AnatomyHair generator beside this module) the round-1 hair stays, and it is built
-- for the round-1 head (a 1.2-stud ball): over this head's real proportions it floats off the skull and
-- covers the forehead / eyes. Then only bald heads get a mesh (the others keep the round-1 head and hair).
-- Off once AnatomyHair exists. Reads look.hair.style (request: add it to LookData.SECTIONS.Head).
Gen.HAIR_GATE = true
local HAIR_MESHES = script.Parent:FindFirstChild("AnatomyHair") ~= nil
local function hairGated(look)
	if not Gen.HAIR_GATE or HAIR_MESHES then
		return false
	end
	local h = type(look.hair) == "table" and look.hair or nil
	local style = h and h.style
	return type(style) == "string" and style ~= "Bald"
end
Gen.HairGated = hairGated

-- colour texture size per level (the Head may use 512 at full; medium <= 128; low none)
Gen.TEXTURE = { full = 384, medium = 128 }
Gen.EYE_TEXTURE = { full = 128 }
Gen.BEARD_TEXTURE = { full = 256, medium = 128 }

Gen._internal = function()
	return { layout = layout, baseField = baseField, reliefFn = reliefFn, hit = hit, ray = ray, eyeFrame = eyeFrame, eyeAngles = eyeAngles, rimAt = rimAt, raySphere = raySphere }
end

-- a point on the face: the ray from inside the head straight forward through (x, y), base field + relief
local function surfaceFn(F)
	return function(x, y)
		local t = hit(F.field, x, y, ZA, 0, 0, -1, 0.42)
		local z = ZA - t
		return x, y, z - F.relief(x, y, z)
	end
end

local function prepare(look)
	local F = layout(look)
	F.field = baseField(F)
	F.relief = reliefFn(F)
	return F
end

-- landmarks in the Head part's space (scaled), as AnatomyClient wants them: { name = { part, pos } }
local function landmarksOf(F)
	local surf = surfaceFn(F)
	local ears = {}
	for side = -1, 1, 2 do
		ears[side] = (earFrame(F, side))
	end
	local yT = 0.22
	local tTop = hit(F.field, 0, yT, ZA, 0, 1, 0, 0.38)
	local tBack = hit(F.field, 0, 0.05, ZA, 0, 0, 1, 0.45)
	local L = Rig.Landmarks(F, surf, ears, { 0, yT + tTop, ZA }, { 0, 0.05, ZA + tBack }, F.P.hairFront)
	local P = F.P
	local out = {}
	for name, p in pairs(L) do
		if name == "EyeRadius" then
			out[name] = { part = "Head", pos = { p[1] * P.kx, 0, 0 } }
		else
			out[name] = { part = "Head", pos = { p[1] * P.kx, p[2] * P.ky, p[3] * P.kz } }
		end
	end
	return out
end

-- cheap (no meshes): the landmarks Generate returns, for the server Builder and tools
function Gen.Landmarks(look)
	return landmarksOf(prepare(look))
end

-- low level: no eyeball pieces; the eyes are painted on the (socket-less) grid
local function paintLowEyes(m, F, look, last)
	local P, C = m.P, m.C
	for side = -1, 1, 2 do
		local E = eyeFrame(F, side)
		local iris = eyeColors(F, look, side)
		for i = 1, last do
			local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
			if z < E.cz and abs(x - E.cx) < 0.08 and abs(y - E.cy) < 0.06 then
				local a, b = eyeAngles(E, x, y, z)
				local up, dn = marginAt(F, a)
				if a > F.aMed - 0.15 and a < F.aLat + 0.15 and b < up + 0.12 and b > dn - 0.1 then
					-- from afar an eye is a shadowed socket with a dark iris: never a white slit (a coarse grid
					-- would smear the white over the lids)
					local k = (sqrt(a * a + b * b) < IRIS_A + 0.2) and 0.5 or 0.25
					local sr, sg, sb = C[i * 3 - 2] * 0.6, C[i * 3 - 1] * 0.56, C[i * 3] * 0.55
					C[i * 3 - 2] = lerp(sr, iris[1] * 0.6, k)
					C[i * 3 - 1] = lerp(sg, iris[2] * 0.6, k)
					C[i * 3] = lerp(sb, iris[3] * 0.6, k)
				end
			end
		end
	end
end

-- share of the head grid's triangles each beard style adds (for the budget)
local BEARD_SHARE = {
	Moustache = 0.05, Goatee = 0.1, ["Van Dyke"] = 0.1, ["Circle Beard"] = 0.13, ["Chin Strap"] = 0.1,
	["Mutton Chops"] = 0.2, ["Short Boxed"] = 0.3, ["Full Beard"] = 0.32,
}

local function lazyTexture(w, h, make)
	return setmetatable({ w = w, h = h }, {
		__index = function(t, k)
			if k ~= "buffer" then
				return nil
			end
			local buf = make()
			rawset(t, "buffer", buf)
			return buf
		end,
	})
end

-- profiling hook for tests only: Gen._clock = os.clock fills Gen._prof (never set in the game)
Gen._clock = nil
Gen._prof = {}
local profT = 0
local function mark(name)
	local clock = Gen._clock
	if clock then
		local t = clock()
		if name then
			Gen._prof[name] = (Gen._prof[name] or 0) + (t - profT)
		end
		profT = t
	end
end

function Gen.Generate(look, lod, ctx)
	if hairGated(look) then
		return { pieces = {}, landmarks = {} }
	end
	mark(nil)
	local F = prepare(look)
	local full, medium = lod == "full", lod == "medium"
	local sr, sg, sb = Paint.Skin(look)
	local skin = { sr, sg, sb }
	local hr, hg, hb = Paint.HairColor(look, F.age, false)
	local hair = { hr, hg, hb }
	local P = F.P
	local pscale = { 1 / P.kx, 1 / P.ky, 1 / P.kz }
	local budget = tonumber(ctx and ctx.budget) or (full and 5000 or (medium and 2000 or 700))
	local surf = surfaceFn(F)
	local pieces = {}
	local used = 0
	-- the fixed pieces first; the head grid gets what the budget leaves
	if full then
		for side = -1, 1, 2 do
			local tag = side < 0 and "L" or "R"
			local em = eyeMesh(F, side, lod, look)
			MeshKit.ComputeNormals(em)
			local lid = lidMesh(F, side, false, lod, skin, hair)
			MeshKit.ComputeNormals(lid, { crease = 60 })
			pieces["Eye" .. tag] = { mesh = em, attach = "Head", reflectance = 0.1 }
			pieces["Lid" .. tag] = { mesh = lid, attach = "Head", doubleSided = true }
			used += em.nt + lid.nt
		end
		local low = lidMesh(F, -1, true, lod, skin, hair)
		lidMesh(F, 1, true, lod, skin, hair, low)
		MeshKit.ComputeNormals(low, { crease = 60 })
		pieces.LidLow = { mesh = low, attach = "Head", doubleSided = true }
		local up, lo = Rig.MouthMeshes(F, surf)
		MeshKit.ComputeNormals(up)
		MeshKit.ComputeNormals(lo)
		pieces.MouthUpper = { mesh = up, attach = "Head", castShadow = false }
		pieces.MouthLower = { mesh = lo, attach = "Head", castShadow = false }
		used += low.nt + up.nt + lo.nt
	elseif medium then
		local eyes = eyeMesh(F, -1, lod, look)
		eyeMesh(F, 1, lod, look, eyes)
		local nEye = eyes.nt
		lidMesh(F, -1, true, lod, skin, hair, eyes)
		lidMesh(F, 1, true, lod, skin, hair, eyes)
		MeshKit.ComputeNormals(eyes, { crease = 60 })
		pieces.Eyes = { mesh = eyes, attach = "Head", reflectance = 0.06 }
		local lids = lidMesh(F, -1, false, lod, skin, hair)
		lidMesh(F, 1, false, lod, skin, hair, lids)
		MeshKit.ComputeNormals(lids, { crease = 60 })
		pieces.LidUpper = { mesh = lids, attach = "Head", doubleSided = true }
		used += eyes.nt + lids.nt
		local _ = nEye
	end
	mark("pieces")
	-- the ears' triangles (built below into the head piece)
	local earScratch = MeshKit.New("EarCount")
	earMesh(F, 1, lod, skin, earScratch, { 0, 0, 1, 1 })
	used += earScratch.nt * 2
	-- the head grid's density for the rest of the budget (a beard is a share of the grid's triangles)
	local style = Paint.BeardStyle(look)
	local share = style and BEARD_SHARE[style] or 0
	local target = (budget - used) / (1 + share) * 0.97
	local q = Gen.GRID_Q[lod] or 1
	for _ = 1, 2 do
		local est = gridTris(F, q)
		if est <= target then
			break
		end
		q *= sqrt(target / est) * 0.99
	end
	mark("estimate")
	local head = headSurface(F, q, lod ~= "low")
	-- the estimate is coarse and the beard's share depends on the face: count the real triangles (the beard
	-- takes every grid triangle with a covered corner, Rig.BeardMesh) and rebuild coarser until it fits
	local mask = style and Rig.BEARDS[style] and Rig.BeardMask(F, style)
	for attempt = 1, 4 do
		local extra = 0
		if mask then
			local P, T = head.P, head.T
			local cov = {}
			for i = 1, head.nv do
				local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
				cov[i] = z < 0.2 and y < F.noseBaseY + 0.02 and y > F.chinY - 0.25 and mask(x, y, z) > 0.002
				MeshKit.Step(1)
			end
			for t = 1, head.nt do
				if cov[T[t * 3 - 2]] or cov[T[t * 3 - 1]] or cov[T[t * 3]] then
					extra += 1
				end
			end
		end
		if used + head.nt + extra <= budget or attempt == 4 then
			break
		end
		q *= sqrt((budget - used) / (head.nt + extra)) * (attempt < 3 and 0.985 or 0.93)
		head = headSurface(F, q, lod ~= "low")
	end
	mark("grid")
	assignV(head, F)
	local gridN = head.nv
	local texSize = Gen.TEXTURE[lod]
	local colMap, rowMap
	if texSize then
		colMap, rowMap = noiseMaps(head, texSize, texSize)
	end
	MeshKit.Fill(head, sr, sg, sb)
	local ears = {}
	for side = -1, 1, 2 do
		local first = head.nv + 1
		earMesh(F, side, lod, skin, head, side < 0 and { 0.02, 0.905, 0.24, 0.995 } or { 0.26, 0.905, 0.48, 0.995 })
		ears[#ears + 1] = { side = side, first = first, last = head.nv, centre = (earFrame(F, side, lod)) }
	end
	mark("ears+v")
	MeshKit.ComputeNormals(head)
	gridNormals(head)
	mark("normals")
	Paint.Vertex(head, F, look, 1, gridN)
	if lod == "low" then
		paintLowEyes(head, F, look, gridN)
	end
	mark("paint")
	MeshKit.BakeAO(head, { cavity = 0.45, ridge = 0.06, down = 0.1, cavityScale = 5 })
	mark("ao")
	-- the beard grows from the finished grid (positions, normals)
	local beard, beardStyle, beardQ = Rig.BeardMesh(head, F, look, gridN, lod)
	mark("beard")
	if full then
		Rig.AddFaceMorphs(head, F, 1, gridN, ears)
	end
	mark("morphs")
	head.gridRows = nil
	-- to the Head part's size
	for _, piece in pairs(pieces) do
		scaleMesh(piece.mesh, P)
	end
	scaleMesh(head, P)
	Rig.BoxSafe(head)
	local headPiece = { mesh = head }
	if texSize then
		-- made on first use: AnatomyClient reads texture.buffer only when textures are on for this client
		-- (never paid for otherwise); deterministic, so a later read gives the same pixels
		headPiece.texture = lazyTexture(texSize, texSize, function()
			return Paint.Texture(head, F, look, texSize, texSize, HEAD_V * texSize, pscale, colMap, rowMap)
		end)
	end
	pieces.Head = headPiece
	if full then
		for side = -1, 1, 2 do
			local tag = side < 0 and "L" or "R"
			local em = pieces["Eye" .. tag].mesh
			local eSize = Gen.EYE_TEXTURE[lod]
			if eSize then
				pieces["Eye" .. tag].texture = lazyTexture(eSize, eSize, function()
					return eyeTexture(em, F, look, side, eSize, pscale)
				end)
			end
		end
	end
	if beard then
		scaleMesh(beard, P)
		Rig.BoxSafe(beard)
		local bp = { mesh = beard, attach = "Head", material = "Fabric", castShadow = beardStyle ~= "Moustache" }
		local bSize = Gen.BEARD_TEXTURE[lod]
		if bSize and headPiece.texture then
			-- strands over the head's own texture (shared UVs): needs the head texture first
			local headTex = headPiece.texture
			bp.texture = lazyTexture(bSize, bSize, function()
				return Paint.BeardTexture(beard, beardQ, headTex.buffer, texSize, texSize, F, look, bSize, bSize, pscale, Rig.BeardMask(F, beardStyle))
			end)
		end
		pieces.Beard = bp
	end
	mark("finish")
	local lms = landmarksOf(F)
	mark("landmarks")
	return { pieces = pieces, landmarks = lms }
end

return Gen
