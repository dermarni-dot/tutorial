-- Traffic (ModuleScript) — StarterPlayerScripts.CityClient.Traffic
-- Cars and city buses driving the streets around you: they keep to the right
-- lane, follow the car in front at a safe distance, stop at red lights
-- downtown (the same cycle the traffic lights show), ease through the other
-- intersections one at a time, turn corners in smooth arcs, stop behind the
-- crosswalk (never on it), give way to anyone in the crosswalk or stepping
-- off the curb (turning cars wait for the people crossing the road they're
-- turning into), and brake for anyone in the road (honking at you). Buses pull up
-- at every bus stop they pass. Headlights come on at night.
--
-- Each player's own screen runs the traffic near their camera, so it costs the
-- server nothing. The cars are solid for you (and for your own car).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Traffic = {}
Traffic.Cars = {}
Traffic.Walkers = {}
Traffic.MaxCars = 26
Traffic.Radius = 380

local player = Players.LocalPlayer
local folder
local S, N, ROAD, LANE = 134, 5, 26, 3.4
local lo, hi -- road indices
local stops = {}
local rng = Random.new()
local walkerPrev = {} -- [model] = { Pos, T, Vel }: how fast people on foot are moving

local COLORS = {
	Color3.fromRGB(214, 60, 60), Color3.fromRGB(60, 116, 214), Color3.fromRGB(236, 236, 236), Color3.fromRGB(36, 36, 40),
	Color3.fromRGB(246, 196, 60), Color3.fromRGB(80, 176, 110), Color3.fromRGB(150, 150, 156), Color3.fromRGB(120, 60, 150),
	Color3.fromRGB(190, 190, 196), Color3.fromRGB(30, 50, 90),
}

