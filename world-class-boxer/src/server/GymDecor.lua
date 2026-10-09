-- GymDecor: everything that turns the training complex from a box into a real boxing gym.
-- Interior structure (steel trusses, columns, ducts, pendant lamps, windows trim, wainscot),
-- zone decor (flags, fight posters, glove racks, round timers, kettlebells, tire & sledgehammer,
-- battle ropes, decorative cardio machines, towel shelves, barber/locker/nutrition details,
-- lobby reception, lounge, vending, trophies, belt display, hall of fame), the pool hall,
-- the building's exterior (facade sign, awning, doors, pilasters, cornice, wall lamps,
-- sidewalk, planters, rooftop units) and the gym's lighting rig.
-- Animated pieces (fans, round timers, TV tickers, neon flicker, barber pole) are tagged and
-- driven client-side by Ambience. Everything is anchored; small props never collide.
local CollectionService = game:GetService("CollectionService")

local GymDecor = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material

------------------------------------------------------------------------
-- palette
------------------------------------------------------------------------
local C = {
	steel = Color3.fromRGB(58, 60, 66),
	steelLight = Color3.fromRGB(150, 153, 160),
	galv = Color3.fromRGB(172, 175, 182),
	black = Color3.fromRGB(24, 24, 28),
	white = Color3.fromRGB(236, 236, 240),
	wood = Color3.fromRGB(140, 100, 65),
	woodDark = Color3.fromRGB(72, 50, 36),
	red = Color3.fromRGB(196, 30, 36),
	blue = Color3.fromRGB(30, 60, 170),
	gold = Color3.fromRGB(255, 196, 40),
	goldDeep = Color3.fromRGB(212, 160, 40),
	green = Color3.fromRGB(40, 140, 70),
	concrete = Color3.fromRGB(168, 166, 160),
	leather = Color3.fromRGB(48, 36, 30),
	wainscot = Color3.fromRGB(42, 44, 50),
	brick = Color3.fromRGB(122, 66, 52),
	brickDark = Color3.fromRGB(96, 52, 42),
	terracotta = Color3.fromRGB(176, 96, 62),
	leaf = Color3.fromRGB(56, 120, 60),
	rubber = Color3.fromRGB(32, 32, 35),
}

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function part(parent, name, size, cf, color, material, opts)
	opts = opts or {}
	local p = Instance.new(opts.class or "Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local collide = opts.collide == true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	if opts.shape then
		p.Shape = opts.shape
	end
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	if opts.reflect then
		p.Reflectance = opts.reflect
	end
	if opts.shadow == false then
		p.CastShadow = false
	end
	p.Parent = parent
	return p
end

-- cylinder along local X
local function cyl(parent, name, length, diameter, cf, color, material, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Cylinder
	return part(parent, name, V3(length, diameter, diameter), cf, color, material, opts)
end

-- vertical cylinder standing on a base CFrame
local function vcyl(parent, name, height, diameter, baseCF, color, material, opts)
	return cyl(parent, name, height, diameter, baseCF * CF(0, height / 2, 0) * ANG(0, 0, RAD(90)), color, material, opts)
end

local function ball(parent, name, d, cf, color, material, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Ball
	return part(parent, name, V3(d, d, d), cf, color, material, opts)
end

-- squashed sphere (gloves, fruit, foliage)
local function blob(parent, name, size, cf, color, material, opts)
	local p = part(parent, name, size, cf, color, material, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- a cylinder-ish bar between two points
local function rod(parent, name, a, b, d, color, material, opts)
	local len = (b - a).Magnitude
	return part(parent, name, V3(d, d, len), CFrame.lookAt((a + b) / 2, b), color, material, opts)
end

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

local function gui(p, face, ppu, light)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 40
	sg.LightInfluence = light or 0
	sg.MaxDistance = 260
	sg.Parent = p
	return sg
end

local function label(parent, text, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextWrapped = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = text
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	t.Parent = parent
	return t
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

-- simple text sign on one face
local function sign(p, face, text, fg, bg, ppu, light, font)
	local sg = gui(p, face, ppu or 40, light or 0)
	if bg then
		frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = bg })
	end
	label(sg, text, { TextColor3 = fg or Color3.new(1, 1, 1), Font = font or Enum.Font.GothamBlack, Size = UDim2.new(0.94, 0, 0.86, 0), Position = UDim2.fromScale(0.03, 0.07) })
	return sg
end

local function spot(p, face, color, range, brightness, angle, shadows)
	local l = Instance.new("SpotLight")
	l.Face = face or Enum.NormalId.Bottom
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Angle = angle or 90
	l.Shadows = shadows == true
	l.Parent = p
	return l
end

local function point(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return l
end

-- an invisible emitter part (lights live in their own part so fixtures never shadow them)
local function emitter(parent, cf)
	return part(parent, "LightSource", V3(0.2, 0.2, 0.2), cf, Color3.new(1, 1, 1), M.SmoothPlastic, { transparency = 1, shadow = false })
end

local function tag(inst, name)
	CollectionService:AddTag(inst, name)
	return inst
end

------------------------------------------------------------------------
-- Wall-mounted items. Interior faces of the building shell and the zone dividers:
-- along = coordinate along the wall, depth = how far the item sticks out.
------------------------------------------------------------------------
local WALLS = {
	N = { axis = "X", plane = -79, sign = 1, out = Enum.NormalId.Back },
	S = { axis = "X", plane = 79, sign = -1, out = Enum.NormalId.Front },
	W = { axis = "Z", plane = -109, sign = 1, out = Enum.NormalId.Right },
	E = { axis = "Z", plane = 109, sign = -1, out = Enum.NormalId.Left },
	DWb = { axis = "Z", plane = -49, sign = 1, out = Enum.NormalId.Right }, -- x=-50 divider, boxing side
	DWw = { axis = "Z", plane = -51, sign = -1, out = Enum.NormalId.Left }, -- x=-50 divider, weight room side
	DEb = { axis = "Z", plane = 49, sign = -1, out = Enum.NormalId.Left }, -- x=+50 divider, boxing side
	DEc = { axis = "Z", plane = 51, sign = 1, out = Enum.NormalId.Right }, -- x=+50 divider, cardio side
	DZs = { axis = "X", plane = 21, sign = 1, out = Enum.NormalId.Back }, -- z=20 dividers, south face
	DZn = { axis = "X", plane = 19, sign = -1, out = Enum.NormalId.Front }, -- z=20 dividers, north face
	XS = { axis = "X", plane = 81, sign = 1, out = Enum.NormalId.Back }, -- exterior south facade
	XN = { axis = "X", plane = -81, sign = -1, out = Enum.NormalId.Front },
	XW = { axis = "Z", plane = -111, sign = -1, out = Enum.NormalId.Left },
	XE = { axis = "Z", plane = 111, sign = 1, out = Enum.NormalId.Right },
}

local function onWall(parent, name, wallId, along, y, width, height, depth, color, material, opts, gap)
	local w = WALLS[wallId]
	local off = w.plane + w.sign * ((gap or 0) + depth / 2)
	local size, pos
	if w.axis == "X" then
		size, pos = V3(width, height, depth), V3(along, y, off)
	else
		size, pos = V3(depth, height, width), V3(off, y, along)
	end
	return part(parent, name, size, CF(pos), color, material, opts), w.out
end

-- the outward normal of a wall as a vector, and a CFrame on the wall that looks out of it
local function wallNormal(wallId)
	local w = WALLS[wallId]
	return w.axis == "X" and V3(0, 0, w.sign) or V3(w.sign, 0, 0)
end

local function wallPoint(wallId, along, y, out)
	local w = WALLS[wallId]
	local off = w.plane + w.sign * (out or 0)
	return w.axis == "X" and V3(along, y, off) or V3(off, y, along)
end

------------------------------------------------------------------------
-- Reusable pieces
------------------------------------------------------------------------
-- fight poster: a SurfaceGui with a header band, headline, fighters and a footer
local POSTERS = {
	{ bg = Color3.fromRGB(18, 18, 22), accent = C.red, top = "FRIDAY NIGHT FIGHTS", title = "CARTER\nvs\nSANTOS", sub = "10 ROUNDS - WELTERWEIGHT", foot = "LIVE AT THE WCB ARENA" },
	{ bg = Color3.fromRGB(240, 196, 40), accent = Color3.fromRGB(20, 20, 24), top = "GOLDEN GLOVES", title = "REGIONAL\nTOURNAMENT", sub = "AMATEUR SHOWCASE", foot = "SATURDAY 7PM - DOORS 6PM", dark = true },
	{ bg = Color3.fromRGB(14, 24, 52), accent = C.gold, top = "THE RECKONING", title = "VEGA\nvs\nKOVAC", sub = "12 ROUNDS - WORLD TITLE", foot = "PAY-PER-VIEW" },
	{ bg = Color3.fromRGB(120, 16, 20), accent = C.white, top = "CHAMPIONSHIP NIGHT", title = "HEAVYWEIGHT\nUNIFICATION", sub = "4 BELTS - 1 KING", foot = "SOLD OUT" },
	{ bg = Color3.fromRGB(28, 28, 32), accent = Color3.fromRGB(60, 170, 255), top = "WCB PRESENTS", title = "BLOOD &\nGLORY", sub = "OKAFOR vs MERCER", foot = "LIVE ON WCB SPORTS" },
	{ bg = Color3.fromRGB(235, 235, 235), accent = C.red, top = "CITY CHAMPIONSHIPS", title = "RUMBLE\nON THE\nWATERFRONT", sub = "8 BOUTS - ALL WEIGHTS", foot = "TICKETS AT THE FRONT DESK", dark = true },
}

local function posterGui(p, face, d)
	local sg = gui(p, face, 40, 0.5)
	local fg = d.dark and Color3.fromRGB(20, 20, 24) or Color3.new(1, 1, 1)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = d.bg })
	frame(sg, { Size = UDim2.new(1, 0, 0.15, 0), BackgroundColor3 = d.accent })
	frame(sg, { Size = UDim2.new(1, 0, 0.02, 0), Position = UDim2.fromScale(0, 0.8), BackgroundColor3 = d.accent })
	label(sg, d.top, { TextColor3 = d.dark and C.gold or d.bg, Size = UDim2.new(0.92, 0, 0.11, 0), Position = UDim2.fromScale(0.04, 0.02) })
	label(sg, d.title, { TextColor3 = fg, Size = UDim2.new(0.9, 0, 0.44, 0), Position = UDim2.fromScale(0.05, 0.19) })
	label(sg, d.sub, { TextColor3 = d.accent, Font = Enum.Font.GothamBold, Size = UDim2.new(0.9, 0, 0.09, 0), Position = UDim2.fromScale(0.05, 0.66) })
	label(sg, d.foot, { TextColor3 = fg, Font = Enum.Font.GothamBold, Size = UDim2.new(0.9, 0, 0.08, 0), Position = UDim2.fromScale(0.05, 0.86) })
	return sg
end

local posterIndex = 0
local function wallPoster(parent, wallId, along, y, w, h)
	posterIndex += 1
	local d = POSTERS[(posterIndex - 1) % #POSTERS + 1]
	local frameP, face = onWall(parent, "PosterFrame", wallId, along, y, w + 0.3, h + 0.3, 0.1, C.black, M.SmoothPlastic)
	local p = onWall(parent, "Poster", wallId, along, y, w, h, 0.12, d.bg, M.SmoothPlastic, nil, 0.04)
	posterGui(p, face, d)
	return frameP
end

-- big painted wall text
local function wallText(parent, wallId, along, y, w, h, text, color, font)
	local p, face = onWall(parent, "WallText", wallId, along, y, w, h, 0.05, Color3.new(), M.SmoothPlastic, { transparency = 1 }, 0.01)
	local sg = gui(p, face, 30, 0.6)
	label(sg, text, { TextColor3 = color or Color3.new(1, 1, 1), Font = font or Enum.Font.GothamBlack, TextStrokeTransparency = 0.7 })
	return p
end

-- industrial fan facing direction f (animated by Ambience: hub spins about its local X)
local function fan(parent, center, f, size, color)
	local m = model(parent, "Fan")
	local hubCF = CFrame.lookAt(center, center + f) * ANG(0, RAD(90), 0)
	local r = size / 2
	cyl(m, "Housing", 0.5, size + 0.4, hubCF * CF(-0.45, 0, 0), C.black, M.Metal)
	cyl(m, "HousingRim", 0.7, size + 0.6, hubCF * CF(-0.3, 0, 0), color or C.steelLight, M.Metal, { transparency = 0.0 })
	local hub = cyl(m, "Hub", 0.6, size * 0.18, hubCF, C.steel, M.Metal)
	for i = 0, 2 do
		part(m, "Blade", V3(0.12, r * 0.88, size * 0.2), hubCF * ANG(i * RAD(120), 0, 0) * CF(0.05, r * 0.5, 0) * ANG(RAD(18), 0, 0), C.steelLight, M.Metal)
	end
	for i = 0, 1 do
		part(m, "Guard", V3(0.1, size, 0.12), hubCF * CF(0.45, 0, 0) * ANG(RAD(45 + i * 90), 0, 0), C.steel, M.Metal)
	end
	cyl(m, "GuardRing", 0.12, size * 0.3, hubCF * CF(0.45, 0, 0), C.steel, M.Metal)
	m.PrimaryPart = hub
	m:SetAttribute("Speed", 9)
	tag(m, "SpinFan")
	return m
end

-- potted plant
local function plant(parent, pos, scale, potColor)
	scale = scale or 1
	vcyl(parent, "PlantPot", 1.6 * scale, 1.8 * scale, CF(pos), potColor or C.terracotta, M.Slate, { collide = true })
	vcyl(parent, "PlantSoil", 0.1, 1.6 * scale, CF(pos + V3(0, 1.55 * scale, 0)), Color3.fromRGB(60, 42, 30), M.Ground)
	blob(parent, "PlantLeaves", V3(2.6, 3.0, 2.6) * scale, CF(pos + V3(0, 3.1 * scale, 0)), C.leaf, M.Grass)
	blob(parent, "PlantLeaves", V3(1.8, 2.2, 1.8) * scale, CF(pos + V3(0.6 * scale, 4.2 * scale, 0.3 * scale)), Color3.fromRGB(70, 140, 72), M.Grass)
end

-- simple chair facing direction yaw (0 = facing -Z)
local function chair(parent, pos, yaw, seatColor, frameColor)
	local base = CF(pos) * ANG(0, yaw or 0, 0)
	part(parent, "ChairSeat", V3(1.9, 0.3, 1.9), base * CF(0, 1.75, 0), seatColor or C.leather, M.Leather, { collide = true })
	part(parent, "ChairBack", V3(1.9, 2.0, 0.25), base * CF(0, 2.9, 0.85), seatColor or C.leather, M.Leather)
	for _, x in ipairs({ -0.8, 0.8 }) do
		for _, z in ipairs({ -0.8, 0.8 }) do
			part(parent, "ChairLeg", V3(0.14, 1.6, 0.14), base * CF(x, 0.8, z), frameColor or C.steel, M.Metal)
		end
	end
end

-- bench along local X (yaw rotates it)
local function bench(parent, pos, yaw, length, color)
	local base = CF(pos) * ANG(0, yaw or 0, 0)
	part(parent, "BenchSeat", V3(length, 0.35, 1.8), base * CF(0, 1.7, 0), color or C.wood, M.WoodPlanks, { collide = true })
	for _, x in ipairs({ -length / 2 + 0.6, length / 2 - 0.6 }) do
		part(parent, "BenchLeg", V3(0.3, 1.55, 1.5), base * CF(x, 0.78, 0), C.steel, M.Metal)
	end
end

-- glove pair hanging by its laces (for racks)
local GLOVE_COLORS = { C.red, Color3.fromRGB(25, 25, 28), C.blue, Color3.fromRGB(230, 180, 30), Color3.fromRGB(235, 235, 240), Color3.fromRGB(40, 150, 70), Color3.fromRGB(150, 40, 170), Color3.fromRGB(240, 120, 30) }
local function glovePair(parent, cf, color)
	for _, s in ipairs({ -0.55, 0.55 }) do
		blob(parent, "Glove", V3(0.9, 1.25, 1.0), cf * CF(s, -0.9, 0), color, M.Leather)
		cyl(parent, "GloveCuff", 0.7, 0.7, cf * CF(s, -0.15, 0) * ANG(0, 0, RAD(90)), C.white, M.Fabric)
	end
end

-- championship belt (strap along local X, plate facing local -Z)
local function belt(parent, cf, strapColor, scale)
	scale = scale or 1
	part(parent, "BeltStrap", V3(3.8, 0.9, 0.12) * scale, cf, strapColor, M.Leather)
	part(parent, "BeltPlate", V3(1.5, 1.35, 0.18) * scale, cf * CF(0, 0, -0.06 * scale), C.gold, M.Metal, { reflect = 0.15 })
	cyl(parent, "BeltJewel", 0.08, 0.5 * scale, cf * CF(0, 0.05 * scale, -0.16 * scale) * ANG(0, RAD(90), 0), C.red, M.Glass)
	for _, x in ipairs({ -1.25, 1.25 }) do
		part(parent, "BeltSidePlate", V3(0.6, 0.75, 0.16) * scale, cf * CF(x * scale, 0, -0.05 * scale), C.goldDeep, M.Metal)
	end
end

-- trophy cup standing on a base CFrame
local function trophy(parent, baseCF, h, color)
	color = color or C.gold
	part(parent, "TrophyBase", V3(0.9, 0.45, 0.9) * h, baseCF * CF(0, 0.225 * h, 0), C.black, M.Marble)
	vcyl(parent, "TrophyStem", 0.7 * h, 0.22 * h, baseCF * CF(0, 0.45 * h, 0), color, M.Metal)
	vcyl(parent, "TrophyCup", 0.85 * h, 0.9 * h, baseCF * CF(0, 1.1 * h, 0), color, M.Metal, { reflect = 0.2 })
	for _, s in ipairs({ -1, 1 }) do
		part(parent, "TrophyHandle", V3(0.12, 0.55, 0.12) * h, baseCF * CF(s * 0.52 * h, 1.55 * h, 0), color, M.Metal)
	end
end

-- simple decorative treadmill (user stands at +Z facing -Z); returns belt-top height above the floor
local function decorTreadmill(parent, pos)
	local O = CF(pos)
	part(parent, "TMDeck", V3(3, 0.55, 7), O * CF(0, 0.28, 0), C.black, M.SmoothPlastic, { collide = true })
	part(parent, "TMBelt", V3(2.3, 0.06, 6.6), O * CF(0, 0.58, 0.1), Color3.fromRGB(30, 30, 30), M.Rubber)
	part(parent, "TMHood", V3(3.1, 0.9, 1.3), O * CF(0, 0.55, -3.6), Color3.fromRGB(40, 40, 46), M.SmoothPlastic)
	for _, x in ipairs({ -1.4, 1.4 }) do
		part(parent, "TMUpright", V3(0.25, 4.3, 0.25), O * CF(x, 2.6, -3.4) * ANG(RAD(-8), 0, 0), C.steelLight, M.Metal)
		part(parent, "TMRail", V3(0.18, 0.18, 2.4), O * CF(x, 4.2, -2.2), C.steelLight, M.Metal)
	end
	local console = part(parent, "TMConsole", V3(3.2, 1.2, 0.45), O * CF(0, 4.8, -3.7) * ANG(RAD(-25), 0, 0), C.black, M.SmoothPlastic)
	sign(console, Enum.NormalId.Back, "6.8 MPH\n2.41 MI", Color3.fromRGB(90, 220, 255), Color3.fromRGB(8, 10, 14), 40)
	return 0.61
end

-- simple decorative upright bike (rider faces -Z); seat top 2.7 above the floor
local function decorBike(parent, pos)
	local O = CF(pos)
	part(parent, "BikeRail", V3(0.4, 0.3, 4.4), O * CF(0, 0.15, -0.4), C.black, M.Metal, { collide = true })
	part(parent, "BikeFootF", V3(2.4, 0.3, 0.4), O * CF(0, 0.15, -2.4), C.black, M.Metal)
	part(parent, "BikeFootB", V3(2.4, 0.3, 0.4), O * CF(0, 0.15, 1.6), C.black, M.Metal)
	part(parent, "BikeSeatPost", V3(0.3, 2.5, 0.3), O * CF(0, 1.35, 1.0) * ANG(RAD(-12), 0, 0), C.red, M.Metal)
	part(parent, "BikeSeat", V3(1.0, 0.25, 1.3), O * CF(0, 2.58, 1.0), C.black, M.Leather)
	part(parent, "BikeColumn", V3(0.3, 3.5, 0.3), O * CF(0, 1.9, -1.5) * ANG(RAD(15), 0, 0), C.red, M.Metal)
	part(parent, "BikeBar", V3(2.2, 0.2, 0.2), O * CF(0, 3.7, -1.95), C.black, M.Metal)
	cyl(parent, "BikeFlywheel", 0.35, 2.0, O * CF(0, 1.3, -2.1) * ANG(0, RAD(90), 0), C.steelLight, M.Metal)
	return 2.7
end

------------------------------------------------------------------------
-- 1. Interior structure: trusses, columns, ducts, wainscot, exit signs, extinguishers, speakers
------------------------------------------------------------------------
local function buildStructure(root)
	local f = folder(root, "Structure")
	-- steel I-beam trusses spanning the hall (north-south), purlins across them
	for _, x in ipairs({ -90, -60, -30, 0, 30, 60, 90 }) do
		part(f, "TrussBottom", V3(1.2, 0.25, 158), CF(x, 28.25, 0), C.steel, M.Metal, { shadow = false })
		part(f, "TrussWeb", V3(0.3, 1.3, 158), CF(x, 29.0, 0), C.steel, M.Metal, { shadow = false })
		part(f, "TrussTop", V3(1.2, 0.25, 158), CF(x, 29.75, 0), C.steel, M.Metal, { shadow = false })
		-- diagonal web members every 20 studs give the truss its look
		for z = -70, 70, 20 do
			part(f, "TrussBrace", V3(0.2, 0.2, 2.2), CF(x, 28.9, z) * ANG(RAD(35), 0, 0), C.steel, M.Metal, { shadow = false })
		end
	end
	for _, z in ipairs({ -60, -20, 20, 60 }) do
		part(f, "Purlin", V3(218, 0.35, 0.5), CF(0, 29.7, z), C.steel, M.Metal, { shadow = false })
	end
	-- steel columns against the long walls (kept clear of signs and windows)
	for _, x in ipairs({ -90, -60, 60, 90 }) do
		for _, z in ipairs({ -78.4, 78.4 }) do
			part(f, "ColumnFlange", V3(1.2, 27.9, 0.22), CF(x, 14.35, z - 0.45), C.steel, M.Metal)
			part(f, "ColumnFlange", V3(1.2, 27.9, 0.22), CF(x, 14.35, z + 0.45), C.steel, M.Metal)
			part(f, "ColumnWeb", V3(0.3, 27.9, 0.9), CF(x, 14.35, z), C.steel, M.Metal)
			part(f, "ColumnBase", V3(1.8, 0.4, 1.4), CF(x, 0.7, z), C.steel, M.Metal)
		end
	end
	-- round ducts with hangers, joints and vent grilles
	for _, z in ipairs({ -40, 40 }) do
		cyl(f, "Duct", 214, 2.2, CF(0, 26, z), C.galv, M.Metal, { shadow = false })
		for x = -105, 105, 15 do
			cyl(f, "DuctJoint", 0.3, 2.35, CF(x, 26, z), C.steelLight, M.Metal, { shadow = false })
		end
		for x = -90, 90, 30 do
			part(f, "DuctHanger", V3(0.12, 2.9, 0.12), CF(x + 7, 28.6, z), C.steel, M.Metal, { shadow = false })
			part(f, "DuctStrap", V3(0.15, 0.15, 2.5), CF(x + 7, 27.15, z), C.steel, M.Metal, { shadow = false })
		end
		for x = -95, 95, 30 do
			part(f, "Vent", V3(1.8, 0.35, 1.3), CF(x, 24.85, z), Color3.fromRGB(80, 82, 88), M.Metal, { shadow = false })
			for k = -1, 1 do
				part(f, "VentSlat", V3(1.6, 0.05, 0.12), CF(x, 24.66, z + k * 0.35), C.black, M.Metal, { shadow = false })
			end
		end
	end
	-- wainscot band, red stripe and baseboard on the inside of the shell (skipping doorways)
	local function band(wallId, from, to)
		local mid, len = (from + to) / 2, to - from
		onWall(f, "Wainscot", wallId, mid, 2.4, len, 4, 0.12, C.wainscot, M.SmoothPlastic, nil, 0.01)
		onWall(f, "WallStripe", wallId, mid, 4.65, len, 0.5, 0.14, C.red, M.SmoothPlastic, nil, 0.01)
		onWall(f, "Baseboard", wallId, mid, 0.7, len + 0.04, 0.6, 0.2, C.black, M.SmoothPlastic, nil, 0.01)
	end
	band("N", -109, -8)
	band("N", 8, 109)
	band("S", -109, -10)
	band("S", 10, 109)
	band("W", -79, 79)
	-- the east wall opens into the Elite Performance Wing at z 44..56 (MapBuilder.EliteWing)
	band("E", -79, 43.5)
	band("E", 56.5, 79)
	-- EXIT signs over both doorways
	for _, d in ipairs({ { "S", 0 }, { "N", 0 } }) do
		local box, face = onWall(f, "ExitSign", d[1], d[2], 15.3, 3, 1, 0.4, Color3.fromRGB(20, 20, 22), M.SmoothPlastic)
		sign(box, face, "EXIT", Color3.fromRGB(90, 255, 120), Color3.fromRGB(14, 30, 16), 40)
	end
	-- fire extinguishers with their wall signs
	for _, d in ipairs({ { "W", 0 }, { "E", -12 }, { "S", -14 }, { "N", 14 }, { "DWw", -24 }, { "DEc", -24 } }) do
		local n = wallNormal(d[1])
		local base = wallPoint(d[1], d[2], 1.6, 0.5)
		vcyl(f, "Extinguisher", 2.0, 0.7, CF(base), C.red, M.SmoothPlastic)
		vcyl(f, "ExtinguisherTop", 0.4, 0.35, CF(base + V3(0, 2.0, 0)), C.black, M.Metal)
		part(f, "ExtinguisherHose", V3(0.12, 1.2, 0.12), CF(base + V3(0, 1.4, 0) + n * 0.4), C.black, M.Rubber)
		local s, face = onWall(f, "ExtinguisherSign", d[1], d[2], 5.9, 1.0, 1.0, 0.06, C.red, M.SmoothPlastic, nil, 0.16)
		sign(s, face, "FIRE", Color3.new(1, 1, 1), C.red, 40)
	end
	-- wall speakers and security cameras
	for _, d in ipairs({ { "N", -37, 21.5 }, { "N", 37, 21.5 }, { "S", -66, 21 }, { "S", 66, 21 }, { "W", 10, 21 }, { "E", 10, 21 } }) do
		local box = onWall(f, "Speaker", d[1], d[2], d[3], 1.6, 2.4, 1.1, C.black, M.SmoothPlastic, nil, 0.05)
		local n = wallNormal(d[1])
		local front = box.Position + n * 0.56
		for k, yy in ipairs({ 0.5, -0.45 }) do
			cyl(f, "SpeakerCone", 0.06, k == 1 and 0.6 or 0.95, CFrame.lookAt(front + V3(0, yy, 0), front + V3(0, yy, 0) + n) * ANG(0, RAD(90), 0), Color3.fromRGB(60, 60, 64), M.Fabric)
		end
	end
	for _, d in ipairs({ { "N", -100 }, { "S", 100 }, { "W", -70 }, { "E", 70 } }) do
		local n = wallNormal(d[1])
		local p = wallPoint(d[1], d[2], 26, 0.6)
		part(f, "CameraMount", V3(0.3, 0.3, 0.3), CF(p), C.white, M.SmoothPlastic)
		part(f, "SecurityCamera", V3(0.6, 0.6, 1.4), CFrame.lookAt(p + n * 0.7 - V3(0, 0.3, 0), p + n * 4 - V3(0, 2.5, 0)), C.white, M.SmoothPlastic)
	end
end

------------------------------------------------------------------------
-- 2. Lighting rig (interior)
------------------------------------------------------------------------
-- warm key light from the pendants: a boxer under the grid reads at mid grey (the lamps were tuned
-- for a much darker hall; Future's falloff over the 19 studs to chest height needs ~2.5)
local LIGHT = {
	boxing = { color = Color3.fromRGB(255, 236, 210), brightness = 2.7 },
	weights = { color = Color3.fromRGB(255, 238, 218), brightness = 2.6 },
	cardio = { color = Color3.fromRGB(230, 240, 255), brightness = 2.6 },
	recovery = { color = Color3.fromRGB(255, 226, 192), brightness = 2.1 },
	services = { color = Color3.fromRGB(255, 228, 196), brightness = 2.3 },
	lobby = { color = Color3.fromRGB(255, 232, 200), brightness = 2.4 },
}

local function zoneLight(x, z)
	if math.abs(x) <= 45 then
		return z < 4 and LIGHT.boxing or LIGHT.lobby
	elseif x < 0 then
		return z < 20 and LIGHT.weights or LIGHT.services
	else
		return z < 20 and LIGHT.cardio or LIGHT.recovery
	end
end

local function pendant(parent, x, z, y, zone)
	local m = model(parent, "PendantLamp")
	part(m, "LampCable", V3(0.08, 30 - (y + 0.6), 0.08), CF(x, (30 + y + 0.6) / 2, z), C.black, M.Metal, { shadow = false })
	vcyl(m, "LampCap", 0.6, 1.1, CF(x, y + 0.3, z), Color3.fromRGB(34, 52, 44), M.Metal, { shadow = false })
	vcyl(m, "LampShade", 0.55, 2.6, CF(x, y - 0.25, z), Color3.fromRGB(34, 52, 44), M.Metal, { shadow = false })
	vcyl(m, "LampShadeRim", 0.25, 3.6, CF(x, y - 0.5, z), Color3.fromRGB(28, 44, 36), M.Metal, { shadow = false })
	vcyl(m, "LampReflector", 0.05, 3.3, CF(x, y - 0.27, z), Color3.fromRGB(245, 240, 225), M.SmoothPlastic, { shadow = false })
	ball(m, "LampBulb", 0.95, CF(x, y - 0.55, z), zone.color, M.Neon, { shadow = false })
	local src = emitter(m, CF(x, y - 1.2, z))
	-- a wide cone so neighbouring pools overlap (no dark bands between lamps 30 studs apart)
	spot(src, Enum.NormalId.Bottom, zone.color, 58, zone.brightness, 130, false)
	return m
end

local function buildLights(root)
	local f = folder(root, "Lighting")
	for x = -90, 90, 30 do
		for z = -60, 60, 30 do
			if not (x == 0 and z == -60) then -- the ring has its own canopy
				pendant(f, x, z, 23.8, zoneLight(x, z))
			end
		end
	end
	-- sparring ring canopy: a square truss with four shadow-casting cans aimed at the canvas
	local rc = V3(0, 0, -50)
	local y = 19.5
	for _, s in ipairs({ -9, 9 }) do
		part(f, "CanopyBar", V3(18.6, 0.6, 0.6), CF(rc + V3(0, y, s)), C.black, M.Metal, { shadow = false })
		part(f, "CanopyBar", V3(0.6, 0.6, 18.6), CF(rc + V3(s, y, 0)), C.black, M.Metal, { shadow = false })
	end
	for _, c in ipairs({ { -9, -9 }, { 9, -9 }, { 9, 9 }, { -9, 9 } }) do
		local corner = rc + V3(c[1], y, c[2])
		part(f, "CanopyCable", V3(0.08, 30 - y, 0.08), CF(corner + V3(0, (30 - y) / 2, 0)), C.black, M.Metal, { shadow = false })
		local canPos = corner - V3(0, 0.9, 0)
		local can = part(f, "RingCan", V3(1.2, 1.2, 1.9), CFrame.lookAt(canPos, rc + V3(0, 3, 0)), C.black, M.Metal, { shadow = false })
		part(f, "RingCanLens", V3(0.95, 0.95, 0.06), can.CFrame * CF(0, 0, -0.97), Color3.fromRGB(255, 250, 235), M.Neon, { shadow = false })
		local src = emitter(f, can.CFrame * CF(0, 0, -1.3))
		-- angled 45 degrees down from the corners: modelling key light on faces and muscles
		spot(src, Enum.NormalId.Front, Color3.fromRGB(255, 246, 228), 52, 3.4, 62, true)
	end
	local banner = part(f, "CanopyBanner", V3(14, 1.6, 0.12), CF(rc + V3(0, y - 1.3, 9.35)), C.red, M.Fabric, { shadow = false })
	sign(banner, Enum.NormalId.Back, "WCB SPARRING RING", Color3.new(1, 1, 1), nil, 30)
	sign(banner, Enum.NormalId.Front, "WCB SPARRING RING", Color3.new(1, 1, 1), nil, 30)
	-- cardio: cool LED strip along the top of the divider + blue wash (the DividerCap tops at 9.4)
	part(f, "LEDStrip", V3(0.3, 0.2, 60), CF(50, 9.5, -48), Color3.fromRGB(60, 150, 255), M.Neon, { shadow = false })
	for _, z in ipairs({ -63, -33 }) do
		point(emitter(f, CF(52.5, 8.6, z)), Color3.fromRGB(80, 150, 255), 18, 0.7)
	end
	-- recovery: soft teal glow along the divider top
	part(f, "LEDStrip", V3(40, 0.2, 0.3), CF(88, 9.5, 20), Color3.fromRGB(90, 220, 200), M.Neon, { shadow = false })
	for _, x in ipairs({ 78, 98 }) do
		point(emitter(f, CF(x, 8.6, 22.5)), Color3.fromRGB(110, 230, 210), 16, 0.6)
	end
end

------------------------------------------------------------------------
-- 3. Lobby: floor crest, reception, lounge, vending, trophies, belts, hall of fame
------------------------------------------------------------------------
local HALL = {
	{ "MARCUS 'THE HAMMER' COLE", "41-2  (33 KO)", "WELTERWEIGHT CHAMPION 1994-99" },
	{ "SOFIA 'LIGHTNING' REYES", "29-0  (18 KO)", "UNDEFEATED FLYWEIGHT QUEEN" },
	{ "BIG EARL JOHNSON", "52-6  (44 KO)", "HEAVYWEIGHT CHAMPION 1987" },
	{ "KENJI 'SILENT STORM' MORI", "37-3  (21 KO)", "2x LIGHTWEIGHT CHAMPION" },
	{ "DARNELL 'SMOKE' HAYES", "45-4  (30 KO)", "UNDISPUTED MIDDLEWEIGHT 2008" },
}

local function buildLobby(root)
	local f = folder(root, "Lobby")
	-- floor crest between the Fight Board and the spawn (reads from the entrance)
	local crest = part(f, "FloorCrest", V3(16, 0.04, 16), CF(0, 0.42, 46), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	local sg = gui(crest, Enum.NormalId.Top, 20, 1)
	local ringOuter = frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.gold })
	Instance.new("UICorner", ringOuter).CornerRadius = UDim.new(0.5, 0)
	local ringInner = frame(sg, { Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), BackgroundColor3 = Color3.fromRGB(150, 20, 26) })
	Instance.new("UICorner", ringInner).CornerRadius = UDim.new(0.5, 0)
	label(sg, "WCB", { TextColor3 = C.gold, Size = UDim2.fromScale(0.6, 0.34), Position = UDim2.fromScale(0.2, 0.3) })
	label(sg, "WORLD CLASS BOXING", { TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.66, 0.08), Position = UDim2.fromScale(0.17, 0.66) })
	label(sg, "EST. 1987", { TextColor3 = C.gold, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.3, 0.06), Position = UDim2.fromScale(0.35, 0.2) })

	-- reception desk (L-shaped) with a monitor, keyboard, bell and sign-in sheet
	part(f, "DeskFront", V3(11.8, 3.6, 2.4), CF(27.9, 2.2, 70.2), C.woodDark, M.Wood, { collide = true })
	part(f, "DeskReturn", V3(2.4, 3.6, 8.4), CF(35.0, 2.2, 67.2), C.woodDark, M.Wood, { collide = true })
	-- (the front top ends where the return's top begins: coplanar marble would shimmer)
	part(f, "DeskTop", V3(11.85, 0.3, 2.8), CF(27.675, 4.15, 70.2), Color3.fromRGB(225, 225, 228), M.Marble)
	part(f, "DeskTopReturn", V3(2.8, 0.3, 8.8), CF(35.0, 4.15, 67.2), Color3.fromRGB(225, 225, 228), M.Marble)
	part(f, "DeskStripe", V3(11.8, 0.35, 0.08), CF(27.9, 3.2, 68.97), C.red, M.SmoothPlastic)
	local deskLogo = part(f, "DeskLogo", V3(8, 1.3, 0.06), CF(27.9, 1.9, 68.97), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	sign(deskLogo, Enum.NormalId.Front, "WORLD CLASS BOXING", C.gold, nil, 40)
	part(f, "MonitorBase", V3(1.0, 0.08, 0.6), CF(25.5, 4.34, 70.6), C.black, M.SmoothPlastic)
	part(f, "MonitorNeck", V3(0.2, 0.7, 0.2), CF(25.5, 4.7, 70.65), C.black, M.SmoothPlastic)
	local screen = part(f, "Monitor", V3(2.3, 1.4, 0.14), CF(25.5, 5.6, 70.55), C.black, M.SmoothPlastic)
	sign(screen, Enum.NormalId.Back, "MEMBER CHECK-IN\n214 TODAY", Color3.fromRGB(90, 200, 255), Color3.fromRGB(10, 14, 22), 50)
	part(f, "Keyboard", V3(1.8, 0.08, 0.6), CF(25.5, 4.34, 71.2), C.black, M.SmoothPlastic)
	vcyl(f, "BellBase", 0.08, 0.6, CF(30.6, 4.3, 69.6), C.black, M.Metal)
	ball(f, "DeskBell", 0.45, CF(30.6, 4.5, 69.6), C.gold, M.Metal)
	part(f, "Clipboard", V3(0.8, 0.05, 1.1), CF(23.4, 4.33, 69.6), Color3.fromRGB(150, 110, 70), M.Wood)
	part(f, "SignInSheet", V3(0.7, 0.03, 0.95), CF(23.4, 4.37, 69.6), C.white, M.SmoothPlastic)
	local welcome = onWall(f, "WelcomeSign", "S", 28, 9.5, 15, 3.2, 0.25, Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	sign(welcome, Enum.NormalId.Front, "WELCOME TO WORLD CLASS BOXING", C.gold, Color3.fromRGB(18, 18, 22), 30)

	-- lounge: rug, two couches, coffee table and a TV
	part(f, "Rug", V3(16, 0.04, 13), CF(-36, 0.42, 51), Color3.fromRGB(120, 28, 34), M.Fabric)
	part(f, "RugBorder", V3(16.6, 0.03, 13.6), CF(-36, 0.415, 51), C.gold, M.Fabric)
	-- couch A faces -Z (towards the TV)
	part(f, "CouchSeat", V3(10, 1.2, 3.2), CF(-36, 1.0, 55.4), C.leather, M.Leather, { collide = true })
	part(f, "CouchBack", V3(10, 2.6, 0.9), CF(-36, 2.1, 57.4), C.leather, M.Leather, { collide = true })
	for _, x in ipairs({ -41.4, -30.6 }) do
		part(f, "CouchArm", V3(0.9, 1.9, 3.2), CF(x, 1.35, 55.4), C.leather, M.Leather, { collide = true })
	end
	for i = -1, 1 do
		part(f, "CouchCushion", V3(3.1, 0.35, 2.9), CF(-36 + i * 3.2, 1.75, 55.3), Color3.fromRGB(62, 46, 38), M.Leather)
	end
	-- couch B faces +X
	part(f, "CouchSeat", V3(3.2, 1.2, 8), CF(-42.4, 1.0, 48.6), C.leather, M.Leather, { collide = true })
	part(f, "CouchBack", V3(0.9, 2.6, 8), CF(-44.4, 2.1, 48.6), C.leather, M.Leather, { collide = true })
	for _, z in ipairs({ 44.15, 53.05 }) do
		part(f, "CouchArm", V3(3.2, 1.9, 0.9), CF(-42.4, 1.35, z), C.leather, M.Leather, { collide = true })
	end
	-- coffee table with magazines
	part(f, "CoffeeTable", V3(5, 0.3, 2.8), CF(-35.5, 1.45, 50.4), Color3.fromRGB(70, 50, 36), M.Wood, { collide = true })
	for _, x in ipairs({ -37.6, -33.4 }) do
		for _, z in ipairs({ 49.3, 51.5 }) do
			part(f, "TableLeg", V3(0.25, 1.05, 0.25), CF(x, 0.82, z), C.black, M.Metal)
		end
	end
	part(f, "Magazine", V3(1.0, 0.05, 1.3), CF(-36.4, 1.63, 50.2) * ANG(0, RAD(15), 0), C.red, M.SmoothPlastic)
	part(f, "Magazine", V3(1.0, 0.05, 1.3), CF(-34.6, 1.63, 50.6) * ANG(0, RAD(-10), 0), Color3.fromRGB(240, 200, 40), M.SmoothPlastic)
	-- TV on a stand facing the couch
	part(f, "TVStand", V3(6, 2, 1.6), CF(-36, 1.4, 44.6), C.woodDark, M.Wood, { collide = true })
	part(f, "TVFrame", V3(7.4, 4.3, 0.35), CF(-36, 4.8, 44.7), C.black, M.SmoothPlastic)
	local tv = part(f, "TVScreen", V3(7, 3.9, 0.1), CF(-36, 4.8, 44.92), Color3.fromRGB(10, 12, 18), M.SmoothPlastic)
	GymDecor.Ticker(tv, Enum.NormalId.Back, "WCB SPORTS")

	-- vending machines along the south wall, east of the entrance
	for i, x in ipairs({ 39.2, 43.4 }) do
		local body = i == 1 and C.red or Color3.fromRGB(20, 60, 160)
		-- body behind a shallow open front box; drinks sit between the lit back panel and the glass
		part(f, "Vending", V3(3.8, 7, 2.0), CF(x, 3.9, 76.9), body, M.SmoothPlastic, { collide = true })
		part(f, "VendingSide", V3(0.3, 7, 0.65), CF(x - 1.75, 3.9, 75.55), body, M.SmoothPlastic, { collide = true })
		part(f, "VendingSide", V3(1.2, 7, 0.65), CF(x + 1.3, 3.9, 75.55), body, M.SmoothPlastic, { collide = true })
		part(f, "VendingTop", V3(2.3, 1.2, 0.65), CF(x - 0.45, 6.8, 75.55), body, M.SmoothPlastic)
		part(f, "VendingBottom", V3(2.3, 1.6, 0.65), CF(x - 0.45, 1.2, 75.55), body, M.SmoothPlastic, { collide = true })
		part(f, "VendingGlow", V3(2.3, 4.2, 0.05), CF(x - 0.45, 4.2, 75.86), Color3.fromRGB(235, 245, 255), M.Neon, { transparency = 0.45, shadow = false })
		for row = 0, 2 do
			part(f, "VendingRack", V3(2.3, 0.08, 0.6), CF(x - 0.45, 2.1 + row * 1.4, 75.55), C.steelLight, M.Metal)
			for col = 0, 2 do
				local colr = ({ C.red, C.gold, Color3.fromRGB(40, 170, 80), C.blue, C.white })[(row * 3 + col + i) % 5 + 1]
				vcyl(f, "Drink", 0.85, 0.42, CF(x - 1.2 + col * 0.75, 2.14 + row * 1.4, 75.55), colr, M.SmoothPlastic)
			end
		end
		part(f, "VendingGlass", V3(2.3, 4.2, 0.08), CF(x - 0.45, 4.2, 75.25), Color3.fromRGB(190, 225, 255), M.Glass, { transparency = 0.55, shadow = false })
		local panel = part(f, "VendingPanel", V3(0.9, 2.2, 0.08), CF(x + 1.3, 4.8, 75.2), C.black, M.SmoothPlastic)
		sign(panel, Enum.NormalId.Front, "$2", C.gold, C.black, 40)
		local head = part(f, "VendingHeader", V3(2.2, 0.8, 0.06), CF(x - 0.45, 6.8, 75.2), Color3.new(), M.SmoothPlastic, { transparency = 1 })
		sign(head, Enum.NormalId.Front, i == 1 and "POWER UP" or "HYDRATE", Color3.new(1, 1, 1), nil, 40)
		part(f, "VendingSlot", V3(2.0, 0.6, 0.06), CF(x - 0.45, 1.1, 75.2), C.black, M.SmoothPlastic)
	end
	point(emitter(f, CF(41.3, 5, 74.6)), Color3.fromRGB(200, 225, 255), 9, 0.6)

	-- trophies and belts inside the existing trophy case (base top y=3, glass above)
	for i, x in ipairs({ -31.5, -28, -20, -16.5 }) do
		trophy(f, CF(x, 3.0, 71.3), ({ 1.6, 2.0, 2.0, 1.4 })[i], i == 2 and C.gold or (i == 3 and Color3.fromRGB(205, 210, 220) or C.goldDeep))
	end
	belt(f, CF(-24, 4.6, 72.4) * ANG(RAD(-8), 0, 0), Color3.fromRGB(20, 20, 22), 1.0)
	for i, x in ipairs({ -29.8, -18.2 }) do
		part(f, "BeltStand", V3(0.3, 2.4, 0.3), CF(x, 4.2, 73.5), C.black, M.Metal)
		belt(f, CF(x, 5.6, 73.35), ({ C.red, C.blue })[i], 0.62)
	end
	point(emitter(f, CF(-24, 7.6, 72)), Color3.fromRGB(255, 230, 170), 8, 0.7)

	-- championship belt display crowning the Fight Board (faces the spawn)
	part(f, "BeltCaseBack", V3(16, 4.4, 0.3), CF(0, 12.6, 32.25), Color3.fromRGB(16, 16, 20), M.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		part(f, "BeltCaseFrame", V3(16.4, 0.3, 1.4), CF(0, 12.6 + s * 2.3, 32.7), C.gold, M.Metal)
		part(f, "BeltCaseFrame", V3(0.3, 4.9, 1.4), CF(s * 8.05, 12.6, 32.7), C.gold, M.Metal)
	end
	part(f, "BeltCaseGlass", V3(16, 4.4, 0.1), CF(0, 12.6, 33.3), Color3.fromRGB(200, 230, 255), M.Glass, { transparency = 0.8, shadow = false })
	local beltColors = { C.red, C.green, Color3.fromRGB(20, 20, 22), C.blue }
	for i, x in ipairs({ -5.6, -1.9, 1.9, 5.6 }) do
		belt(f, CF(x, 12.4, 32.55) * ANG(0, RAD(180), 0), beltColors[i], 0.85)
	end
	local title = part(f, "BeltCaseTitle", V3(10, 0.9, 0.1), CF(0, 15.4, 32.4), Color3.fromRGB(16, 16, 20), M.SmoothPlastic)
	sign(title, Enum.NormalId.Back, "THE FOUR BELTS - WBA  WBC  IBF  WBO", C.gold, Color3.fromRGB(16, 16, 20), 40)
	point(emitter(f, CF(0, 15.5, 34.5)), Color3.fromRGB(255, 225, 160), 10, 0.8)

	-- hall of fame on the south wall above the trophy case
	local hof = onWall(f, "HallTitle", "S", -30, 15.2, 18, 1.8, 0.15, Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	sign(hof, Enum.NormalId.Front, "HALL OF FAME", C.gold, Color3.fromRGB(18, 18, 22), 40)
	for i, entry in ipairs(HALL) do
		local x = -42 + (i - 1) * 6
		onWall(f, "HallFrame", "S", x, 10.6, 4.4, 5.6, 0.18, C.gold, M.Metal, nil, 0.02)
		local plate = onWall(f, "HallPlate", "S", x, 10.6, 3.9, 5.1, 0.2, Color3.fromRGB(22, 22, 28), M.SmoothPlastic, nil, 0.04)
		local sgp = gui(plate, Enum.NormalId.Front, 40, 0.4)
		frame(sgp, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(22, 22, 28) })
		-- a stylised portrait: head + shoulders + gloves
		local face = frame(sgp, { Size = UDim2.fromScale(0.3, 0.22), Position = UDim2.fromScale(0.35, 0.08), BackgroundColor3 = Color3.fromRGB(160 - i * 12, 110 - i * 8, 80 - i * 6) })
		Instance.new("UICorner", face).CornerRadius = UDim.new(0.5, 0)
		frame(sgp, { Size = UDim2.fromScale(0.6, 0.16), Position = UDim2.fromScale(0.2, 0.3), BackgroundColor3 = Color3.fromRGB(150 - i * 12, 102 - i * 8, 74 - i * 6) })
		for _, gx in ipairs({ 0.12, 0.68 }) do
			local g = frame(sgp, { Size = UDim2.fromScale(0.2, 0.14), Position = UDim2.fromScale(gx, 0.26), BackgroundColor3 = C.red })
			Instance.new("UICorner", g).CornerRadius = UDim.new(0.4, 0)
		end
		label(sgp, entry[1], { TextColor3 = C.gold, Size = UDim2.fromScale(0.92, 0.18), Position = UDim2.fromScale(0.04, 0.5) })
		label(sgp, entry[2], { TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.69) })
		label(sgp, entry[3], { TextColor3 = Color3.fromRGB(190, 190, 200), Font = Enum.Font.Gotham, Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.84) })
	end

	-- plants by the entrance and in the lounge
	for _, p in ipairs({ V3(-13.5, 0.4, 76.5), V3(13.5, 0.4, 76.5), V3(-43.5, 0.4, 59.5), V3(-28.5, 0.4, 59.5), V3(44, 0.4, 66) }) do
		plant(f, p, 1)
	end
	-- a round timer above the Fight Board area so the whole lobby hears the bell
	GymDecor.RoundTimer(f, CF(28, 14.4, 78.5), 7, false, true)
end

------------------------------------------------------------------------
-- 4. Boxing area: flags, posters, wall text, timers, glove rack, ringside, fans
------------------------------------------------------------------------
local function flag(parent, cf, kind)
	-- cf = centre of a 5 x 3.4 flag hanging in the XY plane of cf
	local W, H, T = 5, 3.4, 0.08
	local function strip(name, w, h, x, y, color)
		part(parent, name, V3(w, h, T), cf * CF(x, y, 0), color, M.Fabric, { shadow = false })
	end
	if kind == "mexico" or kind == "ireland" or kind == "italy" then
		local cols = ({
			mexico = { Color3.fromRGB(0, 104, 71), C.white, Color3.fromRGB(206, 17, 38) },
			ireland = { Color3.fromRGB(22, 155, 98), C.white, Color3.fromRGB(255, 136, 62) },
			italy = { Color3.fromRGB(0, 140, 69), C.white, Color3.fromRGB(205, 33, 42) },
		})[kind]
		for i = 1, 3 do
			strip("Flag", W / 3, H, (i - 2) * W / 3, 0, cols[i])
		end
		if kind == "mexico" then
			part(parent, "FlagEmblem", V3(0.7, 0.7, T + 0.02), cf, Color3.fromRGB(140, 90, 40), M.Fabric, { shadow = false })
		end
	elseif kind == "germany" or kind == "ghana" or kind == "colombia" then
		local cols = ({
			germany = { C.black, Color3.fromRGB(221, 0, 0), Color3.fromRGB(255, 206, 0) },
			ghana = { Color3.fromRGB(206, 17, 38), Color3.fromRGB(252, 209, 22), Color3.fromRGB(0, 107, 63) },
			colombia = { Color3.fromRGB(252, 209, 22), Color3.fromRGB(0, 56, 147), Color3.fromRGB(206, 17, 38) },
		})[kind]
		for i = 1, 3 do
			strip("Flag", W, H / 3, 0, (2 - i) * H / 3, cols[i])
		end
		if kind == "ghana" then
			part(parent, "FlagStar", V3(0.6, 0.6, T + 0.02), cf * ANG(0, 0, RAD(45)), C.black, M.Fabric, { shadow = false })
		end
	elseif kind == "japan" then
		strip("Flag", W, H, 0, 0, C.white)
		cyl(parent, "FlagDisc", T + 0.02, 1.9, cf * ANG(0, RAD(90), 0), Color3.fromRGB(188, 0, 45), M.Fabric, { shadow = false })
	elseif kind == "usa" then
		for i = 0, 6 do
			strip("Flag", W, H / 7, 0, H / 2 - H / 14 - i * H / 7, i % 2 == 0 and Color3.fromRGB(178, 34, 52) or C.white)
		end
		part(parent, "FlagCanton", V3(W * 0.42, H * 0.54, T + 0.02), cf * CF(-W / 2 + W * 0.21, H / 2 - H * 0.27, 0), Color3.fromRGB(60, 59, 110), M.Fabric, { shadow = false })
	elseif kind == "philippines" then
		strip("Flag", W, H / 2, 0, H / 4, Color3.fromRGB(0, 56, 168))
		strip("Flag", W, H / 2, 0, -H / 4, Color3.fromRGB(206, 17, 38))
		-- white triangle at the hoist made from a rotated square clipped by the edge
		part(parent, "FlagTriangle", V3(H * 0.72, H * 0.72, T + 0.02), cf * CF(-W / 2 + 0.05, 0, 0) * ANG(0, 0, RAD(45)), C.white, M.Fabric, { shadow = false })
		ball(parent, "FlagSun", 0.55, cf * CF(-W / 2 + 0.75, 0, 0), Color3.fromRGB(252, 209, 22), M.Fabric, { shadow = false })
	end
	-- hanging rod
	part(parent, "FlagRod", V3(W + 0.4, 0.12, 0.12), cf * CF(0, H / 2 + 0.06, 0), C.goldDeep, M.Metal, { shadow = false })
end

local function buildBoxing(root)
	local f = folder(root, "Boxing")
	-- national flags hanging from a wire across the hall
	local z = -26
	part(f, "FlagWire", V3(90, 0.08, 0.08), CF(0, 25.6, z), C.black, M.Metal, { shadow = false })
	for _, x in ipairs({ -30, 0, 30 }) do
		part(f, "FlagWireDrop", V3(0.06, 2.7, 0.06), CF(x, 26.95, z), C.black, M.Metal, { shadow = false })
	end
	local kinds = { "mexico", "usa", "ireland", "japan", "philippines", "ghana", "germany", "colombia" }
	for i, kind in ipairs(kinds) do
		flag(f, CF(-38.5 + (i - 1) * 11, 23.75, z), kind)
	end
	-- fight posters on both dividers facing the boxing area
	for _, zz in ipairs({ -68, -60, -52, -44 }) do
		wallPoster(f, "DWb", zz, 5.0, 3.8, 5.4)
		wallPoster(f, "DEb", zz, 5.0, 3.8, 5.4)
	end
	-- painted wall text behind the ring
	wallText(f, "N", -30, 10, 22, 2.4, "DISCIPLINE BEATS TALENT", Color3.new(1, 1, 1))
	wallText(f, "N", 30, 10, 22, 2.4, "HANDS UP.  CHIN DOWN.", C.gold)
	wallText(f, "N", -30, 7.6, 18, 1.4, "- OLD PETE, FOUNDER", Color3.fromRGB(200, 200, 205), Enum.Font.GothamBold)
	-- round timers: one hanging over the station row, one on the wall behind the ring
	GymDecor.RoundTimer(f, CF(0, 15.5, -24), 10, true)
	GymDecor.RoundTimer(f, CF(-30, 15.2, -78.4) * ANG(0, RAD(180), 0), 8, false, true)
	-- glove wall rack on the west divider
	local rackZ = -28
	onWall(f, "GloveRackBoard", "DWb", rackZ, 5.6, 12, 3.4, 0.25, C.woodDark, M.WoodPlanks, nil, 0.02)
	local rackTitle = onWall(f, "GloveRackTitle", "DWb", rackZ, 7.8, 6, 0.7, 0.1, Color3.fromRGB(18, 18, 22), M.SmoothPlastic, nil, 0.05)
	sign(rackTitle, Enum.NormalId.Right, "LOANER GLOVES", C.gold, Color3.fromRGB(18, 18, 22), 40)
	for i = 0, 5 do
		local zz = rackZ - 5 + i * 2
		local peg = wallPoint("DWb", zz, 6.6, 0.55)
		part(f, "RackPeg", V3(0.7, 0.14, 0.14), CF(peg), C.steelLight, M.Metal)
		glovePair(f, CF(peg + V3(0.25, 0, 0)) * ANG(0, RAD(90), 0), GLOVE_COLORS[i + 1])
	end
	for i = 0, 4 do
		local zz = rackZ - 4 + i * 2
		local p = wallPoint("DWb", zz, 4.2, 0.85)
		part(f, "HandWrap", V3(0.08, 2.0, 0.35), CF(p), ({ C.red, C.white, C.black, C.blue, C.gold })[i + 1], M.Fabric)
	end
	-- medicine ball rack on the east divider
	local mz = -27
	for t = 0, 2 do
		local shelf = wallPoint("DEb", mz, 1.0 + t * 1.6, 0.85)
		part(f, "BallShelf", V3(1.7, 0.15, 7), CF(shelf), C.steel, M.Metal)
		for k = 0, 2 do
			ball(f, "MedBall", 1.2 - t * 0.1, CF(shelf + V3(0, 0.67 - t * 0.05, -2.2 + k * 2.2)), ({ C.red, C.black, C.blue, C.gold })[(t + k) % 4 + 1], M.Rubber)
		end
	end
	for _, s in ipairs({ -3.5, 3.5 }) do
		part(f, "BallRackSide", V3(1.7, 4.6, 0.2), CF(wallPoint("DEb", mz + s, 2.8, 0.85)), C.steel, M.Metal)
	end
	-- ringside: corner stools with buckets and towels, a timekeeper's table with the bell
	for _, c in ipairs({ { -15.2, -64.6, C.red }, { 15.2, -35.4, C.blue } }) do
		local p = V3(c[1], 0.5, c[2])
		vcyl(f, "StoolSeat", 0.3, 1.7, CF(p + V3(0, 2.1, 0)), c[3], M.Leather)
		for k = 0, 2 do
			local a = k * RAD(120)
			part(f, "StoolLeg", V3(0.14, 2.2, 0.14), CF(p + V3(math.cos(a) * 0.55, 1.05, math.sin(a) * 0.55)) * ANG(math.sin(a) * 0.15, 0, -math.cos(a) * 0.15), C.steel, M.Metal)
		end
		vcyl(f, "SpitBucket", 1.3, 1.1, CF(p + V3(1.6, 0, 0.4)), Color3.fromRGB(200, 200, 205), M.Metal)
		part(f, "BucketSponge", V3(0.6, 0.3, 0.4), CF(p + V3(1.6, 1.35, 0.4)), Color3.fromRGB(240, 220, 80), M.Fabric)
		part(f, "Towel", V3(1.5, 0.1, 1.0), CF(p + V3(0, 2.3, 0)) * ANG(0, RAD(25), 0), C.white, M.Fabric)
		vcyl(f, "WaterBottle", 1.0, 0.4, CF(p + V3(-1.3, 0, 0.6)), Color3.fromRGB(80, 160, 230), M.SmoothPlastic, { transparency = 0.2 })
	end
	local tp = V3(19.5, 0.5, -44)
	part(f, "TimeTable", V3(2.2, 0.25, 5), CF(tp + V3(0, 2.6, 0)), C.woodDark, M.Wood)
	part(f, "TableSkirt", V3(0.08, 1.2, 5), CF(tp + V3(-1.08, 2.0, 0)), C.red, M.Fabric)
	for _, x in ipairs({ -0.9, 0.9 }) do
		for _, zz in ipairs({ -2.2, 2.2 }) do
			part(f, "TimeTableLeg", V3(0.2, 2.5, 0.2), CF(tp + V3(x, 1.25, zz)), C.black, M.Metal)
		end
	end
	cyl(f, "RingBell", 0.3, 1.3, CF(tp + V3(-0.3, 3.45, -1.4)) * ANG(0, RAD(0), 0), C.gold, M.Metal, { reflect = 0.2 })
	part(f, "BellStand", V3(0.2, 0.7, 0.2), CF(tp + V3(0.05, 2.95, -1.4)), C.black, M.Metal)
	part(f, "BellHammer", V3(1.2, 0.12, 0.12), CF(tp + V3(0.1, 2.8, -0.3)) * ANG(0, RAD(30), 0), C.wood, M.Wood)
	part(f, "Scorecards", V3(0.9, 0.03, 1.2), CF(tp + V3(0.1, 2.75, 1.2)), C.white, M.SmoothPlastic)
	chair(f, tp + V3(2.3, 0, -1.2), RAD(90), C.black)
	chair(f, tp + V3(2.3, 0, 1.3), RAD(90), C.black)
	-- benches along the north wall east of the ring
	bench(f, V3(32, 0.5, -76.4), 0, 12, C.wood)
	vcyl(f, "WaterBottle", 1.0, 0.4, CF(29, 2.05, -76.4), Color3.fromRGB(80, 160, 230), M.SmoothPlastic, { transparency = 0.2 })
	part(f, "GymBag", V3(2.0, 1.1, 1.0), CF(35, 2.45, -76.5), C.red, M.Fabric)
	-- industrial fans on the north wall
	for _, x in ipairs({ -44, 44 }) do
		fan(f, wallPoint("N", x, 14, 1.2), V3(0, 0, 1), 5, C.steelLight)
		part(f, "FanBracket", V3(0.5, 0.5, 1.4), CF(wallPoint("N", x, 14, 0.5)), C.steel, M.Metal)
	end
	-- painted border around the boxing floor and a logo on the gym ring canvas
	for _, e in ipairs({ { 0, -69.6, 89.4, 0.35 }, { 0, 3.6, 89.4, 0.35 }, { -44.6, -33, 0.35, 73.6 }, { 44.6, -33, 0.35, 73.6 } }) do
		part(f, "FloorLine", V3(e[3], 0.02, e[4]), CF(e[1], 0.515, e[2]), C.white, M.SmoothPlastic)
	end
	local logo = part(f, "CanvasLogo", V3(8, 0.02, 8), CF(0, 2.82, -50), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	local lsg = gui(logo, Enum.NormalId.Top, 30, 1)
	label(lsg, "WCB", { TextColor3 = Color3.fromRGB(235, 235, 240), TextTransparency = 0.35 })
end

------------------------------------------------------------------------
-- 5. Weight room
------------------------------------------------------------------------
local function kettlebell(parent, pos, size, color)
	ball(parent, "Kettlebell", size, CF(pos + V3(0, size / 2, 0)), color, M.Metal)
	local hy = size * 0.95
	part(parent, "KBHandle", V3(size * 0.75, 0.14, 0.14), CF(pos + V3(0, hy + 0.28, 0)), color, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		part(parent, "KBHandlePost", V3(0.14, 0.4, 0.14), CF(pos + V3(s * size * 0.33, hy + 0.1, 0)), color, M.Metal)
	end
end

local function buildWeights(root)
	local f = folder(root, "Weights")
	-- rubber tile seams across the weight room floor
	for z = -72, 12, 6 do
		part(f, "TileSeam", V3(58, 0.02, 0.12), CF(-79, 0.512, z), Color3.fromRGB(16, 16, 18), M.SmoothPlastic)
	end
	for x = -102, -56, 6 do
		part(f, "TileSeam", V3(0.12, 0.02, 96), CF(x, 0.512, -30), Color3.fromRGB(16, 16, 18), M.SmoothPlastic)
	end
	-- kettlebell rack along the north wall
	local rz = -77.2
	part(f, "KBRackShelf", V3(16, 0.25, 2.2), CF(-96, 1.75, rz), C.steel, M.Metal)
	part(f, "KBRackBase", V3(16, 0.25, 2.2), CF(-96, 0.65, rz), C.steel, M.Metal)
	for _, x in ipairs({ -103.8, -96, -88.2 }) do
		part(f, "KBRackLeg", V3(0.25, 1.4, 2.0), CF(x, 1.2, rz), C.steel, M.Metal)
	end
	local kbColors = { Color3.fromRGB(240, 200, 40), Color3.fromRGB(60, 140, 220), Color3.fromRGB(220, 60, 50), Color3.fromRGB(60, 170, 90), C.black }
	for i = 0, 5 do
		kettlebell(f, V3(-102.8 + i * 2.15, 1.87, rz), 0.8 + i * 0.07, kbColors[i % 5 + 1])
	end
	for i = 0, 4 do
		kettlebell(f, V3(-102.6 + i * 2.6, 0.77, rz), 1.15 + i * 0.07, C.black)
	end
	-- plyo boxes, medicine balls
	for i, b in ipairs({ { -61.5, 2.0 }, { -58, 2.6 }, { -54.3, 3.2 } }) do
		local box = part(f, "PlyoBox", V3(3.2, b[2], 3), CF(b[1], 0.5 + b[2] / 2, -74.5), Color3.fromRGB(176, 136, 88), M.WoodPlanks, { collide = true })
		sign(box, Enum.NormalId.Back, ({ "20\"", "24\"", "30\"" })[i], C.black, nil, 30)
	end
	for i = 0, 3 do
		ball(f, "MedBall", 1.25, CF(-55, 1.12, -69 + i * 1.6), ({ C.red, C.blue, C.black, C.gold })[i + 1], M.Rubber)
	end
	-- tractor tire with a sledgehammer leaning on it
	local tire = V3(-58, 0.5, -60)
	vcyl(f, "Tire", 1.8, 7, CF(tire), Color3.fromRGB(26, 26, 28), M.Rubber, { collide = true })
	vcyl(f, "TireInner", 0.06, 3.8, CF(tire + V3(0, 1.8, 0)), Color3.fromRGB(10, 10, 12), M.Rubber)
	for k = 0, 11 do
		local a = k * RAD(30)
		part(f, "TireTread", V3(0.5, 1.9, 0.9), CF(tire + V3(math.cos(a) * 3.45, 0.9, math.sin(a) * 3.45)) * ANG(0, -a, 0), Color3.fromRGB(34, 34, 36), M.Rubber)
	end
	local hammerBase = tire + V3(4.2, 0, 0.6)
	local top = tire + V3(3.3, 4.6, 0.6)
	rod(f, "SledgeHandle", hammerBase + V3(0, 0.2, 0), top, 0.28, C.wood, M.Wood)
	part(f, "SledgeHead", V3(0.9, 0.9, 1.8), CFrame.lookAt(top, top + V3(0, 0, 1)), C.steel, M.Metal)
	-- battle ropes anchored to a post by the divider
	local anchor = V3(-52.3, 0.5, -40)
	part(f, "RopeAnchor", V3(1.2, 2.2, 1.2), CF(anchor + V3(0, 1.1, 0)), C.black, M.Metal, { collide = true })
	vcyl(f, "AnchorRing", 0.2, 0.9, CF(anchor + V3(-0.7, 1.0, 0)) * ANG(0, 0, RAD(90)), C.steelLight, M.Metal)
	for _, side in ipairs({ -0.55, 0.55 }) do
		local prev = anchor + V3(-0.8, 0.95, side * 0.3)
		for k = 1, 8 do
			local nxt = anchor + V3(-0.8 - k * 1.5, 0.22 + (k == 1 and 0.4 or 0), side + math.sin(k * 1.3 + side * 3) * 0.45)
			rod(f, "BattleRope", prev, nxt, 0.36, Color3.fromRGB(30, 30, 34), M.Fabric)
			prev = nxt
		end
		rod(f, "RopeHandle", prev, prev + V3(-0.9, 0, 0), 0.42, C.black, M.Rubber)
	end
	-- cable station on the west wall
	for _, zz in ipairs({ -37, -25 }) do
		part(f, "CableTower", V3(1.6, 9, 1.6), CF(-106.4, 5, zz), C.black, M.Metal, { collide = true })
		part(f, "WeightStack", V3(1.1, 3.6, 0.9), CF(-106.4, 2.6, zz + (zz < -30 and 0.95 or -0.95)), Color3.fromRGB(70, 70, 76), M.Metal)
		for k = 0, 5 do
			part(f, "StackLine", V3(1.12, 0.06, 0.92), CF(-106.4, 1.2 + k * 0.6, zz + (zz < -30 and 0.95 or -0.95)), C.black, M.Metal)
		end
		cyl(f, "Pulley", 0.3, 0.7, CF(-105.4, 8.2, zz) * ANG(0, 0, 0), C.steelLight, M.Metal)
		part(f, "Cable", V3(0.06, 4.2, 0.06), CF(-105.1, 6.0, zz), C.black, M.Metal)
		part(f, "DHandle", V3(0.2, 0.6, 0.9), CF(-105.1, 3.7, zz), C.red, M.Rubber)
	end
	part(f, "CableTopBeam", V3(1.2, 1.2, 13.6), CF(-106.4, 9.8, -31), C.black, M.Metal)
	-- chalk stand, plate trees, mirror strip, workout board, fan, flat bench
	local chalk = V3(-82, 0.5, -36)
	vcyl(f, "ChalkPost", 2.8, 0.4, CF(chalk), C.steel, M.Metal)
	vcyl(f, "ChalkBase", 0.2, 1.6, CF(chalk), C.steel, M.Metal)
	vcyl(f, "ChalkBowl", 0.6, 1.7, CF(chalk + V3(0, 2.8, 0)), C.steelLight, M.Metal)
	vcyl(f, "Chalk", 0.12, 1.5, CF(chalk + V3(0, 3.3, 0)), C.white, M.Sand)
	for _, p in ipairs({ V3(-82, 0.5, -46), V3(-82, 0.5, -8) }) do
		part(f, "PlateTreeBase", V3(2.2, 0.2, 2.2), CF(p + V3(0, 0.1, 0)), C.black, M.Metal)
		vcyl(f, "PlateTreePost", 3.6, 0.3, CF(p), C.black, M.Metal)
		for k, h in ipairs({ 1.0, 1.9, 2.8 }) do
			for _, s in ipairs({ -1, 1 }) do
				part(f, "PlateHorn", V3(0.9, 0.18, 0.18), CF(p + V3(s * 0.5, h, 0)), C.steelLight, M.Metal)
				cyl(f, "StoredPlate", 0.28, 2.2 - k * 0.42, CF(p + V3(s * 0.75, h, 0)), k == 1 and Color3.fromRGB(190, 30, 35) or (k == 2 and Color3.fromRGB(30, 60, 160) or Color3.fromRGB(240, 200, 40)), M.Rubber)
			end
		end
	end
	onWall(f, "MirrorFrame", "W", -52, 4.6, 16.4, 6.4, 0.1, C.black, M.Metal, nil, 0.16)
	onWall(f, "Mirror", "W", -52, 4.6, 16, 6, 0.1, Color3.fromRGB(205, 225, 240), M.Glass, { reflect = 0.35 }, 0.2)
	local board, bface = onWall(f, "WODBoard", "DWw", -67, 5.6, 6, 4, 0.15, C.white, M.SmoothPlastic, nil, 0.02)
	local bsg = gui(board, bface, 40, 0.6)
	frame(bsg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.white })
	label(bsg, "WORKOUT OF THE DAY", { TextColor3 = C.red, Size = UDim2.fromScale(0.92, 0.18), Position = UDim2.fromScale(0.04, 0.04) })
	label(bsg, "A  BACK SQUAT  5 x 5\nB  BENCH PRESS  4 x 8\nC  PULL-UPS  3 x MAX\nD  KB SWINGS  50\nFINISHER: TIRE FLIPS x 10", { TextColor3 = Color3.fromRGB(30, 50, 140), Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.9, 0.72), Position = UDim2.fromScale(0.06, 0.25) })
	fan(f, wallPoint("W", 8, 13, 1.2), V3(1, 0, 0), 5, C.steelLight)
	part(f, "FlatBench", V3(1.4, 0.35, 4.2), CF(-62, 2.0, -48), C.black, M.Leather, { collide = true })
	for _, zz in ipairs({ -49.5, -46.5 }) do
		part(f, "FlatBenchLeg", V3(1.2, 1.5, 0.3), CF(-62, 1.15, zz), C.steel, M.Metal)
	end
	wallText(f, "W", -20, 13.2, 22, 3, "NO EXCUSES", C.red)
end

------------------------------------------------------------------------
-- 6. Cardio room
------------------------------------------------------------------------
local function buildCardio(root)
	local f = folder(root, "Cardio")
	-- a row of member machines along the north wall (two are in use by NPC members)
	local tmTop = 0
	for _, x in ipairs({ 58, 66 }) do
		tmTop = decorTreadmill(f, V3(x, 0.5, -71.5))
	end
	for _, x in ipairs({ 84, 92, 100 }) do
		decorBike(f, V3(x, 0.5, -71.5))
	end
	GymDecor.DecorSpots = GymDecor.DecorSpots or {}
	GymDecor.DecorSpots.treadmill = { pos = V3(58, 0, -71.4), stand = tmTop }
	GymDecor.DecorSpots.bike = { pos = V3(92, 0, -70.5), seat = 2.7 }
	-- TV with a sports ticker on the east wall
	onWall(f, "TVFrame", "E", -60, 12, 10.6, 6.4, 0.35, C.black, M.SmoothPlastic, nil, 0.05)
	local tv = onWall(f, "TVScreen", "E", -60, 12, 10, 5.8, 0.1, Color3.fromRGB(10, 12, 18), M.SmoothPlastic, nil, 0.42)
	GymDecor.Ticker(tv, Enum.NormalId.Left, "CARDIO ZONE")
	-- wall fans
	for _, zz in ipairs({ -14, 8 }) do
		fan(f, wallPoint("E", zz, 14, 1.2), V3(-1, 0, 0), 5, C.steelLight)
	end
	-- heart-rate zone chart on the divider
	local chart, cface = onWall(f, "HRChart", "DEc", -63, 5, 4, 5, 0.12, C.white, M.SmoothPlastic, nil, 0.02)
	local csg = gui(chart, cface, 40, 0.6)
	local zones = {
		{ "ZONE 5  MAX  90-100%", Color3.fromRGB(220, 40, 40) }, { "ZONE 4  HARD  80-90%", Color3.fromRGB(240, 130, 30) },
		{ "ZONE 3  TEMPO  70-80%", Color3.fromRGB(240, 210, 40) }, { "ZONE 2  BASE  60-70%", Color3.fromRGB(60, 180, 80) },
		{ "ZONE 1  EASY  50-60%", Color3.fromRGB(60, 140, 230) },
	}
	label(csg, "HEART RATE ZONES", { TextColor3 = C.black, Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.02) })
	for i, z in ipairs(zones) do
		local band = frame(csg, { Size = UDim2.fromScale(0.9, 0.15), Position = UDim2.fromScale(0.05, 0.16 + (i - 1) * 0.165), BackgroundColor3 = z[2] })
		label(band, z[1], { TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold })
	end
	-- towel rack by the water cooler
	local tr = V3(106.2, 0.5, -4)
	for _, zz in ipairs({ -1.4, 1.4 }) do
		part(f, "TowelRackPost", V3(0.2, 4.4, 0.2), CF(tr + V3(0, 2.2, zz)), C.steelLight, M.Metal)
	end
	for k = 0, 2 do
		part(f, "TowelRackBar", V3(0.15, 0.15, 3), CF(tr + V3(0, 1.4 + k * 1.2, 0)), C.steelLight, M.Metal)
		part(f, "Towel", V3(0.15, 1.0, 2.4), CF(tr + V3(0.12, 0.95 + k * 1.2, 0)), ({ C.white, Color3.fromRGB(60, 150, 255), C.white })[k + 1], M.Fabric)
	end
	wallText(f, "E", -35, 9, 18, 3, "EARN YOUR ROUNDS", Color3.fromRGB(90, 190, 255))
end

------------------------------------------------------------------------
-- 7. Recovery area
------------------------------------------------------------------------
local function buildRecovery(root)
	local f = folder(root, "Recovery")
	for _, p in ipairs({ V3(53.5, 0.5, 24.5), V3(53.5, 0.5, 75.5), V3(106.5, 0.5, 75.5), V3(106.5, 0.5, 24.5) }) do
		plant(f, p, 1.1, Color3.fromRGB(220, 220, 214))
	end
	-- towel shelves against the south wall
	local sx, sz = 71, 77.6
	part(f, "ShelfBack", V3(10, 6, 0.2), CF(sx, 3.5, sz + 0.6), C.wood, M.WoodPlanks)
	for k = 0, 2 do
		local y = 1.4 + k * 1.9
		part(f, "Shelf", V3(10, 0.2, 1.6), CF(sx, y, sz), C.wood, M.WoodPlanks)
		for i = 0, 3 do
			cyl(f, "RolledTowel", 1.3, 0.75, CF(sx - 3.6 + i * 2.4, y + 0.48, sz - 0.1) * ANG(0, RAD(90), 0), (k + i) % 2 == 0 and C.white or Color3.fromRGB(90, 200, 190), M.Fabric)
		end
	end
	for _, x in ipairs({ -5, 5 }) do
		part(f, "ShelfSide", V3(0.2, 6, 1.6), CF(sx + x, 3.5, sz), C.wood, M.WoodPlanks)
	end
	-- relaxation bench and two warm floor lamps
	bench(f, V3(90, 0.5, 75.5), 0, 8, Color3.fromRGB(200, 170, 130))
	for _, z in ipairs({ 44, 56 }) do
		local p = V3(53.6, 0.5, z)
		vcyl(f, "FloorLampBase", 0.2, 1.2, CF(p), C.black, M.Metal)
		vcyl(f, "FloorLampPole", 5.6, 0.18, CF(p), C.black, M.Metal)
		vcyl(f, "FloorLampShade", 1.2, 1.6, CF(p + V3(0, 5.6, 0)), Color3.fromRGB(240, 225, 200), M.Fabric, { shadow = false })
		point(emitter(f, CF(p + V3(0, 5.9, 0))), Color3.fromRGB(255, 205, 150), 14, 0.65)
	end
	wallText(f, "S", 90, 10, 26, 2.6, "RECOVERY IS PART OF TRAINING", Color3.fromRGB(120, 230, 210))
	-- (moved north of the Elite wing doorway)
	wallText(f, "E", 33, 7.5, 16, 1.6, "BREATHE  -  RESET  -  REBUILD", Color3.fromRGB(220, 220, 230), Enum.Font.GothamBold)
end

------------------------------------------------------------------------
-- 8. Services: barber, lockers & showers, nutrition bar, bunk room
------------------------------------------------------------------------
local function buildServices(root)
	local f = folder(root, "Services")
	-- barber: second chair, waiting chairs, counter under the mirror, products, price board, clippings
	local c2 = V3(-87, 0.5, 38)
	vcyl(f, "BarberBase", 1.4, 1.2, CF(c2), C.steelLight, M.Metal)
	part(f, "BarberSeat", V3(3, 1.4, 3), CF(c2 + V3(0, 2.1, 0)), Color3.fromRGB(160, 20, 30), M.Leather, { collide = true })
	part(f, "BarberBack", V3(3, 3, 0.6), CF(c2 + V3(0, 4.1, 1.2)), Color3.fromRGB(160, 20, 30), M.Leather)
	part(f, "BarberHeadrest", V3(1.4, 0.9, 0.5), CF(c2 + V3(0, 6.0, 1.25)), C.black, M.Leather)
	for _, s in ipairs({ -1.6, 1.6 }) do
		part(f, "BarberArm", V3(0.4, 0.3, 2.6), CF(c2 + V3(s, 3.0, 0)), C.steelLight, M.Metal)
	end
	part(f, "BarberFootrest", V3(1.6, 0.2, 1.0), CF(c2 + V3(0, 0.9, -2.0)), C.steelLight, M.Metal)
	for i = 0, 2 do
		chair(f, V3(-106.4, 0.5, 43 + i * 2.6), RAD(-90), Color3.fromRGB(130, 20, 28))
	end
	part(f, "BarberCounter", V3(10, 3.2, 1.6), CF(-95, 2.1, 29.2), C.black, M.Marble, { collide = true })
	part(f, "BarberSink", V3(2, 0.2, 1.1), CF(-95, 3.72, 29.2), C.white, M.SmoothPlastic)
	vcyl(f, "SprayBottle", 0.9, 0.35, CF(-98.5, 3.7, 29.2), Color3.fromRGB(60, 160, 230), M.SmoothPlastic)
	part(f, "Clippers", V3(0.3, 0.2, 0.8), CF(-92, 3.8, 29.2), C.black, M.SmoothPlastic)
	part(f, "Comb", V3(0.7, 0.05, 0.15), CF(-91, 3.73, 29.4), C.black, M.SmoothPlastic)
	local shelf = onWall(f, "ProductShelf", "DZs", -102, 5.2, 6, 0.2, 1.2, C.wood, M.Wood)
	for i = 0, 5 do
		vcyl(f, "Product", 0.9 + (i % 2) * 0.3, 0.45, CF(-104.3 + i * 0.9, 5.3, shelf.Position.Z), ({ C.blue, C.gold, C.black, C.red, C.white, C.green })[i + 1], M.SmoothPlastic)
	end
	local price, pface = onWall(f, "PriceBoard", "DZs", -86, 6.8, 7, 4, 0.15, Color3.fromRGB(18, 18, 22), M.SmoothPlastic, nil, 0.02)
	local psg = gui(price, pface, 40, 0.3)
	frame(psg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 18, 22) })
	label(psg, "BIG LOU'S CUTS", { TextColor3 = C.gold, Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.04) })
	label(psg, "FRESH CUT ........ $30\nBEARD / SHAVE ... $20\nCOLOR & DYE ...... $60", { TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.86, 0.62), Position = UDim2.fromScale(0.07, 0.32) })
	local rng = Random.new(77)
	for _ = 1, 9 do
		part(f, "HairClipping", V3(0.35, 0.03, 0.12), CF(-95 + rng:NextNumber(-2.5, 2.5), 0.515, 38 + rng:NextNumber(-2.5, 2.5)) * ANG(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(25, 20, 18), M.SmoothPlastic)
	end

	-- locker room: bags and shoes on the bench, towel cart, shower entrance, wet floor sign
	for i, x in ipairs({ -75.5, -63.5 }) do
		part(f, "GymBag", V3(2.0, 1.0, 1.0), CF(x, 2.1, 32), i == 1 and C.blue or C.black, M.Fabric)
		part(f, "BagHandle", V3(1.2, 0.12, 0.12), CF(x, 2.7, 32), C.black, M.Fabric)
	end
	for i, x in ipairs({ -71, -66.5 }) do
		for _, s in ipairs({ -0.35, 0.35 }) do
			part(f, "Shoe", V3(0.55, 0.45, 1.2), CF(x + s, 0.73, 33.8), i == 1 and C.white or C.red, M.Leather)
		end
	end
	local cart = V3(-56, 0.5, 30)
	part(f, "TowelCart", V3(3, 2.4, 2), CF(cart + V3(0, 1.7, 0)), C.steelLight, M.Metal, { collide = true })
	for k = 0, 2 do
		cyl(f, "RolledTowel", 1.4, 0.8, CF(cart + V3(-0.9 + k * 0.9, 3.3, 0)) * ANG(0, RAD(90), 0), C.white, M.Fabric)
	end
	for _, x in ipairs({ -1.2, 1.2 }) do
		for _, z in ipairs({ -0.8, 0.8 }) do
			cyl(f, "CartWheel", 0.2, 0.5, CF(cart + V3(x, 0.25, z)), C.black, M.Rubber)
		end
	end
	-- shower entrance on the west wall
	onWall(f, "ShowerTiles", "W", 55, 5.5, 10, 10, 0.3, Color3.fromRGB(225, 232, 236), M.Glass, nil, 0.01)
	onWall(f, "ShowerOpening", "W", 55, 4.4, 6, 7.6, 0.32, Color3.fromRGB(28, 34, 40), M.SmoothPlastic, nil, 0.02)
	local sh, shf = onWall(f, "ShowerSign", "W", 55, 9.2, 5, 1, 0.1, Color3.fromRGB(18, 18, 22), M.SmoothPlastic, nil, 0.33)
	sign(sh, shf, "SHOWERS", Color3.fromRGB(150, 220, 255), Color3.fromRGB(18, 18, 22), 40)
	local wf = V3(-100, 0.5, 52.5)
	part(f, "WetFloorSign", V3(1.4, 2.2, 0.1), CF(wf + V3(0, 1.1, 0.35)) * ANG(RAD(-12), 0, 0), Color3.fromRGB(250, 210, 30), M.SmoothPlastic)
	part(f, "WetFloorSign", V3(1.4, 2.2, 0.1), CF(wf + V3(0, 1.1, -0.35)) * ANG(RAD(12), 0, 0), Color3.fromRGB(250, 210, 30), M.SmoothPlastic)

	-- nutrition bar: fridge, blender, fruit, smoothies, protein tubs
	local fr = V3(-83, 0.5, 77.2)
	part(f, "Fridge", V3(3.6, 7.6, 1.6), CF(fr + V3(0, 3.8, 0.4)), C.white, M.SmoothPlastic, { collide = true })
	for _, x in ipairs({ -1.65, 1.65 }) do
		part(f, "FridgeSide", V3(0.3, 7.6, 0.9), CF(fr + V3(x, 3.8, -0.85)), C.white, M.SmoothPlastic, { collide = true })
	end
	part(f, "FridgeTop", V3(3.0, 0.9, 0.9), CF(fr + V3(0, 7.15, -0.85)), C.white, M.SmoothPlastic)
	part(f, "FridgeBottom", V3(3.0, 0.8, 0.9), CF(fr + V3(0, 0.4, -0.85)), C.white, M.SmoothPlastic, { collide = true })
	part(f, "FridgeGlow", V3(3.0, 5.9, 0.05), CF(fr + V3(0, 3.75, -0.42)), Color3.fromRGB(235, 245, 255), M.Neon, { transparency = 0.5, shadow = false })
	for row = 0, 2 do
		part(f, "FridgeShelf", V3(3.0, 0.08, 0.85), CF(fr + V3(0, 1.0 + row * 2.0, -0.85)), C.steelLight, M.Metal)
		for col = 0, 3 do
			vcyl(f, "Bottle", 0.9, 0.38, CF(fr + V3(-1.1 + col * 0.73, 1.04 + row * 2.0, -0.85)), ({ Color3.fromRGB(255, 140, 40), Color3.fromRGB(60, 200, 90), Color3.fromRGB(80, 160, 255), Color3.fromRGB(240, 60, 90) })[(row + col) % 4 + 1], M.Glass, { transparency = 0.15 })
		end
	end
	part(f, "FridgeGlass", V3(3.0, 5.9, 0.08), CF(fr + V3(0, 3.75, -1.32)), Color3.fromRGB(200, 230, 255), M.Glass, { transparency = 0.6, shadow = false })
	part(f, "FridgeHandle", V3(0.12, 2.4, 0.15), CF(fr + V3(1.2, 4.2, -1.42)), C.steelLight, M.Metal)
	local bl = V3(-75.5, 4.4, 70)
	part(f, "BlenderBase", V3(0.8, 0.7, 0.8), CF(bl + V3(0, 0.35, 0)), C.black, M.SmoothPlastic)
	vcyl(f, "BlenderJar", 1.3, 0.7, CF(bl + V3(0, 0.7, 0)), Color3.fromRGB(255, 160, 190), M.Glass, { transparency = 0.25 })
	vcyl(f, "BlenderLid", 0.15, 0.75, CF(bl + V3(0, 2.0, 0)), C.black, M.SmoothPlastic)
	local fb = V3(-65, 4.4, 70)
	vcyl(f, "FruitBowl", 0.45, 1.8, CF(fb), C.white, M.SmoothPlastic)
	for i, d in ipairs({ { 0.3, 0.25, Color3.fromRGB(255, 150, 30) }, { -0.35, 0.2, Color3.fromRGB(200, 30, 40) }, { 0.0, -0.35, Color3.fromRGB(255, 150, 30) }, { 0.2, 0.0, Color3.fromRGB(120, 200, 60) } }) do
		ball(f, "Fruit", 0.55, CF(fb + V3(d[1], 0.6 + (i % 2) * 0.15, d[2])), d[3], M.SmoothPlastic)
	end
	part(f, "Banana", V3(0.9, 0.22, 0.3), CF(fb + V3(-0.1, 0.95, 0.1)) * ANG(0, 0, RAD(12)), Color3.fromRGB(250, 220, 60), M.SmoothPlastic)
	for i = 0, 2 do
		vcyl(f, "Smoothie", 0.8, 0.45, CF(V3(-71 + i * 1.2, 4.4, 69.3)), ({ Color3.fromRGB(240, 120, 160), Color3.fromRGB(120, 200, 90), Color3.fromRGB(250, 190, 70) })[i + 1], M.Glass, { transparency = 0.1 })
	end
	local ps = onWall(f, "ProteinShelf", "S", -61, 6, 8, 0.25, 1.2, C.wood, M.Wood)
	for i = 0, 4 do
		vcyl(f, "ProteinTub", 1.3, 0.95, CF(-64.2 + i * 1.6, 6.12, ps.Position.Z), C.black, M.SmoothPlastic)
		vcyl(f, "TubLid", 0.2, 0.98, CF(-64.2 + i * 1.6, 7.42, ps.Position.Z), ({ C.red, C.gold, C.blue, C.green, C.white })[i + 1], M.SmoothPlastic)
	end

	-- bunk room: nightstands with a lamp, footlockers, rug, poster
	part(f, "BunkRug", V3(22, 0.04, 6), CF(-93, 0.52, 57), Color3.fromRGB(34, 50, 96), M.Fabric)
	for _, x in ipairs({ -96.5, -89.5 }) do
		part(f, "Nightstand", V3(2, 2, 2), CF(x, 1.5, 69.5), C.wood, M.Wood)
		part(f, "NightstandDrawer", V3(1.6, 0.06, 0.06), CF(x, 1.9, 68.47), C.black, M.Metal)
		vcyl(f, "LampBase", 1.0, 0.3, CF(x, 2.5, 69.5), C.black, M.Metal)
		vcyl(f, "LampShade", 0.8, 1.0, CF(x, 3.4, 69.5), Color3.fromRGB(240, 225, 200), M.Fabric, { shadow = false })
	end
	point(emitter(f, CF(-93, 4, 69)), Color3.fromRGB(255, 200, 140), 12, 0.6)
	for _, x in ipairs({ -100, -93, -86 }) do
		part(f, "Footlocker", V3(3, 1.4, 1.5), CF(x, 1.2, 60.4), Color3.fromRGB(60, 80, 50), M.Metal)
		part(f, "FootlockerTrim", V3(3.05, 0.15, 1.55), CF(x, 1.6, 60.4), C.steelLight, M.Metal)
	end
	wallText(f, "W", 66, 7, 14, 2, "SLEEP = GAINS", Color3.fromRGB(170, 170, 255))
end

------------------------------------------------------------------------
-- 9. Pool hall
------------------------------------------------------------------------
local function buildPool(root)
	local f = folder(root, "Pool")
	-- lifeguard chair
	local lg = V3(-40, 0.5, -100)
	for _, x in ipairs({ -1.1, 1.1 }) do
		part(f, "LGLeg", V3(0.25, 6.2, 0.25), CF(lg + V3(x, 3.1, 0.9)) * ANG(RAD(8), 0, 0), C.white, M.SmoothPlastic)
		part(f, "LGLeg", V3(0.25, 6.2, 0.25), CF(lg + V3(x, 3.1, -0.9)) * ANG(RAD(-8), 0, 0), C.white, M.SmoothPlastic)
	end
	for k = 1, 3 do
		part(f, "LGStep", V3(2.4, 0.15, 0.5), CF(lg + V3(0, k * 1.5, 1.2 + k * 0.1)), C.white, M.SmoothPlastic)
	end
	part(f, "LGSeat", V3(2.6, 0.3, 2.2), CF(lg + V3(0, 6.3, 0)), Color3.fromRGB(220, 50, 40), M.SmoothPlastic)
	part(f, "LGBack", V3(2.6, 2.2, 0.3), CF(lg + V3(0, 7.4, -1.0)), Color3.fromRGB(220, 50, 40), M.SmoothPlastic)
	vcyl(f, "LGUmbrellaPole", 4, 0.15, CF(lg + V3(1.3, 6.4, -1.0)), C.white, M.SmoothPlastic)
	vcyl(f, "LGUmbrella", 0.3, 4, CF(lg + V3(1.3, 10.3, -1.0)), Color3.fromRGB(240, 70, 50), M.Fabric, { shadow = false })
	-- loungers on the east deck
	for i = 0, 2 do
		local p = V3(39, 0.5, -106 - i * 6)
		part(f, "Lounger", V3(6, 0.4, 2.2), CF(p + V3(0, 1.0, 0)), C.white, M.SmoothPlastic)
		part(f, "LoungerBack", V3(2.4, 0.4, 2.2), CF(p + V3(3.3, 1.9, 0)) * ANG(0, 0, RAD(35)), C.white, M.SmoothPlastic)
		part(f, "LoungerPad", V3(5.6, 0.2, 1.9), CF(p + V3(-0.2, 1.3, 0)), Color3.fromRGB(40, 120, 200), M.Fabric)
		for _, x in ipairs({ -2.6, 2.4 }) do
			part(f, "LoungerLeg", V3(0.25, 0.8, 1.9), CF(p + V3(x, 0.4, 0)), C.white, M.SmoothPlastic)
		end
		part(f, "LoungerTowel", V3(1.8, 0.1, 1.6), CF(p + V3(-1.5, 1.45, 0)) * ANG(0, RAD(10), 0), ({ C.red, C.gold, C.white })[i + 1], M.Fabric)
	end
	-- pool ladders at two corners of the basin
	for _, d in ipairs({ { 24, -101, -1 }, { -24, -123, 1 } }) do
		local x, edge, inward = d[1], d[2], d[3]
		for _, dx in ipairs({ -0.75, 0.75 }) do
			part(f, "LadderRail", V3(0.18, 5.6, 0.18), CF(x + dx, -1.5, edge + inward * 0.4), C.steelLight, M.Metal, { reflect = 0.2 })
			part(f, "LadderReturn", V3(0.18, 0.18, 1.5), CF(x + dx, 1.3, edge - inward * 0.3), C.steelLight, M.Metal, { reflect = 0.2 })
		end
		for k = 0, 2 do
			part(f, "LadderStep", V3(1.5, 0.12, 0.45), CF(x, -0.6 - k * 1.2, edge + inward * 0.62), C.steelLight, M.Metal)
		end
	end
	-- deck markings
	for _, d in ipairs({ { -20, -99.6, "4 FT" }, { 20, -99.6, "4 FT" }, { 0, -99.6, "NO DIVING" }, { 0, -124.4, "NO DIVING" } }) do
		local p = part(f, "DeckMark", V3(d[3] == "NO DIVING" and 8 or 3.2, 0.02, 1.2), CF(d[1], 0.51, d[2]), Color3.new(), M.SmoothPlastic, { transparency = 1 })
		local sg = gui(p, Enum.NormalId.Top, 30, 1)
		label(sg, d[3], { TextColor3 = Color3.fromRGB(200, 30, 35) })
	end
	-- towel cabinet near the corridor, wall clock, plants
	part(f, "TowelCabinet", V3(3.2, 3, 1.6), CF(14, 2.0, -84), C.white, M.SmoothPlastic, { collide = true })
	for k = 0, 2 do
		cyl(f, "RolledTowel", 1.4, 0.8, CF(14 - 0.9 + k * 0.9, 3.9, -84) * ANG(0, RAD(90), 0), k == 1 and Color3.fromRGB(60, 150, 255) or C.white, M.Fabric)
	end
	cyl(f, "PoolClockRim", 0.2, 3.2, CF(20, 12, -145.85) * ANG(0, RAD(90), 0), C.black, M.SmoothPlastic)
	cyl(f, "PoolClock", 0.2, 2.9, CF(20, 12, -145.78) * ANG(0, RAD(90), 0), C.white, M.SmoothPlastic)
	part(f, "ClockHand", V3(0.08, 1.15, 0.04), CF(20, 12, -145.64) * ANG(0, 0, RAD(-60)) * CF(0, 0.5, 0), C.black, M.SmoothPlastic)
	part(f, "ClockHand", V3(0.12, 0.75, 0.04), CF(20, 12, -145.62) * ANG(0, 0, RAD(30)) * CF(0, 0.33, 0), C.black, M.SmoothPlastic)
	for _, p in ipairs({ V3(-42, 0.5, -82), V3(42, 0.5, -82), V3(-42, 0.5, -143), V3(42, 0.5, -143) }) do
		plant(f, p, 1.1, Color3.fromRGB(230, 230, 228))
	end
end

------------------------------------------------------------------------
-- 10. Exterior of the building
------------------------------------------------------------------------
local function buildExterior(root)
	local f = folder(root, "Exterior")
	-- illuminated sign above the main entrance (faces the street)
	local sg = model(f, "EntranceSign")
	local back = part(sg, "SignBack", V3(62, 6.6, 0.8), CF(0, 23.4, 81.5), Color3.fromRGB(16, 16, 20), M.SmoothPlastic)
	local s = gui(back, Enum.NormalId.Back, 12, 0)
	frame(s, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(16, 16, 20) })
	label(s, "WORLD CLASS BOXING GYM", { TextColor3 = C.gold, Size = UDim2.fromScale(0.94, 0.66), Position = UDim2.fromScale(0.03, 0.08) })
	label(s, "CHAMPIONS ARE MADE HERE  -  EST. 1987", { TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.6, 0.18), Position = UDim2.fromScale(0.2, 0.76) })
	local neon = model(sg, "Neon")
	for _, e in ipairs({ { 0, 3.35, 62.4, 0.28 }, { 0, -3.35, 62.4, 0.28 }, { -31.2, 0, 0.28, 6.9 }, { 31.2, 0, 0.28, 6.9 } }) do
		part(neon, "NeonTube", V3(e[3], e[4], 0.28), CF(e[1], 23.4 + e[2], 82.0), Color3.fromRGB(255, 40, 50), M.Neon, { shadow = false })
	end
	tag(neon, "NeonFlicker")
	for _, x in ipairs({ -20, 20 }) do
		local fix = part(f, "SignUplight", V3(0.8, 0.6, 1.0), CF(V3(x, 18.6, 83.4), V3(x, 23.4, 81.9)), C.black, M.Metal)
		fix.CFrame = CFrame.lookAt(V3(x, 18.6, 83.4), V3(x * 0.5, 23.4, 81.9))
		spot(emitter(f, fix.CFrame * CF(0, 0, -0.7)), Enum.NormalId.Front, Color3.fromRGB(255, 225, 180), 14, 2.2, 70)
	end
	-- entrance awning, posts and downlights
	part(f, "Awning", V3(24, 0.5, 7.6), CF(0, 15.4, 84.6) * ANG(RAD(16), 0, 0), C.red, M.Fabric)
	local valance = part(f, "AwningValance", V3(24, 1.2, 0.2), CF(0, 13.9, 88.35), C.red, M.Fabric)
	sign(valance, Enum.NormalId.Back, "WORLD CLASS BOXING", Color3.new(1, 1, 1), nil, 30)
	part(f, "AwningStripe", V3(24.1, 0.25, 0.22), CF(0, 14.6, 88.36), C.white, M.Fabric)
	for _, x in ipairs({ -11.6, 11.6 }) do
		part(f, "AwningPost", V3(0.35, 14.6, 0.35), CF(x, 7.3, 88.1), C.black, M.Metal)
		spot(emitter(f, CF(x * 0.45, 14.2, 85.5)), Enum.NormalId.Bottom, Color3.fromRGB(255, 225, 185), 18, 1.4, 100)
	end
	-- door frame and propped-open glass doors
	for _, x in ipairs({ -10.2, 10.2 }) do
		part(f, "DoorFrame", V3(0.5, 14, 2.4), CF(x, 7, 80), C.black, M.Metal)
	end
	part(f, "DoorHeader", V3(21, 0.6, 2.4), CF(0, 14.1, 80), C.black, M.Metal)
	for _, sgn in ipairs({ -1, 1 }) do
		local x = sgn * 10.55
		part(f, "DoorLeaf", V3(0.18, 12.6, 4.8), CF(x, 6.7, 83.6), Color3.fromRGB(190, 220, 240), M.Glass, { transparency = 0.55, shadow = false })
		part(f, "DoorLeafFrame", V3(0.22, 12.8, 0.3), CF(x, 6.7, 86.05), C.black, M.Metal)
		part(f, "DoorHandle", V3(0.12, 2.4, 0.12), CF(x + sgn * 0.2, 5.5, 85.3), C.steelLight, M.Metal)
	end
	part(f, "DoorMat", V3(16, 0.06, 4), CF(0, 0.43, 76.6), C.black, M.Fabric)
	-- pilasters, cornice and parapet
	for _, x in ipairs({ -108.8, -87.5, -60, -35, 35, 60, 87.5, 108.8 }) do
		part(f, "Pilaster", V3(2.2, 30, 0.8), CF(x, 15, 81.4), C.brickDark, M.Brick)
		part(f, "PilasterN", V3(2.2, 30, 0.8), CF(x, 15, -81.4), C.brickDark, M.Brick)
	end
	for _, z in ipairs({ -35, 47 }) do
		part(f, "PilasterW", V3(0.8, 30, 2.2), CF(-111.4, 15, z), C.brickDark, M.Brick)
		-- the Elite wing annex (z 30..66) is built against the east wall where the second pilaster was
		if z ~= 47 then
			part(f, "PilasterE", V3(0.8, 30, 2.2), CF(111.4, 15, z), C.brickDark, M.Brick)
		end
	end
	part(f, "CorniceS", V3(225, 1.3, 1.2), CF(0, 29.4, 81.6), Color3.fromRGB(60, 34, 30), M.Concrete)
	part(f, "CorniceN", V3(225, 1.3, 1.2), CF(0, 29.4, -81.6), Color3.fromRGB(60, 34, 30), M.Concrete)
	part(f, "CorniceW", V3(1.2, 1.3, 165), CF(-111.6, 29.4, 0), Color3.fromRGB(60, 34, 30), M.Concrete)
	part(f, "CorniceE", V3(1.2, 1.3, 165), CF(111.6, 29.4, 0), Color3.fromRGB(60, 34, 30), M.Concrete)
	part(f, "ParapetS", V3(224, 2.2, 0.8), CF(0, 33.1, 80.7), C.brickDark, M.Brick)
	part(f, "ParapetN", V3(224, 2.2, 0.8), CF(0, 33.1, -80.7), C.brickDark, M.Brick)
	part(f, "ParapetW", V3(0.8, 2.2, 162), CF(-110.7, 33.1, 0), C.brickDark, M.Brick)
	part(f, "ParapetE", V3(0.8, 2.2, 162), CF(110.7, 33.1, 0), C.brickDark, M.Brick)
	-- wall-pack lights
	for _, p in ipairs({ { V3(-22.5, 11.6, 81.6), V3(0, 0, 1) }, { V3(22.5, 11.6, 81.6), V3(0, 0, 1) }, { V3(-104, 11.6, 81.6), V3(0, 0, 1) }, { V3(104, 11.6, 81.6), V3(0, 0, 1) }, { V3(-111.6, 11.6, 10), V3(-1, 0, 0) }, { V3(111.6, 11.6, 10), V3(1, 0, 0) } }) do
		local box = part(f, "WallPack", V3(1.4, 1.1, 1.4), CFrame.lookAt(p[1], p[1] + p[2]), C.black, M.Metal)
		part(f, "WallPackLens", V3(1.1, 0.4, 0.1), box.CFrame * CF(0, -0.25, -0.72), Color3.fromRGB(255, 230, 190), M.Neon, { shadow = false })
		spot(emitter(f, box.CFrame * CF(0, -0.8, -1.2)), Enum.NormalId.Bottom, Color3.fromRGB(255, 220, 170), 22, 1.3, 120)
	end
	-- fight posters and an OPEN sign on the facade
	for _, x in ipairs({ -26, -19, 19, 26 }) do
		wallPoster(f, "XS", x, 6.5, 4.4, 6.2)
	end
	local open = part(f, "OpenSign", V3(4.6, 1.6, 0.2), CF(-14.2, 9, 81.25), Color3.fromRGB(14, 14, 18), M.SmoothPlastic)
	sign(open, Enum.NormalId.Back, "OPEN 24/7", Color3.fromRGB(255, 70, 70), Color3.fromRGB(14, 14, 18), 40)
	local openNeon = part(f, "OpenNeon", V3(4.9, 1.9, 0.08), CF(-14.2, 9, 81.38), Color3.fromRGB(255, 60, 60), M.Neon, { transparency = 0.7, shadow = false })
	tag(openNeon, "NeonFlicker")
	-- sidewalk (split around the entrance path), curb, planters, benches, bins, hydrant, bike rack
	for _, seg in ipairs({ { -110, -5 }, { 5, 110 } }) do
		local mid, len = (seg[1] + seg[2]) / 2, seg[2] - seg[1]
		part(f, "Sidewalk", V3(len, 0.32, 8), CF(mid, 0.16, 85.1), C.concrete, M.Concrete, { collide = true })
		part(f, "Curb", V3(len, 0.45, 0.45), CF(mid, 0.22, 89.3), Color3.fromRGB(190, 188, 182), M.Concrete, { collide = true })
	end
	for _, x in ipairs({ -55, -85, 55, 85 }) do
		part(f, "Planter", V3(5, 1.5, 2.2), CF(x, 1.05, 87.4), C.brickDark, M.Brick, { collide = true })
		part(f, "PlanterSoil", V3(4.6, 0.1, 1.8), CF(x, 1.82, 87.4), Color3.fromRGB(60, 42, 30), M.Ground)
		for _, dx in ipairs({ -1.4, 0, 1.4 }) do
			blob(f, "Shrub", V3(1.8, 1.6, 1.6), CF(x + dx, 2.5, 87.4), Color3.fromRGB(50 + math.abs(dx) * 10, 115, 55), M.Grass)
		end
	end
	bench(f, V3(-40, 0.32, 87.6), 0, 6, C.wood)
	bench(f, V3(40, 0.32, 87.6), 0, 6, C.wood)
	for _, x in ipairs({ -12.8, 12.8 }) do
		vcyl(f, "TrashBin", 2.6, 1.6, CF(x, 0.32, 88.2), Color3.fromRGB(40, 70, 50), M.Metal, { collide = true })
		vcyl(f, "BinLid", 0.3, 1.8, CF(x, 2.92, 88.2), Color3.fromRGB(30, 50, 36), M.Metal)
	end
	local hy = V3(68, 0.32, 88.6)
	vcyl(f, "Hydrant", 2.1, 0.8, CF(hy), C.red, M.Metal, { collide = true })
	ball(f, "HydrantCap", 0.85, CF(hy + V3(0, 2.1, 0)), C.red, M.Metal)
	cyl(f, "HydrantNozzle", 1.4, 0.35, CF(hy + V3(0, 1.4, 0)), C.gold, M.Metal)
	local br = V3(-24, 0.32, 87.6)
	part(f, "BikeRackBase", V3(8, 0.2, 0.3), CF(br + V3(0, 0.1, 0)), C.steelLight, M.Metal)
	for k = 0, 3 do
		local x = -3 + k * 2
		for _, dz in ipairs({ -0.5, 0.5 }) do
			part(f, "BikeRackPost", V3(0.15, 2.2, 0.15), CF(br + V3(x, 1.1, dz)), C.steelLight, M.Metal)
		end
		part(f, "BikeRackTop", V3(0.15, 0.15, 1.15), CF(br + V3(x, 2.2, 0)), C.steelLight, M.Metal)
	end
	-- rooftop units, vents and a water tank
	for _, p in ipairs({ V3(-40, 32, 50), V3(40, 32, 50), V3(-70, 32, -40), V3(70, 32, -40) }) do
		part(f, "ACUnit", V3(6, 3.2, 4), CF(p + V3(0, 1.6, 0)), Color3.fromRGB(200, 202, 206), M.Metal)
		vcyl(f, "ACFan", 0.2, 3, CF(p + V3(0, 3.2, 0)), C.black, M.Metal)
		part(f, "ACDuct", V3(1.2, 1.2, 3), CF(p + V3(0, 0.6, 3.2)), C.galv, M.Metal)
	end
	for _, p in ipairs({ V3(-15, 32, -20), V3(20, 32, 10), V3(-80, 32, 20), V3(85, 32, 0) }) do
		vcyl(f, "RoofVent", 1.6, 1, CF(p), C.galv, M.Metal)
		vcyl(f, "RoofVentCap", 0.3, 1.6, CF(p + V3(0, 1.7, 0)), C.galv, M.Metal)
	end
	local wt = V3(85, 32, 55)
	for _, d in ipairs({ { -2.4, -2.4 }, { 2.4, -2.4 }, { 2.4, 2.4 }, { -2.4, 2.4 } }) do
		part(f, "TankLeg", V3(0.5, 6, 0.5), CF(wt + V3(d[1], 3, d[2])), C.steel, M.Metal)
	end
	vcyl(f, "WaterTank", 7, 8, CF(wt + V3(0, 6, 0)), Color3.fromRGB(120, 90, 66), M.WoodPlanks)
	vcyl(f, "TankRoof", 1.2, 8.4, CF(wt + V3(0, 13, 0)), Color3.fromRGB(80, 60, 46), M.Wood)
	-- fire escape ladder on the west facade and downspouts at the corners
	for _, dz in ipairs({ -0.8, 0.8 }) do
		part(f, "LadderRail", V3(0.2, 30, 0.2), CF(-111.8, 15, 40 + dz), C.black, M.Metal)
	end
	for k = 1, 19 do
		part(f, "LadderRung", V3(0.15, 0.15, 1.6), CF(-111.8, k * 1.5, 40), C.black, M.Metal)
	end
	for _, c in ipairs({ { -111.4, 81.4 }, { 111.4, 81.4 }, { -111.4, -81.4 }, { 111.4, -81.4 } }) do
		vcyl(f, "Downspout", 30, 0.5, CF(c[1], 0, c[2]), C.galv, M.Metal)
	end
	-- dumpsters behind the gym
	for i, x in ipairs({ -72, -64 }) do
		part(f, "Dumpster", V3(6, 4, 3.6), CF(x, 2.0, -85), i == 1 and Color3.fromRGB(40, 90, 50) or Color3.fromRGB(40, 60, 120), M.Metal, { collide = true })
		part(f, "DumpsterLid", V3(6.1, 0.2, 3.7), CF(x, 4.1, -85) * ANG(RAD(-6), 0, 0), C.black, M.Plastic)
	end
