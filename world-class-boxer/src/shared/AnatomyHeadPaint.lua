-- AnatomyHeadPaint: skin colour for the Head section (AnatomyHead.lua).
-- Pure and deterministic. Works in the nominal head space AnatomyHead builds in (a 1.2-stud head, +X = the
-- character's right, +Y up, -Z forward), before the final scale.
-- * Vertex: skin tone + undertone, flush zones, lips, brows, beard shadow, eye / nose tints. What every level
--   shows when textures are off, and the base the texture is rasterised from.
-- * Texture: the vertex colours rasterised into the head's UV atlas (a fast scanline rasteriser: one add per
--   attribute per texel) plus per-texel detail the mesh cannot carry: grain and pores, brow hairs, stubble,
--   lip lines, wrinkles, nostrils, freckles, moles, acne, scars.
local MeshKit = require(script.Parent:WaitForChild("MeshKit"))

local Paint = {}

local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor
local sin, cos, rad = math.sin, math.cos, math.rad

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
local function bump(q2)
	if q2 >= 1 then
		return 0
	end
	local w = 1 - q2
	return w * w * w
end

-- the nostrils' openings (AnatomyHead's nose field: pockets lying along the underside either side of the
-- columella): 0 outside, rising to 1 at the middle of the opening
local function nostrilAt(F, x, y, z)
	local NN = F.noseInfo and F.noseInfo.nostril
	if not NN then
		return 0
	end
	local ax = x - NN.dev
	local s = ax < 0 and -1 or 1
	local dx, dz = ax * s - NN.x, z - NN.z
	local lb = dx * NN.c + dz * NN.s
	local la = -dx * NN.s + dz * NN.c
	local dy = y - NN.y
	local up = la * (NN.ts or 0) + dy * (NN.tc or 1)
	local al = la * (NN.tc or 1) - dy * (NN.ts or 0)
	if abs(up) > NN.ry * 1.8 then
		return 0
	end
	local q = (lb / (NN.rx * 0.95)) ^ 2 + (al / (NN.rz * 0.9)) ^ 2
	if q >= 1 then
		return 0
	end
	return bump(q)
end

------------------------------------------------------------------------
-- Noise tiles (fixed: the same on every client; per-look offsets pick a different window)
------------------------------------------------------------------------
local TS = 128
local TILE = table.create(TS * TS, 0)
do
	local r = MeshKit.Rng(90210)
	for i = 1, TS * TS do
		TILE[i] = r:Next()
	end
end
local SS = 32
local SMOOTH = table.create(SS * SS, 0)
do
	local r = MeshKit.Rng(4242)
	for i = 1, SS * SS do
		SMOOTH[i] = r:Next()
	end
end
-- smooth value noise in [0, 1] over the wrapping 32 x 32 tile (x, y in tile cells)
local function smoothAt(x, y)
	local ix, iy = floor(x), floor(y)
	local fx, fy = x - ix, y - iy
	fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
	local x0, y0 = ix % SS, iy % SS
	local x1, y1 = (x0 + 1) % SS, (y0 + 1) % SS
	local a, b = SMOOTH[y0 * SS + x0 + 1], SMOOTH[y0 * SS + x1 + 1]
	local c, d = SMOOTH[y1 * SS + x0 + 1], SMOOTH[y1 * SS + x1 + 1]
	local top = a + (b - a) * fx
	return top + (c + (d - c) * fx - top) * fy
end
Paint.SmoothNoise = smoothAt

------------------------------------------------------------------------
-- Colours
------------------------------------------------------------------------
local UNDERTONE = {
	Neutral = { 0, 0, 0 },
	Warm = { 0.016, 0.004, -0.02 },
	Cool = { -0.006, -0.006, 0.014 },
	Olive = { -0.014, 0.01, -0.016 },
}

-- the Body's skin colour (AnatomyBodyKit.Skin: the look's skinRGB, no undertone): the neck takes it
function Paint.BodySkin(look)
	local rgb = type(look.skinRGB) == "table" and look.skinRGB or { 206, 150, 108 }
	return clamp((tonumber(rgb[1]) or 206) / 255, 0, 1), clamp((tonumber(rgb[2]) or 150) / 255, 0, 1), clamp((tonumber(rgb[3]) or 108) / 255, 0, 1)
end

-- base skin colour (0..1) with the undertone
function Paint.Skin(look)
	local rgb = type(look.skinRGB) == "table" and look.skinRGB or { 200, 150, 110 }
	local f = type(look.face) == "table" and look.face or {}
	local u = UNDERTONE[f.undertone] or UNDERTONE.Neutral
	local r, g, b = (tonumber(rgb[1]) or 200) / 255 + u[1], (tonumber(rgb[2]) or 150) / 255 + u[2], (tonumber(rgb[3]) or 110) / 255 + u[3]
	return clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1)
end

local function lum(r, g, b)
	return 0.299 * r + 0.587 * g + 0.114 * b
end

-- 0 below a light skin's luminance .. 1 for the palest tones (thin skin: warmer cavities, redder flush)
function Paint.LightK(r, g, b)
	return smoothstep(0.68, 0.8, 0.299 * r + 0.587 * g + 0.114 * b)
end

-- 0 for light skin .. 1 for the deepest tones
local function darkness(r, g, b)
	return clamp((0.5 - lum(r, g, b)) / 0.32, 0, 1)
end
Paint.Darkness = darkness

-- hair colour (0..1), greying with age; beard = true reads the beard's own colour and greys earlier
local function hairColor(look, age, beard)
	local h = type(look.hair) == "table" and look.hair or {}
	local c = h.color
	local b = type(look.beard) == "table" and look.beard or {}
	if beard and type(b.color) == "table" then
		c = b.color
	end
	c = type(c) == "table" and c or { 30, 24, 20 }
	local r, g, bl = (tonumber(c[1]) or 30) / 255, (tonumber(c[2]) or 24) / 255, (tonumber(c[3]) or 20) / 255
	local grey = clamp((age - (beard and 38 or 46)) / 25, 0, 0.6) * 0.55
	return lerp(r, 0.65, grey), lerp(g, 0.635, grey), lerp(bl, 0.62, grey)
end
Paint.HairColor = hairColor

-- the brows' colour from the hair's: a little darker; greys and whites kept light and warm (a neutral mid grey
-- over warm skin reads green or blue)
local function browColor(hr, hg, hb)
	local gk = clamp((min(hr, hg, hb) - 0.35) / 0.3, 0, 1)
	return lerp(hr * 0.82, hr * 0.88 + 0.03, gk), lerp(hg * 0.82, hg * 0.83 + 0.01, gk), lerp(hb * 0.82, hb * 0.78, gk)
end

-- the beard style the face shows (BuilderHead rules: growth alone gives shadow -> stubble -> short beard)
-- -> style or nil, shadow only, growth
function Paint.BeardStyle(look)
	if look.g == 2 then
		return nil, false, 0
	end
	local b = type(look.beard) == "table" and look.beard or {}
	local style = type(b.style) == "string" and b.style or "None"
	local g = clamp(tonumber(b.growth) or 0, 0, 1)
	if style == "None" then
		if g < 0.2 then
			return nil, false, g
		elseif g < 0.8 then
			return "Stubble", g < 0.45, g
		end
		return "Short Boxed", false, (g - 0.8) * 2
	end
	return style, false, g
end

------------------------------------------------------------------------
-- Masks in nominal space (shared by the vertex paint, the texture and the beard)
------------------------------------------------------------------------
local BROWS = {
	Natural = { head = 1, tail = 0.5, arch = 0.5, len = 1, drop = 0.45, dens = 1 },
	Straight = { head = 1, tail = 0.65, arch = 0.05, len = 1.02, drop = 0.15, dens = 1 },
	["Soft Arch"] = { head = 0.85, tail = 0.45, arch = 0.8, len = 0.98, drop = 0.55, dens = 0.92 },
	["High Arch"] = { head = 0.75, tail = 0.4, arch = 1.25, len = 0.96, drop = 0.75, dens = 0.88 },
	Thick = { head = 1.35, tail = 0.75, arch = 0.4, len = 1.04, drop = 0.35, dens = 1.15 },
	Thin = { head = 0.6, tail = 0.35, arch = 0.7, len = 0.95, drop = 0.5, dens = 0.8 },
}

