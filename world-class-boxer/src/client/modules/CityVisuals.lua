-- CityVisuals: the city reflects YOUR career. Everything here is client-side (workspace.LocalCity
-- plus local edits to the shared city), so every player sees their own success:
--   * homes: the penthouse terrace at Riverside Apartments, your two-storey house on Oak Street,
--     the Hillcrest villa with pool and garage (the estate gate swings open for you), SOLD signs
--   * cars: your best car in the reserved bay at the gym, the collection at home
--   * sponsors: your deals on the city billboards and in their shop windows
--   * media: your next fight on the arena screen, the ticket marquee and the bus-stop poster,
--     lawn signs and an apartment banner cheering you on
--   * legacy: your stars on the Walk of Fame, a bronze statue on Champions Plaza, your case in the
--     Hall of Fame museum and the induction banner outside
--   * the Elite Performance Center opens up (shutters, lights, cryo, plunge pools, sports science
--     lab, motion capture cameras that track you) once your gym reaches the Elite tier
--   * fans gather by the gym, the plaza, the arena and your home (count grows with popularity),
--     paparazzi for champions; pedestrians and traffic on Main Street; other players' fame tags;
--     the mountain camp's cold air
-- Refresh(P) rebuilds each piece only when its key changes; one Heartbeat loop animates fans,
-- pedestrians and traffic near the camera (<= 30 Hz).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))
local CityProps = require(Shared:WaitForChild("CityProps"))
local State = require(script.Parent:WaitForChild("State"))
local CityStores = require(script.Parent:WaitForChild("CityStores"))

local CityVisuals = {}

local player = Players.LocalPlayer
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material

local part = CityProps.Part
local cyl = CityProps.Cyl
local ball = CityProps.Ball
local blob = CityProps.Blob
local wedge = CityProps.Wedge
local gui = CityProps.Gui
local label = CityProps.Label
local frame = CityProps.Frame
local tag = CityProps.Tag
local rgb = CityProps.RGB

local GOLD = Color3.fromRGB(255, 196, 40)
local WHITE = Color3.fromRGB(240, 240, 238)
local DARK = Color3.fromRGB(24, 24, 28)

local root -- workspace.LocalCity
local groups = {} -- name -> { key, folder }
local lastP

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function cityRoot()
	local gym = workspace:FindFirstChild("Gym")
	return gym and gym:FindFirstChild("City")
end

-- the server's anchor for a player-specific build (CityMap site()); nil until it replicates
local function siteCF(name)
	local c = cityRoot()
	local s = c and c:FindFirstChild("Sites")
	local p = s and s:FindFirstChild("Site_" .. name)
	return p and p.CFrame or nil, p
end

local function ensureRoot()
	if root and root.Parent then
		return root
	end
	root = workspace:FindFirstChild("LocalCity")
	if not root then
		root = Instance.new("Folder")
		root.Name = "LocalCity"
		root.Parent = workspace
	end
	return root
end

-- (re)build a named piece only when its key changes; a failing builder warns once per key
local function group(name, key, build)
	local g = groups[name]
	if g and g.key == key and (key == "" or (g.folder and g.folder.Parent)) then
		return g.folder
	end
	if g and g.folder then
		g.folder:Destroy()
	end
	groups[name] = { key = key }
	if key == "" then
		return nil
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = ensureRoot()
	groups[name].folder = f
	local ok, err = pcall(build, f)
	if not ok then
		warn("[CityVisuals] " .. name .. ": " .. tostring(err))
	end
	return f
end

local function surnameOf(P)
	local id = P.identity or {}
	local last = id.last
	if type(last) ~= "string" or last == "" then
		last = tostring(id.name or "Champ"):match("(%S+)$") or "Champ"
	end
	return last
end

local function nickOf(P)
	local n = P.identity and P.identity.nickname
	return (type(n) == "string" and n ~= "") and n or surnameOf(P)
end

local function beltsOf(P)
	local list = {}
	for _, org in ipairs(Config.Orgs) do
		if P.belts and P.belts[org] then
			table.insert(list, org)
		end
	end
	return list
end

local function recText(P)
	local r = (P.tier == 1 and P.amateurRecord) or P.record or {}
	return string.format("%d-%d-%d (%d KO)", r.w or 0, r.l or 0, r.d or 0, r.ko or 0)
end

local function carsOf(owned)
	local list = {}
	for _, id in ipairs(CityProps.CarOrder) do
		if owned and owned[id] then
			table.insert(list, id)
		end
	end
	return list
end

local function gymTierIndex(P)
	if P.gymTier and P.gymTier.index then
		return P.gymTier.index
	end
	local ok, idx = pcall(Catalog.GymTier, P.gym and P.gym.levels, P.owned, P.tier)
	return ok and idx or 1
end

local function trunkColor(P)
	local a = P.appearance and P.appearance.attire
	return rgb(a and a.trunks, Color3.fromRGB(200, 30, 36))
end

local function deal(P, slot)
	local d = P.sponsors and P.sponsors.deals and P.sponsors.deals[slot]
	return type(d) == "table" and d or nil
end

