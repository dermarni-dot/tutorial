-- AnatomyBodyTorso: the UpperTorso piece (ribcage, chest, abdomen, back, shoulder tops, neck column) and the
-- LowerTorso piece (pelvis, glutes, the seat of the trunks), built in UpperTorso space (body space) by
-- AnatomyBody. Method: a loft of smooth superellipse sections whose silhouettes follow the rig (waist / neck
-- pivots, shoulder span, torso depth), then sculpted along the normals by soft anatomical brushes (pecs,
-- rectus blocks, costal margin, obliques, serratus, lats, traps, scapulae, erectors, clavicles,
-- sternocleidomastoids, breasts, fat). The brushes also write per-vertex shading (groove / crown) and muscle
-- weights that the painter and the blend shapes (flex / breathe / tense) read.
-- u = (y - waist pivot) / (neck pivot - waist pivot): 0 = navel, ~0.875 = shoulder pivots, 1 = neck pivot.
local MeshKit = require(script.Parent:WaitForChild("MeshKit"))
local Kit = require(script.Parent:WaitForChild("AnatomyBodyKit"))

local Torso = {}

-- the Head section's visible neck (AnatomySkull.Neck, Head-part space); nil when the skull module is missing
local Skull
do
	local ms = script.Parent:FindFirstChild("AnatomySkull")
	local ok, mod = pcall(function()
		return ms and require(ms)
	end)
	Skull = ok and type(mod) == "table" and type(mod.Neck) == "function" and mod or nil
end
local function neckOf(look)
	if not (Skull and type(look) == "table") then
		return nil
	end
	local ok, hn = pcall(Skull.Neck, look)
	return ok and type(hn) == "table" and hn or nil
end

local abs, min, max, sqrt, cos, sin, pi = math.abs, math.min, math.max, math.sqrt, math.cos, math.sin, math.pi
local clamp, smooth, lerp, bell, bell3, bell2 = Kit.clamp, Kit.smooth, Kit.lerp, Kit.bell, Kit.bell3, Kit.bell2
local TAU = pi * 2

