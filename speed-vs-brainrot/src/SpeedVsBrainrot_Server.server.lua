--[[
	SPEED VS BRAINROT  -  Server Script
	Put this in: ServerScriptService  (as a normal Script)
	Pair it with (both in StarterPlayer > StarterPlayerScripts):
	  SpeedVsBrainrot_HUD    (LocalScript: buttons, menus, cash pops, egg hatching)
	  SpeedVsBrainrot_World  (LocalScript: smooth moving obstacles, spinning cash + eggs,
	                          running animations, the "you got hit" animation, lighting per map)

	The whole world is built by this script when the game starts.

	HOW IT PLAYS
	  1. There are MAPS. Every map has its own floating start island, its own zones and
	     its own BOSS. Map 1 pays 1 to 1K trophies per zone, Map 2 pays 1.5K to 500K.
	     Beat the last zone of a map to unlock the next one (add more maps in MAPS below).
	  2. CASH is only for speed: stand on the GREEN PAD to buy speed.
	     TROPHIES are only for eggs: every island has 4 eggs. Pets multiply your cash.
	     Fuse 3 of the same pet into a better one.
	  3. Cross the RED LINE and your full speed turns on. Speed is relative: every zone has
	     a "pace", so the same Speed makes you run faster in a harder zone (and so does its boss).
	  4. Every zone needs a certain Speed to leave it (shown on its golden gate).
	  5. Get hit by an obstacle or caught by the boss and you're sent back to the start.
	  6. Rebirth when you're fast enough: resets cash + speed for a cash multiplier.
	     PRESTIGE once you reach the final zone of the final map: start over from Map 1
	     with a permanent trophy multiplier (you keep pets and rebirths).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

------------------------------------------------------------------------
-- CONFIG  (tweak these to balance the game)
------------------------------------------------------------------------
local CONFIG = {
	ZoneWidth = 140,          -- every zone, including the start zones, is this wide...
	ZoneLength = 400,         -- ...and this long (long zones = more room to pull away from the boss)
	IslandLength = 200,       -- the start islands stay this long (they sit at the end of their slot)
	MapGap = 1,               -- empty sky (in zone lengths) between one map's end and the next island

	BaseWalkSpeed = 16,
	StartZoneWalkSpeed = 16,  -- everyone walks at this speed until they cross the red line
	WalkPerDoubling = 14,     -- every time your Speed doubles you run this much faster (times the zone's pace)
	MaxWalkSpeed = 340,       -- nobody runs faster than this
	MaxSpeed = 1e9,           -- the most Speed you can buy
	SpeedCostLinear = 0.05,   -- price of one point of Speed = 1 + Speed * linear + (Speed / curve)^2
	SpeedCostCurve = 80,
	PadBuyInterval = 0.2,     -- while you stand on the green pad, it buys speed this often

	CashPerZone = 20,         -- cash pickups lying in each zone
	CashRespawnTime = 8,      -- seconds before picked-up cash comes back

	BossHeadStart = 45,       -- how far behind you the boss appears
	BossGraceTime = 0.8,      -- seconds the boss waits before it starts running
	BossLeash = 60,           -- if you get farther ahead than this, the boss speeds up to stay close
	BossTick = 0.1,           -- seconds between boss brain updates

	HitTime = 0.8,            -- after a hit you tumble for this long, then go back to the start

	PetSlots = 3,             -- your best pets are equipped automatically

	WinBonus = 100000,        -- cash for beating a map (times your multiplier and the map number)
	RebirthSpeedBase = 300,   -- Speed you need for your first rebirth...
	RebirthSpeedGrowth = 1.8, -- ...times this for each rebirth after that
	RebirthBonus = 0.5,       -- +0.5x cash per rebirth
	PrestigeTrophyBonus = 1,  -- +1x trophies per prestige

	KillHeight = -40,         -- fall below this and you're sent back to the start

	CashGamepassId = 0,       -- your "3x Cash" gamepass id (0 = off)

	-- ADMINS: the game's owner (you) is always an admin and can add more admins
	-- from the admin panel in game. Put extra owner UserIds here if you want.
	OwnerUserIds = {},

	LeaderboardRefresh = 60,  -- seconds between leaderboard updates
	RespawnTime = 2,
	DataStoreName = "SpeedVsBrainrot_v2",
}

------------------------------------------------------------------------
-- MAPS  (each map = its own island + zones + ONE boss + 4 eggs)
--   zone fields:
--     cash     = what each cash pickup in the zone is worth
--     trophies = trophies for making it out of this zone (shown on the gate at its end)
--     need     = Speed you need to get into this zone (the boss is tuned to it)
--     pace     = how much faster the same Speed runs here (harder zone = higher pace)
--     theme    = which decorations + obstacles the zone gets
--   egg fields: price = trophies to hatch one; pet bonus = extra cash % (Golden 3x, Rainbow 9x)
--   Add a third map by copying a block (and its themes) - trophies keep going up.
------------------------------------------------------------------------
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local MAPS = {
	{
		name = "Map 1", title = "Brainrot Skylands",
		boss = { name = "Il Grande Zoomerone", size = 12, style = "round",
			body = rgb(105, 50, 175), accent = rgb(0, 230, 255) },
		zones = {
			{ name = "Green Meadow",  theme = "meadow",  cash = 1,    trophies = 1,    need = 0,    pace = 1.00,
			  floor = rgb(100, 205, 85),  wall = rgb(125, 82, 48),  accent = rgb(140, 255, 110) },
			{ name = "Sandy Desert",  theme = "desert",  cash = 3,    trophies = 3,    need = 10,   pace = 1.02,
			  floor = rgb(240, 210, 125), wall = rgb(195, 145, 75), accent = rgb(255, 200, 70) },
			{ name = "Icy Tundra",    theme = "ice",     cash = 8,    trophies = 8,    need = 30,   pace = 1.04,
			  floor = rgb(205, 235, 255), wall = rgb(120, 180, 230), accent = rgb(120, 220, 255) },
			{ name = "Toxic Swamp",   theme = "swamp",   cash = 20,   trophies = 20,   need = 70,   pace = 1.06,
			  floor = rgb(105, 150, 60),  wall = rgb(65, 95, 40),   accent = rgb(170, 255, 60) },
			{ name = "Lava Lands",    theme = "lava",    cash = 50,   trophies = 45,   need = 150,  pace = 1.08,
			  floor = rgb(95, 60, 55),    wall = rgb(60, 35, 30),   accent = rgb(255, 120, 30) },
			{ name = "Candy Kingdom", theme = "candy",   cash = 120,  trophies = 90,   need = 300,  pace = 1.10,
			  floor = rgb(255, 175, 215), wall = rgb(230, 100, 165), accent = rgb(255, 110, 200) },
			{ name = "Neon City",     theme = "neon",    cash = 300,  trophies = 170,  need = 600,  pace = 1.12,
			  floor = rgb(50, 50, 80),    wall = rgb(28, 28, 48),   accent = rgb(0, 255, 230) },
			{ name = "Crystal Caves", theme = "crystal", cash = 750,  trophies = 300,  need = 1100, pace = 1.14,
			  floor = rgb(115, 85, 165),  wall = rgb(62, 42, 102),  accent = rgb(200, 120, 255) },
			{ name = "Storm Peaks",   theme = "storm",   cash = 2000, trophies = 550,  need = 2000, pace = 1.16,
			  floor = rgb(125, 130, 145), wall = rgb(70, 72, 86),   accent = rgb(255, 235, 60) },
			{ name = "The Void",      theme = "void",    cash = 5000, trophies = 1000, need = 3500, pace = 1.18,
			  floor = rgb(35, 25, 50),    wall = rgb(16, 10, 26),   accent = rgb(170, 60, 255) },
		},
		eggs = {
			{ name = "Grass Egg", price = 20, color = rgb(120, 225, 90), spots = rgb(255, 255, 255), pets = {
				{ name = "Leafy Bunny",   chance = 60, bonus = 10,  body = rgb(245, 245, 245), accent = rgb(120, 220, 90), style = "bunny" },
				{ name = "Clover Pup",    chance = 28, bonus = 20,  body = rgb(160, 215, 110), accent = rgb(80, 160, 60), style = "pup" },
				{ name = "Sunny Bee",     chance = 10, bonus = 45,  body = rgb(255, 210, 60), accent = rgb(45, 35, 25), style = "bee" },
				{ name = "Daisy Dragon",  chance = 2,  bonus = 100, body = rgb(250, 250, 240), accent = rgb(255, 205, 40), style = "dragon" },
			} },
			{ name = "Sand Egg", price = 100, color = rgb(240, 205, 120), spots = rgb(200, 140, 70), pets = {
				{ name = "Cactus Cat",    chance = 60, bonus = 40,  body = rgb(110, 190, 90), accent = rgb(255, 120, 170), style = "cat" },
				{ name = "Dune Fox",      chance = 28, bonus = 75,  body = rgb(240, 150, 70), accent = rgb(255, 255, 255), style = "fox" },
				{ name = "Golden Scarab", chance = 10, bonus = 150, body = rgb(255, 200, 50), accent = rgb(60, 160, 120), style = "beetle" },
				{ name = "Sphinx Kitty",  chance = 2,  bonus = 320, body = rgb(235, 190, 110), accent = rgb(40, 90, 200), style = "cat" },
			} },
			{ name = "Ice Egg", price = 500, color = rgb(180, 230, 255), spots = rgb(255, 255, 255), pets = {
				{ name = "Snow Pup",      chance = 60, bonus = 150,  body = rgb(240, 248, 255), accent = rgb(120, 190, 255), style = "pup" },
				{ name = "Frost Penguin", chance = 28, bonus = 280,  body = rgb(40, 50, 70), accent = rgb(255, 255, 255), style = "penguin" },
				{ name = "Ice Dragon",    chance = 10, bonus = 550,  body = rgb(140, 210, 255), accent = rgb(255, 255, 255), style = "dragon" },
				{ name = "Aurora Wisp",   chance = 2,  bonus = 1200, body = rgb(120, 255, 200), accent = rgb(200, 120, 255), style = "wisp" },
			} },
			{ name = "Lava Egg", price = 1000, color = rgb(255, 110, 40), spots = rgb(255, 230, 80), pets = {
				{ name = "Magma Slime",   chance = 60, bonus = 400,  body = rgb(255, 90, 30), accent = rgb(255, 220, 80), style = "slime" },
				{ name = "Ember Fox",     chance = 28, bonus = 750,  body = rgb(200, 50, 30), accent = rgb(255, 180, 40), style = "fox" },
				{ name = "Phoenix Chick", chance = 10, bonus = 1500, body = rgb(255, 160, 40), accent = rgb(255, 60, 30), style = "bird" },
				{ name = "Volcano Bear",  chance = 2,  bonus = 3500, body = rgb(60, 40, 40), accent = rgb(255, 110, 30), style = "bear" },
			} },
		},
	},
	{
		name = "Map 2", title = "Turbo Badlands",
		boss = { name = "Tralalero Turbino", size = 15, style = "boxy",
			body = rgb(30, 120, 200), accent = rgb(255, 70, 40) },
		zones = {
			{ name = "Jungle Run",    theme = "jungle",   cash = 12000,   trophies = 1500,   need = 6000,   pace = 1.24,
			  floor = rgb(70, 160, 70),   wall = rgb(90, 60, 35),   accent = rgb(255, 210, 60) },
			{ name = "Haunted Woods", theme = "haunted",  cash = 30000,   trophies = 5000,   need = 11000,  pace = 1.28,
			  floor = rgb(70, 60, 90),    wall = rgb(40, 32, 55),   accent = rgb(150, 255, 120) },
			{ name = "Robo Factory",  theme = "factory",  cash = 80000,   trophies = 15000,  need = 20000,  pace = 1.32,
			  floor = rgb(150, 155, 165), wall = rgb(80, 82, 92),   accent = rgb(255, 170, 30) },
			{ name = "Outer Space",   theme = "space",    cash = 200000,  trophies = 45000,  need = 35000,  pace = 1.36,
			  floor = rgb(40, 45, 80),    wall = rgb(20, 22, 45),   accent = rgb(120, 200, 255) },
			{ name = "Rainbow Road",  theme = "rainbow",  cash = 500000,  trophies = 150000, need = 60000,  pace = 1.42,
			  floor = rgb(245, 245, 255), wall = rgb(150, 120, 230), accent = rgb(255, 120, 220) },
			{ name = "Inferno Core",  theme = "inferno",  cash = 1300000, trophies = 500000, need = 100000, pace = 1.50,
			  floor = rgb(70, 30, 30),    wall = rgb(40, 15, 15),   accent = rgb(255, 80, 20) },
		},
		eggs = {
			{ name = "Jungle Egg", price = 2500, color = rgb(70, 190, 90), spots = rgb(255, 220, 70), pets = {
				{ name = "Tiki Bear",     chance = 60, bonus = 1200,  body = rgb(160, 110, 60), accent = rgb(255, 210, 60), style = "bear" },
				{ name = "Parrot Pal",    chance = 28, bonus = 2200,  body = rgb(230, 50, 50), accent = rgb(60, 140, 255), style = "bird" },
				{ name = "Vine Slime",    chance = 10, bonus = 4500,  body = rgb(90, 200, 80), accent = rgb(255, 120, 200), style = "slime" },
				{ name = "Jade Dragon",   chance = 2,  bonus = 10000, body = rgb(40, 170, 110), accent = rgb(255, 215, 60), style = "dragon" },
			} },
			{ name = "Candy Egg", price = 10000, color = rgb(255, 150, 210), spots = rgb(130, 220, 255), pets = {
				{ name = "Gummy Bear",       chance = 60, bonus = 3500,  body = rgb(255, 80, 120), accent = rgb(255, 200, 220), style = "bear" },
				{ name = "Cotton Cloud",     chance = 28, bonus = 6500,  body = rgb(255, 220, 245), accent = rgb(180, 220, 255), style = "cloud" },
				{ name = "Lollipop Unicorn", chance = 10, bonus = 13000, body = rgb(255, 255, 255), accent = rgb(255, 120, 200), style = "unicorn" },
				{ name = "Sugar Dragon",     chance = 2,  bonus = 30000, body = rgb(255, 170, 220), accent = rgb(120, 220, 255), style = "dragon" },
			} },
			{ name = "Robo Egg", price = 50000, color = rgb(60, 60, 110), spots = rgb(0, 255, 230), pets = {
				{ name = "Robo Kitty",    chance = 60, bonus = 10000, body = rgb(180, 190, 210), accent = rgb(0, 255, 230), style = "robot" },
				{ name = "Glitch Bat",    chance = 28, bonus = 19000, body = rgb(70, 40, 110), accent = rgb(255, 40, 200), style = "bat" },
				{ name = "Neon Dragon",   chance = 10, bonus = 38000, body = rgb(30, 30, 60), accent = rgb(0, 255, 230), style = "dragon" },
				{ name = "Mecha Unicorn", chance = 2,  bonus = 90000, body = rgb(200, 205, 220), accent = rgb(255, 60, 120), style = "unicorn" },
			} },
			{ name = "Cosmic Egg", price = 250000, color = rgb(40, 20, 70), spots = rgb(190, 80, 255), pets = {
				{ name = "Void Wisp",       chance = 60, bonus = 30000,  body = rgb(140, 60, 255), accent = rgb(230, 200, 255), style = "wisp" },
				{ name = "Star Bunny",      chance = 28, bonus = 55000,  body = rgb(255, 245, 190), accent = rgb(255, 200, 40), style = "bunny" },
				{ name = "Shadow Wolf",     chance = 10, bonus = 110000, body = rgb(30, 25, 45), accent = rgb(190, 80, 255), style = "wolf" },
				{ name = "Cosmic Overlord", chance = 2,  bonus = 280000, body = rgb(20, 10, 40), accent = rgb(255, 215, 60), style = "overlord" },
			} },
		},
	},
}

------------------------------------------------------------------------
-- ZONE BOSSES  (every zone has its own boss that chases you through it;
-- the last zone of each map is the map's big boss above)
--   style = "round" or "boxy" body, hat = crown / horns / fin / antenna / leaf / cap / none
--   size grows a little every zone, and each boss is faster than the one before
------------------------------------------------------------------------
local ZONE_BOSSES = {
	{ -- Map 1
		{ name = "Tung Tung Sahur",       style = "boxy",  hat = "none",    body = rgb(175, 125, 75),  accent = rgb(95, 60, 35) },
		{ name = "Brr Brr Patapim",       style = "round", hat = "leaf",    body = rgb(110, 175, 80),  accent = rgb(150, 100, 60) },
		{ name = "Lirili Larila",         style = "round", hat = "antenna", body = rgb(150, 155, 165), accent = rgb(80, 170, 90) },
		{ name = "Bombardiro Crocodilo",  style = "boxy",  hat = "fin",     body = rgb(85, 125, 75),   accent = rgb(60, 70, 60) },
		{ name = "Trippi Troppi",         style = "round", hat = "horns",   body = rgb(255, 130, 60),  accent = rgb(200, 70, 40) },
		{ name = "Ballerina Cappuccina",  style = "round", hat = "crown",   body = rgb(255, 170, 210), accent = rgb(130, 85, 60), eyes = rgb(255, 60, 160) },
		{ name = "Chimpanzini Bananini",  style = "round", hat = "leaf",    body = rgb(255, 225, 80),  accent = rgb(120, 85, 50) },
		{ name = "Cappuccino Assassino",  style = "boxy",  hat = "cap",     body = rgb(120, 80, 55),   accent = rgb(30, 30, 35) },
		{ name = "Bombombini Gusini",     style = "round", hat = "fin",     body = rgb(240, 240, 245), accent = rgb(255, 160, 40) },
	},
	{ -- Map 2
		{ name = "Frigo Camelo",          style = "boxy",  hat = "antenna", body = rgb(230, 240, 250), accent = rgb(200, 160, 100), eyes = rgb(60, 200, 255) },
		{ name = "Glorbo Fruttodrillo",   style = "round", hat = "horns",   body = rgb(140, 70, 190),  accent = rgb(90, 200, 90) },
		{ name = "La Vaca Saturno",       style = "boxy",  hat = "horns",   body = rgb(245, 245, 245), accent = rgb(30, 30, 35), eyes = rgb(255, 210, 60) },
		{ name = "Garamararam",           style = "round", hat = "antenna", body = rgb(60, 110, 230),  accent = rgb(255, 200, 60) },
		{ name = "Bobrito Bandito",       style = "boxy",  hat = "cap",     body = rgb(150, 100, 60),  accent = rgb(200, 40, 50) },
	},
}
for m, map in ipairs(MAPS) do
	map.boss.hat = map.boss.hat or (map.boss.style == "boxy" and "fin" or "crown")
	map.boss.eyes = map.boss.eyes or (map.boss.style == "boxy" and map.boss.accent or nil)
	local n = #map.zones
	for j, zone in ipairs(map.zones) do
		local def = (j < n and ZONE_BOSSES[m] and ZONE_BOSSES[m][j]) or map.boss
		if def ~= map.boss then
			def.size = def.size or math.floor((map.boss.size * (0.72 + 0.25 * j / n)) * 10) / 10
		end
		zone.boss = def
	end
end

local PET_TIERS = {
	{ name = "",        mult = 1 },
	{ name = "Golden",  mult = 3 },
	{ name = "Rainbow", mult = 9 },
}

-- rarity names + colors (by the pet's place in its egg)
local RARITY = {
	{ name = "Common",    color = rgb(235, 235, 235) },
	{ name = "Rare",      color = rgb(90, 180, 255) },
	{ name = "Epic",      color = rgb(200, 110, 255) },
	{ name = "Legendary", color = rgb(255, 200, 40) },
}

local W, L = CONFIG.ZoneWidth, CONFIG.ZoneLength
local HALF_W = W / 2
local FLOOR_Y = 0.5             -- top of the floor

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function fmt(n)
	n = math.floor(n or 0)
	local suffixes = { "", "K", "M", "B", "T", "Qd", "Qn" }
	local i, v = 1, n
	while math.abs(v) >= 1000 and i < #suffixes do
		v = v / 1000
		i += 1
	end
	if i == 1 then return tostring(n) end
	return string.format("%.1f%s", v, suffixes[i])
end

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props.Shape then p.Shape = props.Shape end
	if props.Size then p.Size = props.Size end
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Shape" and k ~= "Size" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function newWedge(props)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Material = Enum.Material.SmoothPlastic
	if props.Size then w.Size = props.Size end
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Size" then
			w[k] = v
		end
	end
	w.Parent = props.Parent
	return w
end

-- Classic Roblox studs on a face of a part (built in, no image needed)
local SURFACE_OF = {
	[Enum.NormalId.Top] = "TopSurface",
	[Enum.NormalId.Bottom] = "BottomSurface",
	[Enum.NormalId.Left] = "LeftSurface",
	[Enum.NormalId.Right] = "RightSurface",
	[Enum.NormalId.Front] = "FrontSurface",
	[Enum.NormalId.Back] = "BackSurface",
}
local function addStuds(target, face)
	target.Material = Enum.Material.Plastic
	target[SURFACE_OF[face or Enum.NormalId.Top]] = Enum.SurfaceType.Studs
end

-- studs on the sides + bottom (cliffs, island chunks)
local function studSides(target)
	target.Material = Enum.Material.Plastic
	for _, surface in ipairs({ "LeftSurface", "RightSurface", "FrontSurface", "BackSurface", "BottomSurface" }) do
		target[surface] = Enum.SurfaceType.Studs
	end
end

-- Sign text on one face of a part. lines = { {text, color, weight}, ... }
-- pps = pixels per stud: lower = bigger text (text can't go above 100px, so big signs need a low value)
local function addSign(target, face, lines, pps)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps or 20
	sg.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = sg
	local total = 0
	for _, line in ipairs(lines) do total += (line.weight or 1) end
	for i, line in ipairs(lines) do
		local tl = Instance.new("TextLabel")
		tl.LayoutOrder = i
		tl.Size = UDim2.fromScale(1, (line.weight or 1) / total)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.FredokaOne
		tl.TextScaled = true
		tl.Text = line.text
		tl.TextColor3 = line.color or Color3.new(1, 1, 1)
		tl.TextStrokeTransparency = 0
		tl.Parent = sg
	end
	sg.Parent = target
	return sg
end

local function addBillboard(adornee, lines, offsetY, maxDist, width, lineH)
	width = width or 220
	lineH = lineH or 22
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, width, 0, lineH * #lines)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = maxDist or 160
	bb.LightInfluence = 0
	bb.Adornee = adornee
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bb
	for i, line in ipairs(lines) do
		local tl = Instance.new("TextLabel")
		tl.LayoutOrder = i
		tl.Size = UDim2.new(1, 0, 0, lineH)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.FredokaOne
		tl.TextScaled = true
		tl.Text = line.text
		tl.TextColor3 = line.color
		tl.TextStrokeTransparency = 0
		tl.Parent = bb
	end
	bb.Parent = adornee
	return bb
end

-- Billboard sized in studs (shrinks with distance like a real sign)
local function studsBillboard(adornee, lines, offsetY, widthStuds, lineStuds, maxDist)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(widthStuds, 0, lineStuds * #lines, 0)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = maxDist or 200
	bb.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bb
	for i, line in ipairs(lines) do
		local tl = Instance.new("TextLabel")
		tl.LayoutOrder = i
		tl.Size = UDim2.fromScale(1, 1 / #lines)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.FredokaOne
		tl.TextScaled = true
		tl.Text = line.text
		tl.TextColor3 = line.color
		tl.TextStrokeTransparency = 0
		tl.Parent = bb
	end
	bb.Parent = adornee
	return bb
end

------------------------------------------------------------------------
-- WORLD LAYOUT: every map is a run of zones along +Z. Zone slot g covers
-- z = g*L .. (g+1)*L. Slot map.startG is its start island, then its zones,
-- then a gap of open sky before the next map's island.
------------------------------------------------------------------------
local ZONE_AT = {} -- [slot] = { map = map, m = map number, j = zone number in the map (0 = start island), zone = zone def }
local ZONE_LIST = {} -- every zone in play order: { g = slot, map, m, j, zone }
do
	local g = 0
	for m, map in ipairs(MAPS) do
		map.index = m
		map.startG = g
		map.oz = g * L                     -- z where the island starts
		map.redLineZ = map.oz + L - 2       -- cross this and your full speed turns on
		ZONE_AT[g] = { map = map, m = m, j = 0 }
		for j, zone in ipairs(map.zones) do
			local info = { g = g + j, map = map, m = m, j = j, zone = zone }
			ZONE_AT[g + j] = info
			table.insert(ZONE_LIST, info)
			zone.g = g + j
			zone.map = map
			zone.j = j
		end
		map.lastG = g + #map.zones
		map.endZ = (map.lastG + 1) * L
		g = map.lastG + 1 + CONFIG.MapGap
	end
end
local FINAL_G = MAPS[#MAPS].lastG -- reach this zone to unlock PRESTIGE
local WORLD_END = MAPS[#MAPS].endZ

-- Speed -> how fast you run. Speed is relative: the zone's pace multiplies it,
-- so 20K Speed runs faster in a harder zone than in an easy one.
local function walkFor(speed, pace)
	local bonus = CONFIG.WalkPerDoubling * math.log(1 + math.max(0, speed) / 8, 2) * (pace or 1)
	return math.min(CONFIG.MaxWalkSpeed, CONFIG.BaseWalkSpeed + bonus)
end

-- the boss in a zone is tuned so the zone's "need" Speed just about outruns it
local function bossSpeedIn(zone, frac)
	return walkFor(zone.need, zone.pace) * (0.88 + 0.09 * math.clamp(frac, 0, 1))
end

local function getPlayerFromHit(hit)
	local model = hit and hit.Parent
	if not model then return nil end
	local plr = Players:GetPlayerFromCharacter(model)
	if not plr and model.Parent then
		plr = Players:GetPlayerFromCharacter(model.Parent) -- accessories
	end
	return plr
end

-- Pet helpers -------------------------------------------------------
local PET_BY_NAME = {}
local EGG_BY_NAME = {}
for m, map in ipairs(MAPS) do
	for e, egg in ipairs(map.eggs) do
		local total = 0
		for r, pet in ipairs(egg.pets) do
			total += pet.chance
			pet.egg = egg.name
			pet.rarity = r
			PET_BY_NAME[pet.name] = pet
		end
		egg.totalChance = total
		egg.map = m
		egg.order = e
		egg.design = egg.design or string.lower(string.match(egg.name, "^(%a+)") or "classic")
		EGG_BY_NAME[egg.name] = egg
	end
end

local function petKey(name, tier)
	return name .. "|" .. tier
end

local function splitKey(key)
	local name, tier = string.match(key, "^(.+)|(%d)$")
	return name, tonumber(tier)
end

local function petBonusOf(key)
	local name, tier = splitKey(key)
	local def = name and PET_BY_NAME[name]
	local t = tier and PET_TIERS[tier]
	if not def or not t then return 0 end
	return def.bonus * t.mult
end

------------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "SVB_Remotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local NotifyRemote = makeRemote("Notify")
local RebirthRemote = makeRemote("Rebirth")
local PrestigeRemote = makeRemote("Prestige")
local TeleportRemote = makeRemote("Teleport")
local FuseRemote = makeRemote("Fuse")
local PetHatchedRemote = makeRemote("PetHatched")
local CashFxRemote = makeRemote("CashFx")
local HitRemote = makeRemote("Hit")             -- (message) you got hit: play the tumble
local ZoneClearedRemote = makeRemote("ZoneCleared") -- (zoneName, trophies, mapName)
local AdminRemote = makeRemote("Admin")             -- admin panel buttons (checked on the server)
local AnnounceRemote = makeRemote("Announce")       -- (message, from) big banner for everyone
local EventMultiplier = 1                           -- admin cash event (x2, x5, ...)

local function notify(plr, text, color)
	NotifyRemote:FireClient(plr, text, color or Color3.new(1, 1, 1))
end
local function notifyAll(text, color)
	NotifyRemote:FireAllClients(text, color or Color3.new(1, 1, 1))
end

-- Pet info for the client (colors, looks, rarity)
local PetInfo = Instance.new("Folder")
PetInfo.Name = "SVB_Pets"
for _, map in ipairs(MAPS) do
	for _, egg in ipairs(map.eggs) do
		for _, pet in ipairs(egg.pets) do
			local c = Instance.new("Configuration")
			c.Name = pet.name
			c:SetAttribute("Bonus", pet.bonus)
			c:SetAttribute("Body", pet.body)
			c:SetAttribute("Accent", pet.accent)
			c:SetAttribute("Style", pet.style)
			c:SetAttribute("Icon", pet.style)
			c:SetAttribute("Egg", egg.name)
			c:SetAttribute("EggColor", egg.color)
			c:SetAttribute("EggSpots", egg.spots)
			c:SetAttribute("EggDesign", egg.design)
			c:SetAttribute("Chance", pet.chance)
			c:SetAttribute("Rarity", RARITY[pet.rarity].name)
			c:SetAttribute("RarityColor", RARITY[pet.rarity].color)
			c.Parent = PetInfo
		end
	end
end
PetInfo.Parent = ReplicatedStorage

-- Egg info for the client (price, map, where the egg stands)
local EggInfo = Instance.new("Folder")
EggInfo.Name = "SVB_Eggs"
local EggConfigs = {}
for _, map in ipairs(MAPS) do
	for _, egg in ipairs(map.eggs) do
		local c = Instance.new("Configuration")
		c.Name = egg.name
		c:SetAttribute("Order", (egg.map - 1) * 10 + egg.order)
		c:SetAttribute("Price", egg.price)
		c:SetAttribute("Map", egg.map)
		c:SetAttribute("UnlockZone", 0)
		c:SetAttribute("Color", egg.color)
		c:SetAttribute("Spots", egg.spots)
		c:SetAttribute("Design", egg.design)
		c.Parent = EggInfo
		EggConfigs[egg.name] = c
	end
end
EggInfo.Parent = ReplicatedStorage

-- Map info for the client (teleport menu, lighting per map)
local MapInfo = Instance.new("Folder")
MapInfo.Name = "SVB_Maps"
for m, map in ipairs(MAPS) do
	local c = Instance.new("Configuration")
	c.Name = "Map" .. m
	c:SetAttribute("Index", m)
	c:SetAttribute("Title", map.title)
	c:SetAttribute("Boss", map.boss.name)
	c:SetAttribute("Z0", map.oz)
	c:SetAttribute("Z1", map.endZ)
	c:SetAttribute("Color", map.boss.accent)
	c.Parent = MapInfo
end
MapInfo.Parent = ReplicatedStorage

------------------------------------------------------------------------
-- LIGHTING: warm sun, soft haze, a little bloom so neon glows
------------------------------------------------------------------------
for _, name in ipairs({ "SVB_Atmosphere", "SVB_Bloom", "SVB_SunRays", "SVB_Color", "SVB_Sky" }) do
	local old = Lighting:FindFirstChild(name)
	if old then old:Destroy() end
end
Lighting.ClockTime = 14.6
Lighting.GeographicLatitude = 35
Lighting.Brightness = 2.6
Lighting.Ambient = rgb(95, 95, 115)
Lighting.OutdoorAmbient = rgb(145, 145, 160)
Lighting.ColorShift_Top = rgb(255, 240, 215)
Lighting.ShadowSoftness = 0.25
Lighting.GlobalShadows = true
Lighting.EnvironmentDiffuseScale = 0.9
Lighting.EnvironmentSpecularScale = 0.6
Lighting.ExposureCompensation = 0.1
do
	local function fx(class, name, props)
		local o = Instance.new(class)
		o.Name = name
		for k, v in pairs(props) do o[k] = v end
		o.Parent = Lighting
		return o
	end
	fx("Atmosphere", "SVB_Atmosphere", { Density = 0.24, Offset = 0.12, Color = rgb(200, 225, 255), Decay = rgb(110, 150, 200), Glare = 0.35, Haze = 1.3 })
	fx("BloomEffect", "SVB_Bloom", { Intensity = 0.55, Size = 26, Threshold = 1.5 })
	fx("SunRaysEffect", "SVB_SunRays", { Intensity = 0.05, Spread = 0.6 })
	fx("ColorCorrectionEffect", "SVB_Color", { Saturation = 0.15, Contrast = 0.07, Brightness = 0.02, TintColor = rgb(255, 252, 245) })
	fx("Sky", "SVB_Sky", { SunAngularSize = 16, MoonAngularSize = 9, StarCount = 2500, CelestialBodiesShown = true })
end

------------------------------------------------------------------------
-- MAP
------------------------------------------------------------------------
for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("SpawnLocation") then inst:Destroy() end -- only our spawn is used (runtime only)
end
local oldBaseplate = workspace:FindFirstChild("Baseplate")
if oldBaseplate then oldBaseplate:Destroy() end

local Map = Instance.new("Folder")
Map.Name = "SVB_Map"
Map.Parent = workspace

local Decor = Instance.new("Folder")
Decor.Name = "Decor"
Decor.Parent = Map

local Obstacles = Instance.new("Folder")
Obstacles.Name = "Obstacles"
Obstacles.Parent = Map

local ZoneInfo = Instance.new("Folder")
ZoneInfo.Name = "SVB_Zones"
ZoneInfo.Parent = ReplicatedStorage

local DARK = Color3.fromRGB(22, 22, 30)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 215, 60)
local ROT_UP = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder so it stands up

-- k = zone slot
local function publishZone(k, name, color, need, theme, trophies, m, j, pace)
	local c = Instance.new("Configuration")
	c.Name = "Zone" .. k
	c:SetAttribute("Index", k)
	c:SetAttribute("Map", m)
	c:SetAttribute("ZoneNumber", j)
	c:SetAttribute("ZoneName", name)
	c:SetAttribute("Color", color)
	c:SetAttribute("Z0", k * L)
	c:SetAttribute("Z1", (k + 1) * L)
	c:SetAttribute("SpeedNeeded", need)
	c:SetAttribute("Pace", pace or 1)
	c:SetAttribute("Theme", theme)
	c:SetAttribute("Trophies", trophies or 0) -- what you get for making it out of this zone
	c.Parent = ZoneInfo
end
-- Every theme gets its own textures: the ground, the cliff under the track,
-- a trail down the middle and patches on the ground
local M = Enum.Material
local THEME_LOOK = {
	meadow  = { floor = M.Grass,        under = M.Ground,    path = M.Ground,      pathColor = Color3.fromRGB(150, 110, 70),  patch = M.LeafyGrass },
	desert  = { floor = M.Sand,         under = M.Sandstone, path = M.Sandstone,   pathColor = Color3.fromRGB(225, 185, 120), patch = M.Sand },
	ice     = { floor = M.Snow,         under = M.Glacier,   path = M.Ice,         pathColor = Color3.fromRGB(165, 215, 250), patch = M.Glacier },
	swamp   = { floor = M.Mud,          under = M.Ground,    path = M.Pebble,      pathColor = Color3.fromRGB(115, 120, 95),  patch = M.Mud },
	lava    = { floor = M.Basalt,       under = M.Basalt,    path = M.Slate,       pathColor = Color3.fromRGB(80, 65, 60),    patch = M.CrackedLava },
	candy   = { floor = M.Marble,       under = M.Marble,    path = M.SmoothPlastic, pathColor = Color3.fromRGB(255, 245, 250), patch = M.Marble, stripes = true },
	neon    = { floor = M.Asphalt,      under = M.Concrete,  path = M.Asphalt,     pathColor = Color3.fromRGB(35, 35, 45),    patch = M.Concrete, lanes = true },
	crystal = { floor = M.Slate,        under = M.Rock,      path = M.Marble,      pathColor = Color3.fromRGB(190, 160, 235), patch = M.Glass },
	storm   = { floor = M.Rock,         under = M.Slate,     path = M.Cobblestone, pathColor = Color3.fromRGB(120, 120, 130), patch = M.Pebble },
	void    = { floor = M.Granite },
	jungle  = { floor = M.LeafyGrass,   under = M.Ground,    path = M.Mud,         pathColor = Color3.fromRGB(120, 85, 55),   patch = M.Grass },
	haunted = { floor = M.Ground,       under = M.Rock,      path = M.Cobblestone, pathColor = Color3.fromRGB(100, 95, 110),  patch = M.Mud },
	factory = { floor = M.DiamondPlate, under = M.Metal,     path = M.Concrete,    pathColor = Color3.fromRGB(150, 150, 155), patch = M.CorrodedMetal, lanes = true },
	space   = { floor = M.Rock,         under = M.Basalt,    path = M.Metal,       pathColor = Color3.fromRGB(170, 180, 200), patch = M.Pebble },
	rainbow = { floor = M.Marble,       under = M.Marble,    path = M.SmoothPlastic, pathColor = WHITE,                       patch = M.Marble, rainbow = true },
	inferno = { floor = M.Basalt,       under = M.Basalt,    path = M.Slate,       pathColor = Color3.fromRGB(70, 45, 40),    patch = M.CrackedLava },
}

-- a textured part: its material, no studs
local function textured(part, material)
	part.Material = material
	for _, surface in ipairs({ "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }) do
		part[surface] = Enum.SurfaceType.Smooth
	end
	return part
end

-- Floor made of tiles with holes in it (used by The Void). There is always a path through.
local function buildHoleyFloor(k, color, rng)
	local cols, rows = math.floor(W / 10), math.floor(L / 10)
	local tileW, tileL = W / cols, L / rows
	local keep = {}
	local col = math.floor(cols / 2) + 1
	for r = 1, rows do
		keep[r] = keep[r] or {}
		keep[r][col] = true
		col = math.clamp(col + rng:NextInteger(-1, 1), 2, cols - 1)
		keep[r][col] = true
	end
	for r = 1, rows do
		for c = 1, cols do
			local safeRow = r <= 3 or r > rows - 3
			if safeRow or keep[r][c] or rng:NextNumber() > 0.32 then
				local tile = newPart{
					Name = "VoidTile",
					Size = Vector3.new(tileW, 1, tileL),
					Position = Vector3.new(-HALF_W + (c - 0.5) * tileW, 0, k * L + (r - 0.5) * tileL),
					Color = ((r + c) % 2 == 0) and color or color:Lerp(WHITE, 0.07),
					Parent = Map,
				}
				textured(tile, THEME_LOOK.void.floor)
			end
		end
	end
	-- the glowing void below the holes
	newPart{ Name = "VoidGlow", Size = Vector3.new(W + 80, 1, L + 20), Position = Vector3.new(0, CONFIG.KillHeight + 6, k * L + L / 2), Color = Color3.fromRGB(70, 20, 130), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = Map }
end

-- Floating slab + see-through glass walls for zone k (all zones are the same size)
local function buildZoneShell(k, floorColor, underColor, accent, holey, rng, theme)
	local cz = k * L + L / 2
	local look = THEME_LOOK[theme] or {}
	local function underSides(part)
		if look.under then textured(part, look.under) else studSides(part) end
	end
	if holey then
		buildHoleyFloor(k, floorColor, rng)
	else
		local floor = newPart{ Name = "Zone" .. k .. "Floor", Size = Vector3.new(W, 1, L), Position = Vector3.new(0, 0, cz), Color = floorColor, Parent = Map }
		if look.floor then textured(floor, look.floor) else addStuds(floor, Enum.NormalId.Top) end
		-- a trail down the middle of the track
		if look.path then
			local trail = newPart{ Name = "Trail", Size = Vector3.new(26, 0.12, L), Position = Vector3.new(0, FLOOR_Y + 0.06, cz), Color = look.pathColor, CanCollide = false, CastShadow = false, Parent = Decor }
			textured(trail, look.path)
			for _, side in ipairs({ -1, 1 }) do
				local edge = newPart{ Name = "TrailEdge", Size = Vector3.new(1.2, 0.14, L), Position = Vector3.new(side * 13.6, FLOOR_Y + 0.07, cz), Color = look.pathColor:Lerp(BLACK, 0.3), CanCollide = false, CastShadow = false, Parent = Decor }
				textured(edge, look.path)
			end
			if look.lanes then
				-- dashed yellow road lines
				for d = 0, math.floor(L / 16) - 1 do
					newPart{ Name = "LaneDash", Size = Vector3.new(0.6, 0.15, 8), Position = Vector3.new(0, FLOOR_Y + 0.08, k * L + 8 + d * 16), Color = Color3.fromRGB(255, 205, 40), CanCollide = false, CastShadow = false, Parent = Decor }
				end
			elseif look.stripes then
				-- candy-cane stripes across the trail
				for d = 0, math.floor(L / 10) - 1 do
					newPart{ Name = "CandyStripe", Size = Vector3.new(22, 0.14, 3.2), CFrame = CFrame.new(0, FLOOR_Y + 0.08, k * L + 5 + d * 10) * CFrame.Angles(0, math.rad(25), 0), Color = Color3.fromRGB(255, 110, 170), CanCollide = false, CastShadow = false, Parent = Decor }
				end
			elseif look.rainbow then
				-- rainbow lanes
				local cols = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 230, 70), Color3.fromRGB(100, 220, 90), Color3.fromRGB(80, 170, 255), Color3.fromRGB(170, 100, 255) }
				for i, c in ipairs(cols) do
					local lane = newPart{ Name = "RainbowLane", Size = Vector3.new(26 / #cols, 0.14, L), Position = Vector3.new(-13 + (i - 0.5) * (26 / #cols), FLOOR_Y + 0.08, cz), Color = c, CanCollide = false, CastShadow = false, Parent = Decor }
					textured(lane, M.SmoothPlastic)
				end
			end
		end
		-- a chunky underside so the track floats in the sky like an island
		local under = newPart{ Name = "Underside", Size = Vector3.new(W, 10, L), Position = Vector3.new(0, -5.5, cz), Color = underColor, Parent = Map }
		underSides(under)
		for _ = 1, 6 do
			local cw = rng:NextInteger(14, 30)
			local ch = rng:NextInteger(6, 16)
			local half = math.floor(HALF_W - cw / 2)
			local chunk = newPart{
				Name = "UnderChunk",
				Size = Vector3.new(cw, ch, rng:NextInteger(18, 40)),
				Position = Vector3.new(rng:NextInteger(-half, half), -10.5 - ch / 2, k * L + rng:NextInteger(25, L - 25)),
				Color = underColor:Lerp(BLACK, 0.12),
				Parent = Map,
			}
			underSides(chunk)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		-- see-through glass walls keep you on the track
		newPart{ Name = "GlassWall", Size = Vector3.new(1, 28, L), Position = Vector3.new(side * (HALF_W + 0.5), FLOOR_Y + 14, cz), Color = Color3.fromRGB(200, 235, 255), Material = Enum.Material.Glass, Transparency = 0.82, CastShadow = false, Parent = Map }
		newPart{ Name = "WallBase", Size = Vector3.new(1.6, 1, L), Position = Vector3.new(side * (HALF_W + 0.5), FLOOR_Y + 0.5, cz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
		newPart{ Name = "WallTop", Size = Vector3.new(1.4, 0.6, L), Position = Vector3.new(side * (HALF_W + 0.5), FLOOR_Y + 28, cz), Color = accent, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, Parent = Map }
	end
end

-- Lighter / darker patches on the floor so it isn't one flat color
local function floorPatches(k, color, rng, z0, len, material)
	z0, len = z0 or k * L, len or L
	for i = 1, math.floor(14 * len / 200) do
		local amt = 0.06 + rng:NextNumber() * 0.06
		local c = (i % 2 == 0) and color:Lerp(WHITE, amt) or color:Lerp(BLACK, amt)
		local patch = newPart{
			Name = "Patch",
			Size = Vector3.new(rng:NextInteger(8, 22), 0.1, rng:NextInteger(8, 22)),
			Position = Vector3.new(rng:NextInteger(-HALF_W + 14, HALF_W - 14), FLOOR_Y + 0.05, z0 + rng:NextInteger(12, len - 12)),
			Color = c,
			CanCollide = false,
			CastShadow = false,
			Parent = Decor,
		}
		if material then textured(patch, material) else addStuds(patch, Enum.NormalId.Top) end
	end
end

-- Golden gate at the END of a zone: shows the trophies you get for making it out,
-- and the Speed you need to go through (the force field is red until you have it)
local GATE_GOLD = Color3.fromRGB(255, 200, 40)
local function buildTrophyGate(z, lines, need)
	local h = 26
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (HALF_W - 1.5)
		local post = newPart{ Name = "GatePost", Size = Vector3.new(3, h, 3), Position = Vector3.new(x, FLOOR_Y + h / 2, z), Color = GATE_GOLD, Parent = Map }
		post.Reflectance = 0.15
		-- glowing gold studs running up the posts
		for s = 1, 6 do
			newPart{ Name = "GateStud", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, Position = Vector3.new(x - side * 1.4, FLOOR_Y + s * (h / 7), z), Color = Color3.fromRGB(255, 240, 150), Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
		end
		newPart{ Name = "GateFoot", Size = Vector3.new(5, 2, 5), Position = Vector3.new(x, FLOOR_Y + 1, z), Color = GATE_GOLD:Lerp(BLACK, 0.25), Parent = Map }
		newPart{ Name = "GateKnob", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = Vector3.new(x, FLOOR_Y + h + 1.5, z), Color = GATE_GOLD, Material = Enum.Material.Neon, Parent = Map }
	end
	newPart{ Name = "GateBeam", Size = Vector3.new(W - 3, 3, 3), Position = Vector3.new(0, FLOOR_Y + h - 1.5, z), Color = GATE_GOLD, Reflectance = 0.15, Parent = Map }
	newPart{ Name = "GateSill", Size = Vector3.new(W - 3, 0.3, 3), Position = Vector3.new(0, FLOOR_Y + 0.15, z), Color = GATE_GOLD, Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
	-- see-through panel you run through, with the reward on it
	local panel = newPart{ Name = "TrophyPanel", Size = Vector3.new(W - 6, h - 3, 0.3), Position = Vector3.new(0, FLOOR_Y + (h - 3) / 2, z), Color = Color3.fromRGB(255, 225, 120), Transparency = 0.8, CanCollide = false, CastShadow = false, Parent = Map }
	if need then
		-- the client colors this green when your Speed is enough, red when it isn't
		panel.Name = "SpeedGate"
		panel:SetAttribute("Need", need)
		CollectionService:AddTag(panel, "SVB_SpeedGate")
	end
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		addSign(panel, face, lines, 8)
	end
end
-- Decoration helpers (cartoony: round, chunky, bright) ---------------
local function prop(props)
	props.Parent = Decor
	return newPart(props)
end

local function vcyl(height, diameter, x, y, z, color, material) -- standing cylinder, y = bottom
	return prop{
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(x, y + height / 2, z) * ROT_UP,
		Color = color,
		Material = material,
	}
end

local function ball(d, x, y, z, color, material)
	return prop{ Shape = Enum.PartType.Ball, Size = Vector3.new(d, d, d), Position = Vector3.new(x, y, z), Color = color, Material = material }
end

local function block(sx, sy, sz, cf, color, material)
	return prop{ Size = Vector3.new(sx, sy, sz), CFrame = cf, Color = color, Material = material }
end

-- squash a ball into an oval (visual only, so turn its collision off)
local function squash(p, sx, sy, sz)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Scale = Vector3.new(sx, sy, sz)
	m.Parent = p
	p.CanCollide = false
	return p
end

local function cartoonTree(x, z, s, leaf, baseY)
	s = s or 1
	leaf = leaf or Color3.fromRGB(80, 190, 70)
	local y0 = baseY or FLOOR_Y
	local trunk = Color3.fromRGB(125, 85, 50)
	vcyl(6 * s, 2.8 * s, x, y0, z, trunk, Enum.Material.Wood)
	vcyl(4 * s, 2 * s, x, y0 + 6 * s, z, trunk, Enum.Material.Wood)
	ball(10 * s, x, y0 + 12.5 * s, z, leaf)
	ball(7.5 * s, x + 3.8 * s, y0 + 11 * s, z + 1.5 * s, leaf:Lerp(WHITE, 0.12))
	ball(7.5 * s, x - 3.6 * s, y0 + 11.5 * s, z - 1.8 * s, leaf:Lerp(BLACK, 0.12))
	ball(6.5 * s, x + 0.8 * s, y0 + 16 * s, z - 0.6 * s, leaf:Lerp(WHITE, 0.2))
	for f = 1, 4 do
		local a = f * 1.57 + 0.4
		local fruit = ball(1.1 * s, x + math.cos(a) * 4.7 * s, y0 + (12 + (f % 2) * 2) * s, z + math.sin(a) * 4.7 * s, Color3.fromRGB(235, 60, 60))
		fruit.CanCollide = false
	end
end

local function bush(x, z, color, baseY)
	color = color or Color3.fromRGB(70, 170, 60)
	local y0 = baseY or FLOOR_Y
	ball(4.5, x, y0 + 1.6, z, color)
	ball(3.6, x + 2.4, y0 + 1.2, z + 0.8, color:Lerp(WHITE, 0.1))
	ball(3.4, x - 2.2, y0 + 1.1, z - 0.6, color:Lerp(BLACK, 0.1))
end

local function rock(x, z, size, color, baseY)
	local r = prop{ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = Vector3.new(x, (baseY or FLOOR_Y) + size * 0.2, z), Color = color or Color3.fromRGB(140, 140, 150) }
	return squash(r, 1.3, 0.7, 1)
end

local function flower(x, z, color, baseY)
	local y0 = baseY or FLOOR_Y
	local stem = vcyl(2, 0.35, x, y0, z, Color3.fromRGB(70, 160, 60))
	stem.CanCollide = false
	local head = ball(1.5, x, y0 + 2.3, z, color)
	head.CanCollide = false
	local middle = ball(0.7, x, y0 + 2.4, z, Color3.fromRGB(255, 230, 80))
	middle.CanCollide = false
end

local PETALS, decorateZone -- set in the block below
do
	local function mushroom(x, z, s, cap, material)
		s = s or 1
		vcyl(3 * s, 1.4 * s, x, FLOOR_Y, z, Color3.fromRGB(245, 235, 210))
		local top = prop{ Shape = Enum.PartType.Ball, Size = Vector3.one * 4 * s, Position = Vector3.new(x, FLOOR_Y + 3.2 * s, z), Color = cap or Color3.fromRGB(230, 60, 60), Material = material }
		squash(top, 1, 0.6, 1)
		for d = 1, 4 do
			local a = d * 1.57
			local dot = ball(0.7 * s, x + math.cos(a) * 1.2 * s, FLOOR_Y + 3.9 * s, z + math.sin(a) * 1.2 * s, WHITE)
			dot.CanCollide = false
		end
	end

	local function pineTree(x, z, s)
		s = s or 1
		vcyl(4 * s, 1.6 * s, x, FLOOR_Y, z, Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
		local green = Color3.fromRGB(40, 120, 80)
		for t = 0, 2 do
			local size = (8 - t * 2.2) * s
			local y = FLOOR_Y + (5 + t * 3.6) * s
			local layer = prop{ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = Vector3.new(x, y, z), Color = green:Lerp(WHITE, t * 0.05) }
			squash(layer, 1, 0.75, 1)
			local snow = prop{ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.72, Position = Vector3.new(x, y + size * 0.22, z), Color = Color3.fromRGB(250, 252, 255) }
			squash(snow, 1, 0.45, 1)
		end
	end

	local function palmTree(x, z, side)
		local trunk = Color3.fromRGB(150, 110, 70)
		for seg = 0, 3 do
			block(1.8 - seg * 0.15, 3.2, 1.8 - seg * 0.15, CFrame.new(x - side * seg * 0.5, FLOOR_Y + 1.6 + seg * 3, z) * CFrame.Angles(0, 0, -side * 0.12), trunk:Lerp(BLACK, (seg % 2) * 0.1))
		end
		local top = Vector3.new(x - side * 2, FLOOR_Y + 13, z)
		for l = 1, 6 do
			local a = l * (math.pi * 2 / 6)
			local leaf = block(0.3, 7, 1.8, CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.8, -3) * CFrame.Angles(math.rad(70), 0, 0), Color3.fromRGB(60, 170, 70))
			leaf.CanCollide = false
		end
		ball(1.2, top.X + 0.6, top.Y - 0.8, top.Z, Color3.fromRGB(110, 70, 35))
		ball(1.2, top.X - 0.5, top.Y - 0.9, top.Z + 0.6, Color3.fromRGB(110, 70, 35))
	end

	local function cupcake(x, z, color)
		prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 5, 5), CFrame = CFrame.new(x, FLOOR_Y + 1.5, z) * ROT_UP, Color = Color3.fromRGB(255, 200, 120) }
		local frost = prop{ Shape = Enum.PartType.Ball, Size = Vector3.one * 5.6, Position = Vector3.new(x, FLOOR_Y + 3.6, z), Color = color }
		squash(frost, 1, 0.7, 1)
		ball(1.4, x, FLOOR_Y + 5.6, z, Color3.fromRGB(220, 30, 50))
		local sprinkles = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 200, 255) }
		for s = 1, 6 do
			local a = s * 1.05
			local bit = block(0.25, 0.25, 0.8, CFrame.new(x + math.cos(a) * 1.8, FLOOR_Y + 4.7, z + math.sin(a) * 1.8) * CFrame.Angles(0, a, 0.4), sprinkles[s % 3 + 1])
			bit.CanCollide = false
		end
	end

	local function volcano(x, z)
		local rockColor = Color3.fromRGB(60, 45, 40)
		for t = 0, 3 do
			vcyl(2.5, 12 - t * 2.6, x, FLOOR_Y + t * 2.5, z, rockColor:Lerp(BLACK, t * 0.05), Enum.Material.Basalt)
		end
		local top = vcyl(0.4, 3.4, x, FLOOR_Y + 10, z, Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 120, 30)
		glow.Range = 18
		glow.Brightness = 2
		glow.Parent = top
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(80, 60, 55)
		smoke.Opacity = 0.15
		smoke.RiseVelocity = 6
		smoke.Size = 3
		smoke.Parent = top
	end

	local function deadTree(x, z, color)
		color = color or Color3.fromRGB(80, 60, 45)
		vcyl(12, 1.8, x, FLOOR_Y, z, color, Enum.Material.Wood)
		block(0.9, 5, 0.9, CFrame.new(x + 1.6, FLOOR_Y + 9, z) * CFrame.Angles(0, 0, -0.7), color, Enum.Material.Wood)
		block(0.8, 4, 0.8, CFrame.new(x - 1.4, FLOOR_Y + 7, z + 0.5) * CFrame.Angles(0.2, 0, 0.8), color, Enum.Material.Wood)
		block(0.6, 3, 0.6, CFrame.new(x + 0.4, FLOOR_Y + 12.8, z - 0.8) * CFrame.Angles(-0.5, 0, 0.2), color, Enum.Material.Wood)
	end

	local function pond(x, z)
		local water = prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 11, 11), CFrame = CFrame.new(x, FLOOR_Y + 0.08, z) * ROT_UP, Color = Color3.fromRGB(70, 130, 110), Material = Enum.Material.Glass, CanCollide = false }
		water.Transparency = 0.1
		for p = 1, 3 do
			local a = p * 2.1
			local pad = prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.6, 2.6), CFrame = CFrame.new(x + math.cos(a) * 2.8, FLOOR_Y + 0.2, z + math.sin(a) * 2.8) * ROT_UP, Color = Color3.fromRGB(70, 170, 60), CanCollide = false }
			pad.CanCollide = false
		end
		local bloom = ball(1, x + 1, FLOOR_Y + 0.6, z - 2, Color3.fromRGB(255, 150, 200))
		bloom.CanCollide = false
	end

	local DECOR = {}

	PETALS = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 60), Color3.fromRGB(160, 110, 255), Color3.fromRGB(255, 140, 200) }

	function DECOR.meadow(x, z, side, i)
		local r = i % 4
		if r == 0 then
			for f = 1, 5 do
				flower(x + math.random(-4, 4), z + math.random(-4, 4), PETALS[f % #PETALS + 1])
			end
		elseif r == 1 then
			cartoonTree(x, z, 1)
		elseif r == 2 then
			bush(x, z)
			mushroom(x - side * 3, z + 3, 0.7)
		else
			cartoonTree(x, z, 0.8, Color3.fromRGB(110, 205, 80))
		end
	end

	function DECOR.desert(x, z, side, i)
		local r = i % 3
		if r == 0 then
			local g = Color3.fromRGB(70, 160, 75)
			vcyl(13, 3.2, x, FLOOR_Y, z, g)
			ball(3.2, x, FLOOR_Y + 13, z, g)
			block(3.4, 1.6, 1.6, CFrame.new(x + 2, FLOOR_Y + 6, z), g)
			vcyl(4, 1.8, x + 3.4, FLOOR_Y + 6, z, g)
			ball(1.8, x + 3.4, FLOOR_Y + 10, z, g)
			block(3.4, 1.6, 1.6, CFrame.new(x - 2, FLOOR_Y + 8, z), g)
			vcyl(3, 1.8, x - 3.4, FLOOR_Y + 8, z, g)
			ball(1.8, x - 3.4, FLOOR_Y + 11, z, g)
			ball(1.4, x, FLOOR_Y + 14.6, z, Color3.fromRGB(255, 110, 170)) -- cactus flower
		elseif r == 1 then
			palmTree(x, z, side)
		else
			rock(x, z, 7, Color3.fromRGB(215, 165, 105))
			rock(x - side * 3, z + 4, 4, Color3.fromRGB(200, 150, 95))
		end
	end

	function DECOR.ice(x, z, side, i)
		local r = i % 3
		if r == 0 then
			local snow = Color3.fromRGB(250, 250, 255)
			ball(6.5, x, FLOOR_Y + 2.8, z, snow, Enum.Material.Snow)
			ball(4.8, x, FLOOR_Y + 7.4, z, snow, Enum.Material.Snow)
			ball(3.4, x, FLOOR_Y + 10.8, z, snow, Enum.Material.Snow)
			block(2, 0.6, 0.6, CFrame.new(x - side * 1.9, FLOOR_Y + 10.8, z), Color3.fromRGB(255, 140, 40))
			ball(0.6, x - side * 1.5, FLOOR_Y + 11.5, z - 0.7, BLACK)
			ball(0.6, x - side * 1.5, FLOOR_Y + 11.5, z + 0.7, BLACK)
			block(0.5, 0.5, 5, CFrame.new(x, FLOOR_Y + 8.8, z), Color3.fromRGB(220, 50, 60)) -- scarf
		elseif r == 1 then
			pineTree(x, z, 1.1)
		else
			for s = 1, 3 do
				local h = 8 + s * 3
				block(2.6, h, 2.6, CFrame.new(x + math.random(-3, 3), FLOOR_Y + h / 2 - 1, z + math.random(-3, 3))
					* CFrame.Angles(math.rad(math.random(-15, 15)), math.rad(math.random(0, 90)), math.rad(math.random(-15, 15))),
					Color3.fromRGB(150, 215, 255), Enum.Material.Ice)
			end
		end
	end

	function DECOR.swamp(x, z, side, i)
		local r = i % 3
		if r == 0 then
			mushroom(x, z, 1.6, Color3.fromRGB(190, 60, 210))
		elseif r == 1 then
			deadTree(x, z, Color3.fromRGB(70, 60, 40))
		else
			pond(x - side * 2, z)
			vcyl(7, 0.6, x + side * 2, FLOOR_Y, z + 3, Color3.fromRGB(90, 125, 55))
			vcyl(5, 0.6, x + side * 3, FLOOR_Y, z + 2, Color3.fromRGB(80, 110, 50))
		end
	end

	function DECOR.lava(x, z, side, i)
		local r = i % 3
		if r == 0 then
			local rk = block(8, 7, 7, CFrame.new(x, FLOOR_Y + 3, z) * CFrame.Angles(0.2, math.random() * 3, 0.15), Color3.fromRGB(45, 35, 35), Enum.Material.Basalt)
			block(8.4, 0.6, 1.2, rk.CFrame * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		elseif r == 1 then
			volcano(x, z)
		else
			rock(x, z, 6, Color3.fromRGB(70, 50, 45))
			local ember = ball(1.2, x + 1, FLOOR_Y + 1.6, z, Color3.fromRGB(255, 150, 40), Enum.Material.Neon)
			ember.CanCollide = false
		end
	end

	function DECOR.candy(x, z, side, i)
		local colors = { Color3.fromRGB(255, 90, 170), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 220, 80) }
		local r = i % 3
		if r == 0 then
			vcyl(11, 0.9, x, FLOOR_Y, z, WHITE)
			prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 10, 10), CFrame = CFrame.new(x, FLOOR_Y + 14, z), Color = colors[i % 3 + 1] }
			prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 5, 5), CFrame = CFrame.new(x, FLOOR_Y + 14, z), Color = WHITE }
			prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 2, 2), CFrame = CFrame.new(x, FLOOR_Y + 14, z), Color = colors[(i + 1) % 3 + 1] }
		elseif r == 1 then
			cupcake(x, z, colors[i % 3 + 1])
		else
			for s = 0, 4 do
				block(1.2, 2.4, 1.2, CFrame.new(x, FLOOR_Y + 1.2 + s * 2.4, z), (s % 2 == 0) and Color3.fromRGB(230, 40, 60) or WHITE)
			end
			block(4, 1.2, 1.2, CFrame.new(x - side * 1.4, FLOOR_Y + 12.6, z), Color3.fromRGB(230, 40, 60))
		end
	end

	local NEON_WORDS = { "OPEN", "24/7", "ZAP!", "NOODLES", "ARCADE", "BRAINROT", "TURBO" }

	function DECOR.neon(x, z, side, i)
		local h = math.random(20, 44)
		local bx = side * (HALF_W - 6)
		local building = block(10, h, 16, CFrame.new(bx, FLOOR_Y + h / 2, z), Color3.fromRGB(32, 32, 58))
		local strip = (i % 2 == 0) and Color3.fromRGB(0, 255, 230) or Color3.fromRGB(255, 40, 200)
		for s = 1, math.floor(h / 7) do
			block(0.4, 0.8, 14, CFrame.new(bx - side * 5.1, FLOOR_Y + s * 7, z), strip, Enum.Material.Neon)
		end
		-- glowing shop sign facing the track
		local sg = Instance.new("SurfaceGui")
		sg.Face = side < 0 and Enum.NormalId.Right or Enum.NormalId.Left
		sg.LightInfluence = 0
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 20
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0, 120)
		t.Position = UDim2.new(0, 0, 1, -200)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = NEON_WORDS[i % #NEON_WORDS + 1]
		t.TextColor3 = strip
		t.TextStrokeColor3 = WHITE
		t.TextStrokeTransparency = 0.6
		t.Parent = sg
		sg.Parent = building
	end

	function DECOR.crystal(x, z, side, i)
		local colors = { Color3.fromRGB(200, 120, 255), Color3.fromRGB(120, 255, 250), Color3.fromRGB(255, 120, 220) }
		if i % 3 == 0 then
			mushroom(x, z, 1.3, colors[i % 3 + 1], Enum.Material.Neon)
		else
			for s = 1, 3 do
				local h = 6 + s * 3
				block(2.4, h, 2.4, CFrame.new(x + math.random(-3, 3), FLOOR_Y + h / 2 - 1, z + math.random(-3, 3))
					* CFrame.Angles(math.rad(math.random(-20, 20)), math.rad(math.random(0, 90)), math.rad(math.random(-20, 20))),
					colors[(i + s) % 3 + 1], Enum.Material.Neon)
			end
		end
	end

	function DECOR.storm(x, z, side, i)
		local r = i % 3
		if r == 0 then
			block(6, 18, 6, CFrame.new(x, FLOOR_Y + 8, z) * CFrame.Angles(0.08, math.random() * 3, -0.1), Color3.fromRGB(85, 88, 100), Enum.Material.Slate)
			rock(x - side * 3, z + 4, 5, Color3.fromRGB(75, 78, 90))
		elseif r == 1 then
			deadTree(x, z, Color3.fromRGB(60, 55, 55))
		else
			for c = 1, 3 do
				local cloud = ball(7 + c, x + c * 3 - 6, 27 + c, z + math.random(-2, 2), Color3.fromRGB(70, 72, 88))
				cloud.CanCollide = false
			end
		end
	end

	function DECOR.void(x, z, side, i)
		for c = 1, 3 do
			local cube = block(3, 3, 3, CFrame.new(x + math.random(-4, 4), FLOOR_Y + 6 + c * 5, z + math.random(-4, 4))
				* CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3), Color3.fromRGB(20, 15, 30))
			cube.CanCollide = false
			local box = Instance.new("SelectionBox")
			box.Adornee = cube
			box.Color3 = Color3.fromRGB(170, 60, 255)
			box.LineThickness = 0.08
			box.Parent = cube
		end
		if i % 3 == 0 then
			local disc = prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 9, 9), CFrame = CFrame.new(x, FLOOR_Y + 15, z), Color = Color3.fromRGB(170, 60, 255), Material = Enum.Material.Neon, Transparency = 0.25 }
			disc.CanCollide = false
		end
	end


	-- MAP 2 decorations ------------------------------------------------

	function DECOR.jungle(x, z, side, i)
		local r = i % 3
		if r == 0 then
			palmTree(x, z, side)
			bush(x + side * 2, z + 4, Color3.fromRGB(50, 150, 60))
		elseif r == 1 then
			-- big jungle leaves fanning out of the ground
			for l = 1, 5 do
				local a = l * 1.25
				local leaf = block(0.3, 8, 3, CFrame.new(x, FLOOR_Y + 3, z) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, 2.5, 0), Color3.fromRGB(40, 150 + l * 8, 60))
				leaf.CanCollide = false
			end
			flower(x - side * 2, z + 2, Color3.fromRGB(255, 80, 120))
		else
			-- tiki head
			local wood = Color3.fromRGB(140, 95, 55)
			block(4, 9, 4, CFrame.new(x, FLOOR_Y + 4.5, z), wood, Enum.Material.Wood)
			for _, ex in ipairs({ -0.9, 0.9 }) do
				block(1, 1, 0.3, CFrame.new(x - side * 2.05, FLOOR_Y + 6.5, z + ex) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 230, 120), Enum.Material.Neon).CanCollide = false
			end
			block(0.3, 1, 2.6, CFrame.new(x - side * 2.05, FLOOR_Y + 4, z), Color3.fromRGB(70, 40, 25)).CanCollide = false
			block(5, 1, 5, CFrame.new(x, FLOOR_Y + 9.5, z), Color3.fromRGB(60, 160, 70))
		end
	end

	function DECOR.haunted(x, z, side, i)
		local r = i % 3
		if r == 0 then
			deadTree(x, z, Color3.fromRGB(45, 40, 50))
		elseif r == 1 then
			-- tombstone
			local stone = Color3.fromRGB(130, 130, 145)
			block(4, 5, 1.2, CFrame.new(x, FLOOR_Y + 2.5, z) * CFrame.Angles(0, math.rad(90), math.rad(side * 6)), stone, Enum.Material.Slate)
			prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 4, 4), CFrame = CFrame.new(x, FLOOR_Y + 5, z) * CFrame.Angles(0, 0, 0), Color = stone, Material = Enum.Material.Slate }
			block(4, 0.4, 3, CFrame.new(x - side * 2.5, FLOOR_Y + 0.2, z), Color3.fromRGB(70, 55, 45))
		else
			-- pumpkin with a glowing face
			local p = ball(5, x, FLOOR_Y + 2.2, z, Color3.fromRGB(255, 130, 30))
			squash(p, 1.2, 0.85, 1.2)
			vcyl(1.2, 0.6, x, FLOOR_Y + 4.1, z, Color3.fromRGB(80, 120, 40))
			for _, ez in ipairs({ -0.9, 0.9 }) do
				ball(0.9, x - side * 2.6, FLOOR_Y + 2.8, z + ez, Color3.fromRGB(255, 240, 120), Enum.Material.Neon).CanCollide = false
			end
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 160, 60)
			glow.Range = 10
			glow.Parent = p
		end
	end

	function DECOR.factory(x, z, side, i)
		local r = i % 3
		if r == 0 then
			-- chimney with smoke
			local brick = Color3.fromRGB(150, 70, 55)
			block(5, 20, 5, CFrame.new(x, FLOOR_Y + 10, z), brick, Enum.Material.Brick)
			block(6, 1, 6, CFrame.new(x, FLOOR_Y + 20, z), Color3.fromRGB(60, 60, 70))
			local smoke = Instance.new("Smoke")
			smoke.Color = Color3.fromRGB(120, 120, 130)
			smoke.Opacity = 0.12
			smoke.RiseVelocity = 5
			smoke.Size = 4
			smoke.Parent = block(1, 1, 1, CFrame.new(x, FLOOR_Y + 21, z), Color3.fromRGB(60, 60, 70))
		elseif r == 1 then
			-- big gear on the wall
			local gear = prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 9, 9), CFrame = CFrame.new(side * (HALF_W - 1.5), FLOOR_Y + 9, z), Color = Color3.fromRGB(255, 170, 30), Material = Enum.Material.DiamondPlate }
			for t = 0, 7 do
				block(1, 1.6, 1.6, gear.CFrame * CFrame.Angles(t * math.pi / 4, 0, 0) * CFrame.new(0, 5, 0), Color3.fromRGB(230, 150, 25), Enum.Material.DiamondPlate)
			end
		else
			-- stack of crates
			local crate = Color3.fromRGB(170, 120, 70)
			block(4, 4, 4, CFrame.new(x, FLOOR_Y + 2, z), crate, Enum.Material.WoodPlanks)
			block(4, 4, 4, CFrame.new(x - side * 1, FLOOR_Y + 2, z + 4.2), crate:Lerp(BLACK, 0.1), Enum.Material.WoodPlanks)
			block(4, 4, 4, CFrame.new(x - side * 0.5, FLOOR_Y + 6, z + 2) * CFrame.Angles(0, 0.3, 0), crate:Lerp(WHITE, 0.08), Enum.Material.WoodPlanks)
		end
	end

	local PLANET_COLORS = { Color3.fromRGB(255, 150, 80), Color3.fromRGB(120, 200, 255), Color3.fromRGB(200, 120, 255), Color3.fromRGB(120, 230, 150) }
	function DECOR.space(x, z, side, i)
		local r = i % 3
		if r == 0 then
			-- floating planet with a ring
			local c = PLANET_COLORS[i % #PLANET_COLORS + 1]
			local planet = ball(8, x + side * 6, FLOOR_Y + 22, z, c)
			planet.CanCollide = false
			local ringPart = prop{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 14, 14), CFrame = CFrame.new(planet.Position) * CFrame.Angles(0.4, 0, math.rad(90) + 0.3), Color = c:Lerp(WHITE, 0.4), Transparency = 0.3, CanCollide = false }
			ringPart.CastShadow = false
		elseif r == 1 then
			-- little moon rocks with craters
			rock(x, z, 7, Color3.fromRGB(150, 150, 165))
			rock(x - side * 3, z + 4, 4, Color3.fromRGB(130, 130, 145))
		else
			-- rocket on a launch pad
			vcyl(0.8, 7, x, FLOOR_Y, z, Color3.fromRGB(80, 80, 95))
			vcyl(10, 3.2, x, FLOOR_Y + 0.8, z, WHITE)
			local tip = ball(3.2, x, FLOOR_Y + 10.8, z, Color3.fromRGB(230, 50, 60))
			squash(tip, 1, 1.5, 1)
			ball(1.4, x - side * 1.5, FLOOR_Y + 7, z, Color3.fromRGB(120, 200, 255), Enum.Material.Glass).CanCollide = false
			for f = 0, 2 do
				block(0.4, 3, 2, CFrame.new(x, FLOOR_Y + 2.3, z) * CFrame.Angles(0, f * 2.09, 0) * CFrame.new(0, 0, 2), Color3.fromRGB(230, 50, 60))
			end
		end
	end

	local RAINBOW = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 230, 70), Color3.fromRGB(100, 220, 90), Color3.fromRGB(80, 170, 255), Color3.fromRGB(170, 100, 255) }
	function DECOR.rainbow(x, z, side, i)
		if i % 2 == 0 then
			-- little rainbow arch
			for b = 1, 6 do
				local radius = 9 - b * 0.9
				for s = 0, 8 do
					local a = s / 8 * math.pi
					local seg = block(0.9, 0.9, 1.2, CFrame.new(x, FLOOR_Y + math.sin(a) * radius, z + math.cos(a) * radius), RAINBOW[b], Enum.Material.Neon)
					seg.CanCollide = false
				end
			end
		else
			-- fluffy cloud puff
			for c = 1, 4 do
				ball(4 + c, x + math.random(-3, 3), FLOOR_Y + 1.5 + c * 0.4, z + c * 1.6 - 4, WHITE).CanCollide = false
			end
		end
	end

	function DECOR.inferno(x, z, side, i)
		local r = i % 3
		if r == 0 then
			volcano(x, z)
		elseif r == 1 then
			-- obsidian spike with a glowing crack
			local h = 10 + (i % 4) * 2
			local spike = block(4, h, 4, CFrame.new(x, FLOOR_Y + h / 2, z) * CFrame.Angles(0.1, i, -0.1), Color3.fromRGB(30, 20, 30), Enum.Material.Basalt)
			block(0.4, h * 0.8, 4.2, spike.CFrame, Color3.fromRGB(255, 90, 20), Enum.Material.Neon).CanCollide = false
		else
			local fire = Instance.new("Fire")
			fire.Size = 6
			fire.Heat = 12
			fire.Color = Color3.fromRGB(255, 120, 30)
			fire.SecondaryColor = Color3.fromRGB(255, 40, 20)
			local bowl = vcyl(2.5, 4, x, FLOOR_Y, z, Color3.fromRGB(50, 40, 40), Enum.Material.Basalt)
			fire.Parent = bowl
		end
	end

	function decorateZone(k, theme)
		local fn = DECOR[theme]
		if not fn then return end
		local count = math.floor(16 * L / 200)
		for i = 1, count do
			local side = (i % 2 == 0) and 1 or -1
			local z = k * L + (i - 0.5) * (L / count)
			local x = side * (HALF_W - math.random(6, 11))
			fn(x, z, side, i)
		end
	end