local function nightLight(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Enabled = false
	l.Parent = parent
	tag(l, "NightLight")
	return l
end

local function plant(parent, cf, scale, pot)
	scale = scale or 1
	part(parent, "Planter", V3(1.8, 1.4, 1.8) * scale, cf * CF(0, 0.7 * scale, 0), pot or Color3.fromRGB(70, 70, 76), M.Concrete)
	blob(parent, "PlanterLeaves", V3(2.4, 2.6, 2.4) * scale, cf * CF(0, 2.4 * scale, 0), Color3.fromRGB(56, 120, 60), M.Grass)
end

-- every TextLabel under a part's SurfaceGuis (server signs), original text remembered once
local originals = setmetatable({}, { __mode = "k" })
local function setLabel(lbl, text)
	if originals[lbl] == nil then
		originals[lbl] = lbl.Text
	end
	lbl.Text = text or originals[lbl]
end

local function firstLabel(p, name)
	if name then
		local l = p:FindFirstChild(name, true)
		if l and l:IsA("TextLabel") then
			return l
		end
	end
	for _, d in ipairs(p:GetDescendants()) do
		if d:IsA("TextLabel") then
			return d
		end
	end
	return nil
end

local function screens(kind)
	local out = {}
	for _, p in ipairs(CollectionService:GetTagged("CityScreen")) do
		if p:GetAttribute("Kind") == kind and p:IsDescendantOf(workspace) then
			table.insert(out, p)
		end
	end
	return out
end

-- replace a server SurfaceGui with a local one (or restore it when build is nil)
local function overlay(p, guiName, build)
	local mine = p:FindFirstChild("LocalOverlay")
	if mine then
		mine:Destroy()
	end
	for _, sg in ipairs(p:GetChildren()) do
		if sg:IsA("SurfaceGui") and sg.Name ~= "LocalOverlay" and (guiName == nil or sg.Name == guiName or guiName == "*") then
			sg.Enabled = build == nil
		end
	end
	if build then
		local sg = Instance.new("SurfaceGui")
		sg.Name = "LocalOverlay"
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 12
		sg.LightInfluence = 0.1
		sg.MaxDistance = 900
		sg.Parent = p
		build(sg)
	end
end

------------------------------------------------------------------------
-- Homes
------------------------------------------------------------------------
local function apartmentDressing(f, P)
	local roof = siteCF("ApartmentRoof")
	if roof then
		-- penthouse terrace: string lights, loungers, umbrella table, planters, a grill
		local posts = { { -10, -4 }, { 10, -4 }, { 10, 6 }, { -10, 6 } }
		for _, p in ipairs(posts) do
			part(f, "LightPost", V3(0.25, 5, 0.25), roof * CF(p[1], 2.5, p[2]), DARK, M.Metal)
		end
		for k = 0, 9 do
			local t = k / 9
			ball(f, "StringBulb", 0.45, roof * CF(-10 + t * 20, 4.6 - math.sin(t * math.pi) * 0.8, -4), Color3.fromRGB(255, 220, 150), M.Neon, { shadow = false })
			ball(f, "StringBulb", 0.45, roof * CF(-10 + t * 20, 4.6 - math.sin(t * math.pi) * 0.8, 6), Color3.fromRGB(255, 220, 150), M.Neon, { shadow = false })
		end
		local glow = part(f, "TerraceGlow", V3(0.2, 0.2, 0.2), roof * CF(0, 4, 1), WHITE, M.SmoothPlastic, { transparency = 1, shadow = false })
		nightLight(glow, Color3.fromRGB(255, 210, 150), 18, 0.9)
		for k = 0, 1 do
			local lc = roof * CF(-6 + k * 3.4, 0, 1) * ANG(0, RAD(180), 0)
			part(f, "Lounger", V3(2, 0.5, 5.5), lc * CF(0, 0.9, 0), WHITE, M.Fabric)
			part(f, "LoungerBack", V3(2, 0.5, 2.2), lc * CF(0, 1.7, 2.2) * ANG(RAD(50), 0, 0), WHITE, M.Fabric)
		end
		local tcf = roof * CF(5, 0, 1)
		cyl(f, "PatioTable", 0.2, 3.4, tcf * CF(0, 2.6, 0) * ANG(0, 0, RAD(90)), Color3.fromRGB(230, 230, 226), M.SmoothPlastic)
		part(f, "UmbrellaPole", V3(0.2, 6, 0.2), tcf * CF(0, 3, 0), DARK, M.Metal)
		blob(f, "Umbrella", V3(7, 1.4, 7), tcf * CF(0, 6, 0), trunkColor(P), M.Fabric)
		part(f, "Grill", V3(2.4, 2.6, 1.6), roof * CF(9, 1.3, 4), DARK, M.Metal)
		for _, x in ipairs({ -12, 12 }) do
			plant(f, roof * CF(x, 0, -2), 1)
		end
		if P.owned and P.owned.HomeGym then
			-- rooftop training: a bag under a frame, against the skyline
			part(f, "RoofBagFrame", V3(0.4, 8, 0.4), roof * CF(-14, 4, 4), DARK, M.Metal)
			part(f, "RoofBagArm", V3(3, 0.4, 0.4), roof * CF(-12.8, 7.8, 4), DARK, M.Metal)
			part(f, "BagChain", V3(0.15, 1.0, 0.15), roof * CF(-11.6, 7.1, 4), Color3.fromRGB(150, 153, 160), M.Metal)
			cyl(f, "RoofBag", 4, 1.8, roof * CF(-11.6, 4.6, 4) * ANG(0, 0, RAD(90)), Color3.fromRGB(150, 24, 30), M.Leather)
		end
	end
	local door = siteCF("HomeApartment")
	if door then
		local plate = part(f, "NamePlate", V3(2.2, 0.8, 0.08), door * CF(2.6, 5.2, 2.0), Color3.fromRGB(200, 160, 70), M.Metal)
		local sg = gui(plate, Enum.NormalId.Front, 60, 0.3, 40)
		label(sg, "PENTHOUSE - " .. surnameOf(P):upper(), { TextColor3 = Color3.fromRGB(40, 28, 10) })
	end
end

local function houseBuild(f, P, base)
	local owned = P.owned or {}
	local wall = Color3.fromRGB(226, 214, 190)
	local trim = WHITE
	local roofC = Color3.fromRGB(70, 66, 70)
	local W, D, H, R = 17, 15, 15, 5.5
	local mainX, mainZ = -3.5, 2.5
	local mb = base * CF(mainX, 0, mainZ)
	part(f, "HouseMain", V3(W, H, D), mb * CF(0, H / 2, 0), wall, M.WoodPlanks, { collide = true })
	part(f, "StoreyBand", V3(W + 0.3, 0.4, D + 0.3), mb * CF(0, H / 2, 0), trim, M.Wood)
	local a = (mb * CF(0, H + R / 2, -D / 4)).Position
	local b = (mb * CF(0, H + R / 2, D / 4)).Position
	local front = (mb * CF(0, 0, -1)).Position - (mb * CF(0, 0, 0)).Position
	wedge(f, "HouseRoof", V3(W + 1.2, R, D / 2 + 0.7), CFrame.lookAt(a, a + front), roofC, M.Slate, { collide = true })
	wedge(f, "HouseRoof", V3(W + 1.2, R, D / 2 + 0.7), CFrame.lookAt(b, b - front), roofC, M.Slate, { collide = true })
	part(f, "Chimney", V3(1.8, 5, 1.8), mb * CF(-W * 0.3, H + R - 0.6, D * 0.18), Color3.fromRGB(130, 70, 56), M.Brick)
	-- garage wing with its door (raised when you own a home gym: the bag hangs inside)
	-- a hollow shell (back, sides, header and jambs) so a raised door really shows what is inside
	local gb = base * CF(9.5, 0, 4)
	part(f, "GarageBack", V3(8, 9, 0.4), gb * CF(0, 4.5, 5.85), wall, M.WoodPlanks, { collide = true })
	for _, sx in ipairs({ -1, 1 }) do
		part(f, "GarageSide", V3(0.4, 9, 12.05), gb * CF(sx * 3.8, 4.5, 0.02), wall, M.WoodPlanks, { collide = true })
		part(f, "GarageJamb", V3(0.4, 6.7, 0.4), gb * CF(sx * 3.4, 3.35, -5.8), wall, M.WoodPlanks, { collide = true })
	end
	part(f, "GarageHeader", V3(7.2, 2.3, 0.4), gb * CF(0, 7.85, -5.8), wall, M.WoodPlanks, { collide = true })
	part(f, "GarageRoof", V3(8.6, 0.5, 12.6), gb * CF(0, 9.2, 0), roofC, M.Slate)
	local gym = owned.HomeGym
	-- the garage is the gym when you own one; otherwise the Garage add-on keeps your second car here
	local showCar = owned.Garage and carsOf(owned)[2] ~= nil and not gym
	local open = gym or showCar
	local door = part(f, "GarageDoor", V3(6.4, open and 2.2 or 6.6, 0.2), gb * CF(0, open and 6.8 or 3.4, -6.05), Color3.fromRGB(236, 236, 232), M.SmoothPlastic, { collide = not open })
	local dsg = gui(door, Enum.NormalId.Front, 20, 0.6, 120)
	for k = 1, 5 do
		frame(dsg, { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, k / 6), BackgroundColor3 = Color3.fromRGB(190, 190, 186) })
	end
	if open then
		part(f, "GarageFloor", V3(7.2, 0.1, 11.4), gb * CF(0, 0.2, 0), gym and Color3.fromRGB(32, 32, 35) or Color3.fromRGB(120, 120, 118), gym and M.Rubber or M.Concrete)
		if gym then
			part(f, "GarageBagChain", V3(0.15, 2, 0.15), gb * CF(0, 7.8, -2), Color3.fromRGB(150, 153, 160), M.Metal)
			cyl(f, "GarageBag", 4, 1.8, gb * CF(0, 4.6, -2) * ANG(0, 0, RAD(90)), Color3.fromRGB(150, 24, 30), M.Leather)
		end
		local gl = part(f, "GarageLight", V3(0.2, 0.2, 0.2), gb * CF(0, 8, 0), WHITE, M.SmoothPlastic, { transparency = 1 })
		local l = Instance.new("PointLight")
		l.Color, l.Range, l.Brightness, l.Shadows = Color3.fromRGB(255, 240, 220), 12, 0.8, false
		l.Parent = gl
	end
	-- hoop above the garage door
	part(f, "HoopBoard", V3(3, 2, 0.15), gb * CF(0, 8.3, -6.3), WHITE, M.SmoothPlastic)
	for k = 0, 5 do
		local ang = k * math.pi / 3
		part(f, "HoopRim", V3(0.1, 0.1, 0.5), gb * CF(math.cos(ang) * 0.7, 7.5, -7.1 + math.sin(ang) * 0.7) * ANG(0, -ang, 0), Color3.fromRGB(240, 110, 30), M.Metal)
	end
	-- porch with columns, front door, windows on both storeys, wall lamps
	local fz = mainZ - D / 2
	part(f, "Porch", V3(8, 0.6, 3.6), base * CF(mainX, 0.3, fz - 1.8), Color3.fromRGB(160, 150, 140), M.Concrete, { collide = true })
	part(f, "PorchRoof", V3(8.4, 0.4, 4), base * CF(mainX, 7.0, fz - 1.9), trim, M.Wood)
	for _, x in ipairs({ -3.6, 3.6 }) do
		cyl(f, "PorchColumn", 6.4, 0.6, base * CF(mainX + x, 3.6, fz - 3.5) * ANG(0, 0, RAD(90)), trim, M.Wood)
	end
	part(f, "FrontDoor", V3(2.8, 5.8, 0.2), base * CF(mainX, 3.5, fz - 0.1), Color3.fromRGB(30, 60, 110), M.Wood)
	for _, w in ipairs({ { -5.5, 4.5 }, { 5.5, 4.5 }, { -5.5, 11 }, { 0, 11 }, { 5.5, 11 } }) do
		-- glass sits proud of the wall face (fz), the night glow in the gap behind it
		part(f, "HouseWindow", V3(3, 3.2, 0.15), base * CF(mainX + w[1], w[2], fz - 0.14), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.25 })
		part(f, "WindowTrim", V3(3.5, 0.3, 0.3), base * CF(mainX + w[1], w[2] - 1.75, fz - 0.15), trim, M.Wood)
		local win = part(f, "WindowGlow", V3(2.6, 2.8, 0.05), base * CF(mainX + w[1], w[2], fz - 0.03), Color3.fromRGB(255, 214, 150), M.Neon, { transparency = 0.55, shadow = false })
		tag(win, "NightLens")
	end
	for _, x in ipairs({ -1.8, 1.8 }) do
		local lamp = part(f, "WallLamp", V3(0.5, 0.8, 0.3), base * CF(mainX + x, 5.0, fz - 0.25), Color3.fromRGB(255, 230, 170), M.Neon, { shadow = false })
		nightLight(lamp, Color3.fromRGB(255, 210, 150), 12, 0.8)
	end
	-- flag in your colours with your nickname, mailbox with the surname
	local fp = base * CF(-12, 0, -8)
	cyl(f, "FlagPole", 14, 0.3, fp * CF(0, 7, 0) * ANG(0, 0, RAD(90)), Color3.fromRGB(200, 200, 205), M.Metal)
	local flag = part(f, "HomeFlag", V3(0.08, 2.6, 4.2), fp * CF(0, 12.6, -2.2), trunkColor(P), M.Fabric, { shadow = false })
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local sg = gui(flag, face, 30, 0.4, 150)
		label(sg, nickOf(P):upper(), { TextColor3 = WHITE, Size = UDim2.fromScale(0.9, 0.6), Position = UDim2.fromScale(0.05, 0.2) })
	end
	local mbx = base * CF(-6, 0, -13.2)
	part(f, "MailboxPost", V3(0.25, 3, 0.25), mbx * CF(0, 1.5, 0), Color3.fromRGB(140, 100, 65), M.Wood)
	local box = part(f, "Mailbox", V3(0.8, 0.8, 1.4), mbx * CF(0, 3.3, 0), DARK, M.Metal)
	local sg = gui(box, Enum.NormalId.Left, 60, 0.4, 40)
	label(sg, surnameOf(P):upper(), { TextColor3 = WHITE })
	-- backyard pool with the Pool Deck add-on
	if owned.PoolDeck then
		local pc = base * CF(-3, 0, 17)
		part(f, "PoolDeck", V3(16, 0.3, 10), pc * CF(0, 0.15, 0), Color3.fromRGB(170, 130, 90), M.WoodPlanks, { collide = true })
		part(f, "PoolWater", V3(11, 0.25, 6), pc * CF(-1.5, 0.32, 0), Color3.fromRGB(60, 170, 220), M.Glass, { transparency = 0.15, reflect = 0.2 })
		part(f, "Lounger", V3(2, 0.5, 5), pc * CF(6, 0.55, 0), WHITE, M.Fabric) -- on the 0.3 deck
	end
end

