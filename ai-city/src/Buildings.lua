-- Buildings (ModuleScript) — ServerScriptService.Modules.Buildings
-- Building shells: walls with a walk-in doorway and glass doors, framed
-- windows (or glass curtain walls for towers), storefront windows, striped
-- awnings, real floors on every storey with ceiling lights, an elevator for
-- tall buildings, rooftop equipment, and several styles of house.
-- Furniture comes from the Interiors module.

local MapKit = require(script.Parent:WaitForChild("MapKit"))

local Buildings = {}

local part, deco, wedge, column = MapKit.part, MapKit.deco, MapKit.wedge, MapKit.column
local FLOOR_H = MapKit.FLOOR_H
local WHITE, BLACK = MapKit.WHITE, MapKit.BLACK
local Registry = MapKit.Registry

local function window(model, at, x, y, z, sideways, frameColor, glassColor, w, h)
	w, h = w or 4, h or 5
	local size = if sideways then Vector3.new(0.3, h, w) else Vector3.new(w, h, 0.3)
	local frameSize = if sideways then Vector3.new(0.24, h + 0.6, w + 0.6) else Vector3.new(w + 0.6, h + 0.6, 0.24)
	deco(model, "WindowFrame", frameSize, at(x, y, z), frameColor)
	local glass = deco(model, "Window", size, at(x + (if sideways then (if x > 0 then 0.06 else -0.06) else 0), y, z + (if sideways then 0 else -0.06)), glassColor, Enum.Material.Glass, { Transparency = 0.2, Reflectance = 0.18 })
	glass:SetAttribute("DayColor", glassColor)
	table.insert(Registry.Windows, glass)
	return glass
end

