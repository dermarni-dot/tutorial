-- AnatomyHeadRig: what moves the AnatomyHead meshes and what sits inside / on them.
-- * face morphs on the Head piece (FaceFX channels, breathing, cheeks, fight swelling)
-- * the mouth interior: MouthUpper (upper teeth, palate, throat) is fixed to the skull, MouthLower (lower
--   teeth, tongue, floor) swings with the jaw (FaceFX: SetPieceTransform about JawPivot by JAW_OPEN * open)
-- * beards as shells grown from the head grid (style masks, growth, an `open` morph that follows the jaw)
-- * landmarks (ANATOMY_CONTRACTS section 10)
-- Everything in the nominal head space (AnatomyHead's layout F, before the final scale).
local MeshKit = require(script.Parent:WaitForChild("MeshKit"))
local Paint = require(script.Parent:WaitForChild("AnatomyHeadPaint"))

local Rig = {}

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
-- Jaw
------------------------------------------------------------------------
Rig.JAW_OPEN = rad(13) -- the jaw's rotation at open = 1 (the morph and MouthLower agree)

-- the temporomandibular joints' mid-point (the jaw's hinge axis is the X axis through it)
function Rig.JawPivot(F)
	return 0, F.eyeY - 0.1, 0.05
end

-- offset of a point rotated with the jaw by `amount` of JAW_OPEN (chin down and back)
local function jawDelta(F, x, y, z, amount)
	local _, py, pz = Rig.JawPivot(F)
	local th = -Rig.JAW_OPEN * (amount or 1)
	local c, s = cos(th), sin(th)
	local ry, rz = y - py, z - pz
	return 0, ry * c - rz * s - ry, ry * s + rz * c - rz
end
Rig.JawDelta = jawDelta

-- how much of the jaw's motion a skin point follows: the lower lip and chin fully, the upper lip not at
-- all (the parting line is the stomion), the cheeks partly over a band rising toward the ear, the throat
-- and the back of the jaw not at all
local function jawMask(F, x, y, z)
	if z > 0.12 then
		return 0
	end
	local mW = F.mouthW
	local ax = abs(x)
	local beyond = max(0, ax - mW)
	local line = F.mouthLine(clamp(x, -mW, mW)) + beyond * 0.55
	local band = 0.003 + beyond * 0.35
	local j = 1 - smoothstep(-band, band, y - line)
	j *= smoothstep(F.chinY - 0.17, F.chinY - 0.04, y)
	j *= 1 - smoothstep(-0.02, 0.1, z)
	return j
end
Rig.JawMask = jawMask

