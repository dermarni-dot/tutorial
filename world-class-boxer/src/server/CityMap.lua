-- CityMap: the neighbourhood around the gym, so the world outside feels like a real town.
-- Inside the roadwork loop: member parking, Champions Plaza with the golden glove monument,
-- an outdoor training yard, a bus stop and crosswalk. Outside the loop: Champion Ave runs
-- south to Main Street and its row of shops (diner, supplements, pro shop, cafe, laundromat,
-- tattoo, bakery, arena ticket office, corner store, pizza, apartments, boxing museum, gas
-- station, motel); Oak Street's houses to the west; Riverside Park with a basketball court and
-- fountain to the east; the WCB Arena to the north and a city skyline around the edges.
-- Street lights and shop lights are tagged "NightLight"/"NightLens" and switched on at dusk by
-- the client (Ambience). Neon signs are tagged "NeonFlicker".
local GymDecor = require(script.Parent:WaitForChild("GymDecor"))

local CityMap = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material

local part = GymDecor.Part
local cyl = GymDecor.Cyl
local vcyl = GymDecor.VCyl
local ball = GymDecor.Ball
local blob = GymDecor.Blob
local label = GymDecor.Label
local frame = GymDecor.Frame
local spot = GymDecor.Spot
local point = GymDecor.Point
local emitter = GymDecor.Emitter
local tag = GymDecor.Tag
local C = GymDecor.Colors

local ASPHALT = Color3.fromRGB(58, 58, 62)
local SIDEWALK = Color3.fromRGB(170, 168, 162)
local LINE_YELLOW = Color3.fromRGB(240, 210, 90)
local POLE = Color3.fromRGB(46, 48, 54)
local LENS_DAY = Color3.fromRGB(200, 200, 196)
local SW_H = 0.5 -- sidewalk top height (roads are 0.3)

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function gui(p, face, ppu, light, maxDist)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 20
	sg.LightInfluence = light or 0
	sg.MaxDistance = maxDist or 600
	sg.Parent = p
	return sg
end

-- flat slab lying on the ground (roads, sidewalks, paving): x1..x2, z1..z2, top height
local function slab(parent, name, x1, x2, z1, z2, top, color, material, collide)
	return part(parent, name, V3(x2 - x1, top, z2 - z1), CF((x1 + x2) / 2, top / 2, (z1 + z2) / 2), color, material, { collide = collide ~= false })
end

-- zebra crossing: bars run along the traffic direction and are stacked across the road
local function crosswalk(parent, center, alongX, roadWidth, bandWidth)
	local n = math.floor(roadWidth / 2.2)
	for i = 0, n - 1 do
		local o = -roadWidth / 2 + 1.1 + i * (roadWidth - 2.2) / math.max(1, n - 1)
		if alongX then
			part(parent, "Crosswalk", V3(bandWidth, 0.04, 1.0), CF(center + V3(0, 0, o)), C.white, M.SmoothPlastic)
		else
			part(parent, "Crosswalk", V3(1.0, 0.04, bandWidth), CF(center + V3(o, 0, 0)), C.white, M.SmoothPlastic)
		end
	end
end

-- glowing neon outline around a rectangle (cf faces the viewer with its -Z)
local function neonOutline(parent, cf, w, h, color)
	local m = model(parent, "NeonOutline")
	local t = 0.22
	for _, e in ipairs({ { 0, h / 2, w + t, t }, { 0, -h / 2, w + t, t }, { -w / 2, 0, t, h }, { w / 2, 0, t, h } }) do
		part(m, "NeonTube", V3(e[3], e[4], t), cf * CF(e[1], e[2], 0), color, M.Neon, { shadow = false })
	end
	tag(m, "NeonFlicker")
	return m
end

------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------
-- street light standing at base; dir = horizontal unit vector from the pole out over the road
local function streetLight(parent, base, dir, withLight)
	local up = 15
	local m = model(parent, "StreetLight")
	part(m, "LightBase", V3(1.2, 0.6, 1.2), CF(base + V3(0, 0.3, 0)), C.steel, M.Concrete, { collide = true })
	part(m, "LightPole", V3(0.45, up, 0.45), CF(base + V3(0, up / 2, 0)), POLE, M.Metal, { collide = true })
	local a = base + V3(0, up - 0.3, 0)
	local armEnd = a + dir * 4.2
	part(m, "LightArm", V3(0.3, 0.3, 4.4), CFrame.lookAt((a + armEnd) / 2, armEnd), POLE, M.Metal)
	local head = part(m, "LightHead", V3(1.1, 0.45, 2.2), CFrame.lookAt(armEnd, armEnd + dir), POLE, M.Metal)
	local lens = part(m, "LightLens", V3(0.8, 0.08, 1.8), head.CFrame * CF(0, -0.26, 0), LENS_DAY, M.SmoothPlastic, { shadow = false })
	tag(lens, "NightLens")
	if withLight then
		local l = spot(emitter(m, head.CFrame * CF(0, -0.8, 0)), Enum.NormalId.Bottom, Color3.fromRGB(255, 220, 170), 44, 1.7, 120)
		l.Enabled = false
		tag(l, "NightLight")
	end
	return m
end

-- simple car; cf = ground centre, front towards local -Z
local CAR_COLORS = {
	Color3.fromRGB(190, 30, 36), Color3.fromRGB(235, 235, 238), Color3.fromRGB(28, 28, 32), Color3.fromRGB(40, 80, 170),
	Color3.fromRGB(150, 152, 158), Color3.fromRGB(30, 110, 70), Color3.fromRGB(230, 170, 40),
}
local function car(parent, cf, color)
	local m = model(parent, "Car")
	part(m, "CarBody", V3(5.2, 1.5, 10.6), cf * CF(0, 1.55, 0), color, M.SmoothPlastic, { collide = true })
	part(m, "CarCabin", V3(4.6, 1.6, 5.2), cf * CF(0, 3.05, 0.6), Color3.fromRGB(40, 54, 70), M.Glass, { reflect = 0.15 })
	part(m, "CarRoof", V3(4.8, 0.25, 4.6), cf * CF(0, 3.95, 0.7), color, M.SmoothPlastic)
	for _, x in ipairs({ -2.35, 2.35 }) do
		for _, z in ipairs({ -3.4, 3.5 }) do
			cyl(m, "Wheel", 0.9, 2.1, cf * CF(x, 1.05, z), Color3.fromRGB(20, 20, 22), M.Rubber)
			cyl(m, "Hubcap", 0.95, 1.0, cf * CF(x, 1.05, z), Color3.fromRGB(190, 192, 198), M.Metal)
		end
	end
	for _, x in ipairs({ -1.8, 1.8 }) do
		part(m, "Headlight", V3(0.9, 0.45, 0.1), cf * CF(x, 1.9, -5.32), Color3.fromRGB(255, 250, 230), M.Neon, { shadow = false })
		part(m, "Taillight", V3(0.9, 0.4, 0.1), cf * CF(x, 1.9, 5.32), Color3.fromRGB(220, 30, 30), M.Neon, { shadow = false })
	end
	part(m, "BumperF", V3(5.4, 0.5, 0.4), cf * CF(0, 1.0, -5.35), C.black, M.SmoothPlastic)
	part(m, "BumperB", V3(5.4, 0.5, 0.4), cf * CF(0, 1.0, 5.35), C.black, M.SmoothPlastic)
	part(m, "Plate", V3(1.4, 0.45, 0.06), cf * CF(0, 1.4, 5.58), C.white, M.SmoothPlastic)
	return m
end

-- tiered pine and round deciduous tree
local function pine(parent, pos, h)
	vcyl(parent, "PineTrunk", h * 0.3, 0.9, CF(pos), Color3.fromRGB(90, 62, 40), M.Wood, { collide = true })
	for i = 0, 3 do
		local t = i / 3
		vcyl(parent, "PineTier", h * 0.22, h * (0.55 - t * 0.35), CF(pos + V3(0, h * (0.22 + t * 0.6), 0)), Color3.fromRGB(34, 88 + i * 8, 48), M.Grass)
	end
	ball(parent, "PineTop", h * 0.12, CF(pos + V3(0, h * 1.02, 0)), Color3.fromRGB(40, 104, 56), M.Grass)
end

