-- AnatomyBody: the "Body" section generator (ANATOMY_CONTRACTS.md): organic torso, neck, pelvis, arms, legs,
-- hands and feet as EditableMesh data, one piece per R15 part it replaces (UpperTorso, LowerTorso, Left/Right
-- UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot), each in its part's local space. Pure and
-- deterministic (MeshKit only).
-- * shape: AnatomyBodyTorso / AnatomyBodyLimbs / AnatomyBodyGear (rig-sized grid lofts + anatomical
--   sculpting) driven by every muscle level in look.body.lv, body fat (softness, belly, love handles),
--   definition (separations), the physique knobs (look.body.pv), sex, sliders and a per-boxer variation
--   stream (AnatomyBodyKit)
-- * what the boxer wears is part of the body: the satin trunks (seat, waistband, loose legs, the style's
--   trim), the female sports top, boots / trainers (shaft on the shin, the shoe on the foot), gloves (cuff on
--   the forearm, the padded fist on the hand), hand wraps; colours from look.attire (+ look.attire.gear).
--   Officials keep their round-1 clothes (no pieces).
-- * colour: per-vertex paint (every level) and, at full detail, a colour texture per piece made from the
--   same painters evaluated per texel over the piece's (row, column) lattice: crisp muscle separations,
--   crisp garment edges and trims, skin mottling and pores (Kit.GridTexture, made lazily on the client)
-- * motion hooks (full detail): blend shapes flex (every limb and torso piece), breathe (UpperTorso,
--   LowerTorso), tense (UpperTorso), raiseL / raiseR / reachL / reachR (UpperTorso: the shoulder girdle lifts /
--   comes forward when the arm goes up; BodyFX drives them from the shoulder angle), all inside each
--   piece's box (the box rule); landmarks NeckBase, ChestCenter, NippleL/R, Navel, ShoulderTopL/R, ArmpitL/R,
--   ElbowL/R, WristL/R, HipL/R, KneeL/R, AnkleL/R (+ the trunks / glove / boot lettering spots)
-- * levels of detail full / medium / low inside Config.Anatomy.tris.Body (9000 / 4000 / 1500)
local Shared = script.Parent
local MeshKit = require(Shared:WaitForChild("MeshKit"))
local Kit = require(Shared:WaitForChild("AnatomyBodyKit"))
local Torso = require(Shared:WaitForChild("AnatomyBodyTorso"))
local Limbs = require(Shared:WaitForChild("AnatomyBodyLimbs"))
local Gear = require(Shared:WaitForChild("AnatomyBodyGear"))
local okLD, LookData = pcall(function()
	return require(Shared:WaitForChild("LookData"))
end)

local Gen = {}
Gen.Section = "Body"
Gen.LODs = { full = true, medium = true, low = true }
-- colour texture sizes at full detail (none below: at medium / low range vertex colours carry the look)
-- (limbs: 96 texels round x 128 along; the torso 192 x 192: ~0.7 cm a texel, crisp separations and trims)
Gen.TEXTURE = { UpperTorso = 192, LowerTorso = 128, limb = 128, limbW = 96, hand = 128, foot = 128 }

local abs, min, max, sqrt, floor = math.abs, math.min, math.max, math.sqrt, math.floor
local clamp, smooth, lerp, bell = Kit.clamp, Kit.smooth, Kit.lerp, Kit.bell
local pi = math.pi
local TAU = pi * 2

local SIDES = { "Right", "Left" }
local LIMBS = { "UpperArm", "LowerArm", "UpperLeg", "LowerLeg" }

------------------------------------------------------------------------
-- Replace rules: what the meshes take over
------------------------------------------------------------------------
-- the ten R15 torso / limb parts, the hands and feet, the Muscles folder (LookData.DEFAULT_REPLACES.Body);
-- while the meshes draw the trunks the round-1 trunk blocks (their text patches come back on the mesh
-- through BodyFX), the round-1 gloves / wraps (the Hands folder) and shoe / boot parts
local BODY_RULES = {
	{ r15 = "UpperTorso" }, { r15 = "LowerTorso" }, { r15 = "LeftUpperArm" }, { r15 = "RightUpperArm" },
	{ r15 = "LeftLowerArm" }, { r15 = "RightLowerArm" }, { r15 = "LeftUpperLeg" }, { r15 = "RightUpperLeg" },
	{ r15 = "LeftLowerLeg" }, { r15 = "RightLowerLeg" }, { r15 = "LeftHand" }, { r15 = "RightHand" },
	{ r15 = "LeftFoot" }, { r15 = "RightFoot" }, { folder = "Muscles" },
}
Gen.TRUNK_PARTS = { "Waistband", "WaistText", "TrunkShell", "TrunkLeg", "Hem", "SidePanel", "TrunkStripe", "SideStripe", "SponsorPatch" }
Gen.SHOE_PARTS = {
	"Collar", "Sock", "BootShaft", "Eyelets", "Tongue", "Lace", "Laces", "MeshPanel", "AccentStripe", "Wordmark", "HeelMark", "Midsole",
	"Outsole", "ToeBox", "Stripe", "HeelTab", "LaceBar", "Sole", "SoleHeel", "Crease", "Scuff", "SoleSplit", "LaceBow", "LaceTail",
}

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

