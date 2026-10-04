-- Animator: procedural animation for everyone in the game, no animation assets needed.
-- Drives the R15 joints' Transform (works with classic Motor6D joints and with the
-- newer AnimationConstraint avatar joints) every frame in PreSimulation.
--  * tag "Fighter": fight stance, footwork, 6 punches (head/body), block, parry, slip,
--    roll, pivot, clinch, hurt, knockdowns  (attributes Guard, Act, ActId)
--  * tag "Trainee": training poses (attribute Pose; local minigames add PoseDrive,
--    PoseSpeed and Act for exact rep / punch timing)
--  * tag "Ambient": gym members' loops (attribute Loop)
--  * tag "HairSway": long hair, braids and locs swing with movement
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local A = CFrame.Angles
local I = CFrame.identity
local PI = math.pi
local sin, cos, abs, max, min = math.sin, math.cos, math.abs, math.max, math.min

local JOINTS = {
	Root = { "LowerTorso", "Root" }, W = { "UpperTorso", "Waist" }, Neck = { "Head", "Neck" },
	RS = { "RightUpperArm", "RightShoulder" }, RE = { "RightLowerArm", "RightElbow" }, RW = { "RightHand", "RightWrist" },
	LS = { "LeftUpperArm", "LeftShoulder" }, LE = { "LeftLowerArm", "LeftElbow" }, LW = { "LeftHand", "LeftWrist" },
	RH = { "RightUpperLeg", "RightHip" }, RK = { "RightLowerLeg", "RightKnee" }, RA = { "RightFoot", "RightAnkle" },
	LH = { "LeftUpperLeg", "LeftHip" }, LK = { "LeftLowerLeg", "LeftKnee" }, LA = { "LeftFoot", "LeftAnkle" },
}
local TAGS = { "Fighter", "Trainee", "Ambient" }
local rigs = {}

local function hasAnyTag(model)
	for _, tag in ipairs(TAGS) do
		if CollectionService:HasTag(model, tag) then
			return true
		end
	end
	return false
end

local function setup(model)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	local joints = {}
	for key, path in pairs(JOINTS) do
		local p = model:FindFirstChild(path[1])
		local m = p and p:FindFirstChild(path[2])
		if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then
			joints[key] = { motor = m, cur = I }
		end
	end
	local seed = model:GetAttribute("AmbientSeed") or (#model.Name * 97)
	rigs[model] = {
		model = model, joints = joints, lastActId = model:GetAttribute("ActId"), act = nil,
		rng = Random.new(seed), phase = (seed % 100) / 100 * 6.28, nextAuto = 0, autoAct = nil,
		root = model:FindFirstChild("HumanoidRootPart"),
	}
end

local function teardown(model)
	local rig = rigs[model]
	if not rig then
		return
	end
	if hasAnyTag(model) then
		return
	end
	for _, j in pairs(rig.joints) do
		if j.motor and j.motor.Parent then
			j.motor.Transform = I
		end
	end
	if rig.rope then
		rig.rope.beam:Destroy()
		rig.rope.a0:Destroy()
		rig.rope.a1:Destroy()
	end
	rigs[model] = nil
end

for _, tag in ipairs(TAGS) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(m)
		task.defer(setup, m)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(m)
		task.defer(teardown, m)
	end)
	for _, m in ipairs(CollectionService:GetTagged(tag)) do
		setup(m)
	end
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

------------------------------------------------------------------------
-- Pose building blocks
------------------------------------------------------------------------
-- bend the legs so the feet stay planted while the hips drop by `depth`
local function legs(p, depth, stagger)
	depth = max(0, depth)
	local a = math.acos(math.clamp(1 - depth / 2.3, -1, 1))
	stagger = stagger or 0
	p.Root = (p.Root or I) * CFrame.new(0, -depth, 0)
	p.LH = A(a + stagger, 0, 0)
	p.LK = A(-2 * a, 0, 0)
	p.LA = A(a - stagger, 0, 0)
	p.RH = A(a - stagger, 0, 0)
	p.RK = A(-2 * a, 0, 0)
	p.RA = A(a + stagger, 0, 0)
	return p
end

local function standing(t, breathe)
	local b = sin(t * 2) * 0.02 * (breathe or 1)
	return { Root = CFrame.new(0, 0, 0), W = A(b, 0, 0), Neck = A(-b, 0, 0),
		RS = A(0.05, 0, -0.06), RE = A(0.15, 0, 0), LS = A(0.05, 0, 0.06), LE = A(0.15, 0, 0) }
end

local function stance(t, bounce)
	local b = sin(t * 7) * 0.06 * (bounce or 1)
	local p = { LS = A(0.95, 0, 0.25), LE = A(1.75, 0, 0), RS = A(0.7, 0, -0.3), RE = A(2.0, 0, 0),
		W = A(0, -0.3, 0), Neck = A(-0.12, 0.25, 0), Root = A(0, 0, 0) }
	return legs(p, 0.22 + b, 0.18)
