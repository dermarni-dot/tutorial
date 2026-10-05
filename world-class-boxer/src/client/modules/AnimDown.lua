-- AnimDown: knockdowns, knockouts, the count and the get-up.
-- Driven by the attributes FightEngine sets BEFORE Guard = "down":
--   DownPose  fall shape: back | side | knee | sit | face (round 1) + flash | forward | ropes | corner |
--             standing (FightMotion.Falls)
--   KOKind    nil for a knockdown; oneshot (stiff timber fall, fencing arm) | delayed (frozen a beat,
--             then the legs go) | standing (out on his feet, held up by the referee) | crumple
--   DownDir   which way he goes (radians, body space: 0 = forward, pi = backward, + = to his left)
--   DownDist  studs to the ropes / corner post (ropes, corner)
--   Count     the referee's count (stirring from 3: head up, glove down, rolling, a knee by 8)
--   Expr      "ko" also marks an out-cold knockdown (round-1 servers)
-- Falls are key-pose timelines with gravity timing (accelerating drops, impacts with a bounce),
-- the timber fall is integrated as a rigid body pivoting on the feet, and every landing kicks the
-- reaction springs so the head and arms flop and settle like a ragdoll.
local K = require(script.Parent:WaitForChild("AnimKit"))
local R = require(script.Parent:WaitForChild("AnimRig"))

local AnimDown = {}

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local PI = math.pi
local sin, cos, abs, max, min, sqrt = math.sin, math.cos, math.abs, math.max, math.min, math.sqrt
local clamp = math.clamp
local smooth, lerp = K.smooth, K.lerp
local KEYS = R.KEYS
local num = R.num
local kick = R.kick

local G_STUDS = 30 -- real gravity in studs / s^2 (1 stud ~ 0.32 m): falls take real time

------------------------------------------------------------------------
-- Key poses (fill a pose table completely). fh = root joint height above the canvas, l2 = shin.
------------------------------------------------------------------------
local function clear(p)
	for _, k in ipairs(KEYS) do
		p[k] = I
	end
end

local function geo(rig)
	local g = rig.geo
	return g.ok and g.floorH or 3, g.ok and g.L.l2 or 1.1, g.ok and g.L.l1 or 1.1
end

-- knees give, guard drops, head goes (the first instant of every fall)
local function buckle(p, rig, back, sideways)
	clear(p)
	local fh, l2 = geo(rig)
	local drop = min(0.75, l2 * 0.55)
	p.Root = CF(0, -drop, back and 0.15 or -0.12) * A(back and 0.18 or -0.22, 0, sideways and -0.25 * sideways or 0)
	p.W = A(back and 0.12 or -0.28, 0, 0)
	p.Neck = A(back and 0.45 or -0.32, 0, 0.18)
	p.LS = A(0.45, 0, -0.35)
	p.RS = A(0.4, 0, 0.35)
	p.LE = A(0.7, 0, 0)
	p.RE = A(0.6, 0, 0)
	R.legAngles(p, drop, back and -0.05 or 0.12, rig.geo.ok and rig.geo.legLen or 2.3)
	local _ = fh
end

-- upright on both knees (on the way to the canvas, forward falls)
local function knees(p, rig)
	clear(p)
	local fh, l2 = geo(rig)
	p.Root = CF(0, -(fh - l2 - 0.45), 0.25) * A(-0.2, 0, 0)
	p.W = A(-0.25, 0, 0)
	p.Neck = A(-0.35, 0, 0.1)
	p.LS = A(0.6, 0, -0.25)
	p.RS = A(0.55, 0, 0.25)
	p.LE = A(0.5, 0, 0)
	p.RE = A(0.5, 0, 0)
	p.LH = A(0.1, 0, -0.06)
	p.RH = A(0.12, 0, 0.06)
	p.LK = A(-1.55, 0, 0)
	p.RK = A(-1.55, 0, 0)
	p.LA = A(-0.6, 0, 0)
	p.RA = A(-0.6, 0, 0)
end

