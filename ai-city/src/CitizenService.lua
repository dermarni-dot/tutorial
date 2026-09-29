-- CitizenService (ModuleScript) — ServerScriptService.Modules.CitizenService
-- Brings AI City to life: spawns every citizen (dressed by CitizenLook, sized
-- by age), walks them along the sidewalks to wherever their daily routine
-- says (home, work for their whole shift, school, errands, hobbies), and
-- handles couples expecting babies: on the due day the parents go to the
-- hospital and the baby is born there, then the family walks home together.
--
--   CitizenService.Start(map)          -- Main calls this
--   CitizenService.Population          -- the Population object (families, ages, jobs)
--   CitizenService.Models[id]          -- a citizen's character model
--   CitizenService.Event               -- BindableEvent: :Fire(kind, data) for "Born", "Expecting", "GrewUp", "Retired", "NewDay"

local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Modules = ServerScriptService:WaitForChild("Modules")
local Population = require(Modules:WaitForChild("Population"))
local CitizenLook = require(Modules:WaitForChild("CitizenLook"))
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))

local CitizenService = {}
CitizenService.Models = {}
CitizenService.Event = Instance.new("BindableEvent")

local SCALE = { Baby = 0.42, Toddler = 0.58, Child = 0.72, Teen = 0.9, Adult = 1, Retired = 0.97 }
local SPEED = { Baby = 0.5, Toddler = 0.6, Child = 0.9, Teen = 1, Adult = 1, Retired = 0.8 }
local WALK_ANIM = "rbxassetid://507777826" -- Roblox's default R15 walk
local IDLE_ANIM = "rbxassetid://507766666" -- and idle

local map, pop
local folder
local brains = {} -- [id] = { Model, Humanoid, Root, Key, Token, At, Label }
local day = 0
local lastHour
local news = {}

--------------------------------------------------------------------------------
-- News board
--------------------------------------------------------------------------------
local function pushNews(text)
	table.insert(news, 1, text)
	while #news > 3 do
		table.remove(news)
	end
	MapBuilder.SetNews(table.concat(news, "\n"))
	print("[AI City] " .. text)
end

--------------------------------------------------------------------------------
-- Nameplates
--------------------------------------------------------------------------------
local function roleText(c)
	local stage = pop:Stage(c, day)
	local age = pop:Age(c, day)
	if stage == "Baby" then
		return "Baby • " .. age
	elseif stage == "Toddler" then
		return "Toddler • " .. age
	elseif stage == "Child" or stage == "Teen" then
		return "Student • " .. age
	elseif stage == "Retired" then
		return "Retired • " .. age
	end
	return (c.Job or "Looking for work") .. " • " .. age
end

local function makePlate(model, c)
	local head = model:FindFirstChild("Head")
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(200, 64)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 55
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local function line(name, y, h, font, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.4
		l.Text = ""
		l.Parent = gui
		return l
	end
	line("NameLine", 0, 24, Enum.Font.FredokaOne, Color3.new(1, 1, 1)).Text = c.Name
	line("RoleLine", 24, 18, Enum.Font.GothamBold, Color3.fromRGB(220, 225, 240))
	line("StatusLine", 42, 18, Enum.Font.GothamBold, Color3.fromRGB(255, 225, 140))
	gui.Parent = head
	return gui
end

local function refreshPlate(brain, c, activity)
	local gui = brain.Plate
	if not gui then
		return
	end
	gui.RoleLine.Text = roleText(c)
	local h = pop.Households[c.Household]
	local status = activity or brain.Activity or ""
	if h and h.Expecting and (c.Id == h.Partners[1] or c.Id == h.Partners[2]) then
		local left = pop:DaysToGo(h, day)
		status = (if left and left > 0 then "🍼 Baby due in " .. left .. " day" .. (if left == 1 then "" else "s") else "🍼 Baby due today!") .. "\n" .. status
		gui.Size = UDim2.fromOffset(200, 82)
		gui.StatusLine.Size = UDim2.new(1, 0, 0, 36)
	else
		gui.Size = UDim2.fromOffset(200, 64)
		gui.StatusLine.Size = UDim2.new(1, 0, 0, 18)
	end
	gui.StatusLine.Text = status
end

--------------------------------------------------------------------------------
-- Models
--------------------------------------------------------------------------------
local function setupPhysics()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Citizens")
		PhysicsService:CollisionGroupSetCollidable("Citizens", "Citizens", false)
	end)
end

