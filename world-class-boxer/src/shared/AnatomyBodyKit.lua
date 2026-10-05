-- AnatomyBodyKit: pure helpers of the Body anatomy generator (AnatomyBody). No Instances, deterministic.
-- * Skeleton(look): the bind-pose skeleton from look.rig: every R15 part centre and joint pivot in
--   UpperTorso space (studs, +X = the character's right, +Y up, -Z forward). Missing joints (old rigs,
--   the luaurun stubs) fall back to the R15 layout scaled by the part sizes. Joint rotations are ignored:
--   R15 bind poses have none.
-- * Params(look): what the body looks like: per-muscle development (look.body.lv), fat, definition,
--   physique knobs, sex, sliders, vascularity and a per-boxer variation stream (insertions, peaks,
--   asymmetry) seeded from the Body section's own inputs.
-- * small maths: monotone curves (no overshoot on silhouettes), smoothsteps, falloffs, segment distance
local Kit = {}

local sqrt, abs, min, max, floor, cos, sin = math.sqrt, math.abs, math.min, math.max, math.floor, math.cos, math.sin
local pi = math.pi

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end
Kit.clamp = clamp

-- smoothstep from e0 to e1 (e0 > e1 gives the falling step)
local function smooth(e0, e1, x)
	local t = (x - e0) / (e1 - e0)
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end
Kit.smooth = smooth

local function lerp(a, b, t)
	return a + (b - a) * t
end
Kit.lerp = lerp

-- smooth bell: 1 at 0, 0 at |d| >= 1, zero slope at both ends
local function bell(d)
	d = abs(d)
	if d >= 1 then
		return 0
	end
	local k = 1 - d * d
	return k * k
end
Kit.bell = bell

-- ellipsoidal bell around a centre
function Kit.bell3(dx, dy, dz)
	local d2 = dx * dx + dy * dy + dz * dz
	if d2 >= 1 then
		return 0
	end
	local k = 1 - d2
	return k * k
end

function Kit.bell2(dx, dy)
	local d2 = dx * dx + dy * dy
	if d2 >= 1 then
		return 0
	end
	local k = 1 - d2
	return k * k
end

-- distance from p to the segment a-b (and the parameter along it)
function Kit.segDist(px, py, pz, ax, ay, az, bx, by, bz)
	local abx, aby, abz = bx - ax, by - ay, bz - az
	local l2 = abx * abx + aby * aby + abz * abz
	local t = 0
	if l2 > 1e-12 then
		t = clamp(((px - ax) * abx + (py - ay) * aby + (pz - az) * abz) / l2, 0, 1)
	end
	local dx, dy, dz = px - ax - abx * t, py - ay - aby * t, pz - az - abz * t
	return sqrt(dx * dx + dy * dy + dz * dz), t
end

