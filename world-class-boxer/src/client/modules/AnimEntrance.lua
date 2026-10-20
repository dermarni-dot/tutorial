-- AnimEntrance: the ring walk's body language on the client - the entrance celebrations, the climb up the ring
-- steps, the duck through the ropes, the turnbuckle salute, the robe shrug and the ride on the crowd's shoulders.
-- Shared.Entrance holds the plan and the beats; BoxerClient.EntranceFX starts a walk here (AnimEntrance.Start) and
-- the Animator applies it at its output (AnimEntrance.output: one hook line, after the filters, before the motors):
--   * a gesture owns some joints (the arms, the neck...) and is blended over the Animator's pose by its envelope
--   * a keyed state (climb, duck, turnbuckle, lap, carried, setdown) owns the legs and the root as well, and may
--     draw the body somewhere other than the HumanoidRootPart (a world path: up the steps, through the ropes, onto
--     the ropes) - a visual offset on the Root joint only. The server's fighter never moves for it.
-- Everything is a pure function of the time since the walk's message (os.clock), so every client draws the same
-- walk and a late frame never drifts. Joint conventions are the Animator's (AnimFight): shoulder A(pitch up/forward,
-- yaw, roll: - left / + right = out to the side), elbow A(+bend), waist / neck A(+ back / up), hip A(+ thigh
-- forward), knee A(- bend), ankle A(+).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Entrance = require(Shared:WaitForChild("Entrance"))

local AnimEntrance = {}
AnimEntrance.active = {} -- [model] = state (EntranceFX writes, the Animator reads)

local A = CFrame.Angles
local CF = CFrame.new
local V3 = Vector3.new
local sin, cos, abs, max, min, floor, PI = math.sin, math.cos, math.abs, math.max, math.min, math.floor, math.pi
local clamp = math.clamp

local function smooth(x)
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
-- 0 -> 1 over [a, a + rise], 1 -> 0 over [b - fall, b]
local function env(u, a, b, rise, fall)
	return smooth((u - a) / rise) * (1 - smooth((u - (b - fall)) / fall))
end
local function bump(u, a, b)
	if u <= a or u >= b then
		return 0
	end
	return sin((u - a) / (b - a) * PI)
end
AnimEntrance.smooth, AnimEntrance.env, AnimEntrance.bump = smooth, env, bump

local ARMS = { "LS", "LE", "LW", "RS", "RE", "RW" }
local LEGS = { "LH", "LK", "LA", "RH", "RK", "RA" }

------------------------------------------------------------------------
-- Gestures: Gesture(id, u, dur, q) fills q (joint -> Transform) and returns the joint weight table
------------------------------------------------------------------------
local G = {}
-- each returns the set of joints it owns: { key = weight }
G.fistpump = function(u, q)
	local pump = abs(sin(u * 5.5)) * smooth((u - 0.35) / 0.2)
	q.RS = A(2.75 - 0.25 * pump, 0, 0.18)
	q.RE = A(0.2 + 0.6 * pump, 0, 0)
	q.Neck = A(0.22, 0.12, 0)
	return { RS = 1, RE = 1, Neck = 0.6 }
end
G.point = function(u, q)
	local sweep = sin(u * 1.5)
	q.RS = A(1.75, 0.15 * sweep, 0.3 + 0.35 * sweep)
	q.RE = A(0.1, 0, 0)
	q.LS = A(0.45, 0, -0.18)
	q.LE = A(1.2, 0, 0)
	q.Neck = A(0.12, -0.35 * sweep, 0)
	q.W = A(0, -0.12 * sweep, 0)
	return { RS = 1, RE = 1, LS = 0.6, LE = 0.6, Neck = 0.8, W = 0.6 }
end
G.shadowbox = function(u, q)
	local cyc = 0.28
	local n = floor(u / cyc)
	local f = (u - n * cyc) / cyc
	local ext = bump(f, 0, 0.85)
	local left = n % 2 == 0
	local gs, ge = A(1.3, 0, 0.32), A(2.15, 0, 0)
	q.LS, q.LE = gs, ge
	q.RS, q.RE = A(1.3, 0, -0.32), ge
	if left then
		q.LS = gs:Lerp(A(1.6, 0, 0.04), ext)
		q.LE = ge:Lerp(A(0.12, 0, 0), ext)
	else
		q.RS = A(1.3, 0, -0.32):Lerp(A(1.6, 0, -0.04), ext)
		q.RE = ge:Lerp(A(0.12, 0, 0), ext)
	end
	q.W = A(-0.06, (left and -0.18 or 0.18) * ext, 0)
	q.Neck = A(-0.1, 0, 0)
	return { LS = 1, LE = 1, RS = 1, RE = 1, W = 0.8, Neck = 0.6 }
