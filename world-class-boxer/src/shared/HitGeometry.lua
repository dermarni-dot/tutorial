-- HitGeometry: reach and hit volumes from the live rig, shared by the server (FightEngine: the authoritative
-- range check in Fight:Resolve, PunchRange, the body separation, the clinch reach) and the client (FightClient: the
-- punch prediction and the range read-out), so both run the same code on the same numbers.
--
-- A FRAME is one fighter's body as the fight sees it, in studs above his soles (HitGeometry.Frame reads it off
-- the rig's parts; HitGeometry.FrameFromScales builds it from Builder.Scales / the unit rig when there is no rig,
-- as the headless sims have none):
--   stand        sole to crown
--   shoulderY    the shoulder pivot's height; shoulderHalf = half the shoulder width
--   arm          shoulder pivot to the glove's striking face (upper arm + forearm + the glove past the wrist)
--   glove        the glove's radius (half its width)
--   headY, headR the head's centre and radius (the head zone is a sphere: its bottom is the chin)
--   chestY       the top of the torso (the body zone's top), waistY its bottom, torsoHalfW / torsoHalfD its half sizes
--   hScale       stand / the unit rig's (the step and lean a punch gets scale with the legs)
--
-- A punch is a glove path from the attacker's shoulder: a straight goes out level (down to the body, up to a
-- taller chin within its angles), a hook comes round at shoulder height (dipping to the body), an uppercut rises
-- from under the target, an overhand comes over the top. Its reach R is the attacker's (arm + glove + his step),
-- calibrated per punch so that the unit rig against itself lands at exactly the distance the fight was balanced
-- on (FightMotion.Spacing.base x Config.Punches[p].range), and shaped by the height difference: a target above the
-- shoulder costs a straight or a hook reach (the arm reaches up, not out), costs an uppercut nothing (it is going
-- up anyway) and an overhand comes down, so a target below is easy for it. The zone is hit when the glove path
-- meets it inside R plus a tolerance that scales with both men (the glove and the target).
--
-- Every function is pure (no Roblox services): tools/sim/test_hitdetect.luau drives it under lune.
local HitGeometry = {}

-- the unit rig (BodyAssetData.unit: Builder's 70-inch Athletic man at Height / Width / Depth 1; the realistic
-- torso of tools/sim/host.luau), studs above the soles
local UNIT = {
	stand = 6.457, -- neck 5.2892 + (0.5 + 0.26 lift) x head 0.9269 + head / 2
	shoulderY = 4.9199, shoulderX = 0.9549, elbowY = 4.002, wristY = 3.072,
	gloveLen = 0.73, glove = 0.32, -- BuilderBody's fist: ~1.15 x its width from the wrist to the striking face
	headY = 5.994, head = 0.9269, headScale = 0.7724,
	neckY = 5.2892, hipY = 2.6712, utW = 1.59, utD = 0.97, ltW = 1.59,
	heightIn = 70, reachIn = 70,
}
UNIT.arm = (UNIT.shoulderY - UNIT.wristY) + UNIT.gloveLen
HitGeometry.UNIT = UNIT

-- the spacing the ranges were first balanced on (FightMotion.Spacing: base 4.3 x Config.Punches[p].range), kept for
-- the callers that read it; the ranges themselves are calibrated to what the fight ANIMATION reaches (TARGET below)
HitGeometry.BASE = 4.3
HitGeometry.MIN_SEP = 3.25
HitGeometry.CLINCH = 4.8
-- the root-to-root distance out to which the unit rig's punch VISIBLY lands on the unit rig (AnimFight's extension,
-- measured by tools/sim/v9_anim.luau's punch clip over a sweep of gaps: the glove's face within a quarter stud of the
-- head / the chest at the peak - jab 5.5, cross 5.6, lead hook 4.85, rear hook 5.35, uppercut 4.7, body jab 5.35 on
-- the Athletic tier-3 rig; the Heavyweight within 0.1, the Lean within 0.2), less a tenth: the server's hit test and
-- the player's eye agree on the boundary (tools/sim/test_hitdetect pins it within 0.25). The overhand (not in the
-- clip) takes the cross's; the body shots the body jab's share of the head's
local TARGET = {
	jab = { head = 5.5, body = 5.35 },
	cross = { head = 5.45, body = 5.3 },
	leadhook = { head = 4.8, body = 4.7 },
	rearhook = { head = 5.3, body = 5.15 },
	uppercut = { head = 4.65, body = 4.55 },
	overhand = { head = 5.3, body = 5.15 },
}
HitGeometry.TARGET = TARGET

