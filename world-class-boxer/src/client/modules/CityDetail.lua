-- CityDetail: the town's fine-detail layer (client-only; WorldDetail streams it per cell by Graphics
-- level and camera distance). Reads the server city (workspace.Gym.City) and Config.City for where the
-- shop fronts, rows, lanes, lights and parked cars are, so the dressing always lines up with the
-- buildings it decorates. Street furniture keeps off the pedestrian lanes (Config.City.MainStreet
-- .pedLanes), the traffic lanes, the parked cars and the crosswalks; none of it collides (DetailKit
-- defaults), so walking and driving are as before. Scale: Config.City (1 stud = 0.28 m).
--   tier 1  manholes, lane arrows, storm drains, traffic cabinets, mailboxes, newspaper boxes, event
--           posters, the gym's gutter and meters, park fingerposts
--   tier 2  parking meters, hydrants, planters, bike racks, A-frame boards, cafe seating, shop sign
--           goose-neck lamps (NightLens), striped awning valances, parapets, window sills and lintels,
--           pole banners and pennants, crowd barriers, life rings and mooring bollards
--   tier 3  window piers, AC units, downspouts, rooftop vents, sidewalk cracks and stains
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DetailKit = require(script.Parent:WaitForChild("DetailKit"))

local K = DetailKit
local V3, CF, A, RAD = K.V3, K.CF, K.A, K.RAD
local M, FACE, C, rgb = K.M, K.FACE, K.C, K.rgb
local Part, Cyl, VCyl, Rod, Ball = K.Part, K.Cyl, K.VCyl, K.Rod, K.Ball

local CityDetail = {}

local CITY = Config.City
local MAIN = CITY.MainStreet
local SW_H = CITY.SidewalkY
local ROAD_Y = CITY.RoadY
local GRANITE = rgb(150, 148, 144)
local POLE = rgb(40, 44, 50)

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
-- templates (facing local -Z unless noted)
------------------------------------------------------------------------
-- a fire hydrant (barrel, bonnet, two side caps, chain)
local HYDRANT = K.Template("Hydrant", function(t)
	VCyl(t, "HydrantFlange", 0.3, 1.4, V3(0, 0, 0), rgb(190, 30, 30), M.Metal)
	VCyl(t, "HydrantBarrel", 2.4, 1.0, V3(0, 0.3, 0), rgb(200, 34, 34), M.Metal)
	Ball(t, "HydrantBonnet", 1.1, CF(0, 2.8, 0), rgb(200, 34, 34), M.Metal)
	VCyl(t, "HydrantNut", 0.3, 0.4, V3(0, 3.2, 0), C.chrome, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		Part(t, "HydrantCap", V3(0.5, 0.6, 0.6), CF(s * 0.7, 1.9, 0), C.chrome, M.Metal, { shape = "Cylinder" })
	end
	Part(t, "HydrantPumper", V3(0.6, 0.8, 0.8), CF(0, 1.7, -0.65) * A(0, math.pi / 2, 0), C.chrome, M.Metal, { shape = "Cylinder" })
end)

-- a parking meter (post, head, dial window)
local METER = K.Template("ParkingMeter", function(t)
	VCyl(t, "MeterPost", 4.2, 0.26, V3(0, 0, 0), POLE, M.Metal)
	Part(t, "MeterHead", V3(0.9, 1.3, 0.7), CF(0, 4.8, 0), rgb(120, 124, 132), M.Metal)
	Ball(t, "MeterDome", V3(0.92, 0.6, 0.72), CF(0, 5.45, 0), rgb(120, 124, 132), M.Metal)
	Part(t, "MeterWindow", V3(0.6, 0.45, 0.04), CF(0, 5.0, -0.37), rgb(190, 214, 230), M.Glass)
	Part(t, "MeterFlag", V3(0.25, 0.15, 0.04), CF(0.1, 5.0, -0.39), C.red, M.SmoothPlastic)
end)

-- a concrete planter with a shrub
local PLANTER = K.Template("Planter", function(t)
	Part(t, "PlanterBox", V3(4.0, 1.8, 2.2), CF(0, 0.9, 0), rgb(176, 172, 164), M.Concrete)
	Part(t, "PlanterSoil", V3(3.6, 0.1, 1.8), CF(0, 1.76, 0), rgb(70, 52, 36), M.Ground)
	Ball(t, "Shrub", V3(3.8, 2.2, 2.0), CF(0, 2.6, 0), rgb(60, 120, 60), M.Grass)
	Ball(t, "Shrub", V3(1.9, 1.5, 1.5), CF(0.9, 3.3, 0.1), rgb(70, 135, 64), M.Grass)
end)

-- a newspaper box (WCB DAILY), facing local -Z
local NEWSBOX = K.Template("NewsBox", function(t)
	Part(t, "NewsBody", V3(2.0, 3.4, 1.8), CF(0, 2.0, 0), rgb(30, 80, 170), M.Metal)
	Part(t, "NewsLeg", V3(1.6, 0.3, 1.4), CF(0, 0.15, 0), POLE, M.Metal)
	local w = Part(t, "NewsWindow", V3(1.5, 1.3, 0.05), CF(0, 2.6, -0.91), rgb(220, 226, 230), M.Glass)
	local sg = K.Gui(w, FACE.Front, 60, 1)
	K.Frame(sg, { BackgroundColor3 = C.paper })
	K.Text(sg, "WCB DAILY", { TextColor3 = C.ink, Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.05) })
	K.Text(sg, "TITLE FIGHT\nSATURDAY", { TextColor3 = C.redDeep, Face = "signSub", Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.42) })
	Part(t, "NewsHandle", V3(0.8, 0.15, 0.1), CF(0, 1.75, -0.95), C.chrome, M.Metal)
