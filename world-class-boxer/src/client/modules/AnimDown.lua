-- AnimDown: knockdowns, knockouts, the count and the get-up.
-- Driven by the attributes FightEngine sets BEFORE Guard = "down":
--   DownPose  fall shape: back | side | knee | sit | face (round 1) + flash | forward | ropes | corner |
--             standing (FightMotion.Falls)
--   KOKind    nil for a knockdown; oneshot (stiff timber fall, fencing arm) | delayed (out on his feet
--             for a beat, then the legs go) | standing (out on his feet, held up by the referee) |
--             crumple (folds where he stands; crumple + back = the backward collapse)
--   DownDir   which way he goes (radians, body space: 0 = forward, pi = backward, + = to his left);
--             ropes / corner: the way his back turns to the ropes / the post
--   DownDist  ropes / corner: how far the server walks his root into the ropes while he staggers
--   Count     the referee's count (stirring from 3: head up, glove down, rolling, a knee by 8)
--   Expr      "ko" also marks an out-cold knockdown (round-1 servers)
-- Falls are key-pose timelines with gravity timing (accelerating drops, impacts with a bounce); the
-- timber fall is integrated as a rigid body pivoting on the feet. Every pose is put ON the canvas from
-- the rig's real part sizes (AnimRig.groundSolve: nothing floats, nothing sinks) and arms that would
-- go through it are laid on it (AnimRig.liftArms). Landings kick the reaction springs so the head
-- and arms flop and settle like a ragdoll. A knockout plays its moment in slow motion (a real-time
-- envelope both fighters share) and stamps the client-local KOMoment / KOLanded attributes.
-- Get-ups are staged per fall: off the back he rolls to his side, onto hands and knees, a knee, then
-- up; off the face he pushes up first; off the ropes he pulls himself up on them.
local K = require(script.Parent:WaitForChild("AnimKit"))
local R = require(script.Parent:WaitForChild("AnimRig"))
local L = require(script.Parent:WaitForChild("AnimLoco"))

local AnimDown = {}

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local PI = math.pi
local sin, abs, max, min = math.sin, math.abs, math.max, math.min
local clamp = math.clamp
local smooth, lerp = K.smooth, K.lerp
local KEYS = R.KEYS
local LEG_KEYS = R.LEG_KEYS
local num = R.num
local kick = R.kick

local G_STUDS = 30 -- real gravity in studs / s^2 (1 stud ~ 0.32 m): falls take real time
local SLOW = 0.35 -- the knockout moment's time scale
local HOLD_MAX = 0.8 -- a delayed knockout stands at most this long (wall seconds) before the legs go

------------------------------------------------------------------------
-- Key poses (fill a pose table completely). The heights are only a starting point: groundSolve
-- puts every pose on the canvas from the real part sizes. X / Z offsets of the Root move the body
-- away from the root (where it lands relative to where he stood).
------------------------------------------------------------------------
local function clear(p)
	for _, k in ipairs(KEYS) do
		p[k] = I
	end
end

local function geo(rig)
	local g = rig.geo
	return g.ok and g.floorH or 3, g.ok and g.L.l2 or 1.1, g.ok and g.legLen or 2.3
end

-- knees give, guard drops, head goes (the first instant of every fall)
local function buckle(p, rig, back, sideways)
	clear(p)
	local _, l2, len = geo(rig)
	local drop = min(0.75, l2 * 0.55)
	p.Root = CF(0, -drop, back and 0.15 or -0.12) * A(back and 0.18 or -0.22, 0, sideways and -0.25 * sideways or 0)
	p.W = A(back and 0.12 or -0.28, 0, 0)
	p.Neck = A(back and 0.45 or -0.32, 0, 0.18)
	p.LS = A(0.45, 0, -0.35)
	p.RS = A(0.4, 0, 0.35)
	p.LE = A(0.7, 0, 0)
	p.RE = A(0.6, 0, 0)
	R.legAngles(p, drop, back and -0.05 or 0.12, len)
end

-- the backward collapse starts at the knees: straight down, arms limp, head dropping
local function kneesGo(p, rig)
	clear(p)
	local _, l2, len = geo(rig)
	local drop = min(1.25, l2 * 0.95)
	p.Root = CF(0, -drop, 0.12) * A(0.12, 0, 0.05)
	p.W = A(0.06, 0, -0.04)
	p.Neck = A(-0.42, 0.1, 0.12)
	p.LS = A(0.15, 0, -0.3)
	p.RS = A(0.1, 0, 0.32)
	p.LE = A(0.35, 0, 0)
	p.RE = A(0.3, 0, 0)
	R.legAngles(p, drop, -0.04, len)
end

-- upright on both knees (on the way to the canvas, forward falls)
local function knees(p, rig)
	clear(p)
	p.Root = CF(0, -1.6, 0.25) * A(-0.2, 0, 0)
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

-- on hands and knees, head hanging (forward knockdown, the middle of a get-up)
local function handsKnees(p, rig)
	clear(p)
	p.Root = CF(0, -1.9, -0.35) * A(-1.2, 0, 0)
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

-- face down on the canvas, head turned, one arm up by the head
local function faceDown(p, rig)
	clear(p)
	p.Root = CF(0, -2.9, -0.9) * A(-1.55, 0.3, 0)
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

