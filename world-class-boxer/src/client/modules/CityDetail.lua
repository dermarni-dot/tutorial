-- CityDetail: Main Street's and the campus's extra detail layer (client-only; WorldDetail streams it per block
-- by Graphics level and camera distance). Reads the server city (workspace.Gym.City) for where the shops are,
-- how tall and how their window grids run, so the dressing always lines up with the buildings it decorates.
-- Street furniture keeps off the pedestrian lanes (z 166.3 / 184.6, CityVisuals), the traffic lanes, the
-- parked cars and the crosswalks; none of it collides (DetailKit defaults), so walking and driving are as before.
--   tier 1  granite curbs and gutters, manhole covers, the corner traffic signals and street-name blades
--   tier 2  benches, bins, hydrants, parking meters, planters, bike racks, newspaper boxes, storm drains,
--           A-frame boards, shop sign goose-neck lamps (they glow at night: NightLens), parapets, window sills and
--           lintels, striped awning valances, the cafe's fire escape, parking wheel stops, the gym's gutter
--   tier 3  window piers, door handles, downspouts, rooftop vents, sidewalk cracks and stains
local DetailKit = require(script.Parent:WaitForChild("DetailKit"))

local K = DetailKit
local V3, CF, A, RAD = K.V3, K.CF, K.A, K.RAD
local M, FACE, C, rgb = K.M, K.FACE, K.C, K.rgb
local Part, Cyl, VCyl, Rod, Ball = K.Part, K.Cyl, K.VCyl, K.Rod, K.Ball

local CityDetail = {}

local SW_H = 0.5 -- sidewalk top
local ROAD_Y = 0.3
local FRONT_Z = 187 -- shop fronts (south side of Main Street)
local N_CURB, S_CURB = 167, 183
local GRANITE = rgb(150, 148, 144)
local GUTTER = rgb(46, 46, 50)
local POLE = rgb(40, 44, 50)
local SLIGHTS = { -236, -34, 153 } -- the street lights on the shop side (CityMap)

local function cityRoot()
	local g = workspace:FindFirstChild("Gym")
	return g and g:FindFirstChild("City")
end

local function tagged(p, tag)
	pcall(function()
		p:AddTag(tag)
	end)
	return p
end

------------------------------------------------------------------------
-- templates
------------------------------------------------------------------------
-- a park bench facing local -Z (slats, back, cast-iron ends)
local BENCH = K.Template("StreetBench", function(t)
	for k = 0, 2 do
		Part(t, "BenchSlat", V3(5.4, 0.16, 0.42), CF(0, 1.5, -0.5 + k * 0.48), rgb(130, 90, 56), M.Wood)
	end
	for k = 0, 1 do
		Part(t, "BenchBack", V3(5.4, 0.42, 0.14), CF(0, 2.15 + k * 0.55, 0.78) * A(RAD(-12), 0, 0), rgb(130, 90, 56), M.Wood)
	end
	for _, x in ipairs({ -2.4, 2.4 }) do
		Part(t, "BenchEnd", V3(0.22, 1.5, 1.6), CF(x, 0.75, 0), POLE, M.Metal)
		Part(t, "BenchArm", V3(0.24, 0.16, 1.4), CF(x, 2.0, -0.1), POLE, M.Metal)
		Part(t, "BenchBackPost", V3(0.2, 1.3, 0.16), CF(x, 2.3, 0.82) * A(RAD(-12), 0, 0), POLE, M.Metal)
	end
end)

-- a city trash bin (body, lid, liner rim, a sticker)
local BIN = K.Template("StreetBin", function(t)
	VCyl(t, "BinBody", 3.0, 1.7, V3(0, 0, 0), rgb(36, 70, 52), M.Metal)
	VCyl(t, "BinBand", 0.3, 1.76, V3(0, 2.2, 0), C.gold, M.Metal)
	VCyl(t, "BinLid", 0.35, 1.9, V3(0, 3.0, 0), rgb(30, 60, 44), M.Metal)
	VCyl(t, "BinTop", 0.3, 1.0, V3(0, 3.35, 0), rgb(30, 60, 44), M.Metal)
	Part(t, "BinSlot", V3(0.9, 0.35, 0.1), CF(0, 2.75, -0.92), C.ink, M.SmoothPlastic)
end)

