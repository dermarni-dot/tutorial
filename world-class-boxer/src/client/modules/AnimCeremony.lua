-- AnimCeremony: the poses of the celebration cutscene (FightEngine's Fight:Ceremony sets them as Pose on a
-- "Trainee" / the "Referee"; BoxerClient.Ceremony runs the camera). They are added to AnimGym's POSE table, which
-- the Animator already plays for every tagged rig with a Pose, so no Animator code changes for them:
--   cerHandUp     the winner, his right hand raised by the referee (the fist high, the chest up, a look up)
--   cerRaise      the referee holding the winner's right wrist high with his left hand, looking at him
--   cerProud      the winner standing tall, gloves at the hips
--   cerStrapped   the winner's arms lifted out of the way while the belt goes round his waist, eyes down on it
--   cerStrap      the official reaching round the winner's waist, leaning in
--   cerClap       applause (the referee, the official)
--   cerLift       the belt lifted overhead in both hands, the arms in a V, the head back
--   cerCelebrate  the belt still overhead, pumping it, a bounce in the knees
-- POSE[name](p, rig, t, d, w, model, dt), the same signature as AnimGym's; joint conventions as AnimGym.stand:
-- +X on a shoulder lifts the arm forward, +Z on the right shoulder (-Z on the left) lifts it out to the side
-- (about 2.9 rad overhead), +X on an elbow bends it, +X on the waist arches the chest back, +Y turns left.
local AnimCeremony = {}

local Modules = script.Parent
local Gym = require(Modules:WaitForChild("AnimGym"))

local A = CFrame.Angles
local CF = CFrame.new
local sin = math.sin
local clamp = math.clamp

-- (how far into the pose the rig is: rig.cerT counts from the pose's first frame, for a smooth arrival)
local function into(rig, name, dt, secs)
	if rig.cerPose ~= name then
		rig.cerPose = name
		rig.cerT = 0
	end
	rig.cerT = (rig.cerT or 0) + (dt or 0)
	local k = clamp(rig.cerT / (secs or 0.45), 0, 1)
	return k * k * (3 - 2 * k)
end

local function base(p, rig, t, dt)
	Gym.stand(p, rig, t, dt or 0, 1, 0.25)
	return p
end

-- blend a joint from where the stand put it to the target by k
local function to(p, key, target, k)
	p[key] = p[key]:Lerp(target, k)
end

AnimCeremony.POSES = {}
local POSES = AnimCeremony.POSES

POSES.cerProud = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "cerProud", dt, 0.5)
	base(p, rig, t, dt)
	to(p, "W", A(0.08, 0, 0), k)
	to(p, "Neck", A(0.06, 0, 0), k)
	to(p, "RS", A(0.15, 0, 0.42), k)
	to(p, "RE", A(1.15, 0, 0), k)
	to(p, "LS", A(0.15, 0, -0.42), k)
	to(p, "LE", A(1.15, 0, 0), k)
	rig.lookW = 0.6
	return p
end

POSES.cerHandUp = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "cerHandUp", dt, 0.4)
	base(p, rig, t, dt)
	local b = sin(t * 2.2) * 0.03
	to(p, "W", A(0.12 + b, 0, -0.05), k)
	to(p, "Neck", A(0.16, -0.12, 0), k)
	to(p, "RS", A(0.12, 0, 2.72), k)
	to(p, "RE", A(0.22, 0, 0), k)
	to(p, "LS", A(0.2, 0, -0.38), k)
	to(p, "LE", A(0.9, 0, 0), k)
	rig.lookW = 0.3
	return p
end

POSES.cerRaise = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "cerRaise", dt, 0.4)
	base(p, rig, t, dt)
	to(p, "W", A(0.02, 0.12, 0.04), k)
	to(p, "Neck", A(0.1, 0.42, 0), k)
	to(p, "LS", A(0.18, 0, -2.6), k)
	to(p, "LE", A(0.3, 0, 0), k)
	to(p, "RS", A(0.2, 0, 0.18), k)
	to(p, "RE", A(0.45, 0, 0), k)
	rig.lookW = 0
	return p
end

POSES.cerStrapped = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "cerStrapped", dt, 0.5)
	base(p, rig, t, dt)
	to(p, "W", A(0.04, 0, 0), k)
	to(p, "Neck", A(-0.32, 0, 0), k)
	to(p, "RS", A(0.25, 0, 1.0), k)
	to(p, "RE", A(0.6, 0, 0), k)
	to(p, "LS", A(0.25, 0, -1.0), k)
	to(p, "LE", A(0.6, 0, 0), k)
	rig.lookW = 0
	return p
end

POSES.cerStrap = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "cerStrap", dt, 0.5)
	base(p, rig, t, dt)
	p.Root = p.Root * CF(0, -0.14 * k, 0)
	to(p, "W", A(-0.28, 0, 0), k)
	to(p, "Neck", A(-0.18, 0, 0), k)
	to(p, "RS", A(0.95, 0, -0.32), k)
	to(p, "RE", A(0.3, 0, 0), k)
	to(p, "LS", A(0.95, 0, 0.32), k)
	to(p, "LE", A(0.3, 0, 0), k)
	rig.lookW = 0
	return p
end

POSES.cerClap = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "cerClap", dt, 0.35)
	base(p, rig, t, dt)
	local c = 0.16 * (0.5 + 0.5 * sin(t * 15))
	to(p, "RS", A(0.95, 0, -0.18 - c), k)
	to(p, "RE", A(1.25, 0, 0), k)
	to(p, "LS", A(0.95, 0, 0.18 + c), k)
	to(p, "LE", A(1.25, 0, 0), k)
	to(p, "Neck", A(0.04, 0, 0), k)
	rig.lookW = 0.8
	return p
end

local function overhead(p, rig, t, dt, k, pump)
	to(p, "W", A(0.16 + pump * 0.04, 0, 0), k)
	to(p, "Neck", A(0.34, 0, 0), k)
	to(p, "RS", A(0.32, 0, 2.42 + pump * 0.14), k)
	to(p, "RE", A(0.42 - pump * 0.2, 0, 0), k)
	to(p, "LS", A(0.32, 0, -2.42 - pump * 0.14), k)
	to(p, "LE", A(0.42 - pump * 0.2, 0, 0), k)
	rig.lookW = 0
end

POSES.cerLift = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "cerLift", dt, 0.6)
	base(p, rig, t, dt)
	overhead(p, rig, t, dt, k, 0)
	return p
end

POSES.cerCelebrate = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "cerCelebrate", dt, 0.3)
	base(p, rig, t, dt)
	local pump = 0.5 + 0.5 * sin(t * 7)
	p.Root = p.Root * CF(0, -0.06 * pump * k, 0)
	overhead(p, rig, t, dt, k, pump)
	return p
end

-- add the poses to the Animator's table (AnimGym.POSE: the same module table the Animator plays from)
local installed = false
function AnimCeremony.Install()
	if installed then
		return true
	end
	local POSE = Gym.POSE
	if type(POSE) ~= "table" then
		return false
	end
	for name, fn in pairs(POSES) do
		if POSE[name] == nil then
			POSE[name] = fn
		end
	end
	installed = true
	return true
end
AnimCeremony.Install()

return AnimCeremony
