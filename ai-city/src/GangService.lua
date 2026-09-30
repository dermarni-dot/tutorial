-- GangService (ModuleScript) — ServerScriptService.Modules.GangService
-- The rough side of town, and nights when the city loses it.
--   • Gang turf: the blocks past the factory and the warehouse ("the East
--     End") are run by two street crews, the Vipers (green) and the Kings
--     (purple). The streets there are covered in graffiti and trash, with a
--     burned-out car and a fire barrel where the crews hang out.
--   • Walk onto their corner and they'll size you up and tell you to leave.
--     Stick around, or hit one of them, and the whole crew jumps you.
--   • Gang wars: every so often the two crews meet in the street and it turns
--     into a big brawl. Somebody calls the police.
--   • Riots: when the city's safety falls very low (or, rarely, on a bad
--     night), downtown erupts: crowds brawling in the streets, masked rioters
--     running around, stores looted and fires burning, until the police get
--     it under control. Knocked-out people go to the hospital.
-- Turn them off with Config.GANGS = false / Config.RIOTS = false.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MapKit = require(script.Parent:WaitForChild("MapKit"))

local GangService = {}
local S

local CREWS = {
	{ Name = "Vipers", Job = "Viper", Color = Color3.fromRGB(60, 200, 100), Emoji = "🐍", Names = { "Snake", "Dice", "Tank", "Lil T", "Ghost", "Rico" } },
	{ Name = "Kings", Job = "King", Color = Color3.fromRGB(170, 90, 240), Emoji = "👑", Names = { "Crown", "Duke", "Jay", "Smoke", "Ace", "Nico" } },
}
local TAUNTS = { "You lost or something?", "This ain't your block.", "Keep walking.", "You lookin' at something?", "Wrong neighborhood, buddy." }
local WARN = { "Last warning. Beat it.", "I said get lost!", "You deaf? Leave!" }
local JUMP = { "Get 'em!", "Told you to leave!", "Now you're gonna learn!" }

local crews = {} -- crew records: { Info, Spot, Members = { brain }, Angry = { [player] = true }, Seen = { [player] = time } }
local turf = {} -- block centers
local warAt = 0

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function nearestPlayer(pos)
	local best, bestD = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best, bestD
end

local function toastNear(pos, radius, emoji, title, text, color)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - pos).Magnitude < radius then
			S.City.Toast(p, emoji, title, text, color)
		end
	end
end