end

------------------------------------------------------------------------
-- Reusable animated props (also used by MapBuilder/CityMap)
------------------------------------------------------------------------
-- Round timer box: cf faces -Z with its front; both faces show the clock when doubleSided.
function GymDecor.RoundTimer(parent, cf, width, doubleSided, wallMounted)
	local m = model(parent, "RoundTimer")
	local h = width * 0.36
	local box = part(m, "TimerBox", V3(width, h, 0.9), cf, C.black, M.SmoothPlastic)
	local faces = { Enum.NormalId.Front }
	if doubleSided then
		table.insert(faces, Enum.NormalId.Back)
	end
	for _, face in ipairs(faces) do
		local sg = gui(box, face, 30, 0)
		frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 10) })
		label(sg, "ROUND 1", { Name = "Phase", TextColor3 = C.gold, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.5, 0.26), Position = UDim2.fromScale(0.25, 0.04) })
		label(sg, "3:00", { Name = "Time", TextColor3 = Color3.fromRGB(255, 60, 50), Font = Enum.Font.Code, Size = UDim2.fromScale(0.86, 0.66), Position = UDim2.fromScale(0.07, 0.3) })
	end
	for i, colr in ipairs({ Color3.fromRGB(40, 220, 80), Color3.fromRGB(250, 200, 40), Color3.fromRGB(240, 50, 40) }) do
		local lamp = part(m, ({ "LampGo", "LampWarn", "LampRest" })[i], V3(0.8, 0.8, 0.8), cf * CF((i - 2) * 1.1, h / 2 + 0.45, 0), colr, M.Neon, { shape = Enum.PartType.Ball, shadow = false })
		lamp.Transparency = 0.6
	end
	if not wallMounted then
		for _, x in ipairs({ -width / 2 + 0.6, width / 2 - 0.6 }) do
			local top = (cf * CF(x, h / 2, 0)).Position
			part(m, "TimerCable", V3(0.08, math.max(0.5, 29 - top.Y), 0.08), CF(top.X, (top.Y + 29) / 2, top.Z), C.black, M.Metal, { shadow = false })
		end
	end
	m.PrimaryPart = box
	tag(m, "RoundTimer")
	return m
