-- AnimFight: everything a boxer does on his feet in the ring.
--  * style stances that live: every Style (Out-boxer, Swarmer, Slugger, Counter puncher,
--    Boxer-puncher) has its own posture, bounce, guard, hand and head life, weight shifts and feet;
--    layered seeded noise (breathing, weight shifts, glove fidgets, head bob) plus a per-boxer
--    persona (tempo, sizes, quirks, guard height) so two boxers of one style never move alike
--  * kinetic-chain punches: anticipation -> legs / hips -> shoulders -> fist (accelerating into the
--    target) -> contact snap -> recovery, per punch type, with variants picked from the boxer's seed
--    and the combination position; one layer per hand so combinations overlap like real ones, the
--    body schedule continues from wherever the last punch left it; fists aim at the opponent's
--    head or torso (body shots change level with the knees, not the waist)
--  * defence: slips, rolls, parries, pivots, the shell, blocked shots
--  * hit reactions scaled by severity (light snap / medium stumble step / heavy legs shake and
--    catch steps / critical buckle), directional by punch and hand, body-shot folds, liver shots
--  * daze levels, stumbles, the clinch, walkout, rest (on the stool when it is there), win, lose
local K = require(script.Parent:WaitForChild("AnimKit"))
local R = require(script.Parent:WaitForChild("AnimRig"))
local L = require(script.Parent:WaitForChild("AnimLoco"))

local AnimFight = {}

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local PI = math.pi
local sin, cos, abs, max, min, exp, sqrt, floor = math.sin, math.cos, math.abs, math.max, math.min, math.exp, math.sqrt, math.floor
local clamp = math.clamp
local smooth, lerp = K.smooth, K.lerp
local num = R.num
local flex, plant, guardArm, kick = R.flex, R.plant, R.guardArm, R.kick
local noise = K.noise1

------------------------------------------------------------------------
-- Styles. Distances in studs, angles in radians. Glove targets (leadT / rearT) are in UpperTorso
-- space for a standard 2 x 1.6 x 1 torso (x right, y up, -z forward; the chin is about y 1.2).
--  depth = how low the hips sit, bounce = { height, Hz, heel lift }, shift = weight shift { size, Hz },
--  head = { noise size, Hz, weave (bob and weave), slip (side to side) }, hands = { lead paw, rear
--  circle, Hz }, feet = { restless steps per second, step size, pressure steps }, lean = torso pitch
------------------------------------------------------------------------
local STYLE = {
	BoxerPuncher = {
		depth = 0.28, stagger = 1.45, width = 0.1, yawL = -0.22, yawR = -0.78, heel = 0.14, hip = -0.3, wyaw = -0.08,
		lean = -0.05, tuck = -0.15, leadT = { -0.32, 0.92, -1.38 }, rearT = { 0.36, 1.02, -0.8 },
		bounce = { 0.04, 1.75, 0.08 }, shift = { 0.07, 0.32 }, head = { 0.05, 0.55, 0, 0.03 },
		hands = { 0.12, 0.05, 0.6 }, feet = { 0.9, 0.14, 0 }, roll = 0, fidget = { 4, 7 },
		likes = { tap = 1, roll = 1, feint = 2, pump = 1, neck = 1, adjust = 1 },
	},
	OutBoxer = {
		depth = 0.22, stagger = 1.6, width = 0.06, yawL = -0.15, yawR = -0.85, heel = 0.3, hip = -0.4, wyaw = -0.1,
		lean = -0.02, tuck = -0.1, leadT = { -0.44, 0.55, -1.48 }, rearT = { 0.38, 0.98, -0.8 },
		bounce = { 0.075, 2.25, 0.16 }, shift = { 0.05, 0.45 }, head = { 0.05, 0.8, 0, 0.05 },
		hands = { 0.3, 0.08, 0.9 }, feet = { 1.9, 0.2, 0 }, roll = 0, fidget = { 3, 6 },
		likes = { pump = 3, feint = 2, shake = 1, bounce2 = 2, tap = 1 },
	},
	Swarmer = {
		depth = 0.42, stagger = 1.2, width = 0.18, yawL = -0.3, yawR = -0.6, heel = 0.12, hip = -0.18, wyaw = -0.04,
		lean = -0.2, tuck = -0.3, leadT = { -0.27, 1.12, -0.98 }, rearT = { 0.29, 1.12, -0.86 },
		bounce = { 0.035, 1.6, 0.06 }, shift = { 0.06, 0.4 }, head = { 0.06, 0.7, 0.24, 0.04 },
		hands = { 0.06, 0.04, 0.8 }, feet = { 1.1, 0.16, 1 }, roll = 0, fidget = { 3, 6 },
		likes = { tap = 3, feint = 1, neck = 1, adjust = 1 },
	},
	Slugger = {
		depth = 0.32, stagger = 1.5, width = 0.2, yawL = -0.25, yawR = -0.8, heel = 0.03, hip = -0.3, wyaw = -0.06,
		lean = -0.06, tuck = -0.2, leadT = { -0.38, 0.82, -1.28 }, rearT = { 0.44, 0.9, -0.82 },
		bounce = { 0.012, 0.9, 0 }, shift = { 0.13, 0.17 }, head = { 0.04, 0.35, 0, 0.02 },
		hands = { 0.05, 0.06, 0.4 }, feet = { 0.35, 0.12, 0 }, roll = 0.5, fidget = { 4, 8 },
		likes = { roll = 3, tap = 2, neck = 2, breath = 2, adjust = 1 },
	},
	CounterPuncher = {
		depth = 0.26, stagger = 1.4, width = 0.08, yawL = -0.25, yawR = -0.8, heel = 0.12, hip = -0.46, wyaw = -0.12,
		lean = -0.03, tuck = -0.22, leadT = { -0.16, 0.12, -1.02 }, rearT = { 0.3, 1.02, -0.76 },
		bounce = { 0.025, 1.4, 0.05 }, shift = { 0.06, 0.28 }, head = { 0.05, 0.7, 0, 0.11 },
		hands = { 0.05, 0.05, 0.5 }, feet = { 0.6, 0.12, 0 }, roll = 1, fidget = { 4, 7 },
		likes = { roll = 2, feint = 2, neck = 1, adjust = 1 },
	},
}
AnimFight.STYLE = STYLE

-- per-boxer persona from the seed: two boxers of one style never move alike
function AnimFight.persona(seed)
	local function r(i, a, b)
		return a + (b - a) * K.rand3(seed, i, 7.7)
	end
	return {
		tempo = r(1, 0.88, 1.14), size = r(2, 0.82, 1.22), guardY = r(3, -0.07, 0.05), guardX = r(4, -0.05, 0.06),
		lean = r(5, -0.04, 0.05), stance = r(6, 0.92, 1.1), headBob = r(7, 0.6, 1.45), handLife = r(8, 0.6, 1.5),
		weight = r(9, -1, 1), feet = r(10, 0.7, 1.35), fidgetRate = r(11, 0.7, 1.4), chin = r(12, -0.05, 0.05),
		ns = (seed % 997) + 0.37, punchSnap = r(13, 0.9, 1.12), elbows = r(14, -0.05, 0.08),
	}
end

function AnimFight.setup(rig)
	rig.persona = AnimFight.persona(rig.seed)
	rig.bouncePhase = (rig.seed % 13) / 13
	rig.fidget = nil
	rig.nextFidget = 0
	rig.nextFeet = 0
	rig.feetSide = "L"
	rig.pun = { L = nil, R = nil } -- punch layer per hand
	rig.bodyCur = { hip = 0, sho = 0, lean = 0, roll = 0, fwd = 0, side = 0, dip = 0 }
	rig.punchCount = 0
	rig.shakeUntil = 0
	rig.shakeAmt = 0
	rig.pendStep = nil
end

------------------------------------------------------------------------
-- Fidgets: short overlays on the guard (glove tap, shoulder roll, neck roll, feint, lead-hand pump,
-- shake out, big breath, double bounce, glove adjust)
------------------------------------------------------------------------
local FIDGET_DUR = { tap = 0.55, roll = 0.85, neck = 1.1, feint = 0.42, pump = 0.6, shake = 0.9, breath = 1.3, bounce2 = 0.5, adjust = 0.75 }
local FIDGET_LIST = { "tap", "roll", "neck", "feint", "pump", "shake", "breath", "bounce2", "adjust" }

local function pickFidget(rig, st, t)
	local likes = st.likes
	local tired = 1 - clamp(num(rig.a.Stam, 1), 0, 1)
	local total = 0
	for _, n in ipairs(FIDGET_LIST) do
		local w = (likes[n] or 0.3) + (n == "shake" and tired * 3 or 0) + (n == "breath" and tired * 2 or 0)
		total += w
	end
	local x = rig.rng:NextNumber() * total
	for _, n in ipairs(FIDGET_LIST) do
		local w = (likes[n] or 0.3) + (n == "shake" and tired * 3 or 0) + (n == "breath" and tired * 2 or 0)
		x -= w
		if x <= 0 then
			return n
		end
	end
	return "tap"
end

