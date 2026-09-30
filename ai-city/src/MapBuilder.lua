-- MapBuilder (ModuleScript) — ServerScriptService.Modules.MapBuilder
-- Builds AI City: a 9x9 grid of city blocks around a central plaza, with
-- streets, a landscape of hills, a lake and mountains, and every building
-- furnished with spots where people work, shop, eat, play and sleep.
--
--   local map = MapBuilder.Build()   -- builds once; later calls return the same map
--   map.Places[id]                   -- { Id, Label, Kind, Door, Inside, Spots, WorkSpots, Buildings, ... }
--   map.Homes[i]                     -- { Address, Door, Inside, Capacity, Kind, Spots, Building, Floor }
--   map.Spots                        -- every spot: { CFrame, Action, Role, Floor, Place, Building, Seat }
--   map.HobbySpots[hobby]            -- spots for outdoor hobbies
--   map.Route(fromPos, toPos)        -- sidewalk waypoints (crossing at corners)
--   map.SoccerFields, map.JoggingLoops, map.SpeechSpot, map.StageCFrame, map.BallotBox, map.Jail
--   MapBuilder.SetNight(on)          -- street lamps, windows, porch lights, neon
--   MapBuilder.SetNews(text)         -- the plaza's news board
--   MapBuilder.FurnishHome(home)     -- furnish a house when a family moves in

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Modules = script.Parent
local MapKit = require(Modules:WaitForChild("MapKit"))
local Buildings = require(Modules:WaitForChild("Buildings"))
local Interiors = require(Modules:WaitForChild("Interiors"))
local Streets = require(Modules:WaitForChild("Streets"))
local Landscape = require(Modules:WaitForChild("Landscape"))
local Places = require(Modules:WaitForChild("Places"))

local MapBuilder = {}

local SPACING, HALF, SIDEWALK, RING, N, EXTENT, LOT_Y = MapKit.SPACING, MapKit.HALF, MapKit.SIDEWALK, MapKit.RING, MapKit.N, MapKit.EXTENT, MapKit.LOT_Y
local Registry = MapKit.Registry

--------------------------------------------------------------------------------
-- The city plan: what goes on each block. i = west(-) to east(+),
-- j = north(-) to south(+). The plaza is the center block. Anything not
-- listed gets houses (or suburbs on the outer ring).
--------------------------------------------------------------------------------
local PLAN = {
	-- downtown
	["0,0"] = "Plaza",
	["0,-1"] = "TownHall",
	["1,-1"] = "Bank",
	["-1,-1"] = "Police",
	["-1,0"] = "BakeryCafe",
	["1,0"] = "MarketPharmacy",
	["-1,1"] = "LibraryRestaurant",
	["0,1"] = "School",
	["1,1"] = "Park",
	-- around downtown
	["0,-2"] = "Hotel",
	["-1,-2"] = "Offices",
	["1,-2"] = "Offices",
	["-2,-2"] = "FireStation",
	["2,-2"] = "Hospital",
	["-2,-1"] = "Apartments:Sunset Towers",
	["2,-1"] = "Cinema",
	["-2,0"] = "ShopsWest",
	["2,0"] = "ShopsEast",
	["-2,1"] = "Apartments:Maple Court",
	["2,1"] = "Gym",
	["0,2"] = "SportsField",
	["-1,2"] = "MiddleSchool",
	["1,2"] = "HighSchool",
	["-2,2"] = "Daycare",
	["2,2"] = "CommunityCenter",
	-- the next ring
	["0,-3"] = "Museum",
	["-1,-3"] = "Apartments:Oak Terrace",
	["1,-3"] = "Apartments:Birch Lofts",
	["3,-3"] = "PostOffice",
	["-3,0"] = "ArcadeDiner",
	["3,-1"] = "GasStation",
	["3,0"] = "Factory",
	["3,1"] = "Warehouse",
	["-3,3"] = "WillowPark",
	-- woods on the outskirts
	["4,4"] = "Woods",
	["-4,4"] = "Woods",
	["4,-4"] = "Woods",
	["-4,-4"] = "Woods",
	["-4,1"] = "Woods",
	["4,-2"] = "Woods",
	-- the outer ring: big suburban lots, with woods at the corners
	["5,5"] = "Woods",
	["-5,5"] = "Woods",
	["5,-5"] = "Woods",
	["-5,-5"] = "Woods",
	["0,5"] = "Woods",
	["5,0"] = "Woods",
}
MapBuilder.PLAN = PLAN

