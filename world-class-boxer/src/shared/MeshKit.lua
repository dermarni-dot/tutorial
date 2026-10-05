-- MeshKit: pure-Luau mesh data and procedural modelling for the anatomy meshes (shared, deterministic).
-- Runs anywhere Luau runs (server, client, the luaurun tests, the offline renderer): only the writers at
-- the bottom (ToEditableMesh / ToEditableImage) touch the Roblox API, and only when called.
--
-- Mesh data (plain tables, flat number arrays, so a mesh costs ~11 numbers per vertex and serialises
-- as is). Vertex indices are 1-based; triangles are counter-clockwise seen from outside (right-hand
-- rule normal points out), the convention EditableMesh and the renderer share.
--   m.P  positions x,y,z...        m.N  normals (unit; ComputeNormals fills them)
--   m.U  uv u,v...  (0,0 = top-left texel, v grows down like EditableImage rows)
--   m.C  colours r,g,b... 0..1      m.A  alpha per vertex (nil until SetAlpha / Paint writes one)
--   m.T  triangles a,b,c...         m.nv, m.nt  counts
--   m.groups[name] = { vertex ids } (deformation regions FaceFX / BodyFX drive, paint masks)
--   m.W[name] = { per-vertex weight } (optional scalar channels, e.g. flex weights)
--   m.landmarks[name] = { x, y, z } (points other systems align to, in the same space as P)
-- Space: whatever the caller builds in; the anatomy generators build each piece in the local space of
-- the R15 part it is welded to (studs, +X = the character's right, +Y up, -Z forward).
--
-- Toolkit
-- * building: New, Vertex, Tri, Quad, Append / Merge, Transform (+ matrix helpers), Mirror, Flip, Clone
-- * shapes: Loft (spine + per-ring radial / cartesian section, parallel-transport frames, flat / point /
--   dome caps), Revolve, Surface (parametric grid with wrap and poles), Ellipsoid (patches, radial
--   sculpt), Tube (tapered, twisted, helical sweeps along Catmull-Rom points: hair strands, clumps,
--   locs, braids), Ribbon (hair cards), Polygonize (surface nets over a signed distance field: organic
--   smooth unions of muscles / skull features) with SDF primitives and smooth min / max
-- * curves: CatmullRom, Bezier3, SampleCurve, Helix; sections: SuperEllipse, Bump / Belly / Bulge
-- * smoothing: ComputeNormals (area weighted, welded across UV seams), Subdivide (Loop, on the welded
--   topology), Relax (Taubin), Weld
-- * colour: Fill, Paint, Gradient, Tint, masks, Noise / FBM (value noise), Cavity, BakeAO (curvature +
--   down-facing + sphere occluders), RasterizeUV (vertex colours -> RGBA8 texture buffer with padding)
-- * checks: Bounds, Counts, Validate, EdgeStats (watertight / manifold), SignedVolume
-- * output: ToEditableMesh (pcall-safe, chunked), UpdatePositions, ToEditableImage, Export (renderer)
-- * chunking: SetTick(fn) installs a yield callback; every heavy loop calls MeshKit.Step(n), which runs it
--   about every TICK_EVERY units of work (AnatomyClient yields there when its frame budget is spent)
local MeshKit = {}

local sqrt, abs, floor, min, max = math.sqrt, math.abs, math.floor, math.min, math.max
local sin, cos, atan2, pi = math.sin, math.cos, math.atan2, math.pi
local TAU = pi * 2

MeshKit.VERSION = 1
-- EditableMesh limits (Roblox: about 60k vertices / 20k triangles per mesh)
MeshKit.LIMITS = { verts = 60000, tris = 20000 }
-- ring angles used by Loft / Revolve / Tube sections: 0 = +X (right), pi/2 = -Z (front), pi = -X (left),
-- 3pi/2 = +Z (back). Seen from above (+Y) the angle runs counter-clockwise.
MeshKit.RIGHT, MeshKit.FRONT, MeshKit.LEFT, MeshKit.BACK = 0, pi / 2, pi, pi * 1.5

------------------------------------------------------------------------
-- Chunking
------------------------------------------------------------------------
local tickFn, tickCount = nil, 0
MeshKit.TICK_EVERY = 600

-- fn() is called from inside heavy loops; it may yield (task.wait / coroutine.yield). nil = never.
function MeshKit.SetTick(fn)
	tickFn = fn
	tickCount = 0
end

function MeshKit.GetTick()
	return tickFn
end

-- n units of work were done (a vertex ~ 1, a triangle ~ 1, an SDF sample ~ 0.3)
local function step(n)
	if tickFn then
		tickCount += n or 1
		if tickCount >= MeshKit.TICK_EVERY then
			tickCount = 0
			tickFn()
		end
	end
end
MeshKit.Step = step

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
MeshKit.Clamp = clamp

local function lerp(a, b, t)
	return a + (b - a) * t
end
MeshKit.Lerp = lerp

local function smoothstep(e0, e1, x)
	if e0 == e1 then
		return x < e0 and 0 or 1
	end
	local t = clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end
MeshKit.Smoothstep = smoothstep

-- x in [a, b] -> [c, d] (clamped)
function MeshKit.Remap(x, a, b, c, d)
	if a == b then
		return c
	end
	return c + (d - c) * clamp((x - a) / (b - a), 0, 1)
end

local function norm3(x, y, z)
	local l = sqrt(x * x + y * y + z * z)
	if l < 1e-12 then
		return 0, 0, 0, 0
	end
	return x / l, y / l, z / l, l
end
MeshKit.Normalize = norm3

local function cross(ax, ay, az, bx, by, bz)
	return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end
MeshKit.Cross = cross

local function dot(ax, ay, az, bx, by, bz)
	return ax * bx + ay * by + az * bz
end
MeshKit.Dot = dot

-- wrap an angle difference to [-pi, pi]
local function wrapAngle(d)
	d = (d + pi) % TAU
	if d < 0 then
		d += TAU
	end
	return d - pi
end
MeshKit.WrapAngle = wrapAngle

------------------------------------------------------------------------
-- Deterministic randomness and noise (no Random / math.random: same numbers on every machine)
------------------------------------------------------------------------
local M31 = 2147483647
local RngMT = {}
RngMT.__index = RngMT
-- Park-Miller minimal standard generator: exact in doubles (16807 * 2^31 < 2^53)
function MeshKit.Rng(seed)
	local s = floor(abs(tonumber(seed) or 1)) % (M31 - 1) + 1
	return setmetatable({ s = s }, RngMT)
end
function RngMT:Next()
	self.s = (self.s * 16807) % M31
	return (self.s - 1) / (M31 - 1)
end
function RngMT:Range(a, b)
	return a + (b - a) * self:Next()
end
function RngMT:Int(a, b)
	return min(b, a + floor(self:Next() * (b - a + 1)))
end
-- roughly normal (sum of three uniforms), mean 0, sd ~1
function RngMT:Gauss()
	return (self:Next() + self:Next() + self:Next() - 1.5) * 2
end

-- integer lattice hash -> [0, 1). Products stay below 2^53 for |coords| < 1e6 and seeds < 1e6.
local function hash3(ix, iy, iz, seed)
	local h = (ix * 73856093 + iy * 19349663 + iz * 83492791 + (seed or 0) * 2654435) % M31
	h = (h * 16807) % M31
	h = (h * 16807 + 12345) % M31
	h = (h * 48271) % M31
	return h / M31
end
MeshKit.Hash3 = hash3

local function fade(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- smooth 3D value noise in [-1, 1]
local function noise3(x, y, z, seed)
	local ix, iy, iz = floor(x), floor(y), floor(z)
	local fx, fy, fz = fade(x - ix), fade(y - iy), fade(z - iz)
	local s = seed or 0
	local c000, c100 = hash3(ix, iy, iz, s), hash3(ix + 1, iy, iz, s)
	local c010, c110 = hash3(ix, iy + 1, iz, s), hash3(ix + 1, iy + 1, iz, s)
	local c001, c101 = hash3(ix, iy, iz + 1, s), hash3(ix + 1, iy, iz + 1, s)
	local c011, c111 = hash3(ix, iy + 1, iz + 1, s), hash3(ix + 1, iy + 1, iz + 1, s)
	local x00, x10 = c000 + (c100 - c000) * fx, c010 + (c110 - c010) * fx
	local x01, x11 = c001 + (c101 - c001) * fx, c011 + (c111 - c011) * fx
	local y0, y1 = x00 + (x10 - x00) * fy, x01 + (x11 - x01) * fy
	return (y0 + (y1 - y0) * fz) * 2 - 1
end
MeshKit.Noise = noise3

-- fractal sum of value noise, about [-1, 1]
function MeshKit.FBM(x, y, z, seed, octaves, lacunarity, gain)
	octaves = octaves or 3
	lacunarity = lacunarity or 2
	gain = gain or 0.5
	local sum, amp, freq, norm = 0, 1, 1, 0
	for o = 1, octaves do
		sum += noise3(x * freq, y * freq, z * freq, (seed or 0) + o * 131) * amp
		norm += amp
		amp *= gain
		freq *= lacunarity
	end
	return sum / norm
end

------------------------------------------------------------------------
-- Mesh construction
------------------------------------------------------------------------
function MeshKit.New(name)
	return {
		name = name or "Mesh", nv = 0, nt = 0,
		P = {}, N = {}, U = {}, C = {}, A = nil, T = {},
		groups = {}, landmarks = {}, W = nil,
	}
end

-- adds a vertex; uv and colour default to 0,0 and white, the normal to 0,0,0 (ComputeNormals fills it)
local function vertex(m, x, y, z, u, v, r, g, b)
	local n = m.nv + 1
	m.nv = n
	local i3 = n * 3
	local P, N, C = m.P, m.N, m.C
	P[i3 - 2], P[i3 - 1], P[i3] = x, y, z
	N[i3 - 2], N[i3 - 1], N[i3] = 0, 0, 0
	C[i3 - 2], C[i3 - 1], C[i3] = r or 1, g or 1, b or 1
	local U = m.U
	U[n * 2 - 1], U[n * 2] = u or 0, v or 0
	if m.A then
		m.A[n] = 1
	end
	return n
end
MeshKit.Vertex = vertex

local function tri(m, a, b, c)
	local n = m.nt + 1
	m.nt = n
	local T = m.T
	T[n * 3 - 2], T[n * 3 - 1], T[n * 3] = a, b, c
	return n
end
MeshKit.Tri = tri

local function dist2(m, a, b)
	local P = m.P
	local dx, dy, dz = P[a * 3 - 2] - P[b * 3 - 2], P[a * 3 - 1] - P[b * 3 - 1], P[a * 3] - P[b * 3]
	return dx * dx + dy * dy + dz * dz
end

-- quad a,b,c,d (counter-clockwise from outside), split along its shorter diagonal
local function quad(m, a, b, c, d)
	if dist2(m, a, c) <= dist2(m, b, d) then
		tri(m, a, b, c)
		tri(m, a, c, d)
	else
		tri(m, a, b, d)
		tri(m, b, c, d)
	end
end
MeshKit.Quad = quad

function MeshKit.GetPosition(m, i)
	local i3 = i * 3
	return m.P[i3 - 2], m.P[i3 - 1], m.P[i3]
end

function MeshKit.SetPosition(m, i, x, y, z)
	local i3 = i * 3
	m.P[i3 - 2], m.P[i3 - 1], m.P[i3] = x, y, z
end

function MeshKit.GetNormal(m, i)
	local i3 = i * 3
	return m.N[i3 - 2], m.N[i3 - 1], m.N[i3]
end

function MeshKit.SetNormal(m, i, x, y, z)
	local i3 = i * 3
	m.N[i3 - 2], m.N[i3 - 1], m.N[i3] = x, y, z
end

function MeshKit.SetUV(m, i, u, v)
	m.U[i * 2 - 1], m.U[i * 2] = u, v
end

function MeshKit.GetColor(m, i)
	local i3 = i * 3
	return m.C[i3 - 2], m.C[i3 - 1], m.C[i3], m.A and m.A[i] or 1
end

local function ensureAlpha(m)
	local A = m.A
	if not A then
		A = table.create(m.nv, 1)
		m.A = A
	end
	return A
end

function MeshKit.SetColor(m, i, r, g, b, a)
	local i3 = i * 3
	m.C[i3 - 2], m.C[i3 - 1], m.C[i3] = r, g, b
	if a ~= nil and (a < 1 or m.A) then
		ensureAlpha(m)[i] = a
	end
end

function MeshKit.SetAlpha(m, i, a)
	ensureAlpha(m)[i] = a
end

-- per-vertex scalar channel
function MeshKit.SetWeight(m, name, i, w)
	m.W = m.W or {}
	local ch = m.W[name]
	if not ch then
		ch = table.create(m.nv, 0)
		m.W[name] = ch
	end
	ch[i] = w
end

function MeshKit.GetWeight(m, name, i)
	local ch = m.W and m.W[name]
	return ch and ch[i] or 0
end

function MeshKit.AddToGroup(m, name, i)
	local g = m.groups[name]
	if not g then
		g = {}
		m.groups[name] = g
	end
	g[#g + 1] = i
end

-- every vertex in [first, last] whose position passes fn(x, y, z, i) joins the group
function MeshKit.SelectGroup(m, name, fn, first, last)
	local P = m.P
	local g = m.groups[name] or {}
	m.groups[name] = g
	for i = first or 1, last or m.nv do
		if fn(P[i * 3 - 2], P[i * 3 - 1], P[i * 3], i) then
			g[#g + 1] = i
		end
	end
	return g
end

function MeshKit.SetLandmark(m, name, x, y, z)
	m.landmarks[name] = { x, y, z }
end

function MeshKit.Counts(m)
	return m.nv, m.nt
end

function MeshKit.Bounds(m, first, last)
	local P = m.P
	local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for i = first or 1, last or m.nv do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		if x < x0 then
			x0 = x
		end
		if x > x1 then
			x1 = x
		end
		if y < y0 then
			y0 = y
		end
		if y > y1 then
			y1 = y
		end
		if z < z0 then
			z0 = z
		end
		if z > z1 then
			z1 = z
		end
	end
	return x0, y0, z0, x1, y1, z1
end

-- centre and size of the bounding box (what a MeshPart made from this mesh is sized / centred to)
function MeshKit.BoxCenter(m)
	local x0, y0, z0, x1, y1, z1 = MeshKit.Bounds(m)
	return (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0
end

local function copyList(t)
	local out = table.create(#t)
	for i = 1, #t do
		out[i] = t[i]
	end
	return out
end

function MeshKit.Clone(m)
	local c = MeshKit.New(m.name)
	c.nv, c.nt = m.nv, m.nt
	c.P, c.N, c.U, c.C, c.T = copyList(m.P), copyList(m.N), copyList(m.U), copyList(m.C), copyList(m.T)
	c.A = m.A and copyList(m.A) or nil
	for k, g in pairs(m.groups) do
		c.groups[k] = copyList(g)
	end
	for k, p in pairs(m.landmarks) do
		c.landmarks[k] = { p[1], p[2], p[3] }
	end
	if m.W then
		c.W = {}
		for k, w in pairs(m.W) do
			c.W[k] = copyList(w)
		end
	end
	c.meta = m.meta
	return c
end

-- reverse the winding (and the normals) of the triangles [firstTri, lastTri]
function MeshKit.Flip(m, firstTri, lastTri, keepNormals)
	local T = m.T
	for t = firstTri or 1, lastTri or m.nt do
		T[t * 3 - 1], T[t * 3] = T[t * 3], T[t * 3 - 1]
	end
	if not keepNormals and not firstTri then
		local N = m.N
		for i = 1, m.nv * 3 do
			N[i] = -N[i]
		end
	end
end

------------------------------------------------------------------------
-- Affine matrices: { r11, r12, r13, r21, r22, r23, r31, r32, r33, tx, ty, tz } (x' = R x + t)
------------------------------------------------------------------------
function MeshKit.MatIdentity()
	return { 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0 }
end

function MeshKit.MatTranslate(x, y, z)
	return { 1, 0, 0, 0, 1, 0, 0, 0, 1, x, y, z }
end

function MeshKit.MatScale(sx, sy, sz)
	return { sx, 0, 0, 0, sy or sx, 0, 0, 0, sz or sx, 0, 0, 0 }
end

function MeshKit.MatRotX(a)
	local c, s = cos(a), sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c, 0, 0, 0 }
end

function MeshKit.MatRotY(a)
	local c, s = cos(a), sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c, 0, 0, 0 }
end

function MeshKit.MatRotZ(a)
	local c, s = cos(a), sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1, 0, 0, 0 }
end

-- a * b (apply b first)
function MeshKit.MatMul(a, b)
	local o = {}
	for r = 0, 2 do
		for c = 1, 3 do
			o[r * 3 + c] = a[r * 3 + 1] * b[c] + a[r * 3 + 2] * b[3 + c] + a[r * 3 + 3] * b[6 + c]
		end
	end
	for r = 0, 2 do
		o[10 + r] = a[r * 3 + 1] * b[10] + a[r * 3 + 2] * b[11] + a[r * 3 + 3] * b[12] + a[10 + r]
	end
	return o
end

-- product of several matrices, applied right to left: MatChain(A, B, C) = A * B * C
function MeshKit.MatChain(...)
	local n = select("#", ...)
	local out = select(n, ...)
	for i = n - 1, 1, -1 do
		out = MeshKit.MatMul(select(i, ...), out)
	end
	return out
end

-- from a Roblox CFrame (client / server only)
function MeshKit.MatFromCFrame(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { r00, r01, r02, r10, r11, r12, r20, r21, r22, x, y, z }
end

-- columns = the frame's X / Y / Z axes, then the origin
function MeshKit.MatFromBasis(xx, xy, xz, yx, yy, yz, zx, zy, zz, tx, ty, tz)
	return { xx, yx, zx, xy, yy, zy, xz, yz, zz, tx or 0, ty or 0, tz or 0 }
end

function MeshKit.MatApply(mt, x, y, z)
	return mt[1] * x + mt[2] * y + mt[3] * z + mt[10], mt[4] * x + mt[5] * y + mt[6] * z + mt[11], mt[7] * x + mt[8] * y + mt[9] * z + mt[12]
end

-- inverse transpose of the 3x3 part (normals under non-uniform scale)
local function normalMatrix(mt)
	local a, b, c, d, e, f, g, h, k = mt[1], mt[2], mt[3], mt[4], mt[5], mt[6], mt[7], mt[8], mt[9]
	local A, B, C = e * k - f * h, -(d * k - f * g), d * h - e * g
	local det = a * A + b * B + c * C
	if abs(det) < 1e-12 then
		return { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 1
	end
	local D, E, F = -(b * k - c * h), a * k - c * g, -(a * h - b * g)
	local G, H, K = b * f - c * e, -(a * f - c * d), a * e - b * d
	-- inverse = adj^T / det; inverse transpose = adj / det (cofactor matrix / det)
	return { A / det, B / det, C / det, D / det, E / det, F / det, G / det, H / det, K / det }, det
end

-- transform vertices [first, last] (default all) and the landmarks (when transforming everything)
function MeshKit.Transform(m, mt, first, last)
	local P, N = m.P, m.N
	local nm, det = normalMatrix(mt)
	for i = first or 1, last or m.nv do
		local i3 = i * 3
		local x, y, z = P[i3 - 2], P[i3 - 1], P[i3]
		P[i3 - 2] = mt[1] * x + mt[2] * y + mt[3] * z + mt[10]
		P[i3 - 1] = mt[4] * x + mt[5] * y + mt[6] * z + mt[11]
		P[i3] = mt[7] * x + mt[8] * y + mt[9] * z + mt[12]
		local nx, ny, nz = N[i3 - 2], N[i3 - 1], N[i3]
		local tx = nm[1] * nx + nm[2] * ny + nm[3] * nz
		local ty = nm[4] * nx + nm[5] * ny + nm[6] * nz
		local tz = nm[7] * nx + nm[8] * ny + nm[9] * nz
		local ux, uy, uz = norm3(tx, ty, tz)
		N[i3 - 2], N[i3 - 1], N[i3] = ux, uy, uz
		step(0.3)
	end
	if not first and not last then
		for _, p in pairs(m.landmarks) do
			p[1], p[2], p[3] = MeshKit.MatApply(mt, p[1], p[2], p[3])
		end
		-- a mirroring transform turns the triangles inside out: flip them back
		if det < 0 then
			MeshKit.Flip(m, 1, m.nt, true)
		end
	end
	return m
end

-- copy src into dst (optionally transformed); groups / weights merge by name, landmarks get a prefix
function MeshKit.Append(dst, src, mt, landmarkPrefix)
	local base = dst.nv
	local P, N, U, C, T = dst.P, dst.N, dst.U, dst.C, dst.T
	local sP, sN, sU, sC, sT = src.P, src.N, src.U, src.C, src.T
	local nm, det
	if mt then
		nm, det = normalMatrix(mt)
	end
	for i = 1, src.nv do
		local i3, o3 = i * 3, (base + i) * 3
		local x, y, z = sP[i3 - 2], sP[i3 - 1], sP[i3]
		local nx, ny, nz = sN[i3 - 2], sN[i3 - 1], sN[i3]
		if mt then
			x, y, z = MeshKit.MatApply(mt, x, y, z)
			nx, ny, nz = norm3(nm[1] * nx + nm[2] * ny + nm[3] * nz, nm[4] * nx + nm[5] * ny + nm[6] * nz, nm[7] * nx + nm[8] * ny + nm[9] * nz)
		end
		P[o3 - 2], P[o3 - 1], P[o3] = x, y, z
		N[o3 - 2], N[o3 - 1], N[o3] = nx, ny, nz
		C[o3 - 2], C[o3 - 1], C[o3] = sC[i3 - 2], sC[i3 - 1], sC[i3]
		U[(base + i) * 2 - 1], U[(base + i) * 2] = sU[i * 2 - 1], sU[i * 2]
		step(0.5)
	end
	if src.A or dst.A then
		local A = ensureAlpha(dst)
		for i = 1, src.nv do
			A[base + i] = src.A and src.A[i] or 1
		end
	end
	dst.nv = base + src.nv
	local tb = dst.nt
	local flip = det ~= nil and det < 0
	for t = 1, src.nt do
		local a, b, c = sT[t * 3 - 2] + base, sT[t * 3 - 1] + base, sT[t * 3] + base
		if flip then
			b, c = c, b
		end
		T[(tb + t) * 3 - 2], T[(tb + t) * 3 - 1], T[(tb + t) * 3] = a, b, c
	end
	dst.nt = tb + src.nt
	for k, g in pairs(src.groups) do
		local dg = dst.groups[k] or {}
		dst.groups[k] = dg
		for _, i in ipairs(g) do
			dg[#dg + 1] = i + base
		end
	end
	if src.W then
		dst.W = dst.W or {}
		for k, w in pairs(src.W) do
			local dw = dst.W[k]
			if not dw then
				dw = table.create(base, 0)
				dst.W[k] = dw
			end
			for i = 1, src.nv do
				dw[base + i] = w[i] or 0
			end
		end
	end
	if dst.W then
		for _, dw in pairs(dst.W) do
			for i = #dw + 1, dst.nv do
				dw[i] = 0
			end
		end
	end
	for k, p in pairs(src.landmarks) do
		local x, y, z = p[1], p[2], p[3]
		if mt then
			x, y, z = MeshKit.MatApply(mt, x, y, z)
		end
		dst.landmarks[(landmarkPrefix or "") .. k] = { x, y, z }
	end
	return base
end

function MeshKit.Merge(list, name)
	local out = MeshKit.New(name)
	for _, m in ipairs(list) do
		MeshKit.Append(out, m)
	end
	return out
end

-- mirrored copy across a plane through the origin (axis "x" | "y" | "z"); the winding is fixed so
-- the copy still faces out. Groups / landmarks named with L <-> R swap when swapNames is true.
function MeshKit.Mirror(m, axis, swapNames)
	local c = MeshKit.Clone(m)
	local sx, sy, sz = 1, 1, 1
	if axis == "y" then
		sy = -1
	elseif axis == "z" then
		sz = -1
	else
		sx = -1
	end
	MeshKit.Transform(c, MeshKit.MatScale(sx, sy, sz))
	if swapNames then
		local function swap(k)
			local last = k:sub(-1)
			if last == "L" then
				return k:sub(1, -2) .. "R"
			elseif last == "R" then
				return k:sub(1, -2) .. "L"
			elseif k:sub(1, 4) == "Left" then
				return "Right" .. k:sub(5)
			elseif k:sub(1, 5) == "Right" then
				return "Left" .. k:sub(6)
			end
			return k
		end
		local g, l = {}, {}
		for k, v in pairs(c.groups) do
			g[swap(k)] = v
		end
		for k, v in pairs(c.landmarks) do
			l[swap(k)] = v
		end
		c.groups, c.landmarks = g, l
	end
	return c
end

------------------------------------------------------------------------
-- Curves and sections
------------------------------------------------------------------------
-- uniform Catmull-Rom through points { {x,y,z}, ... } at t in [0, 1]; returns x, y, z, dx, dy, dz
-- (ends are clamped, so the curve passes through the first and last point)
function MeshKit.CatmullRom(pts, t)
	local n = #pts
	if n == 1 then
		local p = pts[1]
		return p[1], p[2], p[3], 0, 0, 0
	end
	local f = clamp(t, 0, 1) * (n - 1)
	local s = min(floor(f), n - 2)
	local u = f - s
	local p0, p1, p2, p3 = pts[max(1, s)], pts[s + 1], pts[s + 2], pts[min(n, s + 3)]
	local u2, u3 = u * u, u * u * u
	local x, y, z, dx, dy, dz
	do
		local a, b, c, d = p0[1], p1[1], p2[1], p3[1]
		x = 0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u2 + (-a + 3 * b - 3 * c + d) * u3)
		dx = 0.5 * ((-a + c) + 2 * (2 * a - 5 * b + 4 * c - d) * u + 3 * (-a + 3 * b - 3 * c + d) * u2)
	end
	do
		local a, b, c, d = p0[2], p1[2], p2[2], p3[2]
		y = 0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u2 + (-a + 3 * b - 3 * c + d) * u3)
		dy = 0.5 * ((-a + c) + 2 * (2 * a - 5 * b + 4 * c - d) * u + 3 * (-a + 3 * b - 3 * c + d) * u2)
	end
	do
		local a, b, c, d = p0[3], p1[3], p2[3], p3[3]
		z = 0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u2 + (-a + 3 * b - 3 * c + d) * u3)
		dz = 0.5 * ((-a + c) + 2 * (2 * a - 5 * b + 4 * c - d) * u + 3 * (-a + 3 * b - 3 * c + d) * u2)
	end
	return x, y, z, dx, dy, dz
end

-- cubic Bezier p0..p3 (each {x,y,z}) at t; returns x, y, z, dx, dy, dz
function MeshKit.Bezier3(p0, p1, p2, p3, t)
	local u = 1 - t
	local b0, b1, b2, b3 = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
	local d0, d1, d2 = 3 * u * u, 6 * u * t, 3 * t * t
	local x = b0 * p0[1] + b1 * p1[1] + b2 * p2[1] + b3 * p3[1]
	local y = b0 * p0[2] + b1 * p1[2] + b2 * p2[2] + b3 * p3[2]
	local z = b0 * p0[3] + b1 * p1[3] + b2 * p2[3] + b3 * p3[3]
	local dx = d0 * (p1[1] - p0[1]) + d1 * (p2[1] - p1[1]) + d2 * (p3[1] - p2[1])
	local dy = d0 * (p1[2] - p0[2]) + d1 * (p2[2] - p1[2]) + d2 * (p3[2] - p2[2])
	local dz = d0 * (p1[3] - p0[3]) + d1 * (p2[3] - p1[3]) + d2 * (p3[3] - p2[3])
	return x, y, z, dx, dy, dz
end

-- n points along a curve: kind "catmull" (pts = control points) or "bezier" (pts = 4 points)
function MeshKit.SampleCurve(pts, n, kind)
	local out = table.create(n)
	for i = 1, n do
		local t = n == 1 and 0 or (i - 1) / (n - 1)
		local x, y, z
		if kind == "bezier" then
			x, y, z = MeshKit.Bezier3(pts[1], pts[2], pts[3], pts[4], t)
		else
			x, y, z = MeshKit.CatmullRom(pts, t)
		end
		out[i] = { x, y, z }
	end
	return out
end

-- superellipse point at angle a: n = 2 ellipse, n > 2 squarer (4 = rounded rectangle), n < 2 diamond-ish
function MeshKit.SuperEllipse(a, rx, ry, n)
	local c, s = cos(a), sin(a)
	local e = 2 / (n or 2)
	local x = rx * (c < 0 and -1 or 1) * abs(c) ^ e
	local y = ry * (s < 0 and -1 or 1) * abs(s) ^ e
	return x, y
end

-- angular window: 1 at centre, 0 beyond halfWidth (radians), smooth (raised cosine)
local function bump(a, centre, halfWidth)
	local d = abs(wrapAngle(a - centre))
	if d >= halfWidth then
		return 0
	end
	return 0.5 * (1 + cos(pi * d / halfWidth))
end
MeshKit.Bump = bump

-- window along t: 0 outside [t0, t1], rises smoothly to 1 at tPeak, falls back (asymmetric bellies)
local function belly(t, t0, tPeak, t1)
	if t <= t0 or t >= t1 then
		return 0
	end
	if t <= tPeak then
		local k = (t - t0) / max(1e-6, tPeak - t0)
		return k * k * (3 - 2 * k)
	end
	local k = (t1 - t) / max(1e-6, t1 - tPeak)
	return k * k * (3 - 2 * k)
end
MeshKit.Belly = belly

-- a muscle belly on a loft section: spec = { a = centre angle, w = angular half width, t0, tp (peak), t1,
-- h = height (studs), sharp = exponent (>1 = a crisper peak) }; returns the radial add at (t, a)
function MeshKit.Bulge(t, a, spec)
	local k = belly(t, spec.t0 or 0, spec.tp or 0.5, spec.t1 or 1) * bump(a, spec.a or 0, spec.w or 1)
	if spec.sharp and spec.sharp ~= 1 then
		k = k ^ spec.sharp
	end
	return (spec.h or 0) * k
end

-- sum of several Bulge specs
function MeshKit.Bulges(t, a, list)
	local s = 0
	for _, spec in ipairs(list) do
		s += MeshKit.Bulge(t, a, spec)
	end
	return s
end

-- dense point list spiralling around a base curve (curls, coils, twists, braid strands). base = control
-- points; samples = points out; radius (number or fn(t)); turns; phase (radians); normalHint {x,y,z}
function MeshKit.Helix(base, samples, radius, turns, phase, normalHint)
	local frames = MeshKit.Frames(base, samples, normalHint)
	local out = table.create(samples)
	for i = 1, samples do
		local f = frames[i]
		local t = (i - 1) / max(1, samples - 1)
		local r = type(radius) == "function" and radius(t) or radius
		local a = phase + TAU * turns * t
		local ca, sa = cos(a) * r, sin(a) * r
		out[i] = { f[1] + f[7] * ca + f[10] * sa, f[2] + f[8] * ca + f[11] * sa, f[3] + f[9] * ca + f[12] * sa }
	end
	return out
end

------------------------------------------------------------------------
-- Frames along a spine (parallel transport, so tubes never twist on their own)
------------------------------------------------------------------------
-- spine: fn(t) -> x,y,z | { {x,y,z}, ... } control points (Catmull-Rom) | exact = true: use the points
-- as is. Returns frames[i] = { px,py,pz, tx,ty,tz, sx,sy,sz (side axis), fx,fy,fz (front axis) } and
-- the handedness sign h = sign((side x front) . tangent). sideHint / frontHint pick the first frame
-- (defaults +X / -Z), so for a spine running down -Y the angle 0 is +X and pi/2 is -Z (front).
local function spinePoint(spine, t, exact)
	if type(spine) == "function" then
		return spine(t)
	elseif exact then
		local n = #spine
		local f = clamp(t, 0, 1) * (n - 1)
		local s = min(floor(f), n - 2)
		local u = f - s
		local a, b = spine[s + 1], spine[s + 2]
		return a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u
	end
	local x, y, z = MeshKit.CatmullRom(spine, t)
	return x, y, z
end

function MeshKit.Frames(spine, count, sideHint, frontHint, t0, t1, exact)
	t0, t1 = t0 or 0, t1 or 1
	local pts = table.create(count)
	for i = 1, count do
		local t = count == 1 and t0 or t0 + (t1 - t0) * (i - 1) / (count - 1)
		local x, y, z
		if exact and type(spine) == "table" and #spine == count then
			local p = spine[i]
			x, y, z = p[1], p[2], p[3]
		else
			x, y, z = spinePoint(spine, t, exact)
		end
		pts[i] = { x, y, z, t }
	end
	-- tangents: central differences (one-sided at the ends)
	local frames = table.create(count)
	for i = 1, count do
		local a, b = pts[max(1, i - 1)], pts[min(count, i + 1)]
		local tx, ty, tz = norm3(b[1] - a[1], b[2] - a[2], b[3] - a[3])
		if tx == 0 and ty == 0 and tz == 0 then
			tx, ty, tz = 0, -1, 0
			if i > 1 then
				local p = frames[i - 1]
				tx, ty, tz = p[4], p[5], p[6]
			end
		end
		frames[i] = { pts[i][1], pts[i][2], pts[i][3], tx, ty, tz, 0, 0, 0, 0, 0, 0, pts[i][4] }
	end
	-- first frame from the hints
	local f = frames[1]
	local tx, ty, tz = f[4], f[5], f[6]
	local sh = sideHint or { 1, 0, 0 }
	local fh = frontHint or { 0, 0, -1 }
	local sx, sy, sz = sh[1], sh[2], sh[3]
	local d = dot(sx, sy, sz, tx, ty, tz)
	sx, sy, sz = norm3(sx - d * tx, sy - d * ty, sz - d * tz)
	if sx == 0 and sy == 0 and sz == 0 then
		-- side hint along the spine: the side axis is perpendicular to the front hint and the spine
		sx, sy, sz = norm3(cross(fh[1], fh[2], fh[3], tx, ty, tz))
		if sx == 0 and sy == 0 and sz == 0 then
			sx, sy, sz = norm3(cross(0, 1, 0, tx, ty, tz))
			if sx == 0 and sy == 0 and sz == 0 then
				sx, sy, sz = 1, 0, 0
			end
		end
	end
	-- front axis: perpendicular to tangent and side, on the front hint's side
	local fx, fy, fz = cross(tx, ty, tz, sx, sy, sz)
	if dot(fx, fy, fz, fh[1], fh[2], fh[3]) < 0 then
		fx, fy, fz = -fx, -fy, -fz
	end
	f[7], f[8], f[9], f[10], f[11], f[12] = sx, sy, sz, fx, fy, fz
	local cx, cy, cz = cross(sx, sy, sz, fx, fy, fz)
	local h = dot(cx, cy, cz, tx, ty, tz) >= 0 and 1 or -1
	-- double reflection (Wang et al. 2008): rotation minimising frames
	for i = 2, count do
		local p, c = frames[i - 1], frames[i]
		local v1x, v1y, v1z = c[1] - p[1], c[2] - p[2], c[3] - p[3]
		local c1 = dot(v1x, v1y, v1z, v1x, v1y, v1z)
		local rx, ry, rz = p[7], p[8], p[9]
		local ptx, pty, ptz = p[4], p[5], p[6]
		if c1 > 1e-14 then
			local k = 2 / c1 * dot(v1x, v1y, v1z, rx, ry, rz)
			rx, ry, rz = rx - k * v1x, ry - k * v1y, rz - k * v1z
			local kt = 2 / c1 * dot(v1x, v1y, v1z, ptx, pty, ptz)
			ptx, pty, ptz = ptx - kt * v1x, pty - kt * v1y, ptz - kt * v1z
		end
		local v2x, v2y, v2z = c[4] - ptx, c[5] - pty, c[6] - ptz
		local c2 = dot(v2x, v2y, v2z, v2x, v2y, v2z)
		if c2 > 1e-14 then
			local k = 2 / c2 * dot(v2x, v2y, v2z, rx, ry, rz)
			rx, ry, rz = rx - k * v2x, ry - k * v2y, rz - k * v2z
		end
		-- re-orthogonalise against the tangent (numerical drift) and rebuild the front axis
		local dd = dot(rx, ry, rz, c[4], c[5], c[6])
		rx, ry, rz = norm3(rx - dd * c[4], ry - dd * c[5], rz - dd * c[6])
		if rx == 0 and ry == 0 and rz == 0 then
			rx, ry, rz = p[7], p[8], p[9]
		end
		local qx, qy, qz
		if h > 0 then
			qx, qy, qz = cross(c[4], c[5], c[6], rx, ry, rz)
		else
			qx, qy, qz = cross(rx, ry, rz, c[4], c[5], c[6])
		end
		c[7], c[8], c[9], c[10], c[11], c[12] = rx, ry, rz, qx, qy, qz
	end
	return frames, h
end

------------------------------------------------------------------------
-- Loft: rings of a section swept along a spine (limbs, torso, neck, fingers, locs)
------------------------------------------------------------------------
-- spec:
--   rings, sides            ring count (>= 2) and vertices per ring (>= 3)
--   spine                   fn(t) -> x,y,z | control points { {x,y,z}, ... } (Catmull-Rom) ; exact = true
--                           uses the points as ring centres (rings = #spine)
--   radius(t, a) -> r       polar section (a: MeshKit.RIGHT/FRONT/LEFT/BACK convention)
--   section(t, a) -> s, f   cartesian section in the ring plane (side axis, front axis); wins over radius
--   sideHint, frontHint     first-frame axes (default {1,0,0} and {0,0,-1})
--   t0, t1                  parameter range (default 0 .. 1)
--   capStart, capEnd        nil (open) | "flat" | "point" | "dome"; capDepth (default: mean end radius),
--                           domeRings (default 3)
--   color(t, a, x, y, z) -> r, g, b [, alpha]   vertex colour (default white)
--   uvSeam                  duplicate the seam column so the texture u runs 0..1 without a smear
--                           (costs a seam in the welded topology; normals still weld across it)
--   group                   group name for every vertex it adds
-- returns { first, last, rings, sides, stride, firstTri, lastTri, h }
function MeshKit.Loft(m, spec)
	local rings = max(2, spec.rings or 8)
	local sides = max(3, spec.sides or 12)
	local seam = spec.uvSeam and true or false
	local stride = seam and sides + 1 or sides
	local frames, h = MeshKit.Frames(spec.spine, rings, spec.sideHint, spec.frontHint, spec.t0, spec.t1, spec.exact)
	local section, radius, color = spec.section, spec.radius, spec.color
	local first = m.nv + 1
	local firstTri = m.nt + 1
	local ringR = {} -- mean section radius per ring (cap depth default)
	local function ringPoint(f, t, a)
		local s, fr
		if section then
			s, fr = section(t, a)
		else
			local r = radius and radius(t, a) or 0.5
			s, fr = r * cos(a), r * sin(a)
		end
		return f[1] + f[7] * s + f[10] * fr, f[2] + f[8] * s + f[11] * fr, f[3] + f[9] * s + f[12] * fr, s, fr
	end
	local function addRing(f, t, v, scale, push)
		local sumR = 0
		for j = 0, stride - 1 do
			local a = TAU * j / sides
			local x, y, z, s, fr = ringPoint(f, t, a)
			if scale then
				-- dome rings: the end section shrunk toward the spine and pushed past the end
				local cx, cy, cz = f[1] + f[4] * push, f[2] + f[5] * push, f[3] + f[6] * push
				x = cx + (x - f[1]) * scale
				y = cy + (y - f[2]) * scale
				z = cz + (z - f[3]) * scale
				s, fr = s * scale, fr * scale
			end
			local i = vertex(m, x, y, z, j / sides, v)
			if color then
				local r, g, b, al = color(t, a, x, y, z)
				if r then
					MeshKit.SetColor(m, i, r, g, b, al)
				end
			end
			if spec.group then
				MeshKit.AddToGroup(m, spec.group, i)
			end
			sumR += sqrt(s * s + fr * fr)
		end
		step(stride)
		return sumR / stride
	end
	local ringStart = {}
	for i = 1, rings do
		local f = frames[i]
		ringStart[i] = m.nv + 1
		ringR[i] = addRing(f, f[13], (i - 1) / (rings - 1))
	end
	-- side walls
	local function band(r0, r1, flip)
		for j = 0, sides - 1 do
			local j1 = j + 1
			if not seam and j1 == sides then
				j1 = 0
			end
			local a, b = r0 + j, r0 + j1
			local c, d = r1 + j, r1 + j1
			if (h > 0) ~= (flip == true) then
				tri(m, a, b, c)
				tri(m, b, d, c)
			else
				tri(m, a, c, b)
				tri(m, b, c, d)
			end
		end
		step(sides)
	end
	for i = 1, rings - 1 do
		band(ringStart[i], ringStart[i + 1], false)
	end
	-- caps
	local function cap(which)
		local kind = which == "start" and spec.capStart or spec.capEnd
		if not kind then
			return
		end
		local f = which == "start" and frames[1] or frames[rings]
		local rs = which == "start" and ringStart[1] or ringStart[rings]
		local dir = which == "start" and -1 or 1 -- outward along the tangent
		local depth = spec.capDepth or (which == "start" and ringR[1] or ringR[rings]) or 0.5
		local t = f[13]
		local last = rs
		if kind == "dome" then
			local k = max(1, spec.domeRings or 3)
			for q = 1, k do
				local th = (pi / 2) * q / (k + 1)
				local ringAt = m.nv + 1
				addRing(f, t, which == "start" and -q * 0.05 or 1 + q * 0.05, cos(th), dir * sin(th) * depth)
				band(last, ringAt, dir < 0)
				last = ringAt
			end
		end
		local push = (kind == "point" or kind == "dome") and dir * depth or 0
		local cx, cy, cz = f[1] + f[4] * push, f[2] + f[5] * push, f[3] + f[6] * push
		local apex = vertex(m, cx, cy, cz, 0.5, which == "start" and -0.2 or 1.2)
		if color then
			local r, g, b, al = color(t, 0, cx, cy, cz)
			if r then
				MeshKit.SetColor(m, apex, r, g, b, al)
			end
		end
		if spec.group then
			MeshKit.AddToGroup(m, spec.group, apex)
		end
		-- fan: (apex, j, j+1) faces along +h * tangent
		local outward = (h > 0) == (dir > 0)
		for j = 0, sides - 1 do
			local j1 = j + 1
			if not seam and j1 == sides then
				j1 = 0
			end
			if outward then
				tri(m, apex, last + j, last + j1)
			else
				tri(m, apex, last + j1, last + j)
			end
		end
	end
	cap("start")
	cap("end")
	return { first = first, last = m.nv, rings = rings, sides = sides, stride = stride, ringStart = ringStart,
		firstTri = firstTri, lastTri = m.nt, h = h, frames = frames }
end

------------------------------------------------------------------------
-- Revolve / Surface / Ellipsoid
------------------------------------------------------------------------
-- surface of revolution around the Y axis through (cx, cz). profile = { {r, y}, ... } in counter-
-- clockwise order in the (r, y) half plane (e.g. bottom pole -> side -> top pole) so faces point out.
-- r = 0 entries become single pole vertices. opts: sides, cx, cz, color(i, a, x, y, z), group, a0, a1
-- (partial sweep, radians; open edges), radialScale(a) -> k (non-round sections: k scales r per angle)
function MeshKit.Revolve(m, profile, opts)
	opts = opts or {}
	local sides = max(3, opts.sides or 16)
	local a0, a1 = opts.a0 or 0, opts.a1 or TAU
	local full = abs(a1 - a0 - TAU) < 1e-9
	local cols = full and sides or sides + 1
	local cx, cz = opts.cx or 0, opts.cz or 0
	local first, firstTri = m.nv + 1, m.nt + 1
	local rows = {}
	local n = #profile
	for i = 1, n do
		local r, y = profile[i][1], profile[i][2]
		local v = (i - 1) / max(1, n - 1)
		if r <= 1e-9 then
			local idx = vertex(m, cx, y, cz, 0.5, v)
			rows[i] = { pole = idx }
			if opts.color then
				local cr, cg, cb, ca = opts.color(i, 0, cx, y, cz)
				if cr then
					MeshKit.SetColor(m, idx, cr, cg, cb, ca)
				end
			end
			if opts.group then
				MeshKit.AddToGroup(m, opts.group, idx)
			end
		else
			local start = m.nv + 1
			for j = 0, cols - 1 do
				local a = a0 + (a1 - a0) * j / sides
				local k = opts.radialScale and opts.radialScale(a) or 1
				local x, z = cx + r * k * cos(a), cz - r * k * sin(a)
				local idx = vertex(m, x, y, z, j / sides, v)
				if opts.color then
					local cr, cg, cb, ca = opts.color(i, a, x, y, z)
					if cr then
						MeshKit.SetColor(m, idx, cr, cg, cb, ca)
					end
				end
				if opts.group then
					MeshKit.AddToGroup(m, opts.group, idx)
				end
			end
			rows[i] = { start = start }
		end
		step(cols)
	end
	local segs = sides
	for i = 1, n - 1 do
		local A, B = rows[i], rows[i + 1]
		for j = 0, segs - 1 do
			local j1 = j + 1
			if full and j1 == sides then
				j1 = 0
			end
			if A.pole and B.pole then
				break
			elseif A.pole then
				tri(m, A.pole, B.start + j1, B.start + j)
			elseif B.pole then
				tri(m, A.start + j, A.start + j1, B.pole)
			else
				-- (i, j) -> (i, j+1) runs with the angle, (i, j) -> (i+1, j) along the profile
				local a, b, c, d = A.start + j, A.start + j1, B.start + j, B.start + j1
				tri(m, a, b, c)
				tri(m, b, d, c)
			end
		end
		step(segs)
	end
	-- (i, j), (i, j+1), (i+1, j) has normal dP/da x dP/ds = r * (dy/ds, -dr/ds, 0) at a = 0: outward
	-- exactly when the profile runs counter-clockwise in the (r, y) half plane (opts.inward flips)
	if opts.inward then
		MeshKit.Flip(m, firstTri, m.nt, true)
	end
	return { first = first, last = m.nv, firstTri = firstTri, lastTri = m.nt }
end

-- parametric grid surface: fn(u, v) -> x, y, z [, r, g, b, alpha] for u, v in [0, 1].
-- opts: nu, nv (segments), wrapU (u = 1 joins u = 0), poleV0 / poleV1 (the v = 0 / 1 row collapses to
-- one vertex), uvSeam, group, outwardFrom = {x,y,z} (flip the patch if most faces point toward it)
function MeshKit.Surface(m, fn, opts)
	opts = opts or {}
	local nu, nvv = max(1, opts.nu or 12), max(1, opts.nv or 8)
	local wrap = opts.wrapU and not opts.uvSeam
	local cols = wrap and nu or nu + 1
	local first, firstTri = m.nv + 1, m.nt + 1
	local rows = {}
	for r = 0, nvv do
		local v = r / nvv
		if (r == 0 and opts.poleV0) or (r == nvv and opts.poleV1) then
			local x, y, z, cr, cg, cb, ca = fn(0.5, v)
			local idx = vertex(m, x, y, z, 0.5, v)
			if cr then
				MeshKit.SetColor(m, idx, cr, cg, cb, ca)
			end
			if opts.group then
				MeshKit.AddToGroup(m, opts.group, idx)
			end
			rows[r] = { pole = idx }
		else
			local start = m.nv + 1
			for c = 0, cols - 1 do
				local u = c / nu
				local x, y, z, cr, cg, cb, ca = fn(u, v)
				local idx = vertex(m, x, y, z, u, v)
				if cr then
					MeshKit.SetColor(m, idx, cr, cg, cb, ca)
				end
				if opts.group then
					MeshKit.AddToGroup(m, opts.group, idx)
				end
			end
			rows[r] = { start = start }
		end
		step(cols)
	end
	for r = 0, nvv - 1 do
		local A, B = rows[r], rows[r + 1]
		for c = 0, nu - 1 do
			local c1 = c + 1
			if wrap and c1 == nu then
				c1 = 0
			end
			if A.pole and B.pole then
				break
			elseif A.pole then
				tri(m, A.pole, B.start + c1, B.start + c)
			elseif B.pole then
				tri(m, A.start + c, A.start + c1, B.pole)
			else
				local a, b, cc, d = A.start + c, A.start + c1, B.start + c, B.start + c1
				tri(m, a, b, cc)
				tri(m, b, d, cc)
			end
		end
		step(nu)
	end
	local info = { first = first, last = m.nv, firstTri = firstTri, lastTri = m.nt }
	if opts.outwardFrom then
		local o = opts.outwardFrom
		MeshKit.OrientFrom(m, o[1], o[2], o[3], firstTri, m.nt)
	elseif opts.flip then
		MeshKit.Flip(m, firstTri, m.nt, true)
	end
	return info
end

-- flip the triangles [firstTri, lastTri] if most of them face toward (cx, cy, cz) (closed / convex-ish
-- pieces built with an unknown parameter orientation)
function MeshKit.OrientFrom(m, cx, cy, cz, firstTri, lastTri)
	local P, T = m.P, m.T
	local score = 0
	for t = firstTri or 1, lastTri or m.nt do
		local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		local ax, ay, az = P[a * 3 - 2], P[a * 3 - 1], P[a * 3]
		local bx, by, bz = P[b * 3 - 2], P[b * 3 - 1], P[b * 3]
		local qx, qy, qz = P[c * 3 - 2], P[c * 3 - 1], P[c * 3]
		local nx, ny, nz = cross(bx - ax, by - ay, bz - az, qx - ax, qy - ay, qz - az)
		local ox, oy, oz = (ax + bx + qx) / 3 - cx, (ay + by + qy) / 3 - cy, (az + bz + qz) / 3 - cz
		score += dot(nx, ny, nz, ox, oy, oz) >= 0 and 1 or -1
	end
	if score < 0 then
		MeshKit.Flip(m, firstTri or 1, lastTri or m.nt, true)
		return true
	end
	return false
end

-- ellipsoid (or a patch of one) around (cx, cy, cz) with radii rx, ry, rz. opts:
--   rings (latitude segments), sides (longitude segments)
--   th0, th1: polar range from the bottom pole (0) to the top pole (pi); a0, a1: longitude range
--   (0 = +X, pi/2 = -Z front, MeshKit angle convention; a full turn wraps)
--   radial(dx, dy, dz, u, v) -> k: radius multiplier along the unit direction (sculpting skulls / bellies)
--   deform(x, y, z, dx, dy, dz, u, v) -> x, y, z: free deformation after the radial scale
--   color(x, y, z, dx, dy, dz) -> r, g, b [, alpha]; group
function MeshKit.Ellipsoid(m, cx, cy, cz, rx, ry, rz, opts)
	opts = opts or {}
	local th0, th1 = opts.th0 or 0, opts.th1 or pi
	local a0, a1 = opts.a0 or 0, opts.a1 or TAU
	local full = abs(a1 - a0 - TAU) < 1e-9
	local radial, deform, color = opts.radial, opts.deform, opts.color
	local function fn(u, v)
		local th = th0 + (th1 - th0) * v
		local a = a0 + (a1 - a0) * u
		local st = sin(th)
		local dx, dy, dz = st * cos(a), -cos(th), -st * sin(a)
		local k = radial and radial(dx, dy, dz, u, v) or 1
		local x, y, z = cx + rx * dx * k, cy + ry * dy * k, cz + rz * dz * k
		if deform then
			x, y, z = deform(x, y, z, dx, dy, dz, u, v)
		end
		if color then
			return x, y, z, color(x, y, z, dx, dy, dz)
		end
		return x, y, z
	end
	return MeshKit.Surface(m, fn, {
		nu = opts.sides or 24, nv = opts.rings or 16, wrapU = full, uvSeam = opts.uvSeam,
		poleV0 = th0 <= 1e-9, poleV1 = th1 >= pi - 1e-9, group = opts.group,
		outwardFrom = { cx, cy, cz },
	})
end

------------------------------------------------------------------------
-- Tube and ribbon sweeps (hair strands, clumps, locs, braids, cards)
------------------------------------------------------------------------
-- pts = control points {x,y,z} (Catmull-Rom) or a dense list with exact = true. opts:
--   segments (rings, default 8), sides (default 5), radius (number or fn(t)), taper (tip radius factor,
--   default 0.25), flatten (front / side radius ratio, default 1), twist (radians root -> tip),
--   lumps = { amp, freq, seed } (loc / dread irregularity), rootCap (nil | "flat" | "dome"),
--   tipCap ("point" default | "dome" | "flat" | nil), normalHint (side axis of the first ring),
--   color(t, a, x, y, z) | rootColor / tipColor {r,g,b} gradient, group
function MeshKit.Tube(m, pts, opts)
	opts = opts or {}
	local rad = opts.radius or 0.05
	local taper = opts.taper or 0.25
	local flatten = opts.flatten or 1
	local twist = opts.twist or 0
	local lumps = opts.lumps
	local rc, tc = opts.rootColor, opts.tipColor
	local color = opts.color
	if not color and rc then
		tc = tc or rc
		color = function(t)
			return lerp(rc[1], tc[1], t), lerp(rc[2], tc[2], t), lerp(rc[3], tc[3], t)
		end
	end
	return MeshKit.Loft(m, {
		rings = opts.segments or 8, sides = opts.sides or 5, spine = pts, exact = opts.exact,
		sideHint = opts.normalHint, frontHint = opts.frontHint,
		section = function(t, a)
			local r = (type(rad) == "function" and rad(t) or rad) * lerp(1, taper, t)
			if lumps then
				r *= 1 + (lumps.amp or 0.15) * noise3(t * (lumps.freq or 6), cos(a) * 1.3, sin(a) * 1.3, lumps.seed or 0)
			end
			local aa = a + twist * t
			return r * cos(aa), r * flatten * sin(aa)
		end,
		capStart = opts.rootCap, capEnd = opts.tipCap == nil and "point" or opts.tipCap or nil,
		capDepth = opts.capDepth, domeRings = opts.domeRings,
		color = color, group = opts.group,
	})
end

-- flat strip (hair card, eyelash row, brow hairs). pts as Tube; opts: segments, width (number or
-- fn(t)), taper, normalHint = the card's facing direction at the root (default +Y: lying flat),
-- twist, doubleSided (adds a back face: the MeshPart may not render back faces), color / rootColor /
-- tipColor, alphaRoot / alphaTip (soft tips), group
function MeshKit.Ribbon(m, pts, opts)
	opts = opts or {}
	local n = max(2, opts.segments or 8)
	local hint = opts.normalHint or { 0, 1, 0 }
	-- frames: front axis = the facing hint, side axis = across the card (perpendicular to the spine and
	-- the hint at the root, then parallel transported)
	local x0, y0, z0 = spinePoint(pts, 0, opts.exact)
	local x1, y1, z1 = spinePoint(pts, 1 / (n - 1), opts.exact)
	local sx, sy, sz = norm3(cross(x1 - x0, y1 - y0, z1 - z0, hint[1], hint[2], hint[3]))
	local frames = MeshKit.Frames(pts, n, (sx ~= 0 or sy ~= 0 or sz ~= 0) and { sx, sy, sz } or nil, hint, 0, 1, opts.exact)
	local w = opts.width or 0.06
	local taper = opts.taper or 0.3
	local twist = opts.twist or 0
	local rc, tc = opts.rootColor or { 1, 1, 1 }, opts.tipColor
	tc = tc or rc
	local first, firstTri = m.nv + 1, m.nt + 1
	local alpha = opts.alphaRoot or opts.alphaTip
	for i = 1, n do
		local f = frames[i]
		local t = (i - 1) / (n - 1)
		local hw = (type(w) == "function" and w(t) or w) * lerp(1, taper, t) / 2
		local ca, sa = cos(twist * t), sin(twist * t)
		-- across = side * cos + front * sin (twist turns the card about its spine)
		local ax = f[7] * ca + f[10] * sa
		local ay = f[8] * ca + f[11] * sa
		local az = f[9] * ca + f[12] * sa
		local r, g, b
		if opts.color then
			r, g, b = opts.color(t, 0, f[1], f[2], f[3])
		else
			r, g, b = lerp(rc[1], tc[1], t), lerp(rc[2], tc[2], t), lerp(rc[3], tc[3], t)
		end
		for side = -1, 1, 2 do
			local idx = vertex(m, f[1] + ax * hw * side, f[2] + ay * hw * side, f[3] + az * hw * side, (side + 1) / 2, t, r, g, b)
			if alpha then
				ensureAlpha(m)[idx] = lerp(opts.alphaRoot or 1, opts.alphaTip or 1, t)
			end
			if opts.group then
				MeshKit.AddToGroup(m, opts.group, idx)
			end
		end
		step(2)
	end
	-- the strip faces along the frames' front axis (the hint)
	local front = frames[1]
	for i = 1, n - 1 do
		local a, b = first + (i - 1) * 2, first + (i - 1) * 2 + 1
		local c, d = a + 2, b + 2
		tri(m, a, b, c)
		tri(m, b, d, c)
	end
	-- orient: the first triangle's normal should agree with the hint
	do
		local P = m.P
		local a, b, c = first, first + 1, first + 2
		local nx, ny, nz = cross(P[b * 3 - 2] - P[a * 3 - 2], P[b * 3 - 1] - P[a * 3 - 1], P[b * 3] - P[a * 3],
			P[c * 3 - 2] - P[a * 3 - 2], P[c * 3 - 1] - P[a * 3 - 1], P[c * 3] - P[a * 3])
		if dot(nx, ny, nz, front[10], front[11], front[12]) < 0 then
			MeshKit.Flip(m, firstTri, m.nt, true)
		end
	end
	if opts.doubleSided then
		local back0 = m.nv
		local count = m.nv - first + 1
		local P, U, C = m.P, m.U, m.C
		for i = first, first + count - 1 do
			local idx = vertex(m, P[i * 3 - 2], P[i * 3 - 1], P[i * 3], U[i * 2 - 1], U[i * 2], C[i * 3 - 2], C[i * 3 - 1], C[i * 3])
			if m.A then
				m.A[idx] = m.A[i]
			end
			if opts.group then
				MeshKit.AddToGroup(m, opts.group, idx)
			end
		end
		local lastFront = m.nt
		for t = firstTri, lastFront do
			local T = m.T
			local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
			tri(m, a - first + 1 + back0, c - first + 1 + back0, b - first + 1 + back0)
		end
	end
	return { first = first, last = m.nv, firstTri = firstTri, lastTri = m.nt }
end

------------------------------------------------------------------------
-- Signed distance fields + surface nets (organic blends: skull, jaw, cheekbones, muscle groups)
------------------------------------------------------------------------
-- An SDF is fn(x, y, z) -> distance (negative inside). Primitives return such functions; compose them
-- with SDF.Union / SDF.SmoothUnion / SDF.SmoothSubtract or write one function by hand (faster: fewer
-- closures). Keep fields close to true distances (|gradient| ~ 1): Polygonize skips empty space with
-- that assumption.
local SDF = {}
MeshKit.SDF = SDF

function SDF.Sphere(cx, cy, cz, r)
	return function(x, y, z)
		local dx, dy, dz = x - cx, y - cy, z - cz
		return sqrt(dx * dx + dy * dy + dz * dz) - r
	end
end

-- ellipsoid (Quilez' bound: exact on the surface, close nearby)
function SDF.Ellipsoid(cx, cy, cz, rx, ry, rz)
	return function(x, y, z)
		local px, py, pz = (x - cx) / rx, (y - cy) / ry, (z - cz) / rz
		local k0 = sqrt(px * px + py * py + pz * pz)
		local qx, qy, qz = px / rx, py / ry, pz / rz
		local k1 = sqrt(qx * qx + qy * qy + qz * qz)
		if k1 < 1e-9 then
			return -min(rx, ry, rz)
		end
		return k0 * (k0 - 1) / k1
	end
end

-- capsule between a and b with radius r (or a round cone from ra at a to rb at b)
function SDF.Capsule(ax, ay, az, bx, by, bz, ra, rb)
	rb = rb or ra
	local abx, aby, abz = bx - ax, by - ay, bz - az
	local l2 = abx * abx + aby * aby + abz * abz
	if ra == rb then
		return function(x, y, z)
			local px, py, pz = x - ax, y - ay, z - az
			local h = l2 > 0 and clamp((px * abx + py * aby + pz * abz) / l2, 0, 1) or 0
			local dx, dy, dz = px - abx * h, py - aby * h, pz - abz * h
			return sqrt(dx * dx + dy * dy + dz * dz) - ra
		end
	end
	-- round cone (Quilez sdRoundCone, arbitrary orientation)
	local rr = ra - rb
	local a2 = l2 - rr * rr
	local il2 = l2 > 0 and 1 / l2 or 0
	return function(x, y, z)
		local px, py, pz = x - ax, y - ay, z - az
		local yv = px * abx + py * aby + pz * abz
		local zv = yv - l2
		local wx, wy, wz = px * l2 - abx * yv, py * l2 - aby * yv, pz * l2 - abz * yv
		local x2 = wx * wx + wy * wy + wz * wz
		local y2 = yv * yv * l2
		local z2 = zv * zv * l2
		local k = (rr >= 0 and 1 or -1) * rr * rr * x2
		if (zv >= 0 and 1 or -1) * a2 * z2 > k then
			local dx, dy, dz = px - abx, py - aby, pz - abz
			return sqrt(dx * dx + dy * dy + dz * dz) - rb
		end
		if (yv >= 0 and 1 or -1) * a2 * y2 < k then
			return sqrt(px * px + py * py + pz * pz) - ra
		end
		return (sqrt(x2 * a2 * il2) + yv * rr) * il2 - ra
	end
end

-- axis-aligned rounded box centred at (cx, cy, cz), half extents hx, hy, hz, corner radius r
function SDF.RoundBox(cx, cy, cz, hx, hy, hz, r)
	return function(x, y, z)
		local qx, qy, qz = abs(x - cx) - hx + r, abs(y - cy) - hy + r, abs(z - cz) - hz + r
		local ox, oy, oz = max(qx, 0), max(qy, 0), max(qz, 0)
		return sqrt(ox * ox + oy * oy + oz * oz) + min(max(qx, max(qy, qz)), 0) - r
	end
end

-- polynomial smooth min / max (k = blend radius in studs)
local function smin(a, b, k)
	if k <= 0 then
		return min(a, b)
	end
	local h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
	return b + (a - b) * h - k * h * (1 - h)
end
local function smax(a, b, k)
	return -smin(-a, -b, k)
end
SDF.smin, SDF.smax = smin, smax

function SDF.Union(list)
	return function(x, y, z)
		local d = math.huge
		for i = 1, #list do
			local v = list[i](x, y, z)
			if v < d then
				d = v
			end
		end
		return d
	end
end

-- smooth union of a list; k = one blend radius or a list (k[i] blends field i into the running result)
function SDF.SmoothUnion(list, k)
	return function(x, y, z)
		local d = list[1](x, y, z)
		for i = 2, #list do
			d = smin(d, list[i](x, y, z), type(k) == "table" and (k[i] or 0) or k)
		end
		return d
	end
end

function SDF.SmoothSubtract(a, b, k)
	return function(x, y, z)
		return smax(a(x, y, z), -b(x, y, z), k)
	end
end

function SDF.SmoothIntersect(a, b, k)
	return function(x, y, z)
		return smax(a(x, y, z), b(x, y, z), k)
	end
end

-- field in a transformed space: mt maps world -> the primitive's local space (an inverse transform)
function SDF.Transform(f, mt, scale)
	scale = scale or 1
	return function(x, y, z)
		local lx, ly, lz = MeshKit.MatApply(mt, x, y, z)
		return f(lx, ly, lz) * scale
	end
end

-- add a displacement fn(x, y, z) -> studs (negative = bulge out): noise, striations, dents
function SDF.Displace(f, fn)
	return function(x, y, z)
		return f(x, y, z) + fn(x, y, z)
	end
end

-- surface nets over the box [x0, x1] x [y0, y1] x [z0, z1] with cell size `cell`. opts:
--   refine (Newton projections onto the surface, default 1), smoothNormals (gradient normals, default
--   true), color(x, y, z, nx, ny, nz) -> r, g, b [, alpha], group, maxCells (safety, default 400000),
--   skipEmpty (default true: points whose sign is certain from a neighbour 2 cells away are not
--   evaluated; needs a field with |gradient| <= ~1, i.e. a real or bounded distance)
-- The field must be positive (outside) on the box boundary for a closed result. The grid origin is
-- nudged by a few hundredths of a cell so round-number fields never put an exact zero on a grid point
-- (that would collapse neighbouring cell vertices onto one point).
function MeshKit.Polygonize(m, f, x0, y0, z0, x1, y1, z1, cell, opts)
	opts = opts or {}
	local h = cell
	x0, y0, z0 = x0 - 0.0173 * h, y0 - 0.0137 * h, z0 - 0.0159 * h
	local nx = max(1, math.ceil((x1 - x0) / h))
	local ny = max(1, math.ceil((y1 - y0) / h))
	local nz = max(1, math.ceil((z1 - z0) / h))
	if nx * ny * nz > (opts.maxCells or 400000) then
		error("MeshKit.Polygonize: too many cells (" .. nx * ny * nz .. ")", 2)
	end
	local px, py = nx + 1, ny + 1
	local F = {}
	local evals = 0
	local function sample(i, j, k)
		evals += 1
		local v = f(x0 + i * h, y0 + j * h, z0 + k * h)
		if v > -1e-10 and v < 1e-10 then
			v = 1e-10 -- an exact zero counts as outside
		end
		return v
	end
	if opts.skipEmpty == false then
		for k = 0, nz do
			for j = 0, ny do
				for i = 0, nx do
					F[i + px * (j + py * k)] = sample(i, j, k)
				end
			end
			step(px * py * 0.3)
		end
	else
		-- even lattice first, then every other point only where its nearest even point does not already
		-- decide the sign: |f(c)| > |p - c| * 1.15 means no surface between them
		for k = 0, nz, 2 do
			for j = 0, ny, 2 do
				for i = 0, nx, 2 do
					F[i + px * (j + py * k)] = sample(i, j, k)
				end
			end
			step(px * py * 0.08)
		end
		local d1, d2, d3 = h * 1.15, h * sqrt(2) * 1.15, h * sqrt(3) * 1.15
		for k = 0, nz do
			local ck = k - k % 2
			for j = 0, ny do
				local cj = j - j % 2
				for i = 0, nx do
					local odd = i % 2 + j % 2 + k % 2
					if odd > 0 then
						local c = F[(i - i % 2) + px * (cj + py * ck)]
						local d = odd == 1 and d1 or (odd == 2 and d2 or d3)
						local a = c < 0 and -c or c
						if a > d then
							F[i + px * (j + py * k)] = c < 0 and -(a - d) or (a - d)
						else
							F[i + px * (j + py * k)] = sample(i, j, k)
						end
					end
				end
			end
			step(px * py * 0.15)
		end
	end
	-- one vertex per cell the surface crosses: the mean of its edge crossings
	local cellV = {}
	local first = m.nv + 1
	local EDGES = { { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 }, { 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 }, { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 } }
	local CX, CY, CZ = {}, {}, {}
	for c = 0, 7 do
		CX[c], CY[c], CZ[c] = c % 2, floor(c / 2) % 2, floor(c / 4)
	end
	local cv = table.create(8, 0)
	for k = 0, nz - 1 do
		for j = 0, ny - 1 do
			for i = 0, nx - 1 do
				local neg = 0
				for c = 0, 7 do
					local v = F[(i + CX[c]) + px * ((j + CY[c]) + py * (k + CZ[c]))]
					cv[c + 1] = v
					if v < 0 then
						neg += 1
					end
				end
				if neg > 0 and neg < 8 then
					local sx, sy, sz, cnt = 0, 0, 0, 0
					for e = 1, 12 do
						local ed = EDGES[e]
						local a, b = ed[1], ed[2]
						local va, vb = cv[a + 1], cv[b + 1]
						if (va < 0) ~= (vb < 0) then
							local t = va / (va - vb)
							sx += CX[a] + (CX[b] - CX[a]) * t
							sy += CY[a] + (CY[b] - CY[a]) * t
							sz += CZ[a] + (CZ[b] - CZ[a]) * t
							cnt += 1
						end
					end
					cellV[i + nx * (j + ny * k)] = vertex(m, x0 + (i + sx / cnt) * h, y0 + (j + sy / cnt) * h, z0 + (k + sz / cnt) * h)
				end
			end
		end
		step(nx * ny * 0.4)
	end
	-- faces: every grid edge with a sign change gets a quad of the four cells around it
	local function cellAt(i, j, k)
		return cellV[i + nx * (j + ny * k)]
	end
	local firstTri = m.nt + 1
	for k = 0, nz - 1 do
		for j = 0, ny - 1 do
			for i = 0, nx - 1 do
				if cellAt(i, j, k) then
					local in0 = F[i + px * (j + py * k)] < 0
					-- x edge (i,j,k)-(i+1,j,k): cells (i,j-1,k-1) (i,j,k-1) (i,j,k) (i,j-1,k); normal +x if in0
					if j > 0 and k > 0 and in0 ~= (F[(i + 1) + px * (j + py * k)] < 0) then
						local a, b, c, d = cellAt(i, j - 1, k - 1), cellAt(i, j, k - 1), cellAt(i, j, k), cellAt(i, j - 1, k)
						if a and b and c and d then
							if in0 then
								quad(m, a, b, c, d)
							else
								quad(m, a, d, c, b)
							end
						end
					end
					-- y edge: cells (i-1,j,k-1) (i-1,j,k) (i,j,k) (i,j,k-1); normal +y if in0
					if i > 0 and k > 0 and in0 ~= (F[i + px * ((j + 1) + py * k)] < 0) then
						local a, b, c, d = cellAt(i - 1, j, k - 1), cellAt(i - 1, j, k), cellAt(i, j, k), cellAt(i, j, k - 1)
						if a and b and c and d then
							if in0 then
								quad(m, a, b, c, d)
							else
								quad(m, a, d, c, b)
							end
						end
					end
					-- z edge: cells (i-1,j-1,k) (i,j-1,k) (i,j,k) (i-1,j,k); normal +z if in0
					if i > 0 and j > 0 and in0 ~= (F[i + px * (j + py * (k + 1))] < 0) then
						local a, b, c, d = cellAt(i - 1, j - 1, k), cellAt(i, j - 1, k), cellAt(i, j, k), cellAt(i - 1, j, k)
						if a and b and c and d then
							if in0 then
								quad(m, a, b, c, d)
							else
								quad(m, a, d, c, b)
							end
						end
					end
				end
			end
		end
		step(nx * ny * 0.25)
	end
	-- project onto the surface (Newton steps on forward differences) and take the normal from the field
	local refine = opts.refine or 1
	local e = h * 0.2
	local P, N = m.P, m.N
	local color = opts.color
	local smooth = opts.smoothNormals ~= false
	for i = first, m.nv do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		local gx, gy, gz = 0, 0, 0
		for _ = 1, refine do
			local d = f(x, y, z)
			gx = (f(x + e, y, z) - d) / e
			gy = (f(x, y + e, z) - d) / e
			gz = (f(x, y, z + e) - d) / e
			evals += 4
			local g2 = gx * gx + gy * gy + gz * gz
			if g2 > 1e-12 then
				local k = d / g2
				-- never leave the cell neighbourhood (a weak gradient would throw the vertex far away)
				local mx, my, mz = gx * k, gy * k, gz * k
				local ml = sqrt(mx * mx + my * my + mz * mz)
				if ml > h then
					mx, my, mz = mx * h / ml, my * h / ml, mz * h / ml
				end
				x, y, z = x - mx, y - my, z - mz
			end
		end
		if smooth then
			if refine < 1 then
				local d = f(x, y, z)
				gx, gy, gz = f(x + e, y, z) - d, f(x, y + e, z) - d, f(x, y, z + e) - d
			end
			local ux, uy, uz = norm3(gx, gy, gz)
			N[i * 3 - 2], N[i * 3 - 1], N[i * 3] = ux, uy, uz
		end
		P[i * 3 - 2], P[i * 3 - 1], P[i * 3] = x, y, z
		if color then
			local r, g, b, a = color(x, y, z, N[i * 3 - 2], N[i * 3 - 1], N[i * 3])
			if r then
				MeshKit.SetColor(m, i, r, g, b, a)
			end
		end
		if opts.group then
			MeshKit.AddToGroup(m, opts.group, i)
		end
		step(1.5)
	end
	if not smooth then
		MeshKit.ComputeNormals(m, { first = first })
	end
	return { first = first, last = m.nv, firstTri = firstTri, lastTri = m.nt, cells = nx * ny * nz, evals = evals }
end

------------------------------------------------------------------------
-- Welding, topology, normals, smoothing, subdivision
------------------------------------------------------------------------
-- canonical vertex per position (vertices duplicated along UV seams / dome joins share one)
local function weldMap(m, eps)
	local P = m.P
	local q = 1 / (eps or 1e-5)
	local seen = {}
	local canon = table.create(m.nv)
	for i = 1, m.nv do
		local key = string.format("%d,%d,%d", floor(P[i * 3 - 2] * q + 0.5), floor(P[i * 3 - 1] * q + 0.5), floor(P[i * 3] * q + 0.5))
		local c = seen[key]
		if not c then
			seen[key] = i
			c = i
		end
		canon[i] = c
		step(0.5)
	end
	return canon
end
MeshKit.WeldMap = weldMap

-- area-weighted vertex normals. Vertices at the same position (UV seams, loft joins, poles) share their
-- normal when their own normals are within `crease` degrees (default 75), so seams vanish while hard
-- edges and the two sides of a double-sided card stay apart.
-- opts: first (only write vertices >= first), weld (default true), crease (degrees)
function MeshKit.ComputeNormals(m, opts)
	opts = opts or {}
	local P, N, T = m.P, m.N, m.T
	local acc = table.create(m.nv * 3, 0)
	for t = 1, m.nt do
		local t3 = t * 3
		local a, b, c = T[t3 - 2], T[t3 - 1], T[t3]
		local ax, ay, az = P[a * 3 - 2], P[a * 3 - 1], P[a * 3]
		local nx, ny, nz = cross(P[b * 3 - 2] - ax, P[b * 3 - 1] - ay, P[b * 3] - az, P[c * 3 - 2] - ax, P[c * 3 - 1] - ay, P[c * 3] - az)
		acc[a * 3 - 2] += nx
		acc[a * 3 - 1] += ny
		acc[a * 3] += nz
		acc[b * 3 - 2] += nx
		acc[b * 3 - 1] += ny
		acc[b * 3] += nz
		acc[c * 3 - 2] += nx
		acc[c * 3 - 1] += ny
		acc[c * 3] += nz
		step(1)
	end
	local first = opts.first or 1
	if opts.weld == false then
		for i = first, m.nv do
			local x, y, z = norm3(acc[i * 3 - 2], acc[i * 3 - 1], acc[i * 3])
			if x == 0 and y == 0 and z == 0 then
				y = 1
			end
			N[i * 3 - 2], N[i * 3 - 1], N[i * 3] = x, y, z
		end
		return m
	end
	local canon = weldMap(m)
	local members = {}
	for i = 1, m.nv do
		local c = canon[i]
		if c ~= i then
			local l = members[c]
			if not l then
				l = { c }
				members[c] = l
			end
			l[#l + 1] = i
		end
	end
	local cosCrease = cos(math.rad(opts.crease or 75))
	for i = first, m.nv do
		local ix, iy, iz = norm3(acc[i * 3 - 2], acc[i * 3 - 1], acc[i * 3])
		local sx, sy, sz = acc[i * 3 - 2], acc[i * 3 - 1], acc[i * 3]
		local l = members[canon[i]]
		if l then
			sx, sy, sz = 0, 0, 0
			for _, j in ipairs(l) do
				local jx, jy, jz = acc[j * 3 - 2], acc[j * 3 - 1], acc[j * 3]
				local ux, uy, uz = norm3(jx, jy, jz)
				if j == i or dot(ix, iy, iz, ux, uy, uz) >= cosCrease then
					sx += jx
					sy += jy
					sz += jz
				end
			end
		end
		local x, y, z = norm3(sx, sy, sz)
		if x == 0 and y == 0 and z == 0 then
			y = 1
		end
		N[i * 3 - 2], N[i * 3 - 1], N[i * 3] = x, y, z
		step(0.3)
	end
	return m
end

-- neighbour sets over the welded topology: returns canon, nbr[canonVertex] = { canonical neighbours },
-- edgeCount[key] (key = lo * (nv + 1) + hi on canonical ids)
local function topology(m)
	local canon = weldMap(m)
	local T = m.T
	local nbr = {}
	local edges = {}
	local stride = m.nv + 1
	local function link(a, b)
		local l = nbr[a]
		if not l then
			l = {}
			nbr[a] = l
		end
		if not table.find(l, b) then
			l[#l + 1] = b
		end
	end
	for t = 1, m.nt do
		local a, b, c = canon[T[t * 3 - 2]], canon[T[t * 3 - 1]], canon[T[t * 3]]
		for _, e in ipairs({ { a, b }, { b, c }, { c, a } }) do
			local u, v = e[1], e[2]
			if u ~= v then
				link(u, v)
				link(v, u)
				local lo, hi = min(u, v), max(u, v)
				local key = lo * stride + hi
				edges[key] = (edges[key] or 0) + 1
			end
		end
		step(1)
	end
	return canon, nbr, edges, stride
end
MeshKit.Topology = topology

-- boundary (1 face), non-manifold (> 2 faces) and total edges of the welded topology;
-- a closed watertight surface has boundary == 0 and nonManifold == 0
function MeshKit.EdgeStats(m)
	local _, _, edges = topology(m)
	local boundary, nonManifold, total = 0, 0, 0
	for _, c in pairs(edges) do
		total += 1
		if c == 1 then
			boundary += 1
		elseif c > 2 then
			nonManifold += 1
		end
	end
	return { boundary = boundary, nonManifold = nonManifold, edges = total }
end

-- signed volume (positive for a closed mesh whose faces point out)
function MeshKit.SignedVolume(m)
	local P, T = m.P, m.T
	local v = 0
	for t = 1, m.nt do
		local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		local ax, ay, az = P[a * 3 - 2], P[a * 3 - 1], P[a * 3]
		local bx, by, bz = P[b * 3 - 2], P[b * 3 - 1], P[b * 3]
		local cx, cy, cz = P[c * 3 - 2], P[c * 3 - 1], P[c * 3]
		v += ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx)
	end
	return v / 6
end

-- merge vertices at the same position into one (drops UV seams: keep the first vertex's attributes);
-- returns a new mesh and the old -> new index map
function MeshKit.Weld(m, eps)
	local canon = weldMap(m, eps)
	local out = MeshKit.New(m.name)
	local map = table.create(m.nv)
	for i = 1, m.nv do
		if canon[i] == i then
			local i3 = i * 3
			local n = vertex(out, m.P[i3 - 2], m.P[i3 - 1], m.P[i3], m.U[i * 2 - 1], m.U[i * 2], m.C[i3 - 2], m.C[i3 - 1], m.C[i3])
			out.N[n * 3 - 2], out.N[n * 3 - 1], out.N[n * 3] = m.N[i3 - 2], m.N[i3 - 1], m.N[i3]
			if m.A then
				ensureAlpha(out)[n] = m.A[i]
			end
			map[i] = n
		end
	end
	for i = 1, m.nv do
		map[i] = map[canon[i]]
	end
	for t = 1, m.nt do
		local a, b, c = map[m.T[t * 3 - 2]], map[m.T[t * 3 - 1]], map[m.T[t * 3]]
		if a ~= b and b ~= c and a ~= c then
			tri(out, a, b, c)
		end
	end
	for k, g in pairs(m.groups) do
		local seen, ng = {}, {}
		for _, i in ipairs(g) do
			local n = map[i]
			if not seen[n] then
				seen[n] = true
				ng[#ng + 1] = n
			end
		end
		out.groups[k] = ng
	end
	for k, p in pairs(m.landmarks) do
		out.landmarks[k] = { p[1], p[2], p[3] }
	end
	return out, map
end

-- Taubin smoothing (shrink-free): iterations of lambda / mu Laplacian steps on the welded topology.
-- opts: lambda (0.5), mu (-0.53), keepBoundary (true), weight(i) -> 0..1 (per-vertex strength), only
-- = group name (smooth just that region)
function MeshKit.Relax(m, iterations, opts)
	opts = opts or {}
	local canon, nbr, edges, stride = topology(m)
	local P = m.P
	local lambda, mu = opts.lambda or 0.5, opts.mu or -0.53
	local fixed = {}
	if opts.keepBoundary ~= false then
		for key, c in pairs(edges) do
			if c == 1 then
				local lo, hi = floor(key / stride), key % stride
				fixed[lo], fixed[hi] = true, true
			end
		end
	end
	local active
	if opts.only and m.groups[opts.only] then
		active = {}
		for _, i in ipairs(m.groups[opts.only]) do
			active[canon[i]] = true
		end
	end
	local reps = {}
	for i = 1, m.nv do
		if canon[i] == i then
			reps[#reps + 1] = i
		end
	end
	local tmp = {}
	local function pass(k)
		for _, i in ipairs(reps) do
			local l = nbr[i]
			if l and #l > 0 and not fixed[i] and (not active or active[i]) then
				local sx, sy, sz = 0, 0, 0
				for _, j in ipairs(l) do
					sx += P[j * 3 - 2]
					sy += P[j * 3 - 1]
					sz += P[j * 3]
				end
				local n = #l
				local w = k * (opts.weight and opts.weight(i) or 1)
				local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
				tmp[i * 3 - 2] = x + (sx / n - x) * w
				tmp[i * 3 - 1] = y + (sy / n - y) * w
				tmp[i * 3] = z + (sz / n - z) * w
			end
			step(0.5)
		end
		for _, i in ipairs(reps) do
			if tmp[i * 3] then
				P[i * 3 - 2], P[i * 3 - 1], P[i * 3] = tmp[i * 3 - 2], tmp[i * 3 - 1], tmp[i * 3]
				tmp[i * 3 - 2], tmp[i * 3 - 1], tmp[i * 3] = nil, nil, nil
			end
		end
	end
	for _ = 1, iterations or 1 do
		pass(lambda)
		pass(mu)
	end
	-- duplicates follow their canonical vertex
	for i = 1, m.nv do
		local c = canon[i]
		if c ~= i then
			P[i * 3 - 2], P[i * 3 - 1], P[i * 3] = P[c * 3 - 2], P[c * 3 - 1], P[c * 3]
		end
	end
	return m
end

-- Loop subdivision (levels, default 1) on the welded topology: seams keep their duplicated attributes
-- but move together; boundaries follow the boundary rules. Returns a NEW mesh (normals recomputed;
-- groups keep vertices whose both parents were in the group; weights / alpha interpolate).
function MeshKit.Subdivide(m, levels)
	local cur = m
	for _ = 1, levels or 1 do
		local canon, nbr, edges, stride = topology(cur)
		local P, T = cur.P, cur.T
		-- opposite vertices per canonical edge
		local opp = {}
		for t = 1, cur.nt do
			local a, b, c = canon[T[t * 3 - 2]], canon[T[t * 3 - 1]], canon[T[t * 3]]
			for _, e in ipairs({ { a, b, c }, { b, c, a }, { c, a, b } }) do
				local u, v, w = e[1], e[2], e[3]
				if u ~= v then
					local key = min(u, v) * stride + max(u, v)
					local o = opp[key]
					if not o then
						o = {}
						opp[key] = o
					end
					o[#o + 1] = w
				end
			end
			step(1)
		end
		-- boundary neighbours of each canonical vertex
		local bnd = {}
		for key, cnt in pairs(edges) do
			if cnt == 1 then
				local lo, hi = floor(key / stride), key % stride
				bnd[lo] = bnd[lo] or {}
				bnd[hi] = bnd[hi] or {}
				table.insert(bnd[lo], hi)
				table.insert(bnd[hi], lo)
			end
		end
		-- even vertices
		local even = {}
		for i = 1, cur.nv do
			if canon[i] == i then
				local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
				local b = bnd[i]
				if b and #b == 2 then
					local a, c = b[1], b[2]
					even[i] = { 0.75 * x + 0.125 * (P[a * 3 - 2] + P[c * 3 - 2]), 0.75 * y + 0.125 * (P[a * 3 - 1] + P[c * 3 - 1]), 0.75 * z + 0.125 * (P[a * 3] + P[c * 3]) }
				elseif b then
					even[i] = { x, y, z } -- corner / non-manifold boundary vertex: keep
				else
					local l = nbr[i] or {}
					local n = #l
					if n < 3 then
						even[i] = { x, y, z }
					else
						local beta = n == 3 and 3 / 16 or 3 / (8 * n)
						local sx, sy, sz = 0, 0, 0
						for _, j in ipairs(l) do
							sx += P[j * 3 - 2]
							sy += P[j * 3 - 1]
							sz += P[j * 3]
						end
						even[i] = { (1 - n * beta) * x + beta * sx, (1 - n * beta) * y + beta * sy, (1 - n * beta) * z + beta * sz }
					end
				end
			end
			step(0.5)
		end
		local out = MeshKit.New(cur.name)
		local hasA = cur.A ~= nil
		for i = 1, cur.nv do
			local e = even[canon[i]]
			local i3 = i * 3
			local n = vertex(out, e[1], e[2], e[3], cur.U[i * 2 - 1], cur.U[i * 2], cur.C[i3 - 2], cur.C[i3 - 1], cur.C[i3])
			if hasA then
				ensureAlpha(out)[n] = cur.A[i]
			end
		end
		-- odd vertices: one per original (unwelded) edge, positioned by its canonical edge
		local oddIdx = {}
		local ostride = cur.nv + 1
		local function odd(a, b)
			local lo, hi = min(a, b), max(a, b)
			local key = lo * ostride + hi
			local idx = oddIdx[key]
			if idx then
				return idx
			end
			local ca, cb = canon[lo], canon[hi]
			local ck = min(ca, cb) * stride + max(ca, cb)
			local o = opp[ck] or {}
			local x, y, z
			local ax, ay, az = P[ca * 3 - 2], P[ca * 3 - 1], P[ca * 3]
			local bx, by, bz = P[cb * 3 - 2], P[cb * 3 - 1], P[cb * 3]
			if #o == 2 then
				local c, d = o[1], o[2]
				x = 0.375 * (ax + bx) + 0.125 * (P[c * 3 - 2] + P[d * 3 - 2])
				y = 0.375 * (ay + by) + 0.125 * (P[c * 3 - 1] + P[d * 3 - 1])
				z = 0.375 * (az + bz) + 0.125 * (P[c * 3] + P[d * 3])
			else
				x, y, z = (ax + bx) / 2, (ay + by) / 2, (az + bz) / 2
			end
			local l3, h3 = lo * 3, hi * 3
			idx = vertex(out, x, y, z, (cur.U[lo * 2 - 1] + cur.U[hi * 2 - 1]) / 2, (cur.U[lo * 2] + cur.U[hi * 2]) / 2,
				(cur.C[l3 - 2] + cur.C[h3 - 2]) / 2, (cur.C[l3 - 1] + cur.C[h3 - 1]) / 2, (cur.C[l3] + cur.C[h3]) / 2)
			if hasA then
				ensureAlpha(out)[idx] = (cur.A[lo] + cur.A[hi]) / 2
			end
			oddIdx[key] = idx
			return idx
		end
		local parents = {}
		for t = 1, cur.nt do
			local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
			local ab, bc, ca = odd(a, b), odd(b, c), odd(c, a)
			parents[ab] = parents[ab] or { a, b }
			parents[bc] = parents[bc] or { b, c }
			parents[ca] = parents[ca] or { c, a }
			tri(out, a, ab, ca)
			tri(out, ab, b, bc)
			tri(out, ca, bc, c)
			tri(out, ab, bc, ca)
			step(2)
		end
		-- groups / weights / landmarks
		for k, g in pairs(cur.groups) do
			local inG = {}
			for _, i in ipairs(g) do
				inG[i] = true
			end
			local ng = table.clone(g)
			for idx = cur.nv + 1, out.nv do
				local p = parents[idx]
				if p and inG[p[1]] and inG[p[2]] then
					ng[#ng + 1] = idx
				end
			end
			out.groups[k] = ng
		end
		if cur.W then
			out.W = {}
			for k, w in pairs(cur.W) do
				local nw = table.create(out.nv, 0)
				for i = 1, cur.nv do
					nw[i] = w[i] or 0
				end
				for idx = cur.nv + 1, out.nv do
					local p = parents[idx]
					nw[idx] = p and ((w[p[1]] or 0) + (w[p[2]] or 0)) / 2 or 0
				end
				out.W[k] = nw
			end
		end
		for k, p in pairs(cur.landmarks) do
			out.landmarks[k] = { p[1], p[2], p[3] }
		end
		out.meta = cur.meta
		cur = out
	end
	MeshKit.ComputeNormals(cur)
	return cur
end

------------------------------------------------------------------------
-- Colour: fills, gradients, masks, cavity / ambient occlusion
------------------------------------------------------------------------
function MeshKit.Fill(m, r, g, b, a, first, last)
	local C = m.C
	for i = first or 1, last or m.nv do
		C[i * 3 - 2], C[i * 3 - 1], C[i * 3] = r, g, b
	end
	if a ~= nil and (a < 1 or m.A) then
		local A = ensureAlpha(m)
		for i = first or 1, last or m.nv do
			A[i] = a
		end
	end
end

-- fn(i, x, y, z, nx, ny, nz, r, g, b) -> r, g, b [, alpha] (return nil to keep the vertex as is)
function MeshKit.Paint(m, fn, first, last)
	local P, N, C = m.P, m.N, m.C
	for i = first or 1, last or m.nv do
		local i3 = i * 3
		local r, g, b, a = fn(i, P[i3 - 2], P[i3 - 1], P[i3], N[i3 - 2], N[i3 - 1], N[i3], C[i3 - 2], C[i3 - 1], C[i3])
		if r then
			C[i3 - 2], C[i3 - 1], C[i3] = r, g, b
			if a ~= nil and (a < 1 or m.A) then
				ensureAlpha(m)[i] = a
			end
		end
		step(0.5)
	end
end

-- colour by position along a direction: t = (p . dir - v0) / (v1 - v0) (smoothstepped), c = lerp(c0, c1, t).
-- dir = "x" | "y" | "z" | {dx, dy, dz}; mode = "set" (default) | "mul" (multiply the current colour) |
-- number k (blend k of the gradient over the current colour)
function MeshKit.Gradient(m, dir, v0, v1, c0, c1, mode, first, last)
	local dx, dy, dz = 0, 0, 0
	if dir == "x" then
		dx = 1
	elseif dir == "z" then
		dz = 1
	elseif type(dir) == "table" then
		dx, dy, dz = norm3(dir[1], dir[2], dir[3])
	else
		dy = 1
	end
	local P, C = m.P, m.C
	for i = first or 1, last or m.nv do
		local i3 = i * 3
		local t = smoothstep(v0, v1, P[i3 - 2] * dx + P[i3 - 1] * dy + P[i3] * dz)
		local r, g, b = lerp(c0[1], c1[1], t), lerp(c0[2], c1[2], t), lerp(c0[3], c1[3], t)
		if mode == "mul" then
			C[i3 - 2] *= r
			C[i3 - 1] *= g
			C[i3] *= b
		elseif type(mode) == "number" then
			C[i3 - 2] = lerp(C[i3 - 2], r, mode)
			C[i3 - 1] = lerp(C[i3 - 1], g, mode)
			C[i3] = lerp(C[i3], b, mode)
		else
			C[i3 - 2], C[i3 - 1], C[i3] = r, g, b
		end
	end
end

-- blend toward a colour by weight fn(i, x, y, z, nx, ny, nz) -> 0..1
function MeshKit.Tint(m, r, g, b, weight, first, last)
	local P, N, C = m.P, m.N, m.C
	for i = first or 1, last or m.nv do
		local i3 = i * 3
		local w = weight(i, P[i3 - 2], P[i3 - 1], P[i3], N[i3 - 2], N[i3 - 1], N[i3])
		if w and w > 0 then
			w = min(w, 1)
			C[i3 - 2] = lerp(C[i3 - 2], r, w)
			C[i3 - 1] = lerp(C[i3 - 1], g, w)
			C[i3] = lerp(C[i3], b, w)
		end
	end
end

-- soft ellipsoid mask: 1 inside the core, fading to 0 at the ellipsoid surface (soft = fade share 0..1)
function MeshKit.EllipsoidMask(x, y, z, cx, cy, cz, rx, ry, rz, soft)
	local dx, dy, dz = (x - cx) / rx, (y - cy) / ry, (z - cz) / rz
	local d = sqrt(dx * dx + dy * dy + dz * dz)
	return 1 - smoothstep(1 - (soft or 0.5), 1, d)
end

-- soft half-space mask: 0 behind the plane through (px,py,pz) with normal n, 1 at `width` in front
function MeshKit.PlaneMask(x, y, z, px, py, pz, nx, ny, nz, width)
	local d = (x - px) * nx + (y - py) * ny + (z - pz) * nz
	return smoothstep(0, width or 0.1, d)
end

-- concavity per vertex (welded): > 0 in creases / valleys (muscle separations), < 0 on ridges;
-- scaled by the mean edge length so it is resolution independent. Returns an array (1..nv).
function MeshKit.Cavity(m, scale)
	local canon, nbr = topology(m)
	local P, N = m.P, m.N
	local out = table.create(m.nv, 0)
	local cache = {}
	for i = 1, m.nv do
		local c = canon[i]
		local v = cache[c]
		if v == nil then
			local l = nbr[c]
			v = 0
			if l and #l > 0 then
				local sx, sy, sz, el = 0, 0, 0, 0
				local x, y, z = P[c * 3 - 2], P[c * 3 - 1], P[c * 3]
				for _, j in ipairs(l) do
					local jx, jy, jz = P[j * 3 - 2], P[j * 3 - 1], P[j * 3]
					sx += jx
					sy += jy
					sz += jz
					el += sqrt((jx - x) ^ 2 + (jy - y) ^ 2 + (jz - z) ^ 2)
				end
				local n = #l
				el /= n
				if el > 1e-9 then
					local lx, ly, lz = sx / n - x, sy / n - y, sz / n - z
					-- neighbours' centroid outside along the normal = the vertex sits in a dip
					v = dot(lx, ly, lz, N[c * 3 - 2], N[c * 3 - 1], N[c * 3]) / el * (scale or 4)
				end
			end
			v = clamp(v, -1, 1)
			cache[c] = v
		end
		out[i] = v
		step(0.5)
	end
	return out
end

-- bake ambient occlusion into the vertex colours. opts:
--   cavity (strength, default 0.35): darken creases (Cavity), ridge (default 0.08): lighten ridges
--   down (default 0.12): darken faces looking down (under the pecs, jaw, glutes)
--   occluders = { {x, y, z, r}, ... } spheres (arms against the ribs, chin over the neck), occStrength
--   tint = {r, g, b}: the colour creases fall toward (default a warm dark: skin AO reads reddish)
function MeshKit.BakeAO(m, opts)
	opts = opts or {}
	local cav = opts.cavityValues or MeshKit.Cavity(m, opts.cavityScale)
	local kc, kr, kd = opts.cavity or 0.35, opts.ridge or 0.08, opts.down or 0.12
	local occ = opts.occluders
	local ko = opts.occStrength or 0.5
	local tint = opts.tint or { 0.35, 0.18, 0.14 }
	local P, N, C = m.P, m.N, m.C
	for i = 1, m.nv do
		local i3 = i * 3
		local cv = cav[i]
		local dark = kc * max(0, cv) + kd * max(0, -N[i3 - 1])
		if occ then
			local x, y, z = P[i3 - 2], P[i3 - 1], P[i3]
			local nx, ny, nz = N[i3 - 2], N[i3 - 1], N[i3]
			local o = 0
			for _, s in ipairs(occ) do
				local vx, vy, vz = s[1] - x, s[2] - y, s[3] - z
				local d = sqrt(vx * vx + vy * vy + vz * vz)
				if d > 1e-6 then
					local r = s[4]
					local cosv = (vx * nx + vy * ny + vz * nz) / d
					if cosv > 0 then
						-- solid angle of a sphere ~ (r / d)^2, weighted by how much the normal faces it
						o += min(1, (r * r) / max(d * d, r * r)) * cosv
					end
				end
			end
			dark += ko * min(o, 1)
		end
		dark = clamp(dark, 0, 0.85)
		local light = kr * max(0, -cv)
		local r, g, b = C[i3 - 2], C[i3 - 1], C[i3]
		-- darken toward a tinted shadow colour (multiplied with the base, so it stays the skin's hue)
		r = lerp(r, r * tint[1] * 2, dark)
		g = lerp(g, g * tint[2] * 2, dark)
		b = lerp(b, b * tint[3] * 2, dark)
		C[i3 - 2], C[i3 - 1], C[i3] = min(1, r + light * (1 - r)), min(1, g + light * (1 - g)), min(1, b + light * (1 - b))
		step(0.5)
	end
	return cav
end

-- multiply colours by (1 + amp * noise) for skin mottling / hair variation (freq in cycles per stud)
function MeshKit.NoiseColor(m, amp, freq, seed, first, last)
	local P, C = m.P, m.C
	for i = first or 1, last or m.nv do
		local i3 = i * 3
		local k = 1 + amp * noise3(P[i3 - 2] * freq, P[i3 - 1] * freq, P[i3] * freq, seed or 0)
		C[i3 - 2] = clamp(C[i3 - 2] * k, 0, 1)
		C[i3 - 1] = clamp(C[i3 - 1] * k, 0, 1)
		C[i3] = clamp(C[i3] * k, 0, 1)
	end
end

-- displace vertices along their normals by fn(i, x, y, z, nx, ny, nz) studs (normals not recomputed)
function MeshKit.Displace(m, fn, first, last)
	local P, N = m.P, m.N
	for i = first or 1, last or m.nv do
		local i3 = i * 3
		local nx, ny, nz = N[i3 - 2], N[i3 - 1], N[i3]
		local d = fn(i, P[i3 - 2], P[i3 - 1], P[i3], nx, ny, nz)
		if d and d ~= 0 then
			P[i3 - 2] += nx * d
			P[i3 - 1] += ny * d
			P[i3] += nz * d
		end
		step(0.3)
	end
end

-- free deformation fn(i, x, y, z) -> x, y, z
function MeshKit.Deform(m, fn, first, last)
	local P = m.P
	for i = first or 1, last or m.nv do
		local i3 = i * 3
		local x, y, z = fn(i, P[i3 - 2], P[i3 - 1], P[i3])
		if x then
			P[i3 - 2], P[i3 - 1], P[i3] = x, y, z
		end
		step(0.3)
	end
end

-- UVs by projection: "sphere" (around cx,cy,cz: u = longitude, v = latitude from the top),
-- "cylinder" (around the Y axis through cx, cz: u = angle, v = height between y0 and y1),
-- "planar" (u = x, v = -y mapped from the bounds)
function MeshKit.ProjectUV(m, mode, cx, cy, cz, y0, y1)
	local P, U = m.P, m.U
	local bx0, by0, _, bx1, by1 = MeshKit.Bounds(m)
	cx, cy, cz = cx or 0, cy or 0, cz or 0
	for i = 1, m.nv do
		local x, y, z = P[i * 3 - 2] - cx, P[i * 3 - 1] - cy, P[i * 3] - cz
		local u, v
		if mode == "sphere" then
			local r = sqrt(x * x + y * y + z * z)
			u = (atan2(-z, x) / TAU) % 1
			v = r > 1e-9 and math.acos(clamp(y / r, -1, 1)) / pi or 0
		elseif mode == "cylinder" then
			u = (atan2(-z, x) / TAU) % 1
			v = 1 - clamp((P[i * 3 - 1] - (y0 or by0)) / max(1e-9, (y1 or by1) - (y0 or by0)), 0, 1)
		else
			u = clamp((P[i * 3 - 2] - bx0) / max(1e-9, bx1 - bx0), 0, 1)
			v = 1 - clamp((P[i * 3 - 1] - by0) / max(1e-9, by1 - by0), 0, 1)
		end
		U[i * 2 - 1], U[i * 2] = u, v
	end
end

------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------
-- returns ok, report { nv, nt, nan, badIndex, degenerate, badNormal, overLimit, msg }
function MeshKit.Validate(m, limits)
	limits = limits or MeshKit.LIMITS
	local rep = { nv = m.nv, nt = m.nt, nan = 0, badIndex = 0, degenerate = 0, badNormal = 0, overLimit = false }
	for i = 1, m.nv * 3 do
		local v = m.P[i]
		if v ~= v or v == math.huge or v == -math.huge or m.N[i] ~= m.N[i] or m.C[i] ~= m.C[i] then
			rep.nan += 1
		end
	end
	for i = 1, m.nv * 2 do
		if m.U[i] ~= m.U[i] then
			rep.nan += 1
		end
	end
	for i = 1, m.nv do
		local x, y, z = m.N[i * 3 - 2], m.N[i * 3 - 1], m.N[i * 3]
		local l = sqrt(x * x + y * y + z * z)
		if abs(l - 1) > 1e-3 then
			rep.badNormal += 1
		end
	end
	local P = m.P
	for t = 1, m.nt do
		local a, b, c = m.T[t * 3 - 2], m.T[t * 3 - 1], m.T[t * 3]
		if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" or a < 1 or b < 1 or c < 1 or a > m.nv or b > m.nv or c > m.nv
			or a % 1 ~= 0 or b % 1 ~= 0 or c % 1 ~= 0 then
			rep.badIndex += 1
		elseif a == b or b == c or a == c then
			rep.degenerate += 1
		else
			local nx, ny, nz = cross(P[b * 3 - 2] - P[a * 3 - 2], P[b * 3 - 1] - P[a * 3 - 1], P[b * 3] - P[a * 3],
				P[c * 3 - 2] - P[a * 3 - 2], P[c * 3 - 1] - P[a * 3 - 1], P[c * 3] - P[a * 3])
			if nx * nx + ny * ny + nz * nz < 1e-20 then
				rep.degenerate += 1
			end
		end
	end
	rep.overLimit = m.nv > limits.verts or m.nt > limits.tris
	local ok = rep.nan == 0 and rep.badIndex == 0 and rep.badNormal == 0 and not rep.overLimit and m.nt > 0
	rep.msg = string.format("nv=%d nt=%d nan=%d badIndex=%d degenerate=%d badNormal=%d overLimit=%s", m.nv, m.nt, rep.nan, rep.badIndex,
		rep.degenerate, rep.badNormal, tostring(rep.overLimit))
	return ok, rep
end

------------------------------------------------------------------------
-- Texture: rasterise the vertex colours (and a shader) into UV space
------------------------------------------------------------------------
-- returns an RGBA8 buffer (w * h * 4) for EditableImage:WritePixelsBuffer. shade (optional):
-- fn(u, v, r, g, b, a, x, y, z, nx, ny, nz) -> r, g, b, a (0..1) for per-texel detail (pores, AO,
-- veins). opts: pad (texels of edge dilation against seam bleeding, default 2), background {r,g,b,a}.
-- Needs the Luau buffer library (Roblox, luaurun).
function MeshKit.RasterizeUV(m, w, h, shade, opts)
	opts = opts or {}
	local buf = buffer.create(w * h * 4)
	local filled = table.create(w * h, false)
	local P, N, U, C, A, T = m.P, m.N, m.U, m.C, m.A, m.T
	local bg = opts.background or { 0, 0, 0, 0 }
	local function put(px, py, r, g, b, a)
		local o = (py * w + px) * 4
		buffer.writeu8(buf, o, floor(clamp(r, 0, 1) * 255 + 0.5))
		buffer.writeu8(buf, o + 1, floor(clamp(g, 0, 1) * 255 + 0.5))
		buffer.writeu8(buf, o + 2, floor(clamp(b, 0, 1) * 255 + 0.5))
		buffer.writeu8(buf, o + 3, floor(clamp(a, 0, 1) * 255 + 0.5))
		filled[py * w + px + 1] = true
	end
	for px = 0, w * h - 1 do
		local o = px * 4
		buffer.writeu8(buf, o, floor(bg[1] * 255))
		buffer.writeu8(buf, o + 1, floor(bg[2] * 255))
		buffer.writeu8(buf, o + 2, floor(bg[3] * 255))
		buffer.writeu8(buf, o + 3, floor((bg[4] or 0) * 255))
	end
	for t = 1, m.nt do
		local ia, ib, ic = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		local ax, ay = U[ia * 2 - 1] * w - 0.5, U[ia * 2] * h - 0.5
		local bx, by = U[ib * 2 - 1] * w - 0.5, U[ib * 2] * h - 0.5
		local cx, cy = U[ic * 2 - 1] * w - 0.5, U[ic * 2] * h - 0.5
		local area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
		if abs(area) > 1e-9 then
			local x0, x1 = max(0, floor(min(ax, bx, cx))), min(w - 1, math.ceil(max(ax, bx, cx)))
			local y0, y1 = max(0, floor(min(ay, by, cy))), min(h - 1, math.ceil(max(ay, by, cy)))
			for py = y0, y1 do
				for px = x0, x1 do
					-- barycentric weights of the texel centre
					local w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area
					local w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area
					local w2 = 1 - w0 - w1
					if w0 >= -1e-6 and w1 >= -1e-6 and w2 >= -1e-6 then
						local a3, b3, c3 = ia * 3, ib * 3, ic * 3
						local r = C[a3 - 2] * w0 + C[b3 - 2] * w1 + C[c3 - 2] * w2
						local g = C[a3 - 1] * w0 + C[b3 - 1] * w1 + C[c3 - 1] * w2
						local b = C[a3] * w0 + C[b3] * w1 + C[c3] * w2
						local a = A and (A[ia] * w0 + A[ib] * w1 + A[ic] * w2) or 1
						if shade then
							r, g, b, a = shade((px + 0.5) / w, (py + 0.5) / h, r, g, b, a,
								P[a3 - 2] * w0 + P[b3 - 2] * w1 + P[c3 - 2] * w2, P[a3 - 1] * w0 + P[b3 - 1] * w1 + P[c3 - 1] * w2,
								P[a3] * w0 + P[b3] * w1 + P[c3] * w2, N[a3 - 2] * w0 + N[b3 - 2] * w1 + N[c3 - 2] * w2,
								N[a3 - 1] * w0 + N[b3 - 1] * w1 + N[c3 - 1] * w2, N[a3] * w0 + N[b3] * w1 + N[c3] * w2)
						end
						put(px, py, r, g, b, a or 1)
					end
				end
			end
		end
		step(2)
	end
	-- dilate filled texels into empty neighbours (mip / filtering bleed at UV seams)
	for _ = 1, opts.pad or 2 do
		local add = {}
		for py = 0, h - 1 do
			for px = 0, w - 1 do
				if not filled[py * w + px + 1] then
					for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
						local qx, qy = px + d[1], py + d[2]
						if qx >= 0 and qx < w and qy >= 0 and qy < h and filled[qy * w + qx + 1] then
							add[#add + 1] = { px, py, (qy * w + qx) * 4 }
							break
						end
					end
				end
			end
			step(w * 0.05)
		end
		for _, a in ipairs(add) do
			local o, src = (a[2] * w + a[1]) * 4, a[3]
			buffer.writeu32(buf, o, buffer.readu32(buf, src))
			filled[a[2] * w + a[1] + 1] = true
		end
	end
	return buf
end

------------------------------------------------------------------------
-- Output
------------------------------------------------------------------------
local function round(x, q)
	return floor(x * q + 0.5) / q
end

-- plain table for the offline renderer / JSON (positions 1e-4, normals / colours 1e-3)
function MeshKit.Export(m)
	local out = { name = m.name, nv = m.nv, nt = m.nt, p = table.create(m.nv * 3), n = table.create(m.nv * 3),
		uv = table.create(m.nv * 2), c = table.create(m.nv * 3), t = table.create(m.nt * 3) }
	for i = 1, m.nv * 3 do
		out.p[i] = round(m.P[i], 10000)
		out.n[i] = round(m.N[i], 1000)
		out.c[i] = round(m.C[i], 1000)
	end
	for i = 1, m.nv * 2 do
		out.uv[i] = round(m.U[i], 10000)
	end
	for i = 1, m.nt * 3 do
		out.t[i] = m.T[i]
	end
	if m.A then
		out.a = table.create(m.nv)
		for i = 1, m.nv do
			out.a[i] = round(m.A[i] or 1, 1000)
		end
	end
	out.landmarks = {}
	for k, p in pairs(m.landmarks) do
		out.landmarks[k] = { round(p[1], 10000), round(p[2], 10000), round(p[3], 10000) }
	end
	out.groups = {}
	for k, g in pairs(m.groups) do
		out.groups[k] = #g
	end
	return out
end

-- Write mesh data into a new EditableMesh. Returns em, info { vid, nid, uid, cid, fid } or nil, err.
-- opts: assetService (default game:GetService("AssetService")), options (CreateEditableMesh options),
-- noColors, noUVs, flipV (v -> 1 - v if textures show upside down). Never throws: every API call is
-- inside a pcall and a half-written mesh is destroyed. Calls MeshKit.Step (installed tick) as it goes.
function MeshKit.ToEditableMesh(m, opts)
	opts = opts or {}
	if m.nv == 0 or m.nt == 0 then
		return nil, "empty mesh"
	end
	if m.nv > MeshKit.LIMITS.verts or m.nt > MeshKit.LIMITS.tris then
		return nil, string.format("mesh over the EditableMesh limits (%d verts, %d tris)", m.nv, m.nt)
	end
	local okSvc, svc = pcall(function()
		return opts.assetService or game:GetService("AssetService")
	end)
	if not okSvc or not svc then
		return nil, "AssetService unavailable"
	end
	local okNew, em = pcall(svc.CreateEditableMesh, svc, opts.options)
	if not okNew then
		return nil, "CreateEditableMesh failed: " .. tostring(em)
	end
	if em == nil then
		return nil, "CreateEditableMesh returned nil (memory budget?)"
	end
	local info = { vid = table.create(m.nv), nid = table.create(m.nv), uid = nil, cid = nil, fid = table.create(m.nt) }
	local ok, err = pcall(function()
		local V3, V2, C3 = Vector3.new, Vector2.new, Color3.new
		local P, N, U, C, A, T = m.P, m.N, m.U, m.C, m.A, m.T
		local vid, nid = info.vid, info.nid
		local uid = not opts.noUVs and table.create(m.nv) or nil
		local cid = not opts.noColors and table.create(m.nv) or nil
		info.uid, info.cid = uid, cid
		local flipV = opts.flipV
		for i = 1, m.nv do
			local i3 = i * 3
			vid[i] = em:AddVertex(V3(P[i3 - 2], P[i3 - 1], P[i3]))
			local nx, ny, nz = N[i3 - 2], N[i3 - 1], N[i3]
			if nx == 0 and ny == 0 and nz == 0 then
				nid[i] = em:AddNormal() -- computed by the engine
			else
				nid[i] = em:AddNormal(V3(nx, ny, nz))
			end
			if uid then
				local v = U[i * 2]
				uid[i] = em:AddUV(V2(U[i * 2 - 1], flipV and 1 - v or v))
			end
			if cid then
				cid[i] = em:AddColor(C3(C[i3 - 2], C[i3 - 1], C[i3]), A and A[i] or 1)
			end
			step(1)
		end
		local fid = info.fid
		for t = 1, m.nt do
			local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
			local f = em:AddTriangle(vid[a], vid[b], vid[c])
			fid[t] = f
			em:SetFaceNormals(f, { nid[a], nid[b], nid[c] })
			if uid then
				em:SetFaceUVs(f, { uid[a], uid[b], uid[c] })
			end
			if cid then
				em:SetFaceColors(f, { cid[a], cid[b], cid[c] })
			end
			step(1)
		end
	end)
	if not ok then
		pcall(em.Destroy, em)
		return nil, "EditableMesh write failed: " .. tostring(err)
	end
	return em, info
end

-- move vertices of a written mesh: list = { meshVertexIndex, ... } (nil = all) using m.P (and m.N when
-- withNormals). Returns ok, err.
function MeshKit.UpdatePositions(em, info, m, list, withNormals)
	return pcall(function()
		local V3 = Vector3.new
		local P, N = m.P, m.N
		local vid, nid = info.vid, info.nid
		local n = list and #list or m.nv
		for k = 1, n do
			local i = list and list[k] or k
			local i3 = i * 3
			em:SetPosition(vid[i], V3(P[i3 - 2], P[i3 - 1], P[i3]))
			if withNormals then
				em:SetNormal(nid[i], V3(N[i3 - 2], N[i3 - 1], N[i3]))
			end
		end
	end)
end

-- EditableImage from an RGBA8 buffer (RasterizeUV). Returns img or nil, err.
function MeshKit.ToEditableImage(w, h, buf, opts)
	opts = opts or {}
	local okSvc, svc = pcall(function()
		return opts.assetService or game:GetService("AssetService")
	end)
	if not okSvc or not svc then
		return nil, "AssetService unavailable"
	end
	local ok, img = pcall(svc.CreateEditableImage, svc, { Size = Vector2.new(w, h) })
	if not ok then
		return nil, "CreateEditableImage failed: " .. tostring(img)
	end
	if img == nil then
		return nil, "CreateEditableImage returned nil (memory budget?)"
	end
	local okW, err = pcall(function()
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), buf)
	end)
	if not okW then
		pcall(img.Destroy, img)
		return nil, "WritePixelsBuffer failed: " .. tostring(err)
	end
	return img
end

return MeshKit
