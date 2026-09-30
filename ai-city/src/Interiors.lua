-- Interiors (ModuleScript) — ServerScriptService.Modules.Interiors
-- Furnishes buildings and marks the spots where people do things there:
-- desks to type at, treadmills to run on, stoves to cook at, tables to eat
-- at, beds to sleep in... Each spot is
--   { CFrame = where the feet go (facing the right way), Action = see Actions,
--     Role = "work" / "visit" / "home", Floor = n, Seat = seat part or nil }
-- Furniture doesn't block movement (citizens walk straight to their spot).

local MapKit = require(script.Parent:WaitForChild("MapKit"))

local Interiors = {}

local deco, rgb = MapKit.deco, MapKit.rgb
local WHITE, BLACK = MapKit.WHITE, MapKit.BLACK
local FLOOR_H = MapKit.FLOOR_H

--------------------------------------------------------------------------------
-- Helpers in a building's local space. x: left/right, z: front(-)/back(+).
--------------------------------------------------------------------------------
local function top(b, f)
	return (b.FloorY[f] or 0) + 0.4
end

-- A spot: feet at (x, floor, z), facing direction (dx, dz) in building space
local function spot(list, b, f, x, z, dx, dz, action, role, seat)
	local y = top(b, f)
	local localCf = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x + dx, y, z + dz))
	local s = { CFrame = b.CFrame * localCf, Action = action, Role = role, Floor = f, Seat = seat }
	table.insert(list, s)
	return s
end

local function at(b, f, x, y, z, rot)
	return b.At(x, top(b, f) + y, z) * (rot or CFrame.new())
end

local function box(b, f, name, size, x, y, z, color, material, rot)
	return deco(b.Model, name, size, at(b, f, x, y + size.Y / 2, z, rot), color, material)
end

local function chair(b, f, x, z, faceX, faceZ, color, place)
	local yaw = math.atan2(-faceX, -faceZ)
	local rot = CFrame.Angles(0, yaw, 0)
	color = color or rgb(90, 70, 55)
	local seat = MapKit.seat(b.Model, "Chair", Vector3.new(2, 0.4, 2), at(b, f, x, 1.7, z, rot), color, Enum.Material.Wood, place)
	deco(b.Model, "ChairBack", Vector3.new(2, 2.2, 0.3), at(b, f, x, 1.7, z, rot) * CFrame.new(0, 1.2, 0.9), color)
	for _, lx in ipairs({ -0.8, 0.8 }) do
		for _, lz in ipairs({ -0.8, 0.8 }) do
			deco(b.Model, "ChairLeg", Vector3.new(0.2, 1.6, 0.2), at(b, f, x, 0.8, z, rot) * CFrame.new(lx, 0, lz), color:Lerp(BLACK, 0.3))
		end
	end
	return seat
end

local function desk(b, f, x, z, list, action, role, facing, place, color)
	-- desk faces -Z (the person sits on the +Z side looking at -Z) unless facing = 1
	local s = facing or 1
	color = color or rgb(170, 130, 90)
	box(b, f, "Desk", Vector3.new(5, 0.3, 2.6), x, 2.9, z, color, Enum.Material.Wood)
	for _, lx in ipairs({ -2.2, 2.2 }) do
		box(b, f, "DeskLeg", Vector3.new(0.3, 2.9, 2.4), x + lx, 0, z, color:Lerp(BLACK, 0.3), Enum.Material.Wood)
	end
	if action == "type" then
		local screen = box(b, f, "Monitor", Vector3.new(2.6, 1.6, 0.2), x, 3.5, z - s * 0.8, rgb(30, 32, 38), Enum.Material.SmoothPlastic)
		deco(b.Model, "Screen", Vector3.new(2.3, 1.3, 0.05), screen.CFrame * CFrame.new(0, 0, s * 0.12), rgb(120, 190, 255), Enum.Material.Neon)
		box(b, f, "Keyboard", Vector3.new(2, 0.12, 0.7), x, 3.05, z + s * 0.3, rgb(40, 42, 48))
		box(b, f, "Mug", Vector3.new(0.4, 0.5, 0.4), x + 1.8, 3.05, z, ({ rgb(220, 60, 60), WHITE, rgb(60, 120, 220) })[(math.floor(x + z) % 3) + 1])
	else
		box(b, f, "Paper", Vector3.new(1.2, 0.05, 1.6), x - 0.8, 3.05, z, WHITE)
		box(b, f, "Books", Vector3.new(0.8, 0.6, 1.2), x + 1.5, 3.05, z, rgb(140, 50, 60))
	end
	local seat = chair(b, f, x, z + s * 2, 0, -s, nil, place)
	spot(list, b, f, x, z + s * 2, 0, -s, action, role, seat)
end

local function counter(b, f, x, z, w, color, faceZ)
	box(b, f, "Counter", Vector3.new(w, 3.6, 2.2), x, 0, z, color or rgb(120, 86, 58), Enum.Material.Wood)
	box(b, f, "CounterTop", Vector3.new(w + 0.3, 0.25, 2.5), x, 3.6, z, rgb(236, 232, 224), Enum.Material.Marble)
	return faceZ
end

local function register(b, f, x, z)
	box(b, f, "Register", Vector3.new(1.4, 0.9, 1.2), x, 3.85, z, rgb(40, 42, 48))
	box(b, f, "RegisterScreen", Vector3.new(1, 0.6, 0.1), x, 4.75, z, rgb(90, 220, 140), Enum.Material.Neon)
end