------------------------------------------------------------------------
-- Morphs
------------------------------------------------------------------------
-- every morph of the Head piece: name -> fn(x, y, z, side) -> dx, dy, dz (nil = untouched), nominal studs
local function faceMorphFns(F)
	local mW = F.mouthW
	local eyeY, browY = F.eyeY, F.browY
	local nb, nas = F.noseBaseY, F.nasionY
	local alaX = F.noseW * 0.72
	local E = F.eye
	local function cornerW(ax, y, x)
		local ml = F.mouthLine(clamp(x, -mW, mW))
		return bump(((ax - mW * 0.97) / 0.075) ^ 2 + ((y - ml) / 0.055) ^ 2)
	end
	local function lipMask(x, y)
		local ax = abs(x)
		if ax > mW * 1.05 then
			return 0, 0
		end
		local dy = y - F.mouthLine(x)
		local hu, hl = F.lipH(x)
		local w
		if dy >= 0 then
			w = 1 - smoothstep(hu * 0.9, hu + 0.012, dy)
		else
			w = 1 - smoothstep(hl * 0.9, hl + 0.012, -dy)
		end
		return w * (1 - smoothstep(0.85, 1.05, ax / mW)), dy
	end
	local fns = {}
	fns.open = function(x, y, z)
		local j = jawMask(F, x, y, z)
		local ax = abs(x)
		local dx, dy, dz = 0, 0, 0
		if j > 0.001 then
			dx, dy, dz = jawDelta(F, x, y, z, 1)
			dx, dy, dz = dx * j, dy * j, dz * j
		end
		local dyl = y - F.mouthLine(clamp(x, -mW, mW))
		-- the stomion (the deepest point between the lips) draws back into the mouth
		if ax < mW * 0.98 and abs(dyl) < 0.003 then
			dz += 0.035 * (1 - smoothstep(0.75, 0.98, ax / mW))
		end
		-- the upper lip lifts a little
		if dyl > 0.002 and dyl < 0.07 and ax < mW * 1.2 then
			dy += 0.004 * bump(((ax / mW) / 1.2) ^ 2 + ((dyl - 0.02) / 0.05) ^ 2)
		end
		if dx == 0 and dy == 0 and dz == 0 then
			return nil
		end
		return dx, dy, dz
	end
	-- the nasolabial line (beside the wing down to past the mouth corner): distance from it, and how far along
	local nlx0, nly0 = F.noseW + 0.012, F.noseBaseY + 0.022
	local nlx1, nly1 = mW + 0.028, F.mouthY - 0.028
	local function nasolabial(ax, y)
		local vx, vy = nlx1 - nlx0, nly1 - nly0
		local l2 = vx * vx + vy * vy
		local u = clamp(((ax - nlx0) * vx + (y - nly0) * vy) / l2, 0, 1)
		local dx, dy = ax - nlx0 - vx * u, y - nly0 - vy * u
		return sqrt(dx * dx + dy * dy), u, (dx * vy - dy * vx) < 0
	end
	fns.smile = function(x, y, z, side)
		local ax = abs(x)
		local c = cornerW(ax, y, x)
		local k = bump(((ax - 0.21) / 0.1) ^ 2 + ((y - (eyeY - 0.115)) / 0.09) ^ 2)
		local i = bump(((ax - F.eyeX) / 0.07) ^ 2 + ((y - (eyeY - 0.058)) / 0.022) ^ 2)
		-- the fold deepens (a dent along the line), the cheek bulges over it
		local nd, nu, outer = nasolabial(ax, y)
		local fold = nd < 0.03 and bump((nd / 0.012) ^ 2) * smoothstep(0, 0.2, nu) * (1 - smoothstep(0.8, 1, nu)) or 0
		local over = (nd < 0.05 and outer) and bump(((nd - 0.02) / 0.022) ^ 2) * smoothstep(0, 0.2, nu) or 0
		if c + k + i + fold + over <= 0 then
			return nil
		end
		return side * (0.03 * c + 0.004 * over), 0.045 * c + 0.03 * k + 0.006 * i + 0.004 * over, 0.01 * c - 0.012 * k - 0.003 * i + 0.005 * fold - 0.004 * over
	end
	fns.press = function(x, y, z, side)
		local w, dy = lipMask(x, y)
		local c = cornerW(abs(x), y, x)
		if w <= 0 and c <= 0 then
			return nil
		end
		if dy and dy >= 0 then
			return -side * 0.004 * c, -0.004 * w, 0.004 * w
		end
		return -side * 0.004 * c, 0.005 * w, 0.004 * w
	end
	fns.snarl = function(x, y, z, side)
		local ax = abs(x)
		local ml = F.mouthLine(clamp(x, -mW, mW))
		local u = bump(((ax - 0.045) / 0.06) ^ 2 + ((y - (ml + 0.022)) / 0.03) ^ 2)
		local a = bump(((ax - alaX) / 0.045) ^ 2 + ((y - (nb + 0.02)) / 0.035) ^ 2)
		local k = bump(((ax - (F.noseW + 0.05)) / 0.06) ^ 2 + ((y - (nb + 0.01)) / 0.05) ^ 2)
		if u + a + k <= 0 then
			return nil
		end
		return side * 0.004 * a, 0.016 * u + 0.008 * a + 0.009 * k, -0.003 * u - 0.004 * k
	end
	fns.wide = function(x, y, z, side)
		local c = cornerW(abs(x), y, x)
		local w, dy = lipMask(x, y)
		if c <= 0 and w <= 0 then
			return nil
		end
		local thin = (dy and dy >= 0) and -0.002 or 0.002
		return side * 0.02 * c, -0.003 * c + thin * w, 0.004 * c
	end
	fns.asym = function(x, y, z, side)
		if x <= 0 then
			return nil
		end
		local c = cornerW(x, y, x)
		local k = bump(((x - 0.23) / 0.1) ^ 2 + ((y - (eyeY - 0.12)) / 0.09) ^ 2)
		if c + k <= 0 then
			return nil
		end
		return 0.016 * c, 0.022 * c + 0.011 * k, 0.01 * c - 0.006 * k
	end
	fns.browUp = function(x, y, z)
		local ax = abs(x)
		local b = bump(((ax - 0.15) / 0.22) ^ 2 + ((y - (browY + 0.02)) / 0.075) ^ 2)
		local l = 0
		for s = -1, 1, 2 do
			l += bump(((x - E[s].x) / 0.08) ^ 2 + ((y - (E[s].y + 0.062)) / 0.028) ^ 2)
		end
		if b + l <= 0 then
			return nil
		end
		return 0, 0.026 * b + 0.008 * l, -0.002 * b
	end
	fns.browIn = function(x, y, z)
		local ax = abs(x)
		local b = bump(((ax - 0.07) / 0.085) ^ 2 + ((y - browY) / 0.055) ^ 2)
		if b <= 0 then
			return nil
		end
		return 0, 0.032 * b, -0.002 * b
	end
	fns.knit = function(x, y, z, side)
		local ax = abs(x)
		local b = bump(((ax - 0.08) / 0.09) ^ 2 + ((y - browY) / 0.05) ^ 2)
		local g = bump((x / 0.03) ^ 2 + ((y - (browY - 0.012)) / 0.035) ^ 2)
		if b + g <= 0 then
			return nil
		end
		return -side * 0.02 * b, -0.012 * b - 0.004 * g, -0.003 * b - 0.008 * g
	end
	fns.lid = function(x, y, z)
		local l = 0
		for s = -1, 1, 2 do
			l += bump(((x - E[s].x) / 0.068) ^ 2 + ((y - (E[s].y + 0.048)) / 0.024) ^ 2)
		end
		if l <= 0 then
			return nil
		end
		return 0, -0.005 * l, 0
	end
	fns.squint = function(x, y, z)
		local u, cf, cfx = 0, 0, 0
		for s = -1, 1, 2 do
			u += bump(((x - E[s].x) / 0.07) ^ 2 + ((y - (E[s].y - 0.062)) / 0.025) ^ 2)
			local c = bump(((s * (x - E[s].x) - 0.088) / 0.03) ^ 2 + ((y - E[s].y) / 0.035) ^ 2)
			cf += c
			cfx += -s * 0.003 * c
		end
		if u + cf <= 0 then
			return nil
		end
		return cfx, 0.006 * u, -0.002 * u - 0.001 * cf
	end
	fns.breathe = function(x, y, z, side)
		local a = bump(((abs(x) - alaX) / 0.045) ^ 2 + ((y - (nb + 0.02)) / 0.035) ^ 2)
		if a <= 0 then
			return nil
		end
		return side * 0.005 * a, 0.001 * a, 0
	end
	fns.puff = function(x, y, z, side)
		local p = bump(((abs(x) - 0.2) / 0.11) ^ 2 + ((y - (F.mouthY + 0.02)) / 0.08) ^ 2)
		if p <= 0 then
			return nil
		end
		return side * 0.012 * p, 0, -0.008 * p
	end
	-- fight swelling (FaceFX drives these from the damage state)
	for s = -1, 1, 2 do
		local tag = s < 0 and "L" or "R"
		local e = E[s]
		fns["swellEye" .. tag] = function(x, y, z)
			local q = ((x - e.x) / 0.11) ^ 2 + ((y - (e.y + 0.008)) / 0.095) ^ 2
			if q >= 1 then
				return nil
			end
			-- puffs the lid folds, brow and cheek round the orbit; fades in gently away from the rim (a steep
			-- ramp would show as a band: blend shapes keep the generated normals)
			local d3 = sqrt((x - e.x) ^ 2 + (y - e.y) ^ 2 + (z - e.z) ^ 2)
			local w = bump(q) * smoothstep(F.eyeR + 0.006, F.eyeR + 0.03, d3)
			if y > e.y then
				-- the brow-lid fold sags over the lid
				return s * 0.003 * w, -0.015 * w * smoothstep(e.y, e.y + 0.03, y) + 0.002 * w, -0.015 * w
			end
			-- the lower lid's bag rises
			return s * 0.003 * w, 0.01 * w * smoothstep(e.y - 0.07, e.y - 0.02, y), -0.012 * w
		end
		fns["swellCheek" .. tag] = function(x, y, z)
			local q = ((x - s * 0.25) / 0.1) ^ 2 + ((y - (eyeY - 0.085)) / 0.08) ^ 2
			if q >= 1 then
				return nil
			end
			local w = bump(q)
			return s * 0.008 * w, 0, -0.016 * w
		end
		fns["swellBrow" .. tag] = function(x, y, z)
			local q = ((x - s * 0.12) / 0.07) ^ 2 + ((y - (browY + 0.09)) / 0.06) ^ 2
			if q >= 1 then
				return nil
			end
			return 0, 0, -0.018 * bump(q)
		end
	end
	fns.swellLip = function(x, y, z)
		local q = ((x - 0.04) / 0.06) ^ 2 + ((y - (F.mouthY - 0.02)) / 0.026) ^ 2
		if q >= 1 then
			return nil
		end
		local w = bump(q)
		return 0, -0.004 * w, -0.01 * w
	end
	fns.swellNose = function(x, y, z)
		local q = (x / 0.08) ^ 2 + ((y - (nas + nb) * 0.5) / 0.13) ^ 2
		if q >= 1 then
			return nil
		end
		local w = bump(q)
		return x * 0.15 * w, 0, -0.004 * w
	end
	return fns
