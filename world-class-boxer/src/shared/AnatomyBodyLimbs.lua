-- AnatomyBodyLimbs: the eight limb pieces (UpperArm with the deltoid cap, LowerArm, UpperLeg, LowerLeg per
-- side), built in UpperTorso space (body space) by AnatomyBody. Each limb is a loft along its bone (joint
-- pivot to joint pivot from look.rig) with domed ends that reach past both pivots, so bent joints stay closed.
-- The section is a base ellipse (bone + skin) plus muscle bellies as smooth (t, angle) windows: deltoid
-- heads, biceps peak, brachialis, the triceps horseshoe, forearm flexor / extensor masses, quads with the
-- vastus medialis teardrop, adductors, hamstrings, the two gastrocnemius heads, soleus, tibialis, knees,
-- elbows, ankles. Angles: 0 = lateral (away from the body), pi/2 = front, pi = medial, 3pi/2 = back, on both
-- sides. Every bulge also lands in per-vertex channels for the painter and the flex blend shape.
local MeshKit = require(script.Parent:WaitForChild("MeshKit"))
local Kit = require(script.Parent:WaitForChild("AnatomyBodyKit"))

local Limbs = {}

local abs, min, max, sqrt, cos, sin, pi = math.abs, math.min, math.max, math.sqrt, math.cos, math.sin, math.pi
local clamp, smooth, lerp = Kit.clamp, Kit.smooth, Kit.lerp
local TAU = pi * 2
local LAT, FRONT, MED, BACK = 0, pi / 2, pi, 3 * pi / 2

-- { rings, sides } per piece. Both pieces of a joint share the side count (and the same angle frame), so in
-- a straight joint their facets run parallel and the line where one tucks into the other stays clean.
Limbs.RES = {
	full = { UpperArm = { 17, 16 }, LowerArm = { 13, 16 }, UpperLeg = { 17, 16 }, LowerLeg = { 15, 16 }, dome = 3 },
	medium = { UpperArm = { 11, 12 }, LowerArm = { 9, 12 }, UpperLeg = { 11, 12 }, LowerLeg = { 9, 12 }, dome = 1 },
	low = { UpperArm = { 6, 8 }, LowerArm = { 5, 8 }, UpperLeg = { 6, 8 }, LowerLeg = { 5, 8 }, dome = 1 },
}

-- angular window (raised cosine) and its belly along the bone
local function win(a, c, w)
	local d = abs(MeshKit.WrapAngle(a - c))
	if d >= w then
		return 0
	end
	return 0.5 * (1 + cos(pi * d / w))
end
local function along(b, b0, bp, b1)
	if b <= b0 or b >= b1 then
		return 0
	end
	if b <= bp then
		local k = (b - b0) / (bp - b0)
		return k * k * (3 - 2 * k)
	end
	local k = (b1 - b) / (b1 - bp)
	return k * k * (3 - 2 * k)
end
-- one muscle belly: { a = centre angle, w = half width, b0, bp, b1, h = studs, sharp }
local function belly(b, a, m)
	local wv = win(a, m.a, m.w)
	if wv <= 0 then
		return 0
	end
	local b1 = m.b1
	if m.vee then
		-- the insertion narrows to a point (deltoid): the end comes up toward the window's edges
		b1 -= m.vee * (1 - wv)
	end
	local k = along(b, m.b0, m.bp, max(b1, m.bp + 0.02))
	if k <= 0 then
		return 0
	end
	k *= wv
	if m.sharp then
		k = k ^ m.sharp
	end
	return m.h * k
end