end

local function seated(p, lean)
	lean = lean or 0
	p.Root = A(-lean, 0, 0)
	p.RH = A(PI / 2 + lean, 0, 0.06)
	p.LH = A(PI / 2 + lean, 0, -0.06)
	p.RK = A(-PI / 2, 0, 0)
	p.LK = A(-PI / 2, 0, 0)
	return p
end

------------------------------------------------------------------------
-- Fight moves
------------------------------------------------------------------------
local function punchPose(ptype, hand, zone)
	local L = hand == "L"
	local S, E = L and "LS" or "RS", L and "LE" or "RE"
	local inward = L and 0.12 or -0.12
	local body = zone == "body"
	local out = {}
	if ptype == "jab" or ptype == "cross" then
		out[S] = A(body and 1.15 or 1.6, 0, inward)
		out[E] = A(body and 0.2 or 0.05, 0, 0)
		out.W = A(body and -0.2 or 0, L and -0.45 or 0.55, 0)
		if ptype == "cross" then
			out.RH = A(0.25, 0, 0)
			out.RA = A(0.4, 0, 0) -- rear heel turns
		end
	elseif ptype == "leadhook" or ptype == "rearhook" or ptype == "hook" then
		out[S] = A(body and 1.1 or 1.45, 0, L and -0.75 or 0.75)
		out[E] = A(1.6, 0, 0)
		out.W = A(body and -0.2 or 0, L and 0.7 or -0.7, 0)
	elseif ptype == "overhand" then
		out[S] = A(2.15, 0, -0.35)
		out[E] = A(0.6, 0, 0)
		out.W = A(-0.25, 0.65, -0.25)
		out.Root = CFrame.new(0, -0.2, 0)
	else -- uppercut
		out[S] = A(1.9, 0, inward)
		out[E] = A(1.4, 0, 0)
		out.W = A(-0.1, L and -0.3 or 0.3, 0)
		out.Root = CFrame.new(0, -0.35, 0)
	end
	if body and ptype ~= "overhand" then
		out.Root = CFrame.new(0, -0.55, 0)
	end
	return out
end

local PUNCHES = { jab = true, cross = true, hook = true, leadhook = true, rearhook = true, uppercut = true, overhand = true }

-- applies a timed action on top of a pose; returns false when it's finished
local function applyAct(target, act, t)
	local el = t - act.start
	local k = act.kind
	if PUNCHES[k] then
		local w = act.windup
		local dur = w + 0.05 + w * 0.9
		if el >= dur then
			return false
		end
		local ext
		if el < w then
			ext = smooth(el / w)
		elseif el < w + 0.05 then
			ext = 1
		else
			ext = 1 - smooth((el - w - 0.05) / (w * 0.9))
		end
		for key, cf in pairs(punchPose(k, act.hand, act.zone)) do
			target[key] = (target[key] or I):Lerp(cf, ext)
		end
		return true
	end
	local function pulse(dur)
		if el >= dur then
			return nil
		end
		return sin(PI * el / dur)
	end
	if k == "hit" or k == "hitbody" or k == "blockhit" then
		local s = pulse(0.35)
		if not s then
			return false
		end
		if k == "hit" then
			local hook = act.hand == "leadhook" or act.hand == "rearhook" or act.hand == "hook"
			local upper = act.hand == "uppercut"
			target.Neck = target.Neck * A((upper and -0.6 or 0.5) * s, (hook and 0.5 or 0) * s, 0)
			target.W = target.W * A(0.22 * s, 0, (hook and 0.2 or 0) * s)
		elseif k == "hitbody" then
			target.W = target.W * A(-0.45 * s, 0, 0)
			target.Root = target.Root * CFrame.new(0, -0.3 * s, 0)
		else
			target.Root = target.Root * CFrame.new(0, 0, 0.35 * s)
		end
		return true
	elseif k == "slip" then
		local s = pulse(0.42)
		if not s then
			return false
		end
		local L = act.hand == "L"
		target.W = target.W * A(0, 0, (L and 0.45 or -0.45) * s)
		target.Root = target.Root * CFrame.new((L and -0.5 or 0.5) * s, -0.35 * s, 0)
		return true
	elseif k == "roll" then
		local d = 0.55
		if el >= d then
			return false
		end
		local x = el / d
		local s = sin(PI * x)
		target.W = target.W * A(-0.35 * s, 0, cos(PI * x) * 0.5 * s)
		target.Root = target.Root * CFrame.new(sin(2 * PI * x) * 0.35, -0.75 * s, 0)
		target.Neck = target.Neck * A(-0.2 * s, 0, 0)
		return true
	elseif k == "parry" then
		local s = pulse(0.3)
		if not s then
			return false
		end
		local L = act.hand == "L"
		local S, E = L and "LS" or "RS", L and "LE" or "RE"
		target[S] = target[S]:Lerp(A(1.5, 0, L and -0.55 or 0.55), s)
		target[E] = target[E]:Lerp(A(1.5, 0, 0), s)
		return true
	elseif k == "parryhit" then
		local s = pulse(0.25)
		if not s then
			return false
		end
		target.LS = target.LS:Lerp(A(1.45, 0, -0.7), s)
		target.W = target.W * A(0, -0.25 * s, 0)
		return true
	elseif k == "pivot" then
		local s = pulse(0.35)
		if not s then
			return false
		end
		local L = act.hand == "L"
		target.W = target.W * A(0, (L and 0.5 or -0.5) * s, 0)
		target.LH = (target.LH or I) * A(0.3 * s, 0, 0)
		target.RH = (target.RH or I) * A(-0.3 * s, 0, 0)
		return true
	elseif k == "step" then
		local s = pulse(0.3)
		if not s then
			return false
		end
		local dir = act.hand
		local fwd = dir == "F" and 1 or (dir == "B" and -1 or 0)
		local side = dir == "R" and 1 or (dir == "L" and -1 or 0)
		target.Root = target.Root * CFrame.new(side * 0.6 * s, 0.12 * s, -fwd * 0.6 * s)
		target.LH = (target.LH or I) * A(0.4 * s * (fwd ~= 0 and 1 or 0.5), 0, 0)
		return true
	elseif k == "jump" then
		local s = pulse(act.windup > 0 and act.windup or 0.32)
		if not s then
			return false
		end
		target.Root = target.Root * CFrame.new(0, 0.55 * s, 0)
		return true
	end
	return false
