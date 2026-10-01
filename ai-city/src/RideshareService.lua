-- RideshareService (ModuleScript) — ServerScriptService.Modules.RideshareService
-- 🚕 Drive people around in your own car for money.
--
-- Turn it on with the 🚕 Rides app on your phone, then get in your car
-- (buy one at AutoLand; K calls it). Before long someone nearby steps to the
-- curb and waves you down: a 🙋 marker shows who. Pull up next to them and
-- stop: they hop in the passenger seat and tell you where they're going (a
-- marker shows the way). Stop at the door and they get out and pay:
--   • the fare: 15 coins plus 1 for every 20 studs of the trip
--   • a tip if you were quick (and no tip if you took forever)
--   • a rating out of 5 stars: they knock stars off for speeding way over the
--     limit, for running people over, and for taking too long
-- Your trips and your average rating show in the app. Get out of your car for
-- too long, or turn the app off, and your passenger gets out and walks.

local Players = game:GetService("Players")

local RideshareService = {}
local S

local drivers = {} -- [player] = { On, Fare, Hail, Trips, Stars, Earned }
RideshareService.Drivers = drivers

local HELLO = { "Hi! Thanks for stopping.", "Oh good, a ride!", "Phew, my feet were killing me.", "Hey there! Nice car." }
local WHERE = { "To the %s, please.", "Can you take me to the %s?", "The %s, and step on it!", "I'm going to the %s." }
local THANKS = { "Thanks for the ride!", "Great driving!", "That was fast!", "Have a good one!" }
local SLOW = { "Finally...", "That took forever.", "I could have walked faster." }
local SCARED = { "Are you TRYING to kill us?!", "Slow down!!", "I want to get out!" }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function carOf(player)
	local car = S.Cars and S.Cars.Spawned and S.Cars.Spawned[player]
	if car and car.Parent and car.PrimaryPart then
		return car
	end
	return nil
end

-- is this player sitting in their own car's driver's seat?
local function driving(player)
	local car = carOf(player)
	local seat = car and car:FindFirstChild("DriverSeat")
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return car ~= nil and seat ~= nil and hum ~= nil and seat.Occupant == hum, car
end
RideshareService.Driving = driving

local function speedOf(car)
	local v = car.PrimaryPart.AssemblyLinearVelocity or Vector3.zero
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function show(player, d)
	player:SetAttribute("Rideshare", d.On or nil)
	player:SetAttribute("RideshareTrips", d.Trips)
	player:SetAttribute("RideshareRating", if d.Trips > 0 then math.floor(d.Stars / d.Trips * 10 + 0.5) / 10 else nil)
end

local function release(brain)
	if brain and brain.Model.Parent then
		brain.Model:SetAttribute("Hailing", nil)
		brain.Model:SetAttribute("RideSeat", nil)
		brain.Model:SetAttribute("Action", "")
		S.Citizens.Control(brain, false)
	end
end

-- the passenger gets out (at the door, or wherever the car is)
local function getOut(d, at)
	local fare = d.Fare
	d.Fare = nil
	if not fare then
		return
	end
	local brain = fare.Brain
	if fare.Weld then
		fare.Weld:Destroy()
	end
	if brain.Model.Parent then
		for _, p in ipairs(brain.Model:GetDescendants()) do
			if p:IsA("BasePart") and fare.Mass[p] ~= nil then
				p.Massless = fare.Mass[p]
			end
		end
		brain.Root.Anchored = false
		brain.Root.CFrame = CFrame.new(at + Vector3.new(0, 3.2, 0))
		brain.Root.AssemblyLinearVelocity = Vector3.zero
		brain.Model:SetAttribute("Passenger", nil)
		release(brain)
	end
end

local function cancel(player, d, why)
	if d.Fare then
		local car = carOf(player)
		local at = if car then car.PrimaryPart.Position + car.PrimaryPart.CFrame.RightVector * 5 else d.Fare.Brain.Root.Position
		S.Citizens.Say(d.Fare.Brain, "Fine, I'll walk.", "angry", 3)
		getOut(d, at)
	end
	if d.Hail then
		release(d.Hail.Brain)
		d.Hail = nil
	end
	S.City.Send(player, { Type = "Waypoint", Clear = true })
	if why then
		S.City.Toast(player, "🚕", "Ride cancelled", why, rgb(220, 130, 80))
	end
end