-- brow coordinates: fn(x, y) -> s (0 medial head .. 1 tail; nil when far), t (studs across, + up), half
-- thickness, density
function Paint.BrowFrame(F)
	local st = BROWS[F.browStyle] or BROWS.Natural
	local thick = (1 + 0.35 * (F.browThick or 0)) * (F.female and 0.72 or 1)
	local x0 = F.female and 0.07 or 0.064
	local len = 0.212 * st.len
	local by = F.browY
	local arch = (0.012 * st.arch + 0.005 * (F.browAngle or 0)) * (F.female and 1.3 or 1) + (F.female and 0.007 or 0)
	local asym = F.browAsym or { [-1] = 0, [1] = 0 }
	return function(x, y)
		local ax = abs(x)
		local s = (ax - x0) / len
		if s < -0.2 or s > 1.15 then
			return nil
		end
		local sc = clamp(s, 0, 1)
		local yc = by - 0.006 + arch * sin(clamp(sc / 0.62, 0, 1) * 1.5708)
		if sc > 0.62 then
			yc -= 0.045 * st.drop * ((sc - 0.62) / 0.38) ^ 2
		end
		yc += asym[x < 0 and -1 or 1]
		local half = (0.02 * st.head * (1 - sc) ^ 1.3 + 0.007 * st.tail * sc + 0.0035) * thick
		return s, y - yc, half, st.dens
	end
end