-- A building shell.
-- spec: Name, Label, Center (ground point of the building's middle), Face
-- (direction the front faces), W, D, Floors, Wall, Trim, Material, Roof
-- ("flat"/"gable"), RoofColor, RoofKit ({ "ac", "tower", "garden", "solar",
-- "antenna", "helipad" }), Awning ({ colorA, colorB }), DoorW, WindowColor,
-- Storefront, CurtainWall (glass towers), NoSign, SignColor, SignText,
-- Elevator (default: on for 3+ floors), Plinth
function Buildings.shell(parent, spec)
	local model = Instance.new("Model")
	model.Name = spec.Name
	model.Parent = parent
	local W, D = spec.W, spec.D
	local floors = spec.Floors or 1
	local H = floors * FLOOR_H
	local cf = CFrame.lookAt(spec.Center, spec.Center + spec.Face) -- local -Z = front
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local wall = spec.Wall
	local trim = spec.Trim or wall:Lerp(BLACK, 0.3)
	local mat = spec.Material or Enum.Material.SmoothPlastic
	local glassColor = spec.WindowColor or MapKit.GLASS
	local DW = spec.DoorW or 8
	local DH = math.min(10, H - 1.5)
	local b = { Model = model, CFrame = cf, At = at, W = W, D = D, H = H, Floors = floors, Spec = spec }

	-- ground floor slab and a plinth around the base
	part(model, "Floor", Vector3.new(W, 0.4, D), at(0, 0.2, 0), spec.FloorColor or MapKit.rgb(206, 196, 180), spec.FloorMaterial or Enum.Material.WoodPlanks)
	if spec.Plinth ~= false then
		deco(model, "Plinth", Vector3.new(W + 0.4, 1.2, D + 0.4), at(0, 0.6, 0), trim:Lerp(BLACK, 0.2), Enum.Material.Concrete)
	end

	if spec.CurtainWall then
		-- glass tower: glass walls, a spandrel band on every floor and mullions
		local frame = trim
		for f = 0, floors - 1 do
			local y0 = f * FLOOR_H
			local gy = y0 + FLOOR_H / 2 + 0.4
			local gh = FLOOR_H - 1.6
			for _, side in ipairs({ { 0, D / 2, W, false }, { -W / 2, 0, D, true }, { W / 2, 0, D, true }, { 0, -D / 2, W, false } }) do
				local x, z, len, sideways = side[1], side[2], side[3], side[4]
				local isFront = z < 0 and not sideways
				if not (isFront and f == 0) then
					local size = if sideways then Vector3.new(0.5, gh, len - 0.4) else Vector3.new(len - 0.4, gh, 0.5)
					local g = part(model, "Glass", size, at(x, gy, z), glassColor, Enum.Material.Glass, { Transparency = 0.25, Reflectance = 0.25 })
					g:SetAttribute("DayColor", glassColor)
					table.insert(Registry.Windows, g)
				end
				local band = if sideways then Vector3.new(0.9, 1.6, len + 0.3) else Vector3.new(len + 0.3, 1.6, 0.9)
				part(model, "Spandrel", band, at(x, y0 + FLOOR_H - 0.3, z), frame, Enum.Material.Metal)
			end
			if f == 0 then
				-- lobby front: glass either side of the doors, solid lower band
				local side = (W - DW) / 2
				for _, sx in ipairs({ -1, 1 }) do
					local g = part(model, "Glass", Vector3.new(side - 0.4, gh, 0.5), at(sx * (DW / 2 + side / 2), gy, -D / 2), glassColor, Enum.Material.Glass, { Transparency = 0.25, Reflectance = 0.25 })
					g:SetAttribute("DayColor", glassColor)
					table.insert(Registry.Windows, g)
				end
				part(model, "Wall", Vector3.new(DW, FLOOR_H - DH - 1, 0.6), at(0, DH + (FLOOR_H - DH - 1) / 2, -D / 2), frame, Enum.Material.Metal)
			end
		end
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				part(model, "Corner", Vector3.new(1.2, H, 1.2), at(sx * W / 2, H / 2, sz * D / 2), frame, Enum.Material.Metal)
			end
		end
		-- vertical mullions on the front and back
		for _, sz in ipairs({ -1, 1 }) do
			local x = -W / 2 + 6
			while x < W / 2 - 3 do
				if not (sz < 0 and math.abs(x) < DW / 2 + 1) then
					deco(model, "Mullion", Vector3.new(0.35, H, 0.7), at(x, H / 2, sz * D / 2), frame, Enum.Material.Metal)
				else
					deco(model, "Mullion", Vector3.new(0.35, H - FLOOR_H, 0.7), at(x, FLOOR_H + (H - FLOOR_H) / 2, sz * D / 2), frame, Enum.Material.Metal)
				end
				x += 6
			end
		end
	else
		-- solid walls with a walk-in doorway on the front
		part(model, "Wall", Vector3.new(W, H, 1), at(0, H / 2, D / 2 - 0.5), wall, mat)
		part(model, "Wall", Vector3.new(1, H, D), at(-W / 2 + 0.5, H / 2, 0), wall, mat)
		part(model, "Wall", Vector3.new(1, H, D), at(W / 2 - 0.5, H / 2, 0), wall, mat)
		local side = (W - DW) / 2
		part(model, "Wall", Vector3.new(side, H, 1), at(-(DW / 2 + side / 2), H / 2, -D / 2 + 0.5), wall, mat)
		part(model, "Wall", Vector3.new(side, H, 1), at(DW / 2 + side / 2, H / 2, -D / 2 + 0.5), wall, mat)
		part(model, "Wall", Vector3.new(DW, H - DH, 1), at(0, DH + (H - DH) / 2, -D / 2 + 0.5), wall, mat)
		-- corner pilasters and a band between floors
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				deco(model, "Pilaster", Vector3.new(1.4, H, 1.4), at(sx * (W / 2 - 0.3), H / 2, sz * (D / 2 - 0.3)), trim)
			end
		end
		for f = 1, floors do
			deco(model, "Band", Vector3.new(W + 0.6, 0.7, D + 0.6), at(0, f * FLOOR_H - 0.35, 0), trim)
		end
		-- windows: storefront glass on the ground floor front, framed windows elsewhere
		for f = 0, floors - 1 do
			local y = f * FLOOR_H + 6.5
			if f == 0 and spec.Storefront then
				local sideW = (W - DW) / 2 - 2
				for _, sx in ipairs({ -1, 1 }) do
					local x = sx * (DW / 2 + 1 + sideW / 2)
					window(model, at, x, 4.4, -D / 2 - 0.1, false, trim, glassColor, sideW - 0.6, 6.4)
					deco(model, "DisplayLedge", Vector3.new(sideW - 0.6, 1, 2), at(x, 1.1, -D / 2 + 1.4), MapKit.rgb(240, 236, 228))
				end
			else
				local x = -W / 2 + 5
				while x <= W / 2 - 4.5 do
					if f > 0 or math.abs(x) > DW / 2 + 3 then
						window(model, at, x, y, -D / 2 - 0.1, false, trim, glassColor)
						deco(model, "Sill", Vector3.new(4.8, 0.4, 0.9), at(x, y - 2.9, -D / 2 - 0.35), trim)
					end
					x += 8
				end
			end
			for _, sx in ipairs({ -1, 1 }) do
				local z = -D / 2 + 6
				while z <= D / 2 - 5 do
					window(model, at, sx * (W / 2 + 0.1), y, z, true, trim, glassColor)
					z += 8
				end
			end
		end
	end

	-- glass doors slid open, a step, a mat and a lamp by the door
	for _, sx in ipairs({ -1, 1 }) do
		deco(model, "DoorFrame", Vector3.new(0.7, DH, 1.6), at(sx * (DW / 2 + 0.2), DH / 2, -D / 2 + 0.5), trim:Lerp(BLACK, 0.2))
		local door = deco(model, "GlassDoor", Vector3.new(DW / 2 - 0.4, DH - 0.6, 0.2), at(sx * (DW / 2 + DW / 4 - 0.6), DH / 2, -D / 2 + 1.25), glassColor:Lerp(WHITE, 0.2), Enum.Material.Glass, { Transparency = 0.35 })
		door.Name = "GlassDoor"
		deco(model, "DoorHandle", Vector3.new(0.2, 1.6, 0.3), at(sx * (DW / 2 + 0.3), DH / 2, -D / 2 + 1.1), MapKit.rgb(200, 200, 205), Enum.Material.Metal)
	end
	deco(model, "DoorFrame", Vector3.new(DW + 1.4, 0.8, 1.6), at(0, DH, -D / 2 + 0.5), trim:Lerp(BLACK, 0.2))
	part(model, "Step", Vector3.new(DW + 2, 0.4, 2.4), at(0, 0.2, -D / 2 - 1.2), MapKit.rgb(190, 186, 178), Enum.Material.Concrete)
	deco(model, "DoorMat", Vector3.new(DW - 1, 0.06, 2), at(0, 0.43, -D / 2 - 1.2), MapKit.rgb(120, 60, 50), Enum.Material.Fabric)
	if not spec.CurtainWall then
		for _, sx in ipairs({ -1, 1 }) do
			local sconce = deco(model, "WallLamp", Vector3.new(0.7, 1.2, 0.7), at(sx * (DW / 2 + 1.6), DH - 1.5, -D / 2 - 0.4), MapKit.rgb(255, 230, 180), Enum.Material.Glass)
			MapKit.nightNeon(sconce)
			MapKit.nightLight(sconce, MapKit.LAMP_LIGHT, 10, 0.8)
		end
	end

	-- floors above the ground floor, and a ceiling light on every floor
	b.FloorY = {}
	for f = 0, floors - 1 do
		local y = f * FLOOR_H
		b.FloorY[f + 1] = y
		if f > 0 then
			part(model, "FloorSlab", Vector3.new(W - 1.6, 0.6, D - 1.6), at(0, y + 0.1, 0), spec.FloorColor or MapKit.rgb(200, 192, 178), spec.FloorMaterial or Enum.Material.WoodPlanks)
		end
		local lampY = y + FLOOR_H - 0.9
		local panel = deco(model, "CeilingLight", Vector3.new(math.min(8, W / 3), 0.2, math.min(3, D / 5)), at(0, lampY, 0), MapKit.rgb(255, 250, 235), Enum.Material.Neon)
		MapKit.light(panel, MapKit.rgb(255, 238, 210), math.min(26, math.max(W, D) * 0.6), 0.75)
	end
	-- ceiling above the top floor (so the room has a lid under the roof)
	part(model, "Ceiling", Vector3.new(W - 1.6, 0.4, D - 1.6), at(0, H - 0.2, 0), MapKit.rgb(236, 232, 224), Enum.Material.SmoothPlastic)

	-- roof
	local roofColor = spec.RoofColor or wall:Lerp(BLACK, 0.45)
	if spec.Roof == "gable" then
		local rise = math.min(8, D * 0.45)
		wedge(model, "Roof", Vector3.new(W + 2, rise, D / 2 + 1), at(0, H + rise / 2, -D / 4 - 0.5), roofColor, Enum.Material.Slate, true)
		wedge(model, "Roof", Vector3.new(W + 2, rise, D / 2 + 1), at(0, H + rise / 2, D / 4 + 0.5) * CFrame.Angles(0, math.pi, 0), roofColor, Enum.Material.Slate, true)
		deco(model, "RoofRidge", Vector3.new(W + 2.2, 0.5, 0.8), at(0, H + rise + 0.1, 0), roofColor:Lerp(BLACK, 0.25))
		-- gable ends
		for _, sx in ipairs({ -1, 1 }) do
			wedge(model, "Gable", Vector3.new(0.6, rise, D / 2), at(sx * (W / 2 - 0.3), H + rise / 2, -D / 4), wall, mat)
			wedge(model, "Gable", Vector3.new(0.6, rise, D / 2), at(sx * (W / 2 - 0.3), H + rise / 2, D / 4) * CFrame.Angles(0, math.pi, 0), wall, mat)
		end
	else
		part(model, "Roof", Vector3.new(W + 1, 1, D + 1), at(0, H + 0.5, 0), roofColor, Enum.Material.Concrete)
		for _, e in ipairs({ { 0, -D / 2, W + 1.4, 0.8 }, { 0, D / 2, W + 1.4, 0.8 }, { -W / 2, 0, 0.8, D + 1.4 }, { W / 2, 0, 0.8, D + 1.4 } }) do
			deco(model, "Parapet", Vector3.new(e[3], 1.4, e[4]), at(e[1], H + 1.4, e[2]), trim)
		end
		local kit = spec.RoofKit or (if W >= 20 then { "ac" } else {})
		for _, item in ipairs(kit) do
			if item == "ac" then
				for k = 0, (if W > 40 then 2 else 1) do
					local u = deco(model, "AirCon", Vector3.new(4, 2.6, 4), at(-W / 4 + k * 7, H + 2.3, D / 5), MapKit.rgb(186, 190, 196), Enum.Material.Metal)
					MapKit.cylinder(model, "Fan", 0.3, 3, u.CFrame * CFrame.new(0, 1.35, 0) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(60, 64, 70), Enum.Material.Metal)
				end
			elseif item == "tower" then
				-- a water tower on legs
				local base = at(W / 4, H + 1, -D / 5)
				for _, lx in ipairs({ -1.6, 1.6 }) do
					for _, lz in ipairs({ -1.6, 1.6 }) do
						deco(model, "TowerLeg", Vector3.new(0.4, 6, 0.4), base * CFrame.new(lx, 3, lz), MapKit.DARK_WOOD, Enum.Material.Wood)
					end
				end
				column(model, "WaterTank", 6, 5.4, (base * CFrame.new(0, 9, 0)).Position, MapKit.rgb(140, 100, 70), Enum.Material.WoodPlanks, false)
				local cone = wedge(model, "TankRoof", Vector3.new(5.6, 2, 2.8), base * CFrame.new(0, 13, -1.4), MapKit.rgb(70, 60, 55), Enum.Material.Metal)
				wedge(model, "TankRoof", Vector3.new(5.6, 2, 2.8), base * CFrame.new(0, 13, 1.4) * CFrame.Angles(0, math.pi, 0), cone.Color, Enum.Material.Metal)
			elseif item == "garden" then
				for k = 0, 3 do
					local p = at(-W / 3 + (k % 2) * (W / 3), H + 1.4, -D / 4 + (k // 2) * (D / 3))
					deco(model, "Planter", Vector3.new(6, 1, 3), p, MapKit.rgb(120, 86, 60), Enum.Material.Wood)
					deco(model, "Plants", Vector3.new(5.6, 0.8, 2.6), p * CFrame.new(0, 0.8, 0), MapKit.LEAVES[k % #MapKit.LEAVES + 1], Enum.Material.Grass)
				end
			elseif item == "solar" then
				for k = 0, 3 do
					deco(model, "SolarPanel", Vector3.new(5, 0.2, 3), at(-W / 3 + k * 5.5, H + 2, D / 4) * CFrame.Angles(math.rad(-25), 0, 0), MapKit.rgb(30, 50, 110), Enum.Material.Glass)
				end
			elseif item == "antenna" then
				deco(model, "Antenna", Vector3.new(0.5, 14, 0.5), at(W / 4, H + 8, D / 4), MapKit.rgb(200, 200, 205), Enum.Material.Metal)
				local tip = deco(model, "AntennaLight", Vector3.new(1, 1, 1), at(W / 4, H + 15.4, D / 4), MapKit.rgb(255, 50, 50), Enum.Material.Neon)
				tip.Shape = Enum.PartType.Ball
			elseif item == "helipad" then
				MapKit.disc(model, "Helipad", 0.4, math.min(W, D) * 0.6, at(0, H + 1.2, 0).Position, MapKit.rgb(64, 68, 74), Enum.Material.Concrete)
				local hLetter = deco(model, "HelipadH", Vector3.new(6, 0.1, 8), at(0, H + 1.45, 0), MapKit.rgb(64, 68, 74))
				MapKit.signText(hLetter, Enum.NormalId.Top, "H", WHITE)
			end
		end
		if floors >= 3 then
			-- stair hut on the roof
			part(model, "RoofHut", Vector3.new(6, 5, 6), at(-W / 2 + 5, H + 3.5, D / 2 - 5), trim, Enum.Material.Concrete)
		end
	end

	-- awning over the door (striped) and the sign
	if spec.Awning then
		local width = if spec.Storefront then W - 3 else math.min(W - 2, DW + 8)
		MapKit.awning(model, width, 4, at(0, DH + 1.3, -D / 2 - 2), spec.Awning[1], spec.Awning[2] or WHITE)
	end
	if spec.Label and not spec.NoSign then
		-- clean lettering (emoji look like smudges when blown up on a sign)
		local text = string.upper((spec.Label:gsub("^[^%w]+%s*", "")))
		local signW = math.min(W - 3, math.max(16, #text * 1.9))
		local signY = if spec.Awning then math.min(DH + 4.4, H - 1.5) else math.min(DH + 3.2, H - 1.5)
		local board = deco(model, "SignBoard", Vector3.new(signW + 0.8, 4.4, 0.4), at(0, signY, -D / 2 - 0.3), spec.SignTrim or MapKit.GOLD, Enum.Material.Metal)
		MapKit.nightNeon(board)
		local sign = deco(model, "Sign", Vector3.new(signW, 3.6, 0.6), at(0, signY, -D / 2 - 0.5), spec.SignColor or MapKit.rgb(40, 36, 50))
		MapKit.signText(sign, Enum.NormalId.Front, text, spec.SignText or WHITE)
		b.Sign = sign
	end

	-- stairs (small buildings with 2 floors): a real staircase along the left wall
	if spec.Stairs and floors >= 2 then
		b.Elevator = { Floors = {}, Stairs = true }
		for f = 0, floors - 2 do
			local y = f * FLOOR_H
			for s = 0, 11 do
				part(model, "Stair", Vector3.new(3, 1, 1.2), at(-W / 2 + 2.6, y + 0.9 + s * 1, D / 2 - 2.2 - s * 1.05), MapKit.rgb(150, 110, 75), Enum.Material.WoodPlanks)
			end
			deco(model, "Banister", Vector3.new(0.3, 0.3, 13), at(-W / 2 + 4.2, y + 7.4, D / 2 - 8) * CFrame.Angles(math.rad(-43), 0, 0), MapKit.rgb(110, 80, 55), Enum.Material.Wood)
		end
		for f = 0, floors - 1 do
			local marker = deco(model, "StairLanding", Vector3.new(3, 0.1, 2), at(-W / 2 + 2.6, f * FLOOR_H + 0.45, D / 2 - 1.6), MapKit.rgb(150, 110, 75))
			MapKit.tag(marker, "ElevatorDoor")
			marker:SetAttribute("Floor", f + 1)
			marker:SetAttribute("Floors", floors)
			marker:SetAttribute("Stairs", true)
			b.Elevator.Floors[f + 1] = { Door = marker, Exit = at(-W / 2 + 2.6, f * FLOOR_H + 0.6, D / 2 - 4).Position }
		end
	-- an elevator in the back corner for buildings with 3+ floors
	elseif (spec.Elevator == nil and floors >= 3) or spec.Elevator == true then
		local ex, ez = W / 2 - 4.5, D / 2 - 4.5
		b.Elevator = { Floors = {} }
		for f = 0, floors - 1 do
			local y = f * FLOOR_H
			deco(model, "ElevatorShaft", Vector3.new(6, FLOOR_H - 0.8, 0.4), at(ex, y + FLOOR_H / 2, ez - 3), MapKit.rgb(90, 96, 106), Enum.Material.Metal)
			local doors = part(model, "ElevatorDoor", Vector3.new(4, 8, 0.3), at(ex, y + 4.4, ez - 3.25), MapKit.rgb(190, 196, 206), Enum.Material.Metal)
			doors.CanCollide = false
			local display = deco(model, "ElevatorDisplay", Vector3.new(1.6, 0.8, 0.2), at(ex, y + 9.2, ez - 3.35), MapKit.rgb(20, 20, 24))
			MapKit.signText(display, Enum.NormalId.Front, tostring(f + 1), MapKit.rgb(255, 170, 60), Enum.Font.Code)
			MapKit.tag(doors, "ElevatorDoor")
			doors:SetAttribute("Floor", f + 1)
			doors:SetAttribute("Floors", floors)
			b.Elevator.Floors[f + 1] = { Door = doors, Exit = at(ex, y + 0.6, ez - 6).Position }
		end
	end

	-- where people stand: the door outside, the middle inside (ground floor)
	b.Door = at(0, 0, -D / 2 - 3).Position
	b.Inside = at(0, 0.4, 0).Position
	return b
end

--------------------------------------------------------------------------------
-- Houses: four styles
--------------------------------------------------------------------------------
local HOUSE_WALLS = { MapKit.rgb(240, 222, 186), MapKit.rgb(190, 214, 234), MapKit.rgb(236, 192, 180), MapKit.rgb(200, 224, 190), MapKit.rgb(246, 244, 234), MapKit.rgb(226, 202, 230), MapKit.rgb(214, 176, 140), MapKit.rgb(170, 190, 170) }
local HOUSE_ROOFS = { MapKit.rgb(150, 60, 50), MapKit.rgb(70, 80, 100), MapKit.rgb(110, 75, 55), MapKit.rgb(60, 104, 80), MapKit.rgb(60, 60, 66) }
local SHUTTERS = { MapKit.rgb(60, 90, 70), MapKit.rgb(70, 90, 140), MapKit.rgb(140, 50, 50), MapKit.rgb(60, 60, 66), MapKit.rgb(230, 230, 225) }

-- style: "cottage", "twostory", "modern", "bungalow"
function Buildings.house(parent, center, face, style, rng, garageSide)
	local wall = HOUSE_WALLS[rng:NextInteger(1, #HOUSE_WALLS)]
	local roof = HOUSE_ROOFS[rng:NextInteger(1, #HOUSE_ROOFS)]
	local shutter = SHUTTERS[rng:NextInteger(1, #SHUTTERS)]
	local spec = { Name = "House", Center = center, Face = face, W = 20, D = 16, Floors = 1, Wall = wall, Trim = WHITE, Roof = "gable", RoofColor = roof, DoorW = 5, Material = Enum.Material.WoodPlanks, Elevator = false, Plinth = true }
	if style == "twostory" then
		spec.Floors, spec.W, spec.D = 2, 22, 16
		spec.Stairs = true
		spec.Material = Enum.Material.Brick
		spec.Wall = wall:Lerp(MapKit.rgb(170, 90, 70), 0.35)
	elseif style == "modern" then
		spec.Roof, spec.W, spec.D, spec.Floors = "flat", 24, 16, 2
		spec.Stairs = true
		spec.Material = Enum.Material.SmoothPlastic
		spec.Wall = ({ MapKit.rgb(244, 244, 240), MapKit.rgb(60, 62, 70), MapKit.rgb(214, 208, 196) })[rng:NextInteger(1, 3)]
		spec.Trim = MapKit.rgb(40, 40, 46)
		spec.RoofKit = { "solar" }
		spec.WindowColor = MapKit.rgb(170, 210, 235)
	elseif style == "bungalow" then
		spec.W, spec.D = 26, 16
	end
	local b = Buildings.shell(parent, spec)
	local at = b.At
	local W, D, H = b.W, b.D, b.H
	-- shutters beside the front windows (not on modern houses)
	if style ~= "modern" then
		for f = 0, spec.Floors - 1 do
			local x = -W / 2 + 5
			while x <= W / 2 - 4.5 do
				if f > 0 or math.abs(x) > spec.DoorW / 2 + 3 then
					for _, sx in ipairs({ -1, 1 }) do
						deco(b.Model, "Shutter", Vector3.new(1.4, 5.4, 0.2), at(x + sx * 3, f * FLOOR_H + 6.5, -D / 2 - 0.25), shutter)
					end
					-- flower box under the window
					deco(b.Model, "FlowerBox", Vector3.new(4.4, 0.8, 1), at(x, f * FLOOR_H + 3.4, -D / 2 - 0.7), MapKit.WOOD, Enum.Material.Wood)
					for n = 0, 2 do
						MapKit.ball(b.Model, "Flower", 0.9, at(x - 1.4 + n * 1.4, f * FLOOR_H + 4.1, -D / 2 - 0.7), MapKit.FLOWERS[rng:NextInteger(1, #MapKit.FLOWERS)])
					end
				end
				x += 8
			end
		end
	end
	-- porch with posts and a little roof (cottage and bungalow)
	if style == "cottage" or style == "bungalow" then
		part(b.Model, "Porch", Vector3.new(12, 0.8, 5), at(0, 0.4, -D / 2 - 2.5), MapKit.rgb(170, 130, 90), Enum.Material.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			deco(b.Model, "PorchPost", Vector3.new(0.6, 8, 0.6), at(sx * 5.6, 4.4, -D / 2 - 4.6), WHITE, Enum.Material.Wood)
		end
		wedge(b.Model, "PorchRoof", Vector3.new(13, 1.6, 5.4), at(0, 9.2, -D / 2 - 2.6), spec.RoofColor, Enum.Material.Slate)
		local porchLight = deco(b.Model, "PorchLight", Vector3.new(0.8, 0.8, 0.8), at(0, 8, -D / 2 - 2.5), MapKit.rgb(255, 230, 180), Enum.Material.Glass)
		MapKit.nightNeon(porchLight)
		MapKit.nightLight(porchLight, MapKit.LAMP_LIGHT, 14, 0.9)
		-- a rocking chair on the porch
		MapKit.seat(b.Model, "PorchChair", Vector3.new(2.2, 0.6, 2.2), at(-4, 1.6, -D / 2 - 2.8), MapKit.WOOD, Enum.Material.Wood)
	end
	-- chimney
	if spec.Roof == "gable" then
		deco(b.Model, "Chimney", Vector3.new(2, 7, 2), at(W / 2 - 4, H + 4.5, 3), MapKit.rgb(150, 80, 60), Enum.Material.Brick)
		deco(b.Model, "ChimneyCap", Vector3.new(2.6, 0.5, 2.6), at(W / 2 - 4, H + 8.2, 3), MapKit.rgb(90, 60, 50), Enum.Material.Brick)
	end
	-- a garage with a driveway on two-story houses
	if style == "twostory" then
		-- garageSide keeps the garage on the side away from the nearest road
		local gx = (garageSide or 1) * (W / 2 + 5.5)
		part(b.Model, "Garage", Vector3.new(10, 9, 14), at(gx, 4.5, 1), wall:Lerp(WHITE, 0.2), Enum.Material.Brick)
		deco(b.Model, "GarageDoor", Vector3.new(8, 7, 0.3), at(gx, 3.5, -6.1), MapKit.rgb(236, 236, 236), Enum.Material.DiamondPlate)
		wedge(b.Model, "GarageRoof", Vector3.new(11, 2, 7.5), at(gx, 10, -2.7), spec.RoofColor, Enum.Material.Slate)
		wedge(b.Model, "GarageRoof", Vector3.new(11, 2, 7.5), at(gx, 10, 4.7) * CFrame.Angles(0, math.pi, 0), spec.RoofColor, Enum.Material.Slate)
		deco(b.Model, "Driveway", Vector3.new(9, 0.12, 12), at(gx, 0.1, -12), MapKit.rgb(150, 148, 144), Enum.Material.Concrete)
	end
	b.Style = style
	return b
end

return Buildings
