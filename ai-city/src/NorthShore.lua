-- NorthShore (ModuleScript) — ServerScriptService.Modules.NorthShore
-- A whole new district past the north edge of town, up Shore Drive:
--
--   🚗 AutoLand       a car dealership: cars on the lot you can buy (CarService)
--   🎡 Funland        an amusement park: a Ferris wheel, a carousel and a drop
--                     tower you can ride (they turn on everyone's screen, see
--                     the client's Rides module), Balloon Pop and the prize
--                     booth (FunService), a pet adoption stand (PetService),
--                     food carts, benches and string lights
--   🧗 Sky Obby       a parkour course: jumps, moving platforms, spinning bars,
--                     lava, checkpoints and a timer (FunService)
--   🏖️ Sunset Beach   a boardwalk, sand, umbrellas and towels, lounge chairs,
--                     picnic blankets, a fire pit, dunes, a jetty, kites, crabs,
--                     rolling surf, a volleyball
--                     net, a lifeguard tower, palm trees, and a long pier
--                     into the ocean for fishing
--
-- NorthShore.build(parent, rng) returns the spots for citizens (Funland, Beach,
-- AutoLand) and everything the services need.

local MapKit = require(script.Parent:WaitForChild("MapKit"))
local Streets = require(script.Parent:WaitForChild("Streets"))

local NorthShore = {}

local rgb, WHITE, BLACK = MapKit.rgb, MapKit.WHITE, MapKit.BLACK
local EXT, S, ROAD = MapKit.EXTENT, MapKit.SPACING, MapKit.ROAD
local Z0 = -EXT -- the city's north edge (the outer road runs along it)

NorthShore.DRIVE_X = 0.5 * S -- Shore Drive continues this avenue north
NorthShore.Z0 = Z0
NorthShore.BOARDWALK_Z = Z0 - 328
NorthShore.WATER_Z = Z0 - 430 -- where the ocean begins
-- the height of the sand: flat back by the boardwalk, sloping gently down to
-- the water, then on down under the waves (1 stud every ~9) to 16 deep. Only
-- with real terrain (Landscape shapes it); in tests the beach is flat.
NorthShore.Sloped = false
function NorthShore.BeachY(z)
	if not NorthShore.Sloped then
		return 0
	end
	local wz = NorthShore.WATER_Z
	if z >= wz + 30 then
		return 0
	elseif z >= wz then
		return -1.25 * (1 - (z - wz) / 30)
	end
	return math.max(-16, -1.25 - (wz - z) * 0.11)
end
local BY = NorthShore.BeachY
NorthShore.WEST, NorthShore.EAST = -460, 330
-- paved areas (Landscape clears the terrain grass under these)
NorthShore.PAVED = {
	{ Center = Vector3.new(NorthShore.DRIVE_X, 0, Z0 - 165), Size = Vector3.new(ROAD + 6, 0, 330) },
	{ Center = Vector3.new(150, 0, Z0 - 75), Size = Vector3.new(104, 0, 74) },
	{ Center = Vector3.new(-105, 0, Z0 - 170), Size = Vector3.new(294, 0, 264) },
	{ Center = Vector3.new(-355, 0, Z0 - 175), Size = Vector3.new(180, 0, 250) },
	{ Center = Vector3.new(-65, 0, NorthShore.BOARDWALK_Z), Size = Vector3.new(790, 0, 24) },
}

local model
local function cf(x, y, z)
	return CFrame.new(x, y, z)
end
local function solid(parent, name, size, x, y, z, color, material)
	return MapKit.part(parent, name, size, cf(x, y + size.Y / 2, z), color, material)
end
local function deco(parent, name, size, x, y, z, color, material)
	return MapKit.deco(parent, name, size, cf(x, y + size.Y / 2, z), color, material)
end
local function spot(x, y, z, fx, fz, extra)
	local p = Vector3.new(x, y, z)
	local look = Vector3.new(fx, y, fz)
	if (look - p).Magnitude < 0.1 then
		look = p + Vector3.new(0, 0, -1)
	end
	local s = { CFrame = CFrame.lookAt(p, look), Floor = 1, Role = "visit" }
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

local function lamp(parent, x, z, y)
	y = y or 0
	deco(parent, "LampPost", Vector3.new(0.5, 11, 0.5), x, y, z, rgb(40, 44, 50), Enum.Material.Metal)
	local head = MapKit.ball(parent, "LampGlobe", 1.6, cf(x, y + 11.6, z), rgb(255, 244, 214), Enum.Material.Neon)
	local l = MapKit.light(head, rgb(255, 225, 170), 26, 0.9)
	l.Enabled = false
	table.insert(MapKit.Registry.Lamps, { Head = head, Light = l })
end

local function palm(parent, x, z, rng, y)
	y = y or 0
	local h = rng:NextNumber(12, 17)
	local lean = rng:NextNumber(-0.12, 0.12)
	for k = 0, 5 do
		local u = k / 6
		MapKit.column(parent, "PalmTrunk", h / 6 + 0.4, 1.3 - u * 0.4, Vector3.new(x + lean * h * u * 3, y + h * u + h / 12, z), rgb(140, 110, 76):Lerp(rgb(110, 86, 60), k % 2), Enum.Material.Wood, false)
	end
	local top = Vector3.new(x + lean * h * 3, y + h + 0.4, z)
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2
		local frond = MapKit.deco(parent, "PalmFrond", Vector3.new(1.6, 0.3, 7), CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-22), 0, 0) * CFrame.new(0, 0, -3.2), rgb(60, 140, 60):Lerp(rgb(90, 160, 70), (k % 3) / 3), Enum.Material.SmoothPlastic)
		frond.CastShadow = true
	end
	MapKit.ball(parent, "Coconuts", 1.4, CFrame.new(top - Vector3.new(0, 0.6, 0)), rgb(110, 80, 50))
end

--------------------------------------------------------------------------------
-- Shore Drive
--------------------------------------------------------------------------------
local function drive(data)
	local x = NorthShore.DRIVE_X
	local z1, z2 = Z0 - ROAD / 2, NorthShore.BOARDWALK_Z + 12
	local len = z1 - z2
	MapKit.part(model, "ShoreDrive", Vector3.new(ROAD, 0.2, len), cf(x, 0, (z1 + z2) / 2), MapKit.ASPHALT, Enum.Material.Asphalt)
	for z = z1 - 6, z2 + 6, -11 do
		MapKit.deco(model, "LaneDash", Vector3.new(0.35, 0.22, 6), cf(x, 0.01, z), rgb(245, 205, 70))
	end
	for _, sx in ipairs({ -1, 1 }) do
		MapKit.part(model, "DriveSidewalk", Vector3.new(4, 0.5, len), cf(x + sx * (ROAD / 2 + 2), 0.25, (z1 + z2) / 2), MapKit.CONCRETE, Enum.Material.Pavement)
		for z = z1 - 20, z2 + 10, -44 do
			lamp(model, x + sx * (ROAD / 2 + 3.2), z, 0.5)
		end
	end
	local post = deco(model, "DriveSignPost", Vector3.new(0.4, 9, 0.4), x + ROAD / 2 + 5, 0, z1 - 8, rgb(60, 64, 70), Enum.Material.Metal)
	local sign = MapKit.deco(model, "DriveSign", Vector3.new(10, 3.4, 0.2), post.CFrame * CFrame.new(0, 3.5, 0), rgb(30, 110, 60))
	MapKit.signText(sign, Enum.NormalId.Back, "SHORE DRIVE ➜ Funland · Sunset Beach · AutoLand", WHITE, Enum.Font.GothamBold)
	MapKit.signText(sign, Enum.NormalId.Front, "⬅ AI CITY", WHITE, Enum.Font.GothamBold)
end

--------------------------------------------------------------------------------
-- 🚗 AutoLand
--------------------------------------------------------------------------------
local function autoland(data, rng)
	local m = Instance.new("Model")
	m.Name = "AutoLand"
	m.Parent = model
	local c = Vector3.new(150, 0, Z0 - 75)
	MapKit.part(m, "Lot", Vector3.new(104, 0.3, 74), cf(c.X, 0.15, c.Z), rgb(64, 66, 72), Enum.Material.Asphalt)
	for k = -4, 4 do
		deco(m, "LotLine", Vector3.new(0.3, 0.02, 10), c.X + k * 10, 0.3, c.Z + 8, WHITE)
	end
	-- the showroom: a glass box with a sign on the roof
	local sx, sz = c.X + 28, c.Z - 22
	solid(m, "ShowroomFloor", Vector3.new(40, 0.4, 24), sx, 0.3, sz, rgb(230, 230, 232), Enum.Material.Marble)
	for _, e in ipairs({ { 0, -12 }, { 0, 12 }, { -20, 0 }, { 20, 0 } }) do
		local size = if e[1] == 0 then Vector3.new(40, 12, 0.4) else Vector3.new(0.4, 12, 24)
		local g = solid(m, "ShowroomGlass", size, sx + e[1], 0.7, sz + e[2], rgb(170, 210, 235), Enum.Material.Glass)
		g.Transparency = 0.55
		if e[2] == 12 then
			g.CanCollide = false -- (the way in, facing the lot)
		end
	end
	solid(m, "ShowroomRoof", Vector3.new(42, 1, 26), sx, 12.7, sz, rgb(40, 44, 52), Enum.Material.Metal)
	local sign = deco(m, "AutoLandSign", Vector3.new(26, 5, 0.6), sx, 13.7, sz + 10, rgb(210, 40, 40))
	MapKit.signText(sign, Enum.NormalId.Back, "🚗 AUTOLAND", WHITE, Enum.Font.GothamBlack)
	MapKit.signText(sign, Enum.NormalId.Front, "🚗 AUTOLAND", WHITE, Enum.Font.GothamBlack)
	local desk = solid(m, "SalesDesk", Vector3.new(6, 3, 2.4), sx - 6, 0.7, sz, rgb(250, 250, 250), Enum.Material.SmoothPlastic)
	data.SalesDesk = desk
	data.SalesSpot = spot(sx - 6, 0.7, sz - 2.4, sx - 6, sz + 4)
	-- bunting and balloons on the lot
	for k = 0, 6 do
		local b = MapKit.ball(m, "LotBalloon", 2.4, cf(c.X - 48 + k * 3, 9 + (k % 2), c.Z + 36), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1])
		deco(m, "BalloonString", Vector3.new(0.08, 9 + (k % 2) - 1.2 - 0.3 + 0.1, 0.08), c.X - 48 + k * 3, 0.3, c.Z + 36, WHITE)
		b.Reflectance = 0.2
	end
	-- the cars for sale stand in a row facing the drive (CarService fills them)
	data.Display = {}
	for k = 0, 4 do
		local p = Vector3.new(c.X - 40 + k * 17, 0.3, c.Z + 14)
		MapKit.disc(m, "Turntable", 0.2, 13, p, rgb(200, 200, 205), Enum.Material.Metal)
		table.insert(data.Display, CFrame.lookAt(p, p + Vector3.new(-1, 0, 0.35)))
	end
	-- where your new car is waiting when you drive off the lot
	data.Pickup = CFrame.lookAt(Vector3.new(NorthShore.DRIVE_X + 3.4, 0.1, c.Z + 10), Vector3.new(NorthShore.DRIVE_X + 3.4, 0.1, Z0))
	data.AutoLandSpots = {}
	for k = 0, 4 do
		local p = data.Display[k + 1].Position
		table.insert(data.AutoLandSpots, spot(p.X + 4, 0.3, p.Z + 7, p.X, p.Z, { Action = "browse" }))
	end
	data.AutoLandDoor = Vector3.new(NorthShore.DRIVE_X + ROAD / 2 + 4, 0.5, c.Z)
end

--------------------------------------------------------------------------------
-- 🎡 Funland
--------------------------------------------------------------------------------
local rideSeatN = 0
local function rideSeat(parent, cframe, color, spots, extra)
	rideSeatN += 1
	local seat = MapKit.seat(parent, "RideSeat_" .. rideSeatN, Vector3.new(2, 0.4, 2), cframe, color or rgb(220, 60, 60), Enum.Material.SmoothPlastic, nil)
	seat.CanCollide = false
	local s = { CFrame = cframe - Vector3.new(0, 1.7, 0), Seat = seat, Action = "ride", Role = "visit", Floor = 1, RideSeat = seat.Name }
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	table.insert(spots, s)
	return seat