-- on hands and knees, head hanging (forward knockdown)
local function handsKnees(p, rig)
	clear(p)
	local fh, l2 = geo(rig)
	p.Root = CF(0, -(fh - l2 - 0.15), -0.35) * A(-1.2, 0, 0)
	p.W = A(-0.15, 0, 0)
	p.Neck = A(-0.45, 0, 0.12)
	p.LS = A(1.3, 0, -0.12)
	p.RS = A(1.3, 0, 0.12)
	p.LE = A(0.25, 0, 0)
	p.RE = A(0.25, 0, 0)
	p.LH = A(1.25, 0, -0.08)
	p.RH = A(1.2, 0, 0.08)
	p.LK = A(-1.5, 0, 0)
	p.RK = A(-1.5, 0, 0)
	p.LA = A(-0.55, 0, 0)
	p.RA = A(-0.55, 0, 0)
end

-- face down on the canvas
local function faceDown(p, rig)
	clear(p)
	local fh = geo(rig)
	p.Root = CF(0, -(fh - 0.42), -0.9) * A(-1.5, 0.3, 0)
	p.W = A(-0.05, 0, 0)
	p.Neck = A(0.25, 1.15, 0)
	p.LS = A(2.5, 0, -0.45)
	p.LE = A(0.6, 0, 0)
	p.RS = A(0.15, 0, 0.3)
	p.RE = A(0.2, 0, 0)
	p.LH = A(-0.05, 0, -0.15)
	p.LK = A(-0.9, 0, 0)
	p.RH = A(0, 0, 0.1)
	p.RK = A(-0.2, 0, 0)
	p.LA = A(-0.5, 0, 0)
	p.RA = A(-0.5, 0, 0)
end

-- sitting on the canvas, legs out, gloves down
local function sitDown(p, rig)
	clear(p)
	local fh = geo(rig)
	p.Root = CF(0, -(fh - 0.5), 0.35) * A(0.3, 0, 0)
	p.W = A(-0.25, 0, 0)
	p.Neck = A(-0.35, 0, 0.15)
	p.LS = A(-0.55, 0, -0.28)
	p.LE = A(0.15, 0, 0)
	p.RS = A(-0.5, 0, 0.28)
	p.RE = A(0.15, 0, 0)
	p.LH = A(1.2, 0, -0.12)
	p.LK = A(-0.5, 0, 0)
	p.RH = A(1.05, 0, 0.1)
	p.RK = A(-0.95, 0, 0)
end

-- flat on the back, knees up a little, arms out
local function onBack(p, rig)
	clear(p)
	local fh = geo(rig)
	p.Root = CF(0, -(fh - 0.45), 0.9) * A(1.5, 0, 0)
	p.W = A(0, 0, 0)
	p.Neck = A(0.15, 0, 0)
	p.LS = A(0.3, 0, -1.2)
	p.LE = A(0.4, 0, 0)
	p.RS = A(0.2, 0, 1.35)
	p.RE = A(0.3, 0, 0)
	p.LH = A(0.35, 0, -0.12)
	p.LK = A(-0.75, 0, 0)
	p.LA = A(0.3, 0, 0)
	p.RH = A(0.12, 0, 0.1)
	p.RK = A(-0.25, 0, 0)
end

-- on the hip, half sitting (the middle of a side fall); s = +1 falls to his right, -1 to his left
local function hipSit(p, rig, s)
	clear(p)
	local fh = geo(rig)
	p.Root = CF(0.35 * s, -(fh - 0.6), 0.2) * A(0.2, 0, -0.55 * s)
	p.W = A(-0.1, 0, 0.25 * s)
	p.Neck = A(-0.2, 0, 0.3 * s)
	local near, far = s > 0 and "R" or "L", s > 0 and "L" or "R"
	p[near .. "S"] = A(0.3, 0, 0.6 * s)
	p[near .. "E"] = A(0.4, 0, 0)
	p[far .. "S"] = A(0.9, 0, 0.2 * s)
	p[far .. "E"] = A(1.0, 0, 0)
	p.LH = A(1.0, 0, -0.1)
	p.RH = A(0.9, 0, 0.1)
	p.LK = A(-1.2, 0, 0)
	p.RK = A(-1.0, 0, 0)
end

-- lying on the side
local function onSide(p, rig, s)
	clear(p)
	local fh = geo(rig)
	p.Root = CF(0.75 * s, -(fh - 0.55), 0.1) * A(0.15, 0, -1.45 * s)
	p.W = A(0.12, 0, 0)
	p.Neck = A(-0.15, 0, 0.35 * s)
	local near, far = s > 0 and "R" or "L", s > 0 and "L" or "R"
	p[near .. "S"] = A(1.45, 0, 0.15 * s)
	p[near .. "E"] = A(0.5, 0, 0)
	p[far .. "S"] = A(0.85, 0, 0.35 * s)
	p[far .. "E"] = A(1.25, 0, 0)
	p.LH = A(0.95, 0, 0)
	p.LK = A(-1.3, 0, 0)
	p.RH = A(0.6, 0, 0)
	p.RK = A(-1.05, 0, 0)
