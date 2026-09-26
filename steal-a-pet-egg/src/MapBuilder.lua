-- MapBuilder (ModuleScript) — ServerScriptService.Modules.MapBuilder
-- Builds the whole world from code when the server starts:
--   * lighting (atmosphere, bloom, sun rays, color grading)
--   * terrain ground, hills around the edges, ponds, lakes, lava
--   * a town with 6 big player bases, street lamps, fountain and gates
--   * a road out through 5 biomes, each with a guarded nest, props and particles
-- Returns plot and biome data for GameService.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local MapBuilder = {}

local PLOT_SIZE = 84 -- base depth (front to back)
local PLOT_WIDTH = 140 -- base width (side to side)
local PLOT_SCALE = PLOT_SIZE / 60 -- base layouts are drawn on a 60-stud grid, then scaled
local PLOT_COUNT = 6 -- bases per server (fewer, bigger bases)
local PLOT_GAP = 36 -- room between bases
local PLOT_ROW_SPAN = PLOT_COUNT * PLOT_WIDTH + (PLOT_COUNT - 1) * PLOT_GAP -- all bases side by side
local TOWN_START_Z = -75
local TOWN_END_Z = 230
local BIOME_SPACING = 450 -- how long each zone is
local BIOME_START_Z = TOWN_END_Z + BIOME_SPACING / 2
local TOWN_HALF = PLOT_ROW_SPAN / 2 + 20 -- the town is as wide as the row of bases
local CORRIDOR_HALF = TOWN_HALF -- zones are as wide as the town
local TILE = 10 -- wall checker size
local FLOOR_TILE = 5 -- floor checker size (small squares, like Steal an Egg)
local ZONE_FLOOR_TILE = 12 -- bigger squares in the zones: far fewer parts, and easier to read at top speed
local WALL_HEIGHT = 40
local DOOR_HALF = 35
local DOOR_HEIGHT = 30

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local WARM_LIGHT = Color3.fromRGB(255, 205, 140)
local WOOD = Color3.fromRGB(150, 100, 60)
local DARK_WOOD = Color3.fromRGB(105, 70, 45)
local STONE = Color3.fromRGB(160, 160, 165)
local GOLD_COLOR = Color3.fromRGB(255, 205, 70)

local PLOT_ACCENTS = {
	Color3.fromRGB(255, 110, 110),
	Color3.fromRGB(110, 180, 255),
	Color3.fromRGB(120, 220, 130),
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(190, 130, 255),
	Color3.fromRGB(255, 150, 205),
	Color3.fromRGB(90, 220, 220),
	Color3.fromRGB(255, 155, 80),
}

local terrain = workspace.Terrain

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function part(props)
	local p = Instance.new("Part")
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Size then
		p.Size = props.Size
	end
	for key, value in pairs(props) do
		if key ~= "Parent" and key ~= "Shape" and key ~= "Size" then
			p[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

-- Decorations never block prompts or the camera.
local function deco(props)
	props.CanQuery = false
	props.CanTouch = false
	return part(props)
end

local function cylinderAlongY(cframe)
	return cframe * CFrame.Angles(0, 0, math.rad(90))
end

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

local function surfaceText(target, face, text, color, font)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color or WHITE
	label.TextStrokeTransparency = 0.3
	label.Text = text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = target
	return label
end

local function particles(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	for key, value in pairs(props) do
		e[key] = value
	end
	e.Parent = parent
	return e
end

local function lantern(parent, position, color, range)
	local bulb = deco({ Name = "Lantern", Shape = Enum.PartType.Ball, Size = Vector3.one * 1, Position = position, Color = color, Material = Enum.Material.Neon, CastShadow = false, Parent = parent })
	light(bulb, color, range or 16, 1.3)
	return bulb
end

--------------------------------------------------------------------------------
-- Lighting
--------------------------------------------------------------------------------
local function setupLighting()
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds") then
			child:Destroy()
		end
	end
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	-- Warm mid-afternoon sun, softer than before so nothing looks blown out
	Lighting.ClockTime = 15
	Lighting.GeographicLatitude = 38
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(58, 62, 74)
	Lighting.OutdoorAmbient = Color3.fromRGB(126, 132, 148)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 240, 215)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.9
	Lighting.ShadowSoftness = 0.2
	Lighting.ExposureCompensation = -0.15
	Lighting.GlobalShadows = true

	-- Thin atmosphere with little haze keeps the sky a deep, clear blue
	local mood = Config.TownMood
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "MoodAtmosphere"
	atmosphere.Density = mood.Density
	atmosphere.Offset = 0.1
	atmosphere.Color = mood.Color
	atmosphere.Decay = mood.Decay
	atmosphere.Glare = mood.Glare or 0.2
	atmosphere.Haze = mood.Haze
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 14
	sky.StarCount = 5000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	-- Bloom only catches truly bright things (neon, lanterns), not every surface
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "MoodBloom"
	bloom.Intensity = 0.4
	bloom.Size = 22
	bloom.Threshold = 2
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "MoodRays"
	rays.Intensity = 0.035
	rays.Spread = 0.6
	rays.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MoodCC"
	cc.Brightness = mood.Brightness
	cc.Contrast = 0.1
	cc.Saturation = mood.Saturation
	cc.TintColor = mood.Tint
	cc.Parent = Lighting

	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.05
	dof.FocusDistance = 80
	dof.InFocusRadius = 140
	dof.NearIntensity = 0
	dof.Parent = Lighting

	-- Big fluffy clouds; each zone tints them (see Config moods)
	local clouds = Instance.new("Clouds")
	clouds.Name = "MoodClouds"
	clouds.Cover = mood.CloudCover or 0.6
	clouds.Density = 0.62
	clouds.Color = mood.CloudColor or Color3.new(1, 1, 1)
	clouds.Parent = terrain

	pcall(function()
		terrain.Decoration = true -- animated grass blades
	end)
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(104, 168, 72))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(78, 140, 58))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(62, 50, 92))
	terrain:SetMaterialColor(Enum.Material.Pavement, Color3.fromRGB(150, 145, 140))
	terrain.WaterColor = Color3.fromRGB(40, 140, 170)
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.08
end