-- sitting on the canvas: one leg out straight, the other knee up, gloves down beside the hips
-- (the pelvis tilts back 0.35: a thigh at 1.22 lies flat, the foot of the raised knee rests flat)
local function sitDown(p, rig)
	clear(p)
	p.Root = CF(0, -2.8, 0.35) * A(0.35, 0, 0)
	p.W = A(-0.3, 0, 0)
	p.Neck = A(-0.3, 0, 0.15)
	p.LS = A(-0.45, 0, -0.35)
	p.LE = A(0.15, 0, 0)
	p.RS = A(-0.4, 0, 0.35)
	p.RE = A(0.15, 0, 0)
	p.LH = A(1.22, 0, -0.12)
	p.LK = A(-0.08, 0, 0)
	p.LA = A(-0.3, 0, 0)
	p.RH = A(1.75, 0, 0.12)
	p.RK = A(-1.5, 0, 0)
	p.RA = A(-0.6, 0, 0)
end

-- the backward collapse's middle: the backside hits, the upper body still folding back, limp
local function sitSlump(p, rig)
	clear(p)
	p.Root = CF(0, -2.7, 0.5) * A(0.62, 0, 0.06)
	p.W = A(0.22, 0, 0)
	p.Neck = A(-0.55, 0.15, 0.2)
	p.LS = A(0.1, 0, -0.75)
	p.LE = A(0.3, 0, 0)
	p.RS = A(0.05, 0, 0.8)
	p.RE = A(0.25, 0, 0)
	p.LH = A(1.0, 0, -0.18)
	p.LK = A(-0.15, 0, 0)
	p.LA = A(-0.3, 0, 0)
	p.RH = A(1.25, 0, 0.15)
	p.RK = A(-0.85, 0, 0)
	p.RA = A(-0.4, 0, 0)
end

-- flat on the back, knees up a little, arms out
local function onBack(p, rig)
	clear(p)
	p.Root = CF(0, -2.9, 0.9) * A(1.55, 0, 0)
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

-- out cold on the back: limp arms flung out, head rolled to the side, one knee fallen out
local function onBackLimp(p, rig)
	clear(p)
	local t = rig.koTilt or 0.3
	p.Root = CF(0, -2.9, 1.2) * A(1.57, 0, 0.04)
	p.W = A(0.02, 0, 0)
	p.Neck = A(0.2, 0.75 * (t >= 0 and 1 or -1), 0.25)
	p.LS = A(0.55, 0, -1.45)
	p.LE = A(0.25, 0, 0)
	p.RS = A(0.15, 0, 1.15)
	p.RE = A(0.45, 0, 0)
	p.LH = A(0.55, 0, -0.35)
	p.LK = A(-1.0, 0, 0)
	p.LA = A(0.35, 0, 0)
	p.RH = A(0.1, 0, 0.12)
	p.RK = A(-0.15, 0, 0)
end

-- on the hip, half sitting (the middle of a side fall); s = +1 falls to his right, -1 to his left
local function hipSit(p, rig, s)
	clear(p)
	p.Root = CF(0.35 * s, -2.6, 0.2) * A(0.2, 0, -0.55 * s)
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

-- lying on the side, the under arm out in front of the head, the top arm over the body
local function onSide(p, rig, s)
	clear(p)
	p.Root = CF(0.75 * s, -2.8, 0.1) * A(0.15, 0, -1.5 * s)
	p.W = A(0.12, 0, 0)
	p.Neck = A(-0.15, 0, 0.35 * s)
	local near, far = s > 0 and "R" or "L", s > 0 and "L" or "R"
	-- (the under arm reaches out past the head, along the canvas)
	p[near .. "S"] = A(1.55, 0, 0.35 * s)
	p[near .. "E"] = A(0.35, 0, 0)
	p[far .. "S"] = A(0.75, 0, 0.3 * s)
	p[far .. "E"] = A(1.15, 0, 0)
	p.LH = A(0.95, 0, 0)
	p.LK = A(-1.3, 0, 0)
	p.RH = A(0.6, 0, 0)
	p.RK = A(-1.05, 0, 0)
end

-- one knee down, a glove on the canvas, head bowed (flash knockdown / the middle of a get-up)
local function kneel(p, rig)
	clear(p)
	p.Root = CF(0, -1.45, 0.1) * A(-0.12, 0, 0)
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
	p.Root = CF(0, -1.8, 0.2) * A(-0.75, 0, 0)
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

-- staggering back into the ropes / the corner: arms wheel for balance, head and chest back (the
-- server moves the root, the planted feet take the steps)
local function stagger(p, rig, t)
	clear(p)
	local w = sin(t * 13)
	p.Root = CF(0, -0.25, 0.08) * A(0.16, 0, 0.05 * w)
	p.W = A(0.14, 0, -0.05 * w)
	p.Neck = A(0.32, 0, 0.12)
	p.LS = A(0.75 + 0.35 * w, 0, -0.95)
	p.RS = A(0.85 - 0.35 * w, 0, 1.05)
	p.LE = A(0.45, 0, 0)
	p.RE = A(0.5, 0, 0)
	R.legAngles(p, 0.25, -0.1, rig.geo.ok and rig.geo.legLen or 2.3)
end