end

-- one knee down, a glove on the canvas, head bowed (flash knockdown / the middle of a get-up)
local function kneel(p, rig)
	clear(p)
	local fh, l2 = geo(rig)
	p.Root = CF(0, -(fh - (l2 + 0.35)), 0.1) * A(-0.12, 0, 0)
	p.W = A(-0.2, 0, 0)
	p.Neck = A(-0.45, 0, 0)
	p.LS = A(0.75, 0, -0.05)
	p.LE = A(0.2, 0, 0)
	p.RS = A(0.9, 0, -0.2)
	p.RE = A(1.5, 0, 0)
	p.LH = A(1.6, 0, 0)
	p.LK = A(-1.6, 0, 0)
	p.LA = A(0.1, 0, 0)
	p.RH = A(0.05, 0, 0)
	p.RK = A(-1.55, 0, 0)
	p.RA = A(0.6, 0, 0)
end

-- folded over the body on both knees (body-shot knockdown), one arm round the ribs
local function kneelFold(p, rig)
	clear(p)
	local fh, l2 = geo(rig)
	p.Root = CF(0, -(fh - l2 - 0.2), 0.2) * A(-0.75, 0, 0)
	p.W = A(-0.45, 0, 0.05)
	p.Neck = A(-0.3, 0, 0.1)
	p.LS = A(1.1, 0, -0.1)
	p.LE = A(0.5, 0, 0)
	p.RS = A(0.6, 0.6, -0.35)
	p.RE = A(1.9, 0, 0)
	p.LH = A(0.85, 0, -0.06)
	p.RH = A(0.8, 0, 0.06)
	p.LK = A(-1.6, 0, 0)
	p.RK = A(-1.6, 0, 0)
	p.LA = A(-0.6, 0, 0)
	p.RA = A(-0.6, 0, 0)
end

-- back against the ropes, standing / sagging (the moment he hits them)
local function onRopes(p, rig, sag)
	clear(p)
	local fh, l2 = geo(rig)
	local d = min(0.9, l2 * 0.5) * sag
	p.Root = CF(0, -0.15 - d, 0) * A(0.32 + 0.1 * sag, 0, 0)
	p.W = A(0.2, 0, 0)
	p.Neck = A(0.35 - 0.6 * sag, 0, 0.2)
	-- arms flung out along the ropes
	p.LS = A(0.2, 0, -1.25)
	p.LE = A(0.5, 0, 0)
	p.RS = A(0.25, 0, 1.25)
	p.RE = A(0.45, 0, 0)
	R.legAngles(p, 0.15 + d, -0.15, rig.geo.ok and rig.geo.legLen or 2.3)
	local _ = fh
end

-- sat down against the bottom rope, elbows hooked over it, head lolling
local function sitRopes(p, rig, corner)
	clear(p)
	local fh = geo(rig)
	p.Root = CF(0, -(fh - 0.5), 0.15) * A(0.42, 0, 0)
	p.W = A(0.15, 0, 0)
	p.Neck = A(-0.25, 0, 0.3)
	local out = corner and 1.25 or 0.95
	p.LS = A(-0.45, 0, -out)
	p.LE = A(1.25, 0, 0)
	p.RS = A(-0.4, 0, out)
	p.RE = A(1.2, 0, 0)
	p.LH = A(1.15, 0, -0.18)
	p.LK = A(-0.75, 0, 0)
	p.RH = A(1.25, 0, 0.12)
	p.RK = A(-1.05, 0, 0)
	p.LA = A(0.2, 0, 0)
end

-- out on his feet: knees bent, arms hanging, head down
local function slump(p, rig, t, ns)
	clear(p)
	local sw = K.noise1(t * 0.7, ns)
	local sz = K.noise1(t * 0.55 + 4, ns + 1)
	p.Root = CF(0.12 * sw, -0.35, 0.08 * sz) * A(-0.08 + 0.05 * sz, 0, 0.07 * sw)
	p.W = A(-0.25, 0, 0.06 * sw)
	p.Neck = A(-0.55, 0.1 * sw, 0.25 * sz)
	p.LS = A(0.15, 0, -0.08)
	p.RS = A(0.12, 0, 0.08)
	p.LE = A(0.35, 0, 0)
	p.RE = A(0.3, 0, 0)
	R.legAngles(p, 0.35, 0.1, rig.geo.ok and rig.geo.legLen or 2.3)