end

-- TV screen with a scrolling headline ticker
local HEADLINES = {
	"WCB SPORTS  -  Tonight: VEGA defends against KOVAC in a 12-round war",
	"Rankings shake-up: three new contenders crack the welterweight top 10",
	"Local amateur posts fastest knockout of the season at the Community Center",
	"Training camp report: champions average 6 sessions a day in fight week",
	"Golden Gloves regional tournament sign-ups now open at the front desk",
	"Fight Night at the WCB Arena  -  SOLD OUT",
}
function GymDecor.Ticker(screenPart, face, title)
	local sg = gui(screenPart, face, 40, 0)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 14, 24) })
	frame(sg, { Size = UDim2.new(1, 0, 0.18, 0), BackgroundColor3 = Color3.fromRGB(190, 20, 30) })
	label(sg, title or "WCB SPORTS", { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0.6, 0, 0.14, 0), Position = UDim2.fromScale(0.03, 0.02), TextXAlignment = Enum.TextXAlignment.Left })
	label(sg, "LIVE", { TextColor3 = C.gold, Size = UDim2.new(0.2, 0, 0.12, 0), Position = UDim2.fromScale(0.77, 0.03) })
	-- a "broadcast" picture: ring and two fighters as simple shapes
	local pic = frame(sg, { Size = UDim2.fromScale(0.94, 0.56), Position = UDim2.fromScale(0.03, 0.21), BackgroundColor3 = Color3.fromRGB(24, 30, 48) })
	frame(pic, { Size = UDim2.fromScale(0.8, 0.22), Position = UDim2.fromScale(0.1, 0.7), BackgroundColor3 = Color3.fromRGB(40, 70, 170) })
	for i, x in ipairs({ 0.36, 0.56 }) do
		local body = frame(pic, { Size = UDim2.fromScale(0.08, 0.4), Position = UDim2.fromScale(x, 0.32), BackgroundColor3 = Color3.fromRGB(150 - i * 40, 100 - i * 25, 70 - i * 18) })
		local glove = frame(pic, { Size = UDim2.fromScale(0.05, 0.12), Position = UDim2.fromScale(i == 1 and 0.08 or -0.05, 0.1), BackgroundColor3 = i == 1 and C.red or C.blue })
		glove.Parent = body
		Instance.new("UICorner", glove).CornerRadius = UDim.new(0.5, 0)
	end
	local ticker = frame(sg, { Name = "Ticker", Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.8), BackgroundColor3 = Color3.fromRGB(240, 240, 245), ClipsDescendants = true })
	label(ticker, table.concat(HEADLINES, "     *     "), { Name = "Text", TextScaled = false, TextSize = 26, TextWrapped = false, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(16, 16, 22), TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0, 4000, 1, 0) })
	tag(screenPart, "TVTicker")
	return sg