-- ropes: his back hits the top rope and bends over it, arms flung back along it, head whipped back
local function ropeArch(p, rig, rebound)
	clear(p)
	local k = rebound and 1 or 0
	p.Root = CF(0, -0.18 - 0.2 * k, 0.6 + 0.08 * k) * A(0.36 - 0.1 * k, 0, 0.04)
	p.W = A(0.38 - 0.24 * k, 0, 0)
	p.Neck = A(0.55 - 0.85 * k, 0, 0.1 + 0.15 * k)
	p.LS = A(-0.55 + 0.15 * k, 0, -1.45)
	p.RS = A(-0.5 + 0.15 * k, 0, 1.45)
	p.LE = A(0.55, 0, 0)
	p.RE = A(0.5, 0, 0)
	R.legAngles(p, 0.2 + 0.2 * k, -0.12, rig.geo.ok and rig.geo.legLen or 2.3)
end

-- ropes: sat on the bottom rope at the rope line, back against the middle rope, elbows hooked over
-- it, feet flat on the canvas, head lolling
local function ropeSit(p, rig)
	clear(p)
	p.Root = CF(0, -1.6, 1.35) * A(0.22, 0, 0.05)
	p.W = A(0.1, 0, 0.04)
	p.Neck = A(-0.5, 0.2, 0.32)
	p.LS = A(-0.75, 0, -1.05)
	p.LE = A(1.25, 0, 0)
	p.RS = A(-0.7, 0, 1.1)
	p.RE = A(1.2, 0, 0)
	p.LH = A(1.35, 0, -0.16)
	p.LK = A(-1.55, 0, 0)
	p.LA = A(0.0, 0, 0)
	p.RH = A(1.25, 0, 0.12)
	p.RK = A(-1.35, 0, 0)
	p.RA = A(-0.1, 0, 0)
end

-- corner: backed into the post, both arms thrown out over the top ropes (they run forward-left and
-- forward-right from the post), chest open, head back
local function cornerHit(p, rig)
	clear(p)
	p.Root = CF(0, -0.22, 0.45) * A(0.2, 0, 0)
	p.W = A(0.2, 0, 0)
	p.Neck = A(0.4, 0, -0.1)
	p.LS = A(0, -0.62, -1.42)
	p.RS = A(0, 0.62, 1.42)
	p.LE = A(0.3, 0, 0)
	p.RE = A(0.35, 0, 0)
	R.legAngles(p, 0.25, -0.1, rig.geo.ok and rig.geo.legLen or 2.3)
end

-- corner: sliding down the pads, the arms dragged up along the ropes
local function cornerSlide(p, rig)
	clear(p)
	p.Root = CF(0, -1.0, 0.75) * A(0.15, 0, -0.05)
	p.W = A(0.12, 0, 0.04)
	p.Neck = A(-0.2, 0.1, 0.25)
	p.LS = A(0.2, -0.55, -1.85)
	p.RS = A(0.2, 0.55, 1.8)
	p.LE = A(0.5, 0, 0)
	p.RE = A(0.55, 0, 0)
	R.legAngles(p, 1.0, -0.05, rig.geo.ok and rig.geo.legLen or 2.3)
end

-- corner: sat wedged in the corner, legs splayed in front, arms draped along the bottom ropes either
-- side, head lolled onto a shoulder
local function cornerSit(p, rig)
	clear(p)
	p.Root = CF(0, -2.8, 1.05) * A(0.32, 0, 0.06)
	p.W = A(0.12, 0, 0.05)
	p.Neck = A(-0.42, 0.25, 0.5)
	p.LS = A(-0.2, -0.5, -1.25)
	p.LE = A(0.75, 0, 0)
	p.RS = A(-0.25, 0.5, 1.2)
	p.RE = A(0.8, 0, 0)
	p.LH = A(1.4, 0, -0.42)
	p.LK = A(-0.55, 0, 0)
	p.LA = A(-0.5, 0, 0)
	p.RH = A(1.3, 0, 0.38)
	p.RK = A(-0.35, 0, 0)
	p.RA = A(-0.6, 0, 0)
end

-- out on his feet: knees bent, arms hanging, head down, swaying from the ankles
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

-- get-up stages ------------------------------------------------------------------------------------
-- lying on the back, stirring: knees drawn up, head and shoulders lifting, one elbow under him
local function backStir(p, rig)
	onBack(p, rig)
	p.Root = p.Root * A(-0.25, 0, -0.1)
	p.Neck = A(-0.5, 0, 0)
	p.W = A(-0.15, 0, 0)
	p.LS = A(0.3, 0, -0.55)
	p.LE = A(1.5, 0, 0)
	p.LH = A(1.0, 0, -0.1)
	p.LK = A(-1.6, 0, 0)
	p.RH = A(0.9, 0, 0.1)
	p.RK = A(-1.4, 0, 0)
end

-- rolled onto his left side, propped on the forearm, knees drawn up
local function rollSide(p, rig)
	clear(p)
	p.Root = CF(-0.45, -2.6, 0.55) * A(0.5, 0, 1.15)
	p.W = A(-0.2, 0, -0.2)
	p.Neck = A(-0.3, 0, -0.35)
	p.LS = A(1.25, 0, -0.35)
	p.LE = A(1.35, 0, 0)
	p.RS = A(1.0, 0, 0.25)
	p.RE = A(0.6, 0, 0)
	p.LH = A(1.35, 0, 0)
	p.LK = A(-1.7, 0, 0)
	p.RH = A(1.2, 0, 0)
	p.RK = A(-1.6, 0, 0)
end

