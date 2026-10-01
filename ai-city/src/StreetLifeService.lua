-- StreetLifeService (ModuleScript) — ServerScriptService.Modules.StreetLifeService
-- The people who make the streets lively (see StreetLife for the trucks):
--   🚚 a cook in every food truck, flipping and serving; players can buy a
--      bite at the window (it heals and refills stamina)
--   🎸 street musicians playing in the plaza, both parks, on the boardwalk and
--      at Funland. People walking by stop to listen, clap, cheer or dance for
--      a while before going on their way, and players can tip them (they bow,
--      and they remember you)

local Players = game:GetService("Players")

local StreetLifeService = {}
local S

StreetLifeService.Cooks = {}
StreetLifeService.Buskers = {}

local COOKS = { "Rosa", "Big Mike", "Lupe", "Theo", "Mei", "Jules" }
local BUSKERS = {
	{ "Plaza", "Ziggy", Vector3.new(-18, 0, 30) },
	{ "Park", "Sunny", Vector3.new(10, 0, 4) },
	{ "WillowPark", "Hollis", Vector3.new(-10, 0, 4) },
	{ "Beach", "Marlow", nil },
	{ "Funland", "Pip", nil },
}
local FOOD = {
	taco = { "🌮", "Tacos", 8, 30 }, burger = { "🍔", "Burger", 10, 40 }, icecream = { "🍦", "Ice cream", 6, 20 },
	wrap = { "🥙", "Gyro", 9, 35 }, noodles = { "🍜", "Noodles", 9, 35 }, coffee = { "☕", "Coffee", 5, 15 },
}
local TUNES = { "♪ La la laaa ♪", "♫ Here's one you'll know ♫", "Thank you, thank you!", "♪ Hmm hmm hmm ♪", "This one's for the city!" }
local WATCH = { "Ooh, they're good!", "I love this song!", "Encore!", "Wow!", "Play another one!" }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function spawnWorker(name, job, spot, action, activity)
	local ok, brain = pcall(S.Citizens.SpawnExtra, { Name = name, First = name, Job = job, Age = math.random(20, 55), Activity = activity }, CFrame.new(spot.CFrame.Position + Vector3.new(0, 3, 0)))
	if not ok or not brain then
		return nil
	end
	S.Citizens.Control(brain, true)
	S.Citizens.PlaceAt(brain, spot, action)
	brain.Model:SetAttribute("Activity", activity)
	brain.Model:SetAttribute("Expression", "happy")
	brain.Staff = true
	return brain
end

-- buy a bite at a truck window
local function buyFood(player, place, cook)
	local food = FOOD[place.Food or "taco"] or FOOD.taco
	local root = rootOf(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if S.Crime and S.Crime.IsJailed and S.Crime.IsJailed(player) then
		return
	end
	if not S.City.Spend(player, food[3], food[1] .. " " .. food[2]) then
		S.City.Toast(player, "🪙", "Not enough coins", food[2] .. " costs " .. food[3] .. " coins.", rgb(220, 120, 80))
		return
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + food[4])
	S.City.Send(player, { Type = "Food", Energy = food[4], Name = food[2] })
	player.Character:SetAttribute("Eating", "truck")
	task.delay(2.6, function()
		if player.Character and player.Character:GetAttribute("Eating") == "truck" then
			player.Character:SetAttribute("Eating", nil)
		end
	end)
	if cook and cook.Model.Parent then
		S.Citizens.Say(cook, ({ "Here you go! Enjoy!", "Hot and fresh!", "Come back soon!", "Best in the city, right?" })[math.random(1, 4)], "happy", 3)
	end
	S.City.Toast(player, food[1], food[2] .. "!", "+" .. food[4] .. " health, and stamina. " .. food[3] .. " coins.", rgb(240, 170, 60))
end

-- tip a street musician
local function tip(player, busker)
	if not busker.Model.Parent then
		return
	end
	if not S.City.Spend(player, 5, "🎸 Tipped " .. busker.C.First) then
		S.City.Toast(player, "🪙", "No coins to tip", "You need 5 coins.", rgb(220, 120, 80))
		return
	end
	busker.Tips = (busker.Tips or 0) + 5
	S.Citizens.React(busker, "salute", "Thank you kindly, " .. player.DisplayName .. "!", "happy", 2.5, rootOf(player) and rootOf(player).Position)
	task.delay(2.6, function()
		if busker.Model.Parent then
			S.Citizens.PlaceAt(busker, busker.Spot, "guitar")
		end
	end)
	if not busker.C.Temp then
		pcall(S.City.Remember, busker.C, player, "tipped me", 8)
	end
	S.City.Toast(player, "🎸", "You tipped " .. busker.C.First, "5 coins in the guitar case. They play you a little flourish.", rgb(250, 200, 80))
end

