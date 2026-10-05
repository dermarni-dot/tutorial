-- AnatomyHairKit: the building blocks of the hair meshes (AnatomyHair, ANATOMY_CONTRACTS.md). Pure Luau,
-- deterministic, no Instances, so the client, the renderer and the luaurun tests build identical hair.
-- * the scalp: AnatomySkull's field (the Head mesh's scalp IS its zero set) with rays, normals, projection
--   and push-out, the natural hairline (AnatomySkull.HairlineHeights) reshaped by the hairline type
--   (Straight, Widow's Peak, Receding, Line-Up), fades (low / mid / high / taper / burst / shaved sides)
--   and a body proxy (neck, trapezius, chest and back from the rig) long hair and locs rest on
-- * hair colour: roots darker than tips, per-clump variation, highlights, dye patterns, greying with age
-- * strand paths: grown over the scalp along a comb flow (hugging the skull while it is above them), then
--   falling under gravity past the ears onto the neck, shoulders and back; waves, lift for volume
-- * geometry: flat lens-section clumps (strand groups) with tapered tips, fine strands, round tubes with
--   lumpy (locs), plaited (3-strand braids, cornrows) and rope (2-strand twists) sections, helical curls
--   and coils, and the scalp shell (fades, stubble, line-ups) with UVs for a strand texture
-- Everything is built in NOMINAL space: the 1.2-stud head AnatomySkull describes (+X right, +Y up, -Z
-- forward, origin at the Head part's centre). AnatomyHair scales the finished pieces to the real head.
local Shared = script.Parent
local MeshKit = require(Shared:WaitForChild("MeshKit"))

-- the skull the Head section builds (shared contract); a missing module falls back to the contract's ellipsoid
local Skull
do
	local ms = Shared:FindFirstChild("AnatomySkull")
	if ms then
		local ok, mod = pcall(require, ms)
		if ok and type(mod) == "table" then
			Skull = mod
		end
	end
end

local Kit = {}

local sqrt, abs, floor, min, max = math.sqrt, math.abs, math.floor, math.min, math.max
local sin, cos, atan2, pi, exp = math.sin, math.cos, math.atan2, math.pi, math.exp
local TAU = pi * 2
local noise3, hash3 = MeshKit.Noise, MeshKit.Hash3
local step = MeshKit.Step
local vertex, tri = MeshKit.Vertex, MeshKit.Tri

Kit.NOMINAL = 1.2

------------------------------------------------------------------------
-- Small maths
------------------------------------------------------------------------
local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smoothstep(e0, e1, x)
	if e0 == e1 then
		return x < e0 and 0 or 1
	end
	local t = clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function norm3(x, y, z)
	local l = sqrt(x * x + y * y + z * z)
	if l < 1e-12 then
		return 0, 0, 0, 0
	end
	return x / l, y / l, z / l, l
end

local function acosClamp(v)
	return math.acos(clamp(v, -1, 1))
end

local function cross(ax, ay, az, bx, by, bz)
	return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return d
	end
	return v
end

Kit.clamp, Kit.lerp, Kit.smoothstep, Kit.norm3, Kit.cross, Kit.num = clamp, lerp, smoothstep, norm3, cross, num

-- polynomial smooth min (k = blend width)
local function smin(a, b, k)
	local h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
	return b + (a - b) * h - k * h * (1 - h)
end

-- ellipsoid distance (Quilez' bound)
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

local function sdCapsule(x, y, z, ax, ay, az, bx, by, bz, r)
	local abx, aby, abz = bx - ax, by - ay, bz - az
	local px, py, pz = x - ax, y - ay, z - az
	local h = clamp((px * abx + py * aby + pz * abz) / (abx * abx + aby * aby + abz * abz), 0, 1)
	local dx, dy, dz = px - abx * h, py - aby * h, pz - abz * h
	return sqrt(dx * dx + dy * dy + dz * dz) - r
end

local function sdRoundBox(x, y, z, hx, hy, hz, r)
	local qx, qy, qz = abs(x) - hx + r, abs(y) - hy + r, abs(z) - hz + r
	local ox, oy, oz = max(qx, 0), max(qy, 0), max(qz, 0)
	return sqrt(ox * ox + oy * oy + oz * oz) + min(max(qx, max(qy, qz)), 0) - r
end

-- a string or number as a seed (styles, piece names): deterministic everywhere
function Kit.Seed(...)
	local h = 2166136
	for _, v in ipairs({ ... }) do
		local s = tostring(v)
		for i = 1, #s do
			h = (h * 31 + string.byte(s, i)) % 2147483629
		end
	end
	return h
end

-- value noise in a rotated domain: lattice noise sliced by a near-spherical surface shows concentric rings
-- wherever the surface lies tangent to the lattice planes; oblique rotations (one per octave) break them up
local R1 = { 0.7071, -0.4082, 0.5774, 0.7071, 0.4082, -0.5774, 0, 0.8165, 0.5774 }
local R2 = { 0.3333, 0.9107, -0.244, -0.244, 0.3333, 0.9107, 0.9107, -0.244, 0.3333 }
-- per-texel white noise in [0, 1): an integer avalanche hash (xorshift-multiply, exact in doubles through
-- 16-bit halves). MeshKit.Hash3 is linear in its inputs up to its LCG steps, which turns a texel grid into
-- diagonal stripes (a crosshatch); this one has no lattice structure
local band, bxor, rshift = bit32.band, bit32.bxor, bit32.rshift
local function mul32(a, m)
	local lo, hi = band(a, 0xFFFF), rshift(a, 16)
	local mlo, mhi = band(m, 0xFFFF), rshift(m, 16)
	local mid = (hi * mlo + lo * mhi) % 65536
	return (lo * mlo + mid * 65536) % 4294967296
end
local function whiteHash(ix, iy, s)
	local h = bxor(mul32(ix % 4294967296, 0x9E3779B1), mul32(iy % 4294967296, 0x85EBCA77), mul32((s or 0) % 4294967296, 0xC2B2AE3D))
	h = mul32(bxor(h, rshift(h, 15)), 0x2C1B3C6D)
	h = mul32(bxor(h, rshift(h, 12)), 0x297A2D39)
	h = bxor(h, rshift(h, 15))
	return h / 4294967296
end
Kit.WhiteHash = whiteHash
-- the texture shaders call it once or twice per texel: a 128 x 128 tile of the hash (filled on first use in a
-- few ms, a pure function of the indices; white noise shows no repeat) indexed with the seed folded into an
-- offset is far cheaper than hashing every texel
local WT
function Kit.White(ix, iy, s)
	if not WT then
		WT = table.create(16384)
		for j = 0, 127 do
			for i = 0, 127 do
				WT[j * 128 + i + 1] = whiteHash(i, j, 7)
			end
			step(128)
		end
	end
	-- the seed picks a (wrapping) offset into the tile
	local off = ((s or 0) * 40503 + 12345) % 16384
	return WT[((iy + off // 128) % 128) * 128 + (ix + off) % 128 + 1]
end

-- cellular (Worley) noise: worley = Kit.Worley(seed); f1, f2, id = worley(x, y, z) -> the distances to the
-- nearest and second nearest feature point (cell units) and the nearest one's random id in [0, 1). One
-- jittered point per unit cell (kept in the middle half, so the 2 x 2 x 2 block of cells nearest the sample
-- holds the near points: 8 cells instead of 27); points are cached per call site (one texture).
function Kit.Worley(seed)
	local cache = {}
	local s = (seed or 0) % 65521
	local function cellPoint(ix, iy, iz)
		local key = ((ix % 1024) * 1024 + (iy % 1024)) * 1024 + (iz % 1024)
		local p = cache[key]
		if not p then
			-- the avalanche hash (MeshKit.Hash3 is too regular between neighbouring cells: a visible lattice)
			local a, b = ix + iz * 7919, iy - iz * 104729
			p = {
				ix + 0.25 + 0.5 * whiteHash(a, b, s), iy + 0.25 + 0.5 * whiteHash(a, b, s + 1),
				iz + 0.25 + 0.5 * whiteHash(a, b, s + 2), whiteHash(a, b, s + 3),
			}
			cache[key] = p
		end
		return p
	end
	return function(x, y, z)
		local ix, iy, iz = floor(x - 0.5), floor(y - 0.5), floor(z - 0.5)
		local f1, f2, id = 1e9, 1e9, 0
		for dz = 0, 1 do
			for dy = 0, 1 do
				for dx = 0, 1 do
					local p = cellPoint(ix + dx, iy + dy, iz + dz)
					local ex, ey, ez = p[1] - x, p[2] - y, p[3] - z
					local d = ex * ex + ey * ey + ez * ez
					if d < f1 then
						f2 = f1
						f1, id = d, p[4]
					elseif d < f2 then
						f2 = d
					end
				end
			end
		end
		return sqrt(f1), sqrt(f2), id
	end
end

function Kit.RNoise(x, y, z, f, seed, which)
	local R = which == 2 and R2 or R1
	return noise3((R[1] * x + R[2] * y + R[3] * z) * f, (R[4] * x + R[5] * y + R[6] * z) * f, (R[7] * x + R[8] * y + R[9] * z) * f, seed)
end

------------------------------------------------------------------------
-- The scalp
------------------------------------------------------------------------
-- AnatomySkull's natural hairline keys (angle from the front centre, nominal height), for a missing module
local function fallbackKeys(P)
	local front, temple, rec, fem = P.hairFront, P.hairTemple, P.recede, P.female
	return {
		{ 0.0, front }, { 0.35, front - 0.012 - 0.02 * rec }, { 0.64, temple }, { 0.98, temple - 0.04 },
		{ 1.2, temple - 0.09 }, { 1.3, fem and 0.0 or -0.07 }, { 1.42, fem and 0.03 or -0.02 }, { 1.52, 0.1 },
		{ 1.74, 0.125 }, { 1.95, 0.1 }, { 2.08, -0.06 }, { 2.45, -0.17 }, { pi, -0.27 },
	}
end

-- the contract's fallback skull (ANATOMY_CONTRACTS section 6), in nominal space
local function fallbackParams(look)
	local rig = type(look.rig) == "table" and look.rig or {}
	local parts = type(rig.parts) == "table" and rig.parts or {}
	local s = type(parts.Head) == "table" and parts.Head or { 1.2, 1.2, 1.2 }
	local f = type(look.face) == "table" and look.face or {}
	local female = look.g == 2
	local age = num(look.age, 26)
	local P = {
		sx = num(s[1], 1.2), sy = num(s[2], 1.2), sz = num(s[3], 1.2), female = female, age = age,
		seed = floor(abs(num(f.seed, 7))) % 1000000,
	}
	P.kx, P.ky, P.kz = P.sx / 1.2, P.sy / 1.2, P.sz / 1.2
	P.cw = 0.516 * (1 + 0.05 * clamp(num(f.skullWidth, 0), -1, 1))
	P.ch = 0.576 * (1 + 0.04 * clamp(num(f.crown, 0), -1, 1))
	P.cd = 0.6 * (1 + 0.05 * clamp(num(f.skullLength, 0), -1, 1))
	P.cy, P.cz = 0.072, 0.036
	local fh = clamp(num(f.forehead, 0), -1, 1)
	local recede = clamp((age - 24) / 30, 0, 1) * (female and 0.15 or 0.75)
	P.hairFront = 0.335 + 0.04 * fh + 0.02 * recede
	P.hairTemple = P.hairFront - (female and 0.035 or 0.06) - 0.06 * recede
	P.recede = recede
	return P
end

-- S = Kit.Scalp(look): the skull field (nominal), rays / normals / projection, the hairline keys and a
-- body proxy. Reads only Hair-section look paths (rig.parts.Head, rig.joints.Neck, rig.parts.UpperTorso,
-- face.*, g, age through AnatomySkull).
function Kit.Scalp(look)
	local P, field, keys
	if Skull and type(Skull.Params) == "function" and type(Skull.Nominal) == "function" then
		local ok, p = pcall(Skull.Params, look)
		if ok and type(p) == "table" then
			local ok2, fn = pcall(Skull.Nominal, p)
			if ok2 and type(fn) == "function" then
				P, field = p, fn
				if type(Skull.HairlineHeights) == "function" then
					local ok3, k = pcall(Skull.HairlineHeights, p)
					if ok3 and type(k) == "table" and #k >= 3 then
						keys = k
					end
				end
			end
		end
	end
	if not field then
		P = fallbackParams(look)
		local cw, ch, cd, cy, cz = P.cw, P.ch, P.cd, P.cy, P.cz
		field = function(x, y, z)
			return sdE(x, y - cy, z - cz, cw, ch, cd)
		end
	end
	keys = keys or fallbackKeys(P)
	local S = {
		P = P, f = field, keys = keys, kx = num(P.kx, 1), ky = num(P.ky, 1), kz = num(P.kz, 1),
		cx = 0, cy = num(P.cy, 0.15), cz = num(P.cz, 0.06), seed = floor(num(P.seed, 7)), female = P.female == true,
		age = num(P.age, 26),
	}
	local f = field
	local cx, cy, cz = S.cx, S.cy, S.cz

	-- outward unit normal of the field (tetrahedral differences: 4 samples)
	local H = 0.003
	local function normal(x, y, z)
		local a = f(x + H, y - H, z - H)
		local b = f(x - H, y - H, z + H)
		local c = f(x - H, y + H, z - H)
		local d = f(x + H, y + H, z + H)
		local nx, ny, nz = norm3(a - b - c + d, -a - b + c + d, -a + b - c + d)
		if nx == 0 and ny == 0 and nz == 0 then
			return norm3(x - cx, y - cy, z - cz)
		end
		return nx, ny, nz
	end
	S.normal = normal

	-- the point at signed offset `off` above the scalp along the ray from the cranium centre (dx, dy, dz unit)
	function S.ray(dx, dy, dz, off, t0)
		local t = t0 or 0.5
		for _ = 1, 14 do
			local e = f(cx + dx * t, cy + dy * t, cz + dz * t) - off
			if abs(e) < 6e-5 then
				break
			end
			t = clamp(t - e * 0.95, 0.05, 2.5)
		end
		return cx + dx * t, cy + dy * t, cz + dz * t, t
	end

	-- onto the offset surface f = off (Newton along the normal)
	function S.onto(x, y, z, off)
		for _ = 1, 4 do
			local e = f(x, y, z) - off
			if abs(e) < 1e-4 then
				break
			end
			local nx, ny, nz = normal(x, y, z)
			x, y, z = x - nx * e, y - ny * e, z - nz * e
		end
		return x, y, z
	end

	-- pushed outside the offset surface (unchanged when already outside)
	function S.out(x, y, z, off)
		for _ = 1, 4 do
			local e = f(x, y, z) - off
			if e >= 0 then
				break
			end
			local nx, ny, nz = normal(x, y, z)
			x, y, z = x - nx * e, y - ny * e, z - nz * e
		end
		return x, y, z
	end

	-- angle around the head from the front centre (0 = front, pi = nape), the hairline keys' parameter
	function S.around(x, z)
		local a = atan2(-(z - 0.05), x)
		local da = abs(a - pi / 2)
		if da > pi then
			da = TAU - da
		end
		return da
	end

	-- body proxy (neck column, trapezius, chest / back) from the rig: what long hair, locs and tails rest on.
	-- Head space of the bind pose (Neck C0 in UpperTorso space, C1 in Head space; rotations ignored), nominal.
	local rig = type(look.rig) == "table" and look.rig or {}
	local joints = type(rig.joints) == "table" and rig.joints or {}
	local parts = type(rig.parts) == "table" and rig.parts or {}
	local neck = type(joints.Neck) == "table" and joints.Neck or {}
	local c0 = type(neck.c0) == "table" and neck.c0 or { 0, 0.811, 0 }
	local c1 = type(neck.c1) == "table" and neck.c1 or { 0, -0.6, 0 }
	local us = type(parts.UpperTorso) == "table" and parts.UpperTorso or { 2.0, 1.6, 1.0 }
	local kx, ky, kz = S.kx, S.ky, S.kz
	local ux = (num(c1[1], 0) - num(c0[1], 0)) / kx
	local uy = (num(c1[2], -0.6) - num(c0[2], 0.811)) / ky
	local uz = (num(c1[3], 0) - num(c0[3], 0)) / kz
	local hx, hy, hz = num(us[1], 2) / 2 / kx, num(us[2], 1.6) / 2 / ky, num(us[3], 1) / 2 / kz
	local top = uy + hy
	S.neckTop = top -- the torso box's top (the neck base), nominal y
	S.shoulderX = hx
	S.torso = { ux, uy, uz, hx, hy, hz }
	local rn = 0.31
	function S.body(x, y, z)
		local d = sdCapsule(x, y, z, 0, top + 0.45, 0.04, 0, top - 0.3, 0.0, rn)
		d = smin(d, sdE(x - ux, y - (top - 0.17), z - uz, hx * 0.94, 0.25, hz * 0.92), 0.2)
		d = smin(d, sdRoundBox(x - ux, y - uy, z - uz, hx * 0.88, hy, hz * 0.96, 0.2), 0.12)
		return d
	end
	local function bodyNormal(x, y, z)
		local a = S.body(x + H, y - H, z - H)
		local b = S.body(x - H, y - H, z + H)
		local c = S.body(x - H, y + H, z - H)
		local d = S.body(x + H, y + H, z + H)
		return norm3(a - b - c + d, -a - b + c + d, -a + b - c + d)
	end
	-- the face: hair may frame it, never hang in front of it (forehead fringes stop above the brows)
	function S.face(x, y, z)
		return sdE(x, y + 0.08, z + 0.36, 0.3, 0.42, 0.24)
	end
	local function faceNormal(x, y, z)
		return norm3(x / (0.3 * 0.3), (y + 0.08) / (0.42 * 0.42), (z + 0.36) / (0.24 * 0.24))
	end
	-- outside both the head (offset hoff) and the body (offset boff)
	function S.clear(x, y, z, hoff, boff)
		for _ = 1, 3 do
			local moved = false
			local e = f(x, y, z) - hoff
			if e < 0 then
				local nx, ny, nz = normal(x, y, z)
				x, y, z = x - nx * e, y - ny * e, z - nz * e
				moved = true
			end
			if y < top + 0.6 then
				local eb = S.body(x, y, z) - boff
				if eb < 0 then
					local nx, ny, nz = bodyNormal(x, y, z)
					if nx ~= 0 or ny ~= 0 or nz ~= 0 then
						x, y, z = x - nx * eb, y - ny * eb, z - nz * eb
						moved = true
					end
				end
			end
			if S.guardFace and y < 0.3 and z < -0.05 then
				local ef = S.face(x, y, z) - 0.01
				if ef < 0 then
					local nx, ny, nz = faceNormal(x, y, z)
					-- slide sideways off the face rather than straight out of it
					nx, ny, nz = norm3(nx + (x >= 0 and 0.6 or -0.6), ny * 0.3, nz * 0.5)
					x, y, z = x - nx * ef, y - ny * ef, z - nz * ef
					moved = true
				end
			end
			if not moved then
				break
			end
		end
		return x, y, z
	end
	return S
end

------------------------------------------------------------------------
-- Hairline and coverage
------------------------------------------------------------------------
-- cosine interpolation over the keys (angle from the front, height): h, dh/dangle
local function keyed(K, da)
	local n = #K
	if da <= K[1][1] then
		return K[1][2], 0
	end
	for i = 1, n - 1 do
		local a0, a1 = K[i][1], K[i + 1][1]
		if da <= a1 then
			local t = (da - a0) / (a1 - a0)
			local s = (1 - cos(t * pi)) * 0.5
			local h0, h1 = K[i][2], K[i + 1][2]
			return h0 + (h1 - h0) * s, (h1 - h0) * 0.5 * pi * sin(t * pi) / (a1 - a0)
		end
	end
	return K[n][2], 0
end
Kit.Keyed = keyed

-- hairline of a hairline type: returns dist(x, y, z) -> signed studs along the scalp (> 0 on the hair side),
-- height(da) -> nominal height of the line, and the edge softness. growth (0..1.5) softens a line-up.
function Kit.Hairline(S, kind, growth)
	kind = kind or "Natural"
	growth = growth or 0
	local K = {}
	for i, k in ipairs(S.keys) do
		K[i] = { k[1], k[2] }
	end
	local front = K[1][2]
	local soft, wobble, peak = 0.016, 1, 0
	if kind == "Straight" or kind == "Line-Up" then
		-- a straight front line with defined temple corners
		for _, k in ipairs(K) do
			if k[1] <= 0.5 then
				k[2] = front - 0.004
			elseif k[1] <= 0.66 then
				k[2] = front - 0.012
			end
		end
		soft, wobble = kind == "Line-Up" and 0.003 or 0.008, kind == "Line-Up" and 0 or 0.35
		if kind == "Line-Up" and growth > 0.2 then
			-- the edge grows back in over ~two weeks
			soft = lerp(0.003, 0.014, smoothstep(0.2, 0.6, growth))
			wobble = smoothstep(0.2, 0.6, growth)
		end
	elseif kind == "Widow's Peak" then
		peak = 0.05
		soft = 0.011
	elseif kind == "Receding" then
		for _, k in ipairs(K) do
			local da = k[1]
			if da <= 1.15 then
				-- the temples go first, the front centre less (an M-shaped line)
				k[2] += 0.03 + 0.085 * smoothstep(0.15, 0.62, da) * (1 - smoothstep(0.7, 1.15, da) * 0.6)
			end
		end
		soft = 0.02
	end
	local seed = S.seed
	local w1, w2 = seed % 7, seed % 11
	local function height(da)
		local h = keyed(K, da)
		if peak > 0 then
			local v = max(0, 1 - da / 0.24)
			h -= peak * v * v
		end
		if wobble > 0 then
			h += wobble * (0.006 * sin(da * 9 + w1) + 0.004 * sin(da * 23 + w2))
		end
		return h
	end
	-- the line's height sampled finely over the angle from the front (the window search below)
	local NH = 256
	local HT = table.create(NH + 1)
	for k = 0, NH do
		HT[k + 1] = height(k / NH * pi)
	end
	local function hAt(a)
		a = abs(a)
		if a > pi then
			a = TAU - a
		end
		local s = a / pi * NH
		local k = min(NH - 1, floor(s))
		local u = s - k
		return HT[k + 1] + (HT[k + 2] - HT[k + 1]) * u
	end
	local function dist(x, y, z)
		local da = S.around(x, z)
		local h, slope = keyed(K, da)
		if peak > 0 then
			local v = max(0, 1 - da / 0.24)
			h -= peak * v * v
		end
		if wobble > 0 then
			h += wobble * (0.006 * sin(da * 9 + w1) + 0.004 * sin(da * 23 + w2))
		end
		local r = max(sqrt(x * x + (z - 0.05) * (z - 0.05)), 0.15)
		local sl = slope / r
		local dy = y - h
		local d0 = dy / sqrt(1 + sl * sl)
		local ay = abs(dy)
		if ay > 0.03 and abs(sl) > 1.2 then
			-- where the line is steep (the sideburns, round the ears) the local estimate collapses away from it
			-- (it would read a groove of "near the hairline" up the side of the head to the crown): there, the
			-- distance to the line's points in a window round this angle
			local best = ay
			for k = 1, 8 do
				local o = k * 0.05
				local hx = r * o
				if hx >= best then
					break
				end
				local e1, e2 = y - hAt(da - o), y - hAt(da + o)
				best = min(best, sqrt(hx * hx + e1 * e1), sqrt(hx * hx + e2 * e2))
			end
			return lerp(d0, dy >= 0 and best or -best, smoothstep(0.03, 0.08, ay)), da, h
		end
		return d0, da, h
	end
	return dist, height, soft
end

-- fade shapes: where the sides start to fade (nominal height at the side / at the back) and the hair left
-- at the bottom (0 = shaved to the skin)
Kit.FADES = {
	low = { side = 0.13, back = 0.0, bottom = 0.0 },
	mid = { side = 0.22, back = 0.1, bottom = 0.0 },
	high = { side = 0.31, back = 0.22, bottom = 0.0 },
	fade = { side = 0.21, back = 0.08, bottom = 0.12 },
	taper = { band = 0.075, bottom = 0.12 },
	burst = { bottom = 0.0 },
}

-- The cut: coverage (0 = bare scalp .. 1 = full hair) and shell thickness at a scalp point. spec:
--   hairline (type), growth, fade = Kit.FADES key or nil, top / side (shell thickness, studs),
--   density (0..1: how much scalp shows through), region = fn(x, y, z, da) -> 0..1 (mohawk strip, undercut
--   top: outside it the hair is a shaved stubble of `shaved` coverage), shaved (0..1), part = x of a parting or nil
function Kit.Cut(S, spec)
	local growth = spec.growth or 0
	local grow = clamp(growth / 0.5, 0, 1)
	local dist, height, soft = Kit.Hairline(S, spec.hairline, growth)
	local fade = spec.fade and Kit.FADES[spec.fade]
	local fadeKind = spec.fade
	-- fadeLift: the fade's lines a little higher (dense coily hair hides a low gradient: it is cut higher)
	local lift = spec.fadeLift or 0
	if fade and lift ~= 0 then
		fade = table.clone(fade)
		fade.side = fade.side and fade.side + lift
		fade.back = fade.back and fade.back + lift
		fade.band = fade.band and fade.band * (1 + lift * 6)
	end
	local bottom = fade and lerp(fade.bottom or 0, 1, 0.85 * grow) or 1
	local density = spec.density or 1
	local region, shaved = spec.region, spec.shaved or 0.2
	local top, side = spec.top or 0.03, spec.side or spec.top or 0.03
	local part = spec.part
	local seed = S.seed

	-- the fade alone at (x, y, z) with the angle da: 0..1 multiplier on coverage
	local function fadeAt(x, y, z, da, hl)
		if not fade then
			return 1
		end
		if fadeKind == "taper" then
			-- only the sideburns and the nape taper, in a narrow band above the hairline
			local w = smoothstep(0.95, 1.2, da) * (1 - smoothstep(1.45, 1.6, da)) + smoothstep(1.95, 2.3, da)
			local u = clamp((y - hl) / fade.band, 0, 1)
			return lerp(1, lerp(bottom, 1, smoothstep(0, 1, u)), clamp(w, 0, 1))
		elseif fadeKind == "burst" then
			-- a half circle around each ear, the back stays full
			local r = sqrt((y - 0.01) * (y - 0.01) + (z - 0.02) * (z - 0.02))
			local w = smoothstep(0.2, 0.34, abs(x)) * (1 - smoothstep(0.24, 0.42, z))
			return lerp(1, lerp(bottom, 1, smoothstep(0.1, 0.27, r)), w)
		end
		local w = smoothstep(0.55, 1.0, da)
		local yTop = lerp(fade.side, fade.back, smoothstep(1.7, 2.75, da))
		local u = clamp((y - hl) / max(0.04, yTop - hl), 0, 1)
		return lerp(1, lerp(bottom, 1, u * u * (3 - 2 * u)), w)
	end

	-- coverage, the hairline distance and the fade factor at a nominal point
	local function cov(x, y, z)
		local d, da, hl = dist(x, y, z)
		local c = smoothstep(-soft * 0.6, soft, d)
		if c <= 0 then
			return 0, d, 0, da
		end
		local fd = fadeAt(x, y, z, da, hl)
		c *= fd
		if region then
			local r = region(x, y, z, da)
			c *= lerp(shaved * (1 - 0.4 * (1 - grow)) + 0.5 * grow * shaved, 1, r)
		end
		if part and y > 0.3 and z < 0.22 then
			-- a parting: a thin line of scalp from the front hairline back over the top
			local w = 0.006 + 0.004 * (1 - grow)
			local pd = abs(x - part * (1 - 0.15 * (z + 0.45)))
			c *= lerp(0.35 + 0.5 * grow, 1, smoothstep(w * 0.4, w, pd))
		end
		return c * density, d, fd, da
	end

	-- shell offset over the scalp: the top / side thickness, thinning through the fade. No rim anywhere: the
	-- shell lies under the skin (-SINK: the head's own scalp shows) where the cut leaves bare skin, comes up as
	-- a stubble-thin layer where the coverage starts (the visible edge is sparse hair over skin, dithered in the
	-- texture, not a line) and only then thickens, over a band ~3.5 x its thickness wide (a gentle slope
	-- instead of a ledge or a visor). Returns offset, coverage
	local edgeW = spec.edge or 0.05
	local thin = spec.thin or 0.0025
	local SINK = 0.015
	local function thick(x, y, z)
		local c, d, fd, da = cov(x, y, z)
		local wTop = smoothstep(0.16, 0.4, y)
		local t = lerp(side, top, wTop)
		local emerge = spec.emerge or 0.04
		if region then
			local r = region(x, y, z, da)
			t = lerp(thin + 0.004 * grow, t, r)
			-- a freshly shaved region is the head's own skin (the shell stays under it); stubble grown out
			-- past ~a quarter coverage comes up as a thin layer
			emerge = lerp(0.2, emerge, r)
		end
		t *= clamp(fd, 0, 1) ^ 0.7
		local gc = smoothstep(emerge, emerge + 0.16, c / max(density, 0.2))
		local gd = smoothstep(0, max(edgeW, 3.5 * t), d)
		-- under bare skin the shell sinks ~1.5 cm (nominal 0.015): deep enough that the head mesh's own
		-- facets (its chords cut below the smooth skull field) never leave a gap at the shell's edge
		return -SINK + (thin + SINK) * gc + max(t - thin, 0) * gc * gd * gd ^ 0.3, c
	end
	return { cov = cov, thick = thick, dist = dist, height = height, soft = soft, grow = grow, seed = seed }
end

------------------------------------------------------------------------
-- Hair colour
------------------------------------------------------------------------
local GREY = { 0.7, 0.69, 0.67 }

-- palette for a look: pal.at(rnd, t, x) -> r, g, b (0..1 sRGB) for a strand group with random rnd (0..1),
-- position t along it (0 root .. 1 tip) and side x; pal.base, pal.alt
function Kit.Palette(look, htype)
	local hair = type(look.hair) == "table" and look.hair or {}
	local function rgb(c, d)
		if type(c) == "table" and type(c[1]) == "number" then
			return { clamp(c[1] / 255, 0, 1), clamp(num(c[2], 0) / 255, 0, 1), clamp(num(c[3], 0) / 255, 0, 1) }
		end
		return d
	end
	local base = rgb(hair.color, { 0.086, 0.075, 0.067 })
	local alt = rgb(hair.hcolor, { 0.77, 0.61, 0.36 })
	local dye = type(hair.dye) == "string" and hair.dye or "None"
	local hl = hair.hl == true
	local age = num(look.age, 26)
	-- grey strands from the mid thirties (salt and pepper), more on the temples
	local greyFrac = clamp((age - 38) / 40, 0, 0.55)
	local lum = 0.3 * base[1] + 0.59 * base[2] + 0.11 * base[3]
	-- curly / coily hair scatters light: roots barely darker, tips not sun-bleached
	local coil = htype == "Coiled" or htype == "Kinky"
	local rootK = coil and 0.9 or (htype == "Curly" and 0.84 or 0.78)
	local tipK = coil and 1.02 or 1.07
	local pal = { base = base, alt = alt, dye = dye, hl = hl, grey = greyFrac, lum = lum, greyRGB = GREY }
	-- where an ombre turns (nominal height): the same line on the cap, every clump, the sheets and the locs,
	-- lower for shorter hair
	local L = clamp(num(hair.length, 0.5), 0, 1)
	local dyeY = -0.05 - 0.25 * (1 - L)
	pal.dyeY = dyeY
	-- at(rnd, t, x [, noGrey, y, tipDist, streakMask]) -> r, g, b:
	--   noGrey: without greying (the cap texture and the clumps draw their grey strands themselves)
	--   y: the point's nominal height (an ombre is a horizontal gradient at one height on every lock)
	--   tipDist: studs from the strand's tip (dyed tips are the last few centimetres, on every lock alike)
	--   streakMask: 0..1, how much of a streak this point carries (a streak is a band of a clump, not all of it)
	function pal.at(rnd, t, x, noGrey, y, tipDist, streakMask)
		local c = base
		local r, g, b = c[1], c[2], c[3]
		if dye == "Tips" then
			-- the dyed length differs a little from lock to lock, its edge a soft ~6 cm blend
			local k = tipDist and smoothstep(0.13, 0.03, tipDist * (0.75 + 0.5 * ((rnd * 3.71) % 1))) or smoothstep(0.6, 0.85, t)
			r, g, b = lerp(r, alt[1], k), lerp(g, alt[2], k), lerp(b, alt[3], k)
		elseif dye == "Ombre" then
			local k = y and smoothstep(dyeY + 0.12, dyeY - 0.3, y) or smoothstep(0.25, 0.95, t)
			r, g, b = lerp(r, alt[1], k), lerp(g, alt[2], k), lerp(b, alt[3], k)
		elseif dye == "Streaks" then
			if rnd < 0.18 then
				local k = 0.7 * (streakMask or 1)
				r, g, b = lerp(r, alt[1], k), lerp(g, alt[2], k), lerp(b, alt[3], k)
			end
		elseif dye == "Split" then
			local k = smoothstep(-0.02, 0.02, x or 0)
			r, g, b = lerp(r, alt[1], k), lerp(g, alt[2], k), lerp(b, alt[3], k)
		elseif hl and rnd < 0.24 then
			local k = 0.65 * (streakMask or 1)
			r, g, b = lerp(r, alt[1], k), lerp(g, alt[2], k), lerp(b, alt[3], k)
		end
		if greyFrac > 0 and not noGrey then
			-- a clump holds many strands, some of them grey: every clump about the same mix (salt and pepper
			-- reads evenly, not as some white locks among brown ones); light hair shows its grey less
			local k = clamp(greyFrac * (0.45 + 0.3 * ((rnd * 7.31) % 1)), 0, 0.9) * (1 - 0.3 * smoothstep(0.25, 0.5, lum))
			r, g, b = lerp(r, GREY[1], k), lerp(g, GREY[2], k), lerp(b, GREY[3], k)
		end
		-- per-group variation, darker roots, lighter tips
		local v = 0.9 + 0.2 * ((rnd * 13.7) % 1)
		local k = v * lerp(rootK, 1, smoothstep(0, 0.4, t)) * lerp(1, tipK, smoothstep(0.5, 1, t))
		-- very dark hair is a deep warm brown-black, not a void: lift it so its texture and sheen can read
		local lift = lum < 0.14 and 0.045 * (1 - lum / 0.14) + 0.01 or 0
		return clamp(r * k + lift, 0, 1), clamp(g * k + lift * 0.9, 0, 1), clamp(b * k + lift * 0.8, 0, 1)
	end
	return pal
end

-- skin colour (sRGB 0..1) the scalp shows
function Kit.Skin(look)
	local s = type(look.skinRGB) == "table" and look.skinRGB or { 186, 128, 88 }
	return { clamp(num(s[1], 186) / 255, 0, 1), clamp(num(s[2], 128) / 255, 0, 1), clamp(num(s[3], 88) / 255, 0, 1) }
end

------------------------------------------------------------------------
-- Comb flows and strand paths
------------------------------------------------------------------------
-- the crown whorl hair grows away from (nominal, a little behind the top and off centre)
function Kit.Whorl(S)
	local side = (S.seed % 2 == 0) and 1 or -1
	local x, y, z = S.ray(norm3(0.07 * side, 0.82, 0.55))
	return x, y, z, side
end

-- flow(kind, opts) -> fn(x, y, z, nx, ny, nz) -> unit tangent the hair runs along at that scalp point.
-- kinds: "whorl" (natural growth), "back" (combed back), "forward", "down", "side" (swept across, opts.dir
-- = +1 toward the right), "part" (away from a parting at opts.x), "tie" (toward opts.p), "up" (standing)
function Kit.Flow(S, kind, opts)
	opts = opts or {}
	local wx, wy, wz, wside = Kit.Whorl(S)
	local swirl = (opts.swirl or 0.6) * wside
	local function tangent(vx, vy, vz, nx, ny, nz)
		local d = vx * nx + vy * ny + vz * nz
		return norm3(vx - nx * d, vy - ny * d, vz - nz * d)
	end
	local function whorl(x, y, z, nx, ny, nz)
		local vx, vy, vz = x - wx, y - wy, z - wz
		local l = sqrt(vx * vx + vy * vy + vz * vz)
		-- a spiral around the whorl, fading out within a few centimetres
		local sw = swirl * exp(-l / 0.12)
		local cx, cy, cz = cross(nx, ny, nz, vx, vy, vz)
		return tangent(vx + cx * sw, vy + cy * sw, vz + cz * sw, nx, ny, nz)
	end
	if kind == "whorl" then
		return whorl
	elseif kind == "back" then
		return function(x, y, z, nx, ny, nz)
			local tx, ty, tz = tangent(0.12 * x, -0.25 - 0.4 * max(0, -y), 1, nx, ny, nz)
			if tx == 0 and ty == 0 and tz == 0 then
				return whorl(x, y, z, nx, ny, nz)
			end
			return tx, ty, tz
		end
	elseif kind == "forward" then
		return function(x, y, z, nx, ny, nz)
			local tx, ty, tz = tangent(0.18 * x, -0.3, -1, nx, ny, nz)
			if tx == 0 and ty == 0 and tz == 0 then
				return whorl(x, y, z, nx, ny, nz)
			end
			return tx, ty, tz
		end
	elseif kind == "down" then
		return function(x, y, z, nx, ny, nz)
			-- away from the crown, then straight down the sides and back
			local wx2, wy2, wz2 = whorl(x, y, z, nx, ny, nz)
			local k = smoothstep(0.25, 0.75, 1 - ny)
			local tx, ty, tz = tangent(wx2 * (1 - k), wy2 * (1 - k) - k, wz2 * (1 - k), nx, ny, nz)
			if tx == 0 and ty == 0 and tz == 0 then
				return wx2, wy2, wz2
			end
			return tx, ty, tz
		end
	elseif kind == "side" then
		local dir = opts.dir or 1
		return function(x, y, z, nx, ny, nz)
			local tx, ty, tz = tangent(dir, -0.25, 0.3 + 0.2 * z, nx, ny, nz)
			if tx == 0 and ty == 0 and tz == 0 then
				return whorl(x, y, z, nx, ny, nz)
			end
			return tx, ty, tz
		end
	elseif kind == "part" then
		local px = opts.x or 0
		return function(x, y, z, nx, ny, nz)
			local s = x >= px and 1 or -1
			local k = smoothstep(0.0, 0.12, abs(x - px))
			-- over the forehead the hair is combed out to the side and back round the temples (never down over
			-- the face); further back it falls from the parting down the sides
			local front = smoothstep(-0.1, -0.32, z) * smoothstep(-0.05, 0.2, y)
			-- the parting ends at the crown: behind it the hair falls straight down the back (no gap down the
			-- back of the head between the two sides)
			local behind = smoothstep(0.1, 0.36, z)
			local side = s * (0.4 + 0.6 * k) * (1 + 0.9 * front) * (1 - behind) + 0.12 * x * behind
			local tx, ty, tz = tangent(side, (-0.35 - 0.5 * k) * (1 - 0.8 * front) * (1 - behind) - behind,
				(0.25 + 0.3 * smoothstep(-0.2, 0.3, z) + 0.5 * front) * (1 - behind) + 0.35 * behind, nx, ny, nz)
			if tx == 0 and ty == 0 and tz == 0 then
				return whorl(x, y, z, nx, ny, nz)
			end
			return tx, ty, tz
		end
	elseif kind == "tie" then
		local p = opts.p or { 0, 0.3, 0.55 }
		return function(x, y, z, nx, ny, nz)
			local tx, ty, tz = tangent(p[1] - x, p[2] - y, p[3] - z, nx, ny, nz)
			if tx == 0 and ty == 0 and tz == 0 then
				return 0, -1, 0
			end
			return tx, ty, tz
		end
	elseif kind == "up" then
		return function(x, y, z, nx, ny, nz)
			return nx, ny, nz
		end
	end
	return whorl
end

-- grow a strand path from the scalp point (x, y, z). opts:
--   len (studs), ds (step), flow (Kit.Flow fn), lift (0..1: how far the root rises off the scalp),
--   off(u) -> offset above the scalp to keep (u = 0 root .. 1 tip), stick (0..1: combed hair hugs the skull
--   while the skull is above it), grav (0..1 weight), stiff (0..1: keeps its own direction),
--   bodyOff (clearance over the body proxy), dir = { x, y, z } initial direction override,
--   jitter = { amp, freq, seed } (spatially coherent direction noise), free (0..1: share of the length after
--   which the strand may leave the scalp even where the skull is still above it)
-- returns a list of { x, y, z } (root first) and the index where the strand left the scalp (or nil)
function Kit.Grow(S, x, y, z, opts)
	local f, normal = S.f, S.normal
	local len = opts.len or 0.3
	local ds = opts.ds or 0.03
	local n = max(2, floor(len / ds + 0.5))
	ds = len / n
	local flow = opts.flow
	local off = opts.off
	local stick = opts.stick or 0
	local grav = opts.grav or 0
	local stiff = opts.stiff or 0.5
	local lift = opts.lift or 0
	local bodyOff = opts.bodyOff or 0.035
	local freeAt = opts.free or 0.55
	local jit = opts.jitter
	-- glue: the strand never leaves the scalp (hair pulled tight into a tie, also under the occiput)
	local glue = opts.glue
	local top = S.neckTop + 0.6
	local nx, ny, nz = normal(x, y, z)
	local dx, dy, dz
	if opts.dir then
		dx, dy, dz = norm3(opts.dir[1], opts.dir[2], opts.dir[3])
	else
		dx, dy, dz = flow(x, y, z, nx, ny, nz)
	end
	dx, dy, dz = norm3(dx + nx * lift * 1.6, dy + ny * lift * 1.6, dz + nz * lift * 1.6)
	if dx == 0 and dy == 0 and dz == 0 then
		dx, dy, dz = 0, -1, 0
	end
	local pts = { { x, y, z } }
	local free = false
	local leftAt
	local k = (1 - stiff) * 0.55
	for i = 1, n do
		local u = i / n
		local o = type(off) == "function" and off(u) or (off or 0.01)
		-- steer: toward the comb flow while on the scalp, under gravity once free
		if flow and not free then
			local fx, fy, fz = flow(x, y, z, nx, ny, nz)
			dx += (fx - dx) * k
			dy += (fy - dy) * k
			dz += (fz - dz) * k
		end
		local g = grav * (free and 1 or smoothstep(0.1, 0.6, u) * 0.5)
		dy -= g * 0.9
		if jit then
			local a = jit.amp or 0.3
			local q = jit.freq or 6
			local sd = jit.seed or 0
			dx += a * noise3(x * q, y * q, z * q, sd)
			dy += a * 0.5 * noise3(x * q + 31, y * q, z * q, sd)
			dz += a * noise3(x * q, y * q + 17, z * q, sd)
		end
		dx, dy, dz = norm3(dx, dy, dz)
		if dx == 0 and dy == 0 and dz == 0 then
			dx, dy, dz = 0, -1, 0
		end
		local px, py, pz = x + dx * ds, y + dy * ds, z + dz * ds
		nx, ny, nz = normal(px, py, pz)
		local e = f(px, py, pz) - o
		if stick > 0 and not free then
			if (glue or ny > -0.25) and u <= max(freeAt, 0.98) then
				-- combed hair lies on the skull: pull it back onto its layer
				local q = e * stick
				px, py, pz = px - nx * q, py - ny * q, pz - nz * q
				e -= q
			else
				free = true
				leftAt = leftAt or i
			end
		elseif not free and (ny < -0.25 or u > freeAt) then
			free = true
			leftAt = leftAt or i
		end
		if e < 0 then
			px, py, pz = px - nx * e, py - ny * e, pz - nz * e
		end
		if (py < top and S.body(px, py, pz) < bodyOff) or (S.guardFace and py < 0.3 and pz < -0.05) then
			px, py, pz = S.clear(px, py, pz, o, bodyOff)
		end
		local ex, ey, ez = norm3(px - x, py - y, pz - z)
		if ex ~= 0 or ey ~= 0 or ez ~= 0 then
			dx, dy, dz = ex, ey, ez
		end
		x, y, z = px, py, pz
		pts[#pts + 1] = { x, y, z }
	end
	step(n * 4)
	return pts, leftAt
end

-- arc length of a polyline
function Kit.Length(pts)
	local L = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		L += sqrt(dx * dx + dy * dy + dz * dz)
	end
	return L
end

-- n points evenly spaced by arc length along a Catmull-Rom curve through pts
function Kit.Resample(pts, n)
	local m = #pts
	if m < 2 then
		local p = pts[1] or { 0, 0, 0 }
		local out = {}
		for i = 1, n do
			out[i] = { p[1], p[2] - 0.001 * i, p[3] }
		end
		return out
	end
	local cum = { 0 }
	for i = 2, m do
		local a, b = pts[i - 1], pts[i]
		local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		cum[i] = cum[i - 1] + sqrt(dx * dx + dy * dy + dz * dz)
	end
	local L = cum[m]
	local out = table.create(n)
	local j = 1
	for i = 1, n do
		local s = L * (i - 1) / (n - 1)
		while j < m - 1 and cum[j + 1] < s do
			j += 1
		end
		local seg = cum[j + 1] - cum[j]
		local t = seg > 1e-9 and (s - cum[j]) / seg or 0
		local p0, p1, p2, p3 = pts[max(1, j - 1)], pts[j], pts[j + 1], pts[min(m, j + 2)]
		local t2, t3 = t * t, t * t * t
		local o = {}
		for c = 1, 3 do
			o[c] = 0.5 * (2 * p1[c] + (p2[c] - p0[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
				+ (3 * p1[c] - p0[c] - 3 * p2[c] + p3[c]) * t3)
		end
		out[i] = o
	end
	return out, L
end

-- the "outward" direction hair sections face at a point: away from the skull while beside it, away from
-- the vertical axis below it (hair hanging on the neck and back faces out)
function Kit.Outward(S)
	local cx, cy, cz = S.cx, S.cy, S.cz
	return function(x, y, z)
		if y > cy - 0.1 then
			return norm3(x - cx, y - cy, z - cz)
		end
		local k = smoothstep(cy - 0.1, cy - 0.5, y)
		return norm3(x - cx, (y - cy) * (1 - k), (z - cz * (1 - k)))
	end
end

-- waves: offsets a resampled path sideways / outward with a sine of wavelength lam (studs), amplitude amp
-- growing from the root (rise = studs until full amplitude); phase in radians
function Kit.Wave(pts, out, amp, lam, phase, rise)
	local n = #pts
	local s = 0
	local res = table.create(n)
	for i = 1, n do
		local p = pts[i]
		if i > 1 then
			local q = pts[i - 1]
			s += sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2)
		end
		local a, b = pts[max(1, i - 1)], pts[min(n, i + 1)]
		local tx, ty, tz = norm3(b[1] - a[1], b[2] - a[2], b[3] - a[3])
		local ox, oy, oz = out(p[1], p[2], p[3])
		local sx, sy, sz = norm3(cross(tx, ty, tz, ox, oy, oz))
		local k = amp * smoothstep(0, rise or 0.08, s)
		local w = sin(s / lam * TAU + phase)
		-- mostly sideways (an S-wave in the plane of the hair), a little in and out
		res[i] = { p[1] + (sx * 0.85 + ox * 0.35) * k * w, p[2] + (sy * 0.85 + oy * 0.35) * k * w, p[3] + (sz * 0.85 + oz * 0.35) * k * w }
	end
	return res
end

------------------------------------------------------------------------
-- Geometry
------------------------------------------------------------------------
-- frames along a path: tangent T, side S (= T x O, O = the outward reference), up U (~O). Returns arrays
-- of 9 numbers per point { tx,ty,tz, sx,sy,sz, ux,uy,uz }
local function framesOf(pts, out)
	local n = #pts
	local F = table.create(n)
	local psx, psy, psz = 1, 0, 0
	for i = 1, n do
		local a, b = pts[max(1, i - 1)], pts[min(n, i + 1)]
		local tx, ty, tz = norm3(b[1] - a[1], b[2] - a[2], b[3] - a[3])
		if tx == 0 and ty == 0 and tz == 0 then
			tx, ty, tz = 0, -1, 0
		end
		local p = pts[i]
		local ox, oy, oz = out(p[1], p[2], p[3])
		local sx, sy, sz, l = norm3(cross(tx, ty, tz, ox, oy, oz))
		if l < 0.15 then
			-- the hair runs along the outward direction (standing up): keep the previous side axis
			local d = psx * tx + psy * ty + psz * tz
			sx, sy, sz = norm3(psx - tx * d, psy - ty * d, psz - tz * d)
			if sx == 0 and sy == 0 and sz == 0 then
				sx, sy, sz = norm3(cross(tx, ty, tz, 0, 0, 1))
				if sx == 0 and sy == 0 and sz == 0 then
					sx, sy, sz = 1, 0, 0
				end
			end
		end
		local ux, uy, uz = cross(sx, sy, sz, tx, ty, tz)
		F[i] = { tx, ty, tz, sx, sy, sz, ux, uy, uz }
		psx, psy, psz = sx, sy, sz
	end
	return F
end
Kit.Frames = framesOf

-- A flat strand clump (a group of strands combed together): lens section, half width w(t) x half thickness
-- h(t), twisted, tapering to a point. opts: sides (3..6), w, h (numbers or fn(t)), twist (radians),
-- color(t, k, sa) -> r, g, b (sa = sin of the section angle: +1 the outer face, -1 the scalp side),
-- out (Kit.Outward fn), tip ("point" default | "open")
-- Returns the vertex range.
function Kit.Clump(m, pts, opts)
	local n = #pts
	local sides = opts.sides or 5
	local wf, hf = opts.w, opts.h
	local twist = opts.twist or 0
	local color = opts.color
	local flat = opts.flat or 0
	local F = framesOf(pts, opts.out)
	local first = m.nv + 1
	local A = table.create(sides)
	for k = 1, sides do
		-- one vertex on the outer face's centre line for odd counts
		A[k] = pi / 2 + (k - 1) * TAU / sides
	end
	local last = opts.tip == "open" and n or n - 1
	for i = 1, last do
		local t = (i - 1) / (n - 1)
		local p, f = pts[i], F[i]
		local w = type(wf) == "function" and wf(t) or wf
		local h = type(hf) == "function" and hf(t) or hf
		local ca, sa = cos(twist * t), sin(twist * t)
		-- twisted side / up axes
		local sx, sy, sz = f[4] * ca + f[7] * sa, f[5] * ca + f[8] * sa, f[6] * ca + f[9] * sa
		local ux, uy, uz = f[7] * ca - f[4] * sa, f[8] * ca - f[5] * sa, f[9] * ca - f[6] * sa
		for k = 1, sides do
			local a = A[k]
			local c, s = cos(a), sin(a)
			local x = p[1] + sx * w * c + ux * h * s
			local y = p[2] + sy * w * c + uy * h * s
			local z = p[3] + sz * w * c + uz * h * s
			local r, g, b = 1, 1, 1
			if color then
				r, g, b = color(t, k, s)
			end
			local v = vertex(m, x, y, z, (k - 1) / sides, t, r, g, b)
			local nx, ny, nz = norm3(sx * h * c + ux * w * s, sy * h * c + uy * w * s, sz * h * c + uz * w * s)
			-- flat: the faces shade like the surface the clump lies on (its up axis); 1 = the whole section
			if flat > 0 and (s > -0.2 or flat >= 1) then
				nx, ny, nz = norm3(lerp(nx, ux, flat), lerp(ny, uy, flat), lerp(nz, uz, flat))
			end
			local N = m.N
			N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = nx, ny, nz
		end
	end
	for i = 1, last - 1 do
		local r0 = first + (i - 1) * sides
		local r1 = r0 + sides
		for k = 0, sides - 1 do
			local k1 = (k + 1) % sides
			tri(m, r0 + k, r1 + k, r0 + k1)
			tri(m, r1 + k, r1 + k1, r0 + k1)
		end
	end
	if opts.tip ~= "open" then
		local p, f = pts[n], F[n]
		local r, g, b = 1, 1, 1
		if color then
			r, g, b = color(1, 0, 1)
		end
		local v = vertex(m, p[1], p[2], p[3], 0.5, 1, r, g, b)
		local N = m.N
		N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = f[1], f[2], f[3]
		local r0 = first + (last - 1) * sides
		for k = 0, sides - 1 do
			tri(m, r0 + k, v, r0 + (k + 1) % sides)
		end
	end
	step((m.nv - first + 1) * 2)
	return first, m.nv
end

-- a fine strand: a flat card (two vertices across) facing outward, tapering to a point; the piece is
-- drawn double sided. opts: w (half width, number or fn(t)), color(t) -> r, g, b, out
function Kit.Strand(m, pts, opts)
	local n = #pts
	local F = framesOf(pts, opts.out)
	local wf = opts.w or 0.006
	local color = opts.color
	local first = m.nv + 1
	local N = m.N
	for i = 1, n - 1 do
		local t = (i - 1) / (n - 1)
		local p, f = pts[i], F[i]
		local w = type(wf) == "function" and wf(t) or wf
		local r, g, b = 1, 1, 1
		if color then
			r, g, b = color(t)
		end
		for side = -1, 1, 2 do
			local v = vertex(m, p[1] + f[4] * w * side, p[2] + f[5] * w * side, p[3] + f[6] * w * side, (side + 1) / 2, t, r, g, b)
			N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = f[7], f[8], f[9]
		end
	end
	local p, f = pts[n], F[n]
	local r, g, b = 1, 1, 1
	if color then
		r, g, b = color(1)
	end
	local tip = vertex(m, p[1], p[2], p[3], 0.5, 1, r, g, b)
	N[tip * 3 - 2], N[tip * 3 - 1], N[tip * 3] = f[7], f[8], f[9]
	for i = 1, n - 2 do
		local a = first + (i - 1) * 2
		tri(m, a, a + 1, a + 2)
		tri(m, a + 1, a + 3, a + 2)
	end
	local a = first + (n - 2) * 2
	tri(m, a, a + 1, tip)
	step((n - 1) * 4)
	return first, m.nv
end

-- A round tube along pts with a polar section r(t, a) (a = angle from the side axis toward the outer
-- face): locs (lumps), braids (3-strand support function), twists (2 strands). Normals from the grid.
-- opts: sides, r = fn(t, a) or number, color(t, a, rr) -> r, g, b (rr = r / nominal radius), out,
-- tip = "point" | "dome" | "open", root = "open" | "dome", rad (nominal radius for the dome caps)
function Kit.Tube(m, pts, opts)
	local n = #pts
	local sides = opts.sides or 6
	local rf = opts.r
	local color = opts.color
	local F = framesOf(pts, opts.out)
	local rad = opts.rad or (type(rf) == "number" and rf or 0.03)
	-- ring list: dome rings at the root, the body, dome rings at the tip
	local rings = {}
	local function addRing(i, t, scale, push)
		rings[#rings + 1] = { i = i, t = t, s = scale, push = push }
	end
	local domeN = 2
	if opts.root == "dome" then
		for d = domeN, 1, -1 do
			local a = d / (domeN + 1) * pi / 2
			addRing(1, 0, cos(a), -sin(a) * rad)
		end
	end
	for i = 1, n do
		addRing(i, (i - 1) / (n - 1), 1, 0)
	end
	local tip = opts.tip or "point"
	if tip == "dome" then
		for d = 1, domeN do
			local a = d / (domeN + 1) * pi / 2
			addRing(n, 1, cos(a), sin(a) * rad)
		end
	end
	local R = #rings
	-- positions first (normals need the neighbours)
	local PX, PY, PZ = table.create(R * sides), table.create(R * sides), table.create(R * sides)
	local RR = table.create(R * sides)
	for j = 1, R do
		local ring = rings[j]
		local p, f = pts[ring.i], F[ring.i]
		local t = ring.t
		local cx, cy, cz = p[1] + f[1] * ring.push, p[2] + f[2] * ring.push, p[3] + f[3] * ring.push
		for k = 1, sides do
			local a = (k - 1) * TAU / sides
			local r = (type(rf) == "function" and rf(t, a) or rf) * ring.s
			local c, s = cos(a), sin(a)
			local o = (j - 1) * sides + k
			PX[o] = cx + (f[4] * c + f[7] * s) * r
			PY[o] = cy + (f[5] * c + f[8] * s) * r
			PZ[o] = cz + (f[6] * c + f[9] * s) * r
			RR[o] = r / max(rad, 1e-6)
		end
		-- (the section callback per vertex: noise lumps, plait lobes)
		step(sides * 2)
	end
	local first = m.nv + 1
	local N = m.N
	for j = 1, R do
		local ring = rings[j]
		local jp, jn = max(1, j - 1), min(R, j + 1)
		for k = 1, sides do
			local o = (j - 1) * sides + k
			local kp, kn = (k - 2) % sides + 1, k % sides + 1
			-- d/da x d/dt (outward for a ring that turns from the side axis toward the outer face)
			local ox, oy, oz = PX[(j - 1) * sides + kn] - PX[(j - 1) * sides + kp], PY[(j - 1) * sides + kn] - PY[(j - 1) * sides + kp],
				PZ[(j - 1) * sides + kn] - PZ[(j - 1) * sides + kp]
			local tx, ty, tz = PX[(jn - 1) * sides + k] - PX[(jp - 1) * sides + k], PY[(jn - 1) * sides + k] - PY[(jp - 1) * sides + k],
				PZ[(jn - 1) * sides + k] - PZ[(jp - 1) * sides + k]
			local nx, ny, nz = norm3(cross(tx, ty, tz, ox, oy, oz))
			if nx == 0 and ny == 0 and nz == 0 then
				local f = F[ring.i]
				local a = (k - 1) * TAU / sides
				nx, ny, nz = f[4] * cos(a) + f[7] * sin(a), f[5] * cos(a) + f[8] * sin(a), f[6] * cos(a) + f[9] * sin(a)
			end
			local r, g, b = 1, 1, 1
			if color then
				r, g, b = color(ring.t, (k - 1) * TAU / sides, RR[o])
			end
			local v = vertex(m, PX[o], PY[o], PZ[o], (k - 1) / sides, ring.t, r, g, b)
			N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = nx, ny, nz
		end
	end
	for j = 1, R - 1 do
		local r0 = first + (j - 1) * sides
		local r1 = r0 + sides
		for k = 0, sides - 1 do
			local k1 = (k + 1) % sides
			tri(m, r0 + k, r1 + k, r0 + k1)
			tri(m, r1 + k, r1 + k1, r0 + k1)
		end
	end
	-- closing vertices
	local function cap(j, push, flip)
		local ring = rings[j]
		local p, f = pts[ring.i], F[ring.i]
		local r, g, b = 1, 1, 1
		if color then
			r, g, b = color(ring.t, 0, 0.5)
		end
		local d = flip and -1 or 1
		local v = vertex(m, p[1] + f[1] * push, p[2] + f[2] * push, p[3] + f[3] * push, 0.5, ring.t, r, g, b)
		N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = f[1] * d, f[2] * d, f[3] * d
		local r0 = first + (j - 1) * sides
		for k = 0, sides - 1 do
			local k1 = (k + 1) % sides
			if flip then
				tri(m, r0 + k1, v, r0 + k)
			else
				tri(m, r0 + k, v, r0 + k1)
			end
		end
	end
	if tip == "point" then
		cap(R, rad * 0.9, false)
	elseif tip == "dome" or tip == "flat" then
		cap(R, tip == "dome" and rad or 0, false)
	end
	if opts.root == "dome" then
		cap(1, -rad, true)
	end
	step((m.nv - first + 1) * 3)
	return first, m.nv
end

-- points of a helix around a centreline (curls, coils, ringlets): radius rad(t), turns, phase; the
-- returned points are dense enough for a smooth sweep (perTurn samples per turn)
function Kit.Helix(pts, out, rad, turns, phase, perTurn)
	local F = framesOf(pts, out)
	local n = #pts
	local count = max(4, floor(turns * (perTurn or 8) + 0.5) + 1)
	local res = table.create(count)
	for i = 1, count do
		local t = (i - 1) / (count - 1)
		local s = t * (n - 1) + 1
		local i0 = min(n - 1, floor(s))
		local u = s - i0
		local p0, p1 = pts[i0], pts[i0 + 1]
		local f0, f1 = F[i0], F[i0 + 1]
		local px, py, pz = lerp(p0[1], p1[1], u), lerp(p0[2], p1[2], u), lerp(p0[3], p1[3], u)
		local sx, sy, sz = norm3(lerp(f0[4], f1[4], u), lerp(f0[5], f1[5], u), lerp(f0[6], f1[6], u))
		local ux, uy, uz = norm3(lerp(f0[7], f1[7], u), lerp(f0[8], f1[8], u), lerp(f0[9], f1[9], u))
		local r = type(rad) == "function" and rad(t) or rad
		local a = phase + TAU * turns * t
		local c, s2 = cos(a), sin(a)
		res[i] = { px + (sx * c + ux * s2) * r, py + (sy * c + uy * s2) * r, pz + (sz * c + uz * s2) * r }
	end
	return res
end

-- braided section (3 strands woven): radius of the union of three strand circles at angle a, for a braid of
-- half width w at arc parameter s (periods along the braid), strand radius rs. The strands cross the
-- middle in turn, so the outline shows the plait's alternating lobes.
function Kit.Plait(a, s, w, rs)
	local best = -1e9
	local ca, sa = cos(a), sin(a)
	for k = 0, 2 do
		local ph = s * TAU + k * TAU / 3
		local u = w * sin(ph)
		local v = w * 0.55 * sin(2 * ph)
		local d = u * ca + v * sa
		if d > best then
			best = d
		end
	end
	return best + rs
end

-- two strands twisted around each other (twists, rope): support radius at angle a, arc parameter s (turns)
function Kit.Rope(a, s, w, rs)
	local ph = s * TAU
	local d1 = w * cos(a - ph)
	local d2 = w * cos(a - ph - pi)
	return max(d1, d2) + rs
end

------------------------------------------------------------------------
-- The scalp shell (cap): fades, stubble, line-ups, the base of every cut
------------------------------------------------------------------------
-- A grid over the skull (azimuth x polar angle from the crown) down to just past the hairline, at the cut's
-- thickness above the scalp. opts: cut (Kit.Cut), cols, rows, color(x, y, z, c) -> r, g, b, extra
-- thickness fn(x, y, z, c) -> studs (volume shells), reach (studs past the hairline, default 0.022),
-- gridNormals (normals of the displaced surface: volumes), smooth (passes, default 3)
-- The skull's blend creases (the frontal bone meeting the vault) do not show through hair: the scalp radius
-- under the grid is smoothed (only filling dips, never sinking into the skull) and so are its normals. Quads
-- that lie wholly under the skin (bare scalp: a skin fade, past the hairline) are left out.
-- UVs: u = azimuth (seam at the back centre), v = polar angle / 2.75.
function Kit.Cap(S, m, opts)
	local cut = opts.cut
	local cols, rows = opts.cols or 40, opts.rows or 18
	local color = opts.color
	local extra = opts.extra
	local reach = opts.reach or 0.022
	local dist = cut.dist
	local first = m.nv + 1
	local N = m.N
	local cx, cy, cz = S.cx, S.cy, S.cz
	-- the polar angle where the scalp crosses `reach` outside the hairline, per column (bisection)
	local function dirOf(az, th)
		-- az: 0 = back centre (+Z), increasing toward the character's right (+X) seen from above
		local st = sin(th)
		return st * sin(az), cos(th), st * cos(az)
	end
	local thMax = table.create(cols + 1)
	local tw = 0.5
	for c = 0, cols do
		local az = c / cols * TAU
		local lo, hi = 0.3, 2.75
		for _ = 1, 11 do
			local mid = (lo + hi) * 0.5
			local dx, dy, dz = dirOf(az, mid)
			local x, y, z, t = S.ray(dx, dy, dz, 0, tw)
			tw = t
			if dist(x, y, z) > -reach then
				lo = mid
			else
				hi = mid
			end
			-- a ray march (up to 14 field samples) per iteration
			step(14)
		end
		thMax[c + 1] = lo
	end
	if opts.radial then
		-- a volume's mass spans the hairline's notches (round the ears, the temples): its rows run at the polar
		-- angles of a dilated, smoothed hairline (a column whose range drops where its neighbours' does not
		-- leaves long skinny triangles cutting chords through the mass: creases). The part past the true
		-- hairline sinks under the skin with the cut's thickness and is culled below.
		local w = max(1, floor(cols / 10))
		local D = table.create(cols + 1)
		for c = 0, cols do
			local m = 0
			for k = -w, w do
				local cc = (c + k) % cols
				m = max(m, thMax[cc + 1])
			end
			D[c + 1] = m
		end
		for _ = 1, 3 do
			local T = table.create(cols + 1)
			for c = 0, cols do
				local a, b = (c - 1) % cols, (c + 1) % cols
				T[c + 1] = 0.5 * D[c + 1] + 0.25 * (D[a + 1] + D[b + 1])
			end
			D = T
		end
		D[cols + 1] = D[1]
		thMax = D
	end
	-- crown pole cluster: a tiny ring first so UVs stay per column
	local TH0 = 0.035
	local stride = cols + 1
	local nG = (rows + 1) * stride
	-- per grid vertex: ray direction, scalp radius along it, normal, offset, coverage
	local DX, DY, DZ = table.create(nG), table.create(nG), table.create(nG)
	local R0, R = table.create(nG), table.create(nG)
	local NX, NY, NZ = table.create(nG), table.create(nG), table.create(nG)
	local OFF, CV = table.create(nG), table.create(nG)
	-- radial: the extra (a volume's depth) goes along the grid ray from the centre, not the scalp normal: a big
	-- mass over a concave scalp (the temples) cannot fold over itself
	local EX = opts.radial and table.create(nG, 0) or nil
	-- warm starts: each column's ray length from the row above (rays converge in two or three steps)
	local tcol = table.create(cols + 1, 0.5)
	for r = 0, rows do
		local f = r / rows
		for c = 0, cols do
			local i = r * stride + c + 1
			local az = c / cols * TAU
			-- denser rows toward the edge, where the fade and hairline detail is
			local th = lerp(TH0, thMax[c + 1], 1 - (1 - f) ^ 1.25)
			local dx, dy, dz = dirOf(az, th)
			local x, y, z, tr = S.ray(dx, dy, dz, 0, tcol[c + 1])
			tcol[c + 1] = tr
			DX[i], DY[i], DZ[i], R0[i], R[i] = dx, dy, dz, tr, tr
			NX[i], NY[i], NZ[i] = S.normal(x, y, z)
			local t, cv = cut.thick(x, y, z)
			if extra then
				local e = extra(x, y, z, cv)
				if EX then
					EX[i] = e
				else
					t += e
				end
			end
			OFF[i], CV[i] = t, cv
			-- a ray, the cut, a normal and the callbacks per vertex
			step(12)
		end
	end
	-- smoothing: radius (dips filled only) and normals, a few Jacobi passes over the grid (columns wrap)
	local passes = opts.smooth or 6
	if passes > 0 then
		local TR, TX, TY, TZ = table.create(nG), table.create(nG), table.create(nG), table.create(nG)
		for _ = 1, passes do
			for r = 0, rows do
				local rp, rn = max(0, r - 1), min(rows, r + 1)
				for c = 0, cols do
					local cp, cn = c - 1, c + 1
					if cp < 0 then
						cp = cols - 1
					end
					if cn > cols then
						cn = 1
					end
					local i = r * stride + c + 1
					local a, b = r * stride + cp + 1, r * stride + cn + 1
					local u, d = rp * stride + c + 1, rn * stride + c + 1
					TR[i] = max(R0[i], 0.5 * R[i] + 0.125 * (R[a] + R[b] + R[u] + R[d]))
					TX[i] = 2 * NX[i] + NX[a] + NX[b] + NX[u] + NX[d]
					TY[i] = 2 * NY[i] + NY[a] + NY[b] + NY[u] + NY[d]
					TZ[i] = 2 * NZ[i] + NZ[a] + NZ[b] + NZ[u] + NZ[d]
				end
				step(cols)
			end
			for i = 1, nG do
				R[i] = TR[i]
				NX[i], NY[i], NZ[i] = norm3(TX[i], TY[i], TZ[i])
				if i % 64 == 0 then
					step(64)
				end
			end
			-- the seam column (c = cols) repeats c = 0
			for r = 0, rows do
				local i0, i1 = r * stride + 1, r * stride + cols + 1
				R[i1], NX[i1], NY[i1], NZ[i1] = R[i0], NX[i0], NY[i0], NZ[i0]
			end
			step(nG)
		end
	end
	for i = 1, nG do
		local c = (i - 1) % stride
		local r = (i - 1 - c) // stride
		local rr, t = R[i], OFF[i]
		if EX then
			rr += EX[i]
		end
		local nx, ny, nz = NX[i], NY[i], NZ[i]
		local x, y, z = cx + DX[i] * rr + nx * t, cy + DY[i] * rr + ny * t, cz + DZ[i] * rr + nz * t
		local cr, cg, cb = 1, 1, 1
		if color then
			cr, cg, cb = color(x, y, z, CV[i])
		end
		-- the polar angle back from the ray (UVs follow the scalp grid)
		local th = acosClamp(DY[i])
		local v = vertex(m, x, y, z, c / cols, th / 2.75, cr, cg, cb)
		N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = nx, ny, nz
		-- (a colour callback and a vertex each)
		step(3)
	end
	if opts.gridNormals then
		-- normals of the displaced surface itself (volumes): differences across the grid, kept outward
		local P = m.P
		local function pos(r, c)
			local i = first + r * stride + c
			return P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		end
		for r = 0, rows do
			for c = 0, cols do
				local cp, cn = c - 1, c + 1
				if cp < 0 then
					cp = cols - 1
				end
				if cn > cols then
					cn = 1
				end
				local rp, rn = max(0, r - 1), min(rows, r + 1)
				local ax, ay, az = pos(r, cn)
				local bx, by, bz = pos(r, cp)
				local ux, uy, uz = ax - bx, ay - by, az - bz
				ax, ay, az = pos(rn, c)
				bx, by, bz = pos(rp, c)
				local vx, vy, vz = ax - bx, ay - by, az - bz
				local nx, ny, nz = norm3(cross(vx, vy, vz, ux, uy, uz))
				local i = first + r * stride + c
				local ox, oy, oz = N[i * 3 - 2], N[i * 3 - 1], N[i * 3]
				if nx * ox + ny * oy + nz * oz < 0 then
					nx, ny, nz = -nx, -ny, -nz
				end
				if nx ~= 0 or ny ~= 0 or nz ~= 0 then
					N[i * 3 - 2], N[i * 3 - 1], N[i * 3] = nx, ny, nz
				end
			end
			step(cols * 2)
		end
	end
	-- a quad whose four corners lie under the skin is never seen: left out
	local under = opts.under or -0.0025
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local a = first + r * stride + c
			local b = a + 1
			local d = a + stride
			local e = d + 1
			local ia = r * stride + c + 1
			local o1, o2, o3, o4 = OFF[ia], OFF[ia + 1], OFF[ia + stride], OFF[ia + stride + 1]
			if EX then
				o1, o2, o3, o4 = o1 + EX[ia], o2 + EX[ia + 1], o3 + EX[ia + stride], o4 + EX[ia + stride + 1]
			end
			if not (o1 < under and o2 < under and o3 < under and o4 < under) then
				-- seen from outside: azimuth grows toward +X from the back (clockwise from above), polar angle downward
				tri(m, a, d, b)
				tri(m, b, d, e)
			end
		end
	end
	-- close the crown: one vertex on the pole
	local px, py, pz, pr = S.ray(0, 1, 0, 0)
	local t0, c0 = cut.thick(px, py, pz)
	if extra then
		t0 += extra(px, py, pz, c0)
	end
	-- the pole sits on the smoothed first ring's mean radius
	local rs, nn = 0, 0
	for c = 0, cols - 1 do
		rs += R[c + 1]
		nn += 1
	end
	pr = max(pr, rs / max(nn, 1))
	local nx, ny, nz = 0, 0, 0
	for c = 0, cols - 1 do
		nx += NX[c + 1]
		ny += NY[c + 1]
		nz += NZ[c + 1]
	end
	nx, ny, nz = norm3(nx, ny, nz)
	if ny <= 0 then
		nx, ny, nz = 0, 1, 0
	end
	px, py, pz = cx, cy + pr + t0, cz
	local cr, cg, cb = 1, 1, 1
	if color then
		cr, cg, cb = color(px, py, pz, c0)
	end
	local pole = vertex(m, px, py, pz, 0.5, 0, cr, cg, cb)
	N[pole * 3 - 2], N[pole * 3 - 1], N[pole * 3] = nx, ny, nz
	for c = 0, cols - 1 do
		tri(m, first + c, first + c + 1, pole)
	end
	step(cols * rows * 2)
	return first, m.nv, thMax
end

-- the polar angle (Kit.Cap's parametrisation) where the scalp at azimuth az is `inset` studs inside the cut's
-- hairline (bisection on the hairline distance; the roots of a sheet that starts at the hairline)
function Kit.HairlinePolar(S, cut, az, inset)
	local lo, hi = 0.05, 2.75
	local t0 = 0.5
	for _ = 1, 14 do
		local mid = (lo + hi) * 0.5
		local st = sin(mid)
		local x, y, z, t = S.ray(st * sin(az), cos(mid), st * cos(az), 0, t0)
		t0 = t
		if cut.dist(x, y, z) > (inset or 0.02) then
			lo = mid
		else
			hi = mid
		end
	end
	step(28)
	return lo
end

-- a scalp point from (azimuth, polar) as Kit.Cap parametrises it, at offset off: x, y, z, nx, ny, nz
function Kit.ScalpAt(S, az, th, off)
	local st = sin(th)
	local x, y, z = S.ray(st * sin(az), cos(th), st * cos(az), 0)
	local nx, ny, nz = S.normal(x, y, z)
	return x + nx * off, y + ny * off, z + nz * off, nx, ny, nz
end

-- normalised mesh counts (for budgets)
function Kit.Tris(m)
	return m.nt
end

return Kit
