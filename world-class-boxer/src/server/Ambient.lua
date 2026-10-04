-- Ambient: gym members, coaches and staff that bring the training complex to life.
-- They are server NPCs (everyone sees the same people) whose bodies are animated
-- client-side by the Animator from the "Loop" attribute. Some react to players:
-- the mitt coach puts his pads up, the barber starts cutting, the masseuse works.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared:WaitForChild("Looks"))
local Builder = require(Shared:WaitForChild("Builder"))
local Poser = require(script.Parent.Poser)
local okDecor, GymDecor = pcall(require, script.Parent.GymDecor)

local Ambient = {}
Ambient.Roles = {} -- role -> model

local V3 = Vector3.new

-- at = where they stand, look = what they face, floor = floor height there
local MEMBERS = {
	{ name = "Rico Vance", tag = "Gym Member", loop = "heavybag", at = V3(-36, 0, -26.4), look = V3(-36, 0, -30), hands = "gloves", seed = 101 },
	{ name = "Dee Okafor", tag = "Gym Member", loop = "heavybag", at = V3(-24, 0, -26.4), look = V3(-24, 0, -30), hands = "gloves", seed = 202, gender = 2 },
	{ name = "Coach Benny", tag = "Mitt Trainer", role = "MittCoach", loop = "mittidle", at = V3(14, 0, -13.5), look = V3(14, 0, -10), props = "mitts", seed = 303, age = 52 },
	{ name = "Marco Silva", tag = "Gym Member", loop = "shadow", at = V3(30, 0, -42), look = V3(22, 0, -50), hands = "wraps", seed = 404 },
	{ name = "Tasha Brooks", tag = "Gym Member", loop = "rope", at = V3(60, 0, 8), look = V3(60, 0, 0), props = "rope", seed = 505, gender = 2, stand = 0 },
	{ name = "Andre Cole", tag = "Gym Member", loop = "curl", at = V3(-62, 0, 8), look = V3(-62, 0, 0), props = "curl", seed = 606 },
	{ name = "Yuki Sato", tag = "Gym Member", loop = "stretch", at = V3(100, 0, 64), look = V3(90, 0, 64), seed = 707, gender = 2 },
	{ name = "Big Lou", tag = "Barber", role = "Barber", loop = "idle", at = V3(-97.6, 0, 39.6), look = V3(-95, 0, 38), props = "clippers", seed = 808, age = 46, hands = "bare" },
	{ name = "Chef Ana", tag = "Nutrition Bar", role = "Chef", loop = "idle", at = V3(-70, 0, 74.5), look = V3(-70, 0, 64), seed = 909, gender = 2, hands = "bare" },
	{ name = "Kim Park", tag = "Massage Therapist", role = "Masseuse", loop = "idle", at = V3(61.4, 0, 60.4), look = V3(64, 0, 60.4), seed = 1001, gender = 2, hands = "bare" },
	{ name = "Old Pete", tag = "Gym Owner", loop = "sitwatch", at = V3(-20, 0, -45), look = V3(0, 0, -50), seed = 1111, age = 68, hands = "bare", seat = 1.5, bench = true },
	{ name = "Jay Ortiz", tag = "Sparring", loop = "spar", at = V3(-2.4, 0, -50), look = V3(2.4, 0, -50), hands = "gloves", seed = 1212, floor = 2.8, headgear = Color3.fromRGB(170, 25, 30) },
	{ name = "Kofi Mensah", tag = "Sparring", loop = "spar", at = V3(2.4, 0, -50), look = V3(-2.4, 0, -50), hands = "gloves", seed = 1313, floor = 2.8, headgear = Color3.fromRGB(30, 60, 160) },
	{ name = "Coach Ray", tag = "Head Coach", loop = "walk", walk = { V3(-20, 0, 12), V3(20, 0, 12), V3(24, 0, -28), V3(-8, 0, -32), V3(-30, 0, -6) }, speed = 6, seed = 1414, age = 57, hands = "bare" },
	{ name = "Nia Grant", tag = "Roadwork", loop = "run", walk = { V3(-160, 0, 120), V3(160, 0, 120), V3(160, 0, -190), V3(-160, 0, -190) }, speed = 15, seed = 1515, gender = 2, hands = "wraps", floor = 0.3 },
	{ name = "Maya Reyes", tag = "Front Desk", loop = "idle", at = V3(28, 0, 73.5), look = V3(28, 0, 60), seed = 1616, gender = 2, hands = "bare", floor = 0.4 },
	{ name = "Leon Price", tag = "Gym Member", loop = "idle", pose = "run", spot = "treadmill", seed = 1717, hands = "wraps" },
	{ name = "Sofia Marin", tag = "Gym Member", loop = "idle", pose = "bike", spot = "bike", seed = 1818, gender = 2, hands = "bare" },
	{ name = "Hank Duro", tag = "Gym Member", loop = "idle", pose = "bench", at = V3(-62, 0, -49.3), look = V3(-62, 0, -60), lie = 1.675, props = "bench", seed = 1919, hands = "bare" },
	{ name = "Gus Ferreira", tag = "Local", loop = "walk", walk = { V3(-150, 0, 184), V3(100, 0, 184) }, speed = 5, seed = 2020, age = 61, hands = "bare", floor = 0.5 },
	{ name = "Lena Shaw", tag = "Local", loop = "walk", walk = { V3(90, 0, 184), V3(-140, 0, 184) }, speed = 5.5, seed = 2121, gender = 2, hands = "bare", floor = 0.5 },
}