end

-- The Ferris wheel. The rim and spokes turn as one piece; the gondolas hang
-- straight down as they go round (the client's Rides module moves them).
local function ferrisWheel(parent, hub, spots)
	local ride = Instance.new("Model")
	ride.Name = "FerrisWheel"
	ride.Parent = parent
	ride:SetAttribute("Kind", "wheel")
	ride:SetAttribute("Hub", hub)
	ride:SetAttribute("Axis", Vector3.new(1, 0, 0))
	ride:SetAttribute("Speed", 0.11)
	local R = 30
	-- the A-frame legs (they don't move)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local foot = hub + Vector3.new(sx * 6, -hub.Y, sz * 18)
			local top = hub + Vector3.new(sx * 3, 0, 0)
			local mid, len = (foot + top) / 2, (top - foot).Magnitude
			MapKit.deco(parent, "WheelLeg", Vector3.new(1.2, len, 1.2), CFrame.lookAt(mid, top) * CFrame.Angles(math.rad(90), 0, 0), rgb(240, 240, 245), Enum.Material.Metal)
		end
	end
	MapKit.cylinder(parent, "WheelAxle", 8, 2.4, CFrame.new(hub), rgb(90, 90, 96), Enum.Material.Metal)
	local function spin(p)
		p:SetAttribute("Spin", true)
		p.Parent = ride
	end
	-- the rim: two rings of segments with lights, and the spokes
	local n = 24
	for _, off in ipairs({ -1.6, 1.6 }) do
		for k = 0, n - 1 do
			local a0, a1 = k / n * math.pi * 2, (k + 1) / n * math.pi * 2
			local p0 = hub + Vector3.new(off, math.cos(a0) * R, math.sin(a0) * R)
			local p1 = hub + Vector3.new(off, math.cos(a1) * R, math.sin(a1) * R)
			local seg = MapKit.deco(ride, "Rim", Vector3.new(0.8, 0.8, (p1 - p0).Magnitude + 0.3), CFrame.lookAt((p0 + p1) / 2, p1), rgb(240, 240, 245), Enum.Material.Metal)
			spin(seg)
			if k % 2 == 0 then
				local bulb = MapKit.ball(ride, "RimLight", 0.7, CFrame.new(p0 + Vector3.new(off * 0.3, 0, 0)), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.Neon)
				spin(bulb)
			end
		end
	end
	local g = 12
	for k = 0, g - 1 do
		local a = k / g * math.pi * 2
		local tip = hub + Vector3.new(0, math.cos(a) * R, math.sin(a) * R)
		for _, off in ipairs({ -1.6, 1.6 }) do
			local base = hub + Vector3.new(off, 0, 0)
			local t2 = tip + Vector3.new(off, 0, 0)
			spin(MapKit.deco(ride, "Spoke", Vector3.new(0.4, 0.4, R), CFrame.lookAt((base + t2) / 2, t2), rgb(220, 220, 228), Enum.Material.Metal))
		end
		-- a gondola hanging from the rim
		local color = MapKit.FLOWERS[k % #MapKit.FLOWERS + 1]
		local pivot = tip
		local parts = {}
		table.insert(parts, MapKit.deco(ride, "GondolaFloor", Vector3.new(4.6, 0.4, 4.6), CFrame.new(pivot - Vector3.new(0, 5.2, 0)), color, Enum.Material.SmoothPlastic))
		table.insert(parts, MapKit.deco(ride, "GondolaRoof", Vector3.new(5, 0.5, 5), CFrame.new(pivot - Vector3.new(0, 0.6, 0)), color:Lerp(WHITE, 0.2), Enum.Material.SmoothPlastic))
		table.insert(parts, MapKit.deco(ride, "GondolaHanger", Vector3.new(0.3, 1, 0.3), CFrame.new(pivot - Vector3.new(0, 0.2, 0)), rgb(90, 90, 96), Enum.Material.Metal))
		for _, sz in ipairs({ -1, 1 }) do
			table.insert(parts, MapKit.deco(ride, "GondolaSide", Vector3.new(4.6, 1.6, 0.3), CFrame.new(pivot + Vector3.new(0, -4.2, sz * 2.2)), color, Enum.Material.SmoothPlastic))
			for _, sx in ipairs({ -1, 1 }) do
				table.insert(parts, MapKit.deco(ride, "GondolaPost", Vector3.new(0.25, 4.2, 0.25), CFrame.new(pivot + Vector3.new(sx * 2.1, -2.8, sz * 2.1)), rgb(230, 230, 236), Enum.Material.Metal))
			end
		end
		for _, sz in ipairs({ -1, 1 }) do
			local seatCf = CFrame.lookAt(pivot + Vector3.new(0, -4.8, sz * 1.2), pivot + Vector3.new(0, -4.8, -sz * 3))
			table.insert(parts, rideSeat(ride, seatCf, color:Lerp(BLACK, 0.2), spots, { Approach = hub + Vector3.new(9, -hub.Y + 0.3, -8 + k % 4 * 4), RideKind = "wheel" }))
		end
		for _, p in ipairs(parts) do
			p:SetAttribute("Gondola", k)
			p:SetAttribute("Pivot", pivot)
			p.Parent = ride
		end
	end
	-- a ticket sign and a line to wait in
	local sign = deco(parent, "RideSign", Vector3.new(10, 3, 0.3), hub.X + 10, 6, hub.Z - 22, rgb(40, 60, 140))
	for _, px in ipairs({ -4.2, 4.2 }) do
		deco(parent, "SignPost", Vector3.new(0.4, 7.5, 0.4), hub.X + 10 + px, 0, hub.Z - 22.35, rgb(60, 64, 70))
	end
	MapKit.signText(sign, Enum.NormalId.Front, "🎡 SKY WHEEL", WHITE, Enum.Font.GothamBlack)
	MapKit.signText(sign, Enum.NormalId.Back, "🎡 SKY WHEEL", WHITE, Enum.Font.GothamBlack)
	MapKit.tag(ride, "Ride")
	return ride
end

-- The carousel: the floor, the poles and the horses go round; the horses bob
local function carousel(parent, c, spots)
	local ride = Instance.new("Model")
	ride.Name = "Carousel"
	ride.Parent = parent
	ride:SetAttribute("Kind", "spin")
	ride:SetAttribute("Hub", c)
	ride:SetAttribute("Axis", Vector3.new(0, 1, 0))
	ride:SetAttribute("Speed", 0.45)
	-- the base and the roof (still)
	MapKit.disc(parent, "CarouselBase", 1.2, 34, c + Vector3.new(0, 0.6, 0), rgb(200, 60, 80), Enum.Material.SmoothPlastic).CanCollide = false
	MapKit.column(parent, "CarouselCenter", 16, 5, c + Vector3.new(0, 8, 0), rgb(250, 220, 120), Enum.Material.SmoothPlastic, false)
	MapKit.disc(parent, "CarouselRoof", 1.2, 36, c + Vector3.new(0, 15.6, 0), rgb(250, 240, 230), Enum.Material.SmoothPlastic)
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * 17.5, 15, math.sin(a) * 17.5)
		MapKit.wedge(parent, "RoofScallop", Vector3.new(0.3, 1.6, 6.8), CFrame.lookAt(p, c + Vector3.new(0, 15, 0)) * CFrame.Angles(0, math.rad(90), math.rad(180)), if k % 2 == 0 then rgb(220, 60, 80) else WHITE, Enum.Material.SmoothPlastic)
		MapKit.ball(parent, "RoofBulb", 0.6, CFrame.new(c + Vector3.new(math.cos(a) * 18, 14.6, math.sin(a) * 18)), rgb(255, 240, 180), Enum.Material.Neon)
	end
	local floor = MapKit.deco(ride, "CarouselFloor", Vector3.new(0.4, 32, 32), CFrame.new(c + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(240, 230, 200), Enum.Material.Wood)
	floor.Shape = Enum.PartType.Cylinder
	floor:SetAttribute("Spin", true)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		local r = if k % 2 == 0 then 12 else 8
		local p = c + Vector3.new(math.cos(a) * r, 1.6, math.sin(a) * r)
		local pole = MapKit.deco(ride, "CarouselPole", Vector3.new(0.3, 13, 0.3), CFrame.new(p + Vector3.new(0, 6.5, 0)), MapKit.GOLD, Enum.Material.Metal)
		pole:SetAttribute("Spin", true)
		-- a horse facing along the direction of travel
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local base = CFrame.lookAt(p + Vector3.new(0, 3.2, 0), p + Vector3.new(0, 3.2, 0) + tangent)
		local color = ({ WHITE, rgb(120, 80, 50), rgb(40, 40, 44), rgb(210, 170, 120) })[k % 4 + 1]
		local parts = {
			MapKit.deco(ride, "HorseBody", Vector3.new(1.6, 1.8, 4), base, color, Enum.Material.SmoothPlastic),
			MapKit.deco(ride, "HorseNeck", Vector3.new(1, 2.2, 1.2), base * CFrame.new(0, 1.3, -1.9) * CFrame.Angles(math.rad(-25), 0, 0), color, Enum.Material.SmoothPlastic),
			MapKit.deco(ride, "HorseHead", Vector3.new(1, 1, 2), base * CFrame.new(0, 2.4, -2.8), color, Enum.Material.SmoothPlastic),
			MapKit.deco(ride, "HorseMane", Vector3.new(0.4, 1.8, 1.4), base * CFrame.new(0, 1.8, -1.5), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.SmoothPlastic),
		}
		for _, sx in ipairs({ -0.5, 0.5 }) do
			for _, sz in ipairs({ -1.4, 1.4 }) do
				table.insert(parts, MapKit.deco(ride, "HorseLeg", Vector3.new(0.4, 1.8, 0.4), base * CFrame.new(sx, -1.5, sz) * CFrame.Angles(math.rad(sz * 12), 0, 0), color, Enum.Material.SmoothPlastic))
			end
		end
		table.insert(parts, rideSeat(ride, base * CFrame.new(0, 1.1, 0.2), MapKit.FLOWERS[(k + 2) % #MapKit.FLOWERS + 1], spots, { Approach = c + Vector3.new(math.cos(a) * 19, 0, math.sin(a) * 19), RideKind = "spin" }))
		for _, part in ipairs(parts) do
			part:SetAttribute("Spin", true)
			part:SetAttribute("Bob", 0.9)
			part:SetAttribute("BobPhase", k * 1.1)
		end
	end
	local sign = deco(parent, "RideSign", Vector3.new(12, 2.6, 0.3), c.X, 16.2, c.Z + 17.8, rgb(200, 60, 80))
	MapKit.signText(sign, Enum.NormalId.Back, "🎠 CAROUSEL", WHITE, Enum.Font.GothamBlack)
	MapKit.signText(sign, Enum.NormalId.Front, "🎠 CAROUSEL", WHITE, Enum.Font.GothamBlack)
	MapKit.tag(ride, "Ride")
	return ride
end

-- The drop tower: the ring of seats climbs slowly... and falls
local function dropTower(parent, c, spots)
	local ride = Instance.new("Model")
	ride.Name = "DropTower"
	ride.Parent = parent
	ride:SetAttribute("Kind", "drop")
	ride:SetAttribute("Hub", c)
	ride:SetAttribute("Height", 62)
	local H = 78
	MapKit.column(parent, "TowerColumn", H, 5, c + Vector3.new(0, H / 2, 0), rgb(60, 70, 110), Enum.Material.Metal, false)
	MapKit.disc(parent, "TowerBase", 1, 20, c + Vector3.new(0, 0.5, 0), rgb(90, 90, 96), Enum.Material.Concrete).CanCollide = false
	MapKit.ball(parent, "TowerTop", 6, CFrame.new(c + Vector3.new(0, H + 1, 0)), rgb(250, 200, 40), Enum.Material.SmoothPlastic)
	for k = 1, 8 do
		MapKit.ball(parent, "TowerLight", 0.8, CFrame.new(c + Vector3.new(2.6, k * 9, 0)), rgb(255, 120, 60), Enum.Material.Neon)
	end
	local ring = MapKit.deco(ride, "DropRing", Vector3.new(1.6, 14, 14), CFrame.new(c + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(250, 200, 40), Enum.Material.SmoothPlastic)
	ring.Shape = Enum.PartType.Cylinder
	ring:SetAttribute("Lift", true)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = c + out * 5.4 + Vector3.new(0, 3.9, 0)
		local seat = rideSeat(ride, CFrame.lookAt(p, p + out), rgb(220, 40, 60), spots, { Approach = c + out * 12, RideKind = "drop" })
		seat:SetAttribute("Lift", true)
		local back = MapKit.deco(ride, "DropSeatBack", Vector3.new(2, 2.4, 0.4), CFrame.lookAt(p, p + out) * CFrame.new(0, 1.3, 1), rgb(40, 40, 50), Enum.Material.SmoothPlastic)
		back:SetAttribute("Lift", true)
	end
	local sign = deco(parent, "RideSign", Vector3.new(12, 2.6, 0.3), c.X, 4, c.Z + 11, rgb(60, 70, 110))
	for _, px in ipairs({ -5.2, 5.2 }) do
		deco(parent, "SignPost", Vector3.new(0.4, 5.2, 0.4), c.X + px, 0, c.Z + 11.35, rgb(60, 64, 70))
	end
	MapKit.signText(sign, Enum.NormalId.Back, "🎢 FREEFALL", WHITE, Enum.Font.GothamBlack)
	MapKit.signText(sign, Enum.NormalId.Front, "🎢 FREEFALL", WHITE, Enum.Font.GothamBlack)
	MapKit.tag(ride, "Ride")
	return ride
end

local function booth(parent, x, z, title, color)
	solid(parent, "BoothCounter", Vector3.new(12, 3.4, 2), x, 0.3, z, color, Enum.Material.Wood)
	solid(parent, "BoothBack", Vector3.new(12, 10, 0.6), x, 0.3, z - 6, color:Lerp(WHITE, 0.4), Enum.Material.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		deco(parent, "BoothPost", Vector3.new(0.6, 11, 0.6), x + sx * 5.7, 0.3, z, color:Lerp(BLACK, 0.2), Enum.Material.Wood)
		deco(parent, "BoothSide", Vector3.new(0.4, 10, 6), x + sx * 6, 0.3, z - 3, color:Lerp(WHITE, 0.2), Enum.Material.Wood)
	end
	for k = 0, 5 do
		MapKit.wedge(parent, "Awning", Vector3.new(2, 1.2, 7), cf(x - 5 + k * 2, 11.9, z - 2.5) * CFrame.Angles(0, math.pi, 0), if k % 2 == 0 then color else WHITE, Enum.Material.Fabric)
	end
	local sign = deco(parent, "BoothSign", Vector3.new(12, 2.4, 0.3), x, 12.6, z + 0.9, rgb(30, 30, 40))
	MapKit.signText(sign, Enum.NormalId.Back, title, rgb(255, 220, 90), Enum.Font.GothamBlack)
	MapKit.signText(sign, Enum.NormalId.Front, title, rgb(255, 220, 90), Enum.Font.GothamBlack)
end

local function funland(data, rng)
	local m = Instance.new("Model")
	m.Name = "Funland"
	m.Parent = model
	local spots = {}
	data.FunlandSpots = spots
	local c = Vector3.new(-105, 0, Z0 - 170)
	MapKit.part(m, "FunlandGround", Vector3.new(294, 0.3, 264), cf(c.X, 0.15, c.Z), rgb(214, 196, 164), Enum.Material.Concrete)
	-- colored paths
	deco(m, "FunPath", Vector3.new(290, 0.04, 8), c.X, 0.3, c.Z, rgb(220, 120, 110), Enum.Material.Concrete)
	deco(m, "FunPath", Vector3.new(8, 0.04, 260), c.X + 60, 0.3, c.Z, rgb(220, 120, 110), Enum.Material.Concrete)
	-- the entrance arch facing Shore Drive
	local ax = 40
	for _, sz in ipairs({ -1, 1 }) do
		MapKit.column(m, "ArchPillar", 20, 3, Vector3.new(ax, 10.3, c.Z + sz * 10), rgb(250, 200, 60), Enum.Material.SmoothPlastic)
		MapKit.ball(m, "ArchBall", 4, cf(ax, 21.5, c.Z + sz * 10), rgb(220, 60, 80), Enum.Material.SmoothPlastic)
	end
	local arch = solid(m, "ArchSign", Vector3.new(1.2, 5, 22), ax, 15, c.Z, rgb(220, 60, 80), Enum.Material.SmoothPlastic)
	MapKit.signText(arch, Enum.NormalId.Right, "🎡 FUNLAND", WHITE, Enum.Font.GothamBlack)
	MapKit.signText(arch, Enum.NormalId.Left, "🎡 FUNLAND", WHITE, Enum.Font.GothamBlack)
	data.FunlandDoor = Vector3.new(ax + 6, 0.3, c.Z)
	-- the rides
	data.Rides = {
		ferrisWheel(m, Vector3.new(-190, 36, Z0 - 240), spots),
		carousel(m, Vector3.new(-60, 0.3, Z0 - 100), spots),
		dropTower(m, Vector3.new(-200, 0.3, Z0 - 90), spots),
	}
	-- people waiting in line and watching
	for _, p in ipairs({ { -170, Z0 - 210, -190, Z0 - 240 }, { -60, Z0 - 124, -60, Z0 - 100 }, { -186, Z0 - 104, -200, Z0 - 90 }, { -40, Z0 - 128, -60, Z0 - 100 } }) do
		for k = 0, 2 do
			table.insert(spots, spot(p[1] + k * 2.2, 0.3, p[2], p[3], p[4], { Action = if k == 2 then "phone" else "wait" }))
		end
	end
	-- 🎈 Balloon Pop: 8 balloons pinned to the back wall (FunService blows them up)
	local bx, bz = -10, Z0 - 220
	booth(m, bx, bz, "🎈 BALLOON POP", rgb(40, 150, 220))
	data.BalloonGame = { Counter = Vector3.new(bx, 0.3, bz + 2.5), Slots = {} }
	for row = 0, 1 do
		for k = 0, 3 do
			table.insert(data.BalloonGame.Slots, Vector3.new(bx - 3.6 + k * 2.4, 4.6 + row * 3.2, bz - 5.3))
		end
	end
	data.BalloonGame.Prompt = solid(m, "BalloonGamePrompt", Vector3.new(2, 0.6, 1), bx + 4, 3.7, bz, rgb(250, 250, 250))
	-- 🎟️ the prize booth: plushies on the shelves
	local px, pz = -10, Z0 - 256
	booth(m, px, pz, "🎟️ PRIZES", rgb(200, 70, 150))
	for row = 0, 2 do
		deco(m, "PrizeShelf", Vector3.new(11, 0.3, 1.2), px, 3.4 + row * 2.6, pz - 5.2, rgb(240, 230, 210), Enum.Material.Wood)
		for k = 0, 4 do
			MapKit.ball(m, "Plushie", 1.6, cf(px - 4 + k * 2, 4.4 + row * 2.6, pz - 5.2), MapKit.FLOWERS[(k + row) % #MapKit.FLOWERS + 1], Enum.Material.Fabric)
		end
	end
	data.PrizeDesk = solid(m, "PrizeDesk", Vector3.new(2, 0.6, 1), px + 4, 3.7, pz, rgb(250, 250, 250))
	-- 🐾 the pet adoption stand (PetService)
	local ax2, az2 = 10, Z0 - 60
	booth(m, ax2, az2, "🐾 PAWS & CLAWS", rgb(90, 170, 90))
	for k = 0, 2 do
		deco(m, "PetPen", Vector3.new(4, 1.6, 4), ax2 - 16 + k * 5, 0.3, az2 - 2, rgb(200, 170, 120), Enum.Material.Wood)
	end
	data.PetDesk = solid(m, "AdoptDesk", Vector3.new(2, 0.6, 1), ax2 + 4, 3.7, az2, rgb(250, 250, 250))
	data.PetPens = { Vector3.new(ax2 - 16, 0.3, az2 - 2), Vector3.new(ax2 - 11, 0.3, az2 - 2), Vector3.new(ax2 - 6, 0.3, az2 - 2) }
	-- food carts (cotton candy, ice cream, hot dogs) and picnic tables
	for k, cart in ipairs({ { -40, Z0 - 160, "🍭", rgb(250, 150, 200) }, { -120, Z0 - 160, "🍦", rgb(120, 200, 240) }, { -150, Z0 - 290, "🌭", rgb(240, 180, 60) } }) do
		solid(m, "FoodCart", Vector3.new(6, 3.6, 3), cart[1], 0.3, cart[2], cart[4], Enum.Material.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			MapKit.cylinder(m, "CartWheel", 0.4, 2, cf(cart[1] + sx * 2, 1.2, cart[2] + 1.6) * CFrame.Angles(0, math.rad(90), 0), rgb(40, 40, 44), Enum.Material.Rubber)
		end
		deco(m, "CartUmbrellaPole", Vector3.new(0.3, 5, 0.3), cart[1], 3.9, cart[2], rgb(220, 220, 220), Enum.Material.Metal)
		MapKit.disc(m, "CartUmbrella", 0.3, 8, Vector3.new(cart[1], 9, cart[2]), cart[4]:Lerp(WHITE, 0.3), Enum.Material.Fabric)
		local sign = deco(m, "CartSign", Vector3.new(4, 1.6, 0.2), cart[1], 4, cart[2] + 1.6, WHITE)
		MapKit.signText(sign, Enum.NormalId.Back, cart[3], BLACK)
		table.insert(spots, spot(cart[1], 0.3, cart[2] + 4, cart[1], cart[2], { Action = "wait" }))
		table.insert(spots, spot(cart[1] + 2.2, 0.3, cart[2] + 5.5, cart[1], cart[2], { Action = "phone" }))
	end
	for k = 0, 5 do
		local tx, tz = -150 + (k % 3) * 22, Z0 - 150 - math.floor(k / 3) * 14
		deco(m, "PicnicTable", Vector3.new(6, 0.4, 3), tx, 2.7, tz, rgb(150, 110, 70), Enum.Material.Wood)
		deco(m, "PicnicLeg", Vector3.new(4, 2.4, 1), tx, 0.3, tz, rgb(120, 90, 60), Enum.Material.Wood)
		for _, sz in ipairs({ -1, 1 }) do
			local seat = MapKit.seat(m, "PicnicBench", Vector3.new(6, 0.4, 1.2), cf(tx, 1.9, tz + sz * 2.2), rgb(150, 110, 70), Enum.Material.Wood, nil)
			for _, lx in ipairs({ -2.5, 2.5 }) do
				deco(m, "BenchLeg", Vector3.new(0.4, 1.5, 1), tx + lx, 0.25, tz + sz * 2.2, rgb(120, 86, 56), Enum.Material.Wood)
			end
			seat.CanCollide = false
			for _, dx in ipairs({ -1.5, 1.5 }) do
				table.insert(spots, spot(tx + dx, 0.3, tz + sz * 2.2, tx + dx, tz, { Action = "eat", Seat = seat }))
			end
		end
	end
	-- string lights over the main path, lamps and flower beds
	-- (on a wire between two poles; each bulb hangs on a short drop)
	for k = 0, 17 do
		local x = c.X - 136 + k * 16
		local y = 9 + math.sin(k) * 0.4
		MapKit.ball(m, "StringLight", 0.7, cf(x, y, c.Z), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.Neon)
		MapKit.deco(m, "LightDrop", Vector3.new(0.06, 10.2 - y, 0.06), cf(x, (y + 10.2) / 2, c.Z), rgb(40, 40, 44))
	end
	MapKit.deco(m, "LightWire", Vector3.new(284, 0.08, 0.08), cf(c.X - 0.5, 10.2, c.Z), rgb(40, 40, 44))
	for _, ex in ipairs({ -142, 141 }) do
		deco(m, "LightPole", Vector3.new(0.5, 10.6, 0.5), c.X + ex, 0, c.Z, rgb(60, 64, 70), Enum.Material.Metal)
	end
	for k = 0, 8 do
		lamp(m, c.X - 128 + k * 32, c.Z + 6, 0.3)
		lamp(m, c.X - 128 + k * 32, c.Z - 6, 0.3)
	end
	for k = 0, 5 do
		local tx = c.X - 130 + k * 50
		for _, sz in ipairs({ -1, 1 }) do
			Streets.tree(m, Vector3.new(tx, 0.3, c.Z + sz * 126), rng:NextNumber(0.8, 1.1), rng)
		end
	end
end

--------------------------------------------------------------------------------
-- 🧗 The Sky Obby
--------------------------------------------------------------------------------
local function obby(data, rng)
	local m = Instance.new("Model")
	m.Name = "SkyObby"
	m.Parent = model
	local o = { Checkpoints = {}, Kill = {}, Region = { Min = Vector3.new(-450, -5, Z0 - 300), Max = Vector3.new(-260, 90, Z0 - 50) } }
	data.Obby = o
	local c = Vector3.new(-355, 0, Z0 - 175)
	MapKit.part(m, "ObbyGround", Vector3.new(180, 0.3, 250), cf(c.X, 0.15, c.Z), rgb(90, 160, 90), Enum.Material.Grass)
	local start = solid(m, "ObbyStart", Vector3.new(14, 1, 14), -280, 0.3, Z0 - 70, rgb(60, 200, 90), Enum.Material.SmoothPlastic)
	o.Start = start
	local sign = deco(m, "ObbySign", Vector3.new(16, 4, 0.4), -280, 8, Z0 - 62, rgb(30, 34, 60))
	MapKit.signText(sign, Enum.NormalId.Front, "🧗 SKY OBBY\nStep on the green pad to start", WHITE, Enum.Font.GothamBlack)
	MapKit.signText(sign, Enum.NormalId.Back, "🧗 SKY OBBY", WHITE, Enum.Font.GothamBlack)
	o.Board = deco(m, "ObbyBoard", Vector3.new(14, 9, 0.4), -266, 0.3, Z0 - 62, rgb(20, 24, 40))
	-- a path of jumps that climbs as it goes (west, then back east higher up)
	local y, x, z = 1.3, -280, Z0 - 78
	local colors = { rgb(255, 90, 110), rgb(255, 200, 60), rgb(90, 170, 255), rgb(170, 110, 255), rgb(90, 220, 140) }
	local step = 0
	local function platform(size, px, py, pz, kind)
		step += 1
		local p = solid(m, "ObbyPlatform", size, px, py, pz, colors[step % #colors + 1], Enum.Material.SmoothPlastic)
		if kind == "lava" then
			local lava = solid(m, "ObbyLava", Vector3.new(size.X - 1, 0.3, 2), px, py + size.Y, pz, rgb(255, 70, 30), Enum.Material.Neon)
			table.insert(o.Kill, lava)
			MapKit.tag(lava, "ObbyKill")
		elseif kind == "move" then
			p:SetAttribute("MoveAxis", Vector3.new(1, 0, 0))
			p:SetAttribute("MoveDist", 7)
			p:SetAttribute("MoveSpeed", 0.8)
			MapKit.tag(p, "ObbyMover")
		elseif kind == "spin" then
			local bar = solid(m, "ObbySpinner", Vector3.new(size.X - 1, 0.8, 0.8), px, py + size.Y + 1.2, pz, rgb(255, 70, 30), Enum.Material.Neon)
			bar.CanCollide = false
			bar:SetAttribute("SpinSpeed", 1.6)
			MapKit.tag(bar, "ObbySpinner")
			table.insert(o.Kill, bar)
			MapKit.tag(bar, "ObbyKill")
		end
		return p
	end
	local course = {
		{ 0, 0, -9, 6, "" }, { 0, 1, -8, 5, "" }, { 0, 1.2, -8, 4, "" }, { -8, 1, 0, 4, "" }, { -8, 0.8, 0, 6, "lava" },
		{ -9, 1, 0, 4, "" }, { "cp" }, { -10, 0, 0, 5, "move" }, { -10, 0, 0, 5, "move" }, { -8, 1.2, 0, 4, "" },
		{ 0, 1.2, -8, 3, "" }, { 0, 1.2, -8, 3, "" }, { 0, 0.5, -10, 8, "spin" }, { "cp" }, { 9, 1.4, 0, 3.4, "" },
		{ 9, 1.4, 0, 3.4, "" }, { 9, 1, 0, 6, "lava" }, { 9, 0, 0, 5, "move" }, { 8, 1.4, 0, 3, "" }, { "cp" },
		{ 0, 1.6, -9, 3, "" }, { 0, 1.6, -9, 3, "" }, { 0, 0, -11, 8, "spin" }, { -9, 1.6, 0, 2.6, "" }, { -9, 1.6, 0, 2.6, "" },
		{ -10, 0, 0, 5, "move" }, { -9, 1.8, 0, 3, "" }, { "finish" },
	}
	for _, c2 in ipairs(course) do
		if c2[1] == "cp" then
			z -= 9
			y += 0.4
			local cp = solid(m, "ObbyCheckpoint", Vector3.new(8, 1, 8), x, y, z, rgb(250, 220, 60), Enum.Material.Neon)
			cp:SetAttribute("Checkpoint", #o.Checkpoints + 1)
			table.insert(o.Checkpoints, cp)
			local flag = deco(m, "CheckpointFlag", Vector3.new(0.3, 6, 0.3), x + 3, y + 1, z, WHITE, Enum.Material.Metal)
			deco(m, "CheckpointBanner", Vector3.new(0.1, 1.6, 2.4), x + 3, y + 5.2, z + 1.2, rgb(250, 220, 60))
		elseif c2[1] == "finish" then
			z -= 10
			y += 0.4
			local fin = solid(m, "ObbyFinish", Vector3.new(12, 1, 12), x, y, z - 2, rgb(80, 220, 255), Enum.Material.Neon)
			o.Finish = fin
			local arch = deco(m, "FinishArch", Vector3.new(12, 2, 0.6), x, y + 8, z - 8, rgb(30, 34, 60))
			MapKit.signText(arch, Enum.NormalId.Back, "🏁 FINISH", WHITE, Enum.Font.GothamBlack)
			for _, sx in ipairs({ -1, 1 }) do
				deco(m, "FinishPost", Vector3.new(0.6, 9, 0.6), x + sx * 6, y + 1, z - 8, WHITE, Enum.Material.Metal)
			end
		else
			x += c2[1]
			y += c2[2]
			z += c2[3]
			local w = c2[4]
			platform(Vector3.new(w, 1, w), x, y, z, c2[5])
		end
	end
	-- supports down to the ground so it doesn't hang in the air
	for _, p in ipairs(m:GetChildren()) do
		if (p.Name == "ObbyPlatform" or p.Name == "ObbyCheckpoint" or p.Name == "ObbyFinish") and not p:GetAttribute("MoveAxis") and p.Position.Y > 3 then
			local h = p.Position.Y - p.Size.Y / 2
			local post = MapKit.deco(m, "ObbyPost", Vector3.new(0.6, h, 0.6), CFrame.new(p.Position.X, h / 2, p.Position.Z), rgb(210, 210, 216), Enum.Material.Metal)
			post.Transparency = 0.2
		end
	end
end

--------------------------------------------------------------------------------
-- 🏖️ Sunset Beach, the boardwalk and the pier
--------------------------------------------------------------------------------
local function beach(data, rng, useTerrain)
	local m = Instance.new("Model")
	m.Name = "SunsetBeach"
	m.Parent = model
	local spots = {}
	data.BeachSpots = spots
	local bz = NorthShore.BOARDWALK_Z
	local W0, W1 = NorthShore.WEST + 60, NorthShore.EAST - 30
	local cx = (W0 + W1) / 2
	-- the boardwalk: raised planks with a railing on the beach side
	MapKit.part(model, "Boardwalk", Vector3.new(W1 - W0, 1, 20), cf(cx, 0.5, bz), rgb(170, 130, 90), Enum.Material.WoodPlanks)
	for x = W0 + 2, W1 - 2, 6 do
		deco(m, "RailPost", Vector3.new(0.4, 3.4, 0.4), x, 1, bz - 9.6, rgb(240, 236, 226), Enum.Material.Wood)
	end
	deco(m, "Rail", Vector3.new(W1 - W0, 0.4, 0.4), cx, 4, bz - 9.6, rgb(240, 236, 226), Enum.Material.Wood)
	for x = W0 + 20, W1 - 20, 60 do
		lamp(m, x, bz + 8, 1)
		local seat = MapKit.seat(m, "BoardwalkBench", Vector3.new(6, 0.5, 2), cf(x + 12, 2.8, bz - 7), MapKit.WOOD, Enum.Material.Wood, nil)
		deco(m, "BenchBack", Vector3.new(6, 2, 0.4), x + 12, 2.6, bz - 6, MapKit.WOOD, Enum.Material.Wood)
		deco(m, "BenchLeg", Vector3.new(5, 1.5, 1.6), x + 12, 1, bz - 7, rgb(50, 50, 55), Enum.Material.Metal)
		table.insert(spots, spot(x + 12, 1, bz - 7, x + 12, bz - 30, { Action = "sit", Seat = seat }))
	end
	-- shops along the boardwalk: a surf shop, a snack shack, an ice cream stand
	for k, shop in ipairs({ { W0 + 60, "🏄 SURF SHOP", rgb(40, 150, 200) }, { cx - 40, "🍟 SNACK SHACK", rgb(240, 170, 40) }, { cx + 90, "🍦 SCOOPS", rgb(240, 120, 170) } }) do
		local sx = shop[1]
		solid(m, "Shack", Vector3.new(18, 10, 12), sx, 1, bz + 16, shop[3]:Lerp(WHITE, 0.5), Enum.Material.WoodPlanks)
		deco(m, "ShackRoof", Vector3.new(20, 1, 14), sx, 11, bz + 16, shop[3], Enum.Material.SmoothPlastic)
		local sign = deco(m, "ShackSign", Vector3.new(14, 2.6, 0.3), sx, 7.6, bz + 9.8, rgb(30, 30, 40))
		MapKit.signText(sign, Enum.NormalId.Front, shop[2], rgb(255, 220, 90), Enum.Font.GothamBlack)
		local window = deco(m, "ShackWindow", Vector3.new(8, 3, 0.2), sx, 3.6, bz + 9.9, rgb(160, 210, 230), Enum.Material.Glass)
		window.Transparency = 0.3
		for n = 0, 1 do
			table.insert(spots, spot(sx - 1.5 + n * 3, 1, bz + 7, sx, bz + 12, { Action = if n == 0 then "wait" else "phone" }))
		end
	end
	-- the sand (terrain in the game; a part in tests)
	local sandZ0, sandZ1 = bz - 10, NorthShore.WATER_Z
	if not useTerrain then
		MapKit.part(m, "Sand", Vector3.new(W1 - W0 + 80, 1, sandZ0 - sandZ1), cf(cx, -0.5, (sandZ0 + sandZ1) / 2), rgb(236, 214, 160), Enum.Material.Sand)
		local sea = MapKit.part(m, "Ocean", Vector3.new(1600, 1, 700), cf(cx, -1.5, sandZ1 - 350), rgb(40, 110, 170), Enum.Material.Glass)
		sea.Transparency = 0.3
		sea.CanCollide = false
	end
	-- umbrellas and towels for sunbathing
	for k = 0, 13 do
		local x = W0 + 30 + k * ((W1 - W0 - 60) / 13) + rng:NextNumber(-4, 4)
		local z = sandZ0 - rng:NextNumber(22, 55)
		local color = MapKit.FLOWERS[k % #MapKit.FLOWERS + 1]
		deco(m, "UmbrellaPole", Vector3.new(0.3, 8, 0.3), x, 0, z, WHITE, Enum.Material.Metal)
		for n = 0, 7 do
			local a = n / 8 * math.pi * 2
			MapKit.wedge(m, "UmbrellaTop", Vector3.new(0.2, 1.6, 4.6), CFrame.new(x, 8, z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -2.3) * CFrame.Angles(0, math.pi, 0), if n % 2 == 0 then color else WHITE, Enum.Material.Fabric)
		end
		for n = 0, 1 do
			local tx = x - 2.5 + n * 5
			deco(m, "Towel", Vector3.new(2.6, 0.05, 6), tx, 0, z + 3, MapKit.FLOWERS[(k + n + 2) % #MapKit.FLOWERS + 1], Enum.Material.Fabric)
			table.insert(spots, spot(tx, 0, z + 3, tx, z + 10, { Action = "sunbathe", BedTop = 0.15 }))
		end
		if k % 3 == 0 then
			MapKit.ball(m, "BeachBall", 1.6, cf(x + 4, 0.8, z + 8), rgb(255, 255, 255))
		end
	end
	-- volleyball
	local vx, vz = cx - 150, sandZ0 - 45
	for _, sx in ipairs({ -1, 1 }) do
		deco(m, "NetPost", Vector3.new(0.4, 8, 0.4), vx + sx * 10, 0, vz, WHITE, Enum.Material.Metal)
	end
	local net = deco(m, "VolleyNet", Vector3.new(20, 3, 0.1), vx, 5, vz, rgb(30, 30, 34), Enum.Material.Fabric)
	net.Transparency = 0.4
	-- the ball flies back and forth over the net (on every screen: see Ambient)
	local ball = MapKit.ball(m, "Volleyball", 1.2, cf(vx + 2, 9, vz + 5), rgb(250, 240, 180))
	ball:SetAttribute("SideA", Vector3.new(vx - 4, 3.5, vz + 8))
	ball:SetAttribute("SideB", Vector3.new(vx + 4, 3.5, vz - 8))
	MapKit.tag(ball, "Volleyball")
	deco(m, "CourtLine", Vector3.new(24, 0.05, 0.3), vx, 0, vz + 11, WHITE)
	deco(m, "CourtLine", Vector3.new(24, 0.05, 0.3), vx, 0, vz - 11, WHITE)
	for _, sz in ipairs({ -1, 1 }) do
		for k = -1, 1, 2 do
			table.insert(spots, spot(vx + k * 5, 0, vz + sz * 7, vx + k * 5, vz, { Action = "volley" }))
		end
		-- and people watching from the side
		table.insert(spots, spot(vx + 16, 0, vz + sz * 4, vx, vz, { Action = "cheer" }))
	end
	-- the lifeguard tower
	local lx, lz = cx + 30, sandZ0 - 70
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			deco(m, "LifeguardLeg", Vector3.new(0.5, 8, 0.5), lx + sx * 2.5, 0, lz + sz * 2.5, WHITE, Enum.Material.Wood)
		end
	end
	solid(m, "LifeguardDeck", Vector3.new(7, 0.6, 7), lx, 8, lz, WHITE, Enum.Material.Wood)
	solid(m, "LifeguardHut", Vector3.new(6, 5, 6), lx, 8.6, lz, rgb(230, 60, 60), Enum.Material.WoodPlanks)
	local sign = deco(m, "LifeguardSign", Vector3.new(5, 1.2, 0.2), lx, 12, lz - 3.2, WHITE)
	MapKit.signText(sign, Enum.NormalId.Back, "LIFEGUARD", rgb(220, 40, 40), Enum.Font.GothamBlack)
	-- palms along the back of the beach
	for k = 0, 12 do
		palm(m, W0 + 20 + k * ((W1 - W0 - 40) / 12), sandZ0 - 6 - (k % 2) * 4, rng, 0)
	end
	-- the pier: a long walk out over the waves, with fishing spots at the end
	local px = 220
	local pz0, pz1 = sandZ0, NorthShore.WATER_Z - 150
	MapKit.part(m, "Pier", Vector3.new(10, 1, pz0 - pz1), cf(px, 1, (pz0 + pz1) / 2), rgb(150, 110, 76), Enum.Material.WoodPlanks)
	for z = pz0 - 5, pz1 + 5, -12 do
		for _, sx in ipairs({ -1, 1 }) do
			deco(m, "PierPile", Vector3.new(0.8, 16, 0.8), px + sx * 4.6, -14, z, MapKit.DARK_WOOD, Enum.Material.Wood)
			deco(m, "PierRail", Vector3.new(0.3, 3, 0.3), px + sx * 4.8, 1.5, z, rgb(240, 236, 226), Enum.Material.Wood)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		deco(m, "PierRailTop", Vector3.new(0.3, 0.3, pz0 - pz1), px + sx * 4.8, 4.5, (pz0 + pz1) / 2, rgb(240, 236, 226), Enum.Material.Wood)
	end
	data.PierFishing = {}
	for k = 0, 3 do
		local sx = if k % 2 == 0 then 1 else -1
		local s = spot(px + sx * 3.2, 1.5, pz1 + 8 + k * 7, px + sx * 12, pz1 + 8 + k * 7, { Action = "fish" })
		table.insert(spots, s)
		table.insert(data.PierFishing, s)
	end
	-- a Water marker for fishing and the fish you can see (see FishingService, Water)
	local w = deco(m, "OceanWater", Vector3.new(2, 0.2, 2), px, -1.1, pz1 + 20, rgb(40, 110, 170))
	w.Transparency = 1
	w:SetAttribute("Radius", 70)
	w:SetAttribute("Surface", if useTerrain then -1 else -1)
	w:SetAttribute("Depth", 12)
	w:SetAttribute("Kind", "ocean")
	w:SetAttribute("Fish", 30)
	w:SetAttribute("RodStand", Vector3.new(px + 7, 0, pz0 + 4))
	MapKit.tag(w, "Water")
	data.BeachDoor = Vector3.new(NorthShore.DRIVE_X - ROAD / 2 - 3, 1, bz)
end

--------------------------------------------------------------------------------
-- The finishing touches: staff, props, things that move
--------------------------------------------------------------------------------
local function trashCan(parent, x, z, y)
	MapKit.column(parent, "TrashCan", 3, 1.8, Vector3.new(x, (y or 0.3) + 1.5, z), rgb(60, 110, 80), Enum.Material.Metal)
	MapKit.disc(parent, "TrashLid", 0.3, 2, Vector3.new(x, (y or 0.3) + 3.1, z), rgb(50, 90, 66), Enum.Material.Metal)
end

local function planter(parent, x, z, rng, y)
	y = y or 0.3
	MapKit.column(parent, "Planter", 1.6, 4, Vector3.new(x, y + 0.8, z), rgb(200, 190, 175), Enum.Material.Concrete)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		MapKit.ball(parent, "PlanterFlowers", 1.3, CFrame.new(x + math.cos(a) * 0.9, y + 1.9, z + math.sin(a) * 0.9), MapKit.FLOWERS[rng:NextInteger(1, #MapKit.FLOWERS)], Enum.Material.SmoothPlastic)
	end
	MapKit.ball(parent, "PlanterLeaves", 1.6, CFrame.new(x, y + 2.1, z), MapKit.LEAVES[2], Enum.Material.SmoothPlastic)
end

-- a string of little flags between two points (they flutter: see Ambient)
local function bunting(parent, a, b, n)
	-- the cord, tied to a pole at each end; the flags hang right off it
	local mid = (a + b) / 2
	MapKit.deco(parent, "BuntingCord", Vector3.new(0.08, 0.08, (b - a).Magnitude), CFrame.lookAt(mid, b), rgb(240, 240, 240))
	for _, e in ipairs({ a, b }) do
		MapKit.deco(parent, "BuntingPole", Vector3.new(0.35, e.Y + 0.6, 0.35), CFrame.new(e.X, (e.Y + 0.6) / 2, e.Z), rgb(230, 230, 236), Enum.Material.Metal)
	end
	for k = 1, n do
		local u = k / (n + 1)
		local p = a:Lerp(b, u) - Vector3.new(0, 0.6, 0)
		local f = MapKit.wedge(parent, "Bunting", Vector3.new(0.1, 1.2, 0.9), CFrame.lookAt(p, p + (b - a).Unit) * CFrame.Angles(0, math.rad(90), math.rad(180)), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.Fabric)
		MapKit.tag(f, "WavingFlag")
	end
end

local function flagPole(parent, x, z, color, h)
	h = h or 14
	MapKit.deco(parent, "FlagPole", Vector3.new(0.35, h, 0.35), CFrame.new(x, h / 2, z), rgb(225, 225, 230), Enum.Material.Metal)
	local f = MapKit.deco(parent, "Flag", Vector3.new(0.1, 2.4, 4), CFrame.new(x, h - 1.5, z + 2.1), color, Enum.Material.Fabric)
	MapKit.tag(f, "WavingFlag")
end

--------------------------------------------------------------------------------
-- 🏖️ More beach: the water's edge, places to sit, things washed up, crabs
--------------------------------------------------------------------------------
local function beachMore(data, rng)
	local beach = data.Model:FindFirstChild("SunsetBeach")
	local spots = data.BeachSpots
	local bz = NorthShore.BOARDWALK_Z
	local sandZ0, wz = bz - 10, NorthShore.WATER_Z
	local W0, W1 = NorthShore.WEST + 60, NorthShore.EAST - 30
	local cx = (W0 + W1) / 2
	local SAND, WET = rgb(236, 214, 160), rgb(196, 170, 120)
	-- wet sand along the water, and the surf: lines of foam that roll in and
	-- slide back (see Ambient)
	for k = 0, 6 do
		deco(beach, "WetSand", Vector3.new(W1 - W0 + 60, 0.06, 2.1), cx, BY(wz + 1 + k * 2), wz + 1 + k * 2, WET, Enum.Material.Sand)
	end
	for k = 0, 2 do
		local foam = MapKit.deco(beach, "Surf", Vector3.new(W1 - W0 + 40 - k * 30, 0.12, 1.4 + k * 0.6), CFrame.new(cx + k * 7, math.max(BY(wz + 2 - k * 2.5), -1) + 0.08, wz + 2 - k * 2.5), WHITE, Enum.Material.SmoothPlastic)
		foam.Transparency = 0.25 + k * 0.2
		foam:SetAttribute("Phase", k * 2.1)
		MapKit.tag(foam, "Surf")
	end
	-- dunes with beach grass along the back of the beach
	for k = 0, 9 do
		local x = W0 + 25 + k * ((W1 - W0 - 50) / 9) + rng:NextNumber(-8, 8)
		local z = sandZ0 - 14 - rng:NextNumber(0, 6)
		if math.abs(x - 220) > 14 then -- (not across the pier)
			local dune = MapKit.ball(beach, "Dune", 1, CFrame.new(x, -0.6, z), SAND:Lerp(WET, 0.15), Enum.Material.Sand)
			dune.Size = Vector3.new(rng:NextNumber(14, 22), 3.2, rng:NextNumber(7, 10))
			dune.CanCollide = false
			for n = 0, 6 do
				local gx, gz = x + rng:NextNumber(-6, 6), z + rng:NextNumber(-2.5, 2.5)
				for b = -1, 1 do
					MapKit.deco(beach, "DuneGrass", Vector3.new(0.12, rng:NextNumber(1.4, 2.4), 0.12), CFrame.new(gx + b * 0.25, 1.1, gz) * CFrame.Angles(0, 0, math.rad(b * 18 + rng:NextNumber(-6, 6))), rgb(150, 170, 80), Enum.Material.Grass)
				end
			end
		end
	end
	-- a wooden ramp from the boardwalk down onto the sand
	for _, rx in ipairs({ cx - 150, cx + 60 }) do
		MapKit.part(beach, "BeachRamp", Vector3.new(6, 0.4, 12), CFrame.new(rx, 0.55, bz - 15.5) * CFrame.Angles(math.rad(-5), 0, 0), rgb(170, 130, 90), Enum.Material.WoodPlanks)
		for n = 0, 6 do
			deco(beach, "SandMat", Vector3.new(5, 0.08, 1.6), rx, 0, bz - 24 - n * 2.2, rgb(190, 160, 110), Enum.Material.WoodPlanks)
		end
	end
	-- an outdoor shower to rinse the sand off
	local shx = cx - 120
	deco(beach, "ShowerPost", Vector3.new(0.5, 8, 0.5), shx, 0, sandZ0 - 4, rgb(220, 220, 225), Enum.Material.Metal)
	deco(beach, "ShowerArm", Vector3.new(0.3, 0.3, 1.6), shx, 7.7, sandZ0 - 4.8, rgb(220, 220, 225), Enum.Material.Metal)
	MapKit.disc(beach, "ShowerHead", 0.3, 1, Vector3.new(shx, 7.6, sandZ0 - 5.5), rgb(200, 200, 206), Enum.Material.Metal)
	deco(beach, "ShowerTray", Vector3.new(3, 0.2, 3), shx, 0, sandZ0 - 5.5, rgb(170, 130, 90), Enum.Material.WoodPlanks)
	-- lounge chairs in pairs with a little table (people sit on them)
	for k = 0, 5 do
		local x = W0 + 50 + k * 88 + rng:NextNumber(-6, 6)
		local z = sandZ0 - rng:NextNumber(58, 66)
		for n = 0, 1 do
			local lxp = x + n * 3.4
			local seat = MapKit.seat(beach, "LoungeChair", Vector3.new(2.2, 0.3, 5), cf(lxp, 1.2, z), if k % 2 == 0 then rgb(40, 130, 200) else rgb(240, 240, 236), Enum.Material.Fabric, nil)
			MapKit.part(beach, "LoungeBack", Vector3.new(2.2, 0.3, 2.4), CFrame.new(lxp, 1.95, z + 3.1) * CFrame.Angles(math.rad(50), 0, 0), seat.Color, Enum.Material.Fabric).CanCollide = false
			for _, lz in ipairs({ -2.2, 2.2 }) do
				deco(beach, "LoungeLeg", Vector3.new(2.2, 1.05, 0.2), lxp, 0, z + lz, WHITE, Enum.Material.Metal)
			end
			table.insert(spots, spot(lxp, 0, z, lxp, z - 10, { Action = "sit", Seat = seat }))
		end
		deco(beach, "SideTable", Vector3.new(1.2, 1.4, 1.2), x + 1.7, 0, z + 2.6, WHITE, Enum.Material.SmoothPlastic)
		deco(beach, "Drink", Vector3.new(0.35, 0.6, 0.35), x + 1.5, 1.4, z + 2.6, MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.Glass)
	end
	-- picnic blankets with a basket
	for k = 0, 3 do
		local x, z = W0 + 120 + k * 150 + rng:NextNumber(-10, 10), sandZ0 - rng:NextNumber(30, 40)
		deco(beach, "PicnicBlanket", Vector3.new(6, 0.06, 5), x, 0, z, if k % 2 == 0 then rgb(220, 60, 60) else rgb(60, 140, 220), Enum.Material.Fabric)
		for n = -1, 1 do
			deco(beach, "BlanketCheck", Vector3.new(0.6, 0.07, 5), x + n * 2, 0, z, WHITE, Enum.Material.Fabric)
		end
		deco(beach, "Basket", Vector3.new(1.6, 1, 1.1), x + 2, 0.06, z - 1.5, rgb(170, 120, 70), Enum.Material.Wood)
		deco(beach, "BasketHandle", Vector3.new(0.15, 0.7, 1), x + 2, 1.06, z - 1.5, rgb(150, 100, 60), Enum.Material.Wood)
		for n = 0, 1 do
			table.insert(spots, spot(x - 1.5 + n * 3, 0, z + 1, x, z - 6, { Action = "sit" }))
		end
	end
	-- a fire pit ringed with stones and log benches (the evening hangout)
	local fx, fz = cx + 120, sandZ0 - 40
	for n = 0, 9 do
		local a = n / 10 * math.pi * 2
		MapKit.ball(beach, "PitStone", 1.1, CFrame.new(fx + math.cos(a) * 2, 0.35, fz + math.sin(a) * 2), rgb(120, 116, 110), Enum.Material.Slate)
	end
	for n = 0, 2 do
		MapKit.cylinder(beach, "Firewood", 3, 0.5, CFrame.new(fx, 0.35, fz) * CFrame.Angles(0, n * 1.05, 0), rgb(110, 76, 50), Enum.Material.Wood)
	end
	local ember = deco(beach, "Embers", Vector3.new(1.6, 0.2, 1.6), fx, 0.3, fz, rgb(255, 120, 40), Enum.Material.Neon)
	MapKit.particles(ember, "smoke")
	for n = 0, 2 do
		local a = n / 3 * math.pi * 2 + 0.5
		local lp = Vector3.new(fx + math.cos(a) * 6, 0.7, fz + math.sin(a) * 6)
		MapKit.cylinder(beach, "LogBench", 5, 1.4, CFrame.lookAt(lp, Vector3.new(fx, 0.7, fz)) * CFrame.Angles(0, math.pi / 2, 0), rgb(130, 92, 60), Enum.Material.Wood)
		table.insert(spots, spot(lp.X, 0, lp.Z, fx, fz, { Action = "sit" }))
	end
	-- driftwood, shells and starfish scattered about
	for k = 0, 7 do
		local x, z = W0 + rng:NextNumber(10, W1 - W0 - 10), wz + rng:NextNumber(12, 40)
		MapKit.cylinder(beach, "Driftwood", rng:NextNumber(3, 6), 0.5, CFrame.new(x, BY(z) + 0.25, z) * CFrame.Angles(0, rng:NextNumber(0, 3.1), 0), rgb(180, 160, 130), Enum.Material.Wood)
	end
	for k = 0, 39 do
		local x, z = W0 + rng:NextNumber(5, W1 - W0 - 5), wz + rng:NextNumber(4, 60)
		if k % 4 == 0 then
			-- a starfish: five little arms
			for a = 0, 4 do
				MapKit.deco(beach, "Starfish", Vector3.new(0.25, 0.1, 0.7), CFrame.new(x, BY(z) + 0.05, z) * CFrame.Angles(0, a * 1.2566, 0) * CFrame.new(0, 0, -0.3), rgb(240, 120, 70), Enum.Material.SmoothPlastic)
			end
		else
			local shell = MapKit.ball(beach, "Seashell", 0.5, CFrame.new(x, BY(z) + 0.1, z), ({ rgb(250, 230, 220), rgb(240, 200, 190), rgb(230, 220, 200) })[k % 3 + 1], Enum.Material.SmoothPlastic)
			shell.Size = Vector3.new(0.5, 0.25, 0.4)
			shell.CanCollide = false
		end
	end
	-- a rocky jetty at the west end, out into the water
	for k = 0, 16 do
		local r = rng:NextNumber(3, 5.5)
		-- (piled up from the sea floor so the jetty stands out of the water)
		local rz = wz + 18 - k * 4.5
		local top = -0.4 + r * 0.6
		local bottom = math.min(BY(rz) - 0.3, -0.4 - r * 0.1)
		local h = top - bottom
		local rock = MapKit.ball(beach, "JettyRock", r, CFrame.new(W0 - 10 + rng:NextNumber(-2, 2), (top + bottom) / 2, rz) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rgb(110, 108, 104):Lerp(rgb(80, 78, 76), rng:NextNumber()), Enum.Material.Slate)
		rock.Size = Vector3.new(r, h, r * 1.1)
	end
	table.insert(spots, spot(W0 - 10, 1.6, wz + 10, W0 - 10, wz - 60, { Action = "birdwatch" }))
	-- kayaks on a rack by the surf shop
	for k = 0, 2 do
		MapKit.deco(beach, "Kayak", Vector3.new(1.6, 0.8, 9), CFrame.new(W0 + 60, 1 + k * 1.1, bz - 14), MapKit.FLOWERS[(k + 3) % #MapKit.FLOWERS + 1], Enum.Material.SmoothPlastic)
	end
	for _, rz in ipairs({ -3.5, 3.5 }) do
		deco(beach, "KayakRack", Vector3.new(2.4, 3.6, 0.3), W0 + 60, 0, bz - 14 + rz, rgb(150, 110, 70), Enum.Material.Wood)
	end
	-- 👕 the Beach Boutique: a little clothing stand with racks of jackets,
	-- a hat stand and a mirror (players shop here: see DisguiseService)
	do
		local bx2, bz2 = W0 + 100, bz - 16
		local stand = Instance.new("Model")
		stand.Name = "BeachBoutique"
		stand.Parent = beach
		MapKit.part(stand, "BoutiqueCounter", Vector3.new(8, 3.2, 2.4), CFrame.new(bx2, 1.6, bz2), rgb(240, 236, 226), Enum.Material.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			deco(stand, "BoutiquePost", Vector3.new(0.4, 9, 0.4), bx2 + sx * 4.6, 0, bz2 - 2, rgb(150, 110, 70), Enum.Material.Wood)
		end
		MapKit.awning(stand, 10.4, 3.4, CFrame.new(bx2, 9, bz2 - 1.6), rgb(250, 120, 160), WHITE)
		local sign = MapKit.deco(stand, "BoutiqueSign", Vector3.new(8, 1.4, 0.2), CFrame.new(bx2, 10.2, bz2 - 2.1), rgb(40, 40, 50))
		MapKit.signText(sign, Enum.NormalId.Back, "👕 BEACH BOUTIQUE", WHITE, Enum.Font.GothamBlack)
		-- two racks of clothes on hangers
		for _, sx in ipairs({ -1, 1 }) do
			local rx2 = bx2 + sx * 9
			for _, ex in ipairs({ -2.2, 2.2 }) do
				deco(stand, "RackPole", Vector3.new(0.2, 5, 0.2), rx2 + ex, 0, bz2, rgb(200, 200, 206), Enum.Material.Metal)
			end
			deco(stand, "RackBar", Vector3.new(4.6, 0.15, 0.15), rx2, 4.9, bz2, rgb(200, 200, 206), Enum.Material.Metal)
			for k = 0, 5 do
				deco(stand, "HangingShirt", Vector3.new(0.3, 2.6, 1.8), rx2 - 1.8 + k * 0.72, 2.2, bz2, MapKit.FLOWERS[(k + (sx > 0 and 3 or 0)) % #MapKit.FLOWERS + 1], Enum.Material.Fabric)
			end
		end
		-- a hat stand and a mirror
		deco(stand, "HatStand", Vector3.new(0.3, 5.6, 0.3), bx2 + 5.6, 0, bz2 + 3, rgb(150, 110, 70), Enum.Material.Wood)
		for k = 0, 2 do
			MapKit.cylinder(stand, "StandHat", 0.4, 1.4, CFrame.new(bx2 + 5.6 + (k - 1) * 0.5, 5.8 - k * 1.2, bz2 + 3) * CFrame.Angles(0, 0, math.rad(90)), ({ rgb(230, 220, 190), rgb(200, 40, 50), rgb(130, 85, 50) })[k + 1], Enum.Material.Fabric)
		end
		local mirror = deco(stand, "BoutiqueMirror", Vector3.new(2.4, 6, 0.2), bx2 - 5.8, 0, bz2 + 3, rgb(210, 230, 240), Enum.Material.Glass)
		mirror.Reflectance = 0.4
		NorthShore.BoutiqueAt = Vector3.new(bx2, 0, bz2 + 2.2)
	end
	-- surf flags at the lifeguard tower: green means good swimming
	local lx, lz = cx + 30, sandZ0 - 70
	for n, c in ipairs({ rgb(60, 200, 90), rgb(250, 210, 40) }) do
		local px = lx - 6 - n * 2
		deco(beach, "SurfFlagPole", Vector3.new(0.25, 9, 0.25), px, 0, lz, WHITE, Enum.Material.Metal)
		MapKit.tag(deco(beach, "SurfFlag", Vector3.new(0.05, 1.6, 2.2), px, 7.2, lz + 1.15, c), "WavingFlag")
	end
	-- kites up in the breeze, on strings down to the sand
	for k = 0, 2 do
		local ax, az = W0 + 160 + k * 170, sandZ0 - 50
		local top = Vector3.new(ax + 8, 34 + k * 5, az - 30)
		local kite = MapKit.deco(beach, "Kite", Vector3.new(3, 3, 0.15), CFrame.lookAt(top, top + Vector3.new(0, 0, 1)) * CFrame.Angles(0, 0, math.rad(45)), MapKit.FLOWERS[(k * 2) % #MapKit.FLOWERS + 1], Enum.Material.Fabric)
		MapKit.tag(kite, "Bob")
		local base = Vector3.new(ax, 0.3, az)
		local mid = (top + base) / 2
		MapKit.deco(beach, "KiteString", Vector3.new(0.05, 0.05, (top - base).Magnitude), CFrame.lookAt(mid, top), WHITE)
		deco(beach, "KiteStake", Vector3.new(0.3, 0.8, 0.3), ax, 0, az, rgb(150, 110, 70), Enum.Material.Wood)
	end
	-- in the water: a swimming raft with a ladder, floaties, a paddleboard
	-- (they all ride the waves)
	local rx, rz = cx - 40, wz - 26
	local raft = MapKit.part(beach, "SwimRaft", Vector3.new(10, 0.8, 10), CFrame.new(rx, -0.7, rz), rgb(236, 230, 214), Enum.Material.WoodPlanks)
	MapKit.tag(raft, "Bob")
	for _, sx in ipairs({ -0.5, 0.5 }) do
		MapKit.tag(MapKit.deco(beach, "RaftLadder", Vector3.new(0.2, 2.4, 0.2), CFrame.new(rx + sx, -0.9, rz + 5.1), rgb(200, 200, 206), Enum.Material.Metal), "Bob")
	end
	for k = 0, 5 do
		local fx2, fz2 = W0 + 80 + k * 90 + rng:NextNumber(-10, 10), wz - rng:NextNumber(8, 30)
		local ring = MapKit.cylinder(beach, "Floatie", 0.6, 2.4, CFrame.new(fx2, -0.85, fz2) * CFrame.Angles(0, 0, math.rad(90)), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.SmoothPlastic)
		ring.CanCollide = false
		MapKit.tag(ring, "Bob")
	end
	local board = MapKit.deco(beach, "Paddleboard", Vector3.new(2.2, 0.3, 10), CFrame.new(cx + 160, -0.9, wz - 18) * CFrame.Angles(0, 0.4, 0), rgb(250, 200, 60), Enum.Material.SmoothPlastic)
	MapKit.tag(board, "Bob")
	if NorthShore.Sloped then
		-- 🐠 under the waves, down the sloping sea floor: swaying kelp, mossy
		-- rocks, starfish, sand dollars and an old sunken rowboat to swim to
		for k = 0, 40 do
			local x, z = W0 + rng:NextNumber(0, W1 - W0), wz - rng:NextNumber(14, 125)
			local floor = BY(z)
			local h = math.min(-1.6 - floor, rng:NextNumber(3, 9))
			if h > 1 then
				local kelp = MapKit.deco(beach, "Kelp", Vector3.new(0.5, h, 0.15), CFrame.new(x, floor + h / 2, z) * CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.12, 0.12)), rgb(50, 110, 60):Lerp(rgb(110, 120, 40), rng:NextNumber()), Enum.Material.SmoothPlastic)
				kelp.CanCollide = false
				MapKit.tag(kelp, "Sway")
			end
		end
		for k = 0, 18 do
			local x, z = W0 + rng:NextNumber(0, W1 - W0), wz - rng:NextNumber(10, 120)
			local r = rng:NextNumber(1.5, 4)
			local rock = MapKit.ball(beach, "SeaRock", r, CFrame.new(x, BY(z) + r * 0.2, z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rgb(90, 100, 92):Lerp(rgb(70, 96, 70), rng:NextNumber()), Enum.Material.Slate)
			rock.Size = Vector3.new(r, r * 0.6, r * 1.2)
			if k % 3 == 0 then
				local sf = MapKit.deco(beach, "SeaStar", Vector3.new(0.9, 0.12, 0.9), CFrame.new(x + r * 0.7, BY(z) + 0.08, z) * CFrame.Angles(0, k, 0), rgb(240, 110, 70), Enum.Material.SmoothPlastic)
				sf.CanCollide = false
			end
		end
		for k = 0, 14 do
			local x, z = W0 + rng:NextNumber(0, W1 - W0), wz - rng:NextNumber(4, 60)
			local dollar = MapKit.cylinder(beach, "SandDollar", 0.08, 0.9, CFrame.new(x, BY(z) + 0.04, z) * CFrame.Angles(0, 0, math.rad(90)), rgb(232, 222, 200), Enum.Material.SmoothPlastic)
			dollar.CanCollide = false
		end
		-- the wreck: tipped on its side, half buried
		local wx, wz2 = cx + 70, wz - 70
		local wf = CFrame.new(wx, BY(wz2) + 0.6, wz2) * CFrame.Angles(0, 0.7, math.rad(25))
		local hull = rgb(110, 84, 60)
		MapKit.part(beach, "WreckHull", Vector3.new(4, 0.3, 10), wf, hull, Enum.Material.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			MapKit.part(beach, "WreckSide", Vector3.new(0.3, 1.6, 10), wf * CFrame.new(sx * 2, 0.8, 0), hull:Lerp(rgb(60, 80, 60), 0.3), Enum.Material.WoodPlanks)
		end
		MapKit.deco(beach, "WreckSeat", Vector3.new(4, 0.25, 1), wf * CFrame.new(0, 1, 1), hull, Enum.Material.Wood)
		MapKit.deco(beach, "WreckOar", Vector3.new(0.25, 0.25, 7), CFrame.new(wx + 4, BY(wz2) + 0.15, wz2 + 3) * CFrame.Angles(0, 1.9, 0), rgb(150, 120, 80), Enum.Material.Wood)
		-- 🐬 a pod of dolphins leaping out past the swimmers, and a jet ski
		-- carving circles (the client animates both: see Ambient)
		for k = 0, 2 do
			local d = Instance.new("Model")
			d.Name = "Dolphin"
			d.Parent = beach
			local base = CFrame.new(cx - 120 + k * 9, -6, wz - 190 - k * 6)
			local grey = rgb(110, 124, 140)
			local body = MapKit.ball(d, "DolphinBody", 1, base, grey, Enum.Material.SmoothPlastic)
			body.Size = Vector3.new(1.4, 1.4, 5)
			body.CanCollide = false
			MapKit.ball(d, "DolphinSnout", 0.6, base * CFrame.new(0, -0.15, -2.8), grey, Enum.Material.SmoothPlastic).Size = Vector3.new(0.5, 0.45, 1.4)
			MapKit.wedge(d, "DolphinFin", Vector3.new(0.15, 1, 1.1), base * CFrame.new(0, 0.95, 0.3), grey:Lerp(MapKit.BLACK, 0.2), Enum.Material.SmoothPlastic)
			MapKit.deco(d, "DolphinTail", Vector3.new(2, 0.15, 0.8), base * CFrame.new(0, 0, 2.7), grey:Lerp(MapKit.BLACK, 0.2), Enum.Material.SmoothPlastic)
			MapKit.deco(d, "DolphinBelly", Vector3.new(0.9, 0.2, 3.4), base * CFrame.new(0, -0.6, -0.2), rgb(220, 226, 232), Enum.Material.SmoothPlastic)
			for _, p in ipairs(d:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
				end
			end
			d:SetAttribute("Phase", k * 0.6)
			MapKit.tag(body, "Dolphin")
		end
		local ski = Instance.new("Model")
		ski.Name = "JetSki"
		ski.Parent = beach
		local jf = CFrame.new(cx + 260, -0.6, wz - 150)
		local js = MapKit.deco(ski, "JetSkiHull", Vector3.new(2.6, 1, 7), jf, WHITE, Enum.Material.SmoothPlastic)
		MapKit.deco(ski, "JetSkiStripe", Vector3.new(2.62, 0.3, 5), jf * CFrame.new(0, 0.2, 0.4), rgb(230, 50, 70), Enum.Material.SmoothPlastic)
		MapKit.deco(ski, "JetSkiSeat", Vector3.new(1.4, 0.5, 3), jf * CFrame.new(0, 0.7, 1), rgb(30, 30, 34), Enum.Material.Leather)
		MapKit.deco(ski, "JetSkiBars", Vector3.new(2, 0.2, 0.2), jf * CFrame.new(0, 1.3, -1.4), rgb(40, 40, 44), Enum.Material.Metal)
		MapKit.deco(ski, "JetSkiRider", Vector3.new(1.4, 2.2, 0.9), jf * CFrame.new(0, 2, 0.6), rgb(240, 120, 40), Enum.Material.Fabric)
		MapKit.ball(ski, "JetSkiHead", 1, jf * CFrame.new(0, 3.6, 0.6), rgb(200, 150, 110), Enum.Material.SmoothPlastic)
		MapKit.deco(ski, "JetSkiWake", Vector3.new(3, 0.06, 9), jf * CFrame.new(0, -0.45, 7.5), WHITE, Enum.Material.SmoothPlastic).Transparency = 0.35
		for _, p in ipairs(ski:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
			end
		end
		MapKit.tag(js, "JetSki")
	end
	-- seaweed washed up along the tide line, and ripples in the sand
	for k = 0, 23 do
		local x = W0 + rng:NextNumber(5, W1 - W0 - 5)
		local weed = MapKit.ball(beach, "Seaweed", 1, CFrame.new(x, BY(wz + 13) + 0.05, wz + 13 + rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rgb(60, 90, 50):Lerp(rgb(110, 100, 50), rng:NextNumber()), Enum.Material.SmoothPlastic)
		weed.Size = Vector3.new(rng:NextNumber(1.5, 3.5), 0.15, rng:NextNumber(0.4, 0.9))
		weed.CanCollide = false
	end
	for k = 0, 59 do
		local x, z = W0 + rng:NextNumber(10, W1 - W0 - 10), wz + rng:NextNumber(16, sandZ0 - wz - 20)
		MapKit.deco(beach, "SandRipple", Vector3.new(rng:NextNumber(4, 9), 0.05, 0.35), CFrame.new(x, BY(z) + 0.02, z) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0), SAND:Lerp(WET, 0.35), Enum.Material.Sand)
	end
	-- tide pools by the jetty, with a starfish and a little rock in each
	for k = 0, 2 do
		local tx, tz = W0 + 8 + k * 9, wz + 6 + (k % 2) * 4
		local pool = MapKit.disc(beach, "TidePool", 0.08, 5 + k, Vector3.new(tx, BY(tz) + 0.04, tz), rgb(70, 150, 170), Enum.Material.Glass)
		pool.Transparency = 0.3
		MapKit.ball(beach, "PoolRock", 1.2, CFrame.new(tx + 1, BY(tz) + 0.3, tz - 0.6), rgb(110, 108, 104), Enum.Material.Slate)
	end
	-- footprints wandering from the boardwalk down to the water
	local fpx, fpz = cx - 150, sandZ0 - 20
	for n = 0, 29 do
		local side = if n % 2 == 0 then -0.45 else 0.45
		local x = fpx + math.sin(n * 0.25) * 6 + side
		local z = fpz - n * 2.1
		if z > wz + 10 then
			MapKit.deco(beach, "Footprint", Vector3.new(0.5, 0.03, 0.9), CFrame.new(x, BY(z) + 0.02, z) * CFrame.Angles(0, math.sin(n * 0.25) * 0.3, 0), SAND:Lerp(WET, 0.55), Enum.Material.Sand)
		end
	end
	-- little crabs scuttling sideways near the water (see Ambient)
	for k = 0, 7 do
		local x, z = W0 + 30 + k * ((W1 - W0 - 60) / 7) + rng:NextNumber(-10, 10), wz + rng:NextNumber(6, 16)
		local crab = Instance.new("Model")
		crab.Name = "Crab"
		crab.Parent = beach
		local y = BY(z)
		local body = MapKit.ball(crab, "CrabBody", 1, CFrame.new(x, y + 0.3, z), rgb(220, 70, 50), Enum.Material.SmoothPlastic)
		body.Size = Vector3.new(1, 0.45, 0.8)
		body.CanCollide = false
		for _, sx in ipairs({ -1, 1 }) do
			MapKit.ball(crab, "CrabClaw", 0.4, CFrame.new(x + sx * 0.55, y + 0.45, z - 0.45), rgb(230, 80, 60), Enum.Material.SmoothPlastic).CanCollide = false
			for n = -1, 1 do
				MapKit.deco(crab, "CrabLeg", Vector3.new(0.5, 0.08, 0.08), CFrame.new(x + sx * 0.6, y + 0.15, z + n * 0.22), rgb(200, 60, 40))
			end
		end
		MapKit.tag(body, "Crab")
	end
end

local function details(data, rng)
	local staff = {}
	data.Staff = staff
	local function worker(name, job, x, y, z, fx, fz, action, activity)
		table.insert(staff, { Name = name, Job = job, Spot = spot(x, y, z, fx, fz), Action = action, Activity = activity })
	end
	-- 🎡 Funland: someone running every ride, the carts, the booths
	local fun = data.Model:FindFirstChild("Funland")
	worker("Rita", "Ride Operator", -178, 0.3, Z0 - 262, -190, Z0 - 240, "present", "🎡 Running the Sky Wheel")
	worker("Gus", "Ride Operator", -60, 0.3, Z0 - 121, -60, Z0 - 100, "guard", "🎠 Running the carousel")
	worker("Bo", "Ride Operator", -190, 0.3, Z0 - 78, -200, Z0 - 90, "present", "🎢 Running the Freefall")
	worker("Candy", "Vendor", -40, 0.3, Z0 - 162.5, -40, Z0 - 150, "counter", "🍭 Spinning cotton candy")
	worker("Luigi", "Vendor", -120, 0.3, Z0 - 162.5, -120, Z0 - 150, "counter", "🍦 Scooping ice cream")
	worker("Frank", "Vendor", -150, 0.3, Z0 - 292.5, -150, Z0 - 280, "counter", "🌭 Grilling hot dogs")
	worker("Pop", "Game Attendant", -13, 0.3, Z0 - 223.5, -13, Z0 - 210, "present", "🎈 Running Balloon Pop")
	worker("Tess", "Prize Clerk", -13, 0.3, Z0 - 259.5, -13, Z0 - 245, "counter", "🎟️ At the prize booth")
	worker("Dr. Paws", "Pet Adoption", 7, 0.3, Z0 - 63.5, 7, Z0 - 50, "counter", "🐾 Finding pets homes")
	worker("Ace", "Obby Attendant", -266, 0.3, Z0 - 66, -280, Z0 - 70, "present", "🧗 Timing the Sky Obby")
	-- trash cans, planters, benches along the paths
	local c = Vector3.new(-105, 0, Z0 - 170)
	for k = 0, 7 do
		local x = c.X - 130 + k * 36
		trashCan(fun, x + 6, c.Z + 7.5)
		planter(fun, x + 14, c.Z - 8, rng)
		if k % 2 == 0 then
			local seat = Streets.bench(fun, CFrame.lookAt(Vector3.new(x + 22, 0.3, c.Z + 9), Vector3.new(x + 22, 0.3, c.Z)), nil)
			table.insert(data.FunlandSpots, { CFrame = CFrame.lookAt(Vector3.new(x + 22, 0.3, c.Z + 9), Vector3.new(x + 22, 0.3, c.Z)), Seat = seat, Action = "sit", Role = "visit", Floor = 1 })
		end
	end
	bunting(fun, Vector3.new(c.X - 140, 10, c.Z + 4), Vector3.new(c.X + 140, 10, c.Z + 4), 30)
	bunting(fun, Vector3.new(c.X + 56, 10, c.Z - 125), Vector3.new(c.X + 56, 10, c.Z + 125), 26)
	-- the ticket booth at the gate, and a balloon seller with a bunch of balloons
	solid(fun, "TicketBooth", Vector3.new(6, 8, 6), 46, 0.3, c.Z - 18, rgb(240, 200, 60), Enum.Material.WoodPlanks)
	deco(fun, "TicketBoothRoof", Vector3.new(7.4, 1, 7.4), 46, 8.3, c.Z - 18, rgb(220, 60, 80), Enum.Material.SmoothPlastic)
	local tsign = deco(fun, "TicketSign", Vector3.new(0.2, 1.6, 5), 49.1, 5, c.Z - 18, rgb(30, 30, 40))
	MapKit.signText(tsign, Enum.NormalId.Right, "🎟️ TICKETS", rgb(255, 220, 90), Enum.Font.GothamBlack)
	worker("Mo", "Ticket Seller", 50.5, 0.3, c.Z - 18, 60, c.Z - 18, "counter", "🎟️ Selling tickets")
	local bx, bz = 50, c.Z + 20
	for k = 0, 8 do
		local a = k / 9 * math.pi * 2
		local top = Vector3.new(bx + math.cos(a) * 1.2, 10 + (k % 3) * 0.8, bz + math.sin(a) * 1.2)
		local b = MapKit.ball(fun, "SellerBalloon", 1.6, CFrame.new(top), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.SmoothPlastic)
		b.Reflectance = 0.2
		MapKit.tag(b, "Bob")
		local mid = (top + Vector3.new(bx, 4, bz)) / 2
		MapKit.deco(fun, "BalloonString", Vector3.new(0.06, 0.06, (top - Vector3.new(bx, 4, bz)).Magnitude), CFrame.lookAt(mid, top), WHITE)
	end
	worker("Zippy", "Balloon Seller", bx, 0.3, bz, bx + 10, bz, "wait", "🎈 Selling balloons")
	-- 🏖️ the beach: sandcastles, surfboards, coolers, buoys, a lifeguard
	local beach = data.Model:FindFirstChild("SunsetBeach")
	local bw = NorthShore.BOARDWALK_Z
	local sandZ0 = bw - 10
	for k = 0, 4 do
		local x, z = -300 + k * 130 + rng:NextNumber(-10, 10), sandZ0 - rng:NextNumber(60, 80)
		deco(beach, "Sandcastle", Vector3.new(4, 1.6, 4), x, 0, z, rgb(222, 196, 140), Enum.Material.Sand)
		for _, e in ipairs({ { -1.4, -1.4 }, { 1.4, -1.4 }, { -1.4, 1.4 }, { 1.4, 1.4 } }) do
			MapKit.column(beach, "CastleTower", 2.6, 1.2, Vector3.new(x + e[1], 1.3, z + e[2]), rgb(214, 188, 132), Enum.Material.Sand, false)
		end
		deco(beach, "CastleKeep", Vector3.new(1.8, 1.4, 1.8), x, 1.6, z, rgb(214, 188, 132), Enum.Material.Sand)
		deco(beach, "CastleFlagPole", Vector3.new(0.1, 1.6, 0.1), x, 3, z, WHITE)
		MapKit.tag(deco(beach, "CastleFlag", Vector3.new(0.05, 0.5, 0.8), x, 4.1, z + 0.4, MapKit.FLOWERS[k + 1]), "WavingFlag")
		MapKit.deco(beach, "Bucket", Vector3.new(1, 1, 1), CFrame.new(x + 3, 0.5, z + 1), MapKit.FLOWERS[(k + 2) % #MapKit.FLOWERS + 1], Enum.Material.SmoothPlastic)
	end
	for k = 0, 5 do
		local x = -340 - 8 + k * 3.2
		MapKit.deco(beach, "Surfboard", Vector3.new(1.8, 0.3, 7), CFrame.new(x, 3.4, bw + 5) * CFrame.Angles(math.rad(80), 0, math.rad(-8 + k * 3)), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.SmoothPlastic)
	end
	for k = 0, 6 do
		local x, z = -280 + k * 85 + rng:NextNumber(-6, 6), sandZ0 - rng:NextNumber(28, 50)
		deco(beach, "Cooler", Vector3.new(2, 1.4, 1.3), x, 0, z, if k % 2 == 0 then rgb(40, 120, 200) else rgb(220, 60, 60), Enum.Material.SmoothPlastic)
		deco(beach, "CoolerLid", Vector3.new(2.1, 0.3, 1.4), x, 1.4, z, WHITE, Enum.Material.SmoothPlastic)
	end
	-- a line of buoys marking the swimming area (they bob on the waves)
	for k = 0, 24 do
		local b = MapKit.ball(beach, "Buoy", 1.4, CFrame.new(-360 + k * 26, -0.9, NorthShore.WATER_Z - 38), if k % 2 == 0 then rgb(240, 60, 50) else WHITE, Enum.Material.SmoothPlastic)
		MapKit.tag(b, "Bob")
	end
	local swim = deco(beach, "SwimSign", Vector3.new(8, 3, 0.3), 120, 5, sandZ0 - 20, rgb(40, 120, 200))
	deco(beach, "SwimSignPost", Vector3.new(0.3, 5, 0.3), 120, 0, sandZ0 - 20, WHITE)
	MapKit.signText(swim, Enum.NormalId.Front, "🏊 SWIM AREA · LIFEGUARD ON DUTY", WHITE, Enum.Font.GothamBold)
	MapKit.signText(swim, Enum.NormalId.Back, "🏊 SWIM AREA", WHITE, Enum.Font.GothamBold)
	worker("Kai", "Lifeguard", -20, 0, sandZ0 - 64, -20, sandZ0 - 200, "birdwatch", "🛟 Watching the swimmers")
	worker("Nalu", "Surf Shop", -340, 1, bw + 12.5, -340, bw, "counter", "🏄 Renting surfboards")
	worker("Shelly", "Snack Shack", -90, 1, bw + 12.5, -90, bw, "counter", "🍟 Frying up snacks")
	worker("Scoop", "Ice Cream", 40, 1, bw + 12.5, 40, bw, "counter", "🍦 Scooping cones")
	-- 🚗 AutoLand: flags, pennants and two inflatable tube men
	local lot = data.Model:FindFirstChild("AutoLand")
	local lc = Vector3.new(150, 0, Z0 - 75)
	for k = 0, 4 do
		flagPole(lot, lc.X - 48 + k * 24, lc.Z + 36.5, ({ rgb(220, 50, 50), rgb(250, 250, 250), rgb(40, 90, 200) })[k % 3 + 1])
	end
	for _, e in ipairs({ { -50, 36 }, { 50, 36 }, { 50, -36 }, { -50, -36 } }) do
		MapKit.deco(lot, "PennantPole", Vector3.new(0.3, 9, 0.3), CFrame.new(lc.X + e[1], 4.5, lc.Z + e[2]), rgb(200, 200, 205), Enum.Material.Metal)
	end
	bunting(lot, lc + Vector3.new(-50, 9, 36), lc + Vector3.new(50, 9, 36), 24)
	bunting(lot, lc + Vector3.new(50, 9, 36), lc + Vector3.new(50, 9, -36), 18)
	for k, e in ipairs({ { -44, 30, rgb(230, 40, 40) }, { 44, 30, rgb(40, 140, 240) } }) do
		local base = MapKit.part(lot, "TubeManFan", Vector3.new(2.4, 1.6, 2.4), CFrame.new(lc.X + e[1], 1.1, lc.Z + e[2]), e[3], Enum.Material.SmoothPlastic)
		MapKit.tag(base, "TubeMan")
	end
end

function NorthShore.build(parent, rng, useTerrain)
	model = Instance.new("Model")
	model.Name = "NorthShore"
	model.Parent = parent
	NorthShore.Sloped = useTerrain == true
	local data = { Model = model }
	drive(data)
	autoland(data, rng)
	funland(data, rng)
	obby(data, rng)
	beach(data, rng, useTerrain)
	details(data, rng)
	beachMore(data, rng)
	-- each ride streams in whole, so every screen can turn all of it
	for _, ride in ipairs(data.Rides or {}) do
		pcall(function()
			ride.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		end)
	end
	return data
end

return NorthShore
