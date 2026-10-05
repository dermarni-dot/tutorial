-- CityMap: the neighbourhood around the gym, so the world outside feels like a real town.
-- Inside the roadwork loop: member parking, Champions Plaza with the golden glove monument,
-- an outdoor training yard, a bus stop and crosswalk. Outside the loop: Champion Ave runs
-- south to Main Street and its row of shops (diner, supplements, pro shop, cafe, laundromat,
-- tattoo, bakery, arena ticket office, corner store, pizza, apartments, boxing museum, gas
-- station, motel); Oak Street's houses to the west; Riverside Park with a basketball court and
-- fountain to the east; the WCB Arena to the north and a city skyline around the edges.
-- Street lights and shop lights are tagged "NightLight"/"NightLens" and switched on at dusk by
-- the client (Ambience). Neon signs are tagged "NeonFlicker".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GymDecor = require(script.Parent:WaitForChild("GymDecor"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local CityProps = require(Shared:WaitForChild("CityProps"))

local CityMap = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material

local part = GymDecor.Part
local cyl = GymDecor.Cyl
local vcyl = GymDecor.VCyl
local ball = GymDecor.Ball
local blob = GymDecor.Blob
local label = GymDecor.Label
local frame = GymDecor.Frame
local spot = GymDecor.Spot
local point = GymDecor.Point
local emitter = GymDecor.Emitter
local tag = GymDecor.Tag
local C = GymDecor.Colors

local ASPHALT = Color3.fromRGB(58, 58, 62)
local SIDEWALK = Color3.fromRGB(170, 168, 162)
local LINE_YELLOW = Color3.fromRGB(240, 210, 90)
local POLE = Color3.fromRGB(46, 48, 54)
local LENS_DAY = Color3.fromRGB(200, 200, 196)
local SW_H = 0.5 -- sidewalk top height (roads are 0.3)

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

local function gui(p, face, ppu, light, maxDist)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 20
	sg.LightInfluence = light or 0
	sg.MaxDistance = maxDist or 600
	sg.Parent = p
	return sg
end

-- flat slab lying on the ground (roads, sidewalks, paving): x1..x2, z1..z2, top height
local function slab(parent, name, x1, x2, z1, z2, top, color, material, collide)
	return part(parent, name, V3(x2 - x1, top, z2 - z1), CF((x1 + x2) / 2, top / 2, (z1 + z2) / 2), color, material, { collide = collide ~= false })
end

-- zebra crossing: bars run along the traffic direction and are stacked across the road
local function crosswalk(parent, center, alongX, roadWidth, bandWidth)
	local n = math.floor(roadWidth / 2.2)
	for i = 0, n - 1 do
		local o = -roadWidth / 2 + 1.1 + i * (roadWidth - 2.2) / math.max(1, n - 1)
		if alongX then
			part(parent, "Crosswalk", V3(bandWidth, 0.04, 1.0), CF(center + V3(0, 0, o)), C.white, M.SmoothPlastic)
		else
			part(parent, "Crosswalk", V3(1.0, 0.04, bandWidth), CF(center + V3(o, 0, 0)), C.white, M.SmoothPlastic)
		end
	end
end

-- glowing neon outline around a rectangle (cf faces the viewer with its -Z)
local function neonOutline(parent, cf, w, h, color)
	local m = model(parent, "NeonOutline")
	local t = 0.22
	for _, e in ipairs({ { 0, h / 2, w + t, t }, { 0, -h / 2, w + t, t }, { -w / 2, 0, t, h }, { w / 2, 0, t, h } }) do
		part(m, "NeonTube", V3(e[3], e[4], t), cf * CF(e[1], e[2], 0), color, M.Neon, { shadow = false })
	end
	tag(m, "NeonFlicker")
	return m
end

-- Invisible anchors the client (CityVisuals) and the server travel code find by name:
-- City/Sites/Site_<name> with attribute Site = name. Player-specific success visuals (homes,
-- cars, fans, stars, statue) are built client-side at these spots, so every player sees their own.
local sitesFolder
CityMap.Sites = {} -- name -> CFrame (server side travel targets)
local function site(name, cf, attrs)
	local p = part(sitesFolder, "Site_" .. name, V3(1, 1, 1), cf, Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	p:SetAttribute("Site", name)
	for k, v in pairs(attrs or {}) do
		p:SetAttribute(k, v)
	end
	CityMap.Sites[name] = cf
	return p
end

-- invisible boxes tagged LightZone: the client grades the picture for the zone the camera is in
-- (Profile: GymWarm / Barbershop / Apartment / Store / Mansion / Street; Ambience picks the smallest box)
local function lightZone(parent, name, size, cf, profile)
	local p = part(parent, name, size, cf, Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	p.CanQuery = false
	p:SetAttribute("Profile", profile)
	tag(p, "LightZone")
	return p
end

-- a prompt on an invisible part with a floating label (same contract as MapBuilder's buildAction:
-- attribute Action on the ProximityPrompt, dispatched by the client)
local function promptPart(parent, name, pos, actionText, objectText, attrs, labelColor)
	local p = part(parent, name, V3(1, 1, 1), CF(pos), Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText
	pp.ObjectText = objectText or ""
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	for k, v in pairs(attrs or {}) do
		pp:SetAttribute(k, v)
	end
	pp.Parent = p
	local bb = Instance.new("BillboardGui")
	bb.Name = "PromptLabel"
	bb.Size = UDim2.fromOffset(220, 40)
	bb.StudsOffset = V3(0, 2.6, 0)
	bb.MaxDistance = 45
	bb.Adornee = p
	label(bb, actionText, { TextColor3 = labelColor or Color3.fromRGB(120, 220, 255), TextStrokeTransparency = 0.3 })
	bb.Parent = p
	return p, pp
end

-- a light that is always on (interiors are under a roof: Future lighting leaves them dark by day)
local function roomLight(parent, cf, color, range, brightness)
	return point(emitter(parent, cf), color or Color3.fromRGB(255, 236, 210), range or 18, brightness or 1.1)
end

-- a light that comes on at dusk (Ambience switches every NightLight)
local function nightPoint(parent, cf, color, range, brightness)
	local l = point(emitter(parent, cf), color or Color3.fromRGB(255, 214, 160), range or 14, brightness or 1)
	l.Enabled = false
	tag(l, "NightLight")
	return l
end

-- Billboard on two steel legs with a catwalk and flood lights; the face is a part named
-- BillboardFace with a generic ad. Tagged CityBillboard (attribute Slot): CityVisuals swaps the ad
-- for the player's sponsor / fight promo locally.
local function billboard(parent, cf, w, h, slot, ad, legH)
	local m = model(parent, "Billboard")
	-- legs reach the ground unless a length is given (rooftop boards stand on the roof)
	legH = legH or (cf.Position.Y - h / 2)
	for _, x in ipairs({ -w * 0.3, w * 0.3 }) do
		if legH > 0.5 then
			part(m, "BillboardLeg", V3(0.7, legH + h / 2, 0.7), cf * CF(x, -(legH + h / 2) / 2, 0.8), POLE, M.Metal, { collide = true })
		end
		part(m, "BillboardBrace", V3(0.25, h * 0.9, 0.25), cf * CF(x, 0, 0.75), POLE, M.Metal)
	end
	part(m, "BillboardFrame", V3(w + 0.8, h + 0.8, 0.6), cf * CF(0, 0, 0.35), Color3.fromRGB(30, 32, 36), M.Metal)
	local face = part(m, "BillboardFace", V3(w, h, 0.2), cf * CF(0, 0, -0.05), Color3.fromRGB(240, 240, 240), M.SmoothPlastic)
	part(m, "Catwalk", V3(w, 0.2, 1.4), cf * CF(0, -h / 2 - 0.6, -0.5), C.steel, M.DiamondPlate)
	for _, x in ipairs({ -w * 0.3, w * 0.3 }) do
		local arm = part(m, "FloodArm", V3(0.2, 0.2, 2.4), cf * CF(x, -h / 2 - 0.5, -1.6), POLE, M.Metal)
		local l = spot(emitter(m, arm.CFrame * CF(0, 0, -1.1)), Enum.NormalId.Top, Color3.fromRGB(255, 244, 220), 18, 1.4, 70)
		l.Enabled = false
		tag(l, "NightLight")
	end
	local sg = gui(face, Enum.NormalId.Front, 10, 0.2, 900)
	sg.Name = "Ad"
	frame(sg, { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = ad.bg })
	label(sg, ad.title, { Name = "Title", TextColor3 = ad.fg, Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.08) })
	label(sg, ad.sub, { Name = "Sub", TextColor3 = ad.fg, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.26), Position = UDim2.fromScale(0.05, 0.64) })
	face:SetAttribute("Slot", slot)
	tag(face, "CityBillboard")
	return m, face
end

-- generic city ads (what everyone sees until CityVisuals puts your sponsor up)
local ADS = {
	{ title = "TONY'S PIZZA", sub = "SLICE OF CHAMPIONS - MAIN ST", bg = Color3.fromRGB(200, 30, 30), fg = Color3.fromRGB(255, 240, 200) },
	{ title = "IRON SUPPLEMENTS", sub = "BUILT IN THE GYM. FUELED BY IRON.", bg = Color3.fromRGB(26, 26, 28), fg = Color3.fromRGB(240, 110, 20) },
	{ title = "FIGHT NIGHT LIVE", sub = "WCB ARENA - TICKETS ON MAIN ST", bg = Color3.fromRGB(150, 16, 24), fg = Color3.fromRGB(255, 220, 90) },
	{ title = "APEX ATHLETICS", sub = "OUTWORK EVERYONE", bg = Color3.fromRGB(20, 20, 20), fg = Color3.fromRGB(0, 170, 190) },
	{ title = "PRESTIGE MOTORS", sub = "DRIVE LIKE A CHAMPION", bg = Color3.fromRGB(16, 18, 24), fg = Color3.fromRGB(220, 220, 230) },
}

------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------
-- street light standing at base; dir = horizontal unit vector from the pole out over the road
local function streetLight(parent, base, dir, withLight)
	local up = 15
	local m = model(parent, "StreetLight")
	part(m, "LightBase", V3(1.2, 0.6, 1.2), CF(base + V3(0, 0.3, 0)), C.steel, M.Concrete, { collide = true })
	part(m, "LightPole", V3(0.45, up, 0.45), CF(base + V3(0, up / 2, 0)), POLE, M.Metal, { collide = true })
	local a = base + V3(0, up - 0.3, 0)
	local armEnd = a + dir * 4.2
	part(m, "LightArm", V3(0.3, 0.3, 4.4), CFrame.lookAt((a + armEnd) / 2, armEnd), POLE, M.Metal)
	local head = part(m, "LightHead", V3(1.1, 0.45, 2.2), CFrame.lookAt(armEnd, armEnd + dir), POLE, M.Metal)
	local lens = part(m, "LightLens", V3(0.8, 0.08, 1.8), head.CFrame * CF(0, -0.26, 0), LENS_DAY, M.SmoothPlastic, { shadow = false })
	tag(lens, "NightLens")
	if withLight then
		local l = spot(emitter(m, head.CFrame * CF(0, -0.8, 0)), Enum.NormalId.Bottom, Color3.fromRGB(255, 220, 170), 44, 1.7, 120)
		l.Enabled = false
		tag(l, "NightLight")
	end
	return m
end

-- simple car; cf = ground centre, front towards local -Z
local CAR_COLORS = {
	Color3.fromRGB(190, 30, 36), Color3.fromRGB(235, 235, 238), Color3.fromRGB(28, 28, 32), Color3.fromRGB(40, 80, 170),
	Color3.fromRGB(150, 152, 158), Color3.fromRGB(30, 110, 70), Color3.fromRGB(230, 170, 40),
}
local function car(parent, cf, color)
	local m = model(parent, "Car")
	part(m, "CarBody", V3(5.2, 1.5, 10.6), cf * CF(0, 1.55, 0), color, M.SmoothPlastic, { collide = true })
	part(m, "CarCabin", V3(4.6, 1.6, 5.2), cf * CF(0, 3.05, 0.6), Color3.fromRGB(40, 54, 70), M.Glass, { reflect = 0.15 })
	part(m, "CarRoof", V3(4.8, 0.25, 4.6), cf * CF(0, 3.95, 0.7), color, M.SmoothPlastic)
	for _, x in ipairs({ -2.35, 2.35 }) do
		for _, z in ipairs({ -3.4, 3.5 }) do
			cyl(m, "Wheel", 0.9, 2.1, cf * CF(x, 1.05, z), Color3.fromRGB(20, 20, 22), M.Rubber)
			cyl(m, "Hubcap", 0.95, 1.0, cf * CF(x, 1.05, z), Color3.fromRGB(190, 192, 198), M.Metal)
		end
	end
	for _, x in ipairs({ -1.8, 1.8 }) do
		part(m, "Headlight", V3(0.9, 0.45, 0.1), cf * CF(x, 1.9, -5.32), Color3.fromRGB(255, 250, 230), M.Neon, { shadow = false })
		part(m, "Taillight", V3(0.9, 0.4, 0.1), cf * CF(x, 1.9, 5.32), Color3.fromRGB(220, 30, 30), M.Neon, { shadow = false })
	end
	part(m, "BumperF", V3(5.4, 0.5, 0.4), cf * CF(0, 1.0, -5.35), C.black, M.SmoothPlastic)
	part(m, "BumperB", V3(5.4, 0.5, 0.4), cf * CF(0, 1.0, 5.35), C.black, M.SmoothPlastic)
	part(m, "Plate", V3(1.4, 0.45, 0.06), cf * CF(0, 1.4, 5.58), C.white, M.SmoothPlastic)
	return m
end

-- tiered pine and round deciduous tree
local function pine(parent, pos, h)
	vcyl(parent, "PineTrunk", h * 0.3, 0.9, CF(pos), Color3.fromRGB(90, 62, 40), M.Wood, { collide = true })
	for i = 0, 3 do
		local t = i / 3
		vcyl(parent, "PineTier", h * 0.22, h * (0.55 - t * 0.35), CF(pos + V3(0, h * (0.22 + t * 0.6), 0)), Color3.fromRGB(34, 88 + i * 8, 48), M.Grass)
	end
	ball(parent, "PineTop", h * 0.12, CF(pos + V3(0, h * 1.02, 0)), Color3.fromRGB(40, 104, 56), M.Grass)
end

local function roundTree(parent, pos, h, rng)
	vcyl(parent, "TreeTrunk", h * 0.55, 1.2, CF(pos), Color3.fromRGB(96, 66, 42), M.Wood, { collide = true })
	blob(parent, "Canopy", V3(h * 0.8, h * 0.65, h * 0.8), CF(pos + V3(0, h * 0.75, 0)), Color3.fromRGB(50 + rng:NextInteger(0, 25), 112 + rng:NextInteger(0, 30), 52), M.Grass)
	blob(parent, "Canopy", V3(h * 0.55, h * 0.5, h * 0.55), CF(pos + V3(h * 0.18, h * 0.95, h * 0.1)), Color3.fromRGB(62, 128, 60), M.Grass)
end

-- window grid on one face (some windows lit); rows/cols fill the band y0..y1 of a face faceH tall
local function windowGrid(p, face, faceH, y0, y1, rows, cols, rng, litChance)
	local sg = gui(p, face, 4, 0.15, 1200)
	local top = 1 - y1 / faceH
	local spanH = (y1 - y0) / faceH
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local lit = rng:NextNumber() < (litChance or 0.35)
			frame(sg, {
				Size = UDim2.fromScale(0.62 / cols, spanH / rows * 0.6),
				Position = UDim2.fromScale((c + 0.19) / cols, top + (r + 0.2) / rows * spanH),
				BackgroundColor3 = lit and Color3.fromRGB(255, 214 + rng:NextInteger(0, 30), 140 + rng:NextInteger(0, 40)) or Color3.fromRGB(34, 44, 58),
			})
		end
	end
	return sg
end

-- picnic table (top along local X)
local function picnicTable(parent, pos, yaw)
	local base = CF(pos) * ANG(0, yaw or 0, 0)
	part(parent, "PicnicTop", V3(6, 0.3, 2.6), base * CF(0, 2.6, 0), C.wood, M.WoodPlanks, { collide = true })
	for _, z in ipairs({ -2.1, 2.1 }) do
		part(parent, "PicnicSeat", V3(6, 0.25, 1.0), base * CF(0, 1.5, z), C.wood, M.WoodPlanks, { collide = true })
	end
	for _, x in ipairs({ -2.3, 2.3 }) do
		part(parent, "PicnicLeg", V3(0.3, 2.6, 4.6), base * CF(x, 1.3, 0), C.woodDark, M.Wood)
	end
end

------------------------------------------------------------------------
-- Inside the loop: crosswalk, bus stop, parking lot, plaza, outdoor yard; lights along the loop
------------------------------------------------------------------------
local function buildCampus(root)
	local f = folder(root, "Campus")
	local rng = Random.new(42)
	-- zebra crossing where the entrance path meets the loop road (road runs along X, z 115..125)
	crosswalk(f, V3(0, 0.32, 120), true, 10, 8.8)
	-- bus stop on the far side of the loop road, facing it
	local bs = CF(-40, 0.3, 130)
	part(f, "BusPad", V3(10, 0.3, 4.6), bs, SIDEWALK, M.Concrete, { collide = true })
	part(f, "BusRoof", V3(9, 0.35, 3.8), bs * CF(0, 8.3, 0.2), Color3.fromRGB(40, 44, 52), M.Metal)
	part(f, "BusBack", V3(8.6, 6.6, 0.15), bs * CF(0, 4.5, 1.9), Color3.fromRGB(180, 210, 230), M.Glass, { transparency = 0.5, shadow = false })
	part(f, "BusSide", V3(0.15, 6.6, 3.2), bs * CF(-4.3, 4.5, 0.4), Color3.fromRGB(180, 210, 230), M.Glass, { transparency = 0.5, shadow = false })
	for _, x in ipairs({ -4.4, 4.4 }) do
		part(f, "BusPost", V3(0.25, 8.2, 0.25), bs * CF(x, 4.2, 1.9), Color3.fromRGB(40, 44, 52), M.Metal, { collide = true })
	end
	GymDecor.Bench(f, (bs * CF(-1.2, 0.15, 1.0)).Position, 0, 5, C.wood)
	local ad = part(f, "BusAd", V3(3.2, 4.6, 0.2), bs * CF(2.4, 4.6, 1.72), C.black, M.SmoothPlastic)
	GymDecor.PosterGui(ad, Enum.NormalId.Front, GymDecor.Posters[3])
	-- CityVisuals swaps the poster for the player's fight promo / sponsor locally
	ad:SetAttribute("Kind", "BusAd")
	tag(ad, "CityScreen")
	part(f, "BusSignPole", V3(0.25, 9, 0.25), bs * CF(5.6, 4.5, -1.6), C.steel, M.Metal, { collide = true })
	local bsign = part(f, "BusSign", V3(1.8, 1.4, 0.15), bs * CF(5.6, 8.4, -1.6), Color3.fromRGB(30, 90, 190), M.SmoothPlastic)
	GymDecor.Sign(bsign, Enum.NormalId.Front, "BUS 12", Color3.new(1, 1, 1), Color3.fromRGB(30, 90, 190), 40)
	GymDecor.Sign(bsign, Enum.NormalId.Back, "BUS 12", Color3.new(1, 1, 1), Color3.fromRGB(30, 90, 190), 40)

	-- member parking east of the entrance path (between the gym sidewalk curb and the loop road)
	local LZ1, LZ2 = 89.6, 112
	slab(f, "ParkingLot", 20, 90, LZ1, LZ2, 0.2, ASPHALT, M.Asphalt)
	slab(f, "ParkingEntry", 80, 90, LZ2, 115, 0.2, ASPHALT, M.Asphalt)
	for x = 22, 86, 8 do
		part(f, "BayLine", V3(0.3, 0.03, 10), CF(x, 0.215, 96.6), C.white, M.SmoothPlastic)
	end
	part(f, "BayHead", V3(64.3, 0.03, 0.3), CF(54, 0.215, 91.7), C.white, M.SmoothPlastic)
	for i, x in ipairs({ 26, 42, 50, 66, 82 }) do
		car(f, CF(x, 0.2, 97.6) * ANG(0, RAD(rng:NextNumber(-3, 3)), 0), CAR_COLORS[(i - 1) % #CAR_COLORS + 1])
	end
	-- bay 58 stays empty for the player's own car (CityVisuals parks your best car here)
	part(f, "ReservedPost", V3(0.25, 3.4, 0.25), CF(58, 1.9, 91.2), C.steel, M.Metal, { collide = true })
	local rs = part(f, "ReservedSign", V3(2.2, 1.3, 0.12), CF(58, 3.9, 91.2), C.white, M.SmoothPlastic)
	rs:SetAttribute("Kind", "Reserved")
	tag(rs, "CityScreen")
	GymDecor.Sign(rs, Enum.NormalId.Back, "RESERVED\nMEMBER OF THE MONTH", Color3.fromRGB(30, 60, 160), C.white, 40)
	site("CarBay", CF(58, 0.2, 97.6))
	-- fans gather along the entrance path (count grows with popularity; CityVisuals)
	site("FanGymW", CFrame.lookAt(V3(-13, 0.2, 100), V3(0, 0.2, 100)), { Len = 14, Rows = 2 })
	site("FanGymE", CFrame.lookAt(V3(13, 0.2, 100), V3(0, 0.2, 100)), { Len = 14, Rows = 2 })
	for _, x in ipairs({ 36, 74 }) do
		streetLight(f, V3(x, 0.2, 109.6), V3(0, 0, -1), true)
	end
	local lotSign = part(f, "LotSign", V3(5, 2, 0.2), CF(24, 4.2, 110.6), Color3.fromRGB(30, 60, 160), M.SmoothPlastic)
	part(f, "LotSignPole", V3(0.25, 3.3, 0.25), CF(24, 1.65, 110.6), C.steel, M.Metal)
	GymDecor.Sign(lotSign, Enum.NormalId.Back, "P  MEMBER PARKING", Color3.new(1, 1, 1), Color3.fromRGB(30, 60, 160), 40)

	-- Champions Plaza west of the entrance path: paving, golden glove monument, benches, trees, flags
	slab(f, "PlazaBorder", -88.3, -21.7, LZ1, LZ2, 0.2, Color3.fromRGB(120, 110, 100), M.Concrete)
	slab(f, "PlazaPaving", -88, -22, LZ1 + 0.3, LZ2 - 0.3, 0.22, Color3.fromRGB(196, 186, 170), M.Pavement)
	local mon = V3(-55, 0.22, 101)
	part(f, "MonumentBase", V3(8, 1.2, 8), CF(mon + V3(0, 0.6, 0)), Color3.fromRGB(80, 80, 86), M.Granite, { collide = true })
	part(f, "MonumentPlinth", V3(5, 4.4, 5), CF(mon + V3(0, 3.4, 0)), Color3.fromRGB(60, 60, 66), M.Granite, { collide = true })
	local plaque = part(f, "MonumentPlaque", V3(3.6, 1.6, 0.1), CF(mon + V3(0, 3.2, 2.55)), C.gold, M.Metal)
	GymDecor.Sign(plaque, Enum.NormalId.Back, "CHAMPIONS WALK\nEvery champion started here", Color3.fromRGB(40, 30, 10), C.gold, 40)
	plaque:SetAttribute("Kind", "Plaque")
	tag(plaque, "CityScreen")
	-- the player's statue rises here at undisputed / legend status, fans gather round the monument
	site("Statue", CFrame.lookAt(V3(-43, 0.22, 101), V3(-43, 0.22, 130)))
	site("FanPlaza", CFrame.lookAt(V3(-55, 0.22, 107.4), V3(-55, 0.22, 101)), { Len = 16, Rows = 1 })
	local gloveCF = CF(mon + V3(0, 8.4, 0)) * ANG(RAD(-12), RAD(25), 0)
	blob(f, "GoldenGlove", V3(4.2, 5.4, 4.6), gloveCF, C.gold, M.Metal, { reflect = 0.2 })
	blob(f, "GoldenThumb", V3(1.5, 2.6, 1.6), gloveCF * CF(-1.9, 0.2, -0.9) * ANG(0, 0, RAD(-18)), C.gold, M.Metal, { reflect = 0.2 })
	cyl(f, "GloveCuff", 2.0, 3.4, gloveCF * CF(0, -3.1, 0) * ANG(0, 0, RAD(90)), C.goldDeep, M.Metal)
	for k = 0, 3 do
		part(f, "GloveLace", V3(1.6, 0.12, 0.14), gloveCF * CF(0, -2.4 + k * 0.4, -1.75) * ANG(0, 0, RAD(k % 2 == 0 and 25 or -25)), Color3.fromRGB(150, 110, 20), M.Fabric)
	end
	local ml = spot(emitter(f, CF(mon + V3(0, 1.4, 6))), Enum.NormalId.Top, Color3.fromRGB(255, 225, 170), 16, 1.6, 60)
	ml.Enabled = false
	tag(ml, "NightLight")
	for _, d in ipairs({ { -76, 95.5 }, { -34, 95.5 }, { -76, 106.5 }, { -34, 106.5 } }) do
		GymDecor.Bench(f, V3(d[1], 0.22, d[2]), RAD(90), 5, C.wood)
	end
	for _, x in ipairs({ -84, -26 }) do
		part(f, "TreePlanter", V3(4, 1.2, 4), CF(x, 0.82, 101), Color3.fromRGB(120, 110, 100), M.Concrete, { collide = true })
		roundTree(f, V3(x, 1.4, 101), 11, rng)
	end
	local flagColors = { { C.red, C.white }, { Color3.fromRGB(18, 18, 22), C.gold }, { C.blue, C.white } }
	for i, x in ipairs({ -64, -55, -46 }) do
		local base = V3(x, 0.22, 110.2)
		vcyl(f, "FlagPole", 16, 0.3, CF(base), C.steelLight, M.Metal, { collide = true })
		ball(f, "FlagPoleTop", 0.5, CF(base + V3(0, 16.1, 0)), C.gold, M.Metal)
		local fl = part(f, "Flag", V3(0.08, 2.6, 4.2), CF(base + V3(0, 14.4, -2.2)), flagColors[i][1], M.Fabric, { shadow = false })
		GymDecor.Sign(fl, Enum.NormalId.Right, "WCB", flagColors[i][2], nil, 30)
		GymDecor.Sign(fl, Enum.NormalId.Left, "WCB", flagColors[i][2], nil, 30)
	end

	-- outdoor training yard east of the building (inside the loop)
	local y0 = V3(136, 0, -16)
	part(f, "YardFloor", V3(30, 0.25, 46), CF(y0 + V3(0, 0.125, 0)), Color3.fromRGB(44, 46, 50), M.Rubber, { collide = true })
	for k = 0, 3 do
		part(f, "SprintLane", V3(0.3, 0.03, 40), CF(y0 + V3(5 + k * 2.6, 0.265, 0)), C.white, M.SmoothPlastic)
	end
	for _, z in ipairs({ -18, -10 }) do
		for _, x in ipairs({ -10, -4 }) do
			part(f, "RigPost", V3(0.4, 9, 0.4), CF(y0 + V3(x, 4.75, z)), C.black, M.Metal, { collide = true })
		end
	end
	for _, x in ipairs({ -10, -4 }) do
		cyl(f, "RigBar", 8.4, 0.22, CF(y0 + V3(x, 8.4, -14)) * ANG(0, RAD(90), 0), C.steelLight, M.Metal)
	end
	for _, z in ipairs({ -18, -14, -10 }) do
		cyl(f, "PullUpBar", 6.4, 0.22, CF(y0 + V3(-7, 8.6, z)), C.steelLight, M.Metal)
	end
	for _, x in ipairs({ -9.2, -7.4 }) do
		cyl(f, "ParallelBar", 6, 0.25, CF(y0 + V3(x, 4.2, 0)) * ANG(0, RAD(90), 0), C.steelLight, M.Metal)
		for _, z in ipairs({ -2.6, 2.6 }) do
			part(f, "ParallelPost", V3(0.3, 4, 0.3), CF(y0 + V3(x, 2.25, z)), C.black, M.Metal)
		end
	end
	vcyl(f, "Tire", 1.7, 6.4, CF(y0 + V3(-6, 0.25, 12)), Color3.fromRGB(26, 26, 28), M.Rubber, { collide = true })
	vcyl(f, "TireInner", 0.05, 3.4, CF(y0 + V3(-6, 1.96, 12)), Color3.fromRGB(10, 10, 12), M.Rubber)
	for k = 0, 2 do
		blob(f, "Sandbag", V3(2.6, 1.2, 1.4), CF(y0 + V3(-11, 0.85 + k * 1.05, 18)) * ANG(0, RAD(k * 20), 0), Color3.fromRGB(70, 74, 52), M.Fabric)
	end
	local ysign = part(f, "YardSign", V3(10, 2.2, 0.3), CF(y0 + V3(0, 6, 22.6)), Color3.fromRGB(18, 18, 22), M.SmoothPlastic)
	for _, x in ipairs({ -4.8, 4.8 }) do
		part(f, "YardSignPost", V3(0.3, 5, 0.3), CF(y0 + V3(x, 2.5, 22.6)), C.black, M.Metal)
	end
	GymDecor.Sign(ysign, Enum.NormalId.Back, "OUTDOOR TRAINING YARD", C.gold, Color3.fromRGB(18, 18, 22), 30)
	GymDecor.Sign(ysign, Enum.NormalId.Front, "OUTDOOR TRAINING YARD", C.gold, Color3.fromRGB(18, 18, 22), 30)

	-- street lights along the roadwork loop (loop road: x/z = +-160 / 120 / -190, 10 wide)
	local lights = folder(f, "LoopLights")
	for _, x in ipairs({ -120, -60, 60, 120 }) do
		streetLight(lights, V3(x, 0, 127.5), V3(0, 0, -1), true)
		streetLight(lights, V3(x, 0, -197.5), V3(0, 0, 1), true)
	end
	for _, z in ipairs({ 70, 0, -70, -140 }) do
		streetLight(lights, V3(167.5, 0, z), V3(-1, 0, 0), true)
		streetLight(lights, V3(-167.5, 0, z), V3(1, 0, 0), true)
	end
	for _, c in ipairs({ { 167.5, 127.5 }, { -167.5, 127.5 }, { 167.5, -197.5 }, { -167.5, -197.5 } }) do
		streetLight(lights, V3(c[1], 0, c[2]), V3(-math.sign(c[1]), 0, -math.sign(c[2])).Unit, true)
	end
end

------------------------------------------------------------------------
-- South: Champion Ave and Main Street with shops
------------------------------------------------------------------------
-- action = ProximityPrompt Action at the counter (client CityVisuals / ClientMain dispatch);
-- interior = walk-in shop built by shopInterior (hollow front room, the rest of the block solid);
-- zone = LightZone profile inside; doorAt = door position along the front (fraction of the width)
local SHOPS = {
	{ x0 = -328, x1 = -304, h = 14, color = Color3.fromRGB(40, 40, 46), mat = M.Brick, sign = "FRESH FADES BARBERSHOP", signBg = Color3.fromRGB(14, 30, 70), signFg = Color3.fromRGB(240, 240, 245), awning = Color3.fromRGB(180, 30, 36), neon = true,
		interior = "barber", action = "Barber", actionText = "Get a cut", zone = "Barbershop", doorAt = -0.2 },
	{ x0 = -300, x1 = -262, h = 14, color = Color3.fromRGB(236, 234, 228), sign = "CHAMP'S DINER", signBg = Color3.fromRGB(190, 20, 30), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(200, 30, 36), neon = true,
		interior = "diner", action = "Diner", actionText = "Order food", zone = "Store" },
	{ x0 = -256, x1 = -222, h = 16, color = Color3.fromRGB(70, 72, 78), sign = "IRON SUPPLEMENTS", signBg = Color3.fromRGB(16, 18, 20), signFg = Color3.fromRGB(80, 220, 110), awning = Color3.fromRGB(30, 110, 60),
		interior = "supplements", action = "Supplements", actionText = "Buy supplements", zone = "Store" },
	{ x0 = -216, x1 = -176, h = 18, color = Color3.fromRGB(32, 32, 36), sign = "WCB PRO SHOP - GLOVES & GEAR", shop = "WCB PRO SHOP", signBg = Color3.fromRGB(14, 14, 16), signFg = C.gold, awning = Color3.fromRGB(20, 20, 24),
		interior = "proshop", action = "ProShop", actionText = "Browse gear", zone = "Store" },
	{ x0 = -170, x1 = -126, h = 34, color = Color3.fromRGB(134, 72, 56), mat = M.Brick, sign = "CORNER CAFE", signBg = Color3.fromRGB(60, 40, 30), signFg = Color3.fromRGB(255, 230, 190), awning = Color3.fromRGB(90, 60, 40), floors = 3 },
	{ x0 = -120, x1 = -90, h = 14, color = Color3.fromRGB(200, 222, 240), sign = "SPIN CITY LAUNDROMAT", signBg = Color3.fromRGB(40, 110, 200), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(40, 110, 200) },
	{ x0 = -84, x1 = -56, h = 16, color = Color3.fromRGB(40, 32, 52), sign = "INK & IRON TATTOO", signBg = Color3.fromRGB(20, 14, 26), signFg = Color3.fromRGB(220, 90, 255), awning = Color3.fromRGB(70, 30, 90), neon = true },
	{ x0 = -50, x1 = -18, h = 15, color = Color3.fromRGB(244, 222, 180), sign = "SUNRISE BAKERY", signBg = Color3.fromRGB(250, 240, 220), signFg = Color3.fromRGB(170, 90, 40), awning = Color3.fromRGB(240, 170, 60) },
	{ x0 = -12, x1 = 12, h = 22, color = Color3.fromRGB(26, 26, 30), sign = "WCB ARENA TICKETS", signBg = Color3.fromRGB(150, 16, 24), signFg = Color3.fromRGB(255, 220, 90), awning = Color3.fromRGB(150, 16, 24), marquee = true,
		action = "CareerHub", actionText = "Fight offers" },
	{ x0 = 18, x1 = 56, h = 14, color = Color3.fromRGB(220, 220, 214), sign = "CORNER STORE 24/7", signBg = Color3.fromRGB(30, 120, 60), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(30, 120, 60) },
	{ x0 = 62, x1 = 96, h = 15, color = Color3.fromRGB(176, 60, 44), mat = M.Brick, sign = "TONY'S PIZZA", signBg = Color3.fromRGB(20, 110, 50), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(200, 40, 40), neon = true,
		action = "Diner", actionText = "Grab a slice" },
	{ x0 = 102, x1 = 150, h = 42, color = Color3.fromRGB(150, 150, 156), mat = M.Concrete, sign = "RIVERSIDE APARTMENTS", signBg = Color3.fromRGB(30, 34, 40), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(30, 34, 40), floors = 4, apartments = true },
	{ x0 = 156, x1 = 196, h = 22, color = Color3.fromRGB(220, 210, 190), mat = M.Limestone, sign = "BOXING HALL OF FAME MUSEUM", signBg = Color3.fromRGB(20, 20, 24), signFg = C.gold, awning = Color3.fromRGB(20, 20, 24), columns = true,
		interior = "museum", action = "Museum", actionText = "Your legacy", zone = "Store", doorAt = 0, roomDepth = 22, roomH = 12 },
	{ x0 = 256, x1 = 300, h = 16, color = Color3.fromRGB(220, 200, 150), sign = "STARLIGHT MOTEL", signBg = Color3.fromRGB(16, 20, 40), signFg = Color3.fromRGB(255, 120, 180), awning = Color3.fromRGB(40, 60, 120), neon = true, poleSign = "MOTEL" },
	{ x0 = 304, x1 = 330, h = 16, color = Color3.fromRGB(26, 28, 34), mat = M.Metal, sign = "PRESTIGE MOTORS", signBg = Color3.fromRGB(12, 12, 16), signFg = Color3.fromRGB(220, 220, 230), awning = Color3.fromRGB(12, 12, 16),
		interior = "motors", action = "Motors", actionText = "Browse cars", zone = "Store", doorAt = 0.25, roomH = 12, roomDepth = 22 },
}

local FRONT_Z = 187 -- shop fronts face north (-Z) towards the gym; south sidewalk is z 183..187

------------------------------------------------------------------------
-- Walk-in shop interiors. The front room of the block is hollow (floor, side walls, a ceiling made
-- by the upper storeys, the solid back block as the back wall); the street front has glass panes
-- either side of an open door. ctx: x0/x1 inner side walls, z0 just inside the glass, z1 back
-- wall, y floor top, h room height, cx centre, doorX. Each builder returns the counter position
-- for the shop's prompt. Budgets: about 30-60 parts per shop.
------------------------------------------------------------------------
local INTERIOR = {}

-- a strip of products drawn on one part (a shelf of tubs, boxes or bottles in one SurfaceGui)
local function productRow(parent, cf, w, h, colors, labels, face)
	local p = part(parent, "ProductRow", V3(w, h, 0.8), cf, Color3.fromRGB(40, 40, 44), M.SmoothPlastic)
	local sg = gui(p, face or Enum.NormalId.Front, 30, 0.6, 120)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(34, 34, 38) })
	local n = math.max(1, math.floor(w / 1.3))
	for k = 0, n - 1 do
		local col = colors[k % #colors + 1]
		local box = frame(sg, { Size = UDim2.fromScale(0.8 / n, 0.86), Position = UDim2.fromScale((k + 0.1) / n, 0.1), BackgroundColor3 = col })
		Instance.new("UICorner", box).CornerRadius = UDim.new(0.15, 0)
		local txt = labels and labels[k % #labels + 1]
		if txt then
			label(box, txt, { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.35), Font = Enum.Font.GothamBold })
		end
	end
	return p
end

-- chequered floor drawn on the floor's top face (cheap: one SurfaceGui)
local function checkerFloor(floorPart, a, b, cols, rows)
	local sg = gui(floorPart, Enum.NormalId.Top, 6, 1, 160)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = a })
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			if (r + c) % 2 == 0 then
				frame(sg, { Size = UDim2.fromScale(1 / cols, 1 / rows), Position = UDim2.fromScale(c / cols, r / rows), BackgroundColor3 = b })
			end
		end
	end
end

local function counter(f, cf, len, topColor, bodyColor)
	part(f, "Counter", V3(len, 3.2, 2), cf * CF(0, 1.6, 0), bodyColor, M.WoodPlanks, { collide = true })
	part(f, "CounterTop", V3(len + 0.3, 0.2, 2.3), cf * CF(0, 3.3, 0), topColor, M.Marble)
	part(f, "Register", V3(1.2, 0.9, 1), cf * CF(len / 2 - 1, 3.85, 0.1) * ANG(RAD(-15), 0, 0), Color3.fromRGB(30, 30, 34), M.SmoothPlastic)
end

INTERIOR.supplements = function(f, d, c)
	local y = c.y
	local zBack = c.z1
	-- floor-to-ceiling shelving on the back wall: three shelves of tubs and boxes
	part(f, "ShelfBack", V3(c.x1 - c.x0 - 4, c.h - 1.5, 0.3), CF(c.cx, y + (c.h - 1.5) / 2, zBack - 0.2), Color3.fromRGB(26, 26, 28), M.SmoothPlastic)
	local tubColors = { Color3.fromRGB(30, 30, 30), Color3.fromRGB(240, 110, 20), Color3.fromRGB(30, 150, 70), Color3.fromRGB(200, 30, 40), Color3.fromRGB(230, 230, 230), Color3.fromRGB(40, 90, 200) }
	local names = { "WHEY", "BCAA", "CREATINE", "PRE", "MASS", "ISO", "OMEGA", "CASEIN" }
	for k, sy in ipairs({ 1.4, 3.6, 5.8 }) do
		part(f, "Shelf", V3(c.x1 - c.x0 - 4, 0.2, 1.6), CF(c.cx, y + sy - 0.15, zBack - 1.1), Color3.fromRGB(190, 190, 196), M.Metal)
		productRow(f, CF(c.cx, y + sy + 0.75, zBack - 1.1), c.x1 - c.x0 - 4.4, 1.5, tubColors, k == 2 and names or nil)
	end
	-- side wall: drinks fridge (glass front) and a big brand poster
	local fx = c.x0 + 1.4
	part(f, "Fridge", V3(2.6, 7, 4), CF(fx, y + 3.5, zBack - 4), Color3.fromRGB(220, 222, 226), M.Metal, { collide = true })
	local fg = part(f, "FridgeGlass", V3(0.1, 6, 3.4), CF(fx + 1.35, y + 3.6, zBack - 4), Color3.fromRGB(200, 230, 255), M.Glass, { transparency = 0.3 })
	local fsg = gui(fg, Enum.NormalId.Right, 20, 0.5, 80)
	for r = 0, 3 do
		for k = 0, 5 do
			local col = ({ Color3.fromRGB(60, 200, 255), Color3.fromRGB(255, 220, 40), Color3.fromRGB(240, 80, 60), Color3.fromRGB(120, 240, 120) })[(r + k) % 4 + 1]
			frame(fsg, { Size = UDim2.fromScale(0.1, 0.17), Position = UDim2.fromScale(0.06 + k * 0.155, 0.05 + r * 0.24), BackgroundColor3 = col })
		end
	end
	local fl = Instance.new("PointLight")
	fl.Color, fl.Range, fl.Brightness, fl.Shadows = Color3.fromRGB(200, 230, 255), 6, 0.8, false
	fl.Parent = fg
	local poster = part(f, "BrandPoster", V3(0.15, 5, 7), CF(c.x0 + 0.1, y + 5.2, c.z0 + 6), Color3.fromRGB(20, 20, 22), M.SmoothPlastic)
	GymDecor.Sign(poster, Enum.NormalId.Right, "BUILT IN THE GYM.\nFUELED BY IRON.", Color3.fromRGB(240, 110, 20), Color3.fromRGB(20, 20, 22), 30)
	-- shake bar / counter by the door side, tub pyramid display by the window, scale and mirror
	local ccf = CF(c.x1 - 5, y, c.z0 + 7) * ANG(0, RAD(90), 0)
	counter(f, ccf, 7, Color3.fromRGB(30, 30, 32), Color3.fromRGB(46, 120, 70))
	vcyl(f, "Blender", 1.4, 0.7, ccf * CF(-1.5, 3.4, 0), Color3.fromRGB(220, 230, 240), M.Glass, { transparency = 0.2 })
	for k, off in ipairs({ { -1.2, 0 }, { 0, 0 }, { 1.2, 0 }, { -0.6, 1.2 }, { 0.6, 1.2 }, { 0, 2.4 } }) do
		vcyl(f, "TubDisplay", 1.2, 0.95, CF(c.cx - 4 + off[1], y + off[2], c.z0 + 2.5), tubColors[k % #tubColors + 1], M.SmoothPlastic)
	end
	part(f, "Scale", V3(1.8, 0.3, 1.8), CF(c.x0 + 3, y + 0.15, c.z0 + 10), Color3.fromRGB(40, 40, 44), M.Metal)
	part(f, "ScaleMirror", V3(0.15, 6, 3), CF(c.x0 + 0.1, y + 3.6, c.z0 + 11.5), Color3.fromRGB(220, 235, 245), M.Glass, { reflect = 0.4 })
	return (ccf * CF(0, 0, -2.4)).Position + V3(0, 0.5, 0)
end

INTERIOR.proshop = function(f, d, c)
	local y = c.y
	local zBack = c.z1
	-- pegboard wall of gloves in every brand's colours, brand banners hanging from the ceiling
	local peg = part(f, "Pegboard", V3(c.x1 - c.x0 - 6, 6, 0.2), CF(c.cx, y + 4.2, zBack - 0.15), Color3.fromRGB(196, 170, 130), M.Wood)
	local psg = gui(peg, Enum.NormalId.Front, 10, 1, 80)
	for r = 0, 5 do
		for k = 0, 15 do
			frame(psg, { Size = UDim2.fromScale(0.012, 0.03), Position = UDim2.fromScale(0.03 + k * 0.062, 0.08 + r * 0.16), BackgroundColor3 = Color3.fromRGB(90, 70, 50) })
		end
	end
	local brands = {}
	for _, id in ipairs(Catalog.BrandOrder) do
		table.insert(brands, Catalog.Brand(id))
	end
	local span = c.x1 - c.x0 - 9
	for i, b in ipairs(brands) do
		local col = CityProps.RGB(b.palette and b.palette.primary, C.red)
		local row = (i - 1) % 2
		local gx = c.x0 + 4.5 + ((i - 1) / math.max(1, #brands - 1)) * span
		local gcf = CF(gx, y + 3.2 + row * 2.4, zBack - 0.8)
		blob(f, "DisplayGlove", V3(1.0, 1.25, 1.1), gcf * CF(-0.55, 0, 0) * ANG(0, 0, RAD(8)), col, M.Leather)
		blob(f, "DisplayGlove", V3(1.0, 1.25, 1.1), gcf * CF(0.55, 0, 0) * ANG(0, 0, RAD(-8)), col, M.Leather)
		-- brand banner (wordmark in the brand colours) above its gloves
		local word = b.wordmark ~= "" and b.wordmark or "GYM ISSUE"
		local ban = part(f, "BrandBanner", V3(3.2, 1.6, 0.08), CF(gx, y + c.h - 1.6, c.z0 + 4 + (i % 2) * 5), col, M.Fabric, { shadow = false })
		local fontOk, font = pcall(function()
			return Enum.Font[b.font]
		end)
		GymDecor.Sign(ban, Enum.NormalId.Front, word, CityProps.RGB(b.wordColor), col, 30, 0.4, fontOk and font or Enum.Font.GothamBlack)
		GymDecor.Sign(ban, Enum.NormalId.Back, word, CityProps.RGB(b.wordColor), col, 30, 0.4, fontOk and font or Enum.Font.GothamBlack)
	end
	-- boot wall on the left, robe mannequin, a hanging test bag and the belt case
	productRow(f, CF(c.x0 + 0.5, y + 2.2, c.z0 + 9) * ANG(0, RAD(90), 0), 8, 1.2, { Color3.fromRGB(20, 20, 24), Color3.fromRGB(240, 240, 240), Color3.fromRGB(200, 30, 36), Color3.fromRGB(230, 180, 40) }, { "BOOT", "PRO", "ELITE" }, Enum.NormalId.Back)
	productRow(f, CF(c.x0 + 0.5, y + 4.2, c.z0 + 9) * ANG(0, RAD(90), 0), 8, 1.2, { Color3.fromRGB(30, 60, 190), Color3.fromRGB(120, 20, 30), Color3.fromRGB(245, 240, 230) }, { "WRAPS", "GEL" }, Enum.NormalId.Back)
	local mq = CF(c.x0 + 5, y, c.z0 + 3.5)
	vcyl(f, "MannequinStand", 0.2, 2, mq, Color3.fromRGB(30, 30, 30), M.Metal)
	blob(f, "Robe", V3(2.6, 4.6, 1.6), mq * CF(0, 3.4, 0), Color3.fromRGB(200, 30, 36), M.Fabric)
	blob(f, "RobeTrim", V3(2.7, 0.5, 1.7), mq * CF(0, 1.3, 0), C.gold, M.Fabric)
	ball(f, "MannequinHead", 1.0, mq * CF(0, 6.2, 0), Color3.fromRGB(230, 230, 232), M.SmoothPlastic)
	local bagCF = CF(c.cx - 2, y, c.z0 + 9)
	part(f, "BagChain", V3(0.15, c.h - 6.6, 0.15), bagCF * CF(0, 6.6 + (c.h - 6.6) / 2, 0), C.steelLight, M.Metal)
	vcyl(f, "TestBag", 4.4, 2.0, bagCF * CF(0, 2.2, 0), Color3.fromRGB(150, 24, 30), M.Leather, { collide = true })
	local case = CF(c.cx + 5, y, c.z0 + 4)
	part(f, "CaseBase", V3(4, 3, 2.4), case * CF(0, 1.5, 0), Color3.fromRGB(30, 30, 34), M.Wood, { collide = true })
	part(f, "CaseGlass", V3(4, 1.8, 2.4), case * CF(0, 3.9, 0), Color3.fromRGB(210, 230, 245), M.Glass, { transparency = 0.6 })
	part(f, "ReplicaStrap", V3(3.2, 0.5, 0.9), case * CF(0, 3.3, 0), Color3.fromRGB(20, 20, 22), M.Leather)
	cyl(f, "ReplicaPlate", 0.2, 1.1, case * CF(0, 3.45, 0) * ANG(0, 0, RAD(90)), C.gold, M.Metal, { reflect = 0.25 })
	local ccf = CF(c.x1 - 4.5, y, c.z0 + 8) * ANG(0, RAD(90), 0)
	counter(f, ccf, 8, Color3.fromRGB(20, 20, 22), Color3.fromRGB(32, 32, 36))
	return (ccf * CF(0, 0, -2.4)).Position + V3(0, 0.5, 0)
end

INTERIOR.diner = function(f, d, c)
	local y = c.y
	-- counter with stools along the back, menu board above, booths down the side
	local ccf = CF(c.cx - 2, y, c.z1 - 4.5)
	part(f, "DinerCounter", V3(18, 3.4, 2.2), ccf * CF(0, 1.7, 0), Color3.fromRGB(200, 30, 36), M.SmoothPlastic, { collide = true })
	part(f, "DinerCounterTop", V3(18.4, 0.25, 2.6), ccf * CF(0, 3.5, 0), Color3.fromRGB(230, 230, 232), M.Marble)
	part(f, "DinerTrim", V3(18.4, 0.25, 0.1), ccf * CF(0, 2.6, -1.15), Color3.fromRGB(220, 220, 225), M.Metal, { reflect = 0.3 })
	for k = 0, 5 do
		local sx = -7.5 + k * 3
		vcyl(f, "StoolPost", 2.2, 0.3, ccf * CF(sx, 0, -2.6), C.steelLight, M.Metal)
		vcyl(f, "StoolSeat", 0.45, 1.5, ccf * CF(sx, 2.2, -2.6), Color3.fromRGB(200, 30, 36), M.Leather, { collide = true })
	end
	part(f, "PieCase", V3(3, 1.6, 1.6), ccf * CF(6.5, 4.4, 0), Color3.fromRGB(220, 235, 245), M.Glass, { transparency = 0.4 })
	part(f, "CoffeeMachine", V3(1.8, 2.2, 1.4), ccf * CF(-6.5, 4.7, 0.2), Color3.fromRGB(40, 40, 44), M.Metal)
	local menu = part(f, "MenuBoard", V3(14, 4, 0.2), CF(c.cx - 2, y + c.h - 2.8, c.z1 - 0.15), Color3.fromRGB(20, 20, 22), M.SmoothPlastic)
	local msg = gui(menu, Enum.NormalId.Front, 20, 0.2, 120)
	frame(msg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(22, 22, 24) })
	label(msg, "CHAMP'S MENU", { TextColor3 = C.gold, Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.03) })
	local lines = {}
	for _, meal in ipairs(Config.Meals) do
		if meal.price > 0 and not meal.requires then
			table.insert(lines, string.format("%s  %s", meal.name:upper(), Config.Money(meal.price)))
		end
	end
	label(msg, table.concat(lines, "\n"), { TextColor3 = Color3.fromRGB(240, 240, 235), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.27) })
	for k = 0, 2 do
		local bz = c.z0 + 2.2 + k * 3.6
		local bx = c.x1 - 3.2
		part(f, "BoothTable", V3(3.4, 0.25, 1.8), CF(bx, y + 2.6, bz), Color3.fromRGB(230, 230, 232), M.Marble)
		part(f, "BoothLeg", V3(0.3, 2.5, 0.3), CF(bx, y + 1.25, bz), C.steelLight, M.Metal)
		for _, s in ipairs({ -1, 1 }) do
			part(f, "BoothSeat", V3(3.4, 1.6, 1.0), CF(bx, y + 0.8, bz + s * 1.45), Color3.fromRGB(200, 30, 36), M.Leather, { collide = true })
			part(f, "BoothBack", V3(3.4, 2.4, 0.4), CF(bx, y + 2.4, bz + s * 1.85), Color3.fromRGB(170, 24, 30), M.Leather)
		end
	end
	-- jukebox in the corner, boxing photos of the regulars on the wall
	local jb = CF(c.x0 + 1.5, y, c.z1 - 1.5)
	part(f, "Jukebox", V3(2.4, 4.2, 1.6), jb * CF(0, 2.1, 0), Color3.fromRGB(120, 60, 30), M.Wood, { collide = true })
	local arch = part(f, "JukeboxGlow", V3(2.0, 1.4, 0.1), jb * CF(0, 3.4, -0.82), Color3.fromRGB(255, 160, 60), M.Neon, { shadow = false })
	local jl = Instance.new("PointLight")
	jl.Color, jl.Range, jl.Brightness, jl.Shadows = Color3.fromRGB(255, 140, 60), 8, 1, false
	jl.Parent = arch
	for k = 1, 2 do
		local ph = part(f, "DinerPhoto", V3(0.12, 3.2, 2.4), CF(c.x0 + 0.1, y + 5, c.z0 + 2 + k * 3.4), C.black, M.SmoothPlastic)
		GymDecor.PosterGui(ph, Enum.NormalId.Right, GymDecor.Posters[(k % #GymDecor.Posters) + 1])
	end
	return (ccf * CF(5, 0, -2.8)).Position + V3(0, 0.5, 0)
end

INTERIOR.barber = function(f, d, c)
	local y = c.y
	-- two stations on the back wall: mirror, shelf, chair; a waiting bench by the window
	for k = 0, 1 do
		local sx = c.cx - 3.5 + k * 7
		part(f, "StationMirror", V3(4, 4.5, 0.15), CF(sx, y + 5, c.z1 - 0.2), Color3.fromRGB(215, 232, 245), M.Glass, { reflect = 0.45 })
		part(f, "StationShelf", V3(4.4, 0.3, 1.2), CF(sx, y + 2.6, c.z1 - 0.7), Color3.fromRGB(30, 30, 34), M.Marble)
		blob(f, "Clippers", V3(0.4, 0.3, 0.9), CF(sx - 1, y + 2.9, c.z1 - 0.7), C.black, M.SmoothPlastic)
		vcyl(f, "Tonic", 0.9, 0.35, CF(sx + 1.2, y + 2.75, c.z1 - 0.7), Color3.fromRGB(60, 160, 200), M.Glass, { transparency = 0.2 })
		local ch = CF(sx, y, c.z1 - 4)
		vcyl(f, "ChairBase", 0.4, 2.2, ch, Color3.fromRGB(200, 200, 205), M.Metal)
		vcyl(f, "ChairPost", 1.4, 0.6, ch * CF(0, 0.4, 0), Color3.fromRGB(200, 200, 205), M.Metal)
		part(f, "ChairSeat", V3(2.2, 0.6, 2.2), ch * CF(0, 2.1, 0), Color3.fromRGB(150, 20, 26), M.Leather, { collide = true })
		part(f, "ChairBack", V3(2.2, 2.8, 0.5), ch * CF(0, 3.6, 1.0) * ANG(RAD(-10), 0, 0), Color3.fromRGB(150, 20, 26), M.Leather)
		for _, s in ipairs({ -1, 1 }) do
			part(f, "ChairArm", V3(0.3, 0.3, 1.8), ch * CF(s * 1.15, 3.0, 0.1), Color3.fromRGB(200, 200, 205), M.Metal)
		end
		part(f, "FootRest", V3(1.6, 0.2, 0.8), ch * CF(0, 0.9, -1.6), Color3.fromRGB(200, 200, 205), M.Metal)
	end
	GymDecor.Bench(f, V3(c.x0 + 1.5, y, c.z0 + 6), RAD(90), 6, C.woodDark)
	productRow(f, CF(c.x0 + 0.5, y + 4.6, c.z0 + 6) * ANG(0, RAD(90), 0), 6, 1.1, { Color3.fromRGB(30, 30, 34), Color3.fromRGB(200, 170, 80), Color3.fromRGB(40, 110, 160) }, { "POMADE", "BEARD OIL" }, Enum.NormalId.Back)
	local styles = part(f, "StyleChart", V3(0.12, 4, 3), CF(c.x1 - 0.1, y + 5, c.z0 + 4), C.white, M.SmoothPlastic)
	GymDecor.Sign(styles, Enum.NormalId.Left, "FADES\nTAPERS\nCORNROWS\nLOCS\nLINE-UPS", C.black, C.white, 30)
	-- the classic spinning pole beside the door (Ambience spins every SpinFan model)
	local pm = model(f, "BarberPole")
	local px, pz = c.doorX - 3, FRONT_Z - 0.6
	local hub = cyl(pm, "Hub", 4.4, 0.9, CF(px, 5.4, pz) * ANG(0, 0, RAD(90)), C.white, M.SmoothPlastic)
	for i = 0, 2 do
		part(pm, "Blade", V3(0.25, 0.95, 0.95), CF(px, 3.9 + i * 1.5, pz) * ANG(0, 0, RAD(60)), i % 2 == 0 and C.red or C.blue, M.SmoothPlastic)
	end
	part(pm, "PoleCap", V3(1.2, 0.4, 1.2), CF(px, 7.8, pz), Color3.fromRGB(210, 210, 215), M.Metal)
	part(pm, "PoleCap", V3(1.2, 0.4, 1.2), CF(px, 3.0, pz), Color3.fromRGB(210, 210, 215), M.Metal)
	pm.PrimaryPart = hub
	pm:SetAttribute("Speed", 2.2)
	tag(pm, "SpinFan")
	return V3(c.cx, y + 3.2, c.z1 - 7)
end

INTERIOR.museum = function(f, d, c)
	local y = c.y
	-- the great room: legends on plinths along both walls, a gloves-and-belt case in the middle,
	-- era banners and the HALL OF FAME wall at the back. Your own exhibit appears (CityVisuals) at
	-- Site_MuseumExhibit once you hold a title.
	local hof = part(f, "HallSign", V3(16, 3, 0.2), CF(c.cx, y + c.h - 2.6, c.z1 - 0.15), Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
	GymDecor.Sign(hof, Enum.NormalId.Front, "HALL OF FAME", C.gold, Color3.fromRGB(20, 20, 24), 30, 0, Enum.Font.Garamond)
	-- era banners flank the sign on the back wall
	for k, era in ipairs({ "THE BARE-KNUCKLE ERA", "THE GOLDEN AGE", "THE TELEVISION ERA", "THE MODERN GREATS" }) do
		local bx = c.cx + ({ -15, -10.5, 10.5, 15 })[k]
		local ban = part(f, "EraBanner", V3(3.4, 6, 0.1), CF(bx, y + c.h - 5, c.z1 - 0.3), Color3.fromRGB(110, 20, 26), M.Fabric)
		GymDecor.Sign(ban, Enum.NormalId.Front, era, C.gold, Color3.fromRGB(110, 20, 26), 30)
	end
	local bronze = Color3.fromRGB(150, 104, 54)
	for i = 1, math.min(6, #Config.Legends) do
		local lg = Config.Legends[i]
		local side = i % 2 == 1 and -1 or 1
		local row = math.floor((i - 1) / 2)
		local bx = side < 0 and c.x0 + 2.5 or c.x1 - 2.5
		local bz = c.z0 + 5 + row * 5.5
		local base = CF(bx, y, bz)
		part(f, "BustPlinth", V3(2.2, 3.6, 2.2), base * CF(0, 1.8, 0), Color3.fromRGB(230, 226, 216), M.Marble, { collide = true })
		blob(f, "BustShoulders", V3(2.0, 1.0, 1.1), base * CF(0, 4.0, 0), bronze, M.Metal, { reflect = 0.12 })
		blob(f, "BustHead", V3(0.95, 1.15, 1.05), base * CF(0, 4.9, 0), bronze, M.Metal, { reflect = 0.12 })
		local pl = part(f, "BustPlaque", V3(0.1, 1.2, 2.0), base * CF(-side * 1.15, 2.6, 0), C.gold, M.Metal)
		GymDecor.Sign(pl, side < 0 and Enum.NormalId.Right or Enum.NormalId.Left, string.format("%s\nLEGACY %d", lg.name, lg.score), Color3.fromRGB(40, 28, 10), C.gold, 40)
	end
	local cc = CF(c.cx, y, c.z0 + 8)
	part(f, "CaseBase", V3(5, 3, 3), cc * CF(0, 1.5, 0), Color3.fromRGB(30, 26, 22), M.Wood, { collide = true })
	part(f, "CaseGlass", V3(5, 2.2, 3), cc * CF(0, 4.1, 0), Color3.fromRGB(210, 230, 245), M.Glass, { transparency = 0.65 })
	blob(f, "VintageGlove", V3(1.0, 1.2, 1.1), cc * CF(-1.2, 3.6, 0), Color3.fromRGB(110, 60, 30), M.Leather)
	blob(f, "VintageGlove", V3(1.0, 1.2, 1.1), cc * CF(-0.1, 3.6, 0.2), Color3.fromRGB(110, 60, 30), M.Leather)
	part(f, "VintageBelt", V3(1.8, 0.4, 0.8), cc * CF(1.4, 3.3, 0), Color3.fromRGB(20, 20, 22), M.Leather)
	cyl(f, "VintagePlate", 0.15, 0.8, cc * CF(1.4, 3.42, 0) * ANG(0, 0, RAD(90)), C.gold, M.Metal, { reflect = 0.25 })
	-- velvet ropes keeping visitors off the case
	for k, off in ipairs({ { -3.5, -2.5 }, { 3.5, -2.5 }, { 3.5, 2.5 }, { -3.5, 2.5 } }) do
		vcyl(f, "Stanchion", 3, 0.3, cc * CF(off[1], 0, off[2]), C.goldDeep, M.Metal)
		local nxt = ({ { 3.5, -2.5 }, { 3.5, 2.5 }, { -3.5, 2.5 }, { -3.5, -2.5 } })[k]
		local a = (cc * CF(off[1], 2.6, off[2])).Position
		local b = (cc * CF(nxt[1], 2.6, nxt[2])).Position
		part(f, "VelvetRope", V3(0.18, 0.18, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Color3.fromRGB(140, 16, 30), M.Fabric)
	end
	-- spot lights on the exhibits (always on: it is indoors)
	for _, x in ipairs({ c.x0 + 2.5, c.x1 - 2.5 }) do
		spot(emitter(f, CF(x, y + c.h - 0.6, c.z0 + 10)), Enum.NormalId.Bottom, Color3.fromRGB(255, 230, 190), 18, 1.2, 70)
	end
	site("MuseumExhibit", CFrame.lookAt(V3(c.cx, y, c.z1 - 5), V3(c.cx, y, c.z0)))
	site("MuseumBanner", CFrame.lookAt(V3(c.cx, 14.6, FRONT_Z - 3.9), V3(c.cx, 14.6, FRONT_Z - 10)))
	return V3(c.cx + 4, y + 3.2, c.z0 + 4)
end

INTERIOR.motors = function(f, d, c)
	local y = c.y
	-- polished floor, two cars on turntables under spotlights, a sales desk and the brand wall
	local stands = { { c.x0 + 6.5, c.z0 + 8, 60, "Supercar" }, { c.x1 - 6.5, c.z0 + 14, 125, "SportsCar" } }
	for _, st in ipairs(stands) do
		local tcf = CF(st[1], y, st[2]) * ANG(0, RAD(st[3]), 0)
		vcyl(f, "Turntable", 0.3, 11, tcf, Color3.fromRGB(40, 40, 46), M.Metal, { reflect = 0.2, collide = true })
		CityProps.SportsCar(f, tcf * CF(0, 0.3, 0), st[4], nil, "PRESTIGE")
		spot(emitter(f, CF(st[1], y + c.h - 0.6, st[2])), Enum.NormalId.Bottom, Color3.fromRGB(240, 245, 255), 16, 1.6, 60)
	end
	local wall = part(f, "BrandWall", V3(c.x1 - c.x0 - 2, 3, 0.2), CF(c.cx, y + c.h - 2.6, c.z1 - 0.15), Color3.fromRGB(14, 14, 18), M.SmoothPlastic)
	GymDecor.Sign(wall, Enum.NormalId.Front, "PRESTIGE MOTORS", Color3.fromRGB(220, 220, 230), Color3.fromRGB(14, 14, 18), 30, 0, Enum.Font.Michroma)
	local desk = CF(c.x0 + 4, y, c.z1 - 2.5)
	part(f, "SalesDesk", V3(5, 2.8, 2), desk * CF(0, 1.4, 0), Color3.fromRGB(230, 230, 232), M.Marble, { collide = true })
	part(f, "DeskScreen", V3(1.6, 1.1, 0.1), desk * CF(0.8, 3.4, 0.3), Color3.fromRGB(20, 30, 50), M.Glass)
	return (desk * CF(2, 0, -2.4)).Position + V3(0, 0.5, 0)
end

-- the hollow front room of an interior shop (see INTERIOR above)
local function shopInterior(f, d, w, cx, doorX)
	local RD, RH = d.roomDepth or 16, d.roomH or 10
	local floorTop = d.columns and 0.8 or SW_H
	local mat = d.mat or M.SmoothPlastic
	for _, s in ipairs({ -1, 1 }) do
		part(f, "ShopSideWall", V3(1, RH, RD), CF(cx + s * (w / 2 - 0.5), RH / 2, FRONT_Z + RD / 2), d.color, mat, { collide = true })
	end
	local floorMat = ({ diner = M.SmoothPlastic, barber = M.SmoothPlastic, museum = M.Marble, motors = M.Marble, supplements = M.Rubber })[d.interior] or M.WoodPlanks
	local floorCol = ({ museum = Color3.fromRGB(226, 222, 214), motors = Color3.fromRGB(40, 40, 46), supplements = Color3.fromRGB(34, 34, 38) })[d.interior] or Color3.fromRGB(150, 110, 72)
	local fl = part(f, "ShopFloor", V3(w - 2, floorTop, RD), CF(cx, floorTop / 2, FRONT_Z + RD / 2), floorCol, floorMat, { collide = true })
	if d.interior == "diner" then
		checkerFloor(fl, Color3.fromRGB(24, 24, 26), Color3.fromRGB(236, 236, 230), 18, 8)
	elseif d.interior == "barber" then
		checkerFloor(fl, Color3.fromRGB(30, 30, 34), Color3.fromRGB(230, 230, 226), 12, 8)
	end
	-- facade: piers at both ends, a header above the glass, panes either side of the open door
	local glassTop = math.min(7.7, RH - 0.6)
	for _, s in ipairs({ -1, 1 }) do
		part(f, "ShopPier", V3(2, RH, 0.6), CF(cx + s * (w / 2 - 1), RH / 2, FRONT_Z + 0.3), d.color, mat, { collide = true })
	end
	part(f, "ShopHeader", V3(w, RH - glassTop, 0.6), CF(cx, glassTop + (RH - glassTop) / 2, FRONT_Z + 0.3), d.color, mat, { collide = true })
	local spans = { { cx - w / 2 + 2, doorX - 2 }, { doorX + 2, cx + w / 2 - 2 } }
	for _, sp in ipairs(spans) do
		local pw = sp[2] - sp[1]
		if pw > 0.6 then
			local pc = (sp[1] + sp[2]) / 2
			local pane = part(f, "ShopWindow", V3(pw, glassTop - 1, 0.12), CF(pc, 1 + (glassTop - 1) / 2, FRONT_Z + 0.1), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.6, reflect = 0.12, shadow = false, collide = true })
			pane:SetAttribute("Shop", d.sign)
			part(f, "Kickplate", V3(pw, 0.7, 0.3), CF(pc, 0.65, FRONT_Z + 0.1), Color3.fromRGB(40, 40, 44), M.Metal, { collide = true })
			local n = math.max(1, math.floor(pw / 6))
			for k = 0, n do
				part(f, "Mullion", V3(0.25, glassTop - 1, 0.25), CF(sp[1] + k * pw / n, 1 + (glassTop - 1) / 2, FRONT_Z + 0.1), Color3.fromRGB(30, 30, 34), M.Metal)
			end
		end
	end
	-- the door stands open inwards (glass leaf hinged at the right jamb)
	part(f, "ShopDoor", V3(0.15, glassTop - 0.2, 3.7), CF(doorX + 1.9, floorTop + (glassTop - 0.2) / 2, FRONT_Z + 2.1), Color3.fromRGB(180, 210, 230), M.Glass, { transparency = 0.45, shadow = false })
	part(f, "DoorFrame", V3(4.2, 0.3, 0.6), CF(doorX, glassTop + 0.15, FRONT_Z + 0.3), Color3.fromRGB(30, 30, 34), M.Metal)
	-- one warm interior light (on all day: Future lighting leaves a roofed room dark), two fixtures
	roomLight(f, CF(cx, RH - 0.8, FRONT_Z + RD * 0.55), Color3.fromRGB(255, 236, 214), math.max(20, w * 0.7), 1.1)
	for _, s in ipairs({ -0.25, 0.25 }) do
		part(f, "CeilingPanel", V3(4, 0.12, 2), CF(cx + s * w, RH - 0.06, FRONT_Z + RD * 0.55), Color3.fromRGB(250, 248, 240), M.Neon, { shadow = false })
	end
	lightZone(f, "ShopZone", V3(w - 2, RH, RD), CF(cx, RH / 2, FRONT_Z + RD / 2), d.zone or "Store")
	local build = INTERIOR[d.interior]
	local ctx = { x0 = cx - w / 2 + 1, x1 = cx + w / 2 - 1, z0 = FRONT_Z + 0.6, z1 = FRONT_Z + RD, y = floorTop, h = RH, cx = cx, doorX = doorX }
	local ok, at = pcall(build, f, d, ctx)
	if not ok then
		warn("[CityMap] interior " .. tostring(d.interior) .. " failed: " .. tostring(at))
		at = nil
	end
	return RD, RH, at
end

local function shop(f, d, rng)
	local w = d.x1 - d.x0
	local cx = (d.x0 + d.x1) / 2
	local depth = 30
	local h = d.h
	local sfW = w - 4
	local doorX = cx + w * (d.doorAt or 0.22)
	local body, gridPart, gridBase
	local counterAt
	if d.interior then
		-- the back of the block stays solid; the storeys above the shop room sit on its ceiling
		local RD, RH, at = shopInterior(f, d, w, cx, doorX)
		counterAt = at
		body = part(f, "Building", V3(w, h, depth - RD), CF(cx, h / 2, FRONT_Z + RD + (depth - RD) / 2), d.color, d.mat or M.SmoothPlastic, { collide = true })
		gridPart = part(f, "BuildingUpper", V3(w, h - RH, RD), CF(cx, RH + (h - RH) / 2, FRONT_Z + RD / 2), d.color, d.mat or M.SmoothPlastic, { collide = true })
		gridBase = RH
	else
		body = part(f, "Building", V3(w, h, depth), CF(cx, h / 2, FRONT_Z + depth / 2), d.color, d.mat or M.SmoothPlastic, { collide = true })
		gridPart, gridBase = body, 0
		-- storefront: dark interior, glass, mullions, door and kickplate
		part(f, "ShopInterior", V3(sfW, 7, 0.12), CF(cx, 4.2, FRONT_Z - 0.07), Color3.fromRGB(36, 40, 48), M.SmoothPlastic)
		local win = part(f, "ShopWindow", V3(sfW, 7, 0.1), CF(cx, 4.2, FRONT_Z - 0.2), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.55, reflect = 0.12, shadow = false })
		win:SetAttribute("Shop", d.sign)
		local n = math.max(1, math.floor(sfW / 6))
		for k = 0, n do
			part(f, "Mullion", V3(0.3, 7, 0.25), CF(d.x0 + 2 + k * sfW / n, 4.2, FRONT_Z - 0.2), Color3.fromRGB(30, 30, 34), M.Metal)
		end
		part(f, "ShopDoor", V3(3.2, 6.6, 0.15), CF(doorX, 3.9, FRONT_Z - 0.32), Color3.fromRGB(28, 28, 32), M.Metal)
		part(f, "Kickplate", V3(sfW, 0.7, 0.3), CF(cx, 0.65, FRONT_Z - 0.15), Color3.fromRGB(40, 40, 44), M.Metal)
	end
	part(f, "Cornice", V3(w + 0.8, 0.9, depth + 0.8), CF(cx, h + 0.45, FRONT_Z + depth / 2), Color3.fromRGB(60, 58, 56), M.Concrete)
	-- where a sponsor's poster goes in this shop's window (CityVisuals, when you carry their brand)
	-- walk-in shops: just behind the glass, inside the room; facade-only shops are a solid block from
	-- FRONT_Z back, so their standee stands on the sidewalk in front of the window (foot clear of the
	-- glass at FRONT_Z - 0.2 and the kickplate). Shop = the Catalog sponsor's `shop` key when the sign is longer.
	local wz = d.interior and FRONT_Z + 1.2 or FRONT_Z - 1.4
	site("Window_" .. d.sign:gsub("[^%w]", ""), CFrame.lookAt(V3(d.x0 + 4.5, SW_H, wz), V3(d.x0 + 4.5, SW_H, wz - 6)), { Shop = d.shop or d.sign })
	-- the prompt: at the counter inside walk-in shops, by the door otherwise
	if d.action then
		local at = counterAt or V3(doorX, SW_H + 2.4, FRONT_Z - 1.6)
		promptPart(f, "ShopPrompt", at, d.actionText or "Enter", d.sign, { Action = d.action, Store = d.sign }, d.signFg)
	end
	-- warm light spilling out of the shop at night
	local glow = point(emitter(f, CF(cx, 5, FRONT_Z - 1.2)), Color3.fromRGB(255, 214, 160), 16, 0.9)
	glow.Enabled = false
	tag(glow, "NightLight")
	-- awning and sign band
	part(f, "ShopAwning", V3(w - 1.5, 0.35, 4.2), CF(cx, 8.6, FRONT_Z - 1.9) * ANG(RAD(-14), 0, 0), d.awning, M.Fabric)
	local signPart = part(f, "ShopSign", V3(w - 3, 2.6, 0.4), CF(cx, 10.9, FRONT_Z - 0.25), d.signBg, M.SmoothPlastic)
	local sg = gui(signPart, Enum.NormalId.Front, 20, 0, 700)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = d.signBg })
	label(sg, d.sign, { TextColor3 = d.signFg, Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1) })
	if d.neon then
		neonOutline(f, CF(cx, 10.9, FRONT_Z - 0.56), w - 2.6, 2.9, d.signFg)
	end
	-- upper floors
	local wy0 = d.marquee and 16 or (d.columns and 14.6 or 13)
	local rows = d.floors or math.floor((h - 1.5 - wy0) / 5.5)
	if rows >= 1 then
		windowGrid(gridPart, Enum.NormalId.Front, h - gridBase, wy0 - gridBase, h - 1.5 - gridBase, rows, math.max(2, math.floor(w / 7)), rng, 0.4)
	end
	if d.marquee then
		local mq = part(f, "Marquee", V3(w + 2, 3.2, 3), CF(cx, 13.6, FRONT_Z - 1.6), Color3.fromRGB(20, 20, 24), M.Metal)
		local msg = gui(mq, Enum.NormalId.Front, 20, 0, 700)
		frame(msg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(250, 246, 230) })
		label(msg, "SAT: VEGA vs KOVAC  -  WORLD TITLE", { Name = "MarqueeText", TextColor3 = Color3.fromRGB(20, 20, 24), Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15) })
		-- CityVisuals writes your next fight here
		mq:SetAttribute("Kind", "Marquee")
		tag(mq, "CityScreen")
		for k = 0, 7 do
			ball(f, "MarqueeBulb", 0.35, CF(cx - w / 2 - 0.6 + k * (w + 1.2) / 7, 15.35, FRONT_Z - 3.0), Color3.fromRGB(255, 230, 150), M.Neon, { shadow = false })
		end
	end
	if d.columns then
		part(f, "MuseumSteps", V3(w - 6, 0.8, 3.6), CF(cx, 0.4, FRONT_Z - 1.8), Color3.fromRGB(200, 196, 186), M.Limestone, { collide = true })
		for k = 0, 3 do
			vcyl(f, "MuseumColumn", 11.7, 1.4, CF(d.x0 + 6 + k * (w - 12) / 3, 0.8, FRONT_Z - 2.6), Color3.fromRGB(235, 228, 210), M.Limestone, { collide = true })
		end
		part(f, "Pediment", V3(w - 4, 1.4, 3.8), CF(cx, 13.2, FRONT_Z - 1.8), Color3.fromRGB(235, 228, 210), M.Limestone)
	end
	if d.poleSign then
		local px = d.x0 + 3
		part(f, "PoleSignPost", V3(0.6, 24, 0.6), CF(px, 12, FRONT_Z - 2.5), POLE, M.Metal, { collide = true })
		local ps = part(f, "PoleSign", V3(1, 9, 3.6), CF(px, 20, FRONT_Z - 2.5), Color3.fromRGB(16, 20, 40), M.SmoothPlastic)
		local txt = table.concat(string.split(d.poleSign, ""), "\n")
		GymDecor.Sign(ps, Enum.NormalId.Left, txt, d.signFg, Color3.fromRGB(16, 20, 40), 20)
		GymDecor.Sign(ps, Enum.NormalId.Right, txt, d.signFg, Color3.fromRGB(16, 20, 40), 20)
		for _, s in ipairs({ -1, 1 }) do
			neonOutline(f, CF(px + s * 0.62, 20, FRONT_Z - 2.5) * ANG(0, RAD(90 * s), 0), 3.5, 8.9, d.signFg)
		end
	end
	if rng:NextNumber() < 0.7 then
		part(f, "RoofUnit", V3(5, 2.4, 4), CF(cx + rng:NextNumber(-w / 4, w / 4), h + 2.1, FRONT_Z + depth * 0.6), Color3.fromRGB(196, 198, 202), M.Metal)
	end
	return body
end

local function gasStation(f)
	local cx, cz = 226, 202
	slab(f, "GasApron", 200, 252, FRONT_Z, 221, 0.2, Color3.fromRGB(150, 150, 152), M.Concrete)
	-- canopy on four pillars with a red fascia stripe and light panels underneath
	part(f, "GasCanopy", V3(40, 1.6, 20), CF(cx, 14.2, cz), C.white, M.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		part(f, "GasFascia", V3(40.3, 0.8, 0.2), CF(cx, 14.2, cz + s * 10.05), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
		part(f, "GasFascia", V3(0.2, 0.8, 20.3), CF(cx + s * 20.05, 14.2, cz), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	end
	for _, x in ipairs({ -12, 0, 12 }) do
		part(f, "CanopyPanel", V3(6, 0.08, 3), CF(cx + x, 13.36, cz), Color3.fromRGB(245, 248, 255), M.Neon, { shadow = false })
	end
	for _, x in ipairs({ -14, 14 }) do
		for _, z in ipairs({ -6, 6 }) do
			part(f, "GasPillar", V3(1, 13, 1), CF(cx + x, 6.7, cz + z), C.white, M.SmoothPlastic, { collide = true })
		end
	end
	for _, x in ipairs({ -10, 0, 10 }) do
		part(f, "PumpIsland", V3(3, 0.5, 8), CF(cx + x, 0.45, cz), Color3.fromRGB(190, 186, 180), M.Concrete, { collide = true })
		for _, z in ipairs({ -2, 2 }) do
			local pump = part(f, "Pump", V3(1.6, 5, 1.2), CF(cx + x, 3.2, cz + z), Color3.fromRGB(200, 30, 36), M.SmoothPlastic, { collide = true })
			GymDecor.Sign(pump, Enum.NormalId.Front, "3.49", C.gold, C.black, 40)
		end
	end
	for _, x in ipairs({ -8, 8 }) do
		spot(emitter(f, CF(cx + x, 12.8, cz)), Enum.NormalId.Bottom, Color3.fromRGB(240, 245, 255), 26, 1.6, 120)
	end
	-- the shop behind the pumps and the price pylon by the street
	part(f, "GasShop", V3(26, 11, 14), CF(cx, 5.5, cz + 18), Color3.fromRGB(230, 230, 226), M.SmoothPlastic, { collide = true })
	local gs = part(f, "GasShopSign", V3(18, 2.2, 0.3), CF(cx, 9.4, cz + 10.85), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	GymDecor.Sign(gs, Enum.NormalId.Front, "FUEL & GO - SNACKS - ICE", Color3.new(1, 1, 1), Color3.fromRGB(200, 30, 36), 20)
	local gw = part(f, "GasShopWindow", V3(20, 5, 0.1), CF(cx, 3.6, cz + 10.9), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.45, shadow = false })
	gw:SetAttribute("Shop", "FUEL & GO")
	-- on the apron in front of the shop window (cz + 10.9); the shop block itself starts at cz + 11
	site("Window_FUELGO", CFrame.lookAt(V3(cx - 6, 0.2, cz + 9.8), V3(cx - 6, 0.2, cz)), { Shop = "FUEL & GO" })
	local py = V3(cx - 25, 0, cz - 9)
	part(f, "PylonPole", V3(0.8, 16, 0.8), CF(py + V3(0, 8, 0)), C.steel, M.Metal, { collide = true })
	local pylon = part(f, "Pylon", V3(6, 6, 1), CF(py + V3(0, 17, 0)), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local psg = gui(pylon, face, 20, 0, 700)
		frame(psg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 30, 36) })
		label(psg, "GAS", { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.8, 0.4), Position = UDim2.fromScale(0.1, 0.05) })
		label(psg, "3.49", { TextColor3 = C.gold, Font = Enum.Font.Code, Size = UDim2.fromScale(0.8, 0.45), Position = UDim2.fromScale(0.1, 0.5) })
	end
end

-- Riverside Apartments: lobby canopy, balconies, fire escape, AC units, rooftop tank and the
-- penthouse terrace (the player's apartment when they buy one; CityVisuals dresses it)
local function apartmentExtras(f, d, rng)
	local w = d.x1 - d.x0
	local cx = (d.x0 + d.x1) / 2
	local h = d.h
	local doorX = cx + w * (d.doorAt or 0.22)
	local concrete = Color3.fromRGB(120, 120, 126)
	local rail = Color3.fromRGB(40, 42, 48)
	-- lobby canopy with a lit address plate
	part(f, "LobbyCanopy", V3(7, 0.4, 4.4), CF(doorX, 8.0, FRONT_Z - 2.2), Color3.fromRGB(26, 28, 32), M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		part(f, "CanopyPost", V3(0.25, 7.6, 0.25), CF(doorX + s * 3.2, SW_H + 3.8, FRONT_Z - 4.2), Color3.fromRGB(26, 28, 32), M.Metal, { collide = true })
	end
	local plate = part(f, "AddressPlate", V3(3, 0.6, 0.08), CF(doorX, 8.6, FRONT_Z - 4.42), Color3.fromRGB(230, 200, 120), M.Metal)
	GymDecor.Sign(plate, Enum.NormalId.Front, "1 RIVERSIDE", Color3.fromRGB(40, 30, 10), Color3.fromRGB(230, 200, 120), 40)
	nightPoint(f, CF(doorX, 7.4, FRONT_Z - 2.4), Color3.fromRGB(255, 220, 170), 12, 0.9)
	-- balconies under the middle window columns of floors 2-4 (the window grid's band is y 13..h-1.5)
	local cols = math.max(2, math.floor(w / 7))
	local rowH = (h - 1.5 - 13) / (d.floors or 4)
	for fl = 1, (d.floors or 4) - 1 do
		local y = 13 + fl * rowH
		for c = 1, cols - 2 do
			local x = d.x0 + (c + 0.5) / cols * w
			part(f, "Balcony", V3(w / cols * 0.75, 0.35, 2.4), CF(x, y, FRONT_Z - 1.2), concrete, M.Concrete)
			part(f, "BalconyRail", V3(w / cols * 0.75, 1.6, 0.12), CF(x, y + 0.95, FRONT_Z - 2.35), rail, M.Metal, { transparency = 0.15 })
		end
	end
	-- fire escape on the west wall: landings, rails and diagonal flights
	local fx = d.x0 - 1.4
	for fl = 1, (d.floors or 4) - 1 do
		local y = 13 + fl * rowH
		part(f, "FireLanding", V3(2.6, 0.2, 7), CF(fx, y, FRONT_Z + 12), rail, M.DiamondPlate)
		part(f, "FireRail", V3(0.12, 1.4, 7), CF(fx - 1.25, y + 0.8, FRONT_Z + 12), rail, M.Metal)
		local a = V3(fx, y - rowH + 0.2, FRONT_Z + 9)
		local b = V3(fx, y, FRONT_Z + 15)
		if fl > 1 then
			part(f, "FireStair", V3(2.0, 0.2, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), rail, M.DiamondPlate)
		end
	end
	-- window AC units dotted across the facade (lived-in look)
	for _ = 1, 5 do
		local c = rng:NextInteger(0, cols - 1)
		local fl = rng:NextInteger(0, (d.floors or 4) - 1)
		part(f, "ACUnit", V3(1.8, 1.1, 1.2), CF(d.x0 + (c + 0.5) / cols * w + 1.4, 13 + fl * rowH + 1.2, FRONT_Z - 0.6), Color3.fromRGB(210, 210, 206), M.Metal)
	end
	-- roof: water tank on legs, stair hut, glass terrace rail along the front (penthouse)
	local tank = V3(d.x1 - 8, h + 0.9, FRONT_Z + 20)
	for _, o in ipairs({ { -1.6, -1.6 }, { 1.6, -1.6 }, { -1.6, 1.6 }, { 1.6, 1.6 } }) do
		part(f, "TankLeg", V3(0.3, 4, 0.3), CF(tank + V3(o[1], 2, o[2])), rail, M.Metal)
	end
	vcyl(f, "WaterTank", 5.5, 5, CF(tank + V3(0, 4, 0)), Color3.fromRGB(120, 86, 60), M.WoodPlanks)
	part(f, "TankRoof", V3(5.2, 1.4, 5.2), CF(tank + V3(0, 10.2, 0)) * ANG(0, RAD(45), 0), Color3.fromRGB(60, 50, 44), M.Slate)
	part(f, "StairHut", V3(6, 5, 6), CF(d.x0 + 6, h + 3.4, FRONT_Z + 22), concrete, M.Concrete, { collide = true })
	part(f, "TerraceRail", V3(w - 4, 1.6, 0.12), CF(cx, h + 1.7, FRONT_Z + 0.8), Color3.fromRGB(190, 220, 240), M.Glass, { transparency = 0.5 })
	site("ApartmentRoof", CFrame.lookAt(V3(cx, h + 0.9, FRONT_Z + 8), V3(cx, h + 0.9, FRONT_Z - 10)))
	site("ApartmentBanner", CFrame.lookAt(V3(d.x0 + 2.5 / cols * w, 13 + 2.5 * rowH, FRONT_Z - 0.15), V3(d.x0 + 2.5 / cols * w, 13 + 2.5 * rowH, FRONT_Z - 10)))
	-- the way in: prompt + realty sign (CityVisuals marks it SOLD with your name once you own it)
	site("HomeApartment", CFrame.lookAt(V3(doorX, SW_H, FRONT_Z - 2.6), V3(doorX, SW_H, FRONT_Z - 10)))
	promptPart(f, "HomePrompt", V3(doorX, SW_H + 2.4, FRONT_Z - 1.4), "Enter apartment", "Riverside Apartments", { Action = "Home", Kind = "Apartment" }, Color3.fromRGB(255, 230, 170))
	part(f, "RealtyPost", V3(0.2, 4.2, 0.2), CF(doorX - 5, SW_H + 2.1, FRONT_Z - 3.4), C.white, M.Wood)
	local rs = part(f, "RealtySign", V3(2.6, 1.6, 0.1), CF(doorX - 5, SW_H + 3.6, FRONT_Z - 3.4), Color3.fromRGB(180, 30, 36), M.SmoothPlastic)
	GymDecor.Sign(rs, Enum.NormalId.Front, "PENTHOUSE\nAVAILABLE\nCITY REALTY", C.white, Color3.fromRGB(180, 30, 36), 40)
	rs:SetAttribute("Kind", "ForSale")
	rs:SetAttribute("Home", "Apartment")
	tag(rs, "CityScreen")
end

-- Walk of Fame along Champion Ave: the all-time greats on the west sidewalk (shared), your own
-- stars appear on the east sidewalk (CityVisuals, at Site_WalkOfFame)
local function walkOfFame(f)
	local k = 0
	for z = 129, 161, 4 do
		k += 1
		local lg = Config.Legends[k]
		if lg then
			CityProps.Star(f, CF(-9.5, SW_H + 0.03, z), "LEGACY " .. lg.score, lg.name)
		end
	end
	site("WalkOfFame", CF(9.5, SW_H + 0.03, 129), { Step = 4, Max = 9 })
	local post = part(f, "FameSignPost", V3(0.25, 5, 0.25), CF(-10.8, SW_H + 2.5, 126), C.steel, M.Metal)
	local fs = part(f, "FameSign", V3(4.4, 1.4, 0.12), CF(-10.8, SW_H + 5.4, 126), Color3.fromRGB(60, 30, 50), M.SmoothPlastic)
	GymDecor.Sign(fs, Enum.NormalId.Back, "WALK OF FAME", C.gold, Color3.fromRGB(60, 30, 50), 40)
	GymDecor.Sign(fs, Enum.NormalId.Front, "WALK OF FAME", C.gold, Color3.fromRGB(60, 30, 50), 40)
	return post
end

local function buildSouth(root)
	local f = folder(root, "MainStreet")
	local rng = Random.new(1987)
	-- Champion Ave: from the loop road (z 125) to Main Street (z 167)
	slab(f, "ChampionAve", -8, 8, 125, 167, 0.3, ASPHALT, M.Asphalt)
	for z = 130, 160, 6 do
		part(f, "LaneDash", V3(0.35, 0.03, 3), CF(0, 0.315, z), LINE_YELLOW, M.SmoothPlastic)
	end
	slab(f, "AveSidewalk", -11, -8, 125, 163, SW_H, SIDEWALK, M.Concrete)
	slab(f, "AveSidewalk", 8, 11, 125, 163, SW_H, SIDEWALK, M.Concrete)
	local ave = part(f, "StreetSign", V3(5, 1, 0.12), CF(-10.8, 8.6 + SW_H, 128), Color3.fromRGB(30, 110, 60), M.SmoothPlastic)
	part(f, "StreetSignPole", V3(0.25, 9, 0.25), CF(-10.8, 4.5 + SW_H, 128.2), C.steel, M.Metal)
	GymDecor.Sign(ave, Enum.NormalId.Front, "CHAMPION AVE", Color3.new(1, 1, 1), Color3.fromRGB(30, 110, 60), 40)
	GymDecor.Sign(ave, Enum.NormalId.Back, "CHAMPION AVE", Color3.new(1, 1, 1), Color3.fromRGB(30, 110, 60), 40)
	-- Main Street along X (z 167..183) with sidewalks, centre line, crosswalks and parked cars
	slab(f, "MainStreet", -330, 330, 167, 183, 0.3, ASPHALT, M.Asphalt)
	for x = -320, 320, 10 do
		if math.abs(x) > 10 then
			-- between the two traffic lanes (169.6 / 174.8, CityVisuals); the parking row is 177.4..183
			part(f, "CenterDash", V3(4, 0.03, 0.35), CF(x, 0.315, 172.2), LINE_YELLOW, M.SmoothPlastic)
		end
	end
	for _, seg in ipairs({ { -330, -269 }, { -255, -8 }, { 8, 330 } }) do
		slab(f, "SidewalkN", seg[1], seg[2], 163, 167, SW_H, SIDEWALK, M.Concrete)
	end
	slab(f, "SidewalkS", -330, 330, 183, FRONT_Z, SW_H, SIDEWALK, M.Concrete)
	for _, x in ipairs({ -12.5, 12.5 }) do
		crosswalk(f, V3(x, 0.32, 175), false, 16, 5)
	end
	for i, x in ipairs({ -244, -150, -36, 78, 132, 284 }) do
		car(f, CF(x, 0.3, 180.2) * ANG(0, RAD(i % 2 == 0 and 90 or -90), 0), CAR_COLORS[(i + 2) % #CAR_COLORS + 1])
	end
	-- street lights between the sidewalk trees, plus a few on the shop side
	for _, x in ipairs({ -278, -188, -108, 92, 172, 252 }) do
		streetLight(f, V3(x, SW_H, 164.2), V3(0, 0, 1), true)
	end
	for _, x in ipairs({ -236, -34, 153 }) do
		streetLight(f, V3(x, SW_H, 185.8), V3(0, 0, -1), false)
	end
	for _, d in ipairs(SHOPS) do
		shop(f, d, rng)
		if d.apartments then
			apartmentExtras(f, d, rng)
		end
	end
	gasStation(f)
	walkOfFame(f)
	-- the street's own colour grade (shops grade themselves inside: Ambience picks the smallest box)
	lightZone(f, "StreetZone", V3(660, 44, 34), CF(0, 22, 175), "Street")
	-- trees in sidewalk pits along the north sidewalk
	for x = -300, 300, 40 do
		if math.abs(x) > 20 then
			local tx = x + 12
			if tx < -272 or tx > -252 then -- keep the Oak Street junction clear
				part(f, "TreePit", V3(2.4, 0.05, 2.4), CF(tx, SW_H + 0.02, 165), Color3.fromRGB(70, 52, 36), M.Ground)
				roundTree(f, V3(tx, SW_H, 165), 9, rng)
			end
		end
	end
end

------------------------------------------------------------------------
-- West: Oak Street with houses (x = -262, from Main Street north)
------------------------------------------------------------------------
local HOUSE_COLORS = {
	Color3.fromRGB(220, 206, 180), Color3.fromRGB(176, 196, 214), Color3.fromRGB(214, 180, 170), Color3.fromRGB(200, 214, 180),
	Color3.fromRGB(238, 236, 228), Color3.fromRGB(190, 170, 200), Color3.fromRGB(150, 168, 190),
}

local function house(f, center, front, rng, i)
	local W, D, H, R = 16, 14, 10, 5
	local base = CFrame.lookAt(center, center + front) -- local -Z = front, X = along the street
	local color = HOUSE_COLORS[(i - 1) % #HOUSE_COLORS + 1]
	part(f, "House", V3(W, H, D), base * CF(0, H / 2, 0), color, M.WoodPlanks, { collide = true })
	-- gable roof from two wedges, low edges at the front and back walls
	local roofColor = ({ Color3.fromRGB(80, 50, 40), Color3.fromRGB(60, 62, 70), Color3.fromRGB(110, 60, 44) })[i % 3 + 1]
	local a = (base * CF(0, H + R / 2, -D / 4)).Position
	local b = (base * CF(0, H + R / 2, D / 4)).Position
	part(f, "Roof", V3(W + 1, R, D / 2 + 0.6), CFrame.lookAt(a, a + front), roofColor, M.Slate, { class = "WedgePart", collide = true })
	part(f, "Roof", V3(W + 1, R, D / 2 + 0.6), CFrame.lookAt(b, b - front), roofColor, M.Slate, { class = "WedgePart", collide = true })
	part(f, "Chimney", V3(1.6, 4, 1.6), base * CF(W * 0.3, H + R - 0.5, D * 0.15), Color3.fromRGB(130, 70, 56), M.Brick)
	-- door, porch, windows
	part(f, "Door", V3(2.4, 5.4, 0.2), base * CF(-W * 0.18, 3.3, -D / 2 - 0.1), ({ C.red, Color3.fromRGB(30, 60, 120), Color3.fromRGB(30, 90, 60) })[i % 3 + 1], M.Wood)
	part(f, "Porch", V3(6, 0.6, 3), base * CF(-W * 0.18, 0.3, -D / 2 - 1.5), Color3.fromRGB(150, 140, 130), M.Concrete, { collide = true })
	part(f, "PorchRoof", V3(6, 0.3, 3.2), base * CF(-W * 0.18, 6.9, -D / 2 - 1.5), color:Lerp(Color3.new(0, 0, 0), 0.3), M.WoodPlanks)
	for _, x in ipairs({ W * 0.12, W * 0.34 }) do
		part(f, "HouseWindow", V3(2.6, 2.8, 0.15), base * CF(x, 4.6, -D / 2 - 0.08), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.25 })
		part(f, "WindowTrim", V3(3.0, 0.3, 0.3), base * CF(x, 3.1, -D / 2 - 0.15), C.white, M.Wood)
	end
	-- mailbox at the kerb, front path and a hedge
	local mb = base * CF(W * 0.4, 0, -D / 2 - 9)
	part(f, "MailboxPost", V3(0.25, 3, 0.25), mb * CF(0, 1.5 + SW_H, 0), C.wood, M.Wood)
	part(f, "Mailbox", V3(0.8, 0.8, 1.4), mb * CF(0, 3.3 + SW_H, 0), ({ C.black, C.blue, C.red })[i % 3 + 1], M.Metal)
	part(f, "FrontPath", V3(2.4, 0.12, 8), base * CF(-W * 0.18, 0.06, -D / 2 - 7), Color3.fromRGB(180, 176, 168), M.Concrete)
	blob(f, "Hedge", V3(5, 2.2, 1.8), base * CF(W * 0.3, 1.1, -D / 2 - 1.5), Color3.fromRGB(50, 110, 55), M.Grass)
	if rng:NextNumber() < 0.5 then
		car(f, base * CF(W / 2 + 4.5, 0, -2) * ANG(0, RAD(180), 0), CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)])
	end
	-- a few things that say somebody lives here (own random stream: the car layout above is unchanged)
	local srng = Random.new(900 + i)
	local story = {}
	for k = 1, 6 do
		story[k] = k
	end
	for k = #story, 2, -1 do
		local j = srng:NextInteger(1, k)
		story[k], story[j] = story[j], story[k]
	end
	for n = 1, 2 do
		local kind = story[n]
		if kind == 1 then -- kid's bike leaning by the porch
			local bcf = base * CF(-W * 0.18 + 3.6, 0, -D / 2 - 2.2) * ANG(0, RAD(90), RAD(12))
			for _, z in ipairs({ -0.9, 0.9 }) do
				cyl(f, "BikeWheel", 0.12, 1.3, bcf * CF(0, 0.7, z), C.black, M.Rubber)
			end
			part(f, "BikeFrame", V3(0.12, 0.12, 1.9), bcf * CF(0, 1.05, 0), ({ C.red, C.blue, C.green })[i % 3 + 1], M.Metal)
		elseif kind == 2 then -- bins at the kerb
			for k, col in ipairs({ Color3.fromRGB(40, 90, 50), Color3.fromRGB(40, 60, 120) }) do
				part(f, "Bin", V3(1.4, 2.4, 1.4), base * CF(W * 0.1 + k * 1.6, 1.2 + SW_H, -D / 2 - 8.6), col, M.SmoothPlastic, { collide = true })
			end
		elseif kind == 3 then -- porch light that comes on at dusk
			part(f, "PorchLamp", V3(0.5, 0.7, 0.3), base * CF(-W * 0.18 + 1.8, 5.2, -D / 2 - 0.2), Color3.fromRGB(255, 230, 170), M.Neon, { shadow = false })
			nightPoint(f, base * CF(-W * 0.18 + 1.8, 5.0, -D / 2 - 1.2), Color3.fromRGB(255, 214, 150), 12, 0.8)
		elseif kind == 4 then -- a heavy bag under the carport: the neighbourhood's next prospect
			part(f, "YardBagFrame", V3(0.3, 7, 0.3), base * CF(W / 2 + 1.5, 3.5, D / 2 - 1), C.steel, M.Metal)
			part(f, "YardBagArm", V3(2.2, 0.3, 0.3), base * CF(W / 2 + 2.5, 6.9, D / 2 - 1), C.steel, M.Metal)
			cyl(f, "YardBag", 3.4, 1.5, base * CF(W / 2 + 3.4, 4.0, D / 2 - 1) * ANG(0, 0, RAD(90)), Color3.fromRGB(120, 26, 30), M.Leather)
		elseif kind == 5 then -- lawn sign cheering on the local fighter (CityVisuals writes your name on it)
			part(f, "LawnSignStake", V3(0.12, 2.2, 0.12), base * CF(W * 0.32, 1.1, -D / 2 - 5), C.wood, M.Wood)
			local ls = part(f, "LawnSign", V3(2.4, 1.4, 0.08), base * CF(W * 0.32, 2.4, -D / 2 - 5), C.white, M.SmoothPlastic)
			GymDecor.Sign(ls, Enum.NormalId.Front, "SUPPORT\nLOCAL BOXING", C.red, C.white, 40)
			ls:SetAttribute("Kind", "LawnSign")
			tag(ls, "CityScreen")
		else -- picket fence along the side yard
			part(f, "Fence", V3(0.25, 3, D + 4), base * CF(-W / 2 - 3, 1.5, 0), C.white, M.Wood, { collide = true })
			part(f, "FenceRail", V3(0.3, 0.3, D + 4), base * CF(-W / 2 - 3, 2.6, 0), C.white, M.Wood)
		end
	end
end

-- the empty lot on Oak Street that becomes YOUR house (CityVisuals builds it when you own a House)
local function homeLot(f, center, front)
	local base = CFrame.lookAt(center, center + front)
	part(f, "HomeLawn", V3(30, 0.15, 26), base * CF(0, 0.075, -1), Color3.fromRGB(84, 134, 66), M.Grass, { collide = true })
	part(f, "Driveway", V3(5, 0.18, 14), base * CF(10, 0.09, -11), Color3.fromRGB(150, 148, 144), M.Concrete, { collide = true })
	part(f, "LotPath", V3(2.4, 0.16, 9), base * CF(-3, 0.08, -10.5), Color3.fromRGB(180, 176, 168), M.Concrete)
	for _, x in ipairs({ -14.2, 14.2 }) do
		blob(f, "Hedge", V3(1.4, 2.4, 22), base * CF(x, 1.2, -1), Color3.fromRGB(50, 110, 55), M.Grass)
	end
	part(f, "SignPost", V3(0.25, 5, 0.25), base * CF(4, 2.5, -13.5), C.white, M.Wood)
	local rs = part(f, "RealtySign", V3(4, 2.6, 0.12), base * CF(4, 4.0, -13.5), Color3.fromRGB(180, 30, 36), M.SmoothPlastic)
	GymDecor.Sign(rs, Enum.NormalId.Front, "FOR SALE\nCITY REALTY\n$400,000", C.white, Color3.fromRGB(180, 30, 36), 40)
	rs:SetAttribute("Kind", "ForSale")
	rs:SetAttribute("Home", "House")
	tag(rs, "CityScreen")
	site("HomeHouse", base)
	promptPart(f, "HomePrompt", (base * CF(-3, 2.6, -6)).Position, "Enter house", "Oak Street", { Action = "Home", Kind = "House" }, Color3.fromRGB(255, 230, 170))
end

local function buildWest(root)
	local f = folder(root, "Residential")
	local rng = Random.new(808)
	local sx = -262
	slab(f, "OakStreet", sx - 7, sx + 7, -240, 167, 0.3, ASPHALT, M.Asphalt)
	for z = -230, 160, 12 do
		part(f, "LaneDash", V3(0.35, 0.03, 4), CF(sx, 0.315, z), C.white, M.SmoothPlastic)
	end
	slab(f, "Sidewalk", sx - 10, sx - 7, -240, 163, SW_H, SIDEWALK, M.Concrete)
	slab(f, "Sidewalk", sx + 7, sx + 10, -240, -41, SW_H, SIDEWALK, M.Concrete)
	slab(f, "Sidewalk", sx + 7, sx + 10, -29, 163, SW_H, SIDEWALK, M.Concrete)
	-- connector road from Oak Street to the loop's west side
	slab(f, "ConnectorRoad", sx + 7, -165, -41, -29, 0.3, ASPHALT, M.Asphalt)
	for x = -245, -175, 10 do
		part(f, "LaneDash", V3(4, 0.03, 0.35), CF(x, 0.315, -35), C.white, M.SmoothPlastic)
	end
	local i = 0
	for z = -200, 150, 50 do
		i += 1
		if z == 150 then
			homeLot(f, V3(sx + 25, 0, z), V3(-1, 0, 0))
		else
			house(f, V3(sx + 25, 0, z), V3(-1, 0, 0), rng, i)
		end
	end
	for z = -175, 125, 50 do
		i += 1
		house(f, V3(sx - 25, 0, z), V3(1, 0, 0), rng, i)
	end
	for k, z in ipairs({ -190, -110, -60, 10, 90, 140 }) do
		streetLight(f, V3(sx + 9.2, SW_H, z), V3(-1, 0, 0), k % 2 == 1)
	end
	-- Oak Street runs on north to the gates of Hillcrest Estates
	slab(f, "OakStreetN", sx - 7, sx + 7, -270, -240, 0.3, ASPHALT, M.Asphalt)
	slab(f, "SidewalkN", sx - 10, sx - 7, -268, -240, SW_H, SIDEWALK, M.Concrete)
	slab(f, "SidewalkN", sx + 7, sx + 10, -268, -240, SW_H, SIDEWALK, M.Concrete)
	local s = part(f, "StreetSign", V3(5, 1, 0.12), CF(sx + 9.4, 8.6, -44) * ANG(0, RAD(90), 0), Color3.fromRGB(30, 110, 60), M.SmoothPlastic)
	part(f, "StreetSignPole", V3(0.25, 9, 0.25), CF(sx + 9.4, 4.5 + SW_H, -44), C.steel, M.Metal)
	GymDecor.Sign(s, Enum.NormalId.Front, "OAK STREET", Color3.new(1, 1, 1), Color3.fromRGB(30, 110, 60), 40)
	GymDecor.Sign(s, Enum.NormalId.Back, "OAK STREET", Color3.new(1, 1, 1), Color3.fromRGB(30, 110, 60), 40)
end

------------------------------------------------------------------------
-- East: Riverside Park with a basketball court, fountain, paths, picnic tables and trees
------------------------------------------------------------------------
local function segDist(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function buildEast(root)
	local f = folder(root, "Park")
	local rng = Random.new(2024)
	-- basketball court with an apron and a chain-link fence (gate on the south side)
	local ct = V3(262, 0, -45)
	part(f, "CourtApron", V3(40, 0.2, 24), CF(ct + V3(0, 0.1, 0)), Color3.fromRGB(150, 150, 150), M.Concrete, { collide = true })
	part(f, "Court", V3(30, 0.25, 18), CF(ct + V3(0, 0.125, 0)), Color3.fromRGB(46, 92, 140), M.SmoothPlastic, { collide = true })
	local lines = part(f, "CourtLines", V3(30, 0.02, 18), CF(ct + V3(0, 0.26, 0)), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	local lg = gui(lines, Enum.NormalId.Top, 10, 1)
	local function box(xs, ys, w, h)
		local fr = frame(lg, { Size = UDim2.fromScale(w, h), Position = UDim2.fromScale(xs, ys), BackgroundTransparency = 1 })
		local st = Instance.new("UIStroke")
		st.Color = C.white
		st.Thickness = 3
		st.Parent = fr
		return fr
	end
	box(0.02, 0.03, 0.96, 0.94)
	box(0.5, 0.03, 0.0, 0.94)
	local circle = box(0.43, 0.38, 0.14, 0.24)
	Instance.new("UICorner", circle).CornerRadius = UDim.new(0.5, 0)
	box(0.02, 0.33, 0.18, 0.34)
	box(0.8, 0.33, 0.18, 0.34)
	for _, s in ipairs({ -1, 1 }) do
		local hx = ct.X + s * 16.5
		part(f, "HoopPole", V3(0.5, 10, 0.5), CF(hx, 5, ct.Z), C.steel, M.Metal, { collide = true })
		part(f, "HoopArm", V3(2, 0.4, 0.4), CF(hx - s * 1, 9.6, ct.Z), C.steel, M.Metal)
		part(f, "Backboard", V3(0.2, 3.2, 5.2), CF(hx - s * 2, 9.8, ct.Z), C.white, M.SmoothPlastic, { transparency = 0.15 })
		for k = 0, 7 do
			local a = k * RAD(45)
			part(f, "Rim", V3(0.12, 0.12, 0.62), CF(hx - s * 2.85 + math.cos(a) * 0.75, 8.9, ct.Z + math.sin(a) * 0.75) * ANG(0, -a, 0), Color3.fromRGB(240, 110, 30), M.Metal)
		end
	end
	local fenceColor = Color3.fromRGB(150, 155, 160)
	local function fence(cx, cz, sx, sz)
		part(f, "CourtFence", V3(sx, 6, sz), CF(ct + V3(cx, 3, cz)), fenceColor, M.DiamondPlate, { transparency = 0.75, shadow = false, collide = true })
	end
	fence(0, -11.6, 39.4, 0.15)
	fence(-11.3, 11.6, 16.8, 0.15)
	fence(11.3, 11.6, 16.8, 0.15)
	fence(-19.6, 0, 0.15, 23.4)
	fence(19.6, 0, 0.15, 23.4)
	ball(f, "Basketball", 1.0, CF(ct + V3(6, 0.75, 3)), Color3.fromRGB(230, 110, 30), M.Rubber)
	-- fountain plaza
	local fo = V3(290, 0, 60)
	part(f, "FountainPlaza", V3(34, 0.2, 34), CF(fo + V3(0, 0.1, 0)), Color3.fromRGB(196, 186, 170), M.Pavement, { collide = true })
	vcyl(f, "FountainBasin", 1.6, 18, CF(fo), Color3.fromRGB(170, 168, 162), M.Granite, { collide = true })
	vcyl(f, "FountainWater", 0.2, 16.6, CF(fo + V3(0, 1.45, 0)), Color3.fromRGB(70, 150, 210), M.Glass, { transparency = 0.25 })
	vcyl(f, "FountainPillar", 4.5, 2, CF(fo), Color3.fromRGB(180, 178, 172), M.Granite)
	vcyl(f, "FountainBowl", 0.8, 6.4, CF(fo + V3(0, 4.5, 0)), Color3.fromRGB(180, 178, 172), M.Granite)
	vcyl(f, "FountainBowlWater", 0.1, 5.8, CF(fo + V3(0, 5.25, 0)), Color3.fromRGB(80, 160, 220), M.Glass, { transparency = 0.2 })
	local jet = part(f, "FountainJet", V3(0.5, 0.5, 0.5), CF(fo + V3(0, 5.6, 0)), C.white, M.SmoothPlastic, { transparency = 1, shadow = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 40
	pe.Lifetime = NumberRange.new(0.9, 1.3)
	pe.Speed = NumberRange.new(10, 13)
	pe.SpreadAngle = Vector2.new(9, 9)
	pe.Acceleration = Vector3.new(0, -28, 0)
	pe.Size = NumberSequence.new(0.45, 0.2)
	pe.Transparency = NumberSequence.new(0.3, 0.8)
	pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	pe.LightEmission = 0.3
	pe.Parent = jet
	for k = 0, 5 do
		local a = k * RAD(60) + RAD(30)
		GymDecor.Bench(f, fo + V3(math.cos(a) * 14, 0.2, math.sin(a) * 14), RAD(90) - a, 5, C.wood)
	end
	-- paths: from the loop road, to Main Street, and down to the court gate
	local paths = {
		{ V3(165, 0, 60), V3(273, 0, 60) },
		{ V3(290, 0, 77), V3(290, 0, 163) },
		{ V3(284, 0, 44), V3(262, 0, -33) },
	}
	for _, seg in ipairs(paths) do
		local a, b = seg[1], seg[2]
		part(f, "ParkPath", V3(5, 0.14, (b - a).Magnitude), CFrame.lookAt((a + b) / 2 + V3(0, 0.07, 0), b + V3(0, 0.07, 0)), Color3.fromRGB(196, 176, 140), M.Pavement)
	end
	-- picnic tables and lamp posts
	local picnic = { V3(252, 0, 22), V3(322, 0, 28), V3(318, 0, 104), V3(256, 0, 104) }
	for k, p in ipairs(picnic) do
		picnicTable(f, p, RAD(k * 37))
	end
	for _, p in ipairs({ V3(222, 0, 64), V3(294, 0, 120), V3(277, 0, 10) }) do
		streetLight(f, p, V3(0, 0, -1), true)
	end
	-- trees anywhere else in the park
	local function clear(p)
		if (p - fo).Magnitude < 25 then
			return false
		end
		if math.abs(p.X - ct.X) < 27 and math.abs(p.Z - ct.Z) < 19 then
			return false
		end
		for _, seg in ipairs(paths) do
			if segDist(p, seg[1], seg[2]) < 8 then
				return false
			end
		end
		for _, q in ipairs(picnic) do
			if (p - q).Magnitude < 9 then
				return false
			end
		end
		return true
	end
	local n, tries = 0, 0
	while n < 34 and tries < 400 do
		tries += 1
		local p = V3(rng:NextNumber(234, 340), 0, rng:NextNumber(-220, 150))
		if clear(p) then
			n += 1
			if n % 2 == 0 then
				pine(f, p, rng:NextNumber(14, 22))
			else
				roundTree(f, p, rng:NextNumber(10, 15), rng)
			end
		end
	end
	local ps = part(f, "ParkSign", V3(10, 2.4, 0.4), CF(230, 4, 60) * ANG(0, RAD(90), 0), Color3.fromRGB(60, 40, 26), M.Wood)
	GymDecor.Sign(ps, Enum.NormalId.Back, "RIVERSIDE PARK", Color3.fromRGB(255, 230, 170), Color3.fromRGB(60, 40, 26), 30)
	GymDecor.Sign(ps, Enum.NormalId.Front, "RIVERSIDE PARK", Color3.fromRGB(255, 230, 170), Color3.fromRGB(60, 40, 26), 30)
	for _, dz in ipairs({ -4.5, 4.5 }) do
		part(f, "ParkSignPost", V3(0.4, 4, 0.4), CF(230, 2, 60 + dz), Color3.fromRGB(60, 40, 26), M.Wood)
	end
end

------------------------------------------------------------------------
-- North: the WCB Arena on the skyline
------------------------------------------------------------------------
local function buildArena(root)
	local f = folder(root, "Arena")
	local c = V3(0, 0, -322)
	local R, H = 62, 38
	local segs = 20
	for k = 0, segs - 1 do
		local a = (k + 0.5) / segs * math.pi * 2
		local dir = V3(math.sin(a), 0, math.cos(a))
		local pos = c + dir * R + V3(0, H / 2, 0)
		local w = 2 * R * math.sin(math.pi / segs) + 0.8
		local cf = CFrame.lookAt(pos, pos + dir)
		part(f, "ArenaWall", V3(w, H, 3), cf, Color3.fromRGB(56, 58, 66), M.Concrete, { collide = true })
		part(f, "ArenaGlass", V3(w, 8, 0.4), cf * CF(0, -H / 2 + 7, -1.6), Color3.fromRGB(120, 170, 220), M.Glass, { transparency = 0.15, reflect = 0.2 })
		part(f, "ArenaLED", V3(w, 1.2, 0.3), cf * CF(0, H / 2 - 2, -1.65), k % 2 == 0 and Color3.fromRGB(255, 40, 50) or C.gold, M.Neon, { shadow = false })
		part(f, "ArenaRib", V3(0.8, H - 4, 0.8), cf * CF(w / 2 - 0.4, -1, -1.8), Color3.fromRGB(80, 82, 90), M.Metal)
	end
	vcyl(f, "ArenaRoof", 2, 2 * R + 4, CF(c + V3(0, H, 0)), Color3.fromRGB(70, 72, 80), M.Metal)
	blob(f, "ArenaDome", V3(2 * R - 10, 22, 2 * R - 10), CF(c + V3(0, H + 2, 0)), Color3.fromRGB(205, 210, 218), M.Metal)
	-- flat entrance block facing the gym (south), with the big screen, canopy, doors and banners
	local FZ = -254 -- facade plane
	part(f, "EntranceBlock", V3(64, 30, 16), CF(0, 15, FZ - 8), Color3.fromRGB(40, 42, 50), M.Concrete, { collide = true })
	part(f, "EntranceTrim", V3(64.4, 1, 16.4), CF(0, 30.5, FZ - 8), Color3.fromRGB(190, 20, 30), M.SmoothPlastic)
	local screen = part(f, "ArenaScreen", V3(40, 14, 1), CF(0, 21.5, FZ + 0.5), Color3.fromRGB(8, 8, 12), M.SmoothPlastic)
	local sg = gui(screen, Enum.NormalId.Back, 8, 0, 2000)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 12) })
	frame(sg, { Size = UDim2.fromScale(1, 0.22), BackgroundColor3 = Color3.fromRGB(190, 20, 30) })
	label(sg, "WCB ARENA", { Name = "ScreenTop", TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.02) })
	label(sg, "FIGHT NIGHT", { Name = "ScreenHeadline", TextColor3 = C.gold, Size = UDim2.fromScale(0.9, 0.38), Position = UDim2.fromScale(0.05, 0.26) })
	label(sg, "SATURDAY  -  WORLD TITLE ON THE LINE", { Name = "ScreenSub", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.7) })
	-- CityVisuals puts your next fight / your title win on the big screen (text only, locally)
	screen:SetAttribute("Kind", "ArenaScreen")
	tag(screen, "CityScreen")
	site("FanArena", CFrame.lookAt(V3(0, 0.2, -236), V3(0, 0.2, -254)), { Len = 30, Rows = 2 })
	neonOutline(f, CF(0, 21.5, FZ + 1.1), 40.4, 14.4, Color3.fromRGB(255, 60, 70))
	part(f, "EntranceCanopy", V3(44, 1.2, 10), CF(0, 12, FZ + 5), Color3.fromRGB(30, 30, 34), M.Metal)
	for _, x in ipairs({ -20, 20 }) do
		part(f, "CanopyPost", V3(1, 11.4, 1), CF(x, 5.7, FZ + 9.5), Color3.fromRGB(30, 30, 34), M.Metal, { collide = true })
	end
	for k = 0, 3 do
		part(f, "ArenaDoor", V3(6, 9, 0.3), CF(-13.5 + k * 9, 5.3, FZ + 0.15), Color3.fromRGB(160, 200, 230), M.Glass, { transparency = 0.3 })
	end
	part(f, "ArenaSteps", V3(56, 0.8, 6), CF(0, 0.4, FZ + 3), Color3.fromRGB(150, 148, 144), M.Concrete, { collide = true })
	for i, x in ipairs({ -26, 26 }) do
		local b = part(f, "ArenaBanner", V3(4, 14, 0.2), CF(x, 18, FZ + 0.1), i == 1 and Color3.fromRGB(190, 20, 30) or Color3.fromRGB(20, 40, 120), M.Fabric)
		GymDecor.Sign(b, Enum.NormalId.Back, i == 1 and "LIVE\nFIGHTS" or "WCB\nARENA", Color3.new(1, 1, 1), nil, 20)
	end
	spot(emitter(f, CF(0, 11, FZ + 6)), Enum.NormalId.Bottom, Color3.fromRGB(255, 225, 180), 24, 1.6, 110)
	-- plaza, approach road from the loop, light towers and flags
	slab(f, "ArenaPlaza", -50, 50, -252, -212, 0.2, Color3.fromRGB(176, 170, 160), M.Pavement)
	slab(f, "ArenaWay", -8, 8, -212, -195, 0.3, ASPHALT, M.Asphalt)
	for _, x in ipairs({ -46, 46 }) do
		local tw = V3(x, 0, -230)
		part(f, "LightTower", V3(1.4, 40, 1.4), CF(tw + V3(0, 20, 0)), Color3.fromRGB(70, 72, 80), M.Metal, { collide = true })
		part(f, "TowerLights", V3(8, 3, 1), CFrame.lookAt(tw + V3(0, 40, 0), V3(0, 10, FZ)), Color3.fromRGB(255, 255, 235), M.Neon, { shadow = false })
	end
	for i, x in ipairs({ -36, -28, 28, 36 }) do
		local base = V3(x, 0.2, -216)
		vcyl(f, "FlagPole", 18, 0.3, CF(base), C.steelLight, M.Metal, { collide = true })
		part(f, "ArenaFlag", V3(0.08, 3, 5), CF(base + V3(0, 16, -2.6)), (i == 2 or i == 3) and C.gold or C.red, M.Fabric, { shadow = false })
	end
	-- parking on both sides with a few cars
	local rng = Random.new(77)
	for _, side in ipairs({ -1, 1 }) do
		local lot = V3(side * 96, 0, -292)
		part(f, "ArenaParking", V3(60, 0.2, 60), CF(lot + V3(0, 0.1, 0)), ASPHALT, M.Asphalt, { collide = true })
		for row = 0, 1 do
			local rz = lot.Z - 15 + row * 28
			for k = 0, 8 do
				part(f, "BayLine", V3(0.3, 0.03, 10), CF(lot.X - 24 + k * 6, 0.215, rz), C.white, M.SmoothPlastic)
				if k < 8 and rng:NextNumber() < 0.55 then
					car(f, CF(lot.X - 21 + k * 6, 0.2, rz) * ANG(0, RAD(row == 0 and 0 or 180), 0), CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)])
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- North-west: Hillcrest Estates, the gated plot at the top of Oak Street. Everyone sees the walls,
-- the gate, the gardens and the empty villa podium; a player who owns the Mansion sees their own
-- villa, pool and garage on it (CityVisuals) and the gate opens for them (locally).
------------------------------------------------------------------------
local ESTATE = { x0 = -328, x1 = -196, z0 = -374, z1 = -271, gateX = -262 }
CityMap.Estate = ESTATE

local function palm(parent, pos, h, rng)
	local lean = V3(rng:NextNumber(-0.18, 0.18), 1, rng:NextNumber(-0.18, 0.18))
	local p = pos
	for k = 0, 2 do
		local top = p + lean * (h / 3)
		GymDecor.Rod(parent, "PalmTrunk", p, top, 0.95 - k * 0.15, Color3.fromRGB(120, 96, 66), M.Wood)
		p = top
	end
	for k = 0, 5 do
		local a = k * RAD(60) + rng:NextNumber(-0.2, 0.2)
		blob(parent, "PalmFrond", V3(1.2, 0.35, 6), CF(p) * ANG(0, a, 0) * CF(0, -0.4, -2.6) * ANG(RAD(-22), 0, 0), Color3.fromRGB(48, 120, 52), M.Grass)
	end
	ball(parent, "Coconuts", 1.0, CF(p + V3(0, -0.6, 0)), Color3.fromRGB(90, 70, 40), M.Wood)
end

local function buildEstates(root)
	local f = folder(root, "Estates")
	local rng = Random.new(4242)
	local E = ESTATE
	local gx = E.gateX
	local brick = Color3.fromRGB(150, 128, 104)
	local stone = Color3.fromRGB(214, 206, 190)
	slab(f, "EstateLawn", E.x0, E.x1, E.z0, E.z1, 0.22, Color3.fromRGB(78, 132, 62), M.Grass)
	-- perimeter wall with stone pillars and coping; the gate gap in the south wall
	local function wall(x1, x2, z1, z2)
		local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
		local sx, sz = math.max(1.2, x2 - x1), math.max(1.2, z2 - z1)
		part(f, "EstateWall", V3(sx, 5, sz), CF(cx, 2.5, cz), brick, M.Brick, { collide = true })
		part(f, "WallCoping", V3(sx + 0.3, 0.35, sz + 0.3), CF(cx, 5.15, cz), stone, M.Limestone)
	end
	wall(E.x0, gx - 7, E.z1 - 0.6, E.z1 + 0.6)
	wall(gx + 7, E.x1, E.z1 - 0.6, E.z1 + 0.6)
	wall(E.x0, E.x1, E.z0 - 0.6, E.z0 + 0.6)
	wall(E.x0 - 0.6, E.x0 + 0.6, E.z0, E.z1)
	wall(E.x1 - 0.6, E.x1 + 0.6, E.z0, E.z1)
	for x = E.x0, E.x1, 23 do
		for _, z in ipairs({ E.z0, E.z1 }) do
			if math.abs(x - gx) > 9 then
				part(f, "WallPillar", V3(1.9, 6.4, 1.9), CF(x, 3.2, z), stone, M.Limestone, { collide = true })
			end
		end
	end
	-- gate: two pillars with lamps, two wrought-iron leaves (one Model each so CityVisuals can swing
	-- them open for the owner; the collider is the leaf's PrimaryPart)
	for _, sx in ipairs({ -1, 1 }) do
		local px = gx + sx * 7.8
		part(f, "GatePillar", V3(2.4, 8, 2.4), CF(px, 4, E.z1), stone, M.Limestone, { collide = true })
		ball(f, "GateLamp", 1.1, CF(px, 8.7, E.z1), Color3.fromRGB(255, 236, 200), M.Neon, { shadow = false })
		nightPoint(f, CF(px, 8.2, E.z1 + 1.5), Color3.fromRGB(255, 220, 170), 16, 1)
		local leaf = model(f, "GateLeaf")
		local hinge = gx + sx * 6.6
		local col = part(leaf, "GateCollider", V3(6.6, 7, 0.4), CF(gx + sx * 3.3, 3.5, E.z1), Color3.new(), M.SmoothPlastic, { transparency = 1, collide = true })
		leaf.PrimaryPart = col
		leaf:SetAttribute("Hinge", hinge)
		leaf:SetAttribute("Side", sx)
		for _, y in ipairs({ 0.6, 6.6 }) do
			part(leaf, "GateRail", V3(6.6, 0.25, 0.25), CF(gx + sx * 3.3, y, E.z1), Color3.fromRGB(26, 26, 28), M.Metal)
		end
		for k = 0, 6 do
			part(leaf, "GateBar", V3(0.18, 6.2 + (k % 2) * 0.6, 0.18), CF(gx + sx * (0.5 + k * 0.95), 3.6 + (k % 2) * 0.3, E.z1), Color3.fromRGB(26, 26, 28), M.Metal)
		end
		ball(leaf, "GateCrest", 0.9, CF(gx + sx * 3.3, 4.2, E.z1), C.gold, M.Metal)
	end
	local plaque = part(f, "EstatePlaque", V3(6, 1.6, 0.15), CF(gx - 13, 3.2, E.z1 + 0.68), Color3.fromRGB(40, 40, 44), M.Granite)
	GymDecor.Sign(plaque, Enum.NormalId.Back, "HILLCREST ESTATES", C.gold, Color3.fromRGB(40, 40, 44), 40, 0, Enum.Font.Garamond)
	local rs = part(f, "RealtySign", V3(4.6, 2.6, 0.12), CF(gx + 13, 3.6, E.z1 + 2.4), Color3.fromRGB(180, 30, 36), M.SmoothPlastic)
	part(f, "SignPost", V3(0.25, 3, 0.25), CF(gx + 13, 1.5, E.z1 + 2.4), C.white, M.Wood)
	GymDecor.Sign(rs, Enum.NormalId.Back, "HILLCREST MANSION\nFOR SALE  $5,000,000\nCITY REALTY", C.white, Color3.fromRGB(180, 30, 36), 40)
	rs:SetAttribute("Kind", "ForSale")
	rs:SetAttribute("Home", "Mansion")
	tag(rs, "CityScreen")
	-- gatehouse just inside
	local gh = CF(gx - 13, 0.22, E.z1 - 5)
	part(f, "Gatehouse", V3(5.5, 7.5, 5.5), gh * CF(0, 3.75, 0), stone, M.Limestone, { collide = true })
	part(f, "GatehouseRoof", V3(7, 0.6, 7), gh * CF(0, 7.8, 0), Color3.fromRGB(50, 50, 56), M.Slate)
	part(f, "GatehouseWindow", V3(3.6, 2.2, 0.1), gh * CF(0, 4.4, 2.8), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.3 })
	nightPoint(f, gh * CF(0, 6.6, 3.6), Color3.fromRGB(255, 225, 180), 12, 0.8)
	-- driveway to the forecourt, a fountain, the villa podium
	slab(f, "EstateDrive", gx - 4.5, gx + 4.5, -334, E.z1 - 0.6, 0.3, Color3.fromRGB(196, 188, 172), M.Pavement)
	slab(f, "Forecourt", gx - 24, gx + 24, -348, -334, 0.3, Color3.fromRGB(196, 188, 172), M.Pavement)
	local fo = V3(gx, 0.3, -341.5)
	vcyl(f, "FountainBasin", 1.4, 9, CF(fo), stone, M.Limestone, { collide = true })
	vcyl(f, "FountainWater", 0.15, 8, CF(fo + V3(0, 1.25, 0)), Color3.fromRGB(70, 150, 210), M.Glass, { transparency = 0.25 })
	vcyl(f, "FountainPillar", 3.4, 1.4, CF(fo), stone, M.Limestone)
	local jet = part(f, "FountainJet", V3(0.4, 0.4, 0.4), CF(fo + V3(0, 3.6, 0)), C.white, M.SmoothPlastic, { transparency = 1, shadow = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 18
	pe.Lifetime = NumberRange.new(0.8, 1.1)
	pe.Speed = NumberRange.new(7, 9)
	pe.SpreadAngle = Vector2.new(12, 12)
	pe.Acceleration = Vector3.new(0, -26, 0)
	pe.Size = NumberSequence.new(0.35, 0.15)
	pe.Transparency = NumberSequence.new(0.3, 0.85)
	pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	pe.Parent = jet
	part(f, "VillaPodium", V3(78, 0.8, 26), CF(gx, 0.4, -361), Color3.fromRGB(226, 220, 206), M.Limestone, { collide = true })
	part(f, "PodiumSteps", V3(16, 0.5, 2), CF(gx, 0.25, -347.4), Color3.fromRGB(226, 220, 206), M.Limestone, { collide = true })
	site("HomeMansion", CFrame.lookAt(V3(gx, 0.8, -361), V3(gx, 0.8, -300)))
	site("MansionPool", CFrame.lookAt(V3(-312, 0.22, -338), V3(-312, 0.22, -300)))
	site("MansionGarage", CFrame.lookAt(V3(-210, 0.22, -360), V3(-210, 0.22, -300)))
	site("EstateGate", CFrame.lookAt(V3(gx, 0.3, -262), V3(gx, 0.3, -300)))
	promptPart(f, "HomePrompt", V3(gx, 3.2, -346.2), "Enter mansion", "Hillcrest Estates", { Action = "Home", Kind = "Mansion" }, Color3.fromRGB(255, 220, 120))
	-- palms along the drive and round the forecourt, hedges inside the south wall, garden lamps
	for _, z in ipairs({ -280, -296, -312, -328 }) do
		for _, sx in ipairs({ -1, 1 }) do
			palm(f, V3(gx + sx * 8, 0.22, z), rng:NextNumber(13, 17), rng)
		end
	end
	for _, x in ipairs({ -320, -296, -228, -208 }) do
		blob(f, "Hedge", V3(14, 3, 2.4), CF(x, 1.5, E.z1 - 3), Color3.fromRGB(46, 104, 50), M.Grass)
	end
	for _, z in ipairs({ -288, -320 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local lp = V3(gx + sx * 5.5, 0.22, z)
			vcyl(f, "GardenLampPost", 4.2, 0.3, CF(lp), Color3.fromRGB(26, 26, 28), M.Metal)
			local lens = ball(f, "GardenLamp", 0.8, CF(lp + V3(0, 4.5, 0)), LENS_DAY, M.SmoothPlastic, { shadow = false })
			tag(lens, "NightLens")
			nightPoint(f, CF(lp + V3(0, 4.4, 0)), Color3.fromRGB(255, 220, 170), 14, 0.9)
		end
	end
	lightZone(f, "EstateZone", V3(E.x1 - E.x0, 40, E.z1 - E.z0), CF((E.x0 + E.x1) / 2, 20, (E.z0 + E.z1) / 2), "Mansion")
end

------------------------------------------------------------------------
-- North-east: the WCB Elite Performance Center (a bigger, newer gym across town). The shell is
-- shared; its roller shutters, lights and the elite decor open up for you (CityVisuals) once your
-- facility reaches the Elite tier (Catalog.GymTier index >= 3). Travel: Life tab / prompt.
------------------------------------------------------------------------
local ELITE = { x0 = 145, x1 = 225, z0 = -372, z1 = -322, h = 24 }
CityMap.EliteCenter = ELITE

local function buildEliteCenter(root)
	local f = folder(root, "EliteCenter")
	local E = ELITE
	local cx, cz = (E.x0 + E.x1) / 2, (E.z0 + E.z1) / 2
	local clad = Color3.fromRGB(44, 46, 52)
	local glassC = Color3.fromRGB(150, 190, 215)
	-- access road from the loop's north side, plaza with a sprint lane
	slab(f, "EliteRoad", 155, 165, -282, -195, 0.3, ASPHALT, M.Asphalt)
	for z = -275, -200, 10 do
		part(f, "LaneDash", V3(0.35, 0.03, 4), CF(160, 0.315, z), LINE_YELLOW, M.SmoothPlastic)
	end
	slab(f, "ElitePlaza", 138, 232, -322, -282, 0.25, Color3.fromRGB(190, 190, 194), M.Pavement)
	local lane = part(f, "SprintLane", V3(88, 0.06, 8), CF(185, 0.28, -292), Color3.fromRGB(170, 50, 44), M.Rubber)
	local lg = gui(lane, Enum.NormalId.Top, 4, 1, 200)
	for k = 1, 3 do
		frame(lg, { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, k / 4), BackgroundColor3 = C.white })
	end
	-- building: plinth, floor, solid back and sides, glass curtain wall on the south front
	part(f, "ElitePlinth", V3(E.x1 - E.x0 + 4, 0.6, E.z1 - E.z0 + 4), CF(cx, 0.3, cz), Color3.fromRGB(120, 120, 126), M.Concrete, { collide = true })
	part(f, "EliteFloor", V3(E.x1 - E.x0, 0.3, E.z1 - E.z0), CF(cx, 0.75, cz), Color3.fromRGB(58, 60, 66), M.Rubber, { collide = true })
	part(f, "EliteBackWall", V3(E.x1 - E.x0, E.h, 1.2), CF(cx, E.h / 2, E.z0), clad, M.Concrete, { collide = true })
	for _, x in ipairs({ E.x0, E.x1 }) do
		part(f, "EliteSideWall", V3(1.2, E.h, E.z1 - E.z0), CF(x, E.h / 2, cz), clad, M.Concrete, { collide = true })
	end
	part(f, "EliteRoof", V3(E.x1 - E.x0 + 3, 1.2, E.z1 - E.z0 + 5), CF(cx, E.h + 0.6, cz + 1), Color3.fromRGB(30, 32, 36), M.Metal, { collide = true })
	for k = 0, 6 do
		part(f, "RoofFin", V3(0.6, 2.4, E.z1 - E.z0 + 4), CF(E.x0 + 6 + k * (E.x1 - E.x0 - 12) / 6, E.h + 2.4, cz + 1), Color3.fromRGB(70, 72, 80), M.Metal)
	end
	-- glass front with mullions; the entrance gap holds the shutters
	local doorW = 14
	for _, sp in ipairs({ { E.x0, cx - doorW / 2 }, { cx + doorW / 2, E.x1 } }) do
		local w = sp[2] - sp[1]
		part(f, "EliteGlass", V3(w, E.h - 1, 0.3), CF((sp[1] + sp[2]) / 2, (E.h - 1) / 2 + 0.6, E.z1), glassC, M.Glass, { transparency = 0.35, reflect = 0.15, collide = true })
		for k = 0, math.floor(w / 6) do
			part(f, "EliteMullion", V3(0.35, E.h - 1, 0.5), CF(sp[1] + k * w / math.floor(w / 6), (E.h - 1) / 2 + 0.6, E.z1), Color3.fromRGB(26, 26, 30), M.Metal)
		end
	end
	part(f, "EliteTransom", V3(doorW + 1, E.h - 11, 0.8), CF(cx, 11 + (E.h - 11) / 2, E.z1), clad, M.Concrete, { collide = true })
	for _, sx in ipairs({ -1, 1 }) do
		local sh = part(f, "EliteShutter", V3(doorW / 2, 10.4, 0.4), CF(cx + sx * doorW / 4, 5.8, E.z1 + 0.2), Color3.fromRGB(150, 152, 158), M.DiamondPlate, { collide = true })
		local sg = gui(sh, Enum.NormalId.Back, 8, 0.6, 200)
		for k = 0, 9 do
			frame(sg, { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, k / 10), BackgroundColor3 = Color3.fromRGB(90, 92, 98) })
		end
	end
	part(f, "EliteCanopy", V3(doorW + 10, 0.6, 7), CF(cx, 11.6, E.z1 + 3.6), Color3.fromRGB(26, 26, 30), M.Metal)
	local band = part(f, "EliteSign", V3(46, 3.2, 0.4), CF(cx, E.h - 3, E.z1 + 0.5), Color3.fromRGB(16, 16, 20), M.SmoothPlastic)
	local bsg = gui(band, Enum.NormalId.Back, 12, 0, 1200)
	frame(bsg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(16, 16, 20) })
	label(bsg, "WCB ELITE PERFORMANCE CENTER", { Name = "SignText", TextColor3 = Color3.fromRGB(120, 128, 140), Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15), Font = Enum.Font.Michroma })
	-- inside: glass partitions with doorways split recovery / motion capture / sports science
	for _, px in ipairs({ E.x0 + 27, E.x1 - 27 }) do
		for _, sp in ipairs({ { E.z0 + 1, cz - 4 }, { cz + 4, E.z1 - 1 } }) do
			part(f, "ElitePartition", V3(0.3, 12, sp[2] - sp[1]), CF(px, 6.9, (sp[1] + sp[2]) / 2), Color3.fromRGB(200, 220, 235), M.Glass, { transparency = 0.55, collide = true })
		end
	end
	-- ceiling lights stay off for everyone; the client turns them on for an unlocked facility
	for _, x in ipairs({ E.x0 + 13, cx, E.x1 - 13 }) do
		for _, z in ipairs({ cz - 10, cz + 10 }) do
			local fix = part(f, "EliteLightPanel", V3(8, 0.2, 2.4), CF(x, E.h - 0.2, z), Color3.fromRGB(230, 236, 246), M.SmoothPlastic, { shadow = false })
			local l = spot(fix, Enum.NormalId.Bottom, Color3.fromRGB(228, 238, 255), 32, 1.5, 120)
			l.Name = "EliteCenterLight"
			l.Enabled = false
		end
	end
	lightZone(f, "EliteZone", V3(E.x1 - E.x0, E.h, E.z1 - E.z0), CF(cx, E.h / 2, cz), "GymElite")
	site("EliteCenter", CFrame.lookAt(V3(cx, 0.9, E.z1 - 8), V3(cx, 0.9, E.z0)))
	site("EliteEntrance", CFrame.lookAt(V3(cx, 0.25, E.z1 + 8), V3(cx, 0.25, E.z1)))
	site("EliteRecovery", CFrame.lookAt(V3(E.x0 + 13.5, 0.9, cz), V3(E.x0 + 13.5, 0.9, E.z1)))
	site("EliteMocap", CFrame.lookAt(V3(cx, 0.9, cz - 3), V3(cx, 0.9, E.z1)))
	site("EliteLab", CFrame.lookAt(V3(E.x1 - 13.5, 0.9, cz), V3(E.x1 - 13.5, 0.9, E.z1)))
	promptPart(f, "ElitePrompt", V3(cx - doorW / 2 - 3, 3.0, E.z1 + 3), "Elite Performance Center", "Facility tier", { Action = "EliteCenter" }, Color3.fromRGB(150, 220, 255))
	for _, x in ipairs({ 150, 220 }) do
		streetLight(f, V3(x, 0.25, -284), V3(0, 0, -1), true)
	end
end

------------------------------------------------------------------------
-- Billboards around town: generic ads for everyone, your sponsors / fight promos for you
------------------------------------------------------------------------
local function buildBillboards(root)
	local f = folder(root, "Billboards")
	local list = {
		{ "Champion", CFrame.lookAt(V3(-17, 9.5, 145), V3(0, 9.5, 145)), 12, 7, ADS[3] },
		{ "Cafe", CFrame.lookAt(V3(-148, 40.5, 208), V3(-148, 40.5, 100)), 22, 9, ADS[1], 2 },
		{ "Apartments", CFrame.lookAt(V3(118, 48.5, 212), V3(118, 48.5, 100)), 22, 9, ADS[2], 2 },
		{ "Loop", CFrame.lookAt(V3(177, 10, -60), V3(150, 10, -60)), 14, 8, ADS[4] },
		{ "ArenaW", CFrame.lookAt(V3(-42, 11, -206), V3(-42, 11, -150)), 16, 8, ADS[3] },
		{ "ArenaE", CFrame.lookAt(V3(42, 11, -206), V3(42, 11, -150)), 16, 8, ADS[5] },
	}
	for _, b in ipairs(list) do
		billboard(f, b[2], b[3], b[4], b[1], b[5], b[6])
	end
end

------------------------------------------------------------------------
-- Far away: the mountain training camp (Mountain / Elite Camp owners can travel here during a
-- camp; CityVisuals tints the local atmosphere while you are inside the pod)
------------------------------------------------------------------------
local CAMP = V3(-3000, 0, 3000)
CityMap.CampCenter = CAMP

local function buildCamp(root)
	local f = folder(root, "TrainingCamp")
	local rng = Random.new(1985)
	local snow = Color3.fromRGB(236, 240, 246)
	part(f, "CampGround", V3(320, 2, 320), CF(CAMP + V3(0, -1, 0)), snow, M.Snow, { collide = true })
	-- (a sphere mesh collides as its box: the hill is scenery only)
	blob(f, "CampHill", V3(140, 46, 90), CF(CAMP + V3(0, -6, -120)), snow, M.Snow)
	-- log cabin with porch, chimney smoke and a warm window
	local cab = CF(CAMP + V3(0, 0, -20))
	part(f, "Cabin", V3(26, 11, 16), cab * CF(0, 5.5, 0), Color3.fromRGB(110, 74, 46), M.WoodPlanks, { collide = true })
	local a = (cab * CF(0, 13, -4)).Position
	local b = (cab * CF(0, 13, 4)).Position
	part(f, "CabinRoof", V3(28, 4, 9), CFrame.lookAt(a, a + V3(0, 0, -1)), Color3.fromRGB(240, 244, 250), M.Snow, { class = "WedgePart", collide = true })
	part(f, "CabinRoof", V3(28, 4, 9), CFrame.lookAt(b, b + V3(0, 0, 1)), Color3.fromRGB(240, 244, 250), M.Snow, { class = "WedgePart", collide = true })
	local chim = part(f, "Chimney", V3(2.4, 6, 2.4), cab * CF(8, 13, 3), Color3.fromRGB(110, 106, 100), M.Cobblestone)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 5
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Speed = NumberRange.new(2, 3)
	smoke.Size = NumberSequence.new(1.5, 5)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205))
	smoke.Parent = chim
	part(f, "CabinPorch", V3(14, 0.6, 5), cab * CF(0, 0.3, -10.5), Color3.fromRGB(90, 60, 38), M.WoodPlanks, { collide = true })
	part(f, "CabinDoor", V3(3, 6.5, 0.2), cab * CF(0, 3.5, -8.1), Color3.fromRGB(70, 46, 30), M.Wood)
	local win = part(f, "CabinWindow", V3(4, 3, 0.15), cab * CF(-7, 5.5, -8.08), Color3.fromRGB(255, 200, 120), M.Neon, { transparency = 0.2, shadow = false })
	point(win, Color3.fromRGB(255, 190, 120), 14, 0.9)
	-- the Rocky corner: log pile, chopping block and axe, a heavy bag on a frame, campfire
	for k = 0, 4 do
		cyl(f, "Log", 6, 1.2, cab * CF(-16, 0.6 + math.floor(k / 3) * 1.1, -2 + (k % 3) * 1.25), Color3.fromRGB(120, 84, 52), M.Wood)
	end
	vcyl(f, "ChopBlock", 2, 2.2, cab * CF(-15, 0, -8), Color3.fromRGB(130, 92, 58), M.Wood, { collide = true })
	part(f, "AxeHandle", V3(0.25, 3, 0.25), cab * CF(-15, 2.8, -8) * ANG(0, 0, RAD(25)), Color3.fromRGB(150, 110, 70), M.Wood)
	part(f, "AxeHead", V3(0.9, 0.5, 0.15), cab * CF(-14.5, 2.2, -8) * ANG(0, 0, RAD(25)), C.steelLight, M.Metal)
	local bagCF = cab * CF(14, 0, -14)
	for _, x in ipairs({ -2.5, 2.5 }) do
		part(f, "BagFramePost", V3(0.6, 9, 0.6), bagCF * CF(x, 4.5, 0), Color3.fromRGB(100, 70, 44), M.Wood, { collide = true })
	end
	part(f, "BagFrameBeam", V3(6, 0.6, 0.6), bagCF * CF(0, 9, 0), Color3.fromRGB(100, 70, 44), M.Wood)
	vcyl(f, "CampBag", 4.4, 1.9, bagCF * CF(0, 2.6, 0), Color3.fromRGB(110, 70, 40), M.Leather, { collide = true })
	local fire = CF(CAMP + V3(0, 0, -2))
	for k = 0, 2 do
		cyl(f, "FireLog", 3, 0.5, fire * ANG(0, RAD(k * 60), 0) * CF(0, 0.3, 0), Color3.fromRGB(70, 48, 30), M.Wood)
	end
	local flame = part(f, "Campfire", V3(0.6, 0.6, 0.6), fire * CF(0, 0.8, 0), Color3.fromRGB(255, 140, 40), M.Neon, { transparency = 1, shadow = false })
	local fe = Instance.new("ParticleEmitter")
	fe.Rate = 16
	fe.Lifetime = NumberRange.new(0.5, 0.9)
	fe.Speed = NumberRange.new(2, 4)
	fe.Size = NumberSequence.new(1.0, 0.1)
	fe.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20))
	fe.LightEmission = 0.8
	fe.Parent = flame
	point(flame, Color3.fromRGB(255, 150, 70), 18, 1.4)
	-- pines all round, the camp sign, prompts
	local n = 0
	while n < 16 do
		local p = CAMP + V3(rng:NextNumber(-140, 140), 0, rng:NextNumber(-110, 140))
		if (p - CAMP).Magnitude > 38 then
			n += 1
			pine(f, p, rng:NextNumber(16, 26))
		end
	end
	local sg = part(f, "CampSign", V3(12, 2.6, 0.4), CF(CAMP + V3(0, 4.4, 30)), Color3.fromRGB(70, 46, 30), M.Wood)
	GymDecor.Sign(sg, Enum.NormalId.Back, "SUMMIT TRAINING CAMP", Color3.fromRGB(255, 230, 170), Color3.fromRGB(70, 46, 30), 30)
	GymDecor.Sign(sg, Enum.NormalId.Front, "SUMMIT TRAINING CAMP", Color3.fromRGB(255, 230, 170), Color3.fromRGB(70, 46, 30), 30)
	for _, x in ipairs({ -5.5, 5.5 }) do
		part(f, "CampSignPost", V3(0.5, 4.4, 0.5), CF(CAMP + V3(x, 2.2, 30)), Color3.fromRGB(70, 46, 30), M.Wood)
	end
	site("Camp", CFrame.lookAt(CAMP + V3(0, 0, 18), CAMP + V3(0, 0, -20)))
	promptPart(f, "SleepPrompt", (cab * CF(3, 2.6, -11)).Position, "Sleep in the cabin", "Training camp", { Action = "Sleep" }, Color3.fromRGB(170, 170, 255))
	promptPart(f, "LeavePrompt", CAMP + V3(0, 2.6, 24), "Back to the city", "Training camp", { Action = "LeaveCamp" }, Color3.fromRGB(255, 220, 120))