end

local function fightPose(rig, model, t)
	local guard = model:GetAttribute("Guard") or "stance"
	local p
	if guard == "block" then
		p = { LS = A(1.9, 0, 0.45), LE = A(2.3, 0, 0), RS = A(1.9, 0, -0.45), RE = A(2.3, 0, 0),
			W = A(-0.15, 0, 0), Neck = A(-0.25, 0, 0), Root = I }
		legs(p, 0.45, 0.18)
	elseif guard == "hurt" then
		p = { LS = A(0.5, 0, 0.2), LE = A(1.2, 0, 0), RS = A(0.4, 0, -0.2), RE = A(1.3, 0, 0),
			W = A(0.1, 0, sin(t * 5) * 0.15), Neck = A(0.15, 0, sin(t * 4) * 0.12), Root = A(0, 0, sin(t * 3) * 0.08) }
		legs(p, 0.25 + sin(t * 4) * 0.08, 0.1)
		p.LK = p.LK * A(-0.2 * abs(sin(t * 3)), 0, 0)
	elseif guard == "clinch" then
		p = { LS = A(1.5, 0, 0.1), LE = A(0.8, 0, 0), RS = A(1.5, 0, -0.1), RE = A(0.8, 0, 0),
			W = A(-0.35, 0, 0), Neck = A(-0.2, 0, 0), Root = CFrame.new(0, 0, -0.4) }
		legs(p, 0.3, 0.2)
	elseif guard == "down" then
		p = { LS = A(0.2, 0, -1.3), LE = A(0.3, 0, 0), RS = A(0.2, 0, 1.3), RE = A(0.3, 0, 0),
			W = I, Neck = A(0.2, 0, 0.3), Root = CFrame.new(0, -2.3, 0) * A(1.45, 0, 0),
			LH = A(0.3, 0, 0), LK = A(-0.6, 0, 0), RH = A(0.1, 0, 0), RK = A(-0.2, 0, 0) }
	else
		p = stance(t, 1)
		-- footwork: legs step when the fighter moves
		local root = rig.root
		if root then
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			if speed > 1.5 then
				local w = t * 12
				local k = math.clamp(speed / 10, 0, 1)
				p.LH = p.LH * A(0.25 * sin(w) * k, 0, 0)
				p.RH = p.RH * A(-0.25 * sin(w) * k, 0, 0)
				p.LK = p.LK * A(-0.3 * max(0, -sin(w)) * k, 0, 0)
				p.RK = p.RK * A(-0.3 * max(0, sin(w)) * k, 0, 0)
			end
		end
	end
	return p, guard
end

------------------------------------------------------------------------
-- Training poses & gym loops.  d = drive (0..1 rep position), w = cycle speed
------------------------------------------------------------------------
local POSE = {}

POSE.guard = function(t)
	return stance(t, 1)
end
POSE.heavybag = POSE.guard
POSE.spar = POSE.guard
POSE.shadow = POSE.guard

POSE.speedbag = function(t, d, w)
	local x = t * 16 * w
	local p = { RS = A(1.55 + 0.14 * sin(x), 0, -0.4), RE = A(1.95 + 0.25 * cos(x), 0, 0),
		LS = A(1.55 - 0.14 * sin(x), 0, 0.4), LE = A(1.95 - 0.25 * cos(x), 0, 0),
		W = A(0, 0, 0), Neck = A(-0.18, 0, 0), Root = I }
	return legs(p, 0.12 + abs(sin(x / 2)) * 0.03, 0.1)
