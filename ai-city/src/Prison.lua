-- Prison (ModuleScript) — ServerScriptService.Modules.Prison
-- AI City State Prison: a walled compound on the east side of town, at the
-- end of Prison Road. Built by MapBuilder; PrisonService runs the people.
--
--   • A perimeter wall with razor wire, a gate with a guard booth, and a
--     guard tower with a sweeping searchlight on every corner
--   • Cell Block A: two tiers of barred cells along a long hall. The 16 cells
--     on the ground floor have bunk beds, a toilet, a sink and a sliding door
--     that opens in the morning and slams shut at lights out. The hall in the
--     middle is the mess hall (steel tables, a serving counter) and the TV
--     lounge, with a guard desk by the yard door.
--   • The yard: a basketball court, a weight pit, picnic tables, and a
--     walking track around it all
--   • The administration building, a parking lot and the prison bus
--
-- Prison.build(parent, rng) returns everything PrisonService needs (cells,
-- spots, doors, walking lanes) in map.Prison. Positions inside are in the
-- prison's own frame: local -Z faces the city, and Prison.F turns them into
-- world positions.

local MapKit = require(script.Parent:WaitForChild("MapKit"))
local Streets = require(script.Parent:WaitForChild("Streets"))

local Prison = {}

local rgb, WHITE, BLACK = MapKit.rgb, MapKit.WHITE, MapKit.BLACK

-- where it is: east of the city, facing west down Prison Road
Prison.CENTER = Vector3.new(MapKit.EXTENT + 230, 0, -MapKit.EXTENT * 0.35)
Prison.W, Prison.D = 170, 150 -- inside the walls (local x, local z)
Prison.RADIUS = 125 -- keep trees and hills this far away
Prison.F = CFrame.lookAt(Prison.CENTER, Prison.CENTER + Vector3.new(-1, 0, 0))

local G = 0.3 -- the top of the compound's concrete slab
Prison.G = G
local SPINE = 20 -- the hall's walkway (local z)
local CELL_W, CELL_D, TIER = 12, 10, 11
local BLOCK_X0, BLOCK_X1, BLOCK_Z0, BLOCK_Z1, BLOCK_H = -80, 16, -6, 46, 24

local CONCRETE = rgb(176, 174, 168)
local DARK_CONCRETE = rgb(128, 126, 122)
local STEEL = rgb(62, 66, 72)
local FLOOR = rgb(150, 150, 146)

local F = Prison.F
local model

local function cf(x, y, z)
	return F * CFrame.new(x, G + y, z)
end
local function pos(x, y, z)
	return (F * CFrame.new(x, G + y, z)).Position
end
Prison.Pos = pos

-- a box standing on the slab: (x, z) is its center, y its bottom
local function solid(name, size, x, y, z, color, material)
	return MapKit.part(model, name, size, cf(x, y + size.Y / 2, z), color, material)
end
local function deco(name, size, x, y, z, color, material)
	return MapKit.deco(model, name, size, cf(x, y + size.Y / 2, z), color, material)
end
-- a spot for someone to be (standing at x, z, facing toward fx, fz)
local function spotAt(x, z, fx, fz, extra)
	local p = pos(x, 0, z)
	local look = pos(fx, 0, fz)
	if (look - p).Magnitude < 0.1 then
		look = p + F.LookVector
	end
	local s = { CFrame = CFrame.lookAt(p, Vector3.new(look.X, p.Y, look.Z)), Local = Vector3.new(x, 0, z) }
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