end

------------------------------------------------------------------------
-- OBSTACLES + HAZARDS (every zone gets its own; touching a hazard sends you back to the start)
-- Moving obstacles follow the server clock, so every player sees them in the same place.
-- The server only checks where they are; SpeedVsBrainrot_World moves them smoothly on screen.
------------------------------------------------------------------------
local Hazards = {}   -- [zone slot] = list of things that hurt

-- where a moving part is at time t (the World client uses the same math)
local TAU = math.pi * 2
local function moverCF(m, t)
	local u = t / m.period + m.phase
	if m.kind == "slide" then
		return m.base * CFrame.new(math.sin(u * TAU) * m.amp, 0, 0)
	elseif m.kind == "spin" then
		return m.base * CFrame.Angles(0, u * TAU, 0)
	elseif m.kind == "swing" then
		return m.base * CFrame.Angles(0, 0, math.sin(u * TAU) * m.amp) * CFrame.new(0, -m.len, 0)
	elseif m.kind == "pound" then
		-- hangs up high, slams down, waits, rises again
		local f = u % 1
		local h
		if f < 0.55 then
			h = 1
		elseif f < 0.62 then
			h = 1 - (f - 0.55) / 0.07
		elseif f < 0.8 then
			h = 0
		else
			h = (f - 0.8) / 0.2
		end
		return m.base * CFrame.new(0, h * m.amp, 0)
	end
	return m.base
