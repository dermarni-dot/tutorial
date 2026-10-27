-- CityHomes: the players' home interiors. Per player and server-built (a teleported character must
-- land on real collision), far outside the map, built on demand when the player travels home and
-- furnished from the profile: home kind, add-ons (Home Gym, Trophy Room, Recovery Suite, Pool Deck),
-- belts, fight posters from the history, the record on the TV. Rebuilt only when that signature
-- changes; released when the player leaves. Every home: Sleep prompt by the bed, Exit prompt by the
-- door. CityMap re-exports Enter / Exit / Release / HomeSpec / HomeKind under its old names.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GymDecor = require(script.Parent:WaitForChild("GymDecor"))
local K = require(script.Parent:WaitForChild("CityKit"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local CityHomes = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material
local C = K.C
local part, cyl, vcyl, ball, blob = K.part, K.cyl, K.vcyl, K.ball, K.blob
local label, frame, gui, spot, point, emitter = K.label, K.frame, K.gui, K.spot, K.point, K.emitter
local promptPart, lightZone, roomLight = K.promptPart, K.lightZone, K.roomLight

local homesFolder
local homeSlots = {} -- slot index -> player
local homes = {} -- player -> { model, kind, sig, spawn, slot, tokens, tokAt }
-- interior rebuild budget per player: a burst of REBUILD_BURST, refilling one per REBUILD_GAP seconds
local REBUILD_BURST = 3
local REBUILD_GAP = 1.5

local HOME_SPEC = {
	Apartment = { w = 46, d = 30, h = 13, zone = "Apartment", floor = Color3.fromRGB(150, 112, 78), floorMat = M.WoodPlanks,
		wall = Color3.fromRGB(226, 222, 214), view = "city", sheet = Color3.fromRGB(60, 70, 90), sofa = Color3.fromRGB(70, 72, 80), lights = 3 },
	House = { w = 58, d = 38, h = 14, zone = "Apartment", floor = Color3.fromRGB(170, 132, 92), floorMat = M.WoodPlanks,
		wall = Color3.fromRGB(236, 230, 218), view = "suburb", sheet = Color3.fromRGB(150, 60, 50), sofa = Color3.fromRGB(110, 86, 64), lights = 4 },
	Mansion = { w = 96, d = 60, h = 20, zone = "Mansion", floor = Color3.fromRGB(236, 232, 224), floorMat = M.Marble,
		wall = Color3.fromRGB(246, 244, 238), view = "coast", sheet = Color3.fromRGB(240, 236, 226), sofa = Color3.fromRGB(240, 236, 226), lights = 6 },
}
CityHomes.HomeSpec = HOME_SPEC

local function homeKindFor(profile, kind)
	local owned = type(profile.owned) == "table" and profile.owned or {}
	if kind and HOME_SPEC[kind] and owned[kind] == true then
		return kind
	end
	for _, id in ipairs({ "Mansion", "House", "Apartment" }) do
		if owned[id] == true then
			return id
		end
	end
	return nil
end
CityHomes.HomeKind = homeKindFor

function CityHomes.Init(folder)
	homesFolder = folder
end

-- what you see through the window wall: a lit backdrop panel outside the glass
local function homeView(f, base, w, h, d, view)
	local panel = part(f, "WindowView", V3(w * 1.6, h * 2.4, 0.2), base * CF(0, h * 0.8, -d / 2 - 14), Color3.fromRGB(120, 160, 210), M.SmoothPlastic, { shadow = false })
	local sg = gui(panel, Enum.NormalId.Back, 3, 0, 300)
	local sky = frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) })
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	local rng = Random.new(#view * 31)
	if view == "city" then
		grad.Color = ColorSequence.new(Color3.fromRGB(40, 60, 110), Color3.fromRGB(250, 160, 110))
		grad.Parent = sky
		for k = 0, 15 do
			local th = rng:NextNumber(0.25, 0.6)
			local tw = rng:NextNumber(0.04, 0.08)
			local tower = frame(sg, { Size = UDim2.fromScale(tw, th), Position = UDim2.fromScale(k / 16 + rng:NextNumber(-0.01, 0.01), 1 - th), BackgroundColor3 = Color3.fromRGB(30 + k % 3 * 8, 34, 50) })
			for r = 0, 3 do
				frame(tower, { Size = UDim2.fromScale(0.7, 0.03), Position = UDim2.fromScale(0.15, 0.1 + r * 0.2), BackgroundColor3 = Color3.fromRGB(255, 214, 140), BackgroundTransparency = rng:NextNumber() < 0.5 and 0 or 0.7 })
			end
		end
	elseif view == "suburb" then
		grad.Color = ColorSequence.new(Color3.fromRGB(110, 170, 230), Color3.fromRGB(220, 236, 250))
		grad.Parent = sky
		for k = 0, 3 do
			local hill = frame(sg, { Size = UDim2.fromScale(0.6, 0.5), Position = UDim2.fromScale(k * 0.3 - 0.15, 0.62 + (k % 2) * 0.06), BackgroundColor3 = Color3.fromRGB(70 + k * 8, 130 + k * 6, 70) })
			Instance.new("UICorner", hill).CornerRadius = UDim.new(0.5, 0)
		end
		for k = 0, 9 do
			local tree = frame(sg, { Size = UDim2.fromScale(0.07, 0.16), Position = UDim2.fromScale(k * 0.1 + 0.01, 0.58 + rng:NextNumber(0, 0.08)), BackgroundColor3 = Color3.fromRGB(40, 100 + k % 3 * 12, 50) })
			Instance.new("UICorner", tree).CornerRadius = UDim.new(0.5, 0)
		end
		frame(sg, { Size = UDim2.fromScale(1, 0.12), Position = UDim2.fromScale(0, 0.88), BackgroundColor3 = Color3.fromRGB(90, 140, 70) })
	else
		grad.Color = ColorSequence.new(Color3.fromRGB(80, 140, 220), Color3.fromRGB(255, 210, 160))
		grad.Parent = sky
		local sun = frame(sg, { Size = UDim2.fromScale(0.09, 0.14), Position = UDim2.fromScale(0.7, 0.42), BackgroundColor3 = Color3.fromRGB(255, 236, 170) })
		Instance.new("UICorner", sun).CornerRadius = UDim.new(0.5, 0)
		local sea = frame(sg, { Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.6), BackgroundColor3 = Color3.new(1, 1, 1) })
		local sg2 = Instance.new("UIGradient")
		sg2.Rotation = 90
		sg2.Color = ColorSequence.new(Color3.fromRGB(70, 150, 200), Color3.fromRGB(20, 70, 130))
		sg2.Parent = sea
		for k = 0, 2 do
			frame(sg, { Size = UDim2.fromScale(0.3, 0.004), Position = UDim2.fromScale(0.55 + k * 0.05, 0.63 + k * 0.03), BackgroundColor3 = Color3.fromRGB(255, 240, 200) })
		end
		for _, x in ipairs({ 0.06, 0.88 }) do
			frame(sg, { Size = UDim2.fromScale(0.012, 0.4), Position = UDim2.fromScale(x, 0.34), BackgroundColor3 = Color3.fromRGB(40, 36, 30) })
			local crown = frame(sg, { Size = UDim2.fromScale(0.1, 0.06), Position = UDim2.fromScale(x - 0.044, 0.31), BackgroundColor3 = Color3.fromRGB(30, 50, 30) })
			Instance.new("UICorner", crown).CornerRadius = UDim.new(0.5, 0)
		end
	end
	return panel
