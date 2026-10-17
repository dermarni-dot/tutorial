--!nocheck
-- export_ref.luau: reference data for modelling hair outside Roblox (Blender), from the game's own generators.
--
--   lune run tools/sim/export_ref.luau [--ref DIR] [--before DIR] [--only id,id] [--no-ref] [--no-before]
--                                      [--src DIR]  (shared/ + client/ to run instead of src/, e.g. a git archive)
--
--   --ref     (default tools/hair/ref)       skull.json / skull_f.json, head_m.obj / head_f.obj,
--                                            torso_m.obj / torso_f.obj (nominal head space)
--   --before  (default tools/sim/out/before) one JSON per look of the CURRENT generated hair + head
--                                            (real head space) with .rgba textures, and index.json
-- Schemas: tools/sim/README.md.
local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")
local Host = require("./host")

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		local k = a[i]
		if k == "--no-ref" or k == "--no-before" then
			args[k:sub(3)] = true
			i += 1
		else
			args[k:gsub("^%-%-", "")] = a[i + 1]
			i += 2
		end
	end
end
local H = Host.new({ src = args.src })
local ROOT = H.root
local REF = args.ref or (ROOT .. "/tools/hair/ref")
local BEFORE = args.before or (ROOT .. "/tools/sim/out/before")

local Skull = H.require("AnatomySkull")
local Kit = H.require("AnatomyHairKit")
local Hair = H.require("AnatomyHair")
local Head = H.require("AnatomyHead")
local Body = H.require("AnatomyBody")
local MeshKit = H.require("MeshKit")
local Looks = H.require("Looks")

local sin, cos, pi, sqrt, abs, floor = math.sin, math.cos, math.pi, math.sqrt, math.abs, math.floor

local function rnd(x, q)
	q = q or 10000
	return floor(x * q + 0.5) / q
end