------------------------------------------------------------------------
-- The stance: style x persona x physique x stamina x body damage, alive every frame
------------------------------------------------------------------------
-- gl / gr: the glove targets this frame (written into rig.guardL / guardR as 3-number arrays)
function AnimFight.stance(p, rig, t, dt)
	local a = rig.a
	local st = STYLE[a.Style] or STYLE.BoxerPuncher
	local P = rig.persona
	local amp = R.ampOf(rig) * P.size
	local stam = clamp(num(a.Stam, 1), 0, 1)
	local tired = 1 - stam
	local gut = clamp((0.6 - num(a.BodyHP, 1)) / 0.6, 0, 1)
	local lo = rig.loco
	local mv = lo.gaitW
	local ns = P.ns
	local tempo = P.tempo * (0.8 + 0.2 * stam)
	-- the bounce on the balls of the feet: slower, lower and flatter-footed when tired or heavy
	local bH, bF, bHeel = st.bounce[1], st.bounce[2], st.bounce[3]
	rig.bouncePhase += dt * bF * tempo
	local bp = rig.bouncePhase
	local bw = (0.35 + 0.65 * stam) * (1 - 0.6 * mv) * amp
	-- not a pure sine: quick push up, softer landing (a real bounce spends longer low)
	local b01 = 0.5 - 0.5 * cos(2 * PI * bp)
	local bounce = (b01 ^ 1.6) * bH * bw
	-- layered life: weight shift (front / back and side to side), sway, breathing
	local sh = st.shift[1] * amp
	local sf = st.shift[2] * tempo
	local wx = noise(t * sf, ns) * sh
	local wz = (noise(t * sf * 0.8 + 3.3, ns + 1) * 0.6 + P.weight * 0.25) * sh
	-- breathing: faster and deeper as the tank empties, the shoulders heave
	rig.breathPhase += dt * (0.27 + 0.6 * tired) * (P.tempo * 0.5 + 0.5)
	local br = K.breath(rig.breathPhase) * (0.016 + 0.055 * tired)
	rig.breath = max(rig.breath, tired)
	-- head movement: the counter puncher's constant small slips, the swarmer's bob and weave
	local hs = st.head
	local hn = hs[1] * P.headBob * amp
	local hx = noise(t * hs[2] * tempo + 11, ns + 2) * hn
	local hy = noise(t * hs[2] * tempo * 1.3 + 5, ns + 3) * hn * 0.6
	local slip = noise(t * 0.55 * tempo + 21, ns + 4) * hs[4] * amp
	local weave = hs[3] * amp * (0.5 + 0.5 * stam) * (1 - 0.5 * mv)
	local wvx, wvd = 0, 0
	if weave > 0 then
		local wp = t * 0.72 * tempo + ns
		wvx = weave * sin(wp * 2 * PI) * 0.9
		wvd = weave * 0.45 * (0.5 - 0.5 * cos(wp * 4 * PI))
	end
	-- the counter puncher's shoulder roll (Philly shell rhythm)
	local sroll = st.roll * 0.07 * sin(t * 1.3 * tempo + ns) * amp
	local depth = st.depth * P.stance + 0.08 * tired + 0.05 * gut
	-- hips: bladed, leaning into the direction of travel (AnimLoco adds momentum after the filters)
	local lv = lo.lv
	p.Root = CF(wx + wvx + slip * 0.6, -(depth + wvd) + bounce, wz)
		* A(st.lean * 0.3 + P.lean * 0.3 + lv.Z * 0.008, st.hip, -lv.X * 0.008 - (wx + wvx) * 0.35)
	p.W = A(st.lean + P.lean - 0.14 * gut + br - 0.02 * mv, st.wyaw + sroll * 0.5 + hx * 0.4, (wvx + slip) * 0.45 + sroll + hx * 0.3)
	p.Neck = A(st.tuck + P.chin - br * 0.5 + 0.08 * gut + hy, -(st.hip + st.wyaw) * 0.85 - hx * 0.6, -(wvx + slip) * 0.35 - sroll + hx * 0.4)
	-- gloves: the style's guard, the persona's habits, tired arms sink and drift forward, hands live
	local lt, rt = st.leadT, st.rearT
	local hl = st.hands
	local life = P.handLife * (0.6 + 0.4 * stam)
	local hf = hl[3] * tempo
	local sinkY, sinkZ = 0.45 * tired - br * 0.4, 0.2 * tired
	local gl, gr = rig.gl, rig.gr
	gl[1] = lt[1] + P.guardX * -1 + noise(t * hf + 31, ns + 5) * hl[2] * life
	gl[2] = lt[2] + P.guardY - sinkY + noise(t * hf * 1.2 + 37, ns + 6) * hl[2] * life + bounce * 0.6
	gl[3] = lt[3] + sinkZ + noise(t * hf * 0.9 + 41, ns + 7) * hl[2] * life * 0.6
	gr[1] = rt[1] + P.guardX + sroll * 0.5 + noise(t * hf * 1.1 + 43, ns + 8) * hl[2] * life * 0.7
	gr[2] = rt[2] + P.guardY - sinkY - 0.25 * gut + noise(t * hf * 0.95 + 47, ns + 9) * hl[2] * life * 0.7 + bounce * 0.5
	gr[3] = rt[3] + sinkZ + noise(t * hf + 53, ns + 10) * hl[2] * life * 0.4
	-- the out-boxer's pawing lead: measured little extensions ("range finding")
	if hl[1] > 0.08 and mv < 0.6 then
		local pw = noise(t * 0.9 * tempo + 61, ns + 11)
		local paw = max(0, pw - 0.25) / 0.75
		paw = paw * paw * hl[1] * life
		gl[3] -= paw * 1.2
		gl[2] += paw * 0.35
		gl[1] += paw * 0.15
	end
	-- fidgets
	AnimFight.fidgets(p, rig, st, t, gl, gr)
	rig.guardL, rig.guardR = gl, gr
	rig.guardSink = sinkY
	-- authored fallback (far rigs) then the IK guard (near rigs)
	p.LS = A(0.9 - 0.35 * tired + br * 0.4, 0, 0.2 + sroll)
	p.LE = A(1.75 - 0.25 * tired, 0, 0)
	p.RS = A(0.8 - 0.35 * tired + br * 0.4, 0, -0.3 + sroll * 0.5)
	p.RE = A(2.05 - 0.2 * tired, 0, 0)
	p.LW = A(0, 0.22, 0)
	p.RW = A(0, -0.22, 0)
	local eo = P.elbows
	guardArm(rig, p, "L", gl[1], gl[2], gl[3], 1, nil, 0.2 + eo)
	guardArm(rig, p, "R", gr[1], gr[2], gr[3], 1, nil, gut > 0 and lerp(0.2, 0.05, gut) or 0.2 + eo)
	-- feet: the stance, up on the balls with the bounce
	local up = b01 * bHeel * bw * 3
	plant(rig, st.stagger * P.stance, st.width, st.yawL, st.yawR, st.heel * 0.7 + up, st.heel * 1.4 + up)
	rig.stepDist = 0.3 -- boxers reset their feet constantly
	rig.liftK = 0.6 -- and keep them close to the canvas
	-- restless feet / pressure steps while standing (the gait takes over when moving)
	AnimFight.restlessFeet(rig, st, t, mv)
	-- legs shaking after a heavy shot
	if t < rig.shakeUntil then
		local k = (rig.shakeUntil - t) / 1.2
		local s = clamp(k, 0, 1) * rig.shakeAmt
		p.Root = CF(sin(t * 31) * 0.025 * s, -0.08 * s - abs(sin(t * 23)) * 0.04 * s, 0) * p.Root * A(0, 0, sin(t * 17) * 0.05 * s)
		rig.foot.L.knee += sin(t * 27) * 0.18 * s
		rig.foot.R.knee += sin(t * 29 + 1) * 0.18 * s
	end
	-- a fighter's muscles never fully switch off in the stance
	flex(rig, "forearms", 0.15)
	flex(rig, "frontDelt", 0.12)
	flex(rig, "abs", 0.12 + 0.3 * gut)
	flex(rig, "calves", 0.1 + up)
	if gut > 0.6 and not rig.exprHint then
		rig.exprHint = "pain"
	end
	L.gait(rig, "shuffle")
	return st
end

function AnimFight.fidgets(p, rig, st, t, gl, gr)
	local f = rig.fidget
	if not f then
		if t >= rig.nextFidget and rig.loco.gaitW < 0.3 and not rig.pun.L and not rig.pun.R then
			if rig.nextFidget > 0 then
				local kind = pickFidget(rig, st, t)
				rig.fidget = { kind = kind, start = t, dur = FIDGET_DUR[kind] or 0.6, side = rig.rng:NextNumber() < 0.5 and -1 or 1 }
			end
			local fr = st.fidget
			rig.nextFidget = t + rig.rng:NextNumber(fr[1], fr[2]) / rig.persona.fidgetRate
		end
		return
	end
	local el = t - f.start
	if el > f.dur or rig.pun.L or rig.pun.R then
		rig.fidget = nil
		return
	end
	local u = el / f.dur
	local e = K.bump(u, 0, 1)
	local kind = f.kind
	if kind == "tap" then
		-- gloves meet in front of the chest, a double tap
		local tap = e * (0.75 + 0.25 * abs(sin(u * PI * 4)))
		gl[1] = lerp(gl[1], -0.1, tap)
		gr[1] = lerp(gr[1], 0.1, tap)
		gl[3] = lerp(gl[3], -1.15, tap)
		gr[3] = lerp(gr[3], -1.15, tap)
		gl[2] = lerp(gl[2], 0.85, tap * 0.6)
		gr[2] = lerp(gr[2], 0.85, tap * 0.6)
	elseif kind == "roll" then
		-- one shoulder rolls up, back and down
		local s = f.side
		local c = u * 2 * PI
		p.W = p.W * A(-0.04 * sin(c) * e, 0, s * 0.1 * sin(c) * e)
		p.Neck = p.Neck * A(0, 0, -s * 0.06 * sin(c) * e)
		if s > 0 then
			gr[2] += 0.12 * sin(c) * e
		else
			gl[2] += 0.12 * sin(c) * e
		end
	elseif kind == "neck" then
		-- a neck roll: head tilts one way then the other
		local c = u * 2 * PI
		p.Neck = p.Neck * A(0.06 * sin(c * 0.5) * e, 0.05 * sin(c) * e, 0.22 * sin(c) * e * f.side)
	elseif kind == "feint" then
		-- half a jab with a shoulder dip, or a hip feint
		local k = K.attackDecay(el, 0.12, f.dur)
		if f.side > 0 then
			gl[3] -= 0.55 * k
			gl[2] += 0.1 * k
			p.W = p.W * A(-0.05 * k, -0.12 * k, 0.08 * k)
			p.Root = CF(0, -0.05 * k, -0.06 * k) * p.Root
		else
			p.Root = CF(-0.12 * k, -0.12 * k, -0.05 * k) * p.Root * A(0, 0.12 * k, 0)
			p.W = p.W * A(-0.06 * k, 0.1 * k, -0.08 * k)
		end
	elseif kind == "pump" then
		-- two quick pumps of the lead hand
		local k = max(0, sin(u * PI * 2)) * e
		gl[3] -= 0.45 * k
		gl[2] += 0.08 * k
	elseif kind == "shake" then
		-- shake out the arms: hands drop and shake, then back up
		local k = e
		gl[2] -= 0.55 * k
		gr[2] -= 0.55 * k
		gl[1] -= 0.25 * k
		gr[1] += 0.25 * k
		gl[3] += 0.3 * k
		gr[3] += 0.3 * k
		gl[2] += sin(el * 34) * 0.06 * k
		gr[2] += sin(el * 31 + 1) * 0.06 * k
		p.Neck = p.Neck * A(0, sin(el * 9) * 0.08 * k, 0)
	elseif kind == "breath" then
		-- a big breath: chest up, shoulders rise and fall
		local k = sin(u * PI)
		p.W = p.W * A(0.07 * k, 0, 0)
		p.Neck = p.Neck * A(0.06 * k, 0, 0)
		gl[2] += 0.1 * k
		gr[2] += 0.1 * k
	elseif kind == "bounce2" then
		-- a quick double hop
		local k = abs(sin(u * PI * 2)) * e
		p.Root = CF(0, 0.06 * k, 0) * p.Root
		rig.foot.L.heel += 0.25 * k
		rig.foot.R.heel += 0.25 * k
	elseif kind == "adjust" then
		-- push one glove onto the other (the lace / cuff)
		local s = f.side
		if s > 0 then
			gr[1] = lerp(gr[1], gl[1] + 0.1, e)
			gr[2] = lerp(gr[2], gl[2] - 0.05, e)
			gr[3] = lerp(gr[3], gl[3] + 0.15, e)
		else
			gl[1] = lerp(gl[1], gr[1] - 0.1, e)
			gl[2] = lerp(gl[2], gr[2] - 0.05, e)
			gl[3] = lerp(gl[3], gr[3] + 0.15, e)
		end
		p.Neck = p.Neck * A(-0.08 * e, 0, 0)
	end