-- where facial hair grows (1) with soft edges: moustache, chin, jaw, cheeks below the cheek line,
-- sideburns, under the jaw to the neckline; never the lips
function Paint.BeardZone(F)
	local mY, mW = F.mouthY, F.mouthW
	local nB = F.noseBaseY
	local cy = F.chinY
	-- the cheek line: (|x|, y) from the sideburn down and forward to beside the mouth
	local CL = { { 0.46, 0.07 }, { 0.41, -0.05 }, { 0.34, -0.12 }, { 0.25, -0.17 }, { 0.17, mY + 0.06 }, { 0.12, mY + 0.03 } }
	local function cheekLine(ax)
		if ax >= CL[1][1] then
			return CL[1][2]
		end
		for i = 1, #CL - 1 do
			local a, b = CL[i], CL[i + 1]
			if ax >= b[1] then
				local t = (ax - b[1]) / (a[1] - b[1])
				return lerp(b[2], a[2], t * t * (3 - 2 * t))
			end
		end
		return CL[#CL][2]
	end
	local seed = F.seed or 0
	return function(x, y, z)
		if z > 0.16 or y > 0.1 then
			return 0
		end
		local ax = abs(x)
		-- (the cheek line wanders and thins out over a band: nobody's is a ruled curve; the strands growing down
		-- out of its sparse top break it up further)
		local line = cheekLine(ax) + 0.014 * MeshKit.Noise(ax * 22, y * 14, x < 0 and 3.7 or 9.1, seed)
			+ 0.007 * MeshKit.Noise(ax * 70, y * 55, x < 0 and 5.3 or 1.9, seed + 2)
		local w = smoothstep(line + 0.045, line - 0.065, y)
		-- the moustache: the upper lip skin between the nostrils' sides
		local mx = 1 - smoothstep(0.1, 0.135, ax)
		local my = smoothstep(nB + 0.004, nB - 0.008, y)
		w = max(w, mx * my * smoothstep(mY - 0.02, mY, y))
		-- never on the lips (vermilion)
		local ml = F.mouthLine(x)
		local hu, hl = F.lipH(x)
		local dy = y - ml
		local inLip = (dy < hu + 0.002 and dy > -hl - 0.003) and (1 - smoothstep(0.85, 1.05, ax / mW)) or 0
		w *= 1 - inLip
		-- down the front of the neck to the neckline, not round the back: it ends at the angle of the jaw, under
		-- the front of the ear (behind it the skin is the neck's)
		-- (the neckline follows the jaw's underside a little below it: under the chin, then rising to the angle;
		-- a beard is not a block hanging under the jaw)
		local yLim = lerp(cy - 0.1, F.gonionY - 0.06, smoothstep(0.04, F.jawW, ax))
		w *= smoothstep(yLim - 0.035, yLim + 0.015, y)
		w *= 1 - smoothstep(0.03, 0.1, z)
		-- the sideburn: up the side of the face only the narrow strip in front of the ear (blended in with
		-- height: a cut at one height would draw a line across the cheek)
		local sb = smoothstep(0.34, 0.39, ax) * (1 - smoothstep(0.02, 0.09, z))
		w *= lerp(1, sb, smoothstep(-0.13, -0.05, y))
		return clamp(w, 0, 1)
	end
end

------------------------------------------------------------------------
-- Vertex colours (first..last of m)
------------------------------------------------------------------------
function Paint.Vertex(m, F, look, first, last)
	local sr, sg, sb = Paint.Skin(look)
	local dark = darkness(sr, sg, sb)
	local hr, hg, hb = hairColor(look, F.age, false)
	local br, bg, bb = hairColor(look, F.age, true)
	local brow = Paint.BrowFrame(F)
	local beardZone = Paint.BeardZone(F)
	local style, _, growth = Paint.BeardStyle(look)
	-- a five o'clock shadow on every adult man, then the stubble darkens it as it grows
	local shadow = F.female and 0 or (F.age < 17 and 0.08 or 0.3)
	if style then
		shadow = max(shadow, 0.45 + 0.4 * growth)
	end
	local mW = F.mouthW
	-- lips: redder than the skin on light tones, deeper and a touch cooler on deep tones
	local lipR, lipG, lipB = lerp(sr * 0.82, sr * 0.74, dark), lerp(sg * 0.62, sg * 0.6, dark), lerp(sb * 0.66, sb * 0.7, dark)
	-- the palest tones show the blood under thin skin: more flush (cheeks, nose, chin) and rosier lips, never
	-- chalky
	local lightK = Paint.LightK(sr, sg, sb)
	lipR, lipG, lipB = lipR * (1 + 0.04 * lightK), lipG * (1 - 0.07 * lightK), lipB * (1 - 0.04 * lightK)
	local flushK = (1 - 0.7 * dark) * 0.6 * (1 + 0.7 * lightK)
	local P, C = m.P, m.C
	for i = first or 1, last or m.nv do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		local r, g, b = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
		local ax = abs(x)
		-- the face's warmth reaches the rest of the head in part (no colour step at the temples / jaw)
		r, g, b = r * 1.004, g * 0.994, b * 0.993
		local wF = 1 - smoothstep(-0.14, -0.02, z)
		if z < -0.02 then
			-- warmth: malar cheeks, the nose tip and wings, the chin; a little sallower forehead
			local fl = bump(((ax - 0.22) / 0.12) ^ 2 + ((y - F.eyeY + 0.09) / 0.09) ^ 2) * 0.9
				+ bump((x / 0.075) ^ 2 + ((y - F.noseTipY + 0.01) / 0.06) ^ 2) * 0.8
				+ bump((x / 0.09) ^ 2 + ((y - F.chinY - 0.03) / 0.05) ^ 2) * 0.35
			if fl > 0 then
				local k = fl * flushK * 0.22
				r, g, b = r * (1 + 0.25 * k), g * (1 - 0.55 * k), b * (1 - 0.55 * k)
			end
			if y > F.browY + 0.03 then
				local k = smoothstep(F.browY + 0.03, F.browY + 0.12, y) * 0.03 * wF
				r, g, b = r * (1 + k * 0.3), g * (1 + k * 0.2), b * (1 - k)
			end
			-- lips (vermilion), the inner part a little pinker
			local ml = F.mouthLine(x)
			local dy = y - ml
			local hu, hl = F.lipH(x)
			local lx = ax / mW
			if lx < 1.12 and dy < hu + 0.006 and dy > -hl - 0.006 then
				local w
				if dy >= 0 then
					w = 1 - smoothstep(hu - 0.002, hu + 0.003, dy)
				else
					w = 1 - smoothstep(hl - 0.003, hl + 0.004, -dy)
				end
				w *= 1 - smoothstep(0.86, 1.0, lx)
				-- the mouth's inside (the deep row between the lips)
				if abs(dy) < 0.0024 and lx < 0.95 then
					r, g, b = 0.2, 0.05, 0.055
					w = 0
				end
				if w > 0 then
					local inner = (1 - smoothstep(0.1, 0.75, abs(dy) / max(0.004, dy >= 0 and hu or hl))) * (0.2 + 0.45 * dark) * (dy < 0 and 1 or 0.6)
					-- deep tones: the outer lip deeper, the inner pinker
					local outer = smoothstep(0.55, 1.0, abs(dy) / max(0.004, dy >= 0 and hu or hl)) * dark * 0.3
					local lr, lg, lb = lerp(lipR, 0.52, inner) * (1 - outer), lerp(lipG, 0.28, inner) * (1 - outer), lerp(lipB, 0.29, inner) * (1 - outer * 0.8)
					r, g, b = lerp(r, lr, w * 0.9), lerp(g, lg, w * 0.9), lerp(b, lb, w * 0.9)
				end
			end
			-- brows (the texture draws the hairs; this is their colour seen from afar)
			local s, t, half = brow(x, y)
			if s then
				local edge = 1 - smoothstep(half * 0.5, half * 1.3, abs(t))
				local ends = smoothstep(-0.15, 0.06, s) * (1 - smoothstep(0.9, 1.1, s))
				local w = edge * ends * 0.7
				if w > 0 then
					local cr, cg, cb = browColor(hr, hg, hb)
					r, g, b = lerp(r, cr, w), lerp(g, cg, w), lerp(b, cb, w)
				end
			end
			-- around the eyes: a little darker and cooler (more on deep tones); the inner corner pinker
			for side = -1, 1, 2 do
				local e = F.eye[side]
				local dx, dy2 = (x - e.x) * side, y - e.y
				local q = (dx / 0.09) ^ 2 + ((dy2 + 0.012) / 0.062) ^ 2
				if q < 1 then
					local k = bump(q) * (0.06 + 0.1 * dark + 0.04 * clamp((F.age - 30) / 25, 0, 1))
					r, g, b = r * (1 - k), g * (1 - k * 1.12), b * (1 - k * 0.95)
				end
				local cq = ((dx + 0.064) / 0.016) ^ 2 + (dy2 / 0.013) ^ 2
				if cq < 1 then
					local k = bump(cq) * 0.35
					r, g, b = lerp(r, 0.8, k), lerp(g, 0.5, k), lerp(b, 0.5, k)
				end
			end
			-- nostril shadows (the texture sharpens them)
			local nk = nostrilAt(F, x, y, z)
			if nk > 0 then
				local k = nk * 0.6 * smoothstep(0.05, 0.5, -m.N[i * 3 - 1])
				r, g, b = r * (1 - k), g * (1 - k * 1.08), b * (1 - k * 1.05)
			end
		end
		-- beard shadow (blue-grey from the hair under the skin)
		if shadow > 0 then
			local bz = beardZone(x, y, z)
			if bz > 0 then
				local k = bz * shadow * 0.42 * (1 - 0.65 * dark)
				r, g, b = lerp(r, br * 0.7 + 0.12, k), lerp(g, bg * 0.7 + 0.12, k), lerp(b, bb * 0.7 + 0.16, k)
			end
		end
		C[i * 3 - 2], C[i * 3 - 1], C[i * 3] = r, g, b
		MeshKit.Step(2)
	end
	MeshKit.NoiseColor(m, 0.02, 7, F.seed % 9973, first, last)
end

------------------------------------------------------------------------
-- Spots (freckles, moles, acne, marks, scars): a list in front-projected (x, y) plus a cell grid
------------------------------------------------------------------------
local function spotList(F, look)
	local f = type(look.face) == "table" and look.face or {}
	local list = {}
	local rng = MeshKit.Rng(F.seed * 7 + 13)
	local sr, sg, sb = Paint.Skin(look)
	local dark = darkness(sr, sg, sb)
	local function add(x, y, r, cr, cg, cb, a, len, ang)
		list[#list + 1] = { x = x, y = y, r = r, cr = cr, cg = cg, cb = cb, a = a, len = len or 0, ca = cos(ang or 0), sa = sin(ang or 0) }
	end
	-- freckles: over the nose bridge and the upper cheeks (fewer and fainter on deep skin)
	local fr = clamp(tonumber(f.freckles) or 0, 0, 1)
	for _ = 1, floor(fr * 90 * (1 - 0.5 * dark)) do
		local side = rng:Next() < 0.5 and -1 or 1
		local u = rng:Next()
		local x = side * (0.015 + u * 0.27)
		local y = F.eyeY - 0.04 - rng:Next() * 0.13 + (abs(x) < 0.07 and 0.035 or 0) - u * u * 0.04
		add(x, y, 0.0028 + rng:Next() * 0.0032, sr * 0.72, sg * 0.56, sb * 0.46, 0.3 + 0.35 * rng:Next())
	end
	-- moles
	for _ = 1, floor(clamp(tonumber(f.moles) or 0, 0, 3) + 0.5) do
		local side = rng:Next() < 0.5 and -1 or 1
		add(side * (0.06 + rng:Next() * 0.26), F.eyeY - 0.06 - rng:Next() * 0.4, 0.004 + rng:Next() * 0.0035, sr * 0.4, sg * 0.28, sb * 0.22, 0.85)
	end
	-- acne: red spots when young, small pale pits later
	local acne = clamp(tonumber(f.acne) or 0, 0, 1)
	local pits = F.age >= 26
	for i = 1, floor(acne * 26) do
		local side = rng:Next() < 0.5 and -1 or 1
		local x, y = side * (0.07 + rng:Next() * 0.26), F.eyeY - 0.07 - rng:Next() * 0.34
		if pits and i % 3 ~= 0 then
			add(x, y, 0.0042, sr * 0.86, sg * 0.8, sb * 0.78, 0.45)
		else
			add(x, y, 0.0036, lerp(sr, 0.72, 0.45), lerp(sg, 0.3, 0.45), lerp(sb, 0.3, 0.45), 0.55)
		end
	end
	-- a birthmark
	local marks = clamp(tonumber(f.marks) or 0, 0, 1)
	if marks > 0.05 then
		local side = rng:Next() < 0.5 and -1 or 1
		add(side * (0.14 + rng:Next() * 0.14), F.eyeY - 0.05 - rng:Next() * 0.2, 0.012 + 0.03 * marks, lerp(sr, sr * 0.6, 0.5), lerp(sg, sg * 0.5, 0.5), lerp(sb, sb * 0.5, 0.5), 0.4)
	end
	-- scars: pale, slightly shiny lines (slider scars at random, fight scars where the cuts were)
	local scR, scG, scB = lerp(sr, 0.92, 0.3 + 0.2 * dark), lerp(sg, 0.76, 0.3 + 0.2 * dark), lerp(sb, 0.74, 0.3 + 0.2 * dark)
	for _ = 1, floor(clamp(tonumber(f.scars) or 0, 0, 3) + 0.5) do
		local side = rng:Next() < 0.5 and -1 or 1
		add(side * (0.08 + rng:Next() * 0.22), F.eyeY + 0.12 - rng:Next() * 0.42, 0.0026, scR, scG, scB, 0.7, 0.03 + rng:Next() * 0.04, (rng:Next() - 0.5) * 1.6)
	end
	for i, sc in ipairs(F.scars or {}) do
		if i <= 8 and type(sc) == "table" then
			local side = (tonumber(sc.side) or 1) < 0 and -1 or 1
			local t = clamp(tonumber(sc.at) or 0.5, 0, 1)
			local size = clamp(tonumber(sc.size) or 0.5, 0, 1)
			local x, y, ang = side * F.eyeX * (0.55 + 0.75 * t), F.browY + 0.012, side * -0.25
			if sc.kind == "cheek" then
				x, y, ang = side * (0.2 + 0.1 * t), F.eyeY - 0.1, side * 0.4
			elseif sc.kind == "nose" then
				x, y, ang = side * 0.01, F.nasionY - 0.03 - t * 0.12, 1.3
			elseif sc.kind == "lip" then
				x, y, ang = side * F.mouthW * 0.35 * t, F.mouthY + 0.035, 1.5
			elseif sc.kind == "chin" then
				x, y, ang = side * 0.05 * t, F.chinY + 0.02, 0.2 * side
			end
			add(x, y, 0.003 + 0.0018 * size, scR, scG, scB, 0.75, 0.022 + 0.035 * size, ang)
		end
	end
	-- the grid: cells of CELL studs over the front of the head
	local CELL, X0, Y0, NX, NY = 0.04, -0.52, -0.8, 26, 34
	local grid = {}
	for k, sp in ipairs(list) do
		local ext = sp.r + sp.len * 0.5
		for cy = floor((sp.y - ext - Y0) / CELL), floor((sp.y + ext - Y0) / CELL) do
			for cx = floor((sp.x - ext - X0) / CELL), floor((sp.x + ext - X0) / CELL) do
				if cx >= 0 and cx < NX and cy >= 0 and cy < NY then
					local key = cy * NX + cx + 1
					local cell = grid[key]
					if not cell then
						cell = {}
						grid[key] = cell
					end
					cell[#cell + 1] = k
				end
			end
		end
	end
	return list, grid, CELL, X0, Y0, NX, NY
end

------------------------------------------------------------------------
-- Rasteriser: vertex colours + position into a w x h RGBA8 buffer, shade(px, py, r, g, b, x, y, z) -> r, g, b
-- per covered texel. Empty texels take their neighbours' colour (pad passes), then the fill colour.
------------------------------------------------------------------------
-- keepEmpty: no padding and no fill (texels no triangle covers keep alpha 0: the caller merges the result)
local function rasterize(m, w, h, shade, pad, fill, Q, grain, simpleTri, pscale, D, keepEmpty)
	local buf = buffer.create(w * h * 4)
	local P, U, C, T = m.P, m.U, m.C, m.T
	Q = Q or {}
	D = D or {}
	local writeu32 = buffer.writeu32
	local EPS = -1e-7
	local KT, gox, goy = grain and grain.KT, grain and grain.ox or 0, grain and grain.oy or 0
	local lf = grain and grain.lf
	local gcol, grow = grain and grain.col, grain and grain.row
	local psx, psy, psz = 1, 1, 1
	if pscale then
		psx, psy, psz = pscale[1], pscale[2], pscale[3]
	end
	local function pack(sr, sg, sb)
		sr = sr < 0 and 0 or (sr > 1 and 1 or sr)
		sg = sg < 0 and 0 or (sg > 1 and 1 or sg)
		sb = sb < 0 and 0 or (sb > 1 and 1 or sb)
		return floor(sr * 255 + 0.5) + floor(sg * 255 + 0.5) * 256 + floor(sb * 255 + 0.5) * 65536 + 4278190080
	end
	for t = 1, m.nt do
		local ia, ib, ic = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		local ax, ay = U[ia * 2 - 1] * w - 0.5, U[ia * 2] * h - 0.5
		local bx, by = U[ib * 2 - 1] * w - 0.5, U[ib * 2] * h - 0.5
		local cx, cy = U[ic * 2 - 1] * w - 0.5, U[ic * 2] * h - 0.5
		local area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
		if area > 1e-9 or area < -1e-9 then
			local inv = 1 / area
			local A0, B0, C0 = (by - cy) * inv, (cx - bx) * inv, (bx * cy - by * cx) * inv
			local A1, B1, C1 = (cy - ay) * inv, (ax - cx) * inv, (cx * ay - cy * ax) * inv
			local A2, B2, C2 = -A0 - A1, -B0 - B1, 1 - C0 - C1
			-- attribute planes f = fx * px + fy * py + f0
			local a3, b3, c3 = ia * 3, ib * 3, ic * 3
			local function plane(fa, fb, fc)
				local da, db = fa - fc, fb - fc
				return da * A0 + db * A1, da * B0 + db * B1, fc + da * C0 + db * C1
			end
			local rX, rY, r0 = plane(C[a3 - 2], C[b3 - 2], C[c3 - 2])
			local gX, gY, g0 = plane(C[a3 - 1], C[b3 - 1], C[c3 - 1])
			local bX, bY, b0 = plane(C[a3], C[b3], C[c3])
			local simple = KT ~= nil and simpleTri ~= nil and simpleTri(ia, ib, ic)
			local xX, xY, x0p, yX, yY, y0p, zX, zY, z0p, qX, qY, q0p, dX, dY, d0p
			if not simple then
				xX, xY, x0p = plane(P[a3 - 2] * psx, P[b3 - 2] * psx, P[c3 - 2] * psx)
				yX, yY, y0p = plane(P[a3 - 1] * psy, P[b3 - 1] * psy, P[c3 - 1] * psy)
				zX, zY, z0p = plane(P[a3] * psz, P[b3] * psz, P[c3] * psz)
				qX, qY, q0p = plane(Q[ia] or 0, Q[ib] or 0, Q[ic] or 0)
				dX, dY, d0p = plane(D[ia] or 0, D[ib] or 0, D[ic] or 0)
			end
			local X0, X1 = max(0, floor(min(ax, bx, cx))), min(w - 1, math.ceil(max(ax, bx, cx)))
			local Y0, Y1 = max(0, floor(min(ay, by, cy))), min(h - 1, math.ceil(max(ay, by, cy)))
			for py = Y0, Y1 do
				-- the span where all three weights are >= 0
				local lo, hi = X0, X1
				local ok = true
				local R = B0 * py + C0
				if A0 > 1e-12 then
					lo = max(lo, math.ceil((EPS - R) / A0))
				elseif A0 < -1e-12 then
					hi = min(hi, floor((EPS - R) / A0))
				elseif R < EPS then
					ok = false
				end
				R = B1 * py + C1
				if A1 > 1e-12 then
					lo = max(lo, math.ceil((EPS - R) / A1))
				elseif A1 < -1e-12 then
					hi = min(hi, floor((EPS - R) / A1))
				elseif R < EPS then
					ok = false
				end
				R = B2 * py + C2
				if A2 > 1e-12 then
					lo = max(lo, math.ceil((EPS - R) / A2))
				elseif A2 < -1e-12 then
					hi = min(hi, floor((EPS - R) / A2))
				elseif R < EPS then
					ok = false
				end
				if ok and lo <= hi then
					local r = rX * lo + rY * py + r0
					local g = gX * lo + gY * py + g0
					local b = bX * lo + bY * py + b0
					local o = (py * w + lo) * 4
					if simple then
						-- grain only (scalp, back, ears, neck): no shade call
						local rowT = ((grow[py + 1] + goy) % TS) * TS + 1
						for px = lo, hi do
							local k = KT[rowT + (gcol[px + 1] + gox) % TS]
							if lf then
								k *= lf(px, py)
							end
							writeu32(buf, o, pack(r * k, g * k, b * k))
							o += 4
							r += rX
							g += gX
							b += bX
						end
					else
						local x = xX * lo + xY * py + x0p
						local y = yX * lo + yY * py + y0p
						local z = zX * lo + zY * py + z0p
						local q = qX * lo + qY * py + q0p
						local d = dX * lo + dY * py + d0p
						for px = lo, hi do
							writeu32(buf, o, pack(shade(px, py, r, g, b, x, y, z, q, d)))
							o += 4
							r += rX
							g += gX
							b += bX
							x += xX
							y += yX
							z += zX
							q += qX
							d += dX
						end
					end
					-- a shaded texel costs several grain texels: yield about as often in time
					MeshKit.Step(simple and (hi - lo + 1) or (hi - lo + 1) * 4)
				end
			end
		end
		MeshKit.Step(1)
	end
	if keepEmpty then
		return buf
	end
	-- pad: empty texels next to filled ones copy them (filtering at UV seams), then the rest get the fill
	local readu8, readu32 = buffer.readu8, buffer.readu32
	for _ = 1, pad or 2 do
		local dst, src, n = {}, {}, 0
		for py = 0, h - 1 do
			local row = py * w
			for px = 0, w - 1 do
				local o = (row + px) * 4
				if readu8(buf, o + 3) == 0 then
					local s
					if px > 0 and readu8(buf, o - 1) ~= 0 then
						s = o - 4
					elseif px < w - 1 and readu8(buf, o + 7) ~= 0 then
						s = o + 4
					elseif py > 0 and readu8(buf, o - w * 4 + 3) ~= 0 then
						s = o - w * 4
					elseif py < h - 1 and readu8(buf, o + w * 4 + 3) ~= 0 then
						s = o + w * 4
					end
					if s then
						n += 1
						dst[n], src[n] = o, s
					end
				end
			end
			MeshKit.Step(w * 0.1)
		end
		for k = 1, n do
			writeu32(buf, dst[k], readu32(buf, src[k]))
		end
	end
	local fillV = floor(fill[1] * 255 + 0.5) + floor(fill[2] * 255 + 0.5) * 256 + floor(fill[3] * 255 + 0.5) * 65536 + 4278190080
	for py = 0, h - 1 do
		for o = py * w * 4, (py + 1) * w * 4 - 4, 4 do
			if readu8(buf, o + 3) == 0 then
				writeu32(buf, o, fillV)
			end
		end
		MeshKit.Step(w * 0.05)
	end
	return buf
end
Paint.Rasterize = rasterize

------------------------------------------------------------------------
-- The head texture (w x h). texelsPerStud: the atlas' texel density on the face (strokes are sized in texels)
------------------------------------------------------------------------
-- pscale: multipliers from the mesh's (scaled) positions back to nominal space
-- col / row: per texel column / row noise indices (see AnatomyHead noiseMaps); nil = texel coordinates
function Paint.Texture(m, F, look, w, h, faceV, pscale, col, row)
	if not col then
		col, row = table.create(w, 0), table.create(h, 0)
		for i = 1, w do
			col[i] = i - 1
		end
		for i = 1, h do
			row[i] = i - 1
		end
	end
	local psx, psy, psz = 1, 1, 1
	if pscale then
		psx, psy, psz = pscale[1], pscale[2], pscale[3]
	end
	local f = type(look.face) == "table" and look.face or {}
	local sr, sg, sb = Paint.Skin(look)
	local dark = darkness(sr, sg, sb)
	local scale = w / 512 -- stroke lengths in texels follow the atlas size
	-- women's skin a little finer by default (fewer, shallower pores)
	local smoothK = clamp(tonumber(f.smooth) or (F.female and 0.7 or 0.5), 0, 1)
	local poreK = clamp(tonumber(f.pores) or (F.female and 0.2 or 0.35), 0, 1)
	local grainA = (0.05 + 0.05 * poreK - 0.03 * smoothK) * (1 - 0.35 * dark)
	local poreA = (0.05 + 0.1 * poreK) * (1 - 0.4 * smoothK)
	local mottleA = 0.035 + 0.02 * (1 - smoothK)
	local hr, hg, hb = hairColor(look, F.age, false)
	local br, bg, bb = hairColor(look, F.age, true)
	local brow = Paint.BrowFrame(F)
	local bwR, bwG, bwB = browColor(hr, hg, hb)
	local beardZone = Paint.BeardZone(F)
	local style, _, growth = Paint.BeardStyle(look)
	-- shaved: faint follicles; stubble: denser and darker with growth; grown styles: dense under the beard
	local stub, stubDens = 0, 0
	if not F.female and F.age >= 16 then
		stub, stubDens = 0.22, 0.07
		if style then
			stub, stubDens = 0.5 + 0.5 * growth, 0.14 + 0.24 * growth
		end
	end
	local wr = F.wrinkles
	-- small maps (medium / low detail): a texel is millimetres wide there, so pores and stubble follicles would be
	-- specks (acne, pepper); they take their average tone instead
	local fine = w >= 256
	-- adults: a faint glabella crease whatever the wrinkle slider
	local glabK = clamp((F.age - 20) / 25, 0, 1) * (F.female and 0.2 or 0.35)
	local mW = F.mouthW
	local seed = F.seed
	local ox, oy = floor(MeshKit.Hash3(1, 2, 3, seed) * TS), floor(MeshKit.Hash3(4, 5, 6, seed) * TS)
	local eyes = F.eye
	local bY, nY, nbY, ntY = F.browY, F.nasionY, F.noseBaseY, F.noseTipY
	local chinY = F.chinY
	-- grain + mottling for this look: one lookup per texel
	local KT = table.create(TS * TS, 1)
	for j = 0, TS - 1 do
		for i = 0, TS - 1 do
			local idx = j * TS + i + 1
			KT[idx] = 1 + (TILE[idx] - 0.5) * grainA + (smoothAt(i * 0.25, j * 0.25) - 0.5) * mottleA
		end
		MeshKit.Step(TS * 0.5)
	end
	-- a low-frequency value breakup (+-4 %): no skin is one even tone (and it keeps the speculars from
	-- reading as lacquer)
	local lfx, lfy = MeshKit.Hash3(2, 9, 4, seed) * 50, MeshKit.Hash3(5, 1, 7, seed) * 50
	local function lowF(px, py)
		return 0.96 + 0.08 * smoothAt(px * 0.03 + lfx, py * 0.03 + lfy)
	end
	-- the beard zone per vertex (smooth: interpolated across each triangle like a colour)
	local neckTone = F.neckTone
	local Q = table.create(m.nv, 0)
	if stub > 0 then
		local P = m.P
		for i = 1, m.nv do
			local z = P[i * 3] * psz
			local y = P[i * 3 - 1] * psy
			if y < 0.12 and z < 0.17 then
				local x = P[i * 3 - 2] * psx
				-- none on the neck (F.neckTone: the Body's skin there, and its column has no stubble)
				Q[i] = beardZone(x, y, z) * (1 - (neckTone and neckTone(x, y, z) or 0))
				MeshKit.Step(2)
			end
		end
	end
	-- how much each vertex faces down (nostril openings are on the underside of the nose)
	local D = table.create(m.nv, 0)
	do
		local N = m.N
		for i = 1, m.nv do
			D[i] = clamp(-N[i * 3 - 1], 0, 1)
		end
	end
	local spots, grid, CELL, GX0, GY0, NX, NY = spotList(F, look)
	local hasSpots = #spots > 0
	local browLen = 9 * scale
	local brY0, brY1 = bY - 0.06, bY + 0.06
	local lipTop = F.mouthY + 0.06
	local lipBot = F.mouthY - 0.07
	-- the brows' hair strokes: per texel coverage and direction (sparse), drawn after the raster
	local BRC, BRX, BRY = {}, {}, {}
	-- the wrinkle lines of this face (seeded: their number, spacing, reach, bend and depth)
	local H3 = MeshKit.Hash3
	local foreLines, crowLines, neckLines = {}, {}, {}
	do
		local nL = 3 + ((H3(1, 1, seed) < wr - 0.35) and 1 or 0)
		local yl = bY + 0.05 + 0.006 * H3(2, 2, seed)
		for i = 1, nL do
			foreLines[i] = { yl, 0.16 + 0.07 * H3(i, 3, seed), 0.008 + 0.01 * H3(i, 4, seed), H3(i, 5, seed) * 6.28, (0.65 + 0.35 * H3(i, 6, seed)) * (i == 1 and 1 or 0.85) }
			yl += 0.024 + 0.01 * H3(i, 7, seed)
		end
		for i = 1, 3 do
			crowLines[i] = { (i - 2) * 0.38 + (H3(i, 8, seed) - 0.5) * 0.2, 0.03 + 0.02 * H3(i, 9, seed), H3(i, 10, seed) * 6.28 }
		end
		for i = 1, 2 do
			neckLines[i] = { chinY - 0.09 - (i - 1) * (0.05 + 0.02 * H3(i, 11, seed)) }
		end
	end
	local function shade(px, py, r, g, b, x, y, z, bz, down)
		-- grain: per-texel white noise, a few-texel mottling
		local ti = ((row[py + 1] + oy) % TS) * TS + (col[px + 1] + ox) % TS + 1
		local n = TILE[ti]
		-- the breakup by position over the face (the nose's own texture island takes the same tones as the face
		-- round it), by texel toward the back (where the grain-only texels use it)
		local lf = lowF(px, py)
		if z < 0.04 then
			local l3 = 0.96 + 0.08 * smoothAt(x * 9 + lfx, y * 9 + lfy)
			lf = l3 + (lf - l3) * smoothstep(-0.1, 0.04, z)
		end
		local k = KT[ti] * lf
		local ax = abs(x)
		-- the ears' island (below the head's map) and the back of the head: grain only. The nose patch's island
		-- sits there too: it takes the face's detail
		if z > 0.04 or (py > faceV and ax > 0.25) then
			return r * k, g * k, b * k
		end
		-- low detail: the eyes are painted (no eyeball pieces), averaged over the texel (F.paintEyesTex)
		local pe = F.paintEyesTex or F.paintEyes
		if pe then
			local er, eg, eb, ea = pe(x, y, z)
			if er then
				r, g, b = lerp(r, er, ea), lerp(g, eg, ea), lerp(b, eb, ea)
				if ea >= 1 then
					return r, g, b
				end
			end
		end
		-- pores: denser and deeper on the nose and the cheeks, none on the lips; faded out toward the back
		-- (no step in the skin's tone at the temples and the jaw)
		local wFace = 1 - smoothstep(-0.12, 0.02, z)
		local pz = 0.55
		if y < nY and y > nbY - 0.01 and ax < 0.1 then
			pz = 1
		elseif y < F.eyeY - 0.04 and y > F.mouthY - 0.02 and ax > 0.12 then
			pz = 0.85
		end
		if fine and n < 0.075 * pz * wFace then
			k -= poreA * pz
		end
		-- brows: a quarter-strength underpaint here (the skin between the hairs is shadowed by them); the hairs
		-- themselves are strokes drawn after the raster (BR*: coverage and direction per texel)
		if y > brY0 and y < brY1 and z < -0.2 then
			local s2, t, half, dens = brow(x, y)
			if s2 and abs(t) < half * 1.5 then
				local phi = s2 < 0.25 and lerp(1.25, 0.35, s2 / 0.25) or (s2 < 0.7 and lerp(0.35, 0.12, (s2 - 0.25) / 0.45) or lerp(0.12, -0.3, (s2 - 0.7) / 0.3))
				phi += t / half * 0.25 -- the upper hairs lie flatter, fanning
				local lat = x < 0 and 1 or -1 -- lateral is +px on the character's left (x < 0)
				local edge = 1 - smoothstep(half * 0.45, half * 1.45, abs(t))
				local ends = smoothstep(-0.18, 0.05, s2) * (1 - smoothstep(0.88, 1.12, s2))
				local cover = edge * ends
				if cover > 0 then
					local kk = cover * 0.25
					r, g, b = lerp(r, bwR, kk), lerp(g, bwG, kk), lerp(b, bwB, kk)
					local idx = py * w + px
					BRC[idx] = cover * dens
					BRX[idx], BRY[idx] = lat * cos(phi), -sin(phi)
				end
			end
		end
		-- lips: fine vertical creases, the vermilion border's white roll, a moist band, the dark lip line
		if y < lipTop and y > lipBot and ax < mW * 1.1 then
			local ml = F.mouthLine(x)
			local dy = y - ml
			local hu, hl = F.lipH(x)
			if dy < hu + 0.004 and dy > -hl - 0.004 then
				local crease = smoothAt((px + ox) * 0.55, (py + oy) * 0.06)
				local inL = dy >= 0 and dy / max(hu, 0.003) or -dy / max(hl, 0.003)
				local kk = (crease - 0.5) * 0.14 * (1 - smoothstep(0.75, 1, inL))
				k += kk
				if dy < -hl * 0.2 and dy > -hl * 0.7 then
					k += 0.05 * (1 - ax / mW) * (1 - dark * 0.5)
				end
				-- the vermilion border: a slightly darker rim where the lip meets the skin
				local bd = min(abs(dy - hu), abs(dy + hl))
				if bd < 0.0022 then
					k *= 1 - 0.07 * (1 - bd / 0.0022) * (1 - smoothstep(0.8, 1.05, ax / mW))
				end
				-- the line between the lips, and inside it the mouth (seen when the jaw opens)
				local lw = 1 - smoothstep(0.7, 1.0, ax / mW)
				if abs(dy) < 0.0028 * lw then
					local inside = (1 - smoothstep(0.0012, 0.0026, abs(dy))) * lw
					r, g, b = lerp(r, 0.2, inside), lerp(g, 0.045, inside), lerp(b, 0.05, inside)
					k *= 0.55
				end
			elseif dy > hu + 0.004 and dy < hu + 0.008 and ax < mW then
				k += 0.035 * (1 - ax / mW)
			end
		end
		-- nostrils: the openings under the tip, either side of the columella
		if y < nbY + 0.045 and y > nbY - 0.01 and ax < F.noseW * 1.2 then
			local nk = nostrilAt(F, x, y, z)
			if nk > 0 then
				-- the opening: dark, a warm red-brown deep inside
				local d = smoothstep(0.0, 0.75, nk) * smoothstep(0.0, 0.45, down)
				k *= 1 - 0.82 * d
				r, g, b = lerp(r, r * 0.9, d), lerp(g, g * 0.72, d), lerp(b, b * 0.72, d)
			end
			-- (the alar creases are the nose solid's own: its union with the face is crisp there, the AO darkens
			-- them; a painted ring never lies exactly on them and reads as a drawn arc on the cheek)
		end
		-- stubble: follicle dots over the beard zone, denser and darker as it grows
		if bz > 0.03 then
			local kk = (0.22 + 0.3 * (style and growth or 0)) * stub * (1 - 0.55 * dark) * bz
			if fine then
				local d = TILE[((py + oy * 3 + 17) % TS) * TS + (px + ox * 5 + 29) % TS + 1]
				if d >= stubDens * bz then
					kk = 0
				end
			else
				kk *= min(1, stubDens * bz * 1.3)
			end
			if kk > 0 then
				r, g, b = lerp(r, br * 0.65, kk), lerp(g, bg * 0.65, kk), lerp(b, bb * 0.65 + 0.015, kk)
			end
		end
		-- the glabella's frown lines: faint on every adult (the knit morph folds the skin there), deeper with age
		if ax < 0.03 and y > bY - 0.03 and y < bY + 0.045 then
			local line = bump(((ax - 0.013) / 0.0035) ^ 2)
			local hi = bump(((ax - 0.0175) / 0.003) ^ 2)
			local gk = max(wr, glabK)
			k += (0.3 * hi - line) * 0.09 * gk * bump(((y - bY - 0.008) / 0.04) ^ 2)
		end
		-- wrinkles: a few seeded lines each (forehead arcs, crow's feet, under the eyes, the neck), every line a
		-- soft shadow with a highlight on its upper side (a fold, not a drawn stripe)
		if wr > 0.12 then
			if y > bY + 0.03 and y < bY + 0.2 and ax < 0.27 then
				for _, L in ipairs(foreLines) do
					local yl = L[1] + L[3] * (x / L[2]) ^ 2 + 0.0018 * sin(x * 23 + L[4])
					local d = y - yl
					if d > -0.008 and d < 0.012 then
						local ends = 1 - smoothstep(L[2] * 0.75, L[2], ax)
						local a = 0.13 * wr * L[5] * ends
						k += a * (0.5 * bump(((d - 0.0042) / 0.0032) ^ 2) - bump((d / 0.0026) ^ 2))
					end
				end
			end

			for side = -1, 1, 2 do
				local e = eyes[side]
				local dx, dy = (x - e.x) * side, y - e.y
				if dx > 0.055 and dx < 0.13 and dy > -0.05 and dy < 0.045 then
					for _, C3 in ipairs(crowLines) do
						local ca, sa = cos(C3[1]), sin(C3[1])
						local ux, uy = dx - 0.064, dy - 0.002
						local along = ux * ca + uy * sa
						local across = -ux * sa + uy * ca + 0.002 * sin(along * 90 + C3[3])
						if along > 0 and along < C3[2] then
							local fade = smoothstep(0, 0.008, along) * (1 - smoothstep(C3[2] * 0.6, C3[2], along))
							local a = 0.14 * wr * fade
							k += a * (0.45 * bump(((across - 0.0035) / 0.0028) ^ 2) - bump((across / 0.0022) ^ 2))
						end
					end
				end
				if abs(dx) < 0.06 and dy < -0.03 and dy > -0.07 then
					local yl = -0.045 - 0.006 * (dx / 0.06) ^ 2
					k -= 0.07 * wr * bump(((dy - yl) / 0.005) ^ 2) * (1 - smoothstep(0.03, 0.06, abs(dx)))
				end
			end
			if y < chinY - 0.05 and y > chinY - 0.26 and z < 0.02 then
				local nk = 1 - (neckTone and neckTone(x, y, z) or 0)
				for _, L in ipairs(neckLines) do
					local yl = L[1] - 0.02 * (x / 0.2) ^ 2
					local d = y - yl
					k -= 0.06 * wr * bump((d / 0.004) ^ 2) * (1 - smoothstep(0.16, 0.24, ax)) * nk
				end
			end
		end
		-- spots
		if hasSpots and z < -0.15 then
			local cx3, cy3 = floor((x - GX0) / CELL), floor((y - GY0) / CELL)
			if cx3 >= 0 and cx3 < NX and cy3 >= 0 and cy3 < NY then
				local cell = grid[cy3 * NX + cx3 + 1]
				if cell then
					for _, si in ipairs(cell) do
						local sp = spots[si]
						local ox2, oy2 = x - sp.x, y - sp.y
						local d
						if sp.len > 0 then
							local al = ox2 * sp.ca + oy2 * sp.sa
							local ac = -ox2 * sp.sa + oy2 * sp.ca
							local cl = clamp(al, -sp.len * 0.5, sp.len * 0.5)
							d = sqrt((al - cl) ^ 2 + ac * ac)
						else
							d = sqrt(ox2 * ox2 + oy2 * oy2)
						end
						local wgt = (1 - smoothstep(sp.r * 0.5, sp.r, d)) * sp.a
						if wgt > 0 then
							r, g, b = lerp(r, sp.cr, wgt), lerp(g, sp.cg, wgt), lerp(b, sp.cb, wgt)
						end
					end
				end
			end
		end
		return r * k, g * k, b * k
	end
	-- triangles that only need the grain: the back of the head, the scalp above the forehead lines, the
	-- ears (below the head grid in v), the neck stub
	local P, U = m.P, m.U
	local yTop, yNeck = bY + 0.2, chinY - 0.26
	local vMax = faceV / h
	local function simpleTri(ia, ib, ic)
		local za, zb, zc = P[ia * 3] * psz, P[ib * 3] * psz, P[ic * 3] * psz
		if za > 0.05 and zb > 0.05 and zc > 0.05 then
			return true
		end
		local ya, yb, yc = P[ia * 3 - 1] * psy, P[ib * 3 - 1] * psy, P[ic * 3 - 1] * psy
		if (ya > yTop and yb > yTop and yc > yTop) or (ya < yNeck and yb < yNeck and yc < yNeck) then
			return true
		end
		return U[ia * 2] > vMax and U[ib * 2] > vMax and U[ic * 2] > vMax
	end
	local buf = rasterize(m, w, h, shade, 2, { sr * 0.9, sg * 0.9, sb * 0.9 }, Q, { KT = KT, ox = ox, oy = oy, col = col, row = row, lf = lowF }, simpleTri, pscale, D)
	-- the brow hairs: short strokes (3..6 texels at 384) from random roots along each hair's direction, drawn
	-- anti-aliased (each step shared between the two texels across the stroke), darker at the root
	local readu8, writeu8 = buffer.readu8, buffer.writeu8
	local sc = w / 384
	local function blend(qx, qy, cr, cg, cb, al)
		if qx < 0 or qx >= w or qy < 0 or qy >= h or al <= 0.003 then
			return
		end
		local o = (qy * w + qx) * 4
		writeu8(buf, o, floor(lerp(readu8(buf, o), cr, al) + 0.5))
		writeu8(buf, o + 1, floor(lerp(readu8(buf, o + 1), cg, al) + 0.5))
		writeu8(buf, o + 2, floor(lerp(readu8(buf, o + 2), cb, al) + 0.5))
	end
	for idx, cov in pairs(BRC) do
		local px, py = idx % w, idx // w
		local hv = TILE[((py * 7 + oy + 3) % TS) * TS + (px * 5 + ox + 11) % TS + 1]
		local Ls = (3 + 3 * TILE[((py * 3 + ox) % TS) * TS + (px * 11 + oy) % TS + 1]) * sc
		if hv < cov * 0.95 / Ls * 2.2 then
			local dx, dy = BRX[idx], BRY[idx]
			local var = 0.85 + 0.3 * TILE[((py * 13 + 5) % TS) * TS + (px * 7 + 9) % TS + 1]
			local cr, cg, cb = clamp(bwR * var, 0, 1) * 255, clamp(bwG * var, 0, 1) * 255, clamp(bwB * var, 0, 1) * 255
			local t = 0
			while t <= Ls do
				local f = t / Ls
				local al = (0.7 - 0.45 * f) * min(1, cov * 1.4)
				local fx, fy = px + dx * t, py + dy * t
				-- across the stroke: split between the two nearest texels (perpendicular to the direction)
				local nx2, ny2 = -dy, dx
				local q = fx * nx2 + fy * ny2
				local qf = q - floor(q)
				local bx, by = floor(fx - nx2 * qf + 0.5), floor(fy - ny2 * qf + 0.5)
				local ax2, ay2 = floor(bx + nx2 + 0.5), floor(by + ny2 + 0.5)
				blend(bx, by, cr, cg, cb, al * (1 - qf))
				blend(ax2, ay2, cr, cg, cb, al * qf)
				t += 0.6
			end
			MeshKit.Step(4)
		end
		MeshKit.Step(1)
	end
	return buf
end

------------------------------------------------------------------------
-- Beard texture: the head's texture under the shell (same UVs) with hair strands over it, their density
-- following the coverage (Q: per beard vertex, 0 at the sunken edge .. 1 inside), so the beard thins
-- into the skin instead of ending at a cut edge
------------------------------------------------------------------------
-- mask(x, y, z): the style's coverage at a nominal point (evaluated per texel: smooth edges at any grid size)
-- inPlace: m is the head itself (same texture): only the triangles the beard touches are shaded, over a copy of
-- headBuf (the rest of the head's texture is kept as it is)
function Paint.BeardTexture(m, Q, headBuf, headW, headH, F, look, w, h, pscale, mask, inPlace)
	local br, bg, bb = hairColor(look, F.age, true)
	local style, _, growth = Paint.BeardStyle(look)
	local seed = F.seed + 77
	-- strand length in texels (6..14 at 384: longer growth, longer strands; a full beard longer still)
	local L = (6 + 8 * growth) * (w / 384)
	if style == "Full Beard" then
		L *= 1.25
	end
	L = max(L, 3)
	local grey = clamp((F.age - 38) / 25, 0, 0.6)
	local readu8, writeu8 = buffer.readu8, buffer.writeu8
	local mW = F.mouthW
	local dk = darkness(br, bg, bb)
	-- dark hair shows its strands by their sheen
	local shR, shG, shB = lerp(br, 0.36, 0.34 * dk), lerp(bg, 0.32, 0.34 * dk), lerp(bb, 0.29, 0.34 * dk)
	local noise = MeshKit.Noise
	-- per texel coverage and growth direction (f32 buffers: no GC traversal, zeroed on creation)
	local COV = buffer.create(w * h * 4)
	local DXY = buffer.create(w * h * 8)
	local readf32, writef32 = buffer.readf32, buffer.writef32
	-- the covered texels' bounds (the strands' pass walks only those)
	local bx0, bx1, by0, by1 = w, -1, h, -1
	-- pass 1 (the rasterizer): the skin under the beard, darkened into the beard's body where it is dense;
	-- per texel the coverage and the growth direction for the strands
	local function shade(px, py, r, g, b, x, y, z, cov)
		local u, v = (px + 0.5) / w, (py + 0.5) / h
		local hx, hy = min(headW - 1, floor(u * headW)), min(headH - 1, floor(v * headH))
		local o = (hy * headW + hx) * 4
		local sr, sg, sb = readu8(headBuf, o) / 255, readu8(headBuf, o + 1) / 255, readu8(headBuf, o + 2) / 255
		if inPlace then
			-- the head's own triangles are fine round the mouth: the coverage interpolated from its vertices,
			-- the edge broken up per texel (cheap: no mask evaluation per texel over the whole beard)
			if cov > 0.005 and cov < 0.995 then
				local e = 4 * cov * (1 - cov)
				cov = clamp(cov + (TILE[((py * 3 + 7) % TS) * TS + (px * 5 + 3) % TS + 1] - 0.5) * 0.45 * e, 0, 1)
			end
		elseif mask then
			cov = mask(x, y, z)
		end
		if cov <= 0.01 then
			return sr, sg, sb
		end
		-- growth direction (texel space: +py is down the face): down and a little outward along the jaw,
		-- out from the philtrum on the moustache
		local lat = x < 0 and 1 or -1
		local ax = abs(x)
		local tilt = 0.3 * smoothstep(0.06, 0.3, ax)
		if y > F.mouthLine(clamp(x, -mW, mW)) then
			tilt = 0.6 * smoothstep(0.004, 0.05, ax)
		end
		local dx, dy = lat * tilt, 1
		local l = sqrt(dx * dx + dy * dy)
		local idx = py * w + px
		writef32(COV, idx * 4, cov)
		writef32(DXY, idx * 8, dx / l)
		writef32(DXY, idx * 8 + 4, dy / l)
		if cov > 0.03 then
			if px < bx0 then
				bx0 = px
			end
			if px > bx1 then
				bx1 = px
			end
			if py < by0 then
				by0 = py
			end
			if py > by1 then
				by1 = py
			end
		end
		-- the underpaint (the beard's shadowed depth) only in the dense core: the outer third is strands over
		-- skin; clumps of hair catch the light unevenly (no flat slab of colour)
		local baseK = smoothstep(0.4, 1.0, cov) * 0.72
		local clump = noise(x * 60, y * 75, z * 60, seed + 9) * 0.6 + noise(x * 160, y * 200, z * 160, seed + 13) * 0.4
		local kb = (0.6 + 0.12 * (1 - dk)) * (0.82 + 0.45 * clump)
		local lift = 0.05 * dk * clump
		return lerp(sr, br * kb + lift, baseK), lerp(sg, bg * kb + lift, baseK), lerp(sb, bb * kb + lift * 0.9, baseK)
	end
	local buf
	if inPlace then
		-- the beard's triangles only (any corner covered), merged over a copy of the head's texture
		local T = m.T
		local Ts = {}
		for t = 1, m.nt do
			local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
			if (Q[a] or 0) > 0.001 or (Q[b] or 0) > 0.001 or (Q[c] or 0) > 0.001 then
				Ts[#Ts + 1], Ts[#Ts + 2], Ts[#Ts + 3] = a, b, c
			end
		end
		local sub = rasterize({ P = m.P, U = m.U, C = m.C, T = Ts, nt = #Ts // 3 }, w, h, shade, 0, nil, Q, nil, nil, pscale, nil, true)
		buf = buffer.create(w * h * 4)
		buffer.copy(buf, 0, headBuf, 0, w * h * 4)
		local readu32, writeu32 = buffer.readu32, buffer.writeu32
		for y = 0, h - 1 do
			for o = y * w * 4, y * w * 4 + w * 4 - 4, 4 do
				local v = readu32(sub, o)
				if v >= 16777216 then
					writeu32(buf, o, v)
				end
			end
			MeshKit.Step(w // 8)
		end
	else
		buf = rasterize(m, w, h, shade, 2, { br * 0.8, bg * 0.8, bb * 0.8 }, Q, nil, nil, pscale)
	end
	-- pass 2: strands, each a short straight stroke along the growth direction from a random start, its own
	-- length and shade (+-12 %), lighter toward the tip and thinning out; fewer where the beard thins (the
	-- skin shows between them). Strokes, not lanes of a grid: no moire where the direction turns
	-- per-texel random numbers from the noise tile (four decorrelated lookups)
	local ox, oy = floor(MeshKit.Hash3(7, 8, 9, seed) * TS), floor(MeshKit.Hash3(9, 8, 7, seed) * TS)
	local function rnd(px, py, k)
		return TILE[((py * (3 + 2 * k) + px * k + oy + 31 * k) % TS) * TS + (px * (5 + 2 * k) + py * (k + 1) + ox + 17 * k) % TS + 1]
	end
	for py = max(0, by0), min(h - 1, by1) do
		for px = max(0, bx0), min(w - 1, bx1) do
			local idx = py * w + px
			local cov = readf32(COV, idx * 4)
			if cov > 0.03 then
				local hv = rnd(px, py, 0)
				local Ls = L * (0.6 + 0.7 * rnd(px, py, 1))
				local dens = clamp(cov * 1.2, 0, 1)
				if hv < dens * 1.5 / Ls then
					local dx, dy = readf32(DXY, idx * 8), readf32(DXY, idx * 8 + 4)
					local var = 0.88 + 0.24 * rnd(px, py, 2)
					local isGrey = rnd(px, py, 3) < 0.6 * grey
					local a0 = 0.55 + 0.4 * dens
					local t = 0
					while t <= Ls do
						local qx, qy = floor(px + dx * t + 0.5), floor(py + dy * t + 0.5)
						if qx >= 0 and qx < w and qy >= 0 and qy < h then
							local qi = qy * w + qx
							local c2 = readf32(COV, qi * 4)
							if c2 > 0.01 then
								local f = t / Ls
								local tip = (0.82 + 0.4 * f) * var
								local cr, cg, cb = lerp(br, shR, f) * tip, lerp(bg, shG, f) * tip, lerp(bb, shB, f) * tip
								if isGrey then
									cr, cg, cb = 0.74 * var, 0.73 * var, 0.71 * var
								end
								local al = a0 * (1 - 0.55 * f * f) * smoothstep(0.01, 0.25, c2)
								local o = qi * 4
								writeu8(buf, o, floor(lerp(readu8(buf, o), clamp(cr, 0, 1) * 255, al) + 0.5))
								writeu8(buf, o + 1, floor(lerp(readu8(buf, o + 1), clamp(cg, 0, 1) * 255, al) + 0.5))
								writeu8(buf, o + 2, floor(lerp(readu8(buf, o + 2), clamp(cb, 0, 1) * 255, al) + 0.5))
							end
						end
						t += 0.7
					end
					MeshKit.Step(4 + Ls)
				end
			end
		end
		MeshKit.Step(w // 16)
	end
	return buf
end

return Paint
