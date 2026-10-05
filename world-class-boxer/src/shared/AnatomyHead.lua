-- AnatomyHead: organic head / face meshes for the Head section (ANATOMY_CONTRACTS.md).
-- The head is one closed surface: rays from a smooth family (crown cap, a horizontal face band, chin / neck
-- cap) hit the shared skull (AnatomySkull) blended with a face skeleton (lower-face contour slices, the
-- zygomatic arches) and are pushed out by the soft-tissue relief (brow ridge, orbits, cheeks, lips with the
-- cupid's bow, philtrum, nasolabial folds, chin, jaw line, jowls); rows / columns crowd where the features
-- are. The nose is a solid in the field (a dorsal ridge by type, the lower nose a rounded triangular block
-- with the tip lobule fused on, the wings swelling from its sides, the alar groove and the nostrils' pockets
-- cut in); its lower part is a patch of its own, sampled from a point inside it (it has its own texture
-- island), the eyes' and the mouth's are patches too, each zipped into the grid. The eye sockets dive behind
-- separate eyeball pieces; upper / lower lids are separate thin shells (blinks are rigid turns); ears are
-- closed pillows in the Head piece; the mouth interior (teeth, tongue, throat) is two pieces, the lower one
-- swinging with the jaw. Colour: vertex colours (AnatomyHeadPaint) + a texture at every level (384 / 128 /
-- 64: pores, brow hairs, stubble, painted beards, lips, wrinkles, freckles, moles, scars; at low the eyes are
-- painted too), shaded inside Generate. Motion: AnatomyHeadRig morphs (FaceFX channels, swelling); fight
-- damage is AnatomyHeadDamage's (FaceFX paints it).
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
		{ folder = "Damage", except = { "BloodChest", "RibBruise" } }, { folder = "Muscles", names = { "Neck", "NeckSCM" } } }
end

local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor
local sin, cos, pi, exp = math.sin, math.cos, math.pi, math.exp
local huge = math.huge
local TAU = 2 * pi
local smin, smax = Skull.smin, Skull.smax
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