local function part(parent, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- a car (or a bus) as parts laid out around its own origin; the parts are moved
-- together every frame (offsets kept in `Parts`)
local function build(kind)
	local m = Instance.new("Model")
	m.Name = if kind == "bus" then "TrafficBus" else "TrafficCar"
	local parts = {}
	local function add(name, size, offset, color, material, shape, solid)
		local p = part(m, name, size, offset, color, material, shape)
		if solid then
			p.CanCollide = true
		end
		table.insert(parts, { Part = p, Offset = offset, Role = name, Front = offset.Position.Z < 0, Side = if offset.Position.X < 0 then -1 else 1 })
		return p
	end
	local glass = Color3.fromRGB(40, 50, 60)
	local lights = {}
	if kind == "bus" then
		local body = Color3.fromRGB(240, 190, 40)
		add("Body", Vector3.new(7, 7, 26), CFrame.new(0, 4.6, 0), body, nil, nil, true)
		add("Stripe", Vector3.new(7.05, 1, 26.05), CFrame.new(0, 3.2, 0), Color3.fromRGB(40, 60, 110))
		for _, sx in ipairs({ -1, 1 }) do
			add("Windows", Vector3.new(0.1, 2.2, 22), CFrame.new(sx * 3.52, 6, 1), glass, Enum.Material.Glass)
			for _, sz in ipairs({ -1, 1 }) do
				add("Wheel", Vector3.new(1, 3, 3), CFrame.new(sx * 3.2, 1.5, sz * 9), Color3.fromRGB(22, 22, 25), Enum.Material.Rubber, Enum.PartType.Cylinder)
				add("Hubcap", Vector3.new(1.05, 1.4, 1.4), CFrame.new(sx * 3.2, 1.5, sz * 9), Color3.fromRGB(200, 200, 206), Enum.Material.Metal, Enum.PartType.Cylinder)
			end
			add("Taillight", Vector3.new(1.2, 0.8, 0.2), CFrame.new(sx * 2.6, 2.6, 13.05), Color3.fromRGB(120, 20, 20), Enum.Material.Neon)
			add("Blinker", Vector3.new(0.5, 0.5, 0.2), CFrame.new(sx * 3.3, 2.6, -13.06), Color3.fromRGB(120, 80, 20), Enum.Material.Neon)
			add("Blinker", Vector3.new(0.5, 0.5, 0.2), CFrame.new(sx * 3.3, 3.6, 13.06), Color3.fromRGB(120, 80, 20), Enum.Material.Neon)
			table.insert(lights, add("Headlight", Vector3.new(1.4, 0.7, 0.2), CFrame.new(sx * 2.4, 2.6, -13.05), Color3.fromRGB(255, 250, 220), Enum.Material.Neon))
		end
		add("Windshield", Vector3.new(6.4, 3, 0.2), CFrame.new(0, 5.8, -13.05), glass, Enum.Material.Glass)
		local sign = add("RouteSign", Vector3.new(4, 1, 0.1), CFrame.new(0, 7.6, -13.1), Color3.fromRGB(20, 20, 20), Enum.Material.Neon)
		sign.Color = Color3.fromRGB(255, 170, 40)
	else
		local color = COLORS[rng:NextInteger(1, #COLORS)]
		local van = rng:NextNumber() < 0.15
		local long = if van then 13 else 11
		local tall = if van then 3.4 else 2.2
		add("Body", Vector3.new(6, tall, long), CFrame.new(0, 1.2 + tall / 2, 0), color, nil, nil, true)
		local cz = if van then 1.5 else 0.6
		add("Cabin", Vector3.new(5.4, 2, 5.6), CFrame.new(0, 2.3 + tall, cz), color:Lerp(Color3.new(0, 0, 0), 0.08))
		add("Windshield", Vector3.new(5, 1.7, 0.2), CFrame.new(0, 2.3 + tall, cz - 2.85), glass, Enum.Material.Glass)
		add("RearWindow", Vector3.new(5, 1.5, 0.2), CFrame.new(0, 2.3 + tall, cz + 2.85), glass, Enum.Material.Glass)
		for _, sx in ipairs({ -1, 1 }) do
			add("SideWindow", Vector3.new(0.2, 1.5, 4.6), CFrame.new(sx * 2.72, 2.3 + tall, cz), glass, Enum.Material.Glass)
			for _, sz in ipairs({ -1, 1 }) do
				add("Wheel", Vector3.new(1, 2.4, 2.4), CFrame.new(sx * 2.8, 1.2, sz * (long / 2 - 2.2)), Color3.fromRGB(22, 22, 25), Enum.Material.Rubber, Enum.PartType.Cylinder)
				-- a hubcap with a spoke on it, so you can see the wheels turn
				add("Hubcap", Vector3.new(1.05, 1.2, 1.2), CFrame.new(sx * 2.8, 1.2, sz * (long / 2 - 2.2)), Color3.fromRGB(200, 200, 206), Enum.Material.Metal, Enum.PartType.Cylinder)
				add("Spoke", Vector3.new(1.1, 1.1, 0.25), CFrame.new(sx * 2.8, 1.2, sz * (long / 2 - 2.2)), Color3.fromRGB(90, 90, 96), Enum.Material.Metal)
			end
			table.insert(lights, add("Headlight", Vector3.new(1.2, 0.6, 0.2), CFrame.new(sx * 2, 1.9 + tall / 2, -long / 2 - 0.05), Color3.fromRGB(255, 250, 220), Enum.Material.Neon))
			add("Taillight", Vector3.new(1.2, 0.5, 0.2), CFrame.new(sx * 2, 1.9 + tall / 2, long / 2 + 0.05), Color3.fromRGB(120, 20, 20), Enum.Material.Neon)
			add("Blinker", Vector3.new(0.45, 0.45, 0.2), CFrame.new(sx * 2.8, 1.9 + tall / 2, -long / 2 - 0.06), Color3.fromRGB(120, 80, 20), Enum.Material.Neon)
			add("Blinker", Vector3.new(0.45, 0.45, 0.2), CFrame.new(sx * 2.8, 1.9 + tall / 2, long / 2 + 0.06), Color3.fromRGB(120, 80, 20), Enum.Material.Neon)
		end
	end
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Range = 40
	beam.Angle = 60
	beam.Brightness = 2
	beam.Color = Color3.fromRGB(255, 244, 220)
	beam.Enabled = false
	beam.Parent = lights[1]
	m.Parent = folder
	return m, parts, beam, (if kind == "bus" then 26 else 11)
end

--------------------------------------------------------------------------------
-- The road grid: intersections at ((a + 0.5) * S, (b + 0.5) * S)
--------------------------------------------------------------------------------
local function node(a, b)
	return Vector3.new((a + 0.5) * S, 0.1, (b + 0.5) * S) -- (the top of the road)
end
local function right(dir)
	return Vector3.new(-dir.Z, 0, dir.X)
end
local function inGrid(a, b)
	return a >= lo and a <= hi and b >= lo and b <= hi
end
-- downtown intersections have traffic lights (see Streets)
local function hasLights(a, b)
	return math.abs(a + 0.5) <= 2 and math.abs(b + 0.5) <= 2
end
-- the same cycle as the lights on screen (see World): 16 seconds, X then Z
local function green(dir)
	local t = workspace:GetServerTimeNow() % 16
	local phase = if math.abs(dir.X) > 0.5 then t else (t + 8) % 16
	return phase < 6.5
end

local DIRS = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }

-- where a car enters / leaves an intersection, in its lane
local function entry(a, b, dir)
	return node(a, b) - dir * (ROAD / 2 + 1) + right(dir) * LANE
end
local function exit(a, b, dir)
	return node(a, b) + dir * (ROAD / 2 + 1) + right(dir) * LANE
end

-- pick where to go at the next intersection (no U-turns, stay on the grid)
local function nextDir(car)
	local a, b = car.A, car.B
	local options = {}
	for _, d in ipairs(DIRS) do
		if d:Dot(car.Dir) > -0.5 then
			local na, nb = a + math.floor(d.X + 0.5), b + math.floor(d.Z + 0.5)
			if inGrid(na, nb) then
				local w = if d:Dot(car.Dir) > 0.5 then 3 else 1
				for _ = 1, w do
					table.insert(options, d)
				end
			end
		end
	end
	if #options == 0 then
		return -car.Dir -- the edge of town: turn around
	end
	return options[rng:NextInteger(1, #options)]
end

local WHEEL = { Wheel = true, Hubcap = true, Spoke = true }
local function place(car, cf)
	car.CF = cf
	local spin = car.Spin or 0
	local steer = car.Steer or 0
	for _, p in ipairs(car.Parts) do
		if WHEEL[p.Role] then
			-- wheels turn about the axle; the front ones steer into turns
			local off = p.Offset
			if p.Front then
				off = off * CFrame.Angles(0, steer, 0)
			end
			p.Part.CFrame = cf * off * CFrame.Angles(spin, 0, 0)
		else
			p.Part.CFrame = cf * p.Offset
		end
	end
end

-- brake lights brighten when slowing; blinkers flash before a turn
local TAIL_ON, TAIL_OFF = Color3.fromRGB(255, 40, 40), Color3.fromRGB(120, 20, 20)
local BLINK_ON, BLINK_OFF = Color3.fromRGB(255, 180, 40), Color3.fromRGB(120, 80, 20)
local function lights(car, braking, blink)
	local t = os.clock()
	local blinkOn = blink ~= 0 and (t * 2.2) % 1 < 0.5
	for _, p in ipairs(car.Parts) do
		if p.Role == "Taillight" then
			local c = if braking then TAIL_ON else TAIL_OFF
			if p.Part.Color ~= c then
				p.Part.Color = c
			end
		elseif p.Role == "Blinker" then
			local c = if blinkOn and p.Side == blink then BLINK_ON else BLINK_OFF
			if p.Part.Color ~= c then
				p.Part.Color = c
			end
		end
	end
end
Traffic.Lights = lights

-- a car on the segment toward intersection (A, B), heading Dir
local function spawnCar(kind, a, b, dir, s)
	local m, parts, beam, length = build(kind)
	local car = {
		Model = m, Parts = parts, Beam = beam, Kind = kind, Length = length,
		A = a, B = b, Dir = dir, Phase = "road", S = s or 0,
		Speed = 0, Max = if kind == "bus" then 15 else rng:NextNumber(17, 24),
	}
	local from = exit(a - math.floor(dir.X + 0.5), b - math.floor(dir.Z + 0.5), dir)
	car.From = from
	car.To = entry(a, b, dir)
	car.Len = (car.To - car.From).Magnitude
	place(car, CFrame.lookAt(from + dir * car.S, from + dir * (car.S + 1)))
	table.insert(Traffic.Cars, car)
	return car
end

local function despawn(car)
	car.Model:Destroy()
	local i = table.find(Traffic.Cars, car)
	if i then
		table.remove(Traffic.Cars, i)
	end
end

-- somebody (you, or a citizen) standing in the road just ahead?
local function blocked(car, camPos)
	local pos, dir = car.CF.Position, car.CF.LookVector
	local function inFront(p)
		local rel = p - pos
		local ahead = rel:Dot(dir)
		local side = math.abs(rel:Dot(right(dir)))
		return ahead > 0 and ahead < car.Length / 2 + 9 and side < 4 and math.abs(rel.Y) < 8
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and inFront(root.Position) then
		return "you"
	end
	if (pos - camPos).Magnitude < 160 then
		for _, p in ipairs(Traffic.Walkers) do
			if (p - pos).Magnitude < 20 and inFront(p) then
				return "someone"
			end
		end
	end
	return nil
end

local function gapAhead(car)
	local best = math.huge
	local pos, dir = car.CF.Position, car.CF.LookVector
	for _, other in ipairs(Traffic.Cars) do
		if other ~= car then
			local rel = other.CF.Position - pos
			local ahead = rel:Dot(dir)
			if ahead > 0 and ahead < 40 and math.abs(rel:Dot(right(dir))) < 2.6 then
				best = math.min(best, ahead - (car.Length + other.Length) / 2)
			end
		end
	end
	return best
end

local function intersectionBusy(car)
	for _, other in ipairs(Traffic.Cars) do
		if other ~= car and other.Phase == "turn" and other.A == car.A and other.B == car.B then
			return true
		end
	end
	return false
end

-- where a car stops: its front bumper behind the crosswalk (the stripes run
-- from 13.3 to 18.3 studs out from the middle of the intersection), never on it
local CROSS_NEAR, CROSS_FAR = ROAD / 2 - 0.5, ROAD / 2 + 6
local function stopGap(car)
	return (CROSS_FAR + 1) - (ROAD / 2 + 1) + car.Length / 2
end

-- anyone in a crosswalk of intersection (a, b): the one a car going `dir`
-- drives over on the way in (side -1) or on the way out (side 1). People
-- waiting on the curb don't count; people stepping off it do (Walkers has
-- where everyone will be in a moment, too).
local function crosswalkBusy(a, b, dir, side)
	local c = node(a, b)
	local r = right(dir)
	for _, p in ipairs(Traffic.Walkers) do
		local rel = p - c
		local along = rel:Dot(dir) * side
		if along > CROSS_NEAR and along < CROSS_FAR + 1 and math.abs(rel:Dot(r)) < ROAD / 2 - 0.2 and math.abs(rel.Y) < 8 then
			return true
		end
	end
	return false
end
Traffic.CrosswalkBusy = crosswalkBusy
Traffic.StopGap = stopGap

-- a driver waiting on you: the headlights flash
local function honk(car)
	if os.clock() < (car.NextHonk or 0) then
		return
	end
	car.NextHonk = os.clock() + 3
	car.Honked = os.clock()
	if Traffic.OnHonk then
		Traffic.OnHonk(car)
	end
end

local function drive(car, dt, camPos, night)
	-- how fast do we want to go?
	local want = car.Max
	local gap = gapAhead(car)
	if gap < 18 then
		want = math.min(want, math.max(0, (gap - 3) * 1.4))
	end
	local who = blocked(car, camPos)
	if who then
		want = 0
		if who == "you" then
			honk(car)
		end
	end
	if car.Phase == "turn" and car.Next and car.U < 0.75 and crosswalkBusy(car.A, car.B, car.Next, 1) then
		want = 0 -- waiting in the intersection for the people crossing
	end
	if car.Phase == "road" then
		local left = car.Len - car.S
		local gap = stopGap(car)
		-- red light (or someone already turning in an unlit intersection), or
		-- people in the crosswalk: stop at the line, behind the stripes
		if left < gap + 24 then
			local stop = false
			if left > gap - 1 then
				if hasLights(car.A, car.B) then
					stop = not green(car.Dir)
				else
					stop = intersectionBusy(car)
				end
				if not stop and (crosswalkBusy(car.A, car.B, car.Dir, -1) or (car.Planned and crosswalkBusy(car.A, car.B, car.Planned, 1))) then
					stop = true
					car.Yielding = true
				end
				-- don't block the crosswalk: if the car in front is waiting just
				-- past it, wait at the line until there's room on the other side
				if not stop and gapAhead(car) < (left - gap) + (CROSS_FAR - CROSS_NEAR) + 6 then
					stop = true
				end
			end
			if stop then
				want = math.min(want, math.max(0, (left - gap) * 1.3))
			else
				car.Yielding = nil
				if not hasLights(car.A, car.B) then
					want = math.min(want, 10) -- slow down for the crossing
				end
			end
		end
		-- buses pull up at their stops
		if car.Kind == "bus" then
			for k, p in ipairs(stops) do
				local rel = p - car.CF.Position
				local ahead = rel:Dot(car.Dir)
				if math.abs(rel:Dot(right(car.Dir))) < 2 and ahead > -1 and ahead < 18 and car.LastStop ~= k then
					want = math.min(want, math.max(0, ahead * 1.2))
					if ahead < 1.5 and car.Speed < 0.5 then
						car.LastStop = k
						car.HoldUntil = os.clock() + 4
					end
				end
			end
			if car.HoldUntil and os.clock() < car.HoldUntil then
				want = 0
			end
		end
	end
	-- decide the next turn early, so the blinker can go on
	if car.Phase == "road" and not car.Planned and car.Len - car.S < 40 then
		car.Planned = nextDir(car)
	end
	-- smooth acceleration and braking
	local accel = if want > car.Speed then 7 else 16
	local before = car.Speed
	car.Speed += math.clamp(want - car.Speed, -accel * dt, accel * dt)
	local step = car.Speed * dt
	car.Braking = car.Speed < before - 0.01 or (car.Speed < 0.3 and want < 0.3)
	car.Spin = ((car.Spin or 0) - step / (if car.Kind == "bus" then 1.5 else 1.2)) % (math.pi * 2)
	local turning = car.Planned or car.Next
	local blink = 0
	if turning then
		local r = right(car.Dir)
		local dot = turning:Dot(r)
		blink = if dot > 0.5 then 1 elseif dot < -0.5 then -1 else 0
	end
	car.Steer = if car.Phase == "turn" then -blink * 0.45 else 0
	if car.Phase == "road" then
		car.S += step
		if car.S >= car.Len then
			-- into the intersection: an arc to the next road
			local nd = car.Planned or nextDir(car)
			car.Planned = nil
			car.Next = nd
			car.Phase = "turn"
			car.U = 0
			car.P0 = entry(car.A, car.B, car.Dir)
			car.P2 = exit(car.A, car.B, nd)
			if nd:Dot(car.Dir) < -0.5 then
				car.P1 = node(car.A, car.B) + car.Dir * 4
			elseif nd:Dot(car.Dir) > 0.5 then
				car.P1 = (car.P0 + car.P2) / 2
			else
				-- where the two lanes cross
				local c = node(car.A, car.B)
				local laneIn = c + right(car.Dir) * LANE
				local laneOut = c + right(nd) * LANE
				car.P1 = Vector3.new(if math.abs(car.Dir.X) > 0.5 then laneOut.X else laneIn.X, 0, if math.abs(car.Dir.Z) > 0.5 then laneOut.Z else laneIn.Z)
			end
			car.TurnLen = (car.P1 - car.P0).Magnitude + (car.P2 - car.P1).Magnitude
		else
			local p = car.From + car.Dir * car.S
			place(car, CFrame.lookAt(p, p + car.Dir))
		end
	end
	if car.Phase == "turn" then
		car.U += step / math.max(1, car.TurnLen)
		if car.U >= 1 then
			-- out on the next road
			local nd = car.Next
			local na, nb = car.A + math.floor(nd.X + 0.5), car.B + math.floor(nd.Z + 0.5)
			car.From = exit(car.A, car.B, nd)
			car.A, car.B, car.Dir = na, nb, nd
			car.To = entry(na, nb, nd)
			car.Len = (car.To - car.From).Magnitude
			car.S = 0
			car.Next = nil
			car.Phase = "road"
			place(car, CFrame.lookAt(car.From, car.From + nd))
		else
			local u = car.U
			local p = car.P0 * (1 - u) ^ 2 + car.P1 * 2 * u * (1 - u) + car.P2 * u * u
			local d = (car.P1 - car.P0) * 2 * (1 - u) + (car.P2 - car.P1) * 2 * u
			if d.Magnitude < 0.01 then
				d = car.Dir
			end
			place(car, CFrame.lookAt(p, p + d.Unit))
		end
	end
	-- the headlights come on at night; brake lights and blinkers
	if car.Beam.Enabled ~= night then
		car.Beam.Enabled = night
	end
	lights(car, car.Braking, blink)
	car.Blink = blink
end

-- keep the right number of cars around the camera
local function populate(camPos)
	for k = #Traffic.Cars, 1, -1 do
		local car = Traffic.Cars[k]
		if (car.CF.Position - camPos).Magnitude > Traffic.Radius + 60 then
			despawn(car)
		end
	end
	local buses = 0
	for _, car in ipairs(Traffic.Cars) do
		if car.Kind == "bus" then
			buses += 1
		end
	end
	local tries = 0
	while #Traffic.Cars < Traffic.MaxCars and tries < 6 do
		tries += 1
		local a, b = rng:NextInteger(lo, hi), rng:NextInteger(lo, hi)
		local dir = DIRS[rng:NextInteger(1, 4)]
		local pa, pb = a - math.floor(dir.X + 0.5), b - math.floor(dir.Z + 0.5)
		if inGrid(pa, pb) then
			local s = rng:NextNumber(5, S - ROAD - 20)
			local from = exit(pa, pb, dir)
			local pos = from + dir * s
			local d = (pos - camPos).Magnitude
			local free = true
			-- (room for a bus: they're long)
			for _, other in ipairs(Traffic.Cars) do
				if (other.CF.Position - pos).Magnitude < (other.Length or 14) / 2 + 22 then
					free = false
					break
				end
			end
			if free and d < Traffic.Radius and d > 70 then
				local bus = buses < 2 and rng:NextNumber() < 0.3
				spawnCar(if bus then "bus" else "car", a, b, dir, s)
				if bus then
					buses += 1
				end
			end
		end
	end
end

function Traffic.Step(dt)
	local camera = workspace.CurrentCamera
	if not camera or not folder then
		return
	end
	local camPos = camera.CFrame.Position
	local h = Lighting.ClockTime
	local night = h >= 18.5 or h < 6.3
	-- where everyone on foot is (once a frame)
	local walkers = {}
	local now = os.clock()
	local seen = {}
	local function add(m, r)
		local pos = r.Position
		table.insert(walkers, pos)
		-- and where they'll be in a moment (so cars brake before someone
		-- steps off the curb, not after)
		local prev = walkerPrev[m]
		local vel = Vector3.zero
		if prev and now > prev.T then
			vel = prev.Vel:Lerp((pos - prev.Pos) / math.max(now - prev.T, 1 / 120), 0.3)
		end
		walkerPrev[m] = { Pos = pos, T = now, Vel = vel }
		seen[m] = true
		local flat = Vector3.new(vel.X, 0, vel.Z)
		if flat.Magnitude > 1.5 and flat.Magnitude < 40 then
			table.insert(walkers, pos + flat * 0.6)
			table.insert(walkers, pos + flat * 1.2)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged("Citizen")) do
		local r = m:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - camPos).Magnitude < 200 then
			add(m, r)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
		if r and not (hum and hum.SeatPart) and (r.Position - camPos).Magnitude < 200 then
			add(pl.Character, r)
		end
	end
	for m in pairs(walkerPrev) do
		if not seen[m] then
			walkerPrev[m] = nil
		end
	end
	Traffic.Walkers = walkers
	for _, car in ipairs(table.clone(Traffic.Cars)) do
		drive(car, dt, camPos, night)
	end
	populate(camPos)
end

function Traffic.Start()
	local info = ReplicatedStorage:FindFirstChild("CityInfo")
	if info then
		S = info:GetAttribute("Spacing") or S
		N = info:GetAttribute("Blocks") or N
		ROAD = info:GetAttribute("Road") or ROAD
		LANE = info:GetAttribute("Lane") or LANE
		local f = info:FindFirstChild("BusStops")
		if f then
			for _, v in ipairs(f:GetChildren()) do
				table.insert(stops, v.Value)
			end
		end
	end
	lo, hi = -N - 1, N
	folder = Instance.new("Folder")
	folder.Name = "LocalTraffic"
	folder.Parent = workspace
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(Traffic.Step, math.min(dt, 0.1))
		if not ok then
			warn("[Traffic] " .. tostring(err))
		end
	end)
end

return Traffic
