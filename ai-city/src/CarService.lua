-- CarService (ModuleScript) — ServerScriptService.Modules.CarService
-- Cars of your own.
--
--   🚗 AutoLand, up Shore Drive: walk up to a car on the lot and press E to buy
--      it (or to switch to one you own). It's waiting for you on the drive.
--   K (or the Car app on your phone) calls your car: it pulls up on the nearest road next to you.
--   Sit in the driver's seat to drive: W / S (or the triggers / left stick) to
--      go and brake, A / D to steer, Space to get out. Friends can ride along
--      in the other seats. Only you can drive your own car.
--   Careful: running people over hurts them, and if anyone sees it, it's a
--      crime (see CrimeService).
--
-- Your car is physical: the server builds it and hands it to your computer to
-- drive (the client's Drive module), so it handles smoothly.

local Players = game:GetService("Players")

local CarService = {}
local S

CarService.CARS = {
	{ Id = "Compact", Name = "City Compact", Emoji = "🚗", Price = 250, MaxSpeed = 50, Accel = 16, Turn = 1.7, Color = Color3.fromRGB(80, 170, 220), Desc = "Small, nimble and cheap. Parks anywhere." },
	{ Id = "Sedan", Name = "Family Sedan", Emoji = "🚙", Price = 600, MaxSpeed = 60, Accel = 18, Turn = 1.5, Color = Color3.fromRGB(150, 150, 160), Desc = "Four doors, room for friends, a smooth ride." },
	{ Id = "Pickup", Name = "Pickup Truck", Emoji = "🛻", Price = 800, MaxSpeed = 58, Accel = 17, Turn = 1.35, Color = Color3.fromRGB(190, 60, 50), Desc = "Tough, tall and loud. A bed in the back." },
	{ Id = "Van", Name = "Delivery Van", Emoji = "🚐", Price = 700, MaxSpeed = 52, Accel = 14, Turn = 1.3, Color = Color3.fromRGB(240, 240, 236), Desc = "Big and boxy. Carries the whole crew." },
	{ Id = "Sports", Name = "Sports Car", Emoji = "🏎️", Price = 2000, MaxSpeed = 90, Accel = 28, Turn = 1.8, Color = Color3.fromRGB(245, 200, 40), Desc = "Low, loud and FAST. Hold on tight." },
}
local byId = {}
for _, c in ipairs(CarService.CARS) do
	byId[c.Id] = c
end

local cars = {} -- [player] = the car model they called
CarService.Spawned = cars

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

--------------------------------------------------------------------------------
-- Building a car (for the lot, or to drive)
--------------------------------------------------------------------------------
-- the body parts, laid out around the car's ground point (facing -Z)
local function shape(spec)
	local style = spec.Id
	local long = if style == "Van" then 13 elseif style == "Pickup" then 13 elseif style == "Compact" then 10 else 11.5
	local tall = if style == "Van" then 3.6 elseif style == "Sports" then 1.6 elseif style == "Pickup" then 2.6 else 2.2
	local cabinZ, cabinL, cabinH = 0.6, 5.6, 2
	if style == "Van" then
		cabinZ, cabinL, cabinH = 0.4, 11, 2.4
	elseif style == "Pickup" then
		cabinZ, cabinL = -1.6, 4.6
	elseif style == "Sports" then
		cabinZ, cabinL, cabinH = 0.8, 4.4, 1.5
	end
	return long, tall, cabinZ, cabinL, cabinH
end

function CarService.Build(spec, cf, drivable, parent)
	local m = Instance.new("Model")
	m.Name = if drivable then "PlayerCar" else "LotCar"
	local long, tall, cabinZ, cabinL, cabinH = shape(spec)
	local color = spec.Color
	local glass = rgb(40, 50, 62)
	local chassis
	local function add(name, size, offset, c, material, shapeType)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * offset
		p.Color = c
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		if shapeType then
			p.Shape = shapeType
		end
		p.CanCollide = false
		p.Anchored = not drivable
		if drivable then
			p.Massless = true
		end
		p.Parent = m
		if chassis and drivable then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = chassis, p
			w.Parent = p
		end
		return p
	end
	-- the chassis: the solid part that touches the road (invisible)
	chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6.2, 1.8, long)
	chassis.CFrame = cf * CFrame.new(0, 1.1, 0)
	chassis.Transparency = 1
	chassis.Anchored = not drivable
	chassis.CanCollide = drivable
	pcall(function()
		chassis.CustomPhysicalProperties = PhysicalProperties.new(0.8, 0.02, 0, 100, 1)
	end)
	chassis.Parent = m
	m.PrimaryPart = chassis
	add("Body", Vector3.new(6, tall, long), CFrame.new(0, 1.2 + tall / 2, 0), color, nil).Reflectance = 0.12
	add("Cabin", Vector3.new(5.4, cabinH, cabinL), CFrame.new(0, 1.2 + tall + cabinH / 2, cabinZ), color:Lerp(Color3.new(0, 0, 0), 0.08))
	add("Windshield", Vector3.new(5, cabinH * 0.8, 0.2), CFrame.new(0, 1.2 + tall + cabinH / 2, cabinZ - cabinL / 2 - 0.05), glass, Enum.Material.Glass)
	for _, sx in ipairs({ -1, 1 }) do
		add("SideWindow", Vector3.new(0.2, cabinH * 0.75, cabinL - 1), CFrame.new(sx * 2.72, 1.2 + tall + cabinH / 2, cabinZ), glass, Enum.Material.Glass)
		for _, sz in ipairs({ -1, 1 }) do
			add("Wheel", Vector3.new(1, 2.4, 2.4), CFrame.new(sx * 2.8, 1.2, sz * (long / 2 - 2.1)) * CFrame.Angles(0, 0, math.rad(90)), rgb(22, 22, 25), Enum.Material.Rubber, Enum.PartType.Cylinder)
			add("Hubcap", Vector3.new(1.05, 1.2, 1.2), CFrame.new(sx * 2.8, 1.2, sz * (long / 2 - 2.1)) * CFrame.Angles(0, 0, math.rad(90)), rgb(200, 200, 206), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		add("Headlight", Vector3.new(1.2, 0.6, 0.2), CFrame.new(sx * 2, 1.8 + tall / 2, -long / 2 - 0.05), rgb(255, 250, 220), Enum.Material.Neon)
		add("Taillight", Vector3.new(1.2, 0.5, 0.2), CFrame.new(sx * 2, 1.8 + tall / 2, long / 2 + 0.05), rgb(200, 30, 30), Enum.Material.Neon)
	end
	if spec.Id == "Sports" then
		add("Spoiler", Vector3.new(5.6, 0.3, 1.2), CFrame.new(0, 1.2 + tall + 1, long / 2 - 0.6), rgb(30, 30, 34))
		add("Stripe", Vector3.new(1.2, 0.05, long), CFrame.new(0, 1.2 + tall + 0.03, 0), rgb(30, 30, 34))
	elseif spec.Id == "Pickup" then
		add("BedWall", Vector3.new(6, 1.2, 0.3), CFrame.new(0, 1.2 + tall + 0.6, long / 2 - 0.15), color:Lerp(Color3.new(0, 0, 0), 0.1))
	end
	if drivable then
		-- the seats: you drive from the front left, friends ride along
		local seat = Instance.new("VehicleSeat")
		seat.Name = "DriverSeat"
		seat.Size = Vector3.new(2, 0.6, 2)
		seat.CFrame = cf * CFrame.new(-1.3, 1.2 + tall - 0.1, cabinZ + 0.4)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.Massless = true
		seat.MaxSpeed = 0
		seat.Torque = 0
		seat.HeadsUpDisplay = false
		seat.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = chassis, seat
		w.Parent = seat
		for n, off in ipairs({ { 1.3, cabinZ + 0.4 }, { -1.3, cabinZ + 2.6 }, { 1.3, cabinZ + 2.6 } }) do
			if n == 1 or spec.Id ~= "Sports" then
				local ps = Instance.new("Seat")
				ps.Name = "PassengerSeat"
				ps.Size = Vector3.new(2, 0.6, 2)
				ps.CFrame = cf * CFrame.new(off[1], 1.2 + tall - 0.1, off[2])
				ps.Transparency = 1
				ps.CanCollide = false
				ps.Massless = true
				ps.Parent = m
				local pw = Instance.new("WeldConstraint")
				pw.Part0, pw.Part1 = chassis, ps
				pw.Parent = ps
			end
		end
		-- keep it upright (it can still turn and go over bumps)
		pcall(function()
			local a = Instance.new("Attachment")
			a.Name = "Upright"
			a.Axis = Vector3.new(0, 1, 0)
			a.SecondaryAxis = Vector3.new(1, 0, 0)
			a.Parent = chassis
			local align = Instance.new("AlignOrientation")
			align.Mode = Enum.OrientationAlignmentMode.OneAttachment
			align.AlignType = Enum.AlignType.PrimaryAxisParallel
			align.PrimaryAxis = Vector3.new(0, 1, 0)
			align.Attachment0 = a
			align.MaxTorque = 4e5
			align.Responsiveness = 40
			align.Parent = chassis
		end)
		m:SetAttribute("CityCar", true)
		m:SetAttribute("CarId", spec.Id)
		m:SetAttribute("MaxSpeed", spec.MaxSpeed)
		m:SetAttribute("Accel", spec.Accel)
		m:SetAttribute("Turn", spec.Turn)
	end
	m.Parent = parent or workspace
	return m
end

--------------------------------------------------------------------------------
-- Calling your car
--------------------------------------------------------------------------------
-- a spot in the right-hand lane of the road nearest to a position (or just in
-- front of you, away from the city's roads)
function CarService.RoadSpot(pos, look)
	local sp = S.Map.Spacing or 134
	local road = S.Map.Road or 26
	local lane = S.Map.Lane or 3.4
	local extent = S.Map.Extent or 737
	local function nearestLine(v)
		return (math.floor(v / sp) + 0.5) * sp
	end
	local lx, lz = nearestLine(pos.X), nearestLine(pos.Z)
	local dx, dz = math.abs(pos.X - lx), math.abs(pos.Z - lz)
	local inCity = math.abs(pos.X) < extent + 10 and math.abs(pos.Z) < extent + 10
	if inCity and math.min(dx, dz) < 70 then
		if dx < dz then
			-- an avenue (runs along Z): head the way you're facing
			local dir = if look.Z >= 0 then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
			local p = Vector3.new(lx, 0.1, pos.Z) + Vector3.new(-dir.Z, 0, dir.X) * (road / 2 - 3.6)
			return CFrame.lookAt(p, p + dir)
		else
			local dir = if look.X >= 0 then Vector3.new(1, 0, 0) else Vector3.new(-1, 0, 0)
			local p = Vector3.new(pos.X, 0.1, lz) + Vector3.new(-dir.Z, 0, dir.X) * (road / 2 - 3.6)
			return CFrame.lookAt(p, p + dir)
		end
	end
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	local p = pos + flat * 9 - Vector3.new(0, 2.9, 0)
	return CFrame.lookAt(p, p + Vector3.new(-flat.Z, 0, flat.X))
end

local function despawn(player)
	local old = cars[player]
	if old then
		cars[player] = nil
		if old.Parent then
			old:Destroy()
		end
	end
end

function CarService.Spawn(player, id, cf)
	local pd = S.City.Data(player)
	local spec = byId[id or (pd and pd.Car) or ""]
	if not spec then
		return nil
	end
	despawn(player)
	local color = spec.Color
	local car = CarService.Build({ Id = spec.Id, Color = color, MaxSpeed = spec.MaxSpeed, Accel = spec.Accel, Turn = spec.Turn }, cf, true, workspace)
	car:SetAttribute("Owner", player.UserId)
	car.Name = player.Name .. "'s " .. spec.Name
	cars[player] = car
	local seat = car:FindFirstChild("DriverSeat")
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		local who = hum and Players:GetPlayerFromCharacter(hum.Parent)
		if hum and who ~= player then
			-- not your car
			hum.Sit = false
			if who then
				S.City.Toast(who, "🔒", "Not your car", "Buy your own at 🚗 AutoLand (up Shore Drive), then press K to call it.", rgb(220, 90, 80))
			end
			return
		end
		if who then
			pcall(function()
				car.PrimaryPart:SetNetworkOwner(who)
			end)
			S.City.Toast(who, spec.Emoji, "Driving your " .. spec.Name, "W / S to drive and brake, A / D to steer, Space to get out.", rgb(80, 170, 240))
		end
	end)
	return car
end

-- K (or the phone's Car app): your car pulls up next to you
function CarService.Call(player)
	local pd = S.City.Data(player)
	local root = rootOf(player)
	if not pd or not root then
		return { Ok = false, Error = "Try again in a moment." }
	end
	if not pd.Car or not byId[pd.Car] then
		return { Ok = false, Error = "You don't have a car yet. Buy one at 🚗 AutoLand, up Shore Drive past the north edge of town." }
	end
	if S.Crime and S.Crime.IsJailed(player) then
		return { Ok = false, Error = "Not from prison!" }
	end
	local car = CarService.Spawn(player, pd.Car, CarService.RoadSpot(root.Position, root.CFrame.LookVector))
	return { Ok = car ~= nil, Car = car }
end

--------------------------------------------------------------------------------
-- 🚗 AutoLand
--------------------------------------------------------------------------------
function CarService.Buy(player, id)
	local pd = S.City.Data(player)
	local spec = byId[id or ""]
	if not pd or not spec then
		return { Ok = false, Error = "That car isn't for sale." }
	end
	pd.Cars = pd.Cars or {}
	if not pd.Cars[id] then
		if not S.City.Spend(player, spec.Price, spec.Emoji .. " Bought a " .. spec.Name) then
			return { Ok = false, Error = "The " .. spec.Name .. " costs " .. spec.Price .. " coins." }
		end
		pd.Cars[id] = true
		S.City.News("🚗 " .. player.DisplayName .. " drove a brand new " .. spec.Name .. " off the lot at AutoLand!", "City", true)
	end
	pd.Car = id
	local NS = S.Map.NorthShore
	local car = CarService.Spawn(player, id, NS and NS.Pickup or CarService.RoadSpot(rootOf(player).Position, Vector3.new(0, 0, -1)))
	S.City.Toast(player, spec.Emoji, "Your " .. spec.Name .. " is ready!", "It's waiting on Shore Drive. Press K (your car keys) or use the 🚗 Car app on your phone anytime to call it to wherever you are.", rgb(80, 200, 120))
	return { Ok = true, Car = car }
end

local function carStore(player)
	local pd = S.City.Data(player)
	local items = {}
	for _, c in ipairs(CarService.CARS) do
		local owned = pd and pd.Cars and pd.Cars[c.Id] == true
		table.insert(items, {
			Id = c.Id, Name = c.Name, Emoji = c.Emoji, Price = c.Price, Desc = c.Desc, Owned = owned, UseText = "🔑 Drive this one", Using = owned and pd.Car == c.Id and cars[player] ~= nil,
			Stats = { { "Speed", c.MaxSpeed, 90 }, { "Pickup", c.Accel, 28 }, { "Turning", c.Turn, 1.8 } },
		})
	end
	return { Title = "AutoLand", Emoji = "🚗", Currency = "coins", Balance = S.City.Coins(player), Action = "Car", Items = items, Note = "Press K anywhere to call your car to the nearest road. W / S to drive, A / D to steer, Space to get out." }
end

function CarService.Request(player, data)
	if data.Op == "call" then
		return CarService.Call(player)
	end
	local r = CarService.Buy(player, data.Id)
	if r.Ok then
		return { Ok = true, Store = carStore(player) }
	end
	return r
end

function CarService.Start(services)
	S = services
	S.City.Handle("Car", CarService.Request)
	S.City.Handle("CarStore", function(player)
		return { Ok = true, Store = carStore(player) }
	end)
	local NS = S.Map and S.Map.NorthShore
	if NS then
		-- the cars on the lot, each with a prompt
		local lot = Instance.new("Folder")
		lot.Name = "AutoLandLot"
		lot.Parent = NS.Model
		for k, cf in ipairs(NS.Display) do
			local spec = CarService.CARS[k]
			if spec then
				local car = CarService.Build(spec, cf, false, lot)
				local body = car:FindFirstChild("Body")
				local p = Instance.new("ProximityPrompt")
				p.ActionText = "Look at the " .. spec.Name
				p.ObjectText = spec.Emoji .. " " .. spec.Price .. " coins"
				p.KeyboardKeyCode = Enum.KeyCode.E
				p.MaxActivationDistance = 12
				p.RequiresLineOfSight = false
				p.Parent = body
				p.Triggered:Connect(function(player)
					local d = carStore(player)
					d.Type = "Store"
					S.City.Send(player, d)
				end)
			end
		end
		-- a salesperson behind the desk
		task.spawn(function()
			while not workspace:FindFirstChild("Citizens") do
				task.wait(0.5)
			end
			pcall(function()
				local rep = S.Citizens.SpawnExtra({ Name = "Sal Motors", First = "Sal", Job = "Car Salesperson", Age = 44, Activity = "🚗 Selling cars" }, CFrame.new(NS.SalesSpot.CFrame.Position + Vector3.new(0, 3, 0)))
				S.Citizens.Control(rep, true)
				S.Citizens.PlaceAt(rep, NS.SalesSpot, "counter")
				rep.Model:SetAttribute("Activity", "🚗 Selling cars at AutoLand")
				CarService.Salesperson = rep
			end)
		end)
	end
	-- running people over
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player, car in pairs(cars) do
				if not player.Parent then
					despawn(player)
				elseif car.Parent and car.PrimaryPart then
					local v = car.PrimaryPart.AssemblyLinearVelocity
					local speed = Vector3.new(v.X, 0, v.Z).Magnitude
					if speed > 16 then
						local front = car.PrimaryPart.Position + v.Unit * 5
						for _, brain in ipairs(S.Citizens.Nearby(front, 5)) do
							if brain.State ~= "ko" and brain.State ~= "hospital" and os.clock() - (brain.HitByCar or 0) > 3 then
								brain.HitByCar = os.clock()
								if speed > 38 and S.Citizens.KnockOut(brain, player.DisplayName) then
									S.City.News("🚑 " .. brain.C.Name .. " was hit by a car.", "Crime", true)
								else
									S.Citizens.Hurt(brain, car.PrimaryPart.Position, "WHOA! Watch where you're going!", 30)
								end
								if S.Crime and S.Crime.Report then
									pcall(S.Crime.Report, player, brain.Root.Position, brain, if speed > 38 then 3 else 1, "hit " .. brain.C.First .. " with your car", "ran someone over", if speed > 38 then 2 else 1)
								end
							end
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(despawn)
end

return CarService