--------------------------------------------------------------------------------
-- The walls, the gate, the towers
--------------------------------------------------------------------------------
local function perimeter(data)
	local hw, hd, h = Prison.W / 2, Prison.D / 2, 18
	local wall = rgb(160, 158, 150)
	-- the back and the two sides; the front has the gate in the middle
	solid("PerimeterWall", Vector3.new(Prison.W + 4, h, 2), 0, 0, hd + 1, wall, Enum.Material.Concrete)
	solid("PerimeterWall", Vector3.new(2, h, Prison.D + 4), -hw - 1, 0, 0, wall, Enum.Material.Concrete)
	solid("PerimeterWall", Vector3.new(2, h, Prison.D + 4), hw + 1, 0, 0, wall, Enum.Material.Concrete)
	local gateHalf = 9
	local seg = hw - gateHalf + 1
	for _, sx in ipairs({ -1, 1 }) do
		solid("PerimeterWall", Vector3.new(seg + 1, h, 2), sx * (gateHalf + seg / 2), 0, -hd - 1, wall, Enum.Material.Concrete)
	end
	-- razor wire along the top: two coils on little posts
	local function wire(x0, z0, x1, z1)
		local a, b = pos(x0, h + 1.1, z0), pos(x1, h + 1.1, z1)
		local mid, len = (a + b) / 2, (b - a).Magnitude
		MapKit.cylinder(model, "RazorWire", len, 1.1, CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0), rgb(150, 154, 160), Enum.Material.DiamondPlate).Transparency = 0.25
	end
	wire(-hw - 2, hd + 1, hw + 2, hd + 1)
	wire(-hw - 1, -hd - 2, -hw - 1, hd + 2)
	wire(hw + 1, -hd - 2, hw + 1, hd + 2)
	wire(-hw - 2, -hd - 1, -gateHalf, -hd - 1)
	wire(gateHalf, -hd - 1, hw + 2, -hd - 1)
	-- the gate: a steel frame, two sliding gates (open in the daytime for
	-- visitors), a barrier arm and a guard booth
	solid("GateBeam", Vector3.new(gateHalf * 2 + 4, 3, 3), 0, h - 1, -hd - 1, STEEL, Enum.Material.Metal)
	local sign = deco("PrisonSign", Vector3.new(gateHalf * 2 + 2, 2.6, 0.3), 0, h - 0.8, -hd - 2.7, rgb(30, 34, 40))
	MapKit.signText(sign, Enum.NormalId.Back, "AI CITY STATE PRISON", rgb(250, 210, 80), Enum.Font.GothamBlack)
	MapKit.signText(sign, Enum.NormalId.Front, "AI CITY STATE PRISON", rgb(250, 210, 80), Enum.Font.GothamBlack)
	for _, sx in ipairs({ -1, 1 }) do
		local panel = deco("GatePanel", Vector3.new(gateHalf, h - 3, 0.5), sx * (gateHalf + gateHalf / 2 - 0.5), 0, -hd - 3, STEEL, Enum.Material.DiamondPlate)
		panel.Transparency = 0.35
	end
	local arm = deco("BarrierArm", Vector3.new(gateHalf * 2 - 2, 0.5, 0.5), -gateHalf + 1, 3.3, -hd - 6, rgb(230, 60, 50)) -- (raised, pivoting on its post)
	arm.CFrame = arm.CFrame * CFrame.Angles(0, 0, math.rad(70)) * CFrame.new(gateHalf - 1, 0, 0)
	deco("BarrierPost", Vector3.new(1, 3.6, 1), -gateHalf + 1, 0, -hd - 6, rgb(240, 200, 60), Enum.Material.Metal)
	solid("GuardBooth", Vector3.new(7, 8, 7), gateHalf + 6, 0, -hd - 7, rgb(200, 198, 190), Enum.Material.Concrete)
	local window = deco("BoothWindow", Vector3.new(5, 3, 0.2), gateHalf + 6, 3.6, -hd - 10.6, rgb(170, 210, 230), Enum.Material.Glass)
	window.Transparency = 0.3
	solid("BoothRoof", Vector3.new(8.4, 0.6, 8.4), gateHalf + 6, 8, -hd - 7, STEEL, Enum.Material.Metal)
	data.Gate = pos(0, 0, -hd - 10)
	data.GateInside = pos(0, 0, -hd + 6)
	data.Booth = spotAt(gateHalf + 1.5, -hd - 10.5, gateHalf + 1.5, -hd - 20)
	-- the four towers, a guard up in each, and a searchlight that sweeps the yard
	data.Towers = {}
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local x, z = c[1] * (hw - 4), c[2] * (hd - 4)
		solid("TowerLeg", Vector3.new(6, 26, 6), x, 0, z, DARK_CONCRETE, Enum.Material.Concrete)
		solid("TowerFloor", Vector3.new(11, 1, 11), x, 26, z, STEEL, Enum.Material.Metal)
		for _, e in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
			local size = if e[1] == 0 then Vector3.new(11, 1.4, 0.4) else Vector3.new(0.4, 1.4, 11)
			deco("TowerRail", size, x + e[1] * 5.3, 27, z + e[2] * 5.3, STEEL, Enum.Material.Metal)
			local glass = deco("TowerGlass", if e[1] == 0 then Vector3.new(10, 3.6, 0.2) else Vector3.new(0.2, 3.6, 10), x + e[1] * 5.3, 28.4, z + e[2] * 5.3, rgb(160, 200, 220), Enum.Material.Glass)
			glass.Transparency = 0.55
		end
		for _, px in ipairs({ -1, 1 }) do
			for _, pz in ipairs({ -1, 1 }) do
				deco("TowerPost", Vector3.new(0.5, 5.2, 0.5), x + px * 5.2, 27, z + pz * 5.2, STEEL, Enum.Material.Metal)
			end
		end
		deco("TowerRoof", Vector3.new(12.4, 0.8, 12.4), x, 32.2, z, rgb(60, 64, 72), Enum.Material.Metal)
		-- the searchlight: its head turns (see PrisonService)
		local head = deco("Searchlight", Vector3.new(1.4, 1.4, 2.2), x, 32.8, z, rgb(230, 230, 220), Enum.Material.Metal)
		local lens = deco("SearchlightLens", Vector3.new(1.1, 1.1, 0.2), x, 33.1, z, rgb(255, 250, 220), Enum.Material.Neon)
		lens.CFrame = head.CFrame * CFrame.new(0, 0, -1.15)
		local beam = MapKit.spot(head, Enum.NormalId.Front, rgb(255, 250, 225), 120, 22, 4)
		beam.Enabled = false
		table.insert(data.Towers, {
			Head = head, Lens = lens, Light = beam, Base = pos(x, 32.8 + 0.7, z),
			Aim = pos(-x * 0.2, 0, -z * 0.2), Guard = spotAt(x - c[1] * 2, z - c[2] * 2, 0, 0, { Raise = 27 }),
		})
	end
end

--------------------------------------------------------------------------------
-- Cell Block A
--------------------------------------------------------------------------------
-- the bars across a cell front (local x0..x1 at z), leaving a door gap
local function bars(x0, x1, z, y0, h, gap0, gap1)
	local x = x0 + 0.3
	while x < x1 - 0.2 do
		if not gap0 or x < gap0 - 0.1 or x > gap1 + 0.1 then
			solid("CellBar", Vector3.new(0.28, h, 0.28), x, y0, z, STEEL, Enum.Material.Metal)
		end
		x += 1.15
	end
	for _, y in ipairs({ 0.05, h * 0.45, h - 0.35 }) do
		if gap0 then
			if y > h * 0.9 then
				deco("CellRail", Vector3.new(x1 - x0, 0.3, 0.4), (x0 + x1) / 2, y0 + y, z, STEEL, Enum.Material.Metal)
			else
				deco("CellRail", Vector3.new(gap0 - x0, 0.3, 0.4), (x0 + gap0) / 2, y0 + y, z, STEEL, Enum.Material.Metal)
				deco("CellRail", Vector3.new(x1 - gap1, 0.3, 0.4), (gap1 + x1) / 2, y0 + y, z, STEEL, Enum.Material.Metal)
			end
		else
			deco("CellRail", Vector3.new(x1 - x0, 0.3, 0.4), (x0 + x1) / 2, y0 + y, z, STEEL, Enum.Material.Metal)
		end
	end
