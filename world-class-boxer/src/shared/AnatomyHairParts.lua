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
-- the Head section's skin paint (its base tone with the undertone): the scalp a cut shows matches the forehead.
-- Optional: without it the hair falls back to its own skin tone
local HeadPaint
do
	local mod = Shared:FindFirstChild("AnatomyHeadPaint")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" and type(res.Skin) == "function" then
			HeadPaint = res
		end
	end
end

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
	full = { cols = 48, rows = 22, tex = 256, sides = 5, k = 1, rings = 1, groups = 6, segs = 2, strands = true, tubeSides = 6 },
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
-- the scalp under short hair: the tone the head section paints there (its scalp comes out a little lighter
-- and less red than skinRGB: measured on its textures over every skin tone), so a shaved or faded region
-- meets the head's own skin without a seam
function Parts.ScalpTone(H)
	local r, g, b
	if HeadPaint then
		local ok, pr, pg, pb = pcall(HeadPaint.Skin, H.look)
		if ok and type(pr) == "number" and type(pg) == "number" and type(pb) == "number" then
			r, g, b = pr, pg, pb
		end
	end
	if not r then
		local sk = H.skin
		r, g, b = sk[1], sk[2], sk[3]
	end
	return clamp(r + 0.016, 0, 1), clamp(g + 0.03, 0, 1), clamp(b + 0.02, 0, 1)
end