local function roundTree(parent, pos, h, rng)
	vcyl(parent, "TreeTrunk", h * 0.55, 1.2, CF(pos), Color3.fromRGB(96, 66, 42), M.Wood, { collide = true })
	blob(parent, "Canopy", V3(h * 0.8, h * 0.65, h * 0.8), CF(pos + V3(0, h * 0.75, 0)), Color3.fromRGB(50 + rng:NextInteger(0, 25), 112 + rng:NextInteger(0, 30), 52), M.Grass)
	blob(parent, "Canopy", V3(h * 0.55, h * 0.5, h * 0.55), CF(pos + V3(h * 0.18, h * 0.95, h * 0.1)), Color3.fromRGB(62, 128, 60), M.Grass)
end

-- window grid on one face (some windows lit); rows/cols fill the band y0..y1 of a face faceH tall
local function windowGrid(p, face, faceH, y0, y1, rows, cols, rng, litChance)
	local sg = gui(p, face, 4, 0.15, 1200)
	local top = 1 - y1 / faceH
	local spanH = (y1 - y0) / faceH
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local lit = rng:NextNumber() < (litChance or 0.35)
			frame(sg, {
				Size = UDim2.fromScale(0.62 / cols, spanH / rows * 0.6),
				Position = UDim2.fromScale((c + 0.19) / cols, top + (r + 0.2) / rows * spanH),
				BackgroundColor3 = lit and Color3.fromRGB(255, 214 + rng:NextInteger(0, 30), 140 + rng:NextInteger(0, 40)) or Color3.fromRGB(34, 44, 58),
			})
		end
	end
	return sg
end

-- picnic table (top along local X)
local function picnicTable(parent, pos, yaw)
	local base = CF(pos) * ANG(0, yaw or 0, 0)
	part(parent, "PicnicTop", V3(6, 0.3, 2.6), base * CF(0, 2.6, 0), C.wood, M.WoodPlanks, { collide = true })
	for _, z in ipairs({ -2.1, 2.1 }) do
		part(parent, "PicnicSeat", V3(6, 0.25, 1.0), base * CF(0, 1.5, z), C.wood, M.WoodPlanks, { collide = true })
	end
	for _, x in ipairs({ -2.3, 2.3 }) do
		part(parent, "PicnicLeg", V3(0.3, 2.6, 4.6), base * CF(x, 1.3, 0), C.woodDark, M.Wood)
	end
end

