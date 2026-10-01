-- Landscape (ModuleScript) — ServerScriptService.Modules.Landscape
-- The land around the city: terrain grass (with swaying grass blades),
-- rolling hills with pine forests, a lake with a sandy beach and a wooden
-- pier for fishing, and snowy mountains on the horizon.

local MapKit = require(script.Parent:WaitForChild("MapKit"))
local Streets = require(script.Parent:WaitForChild("Streets"))
local Prison = require(script.Parent:WaitForChild("Prison"))
local NorthShore = require(script.Parent:WaitForChild("NorthShore"))

local Landscape = {}

local deco, part, rgb = MapKit.deco, MapKit.part, MapKit.rgb
local EXTENT = MapKit.EXTENT

-- keep the hills and the woods off the prison and Prison Road
-- would a hill or mountain of this size (a terrain ball: center p, radius R)
-- reach anything people walk or drive on? (the city, the whole North Shore and
-- its ocean, the prison and Prison Road). Terrain carving under roads only
-- goes a few studs up, so anything taller would hang over the road.
local function inTheWay(p, R)
	local reach = if math.abs(p.Y) < R then math.sqrt(R * R - p.Y * p.Y) else 0
	reach += 40
	local function rect(x0, z0, x1, z1)
		local dx = math.max(x0 - p.X, 0, p.X - x1)
		local dz = math.max(z0 - p.Z, 0, p.Z - z1)
		return dx * dx + dz * dz < reach * reach
	end
	if rect(-EXTENT - 30, -EXTENT - 30, EXTENT + 30, EXTENT + 30) then
		return true
	end
	if rect(NorthShore.WEST - 1300, NorthShore.WATER_Z - 950, NorthShore.EAST + 1300, -EXTENT) then
		return true -- (the shore, and the ocean all the way along)
	end
	local c = Prison.CENTER
	if (Vector3.new(p.X, 0, p.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude < Prison.RADIUS + reach then
		return true
	end
	return rect(EXTENT, c.Z - 12, c.X, c.Z + 12)
end

local function nearPrison(p, margin)
	-- (and off the North Shore: Funland, the beach and the ocean)
	if p.X > NorthShore.WEST - margin and p.X < NorthShore.EAST + margin and p.Z < -EXTENT + margin * 0.3 then
		return true
	end
	local c = Prison.CENTER
	if (Vector3.new(p.X, 0, p.Z) - c).Magnitude < Prison.RADIUS + margin then
		return true
	end
	return p.X < c.X and p.X > EXTENT - 40 and math.abs(p.Z - c.Z) < 20 + margin * 0.2
end

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
	-- the creek's course (from the hills down into the lake): planned first,
	-- so no hill or mountain gets piled on top of it
	local creek = {}
	do
		local Lk = Landscape.LAKE
		local from = Lk + Vector3.new(-520, 0, 420)
		for k = 0, 80 do
			local u = k / 80
			table.insert(creek, from:Lerp(Lk, u) + Vector3.new(math.sin(u * 9) * 26, 0, math.cos(u * 7) * 18))
		end
	end
	local function overCreek(p, R)
		local reach = (if math.abs(p.Y) < R then math.sqrt(R * R - p.Y * p.Y) else 0) + 18
		for _, c in ipairs(creek) do
			if (Vector3.new(p.X, 0, p.Z) - c).Magnitude < reach then
				return true
			end
		end
		return false
	end
	local function carveCreek(nearLakeOnly)
		for _, p in ipairs(creek) do
			local d = (Vector3.new(p.X, 0, p.Z) - Landscape.LAKE).Magnitude
			local ok = if nearLakeOnly then d < Landscape.LAKE_RADIUS + 24 and d > Landscape.LAKE_RADIUS - 6 else d > Landscape.LAKE_RADIUS - 4
			if ok and not inTheWay(Vector3.new(p.X, 0, p.Z), 8) then
				if not nearLakeOnly then
					terrain:FillCylinder(CFrame.new(p.X, -1.5, p.Z), 5, 7, Enum.Material.Air)
					terrain:FillCylinder(CFrame.new(p.X, -5.5, p.Z), 2, 7, Enum.Material.Mud)
					terrain:FillCylinder(CFrame.new(p.X, -1.2, p.Z), 1.6, 9.5, Enum.Material.Ground)
				end
				terrain:FillCylinder(CFrame.new(p.X, -1.5, p.Z), 5, 6, Enum.Material.Air)
				terrain:FillCylinder(CFrame.new(p.X, -3.5, p.Z), 2.4, 5.5, Enum.Material.Water)
			end
		end
	end
	if useTerrain then
		-- a big flat grass plain; the city sits on top of it
		terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(size, 12, size), Enum.Material.Grass)
		-- rolling hills outside the city
		for n = 1, 28 do
			local a = n / 28 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local r = EXTENT + rng:NextNumber(140, 420)
			local p = Vector3.new(math.cos(a) * r, -rng:NextNumber(20, 34), math.sin(a) * r)
			local R = rng:NextNumber(45, 80)
			if (p - Landscape.LAKE).Magnitude > Landscape.LAKE_RADIUS + 90 and not nearPrison(p, 90) and not inTheWay(p, R) and not overCreek(p, R) then
				terrain:FillBall(p, R, Enum.Material.Grass)
			end
		end
		-- mountains on the horizon
		for n = 1, 12 do
			local a = n / 12 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
			local r = EXTENT + rng:NextNumber(700, 820)
			local height = rng:NextNumber(150, 230)
			local p = Vector3.new(math.cos(a) * r, -height * 0.35, math.sin(a) * r)
			if inTheWay(p, height) or overCreek(p, height) then
				continue -- (never over a road, the shore, the ocean or the creek)
			end
			terrain:FillBall(p, height, Enum.Material.Rock)
			terrain:FillBall(p + Vector3.new(0, height * 0.72, 0), height * 0.38, Enum.Material.Snow)
		end
		-- 🎨 a natural palette for every terrain material
		pcall(function()
			terrain:SetMaterialColor(Enum.Material.Grass, rgb(96, 150, 66))
			terrain:SetMaterialColor(Enum.Material.LeafyGrass, rgb(72, 128, 52))
			terrain:SetMaterialColor(Enum.Material.Ground, rgb(122, 98, 72))
			terrain:SetMaterialColor(Enum.Material.Mud, rgb(84, 70, 56))
			terrain:SetMaterialColor(Enum.Material.Rock, rgb(118, 116, 110))
			terrain:SetMaterialColor(Enum.Material.Slate, rgb(92, 94, 98))
			terrain:SetMaterialColor(Enum.Material.Basalt, rgb(70, 68, 70))
			terrain:SetMaterialColor(Enum.Material.Sand, rgb(226, 206, 156))
			terrain:SetMaterialColor(Enum.Material.Snow, rgb(244, 246, 250))
			terrain:SetMaterialColor(Enum.Material.Glacier, rgb(196, 222, 238))
			terrain:SetMaterialColor(Enum.Material.Limestone, rgb(196, 188, 168))
		end)
		local far = EXTENT + 60
		local function outside(p, margin)
			return not inTheWay(Vector3.new(p.X, 0, p.Z), margin or 6) and (Vector3.new(p.X, 0, p.Z) - Landscape.LAKE).Magnitude > Landscape.LAKE_RADIUS + 20
		end
		-- the plain isn't one flat green: lush patches, worn dirt, gravel
		for n = 1, 140 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = far + rng:NextNumber(0, 820)
			local p = Vector3.new(math.cos(a) * r, -1, math.sin(a) * r)
			if outside(p, 30) then
				local roll = rng:NextNumber()
				local mat = if roll < 0.55 then Enum.Material.LeafyGrass elseif roll < 0.8 then Enum.Material.Ground elseif roll < 0.92 then Enum.Material.Mud else Enum.Material.Limestone
				terrain:FillCylinder(CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), 2.2, rng:NextNumber(8, 26), mat)
			end
		end
		-- dirt trails winding out from the edge of town into the hills
		for t = 1, 5 do
			local a0 = t / 5 * math.pi * 2 + 0.4
			local wobble = rng:NextNumber(0.8, 1.6)
			for k = 0, 60 do
				local r = far + 10 + k * 9
				local a = a0 + math.sin(k / 7 * wobble) * 0.08
				local p = Vector3.new(math.cos(a) * r, -1, math.sin(a) * r)
				if outside(p, 4) then
					terrain:FillCylinder(CFrame.new(p), 2.2, 3.6, Enum.Material.Ground)
				end
			end
		end
		-- the hills: lumpy (a few overlapping mounds), lush on top, with rock
		-- showing through on the slopes
		for n = 1, 22 do
			local a = n / 22 * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
			local r = EXTENT + rng:NextNumber(260, 560)
			local p = Vector3.new(math.cos(a) * r, -rng:NextNumber(18, 30), math.sin(a) * r)
			local R = rng:NextNumber(40, 70)
			if not inTheWay(p, R + 30) and not overCreek(p, R) and (p - Landscape.LAKE).Magnitude > Landscape.LAKE_RADIUS + R + 40 then
				terrain:FillBall(p, R, Enum.Material.Grass)
				for k = 1, 3 do
					local off = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * R * 0.6
					terrain:FillBall(p + off + Vector3.new(0, -R * 0.15, 0), R * rng:NextNumber(0.5, 0.75), if k == 1 then Enum.Material.LeafyGrass else Enum.Material.Grass)
				end
				for k = 1, 4 do
					local ang = rng:NextNumber(0, math.pi * 2)
					local q = p + Vector3.new(math.cos(ang) * R * 0.7, R * 0.45 + p.Y * 0.2, math.sin(ang) * R * 0.7)
					terrain:FillBall(q, rng:NextNumber(4, 9), if k % 2 == 0 then Enum.Material.Rock else Enum.Material.Slate)
				end
			end
		end
		-- mountains: foothills and scree at the base, rock strata, glacier
		-- ice under the snow
		for n = 1, 12 do
			local a = n / 12 * math.pi * 2 + 0.26
			local r = EXTENT + rng:NextNumber(720, 860)
			local h = rng:NextNumber(110, 170)
			local p = Vector3.new(math.cos(a) * r, -h * 0.4, math.sin(a) * r)
			if not inTheWay(p, h + 40) and not overCreek(p, h * 1.4) then
				terrain:FillBall(p, h, Enum.Material.Rock)
				terrain:FillBall(p + Vector3.new(h * 0.3, h * 0.25, -h * 0.2), h * 0.55, Enum.Material.Slate)
				terrain:FillBall(p + Vector3.new(-h * 0.35, h * 0.1, h * 0.25), h * 0.6, Enum.Material.Basalt)
				terrain:FillBall(p + Vector3.new(0, h * 0.62, 0), h * 0.42, Enum.Material.Glacier)
				terrain:FillBall(p + Vector3.new(0, h * 0.7, 0), h * 0.38, Enum.Material.Snow)
				for k = 1, 6 do
					local ang = rng:NextNumber(0, math.pi * 2)
					local foot = p + Vector3.new(math.cos(ang) * h * 0.95, h * 0.25, math.sin(ang) * h * 0.95)
					terrain:FillBall(foot, rng:NextNumber(18, 34), if k % 3 == 0 then Enum.Material.Ground else Enum.Material.Grass)
					terrain:FillBall(foot + Vector3.new(0, 6, 0), rng:NextNumber(5, 10), Enum.Material.Rock)
				end
			end
		end
		-- a creek running down to the lake: a shallow channel, a muddy bed
		carveCreek(false)
		-- the lake: sand shore, then water
		local L = Landscape.LAKE
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -3, 0)), 6, Landscape.LAKE_RADIUS + 16, Enum.Material.Sand)
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -2.5, 0)), 5, Landscape.LAKE_RADIUS + 5, Enum.Material.Mud)
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -5, 0)), 10, Landscape.LAKE_RADIUS, Enum.Material.Air)
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -6, 0)), 10, Landscape.LAKE_RADIUS, Enum.Material.Water)
		terrain:FillCylinder(CFrame.new(L + Vector3.new(0, -12, 0)), 4, Landscape.LAKE_RADIUS, Enum.Material.Sand)
		carveCreek(true) -- (the creek runs right into the lake)
		-- no terrain grass under the city: it would grow up through the roads,
		-- sidewalks and floors. The city stands on its own paved base (below).
		local cityW = EXTENT * 2 + 40
		terrain:FillBlock(CFrame.new(0, -4, 0), Vector3.new(cityW, 16, cityW), Enum.Material.Air)
		terrain:FillBlock(CFrame.new(0, -12, 0), Vector3.new(cityW, 8, cityW), Enum.Material.Asphalt)
		-- the North Shore: a sandy beach, then the ocean; no grass under the
		-- paved parts (see NorthShore)
		local wz = NorthShore.WATER_Z
		local beachZ = NorthShore.BOARDWALK_Z - 10
		local oceanW, oceanD = 2400, 900
		terrain:FillBlock(CFrame.new(-65, -3, (beachZ + wz) / 2), Vector3.new(oceanW, 6, beachZ - wz), Enum.Material.Sand)
		terrain:FillBlock(CFrame.new(-65, -6, wz - oceanD / 2), Vector3.new(oceanW, 14, oceanD), Enum.Material.Air)
		terrain:FillBlock(CFrame.new(-65, -9, wz - oceanD / 2), Vector3.new(oceanW, 16, oceanD), Enum.Material.Water)
		terrain:FillBlock(CFrame.new(-65, -19, wz - oceanD / 2), Vector3.new(oceanW, 4, oceanD), Enum.Material.Sand)
		for _, area in ipairs(NorthShore.PAVED) do
			terrain:FillBlock(CFrame.new(area.Center + Vector3.new(0, -4, 0)), Vector3.new(area.Size.X, 8, area.Size.Z), Enum.Material.Air)
			terrain:FillBlock(CFrame.new(area.Center + Vector3.new(0, -10, 0)), Vector3.new(area.Size.X, 4, area.Size.Z), Enum.Material.Ground)
		end
		-- the same under the prison and Prison Road (see Prison)
		local pc = Prison.F * CFrame.new(0, 0, -12)
		local pSize = Vector3.new(Prison.W + 24, 16, Prison.D + 48)
		terrain:FillBlock(pc * CFrame.new(0, -4, 0), pSize, Enum.Material.Air)
		terrain:FillBlock(pc * CFrame.new(0, -12, 0), Vector3.new(pSize.X, 8, pSize.Z), Enum.Material.Asphalt)
		local roadFrom, roadTo = EXTENT, Prison.CENTER.X - Prison.D / 2
		local roadMid = Vector3.new((roadFrom + roadTo) / 2, 0, Prison.CENTER.Z)
		terrain:FillBlock(CFrame.new(roadMid + Vector3.new(0, -4, 0)), Vector3.new(roadTo - roadFrom + 8, 16, 20), Enum.Material.Air)
		terrain:FillBlock(CFrame.new(roadMid + Vector3.new(0, -12, 0)), Vector3.new(roadTo - roadFrom + 8, 8, 20), Enum.Material.Asphalt)
		-- swaying grass on the hills around the city (the city itself has no
		-- terrain under it, so no blades come up through floors or roads),
		-- and clear, reflective water with gentle waves
		pcall(function()
			terrain.Decoration = true
			-- clear enough to see the fish, the weeds and the rocks below
			terrain.WaterColor = rgb(32, 112, 140)
			terrain.WaterReflectance = 0.6
			terrain.WaterTransparency = 0.72
			terrain.WaterWaveSize = 0.18
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
	-- sitting in the water (the surface is at y = -1), not hovering over it
	local boat = pierCf * CFrame.new(10, if useTerrain then -0.75 else 0.2, -22)
	deco(folder, "Boat", Vector3.new(4, 1.4, 9), boat, rgb(170, 90, 60), Enum.Material.WoodPlanks)
	deco(folder, "BoatSeat", Vector3.new(4, 0.3, 1.2), boat * CFrame.new(0, 0.6, 0), rgb(200, 150, 100), Enum.Material.Wood)
	local sign = deco(folder, "LakeSign", Vector3.new(10, 3.4, 0.4), pierCf * CFrame.new(-8, 4, 6), rgb(40, 90, 70), Enum.Material.Wood)
	MapKit.signText(sign, Enum.NormalId.Back, "MIRROR LAKE", MapKit.WHITE)
	MapKit.signText(sign, Enum.NormalId.Front, "MIRROR LAKE", MapKit.WHITE)
	for n = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local p = L + Vector3.new(math.cos(a), 0, math.sin(a)) * (Landscape.LAKE_RADIUS + rng:NextNumber(-2, 6))
		deco(folder, "Reed", Vector3.new(0.3, rng:NextNumber(2.5, 4.5), 0.3), CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), rgb(90, 130, 60), Enum.Material.SmoothPlastic)
	end

	-- under the water: sand ripples, rocks, swaying weeds; lily pads on top.
	-- A "Water" part marks the lake for fishing and for the fish that swim in
	-- it (see FishingService and the client's Water module)
	local surface = if useTerrain then -1 else 0.35
	local bed = if useTerrain then -10 else -0.5
	local lakeInfo = deco(folder, "LakeWater", Vector3.new(2, 0.2, 2), CFrame.new(L.X, surface, L.Z), rgb(60, 140, 200))
	lakeInfo.Transparency = 1
	lakeInfo:SetAttribute("Radius", Landscape.LAKE_RADIUS)
	lakeInfo:SetAttribute("Surface", surface)
	lakeInfo:SetAttribute("Depth", surface - bed)
	lakeInfo:SetAttribute("Kind", "lake")
	lakeInfo:SetAttribute("Fish", 36)
	lakeInfo:SetAttribute("RodStand", (pierCf * CFrame.new(-5.5, -0.2, 3)).Position)
	MapKit.tag(lakeInfo, "Water")
	for n = 1, 70 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * (Landscape.LAKE_RADIUS - 6)
		local p = L + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if n % 3 == 0 then
			MapKit.ball(folder, "LakeRock", rng:NextNumber(1.5, 4), CFrame.new(p.X, bed + 0.5, p.Z), rgb(110, 110, 104):Lerp(rgb(80, 90, 70), rng:NextNumber()), Enum.Material.Rock)
		else
			local h = rng:NextNumber(2, math.max(2.2, math.min(6, surface - bed - 1)))
			for k = 0, 2 do
				deco(folder, "Seaweed", Vector3.new(0.35, h * (1 - k * 0.2), 0.12), CFrame.new(p.X + k * 0.4 - 0.4, bed + h * (1 - k * 0.2) / 2, p.Z) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 3), rng:NextNumber(-0.25, 0.25)), rgb(50, 120, 60):Lerp(rgb(90, 150, 60), rng:NextNumber()), Enum.Material.SmoothPlastic)
			end
		end
	end
	for n = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local p = L + Vector3.new(math.cos(a), 0, math.sin(a)) * (Landscape.LAKE_RADIUS - rng:NextNumber(4, 22))
		MapKit.disc(folder, "LilyPad", 0.08, rng:NextNumber(1.6, 2.8), Vector3.new(p.X, surface + 0.05, p.Z), rgb(70, 150, 60), Enum.Material.SmoothPlastic)
		if n % 4 == 0 then
			MapKit.ball(folder, "LilyFlower", 0.6, CFrame.new(p.X, surface + 0.3, p.Z), rgb(250, 190, 220))
		end
	end

	-- where the ground actually is (on a hill, the trees stand on the slope,
	-- not buried in it); nil in a creek or the lake
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.IgnoreWater = true
	pcall(function()
		groundParams.FilterDescendantsInstances = { terrain }
	end)
	local function ground(x, z)
		if not useTerrain then
			return Vector3.new(x, 0, z)
		end
		local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), groundParams)
		if not hit then
			return Vector3.new(x, 0, z)
		end
		if hit.Material == Enum.Material.Mud or hit.Material == Enum.Material.Water or hit.Position.Y < -1.6 then
			return nil
		end
		return hit.Position
	end
	-- boulders on the plain and the slopes
	for n = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = EXTENT + rng:NextNumber(70, 700)
		local p = ground(math.cos(a) * r, math.sin(a) * r)
		if p and (p - L).Magnitude > Landscape.LAKE_RADIUS + 20 and not nearPrison(p, 20) then
			local sz = rng:NextNumber(2.5, 7)
			local rock = MapKit.ball(folder, "Boulder", sz, CFrame.new(p + Vector3.new(0, sz * 0.25, 0)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)), rgb(120, 118, 112):Lerp(rgb(90, 92, 96), rng:NextNumber()), Enum.Material.Slate)
			rock.Size = Vector3.new(sz, sz * rng:NextNumber(0.5, 0.8), sz * rng:NextNumber(0.7, 1))
			if rng:NextNumber() < 0.5 then
				-- a smaller one leaning on it
				MapKit.ball(folder, "Boulder", sz * 0.45, CFrame.new(p + Vector3.new(sz * 0.55, sz * 0.12, sz * 0.2)), rock.Color:Lerp(rgb(70, 70, 72), 0.2), Enum.Material.Slate)
			end
		end
	end
	-- wildflower meadows
	for n = 1, 28 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = EXTENT + rng:NextNumber(60, 500)
		local c = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if (c - L).Magnitude > Landscape.LAKE_RADIUS + 30 and not nearPrison(c, 20) and math.abs(c.X - 50) > 26 then
			local color = MapKit.FLOWERS[rng:NextInteger(1, #MapKit.FLOWERS)]
			for k = 1, 10 do
				local p = ground(c.X + rng:NextNumber(-9, 9), c.Z + rng:NextNumber(-9, 9))
				if p then
					MapKit.deco(folder, "Stem", Vector3.new(0.1, 1.1, 0.1), CFrame.new(p + Vector3.new(0, 0.55, 0)), rgb(70, 130, 50))
					MapKit.ball(folder, "Wildflower", 0.6, CFrame.new(p + Vector3.new(0, 1.15, 0)), if k % 4 == 0 then MapKit.FLOWERS[rng:NextInteger(1, #MapKit.FLOWERS)] else color).CanCollide = false
				end
			end
		end
	end
	-- reeds and cattails at the lake's edge
	for n = 1, 70 do
		local a = rng:NextNumber(0, math.pi * 2)
		if math.abs(((a - math.atan2(dir.Z, dir.X)) + math.pi) % (math.pi * 2) - math.pi) > 0.18 then -- (not on the pier)
			local r = Landscape.LAKE_RADIUS + rng:NextNumber(-3, 3)
			local base = L + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			for k = 0, 2 do
				local h = rng:NextNumber(2.5, 4.5)
				local tilt = CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15))
				local cf = CFrame.new(base + Vector3.new(rng:NextNumber(-0.8, 0.8), -1, rng:NextNumber(-0.8, 0.8))) * tilt
				MapKit.deco(folder, "Reed", Vector3.new(0.14, h, 0.14), cf * CFrame.new(0, h / 2, 0), rgb(110, 140, 70))
				if k == 0 then
					MapKit.deco(folder, "Cattail", Vector3.new(0.3, 0.9, 0.3), cf * CFrame.new(0, h - 0.2, 0), rgb(110, 70, 40))
				end
			end
		end
	end

	-- a forest ring of pines and leafy trees between the city and the hills
	for n = 1, 170 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = EXTENT + rng:NextNumber(40, 360)
		local p = ground(math.cos(a) * r, math.sin(a) * r)
		if p and (p - L).Magnitude > Landscape.LAKE_RADIUS + 26 and math.abs(p.X - 50) > 20 and not nearPrison(p, 12) then
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