-- members working out on the decorative cardio machines (GymDecor records where they are
-- when the gym is built; these are the fallbacks)
local SPOTS = {
	treadmill = { pos = V3(58, 0, -71.4), stand = 0.61 },
	bike = { pos = V3(92, 0, -70.5), seat = 2.7 },
}
local function getSpot(name)
	if not name then
		return nil
	end
	local live = okDecor and type(GymDecor) == "table" and GymDecor.DecorSpots
	return (live and live[name]) or SPOTS[name]
end

local function setKinematic(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") then
			pcall(function()
				d.IsKinematic = true
			end)
		end
	end
end

local function nameTag(model, name, tag)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameTag"
	bb.Size = UDim2.fromOffset(200, 40)
	bb.StudsOffset = V3(0, 2.2, 0)
	bb.MaxDistance = 45
	bb.Adornee = head
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 0.6, 0)
	t.BackgroundTransparency = 1
	t.Text = name
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.Parent = bb
	local s = Instance.new("TextLabel")
	s.Name = "Role"
	s.Size = UDim2.new(1, 0, 0.4, 0)
	s.Position = UDim2.fromScale(0, 0.6)
	s.BackgroundTransparency = 1
	s.Text = tag
	s.Font = Enum.Font.Gotham
	s.TextScaled = true
	s.TextColor3 = Color3.fromRGB(255, 210, 90)
	s.TextStrokeTransparency = 0.5
	s.Parent = bb
	bb.Parent = head
end

local function yawTo(from, to)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude < 0.01 then
		return 0
	end
	return math.atan2(-d.X, -d.Z)
end

local function spawnMember(folder, def)
	local app = Looks.Random(def.seed, def.gender or 1, { age = def.age or 26, class = 5 })
	if def.age and def.age > 50 then
		app.hair.color = { 160, 160, 160 }
		app.beard.growth = 0.8
	end
	local fit = def.loop == "sitwatch" and 0.15 or 0.55
	local build = Looks.RandomBuild(def.seed, fit, def.age or 26, app.body.frame)
	local gear = { gloves = "Competition", glovesCond = 70, wrapsCond = 80 }
	local npc = Builder.CreateNPC(app, build, gear, def.name, { hands = def.hands or "wraps", name = def.name, nick = "", waistText = "" })
	if not npc then
		return nil
	end
	setKinematic(npc)
	npc:SetAttribute("Loop", def.loop)
	if def.pose then
		npc:SetAttribute("Pose", def.pose)
	end
	npc:SetAttribute("AmbientSeed", def.seed)
	if def.headgear then
		Builder.SetHeadgear(npc, def.headgear, true)
	end
	local hum = npc:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.BreakJointsOnDeath = false
	end
	npc.Parent = folder
	local spot = getSpot(def.spot)
	local at = (spot and spot.pos) or def.at or (def.walk and def.walk[1]) or V3(0, 0, 0)
	local yaw = yawTo(at, def.look or (at + V3(0, 0, -1)))
	if def.walk then
		local root = npc:FindFirstChild("HumanoidRootPart")
		local start = def.walk[1]
		npc:PivotTo(CFrame.new(start.X, (def.floor or 0.5) + hum.HipHeight + root.Size.Y / 2 + 0.2, start.Z))
		root:SetNetworkOwner(nil)
		hum.WalkSpeed = def.speed or 8
	else
		Poser.Place(npc, at.X, at.Z, yaw, { floor = def.floor or 0.5, stand = (spot and spot.stand) or def.stand, seat = (spot and spot.seat) or def.seat, lie = def.lie })
	end
	if def.props then
		Poser.AttachProps(npc, def.props, 2)
	end
	nameTag(npc, def.name, def.tag)
	CollectionService:AddTag(npc, "Ambient")
	if def.role then
		Ambient.Roles[def.role] = npc
	end
	return npc
end

local function walker(npc, def)
	local hum = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	local i = 1
	local rng = Random.new(def.seed)
	while npc.Parent and hum and root do
		i = i % #def.walk + 1
		local target = def.walk[i]
		local started = os.clock()
		local leg = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z).Magnitude
		local limit = math.max(40, leg / (def.speed or 8) * 1.6 + 5)
		while npc.Parent do
			hum:MoveTo(target)
			local flat = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z)
			if flat.Magnitude < 4 or os.clock() - started > limit then
				break
			end
			task.wait(1)
		end
		if def.loop == "walk" then
			-- the coach stops to watch for a moment
			hum:MoveTo(root.Position)
			task.wait(rng:NextNumber(2, 6))
		end
	end
end

function Ambient.Start()
	local old = workspace:FindFirstChild("GymMembers")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "GymMembers"
	folder.Parent = workspace
	for _, def in ipairs(MEMBERS) do
		if def.bench then
			local b = Instance.new("Part")
			b.Name = "WatchBench"
			b.Anchored = true
			b.Size = V3(6, def.seat or 1.5, 2)
			b.CFrame = CFrame.new(def.at.X, (def.floor or 0.5) + (def.seat or 1.5) / 2, def.at.Z) * CFrame.Angles(0, yawTo(def.at, def.look), 0)
			b.Color = Color3.fromRGB(110, 80, 55)
			b.Material = Enum.Material.WoodPlanks
			b.Parent = folder
		end
		local ok, npc = pcall(spawnMember, folder, def)
		if not ok then
			warn("[Boxer] ambient member failed:", def.name, npc)
		elseif npc and def.walk then
			task.spawn(walker, npc, def)
		end
		task.wait()
	end
end

-- change what a role NPC is doing (e.g. the mitt coach raises the pads)
function Ambient.SetLoop(role, loop)
	local npc = Ambient.Roles[role]
	if npc and npc.Parent then
		npc:SetAttribute("Loop", loop)
	end
end

return Ambient