end)

-- a blue post box
local MAILBOX = K.Template("MailBox", function(t)
	Part(t, "MailBody", V3(2.4, 3.2, 2.2), CF(0, 2.4, 0), rgb(30, 60, 140), M.Metal)
	Ball(t, "MailTop", V3(2.4, 1.4, 2.2), CF(0, 4.0, 0), rgb(30, 60, 140), M.Metal)
	Part(t, "MailLegs", V3(2.0, 0.8, 1.8), CF(0, 0.4, 0), POLE, M.Metal)
	Part(t, "MailSlot", V3(1.4, 0.4, 0.06), CF(0, 3.6, -1.13), C.ink, M.SmoothPlastic)
	K.Sign(Part(t, "MailLabel", V3(1.8, 0.7, 0.04), CF(0, 2.2, -1.12), rgb(30, 60, 140), M.SmoothPlastic), FACE.Front, "CITY MAIL", C.white, rgb(30, 60, 140), 40, "signSub")
end)

-- an inverted-U bike rack
local BIKERACK = K.Template("BikeRack", function(t)
	for k = 0, 2 do
		local x = -2.4 + k * 2.4
		Rod(t, "RackLeg", V3(x, 0, -0.8), V3(x, 2.8, -0.8), 0.18, C.steelLight, M.Metal)
		Rod(t, "RackLeg", V3(x, 0, 0.8), V3(x, 2.8, 0.8), 0.18, C.steelLight, M.Metal)
		Rod(t, "RackTop", V3(x, 2.8, -0.8), V3(x, 2.8, 0.8), 0.18, C.steelLight, M.Metal)
	end
end)

-- a bicycle leaning in a rack (along local X)
local BIKE = K.Template("Bike", function(t)
	for _, x in ipairs({ -1.6, 1.6 }) do
		Part(t, "BikeWheel", V3(0.14, 2.3, 2.3), CF(x, 1.15, 0), C.ink, M.Rubber, { shape = "Cylinder" })
		Part(t, "BikeRim", V3(0.16, 1.7, 1.7), CF(x, 1.15, 0), C.steelLight, M.Metal, { shape = "Cylinder", t = 0.5 })
	end
	local frameCol = C.red
	Rod(t, "BikeFrame", V3(-1.6, 1.15, 0), V3(0, 1.25, 0), 0.12, frameCol, M.Metal)
	Rod(t, "BikeFrame", V3(0, 1.25, 0), V3(1.2, 2.4, 0), 0.12, frameCol, M.Metal)
	Rod(t, "BikeFrame", V3(-0.6, 2.4, 0), V3(1.2, 2.4, 0), 0.12, frameCol, M.Metal)
	Rod(t, "BikeFrame", V3(-1.6, 1.15, 0), V3(-0.6, 2.4, 0), 0.12, frameCol, M.Metal)
	Rod(t, "BikeFork", V3(1.2, 2.4, 0), V3(1.6, 1.15, 0), 0.12, C.steelLight, M.Metal)
	Part(t, "BikeSeat", V3(0.9, 0.15, 0.35), CF(-0.7, 2.7, 0), C.ink, M.Leather)
	Part(t, "BikeBars", V3(0.14, 0.14, 1.5), CF(1.25, 3.0, 0), C.ink, M.Metal)
end)

-- a cafe table with two chairs (chairs along local X)
local CAFESET = K.Template("CafeSet", function(t)
	VCyl(t, "TableBase", 0.2, 1.8, V3(0, 0, 0), POLE, M.Metal)
	VCyl(t, "TablePost", 2.4, 0.25, V3(0, 0.2, 0), POLE, M.Metal)
	VCyl(t, "TableTop", 0.15, 2.6, V3(0, 2.6, 0), rgb(236, 232, 224), M.Marble)
	Ball(t, "TableFlower", 0.6, CF(0, 3.1, 0), rgb(230, 70, 90), M.Grass, { shadow = false })
	for _, x in ipairs({ -2.2, 2.2 }) do
		Part(t, "ChairSeat", V3(1.6, 0.2, 1.6), CF(x, 1.6, 0), rgb(60, 62, 70), M.Metal)
		Part(t, "ChairBack", V3(0.2, 1.8, 1.6), CF(x + (x > 0 and 0.7 or -0.7), 2.6, 0), rgb(60, 62, 70), M.Metal)
		for _, dz in ipairs({ -0.6, 0.6 }) do
			Rod(t, "ChairLeg", V3(x - 0.6, 0, dz), V3(x - 0.6, 1.5, dz), 0.1, POLE, M.Metal)
			Rod(t, "ChairLeg", V3(x + 0.6, 0, dz), V3(x + 0.6, 1.5, dz), 0.1, POLE, M.Metal)
		end
	end
end)

-- a crowd-control barrier (2 m steel), along local X
local BARRIER = K.Template("Barrier", function(t)
	Part(t, "BarrierTop", V3(7.2, 0.2, 0.2), CF(0, 3.6, 0), C.steelLight, M.Metal)
	Part(t, "BarrierBottom", V3(7.2, 0.2, 0.2), CF(0, 0.6, 0), C.steelLight, M.Metal)
	Part(t, "BarrierPanel", V3(7.0, 2.8, 0.08), CF(0, 2.1, 0), C.steelLight, M.Metal, { t = 0.7, shadow = false })
	for _, x in ipairs({ -3.5, 3.5 }) do
		Part(t, "BarrierPost", V3(0.2, 3.8, 0.2), CF(x, 1.9, 0), C.steelLight, M.Metal)
		Part(t, "BarrierFoot", V3(0.2, 0.2, 1.6), CF(x, 0.1, 0), C.steelLight, M.Metal, { shadow = false })
	end
end)

