-- MapBuilder: builds the training complex entirely from parts.
-- Gym zones: Boxing Area, Weight Room, Cardio Room, Recovery Area, Barber Shop,
-- Locker Room, Nutrition Bar, Bunk Room, lobby with Fight Board & trophy case.
-- Outside: roadwork loop with checkpoints, swimming pool annex (real water).
-- Equipment visuals per upgrade level are drawn client-side (GymVisuals) at each
-- station's Base; the server provides the anchors, use points and prompts.
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GymDecor = require(script.Parent:WaitForChild("GymDecor"))
local CityMap = require(script.Parent:WaitForChild("CityMap"))

local MapBuilder = {}

local V3 = Vector3.new
local CF = CFrame.new

local function part(parent, props)
	local p = Instance.new(props.Class or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Class" then
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function deco(parent, name, size, cf, color, material, extra)
	local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return part(parent, props)
end

local function label(adornee, text, color, offsetY, maxDist)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 46)
	bb.StudsOffset = V3(0, offsetY or 4, 0)
	bb.MaxDistance = maxDist or 70
	bb.Adornee = adornee
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Parent = bb
	bb.Parent = adornee
	return bb
end

local function sign(p, face, text, bg, fg)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg or Color3.fromRGB(15, 15, 18)
	t.BackgroundTransparency = bg and 0 or 1
	t.TextColor3 = fg or Color3.fromRGB(255, 200, 40)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.Parent = sg
	sg.Parent = p
	return t
end

local function prompt(p, actionText, objectText, attrs)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText
	pp.ObjectText = objectText
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	for k, v in pairs(attrs) do
		pp:SetAttribute(k, v)
	end
	pp.Parent = p
	return pp
end