end

------------------------------------------------------------------------
-- Skyline around the edges of the map
------------------------------------------------------------------------
local function buildSkyline(root)
	local f = folder(root, "Skyline")
	local rng = Random.new(31337)
	local center = V3(0, 0, -30)
	local function tower(pos, w, d, h)
		local look = V3(center.X - pos.X, 0, center.Z - pos.Z).Unit
		local cf = CFrame.lookAt(pos + V3(0, h / 2, 0), pos + V3(0, h / 2, 0) + look)
		local tone = rng:NextInteger(0, 3)
		local color = ({ Color3.fromRGB(70, 78, 92), Color3.fromRGB(110, 112, 120), Color3.fromRGB(56, 70, 90), Color3.fromRGB(150, 140, 126) })[tone + 1]
		local body = part(f, "Tower", V3(w, h, d), cf, color, tone == 2 and M.Glass or M.Concrete, { reflect = tone == 2 and 0.15 or 0 })
		windowGrid(body, Enum.NormalId.Front, h, 4, h - 3, math.floor(h / 10), math.max(3, math.floor(w / 6)), rng, 0.3)
		part(f, "TowerCap", V3(w * 0.6, 3, d * 0.6), cf * CF(0, h / 2 + 1.5, 0), color:Lerp(Color3.new(0, 0, 0), 0.2), M.Concrete)
		if h > 110 then
			part(f, "Antenna", V3(0.6, 18, 0.6), cf * CF(0, h / 2 + 12, 0), C.steelLight, M.Metal)
			ball(f, "AntennaLight", 1.2, cf * CF(0, h / 2 + 21.5, 0), Color3.fromRGB(255, 40, 40), M.Neon, { shadow = false })
		end
	end
	for x = -340, 340, 56 do
		if math.abs(x) > 80 then
			tower(V3(x + rng:NextNumber(-8, 8), 0, -396), rng:NextInteger(26, 40), 20, rng:NextInteger(70, 170))
		end
		tower(V3(x + rng:NextNumber(-8, 8), 0, 334), rng:NextInteger(24, 38), 20, rng:NextInteger(60, 150))
	end
	for z = -300, 260, 70 do
		tower(V3(364, 0, z + rng:NextNumber(-10, 10)), 20, rng:NextInteger(26, 40), rng:NextInteger(60, 160))
		tower(V3(-364, 0, z + rng:NextNumber(-10, 10)), 20, rng:NextInteger(26, 40), rng:NextInteger(60, 160))
	end
