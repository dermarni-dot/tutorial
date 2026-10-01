-- StreetCrimeService (ModuleScript) — ServerScriptService.Modules.StreetCrimeService
-- Other people commit crimes too, and the police arrest them.
--
-- Now and then (more at night, and when Safety or the Economy is low) someone
-- near a player turns to crime. Sometimes it's a stranger in a dark hoodie and
-- a beanie, sometimes a fed-up local:
--   🫳 pickpocketing   sneaks up behind someone and lifts their wallet
--   👜 bag snatching   grabs a bag and runs
--   🧾 store robbery   "Hands up! Give me the money!" at a store's register
--   🎨 graffiti        sprays a tag on a wall (it stays until the city cleans it)
--   💸 your pocket     ...or yours, if you stand still too long near one
--
-- If someone sees it, they shout "STOP, THIEF!" and call the police. Officers
-- chase the thief; if they catch them: hands up, handcuffs, a walk to the
-- police station and some time in the jail cell (go look!). Thieves who
-- get far enough away escape.
--
-- Players can chase a thief down and hit them (F). That's not a crime: they
-- give up with their hands in the air, you get the loot back to its owner and
-- a reward, and the police come and take them away.
--
-- StreetCrimeService.Arrest(officer, suspects, reason) is also used for street
-- fights. Config.NPC_CRIME = false turns it off; Config.NPC_CRIME_COOLDOWN is
-- the average seconds between crimes near a player (default 110).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Weapons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapons"))

local StreetCrime = {}
local S

local WATCH = 160 -- crimes only happen this close to a player
local SIGHT = 45 -- bystanders this close (with a clear view) notice

local cases = {} -- crimes in progress
local byBrain = {} -- [thief brain] = case
local inmates = {} -- [brain] = { Until, Slot }
local escorts = {} -- [brain] = true while being walked to the station (officers too)
local graffiti = {}
local nextCrime = 0
local robbedAt = {} -- [register] = time it can be robbed again

local NAMES = { "Vinnie", "Slick", "Rico", "Dash", "Shady Sam", "Nico", "Jax", "Mags", "Lefty", "Roxy" }
local TAGS = { "ZAP!", "K1NG", "★CREW★", "BOOM", "RAT PACK", "NO RULES", "WILD", "404", "SKRRT", "CITY RATS" }
local TAG_COLORS = { Color3.fromRGB(255, 70, 140), Color3.fromRGB(70, 220, 255), Color3.fromRGB(255, 210, 40), Color3.fromRGB(120, 255, 90), Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 120, 40) }
local STOP = { "STOP, THIEF!", "Hey! Stop that person!", "THIEF! THIEF!", "Somebody stop them!" }
local COPS = { "Freeze! Police!", "Stop right there!", "Police! Don't move!" }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function isPolice(brain)
	local job = brain.C and brain.C.Job
	return job == "Police Officer" or job == "Night Officer" or job == "SWAT Officer"
end