end

GymDecor.Part = part
GymDecor.Cyl = cyl
GymDecor.VCyl = vcyl
GymDecor.Ball = ball
GymDecor.Blob = blob
GymDecor.Rod = rod
GymDecor.Gui = gui
GymDecor.Label = label
GymDecor.Frame = frame
GymDecor.Sign = sign
GymDecor.Spot = spot
GymDecor.Point = point
GymDecor.Emitter = emitter
GymDecor.Tag = tag
GymDecor.Plant = plant
GymDecor.Bench = bench
GymDecor.Fan = fan
GymDecor.PosterGui = posterGui
GymDecor.Posters = POSTERS
GymDecor.Colors = C

------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------
function GymDecor.Build(gym)
	local root = folder(gym, "Decor")
	local sections = {
		{ "structure", buildStructure }, { "lights", buildLights }, { "lobby", buildLobby }, { "boxing", buildBoxing },
		{ "weights", buildWeights }, { "cardio", buildCardio }, { "recovery", buildRecovery }, { "services", buildServices },
		{ "pool", buildPool }, { "exterior", buildExterior },
	}
	for _, s in ipairs(sections) do
		local ok, err = pcall(s[2], root)
		if not ok then
			warn("[GymDecor] " .. s[1] .. " failed: " .. tostring(err))
		end
	end
	return root
end

return GymDecor