end

-- constant small foot adjustments while standing: alternating feet, small offsets, held a moment
function AnimFight.restlessFeet(rig, st, t, mv)
	local rate = st.feet[1] * rig.persona.feet
	if rate <= 0 or mv > 0.25 or rig.pun.L or rig.pun.R then
		return
	end
	if t < rig.nextFeet then
		return
	end
	local s = rig.feetSide
	if not L.ready(rig, s, rig.clock) then
		rig.nextFeet = t + 0.05
		return
	end
	local size = st.feet[2]
	local r = rig.rng
	local ox = (r:NextNumber() - 0.5) * 2 * size * 0.8
	local oz = (r:NextNumber() - 0.5) * 2 * size
	if st.feet[3] > 0 and s == "L" and r:NextNumber() < 0.6 then
		-- pressure: inch the lead foot forward, the rear foot follows on the next beat
		oz = -size * (0.8 + r:NextNumber() * 0.6)
	end
	local hold = r:NextNumber(0.25, 0.7) / rate
	L.request(rig, s, ox, oz, 0.15, 0.08, hold, rig.clock)
	rig.feetSide = s == "L" and "R" or "L"
	rig.nextFeet = t + (r:NextNumber(0.6, 1.4) / rate)
end

------------------------------------------------------------------------
-- Daze 1: dazed (heavy legs, lagging guard, head shakes); 2: rubber legs (buckles with catch steps,
-- drift, arms half down); 3: out on his feet (drunken sway, arms dangling, stagger steps)
------------------------------------------------------------------------
function AnimFight.daze(p, rig, t, dt, daze, conc)
	if daze <= 0 and conc < 0.3 then
		return
	end
	local d = clamp(daze + conc * 0.6, 0, 3.5)
	local ns = rig.persona.ns
	local sw = noise(t * 0.8, ns + 40)
	local sz = noise(t * 0.6 + 9, ns + 41)
	p.Root = CF(0.1 * d * sw, -0.06 * d - 0.04 * d * abs(noise(t * 1.7, ns + 42)), 0.05 * d * sz) * p.Root
		* A(0.03 * d * sz, 0, 0.04 * d * sw)
	p.Neck = p.Neck * A(-0.06 * d, 0.05 * d * noise(t * 0.9, ns + 43), 0.08 * d * noise(t * 0.7 + 3, ns + 44))
	local drop = clamp((d - 0.5) * 0.25, 0, 0.9)
	if rig.gl then
		rig.gl[2] -= drop * 0.9
		rig.gr[2] -= drop * 0.9
		rig.gl[3] += drop * 0.4
		rig.gr[3] += drop * 0.4
		if rig.lod >= 2 then
			guardArm(rig, p, "L", rig.gl[1], rig.gl[2], rig.gl[3], 1, nil, 0.25)
			guardArm(rig, p, "R", rig.gr[1], rig.gr[2], rig.gr[3], 1, nil, 0.25)
		end
	end
	p.rate = 9 - 1.5 * min(daze, 3) -- the guard follows late
	-- head shake (trying to clear it) every few seconds
	if t >= (rig.nextShake or 0) then
		rig.nextShake = t + rig.rng:NextNumber(2.2, 4.2)
		rig.shakeT = t
	end
	local se = t - (rig.shakeT or -10)
	if se < 0.5 and daze <= 2 then
		p.Neck = p.Neck * A(0, 0.22 * sin(se * 30) * (1 - se / 0.5), 0)
	end
	-- rubber legs: knee buckles the springs carry, a catch step under the falling side
	if daze >= 2 and t >= (rig.nextBuckle or 0) then
		rig.nextBuckle = t + rig.rng:NextNumber(0.7, 1.6) / (daze - 1)
		local s = rig.rng:NextNumber() < 0.5 and -1 or 1
		kick(rig, -0.4, 0, 0.5 * s, -0.3, 0, 0.9 * s, 0, 0.6 * s, 1.0 + 0.4 * daze, 0, 0.4, 0.4, 0, 0)
		local side = s < 0 and "L" or "R"
		if L.ready(rig, side, t) then
			L.request(rig, side, s * (0.25 + 0.1 * daze), rig.rng:NextNumber(-0.25, 0.25), 0.2, 0.1, 0.6, t)
		end
	end
	if daze >= 3 then
		-- out on his feet: arms hang, the body sways from the ankles
		p.LS = p.LS:Lerp(A(0.25, 0, 0.12), 0.7)
		p.RS = p.RS:Lerp(A(0.2, 0, -0.12), 0.7)
		p.LE = p.LE:Lerp(A(0.6, 0, 0), 0.7)
		p.RE = p.RE:Lerp(A(0.5, 0, 0), 0.7)
		p.W = p.W * A(0.1 * noise(t * 0.8, ns + 45), 0, 0.12 * noise(t * 0.9 + 0.5, ns + 46))
	end
	rig.stepDist = 0.22
	rig.stepTime = 1 + 0.25 * daze
	if daze >= 2 then
		L.gait(rig, "stagger")
	end
end

