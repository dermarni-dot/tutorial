-- Poses (ModuleScript) — ReplicatedStorage.Shared.Poses
-- The client side of citizens' body language. For every citizen near the
-- camera it:
--   • plays the pose for their "Action" attribute (typing, lifting, sitting,
--     sleeping, cheering, fishing...) by setting Motor6D.Transform every frame
--     (smoothly blended, with each person's own rhythm)
--   • puts the right props in their hands (a cup, a book, dumbbells, a rod...)
--   • swings kids on the swings, shoots basketballs at the hoop, kicks the
--     soccer ball, flinches when hit, shows stars when knocked out
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
L.chess = function(t, ph)
	local c = (t * 0.2 + ph) % 1
	local move = if c < 0.12 then sin(c / 0.12 * math.pi) else 0
	return sit({ LS = A(30, 0, 8), LE = A(70), RS = A(30 + move * 30, 0, -6), RE = A(60 - move * 30), Neck = A(-25), Waist = A(-16) }), true
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
	return { LS = A(10, 0, -75), RS = A(10, 0, 70), LE = A(20), RE = A(35), LH = A(4, 0, -14), RH = A(12, 0, 12), RK = A(-25), Neck = A(0, 35, 10) }, true
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
L.fish = function(t, ph)
	local c = (t * 0.1 + ph) % 1
	local jerk = if c < 0.06 then sin(c / 0.06 * math.pi) else 0
	return { LS = A(46 + jerk * 30, 0, 12), RS = A(50 + jerk * 30, 0, -8), LE = A(34), RE = A(28), Neck = A(-6), Waist = A(-3 + jerk * 6) }, true
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
	return { RS = A(95, 0, -12), RE = A(4), Neck = A(0, -10, 0) }, false
end
L.scared = function(t, ph)
	local tr = osc(t, 30, ph) * 2
	return { LS = A(100 + tr, 0, 30), RS = A(100 - tr, 0, -30), LE = A(128), RE = A(128), Waist = A(-10 + tr), LK = A(-14), RK = A(-14), LH = A(8), RH = A(8) }, false
end
L.kick = function(t, ph, k)
	return { RH = A(-30 + k * 110), RK = A(-50 + k * 50), LS = A(-20), RS = A(30, 0, 20), Waist = A(-8) }, false
end
-- a punch thrown while fighting (right jab out and back)
L.strike = function(t, ph, k)
	local out = math.sin(k * math.pi)
	return { RS = A(60 + out * 35, 0, -10), RE = A(100 - out * 95), LS = A(55, 0, 16), LE = A(110), Waist = A(-6, -out * 25, 0) }, false
end
L.flinch = function(t, ph, k)
	return { Waist = A(18 * (1 - k)), Neck = A(20 * (1 - k)), LS = A(40 * (1 - k), 0, -20), RS = A(40 * (1 - k), 0, 20) }, false
end
L.idle = nil
L.wait = nil
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
	model:GetAttributeChangedSignal("Swing"):Connect(function()
		st.Swing = os.clock()
	end)
	model:GetAttributeChangedSignal("Kick"):Connect(function()
		st.Kick = os.clock()
	end)
	model:GetAttributeChangedSignal("Hit"):Connect(function()
		st.Hit = os.clock()
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

local function setProps(st, model, action)
	if st.PropAction == action then
		return
	end
	st.PropAction = action
	if st.Props then
		st.Props:Destroy()
		st.Props = nil
	end
	local info = Actions.Get(action or "")
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
local localPlayer = Players.LocalPlayer

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
	-- short overlays: a soccer kick, a flinch
	if now - st.Swing < 0.35 then
		target, full = L.strike(t, st.Phase, (now - st.Swing) / 0.35)
	elseif now - st.Kick < 0.35 then
		target, full = L.kick(t, st.Phase, (now - st.Kick) / 0.35)
	elseif now - st.Hit < 0.35 then
		target, full = L.flinch(t, st.Phase, (now - st.Hit) / 0.35)
	else
		local fn = L[poseName]
		if fn then
			target, full = fn(t, st.Phase)
		end
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
	setProps(st, model, action)
	local pivot = model:GetAttribute("SwingPivot")
	if pivot and root.Anchored then
		st.SwingBase = st.SwingBase or root.CFrame
		local angle = sin(t * 2.1 + st.Phase) * 0.55
		local axis = st.SwingBase.RightVector
		root.CFrame = CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-pivot) * st.SwingBase
	elseif st.SwingBase then
		st.SwingBase = nil
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
end

return Poses
