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
local PLOT_GAP = 9
local PLOT_ROW_SPAN = PLOT_COUNT * PLOT_WIDTH + (PLOT_COUNT - 1) * PLOT_GAP -- all bases side by side
local TOWN_START_Z = -75
local TOWN_END_Z = 230
local BIOME_SPACING = 300
local BIOME_START_Z = TOWN_END_Z + BIOME_SPACING / 2
local TOWN_HALF = PLOT_ROW_SPAN / 2 + 20 -- the town is as wide as the row of bases
local CORRIDOR_HALF = TOWN_HALF -- zones are as wide as the town
local TILE = 10 -- wall checker size
local FLOOR_TILE = 5 -- floor checker size (small squares, like Steal an Egg)
local WALL_HEIGHT = 40
local DOOR_HALF = 35
local DOOR_HEIGHT = 30

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local WARM_LIGHT = Color3.fromRGB(255, 205, 140)
local WOOD = Color3.fromRGB(150, 100, 60)
local DARK_WOOD = Color3.fromRGB(105, 70, 45)
local STONE = Color3.fromRGB(160, 160, 165)

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
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0.55
	Lighting.ShadowSoftness = 0.3
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
	sky.SunAngularSize = 11
	sky.MoonAngularSize = 9
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	-- Bloom only catches truly bright things (neon, lanterns), not every surface
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 22
	bloom.Threshold = 2
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
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
	clouds.Density = 0.55
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
local function checkerFloor(folder, xMin, xMax, zMin, zMax, colors, skip)
	part({ Name = "Floor", Size = Vector3.new(xMax - xMin, 2, zMax - zMin), Position = Vector3.new((xMin + xMax) / 2, -1, (zMin + zMax) / 2), Color = colors[1], Material = Enum.Material.SmoothPlastic, Parent = folder })
	local ix = 0
	for x = xMin, xMax - FLOOR_TILE, FLOOR_TILE do
		local iz = 0
		for z = zMin, zMax - FLOOR_TILE, FLOOR_TILE do
			local cx, cz = x + FLOOR_TILE / 2, z + FLOOR_TILE / 2
			if (ix + iz) % 2 == 1 and not (skip and skip(cx, cz)) then
				deco({ Name = "Tile", Size = Vector3.new(FLOOR_TILE, 0.2, FLOOR_TILE), Position = Vector3.new(cx, -0.05, cz), Color = colors[2], Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = folder })
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

local function placeProps(folder, def, centerZ, rng, keepClear)
	-- each entry: { position, clearance radius }
	local placed = {}
	for _, p in ipairs(keepClear or {}) do
		table.insert(placed, { Vector2.new(p.X, p.Z), p.Y > 0 and p.Y or 11 })
	end
	local count = 0
	local tries = 0
	while count < 170 and tries < 3000 do
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
	Motes = { Y = 2, Props = { Color = ColorSequence.new(Color3.fromRGB(200, 140, 255), Color3.fromRGB(120, 200, 255)), LightEmission = 1, Size = NumberSequence.new(0.4, 0), Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(5, 8), Rate = 60, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top } },
}

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
	surfaceText(console, Enum.NormalId.Back, "🏃 TRAINING SPEED", Color3.fromRGB(120, 255, 140))
	deco({ Name = "ConsoleGlow", Size = Vector3.new(beltWidth + 1.2, 0.2, 0.7), CFrame = at(TX, 4.3, -13.4), Color = accent, Material = Enum.Material.Neon, CastShadow = false, Parent = model })
	local treadSign = deco({ Name = "TreadmillSign", Size = Vector3.new(8 * K, 1.8, 0.4), CFrame = at(TX, 8.6, -13.4), Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.SmoothPlastic, Parent = model })
	surfaceText(treadSign, Enum.NormalId.Front, "🏃 TREADMILL", Color3.fromRGB(255, 225, 120))
	surfaceText(treadSign, Enum.NormalId.Back, "Step on to train Speed!", Color3.fromRGB(255, 225, 120))

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

	plot.SpawnCFrame = at(0, 4, -14)
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
		for j = -1, 1 do
			local egg = deco({ Name = "DisplayEgg", Size = Vector3.new(1.4, 1.9, 1.4), CFrame = base * CFrame.new(j * 3.5, 4.8, 0), Color = Config.Rarities[j + 3].Color, Material = Enum.Material.SmoothPlastic, Parent = folder })
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = egg
		end
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
end

--------------------------------------------------------------------------------
-- Biomes
--------------------------------------------------------------------------------
-- A little straw nest that one egg sits in. Its top is at y = 1.
local function buildEggNest(folder, position, rng)
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
local function scatterSpots(def, centerZ, rng, avoid)
	local zMin, zMax = centerZ - BIOME_SPACING / 2, centerZ + BIOME_SPACING / 2
	local spots = {}
	local tries = 0
	while #spots < def.EggSpots and tries < 2000 do
		tries += 1
		local p = Vector3.new(rng:NextNumber(-CORRIDOR_HALF + 14, CORRIDOR_HALF - 14), 0, rng:NextNumber(zMin + 28, zMax - 14))
		local ok = true
		for _, other in ipairs(spots) do
			if (other - p).Magnitude < 32 then
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
	checkerFloor(folder, -CORRIDOR_HALF, CORRIDOR_HALF, zMin, zMax, def.Floor)
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
	local spotGround = scatterSpots(def, centerZ, rng, avoid)
	local spots = {}
	for i, p in ipairs(spotGround) do
		buildEggNest(folder, p, rng)
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
	placeProps(folder, def, centerZ, rng, keepClear)
	scatterClutter(folder, def, centerZ, rng)
	ambientParticles(folder, def.Particles, centerZ)

	return {
		Index = index,
		Def = def,
		Center = center,
		NestCenter = nestCenter,
		Spots = spots,
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
		RainArea = { MinZ = 70, MaxZ = 180, HalfWidth = 200 },
		SafeZoneZ = TOWN_END_Z - 40, -- guardians give up at the red safe-zone line
	}
end

return MapBuilder
