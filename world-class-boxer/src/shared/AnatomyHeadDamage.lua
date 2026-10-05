-- AnatomyHeadDamage: what a fight leaves on the anatomy head (bruises, cuts, blood, swelling, grime).
-- Pure (no Instances, no services): FaceFX runs it on the client against the Head piece's generated mesh and
-- texture pixels; renders and tests call the same functions. Everything is in the Head part's space.
-- Marks are placed on the real surface (projected along -Z onto the mesh), so they follow the geometry:
--  * bruises: 3D ellipsoids, weighted by distance and by facing (a cheek bruise never runs up the side of the
--    nose), multiplied into the skin (the pores and the skin tone stay; fresh red-purple -> blue -> yellow-green)
--  * cuts: curved, tapered gashes along the brow ridge, the lateral brow and the cheekbone (an open red core with
--    a dark centre, a swollen halo; later a scab, then a pink line)
--  * blood: trickles that run down the surface from the cuts / nostrils / a split lip, meandering, round the eye
--  * grime: dull mottled smudges (the Grime attribute)
-- API
--  * Damage.Swell(dmg, tier) -> swell (Head morph weights), closing { [-1], [1] }, red { [-1], [1] } (sclera)
--  * Damage.Surface(mesh, step) -> surf(x, y) -> z, nx, ny, nz (front-most point of the mesh at x, y) | nil
--  * Damage.Marks(lms, eyeR, dmg, tier, grime, surf, step) -> marks, lid tints { [-1] = { r, g, b, a } | nil, [1] }
--  * Damage.PaintTexture(mesh, W, H, orig, marks, was, step) -> strips { { x0, y0, w, h, pixels } } | nil, painted
--      repaints the texels of the triangles under a mark now or in `was` (the previous result's `painted`), in
--      32-row strips spanning only their dirty columns, from `orig`: a healed mark goes back exactly. The caller
--      writes every strip at the end of the job (one consistent update).
--  * Damage.PaintVertices(mesh, marks, was, step, ids) -> ids, colours, touched (the same marks as vertex colours)
--  * Damage.Shade(marks, x, y, z, nx, ny, nz, ts, r, g, b) -> r, g, b (one point)
--  * Damage.Sclera(W, H, orig, k, step) -> pixels (the eyeball texture with a bloodshot white)
-- step(n): called every ~n units of work with the work done; FaceFX yields there (a per-frame time budget).
local Damage = {}

local sqrt, sin, cos, abs, min, max, floor, ceil = math.sqrt, math.sin, math.cos, math.abs, math.min, math.max, math.floor, math.ceil
local huge = math.huge
local readu8, writeu8 = buffer.readu8, buffer.writeu8

local function clamp(x, a, b)
	return x < a and a or (x > b and b or x)
end

local function n01(dmg, key)
	return clamp(tonumber(dmg[key]) or 0, 0, 1.5)
end

------------------------------------------------------------------------
-- Swelling (the Head's swell* morphs), lids closing, sclera redness: straight from the damage table
------------------------------------------------------------------------
function Damage.Swell(dmg, tier)
	dmg = type(dmg) == "table" and dmg or {}
	tier = tonumber(tier) or 0
	local swell = {}
	local closing, red = {}, {}
	for s = -1, 1, 2 do
		local tag = s < 0 and "L" or "R"
		local ev = n01(dmg, s < 0 and "leftEye" or "rightEye")
		local ck = n01(dmg, s < 0 and "cheekL" or "cheekR")
		local ear = n01(dmg, s < 0 and "earL" or "earR")
		swell["swellEye" .. tag] = clamp(ev * 0.9, 0, 1.2)
		swell["swellCheek" .. tag] = clamp(ck * 0.85, 0, 1.2)
		swell["swellEar" .. tag] = clamp(ear, 0, 1.2)
		closing[s] = clamp((ev - 0.3) / 0.7, 0, 1)
		red[s] = clamp(ev * 0.5 + (tier >= 4 and 0.35 or 0) + n01(dmg, "redness") * 0.15, 0, 0.8)
	end
	if dmg.nose == true then
		swell.swellNose = 0.6
	end
	local lump = n01(dmg, "forehead")
	if lump > 0.2 then
		swell[(tonumber(dmg.cutSide) or 1) < 0 and "swellBrowL" or "swellBrowR"] = clamp(lump, 0, 1.2)
	end
	local lip = n01(dmg, "lip")
	if lip > 0.25 then
		swell.swellLip = clamp((lip - 0.25) * 1.3, 0, 1.2)
	end
	for k, w in pairs(swell) do
		if w <= 0.005 then
			swell[k] = nil
		end
	end
	return swell, closing, red
end

-- does this state leave any mark (a clean face needs no paint job)?
function Damage.Any(dmg, tier, grime)
	if (tonumber(tier) or 0) >= 1 or (tonumber(grime) or 0) > 0.05 then
		return true
	end
	if type(dmg) == "table" then
		for k, v in pairs(dmg) do
			if k ~= "age" and k ~= "cutSide" and k ~= "cutSide2" and k ~= "ribsL" and k ~= "ribsR" and (v == true or (tonumber(v) or 0) > 0.05) then
				return true
			end
		end
	end
	return false
end

------------------------------------------------------------------------
-- The surface: front-most point of the mesh along -Z at (x, y) (an x / y bin index of its triangles)
------------------------------------------------------------------------
function Damage.Surface(mesh, step)
	local P, T, N = mesh.P, mesh.T, mesh.N
	local nt = mesh.nt
	local x0, x1, y0, y1 = huge, -huge, huge, -huge
	for i = 1, mesh.nv do
		local x, y = P[i * 3 - 2], P[i * 3 - 1]
		x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
	end
	if x1 < x0 then
		return function()
			return nil
		end
	end
	local cell = max(x1 - x0, y1 - y0) / 40
	local nx = floor((x1 - x0) / cell) + 1
	local bins = {}
	local zCut = 0.25 * (x1 - x0) -- the back of the head never is the front-most point of the face
	for t = 1, nt do
		local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		local za, zb, zc = P[a * 3], P[b * 3], P[c * 3]
		if min(za, zb, zc) < zCut then
			local xa, xb, xc = P[a * 3 - 2], P[b * 3 - 2], P[c * 3 - 2]
			local ya, yb, yc = P[a * 3 - 1], P[b * 3 - 1], P[c * 3 - 1]
			local cx0, cx1 = floor((min(xa, xb, xc) - x0) / cell), floor((max(xa, xb, xc) - x0) / cell)
			local cy0, cy1 = floor((min(ya, yb, yc) - y0) / cell), floor((max(ya, yb, yc) - y0) / cell)
			for cy = cy0, cy1 do
				for cx = cx0, cx1 do
					local key = cy * nx + cx
					local bin = bins[key]
					if not bin then
						bin = {}
						bins[key] = bin
					end
					bin[#bin + 1] = t
				end
			end
		end
		if step and t % 128 == 0 then
			step(128)
		end
	end
	return function(x, y)
		if x < x0 or x > x1 or y < y0 or y > y1 then
			return nil
		end
		local bin = bins[floor((y - y0) / cell) * nx + floor((x - x0) / cell)]
		if not bin then
			return nil
		end
		local best, bnx, bny, bnz = huge, 0, 0, -1
		for _, t in ipairs(bin) do
			local a, b, c = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
			local xa, ya, xb, yb, xc, yc = P[a * 3 - 2], P[a * 3 - 1], P[b * 3 - 2], P[b * 3 - 1], P[c * 3 - 2], P[c * 3 - 1]
			local den = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc)
			if den > 1e-12 or den < -1e-12 then
				local l1 = ((yb - yc) * (x - xc) + (xc - xb) * (y - yc)) / den
				local l2 = ((yc - ya) * (x - xc) + (xa - xc) * (y - yc)) / den
				local l3 = 1 - l1 - l2
				if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6 then
					local z = l1 * P[a * 3] + l2 * P[b * 3] + l3 * P[c * 3]
					if z < best then
						best = z
						if N then
							bnx = l1 * N[a * 3 - 2] + l2 * N[b * 3 - 2] + l3 * N[c * 3 - 2]
							bny = l1 * N[a * 3 - 1] + l2 * N[b * 3 - 1] + l3 * N[c * 3 - 1]
							bnz = l1 * N[a * 3] + l2 * N[b * 3] + l3 * N[c * 3]
						end
					end
				end
			end
		end
		if best == huge then
			return nil
		end
		local l = sqrt(bnx * bnx + bny * bny + bnz * bnz)
		if l < 1e-9 then
			return best, 0, 0, -1
		end
		return best, bnx / l, bny / l, bnz / l
	end
end

------------------------------------------------------------------------
-- Colours
------------------------------------------------------------------------
-- a bruise's multiply tint by its age in days (the deepest; lighter marks go part of the way): fresh red-purple,
-- blue-purple after a day or two, yellow-green from day four, gone after nine
local TINTS = {
	{ 0, 0.6, 0.38, 0.47 },
	{ 1.5, 0.52, 0.43, 0.62 },
	{ 4, 0.78, 0.72, 0.6 },
	{ 6.5, 0.95, 0.92, 0.72 },
	{ 9, 1, 1, 1 },
}
local function bruiseTint(age, depth)
	local r, g, b = 1, 1, 1
	if age <= 0 then
		r, g, b = TINTS[1][2], TINTS[1][3], TINTS[1][4]
	else
		for i = 1, #TINTS - 1 do
			local a, c = TINTS[i], TINTS[i + 1]
			if age <= c[1] then
				local t = (age - a[1]) / (c[1] - a[1])
				r, g, b = a[2] + (c[2] - a[2]) * t, a[3] + (c[3] - a[3]) * t, a[4] + (c[4] - a[4]) * t
				break
			end
		end
	end
	return 1 + (r - 1) * depth, 1 + (g - 1) * depth, 1 + (b - 1) * depth
end
Damage.BruiseTint = bruiseTint

local BLOOD = { 0.42, 0.02, 0.035 } -- fresh, wet
local BLOOD_DRY = { 0.3, 0.035, 0.03 }

------------------------------------------------------------------------
-- Marks
------------------------------------------------------------------------
-- blot (kind 1): an ellipsoid, rotated `rot` in x / y; mul = multiply tint (else mix toward the colour);
-- face = the surface normal at its centre (texels facing away fade), mot = mottling 0..1
local function addBlot(M, x, y, z, ax, ay, az, rot, r, g, b, a, mul, face, mot)
	if a <= 0.01 or not z then
		return
	end
	local ext = max(ax, ay)
	local m = {
		kind = 1, x = x, y = y, z = z, c = cos(rot), s = sin(rot), iax = 1 / ax, iay = 1 / ay, iaz = 1 / az,
		r = r, g = g, b = b, a = a, mul = mul, mot = mot or 0, mf = 1 / (ext * 0.55),
		x0 = x - ext, x1 = x + ext, y0 = y - ext, y1 = y + ext, z0 = z - az, z1 = z + az,
	}
	if face then
		m.fx, m.fy, m.fz = face[1], face[2], face[3]
	end
	M[#M + 1] = m
end

-- stroke (kind 2): a polyline of surface points with a radius at each (tapered), soft = 0 crisp (one texel of
-- anti-aliasing) .. 1 a soft falloff over the whole radius
local function addStroke(M, pts, r, g, b, a, mul, soft)
	local n = #pts
	if n < 2 or a <= 0.01 then
		return
	end
	local X, Y, Z, R = table.create(n), table.create(n), table.create(n), table.create(n)
	local x0, x1, y0, y1, z0, z1 = huge, -huge, huge, -huge, huge, -huge
	for i, p in ipairs(pts) do
		X[i], Y[i], Z[i], R[i] = p[1], p[2], p[3], p[4]
		x0, x1 = min(x0, p[1] - p[4]), max(x1, p[1] + p[4])
		y0, y1 = min(y0, p[2] - p[4]), max(y1, p[2] + p[4])
		z0, z1 = min(z0, p[3] - p[4]), max(z1, p[3] + p[4])
	end
	local IL = table.create(n - 1)
	-- each segment's box (radius + the anti-aliasing allowance): the painter tests only the segments near a triangle
	local pad = 0.02
	local SX0, SX1, SY0, SY1 = table.create(n - 1), table.create(n - 1), table.create(n - 1), table.create(n - 1)
	for i = 1, n - 1 do
		local dx, dy, dz = X[i + 1] - X[i], Y[i + 1] - Y[i], Z[i + 1] - Z[i]
		local l2 = dx * dx + dy * dy + dz * dz
		IL[i] = l2 > 1e-14 and 1 / l2 or 0
		local rr = max(R[i], R[i + 1]) + pad
		SX0[i], SX1[i] = min(X[i], X[i + 1]) - rr, max(X[i], X[i + 1]) + rr
		SY0[i], SY1[i] = min(Y[i], Y[i + 1]) - rr, max(Y[i], Y[i + 1]) + rr
	end
	M[#M + 1] = {
		kind = 2, n = n, X = X, Y = Y, Z = Z, R = R, IL = IL, SX0 = SX0, SX1 = SX1, SY0 = SY0, SY1 = SY1,
		r = r, g = g, b = b, a = a, mul = mul, soft = soft or 0,
		x0 = x0 - pad, x1 = x1 + pad, y0 = y0 - pad, y1 = y1 + pad, z0 = z0 - pad, z1 = z1 + pad,
	}
end

-- a small deterministic hash -> 0..1
local function h01(a, b)
	local v = sin(a * 127.1 + b * 311.7) * 43758.5453
	return v - floor(v)
end

-- the marks of a damage table. lms: AnatomyHead landmarks ({ pos = { x, y, z } }), eyeR: the eye radius (Head
-- part space), grime 0..1, surf: Damage.Surface's function (marks off the mesh are dropped)
function Damage.Marks(lms, eyeR, dmg, tier, grime, surf, step)
	dmg = type(dmg) == "table" and dmg or {}
	local function pause()
		if step then
			step(1)
		end
	end
	tier = tonumber(tier) or 0
	grime = clamp(tonumber(grime) or 0, 0, 1)
	local M = {}
	local lid = {}
	local function p(name)
		local l = lms[name]
		return l and type(l.pos) == "table" and l.pos or nil
	end
	local eL, eR = p("EyeL"), p("EyeR")
	if not (eL and eR and surf) then
		return M, lid
	end
	local k = (tonumber(eyeR) or 0.06) / 0.06
	local function n(key)
		return n01(dmg, key)
	end
	local age = max(0, tonumber(dmg.age) or 0)
	local fade = clamp(1 - age / 9, 0.12, 1)
	local fresh = age < 0.5
	local wet = age < 0.15
	-- a surface point (nil off the mesh)
	local function on(x, y)
		local z, nx, ny, nz = surf(x, y)
		if not z then
			return nil
		end
		return z, { nx, ny, nz }
	end
	local function bruise(x, y, ax, ay, az, rot, depth, a, mot, faced)
		local z, nrm = on(x, y)
		if z then
			local r, g, b = bruiseTint(age, depth)
			addBlot(M, x, y, z, ax, ay, az, rot, r, g, b, a, true, faced ~= false and nrm or nil, mot or 0.35)
		end
	end
	local function flush(x, y, ax, ay, az, a, r, g, b)
		local z, nrm = on(x, y)
		if z then
			addBlot(M, x, y, z, ax, ay, az, 0, r or 1, g or 0.8, b or 0.78, a, true, nrm, 0.25)
		end
	end
	local brMid = { [-1] = p("BrowMidL"), [1] = p("BrowMidR") }
	local brOut = { [-1] = p("BrowOuterL"), [1] = p("BrowOuterR") }
	local brIn = { [-1] = p("BrowInnerL"), [1] = p("BrowInnerR") }
	local eye = { [-1] = eL, [1] = eR }
	local eyeY = (eL[2] + eR[2]) * 0.5

	-- 1. punch redness (any fight damage) and general bruising on the cheekbones
	local redn = n("redness")
	local bru = n("bruise")
	if tier >= 1 or redn > 0.1 then
		local a = clamp(0.18 + 0.3 * max(redn, tier >= 2 and 0.5 or 0.3), 0, 0.5) * (fresh and 1 or 0.5)
		for s = -1, 1, 2 do
			local e = eye[s]
			flush(e[1] + s * 0.035 * k, e[2] - 0.09 * k, 0.085 * k, 0.065 * k, 0.09 * k, a)
		end
		flush(0, eyeY + 0.2 * k, 0.13 * k, 0.07 * k, 0.12 * k, a * 0.6)
	end
	if bru > 0.2 then
		for s = -1, 1, 2 do
			local e = eye[s]
			bruise(e[1] + s * 0.04 * k, e[2] - 0.095 * k, 0.08 * k, 0.06 * k, 0.08 * k, s * 0.3, 0.45, clamp(0.15 + 0.4 * bru, 0, 0.6) * fade)
		end
	end

	pause()
	-- 2. black eyes: deepest in the crescent under the eye, round the whole orbit, the lid crease, the outer corner
	for s = -1, 1, 2 do
		local e = eye[s]
		local ev = n(s < 0 and "leftEye" or "rightEye")
		if ev > 0.08 then
			local a0 = clamp(0.3 + 0.6 * ev, 0, 0.95) * fade
			local g = 1 + 0.2 * min(ev, 1)
			if fresh then
				-- the swelling's red halo round it
				flush(e[1] + s * 0.01 * k, e[2] - 0.02 * k, 0.12 * k * g, 0.1 * k * g, 0.13 * k, 0.45 * min(ev, 1), 1, 0.82, 0.82)
			end
			bruise(e[1], e[2] - 0.004 * k, 0.083 * k * g, 0.07 * k * g, 0.13 * k, 0, 0.7, a0 * 0.8, 0.3, false)
			bruise(e[1] + s * 0.008 * k, e[2] - 0.045 * k, 0.058 * k * g, 0.03 * k * g, 0.06 * k, s * 0.12, 1, a0, 0.3, false)
			bruise(e[1] - s * 0.008 * k, e[2] + 0.036 * k, 0.052 * k, 0.022 * k, 0.07 * k, 0, 0.85, a0 * 0.65, 0.25, false)
			bruise(e[1] + s * 0.062 * k, e[2], 0.03 * k, 0.048 * k, 0.07 * k, 0, 0.8, a0 * 0.6, 0.3, false)
			local tr, tg, tb = bruiseTint(age, 1)
			-- (the bruise blots shade the lids too: this only deepens the fold a little; no maroon shell)
			lid[s] = { tr, tg, tb, a0 * 0.35 }
		end
		local ck = n(s < 0 and "cheekL" or "cheekR")
		if ck > 0.1 then
			local a = clamp(0.25 + 0.5 * ck, 0, 0.8) * fade
			if fresh then
				flush(e[1] + s * 0.045 * k, e[2] - 0.1 * k, 0.1 * k, 0.08 * k, 0.1 * k, 0.35 * min(ck, 1), 1, 0.84, 0.84)
			end
			bruise(e[1] + s * 0.04 * k, e[2] - 0.098 * k, (0.06 + 0.025 * ck) * k, (0.045 + 0.018 * ck) * k, 0.07 * k, s * 0.35, 0.85, a)
		end
		local ear = n(s < 0 and "earL" or "earR")
		local ep = p(s < 0 and "EarL" or "EarR")
		if ear > 0.15 and ep then
			-- the ear's own surface (the projection along -Z would land on the cheek): a blot at the landmark
			local r, g, b = bruiseTint(age, 0.6)
			-- thin across the ear (its plane faces sideways): the pinna, not the head behind it
			addBlot(M, ep[1], ep[2], ep[3], 0.017 * k, 0.075 * k, 0.065 * k, 0, r, g * 0.95, b, clamp(0.25 + 0.45 * ear, 0, 0.7) * fade, true, nil, 0.4)
		end
	end

	pause()
	-- 3. a broken nose: the bridge and the inner corners of the eyes
	local tip, nas = p("NoseTip"), p("Nasion")
	if dmg.nose == true and tip and nas then
		bruise((tip[1] + nas[1]) * 0.5, nas[2] - (nas[2] - tip[2]) * 0.4, 0.03 * k, 0.065 * k, 0.08 * k, 0.1, 0.8, 0.5 * fade, 0.3, false)
		for s = -1, 1, 2 do
			bruise(s * 0.04 * k + nas[1], nas[2] - 0.035 * k, 0.025 * k, 0.03 * k, 0.05 * k, 0, 0.7, 0.4 * fade)
		end
	end

	-- 4. a lump on the forehead
	local cutSide = (tonumber(dmg.cutSide) or 1) < 0 and -1 or 1
	local lump = n("forehead")
	if lump > 0.2 then
		local bm = brMid[cutSide]
		local bx = bm and bm[1] * 0.75 or cutSide * 0.12 * k
		local by = bm and bm[2] + 0.1 * k or eyeY + 0.19 * k
		bruise(bx, by, (0.045 + 0.02 * lump) * k, (0.04 + 0.015 * lump) * k, 0.08 * k, 0, 0.6, 0.45 * fade)
	end

	-- 5. blood trickles: from (x, y) down the surface, round the eye opening, meandering
	local function trickle(x, y, len, w, seed, a, s, wob)
		local pts = {}
		local stepL = 0.009 * k
		local nSteps = max(2, floor(len / stepL + 0.5))
		local e = s and eye[s]
		local ph = h01(seed, 1.7) * 6.28
		wob = wob or 1
		for i = 0, nSteps do
			local z = surf(x, y)
			if not z then
				break
			end
			local t = i / nSteps
			-- thins as it runs, ends in a drop
			local rad = w * (1 - 0.35 * t)
			if i == nSteps then
				rad = w * 1.25
			end
			pts[#pts + 1] = { x, y, z, rad }
			y -= stepL
			x += stepL * wob * (0.32 * sin(i * 0.9 + ph) + 0.4 * (h01(seed, i) - 0.5))
			-- never across the eye opening: down its outer side
			if e then
				local dx, dy = x - e[1], y - e[2]
				local rx, ry = eyeR * 1.45, eyeR * 1.15
				local q = (dx / rx) ^ 2 + (dy / ry) ^ 2
				if q < 1 then
					local side = (dx * s >= -0.3 * rx) and s or -s
					x = e[1] + side * rx * sqrt(max(0, 1 - (dy / ry) ^ 2))
				end
			end
		end
		if #pts >= 2 then
			local col = wet and BLOOD or BLOOD_DRY
			addStroke(M, pts, col[1], col[2], col[3], a, false, 0)
		end
	end

	pause()
	-- 6. cuts: curved tapered gashes (quadratic curve from p0 over c to p2, lifted onto the surface)
	local function gash(p0x, p0y, cx, cy, p2x, p2y, w, sev, seed, s, bleed)
		local N = 9
		local core, halo, inner = {}, {}, {}
		local lowX, lowY, lowT = nil, huge, 0
		for i = 0, N do
			local t = i / N
			local u = 1 - t
			local x = u * u * p0x + 2 * u * t * cx + t * t * p2x
			local y = u * u * p0y + 2 * u * t * cy + t * t * p2y
			local z = surf(x, y)
			if z then
				-- tapered: widest a little past the middle, pointed ends
				local taper = sin(math.pi * clamp(t * 0.92 + 0.04, 0, 1)) ^ 0.75
				core[#core + 1] = { x, y, z, w * taper }
				halo[#halo + 1] = { x, y, z, w * (2.6 + 0.8 * taper) }
				inner[#inner + 1] = { x, y, z, w * 0.38 * taper }
				if y < lowY and t > 0.25 and t < 0.85 then
					lowX, lowY, lowT = x, y, t
				end
			end
		end
		if #core < 3 then
			return
		end
		if age < 2 then
			-- swollen, red skin round a fresh cut
			addStroke(M, halo, 0.96, 0.74, 0.74, 0.55 * clamp(sev, 0.3, 1) * (1 - age / 2), true, 1)
		end
		if age < 1 then
			addStroke(M, core, 0.4, 0.02, 0.035, 0.95, false, 0)
			if sev > 0.35 then
				addStroke(M, inner, 0.13, 0.0, 0.012, 0.85, false, 0)
			end
		elseif age < 6 then
			-- a dark scab, narrower as it heals
			local h = (age - 1) / 5
			for _, q in ipairs(core) do
				q[4] *= 1 - 0.35 * h
			end
			addStroke(M, core, 0.3 + 0.1 * h, 0.12 + 0.08 * h, 0.08 + 0.06 * h, 0.92 - 0.3 * h, false, 0)
		else
			-- a pink healing line
			for _, q in ipairs(core) do
				q[4] *= 0.6
			end
			addStroke(M, core, 1.07, 0.8, 0.8, clamp(0.7 - (age - 6) / 12, 0.15, 0.7), true, 0.3)
		end
		if bleed and fresh and lowX then
			trickle(lowX, lowY - w, (0.07 + 0.22 * min(sev, 1)) * k, (0.0028 + 0.0016 * min(sev, 1)) * k, seed, 0.92, s)
			if sev > 0.6 then
				local q = core[max(1, floor(#core * 0.3))]
				trickle(q[1], q[2] - w, (0.05 + 0.12 * sev) * k, 0.0024 * k, seed + 5, 0.85, s)
			end
		end
	end
	pause()
	local cuts = { { n("cut"), cutSide, 1 }, { n("cut2"), (tonumber(dmg.cutSide2) or -cutSide) < 0 and -1 or 1, 2 } }
	for _, c in ipairs(cuts) do
		local cv, s, which = c[1], c[2], c[3]
		local mid, outer, inn = brMid[s], brOut[s], brIn[s]
		pause()
		if cv > 0.05 and mid and outer and inn then
			local w = (0.0032 + 0.0026 * min(cv, 1)) * k
			local L = 0.45 + 0.55 * min(cv, 1)
			if which == 1 then
				-- the lateral brow: along the brow's outer half, just above it, over the orbit rim
				local ax, ay = mid[1] + s * 0.004 * k, mid[2] + 0.012 * k
				local bx, by = outer[1] + s * 0.008 * k, outer[2] + 0.004 * k
				ax, ay = bx + (ax - bx) * L, by + (ay - by) * L
				gash(ax, ay, (ax + bx) * 0.5, (ay + by) * 0.5 + 0.012 * k, bx, by, w, cv, 11 + s, s, cv > 0.3)
			else
				-- the brow ridge above the inner brow, slanting up and out
				local ax, ay = inn[1] + s * 0.012 * k, inn[2] + 0.026 * k
				local bx, by = mid[1] + s * 0.006 * k, mid[2] + 0.04 * k
				bx, by = ax + (bx - ax) * L, ay + (by - ay) * L
				gash(ax, ay, (ax + bx) * 0.5, (ay + by) * 0.5 + 0.008 * k, bx, by, w * 0.85, cv, 23 + s, s, cv > 0.3)
			end
		end
	end
	pause()
	-- a cheekbone gash on the cut side when the cuts are bad
	local cv1 = n("cut")
	if tier >= 3 and cv1 > 0.65 then
		local e = eye[cutSide]
		local s = cutSide
		local ax, ay = e[1] - s * 0.004 * k, e[2] - 0.092 * k
		local bx, by = e[1] + s * 0.058 * k, e[2] - 0.072 * k
		gash(ax, ay, (ax + bx) * 0.5, (ay + by) * 0.5 - 0.008 * k, bx, by, (0.0026 + 0.002 * cv1) * k, cv1 * 0.8, 37 + s, s, true)
	end

	pause()
	-- 7. a bleeding nose: from both nostrils over the upper lip (heavy: on over the lips to the chin)
	local bleed = n("noseBleed")
	local lu, ll = p("LipUpper"), p("LipLower")
	if bleed > 0.2 and fresh and lu then
		-- one nostril bleeds more (the side the nose was hit from); the other a thinner, shorter run that
		-- wanders off on its own line
		local main = (tonumber(dmg.cutSide) or 1) >= 0 and 1 or -1
		for s = -1, 1, 2 do
			local ns = p(s < 0 and "NostrilL" or "NostrilR")
			local lead = s == main
			if ns and (lead or bleed > 0.45) then
				local len = (ns[2] - lu[2]) + (0.02 + 0.14 * clamp(bleed - 0.3, 0, 1)) * k * (lead and 1 or 0.45)
				local w = (0.0042 + 0.0022 * min(bleed, 1)) * k * (lead and 1 or 0.65)
				trickle(ns[1] + s * (lead and 0.002 or 0.005) * k, ns[2] - 0.004 * k, len, w, 41 + s * 7, lead and 0.92 or 0.75, nil, lead and 1.6 or 2.2)
			end
		end
		-- smeared under the nose
		local z = surf(lu[1], lu[2] + 0.03 * k)
		if z then
			addBlot(M, lu[1], lu[2] + 0.03 * k, z, 0.04 * k, 0.018 * k, 0.04 * k, 0, BLOOD_DRY[1], BLOOD_DRY[2], BLOOD_DRY[3], 0.35 * min(bleed, 1), false, nil, 0.5)
		end
	end

	pause()
	-- 8. a split lip: a short cut across the lower lip, a bruise on it, bleeding down the chin
	local lip = n("lip")
	if lip > 0.25 and ll then
		local lx, ly = ll[1] + 0.045 * k, ll[2]
		local zb = surf(lx, ly)
		if zb then
			local r, g, b = bruiseTint(age, 0.7)
			addBlot(M, ll[1] + 0.03 * k, ly, zb, 0.045 * k, 0.02 * k, 0.04 * k, 0, r, g, b, clamp(0.4 * lip, 0, 0.5) * fade, true, nil, 0.3)
		end
		local pts = {}
		for i = 0, 4 do
			local t = i / 4
			local x, y = lx + 0.004 * k * t, ly + (0.012 - 0.024 * t) * k
			local z = surf(x, y)
			if z then
				pts[#pts + 1] = { x, y, z, (0.0028 + 0.002 * min(lip, 1)) * k * sin(math.pi * clamp(t * 0.9 + 0.05, 0, 1)) ^ 0.6 }
			end
		end
		if age < 1 then
			addStroke(M, pts, 0.36, 0.015, 0.035, 0.95, false, 0)
		elseif age < 6 then
			addStroke(M, pts, 0.32, 0.12, 0.09, 0.85, false, 0)
		end
		if lip > 0.6 and fresh then
			trickle(lx + 0.004 * k, ly - 0.012 * k, (0.06 + 0.08 * lip) * k, 0.0034 * k, 53, 0.88, nil)
		end
	end

	-- 9. a beaten, bleeding face late in a fight: blood smeared on the chin
	local chin = p("Chin")
	if tier >= 4 and fresh and chin and (n("cut") > 0.3 or bleed > 0.3 or lip > 0.5) then
		local z = surf(chin[1] + 0.02 * k, chin[2] + 0.035 * k)
		if z then
			addBlot(M, chin[1] + 0.02 * k, chin[2] + 0.035 * k, z, 0.07 * k, 0.04 * k, 0.06 * k, 0.2, BLOOD_DRY[1], BLOOD_DRY[2], BLOOD_DRY[3], 0.4, false, nil, 0.6)
		end
	end

	pause()
	-- 10. grime: dull mottled smudges (forehead, temple, cheek, jaw, chin)
	if grime > 0.05 then
		local a = 0.55 * grime
		local spots = {
			{ -0.09, 0.2, 0.07, 0.045 }, { 0.3, 0.05, 0.05, 0.07 }, { -0.27, -0.1, 0.07, 0.06 }, { 0.22, -0.26, 0.08, 0.05 },
			{ 0.02, -0.36, 0.06, 0.035 }, { -0.33, 0.06, 0.04, 0.06 },
		}
		for i, sp in ipairs(spots) do
			local x, y = sp[1] * k, eyeY + sp[2] * k
			local z, nrm = on(x, y)
			if z then
				addBlot(M, x, y, z, sp[3] * k, sp[4] * k, 0.08 * k, (i - 3) * 0.4, 0.86, 0.82, 0.76, a * (0.7 + 0.3 * h01(i, 3)), true, nrm, 0.6)
			end
		end
	end
	return M, lid
end

------------------------------------------------------------------------
-- Shading one point
------------------------------------------------------------------------
-- hm / lo / hi: the marks to test and, for strokes, the range of their segments near the point (nh of them);
-- ts: the size of one texel on the surface (anti-aliasing of thin strokes)
local function shadeHits(hm, hlo, hhi, nh, x, y, z, nx, ny, nz, ts, r, g, b)
	for j = 1, nh do
		local m = hm[j]
		local a = 0
		if m.kind == 1 then
			local dx, dy, dz = x - m.x, y - m.y, z - m.z
			local u = (dx * m.c + dy * m.s) * m.iax
			local v = (dy * m.c - dx * m.s) * m.iay
			local w = dz * m.iaz
			local q = u * u + v * v + w * w
			if q < 1 then
				a = 1 - q
				a = a * a * m.a
				local fx = m.fx
				if fx then
					-- facing: full at the blot's own normal, nothing past ~70 degrees from it
					local f = nx * fx + ny * m.fy + nz * m.fz
					if f < 0.75 then
						a *= f <= 0.3 and 0 or (f - 0.3) / 0.45
					end
				end
				local mot = m.mot
				if mot > 0 and a > 0 then
					local mf = m.mf
					local nn = sin(x * mf + 1.7 * sin(y * mf * 1.3 + z * mf * 0.7))
					a *= 1 - mot * (0.5 + 0.5 * nn)
				end
			end
		else
			local X, Y, Z, R, IL = m.X, m.Y, m.Z, m.R, m.IL
			local SX0, SX1, SY0, SY1 = m.SX0, m.SX1, m.SY0, m.SY1
			local best, bestR = huge, 0
			for i = hlo[j], hhi[j] do
				if x >= SX0[i] and x <= SX1[i] and y >= SY0[i] and y <= SY1[i] then
					local ax, ay, az = X[i], Y[i], Z[i]
					local sx, sy, sz = X[i + 1] - ax, Y[i + 1] - ay, Z[i + 1] - az
					local px, py, pz = x - ax, y - ay, z - az
					local t = (px * sx + py * sy + pz * sz) * IL[i]
					t = t < 0 and 0 or (t > 1 and 1 or t)
					px, py, pz = px - sx * t, py - sy * t, pz - sz * t
					local rad = R[i] + (R[i + 1] - R[i]) * t
					-- normalised by the radius the anti-aliasing allows (a sub-texel stroke: one texel, fainter)
					local re = rad + 0.5 * ts
					local q = (px * px + py * py + pz * pz) / (re * re)
					if q < best then
						best, bestR = q, rad
					end
				end
			end
			if best < 1 then
				local re = bestR + 0.5 * ts
				local d = sqrt(best) * re -- distance from the centre line
				local edge = ts + m.soft * bestR
				local cov = (re - d) / edge
				cov = cov >= 1 and 1 or cov
				if cov > 0 then
					if m.soft > 0 then
						cov = cov * cov * (3 - 2 * cov)
					end
					local thin = bestR < 0.5 * ts and bestR / (0.5 * ts) or 1
					a = m.a * cov * thin
				end
			end
		end
		if a > 0 then
			if m.mul then
				r, g, b = r * (1 + (m.r - 1) * a), g * (1 + (m.g - 1) * a), b * (1 + (m.b - 1) * a)
			else
				r, g, b = r + (m.r - r) * a, g + (m.g - g) * a, b + (m.b - b) * a
			end
		end
	end
	return r, g, b
end

-- the marks whose box holds (x0..x1, y0..y1, z0..z1), into hm / hlo / hhi; returns the count
local function collect(marks, x0, x1, y0, y1, z0, z1, hm, hlo, hhi)
	local nh = 0
	for _, m in ipairs(marks) do
		if x1 >= m.x0 and x0 <= m.x1 and y1 >= m.y0 and y0 <= m.y1 and z1 >= m.z0 and z0 <= m.z1 then
			if m.kind == 1 then
				nh += 1
				hm[nh], hlo[nh], hhi[nh] = m, 0, 0
			else
				local SX0, SX1, SY0, SY1 = m.SX0, m.SX1, m.SY0, m.SY1
				local lo, hi = 0, -1
				for i = 1, m.n - 1 do
					if x1 >= SX0[i] and x0 <= SX1[i] and y1 >= SY0[i] and y0 <= SY1[i] then
						if lo == 0 then
							lo = i
						end
						hi = i
					end
				end
				if lo > 0 then
					nh += 1
					hm[nh], hlo[nh], hhi[nh] = m, lo, hi
				end
			end
		end
	end
	return nh
end

function Damage.Shade(marks, x, y, z, nx, ny, nz, ts, r, g, b)
	local hm, hlo, hhi = {}, {}, {}
	local nh = collect(marks, x, x, y, y, z, z, hm, hlo, hhi)
	if nh == 0 then
		return r, g, b, false
	end
	local r2, g2, b2 = shadeHits(hm, hlo, hhi, nh, x, y, z, nx, ny, nz, ts, r, g, b)
	return r2, g2, b2, r2 ~= r or g2 ~= g or b2 ~= b
end

local function unionBox(marks)
	local x0, x1, y0, y1, z0, z1 = huge, -huge, huge, -huge, huge, -huge
	for _, m in ipairs(marks) do
		x0, x1, y0, y1, z0, z1 = min(x0, m.x0), max(x1, m.x1), min(y0, m.y0), max(y1, m.y1), min(z0, m.z0), max(z1, m.z1)
	end
	return x0, x1, y0, y1, z0, z1
end

------------------------------------------------------------------------
-- Painting the texture (triangle rasteriser over the texels of the triangles under a mark)
------------------------------------------------------------------------
local EPS = -1e-7 -- the texels whose centre a triangle covers (the generator's rule: each texel once)
local STRIP = 32 -- texel rows per written strip (each strip spans only its own dirty columns)

-- returns strips { { x0, y0, w, h, pixels }, ... } (nil when nothing changes) and the triangles painted now
function Damage.PaintTexture(mesh, W, H, orig, marks, was, step)
	local P, U, T, N = mesh.P, mesh.U, mesh.T, mesh.N
	local nt = mesh.nt
	was = was or {}
	local ux0, ux1, uy0, uy1, uz0, uz1 = unionBox(marks)
	local now = {}
	local work, nw = {}, 0
	local nS = ceil(H / STRIP)
	local SX0, SX1 = table.create(nS, W), table.create(nS, -1)
	local cm, clo, chi = {}, {}, {}
	local any = false
	for t = 1, nt do
		local ia, ib, ic = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		local hit = false
		local xa, ya, za = P[ia * 3 - 2], P[ia * 3 - 1], P[ia * 3]
		local xb, yb, zb = P[ib * 3 - 2], P[ib * 3 - 1], P[ib * 3]
		local xc, yc, zc = P[ic * 3 - 2], P[ic * 3 - 1], P[ic * 3]
		local tx0, tx1 = min(xa, xb, xc), max(xa, xb, xc)
		local ty0, ty1 = min(ya, yb, yc), max(ya, yb, yc)
		local tz0, tz1 = min(za, zb, zc), max(za, zb, zc)
		if tx1 >= ux0 and tx0 <= ux1 and ty1 >= uy0 and ty0 <= uy1 and tz1 >= uz0 and tz0 <= uz1 then
			local nh = collect(marks, tx0, tx1, ty0, ty1, tz0, tz1, cm, clo, chi)
			if nh > 0 then
				hit = true
				now[t] = true
				nw += 1
				work[nw] = { t, table.move(cm, 1, nh, 1, table.create(nh)), table.move(clo, 1, nh, 1, table.create(nh)), table.move(chi, 1, nh, 1, table.create(nh)), nh }
			end
		end
		if hit or was[t] then
			local ua, ub, uc = U[ia * 2 - 1] * W, U[ib * 2 - 1] * W, U[ic * 2 - 1] * W
			local va, vb, vc = U[ia * 2] * H, U[ib * 2] * H, U[ic * 2] * H
			local px0, px1 = max(0, floor(min(ua, ub, uc) - 1.5)), min(W - 1, ceil(max(ua, ub, uc) + 0.5))
			local py0, py1 = max(0, floor(min(va, vb, vc) - 1.5)), min(H - 1, ceil(max(va, vb, vc) + 0.5))
			for s = py0 // STRIP + 1, py1 // STRIP + 1 do
				if px0 < SX0[s] then
					SX0[s] = px0
				end
				if px1 > SX1[s] then
					SX1[s] = px1
				end
			end
			any = true
		end
		if step and t % 64 == 0 then
			step(64)
		end
	end
	if not any then
		return nil, now
	end
	-- the strips, from the generated pixels
	local strips, SB = {}, table.create(nS, false)
	for s = 1, nS do
		if SX1[s] >= SX0[s] then
			local y0 = (s - 1) * STRIP
			local h = min(STRIP, H - y0)
			local w = SX1[s] - SX0[s] + 1
			local buf = buffer.create(w * h * 4)
			for py = y0, y0 + h - 1 do
				buffer.copy(buf, (py - y0) * w * 4, orig, (py * W + SX0[s]) * 4, w * 4)
			end
			SB[s] = buf
			strips[#strips + 1] = { SX0[s], y0, w, h, buf }
			if step then
				step(h)
			end
		end
	end
	for k = 1, nw do
		local wk = work[k]
		local t, hm, hlo, hhi, nh = wk[1], wk[2], wk[3], wk[4], wk[5]
		local ia, ib, ic = T[t * 3 - 2], T[t * 3 - 1], T[t * 3]
		-- texel centres: px + 0.5 = u * W (the generator's convention)
		local ax, ay = U[ia * 2 - 1] * W - 0.5, U[ia * 2] * H - 0.5
		local bx, by = U[ib * 2 - 1] * W - 0.5, U[ib * 2] * H - 0.5
		local cx, cy = U[ic * 2 - 1] * W - 0.5, U[ic * 2] * H - 0.5
		local area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
		if area > 1e-9 or area < -1e-9 then
			local inv = 1 / area
			local A0, B0, C0 = (by - cy) * inv, (cx - bx) * inv, (bx * cy - by * cx) * inv
			local A1, B1, C1 = (cy - ay) * inv, (ax - cx) * inv, (cx * ay - cy * ax) * inv
			local A2, B2, C2 = -A0 - A1, -B0 - B1, 1 - C0 - C1
			local E0, E1, E2 = EPS, EPS, EPS
			local a3, b3, c3 = ia * 3, ib * 3, ic * 3
			-- attribute planes f = fX * px + fY * py + fO (f = fc + (fa - fc) * w0 + (fb - fc) * w1)
			local da, db, fc = P[a3 - 2] - P[c3 - 2], P[b3 - 2] - P[c3 - 2], P[c3 - 2]
			local xX, xY, xO = da * A0 + db * A1, da * B0 + db * B1, fc + da * C0 + db * C1
			da, db, fc = P[a3 - 1] - P[c3 - 1], P[b3 - 1] - P[c3 - 1], P[c3 - 1]
			local yX, yY, yO = da * A0 + db * A1, da * B0 + db * B1, fc + da * C0 + db * C1
			da, db, fc = P[a3] - P[c3], P[b3] - P[c3], P[c3]
			local zX, zY, zO = da * A0 + db * A1, da * B0 + db * B1, fc + da * C0 + db * C1
			local nX, nY, nO, mX, mY, mO, oX, oY, oO = 0, 0, 0, 0, 0, 0, 0, 0, -1
			if N then
				da, db, fc = N[a3 - 2] - N[c3 - 2], N[b3 - 2] - N[c3 - 2], N[c3 - 2]
				nX, nY, nO = da * A0 + db * A1, da * B0 + db * B1, fc + da * C0 + db * C1
				da, db, fc = N[a3 - 1] - N[c3 - 1], N[b3 - 1] - N[c3 - 1], N[c3 - 1]
				mX, mY, mO = da * A0 + db * A1, da * B0 + db * B1, fc + da * C0 + db * C1
				da, db, fc = N[a3] - N[c3], N[b3] - N[c3], N[c3]
				oX, oY, oO = da * A0 + db * A1, da * B0 + db * B1, fc + da * C0 + db * C1
			end
			-- one texel's size on the surface
			local e1x, e1y, e1z = P[b3 - 2] - P[a3 - 2], P[b3 - 1] - P[a3 - 1], P[b3] - P[a3]
			local e2x, e2y, e2z = P[c3 - 2] - P[a3 - 2], P[c3 - 1] - P[a3 - 1], P[c3] - P[a3]
			local crx, cry, crz = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
			local ts = sqrt(sqrt(crx * crx + cry * cry + crz * crz) / abs(area))
			local X0, X1 = max(0, floor(min(ax, bx, cx) - 1)), min(W - 1, ceil(max(ax, bx, cx) + 1))
			local Y0, Y1 = max(0, floor(min(ay, by, cy) - 1)), min(H - 1, ceil(max(ay, by, cy) + 1))
			for py = Y0, Y1 do
				local s = py // STRIP + 1
				local sx0 = SX0[s]
				local lo, hi = max(X0, sx0), min(X1, SX1[s])
				local ok = true
				local R = B0 * py + C0
				if A0 > 1e-12 then
					lo = max(lo, ceil((E0 - R) / A0))
				elseif A0 < -1e-12 then
					hi = min(hi, floor((E0 - R) / A0))
				elseif R < E0 then
					ok = false
				end
				R = B1 * py + C1
				if A1 > 1e-12 then
					lo = max(lo, ceil((E1 - R) / A1))
				elseif A1 < -1e-12 then
					hi = min(hi, floor((E1 - R) / A1))
				elseif R < E1 then
					ok = false
				end
				R = B2 * py + C2
				if A2 > 1e-12 then
					lo = max(lo, ceil((E2 - R) / A2))
				elseif A2 < -1e-12 then
					hi = min(hi, floor((E2 - R) / A2))
				elseif R < E2 then
					ok = false
				end
				if ok and lo <= hi then
					local out = SB[s]
					local sw = SX1[s] - sx0 + 1
					local o = (py * W + lo) * 4
					local q = ((py - (s - 1) * STRIP) * sw + (lo - sx0)) * 4
					local x, y, z = xX * lo + xY * py + xO, yX * lo + yY * py + yO, zX * lo + zY * py + zO
					local nx, ny, nz = nX * lo + nY * py + nO, mX * lo + mY * py + mO, oX * lo + oY * py + oO
					for _ = lo, hi do
						local r, g, b = readu8(orig, o) / 255, readu8(orig, o + 1) / 255, readu8(orig, o + 2) / 255
						local r2, g2, b2 = shadeHits(hm, hlo, hhi, nh, x, y, z, nx, ny, nz, ts, r, g, b)
						if r2 ~= r or g2 ~= g or b2 ~= b then
							writeu8(out, q, floor(clamp(r2, 0, 1) * 255 + 0.5))
							writeu8(out, q + 1, floor(clamp(g2, 0, 1) * 255 + 0.5))
							writeu8(out, q + 2, floor(clamp(b2, 0, 1) * 255 + 0.5))
						end
						o += 4
						q += 4
						x += xX
						y += yX
						z += zX
						nx += nX
						ny += mX
						nz += oX
					end
					if step then
						step((hi - lo + 1) * nh)
					end
				end
			end
		end
	end
	return strips, now
end

------------------------------------------------------------------------
-- The same marks as vertex colours (a piece without a texture). ids: the vertices to consider (nil = all);
-- was: the vertices touched last time (they go back to the generated colours)
------------------------------------------------------------------------
function Damage.PaintVertices(mesh, marks, was, step, ids, ts)
	local P, C, N = mesh.P, mesh.C, mesh.N
	was = was or {}
	ts = ts or 0.012
	local ux0, ux1, uy0, uy1, uz0, uz1 = unionBox(marks)
	local outIds, cols, now = {}, {}, {}
	local hm, hlo, hhi = {}, {}, {}
	local count = ids and #ids or mesh.nv
	for k = 1, count do
		local i = ids and ids[k] or k
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		local r, g, b = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
		local hit = false
		if x >= ux0 and x <= ux1 and y >= uy0 and y <= uy1 and z >= uz0 and z <= uz1 then
			local nh = collect(marks, x, x, y, y, z, z, hm, hlo, hhi)
			if nh > 0 then
				local nx, ny, nz = 0, 0, -1
				if N then
					nx, ny, nz = N[i * 3 - 2], N[i * 3 - 1], N[i * 3]
				end
				local r2, g2, b2 = shadeHits(hm, hlo, hhi, nh, x, y, z, nx, ny, nz, ts, r, g, b)
				if r2 ~= r or g2 ~= g or b2 ~= b then
					r, g, b = r2, g2, b2
					hit = true
				end
			end
		end
		if hit or was[i] then
			outIds[#outIds + 1] = i
			cols[#cols + 1] = { clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1) }
			if hit then
				now[i] = true
			end
		end
		if step and k % 128 == 0 then
			step(128)
		end
	end
	return outIds, cols, now
end

------------------------------------------------------------------------
-- A bloodshot eye (the eyeball texture's polar map: the white is beyond radius 0.3, the visible white up to
-- ~0.37; redder toward the corners, a bright haemorrhage on the outer side when k is high)
------------------------------------------------------------------------
function Damage.Sclera(W, H, orig, k, side, step)
	local out = buffer.create(W * H * 4)
	buffer.copy(out, 0, orig, 0, W * H * 4)
	if k <= 0.01 then
		return out
	end
	for py = 0, H - 1 do
		for px = 0, W - 1 do
			local du, dv = (px + 0.5) / W - 0.5, (py + 0.5) / H - 0.5
			local r = sqrt(du * du + dv * dv)
			if r > 0.29 then
				local ph = math.atan2(-dv, du)
				local corner = abs(cos(ph))
				local a = k * clamp((r - 0.29) / 0.035, 0, 1) * (0.45 + 0.55 * corner)
				-- the outer corner (toward +side x on the face): a haemorrhage patch
				local lateral = cos(ph) * (side or 1)
				if k > 0.45 and lateral > 0.55 and r < 0.4 then
					a = max(a, clamp((k - 0.45) * 2.2, 0, 0.9) * clamp((lateral - 0.55) / 0.2, 0, 1))
				end
				if a > 0.003 then
					local o = (py * W + px) * 4
					local cr, cg, cb = readu8(orig, o), readu8(orig, o + 1), readu8(orig, o + 2)
					writeu8(out, o, floor(cr + (205 - cr) * a + 0.5))
					writeu8(out, o + 1, floor(cg + (55 - cg) * a + 0.5))
					writeu8(out, o + 2, floor(cb + (60 - cb) * a + 0.5))
				end
			end
		end
		if step then
			step(W)
		end
	end
	return out
end

return Damage