end

-- floor, ceiling, three solid walls, a floor-to-ceiling window wall at local -Z, lights, zone
local function homeShell(f, base, spec)
	local w, d, h = spec.w, spec.d, spec.h
	part(f, "HomeFloor", V3(w + 2, 1, d + 2), base * CF(0, -0.5, 0), spec.floor, spec.floorMat, { collide = true })
	part(f, "HomeCeiling", V3(w + 2, 1, d + 2), base * CF(0, h + 0.5, 0), Color3.fromRGB(244, 242, 236), M.SmoothPlastic, { collide = true })
	part(f, "HomeWall", V3(w + 2, h, 1), base * CF(0, h / 2, d / 2 + 0.5), spec.wall, M.SmoothPlastic, { collide = true })
	for _, sx in ipairs({ -1, 1 }) do
		part(f, "HomeWall", V3(1, h, d + 2), base * CF(sx * (w / 2 + 0.5), h / 2, 0), spec.wall, M.SmoothPlastic, { collide = true })
	end
	part(f, "HomeSill", V3(w, 1.2, 1), base * CF(0, 0.6, -d / 2 - 0.5), spec.wall, M.SmoothPlastic, { collide = true })
	part(f, "HomeGlass", V3(w, h - 1.6, 0.3), base * CF(0, 1.2 + (h - 1.6) / 2, -d / 2 - 0.5), Color3.fromRGB(200, 225, 240), M.Glass, { transparency = 0.7, reflect = 0.08, collide = true, shadow = false })
	part(f, "HomeHeader", V3(w, 0.4, 1), base * CF(0, h - 0.2, -d / 2 - 0.5), spec.wall, M.SmoothPlastic)
	local n = math.floor(w / 9)
	for k = 0, n do
		part(f, "WindowMullion", V3(0.35, h - 1.6, 0.5), base * CF(-w / 2 + k * w / n, 1.2 + (h - 1.6) / 2, -d / 2 - 0.5), Color3.fromRGB(34, 34, 38), M.Metal)
	end
	homeView(f, base, w, h, d, spec.view)
	for k = 1, spec.lights do
		local x = -w / 2 + (k - 0.5) * w / spec.lights
		roomLight(f, base * CF(x, h - 1, 2), Color3.fromRGB(255, 232, 205), math.max(22, h * 1.8), 0.9)
		part(f, "CeilingLight", V3(2.6, 0.15, 2.6), base * CF(x, h - 0.08, 2), Color3.fromRGB(255, 248, 236), M.Neon, { shadow = false })
	end
	lightZone(f, "HomeZone", V3(w, h, d), base * CF(0, h / 2, 0), spec.zone)