-- a life ring on a post
local LIFERING = K.Template("LifeRing", function(t)
	Part(t, "RingBoard", V3(3.4, 3.6, 0.15), CF(0, 4.2, 0), rgb(220, 220, 214), M.SmoothPlastic)
	Part(t, "LifeRing", V3(0.6, 2.6, 2.6), CF(0, 4.2, -0.4) * A(0, math.pi / 2, 0), rgb(240, 110, 20), M.SmoothPlastic, { shape = "Cylinder" })
	Part(t, "LifeRingHole", V3(0.65, 1.1, 1.1), CF(0, 4.2, -0.4) * A(0, math.pi / 2, 0), rgb(220, 220, 214), M.SmoothPlastic, { shape = "Cylinder", shadow = false })
end)

-- a traffic signal controller cabinet
local function cabinet(m, cf)
	Part(m, "SignalCabinet", V3(2.4, 4.2, 1.6), cf * CF(0, 2.1, 0), rgb(150, 156, 150), M.Metal)
	Part(m, "CabinetBase", V3(2.6, 0.3, 1.8), cf * CF(0, 0.15, 0), C.concrete, M.Concrete, { shadow = false })
	Part(m, "CabinetVent", V3(1.6, 0.6, 0.04), cf * CF(0, 3.6, -0.82), rgb(90, 96, 90), M.DiamondPlate, { shadow = false })
end

-- an A-frame chalkboard (faces local -Z)
local function aFrame(m, cf, text)
	local front = Part(m, "BoardFront", V3(2.4, 3.4, 0.12), cf * CF(0, 1.7, -0.45) * A(RAD(10), 0, 0), C.ink2, M.Wood)
	Part(m, "BoardBack", V3(2.4, 3.4, 0.12), cf * CF(0, 1.7, 0.45) * A(RAD(-10), 0, 0), C.ink2, M.Wood)
	local sg = K.Gui(front, FACE.Front, 40, 1)
	K.Text(sg, text, { TextColor3 = C.white, Face = "marker", Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1) })
end

local function manhole(m, x, z)
	local p = K.Patch(m, "Manhole", 3.2, 3.2, CF(x, ROAD_Y, z), "manhole")
	if not p then
		VCyl(m, "ManholeCover", 0.03, 3.0, V3(x, ROAD_Y + 0.005, z), rgb(70, 70, 72), M.DiamondPlate, { shadow = false })
	end
end

-- a storm drain at a kerb: grate in the gutter and the inlet in the kerb face (side = +1: the kerb is at +Z of the road)
local function storm(m, x, kerbZ, side)
	Part(m, "StormDrain", V3(3.2, 0.04, 1.2), CF(x, ROAD_Y + 0.02, kerbZ - side * 0.9), C.ink2, M.DiamondPlate, { shadow = false })
	Part(m, "CurbInlet", V3(3.2, 0.3, 0.06), CF(x, SW_H - 0.18, kerbZ - side * 0.02), C.ink, M.SmoothPlastic, { shadow = false })
end

-- a lane arrow in the road at pos pointing along dir
local function arrow(m, pos, dir)
	local cf = CFrame.lookAt(V3(pos.X, ROAD_Y + 0.02, pos.Z), V3(pos.X, ROAD_Y + 0.02, pos.Z) + dir)
	Part(m, "LaneArrow", V3(0.6, 0.03, 6), cf * CF(0, 0, 1.5), C.white, M.SmoothPlastic, { shadow = false })
	K.Wedge(m, "LaneArrowHead", V3(0.04, 2.0, 2.6), cf * CF(0, 0, -2.6) * A(0, 0, math.pi / 2), C.white, M.SmoothPlastic, { shadow = false })
end

-- a WCB banner on a street light pole: base = the pole's foot, dir = the arm's direction
local function poleBanner(m, base, dir)
	for _, y in ipairs({ 11, 17 }) do
		Rod(m, "BannerArm", base + V3(0, y, 0), base + V3(0, y, 0) + dir * 2.6, 0.14, POLE, M.Metal)
		Ball(m, "BannerArmCap", 0.3, base + V3(0, y, 0) + dir * 2.7, C.gold, M.Metal)
	end
	local mid = base + V3(0, 14, 0) + dir * 1.4
	local cloth = Part(m, "PoleBanner", V3(0.05, 5.6, 2.2), CFrame.lookAt(mid, mid + dir) * A(0, math.pi / 2, 0), C.ink, M.Fabric, { shadow = false })
	local okR = K.Decal(cloth, FACE.Right, "bannerWCB")
	K.Decal(cloth, FACE.Left, "bannerWCB")
	if not okR then
		K.Sign(cloth, FACE.Right, "WCB", C.gold, C.ink, 20)
		K.Sign(cloth, FACE.Left, "WCB", C.gold, C.ink, 20)
	end
end