local function villaBuild(f, P, base)
	local owned = P.owned or {}
	local white = Color3.fromRGB(242, 240, 234)
	local dark = Color3.fromRGB(34, 34, 38)
	local glassC = Color3.fromRGB(150, 190, 215)
	-- central two-storey block with a glass curtain front, two single-storey wings
	-- the core's face sits 4 studs behind the glass curtain: a double-height gallery you see from the
	-- drive (trophy pedestals live there), closed at the sides by two short walls
	part(f, "VillaCore", V3(30, 18, 18), base * CF(0, 9, 3), white, M.Concrete, { collide = true })
	part(f, "GalleryFloor", V3(26, 0.2, 4.2), base * CF(0, 0.1, -8.05), Color3.fromRGB(230, 226, 218), M.Marble)
	for _, sx in ipairs({ -1, 1 }) do
		part(f, "GalleryWall", V3(2, 18, 4.4), base * CF(sx * 14, 9, -8.15), white, M.Concrete, { collide = true })
	end
	local gl = part(f, "GalleryLight", V3(0.2, 0.2, 0.2), base * CF(0, 15, -8), WHITE, M.SmoothPlastic, { transparency = 1, shadow = false })
	nightLight(gl, Color3.fromRGB(255, 226, 180), 18, 0.9)
	part(f, "VillaGlass", V3(26, 15.5, 0.3), base * CF(0, 8.6, -10.2), glassC, M.Glass, { transparency = 0.35, reflect = 0.15 })
	for k = 0, 6 do
		part(f, "VillaMullion", V3(0.3, 15.5, 0.5), base * CF(-13 + k * 26 / 6, 8.6, -10.3), dark, M.Metal)
	end
	part(f, "VillaFloorBand", V3(26.4, 0.6, 0.6), base * CF(0, 9, -10.4), dark, M.Metal)
	part(f, "VillaRoof", V3(36, 1, 28), base * CF(0, 18.5, 0), dark, M.Metal, { collide = true })
	for _, sx in ipairs({ -1, 1 }) do
		local wcf = base * CF(sx * 26, 0, 2)
		part(f, "VillaWing", V3(22, 9, 20), wcf * CF(0, 4.5, 0), white, M.Concrete, { collide = true })
		part(f, "WingGlass", V3(18, 7, 0.3), wcf * CF(0, 4.6, -10.2), glassC, M.Glass, { transparency = 0.35, reflect = 0.15 })
		part(f, "WingRoof", V3(25, 0.8, 25), wcf * CF(sx * 1.2, 9.4, -1.5), dark, M.Metal, { collide = true })
		part(f, "TerraceRail", V3(22, 1.4, 0.15), wcf * CF(0, 10.5, -10), glassC, M.Glass, { transparency = 0.5 })
		-- warm interior glow through the glass after dark
		local glow = part(f, "WingGlow", V3(16, 6, 0.05), wcf * CF(0, 4.6, -10.025), Color3.fromRGB(255, 214, 160), M.Neon, { transparency = 0.6, shadow = false })
		tag(glow, "NightLens")
		local up = part(f, "Uplight", V3(0.6, 0.3, 0.6), base * CF(sx * 12, 0.15, -12), dark, M.Metal)
		local l = Instance.new("SpotLight")
		l.Face, l.Angle, l.Range, l.Brightness, l.Shadows = Enum.NormalId.Top, 50, 22, 1.6, false
		l.Color = Color3.fromRGB(255, 226, 180)
		l.Enabled = false
		l.Parent = up
		tag(l, "NightLight")
	end
	local coreGlow = part(f, "CoreGlow", V3(24, 14, 0.05), base * CF(0, 8.6, -6.025), Color3.fromRGB(255, 220, 170), M.Neon, { transparency = 0.65, shadow = false })
	tag(coreGlow, "NightLens")
	-- entrance: door, canopy on columns, topiary planters
	part(f, "VillaDoor", V3(5, 10, 0.3), base * CF(0, 5, -10.5), Color3.fromRGB(60, 40, 28), M.Wood)
	part(f, "EntryCanopy", V3(12, 0.6, 7), base * CF(0, 11, -13.5), dark, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		cyl(f, "EntryColumn", 10.6, 0.8, base * CF(sx * 5.4, 5.3, -16.5) * ANG(0, 0, RAD(90)), white, M.Concrete)
		part(f, "TopiaryPot", V3(2.4, 2.2, 2.4), base * CF(sx * 9, 1.1, -14), dark, M.Concrete)
		ball(f, "Topiary", 3, base * CF(sx * 9, 3.6, -14), Color3.fromRGB(46, 104, 50), M.Grass)
	end
	if owned.TrophyRoom then
		-- the trophy room behind the glass: belts on lit pedestals, seen from the drive
		local belts = beltsOf(P)
		for i = 1, math.max(1, #belts) do
			local px = -9 + (i - 1) * 6
			part(f, "Pedestal", V3(2, 3.4, 2), base * CF(px, 1.9, -7.6), white, M.Marble)
			part(f, "PedestalBelt", V3(2.6, 0.6, 0.2), base * CF(px, 4.1, -8.0), DARK, M.Leather)
			cyl(f, "PedestalPlate", 0.2, 1.0, base * CF(px, 4.1, -8.15) * ANG(0, RAD(90), 0), GOLD, M.Metal, { reflect = 0.3 })
		end
	else
		for _, sx in ipairs({ -1, 1 }) do
			plant(f, base * CF(sx * 10, 0.2, -8), 1.2)
		end
	end
	-- gold name plaque at the gate
	local gate = siteCF("EstateGate")
	if gate then
		local pl = part(f, "GatePlaque", V3(4.6, 1.4, 0.1), gate * CF(-9.2, 5.4, -8.6), GOLD, M.Metal, { reflect = 0.2 })
		local sg = gui(pl, Enum.NormalId.Front, 50, 0.3, 80)
		label(sg, "THE " .. surnameOf(P):upper() .. " ESTATE", { TextColor3 = Color3.fromRGB(40, 28, 10), Font = Enum.Font.Garamond })
	end
	-- garage with every car you own
	local gcf = siteCF("MansionGarage")
	if gcf then
		part(f, "Garage", V3(26, 9, 14), gcf * CF(0, 4.5, 2), white, M.Concrete, { collide = true })
		part(f, "GarageRoof", V3(28, 0.8, 16), gcf * CF(0, 9.4, 1.5), dark, M.Metal)
		for k = -1, 1 do
			part(f, "GarageBay", V3(7.6, 7, 0.2), gcf * CF(k * 8.4, 3.6, -5.05), Color3.fromRGB(40, 40, 46), M.Metal)
		end
		local cars = carsOf(owned)
		for i = 1, math.min(3, #cars) do
			-- parked nose-out on the apron, tails clear of the garage face (local z -5)
			CityProps.SportsCar(f, gcf * CF((i - 2) * 8.4, 0, -12), cars[i], nil, surnameOf(P):upper():sub(1, 8))
		end
	end
	-- pool deck (infinity pool with a caustic pattern) or a sculpture lawn
	local pcf = siteCF("MansionPool")
	if pcf then
		if owned.PoolDeck then
			part(f, "PoolDeck", V3(30, 0.4, 18), pcf * CF(0, 0.2, 0), Color3.fromRGB(226, 220, 206), M.Limestone, { collide = true })
			local water = part(f, "PoolWater", V3(22, 0.3, 9), pcf * CF(0, 0.45, -1), Color3.fromRGB(70, 180, 230), M.Glass, { transparency = 0.2, reflect = 0.25 })
			local sg = gui(water, Enum.NormalId.Top, 4, 0.4, 150)
			for k = 0, 11 do
				local c = frame(sg, { Size = UDim2.fromScale(0.1, 0.08), Position = UDim2.fromScale((k * 0.37) % 0.9, (k * 0.23) % 0.9), BackgroundColor3 = Color3.fromRGB(200, 240, 255), BackgroundTransparency = 0.6 })
				Instance.new("UICorner", c).CornerRadius = UDim.new(0.5, 0)
			end
			nightLight(water, Color3.fromRGB(80, 200, 255), 16, 1)
			for k = 0, 2 do
				local lc = pcf * CF(-8 + k * 4, 0, 6)
				part(f, "Lounger", V3(2.2, 0.5, 5.5), lc * CF(0, 0.9, 0), WHITE, M.Fabric)
				part(f, "LoungerBack", V3(2.2, 0.5, 2.2), lc * CF(0, 1.7, 2.2) * ANG(RAD(50), 0, 0), WHITE, M.Fabric)
			end
		else
			for k = -1, 1, 2 do
				part(f, "Plinth", V3(2, 2, 2), pcf * CF(k * 6, 1, 0), white, M.Marble)
				ball(f, "Topiary", 2.8, pcf * CF(k * 6, 3.4, 0), Color3.fromRGB(46, 104, 50), M.Grass)
			end
		end
		if owned.HomeGym then
			-- open-air training pavilion by the pool
			local tp = pcf * CF(0, 0, 13)
			for _, c in ipairs({ { -4, -3 }, { 4, -3 }, { 4, 3 }, { -4, 3 } }) do
				part(f, "PavilionPost", V3(0.5, 8, 0.5), tp * CF(c[1], 4, c[2]), dark, M.Metal)
			end
			part(f, "PavilionRoof", V3(9.6, 0.4, 7.6), tp * CF(0, 8.2, 0), white, M.Concrete)
			cyl(f, "PavilionBag", 4.2, 1.9, tp * CF(0, 4.6, 0) * ANG(0, 0, RAD(90)), Color3.fromRGB(150, 24, 30), M.Leather)
			part(f, "PavilionMat", V3(8, 0.15, 6), tp * CF(0, 0.3, 0), Color3.fromRGB(32, 32, 35), M.Rubber)
		end
	end
end

-- swing the Hillcrest gate leaves open for the owner (local only), or put them back
local gateSaved = {}
local function setGate(open)
	local c = cityRoot()
	local est = c and c:FindFirstChild("Estates")
	if not est then
		return
	end
	for _, leaf in ipairs(est:GetChildren()) do
		if leaf:IsA("Model") and leaf.Name == "GateLeaf" and leaf.PrimaryPart then
			if not gateSaved[leaf] then
				gateSaved[leaf] = leaf:GetPivot()
			end
			local hinge = tonumber(leaf:GetAttribute("Hinge")) or leaf.PrimaryPart.Position.X
			local side = tonumber(leaf:GetAttribute("Side")) or 1
			local p0 = gateSaved[leaf]
			if open then
				local h = CF(hinge, p0.Position.Y, p0.Position.Z)
				leaf:PivotTo(h * ANG(0, RAD(side * 80), 0) * h:Inverse() * p0)
			else
				leaf:PivotTo(p0)
			end
			leaf.PrimaryPart.CanCollide = not open
		end
	end
end

-- realty signs: SOLD with your name on the home you own, the advert otherwise
local function forSaleSigns(P)
	for _, p in ipairs(screens("ForSale")) do
		local kind = p:GetAttribute("Home")
		local l = firstLabel(p)
		if l then
			setLabel(l, (P.owned and P.owned[kind]) and ("SOLD\n" .. surnameOf(P):upper()) or nil)
		end
	end
end

local function updateHomes(P)
	local owned = P.owned or {}
	local addons = {}
	for _, id in ipairs({ "Garage", "HomeGym", "TrophyRoom", "RecoverySuite", "PoolDeck", "SportsCar", "Supercar", "Hypercar" }) do
		table.insert(addons, owned[id] and "1" or "0")
	end
	local common = table.concat(addons) .. "|" .. surnameOf(P) .. "|" .. nickOf(P) .. "|" .. table.concat(beltsOf(P), ",")
	group("HomeApartment", owned.Apartment and (common .. (siteCF("ApartmentRoof") and "|s" or "|-")) or "", function(f)
		apartmentDressing(f, P)
	end)
	local hb = siteCF("HomeHouse")
	group("HomeHouse", (owned.House and hb) and common or "", function(f)
		houseBuild(f, P, hb)
	end)
	local vb = siteCF("HomeMansion")
	group("HomeMansion", (owned.Mansion and vb) and (common .. (siteCF("MansionGarage") and "|g" or "")) or "", function(f)
		villaBuild(f, P, vb)
	end)
	setGate(owned.Mansion == true)
	forSaleSigns(P)
end

------------------------------------------------------------------------
-- Cars: your best car in the reserved bay at the gym and at home
------------------------------------------------------------------------
local function updateCars(P)
	local owned = P.owned or {}
	local cars = carsOf(owned)
	local home = P.home
	local bay = siteCF("CarBay")
	-- Garage / HomeGym decide whether the second car stands in the house garage
	local key = #cars > 0 and (table.concat(cars, ",") .. "|" .. tostring(home) .. "|" .. (bay and "b" or "-") .. "|" .. surnameOf(P) .. "|" .. (owned.Garage and "G" or "-") .. (owned.HomeGym and "H" or "-")) or ""
	group("Cars", key, function(f)
		local plate = surnameOf(P):upper():sub(1, 8)
		if bay then
			CityProps.SportsCar(f, bay, cars[1], nil, plate)
		end
		if home == "House" then
			local hb = siteCF("HomeHouse")
			if hb then
				CityProps.SportsCar(f, hb * CF(9.5, 0.18, -12), cars[1], nil, plate)
				-- (the garage is the gym when you own one, so the second car only shows without it)
				if owned.Garage and cars[2] and not owned.HomeGym then
					CityProps.SportsCar(f, hb * CF(9.5, 0.25, 4), cars[2], nil, plate)
				end
			end
		elseif home == "Apartment" then
			-- kerbside in front of Riverside Apartments
			CityProps.SportsCar(f, CF(115, 0.3, 180.2) * ANG(0, RAD(-90), 0), cars[1], nil, plate)
		end
	end)
	for _, p in ipairs(screens("Reserved")) do
		local l = firstLabel(p)
		if l then
			setLabel(l, #cars > 0 and ("RESERVED\n" .. surnameOf(P):upper()) or nil)
		end
	end
end

------------------------------------------------------------------------
-- Sponsors: billboards and shop windows
------------------------------------------------------------------------
local BOARD_SLOTS = {
	Champion = { "trunks", "gear", "robe", "corner" }, Cafe = { "robe", "corner", "trunks", "gear" },
	Apartments = { "gear", "trunks", "corner", "robe" }, Loop = { "corner", "robe", "gear", "trunks" },
}
local SLOT_VERB = { trunks = "WEARS", robe = "WALKS OUT IN", corner = "FIGHTS WITH", gear = "TRAINS WITH" }

-- silhouette of a boxer in a guard (frames), used on ads and posters
local function silhouette(parent, color, x, y, s)
	local head = frame(parent, { Size = UDim2.fromScale(0.09 * s, 0.16 * s), Position = UDim2.fromScale(x + 0.045 * s, y), BackgroundColor3 = color })
	Instance.new("UICorner", head).CornerRadius = UDim.new(0.5, 0)
	local torso = frame(parent, { Size = UDim2.fromScale(0.18 * s, 0.4 * s), Position = UDim2.fromScale(x, y + 0.17 * s), BackgroundColor3 = color })
	Instance.new("UICorner", torso).CornerRadius = UDim.new(0.3, 0)
	for _, gx in ipairs({ -0.03, 0.15 }) do
		local glove = frame(parent, { Size = UDim2.fromScale(0.06 * s, 0.1 * s), Position = UDim2.fromScale(x + gx * s, y + 0.1 * s), BackgroundColor3 = color })
		Instance.new("UICorner", glove).CornerRadius = UDim.new(0.5, 0)
	end
end

local function adContent(P, slot)
	local camp = P.camp and P.camp.offer
	if slot == "ArenaW" then
		if camp and camp.opp then
			local opp = tostring(camp.opp.name or "?"):match("(%S+)$") or "?"
			return { bg = Color3.fromRGB(120, 14, 20), fg = Color3.fromRGB(255, 220, 90), top = tostring(camp.kind or "FIGHT NIGHT"):upper(),
				title = surnameOf(P):upper() .. " vs " .. opp:upper(), sub = string.format("%s  -  %d DAYS", tostring(camp.venueName or "WCB ARENA"):upper(), P.camp.daysLeft or 0) }
		end
		local belts = beltsOf(P)
		if #belts > 0 then
			return { bg = Color3.fromRGB(16, 16, 20), fg = GOLD, top = table.concat(belts, "  ") .. " WORLD CHAMPION", title = tostring(P.identity.name):upper(), sub = recText(P) }
		end
		return nil
	elseif slot == "ArenaE" then
		if (P.popularity or 0) >= 25 then
			return { bg = Color3.fromRGB(14, 30, 70), fg = WHITE, top = "HOMETOWN HERO", title = "\"" .. nickOf(P):upper() .. "\"", sub = recText(P) .. "  -  WCB ARENA" }
		end
		return nil
	end
	for _, s in ipairs(BOARD_SLOTS[slot] or {}) do
		local d = deal(P, s)
		if d and d.logo then
			return { bg = rgb(d.logo.bg, DARK), fg = rgb(d.logo.fg, WHITE), top = tostring(d.logo.text or d.name), title = "\"" .. nickOf(P):upper() .. "\"",
				sub = string.format("%s %s  -  %s", SLOT_VERB[s] or "LOVES", tostring(d.name):upper(), recText(P)) }
		end
	end
	return nil
end

local function updateBillboards(P)
	for _, face in ipairs(CollectionService:GetTagged("CityBillboard")) do
		if face:IsDescendantOf(workspace) then
			local c = adContent(P, face:GetAttribute("Slot"))
			local key = c and (c.top .. c.title .. c.sub) or ""
			if face:GetAttribute("LocalKey") ~= key then
				face:SetAttribute("LocalKey", key)
				overlay(face, "Ad", c and function(sg)
					sg.PixelsPerStud = 10
					frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = c.bg })
					frame(sg, { Size = UDim2.fromScale(1, 0.05), Position = UDim2.fromScale(0, 0.95), BackgroundColor3 = c.fg })
					silhouette(sg, c.fg, 0.04, 0.2, 1.3)
					label(sg, c.top, { TextColor3 = c.fg, Size = UDim2.fromScale(0.66, 0.2), Position = UDim2.fromScale(0.3, 0.06) })
					label(sg, c.title, { TextColor3 = WHITE, Size = UDim2.fromScale(0.66, 0.36), Position = UDim2.fromScale(0.3, 0.3) })
					label(sg, c.sub, { TextColor3 = c.fg, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.66, 0.16), Position = UDim2.fromScale(0.3, 0.72) })
				end or nil)
			end
		end
	end
end

-- standees inside the window of a sponsor's own shop (and a couple of local shops that just love you)
local function updateWindows(P)
	local wanted = {}
	for _, slot in ipairs(Catalog.SponsorSlots) do
		local d = deal(P, slot)
		if d and d.shop then
			wanted[d.shop] = { bg = rgb(d.logo and d.logo.bg, DARK), fg = rgb(d.logo and d.logo.fg, WHITE), top = "OFFICIAL FIGHTER", brand = tostring(d.logo and d.logo.text or d.name) }
		end
	end
	if (P.popularity or 0) >= 30 and not wanted["CHAMP'S DINER"] then
		wanted["CHAMP'S DINER"] = { bg = Color3.fromRGB(190, 20, 30), fg = WHITE, top = "EATS HERE!", brand = "CHAMP'S" }
	end
	if P.camp and P.camp.offer and not wanted["WCB ARENA TICKETS"] then
		wanted["WCB ARENA TICKETS"] = { bg = Color3.fromRGB(150, 16, 24), fg = Color3.fromRGB(255, 220, 90), top = "ON SALE NOW", brand = "vs " .. tostring(P.camp.offer.opp and P.camp.offer.opp.name or "?"):upper() }
	end
	local parts, key = {}, {}
	local c = cityRoot()
	local sites = c and c:FindFirstChild("Sites")
	for _, s in ipairs(sites and sites:GetChildren() or {}) do
		local shopName = s:GetAttribute("Shop")
		if shopName and wanted[shopName] then
			table.insert(parts, { s.CFrame, wanted[shopName] })
			table.insert(key, shopName .. wanted[shopName].top .. wanted[shopName].brand)
		end
	end
	table.sort(key)
	group("ShopWindows", #parts > 0 and (table.concat(key, ";") .. nickOf(P)) or "", function(f)
		for _, e in ipairs(parts) do
			local w = e[2]
			local st = part(f, "Standee", V3(3.2, 5.4, 0.12), e[1] * CF(0, 3.4, 0), w.bg, M.SmoothPlastic, { shadow = false })
			part(f, "StandeeFoot", V3(1.6, 0.2, 1.2), e[1] * CF(0, 0.6, 0.3), DARK, M.Metal)
			local sg = gui(st, Enum.NormalId.Front, 40, 0.2, 150)
			frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = w.bg })
			label(sg, w.top, { TextColor3 = w.fg, Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.03) })
			silhouette(sg, w.fg, 0.32, 0.16, 2)
			label(sg, "\"" .. nickOf(P):upper() .. "\"", { TextColor3 = WHITE, Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.72) })
			label(sg, w.brand, { TextColor3 = w.fg, Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.84) })
		end
	end)