------------------------------------------------------------------------
-- Punches
------------------------------------------------------------------------
-- body at contact (radians / studs, added to the stance): hip = pelvis turn (+ = rear side forward),
-- sho = shoulders past the hips, lean / roll = torso, fwd / side = weight transfer, dip = level change
-- (+ = down); load = anticipation length (share of the windup) with aHip / aSho / aDip / aLean the
-- counter-movement; tHip / tSho / tArm = when each link of the chain starts (share of the windup),
-- pow = how hard the fist accelerates; rec = recovery (x windup); pivot / heel / knee = feet; path =
-- the fist's shape; reach = share of the full extension; wrist = corkscrew; low = aim lower
local PUNCH = {
	jab = { hand = "L", path = "straight", hip = -0.07, sho = -0.24, fwd = 0.16, side = -0.03, dip = 0.03, lean = -0.05, roll = 0.07,
		load = 0.12, aHip = 0.02, aSho = 0.02, aDip = 0, aLean = 0, tHip = 0, tSho = 0.08, tArm = 0.14, pow = 1.5, rec = 0.92,
		heelL = 0.14, wrist = 1.25, rise = 0.05, reach = 1, nx = 0.06,
		variants = {
			{ w = 3, name = "snap" },
			{ w = 2, name = "step", fwd = 0.34, lean = -0.08, step = 0.42 },
			{ w = 1.4, name = "paw", reach = 0.82, sho = -0.12, hip = -0.03, rec = 0.72, pow = 1.25, low = 0.18 },
			{ w = 1.4, name = "long", lean = -0.13, fwd = 0.26, sho = -0.3, dip = 0.08, reach = 1.06 },
		} },
	cross = { hand = "R", path = "straight", hip = 0.44, sho = 0.34, fwd = 0.28, side = -0.07, dip = 0.06, lean = -0.08, roll = -0.09,
		load = 0.22, aHip = 0.07, aSho = 0.05, aDip = 0.03, aLean = 0.03, tHip = 0, tSho = 0.16, tArm = 0.26, pow = 1.75, rec = 1.0,
		pivot = "R", pivotAmt = 0.62, heelR = 0.55, kneeR = 0.25, wrist = 1.2, rise = 0.04, reach = 1, nx = -0.1,
		variants = {
			{ w = 3, name = "standard" },
			{ w = 1.6, name = "long", fwd = 0.4, lean = -0.14, dip = 0.1, reach = 1.06 },
			{ w = 1.4, name = "dip", dip = 0.22, roll = -0.16, lean = -0.12, nx = -0.2 },
			{ w = 1.0, name = "counter", aLean = 0.1, aDip = 0.0, load = 0.3, fwd = 0.22 },
		} },
	leadhook = { hand = "L", path = "hook", hip = -0.3, sho = -0.3, fwd = 0.05, side = 0.12, dip = 0.12, lean = -0.04, roll = 0.14,
		load = 0.25, aHip = 0.1, aSho = 0.06, aDip = 0.05, aLean = 0, tHip = 0, tSho = 0.12, tArm = 0.2, pow = 1.55, rec = 1.0,
		pivot = "L", pivotAmt = 0.7, heelL = 0.5, kneeL = 0.28, wrist = 0.15, arc = 0.6, reach = 0.92, nx = 0.08,
		variants = {
			{ w = 3, name = "tight", arc = 0.45 },
			{ w = 1.6, name = "wide", arc = 0.9, hip = -0.38, sho = -0.36, load = 0.3 },
			{ w = 1.0, name = "check", hip = -0.48, sho = -0.36, stepR = { 0.45, 0.3 } },
		} },
	rearhook = { hand = "R", path = "hook", hip = 0.46, sho = 0.4, fwd = 0.08, side = -0.12, dip = 0.12, lean = -0.04, roll = -0.14,
		load = 0.26, aHip = 0.1, aSho = 0.06, aDip = 0.05, aLean = 0, tHip = 0, tSho = 0.12, tArm = 0.22, pow = 1.55, rec = 1.0,
		pivot = "R", pivotAmt = 0.7, heelR = 0.55, kneeR = 0.28, wrist = -0.15, arc = 0.6, reach = 0.92, nx = -0.1,
		variants = {
			{ w = 3, name = "tight", arc = 0.45 },
			{ w = 1.6, name = "wide", arc = 0.95, hip = 0.54, sho = 0.46, load = 0.32 },
		} },
	uppercut = { hand = "R", path = "upper", hip = 0.3, sho = 0.18, fwd = 0.1, side = -0.04, dip = -0.1, lean = 0.06, roll = -0.06,
		load = 0.36, aHip = 0.08, aSho = 0.05, aDip = 0.28, aLean = -0.06, tHip = 0.1, tSho = 0.24, tArm = 0.3, pow = 1.7, rec = 1.0,
		pivot = "R", pivotAmt = 0.45, heelR = 0.45, kneeR = 0.22, rise = true, wrist = 0, reach = 0.9, nx = -0.05,
		variants = {
			{ w = 2, name = "short", aDip = 0.2, dip = -0.06 },
			{ w = 1.5, name = "dipping", aDip = 0.4, dip = -0.16, load = 0.42, aLean = -0.1 },
		} },
	overhand = { hand = "R", path = "over", hip = 0.44, sho = 0.38, fwd = 0.26, side = -0.16, dip = 0.16, lean = -0.18, roll = -0.22,
		load = 0.3, aHip = 0.08, aSho = 0.04, aDip = -0.04, aLean = 0.05, tHip = 0, tSho = 0.14, tArm = 0.22, pow = 1.6, rec = 1.05,
		pivot = "R", pivotAmt = 0.6, heelR = 0.6, kneeR = 0.3, wrist = 1.0, reach = 1, nx = -0.22,
		variants = {
			{ w = 2, name = "looping" },
			{ w = 1.2, name = "dipping", dip = 0.26, lean = -0.24, side = -0.22 },
		} },
}
PUNCH.hook = PUNCH.rearhook
AnimFight.PUNCH = PUNCH
local PUNCH_HAND = { jab = "L", cross = "R", leadhook = "L", rearhook = "R", hook = "R", uppercut = "R", overhand = "R" }
AnimFight.PUNCH_HAND = PUNCH_HAND

-- where the fist goes with nobody to aim at (standard torso units, x towards the centre line)
local PEAK = {
	straight = { x = 0.3, y = 1.0, z = -2.6, by = 0.15 },
	hook = { x = 0.1, y = 1.0, z = -1.0, by = 0.1 },
	upper = { x = 0.15, y = 1.1, z = -0.95, by = 0.35 },
	over = { x = 0.55, y = 1.15, z = -2.3, by = 0.3 },
}
local POLE = {
	straight = { 0.35, -1, 0.1 }, hook = { 1, 0.3, 0.25 }, upper = { 0.35, -1, 0.35 }, over = { 0.9, 0.35, 0.55 },
}
-- style preference among a punch's variants (multiplies the weights by name)
local STYLE_VARIANT = {
	OutBoxer = { step = 2.2, paw = 2.0, long = 1.5, standard = 1.0, tight = 1.3 },
	Swarmer = { snap = 1.4, tight = 2.0, check = 1.5, short = 2.0, dip = 1.6, dipping = 1.4 },
	Slugger = { wide = 2.2, standard = 1.2, looping = 1.6, dipping = 1.6, long = 1.2 },
	CounterPuncher = { counter = 2.4, check = 1.6, snap = 1.3, dip = 1.4 },
}