-- the punch's shape by kind: where it starts (origin: shoulderY + o x arm), the angles it can be thrown at (up /
-- down, degrees, at full reach), how far up and down the glove gets from the origin as a share of the arm (the
-- vertical reach: an uppercut rises a whole arm and the legs' drive, a hook barely rises, an overhand comes down
-- over the top; a straight or a hook dips to the body as far as it reaches out), the dip a body shot takes (x arm)
local KIND = {
	straight = { o = 0, up = 50, down = 48, vUp = 0.92, vDown = -1, rise = 0.2, dip = 0.25 },
	hook = { o = 0.02, up = 34, down = 40, vUp = 0.6, vDown = -1, rise = 0.1, dip = 0.3 },
	uppercut = { o = -0.1, up = 85, down = 24, vUp = 1.0, vDown = 0.5, rise = 0.35, dip = 0 },
	overhand = { o = 0.2, up = 20, down = 58, vUp = 0.45, vDown = 1.05, rise = 0.2, dip = 0 },
}
HitGeometry.KIND = KIND
local PUNCH_KIND = { jab = "straight", cross = "straight", leadhook = "hook", rearhook = "hook", uppercut = "uppercut", overhand = "overhand" }
HitGeometry.PUNCH_KIND = PUNCH_KIND
-- Config.Punches[p].range (kept here so the module stays pure; FightEngine passes the live table through opts)
local RANGE = { jab = 1.10, cross = 1.05, leadhook = 0.85, rearhook = 0.85, uppercut = 0.75, overhand = 1.0 }
HitGeometry.RANGE = RANGE

-- the tolerance: a share of the glove plus the target (the bigger the pair, the softer the edge)
local TOL = 0.14
-- how far a bend (a duck, a weave, a roll, a body-shot crouch) takes the head and the chest down, x stand
local BEND_DROP = 0.16
-- the step and lean a punch gets past the arm, at the unit height (the rest of the balanced reach)
local STEP = 1.45

local function num(v, d)
	return type(v) == "number" and v == v and v or d
end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
-- from Builder.Scales (height / width / depth / head) and the tale of the tape: sc = { height, width, depth,
-- head } (1 = the unit), opts = { height (in), reach (in), female }
function HitGeometry.FrameFromScales(sc, opts)
	sc = sc or {}
	opts = opts or {}
	local hs = math.clamp(num(sc.height, 1), 0.5, 2)
	local ws = math.clamp(num(sc.width, 1), 0.5, 2)
	local ds = math.clamp(num(sc.depth, 1), 0.5, 2)
	local hd = math.clamp(num(sc.head, UNIT.headScale) / UNIT.headScale, 0.5, 2)
	local female = opts.female == true
	-- the tape's reach against its height: a long-armed man's arms run past the rig's (half the ape index)
	local hIn = math.max(40, num(opts.height, UNIT.heightIn))
	local rIn = num(opts.reach, hIn)
	local ape = math.clamp(1 + 0.5 * (rIn / hIn - 1), 0.85, 1.15)
	local fw = female and 0.93 or 1
	local F = {
		stand = UNIT.stand * hs,
		shoulderY = UNIT.shoulderY * hs,
		shoulderHalf = UNIT.shoulderX * ws * (female and 0.95 or 1),
		arm = UNIT.arm * hs * ape,
		glove = UNIT.glove * (0.5 * ws + 0.5 * ds) * fw,
		headY = UNIT.headY * hs,
		headR = UNIT.head / 2 * hs * hd,
		chestY = UNIT.neckY * hs,
		waistY = UNIT.hipY * hs,
		torsoHalfW = UNIT.utW / 2 * ws * (female and 0.9 or 1),
		torsoHalfD = UNIT.utD / 2 * ds * (female and 0.94 or 1),
		hScale = hs,
		female = female,
		source = "scales",
	}
	return F