end

------------------------------------------------------------------------
-- City media: marquee, arena screen, bus poster, plaque, lawn signs, apartment banner
------------------------------------------------------------------------
local function recentTitle(P)
	local h = P.history and P.history[1]
	if type(h) ~= "table" or h.outcome ~= "win" or (P.day or 0) - (h.day or 0) > 12 then
		return nil
	end
	if type(h.stakes) == "table" and #h.stakes > 0 then
		return table.concat(h.stakes, " / ") .. " WORLD CHAMPION"
	elseif h.kind == "Regional Title" then
		return "REGIONAL CHAMPION"
	elseif h.kind == "National Title" then
		return "NATIONAL CHAMPION"
	end
	return nil
end

local function updateMedia(P)
	local camp = P.camp and P.camp.offer
	local opp = camp and camp.opp and (tostring(camp.opp.name or "?"):match("(%S+)$") or "?") or nil
	local title = recentTitle(P)
	local name = tostring(P.identity and P.identity.name or ""):upper()
	for _, p in ipairs(screens("Marquee")) do
		local l = firstLabel(p, "MarqueeText")
		if l then
			if camp then
				setLabel(l, string.format("%s vs %s  -  %s  -  %d DAYS", surnameOf(P):upper(), opp:upper(), tostring(camp.kind or ""):upper(), P.camp.daysLeft or 0))
			elseif title then
				setLabel(l, "NEW " .. title .. ": " .. name)
			else
				setLabel(l, nil)
			end
		end
	end
	for _, p in ipairs(screens("ArenaScreen")) do
		local top, head, sub = firstLabel(p, "ScreenTop"), firstLabel(p, "ScreenHeadline"), firstLabel(p, "ScreenSub")
		if top and head and sub then
			if camp then
				setLabel(top, tostring(camp.venueName or "WCB ARENA"):upper())
				setLabel(head, surnameOf(P):upper() .. " vs " .. opp:upper())
				setLabel(sub, string.format("%s  -  %d ROUNDS  -  IN %d DAYS", tostring(camp.kind or ""):upper(), camp.rounds or 0, P.camp.daysLeft or 0))
			elseif title then
				setLabel(top, "AND THE NEW...")
				setLabel(head, name)
				setLabel(sub, title .. "  -  " .. recText(P))
			else
				setLabel(top, nil)
				setLabel(head, nil)
				setLabel(sub, nil)
			end
		end
	end
	for _, p in ipairs(screens("BusAd")) do
		local key = camp and ("c" .. opp .. tostring(P.camp.daysLeft)) or (title and ("t" .. title) or "")
		if p:GetAttribute("LocalKey") ~= key then
			p:SetAttribute("LocalKey", key)
			overlay(p, "*", key ~= "" and function(sg)
				sg.PixelsPerStud = 40
				frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(16, 16, 22) })
				frame(sg, { Size = UDim2.fromScale(1, 0.14), BackgroundColor3 = Color3.fromRGB(190, 20, 30) })
				label(sg, camp and tostring(camp.kind or "FIGHT NIGHT"):upper() or "CHAMPION", { TextColor3 = WHITE, Size = UDim2.fromScale(0.9, 0.11), Position = UDim2.fromScale(0.05, 0.015) })
				silhouette(sg, Color3.fromRGB(60, 60, 70), 0.33, 0.18, 1.9)
				label(sg, camp and (surnameOf(P):upper() .. "\nvs\n" .. opp:upper()) or name, { TextColor3 = GOLD, Size = UDim2.fromScale(0.9, 0.36), Position = UDim2.fromScale(0.05, 0.4) })
				label(sg, camp and string.format("%s - %d DAYS", tostring(camp.venueName or ""):upper(), P.camp.daysLeft or 0) or (title or ""), { TextColor3 = WHITE, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.08), Position = UDim2.fromScale(0.05, 0.86) })
			end or nil)
		end
	end
	for _, p in ipairs(screens("Plaque")) do
		local l = firstLabel(p)
		if l then
			setLabel(l, (P.titlesWon or 0) > 0 and string.format("CHAMPIONS WALK\n%s - %d WORLD TITLE%s", name, P.titlesWon, P.titlesWon == 1 and "" or "S") or nil)
		end
	end
	local cheer = (P.popularity or 0) >= 40
	for _, p in ipairs(screens("LawnSign")) do
		local l = firstLabel(p)
		if l then
			setLabel(l, cheer and ("GO\n" .. nickOf(P):upper() .. "!") or nil)
		end
	end
	local bcf = siteCF("ApartmentBanner")
	group("FanBanner", (cheer and bcf) and nickOf(P) or "", function(f)
		local ban = part(f, "FanBanner", V3(6, 2.4, 0.1), bcf, WHITE, M.Fabric, { shadow = false })
		local sg = gui(ban, Enum.NormalId.Front, 20, 0.5, 300)
		frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
		label(sg, "GO " .. nickOf(P):upper() .. "!", { TextColor3 = Color3.fromRGB(200, 20, 30), Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1) })
	end)
end

