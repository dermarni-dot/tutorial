-- Animator: motion-capture-feeling procedural animation for everyone in the game, no animation
-- assets. Drives the R15 joints' Transform (classic Motor6D joints and AnimationConstraint avatar
-- joints) every frame in PreSimulation. The motion lives in modules (BoxerClient):
--  * AnimLoco  - root-motion sensing, gait cycles (walk / run / sprint, boxing step-drag, gallop,
--                stagger), planted feet that never slide, turning in place, weight and momentum
--  * AnimFight - style stances that never stand still (seeded per boxer), kinetic-chain punches
--                with variants, defence, severity-scaled directional hit reactions, daze, clinch,
--                walkout / rest (on the stool) / win / lose
--  * AnimDown  - knockdowns by DownPose (flash, forward, side, back, face, knee, sit, ropes,
--                corner), knockouts by KOKind (one-punch timber fall, delayed, standing, crumple)
--                with a slow-motion beat and a ragdoll-like settle, the count, get-ups
--  * AnimGym   - training poses, flex poses, gym members' loops, watchers, the referee's stance
--  * AnimRig / AnimKit - rig geometry, IK, springs, math
-- Who is animated: tag "Fighter" (fights), "Trainee" (Pose), "Ambient" (Loop), "Referee",
-- "Preview" (the Creator), and every player character (walking / running / jumping around the
-- world; while a player is climbing, swimming or dead the default animation shows through).
-- Other players' training punches are re-synthesized locally and published as client-local
-- AutoAct / AutoActId so the gym's bags react (CONTRACTS section 7).
-- Faces (blinks, gaze, expressions), muscles (contraction, pump, jiggle, veins) and hair (spring
-- physics) live in BoxerClient.FaceFX / BodyFX / HairFX; this script drives them every frame.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Modules = script.Parent:WaitForChild("BoxerClient")
local K = require(Modules:WaitForChild("AnimKit"))
local R = require(Modules:WaitForChild("AnimRig"))
local Loco = require(Modules:WaitForChild("AnimLoco"))
local Fight = require(Modules:WaitForChild("AnimFight"))
local Down = require(Modules:WaitForChild("AnimDown"))
local Gym = require(Modules:WaitForChild("AnimGym"))

-- the FX modules are optional: the body animation must keep running if one of them fails
local function optional(name)
	local ok, mod = pcall(function()
		return require(Modules:WaitForChild(name, 10))
	end)
	if ok and type(mod) == "table" then
		return mod
	end
	warn("[Animator] " .. name .. " unavailable: " .. tostring(mod))
	return nil
end
local BodyFX = optional("BodyFX")
local FaceFX = optional("FaceFX")
local HairFX = optional("HairFX")
R.setFX({ BodyFX = BodyFX, FaceFX = FaceFX, HairFX = HairFX })

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local PI = math.pi
local sin, abs, max, min, exp, sqrt, atan2, floor = math.sin, math.abs, math.max, math.min, math.exp, math.sqrt, math.atan2, math.floor
local clamp = math.clamp
local smooth = K.smooth
local num = R.num