end

------------------------------------------------------------------------
-- Home interiors. Per player and server-built (a teleported character must land on real
-- collision), far outside the map, built on demand when the player travels home and furnished
-- from the profile: home kind, add-ons (Home Gym, Trophy Room, Recovery Suite, Pool Deck), belts,
-- fight posters from the history, the record on the TV. Rebuilt only when that signature changes;
-- released when the player leaves. Every home: Sleep prompt by the bed, Exit prompt by the door.
------------------------------------------------------------------------
local homesFolder
local homeSlots = {} -- slot index -> player
local homes = {} -- player -> { model, kind, sig, spawn, slot }

local HOME_SPEC = {
	Apartment = { w = 46, d = 30, h = 13, zone = "Apartment", floor = Color3.fromRGB(150, 112, 78), floorMat = M.WoodPlanks,
		wall = Color3.fromRGB(226, 222, 214), view = "city", sheet = Color3.fromRGB(60, 70, 90), sofa = Color3.fromRGB(70, 72, 80), lights = 3 },
	House = { w = 58, d = 38, h = 14, zone = "Apartment", floor = Color3.fromRGB(170, 132, 92), floorMat = M.WoodPlanks,
		wall = Color3.fromRGB(236, 230, 218), view = "suburb", sheet = Color3.fromRGB(150, 60, 50), sofa = Color3.fromRGB(110, 86, 64), lights = 4 },
	Mansion = { w = 96, d = 60, h = 20, zone = "Mansion", floor = Color3.fromRGB(236, 232, 224), floorMat = M.Marble,
		wall = Color3.fromRGB(246, 244, 238), view = "coast", sheet = Color3.fromRGB(240, 236, 226), sofa = Color3.fromRGB(240, 236, 226), lights = 6 },
}
CityMap.HomeSpec = HOME_SPEC

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
CityMap.HomeKind = homeKindFor

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
	-- skirting and soft ceiling light
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