end
G.chestbeat = function(u, q)
	local bl = abs(sin(u * 6.5))
	local br = abs(sin(u * 6.5 + PI / 2))
	q.LS = A(0.95 + 0.25 * bl, 0, 0.5)
	q.RS = A(0.95 + 0.25 * br, 0, -0.5)
	q.LE = A(2.2 - 0.25 * bl, 0, 0)
	q.RE = A(2.2 - 0.25 * br, 0, 0)
	q.W = A(0.1 + 0.04 * (bl + br), 0, 0)
	q.Neck = A(0.18, 0, 0)
	return { LS = 1, LE = 1, RS = 1, RE = 1, W = 0.8, Neck = 0.7 }
end
G.bow = function(u, q, dur)
	local b = bump(u, 0.35, dur - 0.15)
	q.LS = A(1.25, 0, 0.42)
	q.RS = A(1.25, 0, -0.42)
	q.LE = A(1.35, 0, 0)
	q.RE = A(1.35, 0, 0)
	q.W = A(-0.5 * b, 0, 0)
	q.Neck = A(-0.3 * b, 0, 0)
	return { LS = 1, LE = 1, RS = 1, RE = 1, W = 1, Neck = 1 }
end
G.shakeout = function(u, q)
	q.LS = A(0.15 + 0.12 * sin(u * 23), 0, -0.22)
	q.RS = A(0.15 + 0.12 * sin(u * 21 + 1), 0, 0.22)
	q.LE = A(0.25 + 0.2 * sin(u * 19), 0, 0)
	q.RE = A(0.25 + 0.2 * sin(u * 17 + 2), 0, 0)
	q.Neck = A(0.05, 0, 0.2 * sin(u * 3))
	-- the hop: the whole body off the floor (applied to the root by output)
	q.hop = 0.2 * abs(sin(u * 7))
	return { LS = 1, LE = 1, RS = 1, RE = 1, Neck = 0.7 }
end
G.comeatme = function(u, q)
	local flick = max(0, sin(u * 6))
	q.LS = A(0.55, 0, -1.15)
	q.RS = A(0.55, 0, 1.15)
	q.LE = A(0.35 + 0.4 * flick, 0, 0)
	q.RE = A(0.35 + 0.4 * flick, 0, 0)
	q.W = A(0.16, 0, 0)
	q.Neck = A(0.18, 0, 0.15)
	return { LS = 1, LE = 1, RS = 1, RE = 1, W = 0.8, Neck = 0.8 }
end
G.beltlift = function(u, q)
	local pump = 0.08 * sin(u * 4)
	q.LS = A(2.72 + pump, 0, -0.42)
	q.RS = A(2.72 + pump, 0, 0.42)
	q.LE = A(0.45, 0, 0)
	q.RE = A(0.45, 0, 0)
	q.Neck = A(0.32, 0, 0)
	q.W = A(0.08, 0, 0)
	q.belt = true
	return { LS = 1, LE = 1, RS = 1, RE = 1, Neck = 0.8, W = 0.6 }