-- a fire hydrant (barrel, bonnet, two side caps, chain)
local HYDRANT = K.Template("Hydrant", function(t)
	VCyl(t, "HydrantFlange", 0.25, 1.2, V3(0, 0, 0), rgb(190, 30, 30), M.Metal)
	VCyl(t, "HydrantBarrel", 1.8, 0.8, V3(0, 0.25, 0), rgb(200, 34, 34), M.Metal)
	Ball(t, "HydrantBonnet", 0.86, CF(0, 2.1, 0), rgb(200, 34, 34), M.Metal)
	VCyl(t, "HydrantNut", 0.25, 0.3, V3(0, 2.4, 0), C.chrome, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		Part(t, "HydrantCap", V3(0.4, 0.46, 0.46), CF(s * 0.55, 1.45, 0), C.chrome, M.Metal, { shape = "Cylinder" })
	end
	Part(t, "HydrantPumper", V3(0.5, 0.6, 0.6), CF(0, 1.3, -0.5) * A(0, math.pi / 2, 0), C.chrome, M.Metal, { shape = "Cylinder" })
end)

-- a parking meter (post, head, dial window)
local METER = K.Template("ParkingMeter", function(t)
	VCyl(t, "MeterPost", 3.4, 0.22, V3(0, 0, 0), POLE, M.Metal)
	Part(t, "MeterHead", V3(0.7, 1.0, 0.55), CF(0, 3.85, 0), rgb(120, 124, 132), M.Metal)
	Ball(t, "MeterDome", V3(0.72, 0.5, 0.56), CF(0, 4.35, 0), rgb(120, 124, 132), M.Metal)
	Part(t, "MeterWindow", V3(0.45, 0.35, 0.04), CF(0, 4.0, -0.29), rgb(190, 214, 230), M.Glass)
	Part(t, "MeterFlag", V3(0.2, 0.12, 0.04), CF(0.08, 4.0, -0.31), C.red, M.SmoothPlastic)
end)

-- a concrete planter with a shrub
local PLANTER = K.Template("Planter", function(t)
	Part(t, "PlanterBox", V3(3.0, 1.4, 1.6), CF(0, 0.7, 0), rgb(176, 172, 164), M.Concrete)
	Part(t, "PlanterSoil", V3(2.7, 0.1, 1.3), CF(0, 1.36, 0), rgb(70, 52, 36), M.Ground)
	Ball(t, "Shrub", V3(2.8, 1.6, 1.5), CF(0, 2.0, 0), rgb(60, 120, 60), M.Grass)
	Ball(t, "Shrub", V3(1.4, 1.1, 1.1), CF(0.7, 2.6, 0.1), rgb(70, 135, 64), M.Grass)
end)

-- a newspaper box (WCB DAILY), facing local -Z
local NEWSBOX = K.Template("NewsBox", function(t)
	Part(t, "NewsBody", V3(1.6, 2.6, 1.4), CF(0, 1.6, 0), rgb(30, 80, 170), M.Metal)
	Part(t, "NewsLeg", V3(1.2, 0.3, 1.1), CF(0, 0.15, 0), POLE, M.Metal)
	local w = Part(t, "NewsWindow", V3(1.2, 1.0, 0.05), CF(0, 2.0, -0.71), rgb(220, 226, 230), M.Glass)
	local sg = K.Gui(w, FACE.Front, 60, 1)
	K.Frame(sg, { BackgroundColor3 = C.paper })
	K.Text(sg, "WCB DAILY", { TextColor3 = C.ink, Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.05) })
	K.Text(sg, "TITLE FIGHT\nSATURDAY", { TextColor3 = C.redDeep, Face = "signSub", Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.42) })
	Part(t, "NewsHandle", V3(0.6, 0.12, 0.1), CF(0, 1.35, -0.74), C.chrome, M.Metal)
end)

-- an inverted-U bike rack
local BIKERACK = K.Template("BikeRack", function(t)
	for k = 0, 2 do
		local x = -1.6 + k * 1.6
		Rod(t, "RackLeg", V3(x, 0, -0.6), V3(x, 2.4, -0.6), 0.16, C.steelLight, M.Metal)
		Rod(t, "RackLeg", V3(x, 0, 0.6), V3(x, 2.4, 0.6), 0.16, C.steelLight, M.Metal)
		Rod(t, "RackTop", V3(x, 2.4, -0.6), V3(x, 2.4, 0.6), 0.16, C.steelLight, M.Metal)
	end
end)

-- a bicycle leaning in a rack (along local X)
local BIKE = K.Template("Bike", function(t)
	for _, x in ipairs({ -1.1, 1.1 }) do
		Part(t, "BikeWheel", V3(0.12, 1.5, 1.5), CF(x, 0.75, 0), C.ink, M.Rubber, { shape = "Cylinder" })
		Part(t, "BikeRim", V3(0.14, 1.1, 1.1), CF(x, 0.75, 0), C.steelLight, M.Metal, { shape = "Cylinder", t = 0.5 })
	end
	local frameCol = C.red
	Rod(t, "BikeFrame", V3(-1.1, 0.75, 0), V3(0, 0.8, 0), 0.1, frameCol, M.Metal)
	Rod(t, "BikeFrame", V3(0, 0.8, 0), V3(0.8, 1.55, 0), 0.1, frameCol, M.Metal)
	Rod(t, "BikeFrame", V3(-0.4, 1.55, 0), V3(0.8, 1.55, 0), 0.1, frameCol, M.Metal)
	Rod(t, "BikeFrame", V3(-1.1, 0.75, 0), V3(-0.4, 1.55, 0), 0.1, frameCol, M.Metal)
	Rod(t, "BikeFork", V3(0.8, 1.55, 0), V3(1.1, 0.75, 0), 0.1, C.steelLight, M.Metal)
	Part(t, "BikeSeat", V3(0.6, 0.12, 0.25), CF(-0.45, 1.75, 0), C.ink, M.Leather)
	Part(t, "BikeBars", V3(0.12, 0.12, 1.0), CF(0.85, 1.95, 0), C.ink, M.Metal)
end)