-- face down, pushing up: hands under the shoulders, chest off the canvas, knees still down
local function pushUp(p, rig)
	clear(p)
	p.Root = CF(0, -2.6, -0.6) * A(-1.25, 0, 0)
	p.W = A(0.3, 0, 0)
	p.Neck = A(0.15, 0, 0)
	p.LS = A(1.15, 0, -0.25)
	p.RS = A(1.15, 0, 0.25)
	p.LE = A(0.6, 0, 0)
	p.RE = A(0.6, 0, 0)
	p.LH = A(0.25, 0, -0.08)
	p.RH = A(0.25, 0, 0.08)
	p.LK = A(-0.9, 0, 0)
	p.RK = A(-0.9, 0, 0)
	p.LA = A(-0.5, 0, 0)
	p.RA = A(-0.5, 0, 0)
end

-- sitting, about to rise: leaning forward over a tucked leg, a glove on the canvas beside him
local function sitTuck(p, rig)
	clear(p)
	p.Root = CF(0, -2.5, 0.25) * A(-0.35, 0, 0.1)
	p.W = A(-0.3, 0, 0)
	p.Neck = A(-0.2, 0, 0)
	p.LS = A(0.45, 0, -0.35)
	p.LE = A(0.3, 0, 0)
	p.RS = A(0.9, 0, 0.1)
	p.RE = A(0.9, 0, 0)
	p.LH = A(1.4, 0, -0.1)
	p.LK = A(-1.7, 0, 0)
	p.LA = A(0.3, 0, 0)
	p.RH = A(0.6, 0, 0.2)
	p.RK = A(-2.0, 0, 0)
	p.RA = A(-0.6, 0, 0)
end

-- one knee down, pushing off it with a glove on the knee, head up: about to stand
local function kneelPush(p, rig)
	kneel(p, rig)
	p.Root = CF(0, -1.35, 0.05) * A(-0.3, 0, 0)
	p.W = A(-0.25, 0, 0)
	p.Neck = A(-0.05, 0, 0)
	p.LS = A(0.65, 0, -0.1)
	p.LE = A(1.0, 0, 0)
	p.RS = A(0.5, 0, 0.15)
	p.RE = A(0.4, 0, 0)
end

-- ropes / corner get-up: reaching up to grab the rope behind / beside him, still sitting
local function ropeGrab(p, rig, corner)
	if corner then
		cornerSit(p, rig)
		p.LS = A(0.5, -0.5, -2.1)
		p.RS = A(0.5, 0.5, 2.1)
	else
		ropeSit(p, rig)
		p.LS = A(0.6, 0, -2.2)
		p.RS = A(0.6, 0, 2.2)
	end
	p.LE = A(1.0, 0, 0)
	p.RE = A(1.0, 0, 0)
	p.Neck = A(0.05, 0, 0)
	p.W = A(-0.05, 0, 0)
end

-- hauled half up on the ropes: hands on the rope above, back against it, knees bent
local function ropePull(p, rig, corner)
	clear(p)
	p.Root = CF(0, -0.9, corner and 0.65 or 1.1) * A(0.08, 0, 0)
	p.W = A(0.05, 0, 0)
	p.Neck = A(-0.05, 0, 0)
	p.LS = A(0.4, corner and -0.5 or 0, -1.75)
	p.RS = A(0.4, corner and 0.5 or 0, 1.75)
	p.LE = A(0.9, 0, 0)
	p.RE = A(0.9, 0, 0)
	R.legAngles(p, 0.9, -0.05, rig.geo.ok and rig.geo.legLen or 2.3)
end

------------------------------------------------------------------------
-- Timelines: { time, builder, ease into this key, impact strength? } (falls: seconds; get-ups:
-- shares of the get-up time). plant = the feet stay planted (IK) until that key's time.
------------------------------------------------------------------------
local GRAV, OUT, SMOOTH = "grav", "out", "smooth"
local FALLS = {
	flash = { { 0.14, "buckle", OUT }, { 0.42, "kneel", GRAV, 0.6 } },
	sit = { { 0.16, "buckle", OUT }, { 0.5, "sit", GRAV, 0.8 } },
	knee = { { 0.25, "buckleF", SMOOTH }, { 0.62, "kneel", GRAV, 0.6 }, { 1.15, "kneelFold", SMOOTH } },
	forward = { { 0.15, "buckleF", OUT }, { 0.45, "knees", GRAV, 0.6 }, { 0.75, "handsKnees", GRAV, 1 } },
	face = { { 0.15, "buckleF", OUT }, { 0.45, "knees", GRAV, 0.6 }, { 0.82, "faceDown", GRAV, 1 } },
	back = { { 0.16, "buckle", OUT }, { 0.5, "sit", GRAV, 0.6 }, { 0.86, "onBack", GRAV, 1 } },
	side = { { 0.18, "buckleS", OUT }, { 0.55, "hipSit", GRAV, 0.6 }, { 0.92, "onSide", GRAV, 1 } },
	-- the server walks his root into the ropes over the first 0.45 s: the planted feet take the steps
	ropes = { { 0.45, "stagger", SMOOTH }, { 0.6, "ropeArch", OUT, 0.7 }, { 0.92, "ropeArch2", SMOOTH }, { 1.5, "ropeSit", GRAV, 0.8 } },
	corner = { { 0.45, "stagger", SMOOTH }, { 0.6, "cornerHit", OUT, 0.7 }, { 1.05, "cornerSlide", SMOOTH }, { 1.55, "cornerSit", GRAV, 0.8 } },
	-- knockouts: the backward collapse (crumple + back) goes at the knees first, then folds back
	koBack = { { 0.2, "kneesGo", GRAV }, { 0.46, "sitSlump", GRAV, 0.8 }, { 0.8, "onBackLimp", GRAV, 1.3 } },
}
FALLS.standing = FALLS.knee -- unknown use of "standing" without a KO: treat as a sagging knee
-- until when (same units) the feet stay planted: the knees give on planted feet, then the fall leaves them
local PLANT = { flash = 0.14, sit = 0.16, knee = 0.25, forward = 0.15, face = 0.15, back = 0.16, side = 0.18, ropes = 0.92, corner = 0.6, koBack = 0.2 }