end

-- a sliding barred door: a see-through blocker and the bars that ride on it
local function slidingDoor(x0, x1, z, h, openShift)
	local parts = {}
	local w = x1 - x0
	local blocker = solid("CellDoor", Vector3.new(w, h - 0.5, 0.3), (x0 + x1) / 2, 0, z, STEEL, Enum.Material.Metal)
	blocker.Transparency = 1
	table.insert(parts, blocker)
	for k = 0, 2 do
		table.insert(parts, deco("CellDoorBar", Vector3.new(0.26, h - 0.6, 0.26), x0 + 0.5 + k * (w - 1) / 2, 0.1, z - 0.3, rgb(80, 84, 92), Enum.Material.Metal))
	end
	for _, y in ipairs({ 0.3, h * 0.45, h - 1 }) do
		table.insert(parts, deco("CellDoorRail", Vector3.new(w, 0.28, 0.3), (x0 + x1) / 2, y, z - 0.3, rgb(80, 84, 92), Enum.Material.Metal))
	end
	local door = { Parts = {}, Open = false }
	local shift = (F * CFrame.new(openShift, 0, 0)).Position - F.Position
	for _, p in ipairs(parts) do
		table.insert(door.Parts, { Part = p, Closed = p.CFrame, Opened = p.CFrame + shift })
	end
	return door
end