local function rv(t, q)
	local o = table.create(#t)
	for i, v in ipairs(t) do
		o[i] = rnd(v, q)
	end
	return o
end

-- first exit of the field f along a ray from (cx, cy, cz): marched then bisected
local function exitT(f, cx, cy, cz, dx, dy, dz, tmax)
	local step = 0.01
	local t = 0
	local prev = 0
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

-- plain copy of a table of numbers / strings / booleans / nested tables (JSON-safe)
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

-- FADE_TOP is local to AnatomyHair: read it from the source (src/ stays unchanged)
local FADE_TOP
do
	local src = fs.readFile(H.src .. "/shared/AnatomyHair.lua")
	local tbl = src:match("local FADE_TOP = (%b{})")
	FADE_TOP = tbl and luau.load("return " .. tbl)() or nil
end

------------------------------------------------------------------------
-- skull.json
------------------------------------------------------------------------
local HAIRLINES = { "Natural", "Straight", "Widow's Peak", "Receding", "Line-Up" }
local FADE_KINDS = { "low", "mid", "high", "fade", "taper", "burst" }

local function skullRef(g, headOut)
	local look = H.Look({ g = g })
	local P = Skull.Params(look)
	local f = Skull.Nominal(P)
	local S = Kit.Scalp(look)
	local cx, cy, cz = 0, P.cy, P.cz
	-- radial table
	local thetas, azs = {}, {}
	for i = 0, 60 do
		thetas[#thetas + 1] = i * 2.5
	end
	for j = 0, 71 do
		azs[#azs + 1] = j * 5
	end
	local r = {}
	local pts = {} -- [i][j] = {x, y, z} scalp points (reused by the coverage grids)
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
	-- hairlines as 3D polylines on the scalp: per angle from the front (da) and side, the point on the meridian
	-- (a vertical half plane through the axis x = 0, z = 0.05: the hairline's own parameter) where the
	-- hairline distance crosses zero, scanning down from the top
	local AX, AZ = 0, 0.05
	local function meridianPoint(hx, hz, phi)
		-- ray from (0, cy, 0.05) at elevation phi in the half plane (hx, hz)
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
				local a = pi / 2 - side * da -- 0 = +X (right), pi/2 = front (-Z)
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
	-- fade / cut coverage on the radial grid (natural hairline, growth 0): 0 bare skin .. 1 full hair
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
	-- fade top lines (where the gradient reaches full hair; Kit.Cut's yTop over da 0.55 .. pi), on the scalp
	local fadeLines = {}
	for _, kind in ipairs({ "low", "mid", "high", "fade" }) do
		local F = Kit.FADES[kind]
		local L = { right = {}, left = {} }
		local da = 0.55
		while da <= pi + 1e-9 do
			local y = F.side + (F.back - F.side) * Kit.smoothstep(1.7, 2.75, da)
			for _, side in ipairs({ 1, -1 }) do
				local a = pi / 2 - side * da
				local hx, hz = cos(a), -sin(a)
				-- the scalp point at height y on this meridian (bisection on elevation)
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
	-- the body proxy long hair rests on (Kit.Scalp's S.body), as parameters and as a sampled surface:
	-- per height, the distance from the vertical axis (x = 0, z = 0) to S.body's zero set by azimuth
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
			local dx, dz = sin(a), cos(a)
			local t = exitT(function(px, py, pz)
				return S.body(px, py, pz)
			end, 0, y, 0, dx, 0, dz, 3)
			table.insert(row[2], t and rnd(t) or false)
		end
		bodySurf.rows[#bodySurf.rows + 1] = row
		y -= 0.05
	end
	-- the rig in head space (real studs and nominal)
	local rig = look.rig
	local c0, c1 = rig.joints.Neck.c0, rig.joints.Neck.c1
	local ut = rig.parts.UpperTorso
	local utc = { c1[1] - c0[1], c1[2] - c0[2], c1[3] - c0[3] } -- UpperTorso centre in head space
	local function nominal(p)
		return { rnd(p[1] / P.kx), rnd(p[2] / P.ky), rnd(p[3] / P.kz) }
	end
	local shoulderR = { utc[1] + ut[1] / 2, utc[2] + 0.375 * ut[2], utc[3] }
	local shoulderL = { utc[1] - ut[1] / 2, utc[2] + 0.375 * ut[2], utc[3] }
	local utTop = { utc[1], utc[2] + ut[2] / 2, utc[3] }
	-- ears from the generated head (its ear vertices: UV islands v >= 0.905, u in [0.02, 0.24] left / [0.26, 0.48]
	-- right, AnatomyHead earMesh boxes), nominal
	local ears = {}
	if headOut then
		local m = headOut.pieces.Head.mesh
		for _, e in ipairs({ { "left", 0.02, 0.24 }, { "right", 0.26, 0.48 } }) do
			local b = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge }
			local n = 0
			for i = 1, m.nv do
				local u, v = m.U[i * 2 - 1], m.U[i * 2]
				if v >= 0.9 and u >= e[2] - 0.005 and u <= e[3] + 0.005 then
					n += 1
					local x, yy, z = m.P[i * 3 - 2] / P.kx, m.P[i * 3 - 1] / P.ky, m.P[i * 3] / P.kz
					b[1], b[2], b[3] = math.min(b[1], x), math.min(b[2], yy), math.min(b[3], z)
					b[4], b[5], b[6] = math.max(b[4], x), math.max(b[5], yy), math.max(b[6], z)
				end
			end
			ears[e[1]] = { min = { rnd(b[1]), rnd(b[2]), rnd(b[3]) }, max = { rnd(b[4]), rnd(b[5]), rnd(b[6]) }, verts = n }
		end
		ears.clearance = 0.02
		ears.note = "AABB of the head mesh's ear vertices, nominal; keep hair cards at least `clearance` outside it (tuck behind / above)"
	end
	local headLm = {}
	for name, lm in pairs(Head.Landmarks(look)) do
		headLm[name] = nominal(lm.pos)
	end
	local hairLm = {}
	for name, lm in pairs(Hair.Landmarks(look)) do
		hairLm[name] = nominal(lm.pos)
	end
	return {
		about = "AnatomySkull reference, NOMINAL head space (1.2-stud head; real = nominal * k), +X right, +Y up, -Z forward, origin = Head part centre",
		gender = g == 2 and "female" or "male",
		k = { rnd(P.kx, 1e6), rnd(P.ky, 1e6), rnd(P.kz, 1e6) },
		headSize = rig.parts.Head,
		centre = { 0, rnd(cy), rnd(cz) },
		radial = {
			about = "r[i][j]: distance from centre to the scalp (field zero set) along dir = (sin th sin az, cos th, sin th cos az); th = thetas[i] deg from +Y, az = azimuths[j] deg, 0 = +Z (back), 90 = +X (right), 180 = -Z (front)",
			thetas = thetas, azimuths = azs, r = r,
		},
		hairline = {
			about = "Kit.Hairline(S, kind, growth 0): per line, right / left = {da, x, y, z} scalp points (da = angle from the front centre around the vertical axis x = 0, z = 0.05; right = +X); height = {da, nominal y of the line}. false = no crossing found",
			keys = plain(Skull.HairlineHeights(P)), lines = lines, soft = 0.016,
		},
		fades = {
			about = "Kit.FADES (side / back: nominal y where the fade reaches full hair at the side / back; bottom: hair left at the hairline, 0 = skin; taper: band height above the hairline; burst: half circle round the ear) and AnatomyHair FADE_TOP (y where the top hair starts per fade). topLines: the side/back top line on the scalp {da, x, y, z}. coverage[kind][i][j]: Kit.Cut coverage at the radial grid's scalp points (0 skin .. 1 hair; includes the natural hairline edge and density 1)",
			FADES = plain(Kit.FADES), FADE_TOP = plain(FADE_TOP), topLines = fadeLines, coverage = coverage,
		},
		ears = ears,
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
				upperTorsoCentre = { real = rv(utc), nominal = nominal(utc) },
				upperTorsoTop = { real = rv(utTop), nominal = nominal(utTop) },
				rightShoulderPivot = { real = rv(shoulderR), nominal = nominal(shoulderR) },
				leftShoulderPivot = { real = rv(shoulderL), nominal = nominal(shoulderL) },
			},
		},
		neck = plain(P.neck),
		landmarks = { head = headLm, hair = hairLm },
		P = plain(P),
	}
end

------------------------------------------------------------------------
-- OBJ writer (v x y z r g b, vt u 1-v, vn, one `o` per piece)
------------------------------------------------------------------------
local function objOf(list, scale)
	local out = { "# world-class-boxer generated mesh (tools/sim/export_ref.luau); vt v is flipped (OBJ: 0 = bottom)" }
	local base = 0
	for _, it in ipairs(list) do
		local name, m = it[1], it[2]
		local sx, sy, sz = scale[1], scale[2], scale[3]
		local ox, oy, oz = it.offset and it.offset[1] or 0, it.offset and it.offset[2] or 0, it.offset and it.offset[3] or 0
		out[#out + 1] = "o " .. name
		local P, N, U, C = m.P, m.N, m.U, m.C
		for i = 1, m.nv do
			local r, g, b = 1, 1, 1
			if C and C[i * 3] then
				r, g, b = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
			end
			out[#out + 1] = string.format("v %.5f %.5f %.5f %.4f %.4f %.4f", (P[i * 3 - 2] + ox) * sx, (P[i * 3 - 1] + oy) * sy, (P[i * 3] + oz) * sz, r, g, b)
		end
		for i = 1, m.nv do
			out[#out + 1] = string.format("vt %.5f %.5f", U and U[i * 2 - 1] or 0, 1 - (U and U[i * 2] or 0))
		end
		for i = 1, m.nv do
			out[#out + 1] = string.format("vn %.4f %.4f %.4f", N[i * 3 - 2] or 0, N[i * 3 - 1] or 0, N[i * 3] or 1)
		end
		local T = m.T
		for t = 1, m.nt do
			local a, b, c = T[t * 3 - 2] + base, T[t * 3 - 1] + base, T[t * 3] + base
			out[#out + 1] = string.format("f %d/%d/%d %d/%d/%d %d/%d/%d", a, a, a, b, b, b, c, c, c)
		end
		base += m.nv
	end
	return table.concat(out, "\n") .. "\n"
end

local function sortedNames(pieces)
	local names = {}
	for n in pairs(pieces) do
		names[#names + 1] = n
	end
	table.sort(names)
	return names
end

------------------------------------------------------------------------
-- reference set
------------------------------------------------------------------------
local counts = {}
if not args.ref_skip and not args["no-ref"] then
	Host.MkDir(REF)
	for _, g in ipairs({ 1, 2 }) do
		local tag = g == 2 and "f" or "m"
		local look = H.Look({ g = g })
		local head = Head.Generate(look, "full", H.Ctx("Head", "full"))
		local P = Skull.Params(look)
		local inv = { 1 / P.kx, 1 / P.ky, 1 / P.kz }
		local list = {}
		local nv, nt = 0, 0
		for _, name in ipairs(sortedNames(head.pieces)) do
			local m = head.pieces[name].mesh
			list[#list + 1] = { name, m }
			nv += m.nv
			nt += m.nt
		end
		fs.writeFile(REF .. "/head_" .. tag .. ".obj", objOf(list, inv))
		counts[#counts + 1] = string.format("head_%s.obj: %d pieces, %d verts, %d tris", tag, #list, nv, nt)
		-- neck + upper torso (AnatomyBody, UpperTorso part space -> head space: minus (c1 - c0) offset, rotations
		-- ignored as Kit.Scalp does), nominal
		local okB, body = pcall(Body.Generate, look, "full", H.Ctx("Body", "full"))
		if okB and body.pieces.UpperTorso then
			local c0, c1 = look.rig.joints.Neck.c0, look.rig.joints.Neck.c1
			local off = { c1[1] - c0[1], c1[2] - c0[2], c1[3] - c0[3] }
			local tl = { { "UpperTorso", body.pieces.UpperTorso.mesh, offset = off } }
			fs.writeFile(REF .. "/torso_" .. tag .. ".obj", objOf(tl, inv))
			counts[#counts + 1] = string.format("torso_%s.obj: %d verts, %d tris", tag, body.pieces.UpperTorso.mesh.nv, body.pieces.UpperTorso.mesh.nt)
		else
			counts[#counts + 1] = "torso_" .. tag .. ".obj: SKIPPED (" .. tostring(body) .. ")"
		end
		local t0 = os.clock()
		local ref = skullRef(g, head)
		Host.WriteJSON(REF .. (g == 2 and "/skull_f.json" or "/skull.json"), ref)
		counts[#counts + 1] = string.format("%s: radial %dx%d, hairlines %d, %.1fs", g == 2 and "skull_f.json" or "skull.json", #ref.radial.thetas, #ref.radial.azimuths, #HAIRLINES, os.clock() - t0)
	end
end

------------------------------------------------------------------------
-- "before" previews: the current generated hair + head per look
------------------------------------------------------------------------
local HC = Looks.HairColors -- 1 black, 2 dark brown, 3 brown, 4 light brown, 5 dark blonde, 6 blonde
Host.LOOKS = {
	{ id = "buzz_k", g = 1, hair = { style = "Buzz Cut", type = "Kinky", color = 1 } },
	{ id = "lowfade_k", g = 1, hair = { style = "Low Fade", type = "Kinky", color = 1 } },
	{ id = "midfade_s", g = 1, hair = { style = "Mid Fade", type = "Straight", color = 2 } },
	{ id = "highfade_k", g = 1, hair = { style = "High Fade", type = "Kinky", color = 1 } },
	{ id = "taper_c", g = 1, hair = { style = "Taper Fade", type = "Coiled", color = 1 } },
	{ id = "burst_cu", g = 1, hair = { style = "Burst Fade", type = "Curly", color = 1 } },
	{ id = "waves_k", g = 1, hair = { style = "360 Waves", type = "Kinky", color = 1 } },
	{ id = "afro_k", g = 1, hair = { style = "Afro", type = "Kinky", color = 1 } },
	{ id = "afro_c_f", g = 2, hair = { style = "Afro", type = "Coiled", color = 1 } },
	{ id = "shortdreads_c", g = 1, hair = { style = "Short Dreads", type = "Coiled", color = 1 } },
	{ id = "dreads_k", g = 1, hair = { style = "Dreadlocks", type = "Kinky", color = 1 } },
	{ id = "twists_k", g = 1, hair = { style = "Twists", type = "Kinky", color = 1 } },
	{ id = "braids_k_f", g = 2, hair = { style = "Braids", type = "Kinky", color = 1 } },
	{ id = "boxbraids_k_f", g = 2, hair = { style = "Box Braids", type = "Kinky", color = 1 } },
	{ id = "cornrows_k", g = 1, hair = { style = "Cornrows", type = "Kinky", color = 1 } },
	{ id = "long_s_f", g = 2, hair = { style = "Long Hair", type = "Straight", color = 3 } },
	{ id = "long_w_m", g = 1, hair = { style = "Long Hair", type = "Wavy", color = 5 } },
}

local PROP_SKIP = { mesh = true, texture = true }
local function pieceOut(name, piece, dir, prefix)
	local m = piece.mesh
	local e = MeshKit.Export(m)
	local o = { p = e.p, n = e.n, uv = e.uv, c = e.c, a = e.a, t = e.t, nv = e.nv, nt = e.nt, landmarks = e.landmarks }
	for k, v in pairs(piece) do
		if not PROP_SKIP[k] then
			o[k] = plain(v)
		end
	end
	o.hairfx = plain(m.hairfx)
	local okT, buf, w, h = pcall(Host.TextureOf, H, piece)
	if okT and buf then
		local file = prefix .. "_" .. name .. ".rgba"
		Host.WriteRGBA(dir .. "/" .. file, buf)
		o.texture = { file = file, w = w, h = h, format = "rgba8, rows top to bottom, straight alpha" }
	elseif not okT then
		o.texture = { error = tostring(buf) }
	end
	return o
end

if not args["no-before"] then
	Host.MkDir(BEFORE)
	local only
	if args.only then
		only = {}
		for id in args.only:gmatch("[^,]+") do
			only[id] = true
		end
	end
	local index = { about = "current generated hair (AnatomyHair, full LOD) + head (AnatomyHead, full) per look, REAL Head part space (studs)", looks = {} }
	for _, L in ipairs(Host.LOOKS) do
		if not only or only[L.id] then
			local t0 = os.clock()
			local look = H.Look({ g = L.g, hair = L.hair })
			local hair = Hair.Generate(look, "full", H.Ctx("Hair", "full"))
			local head = Head.Generate(look, "full", H.Ctx("Head", "full"))
			local out = { id = L.id, look = look, pieces = {}, head = {}, landmarks = { hair = plain(hair.landmarks), head = plain(head.landmarks) } }
			local hv, ht = 0, 0
			for _, name in ipairs(sortedNames(hair.pieces)) do
				local p = hair.pieces[name]
				out.pieces[name] = pieceOut(name, p, BEFORE, L.id)
				hv += p.mesh.nv
				ht += p.mesh.nt
			end
			for _, name in ipairs(sortedNames(head.pieces)) do
				out.head[name] = pieceOut(name, head.pieces[name], BEFORE, L.id .. "_head")
			end
			Host.WriteJSON(BEFORE .. "/" .. L.id .. ".json", out)
			local np = 0
			for _ in pairs(out.pieces) do
				np += 1
			end
			table.insert(index.looks, { id = L.id, file = L.id .. ".json", style = L.hair.style, type = L.hair.type, g = L.g, look = look,
				hairPieces = np, hairVerts = hv, hairTris = ht })
			counts[#counts + 1] = string.format("before/%s.json: %d hair pieces, %d verts, %d tris (%.2fs)", L.id, np, hv, ht, os.clock() - t0)
		end
	end
	Host.WriteJSON(BEFORE .. "/index.json", index, true)
end

for _, c in ipairs(counts) do
	print(c)
end
print("ref:", REF)
print("before:", BEFORE)