end
Rig.FaceMorphFns = faceMorphFns

-- the box rule (ANATOMY_CONTRACTS section 11): no delta may leave the piece's box or move a vertex lying on a
-- face of the box along that axis (AnatomyClient would clamp / pin it). Applied to every morph of m.
function Rig.BoxSafe(m)
	if not m.morphs then
		return
	end
	local x0, y0, z0, x1, y1, z1 = MeshKit.Bounds(m)
	local lo, hi = { x0, y0, z0 }, { x1, y1, z1 }
	local ex = 1e-5 + 1e-6 * max(x1 - x0, y1 - y0, z1 - z0)
	local P = m.P
	for _, mo in pairs(m.morphs) do
		local d = mo.d
		for k, i in ipairs(mo.ids) do
			for a = 1, 3 do
				local p = P[i * 3 - 3 + a]
				local dd = d[k * 3 - 3 + a]
				if dd ~= 0 then
					if p <= lo[a] + ex or p >= hi[a] - ex then
						dd = 0
					else
						dd = clamp(p + dd, lo[a] + ex, hi[a] - ex) - p
					end
					d[k * 3 - 3 + a] = dd
				end
			end
		end
	end
end

-- add every face morph to the head grid vertices first..last (plus the ear swellings on the ear ranges)
-- the height band each morph can touch (a cheap test before its function)
local function morphBands(F)
	local eY, bY, mY, nb, cY = F.eyeY, F.browY, F.mouthY, F.noseBaseY, F.chinY
	return {
		open = { cY - 0.2, mY + 0.08 }, smile = { mY - 0.07, eY - 0.02 }, press = { mY - 0.07, mY + 0.06 },
		snarl = { mY - 0.02, nb + 0.06 }, wide = { mY - 0.07, mY + 0.06 }, asym = { mY - 0.07, eY - 0.02 },
		browUp = { eY + 0.02, bY + 0.1 }, browIn = { bY - 0.05, bY + 0.05 }, knit = { bY - 0.05, bY + 0.05 },
		lid = { eY + 0.02, eY + 0.08 }, squint = { eY - 0.09, eY + 0.04 }, breathe = { nb - 0.02, nb + 0.06 },
		puff = { mY - 0.06, mY + 0.1 }, swellEyeL = { eY - 0.08, eY + 0.1 }, swellEyeR = { eY - 0.08, eY + 0.1 },
		swellCheekL = { eY - 0.17, eY }, swellCheekR = { eY - 0.17, eY }, swellBrowL = { bY + 0.03, bY + 0.15 },
		swellBrowR = { bY + 0.03, bY + 0.15 }, swellLip = { mY - 0.05, mY + 0.01 }, swellNose = { nb - 0.01, F.nasionY + 0.02 },
	}
