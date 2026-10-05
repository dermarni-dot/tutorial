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
	local arch = (0.012 * st.arch + 0.005 * (F.browAngle or 0)) * (F.female and 1.3 or 1)
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
	return function(x, y, z)
		if z > 0.16 or y > 0.1 then
			return 0
		end
		local ax = abs(x)
		local line = cheekLine(ax)
		local w = smoothstep(line + 0.022, line - 0.035, y)
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
		-- down the front of the neck to the neckline, not round the back
		w *= smoothstep(cy - 0.2, cy - 0.12, y)
		w *= 1 - smoothstep(0.06, 0.15, z)
		-- the sideburn stays narrow in front of the ear
		if y > -0.08 then
			w *= smoothstep(0.34, 0.39, ax) * (1 - smoothstep(0.02, 0.09, z)) + (y < -0.02 and smoothstep(-0.02, -0.08, y) or 0)
			w = clamp(w, 0, 1)
		end
		return w
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
	local lipR, lipG, lipB = lerp(sr * 0.85, sr * 0.78, dark), lerp(sg * 0.54, sg * 0.66, dark), lerp(sb * 0.55, sb * 0.78, dark)
	local flushK = (1 - 0.7 * dark) * 0.6
	local P, C = m.P, m.C
	for i = first or 1, last or m.nv do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		local r, g, b = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
		local ax = abs(x)
		if z < -0.08 then
			-- warmth: malar cheeks, the nose tip and wings, the chin; a little sallower forehead
			local fl = bump(((ax - 0.22) / 0.12) ^ 2 + ((y - F.eyeY + 0.09) / 0.09) ^ 2) * 0.9
				+ bump((x / 0.075) ^ 2 + ((y - F.noseTipY + 0.01) / 0.06) ^ 2) * 0.8
				+ bump((x / 0.09) ^ 2 + ((y - F.chinY - 0.03) / 0.05) ^ 2) * 0.35
			if fl > 0 then
				local k = fl * flushK * 0.22
				r, g, b = r * (1 + 0.25 * k), g * (1 - 0.55 * k), b * (1 - 0.55 * k)
			end
			if y > F.browY + 0.03 then
				local k = smoothstep(F.browY + 0.03, F.browY + 0.12, y) * 0.03
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
					local lr, lg, lb = lerp(lipR, 0.52, inner), lerp(lipG, 0.28, inner), lerp(lipB, 0.29, inner)
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
					r, g, b = lerp(r, hr * 0.85, w), lerp(g, hg * 0.85, w), lerp(b, hb * 0.85, w)
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
			local nq = ((ax - F.noseW * 0.4) / (F.noseW * 0.34)) ^ 2 + ((y - F.noseBaseY - 0.005) / 0.012) ^ 2
			if nq < 1 then
				local k = bump(nq) * 0.5 * smoothstep(0.15, 0.6, -m.N[i * 3 - 1])
				r, g, b = r * (1 - k), g * (1 - k), b * (1 - k)
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
	end
	MeshKit.Step((last or m.nv) - (first or 1))
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
local function rasterize(m, w, h, shade, pad, fill, Q, grain, simpleTri, pscale, D)
	local buf = buffer.create(w * h * 4)
	local P, U, C, T = m.P, m.U, m.C, m.T
	Q = Q or {}
	D = D or {}
	local writeu32 = buffer.writeu32
	local EPS = -1e-7
	local KT, gox, goy = grain and grain.KT, grain and grain.ox or 0, grain and grain.oy or 0
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
	local smoothK = clamp(tonumber(f.smooth) or 0.5, 0, 1)
	local poreK = clamp(tonumber(f.pores) or 0.35, 0, 1)
	local grainA = (0.05 + 0.05 * poreK - 0.03 * smoothK) * (1 - 0.35 * dark)
	local poreA = (0.05 + 0.1 * poreK) * (1 - 0.4 * smoothK)
	local mottleA = 0.035 + 0.02 * (1 - smoothK)
	local hr, hg, hb = hairColor(look, F.age, false)
	local br, bg, bb = hairColor(look, F.age, true)
	local brow = Paint.BrowFrame(F)
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
	-- the beard zone per vertex (smooth: interpolated across each triangle like a colour)
	local Q = table.create(m.nv, 0)
	if stub > 0 then
		local P = m.P
		for i = 1, m.nv do
			local z = P[i * 3] * psz
			local y = P[i * 3 - 1] * psy
			if y < 0.12 and z < 0.17 then
				Q[i] = beardZone(P[i * 3 - 2] * psx, y, z)
			end
		end
		MeshKit.Step(m.nv)
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
	local function shade(px, py, r, g, b, x, y, z, bz, down)
		-- grain: per-texel white noise, a few-texel mottling
		local ti = ((row[py + 1] + oy) % TS) * TS + (col[px + 1] + ox) % TS + 1
		local n = TILE[ti]
		local k = KT[ti]
		if py > faceV or z > -0.05 then
			return r * k, g * k, b * k
		end
		local ax = abs(x)
		-- pores: denser and deeper on the nose and the cheeks, none on the lips
		local pz = 0.55
		if y < nY and y > nbY - 0.01 and ax < 0.1 then
			pz = 1
		elseif y < F.eyeY - 0.04 and y > F.mouthY - 0.02 and ax > 0.12 then
			pz = 0.85
		end
		if n < 0.075 * pz then
			k -= poreA * pz
		end
		-- brow hairs: strokes along each hair's direction (up at the head, outward along the body, down at the tail)
		if y > brY0 and y < brY1 and z < -0.2 then
			local s, t, half, dens = brow(x, y)
			if s and abs(t) < half * 1.5 then
				local phi = s < 0.25 and lerp(1.25, 0.35, s / 0.25) or (s < 0.7 and lerp(0.35, 0.12, (s - 0.25) / 0.45) or lerp(0.12, -0.3, (s - 0.7) / 0.3))
				phi += t / half * 0.25 -- the upper hairs lie flatter, fanning
				local lat = x < 0 and 1 or -1 -- lateral is +px on the character's left (x < 0)
				local dx, dy = lat * cos(phi), -sin(phi)
				local a = px * dx + py * dy
				local c = -px * dy + py * dx
				local lane = floor(c * 0.9)
				local off = TILE[(lane % TS) * 3 % (TS * TS) + 1]
				local seg = floor(a / browLen + off)
				local hv = TILE[((lane * 7 + seg * 13) % TS) * TS + (seg * 5 + lane) % TS + 1]
				local frac = a / browLen + off - seg
				local edge = 1 - smoothstep(half * 0.45, half * 1.45, abs(t))
				local ends = smoothstep(-0.18, 0.05, s) * (1 - smoothstep(0.88, 1.12, s))
				local cover = edge * ends
				if cover > 0 then
					local hair = hv < 0.55 * dens * (0.35 + 0.65 * cover) and (1 - 0.6 * frac) or 0
					local kk = clamp(hair * (0.55 + 0.45 * cover) + cover * 0.22, 0, 0.95)
					r, g, b = lerp(r, hr * 0.8, kk), lerp(g, hg * 0.8, kk), lerp(b, hb * 0.8, kk)
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
		if y < nbY + 0.03 and y > nbY - 0.01 and ax < F.noseW then
			local q = ((ax - F.noseW * 0.4) / (F.noseW * 0.3)) ^ 2 + ((y - nbY - 0.005) / 0.01) ^ 2
			if q < 1 then
				k *= 1 - bump(q) * 0.75 * smoothstep(0.15, 0.6, down)
			end
			-- the alar crease: a soft shadow line round the wing
			local cx2 = (ax - F.noseW * 0.72) / (F.noseW * 0.45)
			local cy2 = (y - nbY - 0.022) / 0.034
			local cr = sqrt(cx2 * cx2 + cy2 * cy2)
			if cr > 0.8 and cr < 1.25 and cy2 > -0.6 then
				k *= 1 - 0.12 * bump(((cr - 1.02) / 0.2) ^ 2)
			end
		end
		-- stubble: follicle dots over the beard zone, denser and darker as it grows
		if bz > 0.03 then
			do
				local d = TILE[((py + oy * 3 + 17) % TS) * TS + (px + ox * 5 + 29) % TS + 1]
				if d < stubDens * bz then
					local kk = (0.35 + 0.35 * (style and growth or 0)) * stub * (1 - 0.55 * dark) * bz
					r, g, b = lerp(r, br * 0.65, kk), lerp(g, bg * 0.65, kk), lerp(b, bb * 0.65 + 0.015, kk)
				end
			end
		end
		-- wrinkles: forehead lines, glabella, crow's feet, under the eyes, the neck (age / slider)
		if wr > 0.12 then
			if y > bY + 0.035 and y < bY + 0.18 and ax < 0.26 then
				local ph = (y - bY - 0.035) * 220 + (smoothAt(x * 30 + 7, 3) - 0.5) * 4
				local line = smoothstep(0.86, 0.99, cos(ph))
				k -= line * 0.15 * wr * (1 - smoothstep(0.16, 0.26, ax)) * smoothstep(bY + 0.035, bY + 0.06, y)
			end
			if ax < 0.03 and y > bY - 0.03 and y < bY + 0.045 then
				local line = bump(((ax - 0.014) / 0.004) ^ 2)
				k -= line * 0.1 * wr * bump(((y - bY - 0.008) / 0.04) ^ 2)
			end
			for side = -1, 1, 2 do
				local e = eyes[side]
				local dx, dy = (x - e.x) * side, y - e.y
				if dx > 0.06 and dx < 0.13 and dy > -0.05 and dy < 0.04 then
					local ang = math.atan2(dy + 0.005, dx - 0.055)
					local line = smoothstep(0.82, 0.98, cos(ang * 11 + (smoothAt(x * 40, y * 40) - 0.5) * 3))
					k -= line * 0.17 * wr * (1 - smoothstep(0.09, 0.13, dx)) * smoothstep(0.06, 0.075, dx)
				end
				if abs(dx) < 0.06 and dy < -0.03 and dy > -0.07 then
					local yl = -0.045 - 0.006 * (dx / 0.06) ^ 2
					k -= 0.08 * wr * bump(((dy - yl) / 0.006) ^ 2) * (1 - smoothstep(0.03, 0.06, abs(dx)))
				end
			end
			if y < chinY - 0.06 and y > chinY - 0.24 and z < 0 then
				local ph = (y - chinY) * 120
				k -= smoothstep(0.9, 0.99, cos(ph)) * 0.06 * wr
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
		if za > -0.04 and zb > -0.04 and zc > -0.04 then
			return true
		end
		local ya, yb, yc = P[ia * 3 - 1] * psy, P[ib * 3 - 1] * psy, P[ic * 3 - 1] * psy
		if (ya > yTop and yb > yTop and yc > yTop) or (ya < yNeck and yb < yNeck and yc < yNeck) then
			return true
		end
		return U[ia * 2] > vMax and U[ib * 2] > vMax and U[ic * 2] > vMax
	end
	return rasterize(m, w, h, shade, 2, { sr * 0.9, sg * 0.9, sb * 0.9 }, Q, { KT = KT, ox = ox, oy = oy, col = col, row = row }, simpleTri, pscale, D)