-- someone near you steps out and waves you down
local function findHail(player, d, car)
	local pos = car.PrimaryPart.Position
	local best, bestD
	for _, brain in ipairs(S.Citizens.Nearby(pos, 170)) do
		local dist = (brain.Root.Position - pos).Magnitude
		if dist > 35 and not brain.Temp and brain.State == "walk" and (brain.Floor or 1) == 1 and not brain.Building and S.Life:Age(brain.C) >= 16 and not brain.Model:GetAttribute("Hailing") and not brain.Model:GetAttribute("Passenger") then
			if not bestD or math.abs(dist - 80) < math.abs(bestD - 80) then
				best, bestD = brain, dist
			end
		end
	end
	if not best then
		return
	end
	S.Citizens.Control(best, true)
	best.Humanoid:MoveTo(best.Root.Position)
	best.Model:SetAttribute("Action", "hail")
	best.Model:SetAttribute("Hailing", player.UserId)
	best.Model:SetAttribute("Activity", "🙋 Waving down a ride")
	S.Citizens.Say(best, "Taxi! TAXI!", "happy", 3)
	d.Hail = { Brain = best, Since = os.clock() }
	S.City.Send(player, { Type = "Waypoint", Position = best.Root.Position, Label = "Pickup: " .. best.C.First, Emoji = "🙋", Model = best.Model, CitizenId = best.C.Id })
	S.City.Toast(player, "🙋", best.C.First .. " needs a ride", "Pull up next to them and stop.", rgb(250, 200, 60))
end

