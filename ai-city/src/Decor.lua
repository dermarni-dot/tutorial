-- Decor (ModuleScript) — ServerScriptService.Modules.Decor
-- The finishing touches inside every building, after Interiors has put in the
-- big furniture. Every room gets:
--   • baseboards and a chair rail along the walls
--   • framed paintings and a wall clock on the back wall
--   • plants, trash bins and lamps in free corners
--   • ceiling lights that suit the room (pendant lamps in cafes and
--     restaurants, chandeliers in the bank, town hall and hotel)
-- and each kind of room (and each kind of shop) gets its own props: clothes
-- racks and mannequins, toy piles, TVs on the wall, flower buckets, fish
-- tanks, a tool wall, drink fridges, filing cabinets, lockers, IV stands...
--
-- Nothing is ever placed on top of what's already there: every prop checks the
-- floor space first (see `free`).

local MapKit = require(script.Parent:WaitForChild("MapKit"))

local Decor = {}

local rgb = MapKit.rgb
local WHITE, BLACK = MapKit.WHITE, MapKit.BLACK
local deco, part = MapKit.deco, MapKit.part

--------------------------------------------------------------------------------
-- A room: local coordinates on floor f of building b (x left/right, z front(-)
-- to back(+), y up from the floor), and what floor space is already taken
--------------------------------------------------------------------------------
local SKIP = { Rug = true, Floor = true, FloorSlab = true, CellFloor = true, CeilingLight = true, Ceiling = true, DoorMat = true, Tile = true, FloorTiles = true }

