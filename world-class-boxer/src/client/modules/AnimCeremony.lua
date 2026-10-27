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

------------------------------------------------------------------------
-- the post-fight scene (PostFight: both men in the centre, the referee between them)
--   pfWait        a fighter waiting on the verdict: gloves hanging, the chest heaving, a glance at the referee
--   pfHold        the referee between them, a wrist in each hand (arms down and a little out), looking ahead
--   pfRaiseL      the referee raising HIS left arm (the man at his left won), head turned to him
--   pfRaiseR      the referee raising HIS right arm (the man at his right won)
--   pfRaiseBoth   a draw: both arms up
--   pfHandUpR     the winner's right arm raised by the referee (the fist high, the chest up, a look up)
--   pfHandUpL     the same, the left arm
--   pfLose        the loser: head down, gloves on the hips, a slow shake of the head
------------------------------------------------------------------------
POSES.pfWait = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "pfWait", dt, 0.5)
	base(p, rig, t, dt)
	local br = sin(t * 2.6) * 0.035 -- heavy breathing
	local glance = 0.22 * (0.5 + 0.5 * sin(t * 0.45))
	to(p, "W", A(0.1 + br, 0, 0), k)
	to(p, "Neck", A(-0.02 - br * 0.5, glance, 0), k)
	to(p, "RS", A(0.12, 0, 0.3 + br * 0.4), k)
	to(p, "RE", A(0.42, 0, 0), k)
	to(p, "LS", A(0.12, 0, -0.3 - br * 0.4), k)
	to(p, "LE", A(0.42, 0, 0), k)
	rig.lookW = 0.35
	return p
end

-- (the arms hang a little out, REF_OUT rad: PostFight.Layout stands each man a shoulder width of each plus its
-- SIDE_GAP of air from the referee, with his own arm a touch out toward him - the hanging hands meet the wrists
-- there; an arm held 0.9 rad out reached into the man's forearm)
local REF_OUT = 0.25
POSES.pfHold = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "pfHold", dt, 0.5)
	base(p, rig, t, dt)
	to(p, "W", A(0.04, 0, 0), k)
	to(p, "Neck", A(0.04, 0, 0), k)
	to(p, "RS", A(-0.1, 0, REF_OUT), k)
	to(p, "RE", A(0.2, 0, 0), k)
	to(p, "LS", A(-0.1, 0, -REF_OUT), k)
	to(p, "LE", A(0.2, 0, 0), k)
	rig.lookW = 0.4
	return p
end

-- (at the raise the loser's wrist is let go: the referee's free arm drops to his side, REF_FREE rad out, clear of
-- the loser's forearm as his gloves go to his hips - pfLose)
local REF_UP, WIN_UP, REF_FREE = 2.75, 2.9, 0.06
local function refRaise(p, rig, t, dt, k, left, both)
	to(p, "W", A(0.04, left and 0.1 or -0.1, 0), k)
	to(p, "Neck", A(0.12, both and 0 or (left and 0.45 or -0.45), 0), k)
	-- (the raised arm nearly straight up, REF_UP rad: the winner's goes up at WIN_UP beside it, the two hands meet
	-- over the gap between the bodies instead of crossing into the other man)
	if left or both then
		to(p, "LS", A(0.18, 0, -REF_UP), k)
		to(p, "LE", A(0.3, 0, 0), k)
	else
		to(p, "LS", A(-0.05, 0, -REF_FREE), k)
		to(p, "LE", A(0.15, 0, 0), k)
	end
	if (not left) or both then
		to(p, "RS", A(0.18, 0, REF_UP), k)
		to(p, "RE", A(0.3, 0, 0), k)
	else
		to(p, "RS", A(-0.05, 0, REF_FREE), k)
		to(p, "RE", A(0.15, 0, 0), k)
	end
	rig.lookW = 0
end

POSES.pfRaiseL = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "pfRaiseL", dt, 0.45)
	base(p, rig, t, dt)
	refRaise(p, rig, t, dt, k, true, false)
	return p
end

POSES.pfRaiseR = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "pfRaiseR", dt, 0.45)
	base(p, rig, t, dt)
	refRaise(p, rig, t, dt, k, false, false)
	return p
end

POSES.pfRaiseBoth = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "pfRaiseBoth", dt, 0.45)
	base(p, rig, t, dt)
	refRaise(p, rig, t, dt, k, false, true)
	return p
end

local function handUp(p, rig, t, dt, k, rightArm)
	local b = sin(t * 2.2) * 0.03
	to(p, "W", A(0.12 + b, 0, rightArm and -0.05 or 0.05), k)
	to(p, "Neck", A(0.16, rightArm and -0.12 or 0.12, 0), k)
	if rightArm then
		to(p, "RS", A(0.12, 0, WIN_UP), k)
		to(p, "RE", A(0.22, 0, 0), k)
		to(p, "LS", A(0.2, 0, -0.38), k)
		to(p, "LE", A(0.9, 0, 0), k)
	else
		to(p, "LS", A(0.12, 0, -WIN_UP), k)
		to(p, "LE", A(0.22, 0, 0), k)
		to(p, "RS", A(0.2, 0, 0.38), k)
		to(p, "RE", A(0.9, 0, 0), k)
	end
	rig.lookW = 0.3
end

POSES.pfHandUpR = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "pfHandUpR", dt, 0.4)
	base(p, rig, t, dt)
	handUp(p, rig, t, dt, k, true)
	return p
end

POSES.pfHandUpL = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "pfHandUpL", dt, 0.4)
	base(p, rig, t, dt)
	handUp(p, rig, t, dt, k, false)
	return p
end

POSES.pfLose = function(p, rig, t, d, w, model, dt)
	local k = into(rig, "pfLose", dt, 0.7)
	base(p, rig, t, dt)
	local br = sin(t * 1.4) * 0.03
	local shake = sin(t * 4.2) * 0.12 * (0.5 + 0.5 * sin(t * 0.6))
	to(p, "W", A(-0.1 + br, 0, 0), k)
	to(p, "Neck", A(-0.55 - br, shake, 0), k)
	to(p, "RS", A(-0.25, 0, 0.55) * A(0, 0.9, 0), k)
	to(p, "RE", A(1.6, 0, 0), k)
	to(p, "LS", A(-0.25, 0, -0.55) * A(0, -0.9, 0), k)
	to(p, "LE", A(1.6, 0, 0), k)
	rig.lookW = 0
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