end

local function bed(f, cf, w, len, sheet)
	part(f, "BedFrame", V3(w + 0.6, 1.4, len + 0.6), cf * CF(0, 0.7, 0), Color3.fromRGB(70, 50, 36), M.Wood, { collide = true })
	part(f, "Mattress", V3(w, 0.9, len), cf * CF(0, 1.85, 0), Color3.fromRGB(242, 242, 238), M.Fabric)
	part(f, "Blanket", V3(w + 0.12, 0.3, len * 0.62), cf * CF(0, 2.3, -len * 0.19), sheet, M.Fabric)
	part(f, "Headboard", V3(w + 0.6, 4.2, 0.5), cf * CF(0, 2.6, len / 2 + 0.3), Color3.fromRGB(60, 44, 32), M.Fabric)
	for _, x in ipairs({ -1, 1 }) do
		blob(f, "Pillow", V3(w * 0.38, 0.65, 1.6), cf * CF(x * w * 0.22, 2.55, len / 2 - 1.1), Color3.fromRGB(250, 250, 248), M.Fabric)
		part(f, "Nightstand", V3(2, 2, 2), cf * CF(x * (w / 2 + 1.8), 1, len / 2 - 1), Color3.fromRGB(70, 50, 36), M.Wood, { collide = true })
	end
	local lamp = blob(f, "BedLamp", V3(1, 1.2, 1), cf * CF(w / 2 + 1.8, 2.8, len / 2 - 1), Color3.fromRGB(255, 236, 200), M.SmoothPlastic, { shadow = false })
	point(lamp, Color3.fromRGB(255, 210, 160), 10, 0.7)
end

local function sofa(f, cf, len, color)
	part(f, "SofaBase", V3(len, 1.6, 3.2), cf * CF(0, 0.8, 0), color, M.Fabric, { collide = true })
	part(f, "SofaBack", V3(len, 2.4, 0.9), cf * CF(0, 2.2, 1.2), color, M.Fabric)
	for _, x in ipairs({ -1, 1 }) do
		part(f, "SofaArm", V3(0.9, 2.3, 3.2), cf * CF(x * (len / 2 - 0.45), 1.15, 0), color, M.Fabric)
		part(f, "SofaCushion", V3(len / 2 - 1.1, 0.55, 2.3), cf * CF(x * (len / 4 - 0.2), 1.85, -0.2), color:Lerp(Color3.new(1, 1, 1), 0.12), M.Fabric)
	end
end

local function kitchen(f, cf, len, cab, top)
	part(f, "Cabinets", V3(len, 3.2, 2.2), cf * CF(0, 1.6, 0), cab, M.SmoothPlastic, { collide = true })
	part(f, "Worktop", V3(len + 0.2, 0.25, 2.4), cf * CF(0, 3.3, 0), top, M.Marble)
	part(f, "UpperCabinets", V3(len, 2.4, 1.2), cf * CF(0, 7.0, 0.5), cab, M.SmoothPlastic)
	part(f, "Fridge", V3(3, 7.2, 2.6), cf * CF(len / 2 + 1.6, 3.6, 0.1), Color3.fromRGB(200, 202, 206), M.Metal, { collide = true, reflect = 0.1 })
	part(f, "Hob", V3(2.4, 0.08, 1.6), cf * CF(-len / 4, 3.45, 0), Color3.fromRGB(20, 20, 22), M.Glass)
	part(f, "Sink", V3(2, 0.1, 1.4), cf * CF(len / 4, 3.44, 0), Color3.fromRGB(180, 184, 190), M.Metal)
	part(f, "Kettle", V3(0.7, 0.9, 0.7), cf * CF(0, 3.9, 0.2), Color3.fromRGB(200, 40, 40), M.SmoothPlastic)
end

-- "SURNAME vs OPP / WIN by KO R3" poster from a history entry
local function fightPoster(f, cf, entry, surname)
	local p = part(f, "FightPoster", V3(3.2, 4.6, 0.12), cf, C.black, M.SmoothPlastic)
	local win = entry.outcome == "win"
	local opp = tostring(entry.opp or "?")
	local oppLast = opp:match("(%S+)$") or opp
	GymDecor.PosterGui(p, Enum.NormalId.Front, {
		bg = win and Color3.fromRGB(18, 18, 22) or Color3.fromRGB(60, 20, 22), accent = win and C.gold or C.red,
		top = tostring(entry.kind or "FIGHT NIGHT"):upper(), title = string.format("%s\nvs\n%s", surname:upper(), oppLast:upper()),
		sub = string.format("%s - %s R%d", tostring(entry.outcome or ""):upper(), tostring(entry.method or ""), tonumber(entry.round) or 0),
		foot = string.format("%s - DAY %d", tostring(entry.venue or "WCB"):upper(), tonumber(entry.day) or 0),
	})
	return p
