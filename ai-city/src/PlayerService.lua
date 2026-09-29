-- PlayerService (ModuleScript) — ServerScriptService.Modules.PlayerService
-- Things players do that aren't crimes or conversations:
--   • elevators and stairs (press E at the doors, pick a floor)
--   • citizen profile cards (click anyone), the People directory, finding someone
--   • places info for the map (open now? who works there?)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PlayerService = {}
local S
local doors = {} -- [door part] = { Building, Floor }

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

--------------------------------------------------------------------------------
-- Elevators
--------------------------------------------------------------------------------
local function buildingName(b)
	local model = b.Model
	return (model and (model:GetAttribute("Address") or model:GetAttribute("PlaceId") or model.Name)) or "Building"
end

local function addElevatorPrompt(part, b, floor)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ElevatorPrompt"
	prompt.ActionText = if b.Elevator.Stairs then "Stairs" else "Elevator"
	prompt.ObjectText = "Floor " .. floor .. " of " .. #b.Elevator.Floors
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Elevator")
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local labels = {}
		for f = 1, #b.Elevator.Floors do
			labels[f] = if f == 1 then "Lobby" else "Floor " .. f
		end
		local placeId = b.Model and b.Model:GetAttribute("PlaceId")
		S.City.Send(player, {
			Type = "Elevator",
			Door = part,
			Current = floor,
			Floors = #b.Elevator.Floors,
			Labels = labels,
			Stairs = b.Elevator.Stairs == true,
			Building = if placeId and Config.PlaceById[placeId] then Config.PlaceById[placeId].label else buildingName(b),
		})
	end)
end

