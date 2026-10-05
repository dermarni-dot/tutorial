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
			l.Angle = 120
			l.Range = 30
			l.Brightness = 1.6
			l.Color = Color3.fromRGB(228, 238, 255)
			l.Shadows = false
			l.Enabled = false
			l.Parent = fix
		end
	end
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
	for _, pos in ipairs({ V3(18, 0, 40), V3(104, 0, 4), V3(-104, 0, -4) }) do
		deco(gym, "Cooler", V3(2, 4, 2), CF(pos + V3(0, 2, 0)), Color3.fromRGB(230, 230, 235))
		deco(gym, "Jug", V3(1.6, 2, 1.6), CF(pos + V3(0, 5, 0)), Color3.fromRGB(120, 190, 255), Enum.Material.Glass, { Transparency = 0.3 })
		buildAction(gym, "WaterPrompt", "Drink Water", "Water cooler", pos + V3(0, 0, 2.5), { Action = "Water" }, Color3.fromRGB(120, 190, 255))
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
		lamp(gym, V3(x, 21, PZ), 40, 0.7, Color3.fromRGB(220, 240, 255))
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
	-- the sun indoors so the gym's own lamps light it, daylight streams through the windows
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(64, 60, 56)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 120, 128)
	Lighting.ExposureCompensation = 0
	Lighting.GeographicLatitude = 34
	pcall(function()
		Lighting.EnvironmentDiffuseScale = 1
		Lighting.EnvironmentSpecularScale = 0.6
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
	effect("ColorCorrectionEffect", "GymGrade", { Brightness = 0.02, Contrast = 0.1, Saturation = 0.08, TintColor = Color3.fromRGB(255, 248, 240) })
	effect("BloomEffect", "GymBloom", { Intensity = 0.4, Size = 22, Threshold = 1.75 })
	effect("SunRaysEffect", "GymSunRays", { Intensity = 0.045, Spread = 0.55 })
	local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atm.Density = 0.28
	atm.Offset = 0.12
	atm.Color = Color3.fromRGB(205, 196, 182)
	atm.Decay = Color3.fromRGB(110, 118, 132)
	atm.Glare = 0.15
	atm.Haze = 1.3
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