end

local BELT_COLORS = { REGIONAL = Color3.fromRGB(190, 190, 200), NATIONAL = Color3.fromRGB(205, 127, 50) }
local function beltList(profile)
	local list = {}
	local reg = type(profile.regional) == "table" and profile.regional or {}
	if reg.regional then
		table.insert(list, "REGIONAL")
	end
	if reg.national then
		table.insert(list, "NATIONAL")
	end
	for _, org in ipairs(Config.Orgs) do
		if type(profile.belts) == "table" and profile.belts[org] then
			table.insert(list, org)
		end
	end
	return list
end

local function belt(f, cf, name)
	local col = BELT_COLORS[name] or C.gold
	part(f, "BeltStrap", V3(3.4, 0.7, 0.18), cf, Color3.fromRGB(20, 20, 22), M.Leather)
	cyl(f, "BeltPlate", 0.2, 1.4, cf * CF(0, 0, -0.12) * ANG(0, RAD(90), 0), col, M.Metal, { reflect = 0.3 })
	for _, x in ipairs({ -1.1, 1.1 }) do
		part(f, "BeltSidePlate", V3(0.6, 0.55, 0.08), cf * CF(x, 0, -0.12), col, M.Metal, { reflect = 0.3 })
	end
	local tagPart = part(f, "BeltTag", V3(1.6, 0.35, 0.05), cf * CF(0, -0.75, -0.1), Color3.fromRGB(20, 20, 22), M.SmoothPlastic)
	GymDecor.Sign(tagPart, Enum.NormalId.Front, name, col, nil, 60)
end

local function trophy(f, cf, h, color)
	vcyl(f, "TrophyBase", 0.5, 1.1, cf, Color3.fromRGB(40, 30, 24), M.Wood)
	vcyl(f, "TrophyStem", h * 0.45, 0.25, cf * CF(0, 0.5, 0), color, M.Metal, { reflect = 0.3 })
	blob(f, "TrophyCup", V3(0.9, h * 0.4, 0.9), cf * CF(0, 0.5 + h * 0.6, 0), color, M.Metal, { reflect = 0.3 })
end

local function homeGym(f, cf, big)
	part(f, "GymMat", V3(big and 16 or 10, 0.15, big and 12 or 8), cf * CF(0, 0.08, 0), Color3.fromRGB(32, 32, 35), M.Rubber)
	part(f, "BagChain", V3(0.15, 3, 0.15), cf * CF(-2.5, 9.5, 0), C.steelLight, M.Metal)
	vcyl(f, "HomeBag", 4.4, 2, cf * CF(-2.5, 3.6, 0), Color3.fromRGB(150, 24, 30), M.Leather, { collide = true })
	part(f, "RackFrame", V3(4.4, 2.2, 1.2), cf * CF(2.8, 1.1, 2.6), C.steel, M.Metal, { collide = true })
	for k = 0, 3 do
		cyl(f, "Dumbbell", 1.3, 0.45 + k * 0.08, cf * CF(1.3 + k * 1.0, 2.45, 2.6), Color3.fromRGB(30, 30, 32), M.Metal)
	end
	if big then
		local ring = cf * CF(3, 0, -1)
		local half = 6
		part(f, "RingFloor", V3(half * 2 + 1, 1.2, half * 2 + 1), ring * CF(8, 0.6, 0), Color3.fromRGB(30, 30, 34), M.SmoothPlastic, { collide = true })
		local canvas = part(f, "RingCanvas", V3(half * 2, 0.1, half * 2), ring * CF(8, 1.25, 0), Color3.fromRGB(226, 222, 212), M.Fabric, { collide = true })
		GymDecor.Sign(canvas, Enum.NormalId.Top, "HOME OF THE CHAMP", Color3.fromRGB(150, 20, 26), nil, 10)
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			part(f, "RingPost", V3(0.5, 4.4, 0.5), ring * CF(8 + c[1] * half, 3.4, c[2] * half), C.red, M.SmoothPlastic, { collide = true })
		end
		for _, y in ipairs({ 2.4, 3.4, 4.4 }) do
			for _, e in ipairs({ { 0, -half, half * 2, 0 }, { 0, half, half * 2, 0 }, { -half, 0, 0, half * 2 }, { half, 0, 0, half * 2 } }) do
				part(f, "RingRope", V3(math.max(0.2, e[3]), 0.2, math.max(0.2, e[4])), ring * CF(8 + e[1], y, e[2]), Color3.fromRGB(240, 240, 240), M.Fabric)
			end
		end
	end
end