local function room(b, f, rng, kind, place, spots)
	local r = { B = b, F = f, W = b.W, D = b.D, Rng = rng, Kind = kind, PlaceId = place, Taken = {} }
	r.Y0 = (b.FloorY and b.FloorY[f] or 0) + 0.4
	r.H = MapKit.FLOOR_H - 1.0 -- floor to the underside of the ceiling
	function r.At(x, y, z, rot)
		return b.At(x, r.Y0 + y, z) * (rot or CFrame.new())
	end
	-- what's already on this floor (seen from above)
	local bx, by, bz = b.CFrame.RightVector, b.CFrame.UpVector, b.CFrame.LookVector
	for _, d in ipairs(b.Model:GetDescendants()) do
		if d:IsA("BasePart") and not SKIP[d.Name] and d.Size.Y > 0.15 then
			local p = b.CFrame:PointToObjectSpace(d.Position)
			local y = p.Y - r.Y0
			if y > -0.5 and y < r.H and math.abs(p.X) < r.W / 2 - 1.1 and math.abs(p.Z) < r.D / 2 - 1.1 then
				-- the part's footprint along the building's axes (parts can be turned)
				local cf, s = d.CFrame, d.Size / 2
				local function extent(axis)
					return math.abs(cf.RightVector:Dot(axis)) * s.X + math.abs(cf.UpVector:Dot(axis)) * s.Y + math.abs(cf.LookVector:Dot(axis)) * s.Z
				end
				local hx, hy, hz = extent(bx), extent(by), extent(bz)
				table.insert(r.Taken, { p.X - hx, p.Z - hz, p.X + hx, p.Z + hz, y - hy, y + hy })
			end
		end
	end
	-- where people stand to work / browse / sit stays clear
	for _, sp in ipairs(spots or {}) do
		if sp.Floor == f then
			local p = b.CFrame:PointToObjectSpace(sp.CFrame.Position)
			table.insert(r.Taken, { p.X - 1.3, p.Z - 1.3, p.X + 1.3, p.Z + 1.3, -1, r.H })
		end
	end
	-- is this box (x, z center, w × d footprint, from y0 up to y1) free?
	function r.Free(x, z, w, d, y0, y1)
		y0, y1 = y0 or 0, y1 or r.H
		local ax0, az0, ax1, az1 = x - w / 2, z - d / 2, x + w / 2, z + d / 2
		if ax0 < -r.W / 2 + 0.9 or ax1 > r.W / 2 - 0.9 or az0 < -r.D / 2 + 0.9 or az1 > r.D / 2 - 0.9 then
			return false
		end
		-- keep the front door clear on the ground floor
		if r.F == 1 and az0 < -r.D / 2 + 5 and math.abs(x) < (b.Spec and b.Spec.DoorW or 8) / 2 + 2.5 then
			return false
		end
		-- and the stairs (left wall) and the elevator (back right)
		if b.Elevator and b.Elevator.Stairs and ax0 < -r.W / 2 + 5.5 and az1 > r.D / 2 - 16 then
			return false
		end
		if b.Elevator and not b.Elevator.Stairs and ax1 > r.W / 2 - 10 and az1 > r.D / 2 - 13 then
			return false
		end
		for _, t in ipairs(r.Taken) do
			if ax0 < t[3] and ax1 > t[1] and az0 < t[4] and az1 > t[2] and y0 < t[6] and y1 > t[5] then
				return false
			end
		end
		return true
	end
	function r.Take(x, z, w, d, y0, y1)
		table.insert(r.Taken, { x - w / 2, z - d / 2, x + w / 2, z + d / 2, y0 or 0, y1 or r.H })
	end
	-- a box sitting at height y (bottom), centered on x, z
	function r.Box(name, size, x, y, z, color, material, rot)
		return deco(b.Model, name, size, r.At(x, y + size.Y / 2, z, rot), color, material)
	end
	function r.Solid(name, size, x, y, z, color, material, rot)
		return part(b.Model, name, size, r.At(x, y + size.Y / 2, z, rot), color, material)
	end
	-- place a prop if its footprint is free; returns true if it was placed
	-- (or, if that's taken, in the nearest free floor space close by)
	function r.Try(x, z, w, d, y0, y1, build)
		if not r.Free(x, z, w, d, y0, y1) then
			return y0 == 0 and r.Place(w, d, y1, x, z, build, 0.6, 12)
		end
		r.Take(x, z, w, d, y0, y1)
		build(x, z)
		return true
	end
	-- place a w × d prop in the free spot nearest (px, pz), keeping `pad` studs
	-- of walking room around it; returns true if there was room anywhere
	function r.Place(w, d, y1, px, pz, build, pad, maxDist)
		pad = pad or 0.8
		local best, bestD = nil, if maxDist then maxDist * maxDist else nil
		for x = -r.W / 2 + w / 2 + 1, r.W / 2 - w / 2 - 1, 1 do
			for z = -r.D / 2 + d / 2 + 1, r.D / 2 - d / 2 - 1, 1 do
				local dist = (x - px) ^ 2 + (z - pz) ^ 2
				if (not bestD or dist < bestD) and r.Free(x, z, w + pad * 2, d + pad * 2, 0, y1) then
					best, bestD = { x, z }, dist
				end
			end
		end
		if not best then
			return false
		end
		r.Take(best[1], best[2], w, d, 0, y1)
		build(best[1], best[2])
		return true
	end
	return r
end

--------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------
local PAINT = { rgb(120, 180, 230), rgb(250, 180, 120), rgb(170, 140, 220), rgb(120, 200, 170), rgb(240, 140, 160), rgb(250, 220, 120) }
local LAND = { rgb(90, 160, 90), rgb(60, 110, 170), rgb(200, 170, 110), rgb(140, 90, 70) }

-- a framed landscape painting on the back wall (facing into the room)
-- (glass towers: the glass is further out than a solid wall)
local function wallZ(r)
	return if r.B and r.B.CurtainWall then r.D / 2 - 0.33 else r.D / 2 - 1.08
end
local function painting(r, x, y, w, h)
	local z = wallZ(r)
	local frame = ({ rgb(60, 45, 35), rgb(200, 170, 90), rgb(30, 30, 34), WHITE })[r.Rng:NextInteger(1, 4)]
	r.Box("PaintingFrame", Vector3.new(w, h, 0.14), x, y, z, frame, Enum.Material.Wood)
	r.Box("Painting", Vector3.new(w - 0.4, h * 0.55 - 0.2, 0.08), x, y + h * 0.45, z - 0.06, PAINT[r.Rng:NextInteger(1, #PAINT)], Enum.Material.SmoothPlastic)
	r.Box("Painting", Vector3.new(w - 0.4, h * 0.45 - 0.2, 0.08), x, y + 0.2, z - 0.06, LAND[r.Rng:NextInteger(1, #LAND)], Enum.Material.SmoothPlastic)
	local sun = r.Box("PaintingSun", Vector3.new(0.05, h * 0.2, h * 0.2), x + w * 0.2, y + h * 0.66, z - 0.1, rgb(255, 230, 140), Enum.Material.SmoothPlastic, CFrame.Angles(0, math.rad(90), 0))
	sun.Shape = Enum.PartType.Cylinder
end

-- a round wall clock (hands at a random time)
local function clock(r, x, y)
	local z = wallZ(r)
	local face = r.Box("ClockFace", Vector3.new(0.18, 1.8, 1.8), x, y, z, WHITE, Enum.Material.SmoothPlastic, CFrame.Angles(0, math.rad(90), 0))
	face.Shape = Enum.PartType.Cylinder
	local rim = r.Box("ClockRim", Vector3.new(0.12, 2.05, 2.05), x, y - 0.125, z + 0.04, rgb(40, 40, 46), Enum.Material.Metal, CFrame.Angles(0, math.rad(90), 0))
	rim.Shape = Enum.PartType.Cylinder
	local hour, minute = r.Rng:NextNumber(0, 360), r.Rng:NextNumber(0, 360)
	r.Box("ClockHand", Vector3.new(0.08, 0.55, 0.04), x, y + 0.9 - 0.02, z - 0.12, BLACK, nil, CFrame.Angles(0, 0, math.rad(hour)) * CFrame.new(0, 0.25, 0))
	r.Box("ClockHand", Vector3.new(0.06, 0.78, 0.04), x, y + 0.9 - 0.02, z - 0.14, BLACK, nil, CFrame.Angles(0, 0, math.rad(minute)) * CFrame.new(0, 0.36, 0))
end

local function plant(r, x, z, big)
	local s = if big then 1.35 else 1
	r.Box("Pot", Vector3.new(1.3, 1.3, 1.3) * s, x, 0, z, ({ rgb(180, 110, 80), rgb(240, 240, 236), rgb(60, 60, 66) })[r.Rng:NextInteger(1, 3)], Enum.Material.Slate)
	MapKit.ball(r.B.Model, "PlantLeaves", 2.4 * s, r.At(x, 2.4 * s, z), MapKit.LEAVES[r.Rng:NextInteger(1, #MapKit.LEAVES)], Enum.Material.SmoothPlastic)
	MapKit.ball(r.B.Model, "PlantLeaves", 1.7 * s, r.At(x + 0.4, 3.4 * s, z - 0.3), MapKit.LEAVES[r.Rng:NextInteger(1, #MapKit.LEAVES)], Enum.Material.SmoothPlastic)
end

local function bin(r, x, z)
	r.Box("TrashBin", Vector3.new(1, 1.4, 1), x, 0, z, rgb(70, 74, 80), Enum.Material.Metal)
	r.Box("TrashBinLid", Vector3.new(1.1, 0.12, 1.1), x, 1.4, z, rgb(50, 52, 58), Enum.Material.Metal)
end

local function floorLamp(r, x, z, light)
	r.Box("LampPole", Vector3.new(0.18, 4.6, 0.18), x, 0, z, rgb(40, 40, 44), Enum.Material.Metal)
	r.Box("LampBase", Vector3.new(0.9, 0.15, 0.9), x, 0, z, rgb(40, 40, 44), Enum.Material.Metal)
	local shade = r.Box("LampShade", Vector3.new(1.4, 1, 1.4), x, 4.4, z, rgb(250, 236, 200), Enum.Material.Fabric)
	if light then
		MapKit.light(shade, rgb(255, 225, 170), 12, 0.6)
	end
end

local function bookshelf(r, x, z, w, alongX)
	local size = if alongX then Vector3.new(w, 6.5, 1.3) else Vector3.new(1.3, 6.5, w)
	r.Box("Bookshelf", size, x, 0, z, rgb(120, 86, 58), Enum.Material.Wood)
	for row = 0, 3 do
		local n = math.floor((w - 0.4) / 0.42)
		for k = 0, n - 1 do
			if r.Rng:NextNumber() < 0.85 then
				local off = -w / 2 + 0.4 + k * 0.42
				local h = r.Rng:NextNumber(0.9, 1.3)
				local c = ({ rgb(170, 50, 50), rgb(50, 90, 160), rgb(60, 130, 80), rgb(220, 180, 70), rgb(120, 70, 140), rgb(230, 230, 220), rgb(60, 60, 66) })[r.Rng:NextInteger(1, 7)]
				local bx, bz = if alongX then x + off else x, if alongX then z else z + off
				r.Box("Book", if alongX then Vector3.new(0.34, h, 1) else Vector3.new(1, h, 0.34), bx, 0.35 + row * 1.55, bz, c, Enum.Material.SmoothPlastic)
			end
		end
	end
end

local function cabinet(r, x, z)
	r.Box("FilingCabinet", Vector3.new(1.8, 4.2, 2), x, 0, z, rgb(150, 156, 166), Enum.Material.Metal)
	for k = 0, 2 do
		r.Box("Drawer", Vector3.new(1.5, 0.08, 0.1), x, 1 + k * 1.3, z - 1.02, rgb(90, 94, 104), Enum.Material.Metal)
	end
end

local function lockers(r, x, z, n)
	for k = 0, n - 1 do
		local lx = x - (n - 1) * 0.9 + k * 1.8
		r.Box("Locker", Vector3.new(1.7, 6, 1.6), lx, 0, z, ({ rgb(60, 90, 150), rgb(70, 100, 160) })[k % 2 + 1], Enum.Material.Metal)
		r.Box("LockerVent", Vector3.new(1, 0.5, 0.05), lx, 4.9, z - 0.82, rgb(40, 60, 100), Enum.Material.Metal)
		r.Box("LockerHandle", Vector3.new(0.12, 0.6, 0.1), lx + 0.55, 3, z - 0.84, rgb(200, 200, 205), Enum.Material.Metal)
	end
end

local function fridgeCase(r, x, z, w)
	-- a glass-door drinks fridge against the back wall, full of bottles
	r.Box("Fridge", Vector3.new(w, 6.4, 2), x, 0, z, rgb(230, 232, 236), Enum.Material.Metal)
	for row = 0, 3 do
		for k = 0, math.floor(w / 0.6) - 2 do
			r.Box("Bottle", Vector3.new(0.35, 0.9, 0.35), x - w / 2 + 0.7 + k * 0.6, 0.6 + row * 1.4, z - 0.4, ({ rgb(220, 60, 60), rgb(60, 180, 90), rgb(250, 190, 40), rgb(70, 140, 230), rgb(240, 120, 40) })[(k + row) % 5 + 1], Enum.Material.Glass)
		end
	end
	local glass = r.Box("FridgeGlass", Vector3.new(w - 0.3, 6, 0.1), x, 0.2, z - 1.05, rgb(200, 230, 245), Enum.Material.Glass)
	glass.Transparency = 0.55
	local glow = r.Box("FridgeLight", Vector3.new(w - 0.5, 0.15, 0.3), x, 6.1, z - 0.7, rgb(220, 240, 255), Enum.Material.Neon)
	glow.Transparency = 0.2
end

local function pendant(r, x, z, color)
	local y = r.H - 0.2
	r.Box("PendantCord", Vector3.new(0.06, 3.0, 0.06), x, y - 2.4, z, rgb(30, 30, 30)) -- (up into the ceiling)
	local shade = r.Box("PendantShade", Vector3.new(1.6, 0.9, 1.6), x, y - 3.2, z, color or rgb(40, 60, 50), Enum.Material.Metal)
	local bulb = r.Box("PendantBulb", Vector3.new(0.6, 0.35, 0.6), x, y - 3.4, z, rgb(255, 230, 170), Enum.Material.Neon)
	return shade, bulb
end

local function chandelier(r, x, z)
	local y = r.H - 0.2
	r.Box("ChandelierChain", Vector3.new(0.12, 2.6, 0.12), x, y - 1.9, z, MapKit.GOLD, Enum.Material.Metal)
	local ring = r.Box("Chandelier", Vector3.new(0.3, 3.6, 3.6), x, y - 3.8, z, MapKit.GOLD, Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(90)))
	ring.Shape = Enum.PartType.Cylinder
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		local c = r.Box("Candle", Vector3.new(0.3, 0.6, 0.3), x + math.cos(a) * 1.5, y - 1.86, z + math.sin(a) * 1.5, rgb(255, 236, 190), Enum.Material.Neon)
		if k == 0 then
			MapKit.light(c, rgb(255, 220, 160), 18, 0.8)
		end
	end
end

local function rack(r, x, z, alongX)
	-- a clothes rail with hanging shirts
	local len = 5
	r.Box("RackPost", Vector3.new(0.2, 5, 0.2), x + (if alongX then -len / 2 else 0), 0, z + (if alongX then 0 else -len / 2), rgb(180, 180, 186), Enum.Material.Metal)
	r.Box("RackPost", Vector3.new(0.2, 5, 0.2), x + (if alongX then len / 2 else 0), 0, z + (if alongX then 0 else len / 2), rgb(180, 180, 186), Enum.Material.Metal)
	r.Box("RackBar", if alongX then Vector3.new(len, 0.15, 0.15) else Vector3.new(0.15, 0.15, len), x, 4.9, z, rgb(180, 180, 186), Enum.Material.Metal)
	for k = 0, 7 do
		local off = -len / 2 + 0.5 + k * 0.57
		local c = MapKit.FLOWERS[r.Rng:NextInteger(1, #MapKit.FLOWERS)]
		r.Box("Shirt", if alongX then Vector3.new(0.22, 2.4, 1.6) else Vector3.new(1.6, 2.4, 0.22), x + (if alongX then off else 0), 2.4, z + (if alongX then 0 else off), c, Enum.Material.Fabric)
	end
end

local function mannequin(r, x, z)
	local c = MapKit.FLOWERS[r.Rng:NextInteger(1, #MapKit.FLOWERS)]
	r.Box("MannequinStand", Vector3.new(1.2, 0.2, 1.2), x, 0, z, rgb(60, 60, 66), Enum.Material.Metal)
	r.Box("MannequinLegs", Vector3.new(1.2, 2.6, 0.7), x, 0.2, z, rgb(50, 60, 90), Enum.Material.Fabric)
	r.Box("MannequinBody", Vector3.new(1.8, 2.2, 0.9), x, 2.8, z, c, Enum.Material.Fabric)
	MapKit.ball(r.B.Model, "MannequinHead", 1, r.At(x, 5.6, z), rgb(240, 236, 228), Enum.Material.SmoothPlastic)
end

local function tvWall(r, x, y, w)
	local z = r.D / 2 - 1.1
	local tv = r.Box("TVFrame", Vector3.new(w, w * 0.58, 0.2), x, y, z, rgb(20, 20, 24))
	local screen = r.Box("TVScreen", Vector3.new(w - 0.3, w * 0.58 - 0.3, 0.05), x, y + 0.15, z - 0.12, ({ rgb(90, 160, 255), rgb(120, 220, 160), rgb(255, 150, 90) })[r.Rng:NextInteger(1, 3)], Enum.Material.Neon)
	screen.Transparency = 0.1
	return tv
end

local function bucket(r, x, z)
	r.Box("FlowerBucket", Vector3.new(1.2, 1.2, 1.2), x, 0, z, rgb(90, 110, 130), Enum.Material.Metal)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		MapKit.ball(r.B.Model, "Flower", 0.6, r.At(x + math.cos(a) * 0.35, 1.9 + (k % 2) * 0.3, z + math.sin(a) * 0.35), MapKit.FLOWERS[r.Rng:NextInteger(1, #MapKit.FLOWERS)], Enum.Material.SmoothPlastic)
	end
	r.Box("Stems", Vector3.new(0.8, 0.8, 0.8), x, 1.2, z, rgb(70, 140, 60), Enum.Material.SmoothPlastic)
end

local function aquarium(r, x, z)
	r.Box("TankStand", Vector3.new(5, 2.6, 2), x, 0, z, rgb(60, 50, 44), Enum.Material.Wood)
	local water = r.Box("Aquarium", Vector3.new(4.8, 2.6, 1.8), x, 2.6, z, rgb(80, 170, 230), Enum.Material.Glass)
	water.Transparency = 0.45
	for k = 0, 3 do
		r.Box("Fish", Vector3.new(0.5, 0.3, 0.15), x - 1.6 + k * 1.1, 3.2 + (k % 2) * 0.8, z - 0.2, ({ rgb(255, 140, 40), rgb(255, 220, 60), rgb(240, 80, 120), rgb(100, 220, 255) })[k + 1], Enum.Material.Neon)
	end
	r.Box("Gravel", Vector3.new(4.7, 0.3, 1.7), x, 2.6, z, rgb(220, 200, 160), Enum.Material.Pebble)
	MapKit.light(water, rgb(120, 200, 255), 8, 0.4)
end

local function toyPile(r, x, z)
	for k = 0, 5 do
		local c = MapKit.FLOWERS[r.Rng:NextInteger(1, #MapKit.FLOWERS)]
		if k % 3 == 0 then
			MapKit.ball(r.B.Model, "ToyBall", 1, r.At(x - 0.8 + (k % 2) * 1.5, 0.5 + (k // 3) * 0.9, z + (k % 3) * 0.3), c, Enum.Material.SmoothPlastic)
		else
			r.Box("ToyBlock", Vector3.new(0.8, 0.8, 0.8), x - 1 + (k % 3) * 0.9, (k // 3) * 0.8, z - 0.4 + (k % 2) * 0.8, c, Enum.Material.SmoothPlastic)
		end
	end
	-- a teddy bear
	MapKit.ball(r.B.Model, "Teddy", 1.3, r.At(x + 1.4, 0.65, z - 0.8), rgb(170, 120, 70), Enum.Material.Fabric)
	MapKit.ball(r.B.Model, "Teddy", 0.9, r.At(x + 1.4, 1.6, z - 0.8), rgb(170, 120, 70), Enum.Material.Fabric)
end

local function pegboard(r, x, w)
	local z = r.D / 2 - 1.1
	r.Box("Pegboard", Vector3.new(w, 4, 0.15), x, 3.2, z, rgb(200, 170, 120), Enum.Material.Wood)
	for k = 0, math.floor(w / 1.2) - 1 do
		local tx = x - w / 2 + 0.8 + k * 1.2
		local kind = k % 3
		if kind == 0 then
			r.Box("ToolHandle", Vector3.new(0.2, 1.3, 0.15), tx, 4.2, z - 0.15, rgb(200, 60, 50))
			r.Box("ToolHead", Vector3.new(0.7, 0.3, 0.2), tx, 5.4, z - 0.15, rgb(120, 124, 132), Enum.Material.Metal)
		elseif kind == 1 then
			r.Box("Wrench", Vector3.new(0.18, 1.4, 0.1), tx, 4.1, z - 0.15, rgb(170, 175, 180), Enum.Material.Metal)
		else
			r.Box("Saw", Vector3.new(0.9, 0.5, 0.05), tx, 4.6, z - 0.15, rgb(190, 195, 200), Enum.Material.Metal)
		end
	end
end

local function stanchions(r, x, z, n)
	for k = 0, n - 1 do
		local sx = x - (n - 1) * 1.6 + k * 3.2
		r.Box("Stanchion", Vector3.new(0.25, 3, 0.25), sx, 0, z, MapKit.GOLD, Enum.Material.Metal)
		r.Box("StanchionBase", Vector3.new(0.8, 0.12, 0.8), sx, 0, z, MapKit.GOLD, Enum.Material.Metal)
		if k < n - 1 then
			r.Box("Rope", Vector3.new(3, 0.18, 0.18), sx + 1.6, 2.5, z, rgb(170, 30, 50), Enum.Material.Fabric)
		end
	end
end

local function ivStand(r, x, z)
	r.Box("IVPole", Vector3.new(0.12, 5.5, 0.12), x, 0, z, rgb(200, 204, 210), Enum.Material.Metal)
	r.Box("IVBase", Vector3.new(1.2, 0.12, 1.2), x, 0, z, rgb(200, 204, 210), Enum.Material.Metal)
	local bag = r.Box("IVBag", Vector3.new(0.6, 0.9, 0.2), x, 4.8, z, rgb(200, 230, 255), Enum.Material.Glass)
	bag.Transparency = 0.3
end

local function wheelchair(r, x, z)
	r.Box("WheelchairSeat", Vector3.new(1.8, 0.3, 1.8), x, 1.5, z, rgb(40, 60, 110), Enum.Material.Fabric)
	r.Box("WheelchairBack", Vector3.new(1.8, 1.8, 0.2), x, 1.8, z + 0.9, rgb(40, 60, 110), Enum.Material.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		local w = r.Box("Wheel", Vector3.new(0.15, 2.2, 2.2), x + s * 1, 0, z + 0.2, rgb(60, 62, 70), Enum.Material.Metal)
		w.Shape = Enum.PartType.Cylinder
	end
end

local function globe(r, x, z)
	r.Box("GlobeStand", Vector3.new(0.3, 3.4, 0.3), x, 0, z, rgb(120, 86, 58), Enum.Material.Wood)
	MapKit.ball(r.B.Model, "Globe", 1.6, r.At(x, 4.1, z), rgb(70, 140, 220), Enum.Material.SmoothPlastic)
	MapKit.ball(r.B.Model, "GlobeLand", 0.9, r.At(x + 0.35, 4.3, z - 0.3), rgb(90, 170, 90), Enum.Material.SmoothPlastic)
end

local function barrel(r, x, z, color)
	local b = r.Box("Barrel", Vector3.new(2.6, 1.8, 1.8), x, 0, z, color or rgb(40, 90, 160), Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(90)))
	b.Shape = Enum.PartType.Cylinder
end

local function pallet(r, x, z)
	r.Box("Pallet", Vector3.new(3.6, 0.5, 3.6), x, 0, z, rgb(170, 130, 80), Enum.Material.WoodPlanks)
	for k = 0, 3 do
		r.Box("Crate", Vector3.new(1.6, 1.4, 1.6), x - 0.85 + (k % 2) * 1.7, 0.5 + (k // 2) * 1.4, z - 0.85 + (k % 2) * 1.7 * 0 + (k // 2) * 0, rgb(190, 150, 100), Enum.Material.WoodPlanks)
	end
end

local function sofa(r, x, z, color, w)
	w = w or 6
	r.Box("Sofa", Vector3.new(w, 1.5, 2.4), x, 0, z, color, Enum.Material.Fabric)
	r.Box("SofaBack", Vector3.new(w, 1.8, 0.7), x, 1.5, z + 0.85, color:Lerp(BLACK, 0.1), Enum.Material.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		r.Box("SofaArm", Vector3.new(0.6, 2.2, 2.4), x + s * (w / 2 - 0.3), 0, z, color:Lerp(BLACK, 0.1), Enum.Material.Fabric)
	end
	r.Box("Cushion", Vector3.new(1.2, 1, 0.4), x - w / 4, 1.6, z + 0.35, color:Lerp(WHITE, 0.4), Enum.Material.Fabric)
end

local function vending(r, x, z)
	r.Box("VendingMachine", Vector3.new(3, 6.6, 2.2), x, 0, z, rgb(200, 40, 50), Enum.Material.Metal)
	local front = r.Box("VendingFront", Vector3.new(1.9, 4.6, 0.1), x - 0.4, 1.4, z - 1.12, rgb(220, 240, 255), Enum.Material.Neon)
	front.Transparency = 0.25
	r.Box("VendingSlot", Vector3.new(1.4, 0.5, 0.15), x - 0.4, 0.5, z - 1.12, rgb(30, 30, 34))
end

local function waterCooler(r, x, z)
	r.Box("CoolerBase", Vector3.new(1.3, 3.2, 1.3), x, 0, z, rgb(230, 232, 236), Enum.Material.SmoothPlastic)
	local jug = r.Box("CoolerJug", Vector3.new(1, 1.4, 1), x, 3.2, z, rgb(140, 200, 250), Enum.Material.Glass)
	jug.Transparency = 0.35
	r.Box("CoolerTap", Vector3.new(0.3, 0.3, 0.2), x, 2.2, z - 0.7, rgb(60, 120, 220))
end

-- a cork board with pinned notes (and "wanted" posters at the police station)
local function corkBoard(r, x, wanted)
	local z = r.D / 2 - 1.1
	r.Box("CorkBoard", Vector3.new(5, 3, 0.15), x, 4.2, z, rgb(190, 150, 100), Enum.Material.Fabric)
	for k = 0, 3 do
		local c = if wanted then rgb(245, 235, 200) else ({ rgb(255, 250, 150), rgb(170, 220, 255), rgb(255, 190, 200), WHITE })[k + 1]
		r.Box("Note", Vector3.new(0.9, 1.2, 0.05), x - 1.7 + k * 1.15, 4.5 + (k % 2) * 0.6, z - 0.1, c)
		if wanted then
			MapKit.ball(r.B.Model, "WantedFace", 0.5, r.At(x - 1.7 + k * 1.15, 5.3 + (k % 2) * 0.6, z - 0.14), rgb(90, 70, 60), Enum.Material.SmoothPlastic)
		end
	end
end

local function board(r, x, y, w, h, text, color, textColor)
	local z = r.D / 2 - 1.1
	local p = r.Box("Board", Vector3.new(w, h, 0.15), x, y, z, color or rgb(30, 34, 30), Enum.Material.SmoothPlastic)
	if text then
		-- the board faces into the room (building -Z), which is this part's Front
		MapKit.signText(p, Enum.NormalId.Front, text, textColor or WHITE, Enum.Font.GothamBold, 40)
	end
	return p
end

--------------------------------------------------------------------------------
-- Every room: trim, art, a clock, plants, lights
--------------------------------------------------------------------------------
local THEMES = {
	office = { Trim = rgb(90, 94, 104), Art = true, Clock = true, Plants = 2 },
	officeLight = { Trim = rgb(90, 94, 104), Art = true, Clock = true, Plants = 2 },
	store = { Trim = rgb(120, 120, 126), Art = false, Clock = true, Plants = 1 },
	cafe = { Trim = rgb(90, 60, 40), Art = true, Clock = true, Plants = 2, Pendants = rgb(40, 90, 70) },
	bakery = { Trim = rgb(150, 90, 50), Art = true, Clock = true, Plants = 1, Pendants = rgb(200, 90, 70), Checker = { rgb(240, 236, 226), rgb(200, 90, 80) } },
	restaurant = { Trim = rgb(90, 40, 36), Art = true, Clock = false, Plants = 2, Pendants = rgb(150, 50, 45) },
	bank = { Trim = rgb(180, 160, 110), Art = true, Clock = true, Plants = 2, Chandelier = true },
	police = { Trim = rgb(40, 50, 90), Art = false, Clock = true, Plants = 1 },
	hospital = { Trim = rgb(90, 170, 170), Art = true, Clock = true, Plants = 1, Checker = { rgb(236, 240, 240), rgb(200, 226, 226) } },
	classroom = { Trim = rgb(150, 110, 70), Art = true, Clock = true, Plants = 1 },
	library = { Trim = rgb(110, 76, 50), Art = true, Clock = true, Plants = 2 },
	cinema = { Trim = rgb(90, 30, 40), Art = false, Clock = false, Plants = 0 },
	factory = { Trim = rgb(230, 190, 50), Art = false, Clock = true, Plants = 0 },
	warehouse = { Trim = rgb(230, 190, 50), Art = false, Clock = true, Plants = 0 },
	garage = { Trim = rgb(230, 190, 50), Art = false, Clock = true, Plants = 0 },
	townhall = { Trim = rgb(180, 160, 110), Art = true, Clock = true, Plants = 2, Chandelier = true },
	hotel = { Trim = rgb(160, 130, 80), Art = true, Clock = true, Plants = 2, Chandelier = true },
	home = { Trim = WHITE, Art = true, Clock = true, Plants = 1 },
	lobby = { Trim = rgb(150, 140, 120), Art = true, Clock = false, Plants = 2 },
	apartment = { Trim = WHITE, Art = true, Clock = true, Plants = 1 },
	daycare = { Trim = rgb(250, 190, 90), Art = true, Clock = true, Plants = 1, Checker = { rgb(250, 230, 150), rgb(150, 200, 250) } },
	museum = { Trim = rgb(200, 190, 170), Art = true, Clock = false, Plants = 2 },
	postoffice = { Trim = rgb(40, 70, 150), Art = false, Clock = true, Plants = 1 },
	arcade = { Trim = rgb(150, 60, 220), Art = false, Clock = false, Plants = 0, Checker = { rgb(30, 30, 40), rgb(60, 40, 90) } },
	community = { Trim = rgb(120, 150, 90), Art = true, Clock = true, Plants = 2 },
	gym = { Trim = rgb(60, 62, 70), Art = false, Clock = true, Plants = 1 },
}

local function trim(r, theme)
	local W, D = r.W, r.D
	local c = theme.Trim or WHITE
	-- baseboards on the back and side walls, and the front wall around the door
	r.Box("Baseboard", Vector3.new(W - 2.2, 0.5, 0.2), 0, 0, D / 2 - 1.1, c)
	for _, s in ipairs({ -1, 1 }) do
		r.Box("Baseboard", Vector3.new(0.2, 0.5, D - 2.2), s * (W / 2 - 1.1), 0, 0, c)
	end
	-- a chair rail (a thin strip at hip height) along the back wall
	r.Box("ChairRail", Vector3.new(W - 2.2, 0.2, 0.18), 0, 3, D / 2 - 1.08, c)
end

local function checker(r, colors)
	local W, D = r.W, r.D
	local size = 4
	local nx, nz = math.floor((W - 2) / size), math.floor((D - 2) / size)
	r.Box("FloorTiles", Vector3.new(nx * size, 0.03, nz * size), 0, 0, 0, colors[1], Enum.Material.SmoothPlastic)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			if (i + j) % 2 == 1 then
				r.Box("Tile", Vector3.new(size, 0.035, size), -nx * size / 2 + size / 2 + i * size, 0, -nz * size / 2 + size / 2 + j * size, colors[2], Enum.Material.SmoothPlastic)
			end
		end
	end
end

local function dressRoom(r, theme)
	local W, D = r.W, r.D
	trim(r, theme)
	if theme.Checker then
		checker(r, theme.Checker)
	end
	-- paintings on the back wall, high up (above shelves and boards)
	if theme.Art then
		for _, x in ipairs({ -W / 4, W / 4 }) do
			if r.Free(x, D / 2 - 1.6, 3.4, 1, 7, 10) then
				painting(r, x, 7.3, 3.2, 2.2)
			end
		end
	end
	if theme.Clock and r.Free(0, D / 2 - 1.6, 2.2, 1, 8.4, 10.6) then
		clock(r, 0, 8.6)
	end
	-- plants and a bin in free front corners (by the windows)
	local placed = 0
	for _, c in ipairs({ { -W / 2 + 2.2, -D / 2 + 2.2 }, { W / 2 - 2.2, -D / 2 + 2.2 }, { -W / 2 + 2.2, D / 2 - 2.2 }, { W / 2 - 2.2, D / 2 - 2.2 } }) do
		if placed < (theme.Plants or 1) then
			if r.Try(c[1], c[2], 2.2, 2.2, 0, 5, function(x, z)
				plant(r, x, z, W > 30)
			end) then
				placed += 1
			end
		end
	end
	r.Try(-W / 2 + 2, 0, 1.2, 1.2, 0, 2, function(x, z)
		bin(r, x, z)
	end)
	-- the room's lights
	if theme.Chandelier then
		chandelier(r, 0, 0)
	elseif theme.Pendants then
		local n = math.max(2, math.floor((W - 8) / 8))
		for k = 0, n - 1 do
			local x = -((n - 1) * 8) / 2 + k * 8
			if r.Free(x, -3, 1.6, 1.6, r.H - 4, r.H) then
				local shade, bulb = pendant(r, x, -3, theme.Pendants)
				if k == 0 then
					MapKit.light(bulb, rgb(255, 220, 160), 16, 0.7)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Room-specific props
--------------------------------------------------------------------------------
local EXTRAS = {}

-- shops: each kind of store looks different inside
local SHOPS = {}
SHOPS.Mall = function(r) -- clothing
	for k = 0, 2 do
		r.Try(-r.W / 2 + 5 + k * 7, -r.D / 2 + 9, 5.4, 1.6, 0, 6, function(x, z)
			rack(r, x, z, true)
		end)
	end
	for k = 0, 1 do
		r.Try(-4 + k * 8, -r.D / 2 + 5, 1.6, 1.6, 0, 6, function(x, z)
			mannequin(r, x, z)
		end)
	end
	-- a fitting room with a curtain and a mirror
	r.Try(-r.W / 2 + 3.5, r.D / 2 - 6, 4.4, 4.4, 0, 8, function(x, z)
		r.Solid("FittingWall", Vector3.new(0.3, 7, 4.4), x + 2.2, 0, z, rgb(230, 225, 215), Enum.Material.SmoothPlastic)
		r.Box("Curtain", Vector3.new(4.2, 6.8, 0.15), x, 0.2, z - 2.2, rgb(150, 60, 90), Enum.Material.Fabric)
		local m = r.Box("Mirror", Vector3.new(0.1, 5, 2.6), x - 2, 1, z, rgb(210, 230, 240), Enum.Material.Glass)
		m.Reflectance = 0.5
	end)
end
SHOPS.ToyStore = function(r)
	for k = 0, 2 do
		r.Try(-r.W / 2 + 5 + k * 6, -r.D / 2 + 6, 3.8, 2.6, 0, 3, function(x, z)
			toyPile(r, x, z)
		end)
	end
	r.Try(r.W / 4, -r.D / 2 + 9, 2, 2, 0, 5, function(x, z)
		-- a giant teddy on display
		MapKit.ball(r.B.Model, "BigTeddy", 3, r.At(x, 1.5, z), rgb(180, 120, 70), Enum.Material.Fabric)
		MapKit.ball(r.B.Model, "BigTeddy", 2.1, r.At(x, 3.8, z), rgb(180, 120, 70), Enum.Material.Fabric)
		MapKit.ball(r.B.Model, "BigTeddyEar", 0.8, r.At(x - 0.8, 4.8, z), rgb(160, 100, 60), Enum.Material.Fabric)
		MapKit.ball(r.B.Model, "BigTeddyEar", 0.8, r.At(x + 0.8, 4.8, z), rgb(160, 100, 60), Enum.Material.Fabric)
	end)
end
SHOPS.Electronics = function(r)
	for k, x in ipairs({ -r.W / 4, 0, r.W / 4 }) do
		if r.Free(x, r.D / 2 - 1.6, 5, 1, 7.5, 10.5) then
			tvWall(r, x, 7.6, 4.6)
		end
	end
	for k = 0, 2 do
		r.Try(-6 + k * 6, -r.D / 2 + 8, 4, 2, 0, 4, function(x, z)
			r.Box("DisplayTable", Vector3.new(4, 3, 2), x, 0, z, WHITE, Enum.Material.SmoothPlastic)
			for p = 0, 2 do
				local ph = r.Box("PhoneDisplay", Vector3.new(0.6, 1, 0.1), x - 1.2 + p * 1.2, 3, z, rgb(20, 20, 24), nil, CFrame.Angles(math.rad(-20), 0, 0))
				r.Box("PhoneScreen", Vector3.new(0.5, 0.85, 0.05), x - 1.2 + p * 1.2, 3.07, z - 0.06, ({ rgb(90, 160, 255), rgb(255, 120, 160), rgb(120, 220, 140) })[p + 1], Enum.Material.Neon, CFrame.Angles(math.rad(-20), 0, 0))
				local _ = ph
			end
		end)
	end
end
SHOPS.Florist = function(r)
	for k = 0, 5 do
		r.Try(-r.W / 2 + 3 + k * 2, -r.D / 2 + 3.5, 1.4, 1.4, 0, 3, function(x, z)
			bucket(r, x, z)
		end)
	end
	for k = 0, 3 do
		r.Try(-r.W / 2 + 4 + k * 2.2, 3, 1.4, 1.4, 0, 3, function(x, z)
			bucket(r, x, z)
		end)
	end
end
SHOPS.PetShop = function(r)
	r.Try(-r.W / 2 + 5, -r.D / 2 + 5, 5.2, 2.2, 0, 6, function(x, z)
		aquarium(r, x, z)
	end)
	r.Try(-r.W / 2 + 11, -r.D / 2 + 5, 5.2, 2.2, 0, 6, function(x, z)
		aquarium(r, x, z)
	end)
	for k = 0, 1 do
		r.Try(r.W / 4 - 3 + k * 4, -r.D / 2 + 9, 3, 2.6, 0, 3.4, function(x, z)
			-- a pet cage
			r.Box("CageBase", Vector3.new(3, 0.4, 2.4), x, 0, z, rgb(60, 60, 66), Enum.Material.Metal)
			for s = -1, 1, 2 do
				for t = 0, 4 do
					r.Box("CageBar", Vector3.new(0.08, 2.4, 0.08), x - 1.4 + t * 0.7, 0.4, z + s * 1.15, rgb(200, 200, 205), Enum.Material.Metal)
				end
			end
			r.Box("CageTop", Vector3.new(3, 0.1, 2.4), x, 2.8, z, rgb(200, 200, 205), Enum.Material.Metal)
			MapKit.ball(r.B.Model, "Hamster", 0.7, r.At(x, 0.75, z), rgb(220, 170, 110), Enum.Material.Fabric)
		end)
	end
end
SHOPS.Bookstore = function(r)
	for k = 0, 2 do
		r.Try(-r.W / 2 + 6 + k * 8, -r.D / 2 + 8, 6, 1.4, 0, 7, function(x, z)
			bookshelf(r, x, z, 6, true)
		end)
	end
	r.Try(r.W / 2 - 6, -r.D / 2 + 5, 3, 3, 0, 5, function(x, z)
		sofa(r, x, z, rgb(150, 90, 60), 4)
	end)
end
SHOPS.IceCream = function(r)
	r.Try(0, 0, 10, 2.4, 0, 4, function(x, z)
		-- the freezer with tubs of every flavor under glass
		r.Box("Freezer", Vector3.new(10, 3, 2.4), x, 0, z, rgb(240, 240, 245), Enum.Material.Metal)
		for k = 0, 7 do
			r.Box("IceCreamTub", Vector3.new(1, 0.4, 1.6), x - 4.4 + k * 1.25, 3, z, ({ rgb(250, 240, 220), rgb(120, 70, 40), rgb(250, 170, 200), rgb(170, 230, 170), rgb(250, 230, 120), rgb(200, 160, 230) })[k % 6 + 1], Enum.Material.SmoothPlastic)
		end
		local glass = r.Box("FreezerGlass", Vector3.new(10, 1.4, 0.1), x, 3, z - 1.2, rgb(210, 235, 250), Enum.Material.Glass)
		glass.Transparency = 0.5
	end)
	for k = 0, 3 do
		r.Try(-r.W / 2 + 5 + k * 5, -r.D / 2 + 7, 1.4, 1.4, 0, 3, function(x, z)
			local seat = r.Box("Stool", Vector3.new(1.3, 0.3, 1.3), x, 2.4, z, rgb(250, 130, 180), Enum.Material.SmoothPlastic)
			seat.Shape = Enum.PartType.Cylinder
			r.Box("StoolLeg", Vector3.new(0.25, 2.4, 0.25), x, 0, z, rgb(200, 200, 205), Enum.Material.Metal)
		end)
	end
end
SHOPS.Hardware = function(r)
	pegboard(r, -r.W / 4, math.min(10, r.W / 2 - 2))
	for k = 0, 1 do
		r.Try(-r.W / 2 + 5 + k * 5, -r.D / 2 + 6, 3, 3, 0, 4, function(x, z)
			pallet(r, x, z)
		end)
	end
	r.Try(r.W / 4, -r.D / 2 + 8, 4, 4, 0, 5, function(x, z)
		-- paint cans
		for k = 0, 5 do
			-- (a cylinder stood on end: 1 stud tall once it's turned)
			local can = r.Box("PaintCan", Vector3.new(1, 1.2, 1), x - 1.2 + (k % 3) * 1.2, (k // 3) * 1.0 - 0.1, z, MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.Metal)
			can.Shape = Enum.PartType.Cylinder
			can.CFrame = can.CFrame * CFrame.Angles(0, 0, math.rad(90))
		end
	end)
end
SHOPS.Pharmacy = function(r)
	r.Try(r.W / 4, r.D / 2 - 4, 8, 2.4, 0, 4, function(x, z)
		r.Box("PharmacyCounter", Vector3.new(8, 3.4, 2), x, 0, z, WHITE, Enum.Material.SmoothPlastic)
		r.Box("PharmacySign", Vector3.new(4, 1, 0.2), x, 7.6, z + 1.6, rgb(60, 170, 110), Enum.Material.Neon)
		for _, sx in ipairs({ -1.6, 1.6 }) do
			r.Box("SignCord", Vector3.new(0.06, r.H - 8.6 + 0.6, 0.06), x + sx, 8.6, z + 1.6, rgb(40, 40, 44))
		end
	end)
	for k = 0, 2 do
		r.Try(-r.W / 2 + 4 + k * 2.6, -r.D / 2 + 3, 1.6, 1.6, 0, 3, function(x, z)
			r.Box("Basket", Vector3.new(1.6, 1, 1.4), x, 0, z, rgb(60, 170, 110), Enum.Material.Plastic)
		end)
	end
end
SHOPS.Shop = function(r) -- the market
	fridgeCase(r, -r.W / 4, r.D / 2 - 2.2, 7)
	for k = 0, 2 do
		r.Try(-r.W / 2 + 5 + k * 4.2, -r.D / 2 + 7, 3.6, 2.6, 0, 3, function(x, z)
			-- a produce crate: apples, oranges, limes
			r.Box("ProduceCrate", Vector3.new(3.4, 1.8, 2.4), x, 0, z, rgb(170, 130, 80), Enum.Material.WoodPlanks)
			local c = ({ rgb(220, 50, 60), rgb(250, 150, 40), rgb(120, 200, 60) })[k + 1]
			for p = 0, 5 do
				MapKit.ball(r.B.Model, "Produce", 0.7, r.At(x - 1.1 + (p % 3) * 1.1, 2.1, z - 0.5 + (p // 3) * 1), c, Enum.Material.SmoothPlastic)
			end
		end)
	end
	for k = 0, 2 do
		r.Try(r.W / 2 - 3, -r.D / 2 + 3 + k * 0.1, 1.6, 1.6, 0, 3, function(x, z)
			r.Box("Basket", Vector3.new(1.6, 1 + k * 0.3, 1.4), x, 0, z, rgb(220, 60, 60), Enum.Material.Plastic)
		end)
	end
end

EXTRAS.store = function(r)
	local fn = SHOPS[r.PlaceId]
	if fn then
		fn(r)
	end
	-- a doormat-side basket stack and a gum rack by the till, in every shop
	r.Try(r.W / 2 - 3, -r.D / 2 + 3, 1.6, 1.6, 0, 3, function(x, z)
		for k = 0, 2 do
			r.Box("Basket", Vector3.new(1.6, 0.9, 1.4), x, k * 0.9, z, rgb(220, 60, 60), Enum.Material.Plastic)
		end
	end)
end

EXTRAS.office = function(r)
	for k = 0, 2 do
		r.Try(-r.W / 2 + 2.2 + k * 2, r.D / 2 - 2.2, 1.8, 2, 0, 4.4, function(x, z)
			cabinet(r, x, z)
		end)
	end
	r.Try(r.W / 2 - 3, 0, 2.6, 2, 0, 4, function(x, z)
		r.Box("PrinterTable", Vector3.new(2.6, 2.6, 2), x, 0, z, rgb(200, 200, 205))
		r.Box("Printer", Vector3.new(2, 1.2, 1.6), x, 2.6, z, rgb(230, 230, 235), Enum.Material.SmoothPlastic)
		r.Box("PrinterPaper", Vector3.new(1.2, 0.1, 1), x, 3.8, z, WHITE)
	end)
	r.Try(r.W / 2 - 3, -r.D / 2 + 6, 3.2, 2.4, 0, 7, function(x, z)
		vending(r, x, z)
	end)
	r.Try(r.W / 2 - 3, -r.D / 2 + 9.5, 1.4, 1.4, 0, 5, function(x, z)
		waterCooler(r, x, z)
	end)
	if r.Free(-r.W / 4 + 3, r.D / 2 - 1.6, 5.4, 1, 2.6, 5.8) then
		corkBoard(r, -r.W / 4 + 3, false)
	end
end
EXTRAS.officeLight = EXTRAS.office

EXTRAS.cafe = function(r)
	r.Try(-r.W / 2 + 4, r.D / 2 - 4, 6.2, 3, 0, 4, function(x, z)
		sofa(r, x, z, rgb(150, 90, 60), 5)
	end)
	floorLamp(r, -r.W / 2 + 1.8, r.D / 2 - 6.5)
	-- the menu on the board, and an OPEN sign by the door
	local menu = r.B.Model:FindFirstChild("MenuBoard")
	if menu then
		MapKit.signText(menu, Enum.NormalId.Back, "COFFEE 5  ·  LATTE 6\nMUFFIN 4  ·  CROISSANT 4", rgb(255, 240, 200), Enum.Font.GothamBold, 40)
		MapKit.signText(menu, Enum.NormalId.Front, "COFFEE 5  ·  LATTE 6\nMUFFIN 4  ·  CROISSANT 4", rgb(255, 240, 200), Enum.Font.GothamBold, 40)
	end
end

EXTRAS.bakery = function(r)
	if r.F == 1 then
		r.Try(-r.W / 4, -r.D / 2 + 7, 7, 2.4, 0, 4, function(x, z)
			r.Box("DisplayCase", Vector3.new(7, 3, 2.2), x, 0, z, rgb(230, 220, 200), Enum.Material.Wood)
			for k = 0, 4 do
				local cake = r.Box("Cake", Vector3.new(1, 0.7, 1), x - 2.6 + k * 1.3, 3, z, ({ rgb(250, 230, 240), rgb(120, 70, 40), rgb(250, 240, 200) })[k % 3 + 1], Enum.Material.SmoothPlastic)
				cake.Shape = Enum.PartType.Cylinder
				cake.CFrame = cake.CFrame * CFrame.Angles(0, 0, math.rad(90))
				r.Box("Cherry", Vector3.new(0.3, 0.3, 0.3), x - 2.6 + k * 1.3, 3.55, z, rgb(220, 30, 50), Enum.Material.SmoothPlastic)
			end
			local glass = r.Box("CaseGlass", Vector3.new(7, 1.6, 2.2), x, 3, z, rgb(220, 240, 250), Enum.Material.Glass)
			glass.Transparency = 0.6
		end)
		board(r, r.W / 4, 5.6, 7, 2.6, "BREAD 3  ·  CROISSANT 4\nDONUT 3  ·  MUFFIN 4", rgb(40, 30, 26), rgb(255, 230, 190))
	end
end

EXTRAS.restaurant = function(r)
	-- candles on the tables, a wine rack and a reception stand
	for _, d in ipairs(r.B.Model:GetChildren()) do
		if d.Name == "TableTop" then
			local p = r.B.CFrame:PointToObjectSpace(d.Position)
			if math.abs(p.Y - r.Y0 - 3) < 1 then
				r.Box("Candle", Vector3.new(0.3, 0.6, 0.3), p.X, 3.15, p.Z, rgb(255, 240, 210))
				r.Box("Flame", Vector3.new(0.15, 0.25, 0.15), p.X, 3.75, p.Z, rgb(255, 180, 60), Enum.Material.Neon)
			end
		end
	end
	r.Try(r.W / 2 - 2.2, -2, 1.6, 5, 0, 7, function(x, z)
		r.Box("WineRack", Vector3.new(1.6, 6.4, 5), x, 0, z, rgb(100, 66, 44), Enum.Material.Wood)
		for k = 0, 11 do
			r.Box("WineBottle", Vector3.new(0.5, 0.35, 0.35), x - 0.6, 0.8 + (k % 4) * 1.4, z - 1.8 + (k // 4) * 1.6, ({ rgb(90, 20, 40), rgb(40, 80, 40), rgb(200, 190, 120) })[k % 3 + 1], Enum.Material.Glass)
		end
	end)
	r.Try(-r.W / 2 + 4, -r.D / 2 + 3.5, 1.6, 1.4, 0, 4, function(x, z)
		r.Box("HostStand", Vector3.new(1.6, 3.6, 1.2), x, 0, z, rgb(90, 50, 40), Enum.Material.Wood)
		r.Box("MenuBook", Vector3.new(1, 0.1, 1.2), x, 3.6, z, rgb(150, 30, 40))
	end)
end

EXTRAS.bank = function(r)
	if r.F ~= 1 then
		return
	end
	stanchions(r, -4, -r.D / 2 + 9, 4)
	for _, s in ipairs({ -1, 1 }) do
		r.Try(s * (r.W / 2 - 4), -r.D / 2 + 6, 1.8, 1.8, 0, r.H, function(x, z)
			local col = r.Solid("MarbleColumn", Vector3.new(1.6, r.H, 1.6), x, 0, z, rgb(236, 232, 222), Enum.Material.Marble)
			col.Shape = Enum.PartType.Cylinder
			col.CFrame = col.CFrame * CFrame.Angles(0, 0, math.rad(90))
			col.Size = Vector3.new(r.H, 1.6, 1.6)
		end)
	end
end

EXTRAS.police = function(r)
	if r.F ~= 1 then
		return
	end
	r.Try(-r.W / 2 + 6, r.D / 2 - 7, 7.4, 1.8, 0, 6.2, function(x, z)
		lockers(r, x, z, 4)
	end)
	for k = 0, 1 do
		r.Try(r.W / 2 - 16 - k * 2, -r.D / 2 + 3, 1.8, 2, 0, 4.4, function(x, z)
			cabinet(r, x, z)
		end)
	end
	r.Try(-r.W / 2 + 3, -r.D / 2 + 6, 1.6, 1.6, 0, 7, function(x, z)
		-- a flag on a pole
		r.Box("FlagPole", Vector3.new(0.2, 7, 0.2), x, 0, z, MapKit.GOLD, Enum.Material.Metal)
		r.Box("Flag", Vector3.new(0.08, 2, 3), x, 4.6, z + 1.5, rgb(40, 60, 150), Enum.Material.Fabric)
	end)
	r.Try(-r.W / 2 + 3, 0, 1.4, 1.4, 0, 5, function(x, z)
		waterCooler(r, x, z)
	end)
	for _, x in ipairs({ -4, 4, -12 }) do
		if r.Free(x, r.D / 2 - 1.6, 5.4, 1, 2.6, 5.8) then
			corkBoard(r, x, true)
			break
		end
	end
end

EXTRAS.hospital = function(r)
	for _, d in ipairs(r.B.Model:GetChildren()) do
		if d.Name == "BedFrame" then
			local p = r.B.CFrame:PointToObjectSpace(d.Position)
			if math.abs(p.Y - r.Y0 - 0.7) < 1.5 then
				r.Try(p.X + 2.8, p.Z + 2, 1.2, 1.2, 0, 6, function(x, z)
					ivStand(r, x, z)
				end)
			end
		end
	end
	r.Try(-r.W / 2 + 3, -r.D / 2 + 8, 2.4, 2.6, 0, 3, function(x, z)
		wheelchair(r, x, z)
	end)
	r.Try(r.W / 2 - 3, -r.D / 2 + 6, 2.4, 1.8, 0, 6, function(x, z)
		r.Box("MedCabinet", Vector3.new(2.4, 5.6, 1.6), x, 0, z, WHITE, Enum.Material.SmoothPlastic)
		r.Box("RedCross", Vector3.new(1.4, 0.4, 0.05), x, 4.2, z - 0.82, rgb(220, 40, 50), Enum.Material.Neon)
		r.Box("RedCross", Vector3.new(0.4, 1.4, 0.05), x, 3.7, z - 0.82, rgb(220, 40, 50), Enum.Material.Neon)
	end)
end

EXTRAS.classroom = function(r)
	r.Try(r.W / 2 - 3, r.D / 2 - 5, 1.4, 5, 0, 7, function(x, z)
		bookshelf(r, x, z, 5, false)
	end)
	r.Try(-r.W / 2 + 3, r.D / 2 - 4, 1.6, 1.6, 0, 5, function(x, z)
		globe(r, x, z)
	end)
	-- colorful posters high on the back wall
	for k, x in ipairs({ -r.W / 2 + 6, r.W / 2 - 6 }) do
		if r.Free(x, r.D / 2 - 1.6, 3, 1, 7, 10) then
			r.Box("Poster", Vector3.new(2.6, 2, 0.08), x, 7.4, r.D / 2 - 1.1, ({ rgb(250, 200, 80), rgb(120, 200, 250) })[k], Enum.Material.SmoothPlastic)
			r.Box("PosterPrint", Vector3.new(1.6, 0.3, 0.1), x, 8.4, r.D / 2 - 1.15, rgb(60, 60, 70))
		end
	end
end

EXTRAS.library = function(r)
	for k = 0, 1 do
		r.Try(-r.W / 4 + k * (r.W / 2), -r.D / 2 + 7, 5, 3, 0, 5, function(x, z)
			r.Box("StudyTable", Vector3.new(5, 0.3, 3), x, 2.8, z, rgb(130, 90, 60), Enum.Material.Wood)
			r.Box("TableLeg", Vector3.new(0.4, 2.8, 2.6), x - 2.2, 0, z, rgb(100, 70, 50), Enum.Material.Wood)
			r.Box("TableLeg", Vector3.new(0.4, 2.8, 2.6), x + 2.2, 0, z, rgb(100, 70, 50), Enum.Material.Wood)
			r.Box("ReadingLampBase", Vector3.new(0.6, 0.15, 0.6), x, 3.1, z, rgb(40, 90, 60), Enum.Material.Metal)
			r.Box("ReadingLampNeck", Vector3.new(0.1, 1.2, 0.1), x, 3.25, z, MapKit.GOLD, Enum.Material.Metal)
			r.Box("ReadingLampShade", Vector3.new(1.4, 0.4, 0.6), x, 4.4, z, rgb(40, 110, 70), Enum.Material.Glass)
			r.Box("OpenBook", Vector3.new(1.4, 0.1, 1), x + 1.4, 3.1, z, rgb(250, 245, 230))
		end)
	end
	r.Try(r.W / 2 - 3, 0, 1.6, 1.6, 0, 5, function(x, z)
		globe(r, x, z)
	end)
end

EXTRAS.gym = function(r)
	-- a mirror wall and a water fountain
	local m = r.Box("MirrorWall", Vector3.new(math.min(16, r.W - 12), 5, 0.1), -r.W / 6, 3.3, r.D / 2 - 1.1, rgb(210, 230, 240), Enum.Material.Glass)
	m.Reflectance = 0.45
	r.Try(r.W / 2 - 2.5, -r.D / 2 + 8, 1.6, 1.4, 0, 4, function(x, z)
		r.Box("WaterFountain", Vector3.new(1.6, 3.4, 1.2), x, 0, z, rgb(200, 204, 210), Enum.Material.Metal)
		r.Box("FountainBowl", Vector3.new(1.2, 0.3, 0.9), x, 3.4, z, rgb(170, 200, 230), Enum.Material.Metal)
	end)
	r.Try(-r.W / 2 + 3, 0, 2, 4, 0, 2, function(x, z)
		for k = 0, 2 do
			r.Box("YogaMat", Vector3.new(1.8, 0.4, 3.6), x + 0, k * 0.4, z, ({ rgb(150, 90, 200), rgb(60, 180, 170), rgb(240, 120, 90) })[k + 1], Enum.Material.Fabric)
		end
	end)
end

EXTRAS.hotel = function(r)
	if r.F ~= 1 then
		return
	end
	r.Try(-r.W / 2 + 6, 2, 6.2, 3, 0, 4, function(x, z)
		sofa(r, x, z, rgb(120, 40, 50), 6)
	end)
	r.Try(r.W / 2 - 4, -r.D / 2 + 6, 3, 2, 0, 5, function(x, z)
		-- a luggage cart
		r.Box("CartBase", Vector3.new(3, 0.3, 2), x, 0.6, z, MapKit.GOLD, Enum.Material.Metal)
		r.Box("CartPole", Vector3.new(0.15, 4.4, 0.15), x - 1.4, 0.6, z, MapKit.GOLD, Enum.Material.Metal)
		r.Box("CartPole", Vector3.new(0.15, 4.4, 0.15), x + 1.4, 0.6, z, MapKit.GOLD, Enum.Material.Metal)
		r.Box("CartTop", Vector3.new(3, 0.15, 0.15), x, 5, z, MapKit.GOLD, Enum.Material.Metal)
		r.Box("Suitcase", Vector3.new(1.4, 1.8, 0.8), x - 0.6, 0.9, z, rgb(60, 90, 140), Enum.Material.Leather)
		for _, wx in ipairs({ -1.2, 1.2 }) do
			for _, wz in ipairs({ -0.7, 0.7 }) do
				r.Box("CartWheel", Vector3.new(0.4, 0.62, 0.4), x + wx, 0, z + wz, rgb(30, 30, 34), Enum.Material.Rubber)
			end
		end
		r.Box("Suitcase", Vector3.new(1.2, 1.4, 0.8), x + 0.7, 0.9, z, rgb(150, 60, 50), Enum.Material.Leather)
	end)
end

EXTRAS.home = function(r)
	r.Try(-r.W / 2 + 2, -r.D / 2 + 5, 1.4, 4, 0, 7, function(x, z)
		bookshelf(r, x, z, 4, false)
	end)
	r.Try(-r.W / 4 + 4.2, 1.4, 1.2, 1.2, 0, 5, function(x, z)
		floorLamp(r, x, z, true)
	end)
	r.Try(-r.W / 4, -2.6, 3, 1.6, 0, 1.6, function(x, z)
		r.Box("CoffeeTable", Vector3.new(3, 0.25, 1.6), x, 1.2, z, rgb(130, 90, 60), Enum.Material.Wood)
		r.Box("TableLeg", Vector3.new(2.8, 1.2, 1.4), x, 0, z, rgb(100, 70, 50), Enum.Material.Wood)
		r.Box("Magazine", Vector3.new(0.9, 0.05, 1.1), x - 0.6, 1.45, z, rgb(220, 90, 90))
		r.Box("Mug", Vector3.new(0.4, 0.5, 0.4), x + 0.8, 1.45, z, WHITE)
	end)
	-- bedside tables with lamps
	for _, d in ipairs(r.B.Model:GetChildren()) do
		if d.Name == "Headboard" then
			local p = r.B.CFrame:PointToObjectSpace(d.Position)
			if math.abs(p.Y - r.Y0 - 1.7) < 1.5 then
				r.Try(p.X + 3, p.Z - 0.6, 1.4, 1.4, 0, 3.4, function(x, z)
					r.Box("Nightstand", Vector3.new(1.4, 2, 1.4), x, 0, z, rgb(140, 100, 70), Enum.Material.Wood)
					local lamp = r.Box("BedsideLamp", Vector3.new(0.8, 0.9, 0.8), x, 2, z, rgb(255, 236, 190), Enum.Material.Fabric)
					local _ = lamp
				end)
			end
		end
	end
end
EXTRAS.apartment = EXTRAS.home

EXTRAS.daycare = function(r)
	for k = 0, 1 do
		r.Try(-r.W / 4 + k * 8, -r.D / 2 + 7, 3.8, 2.6, 0, 3, function(x, z)
			toyPile(r, x, z)
		end)
	end
	r.Try(r.W / 2 - 3, r.D / 2 - 5, 1.6, 6, 0, 4, function(x, z)
		-- cubbies with little backpacks
		r.Box("Cubbies", Vector3.new(1.6, 3.6, 6), x, 0, z, rgb(250, 230, 200), Enum.Material.Wood)
		for k = 0, 3 do
			r.Box("KidBag", Vector3.new(0.8, 0.9, 1), x - 0.3, 1.9, z - 2.2 + k * 1.45, MapKit.FLOWERS[k + 1], Enum.Material.Fabric)
		end
	end)
end

EXTRAS.garage = function(r)
	for k = 0, 2 do
		r.Try(r.W / 2 - 3, r.D / 2 - 3 - k * 2.2, 2, 2, 0, 3, function(x, z)
			barrel(r, x, z, ({ rgb(40, 90, 160), rgb(200, 60, 50), rgb(230, 170, 40) })[k + 1])
		end)
	end
	r.Try(-r.W / 4, r.D / 2 - 1.8, 8, 1.2, 0, 7, function(x, z)
		pegboard(r, x, 8)
	end)
end
EXTRAS.warehouse = function(r)
	for k = 0, 3 do
		r.Try(-r.W / 2 + 5 + k * 5, -r.D / 2 + 5, 4, 4, 0, 4, function(x, z)
			pallet(r, x, z)
		end)
	end
end
EXTRAS.factory = function(r)
	for k = 0, 3 do
		r.Try(r.W / 2 - 3, -r.D / 2 + 4 + k * 2.4, 2, 2, 0, 3, function(x, z)
			barrel(r, x, z, rgb(230, 170, 40))
		end)
	end
end

EXTRAS.townhall = function(r)
	if r.F ~= 1 then
		return
	end
	for _, s in ipairs({ -1, 1 }) do
		r.Try(s * (r.W / 2 - 3), r.D / 2 - 4, 1.6, 1.6, 0, 7, function(x, z)
			r.Box("FlagPole", Vector3.new(0.2, 7, 0.2), x, 0, z, MapKit.GOLD, Enum.Material.Metal)
			r.Box("Flag", Vector3.new(0.08, 2, 3), x, 4.6, z - 1.5 * s * 0, ({ rgb(40, 60, 150), rgb(200, 50, 60) })[(s + 3) // 2], Enum.Material.Fabric)
		end)
	end
end

EXTRAS.community = function(r)
	r.Try(r.W / 2 - 4, r.D / 2 - 4, 6, 3, 0, 4, function(x, z)
		sofa(r, x, z, rgb(90, 130, 90), 5)
	end)
	board(r, -r.W / 4, 4.6, 6, 3, "COMMUNITY BOARD\nBake sale Saturday!", rgb(170, 120, 70), WHITE)
end

EXTRAS.postoffice = function(r)
	r.Try(r.W / 2 - 3, -r.D / 2 + 6, 1.8, 4, 0, 4, function(x, z)
		-- a wall of PO boxes
		r.Box("POBoxes", Vector3.new(1.4, 4, 4), x, 0, z, rgb(180, 150, 90), Enum.Material.Metal)
		for i = 0, 2 do
			for j = 0, 3 do
				r.Box("POBoxDoor", Vector3.new(0.05, 1, 0.8), x - 0.72, 0.4 + i * 1.2, z - 1.5 + j * 1, rgb(210, 180, 110), Enum.Material.Metal)
			end
		end
	end)
	for k = 0, 2 do
		r.Try(-r.W / 2 + 3 + k * 2.2, r.D / 2 - 3, 2, 2, 0, 3, function(x, z)
			r.Box("Parcel", Vector3.new(1.8, 1.2 + k * 0.3, 1.4), x, 0, z, rgb(190, 150, 100), Enum.Material.Cardboard)
		end)
	end
end

--------------------------------------------------------------------------------
function Decor.dress(b, f, kind, rng, place, spots)
	local theme = THEMES[kind]
	if not theme then
		return
	end
	local r = room(b, f, rng, kind, place, spots)
	local extras = EXTRAS[kind]
	if extras then
		local ok, err = pcall(extras, r)
		if not ok then
			warn("[Decor] " .. kind .. ": " .. tostring(err))
		end
	end
	local ok, err = pcall(dressRoom, r, theme)
	if not ok then
		warn("[Decor] dress " .. kind .. ": " .. tostring(err))
	end
end

return Decor