end

local OBSTACLES -- set in the block below
do
	-- obstacle spreads were made for a 110-wide track: scale them to the real width
	local XS = HALF_W / 55
	local function rx(n) return math.floor(n * XS + 0.5) end
	-- Box test in the part's own space, padded so it catches the player's body
	local function boxCheck(part, pad)
		pad = pad or Vector3.new(2, 6, 2)
		return function(pos)
			local rel = part.CFrame:PointToObjectSpace(pos)
			local half = (part.Size + pad) / 2
			return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
		end
	end

	local function addHazard(k, part, activeFn, checkFn, message)
		Hazards[k] = Hazards[k] or {}
		table.insert(Hazards[k], {
			part = part,
			active = activeFn,
			check = checkFn or boxCheck(part),
			message = message or "Ouch! Watch out for the glowing stuff.",
		})
	end

	local function solid(props)
		props.Parent = Obstacles
		return newPart(props)
	end

	-- a part that moves on the server clock. kind = slide / spin / swing / pound
	local function mover(k, props, kind, opts, message, pad)
		props.CanCollide = false
		local part = solid(props)
		local m = { part = part, kind = kind, base = part.CFrame, amp = opts.amp or 0, period = opts.period or 3, phase = opts.phase or 0, len = opts.len or 0 }
		part:SetAttribute("MoveKind", kind)
		part:SetAttribute("BaseCF", m.base)
		part:SetAttribute("Amp", m.amp)
		part:SetAttribute("Period", m.period)
		part:SetAttribute("Phase", m.phase)
		part:SetAttribute("Len", m.len)
		CollectionService:AddTag(part, "SVB_Mover")
		part.CFrame = moverCF(m, workspace:GetServerTimeNow())
		if message then
			pad = pad or Vector3.new(2, 6, 2)
			addHazard(k, part, nil, function(pos)
				local cf = moverCF(m, workspace:GetServerTimeNow())
				local rel = cf:PointToObjectSpace(pos)
				local half = (part.Size + pad) / 2
				return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
			end, message)
		end
		return part, m
	end

	-- A glowing bar that spins around a post
	local function spinner(k, basePos, length, color, period, message)
		local center = basePos + Vector3.new(0, 2.2, 0)
		solid{ Name = "SpinnerHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.4, 4, 4), CFrame = CFrame.new(center) * ROT_UP, Color = Color3.fromRGB(50, 50, 60) }
		solid{ Name = "SpinnerCap", Shape = Enum.PartType.Ball, Size = Vector3.one * 3, Position = center + Vector3.new(0, 2.4, 0), Color = color, Material = Enum.Material.Neon }
		mover(k, { Name = "SpinnerBar", Size = Vector3.new(length, 1.4, 1.4), CFrame = CFrame.new(center), Color = color, Material = Enum.Material.Neon }, "spin", { period = period }, message, Vector3.new(2, 5, 2))
	end

	-- something that slides from wall to wall across the track
	local function slider(k, z, size, color, material, period, phase, message, y)
		local amp = HALF_W - size.X / 2 - 2
		return mover(k, { Name = "Slider", Size = size, Position = Vector3.new(0, FLOOR_Y + (y or size.Y / 2), z), Color = color, Material = material }, "slide", { amp = amp, period = period, phase = phase }, message)
	end

	-- a heavy block that slams down; a yellow ring on the floor warns you where
	local function crusher(k, x, z, color, period, phase, message)
		local amp = 9
		solid{ Name = "CrusherWarning", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 13, 13), CFrame = CFrame.new(x, FLOOR_Y + 0.1, z) * ROT_UP, Color = Color3.fromRGB(255, 215, 40), Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false }
		local part = mover(k, { Name = "Crusher", Size = Vector3.new(10, 5, 10), Position = Vector3.new(x, FLOOR_Y + 2.5, z), Color = color, Material = Enum.Material.DiamondPlate }, "pound", { amp = amp, period = period, phase = phase }, message, Vector3.new(1, 2, 1))
		-- yellow and black stripes on the bottom edge
		for s = 0, 4 do
			local stripe = Instance.new("Part")
			stripe.Name = "CrusherStripe"
			stripe.Size = Vector3.new(2, 0.6, 10.1)
			stripe.CanCollide = false
			stripe.Anchored = false
			stripe.Massless = true
			stripe.Color = (s % 2 == 0) and Color3.fromRGB(255, 210, 40) or Color3.fromRGB(30, 30, 30)
			stripe.Material = Enum.Material.SmoothPlastic
			stripe.CFrame = part.CFrame * CFrame.new(-4 + s * 2, -2.2, 0)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = stripe
			weld.Parent = stripe
			stripe.Parent = part
		end
		return part
	end

	-- on/off hazards (lasers, fire jets): the World client blinks them on the same clock
	local function blinker(k, part, offset, period, onTime, message)
		part:SetAttribute("BlinkOffset", offset)
		part:SetAttribute("BlinkPeriod", period)
		part:SetAttribute("BlinkOn", onTime)
		CollectionService:AddTag(part, "SVB_Blink")
		addHazard(k, part, function()
			return ((workspace:GetServerTimeNow() + offset) % period) < onTime
		end, nil, message)
	end

	-- a glowing circle that flashes, then a strike hits it
	local function strike(k, x, z, offset, period, color, message)
		local warnDisc = solid{ Name = "StrikeWarning", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 14, 14), CFrame = CFrame.new(x, FLOOR_Y + 0.2, z) * ROT_UP, Color = color, Material = Enum.Material.Neon, CanCollide = false, Transparency = 0.6 }
		local bolt = solid{ Name = "Strike", Size = Vector3.new(2, 60, 2), Position = Vector3.new(x, FLOOR_Y + 30, z), Color = color:Lerp(WHITE, 0.6), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Transparency = 1 }
		for _, p in ipairs({ warnDisc, bolt }) do
			p:SetAttribute("StrikeRole", p == bolt and "bolt" or "warn")
			p:SetAttribute("StrikeOffset", offset)
			p:SetAttribute("StrikePeriod", period)
			CollectionService:AddTag(p, "SVB_Strike")
		end
		addHazard(k, warnDisc, function()
			local t = (workspace:GetServerTimeNow() + offset) % period
			return t >= 1.4 and t < 1.8
		end, function(pos)
			return Vector2.new(pos.X - x, pos.Z - z).Magnitude <= 7.5 and pos.Y < FLOOR_Y + 12
		end, message)
	end

	OBSTACLES = {}

	-- MAP 1 -----------------------------------------------------------

	-- wooden fences (jump them or find the gap) + a hay cart rolling across
	function OBSTACLES.meadow(k, z0, rng)
		local wood, darkWood = Color3.fromRGB(150, 100, 55), Color3.fromRGB(115, 75, 40)
		for _, dz in ipairs({ 60, 110, 165 }) do
			local z = z0 + dz
			local gap = rng:NextInteger(-rx(35), rx(35))
			local x = -HALF_W
			while x < HALF_W do
				local nx = math.min(x + 10, HALF_W)
				local mid = (x + nx) / 2
				if math.abs(mid - gap) > 8 then
					local len = nx - x
					solid{ Name = "Fence", Size = Vector3.new(len, 0.6, 0.6), Position = Vector3.new(mid, FLOOR_Y + 2.3, z), Color = wood, Material = Enum.Material.Wood }
					solid{ Name = "Fence", Size = Vector3.new(len, 0.6, 0.6), Position = Vector3.new(mid, FLOOR_Y + 1.2, z), Color = wood, Material = Enum.Material.Wood }
					solid{ Name = "FencePost", Size = Vector3.new(0.9, 3, 0.9), Position = Vector3.new(x + 0.45, FLOOR_Y + 1.5, z), Color = darkWood, Material = Enum.Material.Wood }
				end
				x = nx
			end
			solid{ Name = "HayBale", Size = Vector3.new(6, 4, 4), Position = Vector3.new(rng:NextInteger(-rx(40), rx(40)), FLOOR_Y + 2, z + rng:NextInteger(12, 22)), Color = Color3.fromRGB(230, 200, 90), Material = Enum.Material.Fabric }
		end
		slider(k, z0 + 138, Vector3.new(8, 5, 6), Color3.fromRGB(230, 200, 90), Enum.Material.Fabric, 5, 0, "A hay cart bonked you!")
	end

	-- sandstone pillars to weave through + tumbleweeds rolling across
	function OBSTACLES.desert(k, z0, rng)
		for _ = 1, 8 do
			local h = rng:NextInteger(8, 16)
			solid{ Name = "SandPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 5, 5), CFrame = CFrame.new(rng:NextInteger(-rx(42), rx(42)), FLOOR_Y + h / 2, z0 + rng:NextInteger(40, 120)) * ROT_UP, Color = Color3.fromRGB(215, 170, 105), Material = Enum.Material.Sandstone }
		end
		newWedge{ Name = "SandRamp", Size = Vector3.new(16, 5, 18), CFrame = CFrame.new(rng:NextInteger(-rx(30), rx(30)), FLOOR_Y + 2.5, z0 + 135), Color = Color3.fromRGB(235, 195, 120), Material = Enum.Material.Sand, Parent = Obstacles }
		slider(k, z0 + 160, Vector3.new(6, 6, 6), Color3.fromRGB(170, 120, 60), Enum.Material.Grass, 3.6, 0, "A tumbleweed rolled you over!")
		slider(k, z0 + 182, Vector3.new(6, 6, 6), Color3.fromRGB(170, 120, 60), Enum.Material.Grass, 3.2, 0.5, "A tumbleweed rolled you over!")
	end

	-- ice walls with two gaps each + a spinning snowplow
	function OBSTACLES.ice(k, z0, rng)
		for _, dz in ipairs({ 55, 105, 165 }) do
			local z = z0 + dz
			local g1, g2 = rng:NextInteger(-42, -12), rng:NextInteger(12, 42)
			local edges = { -HALF_W, g1 - 6, g1 + 6, g2 - 6, g2 + 6, HALF_W }
			for i = 1, #edges - 1, 2 do
				local a, b = edges[i], edges[i + 1]
				if b - a > 1 then
					solid{ Name = "IceWall", Size = Vector3.new(b - a, 8, 3), Position = Vector3.new((a + b) / 2, FLOOR_Y + 4, z), Color = Color3.fromRGB(165, 220, 255), Material = Enum.Material.Ice, Transparency = 0.1 }
				end
			end
		end
		spinner(k, Vector3.new(0, FLOOR_Y, z0 + 135), 36, Color3.fromRGB(120, 220, 255), 3.4, "The snowplow swept you away!")
	end

	-- toxic goo rivers with log bridges + a mud ball rolling across
	function OBSTACLES.swamp(k, z0, rng)
		for _, dz in ipairs({ 70, 150 }) do
			local z = z0 + dz
			local goo = solid{ Name = "ToxicGoo", Size = Vector3.new(W, 0.4, 12), Position = Vector3.new(0, FLOOR_Y + 0.2, z), Color = Color3.fromRGB(120, 255, 60), Material = Enum.Material.Neon, CanCollide = false }
			addHazard(k, goo, nil, nil, "The toxic goo got you! Jump over it or use a log.")
			for _ = 1, 2 do
				solid{ Name = "LogBridge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 3, 3), CFrame = CFrame.new(rng:NextInteger(-rx(40), rx(40)), FLOOR_Y + 1.2, z) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood }
			end
		end
		slider(k, z0 + 110, Vector3.new(7, 7, 7), Color3.fromRGB(90, 70, 45), Enum.Material.Mud, 3, 0.25, "A mud ball splatted you!")
	end

	-- lava rivers with stone bridges + crushers slamming down
	function OBSTACLES.lava(k, z0, rng)
		for _, dz in ipairs({ 60, 150 }) do
			local z = z0 + dz
			local lava = solid{ Name = "LavaRiver", Size = Vector3.new(W, 0.4, 14), Position = Vector3.new(0, FLOOR_Y + 0.2, z), Color = Color3.fromRGB(255, 100, 20), Material = Enum.Material.Neon, CanCollide = false }
			addHazard(k, lava, nil, nil, "You fell in the lava! Use the stone bridges.")
			for _ = 1, 2 do
				solid{ Name = "StoneBridge", Size = Vector3.new(8, 1, 16), Position = Vector3.new(rng:NextInteger(-rx(38), rx(38)), FLOOR_Y + 0.9, z), Color = Color3.fromRGB(70, 55, 50), Material = Enum.Material.Basalt }
			end
		end
		for i, x in ipairs({ -rx(30), 0, rx(30) }) do
			crusher(k, x, z0 + 105, Color3.fromRGB(70, 55, 50), 2.6, i * 0.3, "SMASHED by a lava rock!")
		end
	end

	-- gumdrops, a candy hurdle row, a giant lollipop spinner, candy canes sliding
	function OBSTACLES.candy(k, z0, rng)
		local colors = { Color3.fromRGB(255, 90, 170), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 220, 80) }
		for i = 1, 6 do
			local d = rng:NextInteger(8, 11)
			solid{ Name = "Gumdrop", Shape = Enum.PartType.Ball, Size = Vector3.new(d, d, d), Position = Vector3.new(rng:NextInteger(-rx(40), rx(40)), FLOOR_Y + d * 0.2, z0 + rng:NextInteger(75, 95)), Color = colors[i % 3 + 1], Material = Enum.Material.Glass }
		end
		for s = 0, math.floor(W / 10) - 1 do
			solid{ Name = "CandyHurdle", Size = Vector3.new(10, 2, 2), Position = Vector3.new(-HALF_W + 5 + s * 10, FLOOR_Y + 1, z0 + 50), Color = (s % 2 == 0) and Color3.fromRGB(230, 40, 60) or WHITE }
		end
		spinner(k, Vector3.new(0, FLOOR_Y, z0 + 125), 40, Color3.fromRGB(255, 80, 170), 4.2, "A giant lollipop smacked you!")
		slider(k, z0 + 170, Vector3.new(4, 9, 4), Color3.fromRGB(230, 40, 60), nil, 2.8, 0, "A candy cane whacked you!")
	end

	-- laser gates that blink on and off + hover cars zooming across
	function OBSTACLES.neon(k, z0, rng)
		for i, dz in ipairs({ 55, 115, 175 }) do
			local laser = solid{ Name = "Laser", Size = Vector3.new(W, 0.5, 0.5), Position = Vector3.new(0, FLOOR_Y + 1.6, z0 + dz), Color = Color3.fromRGB(255, 40, 60), Material = Enum.Material.Neon, CanCollide = false }
			blinker(k, laser, i * 0.6, 2.4, 1.3, "Zapped by a laser! Jump over them or wait for them to turn off.")
			for _, side in ipairs({ -1, 1 }) do
				solid{ Name = "LaserPost", Size = Vector3.new(1.5, 4, 1.5), Position = Vector3.new(side * (HALF_W - 0.75), FLOOR_Y + 2, z0 + dz), Color = Color3.fromRGB(40, 40, 60) }
			end
		end
		local glows = { Color3.fromRGB(0, 255, 230), Color3.fromRGB(255, 40, 200) }
		for i, dz in ipairs({ 85, 145 }) do
			local car = slider(k, z0 + dz, Vector3.new(11, 3, 6), Color3.fromRGB(60, 60, 90), nil, 2.6, i * 0.4, "Hit by a hover car!", 2.4)
			local glow = Instance.new("SurfaceLight")
			glow.Face = Enum.NormalId.Bottom
			glow.Color = glows[i]
			glow.Range = 8
			glow.Brightness = 3
			glow.Parent = car
		end
	end

	-- crystal walls that zig-zag + crystal shards sliding between them
	function OBSTACLES.crystal(k, z0, rng)
		local colors = { Color3.fromRGB(200, 120, 255), Color3.fromRGB(120, 255, 250), Color3.fromRGB(255, 120, 220) }
		for i, dz in ipairs({ 45, 95, 145, 185 }) do
			local z = z0 + dz
			local gapSide = (i % 2 == 0) and 1 or -1
			local len = W - 28
			local x = -gapSide * (HALF_W - len / 2)
			solid{ Name = "CrystalWall", Size = Vector3.new(len, 10, 3), Position = Vector3.new(x, FLOOR_Y + 5, z), Color = colors[i % 3 + 1], Material = Enum.Material.Glass, Transparency = 0.2 }
			for c = 1, 4 do
				solid{ Name = "CrystalSpike", Size = Vector3.new(2, 5, 2), CFrame = CFrame.new(x - len / 2 + c * (len / 5), FLOOR_Y + 11.5, z) * CFrame.Angles(0, math.rad(45), math.rad(rng:NextInteger(-rx(20), rx(20)))), Color = colors[(i + c) % 3 + 1], Material = Enum.Material.Neon }
			end
		end
		slider(k, z0 + 70, Vector3.new(4, 7, 4), colors[2], Enum.Material.Neon, 2.4, 0, "A crystal shard sliced you!")
		slider(k, z0 + 120, Vector3.new(4, 7, 4), colors[3], Enum.Material.Neon, 2.2, 0.5, "A crystal shard sliced you!")
	end

	-- lightning strikes (yellow circle blinks, then BOOM) + rock spires
	function OBSTACLES.storm(k, z0, rng)
		for i = 1, 7 do
			strike(k, rng:NextInteger(-rx(38), rx(38)), z0 + rng:NextInteger(45, 185), i * 0.95, 4.2, Color3.fromRGB(255, 235, 60), "Struck by lightning! Stay off the yellow circles.")
		end
		for _ = 1, 5 do
			local h = rng:NextInteger(10, 22)
			solid{ Name = "RockSpire", Size = Vector3.new(6, h, 6), CFrame = CFrame.new(rng:NextInteger(-rx(40), rx(40)), FLOOR_Y + h / 2 - 1, z0 + rng:NextInteger(45, 185)) * CFrame.Angles(0.06, rng:NextNumber() * 3, -0.08), Color = Color3.fromRGB(85, 88, 100), Material = Enum.Material.Slate }
		end
	end

	-- holes in the floor (built into the floor) + two void spinners
	function OBSTACLES.void(k, z0, rng)
		spinner(k, Vector3.new(-18, FLOOR_Y, z0 + 70), 34, Color3.fromRGB(190, 70, 255), 3.9, "The void spinner smacked you!")
		spinner(k, Vector3.new(18, FLOOR_Y, z0 + 140), 34, Color3.fromRGB(190, 70, 255), -3.5, "The void spinner smacked you!")
	end

	-- MAP 2 -----------------------------------------------------------

	-- swinging logs on vines
	function OBSTACLES.jungle(k, z0, rng)
		for i, dz in ipairs({ 55, 110, 165 }) do
			local z = z0 + dz
			local top = Vector3.new(rng:NextInteger(-rx(20), rx(20)), FLOOR_Y + 26, z)
			solid{ Name = "VineBranch", Size = Vector3.new(W, 2, 2), Position = Vector3.new(0, top.Y + 1, z), Color = Color3.fromRGB(100, 70, 40), Material = Enum.Material.Wood }
			local opts = { amp = math.rad(60), period = 2.8, phase = i * 0.33, len = 22 }
			-- swings side to side around the branch (the log points down the track)
			mover(k, { Name = "SwingLog", Size = Vector3.new(4, 4, 14), CFrame = CFrame.new(top), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood }, "swing", opts, "A swinging log knocked you out!", Vector3.new(2, 4, 2))
			mover(k, { Name = "Vine", Size = Vector3.new(0.5, 22, 0.5), CFrame = CFrame.new(top), Color = Color3.fromRGB(60, 140, 50) }, "swing", { amp = opts.amp, period = opts.period, phase = opts.phase, len = 11 })
		end
		for _ = 1, 5 do
			solid{ Name = "JungleRock", Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Position = Vector3.new(rng:NextInteger(-rx(40), rx(40)), FLOOR_Y + 1, z0 + rng:NextInteger(70, 190)), Color = Color3.fromRGB(100, 120, 90), Material = Enum.Material.Slate }
		end
	end

	-- ghosts drifting across + tombstones
	function OBSTACLES.haunted(k, z0, rng)
		for i, dz in ipairs({ 50, 90, 130, 170 }) do
			local ghost = slider(k, z0 + dz, Vector3.new(6, 7, 6), Color3.fromRGB(220, 255, 220), Enum.Material.Neon, 3 + i * 0.3, i * 0.21, "BOO! A ghost got you!", 4)
			ghost.Shape = Enum.PartType.Ball
			ghost.Transparency = 0.35
		end
		for _ = 1, 6 do
			solid{ Name = "Tombstone", Size = Vector3.new(5, 6, 1.5), Position = Vector3.new(rng:NextInteger(-rx(42), rx(42)), FLOOR_Y + 3, z0 + rng:NextInteger(40, 190)), Color = Color3.fromRGB(120, 120, 135), Material = Enum.Material.Slate }
		end
	end

	-- two rows of pistons + crates
	function OBSTACLES.factory(k, z0, rng)
		for row, dz in ipairs({ 70, 145 }) do
			for i, x in ipairs({ -rx(36), -rx(12), rx(12), rx(36) }) do
				crusher(k, x, z0 + dz, Color3.fromRGB(110, 115, 125), 2.4, (i + row) * 0.25, "A piston squashed you flat!")
			end
		end
		for _ = 1, 4 do
			solid{ Name = "Crate", Size = Vector3.new(5, 5, 5), Position = Vector3.new(rng:NextInteger(-rx(42), rx(42)), FLOOR_Y + 2.5, z0 + rng:NextInteger(95, 120)), Color = Color3.fromRGB(170, 120, 70), Material = Enum.Material.WoodPlanks }
		end
	end

	-- meteor strikes + spinning satellites
	function OBSTACLES.space(k, z0, rng)
		for i = 1, 7 do
			strike(k, rng:NextInteger(-rx(38), rx(38)), z0 + rng:NextInteger(40, 185), i * 0.8, 3.6, Color3.fromRGB(255, 140, 50), "A meteor landed on you!")
		end
		spinner(k, Vector3.new(-20, FLOOR_Y, z0 + 100), 30, Color3.fromRGB(120, 200, 255), 3, "A satellite smacked you!")
		spinner(k, Vector3.new(20, FLOOR_Y, z0 + 160), 30, Color3.fromRGB(120, 200, 255), -2.8, "A satellite smacked you!")
	end

	-- rainbow spinners + a cloud wall drifting across
	function OBSTACLES.rainbow(k, z0, rng)
		local colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 200, 60), Color3.fromRGB(80, 170, 255) }
		for i, dz in ipairs({ 50, 100, 150 }) do
			spinner(k, Vector3.new((i - 2) * 20, FLOOR_Y, z0 + dz), 40, colors[i], (i % 2 == 0) and -2.6 or 2.4, "The rainbow spinner smacked you!")
		end
		slider(k, z0 + 178, Vector3.new(30, 6, 5), WHITE, nil, 3.4, 0, "You got lost in a cloud!")
	end

	-- lava rivers, fire jets and crushers
	function OBSTACLES.inferno(k, z0, rng)
		for _, dz in ipairs({ 50, 160 }) do
			local z = z0 + dz
			local lava = solid{ Name = "LavaRiver", Size = Vector3.new(W, 0.4, 14), Position = Vector3.new(0, FLOOR_Y + 0.2, z), Color = Color3.fromRGB(255, 70, 20), Material = Enum.Material.Neon, CanCollide = false }
			addHazard(k, lava, nil, nil, "Burned in the inferno! Use the bridges.")
			solid{ Name = "StoneBridge", Size = Vector3.new(8, 1, 16), Position = Vector3.new(rng:NextInteger(-rx(38), rx(38)), FLOOR_Y + 0.9, z), Color = Color3.fromRGB(40, 30, 30), Material = Enum.Material.Basalt }
		end
		for i = 0, 4 do
			local x = rx(-40 + i * 20)
			solid{ Name = "FireVent", Size = Vector3.new(5, 0.6, 5), Position = Vector3.new(x, FLOOR_Y + 0.3, z0 + 100), Color = Color3.fromRGB(40, 30, 30), Material = Enum.Material.Basalt }
			local jet = solid{ Name = "FireJet", Size = Vector3.new(4, 14, 4), Position = Vector3.new(x, FLOOR_Y + 7, z0 + 100), Color = Color3.fromRGB(255, 120, 30), Material = Enum.Material.Neon, CanCollide = false, Transparency = 0.2 }
			blinker(k, jet, i * 0.5, 2.5, 1.2, "Toasted by a fire jet!")
		end
		for i, x in ipairs({ -25, 25 }) do
			crusher(k, x, z0 + 130, Color3.fromRGB(50, 35, 35), 2.2, i * 0.5, "SMASHED by a magma block!")
		end
	end
