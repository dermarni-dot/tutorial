-- Venues: fight-night ring system. Builds one template per venue in ServerStorage and
-- clones it for each fight / sparring session.
--   CommunityCenter  - local ring: small hall, folding chairs, fluorescent lights
--   ClubArena        - local ring: club hall with a few rows of seats
--   Arena            - professional ring: big arena, jumbotron, light rig
--   Stadium          - world title ring: open-air stadium, packed crowd, TV cameras,
--                      sweeping spotlights, pyro, giant screens
--   Gym              - sparring ring (instanced copy of a gym ring)
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared:WaitForChild("Looks"))

local Venues = {}

local V3 = Vector3.new
local CF = CFrame.new

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
	local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return part(parent, props)
end

local function sign(p, face, text, bg, fg)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Name = "ScreenText"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg or Color3.fromRGB(10, 10, 14)
	t.BackgroundTransparency = bg and 0 or 1
	t.TextColor3 = fg or Color3.fromRGB(255, 200, 40)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.Parent = sg
	sg.Parent = p
	return t
end

local SPECS = {
	CommunityCenter = {
		size = 110, height = 24, roof = true, half = 10, ringH = 2, rows = 2, rowStart = 18, rowGap = 4.5, rowRise = 0,
		floor = Color3.fromRGB(150, 110, 70), floorMat = Enum.Material.WoodPlanks, wall = Color3.fromRGB(190, 190, 175), wallMat = Enum.Material.Brick,
		canvas = Color3.fromRGB(220, 220, 225), banner = "COMMUNITY BOXING NIGHT", lights = "fluorescent", fill = 0.55, chairs = true,
	},
	ClubArena = {
		size = 150, height = 36, roof = true, half = 11, ringH = 3, rows = 4, rowStart = 22, rowGap = 5, rowRise = 2.2,
		floor = Color3.fromRGB(30, 30, 34), floorMat = Enum.Material.Concrete, wall = Color3.fromRGB(25, 25, 30), wallMat = Enum.Material.Concrete,
		canvas = Color3.fromRGB(225, 225, 230), banner = "CITY CLUB FIGHT NIGHT", lights = "spots", fill = 0.75,
	},
	Arena = {
		size = 220, height = 70, roof = true, half = 12, ringH = 4, rows = 6, rowStart = 26, rowGap = 5, rowRise = 2.5,
		floor = Color3.fromRGB(18, 18, 22), floorMat = Enum.Material.Concrete, wall = Color3.fromRGB(8, 8, 12), wallMat = Enum.Material.SmoothPlastic,
		canvas = Color3.fromRGB(225, 225, 230), banner = "GRAND ARENA", lights = "rig", fill = 0.85, jumbotron = true,
	},
	Stadium = {
		size = 330, height = 90, roof = false, half = 13, ringH = 4.5, rows = 11, rowStart = 30, rowGap = 5.5, rowRise = 3.2,
		floor = Color3.fromRGB(40, 90, 50), floorMat = Enum.Material.Grass, wall = Color3.fromRGB(40, 40, 48), wallMat = Enum.Material.Concrete,
		canvas = Color3.fromRGB(235, 235, 240), banner = "WORLD CHAMPIONSHIP BOXING", lights = "towers", fill = 0.92, jumbotron = true,
		cameras = true, pyro = true, spots = true,
	},
	Gym = {
		size = 70, height = 22, roof = true, half = 10, ringH = 2.5, rows = 0, rowStart = 18, rowGap = 4, rowRise = 0,
		floor = Color3.fromRGB(122, 88, 60), floorMat = Enum.Material.WoodPlanks, wall = Color3.fromRGB(70, 72, 80), wallMat = Enum.Material.Brick,
		canvas = Color3.fromRGB(40, 70, 170), banner = "SPARRING", lights = "fluorescent", fill = 0,
	},
}