local KEYS, LEG_KEYS = R.KEYS, R.LEG_KEYS
-- the arm joints a punch drives, and the fastest any of them may turn while it does (rad/s)
local ARM_KEYS = { LS = true, LE = true, LW = true, RS = true, RE = true, RW = true }
-- a walker's swinging arm joints and where their post-filter transform is kept
local ARM_OUT = { LS = "lsOut", LE = "leOut", RS = "rsOut", RE = "reOut" }
local PUNCH_JOINT_RATE = 31
local TAGS = { "Fighter", "Trainee", "Ambient", "Preview", "Referee" }
-- player characters walk / run / jump with the procedural gait (false = Roblox's default Animate)
local DRIVE_PLAYERS = true
local rigs = {}
local nextSlot = 0 -- (the last rig's turn in the reduced-rate frame cycle: setup)
Gym.init(rigs)
R.rigs = rigs -- read-only handle for tools / tests (the animation lab inspects foot states)
local POSE = Gym.POSE
local PUNCHES = Gym.PUNCHES

-- LOD bands (studs from the camera)
local NEAR, MID, FAR, CULL = 45, 110, 170, 230

-- which exercise (Config.ExerciseTargets / Activities id) a pose works: BodyFX contraction + LivePump
local POSE_ACT = {
	bench = "Bench", curl = "Dumbbells", deadlift = "Barbell", squat = "Squat", pullup = "PullUps", medball = "MedBall",
	row = "Rower", run = "Treadmill", bike = "Bike", rope = "Rope", ladder = "Ladder", heavybag = "HeavyBag",
	speedbag = "SpeedBag", guard = "Shadow", shadow = "Shadow", spar = "Sparring",
}

------------------------------------------------------------------------
-- Rig registry: tags, cached attributes (signals, not per-frame polling), act parsing
------------------------------------------------------------------------
local function hasAnyTag(model)
	for _, tag in ipairs(TAGS) do
		if CollectionService:HasTag(model, tag) then
			return true
		end
	end
	return false
end

local function isPlayerChar(model)
	return DRIVE_PLAYERS and Players:GetPlayerFromCharacter(model) ~= nil
end

local onAct -- forward declaration (acts section)

local function readTags(rig)
	local m = rig.model
	rig.isFighter = CollectionService:HasTag(m, "Fighter")
	rig.isTrainee = CollectionService:HasTag(m, "Trainee")
	rig.isAmbient = CollectionService:HasTag(m, "Ambient")
	rig.isPreview = CollectionService:HasTag(m, "Preview")
	rig.isReferee = CollectionService:HasTag(m, "Referee")
	rig.isTagged = rig.isFighter or rig.isTrainee or rig.isAmbient or rig.isPreview or rig.isReferee
end

local function onAttr(rig, name)
	local model = rig.model
	local v = model:GetAttribute(name)
	local old = rig.a[name]
	rig.a[name] = v
	local now = rig.clock
	if name == "ActId" then
		if v ~= nil and v ~= rig.lastActId then
			rig.lastActId = v
			onAct(rig, model:GetAttribute("Act"), now, false)
		end
	elseif name == "PredActId" then
		if v ~= nil and v ~= rig.predId then
			rig.predId = v
			onAct(rig, model:GetAttribute("PredAct"), now, true)
		end
	elseif name == "Guard" then
		if v ~= old then
			rig.prevGuard = old
			rig.guardT = now
			if old == "down" then
				-- up again without the server's get-up act (the end of a fight, an older server): he still
				-- gets up off the canvas the way he fell instead of popping upright
				local d = rig.down
				if d and not (rig.act and rig.act.kind == "getup") then
					rig.act = Down.recoverAct(d, now)
				end
				Down.clear(rig)
			end
		end
	elseif name == "Pose" or name == "Loop" then
		if v ~= old then
			rig.poseT = now
			rig.combo = nil
			rig.nextLook = 0 -- re-target now (bag on / off, watchers)
		end
	elseif name == "Count" then
		rig.countT = now
	elseif name == "ScaleKey" then
		-- the body was rescaled (ApplyDescription): re-measure the legs now (and once more when the
		-- replicated joints have surely arrived), never plant the feet at the old floor height
		rig.geoNow = true
	elseif name == "ShoutAt" then
		-- Ambience (F) just put a chat bubble over this coach: open the mouth now, and cup a hand by
		-- it when the arms are free (updateRig)
		rig.shoutReq = now
		if FaceFX then
			FaceFX.Shout(model, 1.1)
		end
	end
end

local function setup(model)
	if not model:IsA("Model") then
		return
	end
	local rig = rigs[model]
	if rig then
		readTags(rig)
		return
	end
	local seed = model:GetAttribute("AmbientSeed") or (#model.Name * 97 + 13)
	if type(seed) ~= "number" then
		seed = 13
	end
	rig = {
		model = model, joints = {}, geo = { ok = false }, a = {}, p = {}, kp = {}, kp2 = {},
		rng = Random.new(seed), seed = seed, phase = (seed % 100) / 100 * 6.28,
		root = model:FindFirstChild("HumanoidRootPart"), head = model:FindFirstChild("Head"),
		hum = model:FindFirstChildOfClass("Humanoid"),
		lastActId = model:GetAttribute("ActId"), predId = model:GetAttribute("PredActId"),
		act = nil, autoAct = nil, pending = nil, predKind = nil, predHand = nil, predT = -10, predDur = 0,
		sx = table.create(R.NSPR, 0), sv = table.create(R.NSPR, 0),
		plant = false, stepDist = 0.45, stepTime = 1, liftK = 1,
		cxL = {}, cxR = {}, poseAct = nil, exprHint = nil, breath = 0,
		lookPos = nil, lookPart = nil, lookYaw = 0, lookPitch = 0, nextLook = 0, lookW = 0,
		guardT = 0, prevGuard = nil, poseT = 0, countT = 0,
		breathPhase = 0, nextAuto = 0, autoId = 0, sbCount = 0, combo = nil, comboI = 0,
		gesture = nil, nextGesture = 3, watch = nil, watchAct = nil,
		lastT = os.clock(), clock = 0, timeScale = 1, nextGeo = 0, nextResolve = 0, frameSkip = 0, slot = 0, impactT = -10,
		koTilt = (seed % 7) / 7 - 0.5, partner = nil, nextPartner = 0, curlCycle = 0, lod = 3,
		guardL = nil, guardR = nil, guardSink = 0, gl = { 0, 0, 0 }, gr = { 0, 0, 0 },
	}
	rig.isLocal = model == player.Character
	Loco.init(rig)
	Fight.setup(rig)
	readTags(rig)
	for name, v in pairs(model:GetAttributes()) do
		rig.a[name] = v
	end
	rig.a.Act = nil -- an act that happened before we saw the model is not replayed
	rig.conn = model.AttributeChanged:Connect(function(name)
		onAttr(rig, name)
	end)
	-- (a rescale also moves the floor under the root: re-measure on a HipHeight change too)
	if rig.hum then
		rig.hipConn = rig.hum:GetPropertyChangedSignal("HipHeight"):Connect(function()
			rig.geoNow = true
		end)
	end
	rig.isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
	R.resolveJoints(rig)
	R.computeGeo(rig)
	-- (its turn when it is a still figure drawn at a reduced rate: a crowd that streamed in together spreads
	-- evenly over the frames instead of updating all on one - an even cost, not a spike every other frame)
	nextSlot += 1
	rig.slot = nextSlot
	rigs[model] = rig
	if BodyFX then
		BodyFX.Track(model)
	end
end

local function teardown(model)
	local rig = rigs[model]
	if not rig then
		return
	end
	if model.Parent and (hasAnyTag(model) or isPlayerChar(model)) then
		readTags(rig)
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
	if rig.conn then
		rig.conn:Disconnect()
	end
	if rig.hipConn then
		rig.hipConn:Disconnect()
	end
	-- players keep their pump visible after training; NPC rigs are done
	if BodyFX and not Players:GetPlayerFromCharacter(model) then
		BodyFX.Untrack(model)
	end
	rigs[model] = nil
end

------------------------------------------------------------------------
-- Acts: Act / ActId (server), PredAct (local prediction), AutoAct (re-synthesized)
------------------------------------------------------------------------
onAct = function(rig, s, now, predicted)
	local k, f2, f3, f4, f5 = K.parseAct(s)
	if not k then
		return
	end
	if k == "cancel" then
		-- FightClient: the server refused the special this client predicted ("cancel|special|<id>", a
		-- predicted act): the move the key press started is called off and blends back to the guard
		local sp = rig.special
		if predicted and f2 == "special" and sp and sp.pred and (f3 == "" or f3 == sp.pred) then
			Fight.endSpecial(rig, now)
			if rig.predKind == "special" then
				rig.predKind = nil
			end
		end
		return
	end
	-- the local fighter's special already started on the key press: its server echo (same id) is dropped
	-- for as long as that move lasts, however late the echo comes (a laggy connection), so the set-up is
	-- never rewound; the move may have ended meanwhile (a hit, the bell) and must not start again
	if not predicted and k == "special" and rig.predKind == "special" and f2 == rig.predHand and now - rig.predT < rig.predDur then
		rig.predKind = nil
		return
	end
	-- the local fighter's punch already started on the key press: skip the server echo
	if not predicted and rig.predKind == k and now - rig.predT < 0.25 and (f2 == "" or f2 == rig.predHand) then
		rig.predKind = nil
		return
	end
	local act = { kind = k, start = now, f2 = f2, f3 = f3, dur = 0.4 }
	if PUNCHES[k] then
		act.hand = (f2 == "L" or f2 == "R") and f2 or Fight.PUNCH_HAND[k] or "R"
		act.zone = f3 == "body" and "body" or "head"
		act.windup = clamp(tonumber(f4) or 0.2, 0.08, 0.9)
		act.power = clamp(tonumber(f5) or 0.6, 0, 1.5)
		act.dur = act.windup * 2.05 + 0.045
		if predicted then
			rig.predKind, rig.predHand, rig.predT = k, act.hand, now
		end
		Fight.startPunch(rig, act, now)
		return
	elseif k == "special" then
		-- a special move (special|<id>|<hand>|<windup>|<power>): AnimFight plays its set-up and throws its
		-- punches on the FightMotion.Specials schedule; unknown ids are ignored
		-- (a predicted special is matched to its server echo by its id, for as long as the move lasts)
		local ok = Fight.startSpecial(rig, f2, f3, f4, f5, now)
		if predicted and ok then
			rig.predKind, rig.predHand, rig.predT, rig.predDur = k, f2, now, rig.special.dur
			rig.special.pred = f2 -- (what a "cancel" names)
		end
		return
	elseif k == "hit" or k == "hitbody" or k == "blockhit" then
		act.sev = clamp(tonumber(f4) or 0.5, 0, 1.5)
		act.dur = k == "blockhit" and 0.4 or 0.5 + 0.25 * act.sev
		-- (hit|punch|flag|sev|hand: the 5th field, the punching hand, is round 2 and optional)
		Fight.react(rig, k, f2, f3, act.sev, now, f5 ~= "" and f5 or nil)
	elseif k == "parryhit" then
		act.dur = 0.25
	elseif k == "slip" then
		act.dur = 0.42
	elseif k == "roll" then
		act.dur = 0.55
	elseif k == "parry" then
		act.dur = 0.3
	elseif k == "pivot" then
		act.dur = 0.4
	elseif k == "step" then
		act.dur = 0.36
	elseif k == "jump" then
		act.dur = clamp(tonumber(f4) or 0.32, 0.15, 0.8)
	elseif k == "stumble" then
		act.sev = clamp(tonumber(f3) or 0.6, 0, 1.5)
		act.dur = clamp(tonumber(f4) or 0.7, 0.2, 2)
		R.kick(rig, 1.2 * act.sev, 0, 0, 0.8 * act.sev, 0, 0, 0, 0, 0.6 * act.sev, 0, 0.5 * act.sev, 0.5 * act.sev, 0.4, 0.4)
	elseif k == "getup" then
		act.fall = f2 ~= "" and f2 or "back"
		-- (round 2: the server sends the get-up time of the fall, FightMotion.GetUpTime)
		act.dur = clamp(tonumber(f4) or 0.9, 0.4, 3.2)
		-- the get-up starts from the fall he is lying in (side, the way it turned him)
		local d = rig.down
		if d then
			act.side, act.yaw = d.side, d.yaw
		end
	elseif k == "refcount" then
		act.n = tonumber(f2) or 1
		act.dur = 0.95
	elseif k == "waveoff" then
		act.dur = 1.8
	elseif k == "catch" then
		act.dur = clamp(tonumber(f2) or 2.5, 0.8, 6)
	else
		return -- unknown acts are ignored safely
	end
	rig.act = act
end

local function applyAct(p, rig, act, t)
	if act.kind == "getup" then
		return Down.getup(p, rig, act, t - act.start, t)
	end
	return Fight.applyAct(p, rig, act, t)
end

------------------------------------------------------------------------
-- Who looks at whom (every ~0.5 s): opponents, athletes, the local player, LookAt
------------------------------------------------------------------------
local function isFighterRig(r)
	return r.isFighter
end
local function isAthleteRig(r)
	if r.isFighter or r.isTrainee then
		return true
	end
	local loop = r.a.Loop
	return r.isAmbient and (loop == "heavybag" or loop == "spar" or loop == "shadow" or loop == "rope" or loop == "curl")
end
local function isTraineeRig(r)
	return r.isTrainee
end
local function isRefRig(r)
	return r.isReferee or r.a.Loop == "referee"
end

local function nearestRig(rig, pos, maxD, filter)
	local best, bd = nil, maxD
	for _, r in pairs(rigs) do
		if r ~= rig and r.root and r.root.Parent and filter(r) then
			local d = (r.root.Position - pos).Magnitude
			if d < bd then
				best, bd = r, d
			end
		end
	end
	return best, bd
end

-- the hanging bag in front of a bag worker: the local gym's station bag (GymVisuals builds it in
-- workspace.LocalGym.Visual_<Station>, segment "Bag" = the middle of the bag) or a members' bag
-- (MapBuilder: model tagged MemberBag, part "MemberBag"); flat distance from the root under 6 studs
local BAG_RANGE = 6
local BAG_RANGE_IN = 1.55 -- root to bag surface at the working range (studs, scaled by the torso)
local function findBag(rig, pos)
	local function flat(part)
		local d = part.Position - pos
		return sqrt(d.X * d.X + d.Z * d.Z)
	end
	if rig.isTrainee then
		local st = rig.a.Station
		local lg = workspace:FindFirstChild("LocalGym")
		local vm = lg and lg:FindFirstChild("Visual_" .. (type(st) == "string" and st or "heavybag"))
		local bag = vm and vm:FindFirstChild("Bag", true)
		if bag and bag:IsA("BasePart") and flat(bag) < BAG_RANGE then
			return bag
		end
	end
	local best, bd = nil, BAG_RANGE
	for _, m in ipairs(CollectionService:GetTagged("MemberBag")) do
		local bp = m:FindFirstChild("MemberBag", true)
		if bp and bp:IsA("BasePart") then
			local d = flat(bp)
			if d < bd then
				best, bd = bp, d
			end
		end
	end
	return best
end

local WATCHERS = { coachwatch = true, ringside = true, cornerman = true, sitwatch = true, idle = true, mittidle = true, mitts = true }

local function chooseLook(rig, t)
	if t < rig.nextLook then
		return
	end
	rig.nextLook = t + 0.45 + rig.rng:NextNumber() * 0.35
	local a = rig.a
	local pos = rig.root.Position
	rig.lookPart, rig.lookA, rig.lookB, rig.watch = nil, nil, nil, nil
	if rig.bagPart then
		-- left the bag (re-found below while still on it)
		if rig.oppHead == rig.bagPart then
			rig.oppHead, rig.oppTorso = nil, nil
		end
		rig.bagPart = nil
	end
	if rig.isFighter then
		local o = nearestRig(rig, pos, 40, isFighterRig)
		rig.oppHead = o and o.model:FindFirstChild("Head") or nil
		rig.oppTorso = o and o.model:FindFirstChild("UpperTorso") or nil
		rig.oppRig = o
		rig.lookPart = rig.oppHead
		rig.watch = o and o.model or nil
		rig.refRig = nearestRig(rig, pos, 30, isRefRig)
		return
	end
	local loop = a.Loop
	if rig.isReferee or loop == "referee" then
		-- the downed man, else the middle of the two fighters
		local f1, f2
		for _, r in pairs(rigs) do
			if r.isFighter and r.root and (r.root.Position - pos).Magnitude < 30 then
				if r.a.Guard == "down" then
					rig.lookPart = r.model:FindFirstChild("Head")
					return
				end
				if not f1 then
					f1 = r
				elseif not f2 then
					f2 = r
				end
			end
		end
		rig.lookA = f1 and f1.model:FindFirstChild("Head")
		rig.lookB = f2 and f2.model:FindFirstChild("Head")
		return
	end
	if loop == "spar" and not a.Pose then
		local partner = rig.partner
		if partner and partner.model.Parent then
			rig.lookPart = partner.model:FindFirstChild("Head")
			rig.oppHead = rig.lookPart
			rig.oppTorso = partner.model:FindFirstChild("UpperTorso")
			rig.oppRig = partner
			rig.watch = partner.model
		end
		return
	end
	-- bag work: the bag is the target the punches land on, eyes on it
	if (rig.isTrainee and a.Pose == "heavybag") or (rig.isAmbient and not a.Pose and loop == "heavybag") then
		local bag = findBag(rig, pos)
		if bag then
			rig.bagPart, rig.oppHead, rig.oppTorso = bag, bag, bag
			-- how far to step in (POSE.heavybag): averaged over looks, so a swinging bag does not
			-- drag the stance around
			local lp = rig.root.CFrame:PointToObjectSpace(bag.Position)
			local r = min(bag.Size.Y, bag.Size.Z) * 0.5
			local sc = rig.geo.utScale
			local want = clamp(-lp.Z - r - BAG_RANGE_IN * clamp(sc and sc.Y or 1, 0.7, 1.4), 0, 1.1)
			rig.bagWant = rig.bagWant and (rig.bagWant + (want - rig.bagWant) * 0.3) or want
		else
			rig.bagWant = nil
		end
		return
	end
	if rig.isTrainee or rig.isPreview then
		return -- eyes on the work (FaceFX looks at the camera in the Creator)
	end
	local name = a.Pose or loop
	if WATCHERS[name] or rig.isAmbient or not rig.isTagged then
		local o
		if name == "mitts" or name == "mittidle" or name == "coachwatch" then
			o = nearestRig(rig, pos, 30, isTraineeRig)
		end
		if rig.isTagged then
			o = o or nearestRig(rig, pos, 45, isFighterRig) or nearestRig(rig, pos, 30, isAthleteRig)
		end
		if o then
			rig.lookPart = o.model:FindFirstChild("Head")
			rig.watch = o.model
			return
		end
		-- people look at you when you walk past (the gym's people: another player's boxer looks where HE
		-- looks on his own screen, never round at you)
		local char = player.Character
		local head = rig.isTagged and char and char ~= rig.model and char:FindFirstChild("Head")
		if head and (head.Position - pos).Magnitude < 18 then
			rig.lookPart = head
		end
	end
end

local function updateLookPos(rig)
	local la = rig.a.LookAt
	if typeof(la) == "Vector3" then
		rig.lookPos = la
	elseif rig.lookPart and rig.lookPart.Parent then
		rig.lookPos = rig.lookPart.Position
	elseif rig.lookA and rig.lookA.Parent and rig.lookB and rig.lookB.Parent then
		rig.lookPos = (rig.lookA.Position + rig.lookB.Position) / 2
	else
		rig.lookPos = nil
	end
end

-- head and shoulders turn towards the look target (70% neck, 30% waist), never owl-like
local function applyLook(p, rig, dt)
	local ty, tp = 0, 0
	local wgt = rig.lookW
	if rig.lookPos and wgt > 0 then
		local lp = rig.root.CFrame:PointToObjectSpace(rig.lookPos)
		local yaw = atan2(-lp.X, -lp.Z)
		if abs(yaw) < 2.2 then
			ty = clamp(yaw, -1.25, 1.25) * wgt
			tp = clamp(atan2(lp.Y - 1.5, sqrt(lp.X * lp.X + lp.Z * lp.Z)), -0.5, 0.4) * wgt
		end
	end
	local k = 1 - exp(-dt * 4)
	rig.lookYaw += (ty - rig.lookYaw) * k
	rig.lookPitch += (tp - rig.lookPitch) * k
	if abs(rig.lookYaw) + abs(rig.lookPitch) > 1e-3 then
		p.W = p.W * A(0, rig.lookYaw * 0.3, 0)
		p.Neck = p.Neck * A(rig.lookPitch * 0.85, rig.lookYaw * 0.7, 0)
	end
end

------------------------------------------------------------------------
-- Player characters around the world: the gait, jumps / falls, seats
------------------------------------------------------------------------
local HST = Enum.HumanoidStateType
-- states where the default animation is better than anything we would invent
local SKIP_STATES = { [HST.Climbing] = true, [HST.Swimming] = true, [HST.Dead] = true, [HST.Physics] = true, [HST.Ragdoll] = true }
-- the shortest Freefall that shows as a fall (s): shorter is a kerb / stair edge, the gait carries on
local AIR_MIN = 0.14
local airParams = RaycastParams.new()
airParams.FilterType = Enum.RaycastFilterType.Exclude
airParams.RespectCanCollide = true

-- is there ground just under another player's feet? (a ray from the root, a little past the hip height)
local function groundUnder(rig)
	local root = rig.root
	local hum = rig.hum
	local reach = (hum and hum.HipHeight or 2) + root.Size.Y * 0.5 + 1.2
	airParams.FilterDescendantsInstances = { rig.model }
	local ok, hit = pcall(workspace.Raycast, workspace, root.Position, Vector3.new(0, -reach, 0), airParams)
	return ok and hit ~= nil
end

local function playerPose(p, rig, t, dt)
	local hum = rig.hum
	if not hum or not hum.Parent then
		rig.hum = rig.model:FindFirstChildOfClass("Humanoid")
		hum = rig.hum
	end
	local st = hum and hum:GetState()
	if st and SKIP_STATES[st] then
		return "skip"
	end
	if hum and (hum.Sit or hum.SeatPart) then
		POSE.sit(p, rig, t)
		rig.airT = nil
		return "sit"
	end
	local vy = rig.root.AssemblyLinearVelocity.Y
	-- (another player's Humanoid state is not reliable here: he is in the air when nothing is under him -
	-- running up or down stairs is NOT a jump)
	local air
	if rig.isLocal then
		air = st == HST.Freefall or st == HST.Jumping
	else
		air = abs(vy) > 6 and not groundUnder(rig)
	end
	if air then
		rig.airT0 = rig.airT0 or t
		rig.airVy = min(rig.airVy or 0, vy)
	else
		rig.airT0 = nil
	end
	-- a frame or two of Freefall (a kerb, a stair edge, a part seam) is not a jump: the gait carries on;
	-- a real jump (Jumping) or a fall that lasts tucks the legs
	if air and (st == HST.Jumping or t - rig.airT0 >= AIR_MIN or rig.airT) then
		-- airborne: knees tuck on the way up, legs reach for the ground on the way down
		rig.airT = rig.airT or t
		local up = clamp(vy / 25, -1, 1)
		local tuck = max(0, up) * 0.6 + 0.25
		p.Root = A(-0.08, 0, 0)
		p.W = A(0.05 - 0.1 * up, 0, 0)
		p.Neck = A(-0.05, 0, 0)
		p.LH = A(0.5 * tuck + 0.2, 0, -0.05)
		p.RH = A(0.2 * tuck, 0, 0.05)
		p.LK = A(-1.1 * tuck, 0, 0)
		p.RK = A(-0.6 * tuck - 0.2, 0, 0)
		p.LA = A(-0.3, 0, 0)
		p.RA = A(-0.25, 0, 0)
		p.LS = A(0.4 + 0.5 * up, 0, -0.35)
		p.RS = A(0.3 + 0.5 * up, 0, 0.35)
		p.LE = A(0.6, 0, 0)
		p.RE = A(0.6, 0, 0)
		return "air"
	end
	if rig.airT then
		-- landing: the knees absorb it, as hard as the fall was (a hop barely, a drop off a ledge fully)
		local k = clamp((-(rig.airVy or 0) - 4) / 36, 0.15, 1) * clamp((t - rig.airT) / 0.35, 0.3, 1)
		rig.landT = t
		rig.airT = nil
		R.kick(rig, -0.8 * k, 0, 0, -0.6 * k, 0, 0, 0, 0, 1.4 * k, 0, 0.3 * k, 0.3 * k, 0, 0)
	end
	if not air then
		rig.airVy = 0
	end
	POSE.idle(p, rig, t, 0, 1, rig.model, dt)
	return "ground"
end

------------------------------------------------------------------------
-- Per-rig update
------------------------------------------------------------------------
-- poses whose arms are free for a shout gesture (mitt work keeps the pads up: face only)
local SHOUT_ARMS = { idle = true, walk = true, coachwatch = true, ringside = true, cornerman = true, sitwatch = true,
	mittidle = true }
local PUBLISH_POSE = { heavybag = "heavybag", guard = "shadow", speedbag = "speedbag" }

local function updateRig(rig, model, t, dt, lod, rdt)
	-- joints get replaced (head swap, rescale, respawn): re-resolve dead motors
	if t >= rig.nextResolve then
		rig.nextResolve = t + 1
		for _, k in ipairs(KEYS) do
			local j = rig.joints[k]
			if not j or not j.motor.Parent then
				R.resolveJoints(rig)
				rig.nextGeo = 0
				break
			end
		end
		rig.head = model:FindFirstChild("Head")
	end
	if (t >= rig.nextGeo and lod >= 2) or rig.geoNow then
		rig.nextGeo = rig.geoNow and t + 0.5 or t + 2.5
		rig.geoNow = false
		R.computeGeo(rig)
	end
	-- (the root moves in real time: sensing uses the real frame time, never the slowed one)
	Loco.sense(rig, rdt)
	R.clearPose(rig)
	rig.lod = lod
	rig.dt = dt
	local p = rig.p
	local a = rig.a
	local pose, loop = a.Pose, a.Loop
	chooseLook(rig, t)
	updateLookPos(rig)
	local guard
	local ropeOn = false
	rig.publish = false
	if rig.isFighter then
		if a.Guard == "down" then
			Down.pose(p, rig, t, dt)
			guard = "down"
		else
			if rig.down then
				Down.clear(rig)
			end
			guard = Fight.guardPose(p, rig, t, dt)
			if guard == "walk" then
				-- the ring walk: an upright, unhurried walk (it strides out rather than breaking into a jog),
				-- the gloves carried at the waist on half bent arms with half the swing, a swagger of the
				-- shoulders and a nod in step with the stride (standing: a slow bounce)
				rig.walkMax = 1.45
				POSE.idle(p, rig, t, 0, 1, model, dt)
				local lo = rig.loco
				local mv = lo.gaitW
				p.LE = p.LE:Lerp(A(1.05, 0, 0), 0.85)
				p.RE = p.RE:Lerp(A(1.05, 0, 0), 0.85)
				p.LS = p.LS * A(0.1, 0, -0.05)
				p.RS = p.RS * A(0.1, 0, 0.05)
				rig.armScale = 0.5
				-- (the pose is filtered on its way out: the stride's phase a touch ahead)
				local ph = 2 * PI * (lo.phase - (1 - lo.duty) + 0.06)
				p.W = p.W * A(0, 0.03 * sin(ph) * mv, 0.035 * math.cos(ph) * mv + 0.03 * sin(t * 3.5) * (1 - mv))
				p.Neck = p.Neck * A(0.035 * math.cos(2 * ph) * mv + 0.04 * sin(t * 7) * (1 - mv), 0, 0)
			end
		end
		rig.lookW = 0
	elseif (rig.isReferee or loop == "referee") and not pose then
		POSE.referee(p, rig, t, 0, 1, model, dt)
	elseif not rig.isTagged then
		-- a player walking around the world
		local st = playerPose(p, rig, t, dt)
		if st == "skip" then
			-- the default animation shows (climbing, swimming...): hand the joints back
			if not rig.released then
				rig.released = true
				Loco.release(rig)
			end
			return
		end
		rig.released = false
	else
		local name = pose or loop or (rig.isPreview and "preview") or "idle"
		local w = num(a.PoseSpeed, 1)
		local drive = a.PoseDrive
		if loop == "walk" or loop == "run" then
			-- moving members: the real gait follows the root (AnimLoco)
			if not pose then
				name = "idle"
			end
		end
		if type(drive) ~= "number" then
			-- automatic reps for other players and gym members
			local cyc = (t * 0.55 * w + rig.phase) % 1
			drive = cyc < 0.5 and smooth(cyc * 2) or smooth(2 - cyc * 2)
			if name == "curl" then
				rig.curlCycle = floor(t * 0.55 * w + rig.phase)
			end
		elseif name == "curl" then
			rig.curlCycle = num(a.RepCount, 0)
		end
		if name == "rope" then
			local spin = a.RopeSpin
			if type(spin) == "number" then
				rig.ropePhase = spin
			else
				rig.ropePhase = (rig.ropePhase or 0) + dt * 9 * w
			end
			rig.ropeFoot = a.RopeFoot
			ropeOn = true
		end
		local fn = POSE[name] or POSE.idle
		fn(p, rig, t, drive, w, model, dt)
		rig.poseAct = rig.poseAct or POSE_ACT[name]
		-- a coach's chat bubble (ShoutAt): the shout gesture goes with the words whenever the arms
		-- are free; the watch poses draw their own gestures, the others get the overlay here
		if rig.shoutReq then
			if t - rig.shoutReq < 0.5 and not rig.gesture and SHOUT_ARMS[name] then
				Gym.startGesture(rig, "shout", t, 1.2)
			end
			rig.shoutReq = nil
		end
		if rig.gesture and rig.gestureDrawnT ~= t and SHOUT_ARMS[name] then
			Gym.gestureOverlay(p, rig, t)
		end
		-- other players' bag / shadow / speed-bag work is re-synthesized here and published
		local autoLoop
		if rig.isTrainee and not rig.isLocal then
			autoLoop = PUBLISH_POSE[pose]
			rig.publish = autoLoop ~= nil
		elseif rig.isAmbient and not pose and (loop == "heavybag" or loop == "shadow" or loop == "spar") then
			autoLoop = loop
			rig.publish = loop ~= "shadow"
			if loop == "spar" then
				Gym.findPartner(rig, t)
			end
		end
		if autoLoop == "speedbag" then
			-- one strike per half circle of the fists
			local n = floor(t * 16 * w / PI)
			if n ~= rig.sbCount then
				rig.sbCount = n
				rig.autoId += 1
				model:SetAttribute("AutoAct", string.format("jab|%s|head|0.05|0.40", n % 2 == 0 and "L" or "R"))
				model:SetAttribute("AutoActId", rig.autoId)
			end
		elseif autoLoop then
			Gym.ambientAct(rig, autoLoop, t)
		end
		-- the strain of a hard set: a fine tremor in the working arms
		local eff = num(a.Effort, 0)
		if eff > 0.8 then
			local tr = (eff - 0.8) * 0.12
			p.RS = p.RS * A(tr * sin(t * 113), 0, tr * sin(t * 97))
			p.LS = p.LS * A(tr * sin(t * 107), 0, tr * sin(t * 89))
			p.RE = p.RE * A(tr * sin(t * 101), 0, 0)
			p.LE = p.LE * A(tr * sin(t * 103), 0, 0)
		end
	end
	-- base filter: poses glide, dazed guards lag
	local ab = p.snap and 1 or (1 - exp(-dt * (p.rate or 20)))
	local joints = rig.joints
	if rig.wasPlant and not rig.plant then
		-- leaving planted feet: the keyed legs start from where the IK left them
		for k in pairs(LEG_KEYS) do
			local j = joints[k]
			if j then
				j.base = j.cur
			end
		end
	end
	for _, k in ipairs(KEYS) do
		local j = joints[k]
		if j then
			j.base = j.base:Lerp(p[k], ab)
			p[k] = j.base
		end
	end
	-- overlays: reactions (springs: the cover-up here, the snaps after the filters), punches (per-hand
	-- layers), acts, gaze
	local springs = R.stepSprings(rig, dt)
	if springs then
		R.applySpringsPre(rig, p)
	end
	local near = lod >= 3
	Gym.runPending(rig, t)
	if guard ~= "down" then
		Fight.reactionTick(p, rig, t)
		Fight.specialTick(p, rig, t)
		Fight.punches(p, rig, t, near)
	else
		rig.special = nil
	end
	if rig.autoAct and not applyAct(p, rig, rig.autoAct, t) then
		rig.autoAct = nil
	end
	if rig.act and (guard ~= "down" or rig.act.kind == "getup" or rig.act.kind == "hit" or rig.act.kind == "hitbody") then
		if guard == "down" and rig.act.kind ~= "getup" then
			-- a knockout punch: the springs already carry the snap, the fall owns the body
			if t - rig.act.start > rig.act.dur then
				rig.act = nil
			end
		elseif not applyAct(p, rig, rig.act, t) then
			rig.act = nil
		end
	end
	if p.override then
		for _, k in ipairs(KEYS) do
			local j = joints[k]
			if j then
				j.base = p[k]
			end
		end
	end
	if not rig.isFighter then
		applyLook(p, rig, dt)
	end
	-- output filter (fast enough to keep the snap of a punch); while a punch is out the upper body
	-- barely filters at all: the punch's own curves are smooth, and a 40/s low-pass would leave a fist
	-- at 30 studs/s most of a stud behind the spot it was aimed at
	local ao = 1 - exp(-dt * 40)
	local aoPunch = 1 - exp(-dt * 100)
	local punching = rig.pun and (rig.pun.L or rig.pun.R)
	local plantOn = rig.plant and rig.geo.ok and joints.Root ~= nil
	for _, k in ipairs(KEYS) do
		local j = joints[k]
		if j and not (plantOn and LEG_KEYS[k]) then
			if punching and ARM_KEYS[k] then
				-- (and the punching arms never turn faster than PUNCH_JOINT_RATE: where the body's turn and
				-- the fist's path add up, the arm lags its target by a hair instead of whipping round)
				local nxt = j.cur:Lerp(p[k], aoPunch)
				local _, ang = (j.cur:Inverse() * nxt):ToAxisAngle()
				local maxA = PUNCH_JOINT_RATE * dt
				if ang > maxA then
					nxt = j.cur:Lerp(nxt, maxA / ang)
				end
				j.cur = nxt
			else
				j.cur = j.cur:Lerp(p[k], (punching and not LEG_KEYS[k]) and aoPunch or ao)
			end
		end
	end
	-- the gait's pelvis / shoulder motion and momentum, in step with the feet (after the filters)
	if joints.Root then
		local rx, ry, yawP, rollP, pitchP, wYaw, wPitch, wRoll, nYaw, nPitch, nRoll = Loco.bodyOffsets(rig, dt, t)
		local lo = rig.loco
		local jo = lo.jumpOff
		local jy = lo.jumpYaw
		local rootT = joints.Root.cur
		if rx ~= 0 or ry ~= 0 or yawP ~= 0 or rollP ~= 0 or pitchP ~= 0 then
			rootT = CF(rx, ry, 0) * rootT * A(pitchP, yawP, rollP)
		end
		-- a blow's hip / knee-drop translation (unfiltered; planted legs absorb it below)
		local st = springs and R.springRoot(rig)
		if st then
			rootT = st * rootT
		end
		-- a server nudge / pivot teleport glides instead of popping (the feet step after it)
		if (jo and jo.Magnitude > 1e-3) or (jy and abs(jy) > 1e-3) then
			local lj = jo and rig.root.CFrame:VectorToObjectSpace(jo) or Vector3.zero
			rootT = CF(lj) * A(0, jy or 0, 0) * rootT
		end
		rig.rootOut = rootT
		if joints.W and (wYaw ~= 0 or wPitch ~= 0 or wRoll ~= 0) then
			rig.wOut = joints.W.cur * A(wPitch, wYaw, wRoll)
		else
			rig.wOut = nil
		end
		if joints.Neck and (nYaw ~= 0 or nPitch ~= 0 or nRoll ~= 0) then
			rig.nOut = joints.Neck.cur * A(nPitch, nYaw, nRoll)
		else
			rig.nOut = nil
		end
	end
	-- a walker's arm swing, in step with the legs (after the filters, like the pelvis): opposite the legs,
	-- faded out while a gesture owns the arms
	local sL, eL, zL, sR, eR, zR = Loco.armOffsets(rig, dt, rig.gesture ~= nil)
	if sL and joints.LS and joints.LE and joints.RS and joints.RE then
		rig.armOut = true
		rig.lsOut = A(sL, 0, zL) * joints.LS.cur
		rig.leOut = joints.LE.cur * A(eL, 0, 0)
		rig.rsOut = A(sR, 0, zR) * joints.RS.cur
		rig.reOut = joints.RE.cur * A(eR, 0, 0)
	else
		rig.armOut = false
	end
	if plantOn then
		-- planting starts, or the rig crosses the foot-IK distance: blend the legs over (no pop)
		local nearLegs = lod >= 2
		if not rig.wasPlant or rig.nearLegs ~= nearLegs then
			-- (a distance switch eases over more slowly: the two leg solutions can be far apart)
			rig.plantBlend = (rig.wasPlant and rig.nearLegs ~= nil) and 0.45 or 0.25
			rig.plantT = t
			rig.nearLegs = nearLegs
			if not rig.wasPlant and nearLegs and rig.keyedLegs then
				-- out of keyed legs (a get-up, a fall, a seat): the feet start where they are
				Loco.seedFeet(rig, t)
			end
		end
		local rootT = rig.rootOut or joints.Root.cur
		if nearLegs then
			rootT = Loco.feet(rig, p, rootT, t, dt, true)
			rig.rootOut = rootT
		else
			Loco.farLegs(p, rig, rootT, t, dt)
			rig.foot.L.P, rig.foot.R.P = nil, nil
		end
		-- blend into the IK legs when planting starts (get-up, leaving a seat)
		local pb = rig.plantBlend or 0.25
		local bl = min(1, (t - (rig.plantT or 0)) / pb)
		local l0 = pb > 0.3 and 0.1 or 0.25
		local la = bl < 1 and (l0 + (1 - l0) * bl) or 1
		for k in pairs(LEG_KEYS) do
			local j = joints[k]
			if j then
				j.cur = la < 1 and j.cur:Lerp(p[k], la) or p[k]
			end
		end
	else
		Loco.release(rig)
	end
	rig.keyedLegs = not plantOn and joints.Root ~= nil
	rig.wasPlant = plantOn
	-- the output: filtered pose + gait offsets, the reaction snaps composed on top (never low-passed)
	local out = rig.outT
	if not out then
		out = {}
		rig.outT = out
	end
	for _, k in ipairs(KEYS) do
		local j = joints[k]
		if j then
			local v = j.cur
			if k == "Root" and rig.rootOut then
				v = rig.rootOut
			elseif k == "W" and rig.wOut then
				v = rig.wOut
			elseif k == "Neck" and rig.nOut then
				v = rig.nOut
			elseif rig.armOut and ARM_OUT[k] then
				v = rig[ARM_OUT[k]]
			end
			if springs then
				v = R.springOut(rig, k, v)
			end
			out[k] = v
		else
			out[k] = I
		end
	end
	-- a body on the canvas (keyed legs: a fall, the get-up) never sinks into it, whatever the springs do
	if not plantOn and (rig.down or (rig.act and rig.act.kind == "getup")) and joints.Root then
		local co = rig.clampOut
		if not co then
			co = {}
			rig.clampOut = co
		end
		R.floorClamp(rig, out, co)
	end
	for _, k in ipairs(KEYS) do
		local j = joints[k]
		if j and j.motor.Parent then
			j.motor.Transform = out[k]
		end
	end
	Gym.ropeVisual(rig, model, ropeOn, rig.ropePhase or 0)
end

------------------------------------------------------------------------
-- Registration & main loop
------------------------------------------------------------------------
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

-- every player character (the local one and everyone else's)
local function hookPlayer(plr)
	plr.CharacterAdded:Connect(function(char)
		task.defer(function()
			if char.Parent then
				setup(char)
			end
		end)
	end)
	if plr.Character then
		task.defer(setup, plr.Character)
	end
end
if DRIVE_PLAYERS then
	for _, plr in ipairs(Players:GetPlayers()) do
		hookPlayer(plr)
	end
	Players.PlayerAdded:Connect(hookPlayer)
end

local cam = workspace.CurrentCamera
-- one warning per rig and error (keyed by the rig table, weak: a rig dropped from `rigs` - its model gone,
-- torn down, or a respawn that makes a new rig for the same model - takes its memo with it, and a new
-- rig reports its own failures)
local warned = setmetatable({}, { __mode = "k" })
local fxWarned = {}

local function fxStep(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not fxWarned[name] then
		fxWarned[name] = true
		warn("[Animator] " .. name .. " failed: " .. tostring(err))
	end
end

-- cost of the per-frame update (rigs + FX), readable by profilers / tests: R.stats
local stats = { frames = 0, total = 0, max = 0, rigs = 0 }
R.stats = stats
local frameNo = 0
RunService.PreSimulation:Connect(function(dt)
	local t = os.clock()
	frameNo += 1
	dt = min(dt, 0.1)
	cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local localChar = player.Character
	local updated = 0
	for model, rig in pairs(rigs) do
		if not model.Parent then
			if rig.conn then
				rig.conn:Disconnect()
			end
			if rig.hipConn then
				rig.hipConn:Disconnect()
			end
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
			rig.nextGeo = 0
		end
		rig.isLocal = model == localChar
		local pos = root.Position
		local dist = (pos - camPos).Magnitude
		if dist > CULL then
			continue
		end
		rig.camDist = dist
		local onScreen = true
		if cam and dist > 8 then
			local _, vis = cam:WorldToViewportPoint(pos)
			onScreen = vis
		end
		-- far and off-screen rigs update less often (time steps stay correct: dt is per rig)
		local step = dist > FAR and 3 or (dist > MID and 2 or 1)
		if not onScreen then
			step = max(step, 4)
		end
		rig.frameSkip += 1
		local skip = rig.frameSkip < step
		if not skip then
			rig.frameSkip = 0
		end
		-- A background figure that stands its ground and moves slowly - between combinations at the bag,
		-- curling, skipping, stretching, watching from the apron - is drawn at half rate past the near band
		-- (under a tenth of the screen's height there: its motion reads the same, the gym's crowd costs a
		-- quarter less) and at a sixth off screen (only its shadow or a limb at the frame's edge can show).
		-- Never a walker (its root glides on every frame: planted feet re-solved on every other one shuffle
		-- with it, 3x the slide), never a punch, slip or step in flight or the treadmill run (a fast limb
		-- moves twice as far between two updates), never a fighter or your own character. The figures slowed
		-- here take turns by their slot (an even cost, never the whole crowd on one frame); every other rig
		-- keeps the cadence above
		if not rig.isFighter and not rig.isLocal then
			local lo, pun = rig.loco, rig.pun
			if lo.speed < 0.5 and abs(lo.yawRate) < 0.5 and not (pun.L or pun.R or rig.act or rig.autoAct) and rig.a.Pose ~= "run" then
				local slow = onScreen and (dist > NEAR and 2 or 1) or 6
				if slow > step then
					skip = (frameNo + rig.slot) % slow ~= 0
				end
			end
		end
		if skip then
			-- (a player character's own Animate tracks write the joints every frame: a skipped frame holds
			-- our last pose instead of flashing Roblox's walk between ours)
			if rig.isPlayer and rig.outT and not rig.released then
				local out = rig.outT
				for k, j in pairs(rig.joints) do
					local v = out[k]
					if v and j.motor.Parent then
						j.motor.Transform = v
					end
				end
			end
			continue
		end
		local rdt = clamp(t - rig.lastT, 1 / 240, 0.25)
		rig.lastT = t
		-- the rig's own clock: a knockout plays its key moment in slow motion (a real-time envelope that
		-- both fighters share); a rig whose root is travelling is never slowed (its feet must keep up)
		local ts = Down.timeScale(rig, t)
		if ts < 1 and rig.loco.speed > 1.5 then
			ts = 1
		end
		rig.timeScale = ts
		local sdt = rdt * ts
		rig.clock += sdt
		local lod = (dist < NEAR and onScreen) and 3 or (dist < MID and 2 or 1)
		updated += 1
		local ok, err = pcall(updateRig, rig, model, rig.clock, sdt, lod, rdt)
		if not ok then
			-- (a different error on the same rig is reported too: at most 3 per rig, never every frame)
			local w = warned[rig]
			err = tostring(err)
			if not w or (w.n < 3 and w.last ~= err) then
				w = w or { n = 0 }
				w.n += 1
				w.last = err
				warned[rig] = w
				warn("[Animator] " .. model.Name .. ": " .. err)
			end
		end
	end
	if FaceFX then
		fxStep("FaceFX", FaceFX.Update, dt, t, camPos, rigs, 3)
	end
	if BodyFX then
		fxStep("BodyFX", BodyFX.Update, dt, t, camPos, rigs)
	end
	if HairFX then
		fxStep("HairFX", HairFX.Update, dt, t, camPos, cam)
	end
	local cost = os.clock() - t
	stats.rigs = updated
	stats.frames += 1
	stats.total += cost
	if cost > stats.max then
		stats.max = cost
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