end

-- the default frame (the unit rig)
function HitGeometry.Unit()
	return HitGeometry.FrameFromScales(nil, nil)
end

-- the numbers a frame must carry, all finite and positive (a frame with one missing or zero would read as a man
-- with no reach: never handed out)
local FRAME_KEYS = { "stand", "shoulderY", "shoulderHalf", "arm", "glove", "headY", "headR", "chestY", "waistY", "torsoHalfW", "torsoHalfD", "hScale" }
HitGeometry.FRAME_KEYS = FRAME_KEYS
local function finitePositive(v)
	return type(v) == "number" and v == v and v > 0 and v < math.huge
end
-- nil when the frame is sound, else what is wrong with it
function HitGeometry.Invalid(F)
	if type(F) ~= "table" then
		return "no frame"
	end
	for _, k in ipairs(FRAME_KEYS) do
		if not finitePositive(F[k]) then
			return k .. "=" .. tostring(F[k])
		end
	end
	if not (F.stand > 3 and F.headY > F.chestY and F.chestY > F.waistY) then
		return string.format("heights out of order (stand %.2f head %.2f chest %.2f waist %.2f)", F.stand, F.headY, F.chestY, F.waistY)
	end
	if not (F.arm > 1 and F.arm < 6) then
		return string.format("arm %.2f", F.arm)
	end
	return nil
end
HitGeometry.Valid = function(F)
	return HitGeometry.Invalid(F) == nil
end