end

------------------------------------------------------------------------
-- Timelines: { time, builder, ease into this key, impact? }
------------------------------------------------------------------------
local GRAV, OUT, SMOOTH = "grav", "out", "smooth"
local FALLS = {
	flash = { { 0.14, "buckle", OUT }, { 0.42, "kneel", GRAV, true } },
	sit = { { 0.16, "buckle", OUT }, { 0.5, "sit", GRAV, true } },
	knee = { { 0.25, "buckleF", SMOOTH }, { 0.62, "kneel", GRAV, true }, { 1.15, "kneelFold", SMOOTH } },
	forward = { { 0.15, "buckleF", OUT }, { 0.45, "knees", GRAV, true }, { 0.75, "handsKnees", GRAV, true } },
	face = { { 0.15, "buckleF", OUT }, { 0.45, "knees", GRAV, true }, { 0.82, "faceDown", GRAV, true } },
	back = { { 0.16, "buckle", OUT }, { 0.5, "sit", GRAV, true }, { 0.86, "onBack", GRAV, true } },
	side = { { 0.18, "buckleS", OUT }, { 0.55, "hipSit", GRAV, true }, { 0.92, "onSide", GRAV, true } },
	ropes = { { 0.42, "ropesHit", SMOOTH, true }, { 0.7, "ropesSag", SMOOTH }, { 1.3, "sitRopes", GRAV, true } },
	corner = { { 0.42, "ropesHit", SMOOTH, true }, { 0.7, "ropesSag", SMOOTH }, { 1.3, "sitCorner", GRAV, true } },
}
FALLS.standing = FALLS.knee -- unknown use of "standing" without a KO: treat as a sagging knee

local function build(name, p, rig, d, t)
	local s = d.side
	if name == "buckle" then
		buckle(p, rig, true)
	elseif name == "buckleF" then
		buckle(p, rig, false)
	elseif name == "buckleS" then
		buckle(p, rig, false, s)
	elseif name == "kneel" then
		kneel(p, rig)
	elseif name == "kneelFold" then
		kneelFold(p, rig)
	elseif name == "knees" then
		knees(p, rig)
	elseif name == "handsKnees" then
		handsKnees(p, rig)
	elseif name == "faceDown" then
		faceDown(p, rig)
	elseif name == "sit" then
		sitDown(p, rig)
	elseif name == "onBack" then
		onBack(p, rig)
	elseif name == "hipSit" then
		hipSit(p, rig, s)
	elseif name == "onSide" then
		onSide(p, rig, s)
	elseif name == "ropesHit" then
		onRopes(p, rig, 0)
	elseif name == "ropesSag" then
		onRopes(p, rig, 0.6)
	elseif name == "sitRopes" then
		sitRopes(p, rig, false)
	elseif name == "sitCorner" then
		sitRopes(p, rig, true)
	elseif name == "slump" then
		slump(p, rig, t, d.ns)
	else
		onBack(p, rig)
	end
end

------------------------------------------------------------------------
-- Start / evaluate
------------------------------------------------------------------------
local VALID = { back = true, side = true, knee = true, sit = true, face = true, flash = true, forward = true, ropes = true, corner = true, standing = true }