--------------------------------------------------------------------------------
-- The look of the turf: graffiti, trash, a burned-out car, a fire barrel
--------------------------------------------------------------------------------
local TAGS = { "VIPERS", "KINGS", "EAST END", "V13", "KING$", "NO COPS" }
local function dressTurf(folder, c, rng)
	local HALF, SIDEWALK = MapKit.HALF, MapKit.SIDEWALK
	for k = 1, 6 do
		local a = rng:NextNumber() * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * (HALF - 8), 0, math.sin(a) * (HALF - 8))
		MapKit.deco(folder, "TrashBag", Vector3.new(1.6, 1.4, 1.4), CFrame.new(p + Vector3.new(0, MapKit.LOT_Y + 0.7, 0)), rgb(30, 30, 34), Enum.Material.Plastic)
		if k % 2 == 0 then
			MapKit.deco(folder, "Litter", Vector3.new(0.8, 0.1, 0.6), CFrame.new(p + Vector3.new(1.4, MapKit.LOT_Y + 0.05, 0.6)) * CFrame.Angles(0, a, 0), rgb(220, 210, 180))
		end
	end
	-- graffiti on a wall panel at the block's corners
	for k, sx in ipairs({ -1, 1 }) do
		local wall = MapKit.deco(folder, "GraffitiWall", Vector3.new(12, 6, 0.6), CFrame.new(c + Vector3.new(sx * (HALF - SIDEWALK - 8), MapKit.LOT_Y + 3, -(HALF - SIDEWALK - 1))), rgb(150, 140, 130), Enum.Material.Brick)
		MapKit.signText(wall, Enum.NormalId.Front, TAGS[rng:NextInteger(1, #TAGS)], ({ rgb(60, 220, 110), rgb(180, 90, 250), rgb(250, 90, 60) })[k], Enum.Font.Bangers)
		MapKit.signText(wall, Enum.NormalId.Back, TAGS[rng:NextInteger(1, #TAGS)], ({ rgb(250, 200, 40), rgb(60, 180, 250) })[k], Enum.Font.Bangers)
	end
	-- a burned-out car
	local car = MapKit.deco(folder, "BurnedCar", Vector3.new(5, 2.4, 9), CFrame.new(c + Vector3.new(HALF - SIDEWALK - 6, MapKit.LOT_Y + 1.4, 6)), rgb(40, 36, 34), Enum.Material.CorrodedMetal)
	MapKit.deco(folder, "BurnedCarTop", Vector3.new(4.4, 1.6, 4.6), car.CFrame * CFrame.new(0, 2, 0.5), rgb(30, 28, 26), Enum.Material.CorrodedMetal)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			MapKit.deco(folder, "Rim", Vector3.new(0.6, 1.4, 1.4), car.CFrame * CFrame.new(sx * 2.4, -1, sz * 3.2), rgb(70, 60, 50), Enum.Material.CorrodedMetal)
		end
	end
end

-- a fire in a barrel (or a burning barricade in a riot)
local function fire(folder, pos, big)
	local barrel = MapKit.deco(folder, if big then "BurningBarricade" else "FireBarrel", if big then Vector3.new(4, 1.6, 2) else Vector3.new(1.8, 2.6, 1.8), CFrame.new(pos + Vector3.new(0, MapKit.LOT_Y + (if big then 0.8 else 1.3), 0)), rgb(60, 50, 40), Enum.Material.CorrodedMetal)
	local f = Instance.new("Fire")
	f.Size = if big then 9 else 4
	f.Heat = if big then 14 else 8
	f.Parent = barrel
	local smoke = Instance.new("Smoke")
	smoke.Color = rgb(60, 60, 60)
	smoke.Opacity = if big then 0.25 else 0.1
	smoke.RiseVelocity = 6
	smoke.Parent = barrel
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 150, 60)
	light.Range = if big then 26 else 16
	light.Brightness = 2
	light.Parent = barrel
	return barrel
end

--------------------------------------------------------------------------------
-- Crews
--------------------------------------------------------------------------------
local function spawnMember(crew)
	local info = crew.Info
	local n = #crew.Members + 1
	local name = info.Names[(n - 1) % #info.Names + 1]
	local a = n / 6 * math.pi * 2
	local pos = crew.Spot + Vector3.new(math.cos(a) * 3.5, 3, math.sin(a) * 3.5)
	local brain = S.Citizens.SpawnExtra({ Name = name, First = name, Job = info.Job, Age = math.random(19, 30), Activity = info.Emoji .. " " .. info.Name .. " crew" }, CFrame.lookAt(pos, crew.Spot + Vector3.new(0, 3, 0)))
	brain.Gang = info.Name
	brain.Crew = crew
	brain.C.Personality = "grumpy"
	brain.HP = 120
	S.Citizens.Control(brain, true)
	brain.Model:SetAttribute("Gang", info.Name)
	brain.Model:SetAttribute("Action", ({ "chat", "wait", "phone", "chat" })[n % 4 + 1])
	brain.Post = pos
	table.insert(crew.Members, brain)
	return brain
end

local function alive(brain)
	return brain.Model.Parent and brain.State ~= "ko" and brain.State ~= "hospital"
end

-- a player hit one of them: they all come for that player
function GangService.Provoke(brain, player)
	local crew = brain.Crew
	if not crew or crew.Angry[player] then
		return
	end
	crew.Angry[player] = os.clock() + 30
	for _, m in ipairs(crew.Members) do
		if m ~= brain and alive(m) and S.Crime and S.Crime.StartFight then
			task.delay(math.random() * 0.8, function()
				S.Crime.StartFight(m, player)
			end)
		end
	end
	if S.Citizens then
		S.Citizens.Say(brain, JUMP[math.random(1, #JUMP)], "angry", 2)
	end
end

local function crewTick(crew, now)
	if not workspace:FindFirstChild("Citizens") then
		return
	end
	-- clear out the knocked-out, and a new member joins now and then
	for k = #crew.Members, 1, -1 do
		local m = crew.Members[k]
		if not m.Model.Parent then
			table.remove(crew.Members, k)
		elseif m.State == "ko" or m.State == "hospital" then
			m.GoneAt = m.GoneAt or now
			if now - m.GoneAt > 25 then
				table.remove(crew.Members, k)
				S.Citizens.Despawn(m)
			end
		end
	end
	if #crew.Members < (Config.GANG_SIZE or 5) and now >= (crew.NextRecruit or 0) then
		crew.NextRecruit = now + 60
		task.spawn(pcall, spawnMember, crew)
	end
	-- members who aren't fighting drift back to their corner
	for _, m in ipairs(crew.Members) do
		if alive(m) and m.State ~= "police" then
			S.Citizens.Control(m, true)
		end
		if alive(m) and not m.Model:GetAttribute("Fighting") and not m.Model:GetAttribute("Brawling") and m.Post and not (S.Brawl and S.Brawl.IsBrawling(m)) then
			if (m.Root.Position - m.Post).Magnitude > 3 then
				S.Citizens.SetGait(m, 9, "walk")
				m.Humanoid:MoveTo(m.Post)
			elseif not m.Model:GetAttribute("Action") or m.Model:GetAttribute("Action") == "" then
				m.Model:SetAttribute("Action", ({ "chat", "wait", "phone" })[math.random(1, 3)])
			end
		end
	end
	-- players on the corner
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - crew.Spot).Magnitude
			if d < 26 and not (crew.Angry[player] and crew.Angry[player] > now) then
				crew.Seen[player] = crew.Seen[player] or now
				local stay = now - crew.Seen[player]
				local talker
				for _, m in ipairs(crew.Members) do
					if alive(m) then
						talker = m
						break
					end
				end
				if talker then
					if stay < 1 then
						S.Citizens.Say(talker, TAUNTS[math.random(1, #TAUNTS)], "angry", 2.5)
						S.City.Toast(player, crew.Info.Emoji, crew.Info.Name .. " turf", "You're on the " .. crew.Info.Name .. "' corner. Don't hang around.", crew.Info.Color)
					elseif stay > 9 and not crew.Warned[player] then
						crew.Warned[player] = true
						S.Citizens.Say(talker, WARN[math.random(1, #WARN)], "angry", 2.5)
					elseif stay > 16 then
						GangService.Provoke(talker, player)
						if S.Crime and S.Crime.StartFight then
							S.Crime.StartFight(talker, player)
						end
					end
				end
			elseif d > 40 then
				crew.Seen[player] = nil
				crew.Warned[player] = nil
			end
		end
	end
end

-- the two crews clash in the street between their corners
local function gangWar()
	local a, b = crews[1], crews[2]
	if not a or not b or not S.Brawl then
		return
	end
	local fighters = {}
	local pairs_ = math.min(#a.Members, #b.Members)
	local made = 0
	for k = 1, pairs_ do
		local x, y = a.Members[k], b.Members[k]
		if alive(x) and alive(y) and not S.Brawl.IsBrawling(x) and not S.Brawl.IsBrawling(y) then
			-- meet in the middle first
			local mid = (a.Spot + b.Spot) / 2 + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
			x.Root.CFrame = CFrame.new(mid + Vector3.new(2, 3, 0))
			y.Root.CFrame = CFrame.new(mid + Vector3.new(-2, 3, 0))
			if S.Brawl.Fight(x, y, { Gang = true, Quiet = made > 0, Lines = { a.Info.Name .. "! Let's go!", b.Info.Name .. " run this!" } }) then
				made += 1
				table.insert(fighters, x)
			end
		end
	end
	if made > 0 then
		local pos = (a.Spot + b.Spot) / 2
		toastNear(pos, 220, "⚔️", "Gang war!", "The " .. a.Info.Name .. " and the " .. b.Info.Name .. " are fighting in the street, " .. made * 2 .. " of them. Stay back!", rgb(230, 70, 70))
		S.City.News("⚔️ A gang fight broke out in the East End between the " .. a.Info.Name .. " and the " .. b.Info.Name .. ".", "Crime")
		S.City.Adjust("Safety", -3)
	end
end

--------------------------------------------------------------------------------
-- Riots
--------------------------------------------------------------------------------
local riot = nil -- { Until, Center, Fires = folder, Rioters = { brain }, NextFight, NextLoot }
local RIOT_LINES = { "Burn it down!", "Nobody's safe tonight!", "Wooo!!", "Let's go, let's go!", "Grab everything!", "They can't stop all of us!" }

function GangService.RiotActive()
	return riot ~= nil
end

function GangService.StartRiot(reason)
	if riot or Config.RIOTS == false then
		return false
	end
	local center = (S.Map.Places.Plaza and S.Map.Places.Plaza.Door) or S.Map.SpeechSpot or Vector3.new(0, 0, 0)
	local folder = Instance.new("Folder")
	folder.Name = "Riot"
	folder.Parent = workspace
	riot = { Until = os.clock() + (Config.RIOT_TIME or 240), Center = center, Folder = folder, Rioters = {}, NextFight = 0, NextLoot = os.clock() + 15, NextLine = 0 }
	-- burning barricades on the streets around the plaza
	local nodes = {}
	for _, n in ipairs(S.Map.Nodes or {}) do
		local d = (n - center).Magnitude
		if d > 20 and d < 160 then
			table.insert(nodes, n)
		end
	end
	for _ = 1, math.min(6, #nodes) do
		local n = table.remove(nodes, math.random(1, #nodes))
		fire(folder, Vector3.new(n.X, 0, n.Z), true)
	end
	-- masked rioters pour in
	for k = 1, (Config.RIOTERS or 8) do
		local n = S.Map.Nodes[math.random(1, #S.Map.Nodes)]
		local a = math.random() * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * math.random(20, 60), 3, math.sin(a) * math.random(20, 60))
		local brain = S.Citizens.SpawnExtra({ Name = "Rioter", First = "Rioter", Job = "Rioter", Age = math.random(18, 35), Activity = "🔥 Rioting" }, CFrame.new(pos))
		brain.Rioter = true
		brain.Gang = "Rioters" -- (they don't go home after a fight)
		brain.HP = 100
		brain.C.Personality = "grumpy"
		S.Citizens.Control(brain, true)
		table.insert(riot.Rioters, brain)
	end
	S.City.News("🔥 RIOT! " .. (reason or "Chaos broke out downtown") .. ". Fires are burning around the plaza and the police are overwhelmed.", "Crime")
	S.City.Adjust("Safety", -10)
	S.City.Adjust("Happiness", -6)
	for _, p in ipairs(Players:GetPlayers()) do
		S.City.Toast(p, "🔥", "RIOT DOWNTOWN!", "Fights everywhere, stores looted, fires in the streets. Get involved, get out of the way, or help the police.", rgb(240, 90, 40))
	end
	workspace:SetAttribute("Riot", true)
	return true
end

local function endRiot()
	if not riot then
		return
	end
	for _, r in ipairs(riot.Rioters) do
		if r.Model.Parent then
			S.Citizens.Despawn(r)
		end
	end
	riot.Folder:Destroy()
	riot = nil
	workspace:SetAttribute("Riot", nil)
	S.City.News("🚓 The riot is over. Police cleared the streets downtown and the fires are out.", "Crime")
	for _, p in ipairs(Players:GetPlayers()) do
		S.City.Toast(p, "🚓", "The riot is over", "The police got the city back under control.", rgb(90, 140, 230))
	end
end

local function riotTick(now)
	if now > riot.Until then
		endRiot()
		return
	end
	-- rioters run from street to street, shouting and picking fights
	for _, r in ipairs(riot.Rioters) do
		if alive(r) and not (S.Brawl and S.Brawl.IsBrawling(r)) and not r.Model:GetAttribute("Fighting") then
			if not r.Goal or (r.Root.Position - r.Goal).Magnitude < 4 or now > (r.GoalUntil or 0) then
				local a = math.random() * math.pi * 2
				r.Goal = riot.Center + Vector3.new(math.cos(a) * math.random(10, 90), 0, math.sin(a) * math.random(10, 90))
				r.GoalUntil = now + 8
			end
			S.Citizens.SetGait(r, 15, "run")
			r.Humanoid:MoveTo(r.Goal)
			if now >= riot.NextLine and math.random() < 0.2 then
				riot.NextLine = now + 2
				S.Citizens.Say(r, RIOT_LINES[math.random(1, #RIOT_LINES)], "angry", 2)
			end
		end
	end
	-- fights break out everywhere
	if S.Brawl and now >= riot.NextFight and #S.Brawl.Active() < (Config.RIOT_BRAWLS or 6) then
		riot.NextFight = now + 3
		local pool = {}
		for _, brain in ipairs(S.Citizens.Nearby(riot.Center, 130)) do
			if alive(brain) and not S.Brawl.IsBrawling(brain) and not brain.Model:GetAttribute("Fighting") and not brain.Model:GetAttribute("Chasing") and (brain.Rioter or (brain.State == "walk" and not brain.C.Temp and S.Life:Age(brain.C) >= 18)) then
				table.insert(pool, brain)
			end
		end
		if #pool >= 2 then
			local x = table.remove(pool, math.random(1, #pool))
			local best, bestD = nil, math.huge
			for _, y in ipairs(pool) do
				local d = (y.Root.Position - x.Root.Position).Magnitude
				if d < bestD then
					best, bestD = y, d
				end
			end
			if best and bestD < 50 then
				S.Brawl.Fight(x, best, { Quiet = true, Lines = { RIOT_LINES[math.random(1, #RIOT_LINES)], "Get off me!" } })
			end
		end
	end
	-- stores get looted
	if S.StreetCrime and now >= riot.NextLoot then
		riot.NextLoot = now + math.random(15, 30)
		pcall(S.StreetCrime.Commit, "robbery")
	end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
function GangService.Start(services)
	S = services
	if Config.GANGS ~= false then
		local rng = Random.new((Config.SEED or 1) + 99)
		local folder = Instance.new("Folder")
		folder.Name = "EastEnd"
		folder.Parent = workspace:FindFirstChild("City") or workspace
		local blocks = Config.GANG_TURF or { { 4, 0 }, { 4, 1 } }
		for k, ij in ipairs(blocks) do
			local c = Vector3.new(ij[1] * MapKit.SPACING, 0, ij[2] * MapKit.SPACING)
			table.insert(turf, c)
			dressTurf(folder, c, rng)
			local info = CREWS[(k - 1) % #CREWS + 1]
			-- their corner: the sidewalk at the block's west corner, by a fire barrel
			local spot = c + Vector3.new(-(MapKit.HALF - 3), MapKit.LOT_Y, (if k == 1 then 1 else -1) * (MapKit.HALF - 3))
			fire(folder, spot + Vector3.new(0, -MapKit.LOT_Y, 0), false)
			local crew = { Info = info, Spot = spot, Members = {}, Angry = {}, Seen = {}, Warned = {} }
			table.insert(crews, crew)
			-- (once the citizens are in the world; each member on its own thread,
			-- a body can take a moment to load)
			task.spawn(function()
				for _ = 1, 60 do
					if workspace:FindFirstChild("Citizens") then
						break
					end
					task.wait(0.5)
				end
				for _ = 1, (Config.GANG_SIZE or 5) do
					task.spawn(function()
						local ok, err = pcall(spawnMember, crew)
						if not ok then
							warn("[GangService] couldn't spawn a member: " .. tostring(err))
						end
					end)
				end
				crew.NextRecruit = os.clock() + 60
			end)
			crew.NextRecruit = math.huge
		end
		warAt = os.clock() + (Config.GANG_WAR_EVERY or 240) * 0.6
	end
	task.spawn(function()
		local lastRiotCheck = os.clock()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, crew in ipairs(crews) do
				local ok, err = pcall(crewTick, crew, now)
				if not ok then
					warn("[GangService] " .. tostring(err))
				end
			end
			-- a gang war when someone is around to see it
			if #crews >= 2 and now >= warAt then
				local _, d = nearestPlayer((crews[1].Spot + crews[2].Spot) / 2)
				if d < 200 then
					warAt = now + (Config.GANG_WAR_EVERY or 240) * (0.7 + math.random() * 0.6)
					pcall(gangWar)
				end
			end
			if riot then
				local ok, err = pcall(riotTick, now)
				if not ok then
					warn("[GangService] riot: " .. tostring(err))
				end
			elseif Config.RIOTS ~= false and now - lastRiotCheck > 30 then
				lastRiotCheck = now
				local safety = S.City.State.Safety or 60
				local hour = S.City.Hour()
				local night = hour >= 20 or hour < 4
				if safety < (Config.RIOT_SAFETY or 20) and math.random() < 0.5 then
					GangService.StartRiot("The city is fed up: safety hit rock bottom")
				elseif night and math.random() < (Config.RIOT_CHANCE or 0.01) then
					GangService.StartRiot("A night of chaos broke out downtown")
				end
			end
		end
	end)
end

GangService.Crews = crews
GangService.EndRiot = endRiot

return GangService
