-- CityMap: the town around the gym, at real-world scale (Config.City: 1 stud = 0.28 m). The gym
-- stays at the origin inside the roadwork loop (MapBuilder.Track builds the loop road); CityMap
-- builds everything else:
--   * the CAMPUS inside the loop: entrance plaza, member parking, Champions Plaza with the golden
--     glove monument, the outdoor yard, the training field north of the pool, the bus stop
--   * DOWNTOWN south of the loop: Champion Ave with the Walk of Fame, Main Street with its two rows
--     of shops (CityShops: walk-in interiors, the apartments, the gas station), the fire station,
--     2nd Street and the office towers behind it
--   * the RESIDENTIAL west: Oak Street's houses, Cedar Lane, the hills; Hillcrest Estates at the top
--   * the PARK and WATERFRONT east: Riverside Park (court, fountain, pond, bandstand, playground),
--     Riverside Drive, the promenade, boardwalk, pier and the river with the bridge and the far bank
--   * the ARENA district north: Arena Way, the plaza and the Grand Arena with its parking lots
--   * the GYM / INDUSTRIAL north-east: the Elite Performance Center, warehouses, a construction site
--   * billboards, the far skyline, the mountain training camp
-- Street lights and shop lights are tagged "NightLight"/"NightLens" (Ambience switches them at dusk),
-- neon signs "NeonFlicker". Player-specific pieces (homes, cars, fans, statue, sponsors) are built by
-- the client (CityVisuals) at the invisible Sites (CityKit.site); the travel code reads CityMap.Sites.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GymDecor = require(script.Parent:WaitForChild("GymDecor"))
local K = require(script.Parent:WaitForChild("CityKit"))
local CityShops = require(script.Parent:WaitForChild("CityShops"))
local CityHomes = require(script.Parent:WaitForChild("CityHomes"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local CityProps = require(Shared:WaitForChild("CityProps"))
local Signage = require(Shared:WaitForChild("Signage"))

local CityMap = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material
local C = K.C
local CITY = Config.City
local SW_H, ROAD_Y = K.SW_H, K.ROAD_Y
local part, cyl, vcyl, ball, blob, rod = K.part, K.cyl, K.vcyl, K.ball, K.blob, K.rod
local label, frame, gui, spot, point, emitter, tag = K.label, K.frame, K.gui, K.spot, K.point, K.emitter, K.tag
local folder, model, slab = K.folder, K.model, K.slab
local site, promptPart, lightZone, nightPoint = K.site, K.promptPart, K.lightZone, K.nightPoint

CityMap.Sites = K.Sites -- name -> CFrame (server side travel targets)
CityMap.HomeSpec = CityHomes.HomeSpec
CityMap.HomeKind = CityHomes.HomeKind
CityMap.EnterHome = CityHomes.Enter
CityMap.ReleaseHome = CityHomes.Release

local LOOP, MAIN, AVE = CITY.Loop, CITY.MainStreet, CITY.ChampionAve
local LW = LOOP.w / 2 -- 12.5
local INNER = 8 -- the loop's inner sidewalk width
local OUTER = 10 -- its outer sidewalk width

-- a strip of street lights along X at z, every `step`, arms over the road towards dir
local function lightsX(parent, x1, x2, z, dir, step, h, every)
	local k = 0
	for x = x1, x2, step do
		k += 1
		K.streetLight(parent, V3(x, SW_H, z), dir, (every or 2) == 1 or k % (every or 2) == 1, h)
	end
end
local function lightsZ(parent, z1, z2, x, dir, step, h, every)
	local k = 0
	for z = z1, z2, step do
		k += 1
		K.streetLight(parent, V3(x, SW_H, z), dir, (every or 2) == 1 or k % (every or 2) == 1, h)
	end
end

-- a row of street trees along X at z
local function treesX(parent, x1, x2, z, step, rng, skip)
	for x = x1, x2, step do
		local ok = true
		for _, s in ipairs(skip or {}) do
			if x > s[1] and x < s[2] then
				ok = false
			end
		end
		if ok then
			K.streetTree(parent, V3(x, SW_H, z), rng)
		end
	end
end
local function treesZ(parent, z1, z2, x, step, rng, skip)
	for z = z1, z2, step do
		local ok = true
		for _, s in ipairs(skip or {}) do
			if z > s[1] and z < s[2] then
				ok = false
			end
		end
		if ok then
			K.streetTree(parent, V3(x, SW_H, z), rng)
		end
	end
end

------------------------------------------------------------------------
-- The campus inside the loop
------------------------------------------------------------------------
local function buildCampus(root)
	local f = folder(root, "Campus")
	local rng = Random.new(42)
	local inZ = LOOP.z1 - LW - INNER -- 149.5: the inner sidewalk's north edge on the south road
	-- lawns everywhere between the gym's frontage and the inner sidewalks (the roads sit on them)
	K.lawn(f, -227.5, -24, 89.5, inZ, rng, { patches = 3 })
	K.lawn(f, 24, 227.5, 89.5, inZ, rng, { patches = 3 })
	K.lawn(f, -227.5, -112, -269.5, 89.5, rng, { patches = 4 })
	K.lawn(f, 112, 227.5, -269.5, 89.5, rng, { patches = 4 })
	K.lawn(f, -112, 112, -269.5, -148, rng, { patches = 2 })

	-- entrance plaza: from the gym's sidewalk (z 89.3) to the loop's inner sidewalk, a paved forecourt
	-- with planters, bollards, benches, flags and the welcome board; kept clear on the x -5..5 axis
	slab(f, "EntrancePlaza", -30, 30, 89.5, inZ, 0.3, K.PAVING, M.Pavement)
	slab(f, "PlazaBand", -30, 30, 118, 121, 0.31, Color3.fromRGB(120, 110, 100), M.Concrete)
	slab(f, "PlazaBand", -30, 30, 138, 141, 0.31, Color3.fromRGB(120, 110, 100), M.Concrete)
	for _, x in ipairs({ -20, 20 }) do
		K.planter(f, CF(x, 0.3, 100) * ANG(0, RAD(90), 0), 10, 2.6)
		K.planter(f, CF(x, 0.3, 128) * ANG(0, RAD(90), 0), 10, 2.6)
		K.bench(f, V3(x * 0.6, 0.3, 112), x < 0 and RAD(90) or RAD(-90), 6.4, C.wood)
		K.bench(f, V3(x * 0.6, 0.3, 132), x < 0 and RAD(90) or RAD(-90), 6.4, C.wood)
		K.bin(f, V3(x * 0.6, 0.3, 122))
		K.parkLamp(f, V3(x, 0.3, 112), true)
		K.parkLamp(f, V3(x, 0.3, 140), true)
	end
	for _, x in ipairs({ -8, 0, 8 }) do
		K.bollard(f, V3(x, 0.3, 147))
	end
	local wb = part(f, "WelcomeBoard", V3(14, 4, 0.5), CF(-24, 3.4, 145), Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	for _, x in ipairs({ -30.5, -17.5 }) do
		part(f, "WelcomePost", V3(0.6, 5.6, 0.6), CF(x, 2.8, 145), C.black, M.Metal, { collide = true })
	end
	Signage.Boards(wb, { Enum.NormalId.Front, Enum.NormalId.Back }, "gym", { maxDist = 500 })
	-- the entrance path (CityDetail's keep-out x -5..5, z 84..115 stays open) is the plaza itself
	-- crosswalks across the loop's south road, in line with Champion Ave's sidewalks
	for _, x in ipairs({ -17, 17 }) do
		K.crosswalk(f, V3(x, 0, LOOP.z1), false, LOOP.w, 8)
		K.kerbRamp(f, V3(x, 0, LOOP.z1 - LW - 1.2), V3(0, 0, 1), 8)
		K.kerbRamp(f, V3(x, 0, LOOP.z1 + LW + 1.2), V3(0, 0, -1), 8)
	end
	-- stop bars and signals where Champion Ave meets the loop
	K.stopBar(f, V3(-26, 0, LOOP.z1 + LW / 2), V3(0, 0, 1), LW)
	K.stopBar(f, V3(26, 0, LOOP.z1 - LW / 2), V3(0, 0, 1), LW)
	K.trafficSignal(f, V3(-26, SW_H, LOOP.z1 + LW + 2), V3(0, 0, -1), 20, V3(-1, 0, 0), "GYM LOOP")
	K.trafficSignal(f, V3(26, SW_H, LOOP.z1 - LW - 2), V3(0, 0, 1), 20, V3(1, 0, 0), "GYM LOOP")
	K.trafficSignal(f, V3(-26, SW_H, LOOP.z1 - LW - 2), V3(1, 0, 0), 20, V3(0, 0, 1), "CHAMPION AVE")

	-- member parking east of the plaza: one row of 2.7 x 5 m bays nosing the gym, the aisle open to
	-- the loop road through a dropped kerb (x 180..200); bay 9 stays empty for the player's own car
	local bays = K.parkingLot(f, 40, 200, 100, inZ, { rng = rng, fill = 0.45, reserved = 9, lights = false })
	K.kerbRamp(f, V3(190, 0, LOOP.z1 - LW - 1.2), V3(0, 0, 1), 18)
	slab(f, "LotEntry", 181, 199, inZ, LOOP.z1 - LW, ROAD_Y - 0.01, K.ASPHALT_OLD, M.Asphalt)
	local bay = bays[9] or CF(120, ROAD_Y, 109)
	part(f, "ReservedPost", V3(0.3, 4.2, 0.3), bay * CF(0, 2.1, -10), C.steel, M.Metal, { collide = true })
	local rs = part(f, "ReservedSign", V3(3, 1.8, 0.12), bay * CF(0, 4.6, -10), C.white, M.SmoothPlastic)
	rs:SetAttribute("Kind", "Reserved")
	tag(rs, "CityScreen")
	GymDecor.Sign(rs, Enum.NormalId.Back, "RESERVED\nMEMBER OF THE MONTH", Color3.fromRGB(30, 60, 160), C.white, 40)
	site("CarBay", bay)
	-- fans gather along the entrance plaza (count grows with popularity; CityVisuals)
	site("FanGymW", CFrame.lookAt(V3(-14, 0.3, 104), V3(0, 0.3, 104)), { Len = 16, Rows = 2 })
	site("FanGymE", CFrame.lookAt(V3(14, 0.3, 104), V3(0, 0.3, 104)), { Len = 16, Rows = 2 })
	for _, x in ipairs({ 60, 120, 180 }) do
		K.streetLight(f, V3(x, ROAD_Y, 121), V3(0, 0, -1), true, 26)
	end
	local lotSign = part(f, "LotSign", V3(7, 2.8, 0.3), CF(44, 6.2, 140), Color3.fromRGB(30, 60, 160), M.SmoothPlastic)
	part(f, "LotSignPole", V3(0.35, 4.8, 0.35), CF(44, 2.4, 140), C.steel, M.Metal)
	GymDecor.Sign(lotSign, Enum.NormalId.Back, "P  MEMBER PARKING", C.white, Color3.fromRGB(30, 60, 160), 40)
	GymDecor.Sign(lotSign, Enum.NormalId.Front, "P  MEMBER PARKING", C.white, Color3.fromRGB(30, 60, 160), 40)
	K.fenceIron(f, V3(40, 0.3, 100), V3(40, 0.3, 147), 4)
	K.fenceIron(f, V3(40, 0.3, 100), V3(200, 0.3, 100), 4)
	-- a hedge screens the lot from the plaza, trees along its back
	for x = 52, 190, 46 do
		K.tree(f, V3(x, 0.3, 94), "oak", rng:NextNumber(30, 38), rng)
	end

	-- Champions Plaza west of the entrance: paving, the golden glove monument, benches, trees, flags
	slab(f, "PlazaBorder", -200.3, -39.7, 99.7, inZ, 0.3, Color3.fromRGB(120, 110, 100), M.Concrete)
	slab(f, "PlazaPaving", -200, -40, 100, inZ - 0.3, 0.32, K.PAVING, M.Pavement)
	local mon = V3(-120, 0.32, 118)
	part(f, "MonumentBase", V3(14, 1.6, 14), CF(mon + V3(0, 0.8, 0)), Color3.fromRGB(80, 80, 86), M.Granite, { collide = true })
	part(f, "MonumentStep", V3(10, 1.2, 10), CF(mon + V3(0, 2.2, 0)), Color3.fromRGB(70, 70, 76), M.Granite, { collide = true })
	part(f, "MonumentPlinth", V3(6.5, 8, 6.5), CF(mon + V3(0, 6.8, 0)), Color3.fromRGB(60, 60, 66), M.Granite, { collide = true })
	local plaque = part(f, "MonumentPlaque", V3(4.8, 2.2, 0.1), CF(mon + V3(0, 6.4, 3.3)), C.gold, M.Metal)
	GymDecor.Sign(plaque, Enum.NormalId.Back, "CHAMPIONS WALK\nEvery champion started here", Color3.fromRGB(40, 30, 10), C.gold, 40)
	plaque:SetAttribute("Kind", "Plaque")
	tag(plaque, "CityScreen")
	site("Statue", CFrame.lookAt(V3(-92, 0.32, 118), V3(-92, 0.32, 160)))
	site("FanPlaza", CFrame.lookAt(V3(-120, 0.32, 128), V3(-120, 0.32, 118)), { Len = 18, Rows = 1 })
	local gloveCF = CF(mon + V3(0, 15.4, 0)) * ANG(RAD(-12), RAD(25), 0)
	blob(f, "GoldenGlove", V3(6.4, 8.2, 7), gloveCF, C.gold, M.Metal, { reflect = 0.2 })
	blob(f, "GoldenThumb", V3(2.3, 4, 2.4), gloveCF * CF(-2.9, 0.3, -1.4) * ANG(0, 0, RAD(-18)), C.gold, M.Metal, { reflect = 0.2 })
	cyl(f, "GloveCuff", 3.0, 5.2, gloveCF * CF(0, -4.7, 0) * ANG(0, 0, RAD(90)), C.goldDeep, M.Metal)
	for k = 0, 3 do
		part(f, "GloveLace", V3(2.4, 0.18, 0.2), gloveCF * CF(0, -3.6 + k * 0.6, -2.7) * ANG(0, 0, RAD(k % 2 == 0 and 25 or -25)), Color3.fromRGB(150, 110, 20), M.Fabric)
	end
	for _, a in ipairs({ 30, 150, 270 }) do
		local p = mon + V3(math.cos(RAD(a)) * 9.5, 0.1, math.sin(RAD(a)) * 9.5)
		local ml = spot(emitter(f, CF(p + V3(0, 0.6, 0))), Enum.NormalId.Top, Color3.fromRGB(255, 225, 170), 26, 1.6, 50)
		ml.Enabled = false
		tag(ml, "NightLight")
	end
	for _, d in ipairs({ { -176, 108 }, { -64, 108 }, { -176, 140 }, { -64, 140 }, { -150, 142 }, { -90, 142 } }) do
		K.bench(f, V3(d[1], 0.32, d[2]), d[2] > 130 and RAD(180) or 0, 6.4, C.wood)
	end
	for _, x in ipairs({ -190, -160, -80, -50 }) do
		part(f, "TreePlanter", V3(6, 1.6, 6), CF(x, 1.1, 112), Color3.fromRGB(120, 110, 100), M.Concrete, { collide = true })
		K.tree(f, V3(x, 1.9, 112), "oak", rng:NextNumber(26, 32), rng)
		K.bin(f, V3(x + 4.5, 0.32, 108))
	end
	K.flowerBed(f, CF(-120, 0.32, 136), 44, 2.4, rng)
	local flagColors = { { C.red, C.white }, { Color3.fromRGB(18, 18, 22), C.gold }, { C.blue, C.white } }
	for i, x in ipairs({ -136, -120, -104 }) do
		K.flagPole(f, V3(x, 0.32, 145), 36, flagColors[i][1], "WCB", flagColors[i][2])
	end
	for _, x in ipairs({ -196, -44 }) do
		K.parkLamp(f, V3(x, 0.32, 104), true)
		K.parkLamp(f, V3(x, 0.32, 144), true)
	end

	-- the bus stop on the loop's south road, the far side at x -70, a bus pulled up in the lane
	K.busStop(f, CF(-70, 0, LOOP.z1 + LW + 0.6 + 4), "BUS 12 - DOWNTOWN")
	K.bus(f, CF(-70, ROAD_Y, LOOP.z1 + LW / 2 + 0.6) * ANG(0, RAD(-90), 0), nil, "12  DOWNTOWN")
	K.roadSign(f, V3(-96, SW_H, LOOP.z1 + LW + 1.2), RAD(180), "noparking", "BUS\nSTOP\nONLY")

	-- outdoor training yard east of the building: rubber floor, sprint lanes, rigs, tyre, sandbags
	local y0 = V3(192, 0, -20)
	part(f, "YardFloor", V3(60, 0.3, 90), CF(y0 + V3(0, 0.15, 0)), Color3.fromRGB(44, 46, 50), M.Rubber, { collide = true })
	for k = 0, 4 do
		part(f, "SprintLane", V3(0.4, 0.03, 80), CF(y0 + V3(8 + k * 4, 0.315, 0)), C.white, M.SmoothPlastic, { shadow = false })
	end
	for _, z in ipairs({ -34, -22 }) do
		for _, x in ipairs({ -20, -10 }) do
			part(f, "RigPost", V3(0.5, 11, 0.5), CF(y0 + V3(x, 5.8, z)), C.black, M.Metal, { collide = true })
		end
	end
	for _, x in ipairs({ -20, -10 }) do
		cyl(f, "RigBar", 12.4, 0.25, CF(y0 + V3(x, 10.4, -28)) * ANG(0, RAD(90), 0), C.steelLight, M.Metal)
	end
	for _, z in ipairs({ -34, -28, -22 }) do
		cyl(f, "PullUpBar", 10.4, 0.25, CF(y0 + V3(-15, 10.6, z)), C.steelLight, M.Metal)
	end
	for _, x in ipairs({ -18.2, -16.2 }) do
		cyl(f, "ParallelBar", 7, 0.25, CF(y0 + V3(x, 4.4, -4)) * ANG(0, RAD(90), 0), C.steelLight, M.Metal)
		for _, z in ipairs({ -7, -1 }) do
			part(f, "ParallelPost", V3(0.3, 4.2, 0.3), CF(y0 + V3(x, 2.3, z)), C.black, M.Metal)
		end
	end
	vcyl(f, "Tire", 2.4, 8, CF(y0 + V3(-12, 0.3, 22)), Color3.fromRGB(26, 26, 28), M.Rubber, { collide = true })
	vcyl(f, "TireInner", 0.05, 4, CF(y0 + V3(-12, 2.66, 22)), Color3.fromRGB(10, 10, 12), M.Rubber)
	for k = 0, 2 do
		blob(f, "Sandbag", V3(3.2, 1.4, 1.8), CF(y0 + V3(-22, 1.0 + k * 1.2, 32)) * ANG(0, RAD(k * 20), 0), Color3.fromRGB(70, 74, 52), M.Fabric)
	end
	local ysign = part(f, "YardSign", V3(16, 3, 0.4), CF(y0 + V3(0, 8.5, 45.6)), Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	for _, x in ipairs({ -7.8, 7.8 }) do
		part(f, "YardSignPost", V3(0.4, 7, 0.4), CF(y0 + V3(x, 3.5, 45.6)), C.black, M.Metal)
	end
	GymDecor.Sign(ysign, Enum.NormalId.Back, "OUTDOOR TRAINING YARD", C.gold, Color3.fromRGB(18, 18, 22), 30)
	GymDecor.Sign(ysign, Enum.NormalId.Front, "OUTDOOR TRAINING YARD", C.gold, Color3.fromRGB(18, 18, 22), 30)
	K.fenceChain(f, V3(162, 0.3, -65), V3(222, 0.3, -65), 7)
	K.fenceChain(f, V3(222, 0.3, -65), V3(222, 0.3, 25), 7)
	K.fenceChain(f, V3(162, 0.3, 25), V3(222, 0.3, 25), 7)
	for _, p in ipairs({ V3(165, 0.3, -62), V3(219, 0.3, -62), V3(165, 0.3, 22), V3(219, 0.3, 22) }) do
		K.streetLight(f, p, V3(p.X < 192 and 1 or -1, 0, 0), true, 26)
	end
	-- a path from the plaza round the building to the yard and on to the field
	slab(f, "CampusPath", 112, 160, -22, -14, 0.3, K.PAVING, M.Pavement)
	slab(f, "CampusPath", 156, 164, -22, 100, 0.3, K.PAVING, M.Pavement)
	slab(f, "CampusPath", 30, 164, 92, 100, 0.3, K.PAVING, M.Pavement)
	slab(f, "CampusPath", -164, -30, 92, 100, 0.3, K.PAVING, M.Pavement)
	slab(f, "CampusPath", -164, -156, -160, 100, 0.3, K.PAVING, M.Pavement)
	slab(f, "CampusPath", -164, 164, -168, -160, 0.3, K.PAVING, M.Pavement)
	slab(f, "CampusPath", 156, 164, -168, -22, 0.3, K.PAVING, M.Pavement)
	for _, z in ipairs({ 40, -40, -120 }) do
		K.parkLamp(f, V3(-168, 0.3, z), z == -40)
		K.parkLamp(f, V3(168, 0.3, z), z == -40)
	end
	for _, z in ipairs({ 60, 0, -60, -120 }) do
		K.tree(f, V3(-186, 0.14, z + 12), rng:NextNumber() < 0.5 and "oak" or "maple", rng:NextNumber(30, 40), rng)
		K.tree(f, V3(-132, 0.14, z - 10), "birch", rng:NextNumber(26, 32), rng)
		if z ~= 0 and z ~= -60 then
			K.tree(f, V3(132, 0.14, z - 10), "oak", rng:NextNumber(28, 36), rng)
		end
	end

	-- the training field north of the pool annex: a running track round a lawn, bleachers, floods
	local fc = V3(0, 0, -212)
	part(f, "FieldLawn", V3(300, 0.26, 92), CF(fc + V3(0, 0.13, 0)), K.GRASS_DARK, M.Grass, { collide = true })
	local trackCol = Color3.fromRGB(170, 56, 48)
	part(f, "Track", V3(200, 0.3, 9), CF(fc + V3(0, 0.15, -50)), trackCol, M.Rubber, { collide = true })
	part(f, "Track", V3(200, 0.3, 9), CF(fc + V3(0, 0.15, 50)), trackCol, M.Rubber, { collide = true })
	for _, s in ipairs({ -1, 1 }) do
		for k = 0, 7 do
			local a0 = -math.pi / 2 + k * math.pi / 8
			local a1 = a0 + math.pi / 8
			local pa = fc + V3(100 * s + math.cos(a0) * 50 * s, 0.15, math.sin(a0) * 50)
			local pb = fc + V3(100 * s + math.cos(a1) * 50 * s, 0.15, math.sin(a1) * 50)
			part(f, "TrackBend", V3(9, 0.3, (pb - pa).Magnitude + 1.2), CFrame.lookAt((pa + pb) / 2, pb), trackCol, M.Rubber, { collide = true })
		end
	end
	for k = 1, 3 do
		part(f, "TrackLine", V3(200, 0.02, 0.3), CF(fc + V3(0, 0.31, -54.5 + k * 2.25)), C.white, M.SmoothPlastic, { shadow = false })
		part(f, "TrackLine", V3(200, 0.02, 0.3), CF(fc + V3(0, 0.31, 54.5 - k * 2.25)), C.white, M.SmoothPlastic, { shadow = false })
	end
	for k = 0, 2 do
		part(f, "Bleacher", V3(60, 1.6, 3.2), CF(fc + V3(0, 0.8 + k * 1.6, -66 - k * 3.2)), Color3.fromRGB(150, 152, 160), M.Metal, { collide = true })
	end
	part(f, "BleacherBack", V3(60, 6, 0.4), CF(fc + V3(0, 3, -76)), Color3.fromRGB(120, 122, 130), M.Metal, { collide = true })
	for _, p in ipairs({ V3(-120, 0, -268), V3(120, 0, -268), V3(-120, 0, -156), V3(120, 0, -156) }) do
		part(f, "FloodMast", V3(1.4, 60, 1.4), CF(p + V3(0, 30, 0)), Color3.fromRGB(70, 72, 80), M.Metal, { collide = true })
		local head = part(f, "FloodHead", V3(10, 3.2, 1.2), CFrame.lookAt(p + V3(0, 58, 0), fc + V3(0, 10, 0)), Color3.fromRGB(255, 255, 235), M.Neon, { shadow = false })
		local l = spot(emitter(f, head.CFrame * CF(0, 0, -1)), Enum.NormalId.Front, Color3.fromRGB(240, 245, 255), 160, 1.6, 60)
		l.Enabled = false
		tag(l, "NightLight")
	end
	local fsign = part(f, "FieldSign", V3(22, 3.2, 0.4), CF(fc + V3(0, 8.8, 70)), Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	for _, x in ipairs({ -10.5, 10.5 }) do
		part(f, "FieldSignPost", V3(0.5, 7.2, 0.5), CF(fc + V3(x, 3.6, 70)), C.black, M.Metal)
	end
	GymDecor.Sign(fsign, Enum.NormalId.Front, "WCB TRAINING FIELD", C.gold, Color3.fromRGB(18, 18, 22), 30)
	GymDecor.Sign(fsign, Enum.NormalId.Back, "WCB TRAINING FIELD", C.gold, Color3.fromRGB(18, 18, 22), 30)
	for _, x in ipairs({ -210, -190, 190, 210 }) do
		K.tree(f, V3(x, 0.14, -212 + (x % 40 == 0 and 20 or -20)), "poplar", rng:NextNumber(40, 50), rng)
	end

	-- street lights and trees along the loop's inner sidewalk
	local lights = folder(f, "LoopLights")
	lightsX(lights, -200, 200, LOOP.z1 - LW - 1.4, V3(0, 0, 1), 80, nil, 1)
	lightsX(lights, -200, 200, LOOP.z0 + LW + 1.4, V3(0, 0, -1), 80, nil, 1)
	lightsZ(lights, -240, 120, LOOP.x0 + LW + 1.4, V3(-1, 0, 0), 80, nil, 1)
	lightsZ(lights, -240, 120, LOOP.x1 - LW - 1.4, V3(1, 0, 0), 80, nil, 1)
	treesX(f, -160, 160, LOOP.z0 + LW + 5, 40, rng)
	treesZ(f, -200, 80, LOOP.x0 + LW + 5, 40, rng)
	treesZ(f, -200, 80, LOOP.x1 - LW - 5, 40, rng)
	K.streetSign(f, V3(-24, SW_H, LOOP.z1 - LW - 2), "GYM LOOP", 0, "CHAMPION AVE")
	lightZone(f, "CampusZone", V3(LOOP.x1 - LOOP.x0, 60, LOOP.z1 - LOOP.z0), CF(0, 30, (LOOP.z0 + LOOP.z1) / 2), "Street")
end

------------------------------------------------------------------------
-- Downtown: Champion Ave, Main Street and its rows, the fire station, 2nd Street and the towers
------------------------------------------------------------------------
local function walkOfFame(f)
	-- the all-time greats on the west sidewalk of Champion Ave; your own stars face them on the east
	-- sidewalk (CityVisuals, Site_WalkOfFame, Step studs apart)
	local k = 0
	for z = 200, 290, 7 do
		k += 1
		local lg = Config.Legends[k]
		if lg then
			CityProps.Star(f, CF(-17.5, SW_H + 0.03, z), "LEGACY " .. lg.score, lg.name)
		end
	end
	site("WalkOfFame", CF(17.5, SW_H + 0.03, 200), { Step = 7, Max = 13 })
	local post = part(f, "FameSignPost", V3(0.35, 7, 0.35), CF(-21, SW_H + 3.5, 194), C.steel, M.Metal, { collide = true })
	local fs = part(f, "FameSign", V3(6.4, 2.0, 0.12), CF(-21, SW_H + 7.6, 194), Color3.fromRGB(60, 30, 50), M.SmoothPlastic)
	GymDecor.Sign(fs, Enum.NormalId.Back, "WALK OF FAME", C.gold, Color3.fromRGB(60, 30, 50), 40)
	GymDecor.Sign(fs, Enum.NormalId.Front, "WALK OF FAME", C.gold, Color3.fromRGB(60, 30, 50), 40)
	return post
end

-- the fire station on Main Street's north side, west of Oak Street (front at z frontN, facing south)
local function fireStation(f, rng)
	local x0, x1 = -600, -480
	local cx, w = (x0 + x1) / 2, x1 - x0
	local front = MAIN.frontN
	local red = Color3.fromRGB(176, 40, 40)
	local brick = Color3.fromRGB(150, 84, 64)
	-- apparatus bay (one tall storey) with three roller doors, the office block beside it, the tower
	local bayW, bayH, depth = 76, 20, 60
	part(f, "FireBay", V3(bayW, bayH, depth), CF(x0 + bayW / 2, bayH / 2, front - depth / 2), brick, M.Brick, { collide = true })
	for k = 0, 2 do
		local dx = x0 + 12 + k * 26
		local fd = part(f, "FireDoor", V3(20, 15, 0.4), CF(dx, 7.5 + SW_H, front - 0.5), red, M.Metal, { collide = true })
		local dsg = gui(fd, Enum.NormalId.Front, 6, 1, 300)
		for r = 0, 4 do
			frame(dsg, { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, 0.18 + r * 0.18), BackgroundColor3 = Color3.fromRGB(110, 20, 20) })
		end
		part(f, "FireDoorFrame", V3(21, 0.8, 0.8), CF(dx, 15.9 + SW_H, front - 0.4), C.white, M.Concrete)
		part(f, "BayNumber", V3(3, 3, 0.1), CF(dx, 17.6 + SW_H, front - 0.45), C.white, M.SmoothPlastic)
	end
	local apron = part(f, "FireApron", V3(bayW + 4, ROAD_Y, MAIN.z0 - front + 0.6), CF(x0 + bayW / 2, ROAD_Y / 2, (front + MAIN.z0) / 2), Color3.fromRGB(160, 160, 158), M.Concrete, { collide = true })
	local _ = apron
	K.lineX(f, x0 - 2, x0 + bayW + 2, front + 4, K.LINE_YELLOW, 0.5, "ApronLine")
	local officeW = w - bayW - 4
	local m = K.building(f, CF(x1 - officeW / 2, 0, front), officeW, depth - 10, 1, { color = brick, mat = M.Brick, retail = false, sign = "FIRE STATION 7", signBg = Color3.fromRGB(120, 20, 20), signFg = C.white, rng = rng, units = 1, name = "FireOffice" })
	m:SetAttribute("Sign", "FIRE STATION 7")
	part(f, "HoseTower", V3(12, 46, 12), CF(x1 - 10, 23, front - depth + 8), brick, M.Brick, { collide = true })
	part(f, "HoseTowerCap", V3(13.5, 1.6, 13.5), CF(x1 - 10, 46.8, front - depth + 8), C.white, M.Concrete)
	local band = part(f, "FireBand", V3(bayW, 3.4, 0.4), CF(x0 + bayW / 2, bayH - 2.4, front - 0.4), Color3.fromRGB(120, 20, 20), M.SmoothPlastic)
	GymDecor.Sign(band, Enum.NormalId.Front, "CITY FIRE DEPARTMENT  -  STATION 7", C.white, Color3.fromRGB(120, 20, 20), 30)
	K.flagPole(f, V3(x1 - 30, SW_H, front - 3), 36, C.red, "FD", C.white)
	-- the engine on the apron
	local eng = CF(x0 + 38, ROAD_Y, front + 14) * ANG(0, RAD(180), 0)
	part(f, "FireEngine", V3(8.6, 7.4, 34), eng * CF(0, 1.6 + 3.7, 0), red, M.SmoothPlastic, { collide = true })
	part(f, "EngineCab", V3(8.4, 6, 9), eng * CF(0, 1.6 + 7.4 + 3, -11), red, M.SmoothPlastic)
	part(f, "EngineGlass", V3(8.0, 3.2, 0.2), eng * CF(0, 1.6 + 7.4 + 3.2, -15.55), Color3.fromRGB(40, 54, 70), M.Glass, { shadow = false })
	part(f, "EngineLadder", V3(2.2, 0.6, 28), eng * CF(0, 1.6 + 7.4 + 0.5, 2), Color3.fromRGB(200, 204, 210), M.Metal)
	part(f, "EngineLightBar", V3(6, 0.8, 1.6), eng * CF(0, 1.6 + 7.4 + 6.4, -11), Color3.fromRGB(255, 60, 60), M.Neon, { shadow = false })
	for _, x in ipairs({ -3.8, 3.8 }) do
		for _, z in ipairs({ -10, 6, 11 }) do
			cyl(f, "Wheel", 1.2, 3.4, eng * CF(x, 1.7, z), Color3.fromRGB(22, 22, 26), M.Rubber)
		end
	end
	K.hydrant(f, V3(x0 + 4, SW_H, front + 2))
	lightZone(f, "FireZone", V3(w, bayH, depth), CF(cx, bayH / 2, front - depth / 2), "Store")
end

local function buildDowntown(root)
	local f = folder(root, "MainStreet")
	local rng = Random.new(1987)
	-- Champion Ave: from the loop to Main Street, sidewalks with the Walk of Fame, trees and lamps
	K.roadZ(f, "ChampionAve", AVE.z0, AVE.z1, AVE.x, AVE.w, { y = ROAD_Y - 0.004, sw = { w = 10, e = 10 } })
	walkOfFame(f)
	for z = 205, 285, 20 do
		K.streetLight(f, V3(-21.5, SW_H, z), V3(1, 0, 0), true)
		K.streetLight(f, V3(21.5, SW_H, z + 10), V3(-1, 0, 0), true)
	end
	for z = 212, 282, 24 do
		K.streetTree(f, V3(-21, SW_H, z), rng, 28)
		K.streetTree(f, V3(21, SW_H, z + 6), rng, 28)
	end
	K.crosswalk(f, V3(AVE.x, 0, 298), true, AVE.w, 8)
	K.crosswalk(f, V3(AVE.x, 0, 185), true, AVE.w, 8)
	K.streetSign(f, V3(-21, SW_H, 198), "CHAMPION AVE", RAD(90))

	-- Main Street: two 12.5 lanes between parking lanes, a double yellow centre line, white edge
	-- lines at the parking lanes, crosswalks and signals at Champion Ave, Oak Street and Riverside Drive
	local gasGap = { CityShops.GAS.x0, CityShops.GAS.x1 }
	K.roadX(f, "MainStreet", MAIN.x0, MAIN.x1, (MAIN.z0 + MAIN.z1) / 2, MAIN.z1 - MAIN.z0, {
		center = "double", sw = { n = 10, s = MAIN.frontS - MAIN.z1 },
		gaps = { { CITY.RiversideDrive.x - 12.5, CITY.RiversideDrive.x + 12.5 } },
		gapsN = { { AVE.x - AVE.w / 2, AVE.x + AVE.w / 2 }, { CITY.OakStreet.x - 12.5, CITY.OakStreet.x + 12.5 } },
		gapsS = { gasGap },
	})
	for _, z in ipairs({ MAIN.z0 + 8.5, MAIN.z1 - 8.5 }) do
		for _, r in ipairs(K.cutRanges(MAIN.x0, MAIN.x1, { { -22, 22 }, { CITY.OakStreet.x - 22, CITY.OakStreet.x + 22 }, { CITY.RiversideDrive.x - 22, CITY.RiversideDrive.x + 22 }, gasGap })) do
			K.lineX(f, r[1], r[2], z, K.LINE_WHITE, 0.4, "EdgeLine")
		end
	end
	local function junction(x, name, cross, legs)
		for _, cx in ipairs({ x - 17, x + 17 }) do
			K.crosswalk(f, V3(cx, 0, (MAIN.z0 + MAIN.z1) / 2), false, MAIN.z1 - MAIN.z0, 8)
		end
		K.stopBar(f, V3(x - 24, 0, MAIN.lanes[1].z), V3(0, 0, 1), 12.5)
		K.stopBar(f, V3(x + 24, 0, MAIN.lanes[2].z), V3(0, 0, 1), 12.5)
		K.trafficSignal(f, V3(x - 24, SW_H, MAIN.z1 + 3), V3(0, 0, -1), 24, V3(-1, 0, 0), name)
		K.trafficSignal(f, V3(x + 24, SW_H, MAIN.z0 - 3), V3(0, 0, 1), 24, V3(1, 0, 0), name)
		if legs.n then
			K.crosswalk(f, V3(x, 0, MAIN.z0 - 4), true, 25, 8)
			K.trafficSignal(f, V3(x - 24, SW_H, MAIN.z0 - 3), V3(1, 0, 0), 20, V3(0, 0, 1), cross)
		end
		if legs.s then
			K.crosswalk(f, V3(x, 0, MAIN.z1 + 4), true, 25, 8)
			K.trafficSignal(f, V3(x + 24, SW_H, MAIN.z1 + 3), V3(-1, 0, 0), 20, V3(0, 0, -1), cross)
		end
		for _, dx in ipairs({ -19, 19 }) do
			K.kerbRamp(f, V3(x + dx, 0, MAIN.z0 - 1.2), V3(0, 0, 1), 8)
			K.kerbRamp(f, V3(x + dx, 0, MAIN.z1 + 1.2), V3(0, 0, -1), 8)
		end
	end
	junction(AVE.x, "MAIN ST", "CHAMPION AVE", { n = true })
	junction(CITY.OakStreet.x, "MAIN ST", "OAK ST", { n = true })
	junction(CITY.RiversideDrive.x, "MAIN ST", "RIVERSIDE DR", { n = true, s = true })
	K.streetSign(f, V3(-27, SW_H, MAIN.z1 + 3), "MAIN ST", 0, "CHAMPION AVE")
	K.roadSign(f, V3(120, SW_H, MAIN.z0 - 2), RAD(180), "speed", "25")
	K.roadSign(f, V3(-300, SW_H, MAIN.z1 + 2), 0, "speed", "25")
	-- parked cars in both parking lanes, lights and trees along both sidewalks
	local carX = { -520, -470, -360, -290, -230, -150, -100, -50, 60, 110, 180, 250, 330, 420, 470, 700 }
	for i, x in ipairs(carX) do
		local south = i % 3 ~= 0
		local z = south and MAIN.parkLanes[2] or MAIN.parkLanes[1]
		local kinds = { "sedan", "hatch", "suv", "sedan", "pickup", "taxi", "van" }
		K.car(f, CF(x, ROAD_Y, z) * ANG(0, RAD(south and -90 or 90), 0), K.CAR_COLORS[(i * 3) % #K.CAR_COLORS + 1], kinds[(i % #kinds) + 1])
	end
	lightsX(f, -590, 850, MAIN.z0 - 1.6, V3(0, 0, 1), 60, nil, 2)
	lightsX(f, -560, 820, MAIN.z1 + 1.6, V3(0, 0, -1), 60, nil, 2)
	treesX(f, -575, 835, MAIN.z0 - 5.5, 30, rng, { { -30, 30 }, { CITY.OakStreet.x - 30, CITY.OakStreet.x + 30 }, { CITY.RiversideDrive.x - 30, CITY.RiversideDrive.x + 30 }, { -610, -470 } })
	treesX(f, -545, 520, MAIN.z1 + 8, 30, rng, { { -30, 30 }, { 150, 300 } })
	-- the rows of shops: the south row facing north (towards the gym), the north row facing south
	CityShops.BuildRow(f, CF(0, 0, MAIN.frontS), 0, rng)
	local north = folder(root, "NorthRow")
	CityShops.BuildNorthRow(north, CF(0, 0, MAIN.frontN) * ANG(0, math.pi, 0), math.pi, -MAIN.northRowX[2], -MAIN.northRowX[1], rng)
	-- the service alley behind the north row and its dumpsters
	slab(north, "Alley", MAIN.northRowX[1], MAIN.northRowX[2], LOOP.z1 + LW + OUTER + 0.6, MAIN.frontN - 46, ROAD_Y - 0.02, K.ASPHALT_OLD, M.Asphalt)
	for x = MAIN.northRowX[1] + 30, MAIN.northRowX[2] - 20, 90 do
		K.dumpster(north, CF(x, ROAD_Y, MAIN.frontN - 50), (x % 180 == 0) and Color3.fromRGB(40, 60, 120) or nil)
		K.streetLight(north, V3(x + 40, ROAD_Y, MAIN.frontN - 52), V3(0, 0, -1), true, 24)
	end
	fireStation(north, rng)
	-- the park's railing along Main Street's north sidewalk east of the row, with gates
	local parkZ = MAIN.frontN
	for _, r in ipairs(K.cutRanges(CITY.Park.x0, CITY.Park.x1, { { 330, 342 }, { 540, 552 } })) do
		K.fenceIron(f, V3(r[1], SW_H, parkZ), V3(r[2], SW_H, parkZ), 5)
	end
	-- 2nd Street and the towers behind the shops' backs
	local S2 = CITY.SecondStreet
	K.roadX(f, "SecondStreet", S2.x0, S2.x1, S2.z, S2.w, { sw = { n = 10, s = 12 }, gaps = { { CITY.RiversideDrive.x - 12.5, CITY.RiversideDrive.x + 12.5 } } })
	slab(f, "BackLot", -560, 520, MAIN.frontS + 44.5, S2.z - S2.w / 2 - 10.6, ROAD_Y - 0.02, K.ASPHALT_OLD, M.Asphalt)
	for x = -520, 500, 120 do
		K.dumpster(f, CF(x, ROAD_Y, MAIN.frontS + 48))
		K.car(f, CF(x + 30, ROAD_Y, S2.z - 24) * ANG(0, RAD(180), 0), K.CAR_COLORS[(x // 120) % #K.CAR_COLORS + 1], "sedan")
		K.streetLight(f, V3(x + 60, ROAD_Y, MAIN.frontS + 60), V3(0, 0, 1), x % 240 == 0, 26)
	end
	lightsX(f, -580, 760, S2.z + S2.w / 2 + 1.6, V3(0, 0, -1), 70, nil, 2)
	local towers = {
		{ x = -520, w = 90, d = 70, h = 180, tone = 2, name = "FIRST CITY BANK TOWER" },
		{ x = -360, w = 80, d = 60, h = 140, tone = 1, name = "MERIDIAN OFFICES" },
		{ x = -200, w = 110, d = 70, h = 220, tone = 4, name = "GRAND HOTEL", crown = true },
		{ x = -40, w = 90, d = 60, h = 160, tone = 2, name = "WCB SPORTS NETWORK" },
		{ x = 110, w = 70, d = 60, h = 110, tone = 3, name = "RIVER COURT" },
		{ x = 250, w = 80, d = 70, h = 200, tone = 0, name = "APEX ATHLETICS HQ" },
		{ x = 400, w = 100, d = 70, h = 130, tone = 1, name = "CITY HALL ANNEX" },
		{ x = 560, w = 90, d = 60, h = 90, tone = 3, name = "HARBOUR HOUSE" },
	}
	local zf = S2.z + S2.w / 2 + 12 -- the towers' front line
	for i, t in ipairs(towers) do
		local m = K.tower(f, V3(t.x, 0, zf + t.d / 2), t.w, t.d, t.h, V3(0, 0, -1), rng, { tone = t.tone, crown = t.crown, range = 1600, name = "DowntownTower" })
		-- a lobby across the ground floor and a name band
		part(m, "LobbyGlass", V3(t.w * 0.8, 12, 0.3), CF(t.x, 6.8, zf - 0.1), Color3.fromRGB(150, 190, 220), M.Glass, { transparency = 0.4, reflect = 0.15, shadow = false })
		part(m, "LobbyCanopy", V3(t.w * 0.5, 0.6, 9), CF(t.x, 13.4, zf - 4.5), Color3.fromRGB(30, 30, 34), M.Metal)
		part(m, "LobbyDoor", V3(10, 8, 0.3), CF(t.x, SW_H + 4, zf - 0.35), Color3.fromRGB(30, 30, 34), M.Metal)
		local nb = part(m, "TowerName", V3(t.w * 0.6, 2.6, 0.3), CF(t.x, 16.2, zf - 0.3), Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
		GymDecor.Sign(nb, Enum.NormalId.Front, t.name, C.gold, Color3.fromRGB(20, 20, 24), 30)
		slab(f, "TowerPlaza", t.x - t.w / 2 - 6, t.x + t.w / 2 + 6, zf - 12, zf, SW_H, K.PAVING, M.Pavement)
		K.planter(f, CF(t.x - t.w * 0.35, SW_H, zf - 6), 8, 2.6)
		K.planter(f, CF(t.x + t.w * 0.35, SW_H, zf - 6), 8, 2.6)
		if i % 2 == 0 then
			K.bench(f, V3(t.x - t.w * 0.2, SW_H, zf - 8), 0, 6.4, C.wood)
		else
			K.tree(f, V3(t.x + t.w * 0.2, SW_H, zf - 7), "cherry", 24, rng)
		end
	end
	-- the WCB Sports Network's rooftop screen is a billboard (slot "Network")
	K.billboard(f, CFrame.lookAt(V3(-40, 160 + 14, zf + 2), V3(-40, 174, zf - 100)), 50, 16, "Network", K.ADS[8], 8)
	-- the public lot and the market hall east of the gas station
	K.parkingLot(f, 660, 740, MAIN.frontS, MAIN.frontS + 60, { rng = rng, fill = 0.5 })
	local mk = CF(815, 0, MAIN.frontS)
	part(f, "MarketHall", V3(70, 16, 60), mk * CF(0, 8, 30), Color3.fromRGB(96, 60, 46), M.Brick, { collide = true })
	part(f, "MarketRoof", V3(74, 1, 64), mk * CF(0, 16.5, 30), Color3.fromRGB(60, 62, 70), M.Metal)
	blob(f, "MarketVault", V3(60, 14, 60), mk * CF(0, 17, 30), Color3.fromRGB(70, 72, 80), M.Metal)
	for k = 0, 2 do
		part(f, "MarketArch", V3(14, 13, 0.6), mk * CF(-20 + k * 20, 6.5 + SW_H, -0.2), Color3.fromRGB(40, 54, 70), M.Glass, { transparency = 0.3, reflect = 0.1 })
	end
	local ms = part(f, "MarketSign", V3(40, 3.6, 0.4), CF(815, 13.8, MAIN.frontS - 0.3), Color3.fromRGB(20, 40, 60), M.SmoothPlastic)
	GymDecor.Sign(ms, Enum.NormalId.Front, "DOCKSIDE MARKET  -  FISH  ·  PRODUCE  ·  FLOWERS", Color3.fromRGB(255, 230, 170), Color3.fromRGB(20, 40, 60), 30)
	for k = 0, 3 do
		K.vendorCart(f, CF(790 + k * 16, SW_H, MAIN.frontS - 6) * ANG(0, 0, 0), ({ "fruit", "coffee", "pretzel", "icecream" })[k + 1])
	end
	lightZone(f, "StreetZone", V3(MAIN.x1 - MAIN.x0, 60, 200), CF((MAIN.x0 + MAIN.x1) / 2, 30, 330), "Street")
end

------------------------------------------------------------------------
-- West: Oak Street's houses, Cedar Lane, the hills; Hillcrest Estates at the top of the street
------------------------------------------------------------------------
-- a two-storey house with a gable roof, porch, attached garage and driveway. center = the house's
-- ground centre, front = unit vector towards the street, kerbX = the street's kerb line distance
local function house(f, center, front, rng, i, kerbDist)
	local W, D, H, R = 36, 30, 21, 9
	local base = CFrame.lookAt(center, center + front) -- local -Z = front, X = along the street
	local color = K.HOUSE_COLORS[(i - 1) % #K.HOUSE_COLORS + 1]
	local trim = C.white
	local roofColor = ({ Color3.fromRGB(80, 50, 40), Color3.fromRGB(60, 62, 70), Color3.fromRGB(110, 60, 44), Color3.fromRGB(70, 80, 90) })[i % 4 + 1]
	local m = model(f, "House")
	part(m, "House", V3(W, H, D), base * CF(0, H / 2, 0), color, i % 3 == 0 and M.Brick or M.WoodPlanks, { collide = true })
	part(m, "StoreyBand", V3(W + 0.3, 0.5, D + 0.3), base * CF(0, H / 2, 0), trim, M.Wood, { shadow = false })
	local a = (base * CF(0, H + R / 2, -D / 4)).Position
	local b = (base * CF(0, H + R / 2, D / 4)).Position
	part(m, "Roof", V3(W + 1.6, R, D / 2 + 0.8), CFrame.lookAt(a, a + front), roofColor, M.Slate, { class = "WedgePart", collide = true })
	part(m, "Roof", V3(W + 1.6, R, D / 2 + 0.8), CFrame.lookAt(b, b - front), roofColor, M.Slate, { class = "WedgePart", collide = true })
	part(m, "Chimney", V3(2.4, 7, 2.4), base * CF(W * 0.3, H + R - 1, D * 0.15), Color3.fromRGB(130, 70, 56), M.Brick)
	-- door, porch on columns, windows up and down
	local doorX = -W * 0.2
	part(m, "Door", V3(CITY.Door.w, CITY.Door.h, 0.25), base * CF(doorX, 0.6 + CITY.Door.h / 2, -D / 2 - 0.12), ({ C.red, Color3.fromRGB(30, 60, 120), Color3.fromRGB(30, 90, 60), Color3.fromRGB(60, 40, 30) })[i % 4 + 1], M.Wood)
	part(m, "Porch", V3(12, 0.8, 6), base * CF(doorX, 0.4, -D / 2 - 3), Color3.fromRGB(150, 140, 130), M.Concrete, { collide = true })
	part(m, "PorchStep", V3(6, 0.4, 1.6), base * CF(doorX, 0.2, -D / 2 - 6.8), Color3.fromRGB(150, 140, 130), M.Concrete, { collide = true })
	part(m, "PorchRoof", V3(12.6, 0.5, 6.6), base * CF(doorX, 10.2, -D / 2 - 3.2), color:Lerp(Color3.new(0, 0, 0), 0.3), M.WoodPlanks)
	for _, x in ipairs({ -5.4, 5.4 }) do
		vcyl(m, "PorchColumn", 9.4, 0.8, base * CF(doorX + x, 0.8, -D / 2 - 5.4), trim, M.Wood, { collide = true })
	end
	for _, w in ipairs({ { W * 0.16, 6 }, { W * 0.36, 6 }, { -W * 0.3, 15.5 }, { -W * 0.05, 15.5 }, { W * 0.2, 15.5 }, { W * 0.4, 15.5 } }) do
		part(m, "HouseWindow", V3(4.2, 4.6, 0.15), base * CF(w[1], w[2], -D / 2 - 0.08), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.25, shadow = false })
		part(m, "WindowTrim", V3(4.8, 0.35, 0.35), base * CF(w[1], w[2] - 2.5, -D / 2 - 0.15), trim, M.Wood, { shadow = false })
		part(m, "WindowShutter", V3(1.0, 4.6, 0.12), base * CF(w[1] - 2.7, w[2], -D / 2 - 0.1), roofColor, M.Wood, { shadow = false })
		part(m, "WindowShutter", V3(1.0, 4.6, 0.12), base * CF(w[1] + 2.7, w[2], -D / 2 - 0.1), roofColor, M.Wood, { shadow = false })
	end
	for _, w in ipairs({ { -D * 0.25, 6 }, { D * 0.25, 6 }, { -D * 0.25, 15.5 }, { D * 0.25, 15.5 } }) do
		part(m, "HouseWindow", V3(0.15, 4.6, 4.2), base * CF(-W / 2 - 0.08, w[2], w[1]), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.25, shadow = false })
	end
	-- the garage wing on the right, its driveway to the kerb
	local gx = W / 2 + 9
	part(m, "Garage", V3(18, 11, 26), base * CF(gx, 5.5, 2), color, M.WoodPlanks, { collide = true })
	part(m, "GarageRoof", V3(19.6, 0.6, 27.6), base * CF(gx, 11.3, 2), roofColor, M.Slate)
	local gd = part(m, "GarageDoor", V3(14, 8.5, 0.3), base * CF(gx, 4.25 + 0.4, -11.2), Color3.fromRGB(236, 236, 232), M.SmoothPlastic, { collide = true })
	local gsg = gui(gd, Enum.NormalId.Front, 6, 1, 200)
	for r = 0, 3 do
		frame(gsg, { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, 0.2 + r * 0.2), BackgroundColor3 = Color3.fromRGB(190, 190, 186) })
	end
	part(m, "Driveway", V3(14, 0.2, kerbDist - 11), base * CF(gx, 0.1, -(11 + (kerbDist - 11) / 2)), Color3.fromRGB(150, 148, 144), M.Concrete, { collide = true })
	part(m, "FrontPath", V3(3.6, 0.18, kerbDist - D / 2 - 7.6), base * CF(doorX, 0.09, -(D / 2 + 7.6 + (kerbDist - D / 2 - 7.6) / 2)), Color3.fromRGB(180, 176, 168), M.Concrete, { collide = true })
	-- lawn, hedge along the front, a tree, the mailbox at the kerb
	part(m, "Lawn", V3(W + 36, 0.16, kerbDist + D / 2 + 4), base * CF(4, 0.08, (-kerbDist + D / 2 + 4) / 2), ({ K.GRASS, K.GRASS_DRY, Color3.fromRGB(104, 150, 78) })[i % 3 + 1], M.Grass, { collide = true })
	K.hedge(m, base * CF(W * 0.3, 0.16, -D / 2 - 2.2), 11, 3.2, 2.4)
	K.tree(m, (base * CF(-W / 2 - 8, 0.16, -D / 2 - 6)).Position, ({ "oak", "maple", "birch", "cherry" })[i % 4 + 1], rng:NextNumber(30, 42), rng)
	local mb = base * CF(doorX + 5, 0, -kerbDist + 2)
	part(m, "MailboxPost", V3(0.3, 4, 0.3), mb * CF(0, 2, 0), C.wood, M.Wood)
	part(m, "Mailbox", V3(1.0, 1.0, 1.8), mb * CF(0, 4.4, 0), ({ C.black, C.blue, C.red })[i % 3 + 1], M.Metal)
	if rng:NextNumber() < 0.6 then
		K.car(m, base * CF(gx, 0.2, -D / 2 - 14) * ANG(0, RAD(180), 0), K.CAR_COLORS[rng:NextInteger(1, #K.CAR_COLORS)], ({ "sedan", "suv", "pickup", "hatch" })[rng:NextInteger(1, 4)])
	end
	-- a few things that say somebody lives here
	local srng = Random.new(900 + i)
	local story = {}
	for k = 1, 6 do
		story[k] = k
	end
	for k = #story, 2, -1 do
		local j = srng:NextInteger(1, k)
		story[k], story[j] = story[j], story[k]
	end
	for n = 1, 2 do
		local kind = story[n]
		if kind == 1 then -- bins at the kerb
			for k, col in ipairs({ Color3.fromRGB(40, 90, 50), Color3.fromRGB(40, 60, 120) }) do
				part(m, "Bin", V3(2.0, 3.6, 2.0), base * CF(gx - 10 + k * 2.4, 1.8, -kerbDist + 2), col, M.SmoothPlastic, { collide = true })
			end
		elseif kind == 2 then -- porch light that comes on at dusk
			part(m, "PorchLamp", V3(0.6, 0.9, 0.4), base * CF(doorX + 2.6, 7.4, -D / 2 - 0.3), Color3.fromRGB(255, 230, 170), M.Neon, { shadow = false })
			nightPoint(m, base * CF(doorX + 2.6, 7.2, -D / 2 - 1.6), Color3.fromRGB(255, 214, 150), 16, 0.8)
		elseif kind == 3 then -- a heavy bag under a frame in the side yard
			part(m, "YardBagFrame", V3(0.4, 10, 0.4), base * CF(-W / 2 - 4, 5, D / 2 - 2), C.steel, M.Metal)
			part(m, "YardBagArm", V3(3, 0.4, 0.4), base * CF(-W / 2 - 5.4, 9.8, D / 2 - 2), C.steel, M.Metal)
			part(m, "BagChain", V3(0.15, 1.6, 0.15), base * CF(-W / 2 - 6.6, 8.9, D / 2 - 2), C.steelLight, M.Metal)
			cyl(m, "YardBag", 4.4, 1.9, base * CF(-W / 2 - 6.6, 5.9, D / 2 - 2) * ANG(0, 0, RAD(90)), Color3.fromRGB(120, 26, 30), M.Leather)
		elseif kind == 4 then -- lawn sign cheering on the local fighter (CityVisuals writes your name on it)
			part(m, "LawnSignStake", V3(0.15, 3, 0.15), base * CF(W * 0.34, 1.5, -D / 2 - 9), C.wood, M.Wood)
			local ls = part(m, "LawnSign", V3(3.2, 2.0, 0.08), base * CF(W * 0.34, 3.4, -D / 2 - 9), C.white, M.SmoothPlastic)
			GymDecor.Sign(ls, Enum.NormalId.Front, "SUPPORT\nLOCAL BOXING", C.red, C.white, 40)
			ls:SetAttribute("Kind", "LawnSign")
			tag(ls, "CityScreen")
		elseif kind == 5 then -- picket fence along the front lawn
			local fa = (base * CF(-W / 2 - 18, 0.16, -kerbDist + 3)).Position
			local fb = (base * CF(doorX - 3, 0.16, -kerbDist + 3)).Position
			K.fencePicket(m, fa, fb)
		else -- a basketball hoop over the driveway and a kid's bike
			part(m, "HoopPole", V3(0.4, 12, 0.4), base * CF(gx + 7.4, 6, -D / 2 - 8), C.steel, M.Metal)
			part(m, "HoopBoard", V3(4.4, 3, 0.2), base * CF(gx + 6.6, 11.4, -D / 2 - 8) * ANG(0, RAD(90), 0), C.white, M.SmoothPlastic)
			cyl(m, "HoopRim", 0.2, 1.8, base * CF(gx + 5.4, 10.2, -D / 2 - 8) * ANG(0, 0, RAD(90)), Color3.fromRGB(240, 110, 30), M.Metal)
		end
	end
	return m
end

-- the empty lot on Oak Street that becomes YOUR house (CityVisuals.houseBuild builds it at the site)
local function homeLot(f, center, front, kerbDist)
	local base = CFrame.lookAt(center, center + front)
	part(f, "HomeLawn", V3(66, 0.16, kerbDist + 24), base * CF(2, 0.08, (-kerbDist + 24) / 2 - 2), Color3.fromRGB(84, 134, 66), M.Grass, { collide = true })
	part(f, "Driveway", V3(14, 0.2, kerbDist - 4), base * CF(19, 0.1, -(kerbDist + 4) / 2 - 2), Color3.fromRGB(150, 148, 144), M.Concrete, { collide = true })
	part(f, "LotPath", V3(3.6, 0.18, kerbDist - 15), base * CF(-7, 0.09, -(kerbDist + 15) / 2), Color3.fromRGB(180, 176, 168), M.Concrete, { collide = true })
	for _, x in ipairs({ -32, 36 }) do
		K.hedge(f, base * CF(x, 0.16, -4) * ANG(0, RAD(90), 0), 44, 3.6, 2.4)
	end
	part(f, "SignPost", V3(0.3, 7, 0.3), base * CF(6, 3.5, -kerbDist + 6), C.white, M.Wood)
	local rs = part(f, "RealtySign", V3(5.6, 3.6, 0.12), base * CF(6, 6, -kerbDist + 6), Color3.fromRGB(180, 30, 36), M.SmoothPlastic)
	GymDecor.Sign(rs, Enum.NormalId.Front, "FOR SALE\nCITY REALTY\n$400,000", C.white, Color3.fromRGB(180, 30, 36), 40)
	rs:SetAttribute("Kind", "ForSale")
	rs:SetAttribute("Home", "House")
	tag(rs, "CityScreen")
	site("HomeHouse", base)
	promptPart(f, "HomePrompt", (base * CF(-7, 2.6, -14)).Position, "Enter house", "Oak Street", { Action = "Home", Kind = "House" }, Color3.fromRGB(255, 230, 170))
end

local function buildWest(root)
	local f = folder(root, "Residential")
	local rng = Random.new(808)
	local OAK, CEDAR = CITY.OakStreet, CITY.CedarLane
	local half = OAK.w / 2
	K.roadZ(f, "OakStreet", OAK.z0, OAK.z1, OAK.x, OAK.w, { y = ROAD_Y - 0.004, sw = { w = 8, e = 8 }, gapsE = { { CEDAR.z - 12.5, CEDAR.z + 12.5 } }, lineColor = K.LINE_YELLOW })
	K.roadX(f, "CedarLane", CEDAR.x0, CEDAR.x1, CEDAR.z, CEDAR.w, { sw = { n = 7, s = 7 } })
	K.lawn(f, OAK.x + half + 9, LOOP.x0 - LW - OUTER - 0.6, OAK.z0, CEDAR.z - 20, rng, { patches = 4 })
	K.lawn(f, OAK.x + half + 9, LOOP.x0 - LW - OUTER - 0.6, CEDAR.z + 20, MAIN.frontN - 1, rng, { patches = 4 })
	K.lawn(f, -560, OAK.x - half - 9, OAK.z0, MAIN.z0 - 11, rng, { patches = 5 })
	-- the houses: east side (facing west) at x -384, west side (facing east) at x -496, 64-stud lots
	local i = 0
	local kerbE = 44 -- house centre to the kerb
	for z = -608, 230, 64 do
		if math.abs(z - CEDAR.z) > 36 then
			i += 1
			if z == 224 then
				homeLot(f, V3(OAK.x + half + kerbE, 0, z), V3(-1, 0, 0), kerbE)
			else
				house(f, V3(OAK.x + half + kerbE, 0, z), V3(-1, 0, 0), rng, i, kerbE)
			end
			K.kerbRamp(f, V3(OAK.x + half + 1.2, 0, z - 27), V3(-1, 0, 0), 14)
		end
	end
	for z = -576, 262, 64 do
		i += 1
		house(f, V3(OAK.x - half - kerbE, 0, z), V3(1, 0, 0), rng, i, kerbE)
		K.kerbRamp(f, V3(OAK.x - half - 1.2, 0, z + 27), V3(1, 0, 0), 14)
	end
	-- residential lights (6 m) alternating sides, street trees between the drives
	local k = 0
	for z = OAK.z0 + 30, OAK.z1 - 20, 64 do
		k += 1
		local side = (k % 2 == 0) and 1 or -1
		K.streetLight(f, V3(OAK.x + side * (half + 1.6), SW_H, z), V3(-side, 0, 0), k % 3 ~= 0, CITY.ResidentialLight)
	end
	for z = OAK.z0 + 10, OAK.z1 - 30, 32 do
		if math.abs(z - CEDAR.z) > 20 then
			K.tree(f, V3(OAK.x + half + 11, 0.16, z), "oak", rng:NextNumber(30, 40), rng)
		end
		K.tree(f, V3(OAK.x - half - 11, 0.16, z + 16), ({ "oak", "maple" })[(z // 32) % 2 + 1], rng:NextNumber(30, 40), rng)
	end
	K.streetSign(f, V3(OAK.x + half + 2, SW_H, CEDAR.z - 15), "OAK ST", RAD(90), "CEDAR LN")
	K.roadSign(f, V3(OAK.x + half + 2, SW_H, CEDAR.z + 15), RAD(90), "stop")
	K.roadSign(f, V3(OAK.x - half - 2, SW_H, MAIN.z0 - 16), RAD(-90), "stop")
	K.roadSign(f, V3(OAK.x + half + 2, SW_H, -300), RAD(90), "speed", "20")
	K.crosswalk(f, V3(OAK.x, 0, CEDAR.z + 17), true, OAK.w, 8)
	K.crosswalk(f, V3(CEDAR.x0 + 16, 0, CEDAR.z), false, CEDAR.w, 8)
	K.crosswalk(f, V3(CEDAR.x1 - 10, 0, CEDAR.z), false, CEDAR.w, 8)
	lightsX(f, CEDAR.x0 + 30, CEDAR.x1 - 20, CEDAR.z - 12.5 - 1.6, V3(0, 0, 1), 70, CITY.ResidentialLight, 2)
	-- a corner store at Cedar Lane and a playground on the greenway
	K.building(f, CF(OAK.x + half + 8.6 + 20, 0, CEDAR.z - 12.5 - 7.6), 40, 30, 1, { color = Color3.fromRGB(176, 60, 44), mat = M.Brick, sign = "OAK ST GROCERY", signBg = Color3.fromRGB(30, 110, 60), signFg = C.white, awning = Color3.fromRGB(30, 110, 60), rng = rng, name = "CornerStore" })
	local pg = V3(-330, 0.16, 60)
	part(f, "PlaygroundBark", V3(50, 0.2, 36), CF(pg + V3(0, 0.1, 0)), Color3.fromRGB(120, 86, 56), M.Ground, { collide = true })
	for k2 = 0, 2 do
		part(f, "SwingPost", V3(0.5, 10, 0.5), CF(pg + V3(-16 + k2 * 10, 5, -8)), Color3.fromRGB(200, 40, 40), M.Metal, { collide = true })
	end
	part(f, "SwingBeam", V3(22, 0.5, 0.5), CF(pg + V3(-6, 10, -8)), Color3.fromRGB(200, 40, 40), M.Metal)
	for _, x in ipairs({ -12, -2 }) do
		part(f, "SwingSeat", V3(2, 0.3, 0.8), CF(pg + V3(x, 3, -8)), C.black, M.Rubber)
		for _, dx in ipairs({ -0.8, 0.8 }) do
			part(f, "SwingChain", V3(0.1, 7, 0.1), CF(pg + V3(x + dx, 6.6, -8)), C.steelLight, M.Metal, { shadow = false })
		end
	end
	part(f, "SlideTower", V3(6, 8, 6), CF(pg + V3(14, 4, 6)), Color3.fromRGB(40, 110, 200), M.SmoothPlastic, { collide = true })
	part(f, "SlideRoof", V3(7, 1, 7), CF(pg + V3(14, 9.5, 6)) * ANG(0, RAD(45), 0), Color3.fromRGB(240, 170, 60), M.SmoothPlastic)
	part(f, "Slide", V3(3, 0.4, 14), CF(pg + V3(14, 4.2, 15)) * ANG(RAD(32), 0, 0), Color3.fromRGB(240, 200, 40), M.SmoothPlastic, { collide = true })
	part(f, "SlideLadder", V3(2.4, 8, 0.4), CF(pg + V3(14, 4, 2.8)), C.steelLight, M.Metal, { collide = true })
	K.bench(f, V3(pg.X - 20, 0.3, pg.Z + 20), RAD(180), 6.4, C.wood)
	K.bench(f, V3(pg.X + 20, 0.3, pg.Z + 20), RAD(180), 6.4, C.wood)
	K.bin(f, V3(pg.X, 0.3, pg.Z + 20))
	for _, p in ipairs({ V3(-300, 0.16, -160), V3(-340, 0.16, -100), V3(-290, 0.16, 130), V3(-360, 0.16, 190), V3(-310, 0.16, -230) }) do
		K.tree(f, p, rng:NextNumber() < 0.5 and "oak" or "pine", rng:NextNumber(34, 46), rng)
	end
	-- the hills west of the houses, a water tower and a radio mast on them
	local hills = folder(f, "Hills")
	local hillCols = { Color3.fromRGB(86, 128, 70), Color3.fromRGB(96, 136, 72), Color3.fromRGB(78, 118, 66), Color3.fromRGB(104, 140, 80) }
	for k2, h in ipairs({
		{ -760, -520, 420, 90, 380 }, { -900, -160, 520, 120, 460 }, { -780, 160, 380, 70, 300 }, { -1000, -700, 560, 140, 520 },
		{ -1050, 360, 440, 90, 420 }, { -840, -1000, 600, 110, 500 }, { -1150, -300, 500, 160, 460 },
	}) do
		blob(hills, "Hill", V3(h[3], h[4], h[5]), CF(h[1], -h[4] * 0.15, h[2]), hillCols[k2 % #hillCols + 1], M.Grass, { collide = false })
	end
	for _ = 1, 26 do
		local p = V3(rng:NextNumber(-760, -600), 0.16, rng:NextNumber(-640, 280))
		K.tree(hills, p, "pine", rng:NextNumber(36, 54), rng)
	end
	local wt = V3(-700, 42, -380)
	for _, o in ipairs({ { -7, -7 }, { 7, -7 }, { -7, 7 }, { 7, 7 } }) do
		rod(hills, "TowerLeg", V3(wt.X + o[1] * 1.4, 0, wt.Z + o[2] * 1.4), wt + V3(o[1], 0, o[2]), 1.0, C.steel, M.Metal)
	end
	vcyl(hills, "WaterTower", 24, 26, CF(wt), Color3.fromRGB(220, 222, 226), M.Metal)
	blob(hills, "WaterTowerCap", V3(27, 10, 27), CF(wt + V3(0, 26, 0)), Color3.fromRGB(200, 202, 206), M.Metal)
	local wts = part(hills, "WaterTowerSign", V3(20, 6, 0.3), CF(wt + V3(0, 14, 13.2)), Color3.fromRGB(220, 222, 226), M.SmoothPlastic)
	GymDecor.Sign(wts, Enum.NormalId.Back, "OAKRIDGE", Color3.fromRGB(30, 60, 160), Color3.fromRGB(220, 222, 226), 30)
	local mast = V3(-960, 24, -80)
	part(hills, "RadioMast", V3(2.4, 150, 2.4), CF(mast + V3(0, 75, 0)), Color3.fromRGB(200, 60, 60), M.Metal)
	ball(hills, "MastLight", 2.4, CF(mast + V3(0, 151, 0)), Color3.fromRGB(255, 40, 40), M.Neon, { shadow = false })
end

------------------------------------------------------------------------
-- Hillcrest Estates: the gated plot at the top of Oak Street. Everyone sees the walls, the gate, the
-- gardens and the empty villa podium; a Mansion owner sees their villa, pool and garage on it
-- (CityVisuals) and the gate opens for them (locally).
------------------------------------------------------------------------
local ESTATE = { x0 = -620, x1 = -260, z0 = -920, z1 = -690, gateX = -440 }
CityMap.Estate = ESTATE

local function buildEstates(root)
	local f = folder(root, "Estates")
	local rng = Random.new(4242)
	local E = ESTATE
	local gx = E.gateX
	local brick = Color3.fromRGB(150, 128, 104)
	local stone = Color3.fromRGB(214, 206, 190)
	slab(f, "EstateLawn", E.x0, E.x1, E.z0, E.z1, 0.3, Color3.fromRGB(78, 132, 62), M.Grass)
	K.wall(f, V3(E.x0, 0.3, E.z1), V3(gx - 16, 0.3, E.z1), 7, brick, M.Brick, stone)
	K.wall(f, V3(gx + 16, 0.3, E.z1), V3(E.x1, 0.3, E.z1), 7, brick, M.Brick, stone)
	K.wall(f, V3(E.x0, 0.3, E.z0), V3(E.x1, 0.3, E.z0), 7, brick, M.Brick, stone)
	K.wall(f, V3(E.x0, 0.3, E.z0), V3(E.x0, 0.3, E.z1), 7, brick, M.Brick, stone)
	K.wall(f, V3(E.x1, 0.3, E.z0), V3(E.x1, 0.3, E.z1), 7, brick, M.Brick, stone)
	for x = E.x0, E.x1, 36 do
		for _, z in ipairs({ E.z0, E.z1 }) do
			if math.abs(x - gx) > 20 then
				part(f, "WallPillar", V3(2.6, 9, 2.6), CF(x, 4.8, z), stone, M.Limestone, { collide = true })
			end
		end
	end
	-- gate: two pillars with lamps, two wrought-iron leaves (one Model each so CityVisuals can swing
	-- them open for the owner; the collider is the leaf's PrimaryPart)
	for _, sx in ipairs({ -1, 1 }) do
		local px = gx + sx * 17.5
		part(f, "GatePillar", V3(3.4, 12, 3.4), CF(px, 6.3, E.z1), stone, M.Limestone, { collide = true })
		ball(f, "GateLamp", 1.6, CF(px, 13, E.z1), Color3.fromRGB(255, 236, 200), M.Neon, { shadow = false })
		nightPoint(f, CF(px, 12.4, E.z1 + 2), Color3.fromRGB(255, 220, 170), 24, 1)
		local leaf = model(f, "GateLeaf")
		local hinge = gx + sx * 15.6
		local col = part(leaf, "GateCollider", V3(15.6, 10.5, 0.5), CF(gx + sx * 7.8, 5.5, E.z1), Color3.new(), M.SmoothPlastic, { transparency = 1, collide = true })
		leaf.PrimaryPart = col
		leaf:SetAttribute("Hinge", hinge)
		leaf:SetAttribute("Side", sx)
		for _, y in ipairs({ 0.9, 9.8 }) do
			part(leaf, "GateRail", V3(15.6, 0.35, 0.35), CF(gx + sx * 7.8, y, E.z1), Color3.fromRGB(26, 26, 28), M.Metal)
		end
		for k = 0, 9 do
			part(leaf, "GateBar", V3(0.25, 9.4 + (k % 2) * 0.9, 0.25), CF(gx + sx * (0.8 + k * 1.6), 5.4 + (k % 2) * 0.45, E.z1), Color3.fromRGB(26, 26, 28), M.Metal)
		end
		ball(leaf, "GateCrest", 1.4, CF(gx + sx * 7.8, 6.4, E.z1), C.gold, M.Metal)
	end
	local plaque = part(f, "EstatePlaque", V3(9, 2.4, 0.2), CF(gx - 26, 4.6, E.z1 + 0.7), Color3.fromRGB(40, 40, 44), M.Granite)
	Signage.Board(plaque, Enum.NormalId.Back, "estate", { maxDist = 500 })
	local rs = part(f, "RealtySign", V3(6.4, 3.6, 0.12), CF(gx + 28, 5.2, E.z1 + 3), Color3.fromRGB(180, 30, 36), M.SmoothPlastic)
	part(f, "SignPost", V3(0.3, 4, 0.3), CF(gx + 28, 2, E.z1 + 3), C.white, M.Wood)
	GymDecor.Sign(rs, Enum.NormalId.Back, "HILLCREST MANSION\nFOR SALE  $5,000,000\nCITY REALTY", C.white, Color3.fromRGB(180, 30, 36), 40)
	rs:SetAttribute("Kind", "ForSale")
	rs:SetAttribute("Home", "Mansion")
	tag(rs, "CityScreen")
	-- gatehouse just inside, the drive to the forecourt, a fountain, the villa podium
	local gh = CF(gx - 28, 0.3, E.z1 - 10)
	part(f, "Gatehouse", V3(10, 11, 10), gh * CF(0, 5.5, 0), stone, M.Limestone, { collide = true })
	part(f, "GatehouseRoof", V3(12.5, 0.8, 12.5), gh * CF(0, 11.3, 0), Color3.fromRGB(50, 50, 56), M.Slate)
	part(f, "GatehouseWindow", V3(5, 3.2, 0.1), gh * CF(0, 6.2, 5.05), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.3 })
	part(f, "GatehouseDoor", V3(CITY.Door.w, CITY.Door.h, 0.2), gh * CF(5.05, 0.3 + CITY.Door.h / 2, 0) * ANG(0, RAD(90), 0), Color3.fromRGB(60, 40, 28), M.Wood)
	nightPoint(f, gh * CF(0, 9.6, 6), Color3.fromRGB(255, 225, 180), 16, 0.8)
	slab(f, "EstateDrive", gx - 7, gx + 7, -810, E.z1 - 0.6, 0.42, Color3.fromRGB(196, 188, 172), M.Pavement)
	slab(f, "Forecourt", gx - 42, gx + 42, -838, -810, 0.42, Color3.fromRGB(196, 188, 172), M.Pavement)
	local fo = V3(gx, 0.42, -824)
	vcyl(f, "FountainBasin", 1.8, 14, CF(fo), stone, M.Limestone, { collide = true })
	vcyl(f, "FountainWater", 0.2, 12.6, CF(fo + V3(0, 1.6, 0)), Color3.fromRGB(70, 150, 210), M.Glass, { transparency = 0.25 })
	vcyl(f, "FountainPillar", 5, 2, CF(fo), stone, M.Limestone)
	vcyl(f, "FountainBowl", 0.9, 7, CF(fo + V3(0, 5, 0)), stone, M.Limestone)
	local jet = part(f, "FountainJet", V3(0.4, 0.4, 0.4), CF(fo + V3(0, 6.2, 0)), C.white, M.SmoothPlastic, { transparency = 1, shadow = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 18
	pe.Lifetime = NumberRange.new(0.9, 1.2)
	pe.Speed = NumberRange.new(9, 12)
	pe.SpreadAngle = Vector2.new(12, 12)
	pe.Acceleration = Vector3.new(0, -28, 0)
	pe.Size = NumberSequence.new(0.45, 0.2)
	pe.Transparency = NumberSequence.new(0.3, 0.85)
	pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	pe.Parent = jet
	part(f, "VillaPodium", V3(120, 1.0, 40), CF(gx, 0.5, -865), Color3.fromRGB(226, 220, 206), M.Limestone, { collide = true })
	part(f, "PodiumSteps", V3(24, 0.6, 3), CF(gx, 0.3, -843.5), Color3.fromRGB(226, 220, 206), M.Limestone, { collide = true })
	site("HomeMansion", CFrame.lookAt(V3(gx, 1.0, -865), V3(gx, 1.0, -800)))
	site("MansionPool", CFrame.lookAt(V3(gx - 90, 0.3, -840), V3(gx - 90, 0.3, -800)))
	site("MansionGarage", CFrame.lookAt(V3(gx + 100, 0.3, -870), V3(gx + 100, 0.3, -800)))
	site("EstateGate", CFrame.lookAt(V3(gx, 0.3, E.z1 + 14), V3(gx, 0.3, E.z1 - 20)))
	promptPart(f, "HomePrompt", V3(gx, 3.4, -841), "Enter mansion", "Hillcrest Estates", { Action = "Home", Kind = "Mansion" }, Color3.fromRGB(255, 220, 120))
	-- palms along the drive and round the forecourt, hedges inside the south wall, garden lamps
	for z = -710, -800, -24 do
		for _, sx in ipairs({ -1, 1 }) do
			K.tree(f, V3(gx + sx * 13, 0.3, z), "palm", rng:NextNumber(30, 40), rng)
		end
	end
	for _, x in ipairs({ -600, -540, -340, -280 }) do
		K.hedge(f, CF(x, 0.3, E.z1 - 5), 36, 4.4, 3.2, Color3.fromRGB(46, 104, 50))
	end
	for _, z in ipairs({ -730, -770 }) do
		for _, sx in ipairs({ -1, 1 }) do
			K.parkLamp(f, V3(gx + sx * 9.5, 0.3, z), true)
		end
	end
	for _ = 1, 14 do
		local p = V3(rng:NextNumber(E.x0 + 20, E.x1 - 20), 0.3, rng:NextNumber(E.z0 + 20, E.z1 - 40))
		if math.abs(p.X - gx) > 70 or p.Z < -890 then
			K.tree(f, p, ({ "oak", "pine", "cherry" })[rng:NextInteger(1, 3)], rng:NextNumber(32, 46), rng)
		end
	end
	K.flowerBed(f, CF(gx, 0.42, -845) * ANG(0, 0, 0), 60, 2.4, rng)
	lightZone(f, "EstateZone", V3(E.x1 - E.x0, 50, E.z1 - E.z0), CF((E.x0 + E.x1) / 2, 25, (E.z0 + E.z1) / 2), "Mansion")
end

------------------------------------------------------------------------
-- East: Riverside Park, Riverside Drive, the promenade, boardwalk, pier, the river and its bridge
------------------------------------------------------------------------
local function segDist(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function buildEast(root)
	local f = folder(root, "Park")
	local rng = Random.new(2024)
	local P, RD = CITY.Park, CITY.RiversideDrive
	-- the park lawn and its railings (gates on the loop side and on Main Street)
	K.lawn(f, P.x0, P.x1, P.z0, P.z1, rng, { patches = 6 })
	K.lawn(f, P.x0, 540, -277.5 + LW + 0.6 + OUTER, P.z0, rng, { patches = 2 }) -- the north meadow
	for _, r in ipairs(K.cutRanges(P.z0, P.z1, { { -106, -94 }, { 54, 66 }, { 194, 206 } })) do
		K.fenceIron(f, V3(P.x0, SW_H, r[1]), V3(P.x0, SW_H, r[2]), 5)
	end
	for _, z in ipairs({ -100, 60, 200 }) do
		K.kerbRamp(f, V3(LOOP.x1 + LW + 1.2, 0, z), V3(-1, 0, 0), 8)
		K.crosswalk(f, V3(LOOP.x1, 0, z), true, LOOP.w, 8)
	end
	-- paths: from the three west gates and the two south gates, meeting at the fountain plaza
	local fo = V3(480, 0, 40)
	local ct = V3(340, 0, -100) -- basketball court
	local pond = V3(610, 0, -70)
	local band = V3(400, 0, 190) -- bandstand
	local play = V3(640, 0, 190) -- playground
	local paths = {
		{ V3(P.x0, 0, -100), V3(ct.X - 50, 0, -100) }, { V3(ct.X + 50, 0, -100), V3(fo.X - 20, 0, 20) },
		{ V3(P.x0, 0, 60), V3(fo.X - 30, 0, 50) }, { V3(P.x0, 0, 200), V3(band.X - 20, 0, 196) }, { V3(band.X + 20, 0, 190), V3(fo.X, 0, 70) },
		{ V3(336, 0, P.z1), V3(band.X - 10, 0, 210) }, { V3(546, 0, P.z1), V3(fo.X + 20, 0, 70) }, { V3(fo.X + 30, 0, 40), V3(pond.X - 60, 0, -40) },
		{ V3(fo.X + 30, 0, 60), V3(play.X - 30, 0, 180) }, { V3(pond.X + 40, 0, -20), V3(RD.x - 12.5 - 9, 0, 40) }, { V3(play.X + 30, 0, 190), V3(RD.x - 12.5 - 9, 0, 200) },
	}
	for _, seg in ipairs(paths) do
		local a, b = seg[1], seg[2]
		part(f, "ParkPath", V3(8, 0.2, (b - a).Magnitude + 2), CFrame.lookAt((a + b) / 2 + V3(0, 0.26, 0), b + V3(0, 0.26, 0)), Color3.fromRGB(196, 176, 140), M.Pavement, { collide = true })
	end
	-- fountain plaza: paving, the big basin, a ring of benches and beds, lamps
	part(f, "FountainPlaza", V3(70, 0.2, 70), CF(fo + V3(0, 0.26, 0)), K.PAVING, M.Pavement, { collide = true })
	vcyl(f, "FountainBasin", 2.2, 30, CF(fo + V3(0, 0.3, 0)), Color3.fromRGB(170, 168, 162), M.Granite, { collide = true })
	vcyl(f, "FountainWater", 0.3, 28, CF(fo + V3(0, 2.1, 0)), Color3.fromRGB(70, 150, 210), M.Glass, { transparency = 0.25 })
	vcyl(f, "FountainPillar", 7, 3, CF(fo + V3(0, 0.3, 0)), Color3.fromRGB(180, 178, 172), M.Granite)
	vcyl(f, "FountainBowl", 1.2, 10, CF(fo + V3(0, 7.3, 0)), Color3.fromRGB(180, 178, 172), M.Granite)
	vcyl(f, "FountainBowlWater", 0.15, 9, CF(fo + V3(0, 8.4, 0)), Color3.fromRGB(80, 160, 220), M.Glass, { transparency = 0.2 })
	local jet = part(f, "FountainJet", V3(0.5, 0.5, 0.5), CF(fo + V3(0, 8.9, 0)), C.white, M.SmoothPlastic, { transparency = 1, shadow = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 40
	pe.Lifetime = NumberRange.new(1.0, 1.4)
	pe.Speed = NumberRange.new(13, 16)
	pe.SpreadAngle = Vector2.new(9, 9)
	pe.Acceleration = Vector3.new(0, -28, 0)
	pe.Size = NumberSequence.new(0.6, 0.25)
	pe.Transparency = NumberSequence.new(0.3, 0.8)
	pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	pe.LightEmission = 0.3
	pe.Parent = jet
	for k = 0, 7 do
		local a = k * RAD(45) + RAD(22.5)
		K.bench(f, fo + V3(math.cos(a) * 24, 0.46, math.sin(a) * 24), RAD(90) - a, 6.4, C.wood)
		if k % 2 == 0 then
			K.parkLamp(f, fo + V3(math.cos(a + RAD(22.5)) * 31, 0.46, math.sin(a + RAD(22.5)) * 31), true)
		else
			K.bin(f, fo + V3(math.cos(a + RAD(22.5)) * 30, 0.46, math.sin(a + RAD(22.5)) * 30))
		end
	end
	for _, a in ipairs({ 0, 90, 180, 270 }) do
		K.flowerBed(f, CF(fo + V3(math.cos(RAD(a)) * 20, 0.46, math.sin(RAD(a)) * 20)) * ANG(0, RAD(90 - a), 0), 10, 2, rng)
	end
	K.vendorCart(f, CF(fo + V3(-30, 0.46, -32)) * ANG(0, RAD(30), 0), "icecream")
	K.vendorCart(f, CF(fo + V3(34, 0.46, 30)) * ANG(0, RAD(-150), 0), "hotdog")
	-- the basketball court: full size with fence, two hoops, benches
	part(f, "CourtApron", V3(100, 0.24, 62), CF(ct + V3(0, 0.12, 0)), Color3.fromRGB(150, 150, 150), M.Concrete, { collide = true })
	part(f, "Court", V3(90, 0.3, 50), CF(ct + V3(0, 0.15, 0)), Color3.fromRGB(46, 92, 140), M.SmoothPlastic, { collide = true })
	local lines = part(f, "CourtLines", V3(90, 0.02, 50), CF(ct + V3(0, 0.31, 0)), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	local lg = gui(lines, Enum.NormalId.Top, 6, 1, 300)
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
		local hx = ct.X + s * 48
		part(f, "HoopPole", V3(0.6, 13, 0.6), CF(hx, 6.5, ct.Z), C.steel, M.Metal, { collide = true })
		part(f, "HoopArm", V3(4, 0.5, 0.5), CF(hx - s * 2, 12.4, ct.Z), C.steel, M.Metal)
		part(f, "Backboard", V3(0.25, 4, 6.4), CF(hx - s * 4, 12.4, ct.Z), C.white, M.SmoothPlastic, { transparency = 0.15 })
		cyl(f, "Rim", 0.2, 1.8, CF(hx - s * 5.2, 11.0, ct.Z) * ANG(0, 0, RAD(90)), Color3.fromRGB(240, 110, 30), M.Metal)
	end
	K.fenceChain(f, V3(ct.X - 50, 0.24, ct.Z - 31), V3(ct.X + 50, 0.24, ct.Z - 31), 12)
	K.fenceChain(f, V3(ct.X - 50, 0.24, ct.Z + 31), V3(ct.X - 6, 0.24, ct.Z + 31), 12)
	K.fenceChain(f, V3(ct.X + 6, 0.24, ct.Z + 31), V3(ct.X + 50, 0.24, ct.Z + 31), 12)
	K.fenceChain(f, V3(ct.X - 50, 0.24, ct.Z - 31), V3(ct.X - 50, 0.24, ct.Z + 31), 12)
	K.fenceChain(f, V3(ct.X + 50, 0.24, ct.Z - 31), V3(ct.X + 50, 0.24, ct.Z + 31), 12)
	ball(f, "Basketball", 1.1, CF(ct + V3(12, 0.85, 6)), Color3.fromRGB(230, 110, 30), M.Rubber)
	K.bench(f, ct + V3(-20, 0.24, 27), RAD(180), 6.4, C.wood)
	K.bench(f, ct + V3(20, 0.24, 27), RAD(180), 6.4, C.wood)
	for _, x in ipairs({ -48, 48 }) do
		K.streetLight(f, V3(ct.X + x, 0.24, ct.Z - 28), V3(-math.sign(x), 0, 0.3).Unit, true, 26)
	end
	-- the pond with its deck and a willow-ish birch group
	vcyl(f, "PondBank", 0.36, 150, CF(pond), Color3.fromRGB(150, 140, 110), M.Sand, { collide = true })
	vcyl(f, "Pond", 0.3, 136, CF(pond), Color3.fromRGB(52, 110, 150), M.Glass, { transparency = 0.2, reflect = 0.3, collide = true })
	part(f, "PondDeck", V3(24, 0.5, 30), CF(pond + V3(-62, 0.9, 10)), Color3.fromRGB(150, 116, 84), M.WoodPlanks, { collide = true })
	K.railing(f, pond + V3(-50, 1.1, -5), pond + V3(-50, 1.1, 25))
	K.railing(f, pond + V3(-74, 1.1, 25), pond + V3(-50, 1.1, 25))
	K.railing(f, pond + V3(-74, 1.1, -5), pond + V3(-50, 1.1, -5))
	K.bench(f, pond + V3(-66, 1.15, 10), RAD(90), 6.4, C.wood)
	for k = 0, 2 do
		local a = RAD(40 + k * 50)
		blob(f, "LilyPads", V3(6, 0.15, 5), CF(pond + V3(math.cos(a) * 50, 0.34, math.sin(a) * 50)), Color3.fromRGB(70, 130, 60), M.Grass, { shadow = false })
	end
	for k = 0, 5 do
		local a = RAD(k * 60 + 15)
		K.tree(f, pond + V3(math.cos(a) * 84, 0.14, math.sin(a) * 84), k % 2 == 0 and "birch" or "oak", rng:NextNumber(30, 44), rng)
	end
	-- the bandstand: a raised round stage under a conical roof on eight posts
	vcyl(f, "BandstandBase", 1.6, 32, CF(band), Color3.fromRGB(200, 196, 186), M.Concrete, { collide = true })
	vcyl(f, "BandstandFloor", 0.3, 28, CF(band + V3(0, 1.6, 0)), Color3.fromRGB(150, 116, 84), M.WoodPlanks, { collide = true })
	for k = 0, 7 do
		local a = k * RAD(45)
		vcyl(f, "BandstandPost", 12, 0.9, CF(band + V3(math.cos(a) * 12.5, 1.9, math.sin(a) * 12.5)), C.white, M.Wood, { collide = true })
	end
	K.railing(f, band + V3(12.5, 1.9, 0), band + V3(8.8, 1.9, 8.8), C.white)
	K.railing(f, band + V3(-12.5, 1.9, 0), band + V3(-8.8, 1.9, 8.8), C.white)
	K.railing(f, band + V3(-12.5, 1.9, 0), band + V3(-8.8, 1.9, -8.8), C.white)
	K.railing(f, band + V3(12.5, 1.9, 0), band + V3(8.8, 1.9, -8.8), C.white)
	blob(f, "BandstandRoof", V3(34, 12, 34), CF(band + V3(0, 13.6, 0)), Color3.fromRGB(60, 90, 70), M.Slate)
	vcyl(f, "BandstandFinial", 3, 1.2, CF(band + V3(0, 19.2, 0)), C.gold, M.Metal)
	nightPoint(f, CF(band + V3(0, 12, 0)), Color3.fromRGB(255, 226, 180), 30, 1)
	-- the playground: bark, a climbing frame with slide, swings, a seesaw, benches
	part(f, "PlaygroundBark", V3(60, 0.24, 44), CF(play + V3(0, 0.26, 0)), Color3.fromRGB(120, 86, 56), M.Ground, { collide = true })
	part(f, "SlideTower", V3(7, 9, 7), CF(play + V3(-16, 4.9, -8)), Color3.fromRGB(40, 110, 200), M.SmoothPlastic, { collide = true })
	part(f, "SlideRoof", V3(8, 1, 8), CF(play + V3(-16, 10.4, -8)) * ANG(0, RAD(45), 0), Color3.fromRGB(240, 170, 60), M.SmoothPlastic)
	part(f, "Slide", V3(3, 0.4, 16), CF(play + V3(-16, 4.8, 2)) * ANG(RAD(32), 0, 0), Color3.fromRGB(240, 200, 40), M.SmoothPlastic, { collide = true })
	part(f, "ClimbWall", V3(0.6, 9, 7), CF(play + V3(-19.6, 4.9, -8)), Color3.fromRGB(200, 60, 60), M.SmoothPlastic, { collide = true })
	for k = 0, 3 do
		part(f, "SwingPost", V3(0.5, 10, 0.5), CF(play + V3(2 + k * 8, 5.4, 12)), Color3.fromRGB(200, 40, 40), M.Metal, { collide = true })
	end
	part(f, "SwingBeam", V3(26, 0.5, 0.5), CF(play + V3(14, 10.4, 12)), Color3.fromRGB(200, 40, 40), M.Metal)
	for _, x in ipairs({ 6, 14, 22 }) do
		part(f, "SwingSeat", V3(2, 0.3, 0.8), CF(play + V3(x, 3.4, 12)), C.black, M.Rubber)
		for _, dx in ipairs({ -0.8, 0.8 }) do
			part(f, "SwingChain", V3(0.1, 7, 0.1), CF(play + V3(x + dx, 7, 12)), C.steelLight, M.Metal, { shadow = false })
		end
	end
	part(f, "Seesaw", V3(14, 0.4, 1.4), CF(play + V3(14, 2.4, -10)) * ANG(0, 0, RAD(12)), Color3.fromRGB(60, 160, 80), M.SmoothPlastic)
	part(f, "SeesawPivot", V3(1.4, 2.4, 1.4), CF(play + V3(14, 1.3, -10)), C.steel, M.Metal, { collide = true })
	for _, p in ipairs({ { -28, 24 }, { 28, 24 } }) do
		K.bench(f, play + V3(p[1], 0.38, p[2]), RAD(180), 6.4, C.wood)
	end
	K.bin(f, play + V3(0, 0.38, 25))
	K.fencePicket(f, play + V3(-32, 0.3, -24), play + V3(32, 0.3, -24))
	-- picnic tables, lamps along the paths, bins, the park signs at the gates, trees everywhere else
	local picnic = { V3(300, 0, -20), V3(430, 0, 120), V3(560, 0, 240), V3(700, 0, 110), V3(300, 0, 250), V3(690, 0, -150) }
	for k, p in ipairs(picnic) do
		K.picnicTable(f, p + V3(0, 0.14, 0), RAD(k * 37))
	end
	for _, seg in ipairs(paths) do
		local a, b = seg[1], seg[2]
		local n = math.max(1, math.floor((b - a).Magnitude / 70))
		for k = 1, n do
			local t = (k - 0.5) / n
			local p = a:Lerp(b, t)
			local side = (b - a).Unit:Cross(Vector3.yAxis) * 6
			K.parkLamp(f, p + side + V3(0, 0.14, 0), k % 2 == 1)
			if k % 2 == 0 then
				K.bench(f, p - side + V3(0, 0.14, 0), math.atan2((b - a).X, (b - a).Z), 6.4, C.wood)
			end
		end
	end
	for _, z in ipairs({ -100, 60, 200 }) do
		K.postSign(f, CF(P.x0 + 10, 0.14, z - 10) * ANG(0, RAD(90), 0), 14, 3.6, 5, "RIVERSIDE PARK", Color3.fromRGB(255, 230, 170), Color3.fromRGB(60, 40, 26))
	end
	local function clear(p)
		if (p - fo).Magnitude < 42 or (p - pond).Magnitude < 90 or (p - band).Magnitude < 24 then
			return false
		end
		if math.abs(p.X - ct.X) < 56 and math.abs(p.Z - ct.Z) < 38 then
			return false
		end
		if math.abs(p.X - play.X) < 36 and math.abs(p.Z - play.Z) < 28 then
			return false
		end
		for _, seg in ipairs(paths) do
			if segDist(p, seg[1], seg[2]) < 12 then
				return false
			end
		end
		for _, q in ipairs(picnic) do
			if (p - q).Magnitude < 12 then
				return false
			end
		end
		return true
	end
	local n, tries = 0, 0
	local kinds = { "oak", "oak", "maple", "pine", "birch", "cherry", "poplar" }
	while n < 64 and tries < 800 do
		tries += 1
		local p = V3(rng:NextNumber(P.x0 + 12, P.x1 - 12), 0.14, rng:NextNumber(P.z0 + 12, P.z1 - 12))
		if clear(p) then
			n += 1
			K.tree(f, p, kinds[rng:NextInteger(1, #kinds)], rng:NextNumber(30, 50), rng)
		end
	end
	for _ = 1, 14 do
		K.tree(f, V3(rng:NextNumber(P.x0 + 10, 530), 0.14, rng:NextNumber(-262, P.z0 - 8)), rng:NextNumber() < 0.6 and "pine" or "oak", rng:NextNumber(34, 50), rng)
	end
	lightZone(f, "ParkZone", V3(P.x1 - P.x0, 60, P.z1 - P.z0), CF((P.x0 + P.x1) / 2, 30, (P.z0 + P.z1) / 2), "Street")

	-- Riverside Drive, the promenade lawn with its path, the boardwalk, the quay railing, the pier
	local wf = folder(root, "Waterfront")
	K.roadZ(wf, "RiversideDrive", RD.z0, RD.z1, RD.x, RD.w, { y = ROAD_Y - 0.004, sw = { w = 8, e = 10 }, gaps = { { MAIN.z0, MAIN.z1 }, { CITY.SecondStreet.z - 12.5, CITY.SecondStreet.z + 12.5 }, { -302.5, -277.5 } } })
	lightsZ(wf, RD.z0 + 20, RD.z1 - 20, RD.x + 12.5 + 1.6, V3(-1, 0, 0), 70, nil, 2)
	K.lawn(wf, RD.x + 12.5 + 10.6, CITY.Boardwalk.x0, RD.z0, RD.z1, rng, { patches = 5 })
	slab(wf, "PromenadePath", 818, 826, RD.z0, RD.z1, 0.3, Color3.fromRGB(196, 176, 140), M.Pavement)
	local BW = CITY.Boardwalk
	slab(wf, "Boardwalk", BW.x0, BW.x1, RD.z0, RD.z1, SW_H, Color3.fromRGB(140, 104, 72), M.WoodPlanks)
	slab(wf, "QuayWall", BW.x1, BW.x1 + 2, RD.z0, RD.z1, SW_H, Color3.fromRGB(110, 106, 100), M.Concrete, true, -9)
	for _, r in ipairs(K.cutRanges(RD.z0, RD.z1, { { 52, 68 }, { -300, -280 } })) do
		K.railing(wf, V3(BW.x1 + 1, SW_H, r[1]), V3(BW.x1 + 1, SW_H, r[2]))
	end
	for z = RD.z0 + 30, RD.z1 - 30, 60 do
		K.bench(wf, V3(BW.x0 + 6, SW_H, z), RAD(-90), 6.4, C.wood)
		K.parkLamp(wf, V3(BW.x0 + 2, SW_H, z + 30), true)
		if z % 120 == 30 then
			K.bin(wf, V3(BW.x0 + 3, SW_H, z + 10))
		end
	end
	for z = RD.z0 + 50, RD.z1 - 50, 90 do
		K.tree(wf, V3(800, 0.14, z), ({ "oak", "cherry", "poplar" })[(z // 90) % 3 + 1], rng:NextNumber(30, 40), rng)
	end
	-- the pier
	local pz = 60
	slab(wf, "PierDeck", BW.x1, BW.x1 + 110, pz - 8, pz + 8, SW_H + 0.1, Color3.fromRGB(130, 96, 66), M.WoodPlanks, true, SW_H - 0.6)
	for x = BW.x1 + 10, BW.x1 + 108, 14 do
		for _, dz in ipairs({ -7, 7 }) do
			vcyl(wf, "PierPile", 12, 1.6, CF(x, -10, pz + dz), Color3.fromRGB(80, 60, 44), M.Wood)
		end
	end
	K.railing(wf, V3(BW.x1 + 1, SW_H + 0.1, pz - 8), V3(BW.x1 + 110, SW_H + 0.1, pz - 8))
	K.railing(wf, V3(BW.x1 + 1, SW_H + 0.1, pz + 8), V3(BW.x1 + 110, SW_H + 0.1, pz + 8))
	K.railing(wf, V3(BW.x1 + 110, SW_H + 0.1, pz - 8), V3(BW.x1 + 110, SW_H + 0.1, pz + 8))
	for _, x in ipairs({ BW.x1 + 36, BW.x1 + 80 }) do
		K.parkLamp(wf, V3(x, SW_H + 0.1, pz - 6), true)
		K.bench(wf, V3(x, SW_H + 0.1, pz + 5), RAD(180), 6.4, C.wood)
	end
	local pav = V3(BW.x1 + 96, SW_H + 0.1, pz)
	for _, c in ipairs({ { -6, -6 }, { 6, -6 }, { 6, 6 }, { -6, 6 } }) do
		vcyl(wf, "PavilionPost", 10, 0.8, CF(pav + V3(c[1], 0, c[2])), C.white, M.Wood, { collide = true })
	end
	part(wf, "PavilionRoof", V3(15, 0.6, 15), CF(pav + V3(0, 10.3, 0)), Color3.fromRGB(40, 80, 120), M.Metal)
	blob(wf, "PavilionTop", V3(14, 6, 14), CF(pav + V3(0, 12, 0)), Color3.fromRGB(40, 80, 120), M.Metal)
	local ps = part(wf, "PierSign", V3(16, 3, 0.3), CF(BW.x1 + 4, SW_H + 9, pz) * ANG(0, RAD(90), 0), Color3.fromRGB(20, 40, 60), M.SmoothPlastic)
	for _, dz in ipairs({ -7.5, 7.5 }) do
		part(wf, "PierSignPost", V3(0.6, 7.5, 0.6), CF(BW.x1 + 4, SW_H + 3.75, pz + dz), Color3.fromRGB(20, 40, 60), M.Metal, { collide = true })
	end
	GymDecor.Sign(ps, Enum.NormalId.Front, "RIVERSIDE PIER", Color3.fromRGB(255, 230, 170), Color3.fromRGB(20, 40, 60), 30)
	GymDecor.Sign(ps, Enum.NormalId.Back, "RIVERSIDE PIER", Color3.fromRGB(255, 230, 170), Color3.fromRGB(20, 40, 60), 30)
	-- moored boats
	for k, bz in ipairs({ pz - 16, pz + 18, pz + 34 }) do
		local bc = CF(BW.x1 + 30 + k * 14, -1.2, bz) * ANG(0, RAD(90 + k * 6), 0)
		part(wf, "BoatHull", V3(6, 2.6, 18), bc * CF(0, 0.6, 0), ({ C.white, Color3.fromRGB(30, 60, 120), Color3.fromRGB(200, 40, 40) })[k], M.SmoothPlastic)
		part(wf, "BoatBow", V3(6, 2.6, 5), bc * CF(0, 0.6, -11.5), ({ C.white, Color3.fromRGB(30, 60, 120), Color3.fromRGB(200, 40, 40) })[k], M.SmoothPlastic, { class = "WedgePart" })
		part(wf, "BoatCabin", V3(4.4, 2.4, 6), bc * CF(0, 3.1, 2), Color3.fromRGB(240, 240, 236), M.SmoothPlastic)
		vcyl(wf, "BoatMast", 16, 0.3, bc * CF(0, 1.9, -3), C.steelLight, M.Metal)
	end
	-- the boathouse at the north end of the promenade
	local bh = CF(828, 0, -230)
	part(wf, "Boathouse", V3(44, 16, 30), bh * CF(0, 8, 0), Color3.fromRGB(96, 120, 140), M.WoodPlanks, { collide = true })
	local ra = (bh * CF(0, 16 + 3.5, -7.5)).Position
	local rb = (bh * CF(0, 16 + 3.5, 7.5)).Position
	part(wf, "BoathouseRoof", V3(46, 7, 15.6), CFrame.lookAt(ra, ra + V3(0, 0, -1)), Color3.fromRGB(60, 62, 70), M.Slate, { class = "WedgePart" })
	part(wf, "BoathouseRoof", V3(46, 7, 15.6), CFrame.lookAt(rb, rb + V3(0, 0, 1)), Color3.fromRGB(60, 62, 70), M.Slate, { class = "WedgePart" })
	part(wf, "BoathouseDoor", V3(0.4, 11, 14), bh * CF(22.1, 5.5, 0), Color3.fromRGB(200, 60, 60), M.Wood)
	local bs = part(wf, "BoathouseSign", V3(30, 3, 0.3), bh * CF(0, 12.5, 15.2), Color3.fromRGB(20, 40, 60), M.SmoothPlastic)
	GymDecor.Sign(bs, Enum.NormalId.Back, "RIVERSIDE BOATHOUSE  -  ROWING CLUB", Color3.fromRGB(255, 230, 170), Color3.fromRGB(20, 40, 60), 30)
	-- the river, the far bank and the bridge carrying Foundry Street across
	local R = CITY.River
	local B = CITY.Bounds
	K.water(wf, R.x0, R.x1, B.z0, B.z1, -1.6, 7)
	slab(wf, "FarBank", R.x1, R.x1 + 3, B.z0, B.z1, 0.6, Color3.fromRGB(110, 106, 100), M.Concrete, true, -9)
	local bz = CITY.FoundryStreet.z
	slab(wf, "BridgeApproach", RD.x + 12.5, 783, bz - 12.5, bz + 12.5, ROAD_Y, K.ASPHALT, M.Asphalt)
	slab(wf, "Bridge", 843, R.x1 + 2, bz - 14, bz + 14, 6, K.ASPHALT, M.Asphalt, true, 4.2)
	K.dashesX(wf, 843, R.x1, bz, K.LINE_YELLOW)
	-- (the deck sits 5.7 above the road: ramps either side)
	for _, r in ipairs({ { 813, -1 }, { 1182, 1 } }) do
		local rc = CFrame.lookAt(V3(r[1], 3.15, bz), V3(r[1] + r[2], 3.15, bz))
		part(wf, "BridgeRamp", V3(28, 5.7, 60), rc, K.ASPHALT, M.Asphalt, { class = "WedgePart", collide = true })
	end
	for _, dz in ipairs({ -14.5, 14.5 }) do
		K.railing(wf, V3(843, 6, bz + dz), V3(R.x1 + 2, 6, bz + dz), Color3.fromRGB(60, 90, 120))
		for x = 900, R.x1 - 20, 60 do
			K.streetLight(wf, V3(x, 6, bz + dz), V3(0, 0, -math.sign(dz)), (x // 60) % 2 == 0, 26)
		end
	end
	for x = 920, R.x1 - 40, 80 do
		part(wf, "BridgePier", V3(10, 16, 32), CF(x, -4, bz), Color3.fromRGB(120, 116, 110), M.Concrete)
	end
	for _, dz in ipairs({ -16, 16 }) do
		for _, x in ipairs({ 940, 1090 }) do
			part(wf, "BridgePylon", V3(4, 44, 4), CF(x, 22, bz + dz), Color3.fromRGB(60, 90, 120), M.Metal)
		end
		rod(wf, "BridgeCable", V3(940, 44, bz + dz), V3(1015, 10, bz + dz), 0.5, C.steelLight, M.Metal)
		rod(wf, "BridgeCable", V3(1090, 44, bz + dz), V3(1015, 10, bz + dz), 0.5, C.steelLight, M.Metal)
		rod(wf, "BridgeCable", V3(940, 44, bz + dz), V3(880, 8, bz + dz), 0.5, C.steelLight, M.Metal)
		rod(wf, "BridgeCable", V3(1090, 44, bz + dz), V3(1148, 8, bz + dz), 0.5, C.steelLight, M.Metal)
	end
end