local function recoverySuite(f, cf)
	part(f, "MassageTable", V3(2.6, 0.5, 6), cf * CF(-3, 2.4, 0), Color3.fromRGB(240, 240, 236), M.Leather, { collide = true })
	for _, z in ipairs({ -2.4, 2.4 }) do
		part(f, "TableLeg", V3(2.2, 2.2, 0.3), cf * CF(-3, 1.1, z), Color3.fromRGB(200, 200, 205), M.Metal)
	end
	vcyl(f, "ColdTub", 2.6, 4, cf * CF(2, 0, -1), Color3.fromRGB(200, 205, 212), M.Metal, { collide = true })
	vcyl(f, "ColdWater", 0.1, 3.6, cf * CF(2, 2.45, -1), Color3.fromRGB(120, 200, 240), M.Glass, { transparency = 0.2 })
	part(f, "Sauna", V3(5, 7.5, 4.5), cf * CF(2, 3.75, 4.5), Color3.fromRGB(176, 120, 70), M.WoodPlanks, { collide = true })
	part(f, "SaunaDoor", V3(1.8, 5.6, 0.1), cf * CF(2, 3.0, 2.2), Color3.fromRGB(200, 170, 120), M.Glass, { transparency = 0.4 })
end

-- TV with the boxer's career on it (static until the next visit home)
local function tvWall(f, cf, w, profile)
	part(f, "TVConsole", V3(w, 1.6, 1.8), cf * CF(0, 0.8, 0), Color3.fromRGB(40, 32, 26), M.Wood, { collide = true })
	local scr = part(f, "TVScreen", V3(w * 0.75, w * 0.42, 0.2), cf * CF(0, 2.2 + w * 0.21, 0.6), Color3.fromRGB(10, 10, 14), M.Glass)
	local sg = gui(scr, Enum.NormalId.Back, 30, 0, 120)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 16, 26) })
	frame(sg, { Size = UDim2.fromScale(1, 0.18), BackgroundColor3 = Color3.fromRGB(190, 20, 30) })
	label(sg, "WCB SPORTS  -  LIVE", { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.9, 0.14), Position = UDim2.fromScale(0.05, 0.02) })
	local id = type(profile.identity) == "table" and profile.identity or {}
	local r = profile.tier == 1 and profile.amateurRecord or profile.record
	r = type(r) == "table" and r or { w = 0, l = 0, d = 0, ko = 0 }
	label(sg, string.format("%s \"%s\"", tostring(id.name or ""), tostring(id.nickname or "")), { TextColor3 = C.gold, Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.24) })
	local tier = Config.Tiers[profile.tier]
	label(sg, string.format("%s  -  %d-%d-%d (%d KO)", tier and tier.name or "", r.w or 0, r.l or 0, r.d or 0, r.ko or 0), { TextColor3 = Color3.new(1, 1, 1), Face = "signSub", Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.46) })
	local nextLine = "NEXT FIGHT: TO BE ANNOUNCED"
	local camp = profile.camp
	if type(camp) == "table" and type(camp.offer) == "table" and type(camp.offer.opp) == "table" then
		nextLine = string.format("NEXT: vs %s  -  %d DAYS", tostring(camp.offer.opp.name or "?"):upper(), tonumber(camp.daysLeft) or 0)
	end
	label(sg, nextLine, { TextColor3 = Color3.fromRGB(150, 210, 255), Face = "signSub", Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.64) })
	label(sg, "FANS: " .. tostring(math.floor((profile.popularity or 0) ^ 2 * 950 + (r.w or 0) * 120)), { TextColor3 = Color3.fromRGB(200, 200, 210), Face = "signSub", Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.82) })
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = Color3.fromRGB(150, 180, 255), 10, 0.6, false
	glow.Parent = scr
end

local function outsideDeck(f, base, spec, pool)
	local w, d = spec.w, spec.d
	part(f, "Deck", V3(w, 1, 12), base * CF(0, -0.5, -d / 2 - 7), Color3.fromRGB(150, 116, 84), M.WoodPlanks, { collide = true })
	if pool then
		part(f, "PoolWater", V3(w * 0.55, 0.3, 6.5), base * CF(-w * 0.12, 0.02, -d / 2 - 7.5), Color3.fromRGB(60, 170, 220), M.Glass, { transparency = 0.15, reflect = 0.2 })
		part(f, "PoolEdge", V3(w * 0.55 + 1, 0.2, 7.5), base * CF(-w * 0.12, -0.05, -d / 2 - 7.5), Color3.fromRGB(230, 230, 226), M.Limestone)
		for k = 0, 1 do
			local lc = base * CF(w * 0.28 + k * 3.4, 0, -d / 2 - 7)
			part(f, "Lounger", V3(2, 0.5, 5.5), lc * CF(0, 1, 0), Color3.fromRGB(240, 240, 236), M.Fabric)
			part(f, "LoungerBack", V3(2, 0.5, 2.2), lc * CF(0, 1.8, 2.2) * ANG(RAD(50), 0, 0), Color3.fromRGB(240, 240, 236), M.Fabric)
		end
	end
	for _, x in ipairs({ -w / 2 + 2, w / 2 - 2 }) do
		GymDecor.Plant(f, (base * CF(x, 0, -d / 2 - 3)).Position, 1.1)
	end