local function pickVariant(rig, def, kind, comboPos)
	local vs = def.variants
	if not vs then
		return nil
	end
	local pref = STYLE_VARIANT[rig.a.Style] or {}
	local ws = {}
	for i, v in ipairs(vs) do
		local w = v.w * (pref[v.name] or 1)
		-- the second jab of a double is the short, quick one
		if kind == "jab" and comboPos >= 2 and v.name == "paw" then
			w *= 2
		end
		ws[i] = w
	end
	local roll = K.rand3(rig.seed, rig.punchCount * 1.37 + comboPos, #kind)
	return vs[K.weighted(ws, roll)]
end

-- merged parameters for one punch (allocates once per punch, never per frame)
local function punchParams(rig, kind, comboPos)
	local def = PUNCH[kind] or PUNCH.cross
	local v = pickVariant(rig, def, kind, comboPos)
	local prm = table.clone(def)
	prm.variants = nil
	if v then
		for k, val in pairs(v) do
			if k ~= "w" then
				prm[k] = val
			end
		end
	end
	-- a little life in every repetition: never the same punch twice
	local j = K.rand3(rig.seed, rig.punchCount, 3.1)
	prm.hip *= 0.92 + 0.16 * j
	prm.fwd *= 0.9 + 0.2 * K.rand3(rig.seed, rig.punchCount, 4.2)
	prm.dip += (K.rand3(rig.seed, rig.punchCount, 5.3) - 0.5) * 0.04
	prm.vname = v and v.name or "base"
	return prm
end

-- a new punch: per-hand layer; the fist starts from wherever it is, the body from wherever it is
function AnimFight.startPunch(rig, act, t)
	local hand = act.hand
	rig.punchCount += 1
	local prev = rig.pun[hand]
	local comboPos = 1
	local now = t
	if rig.lastPunchT and now - rig.lastPunchT < 0.9 then
		comboPos = (rig.comboPos or 1) + 1
	end
	rig.comboPos = comboPos
	rig.lastPunchT = now
	local kind = act.kind
	if kind == "hook" then
		kind = hand == "L" and "leadhook" or "rearhook"
	end
	act.pkind = kind
	act.prm = punchParams(rig, kind, comboPos)
	if kind == "uppercut" then
		act.prm.mirror = hand == "L" and -1 or 1
	else
		act.prm.mirror = 1
	end
	act.from = prev and prev.lastPos or nil
	local bc = rig.bodyCur
	act.bodyFrom = { hip = bc.hip, sho = bc.sho, lean = bc.lean, roll = bc.roll, fwd = bc.fwd, side = bc.side, dip = bc.dip }
	rig.pun[hand] = act
	rig.bodyAct = act
	-- step jab / check hook: the feet move with the punch
	local prm = act.prm
	if prm.step and L.ready(rig, "L", t) then
		L.request(rig, "L", 0, -prm.step, act.windup * 0.75, 0.1, act.windup * 1.6, t)
	end
	if prm.stepR and L.ready(rig, "R", t) then
		L.request(rig, "R", prm.stepR[1], prm.stepR[2], act.windup * 0.9, 0.12, act.windup * 2.2, t)
	end
	local FaceFX = R.FX.FaceFX
	if FaceFX then
		FaceFX.Effort(rig.model, 0.35 + 0.3 * act.power, act.windup + 0.25)
	end
end

-- aim point in standard UpperTorso units, or nil (nobody in front / far rig)
local function aimPoint(rig, p, act, body, near)
	if not near then
		return nil
	end
	local tgt = body and rig.oppTorso or rig.oppHead
	local g = rig.geo
	if not (tgt and tgt.Parent and g.ok and g.utScale) then
		return nil
	end
	local ut = R.torsoCF(rig, p.Root, p.W)
	local sc = g.utScale
	local isBag = tgt == rig.bagPart
	local prm = act.prm
	local lp
	if isBag then
		-- a hanging bag: land on its near surface at the height this punch would find on a man
		local arm = g[R.ARM_OF[act.hand][3]]
		local shW = ut:PointToWorldSpace(arm and arm.c0.Position or V3())
		local pk = PEAK[prm.path]
		local hY = ut:PointToWorldSpace(V3(0, (body and pk.by or pk.y) * sc.Y, 0)).Y
		local c = tgt.Position
		local dx, dz = shW.X - c.X, shW.Z - c.Z
		local dm = sqrt(dx * dx + dz * dz)
		local r = min(tgt.Size.Y, tgt.Size.Z) * 0.5 + 0.4
		if dm > r then
			lp = ut:PointToObjectSpace(V3(c.X + dx / dm * r, hY, c.Z + dz / dm * r))
		end
	else
		-- the target's surface facing us (gloves touch, they do not sink into heads)
		local c = tgt.Position
		local toMe = ut.Position - c
		toMe = V3(toMe.X, 0, toMe.Z)
		local dist = toMe.Magnitude
		if dist < 0.1 then
			return nil
		end
		toMe /= dist
		local depth = body and tgt.Size.Z * 0.5 + 0.25 or tgt.Size.Z * 0.45 + 0.22
		local pt = c + toMe * depth
		if body then
			pt -= V3(0, tgt.Size.Y * 0.18, 0)
		end
		if prm.path == "hook" then
			-- hooks land on the side of the jaw / the flank: aim at the side the fist comes from
			local side = ut.RightVector * (act.hand == "L" and -1 or 1)
			pt += side * (body and 0.35 or 0.28) + toMe * 0.1
		elseif prm.path == "upper" then
			pt -= V3(0, body and 0.1 or 0.32, 0)
		end
		lp = ut:PointToObjectSpace(pt)
	end
	if not lp then
		return nil
	end
	lp = V3(lp.X / sc.X, lp.Y / sc.Y, lp.Z / sc.Z)
	if lp.Z > (isBag and 0.2 or -0.7) or lp.Magnitude > 6 then
		return nil
	end
	return lp, isBag
end

-- the fist's world-to-path shape: control points of the cubic from the start to the end point
local function pathPoints(path, P0, P3, inward, arc, rise)
	local d = P3 - P0
	if path == "hook" then
		local out = V3(-inward, 0, 0)
		return P0 + out * (0.55 * arc) + V3(0, 0.18, -0.15), P3 + out * (0.8 * arc) + V3(0, 0.05, 0.35)
	elseif path == "upper" then
		return P0 + V3(0, -0.5, -0.05) + d * 0.15, P3 + V3(0, -0.7, 0.2)
	elseif path == "over" then
		local out = V3(-inward, 0, 0)
		return P0 + V3(0, 0.6, 0) + out * 0.35 + d * 0.2, P3 + V3(0, 0.55, 0.25) + out * 0.1
	end
	local up = V3(0, rise or 0.05, 0)
	return P0 + d * 0.33 + up, P3 - d * 0.3 + up * 0.5
end

local function poleOf(path)
	return POLE[path] or POLE.straight
end

-- evaluate one punch layer; returns false when finished
local function evalPunch(p, rig, act, t, near, driveBody)
	local prm = act.prm
	local w = act.windup
	local el = t - act.start
	local hold = 0.045
	local rec = w * prm.rec
	if el >= w + hold + rec then
		return false
	end
	local L_ = act.hand == "L"
	local u = el / w
	local mirror = prm.mirror
	local anti, hipK, shoK, armK, retK = 0, 1, 1, 0, 0
	local contact = false
	if el < w then
		anti = K.bump(u, 0, prm.load * 2)
		hipK = smooth((u - prm.tHip) / (1 - prm.tHip))
		shoK = smooth((u - prm.tSho) / (1 - prm.tSho))
		armK = K.drive((u - prm.tArm) / (1 - prm.tArm), prm.pow)
	elseif el < w + hold then
		armK = 1
		contact = true
		if not act.impacted then
			act.impacted = true
			local BodyFX = R.FX.BodyFX
			if BodyFX then
				BodyFX.Jiggle(rig.model, "arms", 0.15 + 0.2 * act.power)
			end
			-- the snap: shoulders and head take a little of the impact back
			kick(rig, 0.4, 0, 0, 0.35 + 0.2 * act.power, 0, 0, 0.1, 0, 0, 0)
		end
	else
		local r = (el - w - hold) / rec
		retK = r
		armK = 1
		hipK = 1 - smooth((r - 0.12) / 0.88)
		shoK = 1 - smooth((r - 0.05) / 0.9)
	end
	local pw = (0.8 + 0.4 * clamp(act.power or 0.6, 0, 1.5)) * (0.85 + 0.15 * clamp(num(rig.a.Stam, 1), 0, 1))
	local body = act.zone == "body"
	-- body schedule (the newest punch drives it, continuing from where the last one left the body)
	if driveBody then
		local bf = act.bodyFrom
		-- during the drive each link travels from where the last punch left it to this punch's peak;
		-- in the recovery it unwinds to the stance (fh / fs = the share of the starting values left)
		local drv = el < w
		local fh, fs = drv and (1 - hipK) or 0, drv and (1 - shoK) or 0
		local dipExtra = body and (prm.path == "upper" and 0.2 or 0.42) or 0
		local leanExtra = body and -0.06 or 0
		local hip = prm.hip * mirror * pw * hipK + bf.hip * fh - prm.aHip * mirror * anti
		local sho = prm.sho * mirror * pw * shoK + bf.sho * fs - prm.aSho * mirror * anti
		local lean = (prm.lean + leanExtra) * pw * shoK + bf.lean * fs + prm.aLean * anti
		local roll = (prm.roll * mirror * pw + (body and prm.path == "hook" and (L_ and 0.12 or -0.12) or 0)) * shoK + bf.roll * fs
		local fwd = prm.fwd * pw * hipK + bf.fwd * fh
		local side = prm.side * mirror * pw * hipK + bf.side * fh
		local dip = (prm.dip + dipExtra) * pw * hipK + bf.dip * fh + prm.aDip * anti
		local bc = rig.bodyCur
		bc.hip, bc.sho, bc.lean, bc.roll, bc.fwd, bc.side, bc.dip = hip, sho, lean, roll, fwd, side, dip
		p.Root = CF(side, -dip, -fwd) * p.Root * A(0, hip, 0)
		p.W = p.W * A(lean, sho, roll)
		-- eyes stay on the target: the neck undoes most of the turn, chin behind the shoulder, the head
		-- slips off the centre line with the punch
		p.Neck = p.Neck * A(-0.08 * shoK, -(hip + sho) * 0.8, -roll * 0.55 + (prm.nx or 0) * shoK)
		-- feet: pivot on the ball, the heel lifts, the knee turns in with the hip
		local pv = prm.pivot
		if prm.path == "upper" then
			pv = L_ and "L" or "R"
		end
		if pv then
			local f = rig.foot[pv]
			local sgn = hip >= 0 and 1 or -1
			local k = max(hipK, 0)
			f.heel = max(f.heel, (pv == "L" and (prm.heelL or 0.4) or (prm.heelR or 0.4)) * k)
			f.pivot += sgn * (prm.pivotAmt or 0.5) * k
			f.knee += sgn * ((pv == "L" and prm.kneeL or prm.kneeR) or 0.2) * k
		end
		if prm.heelL and pv ~= "L" then
			rig.foot.L.heel = max(rig.foot.L.heel, prm.heelL * shoK)
		end
		if prm.rise then
			-- the uppercut's leg drive: both heels come up as the body rises
			local up = smooth((u - prm.load) / (1 - prm.load)) * (1 - smooth(retK / 0.6))
			rig.foot.L.heel = max(rig.foot.L.heel, 0.3 * up)
			rig.foot.R.heel = max(rig.foot.R.heel, 0.3 * up)
		end
	end
	-- the fist
	local S, E, Wr = L_ and "LS" or "RS", L_ and "LE" or "RE", L_ and "LW" or "RW"
	local guard = L_ and rig.guardL or rig.guardR
	local g = rig.geo
	local pathed = false
	local inward = L_ and 1 or -1
	if guard and g.ok and rig.lod >= 2 then
		local Pg = V3(guard[1], guard[2] - (rig.guardSink or 0) * 0.3, guard[3])
		local P0 = act.from or Pg
		local pk = PEAK[prm.path] or PEAK.straight
		local P3 = V3(inward * pk.x, (body and pk.by or pk.y) - (prm.low or 0), pk.z * (prm.reach or 1))
		local aimed, isBag = aimPoint(rig, p, act, body, near)
		if aimed then
			if isBag then
				P3 = aimed
			else
				P3 = P3:Lerp(aimed, prm.path == "straight" and 0.9 or 0.8)
			end
		end
		-- never further than the arm reaches from this shoulder (the elbow straightens at contact)
		local arm = g[R.ARM_OF[act.hand][3]]
		local sc = g.utScale
		if arm and arm.ok then
			local sh = V3(arm.c0.Position.X / sc.X, arm.c0.Position.Y / sc.Y, arm.c0.Position.Z / sc.Z)
			local v = P3 - sh
			local reach = arm.dMax / max(0.2, sc.Y) * 1.04 * (prm.reach or 1)
			if v.Magnitude > reach then
				P3 = sh + v.Unit * reach
			end
		end
		local pos
		local pole = poleOf(prm.path)
		local kp
		if retK > 0 then
			-- recovery: the fist comes home first, a little lower and inside, fast then easing
			local hit = act.hitPos or P3
			local k = K.easeOut(min(1, retK / 0.8))
			local c1 = hit + (Pg - hit) * 0.3 + V3(0, -0.12, 0.1)
			local c2 = Pg + V3(0, -0.05, -0.15)
			pos = K.bezier(hit, c1, c2, Pg, k)
			kp = 1 - k
		else
			local B1, B2 = pathPoints(prm.path, P0, P3, inward, prm.arc or 0.6, prm.rise)
			pos = K.bezier(P0, B1, B2, P3, armK)
			if contact then
				-- drives through a touch at contact
				local dir = (P3 - P0)
				if dir.Magnitude > 1e-3 then
					pos += dir.Unit * 0.06 * (1 - (el - w) / hold)
				end
			end
			act.hitPos = pos
			kp = smooth(clamp(armK / 0.85, 0, 1))
		end
		act.lastPos = pos
		-- the elbow rises into the punch (a hook's elbow comes up late) and settles back on the way home
		local zb = lerp(-0.1, pole[3], kp)
		local kb = act.from and 1 or smooth(clamp((armK + retK) * 3, 0, 1))
		if retK > 0 then
			kb = 1
		end
		pathed = guardArm(rig, p, act.hand, pos.X, pos.Y, pos.Z, kb, -zb, lerp(0.2, pole[1], kp), lerp(-1, pole[2], kp))
	end
	local ac = retK > 0 and (1 - smooth(retK / 0.8)) or armK
	if not pathed then
		-- far away / no guard to start from: authored joint angles
		local sp = prm.path == "over" and 2.1 or (prm.path == "upper" and 1.8 or (prm.path == "hook" and 1.42 or 1.6))
		local el2 = prm.path == "hook" and 1.6 or (prm.path == "upper" and 1.45 or 0.1)
		local sr = prm.path == "hook" and 0.85 or -0.1
		if body then
			sp -= 0.35
		end
		p[S] = p[S]:Lerp(A(sp, 0, L_ and -sr or sr), ac)
		p[E] = p[E]:Lerp(A(el2, 0, 0), ac)
	end
	p[Wr] = p[Wr] * A(0, inward * (prm.wrist or 0) * ac, 0)
	-- muscles: the punching side fires, the core turns, the pivot calf pushes
	local side = L_ and -1 or 1
	local imp = ac * ac
	local straight = prm.path == "straight"
	flex(rig, "frontDelt", imp, side)
	flex(rig, "sideDelt", imp * (straight and 0.5 or 0.9), side)
	flex(rig, "triceps", imp * (straight and 0.95 or 0.4), side)
	flex(rig, "biceps", imp * (straight and 0.2 or 0.75), side)
	flex(rig, "pecs", imp * 0.7, side)
	flex(rig, "upperChest", imp * 0.6, side)
	flex(rig, "lats", imp * 0.55, side)
	flex(rig, "forearms", imp * 0.85, side)
	flex(rig, "serratus", imp * 0.5, side)
	flex(rig, "obliques", hipK * 0.65)
	flex(rig, "abs", hipK * 0.4)
	flex(rig, "glutes", hipK * 0.35)
	flex(rig, "quads", hipK * 0.3)
	act.armT = ac
	return true
end

-- both punch layers + the guard hand tuck; returns true while any punch is running
function AnimFight.punches(p, rig, t, near)
	local any = false
	local newest = rig.bodyAct
	for _, h in ipairs(R.SIDES) do
		local act = rig.pun[h]
		if act then
			if evalPunch(p, rig, act, t, near, act == newest) then
				any = true
			else
				rig.pun[h] = nil
				if act == newest then
					rig.bodyAct = nil
					local bc = rig.bodyCur
					bc.hip, bc.sho, bc.lean, bc.roll, bc.fwd, bc.side, bc.dip = 0, 0, 0, 0, 0, 0, 0
				end
			end
		end
	end
	-- a punch whose body schedule ended early (a newer one replaced it) still needs the body to
	-- relax: the newest punch carries it; with no punch left the stance takes over (the filters blend)
	if any then
		-- the free hand covers the chin while the other one is out
		for _, h in ipairs(R.SIDES) do
			if not rig.pun[h] then
				local o = h == "L" and "R" or "L"
				local act = rig.pun[o]
				local k = act and (act.armT or 0) * 0.85 or 0
				if k > 0.02 then
					local sx = h == "R" and 1 or -1
					guardArm(rig, p, h, sx * 0.3, 1.04 - (rig.guardSink or 0) * 0.5, -0.74, k)
				end
			end
		end
	end
	return any
end

------------------------------------------------------------------------
-- Hit reactions: light (head snap), medium (+ a stumble step), heavy (legs shake, catch steps, the
-- guard knocked loose), critical (knees buckle, two catch steps); directional by punch and hand
------------------------------------------------------------------------
-- head-shot reaction impulses: head pitch / yaw / roll, torso pitch / yaw / roll, back, side, drop
-- (a lead hook lands on the defender's right: his head snaps to his left = + yaw)
local HIT = {
	jab = { 2.6, 0, 0, 0.8, 0, 0, 0.9, 0, 0 },
	cross = { 4.2, 0, 0.5, 1.3, 0, 0.2, 1.5, 0, 0.3 },
	leadhook = { 0.6, 6.4, 3.2, 0.3, 1.6, 1.0, 0.2, -1.0, 0.5 },
	rearhook = { 0.6, -6.6, -3.3, 0.3, -1.7, -1.0, 0.2, 1.0, 0.5 },
	uppercut = { 7.4, 0, 0.8, 2.0, 0, 0.3, 0.8, 0, -0.9 },
	overhand = { -3.0, -2.6, -3.6, -0.6, -0.8, -1.0, 0.5, 0.6, 1.3 },
}
HIT.hook = HIT.rearhook
-- which way the blow pushes the body (body space: x right, z back)
local PUSH = {
	jab = { 0, 1 }, cross = { -0.15, 1 }, leadhook = { -1, 0.25 }, rearhook = { 1, 0.25 }, hook = { 1, 0.25 },
	uppercut = { 0, 1 }, overhand = { 0.6, 0.6 },
}
-- which way the hair is flung (head space x right, z back) per punch
local HAIR_FLING = {
	jab = { 0, -1 }, cross = { 0.2, -1 }, leadhook = { 1, -0.2 }, rearhook = { -1, -0.2 }, hook = { -1, -0.2 },
	uppercut = { 0, -0.6 }, overhand = { -0.7, 0.4 },
}

-- catch step: the foot on the side the body is pushed to steps that way (a push back moves the rear
-- foot back first)
local function catchStep(rig, px, pz, size, t, hold)
	local s
	if abs(px) > abs(pz) * 0.8 then
		s = px < 0 and "L" or "R"
	else
		s = pz > 0 and "R" or "L"
	end
	if not L.ready(rig, s, t) then
		s = s == "L" and "R" or "L"
		if not L.ready(rig, s, t) then
			return
		end
	end
	L.request(rig, s, px * size, pz * size, 0.15 + 0.05 * size, 0.1 + 0.05 * size, hold or 0.5, t)
	return s
end

function AnimFight.react(rig, kind, ptype, flag, sev, t)
	local model = rig.model
	local daze = num(rig.a.Daze, 0)
	sev = clamp(sev or 0.5, 0, 1.5)
	rig.hitT = t
	rig.hitSev = sev
	local FX = R.FX
	-- severity tier: heavy / counter shots count a tier up
	local tier = sev < 0.35 and 1 or (sev < 0.75 and 2 or (sev < 1.1 and 3 or 4))
	if (flag == "heavy" or flag == "counter") and tier < 4 then
		tier += 1
	end
	tier = min(4, tier + (daze >= 2 and 1 or 0))
	rig.hitTier = tier
	if kind == "hit" then
		local h = HIT[ptype] or HIT.cross
		local m = (0.45 + sev) * (flag == "counter" and 1.35 or (flag == "heavy" and 1.25 or 1)) * (1 + 0.2 * daze)
		local rs = rig.rng:NextNumber() < 0.5 and -1 or 1 -- straight shots tilt the head either way
		local roll = h[3] * ((ptype == "cross" or ptype == "uppercut" or ptype == "jab") and rs or 1)
		-- light shots snap the head; the body joins in from medium up
		local bodyM = tier == 1 and 0.4 or 1
		kick(rig, h[1] * m, h[2] * m, roll * m, h[4] * m * bodyM, h[5] * m * bodyM, h[6] * m * rs * bodyM, h[7] * m * bodyM, h[8] * m * bodyM, h[9] * m * bodyM, 0,
			tier >= 3 and 1.6 * m or 0, tier >= 3 and 1.6 * m or 0, tier >= 3 and 1.2 * m or 0, tier >= 3 and 1.2 * m or 0)
		local push = PUSH[ptype] or PUSH.cross
		if tier >= 2 then
			catchStep(rig, push[1], push[2], 0.2 + 0.25 * sev, t, 0.4 + 0.3 * sev)
		end
		if tier >= 3 then
			rig.shakeUntil = t + 0.8 + 0.6 * sev
			rig.shakeAmt = clamp(0.6 + 0.4 * sev, 0, 1.2)
			-- a second catch step with the other foot (the legs scramble for balance)
			rig.pendStep = { at = t + 0.16, px = push[1] * 0.7, pz = push[2] * 0.7, size = 0.2 + 0.2 * sev }
		end
		if tier >= 4 then
			kick(rig, 0, 0, 0, -0.6, 0, 0, 0, 0, 1.4, 0, 1, 1, 0.6, 0.6)
		end
		if FX.FaceFX then
			FX.FaceFX.Hit(model, sev)
		end
		if FX.HairFX then
			local f = HAIR_FLING[ptype] or HAIR_FLING.cross
			FX.HairFX.Impulse(model, f[1], f[2], 0.5 + sev * 0.6)
		end
		if FX.BodyFX then
			FX.BodyFX.Jiggle(model, "chest", 0.2 + 0.3 * sev)
		end
	elseif kind == "hitbody" then
		-- body shots fold him: hunch, knees buckle, crunch towards the side that was hit; a hook to
		-- the right side is a liver shot (bigger, slower to recover, a delayed sag)
		local side = flag == "L" and -1 or 1
		local liver = side == 1 and (ptype == "leadhook" or ptype == "hook" or ptype == "uppercut")
		local m = (0.45 + sev) * (liver and 1.45 or 1) * (1 + 0.15 * daze)
		kick(rig, -1.2 * m, 0.4 * side * m, 0, -3.2 * m, 0.5 * side * m, -2.0 * side * m, 0.5 * m, 0.3 * side * m, 1.7 * m, 0,
			side < 0 and 0.6 * m or 0, side > 0 and 0.6 * m or 0, 0, 0)
		if tier >= 2 then
			catchStep(rig, 0.3 * side, 0.8, 0.15 + 0.2 * sev, t, 0.5)
		end
		if liver then
			rig.liverT = t
			rig.liverSev = sev
		end
		if FX.FaceFX then
			FX.FaceFX.Hit(model, sev * 0.8 + (liver and 0.3 or 0))
		end
		if FX.BodyFX then
			FX.BodyFX.Jiggle(model, "core", 0.5 * m)
		end
		if FX.HairFX then
			FX.HairFX.Impulse(model, 0, -0.6, 0.3 + sev * 0.3)
		end
	elseif kind == "blockhit" then
		kick(rig, 0.8, 0, 0, 0.6, 0, 0, 1.5, 0, 0.2, 5)
		if FX.FaceFX then
			FX.FaceFX.Effort(model, 0.5, 0.3)
		end
		if FX.BodyFX then
			FX.BodyFX.Jiggle(model, "arms", 0.3)
		end
	end
end

-- per-frame reaction follow-ups: the second catch step, the liver sag
function AnimFight.reactionTick(p, rig, t)
	local ps = rig.pendStep
	if ps and t >= ps.at then
		rig.pendStep = nil
		catchStep(rig, ps.px, ps.pz, ps.size, t, 0.6)
	end
	local lt = rig.liverT
	if lt then
		local el = t - lt
		if el > 1.6 then
			rig.liverT = nil
		elseif el > 0.25 then
			-- the delayed reaction: the body sags over the liver, the elbow clamps down
			local k = K.attackDecay(el - 0.25, 0.25, 1.35) * clamp(rig.liverSev or 0.6, 0.3, 1.2)
			p.Root = CF(0.05 * k, -0.22 * k, 0.05 * k) * p.Root
			p.W = p.W * A(-0.3 * k, 0.1 * k, -0.18 * k)
			p.Neck = p.Neck * A(0.15 * k, 0, 0)
			if rig.gr then
				guardArm(rig, p, "R", 0.45, 0.25, -0.45, k)
			end
			rig.exprHint = "pain"
		end
	end
end

------------------------------------------------------------------------
-- Other acts: hit / defence / stumble / referee (punches run in their own layers)
------------------------------------------------------------------------
function AnimFight.applyAct(p, rig, act, t)
	local el = t - act.start
	local k = act.kind
	if el >= act.dur then
		return false
	end
	local pulse = K.pulse(el, act.dur) or 0
	if k == "hit" or k == "hitbody" then
		-- the guard is knocked loose for a moment (the springs carry head and torso)
		local s = pulse * clamp(act.sev or 0.5, 0, 1.2)
		if rig.gl then
			rig.gl[2] -= 0.35 * s
			rig.gr[2] -= 0.35 * s
		end
		p.LS = p.LS * A(-0.35 * s, 0, -0.1 * s)
		p.RS = p.RS * A(-0.35 * s, 0, 0.1 * s)
		p.LE = p.LE * A(-0.3 * s, 0, 0)
		p.RE = p.RE * A(-0.3 * s, 0, 0)
		if k == "hitbody" then
			-- the elbow on the hit side clamps down over the ribs
			local Lh = act.f3 == "L"
			local S = Lh and "LS" or "RS"
			p[S] = p[S]:Lerp(A(0.55, 0, Lh and 0.35 or -0.35), pulse * 0.6)
			flex(rig, "abs", pulse)
			flex(rig, "obliques", pulse)
		end
		rig.exprHint = "pain"
	elseif k == "blockhit" then
		flex(rig, "forearms", pulse)
		flex(rig, "frontDelt", pulse * 0.6)
	elseif k == "slip" then
		local Ls = act.f2 == "L"
		local x = el / act.dur
		-- quick out, slower back: the head goes offline over the slip-side knee, the feet stay put
		local s = x < 0.4 and smooth(x / 0.4) or 1 - smooth((x - 0.4) / 0.6)
		local sd = Ls and -1 or 1
		p.Root = CF(sd * 0.34 * s, -0.22 * s, -0.04 * s) * p.Root * A(0, sd * -0.1 * s, sd * -0.06 * s)
		p.W = p.W * A(-0.1 * s, sd * -0.12 * s, sd * -0.42 * s)
		p.Neck = p.Neck * A(0, sd * 0.1 * s, sd * -0.12 * s)
		rig.foot[Ls and "L" or "R"].knee += sd * 0.15 * s
		flex(rig, "obliques", s * 0.8)
	elseif k == "roll" then
		local x = el / act.dur
		local s = sin(PI * x)
		-- U under the punch: dip, shift across, come up on the other side (knees, not the waist)
		local dir = act.f2 == "L" and -1 or 1
		p.Root = CF(-cos(PI * x) * 0.4 * s * dir, -0.58 * s, -0.04 * s) * p.Root * A(0, 0, cos(PI * x) * 0.1 * s * dir)
		p.W = p.W * A(-0.28 * s, 0, cos(PI * x) * 0.42 * s * dir)
		p.Neck = p.Neck * A(-0.12 * s, 0, -cos(PI * x) * 0.15 * s * dir)
		flex(rig, "quads", s * 0.7)
		flex(rig, "obliques", s * 0.7)
	elseif k == "parry" then
		-- the rear hand slaps the incoming jab across (a short, sharp catch)
		local Ls = act.f2 == "L"
		local s = K.attackDecay(el, act.dur * 0.3, act.dur)
		if rig.lod >= 2 and rig.gl then
			local g = Ls and rig.gl or rig.gr
			local sx = Ls and -1 or 1
			guardArm(rig, p, Ls and "L" or "R", lerp(g[1], sx * -0.15, s), lerp(g[2], 0.95, s), lerp(g[3], -1.35, s), 1, nil, 0.3)
		else
			local S, E = Ls and "LS" or "RS", Ls and "LE" or "RE"
			p[S] = p[S]:Lerp(A(1.5, 0, Ls and -0.55 or 0.55), pulse)
			p[E] = p[E]:Lerp(A(1.5, 0, 0), pulse)
		end
		p.W = p.W * A(0, (Ls and -0.12 or 0.12) * s, 0)
		flex(rig, "forearms", pulse, Ls and -1 or 1)
	elseif k == "parryhit" then
		-- the parried man's lead arm is knocked aside, the shoulder turns with it
		p.LS = p.LS:Lerp(A(1.45, 0, -0.7), pulse)
		p.W = p.W * A(0, -0.25 * pulse, 0)
	elseif k == "pivot" then
		local Ls = act.f2 == "L"
		p.W = p.W * A(0, (Ls and 0.35 or -0.35) * pulse, 0)
		p.Root = p.Root * A(0, (Ls and 0.2 or -0.2) * pulse, 0)
		-- turning on the lead foot: it spins on its ball, the rear foot swings round (AnimLoco steps it)
		local f = rig.foot.L
		f.heel = max(f.heel, 0.4 * pulse)
		rig.stepDist = 0.2
	elseif k == "step" then
		-- trainee footwork (the root is anchored): lead foot steps, rear follows, hips ride over
		local dir = act.f2
		local fwd = dir == "F" and 1 or (dir == "B" and -1 or 0)
		local side = dir == "R" and 1 or (dir == "L" and -1 or 0)
		if not act.stepped then
			act.stepped = true
			local leadS = (dir == "R" or dir == "B") and "R" or "L"
			local trailS = leadS == "L" and "R" or "L"
			L.request(rig, leadS, side * 0.4, -fwd * 0.45, 0.14, 0.12, 0.3, t)
			act.trail = trailS
		elseif not act.stepped2 and el > act.dur * 0.35 then
			act.stepped2 = true
			L.request(rig, act.trail, side * 0.25, -fwd * 0.28, 0.13, 0.08, 0.2, t)
		end
		p.Root = CF(side * 0.28 * pulse, 0.03 * pulse, -fwd * 0.28 * pulse) * p.Root
		flex(rig, "calves", pulse)
	elseif k == "jump" then
		rig.foot.L.free, rig.foot.R.free = true, true
		rig.foot.L.lift, rig.foot.R.lift = 0.5 * pulse, 0.5 * pulse
		p.Root = CF(0, 0.5 * pulse, 0) * p.Root
		flex(rig, "calves", pulse)
		flex(rig, "quads", pulse * 0.6)
	elseif k == "stumble" then
		-- thrown off balance: torso lags, arms fling out, short choppy recovery steps (the root moves:
		-- AnimLoco's stagger gait does the feet)
		local dir = act.f2
		local s = K.attackDecay(el, 0.08, act.dur) * clamp(act.sev or 0.6, 0.2, 1.3)
		local wob = sin(el * 9) * 0.06 * s
		if dir == "B" then
			p.Root = p.Root * A(0.22 * s, 0, wob)
			p.W = p.W * A(0.15 * s, 0, 0)
			p.LS = p.LS:Lerp(A(1.0, 0, -1.0), s)
			p.RS = p.RS:Lerp(A(1.0, 0, 1.0), s)
		else
			local sd = dir == "R" and 1 or -1
			p.Root = p.Root * A(wob, 0, -0.25 * s * sd)
			p.W = p.W * A(0, 0, -0.12 * s * sd)
			p[sd > 0 and "LS" or "RS"] = p[sd > 0 and "LS" or "RS"]:Lerp(A(1.4, 0, sd > 0 and -1.2 or 1.2), s)
		end
		p.LE = p.LE:Lerp(A(0.5, 0, 0), s)
		p.RE = p.RE:Lerp(A(0.5, 0, 0), s)
		p.Root = CF(0, -0.15 * s, 0) * p.Root
		rig.stepDist = 0.18
		rig.stepTime = 1.35
		rig.liftK = 0.5
		L.gait(rig, "stagger")
		rig.exprHint = "pain"
	elseif k == "refcount" then
		-- arm up, then chops down for the number, bent over the downed fighter
		local x = el / act.dur
		local up = x < 0.35 and smooth(x / 0.35) or 1 - smooth((x - 0.35) / 0.25)
		p.RS = A(lerp(1.15, 2.5, up), 0, 0.35 * up)
		p.RE = A(0.25, 0, 0)
		p.W = p.W * A(-0.28, 0, 0)
		p.Root = CF(0, -0.3, 0) * p.Root
		p.LS = A(0.55, 0, 0.3)
		p.LE = A(0.7, 0, 0)
		p.Neck = p.Neck * A(-0.2, 0, 0)
	elseif k == "waveoff" then
		-- it's over: arms crossing back and forth overhead
		local x = sin(el * 7.5)
		local e = min(1, el / 0.2) * (1 - smooth((el - act.dur + 0.3) / 0.3))
		p.LS = p.LS:Lerp(A(2.6, 0, -0.55 + 0.75 * x), e)
		p.RS = p.RS:Lerp(A(2.6, 0, 0.55 - 0.75 * x), e)
		p.LE = p.LE:Lerp(A(0.2, 0, 0), e)
		p.RE = p.RE:Lerp(A(0.2, 0, 0), e)
	elseif k == "catch" then
		-- the referee wraps his arms round a man out on his feet and holds him up
		local e = smooth(el / 0.35) * (1 - smooth((el - act.dur + 0.4) / 0.4))
		p.Root = CF(0, -0.22 * e, -0.25 * e) * p.Root
		p.W = p.W * A(-0.22 * e, 0, 0)
		p.LS = p.LS:Lerp(A(1.35, 0, -0.15), e)
		p.RS = p.RS:Lerp(A(1.35, 0, 0.15), e)
		p.LE = p.LE:Lerp(A(1.7, 0, 0), e)
		p.RE = p.RE:Lerp(A(1.7, 0, 0), e)
		p.Neck = p.Neck * A(0.1 * e, 0.4 * e, 0)
	end
	return true
end

------------------------------------------------------------------------
-- The fight pose for a Guard value (stance-like guards; "down" is AnimDown's)
------------------------------------------------------------------------
local function findStool(rig)
	local t = rig.clock
	if rig.stoolCheck and t - rig.stoolCheck < 1 then
		return rig.stool
	end
	rig.stoolCheck = t
	rig.stool = nil
	local arena = rig.model.Parent
	if rig.oppHead and rig.oppHead.Parent and rig.oppHead.Parent.Parent then
		local op = rig.oppHead.Parent.Parent
		if op ~= workspace then
			arena = op
		end
	end
	if not arena or arena == workspace then
		return nil
	end
	local best, bd = nil, 4
	for _, m in ipairs(arena:GetChildren()) do
		if m.Name == "CornerStool" and m:IsA("Model") then
			local seat = m:FindFirstChild("Seat")
			if seat and seat:IsA("BasePart") then
				local d = (seat.Position - rig.root.Position) * V3(1, 0, 1)
				if d.Magnitude < bd then
					best, bd = seat, d.Magnitude
				end
			end
		end
	end
	rig.stool = best
	return best
end

function AnimFight.guardPose(p, rig, t, dt)
	local a = rig.a
	local guard = a.Guard or "stance"
	local daze = num(a.Daze, 0)
	local conc = num(a.Conc, 0)
	local el = t - rig.guardT
	rig.poseAct = "Sparring"
	if guard == "block" then
		AnimFight.stance(p, rig, t, dt)
		-- the shell: forearms over the face, chin down, knees bent, elbows tight
		p.Root = CF(0, -0.18, 0.05) * p.Root
		p.LS = A(1.85, 0, 0.5)
		p.LE = A(2.4, 0, 0)
		p.RS = A(1.85, 0, -0.5)
		p.RE = A(2.4, 0, 0)
		guardArm(rig, p, "L", -0.32, 1.32, -0.72, 1, 0.6)
		guardArm(rig, p, "R", 0.32, 1.32, -0.72, 1, 0.6)
		p.W = p.W * A(-0.12, 0, 0)
		p.Neck = p.Neck * A(-0.15, 0, 0)
		flex(rig, "forearms", 0.6)
		flex(rig, "abs", 0.5)
		flex(rig, "frontDelt", 0.4)
	elseif guard == "clinch" then
		AnimFight.stance(p, rig, t, dt)
		-- tie him up: arms over his, weight leaning on him, head on his shoulder, pummel jitter
		local j = noise(t * 3, rig.persona.ns + 70) * 0.1
		p.Root = CF(0, -0.15, -0.38) * p.Root * A(-0.12, 0, 0)
		p.W = A(-0.32, 0.12, 0.05 + j * 0.3)
		p.Neck = A(-0.2, 0.45, 0.15)
		p.LS = A(1.45 + j, 0, 0.35)
		p.LE = A(1.1, 0, 0)
		p.RS = A(1.45 - j, 0, -0.35)
		p.RE = A(1.0, 0, 0)
		flex(rig, "lats", 0.7)
		flex(rig, "biceps", 0.6)
		flex(rig, "forearms", 0.8)
		flex(rig, "neckSCM", 0.6)
		rig.exprHint = "effort"
	elseif guard == "hurt" then
		AnimFight.stance(p, rig, t, dt)
		-- covering up and sagging: knees dip, guard closes, head down
		local w = noise(t * 2, rig.persona.ns + 80)
		p.Root = CF(0.06 * w, -0.12 - 0.06 * abs(noise(t * 1.6, rig.persona.ns + 81)), 0.1) * p.Root
		p.LS = p.LS:Lerp(A(1.5, 0, 0.45), 0.6)
		p.LE = p.LE:Lerp(A(2.3, 0, 0), 0.6)
		p.RS = p.RS:Lerp(A(1.5, 0, -0.45), 0.6)
		p.RE = p.RE:Lerp(A(2.3, 0, 0), 0.6)
		guardArm(rig, p, "L", -0.3, 1.12, -0.78, 0.8, 0.4)
		guardArm(rig, p, "R", 0.3, 1.12, -0.78, 0.8, 0.4)
		p.Neck = p.Neck * A(-0.12, 0, 0.1 * noise(t * 2.2, rig.persona.ns + 82))
		AnimFight.daze(p, rig, t, dt, max(daze, 1), conc)
	elseif guard == "walkout" then
		if rig.loco.gaitW > 0.2 or rig.loco.speed > 1.2 then
			return "walk"
		end
		-- waiting in the corner / at the steps: warm-up bounce, shoulder rolls, neck rolls
		AnimFight.stance(p, rig, t, dt)
		p.Root = CF(0, 0.05 * abs(sin(t * 4.2)), 0) * p.Root
		local sr = sin(t * 2.2)
		p.LS = A(0.55 + 0.25 * sr, 0, 0.2)
		p.RS = A(0.55 - 0.25 * sr, 0, -0.2)
		p.LE = A(1.6, 0, 0)
		p.RE = A(1.6, 0, 0)
		p.Neck = A(-0.05 + 0.15 * sin(t * 1.3), 0.35 * sin(t * 0.7), 0.2 * cos(t * 1.3))
	elseif guard == "rest" then
		-- between rounds: on the stool when the corner has put it there, else leaning on the ropes;
		-- arms along the ropes, chest heaving, head back
		local stam = clamp(num(a.Stam, 1), 0, 1)
		rig.breathPhase += dt * (0.3 + 0.4 * (1 - stam))
		local br = K.breath(rig.breathPhase) * (0.04 + 0.05 * (1 - stam))
		rig.breath = 1 - stam
		local seat = findStool(rig)
		local g = rig.geo
		local sat = false
		if seat and g.ok then
			local lp = rig.root.CFrame:PointToObjectSpace(seat.Position + V3(0, seat.Size.Y * 0.5, 0))
			-- sitting = the hips just above the seat top, the pelvis pulled back over it
			local hipAbove = (g.rootY - g.L.hip0.Y) -- root joint above the hip joints
			local wantY = lp.Y + 0.35 + hipAbove - g.rootY
			if lp.Z > -0.5 and lp.Z < 3.2 and abs(lp.X) < 2.5 and wantY < 0.2 and wantY > -2.5 then
				sat = true
				p.Root = CF(lp.X * 0.9, wantY, lp.Z * 0.9) * A(0.12 + br * 0.3, 0, 0)
				p.W = A(0.1 + br, 0, 0)
				p.Neck = A(0.2 - br, 0.1 * sin(t * 0.3), 0)
				p.LS = A(0.35 + br, 0, -1.25)
				p.LE = A(0.4, 0, 0)
				p.RS = A(0.35 + br, 0, 1.25)
				p.RE = A(0.4, 0, 0)
				-- feet flat in front, knees apart
				plant(rig, 0.1, 0.35, 0.3, -0.3, 0, 0)
				local fz = lp.Z * 0.9 - 0.3
				rig.foot.L.z = fz - 0.2
				rig.foot.R.z = fz - 0.1
				rig.stepDist = 0.5
			end
		end
		if not sat then
			p.Root = CF(0, -0.12, 0.12) * A(0.1, 0, 0)
			p.W = A(0.08 + br, 0, 0)
			p.Neck = A(0.22 - br, 0.1 * sin(t * 0.3), 0)
			p.LS = A(0.3 + br, 0, -1.35)
			p.LE = A(0.35, 0, 0)
			p.RS = A(0.3 + br, 0, 1.35)
			p.RE = A(0.35, 0, 0)
			plant(rig, 0.1, 0.25, 0.25, -0.25, 0, 0)
		end
	elseif guard == "win" then
		-- arms up, a little hop, then a flex for the crowd
		local cyc = (el % 6)
		R.plant(rig, 0.2, 0.12, 0.2, -0.2, 0, 0)
		if cyc < 3.6 then
			local pump = abs(sin(t * 3.2))
			p.Root = CF(0, -0.08 + 0.1 * pump, 0)
			p.LS = A(2.9 - 0.2 * pump, 0, -0.3)
			p.RS = A(2.9 - 0.2 * pump, 0, 0.3)
			p.LE = A(0.25 + 0.3 * pump, 0, 0)
			p.RE = A(0.25 + 0.3 * pump, 0, 0)
			p.Neck = A(0.3, 0.3 * sin(t * 0.8), 0)
			p.W = A(0.12, 0, 0)
			rig.foot.L.heel, rig.foot.R.heel = 0.2 * pump, 0.2 * pump
		else
			p.LS = A(0, 0, -1.5) * A(0, 1.3, 0)
			p.RS = A(0, 0, 1.5) * A(0, -1.3, 0)
			p.LE = A(2.2, 0, 0)
			p.RE = A(2.2, 0, 0)
			p.Neck = A(0.15, 0, 0)
			flex(rig, "biceps", 1)
			flex(rig, "frontDelt", 0.6)
			flex(rig, "sideDelt", 0.8)
			flex(rig, "lats", 0.6)
		end
		rig.exprHint = "happy"
	elseif guard == "lose" then
		-- head down, hands on the hips, slow heavy breaths
		rig.breathPhase += dt * 0.35
		local br = K.breath(rig.breathPhase) * 0.05
		R.plant(rig, 0.15, 0.1, 0.15, -0.2, 0, 0)
		p.Root = CF(0, -0.05, 0)
		p.Neck = A(-0.5 - br * 0.5, 0.15 * sin(t * 0.25), 0)
		p.W = A(-0.1 + br, 0, 0)
		p.LS = A(-0.25, 0, -0.55) * A(0, -0.9, 0)
		p.RS = A(-0.25, 0, 0.55) * A(0, 0.9, 0)
		p.LE = A(1.6, 0, 0)
		p.RE = A(1.6, 0, 0)
	else
		AnimFight.stance(p, rig, t, dt)
		if guard == "dazed" or daze > 0 or conc >= 0.3 then
			AnimFight.daze(p, rig, t, dt, max(daze, guard == "dazed" and 1 or 0), conc)
		end
	end
	return guard
end

return AnimFight
