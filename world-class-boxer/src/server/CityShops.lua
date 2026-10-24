-- CityShops: the Main Street shop fronts and their walk-in interiors (barbershop, diner, supplements,
-- pro shop, museum, car dealer), the apartments, the gas station - built in a ROW FRAME: x along the
-- street, y up, z back into the block from the front face (z 0 = the shop fronts, the sidewalk is at
-- z < 0). CityShops.BuildRow places a row with any CFrame, so the same builders make the south row
-- (facing north, towards the gym) and the north row (facing south). Scale: ground floor 14 studs
-- (3.9 m), storeys 11.4, doors 2.1 m, counters 0.9 m (Config.City).
-- Prompts: attribute Action on the ProximityPrompt (client CityVisuals / ClientMain dispatch);
-- sites: Window_<shop> (sponsor standees), ApartmentRoof / ApartmentBanner / HomeApartment /
-- ApartmentKerb, MuseumExhibit / MuseumBanner, Window_FUELGO.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GymDecor = require(script.Parent:WaitForChild("GymDecor"))
local K = require(script.Parent:WaitForChild("CityKit"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local CityProps = require(Shared:WaitForChild("CityProps"))
local Signage = require(Shared:WaitForChild("Signage"))

local CityShops = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material
local C = K.C
local CITY = K.CITY
local SW_H = K.SW_H
local G, S = CITY.GroundFloor, CITY.Storey
local label, frame, gui = K.label, K.frame, K.gui
local tag = K.tag

------------------------------------------------------------------------
-- the row frame
------------------------------------------------------------------------
local ROW = CF()
local ROW_YAW = 0
local function part(parent, name, size, cf, color, material, opts)
	return K.part(parent, name, size, ROW * cf, color, material, opts)
end
local function cyl(parent, name, len, dia, cf, color, material, opts)
	return K.cyl(parent, name, len, dia, ROW * cf, color, material, opts)
end
local function vcyl(parent, name, h, dia, base, color, material, opts)
	return K.vcyl(parent, name, h, dia, ROW * base, color, material, opts)
end
local function ball(parent, name, d, cf, color, material, opts)
	return K.ball(parent, name, d, ROW * cf, color, material, opts)
end
local function blob(parent, name, size, cf, color, material, opts)
	return K.blob(parent, name, size, ROW * cf, color, material, opts)
end
local function site(name, cf, attrs)
	return K.site(name, ROW * cf, attrs)
end
local function promptPart(parent, name, pos, actionText, objectText, attrs, labelColor)
	return K.promptPart(parent, name, (ROW * CF(pos)).Position, actionText, objectText, attrs, labelColor)
end
local function lightZone(parent, name, size, cf, profile)
	return K.lightZone(parent, name, size, ROW * cf, profile)
end
local function roomLight(parent, cf, color, range, brightness)
	return K.roomLight(parent, ROW * cf, color, range, brightness)
end
local function nightPoint(parent, cf, color, range, brightness)
	return K.nightPoint(parent, ROW * cf, color, range, brightness)
end
local function neonOutline(parent, cf, w, h, color)
	return K.neonOutline(parent, ROW * cf, w, h, color)
end
local function spotAt(parent, cf, face, color, range, brightness, angle)
	return K.spot(K.emitter(parent, ROW * cf), face, color, range, brightness, angle)
end
local function pointAt(parent, cf, color, range, brightness)
	return K.point(K.emitter(parent, ROW * cf), color, range, brightness)
end
local function bench(parent, pos, yaw, len, color)
	return K.bench(parent, (ROW * CF(pos)).Position, (yaw or 0) + ROW_YAW, len, color)
end
local function plant(parent, pos, scale)
	return GymDecor.Plant(parent, (ROW * CF(pos)).Position, scale)
end

------------------------------------------------------------------------
-- the shops (x0 / x1 along the row; h the parapet height; floors the storeys above the ground floor)
-- action = ProximityPrompt Action at the counter; interior = walk-in shop built by shopInterior;
-- zone = LightZone profile inside; doorAt = door position along the front (fraction of the width)
------------------------------------------------------------------------
local H1, H2, H3, H4 = G + S + 1.2, G + 2 * S + 1.2, G + 3 * S + 1.2, G + 4 * S + 1.2
CityShops.SHOPS = {
	{ x0 = -552, x1 = -500, h = H1, floors = 1, color = Color3.fromRGB(60, 44, 60), mat = M.Brick, sign = "VINYL CITY RECORDS", signBg = Color3.fromRGB(20, 12, 24), signFg = Color3.fromRGB(255, 120, 60), awning = Color3.fromRGB(90, 30, 60), neon = true },
	{ x0 = -492, x1 = -456, h = H1, floors = 1, color = Color3.fromRGB(40, 40, 46), mat = M.Brick, sign = "FRESH FADES BARBERSHOP", signBg = Color3.fromRGB(14, 30, 70), signFg = Color3.fromRGB(240, 240, 245), awning = Color3.fromRGB(180, 30, 36), neon = true,
		interior = "barber", action = "Barber", actionText = "Get a cut", zone = "Barbershop", doorAt = -0.2 },
	{ x0 = -450, x1 = -393, h = 16, floors = 0, color = Color3.fromRGB(236, 234, 228), sign = "CHAMP'S DINER", signBg = Color3.fromRGB(190, 20, 30), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(200, 30, 36), neon = true,
		interior = "diner", action = "Diner", actionText = "Order food", zone = "Store" },
	{ x0 = -384, x1 = -333, h = H1, floors = 1, color = Color3.fromRGB(70, 72, 78), sign = "IRON SUPPLEMENTS", signBg = Color3.fromRGB(16, 18, 20), signFg = Color3.fromRGB(80, 220, 110), awning = Color3.fromRGB(30, 110, 60),
		interior = "supplements", action = "Supplements", actionText = "Buy supplements", zone = "Store" },
	{ x0 = -324, x1 = -264, h = H2, floors = 2, color = Color3.fromRGB(32, 32, 36), sign = "WCB PRO SHOP - GLOVES & GEAR", shop = "WCB PRO SHOP", signBg = Color3.fromRGB(14, 14, 16), signFg = C.gold, awning = Color3.fromRGB(20, 20, 24),
		interior = "proshop", action = "ProShop", actionText = "Browse gear", zone = "Store" },
	{ x0 = -255, x1 = -189, h = H3, floors = 3, color = Color3.fromRGB(134, 72, 56), mat = M.Brick, sign = "CORNER CAFE", signBg = Color3.fromRGB(60, 40, 30), signFg = Color3.fromRGB(255, 230, 190), awning = Color3.fromRGB(90, 60, 40), fireEscape = true },
	{ x0 = -180, x1 = -135, h = H1, floors = 1, color = Color3.fromRGB(200, 222, 240), sign = "SPIN CITY LAUNDROMAT", signBg = Color3.fromRGB(40, 110, 200), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(40, 110, 200) },
	{ x0 = -126, x1 = -84, h = H1, floors = 1, color = Color3.fromRGB(40, 32, 52), sign = "INK & IRON TATTOO", signBg = Color3.fromRGB(20, 14, 26), signFg = Color3.fromRGB(220, 90, 255), awning = Color3.fromRGB(70, 30, 90), neon = true },
	{ x0 = -75, x1 = -27, h = H1, floors = 1, color = Color3.fromRGB(244, 222, 180), sign = "SUNRISE BAKERY", signBg = Color3.fromRGB(250, 240, 220), signFg = Color3.fromRGB(170, 90, 40), awning = Color3.fromRGB(240, 170, 60) },
	{ x0 = -18, x1 = 18, h = H2, floors = 2, color = Color3.fromRGB(26, 26, 30), sign = "WCB ARENA TICKETS", signBg = Color3.fromRGB(150, 16, 24), signFg = Color3.fromRGB(255, 220, 90), awning = Color3.fromRGB(150, 16, 24), marquee = true,
		action = "CareerHub", actionText = "Fight offers" },
	{ x0 = 27, x1 = 84, h = H1, floors = 1, color = Color3.fromRGB(220, 220, 214), sign = "CORNER STORE 24/7", signBg = Color3.fromRGB(30, 120, 60), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(30, 120, 60) },
	{ x0 = 93, x1 = 144, h = H1, floors = 1, color = Color3.fromRGB(176, 60, 44), mat = M.Brick, sign = "TONY'S PIZZA", signBg = Color3.fromRGB(20, 110, 50), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(200, 40, 40), neon = true,
		action = "Diner", actionText = "Grab a slice" },
	{ x0 = 153, x1 = 225, h = H4, floors = 4, color = Color3.fromRGB(150, 150, 156), mat = M.Concrete, sign = "RIVERSIDE APARTMENTS", signBg = Color3.fromRGB(30, 34, 40), signFg = Color3.new(1, 1, 1), awning = Color3.fromRGB(30, 34, 40), apartments = true },
	{ x0 = 234, x1 = 294, h = 30, floors = 0, color = Color3.fromRGB(220, 210, 190), mat = M.Limestone, sign = "BOXING HALL OF FAME MUSEUM", signBg = Color3.fromRGB(20, 20, 24), signFg = C.gold, awning = Color3.fromRGB(20, 20, 24), columns = true,
		interior = "museum", action = "Museum", actionText = "Your legacy", zone = "Store", doorAt = 0, roomDepth = 30, roomH = 16 },
	{ x0 = 303, x1 = 372, h = H2, floors = 2, color = Color3.fromRGB(206, 198, 180), mat = M.Limestone, sign = "FIRST CITY BANK", signBg = Color3.fromRGB(20, 40, 80), signFg = Color3.fromRGB(240, 230, 200), awning = Color3.fromRGB(20, 40, 80) },
	{ x0 = 384, x1 = 450, h = H1, floors = 1, color = Color3.fromRGB(220, 200, 150), sign = "STARLIGHT MOTEL", signBg = Color3.fromRGB(16, 20, 40), signFg = Color3.fromRGB(255, 120, 180), awning = Color3.fromRGB(40, 60, 120), neon = true, poleSign = "MOTEL" },
	{ x0 = 456, x1 = 510, h = H1, floors = 1, color = Color3.fromRGB(26, 28, 34), mat = M.Metal, sign = "PRESTIGE MOTORS", signBg = Color3.fromRGB(12, 12, 16), signFg = Color3.fromRGB(220, 220, 230), awning = Color3.fromRGB(12, 12, 16),
		interior = "motors", action = "Motors", actionText = "Browse cars", zone = "Store", doorAt = 0.25, roomH = 16, roomDepth = 30 },
}
-- the gas station's apron (row-local x) and the dealer-to-river stretch
CityShops.GAS = { x0 = 526, x1 = 646 }

local DEPTH = 44 -- a block's depth from the front face

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
			label(box, txt, { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.35), Face = "signSub" })
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
	part(f, "ShelfBack", V3(c.x1 - c.x0 - 4, c.h - 1.5, 0.3), CF(c.cx, y + (c.h - 1.5) / 2, zBack - 0.2), Color3.fromRGB(26, 26, 28), M.SmoothPlastic)
	local tubColors = { Color3.fromRGB(30, 30, 30), Color3.fromRGB(240, 110, 20), Color3.fromRGB(30, 150, 70), Color3.fromRGB(200, 30, 40), Color3.fromRGB(230, 230, 230), Color3.fromRGB(40, 90, 200) }
	local names = { "WHEY", "BCAA", "CREATINE", "PRE", "MASS", "ISO", "OMEGA", "CASEIN" }
	for k, sy in ipairs({ 1.4, 3.6, 5.8, 8.0 }) do
		part(f, "Shelf", V3(c.x1 - c.x0 - 4, 0.2, 1.6), CF(c.cx, y + sy - 0.15, zBack - 1.1), Color3.fromRGB(190, 190, 196), M.Metal)
		productRow(f, CF(c.cx, y + sy + 0.75, zBack - 1.1), c.x1 - c.x0 - 4.4, 1.5, tubColors, k == 2 and names or nil)
	end
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
	local ccf = CF(c.x1 - 5, y, c.z0 + 8) * ANG(0, RAD(90), 0)
	counter(f, ccf, 8, Color3.fromRGB(30, 30, 32), Color3.fromRGB(46, 120, 70))
	vcyl(f, "Blender", 1.4, 0.7, ccf * CF(-1.5, 3.4, 0), Color3.fromRGB(220, 230, 240), M.Glass, { transparency = 0.2 })
	for k, off in ipairs({ { -1.2, 0 }, { 0, 0 }, { 1.2, 0 }, { -0.6, 1.2 }, { 0.6, 1.2 }, { 0, 2.4 } }) do
		vcyl(f, "TubDisplay", 1.2, 0.95, CF(c.cx - 4 + off[1], y + off[2], c.z0 + 2.5), tubColors[k % #tubColors + 1], M.SmoothPlastic)
	end
	part(f, "Scale", V3(1.8, 0.3, 1.8), CF(c.x0 + 3, y + 0.15, c.z0 + 12), Color3.fromRGB(40, 40, 44), M.Metal)
	part(f, "ScaleMirror", V3(0.15, 6, 3), CF(c.x0 + 0.1, y + 3.6, c.z0 + 13.5), Color3.fromRGB(220, 235, 245), M.Glass, { reflect = 0.4 })
	-- a second island of boxes in the middle of the deeper room
	part(f, "Island", V3(6, 2.6, 2.4), CF(c.cx + 2, y + 1.3, c.z0 + 14), Color3.fromRGB(26, 26, 28), M.SmoothPlastic, { collide = true })
	productRow(f, CF(c.cx + 2, y + 3.3, c.z0 + 14), 5.6, 1.3, tubColors, { "BARS", "SHAKES" })
	return (ccf * CF(0, 0, -2.4)).Position + V3(0, 0.5, 0)
end

INTERIOR.proshop = function(f, d, c)
	local y = c.y
	local zBack = c.z1
	local peg = part(f, "Pegboard", V3(c.x1 - c.x0 - 6, 6, 0.2), CF(c.cx, y + 4.2, zBack - 0.15), Color3.fromRGB(196, 170, 130), M.Wood)
	local psg = gui(peg, Enum.NormalId.Front, 10, 1, 80)
	for r = 0, 3 do
		for k = 0, 7 do
			frame(psg, { Size = UDim2.fromScale(0.014, 0.035), Position = UDim2.fromScale(0.04 + k * 0.125 + (r % 2) * 0.06, 0.1 + r * 0.24), BackgroundColor3 = Color3.fromRGB(90, 70, 50) })
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
		local word = b.wordmark ~= "" and b.wordmark or "GYM ISSUE"
		local ban = part(f, "BrandBanner", V3(3.2, 1.6, 0.08), CF(gx, y + c.h - 1.6, c.z0 + 4 + (i % 2) * 6), col, M.Fabric, { shadow = false })
		local fontOk, font = pcall(function()
			return Enum.Font[b.font]
		end)
		GymDecor.Sign(ban, Enum.NormalId.Front, word, CityProps.RGB(b.wordColor), col, 30, 0.4, fontOk and font or "sign")
		GymDecor.Sign(ban, Enum.NormalId.Back, word, CityProps.RGB(b.wordColor), col, 30, 0.4, fontOk and font or "sign")
	end
	productRow(f, CF(c.x0 + 0.5, y + 2.2, c.z0 + 10) * ANG(0, RAD(90), 0), 10, 1.2, { Color3.fromRGB(20, 20, 24), Color3.fromRGB(240, 240, 240), Color3.fromRGB(200, 30, 36), Color3.fromRGB(230, 180, 40) }, { "BOOT", "PRO", "ELITE" }, Enum.NormalId.Back)
	productRow(f, CF(c.x0 + 0.5, y + 4.2, c.z0 + 10) * ANG(0, RAD(90), 0), 10, 1.2, { Color3.fromRGB(30, 60, 190), Color3.fromRGB(120, 20, 30), Color3.fromRGB(245, 240, 230) }, { "WRAPS", "GEL" }, Enum.NormalId.Back)
	local mq = CF(c.x0 + 5, y, c.z0 + 3.5)
	vcyl(f, "MannequinStand", 0.2, 2, mq, Color3.fromRGB(30, 30, 30), M.Metal)
	blob(f, "Robe", V3(2.6, 4.6, 1.6), mq * CF(0, 3.4, 0), Color3.fromRGB(200, 30, 36), M.Fabric)
	blob(f, "RobeTrim", V3(2.7, 0.5, 1.7), mq * CF(0, 1.3, 0), C.gold, M.Fabric)
	ball(f, "MannequinHead", 1.0, mq * CF(0, 6.2, 0), Color3.fromRGB(230, 230, 232), M.SmoothPlastic)
	local bagCF = CF(c.cx - 2, y, c.z0 + 11)
	part(f, "BagChain", V3(0.15, c.h - 6.6, 0.15), bagCF * CF(0, 6.6 + (c.h - 6.6) / 2, 0), C.steelLight, M.Metal)
	vcyl(f, "TestBag", 4.4, 2.0, bagCF * CF(0, 2.2, 0), Color3.fromRGB(150, 24, 30), M.Leather, { collide = true })
	local case = CF(c.cx + 5, y, c.z0 + 4)
	part(f, "CaseBase", V3(4, 3, 2.4), case * CF(0, 1.5, 0), Color3.fromRGB(30, 30, 34), M.Wood, { collide = true })
	part(f, "CaseGlass", V3(4, 1.8, 2.4), case * CF(0, 3.9, 0), Color3.fromRGB(210, 230, 245), M.Glass, { transparency = 0.6 })
	part(f, "ReplicaStrap", V3(3.2, 0.5, 0.9), case * CF(0, 3.3, 0), Color3.fromRGB(20, 20, 22), M.Leather)
	cyl(f, "ReplicaPlate", 0.2, 1.1, case * CF(0, 3.45, 0) * ANG(0, 0, RAD(90)), C.gold, M.Metal, { reflect = 0.25 })
	local ccf = CF(c.x1 - 4.5, y, c.z0 + 9) * ANG(0, RAD(90), 0)
	counter(f, ccf, 8, Color3.fromRGB(20, 20, 22), Color3.fromRGB(32, 32, 36))
	return (ccf * CF(0, 0, -2.4)).Position + V3(0, 0.5, 0)
end

INTERIOR.diner = function(f, d, c)
	local y = c.y
	local ccf = CF(c.cx - 2, y, c.z1 - 4.5)
	part(f, "DinerCounter", V3(22, 3.4, 2.2), ccf * CF(0, 1.7, 0), Color3.fromRGB(200, 30, 36), M.SmoothPlastic, { collide = true })
	part(f, "DinerCounterTop", V3(22.4, 0.25, 2.6), ccf * CF(0, 3.5, 0), Color3.fromRGB(230, 230, 232), M.Marble)
	part(f, "DinerTrim", V3(22.4, 0.25, 0.1), ccf * CF(0, 2.6, -1.15), Color3.fromRGB(220, 220, 225), M.Metal, { reflect = 0.3 })
	for k = 0, 6 do
		local sx = -9 + k * 3
		vcyl(f, "StoolPost", 2.2, 0.3, ccf * CF(sx, 0, -2.6), C.steelLight, M.Metal)
		vcyl(f, "StoolSeat", 0.45, 1.5, ccf * CF(sx, 2.2, -2.6), Color3.fromRGB(200, 30, 36), M.Leather, { collide = true })
	end
	part(f, "PieCase", V3(3, 1.6, 1.6), ccf * CF(8.5, 4.4, 0), Color3.fromRGB(220, 235, 245), M.Glass, { transparency = 0.4 })
	part(f, "CoffeeMachine", V3(1.8, 2.2, 1.4), ccf * CF(-8.5, 4.7, 0.2), Color3.fromRGB(40, 40, 44), M.Metal)
	local menu = part(f, "MenuBoard", V3(16, 4, 0.2), CF(c.cx - 2, y + c.h - 2.8, c.z1 - 0.15), Color3.fromRGB(20, 20, 22), M.SmoothPlastic)
	local msg = gui(menu, Enum.NormalId.Front, 20, 0.2, 120)
	frame(msg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(22, 22, 24) })
	label(msg, "CHAMP'S MENU", { TextColor3 = C.gold, Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.03) })
	local lines = {}
	for _, meal in ipairs(Config.Meals) do
		if meal.price > 0 and not meal.requires then
			table.insert(lines, string.format("%s  %s", meal.name:upper(), Config.Money(meal.price)))
		end
	end
	label(msg, table.concat(lines, "\n"), { TextColor3 = Color3.fromRGB(240, 240, 235), Face = "signSub", Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.27) })
	for k = 0, 3 do
		local bz = c.z0 + 2.4 + k * 4.4
		local bx = c.x1 - 3.4
		part(f, "BoothTable", V3(3.4, 0.25, 1.8), CF(bx, y + 2.6, bz), Color3.fromRGB(230, 230, 232), M.Marble)
		part(f, "BoothLeg", V3(0.3, 2.5, 0.3), CF(bx, y + 1.25, bz), C.steelLight, M.Metal)
		for _, s in ipairs({ -1, 1 }) do
			part(f, "BoothSeat", V3(3.4, 1.6, 1.0), CF(bx, y + 0.8, bz + s * 1.45), Color3.fromRGB(200, 30, 36), M.Leather, { collide = true })
			part(f, "BoothBack", V3(3.4, 2.4, 0.4), CF(bx, y + 2.4, bz + s * 1.85), Color3.fromRGB(170, 24, 30), M.Leather)
		end
	end
	local jb = CF(c.x0 + 1.5, y, c.z1 - 1.5)
	part(f, "Jukebox", V3(2.4, 4.2, 1.6), jb * CF(0, 2.1, 0), Color3.fromRGB(120, 60, 30), M.Wood, { collide = true })
	local arch = part(f, "JukeboxGlow", V3(2.0, 1.4, 0.1), jb * CF(0, 3.4, -0.82), Color3.fromRGB(255, 160, 60), M.Neon, { shadow = false })
	local jl = Instance.new("PointLight")
	jl.Color, jl.Range, jl.Brightness, jl.Shadows = Color3.fromRGB(255, 140, 60), 8, 1, false
	jl.Parent = arch
	for k = 1, 3 do
		local ph = part(f, "DinerPhoto", V3(0.12, 3.2, 2.4), CF(c.x0 + 0.1, y + 5, c.z0 + 2 + k * 3.6), C.black, M.SmoothPlastic)
		GymDecor.PosterGui(ph, Enum.NormalId.Right, GymDecor.Posters[(k % #GymDecor.Posters) + 1])
	end
	return (ccf * CF(5, 0, -2.8)).Position + V3(0, 0.5, 0)
end

INTERIOR.barber = function(f, d, c)
	local y = c.y
	for k = 0, 1 do
		local sx = c.cx - 4 + k * 8
		part(f, "StationMirror", V3(4, 4.5, 0.15), CF(sx, y + 5, c.z1 - 0.2), Color3.fromRGB(215, 232, 245), M.Glass, { reflect = 0.45 })
		part(f, "StationShelf", V3(4.4, 0.3, 1.2), CF(sx, y + 2.6, c.z1 - 0.7), Color3.fromRGB(30, 30, 34), M.Marble)
		blob(f, "Clippers", V3(0.4, 0.3, 0.9), CF(sx - 1, y + 2.9, c.z1 - 0.7), C.black, M.SmoothPlastic)
		vcyl(f, "Tonic", 0.9, 0.35, CF(sx + 1.2, y + 2.75, c.z1 - 0.7), Color3.fromRGB(60, 160, 200), M.Glass, { transparency = 0.2 })
		local ch = CF(sx, y, c.z1 - 4.5)
		vcyl(f, "ChairBase", 0.4, 2.2, ch, Color3.fromRGB(200, 200, 205), M.Metal)
		vcyl(f, "ChairPost", 1.4, 0.6, ch * CF(0, 0.4, 0), Color3.fromRGB(200, 200, 205), M.Metal)
		part(f, "ChairSeat", V3(2.2, 0.6, 2.2), ch * CF(0, 2.1, 0), Color3.fromRGB(150, 20, 26), M.Leather, { collide = true })
		part(f, "ChairBack", V3(2.2, 2.8, 0.5), ch * CF(0, 3.6, 1.0) * ANG(RAD(-10), 0, 0), Color3.fromRGB(150, 20, 26), M.Leather)
		for _, s in ipairs({ -1, 1 }) do
			part(f, "ChairArm", V3(0.3, 0.3, 1.8), ch * CF(s * 1.15, 3.0, 0.1), Color3.fromRGB(200, 200, 205), M.Metal)
		end
		part(f, "FootRest", V3(1.6, 0.2, 0.8), ch * CF(0, 0.9, -1.6), Color3.fromRGB(200, 200, 205), M.Metal)
	end
	bench(f, V3(c.x0 + 1.5, y, c.z0 + 7), RAD(90), 6.4, C.woodDark)
	productRow(f, CF(c.x0 + 0.5, y + 4.6, c.z0 + 7) * ANG(0, RAD(90), 0), 6, 1.1, { Color3.fromRGB(30, 30, 34), Color3.fromRGB(200, 170, 80), Color3.fromRGB(40, 110, 160) }, { "POMADE", "BEARD OIL" }, Enum.NormalId.Back)
	local styles = part(f, "StyleChart", V3(0.12, 4, 3), CF(c.x1 - 0.1, y + 5, c.z0 + 4), C.white, M.SmoothPlastic)
	GymDecor.Sign(styles, Enum.NormalId.Left, "FADES\nTAPERS\nCORNROWS\nLOCS\nLINE-UPS", C.black, C.white, 30)
	-- the classic spinning pole beside the door (Ambience spins every SpinFan model)
	local pm = K.model(f, "BarberPole")
	local px, pz = c.doorX - 3.6, -0.7
	local hub = cyl(pm, "Hub", 4.4, 0.9, CF(px, 6.2, pz) * ANG(0, 0, RAD(90)), C.white, M.SmoothPlastic)
	for i = 0, 2 do
		part(pm, "Blade", V3(0.25, 0.95, 0.95), CF(px, 4.7 + i * 1.5, pz) * ANG(0, 0, RAD(60)), i % 2 == 0 and C.red or C.blue, M.SmoothPlastic)
	end
	part(pm, "PoleCap", V3(1.2, 0.4, 1.2), CF(px, 8.6, pz), Color3.fromRGB(210, 210, 215), M.Metal)
	part(pm, "PoleCap", V3(1.2, 0.4, 1.2), CF(px, 3.8, pz), Color3.fromRGB(210, 210, 215), M.Metal)
	pm.PrimaryPart = hub
	pm:SetAttribute("Speed", 2.2)
	tag(pm, "SpinFan")
	return V3(c.cx, y + 3.2, c.z1 - 8)
end

INTERIOR.museum = function(f, d, c)
	local y = c.y
	local hof = part(f, "HallSign", V3(18, 3.4, 0.2), CF(c.cx, y + c.h - 2.8, c.z1 - 0.15), Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
	GymDecor.Sign(hof, Enum.NormalId.Front, "HALL OF FAME", C.gold, Color3.fromRGB(20, 20, 24), 30, 0, "serif")
	for k, era in ipairs({ "THE BARE-KNUCKLE ERA", "THE GOLDEN AGE", "THE TELEVISION ERA", "THE MODERN GREATS" }) do
		local bx = c.cx + ({ -22, -15, 15, 22 })[k]
		local ban = part(f, "EraBanner", V3(4.6, 8, 0.1), CF(bx, y + c.h - 6, c.z1 - 0.3), Color3.fromRGB(110, 20, 26), M.Fabric)
		GymDecor.Sign(ban, Enum.NormalId.Front, era, C.gold, Color3.fromRGB(110, 20, 26), 30)
	end
	local bronze = Color3.fromRGB(150, 104, 54)
	for i = 1, math.min(8, #Config.Legends) do
		local lg = Config.Legends[i]
		local side = i % 2 == 1 and -1 or 1
		local row = math.floor((i - 1) / 2)
		local bx = side < 0 and c.x0 + 2.5 or c.x1 - 2.5
		local bz = c.z0 + 5 + row * 6
		local base = CF(bx, y, bz)
		part(f, "BustPlinth", V3(2.2, 3.6, 2.2), base * CF(0, 1.8, 0), Color3.fromRGB(230, 226, 216), M.Marble, { collide = true })
		blob(f, "BustShoulders", V3(2.0, 1.0, 1.1), base * CF(0, 4.0, 0), bronze, M.Metal, { reflect = 0.12 })
		blob(f, "BustHead", V3(0.95, 1.15, 1.05), base * CF(0, 4.9, 0), bronze, M.Metal, { reflect = 0.12 })
		local pl = part(f, "BustPlaque", V3(0.1, 1.2, 2.0), base * CF(-side * 1.15, 2.6, 0), C.gold, M.Metal)
		GymDecor.Sign(pl, side < 0 and Enum.NormalId.Right or Enum.NormalId.Left, string.format("%s\nLEGACY %d", lg.name, lg.score), Color3.fromRGB(40, 28, 10), C.gold, 40)
	end
	local cc = CF(c.cx, y, c.z0 + 10)
	part(f, "CaseBase", V3(5, 3, 3), cc * CF(0, 1.5, 0), Color3.fromRGB(30, 26, 22), M.Wood, { collide = true })
	part(f, "CaseGlass", V3(5, 2.2, 3), cc * CF(0, 4.1, 0), Color3.fromRGB(210, 230, 245), M.Glass, { transparency = 0.65 })
	blob(f, "VintageGlove", V3(1.0, 1.2, 1.1), cc * CF(-1.2, 3.6, 0), Color3.fromRGB(110, 60, 30), M.Leather)
	blob(f, "VintageGlove", V3(1.0, 1.2, 1.1), cc * CF(-0.1, 3.6, 0.2), Color3.fromRGB(110, 60, 30), M.Leather)
	part(f, "VintageBelt", V3(1.8, 0.4, 0.8), cc * CF(1.4, 3.3, 0), Color3.fromRGB(20, 20, 22), M.Leather)
	cyl(f, "VintagePlate", 0.15, 0.8, cc * CF(1.4, 3.42, 0) * ANG(0, 0, RAD(90)), C.gold, M.Metal, { reflect = 0.25 })
	for k, off in ipairs({ { -3.5, -2.5 }, { 3.5, -2.5 }, { 3.5, 2.5 }, { -3.5, 2.5 } }) do
		vcyl(f, "Stanchion", 3, 0.3, cc * CF(off[1], 0, off[2]), C.goldDeep, M.Metal)
		local nxt = ({ { 3.5, -2.5 }, { 3.5, 2.5 }, { -3.5, 2.5 }, { -3.5, -2.5 } })[k]
		local a = (cc * CF(off[1], 2.6, off[2])).Position
		local b = (cc * CF(nxt[1], 2.6, nxt[2])).Position
		part(f, "VelvetRope", V3(0.18, 0.18, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Color3.fromRGB(140, 16, 30), M.Fabric)
	end
	for _, x in ipairs({ c.x0 + 2.5, c.x1 - 2.5 }) do
		spotAt(f, CF(x, y + c.h - 0.6, c.z0 + 12), Enum.NormalId.Bottom, Color3.fromRGB(255, 230, 190), 22, 1.2, 70)
	end
	site("MuseumExhibit", CFrame.lookAt(V3(c.cx, y, c.z1 - 6), V3(c.cx, y, c.z0)))
	site("MuseumBanner", CFrame.lookAt(V3(c.cx, 21, -4.6), V3(c.cx, 21, -12)))
	return V3(c.cx + 4, y + 3.2, c.z0 + 4)
end

INTERIOR.motors = function(f, d, c)
	local y = c.y
	local stands = { { c.x0 + 9, c.z0 + 10, 60, "Supercar" }, { c.x1 - 9, c.z0 + 18, 125, "SportsCar" } }
	for _, st in ipairs(stands) do
		local tcf = CF(st[1], y, st[2]) * ANG(0, RAD(st[3]), 0)
		vcyl(f, "Turntable", 0.3, 15, tcf, Color3.fromRGB(40, 40, 46), M.Metal, { reflect = 0.2, collide = true })
		local carM = CityProps.SportsCar(f, ROW * tcf * CF(0, 0.3, 0), st[4], nil, "PRESTIGE")
		pcall(function()
			carM:ScaleTo(1.4)
		end)
		spotAt(f, CF(st[1], y + c.h - 0.6, st[2]), Enum.NormalId.Bottom, Color3.fromRGB(240, 245, 255), 20, 1.6, 60)
	end
	local wall = part(f, "BrandWall", V3(c.x1 - c.x0 - 2, 3, 0.2), CF(c.cx, y + c.h - 2.6, c.z1 - 0.15), Color3.fromRGB(14, 14, 18), M.SmoothPlastic)
	GymDecor.Sign(wall, Enum.NormalId.Front, "PRESTIGE MOTORS", Color3.fromRGB(220, 220, 230), Color3.fromRGB(14, 14, 18), 30, 0, "tech")
	local desk = CF(c.x0 + 5, y, c.z1 - 3)
	part(f, "SalesDesk", V3(5, 2.8, 2), desk * CF(0, 1.4, 0), Color3.fromRGB(230, 230, 232), M.Marble, { collide = true })
	part(f, "DeskScreen", V3(1.6, 1.1, 0.1), desk * CF(0.8, 3.4, 0.3), Color3.fromRGB(20, 30, 50), M.Glass)
	return (desk * CF(2, 0, -2.4)).Position + V3(0, 0.5, 0)
end

-- the hollow front room of an interior shop (see INTERIOR above)
local function shopInterior(f, d, w, cx, doorX)
	local RD, RH = d.roomDepth or 22, d.roomH or 11.5
	local floorTop = d.columns and SW_H + 0.6 or SW_H
	local mat = d.mat or M.SmoothPlastic
	for _, s in ipairs({ -1, 1 }) do
		part(f, "ShopSideWall", V3(1, RH, RD - 0.6), CF(cx + s * (w / 2 - 0.5), RH / 2, 0.6 + (RD - 0.6) / 2), d.color, mat, { collide = true })
	end
	local floorMat = ({ diner = M.SmoothPlastic, barber = M.SmoothPlastic, museum = M.Marble, motors = M.Marble, supplements = M.Rubber })[d.interior] or M.WoodPlanks
	local floorCol = ({ museum = Color3.fromRGB(226, 222, 214), motors = Color3.fromRGB(40, 40, 46), supplements = Color3.fromRGB(34, 34, 38) })[d.interior] or Color3.fromRGB(150, 110, 72)
	local fl = part(f, "ShopFloor", V3(w - 2, floorTop, RD), CF(cx, floorTop / 2, RD / 2), floorCol, floorMat, { collide = true })
	if d.interior == "diner" then
		checkerFloor(fl, Color3.fromRGB(24, 24, 26), Color3.fromRGB(236, 236, 230), 14, 6)
	elseif d.interior == "barber" then
		checkerFloor(fl, Color3.fromRGB(30, 30, 34), Color3.fromRGB(230, 230, 226), 9, 6)
	end
	-- facade: piers at both ends, a header above the glass, panes either side of the open door (the
	-- opening clears the tallest boxer the Creator allows, 7.6 studs, with room for a hop)
	local glassTop = math.min(10, RH - 1.2)
	for _, s in ipairs({ -1, 1 }) do
		part(f, "ShopPier", V3(2, RH, 0.6), CF(cx + s * (w / 2 - 1), RH / 2, 0.3), d.color, mat, { collide = true })
	end
	part(f, "ShopHeader", V3(w, RH - glassTop, 0.6), CF(cx, glassTop + (RH - glassTop) / 2, 0.3), d.color, mat, { collide = true })
	local spans = { { cx - w / 2 + 2, doorX - 2.3 }, { doorX + 2.3, cx + w / 2 - 2 } }
	for _, sp in ipairs(spans) do
		local pw = sp[2] - sp[1]
		if pw > 0.6 then
			local pc = (sp[1] + sp[2]) / 2
			local pane = part(f, "ShopWindow", V3(pw, glassTop - 1, 0.12), CF(pc, 1 + (glassTop - 1) / 2, 0.1), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.6, reflect = 0.12, shadow = false, collide = true })
			pane:SetAttribute("Shop", d.sign)
			part(f, "Kickplate", V3(pw, 1.0, 0.3), CF(pc, 0.8, 0.1), Color3.fromRGB(40, 40, 44), M.Metal, { collide = true })
			local n = math.max(1, math.floor(pw / 7))
			for k = 0, n do
				part(f, "Mullion", V3(0.3, glassTop - 1, 0.3), CF(sp[1] + k * pw / n, 1 + (glassTop - 1) / 2, 0.1), Color3.fromRGB(30, 30, 34), M.Metal)
			end
		end
	end
	-- the door stands open inwards (glass leaf hinged at the right jamb)
	part(f, "ShopDoor", V3(0.15, glassTop - 0.3, 4.2), CF(doorX + 2.2, floorTop + (glassTop - 0.3) / 2, 2.4), Color3.fromRGB(180, 210, 230), M.Glass, { transparency = 0.45, shadow = false })
	part(f, "DoorFrame", V3(4.8, 0.3, 0.6), CF(doorX, glassTop + 0.15, 0.3), Color3.fromRGB(30, 30, 34), M.Metal)
	roomLight(f, CF(cx, RH - 0.8, RD * 0.55), Color3.fromRGB(255, 236, 214), math.max(24, w * 0.7), 1.1)
	for _, s in ipairs({ -0.25, 0.25 }) do
		part(f, "CeilingPanel", V3(5, 0.12, 2.4), CF(cx + s * w, RH - 0.06, RD * 0.55), Color3.fromRGB(250, 248, 240), M.Neon, { shadow = false })
	end
	lightZone(f, "ShopZone", V3(w - 2, RH, RD), CF(cx, RH / 2, RD / 2), d.zone or "Store")
	local build = INTERIOR[d.interior]
	local ctx = { x0 = cx - w / 2 + 1, x1 = cx + w / 2 - 1, z0 = 0.6, z1 = RD, y = floorTop, h = RH, cx = cx, doorX = doorX }
	local ok, at = pcall(build, f, d, ctx)
	if not ok then
		warn("[CityShops] interior " .. tostring(d.interior) .. " failed: " .. tostring(at))
		at = nil
	end
	return RD, RH, at
end

-- one shop front (row frame). Returns the body part.
local function shop(f, d, rng)
	local w = d.x1 - d.x0
	local cx = (d.x0 + d.x1) / 2
	local depth = d.depth or DEPTH
	local h = d.h
	local sfW = w - 4
	local doorX = cx + w * (d.doorAt or 0.22)
	local body, gridPart, gridBase
	local counterAt
	if d.interior then
		local RD, RH, at = shopInterior(f, d, w, cx, doorX)
		counterAt = at
		body = part(f, "Building", V3(w, h, depth - RD), CF(cx, h / 2, RD + (depth - RD) / 2), d.color, d.mat or M.SmoothPlastic, { collide = true })
		gridPart = part(f, "BuildingUpper", V3(w, h - RH, RD), CF(cx, RH + (h - RH) / 2, RD / 2), d.color, d.mat or M.SmoothPlastic, { collide = true })
		gridBase = RH
	else
		body = part(f, "Building", V3(w, h, depth), CF(cx, h / 2, depth / 2), d.color, d.mat or M.SmoothPlastic, { collide = true })
		gridPart, gridBase = body, 0
		-- storefront: dark interior, glass, mullions, door and kickplate (the glass 0.8..9.8)
		part(f, "ShopInterior", V3(sfW, 9, 0.12), CF(cx, 5.3, -0.07), Color3.fromRGB(36, 40, 48), M.SmoothPlastic)
		local win = part(f, "ShopWindow", V3(sfW, 9, 0.1), CF(cx, 5.3, -0.2), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.55, reflect = 0.12, shadow = false })
		win:SetAttribute("Shop", d.sign)
		local n = math.max(1, math.floor(sfW / 7))
		for k = 0, n do
			part(f, "Mullion", V3(0.3, 9, 0.3), CF(d.x0 + 2 + k * sfW / n, 5.3, -0.2), Color3.fromRGB(30, 30, 34), M.Metal)
		end
		part(f, "ShopDoor", V3(CITY.Door.w, CITY.Door.h + 0.1, 0.15), CF(doorX, SW_H + (CITY.Door.h + 0.1) / 2, -0.32), Color3.fromRGB(28, 28, 32), M.Metal)
		part(f, "Kickplate", V3(sfW, 1.0, 0.3), CF(cx, 0.8, -0.15), Color3.fromRGB(40, 40, 44), M.Metal)
	end
	part(f, "Cornice", V3(w + 0.8, 1.1, depth + 0.8), CF(cx, h + 0.55, depth / 2), Color3.fromRGB(60, 58, 56), M.Concrete)
	-- where a sponsor's poster goes in this shop's window (CityVisuals, when you carry their brand)
	local wz = d.interior and 1.4 or -1.8
	site("Window_" .. d.sign:gsub("[^%w]", ""), CFrame.lookAt(V3(d.x0 + 5, SW_H, wz), V3(d.x0 + 5, SW_H, wz - 6)), { Shop = d.shop or d.sign })
	if d.action then
		local at = counterAt or V3(doorX, SW_H + 2.4, -1.8)
		local _, pp = promptPart(f, "ShopPrompt", at, d.actionText or "Enter", d.sign, { Action = d.action, Store = d.sign }, d.signFg)
		if counterAt then
			pp.MaxActivationDistance = 14
		end
	end
	local glow = pointAt(f, CF(cx, 6, -1.4), Color3.fromRGB(255, 214, 160), 18, 0.9)
	glow.Enabled = false
	tag(glow, "NightLight")
	-- awning and sign band (between the ground floor glass and the first upper storey)
	part(f, "ShopAwning", V3(w - 1.5, 0.35, 5.4), CF(cx, 10.6, -2.6) * ANG(RAD(-14), 0, 0), d.awning, M.Fabric)
	local signPart = part(f, "ShopSign", V3(w - 3, 3.2, 0.4), CF(cx, 12.8, -0.25), d.signBg, M.SmoothPlastic)
	signPart:SetAttribute("Store", d.sign)
	local loc = Signage.ByShop[d.sign]
	if loc then
		Signage.Board(signPart, Enum.NormalId.Front, loc, { maxDist = 700 })
	else
		local sg = gui(signPart, Enum.NormalId.Front, Signage.PPS(3.2, 0.8), 0, 700)
		frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = d.signBg })
		label(sg, d.sign, { TextColor3 = d.signFg, Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1) })
	end
	if d.neon then
		neonOutline(f, CF(cx, 12.8, -0.56), w - 2.6, 3.5, d.signFg)
	end
	-- upper floors
	local wy0 = d.marquee and 19.5 or (d.columns and 25 or G + 2.4)
	local rows = d.floors or 0
	if rows >= 1 then
		K.windowGrid(gridPart, Enum.NormalId.Front, h - gridBase, wy0 - gridBase, h - 1.8 - gridBase, rows, math.max(2, math.floor(w / 9)), rng, 0.4)
	end
	if d.marquee then
		local mq = part(f, "Marquee", V3(w + 2, 3.6, 4), CF(cx, 16.4, -2.1), Color3.fromRGB(20, 20, 24), M.Metal)
		local msg = gui(mq, Enum.NormalId.Front, 20, 0, 700)
		frame(msg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(250, 246, 230) })
		label(msg, "SAT: VEGA vs KOVAC  -  WORLD TITLE", { Name = "MarqueeText", TextColor3 = Color3.fromRGB(20, 20, 24), Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15) })
		mq:SetAttribute("Kind", "Marquee")
		tag(mq, "CityScreen")
		for k = 0, 9 do
			ball(f, "MarqueeBulb", 0.4, CF(cx - w / 2 - 0.7 + k * (w + 1.4) / 9, 18.4, -4.0), Color3.fromRGB(255, 230, 150), M.Neon, { shadow = false })
		end
	end
	if d.columns then
		part(f, "MuseumSteps", V3(w - 8, 0.3, 2.6), CF(cx, SW_H + 0.15, -1.3), Color3.fromRGB(200, 196, 186), M.Limestone, { collide = true })
		part(f, "MuseumSteps", V3(w - 8, 0.3, 1.3), CF(cx, SW_H + 0.45, -0.65), Color3.fromRGB(200, 196, 186), M.Limestone, { collide = true })
		for k = 0, 4 do
			vcyl(f, "MuseumColumn", 22, 2.0, CF(d.x0 + 7 + k * (w - 14) / 4, SW_H + 0.6, -1.8), Color3.fromRGB(235, 228, 210), M.Limestone, { collide = true })
		end
		part(f, "Pediment", V3(w - 4, 2.2, 5.2), CF(cx, 24.5, -2.4), Color3.fromRGB(235, 228, 210), M.Limestone)
		part(f, "PedimentGable", V3(w - 8, 3.6, 1.6), CF(cx, 27.3, -1.2), Color3.fromRGB(235, 228, 210), M.Limestone, { class = "WedgePart" })
	end
	if d.poleSign then
		local px = d.x0 + 4
		part(f, "PoleSignPost", V3(0.8, 34 - SW_H, 0.8), CF(px, SW_H + (34 - SW_H) / 2, -2.2), K.POLE, M.Metal, { collide = true })
		local ps = part(f, "PoleSign", V3(1.2, 12, 4.6), CF(px, 28, -3.4), Color3.fromRGB(16, 20, 40), M.SmoothPlastic)
		local txt = table.concat(string.split(d.poleSign, ""), "\n")
		GymDecor.Sign(ps, Enum.NormalId.Left, txt, d.signFg, Color3.fromRGB(16, 20, 40), 20)
		GymDecor.Sign(ps, Enum.NormalId.Right, txt, d.signFg, Color3.fromRGB(16, 20, 40), 20)
		for _, s in ipairs({ -1, 1 }) do
			neonOutline(f, CF(px + s * 0.72, 28, -3.4) * ANG(0, RAD(90 * s), 0), 4.5, 11.9, d.signFg)
		end
		local vac = part(f, "VacancySign", V3(1.2, 2.2, 4.6), CF(px, 20.6, -3.4), Color3.fromRGB(16, 20, 40), M.SmoothPlastic)
		GymDecor.Sign(vac, Enum.NormalId.Left, "VACANCY", Color3.fromRGB(255, 80, 80), Color3.fromRGB(16, 20, 40), 30, nil, "signSub")
		GymDecor.Sign(vac, Enum.NormalId.Right, "VACANCY", Color3.fromRGB(255, 80, 80), Color3.fromRGB(16, 20, 40), 30, nil, "signSub")
	end
	if d.fireEscape then
		local x0 = cx + w * 0.14
		for fl = 1, d.floors or 1 do
			local y = G + 3.2 + (fl - 1) * S
			part(f, "FireLanding", V3(11, 0.25, 3.2), CF(x0, y, -1.7), Color3.fromRGB(34, 34, 38), M.DiamondPlate)
			part(f, "FireRail", V3(11, 0.15, 0.15), CF(x0, y + 3.4, -3.25), Color3.fromRGB(34, 34, 38), M.Metal)
			part(f, "FireRailPanel", V3(11, 3.2, 0.08), CF(x0, y + 1.7, -3.25), Color3.fromRGB(34, 34, 38), M.Metal, { transparency = 0.6, shadow = false })
			if fl > 1 then
				local a = V3(x0 - 4.5, y - S, -1.9)
				local b = V3(x0 + 3.5, y, -1.9)
				part(f, "FireStair", V3(2.4, 0.25, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Color3.fromRGB(34, 34, 38), M.DiamondPlate)
			end
		end
	end
	if rng:NextNumber() < 0.7 then
		part(f, "RoofUnit", V3(6, 3, 5), CF(cx + rng:NextNumber(-w / 4, w / 4), h + 2.1, depth * 0.6), Color3.fromRGB(196, 198, 202), M.Metal)
	end
	if d.floors and d.floors >= 1 and rng:NextNumber() < 0.5 then
		-- a rooftop water tank on the older blocks
		local tp = CF(cx - w * 0.25, h + 1.1, depth * 0.55)
		for _, o in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
			part(f, "TankLeg", V3(0.35, 5, 0.35), tp * CF(o[1], 2.5, o[2]), Color3.fromRGB(40, 42, 48), M.Metal)
		end
		vcyl(f, "WaterTank", 7, 6, tp * CF(0, 5, 0), Color3.fromRGB(120, 86, 60), M.WoodPlanks)
		part(f, "TankRoof", V3(6.4, 1.8, 6.4), tp * CF(0, 12.5, 0) * ANG(0, RAD(45), 0), Color3.fromRGB(60, 50, 44), M.Slate)
	end
	return body
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
	part(f, "LobbyCanopy", V3(9, 0.5, 6), CF(doorX, 10.2, -3.0), Color3.fromRGB(26, 28, 32), M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		part(f, "CanopyPost", V3(0.35, 9.6, 0.35), CF(doorX + s * 4.0, SW_H + 4.8, -5.7), Color3.fromRGB(26, 28, 32), M.Metal, { collide = true })
	end
	local plate = part(f, "AddressPlate", V3(4, 0.8, 0.08), CF(doorX, 10.9, -6.0), Color3.fromRGB(230, 200, 120), M.Metal)
	GymDecor.Sign(plate, Enum.NormalId.Front, "1 RIVERSIDE", Color3.fromRGB(40, 30, 10), Color3.fromRGB(230, 200, 120), 40)
	nightPoint(f, CF(doorX, 9.4, -3.2), Color3.fromRGB(255, 220, 170), 14, 0.9)
	local floors = d.floors or 4
	local cols = math.max(2, math.floor(w / 9))
	local wy0 = G + 2.4
	local rowH = (h - 1.8 - wy0) / floors
	for fl = 1, floors - 1 do
		local y = wy0 + fl * rowH
		for c = 1, cols - 2 do
			local x = d.x0 + (c + 0.5) / cols * w
			part(f, "Balcony", V3(w / cols * 0.75, 0.4, 3.2), CF(x, y, -1.6), concrete, M.Concrete)
			part(f, "BalconyRail", V3(w / cols * 0.75, 3.6, 0.12), CF(x, y + 2.0, -3.15), rail, M.Metal, { transparency = 0.2 })
		end
	end
	local fx = d.x0 - 1.8
	for fl = 1, floors - 1 do
		local y = wy0 + fl * rowH
		part(f, "FireLanding", V3(3.4, 0.25, 9), CF(fx, y, 16), rail, M.DiamondPlate)
		part(f, "FireRail", V3(0.12, 3.4, 9), CF(fx - 1.65, y + 1.8, 16), rail, M.Metal, { transparency = 0.5 })
		local a = V3(fx, y - rowH + 0.2, 12)
		local b = V3(fx, y, 20)
		if fl > 1 then
			part(f, "FireStair", V3(2.6, 0.25, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), rail, M.DiamondPlate)
		end
	end
	for _ = 1, 6 do
		local c = rng:NextInteger(0, cols - 1)
		local fl = rng:NextInteger(0, floors - 1)
		part(f, "ACUnit", V3(2.2, 1.4, 1.5), CF(d.x0 + (c + 0.5) / cols * w + 1.8, wy0 + fl * rowH + 1.6, -0.75), Color3.fromRGB(210, 210, 206), M.Metal)
	end
	local tank = V3(d.x1 - 10, h + 1.1, 28)
	for _, o in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
		part(f, "TankLeg", V3(0.35, 5, 0.35), CF(tank + V3(o[1], 2.5, o[2])), rail, M.Metal)
	end
	vcyl(f, "WaterTank", 7, 6.4, CF(tank + V3(0, 5, 0)), Color3.fromRGB(120, 86, 60), M.WoodPlanks)
	part(f, "TankRoof", V3(6.8, 1.8, 6.8), CF(tank + V3(0, 12.6, 0)) * ANG(0, RAD(45), 0), Color3.fromRGB(60, 50, 44), M.Slate)
	part(f, "StairHut", V3(8, 7, 8), CF(d.x0 + 8, h + 4.5, 30), concrete, M.Concrete, { collide = true })
	part(f, "TerraceRail", V3(w - 4, 3.4, 0.12), CF(cx, h + 2.8, 1.0), Color3.fromRGB(190, 220, 240), M.Glass, { transparency = 0.5 })
	site("ApartmentRoof", CFrame.lookAt(V3(cx, h + 1.1, 10), V3(cx, h + 1.1, -10)))
	site("ApartmentBanner", CFrame.lookAt(V3(d.x0 + 2.5 / cols * w, wy0 + 2.5 * rowH, -0.15), V3(d.x0 + 2.5 / cols * w, wy0 + 2.5 * rowH, -10)))
	site("HomeApartment", CFrame.lookAt(V3(doorX, SW_H, -3.4), V3(doorX, SW_H, -10)))
	-- the kerbside spot in front of the lobby where your car parks (CityVisuals): the near parking lane
	local kerbZ = CITY.MainStreet.frontS - CITY.MainStreet.parkLanes[2]
	site("ApartmentKerb", CF(doorX + 14, K.ROAD_Y, -kerbZ) * ANG(0, RAD(-90), 0))
	promptPart(f, "HomePrompt", V3(doorX, SW_H + 2.4, -1.8), "Enter apartment", "Riverside Apartments", { Action = "Home", Kind = "Apartment" }, Color3.fromRGB(255, 230, 170))
	part(f, "RealtyPost", V3(0.25, 5.4, 0.25), CF(doorX - 7, SW_H + 2.7, -4.6), C.white, M.Wood)
	local rs = part(f, "RealtySign", V3(3.6, 2.2, 0.1), CF(doorX - 7, SW_H + 4.8, -4.6), Color3.fromRGB(180, 30, 36), M.SmoothPlastic)
	GymDecor.Sign(rs, Enum.NormalId.Front, "PENTHOUSE\nAVAILABLE\nCITY REALTY", C.white, Color3.fromRGB(180, 30, 36), 40)
	rs:SetAttribute("Kind", "ForSale")
	rs:SetAttribute("Home", "Apartment")
	tag(rs, "CityScreen")
end

-- the gas station: canopy over three pump islands, the shop behind, the price pylon by the street
-- (row frame; the apron runs from the kerb to the shop at road level)
local function gasStation(f)
	local gx0, gx1 = CityShops.GAS.x0, CityShops.GAS.x1
	local cx = (gx0 + gx1) / 2
	local cz = 14
	local sw = CITY.MainStreet.frontS - CITY.MainStreet.z1 -- the sidewalk depth
	part(f, "GasApron", V3(gx1 - gx0, K.ROAD_Y, 40 + sw), CF(cx, K.ROAD_Y / 2, (40 - sw) / 2), Color3.fromRGB(150, 150, 152), M.Concrete, { collide = true })
	part(f, "GasCanopy", V3(60, 2.0, 34), CF(cx, 18.6, cz), C.white, M.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		part(f, "GasFascia", V3(60.3, 1.2, 0.2), CF(cx, 18.6, cz + s * 17.05), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
		part(f, "GasFascia", V3(0.2, 1.2, 34.3), CF(cx + s * 30.05, 18.6, cz), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	end
	for _, x in ipairs({ -18, 0, 18 }) do
		part(f, "CanopyPanel", V3(9, 0.1, 4), CF(cx + x, 17.55, cz), Color3.fromRGB(245, 248, 255), M.Neon, { shadow = false })
	end
	for _, x in ipairs({ -22, 22 }) do
		for _, z in ipairs({ -10, 10 }) do
			part(f, "GasPillar", V3(1.6, 17.6, 1.6), CF(cx + x, 8.8 + K.ROAD_Y, cz + z), C.white, M.SmoothPlastic, { collide = true })
		end
	end
	for _, x in ipairs({ -16, 0, 16 }) do
		part(f, "PumpIsland", V3(4, 0.6, 14), CF(cx + x, K.ROAD_Y + 0.3, cz), Color3.fromRGB(190, 186, 180), M.Concrete, { collide = true })
		for _, z in ipairs({ -3.4, 3.4 }) do
			local pump = part(f, "Pump", V3(2.2, 6.4, 1.6), CF(cx + x, K.ROAD_Y + 3.8, cz + z), Color3.fromRGB(200, 30, 36), M.SmoothPlastic, { collide = true })
			GymDecor.Sign(pump, Enum.NormalId.Front, "3.49", C.gold, C.black, 40)
			GymDecor.Sign(pump, Enum.NormalId.Back, "3.49", C.gold, C.black, 40)
		end
	end
	for _, x in ipairs({ -12, 12 }) do
		spotAt(f, CF(cx + x, 17.4, cz), Enum.NormalId.Bottom, Color3.fromRGB(240, 245, 255), 34, 1.6, 120)
	end
	-- the shop behind the pumps and the price pylon by the street
	local shopZ = 46
	part(f, "GasShop", V3(44, 14, 22), CF(cx, 7, shopZ), Color3.fromRGB(230, 230, 226), M.SmoothPlastic, { collide = true })
	part(f, "GasShopFascia", V3(44.4, 1.2, 22.4), CF(cx, 14.4, shopZ), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	local gs = part(f, "GasShopSign", V3(26, 3.2, 0.3), CF(cx, 11.6, shopZ - 11.15), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	Signage.Board(gs, Enum.NormalId.Front, "gas", { maxDist = 700 })
	local gw = part(f, "GasShopWindow", V3(30, 7, 0.1), CF(cx, 4.4, shopZ - 11.1), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.45, shadow = false })
	gw:SetAttribute("Shop", "FUEL & GO")
	part(f, "GasShopDoor", V3(CITY.Door.w, CITY.Door.h, 0.15), CF(cx + 10, K.ROAD_Y + CITY.Door.h / 2, shopZ - 11.2), Color3.fromRGB(30, 30, 34), M.Metal)
	site("Window_FUELGO", CFrame.lookAt(V3(cx - 8, K.ROAD_Y, shopZ - 12.6), V3(cx - 8, K.ROAD_Y, shopZ - 20)), { Shop = "FUEL & GO" })
	-- air / vacuum and an ice chest by the shop, a vacuum sign
	local ice = part(f, "IceChest", V3(5, 5, 3), CF(cx - 18, K.ROAD_Y + 2.5, shopZ - 12.8), Color3.fromRGB(230, 232, 236), M.SmoothPlastic, { collide = true })
	GymDecor.Sign(ice, Enum.NormalId.Front, "ICE", Color3.fromRGB(30, 90, 190), Color3.fromRGB(230, 232, 236), 40)
	vcyl(f, "AirPump", 4.6, 1.4, CF(cx + 19, K.ROAD_Y, shopZ - 13.5), Color3.fromRGB(40, 40, 44), M.Metal, { collide = true })
	local py = V3(gx0 + 8, K.ROAD_Y, -sw + 4)
	part(f, "PylonPole", V3(1.2, 24, 1.2), CF(py + V3(0, 12, 0)), C.steel, M.Metal, { collide = true })
	local pylon = part(f, "Pylon", V3(8, 8, 1.2), CF(py + V3(0, 28, 0)), Color3.fromRGB(200, 30, 36), M.SmoothPlastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local psg = gui(pylon, face, 20, 0, 900)
		frame(psg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 30, 36) })
		label(psg, "FUEL & GO", { TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.8, 0.36), Position = UDim2.fromScale(0.1, 0.05) })
		label(psg, "3.49", { TextColor3 = C.gold, Face = "screen", Size = UDim2.fromScale(0.8, 0.45), Position = UDim2.fromScale(0.1, 0.48) })
	end
	-- a couple of cars at the pumps
	K.car(f, ROW * CF(cx - 8, K.ROAD_Y, cz) * ANG(0, RAD(90), 0), K.CAR_COLORS[4], "suv")
	K.car(f, ROW * CF(cx + 8, K.ROAD_Y, cz + 0.5) * ANG(0, RAD(-90), 0), K.CAR_COLORS[2], "sedan")
end

------------------------------------------------------------------------
-- rows
------------------------------------------------------------------------
-- the south row: every shop of CityShops.SHOPS, the apartments' extras, the gas station
function CityShops.BuildRow(parent, rowCF, rowYaw, rng)
	ROW, ROW_YAW = rowCF, rowYaw or 0
	parent:SetAttribute("RowX", rowCF.Position.X)
	parent:SetAttribute("RowZ", rowCF.Position.Z)
	parent:SetAttribute("RowYaw", rowYaw or 0)
	for _, d in ipairs(CityShops.SHOPS) do
		local ok, err = pcall(shop, parent, d, rng)
		if not ok then
			warn("[CityShops] " .. tostring(d.sign) .. " failed: " .. tostring(err))
		end
		if d.apartments then
			pcall(apartmentExtras, parent, d, rng)
		end
	end
	local ok, err = pcall(gasStation, parent)
	if not ok then
		warn("[CityShops] gas station failed: " .. tostring(err))
	end
	ROW, ROW_YAW = CF(), 0
end

-- a row of simple mixed-use buildings (facade shops below flats / offices) between x0 and x1 of a
-- row frame: no interiors, no prompts, but every storefront carries a sign (own text / lockup)
local NORTH_SHOPS = {
	{ w = 44, floors = 2, sign = "RIVERSIDE REALTY", bg = Color3.fromRGB(20, 60, 110), fg = Color3.fromRGB(240, 240, 245), color = Color3.fromRGB(196, 176, 150), mat = M.Brick, awning = Color3.fromRGB(20, 60, 110) },
	{ w = 36, floors = 1, sign = "LUCKY DRAGON NOODLES", bg = Color3.fromRGB(170, 24, 30), fg = Color3.fromRGB(255, 220, 90), color = Color3.fromRGB(226, 220, 206), awning = Color3.fromRGB(170, 24, 30), neon = true },
	{ w = 40, floors = 3, sign = "MAIN ST PHARMACY", bg = Color3.fromRGB(30, 110, 60), fg = C.white, color = Color3.fromRGB(150, 146, 140), mat = M.Concrete, awning = Color3.fromRGB(30, 110, 60) },
	{ w = 30, floors = 1, sign = "GOLDEN GLOVE PAWN", bg = Color3.fromRGB(20, 20, 24), fg = C.gold, color = Color3.fromRGB(120, 60, 50), mat = M.Brick, awning = Color3.fromRGB(20, 20, 24), neon = true },
	{ w = 48, floors = 2, sign = "WCB SPORTS BAR", bg = Color3.fromRGB(14, 14, 18), fg = Color3.fromRGB(255, 205, 83), color = Color3.fromRGB(60, 56, 60), mat = M.Brick, awning = Color3.fromRGB(14, 14, 18), neon = true },
	{ w = 34, floors = 1, sign = "SUMMIT SPORTSWEAR", bg = Color3.fromRGB(240, 236, 226), fg = Color3.fromRGB(30, 30, 34), color = Color3.fromRGB(236, 232, 224), awning = Color3.fromRGB(30, 30, 34) },
	{ w = 42, floors = 3, sign = "CITY HARDWARE", bg = Color3.fromRGB(200, 90, 30), fg = C.white, color = Color3.fromRGB(176, 120, 90), mat = M.Brick, awning = Color3.fromRGB(200, 90, 30) },
	{ w = 38, floors = 2, sign = "BELLA'S FLOWERS", bg = Color3.fromRGB(240, 150, 180), fg = Color3.fromRGB(60, 30, 50), color = Color3.fromRGB(214, 200, 190), awning = Color3.fromRGB(240, 150, 180) },
	{ w = 46, floors = 2, sign = "DOWNTOWN DENTAL  ·  OPTICIANS", bg = Color3.fromRGB(240, 244, 248), fg = Color3.fromRGB(30, 90, 160), color = Color3.fromRGB(190, 196, 206), mat = M.Concrete, awning = Color3.fromRGB(30, 90, 160) },
	{ w = 36, floors = 1, sign = "RING ROAD BIKES", bg = Color3.fromRGB(30, 30, 34), fg = Color3.fromRGB(80, 220, 110), color = Color3.fromRGB(96, 96, 100), mat = M.Metal, awning = Color3.fromRGB(80, 220, 110) },
	{ w = 44, floors = 3, sign = "THE CORNER BOOKSHOP", bg = Color3.fromRGB(60, 40, 30), fg = Color3.fromRGB(255, 230, 190), color = Color3.fromRGB(150, 90, 70), mat = M.Brick, awning = Color3.fromRGB(60, 40, 30) },
	{ w = 40, floors = 2, sign = "CHAMPION CLEANERS", bg = Color3.fromRGB(40, 110, 200), fg = C.white, color = Color3.fromRGB(220, 226, 232), awning = Color3.fromRGB(40, 110, 200) },
	{ w = 50, floors = 3, sign = "HOTEL MAJESTIC", bg = Color3.fromRGB(26, 22, 30), fg = Color3.fromRGB(230, 200, 120), color = Color3.fromRGB(206, 190, 170), mat = M.Limestone, awning = Color3.fromRGB(26, 22, 30), neon = true, lobby = true },
}
CityShops.NORTH_SHOPS = NORTH_SHOPS

-- gaps = { { a, b } } row-local x ranges no building may cover (the streets crossing the row)
function CityShops.BuildNorthRow(parent, rowCF, rowYaw, x0, x1, rng, gaps)
	ROW, ROW_YAW = rowCF, rowYaw or 0
	parent:SetAttribute("RowX", rowCF.Position.X)
	parent:SetAttribute("RowZ", rowCF.Position.Z)
	parent:SetAttribute("RowYaw", rowYaw or 0)
	local x = x0
	local i = 0
	while true do
		i += 1
		local d = NORTH_SHOPS[(i - 1) % #NORTH_SHOPS + 1]
		for _, g in ipairs(gaps or {}) do
			if x < g[2] and x + d.w > g[1] then
				x = g[2] + 1.2
			end
		end
		if x + d.w > x1 then
			break
		end
		local gap = (i % 3 == 0) and 6 or 0
		local m = K.building(parent, ROW * CF(x + d.w / 2, 0, 0), d.w, 40 + (i % 2) * 6, d.floors, {
			color = d.color, mat = d.mat, sign = d.sign, signBg = d.bg, signFg = d.fg, awning = d.awning, rng = rng, lit = 0.4, retail = not d.lobby,
			name = "RowBuilding", tank = (i % 4 == 1), units = 1,
		})
		m:SetAttribute("Sign", d.sign)
		if d.neon then
			neonOutline(parent, CF(x + d.w / 2, G - 1.7, -0.56), d.w - 2.6 - 0.4, 3.5, d.fg)
		end
		x += d.w + 1.2 + gap
	end
	ROW, ROW_YAW = CF(), 0
end

CityShops.Interiors = INTERIOR
return CityShops