function Gen.Replaces(look, lod)
	local rules = table.clone(BODY_RULES)
	if Gen.DrawsTrunks(look) then
		-- guis = true: their SurfaceGuis (waistband text, sponsor patch) hide with them (AnatomyClient)
		rules[#rules + 1] = { folder = "Attire", names = Gen.TRUNK_PARTS, guis = true }
	end
	rules[#rules + 1] = { folder = "Attire", names = Gen.SHOE_PARTS, guis = true }
	rules[#rules + 1] = { folder = "Hands", guis = true }
	-- the round-1 rib bruises are ellipsoids sized for the block torso: BodyFX paints them on the mesh instead
	rules[#rules + 1] = { folder = "Damage", names = { "RibBruise" } }
	return rules
end

local function bodyPaths()
	return okLD and type(LookData) == "table" and LookData.SECTIONS and LookData.SECTIONS.Body or nil
end

------------------------------------------------------------------------
-- Paint (shared by the vertex colours and the texture: the same functions, per vertex or per texel)
------------------------------------------------------------------------
local mix, sepShade = Kit.Mix, Kit.SepShade

-- the per-character paint context: skin, separation strengths, occlusion tints, noise tiles (texels)
local function paintContext(look, P, seed)
	local sr, sg, sb = Kit.Skin(look)
	local lum = 0.299 * sr + 0.587 * sg + 0.114 * sb
	local def = P.defE
	local fair = lum > 0.6
	local pc = {
		sr = sr, sg = sg, sb = sb, lum = lum, def = def, seed = seed,
		gk = (0.3 + 0.7 * def) * (lum < 0.35 and 0.85 or 1), kMax = fair and 0.36 or 0.45, ck = 0.2 + 0.8 * def,
		-- occlusion: a warm shadow hue on every tone, less saturated (and a little lighter) on fair skin, where a
		-- saturated crease reads as a drawn red line
		ao = { cavity = (0.32 + 0.3 * def) * (fair and 0.8 or 1), ridge = 0.05 + 0.06 * def, down = 0.13 + 0.05 * def },
		aoTint = lum < 0.3 and { 0.44, 0.33, 0.3 } or (fair and { 0.4, 0.33, 0.3 } or { 0.42, 0.3, 0.26 }),
		clothTint = { 0.4, 0.38, 0.38 },
	}
	return pc
end

-- texel noise: blotchy mottling (a few centimetres), fine mottle, pores (per texel). Tiles are made once per
-- texture build; 'scale' = texels per stud along u / v of that piece
local function texNoise(pc)
	if not pc.tiles then
		pc.tiles = { blot = Kit.NoiseTile(MeshKit, 16, pc.seed + 11), fine = Kit.NoiseTile(MeshKit, 32, pc.seed + 23), pore = Kit.NoiseTile(MeshKit, 64, pc.seed + 37) }
	end
	return pc.tiles
end

local skinGrain = Kit.SkinGrain

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

-- body-space landmarks { name = { part, pos } }
local function landmarksBody(sk, P, prof, field, wear)
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
		put("ShoulderTop" .. L, side .. "UpperArm", Limbs.SurfacePoint(sk, P, side, "UpperArm", nil, 0.04, 0.35))
		put("Elbow" .. L, side .. "UpperArm", Limbs.SurfacePoint(sk, P, side, "UpperArm", nil, 1.0, 3 * pi / 2))
		local w = sk.piv[side .. "Wrist"]
		put("Wrist" .. L, side .. "LowerArm", { w[1], w[2], w[3] })
		local h = sk.piv[side .. "Hip"]
		put("Hip" .. L, "LowerTorso", { h[1], h[2], h[3] })
		put("Knee" .. L, side .. "UpperLeg", Limbs.SurfacePoint(sk, P, side, "UpperLeg", nil, 1.0, pi / 2))
		local an = sk.piv[side .. "Ankle"]
		put("Ankle" .. L, side .. "LowerLeg", { an[1], an[2], an[3] })
	end
	if wear.trunk then
		-- where the trunks' lettering goes (BodyFX re-creates the waistband text and the sponsor patch on the
		-- mesh): the waistband's front (centre, top edge, a point half way to the side) and the front of the
		-- right trunk leg (centre and a point 0.5 rad toward the outside)
		local c, topE, edge = Torso.BandFront(sk, P, prof)
		put("WaistFront", "LowerTorso", c)
		put("WaistBandTop", "LowerTorso", topE)
		put("WaistFrontEdge", "LowerTorso", edge)
		local o = { zones = wear.zones.RightUpperLeg }
		local pb = min(0.3, wear.trunk.hemB - 0.14)
		put("TrunkPatchR", "RightUpperLeg", Limbs.SurfacePoint(sk, P, "Right", "UpperLeg", o, pb, pi / 2))
		put("TrunkPatchREdge", "RightUpperLeg", Limbs.SurfacePoint(sk, P, "Right", "UpperLeg", o, pb, pi / 2 - 0.5))
	end
	Gear.Landmarks(sk, P, wear, put, Limbs)
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
-- What the boxer wears (trunks style, garment zones per limb, gear for the hands and feet)
------------------------------------------------------------------------
local function trunkSpec(look)
	local a = type(look.attire) == "table" and look.attire or {}
	local r, g, b = clothOf(look, "LowerTorso")
	local tr, tg, tb = Kit.Rgb(a.trim)
	if not tr then
		tr, tg, tb = 0.94, 0.94, 0.94
	end
	local style = type(a.trunkStyle) == "string" and a.trunkStyle or "Classic"
	-- short styles end high on the thigh (more leg shows, like real boxing trunks); Long reaches the knee
	return { r = r, g = g, b = b, tr = tr, tg = tg, tb = tb, style = style, hemB = style == "Long" and 1.0 or 0.44 }
end

local function wearOf(look)
	local wear = { gear = Gear.Read(look), zones = {} }
	if Gen.DrawsTrunks(look) then
		wear.trunk = trunkSpec(look)
	end
	local g = wear.gear
	for _, side in ipairs(SIDES) do
		local z = {}
		-- thighs: the satin leg down to the hem
		if wear.trunk then
			if wear.trunk.hemB >= 0.97 then
				z.UpperLeg = { { -1, 2, "trunk" } }
			else
				z.UpperLeg = { { -1, wear.trunk.hemB, "trunk" }, { wear.trunk.hemB, 2, "skin" } }
			end
		end
		-- shins: the long trunks' cuff under the knee, then the boot shaft / sock / trainer collar
		local ll = {}
		local from = -1
		if wear.trunk and wear.trunk.hemB >= 0.97 then
			ll[#ll + 1] = { from, 0.2, "trunkcuff" }
			from = 0.2
		end
		local shaftTop = g.shoe.shaft
		if g.shoe.sock and g.shoe.sock < shaftTop then
			ll[#ll + 1] = { from, g.shoe.sock, "skin" }
			ll[#ll + 1] = { g.shoe.sock, shaftTop, "sock" }
		else
			ll[#ll + 1] = { from, shaftTop, "skin" }
		end
		ll[#ll + 1] = { shaftTop, 2, "boot" }
		z.LowerLeg = ll
		-- forearms: the glove's cuff or the wrap at the wrist
		if g.hands == "gloves" then
			z.LowerArm = { { -1, g.glove.cuffTop, "skin" }, { g.glove.cuffTop, 2, "glove" } }
		elseif g.hands == "wraps" then
			z.LowerArm = { { -1, g.wrap.top, "skin" }, { g.wrap.top, 2, "wrap" } }
		end
		for kind, list in pairs(z) do
			wear.zones[side .. kind] = list
		end
	end
	return wear
end

------------------------------------------------------------------------
-- Piece painters
------------------------------------------------------------------------
-- UpperTorso: skin with regional variation, nipples / navel, separations, the female sports top
local function utPainter(pc, sk, P, prof, look)
	local sr, sg, sb = pc.sr, pc.sg, pc.sb
	local yW, H, xS = sk.yW, sk.H, sk.xS
	local spots = {}
	local field1 = Torso.Field(sk, P, prof, 1)
	if not P.female then
		-- nipples and areolas: darker, a little redder (less contrast on dark skin)
		local ak = pc.lum > 0.5 and 0.55 or 0.4
		for _, s in ipairs({ 1, -1 }) do
			local p = torsoSurface(sk, P, prof, s * (0.47 + P.V.nipple[1]) * xS, 0.56 + P.V.nipple[2] - 0.03 * P.lv.pecs, field1)
			spots[#spots + 1] = { p[1], p[2], p[3], 0.055 * xS, sr * 0.68, sg * 0.5, sb * 0.46, ak, true }
			spots[#spots + 1] = { p[1], p[2], p[3], 0.022 * xS, sr * 0.6, sg * 0.42, sb * 0.4, 0.5 }
		end
	end
	do
		local nav = torsoSurface(sk, P, prof, 0, 0.035, nil)
		spots[#spots + 1] = { nav[1], nav[2], nav[3] - 0.01, 0.045, sr * 0.45, sg * 0.32, sb * 0.28, 0.85 }
		-- the navel's crease above it (a short dark line in the texture)
		spots[#spots + 1] = { nav[1], nav[2] + 0.02, nav[3] - 0.01, 0.026, sr * 0.4, sg * 0.28, sb * 0.25, 0.6 }
	end
	local topR, topG, topB = clothOf(look, "UpperTorso")
	local function base(x, y, z, lowK)
		local r, g, b = sr, sg, sb
		local u = (y - yW) / H
		-- shoulders / upper back a touch darker and warmer, the neck a little redder
		local top = smooth(0.7, 1.0, u) * (0.6 + 0.4 * smooth(-0.2, 0.4, z))
		r, g, b = mix(r, g, b, sr * 0.93, sg * 0.88, sb * 0.86, 0.25 * top)
		-- armpits
		local ap = bell(((abs(x) / xS) - 0.86) / 0.14) * bell((u - 0.72) / 0.1)
		r, g, b = mix(r, g, b, sr * 0.8, sg * 0.74, sb * 0.72, 0.35 * ap)
		for _, sp in ipairs(spots) do
			local dx, dy, dz = x - sp[1], y - sp[2], z - sp[3]
			local d2 = (dx * dx + dy * dy + dz * dz) / (sp[4] * sp[4])
			if d2 < 1 then
				local w = (1 - d2) * (1 - d2)
				r, g, b = mix(r, g, b, sp[5], sp[6], sp[7], w * sp[8] * (sp[9] and lowK or 1))
			end
		end
		return r, g, b
	end
	-- the sports top over the skin (soft = edge width in u: the vertex colours need a soft edge, texels a crisp
	-- one with a stitched hem line)
	local function top(r, g, b, x, y, z, soft, grain)
		if not topR then
			return r, g, b
		end
		local w, edge = Torso.TopMask(sk, x, y, z, soft)
		if w <= 0 then
			return r, g, b
		end
		local k = (1 - 0.14 * edge) * (grain or 1)
		return mix(r, g, b, topR * k, topG * k, topB * k, w)
	end
	return { base = base, top = top, hasTop = topR ~= nil }
end

------------------------------------------------------------------------
-- Shoulder: one smooth shading surface across the deltoid cap and the torso
------------------------------------------------------------------------
-- The UpperArm's cap overlaps the UpperTorso's shoulder (two pieces, so the arm can rotate). Where one surface
-- comes out of the other the shading broke into a ring-shaped crease. Near that line each piece's normals turn
-- toward the other's (the nearest vertex over there), so the light runs over the shoulder from the chest and
-- the traps into the deltoid; the silhouette is unchanged. Body space, bind pose (the cap moves little with the
-- arm near the pivot).
local function blendShoulderNormals(ut, arm, armB, sk, side)
	local sg = side == "Right" and 1 or -1
	local yS = sk.piv[side .. "Shoulder"][2]
	local UP, UN, AP, AN = ut.P, ut.N, arm.P, arm.N
	-- the torso's shoulder region (this side), and the arm's cap rows
	local tIds, aIds = {}, {}
	for i = 1, ut.nv do
		if UP[i * 3 - 2] * sg > 0.45 * sk.xS and UP[i * 3 - 1] > yS - 0.45 then
			tIds[#tIds + 1] = i
		end
	end
	for i = 1, arm.nv do
		if (armB[i] or 1) < 0.45 then
			aIds[#aIds + 1] = i
		end
	end
	if #tIds == 0 or #aIds == 0 then
		return
	end
	-- nearest vertex of the other piece, the signed distance off its surface (along its normal) -> weight
	local function transfer(ids, P, oIds, OP, ON, reach)
		local out, ws = table.create(#ids * 3, 0), table.create(#ids, 0)
		for k, i in ipairs(ids) do
			local px, py, pz = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
			local best, bj = math.huge, 0
			for _, j in ipairs(oIds) do
				local dx, dy, dz = px - OP[j * 3 - 2], py - OP[j * 3 - 1], pz - OP[j * 3]
				local d2 = dx * dx + dy * dy + dz * dz
				if d2 < best then
					best, bj = d2, j
				end
			end
			local w = 0
			if best < reach * reach then
				local qx, qy, qz = ON[bj * 3 - 2], ON[bj * 3 - 1], ON[bj * 3]
				local s = (px - OP[bj * 3 - 2]) * qx + (py - OP[bj * 3 - 1]) * qy + (pz - OP[bj * 3]) * qz
				w = (1 - smooth(0.0, 0.07, s)) * (1 - smooth(reach * 0.5, reach, sqrt(best))) * 0.85
				out[k * 3 - 2], out[k * 3 - 1], out[k * 3] = qx, qy, qz
			end
			ws[k] = w
		end
		return out, ws
	end
	local aT, aW = transfer(aIds, AP, tIds, UP, UN, 0.16)
	local tT, tW = transfer(tIds, UP, aIds, AP, AN, 0.16)
	local function apply(ids, N, T, W)
		for k, i in ipairs(ids) do
			local w = W[k]
			if w > 0.01 then
				local nx = N[i * 3 - 2] + (T[k * 3 - 2] - N[i * 3 - 2]) * w
				local ny = N[i * 3 - 1] + (T[k * 3 - 1] - N[i * 3 - 1]) * w
				local nz = N[i * 3] + (T[k * 3] - N[i * 3]) * w
				local l = sqrt(nx * nx + ny * ny + nz * nz)
				if l > 1e-6 then
					N[i * 3 - 2], N[i * 3 - 1], N[i * 3] = nx / l, ny / l, nz / l
				end
			end
		end
	end
	apply(aIds, AN, aT, aW)
	apply(tIds, UN, tT, tW)
end

------------------------------------------------------------------------
-- Generate
------------------------------------------------------------------------
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
	local seed = (P.V.veinSeed or 1) % 100000
	local pc = paintContext(look, P, seed)
	local sr, sg, sb = pc.sr, pc.sg, pc.sb
	local wear = wearOf(look)
	local trunk = wear.trunk
	local pieces = {}
	local morphSets = {}
	local textures = {} -- name -> { info, w, h, paint, arrays } (made after the move into part space)

	-- UpperTorso ----------------------------------------------------------------
	local ut, ui = Torso.Upper(sk, P, lod, { trunks = trunk ~= nil, top = clothOf(look, "UpperTorso") ~= nil })
	local prof = ui.prof
	local grid = ui.loft
	local up = utPainter(pc, sk, P, prof, look)
	local cav = Kit.GridCavity(ut, grid)
	local dark, light = Kit.AOAmounts(ut, cav, pc.ao)
	do
		local C, Pp, ch = ut.C, ut.P, ui.ch
		local lowK = lod == "low" and 0.35 or (lod == "medium" and 0.7 or 1)
		for i = 1, ut.nv do
			local x, y, z = Pp[i * 3 - 2], Pp[i * 3 - 1], Pp[i * 3]
			local r, g, b = up.base(x, y, z, lowK)
			r, g, b = sepShade(pc, r, g, b, ch.groove[i], ch.crown[i], 0.75, 0.22)
			local k = 1 + 0.028 * MeshKit.Noise(x * 2.6, y * 2.6, z * 2.6, seed) + 0.012 * MeshKit.Noise(x * 9, y * 9, z * 9, seed + 7)
			r, g, b = r * k, g * k, b * k
			r, g, b = up.top(r, g, b, x, y, z, 1)
			r, g, b = Kit.ApplyAO(r, g, b, dark[i], light[i], pc.aoTint)
			C[i * 3 - 2], C[i * 3 - 1], C[i * 3] = r, g, b
		end
	end
	Kit.GridUV(ut, grid, Gen.TEXTURE.UpperTorso)
	if full then
		ut.texMap = Kit.TexMap(grid, Gen.TEXTURE.UpperTorso, Gen.TEXTURE.UpperTorso)
	end
	if full then
		local field, ch = ui.field, ui.ch
		local tw = Gen.TEXTURE.UpperTorso
		textures.UpperTorso = { w = tw, h = tw, build = function()
			local tiles = texNoise(pc)
			local grain = Kit.GrainTable(pc, tw, tw)
			-- 1) the brushes per texel at half resolution, on the undisplaced surface (separations, fibres)
			local hw = tw // 2
			local G, Cr, Fb = table.create(hw * hw, 0), table.create(hw * hw, 0), table.create(hw * hw, 0)
			Kit.GridTexture(MeshKit, ut, grid, hw, hw, function(sm)
				field(0, sm.x, sm.y, sm.z, sm.nx, sm.ny, sm.nz, true)
				local k = sm.py * hw + sm.px + 1
				G[k], Cr[k], Fb[k] = ch.groove[0], ch.crown[0], ch.fibre[0] or 0
				return 0, 0, 0
			end, { P = ui.P0, N = ui.N0 })
			-- 2) every texel: the channels bilinear from that lattice (wrapping round the body)
			return Kit.GridTexture(MeshKit, ut, grid, tw, tw, function(sm)
				local fx, fy = (sm.px + 0.5) * 0.5 - 0.5, clamp((sm.py + 0.5) * 0.5 - 0.5, 0, hw - 1)
				local x0, y0 = floor(fx), floor(fy)
				local tx, ty = fx - x0, fy - y0
				local y1 = min(y0 + 1, hw - 1)
				local xa, xb = x0 % hw, (x0 + 1) % hw
				local i00, i10, i01, i11 = y0 * hw + xa + 1, y0 * hw + xb + 1, y1 * hw + xa + 1, y1 * hw + xb + 1
				local w00, w10, w01, w11 = (1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty
				local gr = G[i00] * w00 + G[i10] * w10 + G[i01] * w01 + G[i11] * w11
				local cr = Cr[i00] * w00 + Cr[i10] * w10 + Cr[i01] * w01 + Cr[i11] * w11
				local fib = Fb[i00] * w00 + Fb[i10] * w10 + Fb[i01] * w01 + Fb[i11] * w11
				local r, g, b = up.base(sm.x, sm.y, sm.z, 1)
				r, g, b = sepShade(pc, r, g, b, gr, cr, 0.75, 0.22)
				if fib > 0 then
					local k = 1 + 0.05 * (fib - 0.5) * 2 * pc.def
					r, g, b = r * k, g * k, b * k
				end
				local k = grain[sm.py * tw + sm.px + 1]
				r, g, b = r * k, g * k, b * k
				if up.hasTop then
					r, g, b = up.top(r, g, b, sm.x, sm.y, sm.z, 0.2, 1 + 0.02 * Kit.TileAt(tiles.pore, sm.px * 0.5, sm.py * 2))
				end
				return Kit.ApplyAO(r, g, b, sm.dark, sm.light, pc.aoTint)
			end, { P = ui.P0, N = ui.N0, dark = dark, light = light, noN = true })
		end }
	end
	-- blend shapes (full detail): flex / breathe / tense along the sculpting normals, the shoulder raise / reach
	if full then
		local ch = ui.ch
		local N = ut.N
		local ids, fx, fy, fz = {}, {}, {}, {}
		local bids, bx, by, bz = {}, {}, {}, {}
		local tids, tx, ty, tz = {}, {}, {}, {}
		local rs = { L = { {}, {}, {}, {} }, R = { {}, {}, {}, {} } }
		local rc = { L = { {}, {}, {}, {} }, R = { {}, {}, {}, {} } }
		-- nothing swells right above the waistband (the band does not move: a pushed-out belly would overhang it)
		local tuck = trunk and Torso.BAND_TOP / sk.H or nil
		local UP = ut.P
		local raiseH = 0.17 * sk.H / 1.6
		local reachD = 0.07 * sk.hz / 0.55
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
			local x = UP[i * 3 - 2]
			local sideKey = x >= 0 and "R" or "L"
			local rw = ch.raise[i]
			if rw > 1e-3 then
				local e = rs[sideKey]
				local n = #e[1] + 1
				-- up, and a little in toward the neck where the trapezius bunches
				e[1][n], e[2][n], e[3][n], e[4][n] = i, -x * 0.04 * rw, raiseH * rw, 0.01 * rw
			end
			local cw = ch.reach[i]
			if cw > 1e-3 then
				local e = rc[sideKey]
				local n = #e[1] + 1
				-- forward round the ribs (the shoulder blade slides out and forward)
				e[1][n], e[2][n], e[3][n], e[4][n] = i, x * 0.02 * cw, 0.02 * cw, -reachD * cw * (0.4 + 0.6 * smooth(-0.6, 0.4, -nz))
			end
		end
		morphSets.UpperTorso = {
			flex = { ids, fx, fy, fz }, breathe = { bids, bx, by, bz }, tense = { tids, tx, ty, tz },
			raiseL = rs.L, raiseR = rs.R, reachL = rc.L, reachR = rc.R,
		}
	end
	-- landmarks (body space; translated with the mesh)
	local field1 = Torso.Field(sk, P, prof, 1)
	local lmBody = landmarksBody(sk, P, prof, field1, wear)
	pieces.UpperTorso = { mesh = ut, material = "Plastic" }

	-- LowerTorso (the trunks' seat) ----------------------------------------------------------
	local legTop = trunk and { Limbs.TrunkTop(sk, P, "Right", wear.zones.RightUpperLeg) } or nil
	local lt, li = Torso.Lower(sk, P, lod, prof, { trunks = trunk ~= nil, female = P.female, legTop = legTop })
	local lgrid = li.loft
	local lcav = Kit.GridCavity(lt, lgrid)
	local ltPaint
	local ltAO, ltTint
	if trunk then
		ltAO, ltTint = { cavity = 0.25, down = 0.16, ridge = 0.04 }, pc.clothTint
		local bandY = li.bandBot
		-- the style's side trim on the seat: the same bands as the satin legs' (Gear.LimbPainter: the angle from
		-- the leg's lateral line, 0.2 rad Striped, 0.48 / 0.13 rad the Pro panel / its white stripe), carried up
		-- the seat as straight vertical bands of the width they have where the legs come out of the seat (front /
		-- back offset from the legs' lateral line), so the seat's trim meets the legs' at the openings with clean
		-- edges (a band picked by the surface normal wobbled with the satin's folds and the lattice)
		local trimCz, trimF, trimB = 0, {}, {}
		if legTop and legTop[4] then
			local latX = legTop[4]
			trimCz = legTop[5] or 0
			for _, d0 in ipairs({ 0.13, 0.2, 0.48 }) do
				for k = 1, 2 do
					local ez = k == 1 and legTop[2] or legTop[3]
					local c, s = math.cos(d0), math.sin(d0)
					local r = 1 / ((c / latX) ^ 2.4 + (s / ez) ^ 2.4) ^ (1 / 2.4)
					if k == 1 then
						trimF[d0] = r * s
					else
						trimB[d0] = r * s
					end
				end
			end
		else
			for _, d0 in ipairs({ 0.13, 0.2, 0.48 }) do
				trimF[d0], trimB[d0] = 0.35 * math.sin(d0), 0.35 * math.sin(d0)
			end
		end
		ltPaint = function(x, y, z, nx, ny, nz, crisp, grain)
			local r, g, b = trunk.r, trunk.g, trunk.b
			if y >= bandY - (crisp and 0.002 or 0.004) then
				-- the elastic waistband in the trim colour, a knit line along its middle
				local mid = bell((y - (bandY + li.top) / 2) / (crisp and 0.008 or 0.02)) * 0.08
				r, g, b = trunk.tr * (1 - mid), trunk.tg * (1 - mid), trunk.tb * (1 - mid)
				-- the band's lower edge is stitched
				if crisp then
					local st = bell((y - bandY - 0.01) / 0.004) * 0.12
					r, g, b = r * (1 - st), g * (1 - st), b * (1 - st)
				end
			else
				-- the style's side trim runs down the outside of the seat into the legs (outer half only: the
				-- crotch's middle is never trim)
				local st = trunk.style
				if (st == "Striped" or st == "Pro") and abs(x) > 0.5 * li.hipW then
					local dz = z - trimCz
					local tw = dz < 0 and trimF or trimB
					local adz = abs(dz)
					local aa = crisp and 0.004 or 0.02
					if st == "Striped" then
						r, g, b = mix(r, g, b, trunk.tr, trunk.tg, trunk.tb, smooth(-aa, aa, tw[0.2] - adz))
					else
						r, g, b = mix(r, g, b, trunk.tr, trunk.tg, trunk.tb, smooth(-aa, aa, tw[0.48] - adz))
						r, g, b = mix(r, g, b, 0.95, 0.95, 0.95, smooth(-aa * 0.6, aa * 0.6, tw[0.13] - adz))
					end
				end
				r, g, b = r * (grain or 1), g * (grain or 1), b * (grain or 1)
			end
			return r, g, b
		end
	else
		ltAO, ltTint = pc.ao, pc.aoTint
		ltPaint = function(x, y, z)
			return sr, sg, sb
		end
	end
	local ldark, llight = Kit.AOAmounts(lt, lcav, ltAO)
	do
		local C, Pp, N = lt.C, lt.P, lt.N
		for i = 1, lt.nv do
			local x, y, z = Pp[i * 3 - 2], Pp[i * 3 - 1], Pp[i * 3]
			local r, g, b = ltPaint(x, y, z, N[i * 3 - 2], N[i * 3 - 1], N[i * 3], false, 1 + 0.012 * MeshKit.Noise(x * 3, y * 3, z * 3, seed + 3))
			if not trunk then
				r, g, b = sepShade(pc, r, g, b, 0, li.crown[i], 0.6, 0.2)
			end
			C[i * 3 - 2], C[i * 3 - 1], C[i * 3] = Kit.ApplyAO(r, g, b, ldark[i], llight[i], ltTint)
		end
	end
	Kit.GridUV(lt, lgrid, Gen.TEXTURE.LowerTorso)
	if full then
		lt.texMap = Kit.TexMap(lgrid, Gen.TEXTURE.LowerTorso, Gen.TEXTURE.LowerTorso)
	end
	if full then
		local tw = Gen.TEXTURE.LowerTorso
		local cy = sk.center.LowerTorso
		textures.LowerTorso = { w = tw, h = tw, build = function()
			local tiles = texNoise(pc)
			local grain = Kit.GrainTable(pc, tw, tw)
			return Kit.GridTexture(MeshKit, lt, lgrid, tw, tw, function(sm)
				local x, y, z = sm.x + cy[1], sm.y + cy[2], sm.z + cy[3]
				-- satin: a soft sheen variation along the folds
				local sat = 1 + 0.025 * Kit.TileAt(tiles.fine, sm.px * 0.25, sm.py * 0.12)
				local r, g, b = ltPaint(x, y, z, sm.nx, sm.ny, sm.nz, true, trunk and sat or 1)
				if not trunk then
					local k = grain[sm.py * tw + sm.px + 1]
					r, g, b = r * k, g * k, b * k
				end
				return Kit.ApplyAO(r, g, b, sm.dark, sm.light, ltTint)
			end, { dark = ldark, light = llight })
		end }
	end
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
		morphSets.LowerTorso = { flex = { ids, dx, dy, dz }, breathe = { bids, bx, by, bz } }
	end
	pieces.LowerTorso = { mesh = lt, material = trunk and "SmoothPlastic" or "Plastic", reflectance = trunk and 0.03 or 0 }

	-- limbs ----------------------------------------------------------------
	local gear = wear.gear
	for _, side in ipairs(SIDES) do
		for _, kind in ipairs(LIMBS) do
			local name = side .. kind
			local lopt = { zones = wear.zones[name] }
			if full and not clothOf(look, name) then
				-- veins above the garments (the boot shaft, the glove cuff)
				local topB = 1
				if kind == "LowerLeg" then
					topB = gear.shoe.sock or gear.shoe.shaft
				elseif kind == "LowerArm" then
					topB = gear.hands == "gloves" and gear.glove.cuffTop or (gear.hands == "wraps" and gear.wrap.top or 1)
				end
				lopt.veins = Limbs.VeinPaths(P, kind, side, sk.size[name][1], topB)
			end
			local m, info = Limbs.Build(sk, P, lod, side, kind, lopt)
			local lg = info.grid
			if kind == "UpperArm" then
				blendShoulderNormals(ut, m, info.B, sk, side)
			end
			-- garment vertices (BodyFX never paints grime / bruises on them)
			for i = 1, m.nv do
				local z = info.Z[i]
				if z ~= "skin" and z ~= "vein" then
					MeshKit.AddToGroup(m, "cloth", i)
				end
			end
			local paint = Gear.LimbPainter(pc, sk, P, look, wear, side, kind, info, trunk, Limbs)
			local isCloth = kind == "UpperLeg" and trunk ~= nil
			local lcav2 = Kit.GridCavity(m, lg)
			local d2, l2 = Kit.AOAmounts(m, lcav2, pc.ao)
			local C, Pp, N = m.C, m.P, m.N
			local B, A = info.B, info.A
			for i = 1, m.nv do
				local r, g, b = paint.color(B[i], A[i], Pp[i * 3 - 2], Pp[i * 3 - 1], Pp[i * 3], N[i * 3 - 2], N[i * 3 - 1], N[i * 3], info.groove[i], info.crown[i], false, i)
				C[i * 3 - 2], C[i * 3 - 1], C[i * 3] = Kit.ApplyAO(r, g, b, d2[i] * paint.aoK(B[i]), l2[i], paint.tint(B[i]))
			end
			Kit.GridUV(m, lg, Gen.TEXTURE.limb, nil, Gen.TEXTURE.limbW)
			if full then
				m.texMap = Kit.TexMap(lg, Gen.TEXTURE.limbW, Gen.TEXTURE.limb)
			end
			-- veins take the UV of the skin under them
			if info.veinFirst <= m.nv then
				Kit.GridUVAt(m, lg, info.veinFirst, m.nv, B, A)
			end
			if full then
				local tw, th = Gen.TEXTURE.limbW, Gen.TEXTURE.limb
				textures[name] = { w = tw, h = th, build = function()
					texNoise(pc)
					return paint.texture(m, lg, tw, th, d2, l2)
				end }
				local ids, dx, dy, dz = {}, {}, {}, {}
				local fl, D = info.flex, info.dir
				for i = 1, m.nv do
					local f = fl[i]
					if f > 1e-4 then
						ids[#ids + 1] = i
						dx[#ids], dy[#ids], dz[#ids] = D[i * 3 - 2] * f, D[i * 3 - 1] * f, D[i * 3] * f
					end
				end
				morphSets[name] = { flex = { ids, dx, dy, dz } }
			end
			local _ = isCloth
			pieces[name] = { mesh = m, material = paint.material, reflectance = paint.reflectance or 0 }
		end
	end

	-- hands and feet (gloves, wraps, bare hands; boots / trainers) ---------------------------------
	for _, side in ipairs(SIDES) do
		for _, kind in ipairs({ "Hand", "Foot" }) do
			local name = side .. kind
			local m, info, paint = Gear.Build(sk, P, lod, side, kind, wear, pc, seed)
			local cav2 = Kit.GridCavity(m, info.grid)
			local d2, l2 = Kit.AOAmounts(m, cav2, paint.ao)
			local C, Pp, N = m.C, m.P, m.N
			for i = 1, m.nv do
				local r, g, b = paint.vertex(i, Pp[i * 3 - 2], Pp[i * 3 - 1], Pp[i * 3], N[i * 3 - 2], N[i * 3 - 1], N[i * 3])
				C[i * 3 - 2], C[i * 3 - 1], C[i * 3] = Kit.ApplyAO(r, g, b, d2[i], l2[i], paint.tint)
			end
			Kit.GridUVAtlas(m, info.grid, Gen.TEXTURE[kind == "Hand" and "hand" or "foot"])
			if full then
				local tw = Gen.TEXTURE[kind == "Hand" and "hand" or "foot"]
				textures[name] = { w = tw, h = tw, build = function()
					local tiles = texNoise(pc)
					return Kit.GridTexture(MeshKit, m, info.grid, tw, tw, function(sm)
						local r, g, b = paint.texel(sm, tiles, tw)
						return Kit.ApplyAO(r, g, b, sm.dark, sm.light, paint.tint)
					end, { dark = d2, light = l2, noN = true, noP = not paint.needP })
				end }
				if info.flex then
					local ids, dx, dy, dz = {}, {}, {}, {}
					for k, i in ipairs(info.flex.ids) do
						ids[k] = i
						dx[k], dy[k], dz[k] = info.flex.d[k * 3 - 2], info.flex.d[k * 3 - 1], info.flex.d[k * 3]
					end
					if #ids > 0 then
						morphSets[name] = { flex = { ids, dx, dy, dz } }
					end
				end
			end
			pieces[name] = { mesh = m, material = paint.material, reflectance = paint.reflectance or 0 }
		end
	end

	-- landmarks, body space -> each part's space, then the blend shapes (bounds are final only now)
	for name, e in pairs(lmBody) do
		local piece = pieces[e.part]
		if piece then
			MeshKit.SetLandmark(piece.mesh, name, e.pos[1], e.pos[2], e.pos[3])
		end
	end
	for name, piece in pairs(pieces) do
		local c = sk.center[name] or { 0, 0, 0 }
		MeshKit.Transform(piece.mesh, MeshKit.MatTranslate(-c[1], -c[2], -c[3]))
	end
	if full then
		for name, set in pairs(morphSets) do
			for mname, e in pairs(set) do
				addMorph(pieces[name].mesh, mname, e[1], e[2], e[3], e[4])
			end
		end
		-- colour textures, made the first time AnatomyClient (or a tool) reads them
		for name, t in pairs(textures) do
			pieces[name].texture = Kit.LazyTexture(t.w, t.h, t.build)
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
	return toPart(sk, landmarksBody(sk, P, prof, field, wearOf(look)))
end

return Gen