-- a string of WCB pennants between two points
local function pennants(m, a, b, n)
	local sag = V3(0, -1.6, 0)
	local mid = (a + b) / 2 + sag
	Rod(m, "PennantLine", a, mid, 0.06, C.ink, M.Fabric)
	Rod(m, "PennantLine", mid, b, 0.06, C.ink, M.Fabric)
	local cols = { C.red, C.gold, C.white, C.ink }
	for k = 1, n do
		local f = k / (n + 1)
		local p = f < 0.5 and a:Lerp(mid, f * 2) or mid:Lerp(b, (f - 0.5) * 2)
		local dir = (b - a).Unit
		local cf = CFrame.lookAt(p, p + V3(dir.Z, 0, -dir.X)) * CF(0, -0.75, 0)
		K.Wedge(m, "Pennant", V3(0.05, 1.4, 1.2), cf * A(math.pi, 0, 0), cols[k % #cols + 1], M.Fabric, { shadow = false })
	end
end

------------------------------------------------------------------------
-- reading the server city
------------------------------------------------------------------------
-- every shop front of both rows: { cf (the sign's frame: -Z to the street, origin on the front plane
-- at ground), w, h, depth, sign (part), grids, awning, facade, marquee, columns, canopy, doorX (local) }
local function readShops()
	local root = cityRoot()
	local shops = {}
	for _, rowName in ipairs({ "MainStreet", "NorthRow" }) do
		local row = root and root:FindFirstChild(rowName)
		if row then
			local parts = {}
			for _, d in ipairs(row:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			for _, p in ipairs(parts) do
				if p.Name == "ShopSign" then
					local rot = p.CFrame - p.CFrame.Position
					local cf = CF(p.Position.X, 0, p.Position.Z) * rot * CF(0, 0, p.Size.Z / 2 + 0.25) -- back to the front plane
					table.insert(shops, { cf = cf, w = p.Size.X + 3, sign = p, grids = {}, h = CITY.GroundFloor, depth = 44, row = rowName, store = p:GetAttribute("Store") or "" })
				end
			end
			for _, p in ipairs(parts) do
				for _, s in ipairs(shops) do
					if s.row == rowName then
						local rel = s.cf:PointToObjectSpace(p.Position)
						if math.abs(rel.X) < s.w / 2 and rel.Z > -4 and rel.Z < 60 then
							if p.Name == "Cornice" then
								s.h = p.Position.Y - 0.55
								s.depth = p.Size.Z - 0.8
							elseif p.Name == "ShopAwning" then
								s.awning = p
							elseif p.Name == "ShopInterior" then
								s.facade = true
							elseif p.Name == "Marquee" then
								s.marquee = true
							elseif p.Name == "Pediment" or p.Name == "MuseumSteps" then
								s.columns = true
							elseif p.Name == "LobbyCanopy" then
								s.canopy = true
							elseif p.Name == "ACUnit" then
								s.hasAC = true
							elseif p.Name == "ShopDoor" or p.Name == "DoorFrame" then
								s.doorX = rel.X
							elseif p:GetAttribute("WinRows") and math.abs(rel.X) < 0.6 then
								table.insert(s.grids, p)
							end
						end
					end
				end
			end
		end
	end
	return shops
end

-- the street lights along a stretch (their LightPole feet) and the parked cars (CarBody centres)
local function readStreet(folderName, box)
	local root = cityRoot()
	local f = root and root:FindFirstChild(folderName)
	local lights, cars = {}, {}
	if f then
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "LightPole" or d.Name == "CarBody") then
				local p = d.Position
				if p.X > box[1] and p.X < box[2] and p.Z > box[3] and p.Z < box[4] then
					if d.Name == "LightPole" then
						table.insert(lights, V3(p.X, SW_H, p.Z))
					else
						table.insert(cars, d.CFrame)
					end
				end
			end
		end
	end
	return lights, cars
end

------------------------------------------------------------------------
-- shop dressing
------------------------------------------------------------------------
-- sills and lintels under / over each window row of a grid part's front face (CityVisuals' row layout),
-- or (piers = true) the piers between the window columns
local function windowTrim(m, p, piers)
	local rows = tonumber(p:GetAttribute("WinRows")) or 0
	local cols = tonumber(p:GetAttribute("WinCols")) or 1
	local top = tonumber(p:GetAttribute("WinTop")) or 0
	local span = tonumber(p:GetAttribute("WinSpan")) or 1
	if rows < 1 or p:GetAttribute("WinFace") ~= "Front" then
		return
	end
	local s = p.Size
	local face = p.CFrame * CF(0, 0, -s.Z / 2) -- the front face's centre
	local topY = s.Y / 2
	local w = s.X
	for r = 0, rows - 1 do
		local ty = top + (r + 0.2) / rows * span
		local hh = span / rows * 0.6
		local y0 = topY - (ty + hh) * s.Y
		local y1 = topY - ty * s.Y
		if not piers then
			Part(m, "WindowSill", V3(w * 0.94, 0.32, 0.6), face * CF(0, y0 - 0.14, -0.3), rgb(200, 196, 186), M.Concrete, { shadow = false })
			Part(m, "WindowLintel", V3(w * 0.94, 0.45, 0.3), face * CF(0, y1 + 0.25, -0.15), rgb(180, 176, 168), M.Concrete, { shadow = false })
		else
			for c = 0, cols do
				local x = -w * 0.46 + c * (w * 0.92) / cols
				Part(m, "WindowPier", V3(0.45, y1 - y0 + 0.2, 0.2), face * CF(x, (y0 + y1) / 2, -0.1), rgb(190, 186, 178), M.Concrete, { shadow = false })
			end
		end
	end
end

-- striped valance hanging from an awning's front edge
local function valance(m, aw, stripe)
	local cf = aw.CFrame * CF(0, -0.1, -aw.Size.Z / 2 - 0.02)
	local v = Part(m, "AwningValance", V3(aw.Size.X, 1.2, 0.06), CFrame.new(cf.Position - V3(0, 0.6, 0)) * aw.CFrame.Rotation * A(RAD(14), 0, 0), aw.Color, M.Fabric, { shadow = false })
	local sg = K.Gui(v, FACE.Front, 12, 1)
	local n = math.max(4, math.floor(aw.Size.X / 2.2))
	for k = 0, n - 1, 2 do
		K.Frame(sg, { BackgroundColor3 = stripe, Size = UDim2.fromScale(1 / n, 1), Position = UDim2.fromScale(k / n, 0) })
	end
	K.Frame(sg, { BackgroundColor3 = aw.Color:Lerp(Color3.new(0, 0, 0), 0.35), Size = UDim2.fromScale(1, 0.18), Position = UDim2.fromScale(0, 0.82) })
end

-- the shop fronts' neon: a tube under each sign in the shop's own colour (Neon by day, a coloured
-- pool of light on the sidewalk after dark through Ambience's NightLight)
local NEON_PALETTE = { rgb(255, 60, 110), rgb(60, 210, 255), rgb(255, 200, 60), rgb(255, 80, 60), rgb(90, 240, 150), rgb(190, 90, 255), rgb(255, 140, 50) }
local function neonColor(name)
	local h = 0
	for i = 1, #name do
		h = (h * 31 + string.byte(name, i)) % 1000003
	end
	return NEON_PALETTE[h % #NEON_PALETTE + 1]
end

local function signNeon(m, s)
	local sign = s.sign
	local col = neonColor(tostring(s.store ~= "" and s.store or sign.Position.X))
	local under = sign.CFrame * CF(0, -sign.Size.Y / 2 - 0.3, -sign.Size.Z / 2 - 0.12)
	Part(m, "SignNeon", V3(sign.Size.X * 0.92, 0.16, 0.16), under, col, M.Neon, { shadow = false })
	local src = Part(m, "SignNeonLight", V3(0.2, 0.2, 0.2), under * CF(0, -0.6, -1.2), col, M.SmoothPlastic, { shadow = false, t = 1 })
	local l = Instance.new("PointLight")
	l.Color = col
	l.Range = 20
	l.Brightness = 1.4
	l.Shadows = false
	l.Enabled = false
	l.Parent = src
	tagged(l, "NightLight")
end

-- goose-neck lamps over a shop sign (their lenses glow at night through Ambience's NightLens)
local function signLamps(m, s)
	local sign = s.sign
	local n = s.w > 44 and 3 or 2
	local top = sign.CFrame * CF(0, sign.Size.Y / 2 + 1.2, -sign.Size.Z / 2)
	for k = 1, n do
		local x = -sign.Size.X / 2 + k * sign.Size.X / (n + 1)
		local wallP = top * CF(x, 0.8, 0.2)
		Part(m, "LampPlate", V3(0.6, 0.6, 0.12), wallP, POLE, M.Metal)
		Rod(m, "LampNeck", wallP.Position, (wallP * CF(0, 0.5, -1.9)).Position, 0.14, POLE, M.Metal)
		local head = wallP * CF(0, 0.4, -2.1) * A(RAD(-30), 0, 0)
		Part(m, "LampHood", V3(1.2, 0.45, 0.9), head, POLE, M.Metal)
		tagged(Part(m, "LampLens", V3(0.9, 0.08, 0.6), head * CF(0, -0.25, 0), rgb(200, 200, 196), M.SmoothPlastic, { shadow = false }), "NightLens")
	end
end

local function parapet(m, s)
	Part(m, "Parapet", V3(s.w + 0.8, 1.8, 0.6), s.cf * CF(0, s.h + 1.1 + 0.9, 0.3), rgb(110, 106, 100), M.Concrete)
	Part(m, "ParapetCoping", V3(s.w + 1.2, 0.3, 1.0), s.cf * CF(0, s.h + 1.1 + 1.95, 0.3), rgb(196, 192, 184), M.Concrete, { shadow = false })
end

local function shopFine(m, s, rng)
	-- downspout at one end, a rooftop vent (the doorways stay clear: the prompts live there)
	local x = s.w / 2 - 0.8
	if s.marquee then
		x = s.w / 2 + 2.6
	end
	Rod(m, "Downspout", (s.cf * CF(x, s.h + 0.8, -0.45)).Position, (s.cf * CF(x, SW_H + 0.5, -0.45)).Position, 0.45, rgb(90, 92, 96), M.Metal)
	Part(m, "DownspoutShoe", V3(0.5, 0.4, 1.0), s.cf * CF(x, SW_H + 0.4, -0.9), rgb(90, 92, 96), M.Metal)
	local vx = rng:NextNumber(-s.w / 3, s.w / 3)
	VCyl(m, "RoofVent", 1.8, 1.0, s.cf * CF(vx, s.h + 1.1, s.depth * 0.35), C.steelLight, M.Metal)
	VCyl(m, "RoofVentCap", 0.4, 1.6, s.cf * CF(vx, s.h + 2.9, s.depth * 0.35), C.steelLight, M.Metal)
	for _ = 1, 2 do
		local cx = rng:NextNumber(-s.w / 2 + 2, s.w / 2 - 2)
		K.Patch(m, "SidewalkCrack", 3, 3, s.cf * CF(cx, SW_H, -rng:NextNumber(2, 5)) * A(0, rng:NextNumber(0, 6.28), 0), "cracks", nil, 0.2)
	end
end

-- a small "OPEN" sign glowing behind a shop window
local function openSign(m, s)
	local side = (s.doorX and s.doorX > 0) and -1 or 1
	local z = s.facade and -0.27 or 0.4
	local p = Part(m, "OpenSign", V3(3.0, 1.2, 0.03), s.cf * CF(side * s.w * 0.3, 7.6, z), rgb(255, 70, 80), M.Neon, { shadow = false })
	local sg = K.Gui(p, FACE.Front, 40, 0)
	K.Frame(sg, { BackgroundColor3 = C.ink, BackgroundTransparency = 0.1 })
	local f = K.Frame(sg, { BackgroundTransparency = 1, Size = UDim2.fromScale(0.94, 0.86), Position = UDim2.fromScale(0.03, 0.07) })
	local st = Instance.new("UIStroke")
	st.Color = rgb(60, 160, 255)
	st.Thickness = 2
	st.Parent = f
	K.Text(sg, "OPEN", { TextColor3 = rgb(255, 70, 80), Size = UDim2.fromScale(0.8, 0.7), Position = UDim2.fromScale(0.1, 0.15) })
end

-- window AC units sticking out of a grid's rows
local function acUnits(m, p, rng)
	local rows = tonumber(p:GetAttribute("WinRows")) or 0
	local cols = tonumber(p:GetAttribute("WinCols")) or 1
	local top = tonumber(p:GetAttribute("WinTop")) or 0
	local span = tonumber(p:GetAttribute("WinSpan")) or 1
	if rows < 1 or p:GetAttribute("WinFace") ~= "Front" then
		return
	end
	local sz = p.Size
	local face = p.CFrame * CF(0, 0, -sz.Z / 2)
	for _ = 1, math.min(2, cols) do
		local r = rng:NextInteger(0, rows - 1)
		local c = rng:NextInteger(0, cols - 1)
		local ty = top + (r + 0.2) / rows * span
		local hh = span / rows * 0.6
		local y = sz.Y / 2 - (ty + hh) * sz.Y + 0.7
		local x = -sz.X * 0.46 + (c + 0.5) * (sz.X * 0.92) / cols
		Part(m, "ACUnit", V3(2.2, 1.4, 1.5), face * CF(x, y, -0.7), rgb(214, 212, 204), M.Metal)
		Part(m, "ACGrille", V3(2.0, 1.0, 0.04), face * CF(x, y, -1.47), rgb(150, 150, 150), M.DiamondPlate, { shadow = false })
		Part(m, "ACBracket", V3(2.0, 0.15, 1.4), face * CF(x, y - 0.75, -0.7), rgb(80, 80, 84), M.Metal, { shadow = false })
	end
end

-- which shops serve food: cafe seating on the sidewalk
local SEATING = { ["CHAMP'S DINER"] = true, ["CORNER CAFE"] = true, ["SUNRISE BAKERY"] = true, ["TONY'S PIZZA"] = true, ["LUCKY DRAGON NOODLES"] = true, ["WCB SPORTS BAR"] = true }

------------------------------------------------------------------------
-- Main Street blocks
------------------------------------------------------------------------
local BLOCK = 148
local BLOCKS = {}
do
	local x = MAIN.x0
	while x < MAIN.x1 - 1 do
		table.insert(BLOCKS, { x, math.min(MAIN.x1, x + BLOCK) })
		x += BLOCK
	end
end
local JUNCTIONS = { CITY.ChampionAve.x, CITY.OakStreet.x, CITY.RiversideDrive.x }

local function inBlock(x, b)
	return x >= b[1] and x < b[2]
end
local function nearJunction(x, d)
	for _, j in ipairs(JUNCTIONS) do
		if math.abs(x - j) < d then
			return true
		end
	end
	return false
end
-- free of a street light / parked car / crossing within `clear` studs along x (for sidewalk furniture)
local function free(x, lights, cars, clear)
	if nearJunction(x, 28 + clear) then
		return false
	end
	for _, l in ipairs(lights) do
		if math.abs(l.X - x) < clear + 1 then
			return false
		end
	end
	for _, c in ipairs(cars) do
		if math.abs(c.Position.X - x) < clear + 8 then
			return false
		end
	end
	return true
end

local function block1(b)
	return function(m)
		local x1, x2 = b[1], b[2]
		local mid = (x1 + x2) / 2
		-- manholes and lane arrows in the lanes, storm drains at both kerbs
		manhole(m, mid + 20, (MAIN.lanes[1].z + MAIN.lanes[2].z) / 2 + 6)
		manhole(m, mid - 40, MAIN.parkLanes[1] + 2)
		for _, la in ipairs(MAIN.lanes) do
			local ax = mid - la.dir * 30
			if not nearJunction(ax, 40) then
				arrow(m, V3(ax, 0, la.z), V3(la.dir, 0, 0))
			end
		end
		for x = x1 + 30, x2 - 10, 60 do
			if not nearJunction(x, 24) then
				storm(m, x, MAIN.z0, -1)
				storm(m, x + 22, MAIN.z1, 1)
			end
		end
		-- the signal cabinets, mailboxes and newspaper boxes at the junctions
		for _, j in ipairs(JUNCTIONS) do
			if inBlock(j - 30, b) then
				cabinet(m, CF(j - 30, SW_H, MAIN.z0 - 3.4))
				K.Place(MAILBOX, m, CF(j - 34, SW_H, MAIN.z1 + 3.4) * A(0, math.pi, 0))
			end
			if inBlock(j + 30, b) then
				cabinet(m, CF(j + 30, SW_H, MAIN.z1 + 4.5) * A(0, math.pi, 0))
				K.Place(NEWSBOX, m, CF(j + 34, SW_H, MAIN.z0 - 4.0) * A(0, math.pi, 0))
				K.Place(NEWSBOX, m, CF(j + 36.2, SW_H, MAIN.z0 - 4.0) * A(0, math.pi, 0))
			end
		end
	end
end

local function block2(b, shops)
	return function(m)
		local rng = Random.new(math.floor(b[1]) + 900)
		local lights, cars = readStreet("MainStreet", { b[1], b[2], MAIN.z0 - 20, MAIN.z1 + 20 })
		-- north sidewalk furniture (by the road), spaced through the block
		local slot = 0
		for x = b[1] + 14, b[2] - 8, 26 do
			if free(x, lights, cars, 3.5) then
				slot += 1
				local kind = slot % 4
				if kind == 1 then
					K.Place(PLANTER, m, CF(x, SW_H, MAIN.z0 - 2.4))
				elseif kind == 2 then
					K.Place(BIKERACK, m, CF(x, SW_H, MAIN.z0 - 3.0) * A(0, math.pi / 2, 0))
					K.Place(BIKE, m, CF(x - 1.0, SW_H, MAIN.z0 - 3.0) * A(0, math.pi / 2, 0) * A(RAD(6), 0, 0))
				elseif kind == 3 then
					K.Place(HYDRANT, m, CF(x, SW_H, MAIN.z0 - 2.4))
				else
					K.Place(PLANTER, m, CF(x, SW_H, MAIN.z1 + 3.2))
				end
			end
		end
		-- meters by the parked cars, hydrants on the shop side
		for _, c in ipairs(cars) do
			local south = c.Position.Z > (MAIN.z0 + MAIN.z1) / 2
			for _, d in ipairs({ -6, 6 }) do
				local x = c.Position.X + d
				if inBlock(x, b) then
					K.Place(METER, m, CF(x, SW_H, south and MAIN.z1 + 2.2 or MAIN.z0 - 2.2))
				end
			end
		end
		for x = b[1] + 40, b[2] - 10, 90 do
			if free(x, lights, cars, 2) then
				K.Place(HYDRANT, m, CF(x, SW_H, MAIN.z1 + 2.4))
			end
		end
		-- banners on the lights, pennant strings from them across to the shop fronts
		for _, l in ipairs(lights) do
			local south = l.Z > (MAIN.z0 + MAIN.z1) / 2
			poleBanner(m, l, V3(0, 0, south and -1 or 1))
			if not south then
				pennants(m, l + V3(0, 21, 0), V3(l.X + 8, 20, MAIN.frontN + 0.3), 11)
			else
				pennants(m, l + V3(0, 21, 0), V3(l.X - 8, 20, MAIN.frontS - 0.3), 11)
			end
		end
		-- the shops of this block
		for _, s in ipairs(shops) do
			if inBlock(s.cf.Position.X, b) then
				if not s.columns and not s.canopy then
					parapet(m, s)
				end
				if not s.marquee and not s.columns then
					signLamps(m, s)
					signNeon(m, s)
				end
				if s.awning and not s.canopy then
					valance(m, s.awning, C.white)
				end
				if not s.hasAC then
					for _, g in ipairs(s.grids) do
						windowTrim(m, g, false)
					end
				end
				if not s.columns and not s.canopy then
					openSign(m, s)
				end
				if SEATING[s.store] then
					for _, dx in ipairs({ -s.w * 0.28, s.w * 0.28 }) do
						K.Place(CAFESET, m, s.cf * CF(dx, SW_H, -5.5))
					end
					aFrame(m, s.cf * CF(0, SW_H, -3.2), ({ "TODAY'S\nSPECIAL", "FRESH\nCOFFEE", "CHAMPS\nEAT FREE*" })[rng:NextInteger(1, 3)])
				elseif rng:NextNumber() < 0.4 and not s.columns and not s.canopy then
					aFrame(m, s.cf * CF(-s.w * 0.3, SW_H, -5), ({ "OPEN\nCOME IN", "SALE\nTODAY", "CHAMPS\nWELCOME" })[rng:NextInteger(1, 3)])
				end
			end
		end
	end
end

local function block3(b, shops)
	return function(m)
		local rng = Random.new(math.floor(b[1]) + 1700)
		for _, s in ipairs(shops) do
			if inBlock(s.cf.Position.X, b) then
				if not s.hasAC then
					for _, g in ipairs(s.grids) do
						windowTrim(m, g, true)
						acUnits(m, g, rng)
					end
				end
				shopFine(m, s, rng)
			end
		end
		for _ = 1, 3 do
			K.Patch(m, "RoadStain", 5, 5, CF(rng:NextNumber(b[1] + 4, b[2] - 4), ROAD_Y, rng:NextNumber(MAIN.z0 + 4, MAIN.z1 - 4)) * A(0, rng:NextNumber(0, 6.28), 0), "cracks", nil, 0.35)
		end
	end
end

------------------------------------------------------------------------
-- the other cells
------------------------------------------------------------------------
-- Champion Ave: manholes, a storm drain, meters, pennants between the lights, the plaza's bike racks
local function avenue1(m)
	local AVE = CITY.ChampionAve
	manhole(m, AVE.x + 4, 220)
	manhole(m, AVE.x - 5, 270)
	for _, z in ipairs({ 210, 250 }) do
		Part(m, "StormDrain", V3(1.2, 0.04, 3.2), CF(AVE.x - AVE.w / 2 + 0.9, ROAD_Y + 0.02, z), C.ink2, M.DiamondPlate, { shadow = false })
	end
	arrow(m, V3(AVE.x + 6.25, 0, 230), V3(0, 0, -1))
	arrow(m, V3(AVE.x - 6.25, 0, 260), V3(0, 0, 1))
	cabinet(m, CF(AVE.x + 20, SW_H, 190) * A(0, math.pi / 2, 0))
end
local function avenue2(m)
	local AVE = CITY.ChampionAve
	local lights = readStreet("MainStreet", { AVE.x - 30, AVE.x + 30, AVE.z0, AVE.z1 - 10 })
	for i = 1, #lights - 1 do
		local a, b2 = lights[i], lights[i + 1]
		if math.abs(a.X - b2.X) > 20 then
			pennants(m, a + V3(0, 21, 0), b2 + V3(0, 21, 0), 13)
		end
	end
	for _, z in ipairs({ 222, 262 }) do
		K.Place(PLANTER, m, CF(AVE.x - 21.5, SW_H, z))
		K.Place(PLANTER, m, CF(AVE.x + 21.5, SW_H, z))
	end
	K.Place(BIKERACK, m, CF(AVE.x + 20, SW_H, 240))
	K.Place(BIKE, m, CF(AVE.x + 20, SW_H, 239) * A(RAD(6), 0, 0))
	K.Place(HYDRANT, m, CF(AVE.x - 14.6, SW_H, 236))
end

-- the campus in front of the gym: bike racks and planters by the doors, the gym's gutter and meters, the hours board
local function campus1(m)
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
	manhole(m, -30, CITY.Loop.z1 + 5)
	manhole(m, 60, CITY.Loop.z1 - 5)
end
local function campus2(m)
	local L = CITY.Loop
	for _, x in ipairs({ -26, 26 }) do
		K.Place(BIKERACK, m, CF(x, 0.3, 96) * A(0, math.pi / 2, 0))
		K.Place(BIKE, m, CF(x - 1, 0.3, 96) * A(0, math.pi / 2, 0) * A(RAD(6), 0, 0))
	end
	K.Place(HYDRANT, m, CF(-34, 0.3, 146))
	K.Place(NEWSBOX, m, CF(-62, SW_H, L.z1 + 12.5 + 1.2 + 2) * A(0, math.pi, 0))
	K.Place(MAILBOX, m, CF(30, SW_H, L.z1 - 12.5 - 1.8))
	local lights = readStreet("Campus", { -210, 210, L.z1 - 20, L.z1 + 20 })
	for _, l in ipairs(lights) do
		poleBanner(m, l, V3(0, 0, l.Z < L.z1 and 1 or -1))
	end
end

-- the arena plaza: crowd barriers in front of the doors, posters on the ticket booths
local function arena1(m)
	for _, x in ipairs({ -120, 120 }) do
		local p = Part(m, "EventPoster", V3(6, 9, 0.05), CF(x + 1, 7.5, -490.02), C.ink, M.SmoothPlastic, { shadow = false })
		if not K.Decal(p, FACE.Back, "posterFightNight") then
			K.Sign(p, FACE.Back, "FIGHT\nNIGHT", C.gold, C.ink, 30)
		end
	end
end
local function arena2(m)
	for row = 0, 1 do
		for k = -6, 6 do
			K.Place(BARRIER, m, CF(k * 7.4, 0.3, -512 + row * 10))
		end
	end
	for _, x in ipairs({ -60, 60 }) do
		K.Place(BIKERACK, m, CF(x, 0.3, -476) * A(0, math.pi / 2, 0))
	end
end

-- the park: fingerposts at the gates, a bird bath; the waterfront: life rings and mooring bollards
local function park1(m)
	local P = CITY.Park
	for _, z in ipairs({ -100, 60, 200 }) do
		local post = CF(P.x0 + 14, 0.14, z + 8)
		VCyl(m, "FingerPost", 9, 0.4, post, rgb(60, 40, 26), M.Wood)
		for i, txt in ipairs({ "FOUNTAIN  >", "<  COURT", "BOATHOUSE  >" }) do
			local blade = Part(m, "FingerBlade", V3(5, 0.8, 0.1), post * CF(2.2, 8.2 - i * 1.1, 0) * A(0, RAD(i * 25), 0), rgb(60, 40, 26), M.Wood)
			K.Sign(blade, FACE.Front, txt, rgb(255, 230, 170), rgb(60, 40, 26), 40, "signSub")
		end
	end
end
local function park2(m)
	local BW = CITY.Boardwalk
	for z = -500, 420, 90 do
		K.Place(LIFERING, m, CF(BW.x1 - 1.4, SW_H, z) * A(0, -math.pi / 2, 0))
		VCyl(m, "MooringBollard", 1.6, 1.4, V3(BW.x0 + 20, SW_H, z + 45), C.ink2, M.Metal)
	end
	VCyl(m, "BirdBathPost", 2.6, 0.9, V3(430, 0.14, 100), GRANITE, M.Granite)
	VCyl(m, "BirdBath", 0.4, 3.2, V3(430, 2.74, 100), GRANITE, M.Granite)
	VCyl(m, "BirdBathWater", 0.08, 2.8, V3(430, 3.14, 100), rgb(80, 160, 220), M.Glass)
end

function CityDetail.Ready()
	local r = cityRoot()
	return r ~= nil and r:FindFirstChild("MainStreet") ~= nil
end

function CityDetail.Register(streamer)
	local shops = readShops()
	for i, b in ipairs(BLOCKS) do
		local centre = V3((b[1] + b[2]) / 2, 8, (MAIN.z0 + MAIN.z1) / 2)
		streamer:Add("MainSt" .. i, centre, BLOCK / 2 + 10, { block1(b), block2(b, shops), block3(b, shops) })
	end
	streamer:Add("Avenue", V3(0, 8, 240), 70, { avenue1, avenue2 })
	streamer:Add("Campus", V3(0, 8, 120), 90, { campus1, campus2 })
	streamer:Add("ArenaPlaza", V3(0, 8, -495), 120, { arena1, arena2 })
	streamer:Add("Park", V3(400, 8, 60), 160, { park1 })
	streamer:Add("Waterfront", V3(870, 8, 0), 300, { park2 })
	CityDetail.shops = #shops
end

return CityDetail