local function pickUp(player, d, car)
	local brain = d.Hail.Brain
	d.Hail = nil
	-- where to? somewhere a good way across town
	local here = brain.Root.Position
	local options = {}
	for _, place in ipairs(S.Map.PlaceList) do
		if place.Door and not place.Outdoor or place.Id == "Funland" or place.Id == "Beach" then
			local dist = place.Door and (place.Door - here).Magnitude or 0
			if dist > 220 and dist < 1300 then
				table.insert(options, place)
			end
		end
	end
	if #options == 0 then
		release(brain)
		return
	end
	local place = options[math.random(1, #options)]
	local seat = car:FindFirstChild("PassengerSeat")
	if not seat then
		release(brain)
		return
	end
	-- in the passenger seat: welded on, and weightless so the car drives the same
	local mass = {}
	for _, p in ipairs(brain.Model:GetDescendants()) do
		if p:IsA("BasePart") then
			mass[p] = p.Massless
			p.Massless = true
		end
	end
	brain.Root.Anchored = false
	brain.Root.CFrame = seat.CFrame * CFrame.new(0, 1.8, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "PassengerWeld"
	weld.Part0, weld.Part1 = seat, brain.Root
	weld.Parent = brain.Root
	brain.Model:SetAttribute("Hailing", nil)
	brain.Model:SetAttribute("Passenger", player.UserId)
	brain.Model:SetAttribute("Action", "ride")
	brain.Model:SetAttribute("Activity", "🚕 Riding to the " .. (place.Label or place.Id))
	local dist = (place.Door - here).Magnitude
	d.Fare = {
		Brain = brain, Place = place, Start = os.clock(), Dist = dist, Weld = weld, Mass = mass,
		Expect = 25 + dist / 28, Speeding = 0, Hits = 0,
	}
	S.Citizens.Say(brain, HELLO[math.random(1, #HELLO)] .. " " .. string.format(WHERE[math.random(1, #WHERE)], place.Label or place.Id), "happy", 4)
	S.City.Send(player, { Type = "Waypoint", Position = place.Door, Label = "Drop off: " .. (place.Label or place.Id), Emoji = "📍" })
	S.City.Toast(player, "🚕", brain.C.First .. " is in", "To the " .. (place.Label or place.Id) .. " (" .. math.floor(dist) .. " studs): about " .. (15 + math.floor(dist / 20)) .. " coins, more if you're quick.", rgb(250, 200, 60))
end

local function dropOff(player, d, car)
	local fare = d.Fare
	local trip = os.clock() - fare.Start
	local base = 15 + math.floor(fare.Dist / 20)
	-- the rating: quick and careful is five stars
	local stars = 5
	if trip > fare.Expect * 1.6 then
		stars -= 2
	elseif trip > fare.Expect then
		stars -= 1
	end
	stars -= math.min(2, math.floor(fare.Speeding / 6))
	stars -= fare.Hits * 2
	stars = math.clamp(stars, 1, 5)
	local tip = if trip < fare.Expect * 0.8 and stars >= 4 then math.random(10, 25) elseif trip < fare.Expect and stars >= 4 then math.random(3, 9) else 0
	local brain = fare.Brain
	local line = if stars <= 2 and fare.Hits > 0 then SCARED[math.random(1, #SCARED)] elseif trip > fare.Expect * 1.6 then SLOW[math.random(1, #SLOW)] else THANKS[math.random(1, #THANKS)]
	S.Citizens.Say(brain, line .. (if tip > 0 then " Keep the change!" else ""), if stars >= 4 then "happy" elseif stars <= 2 then "angry" else "neutral", 3)
	local door = fare.Place.Door
	local out = car.PrimaryPart.Position + car.PrimaryPart.CFrame.RightVector * 5
	getOut(d, out)
	if brain.Model.Parent and not brain.C.Temp then
		pcall(S.City.Remember, brain.C, player, if stars >= 4 then "gave me a great ride" else "gave me a scary ride", if stars >= 4 then 6 else -6, if stars >= 4 then "drives a great taxi" else nil)
	end
	S.City.AddCoins(player, base + tip, "🚕 Rideshare fare" .. (if tip > 0 then " + tip" else ""))
	d.Trips += 1
	d.Stars += stars
	d.Earned += base + tip
	show(player, d)
	S.City.Toast(player, "🚕", "Trip done! +" .. (base + tip) .. " coins", string.rep("★", stars) .. string.rep("☆", 5 - stars) .. "  ·  " .. math.floor(trip) .. "s" .. (if tip > 0 then " · " .. tip .. " coin tip" else "") .. "  ·  " .. d.Trips .. " trips, " .. string.format("%.1f", d.Stars / d.Trips) .. "★ average", rgb(90, 200, 120))
	S.City.Send(player, { Type = "Waypoint", Clear = true })
	d.NextHail = os.clock() + math.random(6, 12)
	return base + tip, stars
end
RideshareService.DropOff = dropOff

local function step(player, d)
	local isDriving, car = driving(player)
	local now = os.clock()
	if not isDriving then
		d.Away = d.Away or now
		if now - d.Away > 20 and (d.Fare or d.Hail) then
			cancel(player, d, "You left your passenger waiting too long.")
		end
		return
	end
	d.Away = nil
	local speed = speedOf(car)
	local pos = car.PrimaryPart.Position
	if d.Fare then
		local fare = d.Fare
		if not fare.Brain.Model.Parent then
			d.Fare = nil
			return
		end
		if speed > 70 then
			fare.Speeding += 1
			if fare.Speeding % 8 == 1 then
				S.Citizens.Say(fare.Brain, SCARED[math.random(1, #SCARED)], "scared", 2.5)
			end
		end
		if (fare.Place.Door - pos).Magnitude < 22 and speed < 6 then
			dropOff(player, d, car)
		end
	elseif d.Hail then
		local brain = d.Hail.Brain
		if not brain.Model.Parent or brain.State == "ko" then
			d.Hail = nil
		elseif (brain.Root.Position - pos).Magnitude < 12 and speed < 6 then
			pickUp(player, d, car)
		elseif now - d.Hail.Since > 70 then
			S.Citizens.Say(brain, "Forget it, I'll walk.", "angry", 3)
			release(brain)
			d.Hail = nil
			S.City.Send(player, { Type = "Waypoint", Clear = true })
		end
	elseif d.On and now > (d.NextHail or 0) then
		d.NextHail = now + 5
		findHail(player, d, car)
	end
end
RideshareService.Step = step

-- the app: turn it on and off
function RideshareService.Toggle(player, on)
	local d = drivers[player]
	if not d then
		d = { Trips = 0, Stars = 0, Earned = 0 }
		drivers[player] = d
	end
	if on == nil then
		on = not d.On
	end
	if on and not carOf(player) and not (S.City.Data(player) and S.City.Data(player).Car) then
		return { Ok = false, Error = "You need a car first: buy one at 🚗 AutoLand (up Shore Drive)." }
	end
	d.On = on
	if not on then
		cancel(player, d, nil)
	end
	d.NextHail = os.clock() + 4
	show(player, d)
	S.City.Toast(player, "🚕", if on then "You're on duty" else "Off duty", if on then "Get in your car and drive around: someone will wave you down soon." else "No more ride requests.", rgb(250, 200, 60))
	return { Ok = true, On = on, Trips = d.Trips, Earned = d.Earned }
end

function RideshareService.Start(services)
	S = services
	S.City.Handle("Rideshare", function(player, data)
		return RideshareService.Toggle(player, data and data.On)
	end)
	-- a hit while carrying a passenger costs stars (see CarService)
	RideshareService.OnHit = function(player)
		local d = drivers[player]
		if d and d.Fare then
			d.Fare.Hits += 1
		end
	end
	task.spawn(function()
		while true do
			task.wait(0.4)
			for player, d in pairs(drivers) do
				if not player.Parent then
					drivers[player] = nil
				elseif d.On or d.Fare or d.Hail then
					local ok, err = pcall(step, player, d)
					if not ok then
						warn("[RideshareService] " .. tostring(err))
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local d = drivers[player]
		if d then
			pcall(cancel, player, d, nil)
		end
		drivers[player] = nil
	end)
end

return RideshareService
