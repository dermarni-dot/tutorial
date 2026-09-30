-- Landscape (ModuleScript) — ServerScriptService.Modules.Landscape
-- The land around the city: terrain grass (with swaying grass blades),
-- rolling hills with pine forests, a lake with a sandy beach and a wooden
-- pier for fishing, and snowy mountains on the horizon.

local MapKit = require(script.Parent:WaitForChild("MapKit"))
local Streets = require(script.Parent:WaitForChild("Streets"))

local Landscape = {}

local deco, part, rgb = MapKit.deco, MapKit.part, MapKit.rgb
local EXTENT = MapKit.EXTENT

-- The lake sits outside the city to the south-west
Landscape.LAKE = Vector3.new(-EXTENT - 190, 0, EXTENT + 150)
Landscape.LAKE_RADIUS = 110

function Landscape.build(parent, rng)
	local folder = Instance.new("Folder")
	folder.Name = "Landscape"
	folder.Parent = parent
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local useTerrain = terrain ~= nil and pcall(function()
		return terrain.FillBlock
	end) and type(terrain.FillBlock) == "function"
	local fishingSpots = {}

	local size = EXTENT * 2 + 1800
	if useTerrain then
		-- a big flat grass plain; the city sits on top of it
		terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(size, 12, size), Enum.Material.Grass)
		-- rolling hills outside the city
		for n = 1, 28 do
			local a = n / 28 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local r = EXTENT + rng:NextNumber(140, 420)
			local p = Vector3.new(math.cos(a) * r, -rng:NextNumber(20, 34), math.sin(a) * r)
			if (p - Landscape.LAKE).Magnitude > Landscape.LAKE_RADIUS + 90 then
				terrain:FillBall(p, rng:NextNumber(45, 80), Enum.Material.Grass)
			end
		end
		-- mountains on the horizon
		for n = 1, 12 do
			local a = n / 12 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
			local r = EXTENT + rng:NextNumber(700, 820)
			local height = rng:NextNumber(150, 230)
			local p = Vector3.new(math.cos(a) * r, -height * 0.35, math.sin(a) * r)
			terrain:FillBall(p, height, Enum.Material.Rock)
			terrain:FillBall(p + Vector3.new(0, height * 0.72, 0), height * 0.38, Enum.Material.Snow)
		end
		-- the lake: sand shore, then water
		local L = Landscape.LAKE
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -3, 0)), 6, Landscape.LAKE_RADIUS + 16, Enum.Material.Sand)
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -5, 0)), 10, Landscape.LAKE_RADIUS, Enum.Material.Air)
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -6, 0)), 10, Landscape.LAKE_RADIUS, Enum.Material.Water)
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -12, 0)), 4, Landscape.LAKE_RADIUS, Enum.Material.Sand)
		-- no terrain grass under the city: it would grow up through the roads,
		-- sidewalks and floors. The city stands on its own paved base (below).
		local cityW = EXTENT * 2 + 40
		terrain:FillBlock(CFrame.new(0, -4, 0), Vector3.new(cityW, 16, cityW), Enum.Material.Air)
		terrain:FillBlock(CFrame.new(0, -12, 0), Vector3.new(cityW, 8, cityW), Enum.Material.Asphalt)
		-- swaying grass on the hills around the city (the city itself has no
		-- terrain under it, so no blades come up through floors or roads),
		-- and clear, reflective water with gentle waves
		pcall(function()
			terrain.Decoration = true
			terrain.WaterColor = rgb(40, 110, 130)
			terrain.WaterReflectance = 0.85
			terrain.WaterTransparency = 0.55
			terrain.WaterWaveSize = 0.12
			terrain.WaterWaveSpeed = 8
		end)
	else
		-- no terrain (tests): a simple ground plate and a water disc
		part(folder, "Ground", Vector3.new(size, 2, size), CFrame.new(0, -1.05, 0), MapKit.GRASS, Enum.Material.Grass)
		local water = MapKit.disc(folder, "Lake", 0.5, Landscape.LAKE_RADIUS * 2, Landscape.LAKE + Vector3.new(0, 0.1, 0), rgb(60, 140, 200), Enum.Material.Glass)
		water.Transparency = 0.2
	end

	-- the city's paved base: street level everywhere between the roads,
	-- sidewalks and buildings (a thick slab so nothing shows through)
	local cityW = EXTENT * 2 + 40
	part(folder, "CityGround", Vector3.new(cityW, 4, cityW), CFrame.new(0, -2, 0), rgb(88, 90, 96), Enum.Material.Asphalt)
	-- a curb-height grass verge around the edge of the city
	for _, e in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local size = if e[1] ~= 0 then Vector3.new(3, 0.6, cityW) else Vector3.new(cityW, 0.6, 3)
		deco(folder, "CityEdge", size, CFrame.new(e[1] * (cityW / 2 - 1.5), 0.3, e[2] * (cityW / 2 - 1.5)), MapKit.CURB, Enum.Material.Concrete)
	end

	-- a wooden pier into the lake, with spots for fishing
	local L = Landscape.LAKE
	local dir = (Vector3.new(0, 0, 0) - L).Unit
	local shore = L + dir * (Landscape.LAKE_RADIUS + 4)
	local pierCf = CFrame.lookAt(shore, L)
	for n = 0, 9 do
		part(folder, "PierPlank", Vector3.new(8, 0.5, 4), pierCf * CFrame.new(0, 0.6, -n * 4), MapKit.WOOD, Enum.Material.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			deco(folder, "PierPost", Vector3.new(0.6, 6, 0.6), pierCf * CFrame.new(sx * 3.8, -1.8, -n * 4), MapKit.DARK_WOOD, Enum.Material.Wood)
		end
	end
	for n = 1, 4 do
		local cf = pierCf * CFrame.new((n % 2 == 0) and 3 or -3, 0.85, -12 - n * 6) * CFrame.Angles(0, if n % 2 == 0 then math.rad(-90) else math.rad(90), 0)
		table.insert(fishingSpots, cf)
	end
	-- a rowing boat, a sign and some reeds
	local boat = pierCf * CFrame.new(10, 0.2, -22)
	deco(folder, "Boat", Vector3.new(4, 1.4, 9), boat, rgb(170, 90, 60), Enum.Material.WoodPlanks)
	deco(folder, "BoatSeat", Vector3.new(4, 0.3, 1.2), boat * CFrame.new(0, 0.6, 0), rgb(200, 150, 100), Enum.Material.Wood)
	local sign = deco(folder, "LakeSign", Vector3.new(10, 3.4, 0.4), pierCf * CFrame.new(-8, 4, 6), rgb(40, 90, 70), Enum.Material.Wood)
	MapKit.signText(sign, Enum.NormalId.Back, "MIRROR LAKE", MapKit.WHITE)
	MapKit.signText(sign, Enum.NormalId.Front, "MIRROR LAKE", MapKit.WHITE)
	for n = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local p = L + Vector3.new(math.cos(a), 0, math.sin(a)) * (Landscape.LAKE_RADIUS + rng:NextNumber(-2, 6))
		deco(folder, "Reed", Vector3.new(0.3, rng:NextNumber(2.5, 4.5), 0.3), CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), rgb(90, 130, 60), Enum.Material.Grass)
	end

	-- a forest ring of pines and leafy trees between the city and the hills
	for n = 1, 170 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = EXTENT + rng:NextNumber(40, 360)
		local p = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if (p - L).Magnitude > Landscape.LAKE_RADIUS + 26 and math.abs(p.X - 50) > 20 then
			if rng:NextNumber() < 0.6 then
				Streets.pine(folder, p, rng:NextNumber(1, 1.9))
			else
				Streets.tree(folder, p, rng:NextNumber(1, 1.6), rng)
			end
		end
	end

	-- a welcome sign where 5th Avenue leaves the city to the south
	local signCf = CFrame.lookAt(Vector3.new(50, 10, EXTENT + 24), Vector3.new(50, 10, 0))
	local welcome = part(folder, "WelcomeSign", Vector3.new(34, 9, 1.2), signCf, rgb(36, 84, 66), Enum.Material.Wood)
	MapKit.signText(welcome, Enum.NormalId.Front, "WELCOME TO AI CITY", MapKit.WHITE)
	MapKit.signText(welcome, Enum.NormalId.Back, "AI CITY - COME BACK SOON", MapKit.WHITE)
	for _, sx in ipairs({ -1, 1 }) do
		deco(folder, "SignPost", Vector3.new(1.2, 10, 1.2), signCf * CFrame.new(sx * 15, -8, 0.6), MapKit.DARK_WOOD, Enum.Material.Wood)
		for k = 0, 2 do
			MapKit.ball(folder, "Flower", 1.4, signCf * CFrame.new(sx * 12 + k * 1.6 - 1.6, -9.3, -1.6), MapKit.FLOWERS[(k + (sx + 1)) % #MapKit.FLOWERS + 1])
		end
	end
	return { FishingSpots = fishingSpots, Terrain = useTerrain }
end

return Landscape