-- a belt laid on a shelf / pedestal: strap, centre plate, two side plates
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
		-- a proper home ring: platform, padded posts, three ropes a side
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
	-- the picture is on the +Z face (Back), towards the sofa and the door side of the room
	local sg = gui(scr, Enum.NormalId.Back, 30, 0, 120)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 16, 26) })
	frame(sg, { Size = UDim2.fromScale(1, 0.18), BackgroundColor3 = Color3.fromRGB(190, 20, 30) })
	label(sg, "WCB SPORTS  -  LIVE", { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.9, 0.14), Position = UDim2.fromScale(0.05, 0.02) })
	local id = type(profile.identity) == "table" and profile.identity or {}
	local r = profile.tier == 1 and profile.amateurRecord or profile.record
	r = type(r) == "table" and r or { w = 0, l = 0, d = 0, ko = 0 }
	label(sg, string.format("%s \"%s\"", tostring(id.name or ""), tostring(id.nickname or "")), { TextColor3 = C.gold, Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.24) })
	local tier = Config.Tiers[profile.tier]
	label(sg, string.format("%s  -  %d-%d-%d (%d KO)", tier and tier.name or "", r.w or 0, r.l or 0, r.d or 0, r.ko or 0), { TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.46) })
	local nextLine = "NEXT FIGHT: TO BE ANNOUNCED"
	local camp = profile.camp
	if type(camp) == "table" and type(camp.offer) == "table" and type(camp.offer.opp) == "table" then
		nextLine = string.format("NEXT: vs %s  -  %d DAYS", tostring(camp.offer.opp.name or "?"):upper(), tonumber(camp.daysLeft) or 0)
	end
	label(sg, nextLine, { TextColor3 = Color3.fromRGB(150, 210, 255), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.64) })
	label(sg, "FANS: " .. tostring(math.floor((profile.popularity or 0) ^ 2 * 950 + (r.w or 0) * 120)), { TextColor3 = Color3.fromRGB(200, 200, 210), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.82) })
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = Color3.fromRGB(150, 180, 255), 10, 0.6, false
	glow.Parent = scr