------------------------------------------------------------------------
-- Per-limb anatomy (sizes in studs, scaled by the part's box width)
------------------------------------------------------------------------
-- returns spec { base = Curve(b) -> {rx, rz} via two curves, muscles = {...}, grooves = {...}, flex = {...} }
local function upperArm(sk, P, side, sx)
	local lv, V, fk, def = P.lv, P.V, min(P.fatK, 1.2), P.defE
	local fem = P.female
	local k = Kit.SideK(P, side == "Right" and 1 or -1)
	local fl = P.pv.flat
	local el = P.pv.elong
	local sz = fem and 0.88 or 1
	local rx = Kit.Curve({ { -0.1, 0.31 }, { 0.0, 0.325 }, { 0.2, 0.305 }, { 0.5, 0.272 }, { 0.8, 0.252 }, { 0.97, 0.262 }, { 1.12, 0.24 } })
	local rz = Kit.Curve({ { -0.1, 0.31 }, { 0.0, 0.32 }, { 0.2, 0.3 }, { 0.5, 0.268 }, { 0.8, 0.24 }, { 0.97, 0.228 }, { 1.12, 0.215 } })
	local delt = (0.045 + 0.1 * lv.sideDelt) * fl * k
	local bi = (0.022 + 0.1 * lv.biceps) * fl * V.bicepsHeight * k
	local tri = (0.022 + 0.085 * lv.triceps) * fl * k
	local peakB = 0.56 + V.bicepsPeak - 0.04 * (el - 1)
	local mus = {
		-- deltoid: lateral head (the shoulder's roundness), anterior, posterior; all end in the V insertion
		{ a = LAT, w = 1.3, b0 = -0.2, bp = 0.1, b1 = 0.56, vee = 0.3, h = delt, sharp = 0.9, id = "delt" },
		{ a = FRONT - 0.3, w = 1.0, b0 = -0.2, bp = 0.08, b1 = 0.5, vee = 0.3, h = (0.032 + 0.075 * lv.frontDelt) * fl * V.deltFront * k, sharp = 0.95, id = "delt" },
		{ a = BACK + 0.35, w = 1.0, b0 = -0.2, bp = 0.1, b1 = 0.5, vee = 0.3, h = (0.028 + 0.07 * lv.rearDelt) * fl * k, sharp = 0.95, id = "delt" },
		-- biceps (two heads, one peak) and brachialis peeking out laterally
		{ a = FRONT + 0.05, w = 0.95, b0 = 0.2, bp = peakB, b1 = 0.95, h = bi, sharp = 1.25, id = "biceps" },
		{ a = FRONT - 0.85, w = 0.6, b0 = 0.42, bp = 0.74, b1 = 0.98, h = (0.012 + 0.04 * lv.biceps) * fl * k, id = "brach" },
		-- triceps: the long head (back / inner) and the lateral head (back / outer) = the horseshoe
		{ a = BACK - 0.38, w = 0.95, b0 = 0.08, bp = 0.42, b1 = 0.88, h = tri, id = "triceps" },
		{ a = BACK + 0.62, w = 0.72, b0 = 0.12, bp = 0.34, b1 = 0.66, h = tri * 0.85, sharp = 1.1, id = "triceps" },
		-- elbow: olecranon behind, the epicondyles either side
		{ a = MED, w = 0.6, b0 = 0.86, bp = 0.97, b1 = 1.08, h = 0.016, id = "bone" },
		{ a = LAT, w = 0.6, b0 = 0.86, bp = 0.97, b1 = 1.06, h = 0.01, id = "bone" },
		-- fat: the back of the arm first
		{ a = BACK - 0.2, w = 1.4, b0 = 0.05, bp = 0.45, b1 = 0.9, h = 0.06 * fk, id = "fat" },
	}
	local grooves = {
		-- biceps / triceps valley on the inside (the brachial vessels), deltoid insertion, triceps tendon flat
		{ a = MED + 0.12, w = 0.42, b0 = 0.18, bp = 0.55, b1 = 0.92, h = (0.012 + 0.022 * def) * (0.4 + 0.6 * lv.biceps), id = "g" },
		{ a = LAT + 0.55, w = 0.38, b0 = 0.3, bp = 0.48, b1 = 0.7, h = (0.008 + 0.018 * def) * (0.4 + lv.sideDelt * 0.6), id = "g" },
		{ a = BACK, w = 0.6, b0 = 0.62, bp = 0.82, b1 = 0.98, h = (0.006 + 0.016 * def) * lv.triceps, id = "g" },
		{ a = FRONT - 0.55, w = 0.35, b0 = 0.38, bp = 0.62, b1 = 0.86, h = (0.006 + 0.012 * def) * lv.biceps, id = "g" },
	}
	return { rx = rx, rz = rz, scale = sx * sz, mus = mus, grooves = grooves, b0 = -0.04, b1 = 1.0, capS = { 0.235, 2 }, capE = { 0.235, 3 }, endK = { 0.84, 1.0, 0.89 },
		flexIds = { biceps = 0.35, delt = 0.12, triceps = 0.18, brach = 0.25 } }
end

local function lowerArm(sk, P, side, sx)
	local lv, fk, def = P.lv, min(P.fatK, 1.2), P.defE
	local fem = P.female
	local k = Kit.SideK(P, side == "Right" and 1 or -1)
	local fl = P.pv.flat
	local sz = fem and 0.88 or 1
	local rx = Kit.Curve({ { -0.2, 0.235 }, { 0.0, 0.25 }, { 0.15, 0.262 }, { 0.35, 0.248 }, { 0.6, 0.215 }, { 0.85, 0.188 }, { 1.0, 0.182 }, { 1.15, 0.175 } })
	local rz = Kit.Curve({ { -0.2, 0.22 }, { 0.0, 0.232 }, { 0.15, 0.245 }, { 0.35, 0.228 }, { 0.6, 0.19 }, { 0.85, 0.148 }, { 1.0, 0.138 }, { 1.15, 0.13 } })
	local fa = (0.026 + 0.075 * lv.forearms) * fl * k
	local mus = {
		-- brachioradialis + wrist extensors (thumb side / top), flexors (palm side), extensors (back)
		{ a = FRONT - 0.45, w = 0.9, b0 = -0.05, bp = 0.2, b1 = 0.7, h = fa, sharp = 1.1, id = "fore" },
		{ a = MED - 0.3, w = 1.0, b0 = 0.0, bp = 0.24, b1 = 0.75, h = fa * 0.85, id = "fore" },
		{ a = LAT - 0.55, w = 0.75, b0 = 0.02, bp = 0.22, b1 = 0.62, h = fa * 0.6, id = "fore" },
		{ a = BACK, w = 0.75, b0 = -0.05, bp = 0.03, b1 = 0.16, h = 0.022, id = "bone" },
		{ a = BACK - 0.3, w = 1.5, b0 = 0.05, bp = 0.3, b1 = 0.7, h = 0.025 * fk, id = "fat" },
	}
	local grooves = {
		-- the ulna's ridge between the flexors and the extensors, the tendons near the wrist
		{ a = BACK + 0.15, w = 0.4, b0 = 0.15, bp = 0.5, b1 = 0.85, h = (0.008 + 0.014 * def) * (0.4 + 0.6 * lv.forearms), id = "g" },
		{ a = FRONT + 0.2, w = 0.35, b0 = 0.2, bp = 0.42, b1 = 0.7, h = (0.004 + 0.012 * def) * lv.forearms, id = "g" },
	}
	return { rx = rx, rz = rz, scale = sx * sz, mus = mus, grooves = grooves, b0 = 0.0, b1 = 1.12, capS = { 0.245, 3 }, capE = { 0.2, 1 }, startK = { 0.14, 0.0, 1.035 }, flexIds = { fore = 0.3 } }
end

local function upperLeg(sk, P, side, sx)
	local lv, V, fk, def = P.lv, P.V, min(P.fatK, 1.2), P.defE
	local fem = P.female
	local fl = P.pv.flat
	local rx = Kit.Curve({ { -0.2, 0.2 }, { -0.1, 0.36 }, { 0.0, 0.47 }, { 0.12, 0.5 }, { 0.3, 0.48 }, { 0.5, 0.445 }, { 0.75, 0.385 }, { 0.9, 0.345 }, { 1.0, 0.33 } })
	local rz = Kit.Curve({ { -0.2, 0.2 }, { -0.1, 0.36 }, { 0.0, 0.46 }, { 0.12, 0.48 }, { 0.3, 0.46 }, { 0.5, 0.42 }, { 0.75, 0.36 }, { 0.9, 0.32 }, { 1.0, 0.305 } })
	local q = (0.03 + 0.1 * lv.quads) * fl
	local mus = {
		-- quadriceps: vastus lateralis (the outer sweep), rectus femoris (front), vastus medialis teardrop
		{ a = FRONT - 0.78, w = 1.0, b0 = 0.08, bp = 0.42, b1 = 0.86, h = q * V.quadSweep, id = "quad" },
		{ a = FRONT - 0.05, w = 0.7, b0 = 0.02, bp = 0.4, b1 = 0.84, h = q * 0.72, sharp = 1.1, id = "quad" },
		{ a = FRONT + 0.78, w = 0.68, b0 = 0.52, bp = 0.8, b1 = 0.96, h = (0.02 + 0.095 * lv.quads) * fl * V.teardrop, sharp = 1.15, id = "quad" },
		-- adductors fill the inner thigh near the top; hamstrings behind (two heads)
		{ a = MED + 0.15, w = 1.0, b0 = -0.05, bp = 0.15, b1 = 0.6, h = (0.03 + 0.05 * lv.quads) * fl, id = "add" },
		{ a = BACK + 0.42, w = 0.8, b0 = 0.05, bp = 0.42, b1 = 0.9, h = (0.025 + 0.08 * lv.hamstrings) * fl, id = "ham" },
		{ a = BACK - 0.42, w = 0.8, b0 = 0.08, bp = 0.45, b1 = 0.92, h = (0.025 + 0.075 * lv.hamstrings) * fl, id = "ham" },
		-- knee: the kneecap, the fat pad beside it
		{ a = FRONT, w = 0.6, b0 = 0.84, bp = 0.97, b1 = 1.06, h = 0.03, id = "bone" },
		{ a = FRONT + 0.9, w = 0.5, b0 = 0.86, bp = 0.97, b1 = 1.06, h = 0.012, id = "bone" },
		-- hip / trochanter and the female hip curve
		{ a = LAT, w = 0.9, b0 = -0.08, bp = 0.08, b1 = 0.4, h = 0.025 + (fem and 0.06 or 0) + 0.04 * fk, id = "hip" },
		-- fat: outer and inner thigh
		{ a = LAT + 0.2, w = 1.3, b0 = -0.02, bp = 0.25, b1 = 0.7, h = 0.045 * fk + (fem and 0.03 or 0), id = "fat" },
		{ a = MED, w = 1.2, b0 = -0.02, bp = 0.2, b1 = 0.6, h = 0.05 * fk + (fem and 0.025 or 0), id = "fat" },
	}
	local grooves = {
		-- the IT band down the outside, the sartorius line, the quad / hamstring split
		{ a = LAT - 0.1, w = 0.35, b0 = 0.3, bp = 0.65, b1 = 0.92, h = (0.008 + 0.02 * def) * (0.4 + 0.6 * lv.quads), id = "g" },
		{ a = FRONT + 0.42, w = 0.28, b0 = 0.25, bp = 0.55, b1 = 0.8, h = (0.004 + 0.014 * def) * lv.quads, id = "g" },
		{ a = MED + 0.7, w = 0.35, b0 = 0.3, bp = 0.6, b1 = 0.85, h = (0.004 + 0.012 * def) * lv.hamstrings, id = "g" },
		-- behind the knee
		{ a = BACK, w = 0.8, b0 = 0.88, bp = 1.0, b1 = 1.1, h = 0.02, id = "g" },
	}
	return { rx = rx, rz = rz, scale = sx, mus = mus, grooves = grooves, b0 = -0.2, b1 = 1.0, capS = { 0.15, 1 }, capE = { 0.3, 3 }, flexIds = { quad = 0.28, ham = 0.15 } }
end

local function lowerLeg(sk, P, side, sx)
	local lv, V, fk, def = P.lv, P.V, min(P.fatK, 1.2), P.defE
	local fem = P.female
	local fl = P.pv.flat
	local rx = Kit.Curve({ { 0.0, 0.325 }, { 0.12, 0.305 }, { 0.35, 0.282 }, { 0.6, 0.232 }, { 0.82, 0.178 }, { 0.95, 0.166 }, { 1.12, 0.158 } })
	local rz = Kit.Curve({ { 0.0, 0.305 }, { 0.12, 0.28 }, { 0.35, 0.262 }, { 0.6, 0.21 }, { 0.82, 0.156 }, { 0.95, 0.148 }, { 1.12, 0.14 } })
	local hi = V.calfHigh
	local c = (0.05 + 0.1 * lv.calves) * fl + 0.025 * fk
	local mus = {
		-- gastrocnemius: the medial head bigger and lower, the lateral head higher
		{ a = BACK - 0.48, w = 0.92, b0 = 0.04, bp = 0.28 + hi, b1 = 0.58 + hi, h = c * V.calfRatio, sharp = 1.1, id = "calf" },
		{ a = BACK + 0.5, w = 0.85, b0 = 0.03, bp = 0.22 + hi, b1 = 0.5 + hi, h = c * 0.85 / V.calfRatio ^ 0.5, sharp = 1.1, id = "calf" },
		-- soleus widening the lower calf, tibialis anterior beside the shin
		{ a = BACK - 1.0, w = 0.7, b0 = 0.3, bp = 0.55, b1 = 0.8, h = (0.012 + 0.04 * lv.calves) * fl, id = "sol" },
		{ a = BACK + 1.0, w = 0.7, b0 = 0.3, bp = 0.52, b1 = 0.78, h = (0.012 + 0.035 * lv.calves) * fl, id = "sol" },
		{ a = FRONT - 0.5, w = 0.55, b0 = 0.06, bp = 0.3, b1 = 0.7, h = (0.015 + 0.04 * lv.calves) * fl, id = "tib" },
		-- the tibial tuberosity under the kneecap, the ankle bones
		{ a = FRONT + 0.15, w = 0.55, b0 = 0.02, bp = 0.1, b1 = 0.2, h = 0.012, id = "bone" },
		{ a = MED, w = 0.5, b0 = 0.88, bp = 0.97, b1 = 1.06, h = 0.022, id = "bone" },
		{ a = LAT, w = 0.5, b0 = 0.9, bp = 1.0, b1 = 1.1, h = 0.02, id = "bone" },
		{ a = BACK - 0.3, w = 1.4, b0 = 0.05, bp = 0.3, b1 = 0.7, h = 0.03 * fk + (fem and 0.01 or 0), id = "fat" },
	}
	local grooves = {
		-- the Achilles tendon narrows the back, the shin bone stays flat, the split between the calf heads
		{ a = BACK, w = 0.9, b0 = 0.62, bp = 0.85, b1 = 1.0, h = 0.03, id = "g" },
		{ a = FRONT + 0.4, w = 0.45, b0 = 0.15, bp = 0.5, b1 = 0.85, h = 0.012, id = "g" },
		{ a = BACK, w = 0.22, b0 = 0.08, bp = 0.3, b1 = 0.5, h = (0.004 + 0.012 * def) * lv.calves, id = "g" },
	}
	return { rx = rx, rz = rz, scale = sx, mus = mus, grooves = grooves, b0 = 0.0, b1 = 1.08, capS = { 0.28, 1 }, capE = { 0.2, 1 }, startK = { 0.2, 0.0, 0.89 }, flexIds = { calf = 0.3 } }
end

Limbs.Specs = { UpperArm = upperArm, LowerArm = lowerArm, UpperLeg = upperLeg, LowerLeg = lowerLeg }

-- the superficial veins a conditioned boxer shows, as (bone parameter, angle) paths; more appear as
-- vascularity rises (look.body.vein). Per-boxer jitter from the variation stream. calfTop = where the boot
-- shaft ends (no veins under it).
function Limbs.VeinPaths(P, kind, side, S, calfTop)
	local v = P.vein
	if v < 0.15 then
		return nil
	end
	local rng = MeshKit.Rng((P.V.veinSeed or 1) + #kind * 31 + (side == "Right" and 7 or 0))
	local function j(x, amt)
		return x + (rng:Next() - 0.5) * 2 * amt
	end
	local r = S * (0.006 + 0.012 * v) * (P.female and 0.7 or 1)
	local out = {}
	local function add(pts, k)
		local q = {}
		for i, p in ipairs(pts) do
			q[i] = { j(p[1], 0.03), j(p[2], 0.08) }
		end
		out[#out + 1] = { pts = q, r = r * (k or 1) }
	end
	if kind == "LowerArm" then
		-- cephalic (thumb side) and median (palm side) up the forearm
		add({ { 0.9, FRONT - 0.55 }, { 0.68, FRONT - 0.35 }, { 0.45, FRONT - 0.15 }, { 0.22, FRONT + 0.05 }, { 0.05, FRONT + 0.25 } })
		add({ { 0.86, MED - 0.1 }, { 0.62, MED - 0.25 }, { 0.4, MED - 0.12 }, { 0.18, MED - 0.4 }, { 0.04, FRONT + 0.6 } }, 0.9)
		if v > 0.4 then
			add({ { 0.96, LAT - 0.25 }, { 0.8, LAT + 0.05 }, { 0.62, LAT - 0.12 }, { 0.48, LAT + 0.1 } }, 0.8)
		end
	elseif kind == "UpperArm" and v > 0.35 then
		-- the biceps vein, and the cephalic in the groove beside it
		add({ { 0.93, FRONT + 0.3 }, { 0.75, FRONT + 0.06 }, { 0.55, FRONT - 0.12 }, { 0.36, FRONT - 0.32 } })
		if v > 0.6 then
			add({ { 0.7, FRONT - 0.8 }, { 0.52, FRONT - 0.7 }, { 0.32, FRONT - 0.55 } }, 0.85)
		end
	elseif kind == "LowerLeg" and v > 0.55 and calfTop > 0.3 then
		-- the great saphenous on the inside of the calf, above the boot shaft
		add({ { 0.1, MED + 0.25 }, { (0.1 + calfTop) / 2, MED + 0.05 }, { calfTop - 0.04, MED - 0.15 } }, 0.9)
	end
	return #out > 0 and out or nil
end
Limbs.belly = belly

------------------------------------------------------------------------
-- One limb mesh (body space). bone = { from pivot, to pivot } (joint pivots in body space).
------------------------------------------------------------------------
-- returns mesh, info { rings, sides, first, frames, B (bone param per ring), crown, groove, flex (per vertex
-- radial delta for the flex morph), dir (per vertex radial direction) }
-- opt.trunk = { hemB (bone param of the leg opening), flare } draws a loose satin trunk leg over the thigh
-- down to the hem; opt.cuff = { hemB } a trunk cuff below the knee (long trunks). The hem is a pair of rings
-- (the fabric's edge, then the skin) so the opening reads as a real edge.
-- the bone, the spec and the exact surface radius a piece is built with (shared by Build and SurfacePoint)
local function setup(sk, P, lod, side, kind, opt)
	opt = opt or {}
	local R = Limbs.RES[lod] or Limbs.RES.full
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
	local L = sqrt(dx * dx + dy * dy + dz * dz)
	if L < 1e-3 then
		dx, dy, dz, L = 0, -1, 0, 1
	end
	local box = sk.size[side .. kind]
	local spec = Limbs.Specs[kind](sk, P, side, box[1])
	local S = spec.scale
	local B1 = spec.b1
	local cloth = opt.trunk or opt.cuff
	local hemB = cloth and min(cloth.hemB, B1) or nil
	local mus, grooves = spec.mus, spec.grooves
	local rx, rz = spec.rx, spec.rz
	local nM = #mus
	local endK, startK = spec.endK, spec.startK
	local topEx, topEz, topBulge = rx(0.1), rz(0.1), 0
	if hemB then
		for q = 0, 7 do
			for k = 1, nM do
				topBulge += belly(0.12, TAU * q / 8, mus[k])
			end
		end
		topBulge = topBulge / 8 * 1.5
	end
	-- cloth = true: the satin's radius where the piece is cloth (bb <= hemB), else the skin's
	local function radiusAt(bb, ang, cloth)
		local ex, ez = rx(bb) * S, rz(bb) * S
		local c, s = cos(ang), sin(ang)
		local r = 1 / sqrt((c / ex) ^ 2 + (s / ez) ^ 2)
		for k = 1, nM do
			r += belly(bb, ang, mus[k]) * S
		end
		for k = 1, #grooves do
			r -= belly(bb, ang, grooves[k]) * S
		end
		-- joint ends: the parent's end tucks inside the child's (or the reverse), never at the same radius
		if endK then
			r *= lerp(1, endK[3], smooth(endK[1], endK[2], bb))
		end
		if startK then
			r *= lerp(1, startK[3], smooth(startK[1], startK[2], bb))
		end
		if hemB and cloth and bb <= hemB + 1e-6 then
			-- satin over the leg: drapes over the biggest muscles (no valleys), loose, a little flared at the
			-- opening, soft vertical folds
			local t = smooth(0.0, hemB, bb)
			local loose
			if opt.trunk then
				-- satin hangs from the widest part of the thigh: a near-cylinder that narrows only a little to
				-- the opening, with soft vertical folds
				local base = 1 / sqrt((c / (topEx * S)) ^ 2 + (s / (topEz * S)) ^ 2) + topBulge * S
				loose = base * (1.04 - 0.05 * t) + 0.03 * S
				loose += 0.008 * S * sin(5 * ang + 1.3 + 4 * bb) * (0.3 + 0.7 * t)
				if hemB >= 0.97 then
					-- knee-length trunks gather toward the knee instead of hanging like a skirt
					loose = lerp(loose, r + 0.035 * S, smooth(0.45, 1.0, bb))
				end
				-- above the hip the leg is inside the trunks' seat (the LowerTorso piece carries the hips)
				loose = lerp(r + 0.008 * S, loose, smooth(-0.12, 0.08, bb))
			else
				loose = r + 0.03 * S
			end
			r = max(r + 0.012 * S, loose)
		end
		return r
	end
	return { R = R, a = a, b = b, L = L, ux = dx / L, uy = dy / L, uz = dz / L, spec = spec, S = S, hemB = hemB, radiusAt = radiusAt }
end

-- the lateral / front directions of a limb's loft frames (MeshKit.Loft with sideHint = the lateral side,
-- frontHint = -Z): side = lateral made square to the bone, front = bone x side turned to -Z
local function limbFrame(ux, uy, uz, sg)
	local sx, sy, sz = sg - (sg * ux) * ux, -(sg * ux) * uy, -(sg * ux) * uz
	local sl = sqrt(sx * sx + sy * sy + sz * sz)
	sx, sy, sz = sx / sl, sy / sl, sz / sl
	local fx, fy, fz = uy * sz - uz * sy, uz * sx - ux * sz, ux * sy - uy * sx
	if fz > 0 then
		fx, fy, fz = -fx, -fy, -fz
	end
	return sx, sy, sz, fx, fy, fz
end
Limbs.Frame = limbFrame

-- body-space point on the surface Build makes with the same options (satin included) at (bone, angle)
function Limbs.SurfacePoint(sk, P, side, kind, opt, bb, ang)
	local c = setup(sk, P, "full", side, kind, opt)
	local r = c.radiusAt(bb, ang, true)
	local sx, sy, sz, fx, fy, fz = limbFrame(c.ux, c.uy, c.uz, side == "Right" and 1 or -1)
	local cs, sn = cos(ang), sin(ang)
	local a, L = c.a, c.L
	return { a[1] + c.ux * L * bb + (sx * cs + fx * sn) * r, a[2] + c.uy * L * bb + (sy * cs + fy * sn) * r,
		a[3] + c.uz * L * bb + (sz * cs + fz * sn) * r }
end

function Limbs.Build(sk, P, lod, side, kind, opt)
	opt = opt or {}
	local ctx = setup(sk, P, lod, side, kind, opt)
	local R = ctx.R
	local res = R[kind]
	local rings, sides = res[1], res[2]
	local sg = side == "Right" and 1 or -1
	local a, b, L = ctx.a, ctx.b, ctx.L
	local ux, uy, uz = ctx.ux, ctx.uy, ctx.uz
	local spec, S = ctx.spec, ctx.S
	local B0, B1 = spec.b0, spec.b1
	local function pt(bb)
		return { a[1] + ux * L * bb, a[2] + uy * L * bb, a[3] + uz * L * bb }
	end
	local hemB = ctx.hemB
	local Bs = table.create(rings)
	if hemB and hemB < B1 - 0.03 then
		-- cloth rings down to the hem, then the skin: the edge pair sits 0.012 studs apart
		local n1 = max(2, math.floor(rings * (hemB - B0) / (B1 - B0) * 0.75 + 0.5))
		n1 = min(n1, rings - 3)
		local gap = 0.012 / L
		for i = 1, n1 do
			Bs[i] = B0 + (hemB - B0) * (i - 1) / (n1 - 1)
		end
		for i = n1 + 1, rings do
			local t = (i - n1 - 1) / (rings - n1 - 1)
			Bs[i] = hemB + gap + (B1 - hemB - gap) * t
		end
	else
		for i = 1, rings do
			Bs[i] = B0 + (B1 - B0) * (i - 1) / (rings - 1)
		end
	end
	local spine = table.create(rings)
	for i = 1, rings do
		spine[i] = pt(Bs[i])
	end
	local mus, grooves = spec.mus, spec.grooves
	local nM = #mus
	local radiusAt = ctx.radiusAt
	local m = MeshKit.New(side .. kind)
	local info = MeshKit.Loft(m, {
		rings = rings, sides = sides, spine = spine, exact = true, sideHint = { sg, 0, 0 }, frontHint = { 0, 0, -1 },
		radius = function(t, ang)
			local i = math.floor(t * (rings - 1) + 0.5) + 1
			return radiusAt(Bs[i], ang, true)
		end,
		-- both caps are made below, each with its own depth and dome rings (MeshKit.Loft has one depth, and it
		-- gives a nil capStart the capEnd's kind)
		capStart = nil, capEnd = nil,
	})
	Kit.LoftCap(m, MeshKit, info, "start", spec.capS[1] * S, min(spec.capS[2], R.dome))
	Kit.LoftCap(m, MeshKit, info, "end", spec.capE[1] * S, min(spec.capE[2], R.dome))
	-- veins: low, wide ridges lying on the skin (Kit.Strand), following a path in (bone, angle)
	local veinFirst = m.nv + 1
	local veinN = {}
	if opt.veins and #opt.veins > 0 then
		local f = info.frames[1] -- a straight bone: one frame along it
		for _, path in ipairs(opt.veins) do
			local n = 6
			local pts, nrm = table.create(n), table.create(n)
			local src = path.pts
			for k = 1, n do
				-- even steps along the (bone, angle) polyline
				local tt = (k - 1) / (n - 1) * (#src - 1)
				local j0 = math.min(#src - 1, math.floor(tt) + 1)
				local w = tt - (j0 - 1)
				local bb = src[j0][1] + (src[j0 + 1][1] - src[j0][1]) * w
				local ang = src[j0][2] + (src[j0 + 1][2] - src[j0][2]) * w
				local r = radiusAt(bb, ang)
				local c, sn = cos(ang), sin(ang)
				local ox, oy, oz = f[7] * c + f[10] * sn, f[8] * c + f[11] * sn, f[9] * c + f[12] * sn
				pts[k] = { a[1] + ux * L * bb + ox * r, a[2] + uy * L * bb + oy * r, a[3] + uz * L * bb + oz * r }
				nrm[k] = { ox, oy, oz }
			end
			Kit.Strand(m, MeshKit, pts, nrm, path.r, "vein", veinN)
		end
	end
	MeshKit.ComputeNormals(m, { weld = false })
	for _, e in ipairs(veinN) do
		MeshKit.SetNormal(m, e[1], e[2], e[3], e[4])
	end
	-- per-vertex channels for the painter and the flex shape (ring vertices only; caps stay 0)
	local nv = m.nv
	local crown, groove, flex = table.create(nv, 0), table.create(nv, 0), table.create(nv, 0)
	local dirs = table.create(nv * 3, 0)
	local Bv = table.create(nv, -1)
	local Av = table.create(nv, 0)
	local first, stride = info.first, info.stride
	local frames = info.frames
	local flexIds = spec.flexIds
	for i = 1, rings do
		local f = frames[i]
		local bb = Bs[i]
		for j = 0, sides - 1 do
			local vi = first + (i - 1) * stride + j
			local ang = TAU * j / sides
			local c, s = cos(ang), sin(ang)
			local cr, fx = 0, 0
			for k = 1, nM do
				local mm = mus[k]
				local h = belly(bb, ang, mm)
				if h > 0 and mm.id ~= "fat" and mm.id ~= "bone" then
					cr += h / max(0.02, mm.h) * 0.6
				end
				local fk = flexIds[mm.id]
				if fk then
					fx += h * fk * S
				end
			end
			local gr = 0
			for k = 1, #grooves do
				local gg = grooves[k]
				gr += belly(bb, ang, gg) / max(0.004, gg.h) * min(1, gg.h / 0.012)
			end
			crown[vi] = clamp(cr, 0, 1)
			groove[vi] = clamp(gr, 0, 1)
			flex[vi] = fx
			dirs[vi * 3 - 2] = f[7] * c + f[10] * s
			dirs[vi * 3 - 1] = f[8] * c + f[11] * s
			dirs[vi * 3] = f[9] * c + f[12] * s
			Bv[vi] = bb
			Av[vi] = ang
		end
	end
	-- veins pop out a little on a flex / pump: radially away from the bone
	if veinFirst <= nv then
		local Pp = m.P
		for v = veinFirst, nv do
			local px, py, pz = Pp[v * 3 - 2] - a[1], Pp[v * 3 - 1] - a[2], Pp[v * 3] - a[3]
			local along = px * ux + py * uy + pz * uz
			local rx2, ry2, rz2 = px - ux * along, py - uy * along, pz - uz * along
			local l = sqrt(rx2 * rx2 + ry2 * ry2 + rz2 * rz2)
			if l > 1e-6 then
				dirs[v * 3 - 2], dirs[v * 3 - 1], dirs[v * 3] = rx2 / l, ry2 / l, rz2 / l
				flex[v] = 0.008 * S
			end
		end
	end
	return m, { kind = kind, side = side, L = L, a = a, b = b, ax = { ux, uy, uz }, rings = rings, sides = sides, first = first,
		stride = stride, crown = crown, groove = groove, flex = flex, dir = dirs, B = Bv, A = Av, spec = spec, S = S, hemB = hemB,
		veinFirst = veinFirst }
end

return Limbs
