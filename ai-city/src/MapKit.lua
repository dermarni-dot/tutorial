-- MapKit (ModuleScript) — ServerScriptService.Modules.MapKit
-- Small building blocks shared by the map modules: part helpers, colors, signs,
-- lights, seats, and a registry of things that change between day and night.

local CollectionService = game:GetService("CollectionService")

local MapKit = {}

--------------------------------------------------------------------------------
-- Layout numbers (shared by every map module)
--------------------------------------------------------------------------------
MapKit.SPACING = 100 -- block center to block center
MapKit.ROAD = 16 -- road width
MapKit.BLOCK = MapKit.SPACING - MapKit.ROAD -- 84: a block including its sidewalk
MapKit.HALF = MapKit.BLOCK / 2
MapKit.SIDEWALK = 5
MapKit.RING = MapKit.HALF - MapKit.SIDEWALK / 2 -- where people walk on the sidewalk
MapKit.N = 5 -- blocks from the center to the edge (11x11 blocks)
MapKit.EXTENT = MapKit.N * MapKit.SPACING + MapKit.SPACING / 2 -- the city is 2 * EXTENT across
MapKit.LOT_Y = 0.5 -- ground level inside blocks (top of the curb)
MapKit.FLOOR_H = 12

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
MapKit.rgb = rgb
MapKit.BLACK = Color3.new(0, 0, 0)
MapKit.WHITE = Color3.new(1, 1, 1)
MapKit.ASPHALT = rgb(52, 54, 60)
MapKit.CONCRETE = rgb(198, 196, 190)
MapKit.CURB = rgb(170, 168, 162)
MapKit.GRASS = rgb(92, 164, 74)
MapKit.DARK_GRASS = rgb(74, 142, 60)
MapKit.GLASS = rgb(150, 196, 230)
MapKit.WINDOW_LIT = rgb(255, 212, 140)
MapKit.LAMP_LIGHT = rgb(255, 214, 160)
MapKit.GOLD = rgb(242, 196, 78)
MapKit.WOOD = rgb(150, 104, 64)
MapKit.DARK_WOOD = rgb(96, 64, 42)
MapKit.STONE = rgb(214, 208, 196)
MapKit.METAL = rgb(70, 74, 82)
MapKit.LEAVES = { rgb(66, 146, 58), rgb(86, 164, 68), rgb(58, 128, 56), rgb(104, 160, 60) }
MapKit.FLOWERS = { rgb(255, 92, 122), rgb(255, 208, 60), rgb(168, 110, 255), rgb(255, 150, 60), rgb(250, 250, 250), rgb(90, 160, 255) }

--------------------------------------------------------------------------------
-- Things that change with the time of day (MapBuilder.SetNight walks these)
--------------------------------------------------------------------------------
MapKit.Registry = {
	Windows = {}, -- glass that glows warm at night
	Lamps = {}, -- { Head = part, Light = light }
	NightLights = {}, -- lights that only turn on at night (porch lights, signs)
	NightNeon = {}, -- parts that switch to neon at night { Part, DayMaterial }
	NightParticles = {}, -- particle emitters only on at night (fireflies)
	Seats = {}, -- { Seat = seat, Place = id or nil }
}

--------------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------------
function MapKit.part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- decoration: can't be bumped into, doesn't block clicks or cast shadows
function MapKit.deco(parent, name, size, cf, color, material, props)
	local p = MapKit.part(parent, name, size, cf, color, material, props)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Trim that runs around the OUTSIDE of a W × D building (h tall, t thick,
-- centered at cf), leaving the inside empty. gap: an opening in the front
-- (-Z) side for the door.
function MapKit.ring(parent, name, cf, W, D, h, t, color, material, gap)
	local parts = {}
	local function add(size, offset)
		if size.X > 0.05 and size.Z > 0.05 then
			table.insert(parts, MapKit.deco(parent, name, size, cf * offset, color, material))
		end
	end
	local full = W + 2 * t
	add(Vector3.new(full, h, t), CFrame.new(0, 0, D / 2 + t / 2))
	if gap and gap > 0 then
		local side = (full - gap) / 2
		add(Vector3.new(side, h, t), CFrame.new(-full / 2 + side / 2, 0, -D / 2 - t / 2))
		add(Vector3.new(side, h, t), CFrame.new(full / 2 - side / 2, 0, -D / 2 - t / 2))
	else
		add(Vector3.new(full, h, t), CFrame.new(0, 0, -D / 2 - t / 2))
	end
	for _, s in ipairs({ -1, 1 }) do
		add(Vector3.new(t, h, D), CFrame.new(s * (W / 2 + t / 2), 0, 0))
	end
	return parts
