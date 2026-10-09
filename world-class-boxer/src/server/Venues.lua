-- Venues: fight-night ring system. Builds one template per venue in ServerStorage at boot and
-- clones it for each fight / sparring session (Venues.New dresses the clone for that fight).
--   CommunityCenter  - tier 1: school-hall ring on a basketball court, folding chairs, flickering tubes
--   ClubArena        - tier 2: smoky club, seats, bar, ladder truss with par cans, 2 follow spots
--   Arena            - tier 3: pro arena, box truss rig, jumbotron, LED boards, upper bowl, walkout
--                      stages, TV crew with a jib
--   Stadium          - tier 4: open-air world title stadium, giant bowl, big screens, skycam, fireworks
--   Gym              - sparring room (instanced copy of a gym ring) dressed to the gym facility tier
-- Server parts are structure, contracts and static dressing. Everything that moves or glows per
-- frame (rope physics, spot beams and light pools, crowd, screens, lighting grade, sound) is
-- client-only in src/client/modules/VenueFX.lua, which only the fighting player builds.
--
-- Contracts (CONTRACTS.md 7 / 11) - other code finds these by name:
--   Anchors/RingCenter, RedCorner, BlueCorner, RedNeutral, BlueNeutral (on the canvas), RedEntrance,
--   BlueEntrance, RedSteps, BlueSteps (on the floor), RefereeSpot; arena attributes RingHalf, Venue,
--   Stakes, FightKind, Popularity, GymTier, PlayerNick, Spar, CornerSponsor, Supporters.
--   Rope = 12 invisible proxies (Size.Z = length along LookVector, attrs RopeTier 1..3 bottom->top,
--   RopeSide 1..4, Sag) each holding the visible Beams RopeBeam / RopeShine between Attachments
--   RopeA (+Z end) and RopeB (-Z end). Post / Pad / TurnbucklePad stand upright (FightClient fades
--   them). Crowd/Fan (+Head), Spots/*, TallyLight, Pyro/PyroRed|PyroBlue, Jumbotron / BigScreen with
--   a label named ScreenText.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared:WaitForChild("Looks"))
local Config = require(Shared:WaitForChild("Config"))
-- Catalog is only needed for sponsor logos: a broken Catalog must never stop fights
local Catalog
do
	local ok, mod = pcall(function()
		return require(Shared:WaitForChild("Catalog"))
	end)
	Catalog = ok and mod or nil
end

local Venues = {}

local V3 = Vector3.new
local CF = CFrame.new
local M = Enum.Material
local FACE = Enum.NormalId

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function c3(t, fallback)
	if type(t) == "table" and tonumber(t[1]) then
		return Color3.fromRGB(t[1], t[2] or 0, t[3] or 0)
	end
	return fallback or Color3.new(1, 1, 1)
end

local RED = rgb(200, 25, 30)
local BLUE = rgb(25, 60, 200)
local WHITE = rgb(238, 238, 238)
local GOLD = rgb(255, 200, 40)
local BLACK = rgb(14, 14, 18)

------------------------------------------------------------------------
-- Part helpers
------------------------------------------------------------------------
local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function deco(parent, name, size, cf, color, material, extra)
	local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material or M.SmoothPlastic }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return part(parent, props)
end

-- pure dressing: never collides, never blocks raycasts or touches
local function prop(parent, name, size, cf, color, material, extra)
	local p = deco(parent, name, size, cf, color, material, extra)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- lookAt that survives a vertical direction (CFrame.lookAt degenerates when look ~ up)
local function lookAt(from, to)
	local d = to - from
	if d.Magnitude < 1e-4 then
		return CF(from)
	end
	if math.abs(d.Unit.Y) > 0.98 then
		return CFrame.lookAt(from, to, Vector3.xAxis)
	end
	return CFrame.lookAt(from, to)
end

-- square-section bar between two points (truss chords, rails, cables)
local function rod(parent, name, p0, p1, thick, color, material, extra)
	local len = (p1 - p0).Magnitude
	return prop(parent, name, V3(thick, thick, len), lookAt((p0 + p1) / 2, p1), color, material or M.Metal, extra)
end

-- round bar (Cylinder parts run along their X axis)
local function pipe(parent, name, p0, p1, dia, color, material, extra)
	local len = (p1 - p0).Magnitude
	local p = prop(parent, name, V3(len, dia, dia), lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.pi / 2, 0), color, material or M.Metal, extra)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- ellipsoid (padding, heads, domes): Part + SpecialMesh sphere keeps the box size for collisions
local function blob(parent, name, size, cf, color, material, extra)
	local p = prop(parent, name, size, cf, color, material, extra)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

local function tag(inst, name)
	pcall(function()
		CollectionService:AddTag(inst, name)
	end)
	return inst
end

------------------------------------------------------------------------
-- GUI helpers. Printed things (canvas, skirts, cloth) take light (LightInfluence 1) so they do not
-- glow in the dark; LED / screens use LightInfluence 0. Low PixelsPerStud keeps texture memory sane.
------------------------------------------------------------------------
local function gui(p, face, pps, light, bright)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps or 14
	sg.LightInfluence = light or 0
	sg.Brightness = bright or 1
	sg.MaxDistance = 420
	sg.ClipsDescendants = true
	sg.Parent = p
	return sg
end

local function label(parent, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = WHITE
	t.Text = ""
	for k, v in pairs(props) do
		t[k] = v
	end
	t.Parent = parent
	return t
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function round(f, scale)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.5, 0)
	c.Parent = f
	return c
end

local function stroke(f, thick, color, transp)
	local s = Instance.new("UIStroke")
	s.Thickness = thick
	s.Color = color
	s.Transparency = transp or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	return s
end

-- one-label sign; the label is named ScreenText (FightClient's legacy screens() hook)
local function sign(p, face, text, bg, fg, pps, font, light)
	local sg = gui(p, face, pps or 14, light or 0, 1)
	label(sg, {
		Name = "ScreenText", Size = UDim2.fromScale(1, 1), BackgroundColor3 = bg or BLACK, BackgroundTransparency = bg and 0 or 1,
		TextColor3 = fg or GOLD, Font = font or Enum.Font.GothamBlack, Text = text,
	})
	return sg
end

local function pointLight(p, color, range, brightness, shadows)
	local l = Instance.new("PointLight")
	l.Color = color or Color3.new(1, 1, 1)
	l.Range = range or 20
	l.Brightness = brightness or 1
	l.Shadows = shadows == true
	l.Parent = p
	return l
end

local function spotLight(p, face, color, angle, range, brightness, shadows)
	local l = Instance.new("SpotLight")
	l.Face = face
	l.Color = color or Color3.new(1, 1, 1)
	l.Angle = angle or 45
	l.Range = math.min(60, range or 40)
	l.Brightness = brightness or 1
	l.Shadows = shadows == true
	l.Parent = p
	return l
end

------------------------------------------------------------------------
-- Venue specs (templates are built once; per-fight variation happens in Venues.New)
------------------------------------------------------------------------
local SPECS = {
	CommunityCenter = {
		tier = 1, size = 110, height = 24, roof = true, half = 10, ringH = 2, rows = 2, rowStart = 18, rowGap = 4.5, rowRise = 0,
		floor = rgb(150, 110, 70), floorMat = M.WoodPlanks, wall = rgb(190, 190, 175), wallMat = M.Brick,
		canvas = rgb(214, 210, 198), banner = "COMMUNITY BOXING NIGHT", bannerFont = Enum.Font.PermanentMarker, lights = "fluorescent", fill = 0.55, chairs = true,
		pads = "pillow", sag = 0.3, wear = 0.8, apron = rgb(150, 24, 28), skirt = rgb(26, 32, 70), print = rgb(150, 24, 28),
		ads = { "COMMUNITY BOXING", "AMATEUR NIGHT", "PAL BOXING CLUB", "AMATEUR NIGHT" }, court = true, bunting = true, pa = true, scoreboard = true,
	},
	ClubArena = {
		tier = 2, size = 150, height = 36, roof = true, half = 11, ringH = 3, rows = 4, rowStart = 22, rowGap = 5, rowRise = 2.2,
		floor = rgb(30, 30, 34), floorMat = M.Concrete, wall = rgb(25, 25, 30), wallMat = M.Concrete,
		canvas = rgb(222, 222, 226), banner = "CITY CLUB FIGHT NIGHT", lights = "spots", fill = 0.75, seats = rgb(40, 40, 48),
		pads = "cover", sag = 0.16, wear = 0.4, apron = rgb(22, 22, 26), skirt = rgb(18, 18, 22), print = rgb(170, 20, 26),
		ads = { "CITY CLUB", "FIGHT NIGHT", "WCB SPORTS", "CITY CLUB" }, rigY = 28, truss = "ladder", parCans = 4,
		followSpots = 2, spotR = 22, spotY = 28, houseLights = true, bar = true, neon = true, clubScreen = true, cameras = 1,
		barrier = "metal", chase = true,
	},
	Arena = {
		tier = 3, size = 220, height = 70, roof = true, half = 12, ringH = 4, rows = 6, rowStart = 26, rowGap = 5, rowRise = 2.5,
		floor = rgb(18, 18, 22), floorMat = M.Concrete, wall = rgb(8, 8, 12), wallMat = M.SmoothPlastic,
		canvas = rgb(226, 226, 230), banner = "GRAND ARENA", lights = "rig", fill = 0.85, jumbotron = true, jumboY = 30, seats = rgb(120, 22, 30),
		pads = "cover", sag = 0.1, wear = 0.15, apron = rgb(16, 16, 20), skirt = rgb(12, 12, 16), print = rgb(25, 60, 200), ledSkirt = true,
		ads = { "GRAND ARENA", "WCB SPORTS", "PRO BOXING", "WCB SPORTS" }, rigY = 40, truss = "box", parCans = 8,
		followSpots = 4, spotR = 30, spotY = 40, houseLights = true, cameras = 3, jib = true, walkoutStage = true, pyro = true,
		vip = true, press = true, commentary = true, barrier = "led", chase = true, bowl = true, gloss = true,
	},
	Stadium = {
		tier = 4, size = 330, height = 90, roof = false, half = 13, ringH = 4.5, rows = 11, rowStart = 30, rowGap = 5.5, rowRise = 3.2,
		floor = rgb(40, 90, 50), floorMat = M.Grass, wall = rgb(40, 40, 48), wallMat = M.Concrete,
		canvas = rgb(235, 235, 240), banner = "WORLD CHAMPIONSHIP BOXING", lights = "towers", fill = 0.92, jumbotron = true, jumboY = 44, seats = rgb(25, 50, 120),
		pads = "cover", sag = 0.08, wear = 0.05, apron = rgb(14, 14, 18), skirt = rgb(10, 10, 14), print = rgb(200, 25, 30), ledSkirt = true,
		ads = { "WORLD CHAMPIONSHIP", "WCB SPORTS", "NATIONAL STADIUM", "WCB SPORTS" }, rigY = 52, truss = "box", parCans = 8,
		followSpots = 6, spotR = 34, spotY = 42, houseLights = true, cameras = 4, jib = true, skycam = true, walkoutStage = true, pyro = true,
		fireworks = true, vip = true, press = true, commentary = true, barrier = "led", chase = true, bowl = true, gloss = true, bigScreens = true,
		spots = true,
	},
	Gym = {
		tier = 0, size = 70, height = 22, roof = true, half = 10, ringH = 2.5, rows = 0, rowStart = 18, rowGap = 4, rowRise = 0,
		floor = rgb(122, 88, 60), floorMat = M.WoodPlanks, wall = rgb(70, 72, 80), wallMat = M.Brick,
		canvas = rgb(40, 70, 170), banner = "SPARRING", lights = "fluorescent", fill = 0,
		pads = "pillow", sag = 0.22, wear = 0.55, apron = rgb(30, 30, 34), skirt = rgb(30, 30, 34), print = rgb(235, 235, 240),
		ads = { "SPARRING", "WORK HARD", "HANDS UP", "WORK HARD" }, gym = true, windows = true,
	},
}
Venues.Specs = SPECS

local ROPE_H = { 1.6, 3.0, 4.4 }
local SHIRTS = { { 200, 30, 30 }, { 30, 60, 200 }, { 240, 240, 240 }, { 30, 30, 30 }, { 240, 190, 40 }, { 40, 150, 70 }, { 130, 40, 170 }, { 240, 120, 30 }, { 60, 60, 66 }, { 150, 150, 158 } }
local ORG_COLORS = {
	WBA = { strap = rgb(20, 20, 20), accent = rgb(255, 200, 40) },
	WBC = { strap = rgb(20, 110, 55), accent = rgb(255, 215, 90) },
	IBF = { strap = rgb(140, 18, 28), accent = rgb(255, 215, 90) },
	WBO = { strap = rgb(20, 36, 110), accent = rgb(230, 230, 235) },
}

local function skinColor(rng)
	local s = Looks.SkinTones[rng:NextInteger(1, #Looks.SkinTones)]
	return rgb(s[1], s[2], s[3])
end

local function hairColor(rng)
	local h = Looks.HairColors[rng:NextInteger(1, 9)]
	return rgb(h[1], h[2], h[3])
end

------------------------------------------------------------------------
-- Cheap people (judges, crew, cornermen, press): at most 6 parts each (CONTRACTS 11), never Builder NPCs.
-- Torso, Head, ArmL, ArmR, one legs block (standing "Legs", seated "Lap") and an optional Hair cap or Mic.
-- Ties, towels and headsets are SurfaceGui prints, not parts. Seated people only ever sit at the skirted
-- ringside tables, which hide their shins from the ring, so they get no shin block.
-- cf = feet (or seat) position, LookVector = where they face. Arms are named ArmL / ArmR with an
-- attribute Side so VenueFX can swing them around the shoulder (Torso.CFrame * (side*1.05, 0.75, 0)).
------------------------------------------------------------------------
local function armCF(torsoCF, side, pitch, roll)
	return torsoCF * CF(side * 1.05, 0.75, 0) * CFrame.Angles(pitch or 0, 0, (roll or 0) * side) * CF(0, -0.9, 0)
end

local function figure(parent, name, cf, rng, o)
	o = o or {}
	local m = Instance.new("Model")
	m.Name = name
	local skin = o.skin or skinColor(rng)
	local shirt = o.shirt or c3(SHIRTS[rng:NextInteger(1, #SHIRTS)])
	local pants = o.pants or rgb(28, 28, 34)
	local seated = o.pose == "sit"
	local hipY = seated and (o.seatH or 1.7) or 2.6
	local parts = 0
	if seated then
		prop(m, "Lap", V3(1.3, 0.6, 1.45), cf * CF(0, hipY + 0.3, -0.6), pants, M.Fabric, { CastShadow = false })
	else
		local legs = prop(m, "Legs", V3(1.3, 2.6, 0.68), cf * CF(0, 1.3, 0), pants, M.Fabric, { CastShadow = false })
		-- a darker seam from the crotch down reads as two legs at any distance
		for _, f in ipairs({ FACE.Front, FACE.Back }) do
			local sg = gui(legs, f, 20, 1, 1)
			frame(sg, { Size = UDim2.fromScale(0.07, 0.8), Position = UDim2.fromScale(0.465, 0.2), BackgroundColor3 = pants:Lerp(BLACK, 0.6) })
		end
	end
	parts += 1
	local torsoY = hipY + (seated and 0.6 or 0) + 0.95
	local torsoCF = cf * CF(0, torsoY, 0)
	local torso = prop(m, "Torso", V3(1.6, 1.9, 0.85), torsoCF, shirt, M.Fabric, { CastShadow = false })
	local head = blob(m, "Head", V3(1.02, 1.18, 1.08), cf * CF(0, torsoY + 1.55, 0), skin, M.SmoothPlastic, { CastShadow = false })
	parts += 2
	local arms = o.arms or { { 0, 0.08 }, { 0, 0.08 } }
	for i, side in ipairs({ -1, 1 }) do
		local a = arms[i] or arms[1]
		local arm = prop(m, side < 0 and "ArmL" or "ArmR", V3(0.46, 1.8, 0.5), armCF(torsoCF, side, a[1], a[2]), o.sleeves or shirt, M.Fabric, { CastShadow = false })
		arm:SetAttribute("Side", side)
		arm:SetAttribute("Pitch", a[1])
		arm:SetAttribute("Roll", a[2])
		parts += 1
	end
	if o.mic then
		local armR = m:FindFirstChild("ArmR")
		prop(m, "Mic", V3(0.2, 0.2, 0.7), armR.CFrame * CF(0, -0.95, -0.25), rgb(30, 30, 32), M.Metal, { CastShadow = false })
		parts += 1
	end
	-- the roll is always drawn so the venue's random stream does not depend on the part budget
	local wantsHair = o.hair ~= false and rng:NextNumber() < 0.8
	if wantsHair and parts < 6 then
		blob(m, "Hair", V3(1.08, 0.62, 1.12), head.CFrame * CF(0, 0.33, 0.06), o.hairColor or hairColor(rng), M.Fabric, { CastShadow = false })
	end
	-- shirt-front prints: tie (on a white shirt front) and the cutman's towel over one shoulder
	local front
	if o.tie or o.towel then
		front = gui(torso, FACE.Front, 30, 1, 1)
	end
	if o.tie then
		frame(front, { Name = "Shirt", Size = UDim2.fromScale(0.24, 0.42), Position = UDim2.fromScale(0.38, 0), BackgroundColor3 = rgb(236, 236, 240) })
		frame(front, { Name = "Tie", Size = UDim2.fromScale(0.12, 0.6), Position = UDim2.fromScale(0.44, 0.06), BackgroundColor3 = o.tie, ZIndex = 2 })
	end
	if o.towel then
		frame(front, { Name = "Towel", Size = UDim2.fromScale(0.24, 0.55), Position = UDim2.fromScale(0.06, 0), BackgroundColor3 = WHITE, ZIndex = 3 })
	end
	if o.headset then
		-- ear cups on both sides of the head plus a short boom mic
		for _, f in ipairs({ FACE.Left, FACE.Right }) do
			local sg = gui(head, f, 40, 1, 1)
			round(frame(sg, { Name = "EarCup", Size = UDim2.fromScale(0.42, 0.36), Position = UDim2.fromScale(0.29, 0.36), BackgroundColor3 = rgb(20, 20, 22) }), 0.5)
		end
		local sg = gui(head, FACE.Front, 40, 1, 1)
		frame(sg, { Name = "Boom", Size = UDim2.fromScale(0.3, 0.06), Position = UDim2.fromScale(0.62, 0.7), BackgroundColor3 = rgb(20, 20, 22) })
	end
	if o.text or o.towel then
		local back = gui(torso, FACE.Back, 30, 1, 1)
		if o.towel then
			-- the towel hangs down the back of the same shoulder (Back face is mirrored)
			frame(back, { Name = "Towel", Size = UDim2.fromScale(0.24, 0.4), Position = UDim2.fromScale(0.7, 0), BackgroundColor3 = WHITE })
		end
		if o.text then
			label(back, { Size = UDim2.fromScale(0.9, 0.35), Position = UDim2.fromScale(0.05, 0.12), Text = o.text, TextColor3 = o.textColor or WHITE, ZIndex = 2 })
		end
	end
	m.PrimaryPart = torso
	m:SetAttribute("Pose", seated and "sit" or "stand")
	if o.loop then
		m:SetAttribute("Loop", o.loop)
	end
	if o.role then
		m:SetAttribute("Role", o.role)
	end
	m.Parent = parent
	return m
end

local function chair(parent, cf, color, padded)
	prop(parent, "ChairSeat", V3(1.7, 0.3, 1.6), cf * CF(0, 1.55, 0), color, padded and M.Fabric or M.Metal, { CastShadow = false })
	prop(parent, "ChairBack", V3(1.7, 2.0, 0.25), cf * CF(0, 2.6, 0.75), color, padded and M.Fabric or M.Metal, { CastShadow = false })
end

-- ringside table; cf at floor level, LookVector toward the ring. The skirt faces the ring.
local function ringTable(parent, name, cf, len, cloth, text)
	local m = Instance.new("Model")
	m.Name = name
	prop(m, "TableTop", V3(len, 0.18, 2.3), cf * CF(0, 2.5, 0), rgb(46, 42, 40), M.Wood)
	local skirt = prop(m, "TableSkirt", V3(len, 2.45, 0.1), cf * CF(0, 1.25, -1.12), cloth, M.Fabric, { CastShadow = false })
	if text then
		sign(skirt, FACE.Front, text, cloth, rgb(240, 240, 240), 14, Enum.Font.GothamBold, 1)
	end
	m.Parent = parent
	return m
end

------------------------------------------------------------------------
-- Crowd
------------------------------------------------------------------------
-- rows with real fans (what the ringside / walkout cameras read: bodies, hair, arms VenueFX throws
-- up). Every row behind is a printed row: one slab per seating block whose ring-facing surface
-- gets RichText "heads" from VenueFX.setupBowl on the fighting client, like the upper bowl. A
-- Stadium clone carries ~550 crowd parts that way instead of ~3,200, an Arena ~400 instead of ~1,200
local PHYSICAL_ROWS = 3

local function buildCrowd(arena, spec, rng)
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	crowd.Parent = arena
	local prints = arena:FindFirstChild("Bowl") or Instance.new("Folder")
	prints.Name = "Bowl"
	prints.Parent = arena
	-- body sizes and hair come from their own stream so the seating draws stay as they were
	local vary = Random.new(spec.half * 977 + spec.tier * 31 + spec.rows)
	for side = 0, 3 do
		local rot = CFrame.Angles(0, side * math.pi / 2, 0)
		for row = 0, spec.rows - 1 do
			local dist = spec.rowStart + row * spec.rowGap
			local h = row * spec.rowRise
			local stepColor = spec.chairs and rgb(60, 60, 70) or rgb(35, 35, 42)
			-- seat rows behind every row of fans (empty seats show when the house is not full)
			local blocks = {}
			if side == 0 or side == 2 then
				local w = dist - 5
				for _, sx in ipairs({ -1, 1 }) do
					table.insert(blocks, { w = w, x = sx * (5 + w / 2) })
				end
			else
				table.insert(blocks, { w = dist * 2 + 10, x = 0 })
			end
			for _, b in ipairs(blocks) do
				if h > 0 then
					deco(arena, "Stand", V3(b.w, h + 0.5, spec.rowGap), rot * CF(b.x, (h + 0.5) / 2, dist + spec.rowGap / 2), stepColor, M.Concrete)
				end
				if spec.seats then
					-- the seat-back strip stands on the stand (top h + 0.5); the ringside row on the floor
					local seatY = h > 0 and (h + 0.5 + 0.6) or 0.6
					prop(arena, "SeatRow", V3(b.w, 1.2, 0.35), rot * CF(b.x, seatY, dist + spec.rowGap / 2 + 0.8), spec.seats, M.Fabric, { CastShadow = false })
				end
				if row >= PHYSICAL_ROWS then
					-- the printed row: the slab's Front face (towards the ring) gets the heads client-side
					local seatCol = spec.seats or rgb(30, 30, 36)
					local slab = prop(prints, "RowPrint", V3(b.w, 3.0, 0.8), rot * CF(b.x, h + 0.5 + 1.5, dist + spec.rowGap / 2), seatCol:Lerp(BLACK, 0.5), M.Fabric, { CastShadow = false })
					local sg = gui(slab, FACE.Front, 4, 1, 1)
					sg.Name = "CrowdPrint"
					frame(sg, { Name = "Seats", Size = UDim2.fromScale(1, 1), BackgroundColor3 = seatCol:Lerp(Color3.new(), 0.35) })
					slab:SetAttribute("CrowdRows", 1)
					slab:SetAttribute("CrowdCols", math.max(4, math.floor(b.w / 2.4)))
					slab:SetAttribute("Fill", spec.fill)
				end
			end
			local seats = row < PHYSICAL_ROWS and math.floor((dist * 2) / 3.2) or -1
			for i = 0, seats do
				local x = -dist + i * 3.2
				local aisle = (side == 0 or side == 2) and math.abs(x) < 5
				if not aisle and rng:NextNumber() < spec.fill then
					local base = rot * CF(x, h + 0.5, dist + spec.rowGap / 2)
					if spec.chairs then
						deco(arena, "Chair", V3(1.8, 1.6, 1.8), base * CF(0, 0.8, 0.3), rgb(70, 70, 80), M.Metal, { CanCollide = false })
					end
					local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
					local y = spec.chairs and 2 or 1
					-- no two fans the same build: broad / narrow shoulders, tall / short (seat stays put)
					local sw, sh = 1.6 * (0.88 + vary:NextNumber() * 0.26), 2 * (0.9 + vary:NextNumber() * 0.2)
					local cy = y - (2 - sh) / 2
					local fan = deco(crowd, "Fan", V3(sw, sh, 1), base * CF(0, cy, 0), c3(shirt), M.Fabric, { CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
					fan:SetAttribute("Row", row)
					local headCF = base * CF(0, cy + sh / 2 + 0.6, 0)
					local head = deco(fan, "Head", V3(1.2, 1.2, 1.2), headCF, skinColor(rng), nil, { CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
					head.Shape = Enum.PartType.Ball
					-- the camera-facing rows get hair caps; the rows behind stay one block + one ball (part budget)
					if row <= 1 and vary:NextNumber() < 0.75 then
						blob(fan, "Hair", V3(1.25, 0.6, 1.25), headCF * CF(0, 0.38, 0.05), hairColor(vary), M.Fabric, { CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
					end
					-- the front row is what the camera sees: they get arms VenueFX can throw in the air
					if row == 0 then
						for _, sx in ipairs({ -1, 1 }) do
							local arm = prop(fan, sx < 0 and "ArmL" or "ArmR", V3(0.42, 1.6, 0.45), base * CF(sx * (sw / 2 + 0.22), y + 0.05, -0.05), fan.Color, M.Fabric, { CastShadow = false })
							arm:SetAttribute("Side", sx)
						end
					end
				end
			end
		end
	end
	return crowd
end

-- the big upper bowl (Arena / Stadium): one slab per side whose ring-facing surface carries rows
-- of RichText "heads" - thousands of fans for ~40 GUI objects instead of thousands of parts
local function buildBowl(arena, spec, rng)
	local S = spec.size
	local R0 = spec.rowStart + spec.rows * spec.rowGap + 1
	local y0 = (spec.rows - 1) * spec.rowRise + 3.5
	local R1 = S / 2 - 3
	local y1 = math.min(spec.height - 10, y0 + (R1 - R0) * 0.72)
	spec.bowlTop = y1
	local dR, dy = R1 - R0, y1 - y0
	local slopeLen = math.sqrt(dR * dR + dy * dy)
	local width = R0 + R1
	local nRows = math.clamp(math.floor(slopeLen / 2.6), 10, 26)
	local bowl = arena:FindFirstChild("Bowl") or Instance.new("Folder") -- (buildCrowd's printed rows share it)
	bowl.Name = "Bowl"
	bowl.Parent = arena
	for side = 0, 3 do
		local a = side * math.pi / 2
		local o = V3(math.sin(a), 0, math.cos(a))
		local mid = o * ((R0 + R1) / 2) + V3(0, (y0 + y1) / 2, 0)
		local s = (o * dR + V3(0, dy, 0)).Unit
		local n = (-o * dy + V3(0, dR, 0)).Unit
		local zAxis = -n
		local xAxis = s:Cross(zAxis)
		local slab = prop(bowl, "BowlTier", V3(width, slopeLen, 1.2), CFrame.fromMatrix(mid, xAxis, s, zAxis), spec.seats or rgb(30, 30, 36), M.Fabric, { CastShadow = false })
		local sg = gui(slab, FACE.Front, 4, 1, 1)
		sg.Name = "CrowdPrint"
		frame(sg, { Name = "Seats", Size = UDim2.fromScale(1, 1), BackgroundColor3 = (spec.seats or rgb(30, 30, 36)):Lerp(Color3.new(), 0.35) })
		-- the heads themselves are generated by VenueFX on the fighting client only (zero replication)
		slab:SetAttribute("CrowdRows", nRows)
		slab:SetAttribute("Fill", spec.fill)
		for i = 1, nRows - 1, 2 do
			frame(sg, { Name = "SeatLine", Size = UDim2.fromScale(1, 0.18 / nRows), Position = UDim2.fromScale(0, i / nRows), BackgroundColor3 = rgb(10, 10, 12), BackgroundTransparency = 0.5 })
		end
		-- aisle stairs
		for _, ax in ipairs({ 0.25, 0.5, 0.75 }) do
			frame(sg, { Name = "Aisle", Size = UDim2.fromScale(0.012, 1), Position = UDim2.fromScale(ax, 0), BackgroundColor3 = rgb(70, 70, 76) })
		end
		-- the bowl's front fascia carries a ring of LED (VenueFX drives it)
		local fascia = prop(bowl, "LEDRibbon", V3(width * (R0 / ((R0 + R1) / 2)) * 0.98, 1.6, 0.3), CFrame.lookAt(o * (R0 - 0.4) + V3(0, y0 - 0.3, 0), V3(0, y0 - 0.3, 0)), BLACK, M.SmoothPlastic, { CastShadow = false })
		fascia:SetAttribute("Upper", true)
	end
end

------------------------------------------------------------------------
-- Ring
------------------------------------------------------------------------
local CORNERS_XZ = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } -- red, neutral, blue, neutral
local CORNER_COLORS = { RED, WHITE, BLUE, WHITE }

local function ropeBeams(proxy, color, sag)
	local L = proxy.Size.Z
	local down, right = V3(0, -1, 0), V3(1, 0, 0)
	local a0 = Instance.new("Attachment")
	a0.Name = "RopeA"
	a0.CFrame = CFrame.fromMatrix(V3(0, 0, L / 2), down, right)
	a0.Parent = proxy
	local a1 = Instance.new("Attachment")
	a1.Name = "RopeB"
	a1.CFrame = CFrame.fromMatrix(V3(0, 0, -L / 2), down, right)
	a1.Parent = proxy
	-- a cubic Bezier with both control points pushed by c sags 0.75 * c at mid-span
	local c = sag / 0.75
	local function beam(name, width, col, transp, emission)
		local b = Instance.new("Beam")
		b.Name = name
		b.Attachment0, b.Attachment1 = a0, a1
		b.Width0, b.Width1 = width, width
		b.FaceCamera = true
		b.Segments = 16
		b.LightInfluence = 1
		b.LightEmission = emission or 0
		b.Color = ColorSequence.new(col)
		b.Transparency = NumberSequence.new(transp or 0)
		b.CurveSize0, b.CurveSize1 = c, -c
		b.Parent = proxy
		return b
	end
	beam("RopeBeam", 0.28, color, 0)
	-- a narrow lighter core reads as the round highlight of a padded rope
	beam("RopeShine", 0.08, color:Lerp(Color3.new(1, 1, 1), 0.55), 0.45, 0.15)
end

local function canvasLogo(logoPart, top, mid, bottom, color, accent)
	for _, c in ipairs(logoPart:GetChildren()) do
		if c:IsA("SurfaceGui") then
			c:Destroy()
		end
	end
	local sg = gui(logoPart, FACE.Top, 24, 1, 1)
	sg.Name = "LogoPrint"
	local ring = frame(sg, { Name = "Ring", Size = UDim2.fromScale(0.96, 0.96), Position = UDim2.fromScale(0.02, 0.02), BackgroundTransparency = 1 })
	round(ring, 0.5)
	stroke(ring, 7, accent, 0.05)
	local inner = frame(sg, { Name = "Inner", Size = UDim2.fromScale(0.82, 0.82), Position = UDim2.fromScale(0.09, 0.09), BackgroundColor3 = accent, BackgroundTransparency = 0.88 })
	round(inner, 0.5)
	stroke(inner, 2, color, 0.2)
	label(sg, { Name = "Top", Size = UDim2.fromScale(0.62, 0.11), Position = UDim2.fromScale(0.19, 0.17), Text = top or "", TextColor3 = accent, TextTransparency = 0.1 })
	label(sg, { Name = "Mid", Size = UDim2.fromScale(0.74, 0.3), Position = UDim2.fromScale(0.13, 0.35), Text = mid or "WCB", TextColor3 = color, TextTransparency = 0.05 })
	label(sg, { Name = "Bottom", Size = UDim2.fromScale(0.6, 0.1), Position = UDim2.fromScale(0.2, 0.7), Text = bottom or "", TextColor3 = accent, TextTransparency = 0.1 })
end

-- printed canvas: sponsor bands inside each rope line (reading from outside), venue name on the
-- apron edge and seeded wear (sweat rings, scuffs, faded old spots). Orientation-independent on purpose.
local function canvasPrint(canvas, spec, ads, seed)
	local old = canvas:FindFirstChild("CanvasPrint")
	if old then
		old:Destroy()
	end
	local N = canvas.Size.X
	local sg = gui(canvas, FACE.Top, 10, 1, 1)
	sg.Name = "CanvasPrint"
	local inner = spec.half * 2 / N
	for i = 0, 3 do
		local rot = i * 90
		local a = math.rad(rot)
		local off = (spec.half - 1.7) / N
		label(sg, {
			Name = "Band", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + math.sin(a) * off, 0.5 + math.cos(a) * off),
			Size = UDim2.fromScale(inner * 0.6, 1.5 / N), Rotation = -rot, Text = ads[i % #ads + 1], TextColor3 = spec.print, TextTransparency = 0.18,
		})
		local edge = (spec.half + 1.6) / N
		label(sg, {
			Name = "Edge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + math.sin(a) * edge, 0.5 + math.cos(a) * edge),
			Size = UDim2.fromScale(inner * 0.75, 1.1 / N), Rotation = -rot, Text = string.upper(spec.displayName or ""), TextColor3 = spec.print:Lerp(Color3.new(), 0.25), TextTransparency = 0.3,
			Font = Enum.Font.GothamBold,
		})
	end
	local rng = Random.new(seed)
	local wear = spec.wear or 0.3
	local dark = spec.canvas:Lerp(Color3.new(0, 0, 0), 0.35)
	local sweat = spec.canvas:Lerp(rgb(150, 128, 86), 0.45)
	for _ = 1, math.floor(3 + wear * 14) do
		local s = 0.015 + rng:NextNumber() * 0.06
		local f = frame(sg, {
			Name = "Stain", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(s, s * (0.6 + rng:NextNumber() * 0.8)),
			Position = UDim2.fromScale(0.5 + (rng:NextNumber() - 0.5) * inner * 0.95, 0.5 + (rng:NextNumber() - 0.5) * inner * 0.95),
			Rotation = rng:NextNumber() * 180, BackgroundColor3 = rng:NextNumber() < 0.6 and sweat or dark, BackgroundTransparency = 0.82 + rng:NextNumber() * 0.1,
		})
		round(f, 0.5)
	end
	for _ = 1, math.floor(wear * 12) do
		frame(sg, {
			Name = "Scuff", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.03 + rng:NextNumber() * 0.07, 0.003 + rng:NextNumber() * 0.004),
			Position = UDim2.fromScale(0.5 + (rng:NextNumber() - 0.5) * inner * 0.9, 0.5 + (rng:NextNumber() - 0.5) * inner * 0.9),
			Rotation = rng:NextNumber() * 180, BackgroundColor3 = dark, BackgroundTransparency = 0.78,
		})
	end
	-- an old ring carries faded brown spots from past fights
	if wear > 0.45 then
		for _ = 1, rng:NextInteger(1, 3) do
			local s = 0.006 + rng:NextNumber() * 0.01
			local f = frame(sg, {
				Name = "OldSpot", Size = UDim2.fromScale(s, s), Position = UDim2.fromScale(0.5 + (rng:NextNumber() - 0.5) * inner * 0.7, 0.5 + (rng:NextNumber() - 0.5) * inner * 0.7),
				BackgroundColor3 = rgb(110, 48, 40), BackgroundTransparency = 0.72,
			})
			round(f, 0.5)
		end
	end
	return sg
end

local function skirtPrint(skirt, text, sub, bg, fg, led)
	local old = skirt:FindFirstChild("SkirtPrint")
	if old then
		old:Destroy()
	end
	local sg = gui(skirt, FACE.Front, 12, led and 0 or 1, led and 1.4 or 1)
	sg.Name = "SkirtPrint"
	local back = frame(sg, { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = bg })
	if led then
		-- LED skirts get a gradient VenueFX slides around
		local g = Instance.new("UIGradient")
		g.Name = "Sweep"
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, bg), ColorSequenceKeypoint.new(0.5, bg:Lerp(Color3.new(1, 1, 1), 0.25)), ColorSequenceKeypoint.new(1, bg) })
		g.Parent = back
	end
	label(back, { Name = "Main", Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.19, 0.12), Text = text, TextColor3 = fg })
	label(back, { Name = "Sub", Size = UDim2.fromScale(0.62, 0.2), Position = UDim2.fromScale(0.19, 0.74), Text = sub or "", TextColor3 = fg, TextTransparency = 0.25, Font = Enum.Font.GothamBold })
	return sg
end

local function buildRing(arena, spec)
	local half, RH = spec.half, spec.ringH
	local E = half + 3.2 -- outer edge of the apron
	deco(arena, "RingBase", V3(half * 2 + 6, RH - 0.4, half * 2 + 6), CF(0, (RH - 0.4) / 2, 0), rgb(20, 20, 20))
	local apron = deco(arena, "Apron", V3(half * 2 + 6.4, 0.8, half * 2 + 6.4), CF(0, RH - 0.8, 0), spec.apron, M.Fabric)
	for _, face in ipairs({ FACE.Front, FACE.Back, FACE.Left, FACE.Right }) do
		local sg = gui(apron, face, 20, 1, 1)
		sg.Name = "ApronPrint"
		label(sg, { Name = "Text", Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.2, 0.1), Text = "WCB  -  " .. string.upper(spec.displayName or ""), TextColor3 = WHITE, TextTransparency = 0.1 })
	end
	-- the skirt drapes from the apron edge to the floor on all four sides
	local skirtH = RH - 1.15
	for side = 0, 3 do
		local a = side * math.pi / 2
		local o = V3(math.sin(a), 0, math.cos(a))
		local pos = o * (E + 0.06) + V3(0, skirtH / 2, 0)
		local sk = prop(arena, "RingSkirt", V3(E * 2 + 0.2, skirtH, 0.1), CFrame.lookAt(pos, pos + o), spec.skirt, M.Fabric)
		sk:SetAttribute("Side", side)
		skirtPrint(sk, spec.ads[side % #spec.ads + 1], "WCB SPORTS", spec.skirt, rgb(235, 235, 240), spec.ledSkirt)
	end
	local canvas = deco(arena, "Canvas", V3(half * 2 + 6, 0.4, half * 2 + 6), CF(0, RH - 0.2, 0), spec.canvas, M.Fabric)
	canvasPrint(canvas, spec, spec.ads, spec.half * 131 + spec.tier)
	local logoSize = math.min(12, half)
	local logo = deco(arena, "CanvasLogo", V3(logoSize, 0.05, logoSize), CF(0, RH + 0.03, 0), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	canvasLogo(logo, "WORLD CLASS BOXING", "WCB", string.upper(spec.displayName or ""), spec.print, spec.print:Lerp(BLACK, 0.3))
	-- corner posts, turnbuckles and pads
	local padTop, padBot = ROPE_H[3] + 0.75, ROPE_H[1] - 0.7
	for i, c in ipairs(CORNERS_XZ) do
		local cx, cz = c[1] * half, c[2] * half
		local inward = V3(-c[1], 0, -c[2]).Unit
		deco(arena, "Post", V3(0.8, 5.5, 0.8), CF(cx, RH + 2.75, cz), rgb(50, 52, 58), M.Metal)
		prop(arena, "PostCap", V3(1.0, 0.25, 1.0), CF(cx, RH + 5.6, cz), CORNER_COLORS[i], M.Metal)
		for ti, h in ipairs(ROPE_H) do
			local p0 = V3(cx, RH + h, cz)
			pipe(arena, "Turnbuckle", p0 + inward * 0.35, p0 + inward * 1.05, 0.22, rgb(170, 172, 178), M.Metal, { CastShadow = false })
			if spec.pads == "pillow" then
				-- faces the ring centre so the sponsor print on FACE.Front reads from inside the ring (UpVector stays +Y)
				local pad = blob(arena, "TurnbucklePad", V3(1.25, 1.05, 1.25), CFrame.lookAt(p0 + inward * 0.55, V3(0, p0.Y, 0)), CORNER_COLORS[i], M.Leather)
				pad:SetAttribute("Corner", i)
				pad:SetAttribute("RopeTier", ti)
			end
		end
		if spec.pads == "cover" then
			local h = padTop - padBot
			local pos = V3(cx, RH + (padTop + padBot) / 2, cz) + inward * 0.55
			local pad = deco(arena, "Pad", V3(1.55, h, 0.95), CFrame.lookAt(pos, V3(0, pos.Y, 0)), CORNER_COLORS[i], M.Leather, { CanCollide = false })
			pad:SetAttribute("Corner", i)
			for _, f in ipairs({ 0.33, 0.66 }) do
				prop(arena, "PadSeam", V3(1.58, 0.06, 0.98), pad.CFrame * CF(0, (f - 0.5) * h, 0), CORNER_COLORS[i]:Lerp(BLACK, 0.45), M.Fabric, { CastShadow = false })
			end
			local sg = gui(pad, FACE.Front, 24, 1, 1)
			sg.Name = "PadPrint"
			label(sg, { Name = "Logo", Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.39), Text = "WCB", Rotation = 0, TextColor3 = (i % 2 == 0) and rgb(40, 40, 46) or WHITE })
		end
	end
	-- ropes: invisible proxies (FightClient fade + recolour contract) carrying the visible Beams
	for ri, h in ipairs(ROPE_H) do
		for side = 1, 4 do
			local a, b = CORNERS_XZ[side], CORNERS_XZ[side % 4 + 1]
			local pa, pb = V3(a[1] * half, RH + h, a[2] * half), V3(b[1] * half, RH + h, b[2] * half)
			local rope = deco(arena, "Rope", V3(0.25, 0.25, (pb - pa).Magnitude), CFrame.lookAt((pa + pb) / 2, pb), spec.ropes and spec.ropes[ri] or ({ RED, WHITE, BLUE })[ri], M.Fabric,
				{ CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1 })
			rope:SetAttribute("RopeTier", ri)
			rope:SetAttribute("RopeSide", side)
			rope:SetAttribute("Sag", spec.sag * (ri == 3 and 0.85 or 1))
			ropeBeams(rope, rope.Color, spec.sag * (ri == 3 and 0.85 or 1))
		end
	end
	for _, w in ipairs({ { 0, -half, half * 2, 0.5 }, { 0, half, half * 2, 0.5 }, { -half, 0, 0.5, half * 2 }, { half, 0, 0.5, half * 2 } }) do
		-- collision only: no queries (follow-spot / camera rays must reach the canvas) and no touches
		deco(arena, "RingWall", V3(w[3], 12, w[4]), CF(w[1], RH + 6, w[2]), Color3.new(), nil, { Transparency = 1, CanQuery = false, CanTouch = false })
	end
	-- steps with hand rails on both sides of the ring
	for _, z in ipairs({ -1, 1 }) do
		for i = 1, 3 do
			local st = deco(arena, "Step", V3(4, i * (RH / 3), 1.5), CF(0, i * (RH / 3) / 2, z * (half + 2.25 + (4 - i) * 1.5)), rgb(40, 40, 44), M.DiamondPlate)
			st.CastShadow = true
		end
		for _, x in ipairs({ -2.2, 2.2 }) do
			local lo, hi = V3(x, 0, z * (half + 7.4)), V3(x, RH, z * (E + 0.1))
			pipe(arena, "StepRail", lo, lo + V3(0, 3, 0), 0.18, rgb(150, 150, 156), M.Metal)
			pipe(arena, "StepRail", hi, hi + V3(0, 3, 0), 0.18, rgb(150, 150, 156), M.Metal)
			pipe(arena, "StepRail", lo + V3(0, 3, 0), hi + V3(0, 3, 0), 0.18, rgb(150, 150, 156), M.Metal)
		end
	end
	-- corner kit: the stool is stored outside on the floor and the bucket waits on the apron;
	-- VenueFX lifts the stool into the corner between rounds
	for _, k in ipairs({ { "Red", -1 }, { "Blue", 1 } }) do
		local s = k[2]
		local stool = Instance.new("Model")
		stool.Name = "CornerStool"
		stool:SetAttribute("Corner", k[1])
		local base = CF(s * (half + 5.6), 0, s * (half + 5.6))
		local seat = pipe(stool, "Seat", base.Position + V3(0, 2.3, 0), base.Position + V3(0, 2.6, 0), 1.5, k[1] == "Red" and RED or BLUE, M.Leather)
		prop(stool, "Legs", V3(1.1, 2.3, 1.1), base * CF(0, 1.15, 0), rgb(40, 40, 44), M.Metal, { Transparency = 0.15 })
		stool.PrimaryPart = seat
		stool.Parent = arena
		local bucket = Instance.new("Model")
		bucket.Name = "CornerBucket"
		bucket:SetAttribute("Corner", k[1])
		local bp = V3(s * (half + 1.5), RH, s * (half + 2.6))
		pipe(bucket, "Bucket", bp, bp + V3(0, 1.1, 0), 1.0, rgb(230, 230, 235), M.Plastic)
		pipe(bucket, "Water", bp + V3(0, 0.95, 0), bp + V3(0, 1.0, 0), 0.9, rgb(90, 140, 190), M.Glass, { Transparency = 0.35 })
		pipe(bucket, "Bottle", bp + V3(0.8 * -s, 0, 0), bp + V3(0.8 * -s, 0.9, 0), 0.32, k[1] == "Red" and RED or BLUE, M.Plastic)
		bucket.Parent = arena
	end
	return canvas
end

------------------------------------------------------------------------
-- Ringside: officials, timekeeper + bell, press, commentary, VIP rows, cornermen, announcer, barrier
------------------------------------------------------------------------
local function buildRingside(arena, spec, rng)
	if spec.gym then
		return
	end
	local half, RH = spec.half, spec.ringH
	local E = half + 3.2
	local side = Instance.new("Folder")
	side.Name = "Ringside"
	side.Parent = arena
	local officials = Instance.new("Folder")
	officials.Name = "Officials"
	officials.Parent = arena
	local cloth = spec.tier >= 3 and rgb(18, 18, 24) or rgb(110, 20, 26)
	local suit = rgb(26, 30, 44)
	-- judge 1 + timekeeper (-X), judge 2 (+X), judge 3 (+Z, beside the blue walkway)
	local function face(pos)
		return CFrame.lookAt(pos, V3(0, pos.Y, 0))
	end
	local function faceAxis(pos, n)
		return CFrame.lookAt(pos, pos - n)
	end
	local tables = {
		{ name = "JudgeTable", cf = face(V3(-(E + 2.2), 0, 0)), len = 9, seats = { { -2.4, "Judge" }, { 2.4, "Timekeeper" } }, text = "OFFICIALS" },
		{ name = "JudgeTable", cf = face(V3(E + 2.2, 0, 0)), len = 4.5, seats = { { 0, "Judge" } }, text = "JUDGE" },
		{ name = "JudgeTable", cf = faceAxis(V3(9, 0, E + 2.2), V3(0, 0, 1)), len = 4.5, seats = { { 0, "Judge" } }, text = "JUDGE" },
	}
	for _, t in ipairs(tables) do
		ringTable(side, t.name, t.cf, t.len, cloth, t.text)
		for _, s in ipairs(t.seats) do
			local seatCF = t.cf * CF(s[1], 0, 1.7)
			chair(side, seatCF * CF(0, 0, 0.1), rgb(30, 30, 34), spec.tier >= 3)
			local fig = figure(officials, s[2], seatCF, rng, { pose = "sit", shirt = suit, sleeves = suit, tie = s[2] == "Judge" and rgb(140, 20, 30) or rgb(20, 20, 24), arms = { { 0.8, 0.12 }, { 0.8, 0.12 } }, role = s[2] })
			fig:SetAttribute("Role", s[2])
			-- scorecards on the table
			prop(side, "Scorecard", V3(1.0, 0.03, 1.3), t.cf * CF(s[1] + 0.3, 2.61, -0.2) * CFrame.Angles(0, 0.2, 0), rgb(245, 245, 240), M.SmoothPlastic, { CastShadow = false })
			if s[2] == "Timekeeper" then
				local bell = Instance.new("Model")
				bell.Name = "RingBell"
				local bp = t.cf * CF(s[1] - 1.6, 2.6, -0.3)
				prop(bell, "BellBase", V3(1.4, 0.2, 1.0), bp * CF(0, 0.1, 0), rgb(60, 36, 20), M.Wood)
				prop(bell, "BellStand", V3(0.15, 0.9, 0.15), bp * CF(0, 0.6, 0), rgb(40, 40, 40), M.Metal)
				local dome = blob(bell, "Bell", V3(1.0, 0.6, 1.0), bp * CF(0, 1.15, 0), rgb(214, 170, 60), M.Foil)
				prop(bell, "BellHammer", V3(0.12, 0.12, 1.1), bp * CF(0.55, 0.35, 0.2) * CFrame.Angles(0, 0.6, 0), rgb(80, 50, 30), M.Wood)
				bell.PrimaryPart = dome
				bell.Parent = side
			end
		end
	end
	-- press row behind judge 2 (laptop glow is a cheap emissive lid)
	if spec.press then
		local count = spec.tier >= 3 and 4 or 2
		local cf = face(V3(E + 6.8, 0, 0))
		ringTable(side, "PressTable", cf, count * 2.6, rgb(20, 20, 26), "PRESS")
		for i = 1, count do
			local x = (i - (count + 1) / 2) * 2.6
			local seatCF = cf * CF(x, 0, 1.7)
			chair(side, seatCF * CF(0, 0, 0.1), rgb(30, 30, 34), false)
			figure(officials, "Press", seatCF, rng, { pose = "sit", arms = { { 0.85, 0.1 }, { 0.85, 0.1 } }, role = "Press" })
			prop(side, "LaptopBase", V3(1.2, 0.06, 0.85), cf * CF(x, 2.63, -0.1), rgb(40, 40, 44), M.Metal, { CastShadow = false })
			local lid = prop(side, "Laptop", V3(1.2, 0.8, 0.05), cf * CF(x, 3.0, 0.32) * CFrame.Angles(math.rad(-15), 0, 0), rgb(40, 40, 44), M.Metal, { CastShadow = false })
			local sg = gui(lid, FACE.Back, 40, 0, 1.2)
			frame(sg, { Size = UDim2.fromScale(0.92, 0.88), Position = UDim2.fromScale(0.04, 0.06), BackgroundColor3 = rgb(150, 190, 255) })
		end
	end
	-- broadcast commentary desk behind judge 1
	if spec.commentary then
		local cf = face(V3(-(E + 7.2), 0, 0))
		local desk = ringTable(side, "CommentaryDesk", cf, 9, rgb(20, 20, 26), nil)
		local skirt = desk:FindFirstChild("TableSkirt")
		if skirt then
			sign(skirt, FACE.Front, "WCB LIVE", rgb(20, 20, 26), rgb(255, 60, 60), 14)
		end
		for i, x in ipairs({ -2.2, 2.2 }) do
			local seatCF = cf * CF(x, 0, 1.7)
			chair(side, seatCF * CF(0, 0, 0.1), rgb(30, 30, 34), true)
			figure(officials, "Commentator", seatCF, rng, { pose = "sit", shirt = suit, sleeves = suit, tie = i == 1 and rgb(25, 60, 200) or rgb(140, 20, 30), headset = true, arms = { { 0.75, 0.1 }, { 0.75, 0.1 } }, role = "Commentator" })
			local mon = prop(side, "Monitor", V3(1.6, 1.0, 0.12), cf * CF(x, 3.15, -0.6), rgb(20, 20, 22), M.Metal, { CastShadow = false })
			local sg = gui(mon, FACE.Back, 30, 0, 1.1)
			frame(sg, { Size = UDim2.fromScale(0.94, 0.9), Position = UDim2.fromScale(0.03, 0.05), BackgroundColor3 = rgb(40, 90, 60) })
		end
	end
	-- VIP rows on both walkway sides (their fans join the Crowd so they cheer with everyone)
	if spec.vip then
		local crowd = arena:FindFirstChild("Crowd")
		local vary = Random.new(spec.half * 613 + spec.tier)
		for _, z in ipairs({ -1, 1 }) do
			for row = 0, 1 do
				for i = 0, 4 do
					local x = -(6.5 + i * 2.1)
					local pos = V3(x, 0, z * (E + 4.6 + row * 2.6))
					local cf = faceAxis(pos, V3(0, 0, z))
					chair(side, cf, rgb(110, 20, 26), true)
					if crowd and rng:NextNumber() < 0.9 then
						local fan = deco(crowd, "Fan", V3(1.6, 1.9, 1), cf * CF(0, 2.75, 0.1), c3(SHIRTS[rng:NextInteger(1, #SHIRTS)]):Lerp(BLACK, 0.4), M.Fabric,
							{ CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
						fan:SetAttribute("Row", 0)
						fan:SetAttribute("VIP", true)
						local head = deco(fan, "Head", V3(1.15, 1.15, 1.15), cf * CF(0, 4.25, 0.1), skinColor(rng), nil, { CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
						head.Shape = Enum.PartType.Ball
						-- right behind the walkways and in every walkout shot: most VIPs get hair
						if vary:NextNumber() < 0.8 then
							blob(fan, "Hair", V3(1.2, 0.58, 1.2), head.CFrame * CF(0, 0.36, 0.05), hairColor(vary), M.Fabric, { CastShadow = false })
						end
					end
				end
			end
		end
	end
	-- cornermen (2 per fighter corner) wait on the floor by their corner during rounds
	local CORNER = { Red = { -1, RED }, Blue = { 1, BLUE } }
	for name, c in pairs(CORNER) do
		local s = c[1]
		local diag = V3(s, 0, s).Unit
		local perp = V3(-diag.Z, 0, diag.X)
		for i, role in ipairs({ "Trainer", "Cutman" }) do
			local pos = V3(s * (half + 4.6), 0, s * (half + 4.6)) + perp * (i == 1 and -1.5 or 1.5)
			local fig = figure(officials, "Cornerman", CFrame.lookAt(pos, V3(0, 0, 0)), rng, {
				shirt = c[2]:Lerp(BLACK, 0.25), sleeves = c[2]:Lerp(BLACK, 0.25), text = "CORNER", towel = role == "Cutman", loop = "cornerman", role = role,
				arms = { { 0.1, 0.12 }, { 0.1, 0.12 } },
			})
			fig:SetAttribute("Corner", name)
			fig:SetAttribute("Slot", i)
		end
	end
	-- ring announcer waits by the officials' table; VenueFX walks him to the centre for the intros
	figure(officials, "Announcer", CFrame.lookAt(V3(-(E + 1.4), 0, 6.5), V3(0, 0, 6.5)), rng,
		{ shirt = rgb(15, 15, 18), sleeves = rgb(15, 15, 18), pants = rgb(15, 15, 18), tie = rgb(240, 240, 240), role = "Announcer", arms = { { 0.1, 0.1 }, { 1.3, 0.05 } }, mic = true })
	-- crowd barrier in front of the first row: LED boards for the big shows, steel barricades in clubs
	if spec.barrier and spec.rows > 0 then
		local rb = spec.rowStart - 0.6
		local segs = {}
		for sd = 0, 3 do
			local a = sd * math.pi / 2
			local o = V3(math.sin(a), 0, math.cos(a))
			local t = V3(o.Z, 0, -o.X)
			if sd == 0 or sd == 2 then
				for _, sx in ipairs({ -1, 1 }) do
					local len = rb - 5
					table.insert(segs, { pos = o * rb + t * (sx * (5 + len / 2)), o = o, len = len })
				end
			else
				table.insert(segs, { pos = o * rb, o = o, len = rb * 2 })
			end
		end
		for _, sg in ipairs(segs) do
			if spec.barrier == "led" then
				local p = prop(arena, "LEDRibbon", V3(sg.len, 1.8, 0.35), CFrame.lookAt(sg.pos + V3(0, 0.9, 0), sg.pos + V3(0, 0.9, 0) - sg.o), BLACK, M.SmoothPlastic, { CanCollide = true })
				p:SetAttribute("Upper", false)
			else
				prop(arena, "Barricade", V3(sg.len, 0.18, 0.18), CFrame.lookAt(sg.pos + V3(0, 3.2, 0), sg.pos + V3(0, 3.2, 0) - sg.o), rgb(150, 150, 156), M.Metal)
				prop(arena, "Barricade", V3(sg.len, 2.6, 0.06), CFrame.lookAt(sg.pos + V3(0, 1.7, 0), sg.pos + V3(0, 1.7, 0) - sg.o), rgb(110, 110, 116), M.DiamondPlate, { Transparency = 0.35 })
			end
		end
	end
	-- glossy floor around the ring (Roblox reflectance only mirrors the sky, so sheen = smooth dark)
	if spec.gloss then
		local g = spec.rowStart - 0.8
		prop(arena, "FloorGloss", V3(g * 2, 0.04, g * 2), CF(0, 0.02, 0), rgb(12, 12, 16), M.SmoothPlastic, { Reflectance = 0.12, CanCollide = false, CanQuery = true })
	end
end

------------------------------------------------------------------------
-- Lighting rigs
------------------------------------------------------------------------
-- box truss between two points: 4 chords + zig-zag braces on the two vertical faces (ladder = 2 chords)
local function truss(parent, a, b, w, color, ladder)
	local len = (b - a).Magnitude
	local cf = lookAt((a + b) / 2, b)
	local offs = ladder and { { 0, w / 2 }, { 0, -w / 2 } } or { { -w / 2, w / 2 }, { w / 2, w / 2 }, { -w / 2, -w / 2 }, { w / 2, -w / 2 } }
	for _, o in ipairs(offs) do
		prop(parent, "TrussChord", V3(0.18, 0.18, len), cf * CF(o[1], o[2], 0), color, M.Metal, { CastShadow = false })
	end
	local n = math.max(2, math.floor(len / 3.6))
	local step = len / n
	for _, fx in ipairs(ladder and { 0 } or { -w / 2, w / 2 }) do
		for i = 0, n - 1 do
			local z0 = -len / 2 + i * step
			local up = i % 2 == 0
			rod(parent, "TrussBrace", cf * V3(fx, up and -w / 2 or w / 2, z0), cf * V3(fx, up and w / 2 or -w / 2, z0 + step), 0.1, color, M.Metal, { CastShadow = false })
		end
	end
end

local function lensGui(p, face, color, bright)
	local sg = gui(p, face, 40, 0, bright or 2.5)
	sg.Name = "Lens"
	local f = frame(sg, { Name = "Glow", Size = UDim2.fromScale(0.86, 0.86), Position = UDim2.fromScale(0.07, 0.07), BackgroundColor3 = color })
	round(f, 0.5)
	return f
end

local function buildLights(arena, spec, kind)
	local S, H, half = spec.size, spec.height, spec.half
	if spec.lights == "fluorescent" then
		local n = 0
		for x = -1, 1 do
			for z = -1, 1, 2 do
				n += 1
				local l = deco(arena, "Fluorescent", V3(10, 0.4, 1.5), CF(x * 14, H - 2, z * 10), rgb(235, 245, 255), M.Neon, { CastShadow = false })
				local pl = Instance.new("PointLight")
				pl.Range = 26
				pl.Brightness = 0.55 -- six tubes stack up; brighter blows out pale skin and the white pads
				pl.Parent = l
				prop(arena, "TubeHousing", V3(10.4, 0.3, 1.9), CF(x * 14, H - 1.7, z * 10), rgb(200, 200, 196), M.Metal)
				-- the community hall has a dying tube (Ambience flickers tagged neon)
				if spec.tier == 1 and n == 2 then
					tag(l, "NeonFlicker")
				end
			end
		end
		return
	end
	local rigY = spec.rigY or 28
	local rig = Instance.new("Model")
	rig.Name = "LightRig"
	local T = half + 3
	local w = spec.truss == "ladder" and 1.0 or 1.4
	local trussColor = rgb(40, 40, 44)
	local corners = { V3(-T, rigY, -T), V3(T, rigY, -T), V3(T, rigY, T), V3(-T, rigY, T) }
	for i = 1, 4 do
		truss(rig, corners[i], corners[i % 4 + 1], w, trussColor, spec.truss == "ladder")
	end
	-- lamp bars across the square carry the key lights
	for _, z in ipairs({ -10, 0, 10 }) do
		pipe(rig, "LampBar", V3(-T, rigY - w / 2, z), V3(T, rigY - w / 2, z), 0.3, trussColor, M.Metal, { CastShadow = false })
	end
	-- chain motors up to the roof; the open-air stadium rig hangs from cables to the bowl rim
	for _, c in ipairs(corners) do
		if spec.roof then
			rod(rig, "TrussChain", c + V3(0, w / 2, 0), V3(c.X, H - 1, c.Z), 0.12, rgb(25, 25, 25), M.Metal, { CastShadow = false })
			prop(rig, "ChainMotor", V3(0.9, 1.1, 0.9), CF(c + V3(0, w / 2 + 0.7, 0)), rgb(25, 25, 28), M.Metal, { CastShadow = false })
		else
			local top = V3(c.X / T * (S / 2 - 10), H, c.Z / T * (S / 2 - 10))
			local a0 = Instance.new("Attachment")
			a0.Parent = prop(rig, "CableAnchor", V3(1, 1, 1), CF(c + V3(0, w / 2, 0)), trussColor, M.Metal, { Transparency = 1 })
			local a1 = Instance.new("Attachment")
			a1.Parent = prop(rig, "CableAnchor", V3(1, 1, 1), CF(top), trussColor, M.Metal, { Transparency = 1 })
			local cable = Instance.new("Beam")
			cable.Name = "RigCable"
			cable.Attachment0, cable.Attachment1 = a0, a1
			cable.Width0, cable.Width1 = 0.15, 0.15
			cable.FaceCamera = true
			cable.Segments = 1
			cable.Color = ColorSequence.new(rgb(20, 20, 22))
			cable.LightInfluence = 1
			cable.Parent = a0.Parent
		end
	end
	-- key lights: 5 shadowed spot banks (the only shadow casters, so Future lighting stays cheap)
	for _, c in ipairs({ { -10, -10 }, { 10, -10 }, { 10, 10 }, { -10, 10 }, { 0, 0 } }) do
		local y = rigY - w / 2 - 0.9
		prop(rig, "LampHousing", V3(3.2, 0.9, 3.2), CF(c[1], y + 0.2, c[2]), rgb(22, 22, 24), M.Metal, { CastShadow = false })
		for _, o in ipairs({ { -0.75, -0.75 }, { 0.75, -0.75 }, { 0.75, 0.75 }, { -0.75, 0.75 } }) do
			local d = prop(rig, "LampCell", V3(0.12, 1.3, 1.3), CF(c[1] + o[1], y - 0.3, c[2] + o[2]) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 252, 238), M.Neon, { CastShadow = false })
			d.Shape = Enum.PartType.Cylinder
		end
		-- the lamp housing must not cast shadows or it would block its own shadowed light
		local l = deco(rig, "Lamp", V3(3, 0.3, 3), CF(c[1], y - 0.42, c[2]), rgb(255, 255, 240), M.SmoothPlastic, { CastShadow = false, Transparency = 1, CanCollide = false, CanQuery = false })
		spotLight(l, FACE.Bottom, rgb(255, 250, 238), 55, rigY + 20, 3.2, true)
	end
	-- coloured washes (no shadows): red side, blue side, amber fill
	local cans = spec.parCans or 0
	for i = 1, cans do
		local a = (i - 0.5) / cans * math.pi * 2
		local pos = V3(math.cos(a) * T, rigY - w / 2 - 0.8, math.sin(a) * T)
		local wash = pos.Z < -1 and "red" or (pos.Z > 1 and "blue" or "amber")
		if pos.X < -1 and math.abs(pos.Z) < T * 0.5 then
			wash = "amber"
		end
		local col = wash == "red" and rgb(255, 70, 60) or (wash == "blue" and rgb(80, 120, 255) or rgb(255, 190, 110))
		local target = V3(-pos.X * 0.25, spec.ringH, -pos.Z * 0.25)
		local can = prop(rig, "ParCan", V3(0.9, 0.9, 1.4), CFrame.lookAt(pos, target), rgb(20, 20, 22), M.Metal, { CastShadow = false })
		can:SetAttribute("Wash", wash)
		lensGui(can, FACE.Front, col, 2)
		spotLight(can, FACE.Front, col, 50, 55, 0.9, false)
		prop(rig, "Clamp", V3(0.3, 0.8, 0.3), CF(pos + V3(0, 0.7, 0)), trussColor, M.Metal, { CastShadow = false })
	end
	rig.Parent = arena
	-- house lights over the stands (VenueFX dims them for walkouts and rounds)
	if spec.houseLights and spec.rows > 0 then
		local hl = Instance.new("Folder")
		hl.Name = "HouseLights"
		hl.Parent = arena
		local r = spec.rowStart + spec.rows * spec.rowGap * 0.5
		local y = spec.rows * spec.rowRise + 14
		for sd = 0, 3 do
			local a = sd * math.pi / 2
			local p = prop(hl, "HouseLight", V3(1, 1, 1), CF(math.sin(a) * r, y, math.cos(a) * r), rgb(255, 240, 210), M.Neon, { Transparency = 1, CastShadow = false })
			pointLight(p, rgb(255, 236, 205), 60, 0.55, false)
		end
		if spec.roof then
			for _, x in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local p = prop(hl, "HouseLamp", V3(4, 0.4, 4), CF(x * r * 0.9, H - 1.6, z * r * 0.9), rgb(255, 236, 200), M.Neon, { CastShadow = false })
					p:SetAttribute("Lamp", true)
				end
			end
		end
	end
	-- follow spots (the folder name and part contract are FightClient's legacy fallback too)
	local nSpots = spec.followSpots or 0
	if nSpots > 0 then
		local spots = Instance.new("Folder")
		spots.Name = "Spots"
		spots.Parent = arena
		local r, y = spec.spotR or 30, spec.spotY or 40
		for i = 0, nSpots - 1 do
			-- quarter-step offset keeps every spot (and the stadium poles) off the walkway axes
			local a = (i + 0.25) / nSpots * math.pi * 2
			local pos = V3(math.cos(a) * r, y, math.sin(a) * r)
			-- follow spots close enough (< 60 studs) for their beams to reach the ring
			local p = deco(spots, "Spot", V3(1.3, 1.3, 2.8), CFrame.lookAt(pos, V3(0, spec.ringH, 0)), rgb(30, 30, 34), M.Metal, { CanCollide = false, CastShadow = false, CanQuery = false })
			local col = i % 2 == 0 and rgb(255, 228, 170) or rgb(200, 220, 255)
			p:SetAttribute("Color", col)
			lensGui(p, FACE.Front, col, 3)
			spotLight(p, FACE.Front, col, 16, 60, 6, false)
			-- the operator platform stays put while the head pans
			prop(arena, "SpotPlatform", V3(3.2, 0.3, 3.2), CF(pos - V3(0, 1.4, 0)), rgb(30, 30, 34), M.DiamondPlate, { CastShadow = false })
			if spec.roof then
				rod(arena, "SpotHanger", pos - V3(0, 1.3, 0), V3(pos.X, H - 1, pos.Z), 0.15, rgb(30, 30, 30), M.Metal, { CastShadow = false })
			else
				local standTop = pos - V3(0, 1.5, 0)
				rod(arena, "SpotPole", V3(pos.X, 0, pos.Z), standTop, 0.5, rgb(60, 60, 66), M.Metal, { CastShadow = false })
			end
		end
	end
	-- stadium light towers on the bowl rim: their glow is set dressing (60-stud light range)
	if spec.lights == "towers" then
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			local x, z = c[1] * (S / 2 - 8), c[2] * (S / 2 - 8)
			deco(arena, "Tower", V3(2.5, 30, 2.5), CF(x, H - 6, z), rgb(70, 70, 76), M.Metal)
			local head = deco(arena, "TowerLights", V3(14, 6, 1.5), CFrame.lookAt(V3(x, H + 10, z), V3(0, 0, 0)), rgb(255, 255, 230), M.Neon, { CastShadow = false, CanCollide = false })
			head:SetAttribute("Glow", true)
		end
	end
	return rig
end

------------------------------------------------------------------------
-- Screens: structured scoreboards (VenueFX fills NameRed/NameBlue/Round/Clock; ScreenText = message)
------------------------------------------------------------------------
local function screenGui(p, face, pps, title)
	local sg = gui(p, face, pps, 0, 1.5)
	sg.Name = "Screen"
	local bg = frame(sg, { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(6, 8, 14) })
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(rgb(22, 26, 46), rgb(4, 4, 8))
	g.Parent = bg
	label(bg, { Name = "Header", Size = UDim2.fromScale(1, 0.15), BackgroundTransparency = 0, BackgroundColor3 = rgb(150, 16, 24), Text = title, TextColor3 = GOLD })
	label(bg, { Name = "ScreenText", Size = UDim2.fromScale(0.92, 0.5), Position = UDim2.fromScale(0.04, 0.2), Text = "FIGHT NIGHT", TextColor3 = rgb(255, 210, 60) })
	local bar = frame(bg, { Name = "Bar", Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0.78), BackgroundColor3 = rgb(14, 16, 26) })
	label(bar, { Name = "NameRed", Size = UDim2.fromScale(0.36, 0.8), Position = UDim2.fromScale(0.01, 0.1), Text = "RED CORNER", TextColor3 = rgb(255, 80, 80), TextXAlignment = Enum.TextXAlignment.Left })
	label(bar, { Name = "Round", Size = UDim2.fromScale(0.12, 0.8), Position = UDim2.fromScale(0.38, 0.1), Text = "R1", TextColor3 = WHITE })
	label(bar, { Name = "Clock", Size = UDim2.fromScale(0.12, 0.8), Position = UDim2.fromScale(0.5, 0.1), Text = "3:00", TextColor3 = GOLD })
	label(bar, { Name = "NameBlue", Size = UDim2.fromScale(0.36, 0.8), Position = UDim2.fromScale(0.63, 0.1), Text = "BLUE CORNER", TextColor3 = rgb(110, 150, 255), TextXAlignment = Enum.TextXAlignment.Right })
	return sg
end

local function ledRibbonGui(p, text, face)
	local sg = gui(p, face or FACE.Front, 10, 0, 1.6)
	sg.Name = "Ribbon"
	local tick = frame(sg, { Name = "Ticker", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(8, 8, 14), ClipsDescendants = true })
	local g = Instance.new("UIGradient")
	g.Name = "Sweep"
	g.Color = ColorSequence.new(rgb(30, 10, 20), rgb(10, 20, 50))
	g.Parent = tick
	label(tick, {
		Name = "Text", Size = UDim2.new(0, 3200, 1, 0), TextScaled = false, TextSize = math.max(10, math.floor(p.Size.Y * 10 * 0.62)), TextXAlignment = Enum.TextXAlignment.Left,
		Text = text, TextColor3 = rgb(255, 214, 80),
	})
	frame(sg, { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1 })
	return sg
end

local function buildScreens(arena, spec, kind)
	local S, H = spec.size, spec.height
	-- banner on the +Z wall (the community hall's is a hand-painted cloth)
	-- in bowl venues the banner hangs above the upper tier (it would be hidden behind it)
	local bannerY = spec.bowlTop and math.min(H - 5, spec.bowlTop + 7) or H * 0.55
	local bannerSize = V3(math.min(80, S * 0.5), 8, 1)
	if spec.gym then
		-- slim banner above the round timer and telemetry board that share this wall (clear of the LED strip)
		bannerY, bannerSize = H - 3.2, V3(20, 3, 0.4)
	elseif not spec.bowlTop then
		-- clear of the 14-stud entrance tunnel standing in front of this wall
		bannerY = math.max(bannerY, 18.6)
	end
	local banner = deco(arena, "Banner", bannerSize, CF(0, bannerY, S / 2 - 1 - bannerSize.Z / 2), spec.tier == 1 and rgb(235, 232, 220) or rgb(14, 14, 18), spec.tier == 1 and M.Fabric or M.SmoothPlastic)
	if spec.tier == 1 then
		sign(banner, FACE.Front, spec.banner, rgb(235, 232, 220), rgb(170, 25, 30), 12, spec.bannerFont or Enum.Font.GothamBlack, 1)
	else
		sign(banner, FACE.Front, spec.banner, rgb(14, 14, 18), GOLD, 12)
	end
	local title = string.upper(spec.displayName or "FIGHT NIGHT")
	if spec.jumbotron then
		local y = spec.jumboY or 30
		-- hanging screen must not shadow the ring from the light rig above it
		local screen = deco(arena, "Jumbotron", V3(18, 9, 18), CF(0, y, 0), rgb(16, 16, 18), M.Metal, { CastShadow = false, CanCollide = false })
		for _, face in ipairs({ FACE.Front, FACE.Back, FACE.Left, FACE.Right }) do
			screenGui(screen, face, 22, title)
		end
		for _, dy in ipairs({ -5.0, 5.0 }) do
			local band = prop(arena, "JumboRing", V3(18.6, 1.0, 18.6), CF(0, y + dy, 0), rgb(10, 10, 12), M.Metal, { CastShadow = false })
			for _, face in ipairs({ FACE.Front, FACE.Back, FACE.Left, FACE.Right }) do
				ledRibbonGui(band, "WCB SPORTS  -  " .. title .. "  -  ", face)
			end
		end
		-- cables end at the roof / rig instead of running into the sky
		local topY = spec.roof and H or (spec.rigY or y + 10)
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			rod(arena, "ScreenCable", V3(c[1] * 8, y + 5.5, c[2] * 8), V3(c[1] * 8, topY - 0.5, c[2] * 8), 0.2, rgb(30, 30, 30), M.Metal, { CastShadow = false })
		end
	elseif spec.clubScreen then
		local y = (spec.rigY or 28) - 6
		local screen = deco(arena, "Jumbotron", V3(9, 5, 9), CF(0, y, 0), rgb(16, 16, 18), M.Metal, { CastShadow = false, CanCollide = false })
		for _, face in ipairs({ FACE.Front, FACE.Back, FACE.Left, FACE.Right }) do
			screenGui(screen, face, 24, title)
		end
		for _, c in ipairs({ { -1, -1 }, { 1, 1 } }) do
			rod(arena, "ScreenCable", V3(c[1] * 4, y + 2.5, c[2] * 4), V3(c[1] * 4, H - 0.5, c[2] * 4), 0.15, rgb(30, 30, 30), M.Metal, { CastShadow = false })
		end
	end
	if spec.scoreboard then
		-- the hall's old basketball scoreboard over the red tunnel (VenueFX puts names, round and clock on it)
		local board = deco(arena, "Scoreboard", V3(12, 6, 1), CF(0, H - 6, -(S / 2 - 1.6)), rgb(20, 20, 22), M.Metal)
		local sg = screenGui(board, FACE.Back, 20, "HOME  -  GUEST")
		for _, d in ipairs(sg:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.Font = Enum.Font.Arcade
			end
		end
	end
	if spec.bigScreens then
		-- the big screens stand on the bowl rim, above the upper tier
		local y = (spec.bowlTop or 40) + 17
		for _, x in ipairs({ -1, 1 }) do
			local big = deco(arena, "BigScreen", V3(1, 30, 52), CF(x * (S / 2 - 6), y, 0), rgb(10, 10, 12), M.Metal, { CastShadow = false })
			screenGui(big, x < 0 and FACE.Right or FACE.Left, 9, "WORLD TITLE FIGHT")
			-- the legs stand under the panel (its bottom edge is y - 15) and into the bowl's top tier
			for _, z in ipairs({ -18, 18 }) do
				rod(arena, "ScreenLeg", V3(x * (S / 2 - 6), y - 14.5, z), V3(x * (S / 2 - 6), y - 26, z), 0.8, rgb(40, 40, 46), M.Metal)
			end
		end
	end
	-- LED ribbon text gets the sponsors in Venues.New
	for _, d in ipairs(arena:GetDescendants()) do
		if d.Name == "LEDRibbon" and d:IsA("BasePart") then
			ledRibbonGui(d, "WCB SPORTS  -  " .. title .. "  -  ")
		end
	end
end

------------------------------------------------------------------------
-- Walkways, entrance stages, pyro
------------------------------------------------------------------------
local function buildWalkways(arena, spec, kind)
	local S = spec.size
	local reach = S / 2 - 4
	for _, z in ipairs({ -1, 1 }) do
		local col = z < 0 and RED or BLUE
		local corner = z < 0 and "Red" or "Blue"
		local len = reach - spec.half - 4
		local zc = z * (spec.half + 4 + len / 2)
		deco(arena, "Walkway", V3(6, 0.2, len), CF(0, 0.1, zc), col:Lerp(BLACK, 0.7), M.Fabric, { CanCollide = false })
		if spec.tier >= 2 then
			for _, x in ipairs({ -3.1, 3.1 }) do
				prop(arena, "WalkEdge", V3(0.25, 0.22, len), CF(x, 0.12, zc), col, M.Neon, { Transparency = 0.55, CastShadow = false })
			end
		end
		if spec.chase then
			-- chase tiles (Idx 1 = tunnel end) VenueFX runs a travelling wave on during the walk
			local n = math.clamp(math.floor(len / 7), 6, 11)
			for i = 1, n do
				local zz = z * (reach - 1 - (i - 1) * (len - 2) / (n - 1))
				for _, x in ipairs({ -3.1, 3.1 }) do
					local tile = prop(arena, "Chase", V3(0.5, 0.26, 1.2), CF(x, 0.13, zz), col, M.Neon, { Transparency = 0.7, CastShadow = false })
					tile:SetAttribute("Corner", corner)
					tile:SetAttribute("Idx", i)
				end
			end
		end
		if spec.tier >= 2 then
			-- walkway rails keep the crowd back
			for _, x in ipairs({ -3.8, 3.8 }) do
				prop(arena, "WalkRail", V3(0.15, 0.15, len - 4), CF(x, 3, z * (spec.half + 6 + len / 2)), rgb(150, 150, 156), M.Metal)
				for k = 0, 3 do
					local zz = z * (spec.half + 6 + k * (len - 4) / 3)
					prop(arena, "WalkRailPost", V3(0.15, 3, 0.15), CF(x, 1.5, zz), rgb(150, 150, 156), M.Metal)
				end
			end
		end
		local tunnel = deco(arena, "Tunnel", V3(16, 14, 2), CF(0, 7, z * (reach + 1)), rgb(10, 10, 12))
		sign(tunnel, z < 0 and FACE.Back or FACE.Front, z < 0 and "RED CORNER" or "BLUE CORNER", rgb(10, 10, 12), z < 0 and rgb(230, 40, 40) or rgb(60, 110, 255), 12)
		for i = 0, 2 do
			local glow = deco(arena, "WalkLight", V3(1, 1, 1), CF(0, 6, z * (spec.half + 10 + i * (reach - spec.half - 10) / 3)), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
			pointLight(glow, z < 0 and rgb(255, 120, 110) or rgb(130, 160, 255), 20, 1.3, false)
		end
		-- the walkout stage frames the entrance anchor without covering it: risers either side
		-- of the lane, an LED arch the fighter walks through and a big screen over the tunnel
		local stageH = 0
		if spec.walkoutStage then
			stageH = 1.5
			local zE = S / 2 - 8
			for _, sx in ipairs({ -1, 1 }) do
				local riser = deco(arena, "StageRiser", V3(7, stageH, 10), CF(sx * 7.6, stageH / 2, z * (zE - 0.5)), rgb(16, 16, 20), M.Fabric)
				riser:SetAttribute("Corner", corner)
				prop(arena, "StageEdge", V3(7, 0.18, 0.18), CF(sx * 7.6, stageH - 0.15, z * (zE - 5.6)), col, M.Neon, { CastShadow = false })
				local column = deco(arena, "ArchColumn", V3(1.6, 13, 1.6), CF(sx * 4.6, 6.5, z * zE), rgb(18, 18, 22), M.Metal, { CanCollide = false })
				column:SetAttribute("Corner", corner)
				local strip = prop(arena, "ArchLED", V3(0.3, 12.4, 0.3), CF(sx * 3.75, 6.5, z * (zE - 0.85)), col, M.Neon, { CastShadow = false })
				strip:SetAttribute("Corner", corner)
				local jet = prop(arena, "CO2Jet", V3(0.8, 0.9, 0.8), CF(sx * 6.2, stageH + 0.45, z * (zE - 3.5)), rgb(50, 50, 56), M.Metal)
				jet:SetAttribute("Corner", corner)
				local smoke = prop(arena, "SmokeJet", V3(1.2, 0.8, 1.6), CF(sx * 9.5, stageH + 0.4, z * (zE - 4)), rgb(30, 30, 34), M.Metal)
				smoke:SetAttribute("Corner", corner)
			end
			local header = deco(arena, "ArchHeader", V3(10.8, 2.2, 1.6), CF(0, 14.1, z * zE), rgb(18, 18, 22), M.Metal, { CanCollide = false })
			sign(header, z < 0 and FACE.Back or FACE.Front, corner == "Red" and "RED CORNER" or "BLUE CORNER", rgb(18, 18, 22), col, 16)
			local screen = deco(arena, "EntranceScreen", V3(18, 9, 0.6), CF(0, 18.5, z * (S / 2 - 3.6)), rgb(10, 10, 12), M.Metal) -- on the tunnel (top y 14)
			screen:SetAttribute("Corner", corner)
			local sg = gui(screen, z < 0 and FACE.Back or FACE.Front, 16, 0, 1.6)
			sg.Name = "Screen"
			local bg = frame(sg, { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = col:Lerp(BLACK, 0.8) })
			label(bg, { Name = "Nick", Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.08), Text = "", TextColor3 = GOLD })
			label(bg, { Name = "Name", Size = UDim2.fromScale(0.9, 0.36), Position = UDim2.fromScale(0.05, 0.26), Text = corner == "Red" and "RED CORNER" or "BLUE CORNER", TextColor3 = WHITE })
			label(bg, { Name = "Record", Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.68), Text = "", TextColor3 = col:Lerp(WHITE, 0.4) })
		end
		if spec.pyro then
			local pyroFolder = arena:FindFirstChild("Pyro") or Instance.new("Folder")
			pyroFolder.Name = "Pyro"
			pyroFolder.Parent = arena
			for _, x in ipairs({ -6, 6 }) do
				local emitterPart = deco(pyroFolder, z < 0 and "PyroRed" or "PyroBlue", V3(1, 1, 1), CF(x, stageH + 0.5, z * (reach - 6)), rgb(40, 40, 40), M.Metal, { CanCollide = false })
				local pe = Instance.new("ParticleEmitter")
				pe.Enabled = false
				pe.Rate = 120
				pe.Lifetime = NumberRange.new(0.6, 1.1)
				pe.Speed = NumberRange.new(35, 50)
				pe.SpreadAngle = Vector2.new(8, 8)
				pe.LightEmission = 1
				pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0.5) })
				pe.Color = ColorSequence.new(rgb(255, 220, 120), rgb(255, 80, 20))
				-- client-shipped flame sprite: the default sparkle texture reads as giant stars, not a flame jet
				pe.Texture = "rbxasset://textures/particles/fire_main.dds"
				pe.RotSpeed = NumberRange.new(-90, 90)
				pe.Rotation = NumberRange.new(0, 360)
				pe.EmissionDirection = FACE.Top
				pe.Parent = emitterPart
			end
		end
	end
end

------------------------------------------------------------------------
-- Broadcast: tripod cameras with operators, jib, skycam
------------------------------------------------------------------------
local function tvCamera(parent, pos, target, rng, idx)
	local m = Instance.new("Model")
	m.Name = "BroadcastCam"
	m:SetAttribute("Idx", idx)
	local base = CFrame.lookAt(pos, V3(target.X, pos.Y, target.Z))
	for _, leg in ipairs({ -0.6, 0, 0.6 }) do
		prop(m, "TripodLeg", V3(0.15, 5, 0.15), base * CF(leg, 2.5, leg ~= 0 and 0.4 or -0.5) * CFrame.Angles(0.15, 0, leg * 0.25), rgb(30, 30, 30), M.Metal)
	end
	local body = deco(m, "TVCamera", V3(1.4, 1.4, 3), CFrame.lookAt((base * CF(0, 5.6, 0)).Position, target), rgb(25, 25, 28), M.Metal, { CanCollide = false })
	local lens = prop(m, "Lens", V3(0.8, 1, 1), body.CFrame * CF(0, 0, -1.9) * CFrame.Angles(0, math.rad(90), 0), rgb(15, 15, 18), M.Glass)
	lens.Shape = Enum.PartType.Cylinder
	prop(m, "Viewfinder", V3(0.8, 0.6, 0.5), body.CFrame * CF(-0.9, 0.3, 1.2), rgb(20, 20, 22), M.Metal)
	prop(m, "TallyLight", V3(0.3, 0.3, 0.3), body.CFrame * CF(0, 0.9, -1), rgb(255, 30, 30), M.Neon)
	prop(m, "CamCable", V3(0.15, 0.06, 7), base * CF(0, 0.03, 4), rgb(15, 15, 15), M.Rubber, { CastShadow = false })
	figure(m, "CameraOp", base * CF(0, 0, 2.4), rng, { shirt = rgb(20, 20, 22), sleeves = rgb(20, 20, 22), headset = true, arms = { { 1.1, 0.15 }, { 1.3, 0.1 } }, role = "CameraOp" })
	m.PrimaryPart = body
	m.Parent = parent
	return m
end

local function buildBroadcast(arena, spec, rng)
	local n = spec.cameras or 0
	if n <= 0 and not spec.jib and not spec.skycam then
		return
	end
	local half, RH = spec.half, spec.ringH
	local E = half + 3.2
	local folder = Instance.new("Folder")
	folder.Name = "Broadcast"
	folder.Parent = arena
	local target = V3(0, RH + 3, 0)
	-- neutral-corner diagonals first, then beside each walkway
	local spots = { V3(half + 6.2, 0, -(half + 6.2)), V3(-(half + 6.2), 0, half + 6.2), V3(5.8, 0, E + 7), V3(5.8, 0, -(E + 7)) }
	for i = 1, math.min(n, #spots) do
		tvCamera(folder, spots[i], target, rng, i)
	end
	if spec.jib then
		local jib = Instance.new("Model")
		jib.Name = "Jib"
		local bp = V3(E + 8, 0, E + 3)
		local pivot = bp + V3(0, 7.4, 0)
		prop(jib, "JibBase", V3(3, 0.6, 3), CF(bp + V3(0, 0.3, 0)), rgb(30, 30, 34), M.Metal)
		pipe(jib, "JibColumn", bp + V3(0, 0.6, 0), pivot, 0.6, rgb(40, 40, 44), M.Metal)
		local dir = ((V3(0, pivot.Y, 0) - pivot).Unit + V3(0, 0.27, 0)).Unit
		local armCF = CFrame.lookAt(pivot, pivot + dir)
		local arm = prop(jib, "JibArm", V3(0.5, 0.5, 18), armCF * CF(0, 0, -5), rgb(30, 30, 34), M.Metal)
		arm:SetAttribute("Moving", true)
		local w = prop(jib, "JibWeight", V3(1.4, 1.4, 1.4), armCF * CF(0, 0, 4.2), rgb(60, 60, 66), M.Metal)
		w:SetAttribute("Moving", true)
		local head = deco(jib, "JibCam", V3(1.2, 1.2, 2), armCF * CF(0, -0.9, -14), rgb(25, 25, 28), M.Metal, { CanCollide = false, CanQuery = false })
		head:SetAttribute("Moving", true)
		local tally = prop(jib, "TallyLight", V3(0.3, 0.3, 0.3), head.CFrame * CF(0, 0.75, -0.6), rgb(255, 30, 30), M.Neon)
		tally:SetAttribute("Moving", true)
		jib:SetAttribute("Pivot", pivot)
		jib:SetAttribute("Aim", dir)
		jib.PrimaryPart = arm
		jib.Parent = folder
	end
	if spec.skycam then
		local S = spec.size
		local y = RH + 22
		local cam = deco(folder, "SkyCam", V3(1.6, 1.1, 1.6), CF(0, y, -half * 0.6), rgb(25, 25, 28), M.Metal, { CanCollide = false, CanQuery = false })
		local tally = Instance.new("Attachment")
		tally.Name = "TallyAtt"
		tally.Position = V3(0, -0.6, 0)
		tally.Parent = cam
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			local r = spec.lights == "towers" and (S / 2 - 8) or (S / 2 - 14)
			local anchor = prop(folder, "SkyCamAnchor", V3(1.5, 1.5, 1.5), CF(c[1] * r, spec.height - 4, c[2] * r), rgb(40, 40, 44), M.Metal)
			local a0 = Instance.new("Attachment")
			a0.Parent = anchor
			local a1 = Instance.new("Attachment")
			a1.Position = V3(c[1] * 0.7, 0.55, c[2] * 0.7)
			a1.Parent = cam
			local cable = Instance.new("Beam")
			cable.Name = "SkyCable"
			cable.Attachment0, cable.Attachment1 = a0, a1
			cable.Width0, cable.Width1 = 0.1, 0.1
			cable.FaceCamera = true
			cable.Segments = 1
			cable.LightInfluence = 1
			cable.Color = ColorSequence.new(rgb(20, 20, 22))
			cable.Parent = anchor
		end
	end
end

------------------------------------------------------------------------
-- Venue character: court lines, bunting and PA in the hall; bar and neon in the club
------------------------------------------------------------------------
local function buildCharacter(arena, spec, rng)
	local S, H = spec.size, spec.height
	if spec.court then
		local floor = arena.PrimaryPart
		local sg = gui(floor, FACE.Top, 3, 1, 1)
		sg.Name = "CourtLines"
		local line = rgb(245, 240, 225)
		local function outline(x, y, w, h)
			local f = frame(sg, { Size = UDim2.fromScale(w, h), Position = UDim2.fromScale(x, y), BackgroundTransparency = 1 })
			stroke(f, 2, line, 0.15)
			return f
		end
		outline(0.06, 0.12, 0.88, 0.76)
		frame(sg, { Size = UDim2.fromScale(0.004, 0.76), Position = UDim2.fromScale(0.498, 0.12), BackgroundColor3 = line, BackgroundTransparency = 0.15 })
		for _, x in ipairs({ 0.06, 0.78 }) do
			local key = outline(x, 0.4, 0.16, 0.2)
			key.BackgroundColor3 = rgb(170, 40, 40)
			key.BackgroundTransparency = 0.6
		end
		local circle = outline(0.43, 0.43, 0.14, 0.14)
		round(circle, 0.5)
		-- basketball backboards on the side walls
		for _, x in ipairs({ -1, 1 }) do
			local bx = x * (S / 2 - 2.5)
			prop(arena, "BackboardArm", V3(3, 0.3, 0.3), CF(x * (S / 2 - 1.5), 13.5, 0), rgb(60, 60, 64), M.Metal)
			local board = prop(arena, "Backboard", V3(0.2, 4, 6), CF(bx, 13, 0), rgb(240, 240, 240), M.SmoothPlastic)
			local bg = gui(board, x < 0 and FACE.Right or FACE.Left, 20, 1, 1)
			local sq = frame(bg, { Size = UDim2.fromScale(0.36, 0.42), Position = UDim2.fromScale(0.32, 0.42), BackgroundTransparency = 1 })
			stroke(sq, 3, rgb(200, 40, 30), 0)
			local rimC = V3(bx - x * 1.2, 11.2, 0)
			for k = 0, 5 do
				local a0, a1 = k / 6 * math.pi * 2, (k + 1) / 6 * math.pi * 2
				rod(arena, "Hoop", rimC + V3(math.cos(a0) * 0.8, 0, math.sin(a0) * 0.8), rimC + V3(math.cos(a1) * 0.8, 0, math.sin(a1) * 0.8), 0.08, rgb(230, 100, 30), M.Metal)
			end
		end
	end
	if spec.bunting then
		local cols = { RED, WHITE, BLUE, GOLD }
		for i, z in ipairs({ -18, 0, 18 }) do
			local n = 14
			for k = 0, n - 1 do
				local x = -S / 2 + 4 + k * (S - 8) / (n - 1)
				local sagY = H - 4 - math.sin(k / (n - 1) * math.pi) * 2.5
				local flag = Instance.new("WedgePart")
				flag.Name = "Bunting"
				flag.Anchored, flag.CanCollide, flag.CanQuery, flag.CanTouch, flag.CastShadow = true, false, false, false, false
				flag.Size = V3(0.05, 1.2, 1.2)
				flag.CFrame = CF(x, sagY, z) * CFrame.Angles(math.pi, 0, 0)
				flag.Color = cols[(k + i) % #cols + 1]
				flag.Material = M.Fabric
				flag.Parent = arena
			end
		end
	end
	if spec.pa then
		for _, x in ipairs({ -1, 1 }) do
			local p = V3(x * (spec.half + 8), 0, -(spec.half + 6))
			prop(arena, "PAStand", V3(0.2, 6, 0.2), CF(p + V3(0, 3, 0)), rgb(30, 30, 30), M.Metal)
			local box = prop(arena, "PASpeaker", V3(2, 3, 1.6), CFrame.lookAt(p + V3(0, 7.3, 0), V3(0, 7.3, 0)), rgb(24, 24, 26), M.Plastic)
			local sg = gui(box, FACE.Front, 20, 1, 1)
			local cone = frame(sg, { Size = UDim2.fromScale(0.7, 0.45), Position = UDim2.fromScale(0.15, 0.45), BackgroundColor3 = rgb(50, 50, 54) })
			round(cone, 0.5)
		end
	end
	if spec.bar then
		local x = S / 2 - 8
		prop(arena, "BarCounter", V3(3, 3.6, 34), CF(x, 1.8, 0), rgb(50, 30, 20), M.Wood)
		prop(arena, "BarTop", V3(3.6, 0.3, 34.6), CF(x, 3.75, 0), rgb(25, 20, 18), M.Marble)
		prop(arena, "BarShelf", V3(1.2, 8, 30), CF(S / 2 - 1.8, 6, 0), rgb(35, 25, 20), M.Wood)
		for k = 0, 11 do
			local p = prop(arena, "Bottle", V3(0.35, 1.0, 0.35), CF(S / 2 - 1.8, 6.6 + (k % 2) * 2.4, -12 + k * 2.2), c3(SHIRTS[rng:NextInteger(1, #SHIRTS)]):Lerp(rgb(60, 120, 60), 0.4), M.Glass, { Transparency = 0.25 })
			p.Shape = Enum.PartType.Cylinder
			p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		end
		local glow = prop(arena, "BarGlow", V3(0.2, 0.2, 32), CF(S / 2 - 1.2, 11, 0), rgb(255, 120, 40), M.Neon, { CastShadow = false })
		pointLight(glow, rgb(255, 140, 70), 22, 0.8, false)
	end
	if spec.neon then
		local signs = { { "FIGHT NIGHT", rgb(255, 50, 80) }, { "OPEN LATE", rgb(80, 220, 255) }, { "CITY CLUB", rgb(255, 200, 60) } }
		for i, s in ipairs(signs) do
			local z = -S / 2 + 1.3
			local x = -S / 2 + 25 + (i - 1) * 50
			local p = prop(arena, "NeonSign", V3(14, 3.2, 0.2), CF(x, H * 0.6, z), BLACK, M.SmoothPlastic, { Transparency = 1 })
			local sg = gui(p, FACE.Back, 20, 0, 2.5)
			label(sg, { Size = UDim2.fromScale(1, 1), Text = s[1], TextColor3 = s[2], Font = Enum.Font.Bangers, TextStrokeTransparency = 0.4, TextStrokeColor3 = s[2] })
			local tube = prop(arena, "NeonTube", V3(14.4, 0.12, 0.12), CF(x, H * 0.6 - 1.9, z + 0.2), s[2], M.Neon, { CastShadow = false })
			pointLight(tube, s[2], 14, 0.6, false)
			if i == 2 then
				tag(tube, "NeonFlicker")
			end
		end
		-- a purple wash line along the club walls
		for _, x in ipairs({ -1, 1 }) do
			prop(arena, "WallNeon", V3(0.2, 0.2, S - 6), CF(x * (S / 2 - 1.2), H - 3, 0), rgb(140, 60, 255), M.Neon, { CastShadow = false })
		end
	end
	if spec.floorCover then
		prop(arena, "FloorCover", V3(spec.rowStart * 2, 0.06, spec.rowStart * 2), CF(0, 0.03, 0), rgb(20, 20, 24), M.Fabric, { CanCollide = false })
	end
end

------------------------------------------------------------------------
-- Gym sparring room shell (tier dressing is added per session in Venues.New)
------------------------------------------------------------------------
local function poster(parent, cf, w, h, top, mid, bottom, bg, fg, rng)
	local p = prop(parent, "Poster", V3(w, h, 0.05), cf, rgb(230, 225, 210), M.SmoothPlastic, { CastShadow = false })
	local sg = gui(p, FACE.Front, 20, 1, 1)
	local back = frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = bg })
	label(back, { Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.06), Text = top, TextColor3 = fg })
	label(back, { Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.3), Text = mid, TextColor3 = WHITE, Font = Enum.Font.Bangers })
	label(back, { Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.75), Text = bottom, TextColor3 = fg, Font = Enum.Font.GothamBold })
	-- age: a yellowed overlay
	frame(back, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(200, 170, 110), BackgroundTransparency = 0.75 + rng:NextNumber() * 0.2 })
	return p
end

-- Gym members training around the sparring room: real Builder rigs (the same Ambient NPCs as the
-- gym's members, Loop heavybag / rope / shadow, tag Ambient) so the Animator drives them, at medium /
-- low detail. They are built once into the template (no per-spar Builder cost) and pruned per gym tier
-- in applyGymTier (Slot > athletes kept). Positions are on the template floor (y 0), facing their work.
-- The bag athletes stand on the bag's +-Z side: the members'-bag swing code (GymVisuals.onAutoAct /
-- hitPendulum) takes a punch as arriving along world Z, so this way the bag swings away from them.
local ATHLETES = {
	{ name = "Darnell Hayes", tag = "Gym Member", loop = "heavybag", at = V3(-30, 0, -12.4), look = V3(-30, 0, -16), hands = "gloves", seed = 3101, physique = "PowerPuncher", sweat = 0.6, detail = "medium" },
	{ name = "Keisha Moore", tag = "Gym Member", loop = "rope", at = V3(24, 0, 20), look = V3(14, 0, 12), props = "rope", stand = 0, seed = 3202, gender = 2, physique = "LeanTechnical", sweat = 0.55, detail = "low" },
	{ name = "Mateo Cruz", tag = "Gym Member", loop = "shadow", at = V3(22, 0, -22), look = V3(12, 0, -14), hands = "wraps", seed = 3303, physique = "LeanTechnical", sweat = 0.45, detail = "low" },
	{ name = "Ivy Chen", tag = "Gym Member", loop = "heavybag", at = V3(-30, 0, 12.4), look = V3(-30, 0, 16), hands = "gloves", seed = 3404, gender = 2, physique = "Balanced", sweat = 0.55, detail = "low" },
}

-- Runs in its own thread once the template is in ServerStorage: Builder.CreateNPC yields on the avatar
-- service (CreateHumanoidModelFromDescription), and server startup must not wait on that. Each rig is
-- built off-template and only parented in finished, so a spar cloned meanwhile simply has fewer
-- athletes. A rig that fails is retried once a little later.
local ATHLETE_RETRY = 15

local function buildGymAthletes(arena)
	local ok, Ambient = pcall(require, script.Parent.Ambient)
	if not ok or type(Ambient) ~= "table" or type(Ambient.SpawnAt) ~= "function" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Athletes"
	folder.Parent = arena
	local function spawnOne(i, def)
		local stage = Instance.new("Folder")
		local good, npc = pcall(Ambient.SpawnAt, stage, def, Vector3.zero)
		if good and npc then
			npc:SetAttribute("Slot", i)
			-- the template may have been rebuilt while this rig was being made
			if folder.Parent == arena and arena.Parent then
				npc.Parent = folder
			else
				npc:Destroy()
			end
		end
		stage:Destroy()
		if not (good and npc) then
			warn("[Venues] sparring room athlete failed:", def.name, npc)
			return false
		end
		return true
	end
	local missing = {}
	for i, def in ipairs(ATHLETES) do
		if not arena.Parent then
			return
		end
		if not spawnOne(i, def) then
			table.insert(missing, i)
		end
	end
	if #missing > 0 then
		task.wait(ATHLETE_RETRY)
		for _, i in ipairs(missing) do
			if not arena.Parent then
				return
			end
			spawnOne(i, ATHLETES[i])
		end
	end
end

local function buildGymRoom(arena, spec, rng)
	local S, H = spec.size, spec.height
	local half = S / 2
	-- windows in the +X wall: the wall is rebuilt as segments around three panes
	for _, w in ipairs(arena:GetChildren()) do
		if w.Name == "Wall" and w.Position.X > half - 2 then
			w:Destroy()
		end
	end
	local x = half
	deco(arena, "Wall", V3(2, 8, S), CF(x, 4, 0), spec.wall, spec.wallMat)
	deco(arena, "Wall", V3(2, H - 15, S), CF(x, 15 + (H - 15) / 2, 0), spec.wall, spec.wallMat)
	local gaps = { { -21, -15 }, { -3, 3 }, { 15, 21 } }
	local edges = { -half, -21, -15, -3, 3, 15, 21, half }
	for i = 1, #edges - 1, 2 do
		local z0, z1 = edges[i], edges[i + 1]
		deco(arena, "Wall", V3(2, 7, z1 - z0), CF(x, 11.5, (z0 + z1) / 2), spec.wall, spec.wallMat)
	end
	local sun = Instance.new("Folder")
	sun.Name = "Sunlight"
	sun.Parent = arena
	for i, g in ipairs(gaps) do
		local zc = (g[1] + g[2]) / 2
		local pane = prop(arena, "WindowPane", V3(0.2, 7, 6), CF(x - 0.4, 11.5, zc), rgb(200, 220, 235), M.Glass, { Transparency = 0.55 })
		pane:SetAttribute("SunDir", (V3(-1, -0.75, 0.15)).Unit)
		prop(arena, "WindowBar", V3(0.3, 7, 0.25), CF(x - 0.5, 11.5, zc), rgb(60, 60, 64), M.Metal)
		prop(arena, "WindowBar", V3(0.3, 0.25, 6), CF(x - 0.5, 11.5, zc), rgb(60, 60, 64), M.Metal)
		prop(arena, "WindowSill", V3(1.2, 0.3, 6.6), CF(x - 0.8, 7.9, zc), rgb(150, 145, 135), M.Concrete)
		local lamp = prop(sun, "SunLamp", V3(1, 1, 1), CFrame.lookAt(V3(x + 14, 22, zc), V3(x - 16, 0, zc + 3)), Color3.new(), M.SmoothPlastic, { Transparency = 1 })
		spotLight(lamp, FACE.Front, rgb(255, 222, 170), 38, 60, 2.2, i == 2)
	end
	-- floor mats around the ring
	for _, m in ipairs({ { 0, -(spec.half + 6), 28, 4 }, { 0, spec.half + 6, 28, 4 }, { -(spec.half + 6), 0, 4, 20 }, { spec.half + 6, 0, 4, 20 } }) do
		prop(arena, "Mat", V3(m[3], 0.1, m[4]), CF(m[1], 0.05, m[2]), rgb(40, 40, 46), M.Rubber, { CanCollide = false })
	end
	-- heavy bags on chains along the -X wall, a speed bag platform, a bench under the windows.
	-- Each bag is a members' bag rig (tag MemberBag, body part "MemberBag", Hook = the pivot) so the
	-- athletes' Animator finds it and lands punches on its surface; Venues.New re-bases Hook to world
	-- space after the pivot and gives each copy its own Index
	for i, z in ipairs({ -16, 16 }) do
		local top = V3(-half + 5, H - 0.5, z)
		local rig = Instance.new("Model")
		rig.Name = "HeavyBag"
		rig:SetAttribute("Hook", top)
		rig:SetAttribute("Index", i)
		rod(rig, "BagChain", top, V3(top.X, 7.7, z), 0.12, rgb(120, 120, 126), M.Metal)
		local bag = prop(rig, "MemberBag", V3(4.2, 2.1, 2.1), CF(top.X, 5.5, z) * CFrame.Angles(0, 0, math.pi / 2), rgb(140, 20, 24), M.Leather)
		bag.Shape = Enum.PartType.Cylinder
		rig.PrimaryPart = bag
		rig.Parent = arena
		tag(rig, "MemberBag")
	end
	prop(arena, "SpeedBoard", V3(3, 0.4, 3), CF(-half + 2.5, 9.5, 0), rgb(70, 45, 25), M.Wood)
	blob(arena, "SpeedBag", V3(0.9, 1.3, 0.9), CF(-half + 3.2, 8.6, 0), rgb(150, 25, 25), M.Leather)
	prop(arena, "Bench", V3(2, 1.6, 8), CF(half - 3, 0.8, -9), rgb(60, 40, 25), M.Wood)
	for k = 0, 2 do
		local b = prop(arena, "WaterBottle", V3(0.9, 0.35, 0.35), CF(half - 3, 1.85, -11 + k * 1.2) * CFrame.Angles(0, 0, math.pi / 2), rgb(60, 140, 220), M.Plastic, { Transparency = 0.2 })
		b.Shape = Enum.PartType.Cylinder
	end
	-- posters on the -Z wall
	local fights = { { "FRIDAY NIGHT", "COLE vs RAMIREZ" }, { "CITY CLUB", "OKAFOR vs DRAKE" }, { "TITLE ELIMINATOR", "VARGAS vs NOVAK" } }
	for i, f in ipairs(fights) do
		local pp = V3(-18 + (i - 1) * 18, 10, -half + 1.1)
		poster(arena, CFrame.lookAt(pp, pp + V3(0, 0, 1)), 5, 7, f[1], f[2], "LIVE  -  10 ROUNDS", ({ BLACK, rgb(120, 20, 20), rgb(20, 30, 90) })[i], GOLD, rng)
	end
	-- the round timer (VenueFX runs it from the session clock)
	local timer = Instance.new("Model")
	timer.Name = "GymTimer"
	local box = prop(timer, "TimerBox", V3(5, 2.6, 0.6), CF(0, 15, half - 1.4), rgb(16, 16, 18), M.Metal)
	local sg = gui(box, FACE.Front, 30, 0, 1.6)
	label(sg, { Name = "Phase", Size = UDim2.fromScale(1, 0.32), Text = "SPARRING", TextColor3 = WHITE, Font = Enum.Font.GothamBold })
	label(sg, { Name = "Time", Size = UDim2.fromScale(1, 0.66), Position = UDim2.fromScale(0, 0.32), Text = "3:00", TextColor3 = rgb(255, 60, 50), Font = Enum.Font.Arcade })
	for i, n in ipairs({ "LampGo", "LampWarn", "LampRest" }) do
		local l = prop(timer, n, V3(0.6, 0.6, 0.3), CF(-1 + (i - 1), 13.3, half - 1.3), ({ rgb(60, 220, 80), rgb(255, 200, 40), rgb(80, 180, 255) })[i], M.Neon, { Transparency = 0.65 })
		l.Shape = Enum.PartType.Ball
	end
	timer.PrimaryPart = box
	timer.Parent = arena
	-- the coach watches from the red corner; gym mates lean on the apron
	local officials = arena:FindFirstChild("Officials") or Instance.new("Folder")
	officials.Name = "Officials"
	officials.Parent = arena
	-- (off the red corner's diagonal: that spot belongs to the corner team below)
	figure(officials, "Coach", CFrame.lookAt(V3(-(spec.half + 4.2), 0, -(spec.half - 2)), V3(0, 0, 0)), rng,
		{ shirt = rgb(30, 30, 34), sleeves = rgb(30, 30, 34), loop = "coachwatch", role = "Coach", text = "COACH", arms = { { 0.35, 0.3 }, { 0.35, 0.3 } } })
	local watchers = { V3(-(spec.half + 3.9), 0, 5), V3(4, 0, spec.half + 3.9), V3(spec.half + 3.9, 0, -4), V3(-5, 0, -(spec.half + 3.9)) }
	for i, p in ipairs(watchers) do
		local fig = figure(officials, "Onlooker", CFrame.lookAt(p, V3(0, 0, 0)), rng, {
			shirt = c3(SHIRTS[rng:NextInteger(1, #SHIRTS)]), pants = rgb(40, 40, 48), loop = "ringside", role = "Onlooker",
			arms = { { 1.35, -0.15 }, { 1.35, -0.15 } },
		})
		fig:SetAttribute("Slot", i)
	end
	-- a corner team per fighter, as at the real venues (cheap proxies, Loop cornerman): the trainer
	-- always, the cutman (Slot 2) only in tier 3+ rooms (applyGymTier drops him). VenueFX finds them
	-- in Officials and walks them into the corner between rounds.
	for _, c in ipairs({ { "Red", -1, RED }, { "Blue", 1, BLUE } }) do
		local s = c[2]
		local diag = V3(s, 0, s).Unit
		local perp = V3(-diag.Z, 0, diag.X)
		for i, role in ipairs({ "Trainer", "Cutman" }) do
			local pos = V3(s * (spec.half + 4.6), 0, s * (spec.half + 4.6)) + perp * (i == 1 and -1.5 or 1.5)
			local fig = figure(officials, "Cornerman", CFrame.lookAt(pos, V3(0, 0, 0)), rng, {
				shirt = c[3]:Lerp(BLACK, 0.35), sleeves = c[3]:Lerp(BLACK, 0.35), text = "CORNER", towel = role == "Cutman", loop = "cornerman", role = role,
				arms = { { 0.1, 0.12 }, { 0.1, 0.12 } },
			})
			fig:SetAttribute("Corner", c[1])
			fig:SetAttribute("Slot", i)
		end
	end
	-- (the athletes are added by buildTemplate once the template is parented: buildGymAthletes yields)
end

------------------------------------------------------------------------
-- Template
------------------------------------------------------------------------
local function buildTemplate(kind)
	local spec = SPECS[kind]
	spec.displayName = (Config.Venues and Config.Venues[kind] and Config.Venues[kind].name) or (kind == "Gym" and "Sparring Ring" or kind)
	local arena = Instance.new("Model")
	arena.Name = "Venue_" .. kind
	arena:SetAttribute("RingHalf", spec.half)
	arena:SetAttribute("Venue", kind)
	arena:SetAttribute("VenueTier", spec.tier)
	local S, H = spec.size, spec.height
	local floor = deco(arena, "Floor", V3(S, 2, S), CF(0, -1, 0), spec.floor, spec.floorMat)
	arena.PrimaryPart = floor
	for _, w in ipairs({ { 0, -S / 2, S, 2 }, { 0, S / 2, S, 2 }, { -S / 2, 0, 2, S }, { S / 2, 0, 2, S } }) do
		deco(arena, "Wall", V3(w[3], H, w[4]), CF(w[1], H / 2, w[2]), spec.wall, spec.wallMat)
	end
	if spec.roof then
		deco(arena, "Roof", V3(S, 2, S), CF(0, H, 0), rgb(10, 10, 14))
	end
	local rng = Random.new(#kind * 31)
	buildRing(arena, spec)
	if spec.rows > 0 then
		buildCrowd(arena, spec, rng)
	end
	if spec.bowl then
		buildBowl(arena, spec, Random.new(#kind * 53))
	end
	buildRingside(arena, spec, Random.new(#kind * 71))
	if kind ~= "Gym" then
		buildWalkways(arena, spec, kind)
	end
	buildScreens(arena, spec, kind)
	buildLights(arena, spec, kind)
	buildBroadcast(arena, spec, Random.new(#kind * 97))
	buildCharacter(arena, spec, Random.new(#kind * 13))
	if spec.gym then
		buildGymRoom(arena, spec, Random.new(4242))
	end
	-- anchors (on the surface a fighter stands on)
	local anchors = Instance.new("Folder")
	anchors.Name = "Anchors"
	anchors.Parent = arena
	local function anchor(name, pos)
		deco(anchors, name, V3(1, 1, 1), CF(pos), Color3.new(), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	end
	local RH, c = spec.ringH, spec.half - 2.5
	local entrance = kind == "Gym" and spec.half + 6 or S / 2 - 8
	anchor("RingCenter", V3(0, RH, 0))
	anchor("RedCorner", V3(-c, RH, -c))
	anchor("BlueCorner", V3(c, RH, c))
	anchor("RedNeutral", V3(c, RH, -c))
	anchor("BlueNeutral", V3(-c, RH, c))
	anchor("RedEntrance", V3(0, 0, -entrance))
	anchor("BlueEntrance", V3(0, 0, entrance))
	anchor("RedSteps", V3(0, 0, -(spec.half + 9)))
	anchor("BlueSteps", V3(0, 0, spec.half + 9))
	-- the referee starts between the neutral corners, off the fighters' line
	anchor("RefereeSpot", V3(c * 0.95, RH, -c * 0.15))
	arena.Parent = ServerStorage
	if spec.gym then
		task.spawn(buildGymAthletes, arena)
	end
	return arena
end

function Venues.BuildTemplates()
	for kind in pairs(SPECS) do
		local old = ServerStorage:FindFirstChild("Venue_" .. kind)
		if old then
			old:Destroy()
		end
		local ok, err = pcall(buildTemplate, kind)
		if not ok then
			warn("[Venues] template " .. kind .. " failed:", err)
		end
	end
end

------------------------------------------------------------------------
-- Per-fight dressing (applied to the clone BEFORE it is pivoted into its slot)
------------------------------------------------------------------------
local function sponsorDef(id)
	if not Catalog or type(id) ~= "string" then
		return nil
	end
	local ok, s = pcall(Catalog.Sponsor, id)
	return ok and type(s) == "table" and s or nil
end

local function logoGui(p, face, logo, pps)
	local sg = gui(p, face, pps or 24, 1, 1)
	sg.Name = "SponsorLogo"
	local bg = frame(sg, { Size = UDim2.fromScale(0.94, 0.36), Position = UDim2.fromScale(0.03, 0.32), BackgroundColor3 = c3(logo.bg, BLACK) })
	round(bg, 0.12)
	label(bg, { Size = UDim2.fromScale(0.92, 0.62), Position = UDim2.fromScale(0.04, 0.06), Text = tostring(logo.text or ""), TextColor3 = c3(logo.fg, WHITE) })
	label(bg, { Size = UDim2.fromScale(0.92, 0.26), Position = UDim2.fromScale(0.04, 0.7), Text = tostring(logo.glyph or ""), TextColor3 = c3(logo.fg, WHITE), Font = Enum.Font.GothamBold, TextTransparency = 0.2 })
	return sg
end

local function applySponsors(arena, spec, sponsors)
	local names = {}
	if type(sponsors) ~= "table" then
		return names
	end
	for _, slot in ipairs({ "corner", "trunks", "robe", "gear" }) do
		local def = sponsorDef(sponsors[slot])
		if def then
			table.insert(names, string.upper(def.name or def.id))
			if slot == "corner" and type(def.logo) == "table" then
				arena:SetAttribute("CornerSponsor", def.id)
				for _, d in ipairs(arena:GetDescendants()) do
					if d:IsA("BasePart") and (d.Name == "Pad" or (d.Name == "TurnbucklePad" and d:GetAttribute("RopeTier") == 2)) then
						local old = d:FindFirstChild("PadPrint")
						if old then
							old:Destroy()
						end
						logoGui(d, FACE.Front, def.logo, d.Name == "Pad" and 24 or 30)
					elseif d.Name == "RingSkirt" and d:IsA("BasePart") and (d:GetAttribute("Side") or 0) % 2 == 1 then
						local bgc, fgc = c3(def.logo.bg, BLACK), c3(def.logo.fg, WHITE)
						skirtPrint(d, tostring(def.logo.text or def.name), "OFFICIAL CORNER PARTNER", bgc, fgc, spec.ledSkirt)
					elseif d.Name == "ApronPrint" and d:IsA("SurfaceGui") then
						local t = d:FindFirstChild("Text")
						if t then
							t.Text = tostring(def.logo.text or def.name) .. "  -  WCB"
							t.TextColor3 = c3(def.logo.fg, WHITE)
						end
					end
				end
			end
		end
	end
	return names
end

local function applyTitle(arena, spec, stakes, rng)
	local orgs = table.concat(stakes, "  -  ")
	local logo = arena:FindFirstChild("CanvasLogo")
	if logo then
		canvasLogo(logo, "WORLD CHAMPIONSHIP", #stakes > 1 and "UNDISPUTED" or (stakes[1] or "TITLE"), orgs, rgb(200, 160, 40), rgb(30, 30, 34))
	end
	local half, RH = spec.half, spec.ringH
	local E = half + 3.2
	-- belt table at ringside, beside the red walkway
	local tbl = ringTable(arena, "BeltTable", CFrame.lookAt(V3(9, 0, -(E + 2.2)), V3(9, 0, 0)), 3 + #stakes * 2.2, rgb(20, 20, 24), "WORLD TITLE")
	for i, org in ipairs(stakes) do
		local oc = ORG_COLORS[org] or { strap = BLACK, accent = GOLD }
		local x = 9 + (i - (#stakes + 1) / 2) * 2.2
		local base = CFrame.lookAt(V3(x, 3.1, -(E + 2.0)), V3(x, 3.1, 0))
		prop(tbl, "BeltStand", V3(0.2, 0.9, 0.2), base * CF(0, -0.4, 0.2), rgb(40, 40, 44), M.Metal)
		prop(tbl, "BeltStrap", V3(2.0, 0.65, 0.12), base * CF(0, 0.2, 0), oc.strap, M.Leather)
		local plate = prop(tbl, "BeltPlate", V3(0.14, 1.15, 1.15), base * CF(0, 0.2, -0.08) * CFrame.Angles(0, math.rad(90), 0), oc.accent, M.Foil)
		plate.Shape = Enum.PartType.Cylinder
		for _, sx in ipairs({ -0.75, 0.75 }) do
			prop(tbl, "BeltSidePlate", V3(0.35, 0.5, 0.06), base * CF(sx, 0.2, -0.08), oc.accent, M.Foil)
		end
		local sg = gui(plate, FACE.Right, 60, 1, 1)
		label(sg, { Size = UDim2.fromScale(0.6, 0.3), Position = UDim2.fromScale(0.2, 0.35), Text = org, TextColor3 = oc.strap })
	end
	-- org banners hang over the four stands (or from the truss in smaller rooms)
	local r = spec.rows > 0 and (spec.rowStart + spec.rows * spec.rowGap * 0.5) or (half + 8)
	local y = math.min(spec.height - 8, spec.rows * spec.rowRise + 20)
	local rigBottom = (spec.rigY or 40) - 0.7
	if not spec.roof then
		-- open-air venue (the stadium): nothing overhead but the light rig, so the banners hang from its
		-- four truss corners (diagonal angles below put them exactly under the corner nodes)
		r = (half + 3) * math.sqrt(2)
		y = rigBottom - 6.4
	end
	for i = 1, 4 do
		local org = stakes[(i - 1) % #stakes + 1]
		local oc = ORG_COLORS[org] or { strap = BLACK, accent = GOLD }
		local a = (i - 1) * math.pi / 2 + math.pi / 4
		local pos = V3(math.sin(a) * r, y, math.cos(a) * r)
		local b = prop(arena, "OrgBanner", V3(6, 12, 0.15), CFrame.lookAt(pos, V3(0, y, 0)), oc.strap, M.Fabric, { CastShadow = false })
		local sg = gui(b, FACE.Front, 12, 1, 1)
		label(sg, { Size = UDim2.fromScale(0.86, 0.24), Position = UDim2.fromScale(0.07, 0.12), Text = org, TextColor3 = oc.accent })
		label(sg, { Size = UDim2.fromScale(0.86, 0.1), Position = UDim2.fromScale(0.07, 0.42), Text = "WORLD CHAMPIONSHIP", TextColor3 = WHITE, Font = Enum.Font.GothamBold })
		local disc = frame(sg, { Size = UDim2.fromScale(0.5, 0.25), Position = UDim2.fromScale(0.25, 0.6), BackgroundColor3 = oc.accent })
		round(disc, 0.5)
		local top = spec.roof and spec.height - 1 or rigBottom
		rod(arena, "BannerWire", pos + V3(0, 6, 0), V3(pos.X, top, pos.Z), 0.06, rgb(30, 30, 30), M.Metal, { CastShadow = false })
	end
	-- title fights get gold top ropes
	for _, d in ipairs(arena:GetChildren()) do
		if d.Name == "Rope" and d:GetAttribute("RopeTier") == 3 then
			d.Color = rgb(230, 180, 40)
			for _, b in ipairs(d:GetChildren()) do
				if b:IsA("Beam") then
					b.Color = ColorSequence.new(b.Name == "RopeShine" and rgb(255, 235, 150) or rgb(230, 180, 40))
				end
			end
		end
	end
end

-- crowd size follows the player's popularity; supporters wear the red corner and hold signs
local function applyCrowd(arena, spec, popularity, supporters, nick, title, seed)
	local crowd = arena:FindFirstChild("Crowd")
	if not crowd then
		return
	end
	local rng = Random.new(seed)
	local keep = title and 1 or math.clamp(0.42 + (popularity or 0) / 100 * 0.75, 0.42, 1)
	local fans = {}
	for _, fan in ipairs(crowd:GetChildren()) do
		if fan.Name == "Fan" and fan:IsA("BasePart") then
			if keep < 1 and not fan:GetAttribute("VIP") and rng:NextNumber() > keep then
				fan:Destroy()
			else
				table.insert(fans, fan)
			end
		end
	end
	-- the upper bowl reads the same share from the arena attribute (VenueFX)
	arena:SetAttribute("CrowdShare", math.floor(keep * 100) / 100)
	local share = math.clamp(tonumber(supporters) or 0, 0, 1)
	if share <= 0 or #fans == 0 then
		return
	end
	local reds = { rgb(200, 25, 30), rgb(170, 20, 26), rgb(230, 50, 50), rgb(240, 240, 240) }
	local supporterList = {}
	for _, fan in ipairs(fans) do
		-- supporters bunch up on the red side of the house
		local z = fan.Position.Z
		local p = share * (z < 0 and 0.85 or 0.25)
		if rng:NextNumber() < p then
			fan.Color = reds[rng:NextInteger(1, #reds)]
			for _, arm in ipairs(fan:GetChildren()) do
				if arm.Name == "ArmL" or arm.Name == "ArmR" then
					arm.Color = fan.Color
				end
			end
			fan:SetAttribute("Supporter", true)
			table.insert(supporterList, fan)
		end
	end
	local signs = math.min(#supporterList, math.floor(2 + share * 14))
	local texts = { "GO %s!", "%s #1", "%s TIME", "WE LOVE %s", "%s!!!" }
	for i = 1, signs do
		local fan = table.remove(supporterList, rng:NextInteger(1, #supporterList))
		local who = (type(nick) == "string" and nick ~= "") and string.upper(nick) or "RED CORNER"
		local s = prop(fan, "FanSign", V3(2.6, 1.5, 0.1), fan.CFrame * CF(0, 3.3, -0.3), rgb(250, 250, 245), M.SmoothPlastic, { CastShadow = false })
		for _, face in ipairs({ FACE.Front, FACE.Back }) do
			local sg = gui(s, face, 30, 1, 1)
			label(sg, { Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1), Text = string.format(texts[(i - 1) % #texts + 1], who), TextColor3 = rgb(190, 20, 26), Font = Enum.Font.PermanentMarker })
		end
		if i % 2 == 0 then
			s.Color = rgb(255, 220, 60)
		end
	end
end

-- the sparring room follows the gym facility tier (Config.GymTiers 1..4)
local function applyGymTier(arena, spec, tier, rng)
	local H, S = spec.height, spec.size
	local half = S / 2
	local wallCol = ({ rgb(78, 74, 72), rgb(120, 124, 132), rgb(36, 38, 46), rgb(28, 26, 30) })[tier]
	for _, w in ipairs(arena:GetChildren()) do
		if w.Name == "Wall" and w:IsA("BasePart") then
			w.Color = wallCol
			w.Material = tier >= 3 and M.SmoothPlastic or M.Brick
		end
	end
	local dress = Instance.new("Folder")
	dress.Name = "TierDressing"
	dress:SetAttribute("GymTier", tier)
	dress.Parent = arena
	if tier == 1 then
		-- bare bulbs, water stains, one dying tube
		for _, p in ipairs({ V3(-18, H - 3, -14), V3(18, H - 3, 14), V3(-20, H - 3, 18) }) do
			rod(dress, "BulbCord", p, p + V3(0, 2.5, 0), 0.05, rgb(20, 20, 20), M.Fabric)
			local bulb = prop(dress, "BareBulb", V3(0.6, 0.6, 0.6), CF(p), rgb(255, 214, 140), M.Neon, { CastShadow = false })
			bulb.Shape = Enum.PartType.Ball
			pointLight(bulb, rgb(255, 196, 120), 18, 0.45, false)
		end
		for _, w in ipairs(arena:GetChildren()) do
			if w.Name == "Wall" and w:IsA("BasePart") and w.Size.Y >= H - 1 then
				local face = w.Position.Z < 0 and FACE.Back or (w.Position.Z > 0 and math.abs(w.Position.X) < 1 and FACE.Front or (w.Position.X < 0 and FACE.Right or FACE.Left))
				local sg = gui(w, face, 2, 1, 1)
				sg.Name = "Grime"
				for _ = 1, 5 do
					local f = frame(sg, { Size = UDim2.fromScale(0.04 + rng:NextNumber() * 0.06, 0.2 + rng:NextNumber() * 0.4), Position = UDim2.fromScale(rng:NextNumber() * 0.9, 0), BackgroundColor3 = rgb(60, 50, 35), BackgroundTransparency = 0.82 })
					local g = Instance.new("UIGradient")
					g.Rotation = 90
					g.Transparency = NumberSequence.new(0, 1)
					g.Parent = f
				end
			end
		end
		for _, d in ipairs(arena:GetChildren()) do
			if d.Name == "Fluorescent" then
				tag(d, "NeonFlicker")
				break
			end
		end
	end
	if tier >= 2 then
		for i, z in ipairs({ -12, 12 }) do
			local b = prop(dress, "SponsorBanner", V3(0.15, 4, 10), CF(-half + 1.2, 16, z), i == 1 and rgb(20, 60, 190) or rgb(200, 25, 30), M.Fabric, { CastShadow = false })
			local sg = gui(b, FACE.Right, 16, 1, 1)
			label(sg, { Size = UDim2.fromScale(0.9, 0.6), Position = UDim2.fromScale(0.05, 0.2), Text = i == 1 and "WCB PRO SHOP" or "FUEL & GO", TextColor3 = WHITE })
		end
		for _, z in ipairs({ -1, 1 }) do
			local strip = prop(dress, "LEDStrip", V3(S - 6, 0.2, 0.2), CF(0, H - 1.4, z * (half - 1.3)), rgb(60, 140, 255), M.Neon, { CastShadow = false })
			pointLight(strip, rgb(80, 150, 255), 16, 0.35, false)
		end
	end
	if tier >= 3 then
		for k = 0, 3 do
			prop(dress, "WallPad", V3(0.6, 6, 7), CF(-half + 1.4, 3.6, -13 + k * 8.6), rgb(26, 26, 32), M.Leather)
		end
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			local p = V3(c[1] * 14, H - 1.6, c[2] * 14)
			blob(dress, "MotionCam", V3(1.2, 0.8, 1.2), CF(p), rgb(20, 20, 24), M.Glass)
			local dot = prop(dress, "MotionCamDot", V3(0.2, 0.2, 0.2), CF(p - V3(0, 0.38, 0)), rgb(255, 30, 30), M.Neon, { CastShadow = false })
			dot.Shape = Enum.PartType.Ball
		end
		local tele = prop(dress, "Telemetry", V3(10, 5.6, 0.3), CF(-14, 12, half - 1.4), rgb(14, 14, 18), M.Metal)
		local sg = gui(tele, FACE.Front, 24, 0, 1.4)
		sg.Name = "Screen"
		local bg = frame(sg, { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(8, 12, 22) })
		label(bg, { Name = "Header", Size = UDim2.fromScale(1, 0.16), Text = "SPORTS SCIENCE  -  LIVE TRACKING", TextColor3 = rgb(0, 200, 220), Font = Enum.Font.GothamBold })
		for i, n in ipairs({ "PUNCHES", "HEAD", "BODY", "STAMINA" }) do
			label(bg, { Name = "Key" .. i, Size = UDim2.fromScale(0.4, 0.15), Position = UDim2.fromScale(0.05, 0.2 + (i - 1) * 0.19), Text = n, TextColor3 = rgb(160, 180, 200), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold })
			label(bg, { Name = "Val" .. i, Size = UDim2.fromScale(0.45, 0.15), Position = UDim2.fromScale(0.5, 0.2 + (i - 1) * 0.19), Text = "--", TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Right })
		end
		for _, d in ipairs(arena:GetChildren()) do
			if d.Name == "Mat" then
				d.Color = rgb(24, 24, 30)
			end
		end
	end
	if tier >= 4 then
		for _, x in ipairs({ -1, 1 }) do
			prop(dress, "GoldTrim", V3(0.2, 0.35, S - 4), CF(x * (half - 1.1), 8.5, 0), rgb(220, 175, 60), M.Foil, { CastShadow = false })
		end
		for k = 0, 3 do
			local p = prop(dress, "TitlePhoto", V3(3.4, 4.4, 0.15), CF(-15 + k * 10, 16.2, -half + 1.2), rgb(220, 175, 60), M.Foil, { CastShadow = false })
			local sg = gui(p, FACE.Back, 24, 1, 1)
			local inner = frame(sg, { Size = UDim2.fromScale(0.84, 0.88), Position = UDim2.fromScale(0.08, 0.06), BackgroundColor3 = rgb(30, 30, 34) })
			label(inner, { Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.72), Text = "WORLD CHAMPION", TextColor3 = rgb(255, 215, 90) })
			local fig = frame(inner, { Size = UDim2.fromScale(0.4, 0.5), Position = UDim2.fromScale(0.3, 0.15), BackgroundColor3 = rgb(120, 90, 70) })
			round(fig, 0.3)
		end
		local media = prop(dress, "MediaWall", V3(14, 8, 0.3), CF(12, 4.5, half - 1.5), WHITE, M.Fabric)
		local sg = gui(media, FACE.Front, 12, 1, 1)
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromScale(0.24, 0.16)
		grid.CellPadding = UDim2.fromScale(0.01, 0.01)
		grid.Parent = sg
		for k = 1, 24 do
			label(sg, { Text = k % 2 == 0 and "WCB" or "CHAMP", TextColor3 = k % 2 == 0 and rgb(190, 20, 26) or rgb(20, 20, 24) })
		end
		local banner = prop(dress, "ChampionBanner", V3(0.15, 3, 14), CF(half - 1.3, 18.5, 0), rgb(20, 20, 24), M.Fabric, { CastShadow = false })
		local bsg = gui(banner, FACE.Left, 12, 1, 1)
		label(bsg, { Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.15), Text = "HOME OF THE CHAMPION", TextColor3 = rgb(255, 215, 90) })
	end
	-- more people train around better rooms; extra onlookers / athletes already exist, drop the
	-- surplus (2 athletes in a tier 1 room up to 4 at tier 3+); cutmen only work tier 3+ corners
	local keep = 1 + tier
	local keepAthletes = math.clamp(tier + 1, 2, 4)
	local doomed = {}
	for _, d in ipairs(arena:GetDescendants()) do
		if d:IsA("Model") then
			local slot = d:GetAttribute("Slot") or 0
			if (d.Name == "Onlooker" and slot > keep) or (d.Name == "Cornerman" and tier < 3 and slot >= 2)
				or (d.Parent and d.Parent.Name == "Athletes" and slot > keepAthletes) then
				table.insert(doomed, d)
			end
		end
	end
	for _, d in ipairs(doomed) do
		d:Destroy()
	end
end

local count = 0
-- opts (all optional): ringLevel (Gym ring 1..3), stakes / playerStakes (org lists), kind (offer kind),
-- popularity (0..100), nick, gymTier (1..4), sponsors ({ [slot] = Catalog.Sponsors id }), supporters (0..1)
function Venues.New(kind, opts)
	opts = type(opts) == "table" and opts or {}
	local template = ServerStorage:FindFirstChild("Venue_" .. tostring(kind)) or ServerStorage:FindFirstChild("Venue_Arena")
	if not template then
		-- templates failed to build: rebuild once rather than failing the fight
		Venues.BuildTemplates()
		template = ServerStorage:FindFirstChild("Venue_" .. tostring(kind)) or ServerStorage:FindFirstChild("Venue_Arena")
	end
	local spec = SPECS[kind] or SPECS.Arena
	count += 1
	local arena = template:Clone()
	arena.Name = "Fight_" .. tostring(kind) .. "_" .. count
	local stakes = {}
	for _, list in ipairs({ opts.stakes, opts.playerStakes }) do
		if type(list) == "table" then
			for _, s in ipairs(list) do
				if type(s) == "string" and not table.find(stakes, s) then
					table.insert(stakes, s)
				end
			end
		end
	end
	local popularity = math.clamp(tonumber(opts.popularity) or 0, 0, 100)
	local supporters = math.clamp(tonumber(opts.supporters) or popularity / 100, 0, 1)
	local gymTier = math.clamp(math.floor(tonumber(opts.gymTier) or 0), 0, 4)
	arena:SetAttribute("Stakes", table.concat(stakes, ","))
	arena:SetAttribute("FightKind", type(opts.kind) == "string" and opts.kind or (kind == "Gym" and "Sparring" or ""))
	arena:SetAttribute("Popularity", math.floor(popularity))
	arena:SetAttribute("PlayerNick", type(opts.nick) == "string" and opts.nick or "")
	arena:SetAttribute("Spar", kind == "Gym")
	arena:SetAttribute("Supporters", math.floor(supporters * 100) / 100)
	-- each dressing step is optional: a failure leaves a plain but working venue
	local function try(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[Venues] " .. name .. ":", err)
		end
	end
	if kind == "Gym" then
		local lv = math.clamp(math.floor(tonumber(opts.ringLevel) or 2), 1, 3)
		if gymTier == 0 then
			gymTier = lv == 1 and 1 or (lv == 2 and 2 or 3)
		end
		arena:SetAttribute("GymTier", gymTier)
		try("ring level", function()
			local canvas = ({ rgb(150, 146, 136), rgb(40, 70, 170), rgb(235, 235, 240) })[lv]
			local ropes = ({
				{ rgb(200, 200, 200), rgb(170, 170, 170), rgb(200, 200, 200) },
				{ RED, WHITE, BLUE },
				{ rgb(255, 200, 40), WHITE, rgb(255, 200, 40) },
			})[lv]
			local sag = ({ 0.45, 0.22, 0.1 })[lv]
			for _, p in ipairs(arena:GetChildren()) do
				if p.Name == "Canvas" then
					p.Color = canvas
					local ringSpec = table.clone(spec)
					ringSpec.canvas = canvas
					ringSpec.wear = ({ 0.95, 0.5, 0.15 })[lv]
					ringSpec.print = lv == 2 and rgb(235, 235, 240) or rgb(40, 40, 46)
					canvasPrint(p, ringSpec, spec.ads, count)
				elseif p.Name == "Rope" then
					local tier = p:GetAttribute("RopeTier") or 1
					local col = ropes[tier] or p.Color
					local s = sag * (tier == 3 and 0.85 or 1)
					p.Color = col
					p:SetAttribute("Sag", s)
					for _, b in ipairs(p:GetChildren()) do
						if b:IsA("Beam") then
							b.Color = ColorSequence.new(b.Name == "RopeShine" and col:Lerp(Color3.new(1, 1, 1), 0.55) or col)
							b.CurveSize0, b.CurveSize1 = s / 0.75, -s / 0.75
						end
					end
				elseif p.Name == "Apron" then
					p.Color = lv == 3 and rgb(160, 20, 25) or rgb(30, 30, 34)
				elseif p.Name == "CanvasLogo" then
					if lv == 1 then
						p:Destroy()
					else
						canvasLogo(p, "SPARRING", lv == 3 and "ELITE" or "WCB", "GYM RING", lv == 3 and rgb(40, 40, 46) or rgb(235, 235, 240), lv == 3 and rgb(200, 160, 40) or rgb(20, 40, 120))
					end
				end
			end
			if lv == 1 then
				-- patched-up canvas
				for i, off in ipairs({ { 3, 2 }, { -4, -3 }, { 5, -5 } }) do
					local tape = prop(arena, "TapePatch", V3(2.2 + i * 0.4, 0.05, 0.6), CF(off[1], spec.ringH + 0.03, off[2]) * CFrame.Angles(0, i, 0), rgb(175, 175, 180), M.Foil)
					tape.CanCollide = false
				end
			end
		end)
		try("gym tier", applyGymTier, arena, spec, gymTier, Random.new(count * 17 + gymTier))
	else
		arena:SetAttribute("GymTier", gymTier)
		local title = #stakes > 0 or opts.kind == "World Title" or opts.kind == "Unification" or opts.kind == "Title Defense"
		local sponsorNames = {}
		try("sponsors", function()
			sponsorNames = applySponsors(arena, spec, opts.sponsors)
		end)
		if #stakes > 0 then
			try("title", applyTitle, arena, spec, stakes, Random.new(count))
		end
		try("crowd", applyCrowd, arena, spec, popularity, supporters, opts.nick, title, count * 7919 + math.floor(popularity))
		-- LED boards scroll the sponsors and the bill
		try("ribbons", function()
			local bill = { "WCB SPORTS", string.upper(spec.displayName or "") }
			for _, n in ipairs(sponsorNames) do
				table.insert(bill, n)
			end
			if #stakes > 0 then
				table.insert(bill, table.concat(stakes, " / ") .. " WORLD CHAMPIONSHIP")
			end
			local text = table.concat(bill, "   -   ") .. "   -   "
			for _, d in ipairs(arena:GetDescendants()) do
				if d.Name == "Text" and d:IsA("TextLabel") and d.Parent and d.Parent.Name == "Ticker" then
					d.Text = string.rep(text, 3)
				end
			end
		end)
	end
	local slot = count % 12
	local before = arena:GetPivot()
	arena:PivotTo(CF(4000 + (slot % 4) * 500, 0, 4000 + math.floor(slot / 4) * 500))
	-- members' bag rigs keep their pivot as a world-space attribute (GymVisuals / Animator read it):
	-- follow the move, and give every copy its own Index so two rooms never share a bag id
	local moved = arena:GetPivot() * before:Inverse()
	for _, d in ipairs(arena:GetDescendants()) do
		if d:IsA("Model") and CollectionService:HasTag(d, "MemberBag") then
			local hook = d:GetAttribute("Hook")
			if typeof(hook) == "Vector3" then
				d:SetAttribute("Hook", moved * hook)
			end
			d:SetAttribute("Index", "venue" .. count .. "_" .. tostring(d:GetAttribute("Index") or 1))
		end
	end
	arena.Parent = workspace
	return arena
end

return Venues
