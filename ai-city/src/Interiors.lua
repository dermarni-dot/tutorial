-- Interiors (ModuleScript) — ServerScriptService.Modules.Interiors
-- Furnishes buildings and marks the spots where people do things there:
-- desks to type at, treadmills to run on, stoves to cook at, tables to eat
-- at, beds to sleep in... Each spot is
--   { CFrame = where the feet go (facing the right way), Action = see Actions,
--     Role = "work" / "visit" / "home", Floor = n, Seat = seat part or nil }
-- Furniture doesn't block movement (citizens walk straight to their spot).

local MapKit = require(script.Parent:WaitForChild("MapKit"))
local Decor = require(script.Parent:WaitForChild("Decor"))

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
	-- (two side frames instead of four legs: half the parts, same look)
	for _, lx in ipairs({ -0.8, 0.8 }) do
		deco(b.Model, "ChairLeg", Vector3.new(0.2, 1.6, 1.8), at(b, f, x, 0.8, z, rot) * CFrame.new(lx, 0, 0), color:Lerp(BLACK, 0.3))
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
		local screen = box(b, f, "Monitor", Vector3.new(2.6, 1.6, 0.2), x, 3.2, z - s * 0.8, rgb(30, 32, 38), Enum.Material.SmoothPlastic)
		deco(b.Model, "Screen", Vector3.new(2.3, 1.3, 0.05), screen.CFrame * CFrame.new(0, 0, s * 0.12), rgb(120, 190, 255), Enum.Material.Neon)
		box(b, f, "Keyboard", Vector3.new(2, 0.12, 0.7), x, 3.2, z + s * 0.3, rgb(40, 42, 48))
		box(b, f, "Mug", Vector3.new(0.4, 0.5, 0.4), x + 1.8, 3.2, z, ({ rgb(220, 60, 60), WHITE, rgb(60, 120, 220) })[(math.floor(x + z) % 3) + 1])
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

-- What's on the shelves, by shop: { size, colors, material, neon label? }
local STOCK = {
	Bookstore = { Vector3.new(0.35, 1.25, 1), { rgb(170, 50, 50), rgb(50, 90, 160), rgb(60, 130, 80), rgb(220, 180, 70), rgb(120, 70, 140), rgb(230, 230, 220) }, Enum.Material.SmoothPlastic, Gap = 0.42 },
	Electronics = { Vector3.new(1.1, 0.8, 0.9), { rgb(30, 30, 34), rgb(60, 62, 70), rgb(230, 230, 235) }, Enum.Material.SmoothPlastic, Screen = true },
	Pharmacy = { Vector3.new(0.6, 0.8, 0.6), { WHITE, rgb(220, 240, 230), rgb(250, 220, 220), rgb(60, 170, 110) }, Enum.Material.SmoothPlastic, Gap = 0.8 },
	Hardware = { Vector3.new(1, 1, 0.9), { rgb(230, 120, 40), rgb(120, 124, 132), rgb(240, 200, 60), rgb(60, 110, 170) }, Enum.Material.Metal },
	Mall = { Vector3.new(1.1, 0.5, 0.9), { rgb(255, 92, 122), rgb(90, 160, 255), rgb(250, 250, 250), rgb(60, 60, 66), rgb(168, 110, 255) }, Enum.Material.Fabric, Stack = 3 },
	PetShop = { Vector3.new(0.9, 1.3, 0.6), { rgb(200, 150, 90), rgb(90, 150, 200), rgb(220, 90, 70) }, Enum.Material.Fabric },
	ToyStore = { Vector3.new(0.9, 0.9, 0.9), { rgb(255, 92, 122), rgb(255, 208, 60), rgb(90, 160, 255), rgb(120, 220, 120) }, Enum.Material.SmoothPlastic, Balls = true },
}