------------------------------------------------------------------------
-- Inside the loop: crosswalk, bus stop, parking lot, plaza, outdoor yard; lights along the loop
------------------------------------------------------------------------
local function buildCampus(root)
	local f = folder(root, "Campus")
	local rng = Random.new(42)
	-- zebra crossing where the entrance path meets the loop road (road runs along X, z 115..125)
	crosswalk(f, V3(0, 0.32, 120), true, 10, 8.8)
	-- bus stop on the far side of the loop road, facing it
	local bs = CF(-40, 0.3, 130)
	part(f, "BusPad", V3(10, 0.3, 4.6), bs, SIDEWALK, M.Concrete, { collide = true })
	part(f, "BusRoof", V3(9, 0.35, 3.8), bs * CF(0, 8.3, 0.2), Color3.fromRGB(40, 44, 52), M.Metal)
	part(f, "BusBack", V3(8.6, 6.6, 0.15), bs * CF(0, 4.5, 1.9), Color3.fromRGB(180, 210, 230), M.Glass, { transparency = 0.5, shadow = false })
	part(f, "BusSide", V3(0.15, 6.6, 3.2), bs * CF(-4.3, 4.5, 0.4), Color3.fromRGB(180, 210, 230), M.Glass, { transparency = 0.5, shadow = false })
	for _, x in ipairs({ -4.4, 4.4 }) do
		part(f, "BusPost", V3(0.25, 8.2, 0.25), bs * CF(x, 4.2, 1.9), Color3.fromRGB(40, 44, 52), M.Metal, { collide = true })
	end
	GymDecor.Bench(f, (bs * CF(-1.2, 0.15, 1.0)).Position, 0, 5, C.wood)
	local ad = part(f, "BusAd", V3(3.2, 4.6, 0.2), bs * CF(2.4, 4.6, 1.72), C.black, M.SmoothPlastic)
	GymDecor.PosterGui(ad, Enum.NormalId.Front, GymDecor.Posters[3])
	part(f, "BusSignPole", V3(0.25, 9, 0.25), bs * CF(5.6, 4.5, -1.6), C.steel, M.Metal, { collide = true })
	local bsign = part(f, "BusSign", V3(1.8, 1.4, 0.15), bs * CF(5.6, 8.4, -1.6), Color3.fromRGB(30, 90, 190), M.SmoothPlastic)
	GymDecor.Sign(bsign, Enum.NormalId.Front, "BUS 12", Color3.new(1, 1, 1), Color3.fromRGB(30, 90, 190), 40)
	GymDecor.Sign(bsign, Enum.NormalId.Back, "BUS 12", Color3.new(1, 1, 1), Color3.fromRGB(30, 90, 190), 40)

	-- member parking east of the entrance path (between the gym sidewalk curb and the loop road)
	local LZ1, LZ2 = 89.6, 112
	slab(f, "ParkingLot", 20, 90, LZ1, LZ2, 0.2, ASPHALT, M.Asphalt)
	slab(f, "ParkingEntry", 80, 90, LZ2, 115, 0.2, ASPHALT, M.Asphalt)
	for x = 22, 86, 8 do
		part(f, "BayLine", V3(0.3, 0.03, 10), CF(x, 0.215, 96.6), C.white, M.SmoothPlastic)
	end
	part(f, "BayHead", V3(64.3, 0.03, 0.3), CF(54, 0.215, 91.7), C.white, M.SmoothPlastic)
	for i, x in ipairs({ 26, 42, 50, 66, 82 }) do
		car(f, CF(x, 0.2, 97.6) * ANG(0, RAD(rng:NextNumber(-3, 3)), 0), CAR_COLORS[(i - 1) % #CAR_COLORS + 1])
	end
	for _, x in ipairs({ 36, 74 }) do
		streetLight(f, V3(x, 0.2, 109.6), V3(0, 0, -1), true)
	end
	local lotSign = part(f, "LotSign", V3(5, 2, 0.2), CF(24, 4.2, 110.6), Color3.fromRGB(30, 60, 160), M.SmoothPlastic)
	part(f, "LotSignPole", V3(0.25, 3.3, 0.25), CF(24, 1.65, 110.6), C.steel, M.Metal)
	GymDecor.Sign(lotSign, Enum.NormalId.Back, "P  MEMBER PARKING", Color3.new(1, 1, 1), Color3.fromRGB(30, 60, 160), 40)

	-- Champions Plaza west of the entrance path: paving, golden glove monument, benches, trees, flags
	slab(f, "PlazaBorder", -88.3, -21.7, LZ1, LZ2, 0.2, Color3.fromRGB(120, 110, 100), M.Concrete)
	slab(f, "PlazaPaving", -88, -22, LZ1 + 0.3, LZ2 - 0.3, 0.22, Color3.fromRGB(196, 186, 170), M.Pavement)
	local mon = V3(-55, 0.22, 101)
	part(f, "MonumentBase", V3(8, 1.2, 8), CF(mon + V3(0, 0.6, 0)), Color3.fromRGB(80, 80, 86), M.Granite, { collide = true })
	part(f, "MonumentPlinth", V3(5, 4.4, 5), CF(mon + V3(0, 3.4, 0)), Color3.fromRGB(60, 60, 66), M.Granite, { collide = true })
	local plaque = part(f, "MonumentPlaque", V3(3.6, 1.6, 0.1), CF(mon + V3(0, 3.2, 2.55)), C.gold, M.Metal)
	GymDecor.Sign(plaque, Enum.NormalId.Back, "CHAMPIONS WALK\nEvery champion started here", Color3.fromRGB(40, 30, 10), C.gold, 40)
	local gloveCF = CF(mon + V3(0, 8.4, 0)) * ANG(RAD(-12), RAD(25), 0)
	blob(f, "GoldenGlove", V3(4.2, 5.4, 4.6), gloveCF, C.gold, M.Metal, { reflect = 0.2 })
	blob(f, "GoldenThumb", V3(1.5, 2.6, 1.6), gloveCF * CF(-1.9, 0.2, -0.9) * ANG(0, 0, RAD(-18)), C.gold, M.Metal, { reflect = 0.2 })
	cyl(f, "GloveCuff", 2.0, 3.4, gloveCF * CF(0, -3.1, 0) * ANG(0, 0, RAD(90)), C.goldDeep, M.Metal)
	for k = 0, 3 do
		part(f, "GloveLace", V3(1.6, 0.12, 0.14), gloveCF * CF(0, -2.4 + k * 0.4, -1.75) * ANG(0, 0, RAD(k % 2 == 0 and 25 or -25)), Color3.fromRGB(150, 110, 20), M.Fabric)
	end
	local ml = spot(emitter(f, CF(mon + V3(0, 1.4, 6))), Enum.NormalId.Top, Color3.fromRGB(255, 225, 170), 16, 1.6, 60)
	ml.Enabled = false
	tag(ml, "NightLight")
	for _, d in ipairs({ { -76, 95.5 }, { -34, 95.5 }, { -76, 106.5 }, { -34, 106.5 } }) do
		GymDecor.Bench(f, V3(d[1], 0.22, d[2]), RAD(90), 5, C.wood)
	end
	for _, x in ipairs({ -84, -26 }) do
		part(f, "TreePlanter", V3(4, 1.2, 4), CF(x, 0.82, 101), Color3.fromRGB(120, 110, 100), M.Concrete, { collide = true })
		roundTree(f, V3(x, 1.4, 101), 11, rng)
	end
	local flagColors = { { C.red, C.white }, { Color3.fromRGB(18, 18, 22), C.gold }, { C.blue, C.white } }
	for i, x in ipairs({ -64, -55, -46 }) do
		local base = V3(x, 0.22, 110.2)
		vcyl(f, "FlagPole", 16, 0.3, CF(base), C.steelLight, M.Metal, { collide = true })
		ball(f, "FlagPoleTop", 0.5, CF(base + V3(0, 16.1, 0)), C.gold, M.Metal)
		local fl = part(f, "Flag", V3(0.08, 2.6, 4.2), CF(base + V3(0, 14.4, -2.2)), flagColors[i][1], M.Fabric, { shadow = false })
		GymDecor.Sign(fl, Enum.NormalId.Right, "WCB", flagColors[i][2], nil, 30)
		GymDecor.Sign(fl, Enum.NormalId.Left, "WCB", flagColors[i][2], nil, 30)
	end

	-- outdoor training yard east of the building (inside the loop)
	local y0 = V3(136, 0, -16)
	part(f, "YardFloor", V3(30, 0.25, 46), CF(y0 + V3(0, 0.125, 0)), Color3.fromRGB(44, 46, 50), M.Rubber, { collide = true })
	for k = 0, 3 do
		part(f, "SprintLane", V3(0.3, 0.03, 40), CF(y0 + V3(5 + k * 2.6, 0.265, 0)), C.white, M.SmoothPlastic)
	end
	for _, z in ipairs({ -18, -10 }) do
		for _, x in ipairs({ -10, -4 }) do
			part(f, "RigPost", V3(0.4, 9, 0.4), CF(y0 + V3(x, 4.75, z)), C.black, M.Metal, { collide = true })
		end
	end
	for _, x in ipairs({ -10, -4 }) do
		cyl(f, "RigBar", 8.4, 0.22, CF(y0 + V3(x, 8.4, -14)) * ANG(0, RAD(90), 0), C.steelLight, M.Metal)
	end
	for _, z in ipairs({ -18, -14, -10 }) do
		cyl(f, "PullUpBar", 6.4, 0.22, CF(y0 + V3(-7, 8.6, z)), C.steelLight, M.Metal)
	end
	for _, x in ipairs({ -9.2, -7.4 }) do
		cyl(f, "ParallelBar", 6, 0.25, CF(y0 + V3(x, 4.2, 0)) * ANG(0, RAD(90), 0), C.steelLight, M.Metal)
		for _, z in ipairs({ -2.6, 2.6 }) do
			part(f, "ParallelPost", V3(0.3, 4, 0.3), CF(y0 + V3(x, 2.25, z)), C.black, M.Metal)
		end
	end
	vcyl(f, "Tire", 1.7, 6.4, CF(y0 + V3(-6, 0.25, 12)), Color3.fromRGB(26, 26, 28), M.Rubber, { collide = true })
	vcyl(f, "TireInner", 0.05, 3.4, CF(y0 + V3(-6, 1.96, 12)), Color3.fromRGB(10, 10, 12), M.Rubber)
	for k = 0, 2 do
		blob(f, "Sandbag", V3(2.6, 1.2, 1.4), CF(y0 + V3(-11, 0.85 + k * 1.05, 18)) * ANG(0, RAD(k * 20), 0), Color3.fromRGB(70, 74, 52), M.Fabric)
	end
	local ysign = part(f, "YardSign", V3(10, 2.2, 0.3), CF(y0 + V3(0, 6, 22.6)), Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	for _, x in ipairs({ -4.8, 4.8 }) do
		part(f, "YardSignPost", V3(0.3, 5, 0.3), CF(y0 + V3(x, 2.5, 22.6)), C.black, M.Metal)
	end
	GymDecor.Sign(ysign, Enum.NormalId.Back, "OUTDOOR TRAINING YARD", C.gold, Color3.fromRGB(18, 18, 22), 30)
	GymDecor.Sign(ysign, Enum.NormalId.Front, "OUTDOOR TRAINING YARD", C.gold, Color3.fromRGB(18, 18, 22), 30)

	-- street lights along the roadwork loop (loop road: x/z = +-160 / 120 / -190, 10 wide)
	local lights = folder(f, "LoopLights")
	for _, x in ipairs({ -120, -60, 60, 120 }) do
		streetLight(lights, V3(x, 0, 127.5), V3(0, 0, -1), true)
		streetLight(lights, V3(x, 0, -197.5), V3(0, 0, 1), true)
	end
	for _, z in ipairs({ 70, 0, -70, -140 }) do
		streetLight(lights, V3(167.5, 0, z), V3(-1, 0, 0), true)
		streetLight(lights, V3(-167.5, 0, z), V3(1, 0, 0), true)
	end
	for _, c in ipairs({ { 167.5, 127.5 }, { -167.5, 127.5 }, { 167.5, -197.5 }, { -167.5, -197.5 } }) do
		streetLight(lights, V3(c[1], 0, c[2]), V3(-math.sign(c[1]), 0, -math.sign(c[2])).Unit, true)
	end
end

------------------------------------------------------------------------
-- South: Champion Ave and Main Street with shops
------------------------------------------------------------------------
local SHOPS = {
	{ x0 = -300, x1 = -262, h = 14, color = Color3.fromRGB(236, 234, 228), sign = "CHAMP'S DINER", signBg = Color3.fromRGB(190, 20, 30), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(200, 30, 36), neon = true },
	{ x0 = -256, x1 = -222, h = 16, color = Color3.fromRGB(70, 72, 78), sign = "IRON SUPPLEMENTS", signBg = Color3.fromRGB(16, 18, 20), signFg = Color3.fromRGB(80, 220, 110), awning = Color3.fromRGB(30, 110, 60) },
	{ x0 = -216, x1 = -176, h = 18, color = Color3.fromRGB(32, 32, 36), sign = "WCB PRO SHOP - GLOVES & GEAR", signBg = Color3.fromRGB(14, 14, 16), signFg = C.gold, awning = Color3.fromRGB(20, 20, 24) },
	{ x0 = -170, x1 = -126, h = 34, color = Color3.fromRGB(134, 72, 56), mat = M.Brick, sign = "CORNER CAFE", signBg = Color3.fromRGB(60, 40, 30), signFg = Color3.fromRGB(255, 230, 190), awning = Color3.fromRGB(90, 60, 40), floors = 3 },
	{ x0 = -120, x1 = -90, h = 14, color = Color3.fromRGB(200, 222, 240), sign = "SPIN CITY LAUNDROMAT", signBg = Color3.fromRGB(40, 110, 200), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(40, 110, 200) },
	{ x0 = -84, x1 = -56, h = 16, color = Color3.fromRGB(40, 32, 52), sign = "INK & IRON TATTOO", signBg = Color3.fromRGB(20, 14, 26), signFg = Color3.fromRGB(220, 90, 255), awning = Color3.fromRGB(70, 30, 90), neon = true },
	{ x0 = -50, x1 = -18, h = 15, color = Color3.fromRGB(244, 222, 180), sign = "SUNRISE BAKERY", signBg = Color3.fromRGB(250, 240, 220), signFg = Color3.fromRGB(170, 90, 40), awning = Color3.fromRGB(240, 170, 60) },
	{ x0 = -12, x1 = 12, h = 22, color = Color3.fromRGB(26, 26, 30), sign = "WCB ARENA TICKETS", signBg = Color3.fromRGB(150, 16, 24), signFg = Color3.fromRGB(255, 220, 90), awning = Color3.fromRGB(150, 16, 24), marquee = true },
	{ x0 = 18, x1 = 56, h = 14, color = Color3.fromRGB(220, 220, 214), sign = "CORNER STORE 24/7", signBg = Color3.fromRGB(30, 120, 60), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(30, 120, 60) },
	{ x0 = 62, x1 = 96, h = 15, color = Color3.fromRGB(176, 60, 44), mat = M.Brick, sign = "TONY'S PIZZA", signBg = Color3.fromRGB(20, 110, 50), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(200, 40, 40), neon = true },
	{ x0 = 102, x1 = 150, h = 42, color = Color3.fromRGB(150, 150, 156), mat = M.Concrete, sign = "RIVERSIDE APARTMENTS", signBg = Color3.fromRGB(30, 34, 40), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(30, 34, 40), floors = 4 },
	{ x0 = 156, x1 = 196, h = 22, color = Color3.fromRGB(220, 210, 190), mat = M.Limestone, sign = "BOXING HALL OF FAME MUSEUM", signBg = Color3.fromRGB(20, 20, 24), signFg = C.gold, awning = Color3.fromRGB(20, 20, 24), columns = true },
	{ x0 = 256, x1 = 300, h = 16, color = Color3.fromRGB(220, 200, 150), sign = "STARLIGHT MOTEL", signBg = Color3.fromRGB(16, 20, 40), signFg = Color3.fromRGB(255, 120, 180), awning = Color3.fromRGB(40, 60, 120), neon = true, poleSign = "MOTEL" },
}

local FRONT_Z = 187 -- shop fronts face north (-Z) towards the gym; south sidewalk is z 183..187

local function shop(f, d, rng)
	local w = d.x1 - d.x0
	local cx = (d.x0 + d.x1) / 2
	local depth = 30
	local h = d.h
	local body = part(f, "Building", V3(w, h, depth), CF(cx, h / 2, FRONT_Z + depth / 2), d.color, d.mat or M.SmoothPlastic, { collide = true })
	part(f, "Cornice", V3(w + 0.8, 0.9, depth + 0.8), CF(cx, h + 0.45, FRONT_Z + depth / 2), Color3.fromRGB(60, 58, 56), M.Concrete)
	-- storefront: dark interior, glass, mullions, door and kickplate
	local sfW = w - 4
	part(f, "ShopInterior", V3(sfW, 7, 0.12), CF(cx, 4.2, FRONT_Z - 0.07), Color3.fromRGB(36, 40, 48), M.SmoothPlastic)
	part(f, "ShopWindow", V3(sfW, 7, 0.1), CF(cx, 4.2, FRONT_Z - 0.2), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.55, reflect = 0.12, shadow = false })
	local n = math.max(1, math.floor(sfW / 6))
	for k = 0, n do
		part(f, "Mullion", V3(0.3, 7, 0.25), CF(d.x0 + 2 + k * sfW / n, 4.2, FRONT_Z - 0.2), Color3.fromRGB(30, 30, 34), M.Metal)
	end
	part(f, "ShopDoor", V3(3.2, 6.6, 0.15), CF(cx + w * 0.22, 3.9, FRONT_Z - 0.32), Color3.fromRGB(28, 28, 32), M.Metal)
	part(f, "Kickplate", V3(sfW, 0.7, 0.3), CF(cx, 0.65, FRONT_Z - 0.15), Color3.fromRGB(40, 40, 44), M.Metal)
	-- warm light spilling out of the shop at night
	local glow = point(emitter(f, CF(cx, 5, FRONT_Z - 1.2)), Color3.fromRGB(255, 214, 160), 16, 0.9)
	glow.Enabled = false
	tag(glow, "NightLight")
	-- awning and sign band
	part(f, "ShopAwning", V3(w - 1.5, 0.35, 4.2), CF(cx, 8.6, FRONT_Z - 1.9) * ANG(RAD(-14), 0, 0), d.awning, M.Fabric)
	local signPart = part(f, "ShopSign", V3(w - 3, 2.6, 0.4), CF(cx, 10.9, FRONT_Z - 0.25), d.signBg, M.SmoothPlastic)
	local sg = gui(signPart, Enum.NormalId.Front, 20, 0, 700)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = d.signBg })
	label(sg, d.sign, { TextColor3 = d.signFg, Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1) })
	if d.neon then
		neonOutline(f, CF(cx, 10.9, FRONT_Z - 0.56), w - 2.6, 2.9, d.signFg)
	end
	-- upper floors
	local wy0 = d.marquee and 16 or (d.columns and 14.6 or 13)
	local rows = d.floors or math.floor((h - 1.5 - wy0) / 5.5)
	if rows >= 1 then
		windowGrid(body, Enum.NormalId.Front, h, wy0, h - 1.5, rows, math.max(2, math.floor(w / 7)), rng, 0.4)
	end
	if d.marquee then
		local mq = part(f, "Marquee", V3(w + 2, 3.2, 3), CF(cx, 13.6, FRONT_Z - 1.6), Color3.fromRGB(20, 20, 24), M.Metal)
		local msg = gui(mq, Enum.NormalId.Front, 20, 0, 700)
		frame(msg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(250, 246, 230) })
		label(msg, "SAT: VEGA vs KOVAC  -  WORLD TITLE", { TextColor3 = Color3.fromRGB(20, 20, 24), Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15) })
		for k = 0, 7 do
			ball(f, "MarqueeBulb", 0.35, CF(cx - w / 2 - 0.6 + k * (w + 1.2) / 7, 15.35, FRONT_Z - 3.0), Color3.fromRGB(255, 230, 150), M.Neon, { shadow = false })
		end
	end
	if d.columns then
		part(f, "MuseumSteps", V3(w - 6, 0.8, 3.6), CF(cx, 0.4, FRONT_Z - 1.8), Color3.fromRGB(200, 196, 186), M.Limestone, { collide = true })
		for k = 0, 3 do
			vcyl(f, "MuseumColumn", 11.7, 1.4, CF(d.x0 + 6 + k * (w - 12) / 3, 0.8, FRONT_Z - 2.6), Color3.fromRGB(235, 228, 210), M.Limestone, { collide = true })
		end
		part(f, "Pediment", V3(w - 4, 1.4, 3.8), CF(cx, 13.2, FRONT_Z - 1.8), Color3.fromRGB(235, 228, 210), M.Limestone)
	end
	if d.poleSign then
		local px = d.x0 + 3
		part(f, "PoleSignPost", V3(0.6, 24, 0.6), CF(px, 12, FRONT_Z - 2.5), POLE, M.Metal, { collide = true })
		local ps = part(f, "PoleSign", V3(1, 9, 3.6), CF(px, 20, FRONT_Z - 2.5), Color3.fromRGB(16, 20, 40), M.SmoothPlastic)
		local txt = table.concat(string.split(d.poleSign, ""), "\n")
		GymDecor.Sign(ps, Enum.NormalId.Left, txt, d.signFg, Color3.fromRGB(16, 20, 40), 20)
		GymDecor.Sign(ps, Enum.NormalId.Right, txt, d.signFg, Color3.fromRGB(16, 20, 40), 20)
		for _, s in ipairs({ -1, 1 }) do
			neonOutline(f, CF(px + s * 0.62, 20, FRONT_Z - 2.5) * ANG(0, RAD(90 * s), 0), 3.5, 8.9, d.signFg)
		end
	end
	if rng:NextNumber() < 0.7 then
		part(f, "RoofUnit", V3(5, 2.4, 4), CF(cx + rng:NextNumber(-w / 4, w / 4), h + 2.1, FRONT_Z + depth * 0.6), Color3.fromRGB(196, 198, 202), M.Metal)
	end
	return body