-- nose types: bridge height at the nasion (root), dorsal hump (+ Roman / Hawk) or scoop (Snub), tip
-- projection / droop, lobule size (bulb), alar width (ala), length, bridge width
local NOSE = {
	Straight = { root = 0.0, hump = 0.0, scoop = 0.0, tip = 0.0, droop = 0.0, bulb = 0.0, ala = 0.0, len = 0.0, bridgeW = 0.0 },
	Roman = { root = 0.01, hump = 0.014, scoop = 0, tip = 0.006, droop = 0.012, bulb = -0.1, ala = 0.0, len = 0.03, bridgeW = 0.05 },
	Button = { root = -0.012, hump = 0, scoop = 0.006, tip = -0.014, droop = -0.012, bulb = 0.35, ala = -0.05, len = -0.06, bridgeW = -0.1 },
	Snub = { root = -0.008, hump = -0.004, scoop = 0.012, tip = -0.006, droop = -0.024, bulb = 0.1, ala = 0.0, len = -0.05, bridgeW = -0.05 },
	Hawk = { root = 0.014, hump = 0.022, scoop = 0, tip = 0.012, droop = 0.026, bulb = -0.25, ala = -0.05, len = 0.06, bridgeW = 0.0 },
	Wide = { root = -0.006, hump = 0, scoop = 0, tip = -0.006, droop = 0, bulb = 0.3, ala = 0.32, len = 0.0, bridgeW = 0.25 },
	Flat = { root = -0.02, hump = 0, scoop = 0.004, tip = -0.024, droop = 0, bulb = 0.2, ala = 0.38, len = -0.03, bridgeW = 0.35 },
	Nubian = { root = -0.012, hump = 0, scoop = 0, tip = -0.008, droop = -0.004, bulb = 0.35, ala = 0.42, len = 0.0, bridgeW = 0.22 },
	Greek = { root = 0.02, hump = 0, scoop = 0, tip = 0.006, droop = 0.0, bulb = -0.2, ala = -0.05, len = 0.02, bridgeW = 0.0 },
	Boxer = { root = -0.016, hump = 0.006, scoop = 0, tip = -0.018, droop = 0.006, bulb = 0.3, ala = 0.3, len = -0.02, bridgeW = 0.4 },
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
	-- women: rounder malar fat pads (the cheeks), softer contours everywhere
	F.cheekFull = fv("cheekFull", 0) + (female and 0.4 or 0)
	local asymA = 0.3 + P.asym
	local seed = P.seed
	local function rnd(i)
		return (hash(i, seed + 977) - 0.5) * 2 -- [-1, 1]
	end
	F.rnd = rnd
	-- eyes
	F.eyeSize = fv("eyeSize", 0)
	F.eyeR = 0.06 * (1 + 0.05 * F.eyeSize) * (female and 1.09 or 1)
	F.eyeX = 0.16 + 0.014 * fv("eyeDist", 0) + (female and -0.004 or 0)
	F.eyeY = 0.0 + 0.008 * sh.len
	F.eyeDepth = fv("eyeDepth", 0.3, 0, 1)
	F.eyeZ = -0.36 + 0.014 * F.eyeDepth
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
	F.gUp = math.rad(11) * (1 - 0.65 * F.lidHeavy) + math.rad(2.5) * clamp((F.age - 35) / 25, 0, 1) -- visible upper lid (crease)
	F.gDn = math.rad(8)
	F.lidOut = 0.0062 -- upper lid outer surface (radius over the eyeball): a thin lid, no rolled rim
	F.lowOut = 0.0066 -- lower lid sits over the upper one where they meet
	F.lashes = fv("lashes", female and 0.9 or 0.25, 0, 1)
	-- brows
	F.browY = F.eyeY + 0.096 + 0.014 * fv("browHeight", 0) + 0.006 * fv("forehead", 0) + (female and 0.015 or 0)
	F.browAngle = fv("browAngle", 0)
	F.browThick = fv("browThick", 0)
	F.browRidge = P.browRidge * (female and 0.35 or 1)
	F.browStyle = f.browStyle
	F.browAsym = { [-1] = rnd(8) * 0.006 * asymA, [1] = rnd(9) * 0.006 * asymA }
	-- nose
	local nt = NOSE[f.noseType] or NOSE.Straight
	F.noseType = NOSE[f.noseType] and f.noseType or "Straight"
	F.nt = nt
	F.noseBreak = max(fv("noseBreak", 0, 0, 1), clamp(num(battle.nose, 0), 0, 1))
	local nlen = 1 + 0.12 * fv("noseLength", 0) + nt.len
	F.nasionY = F.eyeY + 0.048
	F.noseBaseY = F.nasionY - 0.262 * nlen * (female and 0.92 or 1)
	F.noseTipY = F.noseBaseY + 0.042
	F.noseW = (0.086 + 0.016 * fv("noseWidth", 0)) * (1 + nt.ala * 0.45) * (1 + 0.15 * F.noseBreak) * (female and 0.82 or 1) -- alar half width
	F.nostrilFlare = fv("nostrilFlare", 0.3, 0, 1)
	F.bridge = fv("noseBridge", 0) - (female and 0.2 or 0)
	F.noseTip = fv("noseTip", 0)
	F.noseDev = rnd(3) * 0.008 * asymA + F.noseBreak * 0.02 * (hash(303, seed) < 0.5 and -1 or 1)
	-- mouth
	F.mouthY = F.noseBaseY - 0.104 - 0.012 * sh.len
	F.mouthW = (0.126 + 0.012 * fv("mouthWidth", 0) + 0.004 * fv("lips", 0)) * (female and 0.93 or 1)
	F.lips = fv("lips", 0) + (female and 0.65 or 0)
	F.lipBow = fv("lipBow", female and 0.8 or 0.4, 0, 1)
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
		-- two peaks and a dip; both taper to a point at the corners; the lower lip is the fuller, ~1.25 x the
		-- upper at the centre), their protrusions, and the tapers
		F.lipShape = function(x)
			local xr = abs(x) / mW
			local t1 = max(0, 1 - xr ^ 1.6)
			local t2 = max(0, 1 - xr * xr)
			local hu = (0.028 + 0.007 * lipK) * (t1 ^ 0.7) * (1 + 0.22 * bow * bump(((xr - 0.32) / 0.24) ^ 2) - 0.16 * bow * bump((x / 0.018) ^ 2))
			local hl = (0.036 + 0.009 * lipK) * (t2 ^ 0.55)
			local pu = (0.026 + 0.008 * lipK) * t1 ^ 0.55
			local pl = (0.03 + 0.009 * lipK) * t2 ^ 0.5
			return hu, hl, pu, pl, t1, t2
		end
		F.lipH = function(x)
			local hu, hl = F.lipShape(x)
			return hu, hl
		end
	end
	-- chin / jaw (women: a narrower, slightly pointed chin, a higher softer jaw angle, a shorter face)
	F.chin = fv("chin", 0)
	F.chinProject = fv("chinProject", 0)
	F.chinCleft = fv("chinCleft", 0, 0, 1)
	F.chinY = -0.5 - sh.chinDrop - 0.01 * F.chin + sh.len * 0.5 + (female and 0.026 or 0)
	F.chinW = (0.085 + 0.016 * F.chin + 0.025 * sh.chinW) * (female and 0.7 or 1)
	F.jawW = (0.255 + 0.025 * fv("jawWidth", 0) + 0.03 * sh.jaw + rnd(5) * 0.006 * asymA) * (female and 0.8 or 1)
	F.jawDef = clamp(fv("jawDef", 0.5, 0, 1) * 0.6 + fv("jawAngle", female and 0.15 or 0.55, 0, 1) * 0.4 - 0.25 * sh.round, 0, 1) * (female and 0.45 or 1)
	F.gonionY = -0.39 + 0.02 * (1 - F.jawDef) + sh.len * 0.3 + (female and 0.015 or 0)
	-- cheeks
	F.cheek = fv("cheek", 0) + sh.cheek
	F.cheekH = fv("cheekHeight", 0) + (female and 0.2 or 0)
	F.round = sh.round
	-- ears
	F.earSize = 1 + 0.1 * fv("earSize", 0)
	F.cauli = max(fv("cauliflower", 0, 0, 1), clamp(num(battle.ears, 0), 0, 1))
	F.scars = type(battle.scars) == "table" and battle.scars or {}
	-- skin sliders (paint)
	F.wrinkles = max(fv("wrinkles", 0, 0, 1), clamp((F.age - 30) / 26, 0, 1) * 0.85)
	-- the neck (AnatomySkull.Neck: the skull's own, so the hair rests on it too) and its larynx
	F.neckR = P.neck.r
	F.neckZ = P.neck.z
	F.larynx = female and 0.25 or 1
	return F
end
Gen.Layout = layout

------------------------------------------------------------------------
-- The base field: the shared skull + the face skeleton the face sliders shape
------------------------------------------------------------------------
-- cubic Hermite over key rows { y, v1, v2, ... } sorted by descending y (tangents from the neighbours'
-- differences in y: C1 in y however unevenly the rows are spaced; a uniform Catmull-Rom kinks at rows with
-- unequal gaps, and a kinked slice table creases the whole face along that row); column col at height y
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
	local a, b = K[i], K[i + 1]
	local h = a[1] - b[1]
	local u = (a[1] - y) / h
	local m0, m1
	if i == 1 then
		m0 = b[col] - a[col]
	else
		local p0 = K[i - 1]
		m0 = (b[col] - p0[col]) / (p0[1] - b[1]) * h
	end
	if i + 1 == n then
		m1 = b[col] - a[col]
	else
		local p3 = K[i + 2]
		m1 = (p3[col] - a[col]) / (a[1] - p3[1]) * h
	end
	local u2, u3 = u * u, u * u * u
	return (2 * u3 - 3 * u2 + 1) * a[col] + (u3 - 2 * u2 + u) * m0 + (3 * u2 - 2 * u3) * b[col] + (u3 - u2) * m1
end

-- the lower face as horizontal contour slices (half width, front depth, squareness) cut by the jaw's
-- lower border, which slopes from the menton up to the gonion: one volume, one crisp jawline. Every column
-- of the table changes monotonically down the face (a slice value that bulges at one height would ring the
-- whole face with a ridge); the muzzle's forward curve round the mouth is relief, local to the mouth
local function lowerFaceSlices(F)
	local jw = F.jawW / 0.255 -- jaw width factor (1 = average man)
	local fem = F.female
	local cy = F.chinY
	local mY = F.mouthY
	local cwk = F.chinW / 0.085
	local cp = F.chinProject
	-- { y, half width, front z, front exponent }
	-- the face is a shield, not an egg: a broad, gently curved front that turns back at the cheekbones and
	-- the jaw (exponent ~3); women rounder (~2.7). Targets at the features { y, half width, front z, exponent }
	local nk = fem and 0.86 or 1
	local T = {
		{ F.eyeY - 0.07, 0.335 + 0.008 * F.cheek, -0.41, 3.0 * nk },
		{ F.noseBaseY - 0.01, lerp(0.31, 0.31 * jw, 0.3), -0.435, 2.85 * nk },
		{ mY, lerp(0.295, 0.295 * jw, 0.6) * (fem and 0.92 or 1.02), -0.44, 2.9 * nk },
		{ mY - 0.07, 0.28 * jw * (fem and 0.88 or 1.04), -0.444 - 0.005 * cp, 3.0 * nk },
		{ cy + 0.03, lerp(0.24, 0.255 * jw, 0.7) * (fem and 0.86 or 1.04), -0.448 - 0.014 * cp, 3.0 * nk },
		{ cy - 0.03, 0.17 * cwk * (fem and 0.92 or 1) + 0.04 * (jw - 1), -0.43 - 0.012 * cp, 3.2 * nk },
		{ cy - 0.09, 0.1, -0.34, 3.2 * nk },
	}
	-- resampled at evenly spaced rows (linear between the targets): the targets crowd on short noses / faces,
	-- and rows close together make the face narrow abruptly there (a crease right round the face)
	local K = {}
	local nR = 16
	local yA, yZ = T[1][1], T[#T][1]
	for r = 0, nR - 1 do
		local y = yA + (yZ - yA) * r / (nR - 1)
		local j = 1
		while j < #T - 1 and T[j + 1][1] > y do
			j += 1
		end
		local A, B = T[j], T[j + 1]
		local t = clamp((A[1] - y) / (A[1] - B[1]), 0, 1)
		K[r + 1] = { y, lerp(A[2], B[2], t), lerp(A[3], B[3], t), lerp(A[4], B[4], t) }
	end
	-- smoothed: a polyline through the targets bends only at them, and every bend is a crease running round
	-- the side of the face at that height (the shading's streaks); a few [1 2 1] passes spread each bend
	for _ = 1, 4 do
		local prev = { K[1][2], K[1][3], K[1][4] }
		for r = 2, nR - 1 do
			local cur = { K[r][2], K[r][3], K[r][4] }
			for c = 2, 4 do
				K[r][c] = 0.25 * prev[c - 1] + 0.5 * cur[c - 1] + 0.25 * K[r + 1][c]
			end
			prev = cur
		end
	end
	-- the jaw's lower border: menton -> gonion, then up the ramus behind the angle
	local zM, yM = -0.378 - 0.012 * cp, cy - 0.055
	local zG, yG = 0.03, F.gonionY
	local z0 = 0.03
	local edge = lerp(0.045, 0.018, F.jawDef) -- jawline roundness
	-- the jaw's lower border height at depth z (the cut below)
	local function border(z)
		local t = clamp((z - zM) / (zG - zM), 0, 1)
		if z > zG then
			return yG + (z - zG) * 3.5
		end
		return yM + (yG - yM) * (t ^ 0.85)
	end
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
			-- the back half: a short ellipse ending at the ramus (behind it the skull and the neck make the side
			-- of the head; two surfaces both covering it would crease where they meet)
			local bz = -dz / 0.16
			d = (sqrt(ax * ax + bz * bz) - 1) * min(a, 0.16)
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
	end, border
end

-- the neck's detail over the skull's column (AnatomySkull.Neck): the sternocleidomastoids winding from
-- behind the ears round to the notch, the larynx under the chin
local function neckDetail(F)
	local R, zc = F.neckR, F.neckZ
	local fem = F.female
	local scmR = fem and 0.02 or 0.028
	local lar = F.larynx
	-- the sternocleidomastoid's path on the column: from the mastoid (side-back) to the sternal head (front)
	local scm = {}
	for i = 0, 4 do
		local t = i / 4
		local ph = math.rad(lerp(112, 18, t))
		local y = lerp(-0.2, -0.86, t)
		local r = R - scmR * 0.6
		scm[i + 1] = { r * sin(ph), y, zc - r * cos(ph) / 0.97 }
	end
	local lz = zc - R / 0.97 + 0.014
	return function(x, y, z)
		local ax = abs(x)
		local d = 1
		for i = 1, 4 do
			local a, b = scm[i], scm[i + 1]
			d = min(d, sdCapsule(ax, y, z, a[1], a[2], a[3], b[1], b[2], b[3], scmR, scmR * (i == 4 and 0.8 or 1.05)))
		end
		-- the larynx (Adam's apple) under the chin
		if lar > 0 then
			d = min(d, sdE(x, y + 0.6, z - lz, 0.028, 0.05, 0.028) + 0.006 * (1 - lar))
		end
		return d
	end
end

local function baseField(F)
	local skull = Skull.Nominal(F.P)
	local lower = lowerFaceSlices(F)
	local neckCol, neckP = Skull.NeckSD, F.P.neck
	local neck = neckDetail(F)
	return function(x, y, z)
		local d = skull(x, y, z)
		local ax = abs(x)
		-- the lower face: below the eyes the shield's surface takes over from the skull's (above, the skull's
		-- own face mass rules; behind the jaw's ramus, the skull). An interpolation of the two fields, not a
		-- union: a smooth union swells wherever two surfaces run close, and the shield and the skull run close
		-- all down the side of the face (bands that shade as streaks). Under the jaw's border the shield is cut
		-- away: the neck takes over there
		if y < F.eyeY and z < 0.12 then
			local w = smoothstep(F.eyeY, F.eyeY - 0.11, y) * (1 - smoothstep(0.0, 0.12, z))
			if w > 0 then
				d = lerp(d, lower(x, y, z), w)
			end
		end
		if y < 0 and y > -0.95 then
			-- the neck column (the skull's own; in front the shield replaced the skull's field), a soft angle
			-- under the jaw, then its muscles and the larynx
			d = smin(d, neckCol(neckP, x, y, z), 0.06)
			d = smin(d, neck(x, y, z), 0.04)
		end
		return d
	end
end

------------------------------------------------------------------------
-- Relief: the face's soft-tissue features as displacements along the ray (nominal studs, + = out)
------------------------------------------------------------------------
-- a dome: 1 at the centre, 0 at q2 >= 1; round in section ((1 - r^2)^1.5: a broad, ball-like top, unlike
-- bump's bell) with a smooth foot (zero slope at the edge): tip lobules, alae
local function dome(q2)
	if q2 >= 1 then
		return 0
	end
	local w = 1 - q2
	return w * sqrt(w)
end

-- smooth union of heights >= 0 (a 4-norm: a sum would swell where masses overlap, a hard max would crease)
local function hmax(a, b, c, d, e)
	return (a ^ 4 + b ^ 4 + c ^ 4 + d ^ 4 + e ^ 4) ^ 0.25
end

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
	local femK = fem and 0.9 or 1
	local ridgeK = fem and 0.35 or 1
	local NB = F.noseInfo.box
	local faceOnly = F.face
	-- the orbits: deep under the brow, shallow under the eye (the lower lid and the cheek sit near the cornea)
	local orbitUp = 0.012 + 0.01 * F.eyeDepth + 0.006 * gaunt
	local orbitDn = 0.006 + 0.004 * F.eyeDepth + 0.006 * gaunt
	return function(x, y, z)
		local D = 0
		local ax = abs(x)
		local front = -z -- how far forward (face points have front ~0.3 .. 0.6)
		if front < 0.05 then
			-- the back half of the head: nothing below the skull
			return 0
		end
		------------------------------------------------ brow: the glabella and a ridge arching over each orbit
		if y > browY - 0.07 and y < browY + 0.1 and ax < 0.32 then
			local hG = (0.006 + 0.014 * ridge) * ridgeK
			local gq = (x / 0.07) ^ 2 + ((y - browY + 0.004) / 0.05) ^ 2
			if gq < 1 then
				D += hG * bump(gq)
			end
			-- the supraorbital margin: strongest over the inner half of the eye, fading toward the temple
			local u = (ax - 0.03) / 0.26
			if u > -0.1 and u < 1.1 then
				local ry = browY - 0.008 + 0.01 * sin(clamp(u, 0, 1) * pi) - 0.02 * max(0, u - 0.7) ^ 2
				local dy = y - ry
				local along = bump(((u - 0.32) / 0.75) ^ 2)
				local h = (0.005 + 0.02 * ridge) * ridgeK * along
				-- soft into the forehead above, a rounded edge over the orbit below
				local sy = dy > 0 and dy / 0.055 or -dy / 0.026
				D += h * bump(sy * sy)
			end
		end
		------------------------------------------------ orbits: the recess the eyes and lids sit in
		for side = -1, 1, 2 do
			local e = F.eye[side]
			local dx2 = (x - e.x) * side -- + = lateral
			local dy2 = y - e.y - 0.006
			if dy2 > -0.08 and dy2 < 0.09 and dx2 > -0.11 and dx2 < 0.13 then
				local rx = dx2 < 0 and 0.085 or 0.105
				local up = dy2 > 0
				local q = (dx2 / rx) ^ 2 + (dy2 / (up and 0.075 or 0.058)) ^ 2
				if q < 1 then
					D -= (up and orbitUp or orbitDn) * bump(q)
				end
			end
		end
		------------------------------------------------ nasion: the dip between the brow and the bridge
		do
			local q = (x / 0.07) ^ 2 + ((y - nasY - 0.008) / 0.032) ^ 2
			if q < 1 then
				D -= 0.012 * bump(q)
			end
		end
		------------------------------------------------ cheeks: the malar fat pads, the buccal hollow, jowls
		do
			-- the cheek's "apple" under the eye, beside the nose (fuller young / female / fat)
			local cyy = eyeY - 0.105 + 0.018 * cheekH
			local q = ((ax - 0.16) / 0.085) ^ 2 + ((y - cyy) / 0.065) ^ 2
			if q < 1 then
				D += (0.006 + 0.008 * max(cheekFull, 0) + 0.012 * fat - 0.004 * gaunt) * bump(q)
			end
			-- the cheekbone's prominence (on top of the zygomatic body in the base field)
			local zq = ((ax - (0.245 + 0.01 * cheek)) / 0.09) ^ 2 + ((y - (eyeY - 0.085 + 0.02 * cheekH)) / 0.06) ^ 2
			if zq < 1 then
				D += (0.006 + 0.01 * cheek + 0.008 * gaunt) * bump(zq)
			end
			-- buccal hollow under the cheekbone (lean / gaunt) or full cheeks (fat)
			local hy = y - (mY + 0.07)
			local hq = ((ax - 0.235) / 0.085) ^ 2 + (hy / 0.07) ^ 2
			if hq < 1 then
				local fill = (0.02 * fat + 0.012 * max(cheekFull, 0) + 0.006 * F.round) - (0.014 * gaunt + 0.008 * max(-cheekFull, 0))
				D += fill * bump(hq)
			end
		end
		------------------------------------------------ mouth: the muzzle, lips, philtrum, corners
		do
			local ml = mY + mt * x + curve * x * x
			local my = y - ml
			-- the muzzle: the teeth push the lips and the skin round them forward (local to the mouth: no ring)
			local uq = (x / 0.16) ^ 2 + ((my - 0.022) / 0.13) ^ 2
			if uq < 1 then
				D += 0.024 * bump(uq)
			end
			if my > -0.1 and my < (baseY - mY) + 0.01 and ax < mW + 0.07 then
				local xr = ax / mW -- 0 centre, 1 corner
				-- vermilion heights (the upper lip with its cupid's bow, the fuller lower lip) and protrusions
				local Hu, Hl, pu, pl, taper = F.lipShape(x)
				if my >= 0 then
					local h = my / max(Hu, 0.003)
					if h <= 1 and xr < 1 then
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
					if h <= 1 and xr < 1 then
						local prof = sqrt(max(0, 1 - ((h - 0.45) / 0.6) ^ 2))
						-- the lower lip's centre sits a little forward of its sides
						D += pl * (0.45 + 0.55 * prof) + 0.004 * (1 - xr * xr)
					else
						-- below the lower lip: down into the mentolabial sulcus
						local dn = (-my - Hl) / 0.03
						D += ((0.032 + 0.009 * lips) * 0.45 + 0.004 * (1 - min(xr, 1) ^ 2)) * (1 - smoothstep(0.5, 1.5, xr)) * (1 - smoothstep(0, 1, dn))
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
					local colw = 0.015 + 0.006 * hp
					local g = bump((x / colw) ^ 2)
					local c = bump(((ax - colw) / 0.008) ^ 2)
					local fade = smoothstep(0.25, 0.5, hp) * (1 - smoothstep(0.85, 1.0, hp)) + smoothstep(0.05, 0.3, hp) * (1 - smoothstep(0.3, 0.5, hp))
					D += (-0.0035 * g + 0.002 * c) * fade
				end
				-- mouth corners: the lips end tucked into a small hollow (never flush); the modiolus bulge beside it
				local cq = ((ax - mW) / 0.02) ^ 2 + (my / 0.013) ^ 2
				if cq < 1 then
					D -= 0.011 * bump(cq)
				end
				local mq = ((ax - mW - 0.024) / 0.026) ^ 2 + ((my + 0.004) / 0.032) ^ 2
				if mq < 1 then
					D += 0.004 * bump(mq)
				end
			end
		end
		------------------------------------------------ nasolabial folds (age, fat): a soft crease, the cheek over it
		do
			-- from beside the ala down / out to beside the mouth corner
			local x0, y0 = nW + 0.014, baseY + 0.02
			local x1, y1 = mW + 0.03, mY - 0.03
			local vx, vy = x1 - x0, y1 - y0
			local l2 = vx * vx + vy * vy
			local u = clamp(((ax - x0) * vx + (y - y0) * vy) / l2, 0, 1)
			local dx, dy = ax - x0 - vx * u, y - y0 - vy * u
			local dd = sqrt(dx * dx + dy * dy)
			if dd < 0.05 then
				-- signed: + on the cheek side (lateral / above)
				local sgn = (dx * vy - dy * vx) < 0 and 1 or -1
				local depth = (0.003 + 0.008 * F.wrinkles + 0.006 * fat) * (1 - 0.4 * u) * smoothstep(0, 0.15, u)
				if sgn > 0 then
					D += depth * 1.1 * bump(((dd - 0.02) / 0.02) ^ 2) -- zero on the fold line itself
				end
				D -= depth * 0.6 * bump((dd / 0.014) ^ 2)
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
				D -= 0.008 * bump(sq)
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
		------------------------------------------------ forehead: the frontal eminences (rounder on women)
		do
			if y > browY + 0.02 and y < 0.45 then
				local q = ((ax - 0.11) / 0.1) ^ 2 + ((y - 0.24) / 0.09) ^ 2
				if q < 1 then
					D += (fem and 0.008 or 0.004) * bump(q)
				end
			end
		end
		------------------------------------------------ the nose is exact (a solid in the field): no relief on it
		if D ~= 0 and x > NB[1] and x < NB[2] and y > NB[3] and y < NB[4] then
			-- how far the point stands out of the face without a nose (on the nose: its height)
			local g = faceOnly(x, y, z)
			if g > 0.002 then
				D *= 1 - smoothstep(0.002, 0.014, g)
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
		n += 1
	end
	-- a field sample is a few microseconds (the nose's box more): ~2 units each, so AnatomyClient's tick
	-- comes round well inside its frame budget
	MeshKit.Step(2 * n + 10)
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
-- The nose: a solid (signed distance) merged into the base field, so every ray family meets the same nose:
-- the dorsum (a rounded ridge along the profile), the tip lobule, the alae, the columella and the sill under
-- it, the nostrils carved up into it from below. The relief fades out over it (reliefFn): its shape is exact
-- wherever it is sampled, from the front (the grid) or from inside and below (the nose patch)
------------------------------------------------------------------------
local function noseField(F, face)
	local nt = F.nt
	local fem = F.female
	local nasY, baseY, tipY = F.nasionY, F.noseBaseY, F.noseTipY
	local brk = F.noseBreak
	local dev = F.noseDev
	local nW = F.noseW
	-- the face without a nose at the midline: its depth by height (a table, Catmull-Rom between samples)
	local yLo, yHi = baseY - 0.07, nasY + 0.09
	local nS = 16
	local ZS = table.create(nS + 1)
	for i = 0, nS do
		local y = yLo + (yHi - yLo) * i / nS
		ZS[i + 1] = ZA - hit(face, 0, y, ZA, 0, 0, -1, 0.42)
	end
	local function zf(y)
		local u = clamp((y - yLo) / (yHi - yLo) * nS, 0, nS - 1e-6)
		local i = floor(u)
		local t = u - i
		local p0, p1, p2, p3 = ZS[max(i, 1)], ZS[i + 1], ZS[i + 2], ZS[min(i + 3, nS + 1)]
		return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t)
	end
	local tipProj = (0.115 + nt.tip + 0.008 * F.bridge - 0.022 * brk) * (fem and 0.92 or 1)
	local tipUp = F.noseTip * 0.012 - nt.droop
	local hRoot = 0.008 + nt.root + 0.008 * F.bridge
	local hump = nt.hump + 0.01 * brk
	local scoop = nt.scoop
	local bulb = clamp(0.4 + nt.bulb, 0, 1.2)
	local bridgeW = nt.bridgeW + 0.3 * brk
	local flare = F.nostrilFlare
	local femK = fem and 0.88 or 1
	local yT = tipY + tipUp - 0.004 -- the tip's most forward point
	local function devAt(y)
		return dev * clamp((nasY - y) / (nasY - tipY), 0, 1.2)
	end
	local zT = zf(yT) - tipProj
	-- the dorsum: its height over the face and the half width of its base by height; the cross-section is a bell
	-- (1 - u^2)^2: a rounded ridge, flanks turning concave into the face. At the tip it stays a little behind the
	-- lobule (the supratip break); under the tip it retreats into the base (the columella, the sill and the alae
	-- make the underside)
	local wK = (1 + 0.6 * bridgeW) * femK
	-- rows: y, height over the face, base half width, cross-section exponent (2: a ridge; toward the base the
	-- sidewalls fill out into the wings: a broad mound)
	local K = {
		{ nasY + 0.045, -0.014, 0.03 * wK, 2 },
		{ nasY, hRoot, 0.032 * wK, 2 },
		{ lerp(nasY, yT, 0.45), lerp(hRoot, tipProj, 0.5) + hump, 0.046 * wK, 2 },
		{ lerp(nasY, yT, 0.8), tipProj * 0.87 - scoop, 0.062 * wK, 1.9 },
		{ yT + 0.013, tipProj * 0.93, 0.07 * wK, 1.8 },
		{ yT - 0.006, tipProj * 0.86, 0.074 * wK, 1.7 },
		-- under the tip the ridge sinks into the face (inside the lower nose's block: it makes the lower nose)
		{ yT - 0.035, tipProj * 0.12, 0.076 * wK, 1.6 },
		{ yT - 0.06, -0.03, 0.076 * wK, 1.6 },
	}
	-- tabulated (fine, linear): the field is evaluated a great many times
	local nR = 400
	local rY0, rY1 = K[#K][1] - 0.01, K[1][1] + 0.01
	local RH, RB, RZ, RP = table.create(nR + 1), table.create(nR + 1), table.create(nR + 1), table.create(nR + 1)
	for i = 0, nR do
		local y = rY0 + (rY1 - rY0) * i / nR
		RH[i + 1], RB[i + 1], RP[i + 1] = keyed(K, y, 2), keyed(K, y, 3), keyed(K, y, 4)
		RZ[i + 1] = zf(y)
	end
	local rK = nR / (rY1 - rY0)
	local function ridge(x, y, z)
		local u = clamp((y - rY0) * rK, 0, nR - 1e-6)
		local i = floor(u)
		local t = u - i
		local H = RH[i + 1] + (RH[i + 2] - RH[i + 1]) * t
		local B = RB[i + 1] + (RB[i + 2] - RB[i + 1]) * t
		local pE = RP[i + 1] + (RP[i + 2] - RP[i + 1]) * t
		local zface = RZ[i + 1] + (RZ[i + 2] - RZ[i + 1]) * t
		local ax = abs(x) / B
		-- the slopes of the table along y (the surface's y gradient joins the normalisation)
		local dH, dB, dZ = (RH[i + 2] - RH[i + 1]) * rK, (RB[i + 2] - RB[i + 1]) * rK, (RZ[i + 2] - RZ[i + 1]) * rK
		local h, g, gy
		if ax < 1 then
			-- the base sits a little under the face (no smooth-union swelling along its foot)
			local w = 1 - ax * ax
			local wp = w ^ pE
			local wp1 = wp / max(w, 1e-6)
			h = H * wp - 0.012 * (1 - w)
			g = -2 * pE * H * wp1 * ax / B - 0.024 * ax / B -- dh/dx (for |x|)
			gy = dH * wp + (2 * pE * H * wp1 + 0.024) * ax * ax / B * dB
		else
			-- past its base the ridge dives under the face
			h = -0.012 - (ax - 1) * 0.03
			g = -0.03 / B
			gy = 0.03 * ax / B * dB
		end
		local sy = dZ - gy
		return (zface - h - z) / sqrt(1 + g * g + sy * sy)
	end
	-- the lower nose: a rounded triangular block (the basal view: the tip in front, the alar bases behind) whose
	-- underside rises toward the tip, a lobule fused onto its front, the columella under it; displacements
	-- (outward +) swell the alar lobules out of its sides, cut the alar groove along their upper border and the
	-- nostrils' pockets into the underside either side of the columella
	local Lrx, Lry, Lrz = (0.027 + 0.008 * bulb) * femK, 0.022 + 0.004 * bulb, 0.028
	local Ly = yT - 0.003
	local Lx, Lz = devAt(Ly), zT + Lrz
	-- the block, in (x, h = height over the face plane at the midline, y): triangle corners (0, hTip), (+-W, hB)
	local W = nW * 0.98
	local hB = 0.004
	local hTip = tipProj - 0.028
	local rr = 0.012 -- edge rounding
	local yBot0 = baseY + 0.004 -- the underside's height at the face
	local ySl = (yT - 0.024 - yBot0) / max(hTip, 0.02) -- its rise toward the tip
	local yTop = yT - 0.012
	-- the triangle's edges (inward normals), for an exact-enough distance in the basal plane
	local ex1, eh1 = W, hB - hTip -- from the tip corner to (W, hB)
	local el = sqrt(ex1 * ex1 + eh1 * eh1)
	local n1x, n1h = -eh1 / el, ex1 / el -- outward normal of the right edge (pointing +x, +h)
	if n1x < 0 then
		n1x, n1h = -n1x, -n1h
	end
	-- the basal outline's corners rounded (r2: the alar bases are round, not points)
	local r2 = 0.02
	local function block(x, y, h)
		-- (a smooth |x|: no crease down the front)
		local ax = sqrt(x * x + 0.0001)
		-- 2D: inside < 0 (the two slanted edges and the back edge h = hB), shrunk by r2 then grown back
		local d1 = ax * n1x + (h - hTip) * n1h + r2
		local d2 = hB - h + r2
		local d2D
		if d1 > 0 and d2 > 0 then
			-- outside both: the corner region (exact enough: the larger of the two, rounded)
			d2D = sqrt(d1 * d1 + d2 * d2) - r2
		else
			d2D = max(d1, d2) - r2
		end
		-- vertical: from the sloped underside to the top
		-- (the alar rims sit a little higher than the columella: the underside rises toward the sides)
		local yb = yBot0 + ySl * max(h, 0) + 0.006 * min(ax / W, 1.2) ^ 2
		local dv = max(yb - y, y - yTop)
		local ox, oy = max(d2D + rr, 0), max(dv + rr, 0)
		return sqrt(ox * ox + oy * oy) + min(max(d2D + rr, dv + rr), 0) - rr
	end
	-- the alae: swellings on the block's sides, low and toward the back (the alar lobules), long along the
	-- side's edge (they wrap the nostrils), flat across it
	local Ay = baseY + 0.015
	local ef = 0.68 -- along the edge from the tip corner
	local Ax, Ah = W * ef, hTip + (hB - hTip) * ef
	local Az0 = Ah -- height over the face (z = zf(y) - h)
	local eux, euh = ex1 / el, eh1 / el -- along the edge (tip -> back corner)
	local Adev = devAt(Ay)
	local aA = (0.009 + 0.005 * flare + 0.008 * max(nt.ala, 0)) * femK
	local Ra, Rv, Rn = 0.036, 0.016, 0.022
	-- the columella (from under the lobule back to the subnasale)
	local C0x, C0y, C0z = devAt(yT - 0.017), yT - 0.017, zT + 0.02
	local C1x, C1y, C1z = devAt(baseY) * 0.5, baseY + 0.004, zf(baseY) - 0.007
	-- the alar groove: from the top of the alar crease forward toward the tip
	local G0x, G0y, G0z = nW + 0.002, baseY + 0.034, zf(baseY + 0.034) - 0.006
	local G1x, G1y, G1z = 0.03 * femK, yT - 0.006, zT + 0.034
	local gdx, gdy, gdz = G1x - G0x, G1y - G0y, G1z - G0z
	local gl2 = gdx * gdx + gdy * gdy + gdz * gdz
	-- the nostrils: teardrops either side of the columella, front ends turned in, lying along the underside
	local gam = math.rad(22)
	local sg, cg = sin(gam), cos(gam)
	local zBack, zFront = zf(baseY) - 0.014, zT + 0.026
	local Nrx, Nry = (0.012 + 0.003 * flare) * femK, 0.01
	local Nrz = clamp((zBack - zFront) * 0.5 / cg, 0.01, (0.026 + 0.004 * flare) * femK)
	local Nz = (zBack + zFront) * 0.5
	local st, ct = sin(math.atan(ySl)), cos(math.atan(ySl))
	local Ny = yBot0 + ySl * (zf(baseY) - Nz) - 0.002
	local Nx = 0.0105 + Nrx * 0.9
	local aN = 0.013
	-- the box the nose can touch (outside it the field is the face's alone)
	local bx0, bx1 = -nW - 0.05 + min(dev, 0) * 1.2, nW + 0.05 + max(dev, 0) * 1.2
	local by0, by1 = baseY - 0.045, nasY + 0.05
	local function body(x, y, z, zfy)
		local dvy = devAt(y)
		local nx = x - dvy
		zfy = zfy or zf(y)
		local d = ridge(nx, y, z)
		d = smin(d, block(nx, y, zfy - z), 0.016)
		d = smin(d, sdE(x - Lx, y - Ly, z - Lz, Lrx, Lry, Lrz), 0.016)
		local ax = x - Adev
		local s = ax < 0 and -1 or 1
		local sx = ax * s
		local D = 0
		-- the ala (in the edge's frame: along, vertical, normal)
		local hh = zfy - z
		local qa = (sx - Ax) * eux + (hh - Az0) * euh
		local qn = (sx - Ax) * n1x + (hh - Az0) * n1h
		local q = (qa / Ra) ^ 2 + ((y - Ay) / Rv) ^ 2 + (qn / Rn) ^ 2
		if q < 1 then
			D += aA * bump(q)
		end
		-- the groove (distance to its segment)
		local px, py, pz = sx - G0x, y - G0y, z - G0z
		local t = clamp((px * gdx + py * gdy + pz * gdz) / gl2, 0, 1)
		local ex, ey, ez = px - gdx * t, py - gdy * t, pz - gdz * t
		q = (ex * ex + ey * ey + ez * ez) / (0.008 * 0.008)
		if q < 1 then
			D -= 0.003 * bump(q) * sin(pi * clamp(t * 1.15, 0, 1))
		end
		-- the nostrils
		local dx, dz = sx - Nx, z - Nz
		local lb = dx * cg + dz * sg
		local la = -dx * sg + dz * cg
		local dy = y - Ny
		q = (lb / Nrx) ^ 2 + ((la * st + dy * ct) / Nry) ^ 2 + ((la * ct - dy * st) / Nrz) ^ 2
		if q < 1 then
			D -= aN * bump(q)
		end
		return d - D, s, ax
	end
	local function field(x, y, z)
		-- the box: the nose's reach (the ridge runs on behind the face: never past it into the head)
		if x < bx0 or x > bx1 or y < by0 or y > by1 then
			return face(x, y, z)
		end
		local zfy = zf(y)
		if z > zfy + 0.05 then
			return face(x, y, z)
		end
		local d = body(x, y, z, zfy)
		-- the union with the face: crisp at the alar creases and the subnasale, a broad blend up the sidewalls
		-- (the nose flows into the cheeks and the inner corners of the eyes, it is not stuck on)
		local kF = 0.008 + 0.02 * smoothstep(baseY + 0.03, baseY + 0.075, y)
		-- the face matters only within the union's reach of the body: in front of the face by more than that
		-- (0.95 x the gap at the midline bounds the face's distance from below in this box) it is the body's
		if 0.95 * (zfy - z) <= d + kF + 0.004 then
			d = smin(face(x, y, z), d, kF)
		end
		return d
	end
	F.noseInfo = {
		zf = zf, yT = yT, zT = zT, tipProj = tipProj, devAt = devAt, box = { bx0, bx1, by0, by1 },
		-- the patch's ray centre: inside the lower nose, above the tip and behind it
		C = { devAt(yT + 0.03), yT + 0.03, zT + 0.045 },
		tip = { devAt(yT), yT, zT },
		nostril = { x = Nx, y = Ny, z = Nz, rx = Nrx, ry = Nry, rz = Nrz, c = cg, s = sg, tc = ct, ts = st, dev = devAt(Ny) },
		ala = { x = Ax, y = Ay, z = zf(Ay) - Az0, rx = Ra * 0.6, ry = Rv, rz = Ra, dev = Adev },
		baseY = baseY,
	}
	return field
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
local function rowList(F, q, partial)
	q *= Gen.DENSITY
	local rows = {}
	-- the crown: enough rings that the dome's silhouette stays round at every level (crowded a little toward
	-- the band, where the forehead and the temples turn)
	local nTop = max(7, floor(14 * q + 0.5))
	for i = nTop - 1, 1, -1 do
		rows[#rows + 1] = { kind = "top", a = (pi / 2) * (i / nTop) ^ 0.85 }
	end
	local yT, yB = 0.22, -0.4
	local eY, bY = F.eyeY, F.browY
	local mY = F.mouthY
	-- the eyes and the mouth are patches of their own (headSurface): the rows round them only need to meet
	-- the patches' outer rings; the nose keeps tight rows (its wings and nostrils)
	local keys = {
		{ yT, 0.026 }, { bY + 0.03, 0.018 }, { eY + 0.05, 0.015 }, { eY - 0.05, 0.015 },
		{ F.noseTipY + 0.035, 0.015 }, { F.noseBaseY - 0.002, 0.013 },
		{ mY + 0.06, 0.013 }, { mY - 0.06, 0.013 },
		{ yB, 0.018 },
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
	-- a row between the nose patch and the mouth patch (both zip to it: it keeps the two holes apart)
	do
		local yGap = F.noseBaseY - 0.024
		local bi = nil
		for i = 1, #band - 1 do
			if band[i] >= yGap and band[i + 1] < yGap then
				bi = i
				break
			end
		end
		if bi then
			local gu, gd = band[bi] - yGap, yGap - band[bi + 1]
			if gu < 0.006 then
				band[bi] = yGap
			elseif gd < 0.006 then
				band[bi + 1] = yGap
			else
				table.insert(band, bi + 1, yGap)
			end
		end
	end
	-- the nose's rows get extra columns down the middle (bandColumns); between them, partial rows across the
	-- nose only (its underside, the wings and the nostrils want rows a few thousandths apart; rows round the
	-- whole head that tight would spend the budget on the back of the head)
	local n0, n1 = F.noseBaseY - 0.02, F.nasionY + 0.03
	local z0, z1 = F.noseBaseY - 0.012, F.noseTipY + 0.022
	local target = 0.0052 / max(q, 0.55)
	for bi, yy in ipairs(band) do
		rows[#rows + 1] = { kind = "band", y = yy, nose = q >= 0.45 and yy >= n0 and yy <= n1 }
		local yn = band[bi + 1]
		if partial and yn and yn < z1 and yy > z0 then
			local gap = yy - yn
			local k = floor(gap / target + 0.5) - 1
			for i = 1, k do
				local yp = yy - gap * i / (k + 1)
				if yp <= z1 and yp >= z0 then
					rows[#rows + 1] = { kind = "band", y = yp, nose = true, partial = true }
				end
			end
		end
	end
	-- chin, under-jaw and the neck down to the junction (y ~-0.62), then the rows closing the neck's end
	-- inside the torso
	local nBot = max(4, floor(11 * q + 0.5))
	for i = 1, nBot do
		rows[#rows + 1] = { kind = "bot", a = math.rad(46) * (i / nBot) ^ 1.05 }
	end
	for _, aDeg in ipairs({ 58, 70, 82 }) do
		rows[#rows + 1] = { kind = "bot", a = math.rad(aDeg) }
	end
	return rows, yT, yB
end

local function rowApproxY(row, yT, yB)
	if row.kind == "band" then
		return row.y
	elseif row.kind == "top" then
		return yT + 0.4 * sin(row.a)
	end
	return yB - 0.3 * sin(row.a)
end

-- the column density round a row (th: the column angle) and its column count
local function rowDensity(F, row, yApprox)
	-- feature weights vary smoothly from row to row (an abrupt change skews the stitched triangles)
	local eyeW = exp(-((yApprox - F.eyeY) / 0.06) ^ 2)
	local mouthW = exp(-((yApprox - F.mouthY) / 0.05) ^ 2)
	local mid = (F.nasionY + F.noseBaseY) * 0.5
	local noseW = exp(-((yApprox - mid) / ((F.nasionY - F.noseBaseY) * 0.6)) ^ 4)
	local faceW = 1
	local capK = 1
	if row.kind == "top" then
		faceW = cos(row.a) ^ 1.5
		capK = max(0.55, cos(row.a) ^ 0.7)
	elseif row.kind == "bot" then
		faceW = cos(row.a) ^ 1.2
		capK = 0.5 + 0.5 * cos(row.a)
	end
	-- the back and sides keep a fair share: their silhouette must stay round too
	return function(th)
		local df = abs(((th - pi / 2 + pi) % TAU) - pi)
		local r = 0.3 + 0.8 * exp(-(df / 0.9) ^ 2) + 0.7 * faceW * exp(-(df / 0.5) ^ 2)
		r += 0.55 * eyeW * exp(-((df - 0.42) / 0.18) ^ 2)
		r += mouthW * (0.6 * exp(-((df - 0.3) / 0.12) ^ 2) + 0.9 * exp(-(df / 0.16) ^ 2))
		r += 1.5 * noseW * exp(-(df / 0.12) ^ 2)
		return r
	end, faceW, capK
end

local function cdfOf(rho, N)
	local cdf = table.create(N + 1, 0)
	local acc = 0
	for i = 1, N do
		acc += rho(1.5 * pi + TAU * (i - 0.5) / N)
		cdf[i + 1] = acc
	end
	return cdf, acc
end

-- the band ray's angle offset from the front that reaches x (studs, at the face's depth ~0.44 in front)
local function thetaThroughFront(x)
	local k2 = GA * GA - GB * GB
	local qz = -0.44 - ZA
	local th = 2.5 * pi - math.asin(clamp(x / 0.33, -0.95, 0.95))
	for _ = 1, 10 do
		local c, sn = cos(th), sin(th)
		local f = k2 * sn * c - GA * x * sn - GB * qz * c
		local fp = k2 * (c * c - sn * sn) - GA * x * c + GB * qz * sn
		if abs(fp) < 1e-9 then
			break
		end
		th -= clamp(f / fp, -0.25, 0.25)
	end
	return abs(2.5 * pi - th)
end

-- the band's columns: one set for every band row (aligned columns stitch into a regular strip of quads; rows
-- each with their own columns zigzag, and the normals interpolated over the zigzag band into streaks along the
-- rows), with extra columns down the middle for the nose's rows (a superset: still aligned)
local function bandColumns(F, q)
	q *= Gen.DENSITY
	local rho = function(th)
		local df = abs(((th - pi / 2 + pi) % TAU) - pi)
		return 0.42 + 0.7 * exp(-(df / 0.9) ^ 2) + 0.45 * exp(-(df / 0.5) ^ 2)
	end
	local N = 360
	local cdf, total = cdfOf(rho, N)
	local n = max(16, floor(46 * q * (total / N) + 0.5))
	local C0 = table.create(n + 1)
	local k = 1
	for j = 0, n do
		local target = total * j / n
		while k < N and cdf[k + 1] < target do
			k += 1
		end
		local c0, c1 = cdf[k], cdf[k + 1]
		local frac = c1 > c0 and (target - c0) / (c1 - c0) or 0
		C0[j + 1] = 1.5 * pi + TAU * ((k - 1) + frac) / N
	end
	C0[1], C0[n + 1] = 1.5 * pi, 3.5 * pi
	-- the nose's rows: twice the columns over the face, four times over the nose itself (its ridge and
	-- sidewalls turn within a few hundredths: coarse columns facet them and crease their foot)
	local C1 = {}
	for j = 1, n + 1 do
		C1[#C1 + 1] = C0[j]
		if j <= n then
			local a, b = C0[j], C0[j + 1]
			local m = (a + b) * 0.5
			local df = abs(((m - pi / 2 + pi) % TAU) - pi)
			if df < 0.13 * max(q, 0.6) / max(q, 0.6) and q >= 0.6 then
				for f = 1, 3 do
					C1[#C1 + 1] = a + (b - a) * f / 4
				end
			elseif df < 0.45 then
				C1[#C1 + 1] = m
			end
		end
	end
	-- the partial rows' span: between the C0 columns nearest the nose's sides (x ~ +-0.15 at the face), as
	-- indices into C1 (every C0 column is in C1, so full rows have vertices there too)
	local span = thetaThroughFront(0.15)
	local lo, hi = 2.5 * pi - span, 2.5 * pi + span
	local ia, ib = 1, #C1
	local bestA, bestB = huge, huge
	for j, th in ipairs(C1) do
		local isC0 = table.find(C0, th) ~= nil
		if isC0 then
			if abs(th - lo) < bestA then
				bestA, ia = abs(th - lo), j
			end
			if abs(th - hi) < bestB then
				bestB, ib = abs(th - hi), j
			end
		end
	end
	return C0, C1, ia, ib
end

-- column counts per row (N: CDF resolution), then evened out: neighbouring rows differ by at most 4 columns
-- (bigger jumps stitch into long slivers that skew the shading and the texture)
local function rowCounts(F, rows, q, yT, yB, N)
	local C0, C1, ia, ib = bandColumns(F, q)
	q *= Gen.DENSITY
	local counts = {}
	for r, row in ipairs(rows) do
		if row.partial then
			counts[r] = ib - ia
		elseif row.kind == "band" then
			counts[r] = (row.nose and #C1 or #C0) - 1
		else
			-- the caps: the crown's rings keep enough columns that the dome's outline stays round
			local rho, faceW, capK = rowDensity(F, row, rowApproxY(row, yT, yB))
			local _, total = cdfOf(rho, N)
			local floorN = row.kind == "top" and floor(lerp(12, 30, cos(row.a)) * min(1, q / 0.6) + 0.5) or 10
			counts[r] = max(floorN, 10, floor(lerp(32, 42, faceW) * q * capK * (total / N) + 0.5))
		end
	end
	for _ = 1, 2 do
		for r = 2, #rows do
			if rows[r].kind ~= "band" then
				counts[r] = max(counts[r], counts[r - 1] - 4)
			end
		end
		for r = #rows - 1, 1, -1 do
			if rows[r].kind ~= "band" then
				counts[r] = max(counts[r], counts[r + 1] - 4)
			end
		end
	end
	return counts
end

local function columnsFor(F, row, n, yApprox, N)
	local rho = rowDensity(F, row, yApprox)
	N = N or 180
	local cdf, total = cdfOf(rho, N)
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
-- triangles of the head grid at density q (a coarse column CDF: an estimate within a few %)
local function gridTris(F, q, partial)
	local rows, yT, yB = rowList(F, q, partial)
	local counts = rowCounts(F, rows, q, yT, yB, 48)
	local C0, C1, ia, ib = bandColumns(F, q)
	local spanC0 = 0
	for _, th in ipairs(C0) do
		if th >= C1[ia] - 1e-9 and th <= C1[ib] + 1e-9 then
			spanC0 += 1
		end
	end
	local nR = #rows
	local function nv(r)
		return (r == 0 or r == nR + 1) and 1 or counts[r] + 1
	end
	local total = 0
	local r = 0
	while r <= nR do
		local nxt, k = r + 1, 0
		while nxt <= nR and rows[nxt].partial do
			nxt += 1
			k += 1
		end
		if k == 0 then
			total += (nv(r) - 1) + (nv(nxt) - 1)
		else
			local np = ib - ia + 1
			local sA = rows[r].nose and np or spanC0
			local sC = rows[nxt].nose and np or spanC0
			total += (sA - 1) + (np - 1) + (k - 1) * 2 * (np - 1) + (np - 1) + (sC - 1)
			total += (nv(r) - sA) + (nv(nxt) - sC) + 2 * k
		end
		r = nxt
	end
	-- (about half a millisecond: the rows' and columns' layouts)
	MeshKit.Step(120)
	return total
end
-- the patches' (eyes, mouth) net triangles over the grid's: their rings and zips minus the grid triangles they
-- replace (measured over the sample looks at the usual densities)
local PATCH_TRIS = { full = 1350, medium = 620, low = 0 }

-- position (or any 3-vector per vertex: arr, default the positions) on grid row r at texture u (linear
-- between the row's columns)
local function rowPointAt(m, r, u, arr)
	local G = m.gridRows
	local P, U = arr or m.P, m.U
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

------------------------------------------------------------------------
-- Feature patches: the eye openings and the mouth get their own ring topology (edge loops that follow the
-- lid rims and the lips), cut into the grid and zipped to it. The rims and the lips' parting line are then
-- exact rings of vertices (a crisp fold where the skin meets the lids, a clean slit between the lips), and
-- the grid never needs rows tight enough for them: grid rows run round the whole head, and tight rows make
-- thin slivers on the cheeks that smear the shading sideways
------------------------------------------------------------------------
-- the band ray through (px, pz): the guide ellipse's normal passing through the point (rays leave the ellipse
-- along its normals). Newton on (p - g(th)) x n(th) = 0 from a guess near the front
local function thetaThrough(px, pz, th0)
	local qz = pz - ZA
	local k2 = GA * GA - GB * GB
	local th = th0
	if not th then
		local reach = GA + max(0.1, -qz - GB) * GB / GA
		th = 2.5 * pi - math.asin(clamp(px / reach, -0.95, 0.95))
	end
	for _ = 1, 10 do
		local c, s = cos(th), sin(th)
		local f = k2 * s * c - GA * px * s - GB * qz * c
		local fp = k2 * (c * c - s * s) - GA * px * c + GB * qz * s
		if abs(fp) < 1e-9 then
			break
		end
		local d = clamp(f / fp, -0.25, 0.25)
		th -= d
		if abs(d) < 1e-10 then
			break
		end
	end
	return th
end

-- 2D helpers on closed polygons { x1, y1, x2, y2, ... } (the front view: x, y)
local function polyArea(xs, ys)
	local n, a = #xs, 0
	for i = 1, n do
		local j = i % n + 1
		a += xs[i] * ys[j] - xs[j] * ys[i]
	end
	return a * 0.5
end

-- signed distance from (px, py) to the closed polygon (negative inside)
local function polySD(xs, ys, px, py)
	local n = #xs
	local best = huge
	local inside = false
	local j = n
	for i = 1, n do
		local ax, ay, bx, by = xs[j], ys[j], xs[i], ys[i]
		local vx, vy = bx - ax, by - ay
		local wx, wy = px - ax, py - ay
		local l2 = vx * vx + vy * vy
		local t = l2 > 0 and clamp((wx * vx + wy * vy) / l2, 0, 1) or 0
		local dx, dy = wx - vx * t, wy - vy * t
		local d2 = dx * dx + dy * dy
		if d2 < best then
			best = d2
		end
		if (ay > py) ~= (by > py) and px < ax + (py - ay) / (by - ay) * vx then
			inside = not inside
		end
		j = i
	end
	local d = sqrt(best)
	return inside and -d or d
end

-- the eye patch: rings (lists of target points) round the socket rim. The rim is where the skin meets the
-- lids: on the cover sphere just over the lid shells (rimAt's contour in the eye's angles), so the lid shells
-- (lidMesh: their skin reaches past the rim, under the fold) always meet it. Inside: one ring diving behind the
-- eyeball (hidden by the lids and the eyeball) and the centre. Outside: rings blending from the cover sphere,
-- rising away from the rim (bowl: up the fold toward the brow, gently down into the cheek), into the face
local function eyePatchSpec(F, side, lod)
	local E = eyeFrame(F, side)
	local eR = F.eyeR
	-- the skin at the rim: flush with the lower lid (a hair over it), folding a little over the upper (the crease)
	local coverDn = eR + F.lowOut + 0.0004
	local coverUp = eR + F.lidOut + 0.003 + 0.0015 * F.lidHeavy
	local age = clamp((F.age - 35) / 25, 0, 1)
	-- how the skin leaves the rim: up the fold toward the brow (steeper for deep-set / older / lean eyes); under
	-- the eye straight down (the sphere's radius grows as fast as its surface turns back: no trough under the
	-- lid), a touch hollow when deep-set or gaunt
	local bowlUp = 0.9 + 0.5 * F.eyeDepth + 0.3 * age + 0.25 * F.gaunt
	local bowlDn = 0.85 - 0.2 * F.eyeDepth - 0.2 * F.gaunt
	local _, _, a0, a1 = rimAt(F, 0)
	-- the rim, finely: the upper contour medial -> lateral, the lower back (cosine spacing: the round corners)
	local nH = 48
	local ra, rb = {}, {}
	for i = 0, nH do
		local a = lerp(a0, a1, (1 - cos(pi * i / nH)) * 0.5)
		local up = rimAt(F, a)
		ra[#ra + 1], rb[#rb + 1] = a, up
	end
	for i = nH - 1, 1, -1 do
		local a = lerp(a0, a1, (1 - cos(pi * i / nH)) * 0.5)
		local _, dn = rimAt(F, a)
		ra[#ra + 1], rb[#rb + 1] = a, dn
	end
	local n = #ra
	local X, Y, Z, UW = table.create(n), table.create(n), table.create(n), table.create(n)
	for i = 1, n do
		local uw = smoothstep(-0.05, 0.12, rb[i])
		UW[i] = uw
		X[i], Y[i], Z[i] = eyePoint(E, ra[i], rb[i], lerp(coverDn, coverUp, uw))
	end
	-- outward normals in the front view, and a parameter that is part arc length, part turning angle (points
	-- along the long lid contours and round the corners alike)
	local area = polyArea(X, Y)
	local sgn = area > 0 and 1 or -1
	local NX, NY = table.create(n), table.create(n)
	for i = 1, n do
		local ip, inx = (i - 2) % n + 1, i % n + 1
		local tx, ty = X[inx] - X[ip], Y[inx] - Y[ip]
		local l = sqrt(tx * tx + ty * ty)
		NX[i], NY[i] = sgn * ty / l, -sgn * tx / l
	end
	local S = table.create(n + 1, 0)
	local len, turn = 0, 0
	for i = 1, n do
		local j = i % n + 1
		len += sqrt((X[j] - X[i]) ^ 2 + (Y[j] - Y[i]) ^ 2)
		turn += abs(math.atan2(NX[i] * NY[j] - NY[i] * NX[j], NX[i] * NX[j] + NY[i] * NY[j]))
	end
	for i = 1, n do
		local j = i % n + 1
		local ds = sqrt((X[j] - X[i]) ^ 2 + (Y[j] - Y[i]) ^ 2) / len
		local dt = abs(math.atan2(NX[i] * NY[j] - NY[i] * NX[j], NX[i] * NX[j] + NY[i] * NY[j])) / turn
		S[i + 1] = S[i] + 0.7 * ds + 0.3 * dt
	end
	local full = lod == "full"
	local M = full and 26 or 18
	-- per point k: the rim position (3D, on the cover), the outward normal (front view), the up / down blend,
	-- how far out the patch reaches there (less toward the nose, more toward the temple and the cheek)
	local pts = table.create(M)
	local i = 1
	for k = 0, M - 1 do
		local target = S[n + 1] * k / M
		while i < n and S[i + 1] < target do
			i += 1
		end
		local j = i % n + 1
		local f = S[i + 1] > S[i] and (target - S[i]) / (S[i + 1] - S[i]) or 0
		local nx, ny = lerp(NX[i], NX[j], f), lerp(NY[i], NY[j], f)
		local nl = sqrt(nx * nx + ny * ny)
		nx, ny = nx / nl, ny / nl
		local uw = lerp(UW[i], UW[j], f)
		local lat = nx * side
		local reach = 0.031 + 0.008 * max(0, lat) - 0.012 * max(0, -lat) + 0.004 * max(0, -ny)
		pts[k + 1] = {
			x = lerp(X[i], X[j], f), y = lerp(Y[i], Y[j], f), z = lerp(Z[i], Z[j], f),
			nx = nx, ny = ny, uw = uw, reach = reach,
			lidR = lerp(coverDn, coverUp, uw), bowl = lerp(bowlDn, bowlUp, uw),
		}
	end
	local cx, cy = 0, 0
	for k = 1, M do
		cx += pts[k].x
		cy += pts[k].y
	end
	-- ring offsets: the dive, the rim, then fractions of the reach
	local outer = full and { 0.14, 0.35, 0.62, 1 } or { 0.3, 1 }
	return {
		kind = "eye", side = side, E = E, M = M, pts = pts, outer = outer, dive = -0.002,
		centre = { cx / M, cy / M }, inner = eR - 0.006,
	}
end

-- the mouth patch: rings round the closed lips. The parting line is two rows of vertices (upper lip / lower
-- lip, a hair apart: the jaw opens them) meeting at the corners; rings at fractions of the vermilion out to
-- the border, then rings past it into the skin (round past the corners)
local function mouthPatchSpec(F, lod)
	local full = lod == "full"
	local mW = F.mouthW
	local nHalf = full and 13 or 8
	local lipF = full and { 0, 0.3, 0.7, 1 } or { 0, 0.6, 1 }
	local skinO = full and { 0.006, 0.02, 0.042 } or { 0.008, 0.024, 0.042 }
	local mL = F.mouthLine
	local function lineAt(x)
		local ax = abs(x)
		if ax <= mW then
			return mL(x)
		end
		local s = x > 0 and 1 or -1
		local e = 0.0005
		local slope = (mL(s * mW) - mL(s * (mW - e))) / e
		return mL(s * mW) + (ax - mW) * (slope + 0.25)
	end
	local M = nHalf * 2
	local rings = {}
	-- xn per point k (0 = left corner, nHalf = right corner; upper half first)
	local XN, UP = table.create(M), table.create(M)
	for k = 0, M - 1 do
		local p = k <= nHalf and k / nHalf or (M - k) / nHalf
		XN[k + 1] = -cos(pi * p)
		UP[k + 1] = k <= nHalf
	end
	for _, f in ipairs(lipF) do
		local ring = { lip = true, f = f }
		for k = 1, M do
			local x = XN[k] * mW
			local hu, hl = F.lipH(x)
			local corner = (k == 1 or k == nHalf + 1)
			local y
			if corner then
				y = lineAt(x)
			elseif f == 0 then
				local eps = 0.0008 * sqrt(max(0, 1 - XN[k] ^ 2))
				y = lineAt(x) + (UP[k] and eps or -eps)
			else
				y = lineAt(x) + (UP[k] and f * hu or -f * hl)
			end
			ring[k] = { x = x, y = y, corner = corner }
		end
		rings[#rings + 1] = ring
	end
	-- the skin rings above the lip stop short of the nose's base (the nose patch ends above the subnasale's
	-- grid row: the two patches never meet)
	local capY = F.noseBaseY - 0.024 - (full and 0.011 or 0.014)
	local oMax = skinO[#skinO]
	for _, o in ipairs(skinO) do
		local ex = o * 0.9
		local ring = { lip = false, o = o }
		for k = 1, M do
			local x = XN[k] * (mW + ex)
			local ax = abs(x)
			local up = UP[k]
			local y
			if ax <= mW then
				local hu, hl = F.lipH(x)
				local kU = clamp((capY - (lineAt(x) + hu)) / oMax, 0.4, 1)
				y = lineAt(x) + (up and (hu + o * kU) or -(hl + 1.15 * o))
			else
				local xb = clamp((ax - mW) / ex, 0, 1)
				local h = sqrt(max(0, 1 - xb * xb))
				y = lineAt(x) + (up and o * h or -1.15 * o * h)
			end
			ring[k] = { x = x, y = y }
		end
		rings[#rings + 1] = ring
	end
	return { kind = "mouth", M = M, nHalf = nHalf, rings = rings, nLip = #lipF, centre = { 0, F.mouthY } }
end

-- the head's skin: grid rows of rays + the feature patches. lod: "full" | "medium" | "low" (low: no patches,
-- no sockets: the eyes are painted, nothing dives behind them)
local function headSurface(F, q, lod)
	local m = MeshKit.New("Head")
	local field = F.field
	local relief = F.relief
	local rows, yT, yB = rowList(F, q, false)
	local counts = rowCounts(F, rows, q, yT, yB, 90)
	local C0, C1, ia, ib = bandColumns(F, q)
	local CP = table.create(ib - ia + 1)
	for j = ia, ib do
		CP[#CP + 1] = C1[j]
	end
	local rowCols = {}
	local rowStart, rowCount = {}, {}
	local prevTh, prevT = nil, nil
	-- per vertex: the base surface point, the ray direction, how much a socket's cover sphere shapes the skin
	-- there (0..1) and which eye's (EC: -1 / 1, 0 = none)
	local B, Dir, SW, EC = {}, {}, {}, {}
	local function rec(i, bx, by, bz, dx, dy, dz, sw, ec)
		B[i * 3 - 2], B[i * 3 - 1], B[i * 3] = bx, by, bz
		Dir[i * 3 - 2], Dir[i * 3 - 1], Dir[i * 3] = dx, dy, dz
		SW[i] = sw
		EC[i] = ec or 0
	end
	do
		local t = hit(field, 0, yT, ZA, 0, 1, 0, 0.38)
		local i = MeshKit.Vertex(m, 0, yT + t, ZA, 0.5, 0)
		rec(i, 0, yT + t, ZA, 0, 1, 0, 0)
		rowStart[0], rowCount[0] = i, 1
	end
	for r, row in ipairs(rows) do
		local yApprox = rowApproxY(row, yT, yB)
		local cols
		if row.partial then
			cols = CP
		elseif row.kind == "band" then
			cols = row.nose and C1 or C0
		else
			cols = columnsFor(F, row, counts[r], yApprox)
		end
		rowCols[r] = cols
		rowStart[r], rowCount[r] = m.nv + 1, #cols
		local tPrev = 0.5
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
			-- v is assigned by arc length once every row exists (assignV)
			local vi = MeshKit.Vertex(m, ox + dx * tt, oy + dy * tt, oz + dz * tt, uOf(th), 0)
			rec(vi, bx, by, bz, dx, dy, dz, 0)
		end
		-- the band / cap rays change family at the cap borders: guesses only within a family. Partial rows
		-- (and the full row after them) guess from the last full row above
		if not row.partial then
			local nextRow = rows[r + 1]
			if nextRow and nextRow.kind == row.kind then
				prevTh, prevT = cols, curT
			else
				prevTh, prevT = nil, nil
			end
		end
		-- each column is a ray cast through the field (several SDF evaluations)
		MeshKit.Step(#cols * 4)
	end
	do
		local t = hit(field, 0, yB, ZA, 0, -1, 0, 0.5)
		local i = MeshKit.Vertex(m, 0, yB - t, ZA, 0.5, HEAD_V)
		rec(i, 0, yB - t, ZA, 0, -1, 0, 0)
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
	-- the index of column theta th in row r's columns
	local function colIndex(r, th)
		local cols = rowCols[r]
		for j, t in ipairs(cols) do
			if abs(t - th) < 1e-9 then
				return j
			end
		end
		error("AnatomyHead: column missing from a band row")
	end
	local thA, thB = C1[ia], C1[ib]
	local r = 0
	local nR = #rows
	while r <= nR do
		local nxt = r + 1
		local Ps = {}
		while nxt <= nR and rows[nxt].partial do
			Ps[#Ps + 1] = nxt
			nxt += 1
		end
		if #Ps == 0 then
			stitch(rowStart[r], rowCount[r], rowStart[nxt], rowCount[nxt])
		else
			-- a block: full row A, partial rows P1..Pk across the nose, full row C. Inside the span the rows
			-- zip one to the next; outside it A zips straight to C; at the span's ends a fan closes the gap
			local A, C = r, nxt
			local aI, aJ = colIndex(A, thA), colIndex(A, thB)
			local cI, cJ = colIndex(C, thA), colIndex(C, thB)
			local a0, c0 = rowStart[A], rowStart[C]
			stitch(a0 + aI - 1, aJ - aI + 1, rowStart[Ps[1]], rowCount[Ps[1]])
			for i = 1, #Ps - 1 do
				stitch(rowStart[Ps[i]], rowCount[Ps[i]], rowStart[Ps[i + 1]], rowCount[Ps[i + 1]])
			end
			local pk = Ps[#Ps]
			stitch(rowStart[pk], rowCount[pk], c0 + cI - 1, cJ - cI + 1)
			stitch(a0, aI, c0, cI)
			stitch(a0 + aJ - 1, rowCount[A] - aJ + 1, c0 + cJ - 1, rowCount[C] - cJ + 1)
			-- the fans: left (A, C, Pk, ..., P1), right (A, P1, ..., Pk, C)
			local Aa, Ca = a0 + aI - 1, c0 + cI - 1
			local Ab, Cb = a0 + aJ - 1, c0 + cJ - 1
			MeshKit.Tri(m, Aa, Ca, rowStart[pk])
			for i = #Ps, 2, -1 do
				MeshKit.Tri(m, Aa, rowStart[Ps[i]], rowStart[Ps[i - 1]])
			end
			for i = 1, #Ps - 1 do
				MeshKit.Tri(m, Ab, rowStart[Ps[i]] + rowCount[Ps[i]] - 1, rowStart[Ps[i + 1]] + rowCount[Ps[i + 1]] - 1)
			end
			MeshKit.Tri(m, Ab, rowStart[pk] + rowCount[pk] - 1, Cb)
		end
		r = nxt
	end
	local gridEnd = m.nv
	local G = { start = rowStart, count = rowCount, n = #rows + 1, rows = rows, B = B, Dir = Dir, SW = SW, EC = EC, gridEnd = gridEnd, patch = {}, cols = rowCols }
	m.gridRows = G
	-- the grid's own sampling scale at each vertex (half the gap to its neighbours along the row / across the
	-- rows): fieldNormals filters the relief's slope over it, so a feature the columns cannot hold never
	-- smears into a streak along a long thin triangle
	do
		local Pm = m.P
		local EH, EV = table.create(gridEnd, 0.0015), table.create(gridEnd, 0.0015)
		local function dist(a, b)
			return sqrt((Pm[a * 3 - 2] - Pm[b * 3 - 2]) ^ 2 + (Pm[a * 3 - 1] - Pm[b * 3 - 1]) ^ 2 + (Pm[a * 3] - Pm[b * 3]) ^ 2)
		end
		for r = 1, #rows do
			local s0, n = rowStart[r], rowCount[r]
			local yr = rows[r].kind == "band" and rows[r].y
			local yu = rows[r - 1] and rows[r - 1].kind == "band" and rows[r - 1].y
			local yd = rows[r + 1] and rows[r + 1].kind == "band" and rows[r + 1].y
			local ev = 0.0015
			if yr and yu and yd then
				ev = 0.5 * max(yu - yr, yr - yd)
			end
			for j = 0, n - 1 do
				local i = s0 + j
				local a = j > 0 and dist(i, i - 1) or 0
				local b = j < n - 1 and dist(i, i + 1) or 0
				EH[i] = clamp(0.5 * max(a, b), 0.0015, 0.035)
				EV[i] = clamp(ev, 0.0015, 0.02)
			end
		end
		G.EH, G.EV = EH, EV
	end
	if lod == "low" then
		return m
	end

	--------------------------------------------------------------- patch vertices (the grid's own ray family)
	local P = m.P
	-- one skin vertex on the band ray through the target (x, y, z guess): the field, the relief, then the
	-- socket's shaping for eye patches (sock = { E, o (offset from the rim; < 0 inside), pt, inner, side })
	local function patchVertex(tx, ty, tz, sock)
		local th = thetaThrough(tx, tz)
		local vi
		for pass = 1, 2 do
			local ox, oy, oz, dx, dy, dz = ray({ kind = "band", y = ty }, th, yT, yB)
			local t = hit(field, ox, oy, oz, dx, dy, dz, sqrt((tx - ox) ^ 2 + (tz - oz) ^ 2), 0.05)
			local bx, by, bz = ox + dx * t, oy + dy * t, oz + dz * t
			local tt = t + relief(bx, by, bz)
			local sw, ec = 0, 0
			if sock then
				local E, o, pt = sock.E, sock.o, sock.pt
				if o < 0 or sock.centre then
					-- behind the eyeball (just under its surface): the lids and the eyeball hide it
					local tH, tc = raySphere(ox, oy, oz, dx, dy, dz, E.cx, E.cy, E.cz, sock.inner)
					tt = tH or tc
					sw, ec = 1, sock.side
				else
					local rB = pt.lidR + pt.bowl * o
					local tB = raySphere(ox, oy, oz, dx, dy, dz, E.cx, E.cy, E.cz, rB)
					local s = clamp(o / pt.reach, 0, 1)
					local wB = 1 - s * s * (3 - 2 * s)
					if tB and wB > 0 then
						tt = lerp(tt, tB, wB)
						sw, ec = wB, sock.side
					end
				end
			end
			local px, pz = ox + dx * tt, oz + dz * tt
			if pass == 1 and not (sock and sock.exact) and abs(px - tx) > 0.0006 then
				-- the guess at the depth was off: aim again through the point found
				th = thetaThrough(tx, pz, th)
			else
				vi = MeshKit.Vertex(m, px, oy + dy * tt, pz, uOf(th), 0)
				rec(vi, bx, by, bz, dx, dy, dz, sw, ec)
				G.patch[#G.patch + 1] = vi
				break
			end
		end
		MeshKit.Step(6)
		return vi
	end

	--------------------------------------------------------------- cutting a patch's hole into the grid
	local T = m.T
	-- removes every grid triangle touching the region (outer ring polygon xs / ys, grown by grow), returns the
	-- hole's boundary loop (grid vertex ids, in the kept triangles' edge direction)
	local dead = G.dead or {}
	G.dead = dead
	local function cutHole(xs, ys, grow)
		local x0, x1, y0, y1 = huge, -huge, huge, -huge
		for i = 1, #xs do
			x0, x1 = min(x0, xs[i]), max(x1, xs[i])
			y0, y1 = min(y0, ys[i]), max(y1, ys[i])
		end
		x0, x1, y0, y1 = x0 - grow, x1 + grow, y0 - grow, y1 + grow
		local inside = {}
		for i = 1, gridEnd do
			local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
			if z < -0.05 and x > x0 and x < x1 and y > y0 and y < y1 and polySD(xs, ys, x, y) < grow then
				inside[i] = true
			end
			if i % 256 == 0 then
				MeshKit.Step(48)
			end
		end
		local nt = m.nt
		local gone = {}
		for t = 1, nt do
			if t % 256 == 0 then
				MeshKit.Step(48)
			end
			local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
			if a <= gridEnd and b <= gridEnd and c <= gridEnd and not dead[t] then
				if inside[a] or inside[b] or inside[c] then
					gone[t] = true
				else
					local gx = (P[a * 3 - 2] + P[b * 3 - 2] + P[c * 3 - 2]) / 3
					local gy = (P[a * 3 - 1] + P[b * 3 - 1] + P[c * 3 - 1]) / 3
					local gz = (P[a * 3] + P[b * 3] + P[c * 3]) / 3
					if gz < -0.05 and gx > x0 and gx < x1 and gy > y0 and gy < y1 and polySD(xs, ys, gx, gy) < grow then
						gone[t] = true
					end
				end
			end
		end
		-- the loop round the removed triangles; a vertex the loop passes twice (two lobes of the hole meeting
		-- at a corner) takes its remaining triangles into the hole too
		for _ = 1, 8 do
			local edgeOf = {}
			for t in pairs(gone) do
				local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
				edgeOf[a * 65536 + b], edgeOf[b * 65536 + c], edgeOf[c * 65536 + a] = true, true, true
			end
			local nextOf, outN = {}, {}
			local pinch = nil
			for t = 1, nt do
				if t % 256 == 0 then
					MeshKit.Step(32)
				end
				if not gone[t] and not dead[t] then
					local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
					for e = 1, 3 do
						local u, v
						if e == 1 then
							u, v = a, b
						elseif e == 2 then
							u, v = b, c
						else
							u, v = c, a
						end
						if edgeOf[v * 65536 + u] then
							outN[u] = (outN[u] or 0) + 1
							nextOf[u] = v
							if outN[u] > 1 then
								pinch = u
							end
						end
					end
				end
			end
			if not pinch then
				local start = next(nextOf)
				local loop = {}
				local v = start
				repeat
					loop[#loop + 1] = v
					v = nextOf[v]
				until v == start or v == nil or #loop > 4096
				local nLoop = 0
				for _ in pairs(nextOf) do
					nLoop += 1
				end
				for t in pairs(gone) do
					dead[t] = true
				end
				return loop, nLoop == #loop
			end
			for t = 1, nt do
				if not gone[t] and not dead[t] then
					local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
					if a == pinch or b == pinch or c == pinch then
						gone[t] = true
					end
				end
			end
		end
		error("AnatomyHead: patch hole did not close")
	end

	-- zips the hole loop H (kept edge direction) to the ring R (patch vertex ids, in the order the patch's own
	-- triangles need: ring edges R[k] -> R[k+1] are free): triangles (h1, h0, r) and (h, r0, r1). Both loops are
	-- walked by angle round the centre (made monotonic), from aligned starting points
	local function zip(H, R, cx, cy)
		local nh, nr = #H, #R
		local function ang(i)
			return math.atan2(P[i * 3 - 1] - cy, P[i * 3 - 2] - cx)
		end
		-- the walking direction: both loops must turn the same way round the centre
		local function turnOf(L)
			local s = 0
			for i = 1, #L do
				local a, b = ang(L[i]), ang(L[i % #L + 1])
				local d = b - a
				if d > pi then
					d -= TAU
				elseif d < -pi then
					d += TAU
				end
				s += d
			end
			return s
		end
		local dirH = turnOf(H) > 0 and 1 or -1
		local dirR = turnOf(R) > 0 and 1 or -1
		if dirH ~= dirR then
			return false
		end
		-- start R at the ring point closest in angle to H[1]
		local a0 = ang(H[1])
		local best, bk = huge, 1
		for k = 1, nr do
			local d = abs(((ang(R[k]) - a0 + pi) % TAU) - pi)
			if d < best then
				best, bk = d, k
			end
		end
		local function unwrapped(L, first, n)
			local out = table.create(n + 1)
			local base = ang(L[first])
			local prev = 0
			for s = 0, n do
				local idx = (first - 1 + s) % n + 1
				local d = ((ang(L[idx]) - base) * dirH + pi) % TAU - pi
				if s == n then
					d = TAU
				elseif s > 0 and d < prev - pi then
					d += TAU
				end
				d = max(d, prev)
				out[s + 1] = d
				prev = d
			end
			return out
		end
		local AH = unwrapped(H, 1, nh)
		local AR = unwrapped(R, bk, nr)
		-- the ring's start may sit a little before H[1] in angle
		local off = ((ang(R[bk]) - a0) * dirH + pi) % TAU - pi
		for s = 1, nr + 1 do
			AR[s] += off
		end
		local i, j = 0, 0
		local function Hi(s)
			return H[s % nh + 1]
		end
		local function Rj(s)
			return R[(bk - 1 + s) % nr + 1]
		end
		while i < nh or j < nr do
			local advH
			if i >= nh then
				advH = false
			elseif j >= nr then
				advH = true
			else
				advH = AH[i + 2] <= AR[j + 2]
			end
			if advH then
				MeshKit.Tri(m, Hi(i + 1), Hi(i), Rj(j))
				i += 1
			else
				MeshKit.Tri(m, Hi(i), Rj(j), Rj(j + 1))
				j += 1
			end
		end
		return true
	end

	-- the patch's triangles. V[j][k]: ring j (0 = innermost) point k. Quads (j, k) -> (j+1, k+1) as (A, B, C) +
	-- (A, C, D): ring j's edges run k -> k+1, ring j+1's back. Shared corner vertices make a quad a triangle
	local function tri3(a, b, c)
		if a ~= b and b ~= c and a ~= c then
			MeshKit.Tri(m, a, b, c)
		end
	end
	local function strips(V, M)
		for j = 1, #V - 1 do
			local r0, r1 = V[j], V[j + 1]
			for k = 1, M do
				local k1 = k % M + 1
				local a, b, c, d = r0[k], r0[k1], r1[k1], r1[k]
				-- the shorter diagonal
				local ac = (P[a * 3 - 2] - P[c * 3 - 2]) ^ 2 + (P[a * 3 - 1] - P[c * 3 - 1]) ^ 2 + (P[a * 3] - P[c * 3]) ^ 2
				local bd = (P[b * 3 - 2] - P[d * 3 - 2]) ^ 2 + (P[b * 3 - 1] - P[d * 3 - 1]) ^ 2 + (P[b * 3] - P[d * 3]) ^ 2
				if ac <= bd then
					tri3(a, b, c)
					tri3(a, c, d)
				else
					tri3(a, b, d)
					tri3(b, c, d)
				end
			end
		end
	end
	-- after building: the patch faces the same way as the grid round it (its outer ring is zipped with the
	-- hole's edges reversed); a patch built the other way round is flipped, its outer ring walked backwards
	local function finishPatch(firstTri, outerRing, cx, cy, grow, extend)
		local xs, ys = {}, {}
		for k, vi in ipairs(outerRing) do
			xs[k], ys[k] = P[vi * 3 - 2], P[vi * 3 - 1]
		end
		local H, single = cutHole(xs, ys, grow)
		assert(single, "AnatomyHead: patch hole is not one loop")
		local R = outerRing
		if extend then
			-- more rings out to the hole's edge (a coarse grid round the patch would leave long zip triangles)
			R = extend(H, outerRing)
		end
		if not zip(H, R, cx, cy) then
			-- flip the patch: its triangles and the ring's walking order
			for t = firstTri, m.nt do
				T[t * 3 - 1], T[t * 3] = T[t * 3], T[t * 3 - 1]
			end
			local rev = table.create(#R)
			for k = #R, 1, -1 do
				rev[#rev + 1] = R[k]
			end
			assert(zip(H, rev, cx, cy), "AnatomyHead: patch zip failed")
		end
		return H
	end

	--------------------------------------------------------------- eyes
	local full = lod == "full"
	for side = -1, 1, 2 do
		local spec = eyePatchSpec(F, side, lod)
		local E, M, pts = spec.E, spec.M, spec.pts
		local firstTri = m.nt + 1
		local V = {}
		-- the dive ring and the rim (exact: through the rim points on the cover sphere)
		local dive, rim = table.create(M), table.create(M)
		for k = 1, M do
			local p = pts[k]
			local o = spec.dive
			dive[k] = patchVertex(p.x + o * p.nx, p.y + o * p.ny, p.z, { E = E, o = o, pt = p, inner = spec.inner, side = side })
			rim[k] = patchVertex(p.x, p.y, p.z, { E = E, o = 0, pt = p, side = side, exact = true })
		end
		V[1], V[2] = dive, rim
		local prevZ = table.create(M)
		for k = 1, M do
			prevZ[k] = P[rim[k] * 3]
		end
		for _, fr in ipairs(spec.outer) do
			local ring = table.create(M)
			for k = 1, M do
				local p = pts[k]
				local o = fr * p.reach
				ring[k] = patchVertex(p.x + o * p.nx, p.y + o * p.ny, prevZ[k], { E = E, o = o, pt = p, side = side })
				prevZ[k] = P[ring[k] * 3]
			end
			V[#V + 1] = ring
		end
		-- the centre (behind the eyeball) and its fan: the dive ring's edges reversed
		local cx, cy = spec.centre[1], spec.centre[2]
		local c = patchVertex(cx, cy, E.cz - F.eyeR, { E = E, o = -1, centre = true, pt = pts[1], inner = spec.inner, side = side })
		G.eyes = G.eyes or {}
		G.eyes[side] = { rings = V, pts = pts, centre = c, outer = spec.outer }
		for k = 1, M do
			tri3(c, dive[k % M + 1], dive[k])
		end
		strips(V, M)
		finishPatch(firstTri, V[#V], cx, cy, full and 0.006 or 0.009)
	end

	--------------------------------------------------------------- mouth
	do
		local spec = mouthPatchSpec(F, lod)
		local M, nHalf = spec.M, spec.nHalf
		local firstTri = m.nt + 1
		local V = {}
		local cornerL, cornerR
		local prevZ = table.create(M)
		for j, ring in ipairs(spec.rings) do
			local out = table.create(M)
			for k = 1, M do
				local p = ring[k]
				-- the lip rings share the corner vertices (the lips meet in a point there)
				local shared = ring.lip and p.corner and (k == 1 and cornerL or (k ~= 1 and cornerR)) or nil
				if shared then
					out[k] = shared
				else
					local z = prevZ[k]
					if not z then
						local t = hit(field, p.x, p.y, ZA, 0, 0, -1, 0.44)
						z = ZA - t
					end
					out[k] = patchVertex(p.x, p.y, z)
					if ring.lip and p.corner then
						if k == 1 then
							cornerL = out[k]
						else
							cornerR = out[k]
						end
					end
				end
				prevZ[k] = P[out[k] * 3]
			end
			V[j] = out
		end
		-- the slit between the lips (inside the parting ring): upper point k pairs with lower point M + 2 - k
		local r0 = V[1]
		for k = 1, nHalf do
			local u0, u1 = r0[k], r0[k + 1]
			local l0 = r0[(M + 1 - k) % M + 1]
			local l1 = r0[(M - k) % M + 1]
			tri3(u1, u0, l0)
			tri3(u1, l0, l1)
		end
		strips(V, M)
		G.mouthHole = finishPatch(firstTri, V[#V], spec.centre[1], spec.centre[2], full and 0.006 or 0.009)
	end
	--------------------------------------------------------------- nose (the lower nose: tip, wings, columella, nostrils)
	-- rays from a point inside the lower nose (above and behind the tip) out to their first exit: they meet the
	-- underside, the nostrils and the wings face on, where the grid's horizontal rows only graze them. Rings by
	-- arc length out to where the nose meets the face (just short of the alar creases and the lip) or, up the
	-- dorsum, a height; then two rings on the face itself (the grid's rays: the creases, the cheek and the lip
	-- round the nose's foot), the outer one zipped to the grid. The rays' part has its own texture island (the
	-- underside is no sliver of the face's map); its last ring has a twin with the grid's texture coordinates
	local function buildNose()
		local NI = F.noseInfo
		-- the floor: the nose patch (its face rings too) stays above the mouth hole's top edge (the grid row
		-- both patches zip to) by more than the cut's margin
		local floorY = NI.baseY - 0.016
		do
			local top = -huge
			for _, vi in ipairs(G.mouthHole or {}) do
				if abs(P[vi * 3 - 2] - NI.devAt(NI.baseY)) < F.noseW + 0.03 then
					top = max(top, P[vi * 3 - 1])
				end
			end
			if top > -huge then
				floorY = max(floorY, top + (full and 0.007 or 0.011))
			end
		end
		local face = F.face
		local ox, oy, oz = NI.C[1], NI.C[2], NI.C[3]
		local axx, axy, axz = NI.tip[1] - ox, NI.tip[2] - oy, NI.tip[3] - oz
		local al = sqrt(axx * axx + axy * axy + axz * axz)
		axx, axy, axz = axx / al, axy / al, axz / al
		-- e1: across (+x), e2: the axis' "up"
		local e1x, e1y, e1z = 1 - axx * axx, -axx * axy, -axx * axz
		local l1 = sqrt(e1x * e1x + e1y * e1y + e1z * e1z)
		e1x, e1y, e1z = e1x / l1, e1y / l1, e1z / l1
		local e2x, e2y, e2z = axy * e1z - axz * e1y, axz * e1x - axx * e1z, axx * e1y - axy * e1x
		if e2y < 0 then
			e2x, e2y, e2z = -e2x, -e2y, -e2z
		end
		local M = full and 26 or 14
		local R = full and 7 or 3
		local yCap = NI.yT + 0.05
		local gB = 0.009
		local function dirOf(a, ph)
			local ca, sa = cos(a), sin(a)
			local cp, sp = cos(ph), sin(ph)
			return ca * axx + sa * (cp * e1x + sp * e2x), ca * axy + sa * (cp * e1y + sp * e2y), ca * axz + sa * (cp * e1z + sp * e2z)
		end
		-- the first exit along d from the inside point: sphere traced from the start (a march started nearer a
		-- neighbouring ray's exit can step past this ray's own first exit), then bracketed and refined
		local fC = field(ox, oy, oz)
		local function exitAt(dx, dy, dz)
			local t, f = 0, fC
			local n = 0
			local tIn, fIn = t, f
			for _ = 1, 80 do
				tIn, fIn = t, f
				t += clamp(-f * 0.85, 0.0015, 0.01)
				f = field(ox + dx * t, oy + dy * t, oz + dz * t)
				n += 1
				if f > 0 or t > 0.3 then
					break
				end
			end
			MeshKit.Step(3 * n + 18)
			if f <= 0 then
				return ox + dx * t, oy + dy * t, oz + dz * t, t
			end
			-- two halvings, then false position (Illinois: the stale end's value halved, so both ends move)
			local a, b, fa, fb = tIn, t, fIn, f
			for _ = 1, 2 do
				local mid = (a + b) * 0.5
				local fm = field(ox + dx * mid, oy + dy * mid, oz + dz * mid)
				if fm > 0 then
					b, fb = mid, fm
				else
					a, fa = mid, fm
				end
			end
			local side = 0
			for _ = 1, 3 do
				local tm = a + (b - a) * clamp(-fa / max(fb - fa, 1e-12), 0.02, 0.98)
				local fm = field(ox + dx * tm, oy + dy * tm, oz + dz * tm)
				if fm > 0 then
					b, fb = tm, fm
					if side == 1 then
						fa *= 0.5
					end
					side = 1
				else
					a, fa = tm, fm
					if side == -1 then
						fb *= 0.5
					end
					side = -1
				end
			end
			local tt = a + (b - a) * clamp(-fa / max(fb - fa, 1e-12), 0, 1)
			return ox + dx * tt, oy + dy * tt, oz + dz * tt, tt
		end
		-- past the boundary: near the face (the creases, the lip), above the cap, or through into the lip below.
		-- Not inside the nostrils' vestibules (between the columella and the wings, above the sill: their back
		-- walls run close to the face, but they are the nose's own cavities)
		local AL = NI.ala
		local pocketX = AL.x - AL.rx * 0.4
		local nbY = NI.baseY
		local function beyond(x, y, z)
			local cx = x - NI.devAt(y)
			if y > yCap - 2.5 * cx * cx or y < floorY + (full and 0.008 or 0.01) then
				return true
			end
			if abs(x - NI.devAt(y)) < pocketX and y > nbY + 0.006 then
				return false
			end
			return face(x, y, z) < gB
		end
		-- directions round the axis, denser under the tip (the columella and the nostrils are small)
		local PH = table.create(M)
		do
			local nS = 360
			local cdf = table.create(nS + 1, 0)
			for i = 1, nS do
				local ph = TAU * (i - 0.5) / nS
				local dd = abs(((ph - 1.5 * pi + pi) % TAU) - pi) -- angle from straight down
				cdf[i + 1] = cdf[i] + 1 + 0.9 * bump((dd / 1.25) ^ 2)
			end
			local i = 1
			for k = 1, M do
				-- the first direction straight down (the columella's midline)
				local target = cdf[nS + 1] * ((k - 1) / M)
				while i < nS and cdf[i + 1] < target do
					i += 1
				end
				local f = (target - cdf[i]) / max(1e-9, cdf[i + 1] - cdf[i])
				PH[k] = (1.5 * pi - pi + TAU * ((i - 1) + f) / nS)
			end
			-- rotate so k = 1 points down (the cdf above starts at phi = 0)
			local start = 0
			for k = 1, M do
				if abs(((PH[k] - 1.5 * pi + pi) % TAU) - pi) < abs(((PH[start + 1] - 1.5 * pi + pi) % TAU) - pi) then
					start = k - 1
				end
			end
			local rot = table.create(M)
			for k = 1, M do
				rot[k] = PH[(start + k - 1) % M + 1]
			end
			PH = rot
		end
		-- the sampling depends on the face and the level only (not on the grid's density): the budget's rebuilds
		-- reuse it
		local cacheKey = string.format("%s|%.5f", lod, floorY)
		F.noseSample = F.noseSample or {}
		local cached = F.noseSample[cacheKey]
		local A
		if cached then
			A = cached.A
		else
			-- per direction: the boundary angle, then the rings' angles by arc length
			A = table.create(M)
			local dA = full and 0.1 or 0.14
			for k = 1, M do
				local ph = PH[k]
				local as, xs, ys, zs = { 0 }, {}, {}, {}
				xs[1], ys[1], zs[1] = exitAt(axx, axy, axz)
				local a = 0
				local aB = nil
				while a < 2.6 do
					a += dA
					local x, y, z = exitAt(dirOf(a, ph))
					if beyond(x, y, z) then
						-- bisect the boundary between the last sample inside and this one
						local lo, hi = a - dA, a
						for _ = 1, 6 do
							local mid = (lo + hi) * 0.5
							local mx, my, mz = exitAt(dirOf(mid, ph))
							if beyond(mx, my, mz) then
								hi = mid
							else
								lo = mid
							end
						end
						aB = lo
						break
					end
					as[#as + 1], xs[#xs + 1], ys[#ys + 1], zs[#zs + 1] = a, x, y, z
				end
				aB = aB or a
				local x, y, z = exitAt(dirOf(aB, ph))
				as[#as + 1], xs[#xs + 1], ys[#ys + 1], zs[#zs + 1] = aB, x, y, z
				-- cumulative arc length, then the ring angles at even arc fractions
				local S = { 0 }
				for i = 2, #as do
					S[i] = S[i - 1] + sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2 + (zs[i] - zs[i - 1]) ^ 2)
				end
				local ring = table.create(R)
				local i = 1
				for j = 1, R do
					local target = S[#S] * j / R
					while i < #S - 1 and S[i + 1] < target do
						i += 1
					end
					local f = S[i + 1] > S[i] and clamp((target - S[i]) / (S[i + 1] - S[i]), 0, 1) or 1
					ring[j] = lerp(as[i], as[i + 1], f)
				end
				ring[R] = aB
				A[k] = { ph = ph, a = ring, len = S[#S] }
				MeshKit.Step(#as * 6)
			end
		end
		do
			local maxLen = 0
			for k = 1, M do
				maxLen = max(maxLen, A[k].len)
			end
			if maxLen < 0.025 then
				return
			end
		end
		-- the vertices: base point = the exit, the relief (faded out over the nose) along the band ray there
		local isle = {}
		local function noseVertex(x, y, z, uvGrid)
			local th = thetaThrough(x, z)
			local c, s = cos(th), sin(th)
			local nx, nz = GB * c, -GA * s
			local nl = sqrt(nx * nx + nz * nz)
			nx, nz = nx / nl, nz / nl
			local d = relief(x, y, z)
			local vi = MeshKit.Vertex(m, x + nx * d, y, z + nz * d, uOf(th), 0)
			rec(vi, x, y, z, nx, 0, nz, 0)
			G.patch[#G.patch + 1] = vi
			if not uvGrid then
				isle[#isle + 1] = vi
			end
			MeshKit.Step(8)
			return vi
		end
		local firstTri = m.nt + 1
		local V = {}
		if not cached then
			-- the exits of the centre and of every ring point
			local pts = table.create(R * M * 3)
			local cx, cy, cz = exitAt(axx, axy, axz)
			for j = 1, R do
				for k = 1, M do
					local d = A[k]
					local x, y, z = exitAt(dirOf(d.a[j], d.ph))
					local o = ((j - 1) * M + k) * 3
					pts[o - 2], pts[o - 1], pts[o] = x, y, z
				end
				MeshKit.Step(M * 4)
			end
			cached = { A = A, pts = pts, c = { cx, cy, cz } }
			F.noseSample[cacheKey] = cached
		end
		local pts = cached.pts
		local centre = noseVertex(cached.c[1], cached.c[2], cached.c[3])
		local polar = { [centre] = { 0, 0 } }
		for j = 1, R do
			local ringV = table.create(M)
			for k = 1, M do
				local d = A[k]
				local o = ((j - 1) * M + k) * 3
				ringV[k] = noseVertex(pts[o - 2], pts[o - 1], pts[o])
				polar[ringV[k]] = { d.ph, d.len * j / R }
			end
			V[j] = ringV
		end
		for k = 1, M do
			tri3(centre, V[1][k % M + 1], V[1][k])
		end
		strips(V, M)
		-- the last ring's twin (grid texture coordinates) and the seam pairs (one normal, one colour)
		local last = V[R]
		local twin = table.create(M)
		G.seams = G.seams or {}
		for k = 1, M do
			local a = last[k]
			twin[k] = noseVertex(G.B[a * 3 - 2], G.B[a * 3 - 1], G.B[a * 3], true)
			P[twin[k] * 3 - 2], P[twin[k] * 3 - 1], P[twin[k] * 3] = P[a * 3 - 2], P[a * 3 - 1], P[a * 3]
			G.seams[#G.seams + 1] = { a, twin[k] }
			-- (the twin takes the field's normal at the same point as its partner: one smooth surface)
		end
		-- the face round the nose's foot: rings by the grid's rays outside the nose's front-view outline, each
		-- point straight out (from the patch's centre) from its last-ring point, past the outline of every patch
		-- vertex near that direction: the rings are star-shaped round the centre (no folds, a clean zip to the
		-- grid) and every point lands on the cheek or the lip, never on the nose
		local zx, zy = 0, 0
		for k = 1, M do
			zx += P[twin[k] * 3 - 2]
			zy += P[twin[k] * 3 - 1]
		end
		zx, zy = zx / M, zy / M
		-- the grid's ray through the front-view point (x, y) near depth z
		local function bandHit(x, y, z)
			local th = thetaThrough(x, z)
			local px, pz
			for pass = 1, 2 do
				local rox, roy, roz, dx, dy, dz = ray({ kind = "band", y = y }, th, yT, yB)
				local t = hit(field, rox, roy, roz, dx, dy, dz, sqrt((x - rox) ^ 2 + (z - roz) ^ 2), 0.05)
				local bx, by, bz = rox + dx * t, roy + dy * t, roz + dz * t
				local tt = t + relief(bx, by, bz)
				px, pz = rox + dx * tt, roz + dz * tt
				if pass == 1 and abs(px - x) > 0.0006 then
					th = thetaThrough(x, pz, th)
				else
					break
				end
			end
			return px, pz
		end
		-- the twins' angles round the centre, made monotonic (the walk round the ring never turns back)
		local ANG = table.create(M)
		do
			local prev = nil
			local turn = 0
			for k = 1, M do
				local t = twin[k]
				local ang = math.atan2(P[t * 3 - 1] - zy, P[t * 3 - 2] - zx)
				if prev then
					local d = ((ang - prev + pi) % TAU) - pi
					turn += d
				end
				prev = ang
				ANG[k] = ang
			end
			local sgn = turn >= 0 and 1 or -1
			local u = table.create(M)
			u[1] = ANG[1]
			for k = 2, M do
				local d = ((ANG[k] - ANG[k - 1] + pi) % TAU) - pi
				u[k] = u[k - 1] + d
			end
			for k = 2, M do
				if (u[k] - u[k - 1]) * sgn < 0.004 then
					u[k] = u[k - 1] + 0.004 * sgn
				end
			end
			ANG = u
		end
		-- the nose's outline radius round the centre at each twin's angle (every patch vertex counts)
		local nAll = {}
		for _, ring in ipairs(V) do
			for _, vi in ipairs(ring) do
				nAll[#nAll + 1] = vi
			end
		end
		local RO = table.create(M, 0)
		for k = 1, M do
			local ca, sa = cos(ANG[k]), sin(ANG[k])
			local best = 0
			for _, vi in ipairs(nAll) do
				local dx, dy = P[vi * 3 - 2] - zx, P[vi * 3 - 1] - zy
				local along = dx * ca + dy * sa
				local across = abs(-dx * sa + dy * ca)
				-- within a narrow cone round this direction
				if along > 0 and across < 0.006 + along * 0.12 then
					best = max(best, along)
				end
			end
			local t = twin[k]
			local tr = (P[t * 3 - 2] - zx) * ca + (P[t * 3 - 1] - zy) * sa
			RO[k] = max(best, tr)
		end
		-- smooth (never inward): the rings are smooth curves round the outline
		for _ = 1, 3 do
			local R2 = table.clone(RO)
			for k = 1, M do
				local a, b = RO[(k - 2) % M + 1], RO[k % M + 1]
				R2[k] = max(RO[k], 0.25 * a + 0.5 * RO[k] + 0.25 * b)
			end
			RO = R2
		end
		-- the face rings: the outer one a rounded rectangle (superellipse) round the nose's front-view outline,
		-- the inner one between it and the outline; downward both stop above the mouth patch (floorY: a grid
		-- row between, the patches never meet). A smooth convex outer ring zips cleanly to the grid
		local outerV = { twin }
		local bandFirst = m.nv + 1
		G.geomN = G.geomN or {}
		local x0, x1, y0, y1 = huge, -huge, huge, -huge
		for _, vi in ipairs(nAll) do
			local x, y = P[vi * 3 - 2], P[vi * 3 - 1]
			x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
		end
		local mg = full and 0.016 or 0.014
		local aR, aL = x1 - zx + mg, zx - x0 + mg
		local bT, bB = y1 - zy + mg, max(zy - floorY, 0.01)
		local pE = 3.5
		local fr = full and { 0.4, 1 } or { 1 }
		local R0, R1 = table.create(M, 0), table.create(M, 0)
		for k = 1, M do
			local t = twin[k]
			local ca, sa = cos(ANG[k]), sin(ANG[k])
			local rt = (P[t * 3 - 2] - zx) * ca + (P[t * 3 - 1] - zy) * sa
			-- (down: the floor caps the smoothed outline and the superellipse alike)
			local rFloor = sa < -0.05 and (zy - floorY) / -sa or huge
			local r0 = max(rt, min(RO[k], rFloor - 0.008))
			local A, Bv = ca >= 0 and aR or aL, sa >= 0 and bT or bB
			local rse = (abs(ca / A) ^ pE + abs(sa / Bv) ^ pE) ^ (-1 / pE)
			R0[k], R1[k] = r0, max(min(rse, rFloor), r0 + 0.004 * #fr)
		end
		for j, f in ipairs(fr) do
			local ringV = table.create(M)
			for k = 1, M do
				local t = twin[k]
				local r = R0[k] + (R1[k] - R0[k]) * f
				local x, y = zx + cos(ANG[k]) * r, zy + sin(ANG[k]) * r
				local px, pz = bandHit(x, y, P[t * 3])
				ringV[k] = patchVertex(px, y, pz)
			end
			outerV[#outerV + 1] = ringV
			MeshKit.Step(M * 6)
		end
		strips(outerV, M)
		-- rings on out to the hole's edge where it lies far beyond the last one (radially, front view)
		local function extend(H, ring)
			local nh = #H
			if nh < 3 then
				return ring
			end
			local HA, HR = table.create(nh), table.create(nh)
			for i, vi in ipairs(H) do
				local dx, dy = P[vi * 3 - 2] - zx, P[vi * 3 - 1] - zy
				HA[i], HR[i] = math.atan2(dy, dx), sqrt(dx * dx + dy * dy)
			end
			-- the hole's radius toward angle a: the nearest loop points in angle, interpolated
			local function holeR(a)
				local best1, best2, i1, i2 = huge, huge, 1, 1
				for i = 1, nh do
					local d = abs(((HA[i] - a + pi) % TAU) - pi)
					if d < best1 then
						best2, i2 = best1, i1
						best1, i1 = d, i
					elseif d < best2 then
						best2, i2 = d, i
					end
				end
				local w = best1 + best2 > 1e-9 and best2 / (best1 + best2) or 1
				return HR[i1] * w + HR[i2] * (1 - w)
			end
			local gap = table.create(M, 0)
			local maxGap = 0
			for k = 1, M do
				local vi = ring[k]
				local dx, dy = P[vi * 3 - 2] - zx, P[vi * 3 - 1] - zy
				local r = sqrt(dx * dx + dy * dy)
				gap[k] = max(0, holeR(math.atan2(dy, dx)) - r)
				maxGap = max(maxGap, gap[k])
			end
			local nExtra = min(3, floor(maxGap / 0.014))
			if nExtra < 1 then
				return ring
			end
			local rings = { ring }
			for e = 1, nExtra do
				local f = e / (nExtra + 1)
				local rv = table.create(M)
				for k = 1, M do
					local vi = ring[k]
					if gap[k] < 0.009 then
						-- the hole's edge is near here: no new vertex (the strip's quad collapses to a triangle)
						rv[k] = vi
					else
						local dx, dy = P[vi * 3 - 2] - zx, P[vi * 3 - 1] - zy
						local r = sqrt(dx * dx + dy * dy)
						local a = math.atan2(dy, dx)
						local rr = r + gap[k] * f
						local x, y = zx + cos(a) * rr, zy + sin(a) * rr
						local px, pz = bandHit(x, y, P[vi * 3])
						rv[k] = patchVertex(px, y, pz)
					end
				end
				rings[#rings + 1] = rv
			end
			strips(rings, M)
			return rings[#rings]
		end
		local hole = finishPatch(firstTri, outerV[#outerV], zx, zy, full and 0.004 or 0.008, extend)
		G.noseIsle, G.nosePolar = isle, polar
		-- the face rings (and their extension out to the hole) and the hole's edge: their normals are blended
		-- across (bandNormals): field normals inside, the grid's outside, no step where they meet
		local outerIsle = {}
		for j = max(1, R - 1), R do
			for _, vi in ipairs(V[j]) do
				outerIsle[#outerIsle + 1] = vi
			end
		end
		G.noseBand = { first = bandFirst, last = m.nv, hole = hole, baseY = NI.baseY, isle = outerIsle }
	end
	buildNose()
	-- drop the grid triangles the patches replaced (their vertices stay until Generate compacts the mesh)
	local nt2 = 0
	for t = 1, m.nt do
		if not dead[t] then
			nt2 += 1
			T[nt2 * 3 - 2], T[nt2 * 3 - 1], T[nt2 * 3] = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		end
	end
	for i = m.nt * 3, nt2 * 3 + 1, -1 do
		T[i] = nil
	end
	m.nt = nt2
	return m
end

-- the nose patch's own texture island (below the head's map, beside the ears): its polar coordinates (the
-- direction round the tip, the arc length out from it) laid out flat
local NOSE_UV = { 0.52, 0.905, 0.68, 0.995 }
local function noseIsland(m)
	local G = m.gridRows
	local isle, polar = G.noseIsle, G.nosePolar
	if not isle then
		return
	end
	local X, Y = {}, {}
	local x0, x1, y0, y1 = huge, -huge, huge, -huge
	for _, vi in ipairs(isle) do
		local pp = polar[vi]
		local px, py = pp[2] * cos(pp[1]), pp[2] * sin(pp[1])
		X[vi], Y[vi] = px, py
		x0, x1, y0, y1 = min(x0, px), max(x1, px), min(y0, py), max(y1, py)
	end
	local s = min((NOSE_UV[3] - NOSE_UV[1]) / max(1e-6, x1 - x0), (NOSE_UV[4] - NOSE_UV[2]) / max(1e-6, y1 - y0))
	local U = m.U
	for _, vi in ipairs(isle) do
		U[vi * 2 - 1] = NOSE_UV[1] + (X[vi] - x0) * s
		U[vi * 2] = NOSE_UV[2] + (y1 - Y[vi]) * s
	end
end

-- the nose patch's outer ring and its twin (grid texture coordinates) are one surface: the same normal, and
-- one colour (each sees only its own triangles when the ambient occlusion is baked)
local function seamNormals(m)
	-- the nose island's edge and its twins (the same points, two texture islands): low down the nose meets the
	-- face in a crease (the alar creases, the subnasale: each side keeps its own normal); higher up, across the
	-- sidewalls and the dorsum, the skin runs on smoothly (one normal: no edge in the shading)
	local G = m.gridRows
	local band = G and G.noseBand
	local N, P = m.N, m.P
	for _, sp in ipairs(G and G.seams or {}) do
		local a, b = sp[1], sp[2]
		local w = band and smoothstep(band.baseY + 0.022, band.baseY + 0.05, P[a * 3 - 1]) or 0
		if w > 0 then
			local ax, ay, az = N[a * 3 - 2], N[a * 3 - 1], N[a * 3]
			local bx, by, bz = N[b * 3 - 2], N[b * 3 - 1], N[b * 3]
			local mx, my, mz = ax + bx, ay + by, az + bz
			local ml = sqrt(mx * mx + my * my + mz * mz)
			if ml > 1e-9 then
				mx, my, mz = mx / ml, my / ml, mz / ml
				for _, v in ipairs({ a, b }) do
					local vx, vy, vz = lerp(N[v * 3 - 2], mx, w), lerp(N[v * 3 - 1], my, w), lerp(N[v * 3], mz, w)
					local vl = sqrt(vx * vx + vy * vy + vz * vz)
					if vl > 1e-9 then
						N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = vx / vl, vy / vl, vz / vl
					end
				end
			end
		end
	end
end

-- the nose's face rings and the grid round them: a few passes of neighbour averaging of the normals over the
-- band (the face rings carry the field's normals, the grid its rows' normals: averaged across the zip they
-- meet without a step). The island's own edge and the grid beyond stay as they are (fixed ends)
local function bandNormals(m)
	local G = m.gridRows
	local band = G and G.noseBand
	if not band or band.last < band.first then
		return
	end
	local inBand = {}
	for i = band.first, band.last do
		inBand[i] = true
	end
	for _, i in ipairs(band.hole or {}) do
		inBand[i] = true
	end
	-- the island's outer rings where the nose runs on smoothly into the face (not down in the alar creases)
	local P = m.P
	for _, i in ipairs(band.isle or {}) do
		if P[i * 3 - 1] > band.baseY + 0.035 then
			inBand[i] = true
		end
	end
	-- and the grid's next ring out round the hole
	do
		local holeSet = {}
		for _, i in ipairs(band.hole or {}) do
			holeSet[i] = true
		end
		local T = m.T
		local gridEnd = G.gridEnd
		for t = 1, m.nt do
			local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
			if holeSet[a] or holeSet[b] or holeSet[c] then
				for _, v in ipairs({ a, b, c }) do
					if v <= gridEnd then
						inBand[v] = true
					end
				end
			end
		end
	end
	-- neighbours (by the triangles that use a band vertex)
	local nb = {}
	local T = m.T
	for t = 1, m.nt do
		local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		for _, e in ipairs({ { a, b, c }, { b, c, a }, { c, a, b } }) do
			local v = e[1]
			if inBand[v] then
				local l = nb[v]
				if not l then
					l = {}
					nb[v] = l
				end
				l[e[2]], l[e[3]] = true, true
			end
		end
		if t % 512 == 0 then
			MeshKit.Step(64)
		end
	end
	local N = m.N
	for _ = 1, 4 do
		local out = {}
		for v, l in pairs(nb) do
			local sx, sy, sz = N[v * 3 - 2], N[v * 3 - 1], N[v * 3]
			for u in pairs(l) do
				sx += N[u * 3 - 2]
				sy += N[u * 3 - 1]
				sz += N[u * 3]
			end
			local sl = sqrt(sx * sx + sy * sy + sz * sz)
			if sl > 1e-9 then
				out[v] = { sx / sl, sy / sl, sz / sl }
			end
		end
		for v, n in pairs(out) do
			N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = n[1], n[2], n[3]
		end
		MeshKit.Step(32)
	end
end
local function seamColours(m)
	local seams = m.gridRows and m.gridRows.seams
	local C = m.C
	for _, s in ipairs(seams or {}) do
		local a, b = s[1], s[2]
		for c = 0, 2 do
			local v = (C[a * 3 - c] + C[b * 3 - c]) * 0.5
			C[a * 3 - c], C[b * 3 - c] = v, v
		end
	end
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
	-- the arc length runs down the full rows (the partial ones across the nose take v by height, below)
	local chain = { [0] = 0 }
	for r = 1, n do
		if not (rows[r] and rows[r].partial) then
			chain[#chain + 1] = r
		end
	end
	local nC = #chain
	local S, W = { [0] = 0 }, { [0] = 0 }
	local bY, cY = F.browY, F.chinY
	for ci = 1, nC do
		local r = chain[ci]
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
		S[ci] = S[ci - 1] + ds
		W[ci] = W[ci - 1] + ds * rho
		MeshKit.Step(8)
	end
	local bandY, bandV = {}, {}
	for ci = 0, nC do
		local r = chain[ci]
		local v = HEAD_V * W[ci] / W[nC]
		local s0 = G.start[r]
		for j = 0, G.count[r] - 1 do
			U[(s0 + j) * 2] = v
		end
		local row = rows[r]
		if row and row.kind == "band" then
			bandY[#bandY + 1], bandV[#bandV + 1] = row.y, v
		end
	end
	-- the patches' vertices and the partial rows' (all in the band: band rays) between the rows by height
	local P = m.P
	local nb = #bandY
	local byHeight = table.clone(G.patch)
	for r = 1, n - 1 do
		if rows[r] and rows[r].partial then
			for j = 0, G.count[r] - 1 do
				byHeight[#byHeight + 1] = G.start[r] + j
			end
		end
	end
	for _, i in ipairs(byHeight) do
		local y = P[i * 3 - 1]
		local lo, hi = 1, nb
		if y >= bandY[1] then
			U[i * 2] = bandV[1]
		elseif y <= bandY[nb] then
			U[i * 2] = bandV[nb]
		else
			while hi - lo > 1 do
				local mid = (lo + hi) // 2
				if bandY[mid] > y then
					lo = mid
				else
					hi = mid
				end
			end
			local t = (bandY[lo] - y) / (bandY[lo] - bandY[hi])
			U[i * 2] = lerp(bandV[lo], bandV[hi], t)
		end
	end
	-- for the texture's noise: arc length at each full row and the face's texels per stud (per unit of v)
	G.arcS, G.arcW, G.arcTotal, G.arcN = S, W, W[nC], nC
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
			row[py + 1] = floor(S[G.arcN] * kv + (wv - total) * kv)
		else
			while r < G.arcN and W[r] < wv do
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
	-- the row above / below for the vertical tangent: full rows look past the partial rows (the same tangent
	-- either side of the partial rows' span: no seam in the shading at its ends); partial rows use their
	-- neighbours within the span
	local function cover(r, u, dir)
		local k = r + dir
		local fromPartial = G.rows[r] and G.rows[r].partial
		while k > 0 and k < G.n do
			local row = G.rows[k]
			if not (row and row.partial) then
				return k
			end
			if fromPartial then
				local s0, n = G.start[k], G.count[k]
				if U[s0 * 2 - 1] <= u + 1e-9 and U[(s0 + n - 1) * 2 - 1] >= u - 1e-9 then
					return k
				end
			end
			k += dir
		end
		return k
	end
	for r = 1, G.n - 1 do
		local s0, n = G.start[r], G.count[r]
		local partialRow = G.rows[r] and G.rows[r].partial
		for j = 0, n - 1 do
			local i = s0 + j
			local jp, jn = j - 1, j + 1
			if jp < 0 then
				jp = partialRow and 0 or n - 2
			end
			if jn > n - 1 then
				jn = partialRow and n - 1 or 1
			end
			local a, b = s0 + jp, s0 + jn
			local tux, tuy, tuz = P[b * 3 - 2] - P[a * 3 - 2], P[b * 3 - 1] - P[a * 3 - 1], P[b * 3] - P[a * 3]
			local u = U[i * 2 - 1]
			local ax, ay, az = rowAt(cover(r, u, -1), u)
			local bx, by, bz = rowAt(cover(r, u, 1), u)
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

-- normals of the grid from the fields themselves: the base field's gradient at the base point, tilted by the
-- tangential gradient of the relief (the displacement along the ray: n (1 + d_t . g) - (d . n) g), so they
-- are as smooth as the shapes (no row-to-row flips from the stitching, no error from the ray-march
-- tolerance). Where the socket reshaped the skin the grid normals stay (blended by how much it did)
local function fieldNormals(m, F)
	local G = m.gridRows
	local B, Dir, SW, EC = G.B, G.Dir, G.SW, G.EC
	local EH, EV = G.EH or {}, G.EV or {}
	local field, relief = F.field, F.relief
	local N = m.N
	local e = 0.0015
	local k4 = 1 / (4 * e)
	-- only the patches' vertices (fine rings: the fields' normals are what their triangles show); the grid's
	-- coarse rows keep the normals of their own geometry (gridNormals): an exact normal on a coarse sampling
	-- disagrees with the triangles it shades, row by row (streaks along the rows)
	local list = G.patch
	local geomN = G.geomN or {}
	for _, i in ipairs(list) do
		if geomN[i] then
			continue
		end
		local bx, by, bz = B[i * 3 - 2], B[i * 3 - 1], B[i * 3]
		local f1 = field(bx + e, by - e, bz - e)
		local f2 = field(bx - e, by - e, bz + e)
		local f3 = field(bx - e, by + e, bz - e)
		local f4 = field(bx + e, by + e, bz + e)
		local nx, ny, nz = f1 - f2 - f3 + f4, -f1 - f2 + f3 + f4, -f1 + f2 - f3 + f4
		local l = sqrt(nx * nx + ny * ny + nz * nz)
		if l > 1e-12 then
			nx, ny, nz = nx / l, ny / l, nz / l
			local gx, gy, gz = 0, 0, 0
			if bz < -0.04 then
				local eh, ev = EH[i] or e, EV[i] or e
				local hl = sqrt(nx * nx + nz * nz)
				if (eh > e * 1.5 or ev > e * 1.5) and hl > 0.2 then
					-- the relief's slope filtered over the grid's sampling: along the row (horizontal tangent)
					-- with the column gap, across the rows with the row gap
					local hx, hz = -nz / hl, nx / hl
					local vx, vy, vz = ny * hz, nz * hx - nx * hz, -ny * hx
					local vl = sqrt(vx * vx + vy * vy + vz * vz)
					vx, vy, vz = vx / vl, vy / vl, vz / vl
					local gh = (relief(bx + hx * eh, by, bz + hz * eh) - relief(bx - hx * eh, by, bz - hz * eh)) / (2 * eh)
					local gv = (relief(bx + vx * ev, by + vy * ev, bz + vz * ev) - relief(bx - vx * ev, by - vy * ev, bz - vz * ev)) / (2 * ev)
					gx, gy, gz = gh * hx + gv * vx, gv * vy, gh * hz + gv * vz
				else
					local r1 = relief(bx + e, by - e, bz - e)
					local r2 = relief(bx - e, by - e, bz + e)
					local r3 = relief(bx - e, by + e, bz - e)
					local r4 = relief(bx + e, by + e, bz + e)
					gx, gy, gz = (r1 - r2 - r3 + r4) * k4, (-r1 - r2 + r3 + r4) * k4, (-r1 + r2 - r3 + r4) * k4
					local gn = gx * nx + gy * ny + gz * nz
					gx, gy, gz = gx - gn * nx, gy - gn * ny, gz - gn * nz
				end
			end
			local dx, dy, dz = Dir[i * 3 - 2], Dir[i * 3 - 1], Dir[i * 3]
			local a = dx * nx + dy * ny + dz * nz
			local k = 1 + (dx - a * nx) * gx + (dy - a * ny) * gy + (dz - a * nz) * gz
			local ox, oy, oz = nx * k - a * gx, ny * k - a * gy, nz * k - a * gz
			local lo = sqrt(ox * ox + oy * oy + oz * oz)
			if lo > 1e-12 then
				ox, oy, oz = ox / lo, oy / lo, oz / lo
				local w = SW[i]
				if w > 0 then
					-- skin laid on an eye's cover sphere: the sphere's own normal (radial from the eyeball)
					local ec = EC[i]
					local sx, sy, sz = N[i * 3 - 2], N[i * 3 - 1], N[i * 3]
					if ec ~= 0 then
						local e = F.eye[ec]
						sx, sy, sz = m.P[i * 3 - 2] - e.x, m.P[i * 3 - 1] - e.y, m.P[i * 3] - e.z
						local sl = sqrt(sx * sx + sy * sy + sz * sz)
						if sl > 1e-9 then
							sx, sy, sz = sx / sl, sy / sl, sz / sl
						end
					end
					ox, oy, oz = lerp(ox, sx, w), lerp(oy, sy, w), lerp(oz, sz, w)
					lo = sqrt(ox * ox + oy * oy + oz * oz)
					if lo > 1e-9 then
						ox, oy, oz = ox / lo, oy / lo, oz / lo
					end
				end
				N[i * 3 - 2], N[i * 3 - 1], N[i * 3] = ox, oy, oz
			end
		end
		-- four field and four relief samples
		MeshKit.Step(16)
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
		angs = { 0, PUPIL_A, IRIS_A, LIMBUS_A, 0.75, 1.2, 1.9 }
	elseif lod == "medium" then
		angs = { 0, IRIS_A, 0.7, 1.3, 2.0 }
	else
		angs = { 0, 0.25, LIMBUS_A, 1.2, 2.2 }
	end
	local sides = lod == "full" and 14 or (lod == "medium" and 8 or 7)
	local ringStart = {}
	for k, ang in ipairs(angs) do
		-- cornea bulge over the iris
		local r = R + 0.0036 * (1 - smoothstep(0.2, 0.62, ang))
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
-- Eyelids: thin shells over the eyeball from the margin to well past the socket rim (hidden there), so a
-- rigid turn about the fissure axis is a blink. The margin is crisp (the wet line, then the lash line),
-- never a rolled rim; a lash fringe stands out of it. Their skin is coloured afterwards from the head's own
-- colours next to them (colourLids), so the lids read as the face's skin, not as rings round the eyes.
------------------------------------------------------------------------
local LID_KIND = { wet = 1, line = 2, skin = 3, hid = 4, lash = 5, tip = 6 }

local function lidMesh(F, side, lower, lod, m)
	local E = eyeFrame(F, side)
	m = m or MeshKit.New(lower and "LidLow" or "Lid")
	local first = m.nv + 1
	local firstTri = m.nt + 1
	local R = F.eyeR
	local sg = lower and -1 or 1
	local rOut = R + (lower and F.lowOut or F.lidOut)
	local full = lod == "full"
	local nA = full and 12 or (lod == "medium" and 8 or 5)
	local deg = math.rad
	local g = math.deg(lower and F.gDn or F.gUp)
	-- profile rows: (elevation offset from the margin in degrees, radius, kind). A thin wedge: the wet line on
	-- the eyeball, the lash line half a millimetre out, a quick round-over to the lid's skin. The skin rows run
	-- on under the head's skin past the rim (the head folds over the upper lid: the crease; it meets the lower
	-- one flush), and the upper lid's hidden rows reach far enough round to cover the eye when it turns shut
	local prof
	if lower then
		if full then
			prof = { { 0, R + 0.001, "wet" }, { 0.4, R + 0.0033, "line" }, { 1.3, R + 0.0052, "skin" }, { g * 0.55, rOut + 0.0002, "skin" }, { g + 2, rOut - 0.0006, "skin" }, { 25, rOut - 0.002, "hid" } }
		else
			prof = { { 0, R + 0.001, "wet" }, { 0.7, R + 0.0038, "line" }, { g * 0.55, rOut, "skin" }, { g + 2, rOut - 0.0006, "skin" }, { 30, rOut - 0.002, "hid" } }
		end
	elseif full then
		-- (the hidden rows come down over the cornea when the lid shuts: they clear its bulge, R + 0.0036, chords
		-- included, and stay well under the brow's skin while the eye is open)
		prof = { { 0, R + 0.001, "wet" }, { 0.4, R + 0.0035, "line" }, { 1.2, R + 0.0052, "skin" }, { g * 0.5, rOut + 0.0002, "skin" }, { g + 2, rOut - 0.0002, "skin" }, { 30, rOut, "hid" }, { 45, rOut - 0.0002, "hid" }, { 60, rOut - 0.0006, "hid" } }
	else
		prof = { { 0, R + 0.001, "wet" }, { 0.7, R + 0.004, "line" }, { g * 0.5, rOut + 0.0002, "skin" }, { g + 2, rOut - 0.0002, "skin" }, { 36, rOut - 0.0001, "hid" }, { 50, rOut - 0.0003, "hid" }, { 62, rOut - 0.0006, "hid" } }
	end
	local np = #prof
	local kinds = m.lidKinds or {}
	m.lidKinds = kinds
	local cols = {}
	local aA, aB = F.aMed - deg(2), F.aLat + deg(2)
	if lower then
		aA, aB = F.aMed - EXT_MED - deg(5), F.aLat + EXT_LAT + deg(5)
		nA = floor(nA * 1.25 + 0.5)
	end
	for i = 0, nA do
		local a = lerp(aA, aB, i / nA)
		local up = marginAt(F, a)
		local bm = lower and lowerEdge(F, a) or up
		cols[i] = m.nv + 1
		for _, p in ipairs(prof) do
			local x, y, z = eyePoint(E, a, bm + sg * deg(p[1]), p[2])
			local vid = MeshKit.Vertex(m, x, y, z, 0.5, 0.5, 0.5, 0.4, 0.35)
			kinds[vid] = LID_KIND[p[3]]
			if p[3] == "skin" or p[3] == "hid" then
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
	-- the lash fringe: a ribbon out of the lash line, leaving the lid forward and curling away from the eye
	-- (up on the upper lid, down on the lower). Its free edge is ragged (smooth noise in length, no comb of
	-- alternating teeth); longest over the outer third, short at the inner corner; the tips take some of the
	-- skin's colour (colourLids: a soft edge, not a cut-out). The lid pieces are double-sided
	local lashK = F.lashes
	if lod ~= "low" and (not lower or lashK > 0.12) then
		local fem = F.female and 1 or 0
		local nL = full and (lower and 12 or 26) or (lower and 0 or 10)
		local len = lower and (0.0035 + 0.003 * lashK) or (0.005 + 0.0015 * fem + 0.0055 * lashK)
		local seed = F.seed + (side > 0 and 7 or 3) + (lower and 11 or 0)
		local r0 = R + (lower and 0.0032 or 0.0034)
		local prevR, prevT
		for i = 0, nL do
			local u = i / max(1, nL)
			local a = lerp(F.aMed + deg(lower and 16 or 8), F.aLat - deg(lower and 6 or 1), u)
			local up, dn = marginAt(F, a)
			local bm = (lower and dn or up) + sg * deg(0.35)
			local centre = clamp(1 - abs(u - 0.66) * 1.45, 0.3, 1)
			local rag = 0.85 + 0.3 * MeshKit.Noise(u * 9, seed * 0.13, 0.5, seed)
			local L = len * (0.45 + 0.65 * centre) * rag
			if i == 0 or i == nL then
				L *= 0.45
			end
			local fan = deg(10) * (u - 0.55) -- fan out toward the corners
			-- the tip: out from the eye by L (forward, off the lid), turned away from it by the curl
			local curl = deg((lower and 3 or 4) + 5 * lashK + 2 * (centre - 0.5))
			local rx, ry, rz = eyePoint(E, a, bm, r0)
			local tx, ty, tz = eyePoint(E, a + fan, bm + sg * curl, r0 + L)
			local vr = MeshKit.Vertex(m, rx, ry, rz, 0.5, 0.5, 0.1, 0.08, 0.07)
			local vt = MeshKit.Vertex(m, tx, ty, tz, 0.5, 0.5, 0.1, 0.08, 0.07)
			kinds[vr], kinds[vt] = LID_KIND.lash, LID_KIND.tip
			if prevR then
				MeshKit.Tri(m, prevR, vr, vt)
				MeshKit.Tri(m, prevR, vt, prevT)
			end
			prevR, prevT = vr, vt
		end
	end
	return m, first
end

-- the sockets' colour (after the vertex paint and the baked AO): the rim, the hidden dive and the first ring
-- take the skin's colour from a little way out (the AO bake reads the dive behind the rim as a ridge), then
-- the socket's shading: the fold's shadow along the upper rim and up into the crease, a softer one under
-- the lower lid, the whole socket a little darker (18-25 % on light skin, 10-15 % on dark: the darkness of
-- the tone carries less), the inner corner pinker
local function shadeSockets(m, F)
	local G = m.gridRows
	if not G or not G.eyes then
		return
	end
	local C = m.C
	local sr, sg, sb = C[1], C[2], C[3]
	local dk = Paint.Darkness(sr, sg, sb)
	local S = lerp(0.24, 0.13, dk) -- the fold's shadow at the rim
	local A = lerp(0.1, 0.05, dk) -- the socket's overall shade
	for side = -1, 1, 2 do
		local e = G.eyes[side]
		if e then
			local V, pts = e.rings, e.pts
			local M = #pts
			local ref = math.min(5, #V)
			for k = 1, M do
				local p = pts[k]
				local rv = V[ref][k]
				local r0, g0, b0 = C[rv * 3 - 2], C[rv * 3 - 1], C[rv * 3]
				for j = 1, ref - 1 do
					local vi = V[j][k]
					C[vi * 3 - 2], C[vi * 3 - 1], C[vi * 3] = r0, g0, b0
				end
				-- per ring: the offset from the rim (studs, nominal)
				for j = 1, #V do
					local vi = V[j][k]
					local o = j <= 2 and 0 or (e.outer[j - 2] * p.reach)
					local uw = p.uw
					local fold = uw * math.exp(-o / 0.0055) + (1 - uw) * 0.45 * math.exp(-o / 0.0035)
					local socket = 1 - smoothstep(0, p.reach, o)
					local k1 = 1 - S * fold - A * socket
					local r, g, b = C[vi * 3 - 2] * k1, C[vi * 3 - 1] * k1 * 0.985, C[vi * 3] * k1 * 0.99
					-- the inner corner: pinker, a little darker
					local lat = p.nx * side
					local inner = smoothstep(0.55, 0.95, -lat) * math.exp(-o / 0.006)
					if inner > 0 then
						r, g, b = lerp(r, r * 1.02, inner), lerp(g, g * 0.86, inner), lerp(b, b * 0.88, inner)
					end
					C[vi * 3 - 2], C[vi * 3 - 1], C[vi * 3] = r, g, b
				end
			end
			local c = e.centre
			local rv = V[1][1]
			C[c * 3 - 2], C[c * 3 - 1], C[c * 3] = C[rv * 3 - 2], C[rv * 3 - 1], C[rv * 3]
		end
	end
end

-- the lids' colours: their skin from the head's own colour right beside them (the socket ring just outside
-- the rim, nearest round the eye), so the lids read as the face's skin, not as rings round the eyes: the
-- upper lid in the fold's shade toward the crease, the lower lid as the skin under it; the wet line pink,
-- the lash line and the lashes the hair's darkest (the lashes' tips toward the lid's skin: a soft edge).
-- Runs before the head is compacted / scaled (nominal positions, the patch rings' ids)
local function colourLids(lids, head, F, look)
	local G = head.gridRows
	local hr, hg, hb = Paint.HairColor(look, F.age, false)
	local lr, lg, lb = lerp(hr * 0.3, 0.045, 0.5), lerp(hg * 0.3, 0.035, 0.5), lerp(hb * 0.3, 0.03, 0.5)
	local C, P = head.C, head.P
	local dk = Paint.Darkness(C[1], C[2], C[3])
	local function skinAt(x, y, z)
		local side = x < 0 and -1 or 1
		local e = G and G.eyes and G.eyes[side]
		if not e then
			return Paint.Skin(look)
		end
		-- the skin a little way out from the rim (the rings by it sit in the socket's shade, which the lid's
		-- own shading supplies): the nearest vertex of the ring half way out, a touch darker
		local ring = e.rings[max(3, #e.rings - 1)]
		local best, bd = ring[1], math.huge
		for _, vi in ipairs(ring) do
			local dx, dy, dz = P[vi * 3 - 2] - x, P[vi * 3 - 1] - y, P[vi * 3] - z
			local d = dx * dx + dy * dy + dz * dz
			if d < bd then
				best, bd = vi, d
			end
		end
		return C[best * 3 - 2] * 0.95, C[best * 3 - 1] * 0.94, C[best * 3] * 0.94
	end
	for _, m in ipairs(lids) do
		local kinds = m.lidKinds or {}
		local Pm = m.P
		for i = 1, m.nv do
			local k = kinds[i]
			if k then
				local x, y, z = Pm[i * 3 - 2], Pm[i * 3 - 1], Pm[i * 3]
				local r, g, b
				local sr, sg, sb = skinAt(x, y, z)
				if k == LID_KIND.lash or k == LID_KIND.line then
					r, g, b = lr, lg, lb
				elseif k == LID_KIND.tip then
					r, g, b = lerp(lr, sr, 0.3), lerp(lg, sg, 0.3), lerp(lb, sb, 0.3)
				elseif k == LID_KIND.wet then
					r, g, b = lerp(sr, lerp(0.74, 0.42, dk), 0.6) * 0.92, lerp(sg, lerp(0.42, 0.25, dk), 0.6) * 0.92, lerp(sb, lerp(0.41, 0.24, dk), 0.6) * 0.92
				else
					-- the rim ring is already in the fold's shade: the lid under it a little more toward the
					-- crease, its margin edge as the skin
					local e = F.eye[x < 0 and -1 or 1]
					local above = y > e.y
					local kk = above and (k == LID_KIND.hid and 0.9 or 0.96) or 1.0
					r, g, b = sr * kk, sg * kk * 0.99, sb * kk
				end
				MeshKit.SetColor(m, i, clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1))
			end
		end
		MeshKit.Step(m.nv)
	end
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

-- distance from (u, v) to the segment a-b (2D)
local function segDist(u, v, au, av, bu, bv)
	local vx, vy = bu - au, bv - av
	local wx, wy = u - au, v - av
	local l2 = vx * vx + vy * vy
	local t = l2 > 0 and clamp((wx * vx + wy * vy) / l2, 0, 1) or 0
	local dx, dy = wx - vx * t, wy - vy * t
	return sqrt(dx * dx + dy * dy)
end

-- the ear: a closed pillow in the ear's own plane. The outline is a C (fuller at the top, the lobule narrower,
-- the front edge straighter with the notch between the tragus and the lobule); the outer face carries the
-- helix rolled along the rim from the front top round the back to the lobule, the scapha's groove inside it,
-- the antihelix (a stem up the back forking into the upper and lower crura round the triangular fossa), the
-- deep concha with the helix's root across its top, the tragus and the antitragus, the soft lobule. m.earK
-- keeps each vertex's shading factor (the rim and the bowl redder / darker): its colour is the cheek's,
-- set once the face is painted (Generate)
local function earMesh(F, side, lod, skin, m, uvBox)
	m = m or MeshKit.New("Ear")
	local first = m.nv + 1
	local firstTri = m.nt + 1
	local cauli = F.cauli
	local c0, nx, nz, px, py, pz, qx, qy, qz, H, W = earFrame(F, side, lod)
	local ocx, ocy, ocz = c0[1], c0[2], c0[3]
	local function outline(w)
		local c, sn = cos(w), sin(w)
		local r = 1 / sqrt((c / W) ^ 2 + (sn / H) ^ 2)
		if sn < 0 then
			r *= 1 - 0.2 * sn * sn -- the lobule is narrower
		end
		if c < 0 then
			r *= 1 - 0.1 * c * c -- the front edge is straighter
		end
		-- the intertragic notch (front, low)
		local dn = ((w + pi) % TAU) - pi -- w in [-pi, pi)
		local nq = ((dn - (-2.25)) / 0.22) ^ 2
		if nq < 1 then
			r *= 1 - 0.1 * bump(nq)
		end
		return r
	end
	-- the antihelix's polyline (normalized ear coords: u back, v up; the outline at radius ~1)
	local AH = { { 0.14, -0.5 }, { 0.44, -0.1 }, { 0.5, 0.22 }, { 0.36, 0.48 } } -- stem, up the back
	local SUP = { { 0.36, 0.48 }, { 0.12, 0.74 } } -- upper crus, toward the top rim
	local INF = { { 0.36, 0.48 }, { -0.18, 0.4 } } -- lower crus, forward over the concha
	local CRUS = { { -0.72, 0.22 }, { -0.3, 0.12 } } -- the helix's root across the concha's top
	local function outer(rho, w)
		local u, v = rho * cos(w), rho * sin(w)
		local h = 0
		-- the helix: from the front top over the top and down the back, fading out above the lobule
		local dn = ((w + pi) % TAU) - pi
		local along = smoothstep(-1.45, -0.95, dn) * (1 - smoothstep(2.45, 2.75, dn))
		local dr = 1 - rho
		h += 0.026 * along * bump(((dr - 0.07) / 0.085) ^ 2)
		-- the scapha inside it
		h -= 0.013 * along * bump(((dr - 0.22) / 0.075) ^ 2)
		-- the antihelix and its crura
		local da = min(segDist(u, v, AH[1][1], AH[1][2], AH[2][1], AH[2][2]), segDist(u, v, AH[2][1], AH[2][2], AH[3][1], AH[3][2]), segDist(u, v, AH[3][1], AH[3][2], AH[4][1], AH[4][2]))
		local ds = segDist(u, v, SUP[1][1], SUP[1][2], SUP[2][1], SUP[2][2])
		local di = segDist(u, v, INF[1][1], INF[1][2], INF[2][1], INF[2][2])
		h += 0.018 * bump((da / 0.15) ^ 2) + 0.012 * bump((ds / 0.12) ^ 2) + 0.012 * bump((di / 0.12) ^ 2)
		-- the triangular fossa between the crura
		h -= 0.007 * bump(((u - 0.12) / 0.16) ^ 2 + ((v - 0.56) / 0.14) ^ 2)
		-- the concha: the deep bowl, the helix's root across its top
		local cq = ((u + 0.12) / 0.38) ^ 2 + ((v + 0.1) / 0.38) ^ 2
		h -= 0.045 * bump(cq)
		h += 0.011 * bump((segDist(u, v, CRUS[1][1], CRUS[1][2], CRUS[2][1], CRUS[2][2]) / 0.12) ^ 2)
		-- tragus (front, over the canal) and antitragus (back, above the lobule)
		h += 0.017 * bump(((u + 0.66) / 0.17) ^ 2 + ((v + 0.16) / 0.22) ^ 2)
		h += 0.013 * bump(((u - 0.08) / 0.18) ^ 2 + ((v + 0.52) / 0.16) ^ 2)
		-- the lobule: soft, a little full
		h += 0.005 * bump((u / 0.38) ^ 2 + ((v + 0.8) / 0.2) ^ 2)
		-- cauliflower: the upper rim and the scapha fill and lump up
		if cauli > 0.05 then
			local lump = 0.5 + 0.5 * sin(w * 5 + F.seed % 7) * cos(rho * 9)
			h += cauli * (0.012 * smoothstep(0.35, 0.8, rho) * smoothstep(-0.2, 0.6, sin(w)) * (0.6 + 0.6 * lump))
		end
		return h
	end
	local full = lod == "full"
	local nW = full and 18 or (lod == "medium" and 10 or 5)
	local outerR = full and { 0.25, 0.45, 0.62, 0.76, 0.87, 0.95 } or (lod == "medium" and { 0.5, 0.85 } or { 0.6 })
	local thick = 0.008 + 0.01 * cauli
	local function place(rho, w, hOut)
		local r = rho * outline(w)
		local lp, lq = r * cos(w), r * sin(w)
		return ocx + px * lp + qx * lq + nx * hOut, ocy + py * lp + qy * lq, ocz + pz * lp + qz * lq + nz * hOut
	end
	-- texture: the front's disc in the box's first two thirds, the back's (from the rim's back edge to the back
	-- pole) in the rest: no texel is shared by both sides (one would show the other's shading)
	local function uv(rho, w, back)
		local u = 0.5 + 0.5 * rho * cos(w) * side
		local v = 0.5 - 0.5 * rho * sin(w)
		u = back and (0.7 + 0.3 * u) or (0.68 * u)
		return uvBox[1] + (uvBox[3] - uvBox[1]) * u, uvBox[2] + (uvBox[4] - uvBox[2]) * v
	end
	local cr, cg, cb = skin[1], skin[2], skin[3]
	local K = m.earK or {}
	m.earK = K
	-- the shading factor: the rim and the bowl a little redder / darker
	local function shadeK(rho, w, back)
		local u, v = rho * cos(w), rho * sin(w)
		local bowl = back and 0 or bump(((u + 0.12) / 0.36) ^ 2 + ((v + 0.1) / 0.36) ^ 2)
		return 1 - 0.08 * smoothstep(0.75, 1, rho) - 0.2 * bowl
	end
	local rings = {}
	local pole = MeshKit.Vertex(m, 0, 0, 0)
	do
		local x, y, z = place(0, 0, outer(0, 0) + thick * 0.5)
		MeshKit.SetPosition(m, pole, x, y, z)
		local u, v = uv(0, 0)
		MeshKit.SetUV(m, pole, u, v)
		local k = shadeK(0, 0)
		K[pole] = k
		MeshKit.SetColor(m, pole, cr * k, cg * k * 0.94, cb * k * 0.92)
	end
	rings[#rings + 1] = { pole = pole }
	local function ring(rho, hfn, back, uvBack)
		local start = m.nv + 1
		for j = 0, nW - 1 do
			local w = TAU * j / nW
			local x, y, z = place(rho, w, hfn(rho, w))
			local u, v = uv(rho, w, uvBack)
			local k = shadeK(rho, w, back)
			local vi = MeshKit.Vertex(m, x, y, z, u, v, cr * k, cg * k * 0.94, cb * k * 0.92)
			K[vi] = k
		end
		rings[#rings + 1] = { start = start }
		MeshKit.Step(nW * 2) -- the relief functions are not cheap: let AnatomyClient yield between rings
	end
	for _, rr in ipairs(outerR) do
		ring(rr, function(rho, w)
			return outer(rho, w) + thick * 0.5
		end)
	end
	-- the rim: the helix rolls over the edge (a little behind the mid-plane where the helix runs)
	local function rimH(rho, w)
		local dn = ((w + pi) % TAU) - pi
		local along = smoothstep(-1.45, -0.95, dn) * (1 - smoothstep(2.45, 2.75, dn))
		return 0.004 * along
	end
	ring(1.0, rimH)
	-- the back: from a twin of the rim (the back's texture coordinates; one normal with it, earSeams) to the
	-- back pole
	local front = rings
	rings = {}
	ring(1.0, rimH, false, true)
	m.earSeams = m.earSeams or {}
	for j = 0, nW - 1 do
		m.earSeams[#m.earSeams + 1] = { front[#front].start + j, rings[1].start + j }
	end
	ring(0.6, function(rho)
		-- the back bulges behind the concha (the bowl is deep)
		return -(thick * 0.5 + 0.024 * (1 - rho * rho) + 0.034 * bump((rho / 0.6) ^ 2))
	end, true, true)
	local bp = MeshKit.Vertex(m, 0, 0, 0)
	do
		local x, y, z = place(0, 0, -(thick * 0.5 + 0.06))
		MeshKit.SetPosition(m, bp, x, y, z)
		local u, v = uv(0, 0, true)
		MeshKit.SetUV(m, bp, u, v)
		K[bp] = 1
		MeshKit.SetColor(m, bp, cr, cg, cb)
	end
	rings[#rings + 1] = { pole = bp }
	for _, list in ipairs({ front, rings }) do
		for i = 1, #list - 1 do
			local A, B = list[i], list[i + 1]
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
	end
	-- outward: away from the ear's own centre plane
	MeshKit.OrientFrom(m, ocx, ocy, ocz, firstTri, m.nt)
	return m, first
end

------------------------------------------------------------------------
-- Generate
------------------------------------------------------------------------
-- drops the vertices no triangle uses (the grid's under the patches), everything per vertex kept in step;
-- returns the number of kept vertices among the first `upTo`
local function compactMesh(m, upTo)
	local T = m.T
	local nv, nt = m.nv, m.nt
	local used = table.create(nv, false)
	for i = 1, nt * 3 do
		used[T[i]] = true
	end
	local map = table.create(nv, 0)
	local P, N, U, C, A = m.P, m.N, m.U, m.C, m.A
	local n, keptUpTo = 0, 0
	for i = 1, nv do
		if used[i] then
			n += 1
			map[i] = n
			if i <= upTo then
				keptUpTo = n
			end
			if n ~= i then
				P[n * 3 - 2], P[n * 3 - 1], P[n * 3] = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
				N[n * 3 - 2], N[n * 3 - 1], N[n * 3] = N[i * 3 - 2], N[i * 3 - 1], N[i * 3]
				C[n * 3 - 2], C[n * 3 - 1], C[n * 3] = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
				U[n * 2 - 1], U[n * 2] = U[i * 2 - 1], U[i * 2]
				if A then
					A[n] = A[i]
				end
			end
		else
			map[i] = 0
		end
	end
	MeshKit.Step(nv // 8)
	if n == nv then
		return keptUpTo
	end
	for i = nv * 3, n * 3 + 1, -1 do
		P[i], N[i], C[i] = nil, nil, nil
	end
	for i = nv * 2, n * 2 + 1, -1 do
		U[i] = nil
	end
	if A then
		for i = nv, n + 1, -1 do
			A[i] = nil
		end
	end
	for i = 1, nt * 3 do
		T[i] = map[T[i]]
	end
	MeshKit.Step(nt // 8)
	if m.W then
		for k, w in pairs(m.W) do
			local nw = table.create(n, 0)
			for i = 1, nv do
				if map[i] > 0 then
					nw[map[i]] = w[i] or 0
				end
			end
			m.W[k] = nw
		end
	end
	for k, g in pairs(m.groups) do
		local ng = {}
		for _, i in ipairs(g) do
			if map[i] > 0 then
				ng[#ng + 1] = map[i]
			end
		end
		m.groups[k] = ng
	end
	if m.morphs then
		for _, mo in pairs(m.morphs) do
			local ids, d = {}, {}
			for k, i in ipairs(mo.ids) do
				local j = map[i]
				if j > 0 then
					local c = #ids + 1
					ids[c] = j
					d[c * 3 - 2], d[c * 3 - 1], d[c * 3] = mo.d[k * 3 - 2], mo.d[k * 3 - 1], mo.d[k * 3]
				end
			end
			mo.ids, mo.d = ids, d
			MeshKit.Step(#ids // 8)
		end
	end
	m.nv = n
	return keptUpTo
end

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
Gen.TEXTURE = { full = 384, medium = 128, low = 64 }
Gen.EYE_TEXTURE = { full = 96 }
Gen.BEARD_TEXTURE = { full = 384, medium = 128 }


-- a point on the face: the ray from inside the head straight forward through (x, y), base field + relief
local function surfaceFn(F)
	return function(x, y)
		local t = hit(F.field, x, y, ZA, 0, 0, -1, 0.42)
		local z = ZA - t
		return x, y, z - F.relief(x, y, z)
	end
end

-- where the head takes the Body's skin tone: under the jaw and on the neck. The Body's neck column meets the
-- head under the jaw (a little outside the head's own neck), and the face's tone there (undertone, beard
-- shadow, stubble, baked occlusion) made that seam a darker, redder line. 0 at the jaw's lower border and
-- above it (the face keeps its own tone) .. 1 on the neck column (nominal coordinates)
local function neckToneFn(F)
	local _, border = lowerFaceSlices(F)
	local neckCol, neckP = Skull.NeckSD, F.P.neck
	return function(x, y, z)
		local below = border(z) - y
		if below <= 0.005 then
			return 0
		end
		local dN = neckCol(neckP, x, y, z)
		if dN >= 0.16 then
			return 0
		end
		return smoothstep(0.005, 0.05, below) * (1 - smoothstep(0.04, 0.16, dN))
	end
end

local function prepare(look)
	local F = layout(look)
	F.face = baseField(F)
	F.field = noseField(F, F.face)
	F.relief = reliefFn(F)
	F.neckTone = neckToneFn(F)
	return F
end

Gen._internal = function()
	return {
		layout = layout, baseField = baseField, reliefFn = reliefFn, hit = hit, ray = ray, eyeFrame = eyeFrame, eyeAngles = eyeAngles,
		rimAt = rimAt, raySphere = raySphere, lowerFaceSlices = lowerFaceSlices, prepare = prepare, surfaceFn = surfaceFn,
	}
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
-- low detail has no eyeball / lid pieces: its texture paints the eyes (per texel, from the eye's own angles):
-- a shadowed socket, the white barely showing, a dark iris and pupil, the upper lash line. Returns a
-- function(x, y, z) -> r, g, b, a (nil away from the eyes) for Paint.Texture
local function lowEyePainter(F, look)
	-- the white a little dimmer on deep skin tones (against a dark face a mid grey already reads as the white)
	local wk = 0.5 - 0.12 * Paint.Darkness(Paint.Skin(look))
	local eyes = {}
	for side = -1, 1, 2 do
		local iris, white = eyeColors(F, look, side)
		eyes[#eyes + 1] = { E = eyeFrame(F, side), iris = iris, white = white }
	end
	return function(x, y, z)
		for _, ey in ipairs(eyes) do
			local E = ey.E
			if z < E.cz and abs(x - E.cx) < 0.085 and abs(y - E.cy) < 0.07 then
				local a, b = eyeAngles(E, x, y, z)
				local up, dn = marginAt(F, a)
				local a0, a1 = F.aMed - 0.12, F.aLat + 0.12
				if a > a0 - 0.3 and a < a1 + 0.3 and b < up + 0.45 and b > dn - 0.3 then
					-- the socket's shade round the opening (deeper above, under the brow)
					local ea = max(0, max(a0 - a, a - a1))
					local eb = b > up and (b - up) / 0.42 or (b < dn and (dn - b) / 0.28 or 0)
					local q = (ea / 0.3) ^ 2 + eb * eb
					local shade = q < 1 and 0.28 * (1 - q) or 0
					if a > F.aMed and a < F.aLat and b < up and b > dn then
						-- the opening: white in shadow, the iris and the pupil
						local r = sqrt(a * a + b * b)
						-- (from afar the white is mostly in the lids' shadow: a bright texel would glow)
						local cr, cg, cb = ey.white[1] * wk, ey.white[2] * wk * 0.96, ey.white[3] * wk * 0.94
						if r < IRIS_A then
							local pk = r < PUPIL_A * 1.3 and 0.25 or 1
							cr, cg, cb = ey.iris[1] * 0.7 * pk, ey.iris[2] * 0.7 * pk, ey.iris[3] * 0.7 * pk
						end
						-- the upper lid's shadow and lashes over the top of the opening
						local lash = smoothstep(up - 0.12, up - 0.02, b)
						cr, cg, cb = lerp(cr, 0.07, lash), lerp(cg, 0.05, lash), lerp(cb, 0.04, lash)
						return cr, cg, cb, 1
					end
					-- the lash line just over the margin
					if b >= up and b < up + 0.07 and a > F.aMed - 0.05 and a < F.aLat + 0.08 then
						return 0.08, 0.055, 0.045, 0.85 * (1 - (b - up) / 0.07)
					end
					if shade > 0 then
						return 0.2, 0.13, 0.11, shade
					end
				end
			end
		end
		return nil
	end
end

-- the low head's vertex colours with the painted eyes averaged in (a copy; m.C is kept for the texture)
local function lowEyeColours(m, F, pscale, n)
	local pe = F.paintEyes
	local P, C = m.P, table.clone(m.C)
	local psx, psy, psz = pscale[1], pscale[2], pscale[3]
	local eL, eR = F.eye[-1], F.eye[1]
	local S = 0.045 -- the neighbourhood's half size (about half the grid's spacing round the eyes)
	for i = 1, min(n, m.nv) do
		local x, y, z = P[i * 3 - 2] * psx, P[i * 3 - 1] * psy, P[i * 3] * psz
		local e = x < 0 and eL or eR
		if z < e.z and abs(x - e.x) < 0.13 and abs(y - e.y) < 0.11 then
			local sr, sg, sb, sa = 0, 0, 0, 0
			for a = -2, 2 do
				for b = -2, 2 do
					local er, eg, eb, ea = pe(x + a * S * 0.5, y + b * S * 0.5, z)
					if er then
						sr += er * ea
						sg += eg * ea
						sb += eb * ea
						sa += ea
					end
				end
			end
			if sa > 0 then
				local k = min(1, sa / 25 * 1.15)
				local i3 = i * 3
				C[i3 - 2] = lerp(C[i3 - 2], sr / sa, k)
				C[i3 - 1] = lerp(C[i3 - 1], sg / sa, k)
				C[i3] = lerp(C[i3], sb / sa, k)
			end
			MeshKit.Step(25)
		end
	end
	return C
end

-- share of the head grid's triangles each beard style adds (for the budget)
local BEARD_SHARE = {
	Moustache = 0.05, Goatee = 0.1, ["Van Dyke"] = 0.1, ["Circle Beard"] = 0.13, ["Chin Strap"] = 0.1,
	["Mutton Chops"] = 0.2, ["Short Boxed"] = 0.3, ["Full Beard"] = 0.32,
}

-- a colour texture made when it is asked for: { w, h, make = fn() -> RGBA8 buffer } (the Body's form).
-- AnatomyClient calls make() on its worker thread only when textures are on for this client: an ordinary call,
-- so MeshKit's tick may yield while the texture is shaded. The buffer is kept once made (rawset .buffer: a cached
-- generation reused by a rebuild or an LOD switch does not paint again, and the cache can count it).
-- Tools and tests may read .buffer: that read goes through __index, which cannot yield in Luau, so the tick is
-- suspended for it (never read it where the tick may yield: call make)
local function lazyTexture(w, h, paint)
	local tex = { w = w, h = h }
	tex.make = function()
		local buf = rawget(tex, "buffer")
		if buf == nil then
			buf = paint()
			rawset(tex, "buffer", buf)
		end
		return buf
	end
	return setmetatable(tex, {
		__index = function(t, k)
			if k ~= "buffer" then
				return nil
			end
			local tickFn = MeshKit.GetTick()
			MeshKit.SetTick(nil)
			local ok, buf = pcall(t.make)
			MeshKit.SetTick(tickFn)
			if not ok then
				error(buf, 0)
			end
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
			local lid = lidMesh(F, side, false, lod)
			MeshKit.ComputeNormals(lid, { crease = 60 })
			pieces["Eye" .. tag] = { mesh = em, attach = "Head", reflectance = 0.1 }
			pieces["Lid" .. tag] = { mesh = lid, attach = "Head", doubleSided = true, material = "Plastic" }
			used += em.nt + lid.nt
		end
		local low = lidMesh(F, -1, true, lod)
		lidMesh(F, 1, true, lod, low)
		MeshKit.ComputeNormals(low, { crease = 60 })
		pieces.LidLow = { mesh = low, attach = "Head", doubleSided = true, material = "Plastic" }
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
		lidMesh(F, -1, true, lod, eyes)
		lidMesh(F, 1, true, lod, eyes)
		MeshKit.ComputeNormals(eyes, { crease = 60 })
		pieces.Eyes = { mesh = eyes, attach = "Head", reflectance = 0.06 }
		local lids = lidMesh(F, -1, false, lod)
		lidMesh(F, 1, false, lod, lids)
		MeshKit.ComputeNormals(lids, { crease = 60 })
		pieces.LidUpper = { mesh = lids, attach = "Head", doubleSided = true, material = "Plastic" }
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
	-- every beard is painted into the head's texture (hair strands thinning into the skin: no cut edge); at
	-- full the fuller styles also get a shell over their dense core (its edge sinks under the painted beard)
	local shellBeard = full and style and Rig.BEARDS[style] and Rig.BEARDS[style].shell and true or false
	local share = shellBeard and BEARD_SHARE[style] or 0
	local target = (budget - used) / (1 + share) * 0.985
	local q = Gen.GRID_Q[lod] or 1
	-- the grid's triangles go ~ q^2, in steps (rows and columns are whole): the cheap count (gridTris) finds
	-- the densest q whose grid + patches (X) fits tgt before anything is built
	local function fitQ(q0, X, tgt)
		local g = gridTris(F, q0, false)
		if g + X <= tgt then
			return q0
		end
		-- down in steps to a fit, then halve the gap to the last miss a few times (the densest fit near it)
		local hi, qq = q0, q0
		for _ = 1, 12 do
			qq *= min(0.985, sqrt(max(0.05, (tgt - X) / g)) * 0.995)
			g = gridTris(F, qq, false)
			if g + X <= tgt then
				for _ = 1, 3 do
					local mid = (qq + hi) * 0.5
					if gridTris(F, mid, false) + X <= tgt then
						qq = mid
					else
						hi = mid
					end
				end
				return qq
			end
			hi = qq
		end
		return qq
	end
	q = fitQ(q, PATCH_TRIS[lod] or 0, target)
	mark("estimate")
	local head = headSurface(F, q, lod)
	-- the estimate is coarse and the beard's share depends on the face: count the real triangles (the beard
	-- takes every grid triangle with a covered corner, Rig.BeardMesh); over: rebuild coarser (the patches'
	-- real share now known); well under: one denser rebuild, kept if it fits
	local mask = shellBeard and Rig.BeardMask(F, style)
	local function beardExtra(h)
		if not mask then
			return 0
		end
		local P, T = h.P, h.T
		local cov = {}
		for i = 1, h.nv do
			local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
			cov[i] = z < 0.2 and y < F.noseBaseY + 0.02 and y > F.chinY - 0.25 and mask(x, y, z) > 0.002
			MeshKit.Step(1)
		end
		local extra = 0
		for t = 1, h.nt do
			if cov[T[t * 3 - 2]] or cov[T[t * 3 - 1]] or cov[T[t * 3]] then
				extra += 1
			end
		end
		return extra
	end
	local extra = beardExtra(head)
	for attempt = 1, 3 do
		local total = used + head.nt + extra
		local Xr = head.nt - gridTris(F, q, false)
		local tgt = (budget - used) / (1 + extra / max(1, head.nt))
		if total <= budget then
			if attempt == 1 and total < budget * 0.965 then
				-- the densest q the real patch share allows (the count's steps make it a search)
				local qUp = q * sqrt(max(1, (tgt * 0.985 - Xr) / max(1, head.nt - Xr)))
				local q2 = fitQ(qUp, Xr, tgt * 0.985)
				if q2 > q * 1.01 then
					local h2 = headSurface(F, q2, lod)
					local e2 = beardExtra(h2)
					if used + h2.nt + e2 <= budget then
						head, q, extra = h2, q2, e2
					end
				end
			end
			break
		end
		q = fitQ(q * 0.99, Xr, tgt * (attempt < 2 and 0.985 or 0.95))
		head = headSurface(F, q, lod)
		extra = beardExtra(head)
	end
	mark("grid")
	assignV(head, F)
	noseIsland(head)
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
	fieldNormals(head, F)
	seamNormals(head)
	bandNormals(head)
	-- the ears' rim twins: one normal (the helix rolls round smoothly)
	do
		local N = head.N
		for _, sp in ipairs(head.earSeams or {}) do
			local a, b = sp[1], sp[2]
			local x, y, z = N[a * 3 - 2] + N[b * 3 - 2], N[a * 3 - 1] + N[b * 3 - 1], N[a * 3] + N[b * 3]
			local l = sqrt(x * x + y * y + z * z)
			if l > 1e-9 then
				x, y, z = x / l, y / l, z / l
				N[a * 3 - 2], N[a * 3 - 1], N[a * 3] = x, y, z
				N[b * 3 - 2], N[b * 3 - 1], N[b * 3] = x, y, z
			end
		end
		head.earSeams = nil
	end
	mark("normals")
	Paint.Vertex(head, F, look, 1, gridN)
	-- the ears take the cheek's colour beside them (a touch redder), shaded by their own folds
	do
		local P, C, K = head.P, head.C, head.earK or {}
		for _, e in ipairs(ears) do
			local c = e.centre
			local tx, ty, tz = c[1] - e.side * 0.03, c[2] + 0.01, c[3] - 0.13
			local best, bd = 1, huge
			for i = 1, gridN do
				local dx, dy, dz = P[i * 3 - 2] - tx, P[i * 3 - 1] - ty, P[i * 3] - tz
				local d = dx * dx + dy * dy + dz * dz
				if d < bd then
					best, bd = i, d
				end
			end
			local r0, g0, b0 = C[best * 3 - 2] * 1.04, C[best * 3 - 1] * 0.97, C[best * 3] * 0.97
			for i = e.first, e.last do
				local k = K[i] or 1
				local red = 1 - k -- the rim and the bowl: redder as they darken
				C[i * 3 - 2] = clamp(r0 * (k + 0.35 * red), 0, 1)
				C[i * 3 - 1] = clamp(g0 * k, 0, 1)
				C[i * 3] = clamp(b0 * k * 0.98, 0, 1)
			end
			MeshKit.Step(gridN // 8)
		end
		head.earK = nil
	end
	if lod == "low" then
		-- no eye pieces: the texture paints them
		F.paintEyes = lowEyePainter(F, look)
		-- in the 64^2 texture a texel is ~0.02 studs, about the eye opening's height: each texel takes the painted
		-- eye's average over its footprint (3 x 3 samples), so the opening reads as a soft dark almond with the
		-- iris in it. A point sample caught the white alone, a bright slit
		local pe, hs = F.paintEyes, 0.007
		F.paintEyesTex = function(x, y, z)
			local sr, sg, sb, sa = 0, 0, 0, 0
			for a = -1, 1 do
				for b = -1, 1 do
					local er, eg, eb, ea = pe(x + a * hs, y + b * hs, z)
					if er then
						sr += er * ea
						sg += eg * ea
						sb += eb * ea
						sa += ea
					end
				end
			end
			if sa <= 0 then
				return nil
			end
			return sr / sa, sg / sa, sb / sa, sa / 9
		end
	end
	mark("paint")
	MeshKit.BakeAO(head, { cavity = 0.45, ridge = 0.06, down = 0.1, cavityScale = 5 })
	shadeSockets(head, F)
	seamColours(head)
	-- under the jaw and down the neck: toward the Body's skin (its base colour: no undertone, no shadow, no
	-- baked occlusion), so the seam with the Body's neck column is not a line (F.neckTone)
	do
		local br0, bg0, bb0 = Paint.BodySkin(look)
		local P, C, wt = head.P, head.C, F.neckTone
		for i = 1, gridN do
			local w = wt(P[i * 3 - 2], P[i * 3 - 1], P[i * 3])
			if w > 0 then
				C[i * 3 - 2] = lerp(C[i * 3 - 2], br0, w)
				C[i * 3 - 1] = lerp(C[i * 3 - 1], bg0, w)
				C[i * 3] = lerp(C[i * 3], bb0, w)
			end
		end
		MeshKit.Step(gridN // 4)
	end
	mark("ao")
	-- the lids take the colour of the skin right beside them
	do
		local lids = {}
		for _, name in ipairs({ "LidL", "LidR", "LidLow", "LidUpper", "Eyes" }) do
			if pieces[name] then
				lids[#lids + 1] = pieces[name].mesh
			end
		end
		if #lids > 0 then
			colourLids(lids, head, F, look)
		end
	end
	-- the beard grows from the finished grid (positions, normals)
	local beard, beardStyle, beardQ
	if shellBeard then
		beard, beardStyle, beardQ = Rig.BeardMesh(head, F, look, gridN, lod)
	end
	mark("beard")
	if full then
		Rig.AddFaceMorphs(head, F, 1, gridN, ears)
	end
	mark("morphs")
	head.gridRows = nil
	-- the grid's vertices under the patches go (no triangle uses them)
	gridN = compactMesh(head, gridN)
	-- to the Head part's size
	for _, piece in pairs(pieces) do
		scaleMesh(piece.mesh, P)
	end
	scaleMesh(head, P)
	Rig.BoxSafe(head)
	-- matte skin (SmoothPlastic reads as lacquer; the body's skin is Plastic too)
	local headPiece = { mesh = head, material = "Plastic" }
	-- low detail: the texture paints the eyes (no eyeball pieces); a client without textures shows the vertex
	-- colours, so they get the eyes too, each vertex the painted eyes' average over its neighbourhood (the
	-- grid is too coarse for their shapes, not for their tone). The texture paints from the plain colours
	local plainC = head.C
	if lod == "low" and F.paintEyes then
		head.C = lowEyeColours(head, F, pscale, gridN)
	end
	if texSize then
		-- made on first use: AnatomyClient calls texture.make only when textures are on for this client (never
		-- paid for otherwise); deterministic, so a later make gives the same pixels
		headPiece.texture = lazyTexture(texSize, texSize, function()
			local cur = head.C
			head.C = plainC
			local buf = Paint.Texture(head, F, look, texSize, texSize, HEAD_V * texSize, pscale, colMap, rowMap)
			head.C = cur
			if style and Rig.BEARDS[style] then
				-- the beard painted over the skin (the shell's strands, on the head's own texture). It thins out on
				-- the neck (F.neckTone): the Body's neck column meets the head there and grows no beard
				local bm0, nt = Rig.BeardMask(F, style), F.neckTone
				local function bm(x, y, z)
					local c = bm0(x, y, z)
					if c > 0 then
						c *= 1 - nt(x, y, z)
					end
					return c
				end
				local Ph = head.P
				local Qh = table.create(head.nv, 0)
				for i = 1, head.nv do
					local x, y, z = Ph[i * 3 - 2] * pscale[1], Ph[i * 3 - 1] * pscale[2], Ph[i * 3] * pscale[3]
					if z < 0.2 and y < F.noseBaseY + 0.02 and y > F.chinY - 0.25 then
						Qh[i] = bm(x, y, z)
						MeshKit.Step(2)
					end
				end
				buf = Paint.BeardTexture(head, Qh, buf, texSize, texSize, F, look, texSize, texSize, pscale, bm, true)
			end
			return buf
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
	mark("lids")
	if beard then
		scaleMesh(beard, P)
		Rig.BoxSafe(beard)
		local bp = { mesh = beard, attach = "Head", material = "Plastic", castShadow = beardStyle ~= "Moustache" }
		local bSize = Gen.BEARD_TEXTURE[lod]
		if bSize and headPiece.texture then
			-- strands over the head's own texture (shared UVs): needs the head texture first
			local headTex = headPiece.texture
			bp.texture = lazyTexture(bSize, bSize, function()
				-- make(), not .buffer: AnatomyClient makes the Beard before the Head (name order), on its worker thread
				return Paint.BeardTexture(beard, beardQ, headTex.make(), texSize, texSize, F, look, bSize, bSize, pscale, Rig.BeardMask(F, beardStyle))
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