local function streetNear(pos)
	local sp = S.Map.Spacing or 100
	return S.Map.StreetName and S.Map.StreetName(math.floor(pos.Z / sp + 0.5)) or "downtown"
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function nearestPlayer(pos)
	local best, bestD = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root then
			local d = (root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = player, d
			end
		end
	end
	return best, bestD
end

local function busy(brain)
	return byBrain[brain] ~= nil or inmates[brain] ~= nil or escorts[brain] ~= nil or brain.State == "ko" or brain.State == "hospital" or brain.State == "police" or brain.State == "talk" or brain.State == "chat" or brain.Held ~= nil or brain.Model:GetAttribute("Fighting") ~= nil or brain.Model:GetAttribute("Chasing") ~= nil or brain.Model:GetAttribute("Brawling") ~= nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function canSee(brain, target)
	local head = brain.Model:FindFirstChild("Head")
	if not head then
		return false
	end
	local d = target - head.Position
	if d.Magnitude < 10 then
		return true
	end
	if d.Magnitude > SIGHT then
		return false
	end
	local filter = { workspace:FindFirstChild("Citizens") }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(filter, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(head.Position, d, rayParams)
	return hit == nil or (hit.Position - target).Magnitude < 3
end

-- a street node at a distance from a spot (for strangers arriving and getaways)
local function nodeAround(pos, minD, maxD, awayFrom)
	local best, bestScore = nil, -math.huge
	for _ = 1, 30 do
		local node = S.Map.Nodes[math.random(1, #S.Map.Nodes)]
		local d = (node - pos).Magnitude
		if d >= minD and d <= maxD then
			local score = if awayFrom then (node - awayFrom).Magnitude else math.random()
			if score > bestScore then
				best, bestScore = node, score
			end
		end
	end
	return best or (pos + Vector3.new(maxD * 0.7, 0, 0))
end

local function toast(pos, radius, icon, title, text, color)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and (root.Position - pos).Magnitude < radius then
			S.City.Toast(player, icon, title, text, color)
		end
	end
end

--------------------------------------------------------------------------------
-- Jail: the cell at the police station
--------------------------------------------------------------------------------
local SLOTS = { Vector3.new(-2, 0, 1), Vector3.new(0, 0, 1.5), Vector3.new(2, 0, 1), Vector3.new(-2, 0, -1.2), Vector3.new(0, 0, -1), Vector3.new(2, 0, -1.2) }

local function freeSlot()
	local used = {}
	for _, j in pairs(inmates) do
		used[j.Slot] = true
	end
	for k = 1, #SLOTS do
		if not used[k] then
			return k
		end
	end
	return math.random(1, #SLOTS)
end

local function jail(brain, reason)
	-- the state prison: they're bussed out there and do their time with the
	-- other inmates (see PrisonService)
	if S.Prison and S.Prison.Admit then
		local seconds = if brain.C.Temp then math.random(150, 260) else math.random(180, 300)
		if S.Prison.Admit(brain, reason) then
			inmates[brain] = { Until = os.clock() + seconds, Slot = 0, Reason = reason, Prison = true }
			brain.Model:SetAttribute("Action", "")
			brain.Model:SetAttribute("Arrested", nil)
			brain.Model:SetAttribute("Expression", "sad")
			S.City.News("🚌 " .. brain.C.Name .. " was sent to the State Prison for " .. reason .. ".", "Crime", true)
			return
		end
	end
	local station = S.Map.Places.PoliceStation
	local cell = S.Map.Jail or (station and (station.Inside or station.Door))
	if not cell then
		return
	end
	local slot = freeSlot()
	inmates[brain] = { Until = os.clock() + (if brain.C.Temp then math.random(90, 150) else math.random(120, 200)), Slot = slot, Reason = reason }
	local pos = cell + SLOTS[slot] + Vector3.new(0, 3.2, 0)
	brain.Root.Anchored = false
	brain.Root.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(180), 0)
	brain.Root.AssemblyLinearVelocity = Vector3.zero
	brain.Humanoid:MoveTo(pos)
	S.Citizens.SetGait(brain, 8, "idle")
	brain.Model:SetAttribute("Action", "jailed")
	brain.Model:SetAttribute("Arrested", nil)
	brain.Model:SetAttribute("Jailed", true)
	brain.Model:SetAttribute("Activity", "🔒 In jail: " .. reason)
	brain.Model:SetAttribute("Expression", "sad")
end

local function releaseInmate(brain)
	local j = inmates[brain]
	inmates[brain] = nil
	if j and j.Prison and S.Prison then
		S.Prison.Release(brain)
	end
	if not brain.Model.Parent then
		return
	end
	brain.Model:SetAttribute("Jailed", nil)
	brain.Model:SetAttribute("Action", "")
	if brain.C.Temp then
		S.Citizens.Despawn(brain)
		return
	end
	local station = S.Map.Places.PoliceStation
	if station then
		brain.Root.CFrame = CFrame.new(station.Door + Vector3.new(0, 3.5, 0))
	end
	S.Citizens.Say(brain, ({ "Freedom!", "I'm never doing that again...", "Finally out!" })[math.random(1, 3)], "sad", 2.5)
	S.Citizens.Control(brain, false)
	if j and j.Reason then
		S.City.Boost(brain.C, -10)
	end
end

function StreetCrime.IsJailed(brain)
	return inmates[brain] ~= nil
end

--------------------------------------------------------------------------------
-- Arrests: hands up, cuffs, a walk to the station, the cell
--------------------------------------------------------------------------------
-- officer: the arresting officer (walks them in); suspects: a brain or a list
function StreetCrime.Arrest(officer, suspects, reason)
	if suspects.Model then
		suspects = { suspects }
	end
	local station = S.Map.Places.PoliceStation
	for _, s in ipairs(suspects) do
		escorts[s] = true
		if s.State ~= "police" then
			S.Citizens.Control(s, true)
		end
		s.Humanoid:MoveTo(s.Root.Position)
		s.Model:SetAttribute("Criminal", nil)
		s.Model:SetAttribute("Arrested", true)
		s.Model:SetAttribute("Action", "handsup")
		s.Model:SetAttribute("Activity", "🚓 Arrested: " .. reason)
		S.Citizens.Say(s, ({ "Okay, okay! I give up!", "Alright! Don't shoot!", "Ugh... fine." })[math.random(1, 3)], "scared", 2.5)
	end
	if officer then
		escorts[officer] = true
		if officer.State ~= "police" then
			S.Citizens.Control(officer, true)
		end
		officer.Humanoid:MoveTo(officer.Root.Position)
		officer.Model:SetAttribute("Activity", "🚓 Making an arrest")
		S.Citizens.Say(officer, "You're under arrest for " .. reason .. "!", "angry", 3)
	end
	local names = {}
	for _, s in ipairs(suspects) do
		table.insert(names, s.C.Name)
	end
	local where = streetNear(suspects[1].Root.Position)
	S.City.News("🚓 " .. (if officer then officer.C.Name else "The police") .. " arrested " .. table.concat(names, " and ") .. " for " .. reason .. " on " .. where .. ".", "Crime")
	S.City.Adjust("Safety", 1)
	task.spawn(function()
		task.wait(1.6)
		for _, s in ipairs(suspects) do
			if s.Model.Parent then
				s.Model:SetAttribute("Action", "cuffed")
				S.Citizens.SetGait(s, 9, "walk")
			end
		end
		if officer and officer.Model.Parent then
			S.Citizens.SetGait(officer, 9, "walk")
		end
		-- walk them in along the sidewalks
		local lead = suspects[1]
		local path = if station and S.Map.Route then S.Map.Route(lead.Root.Position, station.Door) else {}
		if station then
			table.insert(path, station.Door)
		end
		local i, t0 = 1, os.clock()
		while station and i <= #path and os.clock() - t0 < 60 and lead.Model.Parent and escorts[lead] do
			local target = path[i]
			for k, s in ipairs(suspects) do
				if s.Model.Parent then
					s.Humanoid:MoveTo(target + Vector3.new((k - 1) * 2.5, 0, 0))
				end
			end
			if officer and officer.Model.Parent then
				officer.Humanoid:MoveTo(lead.Root.Position + flat(lead.Root.CFrame.RightVector) * -3 + flat(lead.Root.CFrame.LookVector) * -1.5)
			end
			if flat(lead.Root.Position - target).Magnitude < 4 then
				i += 1
			end
			task.wait(0.4)
		end
		for _, s in ipairs(suspects) do
			escorts[s] = nil
			if s.Model.Parent and s.State ~= "ko" and s.State ~= "hospital" then
				jail(s, reason)
			end
		end
		if officer then
			escorts[officer] = nil
			if officer.Model.Parent then
				if officer.C.Temp then
					S.Citizens.Despawn(officer)
				elseif officer.State == "police" and not officer.Model:GetAttribute("Chasing") and not officer.Model:GetAttribute("Fighting") then
					S.Citizens.Control(officer, false)
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- The crimes
--------------------------------------------------------------------------------
local function finishCase(case)
	if case.Done then
		return
	end
	case.Done = true
	local i = table.find(cases, case)
	if i then
		table.remove(cases, i)
	end
	byBrain[case.Thief] = nil
	-- take the "Thief" marker off everyone's screen who was told to chase them
	for player in pairs(case.Alerted or {}) do
		if player.Parent then
			S.City.Send(player, { Type = "Waypoint", Clear = true, CitizenId = case.Thief.C.Id })
		end
	end
	case.Alerted = nil
	for _, officer in ipairs(case.Officers) do
		if officer.Model.Parent and not escorts[officer] then
			officer.Model:SetAttribute("Chasing", nil)
			officer.Model:SetAttribute("ChaseState", nil)
			if officer.C.Temp then
				S.Citizens.Despawn(officer)
			elseif officer.State == "police" and not officer.Model:GetAttribute("Fighting") then
				S.Citizens.Control(officer, false)
			end
		end
	end
end

-- the thief walks away as if nothing happened (or disappears, for strangers)
local function slipAway(case)
	local thief = case.Thief
	thief.Model:SetAttribute("Criminal", nil)
	finishCase(case)
	if not thief.Model.Parent then
		return
	end
	if thief.C.Temp then
		thief.Model:SetAttribute("Action", "")
		S.Citizens.SetGait(thief, 11, "walk")
		thief.Humanoid:MoveTo(nodeAround(thief.Root.Position, 80, 140))
		task.delay(14, function()
			if thief.Model.Parent and not byBrain[thief] and not escorts[thief] and not inmates[thief] then
				S.Citizens.Despawn(thief)
			end
		end)
	else
		thief.Model:SetAttribute("Action", "")
		S.Citizens.Control(thief, false)
	end
end

local function callPolice(case, caller)
	if case.Called then
		return
	end
	case.Called = true
	local pos = case.Thief.Root.Position
	if caller and caller.Model and caller.Model.Parent then
		S.Citizens.Say(caller, "Police! There's a thief on " .. streetNear(pos) .. "!", "scared", 3)
	end
	-- up to two officers: on duty nearby first, then a patrol car
	local want = if case.Kind == "robbery" then 2 else 1
	local pool = {}
	for _, brain in ipairs(S.Citizens.List) do
		if isPolice(brain) and not brain.Temp and not busy(brain) and brain.Plan and brain.Plan.Kind == "Work" and (brain.Root.Position - pos).Magnitude < 500 then
			table.insert(pool, brain)
		end
	end
	table.sort(pool, function(a, b)
		return (a.Root.Position - pos).Magnitude < (b.Root.Position - pos).Magnitude
	end)
	for k = 1, want do
		local officer = pool[k]
		if officer then
			S.Citizens.Control(officer, true)
		else
			local spot = nodeAround(pos, 70, 130)
			officer = S.Citizens.SpawnExtra({ Name = "Officer " .. ({ "Reyes", "Park", "Novak", "Walsh", "Chen" })[math.random(1, 5)], Job = "Police Officer", Age = math.random(26, 44), Activity = "🚓 Chasing a thief" }, CFrame.new(spot + Vector3.new(0, 3, 0)))
			officer.HP = Weapons.POLICE_HP
			S.Citizens.Control(officer, true)
		end
		officer.C.First = officer.C.First or officer.C.Name
		officer.Model:SetAttribute("Activity", "🚓 Chasing a thief")
		officer.Model:SetAttribute("Chasing", -1)
		officer.Model:SetAttribute("ChaseState", "chasing")
		S.Citizens.Say(officer, "On my way!", "focused", 1.5)
		table.insert(case.Officers, officer)
	end
end

-- noticed! the thief runs for it
local function bolt(case, caller)
	if case.Phase == "flee" or case.Phase == "caught" then
		return
	end
	local thief = case.Thief
	case.Phase = "flee"
	case.FleeStart = os.clock()
	thief.Model:SetAttribute("Criminal", true)
	thief.Model:SetAttribute("Action", if case.Kind == "graffiti" then "" else "getaway")
	thief.Model:SetAttribute("Expression", "scared")
	thief.Model:SetAttribute("Activity", "🦹 Running from the police!")
	S.Citizens.SetGait(thief, 16.5, "run")
	-- a getaway spot away from whoever noticed
	local from = if caller and caller.Root then caller.Root.Position else thief.Root.Position
	local dest = nodeAround(thief.Root.Position, 170, 260, from)
	case.Path = if S.Map.Route then S.Map.Route(thief.Root.Position, dest) else { dest }
	table.insert(case.Path, dest)
	case.PathIndex = 1
	case.CallAt = os.clock() + math.random(15, 35) / 10
	case.Caller = caller
	-- players nearby: catch them!
	local what = case.What
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and (root.Position - thief.Root.Position).Magnitude < 130 then
			S.City.Toast(player, "🦹", "Stop, thief!", what .. " on " .. streetNear(thief.Root.Position) .. ". Chase them down and hit them (F) before they get away!", rgb(255, 120, 60))
			-- the marker follows the thief by id: a model that has only just
			-- spawned may not have streamed in to this player yet
			S.City.Send(player, { Type = "Waypoint", Position = thief.Root.Position, Label = "Thief", Emoji = "🦹", Model = thief.Model, CitizenId = thief.C.Id })
			case.Alerted = case.Alerted or {}
			case.Alerted[player] = true
		end
	end
end

-- bystanders who saw it happen
local function witnesses(case, pos)
	local out = {}
	for _, brain in ipairs(S.Citizens.Nearby(pos, SIGHT)) do
		if brain ~= case.Thief and brain ~= case.Victim and not brain.Temp and brain.State ~= "ko" and brain.State ~= "hospital" and brain.Model:GetAttribute("Action") ~= "sleep" and canSee(brain, pos) then
			table.insert(out, brain)
		end
	end
	return out
end

local function commit(case)
	local thief = case.Thief
	local pos = thief.Root.Position
	local victim = case.Victim
	case.Phase = "done-act"
	S.City.Crime(if case.Kind == "robbery" then 3 elseif case.Kind == "graffiti" then 1 else 2)
	if case.Kind == "pickpocket" then
		local noticed = math.random() < 0.6
		case.What = "Someone stole " .. victim.C.First .. "'s wallet"
		S.City.Boost(victim.C, -10)
		if noticed then
			S.Citizens.Say(victim, ({ "Hey!! My wallet!", "THIEF! They took my wallet!", "Wait... my wallet! STOP!" })[math.random(1, 3)], "angry", 3)
			bolt(case, victim)
		else
			-- maybe someone else saw it
			for _, w in ipairs(witnesses(case, pos)) do
				if math.random() < 0.35 then
					S.Citizens.Say(w, "Hey! That person just took your wallet!", "surprised", 3)
					bolt(case, w)
					break
				end
			end
			if case.Phase ~= "flee" then
				S.City.News("🫳 A pickpocket struck on " .. streetNear(pos) .. ". " .. victim.C.Name .. " lost their wallet.", "Crime", true)
				slipAway(case)
			end
		end
	elseif case.Kind == "snatch" then
		case.What = "Someone snatched " .. victim.C.First .. "'s bag"
		S.City.Boost(victim.C, -15)
		S.Citizens.Hurt(victim, pos, "MY BAG!!", 10)
		bolt(case, victim)
	elseif case.Kind == "player" then
		local player = case.Player
		local amount = math.min(S.City.Coins(player), math.random(6, 16))
		case.Stolen = amount
		case.What = "Someone picked your pocket"
		if amount > 0 then
			S.City.AddCoins(player, -amount, "💸 Pickpocketed")
		end
		S.City.Toast(player, "💸", "Your pocket was picked! -" .. amount .. " coins", "Chase the thief and hit them (F) to get it back!", rgb(255, 90, 90))
		bolt(case, nil)
	elseif case.Kind == "robbery" then
		S.Citizens.Say(thief, "Hands up! Give me the money!", "angry", 3)
		thief.Model:SetAttribute("Action", "point")
		case.What = "The " .. case.StoreLabel .. " is being robbed"
		S.City.SendNear(pos, 150, { Type = "Alarm", Position = pos, Seconds = 10 })
		S.City.News("🚨 The " .. case.StoreLabel .. " was robbed!", "Crime")
		for _, w in ipairs(S.Citizens.Nearby(pos, 26)) do
			if w ~= thief and not isPolice(w) and w.State ~= "ko" and w.State ~= "hospital" then
				S.Citizens.Flee(w, pos, 8, if math.random() < 0.5 then "It's a robbery!!" else nil)
			end
		end
		task.delay(2.5, function()
			if not case.Done and case.Phase == "done-act" then
				bolt(case, nil)
				callPolice(case, nil)
			end
		end)
	elseif case.Kind == "graffiti" then
		case.What = "Someone is spraying graffiti"
		thief.Model:SetAttribute("Action", "spray")
		thief.Humanoid:MoveTo(thief.Root.Position)
		thief.Root.CFrame = CFrame.lookAt(thief.Root.Position, Vector3.new(case.Wall.Position.X, thief.Root.Position.Y, case.Wall.Position.Z))
		task.delay(6, function()
			if case.Done or case.Phase ~= "done-act" then
				return
			end
			-- the tag on the wall
			local w = case.Wall
			local tag = Instance.new("Part")
			tag.Name = "Graffiti"
			tag.Anchored = true
			tag.CanCollide = false
			tag.CanQuery = false
			tag.CanTouch = false
			tag.Transparency = 1
			tag.Size = Vector3.new(6, 3, 0.1)
			tag.CFrame = CFrame.lookAt(w.Position + w.Normal * 0.08, w.Position + w.Normal * 2)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.LightInfluence = 1
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Text = TAGS[math.random(1, #TAGS)]
			label.TextColor3 = TAG_COLORS[math.random(1, #TAG_COLORS)]
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.Rotation = math.random(-12, 12)
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 4
			stroke.Color = Color3.new(0.05, 0.05, 0.08)
			stroke.Parent = label
			label.Parent = gui
			gui.Parent = tag
			tag.Parent = workspace
			table.insert(graffiti, { Part = tag, Day = S.City.State.Day })
			S.City.Adjust("Happiness", -1)
			local seen = witnesses(case, thief.Root.Position)
			if #seen > 0 and math.random() < 0.6 then
				S.Citizens.Say(seen[1], "Hey! Stop that! That's vandalism!", "angry", 3)
				bolt(case, seen[1])
			else
				S.City.News("🎨 Someone sprayed graffiti on a wall on " .. streetNear(w.Position) .. ".", "Crime", true)
				slipAway(case)
			end
		end)
	end
	-- passers-by react
	if case.Kind ~= "graffiti" then
		for _, w in ipairs(witnesses(case, pos)) do
			if S.Citizens.CanReact(w) and math.random() < 0.6 then
				S.Citizens.React(w, "scared", if math.random() < 0.5 then STOP[math.random(1, #STOP)] else nil, "surprised", 3, pos)
			end
		end
	end
end

-- caught: by an officer, or given up to a player
local function caught(case, officer, byPlayer)
	if case.Phase == "caught" then
		return
	end
	case.Phase = "caught"
	local thief = case.Thief
	local reason = ({ pickpocket = "pickpocketing", snatch = "bag snatching", robbery = "robbing the " .. (case.StoreLabel or "store"), graffiti = "vandalism", player = "pickpocketing" })[case.Kind] or "theft"
	-- the loot goes back
	if case.Kind == "player" and case.Player and case.Player.Parent and (case.Stolen or 0) > 0 then
		S.City.AddCoins(case.Player, case.Stolen, "💸 Got your coins back")
		if not byPlayer then
			S.City.Toast(case.Player, "🚓", "The police caught your pickpocket!", "You got your " .. case.Stolen .. " coins back.", rgb(90, 180, 120))
		end
	end
	if case.Victim and case.Victim.C and not case.Victim.C.Temp then
		S.City.Boost(case.Victim.C, 8)
	end
	byBrain[thief] = nil
	finishCase(case)
	StreetCrime.Arrest(officer, thief, reason)
end

local function pickCrime(force)
	local now = os.clock()
	if not force and (now < nextCrime or #cases >= 2) then
		return
	end
	local hour = S.City.Hour()
	local night = hour >= 20 or hour < 5
	local safety = S.City.State.Safety or 60
	local economy = S.City.State.Economy or 55
	local chance = 0.35 * (if night then 1.6 else 1) * math.clamp((120 - safety - economy * 0.3) / 60, 0.4, 1.8)
	if not force and math.random() > chance then
		return
	end
	-- a player to be near
	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if rootOf(p) then
			table.insert(players, p)
		end
	end
	if #players == 0 then
		return
	end
	local player = players[math.random(1, #players)]
	local proot = rootOf(player)
	-- what kind of crime?
	local kinds = {
		{ "pickpocket", 3 },
		{ "snatch", 2 },
		{ "robbery", if night then 1 else 1.5 },
		{ "graffiti", if night then 3 else 0.6 },
		{ "player", if (proot.AssemblyLinearVelocity or Vector3.zero).Magnitude < 2 and (player:GetAttribute("Coins") or 0) >= 10 and not player:GetAttribute("Hiding") and (player:GetAttribute("JailUntil") or 0) < workspace:GetServerTimeNow() then 1 else 0 },
	}
	local total = 0
	for _, k in ipairs(kinds) do
		total += k[2]
	end
	local roll, kind = math.random() * total, "pickpocket"
	for _, k in ipairs(kinds) do
		roll -= k[2]
		if roll <= 0 then
			kind = k[1]
			break
		end
	end
	kind = force or kind
	-- the target
	local case = { Kind = kind, Phase = "approach", Started = now, Officers = {} }
	local near = S.Citizens.Nearby(proot.Position, WATCH)
	local targetPos
	if kind == "player" then
		case.Player = player
		targetPos = proot.Position
	elseif kind == "robbery" then
		local best
		for _, place in ipairs(S.Map.PlaceList) do
			if place.Kind == "store" and place.Model and (place.Door - proot.Position).Magnitude < WATCH then
				for _, d in ipairs(place.Model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Register" and (robbedAt[d] or 0) < now and math.abs(d.Position.Y - place.Door.Y) < 8 then
						best = { Place = place, Register = d }
						break
					end
				end
			end
			if best then
				break
			end
		end
		if not best then
			return
		end
		case.Store, case.Register = best.Place, best.Register
		case.StoreLabel = Config.PlaceById[best.Place.Id] and Config.PlaceById[best.Place.Id].label or best.Place.Label or "store"
		robbedAt[best.Register] = now + 400
		targetPos = best.Register.Position
	elseif kind == "graffiti" then
		-- a building wall close to a sidewalk near the player
		local filter = { workspace:FindFirstChild("Citizens") }
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(filter, p.Character)
			end
		end
		rayParams.FilterDescendantsInstances = filter
		for _ = 1, 10 do
			local start = nodeAround(proot.Position, 20, 100)
			for _, dir in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
				local hit = workspace:Raycast(start + Vector3.new(0, 4, 0), dir * 30, rayParams)
				if hit and hit.Instance and hit.Instance.Anchored and math.abs(hit.Normal.Y) < 0.2 and hit.Instance.Size.Y > 6 and not hit.Instance:FindFirstAncestorOfClass("Tool") then
					case.Wall = { Position = hit.Position, Normal = hit.Normal }
					break
				end
			end
			if case.Wall then
				break
			end
		end
		if not case.Wall then
			return
		end
		targetPos = case.Wall.Position + case.Wall.Normal * 2.5
	else
		-- someone out on the street
		local options = {}
		for _, brain in ipairs(near) do
			if not brain.Temp and not busy(brain) and (brain.State == "walk" or brain.State == "act") and (brain.Floor or 1) == 1 and S.Life:Age(brain.C) >= 16 and not isPolice(brain) then
				local place = brain.Target and brain.Target.Place
				if brain.State == "walk" or (place and place.Outdoor) then
					table.insert(options, brain)
				end
			end
		end
		if #options == 0 then
			return
		end
		case.Victim = options[math.random(1, #options)]
		targetPos = case.Victim.Root.Position
	end
	-- the thief: a local in a bad mood, or a stranger in a hoodie
	local thief
	if math.random() < 0.4 and kind ~= "robbery" then
		local best, worst = nil, math.huge
		for _, brain in ipairs(near) do
			if brain ~= case.Victim and not brain.Temp and not busy(brain) and brain.State == "walk" and S.Life:Age(brain.C) >= 16 and S.Life:Age(brain.C) < 60 and not isPolice(brain) then
				local mood = S.City.MoodOf(brain.C) + (if brain.C.Personality == "grumpy" then -15 else 0)
				if mood < 45 and mood < worst and (brain.Root.Position - targetPos).Magnitude < 90 then
					best, worst = brain, mood
				end
			end
		end
		if best then
			thief = best
			S.Citizens.Control(thief, true)
		end
	end
	if not thief then
		local spot = nodeAround(targetPos, 45, 80)
		local name = NAMES[math.random(1, #NAMES)]
		thief = S.Citizens.SpawnExtra({ Name = name, First = name, Job = "Thief", Age = math.random(19, 38), Activity = "🚶 Just walking" }, CFrame.new(spot + Vector3.new(0, 3, 0)))
		thief.HP = Weapons.CITIZEN_HP
		S.Citizens.Control(thief, true)
		thief.Model:SetAttribute("Activity", "🚶 Just walking")
	end
	case.Thief = thief
	byBrain[thief] = case
	table.insert(cases, case)
	-- walking there (through the store door for a robbery)
	if kind == "robbery" and S.Map.Route then
		case.Path = S.Map.Route(thief.Root.Position, case.Store.Door)
		table.insert(case.Path, case.Store.Door)
		table.insert(case.Path, case.Store.Inside or case.Store.Door)
		table.insert(case.Path, case.Register.Position)
		case.PathIndex = 1
	end
	-- snatchers run up; pickpockets hurry to catch up with someone walking, then slow down
	local walk = Config.WALK_SPEED or 9.5
	S.Citizens.SetGait(thief, if kind == "snatch" then math.max(17, walk * 1.8) elseif kind == "pickpocket" or kind == "player" then math.max(13, walk * 1.6) else math.max(10, walk * 1.1), if kind == "snatch" or kind == "pickpocket" then "run" else "walk")
	local every = Config.NPC_CRIME_COOLDOWN or 110
	nextCrime = now + every * (0.6 + math.random() * 0.8)
	return case
end

--------------------------------------------------------------------------------
-- Every tick
--------------------------------------------------------------------------------
local function followPath(case, brain)
	local p = case.Path and case.Path[case.PathIndex]
	if not p then
		return true
	end
	brain.Humanoid:MoveTo(p)
	if flat(brain.Root.Position - p).Magnitude < 4 then
		case.PathIndex += 1
	end
	return case.PathIndex > #case.Path
end

local function tick(case, now)
	local thief = case.Thief
	if not thief.Model.Parent or thief.State == "ko" or thief.State == "hospital" then
		finishCase(case)
		return
	end
	if case.Phase == "approach" then
		if now - case.Started > 45 then
			slipAway(case)
			return
		end
		local target
		if case.Kind == "player" then
			local r = case.Player.Parent and rootOf(case.Player)
			if not r or (r.AssemblyLinearVelocity or Vector3.zero).Magnitude > 12 then
				slipAway(case)
				return
			end
			target = r.Position - flat(r.CFrame.LookVector) * 2.5
		elseif case.Kind == "robbery" then
			if followPath(case, thief) then
				commit(case)
			end
			return
		elseif case.Kind == "graffiti" then
			target = case.Wall.Position + case.Wall.Normal * 2.5
		else
			local v = case.Victim
			if not v.Model.Parent or busy(v) and not v.Held then
				slipAway(case)
				return
			end
			target = v.Root.Position - flat(v.Root.CFrame.LookVector) * 2
		end
		thief.Humanoid:MoveTo(target)
		local d = flat(thief.Root.Position - target).Magnitude
		if case.Kind == "pickpocket" or case.Kind == "player" or case.Kind == "snatch" then
			-- sneak the last few steps
			-- (always a little quicker than people walk, or they'd never catch up)
			local walk = Config.WALK_SPEED or 9.5
			S.Citizens.SetGait(thief, if d > 12 then math.max(13, walk * 1.6) else math.max(9, walk * 1.25), if d > 12 then "run" else "walk")
		end
		if d < 3.4 then
			commit(case)
		end
	elseif case.Phase == "flee" then
		if case.Called ~= true and case.CallAt and now >= case.CallAt then
			callPolice(case, case.Caller)
		end
		local done = followPath(case, thief)
		-- officers chase
		local closest = math.huge
		for _, officer in ipairs(case.Officers) do
			if officer.Model.Parent and officer.State ~= "ko" then
				local d = (officer.Root.Position - thief.Root.Position).Magnitude
				closest = math.min(closest, d)
				S.Citizens.SetGait(officer, if d < 30 then 18.5 else 20, "run")
				officer.Humanoid:MoveTo(thief.Root.Position)
				if math.random() < 0.02 then
					S.Citizens.Say(officer, COPS[math.random(1, #COPS)], "angry", 1.6)
				end
				if d < 4.5 then
					caught(case, officer)
					return
				end
			end
		end
		-- a thief who got far enough away (and isn't being tailed) escapes
		if (done and closest > 25) or now - case.FleeStart > 70 then
			S.City.News("🏃 The thief got away on " .. streetNear(thief.Root.Position) .. ".", "Crime", true)
			for player in pairs(case.Alerted or {}) do
				if player.Parent then
					S.City.Toast(player, "🏃", "The thief got away", "They slipped off on " .. streetNear(thief.Root.Position) .. ".", rgb(160, 160, 170))
				end
			end
			slipAway(case)
		end
	elseif case.Phase == "surrender" then
		thief.Humanoid:MoveTo(thief.Root.Position)
		if not case.Called then
			callPolice(case, nil)
		end
		for _, officer in ipairs(case.Officers) do
			if officer.Model.Parent then
				S.Citizens.SetGait(officer, 18, "run")
				officer.Humanoid:MoveTo(thief.Root.Position)
				if (officer.Root.Position - thief.Root.Position).Magnitude < 5 then
					caught(case, officer, true)
					return
				end
			end
		end
		if now - case.SurrenderAt > 50 then
			caught(case, nil, true)
		end
	end
end

--------------------------------------------------------------------------------
-- Players catching thieves
--------------------------------------------------------------------------------
function StreetCrime.IsCriminal(brain)
	local case = byBrain[brain]
	return case ~= nil and (case.Phase == "flee" or case.Phase == "done-act" or case.Phase == "surrender")
end

-- a player hit a fleeing thief: that's not a crime. They give up.
function StreetCrime.PlayerHit(player, brain, weapon, weaponId, fromPos)
	local case = byBrain[brain]
	local damage = math.floor(weapon.Damage * 0.6)
	brain.HP = (brain.HP or Weapons.CITIZEN_HP) - damage
	brain.LastHit = os.clock()
	brain.Model:SetAttribute("MaxHP", Weapons.CITIZEN_HP)
	brain.Model:SetAttribute("HP", math.max(1, brain.HP))
	brain.HP = math.max(1, brain.HP)
	S.Citizens.Hurt(brain, fromPos, "OW! Okay, okay!", weapon.Knock * 0.5)
	S.City.SendNear(brain.Root.Position, 120, { Type = "Hit", Position = brain.Root.Position + Vector3.new(0, 2, 0), Damage = damage, Weapon = weaponId })
	if case and case.Phase ~= "surrender" and case.Phase ~= "caught" then
		case.Phase = "surrender"
		case.SurrenderAt = os.clock()
		brain.Humanoid:MoveTo(brain.Root.Position)
		brain.Model:SetAttribute("Action", "handsup")
		brain.Model:SetAttribute("Activity", "🙌 Caught by " .. player.DisplayName)
		S.Citizens.Say(brain, "Okay! OKAY! I give up! Don't hurt me!", "scared", 3)
		-- the reward: the loot back to its owner, and something for the hero
		local reward = if case.Kind == "robbery" then 60 elseif case.Kind == "player" then 15 else 30
		S.City.AddCoins(player, reward, "🦸 Caught a thief")
		if case.Kind == "player" and case.Player == player and (case.Stolen or 0) > 0 then
			S.City.AddCoins(player, case.Stolen, "💸 Got your coins back")
			case.Stolen = 0
		end
		if case.Victim and case.Victim.C and not case.Victim.C.Temp then
			S.City.Remember(case.Victim.C, player, "caught the thief who robbed me", 30, "caught a thief")
			S.Citizens.Say(case.Victim, "My hero! Thank you!", "happy", 3)
		end
		for _, w in ipairs(S.Citizens.Nearby(brain.Root.Position, 40)) do
			if w ~= brain and w ~= case.Victim and not w.Temp then
				S.City.Remember(w.C, player, "caught a thief", 8, "caught a thief")
			end
		end
		S.City.Toast(player, "🦸", "You caught the thief! +" .. reward .. " coins", "Hold on, the police are coming to take them away.", rgb(90, 180, 120))
		S.City.News("🦸 " .. player.DisplayName .. " caught a thief on " .. streetNear(brain.Root.Position) .. "!", "City")
		S.City.Progress(player, "thief", 1)
		S.City.Send(player, { Type = "Waypoint", Clear = true, CitizenId = brain.C.Id })
	end
	return { Ok = true, Hit = true, Name = brain.C.First, HP = brain.HP, Weapon = weaponId }
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
function StreetCrime.Start(services)
	S = services
	nextCrime = os.clock() + (Config.NPC_CRIME_COOLDOWN or 110) * 0.5
	task.spawn(function()
		local lastPick = 0
		local lastDay = S.City.State.Day
		while true do
			task.wait(0.3)
			local now = os.clock()
			for _, case in ipairs(table.clone(cases)) do
				if not case.Done then
					tick(case, now)
				end
			end
			for brain, j in pairs(inmates) do
				if not brain.Model.Parent then
					inmates[brain] = nil
				elseif now >= j.Until then
					releaseInmate(brain)
				elseif not j.Prison and S.Map.Jail and (brain.Root.Position - S.Map.Jail).Magnitude > 10 then
					-- no escaping
					brain.Root.CFrame = CFrame.new(S.Map.Jail + SLOTS[j.Slot] + Vector3.new(0, 3.2, 0))
				end
			end
			-- the city cleans the graffiti every morning
			if S.City.State.Day ~= lastDay then
				lastDay = S.City.State.Day
				for _, g in ipairs(graffiti) do
					g.Part:Destroy()
				end
				graffiti = {}
			end
			if Config.NPC_CRIME ~= false and now - lastPick > 5 then
				lastPick = now
				pickCrime()
			end
		end
	end)
end

StreetCrime.Cases = cases
StreetCrime.Inmates = inmates
-- for tests and your own scripts: a crime near a player right now
-- ("pickpocket", "snatch", "robbery", "graffiti" or "player")
function StreetCrime.Commit(kind)
	return pickCrime(kind or "pickpocket")
end

return StreetCrime