end

------------------------------------------------------------------------
-- Beard texture: the head's texture under the shell (same UVs) with hair strands over it, their density
-- following the coverage (Q: per beard vertex, 0 at the sunken edge .. 1 inside), so the beard thins
-- into the skin instead of ending at a cut edge
------------------------------------------------------------------------
-- mask(x, y, z): the style's coverage at a nominal point (evaluated per texel: smooth edges at any grid size)
function Paint.BeardTexture(m, Q, headBuf, headW, headH, F, look, w, h, pscale, mask)
	local br, bg, bb = hairColor(look, F.age, true)
	local style, _, growth = Paint.BeardStyle(look)
	local seed = F.seed + 77
	local ox, oy = floor(MeshKit.Hash3(7, 8, 9, seed) * TS), floor(MeshKit.Hash3(9, 8, 7, seed) * TS)
	local L = (5 + 9 * growth) * (w / 256) -- strand length in texels
	if style == "Full Beard" then
		L *= 1.5
	end
	local grey = clamp((F.age - 38) / 25, 0, 0.6)
	local readu8 = buffer.readu8
	local mW = F.mouthW
	local function shade(px, py, r, g, b, x, y, z, cov)
		-- the skin (and stubble) under the beard: the head texture at the same UV
		local u, v = (px + 0.5) / w, (py + 0.5) / h
		local hx, hy = min(headW - 1, floor(u * headW)), min(headH - 1, floor(v * headH))
		local o = (hy * headW + hx) * 4
		local sr, sg, sb = readu8(headBuf, o) / 255, readu8(headBuf, o + 1) / 255, readu8(headBuf, o + 2) / 255
		if mask then
			cov = mask(x, y, z)
		end
		if cov <= 0.01 then
			return sr, sg, sb
		end
		-- growth direction (texel space: +py is down the face): down, a little outward on the cheeks, out
		-- from the philtrum on the moustache
		local lat = x < 0 and 1 or -1
		local ax = abs(x)
		local tilt = 0.25 * smoothstep(0.08, 0.3, ax)
		if y > F.mouthLine(clamp(x, -mW, mW)) then
			tilt = 0.55 * smoothstep(0.005, 0.05, ax)
		end
		local dx, dy = lat * tilt, 1
		local l = sqrt(dx * dx + dy * dy)
		dx, dy = dx / l, dy / l
		local a = px * dx + py * dy
		local c = -px * dy + py * dx
		local lane = floor(c)
		local off = TILE[((lane * 3 + ox) % TS) * TS + (lane * 7 + oy) % TS + 1]
		local seg = floor(a / L + off)
		local hv = TILE[((lane * 11 + seg * 5 + oy) % TS) * TS + (seg * 13 + lane + ox) % TS + 1]
		local frac = a / L + off - seg
		local dens = clamp(cov * 1.4, 0, 1)
		-- the beard's own body colour where it is dense, the skin where it thins
		local baseK = smoothstep(0.15, 0.8, cov)
		local kb = 0.7 + 0.25 * TILE[((py + oy) % TS) * TS + (px + ox) % TS + 1]
		local rr, gg, bb2 = lerp(sr, br * kb, baseK), lerp(sg, bg * kb, baseK), lerp(sb, bb * kb, baseK)
		if hv < 0.25 + 0.6 * dens then
			-- a strand: darker at the root, lighter toward the tip; a few grey ones with age
			local tip = 0.75 + 0.55 * frac
			local hr2, hg2, hb2 = br * tip, bg * tip, bb * tip
			if hv < 0.25 * grey then
				hr2, hg2, hb2 = 0.75, 0.74, 0.72
			end
			local kk = clamp(0.35 + 0.6 * dens, 0, 0.95)
			rr, gg, bb2 = lerp(rr, hr2, kk), lerp(gg, hg2, kk), lerp(bb2, hb2, kk)
		end
		return rr, gg, bb2
	end
	return rasterize(m, w, h, shade, 2, { br * 0.8, bg * 0.8, bb * 0.8 }, Q, nil, nil, pscale)
end

return Paint
