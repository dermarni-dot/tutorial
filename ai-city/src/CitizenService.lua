-- CitizenService (ModuleScript) — ServerScriptService.Modules.CitizenService
-- Brings the citizens to life: spawns a dressed NPC for every person in Life,
-- walks them along the sidewalks to where their day takes them (with their
-- own pace, lane and little pauses), takes elevators, sits at desks, lifts
-- weights, sleeps in bed, plays soccer after school, chats and gossips with
-- friends, reacts to speeches and crimes, gets knocked out and wakes up in
-- the hospital, has babies, and grows up.
--
-- The server only decides WHERE people are and WHAT they're doing (the
-- "Action" and "Expression" attributes). Every player's client animates the
-- poses, props and faces (see CityClient), which keeps the server light.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Actions = require(Shared:WaitForChild("Actions"))
local CitizenLook = require(script.Parent:WaitForChild("CitizenLook"))
local Errands = require(script.Parent:WaitForChild("Errands"))

local CitizenService = {}
local S -- services (see Main)
local map, pop
local folder
local brains = {} -- [citizen id] = brain
local list = {} -- all brains (including temporary ones like extra police)
local byModel = {}
local taken = {} -- [spot] = brain using it
local tempId = 0

local ANIM = {
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	idle = "rbxassetid://507766666",
}
local WALK_SPEED = Config.WALK_SPEED or 7.5
local TRAVEL_SPEED = Config.TRAVEL_SPEED or 16
local HURRY_SPEED = Config.HURRY_SPEED or 12
local WATCH_RADIUS = Config.WATCH_RADIUS or 140

CitizenService.Brains = brains
CitizenService.List = list

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

local playerSpots = {} -- player positions, refreshed every tick
local function refreshPlayers()
	table.clear(playerSpots)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(playerSpots, root.Position)
		end
	end
end

local function nearestPlayerDistance(pos)
	local best = math.huge
	for _, p in ipairs(playerSpots) do
		local d = (p - pos).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end
CitizenService.NearestPlayerDistance = nearestPlayerDistance

local function hour()
	return S.City.Hour()
end

local function day()
	return S.City.Day()
end

local function gameTime()
	return day() * 24 + hour()
end

-- a stable random generator per citizen
local function rngFor(id, salt)
	return Random.new((id * 7919 + (salt or 0) * 104729) % 2147483646 + 1)
end

--------------------------------------------------------------------------------
-- Speech bubbles and reactions
--------------------------------------------------------------------------------
-- Shows a speech bubble over a citizen for everyone nearby
function CitizenService.Say(brain, text, expression, seconds)
	if not brain or not brain.Model or not brain.Model.Parent or not text then
		return
	end
	seconds = seconds or math.clamp(#text / 14, 2, 6)
	S.City.SendNear(brain.Root.Position, 110, { Type = "Bubble", Model = brain.Model, Text = text, Seconds = seconds })
	brain.Model:SetAttribute("Talking", true)
	if expression then
		brain.Model:SetAttribute("Expression", expression)
	end
	local token = {}
	brain.TalkToken = token
	task.delay(seconds, function()
		if brain.TalkToken == token and brain.Model then
			brain.Model:SetAttribute("Talking", false)
		end
	end)
end

local function setAction(brain, action)
	brain.Model:SetAttribute("Action", action or "")
end

local function setActivity(brain, text)
	brain.Model:SetAttribute("Activity", text or "")
end

local function refreshExpression(brain)
	if brain.C and not brain.C.Temp and brain.State ~= "ko" then
		local action = brain.Model:GetAttribute("Action")
		local expr = S.City.ExpressionFor(brain.C)
		if action == "sleep" or action == "nap" or action == "patient" then
			expr = "asleep"
		elseif action == "type" or action == "study" or action == "machine" or action == "lift" or action == "squat" or action == "fixcar" then
			if expr == "neutral" then
				expr = "focused"
			end
		elseif action == "dance" or action == "play" or action == "swing" or action == "game" then
			expr = if expr == "angry" or expr == "sad" then expr else "grin"
		end
		brain.Model:SetAttribute("Expression", expr)
		brain.Model:SetAttribute("Mood", math.floor(S.City.MoodOf(brain.C)))
	end
end

--------------------------------------------------------------------------------
-- Bodies
--------------------------------------------------------------------------------
local function setupPhysics()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Citizens")
		PhysicsService:CollisionGroupSetCollidable("Citizens", "Citizens", false)
	end)
end

local function loadTracks(brain)
	local animator = brain.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = brain.Humanoid
	brain.Tracks = {}
	for name, id in pairs(ANIM) do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, a)
		if ok and track then
			track.Looped = true
			track.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			brain.Tracks[name] = track
		end
	end
end

-- which body animation plays: "walk", "run", "idle" or nil (still: a pose from the client)
local function playTrack(brain, name, speed)
	if not brain.Tracks then
		return
	end
	for n, track in pairs(brain.Tracks) do
		if n == name then
			if not track.IsPlaying then
				track:Play(0.25)
			end
			if speed then
				track:AdjustSpeed(speed)
			end
		elseif track.IsPlaying then
			track:Stop(0.25)
		end
	end
end

local function rootHeight(brain)
	return brain.Humanoid.HipHeight + brain.Root.Size.Y / 2
end

local function stageOf(c)
	return if c.Temp then "Adult" else pop:Stage(c)
end

local function ageOf(c)
	return if c.Temp then (c.Age or 30) else pop:Age(c)
end

local function describe(c)
	local job = if stageOf(c) == "Adult" then c.Job else nil
	return { Name = c.Name, Job = job, Age = ageOf(c), Hobby = c.Hobby }
end

local function jobOf(c)
	return c.Job and pop.Jobs(Config, c.Job)
end

local function refreshInfo(brain)
	local c = brain.C
	local m = brain.Model
	local stage = stageOf(c)
	m:SetAttribute("CitizenId", c.Id)
	m:SetAttribute("DisplayName", c.Name)
	m:SetAttribute("First", c.First or c.Name)
	m:SetAttribute("Age", ageOf(c))
	m:SetAttribute("Stage", stage)
	m:SetAttribute("Job", if stage == "Adult" then (c.Job or "") else "")
	m:SetAttribute("Personality", c.Personality or "")
	m:SetAttribute("Hobby", c.Hobby or "")
	if not c.Temp then
		local h = pop.Households[c.Household]
		local due = h and pop:DaysToGo(h)
		m:SetAttribute("Expecting", if due and h.Expecting.Carrier == c.Id then due else -1)
		local school = pop:SchoolFor(c)
		m:SetAttribute("School", school and (Config.PlaceById[school] and Config.PlaceById[school].label or school) or "")
		local home = h and h.Home and map.Homes[h.Home]
		m:SetAttribute("Address", home and home.Address or "")
	end
end

local function makeBody(c, cframe)
	local model, look = CitizenLook.Build(describe(c))
	look = look or CitizenLook.Describe(describe(c))
	model.Name = c.Name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoJumpEnabled = true
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 30
	for _, st in ipairs({ Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Flying }) do
		humanoid:SetStateEnabled(st, false)
	end
	local scale = look.Scale or 1
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Citizens"
		end
	end
	model:PivotTo(cframe)
	pcall(function()
		-- with StreamingEnabled, a citizen arrives on players' screens all at once
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	CollectionService:AddTag(model, "Citizen")
	model:SetAttribute("Scale", scale)
	return model, humanoid, root, look
end

--------------------------------------------------------------------------------
-- Spots: where people stand, sit, work and sleep
--------------------------------------------------------------------------------
local function free(spot, brain)
	return spot and (taken[spot] == nil or taken[spot] == brain)
end

local function reserve(brain, spot)
	if brain.Spot and taken[brain.Spot] == brain then
		taken[brain.Spot] = nil
	end
	brain.Spot = spot
	if spot then
		taken[spot] = brain
	end
end

-- the best free spot in a list: matching the wanted action, then any
local function pickSpot(spots, brain, want, roles, rng)
	local matches, others = {}, {}
	for _, s in ipairs(spots or {}) do
		if free(s, brain) and (not roles or roles[s.Role]) then
			if want and s.Action == want then
				table.insert(matches, s)
			else
				table.insert(others, s)
			end
		end
	end
	local pool = if #matches > 0 then matches else others
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

local KID_ROLES = { kid = true, visit = true }
local VISIT_ROLES = { visit = true }
local STUDENT_ROLES = { student = true }
local HOME_ROLES = { home = true }

--------------------------------------------------------------------------------
-- Where a plan takes someone: { Spot, Pos, Door, Building, Floor, Place, Action }
--------------------------------------------------------------------------------
local function placeFallback(id)
	return map.Places[id] or map.Places.Plaza or map.PlaceList[1]
end

local function homeOf(c)
	local h = pop.Households[c.Household]
	return h and h.Home and map.Homes[h.Home]
end

local function standNear(place, rng)
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(2, 7)
	local base = if place.Outdoor then place.Door else (place.Inside or place.Door)
	return base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function workSpotFor(brain, place, rng)
	local c = brain.C
	local work = {}
	for _, s in ipairs(place.Spots) do
		if s.Role == "work" then
			table.insert(work, s)
		end
	end
	if #work == 0 then
		return nil
	end
	-- a free till first: customers need someone to check them out
	for _, s in ipairs(work) do
		if (s.Action == "cashier" or s.Action == "counter") and free(s, brain) and not brain.C.Temp then
			return s
		end
	end
	-- their own desk first (same one every day), then any free one
	local mine = work[((c.WorkSpot or c.Id) - 1) % #work + 1]
	if free(mine, brain) then
		return mine
	end
	return pickSpot(work, brain, nil, nil, rng)
end

local function targetFor(brain, plan)
	local c = brain.C
	local rng = rngFor(c.Id, day() * 24 + math.floor(hour()))
	local t = { Plan = plan }
	if plan.Kind == "Home" then
		local home = homeOf(c)
		if not home then
			-- no home: a bench in the park
			local place = placeFallback("Park")
			t.Place, t.Door, t.Pos, t.Action = place, place.Door, standNear(place, rng), "sit"
			return t
		end
		S.MapBuilder.FurnishHome(home)
		local want = plan.Want
		local spots = home.Spots
		-- beds: each person has their own (kids share with siblings in turns)
		if want == "sleep" or want == "nap" then
			local stage = stageOf(c)
			local beds = {}
			for _, s in ipairs(spots) do
				if (s.Action == "sleep" or s.Action == "nap") and free(s, brain) then
					if stage == "Baby" and s.Crib then
						table.insert(beds, 1, s)
					else
						table.insert(beds, s)
					end
				end
			end
			t.Spot = beds[1]
		end
		t.Spot = t.Spot or pickSpot(spots, brain, want, HOME_ROLES, rng)
		t.Door, t.Building, t.Floor = home.Door, home.Building, home.Floor or 1
		t.Home = home
		if not t.Spot then
			t.Pos = home.Inside or home.Door
			t.Floor = 1
			t.Action = want or "wait"
		end
		return t
	end
	if plan.Kind == "Hobby" then
		if plan.Hobby == "jogging" then
			t.Jog = true
			local best, bestD = nil, math.huge
			for _, loop in ipairs(map.JoggingLoops) do
				local d = flatDist(loop[1], brain.Root.Position)
				if d < bestD then
					best, bestD = loop, d
				end
			end
			t.Loop = best
			t.Pos = best and best[1] or brain.Root.Position
			t.Door = t.Pos
			return t
		end
		local spots = map.HobbySpots[plan.Hobby]
		t.Spot = pickSpot(spots, brain, nil, nil, rng)
		if t.Spot then
			t.Door = t.Spot.CFrame.Position
			t.Place = t.Spot.Place and map.Places[t.Spot.Place]
			return t
		end
		plan = { Kind = "Place", Place = "Park", Want = "sit" }
	end
	local place = placeFallback(plan.Place)
	t.Place = place
	t.Door = place.Door
	if plan.Kind == "Work" then
		t.Spot = workSpotFor(brain, place, rng)
	elseif plan.Kind == "School" then
		if plan.Recess then
			local spots = {}
			for _, s in ipairs(place.Spots) do
				if s.Recess then
					table.insert(spots, s)
				end
			end
			t.Spot = pickSpot(spots, brain, plan.Want, nil, rng)
		else
			t.Spot = pickSpot(place.Spots, brain, "study", STUDENT_ROLES, rng)
		end
	elseif plan.Want == "soccer" and place.Field then
		t.Soccer = place.Field
		t.Pos = place.Field.Center + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-8, 8))
		return t
	elseif plan.Kind == "Hospital" then
		t.Spot = pickSpot(place.Spots, brain, "wait", VISIT_ROLES, rng)
	else
		local kid = ageOf(c) < 13
		t.Spot = pickSpot(place.Spots, brain, plan.Want, if kid then KID_ROLES else VISIT_ROLES, rng)
	end
	if t.Spot then
		t.Building, t.Floor = t.Spot.Building, t.Spot.Floor or 1
	else
		t.Pos = standNear(place, rng)
		t.Building = if place.Outdoor then nil else place.Building
		t.Floor = 1
		t.Action = if plan.Want == "chat" or plan.Want == nil then "wait" else plan.Want
	end
	return t