-- a string of WCB pennants across the street between two points
local function pennants(m, a, b, n)
	local sag = V3(0, -1.2, 0)
	local mid = (a + b) / 2 + sag
	Rod(m, "PennantLine", a, mid, 0.05, C.ink, M.Fabric)
	Rod(m, "PennantLine", mid, b, 0.05, C.ink, M.Fabric)
	local cols = { C.red, C.gold, C.white, C.ink }
	for k = 1, n do
		local f = k / (n + 1)
		local p = f < 0.5 and a:Lerp(mid, f * 2) or mid:Lerp(b, (f - 0.5) * 2)
		local dir = (b - a).Unit
		local cf = CFrame.lookAt(p, p + V3(dir.Z, 0, -dir.X)) * CF(0, -0.55, 0)
		K.Wedge(m, "Pennant", V3(0.05, 1.0, 0.9), cf * A(math.pi, 0, 0), cols[k % #cols + 1], M.Fabric, { shadow = false })
	end
end

-- a rooftop water tank on legs
local function waterTank(m, x, y, z)
	for _, o in ipairs({ { -1.4, -1.4 }, { 1.4, -1.4 }, { 1.4, 1.4 }, { -1.4, 1.4 } }) do
		Rod(m, "TankLeg", V3(x + o[1], y, z + o[2]), V3(x + o[1] * 0.8, y + 3, z + o[2] * 0.8), 0.25, C.steelDark, M.Metal)
	end
	VCyl(m, "WoodTank", 4.2, 4.0, V3(x, y + 3, z), rgb(120, 86, 58), M.WoodPlanks)
	for k = 0, 2 do
		VCyl(m, "TankHoop", 0.12, 4.08, V3(x, y + 3.6 + k * 1.4, z), C.steelDark, M.Metal)
	end
	Part(m, "TankRoof", V3(4.2, 1.4, 4.2), CF(x, y + 7.8, z) * A(0, RAD(45), 0), rgb(70, 60, 50), M.Wood, { class = "Part" })
end

-- a traffic signal controller cabinet
local function cabinet(m, x, z)
	Part(m, "SignalCabinet", V3(1.8, 3.2, 1.2), CF(x, SW_H + 1.6, z), rgb(150, 156, 150), M.Metal)
	Part(m, "CabinetBase", V3(2.0, 0.3, 1.4), CF(x, SW_H + 0.15, z), C.concrete, M.Concrete, { shadow = false })
	Part(m, "CabinetVent", V3(1.2, 0.5, 0.04), CF(x, SW_H + 2.7, z - 0.62), rgb(90, 96, 90), M.DiamondPlate, { shadow = false })
end

-- an A-frame chalkboard (faces local -Z)
local function aFrame(m, cf, text)
	local front = Part(m, "BoardFront", V3(1.6, 2.4, 0.1), cf * CF(0, 1.2, -0.3) * A(RAD(10), 0, 0), C.ink2, M.Wood)
	Part(m, "BoardBack", V3(1.6, 2.4, 0.1), cf * CF(0, 1.2, 0.3) * A(RAD(-10), 0, 0), C.ink2, M.Wood)
	local sg = K.Gui(front, FACE.Front, 40, 1)
	K.Text(sg, text, { TextColor3 = C.white, Face = "marker", Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1) })
end

------------------------------------------------------------------------
-- streets
------------------------------------------------------------------------
-- a granite curb strip and the dark gutter beside it along X (z = the curb line, side = +1 when the road is +Z)
local function curbX(m, x1, x2, z, side)
	Part(m, "Curb", V3(x2 - x1, 0.34, 0.5), CF((x1 + x2) / 2, SW_H - 0.15, z - side * 0.25 + side * 0.01), GRANITE, M.Granite, { shadow = false })
	Part(m, "Gutter", V3(x2 - x1, 0.03, 1.2), CF((x1 + x2) / 2, ROAD_Y + 0.016, z + side * 0.6), GUTTER, M.Asphalt, { shadow = false })
end

local function curbZ(m, z1, z2, x, side)
	Part(m, "Curb", V3(0.3, 0.34, z2 - z1), CF(x - side * 0.15 + side * 0.01, SW_H - 0.15, (z1 + z2) / 2), GRANITE, M.Granite, { shadow = false })
	Part(m, "Gutter", V3(1.2, 0.03, z2 - z1), CF(x + side * 0.6, ROAD_Y + 0.016, (z1 + z2) / 2), GUTTER, M.Asphalt, { shadow = false })
end

local function manhole(m, x, z)
	local p = K.Patch(m, "Manhole", 2.6, 2.6, CF(x, ROAD_Y, z), "manhole")
	if not p then
		VCyl(m, "ManholeCover", 0.03, 2.4, V3(x, ROAD_Y + 0.005, z), rgb(70, 70, 72), M.DiamondPlate, { shadow = false })
	end
end

-- a traffic signal: pole at base, mast arm reaching `reach` along dir over the road, heads facing `face`
local function signal(m, base, dir, reach, face, streetName)
	VCyl(m, "SignalPole", 15.5, 0.6, base, POLE, M.Metal)
	VCyl(m, "SignalFoot", 0.5, 1.2, base, POLE, M.Metal)
	local armY = base.Y + 14.8
	local tip = V3(base.X, armY, base.Z) + dir * reach
	Rod(m, "SignalArm", V3(base.X, armY, base.Z), tip, 0.36, POLE, M.Metal)
	Rod(m, "SignalBrace", V3(base.X, armY - 2, base.Z), V3(base.X, armY, base.Z) + dir * 4, 0.16, POLE, M.Metal)
	for _, f in ipairs({ 0.62, 0.98 }) do
		local at = V3(base.X, armY, base.Z):Lerp(tip, f) - V3(0, 2.0, 0)
		local cf = CFrame.lookAt(at, at + face)
		Part(m, "SignalHead", V3(1.1, 3.2, 0.9), cf, rgb(40, 40, 34), M.Metal)
		Part(m, "SignalBack", V3(1.5, 3.6, 0.1), cf * CF(0, 0, 0.5), C.black, M.SmoothPlastic)
		Rod(m, "SignalHanger", at + V3(0, 1.6, 0), at + V3(0, 2.0, 0), 0.12, POLE, M.Metal)
		local lamps = { { 1.0, rgb(90, 20, 20), M.SmoothPlastic }, { 0, rgb(90, 70, 20), M.SmoothPlastic }, { -1.0, rgb(60, 255, 120), M.Neon } }
		for _, l in ipairs(lamps) do
			Part(m, "SignalLens", V3(0.06, 0.72, 0.72), cf * CF(0, l[1], -0.47) * A(0, math.pi / 2, 0), l[2], l[3], { shape = "Cylinder" })
			Part(m, "SignalVisor", V3(0.86, 0.1, 0.5), cf * CF(0, l[1] + 0.42, -0.7), rgb(40, 40, 34), M.Metal)
		end
	end
	-- the walk signal facing along the crosswalk, and the street-name blade
	local ped = CFrame.lookAt(base + V3(0, 8.4, 0) - face * 0.5, base + V3(0, 8.4, 0) - face * 2)
	Part(m, "WalkSignal", V3(1.1, 1.1, 0.6), ped, rgb(40, 40, 34), M.Metal)
	Part(m, "WalkLens", V3(0.8, 0.8, 0.04), ped * CF(0, 0, -0.32), rgb(230, 230, 220), M.Neon, { t = 0.2 })
	if streetName then
		local blade = Part(m, "StreetBlade", V3(5.2, 0.9, 0.1), CFrame.lookAt(base + V3(0, 13.2, 0), base + V3(0, 13.2, 0) + face) * CF(1.8, 0, 0), rgb(30, 110, 60), M.SmoothPlastic)
		K.Sign(blade, FACE.Front, streetName, C.white, rgb(30, 110, 60), 40, "signSub")
		K.Sign(blade, FACE.Back, streetName, C.white, rgb(30, 110, 60), 40, "signSub")
	end
	-- a push button box
	Part(m, "WalkButton", V3(0.4, 0.6, 0.3), CFrame.lookAt(base + V3(0, 3.6, 0), base + V3(0, 3.6, 0) - face) * CF(0, 0, -0.42), C.gold, M.Metal)
end

local function storm(m, x)
	Part(m, "StormDrain", V3(2.4, 0.04, 0.9), CF(x, ROAD_Y + 0.02, S_CURB - 0.55), C.ink2, M.DiamondPlate, { shadow = false })
	Part(m, "CurbInlet", V3(2.4, 0.22, 0.06), CF(x, SW_H - 0.12, S_CURB - 0.02), C.ink, M.SmoothPlastic, { shadow = false })
end

------------------------------------------------------------------------
-- shop facades (read from the server city)
------------------------------------------------------------------------
-- every Main Street shop: { cx, w, h, depth, sign (part), building parts with a window grid }
local function readShops()
	local root = cityRoot()
	local ms = root and root:FindFirstChild("MainStreet")
	if not ms then
		return {}
	end
	local shops = {}
	for _, p in ipairs(ms:GetChildren()) do
		if p:IsA("BasePart") and p.Name == "ShopSign" then
			table.insert(shops, { cx = p.Position.X, w = p.Size.X + 3, sign = p, grids = {}, h = 14 })
		end
	end
	for _, p in ipairs(ms:GetChildren()) do
		if p:IsA("BasePart") then
			for _, s in ipairs(shops) do
				if math.abs(p.Position.X - s.cx) < 0.6 then
					if p.Name == "Cornice" then
						s.h = p.Position.Y - 0.45
						s.depth = p.Size.Z - 0.8
					elseif p.Name == "ShopAwning" then
						s.awning = p
					elseif p.Name == "ShopInterior" then
						s.facade = true
					elseif p.Name == "Marquee" then
						s.marquee = true

					elseif p:GetAttribute("WinRows") then
						table.insert(s.grids, p)
					end
				end
			end
		end
	end
	for _, p in ipairs(ms:GetChildren()) do
		local spanned = { ACUnit = "hasAC", Pediment = "columns", LobbyCanopy = "canopy", MuseumSteps = "columns" }
		if p:IsA("BasePart") and (spanned[p.Name] or p.Name == "ShopDoor" or p.Name == "DoorFrame") then
			for _, s in ipairs(shops) do
				if math.abs(p.Position.X - s.cx) < s.w / 2 then
					if spanned[p.Name] then
						s[spanned[p.Name]] = true
					else
						s.doorX = p.Position.X
					end
				end
			end
		end
	end
	table.sort(shops, function(a, b)
		return a.cx < b.cx
	end)
	return shops
end

-- sills and lintels under / over each window row of a grid part's front face (CityVisuals' row layout), or
-- (piers = true) the piers between the window columns
local function windowTrim(m, p, piers)
	local rows = tonumber(p:GetAttribute("WinRows")) or 0
	local cols = tonumber(p:GetAttribute("WinCols")) or 1
	local top = tonumber(p:GetAttribute("WinTop")) or 0
	local span = tonumber(p:GetAttribute("WinSpan")) or 1
	if rows < 1 or p:GetAttribute("WinFace") ~= "Front" then
		return
	end
	local s = p.Size
	local faceZ = p.Position.Z - s.Z / 2
	local topY = p.Position.Y + s.Y / 2
	local w = s.X
	for r = 0, rows - 1 do
		local ty = top + (r + 0.2) / rows * span
		local hh = span / rows * 0.6
		local y0 = topY - (ty + hh) * s.Y
		local y1 = topY - ty * s.Y
		if not piers then
			Part(m, "WindowSill", V3(w * 0.94, 0.28, 0.45), CF(p.Position.X, y0 - 0.12, faceZ - 0.2), rgb(200, 196, 186), M.Concrete, { shadow = false })
			Part(m, "WindowLintel", V3(w * 0.94, 0.4, 0.25), CF(p.Position.X, y1 + 0.22, faceZ - 0.1), rgb(180, 176, 168), M.Concrete, { shadow = false })
		else
			for c = 0, cols do
				local x = p.Position.X - w * 0.46 + c * (w * 0.92) / cols
				Part(m, "WindowPier", V3(0.35, y1 - y0 + 0.2, 0.18), CF(x, (y0 + y1) / 2, faceZ - 0.08), rgb(190, 186, 178), M.Concrete, { shadow = false })
			end
		end
	end