end

POSE.bench = function(t, d)
	local p = { Root = A(PI / 2, 0, 0), W = I, Neck = A(-0.15, 0, 0),
		RS = A(lerp(0.35, 1.57, d), 0, -0.1), RE = A(lerp(1.65, 0.05, d), 0, 0),
		LS = A(lerp(0.35, 1.57, d), 0, 0.1), LE = A(lerp(1.65, 0.05, d), 0, 0),
		RH = A(0.05, 0, 0.18), RK = A(-1.75, 0, 0), RA = A(0.4, 0, 0),
		LH = A(0.05, 0, -0.18), LK = A(-1.75, 0, 0), LA = A(0.4, 0, 0) }
	return p
end

POSE.deadlift = function(t, d)
	local h = 1 - d
	local lean = 1.0 * h
	local p = { Root = A(-lean, 0, 0), W = A(-0.1 * h, 0, 0), Neck = A(0.3 * h, 0, 0),
		RS = A(lean + 0.05, 0, -0.05), RE = A(0.05, 0, 0), LS = A(lean + 0.05, 0, 0.05), LE = A(0.05, 0, 0) }
	local depth = 0.9 * h
	local a = math.acos(math.clamp(1 - depth / 2.3, -1, 1))
	p.Root = CFrame.new(0, -depth, 0) * p.Root
	p.RH = A(lean + a, 0, 0)
	p.LH = A(lean + a, 0, 0)
	p.RK = A(-2 * a, 0, 0)
	p.LK = A(-2 * a, 0, 0)
	p.RA = A(a, 0, 0)
	p.LA = A(a, 0, 0)
	return p
end

POSE.squat = function(t, d)
	local h = 1 - d
	local lean = 0.45 * h
	local depth = 1.55 * h
	local a = math.acos(math.clamp(1 - depth / 2.3, -1, 1))
	local p = { Root = CFrame.new(0, -depth, 0) * A(-lean, 0, 0), W = A(0.05, 0, 0), Neck = A(0.2 * h, 0, 0),
		RS = A(-0.25, 0, 1.25), RE = A(1.7, 0, 0), LS = A(-0.25, 0, -1.25), LE = A(1.7, 0, 0) }
	p.RH = A(a + lean, 0, 0.12)
	p.LH = A(a + lean, 0, -0.12)
	p.RK = A(-2 * a, 0, 0)
	p.LK = A(-2 * a, 0, 0)
	p.RA = A(a, 0, 0)
	p.LA = A(a, 0, 0)
	return p
end

POSE.curl = function(t, d, w, rig)
	-- alternate arms each rep
	local cycle = rig.curlCycle or 0
	local right = cycle % 2 == 0
	local up = d
	local p = standing(t, 0.5)
	p.RS = A(0.12, 0, -0.08)
	p.LS = A(0.12, 0, 0.08)
	p.RE = A(right and lerp(0.15, 2.3, up) or 0.15, 0, 0)
	p.LE = A((not right) and lerp(0.15, 2.3, up) or 0.15, 0, 0)
	return legs(p, 0.08, 0)
end

POSE.pullup = function(t, d)
	local s1 = PI - (PI - 0.5) * d
	local b = 2.6 * d
	return { Root = CFrame.new(0, 1.9 * d, 0), W = I, Neck = A(-0.1 * d, 0, 0),
		RS = A(s1, 0, -0.12), RE = A(b, 0, 0), LS = A(s1, 0, 0.12), LE = A(b, 0, 0),
		RH = A(0.25, 0, 0), RK = A(-1.2, 0, 0), LH = A(0.35, 0, 0), LK = A(-1.0, 0, 0) }
end

POSE.run = function(t, d, w)
	local x = t * 10 * w
	local s = sin(x)
	return { Root = CFrame.new(0, 0.12 * abs(cos(x)), 0) * A(-0.12, 0, 0), W = A(0, 0.12 * s, 0), Neck = A(0.1, -0.12 * s, 0),
		RS = A(-0.6 * s, 0, -0.08), RE = A(1.5, 0, 0), LS = A(0.6 * s, 0, 0.08), LE = A(1.5, 0, 0),
		RH = A(0.12 + 0.75 * s, 0, 0), RK = A(-0.25 - 1.0 * max(0, -cos(x)), 0, 0), RA = A(0.1, 0, 0),
		LH = A(0.12 - 0.75 * s, 0, 0), LK = A(-0.25 - 1.0 * max(0, cos(x)), 0, 0), LA = A(0.1, 0, 0) }
end

