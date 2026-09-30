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
