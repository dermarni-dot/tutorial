-- AnatomyBody: the "Body" section generator (ANATOMY_CONTRACTS.md): organic torso, neck, pelvis, arms and legs
-- as EditableMesh data, one piece per R15 part it replaces (UpperTorso, LowerTorso, Left/Right UpperArm,
-- LowerArm, UpperLeg, LowerLeg), each in its part's local space. Pure and deterministic (MeshKit only).
-- * shape: AnatomyBodyTorso / AnatomyBodyLimbs (rig-sized lofts + anatomical sculpting) driven by every
--   muscle level in look.body.lv, body fat (softness, belly, love handles), definition (separations), the
--   physique knobs (look.body.pv), sex, sliders and a per-boxer variation stream (AnatomyBodyKit)
-- * definition: geometry first (grooves between the bellies), then painted vertex colours: skin tone with
--   regional variation, separation shading scaled by definition, crowns, nipples / navel, veins with
--   vascularity, mottling, baked ambient occlusion
-- * attire: the R15 parts that were clothing in round 1 keep their colour (look.attire.parts): the trunks'
--   seat on LowerTorso, the female sports top on UpperTorso. Officials keep their round-1 clothes (no pieces).
-- * motion hooks (full detail): blend shapes flex (every piece), breathe (UpperTorso, LowerTorso), tense
--   (UpperTorso), all inside each piece's box (the box rule); landmarks NeckBase, ChestCenter, NippleL/R,
--   Navel, ShoulderTopL/R, ArmpitL/R, ElbowL/R, WristL/R, HipL/R, KneeL/R, AnkleL/R
-- * levels of detail full / medium / low inside Config.Anatomy.tris.Body (9000 / 4000 / 1500)
local Shared = script.Parent
local MeshKit = require(Shared:WaitForChild("MeshKit"))
local Kit = require(Shared:WaitForChild("AnatomyBodyKit"))
local Torso = require(Shared:WaitForChild("AnatomyBodyTorso"))
local Limbs = require(Shared:WaitForChild("AnatomyBodyLimbs"))
local okLD, LookData = pcall(function()
	return require(Shared:WaitForChild("LookData"))
end)