function AnimDown.start(rig, t)
	local a = rig.a
	local pose = VALID[a.DownPose] and a.DownPose or "back"
	local ko = a.KOKind
	if type(ko) ~= "string" then
		ko = (a.Expr == "ko") and "crumple" or nil
	end
	local dir = num(a.DownDir, pose == "face" and 0 or PI)
	local d = {
		pose = pose, ko = ko, dir = dir, dist = num(a.DownDist, 1.5), t0 = t, ns = rig.persona and rig.persona.ns or 1,
		side = pose == "side" and (dir > 0 and -1 or 1) or (rig.rng:NextNumber() < 0.5 and -1 or 1),
		impacts = {}, from = {}, theta = 0, omega = 0, landed = false, fence = rig.rng:NextNumber() < 0.5 and "L" or "R",
		delay = 0,
	}
	-- the pose the fall starts from (whatever he was doing)
	for _, k in ipairs(KEYS) do
		local j = rig.joints[k]
		d.from[k] = j and j.cur or I
	end
	if ko == "oneshot" then
		-- a stiff timber fall: backwards unless he was caught going forward
		d.timber = (pose == "face" or pose == "forward") and -1 or 1
		d.theta = 0.08 * d.timber
		d.omega = (0.9 + rig.rng:NextNumber() * 0.4) * d.timber
	elseif ko == "delayed" then
		d.delay = 0.55 + rig.rng:NextNumber() * 0.45
	end
	-- the fall direction relative to the authored one (authored falls go back / forward / to a side)
	local auth = (pose == "face" or pose == "forward" or pose == "knee" or pose == "flash") and 0 or PI
	if pose == "side" then
		auth = d.side > 0 and -PI / 2 or PI / 2
	end
	local yaw = K.wrap(dir - auth)
	if pose == "ropes" or pose == "corner" then
		d.yaw = yaw -- turns his back to the ropes as he staggers
	else
		d.yaw = clamp(yaw, -0.6, 0.6) -- a little variety, never a different fall
	end
	rig.down = d
	-- the dramatic moment: the client slows the knockout down for a beat (both men)
	if ko and ko ~= "standing" then
		rig.slowFrom = t
		rig.model:SetAttribute("KOMoment", os.clock())
		local opp = rig.oppRig
		if opp then
			opp.slowFrom = t
		end
	end
	return d
end

