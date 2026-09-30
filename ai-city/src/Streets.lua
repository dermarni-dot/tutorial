-- Streets (ModuleScript) — ServerScriptService.Modules.Streets
-- Roads with lane markings and crosswalks, raised sidewalks with curbs, street
-- lamps that light the ground at night, traffic lights downtown, street name
-- signs, fire hydrants, trash cans, bus stops with shelters, sidewalk trees
-- and parked cars.

local MapKit = require(script.Parent:WaitForChild("MapKit"))

local Streets = {}

local part, deco, rgb = MapKit.part, MapKit.deco, MapKit.rgb
local SPACING, ROAD, BLOCK, HALF, SIDEWALK, N, EXTENT, LOT_Y = MapKit.SPACING, MapKit.ROAD, MapKit.BLOCK, MapKit.HALF, MapKit.SIDEWALK, MapKit.N, MapKit.EXTENT, MapKit.LOT_Y
local WHITE, BLACK = MapKit.WHITE, MapKit.BLACK

Streets.STREETS = { "Chestnut Street", "Pine Street", "Oak Street", "Maple Street", "Elm Street", "Cedar Street", "Birch Street", "Willow Street", "Ash Street", "Spruce Street", "Aspen Street", "Hazel Street" }
Streets.AVENUES = { "1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue", "5th Avenue", "6th Avenue", "7th Avenue", "8th Avenue", "9th Avenue", "10th Avenue", "11th Avenue", "12th Avenue" }