end

local function gasStation(f)
	local cx, cz = 226, 202
	slab(f, "GasApron", 200, 252, FRONT_Z, 221, 0.2, Color3.fromRGB(150, 150, 152), M.Concrete)
	-- canopy on four pillars with a red fascia stripe and light panels underneath
	part(f, "GasCanopy", V3(40, 1.6, 20), CF(cx, 14.2, cz), C.white, M.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		part(f, "GasFascia", V3(40.3, 0.8, 0.2), CF(cx, 14.2, cz + s * 10.05), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
		part(f, "GasFascia", V3(0.2, 0.8, 20.3), CF(cx + s * 20.05, 14.2, cz), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	end
	for _, x in ipairs({ -12, 0, 12 }) do
		part(f, "CanopyPanel", V3(6, 0.08, 3), CF(cx + x, 13.36, cz), Color3.fromRGB(245, 248, 255), M.Neon, { shadow = false })
	end
	for _, x in ipairs({ -14, 14 }) do
		for _, z in ipairs({ -6, 6 }) do
			part(f, "GasPillar", V3(1, 13, 1), CF(cx + x, 6.7, cz + z), C.white, M.SmoothPlastic, { collide = true })
		end
	end
	for _, x in ipairs({ -10, 0, 10 }) do
		part(f, "PumpIsland", V3(3, 0.5, 8), CF(cx + x, 0.45, cz), Color3.fromRGB(190, 186, 180), M.Concrete, { collide = true })
		for _, z in ipairs({ -2, 2 }) do
			local pump = part(f, "Pump", V3(1.6, 5, 1.2), CF(cx + x, 3.2, cz + z), Color3.fromRGB(200, 30, 36), M.SmoothPlastic, { collide = true })
			GymDecor.Sign(pump, Enum.NormalId.Front, "3.49", C.gold, C.black, 40)
		end
	end
	for _, x in ipairs({ -8, 8 }) do
		spot(emitter(f, CF(cx + x, 12.8, cz)), Enum.NormalId.Bottom, Color3.fromRGB(240, 245, 255), 26, 1.6, 120)
	end
	-- the shop behind the pumps and the price pylon by the street
	part(f, "GasShop", V3(26, 11, 14), CF(cx, 5.5, cz + 18), Color3.fromRGB(230, 230, 226), M.SmoothPlastic, { collide = true })
	local gs = part(f, "GasShopSign", V3(18, 2.2, 0.3), CF(cx, 9.4, cz + 10.85), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	GymDecor.Sign(gs, Enum.NormalId.Front, "FUEL & GO - SNACKS - ICE", Color3.new(1, 1, 1), Color3.fromRGB(200, 30, 36), 20)
	part(f, "GasShopWindow", V3(20, 5, 0.1), CF(cx, 3.6, cz + 10.9), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.45, shadow = false })
	local py = V3(cx - 25, 0, cz - 9)
	part(f, "PylonPole", V3(0.8, 16, 0.8), CF(py + V3(0, 8, 0)), C.steel, M.Metal, { collide = true })
	local pylon = part(f, "Pylon", V3(6, 6, 1), CF(py + V3(0, 17, 0)), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local psg = gui(pylon, face, 20, 0, 700)
		frame(psg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 30, 36) })
		label(psg, "GAS", { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.8, 0.4), Position = UDim2.fromScale(0.1, 0.05) })
		label(psg, "3.49", { TextColor3 = C.gold, Font = Enum.Font.Code, Size = UDim2.fromScale(0.8, 0.45), Position = UDim2.fromScale(0.1, 0.5) })
	end
end

local function buildSouth(root)
	local f = folder(root, "MainStreet")
	local rng = Random.new(1987)
	-- Champion Ave: from the loop road (z 125) to Main Street (z 167)
	slab(f, "ChampionAve", -8, 8, 125, 167, 0.3, ASPHALT, M.Asphalt)
	for z = 130, 160, 6 do
		part(f, "LaneDash", V3(0.35, 0.03, 3), CF(0, 0.315, z), LINE_YELLOW, M.SmoothPlastic)
	end
	slab(f, "AveSidewalk", -11, -8, 125, 163, SW_H, SIDEWALK, M.Concrete)
	slab(f, "AveSidewalk", 8, 11, 125, 163, SW_H, SIDEWALK, M.Concrete)
	local ave = part(f, "StreetSign", V3(5, 1, 0.12), CF(-10.8, 8.6 + SW_H, 128), Color3.fromRGB(30, 110, 60), M.SmoothPlastic)
	part(f, "StreetSignPole", V3(0.25, 9, 0.25), CF(-10.8, 4.5 + SW_H, 128.2), C.steel, M.Metal)
	GymDecor.Sign(ave, Enum.NormalId.Front, "CHAMPION AVE", Color3.new(1, 1, 1), Color3.fromRGB(30, 110, 60), 40)
	GymDecor.Sign(ave, Enum.NormalId.Back, "CHAMPION AVE", Color3.new(1, 1, 1), Color3.fromRGB(30, 110, 60), 40)
	-- Main Street along X (z 167..183) with sidewalks, centre line, crosswalks and parked cars
	slab(f, "MainStreet", -330, 330, 167, 183, 0.3, ASPHALT, M.Asphalt)
	for x = -320, 320, 10 do
		if math.abs(x) > 10 then
			part(f, "CenterDash", V3(4, 0.03, 0.35), CF(x, 0.315, 175), LINE_YELLOW, M.SmoothPlastic)
		end
	end
	for _, seg in ipairs({ { -330, -269 }, { -255, -8 }, { 8, 330 } }) do
		slab(f, "SidewalkN", seg[1], seg[2], 163, 167, SW_H, SIDEWALK, M.Concrete)
	end
	slab(f, "SidewalkS", -330, 330, 183, FRONT_Z, SW_H, SIDEWALK, M.Concrete)
	for _, x in ipairs({ -12.5, 12.5 }) do
		crosswalk(f, V3(x, 0.32, 175), false, 16, 5)
	end
	for i, x in ipairs({ -244, -150, -36, 78, 132, 284 }) do
		car(f, CF(x, 0.3, 179.6) * ANG(0, RAD(i % 2 == 0 and 90 or -90), 0), CAR_COLORS[(i + 2) % #CAR_COLORS + 1])
	end
	-- street lights between the sidewalk trees, plus a few on the shop side
	for _, x in ipairs({ -278, -188, -108, 92, 172, 252 }) do
		streetLight(f, V3(x, SW_H, 164.2), V3(0, 0, 1), true)
	end
	for _, x in ipairs({ -236, -34, 153 }) do
		streetLight(f, V3(x, SW_H, 185.8), V3(0, 0, -1), false)
	end
	for _, d in ipairs(SHOPS) do
		shop(f, d, rng)
	end
	gasStation(f)
	-- trees in sidewalk pits along the north sidewalk
	for x = -300, 300, 40 do
		if math.abs(x) > 20 then
			local tx = x + 12
			if tx < -272 or tx > -252 then -- keep the Oak Street junction clear
				part(f, "TreePit", V3(2.4, 0.05, 2.4), CF(tx, SW_H + 0.02, 165), Color3.fromRGB(70, 52, 36), M.Ground)
				roundTree(f, V3(tx, SW_H, 165), 9, rng)
			end
		end
	end
end

------------------------------------------------------------------------
-- West: Oak Street with houses (x = -262, from Main Street north)
------------------------------------------------------------------------
local HOUSE_COLORS = {
	Color3.fromRGB(220, 206, 180), Color3.fromRGB(176, 196, 214), Color3.fromRGB(214, 180, 170), Color3.fromRGB(200, 214, 180),
	Color3.fromRGB(238, 236, 228), Color3.fromRGB(190, 170, 200), Color3.fromRGB(150, 168, 190),
}

local function house(f, center, front, rng, i)
	local W, D, H, R = 16, 14, 10, 5
	local base = CFrame.lookAt(center, center + front) -- local -Z = front, X = along the street
	local color = HOUSE_COLORS[(i - 1) % #HOUSE_COLORS + 1]
	part(f, "House", V3(W, H, D), base * CF(0, H / 2, 0), color, M.WoodPlanks, { collide = true })
	-- gable roof from two wedges, low edges at the front and back walls
	local roofColor = ({ Color3.fromRGB(80, 50, 40), Color3.fromRGB(60, 62, 70), Color3.fromRGB(110, 60, 44) })[i % 3 + 1]
	local a = (base * CF(0, H + R / 2, -D / 4)).Position
	local b = (base * CF(0, H + R / 2, D / 4)).Position
	part(f, "Roof", V3(W + 1, R, D / 2 + 0.6), CFrame.lookAt(a, a + front), roofColor, M.Slate, { class = "WedgePart", collide = true })
	part(f, "Roof", V3(W + 1, R, D / 2 + 0.6), CFrame.lookAt(b, b - front), roofColor, M.Slate, { class = "WedgePart", collide = true })
	part(f, "Chimney", V3(1.6, 4, 1.6), base * CF(W * 0.3, H + R - 0.5, D * 0.15), Color3.fromRGB(130, 70, 56), M.Brick)
	-- door, porch, windows
	part(f, "Door", V3(2.4, 5.4, 0.2), base * CF(-W * 0.18, 3.3, -D / 2 - 0.1), ({ C.red, Color3.fromRGB(30, 60, 120), Color3.fromRGB(30, 90, 60) })[i % 3 + 1], M.Wood)
	part(f, "Porch", V3(6, 0.6, 3), base * CF(-W * 0.18, 0.3, -D / 2 - 1.5), Color3.fromRGB(150, 140, 130), M.Concrete, { collide = true })
	part(f, "PorchRoof", V3(6, 0.3, 3.2), base * CF(-W * 0.18, 6.9, -D / 2 - 1.5), color:Lerp(Color3.new(0, 0, 0), 0.3), M.WoodPlanks)
	for _, x in ipairs({ W * 0.12, W * 0.34 }) do
		part(f, "HouseWindow", V3(2.6, 2.8, 0.15), base * CF(x, 4.6, -D / 2 - 0.08), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.25 })
		part(f, "WindowTrim", V3(3.0, 0.3, 0.3), base * CF(x, 3.1, -D / 2 - 0.15), C.white, M.Wood)
	end
	-- mailbox at the kerb, front path and a hedge
	local mb = base * CF(W * 0.4, 0, -D / 2 - 9)
	part(f, "MailboxPost", V3(0.25, 3, 0.25), mb * CF(0, 1.5 + SW_H, 0), C.wood, M.Wood)
	part(f, "Mailbox", V3(0.8, 0.8, 1.4), mb * CF(0, 3.3 + SW_H, 0), ({ C.black, C.blue, C.red })[i % 3 + 1], M.Metal)
	part(f, "FrontPath", V3(2.4, 0.12, 8), base * CF(-W * 0.18, 0.06, -D / 2 - 7), Color3.fromRGB(180, 176, 168), M.Concrete)
	blob(f, "Hedge", V3(5, 2.2, 1.8), base * CF(W * 0.3, 1.1, -D / 2 - 1.5), Color3.fromRGB(50, 110, 55), M.Grass)
	if rng:NextNumber() < 0.5 then
		car(f, base * CF(W / 2 + 4.5, 0, -2) * ANG(0, RAD(180), 0), CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)])
	end
end

local function buildWest(root)
	local f = folder(root, "Residential")
	local rng = Random.new(808)
	local sx = -262
	slab(f, "OakStreet", sx - 7, sx + 7, -240, 167, 0.3, ASPHALT, M.Asphalt)
	for z = -230, 160, 12 do
		part(f, "LaneDash", V3(0.35, 0.03, 4), CF(sx, 0.315, z), C.white, M.SmoothPlastic)
	end
	slab(f, "Sidewalk", sx - 10, sx - 7, -240, 163, SW_H, SIDEWALK, M.Concrete)
	slab(f, "Sidewalk", sx + 7, sx + 10, -240, -41, SW_H, SIDEWALK, M.Concrete)
	slab(f, "Sidewalk", sx + 7, sx + 10, -29, 163, SW_H, SIDEWALK, M.Concrete)
	-- connector road from Oak Street to the loop's west side
	slab(f, "ConnectorRoad", sx + 7, -165, -41, -29, 0.3, ASPHALT, M.Asphalt)
	for x = -245, -175, 10 do
		part(f, "LaneDash", V3(4, 0.03, 0.35), CF(x, 0.315, -35), C.white, M.SmoothPlastic)
	end
	local i = 0
	for z = -200, 150, 50 do
		i += 1
		house(f, V3(sx + 25, 0, z), V3(-1, 0, 0), rng, i)
	end
	for z = -175, 125, 50 do
		i += 1
		house(f, V3(sx - 25, 0, z), V3(1, 0, 0), rng, i)
	end
	for k, z in ipairs({ -190, -110, -60, 10, 90, 140 }) do
		streetLight(f, V3(sx + 9.2, SW_H, z), V3(-1, 0, 0), k % 2 == 1)
	end
	local s = part(f, "StreetSign", V3(5, 1, 0.12), CF(sx + 9.4, 8.6, -44) * ANG(0, RAD(90), 0), Color3.fromRGB(30, 110, 60), M.SmoothPlastic)
	part(f, "StreetSignPole", V3(0.25, 9, 0.25), CF(sx + 9.4, 4.5 + SW_H, -44), C.steel, M.Metal)
	GymDecor.Sign(s, Enum.NormalId.Front, "OAK STREET", Color3.new(1, 1, 1), Color3.fromRGB(30, 110, 60), 40)
	GymDecor.Sign(s, Enum.NormalId.Back, "OAK STREET", Color3.new(1, 1, 1), Color3.fromRGB(30, 110, 60), 40)
end

------------------------------------------------------------------------
-- East: Riverside Park with a basketball court, fountain, paths, picnic tables and trees
------------------------------------------------------------------------
local function segDist(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function buildEast(root)
	local f = folder(root, "Park")
	local rng = Random.new(2024)
	-- basketball court with an apron and a chain-link fence (gate on the south side)
	local ct = V3(262, 0, -45)
	part(f, "CourtApron", V3(40, 0.2, 24), CF(ct + V3(0, 0.1, 0)), Color3.fromRGB(150, 150, 150), M.Concrete, { collide = true })
	part(f, "Court", V3(30, 0.25, 18), CF(ct + V3(0, 0.125, 0)), Color3.fromRGB(46, 92, 140), M.SmoothPlastic, { collide = true })
	local lines = part(f, "CourtLines", V3(30, 0.02, 18), CF(ct + V3(0, 0.26, 0)), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	local lg = gui(lines, Enum.NormalId.Top, 10, 1)
	local function box(xs, ys, w, h)
		local fr = frame(lg, { Size = UDim2.fromScale(w, h), Position = UDim2.fromScale(xs, ys), BackgroundTransparency = 1 })
		local st = Instance.new("UIStroke")
		st.Color = C.white
		st.Thickness = 3
		st.Parent = fr
		return fr
	end
	box(0.02, 0.03, 0.96, 0.94)
	box(0.5, 0.03, 0.0, 0.94)
	local circle = box(0.43, 0.38, 0.14, 0.24)
	Instance.new("UICorner", circle).CornerRadius = UDim.new(0.5, 0)
	box(0.02, 0.33, 0.18, 0.34)
	box(0.8, 0.33, 0.18, 0.34)
	for _, s in ipairs({ -1, 1 }) do
		local hx = ct.X + s * 16.5
		part(f, "HoopPole", V3(0.5, 10, 0.5), CF(hx, 5, ct.Z), C.steel, M.Metal, { collide = true })
		part(f, "HoopArm", V3(2, 0.4, 0.4), CF(hx - s * 1, 9.6, ct.Z), C.steel, M.Metal)
		part(f, "Backboard", V3(0.2, 3.2, 5.2), CF(hx - s * 2, 9.8, ct.Z), C.white, M.SmoothPlastic, { transparency = 0.15 })
		for k = 0, 7 do
			local a = k * RAD(45)
			part(f, "Rim", V3(0.12, 0.12, 0.62), CF(hx - s * 2.85 + math.cos(a) * 0.75, 8.9, ct.Z + math.sin(a) * 0.75) * ANG(0, -a, 0), Color3.fromRGB(240, 110, 30), M.Metal)
		end
	end
	local fenceColor = Color3.fromRGB(150, 155, 160)
	local function fence(cx, cz, sx, sz)
		part(f, "CourtFence", V3(sx, 6, sz), CF(ct + V3(cx, 3, cz)), fenceColor, M.DiamondPlate, { transparency = 0.75, shadow = false, collide = true })
	end
	fence(0, -11.6, 39.4, 0.15)
	fence(-11.3, 11.6, 16.8, 0.15)
	fence(11.3, 11.6, 16.8, 0.15)
	fence(-19.6, 0, 0.15, 23.4)
	fence(19.6, 0, 0.15, 23.4)
	ball(f, "Basketball", 1.0, CF(ct + V3(6, 0.75, 3)), Color3.fromRGB(230, 110, 30), M.Rubber)
	-- fountain plaza
	local fo = V3(290, 0, 60)
	part(f, "FountainPlaza", V3(34, 0.2, 34), CF(fo + V3(0, 0.1, 0)), Color3.fromRGB(196, 186, 170), M.Pavement, { collide = true })
	vcyl(f, "FountainBasin", 1.6, 18, CF(fo), Color3.fromRGB(170, 168, 162), M.Granite, { collide = true })
	vcyl(f, "FountainWater", 0.2, 16.6, CF(fo + V3(0, 1.45, 0)), Color3.fromRGB(70, 150, 210), M.Glass, { transparency = 0.25 })
	vcyl(f, "FountainPillar", 4.5, 2, CF(fo), Color3.fromRGB(180, 178, 172), M.Granite)
	vcyl(f, "FountainBowl", 0.8, 6.4, CF(fo + V3(0, 4.5, 0)), Color3.fromRGB(180, 178, 172), M.Granite)
	vcyl(f, "FountainBowlWater", 0.1, 5.8, CF(fo + V3(0, 5.25, 0)), Color3.fromRGB(80, 160, 220), M.Glass, { transparency = 0.2 })
	local jet = part(f, "FountainJet", V3(0.5, 0.5, 0.5), CF(fo + V3(0, 5.6, 0)), C.white, M.SmoothPlastic, { transparency = 1, shadow = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 40
	pe.Lifetime = NumberRange.new(0.9, 1.3)
	pe.Speed = NumberRange.new(10, 13)
	pe.SpreadAngle = Vector2.new(9, 9)
	pe.Acceleration = Vector3.new(0, -28, 0)
	pe.Size = NumberSequence.new(0.45, 0.2)
	pe.Transparency = NumberSequence.new(0.3, 0.8)
	pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	pe.LightEmission = 0.3
	pe.Parent = jet
	for k = 0, 5 do
		local a = k * RAD(60) + RAD(30)
		GymDecor.Bench(f, fo + V3(math.cos(a) * 14, 0.2, math.sin(a) * 14), RAD(90) - a, 5, C.wood)
	end
	-- paths: from the loop road, to Main Street, and down to the court gate
	local paths = {
		{ V3(165, 0, 60), V3(273, 0, 60) },
		{ V3(290, 0, 77), V3(290, 0, 163) },
		{ V3(284, 0, 44), V3(262, 0, -33) },
	}
	for _, seg in ipairs(paths) do
		local a, b = seg[1], seg[2]
		part(f, "ParkPath", V3(5, 0.14, (b - a).Magnitude), CFrame.lookAt((a + b) / 2 + V3(0, 0.07, 0), b + V3(0, 0.07, 0)), Color3.fromRGB(196, 176, 140), M.Pavement)
	end
	-- picnic tables and lamp posts
	local picnic = { V3(252, 0, 22), V3(322, 0, 28), V3(318, 0, 104), V3(256, 0, 104) }
	for k, p in ipairs(picnic) do
		picnicTable(f, p, RAD(k * 37))
	end
	for _, p in ipairs({ V3(222, 0, 64), V3(294, 0, 120), V3(277, 0, 10) }) do
		streetLight(f, p, V3(0, 0, -1), true)
	end
	-- trees anywhere else in the park
	local function clear(p)
		if (p - fo).Magnitude < 25 then
			return false
		end
		if math.abs(p.X - ct.X) < 27 and math.abs(p.Z - ct.Z) < 19 then
			return false
		end
		for _, seg in ipairs(paths) do
			if segDist(p, seg[1], seg[2]) < 8 then
				return false
			end
		end
		for _, q in ipairs(picnic) do
			if (p - q).Magnitude < 9 then
				return false
			end
		end
		return true
	end
	local n, tries = 0, 0
	while n < 34 and tries < 400 do
		tries += 1
		local p = V3(rng:NextNumber(234, 340), 0, rng:NextNumber(-220, 150))
		if clear(p) then
			n += 1
			if n % 2 == 0 then
				pine(f, p, rng:NextNumber(14, 22))
			else
				roundTree(f, p, rng:NextNumber(10, 15), rng)
			end
		end
	end
	local ps = part(f, "ParkSign", V3(10, 2.4, 0.4), CF(230, 4, 60) * ANG(0, RAD(90), 0), Color3.fromRGB(60, 40, 26), M.Wood)
	GymDecor.Sign(ps, Enum.NormalId.Back, "RIVERSIDE PARK", Color3.fromRGB(255, 230, 170), Color3.fromRGB(60, 40, 26), 30)
	GymDecor.Sign(ps, Enum.NormalId.Front, "RIVERSIDE PARK", Color3.fromRGB(255, 230, 170), Color3.fromRGB(60, 40, 26), 30)
	for _, dz in ipairs({ -4.5, 4.5 }) do
		part(f, "ParkSignPost", V3(0.4, 4, 0.4), CF(230, 2, 60 + dz), Color3.fromRGB(60, 40, 26), M.Wood)
	end
end

------------------------------------------------------------------------
-- North: the WCB Arena on the skyline
------------------------------------------------------------------------
local function buildArena(root)
	local f = folder(root, "Arena")
	local c = V3(0, 0, -322)
	local R, H = 62, 38
	local segs = 20
	for k = 0, segs - 1 do
		local a = (k + 0.5) / segs * math.pi * 2
		local dir = V3(math.sin(a), 0, math.cos(a))
		local pos = c + dir * R + V3(0, H / 2, 0)
		local w = 2 * R * math.sin(math.pi / segs) + 0.8
		local cf = CFrame.lookAt(pos, pos + dir)
		part(f, "ArenaWall", V3(w, H, 3), cf, Color3.fromRGB(56, 58, 66), M.Concrete, { collide = true })
		part(f, "ArenaGlass", V3(w, 8, 0.4), cf * CF(0, -H / 2 + 7, -1.6), Color3.fromRGB(120, 170, 220), M.Glass, { transparency = 0.15, reflect = 0.2 })
		part(f, "ArenaLED", V3(w, 1.2, 0.3), cf * CF(0, H / 2 - 2, -1.65), k % 2 == 0 and Color3.fromRGB(255, 40, 50) or C.gold, M.Neon, { shadow = false })
		part(f, "ArenaRib", V3(0.8, H - 4, 0.8), cf * CF(w / 2 - 0.4, -1, -1.8), Color3.fromRGB(80, 82, 90), M.Metal)
	end
	vcyl(f, "ArenaRoof", 2, 2 * R + 4, CF(c + V3(0, H, 0)), Color3.fromRGB(70, 72, 80), M.Metal)
	blob(f, "ArenaDome", V3(2 * R - 10, 22, 2 * R - 10), CF(c + V3(0, H + 2, 0)), Color3.fromRGB(205, 210, 218), M.Metal)
	-- flat entrance block facing the gym (south), with the big screen, canopy, doors and banners
	local FZ = -254 -- facade plane
	part(f, "EntranceBlock", V3(64, 30, 16), CF(0, 15, FZ - 8), Color3.fromRGB(40, 42, 50), M.Concrete, { collide = true })
	part(f, "EntranceTrim", V3(64.4, 1, 16.4), CF(0, 30.5, FZ - 8), Color3.fromRGB(190, 20, 30), M.SmoothPlastic)
	local screen = part(f, "ArenaScreen", V3(40, 14, 1), CF(0, 21.5, FZ + 0.5), Color3.fromRGB(8, 8, 12), M.SmoothPlastic)
	local sg = gui(screen, Enum.NormalId.Back, 8, 0, 2000)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 12) })
	frame(sg, { Size = UDim2.fromScale(1, 0.22), BackgroundColor3 = Color3.fromRGB(190, 20, 30) })
	label(sg, "WCB ARENA", { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.02) })
	label(sg, "FIGHT NIGHT", { TextColor3 = C.gold, Size = UDim2.fromScale(0.9, 0.38), Position = UDim2.fromScale(0.05, 0.26) })
	label(sg, "SATURDAY  -  WORLD TITLE ON THE LINE", { TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.7) })
	neonOutline(f, CF(0, 21.5, FZ + 1.1), 40.4, 14.4, Color3.fromRGB(255, 60, 70))
	part(f, "EntranceCanopy", V3(44, 1.2, 10), CF(0, 12, FZ + 5), Color3.fromRGB(30, 30, 34), M.Metal)
	for _, x in ipairs({ -20, 20 }) do
		part(f, "CanopyPost", V3(1, 11.4, 1), CF(x, 5.7, FZ + 9.5), Color3.fromRGB(30, 30, 34), M.Metal, { collide = true })
	end
	for k = 0, 3 do
		part(f, "ArenaDoor", V3(6, 9, 0.3), CF(-13.5 + k * 9, 5.3, FZ + 0.15), Color3.fromRGB(160, 200, 230), M.Glass, { transparency = 0.3 })
	end
	part(f, "ArenaSteps", V3(56, 0.8, 6), CF(0, 0.4, FZ + 3), Color3.fromRGB(150, 148, 144), M.Concrete, { collide = true })
	for i, x in ipairs({ -26, 26 }) do
		local b = part(f, "ArenaBanner", V3(4, 14, 0.2), CF(x, 18, FZ + 0.1), i == 1 and Color3.fromRGB(190, 20, 30) or Color3.fromRGB(20, 40, 120), M.Fabric)
		GymDecor.Sign(b, Enum.NormalId.Back, i == 1 and "LIVE\nFIGHTS" or "WCB\nARENA", Color3.new(1, 1, 1), nil, 20)
	end
	spot(emitter(f, CF(0, 11, FZ + 6)), Enum.NormalId.Bottom, Color3.fromRGB(255, 225, 180), 24, 1.6, 110)
	-- plaza, approach road from the loop, light towers and flags
	slab(f, "ArenaPlaza", -50, 50, -252, -212, 0.2, Color3.fromRGB(176, 170, 160), M.Pavement)
	slab(f, "ArenaWay", -8, 8, -212, -195, 0.3, ASPHALT, M.Asphalt)
	for _, x in ipairs({ -46, 46 }) do
		local tw = V3(x, 0, -230)
		part(f, "LightTower", V3(1.4, 40, 1.4), CF(tw + V3(0, 20, 0)), Color3.fromRGB(70, 72, 80), M.Metal, { collide = true })
		part(f, "TowerLights", V3(8, 3, 1), CFrame.lookAt(tw + V3(0, 40, 0), V3(0, 10, FZ)), Color3.fromRGB(255, 255, 235), M.Neon, { shadow = false })
	end
	for i, x in ipairs({ -36, -28, 28, 36 }) do
		local base = V3(x, 0.2, -216)
		vcyl(f, "FlagPole", 18, 0.3, CF(base), C.steelLight, M.Metal, { collide = true })
		part(f, "ArenaFlag", V3(0.08, 3, 5), CF(base + V3(0, 16, -2.6)), (i == 2 or i == 3) and C.gold or C.red, M.Fabric, { shadow = false })
	end
	-- parking on both sides with a few cars
	local rng = Random.new(77)
	for _, side in ipairs({ -1, 1 }) do
		local lot = V3(side * 96, 0, -292)
		part(f, "ArenaParking", V3(60, 0.2, 60), CF(lot + V3(0, 0.1, 0)), ASPHALT, M.Asphalt, { collide = true })
		for row = 0, 1 do
			local rz = lot.Z - 15 + row * 28
			for k = 0, 8 do
				part(f, "BayLine", V3(0.3, 0.03, 10), CF(lot.X - 24 + k * 6, 0.215, rz), C.white, M.SmoothPlastic)
				if k < 8 and rng:NextNumber() < 0.55 then
					car(f, CF(lot.X - 21 + k * 6, 0.2, rz) * ANG(0, RAD(row == 0 and 0 or 180), 0), CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)])
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Skyline around the edges of the map
------------------------------------------------------------------------
local function buildSkyline(root)
	local f = folder(root, "Skyline")
	local rng = Random.new(31337)
	local center = V3(0, 0, -30)
	local function tower(pos, w, d, h)
		local look = V3(center.X - pos.X, 0, center.Z - pos.Z).Unit
		local cf = CFrame.lookAt(pos + V3(0, h / 2, 0), pos + V3(0, h / 2, 0) + look)
		local tone = rng:NextInteger(0, 3)
		local color = ({ Color3.fromRGB(70, 78, 92), Color3.fromRGB(110, 112, 120), Color3.fromRGB(56, 70, 90), Color3.fromRGB(150, 140, 126) })[tone + 1]
		local body = part(f, "Tower", V3(w, h, d), cf, color, tone == 2 and M.Glass or M.Concrete, { reflect = tone == 2 and 0.15 or 0 })
		windowGrid(body, Enum.NormalId.Front, h, 4, h - 3, math.floor(h / 10), math.max(3, math.floor(w / 6)), rng, 0.3)
		part(f, "TowerCap", V3(w * 0.6, 3, d * 0.6), cf * CF(0, h / 2 + 1.5, 0), color:Lerp(Color3.new(0, 0, 0), 0.2), M.Concrete)
		if h > 110 then
			part(f, "Antenna", V3(0.6, 18, 0.6), cf * CF(0, h / 2 + 12, 0), C.steelLight, M.Metal)
			ball(f, "AntennaLight", 1.2, cf * CF(0, h / 2 + 21.5, 0), Color3.fromRGB(255, 40, 40), M.Neon, { shadow = false })
		end
	end
	for x = -340, 340, 56 do
		if math.abs(x) > 80 then
			tower(V3(x + rng:NextNumber(-8, 8), 0, -396), rng:NextInteger(26, 40), 20, rng:NextInteger(70, 170))
		end
		tower(V3(x + rng:NextNumber(-8, 8), 0, 334), rng:NextInteger(24, 38), 20, rng:NextInteger(60, 150))
	end
	for z = -300, 260, 70 do
		tower(V3(364, 0, z + rng:NextNumber(-10, 10)), 20, rng:NextInteger(26, 40), rng:NextInteger(60, 160))
		tower(V3(-364, 0, z + rng:NextNumber(-10, 10)), 20, rng:NextInteger(26, 40), rng:NextInteger(60, 160))
	end
