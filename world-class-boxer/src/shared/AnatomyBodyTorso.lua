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

local abs, min, max, sqrt, cos, sin, pi = math.abs, math.min, math.max, math.sqrt, math.cos, math.sin, math.pi
local clamp, smooth, lerp, bell, bell3, bell2 = Kit.clamp, Kit.smooth, Kit.lerp, Kit.bell, Kit.bell3, Kit.bell2
local TAU = pi * 2

Torso.RES = {
	full = { rings = 33, sides = 36, ltRings = 10, ltSides = 28, dome = 1, ltDome = 2, warp = 0.32 },
	medium = { rings = 22, sides = 28, ltRings = 8, ltSides = 18, dome = 1, ltDome = 1, warp = 0.28 },
	low = { rings = 12, sides = 14, ltRings = 5, ltSides = 12, dome = 1, ltDome = 1, warp = 0.2 },
}

------------------------------------------------------------------------
-- Silhouettes (half width W in shoulder-span units, front F / back K depth in half-depth units)
------------------------------------------------------------------------
function Torso.Profiles(sk, P)
	local fem = P.female
	local lv, fk = P.lv, P.fatK
	local xS, hz = sk.xS, sk.hz
	-- neck radius (studs): the sternocleidomastoids, the traps and the slider thicken it; never thinner than
	-- 0.25 x the head (women 0.225, ANATOMY_CONTRACTS section 6)
	local rn = sk.headX * (fem and 0.258 or 0.282) * (1 + 0.12 * lv.neckSCM + 0.05 * lv.traps + 0.08 * P.sl.neck + 0.06 * min(fk, 1)) * P.V.neckW
	local rMin = sk.headX * (fem and 0.225 or 0.25) * 1.08 -- the contract minimum with room for the notch and the larynx groove
	rn = max(rn, rMin)
	-- the R15 torso is shallow for its width: the neck keeps its width but never gets deeper than the chest
	-- allows (still at least the contract minimum all round)
	local rz = max(rMin * 1.06, min(rn * 0.97, 0.78 * hz)) -- the front is 0.95 of this: still over the minimum
	local nx, fN, kN = rn / xS, rz * 0.95 / hz, rz * 1.04 / hz
	local wk = (1 + 0.05 * P.sl.waist) * (1 + 0.1 * min(fk, 1.2))
	local trap = 1 + 0.25 * lv.traps * (fem and 0.6 or 1)
	local W, F, K
	if fem then
		W = Kit.Curve({
			{ -0.14, 0.76 }, { 0.0, 0.66 * wk }, { 0.12, 0.665 * wk }, { 0.25, 0.71 }, { 0.38, 0.77 }, { 0.5, 0.81 }, { 0.62, 0.83 },
			{ 0.72, 0.85 }, { 0.8, 0.88 }, { 0.86, 0.92 }, { 0.92, 0.94 }, { 0.96, 0.9 }, { 0.99, max(0.8, nx * 1.75) },
			{ 1.02, max(0.67, nx * 1.55) }, { 1.05, max(0.56, nx * 1.4) }, { 1.08, nx * 1.25 }, { 1.12, nx * 1.05 }, { 1.2, nx },
		})
	else
		W = Kit.Curve({
			{ -0.14, 0.77 * wk }, { 0.0, 0.72 * wk }, { 0.12, 0.73 * wk }, { 0.25, 0.77 }, { 0.38, 0.83 }, { 0.5, 0.865 }, { 0.62, 0.885 },
			{ 0.72, 0.9 }, { 0.8, 0.93 }, { 0.86, 0.965 }, { 0.92, 0.98 }, { 0.96, 0.935 }, { 0.99, max(0.84 * trap ^ 0.3, nx * 1.8) },
			{ 1.02, max(0.7 * trap ^ 0.5, nx * 1.6) }, { 1.05, max(0.575 * trap ^ 0.5, nx * 1.42) }, { 1.08, max(nx * 1.28, 0.47 * trap ^ 0.4) },
			{ 1.12, nx * 1.05 }, { 1.2, nx },
		})
	end
	-- the tops run down into the neck monotonically: no dip (a crease) where the neck is thick for the torso
	F = Kit.Curve({
		{ -0.14, 0.9 }, { 0.0, 0.88 }, { 0.2, 0.9 }, { 0.35, 0.95 }, { 0.5, 0.98 }, { 0.62, 0.98 }, { 0.74, 0.95 }, { 0.84, max(0.88, fN * 1.4) },
		{ 0.92, max(0.77, fN * 1.28) }, { 0.97, max(0.66, fN * 1.13) }, { 1.01, fN * 1.04 }, { 1.06, fN * 1.01 }, { 1.2, fN },
	})
	K = Kit.Curve({
		{ -0.14, 0.93 }, { 0.02, 0.86 }, { 0.18, 0.88 }, { 0.33, 0.93 }, { 0.48, 0.97 }, { 0.62, 0.99 }, { 0.74, max(0.99, min(1.04, kN * 1.5)) },
		{ 0.84, max(0.95, min(1.02, kN * 1.42)) }, { 0.92, max(0.87, kN * 1.33) }, { 0.98, max(0.76, kN * 1.22) }, { 1.03, kN * 1.12 },
		{ 1.08, kN * 1.04 }, { 1.2, kN },
	})
	local nF = Kit.Curve({ { -0.1, 2.2 }, { 0.5, 2.25 }, { 0.9, 2.25 }, { 1.0, 2.1 }, { 1.06, 2.0 } })
	local nB = Kit.Curve({ { -0.1, 2.3 }, { 0.5, 2.4 }, { 0.9, 2.35 }, { 1.0, 2.15 }, { 1.06, 2.0 } })
	-- posture: the neck rises a little behind the torso centre (under the skull's base)
	local zc = Kit.Curve({ { 0.92, 0 }, { 1.05, 0.04 * hz }, { 1.2, 0.08 * hz } })
	return { W = W, F = F, K = K, nF = nF, nB = nB, zc = zc, rn = rn, rz = rz }
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
		belly = table.create(nv, 0) }
	local sideK = { [1] = Kit.SideK(P, 1), [-1] = Kit.SideK(P, -1) }
	local hzK = (hz / 0.5) ^ 0.5
	-- pectoralis major: every man has a chest plate; training thickens it, fat softens and lowers it
	local pecH = (0.032 + 0.115 * lv.pecs ^ 0.85 + 0.035 * lv.upperChest) * flat * V.pecFull * hzK + 0.05 * fk
	local upperK = clamp(0.4 + 0.55 * lv.upperChest / max(0.15, lv.pecs + 0.1), 0.38, 1.05)
	-- (never sharper than ~2 ring spacings: a hard border stair-steps where it runs diagonally to the armpit)
	local pecEdge = max(0.034, 0.022 + 0.03 * (1 - def) + 0.03 * fk)
	local pecDrop = V.pecBorder - 0.03 * lv.pecs - 0.04 * fk
	local pecBorder = Kit.Curve({ { 0.02, 0.505 }, { 0.22, 0.48 }, { 0.46, 0.47 }, { 0.66, 0.53 }, { 0.8, 0.62 }, { 0.92, 0.74 }, { 1.05, 0.86 } })
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
	local trapBackH = (0.006 + 0.03 * lv.traps + 0.012 * lv.upperBack) * flat
	local scapH = (0.008 + 0.035 * lv.upperBack + 0.015 * lv.rearDelt) * flat
	local erecH = (0.008 + 0.045 * lv.lowerBack) * flat
	local spineD = (0.01 + 0.02 * def) * (0.6 + 0.4 * lv.lowerBack)
	local clavH = 0.008 + 0.018 * lean * (fem and 0.8 or 1)
	local ribH = 0.006 + 0.012 * lean
	local scmH = (0.012 + 0.03 * lv.neckSCM) * (fem and 0.6 or 1)
	local bellyH = 0.3 * fk ^ 1.4 * (hz / 0.5) * (fem and 0.6 or 1)
	local handleH = 0.11 * fk * pv.waist
	-- breasts (under the sports top)
	local breastH = fem and (0.15 + 0.05 * min(fk + 0.3, 1)) * hzK or 0
	local yN = sk.yN
	local rn = prof.rn
	-- sternocleidomastoid: mastoid (behind the ear, up the neck) -> sternal head (by the notch)
	local zcTop = prof.zc(1.2)
	local scmTop = { 0.74 * rn, yN + 0.29, zcTop + 0.3 * prof.rz }
	local scmBot = { 0.15 * rn, yW + 0.975 * H, -0.95 * prof.F(0.975) * hz }
	local baseDef = 0.25 + 0.75 * def -- separations everyone shows a little of

	local function field(i, x, y, z, nx, ny, nz)
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
				local top = 1 - smooth(0.84, 0.97, u)
				local upper = lerp(1, upperK, smooth(ub + 0.08, 0.86, u))
				local med = smooth(0.012, 0.1 + 0.14 * max(fk, 1 - def), fx)
				local lat = 1 - smooth(0.84, 1.03, fx)
				local swell = 0.72 + 0.28 * bell((fx - 0.5) / 0.48)
				-- the full lower shelf in the middle of the chest; toward the armpit it flattens into the fold
				local shelf = 1 + 0.4 * bell((u - (ub + 0.075)) / 0.1) * (1 - 0.75 * smooth(0.55, 0.95, fx))
				local face = smooth(-0.35, 0.3, -nz)
				local w = inside * top * upper * med * lat * swell * shelf * face
				local h = pecH * sk1 * w
				d += h
				ch.pec[i] = h
				-- the crease under the pec and the sternal valley shade; the crown catches light
				groove += bell((u - ub) / (edge * 2.6)) * smooth(0.06, 0.2, fx) * lat * face * baseDef * min(1, pecH / 0.05)
					* (1 - 0.85 * smooth(0.6, 0.95, fx))
				groove += (1 - smooth(0.0, 0.09, fx)) * smooth(0.5, 0.62, u) * (1 - smooth(0.85, 0.95, u)) * 0.5 * baseDef
				crown += w * 0.6
				-- the groove between the pec and the front of the shoulder
				groove += bell((fx - 0.9) / 0.07) * smooth(0.76, 0.84, u) * (1 - smooth(0.9, 0.96, u)) * face * 0.4 * baseDef
			end
		end
		-- breasts under a compression top (women) --------------------------------
		if fem and u > 0.38 and u < 0.95 and fx < 0.95 then
			local w = bell2((fx - 0.38) / 0.4, (u - 0.6) / 0.21) * smooth(-0.4, 0.3, -nz)
			-- the top binds them into one shelf: a shallow valley between, not two spheres
			local valley = 1 - 0.35 * (1 - smooth(0.0, 0.16, fx))
			local h = breastH * w * valley
			d += h
			ch.pec[i] = h * 0.3
			groove += bell((u - 0.44) / 0.05) * smooth(0.1, 0.25, fx) * (1 - smooth(0.7, 0.85, fx)) * 0.5
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
		if u > 0.84 and fx < 1.0 then
			local w = bell2((fx - 0.52) / 0.46, (u - 1.0) / 0.12) * smooth(-0.6, 0.3, ny + 0.4 * nz)
			local h = trapH * w
			d += h
			ch.trap[i] = h
			crown += w * 0.3
		end
		-- ... up the back of the neck to the skull (one smooth sheet, no step at the neck base)
		if u > 0.9 and nz > -0.25 then
			local w = (1 - smooth(0.25, 0.7, fx)) * bell((u - 1.06) / 0.14) * smooth(-0.25, 0.55, nz)
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
			local w = (1 - smooth(0.0, 0.045 / xS, fx)) * backF * (1 - smooth(0.9, 1.0, u))
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
		if u > 0.9 then
			local dist, t = Kit.segDist(ax, y, z, scmTop[1], scmTop[2], scmTop[3], scmBot[1], scmBot[2], scmBot[3])
			local r = 0.085 * rn / 0.35
			if dist < r * 1.6 then
				local w = bell(dist / (r * 1.6)) * (0.55 + 0.45 * smooth(0.0, 0.5, t)) * smooth(0.97, 1.0, u)
				d += scmH * w
				crown += w * 0.4
				groove += bell((dist - r * 1.1) / (r * 0.5)) * 0.25 * smooth(0.97, 1.02, u)
			end
			local notch = bell2(ax / (0.15 * rn), (u - 0.985) / 0.03) * front
			d -= 0.018 * notch
			groove += notch * 0.8
			if not fem then
				local lar = bell2(ax / (0.22 * rn), (y - (yN + 0.12)) / 0.07) * front
				d += 0.02 * lar
				crown += lar * 0.4
			end
		end
		-- fat: belly, love handles, a softer back --------------------------------------
		if fk > 0 then
			local b = bell2(fx / 0.8, (u - 0.13) / 0.42) * front
			local hh = bell((u - 0.06) / 0.24) * smooth(0.55, 0.92, fx) * smooth(-0.6, 0.1, nz)
			local bk = bell2(fx / 0.9, (u - 0.15) / 0.3) * backF
			local h = bellyH * b + handleH * hh + 0.035 * fk * bk + 0.025 * fk
			d += h
			ch.belly[i] = bellyH * b
		end
		-- breathing: the ribcage
		ch.rib[i] = bell((u - 0.55) / 0.42) * (0.4 + 0.6 * front)
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
	local u1 = 1 + 0.3 / H -- neck column 0.3 above the neck pivot (inside the head)
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
	local info = MeshKit.Loft(m, {
		rings = rings, sides = R.sides, spine = spine, exact = true,
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
		capStart = "dome", capEnd = "dome", capDepth = 0.12, domeRings = R.dome,
	})
	MeshKit.ComputeNormals(m, { weld = false })
	local field, ch = torsoField(sk, P, prof, m.nv)
	if tuckU then
		-- nothing sculpted under the waistband (and no blend shape pushes through it)
		local inner = field
		field = function(i, x, y, z, nx, ny, nz)
			local d = inner(i, x, y, z, nx, ny, nz)
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
	MeshKit.ComputeNormals(m, { weld = false })
	return m, { prof = prof, ch = ch, loft = info, U = U }
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
	local hipW = (xH + thighR) * (fem and 1.06 or 1) * (1 + 0.06 * P.sl.waist * P.pv.waist) + 0.06 * fk + ease
	local waistW = prof.W(0.0) * xS * 1.015 + 0.02 * fk + ease
	local drop = (yW - yH) -- LowerTorso height
	-- the crotch: with trunks the seat ends at the leg openings' top (the legs carry the rest)
	local bot = yH - (trunks and 0.2 or 0.3) * (drop / 0.4) ^ 0.5
	local Fw, Kw = prof.F(0.0) * hz + ease, prof.K(0.0) * hz + ease
	local top, bandBot = yW + 0.015, nil
	local Wc, Fc, Kc
	local Ys
	local rings = R.ltRings
	if trunks then
		-- the band: the waist's own section plus the elastic's thickness, a lip over the seat below it
		top = yW + Torso.BAND_TOP
		bandBot = yW - 0.17 * (drop / 0.4) ^ 0.5
		local bw, bf, bk = waistW + 0.01, Fw + 0.012, Kw + 0.012
		local sw = lerp(hipW, waistW, 0.85)
		Wc = Kit.Curve({ { bot, hipW * 0.6 }, { yH - 0.1, hipW * 0.9 }, { yH + 0.06, hipW }, { bandBot - 0.03, sw }, { bandBot - 0.0005, sw - 0.004 },
			{ bandBot, bw }, { top, bw } })
		Fc = Kit.Curve({ { bot, Fw * 0.55 }, { yH - 0.1, Fw * 0.86 }, { yH + 0.12, Fw * 0.97 }, { bandBot - 0.0005, Fw * 0.985 }, { bandBot, bf }, { top, bf } })
		Kc = Kit.Curve({ { bot, Kw * 0.45 }, { yH - 0.1, Kw * 0.85 }, { yH + 0.08, Kw * 0.96 }, { bandBot - 0.0005, Kw * 0.965 }, { bandBot, bk }, { top, bk } })
		local list
		if rings >= 10 then
			list = { bot, bot + 0.3 * (yH - 0.12 - bot), yH - 0.12, yH, yH + 0.09, (yH + 0.09 + bandBot) / 2, bandBot - 0.012, bandBot, (bandBot + top) / 2, top }
		elseif rings >= 8 then
			list = { bot, yH - 0.12, yH + 0.04, (yH + bandBot) / 2, bandBot - 0.012, bandBot, (bandBot + top) / 2, top }
		else
			list = { bot, yH, bandBot - 0.012, bandBot, top }
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
	local info = MeshKit.Loft(m, {
		rings = rings, sides = R.ltSides, spine = spine, exact = true,
		section = function(t, a)
			local i = math.floor(t * (rings - 1) + 0.5) + 1
			local y = Ys[i]
			local c, s = cos(a), sin(a)
			local e = 2 / 2.4
			local x = Wc(y) * (c < 0 and -1 or 1) * abs(c) ^ e
			local f = s >= 0 and Fc(y) * s ^ e or -Kc(y) * (-s) ^ e
			return x, f
		end,
		-- with trunks the top is the waistband's lip: a flat cap inside the torso
		capStart = "dome", capEnd = trunks and "flat" or "dome", capDepth = 0.14, domeRings = R.ltDome,
	})
	MeshKit.ComputeNormals(m, { weld = false })
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
		-- glutes: two rounded masses behind the hips, fullest a little under the hip pivots
		local g = bell3((ax - 0.62 * xH - 0.05) / (0.58 * hipW), (y - (yH - 0.02)) / 0.36, 0) * smooth(-0.1, 0.5, nz) * (trunks and (1 - smooth(yH + 0.05, bandY - 0.03, y)) or 1)
		d += gH * g * (trunks and 0.55 or 1)
		glute[i] = gH * g
		crown[i] = g * 0.4
		-- the cleft between them (satin bridges it)
		d -= (trunks and 0.008 or 0.025) * (1 - smooth(0.0, 0.06, ax)) * smooth(0.2, 0.6, nz) * smooth(yH + 0.25, yH - 0.05, y)
		-- lower belly
		d += bellyH * bell2(ax / (0.8 * hipW), (y - (yW - 0.05)) / 0.3) * smooth(-0.1, 0.5, -nz)
		return d
	end)
	MeshKit.ComputeNormals(m, { weld = false })
	return m, { crown = crown, glute = glute, hipW = hipW, bot = bot, top = top, bandBot = bandBot, loft = info }
end
Torso.BAND_TOP = 0.035 -- waistband top edge above the waist pivot (studs)

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
