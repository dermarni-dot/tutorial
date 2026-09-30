-- Poses (ModuleScript) — ReplicatedStorage.Shared.Poses
-- The client side of citizens' body language. For every citizen near the
-- camera it:
--   • plays the pose for their "Action" attribute (typing, lifting, sitting,
--     sleeping, cheering, fishing...) by setting Motor6D.Transform every frame
--     (smoothly blended, with each person's own rhythm)
--   • puts the right props in their hands (a cup, a book, dumbbells, a rod...)
--   • swings kids on the swings, shoots basketballs at the hoop, kicks the
--     soccer ball, shows stars when knocked out
--   • fights: a stance, a punch combo (jab, cross, hook, uppercut, and a
--     roundhouse kick in street fights), bat and knife swings, blocks, hit
--     reactions that snap away from the punch, staggers, a victory fist pump
--   • turns their head to look at you when you're close
--   • blinks their eyes, moves their mouth while they talk, and shows their
--     expression (see Shared.Faces)
--
-- Used by CityClient:  Poses.Step(dt) every frame (RunService.PreSimulation).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Actions = require(Shared:WaitForChild("Actions"))
local Faces = require(Shared:WaitForChild("Faces"))

local Poses = {}
local localPlayer = Players.LocalPlayer
Poses.PoseRadius = 130 -- poses play within this distance of the camera
Poses.FaceRadius = 70 -- faces blink and talk within this distance

local rad, sin, cos, abs = math.rad, math.sin, math.cos, math.abs
local function A(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end
local function osc(t, speed, phase)
	return sin(t * speed + (phase or 0))
end

--------------------------------------------------------------------------------
-- The pose library. Each pose returns a table of joint -> CFrame (and whether
-- it replaces the whole body or only some joints, eg. waving while walking).
-- Joints: Neck Waist Root LS LE LW RS RE RW LH LK LA RH RK RA
-- Angles: shoulder/hip +X = forward, elbow +X = bend, knee -X = bend,
-- waist -X = lean forward, neck -X = look down, right arm +Z = out to the side.
--------------------------------------------------------------------------------
local function sit(p)
	p.LH = A(90, 0, -4)
	p.RH = A(90, 0, 4)
	p.LK = A(-90)
	p.RK = A(-90)
	return p
end

local L = {}
Poses.Library = L

L.sit = function(t, ph)
	return sit({ LS = A(12, 0, -4), RS = A(12, 0, 4), LE = A(35), RE = A(35), Neck = A(osc(t, 0.4, ph) * 4, osc(t, 0.23, ph) * 12, 0), Waist = A(-3) }), true
end
L.type = function(t, ph)
	local tap = osc(t, 16, ph) * 3
	return sit({ LS = A(38, 0, 6), RS = A(38, 0, -6), LE = A(52 + tap), RE = A(52 - tap), LW = A(-10 + tap), RW = A(-10 - tap), Neck = A(-10, osc(t, 0.3, ph) * 6, 0), Waist = A(-6) }), true
end
L.write = function(t, ph)
	local w = osc(t, 7, ph)
	return sit({ LS = A(30, 0, 8), LE = A(55), RS = A(34 + w * 3, 0, -6), RE = A(62 + w * 4), RW = A(w * 8), Neck = A(-22, 0, 0), Waist = A(-12) }), true
end
L.read = function(t, ph)
	local turn = (t + ph) % 9 < 0.5
	return sit({ LS = A(48, 0, 10), RS = A(48 + (if turn then 12 else 0), 0, -10), LE = A(72), RE = A(72 - (if turn then 20 else 0)), Neck = A(-20, osc(t, 0.2, ph) * 4, 0), Waist = A(-4) }), true
end
L.eat = function(t, ph)
	local c = (t * 0.45 + ph) % 1
	local up = if c < 0.25 then sin(c / 0.25 * math.pi) else 0
	return sit({ LS = A(25, 0, 6), LE = A(50), RS = A(30 + up * 40, 0, -8), RE = A(60 + up * 60), Neck = A(-12 + up * 8), Waist = A(-8) }), true
end
L.drink = function(t, ph)
	local c = (t * 0.25 + ph) % 1
	local up = if c < 0.3 then sin(c / 0.3 * math.pi) else 0
	return sit({ LS = A(15, 0, 4), LE = A(40), RS = A(28 + up * 45, 0, -10), RE = A(80 + up * 55), Neck = A(-4 + up * 12, osc(t, 0.3, ph) * 8, 0) }), true
end
-- chess: think (chin on hand), reach out, pick up a piece, move it across the
-- board, put it down, then sit back with arms folded while the other player thinks
local function chessPhase(t, ph)
	return (t * 0.14 + ph) % 1
end
Poses.ChessPhase = chessPhase
L.chess = function(t, ph)
	local c = chessPhase(t, ph)
	if c < 0.5 then
		-- thinking: elbow on the table, chin on the hand, eyes on the board
		local tap = if (c * 20) % 1 < 0.5 then 4 else 0
		return sit({ LS = A(58, 0, 14), LE = A(128), LW = A(-10), RS = A(26, 0, -8), RE = A(56 + tap), Neck = A(-22, osc(t, 0.6, ph) * 8, 6), Waist = A(-18) }), true
	elseif c < 0.8 then
		-- the move: reach, lift, carry the piece sideways, set it down
		local k = (c - 0.5) / 0.3
		local reach = sin(math.min(1, k * 1.4) * math.pi * 0.5) * (1 - math.max(0, (k - 0.8) / 0.2))
		local slide = math.clamp((k - 0.35) / 0.35, 0, 1)
		return sit({ LS = A(26, 0, 10), LE = A(60), RS = A(28 + reach * 48, slide * 18, -6), RE = A(64 - reach * 44), RW = A(-reach * 20), Neck = A(-28, slide * 10, 0), Waist = A(-18 - reach * 6) }), true
	end
	-- sitting back, arms folded, watching the other player
	return sit({ LS = A(44, 0, 26), RS = A(44, 0, -26), LE = A(112), RE = A(116), Neck = A(-14, osc(t, 0.4, ph) * 6, 0), Waist = A(-4) }), true
end
L.knit = function(t, ph)
	local k = osc(t, 9, ph) * 4
	return sit({ LS = A(42, 0, 12), RS = A(42, 0, -12), LE = A(78 + k), RE = A(78 - k), Neck = A(-22), Waist = A(-5) }), true
end
L.swingsit = function(t, ph)
	local leg = osc(t, 2.1, ph) * 20
	return { LH = A(80 + leg, 0, -4), RH = A(80 + leg, 0, 4), LK = A(-70 + leg), RK = A(-70 + leg), LS = A(160, 0, -8), RS = A(160, 0, 8), LE = A(15), RE = A(15), Neck = A(8 - leg * 0.3) }, true
end
L.sleep = function(t, ph)
	local b = osc(t, 1.3, ph) * 2
	return { Waist = A(b * 0.5), LS = A(5, 0, -8), RS = A(5, 0, 8), LE = A(15), RE = A(15), Neck = A(b * 0.3, 20, 0), LH = A(2, 0, -3), RH = A(2, 0, 3) }, true
end
L.ko = function(t, ph)
	-- out cold, still breathing
	local b = osc(t, 1.6, ph) * 2
	return { LS = A(10, 0, -75), RS = A(10, 0, 70), LE = A(20), RE = A(35), LH = A(4, 0, -14), RH = A(12, 0, 12), RK = A(-25), Neck = A(b * 0.5, 35, 10), Waist = A(b) }, true
end
L.counter = function(t, ph)
	local look = osc(t, 0.25, ph) * 18
	return { LS = A(34, 0, 10), RS = A(34, 0, -10), LE = A(42), RE = A(42), Neck = A(-6, look, 0), Waist = A(-6, look * 0.2, 0) }, true
end
L.cashier = function(t, ph)
	local scan = osc(t, 3, ph)
	return { LS = A(36, 0, 10), LE = A(58), RS = A(40, scan * 15, -8), RE = A(62), RW = A(0, scan * 20, 0), Neck = A(-14, scan * 6, 0), Waist = A(-6) }, true
end
L.cook = function(t, ph)
	local a = t * 4 + ph
	return { LS = A(40, 0, 10), LE = A(60), RS = A(42 + sin(a) * 8, 0, -10 + cos(a) * 8), RE = A(70 + cos(a) * 8), Neck = A(-22), Waist = A(-8) }, true
end
L.knead = function(t, ph)
	local push = (osc(t, 3.2, ph) + 1) / 2
	return { LS = A(40 + push * 18, 0, 8), RS = A(40 + push * 18, 0, -8), LE = A(55 - push * 30), RE = A(55 - push * 30), Waist = A(-10 - push * 10), Neck = A(-20) }, true
end
L.brew = function(t, ph)
	local c = (t * 0.3 + ph) % 1
	local lift = if c < 0.3 then sin(c / 0.3 * math.pi) else 0
	return { LS = A(34, 0, 8), LE = A(55), RS = A(40 + lift * 25, 0, -8), RE = A(70 + lift * 20), Neck = A(-16, osc(t, 0.4, ph) * 12, 0) }, true
end
L.carry = function(t, ph)
	return { LS = A(58, 0, 14), RS = A(58, 0, -14), LE = A(62), RE = A(62), Neck = A(osc(t, 0.3, ph) * 4) }, false
end
L.teach = function(t, ph)
	local c = (t * 0.12 + ph) % 1
	if c < 0.5 then
		-- writing on the board
		local w = osc(t, 5, ph)
		return { RS = A(118 + w * 8, 0, -8 + w * 10), RE = A(18), LS = A(10, 0, -6), LE = A(20), Neck = A(12, 0, 0) }, true
	end
	-- talking to the class
	local g = osc(t, 2.4, ph)
	return { RS = A(44 + g * 14, 0, -18), RE = A(58 + g * 18), LS = A(26 - g * 8, 0, 12), LE = A(52), Neck = A(g * 4, osc(t, 0.35, ph) * 28, 0) }, true
end
L.clipboard = function(t, ph)
	local w = osc(t, 6, ph)
	return { LS = A(44, 0, 10), LE = A(88), RS = A(40, 0, -8), RE = A(76 + w * 6), RW = A(w * 10), Neck = A(-18, osc(t, 0.3, ph) * 6, 0) }, true
end
L.guard = function(t, ph)
	return { LS = A(34, 0, 22), RS = A(34, 0, -22), LE = A(108), RE = A(104), LH = A(0, 0, -6), RH = A(0, 0, 6), Neck = A(0, osc(t, 0.22, ph) * 35, 0) }, true
end
L.machine = function(t, ph)
	local w = osc(t, 4, ph)
	return { LS = A(46 + w * 6, 0, 12), RS = A(50 - w * 6, 0, -12), LE = A(40 + w * 8), RE = A(40 - w * 8), Waist = A(-14), Neck = A(-16) }, true
end
L.crouchwork = function(t, ph)
	local w = osc(t, 5, ph)
	return { LH = A(80, 0, -12), RH = A(80, 0, 12), LK = A(-120), RK = A(-120), LA = A(40), RA = A(40), Waist = A(-28), LS = A(60, 0, 10), RS = A(62 + w * 8, 0, -10), LE = A(20), RE = A(28 + w * 12), Neck = A(-10) }, true
end
L.kneelwork = L.crouchwork
L.sweep = function(t, ph)
	local s = osc(t, 2.6, ph)
	return { LS = A(34, s * 10, 16), RS = A(48, s * 10, -20), LE = A(45), RE = A(30), Waist = A(-8, s * 18, 0), Neck = A(-18, s * 10, 0) }, true
end
L.shelve = function(t, ph)
	local c = (t * 0.35 + ph) % 1
	local reach = if c < 0.5 then sin(c / 0.5 * math.pi) else 0
	return { RS = A(60 + reach * 70, 0, -6), RE = A(40 - reach * 30), LS = A(50, 0, 10), LE = A(60), Neck = A(reach * 20, osc(t, 0.3, ph) * 10, 0) }, true
end
L.guitar = function(t, ph)
	local s = osc(t, 11, ph)
	return { LS = A(36, 30, -22), LE = A(96), RS = A(28, 0, -10), RE = A(58 + s * 10), RW = A(s * 16), Neck = A(-14 + osc(t, 1.8, ph) * 6, 0, osc(t, 0.9, ph) * 10), Waist = A(0, 0, osc(t, 1.8, ph) * 3) }, true
end
L.cheer = function(t, ph)
	local b = abs(osc(t, 6, ph))
	return { LS = A(160 + b * 10, 0, -22), RS = A(160 + b * 10, 0, 22), LE = A(20 - b * 15), RE = A(20 - b * 15), Root = CFrame.new(0, b * 0.5, 0), Neck = A(12) }, true
end
L.boo = function(t, ph)
	local s = osc(t, 14, ph) * 4
	return { LS = A(48 + s, 0, 10), RS = A(48 - s, 0, -10), LE = A(22), RE = A(22), LW = A(0, 90, 0), RW = A(0, -90, 0), Waist = A(-6), Neck = A(-8, 0, s) }, false
end
L.present = function(t, ph)
	local g = osc(t, 2, ph)
	return { RS = A(50 + g * 20, 0, -24 - g * 10), RE = A(40 + g * 20), LS = A(20, 0, 8), LE = A(34), Neck = A(g * 3, osc(t, 0.4, ph) * 25, 0) }, true
end
L.run = function(t, ph)
	local s = osc(t, 11, ph)
	return { LH = A(s * 42), RH = A(-s * 42), LK = A(-45 - math.max(0, -s) * 55), RK = A(-45 - math.max(0, s) * 55), LS = A(-s * 40), RS = A(s * 40), LE = A(88), RE = A(88), Root = CFrame.new(0, abs(s) * 0.25, 0), Waist = A(-8), Neck = A(4) }, true
end
L.curl = function(t, ph)
	local c = (osc(t, 2.6, ph) + 1) / 2
	local c2 = (osc(t, 2.6, ph + math.pi) + 1) / 2
	return { LS = A(8, 0, -4), RS = A(8, 0, 4), LE = A(15 + c * 120), RE = A(15 + c2 * 120), Neck = A(4), Waist = A(3) }, true
end
L.squat = function(t, ph)
	local d = (osc(t, 1.9, ph) + 1) / 2
	return { LH = A(d * 95, 0, -10), RH = A(d * 95, 0, 10), LK = A(-d * 110), RK = A(-d * 110), LA = A(d * 25), RA = A(d * 25), Waist = A(-d * 30), Root = CFrame.new(0, -d * 1.3, 0), LS = A(10, 0, -85), RS = A(10, 0, 85), LE = A(95), RE = A(95), Neck = A(6) }, true
end
L.punch = function(t, ph)
	local c = (t * 2.4 + ph) % 1
	local r = if c < 0.2 then sin(c / 0.2 * math.pi) else 0
	local l = if c > 0.5 and c < 0.7 then sin((c - 0.5) / 0.2 * math.pi) else 0
	return { LS = A(60 + l * 30, 0, 18), LE = A(110 - l * 100), RS = A(60 + r * 30, 0, -18), RE = A(110 - r * 100), Waist = A(-6, (r - l) * 20, 0), LH = A(-10), RH = A(18), RK = A(-18), Root = CFrame.new(0, abs(osc(t, 6, ph)) * 0.15, 0) }, true
end
L.yoga = function(t, ph)
	local b = osc(t, 0.9, ph) * 3
	return { LS = A(170, 0, -8 + b), RS = A(170, 0, 8 - b), LE = A(5), RE = A(5), RH = A(30, 0, 50), RK = A(-120), RA = A(-20), Neck = A(6 + b) }, true
end
L.stretch = function(t, ph)
	local s = osc(t, 0.8, ph)
	return { Waist = A(0, 0, s * 22), LS = A(165, 0, -10), RS = A(if s > 0 then 20 else 165, 0, 10), LE = A(10), RE = A(10), LH = A(0, 0, -10), RH = A(0, 0, 10), Neck = A(0, 0, s * 10) }, true
end
-- paying at the till: holding out a card, a little nod
L.pay = function(t, ph)
	local c = (t * 0.5 + ph) % 1
	local out = if c < 0.4 then sin(c / 0.4 * math.pi) else 0
	return { RS = A(40 + out * 35, 0, -6), RE = A(60 - out * 40), LS = A(10, 0, 6), LE = A(20), Neck = A(-10 + out * 6, 0, 0) }, false
end
-- posting a letter: lean in and push it into the mailbox
L.deliver = function(t, ph)
	local c = (t * 0.6 + ph) % 1
	local push = if c < 0.5 then sin(c / 0.5 * math.pi) else 0
	return { RS = A(50 + push * 35, 0, -6), RE = A(50 - push * 40), LS = A(20, 0, 16), LE = A(40), Waist = A(-10 - push * 10), Neck = A(-10) }, false
end
-- watering: the can tipped forward, swaying over the flowerbed
L.water = function(t, ph)
	local s = osc(t, 1.2, ph)
	return { RS = A(55, s * 20, -10), RE = A(20), RW = A(-40, 0, 0), LS = A(10, 0, 8), LE = A(20), Waist = A(-6, s * 10, 0), Neck = A(-22, s * 8, 0) }, true
end
-- raking: both hands on the handle, pulling toward the feet
L.rake = function(t, ph)
	local p = osc(t, 2.4, ph)
	return { RS = A(40 + p * 20, 0, -12), RE = A(40 - p * 10), LS = A(55 + p * 20, 0, 18), LE = A(50 - p * 10), Waist = A(-14 - p * 6, 10, 0), Neck = A(-20) }, true
end
-- mopping: side to side, bent over a little
L.mop = function(t, ph)
	local s = osc(t, 2, ph)
	return { LS = A(40, s * 14, 20), RS = A(50, s * 14, -20), LE = A(50), RE = A(35), Waist = A(-12, s * 22, 0), Neck = A(-18, s * 10, 0) }, true
end
-- on patrol: standing tall, looking around, talking on the radio now and then
L.patrol = function(t, ph)
	local c = (t * 0.12 + ph) % 1
	local radio = c < 0.25
	return { RS = A(if radio then 70 else 10, 0, if radio then -30 else -6), RE = A(if radio then 115 else 15), LS = A(10, 0, 8), LE = A(15), Neck = A(0, osc(t, 0.35, ph) * 45, 0) }, false
end
-- unpacking shopping: reach into the bag, then up to the cupboard
L.unpack = function(t, ph)
	local c = (t * 0.45 + ph) % 1
	local up = if c < 0.5 then sin(c / 0.5 * math.pi) else 0
	return { LS = A(24, 0, 10), LE = A(40), RS = A(30 + up * 90, 0, -8), RE = A(50 - up * 30), Waist = A(-8 + up * 6), Neck = A(-14 + up * 30) }, false
end
-- carrying things while walking (arms only, the legs keep walking)
L.carryBag = function(t, ph)
	return { RS = A(4, 0, -12), RE = A(8), Neck = nil }, false
end
L.carryCase = function(t, ph)
	return { RS = A(2, 0, -8), RE = A(4) }, false
end
L.carryStraps = function(t, ph)
	-- both thumbs under the backpack straps
	return { LS = A(18, 0, 8), LE = A(95), RS = A(18, 0, -8), RE = A(95) }, false
end
L.carryCup = function(t, ph)
	return { RS = A(30, 0, -8), RE = A(80) }, false
end
L.carryTray = function(t, ph)
	return { RS = A(40, 0, -10), RE = A(80), RW = A(0, 0, 0) }, false
end

L.browse = function(t, ph)
	local look = osc(t, 0.35, ph)
	local c = (t * 0.15 + ph) % 1
	local reach = if c < 0.15 then sin(c / 0.15 * math.pi) else 0
	return { RS = A(20 + reach * 50, 0, -6), RE = A(30 + reach * 20), LS = A(8, 0, -4), LE = A(22), Neck = A(-4 + reach * 12, look * 38, 0), Waist = A(0, look * 10, 0) }, false
end
L.phone = function(t, ph)
	local tap = if (t + ph) % 3 < 1.5 then osc(t, 10, ph) * 4 else 0
	return { RS = A(26, 0, -6), RE = A(112), RW = A(-20 + tap), LS = A(20, 0, 10), LE = A(80), Neck = A(-24) }, false
end
-- hands cuffed behind the back, head down (legs keep walking)
L.cuffed = function(t, ph)
	return { LS = A(-38, 0, 14), RS = A(-38, 0, -14), LE = A(38), RE = A(38), LW = A(0, 40, 0), RW = A(0, -40, 0), Neck = A(-20 + osc(t, 0.5, ph) * 3), Waist = A(-4) }, false
end
-- giving up: hands in the air
L.handsup = function(t, ph)
	local s = osc(t, 7, ph) * 3
	return { LS = A(168, 0, -24 + s), RS = A(168, 0, 24 - s), LE = A(28), RE = A(28), Neck = A(6) }, false
end
-- shaking a spray can at a wall
L.spray = function(t, ph)
	local s, c = osc(t, 3, ph), osc(t, 2.1, ph)
	return { RS = A(88 + s * 12, 0, -8 + c * 14), RE = A(8), RW = A(osc(t, 16, ph) * 6), LS = A(24, 0, 12), LE = A(64), Neck = A(4, c * 8, 0), Waist = A(-2) }, false
end
-- in a cell: arms crossed, shifting from foot to foot
L.jailed = function(t, ph)
	local s = osc(t, 0.35, ph)
	return { LS = A(46, 0, 28), RS = A(46, 0, -28), LE = A(100), RE = A(100), Waist = A(0, 0, s * 3), Neck = A(-14, s * 20, 0) }, false
end
L.paint = function(t, ph)
	local s = osc(t, 2.2, ph)
	return { RS = A(72 + s * 16, 0, -14 + s * 8), RE = A(28 + s * 10), LS = A(34, 0, 18), LE = A(84), Neck = A(0, s * 6, 0), Waist = A(-3) }, true
end
-- fishing, with the whole body: wind up, cast (stepping into it), wait with
-- the line in the water, a bite, reel it in, and hold up the catch
local function fishPhase(t, ph)
	return (t / 14 + ph) % 1
end
Poses.FishPhase = fishPhase
L.fish = function(t, ph)
	local c = fishPhase(t, ph)
	if c < 0.1 then
		-- wind up: rod back over the shoulder, weight on the back foot
		local k = c / 0.1
		return { RS = A(60 + k * 95, 0, -10), RE = A(40 - k * 20), LS = A(45 + k * 80, 0, 14), LE = A(60 - k * 30), Waist = A(k * 12, k * 22, 0), Neck = A(k * 6, -k * 10, 0),
			LH = A(8 - k * 14), RH = A(-4 + k * 16), LK = A(-6), RK = A(-8 - k * 12), Root = CFrame.new(0, -k * 0.1, k * 0.2) }, true
	elseif c < 0.17 then
		-- the cast: arms whip forward, step into it
		local k = (c - 0.1) / 0.07
		return { RS = A(155 - k * 100, 0, -10), RE = A(20 + k * 20), LS = A(125 - k * 80, 0, 14), LE = A(30 + k * 30), Waist = A(12 - k * 24, 22 - k * 30, 0), Neck = A(6 - k * 12, 0, 0),
			LH = A(-6 + k * 22), RH = A(12 - k * 20), LK = A(-6 - k * 10), RK = A(-20 + k * 10), Root = CFrame.new(0, -0.1, 0.2 - k * 0.4) }, true
	elseif c < 0.76 then
		-- waiting: rod held out, the tip bobbing, weight shifting now and then
		local bob = osc(t, 1.3, ph) * 3
		local shift = osc(t, 0.35, ph)
		return { RS = A(55 + bob, 0, -8), RE = A(40), LS = A(46 + bob, 0, 14), LE = A(62), Neck = A(-10, osc(t, 0.2, ph) * 12, 0), Waist = A(-4, 0, shift * 2),
			LH = A(6 + shift * 3), RH = A(-2 - shift * 3), LK = A(-6 - math.max(0, shift) * 6), RK = A(-6 - math.max(0, -shift) * 6), Root = CFrame.new(0, 0, 0) * A(0, 0, shift * 2) }, true
	elseif c < 0.8 then
		-- a bite! yank the rod up
		local k = sin((c - 0.76) / 0.04 * math.pi)
		return { RS = A(55 + k * 45, 0, -8), RE = A(40 - k * 20), LS = A(46 + k * 40, 0, 14), LE = A(62 - k * 20), Waist = A(k * 14), Neck = A(k * 10),
			LH = A(-k * 8), RH = A(k * 8), LK = A(-10), RK = A(-10) }, true
	elseif c < 0.94 then
		-- reeling in: the right hand winds, leaning back
		local wind = osc(t, 14, ph)
		return { RS = A(62 + wind * 8, wind * 10, -14), RE = A(70 + wind * 20), LS = A(70, 0, 14), LE = A(40), Waist = A(10), Neck = A(-4),
			LH = A(-6), RH = A(10), LK = A(-12), RK = A(-16), Root = CFrame.new(0, -0.1, 0.15) }, true
	end
	-- holding up the catch, proud
	local b = abs(osc(t, 6, ph))
	return { LS = A(120 + b * 10, 0, 20), LE = A(20), RS = A(50, 0, -10), RE = A(40), Neck = A(10, 20, 0), Waist = A(6), Root = CFrame.new(0, b * 0.1, 0) }, true
end
L.binoculars = function(t, ph)
	local pan = osc(t, 0.3, ph)
	return { LS = A(90, 0, 26), RS = A(90, 0, -26), LE = A(140), RE = A(140), Neck = A(12, pan * 40, 0), Waist = A(4, pan * 15, 0) }, true
end
L.dance = function(t, ph)
	local s = osc(t, 5, ph)
	local c = osc(t, 2.5, ph)
	return { LS = A(40 + s * 50, 0, -30 - c * 20), RS = A(40 - s * 50, 0, 30 - c * 20), LE = A(60 + c * 30), RE = A(60 - c * 30), LH = A(s * 15), RH = A(-s * 15), LK = A(-abs(s) * 25), RK = A(-abs(c) * 25), Waist = A(0, c * 22, s * 6), Root = CFrame.new(0, abs(s) * 0.4, 0) * A(0, c * 10, 0), Neck = A(s * 6, -c * 10, 0) }, true
end
L.arcade = function(t, ph)
	local j = osc(t, 18, ph) * 3
	return { LS = A(46, 0, 10), RS = A(46, 0, -10), LE = A(52 + j), RE = A(52 - j), LW = A(j * 3), RW = A(-j * 3), Neck = A(-4), Waist = A(-6, 0, osc(t, 1.2, ph) * 4) }, true
end
L.talk = function(t, ph)
	local g = osc(t, 2.8, ph)
	return { RS = A(26 + g * 16, 0, -10), RE = A(52 + g * 26), LS = A(14 - g * 6, 0, 8), LE = A(34 + g * 10), Neck = A(g * 4, osc(t, 0.7, ph) * 8, 0) }, false
end
L.listen = function(t, ph)
	local nod = if (t + ph) % 4 < 0.6 then osc(t, 9, ph) * 6 else 0
	return { Neck = A(-4 + nod, 0, 6), LS = A(8, 0, -3), RS = A(8, 0, 3), LE = A(18), RE = A(18) }, false
end
L.shoot = function(t, ph)
	local c = (t / 3.2 + ph) % 1
	if c < 0.45 then
		-- dribbling
		local d = abs(osc(t, 9, ph))
		return { RS = A(40 + d * 10, 0, -14), RE = A(40 + d * 30), LS = A(20, 0, 10), LE = A(30), LH = A(20), RH = A(10), LK = A(-25), RK = A(-20), Waist = A(-10) }, true
	elseif c < 0.62 then
		-- the jump shot
		local k = (c - 0.45) / 0.17
		return { RS = A(80 + k * 80, 0, -6), RE = A(110 - k * 100), RW = A(-k * 40), LS = A(80 + k * 70, 0, 6), LE = A(100 - k * 80), Root = CFrame.new(0, sin(k * math.pi) * 1.2, 0), Neck = A(20) }, true
	end
	return { RS = A(150, 0, -6), RE = A(10), RW = A(-50), LS = A(40, 0, 10), LE = A(40), Neck = A(20) }, true
end
L.playsit = function(t, ph)
	local p = osc(t, 3, ph)
	return { LH = A(90, 0, -12), RH = A(90, 0, 12), LK = A(-20), RK = A(-20), LS = A(40 + p * 20, 0, 10), RS = A(40 - p * 20, 0, -10), LE = A(40), RE = A(40), Neck = A(-15, p * 10, 0) }, true
end
L.crawl = L.playsit
L.wave = function(t, ph)
	local w = osc(t, 9, ph)
	return { RS = A(20, 0, 150), RE = A(10 + w * 25), RW = A(0, 0, w * 10), Neck = A(4, 0, -4) }, false
end
L.point = function(t, ph)
	-- pointing the way, with a little "over there" wag
	local w = osc(t, 3, ph) * 5
	return { RS = A(95 + w * 0.4, w, -12), RE = A(4), LS = A(10, 0, 8), LE = A(20), Neck = A(0, -10 + w, 0) }, false
end
-- waiting: shifting weight, checking the time now and then
L.wait = function(t, ph)
	local c = (t * 0.08 + ph) % 1
	local look = if c < 0.12 then sin(c / 0.12 * math.pi) else 0
	local sway = osc(t, 0.7, ph)
	return { LS = A(look * 60, 0, 6), LE = A(look * 100), LW = A(0, look * 50, 0), Neck = A(-look * 25, osc(t, 0.25, ph) * 14, 0), Waist = A(0, 0, sway * 2) }, false
end
L.scared = function(t, ph)
	local tr = osc(t, 30, ph) * 2
	return { LS = A(100 + tr, 0, 30), RS = A(100 - tr, 0, -30), LE = A(128), RE = A(128), Waist = A(-10 + tr), LK = A(-14), RK = A(-14), LH = A(8), RH = A(8) }, false
end
L.kick = function(t, ph, k)
	return { RH = A(-30 + k * 110), RK = A(-50 + k * 50), LS = A(-20), RS = A(30, 0, 20), Waist = A(-8) }, false
end
-- blocking: both forearms up in front of the face, hunched, braced
L.block = function(t, ph, shake)
	local s = (shake or 0) * osc(t, 40, ph) * 6
	return { LS = A(96 + s, 0, 30), LE = A(128), LW = A(0, 20, 0), RS = A(100 - s, 0, -28), RE = A(130), RW = A(0, -20, 0), Waist = A(-14), Neck = A(-10), Root = CFrame.new(0, -0.15, 0) }, false
end
-- swinging a bat or hammer: wind up over the shoulder, then chop down across
L.chop = function(t, ph, k)
	local up = if k < 0.35 then k / 0.35 else 1 - (k - 0.35) / 0.65
	local down = if k < 0.35 then 0 else (k - 0.35) / 0.65
	return { RS = A(60 + up * 110 - down * 40, 0, -20 - down * 10), RE = A(40 - up * 20), RW = A(-95 * down, 0, 0), LS = A(60 + up * 90 - down * 30, 0, 30), LE = A(60), Waist = A(-4 - down * 16, 20 - down * 45, 0), Neck = A(0, -down * 10, 0) }, false
end
-- a knife: a quick lunge forward
L.stab = function(t, ph, k)
	local out = math.sin(k * math.pi)
	return { RS = A(70 + out * 25, 0, -6), RE = A(90 - out * 88), RW = A(-85 * out, 0, 0), LS = A(40, 0, 20), LE = A(90), Waist = A(-8 - out * 10, -out * 22, 0), RH = A(-out * 20), LK = A(-out * 20) }, false
end
-- eating: hand to mouth, again and again
L.eat = function(t, ph)
	local bite = (math.sin(t * 4 + ph) + 1) / 2
	return { RS = A(40 + bite * 50, 0, -24), RE = A(80 + bite * 55), RW = A(0, 30, 0), LS = A(20, 0, 10), LE = A(40), Neck = A(-4 + bite * 6) }, false
end
-- sprinting: lean into it
L.sprint = function(t, ph)
	return { Waist = A(-12), Neck = A(8) }, false
end
--------------------------------------------------------------------------------
-- Fighting. Every move has a wind-up, the strike and a recovery (k runs 0 -> 1
-- over the move), and uses the whole body: the hips turn, the back foot
-- pivots and the weight shifts forward into the hit.
--------------------------------------------------------------------------------
-- 0 -> 1 -> 0 over the move, peaking at `at`
local function snap(k, at)
	at = at or 0.35
	if k < at then
		local u = k / at
		return u * u * (3 - 2 * u)
	end
	local u = (k - at) / (1 - at)
	return (1 - u) * (1 - u)
end
-- the wind-up before the strike (pulling back), 0 -> 1 -> 0 over the first part
local function windup(k, at)
	at = at or 0.35
	if k >= at then
		return 0
	end
	return math.sin(k / at * math.pi)
end

-- the legs of a fighting stance: left foot forward, knees bent, hips turned
local function stance(p, t, ph, still)
	if still then
		local b = abs(osc(t, 7, ph))
		p.LH = p.LH or A(22, 0, -8)
		p.LK = p.LK or A(-26 - b * 6)
		p.RH = p.RH or A(-14, 0, 8)
		p.RK = p.RK or A(-22 - b * 6)
		p.LA = p.LA or A(4)
		p.RA = p.RA or A(10)
		p.Root = p.Root or (CFrame.new(0, -0.3 - b * 0.08, 0) * A(0, -18, 0))
	end
	return p
end

-- fists up, bobbing and weaving
L.fightguard = function(t, ph, still)
	local b = osc(t, 7, ph)
	local weave = osc(t, 2.3, ph)
	return stance({
		LS = A(64 + b * 3, 0, 16), LE = A(120), LW = A(0, 0, 10),
		RS = A(54 - b * 3, 0, -14), RE = A(124), RW = A(0, 0, -10),
		Waist = A(-8, 18 + weave * 6, weave * 5), Neck = A(10, -14, -weave * 4),
	}, t, ph, still), false
end

-- a quick straight left from the lead hand
L.jab = function(t, ph, k, still)
	local out = snap(k, 0.3)
	return stance({
		LS = A(64 + out * 30, 0, 16 - out * 10), LE = A(120 - out * 112), LW = A(0, 0, 10),
		RS = A(54, 0, -14), RE = A(124), RW = A(0, 0, -10),
		Waist = A(-8 - out * 6, 18 + out * 14, 0), Neck = A(10, -14 - out * 8, 0),
	}, t, ph, still), false
end

-- the right cross: the back hand, with the hips and back foot turning into it
local function cross(t, ph, k, still)
	local out, back = snap(k, 0.38), windup(k, 0.3)
	local p = stance({
		LS = A(70, 0, 22), LE = A(128), LW = A(0, 0, 10),
		RS = A(54 - back * 10 + out * 42, 0, -14 + out * 8), RE = A(124 + back * 6 - out * 116), RW = A(0, 0, -10),
		Waist = A(-8 - out * 12, 18 + back * 12 - out * 48, 0), Neck = A(10, -14 + out * 26, 0),
	}, t, ph, still)
	if still then
		p.RH = A(-14 + out * 10, 0, 8)
		p.RA = A(10 + out * 25)
		p.Root = CFrame.new(0, -0.3, -out * 0.35) * A(0, -18 - out * 24, 0)
	end
	return p, false
end
L.cross = cross

-- a left hook: elbow up, the arm swings round with the whole torso
L.hook = function(t, ph, k, still)
	local out, back = snap(k, 0.42), windup(k, 0.35)
	local p = stance({
		LS = A(78 + out * 8, 0, -30 - back * 20 + out * 45), LE = A(95 - out * 10), LW = A(0, 0, 10),
		RS = A(58, 0, -16), RE = A(126), RW = A(0, 0, -10),
		Waist = A(-6, 18 + back * 20 + out * 38 - out * out * 70, -out * 8), Neck = A(8, -12 - out * 20, 0),
	}, t, ph, still)
	if still then
		p.Root = CFrame.new(0, -0.35, 0) * A(0, -18 + back * 10 + out * 30, 0)
		p.LA = A(4 + out * 20)
	end
	return p, false
end

-- an uppercut: dip at the knees, then drive up from the legs
L.uppercut = function(t, ph, k, still)
	local out, dip = snap(k, 0.45), windup(k, 0.4)
	local p = stance({
		LS = A(66, 0, 18), LE = A(124), LW = A(0, 0, 10),
		RS = A(30 - dip * 15 + out * 110, 0, -12), RE = A(110 + dip * 10 - out * 60), RW = A(0, 0, -10),
		Waist = A(-14 * dip + out * 14, 18 - out * 30, 0), Neck = A(10 + out * 10, -10, 0),
	}, t, ph, still)
	if still then
		p.LK = A(-26 - dip * 30 + out * 16)
		p.RK = A(-22 - dip * 30 + out * 16)
		p.LH = A(22 + dip * 14, 0, -8)
		p.RH = A(-14 + dip * 14, 0, 8)
		p.Root = CFrame.new(0, -0.3 - dip * 0.45 + out * 0.2, 0) * A(0, -18 - out * 20, 0)
	end
	return p, false
end

-- a roundhouse kick with the right leg (lean back, arms up to balance)
L.roundhouse = function(t, ph, k)
	local out, chamber = snap(k, 0.45), windup(k, 0.35)
	return {
		RH = A(20 + chamber * 60 + out * 50, 0, out * 45), RK = A(-100 * chamber - 20 * (1 - out) + out * 10 - 10),
		LH = A(8, 0, -6), LK = A(-18), LA = A(10),
		LS = A(70, 0, 30), LE = A(120), RS = A(40, 0, -40 - out * 20), RE = A(80),
		Waist = A(10 * out, -20 * out, -14 * out), Neck = A(4, 22 * out, 10 * out),
		Root = CFrame.new(0, -0.1 + out * 0.15, 0) * A(0, out * 50, 8 * out),
	}, true
end

-- a bat (or hammer) swung flat, like hitting a baseball: wind up behind, follow through
L.batswing = function(t, ph, k, still)
	local wind, out = windup(k, 0.35), snap(k, 0.5)
	local follow = if k > 0.35 then math.min(1, (k - 0.35) / 0.15) * (1 - math.max(0, (k - 0.75) / 0.25)) else 0
	local p = stance({
		RS = A(70 + wind * 20, 0, -30 - wind * 40 + follow * 90), RE = A(60 - follow * 40), RW = A(-85 * follow, 0, 0),
		LS = A(70 + wind * 10, 0, 40 - wind * 20 + follow * 30), LE = A(70 - follow * 30),
		Waist = A(-6 - follow * 8, 40 * wind - 75 * follow, 0), Neck = A(4, -20 * wind + 30 * follow, 0),
	}, t, ph, still)
	if still then
		p.Root = CFrame.new(0, -0.35, -out * 0.25) * A(0, -18 + 25 * wind - 30 * follow, 0)
		p.RA = A(10 + follow * 30)
	end
	return p, false
end

-- a knife slash across the body
L.slash = function(t, ph, k, still)
	local wind, out = windup(k, 0.3), snap(k, 0.4)
	local across = if k > 0.3 then math.min(1, (k - 0.3) / 0.25) * (1 - math.max(0, (k - 0.7) / 0.3)) else 0
	return stance({
		RS = A(80 + wind * 20, 0, -60 * wind + 60 * across), RE = A(40 + wind * 40 - across * 20), RW = A(-70 * across, 0, -20 + across * 40),
		LS = A(50, 0, 24), LE = A(100),
		Waist = A(-8 - out * 8, 30 * wind - 45 * across, 0), Neck = A(6, -10 + across * 18, 0),
	}, t, ph, still), false
end

-- getting hit: the head snaps away from the punch and the body rocks back.
-- side: -1 / 1 which side the hit came from; front: 1 from the front, -1 from behind
L.hitreact = function(t, ph, k, side, front, heavy)
	local e = (1 - k) * (1 - k) * (if heavy then 1.6 else 1)
	local p = {
		Neck = A(24 * e * front, -side * 22 * e, side * 16 * e),
		Waist = A(14 * e * front, -side * 14 * e, side * 10 * e),
		LS = A(30 * e, 0, -24 * e), LE = A(40 * e), RS = A(30 * e, 0, 24 * e), RE = A(40 * e),
	}
	if heavy then
		-- stagger a step back, arms out for balance
		p.LS = A(40 * e, 0, -55 * e)
		p.RS = A(40 * e, 0, 55 * e)
		p.LH = A(-18 * e * front)
		p.RH = A(16 * e * front)
		p.LK = A(-22 * e)
		p.RK = A(-30 * e)
		p.Root = CFrame.new(0, -0.25 * e, 0.4 * e * front) * A(10 * e * front, 0, side * 6 * e)
	end
	return p, false
end

--------------------------------------------------------------------------------
-- Weapons. A tool points the way the hand's palm faces forward, so the
-- forearm's angle aims it: elbow bent 90° = the weapon points up.
--------------------------------------------------------------------------------
-- carrying a weapon around (arms only; the legs keep walking)
L.holdBat = function(t, ph)
	-- resting on the right shoulder
	local sway = osc(t, 1.6, ph) * 3
	return { RS = A(28 + sway, 0, -8), RE = A(128), RW = A(-30, 0, 0), Neck = A(0, 0, 0) }, false
end
L.holdHammer = function(t, ph)
	-- down by the side, head forward, tapping gently
	local tap = osc(t, 2.2, ph) * 4
	return { RS = A(12 + tap, 0, -6), RE = A(30), RW = A(-20 + tap, 0, 0) }, false
end
L.holdKnife = function(t, ph)
	-- low and close, blade forward
	return { RS = A(26, 0, -6), RE = A(60), RW = A(-30, 0, 0), LS = A(10, 0, 6), LE = A(20) }, false
end
-- in a fight with a weapon
L.guardBat = function(t, ph, still)
	-- both hands on the bat, cocked over the back shoulder like a batter
	local b = osc(t, 5, ph) * 3
	return stance({
		RS = A(62 + b, 0, -12), RE = A(118), RW = A(-40, 0, 0),
		LS = A(68 + b, 0, -44), LE = A(112),
		Waist = A(-6, 26, 0), Neck = A(6, -24, 0),
	}, t, ph, still), false
end
L.guardHammer = function(t, ph, still)
	local b = osc(t, 5, ph) * 3
	return stance({
		RS = A(55 + b, 0, -10), RE = A(104), RW = A(-10, 0, 0),
		LS = A(58, 0, -30), LE = A(100),
		Waist = A(-10, 12, 0), Neck = A(10, -10, 0),
	}, t, ph, still), false
end
L.guardKnife = function(t, ph, still)
	-- knife hand forward and low, the other hand up to fend off
	local b = osc(t, 6, ph) * 4
	return stance({
		RS = A(60 + b, 0, -8), RE = A(40), RW = A(-40, 0, 0),
		LS = A(70, 0, 22), LE = A(110), LW = A(0, 0, 10),
		Waist = A(-14, -8, 0), Neck = A(12, 6, 0),
	}, t, ph, still), false
end
-- the hammer: a two-handed overhead slam, the knees dropping into it
L.slam = function(t, ph, k, still)
	local up, down = windup(k, 0.4), snap(k, 0.5)
	local hit = if k > 0.4 then math.min(1, (k - 0.4) / 0.15) else 0
	local recover = math.max(0, (k - 0.7) / 0.3)
	local d = hit * (1 - recover)
	local p = stance({
		RS = A(70 + up * 100 - d * 20, 0, -10), RE = A(80 + up * 20 - d * 70), RW = A(-up * 30 + d * 20, 0, 0),
		LS = A(70 + up * 95 - d * 20, 0, -30 + up * 10), LE = A(80 + up * 20 - d * 60),
		Waist = A(10 * up - 30 * d, 10, 0), Neck = A(-10 * up + 16 * d, -6, 0),
	}, t, ph, still)
	if still then
		p.LK = A(-26 - d * 30)
		p.RK = A(-22 - d * 30)
		p.Root = CFrame.new(0, -0.3 - d * 0.45, -d * 0.2) * A(0, -18, 0)
	end
	return p, false
end
-- pulling a weapon out: from behind the hip, up and round to the front
L.draw = function(t, ph, k)
	local e = 1 - (1 - k) * (1 - k)
	return { RS = A(-40 + e * 80, 0, -20 + e * 10), RE = A(20 + e * 70), RW = A(-40 * (1 - e), 0, 0), Waist = A(0, -12 * (1 - e), 0), Neck = A(-10 * (1 - e), -20 * (1 - e), 0) }, false
end

-- won the fight: a fist pump
L.victory = function(t, ph, k)
	local pump = abs(osc(t, 9, ph))
	return {
		RS = A(155 + pump * 15, 0, -18), RE = A(10 + pump * 30), LS = A(40, 0, 20), LE = A(90), LW = A(0, 0, 10),
		Waist = A(8), Neck = A(14), Root = CFrame.new(0, pump * 0.15, 0),
	}, false
end

-- the punch combo: every swing is the next move in the list (the same on every client)
local COMBO = { "jab", "cross", "hook", "cross", "uppercut" }
local BRAWL_COMBO = { "jab", "cross", "hook", "uppercut", "cross", "roundhouse" }
local MOVE_TIME = { jab = 0.3, cross = 0.38, hook = 0.42, uppercut = 0.46, roundhouse = 0.58, chop = 0.45, batswing = 0.5, stab = 0.34, slash = 0.4, slam = 0.55 }
Poses.Combo = COMBO

-- the move for this swing: weapon, which swing it is, and whether it's a street brawl
local GUARDS = { Bat = L.guardBat, Hammer = L.guardHammer, Knife = L.guardKnife }
local HOLDS = { Bat = L.holdBat, Hammer = L.holdHammer, Knife = L.holdKnife }

local function fightMove(weapon, count, brawl)
	if weapon == "Bat" then
		return if count % 2 == 0 then "batswing" else "chop"
	elseif weapon == "Hammer" then
		return if count % 3 == 0 then "chop" else "slam"
	elseif weapon == "Knife" then
		return if count % 2 == 0 then "stab" else "slash"
	end
	local list = if brawl then BRAWL_COMBO else COMBO
	return list[(count - 1) % #list + 1]
end
Poses.FightMove = fightMove

-- where a hit came from, relative to the one who got hit
local function hitSide(model, root)
	local from = model:GetAttribute("HitFrom")
	if typeof(from) ~= "Vector3" or not root then
		return 1, 1
	end
	local rel = root.CFrame:PointToObjectSpace(from)
	local side = if rel.X >= 0 then 1 else -1
	local front = if rel.Z <= 0 then 1 else -1
	return side, front
end

-- The fight overlay shared by citizens and players. Returns a pose or nil.
--   swingAge: seconds since the last swing; weapon; brawl: a street fight
local function fightPose(model, st, t, now, root, weapon, brawl, fighting, blocking)
	local vel = root and root.AssemblyLinearVelocity
	local still = not vel or Vector3.new(vel.X, 0, vel.Z).Magnitude < 3
	local count = model:GetAttribute("SwingSide") or 0
	local move = fightMove(weapon, count, brawl)
	local dur = MOVE_TIME[move] or 0.4
	local hitAge = now - st.Hit
	local heavy = (model:GetAttribute("HitPower") or 0) >= 20
	if now - st.Swing < dur then
		return L[move](t, st.Phase, (now - st.Swing) / dur, still)
	elseif blocking then
		return L.block(t, st.Phase, math.max(0, 1 - hitAge / 0.4))
	elseif now - st.Block < 0.5 then
		return L.block(t, st.Phase, 1 - (now - st.Block) / 0.5)
	elseif hitAge < (if heavy then 0.6 else 0.4) and not model:GetAttribute("KnockedOut") then
		local side, front = hitSide(model, root)
		return L.hitreact(t, st.Phase, hitAge / (if heavy then 0.6 else 0.4), side, front, heavy)
	elseif now - (st.Won or -99) < 2.2 then
		return L.victory(t, st.Phase, (now - st.Won) / 2.2)
	elseif fighting and not model:GetAttribute("KnockedOut") then
		local guard = GUARDS[weapon] or L.fightguard
		return guard(t, st.Phase, still)
	end
	return nil
end
Poses.FightPose = fightPose

L.idle = nil
L.none = nil

--------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------
local function prop(parent, name, size, cf, color, shape, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = parent.CFrame * cf
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parent
	weld.Part1 = p
	weld.Parent = p
	return p
end

local rgb = Color3.fromRGB
local Ball, Cyl = Enum.PartType.Ball, Enum.PartType.Cylinder
local PROPS = {}
Poses.Props = PROPS
-- each builder: (folder, body parts, scale) -> nothing (parents parts to folder)
PROPS.Cup = function(f, b, s)
	prop(b.RightHand, "Cup", Vector3.new(0.45, 0.55, 0.45) * s, CFrame.new(0, -0.3 * s, -0.25 * s), rgb(245, 245, 240)).Parent = f
end
PROPS.Pan = function(f, b, s)
	prop(b.LeftHand, "Pan", Vector3.new(0.2, 1.4, 1.4) * s, CFrame.new(0, -0.25 * s, -0.9 * s) * A(0, 0, 90), rgb(40, 40, 44), Cyl, Enum.Material.Metal).Parent = f
	prop(b.LeftHand, "PanHandle", Vector3.new(0.15, 0.15, 0.8) * s, CFrame.new(0, -0.25 * s, -0.2 * s), rgb(30, 30, 30)).Parent = f
	prop(b.RightHand, "Spatula", Vector3.new(0.1, 1.1, 0.1) * s, CFrame.new(0, -0.5 * s, -0.2 * s), rgb(150, 110, 70), nil, Enum.Material.Wood).Parent = f
end
PROPS.Tray = function(f, b, s)
	prop(b.RightHand, "Tray", Vector3.new(1.4, 0.1, 1.2) * s, CFrame.new(0, -0.1 * s, -0.5 * s) * A(-60, 0, 0), rgb(200, 200, 205), nil, Enum.Material.Metal).Parent = f
end
PROPS.Chalk = function(f, b, s)
	prop(b.RightHand, "Chalk", Vector3.new(0.1, 0.35, 0.1) * s, CFrame.new(0, -0.35 * s, 0), rgb(250, 250, 250)).Parent = f
end
PROPS.Clipboard = function(f, b, s)
	prop(b.LeftHand, "Clipboard", Vector3.new(0.9, 1.2, 0.08) * s, CFrame.new(0.2 * s, -0.3 * s, -0.25 * s) * A(-60, 0, 0), rgb(150, 110, 70), nil, Enum.Material.Wood).Parent = f
	prop(b.RightHand, "Pen", Vector3.new(0.08, 0.5, 0.08) * s, CFrame.new(0, -0.35 * s, 0), rgb(30, 60, 160)).Parent = f
end
PROPS.Wrench = function(f, b, s)
	prop(b.RightHand, "Wrench", Vector3.new(0.15, 1, 0.3) * s, CFrame.new(0, -0.6 * s, 0), rgb(170, 175, 180), nil, Enum.Material.Metal).Parent = f
end
PROPS.Box = function(f, b, s)
	prop(b.Torso, "Box", Vector3.new(1.6, 1.3, 1.3) * s, CFrame.new(0, -0.1 * s, -1.3 * s), rgb(190, 150, 100), nil, Enum.Material.WoodPlanks).Parent = f
end
PROPS.Broom = function(f, b, s)
	prop(b.RightHand, "Broom", Vector3.new(0.15, 4.2, 0.15) * s, CFrame.new(0, -0.6 * s, -0.3 * s) * A(-30, 0, 20), rgb(150, 110, 70), nil, Enum.Material.Wood).Parent = f
	prop(b.RightHand, "Bristles", Vector3.new(1.2, 0.5, 0.4) * s, CFrame.new(0.7 * s, -2.4 * s, -1.2 * s) * A(-30, 0, 20), rgb(210, 180, 100)).Parent = f
end
PROPS.Trowel = function(f, b, s)
	prop(b.RightHand, "Trowel", Vector3.new(0.3, 0.7, 0.1) * s, CFrame.new(0, -0.5 * s, 0), rgb(160, 165, 170), nil, Enum.Material.Metal).Parent = f
end
PROPS.Guitar = function(f, b, s)
	prop(b.Torso, "GuitarBody", Vector3.new(1.4, 1.7, 0.4) * s, CFrame.new(0.2 * s, -0.5 * s, -0.8 * s) * A(0, 0, 30), rgb(170, 90, 40), nil, Enum.Material.Wood).Parent = f
	prop(b.Torso, "GuitarNeck", Vector3.new(0.25, 2, 0.2) * s, CFrame.new(-0.9 * s, 0.5 * s, -0.8 * s) * A(0, 0, 60), rgb(60, 40, 25), nil, Enum.Material.Wood).Parent = f
end
PROPS.Letter = function(f, b, s)
	prop(b.RightHand, "Letter", Vector3.new(0.6, 0.05, 0.4) * s, CFrame.new(0, -0.3 * s, -0.2 * s), rgb(250, 245, 230)).Parent = f
end
PROPS.CaughtFish = function(f, b, s)
	local fish = prop(b.LeftHand, "CaughtFish", Vector3.new(0.3, 0.7, 1.6) * s, CFrame.new(0, -0.9 * s, -0.2 * s), rgb(110, 150, 170), nil, Enum.Material.SmoothPlastic)
	fish.Parent = f
	local tail = prop(b.LeftHand, "CaughtFishTail", Vector3.new(0.2, 0.6, 0.5) * s, CFrame.new(0, -0.9 * s, 0.75 * s), rgb(90, 130, 150))
	tail.Parent = f
end
PROPS.ChessPiece = function(f, b, s)
	local piece = prop(b.RightHand, "ChessPiece", Vector3.new(0.28, 0.4, 0.28) * s, CFrame.new(0, -0.45 * s, -0.1 * s), rgb(245, 240, 228))
	piece.Parent = f
end
PROPS.Binoculars = function(f, b, s)
	for _, x in ipairs({ -0.22, 0.22 }) do
		local lens = prop(b.RightHand, "Binoculars", Vector3.new(0.7, 0.34, 0.34) * s, CFrame.new(x * s - 0.3 * s, -0.25 * s, -0.3 * s) * A(0, 90, 0), rgb(40, 44, 40), Cyl, Enum.Material.Metal)
		lens.Parent = f
	end
end
PROPS.Popcorn = function(f, b, s)
	prop(b.LeftHand, "PopcornTub", Vector3.new(0.8, 1, 0.8) * s, CFrame.new(0, -0.6 * s, -0.3 * s), rgb(220, 40, 50)).Parent = f
	prop(b.LeftHand, "Popcorn", Vector3.new(0.75, 0.3, 0.75) * s, CFrame.new(0, -0.05 * s, -0.3 * s), rgb(255, 240, 190), Ball).Parent = f
end
PROPS.Whistle = function(f, b, s)
	prop(b.Torso, "Whistle", Vector3.new(0.25, 0.3, 0.12) * s, CFrame.new(0, 0.2 * s, -0.55 * s), rgb(200, 204, 210), nil, Enum.Material.Metal).Parent = f
end

PROPS.Card = function(f, b, s)
	prop(b.RightHand, "Card", Vector3.new(0.5, 0.04, 0.32) * s, CFrame.new(0, -0.3 * s, -0.25 * s), rgb(60, 110, 200)).Parent = f
end
PROPS.MailBag = function(f, b, s)
	prop(b.Torso, "MailBag", Vector3.new(0.5, 1.1, 1.3) * s, CFrame.new(-1.25 * s, -1.1 * s, 0), rgb(60, 80, 150), nil, Enum.Material.Fabric).Parent = f
	prop(b.Torso, "MailStrap", Vector3.new(0.12, 2.6, 0.12) * s, CFrame.new(-0.2 * s, 0, -0.52 * s) * A(0, 0, -40), rgb(50, 60, 110), nil, Enum.Material.Fabric).Parent = f
end
PROPS.WateringCan = function(f, b, s)
	prop(b.RightHand, "WateringCan", Vector3.new(0.7, 0.8, 1) * s, CFrame.new(0, -0.6 * s, -0.3 * s), rgb(60, 160, 90), nil, Enum.Material.Metal).Parent = f
	prop(b.RightHand, "Spout", Vector3.new(0.15, 0.15, 0.9) * s, CFrame.new(0, -0.5 * s, -1.1 * s) * A(-20, 0, 0), rgb(50, 140, 80), nil, Enum.Material.Metal).Parent = f
end
PROPS.Rake = function(f, b, s)
	prop(b.RightHand, "RakeHandle", Vector3.new(0.14, 4.6, 0.14) * s, CFrame.new(0, -0.8 * s, -0.4 * s) * A(-35, 0, 0), rgb(150, 110, 70), nil, Enum.Material.Wood).Parent = f
	prop(b.RightHand, "RakeHead", Vector3.new(1.4, 0.15, 0.4) * s, CFrame.new(0, -2.7 * s, -1.8 * s) * A(-35, 0, 0), rgb(120, 124, 130), nil, Enum.Material.Metal).Parent = f
end
PROPS.Mop = function(f, b, s)
	prop(b.RightHand, "MopHandle", Vector3.new(0.14, 4.4, 0.14) * s, CFrame.new(0, -0.7 * s, -0.4 * s) * A(-30, 0, 15), rgb(90, 140, 200), nil, Enum.Material.Metal).Parent = f
	prop(b.RightHand, "MopHead", Vector3.new(1, 0.4, 0.7) * s, CFrame.new(0.5 * s, -2.6 * s, -1.5 * s) * A(-30, 0, 15), rgb(230, 230, 220), nil, Enum.Material.Fabric).Parent = f
end
PROPS.Radio = function(f, b, s)
	prop(b.RightHand, "Radio", Vector3.new(0.3, 0.6, 0.2) * s, CFrame.new(0, -0.35 * s, -0.15 * s), rgb(30, 30, 34)).Parent = f
	prop(b.RightHand, "Antenna", Vector3.new(0.05, 0.35, 0.05) * s, CFrame.new(0.08 * s, -0.8 * s, -0.15 * s), rgb(20, 20, 20)).Parent = f
end
PROPS.Bag = function(f, b, s)
	prop(b.RightHand, "ShoppingBag", Vector3.new(0.5, 1.1, 0.9) * s, CFrame.new(0, -0.85 * s, 0), rgb(240, 225, 190), nil, Enum.Material.Fabric).Parent = f
	prop(b.RightHand, "Groceries", Vector3.new(0.3, 0.3, 0.3) * s, CFrame.new(0, -0.25 * s, 0.15 * s), rgb(90, 180, 70), Enum.PartType.Ball).Parent = f
	prop(b.RightHand, "Baguette", Vector3.new(0.18, 0.9, 0.18) * s, CFrame.new(0, -0.25 * s, -0.2 * s) * A(12, 0, 0), rgb(210, 160, 90)).Parent = f
end
PROPS.Briefcase = function(f, b, s)
	prop(b.RightHand, "Briefcase", Vector3.new(0.35, 1, 1.4) * s, CFrame.new(0, -0.8 * s, 0), rgb(70, 45, 30), nil, Enum.Material.Leather).Parent = f
end
PROPS.Backpack = function(f, b, s)
	local colors = { rgb(220, 60, 60), rgb(60, 120, 220), rgb(250, 190, 40), rgb(80, 180, 110), rgb(160, 90, 220) }
	local c = colors[(math.floor((b.Torso.Size.X * 1000) + (f:GetFullName():len())) % #colors) + 1]
	prop(b.Torso, "Backpack", Vector3.new(1.4, 1.5, 0.7) * s, CFrame.new(0, -0.1 * s, 0.85 * s), c, nil, Enum.Material.Fabric).Parent = f
	prop(b.Torso, "BackpackPocket", Vector3.new(1, 0.6, 0.25) * s, CFrame.new(0, -0.4 * s, 1.3 * s), c:Lerp(Color3.new(0, 0, 0), 0.2), nil, Enum.Material.Fabric).Parent = f
end
PROPS.GymBag = function(f, b, s)
	prop(b.Torso, "GymBag", Vector3.new(0.8, 0.8, 1.8) * s, CFrame.new(1.3 * s, -1.2 * s, 0) * A(90, 0, 0), rgb(40, 40, 46), Enum.PartType.Cylinder, Enum.Material.Fabric).Parent = f
	prop(b.Torso, "GymStrap", Vector3.new(0.12, 2.6, 0.12) * s, CFrame.new(0.3 * s, -0.1 * s, -0.52 * s) * A(0, 0, 40), rgb(200, 60, 60), nil, Enum.Material.Fabric).Parent = f
end
PROPS.Pastry = function(f, b, s)
	prop(b.RightHand, "PastryBag", Vector3.new(0.5, 0.7, 0.35) * s, CFrame.new(0, -0.5 * s, -0.15 * s), rgb(230, 210, 170)).Parent = f
end
PROPS.Cone = function(f, b, s)
	prop(b.RightHand, "Cone", Vector3.new(0.35, 0.7, 0.35) * s, CFrame.new(0, -0.3 * s, -0.25 * s), rgb(220, 170, 100)).Parent = f
	prop(b.RightHand, "Scoop", Vector3.new(0.5, 0.5, 0.5) * s, CFrame.new(0, 0.15 * s, -0.25 * s), rgb(250, 180, 210), Enum.PartType.Ball).Parent = f
end

PROPS.Dumbbells = function(f, b, s)
	for _, hand in ipairs({ b.LeftHand, b.RightHand }) do
		prop(hand, "Dumbbell", Vector3.new(1.1, 0.2, 0.2) * s, CFrame.new(0, -0.3 * s, 0), rgb(60, 60, 66), nil, Enum.Material.Metal).Parent = f
		for _, x in ipairs({ -0.5, 0.5 }) do
			prop(hand, "Plate", Vector3.new(0.25, 0.55, 0.55) * s, CFrame.new(x * s, -0.3 * s, 0) * A(0, 0, 90), rgb(30, 30, 34), Cyl, Enum.Material.Metal).Parent = f
		end
	end
end
PROPS.Barbell = function(f, b, s)
	prop(b.Torso, "Bar", Vector3.new(6, 0.18, 0.18) * s, CFrame.new(0, 0.9 * s, 0.6 * s), rgb(190, 195, 200), nil, Enum.Material.Metal).Parent = f
	for _, x in ipairs({ -2.6, 2.6 }) do
		prop(b.Torso, "Plate", Vector3.new(0.3, 1.5, 1.5) * s, CFrame.new(x * s, 0.9 * s, 0.6 * s) * A(0, 0, 90), rgb(30, 30, 34), Cyl, Enum.Material.Metal).Parent = f
	end
end
PROPS.Fork = function(f, b, s)
	prop(b.RightHand, "Fork", Vector3.new(0.08, 0.7, 0.08) * s, CFrame.new(0, -0.4 * s, -0.1 * s), rgb(200, 200, 205), nil, Enum.Material.Metal).Parent = f
end
PROPS.Book = function(f, b, s)
	local colors = { rgb(170, 50, 50), rgb(50, 90, 170), rgb(60, 140, 80), rgb(200, 150, 40) }
	prop(b.Torso, "Book", Vector3.new(1.2, 0.15, 0.9) * s, CFrame.new(0, -0.5 * s, -1.25 * s) * A(55, 0, 0), colors[math.random(1, #colors)]).Parent = f
end
PROPS.Pencil = function(f, b, s)
	prop(b.RightHand, "Pencil", Vector3.new(0.08, 0.5, 0.08) * s, CFrame.new(0, -0.35 * s, 0), rgb(250, 200, 50)).Parent = f
end
PROPS.Remote = function(f, b, s)
	prop(b.RightHand, "Remote", Vector3.new(0.25, 0.08, 0.6) * s, CFrame.new(0, -0.3 * s, -0.1 * s), rgb(30, 30, 34)).Parent = f
end
PROPS.Phone = function(f, b, s)
	local phone = prop(b.RightHand, "Phone", Vector3.new(0.4, 0.75, 0.06) * s, CFrame.new(0, -0.35 * s, -0.15 * s) * A(-20, 0, 0), rgb(25, 25, 30))
	phone.Parent = f
	prop(phone, "Screen", Vector3.new(0.34, 0.65, 0.02) * s, CFrame.new(0, 0, -0.04 * s), rgb(120, 190, 255), nil, Enum.Material.Neon).Parent = f
end
PROPS.Cuffs = function(f, b, s)
	for _, hand in ipairs({ b.LeftHand, b.RightHand }) do
		prop(hand, "Cuff", Vector3.new(0.14, 0.5, 0.5) * s, CFrame.new(0, 0.2 * s, 0) * A(0, 0, 90), rgb(190, 194, 200), Cyl, Enum.Material.Metal).Parent = f
	end
	prop(b.RightHand, "Chain", Vector3.new(0.08, 0.08, 0.7) * s, CFrame.new(0, 0.2 * s, 0.25 * s), rgb(160, 164, 170), nil, Enum.Material.Metal).Parent = f
end
PROPS.SprayCan = function(f, b, s)
	local can = prop(b.RightHand, "SprayCan", Vector3.new(0.7, 0.32, 0.32) * s, CFrame.new(0, -0.35 * s, -0.1 * s) * A(0, 0, 90), rgb(230, 60, 110), Cyl, Enum.Material.Metal)
	can.Parent = f
	prop(b.RightHand, "Nozzle", Vector3.new(0.12, 0.12, 0.12) * s, CFrame.new(0, 0.05 * s, -0.1 * s), rgb(240, 240, 240)).Parent = f
end
PROPS.Loot = function(f, b, s)
	prop(b.LeftHand, "Loot", Vector3.new(0.8, 0.7, 0.35) * s, CFrame.new(0, -0.55 * s, 0), rgb(150, 90, 60), nil, Enum.Material.Leather).Parent = f
	prop(b.LeftHand, "LootStrap", Vector3.new(0.6, 0.08, 0.08) * s, CFrame.new(0, -0.15 * s, 0), rgb(110, 70, 45), nil, Enum.Material.Leather).Parent = f
end
PROPS.Brush = function(f, b, s)
	prop(b.RightHand, "Brush", Vector3.new(0.08, 0.9, 0.08) * s, CFrame.new(0, -0.5 * s, -0.1 * s), rgb(150, 110, 70), nil, Enum.Material.Wood).Parent = f
	prop(b.LeftHand, "Palette", Vector3.new(1, 0.08, 0.8) * s, CFrame.new(0, -0.2 * s, -0.3 * s), rgb(220, 190, 140), nil, Enum.Material.Wood).Parent = f
end
PROPS.Rod = function(f, b, s)
	local rod = prop(b.RightHand, "Rod", Vector3.new(0.1, 7, 0.1) * s, CFrame.new(0, -0.3 * s, -3 * s) * A(-65, 0, 0), rgb(60, 60, 64))
	rod.Parent = f
	prop(rod, "Line", Vector3.new(0.03, 6, 0.03) * s, CFrame.new(0, 3.4 * s, 0) * A(65, 0, 0) * CFrame.new(0, -3 * s, 0), rgb(240, 240, 240)).Parent = f
end
PROPS.Knitting = function(f, b, s)
	prop(b.Torso, "Yarn", Vector3.new(0.8, 0.5, 0.6) * s, CFrame.new(0, -0.7 * s, -1.2 * s), rgb(200, 60, 70), nil, Enum.Material.Fabric).Parent = f
	for _, hand in ipairs({ b.LeftHand, b.RightHand }) do
		prop(hand, "Needle", Vector3.new(0.06, 0.9, 0.06) * s, CFrame.new(0, -0.4 * s, -0.1 * s) * A(-40, 0, 0), rgb(200, 200, 205), nil, Enum.Material.Metal).Parent = f
	end
end
PROPS.Basketball = function(f, b, s)
	prop(b.RightHand, "Basketball", Vector3.new(1, 1, 1) * s, CFrame.new(0, -0.55 * s, -0.2 * s), rgb(230, 120, 40), Ball).Parent = f
end

--------------------------------------------------------------------------------
-- Per-citizen state
--------------------------------------------------------------------------------
local JOINTS = {
	Neck = { "Head", "Neck" }, Waist = { "UpperTorso", "Waist" }, Root = { "LowerTorso", "Root" },
	LS = { "LeftUpperArm", "LeftShoulder" }, LE = { "LeftLowerArm", "LeftElbow" }, LW = { "LeftHand", "LeftWrist" },
	RS = { "RightUpperArm", "RightShoulder" }, RE = { "RightLowerArm", "RightElbow" }, RW = { "RightHand", "RightWrist" },
	LH = { "LeftUpperLeg", "LeftHip" }, LK = { "LeftLowerLeg", "LeftKnee" }, LA = { "LeftFoot", "LeftAnkle" },
	RH = { "RightUpperLeg", "RightHip" }, RK = { "RightLowerLeg", "RightKnee" }, RA = { "RightFoot", "RightAnkle" },
}
local IDENTITY = CFrame.new()

local states = {} -- [model] = state
local function stateOf(model)
	local st = states[model]
	if st then
		return st
	end
	st = {
		Motors = {},
		Cur = {},
		Phase = (model:GetAttribute("CitizenId") or math.random(1, 1000)) * 1.618 % (math.pi * 2),
		Face = nil,
		NextBlink = os.clock() + math.random() * 4,
		BlinkUntil = 0,
		Glance = 0,
		LastFaceKey = "",
	}
	for key, path in pairs(JOINTS) do
		local part = model:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		if motor and motor:IsA("Motor6D") then
			st.Motors[key] = motor
		end
	end
	st.Body = {
		RightHand = model:FindFirstChild("RightHand"),
		LeftHand = model:FindFirstChild("LeftHand"),
		Torso = model:FindFirstChild("UpperTorso"),
	}
	st.Kick = 0
	st.Hit = 0
	st.Swing = 0
	st.Block = 0
	model:GetAttributeChangedSignal("Swing"):Connect(function()
		-- our own swing starts right away on our screen; don't restart it when
		-- the server's copy of the same swing arrives a moment later
		if model == localPlayer.Character and os.clock() - st.Swing < 0.25 then
			return
		end
		st.Swing = os.clock()
	end)
	model:GetAttributeChangedSignal("Block"):Connect(function()
		st.Block = os.clock()
	end)
	model:GetAttributeChangedSignal("Kick"):Connect(function()
		st.Kick = os.clock()
	end)
	model:GetAttributeChangedSignal("Hit"):Connect(function()
		st.Hit = os.clock()
	end)
	st.Won = -99
	model:GetAttributeChangedSignal("Won"):Connect(function()
		st.Won = os.clock()
	end)
	-- pulling out a weapon
	model.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			st.Draw = os.clock()
		end
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if st.Props then
				st.Props:Destroy()
			end
			if st.Stars then
				st.Stars:Destroy()
			end
			states[model] = nil
		end
	end)
	states[model] = st
	return st
end

-- what someone carries while walking (the "Carry" attribute, see Errands):
-- the arm pose and the props
local CARRY = {
	Bag = { "carryBag", { "Bag" } }, Briefcase = { "carryCase", { "Briefcase" } }, Backpack = { "carryStraps", { "Backpack" } },
	GymBag = { "carryCase", { "GymBag" } }, MailBag = { "carryCase", { "MailBag", "Letter" } }, Cup = { "carryCup", { "Cup" } },
	Pastry = { "carryCup", { "Pastry" } }, Cone = { "carryCup", { "Cone" } }, WateringCan = { "carryCase", { "WateringCan" } },
	Tray = { "carryTray", { "Tray" } }, Box = { "carry", { "Box" } },
}
Poses.Carry = CARRY

local function setProps(st, model, action, carry)
	local key = if carry then "carry:" .. carry else action
	if st.PropAction == key then
		return
	end
	st.PropAction = key
	if st.Props then
		st.Props:Destroy()
		st.Props = nil
	end
	local info = if carry then { Props = CARRY[carry] and CARRY[carry][2] } else Actions.Get(action or "")
	if not info or not info.Props or not st.Body.RightHand then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "LocalProps"
	local s = model:GetAttribute("Scale") or 1
	for _, name in ipairs(info.Props) do
		local build = PROPS[name]
		if build then
			pcall(build, folder, st.Body, s)
		end
	end
	folder.Parent = model
	st.Props = folder
end

local function setStars(st, model, on)
	if on and not st.Stars then
		local head = model:FindFirstChild("Head")
		if not head then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "KOStars"
		gui.Size = UDim2.fromOffset(90, 40)
		gui.StudsOffset = Vector3.new(0, 1.4, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 90
		gui.Adornee = head
		for k = 1, 3 do
			local star = Instance.new("TextLabel")
			star.Name = "Star" .. k
			star.BackgroundTransparency = 1
			star.Size = UDim2.fromOffset(24, 24)
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.Text = if k == 2 then "💫" else "⭐"
			star.TextScaled = true
			star.Parent = gui
		end
		gui.Parent = head
		st.Stars = gui
	elseif not on and st.Stars then
		st.Stars:Destroy()
		st.Stars = nil
	end
end

-- a basketball flying from the hand to the hoop
local function shootBall(model, target, st)
	local hand = st.Body.RightHand
	if not hand or not target then
		return
	end
	local s = model:GetAttribute("Scale") or 1
	local ball = Instance.new("Part")
	ball.Name = "ShotBall"
	ball.Shape = Ball
	ball.Size = Vector3.new(1, 1, 1) * s
	ball.Color = rgb(230, 120, 40)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Parent = workspace
	local from = hand.Position
	local made = math.random() < 0.55
	local to = target + (if made then Vector3.zero else Vector3.new(math.random(-10, 10) / 10, 0.6, math.random(-10, 10) / 10))
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < 1.6 and ball.Parent do
			local k = (os.clock() - start) / 0.9
			if k <= 1 then
				local p = from:Lerp(to, k) + Vector3.new(0, sin(k * math.pi) * 5, 0)
				ball.CFrame = CFrame.new(p)
			else
				-- falls through the net (or bounces off the rim) to the ground
				local k2 = math.min(1, (k - 1) / 0.7)
				ball.CFrame = CFrame.new(to + Vector3.new(if made then 0 else k2 * 2, -k2 * 8, 0))
			end
			task.wait()
		end
		ball:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- The per-frame update
--------------------------------------------------------------------------------

local function faceUpdate(model, st, t, dt, near, lookYaw)
	local head = model:FindFirstChild("Head")
	local gui = st.Face
	if not gui or not gui.Parent then
		gui = head and head:FindFirstChild("CityFace")
		st.Face = gui
		if not gui then
			return
		end
	end
	local expr = model:GetAttribute("Expression") or "neutral"
	-- blinking every few seconds (not while asleep or knocked out)
	local now = os.clock()
	local blink = 0
	if now >= st.NextBlink then
		st.BlinkUntil = now + 0.13
		st.NextBlink = now + 1.8 + math.random() * 4.5
		if math.random() < 0.15 then
			st.NextBlink = now + 0.35 -- a double blink
		end
	end
	if now < st.BlinkUntil then
		blink = 1
	end
	local talk = 0
	if model:GetAttribute("Talking") then
		talk = math.floor((sin(t * 17 + st.Phase) * 0.5 + 0.5) * 3 + 0.5) / 3
	end
	-- glance toward you, or wander a little
	local glance = if lookYaw then math.clamp(-lookYaw / 50, -1, 1) else sin(t * 0.37 + st.Phase) * 0.35
	glance = math.floor(glance * 4 + 0.5) / 4
	local key = expr .. "|" .. blink .. "|" .. talk .. "|" .. glance
	if key ~= st.LastFaceKey then
		st.LastFaceKey = key
		Faces.Set(gui, expr, blink, talk, glance)
	end
end

--------------------------------------------------------------------------------
-- Checkouts (see CitizenService.TryCheckout): the customer and the clerk go
-- through the sale together, timed off the server clock, and the things being
-- bought move across the counter on every player's screen
--------------------------------------------------------------------------------
local function checkoutK(model)
	local start = model:GetAttribute("CheckoutStart")
	if not start then
		return nil
	end
	local kind = model:GetAttribute("CheckoutKind") or "shop"
	local dur = Actions.CheckoutTime[kind] or 8
	local k = (workspace:GetServerTimeNow() - start) / dur
	if k < 0 or k > 1 then
		return nil
	end
	return k, kind, start
end

-- the customer: unpack the basket, watch, pay by card, take the bag
local function customerPose(t, ph, k, kind)
	if kind == "food" then
		if k < 0.3 then
			return L.talk(t, ph)
		elseif k < 0.5 then
			return L.pay(t, ph)
		elseif k < 0.86 then
			return { LS = A(12, 0, 6), RS = A(12, 0, -6), LE = A(20), RE = A(20), Neck = A(-12, osc(t, 0.5, ph) * 10, 0) }, false
		end
		local r = sin((k - 0.86) / 0.14 * math.pi)
		return { RS = A(30 + r * 45, 0, -6), RE = A(40 - r * 30), Neck = A(-16) }, false
	end
	if k < 0.2 then
		-- putting things on the counter, one hand then the other
		local c = (k / 0.2 * 4) % 1
		local r = sin(c * math.pi)
		local left = math.floor(k / 0.2 * 4) % 2 == 0
		return {
			RS = A(if left then 18 else 18 + r * 58, 0, -8), RE = A(if left then 30 else 72 - r * 44),
			LS = A(if left then 18 + r * 58 else 18, 0, 8), LE = A(if left then 72 - r * 44 else 30),
			Waist = A(-6 - r * 8), Neck = A(-20),
		}, false
	elseif k < 0.6 then
		-- watching the scanner
		return { LS = A(10, 0, 6), RS = A(10, 0, -6), LE = A(24), RE = A(24), Neck = A(-18, osc(t, 1.4, ph) * 12, 0), Waist = A(-3) }, false
	elseif k < 0.8 then
		-- holding the card out to the reader
		local tap = if (k - 0.6) / 0.2 > 0.4 and (k - 0.6) / 0.2 < 0.6 then 1 else 0
		return { RS = A(62 + tap * 10, 0, -6), RE = A(26 - tap * 10), RW = A(-20), LS = A(10, 0, 6), LE = A(20), Neck = A(-14) }, false
	elseif k < 0.9 then
		return { LS = A(10, 0, 6), RS = A(20, 0, -6), LE = A(24), RE = A(60), Neck = A(-8) }, false
	end
	-- taking the bag
	local r = sin((k - 0.9) / 0.1 * math.pi)
	return { RS = A(30 + r * 45, 0, -6), RE = A(40 - r * 30), Neck = A(-14) }, false
end

-- the clerk: say hello, scan every item and bag it, the card reader, hand it over
local function clerkPose(t, ph, k, kind, n)
	if kind == "food" then
		if k < 0.3 then
			return L.listen(t, ph)
		elseif k < 0.5 then
			return { LS = A(58, 0, 12), LE = A(86), LW = A(-30), RS = A(18, 0, -8), RE = A(40), Neck = A(-10) }, false
		elseif k < 0.86 then
			return (L.brew or L.cook)(t, ph)
		end
		local r = sin((k - 0.86) / 0.14 * math.pi)
		return { RS = A(30 + r * 50, 0, -6), RE = A(50 - r * 40), Neck = A(-10) }, false
	end
	if k < 0.2 then
		return L.talk(t, ph)
	elseif k < 0.6 then
		-- each item: reach for it, sweep it over the scanner, drop it in the bag
		local c = ((k - 0.2) / 0.4 * n) % 1
		local reach, sweep, drop
		if c < 0.3 then
			reach, sweep, drop = sin(c / 0.3 * math.pi * 0.5), 0, 0
		elseif c < 0.7 then
			reach, sweep, drop = 1 - (c - 0.3) / 0.4 * 0.5, (c - 0.3) / 0.4, 0
		else
			reach, sweep, drop = 0.5 * (1 - (c - 0.7) / 0.3), 1, sin((c - 0.7) / 0.3 * math.pi)
		end
		return {
			RS = A(40 + reach * 34, -sweep * 30 + (1 - sweep) * 25, -8 - sweep * 20), RE = A(60 - reach * 44), RW = A(-reach * 15),
			LS = A(30, 0, 12), LE = A(60), Waist = A(-8, -sweep * 12 + (1 - sweep) * 8, 0), Neck = A(-20, -sweep * 18 + (1 - sweep) * 12, 0),
			Root = CFrame.new(0, -drop * 0.05, 0),
		}, false
	elseif k < 0.8 then
		-- holding the card reader out
		return { LS = A(62, 0, 12), LE = A(70), LW = A(-30), RS = A(20, 0, -8), RE = A(40), Neck = A(-12) }, false
	elseif k < 0.9 then
		-- tearing off the receipt
		local tug = osc(t, 16, ph)
		return { RS = A(46, 0, -8), RE = A(70 + tug * 8), LS = A(40, 0, 10), LE = A(70), Neck = A(-16) }, false
	end
	-- handing the bag across
	local r = sin((k - 0.9) / 0.1 * math.pi)
	return { RS = A(30 + r * 50, 0, -6), RE = A(50 - r * 40), LS = A(30 + r * 40, 0, 6), LE = A(50 - r * 30), Neck = A(-10) }, false
end

local ITEM_COLORS = { rgb(220, 60, 60), rgb(60, 140, 220), rgb(250, 200, 60), rgb(90, 180, 90), rgb(240, 140, 60), rgb(170, 110, 220), rgb(240, 240, 235) }
local beep = nil
local function playBeep(pos)
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - pos).Magnitude > 45 then
		return
	end
	if not beep then
		beep = Instance.new("Sound")
		beep.Name = "ScannerBeep"
		beep.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		beep.Volume = 0.25
		beep.PlaybackSpeed = 1.6
		beep.Parent = workspace
	end
	pcall(function()
		beep:Play()
	end)
end

local function localPart(parent, name, size, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- the things on the counter (made and moved by each client; the customer's model owns them)
local function checkoutItems(model, st, k, kind, start)
	local co = st.Checkout
	if not k then
		if co then
			co.Folder:Destroy()
			st.Checkout = nil
		end
		return
	end
	local base, look = model:GetAttribute("CheckoutTill"), model:GetAttribute("CheckoutLook")
	if typeof(base) ~= "Vector3" or typeof(look) ~= "Vector3" then
		return
	end
	if not co or co.Start ~= start then
		if co then
			co.Folder:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = "LocalCheckout"
		folder.Parent = workspace
		co = { Start = start, Folder = folder, Items = {}, Beeped = {} }
		local n = if kind == "food" then 1 else (model:GetAttribute("CheckoutItems") or 3)
		for i = 1, n do
			local item
			if kind == "food" then
				item = localPart(folder, "Order", Vector3.new(0.9, 0.5, 0.5), rgb(245, 245, 240), Enum.PartType.Cylinder)
			else
				local sizes = { Vector3.new(0.6, 0.8, 0.4), Vector3.new(0.5, 0.5, 0.5), Vector3.new(0.9, 0.4, 0.6), Vector3.new(0.4, 1, 0.4) }
				item = localPart(folder, "Groceries", sizes[(i - 1) % #sizes + 1], ITEM_COLORS[(i * 3 + math.floor(start)) % #ITEM_COLORS + 1])
			end
			co.Items[i] = item
		end
		if kind ~= "food" then
			co.Bag = localPart(folder, "PaperBag", Vector3.new(1, 1.2, 0.7), rgb(214, 180, 130))
		end
		st.Checkout = co
	end
	local up = Vector3.new(0, 1, 0)
	local right = look:Cross(up) -- the clerk's right
	local C = base + look * 2.4 + Vector3.new(0, 3.85, 0)
	local bagPos = C + right * 1.3 + up * 0.6
	local n = #co.Items
	local hidden = CFrame.new(0, -500, 0)
	if kind == "food" then
		local item = co.Items[1]
		local from, to = C - look * 0.6 + up * 0.25, C + look * 0.9 + up * 0.25
		if k < 0.5 or k > 0.97 then
			item.CFrame = hidden
		elseif k < 0.85 then
			item.CFrame = CFrame.new(from) * CFrame.Angles(0, 0, math.rad(90))
		else
			item.CFrame = CFrame.new(from:Lerp(to, (k - 0.85) / 0.12)) * CFrame.Angles(0, 0, math.rad(90))
		end
		return
	end
	for i, item in ipairs(co.Items) do
		local placed = C + look * 0.55 - right * (0.55 + 0.36 * (i - 1)) + up * (item.Size.Y / 2)
		local appear = 0.2 * (i - 1) / n + 0.02
		local s0, s1 = 0.2 + 0.4 * (i - 1) / n, 0.2 + 0.4 * i / n
		local pos
		if k < appear or k >= s1 then
			pos = nil
		elseif k < s0 then
			pos = placed
		else
			local u = (k - s0) / (s1 - s0)
			local scanner = C + up * (item.Size.Y / 2 + 0.2)
			if u < 0.3 then
				pos = placed:Lerp(scanner, u / 0.3)
			elseif u < 0.7 then
				pos = scanner + right * ((u - 0.3) / 0.4 - 0.5) * 0.4
				if u >= 0.5 and not co.Beeped[i] then
					co.Beeped[i] = true
					playBeep(scanner)
				end
			else
				pos = scanner:Lerp(bagPos + up * 0.4, (u - 0.7) / 0.3)
			end
		end
		item.CFrame = if pos then CFrame.lookAt(pos, pos + look) else hidden
	end
	-- the bag waits by the till, then goes across to the customer
	if k < 0.2 or k > 0.97 then
		co.Bag.CFrame = hidden
	elseif k < 0.9 then
		co.Bag.CFrame = CFrame.lookAt(bagPos, bagPos + look)
	else
		local p = bagPos:Lerp(C + look * 1.8 + up * 0.2, (k - 0.9) / 0.07)
		co.Bag.CFrame = CFrame.lookAt(p, p + look)
	end
end

local function update(model, st, t, dt, camPos, myRoot)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local action = model:GetAttribute("Action") or ""
	local info = Actions.Get(action)
	local poseName = info and info.Pose or action
	if model:GetAttribute("Talking") and (action == "listen" or action == "chat" or action == "wait" or action == "") and not (info and info.Seated) then
		poseName = if action == "" then "" else "talk"
	elseif action == "chat" then
		poseName = if (t + st.Phase) % 7 < 3.5 then "talk" else "listen"
	end
	local now = os.clock()
	local target, full
	-- short overlays: fighting (moves, blocks, hit reactions), a soccer kick
	local brawl = model:GetAttribute("Brawling") ~= nil
	local fighting = model:GetAttribute("Fighting") ~= nil or brawl
	target, full = fightPose(model, st, t, now, root, model:GetAttribute("SwingWeapon") or "Fists", brawl, fighting, false)
	if target then
		-- fighting (see above)
	elseif now - st.Kick < 0.35 then
		target, full = L.kick(t, st.Phase, (now - st.Kick) / 0.35)
	else
		local fn = L[poseName]
		if fn then
			target, full = fn(t, st.Phase)
		end
	end
	-- a living body: when someone stands at a spot doing something with their
	-- arms, their legs and hips shift weight and their chest breathes too
	if target and not full and root.Anchored and not (info and (info.Seated or info.Lying)) then
		local sway = osc(t, 0.9, st.Phase)
		local breath = osc(t, 1.7, st.Phase + 1)
		target.LH = target.LH or A(3 + sway * 3, 0, -3)
		target.RH = target.RH or A(3 - sway * 3, 0, 3)
		target.LK = target.LK or A(-4 - math.max(0, sway) * 7)
		target.RK = target.RK or A(-4 - math.max(0, -sway) * 7)
		target.Root = target.Root or (CFrame.new(0, -abs(sway) * 0.04, 0) * A(0, 0, sway * 2.5))
		target.Waist = target.Waist or A(breath * 1.5, 0, -sway * 1.5)
	end
	-- a checkout in progress: the customer and the clerk play their parts
	local coK, coKind, coStart = checkoutK(model)
	local coRole = coK and model:GetAttribute("CheckoutRole")
	if coK and not fighting then
		if coRole == "customer" then
			target, full = customerPose(t, st.Phase, coK, coKind)
		elseif coRole == "clerk" then
			target, full = clerkPose(t, st.Phase, coK, coKind, model:GetAttribute("CheckoutItems") or 3)
		end
	end
	checkoutItems(model, st, if coRole == "customer" then coK else nil, coKind, coStart)
	-- carrying something on the way (a shopping bag, a briefcase, a backpack...)
	local carry = model:GetAttribute("Carry")
	local carrying = carry and CARRY[carry] and (action == "" or action == "wait") and not target
	if carrying then
		target, full = L[CARRY[carry][1]](t, st.Phase)
	end
	-- look at the player when they're close (or talking to them)
	local lookYaw, lookPitch
	if myRoot and poseName ~= "sleep" and poseName ~= "ko" and poseName ~= "swingsit" then
		local head = model:FindFirstChild("Head")
		local torso = st.Body.Torso
		if head and torso then
			local d = (myRoot.Position + Vector3.new(0, 1.5, 0)) - head.Position
			local talkingToMe = model:GetAttribute("TalkingTo") == localPlayer.UserId
			if d.Magnitude < 16 or talkingToMe then
				local rel = torso.CFrame:VectorToObjectSpace(d)
				local yaw = math.deg(math.atan2(-rel.X, -rel.Z))
				if abs(yaw) < 100 or talkingToMe then
					lookYaw = math.clamp(yaw, -65, 65)
					lookPitch = math.clamp(math.deg(math.atan2(rel.Y, math.sqrt(rel.X ^ 2 + rel.Z ^ 2))), -30, 30)
				end
			end
		end
	end
	if lookYaw then
		target = target or {}
		local base = target.Neck or IDENTITY
		target.Neck = base * A(lookPitch * 0.6, lookYaw, 0)
	end
	-- blend toward the pose
	local a = 1 - math.exp(-dt * 10)
	if target then
		for key, motor in pairs(st.Motors) do
			local goal = target[key] or (if full then IDENTITY else nil)
			if goal then
				local cur = st.Cur[key] or motor.Transform
				cur = cur:Lerp(goal, a)
				st.Cur[key] = cur
				motor.Transform = cur
			else
				st.Cur[key] = nil
			end
		end
	elseif next(st.Cur) then
		table.clear(st.Cur)
	end
	-- props, swings, hoops, stars
	setProps(st, model, action, if carrying then carry else nil)
	local pivot = model:GetAttribute("SwingPivot")
	if pivot and root.Anchored then
		st.SwingBase = st.SwingBase or root.CFrame
		local angle = sin(t * 2.1 + st.Phase) * 0.55
		local axis = st.SwingBase.RightVector
		root.CFrame = CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-pivot) * st.SwingBase
	elseif st.SwingBase then
		st.SwingBase = nil
	end
	if st.Props then
		-- the fish only shows when it's been caught
		local fish = st.Props:FindFirstChild("CaughtFish")
		if fish then
			local showing = fishPhase(t, st.Phase) > 0.94
			fish.Transparency = if showing then 0 else 1
			local tail = st.Props:FindFirstChild("CaughtFishTail")
			if tail then
				tail.Transparency = fish.Transparency
			end
		end
		local piece = st.Props:FindFirstChild("ChessPiece")
		if piece then
			local c = chessPhase(t, st.Phase)
			piece.Transparency = if c > 0.56 and c < 0.76 then 0 else 1
		end
		local card = st.Props:FindFirstChild("Card")
		if card and coK then
			local showing = if coKind == "food" then coK > 0.3 and coK < 0.5 else coK > 0.6 and coK < 0.8
			card.Transparency = if showing then 0 else 1
		elseif card then
			card.Transparency = 0
		end
	end
	if poseName == "shoot" then
		local c = (t / 3.2 + st.Phase) % 1
		local shotBall = st.Props and st.Props:FindFirstChild("Basketball")
		if shotBall then
			shotBall.Transparency = if c > 0.6 then 1 else 0
		end
		if c > 0.6 and not st.Shot then
			st.Shot = true
			shootBall(model, model:GetAttribute("Target"), st)
		elseif c < 0.6 then
			st.Shot = nil
		end
	end
	local ko = model:GetAttribute("KnockedOut") == true
	setStars(st, model, ko)
	if st.Stars then
		for k = 1, 3 do
			local star = st.Stars:FindFirstChild("Star" .. k)
			local ang = t * 3 + k * 2.1
			star.Position = UDim2.new(0.5, cos(ang) * 30, 0.5, sin(ang) * 8)
		end
	end
	return lookYaw
end

-- Call every frame (RunService.PreSimulation)
--------------------------------------------------------------------------------
-- Players: fighting stance, jabs and swings, blocking, eating, the treadmill
--------------------------------------------------------------------------------
local FOOD_COLORS = {
	Croissant = Color3.fromRGB(222, 160, 80), Donut = Color3.fromRGB(240, 130, 180), Coffee = Color3.fromRGB(240, 240, 235), Muffin = Color3.fromRGB(150, 110, 200),
	Burger = Color3.fromRGB(200, 120, 60), Fries = Color3.fromRGB(250, 200, 60), Milkshake = Color3.fromRGB(250, 170, 190), Pasta = Color3.fromRGB(230, 190, 90),
	Pizza = Color3.fromRGB(230, 120, 60), IceCream = Color3.fromRGB(250, 210, 230), Apple = Color3.fromRGB(220, 50, 60), Sandwich = Color3.fromRGB(230, 190, 120), Energy = Color3.fromRGB(60, 220, 120),
}

local function blend(st, target, full, dt)
	local a = 1 - math.exp(-dt * 16)
	if target then
		for key, motor in pairs(st.Motors) do
			local goal = target[key] or (if full then IDENTITY else nil)
			if goal then
				local cur = st.Cur[key] or motor.Transform
				cur = cur:Lerp(goal, a)
				st.Cur[key] = cur
				motor.Transform = cur
			else
				st.Cur[key] = nil
			end
		end
	elseif next(st.Cur) then
		table.clear(st.Cur)
	end
end

-- the swing trail on a weapon: from the grip to the far end of the tool
local function trail(tool, on)
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	local tr = handle:FindFirstChild("SwingTrail")
	if not tr then
		if not on then
			return
		end
		local reach = 0
		for _, part in ipairs(tool:GetChildren()) do
			if part:IsA("BasePart") then
				local y = handle.CFrame:PointToObjectSpace(part.Position).Y + part.Size.Y / 2
				reach = math.max(reach, y)
			end
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailBase"
		a0.Position = Vector3.new(0, reach * 0.35, 0)
		a0.Parent = handle
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailTip"
		a1.Position = Vector3.new(0, reach, 0)
		a1.Parent = handle
		tr = Instance.new("Trail")
		tr.Name = "SwingTrail"
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = 0.18
		tr.FaceCamera = true
		tr.LightEmission = 0.4
		tr.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		tr.Transparency = NumberSequence.new(0.35, 1)
		tr.Enabled = false
		tr.Parent = handle
	end
	if tr.Enabled ~= on then
		tr.Enabled = on
	end
end

local function playerUpdate(model, st, t, dt, player)
	local now = os.clock()
	local target, full
	local tool = model:FindFirstChildOfClass("Tool")
	local holding = tool ~= nil
	local held = tool and tool:GetAttribute("Weapon") or "Fists"
	-- the swing in progress uses the weapon it started with; otherwise what's in hand
	local weapon = if now - st.Swing < 0.6 then (model:GetAttribute("SwingWeapon") or held) else held
	local blocking = model:GetAttribute("Blocking") or (player and player:GetAttribute("Blocking"))
	local eating = model:GetAttribute("Eating")
	if model:GetAttribute("Treadmill") then
		target, full = L.run(t, st.Phase)
	else
		local root = model:FindFirstChild("HumanoidRootPart")
		-- in a fight for 2.5 s after the last swing or hit
		local fighting = now - st.Swing < 2.5 or now - st.Hit < 2.5
		target, full = fightPose(model, st, t, now, root, weapon, false, fighting and not eating, blocking)
	end
	-- working a job (see JobService): the task's animation, then carrying things
	local workAction = model:GetAttribute("WorkAction")
	local carry = model:GetAttribute("Carry")
	local workInfo = workAction and Actions.Get(workAction)
	if not target and workInfo and L[workInfo.Pose] then
		target, full = L[workInfo.Pose](t, st.Phase)
	elseif not target and carry and CARRY[carry] and not holding then
		target, full = L[CARRY[carry][1]](t, st.Phase)
	end
	setProps(st, model, if workInfo then workAction else "", if not workInfo and carry and CARRY[carry] and not holding then carry else nil)
	if target then
		-- fighting, working or carrying (see above)
	elseif holding and now - (st.Draw or -99) < 0.35 then
		target, full = L.draw(t, st.Phase, (now - st.Draw) / 0.35)
	elseif HOLDS[held] and not eating then
		target, full = HOLDS[held](t, st.Phase)
	elseif eating then
		target, full = L.eat(t, st.Phase)
	elseif model:GetAttribute("Sprinting") then
		target, full = L.sprint(t, st.Phase)
	end
	blend(st, target, full, dt)
	-- a streak behind the weapon while it swings
	if tool then
		trail(tool, now - st.Swing < (if weapon == "Hammer" then 0.5 else 0.4))
	end
	-- the food in their hand
	if eating ~= st.EatingProp then
		st.EatingProp = eating
		if st.EatPart then
			st.EatPart:Destroy()
			st.EatPart = nil
		end
		local hand = model:FindFirstChild("RightHand")
		if eating and hand then
			st.EatPart = prop(hand, "Food", Vector3.new(0.55, 0.45, 0.55), CFrame.new(0, -0.4, -0.2), FOOD_COLORS[eating] or Color3.fromRGB(220, 170, 100), if eating == "Apple" or eating == "Donut" then Ball else nil)
			st.EatPart.Parent = model
		end
	end
end

function Poses.StepPlayers(dt, camPos)
	local t = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local model = player.Character
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - camPos).Magnitude < Poses.PoseRadius then
			local st = stateOf(model)
			pcall(playerUpdate, model, st, t, dt, player)
		end
	end
end

function Poses.Step(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	local myRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	for _, model in ipairs(CollectionService:GetTagged("Citizen")) do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - camPos).Magnitude
			if d < Poses.PoseRadius then
				local st = stateOf(model)
				local ok, lookYaw = pcall(update, model, st, t, dt, camPos, myRoot)
				if ok and d < Poses.FaceRadius then
					pcall(faceUpdate, model, st, t, dt, true, lookYaw)
				end
			elseif states[model] then
				-- far away: drop the props to save parts
				setProps(states[model], model, nil)
			end
		end
	end
	Poses.StepPlayers(dt, camPos)
end

return Poses