local function kindAt(i, j)
	local entry = PLAN[i .. "," .. j]
	if entry then
		return (string.match(entry, "^([^:]+)"))
	end
	return if math.max(math.abs(i), math.abs(j)) >= N then "Suburb" else "Houses"
end

--------------------------------------------------------------------------------
-- Map state
--------------------------------------------------------------------------------
local map

local function blockCenter(i, j)
	return Vector3.new(i * SPACING, LOT_Y, j * SPACING)
end

local function rightOf(face)
	return Vector3.new(-face.Z, 0, face.X)
end

-- buildings face the road toward the city center
local function faceFor(i, j)
	if math.abs(j) >= math.abs(i) and j ~= 0 then
		return Vector3.new(0, 0, if j > 0 then -1 else 1)
	elseif i ~= 0 then
		return Vector3.new(if i > 0 then -1 else 1, 0, 0)
	end
	return Vector3.new(0, 0, 1)
end

-- where a building's center goes so its front sits behind the sidewalk
local function frontLot(c, face, depth, lateral)
	return c + face * (HALF - SIDEWALK - 5 - depth / 2) + rightOf(face) * (lateral or 0)
end

local function labelFor(id)
	local info = Config.PlaceById and Config.PlaceById[id]
	if info then
		return info.emoji .. " " .. info.label
	end
	return id
end

--------------------------------------------------------------------------------
-- Walking network: sidewalk corners of every block, joined around each block
-- and across the road at every corner. Doors hook onto the sidewalk in front.
--------------------------------------------------------------------------------
local nodes, edges = {}, {}
local cornerIds = {}