local Gen = {}
Gen.Section = "Body"
Gen.LODs = { full = true, medium = true, low = true }
-- the ten R15 torso / limb parts and the Muscles folder (LookData.DEFAULT_REPLACES.Body), and while the meshes
-- draw the trunks, the round-1 trunk blocks (their text patches come back on the mesh through BodyFX)
local BODY_RULES = {
	{ r15 = "UpperTorso" }, { r15 = "LowerTorso" }, { r15 = "LeftUpperArm" }, { r15 = "RightUpperArm" },
	{ r15 = "LeftLowerArm" }, { r15 = "RightLowerArm" }, { r15 = "LeftUpperLeg" }, { r15 = "RightUpperLeg" },
	{ r15 = "LeftLowerLeg" }, { r15 = "RightLowerLeg" }, { folder = "Muscles" },
}
Gen.TRUNK_PARTS = { "Waistband", "WaistText", "TrunkShell", "TrunkLeg", "Hem", "SidePanel", "TrunkStripe", "SideStripe", "SponsorPatch" }
function Gen.Replaces(look, lod)
	local rules = table.clone(BODY_RULES)
	if Gen.DrawsTrunks(look) then
		-- guis = true: their SurfaceGuis (waistband text, sponsor patch) hide with them (AnatomyClient)
		rules[#rules + 1] = { folder = "Attire", names = Gen.TRUNK_PARTS, guis = true }
	end
	-- the round-1 rib bruises are ellipsoids sized for the block torso: BodyFX paints them on the mesh instead
	rules[#rules + 1] = { folder = "Damage", names = { "RibBruise" } }
	return rules
end

local abs, min, max, sqrt, floor = math.abs, math.min, math.max, math.sqrt, math.floor
local clamp, smooth, lerp, bell = Kit.clamp, Kit.smooth, Kit.lerp, Kit.bell

local SIDES = { "Right", "Left" }
local LIMBS = { "UpperArm", "LowerArm", "UpperLeg", "LowerLeg" }

local function bodyPaths()
	return okLD and type(LookData) == "table" and LookData.SECTIONS and LookData.SECTIONS.Body or nil
end

------------------------------------------------------------------------
-- Painting
------------------------------------------------------------------------
-- multiply-tint toward a colour in sRGB (k = 0..1)
local function mixInto(C, i, r, g, b, k)
	if k <= 0 then
		return
	end
	local i3 = i * 3
	C[i3 - 2] += (r - C[i3 - 2]) * k
	C[i3 - 1] += (g - C[i3 - 1]) * k
	C[i3] += (b - C[i3]) * k
end

-- the colour every skin vertex starts from, with the darker / redder joints and the warmer tanned tops
local function skinBase(look)
	local r, g, b = Kit.Skin(look)
	local lum = 0.299 * r + 0.587 * g + 0.114 * b
	return r, g, b, lum
end

-- separation shading: grooves darken toward the skin's own shadow hue, crowns lift a little
local function shade(m, ch, P, lum, kG, kC, from, to)
	local C = m.C
	local def = P.defE
	local gk = kG * (0.3 + 0.7 * def) * (lum < 0.35 and 0.85 or 1)
	local kMax = lum > 0.6 and 0.36 or 0.45
	local ck = kC * (0.2 + 0.8 * def)
	for i = from or 1, to or m.nv do
		local g = ch.groove[i] or 0
		local c = ch.crown[i] or 0
		local i3 = i * 3
		if g > 0 then
			-- toward the skin's own shadow (a slight warm lean), never red lines, never grey; fair skin shows
			-- every line, so it gets a little less
			local k = min(kMax, g * gk)
			C[i3 - 2] = C[i3 - 2] * (1 - k * 0.3)
			C[i3 - 1] = C[i3 - 1] * (1 - k * 0.33)
			C[i3] = C[i3] * (1 - k * 0.34)
		end
		if c > 0 then
			local k = min(0.25, c * ck)
			C[i3 - 2] += (1 - C[i3 - 2]) * k * 0.55
			C[i3 - 1] += (1 - C[i3 - 1]) * k * 0.5
			C[i3] += (1 - C[i3]) * k * 0.45
		end
	end
end

-- a soft spot (nipple, navel) painted in body space
local function spot(m, cx, cy, cz, rad, r, g, b, k, from, to)
	local P, C = m.P, m.C
	for i = from or 1, to or m.nv do
		local i3 = i * 3
		local dx, dy, dz = P[i3 - 2] - cx, P[i3 - 1] - cy, P[i3] - cz
		local d2 = (dx * dx + dy * dy + dz * dz) / (rad * rad)
		if d2 < 1 then
			local w = (1 - d2) * (1 - d2)
			C[i3 - 2] += (r - C[i3 - 2]) * w * k
			C[i3 - 1] += (g - C[i3 - 1]) * w * k
			C[i3] += (b - C[i3]) * w * k
		end
	end
end

-- mottling, then ambient occlusion from the loft grid's own cavity (no welded-topology pass)
local function finishSkin(m, P, look, seed, aoOpts, loft)
	MeshKit.NoiseColor(m, 0.028, 2.6, seed)
	MeshKit.NoiseColor(m, 0.012, 9, seed + 7)
	local o = table.clone(aoOpts)
	if loft then
		o.cavityValues = Kit.GridCavity(m, loft.first, loft.rings, loft.stride, loft.sides)
	end
	MeshKit.BakeAO(m, o)
end

------------------------------------------------------------------------
-- Blend shapes (box rule: every delta stays inside the generated box; box-face vertices never move along
-- that axis). deltas = per vertex { dx, dy, dz } in the piece's final space.
------------------------------------------------------------------------
local function addMorph(m, name, ids, dxs, dys, dzs)
	local P = m.P
	local x0, y0, z0, x1, y1, z1 = MeshKit.Bounds(m)
	local ex = 1e-6 + 1e-6 * max(x1 - x0, y1 - y0, z1 - z0)
	local pad = ex * 4
	local n = 0
	for k, i in ipairs(ids) do
		local px, py, pz = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		local dx, dy, dz = dxs[k], dys[k], dzs[k]
		if px <= x0 + pad or px >= x1 - pad then
			dx = 0
		else
			dx = clamp(px + dx, x0 + pad, x1 - pad) - px
		end
		if py <= y0 + pad or py >= y1 - pad then
			dy = 0
		else
			dy = clamp(py + dy, y0 + pad, y1 - pad) - py
		end
		if pz <= z0 + pad or pz >= z1 - pad then
			dz = 0
		else
			dz = clamp(pz + dz, z0 + pad, z1 - pad) - pz
		end
		if abs(dx) + abs(dy) + abs(dz) > 2e-4 then
			MeshKit.AddMorph(m, name, i, dx, dy, dz)
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------------
-- Landmarks (analytic: the same numbers Generate writes and Gen.Landmarks returns)
------------------------------------------------------------------------
local function torsoSurface(sk, P, prof, x, u, field)
	local xS, hz, H, yW = sk.xS, sk.hz, sk.H, sk.yW
	local W, F, n = prof.W(u) * xS, prof.F(u) * hz, prof.nF(u)
	local fx = clamp(abs(x) / W, 0, 0.999)
	local f = F * (1 - fx ^ n) ^ (1 / n)
	local y = yW + u * H
	local z = prof.zc(u) - f
	local d = field and field(0, x, y, z, 0, 0, -1) or 0
	return { x, y, z - d }
end

local function limbPoint(sk, P, side, kind, bb, ang)
	local piv = sk.piv
	local a, b
	if kind == "UpperArm" then
		a, b = piv[side .. "Shoulder"], piv[side .. "Elbow"]
	elseif kind == "LowerArm" then
		a, b = piv[side .. "Elbow"], piv[side .. "Wrist"]
	elseif kind == "UpperLeg" then
		a, b = piv[side .. "Hip"], piv[side .. "Knee"]
	else
		a, b = piv[side .. "Knee"], piv[side .. "Ankle"]
	end
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local L = max(1e-3, sqrt(dx * dx + dy * dy + dz * dz))
	local ux, uy, uz = dx / L, dy / L, dz / L
	local sg = side == "Right" and 1 or -1
	-- frame at the start (Frames' convention: side = the lateral hint projected, front = -Z side)
	local sx, sy, sz = sg - (sg * ux) * ux, -(sg * ux) * uy, -(sg * ux) * uz
	local sl = sqrt(sx * sx + sy * sy + sz * sz)
	sx, sy, sz = sx / sl, sy / sl, sz / sl
	local fx, fy, fz = uy * sz - uz * sy, uz * sx - ux * sz, ux * sy - uy * sx
	if fz > 0 then
		fx, fy, fz = -fx, -fy, -fz
	end
	local box = sk.size[side .. kind]
	local spec = Limbs.Specs[kind](sk, P, side, box[1])
	local S = spec.scale
	local ex, ez = spec.rx(bb) * S, spec.rz(bb) * S
	local c, s = math.cos(ang), math.sin(ang)
	local r = 1 / sqrt((c / ex) ^ 2 + (s / ez) ^ 2)
	for _, mm in ipairs(spec.mus) do
		r += Limbs.belly(bb, ang, mm) * S
	end
	for _, gg in ipairs(spec.grooves) do
		r -= Limbs.belly(bb, ang, gg) * S
	end
	local px, py, pz = a[1] + ux * L * bb, a[2] + uy * L * bb, a[3] + uz * L * bb
	return { px + (sx * c + fx * s) * r, py + (sy * c + fy * s) * r, pz + (sz * c + fz * s) * r }
end

-- body-space landmarks { name = { part, pos } }
local function landmarksBody(sk, P, prof, field, trunk)
	local out = {}
	local function put(name, part, p)
		out[name] = { part = part, pos = p }
	end
	local zc1 = prof.zc(1.0)
	put("NeckBase", "UpperTorso", { 0, sk.yN, zc1 })
	put("ChestCenter", "UpperTorso", torsoSurface(sk, P, prof, 0, 0.64, field))
	put("Navel", "UpperTorso", torsoSurface(sk, P, prof, 0, 0.035, nil))
	for _, side in ipairs(SIDES) do
		local sg = side == "Right" and 1 or -1
		local L = side == "Right" and "R" or "L"
		local nip = torsoSurface(sk, P, prof, sg * (0.47 + P.V.nipple[1]) * sk.xS, 0.56 + P.V.nipple[2] - 0.03 * P.lv.pecs, field)
		put("Nipple" .. L, "UpperTorso", nip)
		local W = prof.W(0.74) * sk.xS
		put("Armpit" .. L, "UpperTorso", { sg * W * 0.97, sk.yW + 0.74 * sk.H, 0.0 })
		put("ShoulderTop" .. L, side .. "UpperArm", limbPoint(sk, P, side, "UpperArm", 0.04, 0.35))
		put("Elbow" .. L, side .. "UpperArm", limbPoint(sk, P, side, "UpperArm", 1.0, 3 * math.pi / 2))
		local w = sk.piv[side .. "Wrist"]
		put("Wrist" .. L, side .. "LowerArm", { w[1], w[2], w[3] })
		local h = sk.piv[side .. "Hip"]
		put("Hip" .. L, "LowerTorso", { h[1], h[2], h[3] })
		put("Knee" .. L, side .. "UpperLeg", limbPoint(sk, P, side, "UpperLeg", 1.0, math.pi / 2))
		local an = sk.piv[side .. "Ankle"]
		put("Ankle" .. L, side .. "LowerLeg", { an[1], an[2], an[3] })
	end
	if trunk then
		-- where the trunks' lettering goes (BodyFX re-creates the waistband text and the sponsor patch on the
		-- mesh): the waistband's front (centre, top edge, a point half way to the side) and the front of the
		-- right trunk leg (centre and a point 0.5 rad toward the outside)
		local c, topE, edge = Torso.BandFront(sk, P, prof)
		put("WaistFront", "LowerTorso", c)
		put("WaistBandTop", "LowerTorso", topE)
		put("WaistFrontEdge", "LowerTorso", edge)
		local o = { trunk = { hemB = trunk.hemB } }
		local pb = math.min(0.41, trunk.hemB - 0.2)
		put("TrunkPatchR", "RightUpperLeg", Limbs.SurfacePoint(sk, P, "Right", "UpperLeg", o, pb, math.pi / 2))
		put("TrunkPatchREdge", "RightUpperLeg", Limbs.SurfacePoint(sk, P, "Right", "UpperLeg", o, pb, math.pi / 2 - 0.5))
	end
	return out
end

-- to part space (bind pose: a part's frame is a translation of the UpperTorso's)
local function toPart(sk, lm)
	local out = {}
	for name, e in pairs(lm) do
		local c = sk.center[e.part] or { 0, 0, 0 }
		out[name] = { part = e.part, pos = { e.pos[1] - c[1], e.pos[2] - c[2], e.pos[3] - c[3] } }
	end
	return out
end

------------------------------------------------------------------------
-- Generate
------------------------------------------------------------------------
local function isOfficial(look)
	local a = type(look.attire) == "table" and look.attire or {}
	return a.outfit == "referee" or a.outfit == "cornerman"
end

local function clothOf(look, part)
	local a = type(look.attire) == "table" and look.attire or {}
	local parts = type(a.parts) == "table" and a.parts or {}
	return Kit.Rgb(parts[part])
end

-- a boxer's LowerTorso was the trunks in round 1: the meshes draw the whole trunks (seat, band, legs)
function Gen.DrawsTrunks(look)
	return type(look) == "table" and not isOfficial(look) and clothOf(look, "LowerTorso") ~= nil
end

-- the trunks' look: colour, trim, style, where the legs end
local function trunkSpec(look)
	local a = type(look.attire) == "table" and look.attire or {}
	local r, g, b = clothOf(look, "LowerTorso")
	local tr, tg, tb = Kit.Rgb(a.trim)
	if not tr then
		tr, tg, tb = 0.94, 0.94, 0.94
	end
	local style = type(a.trunkStyle) == "string" and a.trunkStyle or "Classic"
	return { r = r, g = g, b = b, tr = tr, tg = tg, tb = tb, style = style, hemB = style == "Long" and 1.0 or 0.52 }
end

function Gen.Generate(look, lod, ctx)
	if type(look) ~= "table" then
		return { pieces = {} }
	end
	if isOfficial(look) then
		-- shirt and trousers stay the round-1 parts (with their collar, tie, belt); nothing hidden
		return { pieces = {} }
	end
	lod = (lod == "medium" or lod == "low") and lod or "full"
	local full = lod == "full"
	local sk = Kit.Skeleton(look)
	local P = Kit.Params(look, MeshKit, bodyPaths())
	local sr, sg, sb, lum = skinBase(look)
	local seed = (P.V.veinSeed or 1) % 100000
	local def = P.defE
	-- occlusion: a warm shadow hue on every tone, less saturated (and a little lighter) on fair skin, where a
	-- saturated crease reads as a drawn red line
	local fair = lum > 0.6
	local ao = {
		cavity = (0.32 + 0.3 * def) * (fair and 0.8 or 1), ridge = 0.05 + 0.06 * def, down = 0.13 + 0.05 * def,
		tint = lum < 0.3 and { 0.44, 0.33, 0.3 } or (fair and { 0.4, 0.33, 0.3 } or { 0.42, 0.3, 0.26 }),
	}
	local pieces = {}
	local morphCount = 0

	-- UpperTorso ----------------------------------------------------------------
	local trunk = Gen.DrawsTrunks(look) and trunkSpec(look) or nil
	local ut, ui = Torso.Upper(sk, P, lod, { trunks = trunk ~= nil })
	local prof = ui.prof
	local baseN = nil
	MeshKit.Fill(ut, sr, sg, sb)
	do
		local C, Pp = ut.C, ut.P
		local yW, H, xS = sk.yW, sk.H, sk.xS
		for i = 1, ut.nv do
			local x, y, z = Pp[i * 3 - 2], Pp[i * 3 - 1], Pp[i * 3]
			local u = (y - yW) / H
			-- shoulders / upper back a touch darker and warmer, the neck a little redder
			local top = smooth(0.7, 1.0, u) * (0.6 + 0.4 * smooth(-0.2, 0.4, z))
			mixInto(C, i, sr * 0.93, sg * 0.88, sb * 0.86, 0.25 * top)
			-- armpits
			local ap = bell(((abs(x) / xS) - 0.9) / 0.14) * bell((u - 0.74) / 0.1)
			mixInto(C, i, sr * 0.8, sg * 0.74, sb * 0.72, 0.35 * ap)
		end
	end
	shade(ut, ui.ch, P, lum, 0.75, 0.22)
	if not P.female then
		-- nipples and areolas: darker, a little redder (less contrast on dark skin)
		local ak = (lum > 0.5 and 0.55 or 0.4) * (lod == "low" and 0.35 or (lod == "medium" and 0.7 or 1))
		for _, s in ipairs({ 1, -1 }) do
			local field = Torso.Field(sk, P, prof, 1)
			local p = torsoSurface(sk, P, prof, s * (0.47 + P.V.nipple[1]) * sk.xS, 0.56 + P.V.nipple[2] - 0.03 * P.lv.pecs, field)
			spot(ut, p[1], p[2], p[3], 0.055 * sk.xS, sr * 0.68, sg * 0.5, sb * 0.46, ak)
			spot(ut, p[1], p[2], p[3], 0.022 * sk.xS, sr * 0.6, sg * 0.42, sb * 0.4, 0.5)
		end
	end
	do
		local nav = torsoSurface(sk, P, prof, 0, 0.035, nil)
		spot(ut, nav[1], nav[2], nav[3] - 0.01, 0.045, sr * 0.45, sg * 0.32, sb * 0.28, lod == "low" and 0.3 or 0.85)
	end
	-- skin mottling first (cloth never gets it), then the female sports top over the chest (the R15 UpperTorso
	-- was the top in round 1), then the occlusion over both
	MeshKit.NoiseColor(ut, 0.028, 2.6, seed)
	MeshKit.NoiseColor(ut, 0.012, 9, seed + 7)
	local topR, topG, topB = clothOf(look, "UpperTorso")
	if topR then
		local Pp, C = ut.P, ut.C
		local yW, H, xS = sk.yW, sk.H, sk.xS
		for i = 1, ut.nv do
			local x, y, z = Pp[i * 3 - 2], Pp[i * 3 - 1], Pp[i * 3]
			local u = (y - yW) / H
			local fx = abs(x) / xS
			local band = smooth(0.34, 0.41, u) -- the band under the bust
			-- scoop neckline in front, racer back behind, wide straps over the shoulders
			local neckline
			if z < 0 then
				neckline = 1 - smooth(0.78, 0.88, u + 0.1 * (1 - smooth(0.0, 0.45, fx)))
			else
				neckline = 1 - smooth(0.86, 0.95, u)
			end
			local strap = smooth(0.8, 0.88, u) * bell((fx - 0.52) / 0.2)
			local armhole = 1 - smooth(0.76, 0.88, fx) * smooth(0.58, 0.74, u)
			local w = clamp(band * max(neckline * armhole, strap), 0, 1)
			if w > 0 then
				-- the fabric: the colour with a faint knit variation, a darker hem where it ends
				local edge = 1 - abs(w - 0.5) * 2
				local k = 1 - 0.12 * edge
				mixInto(C, i, topR * k, topG * k, topB * k, w)
			end
		end
	end
	local aoT = table.clone(ao)
	aoT.cavityValues = Kit.GridCavity(ut, ui.loft.first, ui.loft.rings, ui.loft.stride, ui.loft.sides)
	MeshKit.BakeAO(ut, aoT)
	-- blend shapes (full detail): flex / breathe / tense along the sculpting normals
	local utMorph
	if full then
		local ch = ui.ch
		local N = ut.N
		local ids, fx, fy, fz = {}, {}, {}, {}
		local bids, bx, by, bz = {}, {}, {}, {}
		local tids, tx, ty, tz = {}, {}, {}, {}
		-- nothing swells right above the waistband (the band does not move: a pushed-out belly would overhang it)
		local tuck = trunk and Torso.BAND_TOP / sk.H or nil
		local UP = ut.P
		for i = 1, ut.nv do
			local nx, ny, nz = N[i * 3 - 2], N[i * 3 - 1], N[i * 3]
			local fade = tuck and smooth(tuck + 0.01, tuck + 0.12, (UP[i * 3 - 1] - sk.yW) / sk.H) or 1
			local f = (ch.pec[i] * 0.2 + ch.lat[i] * 0.2 + ch.trap[i] * 0.16 + ch.abs[i] * 0.3 + ch.obl[i] * 0.12) * fade
			if f > 1e-4 then
				ids[#ids + 1] = i
				fx[#ids], fy[#ids], fz[#ids] = nx * f, ny * f, nz * f
			end
			local rib = ch.rib[i]
			if rib > 0.02 then
				local k = 0.02 * rib * sk.hz / 0.5
				bids[#bids + 1] = i
				bx[#bids], by[#bids], bz[#bids] = nx * k, ny * k + 0.012 * rib, nz * k
			end
			local t = (ch.abs[i] * 0.35 + ch.obl[i] * 0.2) * fade
			if t > 1e-4 then
				tids[#tids + 1] = i
				tx[#tids], ty[#tids], tz[#tids] = nx * t, ny * t, nz * t
			end
		end
		utMorph = { flex = { ids, fx, fy, fz }, breathe = { bids, bx, by, bz }, tense = { tids, tx, ty, tz } }
	end
	-- landmarks (body space; translated with the mesh)
	local field = Torso.Field(sk, P, prof, 1)
	local lmBody = landmarksBody(sk, P, prof, field, trunk)
	for name, e in pairs(lmBody) do
		if e.part == "UpperTorso" then
			MeshKit.SetLandmark(ut, name, e.pos[1], e.pos[2], e.pos[3])
		end
	end
	pieces.UpperTorso = { mesh = ut, material = "SmoothPlastic" }

	-- LowerTorso (the trunks' seat) ----------------------------------------------------------
	local lt, li = Torso.Lower(sk, P, lod, prof, { trunks = trunk ~= nil })
	if trunk then
		MeshKit.Fill(lt, trunk.r, trunk.g, trunk.b)
		local C, Pp = lt.C, lt.P
		local bandY = li.bandBot
		for i = 1, lt.nv do
			local y = Pp[i * 3 - 1]
			if y >= bandY - 0.002 then
				-- the elastic waistband in the trim colour, a faint knit line along its middle
				local mid = bell((y - (bandY + li.top) / 2) / 0.02) * 0.06
				mixInto(C, i, trunk.tr * (1 - mid), trunk.tg * (1 - mid), trunk.tb * (1 - mid), 1)
			end
		end
		-- satin: the folds and the seat seam catch a little shading
		MeshKit.NoiseColor(lt, 0.012, 3, seed + 3)
		MeshKit.BakeAO(lt, { cavity = 0.25, down = 0.16, tint = { 0.4, 0.38, 0.38 }, cavityValues = Kit.GridCavity(lt, li.loft.first, li.loft.rings, li.loft.stride, li.loft.sides) })
	else
		MeshKit.Fill(lt, sr, sg, sb)
		shade(lt, { groove = {}, crown = li.crown }, P, lum, 0.6, 0.2)
		finishSkin(lt, P, look, seed + 1, ao, li.loft)
	end
	local trunks = trunk ~= nil
	local ltMorph
	if full then
		local N = lt.N
		local ids, dx, dy, dz = {}, {}, {}, {}
		local bids, bx, by, bz = {}, {}, {}, {}
		local Pp = lt.P
		for i = 1, lt.nv do
			local g = li.glute[i] * 0.12
			if g > 1e-4 then
				ids[#ids + 1] = i
				dx[#ids], dy[#ids], dz[#ids] = N[i * 3 - 2] * g, N[i * 3 - 1] * g, N[i * 3] * g
			end
			local nz = N[i * 3]
			local y = Pp[i * 3 - 1]
			local b = smooth(0.1, 0.6, -nz) * bell((y - (sk.yW - 0.12)) / 0.22) * 0.012
			if b > 1e-4 then
				bids[#bids + 1] = i
				bx[#bids], by[#bids], bz[#bids] = N[i * 3 - 2] * b, N[i * 3 - 1] * b, nz * b
			end
		end
		ltMorph = { flex = { ids, dx, dy, dz }, breathe = { bids, bx, by, bz } }
	end
	for name, e in pairs(lmBody) do
		if e.part == "LowerTorso" then
			MeshKit.SetLandmark(lt, name, e.pos[1], e.pos[2], e.pos[3])
		end
	end
	pieces.LowerTorso = { mesh = lt, material = "SmoothPlastic", reflectance = trunks and 0.03 or 0 }

	-- limbs ----------------------------------------------------------------
	local limbMorph = {}
	for _, side in ipairs(SIDES) do
		for _, kind in ipairs(LIMBS) do
			local name = side .. kind
			local lopt = {}
			if trunk and kind == "UpperLeg" then
				lopt.trunk = { hemB = trunk.hemB }
			elseif trunk and kind == "LowerLeg" and trunk.style == "Long" then
				lopt.cuff = { hemB = 0.2 }
			end
			if full and not clothOf(look, name) then
				-- the boot shaft hides the lower half of the shin (shoes are not a Body input: assume tall boots)
				lopt.veins = Limbs.VeinPaths(P, kind, side, sk.size[name][1], 0.45)
			end
			local m, info = Limbs.Build(sk, P, lod, side, kind, lopt)
			if info.hemB then
				-- cloth: no skin shading, no muscle flex under the satin
				for i = 1, m.nv do
					if info.B[i] > -0.5 and info.B[i] <= info.hemB + 1e-6 then
						info.crown[i], info.groove[i], info.flex[i] = 0, 0, 0
					end
				end
			end
			local cr, cg, cb = clothOf(look, name)
			if cr then
				MeshKit.Fill(m, cr, cg, cb)
				MeshKit.BakeAO(m, { cavity = 0.25, down = 0.14, cavityValues = Kit.GridCavity(m, info.first, info.rings, info.stride, info.sides) })
			else
				MeshKit.Fill(m, sr, sg, sb)
				local C = m.C
				local B, A = info.B, info.A
				local isArm = kind == "UpperArm" or kind == "LowerArm"
				for i = 1, m.nv do
					local bb = B[i]
					if bb >= -0.5 then
						local a = A[i]
						-- elbows / knees: rougher, darker, redder skin
						local joint = 0
						if kind == "UpperArm" then
							joint = bell((bb - 1.0) / 0.14) * (0.5 + 0.5 * Limbs.belly(1, a, { a = 3 * math.pi / 2, w = 1.6, b0 = 0, bp = 1, b1 = 2, h = 1 }))
						elseif kind == "LowerArm" then
							joint = bell((bb - 0.0) / 0.14) * (0.5 + 0.5 * Limbs.belly(1, a, { a = 3 * math.pi / 2, w = 1.6, b0 = 0, bp = 1, b1 = 2, h = 1 }))
						elseif kind == "UpperLeg" then
							joint = bell((bb - 1.0) / 0.12) * (0.4 + 0.6 * Limbs.belly(1, a, { a = math.pi / 2, w = 1.4, b0 = 0, bp = 1, b1 = 2, h = 1 }))
						else
							joint = bell((bb - 0.0) / 0.12) * (0.4 + 0.6 * Limbs.belly(1, a, { a = math.pi / 2, w = 1.4, b0 = 0, bp = 1, b1 = 2, h = 1 }))
						end
						mixInto(C, i, sr * 0.9, sg * 0.76, sb * 0.72, 0.4 * joint)
						-- outer arms / shins a touch darker than the inner sides (sun, hair)
						local outer = 0.5 + 0.5 * math.cos(a)
						mixInto(C, i, sr * 0.94, sg * 0.9, sb * 0.88, (isArm and 0.18 or 0.12) * outer)
					end
				end
				shade(m, info, P, lum, isArm and 0.7 or 0.6, 0.22)
				-- veins: the skin's colour, a touch cooler and darker (blue-green under fair skin)
				for _, i in ipairs(m.groups.vein or {}) do
					mixInto(C, i, sr * 0.94, sg * 0.94, sb * 0.99, 0.6)
				end
				MeshKit.NoiseColor(m, 0.028, 2.6, seed + #name)
				MeshKit.NoiseColor(m, 0.012, 9, seed + #name + 7)
				if info.hemB then
					-- the trunk leg: trunk colour to the hem, the style's trim (stripe / panel / hem band)
					local hb = info.hemB
					for i = 1, m.nv do
						local bb = B[i]
						local cloth = bb > -0.5 and bb <= hb + 1e-6
						-- the cap past the hip (B = -1) is inside the seat: trunk coloured as well
						if bb == -1 and kind == "UpperLeg" then
							-- the domes past the pivots: the hip one is inside the seat, the knee one is cloth only
							-- under long trunks
							local y = m.P[i * 3 - 1]
							cloth = hb >= 0.97 or y > sk.piv[side .. "Knee"][2]
						end
						if cloth then
							local a = A[i]
							local cr2, cg2, cb2 = trunk.r, trunk.g, trunk.b
							local st = trunk.style
							local lat = abs(MeshKit.WrapAngle(a))
							if kind == "LowerLeg" or bb == -1 then
								-- the long trunks' cuff, and the domes past the pivots (inside the seat): plain
								-- the long trunks' cuff
							elseif st == "Striped" and lat < 0.2 then
								cr2, cg2, cb2 = trunk.tr, trunk.tg, trunk.tb
							elseif st == "Pro" then
								if bb > hb - 0.07 or lat < 0.48 then
									cr2, cg2, cb2 = trunk.tr, trunk.tg, trunk.tb
								end
								if lat < 0.13 and bb <= hb - 0.07 then
									cr2, cg2, cb2 = 0.95, 0.95, 0.95
								end
							end
							mixInto(C, i, cr2, cg2, cb2, 1)
						end
					end
					local o = table.clone(ao)
					o.cavity, o.ridge = 0.3, 0.04
					o.cavityValues = Kit.GridCavity(m, info.first, info.rings, info.stride, info.sides)
					MeshKit.BakeAO(m, o)
				else
					local o = table.clone(ao)
					o.cavityValues = Kit.GridCavity(m, info.first, info.rings, info.stride, info.sides)
					MeshKit.BakeAO(m, o)
				end
			end
			if full then
				local ids, dx, dy, dz = {}, {}, {}, {}
				local fl, D = info.flex, info.dir
				for i = 1, m.nv do
					local f = fl[i]
					if f > 1e-4 then
						ids[#ids + 1] = i
						dx[#ids], dy[#ids], dz[#ids] = D[i * 3 - 2] * f, D[i * 3 - 1] * f, D[i * 3] * f
					end
				end
				limbMorph[name] = { flex = { ids, dx, dy, dz } }
			end
			for lname, e in pairs(lmBody) do
				if e.part == name then
					MeshKit.SetLandmark(m, lname, e.pos[1], e.pos[2], e.pos[3])
				end
			end
			pieces[name] = { mesh = m, material = "SmoothPlastic", reflectance = 0 }
		end
	end

	-- body space -> each part's space, then the blend shapes (bounds are final only now)
	for name, piece in pairs(pieces) do
		local c = sk.center[name] or { 0, 0, 0 }
		MeshKit.Transform(piece.mesh, MeshKit.MatTranslate(-c[1], -c[2], -c[3]))
	end
	if full then
		local function apply(name, set)
			for mname, e in pairs(set or {}) do
				morphCount += addMorph(pieces[name].mesh, mname, e[1], e[2], e[3], e[4])
			end
		end
		apply("UpperTorso", utMorph)
		apply("LowerTorso", ltMorph)
		for name, set in pairs(limbMorph) do
			apply(name, set)
		end
	end
	return { pieces = pieces, landmarks = {} }
end

-- the same landmarks without meshes (server / tools): { name = { part, pos = { x, y, z } } } in part space
function Gen.Landmarks(look)
	if type(look) ~= "table" or isOfficial(look) then
		return {}
	end
	local sk = Kit.Skeleton(look)
	local P = Kit.Params(look, MeshKit, bodyPaths())
	local prof = Torso.Profiles(sk, P)
	local field = Torso.Field(sk, P, prof, 1)
	return toPart(sk, landmarksBody(sk, P, prof, field, Gen.DrawsTrunks(look) and trunkSpec(look) or nil))
end

return Gen