end

local function outsideDeck(f, base, spec, pool)
	-- terrace / pool deck between the glass and the view (seen through the window wall)
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
	-- bed (Sleep prompt), the lounge with the TV, the kitchen, a rug, plants
	local bedCF = base * CF(w / 2 - (kind == "Mansion" and 14 or 9), 0, d / 2 - 5.6)
	local bw = kind == "Mansion" and 9 or 7
	bed(f, bedCF, bw, 10, spec.sheet)
	promptPart(f, "SleepPrompt", (bedCF * CF(-bw / 2 - 2.5, 2.6, -2)).Position, "Sleep (End Day)", "Home sweet home", { Action = "Sleep" }, Color3.fromRGB(170, 170, 255))
	local lounge = base * CF(-w * 0.12, 0, -d * 0.12)
	part(f, "Rug", V3(14, 0.06, 10), lounge * CF(0, 0.03, 0), kind == "Mansion" and Color3.fromRGB(150, 120, 80) or Color3.fromRGB(120, 60, 50), M.Fabric)
	-- the sofa's seat faces its local -Z (back at +Z), i.e. towards the TV wall at lounge z -4.2
	sofa(f, lounge * CF(0, 0, 4), kind == "Apartment" and 9 or 12, spec.sofa)
	part(f, "CoffeeTable", V3(5, 1.4, 2.6), lounge * CF(0, 0.7, 0.4), Color3.fromRGB(46, 36, 28), M.Wood, { collide = true })
	tvWall(f, lounge * CF(0, 0, -4.2), kind == "Mansion" and 12 or 9, profile)
	local kLen = kind == "Apartment" and 10 or 14
	kitchen(f, base * CF(-w / 2 + kLen / 2 + 4.5, 0, d / 2 - 1.6) * ANG(0, RAD(180), 0), kLen,
		kind == "Mansion" and Color3.fromRGB(30, 30, 34) or Color3.fromRGB(236, 236, 232), kind == "Mansion" and Color3.fromRGB(240, 240, 236) or Color3.fromRGB(60, 60, 64))
	for _, p in ipairs({ { -w / 2 + 2.5, -d / 2 + 2.5 }, { w / 2 - 2.5, -d / 2 + 2.5 } }) do
		GymDecor.Plant(f, (base * CF(p[1], 0, p[2])).Position, 1)
	end
	-- the door you came in by (Exit prompt) on the left wall, near the kitchen
	local doorCF = base * CF(-w / 2 + 0.05, 0, d / 2 - 12) * ANG(0, RAD(90), 0)
	part(f, "FrontDoor", V3(4, 8, 0.2), doorCF * CF(0, 4, 0), Color3.fromRGB(60, 40, 28), M.Wood)
	part(f, "DoorHandle", V3(0.2, 0.2, 0.5), doorCF * CF(1.4, 3.8, 0.2), C.gold, M.Metal)
	promptPart(f, "ExitPrompt", (doorCF * CF(0, 2.6, 2.5)).Position, "Go outside", kind, { Action = "LeaveHome" }, Color3.fromRGB(255, 230, 170))
	-- fight posters from the history (newest first) along the back wall
	local nPosters = kind == "Apartment" and 2 or (kind == "House" and 3 or 4)
	local posterY = kind == "Mansion" and 5 or h * 0.45
	for k = 0, nPosters - 1 do
		local e = hist[#hist - k]
		if type(e) == "table" then
			fightPoster(f, base * CF(-2 - (nPosters - 1) * 2.2 + k * 4.4, posterY, d / 2 - 0.1), e, surname)
		end
	end
	-- belts on a lit wall shelf (or the Trophy Room below)
	if #belts > 0 and not owned.TrophyRoom then
		local shelf = base * CF(w / 2 - 0.4, h * 0.42, -d * 0.1) * ANG(0, RAD(90), 0)
		part(f, "BeltShelf", V3(#belts * 4 + 1, 0.3, 1.4), shelf * CF(0, -0.6, -0.3), Color3.fromRGB(40, 30, 24), M.Wood)
		for i, b in ipairs(belts) do
			belt(f, shelf * CF(-(#belts - 1) * 2 + (i - 1) * 4, 0.3, -0.4), b)
		end
		spot(emitter(f, shelf * CF(0, 3, -2)), Enum.NormalId.Bottom, Color3.fromRGB(255, 230, 180), 10, 1.2, 70)
	end
	-- add-ons
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
		-- pedestals under spotlights: every belt, then trophies for the title wins
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
		-- the grand hall: chandelier, double staircase to a mezzanine, a cinema corner
		local ch = base * CF(0, h - 3.5, 0)
		ball(f, "ChandelierCore", 1.4, ch, Color3.fromRGB(255, 236, 190), M.Neon, { shadow = false })
		for k = 0, 9 do
			local a = k * math.pi / 5
			ball(f, "ChandelierCrystal", 0.6, ch * CF(math.cos(a) * 2.6, -0.6 - (k % 2) * 0.5, math.sin(a) * 2.6), Color3.fromRGB(240, 246, 255), M.Glass, { transparency = 0.2, reflect = 0.3 })
		end
		point(emitter(f, ch * CF(0, -1, 0)), Color3.fromRGB(255, 228, 190), 34, 1.2)
		-- the left flight stands 12 studs in from the wall so the front door, the Exit prompt and the
		-- arrival spot (all on the left wall at z d/2 - 12) stay clear underneath it
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
	-- the family photo wall: your first fight, framed
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
CityMap.ReleaseHome = releaseHome
Players.PlayerRemoving:Connect(releaseHome)

-- builds (or reuses) the player's interior and returns the spawn CFrame inside the front door
function CityMap.EnterHome(player, profile, kind)
	kind = homeKindFor(profile, kind)
	if not kind then
		return nil, "You don't own a home yet. Buy one in the Shop (Houses)."
	end
	if not homesFolder then
		return nil, "The city isn't ready."
	end
	local h = homes[player]
	local sig = homeSig(profile, kind)
	if h and h.sig == sig and h.model and h.model.Parent then
		return h.spawn, kind
	end
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
		warn("[CityMap] furnishing failed: " .. tostring(err))
	end
	m.Parent = homesFolder
	local spawnCF = CFrame.lookAt((base * CF(-spec.w / 2 + 4, 3.2, spec.d / 2 - 12)).Position, (base * CF(0, 3.2, 0)).Position)
	homes[player] = { model = m, kind = kind, sig = sig, spawn = spawnCF, slot = slot }
	return spawnCF, kind
end

-- where to stand outside a home (in front of its door / gate)
function CityMap.HomeExit(profile, kind)
	kind = homeKindFor(profile, kind) or kind
	local sitesCF = kind and CityMap.Sites["Home" .. kind]
	if not sitesCF then
		return nil
	end
	if kind == "Mansion" then
		return sitesCF * CF(0, 3.2, -14)
	elseif kind == "House" then
		return sitesCF * CF(-3, 3.2, -10.5)
	end
	return sitesCF * CF(0, 3.2, -1.5)
end

-- server travel targets (Main's travel handlers): where = home | outside | elite | city | estate | camp
-- -> CFrame or nil, error text
function CityMap.TravelCFrame(player, profile, where, kind)
	if where == "home" then
		return CityMap.EnterHome(player, profile, kind)
	elseif where == "outside" then
		local h = homes[player]
		local cf = CityMap.HomeExit(profile, kind or (h and h.kind))
		if not cf then
			return nil, "You don't own a home yet."
		end
		return cf
	elseif where == "elite" then
		local ok, idx = pcall(Catalog.GymTier, profile.gym and profile.gym.levels, profile.owned, profile.tier)
		if not ok or (tonumber(idx) or 1) < 3 then
			return nil, "The Elite Performance Center opens when your gym reaches the Elite tier (Gym tab)."
		end
		local s = CityMap.Sites.EliteCenter
		return s and s * CF(0, 3.2, 0) or nil, s and "elite" or "Not built"
	elseif where == "city" then
		return CF(0, SW_H + 3.2, 185) * ANG(0, RAD(180), 0)
	elseif where == "estate" then
		local s = CityMap.Sites.EstateGate
		return s and s * CF(0, 3.2, 0) or nil
	elseif where == "camp" then
		local owned = type(profile.owned) == "table" and profile.owned or {}
		if not profile.camp then
			return nil, "You can only go to camp during a fight camp."
		end
		if not (owned.MountainCamp or owned.EliteCamp) then
			return nil, "Buy the Mountain or Elite Training Camp in the Shop first."
		end
		local s = CityMap.Sites.Camp
		return s and s * CF(0, 3.2, 0) or nil
	end
	return nil, "Unknown place"
end

------------------------------------------------------------------------
-- MapBuilder scatters trees around the loop; drop those standing where the town now is.
-- A tree's trunk and leaves share one XZ position, so both go together.
------------------------------------------------------------------------
local TREE_CLEAR = {
	{ -22, 22, 120, 170 }, -- Champion Ave, its sidewalks and the avenue billboard
	{ 150, 175, -282, -195 }, -- Elite Performance Center access road
	{ 170, 190, -72, -48 }, -- loop billboard
	{ -276, -248, -272, -236 }, -- Oak Street north end (Hillcrest gate)
	{ -52, -28, 120, 140 }, -- bus stop
	{ -260, -160, -48, -22 }, -- Oak Street connector road
	{ -58, 58, -265, -195 }, -- arena approach and plaza
	{ 160, 236, 52, 68 }, -- park path from the loop
	{ -127, -113, 120, 135 }, { -67, -53, 120, 135 }, { 53, 67, 120, 135 }, { 113, 127, 120, 135 }, -- south loop lights
	{ 160, 196, 120, 136 }, { -196, -160, 120, 136 }, -- south corner lights
}

local function clearTrees(gym)
	local removed = 0
	for _, child in ipairs(gym:GetChildren()) do
		if child:IsA("BasePart") and (child.Name == "Trunk" or child.Name == "Leaves") then
			local p = child.Position
			for _, z in ipairs(TREE_CLEAR) do
				if p.X > z[1] and p.X < z[2] and p.Z > z[3] and p.Z < z[4] then
					child:Destroy()
					removed += 1
					break
				end
			end
		end
	end
	return removed
end

------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------
function CityMap.Build(gym)
	local root = Instance.new("Folder")
	root.Name = "City"
	root.Parent = gym
	sitesFolder = folder(root, "Sites")
	homesFolder = folder(root, "Homes")
	local sections = {
		{ "trees", function()
			clearTrees(gym)
		end },
		{ "campus", buildCampus }, { "south", buildSouth }, { "west", buildWest }, { "east", buildEast },
		{ "arena", buildArena }, { "estates", buildEstates }, { "elite", buildEliteCenter },
		{ "billboards", buildBillboards }, { "camp", buildCamp }, { "skyline", buildSkyline },
	}
	for _, s in ipairs(sections) do
		local ok, err = pcall(s[2], root)
		if not ok then
			warn("[CityMap] " .. s[1] .. " failed: " .. tostring(err))
		end
	end
	return root
end

return CityMap