end
G.stare = function(_u, q)
	-- gloves low, shoulders forward, the head locked on the ring (the walk's nod taken out)
	q.LS = A(0.12, 0, -0.1)
	q.RS = A(0.12, 0, 0.1)
	q.LE = A(1.0, 0, 0)
	q.RE = A(1.0, 0, 0)
	q.W = A(-0.08, 0, 0)
	q.Neck = A(-0.14, 0, 0)
	return { LS = 0.8, LE = 0.8, RS = 0.8, RE = 0.8, W = 0.7, Neck = 1 }
end
G.turnitup = function(u, q)
	local s = sin(u * 6) * 0.5 + 0.5
	q.LS = A(2.0 + 0.45 * s, 0, -0.75)
	q.RS = A(2.0 + 0.45 * s, 0, 0.75)
	q.LE = A(1.2 - 0.6 * s, 0, 0)
	q.RE = A(1.2 - 0.6 * s, 0, 0)
	q.Neck = A(0.3, 0, 0)
	return { LS = 1, LE = 1, RS = 1, RE = 1, Neck = 0.8 }
end
-- (victorylap and turnbuckle are keyed states below; their arms are drawn there)
G.victorylap = function(u, q)
	q.RS = A(2.8, 0, 0.2)
	q.RE = A(0.25, 0, 0)
	q.LS = A(0.4 * sin(u * 9), 0, -0.12)
	q.LE = A(1.4, 0, 0)
	q.Neck = A(0.15, 0, 0)
	return { RS = 1, RE = 1, LS = 1, LE = 1, Neck = 0.7 }
end
G.turnbuckle = function(u, q)
	local pump = abs(sin(u * 4.5)) * 0.3
	q.LS = A(2.85 - pump, 0, -0.5)
	q.RS = A(2.85 - pump, 0, 0.5)
	q.LE = A(0.3 + pump, 0, 0)
	q.RE = A(0.3 + pump, 0, 0)
	q.Neck = A(0.35, 0, 0)
	q.W = A(0.12, 0, 0)
	return { LS = 1, LE = 1, RS = 1, RE = 1, Neck = 0.8, W = 0.6 }
end
AnimEntrance.Gestures = G

-- one gesture at u s of dur: q, owned joints, envelope weight (the GIF tools call this directly)
function AnimEntrance.Gesture(id, u, dur, q)
	local fn = G[id] or G.fistpump
	q = q or {}
	local own = fn(u, q, dur)
	return q, own, env(u, 0, dur, 0.3, 0.35)
end

------------------------------------------------------------------------
-- Keyed states
------------------------------------------------------------------------
local function stand(q)
	q.LH, q.LK, q.LA = A(0.05, 0, 0), A(-0.1, 0, 0), A(0.05, 0, 0)
	q.RH, q.RK, q.RA = A(0.05, 0, 0), A(-0.1, 0, 0), A(0.05, 0, 0)
end

-- sitting on the carrier's shoulders: thighs over his shoulders either side of his head, shins down his chest
local function seat(q, u)
	local sway = 0.05 * sin(u * 4.2)
	q.Root = A(0.12, 0, sway)
	q.W = A(0.04, 0, -sway * 0.6)
	q.LH, q.RH = A(1.35, 0.1, -0.32), A(1.35, -0.1, 0.32)
	q.LK, q.RK = A(-1.45, 0, 0), A(-1.45, 0, 0)
	q.LA, q.RA = A(0.35, 0, 0), A(0.35, 0, 0)
	-- the free arms while no celebration has them: a fist up for the crowd, the other on his carrier's head
	q.RS = A(2.6 - 0.2 * abs(sin(u * 3)), 0, 0.25)
	q.RE = A(0.35 + 0.3 * abs(sin(u * 3)), 0, 0)
	q.LS = A(0.55, 0, -0.35)
	q.LE = A(0.9, 0, 0)
end

-- stepping legs (climbing the steps): which = 1 / 2 the leg that lifts, s = its lift 0..1
local function climbLegs(q, ph)
	local n = floor(ph)
	local f = ph - n
	local s = sin(f * PI)
	local lead = n % 2 == 0
	local lh, lk = A(0.95 * s, 0, 0), A(-1.3 * s, 0, 0)
	stand(q)
	if lead then
		q.LH, q.LK, q.LA = lh, lk, A(0.35 * s, 0, 0)
	else
		q.RH, q.RK, q.RA = lh, lk, A(0.35 * s, 0, 0)
	end
	q.Root = CF(0, -0.08 * s, 0) * A(-0.06, 0, 0)
end

-- the jog of the champion's lap
local function jogLegs(q, ph)
	local s = sin(ph)
	q.LH, q.RH = A(0.6 * s, 0, 0), A(-0.6 * s, 0, 0)
	q.LK, q.RK = A(-(0.45 + 0.8 * max(0, -s)), 0, 0), A(-(0.45 + 0.8 * max(0, s)), 0, 0)
	q.LA, q.RA = A(0.2 * max(0, -s), 0, 0), A(0.2 * max(0, s), 0, 0)
	q.Root = CF(0, 0.07 * abs(s), 0) * A(-0.12, 0, 0)
end

------------------------------------------------------------------------
-- Geometry
------------------------------------------------------------------------
-- the boxer's standing height (HumanoidRootPart centre above the floor: FightEngine's standHeight) and the
-- carrier figures' scale and the lift that seats him on a carrier's shoulders
function AnimEntrance.Geom(model)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local hip = (hum and hum.HipHeight > 0.5) and hum.HipHeight or 2
	local stand = hip + (root and root.Size.Y / 2 or 1) + 0.05
	local k = clamp(hip / 2, 0.85, 1.35)
	local shoulder = 4.5 * k
	return { hip = hip, stand = stand, k = k, shoulder = shoulder, lift = shoulder + 0.32 - hip }