local function onElevator(player, data)
	local entry = doors[data.Door]
	local root = rootOf(player)
	if not entry or not root then
		return { Ok = false }
	end
	if (root.Position - data.Door.Position).Magnitude > 14 then
		return { Ok = false, Error = "Get closer to the doors." }
	end
	local floor = tonumber(data.Floor)
	local target = floor and entry.Building.Elevator.Floors[floor]
	if not target then
		return { Ok = false }
	end
	if S.Crime and S.Crime.IsJailed(player) then
		return { Ok = false, Error = "Nice try." }
	end
	task.delay(0.45, function()
		if root.Parent then
			root.CFrame = CFrame.new(target.Exit + Vector3.new(0, 3.5, 0)) * (root.CFrame - root.CFrame.Position)
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
	return { Ok = true, Floor = floor }
end

--------------------------------------------------------------------------------
-- Profiles and the directory
--------------------------------------------------------------------------------
local function placeLabel(id)
	return id and Config.PlaceById[id] and Config.PlaceById[id].label or id
end

local VALUE_LABELS = { wealth = "💰 Wealth", community = "🤝 Community", safety = "🛡️ Safety", freedom = "🕊️ Freedom", nature = "🌳 Nature", tradition = "🏛️ Tradition" }

local function profile(player, data)
	local id = tonumber(data.Id)
	local c = id and S.Life.Citizens[id]
	if not c then
		return { Ok = false }
	end
	local brain = S.Citizens.GetBrain(id)
	local stage = S.Life:Stage(c)
	local job = c.Job and S.Life.Jobs(Config, c.Job)
	local h = S.Life.Households[c.Household]
	local home = h and h.Home and S.Map.Homes[h.Home]
	local family = {}
	for _, mid in ipairs(h and h.Members or {}) do
		local m = S.Life.Citizens[mid]
		if m and m ~= c then
			table.insert(family, { Id = m.Id, Name = m.First, Age = S.Life:Age(m), Stage = S.Life:Stage(m) })
		end
	end
	local friends = {}
	for _, fid in ipairs(c.Friends or {}) do
		local f = S.Life.Citizens[fid]
		if f then
			table.insert(friends, { Id = f.Id, Name = f.Name })
		end
	end
	local values = {}
	for v, x in pairs(c.Values or {}) do
		table.insert(values, { Label = VALUE_LABELS[v] or v, Value = x })
	end
	table.sort(values, function(a, b)
		return a.Value > b.Value
	end)
	local memories = {}
	for k, m in ipairs(S.City.MemoriesOf(c, player)) do
		if k > 5 then
			break
		end
		table.insert(memories, { Text = m.t, Feeling = m.f, Day = m.d })
	end
	local school, schoolLabel = S.Life:SchoolFor(c)
	local info = S.Life.PersonalityInfo[c.Personality] or {}
	return {
		Ok = true,
		Id = c.Id,
		Name = c.Name,
		Age = S.Life:Age(c),
		Stage = stage,
		Job = if stage == "Adult" then c.Job else nil,
		Workplace = if stage == "Adult" and job then placeLabel(job.place) else nil,
		Hours = if stage == "Adult" and job then { job.start, job.stop } else nil,
		School = if school then schoolLabel else nil,
		Home = home and home.Address,
		Personality = c.Personality,
		PersonalityEmoji = info.Emoji,
		Hobby = c.Hobby,
		Mood = math.floor(S.City.MoodOf(c)),
		Opinion = math.floor(S.City.Opinion(c, player)),
		Activity = brain and brain.Model:GetAttribute("Activity") or "",
		Family = family,
		Friends = friends,
		Values = { values[1], values[2], values[#values] },
		Memories = memories,
		Expecting = h and h.Expecting and S.Life:DaysToGo(h) or nil,
		Model = brain and brain.Model,
	}
end

local function directory(player)
	local out = {}
	for _, c in ipairs(S.Life.List) do
		local brain = S.Citizens.GetBrain(c.Id)
		local stage = S.Life:Stage(c)
		local _, schoolLabel = S.Life:SchoolFor(c)
		table.insert(out, {
			Id = c.Id,
			Name = c.Name,
			Age = S.Life:Age(c),
			Stage = stage,
			Role = if stage == "Adult" then (c.Job or "Looking for work") elseif stage == "Retired" then "Retired" else (schoolLabel or stage),
			Activity = brain and brain.Model:GetAttribute("Activity") or "",
			Mood = math.floor(S.City.MoodOf(c)),
			Opinion = math.floor(S.City.Opinion(c, player)),
			Personality = c.Personality,
		})
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return { Ok = true, People = out }
end

local function locate(player, data)
	local brain = S.Citizens.GetBrain(tonumber(data.Id) or -1)
	if not brain then
		return { Ok = false }
	end
	local pos = brain.Root.Position
	S.City.Send(player, { Type = "Waypoint", Position = pos, Label = brain.C.Name, Emoji = "👤", Model = brain.Model })
	return { Ok = true }
end

local function placesInfo()
	local hour = S.City.Hour()
	local weekend = S.Life:IsWeekend(S.City.Day())
	local out = {}
	for _, place in ipairs(S.Map.PlaceList) do
		local workers, visitors = 0, 0
		local open = nil
		for _, job in ipairs(Config.Jobs) do
			if job.place == place.Id then
				local on = if job.stop > job.start then hour >= job.start and hour < job.stop else hour >= job.start or hour < job.stop
				open = open or on
			end
		end
		for _, brain in ipairs(S.Citizens.List) do
			if brain.Target and brain.Target.Place == place and (brain.State == "act" or brain.State == "soccer") then
				if brain.Plan and brain.Plan.Kind == "Work" then
					workers += 1
				else
					visitors += 1
				end
			end
		end
		table.insert(out, { Id = place.Id, Label = place.Label, Kind = place.Kind, Outdoor = place.Outdoor == true, Position = place.Door, Open = if open == nil then true else open, Workers = workers, Visitors = visitors, Weekend = weekend })
	end
	return { Ok = true, Places = out }
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
function PlayerService.Start(services)
	S = services
	for _, b in ipairs(S.Map.Elevators) do
		for floor, f in pairs(b.Elevator.Floors) do
			if f.Door then
				doors[f.Door] = { Building = b, Floor = floor }
				addElevatorPrompt(f.Door, b, floor)
			end
		end
	end
	S.City.Handle("Elevator", onElevator)
	S.City.Handle("Profile", profile)
	S.City.Handle("Directory", directory)
	S.City.Handle("Locate", locate)
	S.City.Handle("Places", placesInfo)
	-- players don't collide with each other's pets... or citizens' crowds jamming doors
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end)
	end)
end

return PlayerService