-- (ltSides = twice the satin legs' sides less four at every level (Limbs.RES UpperLeg): the trunks' seat then
-- puts a vertex on every leg vertex round each leg, so its rim lies on the legs' rim ring exactly)
Torso.RES = {
	full = { rings = 29, sides = 32, ltRings = 12, ltSides = 28, dome = 1, ltDome = 2, warp = 0.32 },
	medium = { rings = 21, sides = 24, ltRings = 7, ltSides = 20, dome = 1, ltDome = 1, warp = 0.28 },
	low = { rings = 12, sides = 12, ltRings = 5, ltSides = 12, dome = 1, ltDome = 1, warp = 0.2 },
}

------------------------------------------------------------------------
-- Silhouettes (half width W in shoulder-span units, front F / back K depth in half-depth units)
------------------------------------------------------------------------
-- The R15 shoulder pivots sit at the torso box's edge and the arms are thick, so the torso proper stays
-- inside the arms: widest at the armpit (chest wall + lats), then it narrows above the armpit and runs up
-- the trapezius slope to the neck, tucked under the deltoid caps the arm pieces carry. The shoulder line is
-- the arm's deltoid, never a corner of the torso.
function Torso.Profiles(sk, P)
	local fem = P.female
	local lv, fk = P.lv, P.fatK
	local xS, hz = sk.xS, sk.hz
	-- neck radius (studs): the sternocleidomastoids, the traps and the slider thicken it; never thinner than
	-- 0.25 x the head (women 0.225, ANATOMY_CONTRACTS section 6)
	local rn = sk.headX * (fem and 0.258 or 0.282) * (1 + 0.12 * lv.neckSCM + 0.05 * lv.traps + 0.08 * P.sl.neck + 0.06 * min(fk, 1)) * P.V.neckW
	local rMin = sk.headX * (fem and 0.225 or 0.25) * 1.08 -- the contract minimum with room for the notch and the larynx groove
	rn = max(rn, rMin)
	-- the Head section's neck shows from under the jaw down to the Neck pivot: this column stays inside it there
	-- (Head-part space; it is at least the contract minimum: 0.2625 / 0.2375 x head X before the 0.012 margin)
	local hn = neckOf(P.look)
	if hn then
		rn = min(rn, hn.r - 0.012)
	end
	-- the R15 torso is shallow for its width: the neck keeps its width but never gets deeper than the chest
	-- allows (still at least the contract minimum all round)
	local rz = max(rMin * 1.06, min(rn * 0.97, 0.78 * hz)) -- the front is 0.95 of this: still over the minimum
	if hn then
		rz = min(rz, hn.rz - 0.012)
	end
	local nx, fN, kN = rn / xS, rz * 0.95 / hz, rz * 1.04 / hz
	-- under the pivot the column is the visible neck: never thinner than the contract minimum there, even when
	-- the Head's neck is (a head scaled flatter than it is wide)
	local vMin = sk.headX * (fem and 0.225 or 0.25)
	local nxV, fNV = max(nx * 1.02, vMin / xS), max(fN * 1.03, vMin / hz)
	local wk = (1 + 0.05 * P.sl.waist) * (1 + 0.1 * min(fk, 1.2)) * (1 - 0.05 * (P.pv.taper - 1))
	local trap = 1 + 0.25 * lv.traps * (fem and 0.6 or 1)
	-- the lats widen the back under the armpits (the V); the chest slider widens the rib cage
	local lat = (0.015 + 0.06 * lv.lats) * P.pv.taper * (fem and 0.6 or 1)
	local cw = 1 + 0.03 * P.sl.chest
	-- the trapezius slope: from inside the deltoid at the shoulder pivot (u ~0.875) up to the neck
	local ts = trap ^ 0.25
	local W, F, K
	if fem then
		W = Kit.Curve({
			{ -0.14, 0.72 }, { 0.0, 0.6 * wk }, { 0.12, 0.605 * wk }, { 0.25, 0.66 }, { 0.38, 0.72 * cw }, { 0.5, 0.765 * cw + lat * 0.5 },
			{ 0.62, 0.795 * cw + lat }, { 0.72, 0.81 * cw + lat * 0.8 }, { 0.8, 0.805 + lat * 0.3 }, { 0.86, 0.8 }, { 0.9, 0.785 },
			{ 0.93, 0.685 * ts }, { 0.95, max(0.45 * ts, nx * 1.3) }, { 0.965, max(0.34, nx * 1.1) }, { 0.985, nxV },
			{ 1.01, nx }, { 1.2, nx },
		})
	else
		-- (the torso's top edge meets the deltoid cap at about x 0.9 xS, 0.1 above the shoulder pivot (u ~0.93);
		-- from there the trapezius rises to the neck, meeting it a little below the Neck pivot (u ~0.96): the R15
		-- chin sits only ~0.04 above the pivot, so a trapezius that reaches the neck any higher leaves no neck
		-- showing between the jaw and the shoulders)
		W = Kit.Curve({
			{ -0.14, 0.75 * wk }, { 0.0, 0.69 * wk }, { 0.12, 0.7 * wk }, { 0.25, 0.745 }, { 0.38, 0.795 * cw + lat * 0.3 },
			{ 0.5, 0.835 * cw + lat * 0.65 }, { 0.62, 0.86 * cw + lat }, { 0.72, 0.875 * cw + lat * 0.9 }, { 0.8, 0.87 + lat * 0.4 },
			{ 0.86, 0.85 }, { 0.9, 0.825 }, { 0.93, 0.71 * ts }, { 0.95, max(0.47 * ts, nx * 1.3) }, { 0.965, max(0.36, nx * 1.1) },
			{ 0.985, nxV }, { 1.01, nx }, { 1.2, nx },
		})
	end
	-- the tops run down into the neck monotonically: no dip (a crease) where the neck is thick for the torso
	F = Kit.Curve({
		{ -0.14, 0.9 }, { 0.0, 0.88 }, { 0.2, 0.9 }, { 0.35, 0.95 }, { 0.5, 0.98 }, { 0.62, 0.98 }, { 0.74, 0.95 }, { 0.84, max(0.87, fN * 1.4) },
		{ 0.9, max(0.76, fN * 1.3) }, { 0.94, max(0.6, fN * 1.12) }, { 0.97, fNV }, { 1.0, fN }, { 1.2, fN },
	})
	-- the back: full over the shoulder blades, then the trapezius sheet rising into the neck (a tent, no shelf)
	K = Kit.Curve({
		{ -0.14, 0.93 }, { 0.02, 0.86 }, { 0.18, 0.88 }, { 0.33, 0.93 }, { 0.48, 0.97 }, { 0.62, 1.0 }, { 0.74, max(1.0, min(1.04, kN * 1.5)) },
		{ 0.84, max(0.96, min(1.02, kN * 1.42)) }, { 0.92, max(0.85, kN * 1.33) }, { 0.97, max(0.74, kN * 1.22) }, { 1.0, kN * 1.06 },
		{ 1.04, rz * 0.98 / hz }, { 1.2, rz * 0.98 / hz },
	})
	-- the shoulders round off toward the deltoids (a squarer section keeps the torso's corner in front of the
	-- deltoid cap, which then reads as an arm hung beside a box)
	local nF = Kit.Curve({ { -0.1, 2.2 }, { 0.5, 2.25 }, { 0.7, 2.2 }, { 0.84, 1.95 }, { 0.95, 1.85 }, { 1.06, 2.0 } })
	-- the upper back rounds into the sides (a squarer section reads as a box from behind)
	local nB = Kit.Curve({ { -0.1, 2.3 }, { 0.42, 2.3 }, { 0.6, 2.05 }, { 0.84, 1.88 }, { 0.95, 1.85 }, { 1.06, 2.0 } })
	-- posture: the neck rises a little behind the torso centre (under the skull's base), never further back than
	-- the Head's own neck (the column stays inside it above the pivot)
	local zTop = hn and min(0.08 * hz, hn.z) or 0.08 * hz
	local zc = Kit.Curve({ { 0.92, 0 }, { 1.05, zTop * 0.5 }, { 1.2, zTop } })
	return { W = W, F = F, K = K, nF = nF, nB = nB, zc = zc, rn = rn, rz = rz, hn = hn }
end

------------------------------------------------------------------------
-- Brushes: displacement along the normal (studs) + shading / muscle weights per vertex
------------------------------------------------------------------------
-- returns field(i, x, y, z, nx, ny, nz) -> d and the channels it fills
local function torsoField(sk, P, prof, nv)
	local xS, H, yW, hz = sk.xS, sk.H, sk.yW, sk.hz
	local lv, V, pv = P.lv, P.V, P.pv
	local fem = P.female
	local def, fk = P.defE, min(P.fatK, 1.2)
	local lean = clamp((14 - P.fat) / 7, 0, 1) -- clavicles / ribs read below ~12 %
	local flat = pv.flat
	local W = prof.W
	local ch = { groove = table.create(nv, 0), crown = table.create(nv, 0), pec = table.create(nv, 0), lat = table.create(nv, 0),
		trap = table.create(nv, 0), abs = table.create(nv, 0), obl = table.create(nv, 0), rib = table.create(nv, 0),
		belly = table.create(nv, 0), raise = table.create(nv, 0), reach = table.create(nv, 0), fibre = table.create(nv, 0) }
	local sideK = { [1] = Kit.SideK(P, 1), [-1] = Kit.SideK(P, -1) }
	local hzK = (hz / 0.5) ^ 0.5
	-- pectoralis major: every man has a chest plate; training thickens it, fat softens and lowers it
	local pecH = (0.032 + 0.115 * lv.pecs ^ 0.85 + 0.035 * lv.upperChest) * flat * V.pecFull * hzK + 0.05 * fk
	local upperK = clamp(0.4 + 0.55 * lv.upperChest / max(0.15, lv.pecs + 0.1), 0.38, 1.05)
	-- (never sharper than ~2 ring spacings: a hard border stair-steps where it runs diagonally to the armpit)
	local pecEdge = max(0.034, 0.022 + 0.03 * (1 - def) + 0.03 * fk)
	local pecDrop = V.pecBorder - 0.03 * lv.pecs - 0.04 * fk
	-- the lower border is a crescent: lowest under the nipple line, a rounded inner corner at the sternum,
	-- sweeping up into the armpit fold (a flat line across the chest reads as two carved slabs)
	local pecBorder = Kit.Curve({ { 0.02, 0.53 }, { 0.18, 0.485 }, { 0.38, 0.455 }, { 0.55, 0.475 }, { 0.7, 0.545 }, { 0.82, 0.64 }, { 0.92, 0.75 }, { 1.0, 0.84 }, { 1.05, 0.9 } })
	-- rectus abdominis
	local absH = (0.005 + 0.045 * lv.abs) * (0.15 + 0.85 * def) * (fem and 0.6 or 1) * pv.groove ^ 0.5
	local absBand = (0.008 + 0.018 * lv.abs) * (1 - 0.5 * min(fk, 1))
	local rowsBase = { -0.3, 0.075, 0.198, 0.318, 0.47 }
	local rowsS = {}
	for _, s in ipairs({ 1, -1 }) do
		local r = {}
		for k = 1, 5 do
			local off = 0
			if k >= 2 and k <= 4 then
				off = V.abRow[k - 1] + s * V.abStagger
			end
			r[k] = rowsBase[k] + off
		end
		rowsS[s] = r
	end
	local abGap = 0.018 + 0.02 * (1 - def)
	-- other muscles
	local oblH = (0.006 + 0.04 * lv.obliques) * (0.5 + 0.5 * def) * flat + 0.03 * fk
	-- (shallow: the fingers sit across few columns on the side of the chest; the paint carries the rest)
	local serH = (0.003 + 0.014 * lv.serratus) * def * V.serratus * (fem and 0.5 or 1)
	local latH = (0.012 + 0.085 * lv.lats) * pv.taper * flat
	local trapH = (0.012 + 0.085 * lv.traps) * V.trapSlope * (fem and 0.7 or 1)
	-- the back carries as much relief as the front: the trapezius diamond, the muscles over the shoulder
	-- blades, the erector columns either side of a real spine groove (a smooth plane reads as a box)
	local backK = fem and 0.75 or 1
	local trapBackH = (0.015 + 0.07 * lv.traps + 0.03 * lv.upperBack) * flat * backK
	local scapH = (0.02 + 0.09 * lv.upperBack + 0.03 * lv.rearDelt) * flat * backK
	local erecH = (0.02 + 0.1 * lv.lowerBack) * flat * backK
	local spineD = (0.025 + 0.035 * def) * (0.6 + 0.4 * lv.lowerBack)
	local spineW = 0.07 / xS
	local clavH = 0.008 + 0.018 * lean * (fem and 0.8 or 1)
	local ribH = 0.006 + 0.012 * lean
	local scmH = (0.012 + 0.03 * lv.neckSCM) * (fem and 0.6 or 1)
	local bellyH = 0.3 * fk ^ 1.4 * (hz / 0.5) * (fem and 0.6 or 1)
	local handleH = 0.11 * fk * pv.waist
	-- breasts (under the sports top)
	local breastH = fem and (0.21 + 0.08 * min(fk + 0.3, 1)) * hzK or 0
	local yN = sk.yN
	local rn = prof.rn
	-- sternocleidomastoid: mastoid (behind the ear, up the neck) -> sternal head (by the notch)
	local zcTop = prof.zc(1.2)
	local scmTop = { 0.74 * rn, yN + 0.29, zcTop + 0.3 * prof.rz }
	local scmBot = { 0.15 * rn, yW + 0.975 * H, -0.95 * prof.F(0.975) * hz }
	local baseDef = 0.25 + 0.75 * def -- separations everyone shows a little of
	-- the Head's neck in body space (its centre line is the Neck joint's; the ellipse is r wide, rz deep)
	local hn = prof.hn
	local hnZ = hn and (hn.z + ((sk.center and sk.center.Head) and sk.center.Head[3] or 0)) or 0
	local hnE = hn and hn.r / max(1e-3, hn.rz) or 1

	local function field(i, x, y, z, nx, ny, nz, detail)
		local u = (y - yW) / H
		local ax = abs(x)
		local s = x < 0 and -1 or 1
		local fx = ax / xS
		local sk1 = sideK[s]
		local wU = W(u) * xS
		local front = smooth(-0.05, 0.55, -nz)
		local backF = smooth(-0.05, 0.55, nz)
		local d = 0
		local groove, crown = 0, 0
		-- pectoralis major (men) ------------------------------------------------
		if not fem and u > 0.32 and u < 1.0 and fx < 1.05 and nz < 0.35 then
			local ub = pecBorder(fx) + pecDrop
			-- toward the armpit the border climbs steeply across sparse columns: a softer edge there (the
			-- armpit fold is a soft roll anyway) so it never stair-steps
			local edge = pecEdge * (1 + 1.8 * smooth(0.62, 0.95, fx))
			local inside = smooth(ub - edge, ub + edge, u)
			if inside > 0 then
				-- the upper border runs diagonally from the clavicle by the sternum down to the front deltoid
				local topU = 0.955 - 0.11 * fx
				local top = 1 - smooth(topU - 0.07, topU + 0.03, u)
				local upper = lerp(1, upperK, smooth(ub + 0.08, 0.86, u))
				local med = smooth(0.012, 0.1 + 0.14 * max(fk, 1 - def), fx)
				local lat = 1 - smooth(0.84, 1.03, fx)
				local swell = 0.72 + 0.28 * bell((fx - 0.5) / 0.48)
				-- the full lower shelf under the nipple line; toward the sternum and the armpit it fades
				local shelf = 1 + 0.45 * bell((u - (ub + 0.075)) / 0.1) * bell((fx - 0.42) / 0.34)
				local face = smooth(-0.35, 0.3, -nz)
				local w = inside * top * upper * med * lat * swell * shelf * face
				if detail then
					-- the fan of fibres converging on the armpit insertion: faint light / dark striations
					local au = math.atan2(u - 0.8, 0.98 - fx)
					ch.fibre[i] = (0.5 + 0.5 * cos(au * 26)) * w * def * smooth(0.15, 0.4, fx)
				end
				local h = pecH * sk1 * w
				d += h
				ch.pec[i] = h
				-- the crease under the pec and the sternal valley shade; the crown catches light
				groove += bell((u - ub) / (edge * 2.6)) * smooth(0.06, 0.2, fx) * lat * face * baseDef * min(1, pecH / 0.05)
					* (1 - 0.85 * smooth(0.6, 0.95, fx))
				groove += (1 - smooth(0.0, 0.09, fx)) * smooth(0.5, 0.62, u) * (1 - smooth(0.85, 0.95, u)) * 0.5 * baseDef
				crown += w * 0.6
				-- the deltopectoral groove: a diagonal line from under the clavicle down toward the armpit
				local dpU = 0.9 - (fx - 0.86) * 2.4
				groove += bell((u - dpU) / 0.035) * smooth(0.8, 0.88, fx) * (1 - smooth(0.97, 1.02, fx)) * face * 0.45 * baseDef
			end
		end
		-- breasts under a compression top (women) --------------------------------
		if fem and u > 0.38 and u < 0.95 and fx < 0.95 then
			-- fuller below, a defined underbust crease (the top binds them: one shelf with a shallow valley)
			local du = u - 0.585
			local w = bell2((fx - 0.4) / 0.42, du < 0 and du / 0.15 or du / 0.25) * smooth(-0.4, 0.3, -nz)
			local valley = 1 - 0.3 * (1 - smooth(0.0, 0.16, fx))
			local h = breastH * w * valley
			d += h
			ch.pec[i] = h * 0.3
			groove += bell((u - 0.445) / 0.04) * smooth(0.1, 0.25, fx) * (1 - smooth(0.72, 0.86, fx)) * 0.8
		end
		-- rectus abdominis: two columns of pillow blocks --------------------------------
		if u > -0.34 and u < 0.56 and front > 0 then
			local cw = wU * lerp(0.35, 0.46, smooth(-0.2, 0.45, u))
			local xr = ax / cw
			if xr < 1.3 then
				local across = smooth(0.0, 0.2, xr) * (1 - smooth(0.76, 1.1, xr))
				local rows = rowsS[s]
				local along = 0
				-- the intersections curve up toward the sides and tilt a little per boxer
				local uu = u - 0.022 * xr * xr + V.abTilt * (xr - 0.5)
				for k = 1, 4 do
					local lo, hi = rows[k], rows[k + 1]
					if uu > lo and uu < hi then
						local g = (k == 1 and abGap * 1.5 or abGap) / (hi - lo)
						local t = (uu - lo) / (hi - lo)
						-- a pillow: full in the middle, rounding into the grooves
						along = smooth(0, g, t) * (1 - smooth(1 - g, 1, t)) * (0.7 + 0.3 * sin(pi * t)) * (k == 4 and 0.85 or 1)
						break
					end
				end
				-- the rectus disappears under the pecs / ribcage at the top
				local topFade = 1 - smooth(0.42, 0.56, u)
				local w = across * front * topFade
				local h = (absBand + absH * along) * w
				d += h
				ch.abs[i] = h
				-- separations: the linea alba, the intersections, the semilunar line
				local la = (1 - smooth(0.0, 0.22, xr)) * smooth(-0.1, 0.05, u) * topFade
				local inter = (1 - along) * across * topFade * smooth(-0.05, 0.08, u)
				local semi = bell((xr - 1.0) / 0.22) * smooth(-0.1, 0.1, u) * (1 - smooth(0.4, 0.55, u))
				groove += (la * 0.55 + inter * 0.38 * (0.25 + 0.75 * def) + semi * 0.4) * front * baseDef * min(1, (absH + absBand) / 0.025)
				crown += along * across * topFade * 0.5 * def
			end
		end
		-- the ribcage's lower edge (costal margin): the chest sits a little proud of the belly --------
		if u > 0.12 and u < 0.56 and fx < 0.95 and front > 0 then
			local um = 0.47 - 0.34 * fx
			local above = smooth(um - 0.03, um + 0.03, u) * (1 - smooth(0.5, 0.58, u))
			d += ribH * above * front
			groove += bell((u - um + 0.02) / 0.04) * smooth(0.25, 0.4, fx) * (1 - smooth(0.75, 0.9, fx)) * front * 0.35 * baseDef
		end
		-- external obliques: the flank roll over the hip and the muscle over the lower ribs ----
		if u > -0.3 and u < 0.5 and fx > 0.35 then
			local w = bell2((ax - 0.9 * wU) / (0.42 * wU), (u - 0.1) / 0.32) * smooth(-0.6, 0.0, -nz + 0.2) * smooth(-0.2, 0.4, abs(nx) + 0.3)
			local h = oblH * w * sk1
			d += h
			ch.obl[i] = h
			crown += w * 0.25 * def
		end
		-- serratus anterior: fingers on the side of the ribcage under the armpit ---------
		if serH > 0.001 and u > 0.42 and u < 0.78 and fx > 0.55 then
			local band = bell((ax / wU - 0.9) / 0.13) * smooth(-0.5, 0.1, -nz)
			if band > 0 then
				-- three or four ridges stepping down and forward
				local ph = (u - 0.45) / 0.085 + (z / hz) * 0.9
				local ridge = 0.5 + 0.5 * cos(ph * TAU)
				local env = bell((u - 0.6) / 0.18)
				d += serH * band * env * ridge
				groove += band * env * (1 - ridge) * 0.6 * def
			end
		end
		-- latissimus dorsi: the wing from the armpit to the lower back (V-taper), mostly on the side ----
		if u > 0.0 and u < 0.9 and fx > 0.3 then
			local w = bell((u - 0.6 - V.latLow) / 0.32) * smooth(0.4, 0.82, fx) * smooth(-0.45, 0.1, nz) * (0.45 + 0.55 * smooth(0.2, 0.8, abs(nx)))
			local h = latH * w * sk1
			d += h
			ch.lat[i] = h
			-- the lat's front edge under the armpit (seen from the front: the V line)
			groove += bell((nz + 0.1) / 0.25) * smooth(0.5, 0.75, u) * (1 - smooth(0.78, 0.86, u)) * 0.35 * def * min(1, latH / 0.05)
			crown += w * 0.3 * def
		end
		-- trapezius: the slope from the neck to the shoulder ------------------------------
		if u > 0.8 and fx < 1.0 then
			-- (it stops at the Neck pivot: above it the Head's neck shows; the back sheet below still climbs the nape)
			local w = bell2((fx - 0.38) / 0.6, (u - 0.99) / 0.15) * smooth(-0.6, 0.3, ny + 0.4 * nz) * (1 - smooth(0.995, 1.03, u))
			local h = trapH * w
			d += h
			ch.trap[i] = h
			crown += w * 0.3
		end
		-- ... up the back of the neck to the skull (one smooth sheet, no step at the neck base)
		if u > 0.8 and nz > -0.25 then
			local w = (1 - smooth(0.25, 0.7, fx)) * bell((u - 1.02) / 0.22) * smooth(-0.25, 0.55, nz) * (1 - smooth(0.97, 1.0, u))
			d += trapH * 0.5 * w
			ch.trap[i] += trapH * 0.5 * w
		end
		-- mid / lower trapezius diamond and the scapular muscles on the upper back ------
		if backF > 0 and u > 0.35 then
			local dia = fx / 0.46 + abs(u - 0.78) / 0.36
			local w = (1 - smooth(0.55, 1.05, dia)) * backF
			d += trapBackH * w
			ch.trap[i] += trapBackH * w * 0.5
			-- infraspinatus / teres over each shoulder blade; the blade's inner edge is a soft valley
			local sc = bell2((fx - 0.56) / 0.25, (u - 0.72) / 0.15) * backF
			d += scapH * sc
			crown += sc * 0.3 * def
			groove += bell((fx - 0.32) / 0.07) * smooth(0.55, 0.65, u) * (1 - smooth(0.86, 0.95, u)) * backF * 0.5 * baseDef
			-- the blade's lower corner and the teres bump toward the armpit
			groove += bell2((fx - 0.5) / 0.14, (u - 0.58) / 0.04) * backF * 0.3 * baseDef
			-- defined backs: the lower trapezius' edge (the diamond's lower half) and the teres / lat border running
			-- from under the armpit down toward the spine
			groove += bell((dia - 0.92) / 0.1) * (u < 0.78 and 1 or 0.35) * smooth(0.06, 0.16, fx) * backF * 0.4 * def
			local uLine = 0.5 + (fx - 0.45) * 0.34
			groove += bell((u - uLine) / 0.03) * smooth(0.42, 0.56, fx) * (1 - smooth(0.88, 0.98, fx)) * backF * 0.35 * def
		end
		-- erector spinae columns and the spine groove -------------------------------
		if backF > 0 and u < 0.62 then
			local w = bell((fx - 0.12) / 0.09) * (1 - smooth(0.3, 0.62, u)) * backF
			d += erecH * w
			crown += w * 0.3 * def
			-- their outer edges: the lower back's two columns
			groove += bell((fx - 0.235) / 0.045) * (1 - smooth(0.22, 0.5, u)) * backF * 0.35 * def * min(1, erecH / 0.03)
		end
		if backF > 0 and u < 1.0 then
			local w = (1 - smooth(0.0, spineW, fx)) * backF * (1 - smooth(0.9, 1.0, u))
			local depth = spineD * lerp(1, 0.45, smooth(0.3, 0.8, u))
			d -= depth * w
			groove += w * 0.7 * baseDef
		end
		-- clavicles and the hollow above them ----------------------------------------
		if u > 0.88 and u < 1.04 and fx < 0.98 and nz < 0.2 then
			local cu = 0.952 - 0.025 * fx + 0.012 * sin(pi * fx)
			local face = smooth(-0.3, 0.3, -nz + 0.4 * ny)
			local ridge = bell((u - cu) / 0.018) * smooth(0.04, 0.12, fx) * (1 - smooth(0.82, 0.95, fx)) * face
			d += clavH * ridge
			local hollow = bell2((fx - 0.45) / 0.27, (u - cu - 0.032) / 0.03) * face * (0.4 + 0.6 * lean)
			d -= 0.012 * hollow
			groove += hollow * 0.6 + bell((u - cu + 0.025) / 0.02) * smooth(0.1, 0.2, fx) * (1 - smooth(0.7, 0.9, fx)) * face * 0.25
			crown += ridge * 0.8 * (0.3 + 0.7 * lean)
		end
		-- neck: sternocleidomastoids (the V to the notch), the notch, the larynx ---------
		-- (above the Neck pivot the visible neck is the Head's, with its own sternocleidomastoids and larynx: the
		-- column there is a smooth filler inside it, so nothing pushes outward above u ~1)
		if u > 0.9 then
			local below = 1 - smooth(0.99, 1.015, u)
			local dist, t = Kit.segDist(ax, y, z, scmTop[1], scmTop[2], scmTop[3], scmBot[1], scmBot[2], scmBot[3])
			local r = 0.085 * rn / 0.35
			if dist < r * 1.6 then
				local w = bell(dist / (r * 1.6)) * (0.55 + 0.45 * smooth(0.0, 0.5, t)) * smooth(0.93, 0.97, u) * below
				d += scmH * w
				crown += w * 0.4
				groove += bell((dist - r * 1.1) / (r * 0.5)) * 0.25 * smooth(0.94, 0.98, u) * below
			end
			local notch = bell2(ax / (0.15 * rn), (u - 0.985) / 0.03) * front
			d -= 0.018 * notch
			groove += notch * 0.8
			if not fem then
				local lar = bell2(ax / (0.22 * rn), (y - (yN + 0.12)) / 0.07) * front * below
				d += 0.02 * lar
				crown += lar * 0.4
			end
		end
		-- fat: belly, love handles, a softer back --------------------------------------
		if fk > 0 then
			local b = bell2(fx / 0.8, (u - 0.13) / 0.42) * front
			local hh = bell((u - 0.06) / 0.24) * smooth(0.55, 0.92, fx) * smooth(-0.6, 0.1, nz)
			local bk = bell2(fx / 0.9, (u - 0.15) / 0.3) * backF
			-- (the overall layer stops at the Neck pivot: above it the visible neck is the Head's)
			local h = bellyH * b + handleH * hh + 0.035 * fk * bk + 0.025 * fk * (1 - smooth(0.985, 1.01, u))
			d += h
			ch.belly[i] = bellyH * b
		end
		-- breathing: the ribcage
		ch.rib[i] = bell((u - 0.55) / 0.42) * (0.4 + 0.6 * front)
		-- the shoulder girdle when the arm goes up (AnatomyBody's raise / reach shapes, BodyFX drives them from
		-- the shoulder angle): the trapezius slope and the top of the shoulder lift, the front of the shoulder
		-- comes forward
		ch.raise[i] = smooth(0.3, 0.78, fx) * smooth(0.74, 0.9, u) * (1 - smooth(1.0, 1.1, u))
		ch.reach[i] = smooth(0.45, 0.85, fx) * smooth(0.6, 0.82, u) * (1 - smooth(0.98, 1.06, u))
		-- above the Neck pivot the column is a filler inside the Head's neck (AnatomySkull.Neck): at the front and
		-- the sides nothing may push it out of that neck, which is the visible one there
		if hn and d > 0 and u > 0.985 then
			local ez = (z - hnZ) * hnE
			local room = max(0, hn.r - 0.006 - sqrt(x * x + ez * ez))
			if d > room then
				d -= (d - room) * smooth(0.985, 1.0, u)
			end
		end
		-- ... and the trapezius slope (lifted along its upward normal by big traps and fat) meets that neck at
		-- the pivot: beside the neck, front and sides, it tops out under a line falling from 0.03 above the
		-- pivot at the neck (a soft ceiling; the nape sheet behind still climbs to the skull)
		if hn and d > 0 and ny > 0.25 and u > 0.88 and u < 1.0 then
			local dz = z + nz * d - hnZ
			local ex = x + nx * d
			local e = sqrt(ex * ex + dz * dz * hnE * hnE)
			local back = smooth(0.3, 0.7, dz / max(e, 1e-3))
			local cap = (yN + 0.03 - 0.25 * max(0, e - hn.r) - y) / ny
			if d > cap and back < 1 then
				local soft = max(0, cap) + 0.008 * (1 - math.exp(-(d - max(0, cap)) / 0.008))
				d -= (d - min(d, soft)) * (1 - back)
			end
		end
		ch.groove[i] = clamp(groove, 0, 1)
		ch.crown[i] = clamp(crown, 0, 1)
		return d
	end
	return field, ch
end
Torso.Field = torsoField

------------------------------------------------------------------------
-- UpperTorso mesh (body space)
------------------------------------------------------------------------
function Torso.Upper(sk, P, lod, opt)
	opt = opt or {}
	local R = Torso.RES[lod] or Torso.RES.full
	local prof = Torso.Profiles(sk, P)
	local xS, H, yW, hz = sk.xS, sk.H, sk.yW, sk.hz
	local W, F, K, nF, nB, zc = prof.W, prof.F, prof.K, prof.nF, prof.nB, prof.zc
	local u0 = -0.22 / H -- 0.22 studs under the waist pivot (inside the trunks / LowerTorso)
	-- the neck column runs up inside the Head's neck to where that neck starts to round into the skull base
	-- (AnatomySkull.Neck yTop), at most 0.3 above the pivot: any higher, its top shows through at the nape
	local top = 0.3
	local hn, hc = prof.hn, sk.center and sk.center.Head
	if hn and hc and tonumber(hn.yTop) then
		top = clamp(hc[2] + hn.yTop - sk.yN + 0.02, 0.1, 0.3)
		-- a head lifted off the shoulders (Neck C1 below the head's base) shows its own neck down to the
		-- pivot: the column only needs to reach a little way into it
		local hs = sk.size and sk.size.Head
		local lift = hs and (hc[2] - sk.yN - 0.5 * hs[2]) or 0
		if lift > 0.02 then
			top = min(top, 0.12)
		end
	end
	local u1 = 1 + top / H
	-- ring heights: equal steps along the silhouette's arc (the shoulder tops and the neck base get the rings
	-- their fast change needs), a little denser over the chest and abs
	local N = 160
	local acc, us = { 0 }, { u0 }
	local pw, pf, pk = W(u0) * xS, F(u0) * hz, K(u0) * hz
	for k = 1, N do
		local u = u0 + (u1 - u0) * k / N
		local w, f, kk = W(u) * xS, F(u) * hz, K(u) * hz
		local dy = (u1 - u0) * H / N
		local ds = sqrt(dy * dy + (w - pw) ^ 2 + 0.35 * ((f - pf) ^ 2 + (kk - pk) ^ 2))
		local imp = 1 + 0.25 * bell((u - 0.35) / 0.4) - 0.3 * smooth(1.08, 1.15, u)
		acc[k + 1] = acc[k] + ds * imp
		us[k + 1] = u
		pw, pf, pk = w, f, kk
	end
	local rings = R.rings
	local U = table.create(rings)
	local spine = table.create(rings)
	local j = 1
	for i = 1, rings do
		local target = acc[N + 1] * (i - 1) / (rings - 1)
		while j < N + 1 and acc[j + 1] < target do
			j += 1
		end
		local a0, a1 = acc[j], acc[min(j + 1, N + 1)]
		local t = a1 > a0 and (target - a0) / (a1 - a0) or 0
		local u = us[j] + (us[min(j + 1, N + 1)] - us[j]) * clamp(t, 0, 1)
		U[i] = u
		spine[i] = { 0, yW + u * H, zc(u) }
	end
	local warp = Kit.FrontWarp(R.warp)
	local tuckU = opt.trunks and Torso.BAND_TOP / H or nil
	local m = MeshKit.New("UpperTorso")
	local capD = 0.12
	local info = Kit.GridLoft(m, MeshKit, {
		rings = rings, sides = R.sides, spine = spine, exact = true, rowB = U,
		capS = { depth = capD, rings = R.dome, bDepth = capD / H }, capE = { depth = capD, rings = R.dome, bDepth = capD / H },
		section = function(t, a)
			local i = math.floor(t * (rings - 1) + 0.5) + 1
			local u = U[i]
			local aw = warp(a)
			local c, s = cos(aw), sin(aw)
			local wx = W(u) * xS
			local n = s >= 0 and nF(u) or nB(u)
			local e = 2 / n
			local x = wx * (c < 0 and -1 or 1) * abs(c) ^ e
			local f
			if s >= 0 then
				f = F(u) * hz * s ^ e
			else
				f = -K(u) * hz * (-s) ^ e
			end
			if tuckU then
				-- inside the waistband: rounder and smaller, so a twisted waist never pokes through it
				local k = smooth(tuckU - 0.004, tuckU - 0.08, u)
				x *= 1 - 0.2 * k
				f *= 1 - 0.1 * k
			end
			return x, f
		end,
	})
	Kit.GridNormals(m, MeshKit, info)
	-- the undisplaced surface: the colour texture evaluates the same brushes per texel there
	local P0, N0 = table.clone(m.P), table.clone(m.N)
	local field, ch = torsoField(sk, P, prof, m.nv)
	if tuckU then
		-- nothing sculpted under the waistband (and no blend shape pushes through it)
		local inner = field
		field = function(i, x, y, z, nx, ny, nz, detail)
			local d = inner(i, x, y, z, nx, ny, nz, detail)
			-- the sculpting eases off just above the band's top edge (the elastic holds the belly in), so the
			-- skin meets the band inside it instead of lapping over it
			local k = smooth(tuckU - 0.02, tuckU + 0.07, (y - yW) / H)
			if k < 1 then
				for _, arr in pairs(ch) do
					if arr ~= ch.groove and arr ~= ch.crown then
						arr[i] = (arr[i] or 0) * k
					end
				end
			end
			return d * k
		end
	end
	MeshKit.Displace(m, field)
	if opt.top then
		-- the sports top a few millimetres off the skin: fabric over the body, not paint on it (the step at
		-- its border eases over a lattice cell or two; a hem ridge narrower than the lattice caught some
		-- vertices and missed others, a string of beads along every diagonal border: the hem is painted)
		MeshKit.Displace(m, function(i, x, y, z)
			local w = Torso.TopMask(sk, x, y, z, 1)
			return 0.007 * w
		end)
	end
	Kit.GridNormals(m, MeshKit, info)
	return m, { prof = prof, ch = ch, loft = info, U = U, field = field, P0 = P0, N0 = N0 }
end

------------------------------------------------------------------------
-- LowerTorso mesh (body space): pelvis, glutes; with trunks the seat of the satin trunks and the waistband
------------------------------------------------------------------------
-- opt.trunks: the waistband (top edge a little above the waist pivot, proud of the skin) and a loose seat
function Torso.Lower(sk, P, lod, prof, opt)
	opt = opt or {}
	local R = Torso.RES[lod] or Torso.RES.full
	local fem = P.female
	local lv, fk = P.lv, min(P.fatK, 1.2)
	local xS, hz, yW = sk.xS, sk.hz, sk.yW
	local yH, xH = sk.yH, sk.xH
	local ul = sk.size.RightUpperLeg
	local trunks = opt.trunks
	local ease = trunks and 0.03 or 0
	local thighR = 0.48 * ul[1] * (1 + 0.06 * lv.quads)
	-- (women: a clear waist-to-hip curve, front and back)
	local hipW = (xH + thighR) * (fem and 1.2 or 1) * (1 + 0.06 * P.sl.waist * P.pv.waist) + 0.06 * fk + ease
	-- with trunks the seat is at least as wide / deep as the satin legs' tops (opt.legTop: x, front, back),
	-- so a leg never steps out of the seat
	local legTop = trunks and opt.legTop or nil
	if legTop then
		-- the seat hangs from the hips into the legs at exactly their width: never narrower (a leg would step
		-- out of it) and never wider (a shelf / tutu ledge over the legs' tops)
		hipW = legTop[1] + 0.002
	end
	local waistW = prof.W(0.0) * xS * 1.015 + 0.02 * fk + ease
	local drop = (yW - yH) -- LowerTorso height
	-- the bottom: with trunks the seat ends just under the hip pivots on the satin legs (they carry the
	-- trunks from there down, their inner faces meeting on the midline); without, the crotch
	-- (with the legs' tops given, the seat's section over the legs is the legs' own rings a hair outside them
	-- down to its open rim (Limbs.SEAT_RIM under the hip pivots), closed by a flat cap inside the legs; above
	-- the rim the legs taper in fast, hidden inside. One surface from the band to the hem: no step at the rim,
	-- no curl under it, no surfaces crossing at a shallow angle. A seat a hair outside the legs that curled
	-- under at its rim read as a skirt over two tubes: the down-facing curl took the baked 'down' shade, a
	-- dark line right under the hip on every character; a seat running on down inside the legs showed the
	-- shallow crossing as a crease and a shelf wherever its own shape left the legs' rings)
	local rim = legTop and legTop[8] or 0.1
	local bot = trunks and legTop and (yH - rim) or (yH - (trunks and 0.2 or 0.3) * (drop / 0.4) ^ 0.5)
	local Fw, Kw = prof.F(0.0) * hz + ease, prof.K(0.0) * hz + ease
	local hipF, hipK = Fw * 0.97, Kw * 0.96
	if legTop then
		hipF, hipK = max(hipF, legTop[2] + 0.002), max(hipK, legTop[3] + 0.002)
	end
	local top, bandBot = yW + 0.015, nil
	local Wc, Fc, Kc
	local Ys
	local rings = R.ltRings
	local yS = yH + 0.05 -- the seat's full section (above the legs' tops)
	if trunks then
		-- the band: the waist's own section plus the elastic's thickness, a lip over the seat below it
		top = yW + Torso.BAND_TOP
		bandBot = yW - 0.17 * (drop / 0.4) ^ 0.5
		local bw, bf, bk = waistW + 0.01, Fw + 0.012, Kw + 0.012
		local sw = lerp(hipW, waistW, 0.85)
		local lx, lf, lk = hipW, hipF, hipK
		if legTop then
			-- (the legs' front / back extents measured from the seat's own centre line)
			local dz = 0.02 * hz - (legTop[5] or 0.02 * hz)
			lx, lf, lk = legTop[1], legTop[2] + dz, legTop[3] - dz
			hipF, hipK = max(hipF, lf + 0.002), max(hipK, lk + 0.002)
		end
		-- (with the legs' tops given the curves only shape the seat above yS: over the legs it follows their rings)
		Wc = Kit.Curve(legTop and { { bot, lx }, { yS, hipW }, { bandBot - 0.03, sw }, { bandBot - 0.0005, sw - 0.004 }, { bandBot, bw }, { top, bw } } or { { bot, lx - 0.035 }, { yS, hipW }, { bandBot - 0.03, sw }, { bandBot - 0.0005, sw - 0.004 }, { bandBot, bw }, { top, bw } })
		Fc = Kit.Curve(legTop and { { bot, lf }, { yS, hipF }, { bandBot - 0.0005, max(Fw * 0.985, (hipF + Fw) / 2) }, { bandBot, bf }, { top, bf } } or { { bot, lf - 0.03 }, { yH - 0.045, lf - 0.012 }, { yS, hipF }, { bandBot - 0.0005, max(Fw * 0.985, (hipF + Fw) / 2) }, { bandBot, bf }, { top, bf } })
		Kc = Kit.Curve(legTop and { { bot, lk }, { yS, hipK }, { bandBot - 0.0005, max(Kw * 0.965, (hipK + Kw) / 2) }, { bandBot, bk }, { top, bk } } or { { bot, lk - 0.03 }, { yH - 0.045, lk - 0.012 }, { yS, hipK }, { bandBot - 0.0005, max(Kw * 0.965, (hipK + Kw) / 2) }, { bandBot, bk }, { top, bk } })
		local list
		if rings >= 10 then
			list = { bot, lerp(bot, yS, 0.35), lerp(bot, yS, 0.7), yS, yS + 0.3 * (bandBot - yS), yS + 0.62 * (bandBot - yS), bandBot - 0.03, bandBot - 0.012, bandBot, (bandBot + top) / 2, top }
		elseif rings >= 7 then
			list = { bot, (bot + yS) / 2, yS, yS + 0.45 * (bandBot - yS), bandBot - 0.012, bandBot, top }
			if rings >= 8 then
				table.insert(list, #list, (bandBot + top) / 2)
			end
		else
			list = { bot, yS, bandBot - 0.012, bandBot, top }
		end
		rings = #list
		Ys = list
	else
		Wc = Kit.Curve({ { bot, hipW * 0.72 }, { yH - 0.14, hipW * 0.93 }, { yH + 0.06, hipW }, { yH + 0.5 * drop, lerp(hipW, waistW, 0.55) }, { top, waistW } })
		Fc = Kit.Curve({ { bot, Fw * 0.55 }, { yH - 0.1, Fw * 0.86 }, { yH + 0.12, Fw * 0.95 }, { top, Fw * 1.0 } })
		Kc = Kit.Curve({ { bot, Kw * 0.75 }, { yH - 0.1, Kw * 1.0 }, { yH + 0.15, Kw * 1.02 }, { top, Kw } })
		Ys = table.create(rings)
		for i = 1, rings do
			local t = (i - 1) / (rings - 1)
			-- denser near the bottom where the seat rounds off
			Ys[i] = bot + (top - bot) * (t ^ 1.15)
		end
	end
	local spine = table.create(rings)
	for i = 1, rings do
		spine[i] = { 0, Ys[i], 0.02 * hz }
	end
	local m = MeshKit.New("LowerTorso")
	local seatSq = trunks and legTop ~= nil
	-- the satin legs' ring sides and each leg's ring by body height and ring angle (radius and the body-space
	-- centre it is measured from; the left leg's own: the dominant side's thigh is a little fuller)
	local legSides, legR, legRL = seatSq and legTop[6] or 0, seatSq and legTop[7] or nil, seatSq and (legTop[9] or legTop[7]) or nil
	local spineZ = 0.02 * hz
	-- the seat's vertices are the legs' own ring vertices when the side counts match (below: every leg
	-- vertex but its medial face's, plus one on the midline where the two legs' fronts / backs meet): a satin
	-- leg is a coarse polygon (Limbs.RES sides), and a seat vertex anywhere else on the smooth curve stood out
	-- between the leg's vertices, or let a leg's corner vertex out
	local aligned = seatSq and R.ltSides == 2 * (legSides - 2)
	-- how far outside the legs' rings the seat runs over them: a hair (a seat chord across an unaligned leg
	-- vertex needs a little more, its sagitta)
	local off = aligned and 0.002 or 0.006
	local yTop = Ys[#Ys]
	-- the crotch: with trunks a deeper rounded gusset between the legs (the satin bridges the thighs, no V);
	-- on the legs' rings a flat cap inside the legs (a dome under the rim showed as a dark curl)
	local botD = trunks and (legTop and 0 or 0.2 * (drop / 0.4) ^ 0.5) or 0.14
	-- the seat's section over the satin legs at body height y, ring angle a: the two legs' own sections at that
	-- height side by side (their exact radius by angle round each leg's bone, off further out) with a flat
	-- bridge between them, the gusset. A superellipse of its own never fitted the legs: squarer than them it
	-- stood out past their corners, rounder their corners stood out of it, and the thigh's muscle bulging
	-- through the satin made every leg a little different anyway
	local function legSection(y, a)
		local a0 = a % TAU
		local n = legSides
		local step = TAU / n
		if aligned then
			-- seat vertex j -> a leg and its own ring angle: round the right leg from its lateral line forward to
			-- its front medial corner (the last vertex before its medial face), a vertex on the midline at that
			-- corner's depth (where the two legs' fronts meet), round the left leg (its own angle, mirrored) from
			-- its front corner to its back corner, the midline again, and round the right leg's back to its
			-- lateral line: twice the leg's sides less four vertices, the medial faces' own left out (hidden
			-- between the legs: a midline vertex at one of them notched the seat's front and back)
			local j = math.floor(a0 / (TAU / R.ltSides) + 0.5) % R.ltSides
			local half = n / 2 - 1
			local sd, la, mid
			if j < half then
				sd, la = 1, j * step
			elseif j == half then
				sd, la, mid = 1, (half - 1) * step, true
			elseif j < 3 * n / 2 - 3 then
				sd, la = -1, (2 * half - j) * step
			elseif j == 3 * n / 2 - 3 then
				sd, la, mid = -1, (1 - half) * step, true
			else
				sd, la = 1, (j - 3 * n / 2 + 3 - half) * step
			end
			local r, cx2, cz2 = (sd < 0 and legRL or legR)(y, la)
			r += off
			local a2 = sd < 0 and pi - la or la
			local x = mid and 0 or abs(cx2) * sd + r * cos(a2)
			return x, spineZ - cz2 + r * sin(a2)
		end
		-- (other side counts: the seat's vertices stay evenly spaced on the legs' chords, a bridge between the
		-- legs from each one's last lateral vertex to the middle, a hair proud of their fronts)
		local c0 = 0.5
		local function pt(a2)
			local c2, s2 = cos(a2), sin(a2)
			local g = smooth(-c0, c0, c2) * 2 - 1
			-- (the left leg's ring, mirrored, on the left; the bridge runs between the legs' centres)
			local r, cx2, cz2 = (c2 < 0 and legRL or legR)(y, c2 < 0 and pi - a2 or a2)
			r += off + 0.004 * (1 - abs(g))
			return abs(cx2) * g + r * c2, spineZ - cz2 + r * s2
		end
		local j = math.floor(a0 / step)
		local x0, f0 = pt(j * step)
		local x1, f1 = pt((j + 1) * step)
		local w = (a0 - j * step) / step
		return x0 + (x1 - x0) * w, f0 + (f1 - f0) * w
	end
	local info = Kit.GridLoft(m, MeshKit, {
		rings = rings, sides = R.ltSides, spine = spine, exact = true, rowB = Ys,
		capS = { depth = botD, rings = seatSq and 0 or R.ltDome, bDepth = botD },
		-- with trunks the top is the waistband's lip: a flat cap inside the torso
		capE = trunks and { depth = 0, rings = 0, bDepth = 0 } or { depth = 0.14, rings = R.ltDome, bDepth = 0.14 },
		section = function(t, a)
			local i = math.floor(t * (rings - 1) + 0.5) + 1
			local y = Ys[i]
			local c, s = cos(a), sin(a)
			local e = 2 / 2.4
			local x = Wc(y) * (c < 0 and -1 or 1) * abs(c) ^ e
			local f = s >= 0 and Fc(y) * s ^ e or -Kc(y) * (-s) ^ e
			if seatSq and legR then
				-- over the legs their own sections; up toward the band blending into the waist's own
				local k = smooth(yS, yTop - 0.06, y)
				if k < 1 then
					local lx2, lf2 = legSection(y, a)
					x, f = lerp(lx2, x, k), lerp(lf2, f, k)
				end
			end
			return x, f
		end,
	})
	Kit.GridNormals(m, MeshKit, info)
	local gH = (0.05 + 0.13 * lv.glutes) * P.pv.flat + (fem and 0.06 or 0) + 0.06 * fk
	local bellyH = 0.16 * fk ^ 1.5 * (fem and 0.6 or 1)
	local crown = table.create(m.nv, 0)
	local glute = table.create(m.nv, 0)
	local bandY = bandBot or math.huge
	MeshKit.Displace(m, function(i, x, y, z, nx, ny, nz)
		if y >= bandY - 0.006 then
			return 0 -- the band stays a clean ring
		end
		local ax = abs(x)
		local d = 0
		-- (the seat over the legs' tops is the legs' own rings: no sculpt there (a glute or fold pushed out stood
		-- proud of the satin legs, a dent let a leg out); every brush eases out over the hip line instead)
		local lowK = seatSq and smooth(yS, yS + 0.08, y) or 1
		-- glutes: two rounded masses behind the hips, fullest a little under the hip pivots
		local g = bell3((ax - 0.62 * xH - 0.05) / (0.58 * hipW), (y - (yH - 0.02)) / 0.36, 0) * smooth(-0.1, 0.5, nz) * (trunks and (1 - smooth(yH + 0.05, bandY - 0.03, y)) or 1) * lowK
		-- (under the satin a softer push: a full seat reads as an inflated diaper)
		d += gH * g * (trunks and 0.22 or 1)
		glute[i] = gH * g
		crown[i] = g * 0.4
		-- the cleft between them (satin bridges it)
		d -= (trunks and 0.008 or 0.025) * (1 - smooth(0.0, 0.06, ax)) * smooth(0.2, 0.6, nz) * smooth(yH + 0.25, yH - 0.05, y)
		-- lower belly
		d += bellyH * bell2(ax / (0.8 * hipW), (y - (yW - 0.05)) / 0.3) * smooth(-0.1, 0.5, -nz)
		if trunks then
			-- satin drape: soft vertical folds from the band down, deeper toward the legs
			local a = math.atan2(-z, x)
			local hang = smooth(bandY - 0.02, yH, y)
			d += 0.011 * (sin(6 * a + 0.7) + 0.6 * sin(11 * a + 2.1)) * hang
		end
		return d * lowK
	end)
	Kit.GridNormals(m, MeshKit, info)
	if seatSq then
		-- the rim's normals lean as the satin legs' do just under it: their horizontal direction is the rim's
		-- own (its faces alone: averaged with the flat cap's inside the legs they tipped down, and the rim
		-- shaded as a fold line on the legs it lies on), their tilt the slope of the legs' section on down from
		-- the rim (the leg's own normal there averages its ring pair's short band with the chord to the next
		-- ring below); the seat's faces above the rim alone gave the thigh's widening above its fullest, a
		-- crease in the shading along the join at the sides
		local N = m.N
		local rimRow = info.rows[info.firstRing]
		local sides = R.ltSides
		for j = 0, rimRow.n - 1 do
			local v = rimRow.s + j
			local a = TAU * (j % sides) / sides
			local x0, f0 = legSection(bot, a)
			local x1, f1 = legSection(bot - 0.012, a)
			local x2, f2 = legSection(bot - 0.09, a)
			local nx, nz = N[v * 3 - 2], N[v * 3]
			local hl = sqrt(nx * nx + nz * nz)
			if hl > 1e-6 then
				nx, nz = nx / hl, nz / hl
				-- outward growth of the section along this normal going down (f is toward -z)
				local s1 = ((x1 - x0) * nx - (f1 - f0) * nz) / 0.012
				local s2 = ((x2 - x1) * nx - (f2 - f1) * nz) / 0.078
				local sl = 0.5 * (s1 + s2)
				local ny = sl / sqrt(1 + sl * sl)
				local hs = sqrt(max(0, 1 - ny * ny))
				N[v * 3 - 2], N[v * 3 - 1], N[v * 3] = nx * hs, ny, nz * hs
			end
		end
	end
	return m, { crown = crown, glute = glute, hipW = hipW, bot = bot, top = top, bandBot = bandBot, loft = info, rim = seatSq and info.rows[info.firstRing] or nil, seatTop = yS }
end
Torso.BAND_TOP = 0.035 -- waistband top edge above the waist pivot (studs)

-- the female sports top over the chest (the R15 UpperTorso was the top in round 1): band under the bust,
-- scoop neckline in front, racer back behind, wide straps. Returns the cover (0..1) and the hem band (0..1:
-- the elastic edge just inside the border, a smooth bump a few texels wide). soft scales every edge's width
-- (1 = the vertex colours' soft edge, ~0.6 = a crisp edge on the 192 texture, still two to three texels wide
-- round the torso: an edge one texel wide, with a one-texel hem line, came out of the bilinear filter as
-- stair steps and dots along every diagonal border)
function Torso.TopMask(sk, x, y, z, soft)
	local u = (y - sk.yW) / sk.H
	local fx = abs(x) / sk.xS
	-- the front scoop and the higher back line blend across the shoulder line (no step where z changes sign)
	local back = smooth(-0.08, 0.08, z)
	local function cover(k)
		local band = smooth(0.375 - 0.035 * k, 0.375 + 0.035 * k, u)
		-- front: a rounded scoop neckline (deepest at the sternum, rising in a U into the straps); the armhole
		-- (the straps' outer edge) follows the shoulder's slope, narrow over the top, curving out and down round
		-- the armpit to the side seam
		local q = clamp(fx / 0.44, 0, 1)
		local nl = 0.775 + 0.2 * q * q * (3 - 2 * q) + 0.12 * smooth(0.4, 0.6, fx)
		local neckline = 1 - smooth(nl - 0.04 * k, nl + 0.04 * k, u)
		local aF = 0.6 + 0.3 * smooth(0.92, 0.6, u)
		local front = neckline * (1 - smooth(aF - 0.05 * k, aF + 0.05 * k, fx))
		-- back: a racer back (the body of the top narrows to the spine between the shoulder blades, the straps
		-- run from there up and out over the trapezius to meet the front's)
		local aB = 0.2 + 0.7 * smooth(0.76, 0.56, u)
		local body = (1 - smooth(aB - 0.05 * k, aB + 0.05 * k, fx)) * (1 - smooth(0.8 - 0.03 * k, 0.8 + 0.03 * k, u))
		local fc = 0.14 + 0.37 * smooth(0.7, 0.95, u)
		local strap = (1 - smooth(0.085 - 0.03 * k, 0.085 + 0.03 * k, abs(fx - fc))) * smooth(0.62, 0.7, u)
		local backC = max(body, strap)
		return clamp(band * (front + (backC - front) * back), 0, 1)
	end
	local w = cover(soft)
	if w <= 0 then
		return 0, 0
	end
	-- (a full cover inside the border: no partial band of skin along the edges)
	w = clamp(w * 1.15, 0, 1)
	-- the hem: a bump just inside the border, read off a wide version of the same mask (it falls from 1 to 0
	-- across the border over several texels: the bump sits where it is still mostly on), so the line is as
	-- wide and as smooth as that falloff whatever the border's direction
	local wide = cover(max(soft, 0.6) + 1.0)
	return w, bell((wide - 0.72) / 0.28) * w
end

-- the waistband's front (body space, the same numbers Torso.Lower builds it from): centre of the band's
-- front at mid height, the band's top edge, and a point half way to the side on the band's surface
function Torso.BandFront(sk, P, prof)
	local yW, yH, hz = sk.yW, sk.yH, sk.hz
	local drop = yW - yH
	local top = yW + Torso.BAND_TOP
	local bandBot = yW - 0.17 * (drop / 0.4) ^ 0.5
	local ease = 0.03
	local waistW = prof.W(0.0) * sk.xS * 1.015 + 0.02 * min(P.fatK, 1.2) + ease
	local bw, bf = waistW + 0.01, prof.F(0.0) * hz + ease + 0.012
	local zc = 0.02 * hz
	local y = (top + bandBot) / 2
	-- the section is a superellipse x = W |cos|^e, f = F sin^e (e = 2 / 2.4): half way out, f = F * 0.9^e
	local e = 2 / 2.4
	local c = 0.5 ^ (1 / e)
	local f = bf * sqrt(1 - c * c) ^ e
	return { 0, y, zc - bf }, { 0, top, zc - bf }, { bw * 0.5, y, zc - f }
end

return Torso