local function prompt(parent, text, object, key, fn)
	local p = Instance.new("ProximityPrompt")
	p.Name = "StreetPrompt"
	p.ActionText = text
	p.ObjectText = object
	p.KeyboardKeyCode = key
	p.HoldDuration = 0.3
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.Parent = parent
	p.Triggered:Connect(fn)
	return p
end

-- a musician's spot, at a place (an offset from its middle, or near its door)
local function buskSpot(def)
	local place = S.Map.Places[def[1]]
	if not place then
		return nil
	end
	local base
	if def[3] and place.Model and place.Model:IsA("Model") then
		local cf = place.Model:GetPivot()
		base = Vector3.new(cf.Position.X, 0.5, cf.Position.Z) + def[3]
	end
	base = base or ((place.Inside or place.Door) + Vector3.new(6, 0, 6))
	base = Vector3.new(base.X, 0.5, base.Z)
	return { CFrame = CFrame.lookAt(base, base + Vector3.new(0, 0, 1)), Action = "guitar", Role = "work", Floor = 1, Place = def[1] }
end

-- every few seconds near each musician: someone walking by might stop and
-- listen for a while (and someone listening might start dancing)
local function crowdStep()
	for _, b in ipairs(StreetLifeService.Buskers) do
		if b.Model.Parent then
			local pos = b.Root.Position
			b.Next = b.Next or 0
			if os.clock() >= b.Next then
				b.Next = os.clock() + math.random(5, 9)
				if math.random() < 0.35 then
					S.Citizens.Say(b, TUNES[math.random(1, #TUNES)], "happy", 2.5)
				end
				local listeners = 0
				for _, w in ipairs(S.Citizens.Nearby(pos, 26)) do
					if w ~= b and w.Listening and os.clock() < w.Listening then
						listeners += 1
					end
				end
				if listeners < 4 then
					for _, w in ipairs(S.Citizens.Nearby(pos, 30)) do
						if w ~= b and not w.Staff and not w.C.Temp and w.State == "walk" and S.Citizens.CanReact(w) and math.random() < 0.4 then
							local secs = math.random(10, 22)
							w.Listening = os.clock() + secs
							local roll = math.random()
							local action = if roll < 0.35 then "listen" elseif roll < 0.6 then "clap" elseif roll < 0.8 then "cheer" else "dance"
							S.Citizens.React(w, action, if math.random() < 0.4 then WATCH[math.random(1, #WATCH)] else nil, "happy", secs, pos)
							break
						end
					end
				end
			end
		end
	end
end

function StreetLifeService.Start(services)
	S = services
	task.spawn(function()
		local t0 = os.clock()
		while not workspace:FindFirstChild("Citizens") and os.clock() - t0 < 30 do
			task.wait(0.5)
		end
		task.wait(1)
		-- the cooks
		for n, place in ipairs(S.Map.StreetLife or {}) do
			local spot = place.Spots[1]
			if spot then
				local cook = spawnWorker(COOKS[(n - 1) % #COOKS + 1], "Food Truck Cook", spot, "cook", "🍳 Cooking at the " .. (place.Label or "food truck"))
				if cook then
					table.insert(StreetLifeService.Cooks, cook)
					local window = place.Spots[2] and place.Spots[2].CFrame.Position
					local anchor = Instance.new("Part")
					anchor.Name = "TruckWindow"
					anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
					anchor.Transparency = 1
					anchor.Size = Vector3.new(1, 1, 1)
					anchor.CFrame = CFrame.new((window or spot.CFrame.Position) + Vector3.new(0, 2, 0))
					anchor.Parent = place.Model
					local food = FOOD[place.Food or "taco"] or FOOD.taco
					prompt(anchor, "Buy " .. food[2], food[1] .. " " .. food[3] .. " coins", Enum.KeyCode.E, function(player)
						buyFood(player, place, cook)
					end)
				end
			end
		end
		-- the musicians
		for _, def in ipairs(BUSKERS) do
			local spot = buskSpot(def)
			if spot then
				local b = spawnWorker(def[2], "Street Musician", spot, "guitar", "🎸 Busking at the " .. (S.Map.Places[def[1]].Label or def[1]))
				if b then
					b.Spot = spot
					table.insert(StreetLifeService.Buskers, b)
					-- an open guitar case for tips
					local case = Instance.new("Part")
					case.Name = "GuitarCase"
					case.Anchored, case.CanCollide = true, false
					case.Size = Vector3.new(3.2, 0.4, 1.4)
					case.Color = rgb(40, 30, 30)
					case.Material = Enum.Material.Leather
					case.CFrame = spot.CFrame * CFrame.new(0, -0.3, -3)
					case.Parent = b.Model.Parent
					prompt(case, "Tip 5 coins", "🎸 " .. def[2], Enum.KeyCode.E, function(player)
						tip(player, b)
					end)
				end
			end
		end
		while true do
			task.wait(1)
			pcall(crowdStep)
		end
	end)
end

return StreetLifeService