------------------------------------------------------------------------
-- Legacy: Walk of Fame stars, statue, museum case and banner
------------------------------------------------------------------------
local function starList(P)
	local list = {}
	if P.regional and P.regional.regional then
		table.insert(list, "REGIONAL CHAMPION")
	end
	if P.regional and P.regional.national then
		table.insert(list, "NATIONAL CHAMPION")
	end
	local belts = beltsOf(P)
	for i = 1, math.min(4, math.max(#belts, P.titlesWon or 0)) do
		table.insert(list, (belts[i] and (belts[i] .. " ") or "") .. "WORLD CHAMPION")
	end
	if (P.tier or 1) >= 9 then
		table.insert(list, "UNDISPUTED")
	end
	if (P.tier or 1) >= 10 then
		table.insert(list, "BOXING LEGEND")
	end
	if P.legacy and P.legacy.hof then
		table.insert(list, "HALL OF FAME")
	end
	return list
end

local function updateLegacy(P)
	local stars = starList(P)
	local wcf, wp = siteCF("WalkOfFame")
	local name = tostring(P.identity and P.identity.name or "")
	group("WalkOfFame", (#stars > 0 and wcf) and (table.concat(stars, ",") .. name) or "", function(f)
		local step = wp and tonumber(wp:GetAttribute("Step")) or 4
		local max = wp and tonumber(wp:GetAttribute("Max")) or 9
		for i = 1, math.min(max, #stars) do
			CityProps.Star(f, wcf * CF(0, 0, (i - 1) * step), stars[i], name)
		end
	end)
	local scf = siteCF("Statue")
	local statue = (P.tier or 1) >= 9 or (P.legacy and P.legacy.hof)
	group("Statue", (statue and scf) and (name .. tostring(P.tier)) or "", function(f)
		local belts = beltsOf(P)
		local title = (P.tier or 1) >= 10 and "BOXING LEGEND" or ((P.tier or 1) >= 9 and "UNDISPUTED CHAMPION" or (#belts > 0 and table.concat(belts, " ") or "HALL OF FAMER"))
		CityProps.Statue(f, scf, { name = name:upper(), title = title })
		local l = part(f, "StatueLight", V3(0.3, 0.3, 0.3), scf * CF(0, 0.3, -5), WHITE, M.SmoothPlastic, { transparency = 1 })
		local spot = Instance.new("SpotLight")
		spot.Face, spot.Angle, spot.Range, spot.Brightness, spot.Shadows = Enum.NormalId.Top, 40, 20, 1.8, false
		spot.Color = Color3.fromRGB(255, 226, 180)
		spot.Enabled = false
		spot.Parent = l
		tag(spot, "NightLight")
	end)
	local ecf = siteCF("MuseumExhibit")
	local exhibit = (P.titlesWon or 0) > 0 or (P.legacy and P.legacy.hof)
	-- the plaque prints the nickname and record, so they are part of the key (rebuilt after each fight; ~10 parts)
	local exKey = table.concat({ name, tostring(P.titlesWon), table.concat(beltsOf(P), ","), recText(P), nickOf(P) }, "|")
	group("MuseumExhibit", (exhibit and ecf) and exKey or "", function(f)
		part(f, "ExhibitBase", V3(6, 3, 3), ecf * CF(0, 1.5, 0), Color3.fromRGB(30, 26, 22), M.Wood, { collide = true })
		part(f, "ExhibitGlass", V3(6, 3.4, 3), ecf * CF(0, 4.7, 0), Color3.fromRGB(210, 230, 245), M.Glass, { transparency = 0.65 })
		local belts = beltsOf(P)
		for i = 1, math.max(1, math.min(3, #belts)) do
			part(f, "ExhibitBelt", V3(1.6, 0.4, 0.8), ecf * CF(-2 + (i - 1) * 2, 3.25, 0), DARK, M.Leather)
			cyl(f, "ExhibitPlate", 0.15, 0.7, ecf * CF(-2 + (i - 1) * 2, 3.38, 0) * ANG(0, 0, RAD(90)), GOLD, M.Metal, { reflect = 0.3 })
		end
		blob(f, "ExhibitGlove", V3(1, 1.2, 1.1), ecf * CF(1.6, 3.7, 0.4), trunkColor(P), M.Leather)
		local pl = part(f, "ExhibitPlaque", V3(5, 1.6, 0.1), ecf * CF(0, 1.6, -1.55), GOLD, M.Metal)
		local sg = gui(pl, Enum.NormalId.Front, 50, 0.3, 60)
		label(sg, string.format("%s \"%s\"\n%s  -  %d WORLD TITLE%s", name:upper(), nickOf(P):upper(), recText(P), P.titlesWon or 0, (P.titlesWon or 0) == 1 and "" or "S"), { TextColor3 = Color3.fromRGB(40, 28, 10) })
		local l = Instance.new("SpotLight")
		l.Face, l.Angle, l.Range, l.Brightness, l.Shadows = Enum.NormalId.Bottom, 50, 14, 1.4, false
		l.Parent = part(f, "ExhibitLight", V3(0.2, 0.2, 0.2), ecf * CF(0, 9, -2), WHITE, M.SmoothPlastic, { transparency = 1 })
	end)
	local bcf = siteCF("MuseumBanner")
	group("MuseumBanner", (P.legacy and P.legacy.hof and bcf) and name or "", function(f)
		local ban = part(f, "InductionBanner", V3(4.4, 12, 0.1), bcf, Color3.fromRGB(120, 16, 24), M.Fabric, { shadow = false })
		local sg = gui(ban, Enum.NormalId.Front, 20, 0.4, 400)
		frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 16, 24) })
		label(sg, "INDUCTED\n\n" .. name:upper():gsub(" ", "\n") .. "\n\nHALL OF FAME", { TextColor3 = GOLD, Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05) })
	end)
end

------------------------------------------------------------------------
-- Elite Performance Center: opens for an Elite-tier facility
------------------------------------------------------------------------
local mocap = { cams = {}, target = nil, site = nil }
local labMonitors = {} -- { name = TextLabel, bar = Frame } x3 in the sports science lab

local function setEliteOpen(open)
	local c = cityRoot()
	local ec = c and c:FindFirstChild("EliteCenter")
	if not ec then
		return
	end
	for _, d in ipairs(ec:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "EliteShutter" then
			d.Transparency = open and 1 or 0
			d.CanCollide = not open
			for _, sg in ipairs(d:GetChildren()) do
				if sg:IsA("SurfaceGui") then
					sg.Enabled = not open
				end
			end
		elseif d:IsA("SpotLight") and d.Name == "EliteCenterLight" then
			d.Enabled = open
		elseif d:IsA("TextLabel") and d.Name == "SignText" then
			d.TextColor3 = open and Color3.fromRGB(150, 220, 255) or Color3.fromRGB(120, 128, 140)
		end
	end
end

local function eliteDecor(f)
	local rec = siteCF("EliteRecovery")
	if rec then
		-- cryotherapy cabin with cold fog, hot & cold plunge pools with their temperatures
		local cab = rec * CF(-6, 0, -6)
		cyl(f, "CryoCabin", 7, 3.4, cab * CF(0, 4.4, 0) * ANG(0, 0, RAD(90)), Color3.fromRGB(200, 225, 240), M.Glass, { transparency = 0.45 })
		cyl(f, "CryoBase", 0.9, 3.8, cab * CF(0, 1.3, 0) * ANG(0, 0, RAD(90)), Color3.fromRGB(230, 232, 236), M.Metal)
		cyl(f, "CryoRing", 0.4, 3.9, cab * CF(0, 7.9, 0) * ANG(0, 0, RAD(90)), Color3.fromRGB(170, 220, 255), M.Ice)
		local fog = Instance.new("ParticleEmitter")
		fog.Name = "CryoFog"
		fog.Rate = 12
		fog.Lifetime = NumberRange.new(2, 2.6)
		fog.Speed = NumberRange.new(0.4, 0.8)
		fog.Size = NumberSequence.new(0.8, 2.2)
		fog.Transparency = NumberSequence.new(0.6, 1)
		fog.Color = ColorSequence.new(Color3.fromRGB(230, 245, 255))
		fog.Enabled = false
		fog.Parent = f:FindFirstChild("CryoBase") or f
		for k, pool in ipairs({ { "HOT 39C", Color3.fromRGB(255, 160, 90) }, { "COLD 6C", Color3.fromRGB(110, 190, 240) } }) do
			local pc = rec * CF(3, 0, -8 + (k - 1) * 9)
			part(f, "PlungeRim", V3(7, 2.2, 6), pc * CF(4, 1.1, 0), Color3.fromRGB(226, 226, 230), M.Marble, { collide = true })
			part(f, "PlungeWater", V3(6, 0.2, 5), pc * CF(4, 2.25, 0), pool[2], M.Glass, { transparency = 0.25 })
			local sign = part(f, "PlungeSign", V3(3, 1, 0.1), pc * CF(4, 3.6, -3.05), DARK, M.SmoothPlastic)
			local sg = gui(sign, Enum.NormalId.Front, 40, 0, 60)
			label(sg, pool[1], { TextColor3 = pool[2] })
		end
		for k = 0, 1 do
			part(f, "RecoveryBed", V3(2.6, 0.6, 6.5), rec * CF(-8 + k * 4, 2.2, 8), WHITE, M.Leather, { collide = true })
			part(f, "RecoveryBedBase", V3(2, 1.9, 5), rec * CF(-8 + k * 4, 0.95, 8), Color3.fromRGB(190, 190, 196), M.Metal)
		end
	end
	local mc = siteCF("EliteMocap")
	if mc then
		-- motion capture studio: marker floor, camera tripods (they track you), live screens
		local floorPart = part(f, "MocapFloor", V3(20, 0.08, 20), mc * CF(0, 0.05, 0), Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
		local fsg = gui(floorPart, Enum.NormalId.Top, 4, 0.5, 120)
		for k = 0, 4 do
			frame(fsg, { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, k / 4), BackgroundColor3 = Color3.fromRGB(60, 200, 255), BackgroundTransparency = 0.3 })
			frame(fsg, { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(k / 4, 0), BackgroundColor3 = Color3.fromRGB(60, 200, 255), BackgroundTransparency = 0.3 })
		end
		mocap.cams = {}
		mocap.site = mc
		for k = 0, 5 do
			local a = k * math.pi / 3
			local pos = mc * CF(math.cos(a) * 11, 0, math.sin(a) * 11)
			part(f, "TripodLegs", V3(1.4, 6, 1.4), pos * CF(0, 3, 0), DARK, M.Metal)
			local head = part(f, "MocapCam", V3(0.9, 0.7, 1.3), CFrame.lookAt((pos * CF(0, 6.4, 0)).Position, (mc * CF(0, 3, 0)).Position), Color3.fromRGB(40, 40, 46), M.Metal)
			ball(f, "MocapLed", 0.25, head.CFrame * CF(0.3, 0.3, -0.66), Color3.fromRGB(255, 40, 40), M.Neon, { shadow = false })
			local att = Instance.new("Attachment")
			att.Position = V3(0, 0, -0.66)
			att.Parent = head
			local beam = Instance.new("Beam")
			beam.Attachment0 = att
			beam.Width0, beam.Width1 = 0.05, 0.05
			beam.LightEmission = 1
			beam.Color = ColorSequence.new(Color3.fromRGB(80, 220, 255))
			beam.Transparency = NumberSequence.new(0.35)
			beam.FaceCamera = true
			beam.Enabled = false
			beam.Parent = head
			table.insert(mocap.cams, beam)
		end
		for _, sx in ipairs({ -1, 1 }) do
			local scr = part(f, "MocapScreen", V3(7, 4, 0.2), mc * CF(sx * 6, 7, 10), Color3.fromRGB(10, 10, 14), M.Glass)
			local sg = gui(scr, Enum.NormalId.Front, 30, 0, 120)
			frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 14, 24) })
			label(sg, sx < 0 and "MOTION CAPTURE - LIVE" or "PUNCH VELOCITY", { TextColor3 = Color3.fromRGB(80, 220, 255), Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.04) })
			silhouette(sg, Color3.fromRGB(80, 220, 255), 0.4, 0.25, 1.5)
		end
	end
	local lab = siteCF("EliteLab")
	if lab then
		-- sports science lab: VO2 treadmill, force plates, analytics desk with your training numbers
		local tm = lab * CF(-5, 0, -4)
		part(f, "LabTreadmill", V3(3, 0.8, 8), tm * CF(0, 0.6, 0), Color3.fromRGB(30, 30, 34), M.Metal, { collide = true })
		part(f, "LabBelt", V3(2.4, 0.1, 7), tm * CF(0, 1.05, 0), Color3.fromRGB(16, 16, 18), M.Rubber)
		part(f, "LabConsole", V3(3, 2.4, 0.4), tm * CF(0, 4.2, -3.6), Color3.fromRGB(40, 40, 46), M.Metal)
		for _, x in ipairs({ -1.4, 1.4 }) do
			part(f, "LabRail", V3(0.2, 3.4, 0.2), tm * CF(x, 2.6, -3.4), Color3.fromRGB(190, 190, 196), M.Metal)
		end
		local plate = part(f, "ForcePlate", V3(4, 0.2, 4), lab * CF(5, 1.0, -4), Color3.fromRGB(60, 62, 70), M.Metal)
		local edge = part(f, "ForcePlateEdge", V3(4.2, 0.05, 4.2), plate.CFrame * CF(0, 0.1, 0), Color3.fromRGB(80, 220, 255), M.Neon, { transparency = 0.5, shadow = false })
		edge.CastShadow = false
		part(f, "LabDesk", V3(9, 3, 2.6), lab * CF(0, 1.5, 7), WHITE, M.SmoothPlastic, { collide = true })
		-- the monitors are filled by updateLabMonitors on every refresh (EliteDecor itself is only rebuilt when the center opens)
		labMonitors = {}
		for k = 0, 2 do
			local mon = part(f, "LabMonitor", V3(2.6, 1.7, 0.12), lab * CF(-3 + k * 3, 4.0, 7.6), Color3.fromRGB(12, 14, 20), M.Glass)
			local sg = gui(mon, Enum.NormalId.Front, 40, 0, 50)
			frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 16, 28) })
			local title = label(sg, "NO DATA", { TextColor3 = Color3.fromRGB(150, 220, 255), Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.04) })
			local bar = frame(sg, { Size = UDim2.fromScale(0, 0.2), Position = UDim2.fromScale(0.1, 0.55), BackgroundColor3 = Color3.fromRGB(60, 200, 110) })
			frame(sg, { Size = UDim2.fromScale(0.8, 0.02), Position = UDim2.fromScale(0.1, 0.78), BackgroundColor3 = Color3.fromRGB(80, 90, 110) })
			table.insert(labMonitors, { name = title, bar = bar })
		end
	end
