-- StreetLife (ModuleScript) — ServerScriptService.Modules.StreetLife
-- Life on the streets all over town, not just in the plaza:
--   🚚 food trucks parked at the curb across the city (a cook at the window,
--      a queue on the sidewalk, people eating on their feet)
--   🎸 street musicians in the plaza, the parks, on the boardwalk and at
--      Funland, with people stopping to listen, clap and cheer (players can
--      tip them: see StreetLifeService)
-- Each truck is its own little outdoor place ("FoodTruck1"...), so people
-- walk to it along the sidewalks.

local MapKit = require(script.Parent:WaitForChild("MapKit"))

local StreetLife = {}

local rgb, WHITE, BLACK = MapKit.rgb, MapKit.WHITE, MapKit.BLACK
local SPACING, HALF, ROAD = MapKit.SPACING, MapKit.HALF, MapKit.ROAD

-- { block i, block j, side of the block the truck parks on, name, colour, food }
StreetLife.TRUCKS = {
	{ -1, 0, "S", "🌮 TACO TRUCK", rgb(240, 120, 40), "taco" },
	{ 1, -1, "E", "🍔 BURGER BUS", rgb(220, 50, 50), "burger" },
	{ 0, 2, "N", "🍦 SCOOP SHACK", rgb(250, 160, 200), "icecream" },
	{ 2, 1, "W", "🥙 GYRO GO", rgb(60, 140, 220), "wrap" },
	{ -2, -2, "S", "🍜 NOODLE NOMAD", rgb(240, 200, 60), "noodles" },
	{ -1, 3, "E", "☕ COFFEE CART", rgb(120, 80, 60), "coffee" },
}
StreetLife.ALONG = 50 -- how far along the block from its middle (parked cars stay within ±32)

local FACE = { N = Vector3.new(0, 0, -1), S = Vector3.new(0, 0, 1), E = Vector3.new(1, 0, 0), W = Vector3.new(-1, 0, 0) }

-- where a truck parks: its middle in the curb lane, facing along the road
function StreetLife.TruckFrame(t)
	local c = Vector3.new(t[1] * SPACING, 0, t[2] * SPACING)
	local f = FACE[t[3]]
	local along = Vector3.new(-f.Z, 0, f.X)
	local mid = c + f * (HALF + 3.6) + along * StreetLife.ALONG
	return CFrame.lookAt(mid, mid + along), f, along, c
end

-- is this spot taken by a truck? (Streets keeps its parked cars clear)
function StreetLife.Reserved(pos)
	for _, t in ipairs(StreetLife.TRUCKS) do
		local cf = StreetLife.TruckFrame(t)
		if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(cf.Position.X, 0, cf.Position.Z)).Magnitude < 18 then
			return true
		end
	end
	return false
end

local function spotAt(pos, look, action, role)
	return { CFrame = CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z)), Action = action, Role = role or "visit", Floor = 1 }
end