end

------------------------------------------------------------------------
-- THE SKY WORLD: an ocean far below, little floating islands and clouds
------------------------------------------------------------------------
local GRASS = Color3.fromRGB(95, 200, 75)
local DIRT = Color3.fromRGB(150, 95, 55)
local PATH = Color3.fromRGB(215, 150, 85)

for i = 0, math.ceil((WORLD_END + 800) / 2048) - 1 do
	newPart{ Name = "Ocean", Size = Vector3.new(2048, 2, 2048), Position = Vector3.new(0, -62, -400 + 1024 + i * 2048), Color = Color3.fromRGB(45, 150, 230), Reflectance = 0.12, CanCollide = false, CastShadow = false, Parent = Map }
end

do
	local skyRng = Random.new(77)
	local clouds = math.floor(WORLD_END / 120)
	for i = 1, clouds do
		local side = (i % 2 == 0) and 1 or -1
		local x = side * skyRng:NextInteger(95, 380)
		local y = skyRng:NextInteger(-45, 30)
		local z = skyRng:NextInteger(-150, WORLD_END + 150)
		for c = 1, 4 do
			local d = skyRng:NextInteger(12, 26)
			prop{ Name = "Cloud", Shape = Enum.PartType.Ball, Size = Vector3.one * d, Position = Vector3.new(x + c * 9 - 22, y + skyRng:NextInteger(-3, 4), z + skyRng:NextInteger(-6, 6)), Color = WHITE, CanCollide = false, CastShadow = false }
		end
	end

	local function floatingIsle(x, y, z, size, rng)
		local depth = size * (0.7 + rng:NextNumber() * 0.6)
		textured(prop{ Name = "IsleDirt", Size = Vector3.new(size, depth, size), Position = Vector3.new(x, y - depth / 2, z), Color = DIRT }, Enum.Material.Ground)
		textured(prop{ Name = "IsleDirt", Size = Vector3.new(size * 0.55, depth * 0.7, size * 0.55), Position = Vector3.new(x + size * 0.12, y - depth * 1.35, z - size * 0.1), Color = DIRT:Lerp(BLACK, 0.12) }, Enum.Material.Rock)
		textured(prop{ Name = "IsleGrass", Size = Vector3.new(size + 0.8, 2, size + 0.8), Position = Vector3.new(x, y + 1, z), Color = GRASS }, Enum.Material.Grass)
		if size >= 14 then
			cartoonTree(x, z, size / 18, nil, y + 2)
		else
			bush(x, z, nil, y + 2)
		end
	end
	for i = 1, math.floor(WORLD_END / 230) do
		local side = (i % 2 == 0) and 1 or -1
		floatingIsle(side * skyRng:NextInteger(110, 260), skyRng:NextInteger(-30, 10), skyRng:NextInteger(-100, WORLD_END), skyRng:NextInteger(10, 26), skyRng)
	end
end

local BALLOON_COLORS = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 210, 60), Color3.fromRGB(90, 170, 255), Color3.fromRGB(110, 220, 90), Color3.fromRGB(255, 130, 210) }
local function balloon(x, y, z, color)
	local b = ball(3, x, y, z, color)
	squash(b, 1, 1.2, 1)
	prop{ Name = "BalloonString", Size = Vector3.new(0.08, 6, 0.08), Position = Vector3.new(x, y - 4.8, z), Color = WHITE, CanCollide = false }
end

------------------------------------------------------------------------
-- LEADERBOARDS (top cash, top speed, most pets hatched) - one set on every island
------------------------------------------------------------------------
local LB_STATS = {
	{ key = "cash",    title = "TOP CASH",         color = Color3.fromRGB(110, 230, 90),  prefix = "$" },
	{ key = "speed",   title = "TOP SPEED",        color = Color3.fromRGB(255, 90, 90),   prefix = "" },
	{ key = "hatched", title = "MOST PETS HATCHED", color = Color3.fromRGB(255, 150, 230), prefix = "" },
}
local LB_ROWS = 10
local Boards = {} -- [stat key] = list of { rows = { {name, value}, ... } }