local function cellBlock(data, rng)
	local x0, x1, z0, z1, H = BLOCK_X0, BLOCK_X1, BLOCK_Z0, BLOCK_Z1, BLOCK_H
	local wallC = rgb(196, 192, 182)
	-- the shell: back, front and west walls, the east wall with the yard door
	solid("BlockWall", Vector3.new(x1 - x0 + 2, H, 1.4), (x0 + x1) / 2, 0, z0 - 0.7, wallC, Enum.Material.Concrete)
	solid("BlockWall", Vector3.new(x1 - x0 + 2, H, 1.4), (x0 + x1) / 2, 0, z1 + 0.7, wallC, Enum.Material.Concrete)
	solid("BlockWall", Vector3.new(1.4, H, z1 - z0 + 2.8), x0 - 0.7, 0, (z0 + z1) / 2, wallC, Enum.Material.Concrete)
	local doorZ0, doorZ1, doorH = SPINE - 6, SPINE + 6, 11
	solid("BlockWall", Vector3.new(1.4, H, doorZ0 - z0 + 1.4), x1 + 0.7, 0, (z0 - 1.4 + doorZ0) / 2, wallC, Enum.Material.Concrete)
	solid("BlockWall", Vector3.new(1.4, H, z1 + 1.4 - doorZ1), x1 + 0.7, 0, (doorZ1 + z1 + 1.4) / 2, wallC, Enum.Material.Concrete)
	solid("BlockWall", Vector3.new(1.4, H - doorH, doorZ1 - doorZ0), x1 + 0.7, doorH, SPINE, wallC, Enum.Material.Concrete)
	local label = deco("BlockSign", Vector3.new(14, 2.4, 0.3), x1 + 1.6, doorH + 1.2, SPINE, rgb(30, 34, 40))
	label.CFrame = label.CFrame * CFrame.Angles(0, math.rad(90), 0)
	MapKit.signText(label, Enum.NormalId.Front, "CELL BLOCK A", rgb(250, 210, 80), Enum.Font.GothamBlack)
	MapKit.signText(label, Enum.NormalId.Back, "CELL BLOCK A", rgb(250, 210, 80), Enum.Font.GothamBlack)
	-- a stripe and slit windows high up on the long walls
	for _, z in ipairs({ z0 - 1.45, z1 + 1.45 }) do
		deco("BlockStripe", Vector3.new(x1 - x0 + 2, 1.2, 0.1), (x0 + x1) / 2, 3, z, rgb(60, 80, 120))
		for x = x0 + 6, x1 - 4, 12 do
			local w = deco("SlitWindow", Vector3.new(1.2, 5, 0.2), x, 15, z, rgb(160, 190, 210), Enum.Material.Glass)
			w.Transparency = 0.2
		end
	end
	-- the roof, with a skylight down the middle
	solid("BlockRoof", Vector3.new(x1 - x0 + 3, 1, SPINE - 4 - z0 + 1.5), (x0 + x1) / 2, H, (z0 - 1.5 + SPINE - 4) / 2, DARK_CONCRETE, Enum.Material.Concrete)
	solid("BlockRoof", Vector3.new(x1 - x0 + 3, 1, z1 + 1.5 - SPINE - 4), (x0 + x1) / 2, H, (SPINE + 4 + z1 + 1.5) / 2, DARK_CONCRETE, Enum.Material.Concrete)
	local sky = solid("Skylight", Vector3.new(x1 - x0 + 3, 0.6, 8), (x0 + x1) / 2, H + 0.2, SPINE, rgb(190, 215, 230), Enum.Material.Glass)
	sky.Transparency = 0.45
	-- a polished floor and a yellow walking line down the hall
	deco("BlockFloor", Vector3.new(x1 - x0, 0.06, z1 - z0), (x0 + x1) / 2, 0, (z0 + z1) / 2, FLOOR, Enum.Material.SmoothPlastic).Reflectance = 0.08
	deco("HallLine", Vector3.new(x1 - x0 - 4, 0.07, 0.4), (x0 + x1) / 2 + 2, 0, SPINE, rgb(240, 200, 60))
	-- hanging lights
	for x = x0 + 10, x1 - 6, 16 do
		local lamp = deco("HallLamp", Vector3.new(3, 0.5, 1.4), x, H - 3, SPINE, rgb(255, 245, 225), Enum.Material.Neon)
		deco("LampCord", Vector3.new(0.1, 2.9, 0.1), x, H - 2.5, SPINE, BLACK)
		MapKit.light(lamp, rgb(255, 240, 215), 30, 0.9)
	end

	data.Cells = {}
	local doors = {}
	-- two rows of cells: along the front wall (bars facing +z) and the back
	-- wall (bars facing -z). Ground floor cells are real; the upper tier is
	-- a row of barred cells above them, along a catwalk.
	for row, spec in ipairs({ { Back = z0, Bars = z0 + CELL_D, Out = 1 }, { Back = z1, Bars = z1 - CELL_D, Out = -1 } }) do
		local zBars, out = spec.Bars, spec.Out
		local zMid = (spec.Back + zBars) / 2
		for k = 0, 7 do
			local cx0, cx1 = x0 + k * CELL_W, x0 + (k + 1) * CELL_W
			local cx = (cx0 + cx1) / 2
			-- the wall between this cell and the next (both tiers)
			if k < 7 then
				solid("CellWall", Vector3.new(0.8, TIER * 2 - 1, CELL_D), cx1, 0, zMid, CONCRETE, Enum.Material.Concrete)
			end
			local d0, d1 = cx0 + 1.2, cx0 + 4.2 -- the door gap
			bars(cx0, cx1, zBars, 0, TIER - 1, d0, d1)
			local door = slidingDoor(d0, d1, zBars + out * 0.35, TIER - 1, 3.2)
			table.insert(doors, door)
			-- inside: a bunk bed along the side wall, a toilet and a sink, a
			-- shelf and a little desk
			local bx = cx1 - 2.2
			local bz = zMid - out * 0.2
			local lowTop, highTop = 2.2, 6.4
			deco("BunkFrame", Vector3.new(3.4, 0.4, 7.4), bx, lowTop - 0.6, bz, STEEL, Enum.Material.Metal)
			deco("BunkFrame", Vector3.new(3.4, 0.4, 7.4), bx, highTop - 0.6, bz, STEEL, Enum.Material.Metal)
			for _, px in ipairs({ -1.6, 1.6 }) do
				for _, pz in ipairs({ -3.6, 3.6 }) do
					deco("BunkPost", Vector3.new(0.25, highTop + 0.8, 0.25), bx + px, 0, bz + pz, STEEL, Enum.Material.Metal)
				end
			end
			local sheet = ({ rgb(220, 222, 214), rgb(180, 190, 200), rgb(200, 190, 170) })[rng:NextInteger(1, 3)]
			deco("Mattress", Vector3.new(3, 0.4, 7), bx, lowTop - 0.2, bz, sheet, Enum.Material.Fabric)
			deco("Mattress", Vector3.new(3, 0.4, 7), bx, highTop - 0.2, bz, sheet, Enum.Material.Fabric)
			for _, top in ipairs({ lowTop, highTop }) do
				deco("Pillow", Vector3.new(2.2, 0.4, 1.2), bx, top + 0.2, bz + out * -2.9, WHITE, Enum.Material.Fabric)
			end
			deco("BunkLadder", Vector3.new(0.2, highTop, 1.4), bx - 1.8, 0, bz + out * 2.4, STEEL, Enum.Material.Metal)
			local tx = cx0 + 1.4
			local tz = spec.Back + out * 1.4
			deco("CellToilet", Vector3.new(1.6, 1.6, 1.8), tx + 0.4, 0, tz, rgb(200, 204, 210), Enum.Material.Metal)
			deco("CellSink", Vector3.new(1.4, 0.7, 1.1), tx + 2.6, 2.6, spec.Back + out * 0.55, rgb(200, 204, 210), Enum.Material.Metal)
			deco("CellShelf", Vector3.new(3, 0.25, 1), cx - 0.8, 5, spec.Back + out * 0.6, rgb(120, 100, 80), Enum.Material.Wood)
			for n = 0, 2 do
				deco("ShelfBook", Vector3.new(0.4, 1.1, 0.8), cx - 1.8 + n * 0.5, 5.25, spec.Back + out * 0.6, MapKit.FLOWERS[(k + n + row) % #MapKit.FLOWERS + 1]:Lerp(BLACK, 0.3))
			end
			deco("CellDesk", Vector3.new(2.4, 0.2, 1.4), cx - 1, 2.6, spec.Back + out * 3.4, rgb(120, 100, 80), Enum.Material.Wood)
			deco("DeskLeg", Vector3.new(0.2, 2.6, 1.2), cx - 2.1, 0, spec.Back + out * 3.4, STEEL, Enum.Material.Metal)
			local stool = MapKit.seat(model, "CellStool", Vector3.new(1.2, 0.35, 1.2), cf(cx - 1, 1.75, spec.Back + out * 5), STEEL, Enum.Material.Metal, nil)
			stool.CanCollide = false
			deco("StoolLeg", Vector3.new(0.3, 1.6, 0.3), cx - 1, 0, spec.Back + out * 5, STEEL, Enum.Material.Metal)
			local lamp = deco("CellLamp", Vector3.new(1.4, 0.3, 1.4), cx, TIER - 1.3, zMid, rgb(255, 240, 210), Enum.Material.Neon)
			MapKit.light(lamp, rgb(255, 235, 205), 12, 0.5)
			-- where people sleep, sit and stand in here (the bunks lie along z)
			local head = bz + out * -2.9
			local foot = bz + out * 2.9
			local number = (row - 1) * 8 + k + 1
			local cell = {
				Id = number,
				Row = row,
				Center = pos(cx - 1.5, 0, zMid),
				LocalCenter = Vector3.new(cx - 1.5, 0, zMid),
				Bounds = { cx0 + 0.4, cx1 - 0.4, math.min(spec.Back, zBars) + 0.3, math.max(spec.Back, zBars) - 0.3 },
				DoorIn = Vector3.new((d0 + d1) / 2, 0, zBars - out * 1.6),
				DoorOut = Vector3.new((d0 + d1) / 2, 0, zBars + out * 2.4),
				Door = door,
				Bunks = {
					spotAt(bx, (head + foot) / 2, bx, foot, { BedTop = G + lowTop }),
					spotAt(bx, (head + foot) / 2, bx, foot, { BedTop = G + highTop }),
				},
				-- sitting on the edge of the bottom bunk (hips a little above the mattress)
				Seat = spotAt(bx - 1.2, bz, bx - 6, bz, { Raise = lowTop + 0.55 - 1.9 }),
				Stand = spotAt(cx - 2.5, zMid + out * 1.5, cx - 2.5, zBars),
				Desk = spotAt(cx - 1, spec.Back + out * 5, cx - 1, spec.Back, { Seat = stool }),
			}
			local plate = deco("CellNumber", Vector3.new(1.6, 0.9, 0.1), cx1 - 1.6, TIER - 2.3, zBars + out * 0.3, rgb(30, 34, 40))
			MapKit.signText(plate, if out > 0 then Enum.NormalId.Back else Enum.NormalId.Front, "A-" .. string.format("%02d", number), WHITE, Enum.Font.GothamBold)
			table.insert(data.Cells, cell)
			-- the upper tier: a cell floor (the ceiling below), bars along the catwalk
			bars(cx0, cx1, zBars, TIER, TIER - 1)
		end
		-- the upper tier's floor and the catwalk in front of it, with a railing
		solid("TierFloor", Vector3.new(x1 - x0, 1, CELL_D + 3.4), (x0 + x1) / 2, TIER - 1, zMid + out * 1.7, DARK_CONCRETE, Enum.Material.Concrete)
		local edge = zBars + out * 3.2
		deco("CatwalkRail", Vector3.new(x1 - x0, 0.3, 0.3), (x0 + x1) / 2, TIER + 3.2, edge, STEEL, Enum.Material.Metal)
		local mesh = deco("CatwalkMesh", Vector3.new(x1 - x0, 3.2, 0.1), (x0 + x1) / 2, TIER, edge, STEEL, Enum.Material.DiamondPlate)
		mesh.Transparency = 0.55
		for x = x0 + 4, x1 - 2, 8 do
			deco("CatwalkPost", Vector3.new(0.3, 3.4, 0.3), x, TIER, edge, STEEL, Enum.Material.Metal)
		end
	end
	data.Doors = doors

	-- the mess hall in the middle: steel tables and stools, a serving counter
	data.MessSeats = {}
	for _, tx in ipairs({ -59.5, -35.5, -11.5 }) do
		for _, tz in ipairs({ SPINE - 9, SPINE + 9 }) do
			deco("MessTable", Vector3.new(3, 0.3, 6.4), tx, 2.6, tz, rgb(170, 174, 180), Enum.Material.Metal)
			deco("MessTableLeg", Vector3.new(0.6, 2.6, 0.6), tx, 0, tz, STEEL, Enum.Material.Metal)
			for _, sx in ipairs({ -1, 1 }) do
				for _, dz in ipairs({ -2, 0, 2 }) do
					local seat = MapKit.seat(model, "MessStool", Vector3.new(1.3, 0.35, 1.3), cf(tx + sx * 2.3, 1.75, tz + dz), rgb(90, 96, 104), Enum.Material.Metal, nil)
					seat.CanCollide = false
					deco("StoolLeg", Vector3.new(0.3, 1.6, 0.3), tx + sx * 2.3, 0, tz + dz, STEEL, Enum.Material.Metal)
					local s = spotAt(tx + sx * 2.3, tz + dz, tx, tz + dz, { Seat = seat })
					s.Tray = pos(tx + sx * 0.9, 2.9, tz + dz)
					table.insert(data.MessSeats, s)
				end
			end
		end
	end
	-- the serving line along the west wall
	solid("ServingCounter", Vector3.new(3, 3.2, 16), x0 + 2.5, 0, SPINE, rgb(170, 174, 180), Enum.Material.Metal)
	deco("SneezeGuard", Vector3.new(0.2, 1.6, 15), x0 + 3.8, 3.2, SPINE, rgb(200, 220, 230), Enum.Material.Glass).Transparency = 0.5
	for n = -3, 3 do
		deco("FoodTray", Vector3.new(2, 0.3, 1.8), x0 + 2.5, 3.2, SPINE + n * 2.1, ({ rgb(210, 180, 110), rgb(160, 110, 70), rgb(120, 170, 90), rgb(230, 220, 190) })[(n + 3) % 4 + 1], Enum.Material.SmoothPlastic)
	end
	data.Cook = spotAt(x0 + 1, SPINE, x0 + 5, SPINE)
	-- the TV lounge by the serving line: a TV on the wall, plastic chairs
	local tv = deco("PrisonTV", Vector3.new(0.3, 3.4, 5.6), x0 + 0.3, 6.5, SPINE + 11, rgb(20, 20, 24))
	local screen = MapKit.deco(model, "PrisonTVScreen", Vector3.new(0.05, 3, 5.1), tv.CFrame * CFrame.new(0.2, 0, 0), rgb(110, 170, 210), Enum.Material.Neon)
	screen.Transparency = 0.15
	data.TVSeats = {}
	for n = 0, 3 do
		local x, z = x0 + 9, SPINE + 8.5 + n * 1.8
		local seat = MapKit.seat(model, "LoungeChair", Vector3.new(1.6, 0.35, 1.6), cf(x, 1.75, z), rgb(60, 110, 170), Enum.Material.SmoothPlastic, nil)
		seat.CanCollide = false
		deco("ChairBack", Vector3.new(0.3, 1.6, 1.6), x + 0.7, 1.9, z, rgb(60, 110, 170))
		for _, lx in ipairs({ -0.6, 0.6 }) do
			for _, lz in ipairs({ -0.6, 0.6 }) do
				deco("ChairLeg", Vector3.new(0.2, 1.65, 0.2), x + lx, 0, z + lz, STEEL)
			end
		end
		table.insert(data.TVSeats, spotAt(x, z, x0, z, { Seat = seat }))
	end
	-- the guard desk by the yard door
	deco("GuardDesk", Vector3.new(3, 3, 6), x1 - 5, 0, SPINE - 11, rgb(90, 80, 70), Enum.Material.Wood)
	deco("DeskMonitor", Vector3.new(0.3, 1.2, 1.8), x1 - 5, 3, SPINE - 11, rgb(30, 30, 34))
	data.DeskGuard = spotAt(x1 - 2.2, SPINE - 11, x1 - 10, SPINE - 11)
	-- places to mop the floor
	data.MopSpots = {}
	for x = x0 + 14, x1 - 10, 14 do
		table.insert(data.MopSpots, spotAt(x, SPINE + rng:NextNumber(-3, 3), x + 3, SPINE))
	end
	-- where guards walk the hall
	data.HallPatrol = { Vector3.new(x0 + 8, 0, SPINE), Vector3.new(x1 - 8, 0, SPINE) }
end

--------------------------------------------------------------------------------
-- The yard
--------------------------------------------------------------------------------
local function hoop(hcf)
	MapKit.deco(model, "HoopPost", Vector3.new(0.6, 10, 0.6), hcf * CFrame.new(0, 5, 0), rgb(50, 50, 55), Enum.Material.Metal)
	MapKit.deco(model, "Backboard", Vector3.new(6, 4, 0.3), hcf * CFrame.new(0, 10, -0.5), WHITE)
	MapKit.cylinder(model, "Hoop", 0.3, 2.4, hcf * CFrame.new(0, 9, -1.8) * CFrame.Angles(0, 0, math.rad(90)), rgb(240, 90, 30), Enum.Material.Metal)
	return (hcf * CFrame.new(0, 9, -1.8)).Position
end

local function yard(data, rng)
	-- dirt and worn grass under everything, a track around the edge
	deco("YardGround", Vector3.new(58, 0.08, Prison.D - 6), 53, 0, 0, rgb(150, 134, 108), Enum.Material.Ground)
	data.Yard = { Min = Vector3.new(26, 0, -Prison.D / 2 + 4), Max = Vector3.new(Prison.W / 2 - 4, 0, Prison.D / 2 - 4) }
	data.Laps = { Vector3.new(30, 0, -28), Vector3.new(78, 0, -28), Vector3.new(78, 0, 66), Vector3.new(30, 0, 66) }
	for k = 1, 4 do
		local a, b = data.Laps[k], data.Laps[k % 4 + 1]
		local mid, len = (a + b) / 2, (b - a).Magnitude
		local size = if math.abs(a.X - b.X) > 1 then Vector3.new(len + 3, 0.1, 3) else Vector3.new(3, 0.1, len + 3)
		deco("Track", size, mid.X, 0.02, mid.Z, rgb(170, 90, 70), Enum.Material.Concrete)
	end
	-- the basketball court
	local court = cf(48, 0, -50)
	MapKit.part(model, "YardCourt", Vector3.new(24, 0.15, 30), court * CFrame.new(0, 0.1, 0), rgb(96, 100, 108), Enum.Material.Concrete)
	MapKit.deco(model, "CourtLine", Vector3.new(24, 0.16, 0.3), court * CFrame.new(0, 0.12, 0), WHITE)
	data.Hoops = {}
	for _, sz in ipairs({ -1, 1 }) do
		local hcf = court * CFrame.new(0, 0, sz * 14) * CFrame.Angles(0, if sz > 0 then 0 else math.pi, 0)
		local rim = hoop(hcf)
		for k = -1, 1 do
			local s = spotAt(48 + k * 4, -50 + sz * 7, 48, -50 + sz * 14, { Hoop = rim })
			table.insert(data.Hoops, s)
		end
	end
	-- the weight pit: rubber mats, benches, a dumbbell rack, a squat rack, a pull-up bar
	deco("WeightMat", Vector3.new(14, 0.2, 30), 73, 0, -48, rgb(40, 40, 44), Enum.Material.Rubber)
	data.Weights = {}
	for n = 0, 2 do
		local z = -58 + n * 8
		deco("WeightBench", Vector3.new(1.4, 1.6, 4), 70, 0.2, z, rgb(30, 30, 34), Enum.Material.Fabric)
		deco("BenchRack", Vector3.new(3, 3.2, 0.3), 70, 0.2, z - 2, STEEL, Enum.Material.Metal)
		MapKit.cylinder(model, "Barbell", 6, 0.25, cf(70, 3.2, z - 1.8), rgb(180, 180, 186), Enum.Material.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			MapKit.cylinder(model, "Plate", 0.4, 2.2, cf(70 + sx * 2.6, 3.2, z - 1.8), BLACK, Enum.Material.Rubber)
		end
		table.insert(data.Weights, spotAt(72.5, z, 68, z, { Action = "lift" }))
	end
	deco("DumbbellRack", Vector3.new(1.4, 2.4, 8), 78, 0.2, -40, STEEL, Enum.Material.Metal)
	for n = 0, 4 do
		MapKit.cylinder(model, "Dumbbell", 1.3, 0.6, cf(78, 2.9, -43.5 + n * 1.8) * CFrame.Angles(0, math.rad(90), 0), rgb(60, 60, 66), Enum.Material.Metal)
	end
	table.insert(data.Weights, spotAt(75.5, -40, 79, -40, { Action = "lift" }))
	table.insert(data.Weights, spotAt(75.5, -36, 79, -36, { Action = "lift" }))
	deco("SquatRack", Vector3.new(4, 7, 0.4), 74, 0.2, -30, STEEL, Enum.Material.Metal)
	table.insert(data.Weights, spotAt(74, -32, 74, -40, { Action = "squat" }))
	for _, sx in ipairs({ -1, 1 }) do
		deco("PullupPost", Vector3.new(0.4, 8, 0.4), 64 + sx * 3, 0, -33, STEEL, Enum.Material.Metal)
	end
	MapKit.cylinder(model, "PullupBar", 6, 0.3, cf(64, 8, -33), STEEL, Enum.Material.Metal)
	table.insert(data.Weights, spotAt(64, -34.5, 64, -30, { Action = "stretch" }))
	-- picnic tables (for cards, chess and talking)
	data.Tables = {}
	for _, tx in ipairs({ 36, 52, 68 }) do
		for _, tz in ipairs({ 36, 54 }) do
			deco("PicnicTable", Vector3.new(4, 0.4, 8), tx, 2.6, tz, rgb(120, 110, 96), Enum.Material.Concrete)
			deco("PicnicLeg", Vector3.new(1, 2.6, 5), tx, 0, tz, rgb(110, 100, 90), Enum.Material.Concrete)
			for _, sx in ipairs({ -1, 1 }) do
				local seat = MapKit.seat(model, "PicnicBench", Vector3.new(1.4, 0.4, 7.4), cf(tx + sx * 2.8, 1.6, tz), rgb(110, 100, 90), Enum.Material.Concrete, nil)
				seat.CanCollide = false
				for _, lz in ipairs({ -2.6, 2.6 }) do
					deco("BenchLeg", Vector3.new(0.5, 1.5, 0.8), tx + sx * 2.8, 0, tz + lz, rgb(110, 100, 90), Enum.Material.Concrete)
				end
				for _, dz in ipairs({ -2, 1.5 }) do
					table.insert(data.Tables, spotAt(tx + sx * 2.8, tz + dz, tx, tz + dz, { Seat = seat }))
				end
			end
		end
	end
	-- the open middle: somewhere to hang out, lean on the wall, stretch, do pushups
	data.Hangout = {}
	for n = 1, 10 do
		local x, z = rng:NextNumber(32, 76), rng:NextNumber(-22, 22)
		table.insert(data.Hangout, spotAt(x, z, x + rng:NextNumber(-5, 5), z + rng:NextNumber(-5, 5)))
	end
	for n = 0, 5 do
		local z = -24 + n * 9
		table.insert(data.Hangout, spotAt(Prison.W / 2 - 1.6, z, 40, z, { Lean = true }))
	end
	data.Sweep = {}
	for n = 1, 5 do
		table.insert(data.Sweep, spotAt(rng:NextNumber(32, 76), rng:NextNumber(-28, 28), 50, 0))
	end
	data.YardPatrol = { Vector3.new(34, 0, -26), Vector3.new(76, 0, -26), Vector3.new(76, 0, 26), Vector3.new(34, 0, 26) }
	-- a few lights for the yard at night
	for _, p in ipairs({ { 30, -30 }, { 30, 30 }, { 80, 0 } }) do
		deco("YardLightPole", Vector3.new(0.6, 16, 0.6), p[1], 0, p[2], STEEL, Enum.Material.Metal)
		local head = deco("YardLight", Vector3.new(2.6, 0.8, 1.6), p[1], 16, p[2], rgb(255, 245, 220), Enum.Material.Neon)
		local l = MapKit.spot(head, Enum.NormalId.Bottom, rgb(255, 240, 215), 60, 120, 1.6)
		l.Enabled = false
		table.insert(MapKit.Registry.Lamps, { Head = head, Light = l })
	end
end

--------------------------------------------------------------------------------
-- Out front: administration, parking, the prison bus, and Prison Road
--------------------------------------------------------------------------------
local function frontOffice(data)
	local hd = Prison.D / 2
	solid("AdminBuilding", Vector3.new(44, 16, 22), -52, 0, -hd + 16, rgb(206, 200, 188), Enum.Material.Brick)
	deco("AdminRoof", Vector3.new(46, 1, 24), -52, 16, -hd + 16, DARK_CONCRETE, Enum.Material.Concrete)
	for x = -70, -34, 6 do
		for _, y in ipairs({ 3, 10 }) do
			deco("AdminWindow", Vector3.new(3.6, 3.4, 0.2), x, y, -hd + 4.9, rgb(150, 190, 210), Enum.Material.Glass).Transparency = 0.2
		end
	end
	local sign = deco("AdminSign", Vector3.new(20, 2.4, 0.3), -52, 13.4, -hd + 4.8, rgb(30, 34, 40))
	MapKit.signText(sign, Enum.NormalId.Front, "ADMINISTRATION · VISITORS", WHITE, Enum.Font.GothamBold)
	-- a flag
	deco("FlagPole", Vector3.new(0.4, 22, 0.4), -24, 0, -hd + 8, rgb(200, 200, 205), Enum.Material.Metal)
	deco("Flag", Vector3.new(0.1, 3, 5), -24, 18.4, -hd + 10.6, rgb(60, 110, 200))
	-- visitor parking and the prison bus, outside the wall by the gate
	deco("Parking", Vector3.new(44, 0.08, 22), 44, 0, -hd - 18, rgb(70, 72, 78), Enum.Material.Asphalt)
	for n = 0, 4 do
		deco("ParkingLine", Vector3.new(0.3, 0.09, 8), 26 + n * 8, 0, -hd - 11, WHITE)
	end
	Streets.car(model, cf(30, 0, -hd - 11) * CFrame.Angles(0, math.pi, 0), rgb(40, 60, 140))
	Streets.car(model, cf(46, 0, -hd - 11) * CFrame.Angles(0, math.pi, 0), rgb(150, 150, 156))
	local bus = cf(44, 0, -hd - 24) * CFrame.Angles(0, math.rad(90), 0)
	MapKit.part(model, "PrisonBus", Vector3.new(7, 7, 30), bus * CFrame.new(0, 4.6, 0), rgb(236, 236, 230), Enum.Material.SmoothPlastic)
	local stripe = MapKit.deco(model, "BusStripe", Vector3.new(7.1, 1.2, 30.1), bus * CFrame.new(0, 3.4, 0), rgb(40, 60, 110))
	MapKit.signText(stripe, Enum.NormalId.Left, "DEPARTMENT OF CORRECTIONS", WHITE, Enum.Font.GothamBold)
	MapKit.signText(stripe, Enum.NormalId.Right, "DEPARTMENT OF CORRECTIONS", WHITE, Enum.Font.GothamBold)
	for _, sx in ipairs({ -1, 1 }) do
		MapKit.deco(model, "BusWindows", Vector3.new(0.1, 2, 26), bus * CFrame.new(sx * 3.52, 6, 0), rgb(40, 50, 60), Enum.Material.Glass)
		for _, sz in ipairs({ -1, 1 }) do
			MapKit.cylinder(model, "Wheel", 1, 3, bus * CFrame.new(sx * 3.3, 1.5, sz * 10), rgb(22, 22, 25), Enum.Material.Rubber)
		end
	end
	-- Prison Road: from the city's east edge to the gate
	local gate = pos(0, 0, -hd - 10)
	local edge = Vector3.new(MapKit.EXTENT + 18, 0, gate.Z)
	local len = (gate - edge).Magnitude + 6
	local mid = (gate + edge) / 2
	MapKit.part(model, "PrisonRoad", Vector3.new(len, 0.3, 16), CFrame.new(mid.X, 0.05, mid.Z), MapKit.ASPHALT, Enum.Material.Asphalt)
	for d = 6, len - 6, 11 do
		MapKit.deco(model, "LaneDash", Vector3.new(6, 0.32, 0.35), CFrame.new(edge.X + d, 0.06, mid.Z), rgb(245, 205, 70))
	end
	local post = MapKit.deco(model, "RoadSignPost", Vector3.new(0.4, 8, 0.4), CFrame.new(edge.X + 6, 4, mid.Z - 10), rgb(60, 64, 70), Enum.Material.Metal)
	local rs = MapKit.deco(model, "RoadSign", Vector3.new(0.2, 2.2, 9), post.CFrame * CFrame.new(0, 3, 0), rgb(30, 110, 60))
	MapKit.signText(rs, Enum.NormalId.Left, "STATE PRISON ➜", WHITE, Enum.Font.GothamBold)
	MapKit.signText(rs, Enum.NormalId.Right, "⬅ AI CITY", WHITE, Enum.Font.GothamBold)
	data.Road = { From = edge, To = gate }
	data.Release = gate + Vector3.new(-4, 0, 4)
end

function Prison.build(parent, rng)
	model = Instance.new("Model")
	model.Name = "StatePrison"
	model.Parent = parent
	local data = { Model = model, F = F, G = G, Spine = SPINE, BlockX = { BLOCK_X0, BLOCK_X1 } }
	-- the compound sits on a concrete slab
	MapKit.part(model, "PrisonGround", Vector3.new(Prison.W + 16, 1, Prison.D + 40), F * CFrame.new(0, G - 0.5, -12), rgb(140, 140, 136), Enum.Material.Concrete)
	perimeter(data)
	cellBlock(data, rng)
	yard(data, rng)
	frontOffice(data)
	-- walking lanes between the areas (local coordinates; see PrisonService)
	data.Lanes = {
		HallEast = Vector3.new(BLOCK_X1 - 6, 0, SPINE),
		DoorOut = Vector3.new(BLOCK_X1 + 6, 0, SPINE),
		YardHub = Vector3.new(34, 0, SPINE - 20),
	}
	data.Center = Prison.CENTER
	data.Radius = 110
	data.Local = function(p)
		return F:PointToObjectSpace(p) - Vector3.new(0, G, 0)
	end
	data.World = function(v)
		return pos(v.X, v.Y, v.Z)
	end
	MapKit.tag(model, "Prison")
	return data
end

return Prison