POSE.walk = function(t, d, w)
	local x = t * 7 * w
	local s = sin(x)
	return { Root = CFrame.new(0, 0.05 * abs(cos(x)), 0), W = A(0, 0.08 * s, 0), Neck = A(0, -0.08 * s, 0),
		RS = A(-0.4 * s, 0, -0.06), RE = A(0.3, 0, 0), LS = A(0.4 * s, 0, 0.06), LE = A(0.3, 0, 0),
		RH = A(0.45 * s, 0, 0), RK = A(-0.5 * max(0, -cos(x)), 0, 0), LH = A(-0.45 * s, 0, 0), LK = A(-0.5 * max(0, cos(x)), 0, 0) }
end

POSE.bike = function(t, d, w)
	local x = t * 7 * w
	local p = { W = A(-0.1, 0, 0), Neck = A(0.25, 0, 0),
		RS = A(1.25, 0, -0.1), RE = A(0.3, 0, 0), LS = A(1.25, 0, 0.1), LE = A(0.3, 0, 0) }
	seated(p, 0.45)
	p.RH = A(PI / 2 + 0.45 - 0.35 + 0.35 * sin(x), 0, 0.05)
	p.LH = A(PI / 2 + 0.45 - 0.35 - 0.35 * sin(x), 0, -0.05)
	p.RK = A(-1.3 - 0.45 * cos(x), 0, 0)
	p.LK = A(-1.3 + 0.45 * cos(x), 0, 0)
	return p
end

POSE.row = function(t, d)
	local p = { W = I, Neck = A(0, 0, 0),
		RS = A(lerp(1.5, 0.55, d), 0, -0.1), RE = A(lerp(0.05, 1.9, d), 0, 0),
		LS = A(lerp(1.5, 0.55, d), 0, 0.1), LE = A(lerp(0.05, 1.9, d), 0, 0) }
	local lean = lerp(0.35, -0.3, d)
	p.Root = A(-lean, 0, 0)
	p.RH = A(lerp(2.25, 1.5, d) + lean, 0, 0.06)
	p.LH = A(lerp(2.25, 1.5, d) + lean, 0, -0.06)
	p.RK = A(lerp(-2.2, -0.1, d), 0, 0)
	p.LK = A(lerp(-2.2, -0.1, d), 0, 0)
	return p
end

POSE.rope = function(t, d, w, rig)
	local x = (rig.ropePhase or 0)
	local hop = max(0, cos(x)) ^ 2 -- one hop per rope turn, peaking as the rope passes the feet
	local p = { Root = CFrame.new(0, 0.32 * hop * (rig.ropeHop or 1), 0), W = I, Neck = A(-0.05, 0, 0),
		RS = A(0.25, 0, 0.32), RE = A(1.0, 0, 0), LS = A(0.25, 0, -0.32), LE = A(1.0, 0, 0),
		RW = A(0.4 * sin(x), 0, 0), LW = A(0.4 * sin(x), 0, 0) }
	local land = 0.12 * (1 - hop)
	legs(p, land, 0)
	p.Root = CFrame.new(0, 0.32 * hop * (rig.ropeHop or 1), 0) * CFrame.new(0, -land, 0)
	if rig.ropeFoot then
		local L = rig.ropeFoot == "L"
		p[L and "RK" or "LK"] = A(-0.9 * hop, 0, 0)
	end
	return p
end

POSE.ladder = function(t, d, w)
	local x = t * 15 * w
	local p = { W = A(-0.1, 0, 0), Neck = A(0.15, 0, 0),
		RS = A(-0.5 * sin(x), 0, -0.1), RE = A(1.5, 0, 0), LS = A(0.5 * sin(x), 0, 0.1), LE = A(1.5, 0, 0), Root = I }
	legs(p, 0.25, 0)
	p.RH = p.RH * A(0.55 * max(0, sin(x)), 0, 0)
	p.RK = p.RK * A(-0.9 * max(0, sin(x)), 0, 0)
	p.LH = p.LH * A(0.55 * max(0, -sin(x)), 0, 0)
	p.LK = p.LK * A(-0.9 * max(0, -sin(x)), 0, 0)
	return p
end

POSE.longsit = function(t)
	local shiver = sin(t * 40) * 0.015
	local p = { Root = A(0, 0, shiver), W = A(-0.1 + shiver, 0, 0), Neck = A(0.1, 0, 0),
		RS = A(0.25, 0, 0.55), RE = A(0.5, 0, 0), LS = A(0.25, 0, -0.55), LE = A(0.5, 0, 0),
		RH = A(PI / 2, 0, 0.08), LH = A(PI / 2, 0, -0.08), RK = A(-0.12, 0, 0), LK = A(-0.12, 0, 0) }
	return p
end

POSE.sit = function(t)
	local b = sin(t * 1.6) * 0.03
	local p = { W = A(-0.15 + b, 0, 0), Neck = A(0.35, 0, 0),
		RS = A(0.75, 0, 0.05), RE = A(0.55, 0, 0), LS = A(0.75, 0, -0.05), LE = A(0.55, 0, 0) }
	return seated(p, 0)