end

function MapKit.wedge(parent, name, size, cf, color, material, collide)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = collide == true
	p.Parent = parent
	return p
end

function MapKit.ball(parent, name, diameter, cf, color, material)
	local p = MapKit.deco(parent, name, Vector3.one * diameter, cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- an upright cylinder (Roblox cylinders lie along X)
function MapKit.column(parent, name, height, diameter, pos, color, material, collide)
	local p = MapKit.part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	if collide == false then
		p.CanCollide = false
	end
	return p
end

-- a cylinder lying along the given cframe's X axis (wheels, pipes, logs)
function MapKit.cylinder(parent, name, length, diameter, cf, color, material)
	local p = MapKit.deco(parent, name, Vector3.new(length, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- a flat disc facing up (tables, rugs, manholes)
function MapKit.disc(parent, name, thickness, diameter, pos, color, material)
	return MapKit.cylinder(parent, name, thickness, diameter, CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, material)
end

-- A seat people (and citizens) can sit on
function MapKit.seat(parent, name, size, cf, color, material, place)
	local s = Instance.new("Seat")
	s.Name = name
	s.Anchored = true
	s.Size = size
	s.CFrame = cf
	s.Color = color
	s.Material = material or Enum.Material.Fabric
	s.TopSurface = Enum.SurfaceType.Smooth
	s.BottomSurface = Enum.SurfaceType.Smooth
	s.Parent = parent
	table.insert(MapKit.Registry.Seats, { Seat = s, Place = place })
	pcall(CollectionService.AddTag, CollectionService, s, "CitySeat")
	return s
end

function MapKit.tag(inst, tagName)
	pcall(CollectionService.AddTag, CollectionService, inst, tagName)
	return inst
end

-- Text on one face of a part
function MapKit.signText(p, face, text, color, font, pixelsPerStud)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 30
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or MapKit.WHITE
	label.TextStrokeTransparency = 0.6
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = p
	return label
end

function MapKit.light(p, color, range, brightness, shadows)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = shadows == true
	l.Parent = p
	return l
end

function MapKit.spot(p, face, color, range, angle, brightness)
	local l = Instance.new("SpotLight")
	l.Face = face
	l.Color = color
	l.Range = range
	l.Angle = angle or 90
	l.Brightness = brightness or 1
	l.Shadows = false
	l.Parent = p
	return l
end

-- A light that only shines at night
function MapKit.nightLight(p, color, range, brightness)
	local l = MapKit.light(p, color, range, brightness)
	l.Enabled = false
	table.insert(MapKit.Registry.NightLights, l)
	return l
end

-- A part that glows (neon) at night and looks normal by day
function MapKit.nightNeon(p)
	table.insert(MapKit.Registry.NightNeon, { Part = p, Day = p.Material, DayColor = p.Color })
	return p
end

-- Food you can see: MapKit.food(parent, kind, cf, scale) puts one item with
-- its bottom at cf. Kinds: loaf, baguette, croissant, donut, cupcake, cake,
-- pie, muffin, pretzel, cookie, pasta, burger, pizza, fries
local CRUST, CRUMB = MapKit.rgb(196, 128, 60), MapKit.rgb(236, 206, 150)
local FROSTING = { MapKit.rgb(250, 180, 200), MapKit.rgb(120, 70, 40), MapKit.rgb(250, 250, 245), MapKit.rgb(170, 220, 250), MapKit.rgb(250, 220, 120) }
function MapKit.food(parent, kind, cf, scale)
	local s = scale or 1
	local deco, ball = MapKit.deco, MapKit.ball
	local function up(y)
		return cf * CFrame.new(0, y * s, 0)
	end
	local n = math.floor(math.abs(cf.Position.X * 7 + cf.Position.Z * 3)) % 5 + 1
	if kind == "loaf" then
		-- a capsule: a cylinder with rounded ends
		local body = deco(parent, "Loaf", Vector3.new(1, 0.8, 0.8) * s, up(0.4), CRUST)
		body.Shape = Enum.PartType.Cylinder
		for _, e in ipairs({ -0.5, 0.5 }) do
			ball(parent, "Loaf", 0.8 * s, up(0.4) * CFrame.new(e * s, 0, 0), CRUST)
		end
		deco(parent, "LoafScore", Vector3.new(0.9, 0.05, 0.1) * s, up(0.8) * CFrame.Angles(0, math.rad(25), 0), CRUMB)
	elseif kind == "baguette" then
		local p = deco(parent, "Baguette", Vector3.new(2.4, 0.35, 0.35) * s, up(0.18), CRUST)
		p.Shape = Enum.PartType.Cylinder
		for _, e in ipairs({ -1.2, 1.2 }) do
			ball(parent, "Baguette", 0.35 * s, up(0.18) * CFrame.new(e * s, 0, 0), CRUST)
		end
	elseif kind == "croissant" then
		for k = -1, 1 do
			ball(parent, "Croissant", (0.45 - math.abs(k) * 0.1) * s, up(0.2) * CFrame.new(k * 0.3 * s, 0, math.abs(k) * 0.12 * s), MapKit.rgb(220, 150, 70))
		end
	elseif kind == "donut" then
		local d = deco(parent, "Donut", Vector3.new(0.3, 0.8, 0.8) * s, up(0.15) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(210, 150, 80))
		d.Shape = Enum.PartType.Cylinder
		local icing = deco(parent, "DonutIcing", Vector3.new(0.08, 0.76, 0.76) * s, up(0.31) * CFrame.Angles(0, 0, math.rad(90)), FROSTING[n])
		icing.Shape = Enum.PartType.Cylinder
		local hole = deco(parent, "DonutHole", Vector3.new(0.1, 0.24, 0.24) * s, up(0.34) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(90, 60, 40))
		hole.Shape = Enum.PartType.Cylinder
	elseif kind == "cupcake" or kind == "muffin" then
		local c = deco(parent, "CupcakeCase", Vector3.new(0.4, 0.5, 0.5) * s, up(0.2) * CFrame.Angles(0, 0, math.rad(90)), if kind == "muffin" then MapKit.rgb(160, 110, 70) else MapKit.rgb(240, 240, 240))
		c.Shape = Enum.PartType.Cylinder
		ball(parent, "CupcakeTop", 0.58 * s, up(0.48), if kind == "muffin" then MapKit.rgb(150, 90, 60) else FROSTING[n])
		if kind == "cupcake" then
			ball(parent, "Cherry", 0.16 * s, up(0.8), MapKit.rgb(220, 30, 50))
		end
	elseif kind == "cake" then
		local c = deco(parent, "Cake", Vector3.new(0.9, 1.6, 1.6) * s, up(0.45) * CFrame.Angles(0, 0, math.rad(90)), FROSTING[n])
		c.Shape = Enum.PartType.Cylinder
		local top = deco(parent, "CakeTop", Vector3.new(0.1, 1.5, 1.5) * s, up(0.92) * CFrame.Angles(0, 0, math.rad(90)), MapKit.WHITE)
		top.Shape = Enum.PartType.Cylinder
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			ball(parent, "Berry", 0.18 * s, up(1) * CFrame.new(math.cos(a) * 0.55 * s, 0, math.sin(a) * 0.55 * s), MapKit.rgb(200, 30, 60))
		end
	elseif kind == "pie" then
		local p = deco(parent, "Pie", Vector3.new(0.35, 1.5, 1.5) * s, up(0.17) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(214, 160, 90))
		p.Shape = Enum.PartType.Cylinder
		for k = -1, 1 do
			deco(parent, "PieLattice", Vector3.new(1.3, 0.05, 0.12) * s, up(0.36) * CFrame.new(0, 0, k * 0.35 * s), MapKit.rgb(236, 190, 120))
			deco(parent, "PieLattice", Vector3.new(0.12, 0.05, 1.3) * s, up(0.36) * CFrame.new(k * 0.35 * s, 0, 0), MapKit.rgb(236, 190, 120))
		end
	elseif kind == "pretzel" then
		for k = -1, 1, 2 do
			local p = deco(parent, "Pretzel", Vector3.new(0.18, 0.5, 0.5) * s, up(0.09) * CFrame.new(k * 0.22 * s, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(150, 80, 30))
			p.Shape = Enum.PartType.Cylinder
		end
	elseif kind == "cookie" then
		local c = deco(parent, "Cookie", Vector3.new(0.12, 0.6, 0.6) * s, up(0.06) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(200, 150, 90))
		c.Shape = Enum.PartType.Cylinder
		for k = 0, 2 do
			deco(parent, "ChocChip", Vector3.new(0.08, 0.05, 0.08) * s, up(0.13) * CFrame.new((k - 1) * 0.15 * s, 0, (k % 2) * 0.12 * s), MapKit.rgb(70, 40, 20))
		end
	elseif kind == "pasta" then
		local pasta = deco(parent, "Pasta", Vector3.new(0.3, 0.8, 0.8) * s, up(0.15) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(240, 210, 120))
		pasta.Shape = Enum.PartType.Cylinder
		ball(parent, "Sauce", 0.45 * s, up(0.3), MapKit.rgb(200, 40, 30))
		ball(parent, "Basil", 0.14 * s, up(0.42), MapKit.rgb(60, 150, 60))
	elseif kind == "burger" then
		local bottom = deco(parent, "Bun", Vector3.new(0.22, 0.8, 0.8) * s, up(0.11) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(210, 150, 80))
		bottom.Shape = Enum.PartType.Cylinder
		deco(parent, "Patty", Vector3.new(0.78, 0.14, 0.78) * s, up(0.25), MapKit.rgb(100, 60, 40))
		deco(parent, "Lettuce", Vector3.new(0.84, 0.05, 0.84) * s, up(0.34), MapKit.rgb(100, 190, 70))
		deco(parent, "Cheese", Vector3.new(0.7, 0.04, 0.7) * s, up(0.37) * CFrame.Angles(0, math.rad(45), 0), MapKit.rgb(250, 200, 60))
		local top = deco(parent, "Bun", Vector3.new(0.3, 0.8, 0.8) * s, up(0.52) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(210, 150, 80))
		top.Shape = Enum.PartType.Cylinder
	elseif kind == "pizza" then
		local p = deco(parent, "Pizza", Vector3.new(0.1, 1.4, 1.4) * s, up(0.05) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(240, 190, 90))
		p.Shape = Enum.PartType.Cylinder
		local c = deco(parent, "PizzaCheese", Vector3.new(0.05, 1.2, 1.2) * s, up(0.11) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(250, 220, 130))
		c.Shape = Enum.PartType.Cylinder
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			local pep = deco(parent, "Pepperoni", Vector3.new(0.05, 0.26, 0.26) * s, up(0.14) * CFrame.new(math.cos(a) * 0.35 * s, 0, math.sin(a) * 0.35 * s) * CFrame.Angles(0, 0, math.rad(90)), MapKit.rgb(190, 50, 40))
			pep.Shape = Enum.PartType.Cylinder
		end
	elseif kind == "fries" then
		deco(parent, "FriesBox", Vector3.new(0.5, 0.5, 0.3) * s, up(0.25), MapKit.rgb(220, 40, 40))
		for k = 0, 4 do
			deco(parent, "Fry", Vector3.new(0.07, 0.4, 0.07) * s, up(0.6) * CFrame.new((k - 2) * 0.08 * s, 0, (k % 2) * 0.06 * s) * CFrame.Angles(0, 0, math.rad((k - 2) * 6)), MapKit.rgb(250, 210, 80))
		end
	end
end

-- A chess board lying flat at cf (its top surface), size studs across: an
-- 8x8 board with a frame and a game in progress (pawns and back-row pieces)
function MapKit.chessBoard(parent, cf, size)
	size = size or 2.6
	local sq = size / 8
	MapKit.deco(parent, "ChessFrame", Vector3.new(size + 0.3, 0.1, size + 0.3), cf * CFrame.new(0, -0.05, 0), MapKit.rgb(110, 76, 50), Enum.Material.Wood)
	MapKit.deco(parent, "ChessBoard", Vector3.new(size, 0.1, size), cf * CFrame.new(0, 0.01, 0), MapKit.rgb(240, 232, 214), Enum.Material.Marble)
	for i = 0, 7 do
		for j = 0, 7 do
			if (i + j) % 2 == 1 then
				MapKit.deco(parent, "ChessSquare", Vector3.new(sq, 0.11, sq), cf * CFrame.new(-size / 2 + sq / 2 + i * sq, 0.012, -size / 2 + sq / 2 + j * sq), MapKit.rgb(90, 64, 46), Enum.Material.Marble)
			end
		end
	end
	-- a few pieces for each side (some pawns have already moved)
	local layout = { { 0, 1 }, { 2, 1 }, { 3, 3 }, { 5, 1 }, { 6, 2 }, { 1, 0 }, { 4, 0 }, { 7, 0 } }
	for side = 0, 1 do
		local color = if side == 0 then MapKit.rgb(245, 240, 228) else MapKit.rgb(40, 36, 36)
		for k, pos in ipairs(layout) do
			local i, j = pos[1], if side == 0 then pos[2] else 7 - pos[2]
			local x, z = -size / 2 + sq / 2 + i * sq, -size / 2 + sq / 2 + j * sq
			local tall = k > 5
			local body = MapKit.deco(parent, "ChessPiece", Vector3.new(if tall then 0.32 else 0.22, sq * 0.55, sq * 0.55), cf * CFrame.new(x, (if tall then 0.16 else 0.11) + 0.06, z) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.SmoothPlastic)
			body.Shape = Enum.PartType.Cylinder
			MapKit.ball(parent, "ChessPieceTop", sq * (if tall then 0.45 else 0.38), cf * CFrame.new(x, (if tall then 0.38 else 0.27) + 0.06, z), color, Enum.Material.SmoothPlastic)
		end
	end
end

-- Particle effects that bring the city to life
--   "smoke"      soft grey puffs rising from a chimney
--   "fireflies"  little glowing specks that drift at night (parks, ponds)
--   "leaves"     leaves drifting down from a tree
function MapKit.particles(p, kind)
	local e = Instance.new("ParticleEmitter")
	e.Name = "City" .. kind
	e.LockedToPart = false
	if kind == "smoke" then
		e.Color = ColorSequence.new(MapKit.rgb(210, 210, 214), MapKit.rgb(160, 160, 168))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4.5) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(4, 6)
		e.Rate = 3
		e.Speed = NumberRange.new(2, 3.5)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Acceleration = Vector3.new(1.2, 0.4, 0.6) -- a light breeze
		e.RotSpeed = NumberRange.new(-20, 20)
		e.EmissionDirection = Enum.NormalId.Top
	elseif kind == "fireflies" then
		e.Color = ColorSequence.new(MapKit.rgb(230, 255, 140))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.28), NumberSequenceKeypoint.new(0.8, 0.28), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(4, 7)
		e.Rate = 5
		e.Speed = NumberRange.new(0.4, 1.2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 0.15, 0)
		e.Enabled = false
		table.insert(MapKit.Registry.NightParticles, e)
	elseif kind == "leaves" then
		e.Color = ColorSequence.new(MapKit.rgb(120, 170, 60), MapKit.rgb(220, 160, 60))
		e.Size = NumberSequence.new(0.35)
		e.Lifetime = NumberRange.new(5, 8)
		e.Rate = 0.8
		e.Speed = NumberRange.new(0.5, 1)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0.4, -1.1, 0.2)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.Rotation = NumberRange.new(0, 360)
	end
	e.Parent = p
	return e
end

-- Striped awning made of wedges; cf is the awning's center, sloping down toward -Z
function MapKit.awning(parent, width, depth, cf, colorA, colorB)
	local stripes = math.max(3, math.floor(width / 2.2))
	local w = width / stripes
	for k = 0, stripes - 1 do
		local x = -width / 2 + w * (k + 0.5)
		MapKit.wedge(parent, "Awning", Vector3.new(w, 1.6, depth), cf * CFrame.new(x, 0, 0), if k % 2 == 0 then colorA else colorB, Enum.Material.Fabric)
	end
	-- scalloped front edge
	MapKit.deco(parent, "AwningEdge", Vector3.new(width, 0.5, 0.15), cf * CFrame.new(0, -1.05, -depth / 2 + 0.05), colorA, Enum.Material.Fabric)
end

return MapKit
