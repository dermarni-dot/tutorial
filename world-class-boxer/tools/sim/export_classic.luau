--!nocheck
-- export_classic.luau: the asset hair's reference for the CLASSIC head (tools/hair/ref/classic/skull.json), from
-- the game's own Kit: the classic head's field (AnatomyHairKit.CLASSIC, Kit.Scalp of a look.headShape "classic"),
-- its hairline keys (Kit.ClassicKeys), Kit.Hairline per kind, Kit.Cut coverage per fade, the fades' weight
-- lines and the body proxy. Same schema as the retired organic tools/hair/ref/skull.json (export_ref.luau), so
-- the Blender builders read either. The ears, the brows and the head mesh are added by tools/hair/classic_ref.py
-- (from BuilderHead's face layout), which also writes head_m.obj / head_f.obj.
--   lune run tools/sim/export_classic.luau [--out FILE]
local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")
local Host = require("./host")

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		args[a[i]:gsub("^%-%-", "")] = a[i + 1]
		i += 2
	end
end
local H = Host.new()
local ROOT = H.root
local OUTF = args.out or (ROOT .. "/tools/hair/ref/classic/skull_game.json")

local Kit = H.require("AnatomyHairKit")
local HK = H.require("HairAssetKit")
local sin, cos, pi, floor = math.sin, math.cos, math.pi, math.floor

local function rnd(x, q)
	q = q or 10000
	return floor(x * q + 0.5) / q
end

local function exitT(f, cx, cy, cz, dx, dy, dz, tmax)
	local step, t, prev = 0.01, 0, 0
	tmax = tmax or 1.6
	if f(cx, cy, cz) >= 0 then
		return 0
	end
	while t < tmax do
		t += step
		if f(cx + dx * t, cy + dy * t, cz + dz * t) >= 0 then
			local lo, hi = prev, t
			for _ = 1, 32 do
				local m = (lo + hi) * 0.5
				if f(cx + dx * m, cy + dy * m, cz + dz * m) < 0 then
					lo = m
				else
					hi = m
				end
			end
			return (lo + hi) * 0.5
		end
		prev = t
	end
	return nil
end

local function plain(v, depth)
	depth = depth or 0
	local tv = type(v)
	if tv == "number" then
		return (v ~= v or v == math.huge or v == -math.huge) and nil or rnd(v, 1e6)
	elseif tv == "string" or tv == "boolean" then
		return v
	elseif tv == "table" and depth < 6 then
		local o = {}
		for k, x in pairs(v) do
			if type(k) == "string" or type(k) == "number" then
				o[k] = plain(x, depth + 1)
			end
		end
		return o
	end
	return nil
end

local FADE_TOP
do
	local src = fs.readFile(H.src .. "/shared/AnatomyHair.lua")
	local tbl = src:match("local FADE_TOP = (%b{})")
	FADE_TOP = tbl and luau.load("return " .. tbl)() or nil
end
-- on the classic head the top hair starts as much higher as the fades' side lines (Kit.CLASSIC_HAIR.fadeSide)
local FADE_TOP_C = {}
for k, v in pairs(FADE_TOP or {}) do
	FADE_TOP_C[k] = v + Kit.CLASSIC_HAIR.fadeSide
end

local HAIRLINES = { "Natural", "Straight", "Widow's Peak", "Receding", "Line-Up" }
local FADE_KINDS = { "low", "mid", "high", "fade", "taper", "burst" }

local function classicRef(g)
	local look = H.Look({ g = g, headShape = "classic" })
	local S = Kit.Scalp(look)
	assert(S.classic, "not the classic head")
	local f = S.f
	local P = S.P
	local cx, cy, cz = 0, S.cy, S.cz
	local thetas, azs = {}, {}
	for i = 0, 64 do
		thetas[#thetas + 1] = i * 2.5
	end
	for j = 0, 71 do
		azs[#azs + 1] = j * 5
	end
	local r, pts = {}, {}
	for i, th in ipairs(thetas) do
		local row, prow = table.create(#azs), table.create(#azs)
		local t = math.rad(th)
		for j, az in ipairs(azs) do
			local a = math.rad(az)
			local dx, dy, dz = sin(t) * sin(a), cos(t), sin(t) * cos(a)
			local d = exitT(f, cx, cy, cz, dx, dy, dz) or -1
			row[j] = rnd(d)
			prow[j] = { cx + dx * d, cy + dy * d, cz + dz * d }
		end
		r[i] = row
		pts[i] = prow
	end
	local AX, AZ = 0, 0.05
	local function meridianPoint(hx, hz, phi)
		local dx, dy, dz = hx * cos(phi), sin(phi), hz * cos(phi)
		local t = exitT(f, AX, cy, AZ, dx, dy, dz) or 0
		return AX + dx * t, cy + dy * t, AZ + dz * t
	end
	local lines = {}
	for _, kind in ipairs(HAIRLINES) do
		local dist, height = Kit.Hairline(S, kind, 0)
		local L = { right = {}, left = {}, height = {} }
		local da = 0
		while da <= pi + 1e-9 do
			L.height[#L.height + 1] = { rnd(da), rnd(height(da)) }
			for _, side in ipairs({ 1, -1 }) do
				local a = pi / 2 - side * da
				local hx, hz = cos(a), -sin(a)
				local found
				local pPrev, x0, y0, z0 = math.rad(88), meridianPoint(hx, hz, math.rad(88))
				local d0 = dist(x0, y0, z0)
				for k = 87, -85, -1 do
					local ph = math.rad(k)
					local x1, y1, z1 = meridianPoint(hx, hz, ph)
					local d1 = dist(x1, y1, z1)
					if d0 > 0 and d1 <= 0 then
						local lo, hi = ph, pPrev
						for _ = 1, 30 do
							local m = (lo + hi) * 0.5
							local xm, ym, zm = meridianPoint(hx, hz, m)
							if dist(xm, ym, zm) > 0 then
								hi = m
							else
								lo = m
							end
						end
						local xm, ym, zm = meridianPoint(hx, hz, (lo + hi) * 0.5)
						found = { rnd(da), rnd(xm), rnd(ym), rnd(zm) }
						break
					end
					pPrev, d0 = ph, d1
				end
				local list = side > 0 and L.right or L.left
				list[#list + 1] = found or { rnd(da), false }
			end
			da += 0.02
		end
		lines[kind] = L
	end
	local coverage = {}
	for _, kind in ipairs({ "none", table.unpack(FADE_KINDS) }) do
		local cut = Kit.Cut(S, { fade = kind ~= "none" and kind or nil, hairline = "Natural", growth = 0 })
		local grid = {}
		for i = 1, #thetas do
			local row = table.create(#azs)
			for j = 1, #azs do
				local p = pts[i][j]
				row[j] = rnd((cut.cov(p[1], p[2], p[3])), 1000)
			end
			grid[i] = row
		end
		coverage[kind] = grid
	end
	local FADES_C = {}
	for k, F in pairs(Kit.FADES) do
		FADES_C[k] = table.clone(F)
		if F.side then
			FADES_C[k].side = F.side + Kit.CLASSIC_HAIR.fadeSide
		end
	end
	local fadeLines = {}
	for _, kind in ipairs({ "low", "mid", "high", "fade" }) do
		local F = FADES_C[kind]
		local L = { right = {}, left = {} }
		local da = 0.55
		while da <= pi + 1e-9 do
			local y = F.side + (F.back - F.side) * Kit.smoothstep(1.7, 2.75, da)
			for _, side in ipairs({ 1, -1 }) do
				local a = pi / 2 - side * da
				local hx, hz = cos(a), -sin(a)
				local lo, hi = math.rad(-85), math.rad(88)
				for _ = 1, 30 do
					local m = (lo + hi) * 0.5
					local _, ym = meridianPoint(hx, hz, m)
					if ym > y then
						hi = m
					else
						lo = m
					end
				end
				local xm, ym, zm = meridianPoint(hx, hz, (lo + hi) * 0.5)
				local list = side > 0 and L.right or L.left
				list[#list + 1] = { rnd(da), rnd(xm), rnd(ym), rnd(zm) }
			end
			da += 0.05
		end
		fadeLines[kind] = L
	end
	local top = S.neckTop
	local ux, uy, uz, hx, hy, hz = table.unpack(S.torso)
	local bodySurf = { azimuths = {}, rows = {} }
	for a = 0, 350, 10 do
		bodySurf.azimuths[#bodySurf.azimuths + 1] = a
	end
	local y = top + 0.45
	while y >= top - 1.4 - 1e-9 do
		local row = { rnd(y), {} }
		for _, ad in ipairs(bodySurf.azimuths) do
			local a = math.rad(ad)
			local t = exitT(function(px, py, pz)
				return S.body(px, py, pz)
			end, 0, y, 0, sin(a), 0, cos(a), 3)
			table.insert(row[2], t and rnd(t) or false)
		end
		bodySurf.rows[#bodySurf.rows + 1] = row
		y -= 0.05
	end
	local rig = look.rig
	local c0, c1 = rig.joints.Neck.c0, rig.joints.Neck.c1
	local ut = rig.parts.UpperTorso
	local utc = { c1[1] - c0[1], c1[2] - c0[2], c1[3] - c0[3] }
	local function nominal(p)
		return { rnd(p[1] / S.kx), rnd(p[2] / S.ky), rnd(p[3] / S.kz) }
	end
	local W, T, Fz, Bz = HK.Measure(S)
	return {
		about = "CLASSIC head reference (Kit.Scalp of a look.headShape \"classic\": AnatomyHairKit.CLASSIC rounded cylinder), NOMINAL head space (1.2-stud head; real = nominal * k), +X right, +Y up, -Z forward, origin = Head part centre",
		shape = "classic",
		classic = plain(Kit.CLASSIC),
		classicHair = plain(Kit.CLASSIC_HAIR),
		gender = g == 2 and "female" or "male",
		k = { rnd(S.kx, 1e6), rnd(S.ky, 1e6), rnd(S.kz, 1e6) },
		headSize = rig.parts.Head,
		centre = { 0, rnd(cy), rnd(cz) },
		fit0 = { W = rnd(W), T = rnd(T), Fz = rnd(Fz), Bz = rnd(Bz), shape = "classic" },
		radial = {
			about = "r[i][j]: distance from centre to the head surface along dir = (sin th sin az, cos th, sin th cos az); th = thetas[i] deg from +Y, az = azimuths[j] deg, 0 = +Z (back), 90 = +X (right), 180 = -Z (front)",
			thetas = thetas, azimuths = azs, r = r,
		},
		hairline = {
			about = "Kit.Hairline(S, kind, growth 0) on the classic head (Kit.ClassicKeys): per line, right / left = {da, x, y, z} surface points (da = angle from the front centre around the vertical axis x = 0, z = 0.05; right = +X); height = {da, nominal y of the line}. false = no crossing found",
			keys = plain(S.keys), lines = lines, soft = 0.016,
		},
		fades = {
			about = "Kit.FADES with the classic head's side lift (Kit.CLASSIC_HAIR.fadeSide) and AnatomyHair FADE_TOP + the same lift. topLines: the side/back top line {da, x, y, z}. coverage[kind][i][j]: Kit.Cut coverage at the radial grid's surface points (0 skin .. 1 hair; natural hairline, density 1)",
			FADES = plain(FADES_C), FADE_TOP = plain(FADE_TOP_C), topLines = fadeLines, coverage = coverage,
		},
		body = {
			about = "Kit.Scalp body proxy (nominal head space): S.body = smin(smin(capsule neck, ellipsoid trapezius, 0.2), roundbox torso, 0.12); surface.rows = {y, r per azimuth (deg, 0 = +Z back, 90 = +X)} distance from the axis x = z = 0 to S.body's zero set",
			neckTop = rnd(top), shoulderX = rnd(S.shoulderX),
			neckCapsule = { a = { 0, rnd(top + 0.45), 0.04 }, b = { 0, rnd(top - 0.3), 0 }, r = 0.31 },
			trapezius = { centre = { rnd(ux), rnd(top - 0.17), rnd(uz) }, radii = { rnd(hx * 0.94), 0.25, rnd(hz * 0.92) }, blend = 0.2 },
			torsoBox = { centre = { rnd(ux), rnd(uy), rnd(uz) }, half = { rnd(hx * 0.88), rnd(hy), rnd(hz * 0.96) }, round = 0.2, blend = 0.12 },
			surface = bodySurf,
		},
		rig = {
			about = "the default rig (tools/sim/host.luau Host.RIG): real studs; head space positions also nominal",
			parts = rig.parts, joints = rig.joints,
			headSpace = {
				neckPivot = { real = c1, nominal = nominal(c1) },
				upperTorsoCentre = { nominal = nominal(utc) },
			},
		},
		neck = plain(P.neck),
		P = plain(P),
	}
end

Host.MkDir(ROOT .. "/tools/hair/ref/classic")
local ref = classicRef(1)
Host.WriteJSON(OUTF, ref)
Host.WriteJSON((OUTF:gsub("%.json$", "_f.json")), classicRef(2))
print(string.format("%s: radial %dx%d, fit0 W %.3f T %.3f Fz %.3f Bz %.3f, front hairline %.3f", OUTF,
	#ref.radial.thetas, #ref.radial.azimuths, ref.fit0.W, ref.fit0.T, ref.fit0.Fz, ref.fit0.Bz, ref.hairline.keys[1][2]))