local function addNode(pos)
	table.insert(nodes, pos)
	edges[#nodes] = {}
	return #nodes
end

local function link(a, b)
	local d = (nodes[a] - nodes[b]).Magnitude
	edges[a][b] = d
	edges[b][a] = d
end

local function corner(i, j, sx, sz)
	return cornerIds[i .. "," .. j .. "," .. sx .. "," .. sz]
end

local function buildNetwork()
	for i = -N, N do
		for j = -N, N do
			local c = blockCenter(i, j)
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					cornerIds[i .. "," .. j .. "," .. sx .. "," .. sz] = addNode(c + Vector3.new(sx * RING, 0, sz * RING))
				end
			end
		end
	end
	for i = -N, N do
		for j = -N, N do
			link(corner(i, j, -1, -1), corner(i, j, 1, -1))
			link(corner(i, j, -1, 1), corner(i, j, 1, 1))
			link(corner(i, j, -1, -1), corner(i, j, -1, 1))
			link(corner(i, j, 1, -1), corner(i, j, 1, 1))
			if i < N then
				link(corner(i, j, 1, -1), corner(i + 1, j, -1, -1))
				link(corner(i, j, 1, 1), corner(i + 1, j, -1, 1))
			end
			if j < N then
				link(corner(i, j, -1, 1), corner(i, j + 1, -1, -1))
				link(corner(i, j, 1, 1), corner(i, j + 1, 1, -1))
			end
		end
	end
end

-- Hooks a door onto the sidewalk of block (i, j) on the side it faces.
local function hookDoor(i, j, door, face)
	local c = blockCenter(i, j)
	local onWalk, a, b
	if math.abs(face.X) > 0.5 then
		local sx = if face.X > 0 then 1 else -1
		onWalk = Vector3.new(c.X + sx * RING, LOT_Y, math.clamp(door.Z, c.Z - RING, c.Z + RING))
		a, b = corner(i, j, sx, -1), corner(i, j, sx, 1)
	else
		local sz = if face.Z > 0 then 1 else -1
		onWalk = Vector3.new(math.clamp(door.X, c.X - RING, c.X + RING), LOT_Y, c.Z + sz * RING)
		a, b = corner(i, j, -1, sz), corner(i, j, 1, sz)
	end
	local walk = addNode(onWalk)
	link(walk, a)
	link(walk, b)
	local doorNode = addNode(Vector3.new(door.X, LOT_Y, door.Z))
	link(doorNode, walk)
	return doorNode
end

local function flatDist(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

local function nearestNode(pos)
	local best, bestD = nil, math.huge
	for id, p in ipairs(nodes) do
		local d = flatDist(p, pos)
		if d < bestD then
			best, bestD = id, d
		end
	end
	return best
end

-- Shortest sidewalk route (A*, cached). Returns waypoints ending at toPos.
local routeCache = {}
local function route(fromPos, toPos)
	local start, goal = nearestNode(fromPos), nearestNode(toPos)
	local key = start .. ">" .. goal
	local cached = routeCache[key]
	local path
	if cached then
		path = table.clone(cached)
	else
		local g, f, prev, open, closed = { [start] = 0 }, { [start] = flatDist(nodes[start], nodes[goal]) }, {}, { [start] = true }, {}
		while true do
			local current, best = nil, math.huge
			for id in pairs(open) do
				if f[id] < best then
					current, best = id, f[id]
				end
			end
			if not current or current == goal then
				break
			end
			open[current] = nil
			closed[current] = true
			for other, d in pairs(edges[current]) do
				if not closed[other] then
					local ng = g[current] + d
					if not g[other] or ng < g[other] then
						g[other] = ng
						f[other] = ng + flatDist(nodes[other], nodes[goal])
						prev[other] = current
						open[other] = true
					end
				end
			end
		end
		path = {}
		local id = goal
		while id do
			table.insert(path, 1, nodes[id])
			id = prev[id]
		end
		if path[1] ~= nodes[start] then
			path = { nodes[start] }
		end
		routeCache[key] = table.clone(path)
	end
	table.insert(path, toPos)
	return path
end

--------------------------------------------------------------------------------
-- The ctx object the place builders use to register things
--------------------------------------------------------------------------------
local spotCount = 0
local function registerSpot(spot, placeId, building)
	spotCount += 1
	spot.Id = spotCount
	spot.Place = spot.Place or placeId
	spot.Building = spot.Building or building
	spot.Floor = spot.Floor or 1
	table.insert(map.Spots, spot)
	return spot
end

local function newPlace(id, model, i, j)
	local place = map.Places[id]
	if not place then
		place = {
			Id = id,
			Label = labelFor(id),
			Kind = (Config.PlaceById and Config.PlaceById[id] and Config.PlaceById[id].kind) or "fun",
			Model = model,
			Spots = {},
			WorkSpots = {},
			Buildings = {},
			Block = Vector2.new(i, j),
		}
		map.Places[id] = place
		table.insert(map.PlaceList, place)
	end
	return place
end

local ctx = {}
ctx.blockCenter = blockCenter
ctx.faceFor = faceFor
ctx.frontLot = frontLot
ctx.label = labelFor
ctx.hookDoor = hookDoor

function ctx.lot(parent, c, color, material)
	return MapKit.part(parent, "Lot", Vector3.new(MapKit.BLOCK - SIDEWALK * 2, 0.1, MapKit.BLOCK - SIDEWALK * 2), CFrame.new(c + Vector3.new(0, 0.05, 0)), color, material)
end

-- a building that's (part of) a place
function ctx.place(id, b, i, j, face, spots, extra)
	local place = newPlace(id, b.Model, i, j)
	b.Node = hookDoor(i, j, b.Door, face)
	b.PlaceId = id
	b.Model:SetAttribute("PlaceId", id)
	table.insert(place.Buildings, b)
	if not place.Door then
		place.Door, place.Inside, place.Node, place.Building = b.Door, b.Inside, b.Node, b
	end
	for _, s in ipairs(spots or {}) do
		registerSpot(s, id, b)
		table.insert(place.Spots, s)
		if s.Role == "work" then
			table.insert(place.WorkSpots, s.CFrame.Position)
		end
	end
	if b.Elevator then
		table.insert(map.Elevators, b)
	end
	if extra then
		for k, v in pairs(extra) do
			place[k] = v
		end
	end
	return place
end

-- an outdoor place (plaza, park, sports field, woods)
function ctx.outdoor(id, model, i, j, door, face, spots)
	local place = newPlace(id, model, i, j)
	place.Door = door
	place.Inside = door
	place.Outdoor = true
	place.Node = hookDoor(i, j, door, face)
	model:SetAttribute("PlaceId", id)
	for _, s in ipairs(spots or {}) do
		registerSpot(s, id, nil)
		table.insert(place.Spots, s)
		if s.Role == "work" then
			table.insert(place.WorkSpots, s.CFrame.Position)
		end
	end
	return place
end

function ctx.hobby(name, spot)
	map.HobbySpots[name] = map.HobbySpots[name] or {}
	table.insert(map.HobbySpots[name], spot)
	if not spot.Id then
		registerSpot(spot, spot.Place, nil)
	end
end

function ctx.addHome(home)
	home.Index = #map.Homes + 1
	for _, s in ipairs(home.Spots or {}) do
		registerSpot(s, nil, home.Building)
		s.Home = home.Index
	end
	table.insert(map.Homes, home)
	return home
end

-- Houses along a block. slots: list of { sx, sz } (sx = -1/1 left/right half,
-- 0 = middle; sz = -1/1 which street the house faces). big = suburb lots.
local houseNumbers = {}
function ctx.houseRow(parent, i, j, rng, slots, big)
	local c = blockCenter(i, j)
	local model = Instance.new("Model")
	model.Name = "Houses"
	model.Parent = parent
	ctx.lot(model, c, MapKit.GRASS, Enum.Material.Grass)
	for _, slot in ipairs(slots) do
		local sx, sz = slot[1], slot[2]
		local face = Vector3.new(0, 0, sz)
		local styles = if big then { "twostory", "bungalow", "modern" } else { "cottage", "twostory", "modern", "bungalow", "cottage" }
		local style = styles[rng:NextInteger(1, #styles)]
		-- town lots: four houses a block, 36-42 studs wide; suburban lots: one
		-- house per street, 56-64 wide and 38 deep, with a garage
		local scale = if big then 2 else 1.3
		local depth = Buildings.HouseDepth(scale)
		local yard = if big then 8 else 9 -- front yard between the sidewalk and the house
		local depthZ = HALF - SIDEWALK - yard - depth / 2
		local center = c + Vector3.new(sx * 25, 0, sz * depthZ)
		local garageSide = if big then 1 else nil
		local b = Buildings.house(model, center, face, style, rng, garageSide, scale)
		local at = b.At
		-- the front of the lot (the sidewalk edge), in the house's own space
		local frontZ = -(HALF - SIDEWALK - depthZ)
		-- front path, mailbox with the house number, and a hedge or picket fence
		MapKit.deco(b.Model, "Path", Vector3.new(3, 0.12, -frontZ - b.D / 2), at(0, 0.12, (frontZ - b.D / 2) / 2), MapKit.rgb(200, 195, 185), Enum.Material.Slate)
		local lineZ = c.Z + sz * SPACING / 2
		local k = math.floor(lineZ / SPACING)
		local street = Streets.streetName(k)
		houseNumbers[street] = (houseNumbers[street] or 0) + 2
		local number = houseNumbers[street] - (if sx < 0 then 1 else 0)
		local mailbox = MapKit.deco(b.Model, "Mailbox", Vector3.new(1.4, 1.4, 2), at(4, 3.2, frontZ + 1.4), MapKit.rgb(60, 90, 160))
		MapKit.deco(b.Model, "MailboxPost", Vector3.new(0.4, 2.6, 0.4), at(4, 1.3, frontZ + 1.4), MapKit.WOOD, Enum.Material.Wood)
		MapKit.signText(mailbox, Enum.NormalId.Left, tostring(number), MapKit.WHITE)
		MapKit.signText(mailbox, Enum.NormalId.Right, tostring(number), MapKit.WHITE)
		if rng:NextNumber() < 0.5 then
			for _, px in ipairs({ -1, 1 }) do
				local hedge = MapKit.deco(b.Model, "Hedge", Vector3.new(7, 2.6, 1.6), at(px * 6.5, 1.3, frontZ + 0.9), MapKit.LEAVES[3], Enum.Material.Grass)
				hedge:SetAttribute("HideName", "a hedge")
				MapKit.tag(hedge, "HideSpot")
			end
		else
			for n = -5, 5 do
				if math.abs(n) > 1 then
					MapKit.deco(b.Model, "Picket", Vector3.new(0.4, 2.4, 0.3), at(n * 1.1, 1.2, frontZ + 0.9), MapKit.WHITE, Enum.Material.Wood)
				end
			end
			MapKit.deco(b.Model, "FenceRail", Vector3.new(12, 0.3, 0.25), at(0, 1.8, frontZ + 0.9), MapKit.WHITE, Enum.Material.Wood)
		end
		if rng:NextNumber() < 0.6 then
			Streets.tree(model, at(-9, 0, (frontZ - b.D / 2) / 2).Position, rng:NextNumber(0.7, 1), rng)
		end
		if big then
			-- a backyard vegetable garden
			MapKit.deco(b.Model, "BackyardGarden", Vector3.new(8, 0.6, 2), at(-6, 0.3, b.D / 2 + 1.5), MapKit.rgb(110, 76, 50), Enum.Material.Ground)
			for n = 0, 5 do
				MapKit.ball(b.Model, "Veg", 1, at(-9 + n * 1.2, 0.9, b.D / 2 + 1.5), MapKit.LEAVES[n % 4 + 1])
			end
		end
		if style == "twostory" and b.GarageX and rng:NextNumber() < 0.7 then
			-- parked on the driveway in front of the garage
			Streets.car(b.Model, at(b.GarageX or (b.W / 2 + 5.5), 0.1, -12), Streets.CAR_COLORS[rng:NextInteger(1, #Streets.CAR_COLORS)])
		end
		local home = ctx.addHome({
			Model = b.Model,
			Building = b,
			Door = b.Door,
			Inside = b.Inside,
			Address = number .. " " .. street,
			Capacity = if b.Floors > 1 then 6 else 4,
			Kind = "house",
			Floor = 1,
			Spots = {},
			Furnished = false,
		})
		home.Node = hookDoor(i, j, b.Door, face)
		b.Model.Name = "House " .. home.Address
		b.Model:SetAttribute("Address", home.Address)
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
-- The bigger blocks leave open pavement around buildings: the empty corners
-- become little pocket parks (grass, a tree, a bench, flowers).
local function pocketParks(parent, i, j, before, rng)
	local c = blockCenter(i, j)
	local kids = parent:GetChildren()
	local boxes = {}
	for k = before + 1, #kids do
		for _, p in ipairs(kids[k]:GetDescendants()) do
			if p:IsA("BasePart") and p.Size.X < 80 and p.Size.Z < 80 and p.Name ~= "Lot" then
				local pos, half = p.Position, p.Size / 2
				local r = math.max(half.X, half.Z)
				table.insert(boxes, { pos.X - r, pos.X + r, pos.Z - r, pos.Z + r })
			end
		end
	end
	local size = 16
	local inset = HALF - SIDEWALK - size / 2 - 1
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = c.X + sx * inset, c.Z + sz * inset
			local clear = true
			for _, bx in ipairs(boxes) do
				if bx[2] > x - size / 2 - 1 and bx[1] < x + size / 2 + 1 and bx[4] > z - size / 2 - 1 and bx[3] < z + size / 2 + 1 then
					clear = false
					break
				end
			end
			if clear then
				local model = Instance.new("Model")
				model.Name = "PocketPark"
				model.Parent = parent
				local base = Vector3.new(x, LOT_Y, z)
				MapKit.part(model, "Grass", Vector3.new(size, 0.3, size), CFrame.new(base + Vector3.new(0, 0.15, 0)), MapKit.GRASS, Enum.Material.Grass)
				MapKit.deco(model, "Edging", Vector3.new(size + 0.6, 0.4, size + 0.6), CFrame.new(base + Vector3.new(0, 0, 0)), MapKit.rgb(170, 165, 155), Enum.Material.Concrete)
				Streets.tree(model, base + Vector3.new(sx * 3, 0.3, sz * 3), rng:NextNumber(0.8, 1.1), rng)
				Streets.bench(model, CFrame.lookAt(base + Vector3.new(-sx * 3, 0.3, -sz * 4), base + Vector3.new(-sx * 3, 0.3, -sz * 10)), nil)
				for n = 0, 4 do
					MapKit.ball(model, "Flowers", 1, CFrame.new(base + Vector3.new(-sx * (size / 2 - 1.2), 0.8, (n - 2) * 1.6)), MapKit.FLOWERS[rng:NextInteger(1, #MapKit.FLOWERS)], Enum.Material.Grass)
				end
			end
		end
	end
end

function MapBuilder.Build()
	if map then
		return map
	end
	map = {
		Places = {},
		PlaceList = {},
		Homes = {},
		Spots = {},
		HobbySpots = {},
		BenchSpots = {},
		SoccerFields = {},
		JoggingLoops = {},
		Elevators = {},
		Nodes = nodes,
	}
	ctx.map = map
	local rng = Random.new(Config.SEED or 1776)

	local root = Instance.new("Folder")
	root.Name = "City"
	root.Parent = workspace
	map.Root = root

	local land = Landscape.build(root, rng)
	buildNetwork()
	local streets = Streets.build(root, rng, kindAt)
	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = root
	for i = -N, N do
		for j = -N, N do
			local entry = PLAN[i .. "," .. j]
			local kind = kindAt(i, j)
			local name = entry and string.match(entry, ":(.+)$")
			local builder = Places.Builders[kind]
			if builder then
				local before = #buildings:GetChildren()
				builder(ctx, buildings, i, j, rng, name)
				if kind ~= "Houses" and kind ~= "Suburb" and kind ~= "Woods" and not string.find(kind, "Park") then
					pocketParks(buildings, i, j, before, rng)
				end
			end
		end
	end

	-- the lake: an outdoor place with fishing spots on the pier
	local lake = newPlace("Lake", root:FindFirstChild("Landscape"), -N, N)
	lake.Door = blockCenter(-N, N) + Vector3.new(-HALF + 2, 0, HALF - 2)
	lake.Inside = lake.Door
	lake.Outdoor = true
	lake.Node = corner(-N, N, -1, 1)
	for _, cf in ipairs(land.FishingSpots) do
		local s = { CFrame = cf, Action = "fish", Role = "visit", Floor = 1, Place = "Lake" }
		registerSpot(s, "Lake", nil)
		table.insert(lake.Spots, s)
		map.HobbySpots.fishing = map.HobbySpots.fishing or {}
		table.insert(map.HobbySpots.fishing, s)
	end

	-- outdoor benches are somewhere to rest
	for _, entry in ipairs(Registry.Seats) do
		if entry.Place == "Plaza" or entry.Place == "Park" or entry.Place == "WillowPark" then
			table.insert(map.BenchSpots, entry.Seat.CFrame.Position)
		end
	end

	-- people spawn in the plaza, just south of the fountain
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(blockCenter(0, 0) + Vector3.new(0, 0.3, 24))
	spawn.Color = MapKit.rgb(226, 214, 192)
	spawn.Material = Enum.Material.Cobblestone
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	map.Spawn = spawn

	-- places a job or school points at must exist on the map
	for _, job in ipairs(Config.Jobs) do
		if not map.Places[job.place] then
			warn("[MapBuilder] Job '" .. job.title .. "' works at '" .. job.place .. "', which isn't on the map")
		end
	end
	for _, school in ipairs(Config.Schools or {}) do
		if not map.Places[school.place] then
			warn("[MapBuilder] School '" .. school.place .. "' isn't on the map")
		end
	end
	-- outdoor hobbies with nowhere special to go use benches
	for _, hobby in ipairs(Config.Hobbies) do
		if (Config.OutdoorHobbies or {})[hobby] and not map.HobbySpots[hobby] then
			map.HobbySpots[hobby] = {}
			for _, p in ipairs(map.BenchSpots) do
				table.insert(map.HobbySpots[hobby], { CFrame = CFrame.new(p), Action = "sit", Role = "visit", Floor = 1 })
			end
		end
	end

	map.Route = route
	-- from inside one place (or home) to inside another, along the sidewalks
	map.RouteBetween = function(a, b)
		local points = { a.Inside or a.Door, a.Door }
		for _, p in ipairs(route(a.Door, b.Door)) do
			table.insert(points, p)
		end
		table.insert(points, b.Inside or b.Door)
		return points
	end
	map.BusSeats = streets.BusSeats
	map.Bounds = { Min = Vector3.new(-EXTENT, 0, -EXTENT), Max = Vector3.new(EXTENT, 0, EXTENT) }
	map.Spacing = SPACING
	map.Extent = EXTENT
	map.Lake = Landscape.LAKE
	-- life in the parks: fireflies over the ponds and flowerbeds at night,
	-- leaves drifting down from some of the trees
	for _, id in ipairs({ "Park", "WillowPark" }) do
		local park = map.Places[id]
		if park and park.Model then
			local k = 0
			for _, d in ipairs(park.Model:GetDescendants()) do
				if d:IsA("BasePart") then
					if d.Name == "Pond" or d.Name == "FlowerBed" then
						MapKit.particles(d, "fireflies")
					elseif d.Name == "Leaves" then
						k += 1
						if k % 3 == 0 then
							MapKit.particles(d, "leaves")
						end
					end
				end
			end
		end
	end
	map.StreetName = Streets.streetName
	map.AvenueName = Streets.avenueName
	map.Registry = Registry

	-- info for clients (the map screen and the directory)
	local info = Instance.new("Folder")
	info.Name = "CityInfo"
	for _, place in ipairs(map.PlaceList) do
		local v = Instance.new("Vector3Value")
		v.Name = place.Id
		v.Value = place.Door
		v:SetAttribute("Label", place.Label)
		v:SetAttribute("Kind", place.Kind)
		v:SetAttribute("Outdoor", place.Outdoor == true)
		if place.Emoji then
			v:SetAttribute("Emoji", place.Emoji)
		end
		v.Parent = info
	end
	info:SetAttribute("Extent", EXTENT)
	info:SetAttribute("Spacing", SPACING)
	info:SetAttribute("Blocks", N)
	info:SetAttribute("LakeX", Landscape.LAKE.X)
	info:SetAttribute("LakeZ", Landscape.LAKE.Z)
	info:SetAttribute("LakeRadius", Landscape.LAKE_RADIUS)
	if map.SpeechSpot then
		info:SetAttribute("SpeechSpot", map.SpeechSpot)
	end
	info.Parent = ReplicatedStorage
	return map
end

function MapBuilder.Get()
	return map
end

-- Furnish a house the first time a family moves in (saves parts on empty homes)
-- furnish every house within `radius` studs of a position (a few per call)
function MapBuilder.FurnishNear(position, radius)
	if not map then
		return
	end
	local done = 0
	for _, home in ipairs(map.Homes) do
		if home.Furnished == false and home.Door and (home.Door - position).Magnitude < radius then
			MapBuilder.FurnishHome(home)
			done += 1
			if done >= 3 then
				return
			end
		end
	end
end

function MapBuilder.FurnishHome(home)
	if not home or home.Furnished ~= false or not home.Building then
		return home and home.Spots or {}
	end
	home.Furnished = true
	local rng = Random.new(home.Index * 31 + 7)
	local spots = Interiors.furnish(home.Building, function()
		return "home"
	end, rng, nil)
	for _, s in ipairs(spots) do
		registerSpot(s, nil, home.Building)
		s.Home = home.Index
		table.insert(home.Spots, s)
	end
	return home.Spots
end

-- Street lamps, windows, porch lights and neon at night
local isNight = nil
function MapBuilder.SetNight(night)
	if night == isNight then
		return
	end
	isNight = night
	for _, l in ipairs(Registry.Lamps) do
		l.Light.Enabled = night
		l.Head.Material = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic
		l.Head.Color = if night then MapKit.LAMP_LIGHT else MapKit.rgb(120, 120, 112)
	end
	for _, l in ipairs(Registry.NightLights) do
		l.Enabled = night
	end
	for _, n in ipairs(Registry.NightNeon) do
		n.Part.Material = if night then Enum.Material.Neon else n.Day
	end
	for _, e in ipairs(Registry.NightParticles) do
		e.Enabled = night
	end
	for k, w in ipairs(Registry.Windows) do
		-- about half the windows glow warm, like people are home
		local lit = night and (k * 7) % 10 < 5
		w.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
		w.Color = if lit then MapKit.WINDOW_LIT else (w:GetAttribute("DayColor") or MapKit.GLASS)
		w.Transparency = if lit then 0.1 else 0.2
	end
end

function MapBuilder.SetNews(text)
	if map and map.NewsBoard then
		map.NewsBoard.Text = "CITY NEWS\n" .. text
	end
end

MapBuilder.Route = route
function MapBuilder.RouteBetween(a, b)
	return map.RouteBetween(a, b)
end
MapBuilder.Kit = MapKit
return MapBuilder