end

--------------------------------------------------------------------------------
-- Routes: steps of walking and riding elevators
--------------------------------------------------------------------------------
-- a waypoint list with this person's lane offset (people keep to their own
-- side of the sidewalk, so crowds don't walk single file)
local function withLane(points, lane)
	local out = {}
	for k, p in ipairs(points) do
		if k == 1 or k == #points then
			out[k] = p
		else
			local prev, nxt = points[k - 1], points[k + 1]
			local dir = flat(nxt - prev)
			if dir.Magnitude > 0.1 then
				local right = Vector3.new(-dir.Z, 0, dir.X).Unit
				out[k] = p + right * lane
			else
				out[k] = p
			end
		end
	end
	return out
end

local function elevatorExit(b, floor)
	local f = b and b.Elevator and b.Elevator.Floors[floor]
	return f and f.Exit
end

local function buildRoute(brain, t)
	local steps = {}
	local pos = brain.Root.Position
	local from = brain.Building
	local dest = t.Spot and t.Spot.CFrame.Position or t.Pos
	local destFloor = t.Floor or 1
	-- After(brain) runs when a step is done (so we always know if they're inside)
	local function walk(points, after)
		table.insert(steps, { Kind = "walk", Points = points, After = after })
	end
	local function ride(b, floor)
		table.insert(steps, { Kind = "ride", Building = b, Floor = floor })
	end
	if from and from == t.Building then
		-- same building: maybe another floor
		if (brain.Floor or 1) ~= destFloor then
			local exit = elevatorExit(from, brain.Floor or 1)
			if exit then
				walk({ exit })
			end
			ride(from, destFloor)
		end
		walk({ dest })
		return steps
	end
	if from then
		-- leave the building: down the elevator, out the door
		if (brain.Floor or 1) > 1 then
			local exit = elevatorExit(from, brain.Floor)
			if exit then
				walk({ exit })
			end
			ride(from, 1)
		end
		walk({ from.Inside, from.Door }, function(b)
			b.Building, b.Floor = nil, 1
		end)
		pos = from.Door
	end
	-- along the sidewalks
	local doorTarget = if t.Building then t.Building.Door else (t.Door or dest)
	local path = map.Route(pos, doorTarget)
	walk(withLane(path, brain.Lane))
	if t.Building then
		local b = t.Building
		walk({ b.Inside }, function(br)
			br.Building, br.Floor = b, 1
		end)
		if destFloor > 1 then
			local exit = elevatorExit(b, 1)
			if exit then
				walk({ exit })
			end
			ride(b, destFloor)
		end
	end
	walk({ dest })
	return steps
end

--------------------------------------------------------------------------------
-- Standing, sitting and lying at a spot
--------------------------------------------------------------------------------
local function unanchor(brain)
	if brain.Root.Anchored then
		brain.Root.Anchored = false
	end
	brain.Model:SetAttribute("SwingPivot", nil)
	brain.Model:SetAttribute("Target", nil)
end

-- stand up at a spot (used when leaving a seat or bed, so nobody gets stuck in furniture)
local function standAt(brain, cf)
	unanchor(brain)
	brain.Root.CFrame = CFrame.new(cf.Position + Vector3.new(0, rootHeight(brain) + 0.1, 0)) * cf.Rotation
	brain.Root.AssemblyLinearVelocity = Vector3.zero
end

local function placeAt(brain, spot, action)
	local cf = spot.CFrame
	local info = Actions.Get(action) or {}
	local scale = brain.Model:GetAttribute("Scale") or 1
	local rh = rootHeight(brain)
	local rootCf
	if info.Lying then
		local top = spot.BedTop or (cf.Position.Y + 2)
		local base = CFrame.new(cf.Position.X, top + 0.55 * scale, cf.Position.Z) * cf.Rotation * CFrame.Angles(0, math.pi, 0)
		-- the body lies along the bed with the head on the pillow
		rootCf = base * CFrame.new(0, 0, -1.2 * scale) * CFrame.Angles(math.rad(90), 0, 0)
	elseif info.Seated then
		local seat = spot.Seat
		if seat and seat.Parent then
			local top = seat.Position.Y + seat.Size.Y / 2
			rootCf = CFrame.new(seat.Position.X, top + 0.55 * scale, seat.Position.Z) * cf.Rotation
		else
			rootCf = CFrame.new(cf.Position + Vector3.new(0, rh - Actions.SEAT_DROP * scale + (spot.Raise or 0), 0)) * cf.Rotation
		end
	else
		rootCf = CFrame.new(cf.Position + Vector3.new(0, rh + (spot.Raise or 0), 0)) * cf.Rotation
	end
	brain.Root.Anchored = true
	brain.Root.CFrame = rootCf
	if spot.SwingPivot then
		brain.Model:SetAttribute("SwingPivot", spot.SwingPivot)
	end
	if spot.Hoop then
		brain.Model:SetAttribute("Target", spot.Hoop)
	end
end

--------------------------------------------------------------------------------
-- Moving
--------------------------------------------------------------------------------
local function speedFor(brain)
	local c = brain.C
	local base = WALK_SPEED * brain.Pace
	local d = nearestPlayerDistance(brain.Root.Position)
	local plan = brain.Plan
	local late = plan and (plan.Kind == "Work" or plan.Kind == "School") and brain.Late
	if brain.State == "flee" then
		return math.max(16, HURRY_SPEED * 1.35), "run"
	elseif brain.State == "police" then
		return 19, "run"
	elseif brain.Jog then
		return math.max(HURRY_SPEED - 1, 10) * brain.Pace, "run"
	elseif d > WATCH_RADIUS then
		return TRAVEL_SPEED, "walk"
	elseif late then
		return HURRY_SPEED, "run"
	end
	-- kids sometimes run ahead
	if ageOf(c) < 12 and brain.Skip and os.clock() < brain.Skip then
		return base * 1.6, "run"
	end
	return base, "walk"
end

local function applySpeed(brain)
	local speed, gait = speedFor(brain)
	brain.Humanoid.WalkSpeed = speed
	local animSpeed = if gait == "run" then speed / 16 else speed / 8
	playTrack(brain, gait, math.clamp(animSpeed, 0.6, 1.8))
end

local function stop(brain)
	brain.Steps = nil
	brain.Points = nil
	brain.Jog = nil
	brain.Looping = nil
	if not brain.Root.Anchored then
		brain.Humanoid:MoveTo(brain.Root.Position)
	end
end

local arrive -- forward

local function nextStep(brain)
	local done = brain.Steps and brain.Steps[brain.StepIndex]
	if done and done.After then
		done.After(brain)
	end
	brain.StepIndex += 1
	local step = brain.Steps and brain.Steps[brain.StepIndex]
	if not step then
		brain.Steps = nil
		arrive(brain)
		return
	end
	if step.Kind == "walk" then
		brain.Points = step.Points
		brain.PointIndex = 1
		brain.DetourFor = nil
		brain.LastMoveAt = os.clock()
		brain.LastPos = brain.Root.Position
		brain.MoveIssued = 0
		unanchor(brain)
		applySpeed(brain)
		brain.Humanoid:MoveTo(brain.Points[1])
	elseif step.Kind == "ride" then
		-- the elevator (or the stairs): wait a moment, then step out on the new floor
		brain.Points = nil
		brain.State = "ride"
		stop(brain)
		playTrack(brain, "idle")
		setAction(brain, "wait")
		local token = brain.Token
		task.delay(if step.Building.Elevator.Stairs then 1.2 else 2.4, function()
			if brain.Token ~= token or not brain.Model.Parent then
				return
			end
			local exit = elevatorExit(step.Building, step.Floor)
			if exit then
				brain.Root.CFrame = CFrame.new(exit + Vector3.new(0, rootHeight(brain) + 0.2, 0))
				brain.Root.AssemblyLinearVelocity = Vector3.zero
			end
			brain.Floor = step.Floor
			brain.Building = step.Building
			setAction(brain, "")
			brain.State = "walk"
			nextStep(brain)
		end)
	end
end

-- Sends a brain on its way to a target
local function go(brain, t)
	brain.Token = {}
	if not t.IsTask then
		brain.Tasks = nil
	end
	brain.Target = t
	brain.Jog = nil
	brain.Looping = nil
	local oldSpot = brain.Spot
	reserve(brain, t.Spot)
	if brain.Root.Anchored then
		-- get up first
		local cf = if oldSpot then oldSpot.CFrame else CFrame.new(brain.Root.Position - Vector3.new(0, rootHeight(brain), 0))
		standAt(brain, cf)
	end
	setAction(brain, "")
	brain.Model:SetAttribute("Place", t.Place and t.Place.Id or (t.Home and "Home") or "")
	brain.State = "walk"
	brain.Steps = buildRoute(brain, t)
	brain.StepIndex = 0
	brain.Late = false
	local plan = t.Plan
	if plan and (plan.Kind == "Work" or plan.Kind == "School") then
		local job = jobOf(brain.C)
		local start = if plan.Kind == "Work" and job then job.start else (Config.SCHOOL_START or 8)
		brain.Late = hour() > start - 0.1 and hour() < start + 4
	end
	nextStep(brain)
end

-- teleport straight to a target (spawning, or nobody around to see)
local function jump(brain, t)
	brain.Token = {}
	if not t.IsTask then
		brain.Tasks = nil
	end
	brain.Target = t
	brain.Jog = nil
	brain.Looping = nil
	reserve(brain, t.Spot)
	local dest = t.Spot and t.Spot.CFrame or CFrame.new(t.Pos or brain.Root.Position)
	standAt(brain, dest)
	brain.Building = t.Building
	brain.Floor = t.Floor or 1
	brain.Steps = nil
	arrive(brain)
end

--------------------------------------------------------------------------------
-- Soccer after school: a real ball, two teams, goals and cheering
--------------------------------------------------------------------------------
local soccer = {} -- [field] = { Ball, Players = { brain = team }, Score = {0, 0}, Kick = {} }

local function fieldOf(field)
	local match = soccer[field]
	if not match then
		match = { Players = {}, Score = { 0, 0 }, Field = field, Count = { 0, 0 }, Kick = {} }
		soccer[field] = match
	end
	return match
end

local function newBall(field)
	local ball = Instance.new("Part")
	ball.Name = "SoccerBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.8, 1.8, 1.8)
	ball.Color = Color3.fromRGB(245, 245, 245)
	ball.Material = Enum.Material.SmoothPlastic
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.25, 0.4, 0.55, 1, 1)
	ball.Position = field.Center + Vector3.new(0, 2, 0)
	ball.Parent = folder
	for k = 0, 2 do
		local patch = Instance.new("Part")
		patch.Name = "Patch"
		patch.Shape = Enum.PartType.Ball
		patch.Size = Vector3.new(0.8, 0.8, 0.8)
		patch.Color = Color3.fromRGB(30, 30, 34)
		patch.Material = Enum.Material.SmoothPlastic
		patch.CanCollide = false
		patch.Massless = true
		patch.CFrame = ball.CFrame * CFrame.Angles(k * 2.1, k * 1.3, 0) * CFrame.new(0, 0, -0.62)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = ball, patch
		weld.Parent = patch
		patch.Parent = ball
	end
	pcall(function()
		ball:SetNetworkOwner(nil)
	end)
	-- players can kick it too
	local lastKick = 0
	ball.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if player and root and os.clock() - lastKick > 0.35 then
			lastKick = os.clock()
			local dir = root.CFrame.LookVector
			ball.AssemblyLinearVelocity = Vector3.new(dir.X, 0, dir.Z).Unit * 42 + Vector3.new(0, 10, 0)
		end
	end)
	return ball