local function animate(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local walk = Instance.new("Animation")
	walk.AnimationId = WALK_ANIM
	local idle = Instance.new("Animation")
	idle.AnimationId = IDLE_ANIM
	local ok1, walkTrack = pcall(animator.LoadAnimation, animator, walk)
	local ok2, idleTrack = pcall(animator.LoadAnimation, animator, idle)
	if not (ok1 and ok2) then
		return
	end
	walkTrack.Looped = true
	idleTrack.Looped = true
	idleTrack:Play()
	humanoid.Running:Connect(function(speed)
		if speed > 0.5 then
			if not walkTrack.IsPlaying then
				walkTrack:Play(0.2)
				idleTrack:Stop(0.2)
			end
		elseif walkTrack.IsPlaying then
			walkTrack:Stop(0.2)
			idleTrack:Play(0.2)
		end
	end)
end

-- A spot for a plan: { Point = Vector3, Place = table with Door/Inside or nil }
local function spread(id, radius)
	local a = (id * 2.399) % (math.pi * 2)
	local r = radius * (0.35 + ((id * 7) % 10) / 15)
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function destination(c, plan)
	local h = pop.Households[c.Household]
	if plan.Kind == "Home" then
		local home = h and h.Home and map.Homes[h.Home]
		if home then
			local slot = table.find(h.Members, c.Id) or 1
			return { Point = home.Inside + spread(slot, 3.5), Place = home }
		end
		return { Point = map.Places.Plaza.Inside + spread(c.Id, 12), Place = map.Places.Plaza }
	elseif plan.Kind == "Hobby" then
		local spots = map.HobbySpots[plan.Hobby] or map.BenchSpots
		if spots and #spots > 0 then
			return { Point = spots[(c.Id % #spots) + 1] + spread(c.Id, 1.5), Place = nil }
		end
	end
	local place = plan.Place and map.Places[plan.Place]
	if not place then
		place = map.Places.Plaza
	end
	if plan.Kind == "Work" and #place.WorkSpots > 0 then
		return { Point = place.WorkSpots[((c.WorkSpot or 1) - 1) % #place.WorkSpots + 1], Place = place }
	elseif plan.Kind == "Hospital" and place.Beds then
		return { Point = place.Beds[(c.Household % #place.Beds) + 1] + spread(c.Id, 1.5), Place = place }
	elseif plan.Kind == "School" then
		return { Point = place.Inside + Vector3.new(((c.Id * 5) % 20) - 10, 0, ((c.Id * 3) % 10) - 3), Place = place }
	end
	return { Point = place.Inside + spread(c.Id, 5), Place = place }
end

local function flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Walks through the points in order. Stops early if a newer walk started.
local function walk(brain, points, token)
	local humanoid, root = brain.Humanoid, brain.Root
	for _, p in ipairs(points) do
		if brain.Token ~= token or not root.Parent then
			return false
		end
		local started = os.clock()
		local limit = flat(root.Position, p) / math.max(1, humanoid.WalkSpeed) * 2 + 4
		local lastMove = os.clock()
		humanoid:MoveTo(p)
		while flat(root.Position, p) > 2.2 do
			task.wait(0.25)
			if brain.Token ~= token or not root.Parent then
				return false
			end
			if os.clock() - lastMove > 4 then
				humanoid:MoveTo(p) -- MoveTo gives up after 8 seconds, so keep asking
				lastMove = os.clock()
			end
			if os.clock() - started > limit then
				root.CFrame = CFrame.new(p + Vector3.new(0, 3, 0)) -- stuck: hop to the point
				break
			end
		end
	end
	return true
end

local function travel(brain, c, plan)
	local dest = destination(c, plan)
	brain.Token += 1
	local token = brain.Token
	brain.Activity = plan.Activity
	refreshPlate(brain, c, "🚶 On the way")
	task.spawn(function()
		local points = map.RouteBetween(brain.At or brain.Root.Position, dest.Place or dest.Point)
		table.insert(points, dest.Point)
		if walk(brain, points, token) then
			brain.At = dest.Place or dest.Point
			brain.Arrived = plan.Kind
			refreshPlate(brain, c, plan.Activity)
		end
	end)
end

local function spawnCitizen(c, atPosition)
	local stage = pop:Stage(c, day)
	local ok, model = pcall(CitizenLook.Build, { Name = c.Name, Job = c.Job, Age = pop:Age(c, day), Hobby = c.Hobby })
	if not ok or not model then
		warn("[CitizenService] Could not build " .. c.Name .. ": " .. tostring(model))
		return nil
	end
	pcall(function()
		model:ScaleTo(SCALE[stage] or 1)
	end)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	humanoid.WalkSpeed = (Config.WALK_SPEED or 14) * (SPEED[stage] or 1)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	for _, state in ipairs({ Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.FallingDown }) do
		humanoid:SetStateEnabled(state, false)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Citizens"
		end
	end
	model:SetAttribute("CitizenId", c.Id)
	model:PivotTo(CFrame.new(atPosition + Vector3.new(0, 3 * (SCALE[stage] or 1) + 0.5, 0)))
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil) -- the server moves citizens
	end)
	animate(humanoid)
	local old = brains[c.Id]
	local brain = { Model = model, Humanoid = humanoid, Root = root, Token = (old and old.Token or 0) + 1, Stage = stage }
	brain.Plate = makePlate(model, c)
	brains[c.Id] = brain
	CitizenService.Models[c.Id] = model
	return brain
end

--------------------------------------------------------------------------------
-- Life events
--------------------------------------------------------------------------------
local function handleEvents(events)
	for _, e in ipairs(events) do
		pushNews(e.Text)
		CitizenService.Event:Fire(e.Kind, e)
		if e.Citizen then
			-- growing up changes size and clothes: rebuild the model where it stands
			local brain = brains[e.Citizen.Id]
			if brain and brain.Model then
				local pos = brain.Root.Position
				local at = brain.At
				brain.Model:Destroy()
				local fresh = spawnCitizen(e.Citizen, Vector3.new(pos.X, 0.5, pos.Z))
				if fresh then
					fresh.At = at
				end
			end
		end
	end
end

local function checkBirths(hour)
	for _, h in ipairs(pop.Households) do
		if h.Expecting and pop:IsDue(h, day) then
			local carrier = brains[h.Expecting.Carrier]
			local atHospital = carrier and carrier.Arrived == "Hospital"
			if atHospital or hour >= 16 then
				local baby = pop:Birth(h, day)
				local parents = {}
				for _, id in ipairs(h.Partners) do
					table.insert(parents, pop.Citizens[id].First)
				end
				local where = if carrier then carrier.Root.Position else map.Places.Hospital.Inside
				local brain = spawnCitizen(baby, Vector3.new(where.X + 2, 0.5, where.Z))
				if brain then
					brain.At = map.Places.Hospital
				end
				pushNews("👶 " .. baby.Name .. " was born to " .. table.concat(parents, " & ") .. " " .. h.Last .. "!")
				CitizenService.Event:Fire("Born", { Citizen = baby, Household = h })
				for _, id in ipairs(h.Partners) do
					local b = brains[id]
					if b then
						b.Key = nil -- re-plan: time to go home with the baby
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Saving
--------------------------------------------------------------------------------
local store
local function save()
	if not store then
		return
	end
	local data = pop:Serialize()
	pcall(store.SetAsync, store, "Population_v1", data)
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
function CitizenService.Start(builtMap)
	map = builtMap or MapBuilder.Build()
	pop = Population.new(Config, map.Homes)
	CitizenService.Population = pop
	setupPhysics()
	folder = Instance.new("Folder")
	folder.Name = "Citizens"
	folder.Parent = workspace

	-- load the saved city (ages, families, babies born in earlier servers)
	local loaded = false
	if Config.SAVE_POPULATION then
		local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, Config.DATASTORE_NAME or "AICity_v1")
		if ok then
			store = ds
			local ok2, data = pcall(ds.GetAsync, ds, "Population_v1")
			if ok2 and data then
				loaded = pop:Load(data)
			end
		end
	end
	if not loaded then
		pop:Generate()
	end
	day = pop.Day
	for _, c in ipairs(pop.List) do
		c.LastStage = pop:Stage(c, day) -- so only changes from now on are announced
	end

	-- everyone starts where their routine says they should be right now
	local hour = Lighting.ClockTime
	for n, c in ipairs(pop.List) do
		local plan = pop:Plan(c, hour, day)
		local dest = destination(c, plan)
		local brain = spawnCitizen(c, dest.Point)
		if brain then
			brain.At = dest.Place or dest.Point
			brain.Key = plan.Kind .. ":" .. tostring(plan.Place or plan.Hobby or "")
			brain.Activity = plan.Activity
			brain.Arrived = plan.Kind
			refreshPlate(brain, c, plan.Activity)
		end
		if n % 8 == 0 then
			task.wait() -- spread the building over a few frames
		end
	end
	pushNews("🏙️ " .. #pop.List .. " people live in AI City. Talk to them, give speeches, win elections!")

	-- the routine: every second, send anyone whose plan changed on their way
	task.spawn(function()
		lastHour = Lighting.ClockTime
		while true do
			task.wait(1)
			local hour = Lighting.ClockTime
			if lastHour and hour < lastHour - 12 then
				-- midnight: a new day
				day += 1
				handleEvents(pop:NewDay(day))
				CitizenService.Event:Fire("NewDay", { Day = day })
				for id, brain in pairs(brains) do
					local c = pop.Citizens[id]
					if c then
						refreshPlate(brain, c)
					end
				end
			end
			lastHour = hour
			checkBirths(hour)
			for _, c in ipairs(pop.List) do
				local brain = brains[c.Id]
				if brain and brain.Root.Parent then
					local plan = pop:Plan(c, hour, day)
					local key = plan.Kind .. ":" .. tostring(plan.Place or plan.Hobby or "")
					if key ~= brain.Key then
						brain.Key = key
						brain.Arrived = nil
						travel(brain, c, plan)
					end
				end
			end
		end
	end)

	-- save every 2 minutes and when the server closes
	task.spawn(function()
		while true do
			task.wait(120)
			save()
		end
	end)
	game:BindToClose(save)
	return pop
end

function CitizenService.GetBrain(id)
	return brains[id]
end

return CitizenService