-- a food truck: a boxy van with a serving window on the sidewalk side, an
-- awning, a menu board, a counter with napkins and sauce, and a bin
local function truck(parent, t, n)
	local cf, f = StreetLife.TruckFrame(t)
	local m = Instance.new("Model")
	m.Name = "FoodTruck" .. n
	m.Parent = parent
	local color = t[5]
	local function box(name, size, offset, col, mat, collide)
		local p = (if collide then MapKit.part else MapKit.deco)(m, name, size, cf * offset, col, mat)
		return p
	end
	-- (the truck's local X points away from the sidewalk: f is +X... so the
	-- window is on its -X side, toward the block)
	local side = cf:VectorToObjectSpace(-f)
	local sx = if side.X > 0 then 1 else -1
	local Y = 0.1
	-- the body: a hollow box so you can see the cook inside
	box("TruckFloor", Vector3.new(6, 0.4, 11), CFrame.new(0, Y + 1.6, 0), rgb(70, 70, 76), Enum.Material.DiamondPlate, true)
	box("TruckRoof", Vector3.new(6.2, 0.4, 11.2), CFrame.new(0, Y + 8.2, 0), color:Lerp(WHITE, 0.3), Enum.Material.SmoothPlastic, true)
	box("TruckWall", Vector3.new(0.3, 6.4, 11), CFrame.new(-sx * 2.85, Y + 4.9, 0), color, Enum.Material.SmoothPlastic, true)
	box("TruckWall", Vector3.new(6, 6.4, 0.3), CFrame.new(0, Y + 4.9, -5.35), color, Enum.Material.SmoothPlastic, true)
	box("TruckWall", Vector3.new(6, 6.4, 0.3), CFrame.new(0, Y + 4.9, 5.35), color, Enum.Material.SmoothPlastic, true)
	-- the window side: solid below and above the window, open in the middle
	box("TruckWall", Vector3.new(0.3, 2.4, 11), CFrame.new(sx * 2.85, Y + 2.9, 0), color, Enum.Material.SmoothPlastic, true)
	box("TruckWall", Vector3.new(0.3, 1.4, 11), CFrame.new(sx * 2.85, Y + 7.3, 0), color, Enum.Material.SmoothPlastic, true)
	for _, z in ipairs({ -4.6, 4.6 }) do
		box("TruckWall", Vector3.new(0.3, 2.6, 1.8), CFrame.new(sx * 2.85, Y + 5.3, z), color, Enum.Material.SmoothPlastic, true)
	end
	box("ServingLedge", Vector3.new(1.2, 0.2, 7.4), CFrame.new(sx * 3.3, Y + 4.1, 0), rgb(200, 200, 206), Enum.Material.Metal)
	-- a stripe and the name along the side
	box("TruckStripe", Vector3.new(0.32, 0.5, 11.02), CFrame.new(sx * 2.86, Y + 1.9, 0), WHITE)
	local sign = box("TruckSign", Vector3.new(0.34, 1.2, 9), CFrame.new(sx * 2.88, Y + 7.3, 0), color:Lerp(BLACK, 0.4))
	MapKit.signText(sign, if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left, t[4], WHITE, Enum.Font.GothamBlack)
	-- the cab at the front, with a windscreen and headlights
	box("TruckCab", Vector3.new(6, 4.6, 3.6), CFrame.new(0, Y + 3.8, -7.3), color, Enum.Material.SmoothPlastic, true)
	local glass = box("TruckWindscreen", Vector3.new(5.4, 1.8, 0.2), CFrame.new(0, Y + 4.9, -9.12), rgb(150, 190, 220), Enum.Material.Glass)
	glass.Transparency = 0.2
	for _, x in ipairs({ -2.2, 2.2 }) do
		box("TruckHeadlight", Vector3.new(0.8, 0.5, 0.15), CFrame.new(x, Y + 2.4, -9.15), rgb(255, 250, 220), Enum.Material.Neon)
	end
	-- wheels
	for _, z in ipairs({ -7, 3.6 }) do
		for _, x in ipairs({ -2.8, 2.8 }) do
			MapKit.cylinder(m, "TruckWheel", 0.9, 2.4, cf * CFrame.new(x, Y + 1.2, z), rgb(24, 24, 26), Enum.Material.Rubber)
		end
	end
	-- the striped awning over the window
	MapKit.awning(m, 8, 2.4, cf * CFrame.new(sx * 4, Y + 8, 0) * CFrame.Angles(0, sx * math.pi / 2, 0), color, WHITE)
	-- inside: a grill, a fridge, a menu board
	box("Grill", Vector3.new(1.8, 0.9, 3), CFrame.new(-sx * 1.6, Y + 2.25, 2.2), rgb(60, 60, 64), Enum.Material.Metal)
	box("GrillTop", Vector3.new(1.6, 0.1, 2.8), CFrame.new(-sx * 1.6, Y + 2.75, 2.2), rgb(30, 30, 32), Enum.Material.DiamondPlate)
	box("TruckFridge", Vector3.new(1.8, 4.4, 2), CFrame.new(-sx * 1.6, Y + 4, -3.4), rgb(220, 222, 226), Enum.Material.Metal)
	local menu = box("MenuBoard", Vector3.new(0.2, 2.2, 3.4), CFrame.new(sx * 3.1, Y + 3, -6.2), rgb(30, 30, 34))
	MapKit.signText(menu, if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left, "MENU\n" .. t[4]:gsub("^[^%w]+%s*", ""), rgb(255, 230, 120), Enum.Font.GothamBold)
	-- on the sidewalk: napkins, a bin
	local walk = cf * CFrame.new(sx * 5.4, 0, 0)
	MapKit.column(m, "TruckBin", 2.2, 1.6, (walk * CFrame.new(0, 1.4, 6)).Position, rgb(60, 110, 70), Enum.Material.Metal, true)
	-- the cook's spot (inside, at the window) and the queue on the sidewalk
	local spots = {}
	local inside = (cf * CFrame.new(sx * 1.4, Y + 1.8, 0)).Position
	local outside = (cf * CFrame.new(sx * 5.2, 0.5, 0)).Position
	table.insert(spots, spotAt(inside, outside, "cook", "work"))
	for k = 0, 3 do
		local p = (cf * CFrame.new(sx * 5.6, 0.5, -2.6 + k * 2.4)).Position
		table.insert(spots, spotAt(p, if k == 0 then inside else p + (inside - outside), if k % 2 == 0 then "snack" else "wait"))
	end
	-- a couple of people eating standing up a little way off
	for k = 0, 1 do
		local p = (cf * CFrame.new(sx * 6.4, 0.5, 6.5 + k * 2.2)).Position
		table.insert(spots, spotAt(p, (cf * CFrame.new(sx * 6.4, 0.5, 0)).Position, "snack"))
	end
	return m, spots, outside
end

-- builds the trucks (each a little place of its own); returns their places
function StreetLife.build(ctx, parent)
	local folder = Instance.new("Folder")
	folder.Name = "StreetLife"
	folder.Parent = parent
	local places = {}
	for n, t in ipairs(StreetLife.TRUCKS) do
		local m, spots, door = truck(folder, t, n)
		local face = FACE[t[3]]
		local place = ctx.outdoor("FoodTruck" .. n, m, t[1], t[2], door, face, spots)
		place.Label = t[4]
		place.Kind = "food"
		place.Food = t[6]
		place.NoPin = false
		table.insert(places, place)
	end
	return places
end

return StreetLife