local GETUPS = {
	back = { { 0.22, "backStir", SMOOTH }, { 0.42, "rollSide", SMOOTH }, { 0.6, "handsKnees", SMOOTH }, { 0.78, "kneelPush", SMOOTH } },
	face = { { 0.28, "pushUp", SMOOTH }, { 0.52, "handsKnees", SMOOTH }, { 0.76, "kneelPush", SMOOTH } },
	forward = { { 0.35, "handsKnees", SMOOTH }, { 0.72, "kneelPush", SMOOTH } },
	side = { { 0.28, "hipSit", SMOOTH }, { 0.52, "handsKnees", SMOOTH }, { 0.76, "kneelPush", SMOOTH } },
	sit = { { 0.32, "sitTuck", SMOOTH }, { 0.62, "kneelPush", SMOOTH } },
	knee = { { 0.5, "kneelPush", SMOOTH } },
	flash = { { 0.45, "kneelPush", SMOOTH } },
	ropes = { { 0.32, "ropeGrab", SMOOTH }, { 0.72, "ropePull", SMOOTH } },
	corner = { { 0.32, "cornerGrab", SMOOTH }, { 0.72, "cornerPull", SMOOTH } },
}
GETUPS.standing = GETUPS.knee

local function build(name, p, rig, d, t)
	local s = d and d.side or 1
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
	elseif name == "hipSit" then
		hipSit(p, rig, s)
	elseif name == "onSide" then
		onSide(p, rig, s)
	elseif name == "stagger" then
		stagger(p, rig, t)
	elseif name == "ropeArch" then
		ropeArch(p, rig, false)
	elseif name == "ropeArch2" then
		ropeArch(p, rig, true)
	elseif name == "ropeSit" then
		ropeSit(p, rig)
	elseif name == "cornerHit" then
		cornerHit(p, rig)
	elseif name == "cornerSlide" then
		cornerSlide(p, rig)
	elseif name == "cornerSit" then
		cornerSit(p, rig)
	elseif name == "kneesGo" then
		kneesGo(p, rig)
	elseif name == "sitSlump" then
		sitSlump(p, rig)
	elseif name == "onBackLimp" then
		onBackLimp(p, rig)
	elseif name == "slump" then
		slump(p, rig, t, d and d.ns or 1)
	elseif name == "backStir" then
		backStir(p, rig)
	elseif name == "rollSide" then
		rollSide(p, rig)
	elseif name == "pushUp" then
		pushUp(p, rig)
	elseif name == "sitTuck" then
		sitTuck(p, rig)
	elseif name == "kneelPush" then
		kneelPush(p, rig)
	elseif name == "ropeGrab" then
		ropeGrab(p, rig, false)
	elseif name == "ropePull" then
		ropePull(p, rig, false)
	elseif name == "cornerGrab" then
		ropeGrab(p, rig, true)
	elseif name == "cornerPull" then
		ropePull(p, rig, true)
	else -- "onBack" and anything unknown
		onBack(p, rig)
	end
end

------------------------------------------------------------------------
-- Start / slow motion / landing
------------------------------------------------------------------------
local VALID = { back = true, side = true, knee = true, sit = true, face = true, flash = true, forward = true, ropes = true, corner = true, standing = true }

-- capture the pose the rig shows right now (the fall / get-up starts from it)
local function capture(rig, into)
	for _, k in ipairs(KEYS) do
		local j = rig.joints[k]
		into[k] = j and j.cur or I
	end
	if rig.rootOut then
		into.Root = rig.rootOut
	end
	return into
end

-- the dramatic moment: both fighters slow down together for a beat. Real time: every rig runs its
-- own clock, so the moment is shared as an os.clock() stamp (and published as KOMoment)
function AnimDown.slowMo(rig)
	local now = os.clock()
	rig.slowFrom = now
	rig.model:SetAttribute("KOMoment", now)
	local opp = rig.oppRig
	if opp then
		opp.slowFrom = now
	end
end

-- a knockout's final impact (client-local KOLanded = os.clock()): the KO camera holds until shortly after
local function landed(rig, d)
	if d.ko and not d.landedAt then
		d.landedAt = os.clock()
		rig.model:SetAttribute("KOLanded", d.landedAt)
	end