local function shelf(b, f, x, z, len, rng, sideways)
	local size = if sideways then Vector3.new(1.6, 7, len) else Vector3.new(len, 7, 1.6)
	box(b, f, "Shelf", size, x, 0, z, rgb(210, 200, 184), Enum.Material.Wood)
	for row = 0, 2 do
		local n = math.floor(len / 1.3)
		for k = 0, n - 1 do
			local off = -len / 2 + 0.65 + k * 1.3
			local c = MapKit.FLOWERS[rng:NextInteger(1, #MapKit.FLOWERS)]:Lerp(rgb(200, 200, 200), 0.2)
			local px, pz = if sideways then x else x + off, if sideways then z + off else z
			box(b, f, "Product", Vector3.new(0.9, 1 + (k % 2) * 0.4, 0.9), px, 1 + row * 2.2, pz, c)
		end
	end
end

local function plant(b, f, x, z)
	box(b, f, "Pot", Vector3.new(1.4, 1.4, 1.4), x, 0, z, rgb(180, 110, 80), Enum.Material.Slate)
	MapKit.ball(b.Model, "PlantLeaves", 2.6, at(b, f, x, 2.8, z), MapKit.LEAVES[(math.floor(x * 3 + z) % #MapKit.LEAVES) + 1], Enum.Material.Grass)
end

local function rug(b, f, x, z, w, d, color)
	box(b, f, "Rug", Vector3.new(w, 0.06, d), x, 0, z, color, Enum.Material.Fabric)
end

local function tableSet(b, f, x, z, list, action, place, color)
	MapKit.disc(b.Model, "TableTop", 0.25, 4, at(b, f, x, 3, z).Position, color or WHITE, Enum.Material.Wood)
	box(b, f, "TableLeg", Vector3.new(0.4, 2.9, 0.4), x, 0, z, rgb(60, 60, 64), Enum.Material.Metal)
	box(b, f, "Plate", Vector3.new(1, 0.08, 1), x, 3.12, z - 0.8, WHITE)
	box(b, f, "Plate", Vector3.new(1, 0.08, 1), x, 3.12, z + 0.8, WHITE)
	local s1 = chair(b, f, x, z - 2.4, 0, 1, nil, place)
	local s2 = chair(b, f, x, z + 2.4, 0, -1, nil, place)
	spot(list, b, f, x, z - 2.4, 0, 1, action, "visit", s1)
	spot(list, b, f, x, z + 2.4, 0, -1, action, "visit", s2)
end

local function bed(b, f, x, z, list, color, action, role)
	-- head of the bed toward +Z
	box(b, f, "BedFrame", Vector3.new(4.4, 1.4, 7.4), x, 0, z, rgb(110, 80, 60), Enum.Material.Wood)
	box(b, f, "Mattress", Vector3.new(4, 0.8, 7), x, 1.4, z, WHITE, Enum.Material.Fabric)
	box(b, f, "Blanket", Vector3.new(4.1, 0.3, 4.6), x, 2.1, z - 1, color or rgb(90, 130, 200), Enum.Material.Fabric)
	box(b, f, "Pillow", Vector3.new(3, 0.6, 1.2), x, 2.2, z + 2.8, WHITE, Enum.Material.Fabric)
	box(b, f, "Headboard", Vector3.new(4.4, 3.4, 0.4), x, 0, z + 3.7, rgb(110, 80, 60), Enum.Material.Wood)
	-- lying spot: feet at the foot end, facing up the bed
	local s = spot(list, b, f, x, z - 1.4, 0, 1, action or "sleep", role or "home")
	s.BedTop = top(b, f) + 2.2
	return s
end

--------------------------------------------------------------------------------
-- Room types. Each fills floor f of building b and adds spots to list.
--------------------------------------------------------------------------------
local ROOMS = {}

function ROOMS.office(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, 0, W - 6, D - 8, rgb(90, 100, 120))
	local cols = math.max(1, math.floor((W - 8) / 8))
	local rows = math.max(1, math.floor((D - 12) / 7))
	for cx = 0, cols - 1 do
		for rz = 0, rows - 1 do
			local x = -((cols - 1) * 8) / 2 + cx * 8
			local z = -D / 2 + 6 + rz * 7
			if not (f == 1 and math.abs(x) < 5 and rz == 0) and not (b.Elevator and x > W / 2 - 9 and z > D / 2 - 10) then
				desk(b, f, x, z, list, "type", "work", 1, place)
			end
		end
	end
	plant(b, f, -W / 2 + 2.5, D / 2 - 2.5)
	box(b, f, "WaterCooler", Vector3.new(1.4, 4, 1.4), -W / 2 + 2.5, 0, -D / 2 + 3, rgb(200, 220, 240))
	box(b, f, "Whiteboard", Vector3.new(6, 3.4, 0.2), 0, 3.5, D / 2 - 1.2, WHITE)
	spot(list, b, f, 0, D / 2 - 4, 0, 1, "present", "work")
end

function ROOMS.gym(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, 0, W - 3, D - 3, rgb(50, 52, 58))
	-- treadmills along the front windows
	for k = 0, 3 do
		local x = -W / 2 + 5 + k * 5
		box(b, f, "TreadmillBase", Vector3.new(2.6, 0.6, 6), x, 0, -D / 2 + 5, rgb(30, 30, 34), Enum.Material.Metal)
		box(b, f, "TreadmillBelt", Vector3.new(2, 0.1, 5), x, 0.6, -D / 2 + 5, rgb(20, 20, 22), Enum.Material.Rubber)
		box(b, f, "TreadmillRail", Vector3.new(2.6, 3.6, 0.3), x, 0.6, -D / 2 + 2.4, rgb(60, 62, 70), Enum.Material.Metal)
		box(b, f, "TreadmillScreen", Vector3.new(1.6, 0.9, 0.2), x, 4.2, -D / 2 + 2.4, rgb(90, 200, 255), Enum.Material.Neon)
		local s = spot(list, b, f, x, -D / 2 + 5.6, 0, -1, "run", "visit")
		s.Raise = 0.7
	end
	-- dumbbell rack and a mirror wall
	box(b, f, "Mirror", Vector3.new(W - 6, 7, 0.2), 0, 1, D / 2 - 1.2, rgb(200, 220, 230), Enum.Material.Glass).Reflectance = 0.5
	box(b, f, "DumbbellRack", Vector3.new(8, 2.4, 1.6), -W / 4, 0, D / 2 - 3, rgb(40, 40, 44), Enum.Material.Metal)
	for k = 0, 5 do
		MapKit.cylinder(b.Model, "Dumbbell", 1.4, 0.7, at(b, f, -W / 4 - 3.4 + k * 1.35, 2.7, D / 2 - 3) * CFrame.Angles(0, math.rad(90), 0), rgb(60, 60, 66), Enum.Material.Metal)
	end
	for k = 0, 2 do
		spot(list, b, f, -W / 4 - 3 + k * 3, D / 2 - 6, 0, 1, "lift", "visit")
	end
	-- squat rack with a barbell
	local sx = W / 4
	for _, px in ipairs({ -2.6, 2.6 }) do
		box(b, f, "RackPost", Vector3.new(0.5, 8, 0.5), sx + px, 0, 2, rgb(200, 40, 40), Enum.Material.Metal)
	end
	MapKit.cylinder(b.Model, "Barbell", 7, 0.3, at(b, f, sx, 5, 2), rgb(180, 180, 186), Enum.Material.Metal)
	for _, px in ipairs({ -2.9, 2.9 }) do
		MapKit.cylinder(b.Model, "Plate", 0.4, 2.2, at(b, f, sx + px, 5, 2), rgb(30, 30, 34), Enum.Material.Metal)
	end
	spot(list, b, f, sx, 2.6, 0, -1, "squat", "visit")
	-- punching bags
	for k = 0, 1 do
		local bx = -2 + k * 6
		box(b, f, "BagChain", Vector3.new(0.2, 2.5, 0.2), bx, 8.5, 3, rgb(120, 120, 126), Enum.Material.Metal)
		MapKit.cylinder(b.Model, "PunchingBag", 4.4, 2, at(b, f, bx, 6.2, 3) * CFrame.Angles(0, 0, math.rad(90)), rgb(170, 30, 36), Enum.Material.Fabric)
		spot(list, b, f, bx, 1, 0, 1, "punch", "visit")
	end
	-- yoga mats
	for k = 0, 2 do
		local mx = -W / 2 + 4 + k * 4
		box(b, f, "YogaMat", Vector3.new(2.4, 0.1, 6), mx, 0, 4, ({ rgb(120, 90, 220), rgb(60, 180, 160), rgb(240, 120, 150) })[k + 1], Enum.Material.Fabric)
		spot(list, b, f, mx, 4, 0, -1, if k == 1 then "stretch" else "yoga", "visit")
	end
	-- lockers and the coach
	for k = 0, 4 do
		box(b, f, "Locker", Vector3.new(1.6, 7, 1.6), W / 2 - 2, 0, -D / 2 + 8 + k * 1.7, rgb(70, 110, 170), Enum.Material.Metal)
	end
	spot(list, b, f, 0, -2, 0, 1, "coach", "work")
end

function ROOMS.cafe(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, 0, W - 4, D - 4, rgb(160, 120, 90))
	counter(b, f, 0, D / 2 - 5, W - 10, rgb(90, 60, 40))
	box(b, f, "EspressoMachine", Vector3.new(2.4, 2, 1.6), -3, 3.85, D / 2 - 5, rgb(180, 184, 190))
	box(b, f, "PastryCase", Vector3.new(4, 1.6, 2), 4, 3.85, D / 2 - 5, rgb(200, 230, 240)).Transparency = 0.3
	for k = 0, 3 do
		MapKit.ball(b.Model, "Pastry", 0.7, at(b, f, 2.6 + k * 0.9, 4.4, D / 2 - 5), rgb(210, 150, 80))
	end
	register(b, f, 7, D / 2 - 5)
	box(b, f, "MenuBoard", Vector3.new(8, 3.6, 0.2), 0, 6, D / 2 - 1.2, rgb(30, 34, 30))
	spot(list, b, f, -3, D / 2 - 2.6, 0, -1, "brew", "work")
	spot(list, b, f, 7, D / 2 - 2.6, 0, -1, "cashier", "work")
	spot(list, b, f, 1, D / 2 - 2.6, 0, -1, "counter", "work")
	for k = 0, 2 do
		tableSet(b, f, -W / 2 + 6 + k * 8, -1, list, "coffee", place, rgb(240, 236, 228))
	end
end

function ROOMS.bakery(b, f, list, rng, place)
	local W, D = b.W, b.D
	counter(b, f, 0, -2, W - 10, rgb(200, 160, 120))
	for k = 0, 5 do
		box(b, f, "Bread", Vector3.new(1.6, 0.7, 0.8), -6 + k * 2.4, 3.85, -2, rgb(200, 140, 70))
	end
	register(b, f, W / 2 - 7, -2)
	for k = 0, 1 do
		local ox = -W / 2 + 6 + k * 8
		box(b, f, "Oven", Vector3.new(6, 6, 3), ox, 0, D / 2 - 3, rgb(150, 70, 50), Enum.Material.Brick)
		local glow = box(b, f, "OvenGlow", Vector3.new(3.4, 1.6, 0.1), ox, 2.2, D / 2 - 4.55, rgb(255, 150, 60), Enum.Material.Neon)
		MapKit.light(glow, rgb(255, 150, 70), 8, 0.6)
	end
	box(b, f, "KneadingTable", Vector3.new(8, 3.2, 3), W / 4, 0, 4, rgb(220, 210, 190), Enum.Material.Wood)
	box(b, f, "FlourSack", Vector3.new(1.6, 2.2, 1.2), W / 2 - 3, 0, D / 2 - 3, rgb(240, 236, 220), Enum.Material.Fabric)
	spot(list, b, f, W / 4, 1.8, 0, 1, "bake", "work")
	spot(list, b, f, -W / 2 + 6, D / 2 - 6, 0, 1, "bake", "work")
	spot(list, b, f, W / 2 - 7, 0.4, 0, -1, "cashier", "work")
	for k = 0, 2 do
		spot(list, b, f, -6 + k * 5, -5, 0, 1, "browse", "visit")
	end
end

function ROOMS.restaurant(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, -3, W - 4, D - 10, rgb(130, 40, 40))
	for k = 0, 3 do
		tableSet(b, f, -W / 2 + 6 + (k % 2) * 12, -D / 2 + 6 + (k // 2) * 7, list, "eat", place, WHITE)
	end
	-- kitchen at the back behind a pass counter
	counter(b, f, 0, D / 2 - 7, W - 8, rgb(190, 190, 196))
	for k = 0, 1 do
		box(b, f, "Stove", Vector3.new(4, 3.6, 2.6), -6 + k * 8, 0, D / 2 - 2.6, rgb(60, 62, 68), Enum.Material.Metal)
		local flame = box(b, f, "Burner", Vector3.new(1.2, 0.1, 1.2), -6 + k * 8, 3.65, D / 2 - 2.6, rgb(90, 160, 255), Enum.Material.Neon)
		flame.Transparency = 0.2
		spot(list, b, f, -6 + k * 8, D / 2 - 5, 0, 1, "cook", "work")
	end
	spot(list, b, f, 0, D / 2 - 9.4, 0, -1, "serve", "work")
	spot(list, b, f, 6, -2, 0, -1, "serve", "work")
end

function ROOMS.store(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, 0, W - 4, D - 4, rgb(230, 226, 214))
	counter(b, f, W / 2 - 6, -D / 2 + 6, 7, rgb(120, 86, 58))
	register(b, f, W / 2 - 6, -D / 2 + 6)
	spot(list, b, f, W / 2 - 6, -D / 2 + 8.4, 0, -1, "cashier", "work")
	if W >= 30 then
		-- a second checkout lane on bigger stores
		counter(b, f, W / 2 - 15, -D / 2 + 6, 6, rgb(120, 86, 58))
		register(b, f, W / 2 - 15, -D / 2 + 6)
		spot(list, b, f, W / 2 - 15, -D / 2 + 8.4, 0, -1, "cashier", "work")
	end
	local rows = math.max(1, math.floor((W - 10) / 7))
	for k = 0, rows - 1 do
		local x = -W / 2 + 5 + k * 7
		shelf(b, f, x, 2, math.min(10, D - 12), rng, true)
		spot(list, b, f, x + 2, 1, -1, 0, "browse", "visit")
	end
	shelf(b, f, 0, D / 2 - 2, W - 8, rng, false)
	spot(list, b, f, -3, D / 2 - 4.4, 0, 1, "shelve", "work")
	spot(list, b, f, 4, D / 2 - 4.4, 0, 1, "browse", "visit")
	-- stock arriving at the back door
	for k = 0, 1 do
		box(b, f, "StockBox", Vector3.new(1.8, 1.6, 1.8), -W / 2 + 3, 0, -D / 2 + 4 + k * 2.2, rgb(190, 150, 100), Enum.Material.WoodPlanks)
	end
	spot(list, b, f, -W / 2 + 5.5, -D / 2 + 5, 1, 0, "carrybox", "work")
end

function ROOMS.bank(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, -4, 8, D - 12, rgb(150, 30, 40))
	counter(b, f, 0, 3, W - 12, rgb(90, 60, 40))
	for k = -2, 2 do
		box(b, f, "TellerGlass", Vector3.new(0.2, 3, 2.2), k * 5, 3.8, 3, rgb(200, 230, 240), Enum.Material.Glass).Transparency = 0.5
	end
	for k = 0, 2 do
		spot(list, b, f, -6 + k * 6, 5.4, 0, -1, "counter", "work")
		spot(list, b, f, -6 + k * 6, 0.6, 0, 1, "wait", "visit")
	end
	desk(b, f, W / 2 - 7, -D / 2 + 7, list, "type", "work", 1, place, rgb(90, 60, 40))
	for k = 0, 2 do
		chair(b, f, -W / 2 + 4, -D / 2 + 5 + k * 3, 1, 0, rgb(150, 30, 40), place)
	end
	plant(b, f, -W / 2 + 2.5, D / 2 - 6)
	box(b, f, "Chandelier", Vector3.new(3, 0.6, 3), 0, FLOOR_H - 2, -2, MapKit.GOLD, Enum.Material.Metal)
end

function ROOMS.police(b, f, list, rng, place)
	local W, D = b.W, b.D
	counter(b, f, 0, -D / 2 + 7, 12, rgb(60, 70, 100))
	spot(list, b, f, 0, -D / 2 + 9.4, 0, -1, "counter", "work")
	for k = 0, 2 do
		desk(b, f, -W / 2 + 7 + k * 8, 3, list, "type", "work", 1, place, rgb(120, 110, 100))
	end
	-- the holding cell: a real cell in the back corner. The building's back and
	-- side walls, a concrete wall, and a front of solid bars (with a locked door)
	-- that nobody can walk through.
	local cx, cz = W / 2 - 7, D / 2 - 6
	local x0, x1 = cx - 6, W / 2 - 0.4 -- left and right inside edges
	local zf, zb = cz - 4.5, D / 2 - 0.4 -- front (bars) and back
	local h = FLOOR_H - 0.8
	local steel = rgb(52, 54, 60)
	local function solid(name, size, x, y, z, color, material)
		return MapKit.part(b.Model, name, size, at(b, f, x, y + size.Y / 2, z), color, material)
	end
	-- floor and the side wall
	box(b, f, "CellFloor", Vector3.new(x1 - x0, 0.06, zb - zf), (x0 + x1) / 2, 0, (zf + zb) / 2, rgb(120, 122, 128), Enum.Material.Concrete)
	solid("CellWall", Vector3.new(0.6, h, zb - zf + 0.6), x0 - 0.3, 0, (zf + zb) / 2, rgb(170, 172, 178), Enum.Material.Concrete)
	-- the bars, with rails top, bottom and across the middle
	local n = math.floor((x1 - x0) / 0.8)
	for k = 0, n do
		solid("CellBar", Vector3.new(0.3, h, 0.3), x0 + 0.2 + k * (x1 - x0 - 0.4) / n, 0, zf, steel, Enum.Material.Metal)
	end
	for _, y in ipairs({ 0.1, h / 2, h - 0.3 }) do
		solid("CellRail", Vector3.new(x1 - x0, 0.3, 0.45), (x0 + x1) / 2, y, zf, steel, Enum.Material.Metal)
	end
	-- the door: a frame, hinges and a big lock
	local dx = cx + 1.5
	box(b, f, "CellDoorFrame", Vector3.new(0.35, h, 0.6), dx - 2, 0, zf, rgb(40, 42, 48), Enum.Material.Metal)
	box(b, f, "CellDoorFrame", Vector3.new(0.35, h, 0.6), dx + 2, 0, zf, rgb(40, 42, 48), Enum.Material.Metal)
	box(b, f, "CellLock", Vector3.new(0.9, 1.1, 0.7), dx + 1.5, 3.4, zf, rgb(200, 170, 60), Enum.Material.Metal)
	-- inside: a bench, a toilet and a sink, a caged light
	box(b, f, "CellBench", Vector3.new(7, 1.6, 2), cx, 0, zb - 1.2, rgb(120, 120, 126), Enum.Material.Concrete)
	box(b, f, "CellToilet", Vector3.new(1.6, 1.6, 2), x1 - 1.2, 0, zf + 2.2, rgb(220, 222, 226), Enum.Material.Metal)
	box(b, f, "CellSink", Vector3.new(1.4, 0.6, 1), x1 - 0.8, 3, zf + 4.4, rgb(220, 222, 226), Enum.Material.Metal)
	local lamp = box(b, f, "CellLamp", Vector3.new(1.6, 0.4, 1.6), cx, h - 0.6, (zf + zb) / 2, rgb(255, 240, 200), Enum.Material.Neon)
	MapKit.light(lamp, rgb(255, 235, 200), 16, 0.9)
	-- a sign over the bars
	local sign = box(b, f, "CellSign", Vector3.new(6, 1.2, 0.2), cx, h - 1.6, zf - 0.4, rgb(40, 36, 50))
	MapKit.signText(sign, Enum.NormalId.Front, "HOLDING CELL", rgb(255, 210, 80))
	box(b, f, "WantedBoard", Vector3.new(6, 4, 0.2), -W / 2 + 6, 4, D / 2 - 1.2, rgb(200, 180, 140))
	spot(list, b, f, -W / 2 + 6, D / 2 - 4, 0, 1, "guard", "work")
	b.Jail = at(b, f, cx, 0, cz).Position
end

function ROOMS.hospital(b, f, list, rng, place)
	local W, D = b.W, b.D
	if f == 1 then
		counter(b, f, 0, -D / 2 + 8, 14, rgb(120, 180, 220))
		spot(list, b, f, 0, -D / 2 + 10.4, 0, -1, "counter", "work")
		for k = 0, 3 do
			chair(b, f, -W / 2 + 4 + k * 3, -D / 2 + 4, 0, 1, rgb(80, 140, 200), place)
		end
	end
	local beds = math.max(2, math.floor((W - 10) / 7))
	for k = 0, beds - 1 do
		local x = -W / 2 + 6 + k * 7
		local s = bed(b, f, x, D / 2 - 6, list, rgb(170, 210, 235), "patient", "visit")
		s.HospitalBed = true
		box(b, f, "Curtain", Vector3.new(0.1, 7, 7), x + 3.2, 0, D / 2 - 6, rgb(200, 230, 220), Enum.Material.Fabric)
		box(b, f, "Monitor", Vector3.new(1.4, 1.2, 0.4), x - 2.8, 4, D / 2 - 3, rgb(40, 44, 50))
		spot(list, b, f, x - 3, D / 2 - 9, 1, 1, if k % 2 == 0 then "doctor" else "nurse", "work")
	end
end

function ROOMS.classroom(b, f, list, rng, place)
	local W, D = b.W, b.D
	box(b, f, "Chalkboard", Vector3.new(math.min(16, W - 8), 5, 0.2), 0, 2.6, D / 2 - 1.2, rgb(40, 70, 50))
	box(b, f, "ChalkTray", Vector3.new(math.min(16, W - 8), 0.3, 0.5), 0, 2.4, D / 2 - 1.4, rgb(150, 110, 70))
	desk(b, f, W / 2 - 6, D / 2 - 5, list, "type", "work", -1, place, rgb(120, 80, 50))
	spot(list, b, f, -3, D / 2 - 3.2, 0, 1, "teach", "work")
	local cols = math.max(2, math.floor((W - 10) / 6))
	for cx = 0, cols - 1 do
		for rz = 0, 1 do
			local x = -((cols - 1) * 6) / 2 + cx * 6
			local z = -D / 2 + 6 + rz * 6
			-- student desks face the board (+Z): sit on the -Z side
			box(b, f, "StudentDesk", Vector3.new(3, 0.25, 2), x, 2.5, z, rgb(200, 170, 120), Enum.Material.Wood)
			box(b, f, "DeskLeg", Vector3.new(0.3, 2.5, 1.8), x, 0, z, rgb(80, 80, 86), Enum.Material.Metal)
			local seat = chair(b, f, x, z - 1.8, 0, 1, rgb(60, 110, 190), place)
			spot(list, b, f, x, z - 1.8, 0, 1, "study", "student", seat)
		end
	end
	for k = 0, 3 do
		box(b, f, "Poster", Vector3.new(2.4, 3, 0.1), -W / 2 + 0.6, 5, -D / 2 + 5 + k * 5, MapKit.FLOWERS[k + 1], nil, CFrame.Angles(0, math.rad(90), 0))
	end
end

function ROOMS.library(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, 0, W - 6, D - 8, rgb(110, 50, 50))
	for k = 0, 3 do
		local x = -W / 2 + 5 + k * ((W - 10) / 3)
		box(b, f, "Bookshelf", Vector3.new(6, 8, 1.8), x, 0, D / 2 - 2, rgb(110, 70, 45), Enum.Material.Wood)
		for row = 0, 3 do
			box(b, f, "BookRow", Vector3.new(5.4, 1.4, 1.4), x, 0.6 + row * 1.9, D / 2 - 2.1, MapKit.FLOWERS[(k + row) % #MapKit.FLOWERS + 1]:Lerp(rgb(80, 60, 50), 0.4))
		end
	end
	for k = 0, 1 do
		local x = -W / 4 + k * (W / 2)
		box(b, f, "ReadingTable", Vector3.new(8, 0.3, 3.4), x, 2.9, -2, rgb(130, 90, 60), Enum.Material.Wood)
		box(b, f, "TableLeg", Vector3.new(7, 2.9, 0.4), x, 0, -2, rgb(100, 70, 50), Enum.Material.Wood)
		for _, sz in ipairs({ -1, 1 }) do
			for _, ox in ipairs({ -2.2, 2.2 }) do
				local seat = chair(b, f, x + ox, -2 + sz * 2.6, 0, -sz, nil, place)
				spot(list, b, f, x + ox, -2 + sz * 2.6, 0, -sz, "read", "visit", seat)
			end
		end
		box(b, f, "ReadingLamp", Vector3.new(0.5, 1.4, 0.5), x, 3.05, -2, rgb(60, 140, 90))
	end
	counter(b, f, W / 2 - 7, -D / 2 + 6, 8, rgb(110, 70, 45))
	spot(list, b, f, W / 2 - 7, -D / 2 + 8.4, 0, -1, "counter", "work")
	spot(list, b, f, -W / 2 + 5, D / 2 - 4.5, 0, 1, "shelve", "work")
	MapKit.ball(b.Model, "Globe", 2, at(b, f, -W / 2 + 3, 4.2, -D / 2 + 4), rgb(80, 150, 220), Enum.Material.SmoothPlastic)
end

function ROOMS.cinema(b, f, list, rng, place)
	local W, D = b.W, b.D
	local screen = box(b, f, "Screen", Vector3.new(W - 10, 12, 0.3), 0, 3, D / 2 - 1.4, rgb(230, 236, 255), Enum.Material.Neon)
	screen.Transparency = 0.15
	MapKit.light(screen, rgb(170, 190, 255), 30, 0.6)
	for row = 0, 3 do
		for k = -3, 3 do
			local x, z = k * 4, -D / 2 + 8 + row * 4.4
			local seat = MapKit.seat(b.Model, "CinemaSeat", Vector3.new(3, 0.6, 2.6), at(b, f, x, 1.4 + row * 0.6, z), rgb(170, 30, 50), Enum.Material.Fabric, place)
			deco(b.Model, "SeatBack", Vector3.new(3, 2.6, 0.5), at(b, f, x, 2.8 + row * 0.6, z - 1.3), rgb(150, 24, 44), Enum.Material.Fabric)
			box(b, f, "SeatRiser", Vector3.new(3.2, 1.1 + row * 0.6, 3), x, 0, z, rgb(40, 34, 44))
			local s = spot(list, b, f, x, z, 0, 1, "watch", "visit", seat)
			s.Raise = row * 0.6
		end
	end
	counter(b, f, -W / 2 + 7, -D / 2 + 4, 8, rgb(200, 40, 50))
	box(b, f, "Popcorn", Vector3.new(2, 2.4, 1.6), -W / 2 + 5, 3.85, -D / 2 + 4, rgb(250, 230, 150))
	spot(list, b, f, -W / 2 + 7, -D / 2 + 6.4, 0, -1, "cashier", "work")
	-- the usher checking tickets and the projection booth at the back
	spot(list, b, f, W / 2 - 6, -D / 2 + 5, -1, 0, "guard", "work")
	box(b, f, "Projector", Vector3.new(2.4, 2, 3), 0, 6, -D / 2 + 2.4, rgb(40, 40, 46), Enum.Material.Metal)
	spot(list, b, f, 3, -D / 2 + 3, -1, 0, "machine", "work")
end

function ROOMS.factory(b, f, list, rng, place)
	local W, D = b.W, b.D
	box(b, f, "Conveyor", Vector3.new(W - 12, 3, 3), 0, 0, 2, rgb(50, 52, 58), Enum.Material.Metal)
	box(b, f, "ConveyorBelt", Vector3.new(W - 12, 0.2, 2.6), 0, 3, 2, rgb(25, 25, 28), Enum.Material.Rubber)
	for k = 0, 5 do
		box(b, f, "Crate", Vector3.new(1.8, 1.4, 1.8), -W / 2 + 10 + k * 7, 3.2, 2, rgb(170, 125, 75), Enum.Material.WoodPlanks)
	end
	for k = 0, 2 do
		local x = -W / 3 + k * (W / 3)
		box(b, f, "Machine", Vector3.new(7, 6, 5), x, 0, D / 2 - 5, rgb(230, 170, 40), Enum.Material.Metal)
		box(b, f, "MachineLight", Vector3.new(0.6, 0.6, 0.6), x + 2.5, 6.1, D / 2 - 5, rgb(90, 255, 120), Enum.Material.Neon)
		spot(list, b, f, x, D / 2 - 9, 0, 1, "machine", "work")
		spot(list, b, f, x, 0, 0, 1, "machine", "work")
	end
	for k = 0, 1 do
		spot(list, b, f, -W / 2 + 5 + k * 3, -D / 2 + 5, 1, 0, "carrybox", "work")
	end
end

function ROOMS.warehouse(b, f, list, rng, place)
	local W, D = b.W, b.D
	for k = 0, 2 do
		local x = -W / 2 + 8 + k * ((W - 16) / 2)
		box(b, f, "Racking", Vector3.new(10, 0.4, 4), x, 4, D / 2 - 4, rgb(240, 150, 40), Enum.Material.Metal)
		box(b, f, "Racking", Vector3.new(10, 0.4, 4), x, 8, D / 2 - 4, rgb(240, 150, 40), Enum.Material.Metal)
		for n = 0, 3 do
			box(b, f, "Crate", Vector3.new(2.2, 2.2, 2.2), x - 3.6 + n * 2.4, 0 + (n % 2) * 4.4, D / 2 - 4, rgb(170, 125, 75), Enum.Material.WoodPlanks)
		end
		spot(list, b, f, x, D / 2 - 8, 0, 1, "carrybox", "work")
	end
	-- forklift
	box(b, f, "Forklift", Vector3.new(3.4, 3, 5), 0, 0.8, -2, rgb(250, 190, 40), Enum.Material.Metal)
	box(b, f, "ForkMast", Vector3.new(3, 7, 0.4), 0, 0.8, -4.7, rgb(60, 60, 66), Enum.Material.Metal)
	spot(list, b, f, W / 4, -D / 2 + 6, 0, 1, "sort", "work")
end

function ROOMS.garage(b, f, list, rng, place)
	local W, D = b.W, b.D
	counter(b, f, -W / 2 + 6, -D / 2 + 5, 7, rgb(200, 60, 50))
	register(b, f, -W / 2 + 6, -D / 2 + 5)
	spot(list, b, f, -W / 2 + 6, -D / 2 + 7.4, 0, -1, "cashier", "work")
	shelf(b, f, W / 2 - 3, 0, D - 8, rng, true)
	box(b, f, "ToolBoard", Vector3.new(8, 4, 0.2), 0, 4, D / 2 - 1.2, rgb(140, 140, 146))
	spot(list, b, f, 2, D / 2 - 4, 0, 1, "fixcar", "work")
	spot(list, b, f, W / 2 - 6, 0, 1, 0, "browse", "visit")
end

function ROOMS.townhall(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, -2, 10, D - 8, rgb(140, 30, 40))
	-- council desk in a curve at the back and the mayor's desk
	for k = -2, 2 do
		local x = k * 6
		desk(b, f, x, D / 2 - 7 - math.abs(k) * 0.8, list, "type", "work", -1, place, rgb(110, 70, 45))
	end
	for _, sx in ipairs({ -1, 1 }) do
		MapKit.column(b.Model, "FlagPole", 9, 0.3, at(b, f, sx * (W / 2 - 3), 4.5, D / 2 - 3).Position, MapKit.GOLD, Enum.Material.Metal, false)
		box(b, f, "Flag", Vector3.new(0.1, 3, 4), sx * (W / 2 - 3), 5.5, D / 2 - 5.2, rgb(60, 110, 220), Enum.Material.Fabric)
	end
	box(b, f, "Podium", Vector3.new(3, 4, 2), 0, 0, -2, rgb(90, 60, 40), Enum.Material.Wood)
	spot(list, b, f, 0, 0.4, 0, -1, "present", "work")
	for k = 0, 3 do
		chair(b, f, -6 + k * 4, -D / 2 + 7, 0, 1, rgb(140, 30, 40), place)
		spot(list, b, f, -6 + k * 4, -D / 2 + 7, 0, 1, "sit", "visit")
	end
	b.MayorOffice = at(b, f, 0, 0, D / 2 - 7).Position
end

function ROOMS.hotel(b, f, list, rng, place)
	local W, D = b.W, b.D
	if f == 1 then
		rug(b, f, 0, 0, W - 8, D - 8, rgb(120, 30, 40))
		counter(b, f, 0, D / 2 - 7, 14, rgb(110, 70, 45))
		spot(list, b, f, -3, D / 2 - 4.6, 0, -1, "counter", "work")
		spot(list, b, f, 3, D / 2 - 4.6, 0, -1, "counter", "work")
		for k = 0, 1 do
			box(b, f, "Sofa", Vector3.new(7, 2, 3), -W / 2 + 7 + k * (W - 14), 0, -4, rgb(170, 140, 100), Enum.Material.Fabric)
			local seat = MapKit.seat(b.Model, "SofaSeat", Vector3.new(6, 0.4, 2.4), at(b, f, -W / 2 + 7 + k * (W - 14), 2, -4), rgb(170, 140, 100), Enum.Material.Fabric, place)
			spot(list, b, f, -W / 2 + 7 + k * (W - 14), -4, 0, -1, "sit", "visit", seat)
		end
		local chand = box(b, f, "Chandelier", Vector3.new(4, 1.4, 4), 0, FLOOR_H - 2.6, -2, MapKit.GOLD, Enum.Material.Metal)
		MapKit.light(chand, rgb(255, 230, 180), 22, 0.9)
	else
		-- guest rooms
		for k = 0, 1 do
			local x = -W / 4 + k * (W / 2)
			bed(b, f, x, D / 2 - 6, list, rgb(200, 180, 150), "sleep", "visit")
			box(b, f, "Nightstand", Vector3.new(1.6, 2, 1.6), x + 3.4, 0, D / 2 - 3, rgb(110, 80, 60), Enum.Material.Wood)
		end
		box(b, f, "Hallway", Vector3.new(W - 4, 0.06, 4), 0, 0, -D / 2 + 4, rgb(120, 30, 40), Enum.Material.Fabric)
	end
end

function ROOMS.home(b, f, list, rng, place)
	-- a living room at the front, a kitchen in one back corner and bedrooms in the other
	local W, D = b.W, b.D
	rug(b, f, -W / 4, -1, 7, 5, ({ rgb(170, 70, 60), rgb(70, 110, 150), rgb(200, 170, 110), rgb(90, 130, 90) })[rng:NextInteger(1, 4)])
	if f == 1 then
		-- sofa facing a TV
		local sx, sz = -W / 4, 1.5
		box(b, f, "Sofa", Vector3.new(6, 1.6, 2.6), sx, 0, sz + 0.5, ({ rgb(90, 110, 150), rgb(150, 90, 70), rgb(110, 130, 90), rgb(160, 150, 140) })[rng:NextInteger(1, 4)], Enum.Material.Fabric)
		box(b, f, "SofaBack", Vector3.new(6, 2, 0.8), sx, 1.6, sz + 1.6, rgb(80, 90, 110), Enum.Material.Fabric)
		local seat = MapKit.seat(b.Model, "SofaSeat", Vector3.new(5, 0.3, 2), at(b, f, sx, 1.8, sz + 0.2), rgb(90, 110, 150), Enum.Material.Fabric, place)
		spot(list, b, f, sx - 1.3, sz, 0, -1, "tv", "home", seat)
		spot(list, b, f, sx + 1.3, sz, 0, -1, "read", "home")
		box(b, f, "TVStand", Vector3.new(4, 1.6, 1.2), sx, 0, -D / 2 + 2.2, rgb(60, 50, 44), Enum.Material.Wood)
		local tv = box(b, f, "TV", Vector3.new(4, 2.4, 0.2), sx, 1.7, -D / 2 + 2.2, rgb(20, 20, 24))
		local screen = deco(b.Model, "TVScreen", Vector3.new(3.6, 2, 0.05), tv.CFrame * CFrame.new(0, 0, 0.13), rgb(120, 170, 255), Enum.Material.Neon)
		screen.Transparency = 0.1
		-- kitchen
		local kx, kz = W / 2 - 4, D / 2 - 2.2
		box(b, f, "KitchenCounter", Vector3.new(6, 3.4, 2), kx - 1, 0, kz, rgb(236, 232, 224), Enum.Material.Marble)
		box(b, f, "Stove", Vector3.new(2.4, 0.2, 1.8), kx - 2.4, 3.4, kz, rgb(40, 40, 44), Enum.Material.Metal)
		box(b, f, "Fridge", Vector3.new(2.4, 6, 2.2), W / 2 - 2, 0, kz - 3.8, rgb(230, 234, 238), Enum.Material.Metal)
		spot(list, b, f, kx - 2.4, kz - 2.2, 0, 1, "cook", "home")
		-- a little dining table
		MapKit.disc(b.Model, "DiningTable", 0.25, 3.4, at(b, f, W / 4 - 1, 2.8, -1).Position, rgb(150, 110, 70), Enum.Material.Wood)
		box(b, f, "TableLeg", Vector3.new(0.4, 2.7, 0.4), W / 4 - 1, 0, -1, rgb(100, 70, 50), Enum.Material.Wood)
		local c1 = chair(b, f, W / 4 - 1, -3.2, 0, 1, nil, place)
		spot(list, b, f, W / 4 - 1, -3.2, 0, 1, "eat", "home", c1)
	end
	if f == b.Floors or b.Floors == 1 then
		-- beds along the back wall (a crib for the little ones)
		local nBeds = if b.Floors == 1 then 2 else 3
		for k = 0, nBeds - 1 do
			local x = -W / 2 + 3.5 + k * 5
			if b.Floors > 1 or k < 2 then
				bed(b, f, x, D / 2 - 4.2 + (if b.Floors == 1 then 0 else 0), list, ({ rgb(90, 130, 200), rgb(200, 110, 140), rgb(120, 180, 120), rgb(230, 190, 90) })[(k + rng:NextInteger(0, 3)) % 4 + 1], "sleep", "home")
			end
		end
		if b.Floors == 1 then
			-- crib
			box(b, f, "Crib", Vector3.new(3, 2.6, 4), -W / 2 + 13, 0, D / 2 - 3.4, rgb(240, 236, 230), Enum.Material.Wood)
			local s = spot(list, b, f, -W / 2 + 13, D / 2 - 4.4, 0, 1, "nap", "home")
			s.BedTop = top(b, f) + 1.8
			s.Crib = true
		end
		box(b, f, "Lamp", Vector3.new(0.8, 4.6, 0.8), -W / 2 + 1.5, 0, 1, rgb(230, 220, 190))
	end
end

function ROOMS.lobby(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, -2, W / 2, D / 2, rgb(90, 80, 70))
	for k = 0, 5 do
		box(b, f, "Mailbox", Vector3.new(1.4, 1.4, 0.6), -W / 2 + 3 + (k % 3) * 1.5, 3 + (k // 3) * 1.5, D / 2 - 1.4, rgb(180, 150, 90), Enum.Material.Metal)
	end
	local seat = MapKit.seat(b.Model, "SofaSeat", Vector3.new(6, 0.4, 2.4), at(b, f, W / 4, 1.8, -D / 2 + 5), rgb(110, 90, 80), Enum.Material.Fabric, place)
	box(b, f, "Sofa", Vector3.new(7, 1.6, 3), W / 4, 0, -D / 2 + 5, rgb(110, 90, 80), Enum.Material.Fabric)
	spot(list, b, f, W / 4, -D / 2 + 5, 0, -1, "phone", "home", seat)
	plant(b, f, -W / 2 + 2.5, -D / 2 + 3)
end

function ROOMS.apartment(b, f, list, rng, place)
	-- upper floors of apartment buildings: two small flats with beds and a sofa
	local W, D = b.W, b.D
	for k = 0, 1 do
		local x0 = -W / 4 + k * (W / 2)
		box(b, f, "PartyWall", Vector3.new(0.4, FLOOR_H - 1, D - 2), 0, 0, 0, rgb(236, 230, 220))
		bed(b, f, x0 - 4, D / 2 - 4.2, list, ({ rgb(90, 130, 200), rgb(200, 110, 140) })[k + 1], "sleep", "home")
		bed(b, f, x0 + 4, D / 2 - 4.2, list, rgb(120, 180, 120), "sleep", "home")
		box(b, f, "Sofa", Vector3.new(5, 1.6, 2.4), x0, 0, -D / 2 + 4, rgb(150, 130, 110), Enum.Material.Fabric)
		spot(list, b, f, x0, -D / 2 + 4.4, 0, 1, "tv", "home")
		box(b, f, "KitchenCounter", Vector3.new(4, 3.4, 1.8), x0 + (if k == 0 then -W / 4 + 3 else W / 4 - 3), 0, 0, rgb(236, 232, 224), Enum.Material.Marble)
		spot(list, b, f, x0 + (if k == 0 then -W / 4 + 3 else W / 4 - 3), -2, 0, 1, "cook", "home")
	end
end

function ROOMS.daycare(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, 0, W - 6, D - 6, rgb(250, 220, 120))
	for k = 0, 5 do
		MapKit.ball(b.Model, "ToyBall", 1.2, at(b, f, -W / 3 + k * 3, 0.6, 2 + (k % 2) * 3), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1])
		box(b, f, "Block", Vector3.new(1, 1, 1), -W / 3 + k * 3 + 1, 0, -2, MapKit.FLOWERS[(k + 2) % #MapKit.FLOWERS + 1])
	end
	for k = 0, 5 do
		spot(list, b, f, -W / 3 + k * 3.4, (k % 2) * 4 - 1, (k % 2) * 2 - 1, 1, "crawl", "kid")
	end
	for k = 0, 3 do
		local s = bed(b, f, -W / 2 + 4 + k * 5, D / 2 - 4.5, list, rgb(250, 200, 220), "nap", "kid")
		s.Crib = true
	end
	spot(list, b, f, 0, -D / 2 + 5, 0, 1, "babysit", "work")
	spot(list, b, f, W / 3, 3, -1, 0, "babysit", "work")
end

function ROOMS.museum(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, 0, 8, D - 6, rgb(60, 60, 90))
	for k = 0, 3 do
		local x = -W / 2 + 6 + k * ((W - 12) / 3)
		box(b, f, "Pedestal", Vector3.new(3, 3, 3), x, 0, 3, WHITE, Enum.Material.Marble)
		local c = ({ MapKit.GOLD, rgb(120, 200, 240), rgb(220, 120, 90), rgb(160, 220, 140) })[k + 1]
		if k % 2 == 0 then
			MapKit.ball(b.Model, "Exhibit", 2.2, at(b, f, x, 4.1, 3), c, Enum.Material.Glass)
		else
			box(b, f, "Exhibit", Vector3.new(1.4, 2.6, 1.4), x, 3, 3, c, Enum.Material.Marble)
		end
		box(b, f, "Painting", Vector3.new(5, 3.6, 0.2), x, 3.4, D / 2 - 1.2, MapKit.FLOWERS[k + 1]:Lerp(rgb(60, 50, 40), 0.3))
		box(b, f, "Frame", Vector3.new(5.6, 4.2, 0.15), x, 3.1, D / 2 - 1.1, MapKit.GOLD, Enum.Material.Metal)
		spot(list, b, f, x, -0.6, 0, 1, "browse", "visit")
		spot(list, b, f, x + 1, D / 2 - 5, 0, 1, "browse", "visit")
	end
	-- a dinosaur skeleton in the middle
	for k = 0, 5 do
		box(b, f, "Bone", Vector3.new(0.6, 0.6, 2), -3 + k * 1.3, 5 + math.sin(k) * 0.8, -4, rgb(236, 226, 200))
	end
	spot(list, b, f, 0, -D / 2 + 6, 0, 1, "guide", "work")
	spot(list, b, f, W / 2 - 5, -D / 2 + 5, -1, 0, "counter", "work")
end

function ROOMS.postoffice(b, f, list, rng, place)
	local W, D = b.W, b.D
	counter(b, f, 0, 1, W - 12, rgb(60, 80, 140))
	for k = 0, 1 do
		spot(list, b, f, -4 + k * 8, 3.4, 0, -1, "counter", "work")
		spot(list, b, f, -4 + k * 8, -1.4, 0, 1, "wait", "visit")
	end
	for k = 0, 3 do
		box(b, f, "Parcel", Vector3.new(2, 1.6, 1.6), -W / 2 + 4 + k * 2.4, 0, D / 2 - 3, rgb(190, 150, 100))
	end
	box(b, f, "SortingShelf", Vector3.new(10, 6, 1.4), W / 4, 0, D / 2 - 2, rgb(200, 190, 170), Enum.Material.Wood)
	spot(list, b, f, W / 4, D / 2 - 4.4, 0, 1, "sort", "work")
end

function ROOMS.arcade(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, 0, W - 4, D - 4, rgb(40, 20, 70))
	for k = 0, 5 do
		local x = -W / 2 + 4 + k * ((W - 8) / 5)
		local cab = box(b, f, "ArcadeCabinet", Vector3.new(3, 6.4, 2.4), x, 0, D / 2 - 2.6, rgb(30, 30, 40))
		local screen = deco(b.Model, "ArcadeScreen", Vector3.new(2.4, 1.8, 0.1), cab.CFrame * CFrame.new(0, 1, -1.25), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.Neon)
		MapKit.light(screen, screen.Color, 8, 0.8)
		spot(list, b, f, x, D / 2 - 5, 0, 1, "game", "visit")
	end
	counter(b, f, -W / 2 + 6, -D / 2 + 5, 7, rgb(200, 40, 140))
	spot(list, b, f, -W / 2 + 6, -D / 2 + 7.4, 0, -1, "cashier", "work")
end

function ROOMS.community(b, f, list, rng, place)
	local W, D = b.W, b.D
	-- a hall with a small stage, tables and a ping pong table
	box(b, f, "Stage", Vector3.new(14, 1.4, 6), 0, 0, D / 2 - 4, rgb(150, 100, 60), Enum.Material.WoodPlanks)
	spot(list, b, f, 0, D / 2 - 4, 0, -1, "present", "work")
	for k = 0, 1 do
		tableSet(b, f, -W / 4 + k * (W / 2), -2, list, "chess", place, rgb(220, 210, 190))
	end
	box(b, f, "PingPong", Vector3.new(5, 0.3, 9), 0, 2.6, -D / 2 + 7, rgb(40, 110, 70))
	box(b, f, "PingPongNet", Vector3.new(5.4, 0.6, 0.1), 0, 2.9, -D / 2 + 7, WHITE)
	spot(list, b, f, 0, -D / 2 + 1.6, 0, 1, "hoops", "visit")
	spot(list, b, f, 0, -D / 2 + 12.4, 0, -1, "hoops", "visit")
end

-- high office floors: simple desks (fewer parts), still somewhere to work
function ROOMS.officeLight(b, f, list, rng, place)
	local W, D = b.W, b.D
	for cx = 0, 2 do
		for rz = 0, 1 do
			local x = -8 + cx * 8
			local z = -D / 2 + 7 + rz * 9
			box(b, f, "Desk", Vector3.new(5, 0.3, 2.6), x, 2.9, z, rgb(200, 200, 204), Enum.Material.SmoothPlastic)
			box(b, f, "Screen", Vector3.new(2.4, 1.4, 0.15), x, 3.1, z - 0.8, rgb(120, 190, 255), Enum.Material.Neon)
			local seat = MapKit.seat(b.Model, "OfficeChair", Vector3.new(2, 0.4, 2), at(b, f, x, 1.7, z + 2), rgb(40, 40, 46), Enum.Material.Fabric, place)
			spot(list, b, f, x, z + 2, 0, -1, "type", "work", seat)
		end
	end
	plant(b, f, -W / 2 + 2.5, D / 2 - 2.5)
end

Interiors.Rooms = ROOMS

-- Furnishes a building. rooms: a room type for the ground floor and one for
-- the floors above (or a function(f) -> room type). Returns the list of spots.
function Interiors.furnish(b, rooms, rng, place)
	local list = {}
	for f = 1, b.Floors do
		-- a single room type furnishes the ground floor only
		local kind = if type(rooms) == "function" then rooms(f) elseif type(rooms) == "table" then (rooms[f] or (f > 1 and rooms.Upper) or nil) elseif f == 1 then rooms else nil
		local fn = kind and ROOMS[kind]
		if fn then
			fn(b, f, list, rng, place)
		end
	end
	return list
end

return Interiors