-- A store shelf: an open unit (base, back panel, three shelf boards and end
-- posts) with goods sitting on the boards, on both sides when it stands in
-- the room (sideways) or facing the room when it stands against the back wall.
local function shelf(b, f, x, z, len, rng, sideways, place)
	local stock = STOCK[place] or {}
	local wood = rgb(210, 200, 184)
	local function sz(along, h, across)
		return if sideways then Vector3.new(across, h, along) else Vector3.new(along, h, across)
	end
	local function pos(along, across)
		return if sideways then x + across else x + along, if sideways then z + along else z + across
	end
	box(b, f, "ShelfBase", sz(len, 0.6, 1.8), x, 0, z, wood:Lerp(BLACK, 0.25), Enum.Material.Wood)
	box(b, f, "Shelf", sz(len, 7, 0.25), x, 0, z, wood, Enum.Material.Wood)
	for _, e in ipairs({ -1, 1 }) do
		local ex, ez = pos(e * (len / 2 - 0.1), 0)
		box(b, f, "ShelfEnd", sz(0.2, 7, 1.8), ex, 0, ez, wood:Lerp(BLACK, 0.15), Enum.Material.Wood)
	end
	local sides = if sideways then { -1, 1 } else { -1 }
	for row = 0, 2 do
		local y = 0.6 + row * 2.2
		if row > 0 then
			box(b, f, "ShelfBoard", sz(len - 0.2, 0.15, 1.8), x, y - 0.15, z, wood, Enum.Material.Wood)
		end
		local size = stock[1] or Vector3.new(0.9, 1, 0.8)
		local gap = stock.Gap or 1.3
		local n = math.floor((len - 0.6) / gap)
		for _, side in ipairs(sides) do
			for k = 0, n - 1 do
				if rng:NextNumber() < 0.9 then
					local off = -len / 2 + 0.3 + gap / 2 + k * gap
					local px, pz = pos(off, side * 0.55)
					local colors = stock[2] or MapKit.FLOWERS
					local c = colors[rng:NextInteger(1, #colors)]
					if not stock[2] then
						c = c:Lerp(rgb(200, 200, 200), 0.2)
					end
					local h = size.Y * (if stock[2] then 1 else 1 + (k % 2) * 0.4)
					if stock.Balls and k % 2 == 1 then
						MapKit.ball(b.Model, "Product", 0.9, at(b, f, px, y + 0.45, pz), c, Enum.Material.SmoothPlastic)
					else
						for s = 0, (stock.Stack or 1) - 1 do
							local item = box(b, f, "Product", sz(size.X, h, size.Z), px, y + s * h, pz, c, stock[3])
							if stock.Screen then
								local sx, sz2 = pos(off, side * 1.02)
								box(b, f, "ProductScreen", sz(size.X - 0.2, h - 0.25, 0.05), sx, y + 0.12, sz2, rgb(90, 160, 255), Enum.Material.Neon)
							end
							local _ = item
						end
					end
				end
			end
		end
	end
end

local function plant(b, f, x, z)
	box(b, f, "Pot", Vector3.new(1.4, 1.4, 1.4), x, 0, z, rgb(180, 110, 80), Enum.Material.Slate)
	MapKit.ball(b.Model, "PlantLeaves", 2.6, at(b, f, x, 2.8, z), MapKit.LEAVES[(math.floor(x * 3 + z) % #MapKit.LEAVES) + 1], Enum.Material.SmoothPlastic)
end

local function rug(b, f, x, z, w, d, color)
	box(b, f, "Rug", Vector3.new(w, 0.06, d), x, 0, z, color, Enum.Material.Fabric)
end

local function tableSet(b, f, x, z, list, action, place, color)
	MapKit.disc(b.Model, "TableTop", 0.25, 4, at(b, f, x, 3, z).Position, color or WHITE, Enum.Material.Wood)
	box(b, f, "TableLeg", Vector3.new(0.4, 2.9, 0.4), x, 0, z, rgb(60, 60, 64), Enum.Material.Metal)
	if action == "chess" then
		MapKit.chessBoard(b.Model, at(b, f, x, 3.18, z), 2.6)
	else
		-- a meal on each plate (burgers and fries at the diner)
		local diner = place == "Diner"
		for _, side in ipairs({ -1, 1 }) do
			box(b, f, "Plate", Vector3.new(1.2, 0.08, 1.2), x, 3.12, z + side * 0.8, WHITE)
			if action == "eat" then
				local dish = if diner then (if side < 0 then "burger" else "fries") else (if (math.floor(x + z) + side) % 2 == 0 then "pasta" else "pizza")
				MapKit.food(b.Model, dish, at(b, f, x, 3.2, z + side * 0.8), 0.8)
			elseif action == "coffee" then
				MapKit.food(b.Model, if side < 0 then "croissant" else "cookie", at(b, f, x, 3.2, z + side * 0.8), 0.7)
			end
		end
	end
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
	box(b, f, "Whiteboard", Vector3.new(6, 3.4, 0.2), 0, 3.5, D / 2 - 1.2 + (if b.CurtainWall then 0.85 else 0), WHITE)
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
		box(b, f, "BagChain", Vector3.new(0.2, 3.1, 0.2), bx, 8.5, 3, rgb(120, 120, 126), Enum.Material.Metal)
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
	box(b, f, "PastryCase", Vector3.new(4, 1.6, 2), 4, 3.85, D / 2 - 5, rgb(200, 230, 240)).Transparency = 0.6
	for k, kind in ipairs({ "croissant", "muffin", "cookie", "donut" }) do
		MapKit.food(b.Model, kind, at(b, f, 2.4 + (k - 1) * 1.05, 3.9, D / 2 - 5), 0.9)
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
	-- fresh bread and pastries on the counter, in baskets and on trays
	local goods = { "loaf", "croissant", "baguette", "donut", "muffin", "pretzel", "cupcake", "loaf" }
	for k = 0, math.floor((W - 18) / 2.4) do
		local x = -W / 2 + 7 + k * 2.4
		box(b, f, "Tray", Vector3.new(2.1, 0.1, 1.8), x, 3.85, -2.2, rgb(170, 120, 80), Enum.Material.Wood)
		MapKit.food(b.Model, goods[k % #goods + 1], at(b, f, x, 3.95, -2.2), 1)
	end
	-- a glass display case of cakes and sweets at the front of the counter
	local caseW = math.min(10, W - 16)
	box(b, f, "DisplayCase", Vector3.new(caseW, 3.4, 1.6), -W / 2 + 5 + caseW / 2, 0, -4.1, rgb(240, 236, 228), Enum.Material.Wood)
	local glass = box(b, f, "CaseGlass", Vector3.new(caseW, 1.8, 1.6), -W / 2 + 5 + caseW / 2, 3.4, -4.1, rgb(220, 240, 250), Enum.Material.Glass)
	glass.Transparency = 0.65
	local sweets = { "cake", "cupcake", "pie", "donut", "cookie", "cupcake" }
	for k = 0, math.floor(caseW / 1.8) - 1 do
		MapKit.food(b.Model, sweets[k % #sweets + 1], at(b, f, -W / 2 + 6 + k * 1.8, 3.45, -4.1), if sweets[k % #sweets + 1] == "cake" or sweets[k % #sweets + 1] == "pie" then 0.8 else 1)
	end
	-- bread racks on the side wall: three shelves of loaves and baguettes
	local rx = W / 2 - 1.6
	box(b, f, "BreadRack", Vector3.new(1.6, 7, 7), rx, 0, -D / 2 + 7, rgb(150, 110, 70), Enum.Material.Wood)
	for shelf = 0, 2 do
		local y = 1.2 + shelf * 2.2
		box(b, f, "RackShelf", Vector3.new(1.8, 0.15, 7), rx - 0.2, y, -D / 2 + 7, rgb(120, 86, 58), Enum.Material.Wood)
		for k = 0, 3 do
			MapKit.food(b.Model, if (shelf + k) % 3 == 0 then "baguette" else "loaf", at(b, f, rx - 0.3, y + 0.15, -D / 2 + 4.5 + k * 1.7, CFrame.Angles(0, math.rad(90), 0)), 0.8)
		end
	end
	-- a basket of baguettes by the door
	box(b, f, "Basket", Vector3.new(1.4, 1.4, 1.4), -W / 2 + 3, 0, -D / 2 + 3, rgb(180, 130, 70), Enum.Material.Wood)
	for k = 0, 3 do
		local p = MapKit.deco(b.Model, "Baguette", Vector3.new(2.2, 0.3, 0.3), at(b, f, -W / 2 + 3 + (k % 2) * 0.3 - 0.15, 2.2, -D / 2 + 3 + (k // 2) * 0.3 - 0.15, CFrame.Angles(0, 0, math.rad(80))), rgb(196, 128, 60))
		p.Shape = Enum.PartType.Cylinder
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

local DISPLAY_SHOPS = { Florist = true, PetShop = true, ToyStore = true, IceCream = true, Electronics = true }

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
	if DISPLAY_SHOPS[place] then
		-- specialty shops keep floor space for their displays (see Decor)
		rows = math.max(1, rows - 1)
	end
	for k = 0, rows - 1 do
		local x = -W / 2 + 5 + k * 7
		shelf(b, f, x, 2, math.min(10, D - 12), rng, true, place)
		spot(list, b, f, x + 2, 1, -1, 0, "browse", "visit")
	end
	shelf(b, f, 0, D / 2 - 2, W - 8, rng, false, place)
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
	box(b, f, "ChandelierChain", Vector3.new(0.15, 1.9, 0.15), 0, FLOOR_H - 1.45, -2, MapKit.GOLD, Enum.Material.Metal)
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
	local lamp = box(b, f, "CellLamp", Vector3.new(1.6, 0.4, 1.6), cx, h - 0.2, (zf + zb) / 2, rgb(255, 240, 200), Enum.Material.Neon)
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
		box(b, f, "MonitorStand", Vector3.new(0.2, 4, 0.2), x - 2.8, 0, D / 2 - 3, rgb(190, 194, 200), Enum.Material.Metal)
		box(b, f, "MonitorBase", Vector3.new(1.2, 0.15, 1.2), x - 2.8, 0, D / 2 - 3, rgb(190, 194, 200), Enum.Material.Metal)
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
	box(b, f, "GlobeStand", Vector3.new(0.25, 3.3, 0.25), -W / 2 + 3, 0, -D / 2 + 4, rgb(150, 110, 70), Enum.Material.Wood)
	box(b, f, "GlobeBase", Vector3.new(1.4, 0.2, 1.4), -W / 2 + 3, 0, -D / 2 + 4, rgb(150, 110, 70), Enum.Material.Wood)
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
	box(b, f, "ProjectorStand", Vector3.new(2.8, 6, 3.2), 0, 0, -D / 2 + 2.4, rgb(70, 50, 40), Enum.Material.Wood)
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
		for _, ux in ipairs({ -4.85, 4.85 }) do
			for _, uz in ipairs({ -1.85, 1.85 }) do
				box(b, f, "RackUpright", Vector3.new(0.3, 8.4, 0.3), x + ux, 0, D / 2 - 4 + uz, rgb(40, 90, 170), Enum.Material.Metal)
			end
		end
		for n = 0, 3 do
			box(b, f, "Crate", Vector3.new(2.2, 2.2, 2.2), x - 3.6 + n * 2.4, 0 + (n % 2) * 4.4, D / 2 - 4, rgb(170, 125, 75), Enum.Material.WoodPlanks)
		end
		spot(list, b, f, x, D / 2 - 8, 0, 1, "carrybox", "work")
	end
	-- forklift
	box(b, f, "Forklift", Vector3.new(3.4, 3, 5), 0, 0.8, -2, rgb(250, 190, 40), Enum.Material.Metal)
	box(b, f, "ForkMast", Vector3.new(3, 7, 0.4), 0, 0.8, -4.7, rgb(60, 60, 66), Enum.Material.Metal)
	for _, wx in ipairs({ -1.9, 1.9 }) do
		for _, wz in ipairs({ -3.6, -0.4 }) do
			MapKit.cylinder(b.Model, "ForkWheel", 0.6, 1.6, at(b, f, wx, 0.8, wz), rgb(25, 25, 28), Enum.Material.Rubber)
		end
	end
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

-- A double bed (head toward +Z): room for two
local function doubleBed(b, f, x, z, list, color)
	box(b, f, "BedFrame", Vector3.new(6.4, 1.4, 7.6), x, 0, z, rgb(120, 86, 60), Enum.Material.Wood)
	box(b, f, "Mattress", Vector3.new(6, 0.8, 7.2), x, 1.4, z, WHITE, Enum.Material.Fabric)
	box(b, f, "Blanket", Vector3.new(6.1, 0.3, 4.8), x, 2.1, z - 1.1, color, Enum.Material.Fabric)
	box(b, f, "BlanketFold", Vector3.new(6.1, 0.35, 0.8), x, 2.15, z + 1.5, color:Lerp(WHITE, 0.35), Enum.Material.Fabric)
	for _, px in ipairs({ -1.5, 1.5 }) do
		box(b, f, "Pillow", Vector3.new(2.4, 0.6, 1.2), x + px, 2.2, z + 2.9, WHITE, Enum.Material.Fabric)
		local s = spot(list, b, f, x + px, z - 1.4, 0, 1, "sleep", "home")
		s.BedTop = top(b, f) + 2.2
	end
	box(b, f, "Headboard", Vector3.new(6.6, 4, 0.5), x, 0, z + 3.85, rgb(100, 70, 50), Enum.Material.Wood)
end

local function wardrobe(b, f, x, z, alongX, color)
	color = color or rgb(150, 110, 75)
	local size = if alongX then Vector3.new(4.4, 7, 2) else Vector3.new(2, 7, 4.4)
	box(b, f, "Wardrobe", size, x, 0, z, color, Enum.Material.Wood)
	for _, s in ipairs({ -1, 1 }) do
		local hx, hz = if alongX then x + s * 0.3 else x, if alongX then z else z + s * 0.3
		local off = if alongX then Vector3.new(0, 0, 0) else Vector3.new(0, 0, 0)
		local _ = off
		box(b, f, "WardrobeHandle", Vector3.new(0.15, 0.9, 0.15), hx + (if alongX then 0 else (if x < 0 then 1.05 else -1.05)), 3.2, hz + (if alongX then (if z > 0 then -1.05 else 1.05) else 0), rgb(210, 190, 120), Enum.Material.Metal)
	end
end

local function dresser(b, f, x, z, alongX)
	local size = if alongX then Vector3.new(4, 3, 1.8) else Vector3.new(1.8, 3, 4)
	box(b, f, "Dresser", size, x, 0, z, rgb(170, 130, 95), Enum.Material.Wood)
	box(b, f, "Mirror", if alongX then Vector3.new(2.6, 2.4, 0.1) else Vector3.new(0.1, 2.4, 2.6), x, 3.4, z, rgb(210, 230, 240), Enum.Material.Glass).Reflectance = 0.4
	box(b, f, "PhotoFrame", Vector3.new(0.6, 0.8, 0.15), x + (if alongX then 1.3 else 0), 3, z + (if alongX then 0 else 1.3), rgb(60, 50, 44))
end

-- a bathroom: walls with an open doorway, toilet, sink and mirror, and a bathtub.
-- (x0, z0)-(x1, z1) is the room; the doorway is on the side facing doorSide ("x" or "z")
local function bathroom(b, f, x0, z0, x1, z1, doorAt)
	local wallC = rgb(236, 240, 242)
	local h = FLOOR_H - 1.2
	local y = top(b, f) + h / 2
	local function wallPiece(cx, cz, sx, sz)
		if sx > 0.2 and sz > 0.2 then
			MapKit.part(b.Model, "BathroomWall", Vector3.new(sx, h, sz), b.At(cx, y, cz), wallC, Enum.Material.SmoothPlastic)
		end
	end
	-- the walls on the open sides (the others are the building's walls), with a 3.2-stud doorway
	for _, side in ipairs(doorAt.Walls) do
		if side == "x0" or side == "x1" then
			local x = if side == "x0" then x0 else x1
			if doorAt.Door == side then
				local mid = (z0 + z1) / 2
				wallPiece(x, (z0 + mid - 1.6) / 2, 0.3, (mid - 1.6) - z0)
				wallPiece(x, (mid + 1.6 + z1) / 2, 0.3, z1 - (mid + 1.6))
			else
				wallPiece(x, (z0 + z1) / 2, 0.3, z1 - z0)
			end
		else
			local z = if side == "z0" then z0 else z1
			if doorAt.Door == side then
				local mid = (x0 + x1) / 2
				wallPiece((x0 + mid - 1.6) / 2, z, (mid - 1.6) - x0, 0.3)
				wallPiece((mid + 1.6 + x1) / 2, z, x1 - (mid + 1.6), 0.3)
			else
				wallPiece((x0 + x1) / 2, z, x1 - x0, 0.3)
			end
		end
	end
	-- a tiled floor
	box(b, f, "BathroomTiles", Vector3.new(x1 - x0 - 0.3, 0.05, z1 - z0 - 0.3), (x0 + x1) / 2, 0, (z0 + z1) / 2, rgb(200, 220, 228), Enum.Material.Marble)
	local w, d = x1 - x0, z1 - z0
	local cx = (x0 + x1) / 2
	local long = d >= w
	-- bathtub along the far side
	local tubX = if long then cx else x0 + 1.4
	local tubZ = if long then z1 - 1.5 else (z0 + z1) / 2
	local tubSize = if long then Vector3.new(math.min(5, w - 0.8), 2, 2.6) else Vector3.new(2.6, 2, math.min(5, d - 0.8))
	box(b, f, "Bathtub", tubSize, tubX, 0, tubZ, WHITE, Enum.Material.Marble)
	box(b, f, "BathWater", tubSize - Vector3.new(0.5, 0, 0.5) + Vector3.new(0, -1.6, 0), tubX, 1.5, tubZ, rgb(150, 210, 240), Enum.Material.Glass).Transparency = 0.4
	box(b, f, "Faucet", Vector3.new(0.3, 0.8, 0.3), tubX + (if long then tubSize.X / 2 - 0.4 else 0), 2, tubZ + (if long then 0 else tubSize.Z / 2 - 0.4), rgb(200, 204, 210), Enum.Material.Metal)
	-- toilet and sink along the near side
	local nearZ = if long then z0 + 1.4 else z0 + 1.4
	box(b, f, "Toilet", Vector3.new(1.4, 1.5, 2), x0 + 1.2, 0, nearZ + 0.4, WHITE, Enum.Material.Marble)
	box(b, f, "ToiletTank", Vector3.new(1.4, 1.6, 0.6), x0 + 1.2, 1.5, nearZ - 0.4, WHITE, Enum.Material.Marble)
	box(b, f, "Sink", Vector3.new(2, 0.5, 1.4), x1 - 1.3, 2.8, nearZ, WHITE, Enum.Material.Marble)
	box(b, f, "SinkStand", Vector3.new(1.6, 2.8, 1.2), x1 - 1.3, 0, nearZ, rgb(150, 150, 156), Enum.Material.Wood)
	local mirror = box(b, f, "BathMirror", Vector3.new(0.1, 2, 1.8), x1 - 0.2, 4.2, nearZ, rgb(210, 230, 240), Enum.Material.Glass)
	mirror.Reflectance = 0.5
	box(b, f, "Towel", Vector3.new(0.15, 1.6, 1.2), x0 + 0.2, 3.4, (z0 + z1) / 2, ({ rgb(90, 160, 220), rgb(240, 150, 170), rgb(120, 200, 150) })[math.floor(math.abs(x0 + z0)) % 3 + 1], Enum.Material.Fabric)
	-- (on a little stand, so it never hangs in the air)
	for _, tz in ipairs({ -0.65, 0.65 }) do
		box(b, f, "TowelRack", Vector3.new(0.12, 5.1, 0.12), x0 + 0.2, 0, (z0 + z1) / 2 + tz, rgb(200, 200, 206), Enum.Material.Metal)
	end
end

local function kitchen(b, f, x0, x1, z, list)
	-- counters along the back wall: sink, stove and oven, microwave; cupboards above
	local w = x1 - x0
	local cx = (x0 + x1) / 2
	box(b, f, "KitchenCounter", Vector3.new(w, 3.4, 2.2), cx, 0, z, rgb(240, 236, 228), Enum.Material.Wood)
	box(b, f, "Worktop", Vector3.new(w + 0.2, 0.25, 2.4), cx, 3.4, z, rgb(70, 70, 76), Enum.Material.Granite)
	box(b, f, "UpperCabinets", Vector3.new(w, 2.4, 1.3), cx, 6.4, z + 0.45, rgb(240, 236, 228), Enum.Material.Wood)
	for k = 0, math.floor(w / 2.4) - 1 do
		box(b, f, "CabinetHandle", Vector3.new(0.8, 0.12, 0.12), x0 + 1.2 + k * 2.4, 2.8, z - 1.15, rgb(180, 184, 190), Enum.Material.Metal)
	end
	-- sink with a tap
	box(b, f, "KitchenSink", Vector3.new(2.4, 0.2, 1.6), x0 + 2, 3.5, z, rgb(200, 204, 210), Enum.Material.Metal)
	box(b, f, "Tap", Vector3.new(0.2, 1, 0.2), x0 + 2, 3.6, z + 0.8, rgb(200, 204, 210), Enum.Material.Metal)
	-- stove, oven door and knobs
	local sx = x0 + w * 0.55
	box(b, f, "Stove", Vector3.new(2.6, 0.12, 2), sx, 3.66, z, rgb(30, 30, 34), Enum.Material.Metal)
	for _, o in ipairs({ { -0.6, -0.5 }, { 0.6, -0.5 }, { -0.6, 0.5 }, { 0.6, 0.5 } }) do
		local burner = box(b, f, "Burner", Vector3.new(0.7, 0.05, 0.7), sx + o[1], 3.78, z + o[2], rgb(70, 70, 76), Enum.Material.Metal)
		local _ = burner
	end
	box(b, f, "OvenDoor", Vector3.new(2.4, 2, 0.1), sx, 0.8, z - 1.15, rgb(40, 40, 44), Enum.Material.Glass)
	box(b, f, "Pot", Vector3.new(1.1, 0.8, 1.1), sx - 0.6, 3.78, z - 0.5, rgb(170, 170, 176), Enum.Material.Metal)
	spot(list, b, f, sx, z - 2.3, 0, 1, "cook", "home")
	-- microwave and a kettle
	if w > 8 then
		box(b, f, "Microwave", Vector3.new(1.8, 1.1, 1.3), x1 - 1.4, 3.65, z + 0.3, rgb(230, 232, 236), Enum.Material.Metal)
		box(b, f, "MicrowaveDoor", Vector3.new(1.1, 0.8, 0.05), x1 - 1.6, 3.8, z - 0.38, rgb(30, 30, 34), Enum.Material.Glass)
	end
	box(b, f, "Kettle", Vector3.new(0.6, 0.8, 0.6), x0 + 3.8, 3.65, z + 0.3, rgb(200, 60, 60), Enum.Material.Metal)
	box(b, f, "FruitBowl", Vector3.new(1.2, 0.3, 1.2), x0 + 5.2, 3.65, z, rgb(200, 180, 140), Enum.Material.Wood)
	for k = 0, 2 do
		MapKit.ball(b.Model, "Fruit", 0.45, at(b, f, x0 + 4.9 + k * 0.3, 4.1, z + (k % 2) * 0.3), ({ rgb(220, 50, 50), rgb(250, 190, 40), rgb(110, 190, 60) })[k + 1])
	end
end

local function fridge(b, f, x, z, faceX)
	-- a tall fridge, doors facing along -x (faceX = -1) or +x
	box(b, f, "Fridge", Vector3.new(2.4, 6.4, 2.4), x, 0, z, rgb(228, 232, 236), Enum.Material.Metal)
	box(b, f, "FridgeHandle", Vector3.new(0.15, 1.8, 0.15), x + faceX * 1.25, 3.8, z - 0.8, rgb(170, 174, 180), Enum.Material.Metal)
	box(b, f, "FridgeHandle", Vector3.new(0.15, 1.2, 0.15), x + faceX * 1.25, 1.6, z - 0.8, rgb(170, 174, 180), Enum.Material.Metal)
	box(b, f, "FridgeMagnet", Vector3.new(0.05, 0.4, 0.4), x + faceX * 1.23, 4.8, z + 0.3, rgb(250, 190, 40))
end

local function livingRoom(b, f, x, z, list, rng, place)
	-- a sofa facing a TV on the left wall, an armchair, a rug
	local W = b.W
	local fabric = ({ rgb(90, 110, 150), rgb(150, 90, 70), rgb(110, 130, 90), rgb(160, 150, 140), rgb(70, 70, 80) })[rng:NextInteger(1, 5)]
	rug(b, f, x - 1, z, 8, 7, ({ rgb(170, 70, 60), rgb(70, 110, 150), rgb(200, 170, 110), rgb(90, 130, 90) })[rng:NextInteger(1, 4)])
	-- TV on a low unit against the left wall, facing +x
	local tvX = -W / 2 + 1.6
	box(b, f, "TVStand", Vector3.new(1.6, 1.6, 5), tvX, 0, z, rgb(60, 50, 44), Enum.Material.Wood)
	local tv = box(b, f, "TV", Vector3.new(0.2, 2.8, 4.6), tvX, 1.7, z, rgb(20, 20, 24))
	local screen = deco(b.Model, "TVScreen", Vector3.new(0.05, 2.4, 4.2), tv.CFrame * CFrame.new(0.13, 0, 0), rgb(120, 170, 255), Enum.Material.Neon)
	screen.Transparency = 0.1
	box(b, f, "Speaker", Vector3.new(0.8, 2.2, 0.8), tvX, 0, z - 3.2, rgb(40, 40, 44))
	box(b, f, "Speaker", Vector3.new(0.8, 2.2, 0.8), tvX, 0, z + 3.2, rgb(40, 40, 44))
	-- the sofa across the room, back to +x, facing the TV (-x)
	local sx = x + 3.5
	box(b, f, "Sofa", Vector3.new(2.6, 1.6, 6.4), sx, 0, z, fabric, Enum.Material.Fabric)
	box(b, f, "SofaBack", Vector3.new(0.8, 2.1, 6.4), sx + 1.1, 1.6, z, fabric:Lerp(BLACK, 0.12), Enum.Material.Fabric)
	for _, e in ipairs({ -1, 1 }) do
		box(b, f, "SofaArm", Vector3.new(2.6, 2.3, 0.7), sx, 0, z + e * 3.2, fabric:Lerp(BLACK, 0.12), Enum.Material.Fabric)
	end
	box(b, f, "Cushion", Vector3.new(0.5, 1.1, 1.2), sx + 0.5, 1.6, z - 1.8, fabric:Lerp(WHITE, 0.45), Enum.Material.Fabric)
	local seat = MapKit.seat(b.Model, "SofaSeat", Vector3.new(2, 0.3, 5.2), at(b, f, sx - 0.2, 1.8, z), fabric, Enum.Material.Fabric, place)
	spot(list, b, f, sx - 0.3, z - 1.4, -1, 0, "tv", "home", seat)
	spot(list, b, f, sx - 0.3, z + 1.4, -1, 0, "read", "home")
	-- an armchair at the side, angled toward the TV
	local ax, az = x, z - 4.6
	box(b, f, "Armchair", Vector3.new(2.6, 1.6, 2.6), ax, 0, az, fabric:Lerp(WHITE, 0.2), Enum.Material.Fabric)
	box(b, f, "ArmchairBack", Vector3.new(2.6, 2, 0.6), ax, 1.6, az - 1, fabric:Lerp(WHITE, 0.1), Enum.Material.Fabric)
	-- a side table with a lamp
	box(b, f, "SideTable", Vector3.new(1.4, 2, 1.4), sx, 0, z - 4.4, rgb(130, 90, 60), Enum.Material.Wood)
	local lamp = box(b, f, "TableLamp", Vector3.new(0.9, 1.1, 0.9), sx, 2, z - 4.4, rgb(255, 236, 190), Enum.Material.Fabric)
	MapKit.light(lamp, rgb(255, 220, 170), 12, 0.6)
end

local function diningTable(b, f, x, z, list, place)
	-- a table for four with plates and a vase
	box(b, f, "DiningTable", Vector3.new(5, 0.3, 3.2), x, 2.8, z, rgb(150, 110, 70), Enum.Material.Wood)
	for _, lx in ipairs({ -2.2, 2.2 }) do
		for _, lz in ipairs({ -1.3, 1.3 }) do
			box(b, f, "TableLeg", Vector3.new(0.3, 2.8, 0.3), x + lx, 0, z + lz, rgb(110, 80, 50), Enum.Material.Wood)
		end
	end
	box(b, f, "Vase", Vector3.new(0.6, 1, 0.6), x, 3.1, z, rgb(80, 140, 200), Enum.Material.Glass)
	MapKit.ball(b.Model, "Flowers", 0.9, at(b, f, x, 4.4, z), MapKit.FLOWERS[math.floor(math.abs(x * 7 + z)) % #MapKit.FLOWERS + 1])
	local first = true
	for _, lx in ipairs({ -1.3, 1.3 }) do
		for _, side in ipairs({ -1, 1 }) do
			box(b, f, "Plate", Vector3.new(1, 0.08, 1), x + lx, 3.12, z + side * 0.9, WHITE)
			local seat = chair(b, f, x + lx, z + side * 2.4, 0, -side, nil, place)
			if first or side == 1 then
				spot(list, b, f, x + lx, z + side * 2.4, 0, -side, "eat", "home", seat)
			end
			first = false
		end
	end
end

local function kidsDesk(b, f, x, z, list, place)
	box(b, f, "KidsDesk", Vector3.new(4, 0.25, 2.2), x, 2.6, z, rgb(250, 240, 220), Enum.Material.Wood)
	box(b, f, "DeskDrawers", Vector3.new(1.4, 2.6, 2), x + 1.3, 0, z, rgb(250, 240, 220), Enum.Material.Wood)
	box(b, f, "DeskLamp", Vector3.new(0.5, 1.2, 0.5), x - 1.4, 2.85, z + 0.5, rgb(90, 160, 220), Enum.Material.Metal)
	box(b, f, "Notebook", Vector3.new(1.2, 0.08, 0.9), x, 2.88, z, rgb(250, 250, 245))
	local seat = chair(b, f, x, z - 2, 0, 1, rgb(90, 160, 220), place)
	spot(list, b, f, x, z - 2, 0, 1, "study", "home", seat)
end

-- extra rooms for the big suburban houses
local function homeOffice(b, f, x, z, list, place)
	-- a desk against the back wall with a computer, a bookcase beside it
	desk(b, f, x, z, list, "type", "home", -1, place, rgb(120, 86, 60))
	box(b, f, "Bookcase", Vector3.new(4, 7, 1.4), x + 4.8, 0, z + 0.4, rgb(110, 80, 56), Enum.Material.Wood)
	for row = 0, 2 do
		for k = 0, 4 do
			box(b, f, "Book", Vector3.new(0.5, 1.4 - (k % 2) * 0.3, 1), x + 3.4 + k * 0.62, 0.6 + row * 2.2, z + 0.2, MapKit.FLOWERS[(row * 5 + k) % #MapKit.FLOWERS + 1]:Lerp(rgb(60, 50, 40), 0.35))
		end
	end
	box(b, f, "OfficePlant", Vector3.new(1, 1, 1), x - 3.4, 0, z + 0.4, rgb(180, 110, 80), Enum.Material.Slate)
	MapKit.ball(b.Model, "PlantLeaves", 2, at(b, f, x - 3.4, 2, z + 0.4), MapKit.LEAVES[2], Enum.Material.SmoothPlastic)
end

local function piano(b, f, x, z, list, place)
	-- an upright piano against the front wall, a bench in front
	local black = rgb(26, 24, 28)
	box(b, f, "Piano", Vector3.new(5, 4.2, 1.8), x, 0, z, black, Enum.Material.SmoothPlastic)
	box(b, f, "PianoKeys", Vector3.new(4.6, 0.15, 0.8), x, 2.6, z + 1.2, WHITE)
	for k = 0, 8 do
		box(b, f, "BlackKey", Vector3.new(0.18, 0.12, 0.45), x - 2 + k * 0.5, 2.75, z + 1, black)
	end
	box(b, f, "SheetMusic", Vector3.new(1.6, 1.1, 0.05), x, 3.4, z + 0.85, rgb(250, 248, 238))
	local seat = MapKit.seat(b.Model, "PianoBench", Vector3.new(3, 0.4, 1.4), at(b, f, x, 1.7, z + 2.8), black, Enum.Material.SmoothPlastic, place)
	box(b, f, "BenchLegs", Vector3.new(2.6, 1.5, 1), x, 0, z + 2.8, black)
	spot(list, b, f, x, z + 2.8, 0, -1, "piano", "home", seat)
end

local function readingNook(b, f, x, z, list, rng, place)
	local c = ({ rgb(180, 120, 80), rgb(90, 120, 110), rgb(150, 70, 80) })[rng:NextInteger(1, 3)]
	rug(b, f, x, z, 5, 5, rgb(220, 200, 170))
	local seat = MapKit.seat(b.Model, "ArmchairSeat", Vector3.new(2.2, 0.4, 2.2), at(b, f, x, 1.8, z), c, Enum.Material.Fabric, place)
	box(b, f, "Armchair", Vector3.new(2.8, 1.6, 2.8), x, 0, z, c, Enum.Material.Fabric)
	box(b, f, "ArmchairBack", Vector3.new(2.8, 2.4, 0.6), x, 1.6, z + 1.1, c:Lerp(BLACK, 0.1), Enum.Material.Fabric)
	spot(list, b, f, x, z, 0, -1, "read", "home", seat)
	box(b, f, "FloorLamp", Vector3.new(0.3, 5, 0.3), x + 2.2, 0, z + 1, rgb(60, 60, 60), Enum.Material.Metal)
	local shade = box(b, f, "LampShade", Vector3.new(1.3, 1, 1.3), x + 2.2, 5, z + 1, rgb(255, 236, 200), Enum.Material.Fabric)
	MapKit.light(shade, rgb(255, 220, 170), 12, 0.5)
	box(b, f, "SideTable", Vector3.new(1.2, 1.8, 1.2), x - 2.1, 0, z, rgb(130, 90, 60), Enum.Material.Wood)
	box(b, f, "BookStack", Vector3.new(0.8, 0.5, 1), x - 2.1, 1.8, z, rgb(80, 110, 160))
end

local function gameCorner(b, f, x, z, list, place)
	-- a TV with a games console and two beanbags
	box(b, f, "TVStand", Vector3.new(5, 1.6, 1.4), x, 0, z, rgb(50, 50, 56), Enum.Material.Wood)
	local tv = box(b, f, "TV", Vector3.new(4.4, 2.6, 0.2), x, 1.6, z, rgb(20, 20, 24))
	local screen = deco(b.Model, "TVScreen", Vector3.new(4, 2.2, 0.05), tv.CFrame * CFrame.new(0, 0, 0.13), rgb(120, 200, 140), Enum.Material.Neon)
	screen.Transparency = 0.1
	box(b, f, "Console", Vector3.new(1.4, 0.4, 1), x + 1.6, 1.6, z + 0.1, rgb(240, 240, 245))
	for k, c in ipairs({ rgb(220, 70, 70), rgb(70, 130, 220) }) do
		local bx = x + (k == 1 and -1.4 or 1.4)
		local seat = MapKit.seat(b.Model, "Beanbag", Vector3.new(2.4, 1.2, 2.4), at(b, f, bx, 0.6, z + 4), c, Enum.Material.Fabric, place)
		spot(list, b, f, bx, z + 4, 0, -1, "tv", "home", seat)
	end
end

local function laundry(b, f, x, z)
	for k = 0, 1 do
		local m = box(b, f, if k == 0 then "Washer" else "Dryer", Vector3.new(2.4, 3, 2.4), x + k * 2.6, 0, z, rgb(242, 242, 245), Enum.Material.SmoothPlastic)
		deco(b.Model, "Door", Vector3.new(1.5, 1.5, 0.1), m.CFrame * CFrame.new(0, 0, -1.22), rgb(150, 190, 220), Enum.Material.Glass)
	end
	box(b, f, "LaundryBasket", Vector3.new(1.6, 1.2, 1.2), x + 5.2, 0, z, rgb(200, 180, 140), Enum.Material.Fabric)
end

-- the biggest houses: a home gym, a pool table, a kids' playroom
local function homeGym(b, f, x, z, list)
	rug(b, f, x, z, 9, 7, rgb(60, 62, 70))
	box(b, f, "TreadmillBase", Vector3.new(2.6, 0.6, 6), x - 2.5, 0, z, rgb(30, 30, 34), Enum.Material.Metal)
	box(b, f, "TreadmillBelt", Vector3.new(2, 0.1, 5), x - 2.5, 0.6, z, rgb(20, 20, 22), Enum.Material.Rubber)
	box(b, f, "TreadmillRail", Vector3.new(2.6, 3.6, 0.3), x - 2.5, 0.6, z - 2.6, rgb(60, 62, 70), Enum.Material.Metal)
	local s = spot(list, b, f, x - 2.5, z + 0.6, 0, -1, "run", "home")
	s.Raise = 0.7
	box(b, f, "WeightBench", Vector3.new(1.4, 1.6, 4), x + 2.5, 0, z, rgb(40, 40, 44), Enum.Material.Fabric)
	box(b, f, "DumbbellRack", Vector3.new(3, 2.4, 1.2), x + 2.5, 0, z + 3.2, rgb(40, 40, 44), Enum.Material.Metal)
	for k = 0, 2 do
		MapKit.cylinder(b.Model, "Dumbbell", 1.2, 0.6, at(b, f, x + 1.5 + k * 1, 2.7, z + 3.2) * CFrame.Angles(0, math.rad(90), 0), rgb(60, 60, 66), Enum.Material.Metal)
	end
	spot(list, b, f, x + 4.2, z + 1, -1, 0, "lift", "home")
end

local function poolTable(b, f, x, z)
	box(b, f, "PoolTable", Vector3.new(8, 2.8, 4.4), x, 0, z, rgb(100, 60, 36), Enum.Material.Wood)
	box(b, f, "PoolFelt", Vector3.new(7.2, 0.1, 3.6), x, 2.8, z, rgb(30, 120, 70), Enum.Material.Fabric)
	for k = 0, 5 do
		MapKit.ball(b.Model, "PoolBall", 0.35, at(b, f, x - 1 + (k % 3) * 0.4, 3.05, z - 0.4 + (k // 3) * 0.4), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1])
	end
	MapKit.ball(b.Model, "CueBall", 0.35, at(b, f, x + 2.4, 3.05, z), WHITE)
	box(b, f, "Cue", Vector3.new(5, 0.12, 0.12), x + 0.5, 2.95, z + 1.5, rgb(200, 170, 120), Enum.Material.Wood)
	-- hung from the ceiling on two cords
	local lamp = box(b, f, "PoolLamp", Vector3.new(5, 0.5, 1), x, FLOOR_H - 3, z, rgb(40, 90, 60), Enum.Material.Glass)
	for _, dx in ipairs({ -1.8, 1.8 }) do
		box(b, f, "LampCord", Vector3.new(0.08, 2.6, 0.08), x + dx, FLOOR_H - 2.5, z, rgb(30, 30, 30), Enum.Material.Metal)
	end
	MapKit.light(lamp, rgb(255, 230, 190), 14, 0.7)
end

local function playroom(b, f, x, z, list, place)
	rug(b, f, x, z, 8, 7, rgb(250, 210, 120))
	box(b, f, "ToyChest", Vector3.new(3, 1.8, 1.8), x - 2.5, 0, z + 3, rgb(90, 160, 220), Enum.Material.Wood)
	box(b, f, "KidTable", Vector3.new(3, 0.2, 2.4), x + 1.5, 1.6, z, rgb(250, 240, 220), Enum.Material.Wood)
	box(b, f, "KidTableLeg", Vector3.new(2.6, 1.6, 2), x + 1.5, 0, z, rgb(250, 120, 120), Enum.Material.Wood)
	box(b, f, "Easel", Vector3.new(2.4, 4.4, 0.3), x - 2.5, 0, z - 2.4, rgb(170, 130, 90), Enum.Material.Wood)
	box(b, f, "Canvas", Vector3.new(2, 1.8, 0.1), x - 2.5, 2.4, z - 2.25, WHITE)
	spot(list, b, f, x - 2.5, z - 0.6, 0, -1, "paint", "home")
	for k = 0, 3 do
		MapKit.ball(b.Model, "ToyBall", 0.9, at(b, f, x + 3 - k * 0.9, 0.45, z + 2.6), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1])
		box(b, f, "Block", Vector3.new(0.8, 0.8, 0.8), x - 0.5 + k * 0.9, 0, z - 2.6, MapKit.FLOWERS[(k + 2) % #MapKit.FLOWERS + 1])
	end
end

function ROOMS.home(b, f, list, rng, place)
	-- Ground floor: living room at the front left, dining table at the front
	-- right, a kitchen along the back right. Bedrooms at the back left (on one-
	-- storey houses) or upstairs, with a bathroom. The left back corner is
	-- kept clear on two-storey houses for the stairs.
	local W, D = b.W, b.D
	local hw, hd = W / 2, D / 2
	local twoStorey = b.Floors > 1
	local bedColors = { rgb(90, 130, 200), rgb(200, 110, 140), rgb(120, 180, 120), rgb(230, 190, 90), rgb(150, 110, 200) }
	if f == 1 then
		livingRoom(b, f, -hw + 6.5, -hd + 5.5, list, rng, place)
		diningTable(b, f, hw - 7, -hd + 6, list, place)
		kitchen(b, f, hw - math.min(12, W / 2 - 1), hw - 3, hd - 1.8, list)
		fridge(b, f, hw - 1.6, hd - 1.8, -1)
		plant(b, f, -2.5, -hd + 2)
		if W >= 40 then
			-- the big houses: a piano by the front windows, a reading nook
			-- and a home office in the middle of the house
			piano(b, f, 7.5, -hd + 1.3, list, place)
			readingNook(b, f, -5, -1.5, list, rng, place)
			if twoStorey then
				homeOffice(b, f, 1, hd - 2.4, list, place)
			else
				homeOffice(b, f, 3, 3, list, place)
			end
			if W >= 54 then
				-- the biggest houses: a home gym and a pool table
				homeGym(b, f, 15, 2, list)
				poolTable(b, f, -8, 8)
			end
		end
		if not twoStorey then
			-- bathroom on the right, between the dining table and the kitchen
			local z0, z1 = -hd + 9.8, hd - 4.6
			if z1 - z0 >= 4.5 then
				bathroom(b, f, hw - 6, z0, hw - 0.5, z1, { Walls = { "x0", "z0", "z1" }, Door = "x0" })
			end
			-- bedrooms at the back left: a double bed, a kid's bed, a crib
			doubleBed(b, f, -hw + 4.5, hd - 4.4, list, bedColors[rng:NextInteger(1, #bedColors)])
			bed(b, f, -hw + 10.5, hd - 4.2, list, bedColors[rng:NextInteger(1, #bedColors)], "sleep", "home")
			if W >= 28 then
				box(b, f, "Crib", Vector3.new(3, 2.6, 4), -hw + 15, 0, hd - 3.4, rgb(240, 236, 230), Enum.Material.Wood)
				local s = spot(list, b, f, -hw + 15, hd - 4.4, 0, 1, "nap", "home")
				s.BedTop = top(b, f) + 1.8
				s.Crib = true
			end
			wardrobe(b, f, -hw + 1.4, 1, false)
			dresser(b, f, -hw + 1.3, hd - 10.5, false)
		end
		return
	end
	if f == b.Floors then
		-- upstairs: bedrooms along the back (right of the stairs), a bathroom in
		-- the front right corner, a kid's desk, wardrobe and dresser
		doubleBed(b, f, -hw + 9.5, hd - 4.4, list, bedColors[rng:NextInteger(1, #bedColors)])
		local x = -hw + 15.5
		local n = 0
		while x + 2.2 < hw - 1 and n < 2 do
			bed(b, f, x, hd - 4.2, list, bedColors[rng:NextInteger(1, #bedColors)], "sleep", "home")
			x += 5.5
			n += 1
		end
		bathroom(b, f, hw - 7, -hd + 0.5, hw - 0.5, -hd + 7, { Walls = { "x0", "z1" }, Door = "x0" })
		kidsDesk(b, f, -hw + 8, -hd + 3.5, list, place)
		wardrobe(b, f, hw - 1.4, 1.5, false)
		dresser(b, f, -1, -hd + 1.3, true)
		rug(b, f, -1, 1, 8, 5, bedColors[rng:NextInteger(1, #bedColors)]:Lerp(WHITE, 0.4))
		if W >= 40 then
			-- more room upstairs: a game corner, a laundry nook and another wardrobe
			gameCorner(b, f, 7, -hd + 1.2, list, place)
			laundry(b, f, hw - 14, hd - 1.8)
			wardrobe(b, f, hw - 1.4, -4, false)
			plant(b, f, hw - 9, 0)
			if W >= 54 then
				playroom(b, f, 16, 4, list, place)
			end
		end
	end
end

function ROOMS.lobby(b, f, list, rng, place)
	local W, D = b.W, b.D
	rug(b, f, 0, -2, W / 2, D / 2, rgb(90, 80, 70))
	for k = 0, 5 do
		box(b, f, "Mailbox", Vector3.new(1.4, 1.4, 0.6), -W / 2 + 3 + (k % 3) * 1.5, 3 + (k // 3) * 1.5, D / 2 - 1.4 + (if b.CurtainWall then 0.8 else 0), rgb(180, 150, 90), Enum.Material.Metal)
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
	-- (on a spine held up by two steel posts, ribs hanging down, a skull)
	local bone = rgb(236, 226, 200)
	box(b, f, "Spine", Vector3.new(8.4, 0.5, 0.5), 0.25, 6.2, -4, bone)
	for k = 0, 5 do
		local h = 1.6 + math.abs(math.sin(k)) * 0.8
		box(b, f, "Bone", Vector3.new(0.35, h, 2), -3 + k * 1.3, 6.25 - h, -4, bone)
	end
	for _, px in ipairs({ -3.4, 3.8 }) do
		box(b, f, "SkeletonPost", Vector3.new(0.3, 6.2, 0.3), px, 0, -4, rgb(60, 60, 66), Enum.Material.Metal)
	end
	MapKit.ball(b.Model, "Skull", 1.4, at(b, f, 4.9, 6.45, -4), bone)
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
	for _, lx in ipairs({ -2.2, 2.2 }) do
		for _, lz in ipairs({ -3.8, 3.8 }) do
			box(b, f, "TableLeg", Vector3.new(0.3, 2.6, 0.3), lx, 0, -D / 2 + 7 + lz, rgb(40, 40, 44), Enum.Material.Metal)
		end
	end
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
			for _, lx in ipairs({ -2.2, 2.2 }) do
				box(b, f, "DeskLeg", Vector3.new(0.3, 2.9, 2.4), x + lx, 0, z, rgb(150, 150, 156), Enum.Material.Metal)
			end
			box(b, f, "Screen", Vector3.new(2.4, 1.4, 0.15), x, 3.2, z - 0.8, rgb(120, 190, 255), Enum.Material.Neon)
			local seat = MapKit.seat(b.Model, "OfficeChair", Vector3.new(2, 0.4, 2), at(b, f, x, 1.7, z + 2), rgb(40, 40, 46), Enum.Material.Fabric, place)
			box(b, f, "ChairPost", Vector3.new(0.3, 1.5, 0.3), x, 0.2, z + 2, rgb(60, 60, 66), Enum.Material.Metal)
			box(b, f, "ChairBase", Vector3.new(1.8, 0.2, 1.8), x, 0, z + 2, rgb(60, 60, 66), Enum.Material.Metal)
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
			Decor.dress(b, f, kind, rng, place, list)
		end
	end
	return list
end

return Interiors