-- the joint chain of a mesh arm against its parts' bounding boxes (BodyAssetData: the shoulder-to-elbow and
-- elbow-to-wrist rig attachments over the parts' Size.Y; the boxes overlap at the joints, so a box sum reads an arm
-- half as long again as it is)
local ARM_BOX = { upper = 0.63, lower = 0.70 }
-- the shoulder pivot under the upper arm's top, the fist's padding past the hand (x the part's Size.Y)
local SHOULDER_UNDER_TOP, FIST_PAST_HAND = 0.2, 0.35

-- from the live rig: model = the character, soleY = the height of its soles in world space (the caller knows the
-- rig's HipHeight: FightEngine.StandHeight), fallback = a frame to fill anything the rig does not have (optional).
-- Sizes come from the parts (exact and replicated), heights from their rest-pose positions over the root (the
-- server sees the rig in rest, arms hanging; the client is handed the server's frames in the fight's start
-- message). The arm is measured down the hanging chain, shoulder pivot (the ShoulderRigAttachment when the part
-- has one) to the glove's face, never as a sum of part boxes.
-- Returns the frame. F.source = "rig" when it came off the parts; otherwise the fallback's, with F.fallback = why
-- the rig was not used (the caller logs it once). Never a frame with a zero or NaN in it (HitGeometry.Invalid).
function HitGeometry.Frame(model, soleY, fallback)
	local base = fallback or HitGeometry.Unit()
	if HitGeometry.Invalid(base) then
		base = HitGeometry.Unit()
	end
	local function giveUp(why)
		local F = table.clone(base)
		F.fallback = why
		return F
	end
	if not model then
		return giveUp("no model")
	end
	local function vec(v)
		local ok, x, y, z = pcall(function()
			return v.X, v.Y, v.Z
		end)
		if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" and x == x and y == y and z == z then
			return x, y, z
		end
		return nil
	end
	local function part(n)
		local ok, p = pcall(function()
			return model:FindFirstChild(n)
		end)
		if not (ok and p) then
			return nil
		end
		if typeof(p) == "Instance" and not p:IsA("BasePart") then
			return nil
		end
		local sx, sy, sz = vec(p.Size)
		local _, py = vec(p.Position)
		if not (sx and py) or sx <= 0 or sy <= 0 or sz <= 0 then
			return nil
		end
		return { X = sx, Y = sy, Z = sz, posY = py, inst = p }
	end
	-- a rig attachment's height in world space (the rest pose stands upright: the part's Y plus the attachment's)
	local function attY(p, name)
		if not p then
			return nil
		end
		local ok, a = pcall(function()
			return p.inst:FindFirstChild(name)
		end)
		if ok and a then
			local _, y = vec(a.Position)
			if y then
				return p.posY + y
			end
		end
		return nil
	end
	local root = part("HumanoidRootPart")
	if not root then
		return giveUp("no HumanoidRootPart")
	end
	-- the soles: the feet's own bottoms in the rest pose when the rig has feet (the rig's truth, wherever the floor
	-- or the Humanoid's HipHeight says it stands: a HipHeight 0.7 off the legs' own put every height off by as
	-- much), else what the caller worked out from the HipHeight, else the classic 3.2 under the root
	local sole = num(soleY, root.posY - 3.2)
	local lf, rf = part("LeftFoot"), part("RightFoot")
	if lf or rf then
		local fb = math.min(lf and (lf.posY - lf.Y / 2) or math.huge, rf and (rf.posY - rf.Y / 2) or math.huge)
		if fb < root.posY - 1 and fb > root.posY - 6 then
			sole = fb
		end
	end
	local function top(p)
		return p.posY + p.Y / 2 - sole
	end
	local function bottom(p)
		return p.posY - p.Y / 2 - sole
	end
	local head, ut, lt = part("Head"), part("UpperTorso"), part("LowerTorso")
	local side = part("LeftUpperArm") and "Left" or "Right"
	local ua, la = part(side .. "UpperArm"), part(side .. "LowerArm")
	local hand, glove = part(side .. "Hand"), part("Glove" .. side:sub(1, 1))
	if not (head or ut) then
		-- (a root alone: the headless sims' stub rigs)
		return giveUp("no Head / UpperTorso (a root alone)")
	end
	local F = table.clone(base)
	F.source = "rig"
	F.fallback = nil
	if head then
		F.headR = math.max(head.X, head.Y) / 2
		F.headY = head.posY - sole
		F.stand = F.headY + head.Y / 2
	end
	if ut then
		F.chestY = top(ut)
		F.torsoHalfW = ut.X / 2
		F.torsoHalfD = ut.Z / 2
		-- the shoulder pivot sits a little under the torso's top, out at its side
		F.shoulderY = F.chestY - ut.Y * 0.16
		F.shoulderHalf = ut.X / 2 + (ua and ua.X / 2 or 0.25)
	end
	if lt then
		F.waistY = bottom(lt)
	elseif ut then
		F.waistY = bottom(ut) - 0.5
	end
	F.hScale = math.clamp(F.stand / UNIT.stand, 0.5, 2)
	if ua and la then
		-- the shoulder pivot: the rig attachment, else just under the upper arm's top
		local pivot = attY(ua, side .. "ShoulderRigAttachment") or (ua.posY + ua.Y / 2 - ua.Y * SHOULDER_UNDER_TOP)
		-- the glove's striking face: the glove's bottom, else the fist's padding past the hand, else the wrist
		local face
		if glove then
			face = glove.posY - glove.Y / 2
		elseif hand then
			face = hand.posY - hand.Y / 2 - hand.Y * FIST_PAST_HAND
		else
			face = (attY(la, side .. "WristRigAttachment") or (la.posY - la.Y / 2 + la.Y * 0.1)) - UNIT.gloveLen * F.hScale
		end
		-- the chain by the joints when the parts carry them, else the boxes corrected for their overlap
		local upper = attY(ua, side .. "ShoulderRigAttachment") and attY(ua, side .. "ElbowRigAttachment")
			and math.abs(attY(ua, side .. "ShoulderRigAttachment") - attY(ua, side .. "ElbowRigAttachment")) or ua.Y * ARM_BOX.upper
		local lower = attY(la, side .. "ElbowRigAttachment") and attY(la, side .. "WristRigAttachment")
			and math.abs(attY(la, side .. "ElbowRigAttachment") - attY(la, side .. "WristRigAttachment")) or la.Y * ARM_BOX.lower
		local gl = glove and glove.Y * 0.95 or (hand and hand.Y * (1 + FIST_PAST_HAND) or UNIT.gloveLen * F.hScale)
		local chain = upper + lower + gl
		local hanging = pivot - face
		-- the hanging measure when the arm really hangs (a rig caught mid-pose reads short or long: the chain then)
		F.arm = (hanging > chain * 0.8 and hanging < chain * 1.25) and hanging or chain
		F.shoulderY = math.min(pivot - sole, F.chestY)
		if F.shoulderY < F.waistY then
			F.shoulderY = F.chestY - (ut and ut.Y * 0.16 or 0.3)
		end
	end
	if glove then
		F.glove = math.max(glove.X, glove.Z) / 2
	elseif hand then
		F.glove = math.max(hand.X, hand.Z) * 0.75
	end
	-- sanity: a rig whose numbers make no sense keeps the fallback (and says why)
	local bad = HitGeometry.Invalid(F)
	if bad then
		return giveUp("rig reads " .. bad)
	end
	return F
end

-- one line on a frame for a log / a diagnostic
function HitGeometry.Describe(F)
	if type(F) ~= "table" then
		return "none"
	end
	return string.format("%s stand %.2f shoulder %.2f arm %.2f glove %.2f head %.2f/%.2f chest %.2f waist %.2f torso %.2fx%.2f",
		tostring(F.source), num(F.stand, 0), num(F.shoulderY, 0), num(F.arm, 0), num(F.glove, 0), num(F.headY, 0), num(F.headR, 0),
		num(F.chestY, 0), num(F.waistY, 0), num(F.torsoHalfW, 0), num(F.torsoHalfD, 0))
end

------------------------------------------------------------------------
-- The punch
------------------------------------------------------------------------
-- the reach R of A's punch (shoulder pivot to the glove's face along the punch's line) before the height shaping:
-- (arm + glove + the step) x the punch's calibration
local CAL = {} -- ptype -> { head = multiplier, body = multiplier } (solved below)
local function reachOf(A, ptype, zone, mul)
	local c = CAL[ptype]
	return (A.arm + A.glove + STEP * A.hScale) * (c and c[zone] or 1) * (mul or 1)
end

-- A's punch at B: the zones B offers, from A's shoulder (heights above B's soles are A's: both stand on the
-- same canvas). bendB 0..1 lowers B's head and chest; dipA (a body shot) lowers A's origin.
-- opts: { mul (a special's range multiplier), bend (B's 0..1), floor (the fight's close floor, root to root),
-- noRedirect (a head shot never falls to the body) }
-- Returns { ok, zone ("head" | "body"), why ("short" | "high" | "low"), need (the distance the glove had to
-- cover), reach (R + tol), margin = reach - need, dy }
local function zoneBand(B, zone, bend)
	local drop = BEND_DROP * B.stand * math.clamp(bend or 0, 0, 1)
	if zone == "head" then
		local c = B.headY - drop
		return c - B.headR, c + B.headR, B.headR
	end
	return B.waistY, B.chestY - drop, B.torsoHalfD
end

local function tryZone(A, B, kind, K, ptype, zone, dist, opts)
	local lo, hi, front = zoneBand(B, zone, opts.bend)
	local dip = opts.body and K.dip * A.arm or 0
	local oY = A.shoulderY + K.o * A.arm - dip
	-- the horizontal distance the glove must cover: root to root, less the zone's front (the shoulder stands
	-- over the root). Inside the fight's floor (FightMotion.Spacing.min: as close as the bodies get, every punch
	-- reaches) only the height decides
	local floor = num(opts.floor, 0)
	local h = math.max(0, dist - front)
	local hAng = math.max(h, floor - front, 1.2)
	local hReach = dist <= floor and 0 or h
	-- the heights the punch can be at out there (its angles), against the zone's band
	local pLo, pHi = oY - hAng * math.tan(math.rad(K.down)), oY + hAng * math.tan(math.rad(K.up))
	local bLo, bHi = math.max(lo, pLo), math.min(hi, pHi)
	if bLo > bHi then
		return { ok = false, zone = zone, why = (lo > pHi) and "high" or "low", need = math.huge, reach = 0, margin = -math.huge, dy = (lo > pHi) and (lo - oY) or (hi - oY) }
	end
	-- the point of the zone nearest the punch's own height (a tall man's chin, a short man's forehead)
	local y = math.clamp(oY, bLo, bHi)
	local dy = y - oY
	-- the reach: out, the calibrated R; up and down, the arm (an ellipse about the origin)
	local Rh = reachOf(A, ptype, zone, opts.mul)
	local armR = (A.arm + A.glove) * (opts.mul or 1)
	local Rv
	if dy >= 0 then
		Rv = armR * K.vUp + K.rise * A.hScale
	else
		Rv = K.vDown < 0 and math.max(Rh, armR) or armR * K.vDown
	end
	local tol = TOL * (A.glove + front)
	local norm = math.sqrt((hReach / Rh) ^ 2 + (dy / Rv) ^ 2)
	local limit = 1 + tol / Rh
	-- (need / reach in studs along the glove's line, for the read-outs)
	local need = math.sqrt(hReach * hReach + dy * dy)
	local reach = norm > 1e-6 and need * limit / norm or Rh + tol
	return { ok = norm <= limit, zone = zone, why = norm > limit and "short" or nil, need = need, reach = reach, margin = reach - need, dy = dy }
end

function HitGeometry.Test(A, B, ptype, body, dist, opts)
	opts = opts or {}
	local kind = PUNCH_KIND[ptype] or "straight"
	local K = KIND[kind]
	local o = { mul = opts.mul, bend = opts.bend, floor = opts.floor, body = body == true }
	local want = body and "body" or "head"
	local r = tryZone(A, B, kind, K, ptype, want, dist, o)
	if r.ok or body or opts.noRedirect then
		return r
	end
	-- a head shot that cannot get up there (a much taller man, out at range) lands on the body when the
	-- glove reaches that far: the punch is thrown, it just lands low
	if r.why == "high" or (r.why == "short" and r.dy > 0.3) then
		local b = tryZone(A, B, kind, K, ptype, "body", dist, o)
		if b.ok then
			b.redirected = true
			return b
		end
	end
	return r
end

-- the root-to-root distance out to which A's punch lands on B's zone itself (level stances, no falling to the
-- body): the far edge of where Test says yes (a sweep out, then a bisection: up close a tall man's straight can
-- be "low" on a short head before it is in range further out)
function HitGeometry.Range(A, B, ptype, body, opts)
	local o = table.clone(opts or {})
	o.noRedirect = true
	local lastOk, firstBad = nil, nil
	local d = 0.5
	while d <= 12 do
		if HitGeometry.Test(A, B, ptype, body, d, o).ok then
			lastOk = d
		elseif lastOk then
			firstBad = d
			break
		end
		d += 0.25
	end
	if not lastOk then
		return 0
	end
	if not firstBad then
		return lastOk
	end
	local lo, hi = lastOk, firstBad
	for _ = 1, 22 do
		local mid = (lo + hi) / 2
		if HitGeometry.Test(A, B, ptype, body, mid, o).ok then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

-- the root-to-root distance out to which A's punch LANDS on B at all: on the head, or - where the head is out of
-- its angles and the glove still gets there - on the body, as Test lets a head shot fall (an overhand never falls:
-- FightEngine's HitTest runs it noRedirect). This is the reach the fight gates a punch on (FightEngine:PunchRange,
-- FightAI's "in range"): a short man's jab at a tall head is thrown from where it lands low, not refused
function HitGeometry.Reach(A, B, ptype, opts)
	local head = HitGeometry.Range(A, B, ptype, false, opts)
	if ptype == "overhand" or (opts and opts.headOnly) then
		return head
	end
	return math.max(head, HitGeometry.Range(A, B, ptype, true, opts))
end

------------------------------------------------------------------------
-- Bodies: separation and the clinch
------------------------------------------------------------------------
-- centre-to-centre spacing two bodies need so chests and the gloves held up in front of them never sink into each
-- other: both torsos' half depths, both pairs of gloves, and a little air that grows with the pair (the unit pair
-- gives FightMotion.Spacing.minSep). Never so far apart that either man's jab cannot land from there: the pair's
-- shorter jab reach (head or body) less SEP_REACH, down to the bodies' own minimum (torsos and gloves touching).
-- A 60-inch heavyweight against an 84-inch man otherwise stood where neither jab reached (his separation 4.05, his
-- jab 4.0): the AI never saw itself in range
local SEP_GLOVE, SEP_AIR = 1.6, 1.256
local SEP_REACH = 0.35
HitGeometry.SEP_REACH = SEP_REACH
function HitGeometry.MinSepRaw(A, B)
	return A.torsoHalfD + B.torsoHalfD + SEP_GLOVE * (A.glove + B.glove) + SEP_AIR * (A.hScale + B.hScale) / 2
end
function HitGeometry.MinSep(A, B)
	local raw = HitGeometry.MinSepRaw(A, B)
	local reach = math.min(HitGeometry.Reach(A, B, "jab"), HitGeometry.Reach(B, A, "jab"))
	local bodies = A.torsoHalfD + B.torsoHalfD + 2 * (A.glove + B.glove) + 0.1
	local sep = math.min(raw, reach - SEP_REACH)
	if sep ~= sep or sep == math.huge or sep == -math.huge then
		sep = raw
	end
	return math.max(bodies, sep)
end

-- how far out A can tie B up: A's arm and glove wrap past B's chest, plus the step in (the unit pair gives
-- FightMotion.Spacing.clinch)
local CLINCH_STEP = 1.417
function HitGeometry.ClinchRange(A, B)
	return A.arm + A.glove + B.torsoHalfD + CLINCH_STEP * A.hScale
end

-- the height edge, studs (A over B; negative = A is the shorter man)
function HitGeometry.HeightEdge(A, B)
	return A.stand - B.stand
end

-- what the pair favours: the longer man's straights, the shorter man's uppercuts and hooks inside (FightAI's punch
-- weights): ptype -> multiplier around 1
function HitGeometry.PunchPrefs(A, B)
	local edge = HitGeometry.HeightEdge(A, B)
	local reach = (A.arm + A.glove) - (B.arm + B.glove)
	local long = math.clamp(edge / 1.2 + reach / 0.6, -1, 1)
	local p = { jab = 1, cross = 1, leadhook = 1, rearhook = 1, uppercut = 1, overhand = 1 }
	if long > 0 then
		p.jab = 1 + 0.25 * long
		p.cross = 1 + 0.15 * long
		p.overhand = 1 + 0.1 * long
		p.uppercut = 1 - 0.2 * long
	elseif long < 0 then
		local s = -long
		p.uppercut = 1 + 0.3 * s
		p.leadhook = 1 + 0.12 * s
		p.rearhook = 1 + 0.12 * s
		p.jab = 1 - 0.15 * s
		p.overhand = 1 - 0.1 * s
	end
	return p, long
end

------------------------------------------------------------------------
-- Calibration: the unit rig against itself lands every punch at exactly TARGET[p][zone] (where the animation's
-- glove visibly lands) with a level stance, to the head and to the body alike
------------------------------------------------------------------------
do
	local U = HitGeometry.Unit()
	for p in pairs(RANGE) do
		CAL[p] = { head = 1, body = 1 }
		for _, zone in ipairs({ "head", "body" }) do
			local target = TARGET[p][zone]
			local lo, hi = 0.2, 4
			for _ = 1, 40 do
				local mid = (lo + hi) / 2
				CAL[p][zone] = mid
				if HitGeometry.Test(U, U, p, zone == "body", target, { noRedirect = true }).ok then
					hi = mid
				else
					lo = mid
				end
			end
			CAL[p][zone] = hi
		end
	end
end
HitGeometry.CAL = CAL

return HitGeometry