end

-- the lab's three best drills, refreshed in place after every training session
local function updateLabMonitors(P)
	if #labMonitors == 0 or not labMonitors[1].name.Parent then
		return
	end
	local top = {}
	for id, r in pairs(type(P.records) == "table" and P.records or {}) do
		local best = type(r) == "table" and tonumber(r.best) or 0
		if best == best and best > 0 then
			table.insert(top, { id = id, best = best })
		end
	end
	table.sort(top, function(x, y)
		if x.best ~= y.best then
			return x.best > y.best
		end
		return tostring(x.id) < tostring(y.id) -- stable order on ties (pairs order is not)
	end)
	for k, mon in ipairs(labMonitors) do
		local e = top[k]
		local act = e and Config.FindById and Config.FindById(Config.Activities, e.id)
		local text = e and (act and act.name or tostring(e.id)):upper() or "NO DATA"
		if mon.name.Text ~= text then
			mon.name.Text = text
		end
		mon.bar.Size = UDim2.fromScale(0.8 * (e and math.clamp(e.best / 1.45, 0, 1) or 0), 0.2)
	end
end

local function updateElite(P)
	local open = gymTierIndex(P) >= 3
	setEliteOpen(open)
	local ready = siteCF("EliteMocap") ~= nil
	group("EliteDecor", (open and ready) and "open" or "", function(f)
		eliteDecor(f)
	end)
	updateLabMonitors(P)
	if not open then
		mocap.cams = {}
	end
end

------------------------------------------------------------------------
-- Fans, paparazzi, pedestrians, traffic (animated in one loop)
------------------------------------------------------------------------
local fans = {} -- { torso, head, sign, base, phase, rel = {...} }
local flashes = {} -- paparazzi flash parts
local peds = {}
local cars = {}

local SHIRTS = { Color3.fromRGB(200, 30, 36), Color3.fromRGB(30, 60, 170), Color3.fromRGB(240, 240, 240), Color3.fromRGB(24, 24, 28), Color3.fromRGB(240, 180, 30), Color3.fromRGB(40, 140, 70), Color3.fromRGB(120, 60, 160) }