-- texture shader for the cap: strands running along the comb flow, the scalp showing through where the
-- coverage is partial (fades, buzz cuts, partings, the hairline edge), plus the cut's pattern
local function capShader(H, spec)
	local S, cut, pal = H.S, H.cut, H.pal
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
	local stubble = pattern == "stubble"
	local wK = spec.white or (stubble and 0.45 or 0.3)
	-- isotropic mottle: strong for clipper stubble, faint under strands (whose streaks carry the texture)
	local isoK = stubble and 1 or 0.3
	local coilish = pattern == "coil" or pattern == "curl"
	-- streaks along the hair: noise in (across, across', along) coordinates of the comb flow, from the flow's
	-- own stream function (constant along a strand), per flow kind:
	--  * parted, swept, standing (part / side / up): strands at different depths (Z) fan out from the part line:
	--    across = Z, along = the angle round the front-back axis through the parting
	--  * combed back / forward: strands run in the planes through a front-back axis below the head (over the
	--    top, then back along the sides): across = the angle round that axis, along = Z
	--  * from a crown whorl or into a tie (whorl, down, tie): meridians round the axis through that point:
	--    across = the azimuth on a circle (cos, sin: no seam), along = the polar angle; faded out at the pole
	-- Across: ~30 streaks per stud (a few texels each, finer would alias into a plaid); along: long
	local streak = spec.streak or 0.35
	local fk = spec.flow or "whorl"
	local fpx = (spec.flowOpts and spec.flowOpts.x) or spec.part or 0
	local atan2 = math.atan2
	local family = (fk == "part" or fk == "side" or fk == "up") and 1 or ((fk == "back" or fk == "forward") and 2 or 3)
	-- the meridians' pole: the whorl, or the tie
	local ax, ay, az
	do
		local px, py, pz
		if fk == "tie" and spec.flowOpts and spec.flowOpts.p then
			px, py, pz = spec.flowOpts.p[1], spec.flowOpts.p[2], spec.flowOpts.p[3]
		else
			px, py, pz = Kit.Whorl(S)
		end
		ax, ay, az = norm3(px - S.cx, py - S.cy, pz - S.cz)
	end
	-- a basis across the pole axis
	local e1x, e1y, e1z = norm3(Kit.cross(ax, ay, az, 0, 0, 1))
	if e1x == 0 and e1y == 0 and e1z == 0 then
		e1x, e1y, e1z = 1, 0, 0
	end
	local e2x, e2y, e2z = Kit.cross(ax, ay, az, e1x, e1y, e1z)
	local RM = 56 / TAU
	local cxs, cys, czs = S.cx, S.cy, S.cz
	-- returns p, q (across; q only for the meridians' circle), w (along), and a fade for the pole
	local function coords(X, Y, Z)
		if family == 1 then
			return Z * 30, 0, atan2(X - fpx, Y + 0.15) * 1.8, 1
		elseif family == 2 then
			return atan2(X, Y + 0.4) * 21, 0, Z * 3.6, 1
		end
		local vx, vy, vz = X - cxs, Y - cys, Z - czs
		local d = vx * ax + vy * ay + vz * az
		local wx, wy, wz = vx - ax * d, vy - ay * d, vz - az * d
		local th = atan2(wx * e2x + wy * e2y + wz * e2z, wx * e1x + wy * e1y + wz * e1z)
		local pol = atan2(sqrt(wx * wx + wy * wy + wz * wz), d)
		return cos(th) * RM, sin(th) * RM, pol * 4.6, smoothstep(0.12, 0.35, pol)
	end
	local function streakAt(p, q, w, tx)
		local fine = aa(60, tx)
		return noise3(p, q, w + 0.5, seed + 9) + (fine > 0 and 0.5 * fine * noise3(p * 2.03, q * 2.03, w * 1.7 + 3.5, seed + 10) or 0)
	end
	-- grey hairs: thin streaks along the same flow (a strand is grey along its length), as long as the hair:
	-- short dashes in a short cut, long streaks in long hair (never broad bands)
	local greyAlong = spec.greyAlong or lerp(2.6, 0.7, smoothstep(0.1, 0.6, H.len * (spec.long and 1 or 0.3)))
	-- the undyed hair colour and the dyed one (greying is scattered through the texture below); which one a
	-- texel shows depends on the dye: an ombre by height (one line on the cap, the clumps, the sheets), split
	-- by side, streaks in bands along the flow, dyed tips on a short cut (its top IS the tips)
	local capT = spec.capT or 0.55
	local dye = pal.dye
	-- capK: the shell as the shadowed depth under clumps (darker than the hair over it)
	local capK = spec.capK or 1
	local hr, hg, hb = pal.at(0.5, capT, -1, true, 3, 1, 0)
	local ar, ag, ab = pal.at(0.1, capT, 1, true, -3, 0, 1)
	hr, hg, hb, ar, ag, ab = hr * capK, hg * capK, hb * capK, ar * capK, ag * capK, ab * capK
	local split = dye == "Split"
	local dyeY = pal.dyeY or -0.15
	local tipsK = dye == "Tips" and 0.85 * smoothstep(0.45, 0.2, H.len) or 0
	local streaky = dye == "Streaks" or (pal.hl and dye == "None")
	local greyK = pal.grey or 0
	local gr = pal.greyRGB or { 0.7, 0.69, 0.67 }
	local scR, scG, scB = Parts.ScalpTone(H)
	local wx, wy, wz = Kit.Whorl(S)
	local waveLam = spec.waveLam or 0.05
	local contrast = spec.contrast or 1
	-- on near-black hair the coil tops need an absolute lift to read at all
	local dark = clamp((0.16 - pal.lum) / 0.16, 0, 1) * 0.07
	local lightK = smoothstep(0.12, 0.4, pal.lum)
	-- coils / curls: cellular clusters (jittered Worley cells, irregular sizes) in a warped domain
	local cellF = (pattern == "coil" and 30 or 22) / grain
	local worley = coilish and Kit.Worley(H.seed % 9973 + 5) or nil
	local worley2 = coilish and Kit.Worley(H.seed % 9973 + 11) or nil
	-- clipper stubble is drawn hair by hair: each texel is hair or skin with probability = the coverage
	-- (sparse hairs, not a paint). The hairline itself is an anti-aliased edge: blended over ~1.3 texels
	-- however sharp the cut (a per-texel dither there was a sawtooth of 0.01-0.02 stud teeth along every
	-- hairline), wandering by a hair's width along the line (a line-up barely), with a few short hairs
	-- scattered ahead of it over a natural edge's softness
	local ditherAll = stubble and 0.35 or 0
	local soft = cut.soft or 0.016
	local wobA = min(0.005, soft * 0.4)
	local strayW = soft * 2.5
	local cutRest = cut.rest
	-- ao(X, Y, Z) -> 0..1: the volume's own occlusion (the crevices between a mass's clusters, its underside)
	local aoFn = spec.ao
	-- a parting: a narrow gap of shadowed scalp between the strands either side (never a skin-tone stripe)
	local partAt = cut.partAt
	local gapR, gapG, gapB = scR * 0.5, scG * 0.47, scB * 0.45
	return function(u, v, r, g, b, a, x, y, z, nx, ny, nz)
		-- 5-10 us a texel: MeshKit counts the call as 1 unit, these keep its tick on time
		step(2)
		local X, Y, Z = x / kx, y / ky, z / kz
		local c, d, _, da, hl, rest = cut.cov(X, Y, Z)
		local tx = max(texH, texW * sin(v * 2.75))
		local ix, iy = floor(u * TEX), floor(v * TEX)
		-- the hairline: the edge's own blend (over the cut's softness, at least ~1.3 texels), the line wandering
		-- a little; the stray hairs ahead of it are single texels at a falling density
		local edgeK = 1
		if d < soft * 2 then
			if d < -strayW - wobA then
				return scR, scG, scB, 1
			end
			local wob = wobA * noise3(X * 14, Y * 14, Z * 14, seed + 29)
			local eW = max(soft * 0.9, 1.3 * tx)
			local de = d + wob
			edgeK = smoothstep(-eW, eW, de)
			if de < 0 and not stubble then
				local p = 0.25 * (1 - smoothstep(0, strayW, -de))
				if p > 0 and white(ix, iy, seed + 29) < p then
					edgeK = max(edgeK, 0.8)
				end
			end
			if edgeK <= 0.002 then
				return scR, scG, scB, 1
			end
			if not rest then
				rest = cutRest(X, Y, Z, da, hl)
			end
			-- (the body of the hair at its own coverage, the edge blended over it)
			c = rest
		end
		if c <= 0.002 then
			return scR, scG, scB, 1
		end
		-- the strand coordinates here (streaks, grey strands, dye streaks)
		local cp, cq, cw, cpole = coords(X, Y, Z)
		local wn = white(ix, iy, seed) - 0.5
		local n00 = Kit.RNoise(X, Y, Z, F00, seed + 6, 1)
		local a0 = aa(F0, tx)
		local n0 = a0 > 0 and Kit.RNoise(X, Y, Z, F0, seed + 7, 2) * a0 or 0
		local sgrain
		if coilish then
			-- coils / curls make their own clusters below: only the coverage blend needs a grain here
			sgrain = clamp(0.5 + (0.3 * n00 + 0.35 * n0 + wK * wn) * 1.1, 0, 1)
		else
			-- the fine octaves only where they show (strands get their texture from the streaks)
			local n1, n2 = 0, 0
			if isoK > 0.5 then
				local a1, a2 = aa(F1, tx), aa(F2, tx)
				n1 = a1 > 0 and Kit.RNoise(X, Y, Z, F1, seed, 1) * a1 or 0
				n2 = a2 > 0 and Kit.RNoise(X, Y, Z, F2, seed + 5, 2) * a2 or 0
			end
			-- streaks along the hair for longer hair under the clumps
			local n3 = streak > 0 and clamp(streakAt(cp, cq, cw, tx) * 1.7 * cpole, -0.5, 0.5) or 0
			-- stubble grows evenly: its broad octaves stay weak (strong ones read as leopard blotches)
			local lowK = stubble and 0.35 or 1
			sgrain = clamp(0.5 + ((0.3 * n00 * lowK + 0.35 * n0 * lowK + 0.5 * n1 + 0.35 * n2) * isoK + wK * wn + streak * n3) * 1.1, 0, 1)
		end
		-- coverage as a smooth blend with the grain breaking up its middle (a fade is a gradient); clipper
		-- stubble and the hairline band dithered hair by hair
		local m = clamp(c + (sgrain - 0.5) * (stubble and 0.5 or 0.9) * c * (1 - c) * 2, 0, 1)
		if ditherAll > 0 then
			-- a texel holds a few hairs: its share scatters around the coverage (no hard salt and pepper)
			local h = white(ix, iy, seed + 29)
			m = lerp(m, smoothstep(h - 0.35, h + 0.35, c), ditherAll)
		end
		m *= edgeK
		local cr, cg, cb = hr, hg, hb
		local dk = 0
		if split then
			dk = X > 0 and 1 or 0
		elseif dye == "Ombre" then
			dk = smoothstep(dyeY + 0.12, dyeY - 0.3, Y)
		elseif tipsK > 0 then
			dk = tipsK
		elseif streaky then
			-- streaks: a share of the strand bands along the flow
			dk = smoothstep(0.35, 0.5, noise3(cp * 0.7, cq * 0.7, cw * 0.3 + 4.5, seed + 37)) * 0.7
		end
		if dk > 0 then
			cr, cg, cb = lerp(cr, ar, dk), lerp(cg, ag, dk), lerp(cb, ab, dk)
		end
		-- a light dye keeps the strand texture under it (stretched contrast, see Kit.Palette)
		local dyeSt = 1 + 0.5 * dk * (pal.dyeLight or 0)
		if greyK > 0 then
			-- salt and pepper: about greyK of the strands grey, the temples and sideburns first (by the late
			-- forties the sides are grey before the crown)
			local reg = 1 + 0.9 * smoothstep(0.22, 0.4, abs(X)) * (1 - smoothstep(0.3, 0.48, Y)) - 0.45 * smoothstep(0.38, 0.56, Y)
			local f = clamp(greyK * reg, 0, 0.92)
			-- individual grey hairs: dashes one cell across and a few along the local flow frame, each grey
			-- with probability f (an exact share, no blobs or rings)
			local ac = (family == 3 and atan2(cq, cp) * RM or cp) * 2.4
			local ga = floor(ac)
			-- dashes of random length, staggered from one line of hairs to the next (no rows)
			local hl = Kit.WhiteHash(ga, 7, seed + 33)
			local gw = floor(cw * greyAlong * (1.6 + 1.6 * hl) + 7.3 * hl)
			-- a hair is thinner than its cell: a soft line down the cell's middle
			local fr = ac - ga
			local gk = Kit.WhiteHash(ga, gw, seed + 31) < f * 0.6 and 0.3 * (1 - smoothstep(0.15, 0.5, abs(fr - 0.5))) or 0
			-- and the even grey cast of the many grey hairs too fine to draw
			gk = gk + (1 - gk) * f * 0.45
			cr, cg, cb = lerp(cr, gr[1], gk), lerp(cg, gr[2], gk), lerp(cb, gr[3], gk)
		end
		local k = (0.72 + 0.56 * sgrain * dyeSt - 0.28 * (dyeSt - 1)) * contrast + (1 - contrast)
		if stubble then
			-- clipper-short hair: each hair a dark point over the scalp; seen together a cool shadow (the
			-- hairs under the skin and their dots), not a brown paint
			k = 0.7 + 0.6 * sgrain
			cr, cg, cb = cr * 0.75 + 0.012, cg * 0.75 + 0.014, cb * 0.75 + 0.022
		elseif pattern == "waves" then
			-- brushed 360 waves: ripples spiralling out from the crown whorl. Each crest an S-curved arc across
			-- the brush direction (down and out from the crown), broken where the arcs of neighbouring sections
			-- meet; a crest is lit on its upper side with a shadowed trough under it (the painted relief of a
			-- ripple), and the whole carries the coily stipple of hair brushed flat
			local dx, dy, dz = X - wx, Y - wy, Z - wz
			local dd = sqrt(dx * dx + dy * dy + dz * dz)
			local az0 = atan2(cq, cp)
			-- a slow spiral (one arm), S-curves along each crest, sections that shift by a part of a ripple
			local sec = noise3(cos(az0) * 1.6, sin(az0) * 1.6, dd * 2.5, seed + 41)
			local ph = dd / waveLam + az0 / TAU + 0.28 * sin(az0 * 5 + dd * 9) + 0.45 * sec
			local fr = ph - floor(ph)
			-- asymmetric ripple: a quick rise to the crest, a long fall into the trough
			local w = fr < 0.35 and smoothstep(0, 0.35, fr) or (1 - smoothstep(0.35, 1, fr))
			local edge = smoothstep(0.08, 0.3, dd)
			k *= 1 + (0.34 * w - 0.17) * edge * cpole
			-- the stipple of tight coils brushed flat (finer than the ripples, never in rows)
			k *= 0.9 + 0.22 * white(ix + 3, iy + 7, seed + 51)
		elseif coilish then
			-- coil clusters: lighter coil tops in the middle of each cluster, dark crevices between them, the
			-- clusters irregular (jittered cells of random size in a domain warped by ~0.1 studs)
			local wxo = Kit.RNoise(X, Y, Z, 4.3, seed + 21, 2) * 0.1
			local wzo = Kit.RNoise(Z, X, Y, 4.3, seed + 22, 1) * 0.1
			local wyo = Kit.RNoise(Y, Z, X, 4.3, seed + 23, 2) * 0.06
			local f1, f2, id = worley((X + wxo) * cellF, (Y + wyo) * cellF, (Z + wzo) * cellF)
			local rad = 0.6 + 0.8 * id
			local top = 1 - smoothstep(0.05, 0.62 * rad, f1)
			-- the gaps between clusters: soft pores, not a network of cracks
			local crev = smoothstep(0.0, 0.2, f2 - f1)
			-- single coils inside a cluster: a finer cellular octave
			local cellAA = aa(cellF * 0.6, tx)
			local fine = aa(cellF * 1.4, tx)
			local top2 = 1
			if fine > 0 then
				local g1 = worley2((X + wzo) * cellF * 2.3, (Y + wxo) * cellF * 2.3, (Z + wyo) * cellF * 2.3)
				top2 = lerp(1, 0.78 + 0.34 * (1 - smoothstep(0.05, 0.55, g1)), fine)
			end
			-- the cell scale nears a texel far from the crown: fade the cells to their mean there. Gentle: the
			-- clusters read as a soft, fuzzy unevenness, not as cells with outlines (cracked mud)
			local q = lerp(0.72, (0.76 + 0.24 * crev) * (0.78 + 0.32 * top) * top2, cellAA)
			-- broad, gentle variation (a weak low octave: no blotches) and a fine speckle of coil highlights
			q *= 1 + 0.1 * Kit.RNoise(X, Y, Z, 7, seed + 11, 2) + 0.3 * wn
			-- coverage shows the scalp between clusters first: no crevice darkening where the fade thins
			q = lerp(0.75, q, smoothstep(0.4, 0.8, c))
			k = lerp(0.3 + 1.05 * q, 0.6 + 0.6 * q, lightK)
			if aoFn then
				k *= aoFn(X, Y, Z)
			end
			local lift = dark * q
			-- dense coils hide the scalp until the coverage is nearly full: the lower fade shows skin
			m = m ^ 1.6
			return lerp(scR, cr * k + lift, m), lerp(scG, cg * k + lift * 0.82, m), lerp(scB, cb * k + lift * 0.62, m), 1
		end
		if aoFn then
			k *= aoFn(X, Y, Z)
		end
		local orr, og, ob = lerp(scR, cr * k, m), lerp(scG, cg * k, m), lerp(scB, cb * k, m)
		if partAt then
			local gp = partAt(X, Y, Z, tx)
			if gp > 0 then
				gp *= 0.85
				orr, og, ob = lerp(orr, gapR, gp), lerp(og, gapG, gp), lerp(ob, gapB, gp)
			end
		end
		return orr, og, ob, 1
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
		fadeLift = spec.fadeLift, thin = spec.thin, emerge = spec.emerge,
		-- (a volume's dilated grid has no hairline row: its shell sinks over a longer run)
		sinkW = spec.sinkW or (spec.radial and 0.07 or 0.03),
		-- the cap texture's texel across a parting over the top of the head (capShader's texW at ~45 degrees
		-- from the crown): the parting's thinning of the coverage is drawn at what the texture holds
		partTx = H.L.tex and 0.56 * TAU / H.L.tex * 0.75 or nil,
	})
	local L = H.L
	local name = spec.name or "HairCap"
	local piece = Parts.Piece(H, name, {
		material = spec.material or "Plastic", castShadow = true, reflectance = spec.reflectance,
	})
	local pal = H.pal
	local capK = spec.capK or 1
	local hr, hg, hb = pal.at(0.5, spec.capT or 0.55, -1, nil, 3, 1, 0)
	local ar, ag, ab = pal.at(0.1, spec.capT or 0.55, 1, nil, -3, 0, 1)
	hr, hg, hb, ar, ag, ab = hr * capK, hg * capK, hb * capK, ar * capK, ag * capK, ab * capK
	local dye = pal.dye
	local split = dye == "Split"
	local dyeY = pal.dyeY or -0.15
	local tipsK = dye == "Tips" and 0.85 * smoothstep(0.45, 0.2, H.len) or 0
	local scR, scG, scB = Parts.ScalpTone(H)
	local cols = spec.cols or L.cols
	local rows = spec.rows or L.rows
	Kit.Cap(S, piece.mesh, {
		cut = H.cut, cols = cols, rows = rows, extra = spec.extra, reach = spec.reach, gridNormals = spec.gridNormals, radial = spec.radial,
		inset = spec.inset,
		color = function(x, y, z, c)
			local k = smoothstep(0.05, 0.95, c)
			local dk = split and (x > 0 and 1 or 0) or (dye == "Ombre" and smoothstep(dyeY + 0.12, dyeY - 0.3, y) or tipsK)
			local r, g, b = lerp(hr, ar, dk), lerp(hg, ag, dk), lerp(hb, ab, dk)
			if spec.ao then
				local o = spec.ao(x, y, z)
				r, g, b = r * o, g * o, b * o
			end
			return lerp(scR, r, k), lerp(scG, g, k), lerp(scB, b, k)
		end,
	})
	if L.tex then
		-- pad: the texels round the cap's UV islands (culled shaved quads leave big empty areas) take the edge
		-- colours, so filtering and the far mip levels never pull in black. (256 at full detail: the hairline is
		-- the shader's anti-aliased edge, smooth at that size; a 512 cap cost 4-7x the paint time and 1 MB a head)
		piece.texture = { w = L.tex, h = L.tex, shade = capShader(H, spec), pad = L.tex >= 256 and 10 or 6 }
	end
	return piece
end

------------------------------------------------------------------------
-- Roots
------------------------------------------------------------------------
-- about n root points spread evenly over the scalp (a jittered golden-angle lattice), each kept with
-- probability accept(x, y, z, da, cov) (0..1), or, with `even`, kept wherever accept >= 0.5 (an even spread
-- over the accepted region: braids on their rows, never a bare patch where the dice fell).
-- Returns { { x, y, z, nx, ny, nz, da, cov, rnd } }.
function Parts.Roots(H, n, accept, seed, jit, even)
	local S, cut = H.S, H.cut
	local rng = MeshKit.Rng(seed or H.seed + 1)
	-- jit: how far each point strays from its lattice place (1 = even spacing; more = uneven, clustered)
	jit = jit or 1
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
		-- a scalp ray, the cut's coverage (a hairline window search near the ears) and the accept callback
		step(6)
	end
	local frac = max(sum / M0, 0.01)
	local M = max(4, ceil(n / frac))
	local out = {}
	for i = 1, M do
		local jx, jy = rng:Range(-0.3, 0.3) * jit, rng:Range(-0.35, 0.35) * jit
		local x, y, z, nx, ny, nz, da, c = point(M, i, jx, jy)
		local p = clamp(accept(x, y, z, da, c), 0, 1)
		if even then
			if p >= 0.5 then
				out[#out + 1] = { x, y, z, nx, ny, nz, da, c, rng:Next() }
			end
		elseif p > 0 and rng:Next() < p then
			out[#out + 1] = { x, y, z, nx, ny, nz, da, c, rng:Next() }
		end
		step(6)
	end
	-- shuffled: a component that stops at its triangle budget thins its strands evenly over the scalp
	for i = #out, 2, -1 do
		local j = rng:Int(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- triangles a strand pass may add: spec.tris, or spec.share of what the shells (the cap, sheets and volumes,
-- built first: fixed cost) leave of the section's budget, so a pass that runs late is never starved by the
-- ones before it; spec.rest = whatever is still left; spec.reserve = keep that many for later passes
function Parts.Allow(H, spec)
	if spec.tris then
		return spec.tris * (H.nScale or 1)
	end
	local total = H.budget * 0.97 * (H.nScale or 1)
	local used = Parts.Tris(H)
	if not H.passBase then
		H.passBase = max(0, total - used)
	end
	local left = max(0, total - used - (spec.reserve or 0))
	if spec.rest then
		return left
	end
	return min(left, H.passBase * (spec.share or 0.5))
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
-- the nominal height along a resampled strand at parameter t (0 root .. 1 tip)
function Parts.YAt(rs)
	local n = #rs
	return function(t)
		local s = clamp(t, 0, 1) * (n - 1) + 1
		local i = min(n - 1, floor(s))
		local u = s - i
		return rs[i][2] + (rs[i + 1][2] - rs[i][2]) * u
	end
end

-- Greying: the clump's base colour stays ungreyed and one strand-line of its section (one vertex round
-- the section, sometimes two) runs grey along it, the rest only a touch (a few grey hairs in every lock).
-- y(t) -> nominal height at t (optional: dye lines by height)
-- uniform: one tone along the clump (its strand parameter fixed at that t: tufts in the cap's own colour)
function Parts.ClumpColor(H, rnd, x, layerK, sides, yAt, len, uniform)
	local pal = H.pal
	local grey = pal.grey or 0
	local gr = pal.greyRGB
	sides = sides or 5
	local g1 = 1 + floor(((rnd * 13.37) % 1) * sides)
	local g2 = ((rnd * 7.77) % 1) < grey * 1.6 and (1 + (g1 + floor(sides / 2)) % sides) or -1
	local strong = min(0.4, grey * 1.0)
	return function(t, k, s)
		-- a streak / highlight runs down the clump's outer face only
		local r, g, b = pal.at(rnd, uniform or t, x, true, yAt and yAt(t), len and (1 - t) * len, s > 0.3 and 1 or 0.2)
		if grey > 0 then
			-- an even tint (the lock's mix of hairs) and one or two finer grey lines along it
			local gk = (k == g1 or k == g2) and strong or (k == 0 and grey * 0.6 or grey * 0.4)
			r, g, b = lerp(r, gr[1], gk), lerp(g, gr[2], gk), lerp(b, gr[3], gk)
		end
		-- (a uniform tuft lying on the shell: its underside barely darker - dark undersides read as specks)
		local sh = (s >= 0 and (0.93 + 0.13 * s) or (0.93 + (uniform and 0.08 or 0.33) * s)) * layerK
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
	-- (castShadow = false: short tufts lying on a shell would speckle it with their shadows)
	local mat = { material = spec.material or Parts.Material(H.htype), castShadow = spec.castShadow ~= false, reflectance = spec.reflectance }
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
			local col = Parts.ClumpColor(H, rnd, x, (spec.layerK or 1) * (0.9 + 0.2 * rng:Next()), sides, Parts.YAt(rs), plen, spec.uniform)
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

-- one side of a sheet over a grid of points G[c][i] (c across, i along the strands), columns c0..c1 (every
-- `stride`-th, the last always), rings i0..i1: side = 1 the outer face at +d along the sheet's normal, -1 the
-- inner face at -d; lift(c, i) -> extra outward offset of the outer face (locks: ridges and grooves; normals
-- from the lifted surface so they shade); colour(c, t, y, side) -> r, g, b; tFn(i) -> t (0 root .. 1 tip);
-- linked(cA, cB, i) -> false where the columns cA..cB have parted between rings i and i + 1 (no quad there)
local function sheetSide(m, G, c0, c1, i0, i1, d, out, colour, tFn, side, stride, lift, linked)
	local N = m.N
	local vertex, tri = MeshKit.Vertex, MeshKit.Tri
	stride = stride or 1
	local cl = {}
	for c = c0, c1, stride do
		cl[#cl + 1] = c
	end
	if cl[#cl] ~= c1 then
		cl[#cl + 1] = c1
	end
	local ncol, nrow = #cl, i1 - i0 + 1
	if ncol < 2 or nrow < 2 then
		return
	end
	-- the sheet's base normal at (c, i) from the unlifted grid (outward)
	local function baseNormal(c, i)
		local col = G[c]
		local cp, cn = G[max(c0, c - 1)], G[min(c1, c + 1)]
		local pp, pn = col[max(i0, i - 1)], col[min(i1, i + 1)]
		local ax, ay, az = pn[1] - pp[1], pn[2] - pp[2], pn[3] - pp[3]
		local bx, by, bz = cn[i][1] - cp[i][1], cn[i][2] - cp[i][2], cn[i][3] - cp[i][3]
		local nx, ny, nz = norm3(Kit.cross(ax, ay, az, bx, by, bz))
		local p = col[i]
		local ox, oy, oz = out(p[1], p[2], p[3])
		if nx * ox + ny * oy + nz * oz < 0 then
			nx, ny, nz = -nx, -ny, -nz
		end
		if nx == 0 and ny == 0 and nz == 0 then
			nx, ny, nz = ox, oy, oz
		end
		return nx, ny, nz
	end
	-- positions first (normals of a lifted face need the neighbours)
	local PX, PY, PZ, BN = {}, {}, {}, {}
	for k, c in ipairs(cl) do
		for i = i0, i1 do
			local p = G[c][i]
			local nx, ny, nz = baseNormal(c, i)
			-- (the lift bulges the outer face out and, given an inner lift, the inner face in: a lock with a
			-- lens cross-section, not a ribbon)
			local off = d * side + (lift and lift(c, i) or 0) * side
			local o = (k - 1) * nrow + (i - i0) + 1
			PX[o], PY[o], PZ[o] = p[1] + nx * off, p[2] + ny * off, p[3] + nz * off
			BN[o] = { nx, ny, nz }
		end
	end
	local first = m.nv + 1
	for k, c in ipairs(cl) do
		for i = i0, i1 do
			local o = (k - 1) * nrow + (i - i0) + 1
			local nx, ny, nz = BN[o][1], BN[o][2], BN[o][3]
			if side > 0 and lift then
				-- the lifted surface's own normal (across x along), kept on the outer side
				local kp, kn = max(1, k - 1), min(ncol, k + 1)
				local ip, inn = max(i0, i - 1), min(i1, i + 1)
				local a1 = (k - 1) * nrow + (inn - i0) + 1
				local a0 = (k - 1) * nrow + (ip - i0) + 1
				local b1 = (kn - 1) * nrow + (i - i0) + 1
				local b0 = (kp - 1) * nrow + (i - i0) + 1
				local lx, ly, lz = norm3(Kit.cross(PX[a1] - PX[a0], PY[a1] - PY[a0], PZ[a1] - PZ[a0], PX[b1] - PX[b0], PY[b1] - PY[b0], PZ[b1] - PZ[b0]))
				if lx * nx + ly * ny + lz * nz < 0 then
					lx, ly, lz = -lx, -ly, -lz
				end
				if lx ~= 0 or ly ~= 0 or lz ~= 0 then
					nx, ny, nz = lx, ly, lz
				end
			end
			local r, g, b = colour(c, tFn(i), PY[o], side)
			local v = vertex(m, PX[o], PY[o], PZ[o], (k - 1) / (ncol - 1), tFn(i), r, g, b)
			N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = nx * side, ny * side, nz * side
		end
	end
	-- winding: outward for the outer sheet, inward for the inner one, decided per quad from its diagonals
	-- against its vertex normals (a strip whose first quad is degenerate - columns meeting at a root - or
	-- that folds must not turn its whole side inside out and vanish to back-face culling)
	local P = m.P
	for c = 0, ncol - 2 do
		for i = 0, nrow - 2 do
			if linked and not linked(cl[c + 1], cl[c + 2], i0 + i) then
				continue
			end
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
	step(ncol * nrow * 6)
end

-- a two-sided sheet (outer face lifted by `lift`, the inner one every `innerStride`-th column)
local function sheet(m, G, c0, c1, i0, i1, d, out, colour, tFn, lift, innerStride, innerLift, linked)
	sheetSide(m, G, c0, c1, i0, i1, d, out, colour, tFn, 1, 1, lift, linked)
	sheetSide(m, G, c0, c1, i0, i1, d, out, colour, tFn, -1, innerStride or 1, innerLift, linked)
end

-- Curtain: the continuous mass of long hair (nothing shows through between the clumps): columns of strands
-- around the head from azimuth az0 to az1 (Kit.Cap convention: 0 = the back, +pi/2 = the right), each grown
-- like a clump, joined into a two-sided sheet. spec: cols (at full), az0, az1, th(az) -> root polar angle,
-- len(az, rnd) -> studs, flow, off(u), grav, stick, stiff, shade, innerShade, hang = { prefix } (swinging
-- groups as in Clumps), wave, bodyOff, half (half thickness), innerStride (the unseen inner face coarser),
-- locks = { w (columns per lock, >= 3), amp (ridge height at length), root (at the roots), pointK } -> the outer
-- face rises in a rounded ridge per lock with a groove between locks (its normals from the ridged surface:
-- the locks shade like sculpted hair), each lock longer in its middle (pointed lock ends, an uneven hem), the
-- grooves darker and the crowns lighter, a fine strand streak from column to column; layers = { k1, k2, .. }
-- (a layered cut: every lock's length scaled by one of them), round (a semicircular bundle across each lock, its
-- grooves darker), inner (the inner face bulges too: a lens-shaped lock); split (studs: columns drifting further
-- apart than that part from there on)
function Parts.Curtain(H, spec)
	local S, L = H.S, H.L
	local lodK = H.lod == "full" and 1 or (H.lod == "medium" and 0.6 or 0.4)
	local locks = spec.locks
	local cols = max(5, floor((spec.cols or 22) * lodK + 0.5))
	local lw = locks and max(3, floor(locks.w * (H.lod == "full" and 1 or 0.75) + 0.5)) or 1
	local rings = spec.rings or max(4, floor((spec.rings0 or 14) * L.rings + 0.5))
	local out = H.out
	local rng = MeshKit.Rng(H.seed + 501)
	local G, info = {}, {}
	-- the lock profile across its columns: 0 at the groove column, 1 at the lock's middle
	local function ridgeOf(c)
		if not locks then
			return 1
		end
		if locks.round then
			-- (a rounded bundle: a semicircle across the lock, its crest column in the middle)
			local u = 2 * ((c - 1) % lw) / lw - 1
			return math.sqrt(max(0, 1 - u * u))
		end
		return sin(pi * (((c - 1) % lw) / lw)) ^ 0.8
	end
	local lockRnd = {}
	for c = 1, cols do
		local az = lerp(spec.az0, spec.az1, (c - 1) / (cols - 1))
		local th = spec.th(az)
		local x, y, z = Kit.ScalpAt(H.S, az, th, 0)
		local rnd = rng:Next()
		local len = spec.len(az, rnd)
		local ridge = ridgeOf(c)
		if locks then
			local lid = floor((c - 1) / lw)
			lockRnd[lid] = lockRnd[lid] or rng:Next()
			local jag = locks.jag or 0.07
			len *= (1 - (locks.pointK or 0.15) * (1 - ridge)) * (1 - jag + 2 * jag * lockRnd[lid])
			if locks.layers then
				-- layered cut: each lock ends on one of a few length layers (its own, from its random)
				local ly = locks.layers
				len *= ly[1 + floor(((lockRnd[lid] * 7.13) % 1) * #ly)]
			end
		end
		local pts, leftAt = Kit.Grow(S, x, y, z, {
			len = len, ds = clamp(len / 14, 0.02, 0.05), flow = spec.flow, lift = 0, off = spec.off, stick = spec.stick or 0.95,
			grav = spec.grav or 1, stiff = spec.stiff or 0.2, bodyOff = spec.bodyOff or 0.03, free = spec.free,
		})
		if spec.bend then
			pts = spec.bend(pts)
		end
		if spec.clipY then
			-- combed hair ends where the head turns under (never hanging past the nape)
			for i = 3, #pts do
				if pts[i][2] < spec.clipY then
					pts = table.move(pts, 1, i, 1, {})
					break
				end
			end
		end
		local rs = Kit.Resample(pts, rings)
		if spec.wave then
			rs = Kit.Wave(rs, out, spec.wave.amp, spec.wave.lam, spec.wave.phase and spec.wave.phase({ x, y, z, 0, 0, 0, 0, 0, rnd }) or 0, spec.wave.rise or 0.2)
		end
		G[c] = rs
		info[c] = { left = leftAt and (leftAt - 1) / (#pts - 1) or 1, x = x, z = z, rnd = rnd, len = len, ridge = ridge,
			crest = (c - 1) % lw == floor(lw / 2) }
	end
	-- swinging group per column: a lock's columns stay together (the group of its middle column)
	for c = 1, cols do
		local mid = locks and min(cols, (floor((c - 1) / lw)) * lw + floor(lw / 2) + 1) or c
		local q = G[mid][1]
		info[c].g = Parts.GroupKey(H, q[1], q[3])
	end
	local pal = H.pal
	local shade = spec.shade or 0.66
	local innerShade = spec.innerShade or shade * 0.75
	-- strand streaks: the columns' tones scatter by +-streakK
	local streakK = spec.streakK or 0.12
	local colour = function(c, t, y, side)
		local inf = info[c]
		-- a streak / highlight is a fine band on a lock's crest, not the whole lock
		local r, g, b = pal.at(inf.rnd, t, inf.x, nil, y, (1 - t) * inf.len, (inf.crest and side ~= -1) and 0.85 or 0.2)
		local k
		if side and side < 0 then
			k = innerShade * (0.9 + 0.2 * inf.rnd)
			if locks and locks.inner then
				-- (a lens-shaped lock: its inner face's grooves dark too)
				k *= lerp(0.72, 1.06, inf.ridge ^ 0.7)
			end
		else
			-- crowns lighter, grooves darker; a fine streak from column to column
			k = shade * (locks and (locks.round and lerp(0.56, 1.07, inf.ridge ^ 0.7) or lerp(0.7, 1.07, inf.ridge)) or 1)
				* (1 - streakK + 2 * streakK * inf.rnd) * (c % 2 == 0 and 1.03 or 0.97)
		end
		return r * k, g * k, b * k
	end
	local lift, innerLift
	if locks then
		local amp, root = locks.amp or 0.012, locks.root or 0.002
		lift = function(c, i)
			local t = (i - 1) / (rings - 1)
			return info[c].ridge * (root + (amp - root) * smoothstep(0.05, 0.45, t))
		end
		if locks.inner then
			-- the inner face bulges too (locks.inner of the outer ridge): a lock is a bundle with a lens
			-- cross-section, its grooves open on both faces
			local inner = locks.inner
			innerLift = function(c, i)
				return lift(c, i) * inner
			end
		end
	end
	-- split (studs, at spec.cols columns): neighbouring columns that drift further apart than that (a short lock
	-- beside a long one at the hem, strands parted by the shoulders and the back) part for the rest of their
	-- length - no stretched quad bridging them as a flat panel; the lock ends hang free. Fewer columns (a lower
	-- detail) start further apart: the distance scales with their spacing, or every column pair would part
	local linked
	if spec.split then
		local sp = spec.split * (spec.cols or 22) / cols
		local split2 = sp * sp
		local splitAt = {}
		for c = 1, cols - 1 do
			local at = rings + 1
			local A, B = G[c], G[c + 1]
			for i = 2, rings do
				local a, b = A[i], B[i]
				local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
				if dx * dx + dy * dy + dz * dz > split2 then
					at = i
					break
				end
			end
			splitAt[c] = at
		end
		linked = function(cA, cB, i)
			for c = cA, cB - 1 do
				if i + 1 >= splitAt[c] then
					return false
				end
			end
			return true
		end
	end
	local innerStride = spec.innerStride or 1
	local d = spec.half or 0.005
	local mat = { material = spec.material or Parts.Material(H.htype), castShadow = true }
	local static = Parts.Piece(H, spec.piece or "HairTop", mat)
	local tF = function(i)
		return (i - 1) / (rings - 1)
	end
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
			sheet(static.mesh, G, c, cEnd, 1, ki + 1, d, out, colour, tF, lift, innerStride, innerLift, linked)
			if L.segs >= 2 and rings - ki >= 5 then
				local mid = ki + floor((rings - ki) / 2)
				local p1, s1 = Parts.GroupPiece(H, spec.hang.prefix or "HairClump", g, 1, mat)
				local p2, s2 = Parts.GroupPiece(H, spec.hang.prefix or "HairClump", g, 2, mat)
				sheet(p1.mesh, G, c, cEnd, ki, mid + 1, d * 0.9, out, colour, tF, lift, innerStride, innerLift, linked)
				sheet(p2.mesh, G, c, cEnd, mid, rings, d * 0.85, out, colour, tF, lift, innerStride, innerLift, linked)
				for k = c, cEnd do
					local q0, q1, q2 = G[k][ki], G[k][mid], G[k][rings]
					acc(s1.piv, q0[1], q0[2], q0[3])
					acc(s1.tip, q1[1], q1[2], q1[3])
					acc(s2.piv, q1[1], q1[2], q1[3])
					acc(s2.tip, q2[1], q2[2], q2[3])
				end
			else
				local p1, s1 = Parts.GroupPiece(H, spec.hang.prefix or "HairClump", g, 1, mat)
				sheet(p1.mesh, G, c, cEnd, ki, rings, d * 0.9, out, colour, tF, lift, innerStride, innerLift, linked)
				for k = c, cEnd do
					local q0, q2 = G[k][ki], G[k][rings]
					acc(s1.piv, q0[1], q0[2], q0[3])
					acc(s1.tip, q2[1], q2[2], q2[3])
				end
			end
		else
			sheet(static.mesh, G, c, cEnd, 1, rings, d, out, colour, tF, lift, innerStride, innerLift, linked)
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
	-- locs: matted, lumpy, a little flattened, thinner at the root, tapering into a frayed, pointed end
	loc = function(seed, _, ringsPer)
		-- the lumps at what the rings can carry (>= 2.5 rings a lump: finer ones averaged out to a smooth
		-- tube, the clay sausage), a slow swell / pinch along its length: no two locs the same tube
		local lf = min(6, (ringsPer or 13) / 2.6)
		return function(t, a, s, r)
			local lump = 1 + 0.2 * noise3(s * lf, cos(a) * 1.2, sin(a) * 1.2, seed) + 0.07 * noise3(s * lf * 1.9, cos(a) * 2, sin(a) * 2, seed + 3)
				+ 0.14 * noise3(s * 2.2, 0.5, 0.5, seed + 7)
			return r * lump * (0.7 + 0.3 * smoothstep(0, 0.04, s)) * (1 - 0.1 * t) * (1 - 0.55 * smoothstep(0.82, 1, t))
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
			-- (the two strands unravel into a thinner, frayed end)
			local taper = (1 - 0.3 * smoothstep(0.7, 1, t)) * (1 - 0.4 * smoothstep(0.88, 1, t))
			local swell = 1 + 0.08 * noise3(s * 3, 0.5, 0.5, seed + 5)
			return Kit.Rope(a, s / period, r * 0.45 * taper, r * 0.58 * taper) * (0.8 + 0.2 * smoothstep(0, 0.04, s)) * swell
		end
	end,
}

-- Round strands (locs, braids, twists). spec: n, accept, len(r), r (base radius), section (Parts.SECTIONS key),
-- period (braids / twists: studs per crossing), flow, flowFor(r) (a root's own flow, or nil for flow), lift, stick,
-- grav, stiff, free, off(u, r, r0, len), hang = { prefix }, dir(r) -> initial direction, seed, tip ("dome" |
-- "point"), ringsPer (rings per stud), ringsGlued (rings per stud over the run lying on the scalp, when it
-- differs), sinkRoot (the root that many radii under the scalp), shade, sides, hangSides (the swinging segments'
-- sides, when fewer), bend, hangLen(r) (the strand's length is its run over the scalp - grown once to find where
-- it leaves it, len(r) then only has to reach that far - plus this), order(r) (roots built in increasing order:
-- the ones a triangle budget may leave out last), roots (a ready root list in Parts.Roots' format instead)
function Parts.Tubes(H, spec)
	local S, L = H.S, H.L
	local count = max(spec.minN or 3, floor((spec.n or 30) * (spec.lodK and spec.lodK[H.lod] or L.k) * (0.6 + 0.6 * H.density) * (H.nScale or 1) + 0.5))
	local roots = spec.roots or Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.4, 0.8, c)
	end, (spec.seed or 0) + H.seed + 31, spec.rootJitter, spec.rootsEven)
	if spec.order then
		local key = {}
		for _, r in ipairs(roots) do
			key[r] = spec.order(r)
		end
		table.sort(roots, function(a, b)
			if key[a] ~= key[b] then
				return key[a] < key[b]
			end
			return a[9] < b[9]
		end)
	end
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
		if spec.rVar then
			-- thick and thin locs (log-normal-ish: most near the mean, a few much thicker or thinner)
			r0 *= math.exp(spec.rVar * 1.15 * (rng:Next() + rng:Next() + rng:Next() - 1.5))
		end
		local gopts = {
			len = len, ds = clamp(len / 14, 0.015, 0.05), flow = spec.flowFor and spec.flowFor(r) or spec.flow, lift = spec.lift or 0,
			off = function(u)
				return spec.off and spec.off(u, r, r0, len) or (r0 * 0.9 + 0.008)
			end, stick = spec.stick or 0.7, grav = spec.grav or 1, stiff = spec.stiff or 0.4, free = spec.free,
			bodyOff = (spec.bodyOff or 0.02) + r0, dir = spec.dir and spec.dir(r) or nil,
			jitter = spec.jitter and { amp = spec.jitter.amp, freq = spec.jitter.freq, seed = H.seed + 7 } or nil,
		}
		local pts, leftAt = Kit.Grow(S, x, y, z, gopts)
		if spec.hangLen then
			-- a braid rooted at the front hairline runs over the whole skull before it hangs, one at the nape
			-- hangs at once: the same hanging length below wherever each leaves the scalp
			local run = Kit.Length(leftAt and table.move(pts, 1, leftAt, 1, {}) or pts)
			len = run + spec.hangLen(r)
			gopts.len, gopts.ds = len, clamp(len / 14, 0.015, 0.05)
			pts, leftAt = Kit.Grow(S, x, y, z, gopts)
		end
		if spec.bend then
			pts = spec.bend(pts, r)
		end
		if spec.sinkRoot and #pts >= 3 then
			-- the root under the skin (sinkRoot x the radius): the strand comes out of the scalp, no open end
			-- standing on it
			local p, k = pts[1], spec.sinkRoot * r0
			pts[1] = { p[1] - r[4] * k, p[2] - r[5] * k, p[3] - r[6] * k }
		end
		local plen = Kit.Length(pts)
		local ringsPer = (spec.ringsPer or 22) * L.rings
		local ringsGlued = spec.ringsGlued and spec.ringsGlued * L.rings
		if kind == "plain" then
			-- far away: the silhouette of more strands beats the smoothness of each
			ringsPer = 4.5
		elseif kind == "boxbraid" then
			-- a slim cord: its own (low) ring count, no modelled weave
			ringsPer = (spec.ringsPer or 9) * L.rings
		elseif kind ~= "loc" and H.lod == "full" then
			-- the weave needs ~4 rings per crossing to read
			ringsPer = max(ringsPer, 4.2 / period)
		elseif kind ~= "loc" then
			ringsPer = max(ringsPer, 2.2 / period)
		end
		local rings = clamp(floor(plen * ringsPer + 2.5), 3, spec.maxRings or 60)
		local rs
		local leftFrac = leftAt and (leftAt - 1) / (#pts - 1)
		if ringsGlued and kind ~= "plain" and (not leftAt or leftAt > #pts - 2) then
			-- lying on the scalp (all but its last step)
			rs = Kit.Resample(pts, clamp(floor(plen * ringsGlued + 2.5), 3, spec.maxRings or 60))
		elseif ringsGlued and leftAt and leftAt >= 3 and kind ~= "plain" then
			-- a thin cord glued over the skull needs rings enough to bend with it (ringsGlued a stud there),
			-- the hanging part fewer: resampled in two runs meeting where the strand leaves the scalp
			local A = table.move(pts, 1, leftAt, 1, {})
			local B = table.move(pts, leftAt, #pts, 1, {})
			local la, lb = Kit.Length(A), Kit.Length(B)
			local na = clamp(floor(la * ringsGlued + 1.5), 2, 40)
			local nb = clamp(floor(lb * ringsPer + 1.5), 2, spec.maxRings or 60)
			rs = Kit.Resample(A, na)
			local rb = Kit.Resample(B, nb)
			for i = 2, nb do
				rs[#rs + 1] = rb[i]
			end
			leftFrac = (na - 1) / (#rs - 1)
		else
			rs = Kit.Resample(pts, rings)
		end
		if spec.wave and H.lod ~= "low" then
			-- a gentle S-bend down the length (never ruler-straight)
			rs = Kit.Wave(rs, out, spec.wave.amp * (0.6 + 0.8 * rnd), spec.wave.lam * (0.8 + 0.4 * rng:Next()), rnd * TAU, spec.wave.rise or 0.15)
		end
		local sec
		if kind == "plain" then
			sec = function(t, a, s2, rr)
				return rr * (0.8 + 0.2 * smoothstep(0, 0.05, s2)) * (1 - 0.2 * t)
			end
		elseif kind == "loc" then
			sec = Parts.SECTIONS.loc(seed + floor(rnd * 997), nil, ringsPer)
		elseif kind == "boxbraid" then
			sec = function(t, a, s2, rr)
				-- thinner where it leaves its square parting, tapering into the sealed end
				return rr * (0.85 + 0.15 * smoothstep(0, 0.03, s2)) * (1 - 0.25 * smoothstep(0.8, 1, t))
			end
		else
			sec = Parts.SECTIONS[kind](seed, period * (0.92 + 0.16 * rnd))
		end
		local phase = rnd * 3
		local shade = (spec.shade or 1) * (0.9 + 0.2 * rng:Next())
		local yAt = Parts.YAt(rs)
		local frizz = spec.frizz or 0
		local function colour(t, a, rr)
			local cr, cg, cb = pal.at(rnd, t, x, nil, yAt(t), (1 - t) * plen)
			-- crevices between lumps / braid lobes darker, the outer face lighter (a loc's pinches darker still:
			-- its segments read even where the rings smooth them)
			local k = shade * (0.78 + 0.32 * clamp(rr, 0.5, 1.25) - 0.08 * (1 - sin(a)) * 0.5)
			if kind == "loc" then
				k *= 0.86 + 0.24 * clamp(rr, 0.6, 1.2)
			end
			if frizz > 0 then
				-- matted, frizzy surface: a light fuzz of uneven tone along and round the loc
				k *= 1 + frizz * noise3(t * plen * 30, cos(a) * 1.5, sin(a) * 1.5, seed + floor(rnd * 97))
			end
			return cr * k, cg * k, cb * k
		end
		local g = spec.hang and leftAt and Parts.GroupKey(H, x, z, da)
		Parts.Emit(H, static, rs, leftFrac, g, spec.hang and spec.hang.prefix or "HairLoc", mat,
			function(mesh, pts2, ta, tb, openTip, thin)
				local span = tb - ta
				Kit.Tube(mesh, pts2, {
					sides = (ta > 0 and spec.hangSides) or sides, out = out, rad = r0, tip = openTip and "open" or (spec.tip or "dome"),
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
-- hang = { prefix } (long ringlets swing), perTurn, piece, bounce (piece name for a bouncing cluster group),
-- ply (coils per clump, wound round one another), inside (a volume's SDF the roots lie in) with hangLen(r) (how
-- far the clump hangs past where it comes out of it) and shell (the field of the mass's visible surface,
-- Parts.Volume's second result: the clump is built from where it comes out of that)
function Parts.Curls(H, spec)
	local S, L = H.S, H.L
	local count = max(3, floor((spec.n or 60) * L.k * (0.6 + 0.6 * H.density) * (H.nScale or 1) + 0.5))
	local roots = Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.45, 0.85, c)
	end, (spec.seed or 0) + H.seed + 51)
	local out, pal = H.out, H.pal
	local rng = MeshKit.Rng(H.seed + (spec.seed or 0) + 53)
	local mat = { material = spec.material or "Plastic", castShadow = true }
	local sides = spec.sides or (H.lod == "full" and 4 or 3)
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
		local gopts = {
			len = len, ds = clamp(len / 8, 0.01, 0.04), flow = spec.flow, lift = spec.lift or 0.5,
			off = function(u)
				return (spec.off and spec.off(u, r) or 0.02) + rad
			end, stick = spec.stick or 0.3, grav = spec.grav or 0.2, stiff = spec.stiff or 0.5, free = spec.free,
			bodyOff = 0.03 + rad, jitter = { amp = 0.3, freq = 8, seed = H.seed + 3 },
		}
		local pts, leftAt = Kit.Grow(S, x, y, z, gopts)
		if spec.inside then
			-- a clump rooted inside a volume (spec.inside, its SDF) is grown through it to where it comes out,
			-- then hangLen(r) further; only its last ~0.04 inside is built (the rest is never seen)
			local vol = spec.inside
			local function exitAt(p)
				for i = 2, #p do
					if vol(p[i][1], p[i][2], p[i][3]) > 0 then
						return i
					end
				end
				return nil
			end
			local ie = exitAt(pts)
			len = Kit.Length(ie and table.move(pts, 1, ie, 1, {}) or pts) + spec.hangLen(r)
			gopts.len, gopts.ds = len, clamp(len / 8, 0.01, 0.04)
			pts, leftAt = Kit.Grow(S, x, y, z, gopts)
			ie = exitAt(pts)
			-- (a step of the field search per point)
			step(#pts * 4)
			if not ie then
				continue
			end
			if spec.shell then
				-- spec.shell: the field of the mass's visible surface, which near its hairline lies well inside
				-- vol: the clump comes out where it leaves that (bisection: inside at the root, outside past
				-- vol). One with little of the mass over its root is not built: it hung from the bare nape
				-- under the mass's edge
				local sh = spec.shell
				step(160)
				if sh(x, y, z) > -0.06 then
					continue
				end
				local p = pts[ie]
				if sh(p[1], p[2], p[3]) > 0 then
					local lo, hi = 1, ie
					while hi - lo > 1 do
						local mid = (lo + hi) // 2
						local q = pts[mid]
						if sh(q[1], q[2], q[3]) > 0 then
							hi = mid
						else
							lo = mid
						end
						-- (a ray and the shell's depth search: ~160 field samples)
						step(160)
					end
					ie = hi
				end
				-- where it crosses the shell on its last step in (three halvings): its first step out of the scalp
				-- rises straight to its depth under the surface, so a clump kept from that step's start spent
				-- its turns inside the mass - it starts 0.04 inside the crossing instead
				local a, b = pts[ie - 1], pts[ie]
				local lo, hi = 0, 1
				for _ = 1, 3 do
					local m = (lo + hi) * 0.5
					if sh(lerp(a[1], b[1], m), lerp(a[2], b[2], m), lerp(a[3], b[3], m)) > 0 then
						hi = m
					else
						lo = m
					end
				end
				step(640)
				local seg = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
				local f0 = (lo + hi) * 0.5 - 0.04 / max(seg, 1e-4)
				if f0 > 0 then
					pts[ie - 1] = { lerp(a[1], b[1], f0), lerp(a[2], b[2], f0), lerp(a[3], b[3], f0) }
				end
			end
			local i0, run = ie, 0
			while i0 > 1 and run < 0.04 do
				local p, q = pts[i0], pts[i0 - 1]
				run += math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2)
				i0 -= 1
			end
			if i0 > 1 then
				pts = table.move(pts, i0, #pts, 1, {})
				leftAt = leftAt and max(1, leftAt - i0 + 1) or nil
			end
		end
		if spec.bend then
			pts = spec.bend(pts, r)
		end
		local rs = Kit.Resample(pts, max(4, floor(#pts * 0.7)))
		local plen = Kit.Length(rs)
		-- a ringlet: about one turn per 2.4 radii of length, tighter for tighter curls
		local turns = clamp(plen / (rad * (spec.pitch or 2.5)), 0.8, spec.maxTurns or 9)
		local static = Parts.Piece(H, spec.piece or "HairTop", mat)
		local g = spec.hang and leftAt and Parts.GroupKey(H, x, z, da)
		local target = static
		if spec.bounce and not g then
			target = Parts.Piece(H, spec.bounce(r), mat)
			H.bounce = H.bounce or {}
			H.bounce[target.mesh.name] = true
		end
		-- ply: a clump of that many coils wound round one another (each its own radius and phase, the
		-- same turns: they twist together without crossing), not a single spring
		local ply = spec.ply or 1
		for k = 1, ply do
			local radK, phK = rad, rnd * TAU
			if ply > 1 then
				radK *= 0.8 + 0.4 * rng:Next()
				phK += TAU * (k - 1) / ply + rng:Range(-0.35, 0.35)
			end
			local hp = Kit.Helix(rs, out, function(t)
				return radK * (0.75 + 0.25 * smoothstep(0, 0.2, t)) * (1 - 0.2 * t)
			end, turns, phK, perTurn)
			local yAt = Parts.YAt(hp)
			-- (the coils of one clump a little apart in tone)
			local kk = ply > 1 and (0.88 + 0.24 * rng:Next()) or 1
			local col = function(t, a, rr)
				local cr, cg, cb = pal.at(rnd, 0.25 + 0.75 * t, x, nil, yAt(t), (1 - t) * plen)
				-- the outside of each loop catches light, the inside of the cluster is shadowed
				local k2 = (0.8 + 0.3 * smoothstep(-0.6, 0.9, sin(a))) * (0.82 + 0.25 * t) * kk
				return cr * k2, cg * k2, cb * k2
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
	if not coily then
		-- curly: dense clusters of short curls packed into the top layer (half sunk: the top's relief and its
		-- broken outline), not a few loose springs lying on a smooth shell
		local cut = H.cut
		local layer = function(x, y, z)
			return H.S.f(x, y, z) - cut.thick(x, y, z)
		end
		-- the clusters' rounded tops (flattened domes half sunk into the layer, lit like the coil texture) and
		-- short curls springing from them (sunk deep, leaning over: curls, not wires)
		Parts.Lumps(H, { n = spec.lumpN or 300, vol = layer, accept = spec.accept, r = 0.02 * (0.85 + 0.3 * L), flat = 0.6, share = 0.5 })
		return Parts.CoilHalo(H, {
			n = spec.curlN or 320, vol = layer, accept = spec.accept, sink = 0.85, radius = 0.016 * (0.85 + 0.3 * L),
			len = lerp(len0, len1, 0.5) * 0.4, tube = 0.0062, share = spec.share or 0.9, bounce = spec.bounce,
		})
	end
	return Parts.Curls(H, {
		n = spec.coilN or 120, seed = 7, accept = spec.accept, flow = flow, lift = 0.8, stick = 0, grav = 0, stiff = 0.7,
		len = function(r)
			return lerp(0.025, 0.045, r[9]) * (0.8 + 0.5 * L)
		end, radius = 0.009, tube = 0.0048, pitch = 2.0, perTurn = 6, off = function()
			return top * 0.7
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
-- thickness at the hairline; a gentle lumpy relief. spec: vol, or layerT (a uniform layer that thick over the
-- scalp: no field search, so the skull's blend creases never show through) with layerMask(x, y, z) (> 0
-- where the layer is: a mohawk strip, a curly top; its edge rounded off), edge (taper width inside the
-- hairline, at least 0.6 x the thickness: the mass rolls onto the forehead instead of overhanging it),
-- frontEdge, bump (amplitude), bumpFreq (capped at what the grid carries: finer relief reads as lobes and
-- creases), plus the Cap spec (fade, top, side, pattern, region...)
function Parts.Volume(H, spec)
	local S = H.S
	local vol = spec.vol
	local amp = spec.bump or 0.012
	local cols = spec.cols or H.L.cols
	-- ~2.5 grid columns per relief cycle round a ~3-stud head at most
	local fmax = cols / 3 / 2.5
	local f1 = min(spec.bumpFreq or 5, fmax)
	local f2 = min(f1 * 1.7, fmax)
	local seed = H.seed % 1000
	local layerT, layerMask = spec.layerT, spec.layerMask
	local thick0 = layerT or spec.thick0 or 0.12
	local edge = max(spec.edge or 0.1, 0.6 * thick0)
	local cutDist
	local t = table.clone(spec)
	-- a thin layer rises over ~3.5 x its thickness at the front; a big volume (afro, high top) rolls onto the forehead
	-- over its frontEdge (a slope as long as the mass is deep would leave a crease where it meets the sides)
	local frontEdge = layerT and max(spec.frontEdge or edge * 1.8, edge, 3.5 * thick0) or max(spec.frontEdge or edge * 1.8, edge)
	t.extra = function(x, y, z, c)
		-- a uniform layer: a mask and two noises; a volume: a depth search of up to 14 samples of its field (the
		-- skull field, noise, blends: ~0.5 ms a vertex, measured), the hairline and two noises
		step(layerT and 12 or 160)
		local d
		if layerT then
			d = layerT
			if layerMask then
				d *= smoothstep(0, 0.35, layerMask(x, y, z))
			end
		elseif spec.radial then
			-- along the ray from the head's centre (the shell grows along it: no folds over the temples)
			local rx, ry, rz = norm3(x - S.cx, y - S.cy, z - S.cz)
			d = depthIn(vol, x, y, z, rx, ry, rz, spec.tmax or 0.6)
		else
			local nx, ny, nz = S.normal(x, y, z)
			d = depthIn(vol, x, y, z, nx, ny, nz, spec.tmax or 0.6)
		end
		local dist, da = cutDist(x, y, z)
		-- the volume rises from the hairline; over the forehead it rises more slowly (no brim over the eyes)
		local e = lerp(frontEdge, edge, smoothstep(0.3, 1.6, da or 1))
		if spec.edgeDepth then
			-- a deep mass rolls off toward its hairline at a slope (its run edgeDepth x its depth), never
			-- a wall of hair standing on the forehead and the temples
			e = max(e, spec.edgeDepth * d)
		end
		local k = smoothstep(-0.004, e, dist) ^ 1.3
		-- clusters: broad lumps the grid can carry
		local b = amp * (0.7 * Kit.RNoise(x, y, z, f1, seed, 1) + 0.3 * Kit.RNoise(x, y, z, f2, seed + 1, 2))
		-- (the lumps grow in with the depth: switched on over a short span they would ridge the mass's rim)
		return max(0, d * k + b * k * smoothstep(0, 0.2, d))
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
	-- second result (radial volumes): the visible shell as a field - how far (x, y, z) lies outside it along the
	-- ray from the head's centre. Near its hairline the shell rolls off well inside vol, so what hangs out of
	-- the mass has to come out of this surface, not vol's (cut at vol's it started in the air under the mass)
	if not spec.radial then
		return piece
	end
	local cut = H.cut
	return piece, function(x, y, z)
		local dx, dy, dz = x - S.cx, y - S.cy, z - S.cz
		local l = sqrt(dx * dx + dy * dy + dz * dz)
		if l < 1e-4 then
			return -1
		end
		local sx, sy, sz, tr = S.ray(dx / l, dy / l, dz / l, 0, clamp(l, 0.05, 2.5))
		return l - tr - cut.thick(sx, sy, sz) - t.extra(sx, sy, sz)
	end
end

-- coil clusters: groups of 3-5 short springy coils standing half out of a volume's surface (sunk by half their
-- radius, the strand fat: they read as the bumps of coil clusters breaking up the surface and its outline, not
-- as wires floating off it). spec: n (coils at full), vol (the volume SDF they sit in), accept, radius, tube,
-- len, bounce(r) -> piece name, share / tris (budget)
function Parts.CoilHalo(H, spec)
	local S, L, cut = H.S, H.L, H.cut
	if H.lod == "low" then
		return 0
	end
	local count = max(4, floor((spec.n or 120) * L.k * (0.6 + 0.6 * H.density) * (H.nScale or 1) / 4 + 0.5))
	local roots = Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.6, 0.95, c)
	end, H.seed + 61)
	local out, pal = H.out, H.pal
	local rng = MeshKit.Rng(H.seed + 63)
	local mat = { material = "Plastic", castShadow = false }
	local cs = 1 + 0.3 * H.curl
	local sides = 3
	-- the cap texture lifts near-black coil tops: the same lift here
	local darkLift = clamp((0.16 - pal.lum) / 0.16, 0, 1) * 0.045
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local x, y, z, nx, ny, nz, rnd = r[1], r[2], r[3], r[4], r[5], r[6], r[9]
		-- a tangent frame at the cluster's root
		local tx, ty, tz = norm3(Kit.cross(nx, ny, nz, 0.3, 1, 0.2))
		if tx == 0 and ty == 0 and tz == 0 then
			tx, ty, tz = 1, 0, 0
		end
		local bx2, by2, bz2 = Kit.cross(nx, ny, nz, tx, ty, tz)
		local piece = Parts.Piece(H, spec.bounce and spec.bounce(r) or "HairTop", mat)
		if spec.bounce then
			H.bounce = H.bounce or {}
			H.bounce[piece.mesh.name] = true
		end
		local rad0 = (spec.radius or 0.012) * cs
		for _ = 1, 3 + floor(rng:Next() * 2.99) do
			-- each coil a little apart from the cluster's centre
			local ang, dist = rng:Range(0, TAU), rad0 * rng:Range(0.4, 1.7)
			local ox, oy, oz = (tx * cos(ang) + bx2 * sin(ang)) * dist, (ty * cos(ang) + by2 * sin(ang)) * dist, (tz * cos(ang) + bz2 * sin(ang)) * dist
			local px, py, pz = x + ox, y + oy, z + oz
			local qx, qy, qz = S.onto(px, py, pz, 0)
			local mx, my, mz = S.normal(qx, qy, qz)
			local rad = rad0 * (0.75 + 0.5 * rng:Next())
			-- (a coil that strays off its cluster's root past the hairline or into a fade sat on bare skin: a
			-- detached squiggle on the nape)
			local cq = cut.cov(qx, qy, qz)
			if cq < 0.55 then
				continue
			end
			local d = spec.vol and depthIn(spec.vol, qx, qy, qz, mx, my, mz, 0.7) or 0.02
			-- sunk into the surface (half its radius by default): a bump of the coil clusters, not a wire on top
			local sunk = d - rad * (spec.sink or 0.5)
			local bx, by, bz = qx + mx * sunk, qy + my * sunk, qz + mz * sunk
			local len = (spec.len or 0.026) * (0.7 + 0.6 * rng:Next()) * (0.85 + 0.3 * H.len)
			-- leaning over (spec.lean: how far from the normal toward the surface): a curl lying in its cluster, not
			-- a spring standing off it
			local lean = spec.lean or 0.35
			local dx, dy, dz = norm3(mx + rng:Range(-lean, lean), my + rng:Range(-lean * 0.7, lean * 0.85), mz + rng:Range(-lean, lean))
			local base = {}
			for i = 0, 3 do
				local u = i / 3
				base[#base + 1] = { bx + dx * len * u, by + dy * len * u - 0.004 * u * u, bz + dz * len * u }
			end
			local hp = Kit.Helix(base, out, rad, clamp(len / (rad * 2.2), 1, 2), rng:Range(0, TAU), 4)
			local tube = max((spec.tube or 0.0058) * (0.85 + 0.3 * H.thick), rad * 0.45)
			Kit.Tube(piece.mesh, hp, {
				sides = sides, out = out, rad = tube, tip = "point",
				r = function(t)
					return tube * (1 - 0.35 * smoothstep(0.75, 1, t))
				end,
				color = function(t, a)
					local cr, cg, cb = pal.at(rnd, 0.6 + 0.4 * t, x, nil, by, (1 - t) * len)
					-- the coil's outside catches light, its inner side and its base are shadowed; on average the
					-- tone of the textured surface around it (with its lift on near-black hair)
					local k = (0.85 + 0.3 * smoothstep(-0.5, 0.9, sin(a))) * (0.9 + 0.15 * t)
					return cr * k + darkLift, cg * k + darkLift * 0.82, cb * k + darkLift * 0.62
				end,
			})
		end
	end
	return #roots
end

-- coil clusters as lumps: small flattened domes half sunk into a volume's surface - the bumpy, spongy surface
-- of short coily hair at a scale the shell's grid cannot carry, lit like the cap's coil tops (lighter
-- crowns, shadowed rims). spec: n (at full), vol (the volume SDF), accept, r (radius), flat (height / radius),
-- bounce(r) -> piece name, share / tris (budget)
function Parts.Lumps(H, spec)
	if H.lod == "low" then
		return 0
	end
	local S, L = H.S, H.L
	local count = max(4, floor((spec.n or 200) * L.k * (0.6 + 0.6 * H.density) * (H.nScale or 1) + 0.5))
	local roots = Parts.Roots(H, count, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.6, 0.95, c)
	end, H.seed + 81)
	local pal = H.pal
	local rng = MeshKit.Rng(H.seed + 83)
	local mat = { material = "Plastic", castShadow = false }
	local darkLift = clamp((0.16 - pal.lum) / 0.16, 0, 1) * 0.045
	local sides = H.lod == "full" and 6 or 5
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local x, y, z, nx, ny, nz, rnd = r[1], r[2], r[3], r[4], r[5], r[6], r[9]
		local d = spec.vol and depthIn(spec.vol, x, y, z, nx, ny, nz, 0.7) or 0.02
		local rad = (spec.r or 0.012) * (0.65 + 0.7 * rng:Next()) * (1 + 0.25 * H.curl)
		local rn = rad * (spec.flat or 0.55) * (0.8 + 0.4 * rng:Next())
		-- sunk: a third of its height inside the volume
		local cx, cy, cz = x + nx * (d - rn * 0.35), y + ny * (d - rn * 0.35), z + nz * (d - rn * 0.35)
		local tx, ty, tz = norm3(Kit.cross(nx, ny, nz, 0.3, 1, 0.2))
		if tx == 0 and ty == 0 and tz == 0 then
			tx, ty, tz = 1, 0, 0
		end
		local bx, by, bz = Kit.cross(nx, ny, nz, tx, ty, tz)
		local piece = Parts.Piece(H, spec.bounce and spec.bounce(r) or "HairTop", mat)
		if spec.bounce then
			H.bounce = H.bounce or {}
			H.bounce[piece.mesh.name] = true
		end
		local cr0, cg0, cb0 = pal.at(rnd, 0.8, x, nil, y, 0.02)
		local tilt = rng:Range(-0.25, 0.25)
		local rz = rad * (0.75 + 0.5 * rng:Next())
		-- the dome's normals (the ellipsoid's gradient in its frame), one per vertex in build order
		local NL = {}
		local m = piece.mesh
		local first = m.nv + 1
		MeshKit.Ellipsoid(m, 0, 0, 0, rad, rn, rz, {
			sides = sides, rings = 4, th0 = pi * 0.4, th1 = pi,
			deform = function(px, py, pz)
				local gx, gy, gz = norm3(px / (rad * rad), py / (rn * rn), pz / (rz * rz))
				NL[#NL + 1] = { tx * gx + nx * gy + bx * gz, ty * gx + ny * gy + by * gz, tz * gx + nz * gy + bz * gz }
				-- the dome's axis along the surface normal, leaning a little
				local qx, qy = px + py * tilt, py
				return cx + tx * qx + nx * qy + bx * pz, cy + ty * qx + ny * qy + by * pz, cz + tz * qx + nz * qy + bz * pz
			end,
			color = function(_, _, _, dx, dy, dz)
				-- the dome's crown catches light, its rim (where it meets the next cluster) is shadowed
				local k = 0.72 + 0.4 * smoothstep(-0.2, 0.9, dy)
				return cr0 * k + darkLift, cg0 * k + darkLift * 0.82, cb0 * k + darkLift * 0.62
			end,
		})
		local N = m.N
		for i = first, m.nv do
			local q = NL[i - first + 1]
			if q then
				local ux, uy, uz = norm3(q[1], q[2], q[3])
				if ux == 0 and uy == 0 and uz == 0 then
					ux, uy, uz = nx, ny, nz
				end
				N[i * 3 - 2], N[i * 3 - 1], N[i * 3] = ux, uy, uz
			end
		end
	end
	return #roots
end

-- fuzz: short frizzy strands lying almost along a volume's surface (lift <= ~15 deg): at the silhouette
-- they soften the outline, elsewhere they are nearly the surface's own colour (full detail only). spec: n,
-- vol, accept, len, zig (zig-zag amplitude), flow (Kit.Flow for their direction; random tangents otherwise)
function Parts.Fuzz(H, spec)
	local S = H.S
	if not H.L.strands then
		return 0
	end
	local count = max(4, floor((spec.n or 160) * (0.6 + 0.6 * H.density) * (0.6 + 0.8 * H.frizz) * (H.nScale or 1) + 0.5))
	local roots = Parts.Roots(H, count, spec.accept or function(_, y, _, _, c)
		return smoothstep(0.6, 0.95, c) * smoothstep(0.05, 0.25, y)
	end, H.seed + 71)
	local out, pal = H.out, H.pal
	local rng = MeshKit.Rng(H.seed + 73)
	local piece = Parts.Piece(H, "HairStrands", { material = "SmoothPlastic", doubleSided = true, castShadow = false })
	local zig = spec.zig or 0.003
	local flow = spec.flow
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local x, y, z, nx, ny, nz, rnd = r[1], r[2], r[3], r[4], r[5], r[6], r[9]
		local d = spec.vol and depthIn(spec.vol, x, y, z, nx, ny, nz, 0.7) or 0.02
		local bx, by, bz = x + nx * (d - 0.003), y + ny * (d - 0.003), z + nz * (d - 0.003)
		local len = (spec.len or 0.012) * (0.6 + 0.8 * rng:Next())
		-- a direction along the surface (the flow, else random), lifted a little
		local tx, ty, tz
		if flow then
			tx, ty, tz = flow(x, y, z, nx, ny, nz)
		else
			tx, ty, tz = norm3(Kit.cross(nx, ny, nz, rng:Range(-1, 1), rng:Range(-1, 1), rng:Range(-1, 1)))
		end
		local lift = rng:Range(0.05, spec.lift or 0.25)
		local dx, dy, dz = norm3(tx + nx * lift + rng:Range(-0.3, 0.3), ty + ny * lift + rng:Range(-0.3, 0.3), tz + nz * lift + rng:Range(-0.3, 0.3))
		if dx == 0 and dy == 0 and dz == 0 then
			dx, dy, dz = nx, ny, nz
		end
		local sx, sy, sz = norm3(Kit.cross(dx, dy, dz, nx, ny, nz))
		local pts = {}
		for i = 0, 4 do
			local u = i / 4
			local w = (i % 2 == 0 and -1 or 1) * zig * (0.4 + 0.6 * u)
			pts[#pts + 1] = { bx + dx * len * u + sx * w, by + dy * len * u + sy * w, bz + dz * len * u + sz * w }
		end
		local tw = 0.0024 * (0.8 + 0.4 * H.thick)
		Kit.Strand(piece.mesh, pts, {
			w = function(t)
				return tw * (1 - 0.6 * t)
			end,
			out = out,
			color = function(t)
				-- the surface's own lit tone (a darker strand reads as a spike)
				local cr, cg, cb = pal.at(rnd, 0.7 + 0.3 * t, x, nil, by, 0.02 + (1 - t) * len)
				return cr * 1.05, cg * 1.05, cb * 1.05
			end,
		})
	end
	return #roots
end

------------------------------------------------------------------------
-- Cornrows
------------------------------------------------------------------------
-- rows run from the front hairline straight back over the crown to the nape: the planes through a front-back
-- axis `axisDepth` below the cranium centre (psi = a row's angle about it). With the axis deep under the head
-- (cornrows) the rows stay apart all the way down to the nape (bunching a little there) instead of meeting in
-- a star where the axis comes out of the scalp. Returns the rows' psi list, the coverage region fn (1 on a row,
-- 0 on the parting between two rows; parting = the parting's share of a row's width), psiOf and dpsi.
function Parts.RowLayout(H, n, parting, axisDepth, psiMax)
	local S = H.S
	local p0 = 0.5 - (parting or 0.2)
	local A = axisDepth or 0.25
	psiMax = psiMax or 1.25
	local rows = {}
	for i = 1, n do
		rows[i] = -psiMax + 2 * psiMax * (i - 0.5) / n
	end
	local dpsi = 2 * psiMax / n
	local cy = S.cy
	local function psiOf(x, y)
		return math.atan2(x, y - cy + A)
	end
	local pw = min(0.05, (parting or 0.2) * 0.5)
	local region = function(x, y, z, da)
		local ps = psiOf(x, y)
		local k = (ps + psiMax) / dpsi - 0.5
		local f = abs(k - floor(k + 0.5)) -- 0 on a row centre, 0.5 on a parting
		return 1 - smoothstep(p0 - pw, p0 + pw, f)
	end
	return rows, region, psiOf, dpsi
end

-- a cornrow's plait seen from above: a stitch every `stitch` studs on alternating sides of the row (the three
-- strands crossing over), each a rounded bump with a groove between it and the next (the tube's normals come
-- from its geometry, so the stitches shade). (t, a, s, r) -> radius; a = 0 the row's side, pi/2 its top
function Parts.CornrowSection(stitch)
	return function(t, a, s, r)
		local q = s / (2 * stitch)
		local ph = (q - floor(q)) * TAU
		local w = sin(ph)
		local lobe = abs(w) ^ 0.7
		-- the bump is on the side the stitch crosses to (cos(a) > 0 on one side), and rises over the top
		local onSide = max(0, cos(a) * (w >= 0 and 1 or -1))
		local up = max(0, sin(a))
		local k = 0.84 + 0.3 * lobe * onSide ^ 1.5 + 0.06 * lobe * up - 0.1 * (1 - lobe) * up
		-- a braid lying flat on the scalp: wider than it is high
		return r * k * (1 - 0.3 * up)
	end
end

-- the cornrow braids: each row a plait lying on the scalp (half sunk into the shell), from the front hairline
-- back to the nape, its ends tapered and tucked into the scalp; hanging tails at the nape when the hair is long.
-- spec: n, r (row radius), axis (Parts.RowLayout axisDepth), psiMax, stitch (studs a stitch), tail(r)
function Parts.Cornrows(H, spec)
	local S, L = H.S, H.L
	local n = spec.n
	local A = spec.axis or 0.25
	local rows = Parts.RowLayout(H, n, nil, A, spec.psiMax)
	local cut = H.cut
	local f = S.f
	local out, pal = H.out, H.pal
	local mat = { material = "Plastic", castShadow = true }
	local static = Parts.Piece(H, "HairTop", mat)
	local sides = H.lod == "full" and 5 or (H.lod == "medium" and 4 or 3)
	local cy, cz = S.cy, S.cz
	-- rings per stud from what the budget leaves for the rows (~1.3 studs each, plus the tails)
	local allow = Parts.Allow(H, { share = spec.tails and 0.7 or 0.95 })
	local perStud = clamp(allow / (n * 0.95 * sides * 2), 5, H.lod == "full" and 80 or 40)
	-- each stitch gets ~3 rings (finer ones would alias into lumps); far away a plain cord
	local stitch = max(spec.stitch or 0.03, 3 / perStud)
	local plain = stitch > 0.07
	local function inHair(x, y, z)
		return cut.dist(x, y, z) > 0.03 and cut.cov(x, y, z) > 0.05
	end
	for i, psi in ipairs(rows) do
		-- the row's plane (through the axis): normal (cos psi, -sin psi, 0)
		local pnx, pny = cos(psi), -sin(psi)
		-- start where the plane meets the scalp level with the cranium centre's depth: scan in from outside
		local sx, sy = sin(psi), cos(psi)
		local tHi, tLo = 2.2, nil
		for t = 2.2, 0.05, -0.04 do
			if f(sx * t, cy - A + sy * t, cz) < 0 then
				tLo = t
				break
			end
			tHi = t
		end
		local pts = {}
		if tLo then
			for _ = 1, 16 do
				local mid = (tLo + tHi) * 0.5
				if f(sx * mid, cy - A + sy * mid, cz) < 0 then
					tLo = mid
				else
					tHi = mid
				end
			end
			local t0 = (tLo + tHi) * 0.5
			local x0, y0, z0 = sx * t0, cy - A + sy * t0, cz
			-- follow the curve where the plane cuts the scalp, forward (-z) then backward (+z), while in the hair
			local function walk(dir)
				local list = {}
				local x, y, z = x0, y0, z0
				local px, py, pz = 0, 0, dir
				for _ = 1, 140 do
					local nx, ny, nz = S.normal(x, y, z)
					local tx, ty, tz = norm3(Kit.cross(pnx, pny, 0, nx, ny, nz))
					-- (oriented by continuity: under the occiput the curve turns forward again)
					if tx * px + ty * py + tz * pz < 0 then
						tx, ty, tz = -tx, -ty, -tz
					end
					px, py, pz = tx, ty, tz
					x, y, z = x + tx * 0.02, y + ty * 0.02, z + tz * 0.02
					x, y, z = S.onto(x, y, z, 0)
					-- back into the plane
					local d = x * pnx + (y - cy + A) * pny
					x, y = x - pnx * d, y - pny * d
					if not inHair(x, y, z) then
						break
					end
					list[#list + 1] = { x, y, z }
					step(8)
				end
				return list
			end
			local fwd, back = walk(-1), walk(1)
			for k = #fwd, 1, -1 do
				pts[#pts + 1] = fwd[k]
			end
			if inHair(x0, y0, z0) then
				pts[#pts + 1] = { x0, y0, z0 }
			end
			for k = 1, #back do
				pts[#pts + 1] = back[k]
			end
		end
		-- (an outer row that starts just inside the hair's side edge and leaves it after a few steps is no row:
		-- built, it was a dark stub on the shaved temple above the ear)
		if #pts >= 4 and Kit.Length(pts) > 0.3 then
			local plen = Kit.Length(pts)
			local r0 = spec.r * (0.9 + 0.2 * H.thick)
			-- lifted half a radius off the scalp, the last ~0.07 studs at each end sinking into it (tucked)
			local np = #pts
			local acc0 = 0
			for k = 1, np do
				local p = pts[k]
				if k > 1 then
					local q = pts[k - 1]
					local ddx, ddy, ddz = p[1] - q[1], p[2] - q[2], p[3] - q[3]
					acc0 += sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
				end
				local u = acc0 / max(plen, 1e-4)
				local tuck = smoothstep(1 - 0.07 / plen, 1, u)
				local front = 1 - smoothstep(0, 0.06 / plen, u)
				local nx, ny, nz = S.normal(p[1], p[2], p[3])
				local o = r0 * 0.45 * (1 - 0.75 * tuck) * (1 - 0.45 * front)
				p[1], p[2], p[3] = p[1] + nx * o, p[2] + ny * o, p[3] + nz * o
			end
			local tl = spec.tail and spec.tail(i) or 0
			local hasTail = tl > 0.06
			local rs = Kit.Resample(pts, clamp(floor(plen * perStud + 2), 4, 110))
			local sec = plain and function(t, a, s2, r)
				return r * (0.8 + 0.2 * smoothstep(0, 0.03, s2))
			end or Parts.CornrowSection(stitch)
			local x0 = rs[1][1]
			local rnd = (i * 0.618) % 1
			local endK = 0.07 / plen
			Kit.Tube(static.mesh, rs, {
				sides = sides, out = out, rad = r0, tip = "dome", root = "dome",
				r = function(t, a)
					-- tapering into the tucked end (a row with a tail keeps its width into the tail)
					-- (and starting small at the hairline, where the plait picks up its first hair)
					local taper = (hasTail and 1 or (1 - 0.55 * smoothstep(1 - endK, 1, t))) * (0.55 + 0.45 * smoothstep(0, 0.06 / plen, t))
					return sec(t, a, t * plen, r0) * taper
				end,
				color = function(t, a, rr)
					local cr, cg, cb = pal.at(rnd, 0.35 + 0.3 * t, x0, nil, 1, 1)
					-- the grooves between the stitches darker, the stitch crowns lighter
					local k = 0.62 + 0.5 * clamp(rr, 0.55, 1.15)
					return cr * k, cg * k, cb * k
				end,
			})
			-- a tail hangs from the nape end of the row
			if hasTail then
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
		local yAt = Parts.YAt(rs)
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
					local tt = ta + t * span
					local cr, cg, cb = pal.at(rnd, 0.5 + 0.5 * tt, p[1], nil, yAt(tt), (1 - tt) * plen)
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
		local col = Parts.ClumpColor(H, rnd, px, 0.85 + 0.25 * (rad / spec.r0), sides, Parts.YAt(rs), Kit.Length(rs))
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
					local r, g, b = pal.at(rnd, 0.55 + 0.45 * t, x, nil, pts[1][2] + (pts[#pts][2] - pts[1][2]) * t, (1 - t) * 0.08)
					return r * 1.05, g * 1.05, b * 1.05
				end,
			})
		end
	end
end

-- fur: fine single strands lying with the comb flow and lifting off it a little - the hairy texture and the
-- soft, broken outline of a short cut (full detail; a card two vertices wide, double sided, in the hair's own
-- tone with lighter tips, its root sunk into the shell). spec: n, accept, len(r), flow, lift, off, w, jitter,
-- share
function Parts.Fur(H, spec)
	if not H.L.strands then
		return 0
	end
	local S = H.S
	local n = floor((spec.n or 400) * (0.55 + 0.75 * H.density) * (H.nScale or 1) + 0.5)
	if n <= 0 then
		return 0
	end
	local roots = Parts.Roots(H, n, spec.accept or function(_, _, _, _, c)
		return smoothstep(0.5, 0.9, c)
	end, H.seed + 87)
	local piece = Parts.Piece(H, "HairStrands", { material = "SmoothPlastic", doubleSided = true, castShadow = false })
	local out, pal = H.out, H.pal
	local rng = MeshKit.Rng(H.seed + 89)
	local allow, start = Parts.Allow(H, spec), Parts.Tris(H)
	local o0 = spec.off or 0.01
	for _, r in ipairs(roots) do
		if Parts.Tris(H) - start > allow then
			break
		end
		local len = spec.len and spec.len(r) or 0.06
		local pts = Kit.Grow(S, r[1], r[2], r[3], {
			len = len, ds = len / 4, flow = spec.flow, lift = (spec.lift or 0.3) * (0.6 + 0.8 * rng:Next()), off = function(u)
				return o0 + u * 0.012
			end, stick = 0.4, grav = 0, stiff = 0.6, free = 2,
			jitter = { amp = spec.jitter or 0.25, freq = 11, seed = H.seed + 9 },
		})
		local rs = Kit.Resample(pts, 5)
		local tw = (spec.w or 0.0032) * (0.8 + 0.4 * H.thick) * (0.8 + 0.4 * rng:Next())
		local rnd = r[9]
		local y0, y1 = rs[1][2], rs[#rs][2]
		Kit.Strand(piece.mesh, rs, {
			w = function(t)
				return tw * (1 - 0.7 * t)
			end,
			out = out,
			color = function(t)
				local cr, cg, cb = pal.at(rnd, 0.45 + 0.55 * t, r[1], nil, y0 + (y1 - y0) * t, (1 - t) * len)
				local k = 0.95 + 0.12 * t
				return cr * k, cg * k, cb * k
			end,
		})
	end
	return #roots
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
				local cr, cg, cb = pal.at(rnd, 0.5 + 0.5 * t, r[1], nil, rs[1][2] + (rs[#rs][2] - rs[1][2]) * t, (1 - t) * len)
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
	-- the piece limit per level (ANATOMY_CONTRACTS section 2): moving pieces beyond it join the static top, a
	-- whole group at a time (all its segments: a chain folded halfway would tear open at its joint), the
	-- groups with the fewest triangles first
	local maxN = Parts.MAXPIECES[H.lod] or 16
	local function nonEmpty(name)
		local p = H.pieces[name]
		return p ~= nil and p.mesh.nt > 0
	end
	local count = 0
	for _, name in ipairs(H.order) do
		if nonEmpty(name) then
			count += 1
		end
	end
	if count > maxN then
		local FIXED = { HairCap = true, HairTop = true, HairStrands = true }
		local units, inUnit = {}, {}
		for key, grp in pairs(H.groups) do
			local u = { key = key, names = {}, tris = 0 }
			for si = 1, 3 do
				local seg = grp.segs[si]
				if seg and nonEmpty(seg.name) then
					u.names[#u.names + 1] = seg.name
					u.tris += H.pieces[seg.name].mesh.nt
					inUnit[seg.name] = true
				end
			end
			if #u.names > 0 then
				units[#units + 1] = u
			end
		end
		for _, name in ipairs(H.order) do
			if nonEmpty(name) and not inUnit[name] and not FIXED[name] then
				units[#units + 1] = { key = name, names = { name }, tris = H.pieces[name].mesh.nt }
			end
		end
		table.sort(units, function(a, b)
			if a.tris ~= b.tris then
				return a.tris < b.tris
			end
			return a.key < b.key
		end)
		local hadTop = nonEmpty("HairTop")
		local top = Parts.Piece(H, "HairTop", { material = Parts.Material(H.htype), castShadow = true })
		local i = 1
		while count > maxN and units[i] do
			if not hadTop then
				-- folding creates the static top
				hadTop = true
				count += 1
			end
			for _, name in ipairs(units[i].names) do
				MeshKit.Append(top.mesh, H.pieces[name].mesh)
				H.pieces[name].mesh = MeshKit.New(name)
				if H.bounce then
					H.bounce[name] = nil
				end
				count -= 1
			end
			i += 1
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
				-- hair hanging below a sparring headgear's rim stays visible under it (not under a hood): lower
				-- segments, tails, and upper segments whose pivot is below the rim (0.3 of the head's height
				-- above its centre, the round-1 rule: BuilderHair.ApplyHairHidden)
				if s > 1 or grp.prefix == "HairTail" or pv[2] < 0.36 then
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