end

------------------------------------------------------------------------
-- MapBuilder scatters trees around the loop; drop those standing where the town now is.
-- A tree's trunk and leaves share one XZ position, so both go together.
------------------------------------------------------------------------
local TREE_CLEAR = {
	{ -17, 17, 120, 170 }, -- Champion Ave and its sidewalks
	{ -52, -28, 120, 140 }, -- bus stop
	{ -260, -160, -48, -22 }, -- Oak Street connector road
	{ -58, 58, -265, -195 }, -- arena approach and plaza
	{ 160, 236, 52, 68 }, -- park path from the loop
	{ -127, -113, 120, 135 }, { -67, -53, 120, 135 }, { 53, 67, 120, 135 }, { 113, 127, 120, 135 }, -- south loop lights
	{ 160, 196, 120, 136 }, { -196, -160, 120, 136 }, -- south corner lights
}

local function clearTrees(gym)
	local removed = 0
	for _, child in ipairs(gym:GetChildren()) do
		if child:IsA("BasePart") and (child.Name == "Trunk" or child.Name == "Leaves") then
			local p = child.Position
			for _, z in ipairs(TREE_CLEAR) do
				if p.X > z[1] and p.X < z[2] and p.Z > z[3] and p.Z < z[4] then
					child:Destroy()
					removed += 1
					break
				end
			end
		end
	end
	return removed
end

------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------
function CityMap.Build(gym)
	local root = Instance.new("Folder")
	root.Name = "City"
	root.Parent = gym
	local sections = {
		{ "trees", function()
			clearTrees(gym)
		end },
		{ "campus", buildCampus }, { "south", buildSouth }, { "west", buildWest }, { "east", buildEast },
		{ "arena", buildArena }, { "skyline", buildSkyline },
	}
	for _, s in ipairs(sections) do
		local ok, err = pcall(s[2], root)
		if not ok then
			warn("[CityMap] " .. s[1] .. " failed: " .. tostring(err))
		end
	end
	return root
end

return CityMap