end

function Rig.AddFaceMorphs(m, F, first, last, ears)
	local fns = faceMorphFns(F)
	local bands = morphBands(F)
	local list = {}
	for name, fn in pairs(fns) do
		local b = bands[name] or { -9, 9 }
		list[#list + 1] = { name = name, fn = fn, lo = b[1], hi = b[2] }
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	local P = m.P
	local eR = F.eyeR
	for i = first, last do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		if z < 0.13 and y < F.browY + 0.25 and y > F.chinY - 0.2 then
			local side = x < 0 and -1 or 1
			-- the socket skin behind the eyeball (and the rim on it) stays put: moved, it would come out through
			-- the eyeball or pull off the lids
			local e = F.eye[side]
			local d3 = sqrt((x - e.x) ^ 2 + (y - e.y) ^ 2 + (z - e.z) ^ 2)
			local keep = smoothstep(eR + 0.004, eR + 0.018, d3)
			if keep > 0 then
				for _, mo in ipairs(list) do
					if y >= mo.lo and y <= mo.hi then
						local dx, dy, dz = mo.fn(x, y, z, side)
						if dx then
							dx, dy, dz = dx * keep, dy * keep, dz * keep
							if abs(dx) + abs(dy) + abs(dz) > 2e-4 then
								MeshKit.AddMorph(m, mo.name, i, dx, dy, dz)
							end
						end
					end
				end
			end
			-- every morph's function at this vertex
			MeshKit.Step(#list)
		end
	end
	-- swollen ears: the ear inflates about its centre (a hematoma)
	for _, ear in ipairs(ears or {}) do
		local name = ear.side < 0 and "swellEarL" or "swellEarR"
		local c = ear.centre
		for i = ear.first, ear.last do
			local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
			MeshKit.AddMorph(m, name, i, (x - c[1]) * 0.14, (y - c[2]) * 0.1, (z - c[3]) * 0.14)
		end
		MeshKit.Step((ear.last - ear.first) // 4)
	end
end

------------------------------------------------------------------------
-- Mouth interior
------------------------------------------------------------------------
-- surf(x, y) -> the face surface point (x, y, z) (AnatomyHead's rays + relief)
local function archPoint(t, A, Az, z0)
	local ph = t * rad(78)
	return A * sin(ph), z0 + Az * (1 - cos(ph))
end

-- a row of teeth as one strip: front face from the gum to the biting edge, then the back face; tooth
-- gaps darker. upper: true for the upper arch
local function teethStrip(m, F, upper, zInc, cols)
	local mY = F.mouthY
	local age = F.age
	local yel = clamp((age - 25) / 40, 0, 0.5)
	local tr, tg, tb = lerp(0.8, 0.74, yel), lerp(0.77, 0.69, yel), lerp(0.68, 0.54, yel)
	local gr, gg, gb = 0.72, 0.38, 0.38
	local A = upper and 0.074 or 0.068
	local z0 = upper and zInc or zInc + 0.006
	local edgeY = function(t)
		local e = abs(t) ^ 1.5
		if upper then
			return mY + 0.004 + 0.009 * e
		end
		return mY - 0.006 - 0.006 * e
	end
	local gumY = function(t)
		return upper and (mY + 0.034 - 0.004 * abs(t)) or (mY - 0.032 + 0.004 * abs(t))
	end
	local thick = 0.012
	-- tooth boundaries in t (central incisor, lateral, canine, premolars, molar)
	local B = { 0.1, 0.21, 0.33, 0.47, 0.6, 0.76 }
	local ts = {}
	for i = 0, cols do
		ts[#ts + 1] = -1 + 2 * i / cols
	end
	local function gapK(t)
		local at = abs(t)
		local best = 1
		for _, b in ipairs(B) do
			best = min(best, abs(at - b))
		end
		return smoothstep(0.0, 0.035, best)
	end
	local first = m.nv + 1
	local nP = 4
	for _, t in ipairs(ts) do
		local x, z = archPoint(t, A, 0.07, z0)
		-- the inward direction of the arch at t (toward the tongue)
		local ph = t * rad(78)
		local ix, iz = -sin(ph), cos(ph)
		local gy, ey = gumY(t), edgeY(t)
		local gk = 0.55 + 0.45 * gapK(t)
		local shade = 1 - 0.25 * abs(t) -- the back teeth sit in shadow
		-- profile: gum (front), tooth front near the gum, biting edge, back face up to the gum
		local prof = {
			{ x, gy, z, gr * shade, gg * shade, gb * shade },
			{ x, lerp(gy, ey, 0.25), z - 0.001, tr * gk * shade, tg * gk * shade, tb * gk * shade },
			{ x + ix * 0.003, ey, z + iz * 0.003, tr * gk * 0.95 * shade, tg * gk * 0.95 * shade, tb * gk * shade },
			{ x + ix * thick, gy, z + iz * thick, tr * 0.6 * shade, tg * 0.58 * shade, tb * 0.55 * shade },
		}
		for k, p in ipairs(prof) do
			local vi = MeshKit.Vertex(m, p[1], p[2], p[3], 0.5, 0.5, p[4], p[5], p[6])
			if k > 1 then
				MeshKit.AddToGroup(m, "Teeth", vi)
			end
		end
	end
	for c = 0, #ts - 2 do
		local a, b = first + c * nP, first + (c + 1) * nP
		for k = 0, nP - 2 do
			if upper then
				MeshKit.Quad(m, a + k, a + k + 1, b + k + 1, b + k)
			else
				MeshKit.Quad(m, a + k, b + k, b + k + 1, a + k + 1)
			end
		end
	end
	return first
end

-- a dark shell facing the mouth opening (palate + throat above, floor below)
local function cavityShell(m, F, upper, zInc)
	local mY = F.mouthY
	local first = m.nv + 1
	local cols, rows = 6, 3
	local dr, dg, db = 0.1, 0.035, 0.035
	for c = 0, cols do
		local t = -1 + 2 * c / cols
		for r = 0, rows do
			local s = r / rows
			-- from just behind the teeth back and down to the throat (upper) / forward along the floor (lower)
			local x = t * lerp(0.07, 0.05, s)
			local y, z
			if upper then
				y = mY + lerp(0.03, -0.04, s * s) - 0.01 * t * t
				z = zInc + lerp(0.015, 0.11, s)
			else
				y = mY + lerp(-0.035, -0.05, s) + 0.01 * t * t
				z = zInc + lerp(0.015, 0.11, s)
			end
			local k = 1 - 0.5 * s
			MeshKit.Vertex(m, x, y, z, 0.5, 0.5, dr * k, dg * k, db * k)
		end
	end
	for c = 0, cols - 1 do
		local a, b = first + c * (rows + 1), first + (c + 1) * (rows + 1)
		for r = 0, rows - 1 do
			if upper then
				MeshKit.Quad(m, a + r, b + r, b + r + 1, a + r + 1)
			else
				MeshKit.Quad(m, a + r, a + r + 1, b + r + 1, b + r)
			end
		end
	end
	return first
end

local function tongue(m, F, zInc)
	local mY = F.mouthY
	local first = m.nv + 1
	local cols, rows = 6, 3
	for c = 0, cols do
		local t = -1 + 2 * c / cols
		for r = 0, rows do
			local s = r / rows
			local w = 0.052 * (1 - 0.25 * s) * sqrt(max(0, 1 - (t * 0.92) ^ 2))
			local x = t * 0.052 * (1 - 0.2 * s)
			local hump = 0.012 * sqrt(max(0, 1 - t * t)) * (0.6 + 0.4 * sin(s * math.pi))
			local y = mY - 0.03 + hump - 0.012 * s
			local z = zInc + 0.012 + 0.085 * s
			local k = 0.85 - 0.45 * s
			MeshKit.Vertex(m, x, y, z, 0.5, 0.5, 0.74 * k, 0.38 * k, 0.38 * k)
			local _ = w
		end
	end
	for c = 0, cols - 1 do
		local a, b = first + c * (rows + 1), first + (c + 1) * (rows + 1)
		for r = 0, rows - 1 do
			MeshKit.Quad(m, a + r, a + r + 1, b + r + 1, b + r)
		end
	end
	return first
end

-- MouthUpper (fixed) and MouthLower (swings about JawPivot); surf(x, y) gives the lip surface
function Rig.MouthMeshes(F, surf)
	local mY = F.mouthY
	local _, _, zu = surf(0, mY + 0.014)
	local _, _, zl = surf(0, mY - 0.016)
	local zInc = min(zu, zl) + 0.03 -- the incisors' front, behind the lips
	local up = MeshKit.New("MouthUpper")
	teethStrip(up, F, true, zInc, 14)
	cavityShell(up, F, true, zInc)
	local lo = MeshKit.New("MouthLower")
	teethStrip(lo, F, false, zInc, 14)
	tongue(lo, F, zInc)
	cavityShell(lo, F, false, zInc)
	return up, lo, zInc
end

------------------------------------------------------------------------
-- Beards: shells grown from the head grid
------------------------------------------------------------------------
-- style -> { thickness at growth 0 / 1, chin drop (full beards hang below the jaw) at growth 1 } and a mask
local BEARDS = {
	-- every style is painted into the head's texture (strands thinning into the skin); shell = true would also
	-- grow a shell over the style's dense core at full (none does: painted beards read better at every range)
	Moustache = { t0 = 0.005, t1 = 0.012 },
	Goatee = { t0 = 0.007, t1 = 0.018 },
	["Van Dyke"] = { t0 = 0.007, t1 = 0.02, drop = 0.026 },
	["Circle Beard"] = { t0 = 0.006, t1 = 0.016 },
	["Chin Strap"] = { t0 = 0.004, t1 = 0.009 },
	["Mutton Chops"] = { t0 = 0.006, t1 = 0.016 },
	["Short Boxed"] = { t0 = 0.006, t1 = 0.014, drop = 0.01 },
	["Full Beard"] = { t0 = 0.012, t1 = 0.032, drop = 0.055 },
}
Rig.BEARDS = BEARDS

-- 0..1 coverage of a beard style at a point (nominal)
local beardMaskBase
function Rig.BeardMask(F, style)
	local base = beardMaskBase(F, style)
	local seed = (F.seed or 0) + 11
	local noise = MeshKit.Noise
	-- a ragged edge: the transition band (not the full middle, not the bare skin) breaks up in patches
	return function(x, y, z)
		local w = base(x, y, z)
		if w <= 0 or w >= 1 then
			return w
		end
		local e = 4 * w * (1 - w)
		local n = noise(x * 48, y * 48, z * 48, seed) * 0.7 + noise(x * 130, y * 130, z * 130, seed + 5) * 0.3
		return clamp(w + 0.24 * n * e, 0, 1)
	end
end
function beardMaskBase(F, style)
	local zone = Paint.BeardZone(F)
	local mW = F.mouthW
	local nb = F.noseBaseY
	local cy = F.chinY
	local function moustache(x, y)
		local ax = abs(x)
		local ml = F.mouthLine(clamp(x, -mW, mW))
		local hu = F.lipH(clamp(x, -mW, mW))
		-- from the nostril sill, down along the cheeks' fold toward the corners
		local top = nb - 0.004 - max(0, ax - 0.05) * 0.6
		-- just above the vermilion border (never over the lip's middle)
		local bot = ml + hu + 0.002
		local w = smoothstep(bot - 0.003, bot + 0.004, y) * (1 - smoothstep(top - 0.006, top + 0.002, y))
		w *= 1 - smoothstep(mW + 0.002, mW + 0.022, ax)
		-- the ends turn down beside the corners
		local ends = bump(((ax - mW - 0.006) / 0.016) ^ 2 + ((y - (ml + 0.004)) / 0.02) ^ 2)
		return max(w, ends)
	end
	-- the chin's beard: a wedge from just under the lower lip's border down to the chin's point (wide under
	-- the lip, narrowing down; low = longer, pointed), a little under the chin; feathered edges
	local _, hl0 = F.lipH(0)
	local function chin(x, y, z, wide, low)
		local top = F.mouthY - hl0 - 0.007
		local bot = cy - 0.012 - (low and 0.03 or 0)
		local t = clamp((top - y) / (top - bot), 0, 1)
		local half = lerp(mW * 0.72 * wide, (low and 0.03 or 0.05) * wide, t ^ 0.85)
		local ax = abs(x)
		local w = (1 - smoothstep(half * 0.75, half * 1.12, ax)) * smoothstep(bot - 0.02, bot + 0.012, y)
		-- under the chin
		if y < cy + 0.02 and z < -0.12 then
			local u = bump((x / (0.07 * wide)) ^ 2 + ((z + 0.36) / 0.1) ^ 2) * (low and 0.9 or 0.6)
			w = max(w, u * smoothstep(cy - 0.08, cy - 0.02, y))
		end
		-- never above the lower lip's border
		local ml = F.mouthLine(clamp(x, -mW, mW))
		local _, hl = F.lipH(clamp(x, -mW, mW))
		w *= smoothstep(ml - hl - 0.002, ml - hl - 0.01, y)
		return w
	end
	local function jawBand(x, y, z)
		-- along the jaw's lower edge from the sideburn to the chin
		local ax = abs(x)
		local yl = lerp(cy - 0.01, F.gonionY - 0.02, smoothstep(0.05, F.jawW, ax))
		-- a band of beard (~2 cm) along the jaw, thinning at both edges: no drawn line along its middle
		return (1 - smoothstep(0.018, 0.05, abs(y - yl))) * (1 - smoothstep(0.02, 0.08, z))
	end
	if style == "Moustache" then
		return function(x, y, z)
			return moustache(x, y) * zone(x, y, z) ^ 0.25
		end
	elseif style == "Goatee" then
		return function(x, y, z)
			return max(moustache(x, y), chin(x, y, z, 1.0, false)) * min(1, zone(x, y, z) * 3)
		end
	elseif style == "Van Dyke" then
		return function(x, y, z)
			local soul = bump((x / 0.018) ^ 2 + ((y - (F.mouthY - 0.065)) / 0.018) ^ 2)
			return max(moustache(x, y), chin(x, y, z, 0.75, true), soul) * min(1, zone(x, y, z) * 3)
		end
	elseif style == "Circle Beard" then
		return function(x, y, z)
			local ax = abs(x)
			local ring = bump(((ax - mW - 0.008) / 0.03) ^ 2) * smoothstep(cy - 0.01, cy + 0.04, y) * (1 - smoothstep(F.mouthY + 0.0, F.mouthY + 0.03, y))
			return max(moustache(x, y), chin(x, y, z, 1.05, false), ring) * min(1, zone(x, y, z) * 3)
		end
	elseif style == "Chin Strap" then
		return function(x, y, z)
			return jawBand(x, y, z) * min(1, zone(x, y, z) * 2)
		end
	elseif style == "Mutton Chops" then
		return function(x, y, z)
			local ax = abs(x)
			-- the chops' front edge curves forward as it comes down the cheek to the jaw corner
			local x0 = lerp(0.215, 0.15, smoothstep(F.noseBaseY, F.gonionY, y))
			local chop = smoothstep(x0 - 0.02, x0 + 0.015, ax) * smoothstep(F.gonionY - 0.07, F.gonionY - 0.02, y)
			return max(moustache(x, y), chop) * zone(x, y, z)
		end
	end
	-- Short Boxed / Full Beard: the whole zone
	return function(x, y, z)
		return zone(x, y, z)
	end
end

-- the beard piece: grid vertices under the style mask pushed out along their normals (the edge sinks into
-- the skin), the grid's triangles where all three vertices are covered, an `open` morph that follows the jaw.
-- Returns nil for no beard / stubble (stubble is paint).
function Rig.BeardMesh(head, F, look, gridN, lod)
	local style, _, growth = Paint.BeardStyle(look)
	local spec = style and BEARDS[style]
	if not spec then
		return nil
	end
	local mask = Rig.BeardMask(F, style)
	local P, N, T = head.P, head.N, head.T
	local T0 = lerp(spec.t0, spec.t1, growth)
	local drop = (spec.drop or 0) * (0.3 + 0.7 * growth)
	local br, bg, bb = Paint.HairColor(look, F.age, true)
	local m = MeshKit.New("Beard")
	local map = {}
	local W = {}
	local Q = {}
	local sink = 0.003
	local seed = F.seed
	for i = 1, gridN do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		-- (not into the nose's base: the shell over the subnasale's fold would cut through the nostrils)
		if z < 0.2 and y < F.noseBaseY - 0.006 and y > F.chinY - 0.25 then
			-- the dense core only: the thinning edge is painted on the skin (the shell's edge sinks under it)
			local w = smoothstep(0.6, 0.95, mask(x, y, z))
			if w > 0.002 then
				W[i] = w
			end
		end
	end
	-- keep a vertex if it or a triangle neighbour is covered (the shell's edge ring sinks under the skin)
	local keep = {}
	for t = 1, head.nt do
		local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		if a <= gridN and b <= gridN and c <= gridN and (W[a] or W[b] or W[c]) then
			keep[a], keep[b], keep[c] = true, true, true
		end
	end
	local noise = MeshKit.Noise
	for i = 1, gridN do
		if keep[i] then
			local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
			local w = W[i] or 0
			-- the shell thins to nothing at the edge (it leaves the skin at a shallow angle: no cut edge) and
			-- swells into a volume of clumps inside (two noise scales: the mass and the tufts)
			local shape = smoothstep(0.08, 0.95, w)
			shape = shape * shape * (3 - 2 * shape) * shape
			-- the mass in soft lumps (~0.02-0.04 across), a finer tuft breakup on top
			local clump = 1 + 0.3 * noise(x * 30, y * 30, z * 30, seed) + 0.12 * noise(x * 90, y * 90, z * 90, seed + 3)
			local off = T0 * shape * clump - sink * (1 - shape) * 0.4
			local nx, ny, nz = N[i * 3 - 2], N[i * 3 - 1], N[i * 3]
			local hang = 0
			if drop > 0 and y < F.chinY + 0.04 then
				-- a full beard hangs: below the chin the shell grows downward
				hang = drop * shape * smoothstep(F.chinY + 0.04, F.chinY - 0.06, y) * (1 - smoothstep(0.15, 0.3, abs(x)))
			end
			local px, py, pz = x + nx * off, y + ny * off - hang, z + nz * off
			local k = 0.82 + 0.3 * noise(x * 140, y * 140, z * 140, seed + 5)
			local u, v = head.U[i * 2 - 1], head.U[i * 2]
			-- the edge (thin cover) keeps the skin's colour; the body is the beard's
			local cov = smoothstep(0.08, 0.6, w)
			local C = head.C
			local cr = lerp(C[i * 3 - 2], br * k, cov)
			local cg = lerp(C[i * 3 - 1], bg * k, cov)
			local cb = lerp(C[i * 3], bb * k, cov)
			map[i] = MeshKit.Vertex(m, px, py, pz, u, v, clamp(cr, 0, 1), clamp(cg, 0, 1), clamp(cb, 0, 1))
			Q[map[i]] = w
		end
	end
	for t = 1, head.nt do
		local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		local ma, mb, mc = map[a], map[b], map[c]
		if ma and mb and mc and (W[a] or W[b] or W[c]) then
			MeshKit.Tri(m, ma, mb, mc)
		end
	end
	if m.nt == 0 then
		return nil
	end
	MeshKit.Step(gridN)
	MeshKit.ComputeNormals(m)
	-- the beard follows the jaw
	if lod == "full" then
		local Pm = m.P
		for i = 1, m.nv do
			local x, y, z = Pm[i * 3 - 2], Pm[i * 3 - 1], Pm[i * 3]
			local j = jawMask(F, x, y, z)
			if j > 0.001 then
				local dx, dy, dz = jawDelta(F, x, y, z, 1)
				MeshKit.AddMorph(m, "open", i, dx * j, dy * j, dz * j)
			end
		end
		Rig.BoxSafe(m)
	end
	return m, style, Q
end

------------------------------------------------------------------------
-- Landmarks (nominal; AnatomyHead scales them to the Head part)
------------------------------------------------------------------------
-- surf(x, y) -> x, y, z on the face; ears = { [side] = { x, y, z } }; top / back = head top and occiput points
function Rig.Landmarks(F, surf, ears, top, back, hairlineY)
	local L = {}
	local function put(name, x, y, z)
		L[name] = { x, y, z }
	end
	for s = -1, 1, 2 do
		local tag = s < 0 and "L" or "R"
		local e = F.eye[s]
		put("Eye" .. tag, e.x, e.y, e.z)
		put("LidPivot" .. tag, e.x, e.y, e.z)
		-- a second point on the upper lid's hinge axis (the eye's lateral axis, tilted by the canthal tilt):
		-- FaceFX turns the lid about LidPivot -> LidAxis
		put("LidAxis" .. tag, e.x + s * cos(F.tilt) * F.eyeR, e.y + sin(F.tilt) * F.eyeR, e.z)
		local brow = Paint.BrowFrame(F)
		-- the brow's centre line at s = 0 / 0.5 / 1 (found by scanning its frame)
		for _, def in ipairs({ { "BrowInner", 0.02 }, { "BrowMid", 0.5 }, { "BrowOuter", 0.95 } }) do
			local fem = F.female and 0.07 or 0.064
			local ax = fem + def[2] * 0.212
			local x = s * ax
			local _, t = brow(x, F.browY)
			local y = F.browY - (t or 0)
			put(def[1] .. tag, surf(x, y))
		end
		put("Nostril" .. tag, surf(s * F.noseW * 0.4, F.noseBaseY + 0.004))
		local mx = s * F.mouthW
		put("Mouth" .. tag, surf(mx, F.mouthLine(mx)))
		if ears and ears[s] then
			put("Ear" .. tag, ears[s][1], ears[s][2], ears[s][3])
		end
	end
	L.EyeRadius = { F.eyeR, 0, 0 }
	put("Nasion", surf(0, F.nasionY))
	put("NoseTip", surf(F.noseDev, F.noseTipY))
	local hu, hl = F.lipH(0)
	put("LipUpper", surf(0, F.mouthY + hu * 0.5))
	put("LipLower", surf(0, F.mouthY - hl * 0.5))
	put("JawPivot", Rig.JawPivot(F))
	put("Chin", surf(0, F.chinY))
	if top then
		put("HeadTop", top[1], top[2], top[3])
	end
	if back then
		put("Occiput", back[1], back[2], back[3])
	end
	put("Forehead", surf(0, hairlineY or (F.browY + 0.22)))
	return L
end

return Rig