local function buildCrowd(arena, spec, rng)
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	crowd.Parent = arena
	local shirts = { { 200, 30, 30 }, { 30, 60, 200 }, { 240, 240, 240 }, { 30, 30, 30 }, { 240, 190, 40 }, { 40, 150, 70 }, { 130, 40, 170 }, { 240, 120, 30 } }
	for side = 0, 3 do
		local rot = CFrame.Angles(0, side * math.pi / 2, 0)
		for row = 0, spec.rows - 1 do
			local dist = spec.rowStart + row * spec.rowGap
			local h = row * spec.rowRise
			local stepColor = spec.chairs and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(35, 35, 42)
			if side == 0 or side == 2 then
				local w = dist - 5
				for _, sx in ipairs({ -1, 1 }) do
					if h > 0 then
						deco(arena, "Stand", V3(w, h + 0.5, spec.rowGap), rot * CF(sx * (5 + w / 2), (h + 0.5) / 2, dist + spec.rowGap / 2), stepColor, Enum.Material.Concrete)
					end
				end
			elseif h > 0 then
				deco(arena, "Stand", V3(dist * 2 + 10, h + 0.5, spec.rowGap), rot * CF(0, (h + 0.5) / 2, dist + spec.rowGap / 2), stepColor, Enum.Material.Concrete)
			end
			local seats = math.floor((dist * 2) / 3.2)
			for i = 0, seats do
				local x = -dist + i * 3.2
				local aisle = (side == 0 or side == 2) and math.abs(x) < 5
				if not aisle and rng:NextNumber() < spec.fill then
					local base = rot * CF(x, h + 0.5, dist + spec.rowGap / 2)
					if spec.chairs then
						deco(arena, "Chair", V3(1.8, 1.6, 1.8), base * CF(0, 0.8, 0.3), Color3.fromRGB(70, 70, 80), Enum.Material.Metal, { CanCollide = false })
					end
					local shirt = shirts[rng:NextInteger(1, #shirts)]
					local fan = deco(crowd, "Fan", V3(1.6, 2, 1), base * CF(0, spec.chairs and 2 or 1, 0), Color3.fromRGB(shirt[1], shirt[2], shirt[3]), nil, { CanCollide = false, CastShadow = false, CanQuery = false })
					local skin = Looks.SkinTones[rng:NextInteger(1, #Looks.SkinTones)]
					local head = deco(fan, "Head", V3(1.2, 1.2, 1.2), base * CF(0, (spec.chairs and 2 or 1) + 1.6, 0), Color3.fromRGB(skin[1], skin[2], skin[3]), nil, { CanCollide = false, CastShadow = false, CanQuery = false })
					head.Shape = Enum.PartType.Ball
				end
			end
		end
	end
end

local function buildRing(arena, spec)
	local half, RH = spec.half, spec.ringH
	deco(arena, "RingBase", V3(half * 2 + 6, RH - 0.4, half * 2 + 6), CF(0, (RH - 0.4) / 2, 0), Color3.fromRGB(20, 20, 20))
	deco(arena, "Apron", V3(half * 2 + 6.4, 0.8, half * 2 + 6.4), CF(0, RH - 0.8, 0), Color3.fromRGB(160, 20, 25), Enum.Material.Fabric)
	deco(arena, "Canvas", V3(half * 2 + 6, 0.4, half * 2 + 6), CF(0, RH - 0.2, 0), spec.canvas, Enum.Material.Fabric)
	local logo = deco(arena, "CanvasLogo", V3(10, 0.05, 10), CF(0, RH + 0.03, 0), Color3.new(), nil, { Transparency = 1, CanCollide = false })
	sign(logo, Enum.NormalId.Top, "WCB", nil, Color3.fromRGB(200, 25, 30))
	local postColor = { Color3.fromRGB(200, 25, 30), Color3.fromRGB(240, 240, 240), Color3.fromRGB(25, 60, 200), Color3.fromRGB(240, 240, 240) }
	local corners = { { -half, -half }, { half, -half }, { half, half }, { -half, half } }
	for i, c in ipairs(corners) do
		deco(arena, "Post", V3(0.8, 5.5, 0.8), CF(c[1], RH + 2.75, c[2]), postColor[i], Enum.Material.Metal)
		deco(arena, "Pad", V3(1.4, 4, 1.4), CF(c[1] * 0.97, RH + 2.5, c[2] * 0.97), postColor[i], nil, { CanCollide = false })
	end
	local ropeColors = { Color3.fromRGB(200, 25, 30), Color3.fromRGB(240, 240, 240), Color3.fromRGB(25, 60, 200) }
	for ri, h in ipairs({ 1.6, 3.0, 4.4 }) do
		for side = 1, 4 do
			local a, b = corners[side], corners[side % 4 + 1]
			local pa, pb = V3(a[1], RH + h, a[2]), V3(b[1], RH + h, b[2])
			deco(arena, "Rope", V3(0.25, 0.25, (pb - pa).Magnitude), CFrame.lookAt((pa + pb) / 2, pb), ropeColors[ri], Enum.Material.Fabric, { CanCollide = false })
		end
	end
	for _, w in ipairs({ { 0, -half, half * 2, 0.5 }, { 0, half, half * 2, 0.5 }, { -half, 0, 0.5, half * 2 }, { half, 0, 0.5, half * 2 } }) do
		deco(arena, "RingWall", V3(w[3], 12, w[4]), CF(w[1], RH + 6, w[2]), Color3.new(), nil, { Transparency = 1 })
	end
	for _, z in ipairs({ -1, 1 }) do
		for i = 1, 3 do
			deco(arena, "Step", V3(4, i * (RH / 3), 1.5), CF(0, i * (RH / 3) / 2, z * (half + 2.25 + (4 - i) * 1.5)), Color3.fromRGB(40, 40, 40))
		end
	end
end

local function buildTemplate(kind)
	local spec = SPECS[kind]
	local arena = Instance.new("Model")
	arena.Name = "Venue_" .. kind
	arena:SetAttribute("RingHalf", spec.half)
	arena:SetAttribute("Venue", kind)
	local S, H = spec.size, spec.height
	local floor = deco(arena, "Floor", V3(S, 2, S), CF(0, -1, 0), spec.floor, spec.floorMat)
	arena.PrimaryPart = floor
	for _, w in ipairs({ { 0, -S / 2, S, 2 }, { 0, S / 2, S, 2 }, { -S / 2, 0, 2, S }, { S / 2, 0, 2, S } }) do
		deco(arena, "Wall", V3(w[3], H, w[4]), CF(w[1], H / 2, w[2]), spec.wall, spec.wallMat)
	end
	if spec.roof then
		deco(arena, "Roof", V3(S, 2, S), CF(0, H, 0), Color3.fromRGB(10, 10, 14))
	end
	buildRing(arena, spec)
	local rng = Random.new(#kind * 31)
	if spec.rows > 0 then
		buildCrowd(arena, spec, rng)
	end
	-- walkways & tunnels
	local reach = S / 2 - 4
	for _, z in ipairs({ -1, 1 }) do
		if kind ~= "Gym" then
			deco(arena, "Walkway", V3(6, 0.2, reach - spec.half - 4), CF(0, 0.1, z * (spec.half + 4 + (reach - spec.half - 4) / 2)),
				z < 0 and Color3.fromRGB(150, 20, 25) or Color3.fromRGB(20, 40, 150), Enum.Material.Neon, { Transparency = 0.4, CanCollide = false })
			local tunnel = deco(arena, "Tunnel", V3(16, 14, 2), CF(0, 7, z * (reach + 1)), Color3.fromRGB(10, 10, 12))
			sign(tunnel, z < 0 and Enum.NormalId.Back or Enum.NormalId.Front, z < 0 and "RED CORNER" or "BLUE CORNER", Color3.fromRGB(10, 10, 12), z < 0 and Color3.fromRGB(230, 40, 40) or Color3.fromRGB(60, 110, 255))
			for i = 0, 2 do
				local glow = deco(arena, "WalkLight", V3(1, 1, 1), CF(0, 6, z * (spec.half + 10 + i * (reach - spec.half - 10) / 3)), Color3.new(), nil, { Transparency = 1, CanCollide = false })
				local pl = Instance.new("PointLight")
				pl.Range = 20
				pl.Brightness = 1.3
				pl.Color = z < 0 and Color3.fromRGB(255, 120, 110) or Color3.fromRGB(130, 160, 255)
				pl.Parent = glow
			end
			if spec.pyro then
				local pyroFolder = arena:FindFirstChild("Pyro") or Instance.new("Folder")
				pyroFolder.Name = "Pyro"
				pyroFolder.Parent = arena
				for _, x in ipairs({ -6, 6 }) do
					local emitterPart = deco(pyroFolder, z < 0 and "PyroRed" or "PyroBlue", V3(1, 1, 1), CF(x, 1, z * (reach - 6)), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
					local pe = Instance.new("ParticleEmitter")
					pe.Enabled = false
					pe.Rate = 120
					pe.Lifetime = NumberRange.new(0.6, 1.1)
					pe.Speed = NumberRange.new(35, 50)
					pe.SpreadAngle = Vector2.new(8, 8)
					pe.LightEmission = 1
					pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0.5) })
					pe.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 80, 20))
					pe.EmissionDirection = Enum.NormalId.Top
					pe.Parent = emitterPart
				end
			end
		end
	end
	-- banner / screens
	local banner = deco(arena, "Banner", V3(math.min(80, S * 0.5), 8, 1), CF(0, H * 0.55, S / 2 - 1.5), Color3.fromRGB(14, 14, 18))
	sign(banner, Enum.NormalId.Front, spec.banner, Color3.fromRGB(14, 14, 18), Color3.fromRGB(255, 200, 40))
	if spec.jumbotron then
		local y = kind == "Stadium" and 46 or 30
		-- hanging screen must not shadow the ring from the light rig above it
		local screen = deco(arena, "Jumbotron", V3(18, 9, 18), CF(0, y, 0), Color3.fromRGB(10, 10, 10), nil, { CastShadow = false })
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
			sign(screen, face, "FIGHT NIGHT", Color3.fromRGB(10, 10, 14), Color3.fromRGB(255, 200, 40))
		end
		deco(arena, "ScreenCable", V3(0.3, 90 - y, 0.3), CF(0, y + (90 - y) / 2, 0), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, { CanCollide = false, CastShadow = false })
	end
	if kind == "Stadium" then
		for _, x in ipairs({ -1, 1 }) do
			local big = deco(arena, "BigScreen", V3(1, 30, 52), CF(x * (S / 2 - 4), 40, 0), Color3.fromRGB(10, 10, 12))
			sign(big, x < 0 and Enum.NormalId.Right or Enum.NormalId.Left, "WORLD TITLE FIGHT", Color3.fromRGB(10, 10, 14), Color3.fromRGB(255, 200, 40))
		end
	end
	-- lighting
	if spec.lights == "fluorescent" then
		for x = -1, 1 do
			for z = -1, 1, 2 do
				local l = deco(arena, "Fluorescent", V3(10, 0.4, 1.5), CF(x * 14, H - 2, z * 10), Color3.fromRGB(235, 245, 255), Enum.Material.Neon, { CastShadow = false })
				local pl = Instance.new("PointLight")
				pl.Range = 26
				pl.Brightness = 0.55 -- six tubes stack up; brighter blows out pale skin and the white pads
				pl.Parent = l
			end
		end
	else
		-- light range is capped at 60 studs, so the rig hangs low enough to reach the canvas
		local rigY = kind == "Stadium" and 52 or (kind == "Arena" and 40 or 28)
		local rig = deco(arena, "LightRig", V3(30, 1.5, 30), CF(0, rigY, 0), Color3.fromRGB(30, 30, 30), Enum.Material.DiamondPlate)
		rig.CanCollide = false
		for _, c in ipairs({ { -10, -10 }, { 10, -10 }, { 10, 10 }, { -10, 10 }, { 0, 0 } }) do
			-- the lamp housing must not cast shadows or it would block its own shadowed light
			local l = deco(arena, "Lamp", V3(3, 1, 3), CF(c[1], rigY - 1, c[2]), Color3.fromRGB(255, 255, 240), Enum.Material.Neon, { CastShadow = false })
			local sl = Instance.new("SpotLight")
			sl.Face = Enum.NormalId.Bottom
			sl.Angle = 55
			sl.Range = math.min(60, rigY + 20)
			sl.Brightness = 3.2
			sl.Shadows = true
			sl.Parent = l
		end
	end
	if spec.lights == "towers" then
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			local x, z = c[1] * (S / 2 - 12), c[2] * (S / 2 - 12)
			deco(arena, "Tower", V3(2, 80, 2), CF(x, 40, z), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
			local head = deco(arena, "TowerLights", V3(10, 5, 2), CFrame.lookAt(V3(x, 80, z), V3(0, 0, 0)), Color3.fromRGB(255, 255, 230), Enum.Material.Neon, { CastShadow = false })
			local sl = Instance.new("SpotLight")
			sl.Face = Enum.NormalId.Front
			sl.Angle = 45
			sl.Range = 60
			sl.Brightness = 2
			sl.Parent = head
		end
	end
	if spec.spots then
		local spots = Instance.new("Folder")
		spots.Name = "Spots"
		spots.Parent = arena
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			-- follow spots close enough (< 60 studs) for their beams to reach the ring
			local p = deco(spots, "Spot", V3(1.5, 1.5, 3), CF(math.cos(a) * 34, 42, math.sin(a) * 34), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, { CanCollide = false, CastShadow = false })
			local sl = Instance.new("SpotLight")
			sl.Face = Enum.NormalId.Front
			sl.Angle = 18
			sl.Range = 60
			sl.Brightness = 6
			sl.Color = i % 2 == 0 and Color3.fromRGB(255, 220, 140) or Color3.fromRGB(140, 180, 255)
			sl.Parent = p
		end
	end
	if spec.cameras then
		for _, c in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
			local x, z = c[1] * (spec.half + 8), c[2] * (spec.half + 8)
			if c[2] ~= 0 then
				x = 10
			end
			local base = CFrame.lookAt(V3(x, 0, z), V3(0, 0, 0))
			for _, leg in ipairs({ -0.6, 0, 0.6 }) do
				deco(arena, "TripodLeg", V3(0.15, 5, 0.15), base * CF(leg, 2.5, leg ~= 0 and 0.4 or -0.5) * CFrame.Angles(0.15, 0, leg * 0.25), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, { CanCollide = false })
			end
			deco(arena, "TVCamera", V3(1.4, 1.4, 3), base * CF(0, 5.6, 0), Color3.fromRGB(25, 25, 28), Enum.Material.Metal, { CanCollide = false })
			local lens = deco(arena, "Lens", V3(0.8, 1, 1), base * CF(0, 5.6, -1.9) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(15, 15, 18), Enum.Material.Glass, { CanCollide = false })
			lens.Shape = Enum.PartType.Cylinder
			local tally = deco(arena, "TallyLight", V3(0.3, 0.3, 0.3), base * CF(0, 6.5, -1), Color3.fromRGB(255, 30, 30), Enum.Material.Neon, { CanCollide = false })
			tally.Name = "TallyLight"
		end
		local desk = deco(arena, "CommentaryDesk", V3(14, 3, 3), CF(-(spec.half + 10), 1.5, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(20, 20, 26))
		sign(desk, Enum.NormalId.Back, "WCB LIVE", Color3.fromRGB(20, 20, 26), Color3.fromRGB(255, 60, 60))
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
	arena.Parent = ServerStorage
	return arena
end

function Venues.BuildTemplates()
	for kind in pairs(SPECS) do
		local old = ServerStorage:FindFirstChild("Venue_" .. kind)
		if old then
			old:Destroy()
		end
		buildTemplate(kind)
	end
end

local count = 0
-- opts.ringLevel restyles the sparring ring to match the player's gym upgrade
function Venues.New(kind, opts)
	opts = opts or {}
	local template = ServerStorage:FindFirstChild("Venue_" .. kind) or ServerStorage:FindFirstChild("Venue_Arena")
	count += 1
	local arena = template:Clone()
	arena.Name = "Fight_" .. kind .. "_" .. count
	local slot = count % 12
	arena:PivotTo(CF(4000 + (slot % 4) * 500, 0, 4000 + math.floor(slot / 4) * 500))
	if kind == "Gym" and opts.ringLevel then
		local lv = opts.ringLevel
		local canvas = ({ Color3.fromRGB(150, 146, 136), Color3.fromRGB(40, 70, 170), Color3.fromRGB(235, 235, 240) })[lv] or Color3.fromRGB(40, 70, 170)
		local ropes = ({
			{ Color3.fromRGB(200, 200, 200), Color3.fromRGB(170, 170, 170), Color3.fromRGB(200, 200, 200) },
			{ Color3.fromRGB(200, 25, 30), Color3.fromRGB(240, 240, 240), Color3.fromRGB(25, 60, 200) },
			{ Color3.fromRGB(255, 200, 40), Color3.fromRGB(240, 240, 240), Color3.fromRGB(255, 200, 40) },
		})[lv] or {}
		local ropeIndex = 0
		for _, p in ipairs(arena:GetChildren()) do
			if p.Name == "Canvas" then
				p.Color = canvas
				p.Material = lv == 1 and Enum.Material.Fabric or Enum.Material.Fabric
			elseif p.Name == "Rope" then
				ropeIndex += 1
				p.Color = ropes[math.floor((ropeIndex - 1) / 4) % 3 + 1] or p.Color
			elseif p.Name == "Apron" then
				p.Color = lv == 3 and Color3.fromRGB(160, 20, 25) or Color3.fromRGB(30, 30, 34)
			elseif p.Name == "CanvasLogo" then
				p:Destroy()
			end
		end
		if lv == 1 then
			-- patched-up canvas
			for i, off in ipairs({ { 3, 2 }, { -4, -3 }, { 5, -5 } }) do
				local tape = Instance.new("Part")
				tape.Name = "TapePatch"
				tape.Anchored = true
				tape.CanCollide = false
				tape.Size = V3(2.2 + i * 0.4, 0.05, 0.6)
				tape.Color = Color3.fromRGB(175, 175, 180)
				tape.Material = Enum.Material.Foil
				local c = arena:FindFirstChild("Anchors") and arena.Anchors:FindFirstChild("RingCenter")
				if c then
					tape.CFrame = CF(c.Position + V3(off[1], 0.03, off[2])) * CFrame.Angles(0, i, 0)
				end
				tape.Parent = arena
			end
		end
	end
	arena.Parent = workspace
	return arena
end

return Venues
