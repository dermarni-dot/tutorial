-- AnatomyHairParts: the hair section's components on top of AnatomyHairKit, shared by every style recipe in
-- AnatomyHair: the generation context (look inputs with defaults, level of detail, budget, pieces), the scalp
-- shell (HairCap: fades, stubble, line-ups, partings, waves, cornrow / box partings; a strand texture at
-- full / medium), root sampling over the scalp, strand clumps (static and swinging groups), fine strands and
-- flyaways, curls, coils, coily volumes, locs / braids / twists, cornrows and ponytail tails, and the final
-- assembly (nominal -> head space, joint landmarks, HairFX metadata on each moving piece's mesh).
-- Pure and deterministic like the rest of the section (ANATOMY_CONTRACTS.md section 3).
local Shared = script.Parent
local MeshKit = require(Shared:WaitForChild("MeshKit"))
local Kit = require(Shared:WaitForChild("AnatomyHairKit"))

local Parts = {}

local sqrt, abs, floor, min, max, ceil = math.sqrt, math.abs, math.floor, math.min, math.max, math.ceil
local sin, cos, acos, pi = math.sin, math.cos, math.acos, math.pi
local TAU = pi * 2
local clamp, lerp, smoothstep, norm3, num = Kit.clamp, Kit.lerp, Kit.smoothstep, Kit.norm3, Kit.num
local noise3 = MeshKit.Noise
local step = MeshKit.Step

------------------------------------------------------------------------
-- Level of detail
------------------------------------------------------------------------
-- cap grid, texture size, clump section sides, density factor (share of the full-detail strand count),
-- ring factor (rings per stud), movable groups, fine strands / flyaways
Parts.LOD = {
	full = { cols = 48, rows = 22, tex = 256, sides = 5, k = 1, rings = 1, groups = 7, segs = 2, strands = true, tubeSides = 6 },
	medium = { cols = 32, rows = 13, tex = 128, sides = 4, k = 0.4, rings = 0.62, groups = 3, segs = 1, strands = false, tubeSides = 5 },
	low = { cols = 18, rows = 8, tex = nil, sides = 3, k = 0.12, rings = 0.4, groups = 0, segs = 0, strands = false, tubeSides = 4 },
}
Parts.MAXPIECES = { full = 16, medium = 6, low = 2 }
Parts.BUDGET = { full = 10000, medium = 4000, low = 1200 }

------------------------------------------------------------------------
-- Context
------------------------------------------------------------------------
-- H: everything a style recipe needs. Reads only Hair-section look paths.
function Parts.Context(look, lod, ctx, style, htype)
	local hair = type(look.hair) == "table" and look.hair or {}
	local face = type(look.face) == "table" and look.face or {}
	local L = Parts.LOD[lod] or Parts.LOD.full
	local S = Kit.Scalp(look)
	local growth = clamp(num(hair.growth, 0), 0, 1.5)
	local length = clamp(num(hair.length, 0.5), 0, 1)
	local H = {
		look = look, lod = lod, L = L, S = S, style = style, htype = htype,
		pal = Kit.Palette(look, htype), skin = Kit.Skin(look), out = Kit.Outward(S),
		seed = Kit.Seed(floor(num(face.seed, 7)), style, htype),
		growth = growth, grow = clamp(growth / 0.5, 0, 1),
		len = clamp(length + growth * 0.6, 0, 1.5), -- the cut's length plus what grew since
		density = clamp(num(hair.density, 0.7), 0, 1),
		thick = clamp(num(hair.thickness, 0.5), 0, 1),
		clump = clamp(num(hair.clump, 0.5), 0, 1),
		frizz = clamp(num(hair.frizz, 0.3), 0, 1),
		volume = clamp(num(hair.volume, 0), -1, 1),
		curl = clamp(num(hair.curlSize, 0), -1, 1),
		hairline = type(hair.hairline) == "string" and hair.hairline or "Natural",
		part = type(hair.part) == "string" and hair.part or "None",
		female = look.g == 2,
		budget = (type(ctx) == "table" and tonumber(ctx.budget)) or Parts.BUDGET[lod] or 10000,
		pieces = {}, order = {}, groups = {}, landmarks = {},
	}
	H.rng = MeshKit.Rng(H.seed)
	-- a parting's x on the scalp (nominal), nil for none
	if H.part == "Left" then
		H.partX = -0.12
	elseif H.part == "Right" then
		H.partX = 0.12
	elseif H.part == "Middle" then
		H.partX = 0
	end
	return H
end

-- a piece (created on first use): props = { material, doubleSided, castShadow, hideUnder, reflectance }
function Parts.Piece(H, name, props)
	local p = H.pieces[name]
	if not p then
		p = { mesh = MeshKit.New(name), attach = "Head" }
		if props then
			for k, v in pairs(props) do
				p[k] = v
			end
		end
		H.pieces[name] = p
		H.order[#H.order + 1] = name
	end
	return p
end

function Parts.Tris(H)
	local n = 0
	for _, p in pairs(H.pieces) do
		n += p.mesh.nt
	end
	return n
end

-- the material hair of a type reads as: straight / wavy keep a soft sheen, curls and coils are matte
function Parts.Material(htype)
	if htype == "Straight" or htype == "Wavy" then
		return "SmoothPlastic"
	end
	return "Plastic"
end

------------------------------------------------------------------------
-- The scalp shell
------------------------------------------------------------------------
-- texture shader for the cap: strands running along the comb flow, the scalp showing through where the
-- coverage is partial (fades, buzz cuts, partings, the hairline edge), plus the cut's pattern
local function capShader(H, spec)
	local S, cut, pal, sk = H.S, H.cut, H.pal, H.skin
	local kx, ky, kz = S.kx, S.ky, S.kz
	local seed = H.seed % 997
	local pattern = spec.pattern
	local grain = spec.grain or 1
	-- grain octaves (cycles per nominal stud). The texel size varies over the cap (u runs round the head: a
	-- texel is ~0.014 studs wide at the hairline, tiny near the crown), so each octave fades out where it nears
	-- the texture's Nyquist limit there: detail the texture cannot hold averages to its mean instead of
	-- aliasing into moire rings ("wood grain"). A per-texel white noise carries the finest grain: random
	-- speckle has no lattice to alias.
	local F00, F0, F1, F2 = 9 / grain, 22 / grain, 55 / grain, 120 / grain
	local TEX = H.L.tex or 256
	local texH, texW = 0.56 * 2.75 / TEX, 0.56 * TAU / TEX
	-- value noise shows its lattice (a honeycomb of blobs) well before the Nyquist limit: fade an octave out
	-- from 0.1 cycles per texel, gone at 0.25
	local function aa(F, tx)
		return 1 - smoothstep(0.1, 0.25, F * tx)
	end
	local white = Kit.White
	local wK = spec.white or (pattern == "stubble" and 0.55 or 0.3)
	-- isotropic mottle: strong for clipper stubble, faint under strands (whose streaks carry the texture)
	local isoK = (pattern == "stubble") and 1 or 0.3
	local coilish = pattern == "coil" or pattern == "curl"
	-- streaks along the hair: coordinates (across, along) for the cap's comb flow - around the parting's axis
	-- for parted and side-swept hair, around the ear-to-ear axis for combed back / forward hair, the cap's
	-- meridians (from the crown down) otherwise. Across: ~30 streaks per stud (a few texels each, finer would
	-- alias into a plaid); along: long, slowly varying
	local streak = spec.streak or 0.35
	local fk = spec.flow
	local fpx = (spec.flowOpts and spec.flowOpts.x) or spec.part or 0
	local atan2 = math.atan2
	-- streak noise in (across, along): long cells along the hair, two octaves across (the finer one only where
	-- the texels are small enough)
	local function streak2(a, b, tx, k)
		local fine = aa(36, tx)
		return noise3(a, b, 0.5 + k, seed + 9) + (fine > 0 and 0.5 * fine * noise3(a * 2.03, b * 1.7, 3.5 + k, seed + 10) or 0)
	end
	local function streakAt(X, Y, Z, u, v, tx)
		if fk == "part" or fk == "side" then
			local behind = smoothstep(0.1, 0.36, Z)
			local n0 = streak2(Z * 18, atan2(X - fpx, Y + 0.15) * 1.8, tx, 0)
			if behind > 0 then
				-- behind the crown the hair falls down the back: meridian streaks, blended in
				local n1 = noise3(u * 56, v * 4, 2.5, seed + 9)
				return lerp(n0, n1, behind) * (1 + 0.4 * behind * (1 - behind))
			end
			return n0
		elseif fk == "back" or fk == "forward" then
			return streak2(X * 18, atan2(Z, Y + 0.15) * 1.8, tx, 0)
		end
		-- meridians converge at the pole: fade the streaks out there instead of letting them alias
		return noise3(u * 56, v * 4, 0.5, seed + 9) * smoothstep(0.06, 0.2, v)
	end
	-- 0.5: a strand random that is never one of the grey ones (greying is scattered through the texture below)
	local hr, hg, hb = pal.at(0.5, spec.capT or 0.55, -1, true)
	local split = pal.dye == "Split"
	local ar, ag, ab = pal.at(0.5, spec.capT or 0.55, 1, true)
	local greyK = pal.grey or 0
	local gr = pal.greyRGB or { 0.7, 0.69, 0.67 }
	-- the scalp under short hair: shaded skin with a cool cast from the stubble roots
	local scR = sk[1] * 0.84 + hr * 0.1
	local scG = sk[2] * 0.84 + hg * 0.1
	local scB = sk[3] * 0.86 + hb * 0.12
	local wx, wy, wz = Kit.Whorl(S)
	local waveLam = spec.waveLam or 0.05
	local contrast = spec.contrast or 1
	-- on near-black hair the coil tops need an absolute lift to read at all
	local dark = clamp((0.16 - pal.lum) / 0.16, 0, 1) * 0.07
	local lightK = smoothstep(0.12, 0.4, pal.lum)
	return function(u, v, r, g, b, a, x, y, z, nx, ny, nz)
		local X, Y, Z = x / kx, y / ky, z / kz
		local c = cut.cov(X, Y, Z)
		if c <= 0.002 then
			return scR, scG, scB, 1
		end
		local tx = max(texH, texW * sin(v * 2.75))
		local ix, iy = floor(u * TEX), floor(v * TEX)
		local wn = white(ix, iy, seed) - 0.5
		local n00 = Kit.RNoise(X, Y, Z, F00, seed + 6, 1)
		local a0 = aa(F0, tx)
		local n0 = a0 > 0 and Kit.RNoise(X, Y, Z, F0, seed + 7, 2) * a0 or 0
		local s
		if coilish then
			-- coils / curls make their own clusters below: only the coverage blend needs a grain here
			s = clamp(0.5 + (0.3 * n00 + 0.35 * n0 + wK * wn) * 1.1, 0, 1)
		else
			-- the fine octaves only where they show (strands get their texture from the streaks)
			local n1, n2 = 0, 0
			if isoK > 0.5 then
				local a1, a2 = aa(F1, tx), aa(F2, tx)
				n1 = a1 > 0 and Kit.RNoise(X, Y, Z, F1, seed, 1) * a1 or 0
				n2 = a2 > 0 and Kit.RNoise(X, Y, Z, F2, seed + 5, 2) * a2 or 0
			end
			-- streaks along the hair for longer hair under the clumps
			local n3 = streak > 0 and clamp(streakAt(X, Y, Z, u, v, tx) * 1.7, -0.5, 0.5) or 0
			s = clamp(0.5 + ((0.3 * n00 + 0.35 * n0 + 0.5 * n1 + 0.35 * n2) * isoK + wK * wn + streak * n3) * 1.1, 0, 1)
		end
		-- coverage as a smooth blend with the grain breaking up its middle (a fade is a gradient, a buzz cut a
		-- mottle of hair and scalp)
		local m = clamp(c + (s - 0.5) * 0.9 * c * (1 - c) * 4 * 0.5, 0, 1)
		local cr, cg, cb = hr, hg, hb
		if split and X > 0 then
			cr, cg, cb = ar, ag, ab
		end
		if greyK > 0 then
			-- salt and pepper: grey strands scattered through the dark ones (about greyK of them, more at the
			-- temples), each only partly grey at this scale (a texel holds a few strands)
			local f = clamp(greyK * (1 + 0.6 * smoothstep(0.05, 0.25, abs(X) - 0.25)) * (1 + 0.6 * n0), 0, 0.9)
			-- a texel is grey with probability f (a per-texel random: an exact share, no moire), partly grey
			-- strands at the edge of that share
			local h = white(ix, iy, seed + 17)
			local gk = (1 - smoothstep(f - 0.06, f + 0.06, h)) * 0.85
			cr, cg, cb = lerp(cr, gr[1], gk), lerp(cg, gr[2], gk), lerp(cb, gr[3], gk)
		end
		local k = (0.72 + 0.56 * s) * contrast + (1 - contrast)
		if pattern == "stubble" then
			-- clipper-short hair: a mottle of hair over the scalp, strongly grainy
			k = 0.6 + 0.8 * s
		elseif pattern == "waves" then
			-- brushed 360 waves: crescent ridges in rings around the crown
			local dx, dy, dz = X - wx, Y - wy, Z - wz
			local d = sqrt(dx * dx + dy * dy + dz * dz)
			local w = sin((d + 0.012 * sin(math.atan2(dx, dz) * 3)) / waveLam * TAU)
			k *= 1 + 0.22 * w
		elseif pattern == "coil" or pattern == "curl" then
			-- coils / curls: clusters with dark crevices between lighter coil tops (cluster scale ~ a few texels,
			-- finer would alias); curls in bigger rounder clusters
			local g1 = pattern == "coil" and 24 / grain or 15 / grain
			-- a warped domain: clusters of irregular size and shape instead of value noise's lattice of blobs
			local wx = Kit.RNoise(X, Y, Z, 5.3, seed + 21, 2) * 0.045
			local wz = Kit.RNoise(Z, X, Y, 5.3, seed + 22, 1) * 0.045
			local X2, Z2 = X + wx, Z + wz
			local ag = aa(g1 * 1.9, tx)
			local q = Kit.RNoise(X2, Y, Z2, g1, seed + 9, 1) * (0.6 + 0.4 * aa(g1, tx))
				+ (ag > 0 and 0.5 * ag * Kit.RNoise(X2, Y + wx, Z2, g1 * 1.9, seed + 3, 2) or 0)
				+ 0.4 * Kit.RNoise(X, Y, Z, 7, seed + 11, 2) + 0.25 * wn
			-- coil tops catch the light (a warm lift on dark hair), the crevices between clusters fall dark; light
			-- hair scatters more light into its crevices (less contrast)
			local top = smoothstep(-0.55, 0.7, q)
			k = lerp(0.36 + 1.2 * top, 0.62 + 0.62 * top, lightK)
			local lift = dark * top
			return lerp(scR, cr * k + lift, m), lerp(scG, cg * k + lift * 0.82, m), lerp(scB, cb * k + lift * 0.62, m), 1
		end
		return lerp(scR, cr * k, m), lerp(scG, cg * k, m), lerp(scB, cb * k, m), 1
	end
end

-- HairCap: the shell over the scalp. spec = Kit.Cut spec + pattern ("strands" | "waves" | "coil"), flow
-- (texture direction kind), extra(x, y, z, cov) -> extra thickness (volume shells), name, material,
-- capT (where along a strand the visible colour sits), contrast, reflectance
function Parts.Cap(H, spec)
	local S = H.S
	H.cut = Kit.Cut(S, {
		hairline = spec.hairline or H.hairline, growth = H.growth, fade = spec.fade, top = spec.top, side = spec.side,
		density = spec.density, region = spec.region, shaved = spec.shaved, part = spec.part, edge = spec.edge,
	})
	local L = H.L
	local name = spec.name or "HairCap"
	local piece = Parts.Piece(H, name, {
		material = spec.material or "Plastic", castShadow = true, reflectance = spec.reflectance,
	})
	local pal, sk = H.pal, H.skin
	local hr, hg, hb = pal.at(0.5, spec.capT or 0.55, -1)
	local ar, ag, ab = pal.at(0.5, spec.capT or 0.55, 1)
	local split = pal.dye == "Split"
	local scR, scG, scB = sk[1] * 0.84 + hr * 0.1, sk[2] * 0.84 + hg * 0.1, sk[3] * 0.86 + hb * 0.12
	local cols = spec.cols or L.cols
	local rows = spec.rows or L.rows
	Kit.Cap(S, piece.mesh, {
		cut = H.cut, cols = cols, rows = rows, extra = spec.extra, reach = spec.reach, gridNormals = spec.gridNormals,
		color = function(x, y, z, c)
			local k = smoothstep(0.05, 0.95, c)
			local r, g, b = hr, hg, hb
			if split and x > 0 then
				r, g, b = ar, ag, ab
			end
			return lerp(scR, r, k), lerp(scG, g, k), lerp(scB, b, k)
		end,
	})
	if L.tex then
		piece.texture = { w = L.tex, h = L.tex, shade = capShader(H, spec) }
	end
	return piece
end

------------------------------------------------------------------------
-- Roots
------------------------------------------------------------------------
-- about n root points spread evenly over the scalp (a jittered golden-angle lattice), each kept with
-- probability accept(x, y, z, da, cov) (0..1). Returns { { x, y, z, nx, ny, nz, da, cov, rnd } }.
function Parts.Roots(H, n, accept, seed)
	local S, cut = H.S, H.cut
	local rng = MeshKit.Rng(seed or H.seed + 1)
	local zMin = cos(2.75)
	local function point(M, i, jx, jy)
		local zc = 1 - (i - 0.5 + jy) / M * (1 - zMin)
		local th = acos(clamp(zc, -1, 1))
		local az = (i + jx) * 2.399963229728653
		local x, y, z, nx, ny, nz = Kit.ScalpAt(S, az, th, 0)
		local c, _, _, da = cut.cov(x, y, z)
		return x, y, z, nx, ny, nz, da or S.around(x, z), c
	end
	-- acceptance estimate on a fixed lattice, so the count comes out near n
	local M0, sum = 240, 0
	for i = 1, M0 do
		local x, y, z, _, _, _, da, c = point(M0, i, 0, 0)
		sum += clamp(accept(x, y, z, da, c), 0, 1)
	end
	local frac = max(sum / M0, 0.01)
	local M = max(4, ceil(n / frac))
	local out = {}
	for i = 1, M do
		local jx, jy = rng:Range(-0.3, 0.3), rng:Range(-0.35, 0.35)
		local x, y, z, nx, ny, nz, da, c = point(M, i, jx, jy)
		local p = clamp(accept(x, y, z, da, c), 0, 1)
		if p > 0 and rng:Next() < p then
			out[#out + 1] = { x, y, z, nx, ny, nz, da, c, rng:Next() }
		end
	end
	-- shuffled: a component that stops at its triangle budget thins its strands evenly over the scalp
	for i = #out, 2, -1 do
		local j = rng:Int(1, i)
		out[i], out[j] = out[j], out[i]
	end
	step(M * 3)
	return out
end

-- triangles a component may still add: spec.tris, or a share of what the section's budget has left
function Parts.Allow(H, spec)
	if spec.tris then
		return spec.tris * (H.nScale or 1)
	end
	-- strands are added until 97 % of the budget is spent (the last strand of each pass may overshoot a little)
	local left = H.budget * 0.97 * (H.nScale or 1) - Parts.Tris(H) - (spec.reserve or 0)
	return max(0, left) * (spec.share or 1)
end

------------------------------------------------------------------------
-- Moving groups (HairFX swings them; ANATOMY_CONTRACTS section 11: rigid pieces, joint landmarks)
------------------------------------------------------------------------
-- the group a hanging root belongs to: sectors around the head (left front .. back .. right front)
function Parts.GroupKey(H, x, z, da)
	local n = H.L.groups
	if n <= 0 then
		return nil
	end
	-- 0 = the character's left front, 1 = its right front, through the back
	local a = math.atan2(x, z) -- 0 at the back, +pi/2 at the right
	local u = clamp((a + pi) / TAU, 0, 0.9999)
	-- sector index from the left side round the back to the right
	return floor(u * n) + 1
end

-- piece for group g, segment s (1 = from the head, 2 = the lower half): name, props
function Parts.GroupPiece(H, prefix, g, s, props)
	local name = string.format("%s%02d%s", prefix, g, s > 1 and string.char(96 + s) or "")
	local p = Parts.Piece(H, name, props)
	local key = prefix .. g
	local grp = H.groups[key]
	if not grp then
		grp = { prefix = prefix, g = g, segs = {}, piv = { 0, 0, 0, 0 }, tip = { 0, 0, 0, 0 } }
		H.groups[key] = grp
	end
	if not grp.segs[s] then
		grp.segs[s] = { name = name, piv = { 0, 0, 0, 0 }, tip = { 0, 0, 0, 0 } }
	end
	return p, grp.segs[s], grp
end

local function acc(v, x, y, z, w)
	w = w or 1
	v[1] += x * w
	v[2] += y * w
	v[3] += z * w
	v[4] += w
end
Parts.Acc = acc

------------------------------------------------------------------------
-- Clumps
------------------------------------------------------------------------
-- colour of a clump: palette along the strand, the outer face lighter than the side facing the scalp,
-- deeper layers darker (self shadowing reads as volume)
function Parts.ClumpColor(H, rnd, x, layerK)
	local pal = H.pal
	return function(t, k, s)
		local r, g, b = pal.at(rnd, t, x)
		local sh = (s >= 0 and (0.93 + 0.13 * s) or (0.93 + 0.33 * s)) * layerK
		return r * sh, g * sh, b * sh
	end
end

-- Emits one strand: into the static piece, or (when it hangs and the level has swinging groups) split where
-- it leaves the scalp into a static upper part and one or two segments of its group's swinging pieces.
-- build(mesh, pts, ta, tb, openTip, thinStart) adds the geometry of the strand's parameter range [ta, tb]
-- (0 = root .. 1 = tip) along pts; openTip = the range ends before the tip (an overlap follows), thinStart =
-- the range starts under the previous one (slightly thinner so a small swing shows no gap).
function Parts.Emit(H, static, rs, leftFrac, g, prefix, mat, build)
	local L = H.L
	local n = #rs
	if not (g and leftFrac and L.groups > 0 and n >= 5) then
		build(static.mesh, rs, 0, 1, false, false)
		return
	end
	local ki = clamp(floor(clamp(leftFrac, 0.06, 0.85) * (n - 1) + 1.5), 2, n - 2)
	local function tOf(i)
		return (i - 1) / (n - 1)
	end
	local upper = table.move(rs, 1, ki + 1, 1, {})
	if H.sparseTop and #upper >= 7 then
		-- the part lying on the scalp needs fewer rings than the hanging part (keeps its last two: the overlap)
		local thin = {}
		for i = 1, #upper - 2, 2 do
			thin[#thin + 1] = upper[i]
		end
		thin[#thin + 1] = upper[#upper - 1]
		thin[#thin + 1] = upper[#upper]
		upper = thin
	end
	build(static.mesh, upper, 0, tOf(ki + 1), true, false)
	if L.segs >= 2 and n - ki >= 5 then
		local mid = ki + floor((n - ki) / 2)
		local p1, s1 = Parts.GroupPiece(H, prefix, g, 1, mat)
		local p2, s2 = Parts.GroupPiece(H, prefix, g, 2, mat)
		build(p1.mesh, table.move(rs, ki, mid + 1, 1, {}), tOf(ki), tOf(mid + 1), true, true)
		build(p2.mesh, table.move(rs, mid, n, 1, {}), tOf(mid), 1, false, true)
		local q0, q1, q2 = rs[ki], rs[mid], rs[n]
		acc(s1.piv, q0[1], q0[2], q0[3])
		acc(s1.tip, q1[1], q1[2], q1[3])
		acc(s2.piv, q1[1], q1[2], q1[3])
		acc(s2.tip, q2[1], q2[2], q2[3])
	else
		local p1, s1 = Parts.GroupPiece(H, prefix, g, 1, mat)
		build(p1.mesh, table.move(rs, ki, n, 1, {}), tOf(ki), 1, false, true)
		local q0, q2 = rs[ki], rs[n]
		acc(s1.piv, q0[1], q0[2], q0[3])
		acc(s1.tip, q2[1], q2[2], q2[3])
	end
end

-- Strand clumps. spec:
--   n (count at full detail, before density), accept(x, y, z, da, cov) -> 0..1, len(root) -> studs,
--   w, h (half width / thickness, nominal studs), flow (Kit.Flow fn), lift, stick, grav, stiff, free,
--   off(u, root) -> offset (default: cap top + a lift for volume), wave = { amp, lam } (or nil), twist,
--   layerK (shade), jitter = { amp, freq }, piece (static piece name, default "HairTop"),
--   hang = { prefix } -> long hair splits into a static upper part and swinging group pieces (Parts.Emit),
--   tips (share of clumps with fine strands at the tips, full only), seed, sides, maxRings, taper, bend(u, root)
function Parts.Clumps(H, spec)
	local S, L = H.S, H.L
	local count = max(1, floor((spec.n or 60) * L.k * (0.55 + 0.75 * H.density) * (1.25 - 0.5 * H.clump) * (H.nScale or 1) + 0.5))
	if spec.minN then
		count = max(count, spec.minN)
	end
	local roots = Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.35, 0.8, c)
	end, (spec.seed or 0) + H.seed + 11)
	local out = H.out
	local sides = spec.sides or L.sides
	local wK = (0.75 + 0.5 * H.clump) * (0.85 + 0.3 * H.thick)
	local mat = { material = spec.material or Parts.Material(H.htype), castShadow = true, reflectance = spec.reflectance }
	local static = Parts.Piece(H, spec.piece or "HairTop", mat)
	local made = 0
	local rng = MeshKit.Rng(H.seed + (spec.seed or 0) + 23)
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		local x, y, z, da, rnd = r[1], r[2], r[3], r[7], r[9]
		local len = spec.len(r)
		if Parts.Tris(H) - start > allow then
			break
		end
		if len > 0.01 then
			local offFn = spec.off and function(u)
				return spec.off(u, r)
			end or 0.012
			local pts, leftAt = Kit.Grow(S, x, y, z, {
				len = len, ds = spec.ds or clamp(len / 10, 0.012, 0.04), flow = spec.flow, lift = spec.lift or 0,
				off = offFn, stick = spec.stick or 0.6, grav = spec.grav or 0, stiff = spec.stiff or 0.5,
				free = spec.free, glue = spec.glue, bodyOff = spec.bodyOff, dir = spec.dir and spec.dir(r) or nil, jitter = spec.jitter and {
					amp = spec.jitter.amp, freq = spec.jitter.freq, seed = H.seed + (spec.seed or 0),
				} or nil,
			})
			if spec.bend then
				pts = spec.bend(pts, r)
			end
			local plen = Kit.Length(pts)
			local rings = clamp(floor(plen * 26 * L.rings + 3.5), 3, spec.maxRings or 18)
			local rs = Kit.Resample(pts, rings)
			if spec.wave then
				rs = Kit.Wave(rs, out, spec.wave.amp * (0.7 + 0.6 * rnd), spec.wave.lam * (0.85 + 0.3 * rng:Next()),
					spec.wave.phase and spec.wave.phase(r) or rnd * TAU, spec.wave.rise or 0.08)
			end
			local w0 = (spec.w or 0.032) * wK * (0.75 + 0.5 * rng:Next())
			local h0 = (spec.h or 0.009) * (0.85 + 0.3 * H.thick)
			local tipStart = spec.taper or 0.5
			local twist = (spec.twist or 0.5) * (rng:Next() - 0.5) * 2
			local col = Parts.ClumpColor(H, rnd, x, (spec.layerK or 1) * (0.9 + 0.2 * rng:Next()))
			local tipW = spec.tipW or 0.1
			local function W(t)
				return w0 * (0.6 + 0.4 * smoothstep(0, 0.22, t)) * (1 - (1 - tipW) * smoothstep(tipStart, 1, t))
			end
			local function Hh(t)
				return h0 * (1 - 0.6 * smoothstep(0.55, 1, t))
			end
			local g = spec.hang and leftAt and Parts.GroupKey(H, x, z, da)
			Parts.Emit(H, static, rs, leftAt and (leftAt - 1) / (#pts - 1), g, spec.hang and spec.hang.prefix or "HairClump", mat,
				function(mesh, pts2, ta, tb, openTip, thin)
					local span = tb - ta
					local k = thin and 0.92 or 1
					Kit.Clump(mesh, pts2, {
						sides = sides, out = out, twist = twist * span, tip = openTip and "open" or "point", flat = spec.flat,
						w = function(t)
							return W(ta + t * span) * ((t < 0.05 and thin) and k or 1)
						end,
						h = function(t)
							return Hh(ta + t * span) * ((t < 0.05 and thin) and k or 1)
						end,
						color = function(t, kk, sa)
							return col(ta + t * span, kk, sa)
						end,
					})
				end)
			-- fine strands splitting off at the tip: soft, thin ends
			if spec.tips and L.strands and plen > 0.08 and rng:Next() < spec.tips and not (g and L.groups > 0) then
				Parts.TipStrands(H, static, rs, w0, rnd, x, rng, spec)
			end
			made += 1
		end
	end
	return made
end

-- a two-sided sheet over a grid of points G[c][i] (c across, i along the strands), rings i0..i1, offset
-- half thickness d; colour(c, t) -> r, g, b (t = 0 root .. 1 tip of the full strand), tFn(i) -> t
local function sheet(m, G, c0, c1, i0, i1, d, out, colour, tFn)
	local N = m.N
	local vertex, tri = MeshKit.Vertex, MeshKit.Tri
	local ncol, nrow = c1 - c0 + 1, i1 - i0 + 1
	if ncol < 2 or nrow < 2 then
		return
	end
	for side = 1, -1, -2 do
		local first = m.nv + 1
		for c = c0, c1 do
			local col = G[c]
			local cp, cn = G[max(c0, c - 1)], G[min(c1, c + 1)]
			for i = i0, i1 do
				local p = col[i]
				local pp, pn = col[max(i0, i - 1)], col[min(i1, i + 1)]
				local ax, ay, az = pn[1] - pp[1], pn[2] - pp[2], pn[3] - pp[3]
				local bx, by, bz = cn[i][1] - cp[i][1], cn[i][2] - cp[i][2], cn[i][3] - cp[i][3]
				local nx, ny, nz = norm3(Kit.cross(ax, ay, az, bx, by, bz))
				local ox, oy, oz = out(p[1], p[2], p[3])
				if nx * ox + ny * oy + nz * oz < 0 then
					nx, ny, nz = -nx, -ny, -nz
				end
				if nx == 0 and ny == 0 and nz == 0 then
					nx, ny, nz = ox, oy, oz
				end
				local r, g, b = colour(c, tFn(i))
				local v = vertex(m, p[1] + nx * d * side, p[2] + ny * d * side, p[3] + nz * d * side, (c - c0) / (ncol - 1), tFn(i), r, g, b)
				N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = nx * side, ny * side, nz * side
			end
		end
		-- winding: outward for the outer sheet, inward for the inner one, decided per quad from its diagonals
		-- against its vertex normals (a strip whose first quad is degenerate - columns meeting at a root - or
		-- that folds must not turn its whole side inside out and vanish to back-face culling)
		local P = m.P
		for c = 0, ncol - 2 do
			for i = 0, nrow - 2 do
				local a = first + c * nrow + i
				local b = a + 1
				local e = a + nrow
				local f = e + 1
				-- quad (a, b, f, e): diagonals a->f and b->e
				local ux, uy, uz = P[f * 3 - 2] - P[a * 3 - 2], P[f * 3 - 1] - P[a * 3 - 1], P[f * 3] - P[a * 3]
				local wx, wy, wz = P[e * 3 - 2] - P[b * 3 - 2], P[e * 3 - 1] - P[b * 3 - 1], P[e * 3] - P[b * 3]
				local fx, fy, fz = Kit.cross(ux, uy, uz, wx, wy, wz)
				local snx = N[a * 3 - 2] + N[b * 3 - 2] + N[e * 3 - 2] + N[f * 3 - 2]
				local sny = N[a * 3 - 1] + N[b * 3 - 1] + N[e * 3 - 1] + N[f * 3 - 1]
				local snz = N[a * 3] + N[b * 3] + N[e * 3] + N[f * 3]
				-- (a, b, e) has the normal (b - a) x (e - a): the quad's diagonal cross (f - a) x (e - b) points the same way
				local flip = fx * snx + fy * sny + fz * snz < 0
				if flip then
					tri(m, a, e, b)
					tri(m, b, e, f)
				else
					tri(m, a, b, e)
					tri(m, b, f, e)
				end
			end
		end
	end
	step(ncol * nrow * 4)
end

-- Curtain: the continuous inner layer of long hair (nothing shows through between the clumps): columns of
-- strands around the head from azimuth az0 to az1 (Kit.Cap convention: 0 = the back, +pi/2 = the right),
-- each grown like a clump, joined into a two-sided sheet. spec: cols (at full), az0, az1, th(az) -> root polar
-- angle, len(az, rnd) -> studs, flow, off(u), grav, stick, stiff, shade, hang = { prefix } (swinging groups as in
-- Clumps), wave, bodyOff
function Parts.Curtain(H, spec)
	local S, L = H.S, H.L
	local lodK = H.lod == "full" and 1 or (H.lod == "medium" and 0.6 or 0.4)
	local cols = max(5, floor((spec.cols or 22) * lodK + 0.5))
	local rings = spec.rings or max(4, floor((spec.rings0 or 14) * L.rings + 0.5))
	local out = H.out
	local rng = MeshKit.Rng(H.seed + 501)
	local G, info = {}, {}
	for c = 1, cols do
		local az = lerp(spec.az0, spec.az1, (c - 1) / (cols - 1))
		local th = spec.th(az)
		local x, y, z = Kit.ScalpAt(H.S, az, th, 0)
		local rnd = rng:Next()
		local len = spec.len(az, rnd)
		local pts, leftAt = Kit.Grow(S, x, y, z, {
			len = len, ds = clamp(len / 14, 0.02, 0.05), flow = spec.flow, lift = 0, off = spec.off, stick = spec.stick or 0.95,
			grav = spec.grav or 1, stiff = spec.stiff or 0.2, bodyOff = spec.bodyOff or 0.03,
		})
		local rs = Kit.Resample(pts, rings)
		if spec.wave then
			rs = Kit.Wave(rs, out, spec.wave.amp, spec.wave.lam, spec.wave.phase and spec.wave.phase({ x, y, z, 0, 0, 0, 0, 0, rnd }) or 0, spec.wave.rise or 0.2)
		end
		G[c] = rs
		info[c] = { left = leftAt and (leftAt - 1) / (#pts - 1) or 1, x = x, z = z, g = Parts.GroupKey(H, x, z), rnd = rnd }
	end
	local pal = H.pal
	local shade = spec.shade or 0.66
	local colour = function(c, t)
		local r, g, b = pal.at(info[c].rnd, t, info[c].x)
		local k = shade * (0.88 + 0.24 * info[c].rnd)
		return r * k, g * k, b * k
	end
	local d = spec.half or 0.005
	local mat = { material = spec.material or Parts.Material(H.htype), castShadow = true }
	local static = Parts.Piece(H, spec.piece or "HairTop", mat)
	-- strips of consecutive columns in one swinging group (sharing the next group's first column: no gap)
	local c = 1
	while c <= cols do
		local g = info[c].g
		local c1 = c
		while c1 < cols and info[c1 + 1].g == g do
			c1 += 1
		end
		local cEnd = min(cols, c1 + 1)
		if spec.hang and g and L.groups > 0 then
			-- split where the strip's strands leave the scalp (the median of its columns)
			local lefts = {}
			for k = c, c1 do
				lefts[#lefts + 1] = info[k].left
			end
			table.sort(lefts)
			local cut = clamp(lefts[floor(#lefts / 2) + 1], 0.1, 0.8)
			local ki = clamp(floor(cut * (rings - 1) + 1.5), 2, rings - 2)
			sheet(static.mesh, G, c, cEnd, 1, ki + 1, d, out, colour, function(i)
				return (i - 1) / (rings - 1)
			end)
			local tF = function(i)
				return (i - 1) / (rings - 1)
			end
			if L.segs >= 2 and rings - ki >= 5 then
				local mid = ki + floor((rings - ki) / 2)
				local p1, s1 = Parts.GroupPiece(H, spec.hang.prefix or "HairClump", g, 1, mat)
				local p2, s2 = Parts.GroupPiece(H, spec.hang.prefix or "HairClump", g, 2, mat)
				sheet(p1.mesh, G, c, cEnd, ki, mid + 1, d * 0.9, out, colour, tF)
				sheet(p2.mesh, G, c, cEnd, mid, rings, d * 0.85, out, colour, tF)
				for k = c, cEnd do
					local q0, q1, q2 = G[k][ki], G[k][mid], G[k][rings]
					acc(s1.piv, q0[1], q0[2], q0[3])
					acc(s1.tip, q1[1], q1[2], q1[3])
					acc(s2.piv, q1[1], q1[2], q1[3])
					acc(s2.tip, q2[1], q2[2], q2[3])
				end
			else
				local p1, s1 = Parts.GroupPiece(H, spec.hang.prefix or "HairClump", g, 1, mat)
				sheet(p1.mesh, G, c, cEnd, ki, rings, d * 0.9, out, colour, tF)
				for k = c, cEnd do
					local q0, q2 = G[k][ki], G[k][rings]
					acc(s1.piv, q0[1], q0[2], q0[3])
					acc(s1.tip, q2[1], q2[2], q2[3])
				end
			end
		else
			sheet(static.mesh, G, c, cEnd, 1, rings, d, out, colour, function(i)
				return (i - 1) / (rings - 1)
			end)
		end
		c = c1 + 1
	end
	return cols
end

------------------------------------------------------------------------
-- Round strands: locs, braids, twists
------------------------------------------------------------------------
-- section functions: (t, a, s, r) -> radius, with s = arc length along the strand (studs), r = base radius
Parts.SECTIONS = {
	-- locs: matted, lumpy, a little flattened, thinner at the root
	loc = function(seed)
		return function(t, a, s, r)
			local lump = 1 + 0.17 * noise3(s * 22, cos(a) * 1.4, sin(a) * 1.4, seed) + 0.07 * noise3(s * 55, cos(a) * 2, sin(a) * 2, seed + 3)
			return r * lump * (0.72 + 0.28 * smoothstep(0, 0.06, s)) * (1 - 0.15 * t)
		end
	end,
	-- three-strand braid: the union of three woven strands (alternating lobes, tight and neat)
	braid = function(seed, period)
		return function(t, a, s, r)
			local taper = 1 - 0.35 * smoothstep(0.75, 1, t)
			return Kit.Plait(a, s / period, r * 0.52 * taper, r * 0.5 * taper) * (0.8 + 0.2 * smoothstep(0, 0.04, s))
		end
	end,
	-- two-strand twist: a rope
	twist = function(seed, period)
		return function(t, a, s, r)
			local taper = 1 - 0.3 * smoothstep(0.7, 1, t)
			return Kit.Rope(a, s / period, r * 0.45 * taper, r * 0.58 * taper) * (0.8 + 0.2 * smoothstep(0, 0.04, s))
		end
	end,
}

-- Round strands (locs, braids, twists). spec: n, accept, len(r), r (base radius), section (Parts.SECTIONS key),
-- period (braids / twists: studs per crossing), flow, lift, stick, grav, stiff, free, off(u, r), hang = { prefix },
-- dir(r) -> initial direction, seed, tip ("dome" | "point"), ringsPer (rings per stud), shade, sides, bend
function Parts.Tubes(H, spec)
	local S, L = H.S, H.L
	local count = max(spec.minN or 3, floor((spec.n or 30) * (spec.lodK and spec.lodK[H.lod] or L.k) * (0.6 + 0.6 * H.density) * (H.nScale or 1) + 0.5))
	local roots = Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.4, 0.8, c)
	end, (spec.seed or 0) + H.seed + 31)
	local out, pal = H.out, H.pal
	local sides = spec.sides or L.tubeSides
	local mat = { material = spec.material or "Plastic", castShadow = true }
	local static = Parts.Piece(H, spec.piece or "HairTop", mat)
	local rng = MeshKit.Rng(H.seed + (spec.seed or 0) + 41)
	local kind = spec.section or "loc"
	if H.lod == "low" then
		-- far away a plait or a twist reads as its silhouette alone
		kind = "plain"
	end
	local period = spec.period or 0.08
	local seed = H.seed % 1000
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local x, y, z, da, rnd = r[1], r[2], r[3], r[7], r[9]
		local len = spec.len(r)
		local r0 = (spec.r or 0.03) * (0.85 + 0.3 * rng:Next()) * (0.85 + 0.3 * H.thick)
		local pts, leftAt = Kit.Grow(S, x, y, z, {
			len = len, ds = clamp(len / 14, 0.015, 0.05), flow = spec.flow, lift = spec.lift or 0,
			off = function(u)
				return spec.off and spec.off(u, r) or (r0 * 0.9 + 0.008)
			end, stick = spec.stick or 0.7, grav = spec.grav or 1, stiff = spec.stiff or 0.4, free = spec.free,
			bodyOff = (spec.bodyOff or 0.02) + r0, dir = spec.dir and spec.dir(r) or nil,
			jitter = spec.jitter and { amp = spec.jitter.amp, freq = spec.jitter.freq, seed = H.seed + 7 } or nil,
		})
		if spec.bend then
			pts = spec.bend(pts, r)
		end
		local plen = Kit.Length(pts)
		local ringsPer = (spec.ringsPer or 22) * L.rings
		if kind == "plain" then
			ringsPer = 7
		elseif kind ~= "loc" and H.lod == "full" then
			-- the weave needs ~4 rings per crossing to read
			ringsPer = max(ringsPer, 4.2 / period)
		elseif kind ~= "loc" then
			ringsPer = max(ringsPer, 2.2 / period)
		end
		local rings = clamp(floor(plen * ringsPer + 2.5), 3, spec.maxRings or 60)
		local rs = Kit.Resample(pts, rings)
		local sec
		if kind == "plain" then
			sec = function(t, a, s2, rr)
				return rr * (0.8 + 0.2 * smoothstep(0, 0.05, s2)) * (1 - 0.2 * t)
			end
		elseif kind == "loc" then
			sec = Parts.SECTIONS.loc(seed + floor(rnd * 997))
		else
			sec = Parts.SECTIONS[kind](seed, period * (0.92 + 0.16 * rnd))
		end
		local phase = rnd * 3
		local shade = (spec.shade or 1) * (0.9 + 0.2 * rng:Next())
		local function colour(t, a, rr)
			local cr, cg, cb = pal.at(rnd, t, x)
			-- crevices between lumps / braid lobes darker, the outer face lighter
			local k = shade * (0.78 + 0.32 * clamp(rr, 0.5, 1.25) - 0.08 * (1 - sin(a)) * 0.5)
			return cr * k, cg * k, cb * k
		end
		local g = spec.hang and leftAt and Parts.GroupKey(H, x, z, da)
		Parts.Emit(H, static, rs, leftAt and (leftAt - 1) / (#pts - 1), g, spec.hang and spec.hang.prefix or "HairLoc", mat,
			function(mesh, pts2, ta, tb, openTip, thin)
				local span = tb - ta
				Kit.Tube(mesh, pts2, {
					sides = sides, out = out, rad = r0, tip = openTip and "open" or (spec.tip or "dome"),
					r = function(t, a)
						local tt = ta + t * span
						return sec(tt, a, tt * plen + phase, r0) * ((thin and t < 0.05) and 0.94 or 1)
					end,
					color = function(t, a, rr)
						return colour(ta + t * span, a, rr)
					end,
				})
			end)
	end
	return #roots
end

------------------------------------------------------------------------
-- Curls and coils
------------------------------------------------------------------------
-- curl clusters (curly hair): each root grows a short arc, a ringlet spirals round it; neighbours cluster.
-- spec: n, accept, len(r) (the arc), radius (ringlet radius), tube (strand radius), flow, lift, off(u), grav,
-- hang = { prefix } (long ringlets swing), perTurn, piece, bounce (piece name for a bouncing cluster group)
function Parts.Curls(H, spec)
	local S, L = H.S, H.L
	local count = max(3, floor((spec.n or 60) * L.k * (0.6 + 0.6 * H.density) * (H.nScale or 1) + 0.5))
	local roots = Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.45, 0.85, c)
	end, (spec.seed or 0) + H.seed + 51)
	local out, pal = H.out, H.pal
	local rng = MeshKit.Rng(H.seed + (spec.seed or 0) + 53)
	local mat = { material = spec.material or "Plastic", castShadow = true }
	local sides = H.lod == "full" and 4 or 3
	local perTurn = (spec.perTurn or 7) * (H.lod == "full" and 1 or 0.72)
	local cs = 1 + 0.35 * H.curl
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local x, y, z, da, rnd = r[1], r[2], r[3], r[7], r[9]
		local len = spec.len(r)
		local rad = (spec.radius or 0.02) * cs * (0.8 + 0.4 * rng:Next())
		local tube = (spec.tube or 0.0075) * (0.85 + 0.3 * H.thick)
		local pts, leftAt = Kit.Grow(S, x, y, z, {
			len = len, ds = clamp(len / 8, 0.01, 0.04), flow = spec.flow, lift = spec.lift or 0.5,
			off = function(u)
				return (spec.off and spec.off(u, r) or 0.02) + rad
			end, stick = spec.stick or 0.3, grav = spec.grav or 0.2, stiff = spec.stiff or 0.5, free = spec.free,
			bodyOff = 0.03 + rad, jitter = { amp = 0.3, freq = 8, seed = H.seed + 3 },
		})
		local rs = Kit.Resample(pts, max(4, floor(#pts * 0.7)))
		local plen = Kit.Length(rs)
		-- a ringlet: about one turn per 2.4 radii of length, tighter for tighter curls
		local turns = clamp(plen / (rad * (spec.pitch or 2.5)), 0.8, 9)
		local hp = Kit.Helix(rs, out, function(t)
			return rad * (0.75 + 0.25 * smoothstep(0, 0.2, t)) * (1 - 0.2 * t)
		end, turns, rnd * TAU, perTurn)
		local static = Parts.Piece(H, spec.piece or "HairTop", mat)
		local col = function(t, a, rr)
			local cr, cg, cb = pal.at(rnd, 0.25 + 0.75 * t, x)
			-- the outside of each loop catches light, the inside of the cluster is shadowed
			local k = (0.8 + 0.3 * smoothstep(-0.6, 0.9, sin(a))) * (0.82 + 0.25 * t)
			return cr * k, cg * k, cb * k
		end
		local g = spec.hang and leftAt and Parts.GroupKey(H, x, z, da)
		local target = static
		if spec.bounce and not g then
			target = Parts.Piece(H, spec.bounce(r), mat)
			H.bounce = H.bounce or {}
			H.bounce[target.mesh.name] = true
		end
		Parts.Emit(H, target, hp, leftAt and (leftAt - 1) / (#pts - 1), g, spec.hang and spec.hang.prefix or "HairCurl", mat,
			function(mesh, pts2, ta, tb, openTip, thin)
				local span = tb - ta
				Kit.Tube(mesh, pts2, {
					sides = sides, out = out, rad = tube, tip = openTip and "open" or "point",
					r = function(t)
						local tt = ta + t * span
						return tube * (0.75 + 0.25 * smoothstep(0, 0.1, tt)) * (1 - 0.55 * smoothstep(0.7, 1, tt))
					end,
					color = function(t, a, rr)
						return col(ta + t * span, a, rr)
					end,
				})
			end)
	end
	return #roots
end

-- short curly tops (fades, crew cuts, curly tops with curly / coily hair): curls for curly hair, tight coil
-- tufts for coily / afro-textured hair (the shell under them carries the coil texture)
function Parts.ShortCurls(H, spec)
	local L = H.len
	local coily = H.htype == "Kinky" or H.htype == "Coiled"
	local top = spec.top or 0.02
	local len0, len1 = spec.len[1], spec.len[2]
	local flow = Kit.Flow(H.S, "whorl")
	if coily then
		return Parts.Curls(H, {
			n = spec.coilN or 120, seed = 7, accept = spec.accept, flow = flow, lift = 0.8, stick = 0, grav = 0, stiff = 0.7,
			len = function(r)
				return lerp(0.025, 0.045, r[9]) * (0.8 + 0.5 * L)
			end, radius = 0.009, tube = 0.0048, pitch = 2.0, perTurn = 6, off = function()
				return top * 0.7
			end,
		})
	end
	return Parts.Curls(H, {
		n = spec.curlN or 70, seed = 7, accept = spec.accept, flow = flow, lift = 0.55, stick = 0.2, grav = 0.1, stiff = 0.55,
		len = function(r)
			return lerp(len0, len1, r[9]) * 1.1
		end, radius = 0.019, tube = 0.0075, off = function()
			return top * 0.6
		end,
	})
end

------------------------------------------------------------------------
-- Volumes: afros, high tops, coily masses
------------------------------------------------------------------------
-- distance along the normal from a scalp point (x, y, z, n) to the boundary of the volume vol (SDF, nominal),
-- searched up to tmax; 0 when the scalp point is already outside the volume
local function depthIn(vol, x, y, z, nx, ny, nz, tmax)
	if vol(x, y, z) >= 0 then
		return 0
	end
	local lo, hi = 0, tmax
	if vol(x + nx * hi, y + ny * hi, z + nz * hi) < 0 then
		return hi
	end
	for _ = 1, 12 do
		local mid = (lo + hi) * 0.5
		if vol(x + nx * mid, y + ny * mid, z + nz * mid) < 0 then
			lo = mid
		else
			hi = mid
		end
	end
	return (lo + hi) * 0.5
end
Parts.DepthIn = depthIn

-- A hair volume as the cap itself: the shell rises to the outer surface of vol (SDF), tapering to the cut's
-- thickness at the hairline; bumpy coily surface. spec: vol, edge (taper width inside the hairline), bump
-- (amplitude), bumpFreq, plus the Cap spec (fade, top, side, pattern, region...)
function Parts.Volume(H, spec)
	local S = H.S
	local vol = spec.vol
	local amp = spec.bump or 0.012
	local f1 = spec.bumpFreq or 16
	local seed = H.seed % 1000
	local edge = spec.edge or 0.1
	local cutDist
	local t = table.clone(spec)
	local frontEdge = spec.frontEdge or edge * 1.8
	t.extra = function(x, y, z, c)
		local nx, ny, nz = S.normal(x, y, z)
		local d = depthIn(vol, x, y, z, nx, ny, nz, spec.tmax or 0.6)
		local dist, da = cutDist(x, y, z)
		-- the volume rises from the hairline; over the forehead it rises more slowly (no brim over the eyes)
		local e = lerp(frontEdge, edge, smoothstep(0.5, 1.2, da or 1))
		local k = smoothstep(0, e, dist)
		-- clusters: lumps of a few centimetres with finer pebbling on them
		local b = amp * (0.62 * Kit.RNoise(x, y, z, f1, seed, 1) + 0.38 * Kit.RNoise(x, y, z, f1 * 2.6, seed + 1, 2))
		return max(0, d * k + b * k * smoothstep(0.015, 0.05, d))
	end
	t.gridNormals = true
	t.reach = spec.reach or 0.02
	-- the shell's own hairline distance (Kit.Cut is built inside Parts.Cap): bind lazily
	local piece
	do
		local cut0 = Kit.Cut(S, { hairline = spec.hairline or H.hairline, growth = H.growth })
		cutDist = cut0.dist
	end
	piece = Parts.Cap(H, t)
	return piece
end

-- coil halo: small springy coils over a volume's surface, breaking up its outline (soft edges). spec: n,
-- vol (the volume SDF the coils sit on), accept, bounce(r) -> piece name
function Parts.CoilHalo(H, spec)
	local S, L = H.S, H.L
	if H.lod == "low" then
		return 0
	end
	local count = max(4, floor((spec.n or 120) * L.k * (0.6 + 0.6 * H.density) * (H.nScale or 1) + 0.5))
	local roots = Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.6, 0.95, c)
	end, H.seed + 61)
	local out, pal = H.out, H.pal
	local rng = MeshKit.Rng(H.seed + 63)
	local mat = { material = "Plastic", castShadow = false }
	local cs = 1 + 0.3 * H.curl
	local sides = 3
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local x, y, z, nx, ny, nz, rnd = r[1], r[2], r[3], r[4], r[5], r[6], r[9]
		local d = spec.vol and depthIn(spec.vol, x, y, z, nx, ny, nz, 0.6) or 0
		local bx, by, bz = x + nx * (d - 0.004), y + ny * (d - 0.004), z + nz * (d - 0.004)
		-- a short coil standing out of the surface, leaning with the hair's fall
		local len = (0.03 + 0.03 * rng:Next()) * (0.8 + 0.4 * H.len)
		local dx, dy, dz = norm3(nx + rng:Range(-0.5, 0.5), ny + rng:Range(-0.3, 0.4), nz + rng:Range(-0.5, 0.5))
		local base = {}
		for i = 0, 3 do
			local u = i / 3
			base[#base + 1] = { bx + dx * len * u, by + dy * len * u - 0.006 * u * u, bz + dz * len * u }
		end
		local rad = (spec.radius or 0.015) * cs * (0.8 + 0.4 * rng:Next())
		local hp = Kit.Helix(base, out, rad, clamp(len / (rad * 2.1), 1, 3), rnd * TAU, H.lod == "full" and 5 or 4)
		local piece = Parts.Piece(H, spec.bounce and spec.bounce(r) or "HairTop", mat)
		if spec.bounce then
			H.bounce = H.bounce or {}
			H.bounce[piece.mesh.name] = true
		end
		local tube = (spec.tube or 0.0058) * (0.85 + 0.3 * H.thick)
		Kit.Tube(piece.mesh, hp, {
			sides = sides, out = out, rad = tube, tip = "point",
			r = function(t)
				return tube * (1 - 0.5 * smoothstep(0.7, 1, t))
			end,
			color = function(t, a)
				local cr, cg, cb = pal.at(rnd, 0.6 + 0.4 * t, x)
				local k = 0.82 + 0.3 * smoothstep(-0.5, 0.9, sin(a))
				return cr * k, cg * k, cb * k
			end,
		})
	end
	return #roots
end

-- fuzz: short zig-zag strands standing out of a volume's surface, the soft frizzy outline of coily hair
-- (full detail only). spec: n, vol, accept, len, zig (zig-zag amplitude)
function Parts.Fuzz(H, spec)
	local S = H.S
	if not H.L.strands then
		return 0
	end
	local count = max(4, floor((spec.n or 260) * (0.6 + 0.6 * H.density) * (0.6 + 0.8 * H.frizz) * (H.nScale or 1) + 0.5))
	local roots = Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.6, 0.95, c)
	end, H.seed + 71)
	local out, pal = H.out, H.pal
	local rng = MeshKit.Rng(H.seed + 73)
	local piece = Parts.Piece(H, "HairStrands", { material = "SmoothPlastic", doubleSided = true, castShadow = false })
	local zig = spec.zig or 0.006
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local x, y, z, nx, ny, nz, rnd = r[1], r[2], r[3], r[4], r[5], r[6], r[9]
		local d = spec.vol and depthIn(spec.vol, x, y, z, nx, ny, nz, 0.7) or 0.02
		local bx, by, bz = x + nx * (d - 0.006), y + ny * (d - 0.006), z + nz * (d - 0.006)
		local len = (spec.len or 0.04) * (0.6 + 0.8 * rng:Next())
		local dx, dy, dz = norm3(nx + rng:Range(-0.6, 0.6), ny + rng:Range(-0.4, 0.5), nz + rng:Range(-0.6, 0.6))
		-- a side axis for the zig-zag
		local sx, sy, sz = norm3(Kit.cross(dx, dy, dz, 0.3, 1, 0.2))
		local pts = {}
		for i = 0, 5 do
			local u = i / 5
			local w = (i % 2 == 0 and -1 or 1) * zig * (0.4 + 0.6 * u)
			pts[#pts + 1] = { bx + dx * len * u + sx * w, by + dy * len * u + sy * w - 0.004 * u * u, bz + dz * len * u + sz * w }
		end
		local tw = 0.0035 * (0.8 + 0.4 * H.thick)
		Kit.Strand(piece.mesh, pts, {
			w = function(t)
				return tw * (1 - 0.6 * t)
			end,
			out = out,
			color = function(t)
				local cr, cg, cb = pal.at(rnd, 0.7 + 0.3 * t, x)
				return cr * 1.12, cg * 1.12, cb * 1.12
			end,
		})
	end
	return #roots
end

------------------------------------------------------------------------
-- Cornrows
------------------------------------------------------------------------
-- rows run from the front hairline straight back over the crown to the nape: great circles round the head's
-- front-back axis (psi = the row's angle about it). Returns the rows' psi list and the coverage region fn.
function Parts.RowLayout(H, n, parting)
	local S = H.S
	local p0 = 0.5 - (parting or 0.2)
	local psiMax = 1.25
	local rows = {}
	for i = 1, n do
		rows[i] = -psiMax + 2 * psiMax * (i - 0.5) / n
	end
	local dpsi = 2 * psiMax / n
	local cy = S.cy
	local function psiOf(x, y)
		return math.atan2(x, y - cy + 0.25)
	end
	local region = function(x, y, z, da)
		local ps = psiOf(x, y)
		local k = (ps + psiMax) / dpsi - 0.5
		local f = abs(k - floor(k + 0.5)) -- 0 on a row centre, 0.5 on a parting
		return 1 - smoothstep(p0 - 0.05, p0 + 0.05, f)
	end
	return rows, region, psiOf, dpsi
end

-- the cornrow braids: each row a plait lying on the scalp (half sunk into the shell), from the front hairline
-- back to the nape; hanging tails at the nape when the hair is long. spec: n, r (row radius), period, tail(r)
function Parts.Cornrows(H, spec)
	local S, L = H.S, H.L
	local n = spec.n
	local rows, region, psiOf = Parts.RowLayout(H, n)
	local cut = H.cut
	local out, pal = H.out, H.pal
	local mat = { material = "Plastic", castShadow = true }
	local static = Parts.Piece(H, "HairTop", mat)
	local seed = H.seed % 1000
	local period = spec.period or 0.085
	local sides = H.lod == "full" and 5 or (H.lod == "medium" and 4 or 3)
	local cy = S.cy
	-- rings per stud from what the budget leaves for the rows (~1.3 studs each, plus the tails)
	local allow = Parts.Allow(H, { share = spec.tails and 0.7 or 0.95 })
	local perStud = clamp(allow / (n * 1.3 * sides * 2), 5, (H.lod == "full" and 3.6 or 2) / period)
	for i, psi in ipairs(rows) do
		-- walk the great circle from the front to the back, keeping the stretch inside the hair
		local pts = {}
		local started = false
		for k = 0, 64 do
			local beta = -1.45 + 2.95 * k / 64 -- front (-z) round over the top to the back (+z)
			local dx, dy, dz = sin(psi) * cos(beta), cos(psi) * cos(beta), sin(beta)
			local x, y, z = S.ray(dx, dy + 0.0, dz, 0)
			local c = cut.cov(x, y, z)
			if cut.dist(x, y, z) > 0.012 and c > 0.05 then
				started = true
				local nx, ny, nz = S.normal(x, y, z)
				local o = spec.r * 0.55
				pts[#pts + 1] = { x + nx * o, y + ny * o, z + nz * o }
			elseif started then
				break
			end
		end
		if #pts >= 4 then
			local plen = Kit.Length(pts)
			local ringsPer = perStud
			local rs = Kit.Resample(pts, clamp(floor(plen * ringsPer + 2), 4, 80))
			local r0 = spec.r * (0.9 + 0.2 * H.thick)
			local sec = perStud < 2.5 / period and function(t, a, s, r)
				return r * (0.8 + 0.2 * smoothstep(0, 0.03, s))
			end or Parts.SECTIONS.braid(seed, period)
			local x0 = rs[1][1]
			local rnd = (i * 0.618) % 1
			Kit.Tube(static.mesh, rs, {
				sides = sides, out = out, rad = r0, tip = "dome", root = "dome",
				r = function(t, a)
					return sec(t, a, t * plen, r0)
				end,
				color = function(t, a, rr)
					local cr, cg, cb = pal.at(rnd, 0.35 + 0.3 * t, x0)
					local k = 0.74 + 0.36 * clamp(rr, 0.5, 1.2)
					return cr * k, cg * k, cb * k
				end,
			})
			-- a tail hangs from the nape end of the row
			local tl = spec.tail and spec.tail(i) or 0
			if tl > 0.06 then
				H.tails = H.tails or {}
				H.tails[#H.tails + 1] = { rs[#rs], rs[#rs - 1], tl, r0, rnd }
			end
		end
	end
	return rows
end

------------------------------------------------------------------------
-- Hanging ends and ponytails
------------------------------------------------------------------------
-- round strands hanging from given points (cornrow tails, braid ends): list = { { p, prev, len, r, rnd } } (prev =
-- the point before p, giving the direction); section kind, period; swinging groups by position
function Parts.Hang(H, list, kind, period, prefix)
	local S, L = H.S, H.L
	local out, pal = H.out, H.pal
	local mat = { material = "Plastic", castShadow = true }
	local static = Parts.Piece(H, "HairTop", mat)
	local seed = H.seed % 1000
	local allow, start = Parts.Allow(H, {}), Parts.Tris(H)
	for _, e in ipairs(list) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local p, q, len, r0, rnd = e[1], e[2], e[3], e[4], e[5]
		local dx, dy, dz = norm3(p[1] - q[1], p[2] - q[2], p[3] - q[3])
		local pts = Kit.Grow(S, p[1], p[2], p[3], {
			len = len, ds = clamp(len / 12, 0.015, 0.05), dir = { dx, dy - 0.6, dz }, lift = 0, off = r0 + 0.006, stick = 0,
			grav = 1, stiff = 0.5, free = 0, bodyOff = 0.02 + r0,
		})
		local plen = Kit.Length(pts)
		local rings = clamp(floor(plen * (H.lod == "full" and 4.2 / period or 2.2 / period) + 2), 3, 60)
		local rs = Kit.Resample(pts, rings)
		local sec = Parts.SECTIONS[kind](seed, period)
		local g = Parts.GroupKey(H, p[1], p[3], S.around(p[1], p[3]))
		Parts.Emit(H, static, rs, 0.06, g, prefix or "HairBraid", mat, function(mesh, pts2, ta, tb, openTip, thin)
			local span = tb - ta
			Kit.Tube(mesh, pts2, {
				sides = L.tubeSides, out = out, rad = r0, tip = openTip and "open" or "dome",
				r = function(t, a)
					local tt = ta + t * span
					return sec(tt, a, tt * plen, r0) * (1 - 0.25 * tt)
				end,
				color = function(t, a, rr)
					local cr, cg, cb = pal.at(rnd, 0.5 + 0.5 * (ta + t * span), p[1])
					local k = 0.74 + 0.36 * clamp(rr, 0.5, 1.2)
					return cr * k, cg * k, cb * k
				end,
			})
		end)
	end
end

-- a ponytail: the tie band at `tie` and a bundle of clumps falling from it (HairTail01 swings from the tie,
-- HairTail01b is the lower half). spec: tie = { x, y, z }, dir = { x, y, z } (out of the tie), len, n, r0
-- (bundle radius at the tie), curly (ringlets instead of clumps), wave, tieColor
function Parts.PonyTail(H, spec)
	local S, L = H.S, H.L
	local tie, dir = spec.tie, spec.dir
	local ax, ay, az = norm3(dir[1], dir[2], dir[3])
	-- a frame round the tail axis
	local ux, uy, uz = norm3(Kit.cross(ax, ay, az, 1, 0, 0))
	local vx, vy, vz = Kit.cross(ax, ay, az, ux, uy, uz)
	local rng = MeshKit.Rng(H.seed + 91)
	local out, pal = H.out, H.pal
	local mat = { material = Parts.Material(H.htype), castShadow = true }
	local static = Parts.Piece(H, "HairTop", mat)
	local count = max(5, floor((spec.n or 40) * L.k * (0.6 + 0.6 * H.density) * (H.nScale or 1) + 0.5))
	local sides = L.sides
	local wK = (0.75 + 0.5 * H.clump) * (0.85 + 0.3 * H.thick)
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for i = 1, count do
		if Parts.Tris(H) - start > allow then
			break
		end
		local ang = rng:Range(0, TAU)
		local rad = sqrt(rng:Next()) * spec.r0
		local c, sn = cos(ang), sin(ang)
		local ox, oy, oz = ux * c + vx * sn, uy * c + vy * sn, uz * c + vz * sn
		local px, py, pz = tie[1] + ox * rad, tie[2] + oy * rad, tie[3] + oz * rad
		local rnd = rng:Next()
		local len = spec.len * (0.82 + 0.3 * rnd)
		local fan = 0.18 + 0.25 * (rad / spec.r0)
		local pts = Kit.Grow(S, px, py, pz, {
			len = len, ds = clamp(len / 14, 0.02, 0.05), dir = { ax + ox * fan, ay + oy * fan, az + oz * fan }, lift = 0,
			off = 0.02, stick = 0, grav = spec.grav or 1, stiff = 0.55, free = 0, bodyOff = 0.04,
		})
		local rs = Kit.Resample(pts, clamp(floor(Kit.Length(pts) * 22 * L.rings + 3), 4, 14))
		if spec.wave then
			rs = Kit.Wave(rs, out, spec.wave.amp * (0.7 + 0.6 * rnd), spec.wave.lam, rnd * 1.5, 0.12)
		end
		local w0 = (spec.w or 0.03) * wK * (0.75 + 0.5 * rng:Next())
		local h0 = (spec.h or 0.01) * (0.85 + 0.3 * H.thick)
		local col = Parts.ClumpColor(H, rnd, px, 0.85 + 0.25 * (rad / spec.r0))
		local twist = rng:Range(-0.6, 0.6)
		Parts.Emit(H, static, rs, 0.05, 1, "HairTail", mat, function(mesh, pts2, ta, tb, openTip, thin)
			local span = tb - ta
			Kit.Clump(mesh, pts2, {
				sides = sides, out = out, twist = twist * span, tip = openTip and "open" or "point", flat = 0.35,
				w = function(t)
					local tt = ta + t * span
					return w0 * (0.7 + 0.5 * smoothstep(0.05, 0.4, tt)) * (1 - 0.8 * smoothstep(0.65, 1, tt))
				end,
				h = function(t)
					local tt = ta + t * span
					return h0 * (1 - 0.6 * smoothstep(0.6, 1, tt))
				end,
				color = function(t, k, sa)
					return col(ta + t * span, k, sa)
				end,
			})
		end)
	end
	-- the hair tie: a band round the bundle
	local band = {}
	local br = spec.r0 * 1.05
	for k = 0, 12 do
		local a = k / 12 * TAU
		local c, sn = cos(a), sin(a)
		band[#band + 1] = { tie[1] + (ux * c + vx * sn) * br + ax * 0.01, tie[2] + (uy * c + vy * sn) * br + ay * 0.01,
			tie[3] + (uz * c + vz * sn) * br + az * 0.01 }
	end
	local tc = spec.tieColor or { 0.16, 0.15, 0.17 }
	Kit.Tube(static.mesh, band, {
		sides = 4, out = function(x, y, z)
			return norm3(x - tie[1], y - tie[2], z - tie[3])
		end, rad = 0.012, tip = "open", r = 0.012,
		color = function()
			return tc[1], tc[2], tc[3]
		end,
	})
end

-- one or two fine strands fanning out of a clump's last third (full detail only)
function Parts.TipStrands(H, piece, rs, w0, rnd, x, rng, spec)
	local n = #rs
	local i0 = max(2, floor(n * 0.55))
	local out = H.out
	local pal = H.pal
	for j = 1, (rng:Next() < 0.5 and 2 or 1) do
		local side = j == 1 and 1 or -1
		local pts = {}
		local F = Kit.Frames(rs, out)
		local fan = (0.4 + 0.6 * rng:Next()) * w0 * 1.6 * side
		local ext = 1 + 0.12 * rng:Next()
		for i = i0, n do
			local t = (i - i0) / (n - i0)
			local p, f = rs[i], F[i]
			local k = fan * t * t
			pts[#pts + 1] = { p[1] + f[4] * k + (p[1] - rs[i0][1]) * (ext - 1) * t, p[2] + f[5] * k + (p[2] - rs[i0][2]) * (ext - 1) * t,
				p[3] + f[6] * k + (p[3] - rs[i0][3]) * (ext - 1) * t }
		end
		if #pts >= 3 then
			local tw = 0.0035 * (0.8 + 0.4 * H.thick)
			Kit.Strand(Parts.Piece(H, "HairStrands", { material = "SmoothPlastic", doubleSided = true, castShadow = false }).mesh, pts, {
				w = function(t)
					return tw * (1 - 0.8 * t)
				end,
				out = out,
				color = function(t)
					local r, g, b = pal.at(rnd, 0.55 + 0.45 * t, x)
					return r * 1.05, g * 1.05, b * 1.05
				end,
			})
		end
	end
end

-- flyaways: single fine strands lifting off the silhouette (frizz), full detail only
function Parts.Flyaways(H, spec)
	if not H.L.strands then
		return
	end
	local n = floor((spec.n or 20) * (0.3 + 1.4 * H.frizz) + 0.5)
	if n <= 0 then
		return
	end
	local S = H.S
	local roots = Parts.Roots(H, n, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.5, 0.9, c)
	end, H.seed + 77)
	local piece = Parts.Piece(H, "HairStrands", { material = "SmoothPlastic", doubleSided = true, castShadow = false })
	local out, pal = H.out, H.pal
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local len = spec.len and spec.len(r) or 0.12
		local o0 = spec.off or 0.02
		local pts = Kit.Grow(S, r[1], r[2], r[3], {
			len = len, ds = len / 6, flow = spec.flow, lift = 0.35 + 0.4 * H.frizz, off = function(u)
				return o0 + u * (0.02 + 0.05 * H.frizz)
			end, stick = 0, grav = spec.grav or 0.2, stiff = 0.3,
			jitter = { amp = 0.5 + 0.6 * H.frizz, freq = 9, seed = H.seed + 5 },
		})
		local rs = Kit.Resample(pts, 6)
		local tw = 0.003 * (0.8 + 0.4 * H.thick)
		local rnd = r[9]
		Kit.Strand(piece.mesh, rs, {
			w = function(t)
				return tw * (1 - 0.75 * t)
			end,
			out = out,
			color = function(t)
				local cr, cg, cb = pal.at(rnd, 0.5 + 0.5 * t, r[1])
				return cr * 1.08, cg * 1.08, cb * 1.08
			end,
		})
	end
end

------------------------------------------------------------------------
-- Assembly
------------------------------------------------------------------------
-- scales every piece from nominal to the real head, drops empty pieces, adds the joint landmarks and the
-- HairFX metadata (mesh.hairfx) of the moving pieces, and returns the generator result
function Parts.Finish(H, fx)
	local S = H.S
	local mt = MeshKit.MatScale(S.kx, S.ky, S.kz)
	local landmarks = {}
	local function hs(p)
		return { p[1] * S.kx, p[2] * S.ky, p[3] * S.kz }
	end
	fx = fx or {}
	-- the piece limit per level (ANATOMY_CONTRACTS section 2): moving pieces beyond it join the static top
	local maxN = Parts.MAXPIECES[H.lod] or 16
	local names = {}
	for _, name in ipairs(H.order) do
		if H.pieces[name].mesh.nt > 0 then
			names[#names + 1] = name
		end
	end
	if #names > maxN then
		local fixed = { HairCap = 1, HairTop = 2, HairStrands = 3 }
		table.sort(names, function(a, b)
			local fa, fb = fixed[a] or 9, fixed[b] or 9
			if fa ~= fb then
				return fa < fb
			end
			return a < b
		end)
		local top = Parts.Piece(H, "HairTop", { material = Parts.Material(H.htype), castShadow = true })
		local keep = {}
		for i, name in ipairs(names) do
			if i <= maxN or name == "HairTop" then
				keep[#keep + 1] = name
			else
				MeshKit.Append(top.mesh, H.pieces[name].mesh)
				H.pieces[name].mesh = MeshKit.New(name)
				if H.bounce then
					H.bounce[name] = nil
				end
			end
		end
		if #keep > maxN then
			-- HairTop was created by the merge: fold the last kept moving piece in as well
			local last = keep[#keep]
			if last ~= "HairTop" then
				MeshKit.Append(top.mesh, H.pieces[last].mesh)
				H.pieces[last].mesh = MeshKit.New(last)
			end
		end
	end
	-- swinging groups: pivots / tips (means of their strands' joint points) -> joint landmarks + mesh.hairfx
	for key, grp in pairs(H.groups) do
		for s, seg in pairs(grp.segs) do
			local piece = H.pieces[seg.name]
			if piece and piece.mesh.nt > 0 and seg.piv[4] > 0 then
				local pv = { seg.piv[1] / seg.piv[4], seg.piv[2] / seg.piv[4], seg.piv[3] / seg.piv[4] }
				local tp = seg.tip[4] > 0 and { seg.tip[1] / seg.tip[4], seg.tip[2] / seg.tip[4], seg.tip[3] / seg.tip[4] } or { pv[1], pv[2] - 0.3, pv[3] }
				MeshKit.SetLandmark(piece.mesh, seg.name .. ".0", pv[1], pv[2], pv[3])
				MeshKit.SetLandmark(piece.mesh, seg.name .. ".1", tp[1], tp[2], tp[3])
				local parentSeg = s > 1 and grp.segs[s - 1] or nil
				local parent = parentSeg and H.pieces[parentSeg.name] and H.pieces[parentSeg.name].mesh.nt > 0 and parentSeg.name or nil
				piece.mesh.hairfx = {
					kind = "swing", chain = key, seg = s, parent = parent,
					stiff = fx.stiff or 0.3, mass = fx.mass or 1, pivot = hs(pv), tip = hs(tp),
				}
				-- hair hanging below a sparring headgear's rim stays visible under it (not under a hood)
				if s > 1 or grp.prefix == "HairTail" then
					piece.hideUnder = { headgear = false, hood = true }
				end
			end
		end
	end
	-- bouncing clusters (curls, coils, afros, short locs): pivot where the cluster meets the scalp
	for name in pairs(H.bounce or {}) do
		local piece = H.pieces[name]
		if piece and piece.mesh.nt > 0 and not piece.mesh.hairfx then
			local m = piece.mesh
			local P = m.P
			local sx, sy, sz = 0, 0, 0
			for i = 1, m.nv do
				sx += P[i * 3 - 2]
				sy += P[i * 3 - 1]
				sz += P[i * 3]
			end
			sx, sy, sz = sx / m.nv, sy / m.nv, sz / m.nv
			local dx, dy, dz = norm3(sx - S.cx, sy - S.cy, sz - S.cz)
			local px, py, pz = S.ray(dx, dy, dz, 0)
			MeshKit.SetLandmark(m, name .. ".0", px, py, pz)
			MeshKit.SetLandmark(m, name .. ".1", sx, sy, sz)
			m.hairfx = {
				kind = "bounce", stiff = fx.stiff or 0.6, mass = fx.mass or 1.2, pivot = hs({ px, py, pz }), tip = hs({ sx, sy, sz }),
			}
		end
	end
	local pieces = {}
	for _, name in ipairs(H.order) do
		local p = H.pieces[name]
		if p.mesh.nt > 0 then
			MeshKit.Transform(p.mesh, mt)
			p.mesh.name = name
			pieces[name] = p
		end
	end
	for name, lm in pairs(H.landmarks) do
		landmarks[name] = { part = "Head", pos = hs(lm) }
	end
	return { pieces = pieces, landmarks = landmarks }
end

return Parts