end

local function joinSoccer(brain, field)
	local match = fieldOf(field)
	local team = if match.Count[1] <= match.Count[2] then 1 else 2
	match.Players[brain] = team
	match.Count[team] += 1
	brain.State = "soccer"
	brain.Soccer = match
	brain.Model:SetAttribute("Team", team)
	setAction(brain, "soccer")
	setActivity(brain, "⚽ Playing soccer (" .. (if team == 1 then "Blue" else "Red") .. " team)")
end

local function leaveSoccer(brain)
	local match = brain.Soccer
	if match and match.Players[brain] then
		match.Count[match.Players[brain]] -= 1
		match.Players[brain] = nil
	end
	brain.Soccer = nil
	brain.Model:SetAttribute("Team", nil)
end

local GOAL_LINES = { "GOOOAL!!", "YES! GOAL!", "What a shot!", "Get in!!", "⚽⚽⚽" }
local SOCCER_LINES = { "Pass it!", "I'm open!", "Over here!", "Go go go!", "Nice!", "Defense!", "Shoot!" }

local function soccerTick(dt)
	for field, match in pairs(soccer) do
		local n = 0
		for _ in pairs(match.Players) do
			n += 1
		end
		if n < 2 then
			if match.Ball then
				match.Ball:Destroy()
				match.Ball = nil
				match.Score = { 0, 0 }
			end
			-- waiting for a second player: juggle near the center
			for brain in pairs(match.Players) do
				brain.Humanoid:MoveTo(field.Center + Vector3.new(math.sin(os.clock()) * 4, 0, 0))
			end
			continue
		end
		if not match.Ball or not match.Ball.Parent then
			match.Ball = newBall(field)
			match.Score = { 0, 0 }
		end
		local ball = match.Ball
		local bp = ball.Position
		local c = field.Center
		local halfL, halfW = field.Length / 2, field.Width / 2
		-- goals: team 1 attacks +X, team 2 attacks -X
		local rel = bp - c
		if math.abs(rel.X) > halfL + 0.5 then
			if math.abs(rel.Z) < 5 and rel.Y < 7 then
				local scorer = if rel.X > 0 then 1 else 2
				match.Score[scorer] += 1
				local names = {}
				for brain, team in pairs(match.Players) do
					if team == scorer then
						table.insert(names, brain)
					end
				end
				local hero = match.LastKicker and match.Players[match.LastKicker] == scorer and match.LastKicker or names[1]
				for brain, team in pairs(match.Players) do
					if team == scorer then
						CitizenService.React(brain, "cheer", if brain == hero then GOAL_LINES[math.random(1, #GOAL_LINES)] else nil, "grin", 2.5)
					end
				end
				S.City.SendNear(c, 160, { Type = "Toast", Icon = "⚽", Title = "GOAL!", Text = string.format("%s scores! Blue %d – %d Red", hero and hero.C.First or "Someone", match.Score[1], match.Score[2]), Color = if scorer == 1 then Color3.fromRGB(70, 130, 240) else Color3.fromRGB(230, 70, 70) })
			end
			ball.AssemblyLinearVelocity = Vector3.zero
			ball.CFrame = CFrame.new(c + Vector3.new(0, 2, 0))
			bp = ball.Position
		elseif math.abs(rel.Z) > halfW + 1 or rel.Y < -5 or rel.Y > 40 then
			-- out: throw it back in
			ball.AssemblyLinearVelocity = Vector3.zero
			ball.CFrame = CFrame.new(c + Vector3.new(math.clamp(rel.X, -halfL + 2, halfL - 2), 2, math.clamp(rel.Z, -halfW + 2, halfW - 2)))
			bp = ball.Position
		end
		-- the two closest players on each team chase the ball, the rest hold positions
		local byTeam = { {}, {} }
		for brain, team in pairs(match.Players) do
			table.insert(byTeam[team], brain)
		end
		for team, members in ipairs(byTeam) do
			table.sort(members, function(a, b)
				return flatDist(a.Root.Position, bp) < flatDist(b.Root.Position, bp)
			end)
			local attackDir = if team == 1 then 1 else -1
			local goal = c + Vector3.new(attackDir * (halfL + 1), 0, 0)
			for k, brain in ipairs(members) do
				brain.Humanoid.WalkSpeed = (if ageOf(brain.C) < 13 then 12 else 14) * brain.Pace
				playTrack(brain, "run", 0.9)
				local root = brain.Root
				local target
				if k <= 2 then
					-- come at the ball from behind (so the kick goes toward the goal)
					local behind = bp - (goal - bp).Unit * 1.6
					target = if k == 1 then behind else bp + Vector3.new(-attackDir * 8, 0, (if bp.Z > c.Z then -1 else 1) * 6)
				else
					local homeX = c.X - attackDir * halfL * (0.5 - (k - 3) * 0.2)
					target = Vector3.new(homeX, c.Y, math.clamp(bp.Z, c.Z - halfW + 3, c.Z + halfW - 3) + (k % 2 - 0.5) * 8)
				end
				brain.Humanoid:MoveTo(target)
				if flatDist(root.Position, bp) < 3.2 and (match.Kick[brain] or 0) < os.clock() then
					match.Kick[brain] = os.clock() + 0.8
					match.LastKicker = brain
					local aim = (goal + Vector3.new(0, 0, math.random(-4, 4)) - bp)
					aim = Vector3.new(aim.X, 0, aim.Z).Unit
					local spin = CFrame.Angles(0, math.rad(math.random(-25, 25)), 0)
					local power = if flatDist(bp, goal) < 20 then math.random(45, 60) else math.random(25, 42)
					ball.AssemblyLinearVelocity = spin:VectorToWorldSpace(aim) * power + Vector3.new(0, math.random(2, 12), 0)
					brain.Model:SetAttribute("Kick", os.clock())
					if math.random() < 0.12 then
						CitizenService.Say(brain, SOCCER_LINES[math.random(1, #SOCCER_LINES)], "grin", 1.5)
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Arriving and doing things
--------------------------------------------------------------------------------
arrive = function(brain)
	local t = brain.Target
	brain.Points = nil
	if not t then
		brain.State = "idle"
		playTrack(brain, "idle")
		return
	end
	local plan = t.Plan or {}
	brain.Building = t.Building
	brain.Floor = t.Floor or 1
	if t.Soccer then
		joinSoccer(brain, t.Soccer)
		return
	end
	if t.Jog and t.Loop then
		brain.State = "jog"
		brain.Jog = true
		brain.Points = t.Loop
		brain.PointIndex = 1
		brain.Looping = true
		applySpeed(brain)
		brain.Humanoid:MoveTo(t.Loop[1])
		setAction(brain, "")
		return
	end
	brain.State = "act"
	local action
	if t.Spot then
		action = t.Spot.Action
		-- the plan might want something else at a flexible spot (eg. reading on the sofa)
		if plan.Want and t.Home and t.Spot.Action ~= plan.Want and (plan.Want == "read" or plan.Want == "phone" or plan.Want == "tv") and Actions.Get(t.Spot.Action) and Actions.Get(t.Spot.Action).Seated then
			action = plan.Want
		end
		placeAt(brain, t.Spot, action)
	else
		action = t.Action or "wait"
		brain.Root.Anchored = true
		local p = t.Pos or brain.Root.Position
		local look = if t.Look then t.Look elseif t.Place and t.Place.Door then t.Place.Door else p + Vector3.new(0, 0, -1)
		if flatDist(look, p) < 0.5 then
			look = p + Vector3.new(0, 0, -1)
		end
		brain.Root.CFrame = CFrame.lookAt(Vector3.new(p.X, p.Y + rootHeight(brain), p.Z), Vector3.new(look.X, p.Y + rootHeight(brain), look.Z))
	end
	if not Actions.Get(action) then
		action = "wait"
	end
	local info = Actions.Get(action)
	playTrack(brain, if info.Seated or info.Lying or action == "run" or action == "soccer" then nil else "idle")
	setAction(brain, action)
	brain.ActUntil = os.clock() + math.random(35, 90)
	-- errands and rounds (see Errands): how long this step takes, what's in hand
	local checkout = nil
	if t.IsTask then
		brain.TaskUntil = os.clock() + (t.Duration or 10)
		brain.CheckoutWait, brain.RetryCheckout = 0, nil
		if t.Till then
			-- at a till: check out with the clerk behind it (or wait in line)
			checkout = CitizenService.TryCheckout(brain, t)
			if checkout == "busy" then
				setAction(brain, "wait")
				brain.RetryCheckout = t
				brain.TaskUntil = os.clock() + 2
				CitizenService.JoinQueue(brain, t)
			end
		end
		if t.Say and checkout ~= "started" and checkout ~= "busy" then
			CitizenService.Say(brain, t.Say, "happy", 2.2)
		end
	end
	if t.Carry ~= nil then
		brain.Model:SetAttribute("Carry", t.Carry or nil)
		brain.CommuteProp = nil
	elseif brain.CommuteProp or (t.Home and not t.IsTask) then
		-- put the briefcase / backpack / shopping bag down on arrival
		brain.Model:SetAttribute("Carry", nil)
		brain.CommuteProp = nil
	end
	refreshExpression(brain)
end

--------------------------------------------------------------------------------
-- Checkouts: a customer at a till and the clerk behind it do the sale together.
-- The customer puts their things on the counter, the clerk scans each one and
-- bags it, the customer pays by card and takes the bag (at a cafe: order, pay,
-- the order is made and handed over). Every client animates it from the
-- attributes set here, in step, from the server clock.
--------------------------------------------------------------------------------
local CLERK_HELLO = { "Hi there! Find everything okay?", "Next, please! Hi!", "Hello! Did you find what you were looking for?", "Hi! Good to see you again!" }
local CUSTOMER_REPLY = { "Yes, thanks!", "I did, thank you.", "Just these, please.", "Mm-hm! Busy day?" }
local FOOD_HELLO = { "Hi! What can I get you?", "Morning! The usual?", "Welcome! What'll it be?", "Hey there! What are you having?" }
local FOOD_ORDER = { "A latte, please!", "One of those, please.", "Something sweet, please!", "The usual!", "A coffee to go, please." }
local THANKS = { "Thanks! Have a great day!", "Thank you! See you soon!", "Enjoy! Bye now!", "Have a nice one!" }

local function clearCheckout(model, start)
	if model.Parent and model:GetAttribute("CheckoutStart") == start then
		for _, a in ipairs({ "CheckoutStart", "CheckoutKind", "CheckoutItems", "CheckoutTill", "CheckoutLook", "CheckoutRole" }) do
			model:SetAttribute(a, nil)
		end
	end
end

-- a line at the till: people wait one behind the other (not on top of each other)
local queues = {} -- [till spot] = { brain, ... }
function CitizenService.JoinQueue(brain, t)
	local q = queues[t.Till] or {}
	queues[t.Till] = q
	for k = #q, 1, -1 do
		if q[k] ~= brain and (not q[k].Model.Parent or q[k].QueueTill ~= t.Till) then
			table.remove(q, k)
		end
	end
	if not table.find(q, brain) then
		table.insert(q, brain)
	end
	brain.QueueTill = t.Till
	local place = table.find(q, brain)
	local back = flat(t.Pos - t.Till.CFrame.Position)
	back = if back.Magnitude > 0.1 then back.Unit else Vector3.new(0, 0, -1)
	local p = t.Pos + back * (2.4 * place)
	brain.Root.CFrame = CFrame.lookAt(Vector3.new(p.X, brain.Root.Position.Y, p.Z), Vector3.new(t.Till.CFrame.Position.X, brain.Root.Position.Y, t.Till.CFrame.Position.Z))
end
function CitizenService.LeaveQueue(brain)
	local q = brain.QueueTill and queues[brain.QueueTill]
	if q then
		local k = table.find(q, brain)
		if k then
			table.remove(q, k)
		end
	end
	brain.QueueTill = nil
	-- step up to the counter
	local t = brain.RetryCheckout
	if t and t.Pos then
		local look = t.Look or t.Till.CFrame.Position
		brain.Root.CFrame = CFrame.lookAt(Vector3.new(t.Pos.X, brain.Root.Position.Y, t.Pos.Z), Vector3.new(look.X, brain.Root.Position.Y, look.Z))
	end
end

-- "started", "busy" (the clerk is serving someone else) or "none" (nobody at the till)
function CitizenService.TryCheckout(brain, t)
	local till = t.Till
	local clerk = till and taken[till]
	if not clerk or clerk == brain or clerk.State ~= "act" or clerk.Spot ~= till or not clerk.Model.Parent then
		return "none"
	end
	local now = workspace:GetServerTimeNow()
	if (clerk.ServingUntil or 0) > now then
		return "busy"
	end
	local kind = t.CheckoutKind or "shop"
	local dur = Actions.CheckoutTime[kind] or 8
	clerk.ServingUntil = now + dur + 0.5
	local look = flat(brain.Root.Position - till.CFrame.Position)
	look = if look.Magnitude > 0.1 then look.Unit else till.CFrame.LookVector
	local items = if kind == "food" then 1 else math.random(3, 6)
	for _, m in ipairs({ brain.Model, clerk.Model }) do
		m:SetAttribute("CheckoutStart", now)
		m:SetAttribute("CheckoutKind", kind)
		m:SetAttribute("CheckoutItems", items)
		m:SetAttribute("CheckoutTill", till.CFrame.Position)
		m:SetAttribute("CheckoutLook", look)
		m:SetAttribute("CheckoutRole", if m == brain.Model then "customer" else "clerk")
	end
	setAction(brain, "checkout")
	brain.TaskUntil = os.clock() + dur + 0.3
	-- the little conversation, in step with the animation
	local token, clerkToken = brain.Token, clerk.Token
	local function say(at, who, line, expr)
		task.delay(at, function()
			if brain.Token == token and clerk.Token == clerkToken and who.Model.Parent then
				CitizenService.Say(who, line, expr, 2)
			end
		end)
	end
	local price = if kind == "food" then math.random(3, 7) else items * math.random(2, 4)
	if kind == "food" then
		say(0.1, clerk, FOOD_HELLO[math.random(1, #FOOD_HELLO)], "happy")
		say(1.3, brain, FOOD_ORDER[math.random(1, #FOOD_ORDER)], "happy")
		say(dur * 0.32, clerk, "That's " .. price .. " coins. Tap your card here.", "neutral")
		say(dur * 0.88, clerk, "Here you go! Enjoy!", "happy")
	else
		say(0.1, clerk, CLERK_HELLO[math.random(1, #CLERK_HELLO)], "happy")
		say(1.4, brain, CUSTOMER_REPLY[math.random(1, #CUSTOMER_REPLY)], "happy")
		say(dur * 0.6, clerk, "That comes to " .. price .. " coins.", "neutral")
		say(dur * 0.7, brain, "Card's fine. Here you go.", "happy")
		say(dur * 0.9, clerk, THANKS[math.random(1, #THANKS)], "happy")
	end
	task.delay(dur + 0.4, function()
		clearCheckout(brain.Model, now)
		clearCheckout(clerk.Model, now)
	end)
	return "started"
end

--------------------------------------------------------------------------------
-- Reactions (used by speeches, crimes, soccer, greetings)
--------------------------------------------------------------------------------
function CitizenService.CanReact(brain)
	return brain.State ~= "ko" and brain.State ~= "hospital" and brain.State ~= "talk" and brain.State ~= "police"
end

-- A quick reaction: an action (cheer, boo, wave, scared...), a line and a face
-- for a few seconds, then back to what they were doing.
function CitizenService.React(brain, action, line, expression, seconds, lookAt)
	if not CitizenService.CanReact(brain) then
		return
	end
	seconds = seconds or 3
	local before = brain.Model:GetAttribute("Action")
	local token = {}
	brain.ReactToken = token
	local info = Actions.Get(before or "") or {}
	local turned = false
	local oldCf = brain.Root.CFrame
	if lookAt and brain.Root.Anchored and not info.Seated and not info.Lying then
		local p = brain.Root.Position
		brain.Root.CFrame = CFrame.lookAt(p, Vector3.new(lookAt.X, p.Y, lookAt.Z))
		turned = true
	end
	if action and not info.Seated and not info.Lying then
		setAction(brain, action)
	end
	if line then
		CitizenService.Say(brain, line, expression, seconds)
	elseif expression then
		brain.Model:SetAttribute("Expression", expression)
	end
	task.delay(seconds, function()
		if brain.ReactToken ~= token or not brain.Model.Parent then
			return
		end
		brain.ReactToken = nil
		if brain.Model:GetAttribute("Action") == action then
			setAction(brain, before)
		end
		if turned and brain.Root.Anchored and brain.State == "act" then
			brain.Root.CFrame = oldCf
		end
		refreshExpression(brain)
	end)
end

function CitizenService.Nearby(position, radius)
	local out = {}
	for _, brain in ipairs(list) do
		if brain.Model.Parent and (brain.Root.Position - position).Magnitude <= radius then
			table.insert(out, brain)
		end
	end
	return out
end

function CitizenService.BrainOf(model)
	return byModel[model]
end

function CitizenService.GetBrain(id)
	return brains[id]
end

--------------------------------------------------------------------------------
-- Talking to a player: stop, turn, listen
--------------------------------------------------------------------------------
function CitizenService.Hold(brain, player)
	if brain.State == "ko" or brain.State == "hospital" or brain.State == "police" then
		return false
	end
	brain.Held = { Player = player, State = brain.State, Steps = brain.Steps, StepIndex = brain.StepIndex, Points = brain.Points, PointIndex = brain.PointIndex, Action = brain.Model:GetAttribute("Action"), Cf = brain.Root.CFrame, Anchored = brain.Root.Anchored }
	if brain.Soccer then
		leaveSoccer(brain)
		brain.Held.Steps = nil
	end
	brain.State = "talk"
	brain.Points = nil
	local root = brain.Root
	local info = Actions.Get(brain.Held.Action or "") or {}
	if not root.Anchored then
		brain.Humanoid:MoveTo(root.Position)
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
	end
	playTrack(brain, if info.Seated or info.Lying then nil else "idle")
	local proot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if proot and not info.Seated and not info.Lying then
		local p = root.Position
		root.CFrame = CFrame.lookAt(p, Vector3.new(proot.Position.X, p.Y, proot.Position.Z))
		setAction(brain, "listen")
	end
	brain.Model:SetAttribute("TalkingTo", player.UserId)
	return true
end

function CitizenService.Release(brain)
	local held = brain.Held
	brain.Held = nil
	brain.Model:SetAttribute("TalkingTo", nil)
	brain.Model:SetAttribute("Talking", false)
	if brain.State ~= "talk" or not held then
		return
	end
	brain.PlanKey = nil -- think again about where to be
	if held.State == "act" then
		brain.Root.CFrame = held.Cf
		setAction(brain, held.Action)
		brain.State = "act"
		refreshExpression(brain)
	elseif held.State == "walk" and held.Steps then
		brain.Root.Anchored = false
		brain.State = "walk"
		brain.Steps = held.Steps
		brain.StepIndex = held.StepIndex
		brain.Points = held.Points
		brain.PointIndex = held.PointIndex or 1
		setAction(brain, "")
		if brain.Points then
			applySpeed(brain)
			brain.Humanoid:MoveTo(brain.Points[brain.PointIndex])
			brain.LastMoveAt = os.clock()
		end
	else
		brain.Root.Anchored = false
		brain.State = "idle"
		setAction(brain, "")
	end
end

--------------------------------------------------------------------------------
-- Getting hurt, knocked out, fleeing (see CrimeService)
--------------------------------------------------------------------------------
local function interruptMovement(brain)
	if brain.Soccer then
		leaveSoccer(brain)
	end
	if brain.Held then
		brain.Held = nil
		brain.Model:SetAttribute("TalkingTo", nil)
	end
	brain.Token = {}
	brain.Steps = nil
	brain.Points = nil
	brain.Looping = nil
	brain.Jog = nil
end

-- Runs away from a spot for a while, then carries on with the day
function CitizenService.Flee(brain, from, seconds, line)
	if brain.State == "ko" or brain.State == "hospital" or brain.State == "police" then
		return
	end
	interruptMovement(brain)
	local spot = brain.Spot
	reserve(brain, nil)
	if brain.Root.Anchored then
		standAt(brain, spot and spot.CFrame or CFrame.new(brain.Root.Position - Vector3.new(0, rootHeight(brain), 0)))
	end
	brain.State = "flee"
	setAction(brain, "scared")
	brain.Model:SetAttribute("Expression", "scared")
	if line then
		CitizenService.Say(brain, line, "scared", 2.5)
	end
	local away = flat(brain.Root.Position - from)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
	away = CFrame.Angles(0, math.rad(math.random(-35, 35)), 0):VectorToWorldSpace(away)
	local dest = brain.Root.Position + away * math.random(35, 55)
	-- stay inside the city
	dest = Vector3.new(math.clamp(dest.X, -map.Extent, map.Extent), brain.Root.Position.Y, math.clamp(dest.Z, -map.Extent, map.Extent))
	brain.Points = { dest }
	brain.PointIndex = 1
	brain.LastMoveAt = os.clock()
	brain.LastPos = brain.Root.Position
	brain.FleeUntil = os.clock() + (seconds or 8)
	applySpeed(brain)
	brain.Humanoid:MoveTo(dest)
end

-- A quick flinch when hit
function CitizenService.Hurt(brain, from, line, knock)
	if brain.State == "ko" or brain.State == "hospital" then
		return
	end
	brain.Model:SetAttribute("Expression", "hurt")
	-- which way the hit came from and how hard (for the hit reaction, see Poses)
	brain.Model:SetAttribute("HitFrom", from)
	brain.Model:SetAttribute("HitPower", knock or 22)
	brain.Model:SetAttribute("Hit", os.clock())
	if line then
		CitizenService.Say(brain, line, "hurt", 1.8)
	end
	if not brain.Root.Anchored then
		local dir = flat(brain.Root.Position - from)
		if dir.Magnitude > 0.1 then
			brain.Root.AssemblyLinearVelocity = dir.Unit * (knock or 22) + Vector3.new(0, 8 + (knock or 22) * 0.2, 0)
		end
	end
end

local function hospitalBed(brain)
	local hospital = map.Places.Hospital
	if not hospital then
		return nil
	end
	for _, s in ipairs(hospital.Spots) do
		if s.HospitalBed and free(s, brain) then
			return s
		end
	end
	for _, s in ipairs(hospital.Spots) do
		if s.Action == "patient" and free(s, brain) then
			return s
		end
	end
	return nil
end

-- Knocked out: falls down, stars spin, then an ambulance ride to the hospital
-- where they rest in bed for a couple of in-game hours.
function CitizenService.KnockOut(brain, byName)
	if brain.State == "ko" or brain.State == "hospital" then
		return false
	end
	interruptMovement(brain)
	reserve(brain, nil)
	brain.State = "ko"
	playTrack(brain, nil)
	local root = brain.Root
	local p = root.Position
	local groundY = p.Y - rootHeight(brain)
	root.Anchored = true
	local facing = flat(root.CFrame.LookVector)
	facing = if facing.Magnitude > 0.1 then facing.Unit else Vector3.new(0, 0, -1)
	root.CFrame = CFrame.lookAt(Vector3.new(p.X, groundY + 0.6, p.Z), Vector3.new(p.X, groundY + 0.6, p.Z) + facing) * CFrame.Angles(math.rad(90), 0, 0)
	setAction(brain, "ko")
	setActivity(brain, "💫 Knocked out!")
	brain.Model:SetAttribute("Expression", "hurt")
	brain.Model:SetAttribute("KnockedOut", true)
	if brain.C and not brain.C.Temp then
		S.City.Boost(brain.C, -35)
	end
	local token = brain.Token
	task.delay(9, function()
		if brain.Token ~= token or not brain.Model.Parent then
			return
		end
		brain.Model:SetAttribute("KnockedOut", false)
		if brain.C.Temp then
			-- extra police officers just go back to the station
			CitizenService.Despawn(brain)
			return
		end
		local bed = hospitalBed(brain)
		brain.State = "hospital"
		brain.HospitalUntil = gameTime() + 2
		setActivity(brain, "🤕 Recovering at the hospital")
		if bed then
			reserve(brain, bed)
			brain.Target = { Spot = bed, Building = bed.Building, Floor = bed.Floor or 1, Place = map.Places.Hospital }
			brain.Building, brain.Floor = bed.Building, bed.Floor or 1
			placeAt(brain, bed, "patient")
			setAction(brain, "patient")
		else
			local hospital = map.Places.Hospital or map.PlaceList[1]
			standAt(brain, CFrame.new(hospital.Inside or hospital.Door))
			brain.Root.Anchored = true
			setAction(brain, "patient")
		end
		brain.Model:SetAttribute("Expression", "sleepy")
	end)
	return true
end

--------------------------------------------------------------------------------
-- Extra people (police called in by CrimeService)
--------------------------------------------------------------------------------
function CitizenService.SpawnExtra(info, cframe)
	tempId -= 1
	local c = { Id = tempId, Name = info.Name, First = info.First or info.Name, Job = info.Job, Age = info.Age or 32, Temp = true, Personality = "calm", Hobby = "jogging" }
	local model, humanoid, root = makeBody(c, cframe)
	local brain = { C = c, Id = c.Id, Model = model, Humanoid = humanoid, Root = root, Pace = 1.1, Lane = 0, State = "idle", Floor = 1, Temp = true }
	loadTracks(brain)
	refreshInfo(brain)
	setActivity(brain, info.Activity or "🚓 On patrol")
	model:SetAttribute("Expression", "focused")
	byModel[model] = brain
	table.insert(list, brain)
	return brain
end

function CitizenService.Despawn(brain)
	reserve(brain, nil)
	leaveSoccer(brain)
	byModel[brain.Model] = nil
	local index = table.find(list, brain)
	if index then
		table.remove(list, index)
	end
	if brain.C and brain.C.Id and brains[brain.C.Id] == brain then
		brains[brain.C.Id] = nil
	end
	brain.Model:Destroy()
end

-- Lets another module steer a brain directly (police chases)
function CitizenService.Control(brain, on)
	if on then
		interruptMovement(brain)
		reserve(brain, nil)
		if brain.Root.Anchored then
			standAt(brain, CFrame.new(brain.Root.Position - Vector3.new(0, rootHeight(brain), 0)))
		end
		brain.State = "police"
		setAction(brain, "")
		applySpeed(brain)
	else
		brain.State = "idle"
		brain.PlanKey = nil
	end
end

function CitizenService.SetGait(brain, speed, gait)
	brain.Humanoid.WalkSpeed = speed
	playTrack(brain, gait or "run", math.clamp(speed / 16, 0.6, 1.6))
end

--------------------------------------------------------------------------------
-- Spawning citizens
--------------------------------------------------------------------------------
local function planKey(plan)
	return table.concat({ plan.Kind, tostring(plan.Place), tostring(plan.Hobby), tostring(plan.Want), tostring(plan.Recess) }, "|")
end

local function spawnCitizen(c)
	local plan = pop:Plan(c, hour(), day())
	local model, humanoid, root, look = makeBody(c, CFrame.new(0, 200, 0))
	local info = S.Life.PersonalityInfo and S.Life.PersonalityInfo[c.Personality] or {}
	local rng = rngFor(c.Id, 1)
	local age = ageOf(c)
	local pace = (info.Walk or 1) * rng:NextNumber(0.9, 1.1)
	if age >= 75 then
		pace *= 0.7
	elseif age >= 60 then
		pace *= 0.85
	elseif age < 4 then
		pace *= 0.55
	elseif age < 13 then
		pace *= 1.05
	end
	local brain = {
		C = c,
		Id = c.Id,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Look = look,
		Pace = pace,
		Lane = rng:NextNumber(-1.7, 1.7),
		State = "idle",
		Floor = 1,
	}
	brains[c.Id] = brain
	byModel[model] = brain
	table.insert(list, brain)
	loadTracks(brain)
	refreshInfo(brain)
	humanoid.Died:Connect(function()
		-- shouldn't happen (NPCs don't take damage), but just in case: respawn
		task.wait(3)
		if brains[c.Id] == brain then
			CitizenService.Despawn(brain)
			spawnCitizen(c)
		end
	end)
	brain.Plan = plan
	brain.PlanKey = planKey(plan)
	brain.LastAge = age
	setActivity(brain, plan.Activity)
	jump(brain, targetFor(brain, plan))
	return brain
end

-- how long someone's walk to work or school takes, in in-game hours
local function commuteHours(c)
	local home = homeOf(c)
	local placeId
	local job = jobOf(c)
	if job and pop:Stage(c) == "Adult" then
		placeId = job.place
	else
		placeId = pop:SchoolFor(c)
	end
	local place = placeId and map.Places[placeId]
	if not home or not place then
		return 0.5
	end
	local path = map.Route(home.Door, place.Door)
	local len = 0
	for k = 2, #path do
		len += flatDist(path[k], path[k - 1])
	end
	local seconds = len / (TRAVEL_SPEED * 0.85)
	return math.clamp(seconds * 24 / (Config.DAY_LENGTH or 480), 0.2, 2.5)
end

--------------------------------------------------------------------------------
-- Babies
--------------------------------------------------------------------------------
local function checkBirths()
	local h = hour()
	if h < 9 or h > 18 then
		return
	end
	for _, household in ipairs(pop.Households) do
		if household.Expecting and pop:IsDue(household) then
			-- both parents made it to the hospital?
			local ready = true
			for _, id in ipairs(household.Partners) do
				local b = brains[id]
				if b and b.Target and b.Target.Place ~= map.Places.Hospital then
					ready = false
				elseif b and b.State == "walk" then
					ready = false
				end
			end
			if ready or h > 15 then
				local baby = pop:Birth(household, day())
				local parents = {}
				for _, id in ipairs(household.Partners) do
					local p = pop.Citizens[id]
					if p then
						table.insert(parents, p.First)
						S.City.Boost(p, 30)
					end
				end
				S.City.Adjust("Happiness", 1)
				S.City.State.Births += 1
				S.City.News("👶 Welcome to the world, " .. baby.Name .. "! Born to " .. table.concat(parents, " & ") .. " at the hospital.", "Birth")
				S.City.Fire("Born", baby)
				local b = spawnCitizen(baby)
				-- announce it in the hospital
				for _, id in ipairs(household.Partners) do
					local pb = brains[id]
					if pb then
						CitizenService.React(pb, "cheer", if id == household.Partners[1] then "It's a baby! Welcome, " .. baby.First .. "! 💕" else nil, "love", 4)
					end
				end
				if b then
					refreshInfo(b)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The brain loop
--------------------------------------------------------------------------------
local function planFor(brain)
	local c = brain.C
	if brain.State == "hospital" then
		if gameTime() >= (brain.HospitalUntil or 0) then
			brain.State = "act"
			brain.Model:SetAttribute("Expression", "happy")
			CitizenService.Say(brain, "I feel much better now!", "happy", 2)
			brain.PlanKey = nil
		else
			return nil
		end
	end
	return pop:Plan(c, hour(), day())
end

local function think(brain)
	if brain.Temp then
		return
	end
	local st = brain.State
	if st == "ko" or st == "talk" or st == "police" or st == "ride" or st == "chat" or st == "flee" or st == "hospital" and gameTime() < (brain.HospitalUntil or 0) then
		return
	end
	local plan = planFor(brain)
	if not plan then
		return
	end
	local key = planKey(plan)
	setActivity(brain, if brain.Soccer then brain.Model:GetAttribute("Activity") else plan.Activity)
	if key == brain.PlanKey and st ~= "idle" and brain.Tasks then
		-- a clerk finishes serving the customer before moving on
		if (brain.ServingUntil or 0) > workspace:GetServerTimeNow() then
			return
		end
		-- the next step of an errand or a round (see Errands)
		if st == "act" and os.clock() > (brain.TaskUntil or 0) and brain.RetryCheckout then
			-- waiting in line at the till: try again (or pay at the self-checkout after a while)
			brain.CheckoutWait = (brain.CheckoutWait or 0) + 1
			local r = if brain.CheckoutWait < 6 then CitizenService.TryCheckout(brain, brain.RetryCheckout) else "none"
			if r == "busy" then
				brain.TaskUntil = os.clock() + 2
				-- shuffle forward as the line moves
				CitizenService.JoinQueue(brain, brain.RetryCheckout)
			else
				CitizenService.LeaveQueue(brain)
				brain.RetryCheckout = nil
				if r ~= "started" then
					setAction(brain, "pay")
					brain.TaskUntil = os.clock() + 5
				end
			end
			return
		end
		if st == "act" and os.clock() > (brain.TaskUntil or 0) then
			brain.TaskIndex += 1
			local nt = brain.Tasks[brain.TaskIndex]
			if not nt and Errands.Loops(brain, plan) then
				-- rounds start over for as long as the shift lasts
				brain.Tasks = Errands.Tasks(brain, plan, targetFor(brain, plan), Random.new())
				brain.TaskIndex = 1
				nt = brain.Tasks and brain.Tasks[1]
			end
			if nt then
				go(brain, nt)
			else
				brain.Tasks = nil
			end
		end
		return
	end
	if key == brain.PlanKey and st ~= "idle" then
		-- same plan: now and then move to another spot at the same place (browsing
		-- different aisles, a new machine at the gym...)
		if st == "act" and brain.ActUntil and os.clock() > brain.ActUntil and plan.Kind ~= "Work" and plan.Kind ~= "Home" and plan.Kind ~= "School" then
			brain.ActUntil = os.clock() + math.random(35, 90)
			local t = targetFor(brain, plan)
			if t.Spot and t.Spot ~= brain.Spot and t.Place and brain.Target and t.Place == brain.Target.Place then
				go(brain, t)
			end
		end
		return
	end
	if brain.Soccer then
		leaveSoccer(brain)
	end
	brain.Plan = plan
	brain.PlanKey = key
	local t = targetFor(brain, plan)
	-- errands and rounds: a chain of steps with a purpose (see Errands)
	local tasks = Errands.Tasks(brain, plan, t, Random.new())
	if tasks then
		t = tasks[1]
	end
	-- a briefcase on the way to the office, a backpack to school...
	if t.Carry == nil and not brain.Model:GetAttribute("Carry") then
		local carry = Errands.CommuteProp(brain, plan, t)
		if carry then
			brain.Model:SetAttribute("Carry", carry)
			brain.CommuteProp = true
		end
	end
	-- nobody around to see: skip the walk (babies never walk across town)
	brain.Tasks = tasks
	brain.TaskIndex = 1
	local dest = t.Spot and t.Spot.CFrame.Position or t.Pos or (t.Door or brain.Root.Position)
	local unseen = nearestPlayerDistance(brain.Root.Position) > WATCH_RADIUS * 2.2 and nearestPlayerDistance(dest) > WATCH_RADIUS * 2.2
	if ageOf(brain.C) < 3 or (unseen and math.random() < 0.5) then
		jump(brain, t)
	else
		go(brain, t)
	end
end

-- a few little things people do on the way
local PAUSES = { "phone", "wait", "wave" }
-- Personal space: people step around whoever is in their way (other citizens
-- and players) instead of walking through them. Two people walking toward
-- each other both keep to the right, so they pass cleanly; someone boxed in
-- on both sides waits a moment.
CitizenService.Avoid = true
local function steerAround(brain, target)
	local root = brain.Root
	local pos = root.Position
	local to = flat(target - pos)
	local dist = to.Magnitude
	if dist < 1.5 then
		return nil
	end
	local dir = to.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local blocker, blockAhead, blockSide = nil, math.huge, 0
	local leftBusy, rightBusy = false, false
	local function consider(otherPos)
		local rel = flat(otherPos - pos)
		if math.abs(otherPos.Y - pos.Y) > 5 then
			return
		end
		local ahead = rel:Dot(dir)
		local side = rel:Dot(right)
		if ahead > 0.2 and ahead < math.min(6, dist + 1) then
			if math.abs(side) < 2 and ahead < blockAhead then
				blocker, blockAhead, blockSide = otherPos, ahead, side
			elseif ahead < 3.5 and math.abs(side) < 4.2 then
				if side > 0 then
					rightBusy = true
				else
					leftBusy = true
				end
			end
		end
	end
	for _, other in ipairs(list) do
		if other ~= brain and other.Model.Parent and other.State ~= "hospital" then
			local op = other.Root.Position
			if math.abs(op.X - pos.X) < 7 and math.abs(op.Z - pos.Z) < 7 then
				consider(op)
			end
		end
	end
	for _, p in ipairs(playerSpots) do
		if math.abs(p.X - pos.X) < 7 and math.abs(p.Z - pos.Z) < 7 then
			consider(p)
		end
	end
	if not blocker then
		return nil
	end
	-- pass on the right, unless they're already on our right (or it's crowded there)
	local s = if blockSide > 0.3 then -1 else 1
	if (s == 1 and rightBusy) and not leftBusy then
		s = -1
	elseif (s == -1 and leftBusy) and not rightBusy then
		s = 1
	elseif rightBusy and leftBusy and blockAhead < 1.8 then
		return "wait"
	end
	local clear = 2.3 - math.abs(blockSide) * 0.4
	local step = pos + dir * math.min(3.5, blockAhead + 1.2) + right * s * clear
	-- never step aside into a wall: try the other side, or just wait
	if CitizenService.Blocked(pos, step) then
		local other = pos + dir * math.min(3.5, blockAhead + 1.2) - right * s * clear
		if CitizenService.Blocked(pos, other) then
			return "wait"
		end
		return other
	end
	return step
end
CitizenService.SteerAround = steerAround

--------------------------------------------------------------------------------
-- Walls: people check the way is clear, and walk around what's in the way
--------------------------------------------------------------------------------
local wallParams = RaycastParams.new()
pcall(function()
	wallParams.FilterType = Enum.RaycastFilterType.Exclude
	wallParams.RespectCanCollide = true
end)
local wallFilterAt = 0
local function refreshWallFilter()
	if os.clock() - wallFilterAt < 2 then
		return
	end
	wallFilterAt = os.clock()
	local list = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	pcall(function()
		wallParams.FilterDescendantsInstances = list
	end)
end

-- is something solid between two points (at waist height)?
function CitizenService.Blocked(from, to)
	refreshWallFilter()
	local a = Vector3.new(from.X, from.Y, from.Z)
	local b = Vector3.new(to.X, from.Y, to.Z)
	local dir = b - a
	if dir.Magnitude < 0.5 then
		return false
	end
	local ok, hit = pcall(function()
		return workspace:Raycast(a, dir, wallParams)
	end)
	return ok and hit ~= nil
end

-- find a way around whatever is in the way, and splice it into the route
local function detour(brain, target)
	if brain.Pathing or not brain.Points then
		return
	end
	brain.Pathing = true
	brain.DetourFor = brain.PointIndex
	local token = brain.Token
	local from = brain.Root.Position
	task.spawn(function()
		local ok, path = pcall(function()
			local p = PathfindingService:CreatePath({ AgentRadius = 1.4, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 })
			p:ComputeAsync(from, target)
			return p
		end)
		brain.Pathing = nil
		if not ok or not path or path.Status ~= Enum.PathStatus.Success or brain.Token ~= token or not brain.Points then
			return
		end
		local waypoints = path:GetWaypoints()
		if #waypoints < 3 then
			return
		end
		local index = brain.PointIndex
		local points = {}
		for i = 1, index - 1 do
			table.insert(points, brain.Points[i])
		end
		for i = 2, #waypoints - 1 do
			table.insert(points, waypoints[i].Position)
		end
		for i = index, #brain.Points do
			table.insert(points, brain.Points[i])
		end
		brain.Points = points
		brain.DetourFor = index + #waypoints - 2
		brain.Humanoid:MoveTo(points[index])
		brain.MoveIssued = os.clock()
		brain.LastMoveAt = os.clock()
	end)
end
CitizenService.Detour = detour

-- a standing spot that isn't inside anything solid (a tree, a bench, a wall):
-- the nearest clear point around `pos`
function CitizenService.ClearSpot(pos)
	local function clear(p)
		local ok, parts = pcall(function()
			local params = OverlapParams.new()
			params.RespectCanCollide = true
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { folder }
			return workspace:GetPartBoundsInBox(CFrame.new(p + Vector3.new(0, 3, 0)), Vector3.new(2, 4.5, 2), params)
		end)
		return not ok or parts == nil or #parts == 0
	end
	if clear(pos) then
		return pos
	end
	for r = 2, 8, 2 do
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local p = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if clear(p) then
				return p
			end
		end
	end
	return pos
end

local function walkTick(brain)
	local points = brain.Points
	if not points or brain.Root.Anchored then
		return
	end
	local root = brain.Root
	local target = points[brain.PointIndex]
	if not target then
		return
	end
	local final = brain.Steps and brain.StepIndex == #brain.Steps and brain.PointIndex == #points
	local d = flatDist(root.Position, target)
	local now = os.clock()
	-- level of detail: far from every player (and the next waypoint too), people
	-- hop from waypoint to waypoint instead of walking the whole way. Nobody can
	-- see it, the server saves work, and cross-town trips still fit the day.
	local hop = false
	if brain.State == "walk" and not brain.Looping then
		local far = WATCH_RADIUS * 2
		if nearestPlayerDistance(root.Position) > far and nearestPlayerDistance(target) > far then
			hop = true
			local nxt = points[brain.PointIndex + 1]
			local look = if nxt and flatDist(nxt, target) > 0.5 then Vector3.new(nxt.X, target.Y, nxt.Z) else target + root.CFrame.LookVector
			root.CFrame = CFrame.lookAt(target + Vector3.new(0, rootHeight(brain) + 0.1, 0), look + Vector3.new(0, rootHeight(brain) + 0.1, 0))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	if hop or (d < (if final then 1.3 else 2.2) and math.abs(root.Position.Y - rootHeight(brain) - target.Y) < 6) then
		brain.PointIndex += 1
		brain.LastMoveAt = now
		brain.LastPos = root.Position
		if brain.PointIndex > #points then
			if brain.Looping then
				brain.PointIndex = 1
			elseif brain.State == "flee" then
				return
			else
				brain.Points = nil
				nextStep(brain)
				return
			end
		end
		-- sometimes stop to check the phone or look around (not when late)
		if brain.State == "walk" and not brain.Late and math.random() < 0.035 and nearestPlayerDistance(root.Position) < WATCH_RADIUS then
			local action = PAUSES[math.random(1, 2)]
			brain.Humanoid:MoveTo(root.Position)
			playTrack(brain, "idle")
			setAction(brain, action)
			local token = brain.Token
			task.delay(math.random(15, 35) / 10, function()
				if brain.Token == token and brain.State == "walk" and brain.Points then
					setAction(brain, "")
					applySpeed(brain)
					brain.Humanoid:MoveTo(brain.Points[brain.PointIndex] or root.Position)
					brain.LastMoveAt = os.clock()
				end
			end)
			return
		end
		if ageOf(brain.C) < 12 and math.random() < 0.08 then
			brain.Skip = now + 2
		end
		applySpeed(brain)
		brain.Humanoid:MoveTo(points[brain.PointIndex])
		brain.MoveIssued = now
		-- a wall between here and there? find the way around it
		if nearestPlayerDistance(root.Position) < WATCH_RADIUS and CitizenService.Blocked(root.Position, points[brain.PointIndex]) then
			detour(brain, points[brain.PointIndex])
		end
		return
	end
	-- someone in the way? step around them (or wait a moment if boxed in)
	if CitizenService.Avoid and not hop and (brain.State == "walk" or brain.State == "flee") and nearestPlayerDistance(root.Position) < WATCH_RADIUS then
		local steer = steerAround(brain, target)
		if steer == "wait" then
			brain.WaitSince = brain.WaitSince or now
			if now - brain.WaitSince > 1.5 then
				-- waited long enough: squeeze past on the right
				local dir = flat(target - root.Position)
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, -1)
				steer = root.Position + dir * 2 + Vector3.new(-dir.Z, 0, dir.X) * 2.4
			end
		else
			brain.WaitSince = nil
		end
		if steer == "wait" then
			brain.Humanoid:MoveTo(root.Position)
			brain.Steering = now
			brain.LastMoveAt = now
			return
		elseif steer then
			brain.Humanoid:MoveTo(steer)
			brain.Steering = now
			brain.MoveIssued = now
			brain.LastMoveAt = now
			return
		elseif brain.Steering then
			brain.Steering = nil
			brain.Humanoid:MoveTo(target)
			brain.MoveIssued = now
		end
	end
	-- keep MoveTo alive (it times out after 8 seconds)
	if now - (brain.MoveIssued or 0) > 3 then
		brain.MoveIssued = now
		brain.Humanoid:MoveTo(target)
	end
	-- stuck? jump, then (if nobody's looking) hop past the obstacle
	if brain.LastPos and (root.Position - brain.LastPos).Magnitude > 1.5 then
		brain.LastPos = root.Position
		brain.LastMoveAt = now
	elseif now - (brain.LastMoveAt or now) > 1.2 and brain.DetourFor ~= brain.PointIndex then
		-- not getting anywhere: something's in the way, find a way around it
		detour(brain, target)
	elseif now - (brain.LastMoveAt or now) > 2.5 then
		brain.Humanoid.Jump = true
		if now - brain.LastMoveAt > 5 and (nearestPlayerDistance(root.Position) > 45 or now - brain.LastMoveAt > 8) then
			root.CFrame = CFrame.new(target + Vector3.new(0, rootHeight(brain) + 0.3, 0))
			root.AssemblyLinearVelocity = Vector3.zero
			brain.LastMoveAt = now
			brain.LastPos = root.Position
		end
	end
end

-- chatting, greeting friends and gossip
local chatCooldown = {}
local function startChat(a, b)
	local now = os.clock()
	chatCooldown[a] = now + math.random(50, 110)
	chatCooldown[b] = now + math.random(50, 110)
	local lines = S.Dialogue and S.Dialogue.SmallTalk(a.C, b.C) or { { 1, "Hi!" }, { 2, "Hey!" } }
	for _, brain in ipairs({ a, b }) do
		brain.ChatBack = { Cf = brain.Root.CFrame, Action = brain.Model:GetAttribute("Action") }
		brain.State = "chat"
	end
	local function face(x, y)
		local info = Actions.Get(x.ChatBack.Action or "") or {}
		if not info.Seated and not info.Lying then
			local p = x.Root.Position
			x.Root.CFrame = CFrame.lookAt(p, Vector3.new(y.Root.Position.X, p.Y, y.Root.Position.Z))
			setAction(x, "chat")
		end
	end
	face(a, b)
	face(b, a)
	task.spawn(function()
		for _, line in ipairs(lines) do
			local speaker = if line[1] == 1 then a else b
			if speaker.State ~= "chat" then
				break
			end
			CitizenService.Say(speaker, line[2], line[3], 2.8)
			task.wait(3)
		end
		-- gossip: they tell each other what they've heard about players
		local g = S.City.Gossip(a.C, b.C)
		if g and a.State == "chat" then
			CitizenService.Say(a, g, "surprised", 3.5)
			task.wait(3.5)
		end
		for _, brain in ipairs({ a, b }) do
			if brain.State == "chat" and brain.ChatBack then
				brain.Root.CFrame = brain.ChatBack.Cf
				setAction(brain, brain.ChatBack.Action)
				brain.State = "act"
				refreshExpression(brain)
			end
			brain.ChatBack = nil
		end
	end)
end

local greeted = {}
local function socialTick()
	local now = os.clock()
	local idle, walkers = {}, {}
	for _, brain in ipairs(list) do
		if not brain.Temp and brain.Model.Parent and nearestPlayerDistance(brain.Root.Position) < WATCH_RADIUS then
			local action = brain.Model:GetAttribute("Action")
			if brain.State == "act" and brain.Plan and brain.Plan.Kind ~= "Work" and brain.Plan.Kind ~= "School" and action ~= "sleep" and action ~= "nap" and action ~= "patient" and ageOf(brain.C) >= 4 and (chatCooldown[brain] or 0) < now then
				table.insert(idle, brain)
			elseif brain.State == "walk" then
				table.insert(walkers, brain)
			end
		end
	end
	-- two people near each other with nothing urgent to do strike up a conversation
	for i = 1, #idle do
		local a = idle[i]
		if a.State == "act" then
			for j = i + 1, #idle do
				local b = idle[j]
				if b.State == "act" and (a.Root.Position - b.Root.Position).Magnitude < 8 then
					local infoA = S.Life.PersonalityInfo[a.C.Personality] or {}
					local infoB = S.Life.PersonalityInfo[b.C.Personality] or {}
					local friends = table.find(a.C.Friends or {}, b.C.Id) or a.C.Household == b.C.Household
					local chance = ((infoA.Chat or 0.5) + (infoB.Chat or 0.5)) / 2 * (if friends then 1.4 else 0.6)
					if math.random() < chance * 0.5 then
						startChat(a, b)
						break
					end
				end
			end
		end
	end
	-- friends passing on the street wave and say hi
	for _, a in ipairs(walkers) do
		for _, id in ipairs(a.C.Friends or {}) do
			local b = brains[id]
			if b and b.Model.Parent and (b.State == "walk" or b.State == "act") and (a.Root.Position - b.Root.Position).Magnitude < 14 then
				local k = math.min(a.Id, b.Id) .. ":" .. math.max(a.Id, b.Id)
				if (greeted[k] or 0) < now then
					greeted[k] = now + 90
					CitizenService.React(a, "wave", S.Dialogue and S.Dialogue.Greeting(a.C, b.C) or ("Hi " .. b.C.First .. "!"), "happy", 2)
					task.delay(0.8, function()
						CitizenService.React(b, "wave", S.Dialogue and S.Dialogue.Greeting(b.C, a.C) or ("Hey " .. a.C.First .. "!"), "happy", 2)
					end)
				end
			end
		end
	end
	-- people who like a player say hi when they come close
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			for _, brain in ipairs(CitizenService.Nearby(root.Position, 12)) do
				if not brain.Temp and CitizenService.CanReact(brain) and brain.State ~= "chat" then
					local k = brain.Id .. ":" .. player.UserId
					if (greeted[k] or 0) < now then
						greeted[k] = now + 150
						local opinion = S.City.Opinion(brain.C, player)
						local wanted = (player:GetAttribute("Wanted") or 0) > 0
						if wanted then
							CitizenService.React(brain, nil, ({ "Stay away from me!", "Eek! It's that criminal!", "Somebody call the police!" })[math.random(1, 3)], "scared", 2.5)
						elseif opinion >= 25 then
							CitizenService.React(brain, "wave", S.Dialogue and S.Dialogue.GreetPlayer(brain.C, player, opinion) or ("Hi " .. player.DisplayName .. "!"), "happy", 2.5, root.Position)
						elseif opinion <= -25 then
							CitizenService.React(brain, nil, S.Dialogue and S.Dialogue.GreetPlayer(brain.C, player, opinion) or "Hmph.", "angry", 2.5)
						end
					end
				end
			end
		end
	end
end

function CitizenService.OnNewDay(newDay, events)
	for _, brain in ipairs(table.clone(list)) do
		if not brain.Temp then
			brain.C.CommuteHours = commuteHours(brain.C)
			local oldStage = brain.Model:GetAttribute("Stage")
			refreshInfo(brain)
			-- growing up: rebuild the body at the new size and look
			if oldStage ~= brain.Model:GetAttribute("Stage") or (ageOf(brain.C) < 18 and (brain.Model:GetAttribute("Age") or 0) ~= (brain.LastAge or -1)) then
				brain.LastAge = ageOf(brain.C)
				local c = brain.C
				local cf = brain.Root.CFrame
				CitizenService.Despawn(brain)
				local fresh = spawnCitizen(c)
				if fresh and not fresh.Root.Anchored then
					fresh.Root.CFrame = cf
				end
			end
		end
	end
	for _, e in ipairs(events or {}) do
		if e.Citizen and brains[e.Citizen.Id] then
			refreshInfo(brains[e.Citizen.Id])
		end
	end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
function CitizenService.Start(services)
	S = services
	CitizenService.Event = S.City.Event -- same events as CityService.Event (kept for older scripts)
	map, pop = S.Map, S.Life
	Errands.Init({ Map = map, PickSpot = pickSpot, StandNear = standNear, Age = ageOf, Clear = CitizenService.ClearSpot, Occupant = function(spot)
		return taken[spot]
	end })
	setupPhysics()
	folder = workspace:FindFirstChild("Citizens") or Instance.new("Folder")
	folder.Name = "Citizens"
	folder.Parent = workspace
	for _, c in ipairs(pop.List) do
		c.CommuteHours = commuteHours(c)
	end
	refreshPlayers()
	for k, c in ipairs(pop.List) do
		local ok, err = pcall(spawnCitizen, c)
		if not ok then
			warn("[CitizenService] Couldn't spawn " .. tostring(c.Name) .. ": " .. tostring(err))
		end
		if k % 6 == 0 then
			task.wait()
		end
	end
	for _, brain in ipairs(list) do
		brain.LastAge = ageOf(brain.C)
	end

	local acc, slow, social, births, faces = 0, 0, 0, 0, 0
	local order = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		local step = acc
		acc = 0
		refreshPlayers()
		for _, brain in ipairs(list) do
			if brain.Points and brain.Model.Parent then
				local ok, err = pcall(walkTick, brain)
				if not ok then
					warn("[CitizenService] walk: " .. tostring(err))
					brain.Points = nil
				end
			end
			if brain.State == "flee" and brain.FleeUntil and os.clock() > brain.FleeUntil then
				brain.FleeUntil = nil
				brain.State = "idle"
				brain.PlanKey = nil
				setAction(brain, "")
			end
		end
		soccerTick(step)
		-- think about a slice of the city every tick (everyone about once a second)
		slow += step
		local count = math.max(1, math.ceil(#list * step))
		for _ = 1, count do
			order = order % math.max(1, #list) + 1
			local brain = list[order]
			if brain and brain.Model.Parent then
				local ok, err = pcall(think, brain)
				if not ok then
					warn("[CitizenService] think: " .. tostring(err))
				end
			end
		end
		social += step
		if social >= 2 then
			social = 0
			pcall(socialTick)
		end
		faces += step
		if faces >= 5 then
			faces = 0
			for _, brain in ipairs(list) do
				if brain.State == "act" and not brain.ReactToken and not (brain.Model:GetAttribute("Talking")) then
					refreshExpression(brain)
				end
				if brain.C and not brain.C.Temp then
					local h = pop.Households[brain.C.Household]
					local due = h and pop:DaysToGo(h)
					brain.Model:SetAttribute("Expecting", if due and h.Expecting.Carrier == brain.C.Id then due else -1)
				end
			end
		end
		births += step
		if births >= 3 then
			births = 0
			pcall(checkBirths)
		end
	end)
end

return CitizenService