end

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
		impacts = {}, from = capture(rig, {}), theta = 0, omega = 0, landed = false, fence = rig.rng:NextNumber() < 0.5 and "L" or "R",
		delay = 0, keys = FALLS[pose] or FALLS.back, plantT = PLANT[pose] or PLANT.back,
	}
	rig.model:SetAttribute("KOLanded", nil)
	if ko == "oneshot" then
		-- a stiff timber fall: backwards unless he was caught going forward
		d.timber = (pose == "face" or pose == "forward") and -1 or 1
		d.theta = 0.08 * d.timber
		d.omega = (0.9 + rig.rng:NextNumber() * 0.4) * d.timber
	elseif ko == "delayed" then
		-- out on his feet for a beat (never longer than HOLD_MAX of wall time), then the legs go
		d.delay = 0.5 + rig.rng:NextNumber() * (HOLD_MAX - 0.5)
		d.stepAt = d.delay * (0.3 + rig.rng:NextNumber() * 0.2)
	elseif ko == "crumple" and pose == "back" then
		d.keys, d.plantT = FALLS.koBack, PLANT.koBack
	end
	if ko and pose == "forward" then
		-- knockouts do not catch themselves: the forward fall goes all the way down onto the face
		d.keys, d.plantT = FALLS.face, PLANT.face
	end
	-- the fall direction relative to the authored one (authored falls go back / forward / to a side)
	local auth = (pose == "face" or pose == "forward" or pose == "knee" or pose == "flash") and 0 or PI
	if pose == "side" then
		auth = d.side > 0 and -PI / 2 or PI / 2
	end
	local yaw = K.wrap(dir - auth)
	if pose == "ropes" or pose == "corner" then
		d.yaw = yaw -- turns his back to the ropes / the post as he staggers
	else
		d.yaw = clamp(yaw, -0.6, 0.6) -- a little variety, never a different fall
	end
	rig.down = d
	if ko and ko ~= "standing" and ko ~= "delayed" then
		AnimDown.slowMo(rig)
	end
	return d
end

-- time scale of a slowed-down knockout moment (1 = real time); `now` = os.clock()
function AnimDown.timeScale(rig, now)
	local s = rig.slowFrom
	if not s then
		return 1
	end
	local el = now - s
	if el < 0 then
		return 1
	end
	if el > 1.05 then
		rig.slowFrom = nil
		return 1
	end
	-- ease into slow motion, hold, ease back out (in real time: both fighters share it)
	if el < 0.08 then
		return lerp(1, SLOW, smooth(el / 0.08))
	elseif el < 0.75 then
		return SLOW
	end
	return lerp(SLOW, 1, smooth((el - 0.75) / 0.3))
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
	local s = strength * ((d and d.ko) and 1.25 or 0.8)
	local r = rig.rng
	kick(rig, (r:NextNumber() - 0.3) * 6 * s, (r:NextNumber() - 0.5) * 3 * s, (r:NextNumber() - 0.5) * 4 * s,
		(r:NextNumber() - 0.5) * 2 * s, 0, (r:NextNumber() - 0.5) * 2 * s, 0, 0, -0.6 * s, 0,
		(r:NextNumber() - 0.5) * 5 * s, (r:NextNumber() - 0.5) * 5 * s, (r:NextNumber() - 0.5) * 4 * s, (r:NextNumber() - 0.5) * 4 * s)
	if name == "onBackLimp" or name == "timber" then
		-- the back of the head whips onto the canvas and bounces
		kick(rig, 5 * s, 0, 0)
	end
	local FX = R.FX
	if FX.HairFX then
		FX.HairFX.Impulse(rig.model, 0, 0.6, 0.6 * strength)
	end
	if FX.BodyFX then
		FX.BodyFX.Jiggle(rig.model, "all", 0.4 * strength)
	end
end