end

local function furnish(f, base, spec, kind, profile)
	local w, d, h = spec.w, spec.d, spec.h
	local owned = type(profile.owned) == "table" and profile.owned or {}
	local id = type(profile.identity) == "table" and profile.identity or {}
	local surname = tostring(id.last or id.name or "CHAMP")
	local hist = type(profile.history) == "table" and profile.history or {}
	local belts = beltList(profile)
	local bedCF = base * CF(w / 2 - (kind == "Mansion" and 14 or 9), 0, d / 2 - 5.6)
	local bw = kind == "Mansion" and 9 or 7
	bed(f, bedCF, bw, 10, spec.sheet)
	promptPart(f, "SleepPrompt", (bedCF * CF(-bw / 2 - 2.5, 2.6, -2)).Position, "Sleep (End Day)", "Home sweet home", { Action = "Sleep" }, Color3.fromRGB(170, 170, 255))
	local lounge = base * CF(-w * 0.12, 0, -d * 0.12)
	part(f, "Rug", V3(14, 0.06, 10), lounge * CF(0, 0.03, 0), kind == "Mansion" and Color3.fromRGB(150, 120, 80) or Color3.fromRGB(120, 60, 50), M.Fabric)
	sofa(f, lounge * CF(0, 0, 4), kind == "Apartment" and 9 or 12, spec.sofa)
	part(f, "CoffeeTable", V3(5, 1.4, 2.6), lounge * CF(0, 0.7, 0.4), Color3.fromRGB(46, 36, 28), M.Wood, { collide = true })
	tvWall(f, lounge * CF(0, 0, -4.2), kind == "Mansion" and 12 or 9, profile)
	local kLen = kind == "Apartment" and 10 or 14
	kitchen(f, base * CF(-w / 2 + kLen / 2 + 4.5, 0, d / 2 - 1.6) * ANG(0, RAD(180), 0), kLen,
		kind == "Mansion" and Color3.fromRGB(30, 30, 34) or Color3.fromRGB(236, 236, 232), kind == "Mansion" and Color3.fromRGB(240, 240, 236) or Color3.fromRGB(60, 60, 64))
	for _, p in ipairs({ { -w / 2 + 2.5, -d / 2 + 2.5 }, { w / 2 - 2.5, -d / 2 + 2.5 } }) do
		GymDecor.Plant(f, (base * CF(p[1], 0, p[2])).Position, 1)
	end
	local doorCF = base * CF(-w / 2 + 0.05, 0, d / 2 - 12) * ANG(0, RAD(90), 0)
	part(f, "FrontDoor", V3(4, 8, 0.2), doorCF * CF(0, 4, 0), Color3.fromRGB(60, 40, 28), M.Wood)
	part(f, "DoorHandle", V3(0.2, 0.2, 0.5), doorCF * CF(1.4, 3.8, 0.2), C.gold, M.Metal)
	promptPart(f, "ExitPrompt", (doorCF * CF(0, 2.6, 2.5)).Position, "Go outside", kind, { Action = "LeaveHome" }, Color3.fromRGB(255, 230, 170))
	local nPosters = kind == "Apartment" and 2 or (kind == "House" and 3 or 4)
	local posterY = kind == "Mansion" and 5 or h * 0.45
	for k = 0, nPosters - 1 do
		local e = hist[#hist - k]
		if type(e) == "table" then
			fightPoster(f, base * CF(-2 - (nPosters - 1) * 2.2 + k * 4.4, posterY, d / 2 - 0.1), e, surname)
		end
	end
	if #belts > 0 and not owned.TrophyRoom then
		local shelf = base * CF(w / 2 - 0.4, h * 0.42, -d * 0.1) * ANG(0, RAD(90), 0)
		part(f, "BeltShelf", V3(#belts * 4 + 1, 0.3, 1.4), shelf * CF(0, -0.6, -0.3), Color3.fromRGB(40, 30, 24), M.Wood)
		for i, b in ipairs(belts) do
			belt(f, shelf * CF(-(#belts - 1) * 2 + (i - 1) * 4, 0.3, -0.4), b)
		end
		spot(emitter(f, shelf * CF(0, 3, -2)), Enum.NormalId.Bottom, Color3.fromRGB(255, 230, 180), 10, 1.2, 70)
	end
	if owned.HomeGym then
		if kind == "Mansion" then
			homeGym(f, base * CF(w / 2 - 20, 0, -d / 2 + 9), true)
		else
			homeGym(f, base * CF(w / 2 - 9, 0, -d / 2 + 7), false)
		end
	end
	if owned.RecoverySuite and kind ~= "Apartment" then
		recoverySuite(f, base * CF(-w / 2 + 6, 0, -d / 2 + 6))
	end
	if owned.TrophyRoom and kind ~= "Apartment" then
		local tr = base * CF(-w * 0.32, 0, 2)
		part(f, "TrophyCabinet", V3(14, 9, 2), tr * CF(0, 4.5, 0), Color3.fromRGB(40, 30, 24), M.Wood, { collide = true })
		part(f, "CabinetGlass", V3(13, 7.6, 0.1), tr * CF(0, 4.8, -1.05), Color3.fromRGB(210, 230, 245), M.Glass, { transparency = 0.7 })
		for i, b in ipairs(belts) do
			belt(f, tr * CF(-5 + ((i - 1) % 3) * 5, 6.8 - math.floor((i - 1) / 3) * 2.6, -0.6), b)
		end
		for k = 0, math.min(4, math.max(1, tonumber(profile.titlesWon) or 0)) - 1 do
			trophy(f, tr * CF(-5 + k * 2.6, 1.2, -0.4), 2.2, C.gold)
		end
		local plaque = part(f, "LegacyPlaque", V3(6, 1.2, 0.1), tr * CF(0, 9.8, -1.05), C.gold, M.Metal)
		GymDecor.Sign(plaque, Enum.NormalId.Front, string.format("%s - %d TITLE%s", surname:upper(), tonumber(profile.titlesWon) or 0, (tonumber(profile.titlesWon) or 0) == 1 and "" or "S"), Color3.fromRGB(40, 28, 10), C.gold, 40)
		spot(emitter(f, tr * CF(0, h - 1.5, -4)), Enum.NormalId.Bottom, Color3.fromRGB(255, 228, 180), 16, 1.4, 70)
	end
	outsideDeck(f, base, spec, owned.PoolDeck == true and kind ~= "Apartment")
	if kind == "Mansion" then
		local ch = base * CF(0, h - 3.5, 0)
		ball(f, "ChandelierCore", 1.4, ch, Color3.fromRGB(255, 236, 190), M.Neon, { shadow = false })
		for k = 0, 9 do
			local a = k * math.pi / 5
			ball(f, "ChandelierCrystal", 0.6, ch * CF(math.cos(a) * 2.6, -0.6 - (k % 2) * 0.5, math.sin(a) * 2.6), Color3.fromRGB(240, 246, 255), M.Glass, { transparency = 0.2, reflect = 0.3 })
		end
		point(emitter(f, ch * CF(0, -1, 0)), Color3.fromRGB(255, 228, 190), 34, 1.2)
		for _, sx in ipairs({ -1, 1 }) do
			local stairX = sx < 0 and -(w / 2 - 12) or (w / 2 - 4)
			for k = 0, 10 do
				part(f, "Stair", V3(5, 0.8, 1.6), base * CF(stairX, 0.4 + k * 0.95, d / 2 - 26 + k * 1.6), Color3.fromRGB(236, 232, 224), M.Marble, { collide = true })
			end
		end
		part(f, "Mezzanine", V3(w, 0.8, 10), base * CF(0, 10, d / 2 - 5), Color3.fromRGB(236, 232, 224), M.Marble, { collide = true })
		part(f, "MezzanineRail", V3(w - 16, 1.6, 0.2), base * CF(0, 11.2, d / 2 - 10), Color3.fromRGB(200, 225, 240), M.Glass, { transparency = 0.5 })
		local cin = base * CF(w * 0.3, 0, d * 0.05)
		local scr = part(f, "CinemaScreen", V3(14, 7, 0.2), cin * CF(0, 7, -9), Color3.fromRGB(10, 10, 12), M.SmoothPlastic)
		local best = hist[#hist]
		GymDecor.PosterGui(scr, Enum.NormalId.Back, {
			bg = Color3.fromRGB(10, 10, 14), accent = C.gold, top = "NOW SHOWING", title = best and string.format("%s\nvs\n%s", surname:upper(), (tostring(best.opp):match("(%S+)$") or "?"):upper()) or "THE COMEBACK",
			sub = best and string.format("%s - %s", tostring(best.outcome or ""):upper(), tostring(best.method or "")) or "COMING SOON", foot = "THE " .. surname:upper() .. " STORY",
		})
		for row = 0, 1 do
			for k = -1, 1 do
				local sc = cin * CF(k * 3.4, row * 0.6, -1 + row * 4)
				part(f, "Recliner", V3(2.8, 1.6, 2.8), sc * CF(0, 0.8, 0), Color3.fromRGB(30, 30, 34), M.Leather, { collide = true })
				part(f, "ReclinerBack", V3(2.8, 2.4, 0.8), sc * CF(0, 2, 1.3), Color3.fromRGB(30, 30, 34), M.Leather)
			end
		end
	elseif kind == "House" then
		local fp = base * CF(-w / 2 + 0.9, 0, -d * 0.12) * ANG(0, RAD(-90), 0)
		part(f, "Fireplace", V3(7, 6, 1.6), fp * CF(0, 3, 0), Color3.fromRGB(150, 140, 130), M.Cobblestone, { collide = true })
		part(f, "Firebox", V3(3.6, 2.6, 0.4), fp * CF(0, 1.6, -0.7), Color3.fromRGB(20, 18, 16), M.SmoothPlastic)
		local fire = part(f, "Hearth", V3(2.4, 0.4, 0.4), fp * CF(0, 0.7, -0.9), Color3.fromRGB(255, 120, 40), M.Neon, { shadow = false })
		point(fire, Color3.fromRGB(255, 150, 70), 14, 1)
		part(f, "Mantel", V3(8, 0.4, 2), fp * CF(0, 6.2, -0.2), Color3.fromRGB(80, 56, 38), M.Wood)
		part(f, "DiningTable", V3(7, 0.3, 3.6), base * CF(-12, 3, 9), Color3.fromRGB(110, 76, 48), M.Wood, { collide = true })
		for _, x in ipairs({ -2.4, 0, 2.4 }) do
			for _, z in ipairs({ -2.4, 2.4 }) do
				part(f, "DiningChair", V3(1.6, 2.6, 1.6), base * CF(-12 + x, 1.3, 9 + z), Color3.fromRGB(80, 56, 38), M.Wood, { collide = true })
			end
		end
	end
	local first = hist[1]
	if type(first) == "table" then
		fightPoster(f, base * CF(-w / 2 + 0.1, h * 0.45, -d * 0.3) * ANG(0, RAD(-90), 0), first, surname)
	end
end

local function homeSig(profile, kind)
	local owned = type(profile.owned) == "table" and profile.owned or {}
	local hist = type(profile.history) == "table" and profile.history or {}
	local r = type(profile.record) == "table" and profile.record or {}
	local camp = type(profile.camp) == "table" and type(profile.camp.offer) == "table" and profile.camp.offer.oppId or ""
	local addons = {}
	for _, id in ipairs({ "HomeGym", "TrophyRoom", "RecoverySuite", "PoolDeck", "Garage" }) do
		table.insert(addons, owned[id] and "1" or "0")
	end
	return table.concat({ kind, table.concat(addons), table.concat(beltList(profile), ","), tostring(profile.titlesWon), tostring(#hist),
		tostring(r.w) .. "-" .. tostring(r.l), tostring(camp), tostring(profile.tier), tostring(math.floor((profile.popularity or 0) / 5)) }, "|")
end

local function releaseHome(player)
	local h = homes[player]
	homes[player] = nil
	if h then
		if h.model then
			h.model:Destroy()
		end
		homeSlots[h.slot] = nil
	end
end
CityHomes.Release = releaseHome
Players.PlayerRemoving:Connect(releaseHome)

-- builds (or reuses) the player's interior and returns the spawn CFrame inside the front door
function CityHomes.Enter(player, profile, kind)
	kind = homeKindFor(profile, kind)
	if not kind then
		return nil, "You don't own a home yet. Buy one in the Shop (Houses)."
	end
	if not homesFolder then
		return nil, "The city isn't ready."
	end
	local h = homes[player]
	local sig = homeSig(profile, kind)
	local live = h and h.model and h.model.Parent
	if live and h.sig == sig then
		return h.spawn, kind
	end
	local now = os.clock()
	local tokens = REBUILD_BURST
	if h and h.tokens then
		tokens = math.min(REBUILD_BURST, h.tokens + (now - (h.tokAt or now)) / REBUILD_GAP)
	end
	if live and tokens < 1 then
		h.tokens, h.tokAt = tokens, now
		if h.kind == kind then
			return h.spawn, kind
		end
		return nil, "Hold on - you just moved. Try again in a moment."
	end
	tokens = math.max(0, tokens - 1)
	local slot = h and h.slot
	if not slot then
		slot = 1
		while homeSlots[slot] do
			slot += 1
		end
		homeSlots[slot] = player
	end
	if h and h.model then
		h.model:Destroy()
	end
	local spec = HOME_SPEC[kind]
	local base = CF(-3000 - (slot - 1) * 400, 40, -3000)
	local m = Instance.new("Model")
	m.Name = "Home_" .. tostring(player.UserId)
	m:SetAttribute("Owner", player.UserId)
	m:SetAttribute("Kind", kind)
	homeShell(m, base, spec)
	local ok, err = pcall(furnish, m, base, spec, kind, profile)
	if not ok then
		warn("[CityHomes] furnishing failed: " .. tostring(err))
	end
	m.Parent = homesFolder
	local spawnCF = CFrame.lookAt((base * CF(-spec.w / 2 + 4, 3.2, spec.d / 2 - 12)).Position, (base * CF(0, 3.2, 0)).Position)
	homes[player] = { model = m, kind = kind, sig = sig, spawn = spawnCF, slot = slot, tokens = tokens, tokAt = now }
	return spawnCF, kind
end

-- the kind of the home the player is in (nil when not at home)
function CityHomes.Current(player)
	local h = homes[player]
	return h and h.kind or nil
end

return CityHomes