end

POSE.sitwatch = function(t, d, w, rig)
	local p = POSE.sit(t)
	p.Neck = A(0.05, sin(t * 0.4 + rig.phase) * 0.35, 0)
	p.W = A(-0.05, 0, 0)
	p.RS = A(0.9, 0, -0.35)
	p.RE = A(1.4, 0, 0)
	p.LS = A(0.9, 0, 0.35)
	p.LE = A(1.4, 0, 0)
	return p
end

POSE.lie = function(t)
	local b = sin(t * 1.4) * 0.02
	return { Root = A(-PI / 2, 0, 0), W = A(b, 0, 0), Neck = A(0.1, 0.6, 0),
		RS = A(0.05, 0, 0.12), RE = A(0.1, 0, 0), LS = A(0.05, 0, -0.12), LE = A(0.1, 0, 0) }
end

POSE.lieup = function(t)
	local b = sin(t * 1.2) * 0.02
	return { Root = A(PI / 2, 0, 0), W = A(b, 0, 0), Neck = A(-0.1, 0, 0),
		RS = A(0.05, 0, 0.1), RE = A(0.1, 0, 0), LS = A(0.05, 0, -0.1), LE = A(0.1, 0, 0) }
end

POSE.stretch = function(t, d, w, rig)
	local phase = math.floor((t + rig.phase) / 4) % 3
	local k = smooth(math.min(1, ((t + rig.phase) % 4) / 0.8))
	local p = standing(t, 0.5)
	if phase == 0 then
		-- arm across the chest
		p.RS = A(1.45, 0, -1.0):Lerp(p.RS, 1 - k)
		p.RE = A(0.1, 0, 0)
		p.LS = A(1.2, 0, 0.6):Lerp(p.LS, 1 - k)
		p.LE = A(1.6, 0, 0)
	elseif phase == 1 then
		-- overhead side bend
		p.RS = A(0, 0, 2.9):Lerp(p.RS, 1 - k)
		p.LS = A(0, 0, -2.9):Lerp(p.LS, 1 - k)
		p.RE = A(0.3, 0, 0)
		p.LE = A(0.3, 0, 0)
		p.W = A(0, 0, 0.35 * k)
	else
		-- quad stretch: foot pulled to the glutes
		p.RK = A(-2.4 * k, 0, 0)
		p.RS = A(-0.6 * k, 0, 0.1)
		p.RE = A(0.4, 0, 0)
		p.LS = A(0.2, 0, -0.5)
	end
	return legs(p, 0.05, 0)
end

POSE.idle = function(t, d, w, rig)
	local p = standing(t, 1)
	p.Neck = A(-0.02, sin(t * 0.3 + rig.phase) * 0.25, 0)
	p.Root = A(0, 0, sin(t * 0.5 + rig.phase) * 0.025)
	return legs(p, 0.02, 0)
end

POSE.mittidle = function(t)
	local p = standing(t, 1)
	p.RS = A(0.45, 0, -0.1)
	p.RE = A(1.3, 0, 0)
	p.LS = A(0.45, 0, 0.1)
	p.LE = A(1.3, 0, 0)
	return legs(p, 0.05, 0.1)
end

-- the mitt coach holds the pads up; MittCall (local) flashes the called target
POSE.mitts = function(t, d, w, rig, model)
	local p = { RS = A(1.35, 0, -0.25), RE = A(1.65, 0, 0), LS = A(1.35, 0, 0.25), LE = A(1.65, 0, 0),
		W = A(-0.05, 0, 0), Neck = A(-0.05, 0, 0), Root = I }
	legs(p, 0.2 + sin(t * 6) * 0.04, 0.15)
	local call = model:GetAttribute("MittCall")
	local callT = model:GetAttribute("MittCallT")
	if call and callT then
		local el = os.clock() - callT
		if el < 0.45 then
			local s = sin(PI * math.clamp(el / 0.45, 0, 1))
			if call == "L" then
				p.LS = p.LS:Lerp(A(1.55, 0, -0.1), s)
				p.LE = p.LE:Lerp(A(0.9, 0, 0), s)
			elseif call == "R" then
				p.RS = p.RS:Lerp(A(1.55, 0, 0.1), s)
				p.RE = p.RE:Lerp(A(0.9, 0, 0), s)
			elseif call == "D" then
				-- swing a pad over the boxer's head (slip / roll drills)
				p.RS = p.RS:Lerp(A(1.6, 0, 0.9), s)
				p.RE = p.RE:Lerp(A(0.4, 0, 0), s)
			end
		end
	end
	return p
end

POSE.barber = function(t)
	local p = standing(t, 1)
	p.RS = A(1.35 + sin(t * 3) * 0.08, 0, -0.35 + sin(t * 2) * 0.1)
	p.RE = A(1.2, 0, 0)
	p.LS = A(1.1, 0, 0.25)
	p.LE = A(1.1, 0, 0)
	p.W = A(-0.2, 0.15, 0)
	p.Neck = A(0.25, 0, 0)
	return legs(p, 0.05, 0)