-- road k runs along (k + 0.5) * SPACING, for k = -N-1 .. N
function Streets.streetName(k)
	return Streets.STREETS[math.clamp(k + N + 2, 1, #Streets.STREETS)]
end
function Streets.avenueName(k)
	return Streets.AVENUES[math.clamp(k + N + 2, 1, #Streets.AVENUES)]
end

-- Leaves and needles are smooth, softly shaded shapes (no noisy grass texture)
local FOLIAGE = Enum.Material.SmoothPlastic

-- a leafy tree: a round, tapering trunk that forks into two branches, and a
-- full canopy of overlapping rounded clumps in a few shades of green
function Streets.tree(parent, pos, scale, rng)
	scale = scale or 1
	local r = function(a, b)
		return if rng then rng:NextNumber(a, b) else (a + b) / 2
	end
	local trunkH = 7 * scale
	local bark = MapKit.WOOD:Lerp(BLACK, 0.12)
	MapKit.column(parent, "Trunk", trunkH * 0.55, 1.5 * scale, pos + Vector3.new(0, trunkH * 0.275, 0), bark, Enum.Material.Wood, false).CanQuery = false
	MapKit.column(parent, "Trunk", trunkH * 0.55, 1.1 * scale, pos + Vector3.new(0, trunkH * 0.72, 0), bark, Enum.Material.Wood, false).CanQuery = false
	MapKit.disc(parent, "TrunkFlare", 0.5 * scale, 2.2 * scale, pos + Vector3.new(0, 0.25 * scale, 0), bark:Lerp(BLACK, 0.1), Enum.Material.Wood)
	local yaw = r(0, math.pi * 2)
	for k = -1, 1, 2 do
		local base = pos + Vector3.new(0, trunkH * 0.85, 0)
		local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(90 + k * 35)) * CFrame.new(1.4 * scale, 0, 0)
		MapKit.cylinder(parent, "Branch", 3 * scale, 0.6 * scale, cf, bark, Enum.Material.Wood)
	end
	local leaf = MapKit.LEAVES[rng and rng:NextInteger(1, #MapKit.LEAVES) or 1]
	local top = pos + Vector3.new(0, trunkH + 2.4 * scale, 0)
	MapKit.ball(parent, "Leaves", 8.4 * scale, CFrame.new(top), leaf, FOLIAGE)
	for k = 1, 6 do
		local a = yaw + k / 6 * math.pi * 2 + r(-0.3, 0.3)
		local out = r(2.4, 3.4) * scale
		local up = r(-1.2, 2.2) * scale
		local shade = if k % 3 == 0 then leaf:Lerp(WHITE, 0.08) elseif k % 3 == 1 then leaf:Lerp(BLACK, 0.08) else leaf
		MapKit.ball(parent, "Leaves", r(4.4, 5.8) * scale, CFrame.new(top + Vector3.new(math.cos(a) * out, up, math.sin(a) * out)), shade, FOLIAGE)
	end
	MapKit.ball(parent, "Leaves", 5.4 * scale, CFrame.new(top + Vector3.new(r(-0.8, 0.8), 3.4 * scale, r(-0.8, 0.8))), leaf:Lerp(WHITE, 0.12), FOLIAGE)
end

-- a pine for the woods and the hills: a tall rounded cone of overlapping
-- clumps, widest at the bottom
function Streets.pine(parent, pos, scale)
	scale = scale or 1
	MapKit.column(parent, "Trunk", 6 * scale, 1.2 * scale, pos + Vector3.new(0, 3 * scale, 0), MapKit.DARK_WOOD, Enum.Material.Wood, false).CanQuery = false
	local green = rgb(44, 106, 58)
	local n = 6
	for k = 0, n - 1 do
		local u = k / (n - 1)
		local d = (7.4 - u * 5.6) * scale
		local y = (5.2 + u * 11) * scale
		MapKit.ball(parent, "Needles", d, CFrame.new(pos + Vector3.new(0, y, 0)), green:Lerp(rgb(62, 128, 70), u * 0.6), FOLIAGE)
	end
	MapKit.ball(parent, "Needles", 1.4 * scale, CFrame.new(pos + Vector3.new(0, 17.4 * scale, 0)), rgb(62, 128, 70), FOLIAGE)
end

function Streets.bench(parent, cf, place)
	local seat = MapKit.seat(parent, "BenchSeat", Vector3.new(6, 0.5, 2), cf * CFrame.new(0, 1.8, 0), MapKit.WOOD, Enum.Material.Wood, place)
	deco(parent, "BenchBack", Vector3.new(6, 2, 0.4), cf * CFrame.new(0, 3, 0.9), MapKit.WOOD, Enum.Material.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		deco(parent, "BenchLeg", Vector3.new(0.4, 1.6, 1.8), cf * CFrame.new(sx * 2.6, 0.8, 0), rgb(50, 50, 55), Enum.Material.Metal)
		deco(parent, "BenchArm", Vector3.new(0.3, 0.8, 1.8), cf * CFrame.new(sx * 2.9, 2.4, 0.1), rgb(50, 50, 55), Enum.Material.Metal)
	end
	return seat, cf * CFrame.new(0, 0, -0.2)
end

-- street lamp: a post with an arm, a glowing head and a light pointing down
function Streets.lamp(parent, pos, facing)
	local cf = CFrame.lookAt(pos, pos + facing)
	deco(parent, "LampBase", Vector3.new(1.2, 1, 1.2), cf * CFrame.new(0, 0.5, 0), rgb(40, 44, 50), Enum.Material.Metal)
	deco(parent, "LampPost", Vector3.new(0.5, 13, 0.5), cf * CFrame.new(0, 6.5, 0), rgb(40, 44, 50), Enum.Material.Metal)
	deco(parent, "LampArm", Vector3.new(0.4, 0.4, 3), cf * CFrame.new(0, 12.8, -1.4), rgb(40, 44, 50), Enum.Material.Metal)
	local head = deco(parent, "LampHead", Vector3.new(1.8, 0.7, 2.4), cf * CFrame.new(0, 12.6, -2.8), rgb(120, 120, 112), Enum.Material.SmoothPlastic)
	local spot = MapKit.spot(head, Enum.NormalId.Bottom, MapKit.LAMP_LIGHT, 28, 120, 2.2)
	spot.Enabled = false
	table.insert(MapKit.Registry.Lamps, { Head = head, Light = spot })
	return head
end

local function hydrant(parent, pos)
	local red = rgb(210, 40, 40)
	MapKit.column(parent, "Hydrant", 2.4, 1, pos + Vector3.new(0, 1.2, 0), red, Enum.Material.Metal)
	MapKit.ball(parent, "HydrantCap", 1.1, CFrame.new(pos + Vector3.new(0, 2.4, 0)), red, Enum.Material.Metal)
	MapKit.cylinder(parent, "HydrantNozzle", 1.6, 0.45, CFrame.new(pos + Vector3.new(0, 1.6, 0)), rgb(230, 190, 60), Enum.Material.Metal)
end

local function trashCan(parent, pos)
	local can = MapKit.column(parent, "TrashCan", 3, 1.8, pos + Vector3.new(0, 1.5, 0), rgb(50, 90, 70), Enum.Material.Metal)
	-- players on the run can hide in it (see CrimeService)
	can:SetAttribute("HideName", "a trash can")
	MapKit.tag(can, "HideSpot")
	MapKit.disc(parent, "TrashLid", 0.3, 2, pos + Vector3.new(0, 3.1, 0), rgb(40, 70, 56), Enum.Material.Metal)
end

local function busStop(parent, cf, streetName)
	local model = Instance.new("Model")
	model.Name = "BusStop"
	model.Parent = parent
	part(model, "ShelterRoof", Vector3.new(10, 0.4, 4.4), cf * CFrame.new(0, 8.6, 0), rgb(60, 70, 90), Enum.Material.Metal)
	local back = deco(model, "ShelterBack", Vector3.new(10, 6.6, 0.2), cf * CFrame.new(0, 4.6, 2), rgb(180, 220, 240), Enum.Material.Glass)
	back.Transparency = 0.4
	for _, sx in ipairs({ -1, 1 }) do
		deco(model, "ShelterPost", Vector3.new(0.4, 8.4, 0.4), cf * CFrame.new(sx * 4.8, 4.2, 2), rgb(60, 70, 90), Enum.Material.Metal)
	end
	-- an ad panel on one side and the stop sign
	local ad = deco(model, "AdPanel", Vector3.new(0.3, 5, 3.6), cf * CFrame.new(-5, 4.2, 0.1), rgb(250, 250, 250), Enum.Material.Neon)
	MapKit.signText(ad, Enum.NormalId.Right, "🏙️ AI CITY\nVote!", rgb(30, 40, 80))
	local seat = Streets.bench(model, cf * CFrame.new(1, 0, 1), nil)
	deco(model, "StopPole", Vector3.new(0.3, 10, 0.3), cf * CFrame.new(6, 5, -1), rgb(60, 60, 66), Enum.Material.Metal)
	local sign = deco(model, "StopSign", Vector3.new(2.6, 2.6, 0.2), cf * CFrame.new(6, 9.4, -1), rgb(30, 110, 200))
	MapKit.signText(sign, Enum.NormalId.Front, "🚌", WHITE)
	local label = deco(model, "StopName", Vector3.new(8, 1, 0.1), cf * CFrame.new(0, 7.8, 1.9), rgb(30, 40, 60))
	MapKit.signText(label, Enum.NormalId.Front, "BUS · " .. streetName, WHITE, Enum.Font.GothamBold)
	return seat
end

-- more street detail: bike racks, newspaper boxes, planters, bollards, meters
local function bikeRack(parent, pos, along, rng)
	local cf = CFrame.lookAt(pos, pos + along)
	for k = -2, 2 do
		-- an upside-down U of steel tube
		for _, dz in ipairs({ -0.55, 0.55 }) do
			deco(parent, "BikeRackPost", Vector3.new(0.16, 1.8, 0.16), cf * CFrame.new(k * 0.9, 0.9, dz), rgb(120, 124, 132), Enum.Material.Metal)
		end
		MapKit.cylinder(parent, "BikeRackTop", 1.26, 0.16, cf * CFrame.new(k * 0.9, 1.8, 0) * CFrame.Angles(0, math.rad(90), 0), rgb(120, 124, 132), Enum.Material.Metal)
	end
	deco(parent, "BikeRackBar", Vector3.new(4, 0.18, 0.18), cf * CFrame.new(0, 0.2, 0), rgb(120, 124, 132), Enum.Material.Metal)
	-- a bike or two
	for n = 1, rng:NextInteger(0, 2) do
		local bx = cf * CFrame.new(-1.8 + n * 1.8, 1, 0.2)
		local color = ({ rgb(200, 50, 50), rgb(40, 120, 200), rgb(250, 200, 50), rgb(40, 160, 90) })[rng:NextInteger(1, 4)]
		for _, dz in ipairs({ -0.9, 0.9 }) do
			MapKit.cylinder(parent, "BikeWheel", 0.12, 1.5, bx * CFrame.new(0, 0, dz), rgb(30, 30, 32), Enum.Material.Rubber)
		end
		deco(parent, "BikeFrame", Vector3.new(0.15, 0.15, 1.9), bx * CFrame.new(0, 0.4, 0), color, Enum.Material.Metal)
		deco(parent, "BikeSeat", Vector3.new(0.3, 0.12, 0.6), bx * CFrame.new(0, 0.9, 0.4), rgb(30, 30, 32))
	end
end
local function newspaperBoxes(parent, pos, facing)
	local cf = CFrame.lookAt(pos, pos + facing)
	for k, color in ipairs({ rgb(200, 40, 40), rgb(40, 90, 170), rgb(240, 200, 40) }) do
		local box = deco(parent, "NewspaperBox", Vector3.new(1.4, 2.6, 1.3), cf * CFrame.new((k - 2) * 1.6, 1.3, 0), color, Enum.Material.Metal)
		deco(parent, "NewspaperWindow", Vector3.new(1, 0.8, 0.05), box.CFrame * CFrame.new(0, 0.5, -0.66), rgb(230, 230, 220), Enum.Material.Glass)
	end
end
local function planter(parent, pos, rng)
	deco(parent, "Planter", Vector3.new(3.2, 1.6, 3.2), CFrame.new(pos + Vector3.new(0, 0.8, 0)), rgb(150, 140, 128), Enum.Material.Concrete)
	for k = 0, 3 do
		MapKit.ball(parent, "PlanterFlowers", 1.2, CFrame.new(pos + Vector3.new((k % 2 - 0.5) * 1.2, 1.9, (math.floor(k / 2) - 0.5) * 1.2)), MapKit.FLOWERS[rng:NextInteger(1, #MapKit.FLOWERS)], Enum.Material.SmoothPlastic)
	end
end
local function bollards(parent, corner, dir)
	for k = 1, 3 do
		MapKit.cylinder(parent, "Bollard", 2.4, 0.7, CFrame.new(corner + dir * (k * 1.6) + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(60, 62, 70), Enum.Material.Metal)
	end
end
local function parkingMeter(parent, pos)
	deco(parent, "MeterPost", Vector3.new(0.25, 3.4, 0.25), CFrame.new(pos + Vector3.new(0, 1.7, 0)), rgb(80, 84, 92), Enum.Material.Metal)
	deco(parent, "Meter", Vector3.new(0.7, 1, 0.5), CFrame.new(pos + Vector3.new(0, 3.8, 0)), rgb(110, 120, 130), Enum.Material.Metal)
	deco(parent, "MeterDisplay", Vector3.new(0.4, 0.3, 0.05), CFrame.new(pos + Vector3.new(0, 3.95, -0.27)), rgb(160, 220, 170), Enum.Material.Neon)
end

local function streetSign(parent, pos, streetName, avenueName)
	deco(parent, "SignPole", Vector3.new(0.35, 10, 0.35), CFrame.new(pos + Vector3.new(0, 5, 0)), rgb(60, 64, 70), Enum.Material.Metal)
	local s1 = deco(parent, "StreetBlade", Vector3.new(6, 1, 0.15), CFrame.new(pos + Vector3.new(0, 9.4, 0)), rgb(30, 110, 60))
	MapKit.signText(s1, Enum.NormalId.Front, streetName, WHITE, Enum.Font.GothamBold)
	MapKit.signText(s1, Enum.NormalId.Back, streetName, WHITE, Enum.Font.GothamBold)
	local s2 = deco(parent, "AvenueBlade", Vector3.new(0.15, 1, 6), CFrame.new(pos + Vector3.new(0, 10.5, 0)), rgb(30, 110, 60))
	MapKit.signText(s2, Enum.NormalId.Left, avenueName, WHITE, Enum.Font.GothamBold)
	MapKit.signText(s2, Enum.NormalId.Right, avenueName, WHITE, Enum.Font.GothamBold)
end

-- Traffic light facing `dir` (the direction the drivers look from). The client
-- cycles the colors (CollectionService tag "TrafficLight"; Axis = "X" or "Z").
local function trafficLight(parent, pos, dir, axis)
	local cf = CFrame.lookAt(pos, pos + dir)
	deco(parent, "TLPole", Vector3.new(0.5, 11, 0.5), cf * CFrame.new(0, 5.5, 0), rgb(40, 44, 50), Enum.Material.Metal)
	local housing = deco(parent, "TLHousing", Vector3.new(1.4, 4, 1.2), cf * CFrame.new(0, 10, -0.9), rgb(30, 32, 36), Enum.Material.Metal)
	local model = Instance.new("Model")
	model.Name = "TrafficLight"
	model:SetAttribute("Axis", axis)
	model.Parent = parent
	housing.Parent = model
	for k, name in ipairs({ "Red", "Yellow", "Green" }) do
		local l = deco(model, name, Vector3.new(0.9, 0.9, 0.2), cf * CFrame.new(0, 11.3 - (k - 1) * 1.3, -1.55), rgb(60, 60, 60), Enum.Material.SmoothPlastic)
		l.Shape = Enum.PartType.Block
	end
	MapKit.tag(model, "TrafficLight")
end

local CAR_COLORS = { rgb(214, 60, 60), rgb(60, 116, 214), rgb(236, 236, 236), rgb(36, 36, 40), rgb(246, 196, 60), rgb(80, 176, 110), rgb(150, 150, 156), rgb(120, 60, 150) }
Streets.CAR_COLORS = CAR_COLORS

function Streets.car(parent, cf, color, style)
	local m = Instance.new("Model")
	m.Name = "Car"
	m.Parent = parent
	local long = if style == "van" then 13 else 11
	local tall = if style == "van" then 3.4 else 2.2
	deco(m, "Body", Vector3.new(6, tall, long), cf * CFrame.new(0, 1.2 + tall / 2, 0), color, Enum.Material.SmoothPlastic, { Reflectance = 0.12 })
	deco(m, "Cabin", Vector3.new(5.4, 2, 5.6), cf * CFrame.new(0, 2.3 + tall, if style == "van" then 1.5 else 0.6), color:Lerp(BLACK, 0.08))
	deco(m, "Windshield", Vector3.new(5, 1.7, 0.2), cf * CFrame.new(0, 2.3 + tall, (if style == "van" then 1.5 else 0.6) - 2.85), MapKit.GLASS, Enum.Material.Glass, { Transparency = 0.2 })
	deco(m, "RearWindow", Vector3.new(5, 1.5, 0.2), cf * CFrame.new(0, 2.3 + tall, (if style == "van" then 1.5 else 0.6) + 2.85), MapKit.GLASS, Enum.Material.Glass, { Transparency = 0.2 })
	for _, sx in ipairs({ -1, 1 }) do
		deco(m, "SideWindow", Vector3.new(0.2, 1.5, 4.6), cf * CFrame.new(sx * 2.72, 2.3 + tall, if style == "van" then 1.5 else 0.6), MapKit.GLASS, Enum.Material.Glass, { Transparency = 0.25 })
		for _, sz in ipairs({ -1, 1 }) do
			MapKit.cylinder(m, "Wheel", 1, 2.4, cf * CFrame.new(sx * 2.8, 1.2, sz * (long / 2 - 2.2)), rgb(22, 22, 25), Enum.Material.Rubber)
			MapKit.cylinder(m, "Hubcap", 1.05, 1.2, cf * CFrame.new(sx * 2.8, 1.2, sz * (long / 2 - 2.2)), rgb(190, 190, 196), Enum.Material.Metal)
		end
		local head = deco(m, "Headlight", Vector3.new(1.2, 0.6, 0.2), cf * CFrame.new(sx * 2, 1.9 + tall / 2, -long / 2 - 0.05), rgb(255, 250, 220), Enum.Material.Neon)
		deco(m, "Taillight", Vector3.new(1.2, 0.5, 0.2), cf * CFrame.new(sx * 2, 1.9 + tall / 2, long / 2 + 0.05), rgb(200, 30, 30), Enum.Material.Neon)
		head.Name = "Headlight"
	end
	deco(m, "Bumper", Vector3.new(6.2, 0.6, 0.4), cf * CFrame.new(0, 1.3, -long / 2 - 0.1), rgb(60, 60, 64), Enum.Material.Metal)
	deco(m, "Bumper", Vector3.new(6.2, 0.6, 0.4), cf * CFrame.new(0, 1.3, long / 2 + 0.1), rgb(60, 60, 64), Enum.Material.Metal)
	return m
end

--------------------------------------------------------------------------------
-- Build every street
--------------------------------------------------------------------------------
function Streets.build(parent, rng, blockKind)
	local roads = Instance.new("Folder")
	roads.Name = "Streets"
	roads.Parent = parent
	local furniture = Instance.new("Folder")
	furniture.Name = "StreetFurniture"
	furniture.Parent = parent
	local length = EXTENT * 2 + ROAD
	local busSeats, busStops = {}, {}

	for k = -N - 1, N do
		local line = (k + 0.5) * SPACING
		local st = part(roads, "Street", Vector3.new(length, 0.2, ROAD), CFrame.new(0, 0, line), MapKit.ASPHALT, Enum.Material.Asphalt)
		st:SetAttribute("StreetName", Streets.streetName(k))
		local av = part(roads, "Avenue", Vector3.new(ROAD, 0.2, length), CFrame.new(line, 0, 0), MapKit.ASPHALT, Enum.Material.Asphalt)
		av:SetAttribute("StreetName", Streets.avenueName(k))
		-- dashed yellow center lines and white edge lines between intersections
		for s = -N, N do
			for d = -3, 3 do
				local off = d * 11
				deco(roads, "LaneDash", Vector3.new(6, 0.22, 0.35), CFrame.new(s * SPACING + off, 0.01, line), rgb(245, 205, 70))
				deco(roads, "LaneDash", Vector3.new(0.35, 0.22, 6), CFrame.new(line, 0.01, s * SPACING + off), rgb(245, 205, 70))
			end
			for _, e in ipairs({ -1, 1 }) do
				deco(roads, "EdgeLine", Vector3.new(SPACING - ROAD - 2, 0.21, 0.25), CFrame.new(s * SPACING, 0.01, line + e * (ROAD / 2 - 6.9)), rgb(235, 235, 235))
				deco(roads, "EdgeLine", Vector3.new(0.25, 0.21, SPACING - ROAD - 2), CFrame.new(line + e * (ROAD / 2 - 6.9), 0.01, s * SPACING), rgb(235, 235, 235))
			end
			-- a manhole in each road segment
			MapKit.disc(roads, "Manhole", 0.24, 3, Vector3.new(s * SPACING + 20, 0.01, line + 3), rgb(70, 70, 74), Enum.Material.DiamondPlate)
		end
	end

	-- crosswalks and stop lines at every intersection; traffic lights downtown
	for a = -N - 1, N do
		for b = -N - 1, N do
			local x, z = (a + 0.5) * SPACING, (b + 0.5) * SPACING
			local downtown = math.abs(a + 0.5) <= 2 and math.abs(b + 0.5) <= 2
			local stripes = math.floor((ROAD / 2 - 1) / 2.1)
			for s = -stripes, stripes do
				for _, side in ipairs({ -1, 1 }) do
					deco(roads, "Crosswalk", Vector3.new(1.2, 0.24, 5), CFrame.new(x + s * 2.1, 0.02, z + side * (ROAD / 2 + 2.8)), WHITE)
					deco(roads, "Crosswalk", Vector3.new(5, 0.24, 1.2), CFrame.new(x + side * (ROAD / 2 + 2.8), 0.02, z + s * 2.1), WHITE)
				end
			end
			if downtown then
				trafficLight(furniture, Vector3.new(x - ROAD / 2 - 1.5, LOT_Y, z - ROAD / 2 - 1.5), Vector3.new(0, 0, 1), "Z")
				trafficLight(furniture, Vector3.new(x + ROAD / 2 + 1.5, LOT_Y, z + ROAD / 2 + 1.5), Vector3.new(0, 0, -1), "Z")
				trafficLight(furniture, Vector3.new(x + ROAD / 2 + 1.5, LOT_Y, z - ROAD / 2 - 1.5), Vector3.new(-1, 0, 0), "X")
				trafficLight(furniture, Vector3.new(x - ROAD / 2 - 1.5, LOT_Y, z + ROAD / 2 + 1.5), Vector3.new(1, 0, 0), "X")
			end
			if math.abs(a) <= N and math.abs(b) <= N then
				streetSign(furniture, Vector3.new(x + ROAD / 2 + 1.6, LOT_Y, z - ROAD / 2 - 1.6), Streets.streetName(b), Streets.avenueName(a))
			end
		end
	end

	-- sidewalks: a raised slab with a darker curb for every block, lamps at the
	-- corners, and street furniture along the edges
	local walks = Instance.new("Folder")
	walks.Name = "Sidewalks"
	walks.Parent = parent
	for i = -N, N do
		for j = -N, N do
			local c = Vector3.new(i * SPACING, LOT_Y, j * SPACING)
			part(walks, "Sidewalk", Vector3.new(BLOCK, LOT_Y, BLOCK), CFrame.new(c.X, LOT_Y / 2, c.Z), MapKit.CONCRETE, Enum.Material.Pavement)
			for _, e in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
				local sizeCurb = if e[1] == 0 then Vector3.new(BLOCK, LOT_Y + 0.05, 0.6) else Vector3.new(0.6, LOT_Y + 0.05, BLOCK)
				deco(walks, "Curb", sizeCurb, CFrame.new(c.X + e[1] * (HALF - 0.3), (LOT_Y + 0.05) / 2, c.Z + e[2] * (HALF - 0.3)), MapKit.CURB, Enum.Material.Concrete)
			end
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					Streets.lamp(furniture, c + Vector3.new(sx * (HALF - 1.2), 0, sz * (HALF - 1.2)), Vector3.new(sx, 0, sz))
				end
			end
			local kind = blockKind(i, j)
			local downtown = math.abs(i) <= 2 and math.abs(j) <= 2
			-- one hydrant per block, trash cans downtown
			hydrant(furniture, c + Vector3.new(HALF - 2, 0, -HALF + 12))
			if downtown then
				trashCan(furniture, c + Vector3.new(-HALF + 2, 0, HALF - 14))
				trashCan(furniture, c + Vector3.new(HALF - 14, 0, HALF - 2))
				-- the busy sidewalks: bike racks, newspaper boxes, planters,
				-- bollards at the corners and parking meters along the curb
				bikeRack(furniture, c + Vector3.new(-HALF + 3, 0, -8), Vector3.new(0, 0, 1), rng)
				newspaperBoxes(furniture, c + Vector3.new(8, 0, HALF - 2.2), Vector3.new(0, 0, 1))
				planter(furniture, c + Vector3.new(HALF - 3, 0, 10), rng)
				planter(furniture, c + Vector3.new(-10, 0, -HALF + 3), rng)
				bollards(furniture, c + Vector3.new(HALF - 1, 0, HALF - 1), Vector3.new(-1, 0, 0))
				bollards(furniture, c + Vector3.new(-HALF + 1, 0, -HALF + 1), Vector3.new(1, 0, 0))
				for n = -2, 2 do
					if n ~= 0 then
						parkingMeter(furniture, c + Vector3.new(n * 9, 0, -HALF + 0.9))
					end
				end
				-- sidewalk trees in grates along two sides
				for n = -1, 1 do
					if n ~= 0 then
						for _, e in ipairs({ { n * 22, -(HALF - 2.4) }, { -(HALF - 2.4), n * 22 } }) do
							local p = c + Vector3.new(e[1], 0, e[2])
							deco(furniture, "TreeGrate", Vector3.new(3.4, 0.1, 3.4), CFrame.new(p + Vector3.new(0, 0.05, 0)), rgb(60, 60, 64), Enum.Material.DiamondPlate)
							Streets.tree(furniture, p, 0.75, rng)
						end
					end
				end
			elseif kind == "Houses" and rng:NextNumber() < 0.7 then
				for n = -1, 1, 2 do
					Streets.tree(furniture, c + Vector3.new(n * 30, 0, HALF - 2.4), rng:NextNumber(0.7, 0.9), rng)
				end
				planter(furniture, c + Vector3.new(-HALF + 3, 0, HALF - 3), rng)
			end
		end
	end

	-- bus stops along the main avenues
	for _, pos in ipairs({ { -1, -1 }, { 1, 1 }, { -2, 1 }, { 2, -1 }, { -1, 3 }, { 1, -3 }, { 3, 2 }, { -3, -2 } }) do
		local i, j = pos[1], pos[2]
		local c = Vector3.new(i * SPACING, LOT_Y, j * SPACING)
		local cf = CFrame.lookAt(c + Vector3.new(12, 0, -HALF + 2.8), c + Vector3.new(12, 0, -HALF - 5))
		local seat = busStop(furniture, cf, Streets.streetName(j - 1))
		table.insert(busSeats, seat)
		-- where the bus pulls up: in the lane beside the shelter
		table.insert(busStops, Vector3.new(c.X + 12, 0, j * SPACING - SPACING / 2 + MapKit.LANE))
	end

	-- parked cars along the curbs
	local cars = Instance.new("Folder")
	cars.Name = "ParkedCars"
	cars.Parent = parent
	for _ = 1, 70 do
		local horizontal = rng:NextNumber() < 0.5
		local k = rng:NextInteger(-N - 1, N)
		local line = (k + 0.5) * SPACING
		local along = rng:NextInteger(-N, N) * SPACING + rng:NextNumber(-26, 26)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local offset = side * (ROAD / 2 - 3.6)
		local cf
		if horizontal then
			cf = CFrame.new(along, 0.1, line + offset) * CFrame.Angles(0, math.rad(if side > 0 then 90 else -90), 0)
		else
			cf = CFrame.new(line + offset, 0.1, along) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
		end
		Streets.car(cars, cf, CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)], if rng:NextNumber() < 0.15 then "van" else nil)
	end
	return { BusSeats = busSeats, BusStops = busStops }
end

return Streets