-- time scale of a slowed-down knockout moment (1 = real time)
function AnimDown.timeScale(rig, t)
	local s = rig.slowFrom
	if not s then
		return 1
	end
	local el = t - s
	if el < 0 then
		return 1
	end
	if el > 1.05 then
		rig.slowFrom = nil
		return 1
	end
	-- ease into slow motion, hold, ease back out (in this rig's own clock)
	if el < 0.08 then
		return lerp(1, 0.35, smooth(el / 0.08))
	elseif el < 0.75 then
		return 0.35
	end
	return lerp(0.35, 1, smooth((el - 0.75) / 0.3))
end

local function easeOf(kind, u)
	if kind == GRAV then
		return u * u -- falling: accelerates into the impact
	elseif kind == OUT then
		return K.easeOut(u)
	end
	return smooth(u)
end

-- impacts kick the springs: the head and arms flop and settle (ragdoll-like)
local function impact(rig, d, strength, name)
	local s = strength * (d.ko and 1.25 or 0.8)
	local r = rig.rng
	kick(rig, (r:NextNumber() - 0.3) * 6 * s, (r:NextNumber() - 0.5) * 3 * s, (r:NextNumber() - 0.5) * 4 * s,
		(r:NextNumber() - 0.5) * 2 * s, 0, (r:NextNumber() - 0.5) * 2 * s, 0, 0, -0.6 * s, 0,
		(r:NextNumber() - 0.5) * 5 * s, (r:NextNumber() - 0.5) * 5 * s, (r:NextNumber() - 0.5) * 4 * s, (r:NextNumber() - 0.5) * 4 * s)
	local FX = R.FX
	if FX.HairFX then
		FX.HairFX.Impulse(rig.model, 0, 0.6, 0.6 * strength)
	end
	if FX.BodyFX then
		FX.BodyFX.Jiggle(rig.model, "all", 0.4 * strength)
	end
	local _ = name
end

-- evaluate a timeline into p (from the captured pose at el = 0)
local function timeline(p, rig, d, keys, el, t)
	local prevT, prevName = 0, nil
	for i, key in ipairs(keys) do
		local kt = key[1] * (d.speed or 1)
		if el < kt then
			local u = (el - prevT) / max(1e-3, kt - prevT)
			local e = easeOf(key[3], clamp(u, 0, 1))
			if prevName then
				build(prevName, rig.kp, rig, d, t)
			else
				for _, k in ipairs(KEYS) do
					rig.kp[k] = d.from[k]
				end
			end
			build(key[2], rig.kp2, rig, d, t)
			for _, k in ipairs(KEYS) do
				p[k] = rig.kp[k]:Lerp(rig.kp2[k], e)
			end
			return i
		end
		-- passed this key: an impact fires once
		if key[4] and not d.impacts[i] then
			d.impacts[i] = true
			impact(rig, d, i == #keys and 1 or 0.6, key[2])
		end
		prevT, prevName = kt, key[2]
	end
	build(prevName or "onBack", p, rig, d, t)
	return #keys + 1
end

-- the stiff one-punch fall: a rigid body pivoting on its feet (theta'' = 3g / 2L sin theta)
local function timber(p, rig, d, dt, t)
	local fh = geo(rig)
	local Lb = fh * 1.9
	if not d.landed then
		local n = 4
		local h = dt / n
		for _ = 1, n do
			local acc = 1.5 * G_STUDS / Lb * sin(d.theta)
			d.omega += acc * h
			d.theta += d.omega * h
		end
		local lim = d.timber > 0 and 1.42 or -1.42
		if (d.timber > 0 and d.theta >= lim) or (d.timber < 0 and d.theta <= lim) then
			-- the canvas: a bounce, then he lies still
			d.theta = lim
			d.landed = true
			d.landT = t
			impact(rig, d, 1.3, "timber")
		end
	end
	local th = d.theta
	if d.landed then
		local el = t - d.landT
		-- one small rebound, settling
		th = d.theta - d.timber * 0.08 * sin(min(1, el / 0.35) * PI) * (1 - min(1, el / 0.35))
	end
	clear(p)
	-- rotate the whole body about the ground point between the feet; the pelvis lowers by the body's
	-- thickness at the end so he lies ON the canvas, not in it
	local lie = smooth(abs(th) / 1.42)
	p.Root = CF(0, -fh + 0.45 * lie * 0, 0) * A(th, 0, 0) * CF(0, fh, 0) * CF(0, -0.38 * lie, 0)
	-- stiff legs, locked knees; the arms freeze (one fencing arm up, stiff)
	p.LH = A(0.05, 0, -0.05)
	p.RH = A(0.05, 0, 0.05)
	p.LK = A(-0.05, 0, 0)
	p.RK = A(-0.05, 0, 0)
	local fenceS = d.fence
	local fe = smooth(min(1, (t - d.t0) / 0.3))
	-- after a few seconds the fencing arm slowly sinks
	local sink = d.landed and smooth((t - d.landT - 1.2) / 2.5) or 0
	local up = fenceS == "L" and "LS" or "RS"
	local other = fenceS == "L" and "RS" or "LS"
	local sgn = fenceS == "L" and -1 or 1
	p[up] = A(lerp(2.4, 0.4, sink) * fe, 0, sgn * 0.25)
	p[fenceS == "L" and "LE" or "RE"] = A(0.15, 0, 0)
	p[other] = A(0.15, 0, -sgn * lerp(0.2, 0.9, sink))
	p[fenceS == "L" and "RE" or "LE"] = A(0.5, 0, 0)
	p.Neck = A(d.timber > 0 and 0.25 or -0.2, 0, 0)
	p.W = A(0, 0, 0)
	if lie > 0.95 then
		p.Neck = p.Neck * A(0, 0.9 * (rig.koTilt or 0.3), 0.3 * (rig.koTilt or 0.3))
	end
end

-- count stirring: from 3 the head comes up and a glove goes down; by 8 he is working onto a knee
local function stir(p, rig, d, count, t)
	local k = clamp((count - 2) / 5, 0, 1)
	if k <= 0 then
		return
	end
	local pose = d.pose
	if pose == "back" then
		p.Neck = p.Neck:Lerp(A(-0.55, 0, 0), k)
		p.Root = p.Root * A(-0.35 * k, 0, -0.5 * k)
		p.LS = p.LS:Lerp(A(0.6, 0, -0.45), k)
		p.LE = p.LE:Lerp(A(1.3, 0, 0), k)
		p.LH = p.LH:Lerp(A(0.9, 0, 0), k)
		p.LK = p.LK:Lerp(A(-1.6, 0, 0), k)
	elseif pose == "face" or pose == "forward" then
		p.Root = p.Root * A(0.45 * k, 0, 0)
		p.LS = p.LS:Lerp(A(1.4, 0, -0.25), k)
		p.LE = p.LE:Lerp(A(0.6, 0, 0), k)
		p.RS = p.RS:Lerp(A(1.4, 0, 0.25), k)
		p.RE = p.RE:Lerp(A(0.6, 0, 0), k)
		p.Neck = p.Neck:Lerp(A(0.35, 0.2, 0), k)
	elseif pose == "ropes" or pose == "corner" then
		-- reaches up for the ropes to pull himself up
		p.Neck = p.Neck:Lerp(A(0.05, 0, 0), k)
		p.LS = p.LS:Lerp(A(1.2, 0, -1.0), k)
		p.RS = p.RS:Lerp(A(1.2, 0, 1.0), k)
		p.LE = p.LE:Lerp(A(1.0, 0, 0), k)
		p.RE = p.RE:Lerp(A(1.0, 0, 0), k)
	elseif pose == "side" then
		p.Root = p.Root * A(0, 0, 0.4 * k * d.side)
		p.Neck = p.Neck:Lerp(A(-0.2, 0, -0.2 * d.side), k)
	else
		p.Neck = p.Neck:Lerp(A(-0.1, 0.15 * sin(t * 2), 0), k)
		p.W = p.W * A(0.15 * k, 0, 0)
	end
end

-- the full down pose for this frame; returns true while the rig is down
function AnimDown.pose(p, rig, t, dt)
	local d = rig.down
	if not d then
		d = AnimDown.start(rig, t)
	end
	local el = t - d.t0
	rig.plant = false
	p.rate = 40
	local ko = d.ko
	if ko == "standing" then
		-- out on his feet: no fall; slumped, swaying, held up by the referee when he is there
		slump(p, rig, t, d.ns)
		local ref = rig.refRig
		if ref and ref.root and (ref.root.Position - rig.root.Position).Magnitude < 4 then
			local lp = rig.root.CFrame:PointToObjectSpace(ref.root.Position)
			local yaw = math.atan2(-lp.X, -lp.Z)
			p.Root = p.Root * A(-0.18, yaw * 0.3, 0)
			p.Neck = p.Neck * A(-0.1, yaw * 0.4, 0)
		end
		rig.exprHint = "ko"
		-- the legs keep looking for the floor
		rig.plant = true
		R.plant(rig, 0.4, 0.2, 0, -0.4, 0, 0)
		rig.stepDist = 0.2
		local blend = smooth(el / 0.6)
		for _, k in ipairs(KEYS) do
			p[k] = d.from[k]:Lerp(p[k], blend)
		end
		return true
	end
	if ko == "oneshot" then
		timber(p, rig, d, dt, t)
		local blend = smooth(el / 0.12)
		if blend < 1 then
			for _, k in ipairs(KEYS) do
				p[k] = d.from[k]:Lerp(p[k], blend)
			end
		end
	else
		local keys = FALLS[d.pose] or FALLS.back
		local start = d.delay
		if el < start then
			-- the delayed knockout: frozen where he stood, arms drifting down, eyes gone
			local k = el / max(0.1, start)
			for _, key in ipairs(KEYS) do
				p[key] = d.from[key]
			end
			p.LS = p.LS * A(-0.5 * k * k, 0, 0)
			p.RS = p.RS * A(-0.5 * k * k, 0, 0)
			p.Neck = p.Neck * A(0.12 * k, 0, 0.1 * k)
			p.Root = CF(0.03 * sin(el * 3), -0.08 * k * k, 0) * p.Root
			rig.plant = true
			rig.exprHint = "ko"
			return true
		end
		if ko then
			d.speed = 0.85 -- out cold: nothing slows the fall
		end
		local i = timeline(p, rig, d, keys, el - start, t)
		-- knockouts do not catch themselves: the forward fall goes all the way down to the face
		if ko and d.pose == "forward" and i > #keys then
			faceDown(p, rig)
		end
	end
	-- direction: the whole fall turns about the root (ropes / corner progressively, as he staggers)
	local yaw = d.yaw
	if abs(yaw) > 1e-3 then
		local k = (d.pose == "ropes" or d.pose == "corner") and smooth(el / 0.45) or 1
		p.Root = A(0, yaw * k, 0) * p.Root
	end
	-- ropes / corner: the stagger carries him back to them
	if d.pose == "ropes" or d.pose == "corner" then
		local back = clamp(d.dist - 0.75, 0, 3.5)
		local k = smooth(el / 0.45)
		local dirv = A(0, yaw, 0):VectorToWorldSpace(V3(0, 0, back * k))
		p.Root = CF(dirv) * p.Root
		-- stumbling feet on the way (keyed): quick alternating knee lifts
		if el < 0.45 then
			local s = sin(el / 0.45 * PI * 2)
			p.LH = p.LH * A(0.35 * max(0, s), 0, 0)
			p.LK = p.LK * A(-0.6 * max(0, s), 0, 0)
			p.RH = p.RH * A(0.35 * max(0, -s), 0, 0)
			p.RK = p.RK * A(-0.6 * max(0, -s), 0, 0)
		end
	end
	if ko then
		-- out cold: limp, head lolled to one side, arms wider
		local lim = smooth((el - d.delay - 0.6) / 0.6)
		if lim > 0 and ko ~= "oneshot" then
			p.Neck = p.Neck * A(0.1 * lim, 0.9 * (rig.koTilt or 0.3) * lim, 0.4 * (rig.koTilt or 0.3) * lim)
			p.LS = p.LS * A(0, 0, -0.2 * lim)
			p.RS = p.RS * A(0, 0, 0.2 * lim)
		end
		rig.exprHint = "ko"
	else
		-- breathing on the canvas, stirring with the count
		local bt = sin(t * 3) * 0.04
		p.W = p.W * A(bt, 0, 0)
		stir(p, rig, d, num(rig.a.Count, 0), t)
		if d.pose == "flash" or d.pose == "knee" then
			-- shaking it off
			if el < 2.6 then
				p.Neck = p.Neck * A(0, 0.25 * sin(el * 22) * max(0, 1 - (el - 0.6) / 1.4), 0)
			end
		end
		rig.exprHint = "dazed"
	end
	return true
end

------------------------------------------------------------------------
-- The get-up (act getup|<fall>|0|<dur>): from the canvas to one knee, then up through a squat
-- onto planted feet, blending into the live stance underneath
------------------------------------------------------------------------
function AnimDown.getup(p, rig, act, el, t)
	local u = el / act.dur
	if u >= 1 then
		return false
	end
	p.override = true -- the base pose continues from here when the get-up ends
	if not act.from then
		act.from = {}
		for _, k in ipairs(KEYS) do
			local j = rig.joints[k]
			act.from[k] = j and j.cur or I
		end
		act.stance = {}
	end
	-- the live stance underneath (Guard is no longer "down")
	local st = act.stance
	for _, k in ipairs(KEYS) do
		st[k] = p[k]
	end
	local quick = act.fall == "flash" or act.fall == "sit" or act.fall == "knee"
	local kneeAt = quick and 0.3 or 0.48
	if u < kneeAt then
		rig.plant = false
		kneel(rig.kp2, rig)
		rig.kp2.LS = A(0.9, 0, 0.1)
		rig.kp2.LE = A(1.1, 0, 0)
		rig.kp2.Neck = A(-0.15, 0, 0)
		local x = smooth(u / kneeAt)
		for _, k in ipairs(KEYS) do
			p[k] = act.from[k]:Lerp(rig.kp2[k], x)
		end
		if not quick and u > kneeAt * 0.6 then
			-- push off the canvas with a glove
			p.RS = p.RS:Lerp(A(0.6, 0, 0.2), (u - kneeAt * 0.6) / (kneeAt * 0.4))
		end
	else
		local x = smooth((u - kneeAt) / (1 - kneeAt))
		local g = rig.geo
		local kneelDrop = g.ok and (g.floorH - (g.L.l2 + 0.35)) or 1.5
		local rise = lerp(kneelDrop * 0.85, 0.25, x)
		local fx = smooth((x - 0.55) / 0.45)
		p.Root = (CF(0, -rise, 0.1 * (1 - x)) * A(-0.35 * (1 - x), -0.25 * x, 0)):Lerp(st.Root, fx)
		p.W = A(-0.3 * (1 - x), 0, 0):Lerp(st.W, fx)
		p.Neck = A(-0.2 + 0.1 * x, 0, 0):Lerp(st.Neck, fx)
		p.LS = A(lerp(0.75, 0.9, x), 0, lerp(0.15, 0.25, x)):Lerp(st.LS, fx)
		p.LE = A(lerp(1.1, 1.75, x), 0, 0):Lerp(st.LE, fx)
		p.RS = A(lerp(0.9, 0.75, x), 0, lerp(-0.2, -0.3, x)):Lerp(st.RS, fx)
		p.RE = A(lerp(1.5, 2.05, x), 0, 0):Lerp(st.RE, fx)
		R.plant(rig, 0.9, 0.08, -0.2, -0.7, 0, 0.1)
		R.flex(rig, "quads", 0.9 * (1 - x))
		R.flex(rig, "glutes", 0.8 * (1 - x))
		rig.exprHint = "effort"
	end
	return true
end

function AnimDown.clear(rig)
	rig.down = nil
end

return AnimDown
