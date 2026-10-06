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
local wander = K.wander

------------------------------------------------------------------------
-- Styles. Distances in studs, angles in radians. Glove targets (leadT / rearT) are in UpperTorso
-- space for a standard 2 x 1.6 x 1 torso (x right, y up, -z forward; the chin is about y 1.2).
--  depth = how low the hips sit, wk = feet apart sideways as a share of the shoulders' width,
--  bounce = { height, Hz, heel lift }, shift = weight shift { size, Hz }, head = { noise size, Hz,
--  weave (bob and weave), slip (side to side) }, hands = { lead paw, rear circle, Hz }, feet =
--  { restless steps per second, step size, pressure steps }, lean = torso pitch, roll = shoulder roll,
--  micro = the counter puncher's little slips and rolls { every (s), size }, raise = lead shoulder up
-- Silhouettes: the boxer-puncher's classic high guard; the out-boxer upright with the lead hand low
-- and long; the swarmer's peek-a-boo (gloves at the forehead, elbows on the ribs, deep crouch); the
-- slugger wide and heavy, rear hand cocked high by the ear; the counter puncher's shoulder-roll shell
-- (lead arm across the belly, lead shoulder up, rear glove on the chin)
------------------------------------------------------------------------
local STYLE = {
	BoxerPuncher = {
		depth = 0.3, stagger = 1.45, wk = 0.82, yawL = -0.22, yawR = -0.78, heel = 0.14, hip = -0.3, wyaw = -0.08,
		lean = -0.05, tuck = -0.15, leadT = { -0.42, 0.95, -1.12 }, rearT = { 0.38, 1.05, -0.68 },
		bounce = { 0.075, 1.75, 0.1 }, shift = { 0.1, 0.34 }, head = { 0.08, 0.55, 0, 0.05 },
		hands = { 0.12, 0.05, 0.6 }, feet = { 0.9, 0.14, 0 }, roll = 0, fidget = { 4, 7 },
		likes = { tap = 1, roll = 1, feint = 2, pump = 1, neck = 1, adjust = 1 },
	},
	OutBoxer = {
		depth = 0.2, stagger = 1.6, wk = 0.8, yawL = -0.15, yawR = -0.85, heel = 0.14, hip = -0.4, wyaw = -0.1,
		lean = 0.0, tuck = -0.08, leadT = { -0.5, 0.18, -1.5 }, rearT = { 0.36, 1.0, -0.72 },
		bounce = { 0.1, 2.25, 0.08 }, shift = { 0.05, 0.45 }, head = { 0.05, 0.8, 0, 0.05 },
		hands = { 0.3, 0.08, 0.9 }, feet = { 1.9, 0.2, 0 }, roll = 0, fidget = { 3, 6 },
		likes = { pump = 3, feint = 2, shake = 1, bounce2 = 2, tap = 1 },
	},
	Swarmer = {
		depth = 0.5, stagger = 1.25, wk = 0.9, yawL = -0.3, yawR = -0.6, heel = 0.12, hip = -0.18, wyaw = -0.04,
		lean = -0.24, tuck = -0.32, leadT = { -0.25, 1.32, -0.94 }, rearT = { 0.27, 1.3, -0.88 },
		bounce = { 0.035, 1.6, 0.06 }, shift = { 0.06, 0.4 }, head = { 0.07, 0.7, 0.26, 0.05 },
		hands = { 0.06, 0.04, 0.8 }, feet = { 1.1, 0.16, 1 }, roll = 0, fidget = { 3, 6 }, elbows = -0.12,
		likes = { tap = 3, feint = 1, neck = 1, adjust = 1 },
	},
	Slugger = {
		depth = 0.45, stagger = 1.5, wk = 0.92, yawL = -0.25, yawR = -0.8, heel = 0.05, hip = -0.3, wyaw = -0.06,
		lean = -0.08, tuck = -0.2, leadT = { -0.44, 0.92, -1.08 }, rearT = { 0.5, 1.25, -0.5 },
		bounce = { 0.075, 1.35, 0.05 }, shift = { 0.21, 0.42 }, head = { 0.12, 0.7, 0, 0.06 },
		hands = { 0.05, 0.07, 0.45 }, feet = { 0.45, 0.14, 0 }, roll = 0.7, fidget = { 3, 6 },
		likes = { roll = 3, tap = 2, neck = 2, breath = 2, adjust = 1 },
	},
	CounterPuncher = {
		depth = 0.28, stagger = 1.4, wk = 0.8, yawL = -0.25, yawR = -0.8, heel = 0.12, hip = -0.5, wyaw = -0.14,
		lean = -0.03, tuck = -0.24, leadT = { -0.05, 0.12, -0.88 }, rearT = { 0.32, 1.15, -0.62 },
		bounce = { 0.045, 1.4, 0.06 }, shift = { 0.07, 0.3 }, head = { 0.09, 0.85, 0, 0.09 },
		hands = { 0.05, 0.05, 0.5 }, feet = { 0.6, 0.12, 0 }, roll = 1, fidget = { 4, 7 },
		micro = { 0.5, 1.1, 0.2 }, raise = 0.12,
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
-- In close the guards touch, they never sink into each other (the gloves are big: 1.4-1.7 studs). A
-- guard glove that would go into the other man's guard glove gives way - under and beside it, the way
-- a crowded lead hand drops to hand-fight, never back into its own face - by up to GLOVE_GIVE studs;
-- each man takes his share (smoothed: no tug of war). A punching glove is left alone (a punch hits the
-- guard), and so is a hand that is punching.
------------------------------------------------------------------------
local GLOVE_GIVE = 0.55
local function gloveRadius(part)
	local s = part.Size
	return (s.X + s.Y + s.Z) / 6
end
local function gloveRoom(rig, p, gl, gr, dt)
	local room = rig.gloveRoom
	if not room then
		room = { L = Vector3.zero, R = Vector3.zero }
		rig.gloveRoom = room
	end
	local opp = rig.oppRig
	local ok = opp ~= nil and opp.model ~= nil and opp.model.Parent ~= nil and rig.lod >= 3 and rig.geo.ok
	local gc = rig.gloveCache
	if ok and (not gc or gc.opp ~= opp.model or (not (gc.L and gc.oL) and os.clock() > gc.retry)) then
		local m, om = rig.model, opp.model
		gc = {
			opp = om,
			retry = os.clock() + 2,
			L = m:FindFirstChild("GloveL", true),
			R = m:FindFirstChild("GloveR", true),
			hL = m:FindFirstChild("LeftHand"),
			hR = m:FindFirstChild("RightHand"),
			oL = om:FindFirstChild("GloveL", true),
			oR = om:FindFirstChild("GloveR", true),
		}
		rig.gloveCache = gc
	end
	local k = 1 - exp(-dt * 12)
	local sc = rig.geo.utScale
	local tcf
	for _, s in ipairs(R.SIDES) do
		local g = s == "L" and gl or gr
		local want = Vector3.zero
		local mine, hand = gc and gc[s], gc and gc["h" .. s]
		if ok and mine and mine.Parent and hand and not rig.pun[s] then
			local drop = rig.loco and rig.loco.drop or 0
			tcf = tcf or R.torsoCF(rig, CF(0, -drop, 0) * p.Root, p.W)
			-- (where this glove will be: the target plus the glove's offset from the hand)
			local c = tcf * V3(g[1] * sc.X, g[2] * sc.Y, g[3] * sc.Z) + (mine.Position - hand.Position)
			local rm = gloveRadius(mine)
			local over = 0
			local away = Vector3.zero
			local dy = 0
			for _, os in ipairs(R.SIDES) do
				local theirs = gc["o" .. os]
				if theirs and theirs.Parent and not (opp.pun and opp.pun[os]) then
					local d = c - theirs.Position
					local o = rm + gloveRadius(theirs) - d.Magnitude
					if o > over and d.Magnitude > 1e-3 then
						over = o
						away = tcf:VectorToObjectSpace(d.Unit)
						dy = d.Y
					end
				end
			end
			if over > 0 then
				-- (they slide off each other, away from his glove - but never towards its own head: that
				-- part of the way is taken out, so a glove pushed straight back slides off to the side or
				-- under instead)
				local head = gc.head
				if not head or not head.Parent then
					head = rig.model:FindFirstChild("Head")
					gc.head = head
				end
				if head then
					local gp = V3(g[1] * sc.X, g[2] * sc.Y, g[3] * sc.Z)
					local toHead = tcf:PointToObjectSpace(head.Position) - gp
					if toHead.Magnitude > 1e-3 then
						toHead = toHead.Unit
						local inward = away:Dot(toHead)
						if inward > 0 then
							away -= toHead * inward
						end
					end
				end
				-- (and the lower glove goes under, the higher one over - two gloves meeting level go by
				-- the seeds, the same on every client - so the two men never both drop the same way)
				local under = dy < -0.15 or (dy <= 0.15 and rig.seed < (opp.seed or 0))
				away += V3(0, under and -0.8 or 0.45, 0)
				if away.Magnitude < 0.2 then
					away = V3(0, under and -1 or 1, 0)
				end
				want = away.Unit * min(over, GLOVE_GIVE)
			end
		end
		local cur = room[s]:Lerp(want, k)
		room[s] = cur
		g[1] += cur.X / sc.X
		g[2] += cur.Y / sc.Y
		g[3] += cur.Z / sc.Z
	end
end

------------------------------------------------------------------------
-- The stance: style x persona x physique x stamina x body damage, alive every frame
------------------------------------------------------------------------
-- gl / gr: the glove targets this frame (written into rig.guardL / guardR as 3-number arrays)
function AnimFight.stance(p, rig, t, dt)
	local a = rig.a
	local st = STYLE[a.Style] or STYLE.BoxerPuncher
	local P = rig.persona
	-- (heavy men move slower and a little smaller, never still: the stance's life has a floor)
	local amp = max(0.78, R.ampOf(rig) * P.size)
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
	local wx = wander(t, sf, ns) * sh
	local wz = (wander(t, sf * 0.8, ns + 1) * 0.6 + P.weight * 0.25) * sh
	-- breathing: faster and deeper as the tank empties, the shoulders heave
	rig.breathPhase += dt * (0.27 + 0.6 * tired) * (P.tempo * 0.5 + 0.5)
	local br = K.breath(rig.breathPhase) * (0.016 + 0.055 * tired)
	rig.breath = max(rig.breath, tired)
	-- head movement: the counter puncher's constant small slips, the swarmer's bob and weave
	local hs = st.head
	local hn = hs[1] * P.headBob * amp
	local hx = wander(t, hs[2] * tempo, ns + 2) * hn
	local hy = wander(t, hs[2] * tempo * 1.3, ns + 3) * hn * 0.6
	local slip = wander(t, 0.55 * tempo, ns + 4) * hs[4] * amp
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
	p.W = A(st.lean + P.lean - 0.14 * gut + br - 0.02 * mv, st.wyaw + sroll * 0.5 + hx * 0.4, (wvx + slip) * 0.45 + sroll + hx * 0.3 - (st.raise or 0))
	p.Neck = A(st.tuck + P.chin - br * 0.5 + 0.08 * gut + hy, -(st.hip + st.wyaw) * 0.85 - hx * 0.6, -(wvx + slip) * 0.35 - sroll + hx * 0.4 + (st.raise or 0) * 0.8)
	-- the counter puncher's head never stops: small discrete slips and dips every second or so
	AnimFight.microSlips(p, rig, st, t, mv)
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
	gloveRoom(rig, p, gl, gr, dt)
	rig.guardL, rig.guardR = gl, gr
	rig.guardSink = sinkY
	-- authored fallback (far rigs) then the IK guard (near rigs)
	p.LS = A(0.9 - 0.35 * tired + br * 0.4, 0, 0.2 + sroll)
	p.LE = A(1.75 - 0.25 * tired, 0, 0)
	p.RS = A(0.8 - 0.35 * tired + br * 0.4, 0, -0.3 + sroll * 0.5)
	p.RE = A(2.05 - 0.2 * tired, 0, 0)
	p.LW = A(0, 0.22, 0)
	p.RW = A(0, -0.22, 0)
	local eo = P.elbows + (st.elbows or 0)
	-- (the punches start from and come home to this elbow line: rig.guardPole)
	local gpL, gpR = 0.2 + eo, gut > 0 and lerp(0.2, 0.05, gut) or 0.2 + eo
	rig.guardPoleL, rig.guardPoleR = gpL, gpR
	guardArm(rig, p, "L", gl[1], gl[2], gl[3], 1, nil, gpL)
	guardArm(rig, p, "R", gr[1], gr[2], gr[3], 1, nil, gpR)
	-- feet: the stance (about shoulder-wide: a share of this torso's width), up on the balls with the bounce
	local up = b01 * bHeel * bw * 3
	local g = rig.geo
	local width = g.ok and max(0.05, (st.wk * g.utSize.X - g.hipW) * 0.5) or 0.3
	-- (light on the balls of the feet, not on tiptoe: the rear heel a touch higher; AnimRig.plant caps both)
	plant(rig, st.stagger * P.stance, width, st.yawL, st.yawR, st.heel * 0.7 + up, st.heel * 1.1 + up)
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

-- discrete little slips / dips (Style.micro = { min gap, max gap, size }): out fast, back slower
function AnimFight.microSlips(p, rig, st, t, mv)
	local mc = st.micro
	if not mc then
		return
	end
	local r = rig.rng
	if t >= (rig.nextMicro or 0) then
		rig.nextMicro = t + r:NextNumber(mc[1], mc[2]) / rig.persona.fidgetRate
		if mv < 0.5 and not rig.pun.L and not rig.pun.R then
			rig.micro = { t0 = t, dir = r:NextNumber() < 0.5 and -1 or 1, size = mc[3] * (0.75 + 0.5 * r:NextNumber()), dip = r:NextNumber() < 0.3 }
		end
	end
	local m = rig.micro
	if not m then
		return
	end
	local el = t - m.t0
	if el > 0.34 then
		rig.micro = nil
		return
	end
	local k = el < 0.12 and smooth(el / 0.12) or 1 - smooth((el - 0.12) / 0.22)
	-- the head goes off the line over a knee (hips shift, the torso bends to the side); a dip goes under
	p.Root = CF(m.dir * m.size * 0.55 * k, -(m.dip and 0.14 or 0.04) * k, 0) * p.Root
	p.W = p.W * A(-0.04 * k, 0, -m.dir * 0.2 * k)
	p.Neck = p.Neck * A(0, 0, m.dir * 0.07 * k)
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
	jab = { hand = "L", path = "straight", hip = -0.08, sho = -0.28, fwd = 0.2, side = -0.03, dip = 0.03, lean = -0.05, roll = 0.07,
		load = 0.12, aHip = 0.02, aSho = 0.02, aDip = 0, aLean = 0, tHip = 0, tSho = 0.08, tArm = 0.2, pow = 1.9, rec = 0.92,
		heelL = 0.14, wrist = 1.25, rise = 0.05, reach = 1, nx = 0.06,
		variants = {
			{ w = 3, name = "snap" },
			{ w = 2, name = "step", fwd = 0.34, lean = -0.08, step = 0.42 },
			{ w = 1.4, name = "paw", reach = 0.82, sho = -0.12, hip = -0.03, rec = 0.72, pow = 1.25, low = 0.18 },
			{ w = 1.4, name = "long", lean = -0.13, fwd = 0.26, sho = -0.3, dip = 0.08, reach = 1.06 },
		} },
	cross = { hand = "R", path = "straight", hip = 0.52, sho = 0.42, fwd = 0.36, side = -0.08, dip = 0.07, lean = -0.12, roll = -0.1,
		load = 0.22, aHip = 0.07, aSho = 0.05, aDip = 0.03, aLean = 0.03, tHip = 0, tSho = 0.16, tArm = 0.3, pow = 2.1, rec = 1.0,
		pivot = "R", pivotAmt = 0.62, heelR = 0.55, kneeR = 0.25, wrist = 1.2, rise = 0.04, reach = 1, nx = -0.1,
		variants = {
			{ w = 3, name = "standard" },
			{ w = 1.6, name = "long", fwd = 0.4, lean = -0.14, dip = 0.1, reach = 1.06 },
			-- (the level change comes in the load: down under the jab, then the legs drive up into the
			-- cross - from a deep crouch a cross still dipping at contact would reach up over his own head)
			{ w = 1.4, name = "dip", aDip = 0.2, dip = 0.08, roll = -0.16, lean = -0.12, nx = -0.2 },
			{ w = 1.0, name = "counter", aLean = 0.1, aDip = 0.0, load = 0.3, fwd = 0.22 },
		} },
	-- hooks: the whole body turns (hips, then shoulders past them) on the pivoting lead / rear foot, the
	-- weight goes onto that leg; the arm comes late and fast
	leadhook = { hand = "L", path = "hook", hip = -0.6, sho = -0.45, fwd = 0.08, side = 0.16, dip = 0.12, lean = -0.04, roll = 0.16,
		load = 0.3, aHip = 0.3, aSho = 0.22, aDip = 0.06, aLean = 0, tHip = 0.12, tSho = 0.2, tArm = 0.38, pow = 2.6, rec = 1.0,
		elbowT = 0.05, pivot = "L", pivotAmt = 1.0, heelL = 0.6, kneeL = 0.35, wrist = 0.15, arc = 0.6, reach = 0.97, nx = 0.08,
		variants = {
			{ w = 3, name = "tight", arc = 0.45 },
			{ w = 1.6, name = "wide", arc = 0.9, hip = -0.68, sho = -0.5, load = 0.3 },
			{ w = 1.0, name = "check", hip = -0.62, sho = -0.42, aHip = 0.18, aSho = 0.12, stepR = { 0.45, 0.3 } },
		} },
	rearhook = { hand = "R", path = "hook", hip = 0.66, sho = 0.5, fwd = 0.12, side = -0.16, dip = 0.12, lean = -0.04, roll = -0.16,
		load = 0.26, aHip = 0.16, aSho = 0.1, aDip = 0.05, aLean = 0, tHip = 0.06, tSho = 0.16, tArm = 0.4, pow = 2.3, rec = 1.0,
		elbowT = 0.05, pivot = "R", pivotAmt = 1.05, heelR = 0.65, kneeR = 0.35, wrist = -0.15, arc = 0.6, reach = 0.97, nx = -0.1,
		variants = {
			{ w = 3, name = "tight", arc = 0.45 },
			{ w = 1.6, name = "wide", arc = 0.95, hip = 0.74, sho = 0.56, load = 0.32 },
		} },
	-- the uppercut: a real dip (the knees load), then the legs drive the hips up into the punch onto the
	-- ball of the rear foot
	uppercut = { hand = "R", path = "upper", hip = 0.32, sho = 0.2, fwd = 0.1, side = -0.04, dip = -0.12, lean = 0.06, roll = -0.06,
		load = 0.36, aHip = 0.08, aSho = 0.05, aDip = 0.75, aLean = -0.06, tHip = 0.1, tSho = 0.24, tArm = 0.4, pow = 2.4, rec = 1.0,
		pivot = "R", pivotAmt = 0.45, heelR = 0.6, kneeR = 0.22, rise = true, wrist = 0, reach = 0.94, nx = -0.05,
		variants = {
			{ w = 2, name = "short", aDip = 0.62, dip = -0.1 },
			{ w = 1.5, name = "dipping", aDip = 0.82, dip = -0.14, load = 0.42, aLean = -0.1 },
		} },
	-- the overhand: down and off the line in the load (under the jab), then the rear shoulder rolls up
	-- and over and the fist comes down on top, the weight going down and forward through it
	overhand = { hand = "R", path = "over", hip = 0.5, sho = 0.44, fwd = 0.34, side = -0.34, dip = 0.12, lean = -0.14, roll = -0.24,
		load = 0.3, aHip = 0.08, aSho = 0.04, aDip = 0.2, aLean = 0.05, tHip = 0, tSho = 0.14, tArm = 0.38, pow = 2.4, rec = 1.05,
		pivot = "R", pivotAmt = 0.6, heelR = 0.6, kneeR = 0.3, wrist = 1.0, reach = 1, nx = -0.34,
		variants = {
			{ w = 2, name = "looping" },
			{ w = 1.2, name = "dipping", aDip = 0.3, dip = 0.16, lean = -0.16, side = -0.38 },
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
-- (a straight's elbow turns out as the arm locks - the corkscrew - so the last of the bend lies flat and
-- the forearm runs level along the punch's line instead of tipping up from a dropped elbow; a hook's elbow
-- comes up level with the fist, the upper arm out to the side)
local POLE = {
	straight = { 0.9, -0.45, 0.1 }, hook = { 0.85, 0.6, 0.2 }, upper = { 0.35, -1, 0.35 }, over = { 1, 0.08, 0.1 },
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

-- the UpperTorso frame a punch aims in: this frame's pose plus the pelvis drop the feet added (last
-- frame): a rise or a lunge the planted legs cannot follow is taken back by AnimLoco, and the fist must
-- still find the target from where the shoulders really are
local function punchTorso(rig, p)
	local lo = rig.loco
	local d = lo and lo.drop or 0
	if d > 1e-3 then
		return R.torsoCF(rig, CF(0, -d, 0) * p.Root, p.W)
	end
	return R.torsoCF(rig, p.Root, p.W)
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
	local ut = punchTorso(rig, p)
	local sc = g.utScale
	local isBag = tgt == rig.bagPart
	-- the spot is chosen once, on the punch's first frame, and kept in the target's own space: it
	-- follows the target if it moves but never jumps while the body turns under the punch
	if act.aimTgt ~= tgt then
		act.aimTgt = tgt
		act.aimLocal = nil
		local prm = act.prm
		local pt
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
				pt = V3(c.X + dx / dm * r, hY, c.Z + dz / dm * r)
			end
		else
			-- the target's surface facing us (gloves touch, they do not sink into heads)
			local c = tgt.Position
			local toMe = ut.Position - c
			toMe = V3(toMe.X, 0, toMe.Z)
			local dist = toMe.Magnitude
			if dist >= 0.1 then
				toMe /= dist
				local depth = body and tgt.Size.Z * 0.5 + 0.25 or tgt.Size.Z * 0.45 + 0.22
				if body then
					pt = c + toMe * depth - V3(0, tgt.Size.Y * 0.18, 0)
				else
					-- (straight punches go for the chin, not the middle of the face: the fist meets the jaw at
					-- the puncher's own shoulder height, the arm level)
					pt = c + toMe * depth - V3(0, tgt.Size.Y * (prm.path == "straight" and 0.3 or 0), 0)
				end
				if prm.path == "hook" then
					-- hooks land on the side of the jaw / the flank (the side the fist comes from), not in
					-- front of the face: the glove arrives across, just outside the side of the head
					local side = ut.RightVector * (act.hand == "L" and -1 or 1)
					side = V3(side.X, 0, side.Z).Unit
					if body then
						pt = c + toMe * (tgt.Size.Z * 0.5 + 0.12) + side * (tgt.Size.X * 0.32 + 0.2) - V3(0, tgt.Size.Y * 0.2, 0)
					else
						-- (the fist's centre beside the jaw: the glove meets the side of the face from outside)
						pt = c + toMe * (tgt.Size.Z * 0.25) + side * (tgt.Size.X * 0.6 + 0.35) - V3(0, tgt.Size.Y * 0.15, 0)
					end
				elseif prm.path == "upper" then
					pt -= V3(0, body and 0.1 or 0.32, 0)
				end
			end
		end
		if pt then
			local lp = ut:PointToObjectSpace(pt)
			lp = V3(lp.X / sc.X, lp.Y / sc.Y, lp.Z / sc.Z)
			-- only something in front of us, within a few arm lengths
			if lp.Z <= (isBag and 0.2 or -0.7) and lp.Magnitude <= 6 then
				act.aimLocal = tgt.CFrame:PointToObjectSpace(pt)
			end
		end
	end
	if not act.aimLocal then
		return nil
	end
	-- (from contact on the spot stays where the glove met it: the struck head snaps away and the fist
	-- does not chase it)
	local w = act.aimW
	if not w then
		w = tgt.CFrame:PointToWorldSpace(act.aimLocal)
		if act.impacted then
			act.aimW = w
		end
	end
	local lp = ut:PointToObjectSpace(w)
	lp = V3(lp.X / sc.X, lp.Y / sc.Y, lp.Z / sc.Z)
	if lp.Magnitude > 8 then
		return nil
	end
	return lp, isBag
end

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

-- a hook's fist path, laid out in the root's frame so the body's turn does not drag it round with the
-- chest: from the guard out and up to the chamber - level with the target, HOOK_SWING further round the
-- body than it - while the hips turn, then round the spine in a flat arc into the side of the target
-- (angle and radius together: a hook swings, it does not push forward), arriving across (inward) and
-- fastest at contact; `through` drives it a touch on through the target at contact. Takes and returns
-- UpperTorso standard units.
local HOOK_SWING = 0.9
local HOOK_KEEP = 0.5
local function hookPos(rig, p, act, P0, P3, u, eT, armK, inward, body, sc, through)
	local toR = rig.root.CFrame:Inverse() * punchTorso(rig, p)
	if not act.h0 then
		act.h0 = toR * V3(P0.X * sc.X, P0.Y * sc.Y, P0.Z * sc.Z)
		act.hs0 = toR.Position
	end
	local p3 = toR * V3(P3.X * sc.X, P3.Y * sc.Y, P3.Z * sc.Z)
	-- (where the fist starts from travels with the body - the hips' step and lunge, the dip - though not
	-- with the chest's turn: a hook thrown with a long step in is not left behind at the shoulder, folding
	-- the arm up against it before it can chamber)
	local h0 = act.h0 + (toR.Position - act.hs0)
	-- (the spine: the arc's centre travels with the body's step and lunge)
	local px, pz = toR.Position.X, toR.Position.Z
	-- (a lead hand held across the belly - the shoulder-roll shell - comes up into its chamber over a
	-- longer time: a check hook off the hip; a high guard's glove near the centre line - the peek-a-boo -
	-- is not "across": it chambers at the normal pace)
	local across = clamp(h0.X * inward / 0.3, 0, 1) * clamp((0.9 - P0.Y) / 0.4, 0, 1)
	local ck = smooth(clamp(u / (0.66 + 0.2 * across), 0, 1))
	local dx, dz = p3.X - px, p3.Z - pz
	local r3, a3 = sqrt(dx * dx + dz * dz), math.atan2(dx, -dz)
	-- (round a spine close to the target - a crouching swarmer - the angle opens up: the fist still
	-- sweeps about the same distance across)
	-- (a hand coming up from across the belly is still chambering as the sweep begins: it swings out
	-- further round to still come in from the side)
	local sw = (clamp(1.4 / max(0.5, r3), HOOK_SWING, 1.1) + 0.15 * across) * (body and 0.75 or 1)
	local ac = a3 - inward * sw
	local rc = max(0.6, r3 - 0.15)
	local c = h0:Lerp(V3(px + sin(ac) * rc, h0.Y + (p3.Y - h0.Y) * (body and 0.5 or 0.85) + (body and -0.05 or 0.05), pz - cos(ac) * rc), ck)
	-- the sweep from wherever the fist is (never the long way round)
	local cx, cz = c.X - px, c.Z - pz
	local r0, a0 = sqrt(cx * cx + cz * cz), math.atan2(cx, -cz)
	local da = (a3 - a0 + PI) % (2 * PI) - PI
	local an, r = a0 + da * armK, r0 + (r3 - r0) * armK
	local pr = V3(px + sin(an) * r, c.Y + (p3.Y - c.Y) * armK, pz - cos(an) * r)
	if through > 0 then
		pr += V3(inward * 0.075, 0, -0.03) * through
	end
	-- (and on its way never close by its own shoulder: a hand coming across from the far side of the belly
	-- would pass in front of the joint, whipping the arm round it faster than it turns - it goes round it
	-- instead; the landing spot itself is left where it is)
	local arm = rig.geo[R.ARM_OF[act.hand][3]]
	if arm and arm.ok and armK < 1 then
		local sh = toR * arm.c0.Position
		local v = pr - sh
		local keep = arm.dMax * HOOK_KEEP * (1 - smooth(armK))
		if v.Magnitude < keep then
			pr = sh + (v.Magnitude > 1e-3 and v.Unit or toR.LookVector) * keep
		end
	end
	local lt = toR:PointToObjectSpace(pr)
	return V3(lt.X / sc.X, lt.Y / sc.Y, lt.Z / sc.Z)
end

-- body shots: a hook's elbow stays level with the fist (it would line up with a low arm otherwise)
local POLE_BODY = { hook = { 1, -0.35, 0.3 } }
local function poleOf(path, body)
	return (body and POLE_BODY[path]) or POLE[path] or POLE.straight
end

-- The punching forearm never goes through the boxer's own head. The head sits a neck's length over the
-- shoulders (measured on the rig: the Neck joint's C0 / C1 and the head's size, through this frame's neck
-- pose), and a fist going up past it - an overhand from a crouch to a taller man's head - would sweep the
-- forearm across the face with the elbow where the punch's pole puts it. So the pole turns round the
-- arm's line, the shortest way, until the forearm (elbow to wrist) clears the head by the forearm's own
-- radius, or as far from it as the arm can be; the swivel limit below keeps that turn smooth. (Overhands
-- only: the one punch that goes up past the boxer's own head.)
local CLEAR_STEPS = 12
local SIGNS = { 1, -1 }
local function forearmGap(arm, d, n, H)
	local e, f = R.armPoints(arm, d, n.X, n.Y, n.Z)
	local a = e + (f - e) * 0.1
	local ab = (f - e) * (arm.fw - 0.1)
	local s = clamp((H - a):Dot(ab) / max(1e-6, ab:Dot(ab)), 0, 1)
	return (a + ab * s - H).Magnitude
end
-- the turn (radians, round the arm's line dn from the pole n) that keeps the forearm off the head; 0 = clear
local function clearTurn(rig, p, arm, d, dn, n)
	local g = rig.geo
	local c0, c1i = g.jc0.Neck, g.jc1i.Neck
	if not (c0 and c1i and g.headR) then
		return 0
	end
	local H = arm.c0:PointToObjectSpace((c0 * p.Neck * c1i).Position)
	local need = g.headR + arm.rf
	local gap0 = forearmGap(arm, d, n, H)
	if gap0 >= need then
		return 0
	end
	-- (round the line both ways in steps; the first that clears, else the best; then halve back to the edge)
	local side = dn:Cross(n)
	local best, bestGap, pass = 0, gap0, nil
	for i = 1, CLEAR_STEPS do
		for _, sg in ipairs(SIGNS) do
			local a = sg * i * PI / CLEAR_STEPS
			local gap = forearmGap(arm, d, n * cos(a) + side * sin(a), H)
			if gap >= need then
				pass = a
				break
			elseif gap > bestGap then
				best, bestGap = a, gap
			end
		end
		if pass then
			break
		end
	end
	if not pass then
		return best
	end
	local lo = pass - (pass > 0 and 1 or -1) * PI / CLEAR_STEPS
	for _ = 1, 4 do
		local mid = (lo + pass) * 0.5
		if forearmGap(arm, d, n * cos(mid) + side * sin(mid), H) >= need then
			pass = mid
		else
			lo = mid
		end
	end
	return pass
end

-- Fitting a punch to the range, once, on its first frame (the chest and the punching shoulder are
-- swung round the spine to the punch's turn for each guess):
--  * hooks turn until the target sits HOOK_REL inside the line of the punching shoulder (seen from that
--    shoulder: the elbow out level with the fist, the forearm coming across), so the hook lands at any
--    range instead of the chest turning past the target and the arm punching the air in front of it;
--  * any punch whose target is still out of the arm's reach after the turn is thrown with a lunge: the
--    hips drive forward (up to LUNGE_MAX; the lead foot steps in on a straight) so the glove arrives.
-- Returns the share of the authored turn and the lunge (studs).
local HOOK_REL = math.rad(40)
local LUNGE_MAX = 0.5
local HOOK_REACH, HOOK_LUNGE_MAX, UPPER_LUNGE_MAX = 0.76, 1.1, 1.25
local OVER_ROOM = 0.6
-- a straight is fitted so its target sits STRAIGHT_REACH of the arm's full length from the shoulder (the
-- IK's soft limit lands it with the elbow about 160 degrees open); in close the hips give up to GIVE_MAX
-- of ground for it
local STRAIGHT_REACH = 1.02
local GIVE_MAX = 0.6
local STRAIGHT_TURN_MIN = 0.55
local RISE_MAX = 0.35
local STRAIGHT_LUNGE_FAR = 0.85
local RISE_HEEL = 0.1
local GIVE_MARGIN = 0.15
local STRAIGHT_THROUGH = 0.3
-- tan of the steepest a straight's shoulder-to-fist line climbs or drops to the head (10 degrees),
-- unless that would land it more than LEVEL_GIVE under / over the aim (a much taller man is still hit
-- on the jaw, not in the throat)
local STRAIGHT_PITCH = math.tan(math.rad(10))
local LEVEL_GIVE = 0.25
local function levelY(vy, h)
	local lim = h * STRAIGHT_PITCH
	return clamp(clamp(vy, -lim, lim), vy - LEVEL_GIVE, vy + LEVEL_GIVE)
end
local function fitPunch(rig, p, act, body, near, gain, drop)
	local prm = act.prm
	local arm = rig.geo[R.ARM_OF[act.hand][3]]
	if rig.lod < 2 or not (arm and arm.ok) then
		return 1, 0
	end
	local _, isBag = aimPoint(rig, p, act, body, near)
	if not act.aimLocal or isBag then
		return 1, 0
	end
	local turn = (prm.hip + prm.sho) * prm.mirror * gain
	local rc = rig.root.CFrame
	local ut = punchTorso(rig, p)
	local c = rc:PointToObjectSpace(ut.Position)
	local s0 = rc:VectorToObjectSpace(ut:PointToWorldSpace(arm.c0.Position) - ut.Position)
	local f0 = rc:VectorToObjectSpace(ut.LookVector)
	local tg = rc:PointToObjectSpace(act.aimTgt.CFrame:PointToWorldSpace(act.aimLocal)) - c
	-- (the turn is fitted to the target's centre: a hook's aim point lies beside the jaw)
	local tc = rc:PointToObjectSpace(act.aimTgt.Position) - c
	local function shoulder(k)
		local cs, sn = cos(turn * k), sin(turn * k)
		return s0.X * cs + s0.Z * sn, -s0.X * sn + s0.Z * cs
	end
	-- the target's bearing from the shoulder, relative to the chest's facing (+ = to its left)
	local function rel(k)
		local cs, sn = cos(turn * k), sin(turn * k)
		local fx, fz = f0.X * cs + f0.Z * sn, -f0.X * sn + f0.Z * cs
		local sx, sz = shoulder(k)
		local vx, vz = tc.X - sx, tc.Z - sz
		return math.atan2(fz * vx - fx * vz, fx * vx + fz * vz)
	end
	local k = 1
	if prm.path == "hook" and abs(turn) > 1e-3 then
		-- turning into the punch moves the target further inside the shoulder's line: bisect
		local want = act.hand == "L" and HOOK_REL or -HOOK_REL
		local sg = act.hand == "L" and 1 or -1
		local lo, hi = 0.45, 1.2
		if (rel(lo) - want) * sg >= 0 then
			k = lo
		elseif (rel(hi) - want) * sg <= 0 then
			k = hi
		else
			for _ = 1, 12 do
				local mid = (lo + hi) * 0.5
				if (rel(mid) - want) * sg < 0 then
					lo = mid
				else
					hi = mid
				end
			end
			k = (lo + hi) * 0.5
		end
	end
	-- out of reach after the turn: lunge (along the line to the target, in the root's frame)
	local sx, sz = shoulder(k)
	local dx, dy, dz = tg.X - sx, tg.Y - (s0.Y - drop), tg.Z - sz
	-- the body at contact (this punch's turn, lean, dip and step, as evalPunch drives it), laid out exactly:
	-- the shoulder-to-target vector (root frame) before any lunge
	local m = prm.mirror
	local leanX = body and -0.06 or 0
	local d0 = rig.loco and rig.loco.drop or 0
	local tw = act.aimTgt.CFrame:PointToWorldSpace(act.aimLocal)
	local function lay(kt, rise)
		local rt = CF(prm.side * m * gain, -drop + rise, -prm.fwd * gain) * p.Root * A(0, prm.hip * m * gain * kt, 0)
		local wt = p.W * A((prm.lean + leanX) * gain, prm.sho * m * gain * kt, prm.roll * m * gain)
		local utC = R.torsoCF(rig, d0 > 1e-3 and CF(0, -d0, 0) * rt or rt, wt)
		return rc:VectorToObjectSpace(tw - utC:PointToWorldSpace(arm.c0.Position))
	end
	-- the stance legs (AnimLoco's planted foot targets, last frame): how far the hips can still rise over
	-- them, laid out at contact (< 0 = how far the pelvis would have to sink to keep the feet down)
	local ft = rig.ftmp
	local function slack(kt, rise, lunge)
		if not (ft and ft.L and ft.R) then
			return 1
		end
		lunge = lunge or 0
		local rt = CF(prm.side * m * gain, 1 - drop + rise, -prm.fwd * gain - lunge) * p.Root * A(0, prm.hip * m * gain * kt, 0)
		local sl = 1
		for _, sd in ipairs(R.SIDES) do
			local tg = ft[sd]
			-- (the lead foot steps in with a long lunge)
			if sd == "L" and lunge > 0.2 then
				tg = V3(tg.X, tg.Y, tg.Z - lunge * 0.9)
			end
			sl = min(sl, 1 - R.dropFor(rig, sd, rt, tg, 0.965))
		end
		return sl
	end
	if prm.path == "straight" then
		-- a straight lands with the arm straight (STRAIGHT_REACH of its length) at any range: the body at
		-- contact is laid out and the hips travel the rest along the line - in, or in too close back, giving
		-- up to GIVE_MAX of ground (less of the punch's step first) - instead of the elbow folding into a
		-- shove. Still too close after that: the hips and shoulders turn less into it (down to
		-- STRAIGHT_TURN_MIN). To the head the fist travels about level (STRAIGHT_PITCH, evalPunch): a chin far
		-- above a deep crouch makes the legs drive up into the punch (up to RISE_MAX) rather than the arm
		-- reach up for it.
		local want = arm.dMax * STRAIGHT_REACH * (prm.reach or 1)
		-- (a jab gives less: hips going back while it snaps out take the snap out of it)
		local lo = -prm.fwd * gain - (act.pkind == "jab" and GIVE_MAX * 0.4 or GIVE_MAX)
		-- (and a chin too far up and out for the arm - a much taller man's - is stepped in on, up to
		-- STRAIGHT_LUNGE_FAR: the rear foot follows the lead in, a shuffle, rather than the legs locking out)
		local hi = body and LUNGE_MAX or STRAIGHT_LUNGE_FAR
		-- the hip travel that puts the (level-clamped) fist at `want` from the shoulder
		local function solve(v)
			local lunge = 0
			for _ = 1, 4 do
				local hz = v.Z + lunge
				local h = sqrt(v.X * v.X + hz * hz)
				local vy = body and v.Y or levelY(v.Y, h)
				local s2 = v.X * v.X + vy * vy
				if want * want <= s2 then
					return hi
				end
				lunge = -v.Z - sqrt(want * want - s2)
			end
			return lunge
		end
		local v0 = lay(1, 0)
		-- (a jab is too quick for the legs to drive)
		local rise = body and 0 or clamp(v0.Y - want * STRAIGHT_PITCH, 0, act.pkind == "jab" and 0 or RISE_MAX)
		-- (only as far as the stance legs still extend - the rear heel coming up gives a little more,
		-- RISE_HEEL - past that the pelvis would sink straight back and the fist land short and under:
		-- the hips travel in for the rest instead, stepping in for a long way)
		if rise > 0 then
			rise = clamp(slack(1, 0) + RISE_HEEL, 0, rise)
		end
		local kt, lunge = 1, 0
		for i = 0, 3 do
			kt = 1 - i * (1 - STRAIGHT_TURN_MIN) / 3
			lunge = solve(lay(kt, rise))
			if lunge >= lo then
				break
			end
		end
		act.rise = rise
		-- (a lunge the rear leg cannot stretch to - it would sink the pelvis - brings the rear foot in after
		-- the lead: the shuffle a long one always takes)
		lunge = clamp(lunge, lo, hi)
		act.shuffle = lunge > 0.25 and slack(kt, rise, lunge) + RISE_HEEL < 0
		-- (ground is given a little short of the layout: the stance keeps moving under the punch - a slip
		-- or a shoulder roll still settling - and a glove that falls short is worse than a softer elbow)
		if lunge < 0 then
			lunge = min(0, lunge + GIVE_MARGIN)
		end
		return kt, clamp(lunge, lo, hi)
	end
	-- (an overhand comes down from above and needs its room in front of the face: the hips go in only as
	-- far as the arm still reaches up to the head from there, never closer than OVER_ROOM of the arm out in
	-- front of the shoulder - a head out of reach above, a taller man's chin high on its neck, is not chased
	-- in under; the fist lands lower on it instead of the forearm sweeping across his own face)
	if prm.path == "over" then
		local v = lay(1, 0)
		local reachO = arm.dMax * 0.97 * (prm.reach or 1) - 0.15
		local hWant = max(sqrt(max(0, reachO * reachO - v.Y * v.Y)), arm.dMax * OVER_ROOM)
		-- (the lunge drives the hips along -Z: the target's depth that leaves hWant of room)
		local zWant = sqrt(max(0, hWant * hWant - v.X * v.X))
		local lunge = clamp(-v.Z - zWant + 0.05, 0, LUNGE_MAX)
		-- (a head that high above is not thrown at from a dip: the legs come up out of it as far as they
		-- extend; and the rear foot shuffles in after a lunge it cannot stretch to)
		act.rise = clamp(min(v.Y - reachO * 0.85, slack(k, 0) + RISE_HEEL), 0, max(drop, 0))
		act.shuffle = lunge > 0.25 and slack(k, act.rise, lunge) + RISE_HEEL < 0
		return k, lunge
	end
	-- (a chin high above an uppercut - a much taller man's - brings the legs up into it, as far as they
	-- still extend)
	local hook = prm.path == "hook"
	if prm.path == "upper" then
		local v = lay(k, 0)
		local reachU = arm.dMax * 0.97 * (prm.reach or 1) - 0.25
		act.rise = clamp(min(v.Y - reachU * 0.85, slack(k, 0) + RISE_HEEL), 0, RISE_MAX)
		dy -= act.rise
	end
	-- (an uppercut leans back as it rises: a little more; a hook lands with the elbow bent near square -
	-- HOOK_REACH of the arm - so it steps in further for it)
	local short = sqrt(dx * dx + dy * dy + dz * dz) - arm.dMax * (hook and HOOK_REACH or 0.97) * (prm.reach or 1)
		+ (prm.path == "upper" and 0.25 or 0)
	-- (hooks and uppercuts are the close punches: they step in for the range the bigger bodies keep)
	return k, clamp(short + 0.05, 0, hook and HOOK_LUNGE_MAX or (prm.path == "upper" and UPPER_LUNGE_MAX or LUNGE_MAX))
end

-- evaluate one punch layer; returns false when finished
local LATE = 1 / smooth(0.8)
local RET_SPEED = 9 -- studs/s, the fastest average a fist comes home at
local SWIVEL_RATE = 14 -- rad/s, the fastest the elbow turns round the arm's line in a punch
-- the fist's speed at contact the arm's drive is timed for (studs/s), per path
local VPEAK = { straight = 22, hook = 23, upper = 16, over = 20 }
-- the steadier drive of a straight with a long way to go (act.pow, 1.5 - 2): a cubic that sets off from a
-- standstill and still accelerates all the way in, arriving at `pw` times its average speed - unlike
-- x ^ pw below 2, which jumps to speed on its first frame (the fist pops as the arm sets off)
local function evenDrive(x, pw)
	x = clamp(x, 0, 1)
	local c = 3 - pw
	return x * x * (c + (1 - c) * x)
end
local function evalPunch(p, rig, act, t, near, driveBody)
	local prm = act.prm
	local w = act.windup
	local el = t - act.start
	local hold = 0.045
	-- (the recovery: the punch's own time, or longer for a long way home - a fist never flies back
	-- faster than RET_SPEED on average; set at contact, act.recDur)
	local rec = act.recDur or w * prm.rec
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
		-- hips, then shoulders, then the arm: the trunk is still turning at contact (~2/3 of its top
		-- speed) while the arm accelerates all the way into the target
		hipK = smooth(0.8 * (u - prm.tHip) / (1 - prm.tHip)) * LATE
		shoK = smooth(0.8 * (u - prm.tSho) / (1 - prm.tSho)) * LATE
		local ta = act.tArm or prm.tArm
		armK = act.pow and evenDrive((u - ta) / (1 - ta), act.pow) or K.drive((u - ta) / (1 - ta), prm.pow)
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
		-- (quintic: a long lunge comes back with no lurch as it settles into the stance)
		hipK = 1 - K.smoother((r - 0.12) / 0.88)
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
		-- (a hook to the body turns less: the fist has to land in front of the chest, not beside it)
		local rk = (body and prm.path == "hook") and 0.72 or 1
		if not act.turnK then
			act.turnK, act.lunge = fitPunch(rig, p, act, body, near, pw * rk, (prm.dip + dipExtra) * pw)
			-- a long lunge: the lead foot steps in with it (an overhand's too: its lunge up at a taller man's
			-- head over planted feet would only sink the pelvis)
			if act.lunge > 0.2 and not prm.step and not prm.stepR then
				act.leadIn = -act.lunge * 0.9
				-- (a step in further than the stance can stretch: the rear foot follows - a shuffle in - as
				-- soon as it is free)
				if act.lunge > 0.6 or act.shuffle then
					act.followR = -max(act.lunge - 0.4, act.lunge * 0.5) * 0.9
				end
			end
		end
		-- (the lead foot steps as soon as it is free - still landing from the last punch's step it goes a
		-- few frames late, rather than leave the hips to lunge out over planted feet: the rear leg would
		-- lock straight and the pelvis sink, taking the shoulder down and away from the target)
		if act.leadIn and el < w * 0.7 and L.ready(rig, "L", t) then
			L.request(rig, "L", 0, act.leadIn, max(0.1, w * 0.75 - el), 0.1, max(0.1, w * 1.6 - el), t)
			act.leadIn = nil
		end
		if act.followR and not act.leadIn and el < w * 0.75 and L.ready(rig, "R", t) then
			L.request(rig, "R", 0, act.followR, max(0.1, w * 0.9 - el), 0.08, w * 2, t)
			act.followR = nil
		end
		rk *= act.turnK
		-- (the anticipation turns the other way first: the load before the drive)
		local hD, sD = prm.hip * mirror, prm.sho * mirror
		local hip = hD * pw * rk * hipK + bf.hip * fh - prm.aHip * (hD >= 0 and 1 or -1) * anti
		local sho = sD * pw * rk * shoK + bf.sho * fs - prm.aSho * (sD >= 0 and 1 or -1) * anti
		local lean = (prm.lean + leanExtra) * pw * shoK + bf.lean * fs + prm.aLean * anti
		local roll = (prm.roll * mirror * pw + (body and prm.path == "hook" and (L_ and 0.12 or -0.12) or 0)) * shoK + bf.roll * fs
		local fwd = (prm.fwd * pw + act.lunge) * hipK + bf.fwd * fh
		local side = prm.side * mirror * pw * hipK + bf.side * fh
		local dip = (prm.dip + dipExtra) * pw * hipK + bf.dip * fh + prm.aDip * anti - (act.rise or 0) * hipK
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
			f.pivot += sgn * (prm.pivotAmt or 0.5) * k * min(1, act.turnK + 0.3)
			f.knee += sgn * ((pv == "L" and prm.kneeL or prm.kneeR) or 0.2) * k
		end
		if prm.heelL and pv ~= "L" then
			rig.foot.L.heel = max(rig.foot.L.heel, prm.heelL * shoK)
		end
		if prm.rise then
			-- the uppercut's leg drive: up onto the balls of the feet as the body rises (the punching
			-- side's heel highest)
			local up = smooth((u - prm.load) / (1 - prm.load)) * (1 - smooth(retK / 0.6))
			local hi = mirror > 0 and rig.foot.R or rig.foot.L
			local lo2 = mirror > 0 and rig.foot.L or rig.foot.R
			hi.heel = max(hi.heel, 0.55 * up)
			lo2.heel = max(lo2.heel, 0.3 * up)
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
		local eT = prm.elbowT or prm.tArm
		local pk = PEAK[prm.path] or PEAK.straight
		local P3 = V3(inward * pk.x, (body and pk.by or pk.y) - (prm.low or 0), pk.z * (prm.reach or 1))
		local aimed, isBag = aimPoint(rig, p, act, body, near)
		if aimed then
			if isBag then
				P3 = aimed
			else
				P3 = prm.path == "over" and P3:Lerp(aimed, 0.9) or aimed
			end
		end
		-- never further than the arm reaches from this shoulder (the elbow straightens at contact)
		local arm = g[R.ARM_OF[act.hand][3]]
		local sc = g.utScale
		if aimed and not isBag and not body and prm.path == "straight" and arm and arm.ok then
			-- a straight travels about level: the shoulder-to-fist line never climbs or drops more than
			-- STRAIGHT_PITCH (a taller man is met under the chin, a crouching one on the brow), never a
			-- shove up over the puncher's own head
			local ut = punchTorso(rig, p)
			local s0 = arm.c0.Position
			local vW = ut:VectorToWorldSpace(V3(P3.X * sc.X, P3.Y * sc.Y, P3.Z * sc.Z) - s0)
			local vy = levelY(vW.Y, sqrt(vW.X * vW.X + vW.Z * vW.Z))
			if vy ~= vW.Y then
				local l = ut:VectorToObjectSpace(V3(vW.X, vy, vW.Z)) + s0
				P3 = V3(l.X / sc.X, l.Y / sc.Y, l.Z / sc.Z)
			end
		end
		if arm and arm.ok then
			local sh = V3(arm.c0.Position.X / sc.X, arm.c0.Position.Y / sc.Y, arm.c0.Position.Z / sc.Z)
			local v = P3 - sh
			-- (contact a touch short of full extension: the fist is still accelerating when it lands;
			-- measured in studs, the torso units are not square)
			-- (a straight asks for the whole arm: the IK's soft limit still stops it just short, the elbow
			-- about 160 degrees open)
			local reachS = arm.dMax * (prm.path == "straight" and 1.03 or 0.985) * (prm.reach or 1)
			local vS = (v * sc).Magnitude
			-- (and a straight that ends up a little too close still snaps out straight: its fist goes up to
			-- STRAIGHT_THROUGH on through the aim point - the glove already sinks into the face there - rather
			-- than land with the elbow folded)
			if prm.path == "straight" and aimed and not isBag and vS > 1e-3 then
				local want = arm.dMax * (prm.reach or 1)
				if vS < want then
					v *= (vS + min(want - vS, STRAIGHT_THROUGH)) / vS
					P3 = sh + v
					vS = (v * sc).Magnitude
				end
			end
			if vS > reachS then
				P3 = sh + v * (reachS / vS)
			end
			-- nor so close that the elbow has to fold shut: a target that ends up beside the shoulder
			-- is met in front of it instead (a hook's turn already puts the target where it belongs)
			local reach = reachS / max(0.2, sc.Y)
			local near = reach * 0.68
			v = P3 - sh
			if v.Magnitude < near and prm.path ~= "hook" then
				local fwdD = sqrt(max(0, near * near - v.X * v.X - v.Y * v.Y))
				P3 = V3(P3.X, P3.Y, sh.Z - fwdD)
			end
		end
		-- the arm's drive is timed so the fist arrives at about VPEAK whatever the way to the target: a
		-- short way (in close, a small man) is covered later and faster, a long one (a hook up from the
		-- shell's low lead hand) starts sooner (once, on the first frame)
		if not act.tArm then
			-- (the fist's speed at contact is the drive's pow x the path's end tangent / the drive's time;
			-- a smaller man's punches are proportionally slower: the same joint speeds)
			local len
			if prm.path == "hook" then
				-- (a hook's C-arc is slowest in its middle and sweeps in across at the end: its speed
				-- is the arc's own over the last fifth of the curve, where the fist lands)
				local a = hookPos(rig, p, act, P0, P3, 1, eT, 0.8, inward, body, sc, 0)
				local b = hookPos(rig, p, act, P0, P3, 1, eT, 1, inward, body, sc, 0)
				-- (never so short that the fist waits in the chamber: a hand already out in front - the
				-- out-boxer's low lead - still whips round from the load, it does not stall and jerk)
				len = max(((b - a) * sc).Magnitude / 0.2, 1.3)
			else
				local _, B2 = pathPoints(prm.path, P0, P3, inward, prm.arc or 0.6, prm.rise)
				len = max(((P3 - P0) * sc).Magnitude, 3 * ((P3 - B2) * sc).Magnitude)
			end
			-- (a hook to the body lands while the knees drop the whole body with it: timed a touch faster)
			local vp = (VPEAK[prm.path] or 20) * ((body and prm.path == "hook") and 1.12 or 1)
			local need = prm.pow * len / (vp * clamp((arm and arm.ok and arm.dMax or 2.43) / 2.43, 0.8, 1.1))
			act.tArm = clamp(1 - need / w, max(0.12, prm.tArm - 0.15), 0.8)
			-- (a straight with a long way to go in its time - the shell's low lead hand up to a chin that sits
			-- high on its neck - travels at a steadier speed instead of whipping in: driven as hard as the
			-- others it asks the elbow to lock out faster than the arm turns, and the fist arrives a frame
			-- after the head it was aimed at has already snapped back)
			local avail = (1 - act.tArm) * w
			if prm.path == "straight" and need > avail then
				act.pow = max(1.5, prm.pow * avail / need)
			end
		end
		local pos
		local pole = poleOf(prm.path, body)
		local kp
		if retK > 0 then
			-- recovery: the fist comes home first, a little lower and inside, fast then easing
			local hit = act.hitPos or P3
			-- (the fist rests on the target for the hold: it leaves from a standstill; smoothstep, not a
			-- cubic ease: the way home peaks at 1.5x its average speed, not 3x)
			local k = smooth(min(1, retK / 0.8))
			-- (low and in front of the face on the way: a high guard - the peek-a-boo's gloves at the
			-- forehead - is reached from below and in front, so the forearm never sweeps across the
			-- face while the shoulders are still turned)
			local c2 = Pg + V3(0, -0.3, -0.6)
			-- (a fist that landed high or level with the face - an overhand over a deep crouch - first
			-- comes forward and down, clear of the head; a straight one just starts home)
			local c1 = V3(hit.X, min(hit.Y, Pg.Y + 0.35), min(hit.Z, Pg.Z - 0.65))
			pos = K.bezier(hit, c1, c2, Pg, k)
			-- the elbow settles back to the guard more slowly than the fist comes home
			kp = 1 - smooth(retK)
		else
			if prm.path == "hook" then
				pos = hookPos(rig, p, act, P0, P3, u, eT, armK, inward, body, sc, contact and (1 - (el - w) / hold) or 0)
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
			end
			act.hitPos = pos
			if contact then
				local home = (pos - Pg) * sc
				act.recDur = max(w * prm.rec, home.Magnitude / RET_SPEED)
			end
			-- the elbow's line through the punch follows time, not the accelerating fist (a hook's
			-- elbow comes up with the hips, before the arm whips round: the shoulder never has to
			-- swing the whole arm up and across in the last tenth of a second)
			kp = smooth(clamp((u - eT) / ((1 - eT) * 0.85), 0, 1))
			if contact then
				kp = 1
			end
		end
		act.lastPos = pos
		-- the elbow rises into the punch (a hook's elbow comes up late) and settles back on the way home
		local zb = lerp(-0.1, pole[3], kp)
		-- (from the guard the arm IK takes over from the stance's arm as the punch starts moving it, not
		-- in the last frames of the drive)
		local kb = act.from and 1 or smooth(clamp((u - eT) / 0.3, 0, 1))
		if retK > 0 then
			kb = 1
		end
		-- the elbow's direction (the pole) blends from the guard's to the punch's and back; where that
		-- blend points along the arm itself (the raised, out-turned elbow of an overhand or a hook
		-- coming home, a guard whose elbow hangs along the forearm) the hinge is undefined and would
		-- flip in a frame: the pole is taken perpendicular to the arm's line, held from the last frame
		-- when it has no direction of its own, and never swivels round the line faster than
		-- SWIVEL_RATE
		local gpo = (L_ and rig.guardPoleL or rig.guardPoleR) or 0.2
		local px, py, pz = lerp(gpo, pole[1], kp), lerp(-1, pole[2], kp), zb
		local armG = g[R.ARM_OF[act.hand][3]]
		if armG and armG.ok then
			local mx = L_ and -1 or 1
			local d = armG.c0:PointToObjectSpace(V3(pos.X * sc.X, pos.Y * sc.Y, pos.Z * sc.Z))
			if d.Magnitude > 1e-3 then
				local dn = d.Unit
				local n = V3(mx * px, py, pz)
				n -= dn * n:Dot(dn)
				-- (off his own head: in with the punch's elbow line; on the way home the turn it landed with
				-- eases out with the elbow - never searched for again, so it cannot flip sides mid-recovery)
				if prm.path == "over" and kp > 0.01 and n.Magnitude > 0.15 then
					local a
					if retK > 0 then
						a = (act.clearA or 0) * kp
					else
						act.clearA = clearTurn(rig, p, armG, d, dn, n)
						a = act.clearA * kp
					end
					if a ~= 0 then
						n = n * cos(a) + dn:Cross(n) * sin(a)
					end
				end
				local last, lastT = act.swivN, act.swivT
				local lp
				if last then
					lp = last - dn * last:Dot(dn)
					lp = lp.Magnitude > 1e-3 and lp.Unit or nil
				end
				if n.Magnitude < 0.15 and lp then
					n = lp
				elseif n.Magnitude > 1e-4 then
					n = n.Unit
					if lp and lastT and t > lastT then
						local ang = math.acos(clamp(lp:Dot(n), -1, 1))
						local maxA = SWIVEL_RATE * (t - lastT)
						if ang > maxA then
							local q = n - lp * lp:Dot(n)
							if q.Magnitude > 1e-4 then
								n = lp * cos(maxA) + q.Unit * sin(maxA)
							else
								n = lp
							end
						end
					end
				end
				if n.Magnitude > 1e-4 then
					act.swivN, act.swivT = n, t
					px, py, pz = mx * n.X, n.Y, n.Z
				end
			end
		end
		pathed = guardArm(rig, p, act.hand, pos.X, pos.Y, pos.Z, kb, -pz, px, py)
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
-- head-shot reactions. SNAP = the head's direction per punch (pitch + = face up, yaw + = to his left,
-- roll; a lead hook lands on the defender's right: his head snaps to his left), CHEST = the torso's
-- follow-through (pitch / yaw / roll). Sizes per severity tier (TIER): the neck's peak angular speed
-- (rad/s), the chest's, the hips knocked back (studs/s), the knees giving (studs/s), the arms knocked
-- loose (rad/s). Light = a head snap; medium = snap + the chest follows + a catch step; heavy = + legs
-- shake, guard knocked loose; critical = + the knees buckle
local SNAP = {
	jab = { 1, 0, 0.15 }, cross = { 0.95, 0.1, 0.25 }, leadhook = { 0.15, 0.8, 0.62 }, rearhook = { 0.15, -0.8, -0.62 },
	uppercut = { 1, 0, 0.1 }, overhand = { -0.45, -0.4, -0.55 },
}
SNAP.hook = SNAP.rearhook
local CHEST = {
	jab = { 1, 0, 0.1 }, cross = { 1, 0.1, 0.15 }, leadhook = { 0.25, 0.7, 0.8 }, rearhook = { 0.25, -0.7, -0.8 },
	uppercut = { 1, 0, 0.1 }, overhand = { -0.4, -0.35, -0.6 },
}
CHEST.hook = CHEST.rearhook
-- (the neck numbers are the kick; the stiff head spring loses about a third of it inside the first
-- frame, so a light snap reads as about 8-9 rad/s frame to frame, a medium one 12-13)
local TIER = {
	{ neck = 13, chest = 1.8, back = 0.6, drop = 0.15, arms = 0 },
	{ neck = 19, chest = 3.2, back = 1.2, drop = 0.4, arms = 0.6 },
	{ neck = 24, chest = 5.0, back = 2.1, drop = 0.9, arms = 1.4 },
	{ neck = 29, chest = 6.0, back = 2.5, drop = 1.5, arms = 2.0 },
}
-- severity range of each tier (the size grows a little within a tier)
local TIER_LO = { 0, 0.35, 0.75, 1.1 }
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

function AnimFight.react(rig, kind, ptype, flag, sev, t, hand)
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
		local T = TIER[tier]
		-- within a tier a harder shot is a little bigger; a counter / a dazed man's neck a little more
		local within = clamp((sev - TIER_LO[tier]) / 0.4, 0, 1)
		local m = (0.88 + 0.24 * within) * (flag == "counter" and 1.1 or 1) * (1 + 0.08 * daze)
		-- straight shots tilt the head away from the punching hand (either way when it is unknown)
		local rs
		if hand == "L" or hand == "R" then
			rs = hand == "R" and 1 or -1
		else
			rs = rig.rng:NextNumber() < 0.5 and -1 or 1
		end
		local straight = ptype == "cross" or ptype == "uppercut" or ptype == "jab"
		local sd = SNAP[ptype] or SNAP.cross
		local cd = CHEST[ptype] or CHEST.cross
		local sl = math.sqrt(sd[1] * sd[1] + sd[2] * sd[2] + sd[3] * sd[3])
		local n = T.neck * m / sl
		local c = T.chest * m
		local G = R.HEAD_GAIN
		local push = PUSH[ptype] or PUSH.cross
		kick(rig, sd[1] * n / G[1], sd[2] * n * (straight and rs or 1) / G[2], sd[3] * n * (straight and rs or 1) / G[3],
			cd[1] * c, cd[2] * c * (straight and rs or 1), cd[3] * c * (straight and rs or 1),
			push[2] * T.back * m, push[1] * T.back * m, T.drop * m, 0, T.arms * m, T.arms * m, T.arms * 0.75 * m, T.arms * 0.75 * m)
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
		-- the referee wraps his arms round a man out on his feet and holds him up: braced, leaning in,
		-- hands under the armpits and round the back
		local e = smooth(el / 0.35) * (1 - smooth((el - act.dur + 0.4) / 0.4))
		p.Root = CF(0, -0.3 * e, -0.08 * e) * p.Root
		p.W = p.W * A(-0.15 * e, 0, 0)
		p.LS = p.LS:Lerp(A(1.35, 0, -0.15), e)
		p.RS = p.RS:Lerp(A(1.35, 0, 0.15), e)
		p.LE = p.LE:Lerp(A(1.0, 0, 0), e)
		p.RE = p.RE:Lerp(A(1.0, 0, 0), e)
		p.Neck = p.Neck * A(0.05 * e, 0.4 * e, 0)
		local vm = rig.lookPart and rig.lookPart.Parent
		local ut = vm and vm:FindFirstChild("UpperTorso")
		if ut and rig.geo.ok and rig.lod >= 2 then
			-- each hand to the side of the fighter's chest nearest to it, reaching round towards his back
			local rc = rig.root.CFrame
			local c = ut.Position
			local to = V3(c.X - rc.X, 0, c.Z - rc.Z)
			to = to.Magnitude > 0.1 and to.Unit or rc.LookVector
			local hx = ut.Size.X * 0.5 + 0.05
			for _, s in ipairs(R.SIDES) do
				local side = rc.RightVector * (s == "L" and -hx or hx)
				R.armIK(rig, p, s, c + side + to * 0.3 + V3(0, 0.2, 0), e)
			end
		end
		flex(rig, "lats", 0.7 * e)
		flex(rig, "biceps", 0.6 * e)
		flex(rig, "quads", 0.5 * e)
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