local function skinColor(rng)
	local t = Looks.SkinTones[rng:NextInteger(1, #Looks.SkinTones)]
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function fanCount(P)
	local n = math.floor((P.popularity or 0) / 100 * 24)
	if #beltsOf(P) > 0 then
		n += 8
	end
	-- capped at 24 figures (7 parts each, ~170 parts) to stay inside the client part budget
	return math.clamp(n, 0, 24)
end

local function fanSigns(P)
	local nick = nickOf(P):upper()
	local list = { nick .. "!", "GO " .. surnameOf(P):upper() .. "!", "#1 FAN", "KO " .. nick }
	if #beltsOf(P) > 0 then
		table.insert(list, "CHAMP!")
		table.insert(list, "THE GOAT")
	end
	if P.camp and P.camp.offer then
		table.insert(list, "BEAT " .. (tostring(P.camp.offer.opp and P.camp.offer.opp.name or ""):match("(%S+)$") or ""):upper() .. "!")
	end
	return list
end

local function buildFans(f, P, n)
	fans = {}
	flashes = {}
	local rng = Random.new(#nickOf(P) * 97 + n)
	local spots = {}
	for _, name in ipairs({ "FanGymW", "FanGymE", "FanPlaza" }) do
		local cf, p = siteCF(name)
		if cf then
			table.insert(spots, { cf = cf, len = p and tonumber(p:GetAttribute("Len")) or 12, rows = p and tonumber(p:GetAttribute("Rows")) or 1 })
		end
	end
	-- the arena crowd forms during a camp or for a champion; a few wait at your home
	if P.camp or #beltsOf(P) > 0 then
		local cf, p = siteCF("FanArena")
		if cf then
			table.insert(spots, { cf = cf, len = p and tonumber(p:GetAttribute("Len")) or 20, rows = 2 })
		end
	end
	local homeSite = P.home == "House" and siteCF("HomeHouse") or (P.home == "Apartment" and siteCF("HomeApartment")) or (P.home == "Mansion" and siteCF("EstateGate"))
	if homeSite then
		local hcf = homeSite * CF(0, 0, P.home == "House" and -16 or -5)
		table.insert(spots, { cf = CFrame.lookAt(hcf.Position, homeSite.Position), len = 8, rows = 1 })
	end
	if #spots == 0 then
		return
	end
	local signs = fanSigns(P)
	local team = trunkColor(P)
	for i = 1, n do
		local s = spots[(i - 1) % #spots + 1]
		local row = rng:NextInteger(0, math.max(0, s.rows - 1))
		local base = s.cf * CF(rng:NextNumber(-s.len / 2, s.len / 2), 0, row * 1.8) * ANG(0, rng:NextNumber(-0.3, 0.3), 0)
		local shirt = rng:NextNumber() < 0.35 and team or SHIRTS[rng:NextInteger(1, #SHIRTS)]
		local text = rng:NextNumber() < 0.55 and signs[rng:NextInteger(1, #signs)] or nil
		local e = CityProps.Fan(f, base, shirt, skinColor(rng), text, WHITE, team)
		e.base = base
		e.phase = rng:NextNumber(0, math.pi * 2)
		e.rate = rng:NextNumber(2.5, 4)
		e.rel = {}
		for k, p in ipairs(e.parts) do
			e.rel[k] = base:ToObjectSpace(p.CFrame)
		end
		table.insert(fans, e)
	end
	-- an autograph prompt on the first fan by the gym
	local first = fans[1]
	if first then
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Sign autographs"
		pp.ObjectText = "Fans"
		pp.HoldDuration = 0.4
		pp.MaxActivationDistance = 10
		pp.RequiresLineOfSight = false
		pp:SetAttribute("Action", "Autograph")
		pp.Parent = first.torso
	end
	-- paparazzi for champions: camera block + a flash that pops near you
	if (P.tier or 1) >= 8 then
		local cf = siteCF("FanGymE")
		if cf then
			for k = 0, 1 do
				local pb = cf * CF(-5 + k * 10, 0, -2.5) * ANG(0, RAD(k == 0 and 20 or -20), 0)
				local e = CityProps.Fan(f, pb, DARK, skinColor(rng), nil, nil, nil, { pose = "camera" })
				-- the camera body in both hands in front of the face, the flash gun on top
				local cam = part(f, "PapCamera", V3(0.9, 0.65, 0.8), pb * CF(0, 4.7, -1.05), DARK, M.Metal)
				cyl(f, "PapLens", 0.6, 0.5, cam.CFrame * CF(0, 0, -0.65) * ANG(0, RAD(90), 0), Color3.fromRGB(30, 30, 34), M.Metal)
				local flash = part(f, "PapFlash", V3(0.5, 0.25, 0.1), cam.CFrame * CF(0, 0.45, -0.3), WHITE, M.Neon, { shadow = false, transparency = 1 })
				local l = Instance.new("PointLight")
				l.Range, l.Brightness, l.Shadows, l.Enabled = 14, 4, false, false
				l.Parent = flash
				e.base = pb
				e.phase = rng:NextNumber(0, 6)
				e.rate = 1.5
				table.insert(e.parts, cam)
				table.insert(e.parts, flash)
				e.rel = {}
				for k, p in ipairs(e.parts) do
					e.rel[k] = pb:ToObjectSpace(p.CFrame)
				end
				table.insert(fans, e)
				table.insert(flashes, { part = flash, light = l, t = 0 })
			end
		end
	end
end

local function updateFans(P)
	local n = fanCount(P)
	local ready = siteCF("FanGymW") ~= nil
	local key = (n > 0 and ready) and table.concat({ n, nickOf(P), tostring(P.home), tostring(P.camp ~= nil), table.concat(beltsOf(P), ","), tostring((P.tier or 1) >= 8) }, "|") or ""
	group("Fans", key, function(f)
		buildFans(f, P, n)
	end)
	if key == "" then
		fans = {}
		flashes = {}
	end
end

-- Main Street life: pedestrians on both sidewalks and everyday traffic in the two lanes.
-- Street cross-section (z): north curb 167 | eastbound lane ~169.6 | centre line 172.2 | westbound
-- lane ~174.8 | parked cars 180.2 (CityMap) | south curb 183. Hatchbacks are +-2.48 wide at the
-- wheels, so neighbouring lanes and the parked row never touch.
local PED_LANES = { 166.3, 184.6 }
local CAR_LANES = { { z = 169.6, dir = 1 }, { z = 174.8, dir = -1 } }
local CROSSWALK_X = { -12.5, 12.5 } -- module scope: animate() runs at 30 Hz and must not allocate
local HEADWAY = 14 -- studs kept to the car in front (a car is ~9 long)
local STREET_SPAN = 680 -- traffic loops x -340..340

local bulkParts, bulkCFrames = {}, {}
local function bulkSet(p, cf)
	table.insert(bulkParts, p)
	table.insert(bulkCFrames, cf)
end
local function directSet(p, cf)
	p.CFrame = cf
end

-- one walking pose; set = bulkSet in the loop, directSet when building (so nobody waits at the
-- world origin for the first animation frame)
local function posePed(e, swing, set)
	local cf = CF(e.x, 0.5, e.z) * ANG(0, e.dir > 0 and RAD(-90) or RAD(90), 0)
	local lift = math.abs(swing) * 0.08
	set(e.legL, cf * CF(-0.35, 2.2, 0) * ANG(swing, 0, 0) * CF(0, -1.1, 0))
	set(e.legR, cf * CF(0.35, 2.2, 0) * ANG(-swing, 0, 0) * CF(0, -1.1, 0))
	set(e.torso, cf * CF(0, 3.3 + lift, 0))
	set(e.head, cf * CF(0, 4.95 + lift, 0))
	-- arms swing against the legs, hinged at the shoulders
	set(e.armL, cf * CF(-0.98, 4.2 + lift, 0) * ANG(-swing * 0.8, 0, RAD(-4)) * CF(0, -1.0, 0))
	set(e.armR, cf * CF(0.98, 4.2 + lift, 0) * ANG(swing * 0.8, 0, RAD(4)) * CF(0, -1.0, 0))
	if e.bag then
		set(e.bag, cf * CF(1.6, 3.0 + lift, 0) * ANG(-swing * 0.3, 0, 0))
	end
end

local function poseCar(c, set)
	local cf = CF(c.x, 0.3, c.z) * ANG(0, c.dir > 0 and RAD(-90) or RAD(90), 0)
	for i, p in ipairs(c.parts) do
		set(p, cf * c.rel[i])
	end
end

local TRAFFIC_COLORS = { Color3.fromRGB(235, 235, 238), Color3.fromRGB(40, 80, 170), Color3.fromRGB(28, 28, 32), Color3.fromRGB(150, 152, 158), Color3.fromRGB(150, 30, 36), Color3.fromRGB(60, 110, 80) }

local function buildStreetLife(f, count)
	peds = {}
	cars = {}
	local rng = Random.new(77)
	for i = 1, count do
		local lane = PED_LANES[(i % 2) + 1]
		local e = { x = rng:NextNumber(-300, 300), z = lane + rng:NextNumber(-0.3, 0.3), dir = rng:NextNumber() < 0.5 and -1 or 1, speed = rng:NextNumber(3.5, 5.5), phase = rng:NextNumber(0, 6) }
		local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
		local pants = ({ Color3.fromRGB(40, 50, 80), Color3.fromRGB(30, 30, 34), Color3.fromRGB(120, 100, 80) })[rng:NextInteger(1, 3)]
		local skin = skinColor(rng)
		e.legL = part(f, "PedLeg", V3(0.6, 2.2, 0.6), CF(), pants, M.Fabric)
		e.legR = part(f, "PedLeg", V3(0.6, 2.2, 0.6), CF(), pants, M.Fabric)
		e.torso = part(f, "PedTorso", V3(1.5, 2.2, 0.8), CF(), shirt, M.Fabric)
		e.head = ball(f, "PedHead", 1.0, CF(), skin, M.SmoothPlastic)
		-- short sleeves: the arm is mostly skin with the shirt colour on the upper half
		local sleeve = rng:NextNumber() < 0.5
		e.armL = part(f, "PedArm", V3(0.45, 2.0, 0.45), CF(), sleeve and skin or shirt, M.Fabric)
		e.armR = part(f, "PedArm", V3(0.45, 2.0, 0.45), CF(), sleeve and skin or shirt, M.Fabric)
		if rng:NextNumber() < 0.4 then
			e.bag = part(f, "PedBag", V3(0.4, 1.2, 1.0), CF(), ({ Color3.fromRGB(150, 110, 70), DARK, Color3.fromRGB(200, 40, 40) })[rng:NextInteger(1, 3)], M.Leather)
		end
		posePed(e, 0, directSet)
		table.insert(peds, e)
	end
	for i = 1, 4 do
		local lane = CAR_LANES[(i % 2) + 1]
		local x0 = -300 + i * 140
		local c = { parts = {}, rel = {}, x = x0, z = lane.z, dir = lane.dir, speed = rng:NextNumber(16, 22), wait = 0 }
		-- built at its lane start, offsets taken from there (not from the world origin)
		local start = CF(x0, 0.3, lane.z) * ANG(0, lane.dir > 0 and RAD(-90) or RAD(90), 0)
		local m = CityProps.SportsCar(f, start, "Hatchback", TRAFFIC_COLORS[(i - 1) % #TRAFFIC_COLORS + 1])
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				-- moved every frame: never solid, so it can't shove you or block a ray
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				table.insert(c.parts, d)
				table.insert(c.rel, start:ToObjectSpace(d.CFrame))
			end
		end
		table.insert(cars, c)
	end
end

local function updateStreetLife(P)
	local count = math.clamp(10 + math.floor((P.popularity or 0) / 15), 10, 16)
	group("StreetLife", tostring(count), function(f)
		buildStreetLife(f, count)
	end)
end

------------------------------------------------------------------------
-- Other players: a fame tag over champions and famous fighters
------------------------------------------------------------------------
local function updateTags()
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= player then
			local char = pl.Character
			local head = char and char:FindFirstChild("Head")
			if head then
				local belts = tostring(pl:GetAttribute("Belts") or "")
				local fame = tonumber(pl:GetAttribute("Fame")) or 0
				local tier = tonumber(pl:GetAttribute("Tier")) or 1
				local show = belts ~= "" or fame >= 30 or tier >= 6
				local bb = head:FindFirstChild("FameTag")
				local text = show and (belts ~= "" and (belts:gsub(",", " ") .. " WORLD CHAMPION") or ((Config.Tiers[tier] and Config.Tiers[tier].name or "") .. "  -  FAME " .. fame)) or nil
				if show then
					if not bb then
						bb = Instance.new("BillboardGui")
						bb.Name = "FameTag"
						bb.Size = UDim2.fromOffset(220, 46)
						bb.StudsOffset = V3(0, 3.4, 0)
						bb.MaxDistance = 60
						bb.AlwaysOnTop = false
						bb.Parent = head
						label(bb, "", { Name = "Nick", TextColor3 = WHITE, Size = UDim2.fromScale(1, 0.55), TextStrokeTransparency = 0.4 })
						label(bb, "", { Name = "Title", TextColor3 = GOLD, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.58), TextStrokeTransparency = 0.4 })
					end
					local nick = tostring(pl:GetAttribute("Nick") or pl.DisplayName)
					bb.Nick.Text = "\"" .. nick .. "\""
					bb.Title.Text = text
					bb.Title.TextColor3 = belts ~= "" and GOLD or Color3.fromRGB(200, 200, 210)
				elseif bb then
					bb:Destroy()
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Mountain camp air (local Atmosphere tint while inside the camp pod, restored on leaving)
------------------------------------------------------------------------
local CAMP_CENTER = V3(-3000, 0, 3000)
local campSaved
local function updateCampAir(pos)
	-- hands off while a fight (or spar) is on: VenueFX snapshots the Atmosphere at Start and puts it
	-- back at Stop (before InFight clears). If we restored here mid-fight (the fight starts while you
	-- are still at camp, then the arena move takes you "outside") we would overwrite the venue air and
	-- VenueFX would later put the camp haze back over the city. Left alone, campSaved still holds the
	-- city values and the first tick after the fight restores them (or keeps the tint at camp).
	local busy = player:GetAttribute("Busy")
	if player:GetAttribute("InFight") == true or busy == "fight" or busy == "spar" then
		return
	end
	local inside = pos and (V3(pos.X, 0, pos.Z) - CAMP_CENTER).Magnitude < 200
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		return
	end
	if inside and not campSaved then
		campSaved = { Density = atm.Density, Color = atm.Color, Decay = atm.Decay, Haze = atm.Haze, Glare = atm.Glare }
		atm.Density = 0.42
		atm.Color = Color3.fromRGB(214, 226, 240)
		atm.Decay = Color3.fromRGB(150, 170, 200)
		atm.Haze = 2.4
		atm.Glare = 0.05
	elseif not inside and campSaved then
		for k, v in pairs(campSaved) do
			atm[k] = v
		end
		campSaved = nil
	end
end

------------------------------------------------------------------------
-- The loop
------------------------------------------------------------------------
local NEAR = 180
------------------------------------------------------------------------
-- Window grids: CityMap stores only the spec of each window grid as attributes (WinFace, WinTop,
-- WinSpan, WinRows, WinCols, WinLit, WinSeed, WinRange) on the skyline towers and the Main Street
-- upper floors. The Frames are drawn here for the faces within their range of the camera (WinRange,
-- else WIN_RANGE) and dropped again further out, so nothing replicates. The skyline towers carry a
-- range past the whole map: they all face the centre, so the faces you see are across the ring
------------------------------------------------------------------------
local WIN_RANGE = 460 -- the Main Street shop fronts
local WIN_HYST = 80 -- hysteresis: built inside the range, destroyed beyond range + this
local WIN_MAX = 48 -- grids alive at once (nearest first)
local WIN_STEP = 8 -- grids built per pass (the first pass would otherwise make ~1,700 Frames at once)
local winParts = {} -- every part carrying a window spec
local winRange = {} -- part -> its draw range
local winLive = {} -- part -> SurfaceGui
local winScanAt = 0
local winOrder = {} -- reused every pass (no per-pass allocation beyond the sort)

local function scanWindowParts()
	table.clear(winParts)
	table.clear(winRange)
	local c = cityRoot()
	if not c then
		return
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("WinRows") then
			table.insert(winParts, d)
			winRange[d] = tonumber(d:GetAttribute("WinRange")) or WIN_RANGE
		end
	end
end

-- A window row is one Frame per run of up to WIN_BAND windows, not one per window: its UIGradient
-- cuts it into the windows (Transparency: clear in the gaps, so the facade shows through) and
-- colours each one (lit or dark). Same windows, same colours (same random draw) as one Frame per
-- window, in about a third of the instances (a 5-window run needs 18 transparency keypoints;
-- Roblox allows 20)
local WIN_BAND = 5
local WIN_EDGE = 1e-3 -- the width of a window's edge in the gradient (sharp)
local WIN_DARK = Color3.fromRGB(34, 44, 58)
local winTK, winCK = {}, {} -- reused keypoint lists

local function windowBand(sg, rowY, rowH, cols, c0, c1, colours)
	local left, right = (c0 + 0.19) / cols, (c1 + 0.81) / cols
	local f = frame(sg, { Size = UDim2.fromScale(right - left, rowH), Position = UDim2.fromScale(left, rowY), BackgroundColor3 = colours[c0] })
	if c1 == c0 then
		return f
	end
	f.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient's colours multiply it
	table.clear(winTK)
	table.clear(winCK)
	local w = right - left
	for c = c0, c1 do
		local a = c == c0 and 0 or ((c + 0.19) / cols - left) / w
		local b = c == c1 and 1 or ((c + 0.81) / cols - left) / w
		if c > c0 then
			table.insert(winTK, NumberSequenceKeypoint.new(a - WIN_EDGE, 1))
		end
		table.insert(winTK, NumberSequenceKeypoint.new(a, 0))
		table.insert(winTK, NumberSequenceKeypoint.new(b, 0))
		if c < c1 then
			table.insert(winTK, NumberSequenceKeypoint.new(b + WIN_EDGE, 1))
		end
		table.insert(winCK, ColorSequenceKeypoint.new(a, colours[c]))
		table.insert(winCK, ColorSequenceKeypoint.new(b, colours[c]))
	end
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(winCK)
	g.Transparency = NumberSequence.new(winTK)
	g.Parent = f
	return f
end

local function buildWindowGrid(p)
	local rows, cols = tonumber(p:GetAttribute("WinRows")) or 1, tonumber(p:GetAttribute("WinCols")) or 1
	local top, spanH = tonumber(p:GetAttribute("WinTop")) or 0, tonumber(p:GetAttribute("WinSpan")) or 1
	local lit = tonumber(p:GetAttribute("WinLit")) or 0.35
	local rng = Random.new(tonumber(p:GetAttribute("WinSeed")) or 1)
	local okFace, face = pcall(function()
		return Enum.NormalId[p:GetAttribute("WinFace") or "Front"]
	end)
	local sg = gui(p, okFace and face or Enum.NormalId.Front, 4, 0.15, (winRange[p] or WIN_RANGE) + WIN_HYST + 60)
	sg.Name = "Windows"
	local colours = {}
	for r = 0, rows - 1 do
		-- (the draw order is the old per-window one: the same windows light up)
		for c = 0, cols - 1 do
			colours[c] = rng:NextNumber() < lit and Color3.fromRGB(255, 214 + rng:NextInteger(0, 30), 140 + rng:NextInteger(0, 40)) or WIN_DARK
		end
		local bands = math.ceil(cols / WIN_BAND)
		for b = 0, bands - 1 do
			-- runs of even length (6 windows: 3 + 3, not 5 + 1)
			local c0 = math.floor(b * cols / bands)
			local c1 = math.floor((b + 1) * cols / bands) - 1
			windowBand(sg, top + (r + 0.2) / rows * spanH, spanH / rows * 0.6, cols, c0, c1, colours)
		end
	end
	return sg
end

local function updateWindowGrids(camPos, now)
	if #winParts == 0 or now >= winScanAt then
		winScanAt = now + 15 -- the city streams in after the client starts; a cheap rescan
		scanWindowParts()
	end
	table.clear(winOrder)
	for _, p in ipairs(winParts) do
		if p.Parent then
			local d = (p.Position - camPos).Magnitude
			local range = winRange[p] or WIN_RANGE
			local sg = winLive[p]
			if sg and (d > range + WIN_HYST or not sg.Parent) then
				sg:Destroy()
				winLive[p] = nil
			elseif not sg and d < range then
				table.insert(winOrder, p)
			end
		elseif winLive[p] then
			winLive[p]:Destroy()
			winLive[p] = nil
		end
	end
	local alive = 0
	for _ in pairs(winLive) do
		alive += 1
	end
	if #winOrder > 0 and alive < WIN_MAX then
		table.sort(winOrder, function(a, b)
			return (a.Position - camPos).Magnitude < (b.Position - camPos).Magnitude
		end)
		for i, p in ipairs(winOrder) do
			if alive >= WIN_MAX or i > WIN_STEP then
				break
			end
			winLive[p] = buildWindowGrid(p)
			alive += 1
		end
	end
end

local acc, slowAcc, tagAcc = 0, 0, 0
local clock = 0

local function pushBulk()
	if #bulkParts == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(bulkParts) do
			p.CFrame = bulkCFrames[i]
		end
	end
	table.clear(bulkParts)
	table.clear(bulkCFrames)
end

local function animate(dt, camPos, rootPos)
	clock += dt
	-- fans: bob, cheer and turn towards you when you are close; signs sway (the whole figure moves
	-- as one, so arms stay on the shoulders and hands on the sign)
	for _, e in ipairs(fans) do
		if e.torso.Parent and (e.base.Position - camPos).Magnitude < NEAR then
			local near = rootPos and (e.base.Position - rootPos).Magnitude or 999
			local excite = near < 26 and 1 or 0.25
			local hop = math.abs(math.sin(clock * e.rate + e.phase)) * 0.35 * excite
			local base = e.base
			if near < 32 and rootPos then
				local look = V3(rootPos.X, base.Position.Y, rootPos.Z)
				if (look - base.Position).Magnitude > 0.5 then
					base = CFrame.lookAt(base.Position, look)
				end
			end
			local moved = base * CF(0, hop, 0)
			for k, p in ipairs(e.parts) do
				if p == e.sign then
					bulkSet(p, moved * e.rel[k] * ANG(0, 0, math.sin(clock * 3 + e.phase) * 0.08 * excite))
				else
					bulkSet(p, moved * e.rel[k])
				end
			end
		end
	end
	-- paparazzi flashes pop when you walk by
	for _, fl in ipairs(flashes) do
		fl.t -= dt
		if fl.t <= 0 then
			local close = rootPos and (fl.part.Position - rootPos).Magnitude < 40
			if close and math.random() < 0.08 then
				fl.t = 0.08
				fl.part.Transparency = 0
				fl.light.Enabled = true
			else
				fl.part.Transparency = 1
				fl.light.Enabled = false
			end
		end
	end
	-- Main Street (only when the camera is anywhere near it)
	if math.abs(camPos.Z - 176) < 230 and math.abs(camPos.X) < 520 then
		for _, e in ipairs(peds) do
			e.x += e.dir * e.speed * dt
			if e.x > 318 or e.x < -318 then
				e.dir = -e.dir
				e.x = math.clamp(e.x, -318, 318)
			end
			if math.abs(e.x - camPos.X) < 220 then
				posePed(e, math.sin(clock * e.speed * 1.6 + e.phase) * 0.5, bulkSet)
			end
		end
		for _, c in ipairs(cars) do
			-- distance to the nearest car ahead in the same lane (the street wraps at +-340)
			local gap = math.huge
			for _, o in ipairs(cars) do
				if o ~= c and o.z == c.z then
					local dx = (o.x - c.x) * c.dir
					if dx < 0 then
						dx += STREET_SPAN
					end
					gap = math.min(gap, dx)
				end
			end
			if c.wait > 0 then
				c.wait -= dt
			else
				local before = c.x
				-- never closer than HEADWAY: queue behind a car that stopped at a crosswalk
				c.x += c.dir * math.min(c.speed * dt, math.max(0, gap - HEADWAY))
				-- a short stop at the crosswalks now and then
				for _, cw in ipairs(CROSSWALK_X) do
					local edge = cw - c.dir * 7
					if (before - edge) * (c.x - edge) < 0 and math.random() < 0.35 then
						c.wait = 2 + math.random() * 2
					end
				end
				if c.x > STREET_SPAN / 2 then
					c.x -= STREET_SPAN
				elseif c.x < -STREET_SPAN / 2 then
					c.x += STREET_SPAN
				end
			end
			if math.abs(c.x - camPos.X) < 260 then
				poseCar(c, bulkSet)
			end
		end
	end
	pushBulk()
end

local function step(dt)
	acc += dt
	slowAcc += dt
	tagAcc += dt
	if acc < 1 / 30 then
		return
	end
	local frameDt = acc
	acc = 0
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local rootPos = hrp and hrp.Position
	if player:GetAttribute("InFight") ~= true then
		animate(frameDt, cam.CFrame.Position, rootPos)
	end
	if slowAcc >= 0.25 then
		slowAcc = 0
		updateCampAir(rootPos)
		-- motion capture: the cameras lock on while you stand in the studio
		local on = rootPos and mocap.site and (rootPos - mocap.site.Position).Magnitude < 13
		if on and hrp then
			local att = hrp:FindFirstChild("MocapTarget")
			if not att then
				att = Instance.new("Attachment")
				att.Name = "MocapTarget"
				att.Position = V3(0, 0.6, 0)
				att.Parent = hrp
			end
			for _, b in ipairs(mocap.cams) do
				if b.Parent then
					b.Attachment1 = att
					b.Enabled = true
				end
			end
		else
			for _, b in ipairs(mocap.cams) do
				if b.Parent then
					b.Enabled = false
				end
			end
		end
		-- cryo fog only near the cabin (particles cost fill rate)
		local decor = groups.EliteDecor and groups.EliteDecor.folder
		local fog = decor and decor:FindFirstChild("CryoFog", true)
		if fog then
			fog.Enabled = rootPos ~= nil and (fog.Parent.Position - rootPos).Magnitude < 60
		end
	end
	if tagAcc >= 1 then
		tagAcc = 0
		pcall(updateTags)
		pcall(updateWindowGrids, cam.CFrame.Position, os.clock())
	end
end

------------------------------------------------------------------------
-- API
------------------------------------------------------------------------
local started = false
local retryAt = 0

function CityVisuals.Start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and not CityVisuals.warned then
			CityVisuals.warned = true
			warn("[CityVisuals]", err)
		end
		-- the city replicates after the client starts: re-run the last refresh until the sites exist
		if lastP and retryAt > 0 and os.clock() >= retryAt then
			retryAt = 0
			CityVisuals.Refresh(lastP)
		end
	end)
end

-- P = the profile summary (State.P). Cheap when nothing changed: every piece is key-gated.
function CityVisuals.Refresh(P)
	if type(P) ~= "table" or not P.created or P.retired then
		return
	end
	lastP = P
	CityVisuals.Start()
	if not cityRoot() then
		retryAt = os.clock() + 2
		return
	end
	local steps = { updateHomes, updateCars, updateBillboards, updateWindows, updateMedia, updateLegacy, updateElite, updateFans, updateStreetLife }
	for _, fn in ipairs(steps) do
		local ok, err = pcall(fn, P)
		if not ok then
			warn("[CityVisuals] " .. tostring(err))
		end
	end
	-- some sites may still be streaming in: look again shortly
	if not siteCF("CarBay") or not siteCF("HomeMansion") then
		retryAt = os.clock() + 3
	end
end

-- city prompt actions (ClientMain forwards anything it does not handle itself). -> handled
function CityVisuals.Prompt(action, prompt)
	local P = State.P
	if not (P and P.created) or P.retired or State.inFight() then
		return false
	end
	if action == "Home" then
		local kind = prompt and prompt:GetAttribute("Kind")
		if kind and P.owned and P.owned[kind] then
			local r = State.req("TravelHome", kind)
			if not r.ok then
				State.toast(r.err or "Can't go home right now.", Color3.fromRGB(220, 40, 45))
			end
		else
			local item = kind and Catalog.Find(Catalog.Shop, kind)
			State.toast(item and string.format("%s - for sale: %s. Buy it in the Career Hub (Shop).", item.name, Config.Money(item.price)) or "Not your place.", GOLD)
			if State.open.Hub then
				State.open.Hub("Shop")
			end
		end
		return true
	elseif action == "LeaveHome" then
		local r = State.req("LeaveHome")
		if not r.ok then
			State.toast(r.err or "Can't leave right now.", Color3.fromRGB(220, 40, 45))
		end
		return true
	elseif action == "LeaveCamp" then
		local r = State.req("TravelPlace", "gym")
		if not r.ok then
			State.toast(r.err or "Can't leave right now.", Color3.fromRGB(220, 40, 45))
		end
		return true
	elseif action == "Autograph" then
		local r = State.req("Autograph")
		State.toast(r.ok and "The fans go wild. Popularity up!" or (r.err or "Not now."), r.ok and GOLD or Color3.fromRGB(220, 40, 45))
		return true
	elseif action == "Flex" then
		-- safety net for the gym mirror's FlexPrompt (F asks ClientMain for its own branch above the
		-- catch-all; this only runs if that branch is missing): next pose, then face the glass
		local poses = (Config.Pump and Config.Pump.poses) or { "flex_most" }
		local n = ((prompt and prompt:GetAttribute("FlexIdx")) or 0) % #poses + 1
		if prompt then
			prompt:SetAttribute("FlexIdx", n)
		end
		local r = State.req("Flex", poses[n])
		if r.ok then
			local face = prompt and prompt:GetAttribute("FaceAt")
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and typeof(face) == "Vector3" then
				local look = V3(face.X, root.Position.Y, face.Z)
				if (look - root.Position).Magnitude > 0.5 then
					root.CFrame = CFrame.lookAt(root.Position, look)
				end
			end
		else
			State.toast(r.err or "Can't flex right now.", Color3.fromRGB(220, 40, 45))
		end
		return true
	end
	return CityStores.Open(action, prompt and prompt:GetAttribute("Store")) == true
end

-- for the Hub / tests: what the city currently shows
CityVisuals.FanCount = fanCount
CityVisuals.StarList = starList
CityVisuals.AdContent = adContent

return CityVisuals