end

-- striped valance hanging from an awning's front edge
local function valance(m, aw, stripe)
	local cf = aw.CFrame * CF(0, -0.1, -aw.Size.Z / 2 - 0.02)
	local v = Part(m, "AwningValance", V3(aw.Size.X, 0.9, 0.06), CFrame.new(cf.Position - V3(0, 0.45, 0)) * aw.CFrame.Rotation * A(RAD(14), 0, 0), aw.Color, M.Fabric, { shadow = false })
	local sg = K.Gui(v, FACE.Front, 12, 1)
	local n = math.max(4, math.floor(aw.Size.X / 1.6))
	for k = 0, n - 1, 2 do
		K.Frame(sg, { BackgroundColor3 = stripe, Size = UDim2.fromScale(1 / n, 1), Position = UDim2.fromScale(k / n, 0) })
	end
	-- the scalloped edge: a darker band
	K.Frame(sg, { BackgroundColor3 = aw.Color:Lerp(Color3.new(0, 0, 0), 0.35), Size = UDim2.fromScale(1, 0.18), Position = UDim2.fromScale(0, 0.82) })
end

-- goose-neck lamps over a shop sign (their lenses glow at night through Ambience's NightLens)
local function signLamps(m, s)
	local sign = s.sign
	local y = sign.Position.Y + sign.Size.Y / 2 + 0.9
	local n = s.w > 30 and 3 or 2
	for k = 1, n do
		local x = s.cx - sign.Size.X / 2 + k * sign.Size.X / (n + 1)
		for _, lx in ipairs(SLIGHTS) do
			if math.abs(lx - x) < 2 then
				x += (x < lx and -2.4 or 2.4)
			end
		end
		local wallP = V3(x, y + 0.6, FRONT_Z - 0.05)
		Part(m, "LampPlate", V3(0.5, 0.5, 0.1), CF(wallP), POLE, M.Metal)
		Rod(m, "LampNeck", wallP, wallP + V3(0, 0.4, -1.4), 0.12, POLE, M.Metal)
		local head = CF(wallP + V3(0, 0.3, -1.6)) * A(RAD(-30), 0, 0)
		Part(m, "LampHood", V3(0.9, 0.35, 0.7), head, POLE, M.Metal)
		tagged(Part(m, "LampLens", V3(0.7, 0.06, 0.5), head * CF(0, -0.2, 0), rgb(200, 200, 196), M.SmoothPlastic, { shadow = false }), "NightLens")
	end
end

local function parapet(m, s)
	local depth = s.depth or 30
	Part(m, "Parapet", V3(s.w + 0.8, 1.4, 0.5), CF(s.cx, s.h + 0.9 + 0.7, FRONT_Z - 0.15), rgb(110, 106, 100), M.Concrete)
	Part(m, "ParapetCoping", V3(s.w + 1.2, 0.25, 0.8), CF(s.cx, s.h + 0.9 + 1.52, FRONT_Z - 0.15), rgb(196, 192, 184), M.Concrete, { shadow = false })
	local _ = depth
end

local function shopFine(m, s, rng)
	-- downspout at the east end, a rooftop vent, the door handle (doors at the server's DoorFrame / ShopDoor)
	local x = s.cx + s.w / 2 - 0.6
	if s.marquee then
		x = s.cx + s.w / 2 + 2.2
	end
	Rod(m, "Downspout", V3(x, s.h + 0.6, FRONT_Z - 0.35), V3(x, SW_H + 0.4, FRONT_Z - 0.35), 0.35, rgb(90, 92, 96), M.Metal)
	Part(m, "DownspoutShoe", V3(0.4, 0.3, 0.8), CF(x, SW_H + 0.3, FRONT_Z - 0.7), rgb(90, 92, 96), M.Metal)
	local vx = s.cx + rng:NextNumber(-s.w / 3, s.w / 3)
	VCyl(m, "RoofVent", 1.4, 0.8, V3(vx, s.h + 0.9, FRONT_Z + (s.depth or 30) * 0.35), C.steelLight, M.Metal)
	VCyl(m, "RoofVentCap", 0.3, 1.3, V3(vx, s.h + 2.3, FRONT_Z + (s.depth or 30) * 0.35), C.steelLight, M.Metal)
	for _ = 1, 2 do
		local cx = s.cx + rng:NextNumber(-s.w / 2 + 2, s.w / 2 - 2)
		K.Patch(m, "SidewalkCrack", 3, 3, CF(cx, SW_H, rng:NextNumber(183.8, 186.2)) * A(0, rng:NextNumber(0, 6.28), 0), "cracks", nil, 0.2)
	end
end

-- the cafe's iron fire escape (three landings, ladders between, rails)
local function fireEscape(m, s)
	local x0 = s.cx + s.w * 0.12
	for f = 1, 3 do
		local y = 14.5 + (f - 1) * 7
		Part(m, "EscapeLanding", V3(9, 0.2, 2.6), CF(x0, y, FRONT_Z - 1.4), rgb(34, 34, 38), M.DiamondPlate)
		Part(m, "EscapeRail", V3(9, 0.14, 0.14), CF(x0, y + 2.6, FRONT_Z - 2.65), rgb(34, 34, 38), M.Metal)
		for k = 0, 4 do
			Part(m, "EscapeBaluster", V3(0.1, 2.6, 0.1), CF(x0 - 4.4 + k * 2.2, y + 1.3, FRONT_Z - 2.65), rgb(34, 34, 38), M.Metal, { shadow = false })
		end
		for _, sx in ipairs({ -1, 1 }) do
			Part(m, "EscapeBracket", V3(0.16, 0.16, 2.6), CF(x0 + sx * 4.3, y - 0.6, FRONT_Z - 1.4) * A(RAD(-25), 0, 0), rgb(34, 34, 38), M.Metal, { shadow = false })
		end
		if f > 1 then
			Rod(m, "EscapeStair", V3(x0 - 3.6, y - 7, FRONT_Z - 1.6), V3(x0 + 2.4, y, FRONT_Z - 1.6), 0.2, rgb(34, 34, 38), M.Metal, { box = true, depth = 1.6 })
		end
	end
	-- the drop ladder from the first landing
	for _, sx in ipairs({ -0.6, 0.6 }) do
		Part(m, "LadderRail", V3(0.1, 4.4, 0.1), CF(x0 + 3.6 + sx, 14.5 - 2.2, FRONT_Z - 2.4), rgb(34, 34, 38), M.Metal, { shadow = false })
	end
	for k = 0, 4 do
		Part(m, "LadderRung", V3(1.2, 0.08, 0.08), CF(x0 + 3.6, 10.6 + k * 0.8, FRONT_Z - 2.4), rgb(34, 34, 38), M.Metal, { shadow = false })
	end
end

-- a concrete slab Texture over a sidewalk strip (an invisible overlay just above the slab)
local function sidewalkTiles(m, x1, x2, z1, z2)
	local p = Part(m, "SidewalkSlabs", V3(x2 - x1, 0.05, z2 - z1), CF((x1 + x2) / 2, SW_H + 0.012, (z1 + z2) / 2), C.black, M.SmoothPlastic, { t = 1, shadow = false })
	K.Texture(p, FACE.Top, "sidewalk", 8, 8, { Color3 = rgb(255, 252, 246) })
end

-- a WCB banner on a street light pole (arm towards the road, the cloth printed both sides)
local function poleBanner(m, x, z, dir)
	local base = V3(x, SW_H, z)
	for _, y in ipairs({ 8.2, 12.4 }) do
		Rod(m, "BannerArm", base + V3(0, y, 0), base + V3(0, y, 0) + dir * 1.9, 0.12, POLE, M.Metal)
		Ball(m, "BannerArmCap", 0.22, base + V3(0, y, 0) + dir * 1.95, C.gold, M.Metal)
	end
	local mid = base + V3(0, 10.3, 0) + dir * 1.05
	local cloth = Part(m, "PoleBanner", V3(0.05, 3.9, 1.5), CFrame.lookAt(mid, mid + dir) * A(0, math.pi / 2, 0), C.ink, M.Fabric, { shadow = false })
	local okR = K.Decal(cloth, FACE.Right, "bannerWCB")
	K.Decal(cloth, FACE.Left, "bannerWCB")
	if not okR then
		K.Sign(cloth, FACE.Right, "WCB", C.gold, C.ink, 20)
		K.Sign(cloth, FACE.Left, "WCB", C.gold, C.ink, 20)
	end
end

-- an iron tree grate round a sidewalk tree pit
local function treeGrate(m, x, z)
	for _, e in ipairs({ { 0, -1.3, 2.8, 0.2 }, { 0, 1.3, 2.8, 0.2 }, { -1.3, 0, 0.2, 2.4 }, { 1.3, 0, 0.2, 2.4 } }) do
		Part(m, "TreeGrate", V3(e[3], 0.06, e[4]), CF(x + e[1], SW_H + 0.03, z + e[2]), rgb(44, 44, 48), M.DiamondPlate, { shadow = false })
	end
end

-- a small "OPEN" sign glowing behind a shop window
local function openSign(m, s, rng)
	-- in the window on the side away from the door
	local side = (s.doorX and s.doorX > s.cx) and -1 or 1
	local want = s.cx + side * s.w * 0.3
	-- centred in a glazing panel (between the storefront mullions CityMap draws)
	local x0, sfW = s.cx - s.w / 2, s.w - 4
	local n = math.max(1, math.floor(sfW / 6))
	local x, best = want, math.huge
	for k = 0, n - 1 do
		local c = x0 + 2 + (k + 0.5) * sfW / n
		if math.abs(c - want) < best then
			best, x = math.abs(c - want), c
		end
	end
	local z = s.facade and (FRONT_Z - 0.27) or (FRONT_Z + 0.35)
	local _ = rng
	local p = Part(m, "OpenSign", V3(2.4, 0.9, 0.03), CF(x, 6.2, z), C.ink, M.SmoothPlastic, { shadow = false })
	local sg = K.Gui(p, FACE.Front, 40, 0)
	K.Frame(sg, { BackgroundColor3 = C.ink, BackgroundTransparency = 0.2 })
	local f = K.Frame(sg, { BackgroundTransparency = 1, Size = UDim2.fromScale(0.94, 0.86), Position = UDim2.fromScale(0.03, 0.07) })
	local st = Instance.new("UIStroke")
	st.Color = rgb(60, 160, 255)
	st.Thickness = 2
	st.Parent = f
	K.Text(sg, "OPEN", { TextColor3 = rgb(255, 70, 80), Size = UDim2.fromScale(0.8, 0.7), Position = UDim2.fromScale(0.1, 0.15) })
end

-- window AC units sticking out of a grid's lowest row
local function acUnits(m, p, rng)
	local rows = tonumber(p:GetAttribute("WinRows")) or 0
	local cols = tonumber(p:GetAttribute("WinCols")) or 1
	local top = tonumber(p:GetAttribute("WinTop")) or 0
	local span = tonumber(p:GetAttribute("WinSpan")) or 1
	if rows < 1 or p:GetAttribute("WinFace") ~= "Front" then
		return
	end
	local sz = p.Size
	local faceZ = p.Position.Z - sz.Z / 2
	local topY = p.Position.Y + sz.Y / 2
	for _ = 1, math.min(2, cols) do
		local r = rng:NextInteger(0, rows - 1)
		local c = rng:NextInteger(0, cols - 1)
		local ty = top + (r + 0.2) / rows * span
		local hh = span / rows * 0.6
		local y = topY - (ty + hh) * sz.Y + 0.55
		local x = p.Position.X - sz.X * 0.46 + (c + 0.5) * (sz.X * 0.92) / cols
		Part(m, "ACUnit", V3(1.8, 1.1, 1.2), CF(x, y, faceZ - 0.55), rgb(214, 212, 204), M.Metal)
		Part(m, "ACGrille", V3(1.6, 0.8, 0.04), CF(x, y, faceZ - 1.17), rgb(150, 150, 150), M.DiamondPlate, { shadow = false })
		Part(m, "ACBracket", V3(1.6, 0.12, 1.1), CF(x, y - 0.6, faceZ - 0.55), rgb(80, 80, 84), M.Metal, { shadow = false })
	end
end

------------------------------------------------------------------------
-- blocks
------------------------------------------------------------------------
-- Main Street in blocks of 110 studs: each its own cell
local BLOCKS = { { -330, -220 }, { -220, -110 }, { -110, 0 }, { 0, 110 }, { 110, 220 }, { 220, 330 } }
local NORTH_GAPS = { { -269, -255 }, { -8, 8 } } -- where the north sidewalk opens (Oak Street, Champion Ave)
local TREES = { -288, -248, -208, -168, -128, -88, -48, 72, 112, 152, 192, 232, 272, 312 }
local NLIGHTS = { -278, -188, -108, 92, 172, 252 }
local NBLOCK = { -238 } -- the Oak Street lot hedge runs across the north sidewalk here
local CARS = { -244, -150, -36, 78, 132, 284 }

local function inBlock(x, b)
	return x >= b[1] and x < b[2]
end

-- free along the north sidewalk at x (no tree pit, no light, no gap within `clear` studs)
local function northFree(x, clear)
	for _, t in ipairs(TREES) do
		if math.abs(t - x) < clear + 1.4 then
			return false
		end
	end
	for _, l in ipairs(NLIGHTS) do
		if math.abs(l - x) < clear + 0.8 then
			return false
		end
	end
	for _, g in ipairs(NORTH_GAPS) do
		if x > g[1] - clear and x < g[2] + clear then
			return false
		end
	end
	for _, h in ipairs(NBLOCK) do
		if math.abs(h - x) < clear + 1.2 then
			return false
		end
	end
	return true
end

local function block1(b)
	return function(m)
		-- curbs on both sides (split at the north gaps)
		local x1, x2 = b[1], b[2]
		local cuts = { x1 }
		for _, g in ipairs(NORTH_GAPS) do
			if g[1] > x1 and g[1] < x2 then
				table.insert(cuts, g[1])
			end
			if g[2] > x1 and g[2] < x2 then
				table.insert(cuts, g[2])
			end
		end
		table.insert(cuts, x2)
		table.sort(cuts)
		for i = 1, #cuts - 1 do
			local a, c = cuts[i], cuts[i + 1]
			local gap = false
			for _, g in ipairs(NORTH_GAPS) do
				if a >= g[1] and c <= g[2] then
					gap = true
				end
			end
			if not gap and c - a > 0.5 then
				curbX(m, a, c, N_CURB, 1)
			end
		end
		curbX(m, x1, x2, S_CURB, -1)
		sidewalkTiles(m, x1, x2, S_CURB, FRONT_Z - 0.02)
		for i = 1, #cuts - 1 do
			local a, c = cuts[i], cuts[i + 1]
			local gap = false
			for _, g in ipairs(NORTH_GAPS) do
				if a >= g[1] and c <= g[2] then
					gap = true
				end
			end
			if not gap and c - a > 0.5 then
				sidewalkTiles(m, a, c, 163, N_CURB)
			end
		end
		manhole(m, (x1 + x2) / 2 + 17, 177.4)
		-- lane arrows (eastbound lane +X, westbound -X), mid-block
		for _, la in ipairs({ { 169.6, 1 }, { 174.8, -1 } }) do
			local x = (x1 + x2) / 2 - la[2] * 20
			Part(m, "LaneArrow", V3(3.2, 0.03, 0.35), CF(x, ROAD_Y + 0.017, la[1]), C.white, M.SmoothPlastic, { shadow = false })
			K.Wedge(m, "LaneArrowHead", V3(0.05, 1.3, 1.2), CF(x + la[2] * 2.1, ROAD_Y + 0.03, la[1]) * A(0, 0, math.pi / 2) * A(0, la[2] > 0 and 0 or math.pi, 0), C.white, M.SmoothPlastic, { shadow = false })
		end
		-- stop bars before the crosswalks (eastbound traffic stops west of x -12.5, westbound east of 12.5)
		for _, sb in ipairs({ { -21.6, 169.6 }, { 21.6, 174.8 } }) do
			if inBlock(sb[1], b) then
				Part(m, "StopBar", V3(0.8, 0.03, 4.6), CF(sb[1], ROAD_Y + 0.017, sb[2]), C.white, M.SmoothPlastic, { shadow = false })
			end
		end
		-- the corner signals at Champion Ave
		if inBlock(-15.5, b) then
			signal(m, V3(-15.5, SW_H, 164.2), V3(0, 0, 1), 9.5, V3(-1, 0, 0), "MAIN ST")
		end
		if inBlock(15.5, b) then
			signal(m, V3(15.5, SW_H, 185.6), V3(0, 0, -1), 10.5, V3(1, 0, 0), "CHAMPION AVE")
		end
	end
end

local function block2(b, shops)
	return function(m)
		local rng = Random.new(math.floor(b[1]) + 900)
		-- north sidewalk furniture, spaced through the block
		local slot = 0
		for x = b[1] + 14, b[2] - 6, 20 do
			if northFree(x, 3.2) then
				slot += 1
				local kind = slot % 4
				if kind == 1 then
					K.Place(BENCH, m, CF(x, SW_H, 163.9) * A(0, math.pi, 0))
				elseif kind == 2 then
					K.Place(BIN, m, CF(x, SW_H, 163.7))
				elseif kind == 3 then
					K.Place(PLANTER, m, CF(x, SW_H, 163.9))
				else
					K.Place(BIKERACK, m, CF(x, SW_H, 163.9) * A(0, math.pi / 2, 0))
					K.Place(BIKE, m, CF(x - 0.8, SW_H, 163.9) * A(0, math.pi / 2, 0) * A(RAD(6), 0, 0))
				end
			end
		end
		for _, x in ipairs({ -16.5, 18.5 }) do
			if inBlock(x, b) then
				K.Place(NEWSBOX, m, CF(x, SW_H, 163.9) * A(0, math.pi, 0))
			end
		end
		-- south curb: meters by the parked cars, hydrants, storm drains
		for _, cx in ipairs(CARS) do
			for _, d in ipairs({ -4.2, 4.2 }) do
				if inBlock(cx + d, b) then
					K.Place(METER, m, CF(cx + d, SW_H, 183.45))
				end
			end
		end
		for _, x in ipairs({ -300, -200, -96, 40, 118, 200, 312 }) do
			if inBlock(x, b) then
				K.Place(HYDRANT, m, CF(x, SW_H, 183.55))
			end
		end
		for x = b[1] + 25, b[2] - 5, 55 do
			local clear = true
			for _, cx in ipairs(CARS) do
				if math.abs(cx - x) < 6 then
					clear = false
				end
			end
			if clear then
				storm(m, x)
			end
		end
		for _, x in ipairs(NLIGHTS) do
			if inBlock(x, b) then
				poleBanner(m, x, 164.2, V3(0, 0, 1))
				-- a pennant string from the light's arm across to the shop fronts
				pennants(m, V3(x, 15.75, 167.4), V3(x + 6, 15.75, FRONT_Z - 0.2), 9)
			end
		end
		for _, c in ipairs({ { -19.5, 163.9 }, { 19.5, 185.9 } }) do
			if inBlock(c[1], b) then
				cabinet(m, c[1], c[2])
			end
		end
		for _, x in ipairs(TREES) do
			if inBlock(x, b) and math.abs(x - NBLOCK[1]) > 12 then
				treeGrate(m, x, 165)
			end
		end
		-- the shops of this block
		for _, s in ipairs(shops) do
			if inBlock(s.cx, b) then
				parapet(m, s)
				if not s.marquee and not s.columns then
					signLamps(m, s)
				end
				if s.awning and not s.canopy then
					valance(m, s.awning, C.white)
				end
				if not s.hasAC then
					for _, g in ipairs(s.grids) do
						windowTrim(m, g, false)
					end
				end
				if s.h >= 30 and s.w < 46 and s.w > 40 then
					fireEscape(m, s)
				end
				openSign(m, s, rng)
				if rng:NextNumber() < 0.45 and not s.columns then
					aFrame(m, CF(s.cx - s.w * 0.3, SW_H, 185.95), ({ "OPEN\nCOME IN", "TODAY'S\nSPECIAL", "CHAMPS\nWELCOME" })[rng:NextInteger(1, 3)])
				end
			end
		end
	end
end

local function block3(b, shops)
	return function(m)
		local rng = Random.new(math.floor(b[1]) + 1700)
		for i, s in ipairs(shops) do
			if inBlock(s.cx, b) and s.h < 30 and not s.columns and i % 3 == 0 then
				waterTank(m, s.cx + s.w * 0.25, s.h + 0.9, FRONT_Z + (s.depth or 30) * 0.3)
			end
			if inBlock(s.cx, b) then
				if not s.hasAC then
					for _, g in ipairs(s.grids) do
						windowTrim(m, g, true)
						acUnits(m, g, rng)
					end
				end
				shopFine(m, s, rng)
			end
		end
		for _ = 1, 4 do
			local x = rng:NextNumber(b[1] + 4, b[2] - 4)
			if northFree(x, 2) then
				K.Patch(m, "SidewalkCrack", 3, 3, CF(x, SW_H, rng:NextNumber(163.4, 165.6)) * A(0, rng:NextNumber(0, 6.28), 0), "cracks", nil, 0.2)
			end
		end
		for _ = 1, 3 do
			K.Patch(m, "RoadStain", 4, 4, CF(rng:NextNumber(b[1] + 4, b[2] - 4), ROAD_Y, rng:NextNumber(168.4, 181.6)) * A(0, rng:NextNumber(0, 6.28), 0), "cracks", nil, 0.35)
		end
	end
end

-- the campus in front of the gym: curbs on Champion Ave, wheel stops in the member lot, the gym's gutter
local function campus1(m)
	curbZ(m, 125, 163, -8, 1)
	curbZ(m, 125, 163, 8, -1)
	manhole(m, 0, 140)
end

local function campus2(m)
	for _, x in ipairs({ -6.4, 6.4 }) do
		for _, z in ipairs({ 84.5, 88.5 }) do
			VCyl(m, "Bollard", 2.6, 0.7, V3(x, 0.3, z), rgb(60, 62, 68), M.Metal)
			VCyl(m, "BollardBand", 0.3, 0.74, V3(x, 2.2, z), C.gold, M.SmoothPlastic, { shadow = false })
		end
	end
	for x = 26, 82, 8 do
		Part(m, "WheelStop", V3(5, 0.4, 0.6), CF(x, 0.4, 92.6), rgb(196, 192, 184), M.Concrete, { shadow = false })
		Part(m, "WheelStopPaint", V3(1, 0.41, 0.62), CF(x, 0.4, 92.6), C.yellow, M.SmoothPlastic, { shadow = false })
	end
	-- the gym's roof gutter along the south facade, and its electrical meters by the east corner
	Rod(m, "Gutter", V3(-112, 29.9, 82.4), V3(112, 29.9, 82.4), 0.6, rgb(90, 92, 96), M.Metal)
	for k = 0, 2 do
		local x = 64 + k * 3
		Part(m, "MeterBox", V3(1.6, 2.2, 0.6), CF(x, 5, 81.4), C.steelLight, M.Metal)
		Part(m, "MeterDial", V3(0.8, 0.8, 0.05), CF(x, 5.3, 81.73), rgb(220, 226, 230), M.Glass)
	end
	Rod(m, "MeterConduit", V3(64, 6.1, 81.3), V3(70, 6.1, 81.3), 0.2, C.steelLight, M.Metal)
	Rod(m, "MeterConduit", V3(67, 6.1, 81.3), V3(67, 29.5, 81.3), 0.2, C.steelLight, M.Metal)
	-- an hours board on the facade (between the pilasters west of the door, clear of the posters)
	local hb = Part(m, "HoursBoard", V3(3.2, 4.4, 0.12), CF(-45, 6.8, 81.12), C.ink, M.SmoothPlastic)
	local sg = K.Gui(hb, FACE.Back, 40, 1)
	K.Frame(sg, { BackgroundColor3 = C.ink })
	K.Emblem(sg, 0.2, 0.04, 0.6, 0.3)
	K.Text(sg, "OPEN 24/7", { TextColor3 = C.gold, Size = UDim2.fromScale(0.9, 0.14), Position = UDim2.fromScale(0.05, 0.38) })
	K.Text(sg, "MEMBERS\nALWAYS WELCOME", { TextColor3 = C.white, Face = "signSub", Size = UDim2.fromScale(0.86, 0.24), Position = UDim2.fromScale(0.07, 0.56) })
	K.Frame(sg, { BackgroundColor3 = C.red, Size = UDim2.fromScale(0.9, 0.04), Position = UDim2.fromScale(0.05, 0.88) })
end

function CityDetail.Ready()
	return cityRoot() ~= nil and cityRoot():FindFirstChild("MainStreet") ~= nil
end

function CityDetail.Register(streamer)
	local shops = readShops()
	for i, b in ipairs(BLOCKS) do
		local centre = V3((b[1] + b[2]) / 2, 8, 177)
		streamer:Add("MainSt" .. i, centre, 62, { block1(b), block2(b, shops), block3(b, shops) })
	end
	streamer:Add("Campus", V3(0, 8, 110), 70, { campus1, campus2 })
	CityDetail.shops = #shops
end

return CityDetail