end

POSE.massage = function(t)
	local p = standing(t, 1)
	local k = sin(t * 3)
	p.W = A(-0.45, 0, 0)
	p.Neck = A(0.3, 0, 0)
	p.RS = A(1.15 + 0.12 * k, 0, -0.15)
	p.RE = A(0.35, 0, 0)
	p.LS = A(1.15 - 0.12 * k, 0, 0.15)
	p.LE = A(0.35, 0, 0)
	return legs(p, 0.15, 0)
end

------------------------------------------------------------------------
-- Ambient fighters (bag / shadow / sparring members) throw their own punches
------------------------------------------------------------------------
local AUTO_PUNCH = { "jab", "jab", "cross", "leadhook", "rearhook", "uppercut", "jab", "cross" }
local function ambientAct(rig, loop, t)
	if t < rig.nextAuto then
		return
	end
	local r = rig.rng
	local roll = r:NextNumber()
	if loop == "spar" and roll < 0.25 then
		rig.autoAct = { kind = r:NextNumber() < 0.5 and "slip" or "roll", hand = r:NextNumber() < 0.5 and "L" or "R", start = t, windup = 0.2 }
	elseif loop == "shadow" and roll < 0.3 then
		local moves = { "slip", "roll", "step", "pivot" }
		local m = moves[r:NextInteger(1, #moves)]
		local dirs = { "F", "B", "L", "R" }
		rig.autoAct = { kind = m, hand = m == "step" and dirs[r:NextInteger(1, 4)] or (r:NextNumber() < 0.5 and "L" or "R"), start = t, windup = 0.2 }
	else
		local p = AUTO_PUNCH[r:NextInteger(1, #AUTO_PUNCH)]
		local hand = (p == "jab" or p == "leadhook") and "L" or "R"
		if p == "uppercut" then
			hand = r:NextNumber() < 0.5 and "L" or "R"
		end
		rig.autoAct = { kind = p, hand = hand, zone = r:NextNumber() < 0.2 and "body" or "head", start = t, windup = 0.18 + r:NextNumber() * 0.08 }
	end
	rig.nextAuto = t + (loop == "heavybag" and r:NextNumber(0.35, 1.0) or r:NextNumber(0.5, 1.5))
end

------------------------------------------------------------------------
-- Jump-rope visual (beam between the hands that swings around the body)
------------------------------------------------------------------------
local function ropeVisual(rig, model, on, phase)
	if not on then
		if rig.rope then
			rig.rope.beam.Enabled = false
		end
		return
	end
	local rh, lh = model:FindFirstChild("RightHand"), model:FindFirstChild("LeftHand")
	local root = rig.root
	if not (rh and lh and root) then
		return
	end
	if not rig.rope then
		local a0 = Instance.new("Attachment")
		a0.Name = "RopeA"
		a0.Parent = lh
		local a1 = Instance.new("Attachment")
		a1.Name = "RopeB"
		a1.Parent = rh
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0, beam.Width1 = 0.12, 0.12
		beam.Segments = 16
		beam.FaceCamera = true
		beam.LightInfluence = 1
		beam.Color = ColorSequence.new(Color3.fromRGB(60, 66, 84))
		beam.Parent = rh
		rig.rope = { a0 = a0, a1 = a1, beam = beam }
	end
	rig.rope.beam.Enabled = true
	-- rope direction: rotates around the boxer's left-right axis
	local rc = root.CFrame
	local dir = rc:VectorToWorldSpace(Vector3.new(0, -cos(phase), sin(phase)))
	local function aim(att, part)
		local axis = part.CFrame:VectorToObjectSpace(dir)
		att.CFrame = CFrame.lookAt(Vector3.zero, axis) * A(0, PI / 2, 0)
	end
	aim(rig.rope.a0, lh)
	aim(rig.rope.a1, rh)
	-- long enough for the loop to pass under the feet from hip-height hands
	rig.rope.beam.CurveSize0 = 4.3
	rig.rope.beam.CurveSize1 = -4.3
end

------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------
local cam = workspace.CurrentCamera
local frame = 0

RunService.PreSimulation:Connect(function(dt)
	local t = os.clock()
	frame += 1
	local alpha = 1 - math.exp(-dt * 22)
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for model, rig in pairs(rigs) do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		local root = rig.root
		if not root or not root.Parent then
			rig.root = model:FindFirstChild("HumanoidRootPart")
			root = rig.root
			if not root then
				continue
			end
		end
		-- far away models update less often
		local dist = (root.Position - camPos).Magnitude
		if dist > 220 then
			continue
		elseif dist > 120 and (frame + rig.phase * 10) % 3 >= 1 then
			continue
		end

		local target, guard
		local actOk = true
		-- local / replicated actions (punches etc.)
		local actId = model:GetAttribute("ActId")
		if actId ~= rig.lastActId then
			rig.lastActId = actId
			local act = model:GetAttribute("Act")
			if type(act) == "string" then
				local a, b, c, d = string.match(act, "^([^|]+)|?([^|]*)|?([^|]*)|?([^|]*)$")
				rig.act = { kind = a, hand = b, zone = c, windup = tonumber(d) or 0.2, start = t }
			end
		end
		local isFighter = CollectionService:HasTag(model, "Fighter")
		local pose = model:GetAttribute("Pose")
		local loop = model:GetAttribute("Loop")
		local drive = model:GetAttribute("PoseDrive")
		local w = model:GetAttribute("PoseSpeed") or 1
		local ropeOn = false
		if isFighter then
			target, guard = fightPose(rig, model, t)
			actOk = guard ~= "down"
		else
			local name = pose or loop or "idle"
			if loop == "walk" or loop == "run" then
				local v = root.AssemblyLinearVelocity
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				if speed > 1 then
					name = loop == "run" and "run" or "walk"
					w = loop == "run" and speed / 14 or speed / 7
				else
					name = "idle"
				end
			end
			local fn = POSE[name] or POSE.idle
			if drive == nil then
				-- automatic reps for other players and gym members
				local cyc = (t * 0.55 * w + rig.phase) % 1
				drive = cyc < 0.5 and smooth(cyc * 2) or smooth(2 - cyc * 2)
				if name == "curl" then
					rig.curlCycle = math.floor(t * 0.55 * w + rig.phase)
				end
			elseif name == "curl" then
				rig.curlCycle = model:GetAttribute("RepCount") or 0
			end
			if name == "rope" then
				local spin = model:GetAttribute("RopeSpin")
				if spin then
					rig.ropePhase = spin
				else
					rig.ropePhase = (rig.ropePhase or 0) + dt * 9 * w
				end
				rig.ropeFoot = model:GetAttribute("RopeFoot")
				ropeOn = true
			end
			target = fn(t, drive, w, rig, model)
			if loop and not pose and (loop == "heavybag" or loop == "shadow" or loop == "spar") then
				ambientAct(rig, loop, t)
				if rig.autoAct and not applyAct(target, rig.autoAct, t) then
					rig.autoAct = nil
				end
			end
		end
		if rig.act and actOk then
			if not applyAct(target, rig.act, t) then
				rig.act = nil
			end
		end
		ropeVisual(rig, model, ropeOn, rig.ropePhase or 0)
		for key, j in pairs(rig.joints) do
			local goal = target[key] or I
			local a = alpha
			if key == "Root" and guard == "down" then
				a = 1 - math.exp(-dt * 6)
			end
			j.cur = j.cur:Lerp(goal, a)
			if j.motor.Parent then
				j.motor.Transform = j.cur
			end
		end
	end
end)

------------------------------------------------------------------------
-- Hair sway
------------------------------------------------------------------------
local hair = {}
local function addHair(m)
	if m:IsA("Motor6D") then
		hair[m] = { depth = m:GetAttribute("Depth") or 1, phase = math.random() * 6.28, vel = Vector3.zero, cur = I }
	end
end
CollectionService:GetInstanceAddedSignal("HairSway"):Connect(addHair)
CollectionService:GetInstanceRemovedSignal("HairSway"):Connect(function(m)
	hair[m] = nil
end)
for _, m in ipairs(CollectionService:GetTagged("HairSway")) do
	addHair(m)
end

local hairFrame = 0
RunService.PreSimulation:Connect(function(dt)
	hairFrame += 1
	local t = os.clock()
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for m, h in pairs(hair) do
		local p0 = m.Part0
		if not (m.Parent and p0) then
			hair[m] = nil
			continue
		end
		if (p0.Position - camPos).Magnitude > 90 then
			continue
		end
		-- movement of the head in its own space drives the swing (hair lags behind)
		local v = p0.AssemblyLinearVelocity
		local lv = p0.CFrame:VectorToObjectSpace(v)
		local k = 0.4 + 0.25 * h.depth
		local swayX = math.clamp(lv.Z * 0.025, -0.5, 0.5) + sin(t * 1.8 + h.phase) * 0.045 * k
		local swayZ = math.clamp(-lv.X * 0.025, -0.5, 0.5) + sin(t * 1.3 + h.phase * 1.7) * 0.035 * k
		local goal = A(swayX * k, 0, swayZ * k)
		h.cur = h.cur:Lerp(goal, 1 - math.exp(-dt * (8 - h.depth)))
		m.Transform = h.cur
	end
end)

-- the local player's own character needs to be re-registered after respawning
player.CharacterAdded:Connect(function(char)
	for _, tag in ipairs(TAGS) do
		if CollectionService:HasTag(char, tag) then
			setup(char)
		end
	end
end)