------------------------------------------------------------------------
-- Station layout. pos = equipment base; use = where the boxer trains; yaw = direction the boxer faces
------------------------------------------------------------------------
MapBuilder.StationDefs = {
	-- pos = equipment base, use = where the boxer trains (facing yaw, 0 = -Z),
	-- exit = world offset to step off the equipment, stand/seat/lie = surface heights
	-- Boxing Area
	{ id = "heavybag", act = "HeavyBag", pos = V3(-34, 0, -14), use = V3(-34, 0, -10.4), pose = "heavybag", exit = V3(0, 0, 3) },
	{ id = "speedbag", act = "SpeedBag", pos = V3(-18, 0, -14), use = V3(-18, 0, -11.5), pose = "speedbag", exit = V3(0, 0, 3) },
	{ id = "doubleend", act = "DoubleEnd", pos = V3(-2, 0, -14), use = V3(-2, 0, -10.4), pose = "guard", exit = V3(0, 0, 3) },
	{ id = "mitts", act = "MittWork", pos = V3(14, 0, -14), use = V3(14, 0, -10.2), pose = "guard", exit = V3(0, 0, 3) },
	{ id = "mirror", act = "Shadow", pos = V3(32, 0, -16), use = V3(32, 0, -9.5), pose = "guard", exit = V3(0, 0, 3) },
	-- Weight Room
	{ id = "bench", act = "Bench", pos = V3(-92, 0, -52), use = V3(-92, 0, -52), pose = "bench", lie = 1.6, exit = V3(3.4, 0, 0) },
	{ id = "dumbbells", act = "Dumbbells", pos = V3(-72, 0, -56), use = V3(-72, 0, -51.5), pose = "curl", exit = V3(0, 0, 3) },
	{ id = "barbell", act = "Barbell", pos = V3(-92, 0, -24), use = V3(-92, 0, -24), pose = "deadlift", stand = 0.3, exit = V3(0, 0, 5.5) },
	{ id = "squat", act = "Squat", pos = V3(-72, 0, -24), use = V3(-72, 0, -24.3), pose = "squat", stand = 0.2, exit = V3(0, 0, 4.5) },
	{ id = "pullup", act = "PullUps", pos = V3(-92, 0, 2), use = V3(-92, 0, 2), pose = "pullup", exit = V3(0, 0, 3.5) },
	-- medicine ball: slam pad / wall-ball target at pos, the athlete stands 3.8 studs south of it
	-- (clear of Andre Cole's curl spot at x -62 and the z = 20 divider)
	{ id = "medball", act = "MedBall", pos = V3(-74, 0, -1), use = V3(-74, 0, 2.8), pose = "medball", stand = 0, exit = V3(0, 0, 3.2) },
	-- Cardio Room
	{ id = "treadmill", act = "Treadmill", pos = V3(70, 0, -52), use = V3(70, 0, -51.6), pose = "run", stand = 0.7, exit = V3(3.6, 0, 0) },
	{ id = "bike", act = "Bike", pos = V3(90, 0, -52), use = V3(90, 0, -51.2), pose = "bike", seat = 2.7, exit = V3(3.4, 0, 0) },
	{ id = "rower", act = "Rower", pos = V3(70, 0, -26), use = V3(70, 0, -24.4), pose = "row", seat = 0.9, exit = V3(3.2, 0, 0) },
	{ id = "rope", act = "Rope", pos = V3(92, 0, -26), use = V3(92, 0, -26), pose = "rope", stand = 0.1, exit = V3(0, 0, 3) },
	{ id = "ladder", act = "Ladder", pos = V3(80, 0, 2), use = V3(80, 0, 8.5), pose = "ladder", exit = V3(3.5, 0, 0) },
	-- Recovery Area
	{ id = "icebath", act = "IceBath", pos = V3(64, 0, 34), use = V3(64, 0, 34.6), pose = "longsit", seat = 0.35, exit = V3(3.6, 0, 0) },
	{ id = "stretch", act = "Stretch", pos = V3(82, 0, 34), use = V3(82, 0, 34), pose = "stretch", stand = 0.1, exit = V3(0, 0, 3) },
	{ id = "sauna", act = "Sauna", pos = V3(100, 0, 36), use = V3(100, 0, 33.4), pose = "sit", seat = 1.6, yaw = 180, exit = V3(0, 0, 8) },
	{ id = "massage", act = "Massage", pos = V3(64, 0, 60), use = V3(64, 0, 60.4), pose = "lie", lie = 2.4, exit = V3(3.4, 0, 0) },
	{ id = "chamber", act = "Chamber", pos = V3(84, 0, 62), use = V3(84, 0, 62.6), pose = "lieup", lie = 1.3, exit = V3(3.6, 0, 0) },
}

MapBuilder.FloorY = 0.5 -- top of the zone floors (stations stand on these)

MapBuilder.RingCenter = V3(0, 0, -50) -- gym sparring ring (visual)

-- Elite Performance Wing: an annex on the east side of the Recovery Area, entered through a
-- door in the east wall. The server builds the shell (everyone shares it); the interior and
-- whether the doors open are drawn client-side from YOUR facility tier (GymVisuals).
MapBuilder.EliteWing = { x1 = 111, x2 = 153, z1 = 30, z2 = 66, h = 20, door = { 44, 56 } }

-- members' hanging bags (server rigs the client swings when members / players hit them)
MapBuilder.MemberBags = { V3(-36, 0, -30), V3(-24, 0, -30) }

-- Champion's Lounge mezzanine over the east lobby: a deck (x1..x2, z1..z2, floor at y) on steel
-- columns, reached by a stair along its west edge (centre line stairX, foot at z foot, `risers`
-- equal risers up to the deck over treads `going` deep, then a landing). The server builds it so
-- every client collides with the same deck and stairs (nobody stands on air on someone else's
-- screen); the glass gate at the stair foot opens (locally, like the Elite wing doors) for a World
-- Champion facility, and the client dresses the deck as the lounge (GymFacility.buildGallery).
-- The stair foot is south of the lobby water cooler (x 17..19, z 39..41).
MapBuilder.Mezzanine = { x1 = 20, x2 = 46.5, z1 = 38, z2 = 79, y = 12.3, stairX = 18, stairW = 4, foot = 45, risers = 18, going = 1 }

------------------------------------------------------------------------
-- Gym building
------------------------------------------------------------------------
local WOOD = Color3.fromRGB(122, 88, 60)
local WALL = Color3.fromRGB(122, 66, 52) -- red-brown brick shell
local DIVIDER = Color3.fromRGB(70, 72, 80) -- painted block dividers inside
local TRIM = Color3.fromRGB(200, 30, 35)

-- window openings in the shell (centre along the wall); all share one height band
local WIN_W, WIN_Y0, WIN_Y1 = 10, 17, 24
MapBuilder.Windows = {
	N = { -100, -75, -45, 45, 75, 100 },
	S = { -100, -75, -45, 45, 75, 100 },
	W = { -66, -3, 22, 72 },
	E = { -66, -3, 22, 72 },
}

-- a wall built as boxes around rectangular openings: axis "X" runs along X at z = c,
-- axis "Z" runs along Z at x = c; openings = { { a, b, y0, y1 }, ... } along the wall
local function wallWithOpenings(parent, axis, c, from, to, h, openings, color)
	local ys = { 0, h }
	for _, o in ipairs(openings) do
		table.insert(ys, o[3])
		table.insert(ys, o[4])
	end
	table.sort(ys)
	for i = 1, #ys - 1 do
		local y0, y1 = ys[i], ys[i + 1]
		if y1 - y0 > 0.01 then
			local cuts = {}
			for _, o in ipairs(openings) do
				if o[3] < y1 - 0.01 and o[4] > y0 + 0.01 then
					table.insert(cuts, o)
				end
			end
			table.sort(cuts, function(p, q)
				return p[1] < q[1]
			end)
			local cursor = from
			local function seg(a, b)
				if b - a > 0.05 then
					local mid, len = (a + b) / 2, b - a
					if axis == "X" then
						part(parent, { Name = "Wall", Size = V3(len, y1 - y0, 2), CFrame = CF(mid, (y0 + y1) / 2, c), Color = color, Material = Enum.Material.Brick })
					else
						part(parent, { Name = "Wall", Size = V3(2, y1 - y0, len), CFrame = CF(c, (y0 + y1) / 2, mid), Color = color, Material = Enum.Material.Brick })
					end
				end
			end
			for _, cut in ipairs(cuts) do
				seg(cursor, cut[1])
				cursor = math.max(cursor, cut[2])
			end
			seg(cursor, to)
		end
	end
end

-- glass, jambs, head, sill, mullion and transom for one window opening (frames show inside and out).
-- width / y0 / y1 default to the main hall's window band; the Elite wing passes its own.
local function windowFrame(parent, axis, c, along, width, y0, y1)
	local frameColor = Color3.fromRGB(30, 30, 34)
	local winW, winY0, winY1 = width or WIN_W, y0 or WIN_Y0, y1 or WIN_Y1
	local h = winY1 - winY0
	local midY = (winY0 + winY1) / 2
	local function box(name, alongOff, y, w, hh, depth, color, material, extra)
		local size = axis == "X" and V3(w, hh, depth) or V3(depth, hh, w)
		local pos = axis == "X" and V3(along + alongOff, y, c) or V3(c, y, along + alongOff)
		local props = { Name = name, Size = size, CFrame = CF(pos), Color = color, Material = material or Enum.Material.Metal }
		for k, v in pairs(extra or {}) do
			props[k] = v
		end
		return part(parent, props)
	end
	box("WindowGlass", 0, midY, winW, h, 0.2, Color3.fromRGB(170, 205, 230), Enum.Material.Glass, { Transparency = 0.62, CastShadow = false, Reflectance = 0.08 })
	box("WindowJamb", -winW / 2 + 0.2, midY, 0.4, h, 2.4, frameColor)
	box("WindowJamb", winW / 2 - 0.2, midY, 0.4, h, 2.4, frameColor)
	box("WindowHead", 0, winY1 - 0.2, winW, 0.4, 2.4, frameColor)
	box("WindowSill", 0, winY0 - 0.15, winW + 1, 0.5, 3.2, Color3.fromRGB(150, 146, 140), Enum.Material.Concrete)
	box("WindowMullion", 0, midY, 0.25, h, 0.5, frameColor, nil, { CanCollide = false })
	box("WindowTransom", 0, winY0 + h * 0.66, winW, 0.22, 0.5, frameColor, nil, { CanCollide = false })
end

local function zoneSign(parent, text, cf, color)
	local p = deco(parent, "ZoneSign", V3(30, 5, 0.6), cf, Color3.fromRGB(18, 18, 22))
	sign(p, Enum.NormalId.Front, text, Color3.fromRGB(18, 18, 22), color or Color3.fromRGB(255, 200, 40))
	sign(p, Enum.NormalId.Back, text, Color3.fromRGB(18, 18, 22), color or Color3.fromRGB(255, 200, 40))
	return p
end

local function floorZone(parent, name, x1, z1, x2, z2, color, material)
	deco(parent, name, V3(x2 - x1, 0.1, z2 - z1), CF((x1 + x2) / 2, 0.45, (z1 + z2) / 2), color, material or Enum.Material.Rubber)
end

local function lamp(parent, pos, range, brightness, color)
	local l = deco(parent, "Lamp", V3(8, 0.4, 2), CF(pos), Color3.fromRGB(255, 250, 235), Enum.Material.Neon)
	local pl = Instance.new("PointLight")
	pl.Range = range or 34
	pl.Brightness = brightness or 0.85
	pl.Color = color or Color3.fromRGB(255, 244, 225)
	pl.Shadows = false
	pl.Parent = l
	return l
end

local function buildRing(parent, center, half, height, colors)
	local ring = Instance.new("Model")
	ring.Name = "GymRing"
	ring.Parent = parent
	deco(ring, "RingBase", V3(half * 2 + 4, height, half * 2 + 4), CF(center + V3(0, height / 2, 0)), Color3.fromRGB(25, 25, 28))
	deco(ring, "Canvas", V3(half * 2 + 4, 0.3, half * 2 + 4), CF(center + V3(0, height + 0.15, 0)), Color3.fromRGB(40, 70, 170), Enum.Material.Fabric)
	local corners = { { -half, -half }, { half, -half }, { half, half }, { -half, half } }
	for i, c in ipairs(corners) do
		deco(ring, "Post", V3(0.6, 4.5, 0.6), CF(center + V3(c[1], height + 2.25, c[2])), (i == 1 and colors[1]) or (i == 3 and colors[2]) or Color3.fromRGB(230, 230, 230), Enum.Material.Metal)
	end
	for ri, h in ipairs({ 1.4, 2.6, 3.8 }) do
		for side = 1, 4 do
			local a, b = corners[side], corners[side % 4 + 1]
			local pa = center + V3(a[1], height + h, a[2])
			local pb = center + V3(b[1], height + h, b[2])
			deco(ring, "Rope", V3(0.2, 0.2, (pb - pa).Magnitude), CFrame.lookAt((pa + pb) / 2, pb), ri == 2 and Color3.fromRGB(240, 240, 240) or TRIM, Enum.Material.Fabric, { CanCollide = false })
		end
	end
	return ring
end

local function buildStationAnchors(gym, def)
	local m = Instance.new("Model")
	m.Name = "Station_" .. def.id
	m.Parent = gym
	local act = Config.FindById(Config.Activities, def.act)
	local fy = MapBuilder.FloorY
	local base = deco(m, "Base", V3(1, 1, 1), CF(def.pos.X, fy + 0.5, def.pos.Z), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	base:SetAttribute("Station", def.id)
	local yaw = math.rad(def.yaw or 0)
	local useCF = CF(def.use.X, fy, def.use.Z) * CFrame.Angles(0, yaw, 0)
	local use = deco(m, "UsePoint", V3(1, 1, 1), useCF, Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	use:SetAttribute("Station", def.id)
	use:SetAttribute("Pose", def.pose)
	use:SetAttribute("Stand", def.stand or 0)
	if def.seat then
		use:SetAttribute("Seat", def.seat)
	end
	if def.lie then
		use:SetAttribute("Lie", def.lie)
	end
	local pp = deco(m, "PromptPart", V3(1, 1, 1), CF(def.use.X, fy + 3.2, def.use.Z), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	prompt(pp, act and act.name or def.id, act and act.area or "Gym", { Activity = def.act, Station = def.id })
	label(pp, act and act.name or def.id, Color3.fromRGB(255, 220, 90), 4.2, 60)
	m.PrimaryPart = base
	return m
end

-- A member bag hanging from the roof on a long chain. Only the swinging pieces go in the rig
-- model (tag "MemberBag", attribute Hook = the pivot): the client swings, twists and dents it
-- locally when a member or another player throws a punch at it (GymVisuals). The ceiling rod
-- and plate stay outside the rig because they never move.
local function buildMemberBag(gym, x, z, i)
	local hookY = 25.1
	local steel = Color3.fromRGB(150, 150, 160)
	deco(gym, "BeamBag", V3(0.4, 30 - hookY, 0.4), CF(x, (30 + hookY) / 2, z), steel, Enum.Material.Metal)
	deco(gym, "BagCeilingPlate", V3(1.4, 0.2, 1.4), CF(x, 29.9, z), Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
	local rig = Instance.new("Model")
	rig.Name = "MemberBagRig"
	rig:SetAttribute("Hook", V3(x, hookY, z))
	rig:SetAttribute("Index", i)
	rig.Parent = gym
	local leather = i == 1 and Color3.fromRGB(150, 30, 30) or Color3.fromRGB(30, 30, 30)
	local trim = i == 1 and Color3.fromRGB(30, 30, 30) or Color3.fromRGB(200, 170, 60)
	local chainC = Color3.fromRGB(160, 160, 165)
	local function link(a, b, k)
		local d = b - a
		local cf = CFrame.lookAt((a + b) / 2, b, Vector3.xAxis) * CFrame.Angles(math.rad(90), (k % 2) * math.pi / 2, 0)
		deco(rig, "Chain", V3(0.22, d.Magnitude * 1.15, 0.08), cf, chainC, Enum.Material.Metal, { CanCollide = false, CanQuery = false })
	end
	-- main chain: 9 long links from the hook to the swivel above the bag
	local top, bottom = V3(x, hookY, z), V3(x, 9.3, z)
	for k = 1, 9 do
		link(top:Lerp(bottom, (k - 1) / 9), top:Lerp(bottom, k / 9), k)
	end
	deco(rig, "Swivel", V3(0.3, 0.45, 0.3), CF(x, 9.1, z), chainC, Enum.Material.Metal, { CanCollide = false })
	-- four spreader chains to D-rings on the top cap
	for _, s in ipairs({ { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
		local foot = V3(x + s[1] * 0.6, 8.25, z + s[2] * 0.6)
		link(V3(x, 8.9, z), foot, s[1] + 2)
	end
	local up = CFrame.Angles(0, 0, math.rad(90))
	-- the 5-stud body is 5 stacked 1-stud cylinders (a hair longer so no seam shows) centred on
	-- y 5.6: the client dents the hit segment and springs it back (GymVisuals.addMemberBag finds the
	-- middle one by name "MemberBag"; BagLen tells it the body length)
	rig:SetAttribute("BagLen", 5)
	for k = 0, 4 do
		local seg = deco(rig, k == 2 and "MemberBag" or "MemberBagSeg", V3(1.05, 2.6, 2.6), CF(x, 3.6 + k, z) * up, leather, Enum.Material.Leather)
		seg.Shape = Enum.PartType.Cylinder
		seg.Size = V3(1.05, 2.6, 2.6)
	end
	for _, y in ipairs({ 8.12, 3.08 }) do
		local cap = deco(rig, "BagCap", V3(0.2, 2.55, 2.55), CF(x, y, z) * up, Color3.fromRGB(22, 22, 26), Enum.Material.Leather)
		cap.Shape = Enum.PartType.Cylinder
	end
	for _, y in ipairs({ 7.1, 4.1 }) do
		local band = deco(rig, "BagBand", V3(0.22, 2.64, 2.64), CF(x, y, z) * up, trim, Enum.Material.Leather)
		band.Shape = Enum.PartType.Cylinder
	end
	-- the patch sits inside one segment (6.1..7.1) so it rides with that segment's dent
	local patch = deco(rig, "BagPatch", V3(1.1, 0.7, 0.2), CF(x, 6.6, z + 1.24), Color3.fromRGB(20, 20, 24), Enum.Material.Leather)
	sign(patch, Enum.NormalId.Back, "WCB", Color3.fromRGB(20, 20, 24), Color3.fromRGB(255, 200, 40))
	CollectionService:AddTag(rig, "MemberBag")
	return rig
end

-- Elite Performance Wing shell (see MapBuilder.EliteWing): floor, clad walls with tall windows,
-- a roof with two skylights, the doorway into the main hall with glass doors (they open for you
-- locally once your gym reaches the Elite tier) and ceiling lights that stay off until then.
local function buildEliteWing(gym)
	local E = MapBuilder.EliteWing
	local f = Instance.new("Folder")
	f.Name = "EliteWing"
	f.Parent = gym
	local x1, x2, z1, z2, h = E.x1, E.x2, E.z1, E.z2, E.h
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local clad = Color3.fromRGB(46, 48, 54)
	local floorC = Color3.fromRGB(196, 198, 204)
	deco(f, "EliteFloor", V3(x2 - x1, 0.5, z2 - z1), CF(cx, 0.25, cz), floorC, Enum.Material.Marble)
	-- the doorway itself (the wall's 2-stud thickness: the hall floor ends at x 110, the wing's at x1)
	deco(f, "Threshold", V3(x1 - 110, 0.5, E.door[2] - E.door[1]), CF((x1 + 110) / 2, 0.25, (E.door[1] + E.door[2]) / 2), floorC, Enum.Material.Marble)
	-- tall windows: two on the east face, two on the south face, all glass named WindowGlass so the
	-- client's sun shafts find them like the hall's windows
	local wy0, wy1, ww = 3, 15, 9
	local function openings(list)
		local out = {}
		for _, a in ipairs(list) do
			table.insert(out, { a - ww / 2, a + ww / 2, wy0, wy1 })
		end
		return out
	end
	local eastWin, southWin = { 40, 56 }, { 122, 142 }
	wallWithOpenings(f, "X", z1, x1, x2 + 1, h, {}, clad)
	wallWithOpenings(f, "X", z2, x1, x2 + 1, h, openings(southWin), clad)
	wallWithOpenings(f, "Z", x2, z1 + 1, z2 - 1, h, openings(eastWin), clad)
	for _, w in ipairs(f:GetChildren()) do
		if w.Name == "Wall" then
			w.Material = Enum.Material.Concrete
		end
	end
	for _, a in ipairs(eastWin) do
		windowFrame(f, "Z", x2, a, ww, wy0, wy1)
	end
	for _, a in ipairs(southWin) do
		windowFrame(f, "X", z2, a, ww, wy0, wy1)
	end
	-- roof in three slabs around two skylights (glass named SkylightGlass: shafts from above)
	local sky = { { 122, 128 }, { 136, 142 } } -- x spans of the skylights
	local cuts = { x1 - 0.5, sky[1][1], sky[1][2], sky[2][1], sky[2][2], x2 + 1.5 }
	for k = 1, #cuts - 1, 2 do
		local a, b = cuts[k], cuts[k + 1]
		deco(f, "EliteRoof", V3(b - a, 1, z2 - z1 + 2), CF((a + b) / 2, h + 0.5, cz), Color3.fromRGB(38, 40, 44), Enum.Material.Metal)
	end
	for _, s in ipairs(sky) do
		local a, b = s[1], s[2]
		-- solid strips at both ends of each skylight, glass between them
		for _, zz in ipairs({ z1 + 2, z2 - 2 }) do
			deco(f, "EliteRoof", V3(b - a, 1, 6), CF((a + b) / 2, h + 0.5, zz), Color3.fromRGB(38, 40, 44), Enum.Material.Metal)
		end
		local glassLen = z2 - z1 - 10
		deco(f, "SkylightGlass", V3(b - a, 0.2, glassLen), CF((a + b) / 2, h + 0.6, cz), Color3.fromRGB(180, 210, 235), Enum.Material.Glass, { Transparency = 0.55, CastShadow = false })
		for k = 1, 4 do
			deco(f, "SkylightMullion", V3(b - a, 0.3, 0.25), CF((a + b) / 2, h + 0.3, z1 + 5 + k * glassLen / 5), Color3.fromRGB(30, 30, 34), Enum.Material.Metal, { CanCollide = false })
		end
	end
	deco(f, "EliteParapet", V3(x2 - x1 + 2, 1.4, 0.6), CF(cx, h + 1.7, z2 + 0.9), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	deco(f, "EliteParapet", V3(x2 - x1 + 2, 1.4, 0.6), CF(cx, h + 1.7, z1 - 0.9), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	deco(f, "EliteParapet", V3(0.6, 1.4, z2 - z1 + 2), CF(x2 + 0.9, h + 1.7, cz), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	-- exterior name band (faces east, towards the yard and the loop road)
	local band = deco(f, "EliteSignBand", V3(0.4, 2.4, 26), CF(x2 + 1.25, h - 2, cz), Color3.fromRGB(16, 16, 20))
	sign(band, Enum.NormalId.Right, "WCB ELITE PERFORMANCE", Color3.fromRGB(16, 16, 20), Color3.fromRGB(220, 230, 240))
	-- doorway through the hall's east wall: frame, header and two sliding glass leaves
	local d0, d1 = E.door[1], E.door[2]
	local dm = (d0 + d1) / 2
	for _, zz in ipairs({ d0 - 0.25, d1 + 0.25 }) do
		deco(f, "EliteDoorFrame", V3(2.6, 14, 0.5), CF(110, 7, zz), Color3.fromRGB(26, 26, 30), Enum.Material.Metal)
	end
	deco(f, "EliteDoorHeader", V3(2.6, 0.6, d1 - d0 + 1), CF(110, 14.2, dm), Color3.fromRGB(26, 26, 30), Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		-- named EliteGate: the client slides these open (locally) for an Elite-tier gym
		local leaf = deco(f, "EliteGate", V3(0.3, 13.4, (d1 - d0) / 2), CF(110, 7.1, dm + s * (d1 - d0) / 4), Color3.fromRGB(170, 200, 220), Enum.Material.Glass, { Transparency = 0.45, CastShadow = false })
		leaf:SetAttribute("Side", s)
	end
	-- (between the door header and the RECOVERY AREA zone sign above it)
	local head = deco(f, "EliteDoorSign", V3(0.3, 0.8, 12), CF(108.75, 14.95, dm), Color3.fromRGB(16, 16, 20))
	sign(head, Enum.NormalId.Left, "ELITE PERFORMANCE WING", Color3.fromRGB(16, 16, 20), Color3.fromRGB(150, 220, 255))
	-- ceiling light rig (off for everyone; the client switches it on for an unlocked wing)
	for _, x in ipairs({ 121, 143 }) do
		for _, zz in ipairs({ 38, 58 }) do
			local fix = deco(f, "EliteLightPanel", V3(6, 0.25, 2), CF(x, h - 0.2, zz), Color3.fromRGB(235, 240, 250), Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
			local l = Instance.new("SpotLight")
			l.Name = "EliteLight"
			l.Face = Enum.NormalId.Bottom
			l.Angle = 125
			l.Range = 40
			l.Brightness = 2.3
			l.Color = Color3.fromRGB(228, 238, 255)
			l.Shadows = false
			l.Enabled = false
			l.Parent = fix
		end
	end
	return f
end

-- the Champion's Lounge structure (MapBuilder.Mezzanine). Parts with the LoungeTrim attribute are the
-- chrome a World Champion's client turns gold; the LoungeGate leaves and the LoungeGateBlock above
-- them are what that client swings open / lets its character through
local function buildMezzanine(gym)
	local Z = MapBuilder.Mezzanine
	local f = Instance.new("Folder")
	f.Name = "Mezzanine"
	f.Parent = gym
	local x1, x2, z1, z2, y = Z.x1, Z.x2, Z.z1, Z.z2, Z.y
	local floorY = 0.4 -- the hall floor's top
	local steel = Color3.fromRGB(40, 40, 46)
	local chrome = Color3.fromRGB(215, 218, 225)
	local glassC = Color3.fromRGB(200, 225, 240)
	local hidden = { Transparency = 1, CastShadow = false }
	local loose = { CanCollide = false, CanQuery = false, CanTouch = false }
	local function trim(p)
		p:SetAttribute("LoungeTrim", true)
		return p
	end
	local function rod(name, a, b, d, color)
		local dir = b - a
		local up = math.abs(dir.Unit.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
		local p = deco(f, name, V3(dir.Magnitude, d, d), CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Metal, loose)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- a glass balustrade standing on the deck between two points (pane, chrome cap and shoe, posts at
	-- most ~6 studs apart); the pane collides, so nobody walks off the edge
	local function balustrade(a, b, h)
		local mid, len = (a + b) / 2, (b - a).Magnitude
		local cf = CFrame.lookAt(mid + V3(0, h / 2, 0), mid + V3(0, h / 2, 0) + (b - a).Unit:Cross(Vector3.yAxis))
		deco(f, "MezzGlass", V3(len, h, 0.12), cf, glassC, Enum.Material.Glass, { Transparency = 0.72, CastShadow = false })
		trim(deco(f, "MezzRailTop", V3(len, 0.18, 0.22), cf * CF(0, h / 2 + 0.09, 0), chrome, Enum.Material.Metal, loose))
		trim(deco(f, "MezzRailShoe", V3(len, 0.25, 0.26), cf * CF(0, -h / 2 + 0.125, 0), chrome, Enum.Material.Metal, loose))
		local n = math.max(1, math.ceil(len / 6))
		for k = 0, n do
			local x = math.clamp(-len / 2 + len * k / n, -len / 2 + 0.1, len / 2 - 0.1)
			deco(f, "MezzRailPost", V3(0.2, h, 0.2), cf * CF(x, 0, 0), steel, Enum.Material.Metal, loose)
		end
	end
	local cx = (x1 + x2) / 2
	local sx, sw, foot, n, d = Z.stairX, Z.stairW, Z.foot, Z.risers, Z.going
	local r = (y - floorY) / n
	local stairTop = foot + (n - 1) * d -- the landing starts here
	local landingEnd = stairTop + 4
	local gz = foot - 0.6 -- the gate's plane, in front of the first riser
	-- the deck: a 0.6 slab whose south end meets the hall wall's inner face (z 79)
	deco(f, "MezzDeck", V3(x2 - x1, 0.6, z2 - 0.02 - z1), CF(cx, y - 0.3, (z1 + z2 - 0.02) / 2), Color3.fromRGB(52, 52, 58), Enum.Material.Rubber)
	-- steel edge beams (fascias) on the faces seen from the lobby, a chrome band under each; on the
	-- west edge the stair and the landing take their place
	for _, seg in ipairs({ { z1, foot }, { landingEnd, z2 } }) do
		local len = seg[2] - seg[1]
		deco(f, "MezzFascia", V3(0.3, 1.1, len), CF(x1 - 0.15, y - 0.55, seg[1] + len / 2), steel, Enum.Material.Metal)
		trim(deco(f, "MezzFasciaBand", V3(0.34, 0.16, len), CF(x1 - 0.15, y - 1.18, seg[1] + len / 2), chrome, Enum.Material.Metal, loose))
	end
	deco(f, "MezzFascia", V3(x2 - x1 + 0.6, 1.1, 0.3), CF(cx, y - 0.55, z1 - 0.15), steel, Enum.Material.Metal)
	trim(deco(f, "MezzFasciaBand", V3(x2 - x1 + 0.64, 0.16, 0.34), CF(cx, y - 1.18, z1 - 0.15), chrome, Enum.Material.Metal, loose))
	deco(f, "MezzFascia", V3(0.3, 1.1, z2 - z1), CF(x2 + 0.15, y - 0.55, (z1 + z2) / 2), steel, Enum.Material.Metal)
	trim(deco(f, "MezzFasciaBand", V3(0.34, 0.16, z2 - z1 - 0.02), CF(x2 + 0.15, y - 1.18, (z1 + z2) / 2 + 0.01), chrome, Enum.Material.Metal, loose))
	-- columns at the corners and mid east edge (base, shaft, cap stacked, clear of the fascias; the
	-- east ones clear the vending machines, which end at x 45.3); the stair wall carries the west edge,
	-- and south of the landing the hall wall does (no south-west column: it stood in front of the
	-- welcome sign as seen from the spawn)
	for _, c in ipairs({ { x1 + 0.6, z1 + 0.6 }, { x2 - 0.6, z1 + 0.6 }, { x2 - 0.6, 60 }, { x2 - 0.6, z2 - 1.4 } }) do
		deco(f, "MezzColumnBase", V3(1.1, 0.3, 1.1), CF(c[1], floorY + 0.15, c[2]), steel, Enum.Material.Metal, loose)
		deco(f, "MezzColumn", V3(0.8, y - 0.9 - floorY - 0.3, 0.8), CF(c[1], (y - 0.9 + floorY + 0.3) / 2, c[2]), steel, Enum.Material.Metal)
		trim(deco(f, "MezzColumnCap", V3(1.0, 0.3, 1.0), CF(c[1], y - 0.75, c[2]), chrome, Enum.Material.Metal, loose))
	end
	-- downlights under the deck: the champions wall, the reception and the vending corner stay lit
	for _, p in ipairs({ V3(27, y - 0.64, 48), V3(40, y - 0.64, 48), V3(28, y - 0.64, 66), V3(41, y - 0.64, 70) }) do
		local dl = deco(f, "MezzDownlight", V3(1.2, 0.08, 1.2), CF(p), Color3.fromRGB(255, 240, 215), Enum.Material.Neon, { CanCollide = false, CanQuery = false, CastShadow = false })
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 236, 205)
		l.Range = 16
		l.Brightness = 0.9
		l.Shadows = false
		l.Parent = dl
	end

	-- the stair (x sx +- sw/2) climbs along a wall under the deck edge, from the gate to the end of
	-- the landing (the wall's north end is the gate's east jamb)
	deco(f, "StairWall", V3(0.3, y - 0.6 - floorY, landingEnd - gz + 0.15), CF(x1 + 0.15, (y - 0.6 + floorY) / 2, (gz - 0.15 + landingEnd) / 2), DIVIDER, Enum.Material.Brick)
	-- what you walk on: one invisible wedge whose slope runs through the middle of every tread, so a
	-- foot is never more than half a riser off the visible step (the steps themselves do not collide)
	local run = n * d
	deco(f, "StairRamp", V3(sw, y - floorY, run), CF(sx, (y + floorY) / 2, foot - d / 2 + run / 2), steel, nil, { Class = "WedgePart", Transparency = 1, CastShadow = false })
	for i = 1, n - 1 do
		local top = floorY + i * r
		deco(f, "StairStep", V3(sw - 0.1, top - floorY, d), CF(sx, (top + floorY) / 2, foot + (i - 0.5) * d), Color3.fromRGB(58, 58, 64), Enum.Material.Concrete, loose)
		trim(deco(f, "StairNosing", V3(sw - 0.1, 0.06, 0.14), CF(sx, top + 0.03, foot + (i - 1) * d + 0.07), chrome, Enum.Material.Metal, loose))
	end
	deco(f, "StairLanding", V3(sw, 0.6, landingEnd - stairTop), CF(sx, y - 0.3, (stairTop + landingEnd) / 2), Color3.fromRGB(52, 52, 58), Enum.Material.Rubber)
	deco(f, "LandingPost", V3(0.5, y - 0.6 - floorY, 0.5), CF(sx - sw / 2 + 0.3, (y - 0.6 + floorY) / 2, landingEnd - 0.3), steel, Enum.Material.Metal)
	-- the open (west) side: posts on the treads, a chrome handrail and a mid rail parallel to the
	-- nosings, meeting the landing's glass at its height
	local rx = sx - sw / 2 + 0.12
	local function railAt(z, h)
		return V3(rx, floorY + r + (z - foot) * r / d + h, z)
	end
	trim(rod("StairHandrail", railAt(foot, 2.7), railAt(stairTop, 2.7), 0.16, chrome))
	rod("StairMidRail", railAt(foot, 1.35), railAt(stairTop, 1.35), 0.1, steel)
	for _, j in ipairs({ 1, 5, 9, 13, n - 1 }) do
		local zc = foot + (j - 0.5) * d
		rod("StairPost", V3(rx, floorY + j * r, zc), railAt(zc, 2.7), 0.12, steel)
	end
	-- the landing's open sides, then the deck's: the west edge (open where the landing arrives),
	-- north and east (the side rails start behind the north one: no doubled corner)
	balustrade(V3(sx - sw / 2 + 0.15, y, stairTop), V3(sx - sw / 2 + 0.15, y, landingEnd - 0.3), 2.6)
	balustrade(V3(sx - sw / 2, y, landingEnd - 0.15), V3(x1, y, landingEnd - 0.15), 2.6)
	balustrade(V3(x1 + 0.15, y, z1 + 0.35), V3(x1 + 0.15, y, stairTop), 2.6)
	balustrade(V3(x1 + 0.15, y, landingEnd), V3(x1 + 0.15, y, z2), 2.6)
	balustrade(V3(x1, y, z1 + 0.15), V3(x2, y, z1 + 0.15), 2.6)
	balustrade(V3(x2 - 0.15, y, z1 + 0.35), V3(x2 - 0.15, y, z2), 2.6)

	-- the gate at the stair foot: two glass leaves under a lit header, hinged on the west post and on
	-- the stair wall. Closed for everyone; a World Champion's client swings them open and lets its
	-- character through the block above them (the leaves stop a jump from the floor, the block one
	-- from the top of the water cooler in front)
	local gx0, gx1 = sx - sw / 2 - 0.3, x1
	deco(f, "GatePost", V3(0.3, 9.2 - floorY, 0.3), CF(gx0 + 0.15, (9.2 + floorY) / 2, gz), steel, Enum.Material.Metal)
	local header = deco(f, "GateHeader", V3(gx1 - gx0, 1.0, 0.3), CF((gx0 + gx1) / 2, 8.7, gz), steel, Enum.Material.Metal)
	sign(header, Enum.NormalId.Front, "CHAMPION'S LOUNGE\nWORLD CHAMPIONS ONLY", steel, Color3.fromRGB(255, 200, 40))
	local leafW = (gx1 - gx0 - 0.3) / 2 - 0.02
	for _, s in ipairs({ -1, 1 }) do
		local leaf = deco(f, "LoungeGate", V3(leafW, 8.2 - floorY - 0.05, 0.16), CF((gx0 + 0.3 + gx1) / 2 + s * (leafW / 2 + 0.01), (8.2 + floorY + 0.05) / 2, gz), glassC, Enum.Material.Glass, { Transparency = 0.45, CastShadow = false })
		leaf:SetAttribute("Side", s)
	end
	-- invisible guards seal the lounge to the hall's ceiling, so no jump gets a character in from the
	-- lobby, whatever it stands on (the water cooler's jug, a prop, another player's head): over the
	-- gate (the block above the leaves), along the stair's open side and the landing's south rail, and
	-- round the deck's open edges from the outer face of the fascias to the inner face of the glass
	-- (no ledge left outside the glass to stand on). Fully transparent, so they never pull the camera in
	local roof = gym:FindFirstChild("Roof")
	local ceil = roof and roof:IsA("BasePart") and roof.Position.Y - roof.Size.Y / 2 or 30
	local function guard(name, xa, xb, ya, yb, za, zb)
		return deco(f, name, V3(xb - xa, yb - ya, zb - za), CF((xa + xb) / 2, (ya + yb) / 2, (za + zb) / 2), Color3.new(), nil, hidden)
	end
	local glassIn = 0.21 -- the glass panes' inner faces stand this far in from the deck's edges
	guard("LoungeGateBlock", gx0, x1 + glassIn, 9.2, ceil, gz - 0.15, gz + 0.15)
	local sideX = sx - sw / 2 - 0.4
	guard("LoungeGuard", sideX - 0.05, sideX + 0.05, floorY, ceil, gz, landingEnd)
	guard("LoungeGuard", sideX - 0.05, x1, y, ceil, landingEnd - glassIn, landingEnd)
	guard("LoungeGuard", x1 - 0.3, x2 + 0.3, y, ceil, z1 - 0.3, z1 + glassIn)
	guard("LoungeGuard", x1 - 0.3, x1 + glassIn, y, ceil, z1, gz - 0.15)
	guard("LoungeGuard", x1 - 0.3, x1 + glassIn, y, ceil, landingEnd, z2 - 0.02)
	guard("LoungeGuard", x2 - glassIn, x2 + 0.3, y, ceil, z1, z2 - 0.02)
	-- where an edge guard runs into a south-wall window, the opening is a recess behind the deck's end
	-- (the glass stands in the middle of the 2-stud wall, 0.9 behind its inner face, over a sill that
	-- runs on both sides of the guard): a plug carries the guard back to the glass, so nobody slides
	-- round its end along the sill from the lobby corner
	for _, a in ipairs(MapBuilder.Windows.S) do
		for _, gx in ipairs({ { x1 - 0.3, x1 + glassIn }, { x2 - glassIn, x2 + 0.3 } }) do
			if a - WIN_W / 2 < gx[2] and a + WIN_W / 2 > gx[1] then
				guard("LoungeGuard", gx[1], gx[2], WIN_Y0, WIN_Y1, z2 - 0.02, z2 + 0.89)
			end
		end
	end
	-- (between the stair and the deck, inside the gate: above the glass, as before)
	guard("LoungeGuard", x1 + 0.1, x1 + 0.2, y + 2.8, ceil, gz + 0.15, stairTop)
	return f
end

-- invisible boxes tagged LightZone: the client grades the picture for the zone the camera is in
local function lightZone(parent, name, size, cf, profile)
	local p = deco(parent, name, size, cf, Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	p:SetAttribute("Profile", profile)
	CollectionService:AddTag(p, "LightZone")
	return p
end

local function buildAction(gym, name, text, area, pos, attrs, labelColor)
	local p = deco(gym, name, V3(1, 1, 1), CF(pos + V3(0, 3.2, 0)), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	prompt(p, text, area, attrs)
	label(p, text, labelColor or Color3.fromRGB(120, 220, 255), 4, 60)
	return p
end

function MapBuilder.BuildGym()
	local old = workspace:FindFirstChild("Gym")
	if old then
		old:Destroy()
	end
	local gym = Instance.new("Folder")
	gym.Name = "Gym"
	gym.Parent = workspace
	local X1, X2, Z1, Z2, H = -110, 110, -80, 80, 30

	-- ground, floors, walls, roof
	-- ground with a hole where the pool basin sits (x -28..28, z -123..-101)
	local grass = Color3.fromRGB(86, 128, 70)
	local GX1, GX2, GZ1, GZ2 = -380, 380, -410, 350
	local HX1, HX2, HZ1, HZ2 = -28, 28, -123, -101
	local function ground(x1, x2, z1, z2)
		deco(gym, "Ground", V3(x2 - x1, 2, z2 - z1), CF((x1 + x2) / 2, -1, (z1 + z2) / 2), grass, Enum.Material.Grass)
	end
	ground(GX1, GX2, HZ2, GZ2)
	ground(GX1, GX2, GZ1, HZ1)
	ground(GX1, HX1, HZ1, HZ2)
	ground(HX2, GX2, HZ1, HZ2)
	deco(gym, "Floor", V3(X2 - X1, 0.4, Z2 - Z1), CF(0, 0.2, 0), WOOD, Enum.Material.WoodPlanks)
	local function openings(list, door)
		local out = {}
		if door then
			table.insert(out, door)
		end
		for _, a in ipairs(list) do
			table.insert(out, { a - WIN_W / 2, a + WIN_W / 2, WIN_Y0, WIN_Y1 })
		end
		return out
	end
	wallWithOpenings(gym, "X", Z1, X1 - 1, X2 + 1, H, openings(MapBuilder.Windows.N, { -8, 8, 0, 14 }), WALL) -- north (to pool)
	wallWithOpenings(gym, "X", Z2, X1 - 1, X2 + 1, H, openings(MapBuilder.Windows.S, { -10, 10, 0, 14 }), WALL) -- south (main entrance)
	wallWithOpenings(gym, "Z", X1, Z1 + 1, Z2 - 1, H, openings(MapBuilder.Windows.W), WALL)
	-- east wall: windows plus the doorway into the Elite Performance Wing annex
	local wingDoor = MapBuilder.EliteWing.door
	wallWithOpenings(gym, "Z", X2, Z1 + 1, Z2 - 1, H, openings(MapBuilder.Windows.E, { wingDoor[1], wingDoor[2], 0, 14 }), WALL)
	for _, a in ipairs(MapBuilder.Windows.N) do
		windowFrame(gym, "X", Z1, a)
	end
	for _, a in ipairs(MapBuilder.Windows.S) do
		windowFrame(gym, "X", Z2, a)
	end
	for _, a in ipairs(MapBuilder.Windows.W) do
		windowFrame(gym, "Z", X1, a)
	end
	for _, a in ipairs(MapBuilder.Windows.E) do
		windowFrame(gym, "Z", X2, a)
	end
	deco(gym, "Roof", V3(X2 - X1 + 4, 2, Z2 - Z1 + 4), CF(0, H + 1, 0), Color3.fromRGB(35, 35, 38), Enum.Material.DiamondPlate)
	-- red trim band around the outside of the building
	deco(gym, "TrimN", V3(X2 - X1 + 4, 1.5, 0.4), CF(0, H - 2, Z1 - 1.2), TRIM)
	deco(gym, "TrimS", V3(X2 - X1 + 4, 1.5, 0.4), CF(0, H - 2, Z2 + 1.2), TRIM)
	deco(gym, "TrimW", V3(0.4, 1.5, Z2 - Z1 + 4), CF(X1 - 1.2, H - 2, 0), TRIM)
	deco(gym, "TrimE", V3(0.4, 1.5, Z2 - Z1 + 4), CF(X2 + 1.2, H - 2, 0), TRIM)
	-- zone floors and dividers
	floorZone(gym, "BoxingFloor", -45, -70, 45, 4, Color3.fromRGB(46, 48, 56))
	floorZone(gym, "WeightFloor", -108, -78, -50, 18, Color3.fromRGB(30, 30, 32))
	floorZone(gym, "CardioFloor", 50, -78, 108, 18, Color3.fromRGB(35, 50, 70))
	floorZone(gym, "RecoveryFloor", 50, 22, 108, 78, Color3.fromRGB(210, 220, 225), Enum.Material.Marble)
	floorZone(gym, "ServicesFloor", -108, 22, -50, 78, Color3.fromRGB(95, 70, 50), Enum.Material.Wood)
	deco(gym, "Divider", V3(2, 9, 60), CF(-50, 4.5, -48), DIVIDER, Enum.Material.Brick)
	deco(gym, "Divider", V3(2, 9, 60), CF(50, 4.5, -48), DIVIDER, Enum.Material.Brick)
	deco(gym, "Divider", V3(40, 9, 2), CF(-88, 4.5, 20), DIVIDER, Enum.Material.Brick)
	deco(gym, "Divider", V3(40, 9, 2), CF(88, 4.5, 20), DIVIDER, Enum.Material.Brick)
	for _, d in ipairs({ { V3(2.3, 0.4, 60.3), CF(-50, 9.2, -48) }, { V3(2.3, 0.4, 60.3), CF(50, 9.2, -48) }, { V3(40.3, 0.4, 2.3), CF(-88, 9.2, 20) }, { V3(40.3, 0.4, 2.3), CF(88, 9.2, 20) } }) do
		deco(gym, "DividerCap", d[1], d[2], Color3.fromRGB(40, 40, 46), Enum.Material.Concrete)
	end
	zoneSign(gym, "BOXING AREA", CF(0, 20, -78.5), Color3.fromRGB(255, 200, 40))
	zoneSign(gym, "WEIGHT ROOM", CF(-108.5, 18, -30) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 120, 60))
	zoneSign(gym, "CARDIO ROOM", CF(108.5, 18, -30) * CFrame.Angles(0, math.rad(-90), 0), Color3.fromRGB(90, 190, 255))
	zoneSign(gym, "RECOVERY AREA", CF(108.5, 18, 50) * CFrame.Angles(0, math.rad(-90), 0), Color3.fromRGB(140, 240, 220))
	zoneSign(gym, "BARBER - LOCKERS - BUNKS", CF(-108.5, 18, 50) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(240, 200, 140))
	local banner = deco(gym, "Banner", V3(70, 7, 0.6), CF(0, 21, 78.6), Color3.fromRGB(18, 18, 22))
	sign(banner, Enum.NormalId.Front, "WORLD CLASS BOXING GYM", Color3.fromRGB(18, 18, 22), Color3.fromRGB(255, 200, 40))
	local motto = deco(gym, "Motto", V3(70, 4, 0.6), CF(0, 25, -78.6), Color3.fromRGB(18, 18, 22))
	sign(motto, Enum.NormalId.Front, "CHAMPIONS ARE MADE WHEN NOBODY IS WATCHING", Color3.fromRGB(18, 18, 22), TRIM)

	-- spawn & lobby
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "GymSpawn"
	spawn.Anchored = true
	spawn.Size = V3(10, 1, 10)
	spawn.CFrame = CF(0, 0.5, 60)
	spawn.Color = TRIM
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = gym
	local board = deco(gym, "CareerBoard", V3(16, 9, 1), CF(0, 5.5, 32), Color3.fromRGB(20, 20, 26))
	sign(board, Enum.NormalId.Back, "FIGHT BOARD\nCareer - Offers - Rankings", Color3.fromRGB(20, 20, 26), Color3.new(1, 1, 1))
	sign(board, Enum.NormalId.Front, "FIGHT BOARD", Color3.fromRGB(20, 20, 26), Color3.new(1, 1, 1))
	buildAction(gym, "BoardPrompt", "Open Career Hub", "Fight Board", V3(0, 0, 35), { Action = "CareerHub" }, Color3.fromRGB(255, 200, 40))
	local case = deco(gym, "TrophyCase", V3(18, 3, 4), CF(-24, 1.5, 72), Color3.fromRGB(30, 30, 30), Enum.Material.Marble)
	label(case, "TROPHY CASE", Color3.fromRGB(255, 215, 0), 3)
	deco(gym, "TrophyGlass", V3(18, 5, 4), CF(-24, 5.5, 72), Color3.fromRGB(200, 230, 255), Enum.Material.Glass, { Transparency = 0.7 })

	-- station anchors (equipment visuals are drawn client-side by level)
	for _, def in ipairs(MapBuilder.StationDefs) do
		buildStationAnchors(gym, def)
	end
	-- FLEX in front of the shadow-boxing mirror (CONTRACTS s.15 "Flex mirror"; ClientMain dispatches
	-- Action "Flex"): walk up, press F, and the live mirror (GymMirror) shows the pose. Its own key
	-- and a UI offset so it sits under the station's E prompt instead of fighting it; no label, the
	-- station's floating name is already there. FaceAt = the glass, so the client turns you to it.
	for _, def in ipairs(MapBuilder.StationDefs) do
		if def.id == "mirror" then
			local fp = deco(gym, "FlexPrompt", V3(1, 1, 1), CF(def.use.X, MapBuilder.FloorY + 3.2, def.use.Z + 1), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
			local fpp = prompt(fp, "Flex in the mirror", "Mirror", { Action = "Flex", FaceAt = V3(def.pos.X, MapBuilder.FloorY, def.pos.Z) })
			fpp.KeyboardKeyCode = Enum.KeyCode.F
			fpp.GamepadKeyCode = Enum.KeyCode.ButtonY
			fpp.UIOffset = Vector2.new(0, 72)
		end
	end
	-- boxing area: the gym sparring ring
	local rc = MapBuilder.RingCenter
	buildRing(gym, rc, 11, 2.5, { TRIM, Color3.fromRGB(30, 60, 200) })
	buildAction(gym, "SparPrompt", "Spar (Light / Medium / Hard)", "Sparring Ring", rc + V3(0, 0, 14), { Activity = "Sparring", Station = "ring" }, Color3.fromRGB(255, 220, 90))
	local ringSign = deco(gym, "RingSign", V3(20, 3, 0.5), CF(rc + V3(0, 13, -13)), Color3.fromRGB(18, 18, 22))
	sign(ringSign, Enum.NormalId.Back, "SPARRING RING", Color3.fromRGB(18, 18, 22), Color3.new(1, 1, 1))
	-- members' hanging bags along the boxing area (members and other players hit these; the
	-- client swings them)
	for i, p in ipairs(MapBuilder.MemberBags) do
		buildMemberBag(gym, p.X, p.Z, i)
	end
	-- the Elite Performance Wing shell east of the Recovery Area
	local okWing, wingErr = pcall(buildEliteWing, gym)
	if not okWing then
		warn("[Boxer] elite wing failed: " .. tostring(wingErr))
	end
	-- the Champion's Lounge mezzanine over the east lobby
	local okMezz, mezzErr = pcall(buildMezzanine, gym)
	if not okMezz then
		warn("[Boxer] lounge mezzanine failed: " .. tostring(mezzErr))
	end
	-- colour-grade zones the client reads (Ambience): the warm main hall and the cool elite wing
	local W = MapBuilder.EliteWing
	lightZone(gym, "LightZoneGym", V3(X2 - X1, H, Z2 - Z1), CF(0, H / 2, 0), "GymWarm")
	lightZone(gym, "LightZoneElite", V3(W.x2 - W.x1, W.h, W.z2 - W.z1), CF((W.x1 + W.x2) / 2, W.h / 2, (W.z1 + W.z2) / 2), "GymElite")

	-- services: barber, lockers, nutrition bar, bunks, water coolers
	local barberChair = deco(gym, "BarberChair", V3(3, 3, 3), CF(-95, 1.5, 38), Color3.fromRGB(160, 20, 30), Enum.Material.Leather)
	deco(gym, "BarberBase", V3(1.2, 1.4, 1.2), CF(-95, 0.7, 38), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
	barberChair.CFrame = CF(-95, 2, 38)
	deco(gym, "BarberMirror", V3(10, 6, 0.3), CF(-95, 6, 28.2), Color3.fromRGB(210, 230, 245), Enum.Material.Glass, { Reflectance = 0.5 })
	local poleModel = Instance.new("Model")
	poleModel.Name = "BarberPole"
	poleModel.Parent = gym
	local pole = deco(poleModel, "Hub", V3(6, 1.2, 1.2), CF(-103, 7, 28.5) * CFrame.Angles(0, 0, math.rad(90)), Color3.new(1, 1, 1))
	pole.Shape = Enum.PartType.Cylinder
	for i = 0, 2 do
		deco(poleModel, "Blade", V3(0.3, 1.25, 1.25), CF(-103, 5 + i * 2, 28.5) * CFrame.Angles(0, 0, math.rad(60)), i % 2 == 0 and TRIM or Color3.fromRGB(30, 60, 200), nil, { CanCollide = false })
	end
	deco(poleModel, "PoleCap", V3(1.5, 0.5, 1.5), CF(-103, 10.2, 28.5), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	deco(poleModel, "PoleCap", V3(1.5, 0.5, 1.5), CF(-103, 3.8, 28.5), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	poleModel.PrimaryPart = pole
	poleModel:SetAttribute("Speed", 2.2)
	CollectionService:AddTag(poleModel, "SpinFan")
	buildAction(gym, "BarberPrompt", "Barber Shop", "Hair & beard", V3(-95, 0, 42), { Action = "Barber" }, Color3.fromRGB(240, 200, 140))
	for i = 0, 7 do
		local l = deco(gym, "Locker", V3(3, 8, 2), CF(-80 + i * 3.1, 4, 25), i % 2 == 0 and Color3.fromRGB(40, 70, 150) or Color3.fromRGB(35, 60, 130), Enum.Material.DiamondPlate)
		deco(gym, "LockerVent", V3(2, 0.3, 0.1), CF(-80 + i * 3.1, 6.5, 26.05), Color3.fromRGB(20, 20, 25), nil, { CanCollide = false })
		l.Name = "Locker"
	end
	deco(gym, "LockerBench", V3(20, 1.4, 2.5), CF(-69, 0.9, 32), Color3.fromRGB(130, 95, 60), Enum.Material.Wood)
	buildAction(gym, "LockerPrompt", "Locker Room", "Gear & attire", V3(-69, 0, 35), { Action = "Locker" }, Color3.fromRGB(240, 200, 140))
	deco(gym, "BarCounter", V3(20, 4, 4), CF(-70, 2, 70), Color3.fromRGB(70, 50, 40), Enum.Material.Wood)
	deco(gym, "BarTop", V3(20.6, 0.4, 4.6), CF(-70, 4.2, 70), Color3.fromRGB(220, 220, 225), Enum.Material.Marble)
	for i = 0, 3 do
		local stool = deco(gym, "Stool", V3(1.6, 3, 1.6), CF(-77 + i * 4.5, 1.5, 65.5), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
		stool.Shape = Enum.PartType.Cylinder
		stool.CFrame = CF(-77 + i * 4.5, 1.5, 65.5) * CFrame.Angles(0, 0, math.rad(90))
	end
	local menu = deco(gym, "Menu", V3(14, 6, 0.3), CF(-70, 9, 77.8), Color3.fromRGB(20, 25, 20))
	sign(menu, Enum.NormalId.Front, "NUTRITION BAR\nMeals - Shakes - Hydration", Color3.fromRGB(20, 25, 20), Color3.fromRGB(140, 240, 140))
	buildAction(gym, "NutritionPrompt", "Nutrition Bar", "Eat & drink", V3(-70, 0, 64), { Action = "Nutrition" }, Color3.fromRGB(140, 240, 140))
	for i = 0, 2 do
		local x = -100 + i * 7
		deco(gym, "BunkFrame", V3(4, 7, 9), CF(x, 3.5, 66), Color3.fromRGB(70, 70, 80), Enum.Material.Metal, { Transparency = 0.6 })
		deco(gym, "Mattress", V3(3.6, 0.8, 8.4), CF(x, 1.4, 66), Color3.fromRGB(230, 230, 240), Enum.Material.Fabric)
		deco(gym, "MattressTop", V3(3.6, 0.8, 8.4), CF(x, 5, 66), Color3.fromRGB(230, 230, 240), Enum.Material.Fabric)
		deco(gym, "Pillow", V3(2.6, 0.5, 1.6), CF(x, 2, 70), Color3.fromRGB(250, 250, 255), Enum.Material.Fabric)
	end
	buildAction(gym, "SleepPrompt", "Sleep (End Day)", "Bunk Room", V3(-93, 0, 58), { Action = "Sleep" }, Color3.fromRGB(170, 170, 255))
	-- { cooler, side you drink from }: the lobby one is served from its north side, away from the
	-- lounge stair whose gate stands 3 studs south of it
	for _, c in ipairs({ { V3(18, 0, 40), V3(0, 0, -2.5) }, { V3(104, 0, 4), V3(0, 0, 2.5) }, { V3(-104, 0, -4), V3(0, 0, 2.5) } }) do
		local pos = c[1]
		deco(gym, "Cooler", V3(2, 4, 2), CF(pos + V3(0, 2, 0)), Color3.fromRGB(230, 230, 235))
		deco(gym, "Jug", V3(1.6, 2, 1.6), CF(pos + V3(0, 5, 0)), Color3.fromRGB(120, 190, 255), Enum.Material.Glass, { Transparency = 0.3 })
		buildAction(gym, "WaterPrompt", "Drink Water", "Water cooler", pos + c[2], { Action = "Water" }, Color3.fromRGB(120, 190, 255))
	end

	-- pool annex (north) with real water
	local PZ = -112
	deco(gym, "PoolWallW", V3(2, 22, 70), CF(-45, 11, PZ), Color3.fromRGB(200, 215, 230), Enum.Material.SmoothPlastic)
	deco(gym, "PoolWallE", V3(2, 22, 70), CF(45, 11, PZ), Color3.fromRGB(200, 215, 230), Enum.Material.SmoothPlastic)
	deco(gym, "PoolWallN", V3(92, 22, 2), CF(0, 11, PZ - 35), Color3.fromRGB(200, 215, 230), Enum.Material.SmoothPlastic)
	deco(gym, "PoolRoof", V3(92, 1, 72), CF(0, 22.5, PZ), Color3.fromRGB(180, 210, 240), Enum.Material.Glass, { Transparency = 0.4 })
	deco(gym, "Corridor", V3(16, 0.4, 12), CF(0, 0.2, -86), WOOD, Enum.Material.WoodPlanks)
	-- carve the basin: deck pieces around a 56 x 22 hole, water fills it
	local PW, PL = 56, 22
	deco(gym, "PoolFloor", V3(PW + 2, 1, PL + 2), CF(0, -7, PZ), Color3.fromRGB(80, 170, 220), Enum.Material.SmoothPlastic)
	-- basin walls sit 0.03 proud of the ground/deck edges so the pool sides never z-fight
	deco(gym, "BasinN", V3(PW + 2, 7, 1), CF(0, -3.5, PZ - PL / 2 - 0.47), Color3.fromRGB(90, 180, 225), Enum.Material.SmoothPlastic)
	deco(gym, "BasinS", V3(PW + 2, 7, 1), CF(0, -3.5, PZ + PL / 2 + 0.47), Color3.fromRGB(90, 180, 225), Enum.Material.SmoothPlastic)
	deco(gym, "BasinW", V3(1, 7, PL - 0.06), CF(-PW / 2 - 0.47, -3.5, PZ), Color3.fromRGB(90, 180, 225), Enum.Material.SmoothPlastic)
	deco(gym, "BasinE", V3(1, 7, PL - 0.06), CF(PW / 2 + 0.47, -3.5, PZ), Color3.fromRGB(90, 180, 225), Enum.Material.SmoothPlastic)
	-- deck around the basin
	deco(gym, "DeckN", V3(90, 1, (70 - PL) / 2), CF(0, 0, PZ - PL / 2 - (70 - PL) / 4), Color3.fromRGB(225, 230, 235), Enum.Material.Marble)
	deco(gym, "DeckS", V3(90, 1, (70 - PL) / 2), CF(0, 0, PZ + PL / 2 + (70 - PL) / 4), Color3.fromRGB(225, 230, 235), Enum.Material.Marble)
	deco(gym, "DeckW", V3((90 - PW) / 2, 1, PL), CF(-PW / 2 - (90 - PW) / 4, 0, PZ), Color3.fromRGB(225, 230, 235), Enum.Material.Marble)
	deco(gym, "DeckE", V3((90 - PW) / 2, 1, PL), CF(PW / 2 + (90 - PW) / 4, 0, PZ), Color3.fromRGB(225, 230, 235), Enum.Material.Marble)
	pcall(function()
		workspace.Terrain:FillBlock(CF(0, -3.4, PZ), V3(PW, 6.8, PL), Enum.Material.Water)
	end)
	for i = -2, 2 do
		deco(gym, "LaneLine", V3(PW - 4, 0.1, 0.4), CF(0, -6.4, PZ + i * 4), Color3.fromRGB(20, 40, 120), nil, { CanCollide = false })
	end
	local ends = Instance.new("Folder")
	ends.Name = "PoolEnds"
	ends.Parent = gym
	deco(ends, "EndA", V3(1, 6, PL), CF(-PW / 2 + 1, -2, PZ), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	deco(ends, "EndB", V3(1, 6, PL), CF(PW / 2 - 1, -2, PZ), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	local poolSign = deco(gym, "PoolSign", V3(26, 4, 0.5), CF(0, 16, PZ - 34), Color3.fromRGB(20, 40, 80))
	sign(poolSign, Enum.NormalId.Front, "SWIMMING POOL", Color3.fromRGB(20, 40, 80), Color3.fromRGB(150, 220, 255))
	local poolStation = Instance.new("Model")
	poolStation.Name = "Station_pool"
	poolStation.Parent = gym
	local pb = deco(poolStation, "Base", V3(1, 1, 1), CF(-PW / 2 - 4, 1, PZ), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	pb:SetAttribute("Station", "pool")
	buildAction(poolStation, "PromptPart", "Swim Laps", "Swimming Pool", V3(-PW / 2 - 4, 0.5, PZ), { Activity = "Swimming", Station = "pool" }, Color3.fromRGB(150, 220, 255))
	for _, x in ipairs({ -20, 0, 20 }) do
		-- flush under the pool roof (its underside is y 22)
		lamp(gym, V3(x, 21.8, PZ), 40, 0.7, Color3.fromRGB(220, 240, 255))
	end

	-- outdoor roadwork loop with checkpoints
	local track = Instance.new("Folder")
	track.Name = "Track"
	track.Parent = gym
	local corners = { V3(-160, 0, 120), V3(160, 0, 120), V3(160, 0, -190), V3(-160, 0, -190) }
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude + 10
		deco(track, "Road", V3(10, 0.3, len), CFrame.lookAt(mid + V3(0, 0.15, 0), b + V3(0, 0.15, 0)), Color3.fromRGB(60, 60, 64), Enum.Material.Asphalt)
		deco(track, "RoadLine", V3(0.4, 0.32, len - 6), CFrame.lookAt(mid + V3(0, 0.16, 0), b + V3(0, 0.16, 0)), Color3.fromRGB(240, 220, 120), nil, { CanCollide = false })
	end
	deco(track, "EntrancePath", V3(10, 0.3, 36), CF(0, 0.15, 97), Color3.fromRGB(150, 140, 130), Enum.Material.Concrete)
	-- either side of the path, the doorway's width (x -10..10) between the hall floor (z 80) and the
	-- sidewalk (z 81.1) was bare ground: concrete it, flush with the path
	for _, x in ipairs({ -7.5, 7.5 }) do
		deco(track, "EntranceThreshold", V3(5, 0.3, 1.2), CF(x, 0.15, 80.6), Color3.fromRGB(150, 140, 130), Enum.Material.Concrete)
	end
	local cps = Instance.new("Folder")
	cps.Name = "TrackCheckpoints"
	cps.Parent = gym
	local cpPositions = {
		V3(12, 0, 120), V3(160, 0, 120), V3(160, 0, -35), V3(160, 0, -190),
		V3(0, 0, -190), V3(-160, 0, -190), V3(-160, 0, -35), V3(-160, 0, 120),
	}
	for i, pos in ipairs(cpPositions) do
		local cp = deco(cps, "CP" .. i, V3(10, 8, 1), CF(pos + V3(0, 4, 0)), Color3.fromRGB(255, 200, 40), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
		cp:SetAttribute("Index", i)
	end
	local trackStation = Instance.new("Model")
	trackStation.Name = "Station_track"
	trackStation.Parent = gym
	local tb = deco(trackStation, "Base", V3(1, 1, 1), CF(0, 1, 112), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	tb:SetAttribute("Station", "track")
	buildAction(trackStation, "PromptPart", "Start Roadwork", "Roadwork Route", V3(0, 0, 112), { Activity = "Roadwork", Station = "track" }, Color3.fromRGB(255, 200, 40))
	-- start/finish arch straddles the loop road (posts off the tarmac) over a chequered line
	local startArch = deco(track, "StartArch", V3(1.2, 1.2, 15.6), CF(12, 11, 120), TRIM)
	deco(track, "ArchPostL", V3(1, 11, 1), CF(12, 5.5, 112.8), Color3.fromRGB(30, 30, 30))
	deco(track, "ArchPostR", V3(1, 11, 1), CF(12, 5.5, 127.2), Color3.fromRGB(30, 30, 30))
	for row = 0, 1 do
		for k = 0, 9 do
			deco(track, "FinishLine", V3(1, 0.04, 1), CF(11.5 + row, 0.34, 115.5 + k), (row + k) % 2 == 0 and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(20, 20, 22), nil, { CanCollide = false, CanQuery = false })
		end
	end
	label(startArch, "ROADWORK START", Color3.fromRGB(255, 200, 40), 2, 120)
	-- scenery: trees along the loop (CityMap adds street lights and clears trees where the town is)
	local rng = Random.new(5)
	for _ = 1, 70 do
		local side = rng:NextInteger(1, 4)
		local t = rng:NextNumber(-1, 1)
		local pos
		if side == 1 then
			local x = t * 175
			if math.abs(x) < 14 then
				x = (x < 0 and -1 or 1) * (14 + math.abs(x))
			end
			pos = V3(x, 0, 133 + rng:NextNumber(0, 24))
		elseif side == 2 then
			pos = V3(180 + rng:NextNumber(0, 40), 0, -35 + t * 170)
		elseif side == 3 then
			pos = V3(t * 175, 0, -210 - rng:NextNumber(0, 40))
		else
			pos = V3(-180 - rng:NextNumber(0, 40), 0, -35 + t * 170)
		end
		local h = rng:NextNumber(8, 14)
		local trunk = deco(gym, "Trunk", V3(h, 1.4, 1.4), CF(pos + V3(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(95, 65, 40), Enum.Material.Wood)
		trunk.Shape = Enum.PartType.Cylinder
		local leaves = deco(gym, "Leaves", V3(1, 1, 1) * rng:NextNumber(7, 11), CF(pos + V3(0, h + 2, 0)), Color3.fromRGB(50 + rng:NextInteger(0, 30), 110 + rng:NextInteger(0, 40), 50), Enum.Material.Grass)
		leaves.Shape = Enum.PartType.Ball
	end

	-- the building's furniture, decor and light rig, then the town around it
	GymDecor.Build(gym)
	local ok, err = pcall(CityMap.Build, gym)
	if not ok then
		warn("[Boxer] city map failed: " .. tostring(err))
	end

	-- lighting tuned for Future lighting (build.py sets Lighting.Technology): the roof blocks
	-- the sun indoors so the gym's own lamps light it, daylight streams through the windows.
	-- Future lights in linear space, so Ambient is a real fill: (64, 60, 56) was ~4% grey and left
	-- every surface a lamp missed near black. A warm ~15% fill keeps shadows readable while the
	-- lamps, windows and CharacterLight still do the shaping (not flat). Soft shadows for the same
	-- reason. The client's Ambience sets the exposure per place (LightLevels) and the time of day.
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.8
	Lighting.Ambient = Color3.fromRGB(120, 112, 104)
	Lighting.OutdoorAmbient = Color3.fromRGB(132, 136, 146)
	Lighting.ExposureCompensation = 0
	Lighting.GeographicLatitude = 34
	pcall(function()
		Lighting.EnvironmentDiffuseScale = 1
		Lighting.EnvironmentSpecularScale = 0.5
		Lighting.ShadowSoftness = 0.4
	end)
	local function effect(class, name, props)
		local e = Lighting:FindFirstChild(name)
		if not e then
			e = Instance.new(class)
			e.Name = name
			e.Parent = Lighting
		end
		for k, v in pairs(props) do
			e[k] = v
		end
		return e
	end
	-- FightClient finds these by name and switches them off on fight nights
	-- a gentle global grade: the zone grades (Ambience) add the per-room look on top, so this one
	-- stays near neutral (stacked contrast crushed the shadows)
	effect("ColorCorrectionEffect", "GymGrade", { Brightness = 0.01, Contrast = 0.04, Saturation = 0.06, TintColor = Color3.fromRGB(255, 249, 242) })
	effect("BloomEffect", "GymBloom", { Intensity = 0.35, Size = 24, Threshold = 1.8 })
	effect("SunRaysEffect", "GymSunRays", { Intensity = 0.05, Spread = 0.6 })
	local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atm.Density = 0.24
	atm.Offset = 0.12
	atm.Color = Color3.fromRGB(212, 204, 190)
	atm.Decay = Color3.fromRGB(122, 130, 144)
	atm.Glare = 0.15
	atm.Haze = 1.0
	atm.Parent = Lighting
	pcall(function()
		local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Cover = 0.5
		clouds.Density = 0.55
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = workspace.Terrain
	end)
	return gym
end

return MapBuilder