end

local function flatLook(cf)
	local l = cf.LookVector
	local f = V3(l.X, 0, l.Z)
	return f.Magnitude > 1e-3 and f.Unit or V3(0, 0, -1)
end
local function yawOf(dir)
	return math.atan2(-dir.X, -dir.Z)
end
-- the yaw (about +Y, radians) that turns a root facing `cf` to face world direction dir
local function relYaw(cf, dir)
	local d = V3(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-3 then
		return 0
	end
	local a = yawOf(d.Unit) - yawOf(flatLook(cf))
	return (a + PI) % (2 * PI) - PI
end
AnimEntrance.relYaw = relYaw

------------------------------------------------------------------------
-- The walk's state at a moment: what the body does (pure; EntranceFX reads the carry and the belt from it)
------------------------------------------------------------------------
-- st = { plan, beats, celebs, t0 }; returns frame = { beat, bt, mode, lift, world = {pos, face} | nil, gesture = {
-- id, u, dur } | nil, keyedW, hop, belt }
function AnimEntrance.Frame(st, now)
	local plan, beats = st.plan, st.beats
	local el = now - st.t0
	local beat, _, bt = Entrance.BeatAt(beats, el)
	local fr = { el = el, beat = beat and beat.id or "end", bt = bt or 0, lift = 0 }
	if not beat then
		return fr
	end
	local d = beat.t1 - beat.t0
	fr.dur = d
	-- the celebration playing now
	for _, c in ipairs(st.celebs) do
		if el >= c.t0 and el < c.t1 then
			fr.gesture = { id = c.id, u = el - c.t0, dur = c.t1 - c.t0, beat = c.beat }
		end
	end
	local pts = plan.pts or {}
	local id = beat.id
	if plan.carry and (id == "tunnel" or id == "aisle" or id == "crowd") then
		fr.mode = "carried"
		fr.lift = 1
	elseif id == "setdown" then
		fr.mode = "setdown"
		fr.lift = 1 - smooth(bt / (d * 0.8))
	elseif id == "steps" and pts.steps and pts.apron then
		fr.mode = "climb"
		fr.e = smooth(bt / d)
		fr.from, fr.to = pts.steps, pts.apron
	elseif id == "ropes" and pts.apron and pts.inside then
		fr.mode = "duck"
		fr.e = smooth(bt / d)
		fr.from, fr.to = pts.apron, pts.inside
	elseif id == "ring" then
		local g = fr.gesture
		if g and g.id == "turnbuckle" then
			fr.mode = "turnbuckle"
		elseif g and g.id == "victorylap" then
			fr.mode = "lap"
		elseif bt > Entrance.RING_WALK - 0.25 then
			fr.mode = "face" -- the corner: he turns to his fans over the ropes
		end
	elseif id == "robe" then
		fr.mode = "robe"
	end
	return fr
end

------------------------------------------------------------------------
-- Start / stop (EntranceFX)
------------------------------------------------------------------------
function AnimEntrance.Start(model, plan, t0)
	local beats, total = Entrance.Timeline(plan)
	local st = { plan = plan, beats = beats, total = total, t0 = t0 or os.clock(), celebs = Entrance.Celebrations(plan, beats) }
	AnimEntrance.active[model] = st
	return st
end

-- the parade after a big win: lifted where he stands, turned slowly round to every side of the house
function AnimEntrance.StartParade(model, t0, dur)
	local st = { parade = true, t0 = t0 or os.clock(), total = dur or 4, plan = {}, beats = {}, celebs = {} }
	AnimEntrance.active[model] = st
	return st
end

-- stop with a short fade (the pose eases back to the Animator's own)
function AnimEntrance.Stop(model, now)
	local st = AnimEntrance.active[model]
	if st and not st.fadeAt then
		st.fadeAt = now or os.clock()
	end
end

function AnimEntrance.StopAll(now)
	for m in pairs(AnimEntrance.active) do
		AnimEntrance.Stop(m, now)
	end
end

------------------------------------------------------------------------
-- The output hook (Animator: after the filters and the leg IK, before the motors)
------------------------------------------------------------------------
local FADE = 0.35
local qbuf = {}

local function blend(out, k, v, w)
	local cur = out[k]
	if cur and v and w > 0.001 then
		out[k] = w >= 0.999 and v or cur:Lerp(v, w)
	end
end

-- the ring centre of a walk's plan (the climb and the duck face it)
local function planCentre(st)
	local pts = st.plan and st.plan.pts
	return pts and pts.centre or nil
end

-- st.geom is measured once per walk (the body does not change size mid-walk)
function AnimEntrance.output(rig, model, out, _t, _dt)
	local st = AnimEntrance.active[model]
	if not st then
		return
	end
	local now = os.clock()
	local root = rig.root
	if not root then
		return
	end
	local master = 1
	if st.fadeAt then
		master = 1 - smooth((now - st.fadeAt) / FADE)
		if master <= 0 then
			AnimEntrance.active[model] = nil
			return
		end
	end
	local el = now - st.t0
	if el > st.total + 0.4 then
		AnimEntrance.active[model] = nil
		return
	elseif el > st.total then
		master *= 1 - smooth((el - st.total) / 0.35)
	end
	st.geom = st.geom or AnimEntrance.Geom(model)
	local geo = st.geom
	table.clear(qbuf)
	local q = qbuf
	local own = {}
	local rootCF = root.CFrame
	local rootOff -- world position the root is drawn at (keyed world paths)
	local faceDir -- world facing
	local lift = 0
	local hop = 0
	local keyed = false
	local keyGW = 1 -- the owned joints' weight in a keyed state (the turnbuckle's salute eases in with the climb)
	if st.parade then
		-- lifted on the spot and turned slowly round (EntranceFX moves the carriers with the same numbers)
		local e = smooth(el / 0.6) * (1 - smooth((el - (st.total - 0.6)) / 0.6))
		seat(q, el)
		keyed = true
		lift = geo.lift * e
		q.Root = A(0, el * 0.55, 0) * q.Root
		own.RS, own.RE, own.LS, own.LE = 1, 1, 1, 1
	else
		local fr = AnimEntrance.Frame(st, now)
		local g = fr.gesture
		local gw = 0
		if g then
			local own2
			_, own2, gw = AnimEntrance.Gesture(g.id, g.u, g.dur, q)
			for k, w in pairs(own2) do
				own[k] = w
			end
			hop = q.hop or 0
		end
		local m = fr.mode
		if m == "carried" or m == "setdown" then
			keyed = true
			local arms = { RS = q.RS, RE = q.RE, LS = q.LS, LE = q.LE, Neck = q.Neck, W = q.W }
			seat(q, el)
			if g then
				-- the celebration's arms over the seat
				for k, v in pairs(arms) do
					if v and own[k] then
						q[k] = q[k]:Lerp(v, gw * own[k])
					end
				end
			end
			own.RS, own.RE, own.LS, own.LE = 1, 1, 1, 1
			hop = 0
			lift = geo.lift * fr.lift
			if m == "setdown" then
				-- off the shoulders, back onto his feet: the seat unfolds into a stand as he comes down
				local s = 1 - fr.lift
				local sq = {}
				stand(sq)
				for _, k in ipairs(LEGS) do
					q[k] = q[k]:Lerp(sq[k], s)
				end
				q.Root = q.Root:Lerp(CFrame.identity, s)
				for _, k in ipairs({ "RS", "RE", "LS", "LE" }) do
					q[k] = q[k]:Lerp(A(0.2, 0, k:sub(1, 1) == "L" and -0.15 or 0.15), s * 0.7)
				end
			end
		elseif m == "climb" or m == "duck" then
			keyed = true
			gw = 1
			local from = fr.from + V3(0, geo.stand, 0)
			local to = fr.to + V3(0, geo.stand, 0)
			local e = fr.e
			local d = fr.dur or 1
			if m == "climb" then
				-- up the three steps: the rise comes in three treads
				local ph = clamp(fr.bt / d, 0, 1) * 3
				climbLegs(q, ph)
				local rise = (floor(min(ph, 2.999)) + smooth(ph - floor(min(ph, 2.999)))) / 3
				rootOff = from:Lerp(to, e)
				rootOff = V3(rootOff.X, from.Y + (to.Y - from.Y) * rise, rootOff.Z)
				q.LS, q.RS = A(0.45, 0, -0.38), A(0.45, 0, 0.38)
				q.LE, q.RE = A(0.55, 0, 0), A(0.55, 0, 0)
				q.Neck = A(-0.2, 0, 0)
			else
				-- through the ropes: bent at the waist under the top rope, a leg over the middle one, then the other
				local u = clamp(fr.bt / d, 0, 1)
				local b = bump(u, 0.05, 0.95)
				stand(q)
				local l1, l2 = bump(u, 0.15, 0.6), bump(u, 0.45, 0.9)
				q.LH, q.LK = A(0.05 + 1.3 * l1, 0, 0), A(-0.1 - 1.5 * l1, 0, 0)
				q.RH, q.RK = A(0.05 + 1.3 * l2, 0, 0), A(-0.1 - 1.5 * l2, 0, 0)
				q.Root = CF(0, -0.55 * b, 0)
				q.W = A(-0.9 * b, 0, 0)
				q.Neck = A(0.5 * b, 0, 0)
				q.LS, q.LE = A(1.1 * b, 0, -0.55 * b), A(0.6, 0, 0)
				q.RS, q.RE = A(2.3 * b, 0, 0.35 * b), A(0.35, 0, 0)
				rootOff = from:Lerp(to, e)
			end
			faceDir = (planCentre(st) or to) - from
			for _, k in ipairs({ "LS", "LE", "RS", "RE", "W", "Neck" }) do
				own[k] = 1
			end
		elseif m == "turnbuckle" then
			keyed = true
			local pts = st.plan.pts or {}
			local u = g and g.u or 0
			local dur = g and g.dur or 2
			local up = smooth(u / 0.55) * (1 - smooth((u - (dur - 0.45)) / 0.45))
			local post = pts.post and V3(pts.post.X, rootCF.Position.Y, pts.post.Z) or (rootCF.Position + flatLook(rootCF) * 3)
			local dir = post - rootCF.Position
			local dist = V3(dir.X, 0, dir.Z).Magnitude
			local dirU = dist > 0.01 and V3(dir.X, 0, dir.Z).Unit or flatLook(rootCF)
			faceDir = dirU
			rootOff = rootCF.Position + dirU * max(0, dist - 1.25) * up + V3(0, 1.55 * up, 0)
			stand(q)
			if u < 0.55 then
				climbLegs(q, u / 0.55 * 2)
			end
			keyGW = max(gw, up)
		elseif m == "lap" then
			keyed = true
			local pts = st.plan.pts or {}
			local u = g and g.u or 0
			local dur = g and g.dur or 2.2
			local c = rootCF.Position
			local toC = pts.centre and V3(pts.centre.X - c.X, 0, pts.centre.Z - c.Z) or -flatLook(rootCF)
			toC = toC.Magnitude > 0.01 and toC.Unit or V3(0, 0, -1)
			local r = 2.0
			local mid = c + toC * r
			local a0 = math.atan2(-toC.Z, -toC.X) -- the root sits at angle a0 on the circle round mid
			local ang = a0 + smooth(u / dur) * 2 * PI
			local p = mid + V3(cos(ang), 0, sin(ang)) * r
			rootOff = p
			faceDir = V3(-sin(ang), 0, cos(ang)) -- the tangent (counter-clockwise from above)
			jogLegs(q, u * 9)
			keyGW = max(gw, env(u, 0, dur, 0.25, 0.3))
		elseif m == "face" then
			local pts = st.plan.pts or {}
			if pts.post then
				faceDir = V3(pts.post.X, 0, pts.post.Z) - V3(rootCF.Position.X, 0, rootCF.Position.Z)
			end
		elseif m == "robe" then
			local u = fr.bt
			local b = bump(u, 0.2, 1.1)
			q.LS, q.RS = A(-0.5 * b, 0, -0.35 * b), A(-0.5 * b, 0, 0.35 * b)
			q.LE, q.RE = A(0.4 * b, 0, 0), A(0.4 * b, 0, 0)
			q.W = A(0.15 * b, 0, 0)
			q.Neck = A(0.2 * b, 0, 0)
			own.LS, own.RS, own.LE, own.RE, own.W, own.Neck = 1, 1, 1, 1, 0.7, 0.7
			gw = 1
			local pts = st.plan.pts or {}
			if pts.centre then
				faceDir = V3(pts.centre.X, 0, pts.centre.Z) - V3(rootCF.Position.X, 0, rootCF.Position.Z)
			end
		end
		st.frame = fr
		if not keyed then
			-- a gesture only: its joints over the Animator's pose, the hop on the root
			local w = gw * master
			st.keyedSince = nil
			for k, wk in pairs(own) do
				blend(out, k, q[k], w * wk)
			end
			local yaw = faceDir and relYaw(rootCF, faceDir) or 0
			local fw = 0
			if m == "face" then
				fw = smooth((fr.bt - (Entrance.RING_WALK - 0.25)) / 0.4)
			elseif m == "robe" then
				fw = smooth(fr.bt / 0.3)
			end
			if (hop > 0 or abs(yaw) > 1e-3) and out.Root then
				out.Root = CF(0, hop * w, 0) * A(0, yaw * fw * master, 0) * out.Root
			end
			return
		end
	end
	-- a keyed state: legs, root and the owned joints are AnimEntrance's (eased in when it follows the Animator's own
	-- pose, straight on from another keyed state)
	if not st.keyedSince then
		st.keyedSince = now
	end
	local w = master * smooth((now - st.keyedSince) / 0.2)
	for _, k in ipairs(LEGS) do
		blend(out, k, q[k], w)
	end
	for k, wk in pairs(own) do
		blend(out, k, q[k], w * wk * keyGW)
	end
	if q.W and not own.W then
		blend(out, "W", q.W, w)
	end
	local base = q.Root or CFrame.identity
	local off = V3(0, lift + hop, 0)
	if rootOff then
		-- (the world path: the offset from where the server's root is to where the body is drawn)
		off = rootCF:PointToObjectSpace(rootOff) + V3(0, lift + hop, 0)
	end
	local yaw = faceDir and relYaw(rootCF, faceDir) or 0
	local target = CF(off) * A(0, yaw, 0) * base
	if out.Root then
		out.Root = w >= 0.999 and target or out.Root:Lerp(target, w)
	end
end

------------------------------------------------------------------------
-- The carriers (EntranceFX draws them; the numbers live here so the seat and the shoulders always agree)
------------------------------------------------------------------------
-- slots in the carried man's frame (x right, z back), k = figure scale: 1 = the carrier under him (his head between
-- the man's knees, holding his shins), then helpers at his hips and behind him (arms up to his back)
AnimEntrance.CARRY_SLOTS = {
	{ x = 0, z = -0.38, role = "base" },
	{ x = -1.45, z = 0.25, role = "side" },
	{ x = 1.45, z = 0.3, role = "side" },
	{ x = 0.15, z = 1.55, role = "back" },
}

-- carrier i's body: a world CFrame for the figure's feet (floor, facing the walk) and its arm pitches
function AnimEntrance.CarrierPose(i, rootCF, geo, floorY, phase, lift, crouch)
	local s = AnimEntrance.CARRY_SLOTS[i]
	local k = geo.k
	local look = flatLook(rootCF)
	local base = CFrame.lookAt(V3(rootCF.Position.X, floorY, rootCF.Position.Z), V3(rootCF.Position.X, floorY, rootCF.Position.Z) + look)
	local cf = base * CF(s.x * k, 0, s.z * k)
	local swing = 0.42 * sin(phase + i * 1.7)
	local armL, armR
	if s.role == "base" then
		armL, armR = 1.25, 1.25
	elseif s.role == "side" then
		armL, armR = 2.45 - 0.1 * lift, 2.45 - 0.1 * lift
	else
		armL, armR = 2.2, 2.3
	end
	return { cf = cf, swing = swing, bob = 0.06 * abs(sin(phase + i)), armL = armL, armR = armR, role = s.role, crouch = crouch or 0 }
end

return AnimEntrance