local function buildLeaderboard(stat, x, z)
	local wood = Color3.fromRGB(120, 80, 45)
	local board = newPart{ Name = "Leaderboard_" .. stat.key, Size = Vector3.new(1.2, 18, 20), Position = Vector3.new(x, FLOOR_Y + 12, z), Color = DARK, Parent = Map }
	-- colored frame
	for _, dy in ipairs({ -9.2, 9.2 }) do
		newPart{ Name = "BoardFrame", Size = Vector3.new(1.5, 0.6, 20.6), Position = Vector3.new(x, FLOOR_Y + 12 + dy, z), Color = stat.color, Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
	end
	for _, dz in ipairs({ -10, 10 }) do
		newPart{ Name = "BoardFrame", Size = Vector3.new(1.5, 18.4, 0.6), Position = Vector3.new(x, FLOOR_Y + 12, z + dz), Color = stat.color, Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
		newPart{ Name = "BoardPost", Size = Vector3.new(1.2, 4, 1.2), Position = Vector3.new(x, FLOOR_Y + 1.5, z + dz * 0.8), Color = wood, Material = Enum.Material.Wood, Parent = Map }
	end

	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Right -- faces the middle of the island
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 25
	sg.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.13, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = stat.title
	title.TextColor3 = stat.color
	title.TextStrokeTransparency = 0
	title.Parent = sg
	local rows = {}
	for r = 1, LB_ROWS do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(0.94, 0, 0.083, 0)
		row.Position = UDim2.new(0.03, 0, 0.14 + (r - 1) * 0.085, 0)
		row.BackgroundColor3 = (r % 2 == 0) and Color3.fromRGB(40, 40, 55) or Color3.fromRGB(32, 32, 44)
		row.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.3, 0)
		c.Parent = row
		local function cell(xs, ws, align, color)
			local t = Instance.new("TextLabel")
			t.Size = UDim2.new(ws, 0, 0.9, 0)
			t.Position = UDim2.new(xs, 0, 0.05, 0)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextXAlignment = align
			t.TextColor3 = color
			t.TextStrokeTransparency = 0.4
			t.Text = ""
			t.Parent = row
			return t
		end
		local rankColor = (r == 1 and GOLD) or (r == 2 and Color3.fromRGB(210, 220, 235)) or (r == 3 and Color3.fromRGB(230, 150, 90)) or WHITE
		local rank = cell(0.02, 0.1, Enum.TextXAlignment.Center, rankColor)
		rank.Text = "#" .. r
		local name = cell(0.14, 0.5, Enum.TextXAlignment.Left, WHITE)
		local value = cell(0.64, 0.34, Enum.TextXAlignment.Right, stat.color)
		row.Parent = sg
		rows[r] = { name = name, value = value }
	end
	sg.Parent = board
	Boards[stat.key] = Boards[stat.key] or {}
	table.insert(Boards[stat.key], rows)
end

------------------------------------------------------------------------
-- PET EGGS: a detailed egg on a pedestal, slowly spinning (spun by the World client)
------------------------------------------------------------------------
local EggPrompts = {}

local function buildEggStand(egg, x, z)
	local deckTop = FLOOR_Y + 0.6
	local slate = Color3.fromRGB(62, 64, 84)
	-- pedestal: dark base, gold trim, glowing ring, white column
	local base = newPart{ Name = egg.name .. " Stand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 11, 11), CFrame = CFrame.new(x, deckTop + 0.6, z) * ROT_UP, Color = slate, Parent = Map }
	newPart{ Name = "StandTrim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 11.4, 11.4), CFrame = CFrame.new(x, deckTop + 1.25, z) * ROT_UP, Color = GOLD, Reflectance = 0.2, CanCollide = false, Parent = Map }
	newPart{ Name = "StandGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 9.8, 9.8), CFrame = CFrame.new(x, deckTop + 1.35, z) * ROT_UP, Color = egg.color, Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
	newPart{ Name = "StandColumn", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 7.6, 7.6), CFrame = CFrame.new(x, deckTop + 2.5, z) * ROT_UP, Color = Color3.fromRGB(240, 240, 248), Parent = Map }
	newPart{ Name = "StandTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 8.2, 8.2), CFrame = CFrame.new(x, deckTop + 3.65, z) * ROT_UP, Color = egg.color:Lerp(WHITE, 0.3), CanCollide = false, Parent = Map }
	-- flat neon gems set into the base (nothing sticks out)
	for i = 0, 5 do
		local a = i * math.pi / 3
		local gem = newPart{ Name = "StandGem", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, CFrame = CFrame.new(x + math.cos(a) * 5.15, deckTop + 1.2, z + math.sin(a) * 5.15), Color = egg.spots, Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
		local gm = Instance.new("SpecialMesh")
		gm.MeshType = Enum.MeshType.Sphere
		gm.Scale = Vector3.new(1, 0.25, 1)
		gm.Parent = gem
	end

	-- the egg itself (a model so the client can spin + bob it). Every egg has its
	-- own design, painted flat onto the shell, so nothing sticks out of it.
	local model = Instance.new("Model")
	model.Name = egg.name .. " Display"
	local R, H = 3, 3.9 -- egg radius + half height
	local center = Vector3.new(x, deckTop + 3.8 + H + 0.8, z)
	local rng = Random.new(egg.order * 31 + egg.map * 7)
	local function eggPart(props)
		props.CanCollide = false
		props.CanQuery = false
		props.CastShadow = props.CastShadow or false
		props.Parent = model
		return newPart(props)
	end
	local function sphereMesh(part, scale)
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Scale = scale
		m.Parent = part
		return m
	end
	local function radiusAt(y) return R * math.sqrt(math.max(0, 1 - (y / H) ^ 2)) end

	local design = egg.design
	local bodyColor = egg.color
	if design == "lava" then bodyColor = Color3.fromRGB(55, 35, 32) end
	if design == "cosmic" then bodyColor = Color3.fromRGB(28, 14, 50) end
	local shell = eggPart{ Name = "Egg", Shape = Enum.PartType.Ball, Size = Vector3.one * (R * 2), Position = center, Color = bodyColor, CastShadow = true }
	shell.Material = Enum.Material.SmoothPlastic
	shell.Reflectance = (design == "robo") and 0.25 or 0.06
	sphereMesh(shell, Vector3.new(1, H / R, 1))

	-- a ring hugging the egg at height y: thin slices that follow the egg's curve
	local function band(y, thick, color, material, transparency)
		local n = math.max(1, math.ceil(thick / 0.14))
		for i = 0, n - 1 do
			local sy = y - thick / 2 + (i + 0.5) * thick / n
			if math.abs(sy) < H - 0.05 then
				local d = radiusAt(sy) * 2 + 0.07
				eggPart{ Name = "EggBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(thick / n + 0.01, d, d), CFrame = CFrame.new(center + Vector3.new(0, sy, 0)) * ROT_UP, Color = color, Material = material, Transparency = transparency }
			end
		end
	end
	-- where the shell is at angle theta / height y, facing straight out of it
	local function surface(theta, y, out)
		local r = radiusAt(y)
		local p = Vector3.new(math.cos(theta) * r, y, math.sin(theta) * r)
		local n = Vector3.new(p.X / (R * R), p.Y / (H * H), p.Z / (R * R)).Unit
		local pos = center + p + n * (out or 0.03)
		local up = (math.abs(n.Y) > 0.95) and Vector3.xAxis or Vector3.yAxis
		return CFrame.lookAt(pos, pos + n, up), p
	end
	-- a flat painted oval lying on the shell (w wide, h tall, turned by rot)
	local function paint(theta, y, w, h, color, rot, material, out, transparency)
		local s = math.max(w, h)
		local p = eggPart{ Name = "EggPaint", Shape = Enum.PartType.Ball, Size = Vector3.one * s, CFrame = surface(theta, y, out) * CFrame.Angles(0, 0, rot or 0), Color = color, Material = material, Transparency = transparency }
		sphereMesh(p, Vector3.new(w / s, h / s, 0.12 / s))
		return p
	end
	-- a painted line from (t1, y1) to (t2, y2) along the shell
	local function line(t1, y1, t2, y2, width, color, material)
		local cf = surface((t1 + t2) / 2, (y1 + y2) / 2)
		local _, a = surface(t1, y1)
		local _, b = surface(t2, y2)
		local dir = b - a
		local rot = math.atan2(-dir:Dot(cf.RightVector), dir:Dot(cf.UpVector))
		-- a thin flat strip lying on the shell (segments join into a smooth line)
		return eggPart{ Name = "EggLine", Size = Vector3.new(width, dir.Magnitude + 0.06, 0.08), CFrame = cf * CFrame.Angles(0, 0, rot), Color = color, Material = material }
	end
	-- a painted stripe from the top to the bottom, turned by yaw
	local function meridian(yaw, thick, color, material)
		local steps = 10
		for i = 0, steps - 1 do
			local y1 = -H * 0.93 + (i / steps) * H * 1.86
			local y2 = -H * 0.93 + ((i + 1) / steps) * H * 1.86
			line(yaw, y1, yaw, y2, thick, color, material)
		end
	end
	-- a painted ring tipped over by tilt, turned by yaw (for swirls)
	local function tiltBand(tilt, yaw, thick, color, material)
		local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)
		local pts = {}
		for i = 0, 24 do
			local a = i / 24 * math.pi * 2
			local d = rot:VectorToWorldSpace(Vector3.new(math.cos(a), 0, math.sin(a)))
			local k = 1 / math.sqrt((d.X * d.X + d.Z * d.Z) / (R * R) + d.Y * d.Y / (H * H))
			local p = d * k
			pts[i] = { math.atan2(p.Z, p.X), p.Y }
		end
		for i = 0, 23 do
			local t1, t2 = pts[i][1], pts[i + 1][1]
			if t2 - t1 > math.pi then t2 -= math.pi * 2 elseif t1 - t2 > math.pi then t2 += math.pi * 2 end
			line(t1, pts[i][2], t2, pts[i + 1][2], thick, color, material)
		end
	end
	local TAU = math.pi * 2
	local NEON = Enum.Material.Neon

	if design == "grass" then
		-- a meadow egg: a fringe of grass blades around the bottom, daisies all over
		local leaf = Color3.fromRGB(60, 160, 60)
		band(-3.15, 0.8, leaf:Lerp(BLACK, 0.25))
		for i = 0, 17 do
			local t = i / 18 * TAU
			paint(t, -2.25, 0.42, 1.7, (i % 2 == 0) and leaf or leaf:Lerp(WHITE, 0.25), (i % 3 - 1) * 0.25)
		end
		for i = 0, 21 do
			-- spread evenly over the egg (golden angle)
			local t, y = i * 2.4, -1.0 + (i / 21) * 3.9
			local petal = (i % 3 == 0) and Color3.fromRGB(255, 200, 230) or WHITE
			for k = 0, 2 do
				paint(t, y, 0.3, 1.0, petal, k * math.pi / 3)
			end
			paint(t, y, 0.4, 0.4, Color3.fromRGB(255, 205, 50), 0, nil, 0.05)
		end
	elseif design == "sand" then
		-- desert layers, with a turquoise band of gold diamonds
		local tones = { Color3.fromRGB(205, 150, 85), Color3.fromRGB(225, 180, 110), Color3.fromRGB(185, 125, 70) }
		for i, y in ipairs({ -3.2, -2.5, -1.8, 2.3, 3.0 }) do
			band(y, 0.3 + (i % 2) * 0.15, tones[i % 3 + 1])
		end
		band(0.2, 1.3, Color3.fromRGB(40, 165, 155))
		band(-0.48, 0.12, GOLD)
		band(0.88, 0.12, GOLD)
		for i = 0, 9 do
			paint(i / 10 * TAU, 0.2, 0.55, 0.55, GOLD, math.rad(45))
		end
	elseif design == "ice" then
		-- frozen: big snowflakes under a clear frosty glass shell
		bodyColor = egg.color:Lerp(Color3.fromRGB(60, 140, 220), 0.35)
		shell.Color = bodyColor
		band(-3.15, 0.8, WHITE)
		for i = 0, 11 do
			local t, y = i * 2.4, -1.9 + (i / 11) * 4.6
			for k = 0, 2 do
				paint(t, y, 0.14, 1.5, WHITE, k * math.pi / 3)
				-- little V tips on each arm
				for _, e in ipairs({ -1, 1 }) do
					local cf = surface(t, y)
					local arm = CFrame.Angles(0, 0, k * math.pi / 3)
					local tip = (cf * arm * CFrame.new(0, e * 0.55, 0)).Position - center
					local ty = tip.Y
					local tt = math.atan2(tip.Z, tip.X)
					paint(tt, ty, 0.1, 0.45, WHITE, k * math.pi / 3 + math.pi / 2)
				end
			end
			paint(t, y, 0.3, 0.3, Color3.fromRGB(170, 230, 255), 0, NEON, 0.05)
		end
		local glass = eggPart{ Name = "EggGlass", Shape = Enum.PartType.Ball, Size = Vector3.one * (R * 2 + 0.25), Position = center, Color = Color3.fromRGB(220, 245, 255), Material = Enum.Material.Glass, Transparency = 0.6 }
		sphereMesh(glass, Vector3.new(1, (2 * H + 0.25) / (2 * R + 0.25), 1))
	elseif design == "lava" then
		-- dark rock split by glowing cracks, molten glow at the bottom
		band(-3.2, 0.9, egg.color, NEON)
		for i = 0, 5 do
			local t, y = i / 6 * TAU + rng:NextNumber() * 0.5, -2.9
			while y < 3.1 do
				local nt, ny = t + rng:NextNumber(-0.35, 0.35), y + rng:NextNumber(0.7, 1.1)
				line(t, y, nt, math.min(ny, 3.3), 0.16, (y < 0) and egg.color or egg.spots, NEON)
				t, y = nt, ny
			end
		end
	elseif design == "jungle" then
		-- watermelon-style stripes with a tribal band
		for i = 0, 15 do
			meridian(i / 16 * math.pi * 2, 0.5, egg.color:Lerp(BLACK, 0.35))
		end
		band(0, 1.1, Color3.fromRGB(255, 205, 60))
		band(-0.62, 0.14, Color3.fromRGB(120, 70, 30))
		band(0.62, 0.14, Color3.fromRGB(120, 70, 30))
		for i = 0, 11 do
			paint(i / 12 * TAU, 0, 0.42, 0.42, (i % 2 == 0) and Color3.fromRGB(230, 90, 40) or Color3.fromRGB(40, 140, 70), math.rad(45))
		end
	elseif design == "candy" then
		-- crossing candy swirls + sprinkles
		local swirl = { WHITE, Color3.fromRGB(130, 220, 255), Color3.fromRGB(255, 90, 150) }
		for i = 0, 2 do
			tiltBand(0.55, i * TAU / 3, 0.55, swirl[i + 1])
		end
		local bits = { WHITE, Color3.fromRGB(255, 230, 80), Color3.fromRGB(120, 230, 120), Color3.fromRGB(130, 220, 255) }
		for i = 1, 26 do
			paint(rng:NextNumber() * TAU, rng:NextNumber(-3.2, 3.2), 0.15, 0.48, bits[i % #bits + 1], rng:NextNumber() * math.pi)
		end
	elseif design == "robo" then
		-- shiny metal with glowing circuit lines
		band(-3.0, 0.7, Color3.fromRGB(150, 155, 170))
		band(0, 0.2, egg.spots, NEON)
		for i = 0, 3 do
			meridian(i / 4 * math.pi, 0.14, egg.spots, NEON)
		end
		for i = 0, 7 do
			local t = i / 8 * TAU
			paint(t, 0, 0.6, 0.6, Color3.fromRGB(20, 20, 35), 0, nil, 0.04)
			paint(t, 0, 0.32, 0.32, egg.spots, 0, NEON, 0.06)
		end
		for i = 0, 5 do
			local t = (i + 0.5) / 6 * TAU
			line(t, 1.2, t + 0.3, 1.2, 0.1, egg.spots, NEON)
			line(t + 0.3, 1.2, t + 0.3, 2.1, 0.1, egg.spots, NEON)
			paint(t + 0.3, 2.15, 0.28, 0.28, egg.spots, 0, NEON, 0.05)
		end
	elseif design == "cosmic" then
		-- deep space: a glowing nebula swirl, stars and a shimmering force field
		tiltBand(0.35, 0.6, 1.4, Color3.fromRGB(120, 50, 200), NEON, 0.35)
		tiltBand(-0.5, 2.2, 0.6, egg.spots, NEON, 0.45)
		for _ = 1, 34 do
			local d = rng:NextNumber(0.1, 0.24)
			paint(rng:NextNumber() * TAU, rng:NextNumber(-3.4, 3.4), d, d, WHITE, 0, NEON, 0.05)
		end
		for _ = 1, 4 do
			local t, y = rng:NextNumber() * TAU, rng:NextNumber(-2.5, 2.5)
			paint(t, y, 0.12, 0.9, WHITE, 0, NEON, 0.06)
			paint(t, y, 0.12, 0.9, WHITE, math.pi / 2, NEON, 0.06)
		end
		local field = eggPart{ Name = "EggField", Shape = Enum.PartType.Ball, Size = Vector3.one * (R * 2 + 0.2), Position = center, Color = Color3.fromRGB(200, 120, 255), Material = Enum.Material.ForceField }
		sphereMesh(field, Vector3.new(1, (2 * H + 0.2) / (2 * R + 0.2), 1))
	else
		-- classic: two stripes and painted spots
		band(-1.5, 0.6, egg.spots)
		band(1.5, 0.6, egg.spots)
		for i = 0, 5 do
			paint(i / 6 * TAU + 0.5, 0, 1.1, 1.1, egg.spots)
		end
	end
	-- a soft glossy highlight on the upper left
	paint(math.rad(205), 2.1, 0.55, 1.3, WHITE, 0.35, NEON, 0.08, 0.55)
	model.PrimaryPart = shell
	local light = Instance.new("PointLight")
	light.Color = egg.color
	light.Range = 12
	light.Brightness = 1.2
	light.Parent = shell
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(egg.color:Lerp(WHITE, 0.5))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 4
	sparkle.Parent = shell
	model:SetAttribute("BaseCF", model:GetPivot())
	CollectionService:AddTag(model, "SVB_EggSpin")
	model.Parent = Map

	-- name + price plate leaning at the front (players walk up from -X)
	local plate = newPart{ Name = "PricePlate", Size = Vector3.new(0.4, 2.6, 7.5), CFrame = CFrame.new(x - 6.4, deckTop + 1.2, z) * CFrame.Angles(0, 0, math.rad(-25)), Color = DARK, Parent = Map }
	addSign(plate, Enum.NormalId.Left, {
		{ text = string.upper(egg.name), color = egg.color:Lerp(WHITE, 0.35), weight = 1 },
		{ text = fmt(egg.price) .. " TROPHIES", color = Color3.fromRGB(255, 220, 80), weight = 1 },
	}, 30)

	-- what's inside (pet + chance, colored by rarity)
	local lines = { { text = egg.name .. "  -  " .. fmt(egg.price) .. " Trophies", color = Color3.fromRGB(255, 220, 80) } }
	for _, pet in ipairs(egg.pets) do
		table.insert(lines, { text = pet.name .. "  " .. pet.chance .. "%  (+" .. fmt(pet.bonus) .. "%)", color = RARITY[pet.rarity].color })
	end
	studsBillboard(shell, lines, H + 6, 14, 1.3, 70)
	EggConfigs[egg.name]:SetAttribute("Position", center)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hatch"
	prompt.ObjectText = egg.name .. "  -  " .. fmt(egg.price) .. " Trophies"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	table.insert(EggPrompts, { prompt = prompt, egg = egg })
end

------------------------------------------------------------------------
-- START ISLANDS (one per map): a floating chunk of land, flat in the middle
-- (the flat part is the same size as every zone; blocky terraces wrap around it)
------------------------------------------------------------------------
local PortalPrompts = {}

local function buildStartIsland(map)
	local IL = CONFIG.IslandLength
	-- the island sits at the end of its slot, right before the map's first zone
	local m, oz = map.index, map.oz + L - IL
	local startFloor = newPart{ Name = "Island" .. m .. "Floor", Size = Vector3.new(W, 1, IL), Position = Vector3.new(0, 0, oz + IL / 2), Color = GRASS, Parent = Map }
	textured(startFloor, M.Grass)
	textured(newPart{ Name = "IslandDirt", Size = Vector3.new(W, 44, IL), Position = Vector3.new(0, -22.5, oz + IL / 2), Color = DIRT, Parent = Map }, M.Ground)
	publishZone(map.startG, map.title, WHITE, 0, "start", 0, m, 0, 1)
	floorPatches(map.startG, GRASS, Random.new(2 + m), oz, IL, M.LeafyGrass)

	-- blocky grass terraces stepping up around the edges, with dirt cliffs below
	local terrRng = Random.new(3 + m)
	local terraceTops = {}
	local function terraceColumn(cx, cz, ring)
		local options = (ring == 1 and { 0, 1.5, 3 }) or (ring == 2 and { 3, 5, 7 }) or { 7, 10, 13 }
		local top = FLOOR_Y + options[terrRng:NextInteger(1, 3)]
		local bottom = -44 - terrRng:NextInteger(0, 22)
		textured(newPart{ Name = "TerraceDirt", Size = Vector3.new(10, top - 1.2 - bottom, 10), Position = Vector3.new(cx, (top - 1.2 + bottom) / 2, cz), Color = DIRT:Lerp(BLACK, terrRng:NextNumber() * 0.1), Parent = Map }, M.Ground)
		textured(newPart{ Name = "TerraceGrass", Size = Vector3.new(10.3, 1.2, 10.3), Position = Vector3.new(cx, top - 0.6, cz), Color = GRASS:Lerp(WHITE, terrRng:NextNumber() * 0.08), Parent = Map }, M.Grass)
		table.insert(terraceTops, { x = cx, z = cz, y = top, ring = ring })
	end
	for zc = -25, IL - 5, 10 do
		local backRing = (zc < 0) and math.ceil(-zc / 10) or 0
		for ringIdx = 1, 3 do
			local ring = math.max(ringIdx, backRing)
			terraceColumn(-(HALF_W + ringIdx * 10 - 5), oz + zc, ring)
			terraceColumn(HALF_W + ringIdx * 10 - 5, oz + zc, ring)
		end
	end
	for xc = -HALF_W + 5, HALF_W - 5, 10 do
		for ringIdx = 1, 3 do
			terraceColumn(xc, oz - (ringIdx * 10 - 5), ringIdx)
		end
	end
	for _, t in ipairs(terraceTops) do
		local r = terrRng:NextNumber()
		if t.ring >= 2 and r < 0.2 then
			cartoonTree(t.x, t.z, 0.8 + terrRng:NextNumber() * 0.4, (r < 0.1) and Color3.fromRGB(110, 205, 80) or nil, t.y)
		elseif r < 0.32 then
			bush(t.x, t.z, nil, t.y)
		elseif r < 0.42 then
			for f = 1, 3 do
				flower(t.x + terrRng:NextInteger(-3, 3), t.z + terrRng:NextInteger(-3, 3), PETALS[f % #PETALS + 1], t.y)
			end
		elseif r < 0.47 then
			rock(t.x, t.z, 4, nil, t.y)
		end
	end

	-- title sign on the back hills
	local titleSign = newPart{ Name = "TitleSign", Size = Vector3.new(80, 18, 1.5), Position = Vector3.new(0, FLOOR_Y + 30, oz - 12), Color = DARK, Parent = Map }
	addSign(titleSign, Enum.NormalId.Back, {
		{ text = "SPEED VS BRAINROT", color = Color3.fromRGB(255, 220, 60), weight = 1.4 },
		{ text = string.upper(map.name .. "  -  " .. map.title), color = WHITE, weight = 0.8 },
		{ text = "Boss: " .. map.boss.name, color = map.boss.accent:Lerp(WHITE, 0.3), weight = 0.8 },
	}, 10)
	for _, d in ipairs({ -1, 1 }) do
		newPart{ Name = "SignPost", Size = Vector3.new(2, 24, 2), Position = Vector3.new(d * 34, FLOOR_Y + 10, oz - 12), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood, Parent = Map }
	end
	for i, c in ipairs(BALLOON_COLORS) do
		balloon(-44 + i * 1.6, FLOOR_Y + 40 + (i % 2) * 2, oz - 10, c)
		balloon(44 - i * 1.6, FLOOR_Y + 40 + (i % 2) * 2, oz - 10, c)
	end

	-- dirt paths (fountain -> start line, and speed pad <-> egg row)
	local function pathStrip(x0, x1, z0, z1)
		local p = newPart{ Name = "DirtPath", Size = Vector3.new(x1 - x0, 0.2, z1 - z0), Position = Vector3.new((x0 + x1) / 2, FLOOR_Y + 0.1, oz + (z0 + z1) / 2), Color = PATH, CanCollide = false, Parent = Decor }
		textured(p, M.Cobblestone)
	end
	pathStrip(-8, 8, 48, 190)
	pathStrip(-44, 22, 141, 159)

	-- spawn: a glowing ring close to the start line so the walk is short
	map.spawn = Vector3.new(0, FLOOR_Y, oz + 150)
	if m == 1 then
		local spawnPad = Instance.new("SpawnLocation")
		spawnPad.Name = "Spawn"
		spawnPad.Size = Vector3.new(12, 0.4, 12)
		spawnPad.CFrame = CFrame.new(map.spawn + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, math.pi, 0)
		spawnPad.Anchored = true
		spawnPad.Neutral = true
		spawnPad.Duration = 0
		spawnPad.Transparency = 1
		spawnPad.Parent = Map
	end
	prop{ Name = "SpawnRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 15, 15), CFrame = CFrame.new(map.spawn + Vector3.new(0, 0.32, 0)) * ROT_UP, Color = Color3.fromRGB(255, 215, 50), Material = Enum.Material.Neon, CanCollide = false }
	prop{ Name = "SpawnInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.34, 11.5, 11.5), CFrame = CFrame.new(map.spawn + Vector3.new(0, 0.34, 0)) * ROT_UP, Color = Color3.fromRGB(255, 248, 210), CanCollide = false }
	for i = 0, 7 do
		local a = i * math.pi / 4
		ball(1.2, map.spawn.X + math.cos(a) * 9, FLOOR_Y + 0.6, map.spawn.Z + math.sin(a) * 9, (i % 2 == 0) and Color3.fromRGB(255, 220, 60) or WHITE, Enum.Material.Neon).CanCollide = false
	end

	-- checkered START line, then the RED LINE (cross it and your full speed turns on)
	for i = 0, 21 do
		for r = 0, 1 do
			newPart{ Name = "Checker", Size = Vector3.new(W / 22, 0.22, 2.5), Position = Vector3.new(-HALF_W + (i + 0.5) * (W / 22), FLOOR_Y + 0.11, oz + 191.5 + r * 2.5), Color = ((i + r) % 2 == 0) and WHITE or Color3.fromRGB(25, 25, 30), CanCollide = false, Parent = Decor }
		end
	end
	newPart{ Name = "RedLine", Size = Vector3.new(W, 0.25, 3), Position = Vector3.new(0, FLOOR_Y + 0.12, map.redLineZ), Color = Color3.fromRGB(255, 30, 40), Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
	local redLineTag = newPart{ Name = "RedLineTag", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, FLOOR_Y + 1, map.redLineZ), Transparency = 1, CanCollide = false, CanQuery = false, Parent = Map }
	studsBillboard(redLineTag, {
		{ text = "CROSS THE RED LINE", color = Color3.fromRGB(255, 90, 90) },
		{ text = "your full speed turns on!", color = WHITE },
	}, 11, 24, 2.2, 160)

	-- big red arrows leaning forward, pointing down the track
	local function redArrow(x, z)
		local red = Color3.fromRGB(235, 40, 50)
		local base = CFrame.new(x, FLOOR_Y + 0.3, z) * CFrame.Angles(math.rad(-55), 0, 0)
		block(2.6, 0.5, 5, base * CFrame.new(0, 0, 2.5), red).CanCollide = false
		block(4.6, 0.5, 4.6, base * CFrame.new(0, 0, 6.2) * CFrame.Angles(0, math.rad(45), 0), red).CanCollide = false
	end
	for _, ax in ipairs({ -36, -18, 0, 18, 36 }) do
		redArrow(ax, oz + IL + 6)
	end

	-- a ring of blocks (fountain rims)
	local function ring(cx, y, cz, radius, height, thick, color, segments, material)
		segments = segments or 20
		local segLen = 2 * math.pi * radius / segments * 1.08
		for i = 0, segments - 1 do
			local a = i * 2 * math.pi / segments
			local pos = Vector3.new(cx + math.cos(a) * radius, y + height / 2, cz + math.sin(a) * radius)
			block(segLen, height, thick, CFrame.lookAt(pos, Vector3.new(cx, pos.Y, cz)), color, material)
		end
	end

	-- fountain
	local function buildFountain(cx, cz)
		local stone = Color3.fromRGB(205, 205, 220)
		local waterColor = Color3.fromRGB(90, 190, 255)
		prop{ Name = "FountainBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 20, 20), CFrame = CFrame.new(cx, FLOOR_Y + 0.6, cz) * ROT_UP, Color = stone:Lerp(BLACK, 0.1) }
		ring(cx, FLOOR_Y, cz, 9.6, 2.6, 1.4, stone, 24)
		local water = prop{ Name = "FountainWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 18.4, 18.4), CFrame = CFrame.new(cx, FLOOR_Y + 1.9, cz) * ROT_UP, Color = waterColor, Material = Enum.Material.Glass, Transparency = 0.2 }
		water.CanCollide = false
		prop{ Name = "FountainPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 2.4, 2.4), CFrame = CFrame.new(cx, FLOOR_Y + 5, cz) * ROT_UP, Color = stone }
		prop{ Name = "FountainBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 8, 8), CFrame = CFrame.new(cx, FLOOR_Y + 8.2, cz) * ROT_UP, Color = stone }
		local bowlWater = prop{ Name = "FountainBowlWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 7, 7), CFrame = CFrame.new(cx, FLOOR_Y + 8.85, cz) * ROT_UP, Color = waterColor, Material = Enum.Material.Glass, Transparency = 0.2 }
		bowlWater.CanCollide = false
		local top = ball(2.2, cx, FLOOR_Y + 9.6, cz, waterColor, Enum.Material.Neon)
		local spray = Instance.new("ParticleEmitter")
		spray.Color = ColorSequence.new(Color3.fromRGB(160, 225, 255))
		spray.Size = NumberSequence.new(0.6, 0.2)
		spray.Transparency = NumberSequence.new(0.2, 1)
		spray.Lifetime = NumberRange.new(1, 1.4)
		spray.Speed = NumberRange.new(10, 14)
		spray.SpreadAngle = Vector2.new(25, 25)
		spray.Acceleration = Vector3.new(0, -30, 0)
		spray.Rate = 40
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Parent = top
	end
	buildFountain(0, oz + 36)

	local function bench(x, z, angle)
		local wood, dark = Color3.fromRGB(170, 110, 60), Color3.fromRGB(70, 60, 60)
		local cf = CFrame.new(x, FLOOR_Y, z) * CFrame.Angles(0, angle, 0)
		block(7, 0.6, 2.2, cf * CFrame.new(0, 1.8, 0), wood, Enum.Material.Wood)
		block(7, 2, 0.5, cf * CFrame.new(0, 3, 1), wood, Enum.Material.Wood)
		for _, sx in ipairs({ -3, 3 }) do
			block(0.6, 1.8, 2, cf * CFrame.new(sx, 0.9, 0), dark)
		end
	end
	bench(-15, oz + 36, math.rad(90))
	bench(15, oz + 36, math.rad(-90))

	-- lamp posts along the path with party flags strung between them
	local function lampPost(x, z)
		vcyl(9, 0.8, x, FLOOR_Y, z, Color3.fromRGB(50, 50, 60))
		local bulb = ball(2.2, x, FLOOR_Y + 9.8, z, Color3.fromRGB(255, 240, 180), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 230, 170)
		light.Parent = bulb
		block(2.8, 0.5, 2.8, CFrame.new(x, FLOOR_Y + 11.1, z), Color3.fromRGB(50, 50, 60))
	end
	local function buntingAcross(z, y)
		prop{ Name = "BuntingString", Size = Vector3.new(22, 0.1, 0.1), Position = Vector3.new(0, y, z), Color = WHITE, CanCollide = false }
		for f = 0, 9 do
			prop{ Name = "Flag", Size = Vector3.new(1.6, 1.6, 0.15), CFrame = CFrame.new(-9.9 + f * 2.2, y - 0.9, z) * CFrame.Angles(0, 0, math.rad(45)), Color = BALLOON_COLORS[f % #BALLOON_COLORS + 1], CanCollide = false }
		end
	end
	for _, z in ipairs({ 70, 110, 180 }) do
		lampPost(-11, oz + z)
		lampPost(11, oz + z)
		buntingAcross(oz + z, FLOOR_Y + 8.5)
	end

	local function planter(x, z)
		block(4, 1.4, 10, CFrame.new(x, FLOOR_Y + 0.7, z), Color3.fromRGB(150, 95, 55), Enum.Material.Wood)
		for f = 1, 5 do
			flower(x + math.random(-1, 1), z - 5 + f * 1.7, PETALS[f % #PETALS + 1], FLOOR_Y + 0.8)
		end
	end
	planter(HALF_W - 6, oz + 30)
	planter(HALF_W - 6, oz + 50)

	cartoonTree(-44, oz + 14, 1.1)
	cartoonTree(44, oz + 12, 1, Color3.fromRGB(110, 205, 80))
	bush(-20, oz + 186)
	bush(20, oz + 188)
	bush(-48, oz + 176)

	-- leaderboards along the left edge, facing the middle
	for i, stat in ipairs(LB_STATS) do
		buildLeaderboard(stat, -HALF_W + 3, oz + 40 + i * 24)
	end

	-- The green pad: stand on it to buy speed (cash is only for speed)
	local function buildSpeedPad(cx, cz)
		local size = 22
		local pad = newPart{ Name = "SpeedPad", Size = Vector3.new(size, 0.6, size), Position = Vector3.new(cx, FLOOR_Y + 0.3, cz), Color = Color3.fromRGB(60, 220, 80), Parent = Map }
		addStuds(pad, Enum.NormalId.Top)
		local edge = Color3.fromRGB(160, 255, 130)
		for _, d in ipairs({ -1, 1 }) do
			newPart{ Name = "PadEdge", Size = Vector3.new(size + 2, 0.8, 1), Position = Vector3.new(cx, FLOOR_Y + 0.4, cz + d * (size / 2 + 0.5)), Color = edge, Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
			newPart{ Name = "PadEdge", Size = Vector3.new(1, 0.8, size + 2), Position = Vector3.new(cx + d * (size / 2 + 0.5), FLOOR_Y + 0.4, cz), Color = edge, Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
		end
		studsBillboard(pad, { { text = "BUY SPEED", color = edge } }, 10, 22, 3.4, 200)
		return {
			min = Vector3.new(cx - size / 2, -10, cz - size / 2),
			max = Vector3.new(cx + size / 2, FLOOR_Y + 10, cz + size / 2),
			center = Vector3.new(cx, FLOOR_Y + 0.6, cz),
		}
	end
	map.pad = buildSpeedPad(-30, oz + 150)

	-- How to play sign
	local howTo = newPart{ Name = "HowToSign", Size = Vector3.new(30, 15, 1), Position = Vector3.new(-30, FLOOR_Y + 12.5, oz + 185), Color = DARK, Parent = Map }
	addSign(howTo, Enum.NormalId.Front, {
		{ text = "HOW TO PLAY", color = Color3.fromRGB(255, 220, 60), weight = 1.3 },
		{ text = "1. Grab cash, buy speed on the green pad", color = WHITE },
		{ text = "2. Cross the red line & outrun " .. map.boss.name .. "!", color = WHITE },
		{ text = "3. Make it out of a zone = trophies", color = WHITE },
		{ text = "4. Trophies hatch eggs = pets = more cash", color = WHITE },
		{ text = "Get hit = back to the start!", color = Color3.fromRGB(255, 120, 120) },
	})
	for _, d in ipairs({ -1, 1 }) do
		newPart{ Name = "SignPost", Size = Vector3.new(1, 5, 1), Position = Vector3.new(-30 + d * 12, FLOOR_Y + 2.5, oz + 185), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood, Parent = Map }
	end

	-- PET EGGS: 4 eggs on a grey platform (bought with trophies)
	local petX = 37
	local deckZ = oz + 125
	local deck = newPart{ Name = "EggPlatform", Size = Vector3.new(30, 0.6, 104), Position = Vector3.new(petX, FLOOR_Y + 0.3, deckZ), Color = Color3.fromRGB(215, 215, 228), Parent = Map }
	textured(deck, M.Marble)
	for _, d in ipairs({ -1, 1 }) do
		newPart{ Name = "DeckEdge", Size = Vector3.new(0.8, 0.8, 104), Position = Vector3.new(petX + d * 15, FLOOR_Y + 0.4, deckZ), Color = Color3.fromRGB(255, 140, 230), Material = Enum.Material.Neon, CanCollide = false, Parent = Map }
	end
	local sign = newPart{ Name = "PetSign", Size = Vector3.new(1, 8, 34), Position = Vector3.new(petX + 16.5, FLOOR_Y + 17, deckZ), Color = DARK, Parent = Map }
	addSign(sign, Enum.NormalId.Left, {
		{ text = "PET EGGS", color = Color3.fromRGB(255, 150, 230), weight = 1.3 },
		{ text = "Hatch with trophies  -  Fuse 3 to upgrade", color = WHITE, weight = 0.8 },
	})
	for _, dz in ipairs({ -15, 15 }) do
		newPart{ Name = "SignPost", Size = Vector3.new(1, 14, 1), Position = Vector3.new(petX + 16.5, FLOOR_Y + 7, deckZ + dz), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood, Parent = Map }
		for i, c in ipairs(BALLOON_COLORS) do
			if i <= 3 then
				balloon(petX + 16.5 + (i - 2) * 1.6, FLOOR_Y + 22 + (i % 2) * 1.5, deckZ + dz, c)
			end
		end
	end
	for i, egg in ipairs(map.eggs) do
		buildEggStand(egg, petX, oz + 89 + (i - 1) * 24)
	end
	map.eggSpot = Vector3.new(petX - 13, FLOOR_Y, deckZ - 10)

	-- PORTAL to the other map (locked until you've beaten this one)
	local target = (m < #MAPS) and (m + 1) or 1
	local px, pz = 24, oz + 12
	local stone = Color3.fromRGB(120, 125, 140)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		block(3, 3.6, 2.4, CFrame.new(px + math.cos(a) * 8, FLOOR_Y + 9 + math.sin(a) * 8, pz) * CFrame.Angles(0, 0, a), stone, Enum.Material.Slate)
	end
	local swirlColor = MAPS[target].boss.accent
	local swirl = prop{ Name = "PortalSwirl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 14, 14), CFrame = CFrame.new(px, FLOOR_Y + 9, pz) * CFrame.Angles(0, math.rad(90), 0), Color = swirlColor, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false }
	local pp = Instance.new("ParticleEmitter")
	pp.Color = ColorSequence.new(swirlColor:Lerp(WHITE, 0.4))
	pp.LightEmission = 1
	pp.Size = NumberSequence.new(0.8, 0)
	pp.Lifetime = NumberRange.new(1, 1.6)
	pp.Speed = NumberRange.new(2, 4)
	pp.SpreadAngle = Vector2.new(30, 30)
	pp.Rate = 14
	pp.Parent = swirl
	block(18, 1.4, 6, CFrame.new(px, FLOOR_Y + 0.7, pz), stone, Enum.Material.Slate)
	studsBillboard(swirl, {
		{ text = "TO " .. string.upper(MAPS[target].name), color = swirlColor:Lerp(WHITE, 0.3) },
		{ text = MAPS[target].title, color = WHITE },
	}, 11, 18, 2, 150)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Travel"
	prompt.ObjectText = MAPS[target].name .. "  -  " .. MAPS[target].title
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = swirl
	table.insert(PortalPrompts, { prompt = prompt, target = target })
end

------------------------------------------------------------------------
-- BUILD EVERY MAP: island, zones (each ends with a golden trophy gate), finish
------------------------------------------------------------------------
local FinishTriggers = {}
for m, map in ipairs(MAPS) do
	buildStartIsland(map)
	for j, zone in ipairs(map.zones) do
		local k = zone.g
		local rng = Random.new(1000 + k) -- same layout every time the server starts
		local holey = zone.theme == "void"
		buildZoneShell(k, zone.floor, zone.wall, zone.accent, holey, rng, zone.theme)
		if not holey then floorPatches(k, zone.floor, rng, nil, nil, THEME_LOOK[zone.theme] and THEME_LOOK[zone.theme].patch) end
		decorateZone(k, zone.theme)
		local build = OBSTACLES[zone.theme]
		if build then
			-- obstacle layouts are 200 studs long: repeat them down the whole zone
			for part = 0, math.floor(L / 200) - 1 do
				build(k, k * L + part * 200, rng)
			end
		end
		if j < #map.zones then
			local nextZone = map.zones[j + 1]
			buildTrophyGate((k + 1) * L, {
				{ text = fmt(zone.trophies) .. " TROPHIES", color = Color3.fromRGB(255, 225, 80), weight = 2.2 },
				{ text = "for making it out of ZONE " .. j, color = WHITE, weight = 0.55 },
				{ text = "NEXT: " .. string.upper(nextZone.name) .. "  -  NEED " .. fmt(nextZone.need) .. " SPEED", color = Color3.fromRGB(255, 160, 160), weight = 0.6 },
			}, nextZone.need)
		end
		publishZone(k, zone.name, zone.accent, zone.need, zone.theme, zone.trophies, m, j, zone.pace)
	end

	-- finish line + giant trophy at the end of the map
	local endZ = map.endZ
	local finishZ = endZ - 10
	for i = 0, 21 do
		for r = 0, 1 do
			newPart{ Name = "FinishChecker", Size = Vector3.new(W / 22, 0.22, 2.5), Position = Vector3.new(-HALF_W + (i + 0.5) * (W / 22), FLOOR_Y + 0.11, finishZ - 2.5 + r * 2.5), Color = ((i + r) % 2 == 0) and WHITE or Color3.fromRGB(25, 25, 30), CanCollide = false, Parent = Decor }
		end
	end
	local trigger = newPart{ Name = "FinishTrigger" .. m, Size = Vector3.new(W, 14, 10), Position = Vector3.new(0, FLOOR_Y + 7, finishZ), Transparency = 1, CanCollide = false, Parent = Map }
	FinishTriggers[m] = trigger
	local lastZone = map.zones[#map.zones]
	buildTrophyGate(finishZ - 6, {
		{ text = map.name .. " FINISH!", color = GOLD, weight = 1.2 },
		{ text = fmt(lastZone.trophies) .. " TROPHIES  +1 WIN", color = Color3.fromRGB(255, 225, 80), weight = 1.6 },
		{ text = (m < #MAPS) and ("unlocks " .. MAPS[m + 1].name .. ": " .. MAPS[m + 1].title) or "unlocks PRESTIGE", color = WHITE, weight = 0.6 },
	})
	newPart{ Name = "EndWall", Size = Vector3.new(W + 2, 28, 1), Position = Vector3.new(0, FLOOR_Y + 14, endZ + 0.5), Color = Color3.fromRGB(200, 235, 255), Material = Enum.Material.Glass, Transparency = 0.82, CastShadow = false, Parent = Map }
	do
		local gold = Color3.fromRGB(255, 200, 40)
		local x, z = 0, endZ - 2.5
		block(8, 2, 4, CFrame.new(x, FLOOR_Y + 1, z), Color3.fromRGB(70, 45, 30))
		vcyl(3, 1.6, x, FLOOR_Y + 2, z, gold).Reflectance = 0.3
		vcyl(5, 7, x, FLOOR_Y + 6.5, z, gold).Reflectance = 0.3
		ball(7, x, FLOOR_Y + 6.5, z, gold).Reflectance = 0.3
		for _, sx in ipairs({ -1, 1 }) do
			block(1, 4, 1, CFrame.new(x + sx * 4.4, FLOOR_Y + 9, z) * CFrame.Angles(0, 0, sx * 0.3), gold).Reflectance = 0.3
		end
		vcyl(0.5, 7.4, x, FLOOR_Y + 11.5, z, Color3.fromRGB(255, 235, 120), Enum.Material.Neon)
	end
end

-- Things the client needs to know
local MAP1 = MAPS[1]
workspace:SetAttribute("SpawnPos", MAP1.spawn)
workspace:SetAttribute("PadPos", MAP1.pad.center)
workspace:SetAttribute("RedLineZ", MAP1.redLineZ)
workspace:SetAttribute("MapCount", #MAPS)
workspace:SetAttribute("CashGamepassId", CONFIG.CashGamepassId)
workspace:SetAttribute("PetSlots", CONFIG.PetSlots)

------------------------------------------------------------------------
-- PLAYER DATA
------------------------------------------------------------------------
local Data = {}      -- [player] = { cash, speed, trophies, wins, rebirths, prestige, bestZone, maxMap, hatched, pets }
local HasPass = {}   -- [player] = owns the 3x cash gamepass
local PetBonus = {}  -- [player] = total cash % from equipped pets
local CurMap = {}    -- [player] = the map they're on (respawns + teleports go there)
local Stunned = {}   -- [player] = true while tumbling from a hit

local store
pcall(function()
	store = DataStoreService:GetDataStore(CONFIG.DataStoreName)
end)

local function defaultData()
	return { cash = 0, speed = 0, trophies = 0, wins = 0, rebirths = 0, prestige = 0, bestZone = 0, maxMap = 1, hatched = 0, pets = {} }
end

local function loadData(plr)
	local d = defaultData()
	if store then
		local ok, res = pcall(function()
			return store:GetAsync("p_" .. plr.UserId)
		end)
		if ok and type(res) == "table" then
			for k, v in pairs(res) do
				if k == "pets" and type(v) == "table" then
					for key, count in pairs(v) do
						local name, tier = splitKey(tostring(key))
						if name and PET_BY_NAME[name] and PET_TIERS[tier] and type(count) == "number" and count > 0 then
							d.pets[key] = math.floor(count)
						end
					end
				elseif type(v) == "number" and type(d[k]) == "number" then
					d[k] = v
				end
			end
		end
	end
	d.speed = math.clamp(d.speed, 0, CONFIG.MaxSpeed)
	d.maxMap = math.clamp(d.maxMap, 1, #MAPS)
	return d
end

local function saveData(plr)
	local d = Data[plr]
	if not d or not store then return end
	pcall(function()
		store:SetAsync("p_" .. plr.UserId, d)
	end)
end

local function multiplier(d)
	return 1 + d.rebirths * CONFIG.RebirthBonus
end

local function trophyMultiplier(d)
	return 1 + d.prestige * CONFIG.PrestigeTrophyBonus
end

local function cashMultiplier(plr)
	local d = Data[plr]
	if not d then return 1 end
	return multiplier(d) * (1 + (PetBonus[plr] or 0) / 100) * (HasPass[plr] and 3 or 1) * EventMultiplier
end

local function pointCost(s)
	return math.floor(1 + s * CONFIG.SpeedCostLinear + (s / CONFIG.SpeedCostCurve) ^ 2)
end

-- rebirths need Speed (not cash: cash is only for buying speed)
local function rebirthSpeed(d)
	return math.floor(CONFIG.RebirthSpeedBase * CONFIG.RebirthSpeedGrowth ^ d.rebirths)
end

local function prestigeReady(d)
	return d.bestZone >= FINAL_G
end

-- which zone slot a position is in (nil = off the map / between maps)
local function zoneIndexAt(pos)
	if math.abs(pos.X) > HALF_W + 2 or pos.Y > 60 then return nil end
	local k = math.floor(pos.Z / L)
	if ZONE_AT[k] then return k end
	return nil
end

-- how fast you run right here: walk in the start zone, full (relative) speed past the red line
local function walkSpeedAt(d, pos)
	local k = pos and zoneIndexAt(pos)
	local info = k and ZONE_AT[k]
	if not info then return walkFor(d.speed, 1) end
	if info.j == 0 then
		if pos.Z < info.map.redLineZ then return CONFIG.StartZoneWalkSpeed end
		return walkFor(d.speed, info.map.zones[1].pace)
	end
	return walkFor(d.speed, info.zone.pace)
end

local function applySpeed(plr)
	local d = Data[plr]
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if d and hum then
		local target = walkSpeedAt(d, hrp and hrp.Position)
		if math.abs(hum.WalkSpeed - target) > 0.05 then
			hum.WalkSpeed = target
		end
	end
end

-- your best pets are equipped automatically
local function equippedPets(d)
	local list = {}
	for key, count in pairs(d.pets) do
		for _ = 1, math.min(count, CONFIG.PetSlots) do
			table.insert(list, key)
		end
	end
	table.sort(list, function(a, b) return petBonusOf(a) > petBonusOf(b) end)
	local equipped, total = {}, 0
	for i = 1, math.min(CONFIG.PetSlots, #list) do
		equipped[i] = list[i]
		total += petBonusOf(list[i])
	end
	return equipped, total
end

local function syncPets(plr)
	local d = Data[plr]
	if not d then return end
	local equipped, total = equippedPets(d)
	PetBonus[plr] = total
	plr:SetAttribute("PetsJson", HttpService:JSONEncode(d.pets))
	plr:SetAttribute("EquippedPets", table.concat(equipped, ","))
	plr:SetAttribute("PetBonus", total)
end

-- red speed tag over your head
local function updateSpeedTag(plr)
	local d = Data[plr]
	local head = plr.Character and plr.Character:FindFirstChild("Head")
	if not d or not head then return end
	local tag = head:FindFirstChild("SVB_SpeedTag")
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "SVB_SpeedTag"
		tag.Size = UDim2.fromOffset(150, 30)
		tag.StudsOffset = Vector3.new(0, 3.4, 0)
		tag.MaxDistance = 120
		tag.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 75, 75)
		label.TextStrokeTransparency = 0
		label.Parent = tag
		tag.Parent = head
	end
	tag.Label.Text = fmt(d.speed) .. " SPEED"
end

local function syncStats(plr)
	local d = Data[plr]
	if not d then return end
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		ls.Speed.Value = fmt(d.speed)
		ls.Cash.Value = "$" .. fmt(d.cash)
		ls.Trophies.Value = fmt(d.trophies)
	end
	local mult = cashMultiplier(plr)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	plr:SetAttribute("Cash", d.cash)
	plr:SetAttribute("Speed", d.speed)
	plr:SetAttribute("Trophies", d.trophies)
	plr:SetAttribute("Wins", d.wins)
	plr:SetAttribute("Rebirths", d.rebirths)
	plr:SetAttribute("Prestige", d.prestige)
	plr:SetAttribute("PrestigeReady", prestigeReady(d))
	plr:SetAttribute("TrophyMultiplier", trophyMultiplier(d))
	plr:SetAttribute("BestZone", d.bestZone)
	plr:SetAttribute("MaxMap", d.maxMap)
	plr:SetAttribute("CurrentMap", CurMap[plr] or 1)
	plr:SetAttribute("Hatched", d.hatched)
	plr:SetAttribute("Multiplier", mult)
	plr:SetAttribute("NextMultiplier", mult / multiplier(d) * (1 + (d.rebirths + 1) * CONFIG.RebirthBonus))
	plr:SetAttribute("WalkSpeed", walkSpeedAt(d, hrp and hrp.Position))
	plr:SetAttribute("MaxSpeed", CONFIG.MaxSpeed)
	plr:SetAttribute("NextSpeedCost", pointCost(d.speed))
	plr:SetAttribute("RebirthSpeed", rebirthSpeed(d))
	plr:SetAttribute("HasCashPass", HasPass[plr] == true)
	updateSpeedTag(plr)
end

local function inRegion(pos, region, slack)
	slack = slack or 0
	return pos.X >= region.min.X - slack and pos.X <= region.max.X + slack
		and pos.Z >= region.min.Z - slack and pos.Z <= region.max.Z + slack
		and pos.Y <= region.max.Y + slack
end

------------------------------------------------------------------------
-- TELEPORTS
------------------------------------------------------------------------
-- face = which way you look after teleporting (default: toward the zones)
local function teleportPlayer(plr, pos, face)
	local char = plr.Character
	if not char then return end
	pcall(function()
		plr:RequestStreamAroundAsync(pos, 3)
	end)
	local at = pos + Vector3.new(0, 4, 0)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	char:PivotTo(CFrame.lookAt(at, at + (face or Vector3.zAxis)))
end

local function setMap(plr, m)
	CurMap[plr] = m
	plr:SetAttribute("CurrentMap", m)
end

------------------------------------------------------------------------
-- CASH PICKUPS  (stacks of bills + coins; the World client spins + bobs them)
------------------------------------------------------------------------
local CashFolder = Instance.new("Folder")
CashFolder.Name = "SVB_Cash"
CashFolder.Parent = workspace

local obstacleOverlap = OverlapParams.new()
obstacleOverlap.FilterType = Enum.RaycastFilterType.Include
obstacleOverlap.FilterDescendantsInstances = { Obstacles }

local floorRay = RaycastParams.new()
floorRay.FilterType = Enum.RaycastFilterType.Include
floorRay.FilterDescendantsInstances = { Map }
floorRay.RespectCanCollide = true

-- find a free spot on solid floor that isn't inside an obstacle
local function findCashSpot(k)
	for _ = 1, 12 do
		local x = math.random(-(HALF_W - 16), HALF_W - 16)
		local z = math.random(k * L + 12, (k + 1) * L - 12)
		local blocked = #workspace:GetPartBoundsInBox(CFrame.new(x, FLOOR_Y + 2.5, z), Vector3.new(7, 5, 7), obstacleOverlap) > 0
		if not blocked then
			local hit = workspace:Raycast(Vector3.new(x, FLOOR_Y + 3, z), Vector3.new(0, -8, 0), floorRay)
			if hit and math.abs(hit.Position.Y - FLOOR_Y) < 0.6 then
				return x, z
			end
		end
	end
	return nil
end

local function cashPiece(model, props)
	props.CanCollide = false
	props.CanQuery = false
	props.CastShadow = false
	props.Parent = model
	return newPart(props)
end

local BILL = Color3.fromRGB(80, 200, 85)
local BILL_DARK = Color3.fromRGB(45, 150, 60)
local PAPER = Color3.fromRGB(242, 252, 228)
local BAND = Color3.fromRGB(255, 190, 50)
local COIN = Color3.fromRGB(255, 205, 50)

-- the printed face of a bill: a dark green border, a light middle and a "$" seal
local function billPrint(part, face, rotate)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.LightInfluence = 0.6
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	local border = Instance.new("Frame")
	border.AnchorPoint = Vector2.new(0.5, 0.5)
	border.Position = UDim2.fromScale(0.5, 0.5)
	border.Size = UDim2.fromScale(0.9, 0.8)
	border.BackgroundColor3 = Color3.fromRGB(150, 225, 140)
	border.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(30, 110, 45)
	stroke.Thickness = 3
	stroke.Parent = border
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = border
	local seal = Instance.new("TextLabel")
	seal.AnchorPoint = Vector2.new(0.5, 0.5)
	seal.Position = UDim2.fromScale(0.5, 0.5)
	seal.Size = UDim2.fromScale(0.42, 0.9)
	seal.SizeConstraint = Enum.SizeConstraint.RelativeYY
	seal.BackgroundColor3 = Color3.fromRGB(60, 160, 70)
	seal.Font = Enum.Font.FredokaOne
	seal.Text = "$"
	seal.TextScaled = true
	seal.TextColor3 = Color3.fromRGB(225, 255, 210)
	seal.Rotation = rotate or 0
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.5, 0)
	sc.Parent = seal
	seal.Parent = border
	for _, x in ipairs({ 0.12, 0.88 }) do -- little corner numbers
		local n = Instance.new("TextLabel")
		n.AnchorPoint = Vector2.new(0.5, 0.5)
		n.Position = UDim2.fromScale(x, 0.5)
		n.Size = UDim2.fromScale(0.16, 0.5)
		n.BackgroundTransparency = 1
		n.Font = Enum.Font.FredokaOne
		n.Text = "100"
		n.TextScaled = true
		n.TextColor3 = Color3.fromRGB(30, 110, 45)
		n.Parent = border
	end
	border.Parent = sg
	sg.Parent = part
end

-- one brick of bills: a pale paper stack between green bills, a printed top,
-- and a gold paper band with a "$" on it
local function cashBrick(model, cf, s)
	local paper = cashPiece(model, { Name = "CashBrick", Size = Vector3.new(3.1, 1.0, 1.66) * s, CFrame = cf, Color = PAPER })
	paper.Material = Enum.Material.SmoothPlastic
	local top = cashPiece(model, { Name = "TopBill", Size = Vector3.new(3.24, 0.14, 1.78) * s, CFrame = cf * CFrame.new(0, 0.52 * s, 0), Color = BILL })
	billPrint(top, Enum.NormalId.Top)
	cashPiece(model, { Name = "MidBill", Size = Vector3.new(3.2, 0.09, 1.74) * s, CFrame = cf * CFrame.new(0, 0.05 * s, 0), Color = BILL })
	cashPiece(model, { Name = "BottomBill", Size = Vector3.new(3.24, 0.14, 1.78) * s, CFrame = cf * CFrame.new(0, -0.52 * s, 0), Color = BILL_DARK })
	local band = cashPiece(model, { Name = "Band", Size = Vector3.new(0.7, 1.22, 1.84) * s, CFrame = cf, Color = BAND })
	band.Reflectance = 0.1
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.LightInfluence = 0.6
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "$"
	t.TextColor3 = Color3.fromRGB(150, 95, 15)
	t.Parent = sg
	sg.Parent = band
end

-- a shiny gold coin with a raised rim (cf = its center, flat side facing up)
local function coin(model, cf, s)
	local c = cashPiece(model, { Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 1.25, 1.25) * s, CFrame = cf * ROT_UP, Color = COIN })
	c.Reflectance = 0.3
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Right -- the cylinder's top end
	sg.LightInfluence = 0.6
	sg.CanvasSize = Vector2.new(100, 100)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "$"
	t.TextColor3 = Color3.fromRGB(190, 130, 20)
	t.Parent = sg
	sg.Parent = c
	return c
end

-- a gold bar (a wide base with a narrower top, so it looks like an ingot)
local function goldBar(model, cf, s)
	local g = Color3.fromRGB(255, 200, 40)
	cashPiece(model, { Name = "GoldBar", Size = Vector3.new(2.0, 0.5, 1.0) * s, CFrame = cf, Color = g, Reflectance = 0.35 })
	cashPiece(model, { Name = "GoldBarTop", Size = Vector3.new(1.6, 0.25, 0.7) * s, CFrame = cf * CFrame.new(0, 0.37 * s, 0), Color = g:Lerp(WHITE, 0.25), Reflectance = 0.35 })
end

local function spawnCash(k)
	local x, z = findCashSpot(k)
	if not x then
		task.delay(CONFIG.CashRespawnTime, spawnCash, k)
		return
	end
	local info = ZONE_AT[k]
	local zone = info.zone
	local tier = math.min(3, math.clamp(math.ceil(info.j / #info.map.zones * 2), 1, 2) + (info.m - 1)) -- bigger piles deeper in
	local s = 1 + tier * 0.05
	local ground = CFrame.new(x, FLOOR_Y, z)

	local model = Instance.new("Model")
	model.Name = "Cash"
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)

	local hitbox = newPart{ Name = "Hitbox", Size = Vector3.new(4.5, 4.5, 4.5), CFrame = ground * CFrame.new(0, 2.4, 0), Transparency = 1, CanCollide = false, Parent = model }
	model.PrimaryPart = hitbox

	-- the part that spins + bobs on screen
	local spin = Instance.new("Model")
	spin.Name = "Spin"
	local core = ground * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, math.random() * math.pi, 0)
	if tier == 1 then
		-- one stack, a coin leaning on it
		cashBrick(spin, core * CFrame.Angles(0, 0, math.rad(4)), s)
		for c = 0, 1 do
			coin(spin, core * CFrame.new(-2.1 * s, -0.5 + c * 0.24 * s, 0.4 * s) * CFrame.Angles(0, c, 0), s)
		end
	elseif tier == 2 then
		-- two stacks crossed on top of each other, a little stack of coins
		cashBrick(spin, core, s)
		cashBrick(spin, core * CFrame.new(0.15 * s, 1.24 * s, 0.1 * s) * CFrame.Angles(0, math.rad(35), 0), s * 0.95)
		for c = 0, 2 do
			coin(spin, core * CFrame.new(-2.2 * s, -0.5 + c * 0.24 * s, 0.6 * s) * CFrame.Angles(0, c * 0.6, 0), s)
		end
	else
		-- a little pyramid of stacks, a gold bar and a pile of coins
		cashBrick(spin, core * CFrame.new(0, 0, -0.95 * s), s)
		cashBrick(spin, core * CFrame.new(0, 0, 0.95 * s), s)
		cashBrick(spin, core * CFrame.new(0, 1.24 * s, 0) * CFrame.Angles(0, math.rad(90), 0), s * 0.95)
		goldBar(spin, core * CFrame.new(0, 2.15 * s, 0) * CFrame.Angles(0, math.rad(20), 0), s) -- on top of the pile
		for c = 0, 2 do
			coin(spin, core * CFrame.new(-2.3 * s, -0.5 + c * 0.24 * s, -0.3 * s) * CFrame.Angles(0, c * 0.7, 0), s)
		end
	end
	local anchor = spin:FindFirstChild("CashBrick")
	spin.PrimaryPart = anchor
	spin:SetAttribute("BaseCF", spin:GetPivot())
	spin.Parent = model

	-- little gold sparkles so cash is easy to spot
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkle"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 250, 180))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 4
	sparkle.Parent = hitbox
	local glowLight = Instance.new("PointLight")
	glowLight.Color = Color3.fromRGB(140, 255, 120)
	glowLight.Range = 7
	glowLight.Brightness = 0.8
	glowLight.Parent = hitbox

	-- a soft glowing ring on the floor, with a faint disc inside
	cashPiece(model, { Name = "Glow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 6.4, 6.4), CFrame = ground * CFrame.new(0, 0.08, 0) * ROT_UP, Color = Color3.fromRGB(120, 255, 120), Material = Enum.Material.Neon, Transparency = 0.55 })
	cashPiece(model, { Name = "GlowInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 5.6, 5.6), CFrame = ground * CFrame.new(0, 0.09, 0) * ROT_UP, Color = Color3.fromRGB(70, 160, 70), Transparency = 0.6 })

	-- the value in a little green tag
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(96, 30)
	bb.StudsOffset = Vector3.new(0, 2.4 + tier * 0.9, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	local tag = Instance.new("Frame")
	tag.Size = UDim2.fromScale(1, 1)
	tag.BackgroundColor3 = Color3.fromRGB(25, 90, 35)
	tag.BackgroundTransparency = 0.2
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0.5, 0)
	tc.Parent = tag
	local ts = Instance.new("UIStroke")
	ts.Color = Color3.fromRGB(150, 255, 130)
	ts.Thickness = 2
	ts.Parent = tag
	local value = Instance.new("TextLabel")
	value.Size = UDim2.new(1, -10, 1, -4)
	value.Position = UDim2.fromOffset(5, 2)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.FredokaOne
	value.TextScaled = true
	value.Text = "$" .. fmt(zone.cash)
	value.TextColor3 = Color3.fromRGB(200, 255, 180)
	value.TextStrokeColor3 = Color3.fromRGB(20, 70, 25)
	value.TextStrokeTransparency = 0
	value.Parent = tag
	tag.Parent = bb
	bb.Parent = hitbox

	model.Parent = CashFolder

	local taken = false
	hitbox.Touched:Connect(function(hit)
		if taken then return end
		local plr = getPlayerFromHit(hit)
		local d = plr and Data[plr]
		local hum = plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		if not d or not hum or hum.Health <= 0 or Stunned[plr] then return end
		taken = true
		local amount = zone.cash * cashMultiplier(plr)
		d.cash += amount
		syncStats(plr)
		CashFxRemote:FireAllClients(hitbox.Position, amount, plr)
		model:Destroy()
		task.delay(CONFIG.CashRespawnTime, spawnCash, k)
	end)
end

------------------------------------------------------------------------
-- THE BOSSES  (every map has its own; it appears behind you in the zones and chases you)
------------------------------------------------------------------------
local BossFolder = Instance.new("Folder")
BossFolder.Name = "SVB_Bosses"
BossFolder.Parent = workspace

local Chasers = {} -- [player] = the boss chasing that player

local function bossPart(shape, size, color, material)
	local p = Instance.new("Part")
	if shape then p.Shape = shape end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function weldTo(root, p, offset)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.CFrame = root.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = root.Parent
	return p
end

local function buildBoss(def, ownerName, cf)
	local s = def.size
	local leg = s * 0.45

	local model = Instance.new("Model")
	model.Name = def.name
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(s, s, s)
	root.Transparency = 1
	root.CanCollide = false -- it runs through obstacles and other players
	root.CanQuery = false
	root.CFrame = cf
	root.Parent = model
	model.PrimaryPart = root

	local boxy = def.style == "boxy"
	if boxy then
		-- a chunky block with a lighter belly
		weldTo(root, bossPart(nil, Vector3.new(s, s * 0.9, s), def.body), CFrame.new())
		weldTo(root, bossPart(nil, Vector3.new(s * 1.02, s * 0.3, s * 1.02), def.body:Lerp(WHITE, 0.6)), CFrame.new(0, -s * 0.3, 0))
		for t = -2, 2 do -- a row of teeth
			weldTo(root, bossPart(nil, Vector3.new(s * 0.1, s * 0.14, s * 0.06), WHITE), CFrame.new(t * s * 0.15, -s * 0.12, -s * 0.52) * CFrame.Angles(0, 0, math.rad(45)))
		end
	else
		weldTo(root, bossPart(Enum.PartType.Ball, Vector3.new(s, s, s), def.body), CFrame.new())
		weldTo(root, bossPart(nil, Vector3.new(s * 0.45, s * 0.13, s * 0.1), Color3.fromRGB(40, 10, 10)), CFrame.new(0, -s * 0.15, -s * 0.46))
		for _, sx in ipairs({ -1, 1 }) do -- fangs
			weldTo(root, bossPart(nil, Vector3.new(s * 0.07, s * 0.1, s * 0.05), WHITE), CFrame.new(sx * s * 0.12, -s * 0.1, -s * 0.52))
		end
	end
	local top = boxy and s * 0.45 or s * 0.5

	-- what it wears on its head
	local hat = def.hat or "none"
	if hat == "crown" then
		weldTo(root, bossPart(nil, Vector3.new(s * 0.5, s * 0.1, s * 0.5), GOLD, Enum.Material.Neon), CFrame.new(0, top, 0))
		for _, c in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
			weldTo(root, bossPart(nil, Vector3.new(s * 0.08, s * 0.2, s * 0.08), GOLD, Enum.Material.Neon), CFrame.new(c[1] * s * 0.21, top + s * 0.12, c[2] * s * 0.21))
		end
	elseif hat == "horns" then
		for _, sx in ipairs({ -1, 1 }) do
			weldTo(root, bossPart(nil, Vector3.new(s * 0.12, s * 0.36, s * 0.12), Color3.fromRGB(245, 235, 210)), CFrame.new(sx * s * 0.28, top + s * 0.02, 0) * CFrame.Angles(0, 0, -sx * 0.35))
		end
	elseif hat == "fin" then
		weldTo(root, bossPart(nil, Vector3.new(s * 0.12, s * 0.45, s * 0.5), def.body:Lerp(BLACK, 0.2)), CFrame.new(0, top + s * 0.18, s * 0.1) * CFrame.Angles(math.rad(-20), 0, 0))
	elseif hat == "antenna" then
		for _, sx in ipairs({ -1, 1 }) do
			weldTo(root, bossPart(nil, Vector3.new(s * 0.05, s * 0.4, s * 0.05), BLACK), CFrame.new(sx * s * 0.16, top + s * 0.15, 0) * CFrame.Angles(0, 0, -sx * 0.3))
			weldTo(root, bossPart(Enum.PartType.Ball, Vector3.one * s * 0.14, def.accent, Enum.Material.Neon), CFrame.new(sx * s * 0.23, top + s * 0.36, 0))
		end
	elseif hat == "leaf" then
		weldTo(root, bossPart(nil, Vector3.new(s * 0.06, s * 0.2, s * 0.06), Color3.fromRGB(100, 70, 40)), CFrame.new(0, top + s * 0.08, 0))
		weldTo(root, bossPart(nil, Vector3.new(s * 0.32, s * 0.05, s * 0.18), Color3.fromRGB(70, 190, 70)), CFrame.new(s * 0.14, top + s * 0.17, 0) * CFrame.Angles(0, 0, 0.3))
	elseif hat == "cap" then
		weldTo(root, bossPart(nil, Vector3.new(s * 0.7, s * 0.14, s * 0.7), def.accent), CFrame.new(0, top + s * 0.02, 0))
		weldTo(root, bossPart(nil, Vector3.new(s * 0.7, s * 0.05, s * 0.4), def.accent:Lerp(BLACK, 0.2)), CFrame.new(0, top - s * 0.03, -s * 0.45))
	end

	for _, sx in ipairs({ -1, 1 }) do
		-- eyes (glowing pupils) + angry brows
		weldTo(root, bossPart(Enum.PartType.Ball, Vector3.one * s * 0.3, WHITE), CFrame.new(sx * s * 0.2, s * 0.12, -s * 0.42))
		weldTo(root, bossPart(Enum.PartType.Ball, Vector3.one * s * 0.13, def.eyes or Color3.fromRGB(255, 30, 30), Enum.Material.Neon), CFrame.new(sx * s * 0.2, s * 0.12, -s * 0.56))
		weldTo(root, bossPart(nil, Vector3.new(s * 0.32, s * 0.07, s * 0.1), Color3.fromRGB(25, 20, 20)), CFrame.new(sx * s * 0.2, s * 0.3, -s * 0.47) * CFrame.Angles(0, 0, sx * 0.4))

		-- legs on hip joints (the World client swings them while it runs), with big sneakers
		local legPart = bossPart(nil, Vector3.new(s * 0.18, leg + s * 0.1, s * 0.18), def.accent)
		legPart.Name = "BossLeg"
		legPart.Anchored = false
		legPart.CanCollide = false
		legPart.CanQuery = false
		legPart.Massless = true
		local hip = CFrame.new(sx * s * 0.22, -s / 2 + s * 0.1, 0)
		legPart.CFrame = root.CFrame * hip * CFrame.new(0, -(leg + s * 0.1) / 2, 0)
		legPart.Parent = model
		local motor = Instance.new("Motor6D")
		motor.Name = "LegMotor"
		motor.Part0 = root
		motor.Part1 = legPart
		motor.C0 = hip
		motor.C1 = CFrame.new(0, (leg + s * 0.1) / 2, 0)
		motor:SetAttribute("Side", sx)
		motor.Parent = root
		local shoe = bossPart(nil, Vector3.new(s * 0.3, s * 0.14, s * 0.42), WHITE)
		shoe.Anchored = false
		shoe.CanCollide = false
		shoe.CanQuery = false
		shoe.Massless = true
		shoe.CFrame = legPart.CFrame * CFrame.new(0, -(leg + s * 0.1) / 2 + s * 0.05, -s * 0.06)
		local w = Instance.new("WeldConstraint")
		w.Part0 = legPart
		w.Part1 = shoe
		w.Parent = shoe
		shoe.Parent = model
	end

	local glow = Instance.new("PointLight")
	glow.Color = def.accent
	glow.Range = s * 1.6
	glow.Brightness = 1.5
	glow.Parent = root

	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Color = ColorSequence.new(def.accent)
	burst.LightEmission = 1
	burst.Size = NumberSequence.new(1.5, 0)
	burst.Lifetime = NumberRange.new(0.5, 1)
	burst.Speed = NumberRange.new(20, 35)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Parent = root

	-- dust kicked up behind it
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Rate = 12
	dust.Color = ColorSequence.new(Color3.fromRGB(230, 220, 200))
	dust.Transparency = NumberSequence.new(0.4, 1)
	dust.Size = NumberSequence.new(s * 0.12, s * 0.3)
	dust.Lifetime = NumberRange.new(0.5, 0.8)
	dust.Speed = NumberRange.new(2, 4)
	dust.SpreadAngle = Vector2.new(40, 40)
	dust.EmissionDirection = Enum.NormalId.Back
	local feet = Instance.new("Attachment")
	feet.Position = Vector3.new(0, -s / 2 - leg + s * 0.1, s * 0.2)
	feet.Parent = root
	dust.Parent = feet

	addBillboard(root, {
		{ text = def.name, color = WHITE },
		{ text = "chasing " .. ownerName, color = Color3.fromRGB(255, 110, 110) },
	}, s / 2 + 3.5, 180, 260, 24)

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = leg
	hum.WalkSpeed = 0
	hum.AutoRotate = true
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	hum.Parent = model
	for _, state in ipairs({
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Swimming,
	}) do
		hum:SetStateEnabled(state, false)
	end

	CollectionService:AddTag(model, "SVB_Boss")
	model.Parent = BossFolder
	pcall(function() root:SetNetworkOwner(nil) end)
	return model, root, hum, burst
end

-- where the boss appears: a bit behind you, inside the map's zones
local function behindCFrame(map, ownerPos, s, leg)
	local z = math.max((map.startG + 1) * L + s / 2 + 1, ownerPos.Z - CONFIG.BossHeadStart)
	local x = math.clamp(ownerPos.X, -HALF_W + s / 2 + 1, HALF_W - s / 2 - 1)
	local y = FLOOR_Y + leg + s / 2 + 0.2
	return CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(ownerPos.X, y, ownerPos.Z + 0.01))
end

local function removeChaser(plr)
	local c = Chasers[plr]
	Chasers[plr] = nil
	if c and c.model then c.model:Destroy() end
	if plr.Parent then
		plr:SetAttribute("ChasedBy", nil)
		plr:SetAttribute("BossGap", nil)
		plr:SetAttribute("BossZ", nil)
	end
end

local function spawnChaser(plr, map, ownerPos, zone)
	local def = (zone and zone.boss) or map.boss
	local s = def.size
	local leg = s * 0.45
	local model, root, hum, burst = buildBoss(def, plr.DisplayName, behindCFrame(map, ownerPos, s, leg))
	local c = {
		map = map,
		model = model,
		root = root,
		hum = hum,
		burst = burst,
		name = def.name,
		size = s,
		leg = leg,
		catch = s / 2 + 2.5,
		minX = -HALF_W + s / 2 + 1,
		maxX = HALF_W - s / 2 - 1,
		minZ = (map.startG + 1) * L + s / 2 + 1,
		maxZ = map.endZ - s / 2 - 1,
		readyAt = os.clock() + CONFIG.BossGraceTime,
		zone = zone,
	}
	Chasers[plr] = c
	burst:Emit(40)
	notify(plr, def.name .. " is coming for you! RUN!", Color3.fromRGB(255, 90, 90))
	return c
end

-- the boss's normal speed rises smoothly through each zone
local function bossBaseSpeed(z)
	local k = math.floor(z / L)
	local info = ZONE_AT[k]
	if not info or not info.zone then return CONFIG.BaseWalkSpeed end
	return bossSpeedIn(info.zone, (z - k * L) / L)
end

------------------------------------------------------------------------
-- GETTING HIT: you tumble (the World client animates it), then you're back at the start
------------------------------------------------------------------------
local RunBest = {} -- [player] = farthest zone slot reached this run (you're paid trophies when you leave a zone)

local function hitPlayer(plr, message)
	if Stunned[plr] or plr:GetAttribute("AdminGod") then return end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	Stunned[plr] = true
	plr:SetAttribute("Stunned", true)
	HitRemote:FireClient(plr, message)
	notify(plr, message, Color3.fromRGB(255, 90, 90))
	local c = Chasers[plr]
	if c then
		c.caught = true
		c.hum.WalkSpeed = 0
	end
	task.delay(CONFIG.HitTime, function()
		if not plr.Parent then return end
		removeChaser(plr)
		local map = MAPS[CurMap[plr] or 1]
		teleportPlayer(plr, map.spawn)
		RunBest[plr] = map.startG
		Stunned[plr] = nil
		plr:SetAttribute("Stunned", nil)
		applySpeed(plr)
	end)
end

local function chaserTick()
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local alive = hrp ~= nil and hum ~= nil and hum.Health > 0 and not Stunned[plr]
		local k = alive and zoneIndexAt(hrp.Position) or nil
		local info = k and ZONE_AT[k]
		local c = Chasers[plr]

		if not alive or not info or info.j == 0 or (c and c.map ~= info.map) then
			-- safe on a start island (or between maps): no boss
			if c and not c.caught then removeChaser(plr) end
		else
			local pos = hrp.Position
			if c and not c.caught and c.zone ~= info.zone then
				-- a new zone = a new boss: the old one vanishes and this zone's boss takes over
				local old = c.name
				removeChaser(plr)
				c = spawnChaser(plr, info.map, pos, info.zone)
				notify(plr, old .. " gave up... " .. c.name .. " takes over the chase!", Color3.fromRGB(255, 90, 90))
			end
			if not c and (info.j > 1 or pos.Z >= (info.map.startG + 1) * L + 30) then
				c = spawnChaser(plr, info.map, pos, info.zone)
			end
			if c and not c.caught then
				local bpos = c.root.Position
				if bpos.Y < FLOOR_Y - 10 then
					-- it fell into a hole: put it back behind you
					c.model:PivotTo(behindCFrame(c.map, pos, c.size, c.leg))
					c.readyAt = os.clock() + 0.5
					c.burst:Emit(30)
					bpos = c.root.Position
				end

				local dist = ((pos - bpos) * Vector3.new(1, 0, 1)).Magnitude
				if os.clock() >= c.readyAt then
					local speed = bossBaseSpeed(pos.Z)
					if dist > CONFIG.BossLeash then
						-- you got far ahead: it speeds up so it's always close behind you
						speed = math.max(speed, hum.WalkSpeed * (1 + (dist - CONFIG.BossLeash) / 60))
					end
					c.hum.WalkSpeed = speed
					c.hum:MoveTo(Vector3.new(math.clamp(pos.X, c.minX, c.maxX), FLOOR_Y, math.clamp(pos.Z, c.minZ, c.maxZ)))
				else
					c.hum.WalkSpeed = 0
				end

				plr:SetAttribute("ChasedBy", c.name)
				plr:SetAttribute("BossGap", math.max(0, math.floor(dist - c.catch)))
				plr:SetAttribute("BossZ", bpos.Z)

				if dist <= c.catch and os.clock() >= c.readyAt then
					hitPlayer(plr, c.name .. " caught you! Buy more speed on the green pad.")
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- PER-PLAYER TICK: relative speed, the Speed you need to leave a zone,
-- trophies for leaving zones, new zones reached
------------------------------------------------------------------------
local gateWarned = {}

local function playerTick()
	for _, plr in ipairs(Players:GetPlayers()) do
		local d = Data[plr]
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if d and hrp and hum and hum.Health > 0 and not Stunned[plr] then
			local k = zoneIndexAt(hrp.Position)
			local info = k and ZONE_AT[k]
			if info and CurMap[plr] ~= info.m then
				setMap(plr, info.m)
			end

			-- each zone needs a certain Speed to get into: not enough = pushed back through the gate
			if info and info.zone and d.speed < info.zone.need then
				local back = k * L - 6
				teleportPlayer(plr, Vector3.new(hrp.Position.X, FLOOR_Y, back), -Vector3.zAxis)
				if not gateWarned[plr] or os.clock() - gateWarned[plr] > 2 then
					gateWarned[plr] = os.clock()
					notify(plr, "You need " .. fmt(info.zone.need) .. " Speed to get into " .. info.zone.name .. "!", Color3.fromRGB(255, 110, 110))
				end
				k = k - 1
				info = ZONE_AT[k]
			end

			applySpeed(plr)

			-- made it out of a zone? pay its trophies (once per run)
			if info and info.j == 0 then
				RunBest[plr] = k
			elseif info then
				local prev = RunBest[plr] or info.map.startG
				if prev < info.map.startG or prev > info.map.lastG then prev = info.map.startG end
				if k > prev then
					local earned, lastName = 0, nil
					for j = math.max(prev, info.map.startG + 1), k - 1 do
						earned += ZONE_AT[j].zone.trophies
						lastName = ZONE_AT[j].zone.name
					end
					RunBest[plr] = k
					if earned > 0 then
						earned *= trophyMultiplier(d)
						d.trophies += earned
						syncStats(plr)
						ZoneClearedRemote:FireClient(plr, lastName, earned, info.map.name)
					end
				end
			end

			if k and k > d.bestZone and info then
				d.bestZone = k
				syncStats(plr)
				if k == FINAL_G then
					notify(plr, "You reached the FINAL ZONE! You can PRESTIGE now.", GOLD)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- HAZARDS (lava, goo, lasers, strikes, spinners, crushers, falling off)
------------------------------------------------------------------------
local function hazardTick()
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and not Stunned[plr] then
			local pos = hrp.Position
			if pos.Y < CONFIG.KillHeight then
				hitPlayer(plr, "You fell off!")
			else
				local k = zoneIndexAt(pos)
				for _, h in ipairs((k and Hazards[k]) or {}) do
					if (not h.active or h.active()) and h.check(pos) then
						hitPlayer(plr, h.message)
						break
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- GREEN SPEED PAD (stand on it to buy speed)
------------------------------------------------------------------------
local padTime, padWarned = {}, {}

-- buys up to `want` points of speed with the player's cash, returns how many it bought
local function buySpeed(plr, want)
	local d = Data[plr]
	local n, cost = 0, 0
	while n < want and d.speed + n < CONFIG.MaxSpeed do
		local c = pointCost(d.speed + n)
		if cost + c > d.cash then break end
		cost += c
		n += 1
	end
	if n > 0 then
		d.cash -= cost
		d.speed += n
		applySpeed(plr)
		syncStats(plr)
	end
	return n
end

local function padTick(dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		local d = Data[plr]
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local onPad = false
		if d and hrp and hum and hum.Health > 0 then
			for _, map in ipairs(MAPS) do
				if inRegion(hrp.Position, map.pad) then onPad = true end
			end
		end
		if onPad then
			padTime[plr] = (padTime[plr] or 0) + dt
			local t = padTime[plr]
			-- buys faster the longer you stand on it (and in bigger steps when you're fast)
			local pct = (t > 4 and 0.06) or (t > 1.5 and 0.02) or 0.005
			local want = math.max((t > 4 and 10) or (t > 1.5 and 3) or 1, math.floor(d.speed * pct))
			if buySpeed(plr, want) == 0 and not padWarned[plr] then
				padWarned[plr] = true
				if d.speed >= CONFIG.MaxSpeed then
					notify(plr, "You're at max speed! Try a rebirth.", Color3.fromRGB(255, 200, 80))
				else
					notify(plr, "You need $" .. fmt(pointCost(d.speed)) .. " for more speed. Go grab cash!", Color3.fromRGB(255, 110, 110))
				end
			end
		else
			padTime[plr] = nil
			padWarned[plr] = nil
		end
	end
end

------------------------------------------------------------------------
-- PETS: hatch eggs + fuse 3 of the same pet
------------------------------------------------------------------------
local hatchCooldown = {}

local function hatch(plr, egg)
	local d = Data[plr]
	if not d then return end
	if hatchCooldown[plr] and os.clock() - hatchCooldown[plr] < 1.2 then return end -- room for the hatch animation
	hatchCooldown[plr] = os.clock()
	if d.maxMap < egg.map then
		notify(plr, "Beat " .. MAPS[egg.map - 1].name .. " to unlock the " .. egg.name .. "!", Color3.fromRGB(255, 200, 80))
		return
	end
	if d.trophies < egg.price then
		notify(plr, "You need " .. fmt(egg.price) .. " trophies to hatch the " .. egg.name .. ". Make it through zones for trophies!", Color3.fromRGB(255, 110, 110))
		return
	end
	d.trophies -= egg.price
	d.hatched += 1
	local roll = math.random() * egg.totalChance
	local pet = egg.pets[#egg.pets]
	for _, p in ipairs(egg.pets) do
		roll -= p.chance
		if roll <= 0 then
			pet = p
			break
		end
	end
	local key = petKey(pet.name, 1)
	d.pets[key] = (d.pets[key] or 0) + 1
	syncPets(plr)
	syncStats(plr)
	PetHatchedRemote:FireClient(plr, pet.name, 1, petBonusOf(key), false)
	if pet.rarity >= #RARITY then
		notifyAll(plr.DisplayName .. " hatched a LEGENDARY " .. pet.name .. "!", RARITY[#RARITY].color)
	end
end

for _, entry in ipairs(EggPrompts) do
	entry.prompt.Triggered:Connect(function(plr)
		hatch(plr, entry.egg)
	end)
end

FuseRemote.OnServerEvent:Connect(function(plr, key)
	local d = Data[plr]
	if not d or type(key) ~= "string" then return end
	local name, tier = splitKey(key)
	if not name or not PET_BY_NAME[name] or not tier or tier >= #PET_TIERS then return end
	if (d.pets[key] or 0) < 3 then
		notify(plr, "You need 3 of the same pet to fuse.", Color3.fromRGB(255, 200, 80))
		return
	end
	d.pets[key] -= 3
	if d.pets[key] <= 0 then d.pets[key] = nil end
	local newKey = petKey(name, tier + 1)
	d.pets[newKey] = (d.pets[newKey] or 0) + 1
	syncPets(plr)
	syncStats(plr)
	PetHatchedRemote:FireClient(plr, name, tier + 1, petBonusOf(newKey), true)
end)

------------------------------------------------------------------------
-- MAP TRAVEL (portals, teleport menu)
------------------------------------------------------------------------
local function travel(plr, m)
	local d = Data[plr]
	if not d or not MAPS[m] then return end
	if d.maxMap < m then
		notify(plr, "Beat " .. MAPS[m - 1].name .. " (reach its finish) to unlock " .. MAPS[m].name .. "!", Color3.fromRGB(255, 200, 80))
		return
	end
	removeChaser(plr)
	setMap(plr, m)
	teleportPlayer(plr, MAPS[m].spawn)
	RunBest[plr] = MAPS[m].startG
	applySpeed(plr)
	notify(plr, "Welcome to " .. MAPS[m].name .. ": " .. MAPS[m].title .. "!", MAPS[m].boss.accent)
end

for _, entry in ipairs(PortalPrompts) do
	entry.prompt.Triggered:Connect(function(plr)
		travel(plr, entry.target)
	end)
end

------------------------------------------------------------------------
-- PLAYERS
------------------------------------------------------------------------
Players.RespawnTime = CONFIG.RespawnTime

local function onCharacter(plr, char)
	removeChaser(plr)
	Stunned[plr] = nil
	plr:SetAttribute("Stunned", nil)
	local m = CurMap[plr] or 1
	RunBest[plr] = MAPS[m].startG -- a new run starts
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then applySpeed(plr) end
	if m ~= 1 and char:WaitForChild("HumanoidRootPart", 10) then
		task.defer(teleportPlayer, plr, MAPS[m].spawn) -- respawn on the map you were on
	end
	if char:WaitForChild("Head", 10) then updateSpeedTag(plr) end
end

local function onPlayerAdded(plr)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, statName in ipairs({ "Speed", "Cash", "Trophies" }) do
		local v = Instance.new("StringValue")
		v.Name = statName
		v.Parent = ls
	end
	ls.Parent = plr

	local d = loadData(plr)
	if not plr.Parent then return end -- left while loading
	Data[plr] = d
	CurMap[plr] = 1

	if CONFIG.CashGamepassId > 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, CONFIG.CashGamepassId)
		end)
		HasPass[plr] = ok and owns or false
	end

	syncPets(plr)
	syncStats(plr)
	plr.CharacterAdded:Connect(function(c) onCharacter(plr, c) end)
	if plr.Character then task.spawn(onCharacter, plr, plr.Character) end

	notify(plr, "Buy speed on the GREEN PAD, cross the RED LINE, and make it through zones for trophies!", Color3.fromRGB(255, 220, 60))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end

local lastWin = {}
Players.PlayerRemoving:Connect(function(plr)
	saveData(plr)
	removeChaser(plr)
	Data[plr] = nil
	HasPass[plr] = nil
	PetBonus[plr] = nil
	CurMap[plr] = nil
	Stunned[plr] = nil
	padTime[plr] = nil
	padWarned[plr] = nil
	hatchCooldown[plr] = nil
	RunBest[plr] = nil
	gateWarned[plr] = nil
	lastWin[plr] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		saveData(plr)
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, id, purchased)
	if purchased and id == CONFIG.CashGamepassId and Data[plr] then
		HasPass[plr] = true
		syncStats(plr)
		notify(plr, "3x Cash unlocked!", Color3.fromRGB(110, 255, 90))
	end
end)

------------------------------------------------------------------------
-- REBIRTH (needs Speed, not cash; you keep your pets, trophies and wins)
------------------------------------------------------------------------
RebirthRemote.OnServerEvent:Connect(function(plr)
	local d = Data[plr]
	if not d then return end
	local need = rebirthSpeed(d)
	if d.speed < need then
		notify(plr, "You need " .. fmt(need) .. " Speed to rebirth.", Color3.fromRGB(255, 90, 90))
		return
	end
	d.cash = 0
	d.speed = 0
	d.rebirths += 1
	applySpeed(plr)
	syncStats(plr)
	notify(plr, "REBIRTH! Cash is now x" .. string.format("%.1f", cashMultiplier(plr)), Color3.fromRGB(255, 140, 40))
end)

------------------------------------------------------------------------
-- PRESTIGE (unlocked by reaching the final zone of the final map)
-- start over from Map 1 with a permanent trophy multiplier; you keep pets, rebirths and wins
------------------------------------------------------------------------
PrestigeRemote.OnServerEvent:Connect(function(plr)
	local d = Data[plr]
	if not d then return end
	if not prestigeReady(d) then
		notify(plr, "Reach the final zone (" .. MAPS[#MAPS].zones[#MAPS[#MAPS].zones].name .. ") to prestige!", Color3.fromRGB(255, 200, 80))
		return
	end
	d.prestige += 1
	d.cash = 0
	d.speed = 0
	d.trophies = 0
	d.bestZone = 0
	d.maxMap = 1
	travel(plr, 1)
	syncStats(plr)
	notifyAll(plr.DisplayName .. " reached PRESTIGE " .. d.prestige .. "!", GOLD)
	notify(plr, "PRESTIGE " .. d.prestige .. "! Trophies are now x" .. trophyMultiplier(d), GOLD)
end)

------------------------------------------------------------------------
-- TELEPORT BUTTONS (done on the server so the area loads first)
------------------------------------------------------------------------
TeleportRemote.OnServerEvent:Connect(function(plr, where)
	local map = MAPS[CurMap[plr] or 1]
	if Stunned[plr] then return end
	if where == "spawn" then
		removeChaser(plr)
		teleportPlayer(plr, map.spawn)
	elseif where == "pad" then
		removeChaser(plr)
		teleportPlayer(plr, map.pad.center)
	elseif where == "eggs" then
		removeChaser(plr)
		teleportPlayer(plr, map.eggSpot, Vector3.xAxis)
	elseif type(where) == "string" then
		local m = tonumber(string.match(where, "^map(%d+)$"))
		if m then travel(plr, m) end
	end
end)

------------------------------------------------------------------------
-- FINISH LINES (beat a map = a win, its last zone's trophies, and the next map unlocks)
------------------------------------------------------------------------
for m, trigger in ipairs(FinishTriggers) do
	trigger.Touched:Connect(function(hit)
		local plr = getPlayerFromHit(hit)
		local d = plr and Data[plr]
		if not d or Stunned[plr] then return end
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		if lastWin[plr] and os.clock() - lastWin[plr] < 5 then return end
		lastWin[plr] = os.clock()

		local map = MAPS[m]
		d.wins += 1
		local bonus = CONFIG.WinBonus * m * cashMultiplier(plr)
		local trophies = map.zones[#map.zones].trophies * trophyMultiplier(d) -- leaving the last zone
		d.cash += bonus
		d.trophies += trophies
		d.bestZone = math.max(d.bestZone, map.lastG)
		ZoneClearedRemote:FireClient(plr, map.zones[#map.zones].name, trophies, map.name)
		notifyAll(plr.DisplayName .. " escaped " .. map.boss.name .. " and beat " .. map.name .. "!", GOLD)
		notify(plr, "+1 WIN   +" .. fmt(trophies) .. " trophies   +$" .. fmt(bonus), GOLD)
		removeChaser(plr)
		if m < #MAPS and d.maxMap < m + 1 then
			d.maxMap = m + 1
			syncStats(plr)
			notify(plr, MAPS[m + 1].name .. " UNLOCKED! New boss: " .. MAPS[m + 1].boss.name, MAPS[m + 1].boss.accent)
			travel(plr, m + 1)
		else
			syncStats(plr)
			teleportPlayer(plr, map.spawn)
			RunBest[plr] = map.startG
		end
	end)
end

------------------------------------------------------------------------
-- ADMIN PANEL (server side). The game's owner is always an admin and can add
-- or remove other admins from the panel; the list is saved for every server.
-- Every button press is checked here, so only admins can use it.
------------------------------------------------------------------------
do -- (in its own block so its locals stay out of the main script)
	local TextService = game:GetService("TextService")
	local RunService = game:GetService("RunService")

	local AdminStore
	pcall(function() AdminStore = DataStoreService:GetDataStore("SVB_Admins_v1") end)
	local AdminList = {} -- [userId] = name (the admins the owner added)
	local function loadAdmins()
		if not AdminStore then return end
		local ok, res = pcall(function() return AdminStore:GetAsync("admins") end)
		if ok and type(res) == "table" then
			for id, name in pairs(res) do
				local n = tonumber(id)
				if n then AdminList[n] = tostring(name) end
			end
		end
	end
	local function saveAdmins()
		if not AdminStore then return end
		local out = {}
		for id, name in pairs(AdminList) do out[tostring(id)] = name end
		pcall(function() AdminStore:SetAsync("admins", out) end)
	end
	task.spawn(loadAdmins)

	local groupOwnerCache = {}
	local function isOwner(plr)
		if RunService:IsStudio() then return true end -- testing in Studio: you're the owner
		for _, id in ipairs(CONFIG.OwnerUserIds) do
			if plr.UserId == id then return true end
		end
		if game.CreatorType == Enum.CreatorType.User then
			return plr.UserId == game.CreatorId
		end
		-- a group game: the group's owner (rank 255)
		if groupOwnerCache[plr] == nil then
			local ok, rank = pcall(function() return plr:GetRankInGroup(game.CreatorId) end)
			groupOwnerCache[plr] = ok and rank == 255
		end
		return groupOwnerCache[plr]
	end
	local function isAdmin(plr)
		return isOwner(plr) or AdminList[plr.UserId] ~= nil
	end
	local function refreshAdminFlags(plr)
		plr:SetAttribute("IsOwner", isOwner(plr))
		plr:SetAttribute("IsAdmin", isAdmin(plr))
	end

	local function sendAdminList(plr)
		local list = {}
		for id, name in pairs(AdminList) do table.insert(list, { id = id, name = name }) end
		table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
		AdminRemote:FireClient(plr, "admins", list)
	end

	-- everyone the action is for: one player by UserId, or 0 = everyone in the server
	local function targetsOf(userId)
		if userId == 0 then return Players:GetPlayers() end
		local p = type(userId) == "number" and Players:GetPlayerByUserId(userId)
		return p and { p } or {}
	end

	local function filterText(text, fromPlr)
		local ok, result = pcall(function()
			return TextService:FilterStringAsync(text, fromPlr.UserId):GetNonChatStringForBroadcastAsync()
		end)
		return ok and result or nil
	end

	local adminCooldown = {}
	local ACTIONS = {}

	local function giveStat(stat, label)
		return function(admin, targets, amount)
			amount = tonumber(amount)
			if not amount or amount ~= amount then return end
			amount = math.clamp(math.floor(amount), -1e15, 1e15)
			for _, p in ipairs(targets) do
				local d = Data[p]
				if d then
					d[stat] = math.max(0, d[stat] + amount)
					if stat == "speed" then applySpeed(p) end
					syncStats(p)
					if p ~= admin then notify(p, "An admin gave you " .. fmt(amount) .. " " .. label .. "!", GOLD) end
				end
			end
			return (amount >= 0 and "Gave " or "Took ") .. fmt(math.abs(amount)) .. " " .. label
		end
	end
	ACTIONS.cash = giveStat("cash", "cash")
	ACTIONS.speed = giveStat("speed", "speed")
	ACTIONS.trophies = giveStat("trophies", "trophies")

	function ACTIONS.pet(admin, targets, petName, tier)
		if type(petName) ~= "string" or not PET_BY_NAME[petName] then return end
		tier = math.clamp(tonumber(tier) or 1, 1, #PET_TIERS)
		local key = petKey(petName, tier)
		for _, p in ipairs(targets) do
			local d = Data[p]
			if d then
				d.pets[key] = (d.pets[key] or 0) + 1
				syncPets(p)
				syncStats(p)
				PetHatchedRemote:FireClient(p, petName, tier, petBonusOf(key), tier > 1)
			end
		end
		return "Gave " .. (PET_TIERS[tier].name ~= "" and (PET_TIERS[tier].name .. " ") or "") .. petName
	end

	function ACTIONS.tpTo(admin, targets)
		local t = targets[1]
		local root = t and t ~= admin and t.Character and t.Character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local info = ZONE_AT[zoneIndexAt(root.Position) or -1]
		if info then setMap(admin, info.m) end
		removeChaser(admin)
		teleportPlayer(admin, root.Position + Vector3.new(4, -3, 0))
		return "Teleported to " .. t.DisplayName
	end

	function ACTIONS.bring(admin, targets)
		local root = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local info = ZONE_AT[zoneIndexAt(root.Position) or -1]
		local n = 0
		for _, p in ipairs(targets) do
			if p ~= admin and p.Character then
				if info then setMap(p, info.m) end
				removeChaser(p)
				n += 1
				teleportPlayer(p, root.Position + Vector3.new(math.cos(n) * 5, -3, math.sin(n) * 5))
			end
		end
		return "Brought " .. n .. " player(s)"
	end

	function ACTIONS.toMap(admin, targets, m)
		m = tonumber(m)
		if not m or not MAPS[m] then return end
		for _, p in ipairs(targets) do
			local d = Data[p]
			if d then
				d.maxMap = math.max(d.maxMap, m)
				travel(p, m)
				syncStats(p)
			end
		end
		return "Sent to " .. MAPS[m].name
	end

	function ACTIONS.unlockMaps(admin, targets)
		for _, p in ipairs(targets) do
			local d = Data[p]
			if d then
				d.maxMap = #MAPS
				syncStats(p)
			end
		end
		return "Unlocked every map"
	end

	function ACTIONS.prestigeReady(admin, targets)
		for _, p in ipairs(targets) do
			local d = Data[p]
			if d then
				d.bestZone = math.max(d.bestZone, FINAL_G)
				d.maxMap = #MAPS
				syncStats(p)
			end
		end
		return "Prestige unlocked"
	end

	function ACTIONS.god(admin, targets)
		local state
		for _, p in ipairs(targets) do
			state = not p:GetAttribute("AdminGod")
			p:SetAttribute("AdminGod", state)
			if state then removeChaser(p) end
			if p ~= admin then notify(p, state and "An admin made you unhittable!" or "You can be hit again.", GOLD) end
		end
		return "God mode " .. (state and "ON" or "OFF")
	end

	function ACTIONS.reset(admin, targets)
		for _, p in ipairs(targets) do
			local d = Data[p]
			if d then
				local fresh = defaultData()
				for k in pairs(d) do d[k] = nil end
				for k, v in pairs(fresh) do d[k] = v end
				syncPets(p)
				syncStats(p)
				travel(p, 1)
				notify(p, "An admin reset your progress.", Color3.fromRGB(255, 120, 120))
			end
		end
		return "Reset " .. #targets .. " player(s)"
	end

	function ACTIONS.kick(admin, targets, reason)
		reason = type(reason) == "string" and reason ~= "" and filterText(string.sub(reason, 1, 120), admin) or "Kicked by an admin."
		local n = 0
		for _, p in ipairs(targets) do
			if p ~= admin and not isOwner(p) then
				n += 1
				p:Kick(reason)
			end
		end
		return "Kicked " .. n .. " player(s)"
	end

	function ACTIONS.announce(admin, _, text)
		if type(text) ~= "string" or text == "" then return end
		local clean = filterText(string.sub(text, 1, 150), admin)
		if not clean then return "Message could not be sent" end
		AnnounceRemote:FireAllClients(clean, admin.DisplayName)
		return "Announced"
	end

	function ACTIONS.event(admin, _, mult)
		mult = math.clamp(tonumber(mult) or 1, 1, 100)
		EventMultiplier = mult
		workspace:SetAttribute("CashEvent", mult)
		for _, p in ipairs(Players:GetPlayers()) do syncStats(p) end
		if mult > 1 then
			AnnounceRemote:FireAllClients(mult .. "x CASH EVENT! Every pickup is worth " .. mult .. "x!", "EVENT")
		else
			notifyAll("The cash event has ended.", Color3.fromRGB(255, 200, 80))
		end
		return "Cash event x" .. mult
	end

	function ACTIONS.clearBosses()
		local n = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if Chasers[p] then n += 1 end
			removeChaser(p)
		end
		return "Removed " .. n .. " boss(es)"
	end

	-- owner only
	local function addAdmin(admin, who)
		local userId, name
		if type(who) == "number" then
			local p = Players:GetPlayerByUserId(who)
			userId, name = who, p and p.Name
		elseif type(who) == "string" and who ~= "" then
			local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(who) end)
			if not ok or not id then return "No player called " .. who end
			userId, name = id, who
		end
		if not userId then return end
		if not name then
			local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
			name = ok and n or tostring(userId)
		end
		AdminList[userId] = name
		saveAdmins()
		local p = Players:GetPlayerByUserId(userId)
		if p then
			refreshAdminFlags(p)
			notify(p, "You're an admin now! Press the ADMIN button.", GOLD)
		end
		sendAdminList(admin)
		return name .. " is now an admin"
	end
	local function removeAdmin(admin, userId)
		userId = tonumber(userId)
		if not userId or not AdminList[userId] then return end
		local name = AdminList[userId]
		AdminList[userId] = nil
		saveAdmins()
		local p = Players:GetPlayerByUserId(userId)
		if p then refreshAdminFlags(p) end
		sendAdminList(admin)
		return name .. " is no longer an admin"
	end

	AdminRemote.OnServerEvent:Connect(function(plr, action, target, a, b)
		if not isAdmin(plr) or type(action) ~= "string" then return end
		if adminCooldown[plr] and os.clock() - adminCooldown[plr] < 0.15 then return end
		adminCooldown[plr] = os.clock()
		local result
		if action == "getAdmins" then
			if isOwner(plr) then sendAdminList(plr) end
			return
		elseif action == "addAdmin" or action == "removeAdmin" then
			if not isOwner(plr) then
				notify(plr, "Only the game owner can change admins.", Color3.fromRGB(255, 120, 120))
				return
			end
			result = (action == "addAdmin") and addAdmin(plr, a) or removeAdmin(plr, a)
		else
			local fn = ACTIONS[action]
			if not fn then return end
			local targets = targetsOf(tonumber(target) or -1)
			local ok, res = pcall(fn, plr, targets, a, b)
			if not ok then warn("admin action failed: " .. tostring(res)) end
			result = ok and res or "That didn't work"
		end
		if result then
			AdminRemote:FireClient(plr, "result", result)
			print(("[ADMIN] %s: %s -> %s"):format(plr.Name, action, result))
		end
	end)

	Players.PlayerAdded:Connect(refreshAdminFlags)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(refreshAdminFlags, p) end
	Players.PlayerRemoving:Connect(function(p)
		adminCooldown[p] = nil
		groupOwnerCache[p] = nil
	end)
end

------------------------------------------------------------------------
-- LEADERBOARD UPDATES (global, saved in ordered data stores)
------------------------------------------------------------------------
local LbStores = {}
pcall(function()
	for _, stat in ipairs(LB_STATS) do
		LbStores[stat.key] = DataStoreService:GetOrderedDataStore("SVB_LB_" .. stat.key)
	end
end)

local nameCache = {}
local function nameOf(userId)
	if nameCache[userId] then return nameCache[userId] end
	local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	nameCache[userId] = ok and name or ("Player " .. userId)
	return nameCache[userId]
end

local function statValue(d, key)
	local v = d[key] or 0
	return math.clamp(math.floor(v), 0, 9e18)
end

local function refreshLeaderboards()
	for _, stat in ipairs(LB_STATS) do
		local ods = LbStores[stat.key]
		local entries = {}
		if ods then
			for _, plr in ipairs(Players:GetPlayers()) do
				local d = Data[plr]
				if d then
					pcall(function() ods:SetAsync("p_" .. plr.UserId, statValue(d, stat.key)) end)
				end
			end
			local ok, pages = pcall(function() return ods:GetSortedAsync(false, LB_ROWS) end)
			if ok and pages then
				for _, e in ipairs(pages:GetCurrentPage()) do
					local id = tonumber(string.match(e.key, "^p_(%d+)$"))
					if id then table.insert(entries, { name = nameOf(id), value = e.value }) end
				end
			end
		end
		if #entries == 0 then
			-- no data stores (e.g. Studio without API access): show who's in the server
			for _, plr in ipairs(Players:GetPlayers()) do
				local d = Data[plr]
				if d then table.insert(entries, { name = plr.DisplayName, value = statValue(d, stat.key) }) end
			end
			table.sort(entries, function(a, b) return a.value > b.value end)
		end
		for _, rows in ipairs(Boards[stat.key] or {}) do
			for r = 1, LB_ROWS do
				local e = entries[r]
				rows[r].name.Text = e and e.name or "-"
				rows[r].value.Text = e and (stat.prefix .. fmt(e.value)) or ""
			end
		end
	end
end

------------------------------------------------------------------------
-- START EVERYTHING
------------------------------------------------------------------------
for _, info in ipairs(ZONE_LIST) do
	for _ = 1, CONFIG.CashPerZone do
		spawnCash(info.g)
	end
end

-- relative speed, boss, hazards
task.spawn(function()
	while true do
		task.wait(CONFIG.BossTick)
		playerTick()
		chaserTick()
		hazardTick()
	end
end)

-- green pads
task.spawn(function()
	while true do
		local dt = task.wait(CONFIG.PadBuyInterval)
		padTick(dt)
	end
end)

-- leaderboards
task.spawn(function()
	task.wait(5)
	while true do
		refreshLeaderboards()
		task.wait(CONFIG.LeaderboardRefresh)
	end
end)

-- autosave
task.spawn(function()
	while true do
		task.wait(90)
		for _, plr in ipairs(Players:GetPlayers()) do
			task.spawn(saveData, plr)
		end
	end
end)