-- evaluate a timeline into p (from `from` at el = 0); scale = seconds per time unit. Returns the key
-- index being played (#keys + 1 once it is over)
local function timeline(p, rig, d, keys, el, t, from, scale, impacts, yaw)
	local prevT, prevName = 0, nil
	local turn = (yaw and abs(yaw) > 1e-3) and A(0, yaw, 0) or nil
	for i, key in ipairs(keys) do
		local kt = key[1] * scale
		if el < kt then
			local u = (el - prevT) / max(1e-3, kt - prevT)
			local e = easeOf(key[3], clamp(u, 0, 1))
			if prevName then
				build(prevName, rig.kp, rig, d, t)
				if turn then
					rig.kp.Root = turn * rig.kp.Root
				end
			else
				for _, k in ipairs(KEYS) do
					rig.kp[k] = from[k]
				end
			end
			build(key[2], rig.kp2, rig, d, t)
			if turn then
				rig.kp2.Root = turn * rig.kp2.Root
			end
			for _, k in ipairs(KEYS) do
				p[k] = rig.kp[k]:Lerp(rig.kp2[k], e)
			end
			return i
		end
		-- passed this key: its impact fires once
		if key[4] and impacts and not impacts[i] then
			impacts[i] = true
			impact(rig, d, key[4], key[2])
			if i == #keys and d then
				landed(rig, d)
			end
		end
		prevT, prevName = kt, key[2]
	end
	build(prevName or "onBack", p, rig, d, t)
	if turn then
		p.Root = turn * p.Root
	end
	return #keys + 1
end

-- the stiff one-punch fall: a rigid body pivoting on its feet (theta'' = 3g / 2L sin theta) until the
-- back (or the face) is flat on the canvas
local LIE = 1.57
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
		local lim = d.timber * LIE
		if (d.timber > 0 and d.theta >= lim) or (d.timber < 0 and d.theta <= lim) then
			-- the canvas: a bounce, then he lies still
			d.theta = lim
			d.landed = true
			d.landT = t
			impact(rig, d, 1.3, "timber")
			landed(rig, d)
		end
	end
	local th = d.theta
	if d.landed then
		local el = t - d.landT
		-- one small rebound, settling
		th = d.theta - d.timber * 0.08 * sin(min(1, el / 0.35) * PI) * (1 - min(1, el / 0.35))
	end
	clear(p)
	-- rotate the whole body about the ground point under the heels (backwards) / toes (forwards);
	-- groundSolve then rests it on the canvas
	local pz = d.timber > 0 and 0.3 or -0.45
	p.Root = CF(0, -fh, pz) * A(th, 0, 0) * CF(0, fh, -pz)
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
	if d.timber > 0 then
		p[up] = A(lerp(2.4, 0.4, sink) * fe, 0, sgn * 0.25)
		p[other] = A(0.15, 0, -sgn * lerp(0.2, 0.9, sink))
	else
		-- face first: the arms never come up to break the fall
		p[up] = A(-0.15, 0, sgn * 0.12)
		p[other] = A(-0.2, 0, -sgn * 0.15)
	end
	p[fenceS == "L" and "LE" or "RE"] = A(0.15, 0, 0)
	p[fenceS == "L" and "RE" or "LE"] = A(0.5, 0, 0)
	p.Neck = A(d.timber > 0 and 0.25 or -0.2, 0, 0)
	p.W = A(0, 0, 0)
	local lie = smooth(abs(th) / LIE)
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
		-- head comes up, he looks for the rope above to pull himself up
		p.Neck = p.Neck:Lerp(A(0.05, 0, 0), k)
		p.LE = p.LE:Lerp(A(0.9, 0, 0), k)
		p.RE = p.RE:Lerp(A(0.9, 0, 0), k)
	elseif pose == "side" then
		p.Root = p.Root * A(0, 0, 0.4 * k * d.side)
		p.Neck = p.Neck:Lerp(A(-0.2, 0, -0.2 * d.side), k)
	else
		p.Neck = p.Neck:Lerp(A(-0.1, 0.15 * sin(t * 2), 0), k)
		p.W = p.W * A(0.15 * k, 0, 0)
	end
end

-- feet stay where they are (the first instant of a fall): planted, no corrective steps
local function holdFeet(rig)
	rig.plant = true
	rig.stepDist = 99
	local fL, fR = rig.foot.L, rig.foot.R
	fL.heel, fR.heel = 0, 0
end

-- rest the pose on the canvas (unless the feet are planted: the leg IK does that)
local function onCanvas(rig, p)
	if rig.plant then
		return
	end
	local out = rig.fkOut or {}
	rig.fkOut = out
	R.groundSolve(rig, p, out, 0.03)
	R.liftArms(rig, p, out, 0.04)
end

------------------------------------------------------------------------
-- The full down pose for this frame
------------------------------------------------------------------------
-- the referee standing within catching distance of a man out on his feet (nil when he is not there)
local function catcher(rig)
	local ref = rig.refRig
	if ref and ref.root and ref.root.Parent and rig.root then
		local off = ref.root.Position - rig.root.Position
		if V3(off.X, 0, off.Z).Magnitude < 3.4 then
			return ref, off
		end
	end
	return nil
end

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
		-- out on his feet: no fall; slumped and swaying, wobbly half steps, until the referee gets there,
		-- then he sags forward into the referee's arms, the weight off his legs
		slump(p, rig, t, d.ns)
		local ref, off = catcher(rig)
		local lean = d.lean or 0
		lean += ((ref and 1 or 0) - lean) * (1 - math.exp(-dt * 5))
		d.lean = lean
		if lean > 0.01 then
			local lp = rig.root.CFrame:VectorToObjectSpace(off or V3(0, 0, -1))
			local yaw = math.atan2(-lp.X, -lp.Z)
			p.Root = CF(0, -0.3 * lean, -0.3 * lean) * A(0, yaw * 0.5 * lean, 0) * p.Root * A(-0.3 * lean, 0, 0)
			p.W = p.W * A(-0.15 * lean, 0, 0)
			p.Neck = p.Neck * A(-0.15 * lean, yaw * 0.3 * lean, 0.3 * lean)
			-- arms hang over the referee's
			p.LS = p.LS:Lerp(A(0.75, 0, -0.35), lean)
			p.RS = p.RS:Lerp(A(0.7, 0, 0.3), lean)
			p.LE = p.LE:Lerp(A(0.5, 0, 0), lean)
			p.RE = p.RE:Lerp(A(0.45, 0, 0), lean)
			if lean > 0.6 then
				landed(rig, d)
			end
		elseif el > 0.35 and not d.halfStep and rig.foot and L.ready(rig, "R", t) then
			-- a wobbly half step before the referee arrives
			d.halfStep = true
			L.request(rig, "R", 0.15, 0.25, 0.25, 0.08, 1.2, t)
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
	elseif el < d.delay then
		-- the delayed knockout: out on his feet for a beat. The knees wobble, a half stagger step, the
		-- guard sinks, the eyes go; the slow motion starts when the legs go
		local k = el / max(0.1, d.delay)
		slump(p, rig, t, d.ns)
		local blend = smooth(min(1, el / 0.3))
		for _, key in ipairs(KEYS) do
			p[key] = d.from[key]:Lerp(p[key], blend * (0.35 + 0.65 * k))
		end
		local wob = sin(el * 17) * 0.05 + sin(el * 11.3) * 0.03
		p.Root = CF(0.04 * sin(el * 5.3), -0.12 * k + wob, 0) * p.Root * A(0, 0, 0.06 * sin(el * 4.1))
		p.Neck = p.Neck * A(-0.15 * k, 0.2 * sin(el * 3.7) * k, 0.15 * k)
		rig.plant = true
		R.plant(rig, 0.6, 0.12, -0.15, -0.6, 0, 0)
		rig.stepDist = 99
		rig.foot.L.knee += 0.22 * sin(el * 19)
		rig.foot.R.knee += 0.22 * sin(el * 23 + 1)
		if d.stepAt and el >= d.stepAt and L.ready(rig, "L", t) then
			-- a half stagger step, the lead foot dragged in
			d.stepAt = nil
			L.request(rig, "L", 0.12, 0.3, 0.22, 0.06, 2, t)
		end
		rig.exprHint = "ko"
		return true
	else
		local start = d.delay
		if ko == "delayed" and not d.collapse then
			-- the legs go now: the slow-motion beat starts here, from the pose he is in
			d.collapse = true
			d.from = capture(rig, d.from)
			AnimDown.slowMo(rig)
		end
		if ko then
			d.speed = 0.85 -- out cold: nothing slows the fall
		end
		local keys = d.keys
		local fel = el - start
		timeline(p, rig, d, keys, fel, t, d.from, d.speed or 1, d.impacts)
		-- feet stay planted while the knees give (no foot slide in the first instant of a fall)
		local pl = d.plantT
		if pl and fel < pl * (d.speed or 1) then
			holdFeet(rig)
			if d.pose == "ropes" or d.pose == "corner" then
				-- staggering into the ropes: the root moves, the feet step (AnimLoco's stagger gait) and
				-- turn with him as his back comes round to the ropes
				local yk = d.yaw * smooth(el / 0.6)
				local c, sn = math.cos(yk), sin(yk)
				for _, side in ipairs(R.SIDES) do
					local f = rig.foot[side]
					local a0 = rig.geo[side].ankle0
					f.ox = a0.X * c + a0.Z * sn - a0.X
					f.oz = -a0.X * sn + a0.Z * c - a0.Z
					f.yaw = yk
				end
				rig.stepDist = 0.3
				L.gait(rig, "stagger")
			end
		end
	end
	-- direction: the whole fall turns about the root as it goes (ropes / corner over the stagger)
	local yaw = d.yaw
	if abs(yaw) > 1e-3 then
		local k = smooth(el / ((d.pose == "ropes" or d.pose == "corner") and 0.6 or 0.3))
		p.Root = A(0, yaw * k, 0) * p.Root
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
	onCanvas(rig, p)
	return true
end

------------------------------------------------------------------------
-- The get-up (act getup|<fall>|0|<seconds>): staged per fall, then up through a planted squat into
-- the live stance underneath (the feet are seeded where the keyed legs left them and step in)
------------------------------------------------------------------------
function AnimDown.getup(p, rig, act, el, t)
	local u = el / act.dur
	if u >= 1 then
		return false
	end
	p.override = true -- the base pose continues from here when the get-up ends
	if not act.from then
		act.from = capture(rig, {})
		act.stance = {}
		act.last = {}
		act.keys = GETUPS[act.fall] or GETUPS.back
		act.d = { side = act.side or 1, ns = 1 }
		act.standAt = act.keys[#act.keys][1]
		act.yaw = act.yaw or 0
	end
	-- the live stance underneath (Guard is no longer "down")
	local st = act.stance
	for _, k in ipairs(KEYS) do
		st[k] = p[k]
	end
	local standAt = act.standAt
	if u < standAt then
		rig.plant = false
		timeline(p, rig, act.d, act.keys, u, t, act.from, 1, nil, act.yaw)
		onCanvas(rig, p)
		for _, k in ipairs(KEYS) do
			act.last[k] = p[k]
		end
		R.flex(rig, "quads", 0.5)
		R.flex(rig, "glutes", 0.4)
		R.flex(rig, "triceps", 0.5)
	else
		-- up through a squat on planted feet into the stance (the stance's own feet spec)
		local x = smooth((u - standAt) / (1 - standAt))
		for _, k in ipairs(KEYS) do
			if not LEG_KEYS[k] then
				p[k] = act.last[k]:Lerp(st[k], x)
			end
		end
		rig.plant = true
		rig.stepDist = 0.3
		R.flex(rig, "quads", 0.9 * (1 - x))
		R.flex(rig, "glutes", 0.8 * (1 - x))
	end
	rig.exprHint = "effort"
	return true
end

-- the get-up the Animator plays when Guard leaves "down" without a getup act (the end of a fight, an
-- older server): the fall's own staged get-up, a little slower (he is only just coming to)
function AnimDown.recoverAct(d, now)
	local fall = d.pose
	if d.ko == "oneshot" then
		fall = d.timber and d.timber < 0 and "face" or "back"
	elseif d.ko == "crumple" and fall == "back" then
		fall = "back"
	end
	local dur = (fall == "flash" or fall == "knee" or fall == "standing") and 1.3 or (fall == "sit" and 1.6 or 2.6)
	return { kind = "getup", start = now, fall = fall, dur = dur, side = d.side, yaw = d.yaw }
end

function AnimDown.clear(rig)
	rig.down = nil
end

-- (key poses by name: tools / the animation lab inspect them on a real rig)
AnimDown.build = build

return AnimDown
