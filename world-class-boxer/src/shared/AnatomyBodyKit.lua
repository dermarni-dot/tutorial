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

local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor
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

-- concavity of a loft's ring vertices from the grid neighbours (the same meaning and scale as
-- MeshKit.Cavity: > 0 in creases, < 0 on ridges), without the welded-topology pass. Cap vertices get 0.
function Kit.GridCavity(m, first, rings, stride, sides, scale)
	local P, N = m.P, m.N
	local out = table.create(m.nv, 0)
	local k = scale or 4
	for i = 1, rings do
		for j = 0, sides - 1 do
			local v = first + (i - 1) * stride + j
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
			nb(first + (i - 1) * stride + (j + 1) % sides)
			nb(first + (i - 1) * stride + (j - 1) % sides)
			if i > 1 then
				nb(first + (i - 2) * stride + j)
			end
			if i < rings then
				nb(first + i * stride + j)
			end
			el /= n
			if el > 1e-9 then
				local lx, ly, lz = sx / n - x, sy / n - y, sz / n - z
				out[v] = clamp((lx * N[v * 3 - 2] + ly * N[v * 3 - 1] + lz * N[v * 3]) / el * k, -1, 1)
			end
		end
	end
	return out
end

-- a dome cap of its own depth on one end of an open loft (MeshKit.Loft has one capDepth for both ends):
-- the end ring shrunk toward the spine and pushed past the end in `domeRings` steps, then a fan. Same
-- winding rules as MeshKit.Loft's caps, so the piece stays closed and outward facing.
function Kit.LoftCap(m, MeshKit, info, which, depth, domeRings)
	local rings, sides, stride, h = info.rings, info.sides, info.stride, info.h
	local f = which == "start" and info.frames[1] or info.frames[rings]
	local rs = which == "start" and info.ringStart[1] or info.ringStart[rings]
	local dir = which == "start" and -1 or 1
	local P = m.P
	local cx, cy, cz = f[1], f[2], f[3]
	local tx, ty, tz = f[4], f[5], f[6]
	local function band(r0, r1, flip)
		for j = 0, sides - 1 do
			local j1 = (j + 1) % sides
			local a, b = r0 + j, r0 + j1
			local c, d = r1 + j, r1 + j1
			if (h > 0) ~= (flip == true) then
				MeshKit.Tri(m, a, b, c)
				MeshKit.Tri(m, b, d, c)
			else
				MeshKit.Tri(m, a, c, b)
				MeshKit.Tri(m, b, c, d)
			end
		end
	end
	local last = rs
	local k = math.max(1, domeRings or 2)
	for q = 1, k do
		local th = (pi / 2) * q / (k + 1)
		local sc, push = math.cos(th), dir * math.sin(th) * depth
		local at = m.nv + 1
		for j = 0, sides - 1 do
			local v = rs + j
			local x, y, z = P[v * 3 - 2], P[v * 3 - 1], P[v * 3]
			local nvx = cx + tx * push + (x - cx) * sc
			local nvy = cy + ty * push + (y - cy) * sc
			local nvz = cz + tz * push + (z - cz) * sc
			local i = MeshKit.Vertex(m, nvx, nvy, nvz, j / sides, which == "start" and -q * 0.05 or 1 + q * 0.05)
			local r, g, b = m.C[v * 3 - 2], m.C[v * 3 - 1], m.C[v * 3]
			MeshKit.SetColor(m, i, r, g, b)
		end
		band(last, at, dir < 0)
		last = at
	end
	local apex = MeshKit.Vertex(m, cx + tx * dir * depth, cy + ty * dir * depth, cz + tz * dir * depth, 0.5, which == "start" and -0.2 or 1.2)
	local outward = (h > 0) == (dir > 0)
	for j = 0, sides - 1 do
		local j1 = (j + 1) % sides
		if outward then
			MeshKit.Tri(m, apex, last + j, last + j1)
		else
			MeshKit.Tri(m, apex, last + j1, last + j)
		end
	end
	return apex
end

-- a vein: a low, wide ridge lying on the skin (a closed strand with a flattened six-point section whose
-- base corners sit under the skin), so it reads as a soft raised cord instead of a wire. pts[k] = skin point,
-- nrm[k] = outward skin direction there; r = the strand's half height scale (studs). The ends taper and dive
-- under the skin. Returns the first vertex id.
local STRAND = { { -1, -0.8 }, { -0.62, 0.45 }, { -0.22, 1 }, { 0.22, 1 }, { 0.62, 0.45 }, { 1, -0.8 } }
-- shading normals per section point (b, n): half way between the section's own normal and the skin's, so
-- the ridge blends into the skin instead of showing a hard edge
local STRAND_N = { { 0, 1 }, { -0.34, 0.94 }, { -0.115, 0.993 }, { 0.115, 0.993 }, { 0.34, 0.94 }, { 0, 1 } }
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