--------------------------------------------------------------------------------
-- Checkerboard floors and walls (the Steal an Egg look)
--------------------------------------------------------------------------------
-- A floor whose top sits at y = 0: one solid base plus every other tile in the
-- second color. `skip(x, z)` can leave out tiles hidden under bases.
local function checkerFloor(folder, xMin, xMax, zMin, zMax, colors, skip, tile)
	tile = tile or FLOOR_TILE
	part({ Name = "Floor", Size = Vector3.new(xMax - xMin, 2, zMax - zMin), Position = Vector3.new((xMin + xMax) / 2, -1, (zMin + zMax) / 2), Color = colors[1], Material = Enum.Material.SmoothPlastic, Parent = folder })
	local ix = 0
	for x = xMin, xMax - tile, tile do
		local iz = 0
		for z = zMin, zMax - tile, tile do
			local cx, cz = x + tile / 2, z + tile / 2
			if (ix + iz) % 2 == 1 and not (skip and skip(cx, cz)) then
				deco({ Name = "Tile", Size = Vector3.new(tile, 0.2, tile), Position = Vector3.new(cx, -0.05, cz), Color = colors[2], Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
			end
			iz += 1
		end
		ix += 1
	end
end

-- A checkered wall panel. `cf` is the panel center; its front (local -Z) faces
-- the player. Set bothSides to tile the back as well.
local function checkerPanel(folder, cf, width, height, colors, bothSides)
	local thickness = 4
	part({ Name = "Wall", Size = Vector3.new(width, height, thickness), CFrame = cf, Color = colors[1], Material = Enum.Material.SmoothPlastic, Parent = folder })
	local cols = math.floor(width / TILE + 0.001)
	local rows = math.floor(height / TILE + 0.001)
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			if (i + j) % 2 == 1 then
				local x = -width / 2 + TILE * (i + 0.5)
				local y = -height / 2 + TILE * (j + 0.5)
				deco({ Name = "WallTile", Size = Vector3.new(TILE, TILE, 0.2), CFrame = cf * CFrame.new(x, y, -thickness / 2 - 0.05), Color = colors[2], Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
				if bothSides then
					deco({ Name = "WallTile", Size = Vector3.new(TILE, TILE, 0.2), CFrame = cf * CFrame.new(x, y, thickness / 2 + 0.05), Color = colors[2], Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
				end
			end
		end
	end
	-- a darker cap along the top
	deco({ Name = "WallCap", Size = Vector3.new(width, 1, thickness + 1), CFrame = cf * CFrame.new(0, height / 2 + 0.5, 0), Color = colors[1]:Lerp(BLACK, 0.25), Material = Enum.Material.SmoothPlastic, Parent = folder })
end

-- Two side walls facing inward, running from zMin to zMax at x = +-half.
local function sideWalls(folder, half, zMin, zMax, colors)
	local mid = (zMin + zMax) / 2
	for _, side in ipairs({ -1, 1 }) do
		local center = Vector3.new(side * (half + 2), WALL_HEIGHT / 2, mid)
		checkerPanel(folder, CFrame.lookAt(center, Vector3.new(0, WALL_HEIGHT / 2, mid)), zMax - zMin, WALL_HEIGHT, colors)
	end
end

-- A full-width wall across the corridor at z, tiled on the side facing -Z.
local function endWall(folder, half, z, colors, facing)
	local center = Vector3.new(0, WALL_HEIGHT / 2, z)
	checkerPanel(folder, CFrame.lookAt(center, center + Vector3.new(0, 0, facing)), half * 2 + 8, WALL_HEIGHT, colors)
end

--------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------
local PROPS = {}

local LEAF_GREENS = { Color3.fromRGB(76, 160, 60), Color3.fromRGB(64, 142, 52), Color3.fromRGB(92, 176, 70), Color3.fromRGB(58, 128, 48) }

local function leafCube(folder, position, size, rng)
	deco({ Name = "Leaves", Size = Vector3.one * size, Position = position, Color = LEAF_GREENS[rng:NextInteger(1, #LEAF_GREENS)], Material = Enum.Material.SmoothPlastic, Parent = folder })
end

-- Blocky voxel tree: square trunk and a canopy of leaf cubes, some with fruit.
function PROPS.Tree(folder, pos, s, rng)
	local c = 4 * s -- cube size
	local trunkH = 9 * s
	deco({ Name = "Trunk", Size = Vector3.new(2.4 * s, trunkH, 2.4 * s), Position = pos + Vector3.new(0, trunkH / 2, 0), Color = Color3.fromRGB(125, 85, 52), Material = Enum.Material.SmoothPlastic, Parent = folder })
	local base = pos + Vector3.new(0, trunkH + c / 2 - 0.5 * s, 0)
	for layer = 0, 2 do
		local r = if layer == 2 then 0 else 1
		for ix = -r, r do
			for iz = -r, r do
				local corner = math.abs(ix) == 1 and math.abs(iz) == 1
				if not (corner and layer == 1 and rng:NextNumber() < 0.6) then
					leafCube(folder, base + Vector3.new(ix * c, layer * c, iz * c), c, rng)
				end
			end
		end
	end
	-- a few fruits / blossoms poking out
	if rng:NextNumber() < 0.5 then
		local fruit = if rng:NextNumber() < 0.5 then Color3.fromRGB(230, 50, 50) else Color3.fromRGB(255, 190, 220)
		for _ = 1, 3 do
			local side = rng:NextInteger(1, 4)
			local dir = ({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis })[side]
			deco({ Name = "Fruit", Size = Vector3.one * 0.9 * s, Position = base + dir * (c * 1.5 + 0.2) + Vector3.new(rng:NextNumber(-1, 1) * s, rng:NextNumber(-1, 1) * s, 0), Color = fruit, Material = Enum.Material.SmoothPlastic, Parent = folder })
		end
	end
end

function PROPS.TallTree(folder, pos, s, rng)
	local c = 3.5 * s
	local trunkH = 15 * s
	deco({ Name = "Trunk", Size = Vector3.new(2.2 * s, trunkH, 2.2 * s), Position = pos + Vector3.new(0, trunkH / 2, 0), Color = Color3.fromRGB(105, 72, 45), Material = Enum.Material.SmoothPlastic, Parent = folder })
	local base = pos + Vector3.new(0, trunkH - c, 0)
	for layer = 0, 3 do
		local r = if layer >= 2 then 0 else 1
		for ix = -r, r do
			for iz = -r, r do
				if r == 0 or (ix == 0 or iz == 0) or layer == 0 then
					leafCube(folder, base + Vector3.new(ix * c, layer * c, iz * c), c, rng)
				end
			end
		end
	end
end

function PROPS.Bush(folder, pos, s, rng)
	local c = 2.2 * s
	for _ = 1, 4 do
		leafCube(folder, pos + Vector3.new(rng:NextInteger(-1, 1) * c * 0.7, c / 2 + rng:NextInteger(0, 1) * c * 0.6, rng:NextInteger(-1, 1) * c * 0.7), c, rng)
	end
	local flower = ({ Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 230, 90), WHITE, Color3.fromRGB(180, 140, 255) })[rng:NextInteger(1, 4)]
	for _ = 1, 3 do
		deco({ Name = "Flower", Size = Vector3.one * 0.7 * s, Position = pos + Vector3.new(rng:NextNumber(-1.5, 1.5) * s, c * 1.6, rng:NextNumber(-1.5, 1.5) * s), Color = flower, Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
end

function PROPS.Mushroom(folder, pos, s)
	deco({ Name = "Stem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3 * s, 1.2 * s, 1.2 * s), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, 1.5 * s, 0))), Color = Color3.fromRGB(240, 230, 210), Material = Enum.Material.SmoothPlastic, Parent = folder })
	local cap = deco({ Name = "Cap", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 2.4, 4) * s, Position = pos + Vector3.new(0, 3.2 * s, 0), Color = Color3.fromRGB(215, 50, 50), Material = Enum.Material.SmoothPlastic, Parent = folder })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = cap
	for i = 1, 4 do
		local a = i * math.pi / 2
		deco({ Name = "Dot", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6 * s, Position = pos + Vector3.new(math.cos(a) * 1.2 * s, 4 * s, math.sin(a) * 1.2 * s), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
end

local function rock(folder, pos, s, rng, color, material)
	local size = Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(2.5, 4.5), rng:NextNumber(4, 6)) * s
	return deco({
		Name = "Rock",
		Size = size,
		CFrame = CFrame.new(pos + Vector3.new(0, size.Y * 0.35, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
		Color = color,
		Material = material,
		Parent = folder,
	})
end

function PROPS.Rock(folder, pos, s, rng)
	rock(folder, pos, s, rng, Color3.fromRGB(130, 130, 125), Enum.Material.Slate)
end

function PROPS.Log(folder, pos, s, rng)
	deco({ Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 1.8, 1.8) * s, CFrame = CFrame.new(pos + Vector3.new(0, 0.9 * s, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
end

function PROPS.Cactus(folder, pos, s, rng)
	local green = Color3.fromRGB(70, 150, 75)
	deco({ Name = "Cactus", Size = Vector3.new(2.4, 10, 2.4) * s, Position = pos + Vector3.new(0, 5 * s, 0), Color = green, Material = Enum.Material.Grass, Parent = folder })
	deco({ Name = "Top", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.4 * s, Position = pos + Vector3.new(0, 10 * s, 0), Color = green, Material = Enum.Material.Grass, Parent = folder })
	for _, side in ipairs({ -1, 1 }) do
		local h = rng:NextNumber(4, 6.5) * s
		deco({ Name = "Arm", Size = Vector3.new(2.5, 1.6, 1.6) * s, Position = pos + Vector3.new(side * 2 * s, h, 0), Color = green, Material = Enum.Material.Grass, Parent = folder })
		deco({ Name = "ArmUp", Size = Vector3.new(1.6, 3, 1.6) * s, Position = pos + Vector3.new(side * 3 * s, h + 1.3 * s, 0), Color = green, Material = Enum.Material.Grass, Parent = folder })
	end
	deco({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9 * s, Position = pos + Vector3.new(0, 11.2 * s, 0), Color = Color3.fromRGB(255, 110, 170), Material = Enum.Material.SmoothPlastic, Parent = folder })
end

function PROPS.DeadBush(folder, pos, s, rng)
	for _ = 1, 5 do
		deco({ Name = "Twig", Size = Vector3.new(0.3, 3.5, 0.3) * s, CFrame = CFrame.new(pos + Vector3.new(0, 1.4 * s, 0)) * CFrame.Angles(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0, 6), rng:NextNumber(-0.7, 0.7)), Color = Color3.fromRGB(140, 105, 70), Material = Enum.Material.Wood, Parent = folder })
	end
end

function PROPS.Sandstone(folder, pos, s, rng)
	rock(folder, pos, s * 1.3, rng, Color3.fromRGB(210, 170, 115), Enum.Material.Sandstone)
end

function PROPS.Pillar(folder, pos, s, rng)
	local h = rng:NextNumber(5, 11) * s
	deco({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 3, 3), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, h / 2, 0))), Color = Color3.fromRGB(225, 200, 150), Material = Enum.Material.Sandstone, Parent = folder })
	deco({ Name = "Base", Size = Vector3.new(4.5, 1, 4.5), Position = pos + Vector3.new(0, 0.5, 0), Color = Color3.fromRGB(205, 180, 130), Material = Enum.Material.Sandstone, Parent = folder })
	deco({ Name = "Chunk", Size = Vector3.new(3, 2.5, 3), CFrame = CFrame.new(pos + Vector3.new(3.5, 1, 1)) * CFrame.Angles(0.4, 0.8, 0.2), Color = Color3.fromRGB(225, 200, 150), Material = Enum.Material.Sandstone, Parent = folder })
end

function PROPS.Skull(folder, pos, s)
	local bone = Color3.fromRGB(240, 232, 210)
	deco({ Name = "Skull", Shape = Enum.PartType.Ball, Size = Vector3.one * 3 * s, Position = pos + Vector3.new(0, 1.2 * s, 0), Color = bone, Material = Enum.Material.SmoothPlastic, Parent = folder })
	for _, side in ipairs({ -1, 1 }) do
		deco({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8 * s, Position = pos + Vector3.new(side * 0.6 * s, 1.5 * s, -1.2 * s), Color = Color3.fromRGB(40, 30, 25), Material = Enum.Material.SmoothPlastic, Parent = folder })
		deco({ Name = "Horn", Size = Vector3.new(0.5, 0.5, 3) * s, CFrame = CFrame.new(pos + Vector3.new(side * 1.8 * s, 2 * s, 0)) * CFrame.Angles(0, side * 1.2, 0.4), Color = bone, Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
end

function PROPS.Pine(folder, pos, s)
	deco({ Name = "Trunk", Size = Vector3.new(1.6, 5, 1.6) * s, Position = pos + Vector3.new(0, 2.5 * s, 0), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
	for layer = 0, 3 do
		local w = (9 - layer * 2) * s
		local y = (5 + layer * 3) * s
		deco({ Name = "Needles", Size = Vector3.new(w, 2.6 * s, w), CFrame = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, layer * 0.4, 0), Color = Color3.fromRGB(45, 95, 70), Material = Enum.Material.Grass, Parent = folder })
		deco({ Name = "Snow", Size = Vector3.new(w * 0.85, 0.6 * s, w * 0.85), CFrame = CFrame.new(pos + Vector3.new(0, y + 1.5 * s, 0)) * CFrame.Angles(0, layer * 0.4, 0), Color = Color3.fromRGB(245, 250, 255), Material = Enum.Material.Snow, Parent = folder })
	end
end

function PROPS.IceCrystal(folder, pos, s, rng)
	for _ = 1, 3 do
		local h = rng:NextNumber(4, 9) * s
		deco({ Name = "Ice", Size = Vector3.new(1.6, h, 1.6) * s, CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.5, 1.5), h / 2 - 0.5, rng:NextNumber(-1.5, 1.5))) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 3), rng:NextNumber(-0.35, 0.35)), Color = Color3.fromRGB(160, 215, 255), Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.2, Parent = folder })
	end
end

function PROPS.SnowRock(folder, pos, s, rng)
	local r = rock(folder, pos, s, rng, Color3.fromRGB(120, 125, 135), Enum.Material.Slate)
	deco({ Name = "SnowCap", Size = Vector3.new(r.Size.X * 0.9, 0.7, r.Size.Z * 0.9), CFrame = r.CFrame * CFrame.new(0, r.Size.Y / 2, 0), Color = WHITE, Material = Enum.Material.Snow, Parent = folder })
end

function PROPS.Snowman(folder, pos, s)
	local snow = Color3.fromRGB(245, 248, 255)
	deco({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.one * 4 * s, Position = pos + Vector3.new(0, 1.8 * s, 0), Color = snow, Material = Enum.Material.Snow, Parent = folder })
	deco({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.one * 3 * s, Position = pos + Vector3.new(0, 4.6 * s, 0), Color = snow, Material = Enum.Material.Snow, Parent = folder })
	deco({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2 * s, Position = pos + Vector3.new(0, 6.8 * s, 0), Color = snow, Material = Enum.Material.Snow, Parent = folder })
	deco({ Name = "Nose", Size = Vector3.new(0.35, 0.35, 1.3) * s, Position = pos + Vector3.new(0, 6.8 * s, -1.4 * s), Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.8, 1.8) * s, CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, 8.3 * s, 0))), Color = Color3.fromRGB(30, 30, 35), Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "Scarf", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2.6, 2.6) * s, CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, 5.9 * s, 0))), Color = Color3.fromRGB(220, 50, 60), Material = Enum.Material.Fabric, Parent = folder })
end

function PROPS.LavaRock(folder, pos, s, rng)
	local r = rock(folder, pos, s * 1.2, rng, Color3.fromRGB(45, 38, 38), Enum.Material.Basalt)
	deco({ Name = "Crack", Size = Vector3.new(r.Size.X * 0.8, 0.3, 0.4), CFrame = r.CFrame * CFrame.new(0, r.Size.Y * 0.2, -r.Size.Z / 2), Color = Color3.fromRGB(255, 110, 20), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	deco({ Name = "LavaPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 7 * s, 7 * s), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(4 * s, 0.1, 2 * s))), Color = Color3.fromRGB(255, 100, 20), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
end

function PROPS.Obsidian(folder, pos, s, rng)
	for _ = 1, 3 do
		local h = rng:NextNumber(3, 7) * s
		deco({ Name = "Obsidian", Size = Vector3.new(1.8, h, 1.4) * s, CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.5, 1.5), h / 2 - 0.4, rng:NextNumber(-1.5, 1.5))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)), Color = Color3.fromRGB(30, 22, 40), Material = Enum.Material.Glass, Reflectance = 0.3, Parent = folder })
	end
end

function PROPS.Torch(folder, pos)
	deco({ Name = "Post", Size = Vector3.new(0.8, 6, 0.8), Position = pos + Vector3.new(0, 3, 0), Color = Color3.fromRGB(60, 45, 40), Material = Enum.Material.Wood, Parent = folder })
	local bowl = deco({ Name = "Bowl", Size = Vector3.new(1.8, 0.8, 1.8), Position = pos + Vector3.new(0, 6.3, 0), Color = Color3.fromRGB(70, 70, 75), Material = Enum.Material.Metal, Parent = folder })
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 8
	fire.Parent = bowl
	light(bowl, Color3.fromRGB(255, 140, 60), 18, 1.5)
end

function PROPS.DeadTree(folder, pos, s, rng)
	local charred = Color3.fromRGB(40, 32, 30)
	deco({ Name = "Trunk", Size = Vector3.new(1.6, 10, 1.6) * s, Position = pos + Vector3.new(0, 5 * s, 0), Color = charred, Material = Enum.Material.Wood, Parent = folder })
	for i = 1, 3 do
		deco({ Name = "Branch", Size = Vector3.new(0.7, 4.5, 0.7) * s, CFrame = CFrame.new(pos + Vector3.new(0, (5 + i * 1.6) * s, 0)) * CFrame.Angles(0, i * 2.1, 0.8) * CFrame.new(0, 2 * s, 0), Color = charred, Material = Enum.Material.Wood, Parent = folder })
	end
end

function PROPS.Crystal(folder, pos, s, rng)
	local colors = { Color3.fromRGB(180, 110, 255), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 120, 230) }
	local color = colors[rng:NextInteger(1, #colors)]
	for i = 1, 4 do
		local h = rng:NextNumber(4, 12) * s
		deco({ Name = "Crystal", Size = Vector3.new(1.8, h, 1.8) * s, CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-2, 2), h / 2 - 0.5, rng:NextNumber(-2, 2))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)), Color = color, Material = if i == 1 then Enum.Material.Neon else Enum.Material.Glass, Transparency = if i == 1 then 0 else 0.2, CastShadow = false, Parent = folder })
	end
	local children = folder:GetChildren()
	light(children[#children], color, 14, 1)
end

function PROPS.Obelisk(folder, pos, s)
	deco({ Name = "Obelisk", Size = Vector3.new(3, 14, 3) * s, Position = pos + Vector3.new(0, 7 * s, 0), Color = Color3.fromRGB(35, 30, 50), Material = Enum.Material.Slate, Parent = folder })
	local rune = deco({ Name = "Rune", Size = Vector3.new(0.4, 10, 0.2) * s, Position = pos + Vector3.new(0, 7 * s, -1.55 * s), Color = Color3.fromRGB(190, 120, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(rune, Color3.fromRGB(190, 120, 255), 12, 1)
	deco({ Name = "Tip", Size = Vector3.new(2, 2, 2) * s, CFrame = CFrame.new(pos + Vector3.new(0, 14.5 * s, 0)) * CFrame.Angles(0.6, 0.78, 0), Color = Color3.fromRGB(190, 120, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
end

function PROPS.FloatingRock(folder, pos, s, rng)
	local y = rng:NextNumber(10, 26)
	local r = deco({ Name = "FloatingRock", Size = Vector3.new(rng:NextNumber(5, 9), rng:NextNumber(3, 5), rng:NextNumber(5, 9)) * s, CFrame = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 3), rng:NextNumber(-0.2, 0.2)), Color = Color3.fromRGB(55, 45, 75), Material = Enum.Material.Slate, Parent = folder })
	deco({ Name = "Shard", Size = Vector3.new(1.2, 4, 1.2) * s, CFrame = r.CFrame * CFrame.new(0, r.Size.Y / 2 + 1.5, 0), Color = Color3.fromRGB(190, 120, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	deco({ Name = "Drip", Size = Vector3.new(1.5, 3, 1.5) * s, CFrame = r.CFrame * CFrame.new(0, -r.Size.Y / 2 - 1, 0) * CFrame.Angles(0, 0.7, 0), Color = Color3.fromRGB(55, 45, 75), Material = Enum.Material.Slate, Parent = folder })
end

-- Small ground details scattered everywhere: tufts, pebbles, snow piles, embers, shards.
local CLUTTER = {
	Forest = function(folder, p, rng)
		for i = -1, 1 do
			deco({ Name = "Tuft", Size = Vector3.new(0.35, 1.4 + rng:NextNumber(0, 0.8), 0.35), CFrame = CFrame.new(p + Vector3.new(i * 0.4, 0.6, rng:NextNumber(-0.3, 0.3))) * CFrame.Angles(0, 0, math.rad(i * 20)), Color = Color3.fromRGB(70, 150 + rng:NextInteger(-15, 25), 55), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
		end
		if rng:NextNumber() < 0.35 then
			deco({ Name = "Flower", Size = Vector3.one * 0.6, Position = p + Vector3.new(0, 1.7, 0), Color = ({ Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 230, 90), WHITE })[rng:NextInteger(1, 3)], Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
		end
	end,
	Desert = function(folder, p, rng)
		for _ = 1, 2 do
			deco({ Name = "Pebble", Size = Vector3.new(rng:NextNumber(0.6, 1.4), 0.5, rng:NextNumber(0.6, 1.2)), CFrame = CFrame.new(p + Vector3.new(rng:NextNumber(-1, 1), 0.2, rng:NextNumber(-1, 1))) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(190, 150, 100), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
		end
	end,
	Snow = function(folder, p, rng)
		deco({ Name = "SnowPile", Size = Vector3.new(rng:NextNumber(2, 3.5), 0.8, rng:NextNumber(1.5, 3)), Position = p + Vector3.new(0, 0.3, 0), Color = WHITE, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
		deco({ Name = "SnowPile", Size = Vector3.new(1.4, 0.7, 1.2), Position = p + Vector3.new(0.4, 0.8, 0.2), Color = Color3.fromRGB(235, 245, 255), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
	end,
	Volcano = function(folder, p, rng)
		deco({ Name = "Ember", Size = Vector3.new(rng:NextNumber(0.8, 1.6), 0.4, rng:NextNumber(0.8, 1.6)), CFrame = CFrame.new(p + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(255, 110 + rng:NextInteger(0, 60), 30), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	end,
	Void = function(folder, p, rng)
		deco({ Name = "Shard", Size = Vector3.new(0.4, rng:NextNumber(1, 2.2), 0.4), CFrame = CFrame.new(p + Vector3.new(0, 0.6, 0)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)), Color = ({ Color3.fromRGB(200, 130, 255), Color3.fromRGB(120, 200, 255) })[rng:NextInteger(1, 2)], Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	end,
}

local function scatterClutter(folder, def, centerZ, rng)
	local fn = CLUTTER[def.Id]
	if not fn then
		return
	end
	local clutter = Instance.new("Folder")
	clutter.Name = "GroundDetail"
	clutter.Parent = folder
	for _ = 1, 200 do
		local p = Vector3.new(rng:NextNumber(-CORRIDOR_HALF + 6, CORRIDOR_HALF - 6), 0, centerZ + rng:NextNumber(-BIOME_SPACING / 2 + 8, BIOME_SPACING / 2 - 4))
		if math.abs(p.X) > 16 then -- keep the middle path clean
			fn(clutter, p, rng)
		end
	end
end

-- Big landmark structures near the sides of each zone. Positions are offsets
-- from the zone center; LANDMARK_AREAS keeps eggs from spawning inside them.
local LANDMARK_AREAS = {
	Forest = { { -250, -60, 30 }, { 250, 60, 30 }, { -220, 90, 30 }, { 230, -90, 30 } },
	Desert = { { 250, 20, 45 }, { -250, -40, 40 } },
	Snow = { { -240, 40, 30 }, { 240, -60, 30 }, { 230, 90, 25 } },
	Volcano = { { 250, 40, 40 }, { -240, 90, 35 } },
	Void = { { -240, -80, 25 }, { 240, 70, 25 }, { 220, -90, 25 } },
}

local function pyramid(folder, x, z, base, color)
	for i = 0, 5 do
		local w = base - i * base / 6.5
		deco({ Name = "PyramidStep", Size = Vector3.new(w, 5, w), Position = Vector3.new(x, 2.5 + i * 5, z), Color = color:Lerp(WHITE, i * 0.03), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	local top = deco({ Name = "PyramidCap", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(x, 32, z) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(255, 215, 90), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(top, Color3.fromRGB(255, 215, 90), 30, 1.5)
	deco({ Name = "PyramidDoor", Size = Vector3.new(6, 8, 1), Position = Vector3.new(x, 4, z - base / 2 - 0.3), Color = Color3.fromRGB(60, 40, 25), Material = Enum.Material.SmoothPlastic, Parent = folder })
end

local LANDMARKS = {}

function LANDMARKS.Forest(folder, centerZ, rng)
	for _, spot in ipairs(LANDMARK_AREAS.Forest) do
		if spot[2] ~= 90 then
			local m = Instance.new("Model")
			m.Name = "GiantTree"
			m.Parent = folder
			PROPS.Tree(m, Vector3.new(spot[1], 0, centerZ + spot[2]), 2.8, rng)
		end
	end
	-- fairy ring of mushrooms
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local m = Instance.new("Model")
		m.Name = "RingMushroom"
		m.Parent = folder
		PROPS.Mushroom(m, Vector3.new(-220 + math.cos(a) * 18, 0, centerZ + 90 + math.sin(a) * 18), 1.1, rng)
	end
end

function LANDMARKS.Desert(folder, centerZ)
	pyramid(folder, 250, centerZ + 20, 70, Color3.fromRGB(225, 185, 120))
	pyramid(folder, -250, centerZ - 40, 55, Color3.fromRGB(215, 175, 110))
end

function LANDMARKS.Snow(folder, centerZ, rng)
	local x, z = -240, centerZ + 40
	local dome = deco({ Name = "Igloo", Shape = Enum.PartType.Ball, Size = Vector3.one * 34, Position = Vector3.new(x, 0, z), Color = Color3.fromRGB(240, 248, 255), Material = Enum.Material.SmoothPlastic, Parent = folder })
	light(dome, Color3.fromRGB(255, 200, 140), 30, 1)
	for ring = 1, 3 do
		deco({ Name = "IglooLine", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 34 * math.cos(math.asin(ring * 4 / 17)) + 0.4, 34 * math.cos(math.asin(ring * 4 / 17)) + 0.4), CFrame = CFrame.new(x, ring * 4, z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(200, 222, 245), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	deco({ Name = "IglooTunnel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 11, 11), CFrame = CFrame.new(x + 17, 3, z) * CFrame.Angles(0, 0, 0), Color = Color3.fromRGB(235, 245, 255), Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "IglooDoor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 7, 7), CFrame = CFrame.new(x + 22.2, 3, z), Color = Color3.fromRGB(40, 50, 70), Material = Enum.Material.SmoothPlastic, Parent = folder })
	for _, spot in ipairs({ { 240, -60 }, { 230, 90 } }) do
		local m = Instance.new("Model")
		m.Name = "GiantPine"
		m.Parent = folder
		PROPS.Pine(m, Vector3.new(spot[1], 0, centerZ + spot[2]), 2.6, rng)
	end
end

function LANDMARKS.Volcano(folder, centerZ)
	for _, spot in ipairs({ { 250, 40, 1 }, { -240, 90, 0.8 } }) do
		local x, z, sc = spot[1], centerZ + spot[2], spot[3]
		for i = 0, 5 do
			local w = (40 - i * 6) * sc
			deco({ Name = "VolcanoLayer", Size = Vector3.new(w, 6 * sc, w), Position = Vector3.new(x, (3 + i * 6) * sc, z), Color = Color3.fromRGB(72 - i * 3, 50 - i * 2, 46 - i * 2), Material = Enum.Material.SmoothPlastic, Parent = folder })
		end
		local crater = deco({ Name = "Crater", Size = Vector3.new(7, 1, 7) * sc, Position = Vector3.new(x, 36.3 * sc, z), Color = Color3.fromRGB(255, 110, 20), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		local fire = Instance.new("Fire")
		fire.Size = 14
		fire.Heat = 22
		fire.Parent = crater
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(70, 60, 60)
		smoke.Size = 22
		smoke.RiseVelocity = 12
		smoke.Opacity = 0.2
		smoke.Parent = crater
		light(crater, Color3.fromRGB(255, 110, 40), 45, 3)
		for side = -1, 1, 2 do
			deco({ Name = "LavaFlow", Size = Vector3.new(3, 0.3, 30 * sc), CFrame = CFrame.new(x + side * 8 * sc, 0.12, z - 30 * sc) * CFrame.Angles(0, side * 0.25, 0), Color = Color3.fromRGB(255, 100, 20), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		end
	end
end

function LANDMARKS.Void(folder, centerZ, rng)
	for _, spot in ipairs(LANDMARK_AREAS.Void) do
		local m = Instance.new("Model")
		m.Name = "GiantCrystal"
		m.Parent = folder
		PROPS.Crystal(m, Vector3.new(spot[1], 0, centerZ + spot[2]), 3, rng)
	end
end

local PROPS_PER_ZONE = 150 -- spread over the bigger zones, still leaving clear lanes
local function placeProps(folder, def, centerZ, rng, keepClear)
	-- each entry: { position, clearance radius }
	local placed = {}
	for _, p in ipairs(keepClear or {}) do
		table.insert(placed, { Vector2.new(p.X, p.Z), p.Y > 0 and p.Y or 11 })
	end
	local count = 0
	local tries = 0
	while count < PROPS_PER_ZONE and tries < 3000 do
		tries += 1
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = side * rng:NextNumber(26, CORRIDOR_HALF - 8)
		local z = centerZ + rng:NextNumber(-BIOME_SPACING / 2 + 16, BIOME_SPACING / 2 - 10)
		local ok = true
		for _, other in ipairs(placed) do
			if (Vector2.new(x, z) - other[1]).Magnitude < other[2] then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, { Vector2.new(x, z), 11 })
			count += 1
			local kind = def.Props[rng:NextInteger(1, #def.Props)]
			local model = Instance.new("Model")
			model.Name = kind
			model.Parent = folder
			PROPS[kind](model, Vector3.new(x, 0, z), rng:NextNumber(0.85, 1.35), rng)
		end
	end
end

--------------------------------------------------------------------------------
-- Ambient particles over a biome
--------------------------------------------------------------------------------
local AMBIENT = {
	Fireflies = { Y = 3, Props = { Color = ColorSequence.new(Color3.fromRGB(220, 255, 120)), LightEmission = 1, Size = NumberSequence.new(0.25), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(3, 6), Rate = 30, Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180), Drag = 1 } },
	Dust = { Y = 2, Props = { Color = ColorSequence.new(Color3.fromRGB(235, 205, 150)), LightEmission = 0.2, Size = NumberSequence.new(0.35), Transparency = NumberSequence.new(0.4), Lifetime = NumberRange.new(4, 7), Rate = 40, Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(20, 20), Acceleration = Vector3.new(4, 0.5, 0), EmissionDirection = Enum.NormalId.Top } },
	Snowfall = { Y = 45, Props = { Color = ColorSequence.new(WHITE), LightEmission = 0.4, Size = NumberSequence.new(0.35), Transparency = NumberSequence.new(0.1), Lifetime = NumberRange.new(8, 10), Rate = 160, Speed = NumberRange.new(0, 1), Acceleration = Vector3.new(0.6, -5, 0), EmissionDirection = Enum.NormalId.Bottom } },
	Embers = { Y = 1, Props = { Color = ColorSequence.new(Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 60, 20)), LightEmission = 1, Size = NumberSequence.new(0.3, 0.05), Transparency = NumberSequence.new(0, 1), Lifetime = NumberRange.new(3, 6), Rate = 70, Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top } },
	Leaves = { Y = 40, Props = { Color = ColorSequence.new(Color3.fromRGB(120, 190, 70), Color3.fromRGB(230, 170, 60)), LightEmission = 0, Size = NumberSequence.new(0.5), Transparency = NumberSequence.new(0.1), Lifetime = NumberRange.new(8, 12), Rate = 25, Speed = NumberRange.new(0, 1), RotSpeed = NumberRange.new(-90, 90), Rotation = NumberRange.new(0, 360), Acceleration = Vector3.new(1.5, -4, 0.5), EmissionDirection = Enum.NormalId.Bottom } },
	Ash = { Y = 50, Props = { Color = ColorSequence.new(Color3.fromRGB(90, 85, 85)), LightEmission = 0, Size = NumberSequence.new(0.3), Transparency = NumberSequence.new(0.3), Lifetime = NumberRange.new(10, 14), Rate = 70, Speed = NumberRange.new(0, 1), Acceleration = Vector3.new(0.8, -4, 0), EmissionDirection = Enum.NormalId.Bottom } },
	Stardust = { Y = 1, Props = { Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 170, 255)), LightEmission = 1, Size = NumberSequence.new(0.2, 0), Transparency = NumberSequence.new(0, 1), Lifetime = NumberRange.new(6, 10), Rate = 40, Speed = NumberRange.new(2, 4), EmissionDirection = Enum.NormalId.Top } },
	Motes = { Y = 2, Props = { Color = ColorSequence.new(Color3.fromRGB(200, 140, 255), Color3.fromRGB(120, 200, 255)), LightEmission = 1, Size = NumberSequence.new(0.4, 0), Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(5, 8), Rate = 60, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top } },
}

-- A second particle layer for some zones
local EXTRA_AMBIENT = { Forest = "Leaves", Volcano = "Ash", Void = "Stardust" }

local function ambientParticles(folder, kind, centerZ)
	local info = AMBIENT[kind]
	if not info then
		return
	end
	local emitterPart = deco({ Name = kind .. "Emitter", Size = Vector3.new(CORRIDOR_HALF * 2 - 10, 1, BIOME_SPACING), Position = Vector3.new(0, info.Y, centerZ), Transparency = 1, CanCollide = false, CastShadow = false, Parent = folder })
	particles(emitterPart, info.Props)
end

--------------------------------------------------------------------------------
-- Biome features
--------------------------------------------------------------------------------
local FEATURES = {}

-- Areas each feature covers (x, z offset from zone center, radius) so eggs don't spawn in them.
local FEATURE_AREAS = {
	Pond = { { 78, 40, 24 } },
	FrozenLake = { { -75, -10, 32 } },
	Volcano = { { -82, -30, 30 }, { -45, -20, 20 } },
}

function FEATURES.Pond(folder, centerZ, rng)
	local x, z = 78, centerZ + 40
	deco({ Name = "PondRim", Size = Vector3.new(30, 1, 24), Position = Vector3.new(x, 0.5, z), Color = Color3.fromRGB(150, 150, 150), Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "PondWater", Size = Vector3.new(26, 1.1, 20), Position = Vector3.new(x, 0.56, z), Color = Color3.fromRGB(60, 160, 220), Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.25, CanCollide = false, Parent = folder })
	for _ = 1, 4 do
		deco({ Name = "LilyPad", Size = Vector3.new(2.4, 0.2, 2.4), Position = Vector3.new(x + rng:NextNumber(-9, 9), 1.2, z + rng:NextNumber(-6, 6)), Color = Color3.fromRGB(80, 170, 70), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
	end
end

-- Stepped blocky sand mounds
function FEATURES.Dunes(folder, centerZ, rng, keepClear)
	for _ = 1, 7 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local p = Vector3.new(side * rng:NextNumber(50, 100), 0, centerZ + rng:NextNumber(-95, 95))
		for _, spot in ipairs(keepClear or {}) do
			if (spot - p).Magnitude < 14 then
				p = Vector3.new(p.X, 0, p.Z + 30) -- nudge off the egg
			end
		end
		for step = 0, 2 do
			local w = 16 - step * 5
			deco({ Name = "Dune", Size = Vector3.new(w, 2, w * 0.8), Position = p + Vector3.new(0, 1 + step * 2, 0), Color = Color3.fromRGB(236, 205, 138):Lerp(WHITE, step * 0.05), Material = Enum.Material.SmoothPlastic, Parent = folder })
		end
	end
end

function FEATURES.FrozenLake(folder, centerZ)
	deco({ Name = "Ice", Size = Vector3.new(32, 0.4, 44), Position = Vector3.new(-75, 0.2, centerZ - 10), Color = Color3.fromRGB(175, 220, 250), Material = Enum.Material.Glass, Transparency = 0.1, Reflectance = 0.35, Parent = folder })
	deco({ Name = "IceRim", Size = Vector3.new(35, 0.3, 47), Position = Vector3.new(-75, 0.1, centerZ - 10), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = folder })
end

-- Blocky volcano with a glowing crater, smoke and lava rivers
function FEATURES.Volcano(folder, centerZ)
	local x, z = -82, centerZ - 30
	for i = 0, 5 do
		local w = 34 - i * 5
		deco({ Name = "VolcanoLayer", Size = Vector3.new(w, 5, w), Position = Vector3.new(x, 2.5 + i * 5, z), Color = Color3.fromRGB(70 - i * 3, 48 - i * 2, 45 - i * 2), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	local crater = deco({ Name = "Crater", Size = Vector3.new(6, 1, 6), Position = Vector3.new(x, 30.2, z), Color = Color3.fromRGB(255, 110, 20), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(70, 60, 60)
	smoke.Size = 20
	smoke.RiseVelocity = 12
	smoke.Opacity = 0.2
	smoke.Parent = crater
	local fire = Instance.new("Fire")
	fire.Size = 12
	fire.Heat = 20
	fire.Parent = crater
	light(crater, Color3.fromRGB(255, 110, 40), 40, 3)
	for i = 1, 3 do
		deco({ Name = "LavaRiver", Size = Vector3.new(3, 0.2, 30 + i * 6), CFrame = CFrame.new(x + 12 + i * 7, 0.1, z + 10 + i * 4) * CFrame.Angles(0, (i - 2) * 0.35, 0), Color = Color3.fromRGB(255, 100, 20), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	end
end

function FEATURES.FloatingIslands(folder, centerZ, rng)
	for _ = 1, 12 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local pos = Vector3.new(side * rng:NextNumber(40, CORRIDOR_HALF - 40), rng:NextNumber(30, 55), centerZ + rng:NextNumber(-110, 110))
		local island = deco({ Name = "Island", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 16, 16), CFrame = cylinderAlongY(CFrame.new(pos)), Color = Color3.fromRGB(50, 40, 70), Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "Underside", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), Position = pos - Vector3.new(0, 5, 0), Color = Color3.fromRGB(45, 35, 62), Material = Enum.Material.Slate, Parent = folder })
		for i = 1, 3 do
			deco({ Name = "Crystal", Size = Vector3.new(1.4, rng:NextNumber(3, 6), 1.4), CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-4, 4), 3.5, rng:NextNumber(-4, 4))) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(180, 110, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		end
		light(island, Color3.fromRGB(180, 110, 255), 20, 1)
	end
	-- a glowing ring over the road
	local ring = deco({ Name = "PortalRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 40, 40), CFrame = CFrame.new(0, 22, centerZ - 60) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(170, 90, 255), Material = Enum.Material.ForceField, CanCollide = false, CastShadow = false, Parent = folder })
	ring.Transparency = 0.2
end

--------------------------------------------------------------------------------
-- Building helpers for set pieces
--------------------------------------------------------------------------------
-- Gable roof. `cf` is the center of the roof's base; the ridge runs along X.
local function roof(folder, cf, length, width, height, color, material)
	deco({ Name = "Roof", Shape = Enum.PartType.Wedge, Size = Vector3.new(length, height, width / 2), CFrame = cf * CFrame.new(0, height / 2, -width / 4), Color = color, Material = material or Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "Roof", Shape = Enum.PartType.Wedge, Size = Vector3.new(length, height, width / 2), CFrame = cf * CFrame.new(0, height / 2, width / 4) * CFrame.Angles(0, math.pi, 0), Color = color, Material = material or Enum.Material.SmoothPlastic, Parent = folder })
end

-- A cozy little house. `cf` sits on the ground at the house's center; the door faces local -Z.
local function house(folder, cf, w, h, d, opts)
	opts = opts or {}
	local wallColor = opts.Wall or Color3.fromRGB(240, 225, 200)
	local trim = opts.Trim or DARK_WOOD
	local glow = Color3.fromRGB(255, 200, 120)
	deco({ Name = "HouseWalls", Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, h / 2, 0), Color = wallColor, Material = opts.WallMaterial or Enum.Material.SmoothPlastic, Parent = folder })
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "CornerBeam", Size = Vector3.new(0.8, h, 0.8), CFrame = cf * CFrame.new(sx * w / 2, h / 2, -d / 2), Color = trim, Material = Enum.Material.Wood, Parent = folder })
		deco({ Name = "CornerBeam", Size = Vector3.new(0.8, h, 0.8), CFrame = cf * CFrame.new(sx * w / 2, h / 2, d / 2), Color = trim, Material = Enum.Material.Wood, Parent = folder })
		-- glowing windows with frames and flower boxes
		local win = cf * CFrame.new(sx * w * 0.28, h * 0.58, -d / 2 - 0.1)
		deco({ Name = "WindowFrame", Size = Vector3.new(3.4, 3.4, 0.3), CFrame = win, Color = trim, Material = Enum.Material.Wood, Parent = folder })
		local pane = deco({ Name = "Window", Size = Vector3.new(2.8, 2.8, 0.35), CFrame = win, Color = glow, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		deco({ Name = "WindowBar", Size = Vector3.new(0.25, 2.8, 0.45), CFrame = win, Color = trim, Material = Enum.Material.Wood, Parent = folder })
		deco({ Name = "WindowBar", Size = Vector3.new(2.8, 0.25, 0.45), CFrame = win, Color = trim, Material = Enum.Material.Wood, Parent = folder })
		deco({ Name = "FlowerBox", Size = Vector3.new(3.6, 0.8, 1), CFrame = win * CFrame.new(0, -2.1, -0.4), Color = trim, Material = Enum.Material.Wood, Parent = folder })
		for k = -1, 1 do
			deco({ Name = "BoxFlower", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = win * CFrame.new(k * 1.1, -1.5, -0.4), Color = ({ Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 225, 80), WHITE })[k + 2], Material = Enum.Material.SmoothPlastic, Parent = folder })
		end
		if sx == 1 then
			light(pane, glow, 16, 0.8)
		end
	end
	deco({ Name = "Door", Size = Vector3.new(3.2, 5.6, 0.4), CFrame = cf * CFrame.new(0, 2.8, -d / 2 - 0.15), Color = trim, Material = Enum.Material.WoodPlanks, Parent = folder })
	deco({ Name = "DoorKnob", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.4, CFrame = cf * CFrame.new(1, 2.8, -d / 2 - 0.45), Color = Color3.fromRGB(255, 205, 70), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "DoorStep", Size = Vector3.new(5, 0.5, 2), CFrame = cf * CFrame.new(0, 0.25, -d / 2 - 1), Color = STONE, Material = Enum.Material.Slate, Parent = folder })
	lantern(folder, (cf * CFrame.new(2.6, 5.4, -d / 2 - 0.7)).Position, WARM_LIGHT, 12)
	local roofH = opts.RoofHeight or h * 0.6
	roof(folder, cf * CFrame.new(0, h, 0), w + 2, d + 2, roofH, opts.Roof or Color3.fromRGB(190, 70, 60), opts.RoofMaterial)
	if opts.Chimney ~= false then
		local chimney = deco({ Name = "Chimney", Size = Vector3.new(2, roofH + 2, 2), CFrame = cf * CFrame.new(w * 0.3, h + (roofH + 2) / 2, d * 0.15), Color = Color3.fromRGB(150, 90, 70), Material = Enum.Material.Brick, Parent = folder })
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(220, 220, 225)
		smoke.Opacity = 0.12
		smoke.Size = 3
		smoke.RiseVelocity = 4
		smoke.Parent = chimney
	end
end

local function column(folder, pos, h, color, material)
	deco({ Name = "ColumnBase", Size = Vector3.new(4.4, 1, 4.4), Position = pos + Vector3.new(0, 0.5, 0), Color = color:Lerp(BLACK, 0.1), Material = material, Parent = folder })
	deco({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 3.2, 3.2), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, 1 + h / 2, 0))), Color = color, Material = material, Parent = folder })
	deco({ Name = "ColumnTop", Size = Vector3.new(4.4, 1, 4.4), Position = pos + Vector3.new(0, 1.5 + h, 0), Color = color:Lerp(BLACK, 0.1), Material = material, Parent = folder })
end

local function palm(folder, pos, s, rng)
	local lean = rng:NextNumber(-0.25, 0.25)
	local top = pos
	for i = 0, 5 do
		local seg = CFrame.new(pos + Vector3.new(lean * i * i * 0.35 * s, (1.2 + i * 2.2) * s, 0)) * CFrame.Angles(0, 0, -lean * i * 0.12)
		deco({ Name = "PalmTrunk", Size = Vector3.new(1.6 - i * 0.1, 2.4, 1.6 - i * 0.1) * s, CFrame = seg, Color = Color3.fromRGB(150 - i * 5, 110 - i * 4, 70), Material = Enum.Material.Wood, Parent = folder })
		top = seg.Position
	end
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		deco({ Name = "Frond", Size = Vector3.new(1.6, 0.3, 7) * s, CFrame = CFrame.new(top + Vector3.new(0, 1.2 * s, 0)) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, -3.2 * s), Color = Color3.fromRGB(70, 160 + (i % 2) * 20, 60), Material = Enum.Material.Grass, Parent = folder })
	end
	for i = 0, 2 do
		deco({ Name = "Coconut", Shape = Enum.PartType.Ball, Size = Vector3.one * 1 * s, Position = top + Vector3.new(math.cos(i * 2.1) * 0.8 * s, 0.4 * s, math.sin(i * 2.1) * 0.8 * s), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
end

--------------------------------------------------------------------------------
-- Set pieces: four hand-built scenes per zone, out toward the walls.
-- Offsets are from the zone center (x, z, radius kept clear of eggs).
--------------------------------------------------------------------------------
local SETPIECE_SPOTS = {
	Forest = { { "Treehouse", -350, 30, 38 }, { "Waterfall", 385, 60, 36 }, { "GlowGrove", -360, -95, 30 }, { "Campsite", 350, -85, 28 } },
	Desert = { { "Oasis", -360, 50, 40 }, { "Ribcage", 370, -70, 40 }, { "SandArch", -350, -100, 30 }, { "Ruins", 360, 95, 34 } },
	Snow = { { "Cabin", -360, -70, 34 }, { "IceFalls", 385, 35, 36 }, { "SnowFort", -350, 100, 30 }, { "SledHill", 360, -100, 30 } },
	Volcano = { { "Basalt", -365, -20, 38 }, { "LavaLake", 360, -85, 44 }, { "Forge", 360, 95, 32 }, { "Geysers", -350, 110, 28 } },
	Void = { { "RuneCircle", -360, 30, 36 }, { "SkyStairs", 370, -60, 32 }, { "Portal", 360, 100, 30 }, { "Observatory", -350, -100, 30 } },
}

local SETPIECES = {}

function SETPIECES.Treehouse(folder, o, rng)
	deco({ Name = "GiantTrunk", Size = Vector3.new(8, 36, 8), Position = o + Vector3.new(0, 18, 0), Color = Color3.fromRGB(115, 78, 48), Material = Enum.Material.Wood, Parent = folder })
	for _, a in ipairs({ 0, 1.6, 3.2, 4.7 }) do
		deco({ Name = "Root", Size = Vector3.new(2.4, 3, 8), CFrame = CFrame.new(o + Vector3.new(math.cos(a) * 5, 1.2, math.sin(a) * 5)) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(-20), 0, 0), Color = Color3.fromRGB(105, 70, 44), Material = Enum.Material.Wood, Parent = folder })
	end
	for layer = 0, 1 do
		for ix = -1, 1 do
			for iz = -1, 1 do
				if not (layer == 1 and math.abs(ix) + math.abs(iz) == 2) then
					leafCube(folder, o + Vector3.new(ix * 9, 40 + layer * 8, iz * 9), 9.5, rng)
				end
			end
		end
	end
	local deck = o + Vector3.new(0, 20, 0)
	deco({ Name = "Deck", Size = Vector3.new(24, 1.2, 24), Position = deck, Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = folder })
	for _, sx in ipairs({ -1, 1 }) do
		for _, axis in ipairs({ "X", "Z" }) do
			local off = if axis == "X" then Vector3.new(sx * 11.5, 0, 0) else Vector3.new(0, 0, sx * 11.5)
			deco({ Name = "Rail", Size = if axis == "X" then Vector3.new(0.6, 0.6, 24) else Vector3.new(24, 0.6, 0.6), Position = deck + off + Vector3.new(0, 3, 0), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
			for k = -2, 2 do
				local post = if axis == "X" then Vector3.new(0, 0, k * 5.5) else Vector3.new(k * 5.5, 0, 0)
				deco({ Name = "RailPost", Size = Vector3.new(0.6, 3, 0.6), Position = deck + off + post + Vector3.new(0, 1.5, 0), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
			end
		end
	end
	house(folder, CFrame.new(deck + Vector3.new(4, 0.6, 3)) * CFrame.Angles(0, math.rad(20), 0), 11, 7, 9, { Wall = Color3.fromRGB(200, 150, 100), WallMaterial = Enum.Material.WoodPlanks, Roof = Color3.fromRGB(70, 130, 70), Chimney = false })
	-- ladder down the front
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "LadderRail", Size = Vector3.new(0.5, 20, 0.5), Position = o + Vector3.new(sx * 1.4, 10, -12.5), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
	end
	for y = 1.5, 19, 2 do
		deco({ Name = "Rung", Size = Vector3.new(3, 0.35, 0.35), Position = o + Vector3.new(0, y, -12.5), Color = WOOD, Material = Enum.Material.Wood, Parent = folder })
	end
	-- rope swing from a branch
	deco({ Name = "Branch", Size = Vector3.new(14, 1.6, 1.6), Position = o + Vector3.new(-10, 30, 0), Color = Color3.fromRGB(110, 75, 46), Material = Enum.Material.Wood, Parent = folder })
	for _, sz in ipairs({ -0.8, 0.8 }) do
		deco({ Name = "Rope", Size = Vector3.new(0.2, 22, 0.2), Position = o + Vector3.new(-15, 18.5, sz), Color = Color3.fromRGB(220, 195, 140), Material = Enum.Material.Fabric, Parent = folder })
	end
	deco({ Name = "SwingSeat", Size = Vector3.new(2.6, 0.4, 2.2), Position = o + Vector3.new(-15, 7.5, 0), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = folder })
	for i = -2, 2 do
		lantern(folder, deck + Vector3.new(i * 5, 7.5 - math.abs(i) * 0.4, -12), Color3.fromRGB(255, 225, 140), 10)
	end
end

function SETPIECES.Waterfall(folder, o, rng)
	local rockColor = Color3.fromRGB(120, 125, 120)
	for i = 0, 3 do
		deco({ Name = "Cliff", Size = Vector3.new(26 - i * 4, 12, 20 - i * 3), CFrame = CFrame.new(o + Vector3.new(30 - i * 2, 6 + i * 11, 0)) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0), Color = rockColor:Lerp(BLACK, i * 0.05), Material = Enum.Material.Slate, Parent = folder })
		leafCube(folder, o + Vector3.new(24 - i * 2, 12.5 + i * 11, rng:NextNumber(-7, 7)), 4, rng)
	end
	local fall = deco({ Name = "Waterfall", Size = Vector3.new(1, 44, 12), Position = o + Vector3.new(17, 22, 0), Color = Color3.fromRGB(140, 210, 255), Material = Enum.Material.Glass, Transparency = 0.3, Reflectance = 0.2, CanCollide = false, CastShadow = false, Parent = folder })
	particles(fall, { Color = ColorSequence.new(WHITE), LightEmission = 0.2, Size = NumberSequence.new(1.2, 2.5), Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(1, 2), Rate = 25, Speed = NumberRange.new(4, 8), Acceleration = Vector3.new(0, -20, 0), SpreadAngle = Vector2.new(10, 10), EmissionDirection = Enum.NormalId.Left })
	deco({ Name = "PoolRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 34, 34), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.6, 0))), Color = rockColor, Material = Enum.Material.Slate, Parent = folder })
	local pool = deco({ Name = "Pool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, 30, 30), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.65, 0))), Color = Color3.fromRGB(60, 160, 220), Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.3, CanCollide = false, Parent = folder })
	particles(pool, { Color = ColorSequence.new(WHITE), LightEmission = 0.3, Size = NumberSequence.new(1.5, 3), Transparency = NumberSequence.new(0.6, 1), Lifetime = NumberRange.new(1.5, 2.5), Rate = 12, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top })
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		deco({ Name = "LilyPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3, 3), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(math.cos(a) * rng:NextNumber(3, 11), 1.35, math.sin(a) * rng:NextNumber(3, 11)))), Color = Color3.fromRGB(80, 170, 70), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
	end
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		rock(folder, o + Vector3.new(math.cos(a) * 17, 0, math.sin(a) * 17), 0.45, rng, rockColor, Enum.Material.Slate)
	end
end

function SETPIECES.GlowGrove(folder, o, rng)
	local glowColors = { Color3.fromRGB(90, 230, 255), Color3.fromRGB(200, 120, 255), Color3.fromRGB(120, 255, 170) }
	for i = 1, 9 do
		local a = i * 2.4
		local r = if i == 1 then 0 else rng:NextNumber(6, 20)
		local s = if i == 1 then 2.4 else rng:NextNumber(0.8, 1.6)
		local p = o + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local col = glowColors[(i % 3) + 1]
		deco({ Name = "ShroomStem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.5 * s, 1.2 * s, 1.2 * s), CFrame = cylinderAlongY(CFrame.new(p + Vector3.new(0, 1.75 * s, 0))), Color = Color3.fromRGB(235, 230, 215), Material = Enum.Material.SmoothPlastic, Parent = folder })
		local cap = deco({ Name = "GlowCap", Shape = Enum.PartType.Ball, Size = Vector3.new(4.4, 2.2, 4.4) * s, Position = p + Vector3.new(0, 3.6 * s, 0), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = cap
		if i <= 3 then
			light(cap, col, 22, 1.2)
		end
	end
	local sprite = deco({ Name = "FairyDust", Size = Vector3.new(40, 1, 40), Position = o + Vector3.new(0, 3, 0), Transparency = 1, CanCollide = false, CastShadow = false, Parent = folder })
	particles(sprite, { Color = ColorSequence.new(Color3.fromRGB(180, 255, 240), Color3.fromRGB(220, 170, 255)), LightEmission = 1, Size = NumberSequence.new(0.35, 0), Lifetime = NumberRange.new(3, 5), Rate = 15, Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180), EmissionDirection = Enum.NormalId.Top })
end

function SETPIECES.Campsite(folder, o, rng)
	local tentCf = CFrame.new(o + Vector3.new(-8, 0, 4)) * CFrame.Angles(0, math.rad(15), 0)
	roof(folder, tentCf, 10, 9, 6, Color3.fromRGB(230, 120, 50), Enum.Material.Fabric)
	deco({ Name = "TentDoor", Size = Vector3.new(0.3, 4, 3), CFrame = tentCf * CFrame.new(-5.05, 2, 0), Color = Color3.fromRGB(60, 40, 30), Material = Enum.Material.Fabric, Parent = folder })
	local fireRing = o + Vector3.new(6, 0, -4)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		deco({ Name = "FireStone", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, Position = fireRing + Vector3.new(math.cos(a) * 2, 0.4, math.sin(a) * 2), Color = STONE, Material = Enum.Material.Slate, Parent = folder })
	end
	for i = 0, 2 do
		deco({ Name = "FireLog", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 0.6, 0.6), CFrame = CFrame.new(fireRing + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, i * 1.05, math.rad(15)), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
	end
	local embers = deco({ Name = "Embers", Size = Vector3.new(1.6, 0.4, 1.6), Position = fireRing + Vector3.new(0, 0.6, 0), Color = Color3.fromRGB(255, 130, 40), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 9
	fire.Parent = embers
	light(embers, Color3.fromRGB(255, 150, 70), 26, 1.8)
	for _, off in ipairs({ Vector3.new(6, 0, 3), Vector3.new(12, 0, -4) }) do
		deco({ Name = "LogSeat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 1.4, 1.4), CFrame = CFrame.lookAt(fireRing + off + Vector3.new(0, 0.7, 0), fireRing + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, math.rad(90), 0), Color = WOOD, Material = Enum.Material.Wood, Parent = folder })
	end
	deco({ Name = "Backpack", Size = Vector3.new(1.6, 2.2, 1.2), Position = o + Vector3.new(-2, 1.1, -3), Color = Color3.fromRGB(60, 110, 190), Material = Enum.Material.Fabric, Parent = folder })
	deco({ Name = "Firewood", Size = Vector3.new(4, 1.6, 1.6), Position = o + Vector3.new(-12, 0.8, -6), Color = WOOD, Material = Enum.Material.Wood, Parent = folder })
end

function SETPIECES.Oasis(folder, o, rng)
	deco({ Name = "OasisSand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 46, 46), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.3, 0))), Color = Color3.fromRGB(230, 210, 160), Material = Enum.Material.Sand, Parent = folder })
	deco({ Name = "OasisGrass", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 36, 36), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.35, 0))), Color = Color3.fromRGB(110, 180, 80), Material = Enum.Material.Grass, Parent = folder })
	deco({ Name = "OasisWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 24, 24), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.4, 0))), Color = Color3.fromRGB(40, 190, 210), Material = Enum.Material.Glass, Transparency = 0.1, Reflectance = 0.35, CanCollide = false, Parent = folder })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.3
		palm(folder, o + Vector3.new(math.cos(a) * 15, 0, math.sin(a) * 15), rng:NextNumber(1.1, 1.5), rng)
	end
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		deco({ Name = "Reed", Size = Vector3.new(0.3, rng:NextNumber(2, 3.5), 0.3), Position = o + Vector3.new(math.cos(a) * 12.4, 1.4, math.sin(a) * 12.4), Color = Color3.fromRGB(90, 150, 60), Material = Enum.Material.Grass, Parent = folder })
	end
end

function SETPIECES.Ribcage(folder, o, rng)
	local bone = Color3.fromRGB(240, 230, 205)
	for i = 0, 8 do
		deco({ Name = "Vertebra", Shape = Enum.PartType.Ball, Size = Vector3.one * (3.2 - i * 0.12), Position = o + Vector3.new(0, 1.3 + math.sin(i / 8 * math.pi) * 3, -20 + i * 4.5), Color = bone, Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	for i = 1, 6 do
		local z = -18 + i * 5.5
		local size = 1 - math.abs(i - 3.5) * 0.1
		for _, sx in ipairs({ -1, 1 }) do
			local prev = o + Vector3.new(0, 4 + math.sin(i / 8 * math.pi) * 3, z)
			for k = 1, 4 do
				local ang = k / 4 * math.rad(150)
				local p = o + Vector3.new(sx * math.sin(ang) * 11 * size, (4 + math.cos(ang) * 9) * size + 2, z)
				local mid = (prev + p) / 2
				deco({ Name = "Rib", Size = Vector3.new(1.1, 1.1, (p - prev).Magnitude + 0.6), CFrame = CFrame.lookAt(mid, p), Color = bone, Material = Enum.Material.SmoothPlastic, Parent = folder })
				prev = p
			end
		end
	end
	local skull = o + Vector3.new(0, 4, -26)
	deco({ Name = "GiantSkull", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 9, 13), Position = skull, Color = bone, Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "Jaw", Size = Vector3.new(8, 2.4, 9), Position = skull + Vector3.new(0, -4, -3), Color = bone:Lerp(BLACK, 0.08), Material = Enum.Material.SmoothPlastic, Parent = folder })
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "EyeSocket", Shape = Enum.PartType.Ball, Size = Vector3.one * 3, Position = skull + Vector3.new(sx * 2.4, 1.2, -5.4), Color = Color3.fromRGB(50, 35, 30), Material = Enum.Material.SmoothPlastic, Parent = folder })
		deco({ Name = "SkullHorn", Size = Vector3.new(1.6, 1.6, 10), CFrame = CFrame.new(skull + Vector3.new(sx * 6, 4, 1)) * CFrame.Angles(math.rad(35), math.rad(40 * sx), 0), Color = bone, Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	for i = 1, 3 do
		deco({ Name = "SandDrift", Size = Vector3.new(rng:NextNumber(8, 14), 1.4, rng:NextNumber(6, 10)), CFrame = CFrame.new(o + Vector3.new(rng:NextNumber(-10, 10), 0.5, -20 + i * 12)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(236, 205, 138), Material = Enum.Material.Sand, Parent = folder })
	end
end

function SETPIECES.SandArch(folder, o, rng)
	local stone = Color3.fromRGB(210, 150, 100)
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 3 do
			deco({ Name = "ArchLeg", Size = Vector3.new(7 - i * 0.6, 6, 7 - i * 0.6), CFrame = CFrame.new(o + Vector3.new(sx * (14 - i * 0.8), 3 + i * 6, 0)) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0), Color = stone:Lerp(WHITE, i * 0.04), Material = Enum.Material.Sandstone, Parent = folder })
		end
	end
	local prev = o + Vector3.new(-13, 24, 0)
	for k = 1, 6 do
		local ang = k / 6 * math.pi
		local p = o + Vector3.new(-math.cos(ang) * 13, 24 + math.sin(ang) * 7, 0)
		deco({ Name = "ArchTop", Size = Vector3.new(6, 5, (p - prev).Magnitude + 2), CFrame = CFrame.lookAt((prev + p) / 2, p), Color = stone:Lerp(WHITE, 0.12), Material = Enum.Material.Sandstone, Parent = folder })
		prev = p
	end
	for _ = 1, 4 do
		rock(folder, o + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-10, 10)), 0.6, rng, stone, Enum.Material.Sandstone)
	end
end

function SETPIECES.Ruins(folder, o, rng)
	local stone = Color3.fromRGB(230, 210, 170)
	deco({ Name = "RuinFloor", Size = Vector3.new(40, 0.6, 22), Position = o + Vector3.new(0, 0.3, 0), Color = stone:Lerp(BLACK, 0.08), Material = Enum.Material.Sandstone, Parent = folder })
	for i = -2, 2 do
		for _, sz in ipairs({ -8, 8 }) do
			local h = if (i + sz) % 3 == 0 then rng:NextNumber(4, 8) else rng:NextNumber(12, 18)
			column(folder, o + Vector3.new(i * 8, 0.6, sz), h, stone, Enum.Material.Sandstone)
		end
	end
	deco({ Name = "Lintel", Size = Vector3.new(26, 2, 4.4), Position = o + Vector3.new(4, 20.2, 8), Color = stone, Material = Enum.Material.Sandstone, Parent = folder })
	deco({ Name = "FallenColumn", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 3.2, 3.2), CFrame = CFrame.new(o + Vector3.new(-4, 2.2, 0)) * CFrame.Angles(0, math.rad(20), 0), Color = stone, Material = Enum.Material.Sandstone, Parent = folder })
	local idol = deco({ Name = "GoldenIdol", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2.6, 2), Position = o + Vector3.new(0, 3.2, 0), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Foil, Parent = folder })
	deco({ Name = "IdolPedestal", Size = Vector3.new(3, 1.6, 3), Position = o + Vector3.new(0, 1.4, 0), Color = stone, Material = Enum.Material.Sandstone, Parent = folder })
	light(idol, Color3.fromRGB(255, 210, 110), 14, 1)
end

function SETPIECES.Cabin(folder, o, rng)
	local cf = CFrame.lookAt(o, o + Vector3.new(if o.X < 0 then 1 else -1, 0, 0))
	house(folder, cf, 18, 10, 14, { Wall = Color3.fromRGB(130, 85, 55), WallMaterial = Enum.Material.WoodPlanks, Trim = Color3.fromRGB(80, 55, 38), Roof = Color3.fromRGB(245, 250, 255), RoofMaterial = Enum.Material.Snow })
	for i = -3, 3 do
		deco({ Name = "Icicle", Size = Vector3.new(0.4, 1.2 + (i % 2) * 0.8, 0.4), CFrame = cf * CFrame.new(i * 2.6, 9.4 - (i % 2) * 0.4, -8), Color = Color3.fromRGB(200, 235, 255), Material = Enum.Material.Glass, Transparency = 0.2, Parent = folder })
	end
	for i = 0, 5 do
		deco({ Name = "WoodPile", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 1.1, 1.1), CFrame = cf * CFrame.new(-12, 0.6 + (i // 3) * 1, -2 + (i % 3) * 1.1) * CFrame.Angles(0, math.rad(90), 0), Color = WOOD, Material = Enum.Material.Wood, Parent = folder })
	end
	PROPS.Snowman(folder, (cf * CFrame.new(9, 0, -12)).Position, 0.9)
	deco({ Name = "Sled", Size = Vector3.new(2.4, 0.6, 5), CFrame = cf * CFrame.new(-6, 0.5, -11) * CFrame.Angles(0, 0.3, 0), Color = Color3.fromRGB(200, 50, 50), Material = Enum.Material.Wood, Parent = folder })
end

function SETPIECES.IceFalls(folder, o, rng)
	local rockColor = Color3.fromRGB(110, 120, 140)
	for i = 0, 3 do
		local c = deco({ Name = "Cliff", Size = Vector3.new(26 - i * 4, 12, 22 - i * 3), Position = o + Vector3.new(30 - i * 2, 6 + i * 11, 0), Color = rockColor:Lerp(BLACK, i * 0.04), Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "SnowCap", Size = Vector3.new(c.Size.X * 0.95, 1, c.Size.Z * 0.95), Position = c.Position + Vector3.new(0, 6.3, 0), Color = WHITE, Material = Enum.Material.Snow, Parent = folder })
	end
	for i = -2, 2 do
		deco({ Name = "FrozenFall", Size = Vector3.new(1.5, 40 - math.abs(i) * 6, 2.6), Position = o + Vector3.new(17, 20 - math.abs(i) * 3, i * 2.5), Color = Color3.fromRGB(180, 230, 255), Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.3, CastShadow = false, Parent = folder })
	end
	deco({ Name = "FrozenPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 30, 30), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.25, 0))), Color = Color3.fromRGB(175, 220, 250), Material = Enum.Material.Glass, Transparency = 0.1, Reflectance = 0.4, Parent = folder })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local h = rng:NextNumber(5, 12)
		deco({ Name = "IceSpike", Size = Vector3.new(1.6, h, 1.6), CFrame = CFrame.new(o + Vector3.new(math.cos(a) * 17, h / 2 - 0.5, math.sin(a) * 17)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(170, 225, 255), Material = Enum.Material.Glass, Transparency = 0.15, Parent = folder })
	end
	local glow = deco({ Name = "IceGlow", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = o + Vector3.new(0, 1, 0), Color = Color3.fromRGB(150, 220, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(glow, Color3.fromRGB(150, 220, 255), 28, 1.2)
end

function SETPIECES.SnowFort(folder, o, rng)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		if i ~= 4 and i ~= 12 then
			for layer = 0, 1 do
				deco({ Name = "SnowBlock", Size = Vector3.new(5, 3, 3), CFrame = CFrame.new(o + Vector3.new(math.cos(a) * 14, 1.5 + layer * 3, math.sin(a) * 14)) * CFrame.Angles(0, -a + math.pi / 2 + layer * 0.1, 0), Color = Color3.fromRGB(240 - layer * 8, 246, 255), Material = Enum.Material.Snow, Parent = folder })
			end
		end
	end
	deco({ Name = "FlagPole", Size = Vector3.new(0.4, 14, 0.4), Position = o + Vector3.new(0, 7, 0), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "Flag", Size = Vector3.new(0.2, 3, 5), Position = o + Vector3.new(0, 12.4, 2.6), Color = Color3.fromRGB(80, 150, 255), Material = Enum.Material.Fabric, Parent = folder })
	for i = 0, 9 do
		deco({ Name = "Snowball", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, Position = o + Vector3.new(4 + (i % 4) * 1.1 - (i // 4) * 0.5, 0.6 + (i // 4) * 0.9, -4), Color = WHITE, Material = Enum.Material.Snow, Parent = folder })
	end
end

function SETPIECES.SledHill(folder, o, rng)
	for i = 0, 4 do
		deco({ Name = "Hill", Size = Vector3.new(34 - i * 6, 4, 30 - i * 5), CFrame = CFrame.new(o + Vector3.new(i * 1.5, 2 + i * 4, 0)) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0), Color = Color3.fromRGB(245 - i * 3, 250, 255), Material = Enum.Material.Snow, Parent = folder })
	end
	deco({ Name = "SledTrack", Size = Vector3.new(3, 0.3, 26), CFrame = CFrame.new(o + Vector3.new(-6, 9, -6)) * CFrame.Angles(math.rad(-30), 0, 0), Color = Color3.fromRGB(215, 230, 250), Material = Enum.Material.Ice, Parent = folder })
	for i = 0, 2 do
		PROPS.Pine(folder, o + Vector3.new(14, 0, -12 + i * 12), 0.8)
	end
	for i = 0, 4 do
		local post = o + Vector3.new(-16 + i * 7, 0, -16)
		deco({ Name = "FencePost", Size = Vector3.new(0.6, 3, 0.6), Position = post + Vector3.new(0, 1.5, 0), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
		lantern(folder, post + Vector3.new(0, 3.4, 0), Color3.fromRGB(255, 220, 150), 10)
	end
end

function SETPIECES.Basalt(folder, o, rng)
	for i = 1, 22 do
		local a = i * 2.4
		local r = math.sqrt(i) * 5
		local h = rng:NextNumber(4, 22) * (1 - r / 40)
		local p = o + Vector3.new(math.cos(a) * r, h / 2, math.sin(a) * r)
		deco({ Name = "BasaltColumn", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 4.4, 4.4), CFrame = cylinderAlongY(CFrame.new(p)), Color = Color3.fromRGB(48 + (i % 3) * 6, 42, 44), Material = Enum.Material.Basalt, Parent = folder })
		if i % 4 == 0 then
			deco({ Name = "LavaSeam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.6, 4.6), CFrame = cylinderAlongY(CFrame.new(p - Vector3.new(0, h / 2 - 1, 0))), Color = Color3.fromRGB(255, 110, 30), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		end
	end
end

function SETPIECES.LavaLake(folder, o, rng)
	deco({ Name = "LakeRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 58, 58), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.5, 0))), Color = Color3.fromRGB(40, 32, 32), Material = Enum.Material.Basalt, Parent = folder })
	local lava = deco({ Name = "LavaLake", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 52, 52), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.55, 0))), Color = Color3.fromRGB(255, 100, 20), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	light(lava, Color3.fromRGB(255, 110, 40), 50, 2.5)
	particles(lava, { Color = ColorSequence.new(Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 70, 20)), LightEmission = 1, Size = NumberSequence.new(0.6, 0), Lifetime = NumberRange.new(1, 2), Rate = 25, Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(20, 20), Acceleration = Vector3.new(0, -12, 0), EmissionDirection = Enum.NormalId.Top })
	-- rope bridge across the lake
	for z = -27, 27, 2 do
		deco({ Name = "Plank", Size = Vector3.new(5, 0.4, 1.6), CFrame = CFrame.new(o + Vector3.new(0, 2.4 - math.cos(z / 27 * math.pi / 2) * 1.2, z)) * CFrame.Angles(0, rng:NextNumber(-0.05, 0.05), 0), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = folder })
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			deco({ Name = "BridgePost", Size = Vector3.new(0.8, 6, 0.8), Position = o + Vector3.new(sx * 2.8, 3, sz * 28), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
		end
		deco({ Name = "BridgeRope", Size = Vector3.new(0.25, 0.25, 56), Position = o + Vector3.new(sx * 2.8, 4.6, 0), Color = Color3.fromRGB(200, 170, 120), Material = Enum.Material.Fabric, Parent = folder })
	end
	for _ = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		rock(folder, o + Vector3.new(math.cos(a) * rng:NextNumber(8, 20), 0, math.sin(a) * rng:NextNumber(8, 20)), 0.5, rng, Color3.fromRGB(45, 38, 38), Enum.Material.Basalt)
	end
end

function SETPIECES.Forge(folder, o, rng)
	local wall = Color3.fromRGB(70, 60, 60)
	for _, w in ipairs({ { -10, 0, 1, 20, 12 }, { 10, 0, 1, 20, 7 }, { 0, 10, 20, 1, 9 } }) do
		deco({ Name = "RuinWall", Size = Vector3.new(w[3] * 2 + 1, w[5], w[4]), Position = o + Vector3.new(w[1], w[5] / 2, w[2]), Color = wall, Material = Enum.Material.Brick, Parent = folder })
	end
	deco({ Name = "AnvilBase", Size = Vector3.new(2, 2.4, 1.6), Position = o + Vector3.new(0, 1.2, -2), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "Anvil", Size = Vector3.new(4.4, 1.4, 2), Position = o + Vector3.new(0, 3.1, -2), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal, Parent = folder })
	local blade = deco({ Name = "HotBlade", Size = Vector3.new(0.3, 0.2, 4), Position = o + Vector3.new(0.5, 3.9, -2), Color = Color3.fromRGB(255, 160, 60), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	particles(blade, { Color = ColorSequence.new(Color3.fromRGB(255, 200, 80)), LightEmission = 1, Size = NumberSequence.new(0.2, 0), Lifetime = NumberRange.new(0.4, 0.8), Rate = 12, Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, -20, 0) })
	local furnace = deco({ Name = "Furnace", Size = Vector3.new(7, 8, 6), Position = o + Vector3.new(-5, 4, 6), Color = wall:Lerp(BLACK, 0.2), Material = Enum.Material.Brick, Parent = folder })
	local mouth = deco({ Name = "FurnaceFire", Size = Vector3.new(3.4, 2.6, 0.4), Position = furnace.Position + Vector3.new(0, -1.5, -3), Color = Color3.fromRGB(255, 120, 30), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(mouth, Color3.fromRGB(255, 130, 50), 24, 2)
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(60, 55, 55)
	smoke.Size = 6
	smoke.Opacity = 0.25
	smoke.RiseVelocity = 6
	smoke.Parent = furnace
	for i = 0, 3 do
		deco({ Name = "Chain", Size = Vector3.new(0.3, 5, 0.3), Position = o + Vector3.new(-6 + i * 4, 9.5, 9.5), Color = Color3.fromRGB(80, 80, 85), Material = Enum.Material.Metal, Parent = folder })
	end
	PROPS.Torch(folder, o + Vector3.new(8, 0, -8))
end

function SETPIECES.Geysers(folder, o, rng)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		local p = o + Vector3.new(math.cos(a) * 10, 0, math.sin(a) * 10)
		for k = 0, 2 do
			deco({ Name = "Vent", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 7 - k * 2, 7 - k * 2), CFrame = cylinderAlongY(CFrame.new(p + Vector3.new(0, 0.7 + k * 1.4, 0))), Color = Color3.fromRGB(70 - k * 8, 55, 50), Material = Enum.Material.Basalt, Parent = folder })
		end
		local hole = deco({ Name = "VentGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.4, 2.4), CFrame = cylinderAlongY(CFrame.new(p + Vector3.new(0, 4.3, 0))), Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		particles(hole, { Color = ColorSequence.new(Color3.fromRGB(255, 200, 100), Color3.fromRGB(120, 100, 100)), LightEmission = 0.5, Size = NumberSequence.new(1, 4), Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(1.5, 2.5), Rate = 20, Speed = NumberRange.new(18, 26), SpreadAngle = Vector2.new(8, 8), EmissionDirection = Enum.NormalId.Top })
	end
end

function SETPIECES.RuneCircle(folder, o, rng)
	local purple = Color3.fromRGB(190, 120, 255)
	for i, r in ipairs({ 30, 24, 14 }) do
		deco({ Name = "RuneRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, r, r), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.12 + i * 0.02, 0))), Color = if i == 2 then Color3.fromRGB(45, 30, 80) else purple, Material = if i == 2 then Enum.Material.Slate else Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local p = o + Vector3.new(math.cos(a) * 19, 0, math.sin(a) * 19)
		deco({ Name = "StandingStone", Size = Vector3.new(3, 12, 2), CFrame = CFrame.lookAt(p + Vector3.new(0, 6, 0), o + Vector3.new(0, 6, 0)), Color = Color3.fromRGB(40, 32, 60), Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "StoneRune", Size = Vector3.new(0.8, 6, 0.2), CFrame = CFrame.lookAt(p + Vector3.new(0, 6, 0), o + Vector3.new(0, 6, 0)) * CFrame.new(0, 0, -1.05), Color = purple, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	local core = deco({ Name = "FloatingCore", Size = Vector3.new(3, 5, 3), CFrame = CFrame.new(o + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(220, 170, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(core, purple, 34, 2)
	particles(core, { Color = ColorSequence.new(purple, Color3.fromRGB(120, 200, 255)), LightEmission = 1, Size = NumberSequence.new(0.4, 0), Lifetime = NumberRange.new(2, 3), Rate = 20, Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180) })
end

function SETPIECES.SkyStairs(folder, o, rng)
	for i = 0, 15 do
		local a = i * 0.45
		local p = o + Vector3.new(math.cos(a) * 10, 1 + i * 2.2, math.sin(a) * 10)
		deco({ Name = "FloatingStep", Size = Vector3.new(6, 1, 3.4), CFrame = CFrame.new(p) * CFrame.Angles(0, -a, 0), Color = Color3.fromRGB(60, 45, 95), Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "StepGlow", Size = Vector3.new(6.2, 0.2, 0.3), CFrame = CFrame.new(p) * CFrame.Angles(0, -a, 0) * CFrame.new(0, -0.5, -1.6), Color = Color3.fromRGB(150, 200, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	local top = o + Vector3.new(math.cos(16 * 0.45) * 10, 37, math.sin(16 * 0.45) * 10)
	deco({ Name = "TopPlatform", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 12, 12), CFrame = cylinderAlongY(CFrame.new(top)), Color = Color3.fromRGB(50, 40, 80), Material = Enum.Material.Slate, Parent = folder })
	local star = deco({ Name = "StarCrystal", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(top + Vector3.new(0, 3.5, 0)) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color = Color3.fromRGB(255, 240, 150), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(star, Color3.fromRGB(255, 230, 150), 30, 1.5)
end

function SETPIECES.Portal(folder, o, rng)
	local stone = Color3.fromRGB(45, 35, 75)
	local face = CFrame.lookAt(o, o + Vector3.new(if o.X < 0 then 1 else -1, 0, 0))
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "PortalPillar", Size = Vector3.new(3.6, 22, 3.6), CFrame = face * CFrame.new(sx * 9, 11, 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "PillarRune", Size = Vector3.new(0.8, 16, 0.2), CFrame = face * CFrame.new(sx * 9, 11, -1.85), Color = Color3.fromRGB(120, 220, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	deco({ Name = "PortalTop", Size = Vector3.new(24, 3.6, 4.4), CFrame = face * CFrame.new(0, 23.8, 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
	local gate = deco({ Name = "PortalField", Size = Vector3.new(14.4, 20, 0.4), CFrame = face * CFrame.new(0, 11, 0), Color = Color3.fromRGB(170, 100, 255), Material = Enum.Material.ForceField, CanCollide = false, CastShadow = false, Parent = folder })
	gate.Transparency = 0.1
	light(gate, Color3.fromRGB(170, 100, 255), 30, 2)
	particles(gate, { Color = ColorSequence.new(Color3.fromRGB(200, 150, 255), Color3.fromRGB(120, 220, 255)), LightEmission = 1, Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(1, 2), Rate = 30, Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180) })
end

function SETPIECES.Observatory(folder, o, rng)
	deco({ Name = "ObsBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 20, 20), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 5, 0))), Color = Color3.fromRGB(70, 60, 100), Material = Enum.Material.Slate, Parent = folder })
	local dome = deco({ Name = "ObsDome", Shape = Enum.PartType.Ball, Size = Vector3.one * 19, Position = o + Vector3.new(0, 10, 0), Color = Color3.fromRGB(200, 205, 230), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "DomeSlit", Size = Vector3.new(3, 10, 19.4), Position = o + Vector3.new(0, 15, 0), Color = Color3.fromRGB(30, 25, 50), Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "Telescope", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 2.4, 2.4), CFrame = CFrame.new(o + Vector3.new(0, 20, 3)) * CFrame.Angles(0, math.rad(90), math.rad(50)), Color = Color3.fromRGB(230, 190, 90), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "ObsDoor", Size = Vector3.new(4, 6, 0.4), Position = o + Vector3.new(0, 3, -10), Color = Color3.fromRGB(40, 30, 60), Material = Enum.Material.Wood, Parent = folder })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		lantern(folder, o + Vector3.new(math.cos(a) * 11, 10.4, math.sin(a) * 11), Color3.fromRGB(190, 150, 255), 8)
	end
	light(dome, Color3.fromRGB(200, 170, 255), 20, 0.8)
end

--------------------------------------------------------------------------------
-- Details on the inside of the zone walls
--------------------------------------------------------------------------------
local WALL_TRIMS = {}
function WALL_TRIMS.Forest(folder, x, z, side, rng)
	for k = -1, 1 do
		local len = rng:NextNumber(6, 16)
		deco({ Name = "Vine", Size = Vector3.new(0.4, len, 1), Position = Vector3.new(x, WALL_HEIGHT - len / 2, z + k * 2), Color = LEAF_GREENS[rng:NextInteger(1, #LEAF_GREENS)], Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = folder })
		if rng:NextNumber() < 0.4 then
			deco({ Name = "VineFlower", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Position = Vector3.new(x - side * 0.3, WALL_HEIGHT - len + 0.5, z + k * 2), Color = ({ Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 230, 90) })[rng:NextInteger(1, 2)], Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
		end
	end
end
function WALL_TRIMS.Desert(folder, x, z, side, rng)
	local carve = Color3.fromRGB(180, 130, 80)
	deco({ Name = "Carving", Size = Vector3.new(0.3, 6, 6), Position = Vector3.new(x, 8, z), Color = carve, Material = Enum.Material.Sandstone, CanCollide = false, Parent = folder })
	deco({ Name = "CarvingEye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 1.6, 3), Position = Vector3.new(x - side * 0.1, 8.4, z), Color = Color3.fromRGB(60, 150, 170), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
end
function WALL_TRIMS.Snow(folder, x, z, side, rng)
	deco({ Name = "SnowLedge", Size = Vector3.new(1.4, 1, 14), Position = Vector3.new(x, WALL_HEIGHT - 0.3, z), Color = WHITE, Material = Enum.Material.Snow, CanCollide = false, Parent = folder })
	for k = -2, 2 do
		local len = rng:NextNumber(1.5, 4)
		deco({ Name = "Icicle", Size = Vector3.new(0.5, len, 0.5), Position = Vector3.new(x, WALL_HEIGHT - 0.8 - len / 2, z + k * 2.6), Color = Color3.fromRGB(200, 235, 255), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, CastShadow = false, Parent = folder })
	end
end
function WALL_TRIMS.Volcano(folder, x, z, side, rng)
	local y = rng:NextNumber(10, 30)
	for k = 0, 3 do
		deco({ Name = "LavaCrack", Size = Vector3.new(0.3, 4.5, 0.6), CFrame = CFrame.new(x, y - k * 4, z + (k % 2) * 1.2) * CFrame.Angles(if k % 2 == 0 then 0.35 else -0.35, 0, 0), Color = Color3.fromRGB(255, 110, 30), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	end
end
function WALL_TRIMS.Void(folder, x, z, side, rng)
	for k = 0, 2 do
		deco({ Name = "WallRune", Size = Vector3.new(0.3, 2.4, 0.6), Position = Vector3.new(x, 14 + k * 3.2, z + (k - 1) * 1.2), Color = Color3.fromRGB(170, 120, 255):Lerp(Color3.fromRGB(120, 220, 255), k / 2), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	end
	deco({ Name = "WallStar", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, Position = Vector3.new(x, rng:NextNumber(25, 36), z + rng:NextNumber(-6, 6)), Color = WHITE, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
end

local function wallTrims(folder, id, zMin, zMax, rng)
	local fn = WALL_TRIMS[id]
	if not fn then
		return
	end
	local trims = Instance.new("Folder")
	trims.Name = "WallDetail"
	trims.Parent = folder
	for z = zMin + 12, zMax - 8, 16 do
		for _, side in ipairs({ -1, 1 }) do
			fn(trims, side * (CORRIDOR_HALF - 0.35), z, side, rng)
		end
	end
end

--------------------------------------------------------------------------------
-- Scenery beyond the walls: mountains, mesas, peaks and floating rocks, so the
-- world doesn't end at the wall. Also sky pieces (aurora, planets).
--------------------------------------------------------------------------------
local BACKDROPS = {
	Town = { Base = Color3.fromRGB(96, 165, 78), Top = Color3.fromRGB(130, 195, 95), Material = Enum.Material.Grass, MinH = 50, MaxH = 95 },
	Forest = { Base = Color3.fromRGB(60, 120, 62), Top = Color3.fromRGB(85, 150, 75), Material = Enum.Material.Grass, MinH = 70, MaxH = 130, Trees = true },
	Desert = { Base = Color3.fromRGB(195, 115, 75), Top = Color3.fromRGB(225, 160, 105), Material = Enum.Material.Sandstone, MinH = 55, MaxH = 110, Flat = true },
	Snow = { Base = Color3.fromRGB(115, 125, 145), Top = Color3.fromRGB(250, 252, 255), Material = Enum.Material.Slate, MinH = 90, MaxH = 170, Cap = Enum.Material.Snow },
	Volcano = { Base = Color3.fromRGB(45, 34, 34), Top = Color3.fromRGB(70, 48, 44), Material = Enum.Material.Basalt, MinH = 80, MaxH = 150, Lava = true },
	Void = { Base = Color3.fromRGB(45, 34, 72), Top = Color3.fromRGB(80, 60, 120), Material = Enum.Material.Slate, MinH = 40, MaxH = 90, Floating = true },
}

local function mountain(folder, pos, width, height, style, rng)
	local steps = 5
	local top
	for i = 0, steps - 1 do
		local f = 1 - i / steps
		local w = width * (if style.Flat then (1 - i * 0.06) else f)
		local h = height / steps
		local p = pos + Vector3.new(rng:NextNumber(-2, 2), h * (i + 0.5), rng:NextNumber(-2, 2))
		local isTop = i == steps - 1
		deco({ Name = "Mountain", Size = Vector3.new(w, h + 0.5, w * rng:NextNumber(0.8, 1.1)), CFrame = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 0.4), 0), Color = style.Base:Lerp(style.Top, i / (steps - 1)), Material = if isTop and style.Cap then style.Cap else style.Material, CastShadow = false, Parent = folder })
		top = p + Vector3.new(0, h / 2, 0)
	end
	if style.Lava and rng:NextNumber() < 0.5 then
		local crater = deco({ Name = "MountainLava", Size = Vector3.new(width * 0.15, 1, width * 0.15), Position = top + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(255, 110, 30), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(60, 50, 50)
		smoke.Size = 30
		smoke.Opacity = 0.15
		smoke.RiseVelocity = 10
		smoke.Parent = crater
	end
	if style.Trees then
		for _ = 1, 3 do
			local p = top + Vector3.new(rng:NextNumber(-width * 0.12, width * 0.12), 0, rng:NextNumber(-width * 0.12, width * 0.12))
			deco({ Name = "PeakTree", Size = Vector3.new(7, 12, 7), Position = p + Vector3.new(0, 6, 0), Color = LEAF_GREENS[rng:NextInteger(1, #LEAF_GREENS)], Material = Enum.Material.Grass, CastShadow = false, Parent = folder })
		end
	end
end

local function backdrop(folder, id, xHalf, zMin, zMax, rng, ends)
	local style = BACKDROPS[id]
	if not style then
		return
	end
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = folder
	for _, side in ipairs({ -1, 1 }) do
		local z = zMin
		while z < zMax do
			local width = rng:NextNumber(50, 90)
			local x = side * (xHalf + 40 + rng:NextNumber(0, 70))
			local base = if style.Floating then rng:NextNumber(20, 60) else 0
			mountain(scenery, Vector3.new(x, base, z + width / 2), width, rng:NextNumber(style.MinH, style.MaxH), style, rng)
			if style.Floating then
				deco({ Name = "FloatingUnderside", Size = Vector3.new(width * 0.6, base * 0.6, width * 0.6), Position = Vector3.new(x, base - base * 0.3, z + width / 2), Color = style.Base:Lerp(BLACK, 0.2), Material = style.Material, CastShadow = false, Parent = scenery })
			end
			z += width * 0.75
		end
	end
	for _, endZ in ipairs(ends or {}) do
		for x = -xHalf, xHalf, 90 do
			mountain(scenery, Vector3.new(x + rng:NextNumber(-10, 10), 0, endZ.Z + endZ.Dir * (50 + rng:NextNumber(0, 50))), rng:NextNumber(70, 110), rng:NextNumber(style.MinH, style.MaxH), style, rng)
		end
	end
end

local SKY = {}
function SKY.Snow(folder, centerZ, rng)
	-- aurora: soft glowing ribbons high above the zone
	local colors = { Color3.fromRGB(90, 255, 170), Color3.fromRGB(80, 220, 255), Color3.fromRGB(190, 120, 255) }
	for band = 0, 2 do
		for i = 0, 11 do
			local x = -CORRIDOR_HALF + i * (CORRIDOR_HALF * 2 / 11)
			local p = Vector3.new(x, 150 + band * 14 + math.sin(i * 0.8 + band) * 10, centerZ + 60 - band * 50 + math.cos(i * 0.6) * 25)
			local ribbon = deco({ Name = "Aurora", Size = Vector3.new(CORRIDOR_HALF * 2 / 11 + 8, 26, 1), CFrame = CFrame.new(p) * CFrame.Angles(0, math.sin(i) * 0.3, 0), Color = colors[band + 1], Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
			ribbon.Transparency = 0.72
		end
	end
end
function SKY.Void(folder, centerZ, rng)
	local planet = deco({ Name = "Planet", Shape = Enum.PartType.Ball, Size = Vector3.one * 140, Position = Vector3.new(-CORRIDOR_HALF - 220, 230, centerZ + 40), Color = Color3.fromRGB(120, 80, 200), Material = Enum.Material.SmoothPlastic, CastShadow = false, Parent = folder })
	deco({ Name = "PlanetRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 250, 250), CFrame = CFrame.new(planet.Position) * CFrame.Angles(math.rad(70), 0, math.rad(20)), Color = Color3.fromRGB(230, 180, 255), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Transparency = 0.5, Parent = folder })
	deco({ Name = "Moon", Shape = Enum.PartType.Ball, Size = Vector3.one * 70, Position = Vector3.new(CORRIDOR_HALF + 180, 260, centerZ - 60), Color = Color3.fromRGB(200, 220, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder }).Transparency = 0.1
	for i = 1, 5 do
		deco({ Name = "Nebula", Shape = Enum.PartType.Ball, Size = Vector3.new(rng:NextNumber(120, 200), rng:NextNumber(40, 70), rng:NextNumber(80, 140)), Position = Vector3.new(rng:NextNumber(-CORRIDOR_HALF, CORRIDOR_HALF), rng:NextNumber(180, 240), centerZ + rng:NextNumber(-130, 130)), Color = ({ Color3.fromRGB(255, 100, 200), Color3.fromRGB(110, 140, 255), Color3.fromRGB(170, 90, 255) })[(i % 3) + 1], Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Transparency = 0.88, Parent = folder })
	end
end

--------------------------------------------------------------------------------
-- Town extras: a cobbled main street with string lights, and cottages
--------------------------------------------------------------------------------
local function stringLights(folder, a, b, rng)
	local colors = { Color3.fromRGB(255, 220, 130), Color3.fromRGB(255, 130, 160), Color3.fromRGB(140, 200, 255), Color3.fromRGB(170, 255, 150) }
	local bulbs = 11
	for i = 0, bulbs do
		local t = i / bulbs
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * 2.5, 0)
		local bulb = deco({ Name = "StringBulb", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, Position = p, Color = colors[(i % #colors) + 1], Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		if i == bulbs // 2 then
			light(bulb, WARM_LIGHT, 20, 0.8)
		end
		if i < bulbs then
			local q = a:Lerp(b, (i + 1) / bulbs) - Vector3.new(0, math.sin((i + 1) / bulbs * math.pi) * 2.5, 0)
			deco({ Name = "Wire", Size = Vector3.new(0.1, 0.1, (q - p).Magnitude), CFrame = CFrame.lookAt((p + q) / 2, q), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.SmoothPlastic, CastShadow = false, Parent = folder })
		end
	end
end

local function buildTownExtras(folder, rng)
	local extras = Instance.new("Folder")
	extras.Name = "TownDetail"
	extras.Parent = folder
	-- Main street from the bases to the safe line
	local z1, z2 = PLOT_SIZE / 2 + 4, TOWN_END_Z - 44
	local mid, len = (z1 + z2) / 2, z2 - z1
	deco({ Name = "MainStreet", Size = Vector3.new(30, 0.12, len), Position = Vector3.new(0, 0.07, mid), Color = Color3.fromRGB(175, 165, 150), Material = Enum.Material.Cobblestone, CanCollide = false, CastShadow = false, Parent = extras })
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "Curb", Size = Vector3.new(1.2, 0.5, len), Position = Vector3.new(sx * 15.6, 0.25, mid), Color = Color3.fromRGB(210, 205, 195), Material = Enum.Material.Concrete, CanCollide = false, Parent = extras })
	end
	-- String lights across the street
	for z = z1 + 16, z2 - 4, 36 do
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "LightPole", Size = Vector3.new(0.6, 15, 0.6), Position = Vector3.new(sx * 17, 7.5, z), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = extras })
		end
		stringLights(extras, Vector3.new(-17, 14.5, z), Vector3.new(17, 14.5, z), rng)
	end
	-- Bunting between the title board posts
	for i = 0, 10 do
		local x = -22 + i * 4.4
		deco({ Name = "Bunting", Size = Vector3.new(2.6, 2.6, 0.2), CFrame = CFrame.new(x, 36 - math.sin(i / 10 * math.pi) * 3, TOWN_START_Z + 6.5) * CFrame.Angles(0, 0, math.rad(45)), Color = PLOT_ACCENTS[(i % #PLOT_ACCENTS) + 1], Material = Enum.Material.Fabric, CanCollide = false, Parent = extras })
	end
	-- Cottages along the side walls, facing into town
	for _, side in ipairs({ -1, 1 }) do
		for i, z in ipairs({ 90, 150, 205 }) do
			local pos = Vector3.new(side * (TOWN_HALF - 38), 0, z)
			local cf = CFrame.lookAt(pos, pos + Vector3.new(-side, 0, 0))
			local roofs = { Color3.fromRGB(190, 70, 60), Color3.fromRGB(70, 110, 190), Color3.fromRGB(90, 150, 90) }
			local walls = { Color3.fromRGB(245, 230, 205), Color3.fromRGB(250, 215, 200), Color3.fromRGB(225, 235, 245) }
			house(extras, cf, 16, 10, 14, { Wall = walls[i], Roof = roofs[(i + (if side > 0 then 1 else 0)) % 3 + 1] })
			-- picket fence and a mailbox in front
			for k = -4, 4 do
				deco({ Name = "Picket", Size = Vector3.new(0.5, 2.4, 0.3), CFrame = cf * CFrame.new(k * 2, 1.2, -13), Color = WHITE, Material = Enum.Material.WoodPlanks, Parent = extras })
			end
			deco({ Name = "FenceRail", Size = Vector3.new(17, 0.4, 0.3), CFrame = cf * CFrame.new(0, 1.6, -13), Color = WHITE, Material = Enum.Material.WoodPlanks, Parent = extras })
			deco({ Name = "MailPost", Size = Vector3.new(0.4, 3, 0.4), CFrame = cf * CFrame.new(10, 1.5, -12), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = extras })
			deco({ Name = "Mailbox", Size = Vector3.new(1.2, 1, 2), CFrame = cf * CFrame.new(10, 3.3, -12), Color = PLOT_ACCENTS[i], Material = Enum.Material.Metal, Parent = extras })
		end
	end
	-- Picnic tables on the lawn between bases and street
	for _, x in ipairs({ -250, 250 }) do
		local p = Vector3.new(x, 0, 175)
		deco({ Name = "PicnicTop", Size = Vector3.new(8, 0.4, 3.6), Position = p + Vector3.new(0, 2.6, 0), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = extras })
		for _, sz in ipairs({ -2.6, 2.6 }) do
			deco({ Name = "PicnicBench", Size = Vector3.new(8, 0.3, 1.2), Position = p + Vector3.new(0, 1.5, sz), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = extras })
		end
		for _, sx in ipairs({ -3.4, 3.4 }) do
			deco({ Name = "PicnicLeg", Size = Vector3.new(0.4, 2.6, 5.8), Position = p + Vector3.new(sx, 1.3, 0), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = extras })
		end
		deco({ Name = "Umbrella", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 9, 9), CFrame = cylinderAlongY(CFrame.new(p + Vector3.new(0, 7.5, 0))), Color = Color3.fromRGB(240, 90, 90), Material = Enum.Material.Fabric, Parent = extras })
		deco({ Name = "UmbrellaPole", Size = Vector3.new(0.3, 7.5, 0.3), Position = p + Vector3.new(0, 3.75, 0), Color = WHITE, Material = Enum.Material.Metal, Parent = extras })
	end
	backdrop(folder, "Town", TOWN_HALF, TOWN_START_Z - 60, TOWN_END_Z, rng, { { Z = TOWN_START_Z, Dir = -1 } })
end

--------------------------------------------------------------------------------
-- Candy Kingdom, Sunken Reef and Celestial Heights
--------------------------------------------------------------------------------
local CANDY = { Color3.fromRGB(255, 90, 170), Color3.fromRGB(255, 220, 70), Color3.fromRGB(110, 220, 255), Color3.fromRGB(140, 230, 120), Color3.fromRGB(190, 130, 255) }
local CORAL = { Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 170, 80), Color3.fromRGB(160, 110, 255), Color3.fromRGB(255, 90, 90) }
local HEAVEN_GOLD = Color3.fromRGB(255, 210, 100)

function PROPS.Lollipop(folder, pos, s, rng)
	local h = rng:NextNumber(8, 13) * s
	deco({ Name = "Stick", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 0.8 * s, 0.8 * s), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, h / 2, 0))), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = folder })
	local center = CFrame.new(pos + Vector3.new(0, h + 2.6 * s, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local col = CANDY[rng:NextInteger(1, #CANDY)]
	deco({ Name = "Candy", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9 * s, 6 * s, 6 * s), CFrame = center * CFrame.Angles(0, math.rad(90), 0), Color = col, Material = Enum.Material.SmoothPlastic, Parent = folder })
	for i = 0, 11 do
		local a = i * 0.9
		local r = (0.4 + i * 0.22) * s
		deco({ Name = "Swirl", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7 * s, CFrame = center * CFrame.new(math.cos(a) * r, math.sin(a) * r, -0.45 * s), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	deco({ Name = "Bow", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 1, 1) * s, Position = pos + Vector3.new(0, h - 0.5, 0), Color = CANDY[rng:NextInteger(1, #CANDY)], Material = Enum.Material.SmoothPlastic, Parent = folder })
end

function PROPS.CandyCane(folder, pos, s, rng)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	for i = 0, 7 do
		deco({ Name = "Cane", Size = Vector3.new(1.4, 1.6, 1.4) * s, CFrame = base * CFrame.new(0, (0.8 + i * 1.6) * s, 0), Color = if i % 2 == 0 then Color3.fromRGB(230, 40, 60) else WHITE, Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	for i = 1, 5 do
		local a = i / 5 * math.pi
		deco({ Name = "CaneHook", Size = Vector3.new(1.4, 1.5, 1.4) * s, CFrame = base * CFrame.new((1 - math.cos(a)) * 1.6 * s, (12.8 + math.sin(a) * 1.8) * s, 0) * CFrame.Angles(0, 0, -a), Color = if i % 2 == 0 then Color3.fromRGB(230, 40, 60) else WHITE, Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
end

function PROPS.Gumdrop(folder, pos, s, rng)
	for i = 1, 3 do
		local size = rng:NextNumber(2.5, 4.5) * s
		local p = pos + Vector3.new(rng:NextNumber(-3, 3), size * 0.3, rng:NextNumber(-3, 3))
		local drop = deco({ Name = "Gumdrop", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size * 1.1, size), Position = p, Color = CANDY[rng:NextInteger(1, #CANDY)], Material = Enum.Material.Glass, Transparency = 0.1, Parent = folder })
		for k = 1, 4 do
			deco({ Name = "Sugar", Size = Vector3.one * 0.25 * s, Position = drop.Position + Vector3.new(rng:NextNumber(-0.4, 0.4), 0.45, rng:NextNumber(-0.4, 0.4)) * size, Color = WHITE, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		end
	end
end

function PROPS.CottonCandyTree(folder, pos, s, rng)
	local trunkH = rng:NextNumber(7, 10) * s
	deco({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(trunkH, 1.2 * s, 1.2 * s), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, trunkH / 2, 0))), Color = Color3.fromRGB(245, 235, 220), Material = Enum.Material.SmoothPlastic, Parent = folder })
	local fluff = ({ Color3.fromRGB(255, 180, 220), Color3.fromRGB(180, 210, 255), Color3.fromRGB(230, 190, 255) })[rng:NextInteger(1, 3)]
	for i = 1, 7 do
		local a = i * 2.3
		deco({ Name = "CottonCandy", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(4, 6.5) * s, Position = pos + Vector3.new(math.cos(a) * 2.4 * s, trunkH + rng:NextNumber(0, 4) * s, math.sin(a) * 2.4 * s), Color = fluff:Lerp(WHITE, rng:NextNumber(0, 0.25)), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
end

function PROPS.Coral(folder, pos, s, rng)
	local col = CORAL[rng:NextInteger(1, #CORAL)]
	local function branch(from, dir, len, depth)
		local to = from + dir * len
		deco({ Name = "Coral", Size = Vector3.new(0.9, 0.9, len + 0.5) * s, CFrame = CFrame.lookAt((from + to) / 2, to), Color = col, Material = Enum.Material.SmoothPlastic, Parent = folder })
		deco({ Name = "CoralTip", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2 * s, Position = to, Color = col:Lerp(WHITE, 0.4), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		if depth > 0 then
			for side = -1, 1, 2 do
				branch(to, (dir + Vector3.new(side * 0.6, 0.2, rng:NextNumber(-0.5, 0.5))).Unit, len * 0.7, depth - 1)
			end
		end
	end
	branch(pos, Vector3.yAxis, 4 * s, 2)
end

function PROPS.Kelp(folder, pos, s, rng)
	local p = pos
	local segs = rng:NextInteger(6, 10)
	for i = 1, segs do
		local nextP = p + Vector3.new(math.sin(i * 0.9) * 0.8, 2.4 * s, math.cos(i * 0.7) * 0.5)
		deco({ Name = "Kelp", Size = Vector3.new(1.2 * s, 2.8 * s, 0.3), CFrame = CFrame.lookAt((p + nextP) / 2, nextP) * CFrame.Angles(math.rad(90), 0, 0), Color = Color3.fromRGB(60, 140 + i * 5, 70), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
		if i % 2 == 0 then
			deco({ Name = "KelpBulb", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7 * s, Position = nextP + Vector3.new(0.6, 0, 0), Color = Color3.fromRGB(190, 170, 60), Material = Enum.Material.SmoothPlastic, Parent = folder })
		end
		p = nextP
	end
end

function PROPS.Clam(folder, pos, s, rng)
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local shell = Color3.fromRGB(240, 200, 220)
	deco({ Name = "ClamBottom", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 1.6, 4) * s, CFrame = base * CFrame.new(0, 0.6 * s, 0), Color = shell, Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "ClamTop", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 1.6, 4) * s, CFrame = base * CFrame.new(0, 2 * s, 1.2 * s) * CFrame.Angles(math.rad(-35), 0, 0), Color = shell:Lerp(WHITE, 0.2), Material = Enum.Material.SmoothPlastic, Parent = folder })
	local pearl = deco({ Name = "Pearl", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3 * s, CFrame = base * CFrame.new(0, 1.4 * s, -0.3 * s), Color = Color3.fromRGB(250, 245, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(pearl, Color3.fromRGB(200, 230, 255), 8, 0.8)
end

function PROPS.SeaRock(folder, pos, s, rng)
	local r = rock(folder, pos, s, rng, Color3.fromRGB(70, 95, 105), Enum.Material.Slate)
	for _ = 1, 5 do
		deco({ Name = "Barnacle", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(0.5, 0.9) * s, CFrame = r.CFrame * CFrame.new(rng:NextNumber(-1, 1) * r.Size.X * 0.4, r.Size.Y * 0.45, rng:NextNumber(-1, 1) * r.Size.Z * 0.4), Color = Color3.fromRGB(230, 220, 200), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	PROPS.Coral(folder, (r.CFrame * CFrame.new(0, r.Size.Y / 2, 0)).Position, s * 0.5, rng)
end

function PROPS.CloudPuff(folder, pos, s, rng)
	local y = rng:NextNumber(0, 6)
	for i = 1, 6 do
		deco({ Name = "Cloud", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(4, 7) * s, Position = pos + Vector3.new(rng:NextNumber(-4, 4) * s, y + rng:NextNumber(1.5, 3.5) * s, rng:NextNumber(-3, 3) * s), Color = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(235, 235, 255), rng:NextNumber()), Material = Enum.Material.SmoothPlastic, CastShadow = false, Parent = folder })
	end
end

function PROPS.GoldPillar(folder, pos, s, rng)
	local h = rng:NextNumber(10, 18) * s
	column(folder, pos, h, Color3.fromRGB(250, 248, 240), Enum.Material.Marble)
	deco({ Name = "GoldBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 3.5, 3.5), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, 1 + h * 0.5, 0))), Color = HEAVEN_GOLD, Material = Enum.Material.Metal, Parent = folder })
	local orb = deco({ Name = "PillarOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = pos + Vector3.new(0, h + 3, 0), Color = Color3.fromRGB(255, 240, 180), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	if rng:NextNumber() < 0.4 then
		light(orb, Color3.fromRGB(255, 235, 170), 16, 1)
	end
end

function PROPS.HeavenTree(folder, pos, s, rng)
	local trunkH = 9 * s
	deco({ Name = "Trunk", Size = Vector3.new(2 * s, trunkH, 2 * s), Position = pos + Vector3.new(0, trunkH / 2, 0), Color = Color3.fromRGB(245, 240, 230), Material = Enum.Material.Marble, Parent = folder })
	local c = 3.6 * s
	for layer = 0, 1 do
		for ix = -1, 1 do
			for iz = -1, 1 do
				if layer == 0 or (ix == 0 and iz == 0) then
					local gold = (ix + iz + layer) % 2 == 0
					deco({ Name = "Leaves", Size = Vector3.one * c, Position = pos + Vector3.new(ix * c, trunkH + layer * c, iz * c), Color = if gold then Color3.fromRGB(255, 225, 130) else WHITE, Material = if gold then Enum.Material.Neon else Enum.Material.SmoothPlastic, CastShadow = false, Parent = folder })
				end
			end
		end
	end
end

CLUTTER.Candy = function(folder, p, rng)
	for _ = 1, 3 do
		deco({ Name = "Sprinkle", Size = Vector3.new(0.3, 0.25, 1), CFrame = CFrame.new(p + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.15, rng:NextNumber(-1.5, 1.5))) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = CANDY[rng:NextInteger(1, #CANDY)], Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	end
end
CLUTTER.Ocean = function(folder, p, rng)
	if rng:NextNumber() < 0.5 then
		deco({ Name = "Seagrass", Size = Vector3.new(0.3, rng:NextNumber(1.5, 3), 0.3), CFrame = CFrame.new(p + Vector3.new(0, 1, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(70, 160, 90), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	else
		deco({ Name = "Shell", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 0.4, 0.8), Position = p + Vector3.new(0, 0.2, 0), Color = ({ Color3.fromRGB(250, 220, 230), Color3.fromRGB(255, 200, 150), WHITE })[rng:NextInteger(1, 3)], Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
	end
end
CLUTTER.Heaven = function(folder, p, rng)
	deco({ Name = "Wisp", Shape = Enum.PartType.Ball, Size = Vector3.new(rng:NextNumber(2, 4), 0.8, rng:NextNumber(1.5, 3)), Position = p + Vector3.new(0, 0.3, 0), Color = WHITE, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	if rng:NextNumber() < 0.25 then
		deco({ Name = "GoldSpark", Size = Vector3.one * 0.4, CFrame = CFrame.new(p + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0.8, 0.8, 0), Color = HEAVEN_GOLD, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	end
end

AMBIENT.Sprinkles = { Y = 45, Props = { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 170)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 230, 80)), ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 220, 255)) }), LightEmission = 0.3, Size = NumberSequence.new(0.35), Lifetime = NumberRange.new(8, 11), Rate = 60, Speed = NumberRange.new(0, 1), RotSpeed = NumberRange.new(-180, 180), Rotation = NumberRange.new(0, 360), Acceleration = Vector3.new(0.5, -5, 0), EmissionDirection = Enum.NormalId.Bottom } }
AMBIENT.Bubbles = { Y = 1, Props = { Color = ColorSequence.new(Color3.fromRGB(210, 240, 255)), LightEmission = 0.4, Size = NumberSequence.new(0.3, 0.7), Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(5, 9), Rate = 70, Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(15, 15), EmissionDirection = Enum.NormalId.Top } }
AMBIENT.Feathers = { Y = 50, Props = { Color = ColorSequence.new(WHITE, Color3.fromRGB(255, 235, 170)), LightEmission = 0.6, Size = NumberSequence.new(0.45), Transparency = NumberSequence.new(0.1, 0.6), Lifetime = NumberRange.new(10, 14), Rate = 35, Speed = NumberRange.new(0, 1), RotSpeed = NumberRange.new(-60, 60), Rotation = NumberRange.new(0, 360), Acceleration = Vector3.new(1, -3, 0.5), EmissionDirection = Enum.NormalId.Bottom } }
EXTRA_AMBIENT.Heaven = "Stardust"

WALL_TRIMS.Candy = function(folder, x, z, side, rng)
	for k = 0, 2 do
		deco({ Name = "CandyStripe", Size = Vector3.new(0.3, 12, 1.4), CFrame = CFrame.new(x, 14, z + (k - 1) * 3) * CFrame.Angles(math.rad(30), 0, 0), Color = if k % 2 == 0 then Color3.fromRGB(230, 40, 60) else WHITE, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
	end
	for k = -2, 2 do
		deco({ Name = "FrostingDrip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, rng:NextNumber(2, 4), 1.6), Position = Vector3.new(x, WALL_HEIGHT - 1.5, z + k * 3), Color = Color3.fromRGB(255, 245, 250), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	end
end
WALL_TRIMS.Ocean = function(folder, x, z, side, rng)
	for k = 0, 2 do
		local h = rng:NextNumber(5, 12)
		deco({ Name = "WallKelp", Size = Vector3.new(0.3, h, 1.2), CFrame = CFrame.new(x, h / 2, z + (k - 1) * 3) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, 0), Color = Color3.fromRGB(60, 150, 80), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	end
	for _ = 1, 3 do
		deco({ Name = "WallBarnacle", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(0.8, 1.4), Position = Vector3.new(x, rng:NextNumber(3, 30), z + rng:NextNumber(-6, 6)), Color = Color3.fromRGB(230, 220, 200), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
	end
end
WALL_TRIMS.Heaven = function(folder, x, z, side, rng)
	deco({ Name = "Filigree", Size = Vector3.new(0.3, 8, 0.6), Position = Vector3.new(x, 18, z), Color = HEAVEN_GOLD, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	deco({ Name = "Filigree", Size = Vector3.new(0.3, 0.6, 5), Position = Vector3.new(x, 20, z), Color = HEAVEN_GOLD, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	deco({ Name = "WallCloud", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 7), Position = Vector3.new(x - side * 0.5, WALL_HEIGHT, z), Color = WHITE, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
end

BACKDROPS.Candy = { Base = Color3.fromRGB(200, 130, 220), Top = Color3.fromRGB(255, 245, 250), Material = Enum.Material.SmoothPlastic, MinH = 60, MaxH = 120, Cap = Enum.Material.SmoothPlastic }
BACKDROPS.Ocean = { Base = Color3.fromRGB(35, 70, 85), Top = Color3.fromRGB(60, 110, 120), Material = Enum.Material.Slate, MinH = 70, MaxH = 140 }
BACKDROPS.Heaven = { Base = Color3.fromRGB(235, 235, 250), Top = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic, MinH = 30, MaxH = 70, Floating = true }

function SKY.Candy(folder, centerZ, rng)
	-- a rainbow arching over the zone
	local colors = { Color3.fromRGB(255, 80, 90), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 235, 80), Color3.fromRGB(90, 220, 120), Color3.fromRGB(80, 160, 255), Color3.fromRGB(170, 100, 255) }
	for band, col in ipairs(colors) do
		local r = 260 - band * 9
		for i = 0, 17 do
			local a1, a2 = i / 18 * math.pi, (i + 1) / 18 * math.pi
			local p1 = Vector3.new(-math.cos(a1) * r, math.sin(a1) * r * 0.7 + 20, centerZ + 90)
			local p2 = Vector3.new(-math.cos(a2) * r, math.sin(a2) * r * 0.7 + 20, centerZ + 90)
			local seg = deco({ Name = "Rainbow", Size = Vector3.new(10, 1, (p2 - p1).Magnitude + 1), CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Color = col, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
			seg.Transparency = 0.45
		end
	end
end
function SKY.Ocean(folder, centerZ, rng)
	-- sunbeams slanting down through the water, and fish schools
	for i = 1, 10 do
		local beam = deco({ Name = "LightShaft", Size = Vector3.new(rng:NextNumber(10, 20), 140, 4), CFrame = CFrame.new(rng:NextNumber(-CORRIDOR_HALF + 40, CORRIDOR_HALF - 40), 70, centerZ + rng:NextNumber(-130, 130)) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(15)), Color = Color3.fromRGB(200, 240, 255), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		beam.Transparency = 0.9
	end
	for school = 1, 5 do
		local c = Vector3.new(rng:NextNumber(-300, 300), rng:NextNumber(25, 60), centerZ + rng:NextNumber(-120, 120))
		local col = CORAL[rng:NextInteger(1, #CORAL)]
		for _ = 1, 9 do
			local p = c + Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-3, 3), rng:NextNumber(-8, 8))
			deco({ Name = "Fish", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 1, 2), Position = p, Color = col, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
			deco({ Name = "FishTail", Size = Vector3.new(0.2, 1, 0.8), Position = p + Vector3.new(0, 0, 1.2), Color = col:Lerp(BLACK, 0.2), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
		end
	end
end
function SKY.Heaven(folder, centerZ, rng)
	local sun = deco({ Name = "HeavenSun", Shape = Enum.PartType.Ball, Size = Vector3.one * 60, Position = Vector3.new(0, 230, centerZ + 260), Color = Color3.fromRGB(255, 240, 180), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local ray = deco({ Name = "SunRay", Size = Vector3.new(6, 90, 1), CFrame = CFrame.new(sun.Position) * CFrame.Angles(0, 0, a) * CFrame.new(0, 80, 0), Color = Color3.fromRGB(255, 230, 150), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		ray.Transparency = 0.6
	end
end

SETPIECE_SPOTS.Candy = { { "GingerbreadHouse", -360, 40, 36 }, { "ChocolateRiver", 365, -60, 44 } }
SETPIECE_SPOTS.Ocean = { { "Shipwreck", -360, -40, 42 }, { "GiantClam", 360, 70, 30 } }
SETPIECE_SPOTS.Heaven = { { "SkyTemple", -355, 20, 40 }, { "RainbowBridge", 365, -70, 38 } }

function SETPIECES.GingerbreadHouse(folder, o, rng)
	local cf = CFrame.lookAt(o, o + Vector3.new(if o.X < 0 then 1 else -1, 0, 0))
	house(folder, cf, 20, 12, 16, { Wall = Color3.fromRGB(190, 120, 70), Trim = Color3.fromRGB(255, 250, 245), Roof = Color3.fromRGB(255, 245, 250), Chimney = false })
	for i = -4, 4 do
		deco({ Name = "Gumdrop", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = cf * CFrame.new(i * 2.3, 12.4, -9.3), Color = CANDY[(i % #CANDY) + 1], Material = Enum.Material.Glass, Parent = folder })
	end
	for _, sx in ipairs({ -1, 1 }) do
		PROPS.CandyCane(folder, (cf * CFrame.new(sx * 12, 0, -10)).Position, 0.9, rng)
		PROPS.Lollipop(folder, (cf * CFrame.new(sx * 16, 0, -4)).Position, 0.8, rng)
	end
	for i = 0, 6 do
		deco({ Name = "PathCookie", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3, 3), CFrame = cylinderAlongY(cf * CFrame.new(0, 0.15, -11 - i * 3.4)), Color = Color3.fromRGB(210, 150, 90), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
end

function SETPIECES.ChocolateRiver(folder, o, rng)
	local choc = deco({ Name = "ChocolateRiver", Size = Vector3.new(16, 0.4, 80), Position = o + Vector3.new(0, 0.2, 0), Color = Color3.fromRGB(100, 55, 30), Material = Enum.Material.SmoothPlastic, Reflectance = 0.15, CanCollide = false, Parent = folder })
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "RiverBank", Size = Vector3.new(2, 0.8, 80), Position = o + Vector3.new(sx * 9, 0.4, 0), Color = Color3.fromRGB(255, 230, 240), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	for i = 0, 5 do
		deco({ Name = "Wafer", Size = Vector3.new(20, 0.8, 1.8), Position = o + Vector3.new(0, 1.4, -5 + i * 2), Color = if i % 2 == 0 then Color3.fromRGB(230, 190, 130) else Color3.fromRGB(245, 215, 160), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	local fall = deco({ Name = "ChocolateFall", Size = Vector3.new(12, 24, 3), Position = o + Vector3.new(0, 12, 41), Color = Color3.fromRGB(110, 60, 35), Material = Enum.Material.SmoothPlastic, Reflectance = 0.1, Parent = folder })
	particles(fall, { Color = ColorSequence.new(Color3.fromRGB(120, 70, 40)), Size = NumberSequence.new(1, 2), Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(0.8, 1.2), Rate = 20, Speed = NumberRange.new(3, 6), EmissionDirection = Enum.NormalId.Bottom })
	light(choc, Color3.fromRGB(255, 200, 150), 10, 0.3)
end

function SETPIECES.Shipwreck(folder, o, rng)
	local hull = CFrame.new(o + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(20), math.rad(-14))
	local wood = Color3.fromRGB(95, 70, 50)
	deco({ Name = "Hull", Size = Vector3.new(14, 8, 40), CFrame = hull, Color = wood, Material = Enum.Material.WoodPlanks, Parent = folder })
	deco({ Name = "Bow", Shape = Enum.PartType.Wedge, Size = Vector3.new(14, 8, 10), CFrame = hull * CFrame.new(0, 0, -25) * CFrame.Angles(0, math.pi, 0), Color = wood, Material = Enum.Material.WoodPlanks, Parent = folder })
	deco({ Name = "Deck", Size = Vector3.new(13, 0.6, 38), CFrame = hull * CFrame.new(0, 4.2, 0), Color = wood:Lerp(WHITE, 0.15), Material = Enum.Material.WoodPlanks, Parent = folder })
	deco({ Name = "Hole", Size = Vector3.new(0.4, 4, 6), CFrame = hull * CFrame.new(7.1, -1, 6), Color = Color3.fromRGB(20, 25, 30), Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "Mast", Shape = Enum.PartType.Cylinder, Size = Vector3.new(28, 1.4, 1.4), CFrame = hull * CFrame.new(0, 16, 4) * CFrame.Angles(0, 0, math.rad(80)), Color = wood, Material = Enum.Material.Wood, Parent = folder })
	local sail = deco({ Name = "TornSail", Size = Vector3.new(0.3, 10, 12), CFrame = hull * CFrame.new(-4, 18, 4) * CFrame.Angles(0, 0, math.rad(-10)), Color = Color3.fromRGB(220, 210, 185), Material = Enum.Material.Fabric, Parent = folder })
	sail.Transparency = 0.1
	local chest = deco({ Name = "TreasureChest", Size = Vector3.new(4, 2.6, 2.8), Position = o + Vector3.new(-12, 1.3, -8), Color = Color3.fromRGB(120, 80, 40), Material = Enum.Material.WoodPlanks, Parent = folder })
	local gold = deco({ Name = "Gold", Size = Vector3.new(3.4, 0.6, 2.2), Position = chest.Position + Vector3.new(0, 1.5, 0), Color = Color3.fromRGB(255, 210, 70), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(gold, Color3.fromRGB(255, 220, 120), 16, 1.2)
	for _ = 1, 4 do
		PROPS.Coral(folder, o + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-20, 20)), 0.8, rng)
	end
end

function SETPIECES.GiantClam(folder, o, rng)
	PROPS.Clam(folder, o, 4, rng)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		PROPS.Kelp(folder, o + Vector3.new(math.cos(a) * 22, 0, math.sin(a) * 22), 1.1, rng)
	end
	local glow = deco({ Name = "PearlGlow", Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Position = o + Vector3.new(0, 6, -1.2), Color = Color3.fromRGB(230, 240, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	glow.Transparency = 0.5
	light(glow, Color3.fromRGB(200, 230, 255), 30, 1.5)
end

function SETPIECES.SkyTemple(folder, o, rng)
	local marble = Color3.fromRGB(250, 248, 240)
	for i = 0, 2 do
		deco({ Name = "TempleStep", Size = Vector3.new(34 - i * 3, 1.2, 26 - i * 3), Position = o + Vector3.new(0, 0.6 + i * 1.2, 0), Color = marble:Lerp(BLACK, i * 0.03), Material = Enum.Material.Marble, Parent = folder })
	end
	for ix = -2, 2 do
		for _, sz in ipairs({ -9, 9 }) do
			column(folder, o + Vector3.new(ix * 6.5, 3.6, sz), 14, marble, Enum.Material.Marble)
		end
	end
	deco({ Name = "Entablature", Size = Vector3.new(32, 2.4, 22), Position = o + Vector3.new(0, 21.4, 0), Color = marble, Material = Enum.Material.Marble, Parent = folder })
	roof(folder, CFrame.new(o + Vector3.new(0, 22.6, 0)), 33, 23, 6, marble, Enum.Material.Marble)
	deco({ Name = "GoldTrim", Size = Vector3.new(32.4, 0.6, 22.4), Position = o + Vector3.new(0, 20.2, 0), Color = HEAVEN_GOLD, Material = Enum.Material.Metal, Parent = folder })
	local orb = deco({ Name = "AltarOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 3, Position = o + Vector3.new(0, 6.5, 0), Color = Color3.fromRGB(255, 240, 170), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	deco({ Name = "Altar", Size = Vector3.new(4, 2.4, 4), Position = o + Vector3.new(0, 4.4, 0), Color = HEAVEN_GOLD, Material = Enum.Material.Metal, Parent = folder })
	light(orb, Color3.fromRGB(255, 235, 170), 32, 2)
	particles(orb, { Color = ColorSequence.new(Color3.fromRGB(255, 240, 180)), LightEmission = 1, Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(1.5, 2.5), Rate = 15, Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(180, 180) })
end

function SETPIECES.RainbowBridge(folder, o, rng)
	local colors = { Color3.fromRGB(255, 80, 90), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 235, 80), Color3.fromRGB(90, 220, 120), Color3.fromRGB(80, 160, 255), Color3.fromRGB(170, 100, 255) }
	for band, col in ipairs(colors) do
		for i = 0, 11 do
			local a1, a2 = i / 12 * math.pi, (i + 1) / 12 * math.pi
			local p1 = o + Vector3.new(0, math.sin(a1) * 16 + 1, -math.cos(a1) * 30) + Vector3.new((band - 3.5) * 1.6, 0, 0)
			local p2 = o + Vector3.new(0, math.sin(a2) * 16 + 1, -math.cos(a2) * 30) + Vector3.new((band - 3.5) * 1.6, 0, 0)
			deco({ Name = "RainbowBand", Size = Vector3.new(1.6, 0.8, (p2 - p1).Magnitude + 0.4), CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		end
	end
	for _, sz in ipairs({ -1, 1 }) do
		PROPS.CloudPuff(folder, o + Vector3.new(0, 0, sz * 30), 1.6, rng)
	end
end

--------------------------------------------------------------------------------
-- Glowshroom Grotto, Haunted Hollow, Clockwork Citadel and Neon Nexus
--------------------------------------------------------------------------------
local SHROOM_GLOW = { Color3.fromRGB(80, 230, 255), Color3.fromRGB(255, 90, 220), Color3.fromRGB(150, 255, 90), Color3.fromRGB(170, 110, 255) }
local PUMPKIN = Color3.fromRGB(255, 130, 30)
local GHOST = Color3.fromRGB(150, 255, 180)
local BRASS = Color3.fromRGB(205, 155, 65)
local COPPER = Color3.fromRGB(190, 105, 60)
local IRON = Color3.fromRGB(70, 70, 80)
local NEON = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(40, 240, 255), Color3.fromRGB(150, 80, 255), Color3.fromRGB(255, 220, 60) }
local CYBER_DARK = Color3.fromRGB(20, 16, 36)

-- A mushroom: stem, domed cap with glowing spots and dark gills underneath
local function shroom(folder, pos, h, capW, stemColor, capColor, glowSpots, rng)
	local stemW = capW * 0.28
	deco({ Name = "Stem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, stemW, stemW), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, h / 2, 0))), Color = stemColor, Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "Gills", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, capW * 0.9, capW * 0.9), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, h - 0.1, 0))), Color = capColor:Lerp(BLACK, 0.55), Material = Enum.Material.SmoothPlastic, Parent = folder })
	local cap = deco({ Name = "Cap", Shape = Enum.PartType.Ball, Size = Vector3.new(capW, capW * 0.5, capW), Position = pos + Vector3.new(0, h + capW * 0.12, 0), Color = capColor, Material = Enum.Material.SmoothPlastic, Parent = folder })
	for i = 1, glowSpots do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0.05, 0.32) * capW
		local y = math.sqrt(math.max(0, 1 - (r / (capW / 2)) ^ 2)) * capW * 0.25
		deco({ Name = "CapSpot", Shape = Enum.PartType.Ball, Size = Vector3.new(0.18, 0.08, 0.18) * capW, Position = cap.Position + Vector3.new(math.cos(a) * r, y - 0.05, math.sin(a) * r), Color = WHITE:Lerp(capColor, 0.3), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	return cap
end

function PROPS.GiantShroom(folder, pos, s, rng)
	local col = SHROOM_GLOW[rng:NextInteger(1, #SHROOM_GLOW)]
	local cap = shroom(folder, pos, rng:NextNumber(10, 17) * s, rng:NextNumber(10, 14) * s, Color3.fromRGB(215, 225, 235), col:Lerp(BLACK, 0.25), 5, rng)
	local rim = deco({ Name = "CapGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, cap.Size.X * 0.98, cap.Size.X * 0.98), CFrame = cylinderAlongY(CFrame.new(cap.Position - Vector3.new(0, cap.Size.Y * 0.12, 0))), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	if rng:NextNumber() < 0.35 then
		light(rim, col, 26, 1.2)
	end
end

function PROPS.ShroomCluster(folder, pos, s, rng)
	local col = SHROOM_GLOW[rng:NextInteger(1, #SHROOM_GLOW)]
	for i = 1, rng:NextInteger(3, 5) do
		local p = pos + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)) * s
		local h = rng:NextNumber(1.5, 4) * s
		deco({ Name = "Stem", Size = Vector3.new(0.5, h, 0.5) * Vector3.new(s, 1, s), Position = p + Vector3.new(0, h / 2, 0), Color = Color3.fromRGB(220, 230, 240), Material = Enum.Material.SmoothPlastic, Parent = folder })
		local w = rng:NextNumber(1.6, 2.8) * s
		deco({ Name = "GlowCap", Shape = Enum.PartType.Ball, Size = Vector3.new(w, w * 0.55, w), Position = p + Vector3.new(0, h, 0), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
end

function PROPS.GlowRock(folder, pos, s, rng)
	local r = rock(folder, pos, s, rng, Color3.fromRGB(55, 50, 80), Enum.Material.Slate)
	local col = SHROOM_GLOW[rng:NextInteger(1, #SHROOM_GLOW)]
	for _ = 1, 4 do
		deco({ Name = "GlowMoss", Shape = Enum.PartType.Ball, Size = Vector3.new(rng:NextNumber(1, 2), 0.3, rng:NextNumber(1, 2)) * s, CFrame = r.CFrame * CFrame.new(rng:NextNumber(-0.4, 0.4) * r.Size.X, r.Size.Y * 0.48, rng:NextNumber(-0.4, 0.4) * r.Size.Z), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
end

function PROPS.Pumpkin(folder, pos, s, rng)
	local size = rng:NextNumber(3, 5.5) * s
	local base = CFrame.new(pos + Vector3.new(0, size * 0.4, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	for k = -1, 1 do
		deco({ Name = "Pumpkin", Shape = Enum.PartType.Ball, Size = Vector3.new(size * 0.6, size * 0.8, size), CFrame = base * CFrame.new(k * size * 0.28, 0, 0), Color = PUMPKIN:Lerp(Color3.fromRGB(200, 80, 20), math.abs(k) * 0.4), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	deco({ Name = "PumpkinStem", Size = Vector3.new(0.5, 1.2, 0.5) * s, CFrame = base * CFrame.new(0, size * 0.45, 0) * CFrame.Angles(0, 0, 0.3), Color = Color3.fromRGB(80, 110, 40), Material = Enum.Material.Wood, Parent = folder })
	if rng:NextNumber() < 0.5 then
		-- carved face glowing from inside
		local faceGlow = Color3.fromRGB(255, 220, 90)
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "PumpkinEye", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.2, 0.8, 0.8) * size / 3, CFrame = base * CFrame.new(sx * size * 0.2, size * 0.1, -size * 0.49) * CFrame.Angles(0, math.rad(90), 0), Color = faceGlow, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		end
		local mouth = deco({ Name = "PumpkinMouth", Size = Vector3.new(size * 0.5, size * 0.12, 0.2), CFrame = base * CFrame.new(0, -size * 0.14, -size * 0.49), Color = faceGlow, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		if rng:NextNumber() < 0.4 then
			light(mouth, Color3.fromRGB(255, 170, 60), 14, 1)
		end
	end
end

function PROPS.Gravestone(folder, pos, s, rng)
	local stone = Color3.fromRGB(125, 125, 135):Lerp(Color3.fromRGB(90, 100, 90), rng:NextNumber())
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.12, 0.12))
	deco({ Name = "Mound", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 1, 6.5) * s, CFrame = base * CFrame.new(0, 0, 3 * s), Color = Color3.fromRGB(70, 60, 50), Material = Enum.Material.Ground, Parent = folder })
	if rng:NextNumber() < 0.3 then
		deco({ Name = "CrossPost", Size = Vector3.new(0.9, 6, 0.9) * s, CFrame = base * CFrame.new(0, 3 * s, 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "CrossBar", Size = Vector3.new(3.6, 0.9, 0.9) * s, CFrame = base * CFrame.new(0, 4.3 * s, 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
	else
		deco({ Name = "Headstone", Size = Vector3.new(3.4, 3.6, 0.8) * s, CFrame = base * CFrame.new(0, 1.8 * s, 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "HeadstoneTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8 * s, 3.4 * s, 3.4 * s), CFrame = base * CFrame.new(0, 3.6 * s, 0) * CFrame.Angles(0, math.rad(90), 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "RIP", Size = Vector3.new(1.8, 0.35, 0.2) * s, CFrame = base * CFrame.new(0, 2.6 * s, -0.45 * s), Color = stone:Lerp(BLACK, 0.4), Material = Enum.Material.Slate, Parent = folder })
	end
	if rng:NextNumber() < 0.25 then
		deco({ Name = "GraveCandle", Size = Vector3.new(0.4, 0.8, 0.4), CFrame = base * CFrame.new(1.4 * s, 0.4, -1 * s), Color = Color3.fromRGB(240, 235, 210), Material = Enum.Material.SmoothPlastic, Parent = folder })
		deco({ Name = "CandleFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.5, 0.3), CFrame = base * CFrame.new(1.4 * s, 1, -1 * s), Color = GHOST, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
end

function PROPS.SpookyTree(folder, pos, s, rng)
	local bark = Color3.fromRGB(48, 38, 48)
	local p = pos
	local dir = Vector3.yAxis
	for i = 1, 4 do
		dir = (dir + Vector3.new(rng:NextNumber(-0.35, 0.35), 0, rng:NextNumber(-0.35, 0.35))).Unit
		local len = rng:NextNumber(3.5, 5) * s
		local nextP = p + dir * len
		deco({ Name = "Trunk", Size = Vector3.new((2.2 - i * 0.35) * s, (2.2 - i * 0.35) * s, len + 0.6), CFrame = CFrame.lookAt((p + nextP) / 2, nextP), Color = bark, Material = Enum.Material.Wood, Parent = folder })
		if i >= 2 then
			for _ = 1, 2 do
				local bdir = (dir + Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(-0.2, 0.4), rng:NextNumber(-1.2, 1.2))).Unit
				local blen = rng:NextNumber(3, 6) * s
				local tip = nextP + bdir * blen
				deco({ Name = "Branch", Size = Vector3.new(0.5 * s, 0.5 * s, blen), CFrame = CFrame.lookAt((nextP + tip) / 2, tip), Color = bark, Material = Enum.Material.Wood, Parent = folder })
			end
		end
		p = nextP
	end
	if rng:NextNumber() < 0.3 then
		lantern(folder, p + Vector3.new(1.5, -2.5, 0), GHOST, 14)
	end
end

-- A gear: a disc with teeth around the rim and a hub, standing on its edge
local function gear(folder, cf, radius, color, material)
	deco({ Name = "GearDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(radius * 0.25, radius * 2, radius * 2), CFrame = cf, Color = color, Material = material or Enum.Material.Metal, Parent = folder })
	local teeth = math.clamp(math.floor(radius * 2.4), 8, 16)
	for i = 0, teeth - 1 do
		local a = i / teeth * math.pi * 2
		deco({ Name = "GearTooth", Size = Vector3.new(radius * 0.25, radius * 0.32, radius * 0.32), CFrame = cf * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius + radius * 0.1, 0), Color = color, Material = material or Enum.Material.Metal, Parent = folder })
	end
	deco({ Name = "GearHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(radius * 0.4, radius * 0.6, radius * 0.6), CFrame = cf, Color = color:Lerp(BLACK, 0.35), Material = Enum.Material.Metal, Parent = folder })
end

function PROPS.Gear(folder, pos, s, rng)
	local r = rng:NextNumber(3, 6) * s
	gear(folder, CFrame.new(pos + Vector3.new(0, r * 0.75, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0) * CFrame.Angles(rng:NextNumber(0, 1), 0, 0), r, if rng:NextNumber() < 0.5 then BRASS else COPPER)
end

function PROPS.SteamPipe(folder, pos, s, rng)
	local yaw = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local h = rng:NextNumber(6, 10) * s
	local w = 1.4 * s
	deco({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, w, w), CFrame = cylinderAlongY(yaw * CFrame.new(0, h / 2, 0)), Color = COPPER, Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "PipeElbow", Shape = Enum.PartType.Ball, Size = Vector3.one * w * 1.2, CFrame = yaw * CFrame.new(0, h, 0), Color = COPPER, Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5 * s, w, w), CFrame = yaw * CFrame.new(2.5 * s, h, 0), Color = COPPER, Material = Enum.Material.Metal, Parent = folder })
	local vent = deco({ Name = "Vent", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, w * 1.6, w * 1.6), CFrame = yaw * CFrame.new(5 * s, h, 0), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	for _, y in ipairs({ 1.2, h * 0.6 }) do
		deco({ Name = "PipeRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, w * 1.3, w * 1.3), CFrame = cylinderAlongY(yaw * CFrame.new(0, y, 0)), Color = BRASS, Material = Enum.Material.Metal, Parent = folder })
	end
	gear(folder, yaw * CFrame.new(0, h * 0.4, -w * 0.9) * CFrame.Angles(0, math.rad(90), 0), 1.1 * s, Color3.fromRGB(200, 50, 50))
	if rng:NextNumber() < 0.5 then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(235, 235, 240)
		smoke.Opacity = 0.18
		smoke.Size = 2
		smoke.RiseVelocity = 5
		smoke.Parent = vent
	end
end

function PROPS.Lamppost(folder, pos, s)
	deco({ Name = "LampBase", Size = Vector3.new(1.6, 1, 1.6), Position = pos + Vector3.new(0, 0.5, 0), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "LampPost", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10 * s, 0.6, 0.6), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, 5 * s, 0))), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "LampCage", Size = Vector3.new(1.6, 2.2, 1.6), Position = pos + Vector3.new(0, 10 * s + 1, 0), Color = BRASS, Material = Enum.Material.Metal, Transparency = 0.2, Parent = folder })
	local bulb = deco({ Name = "LampBulb", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, Position = pos + Vector3.new(0, 10 * s + 1, 0), Color = Color3.fromRGB(255, 210, 130), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(bulb, Color3.fromRGB(255, 190, 110), 18, 1)
	deco({ Name = "LampCap", Shape = Enum.PartType.Wedge, Size = Vector3.new(2, 0.8, 2), Position = pos + Vector3.new(0, 10 * s + 2.5, 0), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
end

function PROPS.CogTower(folder, pos, s, rng)
	local y = 0
	for i = 0, 2 do
		local h = (5 - i) * s
		local w = (6 - i * 1.4) * s
		deco({ Name = "TowerDrum", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, w, w), CFrame = cylinderAlongY(CFrame.new(pos + Vector3.new(0, y + h / 2, 0))), Color = if i % 2 == 0 then COPPER else BRASS, Material = Enum.Material.Metal, Parent = folder })
		y += h
	end
	gear(folder, CFrame.new(pos + Vector3.new(0, y * 0.55, -3.4 * s)) * CFrame.Angles(0, math.rad(90), 0), 2.2 * s, BRASS)
	local top = deco({ Name = "TowerLight", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6 * s, Position = pos + Vector3.new(0, y + 0.8 * s, 0), Color = Color3.fromRGB(120, 230, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	if rng:NextNumber() < 0.3 then
		light(top, Color3.fromRGB(120, 230, 255), 18, 1)
	end
end

function PROPS.NeonTower(folder, pos, s, rng)
	local w = rng:NextNumber(5, 8) * s
	local h = rng:NextNumber(14, 26) * s
	local col = NEON[rng:NextInteger(1, #NEON)]
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextInteger(0, 3) * math.pi / 2, 0)
	deco({ Name = "Tower", Size = Vector3.new(w, h, w), CFrame = base * CFrame.new(0, h / 2, 0), Color = CYBER_DARK, Material = Enum.Material.Glass, Reflectance = 0.2, Parent = folder })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			deco({ Name = "TowerEdge", Size = Vector3.new(0.3, h, 0.3), CFrame = base * CFrame.new(sx * w / 2, h / 2, sz * w / 2), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		end
	end
	for y = 3, h - 2, 4 do
		deco({ Name = "WindowBand", Size = Vector3.new(w + 0.1, 0.6, w + 0.1), CFrame = base * CFrame.new(0, y, 0), Color = col:Lerp(WHITE, 0.3), Material = Enum.Material.Neon, Transparency = 0.35, CastShadow = false, Parent = folder })
	end
	local top = deco({ Name = "TowerBeacon", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, CFrame = base * CFrame.new(0, h + 1.5, 0), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	deco({ Name = "Antenna", Size = Vector3.new(0.3, 3, 0.3), CFrame = base * CFrame.new(0, h + 0.5, 0), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	if rng:NextNumber() < 0.3 then
		light(top, col, 24, 1.4)
	end
end

function PROPS.HoloTree(folder, pos, s, rng)
	local col = NEON[rng:NextInteger(1, 3)]
	local h = rng:NextNumber(6, 9) * s
	deco({ Name = "HoloTrunk", Size = Vector3.new(0.8, h, 0.8) * Vector3.new(s, 1, s), Position = pos + Vector3.new(0, h / 2, 0), Color = col:Lerp(WHITE, 0.4), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	for i = 0, 2 do
		local size = (6 - i * 1.6) * s
		local leaf = deco({ Name = "HoloLeaves", Size = Vector3.one * size, CFrame = CFrame.new(pos + Vector3.new(0, h + i * 2.6 * s, 0)) * CFrame.Angles(0, i * 0.5, math.rad(45)), Color = col, Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, Parent = folder })
		leaf.Transparency = 0.55
	end
end

function PROPS.DataPillar(folder, pos, s, rng)
	local h = rng:NextNumber(8, 14) * s
	local col = NEON[rng:NextInteger(1, #NEON)]
	deco({ Name = "PillarBase", Size = Vector3.new(4, 1, 4) * Vector3.new(s, 1, s), Position = pos + Vector3.new(0, 0.5, 0), Color = CYBER_DARK, Material = Enum.Material.Metal, Parent = folder })
	local core = deco({ Name = "DataCore", Size = Vector3.new(2.2 * s, h, 2.2 * s), Position = pos + Vector3.new(0, h / 2 + 1, 0), Color = col:Lerp(CYBER_DARK, 0.6), Material = Enum.Material.Glass, Transparency = 0.3, Parent = folder })
	for y = 2, h, 2.5 do
		deco({ Name = "DataRing", Size = Vector3.new(2.8 * s, 0.35, 2.8 * s), Position = pos + Vector3.new(0, y + 1, 0), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	particles(core, { Color = ColorSequence.new(col), LightEmission = 1, Size = NumberSequence.new(0.25, 0), Lifetime = NumberRange.new(1, 2), Rate = 4, Speed = NumberRange.new(3, 5), EmissionDirection = Enum.NormalId.Top })
end

function PROPS.NeonSign(folder, pos, s, rng)
	local col = NEON[rng:NextInteger(1, #NEON)]
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "SignPole", Size = Vector3.new(0.5, 8 * s, 0.5), CFrame = base * CFrame.new(sx * 3.5 * s, 4 * s, 0), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	end
	local board = deco({ Name = "SignBoard", Size = Vector3.new(8 * s, 3.6 * s, 0.4), CFrame = base * CFrame.new(0, 8 * s, 0), Color = CYBER_DARK, Material = Enum.Material.SmoothPlastic, Parent = folder })
	for _, info in ipairs({ { 0, 1.8 }, { 0, -1.8 } }) do
		deco({ Name = "SignFrame", Size = Vector3.new(8.2 * s, 0.3, 0.5), CFrame = board.CFrame * CFrame.new(0, info[2] * s, 0), Color = col, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	local words = { "EGGS 24/7", "PET SHOP", "NEXUS", "SPEED++", "HATCH!", "404 EGG" }
	surfaceText(board, Enum.NormalId.Front, words[rng:NextInteger(1, #words)], col, Enum.Font.Arcade)
end

CLUTTER.Shroom = function(folder, p, rng)
	deco({ Name = "TinyShroom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.5, 0.9), Position = p + Vector3.new(0, 0.7, 0), Color = SHROOM_GLOW[rng:NextInteger(1, #SHROOM_GLOW)], Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	deco({ Name = "TinyStem", Size = Vector3.new(0.25, 0.6, 0.25), Position = p + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(220, 230, 240), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
end
CLUTTER.Spooky = function(folder, p, rng)
	if rng:NextNumber() < 0.5 then
		deco({ Name = "DeadLeaf", Size = Vector3.new(0.8, 0.1, 0.6), CFrame = CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = ({ Color3.fromRGB(150, 80, 30), Color3.fromRGB(110, 60, 30), Color3.fromRGB(170, 120, 40) })[rng:NextInteger(1, 3)], Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	else
		deco({ Name = "Bone", Size = Vector3.new(0.3, 0.3, 1.4), CFrame = CFrame.new(p + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(235, 230, 215), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
	end
end
CLUTTER.Clockwork = function(folder, p, rng)
	if rng:NextNumber() < 0.6 then
		deco({ Name = "Bolt", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.7, 0.7), CFrame = cylinderAlongY(CFrame.new(p + Vector3.new(0, 0.15, 0))), Color = BRASS, Material = Enum.Material.Metal, CanCollide = false, Parent = folder })
	else
		deco({ Name = "Spring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 0.5, 0.5), CFrame = CFrame.new(p + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(170, 170, 180), Material = Enum.Material.Metal, CanCollide = false, Parent = folder })
	end
end
CLUTTER.Cyber = function(folder, p, rng)
	deco({ Name = "GridLight", Size = Vector3.new(rng:NextNumber(1, 3), 0.08, 0.2), CFrame = CFrame.new(p + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, rng:NextInteger(0, 1) * math.pi / 2, 0), Color = NEON[rng:NextInteger(1, #NEON)], Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
end

AMBIENT.Spores = { Y = 1, Props = { Color = ColorSequence.new(Color3.fromRGB(120, 240, 255), Color3.fromRGB(255, 120, 230)), LightEmission = 1, Size = NumberSequence.new(0.35, 0.1), Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(6, 10), Rate = 50, Speed = NumberRange.new(1, 2.5), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top } }
AMBIENT.Mist = { Y = 1.5, Props = { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(170, 230, 190)), LightEmission = 0.2, Size = NumberSequence.new(8, 14), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.8), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(8, 12), Rate = 18, Speed = NumberRange.new(0.5, 1.5), RotSpeed = NumberRange.new(-10, 10), SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top } }
AMBIENT.Steam = { Y = 1, Props = { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(245, 240, 235)), LightEmission = 0.1, Size = NumberSequence.new(2, 6), Transparency = NumberSequence.new(0.85, 1), Lifetime = NumberRange.new(4, 7), Rate = 25, Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Top } }
AMBIENT.Data = { Y = 1, Props = { Color = ColorSequence.new(Color3.fromRGB(40, 240, 255), Color3.fromRGB(255, 60, 200)), LightEmission = 1, Size = NumberSequence.new(0.3), Transparency = NumberSequence.new(0, 1), Lifetime = NumberRange.new(4, 7), Rate = 60, Speed = NumberRange.new(3, 6), EmissionDirection = Enum.NormalId.Top } }
EXTRA_AMBIENT.Shroom = "Fireflies"
EXTRA_AMBIENT.Spooky = "Motes"
EXTRA_AMBIENT.Cyber = "Stardust"

WALL_TRIMS.Shroom = function(folder, x, z, side, rng)
	local col = SHROOM_GLOW[rng:NextInteger(1, #SHROOM_GLOW)]
	local h = rng:NextNumber(10, 26)
	deco({ Name = "GlowVine", Size = Vector3.new(0.3, h, 0.4), CFrame = CFrame.new(x, WALL_HEIGHT - h / 2, z) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, 0), Color = col, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	deco({ Name = "WallShroom", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 0.8, 2.4), Position = Vector3.new(x - side * 0.6, rng:NextNumber(4, 14), z + rng:NextNumber(-5, 5)), Color = col, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
end
WALL_TRIMS.Spooky = function(folder, x, z, side, rng)
	if rng:NextNumber() < 0.5 then
		local web = CFrame.new(x - side * 0.2, WALL_HEIGHT - 4, z)
		for k = 0, 2 do
			local strand = deco({ Name = "Cobweb", Size = Vector3.new(0.1, 7, 0.12), CFrame = web * CFrame.Angles(k * math.pi / 3, 0, 0), Color = Color3.fromRGB(230, 230, 235), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
			strand.Transparency = 0.4
		end
	else
		deco({ Name = "WallCrack", Size = Vector3.new(0.2, rng:NextNumber(4, 9), 0.3), CFrame = CFrame.new(x - side * 0.1, rng:NextNumber(8, 28), z) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), 0, 0), Color = Color3.fromRGB(30, 28, 36), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	end
	if rng:NextNumber() < 0.2 then
		PROPS.Pumpkin(folder, Vector3.new(x - side * 3, WALL_HEIGHT, z), 0.5, rng)
	end
end
WALL_TRIMS.Clockwork = function(folder, x, z, side, rng)
	deco({ Name = "WallPipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16.2, 1.2, 1.2), CFrame = CFrame.new(x - side * 0.6, 8, z) * CFrame.Angles(0, math.rad(90), 0), Color = COPPER, Material = Enum.Material.Metal, CanCollide = false, Parent = folder })
	deco({ Name = "Rivet", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, Position = Vector3.new(x - side * 0.2, 30, z), Color = BRASS, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false, Parent = folder })
	if rng:NextNumber() < 0.3 then
		gear(folder, CFrame.new(x - side * 0.4, rng:NextNumber(16, 28), z), rng:NextNumber(2, 4), BRASS)
	end
end
WALL_TRIMS.Cyber = function(folder, x, z, side, rng)
	local col = NEON[rng:NextInteger(1, 3)]
	deco({ Name = "NeonStripe", Size = Vector3.new(0.2, WALL_HEIGHT - 6, 0.4), Position = Vector3.new(x - side * 0.1, WALL_HEIGHT / 2, z), Color = col, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	deco({ Name = "NeonBand", Size = Vector3.new(0.2, 0.4, 16.2), Position = Vector3.new(x - side * 0.1, 6, z), Color = NEON[2], Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
end

BACKDROPS.Shroom = { Base = Color3.fromRGB(40, 30, 64), Top = Color3.fromRGB(70, 50, 105), Material = Enum.Material.Slate, MinH = 90, MaxH = 160, Cap = Enum.Material.Slate }
BACKDROPS.Spooky = { Base = Color3.fromRGB(40, 40, 48), Top = Color3.fromRGB(62, 60, 72), Material = Enum.Material.Slate, MinH = 45, MaxH = 95 }
BACKDROPS.Clockwork = { Base = Color3.fromRGB(95, 70, 45), Top = Color3.fromRGB(170, 125, 70), Material = Enum.Material.Metal, MinH = 60, MaxH = 120, Flat = true }
BACKDROPS.Cyber = { Base = Color3.fromRGB(22, 16, 42), Top = Color3.fromRGB(70, 35, 120), Material = Enum.Material.Glass, MinH = 100, MaxH = 190, Flat = true }

function SKY.Shroom(folder, centerZ, rng)
	-- big glowing spore-jellies drifting overhead
	for _ = 1, 12 do
		local col = SHROOM_GLOW[rng:NextInteger(1, #SHROOM_GLOW)]
		local c = Vector3.new(rng:NextNumber(-380, 380), rng:NextNumber(70, 130), centerZ + rng:NextNumber(-140, 140))
		local size = rng:NextNumber(10, 20)
		local bell = deco({ Name = "SporeJelly", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size * 0.6, size), Position = c, Color = col, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		bell.Transparency = 0.45
		for k = 1, 5 do
			local a = k / 5 * math.pi * 2
			local len = rng:NextNumber(8, 16)
			local tendril = deco({ Name = "Tendril", Size = Vector3.new(0.4, len, 0.4), Position = c + Vector3.new(math.cos(a) * size * 0.3, -len / 2 - size * 0.2, math.sin(a) * size * 0.3), Color = col, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
			tendril.Transparency = 0.5
		end
	end
end

function SKY.Spooky(folder, centerZ, rng)
	local moon = deco({ Name = "HauntedMoon", Shape = Enum.PartType.Ball, Size = Vector3.one * 80, Position = Vector3.new(-120, 210, centerZ + 300), Color = Color3.fromRGB(235, 245, 225), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	for _ = 1, 5 do
		deco({ Name = "MoonCrater", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(8, 16), Position = moon.Position + Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(-25, 25), -36), Color = Color3.fromRGB(200, 210, 195), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	end
	-- bat flocks
	for flock = 1, 6 do
		local c = Vector3.new(rng:NextNumber(-350, 350), rng:NextNumber(50, 110), centerZ + rng:NextNumber(-130, 130))
		for _ = 1, 7 do
			local p = c + Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-5, 5), rng:NextNumber(-12, 12))
			local yaw = rng:NextNumber(0, math.pi * 2)
			deco({ Name = "Bat", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.6), Position = p, Color = Color3.fromRGB(25, 20, 30), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
			for _, sx in ipairs({ -1, 1 }) do
				deco({ Name = "BatWing", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.2, 1.2, 2.6), CFrame = CFrame.new(p) * CFrame.Angles(0, yaw, 0) * CFrame.new(sx * 1.6, 0.2, 0) * CFrame.Angles(0, math.rad(90 * sx), math.rad(-15 * sx)), Color = Color3.fromRGB(25, 20, 30), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
			end
		end
	end
end

function SKY.Clockwork(folder, centerZ, rng)
	-- airships drifting over the citadel, and a giant clock gear in the sky
	for i = 1, 3 do
		local c = Vector3.new(rng:NextNumber(-320, 320), rng:NextNumber(90, 140), centerZ + rng:NextNumber(-120, 120))
		local yaw = CFrame.new(c) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		deco({ Name = "Blimp", Shape = Enum.PartType.Ball, Size = Vector3.new(16, 16, 44), CFrame = yaw, Color = Color3.fromRGB(190, 70, 60):Lerp(Color3.fromRGB(230, 200, 150), i / 3), Material = Enum.Material.Fabric, CanCollide = false, CastShadow = false, Parent = folder })
		deco({ Name = "BlimpBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 16.4, 16.4), CFrame = yaw * CFrame.Angles(0, math.rad(90), 0), Color = BRASS, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false, Parent = folder })
		deco({ Name = "Gondola", Size = Vector3.new(6, 3.5, 14), CFrame = yaw * CFrame.new(0, -10.5, 0), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = folder })
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "Rope", Size = Vector3.new(0.3, 6, 0.3), CFrame = yaw * CFrame.new(sx * 2.6, -7, sx * 5), Color = Color3.fromRGB(80, 60, 40), Material = Enum.Material.Fabric, CanCollide = false, CastShadow = false, Parent = folder })
		end
		deco({ Name = "Fin", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.6, 8, 8), CFrame = yaw * CFrame.new(0, 6, 20), Color = BRASS, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false, Parent = folder })
		gear(folder, yaw * CFrame.new(0, -10.5, 8.5) * CFrame.Angles(0, math.rad(90), 0), 2.5, IRON)
	end
	gear(folder, CFrame.new(160, 170, centerZ + 280) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0.3, 0, 0), 40, BRASS)
end

function SKY.Cyber(folder, centerZ, rng)
	-- a synthwave sun on the horizon with stripes cut through it
	local sunC = Vector3.new(0, 110, centerZ + 320)
	deco({ Name = "SynthSun", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 150, 150), CFrame = CFrame.new(sunC) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(255, 120, 90), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	deco({ Name = "SynthSunTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 110, 110), CFrame = CFrame.new(sunC + Vector3.new(0, 18, -0.5)) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(255, 210, 80), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	for i = 0, 5 do
		deco({ Name = "SunStripe", Size = Vector3.new(160, 2 + i * 1.2, 1), Position = sunC + Vector3.new(0, -10 - i * 11, -2), Color = Color3.fromRGB(35, 15, 60), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
	end
	-- flying cars zipping across
	for _ = 1, 14 do
		local col = NEON[rng:NextInteger(1, #NEON)]
		local p = Vector3.new(rng:NextNumber(-380, 380), rng:NextNumber(45, 100), centerZ + rng:NextNumber(-140, 140))
		local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextInteger(0, 1) * math.pi / 2, 0)
		deco({ Name = "FlyingCar", Size = Vector3.new(3, 1.4, 6), CFrame = cf, Color = CYBER_DARK, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false, Parent = folder })
		deco({ Name = "CarGlow", Size = Vector3.new(3.2, 0.3, 6.2), CFrame = cf * CFrame.new(0, -0.8, 0), Color = col, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		local trail = deco({ Name = "CarTrail", Size = Vector3.new(1.2, 0.4, 16), CFrame = cf * CFrame.new(0, 0, 11), Color = col, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		trail.Transparency = 0.6
	end
end

SETPIECE_SPOTS.Shroom = { { "ShroomHouse", -355, 30, 36 }, { "GlowPool", 360, -60, 38 } }
SETPIECE_SPOTS.Spooky = { { "HauntedManor", -352, -20, 42 }, { "Graveyard", 360, 60, 40 } }
SETPIECE_SPOTS.Clockwork = { { "ClockTower", -355, 10, 36 }, { "GearWorks", 360, -50, 40 } }
SETPIECE_SPOTS.Cyber = { { "DataCoreHub", -355, 30, 38 }, { "NeonPyramid", 360, -40, 40 } }

function SETPIECES.ShroomHouse(folder, o, rng)
	-- a mushroom you can live in: a round stem-house with a door, windows and a huge cap
	local col = SHROOM_GLOW[2]
	local facing = CFrame.lookAt(o, o + Vector3.new(if o.X < 0 then 1 else -1, 0, 0))
	deco({ Name = "HouseStem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 14, 14), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 8, 0))), Color = Color3.fromRGB(235, 225, 210), Material = Enum.Material.SmoothPlastic, Parent = folder })
	local cap = shroom(folder, o + Vector3.new(0, 14, 0), 2, 30, Color3.fromRGB(235, 225, 210), Color3.fromRGB(200, 50, 150), 10, rng)
	light(cap, col, 40, 1.4)
	deco({ Name = "Door", Size = Vector3.new(4, 7, 0.6), CFrame = facing * CFrame.new(0, 3.5, -7), Color = Color3.fromRGB(110, 70, 45), Material = Enum.Material.WoodPlanks, Parent = folder })
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "RoundWindow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3, 3), CFrame = facing * CFrame.new(sx * 4.2, 10, -6.2) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(255, 220, 140), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	for i = 0, 5 do
		deco({ Name = "SteppingShroom", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 3, 3), CFrame = cylinderAlongY(facing * CFrame.new(0, 0.3, -10 - i * 3.6)), Color = SHROOM_GLOW[(i % #SHROOM_GLOW) + 1], Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	end
	for _ = 1, 4 do
		PROPS.ShroomCluster(folder, o + Vector3.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20)), 1, rng)
	end
end

function SETPIECES.GlowPool(folder, o, rng)
	local pool = deco({ Name = "GlowPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 50, 50), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.2, 0))), Color = Color3.fromRGB(40, 200, 230), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	pool.Transparency = 0.35
	deco({ Name = "PoolRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 53, 53), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.1, 0))), Color = Color3.fromRGB(60, 55, 85), Material = Enum.Material.Slate, Parent = folder })
	for _ = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(4, 18)
		deco({ Name = "LilyPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 4, 4), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(math.cos(a) * r, 0.5, math.sin(a) * r))), Color = Color3.fromRGB(70, 170, 90), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		PROPS.GiantShroom(folder, o + Vector3.new(math.cos(a) * 32, 0, math.sin(a) * 32), 0.6, rng)
	end
	light(pool, Color3.fromRGB(80, 230, 255), 40, 1.5)
end

function SETPIECES.HauntedManor(folder, o, rng)
	local cf = CFrame.lookAt(o, o + Vector3.new(if o.X < 0 then 1 else -1, 0, 0))
	house(folder, cf, 26, 16, 20, { Wall = Color3.fromRGB(75, 70, 85), Trim = Color3.fromRGB(35, 30, 40), Roof = Color3.fromRGB(45, 40, 55), RoofHeight = 12, Chimney = false })
	for _, sx in ipairs({ -1, 1 }) do
		-- two crooked towers
		local t = cf * CFrame.new(sx * 14, 0, 4) * CFrame.Angles(0, 0, math.rad(3 * sx))
		deco({ Name = "Tower", Size = Vector3.new(7, 26, 7), CFrame = t * CFrame.new(0, 13, 0), Color = Color3.fromRGB(65, 60, 75), Material = Enum.Material.Brick, Parent = folder })
		deco({ Name = "TowerSpire", Shape = Enum.PartType.Wedge, Size = Vector3.new(8, 10, 4), CFrame = t * CFrame.new(0, 31, -2), Color = Color3.fromRGB(45, 40, 55), Material = Enum.Material.Slate, Parent = folder })
		deco({ Name = "TowerSpire", Shape = Enum.PartType.Wedge, Size = Vector3.new(8, 10, 4), CFrame = t * CFrame.new(0, 31, 2) * CFrame.Angles(0, math.pi, 0), Color = Color3.fromRGB(45, 40, 55), Material = Enum.Material.Slate, Parent = folder })
		local win = deco({ Name = "TowerWindow", Size = Vector3.new(2, 3, 0.4), CFrame = t * CFrame.new(0, 20, -3.6), Color = GHOST, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		light(win, GHOST, 20, 1)
	end
	-- a ghost floating by the door
	local ghost = deco({ Name = "Ghost", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 6, 4), CFrame = cf * CFrame.new(-6, 7, -16), Color = Color3.fromRGB(235, 255, 240), Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, Parent = folder })
	ghost.Transparency = 0.35
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "GhostEye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 1.1, 0.4), CFrame = ghost.CFrame * CFrame.new(sx * 0.8, 1, -1.8), Color = BLACK, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
	end
	for i = -3, 3 do
		deco({ Name = "IronFence", Size = Vector3.new(0.4, 5, 0.4), CFrame = cf * CFrame.new(i * 4, 2.5, -20), Color = Color3.fromRGB(30, 28, 35), Material = Enum.Material.Metal, Parent = folder })
	end
	deco({ Name = "FenceRail", Size = Vector3.new(24.4, 0.4, 0.4), CFrame = cf * CFrame.new(0, 4.2, -20), Color = Color3.fromRGB(30, 28, 35), Material = Enum.Material.Metal, Parent = folder })
end

function SETPIECES.Graveyard(folder, o, rng)
	for ix = -2, 2 do
		for iz = -2, 2 do
			if rng:NextNumber() < 0.8 then
				PROPS.Gravestone(folder, o + Vector3.new(ix * 7, 0, iz * 8), 0.9, rng)
			end
		end
	end
	-- a spooky gate arch and a big dead tree in the corner
	deco({ Name = "GateArch", Size = Vector3.new(1, 12, 1), Position = o + Vector3.new(-18, 6, -6), Color = Color3.fromRGB(30, 28, 35), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "GateArch", Size = Vector3.new(1, 12, 1), Position = o + Vector3.new(-18, 6, 6), Color = Color3.fromRGB(30, 28, 35), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "GateTop", Size = Vector3.new(1, 1, 13), Position = o + Vector3.new(-18, 12, 0), Color = Color3.fromRGB(30, 28, 35), Material = Enum.Material.Metal, Parent = folder })
	PROPS.SpookyTree(folder, o + Vector3.new(16, 0, 20), 1.6, rng)
	for _ = 1, 3 do
		PROPS.Pumpkin(folder, o + Vector3.new(rng:NextNumber(-16, 16), 0, rng:NextNumber(-20, -16)), 1.2, rng)
	end
	local glow = deco({ Name = "GraveGlow", Size = Vector3.new(36, 0.2, 44), Position = o + Vector3.new(0, 0.12, 0), Color = GHOST, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	glow.Transparency = 0.85
end

function SETPIECES.ClockTower(folder, o, rng)
	local cf = CFrame.lookAt(o, o + Vector3.new(if o.X < 0 then 1 else -1, 0, 0))
	deco({ Name = "TowerBody", Size = Vector3.new(14, 40, 14), CFrame = cf * CFrame.new(0, 20, 0), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.Brick, Parent = folder })
	deco({ Name = "TowerTrim", Size = Vector3.new(15, 1.4, 15), CFrame = cf * CFrame.new(0, 28, 0), Color = BRASS, Material = Enum.Material.Metal, Parent = folder })
	roof(folder, cf * CFrame.new(0, 40, 0), 16, 16, 10, COPPER:Lerp(Color3.fromRGB(80, 160, 130), 0.5), Enum.Material.Metal)
	local face = deco({ Name = "ClockFace", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 11, 11), CFrame = cf * CFrame.new(0, 34, -7.2) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(250, 240, 210), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	deco({ Name = "ClockRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 12.4, 12.4), CFrame = cf * CFrame.new(0, 34, -7.05) * CFrame.Angles(0, math.rad(90), 0), Color = BRASS, Material = Enum.Material.Metal, Parent = folder })
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		deco({ Name = "HourMark", Size = Vector3.new(0.4, 1.2, 0.3), CFrame = cf * CFrame.new(math.sin(a) * 4.4, 34 + math.cos(a) * 4.4, -7.6) * CFrame.Angles(0, 0, -a), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	end
	deco({ Name = "HourHand", Size = Vector3.new(0.5, 3.2, 0.3), CFrame = cf * CFrame.new(0.9, 35.2, -7.8) * CFrame.Angles(0, 0, math.rad(-40)), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "MinuteHand", Size = Vector3.new(0.4, 4.6, 0.3), CFrame = cf * CFrame.new(-1.2, 35.8, -7.9) * CFrame.Angles(0, 0, math.rad(30)), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	light(face, Color3.fromRGB(255, 230, 170), 30, 1.2)
	for _, sx in ipairs({ -1, 1 }) do
		gear(folder, cf * CFrame.new(sx * 7.4, 14, 0), 4, BRASS)
	end
	deco({ Name = "TowerDoor", Size = Vector3.new(5, 8, 0.5), CFrame = cf * CFrame.new(0, 4, -7.2), Color = Color3.fromRGB(90, 60, 40), Material = Enum.Material.WoodPlanks, Parent = folder })
end

function SETPIECES.GearWorks(folder, o, rng)
	deco({ Name = "Platform", Size = Vector3.new(34, 1, 44), Position = o + Vector3.new(0, 0.5, 0), Color = IRON, Material = Enum.Material.DiamondPlate, Parent = folder })
	-- a wall of big interlocking gears
	local gears = { { 0, 12, -14, 10 }, { 0, 20, 4, 7 }, { 0, 9, 14, 6 }, { 0, 28, -6, 5 } }
	for i, g in ipairs(gears) do
		gear(folder, CFrame.new(o + Vector3.new(g[1], g[2], g[3])), g[4], if i % 2 == 0 then COPPER else BRASS)
	end
	for _, sz in ipairs({ -18, 18 }) do
		PROPS.SteamPipe(folder, o + Vector3.new(8, 1, sz), 1.2, rng)
		PROPS.Lamppost(folder, o + Vector3.new(-12, 1, sz), 1)
	end
	local furnace = deco({ Name = "Furnace", Size = Vector3.new(8, 8, 8), Position = o + Vector3.new(-8, 5, 0), Color = IRON, Material = Enum.Material.Metal, Parent = folder })
	local fire = deco({ Name = "FurnaceFire", Size = Vector3.new(0.4, 3, 4), Position = furnace.Position + Vector3.new(4.1, -1, 0), Color = Color3.fromRGB(255, 130, 40), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(fire, Color3.fromRGB(255, 150, 60), 24, 1.6)
end

function SETPIECES.DataCoreHub(folder, o, rng)
	deco({ Name = "HubFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 46, 46), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.3, 0))), Color = CYBER_DARK, Material = Enum.Material.Metal, Parent = folder })
	for r = 1, 3 do
		deco({ Name = "HubRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, r * 14, r * 14), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.25, 0))), Color = NEON[r], Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		deco({ Name = "HubRingFill", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.75, r * 14 - 1.4, r * 14 - 1.4), CFrame = cylinderAlongY(CFrame.new(o + Vector3.new(0, 0.26, 0))), Color = CYBER_DARK, Material = Enum.Material.Metal, Parent = folder })
	end
	local core = deco({ Name = "BigCore", Shape = Enum.PartType.Ball, Size = Vector3.one * 9, Position = o + Vector3.new(0, 16, 0), Color = NEON[2], Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(core, NEON[2], 45, 2)
	particles(core, { Color = ColorSequence.new(NEON[2], NEON[1]), LightEmission = 1, Size = NumberSequence.new(0.6, 0), Lifetime = NumberRange.new(1, 2), Rate = 25, Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(180, 180) })
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local p = o + Vector3.new(math.cos(a) * 14, 0, math.sin(a) * 14)
		PROPS.DataPillar(folder, p, 1.3, rng)
		local top = p + Vector3.new(0, 18, 0)
		deco({ Name = "DataBeam", Size = Vector3.new(0.5, 0.5, (core.Position - top).Magnitude), CFrame = CFrame.lookAt((core.Position + top) / 2, core.Position), Color = NEON[1], Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, Parent = folder })
	end
end

function SETPIECES.NeonPyramid(folder, o, rng)
	for i = 0, 5 do
		local w = 40 - i * 6.5
		deco({ Name = "PyramidStep", Size = Vector3.new(w, 3, w), Position = o + Vector3.new(0, 1.5 + i * 3, 0), Color = CYBER_DARK, Material = Enum.Material.Glass, Reflectance = 0.2, Parent = folder })
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "StepEdge", Size = Vector3.new(0.3, 0.3, w + 0.2), Position = o + Vector3.new(sx * w / 2, 3 + i * 3, 0), Color = NEON[(i % 3) + 1], Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
			deco({ Name = "StepEdge", Size = Vector3.new(w + 0.2, 0.3, 0.3), Position = o + Vector3.new(0, 3 + i * 3, sx * w / 2), Color = NEON[(i % 3) + 1], Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		end
	end
	local crystal = deco({ Name = "TopCrystal", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(o + Vector3.new(0, 24, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = NEON[1], Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	light(crystal, NEON[1], 40, 2)
	local beam = deco({ Name = "SkyBeam", Size = Vector3.new(1.5, 140, 1.5), Position = o + Vector3.new(0, 96, 0), Color = NEON[1], Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, Parent = folder })
	beam.Transparency = 0.5
end

--------------------------------------------------------------------------------
-- Zones 13-20: Jungle Ruins, Crystal Caverns, Toy Town, Aurora Tundra,
-- Sakura Gardens, Infernal Abyss, Galaxy Rift and Rainbow Realm
--------------------------------------------------------------------------------
local TOY = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 205, 60), Color3.fromRGB(80, 170, 255), Color3.fromRGB(90, 210, 110), Color3.fromRGB(190, 110, 255) }
local SAKURA_PINK = Color3.fromRGB(255, 185, 215)
local TORII_RED = Color3.fromRGB(200, 50, 45)

function PROPS.PalmTree(folder, pos, s, rng)
	local p = pos
	local lean = Vector3.new(rng:NextNumber(-0.25, 0.25), 1, rng:NextNumber(-0.25, 0.25)).Unit
	for i = 1, 6 do
		local nextP = p + (lean + Vector3.new(0, 0, 0)) * 2.4 * s
		deco({ Name = "PalmTrunk", Size = Vector3.new(1.4 * s, 1.4 * s, 2.8 * s), CFrame = CFrame.lookAt((p + nextP) / 2, nextP), Color = Color3.fromRGB(150, 110, 70):Lerp(Color3.fromRGB(120, 85, 55), i % 2), Material = Enum.Material.Wood, Parent = folder })
		p = nextP
	end
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		local dir = Vector3.new(math.cos(a), -0.35, math.sin(a)).Unit
		local tip = p + dir * 7 * s
		deco({ Name = "PalmLeaf", Size = Vector3.new(2.4 * s, 0.25, 7.5 * s), CFrame = CFrame.lookAt((p + tip) / 2, tip), Color = Color3.fromRGB(60, 160, 70):Lerp(Color3.fromRGB(90, 190, 80), rng:NextNumber()), Material = Enum.Material.Grass, Parent = folder })
	end
	for i = 1, 3 do
		deco({ Name = "Coconut", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1 * s, Position = p + Vector3.new(math.cos(i * 2.1) * 0.8, -0.8, math.sin(i * 2.1) * 0.8) * s, Color = Color3.fromRGB(110, 75, 40), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
end

function PROPS.Totem(folder, pos, s, rng)
	local colors = { Color3.fromRGB(190, 70, 50), Color3.fromRGB(60, 140, 120), Color3.fromRGB(220, 170, 60) }
	local y = 0
	for i = 1, 3 do
		local h = 3.4 * s
		local c = colors[(i + rng:NextInteger(0, 2)) % 3 + 1]
		deco({ Name = "TotemBlock", Size = Vector3.new(3 * s, h, 3 * s), Position = pos + Vector3.new(0, y + h / 2, 0), Color = c, Material = Enum.Material.Wood, Parent = folder })
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "TotemEye", Size = Vector3.new(0.7, 0.5, 0.2) * s, Position = pos + Vector3.new(sx * 0.7 * s, y + h * 0.65, -1.55 * s), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = folder })
		end
		deco({ Name = "TotemMouth", Size = Vector3.new(1.8, 0.5, 0.2) * s, Position = pos + Vector3.new(0, y + h * 0.25, -1.55 * s), Color = BLACK, Material = Enum.Material.SmoothPlastic, Parent = folder })
		y += h
	end
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "TotemWing", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.6, 2.2, 3) * s, CFrame = CFrame.new(pos + Vector3.new(sx * 2.6 * s, y - 1.5 * s, 0)) * CFrame.Angles(0, math.rad(90 * sx), 0), Color = colors[3], Material = Enum.Material.Wood, Parent = folder })
	end
end

function PROPS.ToyBlocks(folder, pos, s, rng)
	local y = 0
	for i = 1, rng:NextInteger(2, 4) do
		local size = rng:NextNumber(3, 4.5) * s
		local b = deco({ Name = "ToyBlock", Size = Vector3.one * size, CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-0.6, 0.6), y + size / 2, rng:NextNumber(-0.6, 0.6))) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), Color = TOY[rng:NextInteger(1, #TOY)], Material = Enum.Material.SmoothPlastic, Parent = folder })
		local letters = { "A", "B", "C", "1", "2", "3", "★" }
		surfaceText(b, Enum.NormalId.Front, letters[rng:NextInteger(1, #letters)], WHITE)
		y += size
	end
end

function PROPS.GiantBall(folder, pos, s, rng)
	local size = rng:NextNumber(5, 8) * s
	local c = pos + Vector3.new(0, size / 2, 0)
	deco({ Name = "Ball", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = c, Color = TOY[rng:NextInteger(1, #TOY)], Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "BallStripe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(size * 0.3, size * 1.01, size * 1.01), CFrame = CFrame.new(c) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "BallStar", Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.3, Position = c + Vector3.new(0, size * 0.36, 0), Color = TOY[rng:NextInteger(1, #TOY)], Material = Enum.Material.SmoothPlastic, Parent = folder })
end

function PROPS.CherryTree(folder, pos, s, rng)
	local bark = Color3.fromRGB(90, 55, 50)
	local trunkH = rng:NextNumber(6, 8) * s
	deco({ Name = "Trunk", Size = Vector3.new(1.6 * s, trunkH, 1.6 * s), CFrame = CFrame.new(pos + Vector3.new(0, trunkH / 2, 0)) * CFrame.Angles(0, 0, rng:NextNumber(-0.1, 0.1)), Color = bark, Material = Enum.Material.Wood, Parent = folder })
	local top = pos + Vector3.new(0, trunkH, 0)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber(0, 1)
		local tip = top + Vector3.new(math.cos(a) * 3.5, 2, math.sin(a) * 3.5) * s
		deco({ Name = "Branch", Size = Vector3.new(0.7 * s, 0.7 * s, (tip - top).Magnitude), CFrame = CFrame.lookAt((top + tip) / 2, tip), Color = bark, Material = Enum.Material.Wood, Parent = folder })
		deco({ Name = "Blossom", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(5, 6.5) * s, Position = tip + Vector3.new(0, 1, 0), Color = SAKURA_PINK:Lerp(WHITE, rng:NextNumber(0, 0.35)), Material = Enum.Material.SmoothPlastic, Parent = folder })
	end
	deco({ Name = "Blossom", Shape = Enum.PartType.Ball, Size = Vector3.one * 7 * s, Position = top + Vector3.new(0, 3.5 * s, 0), Color = SAKURA_PINK, Material = Enum.Material.SmoothPlastic, Parent = folder })
	for _ = 1, 4 do
		deco({ Name = "FallenPetal", Size = Vector3.new(0.6, 0.08, 0.4), CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-4, 4), 0.06, rng:NextNumber(-4, 4))) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = SAKURA_PINK, Material = Enum.Material.SmoothPlastic, CastShadow = false, Parent = folder })
	end
end

function PROPS.StoneLantern(folder, pos, s, rng)
	local stone = Color3.fromRGB(150, 150, 145)
	deco({ Name = "LanternBase", Size = Vector3.new(2.4, 0.8, 2.4) * s, Position = pos + Vector3.new(0, 0.4 * s, 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
	deco({ Name = "LanternPost", Size = Vector3.new(0.9, 3, 0.9) * s, Position = pos + Vector3.new(0, 2.3 * s, 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
	local box = deco({ Name = "LanternBox", Size = Vector3.new(1.8, 1.6, 1.8) * s, Position = pos + Vector3.new(0, 4.6 * s, 0), Color = Color3.fromRGB(255, 210, 140), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	deco({ Name = "LanternRoof", Shape = Enum.PartType.Wedge, Size = Vector3.new(3, 1, 1.5) * s, CFrame = CFrame.new(pos + Vector3.new(0, 5.9 * s, -0.75 * s)), Color = stone, Material = Enum.Material.Slate, Parent = folder })
	deco({ Name = "LanternRoof", Shape = Enum.PartType.Wedge, Size = Vector3.new(3, 1, 1.5) * s, CFrame = CFrame.new(pos + Vector3.new(0, 5.9 * s, 0.75 * s)) * CFrame.Angles(0, math.pi, 0), Color = stone, Material = Enum.Material.Slate, Parent = folder })
	if rng:NextNumber() < 0.35 then
		light(box, Color3.fromRGB(255, 190, 120), 16, 1)
	end
end

CLUTTER.Jungle = CLUTTER.Forest
CLUTTER.Crystal = CLUTTER.Void
CLUTTER.Toy = CLUTTER.Candy
CLUTTER.Aurora = CLUTTER.Snow
CLUTTER.Sakura = function(folder, p, rng)
	deco({ Name = "Petal", Size = Vector3.new(0.6, 0.08, 0.45), CFrame = CFrame.new(p + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = SAKURA_PINK:Lerp(WHITE, rng:NextNumber(0, 0.4)), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
end
CLUTTER.Inferno = CLUTTER.Volcano
CLUTTER.Galaxy = CLUTTER.Void
CLUTTER.Rainbow = CLUTTER.Candy

AMBIENT.Petals = { Y = 45, Props = { Color = ColorSequence.new(SAKURA_PINK, WHITE), LightEmission = 0.2, Size = NumberSequence.new(0.45), Lifetime = NumberRange.new(10, 14), Rate = 45, Speed = NumberRange.new(0, 1), RotSpeed = NumberRange.new(-90, 90), Rotation = NumberRange.new(0, 360), Acceleration = Vector3.new(2, -3, 1), EmissionDirection = Enum.NormalId.Bottom } }
EXTRA_AMBIENT.Jungle = "Fireflies"
EXTRA_AMBIENT.Crystal = "Stardust"
EXTRA_AMBIENT.Aurora = "Stardust"
EXTRA_AMBIENT.Inferno = "Ash"
EXTRA_AMBIENT.Galaxy = "Motes"
EXTRA_AMBIENT.Rainbow = "Feathers"

WALL_TRIMS.Jungle = WALL_TRIMS.Forest
WALL_TRIMS.Crystal = WALL_TRIMS.Void
WALL_TRIMS.Toy = WALL_TRIMS.Candy
WALL_TRIMS.Aurora = WALL_TRIMS.Snow
WALL_TRIMS.Sakura = function(folder, x, z, side, rng)
	if rng:NextNumber() < 0.5 then
		local lamp = deco({ Name = "PaperLantern", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2.6, 2), Position = Vector3.new(x - side * 1.4, rng:NextNumber(20, 30), z), Color = Color3.fromRGB(255, 120, 100), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		lamp.Transparency = 0.1
	end
	deco({ Name = "WallBeam", Size = Vector3.new(0.4, 0.8, 16.2), Position = Vector3.new(x - side * 0.2, 12, z), Color = Color3.fromRGB(70, 45, 40), Material = Enum.Material.Wood, CanCollide = false, Parent = folder })
end
WALL_TRIMS.Inferno = WALL_TRIMS.Volcano
WALL_TRIMS.Galaxy = WALL_TRIMS.Void
WALL_TRIMS.Rainbow = WALL_TRIMS.Heaven

BACKDROPS.Jungle = { Base = Color3.fromRGB(50, 110, 55), Top = Color3.fromRGB(80, 150, 70), Material = Enum.Material.Grass, MinH = 80, MaxH = 150, Trees = true }
BACKDROPS.Crystal = { Base = Color3.fromRGB(45, 38, 80), Top = Color3.fromRGB(110, 90, 190), Material = Enum.Material.Glass, MinH = 90, MaxH = 170 }
BACKDROPS.Toy = { Base = Color3.fromRGB(255, 140, 140), Top = Color3.fromRGB(255, 230, 120), Material = Enum.Material.SmoothPlastic, MinH = 50, MaxH = 100, Flat = true }
BACKDROPS.Aurora = BACKDROPS.Snow
BACKDROPS.Sakura = { Base = Color3.fromRGB(95, 130, 90), Top = Color3.fromRGB(250, 250, 255), Material = Enum.Material.Grass, MinH = 90, MaxH = 170, Cap = Enum.Material.Snow }
BACKDROPS.Inferno = BACKDROPS.Volcano
BACKDROPS.Galaxy = BACKDROPS.Void
BACKDROPS.Rainbow = BACKDROPS.Heaven

SKY.Aurora = SKY.Snow
SKY.Toy = SKY.Candy
SKY.Galaxy = SKY.Void
function SKY.Rainbow(folder, centerZ, rng)
	SKY.Candy(folder, centerZ, rng)
	SKY.Heaven(folder, centerZ, rng)
end
function SKY.Sakura(folder, centerZ, rng)
	-- a big soft sunset sun behind a snowy mountain
	local sun = deco({ Name = "SakuraSun", Shape = Enum.PartType.Ball, Size = Vector3.one * 70, Position = Vector3.new(140, 160, centerZ + 300), Color = Color3.fromRGB(255, 170, 140), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	sun.Transparency = 0.1
end
function SKY.Inferno(folder, centerZ, rng)
	-- burning meteors streaking across a red sky
	for _ = 1, 10 do
		local p = Vector3.new(rng:NextNumber(-380, 380), rng:NextNumber(80, 150), centerZ + rng:NextNumber(-140, 140))
		local dir = Vector3.new(rng:NextNumber(-1, 1), -0.6, rng:NextNumber(-1, 1)).Unit
		deco({ Name = "Meteor", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(3, 6), Position = p, Color = Color3.fromRGB(255, 140, 50), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		local tail = deco({ Name = "MeteorTail", Size = Vector3.new(2, 2, 26), CFrame = CFrame.lookAt(p - dir * 13, p), Color = Color3.fromRGB(255, 90, 30), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
		tail.Transparency = 0.5
	end
end
function SKY.Jungle(folder, centerZ, rng)
	-- a flock of bright parrots
	for _ = 1, 12 do
		local p = Vector3.new(rng:NextNumber(-350, 350), rng:NextNumber(40, 80), centerZ + rng:NextNumber(-130, 130))
		local col = ({ Color3.fromRGB(230, 50, 50), Color3.fromRGB(60, 150, 255), Color3.fromRGB(255, 210, 50) })[rng:NextInteger(1, 3)]
		deco({ Name = "Parrot", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 2.2), Position = p, Color = col, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "ParrotWing", Size = Vector3.new(2.2, 0.2, 1), Position = p + Vector3.new(sx * 1.5, 0.3, 0), Color = col:Lerp(Color3.fromRGB(60, 200, 90), 0.4), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
		end
	end
end

SETPIECE_SPOTS.Jungle = { { "Ruins", 360, 95, 34 }, { "Waterfall", 385, -60, 36 }, { "Treehouse", -350, 30, 38 } }
SETPIECE_SPOTS.Crystal = { { "RuneCircle", -360, 30, 36 }, { "IceFalls", 385, 35, 36 } }
SETPIECE_SPOTS.Toy = { { "GingerbreadHouse", -360, 40, 36 }, { "RainbowBridge", 365, -70, 38 } }
SETPIECE_SPOTS.Aurora = { { "SnowFort", -350, 100, 30 }, { "Cabin", -360, -70, 34 }, { "IceFalls", 385, 35, 36 } }
SETPIECE_SPOTS.Sakura = { { "Pagoda", -355, 20, 38 }, { "ToriiPath", 365, -40, 40 } }
SETPIECE_SPOTS.Inferno = { { "LavaLake", 360, -85, 44 }, { "Forge", 360, 95, 32 }, { "Basalt", -365, -20, 38 } }
SETPIECE_SPOTS.Galaxy = { { "Portal", 360, 100, 30 }, { "Observatory", -350, -100, 30 }, { "SkyStairs", 370, -60, 32 } }
SETPIECE_SPOTS.Rainbow = { { "RainbowBridge", 365, -70, 38 }, { "SkyTemple", -355, 20, 40 } }

function SETPIECES.Pagoda(folder, o, rng)
	local cf = CFrame.lookAt(o, o + Vector3.new(if o.X < 0 then 1 else -1, 0, 0))
	local wood = Color3.fromRGB(180, 50, 45)
	local roofC = Color3.fromRGB(50, 60, 70)
	deco({ Name = "PagodaBase", Size = Vector3.new(24, 2, 24), CFrame = cf * CFrame.new(0, 1, 0), Color = Color3.fromRGB(160, 155, 150), Material = Enum.Material.Slate, Parent = folder })
	local y = 2
	for i = 0, 3 do
		local w = 16 - i * 3
		local h = 7 - i * 0.8
		deco({ Name = "PagodaFloor", Size = Vector3.new(w, h, w), CFrame = cf * CFrame.new(0, y + h / 2, 0), Color = wood, Material = Enum.Material.Wood, Parent = folder })
		deco({ Name = "PagodaWindow", Size = Vector3.new(w * 0.5, h * 0.4, 0.3), CFrame = cf * CFrame.new(0, y + h * 0.55, -w / 2 - 0.1), Color = Color3.fromRGB(255, 220, 150), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		y += h
		roof(folder, cf * CFrame.new(0, y, 0), w + 6, w + 6, 2.4, roofC, Enum.Material.Slate)
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "EaveTip", Shape = Enum.PartType.Wedge, Size = Vector3.new(1, 1.4, 2), CFrame = cf * CFrame.new(sx * (w / 2 + 3), y + 0.6, -(w / 2 + 2)), Color = roofC, Material = Enum.Material.Slate, Parent = folder })
		end
		y += 2.4
	end
	deco({ Name = "Spire", Size = Vector3.new(0.6, 6, 0.6), CFrame = cf * CFrame.new(0, y + 3, 0), Color = Color3.fromRGB(230, 180, 60), Material = Enum.Material.Metal, Parent = folder })
	for _, sx in ipairs({ -1, 1 }) do
		PROPS.StoneLantern(folder, (cf * CFrame.new(sx * 9, 2, -14)).Position, 1, rng)
		PROPS.CherryTree(folder, (cf * CFrame.new(sx * 16, 0, -6)).Position, 1.1, rng)
	end
end

function SETPIECES.ToriiPath(folder, o, rng)
	-- a line of red torii gates over a stone path
	for i = 0, 4 do
		local c = o + Vector3.new(0, 0, -30 + i * 15)
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "ToriiPost", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 1.4, 1.4), CFrame = cylinderAlongY(CFrame.new(c + Vector3.new(sx * 5, 7, 0))), Color = TORII_RED, Material = Enum.Material.SmoothPlastic, Parent = folder })
		end
		deco({ Name = "ToriiTop", Size = Vector3.new(15, 1.2, 1.8), Position = c + Vector3.new(0, 14.4, 0), Color = Color3.fromRGB(40, 35, 35), Material = Enum.Material.Wood, Parent = folder })
		deco({ Name = "ToriiBeam", Size = Vector3.new(12, 0.9, 1.2), Position = c + Vector3.new(0, 11.8, 0), Color = TORII_RED, Material = Enum.Material.SmoothPlastic, Parent = folder })
		deco({ Name = "PathStone", Size = Vector3.new(6, 0.3, 4), Position = c + Vector3.new(0, 0.15, 0), Color = Color3.fromRGB(165, 160, 155), Material = Enum.Material.Slate, Parent = folder })
	end
	for _, sx in ipairs({ -1, 1 }) do
		PROPS.CherryTree(folder, o + Vector3.new(sx * 13, 0, 0), 1.2, rng)
	end
end

--------------------------------------------------------------------------------
-- Player bases
-- Built in the plot's local space: local -Z is the open front (facing the road).
--------------------------------------------------------------------------------
local function fenceLine(parent, at, x1, z1, x2, z2, color)
	local a = Vector3.new(x1, 0, z1)
	local b = Vector3.new(x2, 0, z2)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local posts = math.max(1, math.floor(length * PLOT_SCALE / 6))
	for i = 0, posts do
		local p = a + dir * (length * i / posts)
		deco({ Name = "FencePost", Size = Vector3.new(0.8, 3.6, 0.8), CFrame = at(p.X, 2.1, p.Z), Color = color, Material = Enum.Material.Wood, Parent = parent })
		deco({ Name = "PostCap", Size = Vector3.new(1.1, 0.4, 1.1), CFrame = at(p.X, 4.1, p.Z), Color = color:Lerp(WHITE, 0.3), Material = Enum.Material.Wood, Parent = parent })
	end
	local mid = (a + b) / 2
	local yaw = math.atan2(-dir.X, -dir.Z)
	for _, y in ipairs({ 1.6, 3.1 }) do
		part({ Name = "FenceRail", Size = Vector3.new(0.35, 0.5, length * PLOT_SCALE), CFrame = at(mid.X, y, mid.Z) * CFrame.Angles(0, yaw, 0), Color = color:Lerp(WHITE, 0.15), Material = Enum.Material.Wood, CanQuery = false, Parent = parent })
	end
end

local PLOT_SOLID = { Floor = true, PenGrass = true, Treadmill = true, EdgeRamp = true }

local function buildPlot(plotsFolder, index, center, frontDir)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model.Parent = plotsFolder

	local accent = PLOT_ACCENTS[index] or PLOT_ACCENTS[1]
	local accentDark = accent:Lerp(BLACK, 0.4)
	local cf = CFrame.lookAt(center, center + frontDir)
	local K = PLOT_SCALE
	local W = PLOT_WIDTH / 2 / K -- half-width on the layout grid (half-depth is 30)
	local function at(x, y, z)
		return cf * CFrame.new(x * K, y, z * K)
	end

	local plot = {
		Index = index,
		Model = model,
		Center = center,
		CFrame = cf,
		FrontDir = frontDir,
		HalfWidth = PLOT_WIDTH / 2,
		HalfDepth = PLOT_SIZE / 2,
		Accent = accent,
		SlotPads = {},
		SlotTops = {},
		SignLabels = {},
	}

	-- Floor and stone border
	part({ Name = "Floor", Size = Vector3.new(PLOT_WIDTH, 0.4, PLOT_SIZE), CFrame = at(0, 0.2, 0), Color = Color3.fromRGB(200, 162, 115), Material = Enum.Material.WoodPlanks, Parent = model })
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Border", Size = Vector3.new(PLOT_WIDTH + 1.2, 0.7, 1.2), CFrame = at(0, 0.35, side * (30 - 0.1 / K)), Color = STONE, Material = Enum.Material.Cobblestone, Parent = model })
		part({ Name = "Border", Size = Vector3.new(1.2, 0.7, PLOT_SIZE), CFrame = at(side * (W - 0.1 / K), 0.35, 0), Color = STONE, Material = Enum.Material.Cobblestone, Parent = model })
	end
	part({ Name = "Carpet", Size = Vector3.new(6 * K, 0.1, 33 * K), CFrame = at(0, 0.45, -13), Color = accent:Lerp(BLACK, 0.15), Material = Enum.Material.Fabric, Parent = model })
	part({ Name = "CarpetTrim", Size = Vector3.new(7 * K, 0.08, 33 * K), CFrame = at(0, 0.43, -13), Color = Color3.fromRGB(255, 215, 90), Material = Enum.Material.Fabric, Parent = model })

	-- Outer fence (front has an opening for the gate)
	local fenceColor = accentDark:Lerp(WOOD, 0.5)
	local e = 30 - 0.4 / K -- front/back fence line
	local ex = W - 0.4 / K -- side fence line
	fenceLine(model, at, -ex, e, ex, e, fenceColor)
	fenceLine(model, at, -ex, -e, -ex, e, fenceColor)
	fenceLine(model, at, ex, -e, ex, e, fenceColor)
	fenceLine(model, at, -ex, -e, -8.5, -e, fenceColor)
	fenceLine(model, at, 8.5, -e, ex, -e, fenceColor)

	-- Corner pillars with lanterns
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			deco({ Name = "Pillar", Size = Vector3.new(2.2, 6, 2.2), CFrame = at(sx * ex, 3, sz * e), Color = STONE, Material = Enum.Material.Cobblestone, Parent = model })
			deco({ Name = "PillarCap", Size = Vector3.new(2.8, 0.6, 2.8), CFrame = at(sx * ex, 6.3, sz * e), Color = accent, Material = Enum.Material.SmoothPlastic, Parent = model })
			lantern(model, at(sx * ex, 7.2, sz * e).Position, WARM_LIGHT, 14)
		end
	end

	-- Entrance gate with the owner's name
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "GatePillar", Size = Vector3.new(2, 11, 2), CFrame = at(sx * 8.5, 5.5, -e), Color = STONE, Material = Enum.Material.Cobblestone, Parent = model })
		deco({ Name = "GateCap", Size = Vector3.new(2.6, 0.8, 2.6), CFrame = at(sx * 8.5, 11.4, -e), Color = accent, Material = Enum.Material.SmoothPlastic, Parent = model })
		lantern(model, at(sx * 8.5, 12.4, -e).Position, accent, 18)
	end
	local gateSign = deco({ Name = "GateSign", Size = Vector3.new(19 * K, 3.4, 0.8), CFrame = at(0, 9.6, -e), Color = Color3.fromRGB(55, 40, 32), Material = Enum.Material.Wood, Parent = model })
	deco({ Name = "GateSignTrim", Size = Vector3.new(19.6 * K, 4, 0.6), CFrame = at(0, 9.6, -e + 0.2 / K), Color = accent, Material = Enum.Material.SmoothPlastic, Parent = model })
	table.insert(plot.SignLabels, surfaceText(gateSign, Enum.NormalId.Front, "Empty Base", WHITE))

	-- Lamp posts outside the gate
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "LampPost", Size = Vector3.new(0.6, 8, 0.6), CFrame = at(sx * 12, 4, -e - 3), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal, Parent = model })
		lantern(model, at(sx * 12, 8.4, -e - 3).Position, WARM_LIGHT, 20)
	end

	-- Open pet pen across the whole back half: grass, a low picket fence with a
	-- walk-in gap, no roof and no pedestals. Eggs and pets sit right on the grass.
	local PEN_FRONT = 3.5
	local penDepth = e - PEN_FRONT
	part({ Name = "PenGrass", Size = Vector3.new((2 * ex - 1) * K, 0.14, penDepth * K), CFrame = at(0, 0.47, PEN_FRONT + penDepth / 2), Color = Color3.fromRGB(104, 178, 76), Material = Enum.Material.Grass, Parent = model })
	part({ Name = "PenGrassEdge", Size = Vector3.new((2 * ex - 0.4) * K, 0.1, 1.2), CFrame = at(0, 0.45, PEN_FRONT), Color = Color3.fromRGB(80, 140, 60), Material = Enum.Material.Grass, Parent = model })
	-- The area pets roam in (the client walks them around inside this box)
	plot.PenCFrame = at(0, 0.54, PEN_FRONT + penDepth / 2)
	plot.PenHalfSize = Vector2.new((ex - 1.5) * K, (penDepth / 2 - 0.8) * K)
	local picket = Color3.fromRGB(250, 245, 235)
	for _, sx in ipairs({ -1, 1 }) do
		local from, to = sx * 6, sx * (ex - 1)
		local count = math.floor(math.abs(to - from) * K / 1.6)
		for i = 0, count do
			local x = from + (to - from) * i / count
			deco({ Name = "Picket", Size = Vector3.new(0.5, 2.4, 0.3), CFrame = at(x, 1.6, PEN_FRONT), Color = picket, Material = Enum.Material.SmoothPlastic, Parent = model })
		end
		part({ Name = "PenRail", Size = Vector3.new(math.abs(to - from) * K, 0.3, 0.25), CFrame = at((from + to) / 2, 1.9, PEN_FRONT - 0.3 / K), Color = picket:Lerp(accent, 0.25), Material = Enum.Material.SmoothPlastic, CanQuery = false, Parent = model })
		-- pen gate posts topped with paw lanterns
		deco({ Name = "PenGatePost", Size = Vector3.new(1.2, 4.6, 1.2), CFrame = at(sx * 6, 2.7, PEN_FRONT), Color = accent, Material = Enum.Material.SmoothPlastic, Parent = model })
		lantern(model, at(sx * 6, 5.4, PEN_FRONT).Position, WARM_LIGHT, 12)
	end
	local penSign = deco({ Name = "PenSign", Size = Vector3.new(7 * K, 1.6, 0.3), CFrame = at(-11, 3.4, PEN_FRONT - 0.4 / K), Color = Color3.fromRGB(55, 40, 32), Material = Enum.Material.Wood, Parent = model })
	surfaceText(penSign, Enum.NormalId.Back, "🐾 PET PEN", Color3.fromRGB(255, 225, 120))
	surfaceText(penSign, Enum.NormalId.Front, "🐾 PET PEN", Color3.fromRGB(255, 225, 120))

	-- A few cozy props tucked into the pen corners
	local hay = Color3.fromRGB(226, 190, 90)
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "HayBale", Size = Vector3.new(3.4, 2, 2.2), CFrame = at(sx * (ex - 2.6), 1.5, PEN_FRONT + 2.3), Color = hay, Material = Enum.Material.Grass, Parent = model })
		deco({ Name = "HayBand", Size = Vector3.new(0.25, 2.05, 2.25), CFrame = at(sx * (ex - 2.6), 1.5, PEN_FRONT + 2.3), Color = Color3.fromRGB(150, 95, 50), Material = Enum.Material.Fabric, Parent = model })
		for i, c in ipairs({ Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 225, 90), Color3.fromRGB(170, 130, 255) }) do
			deco({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, CFrame = at(sx * (ex - 1.2 - i * 1.1), 1.1, e - 1.4 - (i % 2) * 0.9), Color = c, Material = Enum.Material.SmoothPlastic, Parent = model })
		end
	end
	local bowl = deco({ Name = "WaterBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 3.4, 3.4), CFrame = cylinderAlongY(at(0, 0.85, PEN_FRONT + 2.2)), Color = accent, Material = Enum.Material.SmoothPlastic, Parent = model })
	deco({ Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 2.8, 2.8), CFrame = cylinderAlongY(at(0, 1.2, PEN_FRONT + 2.2)), Color = Color3.fromRGB(90, 180, 255), Material = Enum.Material.Glass, Transparency = 0.2, Parent = bowl.Parent })

	-- Where eggs and pets sit: 3 loose rows across the pen, slightly scattered
	-- so it looks like a free-roaming pen, not a grid of slots.
	local COLS = 8
	local spotRng = Random.new(1234) -- same layout in every base
	local xEdge = ex - 7
	for slot = 1, Config.MaxSlots do
		local row = (slot - 1) // COLS
		local col = (slot - 1) % COLS
		-- fill the front row first, from the middle outward
		local order = { 4, 5, 3, 6, 2, 7, 1, 8 }
		local c = order[col + 1] - 1
		local x = -xEdge + c * (2 * xEdge / (COLS - 1)) + spotRng:NextNumber(-1.2, 1.2) + (if row == 1 then 1.5 else 0)
		local z = PEN_FRONT + 6 + row * 7.5 + spotRng:NextNumber(-1, 1)
		plot.SlotTops[slot] = at(x, 0.54, z).Position
	end

	-- Back sign on the back fence
	local backSign = deco({ Name = "BackSign", Size = Vector3.new(22 * K, 4.5, 0.6), CFrame = at(0, 7.5, 29), Color = Color3.fromRGB(55, 40, 32), Material = Enum.Material.Wood, Parent = model })
	deco({ Name = "BackSignTrim", Size = Vector3.new(22.6 * K, 5.1, 0.4), CFrame = at(0, 7.5, 29 + 0.3 / K), Color = accent, Material = Enum.Material.SmoothPlastic, Parent = model })
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "BackSignPost", Size = Vector3.new(0.8, 7.5, 0.8), CFrame = at(sx * 12, 3.75, 29.4), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = model })
	end
	table.insert(plot.SignLabels, surfaceText(backSign, Enum.NormalId.Front, "Empty Base", Color3.fromRGB(255, 235, 170)))

	-- Treadmill: step on it and you auto-run in place (the client locks you on
	-- and plays the run animation) until you press Stop.
	local TX = -24
	local beltWidth, beltLength = 6 * K, 13 * K
	local metal = Color3.fromRGB(205, 208, 218)
	deco({ Name = "TreadmillFrame", Size = Vector3.new(beltWidth + 1.6, 0.6, beltLength + 1.6), CFrame = at(TX, 0.7, -6.5), Color = Color3.fromRGB(70, 72, 82), Material = Enum.Material.Metal, Parent = model })
	plot.Treadmill = part({ Name = "Treadmill", Size = Vector3.new(beltWidth, 0.5, beltLength), CFrame = at(TX, 1.1, -6.5), Color = Color3.fromRGB(32, 32, 38), Material = Enum.Material.Rubber, Parent = model })
	plot.TreadDir = frontDir
	local stripes = Instance.new("Folder")
	stripes.Name = "TreadmillStripes"
	stripes:SetAttribute("Length", beltLength)
	stripes.Parent = model
	for i = 0, 7 do
		local z = -6.5 + (i / 8 - 0.5) * 13
		local stripe = deco({ Name = "BeltStripe", Size = Vector3.new(beltWidth - 0.4, 0.06, 0.35), CFrame = at(TX, 1.37, z), Color = accent, Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, Parent = stripes })
		stripe:SetAttribute("Offset", i / 8)
	end
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "Roller", Shape = Enum.PartType.Cylinder, Size = Vector3.new(beltWidth + 1.6, 1.1, 1.1), CFrame = at(TX, 0.9, -6.5 + sx * 6.9), Color = metal, Material = Enum.Material.Metal, Parent = model })
		deco({ Name = "SideRail", Size = Vector3.new(0.35, 0.35, beltLength * 0.75), CFrame = at(TX + sx * (beltWidth / 2 + 0.5) / K, 4.1, -8.5), Color = metal, Material = Enum.Material.Metal, Parent = model })
		deco({ Name = "RailPost", Size = Vector3.new(0.35, 3.2, 0.35), CFrame = at(TX + sx * (beltWidth / 2 + 0.5) / K, 2.6, -3.2), Color = metal, Material = Enum.Material.Metal, Parent = model })
		deco({ Name = "ConsolePost", Size = Vector3.new(0.5, 4.2, 0.5), CFrame = at(TX + sx * (beltWidth / 2 + 0.5) / K, 3.1, -13.4), Color = metal, Material = Enum.Material.Metal, Parent = model })
	end
	-- console at the front end, facing the runner
	local console = deco({ Name = "Console", Size = Vector3.new(beltWidth + 1, 2.4, 0.6), CFrame = at(TX, 5.6, -13.4) * CFrame.Angles(math.rad(-20), 0, 0), Color = Color3.fromRGB(35, 35, 45), Material = Enum.Material.SmoothPlastic, Parent = model })
	-- live screen: tier, multiplier and what you're gaining (GameService fills it in)
	local screen = Instance.new("SurfaceGui")
	screen.Name = "Screen"
	screen.Face = Enum.NormalId.Back
	screen.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	screen.PixelsPerStud = 40
	screen.LightInfluence = 0
	screen.Parent = console
	local screenBg = Instance.new("Frame")
	screenBg.Name = "Bg"
	screenBg.AnchorPoint = Vector2.new(0.5, 0.5)
	screenBg.Position = UDim2.fromScale(0.5, 0.5)
	screenBg.Size = UDim2.fromScale(0.94, 0.86)
	screenBg.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
	screenBg.Parent = screen
	local screenCorner = Instance.new("UICorner")
	screenCorner.CornerRadius = UDim.new(0.12, 0)
	screenCorner.Parent = screenBg
	local screenStroke = Instance.new("UIStroke")
	screenStroke.Name = "Edge"
	screenStroke.Thickness = 4
	screenStroke.Color = accent
	screenStroke.Parent = screenBg
	local function screenLabel(name, y, h, text, color, font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.05, y)
		l.Size = UDim2.fromScale(0.9, h)
		l.Font = font or Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = screenBg
		return l
	end
	screenLabel("TierLabel", 0.06, 0.34, "BASIC TREADMILL", Color3.fromRGB(255, 225, 120))
	screenLabel("MultLabel", 0.4, 0.28, "x1 SPEED", Color3.fromRGB(120, 255, 140))
	screenLabel("StatusLabel", 0.7, 0.24, "Step on to train!", Color3.fromRGB(200, 210, 235), Enum.Font.GothamBold)
	deco({ Name = "ConsoleGlow", Size = Vector3.new(beltWidth + 1.2, 0.2, 0.7), CFrame = at(TX, 4.3, -13.4), Color = accent, Material = Enum.Material.Neon, CastShadow = false, Parent = model })
	local treadSign = deco({ Name = "TreadmillSign", Size = Vector3.new(8 * K, 1.8, 0.4), CFrame = at(TX, 8.6, -13.4), Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.SmoothPlastic, Parent = model })
	surfaceText(treadSign, Enum.NormalId.Front, "🏃 TREADMILL", Color3.fromRGB(255, 225, 120))
	surfaceText(treadSign, Enum.NormalId.Back, "Step on to train Speed!", Color3.fromRGB(255, 225, 120))

	-- Tier looks (GameService paints these for your treadmill tier): neon trim and
	-- glowing skirts along the sides, a light under the belt, one pip per tier on
	-- the console, a spinning halo of orbs for the top tiers and belt particles.
	local dark = Color3.fromRGB(45, 45, 55)
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "TreadTrim", Size = Vector3.new(0.25, 0.25, beltLength + 1.6), CFrame = at(TX + sx * (beltWidth / 2 + 0.8) / K, 1.05, -6.5), Color = accent, Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, Parent = model })
		deco({ Name = "TreadSkirt", Size = Vector3.new(0.15, 0.45, beltLength + 1.2), CFrame = at(TX + sx * (beltWidth / 2 + 0.83) / K, 0.62, -6.5), Color = accent, Material = Enum.Material.Neon, Transparency = 0.45, CastShadow = false, CanCollide = false, Parent = model })
	end
	light(plot.Treadmill, accent, 16, 0).Name = "TreadLight"
	local pips = Instance.new("Folder")
	pips.Name = "TreadPips"
	pips.Parent = model
	local tiers = #Config.TreadmillLevels
	for i = 1, tiers do
		local x = TX + ((i - 0.5) / tiers - 0.5) * (beltWidth - 0.4) / K
		local pip = deco({ Name = "Pip", Shape = Enum.PartType.Ball, Size = Vector3.one * math.min(0.42, (beltWidth - 0.4) / tiers * 0.85), CFrame = at(x, 4.62, -12.95), Color = dark, Material = Enum.Material.SmoothPlastic, CastShadow = false, CanCollide = false, Parent = pips })
		pip:SetAttribute("Tier", i)
	end
	local halo = Instance.new("Folder")
	halo.Name = "TreadHalo"
	local haloCenter = at(TX, 12.6, -6.5).Position
	halo:SetAttribute("Center", haloCenter)
	halo:SetAttribute("Radius", 3.2)
	halo.Parent = model
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		deco({ Name = "HaloOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * (if i % 2 == 0 then 0.8 else 0.5), CFrame = CFrame.new(haloCenter + Vector3.new(math.cos(a), 0, math.sin(a)) * 3.2), Color = accent, Material = Enum.Material.Neon, Transparency = 1, CastShadow = false, CanCollide = false, Parent = halo })
	end
	local tierFx = particles(plot.Treadmill, { Name = "TierFx", Enabled = false, LightEmission = 1, Lifetime = NumberRange.new(1, 2), Rate = 0, SpreadAngle = Vector2.new(15, 15), EmissionDirection = Enum.NormalId.Top, Transparency = NumberSequence.new(0.1, 1) })
	tierFx.Acceleration = Vector3.new(0, 2, 0)
	particles(plot.Treadmill, { Name = "BurstFx", Enabled = false, LightEmission = 1, Lifetime = NumberRange.new(0.8, 1.6), Rate = 0, Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, Size = NumberSequence.new(0.9, 0), Drag = 2 })
	-- speed streaks shooting off the back of the belt while someone trains
	local backEnd = deco({ Name = "TreadBackFx", Size = Vector3.new(beltWidth, 0.2, 0.2), CFrame = at(TX, 1.5, -6.5 + 7.3), Transparency = 1, CastShadow = false, CanCollide = false, Parent = model })
	particles(backEnd, { Name = "RunFx", Enabled = false, Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(235, 235, 245)), LightEmission = 0.3, Lifetime = NumberRange.new(0.3, 0.6), Rate = 30, Speed = NumberRange.new(10, 16), SpreadAngle = Vector2.new(10, 10), EmissionDirection = Enum.NormalId.Back, Size = NumberSequence.new(0.6, 1.4), Transparency = NumberSequence.new(0.5, 1) })

	-- Golden egg statue on the other side
	local SX = 24
	deco({ Name = "StatueBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 7, 7), CFrame = cylinderAlongY(at(SX, 1.1, -6)), Color = Color3.fromRGB(175, 175, 180), Material = Enum.Material.Marble, Parent = model })
	deco({ Name = "StatueRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 7.4, 7.4), CFrame = cylinderAlongY(at(SX, 1.8, -6)), Color = accent, Material = Enum.Material.SmoothPlastic, Parent = model })
	local statue = deco({ Name = "GoldenEgg", Size = Vector3.new(4, 5.4, 4), CFrame = at(SX, 4.7, -6), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Foil, Reflectance = 0.15, Parent = model })
	local statueMesh = Instance.new("SpecialMesh")
	statueMesh.MeshType = Enum.MeshType.Sphere
	statueMesh.Parent = statue
	particles(statue, { Color = ColorSequence.new(Color3.fromRGB(255, 230, 120)), LightEmission = 1, Size = NumberSequence.new(0.3, 0), Lifetime = NumberRange.new(1, 2), Rate = 6, Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(180, 180) })

	-- Flower bushes along the front sides
	local rng = Random.new(index * 77)
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -12, -3 }) do
			local bush = Instance.new("Model")
			bush.Name = "Bush"
			bush.Parent = model
			PROPS.Bush(bush, at(sx * (ex - 3.5), 0.4, z).Position, 1, rng)
		end
	end

	-- Front pads on stone pedestals: Lock, Treadmill Upgrade, Fuse Machine
	local function pad(name, x, color)
		deco({ Name = name .. "Pedestal", Size = Vector3.new(6.4, 0.6, 6.4), CFrame = at(x, 0.7, -22), Color = Color3.fromRGB(165, 165, 170), Material = Enum.Material.Marble, Parent = model })
		local p = part({ Name = name, Size = Vector3.new(5, 0.3, 5), CFrame = at(x, 1.15, -22), Color = color, Material = Enum.Material.Neon, CastShadow = false, Parent = model })
		light(p, color, 8, 0.8)
		return p
	end
	plot.LockButton = pad("LockButton", -32, Color3.fromRGB(80, 150, 255))
	plot.SpeedPad = pad("SpeedPad", -17, Color3.fromRGB(255, 200, 60))
	plot.FusePad = pad("FusePad", 17, Color3.fromRGB(230, 90, 230))

	-- Forcefield bubble, only visible while the base is locked
	plot.Dome = part({
		Name = "LockDome",
		Size = Vector3.new(PLOT_WIDTH + 6, 60, PLOT_SIZE + 6),
		CFrame = at(0, 0, 0),
		Color = Color3.fromRGB(90, 170, 255),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = model,
	})
	local domeMesh = Instance.new("SpecialMesh")
	domeMesh.MeshType = Enum.MeshType.Sphere
	domeMesh.Parent = plot.Dome

	----------------------------------------------------------------------------
	-- Extra detail: a cottage out back, flags, canopies, garden and pen props
	----------------------------------------------------------------------------
	local cream = Color3.fromRGB(250, 242, 228)
	-- cottage behind the back fence, roof in the base's color, facing the pen
	house(model, at(0, 0, 36), 26, 12, 14, { Wall = cream, Roof = accent:Lerp(BLACK, 0.1), Trim = accentDark:Lerp(DARK_WOOD, 0.4) })
	for _, sx in ipairs({ -1, 1 }) do
		local tree = Instance.new("Model")
		tree.Name = "BackyardTree"
		tree.Parent = model
		PROPS.Tree(tree, at(sx * 17, 0, 36).Position, 0.75, rng)
	end

	-- tall flags on the front corner pillars
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "FlagPole", Size = Vector3.new(0.4, 16, 0.4), CFrame = at(sx * ex, 14.6, -e), Color = Color3.fromRGB(230, 230, 235), Material = Enum.Material.Metal, Parent = model })
		deco({ Name = "FlagTop", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = at(sx * ex, 22.8, -e), Color = GOLD_COLOR, Material = Enum.Material.Metal, Parent = model })
		deco({ Name = "Flag", Size = Vector3.new(5, 3.2, 0.15), CFrame = at(sx * ex - sx * 2.6 / K, 20.8, -e), Color = accent, Material = Enum.Material.Fabric, Parent = model })
		deco({ Name = "FlagStripe", Size = Vector3.new(5.02, 0.7, 0.17), CFrame = at(sx * ex - sx * 2.6 / K, 20.8, -e), Color = WHITE, Material = Enum.Material.Fabric, Parent = model })
	end

	-- striped canopy over the treadmill
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			deco({ Name = "CanopyPost", Size = Vector3.new(0.5, 10, 0.5), CFrame = at(TX + sx * 5.2, 5, -6.5 + sz * 7.6), Color = WHITE, Material = Enum.Material.Metal, Parent = model })
		end
	end
	for i = 0, 5 do
		deco({ Name = "Canopy", Size = Vector3.new(15.5 / 6 * K + 0.05, 0.3, 17 * K), CFrame = at(TX - 7.75 + 15.5 / 12 + i * 15.5 / 6, 10.2, -6.5) * CFrame.Angles(0, 0, math.rad(if i < 3 then 8 else -8)), Color = if i % 2 == 0 then accent else WHITE, Material = Enum.Material.Fabric, Parent = model })
	end

	-- crystal arch over the fuse pad, shield posts at the lock pad
	local pink = Color3.fromRGB(230, 90, 230)
	for k = 0, 6 do
		local a = k / 6 * math.pi
		deco({ Name = "FuseArch", Size = Vector3.new(1.1, 1.1, 1.1), CFrame = at(17 - math.cos(a) * 4, 1.2 + math.sin(a) * 7, -22) * CFrame.Angles(0, 0, a), Color = pink, Material = Enum.Material.Neon, CastShadow = false, Parent = model })
	end
	for _, sx in ipairs({ -1, 1 }) do
		local post = deco({ Name = "ShieldPost", Size = Vector3.new(0.8, 4, 0.8), CFrame = at(-32 + sx * 3.4, 2.4, -22), Color = Color3.fromRGB(80, 150, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = model })
		deco({ Name = "ShieldCap", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, CFrame = post.CFrame * CFrame.new(0, 2.3, 0), Color = Color3.fromRGB(180, 220, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = model })
	end

	-- little glowing garden lights along both sides of the carpet
	for _, sx in ipairs({ -1, 1 }) do
		for z = -26, -2, 6 do
			deco({ Name = "GardenLightPost", Size = Vector3.new(0.3, 1.6, 0.3), CFrame = at(sx * 5.2, 1.2, z), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal, Parent = model })
			deco({ Name = "GardenLight", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, CFrame = at(sx * 5.2, 2.2, z), Color = WARM_LIGHT, Material = Enum.Material.Neon, CastShadow = false, Parent = model })
		end
	end

	-- flower planters along the inside of the front fence
	local flowers = { Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 225, 80), WHITE, Color3.fromRGB(170, 130, 255), accent }
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 3 do
			local x = sx * (12 + i * 6)
			if math.abs(x - -32) > 5 and math.abs(x - -17) > 5 and math.abs(x - 17) > 5 then
				deco({ Name = "Planter", Size = Vector3.new(4.2, 1.2, 1.6), CFrame = at(x, 1, -e + 1.6), Color = DARK_WOOD, Material = Enum.Material.WoodPlanks, Parent = model })
				for k = -1, 1 do
					deco({ Name = "PlanterFlower", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = at(x + k * 1.1, 1.95, -e + 1.6), Color = flowers[((i + k) % #flowers) + 1], Material = Enum.Material.SmoothPlastic, Parent = model })
				end
			end
		end
	end

	-- pen props: pet beds, a toy ball and a food trough
	for _, sx in ipairs({ -1, 1 }) do
		local bed = at(sx * (ex - 4.5), 0.75, 18)
		deco({ Name = "PetBed", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 5, 5), CFrame = cylinderAlongY(bed), Color = accent, Material = Enum.Material.Fabric, Parent = model })
		deco({ Name = "PetBedCushion", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 3.8, 3.8), CFrame = cylinderAlongY(bed * CFrame.new(0, 0.2, 0)), Color = cream, Material = Enum.Material.Fabric, Parent = model })
	end
	deco({ Name = "ToyBall", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = at(9, 1.3, 12), Color = accent:Lerp(WHITE, 0.3), Material = Enum.Material.SmoothPlastic, Parent = model })
	deco({ Name = "ToyBallStripe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.65, 1.65), CFrame = at(9, 1.3, 12), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = model })
	deco({ Name = "Trough", Size = Vector3.new(8, 1.4, 2), CFrame = at(0, 1.1, e - 1.6), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = model })
	deco({ Name = "TroughFood", Size = Vector3.new(7.4, 0.3, 1.5), CFrame = at(0, 1.75, e - 1.6), Color = Color3.fromRGB(220, 170, 90), Material = Enum.Material.Grass, Parent = model })

	-- entrance: welcome mat, mailbox and stepping stones out to the street
	deco({ Name = "WelcomeMat", Size = Vector3.new(8, 0.12, 3.4), CFrame = at(0, 0.5, -e + 2.2), Color = accentDark, Material = Enum.Material.Fabric, Parent = model })
	deco({ Name = "WelcomeMatTrim", Size = Vector3.new(8.6, 0.1, 4), CFrame = at(0, 0.48, -e + 2.2), Color = GOLD_COLOR, Material = Enum.Material.Fabric, Parent = model })
	deco({ Name = "MailPost", Size = Vector3.new(0.4, 3.4, 0.4), CFrame = at(-16, 1.7, -e - 2.5), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = model })
	deco({ Name = "Mailbox", Size = Vector3.new(1.3, 1.1, 2.2), CFrame = at(-16, 3.7, -e - 2.5), Color = accent, Material = Enum.Material.Metal, Parent = model })
	deco({ Name = "MailFlag", Size = Vector3.new(0.15, 0.8, 0.3), CFrame = at(-16 + 0.8 / K, 4.1, -e - 2.2), Color = Color3.fromRGB(230, 50, 50), Material = Enum.Material.Metal, Parent = model })
	for i = 1, 3 do
		deco({ Name = "SteppingStone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3.2, 3.2), CFrame = cylinderAlongY(at((i % 2 - 0.5) * 1.5, 0.1, -e - 1.5 - i * 2.6)), Color = STONE, Material = Enum.Material.Slate, Parent = model })
	end

	plot.SpawnCFrame = at(0, 4, -14)
	-- Running in at top speed used to fling you off the stone border, gate posts
	-- and fence rails, so only the floor, pen grass and treadmill are solid now,
	-- and invisible ramps smooth the small step up onto the floor.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not PLOT_SOLID[d.Name] then
			d.CanCollide = false
		end
	end
	local floorTop = 0.4
	for _, edge in ipairs({
		{ Vector3.new(0, 0, PLOT_SIZE / 2), Vector3.zAxis, PLOT_WIDTH },
		{ Vector3.new(0, 0, -PLOT_SIZE / 2), -Vector3.zAxis, PLOT_WIDTH },
		{ Vector3.new(PLOT_WIDTH / 2, 0, 0), Vector3.xAxis, PLOT_SIZE },
		{ Vector3.new(-PLOT_WIDTH / 2, 0, 0), -Vector3.xAxis, PLOT_SIZE },
	}) do
		local mid = center + edge[1] + edge[2] * 1.5 + Vector3.new(0, floorTop / 2, 0)
		part({ Name = "EdgeRamp", Shape = Enum.PartType.Wedge, Size = Vector3.new(edge[3] + 6, floorTop, 3), CFrame = CFrame.lookAt(mid, mid + edge[2]), Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false, Parent = model })
	end
	return plot
end

--------------------------------------------------------------------------------
-- Town
--------------------------------------------------------------------------------
local function streetLamp(folder, position, faceX)
	deco({ Name = "LampBase", Size = Vector3.new(1.4, 1, 1.4), Position = position + Vector3.new(0, 0.5, 0), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "LampPost", Size = Vector3.new(0.6, 11, 0.6), Position = position + Vector3.new(0, 5.5, 0), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal, Parent = folder })
	deco({ Name = "LampArm", Size = Vector3.new(3, 0.4, 0.4), Position = position + Vector3.new(faceX * 1.3, 10.8, 0), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal, Parent = folder })
	local bulb = lantern(folder, position + Vector3.new(faceX * 2.6, 10.1, 0), WARM_LIGHT, 26)
	bulb.Size = Vector3.new(1.4, 1.4, 1.4)
end


--------------------------------------------------------------------------------
-- Leaderboards: 8 boards on the lawn in front of the bases, 4 each side of the
-- main street, facing the bases so you see them as soon as you spawn.
-- LeaderboardService fills in the rows.
--------------------------------------------------------------------------------
local function buildLeaderboards(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = parent
	local z = 86
	local xs = { -160, -120, -80, -40, 40, 80, 120, 160 }
	local W, H = 17, 21
	local rows = Config.LeaderboardSize
	for i, info in ipairs(Config.Leaderboards) do
		local x = xs[i]
		if not x then
			break
		end
		local board = Instance.new("Model")
		board.Name = info.Key
		board.Parent = folder
		-- face the bases (-Z), angled a little toward the main street
		local base = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x * 0.8, 0, z - 40))
		local wood = Color3.fromRGB(55, 40, 70)
		local accent = info.Color
		deco({ Name = "Pedestal", Size = Vector3.new(W + 3, 1.2, 5), CFrame = base * CFrame.new(0, 0.6, 0), Color = Color3.fromRGB(230, 228, 235), Material = Enum.Material.Marble, Parent = board })
		deco({ Name = "PedestalGlow", Size = Vector3.new(W + 3.2, 0.3, 5.2), CFrame = base * CFrame.new(0, 1.3, 0), Color = accent, Material = Enum.Material.Neon, CastShadow = false, Parent = board })
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "BoardPost", Size = Vector3.new(1.4, H + 4, 1.4), CFrame = base * CFrame.new(sx * (W / 2 + 0.7), (H + 4) / 2 + 1.2, 0.4), Color = wood, Material = Enum.Material.Wood, Parent = board })
			deco({ Name = "PostCap", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = base * CFrame.new(sx * (W / 2 + 0.7), H + 6.2, 0.4), Color = accent, Material = Enum.Material.Neon, CastShadow = false, Parent = board })
		end
		local screen = part({ Name = "Screen", Size = Vector3.new(W, H, 0.6), CFrame = base * CFrame.new(0, H / 2 + 3, 0), Color = Color3.fromRGB(24, 20, 36), Material = Enum.Material.SmoothPlastic, CanQuery = false, Parent = board })
		for _, sy in ipairs({ -1, 1 }) do
			deco({ Name = "Frame", Size = Vector3.new(W + 0.6, 0.5, 0.8), CFrame = base * CFrame.new(0, H / 2 + 3 + sy * (H / 2 + 0.2), 0), Color = accent, Material = Enum.Material.Neon, CastShadow = false, Parent = board })
		end
		-- a crown on top
		local crownY = H + 5.2
		deco({ Name = "CrownBand", Size = Vector3.new(5, 1, 1), CFrame = base * CFrame.new(0, crownY, 0.3), Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Metal, Parent = board })
		for k = -1, 1 do
			deco({ Name = "CrownSpike", Shape = Enum.PartType.Wedge, Size = Vector3.new(1, 1.8, 1.2), CFrame = base * CFrame.new(k * 1.8, crownY + 1.3, 0.3), Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Metal, Parent = board })
		end
		light(screen, accent, 18, 0.6)

		-- the board face: title, column of 10 rows and an "updated" line
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Board"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = screen
		local bg = Instance.new("Frame")
		bg.Name = "Bg"
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(24, 20, 36)
		bg.Parent = gui
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(accent:Lerp(Color3.fromRGB(24, 20, 36), 0.7), Color3.fromRGB(18, 15, 28))
		grad.Rotation = 90
		grad.Parent = bg
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromScale(0.04, 0.015)
		title.Size = UDim2.fromScale(0.92, 0.1)
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = accent
		title.TextStrokeTransparency = 0.3
		title.Text = info.Icon .. " " .. info.Title
		title.Parent = bg
		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0.04, 0.11)
		sub.Size = UDim2.fromScale(0.92, 0.04)
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(200, 195, 220)
		sub.Text = "TOP " .. rows .. " • ALL SERVERS"
		sub.Parent = bg
		local rowH = 0.8 / rows
		for r = 1, rows do
			local row = Instance.new("Frame")
			row.Name = "Row" .. r
			row.Position = UDim2.new(0.03, 0, 0.165 + (r - 1) * rowH, 0)
			row.Size = UDim2.new(0.94, 0, rowH * 0.9, 0)
			row.BackgroundColor3 = if r == 1 then Color3.fromRGB(255, 205, 60) elseif r == 2 then Color3.fromRGB(200, 205, 215) elseif r == 3 then Color3.fromRGB(205, 130, 70) else Color3.fromRGB(45, 40, 65)
			row.BackgroundTransparency = if r <= 3 then 0.55 else 0.35
			row.Parent = bg
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.25, 0)
			corner.Parent = row
			local function cell(name, xs2, w, align, font, text)
				local l = Instance.new("TextLabel")
				l.Name = name
				l.BackgroundTransparency = 1
				l.Position = UDim2.fromScale(xs2, 0.1)
				l.Size = UDim2.fromScale(w, 0.8)
				l.Font = font
				l.TextScaled = true
				l.TextXAlignment = align
				l.TextColor3 = Color3.new(1, 1, 1)
				l.TextStrokeTransparency = 0.5
				l.Text = text
				l.Parent = row
				return l
			end
			cell("Rank", 0.02, 0.13, Enum.TextXAlignment.Center, Enum.Font.FredokaOne, if r == 1 then "👑" else "#" .. r)
			cell("PlayerName", 0.17, 0.5, Enum.TextXAlignment.Left, Enum.Font.GothamBold, "---")
			cell("Value", 0.66, 0.32, Enum.TextXAlignment.Right, Enum.Font.GothamBlack, "")
		end
		local updated = Instance.new("TextLabel")
		updated.Name = "Updated"
		updated.BackgroundTransparency = 1
		updated.Position = UDim2.fromScale(0.04, 0.965)
		updated.Size = UDim2.fromScale(0.92, 0.03)
		updated.Font = Enum.Font.Gotham
		updated.TextScaled = true
		updated.TextColor3 = Color3.fromRGB(160, 155, 185)
		updated.Text = "Loading..."
		updated.Parent = bg
	end
	return folder
end

local function buildTown(folder, rng)
	-- Street lamps along the front of the row of bases
	for x = -PLOT_ROW_SPAN / 2 + PLOT_WIDTH + PLOT_GAP / 2, PLOT_ROW_SPAN / 2 - PLOT_WIDTH, PLOT_WIDTH + PLOT_GAP do
		streetLamp(folder, Vector3.new(x, 0, PLOT_SIZE / 2 + 14), 1)
	end

	-- Trees behind the bases and along the side walls
	for x = -TOWN_HALF + 10, TOWN_HALF - 10, 24 do
		local m = Instance.new("Model")
		m.Name = "Tree"
		m.Parent = folder
		local kind = if rng:NextNumber() < 0.5 then "Tree" else "TallTree"
		PROPS[kind](m, Vector3.new(x + rng:NextNumber(-3, 3), 0, TOWN_START_Z + 12), rng:NextNumber(0.6, 0.75), rng)
	end
	for _, side in ipairs({ -1, 1 }) do
		for z = PLOT_SIZE / 2 + 30, TOWN_END_Z - 20, 26 do
			local m = Instance.new("Model")
			m.Name = "Tree"
			m.Parent = folder
			PROPS.Tree(m, Vector3.new(side * (TOWN_HALF - 10), 0, z + rng:NextNumber(-3, 3)), rng:NextNumber(0.8, 1.1), rng)
		end
	end

	-- Monuments on the plaza: a giant golden egg and a glowing rift crystal
	local statue = Instance.new("Model")
	statue.Name = "GiantEgg"
	statue.Parent = folder
	deco({ Name = "Pedestal", Size = Vector3.new(16, 3, 16), Position = Vector3.new(-150, 1.5, 130), Color = Color3.fromRGB(235, 235, 240), Material = Enum.Material.Marble, Parent = statue })
	local giant = deco({ Name = "GoldenEgg", Size = Vector3.new(10, 13, 10), Position = Vector3.new(-150, 9.5, 130), Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Foil, Reflectance = 0.15, Parent = statue })
	local giantMesh = Instance.new("SpecialMesh")
	giantMesh.MeshType = Enum.MeshType.Sphere
	giantMesh.Parent = giant
	light(giant, Color3.fromRGB(255, 220, 120), 30, 1.5)
	local rift = Instance.new("Model")
	rift.Name = "Rift"
	rift.Parent = folder
	PROPS.Crystal(rift, Vector3.new(150, 0, 130), 2.6, rng)
	deco({ Name = "RiftPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 22, 22), CFrame = cylinderAlongY(CFrame.new(150, 0.2, 130)), Color = Color3.fromRGB(90, 40, 150), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = rift })

	-- Fountain plaza in front of the bases
	local fz = 130
	deco({ Name = "Plaza", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 40, 40), CFrame = cylinderAlongY(CFrame.new(0, 0.3, fz)), Color = Color3.fromRGB(185, 180, 170), Material = Enum.Material.Cobblestone, Parent = folder })
	part({ Name = "FountainBasin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 18, 18), CFrame = cylinderAlongY(CFrame.new(0, 1.3, fz)), Color = Color3.fromRGB(235, 235, 240), Material = Enum.Material.Marble, Parent = folder })
	deco({ Name = "FountainWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 16, 16), CFrame = cylinderAlongY(CFrame.new(0, 2.35, fz)), Color = Color3.fromRGB(70, 170, 220), Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.3, CanCollide = false, Parent = folder })
	deco({ Name = "FountainPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 2, 2), CFrame = cylinderAlongY(CFrame.new(0, 4, fz)), Color = Color3.fromRGB(235, 235, 240), Material = Enum.Material.Marble, Parent = folder })
	deco({ Name = "FountainBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 7, 7), CFrame = cylinderAlongY(CFrame.new(0, 7, fz)), Color = Color3.fromRGB(235, 235, 240), Material = Enum.Material.Marble, Parent = folder })
	local spout = deco({ Name = "FountainEgg", Size = Vector3.new(2.4, 3.2, 2.4), Position = Vector3.new(0, 9, fz), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Foil, Parent = folder })
	local spoutMesh = Instance.new("SpecialMesh")
	spoutMesh.MeshType = Enum.MeshType.Sphere
	spoutMesh.Parent = spout
	particles(spout, { Color = ColorSequence.new(Color3.fromRGB(150, 210, 255)), LightEmission = 0.3, Size = NumberSequence.new(0.5, 0.2), Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(1.2, 1.6), Rate = 90, Speed = NumberRange.new(10, 12), SpreadAngle = Vector2.new(18, 18), Acceleration = Vector3.new(0, -22, 0), EmissionDirection = Enum.NormalId.Top })
	light(spout, Color3.fromRGB(255, 220, 140), 18, 1)

	-- Big title board behind the fountain
	for _, sx in ipairs({ -1, 1 }) do
		deco({ Name = "TitlePost", Size = Vector3.new(2, 50, 2), Position = Vector3.new(sx * 24, 25, TOWN_START_Z + 6), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
	end
	local title = deco({ Name = "TitleBoard", Size = Vector3.new(50, 12, 1), Position = Vector3.new(0, 44, TOWN_START_Z + 6), Color = Color3.fromRGB(45, 30, 60), Material = Enum.Material.SmoothPlastic, Parent = folder })
	surfaceText(title, Enum.NormalId.Back, "🥚 STEAL A PET EGG 🥚", Color3.fromRGB(255, 220, 90))
	for x = -24, 24, 6 do
		lantern(folder, Vector3.new(x, 50.6, TOWN_START_Z + 6), Color3.fromRGB(255, 230, 150), 10)
	end

	-- Benches around the plaza
	for _, a in ipairs({ 0.6, 2.54, 3.74, 5.68 }) do
		local p = Vector3.new(math.cos(a) * 15, 0, fz + math.sin(a) * 15)
		local bench = CFrame.lookAt(p, Vector3.new(0, 0, fz))
		deco({ Name = "BenchSeat", Size = Vector3.new(6, 0.4, 2), CFrame = bench * CFrame.new(0, 1.6, 0), Color = WOOD, Material = Enum.Material.Wood, Parent = folder })
		deco({ Name = "BenchBack", Size = Vector3.new(6, 1.8, 0.3), CFrame = bench * CFrame.new(0, 2.6, 1), Color = WOOD, Material = Enum.Material.Wood, Parent = folder })
		for _, lx in ipairs({ -2.5, 2.5 }) do
			deco({ Name = "BenchLeg", Size = Vector3.new(0.4, 1.4, 1.8), CFrame = bench * CFrame.new(lx, 0.7, 0), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal, Parent = folder })
		end
	end

	-- Market stalls beside the plaza
	local stallColors = { { Color3.fromRGB(230, 70, 70), WHITE }, { Color3.fromRGB(70, 140, 230), WHITE } }
	local stallText = { "🥚 EGG FACTS", "🍦 TREATS" }
	for i, sx in ipairs({ -1, 1 }) do
		local base = CFrame.lookAt(Vector3.new(sx * 60, 0, fz), Vector3.new(0, 0, fz))
		deco({ Name = "Counter", Size = Vector3.new(12, 3.5, 3), CFrame = base * CFrame.new(0, 1.75, 0), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = folder })
		deco({ Name = "CounterTop", Size = Vector3.new(12.6, 0.4, 3.6), CFrame = base * CFrame.new(0, 3.7, 0), Color = Color3.fromRGB(240, 235, 225), Material = Enum.Material.SmoothPlastic, Parent = folder })
		for _, px in ipairs({ -5.8, 5.8 }) do
			deco({ Name = "StallPost", Size = Vector3.new(0.6, 9, 0.6), CFrame = base * CFrame.new(px, 4.5, 2), Color = DARK_WOOD, Material = Enum.Material.Wood, Parent = folder })
		end
		for stripe = 0, 5 do
			deco({ Name = "Awning", Size = Vector3.new(2.1, 0.4, 6), CFrame = base * CFrame.new(-5.25 + stripe * 2.1, 9.2, 0) * CFrame.Angles(math.rad(-15), 0, 0), Color = stallColors[i][(stripe % 2) + 1], Material = Enum.Material.Fabric, Parent = folder })
		end
		local sign = deco({ Name = "StallSign", Size = Vector3.new(10, 2, 0.4), CFrame = base * CFrame.new(0, 10.8, 2.6), Color = Color3.fromRGB(45, 35, 30), Material = Enum.Material.Wood, Parent = folder })
		surfaceText(sign, Enum.NormalId.Front, stallText[i], Color3.fromRGB(255, 230, 150))
		if i == 1 then
			for j = -1, 1 do
				local egg = deco({ Name = "DisplayEgg", Size = Vector3.new(1.4, 1.9, 1.4), CFrame = base * CFrame.new(j * 3.5, 4.8, 0), Color = Config.Rarities[j + 3].Color, Material = Enum.Material.SmoothPlastic, Parent = folder })
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = egg
			end
		else
			-- treats on the counter: cookie, cupcake, ice cream cone
			local cookie = base * CFrame.new(-3.5, 4.05, 0)
			deco({ Name = "Cookie", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.8, 1.8), CFrame = cylinderAlongY(cookie), Color = Color3.fromRGB(210, 150, 90), Material = Enum.Material.SmoothPlastic, Parent = folder })
			for k = 0, 3 do
				deco({ Name = "Chip", Size = Vector3.one * 0.25, CFrame = cookie * CFrame.new(math.cos(k * 1.7) * 0.5, 0.18, math.sin(k * 1.7) * 0.5), Color = Color3.fromRGB(70, 40, 25), Material = Enum.Material.SmoothPlastic, Parent = folder })
			end
			local cake = base * CFrame.new(0, 4.3, 0)
			deco({ Name = "CupcakeBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 1.2, 1.2), CFrame = cylinderAlongY(cake), Color = Color3.fromRGB(240, 200, 150), Material = Enum.Material.SmoothPlastic, Parent = folder })
			deco({ Name = "Frosting", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.1, 1.5), CFrame = cake * CFrame.new(0, 0.6, 0), Color = Color3.fromRGB(255, 150, 200), Material = Enum.Material.SmoothPlastic, Parent = folder })
			deco({ Name = "Cherry", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, CFrame = cake * CFrame.new(0, 1.2, 0), Color = Color3.fromRGB(220, 30, 50), Material = Enum.Material.SmoothPlastic, Parent = folder })
			local cone = base * CFrame.new(3.5, 3.9, 0)
			for k = 0, 3 do
				deco({ Name = "Cone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 0.3 + k * 0.28, 0.3 + k * 0.28), CFrame = cylinderAlongY(cone * CFrame.new(0, k * 0.4, 0)), Color = Color3.fromRGB(220, 170, 100), Material = Enum.Material.SmoothPlastic, Parent = folder })
			end
			for k, col in ipairs({ Color3.fromRGB(255, 240, 220), Color3.fromRGB(255, 160, 200), Color3.fromRGB(150, 220, 255) }) do
				deco({ Name = "Scoop", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, CFrame = cone * CFrame.new(0, 1.6 + (k - 1) * 0.8, 0), Color = col, Material = Enum.Material.SmoothPlastic, Parent = folder })
			end
		end
		-- walk up and press E / hold X to open the stall's menu
		local anchor = deco({ Name = if i == 1 then "EggFactsStall" else "TreatShopStall", Size = Vector3.new(2, 2, 2), CFrame = base * CFrame.new(0, 3, -3), Transparency = 1, CanCollide = false, Parent = folder })
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = if i == 1 then "EggFactsPrompt" else "TreatShopPrompt"
		prompt.ActionText = if i == 1 then "Read" else "Shop"
		prompt.ObjectText = if i == 1 then "🥚 Egg Facts" else "🍦 Treat Shop"
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 14
		prompt:SetAttribute("Range", 14)
		prompt.Parent = anchor
	end

	-- Flower beds along the street
	for _, side in ipairs({ -1, 1 }) do
		for z = 70, TOWN_END_Z - 70, 50 do
			deco({ Name = "FlowerBed", Size = Vector3.new(4, 0.8, 12), Position = Vector3.new(side * 22, 0.4, z + 25), Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.SmoothPlastic, Parent = folder })
			for k = -2, 2 do
				local flower = ({ Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 225, 80), WHITE, Color3.fromRGB(170, 130, 255) })[(k + z // 50) % 4 + 1]
				deco({ Name = "Stem", Size = Vector3.new(0.3, 1.4, 0.3), Position = Vector3.new(side * 22, 1.5, z + 25 + k * 2.2), Color = Color3.fromRGB(70, 150, 60), Material = Enum.Material.SmoothPlastic, Parent = folder })
				deco({ Name = "Bloom", Size = Vector3.new(1.1, 1.1, 1.1), Position = Vector3.new(side * 22, 2.4, z + 25 + k * 2.2), Color = flower, Material = Enum.Material.SmoothPlastic, Parent = folder })
			end
		end
	end

	-- "SAFE ZONE" painted on the floor before the first zone
	deco({ Name = "SafeLine", Size = Vector3.new(TOWN_HALF * 2, 0.15, 1.6), Position = Vector3.new(0, 0.08, TOWN_END_Z - 40), Color = Color3.fromRGB(220, 40, 50), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = folder })
	local safe = deco({ Name = "SafeZone", Size = Vector3.new(70, 0.1, 18), Position = Vector3.new(0, 0.1, TOWN_END_Z - 52), Transparency = 1, CanCollide = false, Parent = folder })
	local gui = surfaceText(safe, Enum.NormalId.Top, "SAFE ZONE", WHITE)
	gui.TextTransparency = 0.25
	gui.TextStrokeTransparency = 1
	gui.Rotation = 180

	buildTownExtras(folder, rng)
end

--------------------------------------------------------------------------------
-- Biomes
--------------------------------------------------------------------------------
-- A little straw nest that one egg sits in. Its top is at y = 1.
-- Each nest is its own model (centered on the ground under the egg) so the
-- game can resize it to fit whatever size of egg spawns in it.
local function buildEggNest(parent, position, rng)
	local folder = Instance.new("Model")
	folder.Name = "EggNest"
	folder:SetAttribute("Center", position)
	folder.Parent = parent
	deco({ Name = "NestStraw", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 5.6, 5.6), CFrame = cylinderAlongY(CFrame.new(position + Vector3.new(0, 0.5, 0))), Color = Color3.fromRGB(215, 175, 95), Material = Enum.Material.Fabric, Parent = folder })
	for i = 1, 9 do
		local a = i / 9 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local p = position + Vector3.new(math.cos(a) * 2.9, 1.1 + rng:NextNumber(-0.15, 0.2), math.sin(a) * 2.9)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		deco({
			Name = "Twig",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6, 0.55, 0.55),
			CFrame = CFrame.lookAt(p, p + tangent) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), math.rad(90), 0),
			Color = Color3.fromRGB(125 + rng:NextInteger(-20, 20), 85 + rng:NextInteger(-15, 15), 48),
			Material = Enum.Material.Wood,
			Parent = folder,
		})
	end
	return folder
end

-- Where the guardian naps: a mossy rock den with a glowing campfire of its color.
local function buildDen(folder, def, home, rng)
	local trim = def.GuardianColor:Lerp(WHITE, 0.2)
	deco({ Name = "DenStep", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 26, 26), CFrame = cylinderAlongY(CFrame.new(home + Vector3.new(0, 0.15, 0))), Color = def.Walls[1]:Lerp(BLACK, 0.15), Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "DenTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 21, 21), CFrame = cylinderAlongY(CFrame.new(home + Vector3.new(0, 0.35, 0))), Color = def.Walls[2], Material = Enum.Material.SmoothPlastic, Parent = folder })
	deco({ Name = "DenTrim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 21.8, 21.8), CFrame = cylinderAlongY(CFrame.new(home + Vector3.new(0, 0.46, 0))), Color = trim, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	deco({ Name = "DenTopInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 20.4, 20.4), CFrame = cylinderAlongY(CFrame.new(home + Vector3.new(0, 0.48, 0))), Color = def.Walls[2], Material = Enum.Material.SmoothPlastic, Parent = folder })
	-- four short pillars with glowing orbs around the den
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local p = home + Vector3.new(math.cos(a) * 14.5, 0, math.sin(a) * 14.5)
		deco({ Name = "DenPillar", Size = Vector3.new(2, 7, 2), Position = p + Vector3.new(0, 3.5, 0), Color = def.Walls[1]:Lerp(BLACK, 0.25), Material = Enum.Material.SmoothPlastic, Parent = folder })
		local orb = deco({ Name = "DenOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = p + Vector3.new(0, 8, 0), Color = trim, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
		light(orb, def.GuardianColor, 18, 1.2)
	end
end

-- Scatter egg spots across the zone, spread apart and clear of the entrance,
-- the guardian's den and big features.
local EGG_SPACING = 60 -- eggs are at least this far apart
local function scatterSpots(def, centerZ, rng, avoid)
	local zMin, zMax = centerZ - BIOME_SPACING / 2, centerZ + BIOME_SPACING / 2
	local spots = {}
	local tries = 0
	while #spots < def.EggSpots and tries < 2000 do
		tries += 1
		local p = Vector3.new(rng:NextNumber(-CORRIDOR_HALF + 14, CORRIDOR_HALF - 14), 0, rng:NextNumber(zMin + 28, zMax - 14))
		local ok = true
		for _, other in ipairs(spots) do
			if (other - p).Magnitude < EGG_SPACING then
				ok = false
				break
			end
		end
		for _, zone in ipairs(avoid) do
			if ok and (Vector3.new(zone[1], 0, zone[2]) - p).Magnitude < zone[3] then
				ok = false
			end
		end
		if ok then
			table.insert(spots, p)
		end
	end
	return spots
end

local SOLID_NAMES = { Floor = true, Wall = true, WallCap = true }
local SETPIECE_X = CORRIDOR_HALF / 462.5 -- set piece spots were laid out for a narrower map

local function buildBiome(biomesFolder, index, def, centerZ)
	local folder = Instance.new("Model")
	folder.Name = def.Id
	folder:SetAttribute("MinZ", centerZ - BIOME_SPACING / 2)
	folder:SetAttribute("MaxZ", centerZ + BIOME_SPACING / 2)
	folder:SetAttribute("BiomeIndex", index)
	folder.Parent = biomesFolder
	local rng = Random.new(index * 1000)

	local center = Vector3.new(0, 0, centerZ)
	local zMin, zMax = centerZ - BIOME_SPACING / 2, centerZ + BIOME_SPACING / 2
	checkerFloor(folder, -CORRIDOR_HALF, CORRIDOR_HALF, zMin, zMax, def.Floor, nil, ZONE_FLOOR_TILE)
	-- a clean path down the middle of the zone, around the guardian's den
	local pathColor = def.Floor[1]:Lerp(WHITE, 0.35)
	local edgeColor = def.Floor[2]:Lerp(BLACK, 0.2)
	for _, seg in ipairs({ { zMin, centerZ - 8 }, { centerZ + 28, zMax } }) do
		local len = seg[2] - seg[1]
		local mid = (seg[1] + seg[2]) / 2
		deco({ Name = "Path", Size = Vector3.new(24, 0.12, len), Position = Vector3.new(0, 0.1, mid), Color = pathColor, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
		for _, sx in ipairs({ -1, 1 }) do
			deco({ Name = "PathEdge", Size = Vector3.new(1, 0.14, len), Position = Vector3.new(sx * 12.5, 0.11, mid), Color = edgeColor, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
		end
	end
	sideWalls(folder, CORRIDOR_HALF, zMin, zMax, def.Walls)
	-- Banners and torches along the walls
	for z = zMin + 30, zMax - 20, 40 do
		for _, side in ipairs({ -1, 1 }) do
			local x = side * (CORRIDOR_HALF - 0.3)
			deco({ Name = "BannerRod", Size = Vector3.new(0.6, 0.4, 6.4), Position = Vector3.new(x, 25.2, z), Color = Color3.fromRGB(230, 190, 80), Material = Enum.Material.Metal, Parent = folder })
			deco({ Name = "Banner", Size = Vector3.new(0.3, 9, 5.5), Position = Vector3.new(x, 20.6, z), Color = def.GuardianColor:Lerp(BLACK, 0.15), Material = Enum.Material.Fabric, Parent = folder })
			deco({ Name = "BannerTip", Size = Vector3.new(0.3, 2.8, 2.8), CFrame = CFrame.new(x, 16.1, z) * CFrame.Angles(math.rad(45), 0, 0), Color = def.GuardianColor:Lerp(BLACK, 0.15), Material = Enum.Material.Fabric, Parent = folder })
			deco({ Name = "BannerEmblem", Size = Vector3.new(0.4, 2.6, 2.6), CFrame = CFrame.new(x - side * 0.1, 21.5, z) * CFrame.Angles(math.rad(45), 0, 0), Color = Color3.fromRGB(255, 225, 110), Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
			local sconce = deco({ Name = "Sconce", Size = Vector3.new(1.6, 1, 1.6), Position = Vector3.new(x - side * 0.9, 11, z + 20), Color = Color3.fromRGB(60, 60, 65), Material = Enum.Material.Metal, Parent = folder })
			local fire = Instance.new("Fire")
			fire.Size = 3
			fire.Heat = 6
			fire.Color = def.GuardianColor:Lerp(Color3.fromRGB(255, 160, 60), 0.5)
			fire.Parent = sconce
			light(sconce, Color3.fromRGB(255, 170, 90), 18, 1)
		end
	end

	-- Entrance: a giant gateway that spans the whole width of the map, with the
	-- zone's name on the beam and floating above it.
	local half = CORRIDOR_HALF
	local beamH = WALL_HEIGHT - DOOR_HEIGHT
	local beamCenter = Vector3.new(0, DOOR_HEIGHT + beamH / 2, zMin)
	checkerPanel(folder, CFrame.lookAt(beamCenter, beamCenter - Vector3.zAxis), half * 2 + 8, beamH, def.Walls, true)
	local glow = def.GuardianColor:Lerp(WHITE, 0.2)
	deco({ Name = "GateGlow", Size = Vector3.new(half * 2 + 8, 1.2, 5), Position = Vector3.new(0, DOOR_HEIGHT - 0.6, zMin), Color = glow, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
	-- pillars along the gateway with torches and hanging banners
	local pillarGap = 70
	for x = -half + pillarGap / 2, half - pillarGap / 2 + 0.1, pillarGap do
		if math.abs(x) > 30 then -- leave the center wide open
			deco({ Name = "GatePillar", Size = Vector3.new(5, DOOR_HEIGHT, 5), Position = Vector3.new(x, DOOR_HEIGHT / 2, zMin), Color = def.Walls[1]:Lerp(BLACK, 0.2), Material = Enum.Material.SmoothPlastic, Parent = folder })
			deco({ Name = "PillarBand", Size = Vector3.new(5.4, 1.2, 5.4), Position = Vector3.new(x, 4, zMin), Color = glow, Material = Enum.Material.Neon, CastShadow = false, Parent = folder })
			local torch = deco({ Name = "GateTorch", Size = Vector3.new(1.6, 1.4, 1.6), Position = Vector3.new(x, DOOR_HEIGHT - 5, zMin - 3.2), Color = Color3.fromRGB(70, 70, 75), Material = Enum.Material.SmoothPlastic, Parent = folder })
			local fire = Instance.new("Fire")
			fire.Size = 4
			fire.Color = def.GuardianColor
			fire.SecondaryColor = WHITE
			fire.Parent = torch
			light(torch, def.GuardianColor, 24, 1.4)
		end
	end
	for x = -half + 35, half - 35, 70 do
		deco({ Name = "GateBanner", Size = Vector3.new(7, 10, 0.3), Position = Vector3.new(x, DOOR_HEIGHT - 6, zMin - 2.6), Color = def.GuardianColor:Lerp(BLACK, 0.15), Material = Enum.Material.Fabric, CanCollide = false, Parent = folder })
		deco({ Name = "GateBannerEmblem", Size = Vector3.new(2.8, 2.8, 0.35), CFrame = CFrame.new(x, DOOR_HEIGHT - 5.5, zMin - 2.8) * CFrame.Angles(0, 0, math.rad(45)), Color = Color3.fromRGB(255, 225, 110), Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, Parent = folder })
	end
	local DOOR_HALF = 60 -- width of the name signs on the beam
	local lintelH = beamH

	-- Zone name on the lintel and floating above the doorway
	local lintelFront = deco({ Name = "ZoneSign", Size = Vector3.new(DOOR_HALF * 2 - 2, lintelH - 2, 0.2), Position = Vector3.new(0, DOOR_HEIGHT + lintelH / 2, zMin - 2.2), Transparency = 1, CanCollide = false, Parent = folder })
	local recommended = Config.RecommendedSpeed(def)
	surfaceText(lintelFront, Enum.NormalId.Front, "⚡ Speed " .. Util.FormatNumber(recommended) .. "+", Color3.fromRGB(255, 230, 120))
	local lintelBack = deco({ Name = "ZoneSignBack", Size = Vector3.new(DOOR_HALF * 2 - 2, lintelH - 2, 0.2), Position = Vector3.new(0, DOOR_HEIGHT + lintelH / 2, zMin + 2.2), Transparency = 1, CanCollide = false, Parent = folder })
	surfaceText(lintelBack, Enum.NormalId.Back, if index == 1 then "🏠 Town" else "← " .. Config.Biomes[index - 1].Name, WHITE)

	local floatAnchor = deco({ Name = "ZoneTitleAnchor", Size = Vector3.one, Position = Vector3.new(0, WALL_HEIGHT + 7, zMin), Transparency = 1, CanCollide = false, Parent = folder })
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(70, 16)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 600
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.65)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = def.Name
	title.TextColor3 = glow
	title.TextStrokeTransparency = 0
	title.Parent = billboard
	local sub = title:Clone()
	sub.Position = UDim2.fromScale(0, 0.65)
	sub.Size = UDim2.fromScale(1, 0.35)
	sub.Font = Enum.Font.GothamBold
	sub.Text = "Guardian: " .. def.GuardianName
	sub.TextColor3 = WHITE
	sub.Parent = billboard
	billboard.Parent = floatAnchor

	-- The guardian naps in the middle; eggs are scattered all over the zone,
	-- each in its own little nest.
	local nestCenter = center
	local home = center + Vector3.new(0, 0, 10)
	buildDen(folder, def, home, rng)
	local avoid = { { home.X, home.Z, 26 } }
	for _, zone in ipairs(FEATURE_AREAS[def.Feature] or {}) do
		table.insert(avoid, { zone[1], centerZ + zone[2], zone[3] })
	end
	for _, zone in ipairs(LANDMARK_AREAS[def.Id] or {}) do
		table.insert(avoid, { zone[1], centerZ + zone[2], zone[3] })
	end
	for _, piece in ipairs(SETPIECE_SPOTS[def.Id] or {}) do
		table.insert(avoid, { piece[2] * SETPIECE_X, centerZ + piece[3], piece[4] })
	end
	local spotGround = scatterSpots(def, centerZ, rng, avoid)
	local spots, nests = {}, {}
	for i, p in ipairs(spotGround) do
		nests[i] = buildEggNest(folder, p, rng)
		spots[i] = p + Vector3.new(0, 1, 0)
	end

	-- Feature, props and ambience
	if def.Feature and FEATURES[def.Feature] then
		FEATURES[def.Feature](folder, centerZ, rng, spotGround)
	end
	if LANDMARKS[def.Id] then
		LANDMARKS[def.Id](folder, centerZ, rng)
	end
	local keepClear = table.clone(spotGround)
	for _, zone in ipairs(LANDMARK_AREAS[def.Id] or {}) do
		table.insert(keepClear, Vector3.new(zone[1], zone[3] + 8, centerZ + zone[2])) -- Y carries the clearance radius
	end
	for _, piece in ipairs(SETPIECE_SPOTS[def.Id] or {}) do
		table.insert(keepClear, Vector3.new(piece[2] * SETPIECE_X, piece[4] + 6, centerZ + piece[3]))
	end
	placeProps(folder, def, centerZ, rng, keepClear)
	scatterClutter(folder, def, centerZ, rng)
	ambientParticles(folder, def.Particles, centerZ)
	ambientParticles(folder, EXTRA_AMBIENT[def.Id], centerZ)

	-- Set pieces, wall details, scenery beyond the walls and sky pieces
	for _, piece in ipairs(SETPIECE_SPOTS[def.Id] or {}) do
		local model = Instance.new("Model")
		model.Name = piece[1]
		model.Parent = folder
		SETPIECES[piece[1]](model, Vector3.new(piece[2] * SETPIECE_X, 0, centerZ + piece[3]), rng)
	end
	wallTrims(folder, def.Id, zMin, zMax, rng)
	backdrop(folder, def.Id, CORRIDOR_HALF, zMin, zMax, rng, if index == #Config.Biomes then { { Z = zMax, Dir = 1 } } else nil)
	if SKY[def.Id] then
		SKY[def.Id](folder, centerZ, rng)
	end

	-- At top speeds you'd snag on every tree and rock, so everything in a zone
	-- except the floor and walls is walk-through: just run past (or through) it.
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and not SOLID_NAMES[d.Name] then
			d.CanCollide = false
		end
	end

	return {
		Index = index,
		Def = def,
		Center = center,
		NestCenter = nestCenter,
		Spots = spots,
		Nests = nests,
		GuardianHome = home,
	}
end

--------------------------------------------------------------------------------
-- Whole map
--------------------------------------------------------------------------------
function MapBuilder.Build()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	terrain:Clear()

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace

	setupLighting()

	local lastBiomeZ = BIOME_START_Z + (#Config.Biomes - 1) * BIOME_SPACING
	local farEnd = lastBiomeZ + BIOME_SPACING / 2
	local nearEnd = TOWN_START_Z

	-- Town floor and walls
	local townFolder = Instance.new("Folder")
	townFolder.Name = "Town"
	townFolder.Parent = mapFolder
	local function underPlot(x, z)
		return math.abs(z) < PLOT_SIZE / 2 and math.abs(x) < PLOT_ROW_SPAN / 2
	end
	local townEnd = BIOME_START_Z - BIOME_SPACING / 2
	checkerFloor(townFolder, -TOWN_HALF, TOWN_HALF, nearEnd, townEnd, Config.TownFloor, underPlot)
	sideWalls(townFolder, TOWN_HALF, nearEnd, townEnd, Config.TownWalls)
	endWall(townFolder, TOWN_HALF, nearEnd - 2, Config.TownWalls, 1)
	-- far end of the last zone
	local lastDef = Config.Biomes[#Config.Biomes]
	endWall(mapFolder, CORRIDOR_HALF, farEnd + 2, lastDef.Walls, -1)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.Position = Vector3.new(0, 0.4, 80)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = mapFolder

	-- Town decoration
	buildTown(townFolder, Random.new(7))
	buildLeaderboards(townFolder)
	-- nothing low in town to trip over or get launched off at top speed
	for _, d in ipairs(townFolder:GetDescendants()) do
		if d:IsA("BasePart") and not SOLID_NAMES[d.Name] and d.Name ~= "Screen" then
			d.CanCollide = false
		end
	end

	-- Bases: one horizontal row across the town, all facing the zones (+Z)
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = mapFolder
	local plots = {}
	for index = 1, PLOT_COUNT do
		local x = -PLOT_ROW_SPAN / 2 + PLOT_WIDTH / 2 + (index - 1) * (PLOT_WIDTH + PLOT_GAP)
		plots[index] = buildPlot(plotsFolder, index, Vector3.new(x, 0, 0), Vector3.new(0, 0, 1))
	end

	-- Biomes
	local biomesFolder = Instance.new("Folder")
	biomesFolder.Name = "Biomes"
	biomesFolder.Parent = mapFolder
	local biomes = {}
	for index, def in ipairs(Config.Biomes) do
		biomes[index] = buildBiome(biomesFolder, index, def, BIOME_START_Z + (index - 1) * BIOME_SPACING)
	end

	return {
		Plots = plots,
		Biomes = biomes,
		RainArea = { MinZ = 70, MaxZ = 180, HalfWidth = TOWN_HALF - 80 },
		SafeZoneZ = TOWN_END_Z - 40, -- guardians give up at the red safe-zone line
	}
end

return MapBuilder