-- monotone cubic Hermite through knots { {x, y}, ... } (x ascending; Fritsch-Carlson): silhouettes never
-- overshoot between control points. Flat outside the knot range.
function Kit.Curve(knots)
	local n = #knots
	local xs, ys, ms, d = table.create(n), table.create(n), table.create(n), table.create(n)
	for i = 1, n do
		xs[i], ys[i] = knots[i][1], knots[i][2]
	end
	for i = 1, n - 1 do
		d[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
	end
	ms[1], ms[n] = d[1] or 0, d[n - 1] or 0
	for i = 2, n - 1 do
		if d[i - 1] * d[i] <= 0 then
			ms[i] = 0
		else
			ms[i] = (d[i - 1] + d[i]) / 2
		end
	end
	for i = 1, n - 1 do
		if d[i] == 0 then
			ms[i], ms[i + 1] = 0, 0
		else
			local a, b = ms[i] / d[i], ms[i + 1] / d[i]
			local s = a * a + b * b
			if s > 9 then
				local t = 3 / sqrt(s)
				ms[i], ms[i + 1] = t * a * d[i], t * b * d[i]
			end
		end
	end
	return function(x)
		if x <= xs[1] then
			return ys[1]
		elseif x >= xs[n] then
			return ys[n]
		end
		local i = 1
		while x > xs[i + 1] do
			i += 1
		end
		local h = xs[i + 1] - xs[i]
		local t = (x - xs[i]) / h
		local t2, t3 = t * t, t * t * t
		return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * ms[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * ms[i + 1]
	end
end

------------------------------------------------------------------------
-- Skeleton
------------------------------------------------------------------------
local function v3(t, dx, dy, dz)
	if type(t) == "table" and type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number" then
		return { t[1], t[2], t[3] }
	end
	return { dx, dy, dz }
end
local function add(a, b)
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end
local function sub(a, b)
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
Kit.add, Kit.sub = add, sub

function Kit.Skeleton(look)
	local rig = type(look.rig) == "table" and look.rig or {}
	local parts = type(rig.parts) == "table" and rig.parts or {}
	local joints = type(rig.joints) == "table" and rig.joints or {}
	local sc = type(look.scale) == "table" and look.scale or {}
	local w, h, d = tonumber(sc.w) or 1, tonumber(sc.h) or 1, tonumber(sc.d) or 1
	local function size(name, x, y, z)
		local s = v3(parts[name], x * w, y * h, z * d)
		-- a degenerate rig entry never reaches the maths
		s[1], s[2], s[3] = max(s[1], 0.05), max(s[2], 0.05), max(s[3], 0.05)
		return s
	end
	local S = {
		UT = size("UpperTorso", 2, 1.6, 1), LT = size("LowerTorso", 2, 0.4, 1), Head = parts.Head and v3(parts.Head, 1.2, 1.2, 1.2) or { 1.2, 1.2, 1.2 },
	}
	for _, side in ipairs({ "Right", "Left" }) do
		S[side .. "UpperArm"] = size(side .. "UpperArm", 1, 1.17, 1)
		S[side .. "LowerArm"] = size(side .. "LowerArm", 1, 1.05, 1)
		S[side .. "Hand"] = size(side .. "Hand", 1, 0.3, 1)
		S[side .. "UpperLeg"] = size(side .. "UpperLeg", 1, 1.22, 1)
		S[side .. "LowerLeg"] = size(side .. "LowerLeg", 1, 1.19, 1)
		S[side .. "Foot"] = size(side .. "Foot", 1, 0.3, 1)
	end
	local function joint(name, c0, c1)
		local j = joints[name]
		return v3(j and j.c0, c0[1], c0[2], c0[3]), v3(j and j.c1, c1[1], c1[2], c1[3])
	end
	local ut, lt, hd = S.UT, S.LT, S.Head
	local sk = { size = S, center = {}, piv = {} }
	sk.center.UpperTorso = { 0, 0, 0 }
	-- neck / waist
	local n0, n1 = joint("Neck", { 0, ut[2] / 2, 0 }, { 0, -hd[2] / 2, 0 })
	sk.piv.Neck = n0
	sk.center.Head = sub(n0, n1)
	local w0, w1 = joint("Waist", { 0, lt[2] / 2, 0 }, { 0, -ut[2] / 2, 0 })
	sk.piv.Waist = w1
	sk.center.LowerTorso = sub(w1, w0)
	for _, side in ipairs({ "Right", "Left" }) do
		local sg = side == "Right" and 1 or -1
		local ua, la, hand = S[side .. "UpperArm"], S[side .. "LowerArm"], S[side .. "Hand"]
		local ul, ll, foot = S[side .. "UpperLeg"], S[side .. "LowerLeg"], S[side .. "Foot"]
		local s0, s1 = joint(side .. "Shoulder", { sg * ut[1] / 2, 0.375 * ut[2], 0 }, { -sg * ua[1] / 2, 0.329 * ua[2], 0 })
		local sp = s0
		local uac = sub(sp, s1)
		local e0, e1 = joint(side .. "Elbow", { 0, -ua[2] / 2, 0 }, { 0, la[2] / 2, 0 })
		local ep = add(uac, e0)
		local lac = sub(ep, e1)
		local r0, r1 = joint(side .. "Wrist", { 0, -la[2] / 2, 0 }, { 0, hand[2] / 2, 0 })
		local wp = add(lac, r0)
		local hc = sub(wp, r1)
		local h0, h1 = joint(side .. "Hip", { sg * lt[1] / 4, -lt[2] / 2, 0 }, { 0, ul[2] / 2, 0 })
		local hp = add(sk.center.LowerTorso, h0)
		local ulc = sub(hp, h1)
		local k0, k1 = joint(side .. "Knee", { 0, -ul[2] / 2, 0 }, { 0, ll[2] / 2, 0 })
		local kp = add(ulc, k0)
		local llc = sub(kp, k1)
		local a0, a1 = joint(side .. "Ankle", { 0, -ll[2] / 2, 0 }, { 0, foot[2] / 2, 0 })
		local ap = add(llc, a0)
		sk.piv[side .. "Shoulder"], sk.piv[side .. "Elbow"], sk.piv[side .. "Wrist"] = sp, ep, wp
		sk.piv[side .. "Hip"], sk.piv[side .. "Knee"], sk.piv[side .. "Ankle"] = hp, kp, ap
		sk.center[side .. "UpperArm"], sk.center[side .. "LowerArm"], sk.center[side .. "Hand"] = uac, lac, hc
		sk.center[side .. "UpperLeg"], sk.center[side .. "LowerLeg"], sk.center[side .. "Foot"] = ulc, llc, sub(ap, a1)
	end
	-- torso frame numbers every builder uses
	sk.yW = sk.piv.Waist[2] -- waist pivot (about the navel)
	sk.yN = sk.piv.Neck[2] -- neck pivot (top of the torso)
	sk.H = max(0.4, sk.yN - sk.yW)
	sk.xS = max(0.3, (abs(sk.piv.RightShoulder[1]) + abs(sk.piv.LeftShoulder[1])) / 2) -- shoulder pivot half span
	sk.yS = (sk.piv.RightShoulder[2] + sk.piv.LeftShoulder[2]) / 2
	sk.hz = ut[3] / 2 -- torso half depth (the R15 box)
	sk.xH = max(0.15, (abs(sk.piv.RightHip[1] - sk.center.LowerTorso[1]) + abs(sk.piv.LeftHip[1] - sk.center.LowerTorso[1])) / 2)
	sk.yH = (sk.piv.RightHip[2] + sk.piv.LeftHip[2]) / 2
	sk.headX = max(0.5, hd[1])
	return sk
end

------------------------------------------------------------------------
-- Parameters
------------------------------------------------------------------------
Kit.MUSCLES = {
	"pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
	"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM",
}
-- physique silhouette knobs when look.body.pv is missing (BuilderBody.PV mirrors these)
local PV = {
	BeginnerLean = { elong = 1.0, flat = 0.85, groove = 0.6, waist = 1.0, taper = 0.9 },
	LeanTechnical = { elong = 1.08, flat = 0.9, groove = 1.15, waist = 0.92, taper = 1.0 },
	Balanced = { elong = 1.0, flat = 1.0, groove = 1.0, waist = 1.0, taper = 1.0 },
	PowerPuncher = { elong = 0.95, flat = 1.12, groove = 0.95, waist = 1.05, taper = 1.1 },
	Heavyweight = { elong = 0.94, flat = 1.0, groove = 0.55, waist = 1.2, taper = 0.95 },
	EliteChampion = { elong = 1.03, flat = 1.06, groove = 1.35, waist = 0.95, taper = 1.2 },
}

-- string -> 31-bit seed (djb2, exact in doubles)
local function hashStr(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end
Kit.hashStr = hashStr

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then
		return d
	end
	return v
end

-- the per-boxer seed: face.seed when the Body section reads it (LookData.SECTIONS.Body lists "face.seed"),
-- otherwise a digest of stable Body inputs (frame, sliders, skin, height, sex, trunk colours)
function Kit.Seed(look, bodyPaths)
	local useFace = false
	for _, p in ipairs(bodyPaths or {}) do
		if p == "face.seed" then
			useFace = true
		end
	end
	if useFace and type(look.face) == "table" and tonumber(look.face.seed) then
		return floor(abs(tonumber(look.face.seed))) % 2147483646 + 1
	end
	local b = type(look.body) == "table" and look.body or {}
	local a = type(look.attire) == "table" and look.attire or {}
	local function c(t)
		return type(t) == "table" and string.format("%s,%s,%s", tostring(t[1]), tostring(t[2]), tostring(t[3])) or "-"
	end
	local s = string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s", tostring(look.g), tostring(look.skin), tostring(look.height),
		tostring(b.frame), tostring(b.arms), tostring(b.chest), tostring(b.shoulders), tostring(b.waist), tostring(b.legs),
		tostring(b.neck), c(a.trunks), c(a.trim), tostring(a.trunkStyle))
	return hashStr(s) + 1
end

function Kit.Params(look, MeshKit, bodyPaths)
	local b = type(look.body) == "table" and look.body or {}
	local lvIn = type(b.lv) == "table" and b.lv or {}
	local P = { female = look.g == 2 }
	local lv = {}
	local sum = 0
	for _, id in ipairs(Kit.MUSCLES) do
		lv[id] = clamp(num(lvIn[id], 0.15), 0, 1.4)
		sum += lv[id]
	end
	P.lv = lv
	P.lvMean = sum / #Kit.MUSCLES
	P.fat = clamp(num(b.fat, 14), 5, 35)
	-- 0 at 11 % body fat, 1 at 24 %
	P.fatK = clamp((P.fat - 11) / 13, 0, 1.3)
	local def = num(b.def, nil)
	if def == nil then
		def = (16 - P.fat) / 8
	end
	P.def = clamp(def, 0, 1)
	-- what the skin shows: women keep a softer surface at the same number, fat blurs everything
	P.defE = P.def * (P.female and 0.72 or 1) * (1 - 0.6 * clamp(P.fatK, 0, 1))
	P.dry = clamp(num(b.dry, 0), 0, 1)
	P.vein = clamp(num(b.vein, 0), 0, 1)
	P.bulk = clamp(num(b.bulk, P.lvMean), 0, 1.3)
	local pv = type(b.pv) == "table" and b.pv or PV[b.physique or ""] or PV.Balanced
	P.pv = {
		elong = clamp(num(pv.elong, 1), 0.8, 1.25), flat = clamp(num(pv.flat, 1), 0.7, 1.3), groove = clamp(num(pv.groove, 1), 0.4, 1.6),
		waist = clamp(num(pv.waist, 1), 0.8, 1.3), taper = clamp(num(pv.taper, 1), 0.8, 1.3),
	}
	P.physique = type(b.physique) == "string" and b.physique or "Balanced"
	P.sl = {}
	for _, k in ipairs({ "arms", "chest", "shoulders", "waist", "legs", "neck" }) do
		P.sl[k] = clamp(num(b[k], 0), -1, 1)
	end
	P.age = clamp(num(look.age, 26), 16, 70)
	-- per-boxer variation: a fixed number of draws in a fixed order (the stream never shifts)
	local rng = MeshKit.Rng(Kit.Seed(look, bodyPaths))
	local function r(a, bb)
		return a + (bb - a) * rng:Next()
	end
	local V = {}
	V.abRow = { r(-0.012, 0.012), r(-0.012, 0.012), r(-0.012, 0.012) } -- tendinous intersections (u)
	V.abStagger = r(-0.014, 0.014) -- left / right offset of the ab rows
	V.abTilt = r(-0.025, 0.025)
	V.pecBorder = r(-0.02, 0.02)
	V.pecFull = r(0.92, 1.1)
	V.nipple = { r(-0.03, 0.03), r(-0.02, 0.02) }
	V.bicepsPeak = r(-0.06, 0.06) -- along the arm
	V.bicepsHeight = r(0.9, 1.15)
	V.deltFront = r(0.9, 1.12)
	V.calfHigh = r(-0.07, 0.07)
	V.calfRatio = r(0.85, 1.2)
	V.latLow = r(-0.05, 0.05)
	V.quadSweep = r(0.9, 1.12)
	V.teardrop = r(0.85, 1.2)
	V.domSide = rng:Next() < 0.82 and 1 or -1 -- the dominant (slightly bigger) side; orthodox = right
	V.asym = r(0.01, 0.035)
	V.veinSeed = floor(r(1, 900000))
	V.chestSpread = r(-0.02, 0.02)
	V.serratus = r(0.85, 1.15)
	V.neckW = r(0.96, 1.05)
	V.trapSlope = r(0.9, 1.12)
	P.V = V
	return P
end

-- side scale for muscle size (the dominant arm / pec / lat is a little bigger)
function Kit.SideK(P, side)
	return 1 + (side == P.V.domSide and 0.5 or -0.5) * P.V.asym
end

-- sRGB 0..1 skin colour
function Kit.Skin(look)
	local c = type(look.skinRGB) == "table" and look.skinRGB or { 206, 150, 108 }
	return clamp(num(c[1], 206) / 255, 0, 1), clamp(num(c[2], 150) / 255, 0, 1), clamp(num(c[3], 108) / 255, 0, 1)
end

-- an attire colour { r, g, b } (0..255) as 0..1, or nil
function Kit.Rgb(c)
	if type(c) == "table" and tonumber(c[1]) then
		return clamp(num(c[1], 0) / 255, 0, 1), clamp(num(c[2], 0) / 255, 0, 1), clamp(num(c[3], 0) / 255, 0, 1)
	end
	return nil
end

------------------------------------------------------------------------
-- Grid lofts (every body piece): rings with a UV seam column, closed by caps whose rows belong to the same
-- (row, column) lattice. The lattice is the piece's UV layout (u = column / sides, v = arc length down the
-- rows) and what its colour texture is sampled over (Kit.GridTexture): one texel per lattice point at any
-- density, smooth bilinear interpolation, no triangle-shaped colour steps.
------------------------------------------------------------------------
local TAU = pi * 2

-- one cap: dome rings (the end ring shrunk toward the spine and pushed past the end) then an apex row (one
-- vertex per column, its own u: the texture has no pole smear). cs = { depth = studs, rings = dome rings
-- (0 = a flat fan), shift = { x, y, z } (studs: the apex leans that way, the rings follow by sin), bDepth =
-- the row parameter the dome spans }. Returns the rows from the ring outward.
local function gridCap(m, MeshKit, info, which, cs)
	local rings, sides, stride, h = info.rings, info.sides, info.stride, info.h
	local f = which == "start" and info.frames[1] or info.frames[rings]
	local rs = info.ringStart[which == "start" and 1 or rings]
	local dir = which == "start" and -1 or 1
	local P = m.P
	local cx, cy, cz = f[1], f[2], f[3]
	local tx, ty, tz = f[4], f[5], f[6]
	local depth = cs.depth or 0
	local k = cs.rings or 0
	local sh = cs.shift
	local sx, sy, sz = sh and sh[1] or 0, sh and sh[2] or 0, sh and sh[3] or 0
	local b0 = info.rowB and info.rowB[which == "start" and 1 or rings] or 0
	local bD = cs.bDepth or 0
	local out = {}
	local flip = dir < 0
	local function band(r0, r1)
		for j = 0, sides - 1 do
			local a, b = r0 + j, r0 + j + 1
			local c, d = r1 + j, r1 + j + 1
			if (h > 0) ~= flip then
				MeshKit.Tri(m, a, b, c)
				MeshKit.Tri(m, b, d, c)
			else
				MeshKit.Tri(m, a, c, b)
				MeshKit.Tri(m, b, c, d)
			end
		end
	end
	local last = rs
	for q = 1, k do
		local th = (pi / 2) * q / (k + 1)
		local sc, sn = cos(th), sin(th)
		local push = dir * sn * depth
		local at = m.nv + 1
		for j = 0, stride - 1 do
			local v = rs + j
			local x, y, z = P[v * 3 - 2], P[v * 3 - 1], P[v * 3]
			MeshKit.Vertex(m, cx + tx * push + (x - cx) * sc + sx * sn, cy + ty * push + (y - cy) * sc + sy * sn,
				cz + tz * push + (z - cz) * sc + sz * sn, j / sides, 0)
		end
		band(last, at)
		out[#out + 1] = { s = at, n = stride, b = b0 + dir * sn * bD, cap = dir }
		last = at
	end
	local ax, ay, az = cx + tx * dir * depth + sx, cy + ty * dir * depth + sy, cz + tz * dir * depth + sz
	local apex = m.nv + 1
	for j = 0, sides - 1 do
		MeshKit.Vertex(m, ax, ay, az, (j + 0.5) / sides, 0)
	end
	local outward = (h > 0) == (dir > 0)
	for j = 0, sides - 1 do
		if outward then
			MeshKit.Tri(m, apex + j, last + j, last + j + 1)
		else
			MeshKit.Tri(m, apex + j, last + j + 1, last + j)
		end
	end
	out[#out + 1] = { s = apex, n = sides, b = b0 + dir * bD, cap = dir, apex = true }
	return out
end

-- spec: MeshKit.Loft's fields (rings, sides, spine, exact, section | radius, sideHint, frontHint, group) +
--   rowB = { parameter per ring } (bone parameter, torso height, ...), capS / capE = gridCap specs (nil = open)
-- returns the Loft info + rowB, rows = { { s = first vertex, n = stride (sides on an apex row), b, cap } }
-- in surface order (start apex .. start dome .. rings .. end dome .. end apex)
function Kit.GridLoft(m, MeshKit, spec)
	local ls = table.clone(spec)
	ls.uvSeam = true
	ls.capStart, ls.capEnd, ls.capS, ls.capE, ls.rowB = nil, nil, nil, nil, nil
	local info = MeshKit.Loft(m, ls)
	info.rowB = spec.rowB
	local rows = {}
	local startRows = spec.capS and gridCap(m, MeshKit, info, "start", spec.capS) or {}
	for q = #startRows, 1, -1 do
		rows[#rows + 1] = startRows[q]
	end
	info.firstRing = #rows + 1
	for i = 1, info.rings do
		rows[#rows + 1] = { s = info.ringStart[i], n = info.stride, b = spec.rowB and spec.rowB[i] or (i - 1) / (info.rings - 1), cap = 0, ring = i }
	end
	info.lastRing = #rows
	local endRows = spec.capE and gridCap(m, MeshKit, info, "end", spec.capE) or {}
	for q = 1, #endRows do
		rows[#rows + 1] = endRows[q]
	end
	info.rows, info.nRows = rows, #rows
	info.last = m.nv
	return info
end

-- vertex of row r at column j (0 .. sides; an apex row has one vertex per column)
local function rowVertex(row, j)
	if j >= row.n then
		j = row.n - 1
	end
	return row.s + j
end
Kit.RowVertex = rowVertex

-- normals across the seam column and the apex rows: the duplicates share the mean (MeshKit.ComputeNormals
-- with weld = false gives each copy only its own side's faces)
function Kit.SeamNormals(m, info)
	if info.atlas then
		for _, g in ipairs(info.atlas) do
			Kit.SeamNormals(m, g)
		end
		return
	end
	local N = m.N
	local sides = info.sides
	for _, row in ipairs(info.rows) do
		if row.n > sides then
			local a, b = row.s, row.s + sides
			local x, y, z = N[a * 3 - 2] + N[b * 3 - 2], N[a * 3 - 1] + N[b * 3 - 1], N[a * 3] + N[b * 3]
			local l = sqrt(x * x + y * y + z * z)
			if l > 1e-9 then
				x, y, z = x / l, y / l, z / l
				N[a * 3 - 2], N[a * 3 - 1], N[a * 3] = x, y, z
				N[b * 3 - 2], N[b * 3 - 1], N[b * 3] = x, y, z
			end
		else
			local x, y, z = 0, 0, 0
			for j = 0, row.n - 1 do
				local v = row.s + j
				x, y, z = x + N[v * 3 - 2], y + N[v * 3 - 1], z + N[v * 3]
			end
			local l = sqrt(x * x + y * y + z * z)
			if l > 1e-9 then
				x, y, z = x / l, y / l, z / l
				for j = 0, row.n - 1 do
					local v = row.s + j
					N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = x, y, z
				end
			end
		end
	end
end

-- normals of a finished grid piece (faces, then the seam / apex duplicates)
function Kit.GridNormals(m, MeshKit, info)
	MeshKit.ComputeNormals(m, { weld = false })
	Kit.SeamNormals(m, info)
end

-- UVs: u = column / sides (apex rows: column centres), v = arc length down the rows (mean over the
-- columns), inside a half-texel margin; info.rowV keeps each row's v for the texture sampler. rect =
-- { u0, v0, u1, v1 } places the grid in part of the texture (an atlas of several grids); default all of it.
function Kit.GridUV(m, info, texH, rect, texW)
	local P = m.P
	local sides, rows = info.sides, info.rows
	local acc = table.create(#rows, 0)
	for r = 2, #rows do
		local a, b = rows[r - 1], rows[r]
		local d = 0
		for j = 0, sides - 1 do
			local p, q = rowVertex(a, j), rowVertex(b, j)
			d += sqrt((P[p * 3 - 2] - P[q * 3 - 2]) ^ 2 + (P[p * 3 - 1] - P[q * 3 - 1]) ^ 2 + (P[p * 3] - P[q * 3]) ^ 2)
		end
		acc[r] = acc[r - 1] + d / sides
	end
	local total = max(acc[#rows], 1e-6)
	rect = rect or { 0, 0, 1, 1 }
	local u0, v0, u1, v1 = rect[1], rect[2], rect[3], rect[4]
	-- half a texel inside the rect: bilinear filtering never reads the neighbour grid's texels
	local mv = 0.5 / (texH or 256)
	local mu = 0.5 / (texW or texH or 256)
	v0, v1 = v0 + mv, v1 - mv
	local uA, uB = u0 + mu, u1 - mu
	info.rect = { u0, rect[2], u1, rect[4] }
	info.uA, info.uB = uA, uB
	local rowV = table.create(#rows)
	for r, row in ipairs(rows) do
		local v = v0 + (v1 - v0) * acc[r] / total
		rowV[r] = v
		for j = 0, row.n - 1 do
			local i = row.s + j
			m.U[i * 2] = v
			local f = row.n > sides and j / sides or (j + 0.5) / sides
			m.U[i * 2 - 1] = uA + (uB - uA) * f
		end
	end
	info.rowV = rowV
end

-- the texel -> lattice map of a single-grid piece (stored on the mesh as mesh.texMap; BodyFX paints bruises /
-- grime into the piece's texture with it: a texel's four lattice vertices and weights, no rasterising):
-- { w, h, sides, uA, uB, v = { row v }, s = { row's first vertex }, n = { row's vertex count } }
function Kit.TexMap(info, w, h)
	local v, st, n = {}, {}, {}
	for r, row in ipairs(info.rows) do
		v[r], st[r], n[r] = info.rowV[r], row.s, row.n
	end
	return { w = w, h = h, sides = info.sides, uA = info.uA or 0, uB = info.uB or 1, v = v, s = st, n = n }
end

-- the texture v of a row parameter b (between the ring rows' parameters; caps extrapolate)
function Kit.GridVOfB(info, bb)
	local rows, rowV = info.rows, info.rowV
	local n = #rows
	if bb <= rows[1].b then
		return rowV[1]
	end
	for r = 2, n do
		local a, b = rows[r - 1], rows[r]
		if bb <= b.b then
			local t = b.b > a.b and (bb - a.b) / (b.b - a.b) or 0
			return rowV[r - 1] + (rowV[r] - rowV[r - 1]) * t
		end
	end
	return rowV[n]
end

-- UVs of extra vertices lying on the grid's surface (veins) from their (row parameter, angle)
function Kit.GridUVAt(m, info, first, last, B, A)
	local uA, uB = info.uA or 0, info.uB or 1
	for i = first, last do
		local a = (A[i] or 0) % TAU
		m.U[i * 2 - 1] = uA + (uB - uA) * a / TAU
		m.U[i * 2] = Kit.GridVOfB(info, B[i] or 0)
	end
end

-- several grids in one texture: info.atlas = { grid infos } gets horizontal bands of the texture in
-- proportion to each grid's surface (mean circumference x length)
function Kit.GridUVAtlas(m, info, texH)
	local list = info.atlas
	if not list then
		Kit.GridUV(m, info, texH)
		return
	end
	local P = m.P
	local areas, total = {}, 0
	for k, g in ipairs(list) do
		local circ, len = 0, 0
		local rows = g.rows
		for r = 1, #rows do
			local row = rows[r]
			local c = 0
			for j = 0, g.sides - 1 do
				local p, q = rowVertex(row, j), rowVertex(row, j + 1)
				c += sqrt((P[p * 3 - 2] - P[q * 3 - 2]) ^ 2 + (P[p * 3 - 1] - P[q * 3 - 1]) ^ 2 + (P[p * 3] - P[q * 3]) ^ 2)
			end
			circ = max(circ, c)
			if r > 1 then
				local a = rows[r - 1]
				local p, q = rowVertex(a, 0), rowVertex(row, 0)
				len += sqrt((P[p * 3 - 2] - P[q * 3 - 2]) ^ 2 + (P[p * 3 - 1] - P[q * 3 - 1]) ^ 2 + (P[p * 3] - P[q * 3]) ^ 2)
			end
		end
		areas[k] = max(1e-4, circ * len) ^ 0.75 -- small parts get a little more than their share
		total += areas[k]
	end
	-- whole texel rows per band
	local v = 0
	local rowsLeft = texH
	for k, g in ipairs(list) do
		local n = k == #list and rowsLeft or max(2, floor(texH * areas[k] / total + 0.5))
		n = min(n, rowsLeft - 2 * (#list - k))
		Kit.GridUV(m, g, texH, { 0, v / texH, 1, (v + n) / texH })
		v += n
		rowsLeft -= n
	end
end

-- concavity per vertex from the lattice neighbours (MeshKit.Cavity's meaning and scale: > 0 in creases,
-- < 0 on ridges) without the welded-topology pass; apex rows get 0, the seam column copies column 0
function Kit.GridCavity(m, info, scale, out)
	local P, N = m.P, m.N
	out = out or table.create(m.nv, 0)
	if info.atlas then
		for _, g in ipairs(info.atlas) do
			Kit.GridCavity(m, g, scale, out)
		end
		return out
	end
	local k = scale or 4
	local sides, rows = info.sides, info.rows
	local nr = #rows
	for r = 1, nr do
		local row = rows[r]
		if row.n > sides then
			for j = 0, sides - 1 do
				local v = row.s + j
				local x, y, z = P[v * 3 - 2], P[v * 3 - 1], P[v * 3]
				local sx, sy, sz, el, n = 0, 0, 0, 0, 0
				local function nb(w)
					local wx, wy, wz = P[w * 3 - 2], P[w * 3 - 1], P[w * 3]
					sx += wx
					sy += wy
					sz += wz
					el += sqrt((wx - x) ^ 2 + (wy - y) ^ 2 + (wz - z) ^ 2)
					n += 1
				end
				nb(row.s + (j + 1) % sides)
				nb(row.s + (j - 1) % sides)
				if r > 1 then
					nb(rowVertex(rows[r - 1], j))
				end
				if r < nr then
					nb(rowVertex(rows[r + 1], j))
				end
				el /= n
				if el > 1e-9 then
					local lx, ly, lz = sx / n - x, sy / n - y, sz / n - z
					out[v] = clamp((lx * N[v * 3 - 2] + ly * N[v * 3 - 1] + lz * N[v * 3]) / el * k, -1, 1)
				end
			end
			out[row.s + sides] = out[row.s]
		end
	end
	return out
end

-- ambient occlusion as two per-vertex amounts (MeshKit.BakeAO's model, kept apart from the colour so the
-- vertex colours and the texture can both apply it): dark (creases, down-facing, occluders), light (ridges)
function Kit.AOAmounts(m, cav, o)
	local N, P = m.N, m.P
	local kc, kr, kd = o.cavity or 0.35, o.ridge or 0.08, o.down or 0.12
	local occ = o.occluders
	local ko = o.occStrength or 0.5
	local dark, light = table.create(m.nv, 0), table.create(m.nv, 0)
	for i = 1, m.nv do
		local i3 = i * 3
		local cv = cav[i] or 0
		local d = kc * max(0, cv) + kd * max(0, -N[i3 - 1])
		if occ then
			local x, y, z = P[i3 - 2], P[i3 - 1], P[i3]
			local nx, ny, nz = N[i3 - 2], N[i3 - 1], N[i3]
			local acc = 0
			for _, sp in ipairs(occ) do
				local vx, vy, vz = sp[1] - x, sp[2] - y, sp[3] - z
				local dd = sqrt(vx * vx + vy * vy + vz * vz)
				if dd > 1e-6 then
					local cosv = (vx * nx + vy * ny + vz * nz) / dd
					if cosv > 0 then
						acc += min(1, (sp[4] * sp[4]) / max(dd * dd, sp[4] * sp[4])) * cosv
					end
				end
			end
			d += ko * min(acc, 1)
		end
		dark[i] = clamp(d, 0, 0.85)
		light[i] = kr * max(0, -cv)
	end
	return dark, light
end

-- one colour through the AO amounts (BakeAO's formula: darkened toward a tinted shadow of itself)
function Kit.ApplyAO(r, g, b, dark, light, tint)
	r = r + (r * tint[1] * 2 - r) * dark
	g = g + (g * tint[2] * 2 - g) * dark
	b = b + (b * tint[3] * 2 - b) * dark
	return min(1, r + light * (1 - r)), min(1, g + light * (1 - g)), min(1, b + light * (1 - b))
end

-- noise tiles for texel painting: an n x n lattice of values in [-1, 1] (hash, deterministic), sampled
-- bilinearly and wrapping in both directions (cheap per texel; MeshKit.Noise per texel is far slower)
function Kit.NoiseTile(MeshKit, n, seed)
	local t = table.create(n * n)
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			t[y * n + x + 1] = MeshKit.Hash3(x, y, 7, seed) * 2 - 1
		end
	end
	return { n = n, v = t }
end

function Kit.TileAt(tile, x, y)
	local n, v = tile.n, tile.v
	local ix, iy = floor(x), floor(y)
	local fx, fy = x - ix, y - iy
	fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
	local x0, y0 = ix % n, iy % n
	local x1, y1 = (x0 + 1) % n, (y0 + 1) % n
	local a, b = v[y0 * n + x0 + 1], v[y0 * n + x1 + 1]
	local c, d = v[y1 * n + x0 + 1], v[y1 * n + x1 + 1]
	local top = a + (b - a) * fx
	return top + (c + (d - c) * fx - top) * fy
end

-- the colour texture of a grid piece: for every texel, the lattice cell under it (rows by info.rowV,
-- columns by u) and a bilinear sample of position, normal, row parameter, column angle and the optional
-- per-vertex arrays (o.colors = C-like { r, g, b } array, o.dark / o.light), then paint(s) -> r, g, b.
-- The sample table s is reused (fields x y z nx ny nz b a u v px py r g bl dark light cap). Calls MeshKit.Step
-- per texel (a client yields between rows). Returns an RGBA8 buffer w * h * 4 (alpha 255).
function Kit.GridTexture(MeshKit, m, info, w, h, paint, o, buf)
	o = o or {}
	buf = buf or buffer.create(w * h * 4)
	if info.atlas then
		for k, g in ipairs(info.atlas) do
			o.grid = k
			Kit.GridTexture(MeshKit, m, g, w, h, paint, o, buf)
		end
		return buf
	end
	local P, N = o.P or m.P, o.N or m.N
	local C, D, L = o.colors, o.dark, o.light
	-- painters that only read the lattice parameters skip the position / normal interpolation
	local wantP, wantN = not o.noP, not o.noN
	local onRow = o.onRow
	local rows, rowV, sides = info.rows, info.rowV, info.sides
	local nr = #rows
	local s = { x = 0, y = 0, z = 0, nx = 0, ny = 1, nz = 0, b = 0, a = 0, u = 0, v = 0, px = 0, py = 0, r = 1, g = 1, bl = 1, dark = 0, light = 0, cap = 0, grid = o.grid or 1 }
	local r0 = 1
	local floorF, writeu8 = floor, buffer.writeu8
	local rect = info.rect or { 0, 0, 1, 1 }
	local uA, uB = info.uA or 0, info.uB or 1
	local py0, py1 = floorF(rect[2] * h + 0.5), floorF(rect[4] * h + 0.5) - 1
	for py = py0, py1 do
		local v = (py + 0.5) / h
		while r0 < nr - 1 and rowV[r0 + 1] < v do
			r0 += 1
		end
		local ra, rb = rows[r0], rows[r0 + 1]
		local va, vb = rowV[r0], rowV[r0 + 1]
		local t = vb > va and clamp((v - va) / (vb - va), 0, 1) or 0
		local t1 = 1 - t
		s.b = ra.b * t1 + rb.b * t
		s.cap = (t < 0.5) and ra.cap or rb.cap
		s.v, s.py = v, py
		if onRow then
			onRow(s)
		end
		for px = 0, w - 1 do
			local u = (px + 0.5) / w
			local jf = clamp((u - uA) / (uB - uA), 0, 1) * sides
			local j = floorF(jf)
			if j > sides - 1 then
				j = sides - 1
			end
			local f = jf - j
			local f1 = 1 - f
			local i1, i2 = rowVertex(ra, j), rowVertex(ra, j + 1)
			local i3, i4 = rowVertex(rb, j), rowVertex(rb, j + 1)
			local w1, w2, w3, w4 = f1 * t1, f * t1, f1 * t, f * t
			local a1, a2, a3, a4 = i1 * 3, i2 * 3, i3 * 3, i4 * 3
			if wantP then
				s.x = P[a1 - 2] * w1 + P[a2 - 2] * w2 + P[a3 - 2] * w3 + P[a4 - 2] * w4
				s.y = P[a1 - 1] * w1 + P[a2 - 1] * w2 + P[a3 - 1] * w3 + P[a4 - 1] * w4
				s.z = P[a1] * w1 + P[a2] * w2 + P[a3] * w3 + P[a4] * w4
			end
			if wantN then
				local nx = N[a1 - 2] * w1 + N[a2 - 2] * w2 + N[a3 - 2] * w3 + N[a4 - 2] * w4
				local ny = N[a1 - 1] * w1 + N[a2 - 1] * w2 + N[a3 - 1] * w3 + N[a4 - 1] * w4
				local nz = N[a1] * w1 + N[a2] * w2 + N[a3] * w3 + N[a4] * w4
				local nl = sqrt(nx * nx + ny * ny + nz * nz)
				if nl > 1e-9 then
					nx, ny, nz = nx / nl, ny / nl, nz / nl
				end
				s.nx, s.ny, s.nz = nx, ny, nz
			end
			s.a = TAU * jf / sides
			s.u, s.px = u, px
			if C then
				s.r = C[a1 - 2] * w1 + C[a2 - 2] * w2 + C[a3 - 2] * w3 + C[a4 - 2] * w4
				s.g = C[a1 - 1] * w1 + C[a2 - 1] * w2 + C[a3 - 1] * w3 + C[a4 - 1] * w4
				s.bl = C[a1] * w1 + C[a2] * w2 + C[a3] * w3 + C[a4] * w4
			end
			if D then
				s.dark = D[i1] * w1 + D[i2] * w2 + D[i3] * w3 + D[i4] * w4
				s.light = L[i1] * w1 + L[i2] * w2 + L[i3] * w3 + L[i4] * w4
			end
			local cr, cg, cb = paint(s)
			local q = (py * w + px) * 4
			writeu8(buf, q, floorF(clamp(cr, 0, 1) * 255 + 0.5))
			writeu8(buf, q + 1, floorF(clamp(cg, 0, 1) * 255 + 0.5))
			writeu8(buf, q + 2, floorF(clamp(cb, 0, 1) * 255 + 0.5))
			writeu8(buf, q + 3, 255)
		end
		MeshKit.Step(w)
	end
	return buf
end

-- paint helpers shared by every piece painter (vertex colours and texels alike)
function Kit.Mix(r, g, b, r2, g2, b2, k)
	if k <= 0 then
		return r, g, b
	end
	return r + (r2 - r) * k, g + (g2 - g) * k, b + (b2 - b) * k
end

-- grooves darken toward the skin's own shadow (a slight warm lean, never red lines, never grey); crowns lift
function Kit.SepShade(pc, r, g, b, groove, crown, kG, kC)
	if groove > 0 then
		local k = min(pc.kMax, groove * kG * pc.gk)
		r, g, b = r * (1 - k * 0.3), g * (1 - k * 0.33), b * (1 - k * 0.34)
	end
	if crown > 0 then
		local k = min(0.25, crown * kC * pc.ck)
		r, g, b = r + (1 - r) * k * 0.55, g + (1 - g) * k * 0.5, b + (1 - b) * k * 0.45
	end
	return r, g, b
end

-- the skin's own variation at a texel (multiplier): blotchy mottling a few centimetres across, a finer
-- mottle, pores; tiles wrap exactly across a w x h texture
function Kit.SkinGrain(tiles, px, py, w, h, amp)
	local blot = Kit.TileAt(tiles.blot, px * 16 / w * 3, py * 16 / h * 3)
	local fine = Kit.TileAt(tiles.fine, px * 32 / w * 4, py * 32 / h * 4)
	local pore = Kit.TileAt(tiles.pore, px, py)
	return 1 + amp * (0.03 * blot + 0.014 * fine + 0.018 * pore * pore * (pore > 0 and 1 or -1))
end

-- the skin grain of a whole w x h texture: one table per size for every character and piece (a fixed noise:
-- its texels are only ever read by their own coordinates, so the layouts of different pieces never line up
-- visibly), made the first time a texture of that size is painted
local GRAIN, GRAIN_TILES = {}, nil
function Kit.GrainTable(_pc, w, h)
	local key = w * 4096 + h
	local t = GRAIN[key]
	if t then
		return t
	end
	return Kit.MakeGrain(w, h)
end

function Kit.MakeGrain(w, h, MeshKit)
	local key = w * 4096 + h
	if not GRAIN_TILES then
		local MK = MeshKit or require(script.Parent:WaitForChild("MeshKit"))
		GRAIN_TILES = { blot = Kit.NoiseTile(MK, 16, 4111), fine = Kit.NoiseTile(MK, 32, 4123), pore = Kit.NoiseTile(MK, 64, 4137) }
	end
	local t = table.create(w * h)
	for py = 0, h - 1 do
		for px = 0, w - 1 do
			t[py * w + px + 1] = Kit.SkinGrain(GRAIN_TILES, px, py, w, h, 1)
		end
	end
	GRAIN[key] = t
	return t
end

-- a texture made when it is asked for: { w, h, make = fn() -> RGBA8 buffer }. AnatomyClient calls make() on its
-- worker thread (an ordinary call: the painter's MeshKit.Step ticks may yield there); tools and tests may also
-- read .buffer (a metamethod: never read it where the tick can yield). Not kept: a cached generation must
-- not hold every character's pixels; a rebuild makes them again (deterministic).
function Kit.LazyTexture(w, h, make)
	return setmetatable({ w = w, h = h, make = make }, {
		__index = function(_, k)
			if k == "buffer" then
				return make()
			end
			return nil
		end,
	})
end

-- a vein: a low, wide ridge lying on the skin (a closed strand with a flattened six-point section whose
-- base corners sit under the skin), so it reads as a soft raised cord instead of a wire. pts[k] = skin point,
-- nrm[k] = outward skin direction there; r = the strand's half height scale (studs). The ends taper and dive
-- under the skin. Returns the first vertex id.
local STRAND = { { -1, -0.8 }, { -0.42, 0.85 }, { 0.42, 0.85 }, { 1, -0.8 } }
-- shading normals per section point (b, n): half way between the section's own normal and the skin's, so
-- the ridge blends into the skin instead of showing a hard edge
local STRAND_N = { { 0, 1 }, { -0.25, 0.968 }, { 0.25, 0.968 }, { 0, 1 } }
-- normalsOut (optional list) receives { vertex, nx, ny, nz } to apply after MeshKit.ComputeNormals
function Kit.Strand(m, MeshKit, pts, nrm, r, group, normalsOut)
	local n, ns = #pts, #STRAND
	local first = m.nv + 1
	local w, h = 2.2 * r, 0.8 * r
	local ring = table.create(n)
	local tangents = table.create(n)
	for k = 1, n do
		local p0, p1 = pts[math.max(1, k - 1)], pts[math.min(n, k + 1)]
		local tx, ty, tz = p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3]
		local tl = math.sqrt(tx * tx + ty * ty + tz * tz)
		if tl < 1e-9 then
			tx, ty, tz, tl = 0, 1, 0, 1
		end
		tx, ty, tz = tx / tl, ty / tl, tz / tl
		local nx, ny, nz = nrm[k][1], nrm[k][2], nrm[k][3]
		-- the skin direction made square to the strand, then the binormal b = n x t (b, n, t right handed)
		local dn = nx * tx + ny * ty + nz * tz
		nx, ny, nz = nx - tx * dn, ny - ty * dn, nz - tz * dn
		local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
		if nl < 1e-9 then
			nx, ny, nz, nl = 1, 0, 0, 1
		end
		nx, ny, nz = nx / nl, ny / nl, nz / nl
		local bx, by, bz = ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx
		tangents[k] = { tx, ty, tz, nx, ny, nz }
		-- thickest in the middle; toward the ends the section shrinks and sinks under the skin
		local tt = (k - 1) / (n - 1)
		local sc = math.max(0.2, math.sin(math.pi * tt)) ^ 0.6
		local sink = (1 - sc) * 0.9 * h
		local p = pts[k]
		ring[k] = m.nv + 1
		for j = 1, ns do
			local q = STRAND[j]
			local x, y = q[1] * w * sc, q[2] * h * sc - sink
			local v = MeshKit.Vertex(m, p[1] + bx * x + nx * y, p[2] + by * x + ny * y, p[3] + bz * x + nz * y, tt, j / ns)
			if normalsOut then
				local qn = STRAND_N[j]
				normalsOut[#normalsOut + 1] = { v, bx * qn[1] + nx * qn[2], by * qn[1] + ny * qn[2], bz * qn[1] + nz * qn[2] }
			end
		end
	end
	for k = 1, n - 1 do
		local r0, r1 = ring[k], ring[k + 1]
		for j = 0, ns - 1 do
			local j1 = (j + 1) % ns
			local a, b, c, d = r0 + j, r0 + j1, r1 + j, r1 + j1
			-- the section runs clockwise seen from +t: (a, c, b) faces out
			MeshKit.Tri(m, a, c, b)
			MeshKit.Tri(m, b, c, d)
		end
	end
	-- tips under the skin, a little past each end
	for e = 0, 1 do
		local k = e == 0 and 1 or n
		local tg = tangents[k]
		local p = pts[k]
		local sgn = e == 0 and -1 or 1
		local tip = MeshKit.Vertex(m, p[1] + tg[1] * sgn * w * 0.6 - tg[4] * h, p[2] + tg[2] * sgn * w * 0.6 - tg[5] * h,
			p[3] + tg[3] * sgn * w * 0.6 - tg[6] * h, e, 0.5)
		if normalsOut then
			normalsOut[#normalsOut + 1] = { tip, tg[4], tg[5], tg[6] }
		end
		local r0 = ring[k]
		for j = 0, ns - 1 do
			local j1 = (j + 1) % ns
			if e == 0 then
				MeshKit.Tri(m, tip, r0 + j, r0 + j1)
			else
				MeshKit.Tri(m, tip, r0 + j1, r0 + j)
			end
		end
	end
	if group then
		for i = first, m.nv do
			MeshKit.AddToGroup(m, group, i)
		end
	end
	return first
end

-- angle warp that crowds loft columns toward the front (pi / 2) and thins them at the back; symmetric
-- about the x = 0 plane, keeps a column on the exact front / back centre line when sides % 4 == 0
function Kit.FrontWarp(k)
	return function(a)
		return a - k * math.sin(a - pi / 2)
	end
end

return Kit
