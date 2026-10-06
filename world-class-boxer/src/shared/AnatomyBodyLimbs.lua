-- AnatomyBodyLimbs: the eight limb pieces (UpperArm with the deltoid cap, LowerArm, UpperLeg, LowerLeg per
-- side), built in UpperTorso space (body space) by AnatomyBody. Each limb is a grid loft (AnatomyBodyKit)
-- along its bone (joint pivot to joint pivot from look.rig) with domed ends that reach past both pivots, so
-- bent joints stay closed. The section is a base ellipse (bone + skin) plus muscle bellies as smooth
-- (t, angle) windows: deltoid heads, biceps peak, brachialis, the triceps horseshoe, forearm flexor /
-- extensor masses, quads with the vastus medialis teardrop, adductors, hamstrings, the two gastrocnemius
-- heads, soleus, tibialis, Achilles tendon, knees, elbows, ankles. Angles: 0 = lateral (away from the body),
-- pi/2 = front, pi = medial, 3pi/2 = back, on both sides.
-- Garments are zones along the bone with their own section: the satin trunk leg over the thigh, the long
-- trunks' cuff, the boot shaft over the ankle and shin, the glove cuff and the hand wrap at the wrist. A
-- zone edge is a pair of rings 0.012 studs apart (the fabric's edge, then the skin), so the edge is crisp in
-- the vertex colours and in the texture. Every bulge also lands in per-vertex channels for the painter and
-- the flex blend shape.
local MeshKit = require(script.Parent:WaitForChild("MeshKit"))
local Kit = require(script.Parent:WaitForChild("AnatomyBodyKit"))

local Limbs = {}

local abs, min, max, sqrt, cos, sin, pi = math.abs, math.min, math.max, math.sqrt, math.cos, math.sin, math.pi
local clamp, smooth, lerp = Kit.clamp, Kit.smooth, Kit.lerp
local TAU = pi * 2
local LAT, FRONT, MED, BACK = 0, pi / 2, pi, 3 * pi / 2

-- { rings, sides, start dome rings, end dome rings } per piece. Both pieces of a joint share the side count
-- (and the same angle frame), so in a straight joint their facets run parallel and the line where one tucks
-- into the other stays clean. Domes that show (the shoulder top, the elbow, the knee) get more rings.
Limbs.RES = {
	full = { UpperArm = { 15, 16, 2, 3 }, LowerArm = { 12, 16, 1, 1 }, UpperLeg = { 16, 16, 1, 3 }, LowerLeg = { 14, 16, 1, 1 } },
	medium = { UpperArm = { 9, 12, 1, 1 }, LowerArm = { 8, 12, 1, 1 }, UpperLeg = { 9, 12, 1, 1 }, LowerLeg = { 8, 12, 1, 1 } },
	low = { UpperArm = { 5, 8, 0, 0 }, LowerArm = { 4, 8, 0, 0 }, UpperLeg = { 5, 8, 0, 0 }, LowerLeg = { 4, 8, 0, 0 } },
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
Limbs.belly = belly
Limbs.win = win
Limbs.along = along

------------------------------------------------------------------------
-- Per-limb anatomy (sizes in studs, scaled by the part's box width)
------------------------------------------------------------------------
-- returns spec { rx / rz = Curve(b) half axes of the base ellipse, mus / grooves = bellies, b0 / b1 = the
-- loft's bone range, capS / capE = { depth (x scale), shift (x scale, toward the medial side) }, flexIds }
local function upperArm(sk, P, side, sx)
	local lv, V, fk, def = P.lv, P.V, min(P.fatK, 1.2), P.defE
	local fem = P.female
	local k = Kit.SideK(P, side == "Right" and 1 or -1)
	local fl = P.pv.flat
	local el = P.pv.elong
	local sz = fem and 0.84 or 1
	local dk = fem and 0.75 or 1
	-- the base already has an arm's shape (no tube on an untrained body): the deltoid's mass at the top, the
	-- insertion waist a third of the way down, the biceps / triceps bellies, the flat above the elbow and
	-- the epicondyles; above the pivot the section closes over the shoulder into the deltoid cap
	-- (the bone slants out from the shoulder pivot to the elbow, so each ring's lateral side is its highest point:
	-- the top rings are small (the lateral rim stays ~0.1 above the pivot) and the deltoid's outline slopes
	-- down and out from the cap instead of standing up as a corner; the medial rim reaches in over the torso's
	-- shoulder edge)
	-- (the top rings sit a little deeper inside the torso's shoulder: the cap's rim stays under the trapezius
	-- and the torso's rounded shoulder, so no ring-shaped step shows where the two pieces overlap)
	local rx = Kit.Curve({ { -0.04, 0.15 }, { 0.0, 0.19 }, { 0.05, 0.225 }, { 0.12, 0.252 }, { 0.22, 0.262 }, { 0.35, 0.256 }, { 0.5, 0.25 }, { 0.65, 0.247 }, { 0.75, 0.242 }, { 0.9, 0.232 }, { 0.97, 0.228 }, { 1.0, 0.226 }, { 1.08, 0.214 } })
	local rz = Kit.Curve({ { -0.04, 0.17 }, { 0.0, 0.205 }, { 0.05, 0.235 }, { 0.12, 0.257 }, { 0.22, 0.268 }, { 0.4, 0.252 }, { 0.6, 0.244 }, { 0.75, 0.236 }, { 0.9, 0.223 }, { 0.97, 0.218 }, { 1.0, 0.216 }, { 1.08, 0.205 } })
	local delt = (0.05 + 0.09 * lv.sideDelt) * fl * k * dk
	local bi = (0.04 + 0.11 * lv.biceps) * fl * V.bicepsHeight * k
	local tri = (0.045 + 0.09 * lv.triceps) * fl * k
	local peakB = 0.56 + V.bicepsPeak - 0.04 * (el - 1)
	local mus = {
		-- deltoid: lateral head (the shoulder's roundness, widest a little under the acromion), anterior,
		-- posterior; all end in the V insertion a third of the way down
		-- (fullest a quarter of the way down, fading out toward the pivot: the bulge is the deltoid's belly
		-- hanging off the shoulder, not a ball sitting on top of it)
		{ a = LAT, w = 1.3, b0 = 0.0, bp = 0.27, b1 = 0.64, vee = 0.3, h = delt, sharp = 0.9, id = "delt" },
		{ a = FRONT - 0.3, w = 1.0, b0 = -0.02, bp = 0.23, b1 = 0.58, vee = 0.3, h = (0.032 + 0.075 * lv.frontDelt) * fl * V.deltFront * k * dk, sharp = 0.95, id = "delt" },
		{ a = BACK + 0.35, w = 1.0, b0 = -0.02, bp = 0.24, b1 = 0.58, vee = 0.3, h = (0.028 + 0.07 * lv.rearDelt) * fl * k * dk, sharp = 0.95, id = "delt" },
		-- biceps (two heads, one peak) and brachialis peeking out laterally
		{ a = FRONT + 0.05, w = 0.95, b0 = 0.2, bp = peakB, b1 = 0.95, h = bi, sharp = 1.25, id = "biceps" },
		{ a = FRONT - 0.85, w = 0.6, b0 = 0.42, bp = 0.74, b1 = 0.98, h = (0.012 + 0.04 * lv.biceps) * fl * k, id = "brach" },
		-- triceps: the long head (back / inner, bulging high) and the lateral head (back / outer) = the horseshoe
		{ a = BACK - 0.38, w = 0.95, b0 = 0.06, bp = 0.35, b1 = 0.88, h = tri, id = "triceps" },
		{ a = BACK + 0.62, w = 0.72, b0 = 0.12, bp = 0.34, b1 = 0.66, h = tri * 0.85, sharp = 1.1, id = "triceps" },
		-- the cap's inner rim: the deltoid's origin along the clavicle / acromion / scapular spine reaches in over
		-- the torso's shoulder edge (the dome leans toward the neck, the torso's corner stays under it)
		{ a = MED, w = 1.5, b0 = -0.14, bp = -0.03, b1 = 0.16, h = 0.07, id = "bone" },
		-- elbow: olecranon behind, the epicondyles either side
		-- (above the pivot: the upper arm's end stays a little inside the forearm's top, so its end dome tucks in
		-- without a ring)
		{ a = MED, w = 0.6, b0 = 0.8, bp = 0.92, b1 = 1.0, h = 0.012, id = "bone" },
		{ a = LAT, w = 0.6, b0 = 0.8, bp = 0.92, b1 = 1.0, h = 0.008, id = "bone" },
		-- fat: the back of the arm first
		{ a = BACK - 0.2, w = 1.4, b0 = 0.05, bp = 0.45, b1 = 0.9, h = 0.06 * fk, id = "fat" },
	}
	local grooves = {
		-- biceps / triceps valley on the inside (the brachial vessels), deltoid insertion, triceps tendon flat
		{ a = MED + 0.12, w = 0.42, b0 = 0.18, bp = 0.55, b1 = 0.92, h = (0.012 + 0.022 * def) * (0.4 + 0.6 * lv.biceps), id = "g" },
		{ a = LAT + 0.55, w = 0.38, b0 = 0.3, bp = 0.48, b1 = 0.7, h = (0.008 + 0.018 * def) * (0.4 + lv.sideDelt * 0.6), id = "g" },
		{ a = BACK, w = 0.6, b0 = 0.62, bp = 0.82, b1 = 0.98, h = (0.006 + 0.016 * def) * lv.triceps, id = "g" },
		{ a = FRONT - 0.55, w = 0.35, b0 = 0.38, bp = 0.62, b1 = 0.86, h = (0.006 + 0.012 * def) * lv.biceps, id = "g" },
		-- the front deltoid's border with the pec (the deltopectoral line running up into the chest) and the
		-- deltoid's back border over the triceps: soft tie-in grooves instead of a ring round the cap
		{ a = FRONT + 0.75, w = 0.4, b0 = -0.02, bp = 0.2, b1 = 0.42, h = (0.006 + 0.012 * def) * (0.4 + 0.6 * lv.frontDelt), id = "g" },
		{ a = BACK + 0.75, w = 0.45, b0 = 0.25, bp = 0.42, b1 = 0.6, h = (0.006 + 0.014 * def) * (0.4 + 0.6 * lv.rearDelt), id = "g" },
	}
	-- the top dome leans toward the neck: the deltoid cap rounds over the shoulder and into the trapezius slope
	return { rx = rx, rz = rz, scale = sx * sz, mus = mus, grooves = grooves, b0 = -0.04, b1 = 1.08, capS = { 0.08, 0 }, capE = { 0.17, 0 }, ringWarp = 1.25, endBend = 0.4,
		flexIds = { biceps = 0.35, delt = 0.12, triceps = 0.18, brach = 0.25 } }
end

local function lowerArm(sk, P, side, sx)
	local lv, fk, def = P.lv, min(P.fatK, 1.2), P.defE
	local fem = P.female
	local k = Kit.SideK(P, side == "Right" and 1 or -1)
	local fl = P.pv.flat
	local sz = fem and 0.84 or 1
	-- a cone on every build: full just below the elbow (the brachioradialis / flexor mass), slim at the wrist;
	-- the root a little inside the upper arm's end (the parent covers the joint)
	-- (wide across the elbow, the flexor and extensor masses; wide thumb-to-little-finger at the wrist)
	-- (the top ring sits inside the upper arm's end; just below the pivot the forearm is fuller than the upper
	-- arm's end, whose dome tucks in at the elbow crease)
	local rx = Kit.Curve({ { -0.2, 0.17 }, { -0.04, 0.2 }, { 0.02, 0.232 }, { 0.1, 0.245 }, { 0.25, 0.258 }, { 0.55, 0.208 }, { 0.85, 0.158 }, { 1.0, 0.146 }, { 1.12, 0.142 } })
	local rz = Kit.Curve({ { -0.2, 0.16 }, { -0.04, 0.19 }, { 0.02, 0.222 }, { 0.1, 0.231 }, { 0.25, 0.236 }, { 0.55, 0.198 }, { 0.85, 0.168 }, { 1.0, 0.166 }, { 1.12, 0.162 } })
	local fa = (0.04 + 0.075 * lv.forearms) * fl * k
	local mus = {
		-- brachioradialis + wrist extensors (thumb side / top), flexors (palm side), extensors (back)
		{ a = FRONT - 0.45, w = 0.9, b0 = 0.0, bp = 0.25, b1 = 0.72, h = fa, sharp = 1.1, id = "fore" },
		{ a = MED - 0.3, w = 1.0, b0 = 0.02, bp = 0.26, b1 = 0.75, h = fa * 0.85, id = "fore" },
		{ a = LAT - 0.55, w = 0.75, b0 = 0.02, bp = 0.24, b1 = 0.62, h = fa * 0.6, id = "fore" },
		{ a = BACK, w = 0.75, b0 = -0.05, bp = 0.03, b1 = 0.16, h = 0.022, id = "bone" },
		-- the wrist bones (ulna head on the pinky side)
		{ a = BACK + 0.6, w = 0.45, b0 = 0.86, bp = 0.95, b1 = 1.04, h = 0.012, id = "bone" },
		{ a = BACK - 0.3, w = 1.5, b0 = 0.05, bp = 0.3, b1 = 0.7, h = 0.025 * fk, id = "fat" },
	}
	local grooves = {
		-- the ulna's ridge between the flexors and the extensors, the tendons near the wrist
		{ a = BACK + 0.15, w = 0.4, b0 = 0.15, bp = 0.5, b1 = 0.85, h = (0.008 + 0.014 * def) * (0.4 + 0.6 * lv.forearms), id = "g" },
		{ a = FRONT + 0.2, w = 0.35, b0 = 0.2, bp = 0.42, b1 = 0.7, h = (0.004 + 0.012 * def) * lv.forearms, id = "g" },
	}
	-- (a short, blunt end past the wrist: the hand's heel comes out of it at a steep angle, a clean wrist line;
	-- a long dome would poke out of the thin palm)
	-- (the dome past the elbow pivot is short, ~0.4 of the forearm's radius there: the olecranon tucked under
	-- the upper arm's back; a long dome stood out behind the elbow as a knob whenever the arm bent)
	return { rx = rx, rz = rz, scale = sx * sz, mus = mus, grooves = grooves, b0 = -0.04, b1 = 1.06, capS = { 0.08, 0 }, capE = { 0.1, 0 }, flexIds = { fore = 0.3 } }
end

local function upperLeg(sk, P, side, sx)
	local lv, V, fk, def = P.lv, P.V, min(P.fatK, 1.2), P.defE
	local fem = P.female
	local fl = P.pv.flat
	-- the knee: the thigh tapers into it (no ball where the end dome overlaps the calf)
	-- (the rings run a little past the knee pivot just under the shin's top, so the thigh's end dome tucks into
	-- the shin with no ball or ring)
	local rx = Kit.Curve({ { -0.2, 0.2 }, { -0.1, 0.36 }, { 0.0, 0.47 }, { 0.12, 0.5 }, { 0.3, 0.48 }, { 0.5, 0.445 }, { 0.75, 0.385 }, { 0.9, 0.34 }, { 1.0, 0.3 }, { 1.07, 0.276 } })
	-- (shallower than the R15 box: a thigh is ~0.8 of the torso's depth)
	local rz = Kit.Curve({ { -0.2, 0.2 }, { -0.1, 0.33 }, { 0.0, 0.415 }, { 0.12, 0.435 }, { 0.3, 0.425 }, { 0.5, 0.395 }, { 0.75, 0.345 }, { 0.9, 0.31 }, { 1.0, 0.282 }, { 1.07, 0.258 } })
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
		-- hip / trochanter and the female hip curve (the waist-to-hip line)
		{ a = LAT, w = 0.9, b0 = -0.08, bp = 0.1, b1 = fem and 0.5 or 0.4, h = 0.025 + (fem and 0.1 or 0) + 0.04 * fk, id = "hip" },
		-- fat: outer and inner thigh
		{ a = LAT + 0.2, w = 1.3, b0 = -0.02, bp = 0.25, b1 = 0.7, h = 0.045 * fk + (fem and 0.035 or 0), id = "fat" },
		{ a = MED, w = 1.2, b0 = -0.02, bp = 0.2, b1 = 0.6, h = 0.05 * fk + (fem and 0.03 or 0), id = "fat" },
	}
	local grooves = {
		-- the IT band down the outside, the sartorius line, the quad / hamstring split
		{ a = LAT - 0.1, w = 0.35, b0 = 0.3, bp = 0.65, b1 = 0.92, h = (0.008 + 0.02 * def) * (0.4 + 0.6 * lv.quads), id = "g" },
		{ a = FRONT + 0.42, w = 0.28, b0 = 0.25, bp = 0.55, b1 = 0.8, h = (0.004 + 0.014 * def) * lv.quads, id = "g" },
		{ a = MED + 0.7, w = 0.35, b0 = 0.3, bp = 0.6, b1 = 0.85, h = (0.004 + 0.012 * def) * lv.hamstrings, id = "g" },
		-- behind the knee
		{ a = BACK, w = 0.8, b0 = 0.88, bp = 1.0, b1 = 1.1, h = 0.02, id = "g" },
	}
	return { rx = rx, rz = rz, scale = sx, mus = mus, grooves = grooves, b0 = -0.2, b1 = 1.07, capS = { 0.15, 0 }, capE = { 0.16, 0 }, flexIds = { quad = 0.28, ham = 0.15 } }
end

local function lowerLeg(sk, P, side, sx)
	local lv, V, fk, def = P.lv, P.V, min(P.fatK, 1.2), P.defE
	local fem = P.female
	local fl = P.pv.flat
	-- the top a little inside the thigh's end (the parent covers the knee)
	local rx = Kit.Curve({ { 0.0, 0.29 }, { 0.12, 0.296 }, { 0.35, 0.28 }, { 0.6, 0.232 }, { 0.82, 0.176 }, { 0.95, 0.163 }, { 1.12, 0.156 } })
	local rz = Kit.Curve({ { 0.0, 0.27 }, { 0.12, 0.274 }, { 0.35, 0.262 }, { 0.6, 0.21 }, { 0.82, 0.152 }, { 0.95, 0.145 }, { 1.12, 0.138 } })
	local hi = V.calfHigh
	local c = (0.05 + 0.1 * lv.calves) * fl + 0.025 * fk
	local mus = {
		-- gastrocnemius: the medial head bigger and lower, the lateral head higher; both end in a V into the
		-- Achilles tendon
		{ a = BACK - 0.48, w = 0.92, b0 = 0.04, bp = 0.28 + hi, b1 = 0.63 + hi, h = c * V.calfRatio, sharp = 1.4, id = "calf" },
		{ a = BACK + 0.5, w = 0.85, b0 = 0.03, bp = 0.22 + hi, b1 = 0.55 + hi, h = c * 0.85 / V.calfRatio ^ 0.5, sharp = 1.4, id = "calf" },
		-- soleus widening the lower calf either side of the tendon, tibialis anterior beside the shin
		{ a = BACK - 1.0, w = 0.7, b0 = 0.3, bp = 0.55, b1 = 0.8, h = (0.02 + 0.04 * lv.calves) * fl, id = "sol" },
		{ a = BACK + 1.0, w = 0.7, b0 = 0.3, bp = 0.52, b1 = 0.78, h = (0.02 + 0.035 * lv.calves) * fl, id = "sol" },
		{ a = FRONT - 0.5, w = 0.55, b0 = 0.06, bp = 0.3, b1 = 0.7, h = (0.015 + 0.04 * lv.calves) * fl, id = "tib" },
		-- the tibial tuberosity under the kneecap, the ankle bones (medial higher, lateral lower), the
		-- Achilles tendon's cord
		{ a = FRONT + 0.15, w = 0.55, b0 = 0.02, bp = 0.1, b1 = 0.2, h = 0.012, id = "bone" },
		{ a = MED, w = 0.5, b0 = 0.86, bp = 0.95, b1 = 1.04, h = 0.035, id = "bone" },
		{ a = LAT, w = 0.5, b0 = 0.9, bp = 1.0, b1 = 1.1, h = 0.035, id = "bone" },
		{ a = BACK, w = 0.22, b0 = 0.68, bp = 0.88, b1 = 1.06, h = 0.02, id = "tendon" },
		{ a = BACK - 0.3, w = 1.4, b0 = 0.05, bp = 0.3, b1 = 0.7, h = 0.03 * fk + (fem and 0.01 or 0), id = "fat" },
	}
	local grooves = {
		-- the hollows either side of the Achilles tendon, the flat of the shin bone, the split between the calf heads
		{ a = BACK, w = 0.45, b0 = 0.7, bp = 0.88, b1 = 1.0, h = 0.05, id = "g" },
		{ a = FRONT + 0.4, w = 0.45, b0 = 0.15, bp = 0.5, b1 = 0.85, h = 0.012, id = "g" },
		{ a = BACK, w = 0.22, b0 = 0.08, bp = 0.32, b1 = 0.58, h = 0.008 + (0.004 + 0.012 * def) * lv.calves, id = "g" },
	}
	return { rx = rx, rz = rz, scale = sx, mus = mus, grooves = grooves, b0 = -0.02, b1 = 1.08, capS = { 0.24, 0 }, capE = { 0.16, 0 }, flexIds = { calf = 0.3 } }
end

Limbs.Specs = { UpperArm = upperArm, LowerArm = lowerArm, UpperLeg = upperLeg, LowerLeg = lowerLeg }

-- crown (muscle bellies catching the light) and groove (separations) at (bone, angle): the painter's
-- channels, per vertex in Build and per texel in the colour texture
function Limbs.Channels(spec, bb, ang)
	local cr, gr = 0, 0
	for _, mm in ipairs(spec.mus) do
		local h = belly(bb, ang, mm)
		if h > 0 and mm.id ~= "fat" and mm.id ~= "bone" and mm.id ~= "tendon" then
			cr += h / max(0.02, mm.h) * 0.6
		end
	end
	for _, gg in ipairs(spec.grooves) do
		gr += belly(bb, ang, gg) / max(0.004, gg.h) * min(1, gg.h / 0.012)
	end
	return clamp(cr, 0, 1), clamp(gr, 0, 1)
end

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
	-- a vein running past a garment edge would show through it: only the stretch above the edge stays
	if kind ~= "LowerLeg" and calfTop < 1 then
		local kept = {}
		for _, path in ipairs(out) do
			local pts = {}
			for _, p in ipairs(path.pts) do
				if p[1] < calfTop - 0.04 then
					pts[#pts + 1] = p
				end
			end
			if #pts >= 2 then
				kept[#kept + 1] = { pts = pts, r = path.r }
			end
		end
		out = kept
	end
	return #out > 0 and out or nil
end

------------------------------------------------------------------------
-- One limb mesh (body space)
------------------------------------------------------------------------
-- opt.zones = { { b0, b1, kind } ... } covering the loft's bone range in order (kind "skin" | "trunk" (the
-- satin trunk leg) | "trunkcuff" (long trunks below the knee) | "boot" | "glove" (the glove's cuff) | "wrap");
-- nil = all skin. Zone edges become ring pairs.
local function zoneAt(zones, bb)
	for _, z in ipairs(zones) do
		if bb <= z[2] + 1e-6 then
			return z
		end
	end
	return zones[#zones]
end

local limbFrameFn -- (limbFrame, defined below)

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
	local ux, uy, uz = dx / L, dy / L, dz / L
	local box = sk.size[side .. kind]
	local spec = Limbs.Specs[kind](sk, P, side, box[1])
	local S = spec.scale
	local B0, B1 = spec.b0, spec.b1
	-- the zones span exactly the loft's range (a caller gives the inner edges only; a zone that starts past
	-- the end, or ends before the start, is dropped)
	local zones = {}
	for _, z in ipairs(opt.zones or { { B0, B1, "skin" } }) do
		if z[1] < B1 - 0.03 and z[2] > B0 + 0.03 then
			zones[#zones + 1] = { max(z[1], B0), min(z[2], B1), z[3] }
		end
	end
	if #zones == 0 then
		zones[1] = { B0, B1, "skin" }
	end
	zones[1][1], zones[#zones][2] = B0, B1
	local mus, grooves = spec.mus, spec.grooves
	local rx, rz = spec.rx, spec.rz
	local nM = #mus
	-- the satin leg hangs from the widest part of the thigh: its reference section (the mean muscle bulk near
	-- the top), and the trunk zone's hem
	local trunkZ
	for _, z in ipairs(zones) do
		if z[3] == "trunk" then
			trunkZ = z
		end
	end
	local topEx, topEz, topBulge = rx(0.12), rz(0.12), 0
	if trunkZ then
		for q = 0, 7 do
			for k = 1, nM do
				topBulge += belly(0.12, TAU * q / 8, mus[k])
			end
		end
		-- (most of the muscle under the satin only fills it out: the leg hangs from the hip, it is not a tube
		-- inflated round the thigh)
		topBulge = topBulge / 8 * 0.7
	end
	local folds = opt.foldPhase or 1.3
	-- the satin leg's half extents (lateral, front, back) at flare t (0 at the top, 1 at the opening)
	-- (an A-line from the hip: the sides flare most, the front stays flat, the back carries the seat's fullness)
	local function trunkDims(t, long)
		local flare = long and (0.045 * t) or (0.11 * t)
		return (topEx + topBulge) * S * (1.02 + flare) + 0.022 * S, (topEz + topBulge) * S * (0.97 + flare * 0.3) + 0.016 * S,
			(topEz + topBulge) * S * (1.03 + flare * 0.5) + 0.024 * S
	end
	-- the skin's radius: base ellipse + bellies - grooves
	local function skinR(bb, ang, smoothK)
		local ex, ez = rx(bb) * S, rz(bb) * S
		local c, s = cos(ang), sin(ang)
		local r = 1 / sqrt((c / ex) ^ 2 + (s / ez) ^ 2)
		local relief = 0
		for k = 1, nM do
			relief += belly(bb, ang, mus[k]) * S
		end
		for k = 1, #grooves do
			relief -= belly(bb, ang, grooves[k]) * S
		end
		return r + relief * (smoothK or 1)
	end
	local function radiusAt(bb, ang, z)
		z = z or zoneAt(zones, bb)
		local kind2 = z[3]
		if kind2 == "skin" then
			return skinR(bb, ang)
		elseif kind2 == "trunk" then
			-- satin over the thigh: a loose rounded-rectangle section (flat front, the medial face on the body's
			-- midline, so from the front the two legs read as one garment with a seam between them, not two
			-- tubes), flaring a little toward the opening, a few soft folds, a slight forward / back swing; above
			-- the hip it runs inside the trunks' seat (the LowerTorso piece carries the hips)
			local hemB = z[2]
			-- (no flare above the hip line: the seat's straight sides meet the legs there)
			local t = smooth(0.05, max(hemB, 0.15), bb)
			local c, s = cos(ang), sin(ang)
			local long = hemB >= 0.97
			local latX, fZ, bZ = trunkDims(t, long)
			-- the medial face: on the body's midline (a hair short of it, so the legs' faces touch, not cross)
			local px = a[1] + ux * L * bb
			local medX = max(0.05, abs(px) - 0.006)
			local ex = c >= 0 and latX or min(latX, medX)
			local ez = s >= 0 and fZ or bZ
			-- (squarer toward the medial face: the two legs' fronts meet flush on the midline)
			-- (the front panel flatter (squarer) than the back)
			local n = (c < 0 and 2.4 + 1.2 * (-c) or 2.4) + (s > 0 and 0.5 * s or 0)
			local loose = 1 / ((abs(c) / ex) ^ n + (abs(s) / ez) ^ n) ^ (1 / n)
			if long then
				-- knee-length trunks hang from the hip and taper toward the knee (never onto the skin)
				loose *= 1 - 0.16 * smooth(0.15, 1.0, bb)
			end
			-- soft folds (none on the medial face, which meets the other leg's)
			local medK = 1 - win(ang, MED, 0.9)
			-- drape: a few broad folds hanging from the seat and finer creases toward the opening
			loose += (0.016 * sin(3 * ang + folds + 2.2 * bb) + 0.01 * sin(7 * ang + 2 * folds + 4 * bb) * t) * S * (0.3 + 0.7 * t) * medK
			loose += 0.015 * S * sin(ang) * t
			-- the creases where the satin bunches at the inner thigh (diagonal, from the crotch out and down)
			loose -= 0.008 * S * max(0, sin(9 * (ang - FRONT) + 14 * bb)) ^ 3 * win(ang, MED - 0.55, 0.8) * (1 - smooth(0.12, 0.4, bb))
			-- above the hip the leg is inside the trunks' seat (the LowerTorso piece carries the hips)
			loose = lerp(skinR(bb, ang) + 0.01 * S, loose, smooth(-0.14, 0.04, bb))
			return max(skinR(bb, ang, 0.8) + 0.014 * S, loose)
		elseif kind2 == "trunkcuff" then
			-- (full relief: the calf right under the cuff never stands out past its hem)
			return skinR(bb, ang) + 0.03 * S
		elseif kind2 == "sock" then
			-- knit over the ankle: a hair proud of the skin above it
			return skinR(bb, ang, 0.85) + 0.01 * S
		elseif kind2 == "boot" then
			-- leather over the ankle and shin: the leg's shape with most of its relief (the skin above the collar
			-- stays inside it), a padded collar at the top
			local top = z[1]
			local collar = Kit.bell((bb - (top + 0.035)) / 0.05)
			-- below the ankle the shaft flares back over the heel counter (one boot, no ledge at the heel) and a
			-- raised tongue runs down the front under the laces
			local heel = 0.035 * smooth(0.92, 1.1, bb) * win(ang, BACK, 1.9)
			local tongue = 0.007 * win(ang, FRONT, 0.45) * smooth(top + 0.05, top + 0.1, bb)
			return skinR(bb, ang, 0.8) + (0.03 + 0.016 * collar + heel + tongue) * S
		elseif kind2 == "glove" then
			-- the glove's cuff: a padded sleeve round the wrist, a little wider toward the hand, a rolled top edge
			local top = z[1]
			local c, s = cos(ang), sin(ang)
			local ex, ez = (rx(top) * 1.02 + 0.07) * S, (rz(top) * 1.06 + 0.07) * S
			local r = 1 / sqrt((c / ex) ^ 2 + (s / ez) ^ 2)
			local roll = Kit.bell((bb - (top + 0.03)) / 0.045)
			return r * (1 + 0.06 * smooth(top, z[2], bb)) + 0.012 * S * roll
		elseif kind2 == "wrap" then
			-- cotton wrap: snug, smoothing the tendons, a few layers thick
			return skinR(bb, ang, 0.3) + 0.016 * S + 0.004 * S * sin(bb * 60)
		end
		return skinR(bb, ang)
	end
	-- the loft's centre line: the bone, except (spec.endBend) the lower part of the upper arm turns toward the
	-- forearm's axis, so at the elbow both pieces are coaxial (the R15 bind pose has the upper arm slanting
	-- out from the shoulder pivot while the forearm hangs straight: tubes meeting at that kink show a ragged
	-- seam). x offset only: a cubic, zero (and flat) where it starts, zero at the pivot with the end tangent
	-- along the forearm; past the pivot it continues along that tangent.
	local sg = side == "Right" and 1 or -1
	local endA, endS0, endSpan = nil, 0, 1
	if spec.endBend and kind == "UpperArm" then
		local w, e = sk.piv[side .. "Wrist"], sk.piv[side .. "Elbow"]
		local fx, fy = w[1] - e[1], w[2] - e[2]
		if abs(fy) > 1e-3 then
			endS0 = spec.endBend * L
			endSpan = L - endS0
			endA = endSpan * (uy * fx / fy - ux)
		end
	end
	local function center(bb)
		local x, y, z = a[1] + ux * L * bb, a[2] + uy * L * bb, a[3] + uz * L * bb
		if endA then
			local s = bb * L
			if s > endS0 then
				local t = (s - endS0) / endSpan
				if t <= 1 then
					x += endA * t * t * (t - 1)
				else
					x += endA / endSpan * (s - L)
				end
			end
		end
		return x, y, z
	end
	-- the frame (lateral, front) of the centre line at bb (the loft's frames: side hint projected, front -Z)
	local function frameAt(bb)
		local h = 0.01
		local x0, y0, z0 = center(bb - h)
		local x1, y1, z1 = center(bb + h)
		local tx, ty, tz = x1 - x0, y1 - y0, z1 - z0
		local tl = sqrt(tx * tx + ty * ty + tz * tz)
		return limbFrameFn(tx / tl, ty / tl, tz / tl, sg)
	end
	return { R = R, a = a, b = b, L = L, ux = ux, uy = uy, uz = uz, spec = spec, S = S, zones = zones, radiusAt = radiusAt, skinR = skinR,
		center = center, frameAt = frameAt, trunkDims = trunkDims }
end

-- the satin trunk leg's top (the LowerTorso seat matches it so the leg never steps out of the seat): body-space
-- x of the leg's outer side, its front and back extents (z), for the thigh built with these zones
-- (also its lateral half-width and the z of its centre line there: the seat's side trim lines up with the
-- legs' trim bands with them)
function Limbs.TrunkTop(sk, P, side, zones)
	local c = setup(sk, P, "full", side, "UpperLeg", { zones = zones })
	local latX, fZ, bZ = c.trunkDims(0, false)
	local _, _, cz = c.center(c.zones[1][1])
	return abs(c.a[1]) + latX, fZ, bZ, latX, cz
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
limbFrameFn = limbFrame

-- body-space point on the surface Build makes with the same options (garments included) at (bone, angle)
function Limbs.SurfacePoint(sk, P, side, kind, opt, bb, ang)
	local c = setup(sk, P, "full", side, kind, opt)
	local r = c.radiusAt(bb, ang)
	-- the frame of the (possibly bent) centre line there
	local sx, sy, sz, fx, fy, fz = c.frameAt(bb)
	local cs, sn = cos(ang), sin(ang)
	local px, py, pz = c.center(bb)
	return { px + (sx * cs + fx * sn) * r, py + (sy * cs + fy * sn) * r, pz + (sz * cs + fz * sn) * r }
end

-- the same point plus the outward (radial) direction and the direction up the bone there (lettering plates)
function Limbs.SurfaceFrame(sk, P, side, kind, opt, bb, ang)
	local c = setup(sk, P, "full", side, kind, opt)
	local r = c.radiusAt(bb, ang)
	local sx, sy, sz, fx, fy, fz = c.frameAt(bb)
	local cs, sn = cos(ang), sin(ang)
	local nx, ny, nz = sx * cs + fx * sn, sy * cs + fy * sn, sz * cs + fz * sn
	local px, py, pz = c.center(bb)
	local x0, y0, z0 = c.center(bb - 0.02)
	local x1, y1, z1 = c.center(bb + 0.02)
	local tx, ty, tz = x0 - x1, y0 - y1, z0 - z1
	local tl = sqrt(tx * tx + ty * ty + tz * tz)
	return { px + nx * r, py + ny * r, pz + nz * r }, { nx, ny, nz }, { tx / tl, ty / tl, tz / tl }
end

-- ring parameters: every zone gets rings in proportion to its length (at least two), a zone edge is a ring
-- pair EDGE studs apart (the garment's edge, then what is under it)
local EDGE = 0.012
local function ringParams(zones, rings, L)
	local B0, B1 = zones[1][1], zones[#zones][2]
	local span = B1 - B0
	local gap = EDGE / L
	local nz = #zones
	local counts, total = {}, 0
	for i, z in ipairs(zones) do
		counts[i] = 2
		total += 2
	end
	-- the remaining rings by length
	while total < rings do
		local best, bestK = 1, -1
		for i, z in ipairs(zones) do
			local k = (z[2] - z[1]) / span / counts[i]
			if k > bestK then
				best, bestK = i, k
			end
		end
		counts[best] += 1
		total += 1
	end
	local out, kinds = {}, {}
	for i, z in ipairs(zones) do
		local z0 = i > 1 and z[1] + gap or z[1]
		local z1 = z[2]
		local n = counts[i]
		for k = 1, n do
			out[#out + 1] = z0 + (z1 - z0) * (k - 1) / (n - 1)
			kinds[#out] = z
		end
	end
	return out, kinds, nz
end

-- returns mesh, info { grid info (Kit.GridLoft: rows, rowV after AnatomyBody's GridUV), rings, sides, B / A (bone
-- parameter and angle per vertex: cap and vein vertices get their own), Z (zone per vertex), crown, groove,
-- flex (per vertex radial delta for the flex morph), dir (per vertex radial direction) }
function Limbs.Build(sk, P, lod, side, kind, opt)
	opt = opt or {}
	local ctx = setup(sk, P, lod, side, kind, opt)
	local R = ctx.R
	local res = R[kind]
	local rings, sides = res[1], res[2]
	local sg = side == "Right" and 1 or -1
	local a, L = ctx.a, ctx.L
	local ux, uy, uz = ctx.ux, ctx.uy, ctx.uz
	local spec, S = ctx.spec, ctx.S
	local zones = ctx.zones
	local Bs, ringZone = ringParams(zones, rings, L)
	rings = #Bs
	if spec.ringWarp and #zones == 1 then
		-- rings crowd toward the start (the deltoid cap's curvature), same count
		local B0, B1 = zones[1][1], zones[1][2]
		for i = 1, rings do
			local t = (Bs[i] - B0) / (B1 - B0)
			Bs[i] = B0 + (B1 - B0) * t ^ spec.ringWarp
		end
	end
	local spine = table.create(rings)
	for i = 1, rings do
		local x, y, z = ctx.center(Bs[i])
		spine[i] = { x, y, z }
	end
	local mus, grooves = spec.mus, spec.grooves
	local nM = #mus
	local radiusAt = ctx.radiusAt
	local m = MeshKit.New(side .. kind)
	-- the domes: the start one leans toward the medial side (deltoid cap: toward the neck)
	local sx, sy, sz = limbFrame(ux, uy, uz, sg)
	local capS, capE = spec.capS, spec.capE
	local shS = capS[2] ~= 0 and { -sx * capS[2] * S, -sy * capS[2] * S, -sz * capS[2] * S } or nil
	local info = Kit.GridLoft(m, MeshKit, {
		rings = rings, sides = sides, spine = spine, exact = true, sideHint = { sg, 0, 0 }, frontHint = { 0, 0, -1 }, rowB = Bs,
		radius = function(t, ang)
			local i = math.floor(t * (rings - 1) + 0.5) + 1
			return radiusAt(Bs[i], ang, ringZone[i])
		end,
		capS = { depth = capS[1] * S, rings = res[3], shift = shS, bDepth = capS[1] * S / L },
		capE = { depth = capE[1] * S, rings = res[4], bDepth = capE[1] * S / L },
	})
	-- veins: low, wide ridges lying on the skin (Kit.Strand), following a path in (bone, angle)
	local veinFirst = m.nv + 1
	local veinN = {}
	local veinBA = {}
	if opt.veins and #opt.veins > 0 then
		for _, path in ipairs(opt.veins) do
			local n = 5
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
				local fsx, fsy, fsz, ffx, ffy, ffz = ctx.frameAt(bb)
				local ox, oy, oz = fsx * c + ffx * sn, fsy * c + ffy * sn, fsz * c + ffz * sn
				local px, py, pz = ctx.center(bb)
				pts[k] = { px + ox * r, py + oy * r, pz + oz * r }
				nrm[k] = { ox, oy, oz }
			end
			local first = Kit.Strand(m, MeshKit, pts, nrm, path.r, "vein", veinN)
			-- every strand vertex keeps the (bone, angle) of the skin under it: its UV and its paint
			local per = 6 -- Kit.Strand section points
			for k = 1, n do
				local tt = (k - 1) / (n - 1) * (#src - 1)
				local j0 = math.min(#src - 1, math.floor(tt) + 1)
				local w = tt - (j0 - 1)
				local bb = src[j0][1] + (src[j0 + 1][1] - src[j0][1]) * w
				local ang = src[j0][2] + (src[j0 + 1][2] - src[j0][2]) * w
				for q = 0, per - 1 do
					veinBA[first + (k - 1) * per + q] = { bb, ang }
				end
			end
			-- the two tips
			veinBA[first + n * per] = veinBA[first]
			veinBA[first + n * per + 1] = veinBA[first + (n - 1) * per]
		end
	end
	-- the short trunks' hem dips a little at the back (the seat's fabric hangs lower behind): the rings round the
	-- hem lean back along the bone (the edge's ring pair moves together, so the edge stays crisp)
	for _, z in ipairs(zones) do
		if z[3] == "trunk" and z[2] < 0.97 then
			local hemB = z[2]
			local Pp = m.P
			for _, row in ipairs(info.rows) do
				local w = row.ring and (1 - smooth(0.03, 0.15, abs(row.b - hemB))) or 0
				if w > 0 then
					for j = 0, row.n - 1 do
						local vi = row.s + j
						local ang = TAU * j / sides
						local d = 0.03 * w * (0.5 - 0.5 * sin(ang))
						Pp[vi * 3 - 2] += ux * d
						Pp[vi * 3 - 1] += uy * d
						Pp[vi * 3] += uz * d
					end
				end
			end
		end
	end
	Kit.GridNormals(m, MeshKit, info)
	for _, e in ipairs(veinN) do
		MeshKit.SetNormal(m, e[1], e[2], e[3], e[4])
	end
	-- per-vertex channels for the painter and the flex shape
	local nv = m.nv
	local crown, groove, flex = table.create(nv, 0), table.create(nv, 0), table.create(nv, 0)
	local dirs = table.create(nv * 3, 0)
	local Bv = table.create(nv, 0)
	local Av = table.create(nv, 0)
	local Zv = table.create(nv, "skin")
	local frames = info.frames
	local flexIds = spec.flexIds
	-- the skin next to a garment edge does not flex past it (a bulge would poke out of the hem / cuff)
	local edges = {}
	for i = 2, #zones do
		local z0, z1 = zones[i - 1], zones[i]
		if (z0[3] == "skin") ~= (z1[3] == "skin") then
			edges[#edges + 1] = z1[1]
		end
	end
	local function flexFade(bb)
		local k = 1
		for _, e in ipairs(edges) do
			k = min(k, smooth(0, 0.15, abs(bb - e)))
		end
		return k
	end
	local rows = info.rows
	for r = 1, #rows do
		local row = rows[r]
		local ring = row.ring
		local bb = row.b
		local z = ring and ringZone[ring] or zoneAt(zones, clamp(bb, zones[1][1], zones[#zones][2]))
		local f = ring and frames[ring] or (row.cap < 0 and frames[1] or frames[#frames])
		local skin = z[3] == "skin"
		local fade = skin and flexFade(bb) or 0
		local bev = clamp(bb, spec.b0, spec.b1)
		for j = 0, row.n - 1 do
			local vi = row.s + j
			local ang = row.n > sides and TAU * j / sides or TAU * (j + 0.5) / sides
			local c, s = cos(ang), sin(ang)
			local cr, gr, fx = 0, 0, 0
			if skin and ring then
				cr, gr = Limbs.Channels(spec, bev, ang)
				for k = 1, nM do
					local mm = mus[k]
					local fk = flexIds[mm.id]
					if fk then
						fx += belly(bev, ang, mm) * fk * S
					end
				end
			end
			crown[vi] = cr
			groove[vi] = gr
			flex[vi] = fx * fade
			dirs[vi * 3 - 2] = f[7] * c + f[10] * s
			dirs[vi * 3 - 1] = f[8] * c + f[11] * s
			dirs[vi * 3] = f[9] * c + f[12] * s
			Bv[vi] = bb
			Av[vi] = ang
			Zv[vi] = z[3]
		end
	end
	-- veins pop out a little on a flex / pump: radially away from the bone; they carry the skin's (b, angle)
	if veinFirst <= nv then
		local Pp = m.P
		for v = veinFirst, nv do
			local px, py, pz = Pp[v * 3 - 2] - a[1], Pp[v * 3 - 1] - a[2], Pp[v * 3] - a[3]
			local al = px * ux + py * uy + pz * uz
			local rx2, ry2, rz2 = px - ux * al, py - uy * al, pz - uz * al
			local l = sqrt(rx2 * rx2 + ry2 * ry2 + rz2 * rz2)
			if l > 1e-6 then
				dirs[v * 3 - 2], dirs[v * 3 - 1], dirs[v * 3] = rx2 / l, ry2 / l, rz2 / l
				flex[v] = 0.008 * S
			end
			local ba = veinBA[v]
			if ba then
				Bv[v], Av[v] = ba[1], ba[2]
			end
			Zv[v] = "vein"
		end
	end
	return m, { kind = kind, side = side, L = L, a = a, ax = { ux, uy, uz }, grid = info, rings = rings, sides = sides, crown = crown,
		groove = groove, flex = flex, dir = dirs, B = Bv, A = Av, Z = Zv, spec = spec, S = S, zones = zones, veinFirst = veinFirst,
		radiusAt = radiusAt, veins = opt.veins }
end

return Limbs
