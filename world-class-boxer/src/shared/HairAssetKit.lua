-- HairAssetKit: the pure half of the asset hair (tools/hair/CONTRACT.md; the client's HairAssets does the
-- engine half). No Instances, deterministic, so lune tests run it as the client does.
-- * Select(data, look): the HairAssetData entry a look draws (AnatomyHair's own style / type routing:
--   Gen.Resolve), nil for Bald, an unknown look or an entry with an id still missing (Usable)
-- * Fit(S, fit0): the per-boxer skull fit (W, T, Fz, Bz from the skull field, against the default male's)
-- * LengthFactor / VolumeFactor(look): the per-style length / volume stretch
-- * Place(data, entry, look, S): every piece's affine map nominal -> Head space (diagonal scale + offset),
--   its MeshPart size and weld centre, its HairFX pivot / tip and point cloud, and the cap's
-- * CapCoverage(look, lod, capSpec, S): the coverage the cap's alpha takes (the style's own Kit.Cut, or a
--   natural hairline); CapGrid + PaintCap paint the cap texture from it
-- * Colors / Tint / ColorKey: the greyscale card textures tinted by the look's palette (Kit.Palette's rules:
--   darker roots, lighter tips, dye along v, streaks and highlights on u bands, age greying)
-- Heavy loops call MeshKit.Step (the builder's tick yields there: time-sliced, cancellable).
local Shared = script.Parent
local MeshKit = require(Shared:WaitForChild("MeshKit"))
local Kit = require(Shared:WaitForChild("AnatomyHairKit"))
local Gen = require(Shared:WaitForChild("AnatomyHair"))

local HK = {}

local abs, floor, min, max, sin, cos, pi = math.abs, math.floor, math.min, math.max, math.sin, math.cos, math.pi
local TAU = pi * 2
local clamp, lerp, num = Kit.clamp, Kit.lerp, Kit.num
local step = MeshKit.Step
local readu8, writeu8, writeu32 = buffer.readu8, buffer.writeu8, buffer.writeu32

-- the default male skull's extents (skull.json fit0): the meshes are modelled on it
HK.FIT0 = { W = 0.383, T = 0.591, Fz = -0.460, Bz = 0.520 }
-- textures drawn as one flat colour (tileable: no root or tip along v) even when the data does not say so
local FLAT = { short = true, braid = true, cornrow = true }
-- u bands a card texture's strands are coloured by (streaks, highlights, the per-lock variation): 3 per strip
HK.BANDS = 12

------------------------------------------------------------------------
-- Entry selection
------------------------------------------------------------------------
local function idOf(v)
	local n = tonumber(v)
	return (n and n > 0) and floor(n) or nil
end
HK.Id = idOf

local function listHas(list, v)
	if type(list) ~= "table" then
		return false
	end
	for _, x in ipairs(list) do
		if x == v then
			return true
		end
	end
	return false
end

-- the texture keys an entry needs (its pieces' and, with a cap, "short")
function HK.TexturesOf(data, entry)
	local out = {}
	for _, p in pairs(type(entry.pieces) == "table" and entry.pieces or {}) do
		if type(p.tex) == "string" then
			out[p.tex] = true
		end
	end
	if HK.HasCap(entry) then
		out.short = true
	end
	return out
end

function HK.HasCap(entry)
	local c = entry.cap
	return type(c) == "table" and (c.cut == "style" or c.cut == "full")
end

-- every mesh and texture id the entry needs is uploaded; the entry draws something (pieces or a cap)
function HK.Usable(data, entry)
	if type(data) ~= "table" or type(entry) ~= "table" then
		return false
	end
	local textures = type(data.textures) == "table" and data.textures or {}
	local any = false
	for _, p in pairs(type(entry.pieces) == "table" and entry.pieces or {}) do
		if not idOf(p.mesh) or type(p.bbox) ~= "table" or #p.bbox < 6 then
			return false
		end
		any = true
	end
	if HK.HasCap(entry) then
		local cap = data.cap
		if type(cap) ~= "table" or not idOf(cap.mesh) or type(cap.bbox) ~= "table" or #cap.bbox < 6 then
			return false
		end
		any = true
	end
	for key in pairs(HK.TexturesOf(data, entry)) do
		local t = textures[key]
		if type(t) ~= "table" or not idOf(t.id) then
			return false
		end
	end
	return any
end

-- the entry the look draws, or nil: style / type as AnatomyHair routes them (a curly Long Hair is AnatomyHair's
-- longCurly recipe: only an entry listing that type takes it), Bald never. skip(entry) -> true leaves an entry
-- out (its asset failed to load)
function HK.Select(data, look, skip)
	if type(data) ~= "table" or type(data.entries) ~= "table" then
		return nil
	end
	look = type(look) == "table" and look or {}
	local style, htype = Gen.Resolve(look)
	if style == "Bald" then
		return nil
	end
	local raw = type(look.hair) == "table" and look.hair.style or nil
	for pass = 1, 2 do
		-- (the recipe's style first; then the look's own id, for an entry written for a style without a recipe)
		local want = pass == 1 and style or raw
		if want and (pass == 1 or want ~= style) then
			for _, e in ipairs(data.entries) do
				if type(e) == "table" and listHas(e.styles, want) and (e.types == nil or listHas(e.types, htype)) then
					if HK.Usable(data, e) and not (skip and skip(e)) then
						return e, style, htype
					end
				end
			end
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Skull fit
------------------------------------------------------------------------
-- distance from (ox, oy, oz) along a unit direction to the field's zero set (bisection: the origin is inside)
local function crossing(f, ox, oy, oz, dx, dy, dz)
	local lo, hi = 0, 1.6
	if f(ox, oy, oz) >= 0 then
		return 0
	end
	for _ = 1, 40 do
		local m = (lo + hi) * 0.5
		if f(ox + dx * m, oy + dy * m, oz + dz * m) < 0 then
			lo = m
		else
			hi = m
		end
	end
	return (lo + hi) * 0.5
end

-- the boxer's skull against the default male's (CONTRACT: W at y 0.15 toward +X, T straight up from the skull
-- centre, Fz at y 0.2 toward -Z, Bz at y 0.1 toward +Z): ax = W / W0, ay = T / T0 (about y = 0), az = the front
-- to back span's ratio, dz = the shift of its middle
function HK.Measure(S)
	local f, cz = S.f, S.cz or 0.035
	local W = crossing(f, 0, 0.15, cz, 1, 0, 0)
	local T = (S.cy or 0.15) + crossing(f, 0, S.cy or 0.15, cz, 0, 1, 0)
	local Fz = cz - crossing(f, 0, 0.2, cz, 0, 0, -1)
	local Bz = cz + crossing(f, 0, 0.1, cz, 0, 0, 1)
	return W, T, Fz, Bz
end

function HK.Fit(S, fit0)
	fit0 = type(fit0) == "table" and fit0 or HK.FIT0
	local W0, T0 = num(fit0.W, HK.FIT0.W), num(fit0.T, HK.FIT0.T)
	local F0, B0 = num(fit0.Fz, HK.FIT0.Fz), num(fit0.Bz, HK.FIT0.Bz)
	local W, T, Fz, Bz = HK.Measure(S)
	return {
		W = W, T = T, Fz = Fz, Bz = Bz,
		ax = W / W0, ay = T / T0, az = (Bz - Fz) / (B0 - F0), dz = (Bz + Fz) / 2 - (B0 + F0) / 2,
	}
end

------------------------------------------------------------------------
-- Length and volume
------------------------------------------------------------------------
-- AnatomyHair's effective length (H.len: the cut's length plus 0.6 x what grew since), 0..1.5
function HK.Len(look)
	local hair = type(look) == "table" and type(look.hair) == "table" and look.hair or {}
	return clamp(clamp(num(hair.length, 0.5), 0, 1) + clamp(num(hair.growth, 0), 0, 1.5) * 0.6, 0, 1.5)
end

-- hanging hair's stretch along y: 1 at the default length (0.5), 0.6 cropped short .. 1.45 at the longest
function HK.LengthFactor(look)
	return clamp(0.6 + 0.8 * HK.Len(look), 0.6, 1.45)
end

-- a volume's (afro, high top) scale about the skull centre: the volume slider and the length
function HK.VolumeFactor(look)
	local hair = type(look) == "table" and type(look.hair) == "table" and look.hair or {}
	local vol = clamp(num(hair.volume, 0), -1, 1)
	return clamp(1 + 0.18 * vol + 0.25 * (HK.Len(look) - 0.5), 0.8, 1.3)
end

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------
-- an affine map with a diagonal matrix: p' = s * p + o (per axis)
local function xf(sx, sy, sz, ox, oy, oz)
	return { sx, sy, sz, ox, oy, oz }
end
function HK.Apply(m, x, y, z)
	return m[1] * x + m[4], m[2] * y + m[5], m[3] * z + m[6]
end
-- y -> c + (y - c) * k after m
local function stretchY(m, c, k)
	return xf(m[1], m[2] * k, m[3], m[4], c + (m[5] - c) * k, m[6])
end
-- p -> C + (p - C) * k after m
local function scaleAbout(m, cx, cy, cz, k)
	return xf(m[1] * k, m[2] * k, m[3] * k, cx + (m[4] - cx) * k, cy + (m[5] - cy) * k, cz + (m[6] - cz) * k)
end
-- then nominal -> real (the head's size per axis)
local function toReal(m, kx, ky, kz)
	return xf(m[1] * kx, m[2] * ky, m[3] * kz, m[4] * kx, m[5] * ky, m[6] * kz)
end

-- the lowest a hanging chain may reach after its stretch (nominal y): the torso box's middle (mid-back)
local function hangFloor(S)
	local t = S.torso
	return type(t) == "table" and num(t[2], -1.8) or -1.8
end

-- one piece's placement from its nominal data and its map m (nominal -> real)
local function placeOf(name, ap, m)
	local b = ap.bbox
	local cx, cy, cz = HK.Apply(m, b[1], b[2], b[3])
	local out = {
		name = name, map = m, centre = { cx, cy, cz }, size = { abs(m[1] * b[4]), abs(m[2] * b[5]), abs(m[3] * b[6]) },
		bounds = { cx - abs(m[1] * b[4]) / 2, cy - abs(m[2] * b[5]) / 2, cz - abs(m[3] * b[6]) / 2,
			cx + abs(m[1] * b[4]) / 2, cy + abs(m[2] * b[5]) / 2, cz + abs(m[3] * b[6]) / 2 },
	}
	-- the point cloud HairFX samples (head space, as a generated piece's vertices)
	local pts = type(ap.points) == "table" and ap.points or {}
	local P = table.create(#pts)
	for i = 1, #pts - 2, 3 do
		local x, y, z = HK.Apply(m, pts[i], pts[i + 1], pts[i + 2])
		P[i], P[i + 1], P[i + 2] = x, y, z
	end
	if #P == 0 then
		-- no cloud exported: the box's corners and centre (enough for the samples HairFX takes)
		local x0, y0, z0, x1, y1, z1 = table.unpack(out.bounds)
		for _, c in ipairs({ { x0, y0, z0 }, { x1, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, { x0, y0, z1 }, { x1, y0, z1 },
			{ x0, y1, z1 }, { x1, y1, z1 }, { cx, cy, cz } }) do
			P[#P + 1], P[#P + 2], P[#P + 3] = c[1], c[2], c[3]
		end
	end
	out.P, out.nv = P, #P // 3
	local fx = ap.hairfx
	if type(fx) == "table" and type(fx.pivot) == "table" then
		local tip = type(fx.tip) == "table" and fx.tip or { fx.pivot[1], fx.pivot[2] - 0.3, fx.pivot[3] }
		local px, py, pz = HK.Apply(m, fx.pivot[1], fx.pivot[2], fx.pivot[3])
		local tx, ty, tz = HK.Apply(m, tip[1], tip[2], tip[3])
		out.hairfx = {
			kind = fx.kind == "bounce" and "bounce" or "swing", chain = fx.chain, seg = fx.seg, parent = fx.parent,
			stiff = fx.stiff, mass = fx.mass, pivot = { px, py, pz }, tip = { tx, ty, tz },
		}
		out.landmarks = { [name .. ".0"] = { px, py, pz }, [name .. ".1"] = { tx, ty, tz } }
	end
	return out
end

-- every piece's placement for this boxer: { [name] = { map, centre, size, bounds, P, nv, hairfx, landmarks } }
-- (the cap as "HairCap" when the entry has one), plus the fit, the length and the volume factors used
function HK.Place(data, entry, look, S, fit)
	fit = fit or HK.Fit(S, data.fit0)
	local kx, ky, kz = num(S.kx, 1), num(S.ky, 1), num(S.kz, 1)
	local base = xf(fit.ax, fit.ay, fit.az, 0, 0, fit.dz)
	local Lf, Vf = HK.LengthFactor(look), HK.VolumeFactor(look)
	local pieces = type(entry.pieces) == "table" and entry.pieces or {}
	-- hanging chains stretch as one about their root's pivot (a lower segment about its own would tear open at
	-- the joint), each no lower than the floor
	local function rootOf(name)
		local seen = 0
		local cur = name
		while seen < 8 do
			local fx = pieces[cur] and pieces[cur].hairfx
			local parent = type(fx) == "table" and fx.parent or nil
			if not (parent and pieces[parent]) then
				break
			end
			cur, seen = parent, seen + 1
		end
		return cur
	end
	local chains = {}
	for name, ap in pairs(pieces) do
		if ap.length == "hang" then
			local root = rootOf(name)
			local ch = chains[root]
			if not ch then
				local rp = pieces[root]
				local fx = rp.hairfx
				local ay = type(fx) == "table" and type(fx.pivot) == "table" and fx.pivot[2] or (rp.bbox[2] + rp.bbox[5] / 2)
				ch = { anchor = ay * fit.ay, bottom = math.huge }
				chains[root] = ch
			end
			ch.bottom = min(ch.bottom, (ap.bbox[2] - ap.bbox[5] / 2) * fit.ay)
		end
	end
	local yFloor = hangFloor(S)
	for _, ch in pairs(chains) do
		local k = Lf
		if k > 1 and ch.bottom < ch.anchor then
			k = max(1, min(k, (ch.anchor - yFloor) / (ch.anchor - ch.bottom)))
		end
		ch.k = k
	end
	local out = {}
	for name, ap in pairs(pieces) do
		local m = base
		if ap.length == "hang" then
			local ch = chains[rootOf(name)]
			m = stretchY(m, ch.anchor, ch.k)
		elseif ap.length == "volume" then
			m = scaleAbout(m, 0, num(S.cy, 0.15), num(S.cz, 0.035), Vf)
		end
		out[name] = placeOf(name, ap, toReal(m, kx, ky, kz))
	end
	if HK.HasCap(entry) and type(data.cap) == "table" then
		out.HairCap = placeOf("HairCap", data.cap, toReal(base, kx, ky, kz))
	end
	return out, fit, Lf, Vf
end

------------------------------------------------------------------------
-- The cap's coverage
------------------------------------------------------------------------
-- cov(x, y, z) -> 0..1 at a nominal scalp point of THIS boxer's skull: the style's own cut (the coverage the
-- generated HairCap draws: fades, hairline type, line-up, growth) for cut "style", else a natural hairline at
-- the entry's density ("full"). Also returns the scalp S and whether the edge is sharp (a line-up)
function HK.CapCoverage(look, lod, capSpec, S)
	look = type(look) == "table" and look or {}
	local hair = type(look.hair) == "table" and look.hair or {}
	local density = clamp(num(capSpec and capSpec.density, 1), 0, 1)
	local cut, S2
	if capSpec and capSpec.cut == "style" then
		cut, S2 = Gen.CapCut(look, lod)
	end
	S = S2 or S or Kit.Scalp(look)
	if not cut then
		cut = Kit.Cut(S, { hairline = type(hair.hairline) == "string" and hair.hairline or "Natural",
			growth = clamp(num(hair.growth, 0), 0, 1.5), density = density })
		return cut.cov, S, (cut.soft or 0.016) < 0.006
	end
	local cov = cut.cov
	if density < 1 then
		return function(x, y, z)
			return cov(x, y, z) * density
		end, S, (cut.soft or 0.016) < 0.006
	end
	return cov, S, (cut.soft or 0.016) < 0.006
end

-- the cap's coverage and colour on a gw x gh grid over its UV (texel centres; u = az / 2pi with az = 0 at the
-- back toward +X, v = theta / thetaMax): flat arrays r, g, b, c (index i + j * gw, 0-based i, j)
function HK.CapGrid(S, cov, pal, thetaMax, gw, gh)
	local n = gw * gh
	local R, G, B, C = table.create(n, 0), table.create(n, 0), table.create(n, 0), table.create(n, 0)
	local t0 = 0.5
	for j = 0, gh - 1 do
		local th = (j + 0.5) / gh * thetaMax
		local st, ct = sin(th), cos(th)
		for i = 0, gw - 1 do
			local az = (i + 0.5) / gw * TAU
			local x, y, z, t = S.ray(st * sin(az), ct, st * cos(az), 0, t0)
			t0 = t
			local c = clamp(cov(x, y, z), 0, 1)
			-- (scalp hair is short: the roots' colour; Split by its side, Ombre by its height)
			local r, g, b = pal.at(0.5, 0, x, false, y)
			local k = i + j * gw + 1
			R[k], G[k], B[k], C[k] = r, g, b, c
			step(6)
		end
	end
	return { r = R, g = G, b = B, c = C, w = gw, h = gh }
end

-- the grid's size for a cut: finer for a sharp edge (a line-up's 3 mm reads only on a finer grid)
function HK.GridSize(sharp)
	if sharp then
		return 192, 96
	end
	return 128, 64
end

-- bilinear sample of a flat grid (wraps in u, clamps in v)
local function gridAt(arr, gw, gh, gu, gv)
	gu = gu % gw
	local i0 = floor(gu)
	local fu = gu - i0
	local i1 = (i0 + 1) % gw
	gv = clamp(gv, 0, gh - 1)
	local j0 = floor(gv)
	local fv = gv - j0
	local j1 = min(j0 + 1, gh - 1)
	local a = arr[i0 + j0 * gw + 1] * (1 - fu) + arr[i1 + j0 * gw + 1] * fu
	local b = arr[i0 + j1 * gw + 1] * (1 - fu) + arr[i1 + j1 * gw + 1] * fu
	return a + (b - a) * fv
end
HK.GridAt = gridAt

-- the cap texture (size x size RGBA8): the short tile (tw x th, RGBA8, wraps both ways) repeated nu x nv times,
-- its grey times the grid's colour, alpha = the tile's alpha x the coverage. flipV writes the rows bottom-up
function HK.PaintCap(grid, tile, tw, th, nu, nv, size, flipV, gain)
	gain = gain or 1
	local out = buffer.create(size * size * 4)
	local gw, gh = grid.w, grid.h
	local R, G, B, C = grid.r, grid.g, grid.b, grid.c
	-- per output column (fixed for every row): the grid's columns and weight (wrapping round the head), the
	-- tile's texel columns (byte offsets) and weight
	local gi0, gi1, gfu = table.create(size), table.create(size), table.create(size)
	local tx0s, tx1s, tfx = table.create(size), table.create(size), table.create(size)
	for i = 0, size - 1 do
		local u = (i + 0.5) / size
		local gu = (u * gw - 0.5) % gw
		local i0 = floor(gu)
		gi0[i + 1], gi1[i + 1], gfu[i + 1] = i0 + 1, (i0 + 1) % gw + 1, gu - i0
		local tu = (u * nu * tw - 0.5) % tw
		local t0 = floor(tu)
		tx0s[i + 1], tx1s[i + 1], tfx[i + 1] = t0 * 4, ((t0 + 1) % tw) * 4, tu - t0
	end
	-- one grid row interpolated in v (r, g, b, c over the gw columns), per output row
	local rr, rg, rb, rc = table.create(gw, 0), table.create(gw, 0), table.create(gw, 0), table.create(gw, 0)
	for j = 0, size - 1 do
		local v = (j + 0.5) / size
		local row = flipV and (size - 1 - j) or j
		local gv = clamp(v * gh - 0.5, 0, gh - 1)
		local j0 = floor(gv)
		local fv = gv - j0
		local j1 = min(j0 + 1, gh - 1)
		local b0, b1 = j0 * gw, j1 * gw
		for q = 1, gw do
			rr[q] = R[b0 + q] + (R[b1 + q] - R[b0 + q]) * fv
			rg[q] = G[b0 + q] + (G[b1 + q] - G[b0 + q]) * fv
			rb[q] = B[b0 + q] + (B[b1 + q] - B[b0 + q]) * fv
			rc[q] = C[b0 + q] + (C[b1 + q] - C[b0 + q]) * fv
		end
		local tv = (v * nv * th - 0.5) % th
		local ty0 = floor(tv)
		local fy = tv - ty0
		local ro0, ro1 = ty0 * tw * 4, ((ty0 + 1) % th) * tw * 4
		local o = row * size * 4
		for i = 1, size do
			local q0, q1, fu = gi0[i], gi1[i], gfu[i]
			local c = rc[q0] + (rc[q1] - rc[q0]) * fu
			local r = rr[q0] + (rr[q1] - rr[q0]) * fu
			local g = rg[q0] + (rg[q1] - rg[q0]) * fu
			local b = rb[q0] + (rb[q1] - rb[q0]) * fu
			if c <= 0.002 then
				-- (bare scalp: the head shows; the colour kept so filtering never pulls in black. The palette's
				-- colours are 0..1: no clamp below; RGBA packed little-endian)
				writeu32(out, o, floor(r * 255 + 0.5) + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5) * 65536)
			else
				local x0, x1, fx = tx0s[i], tx1s[i], tfx[i]
				local w00, w10, w01, w11 = (1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy
				local a00, a10, a01, a11 = ro0 + x0, ro0 + x1, ro1 + x0, ro1 + x1
				local grey = (readu8(tile, a00) * w00 + readu8(tile, a10) * w10 + readu8(tile, a01) * w01 + readu8(tile, a11) * w11) * gain
				local al = readu8(tile, a00 + 3) * w00 + readu8(tile, a10 + 3) * w10 + readu8(tile, a01 + 3) * w01 + readu8(tile, a11 + 3) * w11
				writeu32(out, o, min(255, floor(r * grey + 0.5)) + min(255, floor(g * grey + 0.5)) * 256 + min(255, floor(b * grey + 0.5)) * 65536
					+ min(255, floor(al * c + 0.5)) * 16777216)
			end
			o += 4
		end
		step(size // 16)
	end
	return out
end

------------------------------------------------------------------------
-- Tinting the card textures
------------------------------------------------------------------------
-- a band's random value (0..1, stable): which bands carry a streak / highlight, the lock-to-lock variation
local function bandRnd(b)
	local x = sin(b * 12.9898 + 4.1414) * 43758.5453
	return x - floor(x)
end
HK.BandRnd = bandRnd

-- the colour table a texture is tinted with: flat -> one colour { flat, r, g, b } (tileable strips: a mid tone,
-- no root or tip); else { rows, bands, cols[band] = { r, g, b per row } }: root (v = 0) to tip (v = 1) along the rows, a band's own rnd across u. Kit.Palette's
-- pal.at does every rule (darker roots, lighter tips, Tips / Ombre by v, Streaks / highlights on bands, greying);
-- Split cannot follow the head's side on a card: its base colour
function HK.Colors(pal, rows, flat, bands)
	bands = bands or HK.BANDS
	if flat then
		local r, g, b = pal.at(0.5, 0.5, -1)
		return { flat = true, r = r, g = g, b = b }
	end
	local t = { rows = rows, bands = bands, cols = {} }
	for bi = 0, bands - 1 do
		local rnd = bandRnd(bi)
		local col = table.create(rows * 3)
		for j = 0, rows - 1 do
			local r, g, b = pal.at(rnd, (j + 0.5) / rows, -1)
			col[j * 3 + 1], col[j * 3 + 2], col[j * 3 + 3] = r, g, b
		end
		t.cols[bi + 1] = col
		step(rows // 8)
	end
	return t
end

-- src (sw x sh RGBA8) box-filtered down by the integer factor f (1 = as is), times the colours, alpha kept:
-- a new (sw / f) x (sh / f) buffer. The colours' rows run along the texture's own v (its rows as uploaded),
-- flipV writes them bottom-up
function HK.Tint(src, sw, sh, f, colors, flipV, gain)
	f = max(1, floor(f or 1))
	gain = gain or 1
	local w, h = sw // f, sh // f
	local out = buffer.create(w * h * 4)
	local inv = gain / (f * f)
	local flat = colors.flat
	local rows, bands, cols = colors.rows, colors.bands, colors.cols
	-- per column: its band; per row: each band's colour (x gain / box area)
	local bandOf = table.create(w, 1)
	if not flat then
		for i = 0, w - 1 do
			bandOf[i + 1] = min(bands - 1, floor((i + 0.5) / w * bands)) + 1
		end
	end
	local nb = flat and 1 or bands
	local mr, mg, mb = table.create(nb, 0), table.create(nb, 0), table.create(nb, 0)
	if flat then
		mr[1], mg[1], mb[1] = colors.r * inv, colors.g * inv, colors.b * inv
	end
	local ainv = 1 / (f * f)
	for j = 0, h - 1 do
		local orow = flipV and (h - 1 - j) or j
		if not flat then
			local crow = min(rows - 1, floor((j + 0.5) / h * rows)) * 3
			for bi = 1, bands do
				local col = cols[bi]
				mr[bi], mg[bi], mb[bi] = col[crow + 1] * inv, col[crow + 2] * inv, col[crow + 3] * inv
			end
		end
		local o = orow * w * 4
		for i = 1, w do
			local r, g, b, a
			if f == 1 then
				local s0 = (j * sw + i - 1) * 4
				r, g, b, a = readu8(src, s0), readu8(src, s0 + 1), readu8(src, s0 + 2), readu8(src, s0 + 3)
			else
				r, g, b, a = 0, 0, 0, 0
				for dy = 0, f - 1 do
					local s0 = ((j * f + dy) * sw + (i - 1) * f) * 4
					for _ = 1, f do
						r += readu8(src, s0)
						g += readu8(src, s0 + 1)
						b += readu8(src, s0 + 2)
						a += readu8(src, s0 + 3)
						s0 += 4
					end
				end
				a *= ainv
			end
			local bi = bandOf[i]
			writeu32(out, o, min(255, floor(r * mr[bi] + 0.5)) + min(255, floor(g * mg[bi] + 0.5)) * 256 + min(255, floor(b * mb[bi] + 0.5)) * 65536
				+ min(255, floor(a + 0.5)) * 16777216)
			o += 4
		end
		step(w * f * f // 64 + 1)
	end
	return out, w, h
end

function HK.IsFlat(key, tex)
	return (type(tex) == "table" and tex.tile == true) or FLAT[key] == true
end

-- what a tinted texture depends on (two looks with the same key share one image): the palette's inputs
function HK.ColorKey(look, htype)
	local hair = type(look) == "table" and type(look.hair) == "table" and look.hair or {}
	local function c3(c, d)
		if type(c) ~= "table" then
			return d
		end
		return string.format("%d.%d.%d", floor(num(c[1], 0) + 0.5), floor(num(c[2], 0) + 0.5), floor(num(c[3], 0) + 0.5))
	end
	local age = num(look.age, 26)
	local grey = floor(clamp((age - 38) / 40, 0, 0.55) * 40 + 0.5)
	local kind = (htype == "Coiled" or htype == "Kinky") and "c" or (htype == "Curly" and "u" or "s")
	return table.concat({ c3(hair.color, "-"), c3(hair.hcolor, "-"), type(hair.dye) == "string" and hair.dye or "None",
		hair.hl == true and "h" or "", tostring(grey), kind }, "|")
end

-- the palette the tint uses (Kit.Palette, the generated hair's own colours)
function HK.Palette(look, htype)
	return Kit.Palette(type(look) == "table" and look or {}, htype)
end

-- the colour a piece's part shows where its texture does not cover (a mid hair tone)
function HK.MidColor(pal)
	return pal.at(0.5, 0.5, -1)
end

return HK
