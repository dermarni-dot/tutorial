--[[
	SPEED VS BRAINROT  -  HUD  (LocalScript)
	Put this in: StarterPlayer > StarterPlayerScripts  (next to SpeedVsBrainrot_World)

	What it adds:
	  - Three chunky studded stat tiles on the left: Speed (red, a sneaker),
	    Cash (green, a cash brick) and Trophies (yellow, a trophy). The numbers
	    count up and the tile bounces when they go up.
	  - Six square buttons under them:
	      Teleport  (a swirling portal)   - spawn, the speed pad, the eggs, Map 1 / Map 2
	      3x Cash   (an angry bat)        - your gamepass ("ONLY <robux>price!" above it)
	      Invite    (two friends)         - invite friends ("Play with friends!")
	      Pets      (a puppy)             - your pets, what they give, and Fuse 3 -> 1 better pet
	      Rebirth   (orange arrows)       - reset cash + speed for a cash multiplier
	      Prestige  (a gold star)         - lights up once you reach the final zone
	  - When you collect cash: a big cash brick with "+545" pops up on the
	    screen, wiggles, then flies into your Cash tile. Around your character
	    (everyone sees it): a green swirl, a green glow, rings rippling out on
	    the floor, bills and coins bursting out and "$" signs floating up.
	  - When you make it out of a zone: a "ZONE CLEARED" card with a shine,
	    the trophies counting up, then flying into your Trophies tile.
	  - Hatching an egg: the screen dims, the egg wobbles, cracks, flashes and
	    pops open to show your pet (with its rarity) in front of spinning rays.

	No emojis and no uploaded images: every icon is drawn out of rounded
	frames (see ICONS below), so it looks the same on every device.

	It reads the stats the server puts on your player (Cash, Speed, Trophies,
	HasCashPass, PetsJson, EquippedPets, MaxMap, PrestigeReady, ...) and uses the
	server's remotes (CashFx, Teleport, Fuse, Rebirth, Prestige, PetHatched,
	ZoneCleared).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVB_Remotes")
local CashFxRemote = remotes:WaitForChild("CashFx")
local TeleportRemote = remotes:WaitForChild("Teleport")
local FuseRemote = remotes:WaitForChild("Fuse")
local RebirthRemote = remotes:WaitForChild("Rebirth")
local PrestigeRemote = remotes:WaitForChild("Prestige")
local PetHatchedRemote = remotes:WaitForChild("PetHatched")
local ZoneClearedRemote = remotes:WaitForChild("ZoneCleared")
local PetInfo = ReplicatedStorage:WaitForChild("SVB_Pets")
local MapInfo = ReplicatedStorage:WaitForChild("SVB_Maps")

local ROBUX = utf8.char(0xE002) -- the Robux symbol in Roblox fonts
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)

local COLORS = {
	speed = Color3.fromRGB(228, 52, 58),
	cash = Color3.fromRGB(52, 192, 48),
	trophies = Color3.fromRGB(240, 196, 30),
	teleport = Color3.fromRGB(92, 190, 240),
	pass = Color3.fromRGB(46, 170, 70),
	invite = Color3.fromRGB(250, 208, 40),
	pets = Color3.fromRGB(80, 178, 238),
	rebirth = Color3.fromRGB(250, 140, 40),
	prestige = Color3.fromRGB(150, 90, 235),
}

-- ICONS BEGIN
------------------------------------------------------------------------
-- ICONS: each icon is a list of shapes on a 1 x 1 square (x, y = the
-- shape's center, w, h = its size, all 0..1; y goes down).
--   r     = how round the corners are (0.5 = a circle / pill)
--   rot   = rotation in degrees
--   ring  = only the outline (no fill), line = outline thickness (at 100 px)
--   flat  = no top-to-bottom shading, a = transparency
--   text  = a little text on the shape (tc = its color)
-- Shapes are drawn in order, so later ones sit on top.
------------------------------------------------------------------------
local ICONS = {}
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function S(x, y, w, h, c, opts)
	local sh = { x = x, y = y, w = w, h = h, c = c }
	for k, v in pairs(opts or {}) do
		sh[k] = v
	end
	return sh
end

-- a red sneaker (facing right)
function ICONS.shoe()
	local red, white = rgb(235, 55, 65), rgb(250, 250, 250)
	local list = {
		S(0.5, 0.78, 0.88, 0.15, white, { r = 0.5 }),
		S(0.36, 0.56, 0.5, 0.42, red, { r = 0.38 }),
		S(0.66, 0.64, 0.52, 0.27, red, { r = 0.5 }),
		S(0.44, 0.4, 0.15, 0.22, rgb(255, 120, 120), { r = 0.4, rot = 20 }),
		S(0.27, 0.38, 0.24, 0.1, rgb(150, 25, 35), { r = 0.5, flat = true }),
		S(0.5, 0.64, 0.36, 0.07, white, { r = 0.5, rot = -12, flat = true }),
		S(0.5, 0.74, 0.86, 0.03, rgb(190, 190, 200), { flat = true, line = 0 }),
	}
	for i = 0, 2 do
		table.insert(list, S(0.47 + i * 0.07, 0.47 + i * 0.045, 0.11, 0.035, white, { r = 0.5, rot = 25, line = 0, flat = true }))
	end
	return list
end

-- a stack of cash: green bills, a lighter top, a yellow paper band
function ICONS.cash()
	-- a chunky 3D stack of bills, tipped up a little: the front (with the
	-- edges of the bills), a lighter top, the darker end, and a yellow paper
	-- band wrapping over the top and down the front. Each face is placed in
	-- the brick's own tilted space so the faces meet up.
	local ang = math.rad(-14)
	local cx, cy = 0.5, 0.56
	local cs, sn = math.cos(ang), math.sin(ang)
	local k = 1.14 -- (a touch bigger than the shapes below)
	local function at(lx, ly, w, h, c, opts)
		local o = { rot = -14 }
		for key, v in pairs(opts or {}) do
			o[key] = v
		end
		lx, ly = lx * k, ly * k
		return S(cx + lx * cs - ly * sn, cy + lx * sn + ly * cs, w * k, h * k, c, o)
	end
	local edge = { line = 0, flat = true }
	return {
		at(0.4, -0.06, 0.1, 0.32, rgb(35, 135, 45), { r = 0.1 }), -- the end
		at(0, 0.04, 0.76, 0.3, rgb(60, 185, 65), { r = 0.08 }), -- the front
		at(0, -0.04, 0.72, 0.025, rgb(25, 105, 35), edge),
		at(0, 0.04, 0.72, 0.025, rgb(25, 105, 35), edge),
		at(0, 0.12, 0.72, 0.025, rgb(25, 105, 35), edge),
		at(0.05, -0.17, 0.76, 0.13, rgb(150, 238, 120), { r = 0.12 }), -- the top
		at(0.05, -0.17, 0.66, 0.025, rgb(205, 255, 185), edge), -- a shine on top
		at(0.02, 0.04, 0.17, 0.3, rgb(240, 160, 30), { r = 0.04 }), -- the band (front)
		at(0.07, -0.17, 0.17, 0.13, rgb(255, 215, 80), { r = 0.04 }), -- the band (top)
	}
end

-- a gold trophy with a "1" on it
function ICONS.trophy()
	local gold, dark = rgb(255, 200, 40), rgb(200, 140, 20)
	return {
		S(0.22, 0.33, 0.22, 0.26, gold, { ring = true, line = 6, r = 0.5 }),
		S(0.78, 0.33, 0.22, 0.26, gold, { ring = true, line = 6, r = 0.5 }),
		S(0.5, 0.64, 0.12, 0.18, dark, {}),
		S(0.5, 0.42, 0.52, 0.32, gold, { r = 0.5 }),
		S(0.5, 0.28, 0.54, 0.34, gold, { r = 0.22 }),
		S(0.36, 0.28, 0.06, 0.18, rgb(255, 245, 190), { r = 0.5, line = 0, flat = true, a = 0.2 }),
		S(0.5, 0.36, 0.22, 0.22, rgb(255, 225, 110), { r = 0.5, text = "1", tc = rgb(205, 45, 35) }),
		S(0.5, 0.74, 0.4, 0.08, gold, { r = 0.3 }),
		S(0.5, 0.85, 0.54, 0.15, rgb(120, 70, 40), { r = 0.2 }),
		S(0.5, 0.85, 0.3, 0.06, gold, { line = 0, flat = true }),
	}
end

-- a stone teleport portal with a pink swirl inside
function ICONS.portal()
	return {
		-- an eight-sided stone frame (two turned squares)
		S(0.5, 0.5, 0.86, 0.86, rgb(145, 150, 165), { r = 0.18 }),
		S(0.5, 0.5, 0.86, 0.86, rgb(145, 150, 165), { r = 0.18, rot = 45 }),
		S(0.5, 0.5, 0.8, 0.8, rgb(215, 218, 228), { r = 0.5, ring = true, line = 3 }),
		S(0.5, 0.5, 0.72, 0.72, rgb(230, 60, 170), { r = 0.5 }),
		S(0.54, 0.46, 0.52, 0.52, rgb(150, 50, 220), { r = 0.5, line = 0 }),
		S(0.47, 0.53, 0.36, 0.36, rgb(255, 120, 210), { r = 0.5, line = 0 }),
		S(0.53, 0.48, 0.2, 0.2, rgb(255, 210, 245), { r = 0.5, line = 0 }),
		S(0.5, 0.5, 0.08, 0.08, rgb(255, 255, 255), { r = 0.5, line = 0, flat = true }),
	}
end

-- an angry purple bat (the 3x cash pass)
function ICONS.bat()
	local wing, body = rgb(48, 42, 60), rgb(66, 58, 82)
	local list = {}
	for _, side in ipairs({ -1, 1 }) do
		local function wx(x)
			return if side < 0 then x else 1 - x
		end
		table.insert(list, S(wx(0.25), 0.4, 0.38, 0.15, wing, { r = 0.5, rot = side * 30 }))
		table.insert(list, S(wx(0.22), 0.52, 0.4, 0.15, wing, { r = 0.5, rot = side * 5 }))
		table.insert(list, S(wx(0.26), 0.63, 0.34, 0.14, wing, { r = 0.5, rot = -side * 20 }))
		table.insert(list, S(wx(0.38), 0.32, 0.11, 0.17, body, { r = 0.2, rot = side * 20 }))
	end
	table.insert(list, S(0.5, 0.55, 0.4, 0.44, body, { r = 0.5 }))
	for _, side in ipairs({ -1, 1 }) do
		table.insert(list, S(0.5 + side * 0.08, 0.5, 0.11, 0.11, rgb(255, 50, 50), { r = 0.5, flat = true }))
		table.insert(list, S(0.5 + side * 0.065, 0.48, 0.035, 0.035, rgb(255, 255, 255), { r = 0.5, line = 0, flat = true }))
		table.insert(list, S(0.5 + side * 0.09, 0.42, 0.13, 0.035, rgb(30, 15, 40), { rot = side * 22, line = 0, flat = true }))
		table.insert(list, S(0.5 + side * 0.04, 0.665, 0.04, 0.07, rgb(255, 255, 255), { line = 0, flat = true }))
	end
	return list
end

-- two friends
function ICONS.friends()
	local skin = rgb(255, 210, 80)
	-- blocky Roblox-style heads with a smile
	local function person(x, y, sz, shirt, hair)
		return {
			S(x, y + 0.38 * sz, 0.66 * sz, 0.42 * sz, shirt, { r = 0.3 }),
			S(x, y, 0.56 * sz, 0.52 * sz, skin, { r = 0.24 }),
			S(x, y - 0.21 * sz, 0.58 * sz, 0.14 * sz, hair, { r = 0.3 }),
			S(x - 0.1 * sz, y - 0.02 * sz, 0.06 * sz, 0.09 * sz, rgb(40, 30, 30), { r = 0.5, line = 0, flat = true }),
			S(x + 0.1 * sz, y - 0.02 * sz, 0.06 * sz, 0.09 * sz, rgb(40, 30, 30), { r = 0.5, line = 0, flat = true }),
			S(x, y + 0.12 * sz, 0.22 * sz, 0.05 * sz, rgb(40, 30, 30), { r = 0.5, line = 0, flat = true }),
		}
	end
	local list = person(0.66, 0.42, 0.62, rgb(60, 140, 230), rgb(120, 70, 40))
	for _, sh in ipairs(person(0.38, 0.5, 0.74, rgb(240, 110, 60), rgb(70, 45, 30))) do
		table.insert(list, sh)
	end
	return list
end

-- a pet, drawn by its style (bunny, pup, cat, fox, wolf, bear, bee, beetle,
-- penguin, dragon, slime, bird, cloud, unicorn, robot, bat, wisp, overlord),
-- in its own colors. With no style it's a puppy (the Pets button).
function ICONS.pet(body, accent, style)
	body = body or rgb(200, 140, 80)
	accent = accent or rgb(140, 85, 45)
	style = style or "pup"
	local black, white = rgb(0, 0, 0), rgb(255, 255, 255)
	local ink = rgb(30, 25, 30)
	local pink = rgb(255, 130, 160)
	local light = body:Lerp(white, 0.55)
	-- dark pets get light eyes so you can still see them
	if body.R * 0.3 + body.G * 0.59 + body.B * 0.11 < 0.3 then
		ink = rgb(245, 245, 255)
	end
	local list = {}
	local function add(...)
		for _, sh in ipairs({ ... }) do
			table.insert(list, sh)
		end
	end
	local function flat(x, y, w, h, c, extra)
		local o = { r = 0.5, line = 0, flat = true }
		for k, v in pairs(extra or {}) do
			o[k] = v
		end
		return S(x, y, w, h, c, o)
	end
	-- a pointy ear: a turned square, half hidden behind the head
	local function pointyEar(x, y, size, tilt, inner)
		add(S(x, y, size, size, body, { r = 0.12, rot = 45 + tilt }))
		if inner then
			add(flat(x, y + size * 0.08, size * 0.55, size * 0.55, inner, { r = 0.12, rot = 45 + tilt }))
		end
	end
	-- the eyes: big and shiny (tall ovals for most, visor slits for robots)
	local function eyes(y, gap, size, color)
		for _, sx in ipairs({ -1, 1 }) do
			add(flat(0.5 + sx * gap, y, size, size * 1.3, color or ink))
			add(flat(0.5 + sx * gap - size * 0.18, y - size * 0.3, size * 0.4, size * 0.4, white))
		end
	end
	local function cheeks(y, gap)
		for _, sx in ipairs({ -1, 1 }) do
			add(flat(0.5 + sx * gap, y, 0.1, 0.06, pink, { a = 0.4 }))
		end
	end
	local function head(x, y, w, h, c)
		add(S(x or 0.5, y or 0.54, w or 0.66, h or 0.6, c or body, { r = 0.5 }))
	end
	local function muzzle(y, nose)
		add(S(0.5, y or 0.66, 0.34, 0.24, light, { r = 0.5, line = 1.5 }))
		add(flat(0.5, (y or 0.66) - 0.05, 0.12, 0.08, nose or ink))
	end

	if style == "bunny" then
		for _, sx in ipairs({ -1, 1 }) do
			add(S(0.5 + sx * 0.14, 0.2, 0.15, 0.42, body, { r = 0.5, rot = sx * 10 }))
			add(flat(0.5 + sx * 0.14, 0.22, 0.07, 0.3, accent, { rot = sx * 10 }))
		end
		head()
		eyes(0.5, 0.12, 0.08)
		muzzle(0.66, pink)
		add(flat(0.5, 0.75, 0.08, 0.06, white)) -- teeth
		cheeks(0.62, 0.22)
	elseif style == "cat" or style == "fox" or style == "wolf" then
		local ear = style == "cat" and 0.22 or 0.26
		pointyEar(0.27, 0.27, ear, -10, style == "wolf" and body:Lerp(black, 0.3) or accent)
		pointyEar(0.73, 0.27, ear, 10, style == "wolf" and body:Lerp(black, 0.3) or accent)
		head()
		if style == "fox" then
			add(flat(0.36, 0.66, 0.28, 0.22, white), flat(0.64, 0.66, 0.28, 0.22, white))
		end
		eyes(0.5, 0.13, 0.08, style == "cat" and rgb(60, 160, 60) or nil)
		if style == "wolf" then
			add(flat(0.37, 0.4, 0.14, 0.035, ink, { rot = 15 }), flat(0.63, 0.4, 0.14, 0.035, ink, { rot = -15 }))
		end
		add(flat(0.5, 0.62, 0.09, 0.06, style == "cat" and pink or ink))
		for _, sx in ipairs({ -1, 1 }) do -- whiskers
			add(flat(0.5 + sx * 0.25, 0.66, 0.18, 0.02, ink, { a = 0.3, rot = sx * 8 }))
			add(flat(0.5 + sx * 0.25, 0.71, 0.18, 0.02, ink, { a = 0.3, rot = -sx * 8 }))
		end
		cheeks(0.62, 0.2)
	elseif style == "bear" then
		for _, sx in ipairs({ -1, 1 }) do
			add(S(0.5 + sx * 0.26, 0.26, 0.22, 0.22, body, { r = 0.5 }))
			add(flat(0.5 + sx * 0.26, 0.27, 0.11, 0.11, accent))
		end
		head()
		eyes(0.48, 0.13, 0.075)
		muzzle(0.66)
		cheeks(0.6, 0.22)
	elseif style == "bee" then
		for _, sx in ipairs({ -1, 1 }) do -- wings and feelers
			add(S(0.5 + sx * 0.3, 0.3, 0.26, 0.2, rgb(220, 240, 255), { r = 0.5, rot = sx * 30, a = 0.25 }))
			add(flat(0.5 + sx * 0.1, 0.16, 0.03, 0.18, ink, { rot = sx * 20 }))
			add(flat(0.5 + sx * 0.14, 0.08, 0.07, 0.07, ink))
		end
		head()
		add(flat(0.5, 0.66, 0.6, 0.07, accent), flat(0.5, 0.77, 0.46, 0.06, accent))
		eyes(0.48, 0.13, 0.08)
		add(flat(0.5, 0.58, 0.1, 0.04, ink))
		cheeks(0.58, 0.22)
	elseif style == "beetle" then
		for _, sx in ipairs({ -1, 1 }) do
			add(flat(0.5 + sx * 0.12, 0.15, 0.03, 0.18, ink, { rot = sx * 25 }))
		end
		head(0.5, 0.56, 0.7, 0.6, accent)
		add(S(0.5, 0.42, 0.7, 0.36, body, { r = 0.5 }))     -- shiny shell on top
		add(flat(0.5, 0.42, 0.02, 0.34, body:Lerp(black, 0.4)))
		add(flat(0.36, 0.38, 0.08, 0.07, ink, { a = 0.3 }), flat(0.64, 0.4, 0.07, 0.06, ink, { a = 0.3 }))
		add(flat(0.38, 0.32, 0.12, 0.05, white, { a = 0.4, rot = -20 }))
		eyes(0.66, 0.12, 0.07)
		cheeks(0.74, 0.2)
	elseif style == "penguin" then
		head(0.5, 0.52, 0.7, 0.66)
		add(S(0.5, 0.6, 0.5, 0.48, accent, { r = 0.5, line = 1.5 }))
		eyes(0.52, 0.11, 0.075)
		add(S(0.5, 0.66, 0.12, 0.12, rgb(255, 160, 40), { r = 0.15, rot = 45 }))
		cheeks(0.64, 0.2)
	elseif style == "dragon" then
		for _, sx in ipairs({ -1, 1 }) do
			add(S(0.5 + sx * 0.34, 0.42, 0.24, 0.16, accent, { r = 0.3, rot = sx * -35 })) -- little wings
			add(S(0.5 + sx * 0.18, 0.18, 0.08, 0.22, accent, { r = 0.5, rot = sx * 25 }))  -- horns
		end
		head()
		for i = -1, 1 do
			add(S(0.5 + i * 0.08, 0.25, 0.07, 0.07, accent, { r = 0.15, rot = 45 })) -- spikes
		end
		eyes(0.48, 0.13, 0.08)
		add(S(0.5, 0.67, 0.36, 0.22, light, { r = 0.5, line = 1.5 }))
		add(flat(0.44, 0.64, 0.04, 0.04, ink), flat(0.56, 0.64, 0.04, 0.04, ink))
		cheeks(0.6, 0.22)
	elseif style == "slime" then
		add(S(0.5, 0.6, 0.74, 0.6, body, { r = 0.5 }))
		add(S(0.5, 0.44, 0.5, 0.4, body, { r = 0.5, line = 0 }))
		add(flat(0.3, 0.86, 0.1, 0.1, body), flat(0.66, 0.88, 0.08, 0.08, body))
		add(flat(0.36, 0.38, 0.12, 0.08, white, { a = 0.4, rot = -25 }))
		eyes(0.56, 0.12, 0.08)
		add(flat(0.5, 0.68, 0.12, 0.05, accent))
		cheeks(0.66, 0.22)
	elseif style == "bird" then
		for i = -1, 1 do
			add(S(0.5 + i * 0.07, 0.17, 0.07, 0.2, accent, { r = 0.5, rot = i * 25 })) -- crest
		end
		head()
		eyes(0.48, 0.13, 0.08)
		add(S(0.5, 0.62, 0.14, 0.14, rgb(255, 170, 40), { r = 0.15, rot = 45 }))
		cheeks(0.6, 0.22)
	elseif style == "cloud" then
		for _, c in ipairs({ { 0.3, 0.5, 0.36 }, { 0.7, 0.5, 0.36 }, { 0.5, 0.38, 0.42 }, { 0.5, 0.6, 0.6 } }) do
			add(S(c[1], c[2], c[3], c[3] * 0.9, body, { r = 0.5 }))
		end
		add(flat(0.5, 0.55, 0.6, 0.3, body))
		eyes(0.54, 0.11, 0.07)
		add(flat(0.5, 0.64, 0.08, 0.04, ink))
		cheeks(0.62, 0.2)
	elseif style == "unicorn" then
		for i = 1, 3 do
			add(S(0.26 + i * 0.03, 0.3 + i * 0.12, 0.16, 0.2, accent, { r = 0.5, rot = -20 })) -- mane
		end
		add(S(0.68, 0.24, 0.1, 0.16, body, { r = 0.12, rot = 30 })) -- ear
		head()
		add(S(0.5, 0.16, 0.09, 0.26, rgb(255, 215, 80), { r = 0.4 })) -- horn
		add(flat(0.5, 0.12, 0.09, 0.02, rgb(220, 160, 30)), flat(0.5, 0.18, 0.09, 0.02, rgb(220, 160, 30)))
		eyes(0.5, 0.12, 0.08)
		muzzle(0.68, pink)
		cheeks(0.62, 0.22)
	elseif style == "robot" then
		add(flat(0.5, 0.16, 0.03, 0.14, ink), S(0.5, 0.09, 0.08, 0.08, accent, { r = 0.5 }))
		add(S(0.5, 0.54, 0.68, 0.56, body, { r = 0.18 }))
		add(S(0.5, 0.48, 0.5, 0.16, ink, { r = 0.3 }))
		add(flat(0.39, 0.48, 0.1, 0.07, accent), flat(0.61, 0.48, 0.1, 0.07, accent))
		for i = -1, 1 do
			add(flat(0.5 + i * 0.07, 0.68, 0.04, 0.06, ink, { r = 0.2 }))
		end
		add(S(0.14, 0.54, 0.06, 0.16, accent, { r = 0.3 }), S(0.86, 0.54, 0.06, 0.16, accent, { r = 0.3 }))
	elseif style == "bat" then
		pointyEar(0.24, 0.28, 0.3, -20, accent)
		pointyEar(0.76, 0.28, 0.3, 20, accent)
		head()
		eyes(0.5, 0.13, 0.08, accent)
		add(flat(0.5, 0.62, 0.08, 0.05, ink))
		add(S(0.45, 0.7, 0.04, 0.07, white, { r = 0.1, line = 1 }), S(0.55, 0.7, 0.04, 0.07, white, { r = 0.1, line = 1 }))
		cheeks(0.62, 0.22)
	elseif style == "wisp" then
		add(S(0.5, 0.36, 0.34, 0.34, accent, { r = 0.15, rot = 45, a = 0.3 }))
		add(S(0.5, 0.6, 0.62, 0.56, body, { r = 0.5 }))
		add(S(0.5, 0.4, 0.38, 0.38, body, { r = 0.15, rot = 45, line = 0 }))
		add(flat(0.5, 0.6, 0.36, 0.34, accent, { a = 0.5 }))
		eyes(0.6, 0.11, 0.1)
		cheeks(0.7, 0.18)
	elseif style == "overlord" then
		head(0.5, 0.56, 0.7, 0.6)
		add(S(0.5, 0.25, 0.42, 0.16, rgb(255, 210, 60), { r = 0.1 })) -- crown
		for i = -1, 1 do
			add(S(0.5 + i * 0.14, 0.17, 0.09, 0.09, rgb(255, 210, 60), { r = 0.1, rot = 45 }))
		end
		add(flat(0.5, 0.25, 0.07, 0.07, rgb(230, 50, 80)))
		eyes(0.52, 0.16, 0.075, accent)
		add(flat(0.5, 0.42, 0.08, 0.1, accent))
		add(flat(0.5, 0.68, 0.22, 0.05, ink))
	else -- pup
		add(S(0.22, 0.42, 0.22, 0.4, accent, { r = 0.5, rot = 20 }))
		add(S(0.78, 0.42, 0.22, 0.4, accent, { r = 0.5, rot = -20 }))
		head(0.5, 0.52, 0.66, 0.62)
		muzzle(0.66)
		eyes(0.46, 0.12, 0.08)
		add(flat(0.5, 0.75, 0.08, 0.08, pink))
		cheeks(0.6, 0.22)
	end
	return list
end

-- a shiny egg: a smooth egg shape (narrow top, round bottom) built from thin
-- rounded slices, shaded darker on the lower right, lit from the top left,
-- with a zigzag stripe, raised spots and a soft shadow under it
-- (colors from the egg; cream + green by default)
function ICONS.egg(color, spots, design)
	color = color or rgb(250, 240, 220)
	spots = spots or rgb(120, 210, 90)
	local black, white = rgb(0, 0, 0), rgb(255, 255, 255)
	-- the shell color for designs that change it
	local base = color
	if design == "lava" then base = rgb(55, 35, 32) end
	if design == "cosmic" then base = rgb(40, 20, 70) end
	if design == "robo" then base = rgb(40, 42, 70) end
	if design == "ice" then base = color:Lerp(rgb(60, 140, 220), 0.35) end
	local outline, dark, light = base:Lerp(black, 0.6), base:Lerp(black, 0.3), base:Lerp(white, 0.4)
	local spotDark = spots:Lerp(black, 0.35)
	local CY, B, A = 0.52, 0.42, 0.3 -- center, half height, half width
	-- half the egg's width at v (-1 = the top tip, 1 = the bottom)
	local function halfWidth(v)
		return A * math.sqrt(math.max(0, 1 - v * v)) * (1 + 0.16 * v)
	end
	local list = {
		S(0.5, 0.95, 0.5, 0.06, black, { r = 0.5, line = 0, flat = true, a = 0.75 }), -- shadow on the ground
	}
	local function add(sh) table.insert(list, sh) end
	local SLICES = 22
	-- the egg shape scaled by k around its center, moved by dx/dy, grown by `grow`
	local function body(c, grow, dx, dy, k, opts)
		for i = 0, SLICES - 1 do
			local v = -1 + (i + 0.5) * 2 / SLICES
			local o = { r = 0.5, line = 0, flat = true }
			for key, val in pairs(opts or {}) do
				o[key] = val
			end
			local w = 2 * halfWidth(v) * k + grow
			-- tall slices with round ends overlap, so the edge comes out smooth
			local h = math.min(2 * B / SLICES * 3 * k, w * 0.9) + grow
			add(S(0.5 + dx, CY + v * B * k + dy, w, h, c, o))
		end
	end
	body(outline, 0.045, 0, 0, 1)                           -- dark outline
	body(dark, 0, 0, 0, 1)                                  -- shadow side (shows on the lower right)
	body(base, 0, -0.022, -0.02, 0.9)                       -- the main color
	add(S(0.44, 0.38, 0.26, 0.4, light, { r = 0.5, line = 0, flat = true, a = 0.55, rot = 12 })) -- soft light, upper left

	-- drawing helpers that stay inside the egg
	local function inside(x, y, pad)
		local v = (y - CY) / B
		return math.abs(v) < 0.96 and math.abs(x - 0.5) <= halfWidth(v) * (pad or 0.92)
	end
	local function flat(x, y, w, h, c, extra)
		local o = { r = 0.5, line = 0, flat = true }
		for k, val in pairs(extra or {}) do o[k] = val end
		return S(x, y, w, h, c, o)
	end
	-- a band across the egg at height y (as wide as the egg is there)
	local function hband(y, h, c, extra)
		local w = 2 * math.min(halfWidth((y - h / 2 - CY) / B), halfWidth((y + h / 2 - CY) / B)) * 0.86
		if w > 0.02 then add(flat(0.5, y, w, h, c, extra)) end
	end
	-- a line from (x1, y1) to (x2, y2), cut into short pieces that stay inside the egg
	local function seg(x1, y1, x2, y2, w, c, extra)
		local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		local n = math.max(1, math.ceil(len / 0.05))
		local rot = math.deg(math.atan2(y2 - y1, x2 - x1))
		for i = 0, n - 1 do
			local ax, ay = x1 + (x2 - x1) * i / n, y1 + (y2 - y1) * i / n
			local bx, by = x1 + (x2 - x1) * (i + 1) / n, y1 + (y2 - y1) * (i + 1) / n
			if inside(ax, ay, 0.8) and inside(bx, by, 0.8) then
				local o = { rot = rot, r = 0.5 }
				for k, val in pairs(extra or {}) do o[k] = val end
				add(flat((ax + bx) / 2, (ay + by) / 2, len / n + w * 0.8, w, c, o))
			end
		end
	end
	local function path(pts, w, c, extra)
		for i = 1, #pts - 1 do
			seg(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], w, c, extra)
		end
	end
	local function dot(x, y, d, c, extra)
		if inside(x, y) then add(flat(x, y, d, d, c, extra)) end
	end
	local function flower(x, y, size, petal, middle)
		if not inside(x, y, 0.8) then return end
		for k = 0, 2 do
			add(flat(x, y, size * 0.32, size, petal, { rot = k * 60 }))
		end
		add(flat(x, y, size * 0.36, size * 0.36, middle))
	end

	if design == "grass" then
		local leaf = rgb(60, 160, 60)
		for i = 0, 12 do
			local x = 0.24 + i * 0.044
			if inside(x, 0.84, 1) then
				add(flat(x, 0.83, 0.035, 0.13, (i % 2 == 0) and leaf or leaf:Lerp(white, 0.25), { rot = (i % 3 - 1) * 12 }))
			end
		end
		for i, f in ipairs({ { 0.4, 0.3 }, { 0.6, 0.38 }, { 0.43, 0.52 }, { 0.64, 0.6 }, { 0.36, 0.68 }, { 0.53, 0.22 }, { 0.55, 0.7 } }) do
			flower(f[1], f[2], 0.11, (i % 3 == 0) and rgb(255, 200, 230) or white, rgb(255, 205, 50))
		end
	elseif design == "sand" then
		local tones = { rgb(205, 150, 85), rgb(225, 180, 110), rgb(185, 125, 70) }
		for i, y in ipairs({ 0.2, 0.26, 0.74, 0.8, 0.87 }) do
			hband(y, 0.022 + (i % 2) * 0.012, tones[i % 3 + 1])
		end
		hband(0.52, 0.1, rgb(40, 165, 155))
		hband(0.47, 0.012, rgb(255, 215, 60))
		hband(0.57, 0.012, rgb(255, 215, 60))
		for i = 0, 4 do
			dot(0.33 + i * 0.085, 0.52, 0.04, rgb(255, 215, 60), { rot = 45, r = 0.1 })
		end
	elseif design == "ice" then
		hband(0.82, 0.04, white)
		for _, f in ipairs({ { 0.41, 0.32, 0.15 }, { 0.62, 0.48, 0.13 }, { 0.38, 0.62, 0.14 }, { 0.58, 0.76, 0.12 } }) do
			if inside(f[1], f[2], 0.8) then
				for k = 0, 2 do
					add(flat(f[1], f[2], 0.016, f[3], white, { rot = k * 60, r = 0.3 }))
				end
				add(flat(f[1], f[2], 0.03, 0.03, rgb(170, 230, 255)))
			end
		end
		-- frosty glass sheen
		add(flat(0.4, 0.48, 0.12, 0.5, white, { a = 0.75, rot = 8 }))
	elseif design == "lava" then
		hband(0.83, 0.05, color)
		hband(0.79, 0.02, color:Lerp(rgb(255, 230, 80), 0.5), { a = 0.3 })
		local hot, warm = spots, color
		path({ { 0.42, 0.17 }, { 0.47, 0.3 }, { 0.41, 0.43 }, { 0.48, 0.58 }, { 0.43, 0.73 }, { 0.49, 0.88 } }, 0.022, hot)
		path({ { 0.61, 0.22 }, { 0.67, 0.38 }, { 0.6, 0.52 }, { 0.68, 0.68 }, { 0.62, 0.86 } }, 0.022, warm)
		path({ { 0.41, 0.43 }, { 0.32, 0.52 }, { 0.3, 0.62 } }, 0.016, warm)
		path({ { 0.6, 0.52 }, { 0.53, 0.46 } }, 0.016, hot)
	elseif design == "jungle" then
		local stripe = color:Lerp(black, 0.35)
		for i = -3, 3 do
			local x = 0.5 + i * 0.08
			local top, bottom
			for yy = 0.1, 0.94, 0.01 do
				if inside(x, yy, 0.97) then
					top = top or yy
					bottom = yy
				end
			end
			if top then add(flat(x, (top + bottom) / 2, 0.035, bottom - top, stripe)) end
		end
		hband(0.52, 0.08, rgb(255, 205, 60))
		hband(0.475, 0.012, rgb(120, 70, 30))
		hband(0.565, 0.012, rgb(120, 70, 30))
		for i = 0, 5 do
			dot(0.29 + i * 0.084, 0.52, 0.035, (i % 2 == 0) and rgb(230, 90, 40) or rgb(40, 140, 70), { rot = 45, r = 0.1 })
		end
	elseif design == "candy" then
		local swirl = { white, rgb(130, 220, 255), rgb(255, 90, 150) }
		for i = 0, 2 do
			local y0 = 0.22 + i * 0.22
			seg(0.12, y0, 0.88, y0 + 0.3, 0.05, swirl[i + 1], { r = 0.2 })
		end
		local bits = { white, rgb(255, 230, 80), rgb(120, 230, 120), rgb(130, 220, 255) }
		for i, b in ipairs({ { 0.4, 0.25 }, { 0.6, 0.3 }, { 0.36, 0.45 }, { 0.65, 0.5 }, { 0.48, 0.62 }, { 0.34, 0.78 }, { 0.6, 0.82 }, { 0.55, 0.16 } }) do
			if inside(b[1], b[2]) then
				add(flat(b[1], b[2], 0.014, 0.045, bits[i % #bits + 1], { rot = i * 47 }))
			end
		end
	elseif design == "robo" then
		local glow = spots
		hband(0.82, 0.04, rgb(150, 155, 170))
		hband(0.52, 0.016, glow)
		for _, x in ipairs({ 0.36, 0.5, 0.64 }) do
			seg(x, 0.14, x, 0.9, 0.012, glow)
		end
		for _, x in ipairs({ 0.36, 0.5, 0.64 }) do
			dot(x, 0.52, 0.05, rgb(20, 20, 35))
			dot(x, 0.52, 0.028, glow)
		end
		path({ { 0.42, 0.36 }, { 0.42, 0.3 }, { 0.46, 0.27 } }, 0.012, glow)
		dot(0.47, 0.265, 0.026, glow)
		path({ { 0.58, 0.68 }, { 0.58, 0.74 }, { 0.55, 0.77 } }, 0.012, glow)
		dot(0.545, 0.775, 0.026, glow)
	elseif design == "cosmic" then
		seg(0.14, 0.66, 0.86, 0.4, 0.12, rgb(120, 50, 200), { a = 0.35 })
		seg(0.14, 0.66, 0.86, 0.4, 0.04, spots, { a = 0.2 })
		for i, st in ipairs({ { 0.38, 0.26 }, { 0.6, 0.22 }, { 0.32, 0.5 }, { 0.68, 0.58 }, { 0.47, 0.72 }, { 0.6, 0.8 }, { 0.4, 0.84 }, { 0.53, 0.38 }, { 0.7, 0.36 }, { 0.3, 0.68 } }) do
			dot(st[1], st[2], (i % 3 == 0) and 0.022 or 0.014, white)
		end
		for _, st in ipairs({ { 0.62, 0.3 }, { 0.42, 0.62 } }) do
			add(flat(st[1], st[2], 0.012, 0.075, white))
			add(flat(st[1], st[2], 0.075, 0.012, white))
		end
	else
		-- classic: zigzag stripe + raised spots
		local sv = (0.56 - CY) / B
		local sw = 2 * halfWidth(sv) * 0.88
		add(S(0.5, 0.582, sw * 0.96, 0.022, spotDark, { line = 0, flat = true }))
		add(S(0.5, 0.56, sw, 0.04, spots, { line = 0, flat = true }))
		for i = 0, 5 do
			local x = 0.5 - sw * 0.4 + i * (sw * 0.8 / 5)
			add(S(x, 0.56, 0.06, 0.06, spots, { rot = 45, line = 0, flat = true }))
		end
		for _, sp in ipairs({ { 0.42, 0.33, 0.09 }, { 0.6, 0.4, 0.065 }, { 0.37, 0.73, 0.1 }, { 0.61, 0.76, 0.08 }, { 0.5, 0.86, 0.05 } }) do
			local x, y, d = sp[1], sp[2], sp[3]
			add(S(x + 0.007, y + 0.009, d, d * 0.85, spotDark, { r = 0.5, line = 0, flat = true }))
			add(S(x, y, d, d * 0.85, spots, { r = 0.5, line = 0 }))
			add(S(x - d * 0.18, y - d * 0.18, d * 0.3, d * 0.22, white, { r = 0.5, line = 0, flat = true, a = 0.45 }))
		end
	end
	-- glossy highlight
	add(S(0.38, 0.27, 0.07, 0.17, white, { r = 0.5, line = 0, flat = true, a = 0.35, rot = 24 }))
	add(S(0.42, 0.18, 0.03, 0.03, white, { r = 0.5, line = 0, flat = true, a = 0.2 }))
	return list
end

-- two white arrows chasing each other around an orange coin (rebirth)
function ICONS.rebirth()
	local o, white, dark = rgb(255, 150, 40), rgb(255, 250, 240), rgb(110, 50, 10)
	return {
		S(0.5, 0.5, 0.86, 0.86, o, { r = 0.5 }),
		S(0.5, 0.5, 0.62, 0.62, dark, { r = 0.5, ring = true, line = 14 }),
		S(0.5, 0.5, 0.62, 0.62, white, { r = 0.5, ring = true, line = 8 }),
		-- gaps in the ring, then the arrow heads
		S(0.24, 0.36, 0.16, 0.12, o, { r = 0.2, rot = 35, line = 0, flat = true }),
		S(0.76, 0.64, 0.16, 0.12, o, { r = 0.2, rot = 35, line = 0, flat = true }),
		S(0.27, 0.27, 0.17, 0.17, white, { rot = 10, r = 0.1 }),
		S(0.73, 0.73, 0.17, 0.17, white, { rot = 10, r = 0.1 }),
		S(0.5, 0.5, 0.3, 0.3, o, { r = 0.5, line = 0, flat = true, text = "R", tc = white }),
	}
end

-- a big gold star burst (prestige)
function ICONS.star()
	local gold, deep = rgb(255, 205, 50), rgb(250, 160, 30)
	return {
		S(0.5, 0.5, 0.74, 0.74, deep, { r = 0.12, rot = 22.5 }),
		S(0.5, 0.5, 0.74, 0.74, deep, { r = 0.12, rot = 67.5 }),
		S(0.5, 0.5, 0.7, 0.7, gold, { r = 0.1 }),
		S(0.5, 0.5, 0.7, 0.7, gold, { r = 0.1, rot = 45 }),
		S(0.5, 0.5, 0.42, 0.42, rgb(255, 240, 160), { r = 0.5 }),
		S(0.42, 0.42, 0.1, 0.1, rgb(255, 255, 255), { r = 0.5, line = 0, flat = true }),
		S(0.5, 0.52, 0.26, 0.26, rgb(255, 240, 160), { r = 0.5, line = 0, flat = true, text = "P", tc = rgb(200, 110, 20) }),
	}
end

-- a lock (things you can't use yet)
function ICONS.lock()
	local steel, dark = rgb(200, 205, 220), rgb(90, 95, 110)
	return {
		S(0.5, 0.36, 0.44, 0.44, steel, { r = 0.5, ring = true, line = 10 }),
		S(0.5, 0.64, 0.66, 0.46, rgb(255, 200, 50), { r = 0.16 }),
		S(0.5, 0.6, 0.12, 0.12, dark, { r = 0.5, line = 0, flat = true }),
		S(0.5, 0.7, 0.06, 0.14, dark, { r = 0.5, line = 0, flat = true }),
	}
end
-- ICONS END

-- draws icon `name` into a new square frame `px` pixels across
local function drawIcon(parent, name, px, ...)
	local holder = Instance.new("Frame")
	holder.Name = "Icon_" .. name
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(px, px)
	for _, sh in ipairs(ICONS[name](...)) do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(sh.x, sh.y)
		f.Size = UDim2.fromScale(sh.w, sh.h)
		f.Rotation = sh.rot or 0
		f.BorderSizePixel = 0
		f.BackgroundColor3 = sh.c
		f.BackgroundTransparency = if sh.ring then 1 else (sh.a or 0)
		if (sh.r or 0) > 0 then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(sh.r, 0)
			c.Parent = f
		end
		local line = sh.line or 2.5
		if line > 0 then
			local st = Instance.new("UIStroke")
			st.Color = if sh.ring then sh.c else sh.c:Lerp(Color3.new(0, 0, 0), 0.55)
			st.Thickness = math.max(1, line * px / 100)
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.Parent = f
		end
		if not sh.flat and not sh.ring then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(sh.c:Lerp(Color3.new(1, 1, 1), 0.25), sh.c:Lerp(Color3.new(0, 0, 0), 0.12))
			g.Rotation = 90
			g.Parent = f
		end
		if sh.text then
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.Text = sh.text
			t.TextColor3 = sh.tc or Color3.new(1, 1, 1)
			t.Parent = f
		end
		f.Parent = holder
	end
	holder.Parent = parent
	return holder
end

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
	if i == 1 then
		return tostring(n)
	end
	return string.format("%.1f%s", v, suffixes[i])
end

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = props and props.Parent
	return inst
end

local function corner(parent, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 10), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 3, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

-- big white cartoon text with a dark outline
local function label(parent, text, size, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		Text = text,
		TextColor3 = WHITE,
		TextScaled = true,
		Size = size,
		Parent = parent,
	})
	new("UIStroke", { Color = Color3.fromRGB(25, 25, 30), Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round, Parent = l })
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function tween(obj, t, goal, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

-- a chunky Roblox-brick tile: rounded, outlined, shaded, with studs on it
local function studTile(parent, color, size, props)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.5)
	local tile = new("Frame", {
		BackgroundColor3 = color,
		Size = size,
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(tile, 10)
	stroke(tile, dark, 3.5)
	new("UIGradient", {
		Color = ColorSequence.new(color:Lerp(WHITE, 0.1), color:Lerp(Color3.new(0, 0, 0), 0.1)),
		Rotation = 90,
		Parent = tile,
	})
	-- the studs: a grid of square cells, each with a round raised bump
	-- (lit from the top left), like the top of a Roblox brick
	local studs = new("Frame", {
		Name = "Studs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = tile,
	})
	corner(studs, 10)
	local CELL = 18
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL, CELL),
		CellPadding = UDim2.fromOffset(0, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = studs,
	})
	local w, h = size.X.Offset, size.Y.Offset
	local count = (math.floor(w / CELL) + 1) * (math.floor(h / CELL) + 1)
	for _ = 1, count do
		local cell = new("Frame", { BackgroundTransparency = 1, Parent = studs })
		new("UIStroke", { Color = dark, Thickness = 1, Transparency = 0.82, Parent = cell })
		local bump = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = cell,
		})
		corner(bump, 99)
		new("UIGradient", { Color = ColorSequence.new(color:Lerp(WHITE, 0.28), color:Lerp(Color3.new(0, 0, 0), 0.18)), Rotation = 45, Parent = bump })
		new("UIStroke", { Color = dark, Thickness = 1, Transparency = 0.6, Parent = bump })
	end
	local scale = new("UIScale", { Parent = tile })
	for k, v in pairs(props or {}) do
		tile[k] = v
	end
	return tile, scale
end

local function bounce(scale, amount)
	scale.Scale = amount or 1.15
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- buttons squash when you press them
local function pressable(button, scale, onClick)
	button.MouseButton1Down:Connect(function()
		tween(scale, 0.08, { Scale = 0.9 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		tween(scale, 0.2, { Scale = 1 })
	end)
	button.Activated:Connect(onClick)
end

------------------------------------------------------------------------
-- The screen
------------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "SVB_HUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
-- one size on every screen (designed for a 720 px tall screen, then shrunk a bit
-- so it doesn't cover the game)
local UI_SIZE = 0.8
local screenScale = new("UIScale", { Parent = gui })
local function rescale()
	local cam = workspace.CurrentCamera
	local h = cam and cam.ViewportSize.Y or 720
	screenScale.Scale = math.clamp(h / 720, 0.6, 1.25) * UI_SIZE
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

local column = new("Frame", {
	Name = "LeftColumn",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 80),
	Size = UDim2.fromOffset(240, 760),
	Parent = gui,
})

------------------------------------------------------------------------
-- Stat tiles: Speed (sneaker), Cash (cash brick), Trophies (trophy)
------------------------------------------------------------------------
local stats = {}
local function statTile(key, icon, y, color)
	local tile, scale = studTile(column, color, UDim2.fromOffset(190, 68), { Position = UDim2.fromOffset(0, y), Name = key .. "Tile" })
	-- (the icon is bigger than the tile and pokes out of its left edge)
	drawIcon(tile, icon, 78).Position = UDim2.fromOffset(-12, -6)
	local value = label(tile, "0", UDim2.new(1, -76, 0, 46), {
		Position = UDim2.fromOffset(68, 11),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	stats[key] = { Tile = tile, Scale = scale, Value = value, Shown = 0, Target = 0, Prefix = "" }
	return stats[key]
end
statTile("Speed", "shoe", 0, COLORS.speed)
statTile("Cash", "cash", 78, COLORS.cash)
statTile("Trophies", "trophy", 156, COLORS.trophies)

local function readStat(key)
	local s = stats[key]
	local v = player:GetAttribute(key) or 0
	if v > s.Target and s.Target > 0 then
		bounce(s.Scale, 1.12)
	end
	s.Target = v
end
for key in pairs(stats) do
	local s = stats[key]
	s.Target = player:GetAttribute(key) or 0
	s.Shown = s.Target
	s.Value.Text = fmt(s.Shown)
	player:GetAttributeChangedSignal(key):Connect(function()
		readStat(key)
	end)
end

-- numbers count up smoothly
RunService.RenderStepped:Connect(function(dt)
	for _, s in pairs(stats) do
		if s.Shown ~= s.Target then
			local diff = s.Target - s.Shown
			if math.abs(diff) < 1 then
				s.Shown = s.Target
			else
				s.Shown += diff * math.min(1, dt * 10)
			end
			s.Value.Text = fmt(s.Shown)
		end
	end
end)

------------------------------------------------------------------------
-- Buttons: Teleport, 3x Cash, Invite, Pets
------------------------------------------------------------------------
local BTN = 104
local GAP = 16
local function squareButton(name, icon, text, color, x, y)
	local tile, scale = studTile(column, color, UDim2.fromOffset(BTN, BTN), { Position = UDim2.fromOffset(x, y), Name = name })
	local button = new("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = tile,
	})
	-- a big icon that pokes out over the top, the name across the bottom edge
	local iconLabel = drawIcon(tile, icon, 86)
	iconLabel.AnchorPoint = Vector2.new(0.5, 0)
	iconLabel.Position = UDim2.new(0.5, 0, 0, -16)
	local textLabel = label(tile, text, UDim2.new(1, 8, 0, 30), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -12), ZIndex = 4 })
	return tile, scale, button, iconLabel, textLabel
end

local rowY = 156 + 68 + 44
local _tpTile, tpScale, tpButton = squareButton("Teleport", "portal", "Teleport", COLORS.teleport, 0, rowY)
local passTile, passScale, passButton, passIcon, passText = squareButton("CashPass", "bat", "3x", COLORS.pass, BTN + GAP, rowY)
local _invTile, invScale, invButton = squareButton("Invite", "friends", "Invite", COLORS.invite, 0, rowY + BTN + GAP + 26)
local _petTile, petScale, petButton = squareButton("Pets", "pet", "Pets", COLORS.pets, BTN + GAP, rowY + BTN + GAP + 26)
local row3 = rowY + 2 * (BTN + GAP + 26)
local _rbTile, rbScale, rbButton = squareButton("Rebirth", "rebirth", "Rebirth", COLORS.rebirth, 0, row3)
local prTile, prScale, prButton, prIcon = squareButton("Prestige", "star", "Prestige", COLORS.prestige, BTN + GAP, row3)
-- "3x" and a little cash brick under the bat
passText.Size = UDim2.new(0.42, 0, 0, 32)
passText.Position = UDim2.new(0.36, 0, 1, -14)
local passCash = drawIcon(passTile, "cash", 40)
passCash.AnchorPoint = Vector2.new(0.5, 0.5)
passCash.Position = UDim2.new(0.7, 0, 1, -16)

-- "Play with friends!" under the invite button
label(column, "Play with friends!", UDim2.fromOffset(BTN + 24, 22), { Position = UDim2.fromOffset(-12, rowY + 2 * BTN + GAP + 32) })

-- the gamepass button: a thick spinning rainbow frame, the price above it
passText.TextColor3 = Color3.fromRGB(120, 255, 90)
passText:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(15, 70, 25)
local rainbowFrame = new("Frame", {
	Name = "RainbowFrame",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(BTN + GAP + BTN / 2, rowY + BTN / 2),
	Size = UDim2.fromOffset(BTN + 14, BTN + 14),
	BackgroundColor3 = WHITE,
	ZIndex = 0,
	Parent = column,
})
corner(rainbowFrame, 14)
stroke(rainbowFrame, Color3.fromRGB(25, 25, 30), 2.5)
local rainbow = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 230, 90)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 90, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 70)),
	}),
	Parent = rainbowFrame,
})
local priceLabel = label(column, "ONLY " .. ROBUX .. "?!", UDim2.fromOffset(BTN + 16, 26), {
	Position = UDim2.fromOffset(BTN + GAP - 8, rowY - 36),
})
RunService.RenderStepped:Connect(function()
	rainbow.Rotation = (os.clock() * 90) % 360
	passIcon.Rotation = math.sin(os.clock() * 3) * 8
end)

local passId = workspace:GetAttribute("CashGamepassId") or 0
task.spawn(function()
	if passId <= 0 then
		priceLabel.Text = "3x CASH!"
		return
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
	end)
	if ok and info and info.PriceInRobux then
		priceLabel.Text = "ONLY " .. ROBUX .. info.PriceInRobux .. "!"
	else
		priceLabel.Text = "3x CASH!"
	end
end)
local function refreshPass()
	if player:GetAttribute("HasCashPass") then
		priceLabel.Text = "OWNED!"
	end
end
refreshPass()
player:GetAttributeChangedSignal("HasCashPass"):Connect(refreshPass)

------------------------------------------------------------------------
-- Popup panels (teleport menu, pets)
------------------------------------------------------------------------
local openPanel
local function closePanel()
	if openPanel then
		local p = openPanel
		openPanel = nil
		tween(p:FindFirstChildOfClass("UIScale"), 0.15, { Scale = 0.6 })
		task.delay(0.15, function()
			p.Visible = false
		end)
	end
end
local function showPanel(p)
	if openPanel == p then
		closePanel()
		return
	end
	closePanel()
	openPanel = p
	p.Visible = true
	local s = p:FindFirstChildOfClass("UIScale")
	s.Scale = 0.6
	tween(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function panel(name, size, title, color, iconName)
	local p = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Color3.fromRGB(40, 44, 60),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	corner(p, 16)
	stroke(p, color, 4)
	new("UIScale", { Parent = p })
	local head = new("Frame", { BackgroundColor3 = color, Size = UDim2.new(1, 0, 0, 50), ZIndex = 21, Parent = p })
	corner(head, 16)
	local icon = drawIcon(head, iconName, 44)
	icon.Position = UDim2.fromOffset(10, 3)
	label(head, title, UDim2.new(1, -120, 0, 40), { Position = UDim2.fromOffset(60, 5), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	local close = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(40, 38),
		BackgroundColor3 = Color3.fromRGB(235, 70, 80),
		Text = "X",
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		ZIndex = 23,
		Parent = p,
	})
	corner(close, 10)
	close.Activated:Connect(closePanel)
	return p
end

-- teleport menu: places on this map, then every map (locked ones show a lock)
local tpPanel = panel("TeleportMenu", UDim2.fromOffset(320, 72 + 5 * 58), "Teleport", COLORS.teleport, "portal")
local function tpButtonRow(i, iconName, caption)
	local b = new("TextButton", {
		Position = UDim2.fromOffset(20, 62 + (i - 1) * 58),
		Size = UDim2.new(1, -40, 0, 50),
		BackgroundColor3 = COLORS.teleport:Lerp(WHITE, 0.1),
		Text = "",
		ZIndex = 22,
		Parent = tpPanel,
	})
	corner(b, 12)
	stroke(b, COLORS.teleport:Lerp(Color3.new(0, 0, 0), 0.4), 3)
	local icon = drawIcon(b, iconName, 40)
	icon.Position = UDim2.fromOffset(8, 5)
	local text = label(b, caption, UDim2.new(1, -70, 1, -14), { Position = UDim2.fromOffset(58, 7), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23 })
	return b, text
end
for i, place in ipairs({ { "spawn", "Spawn", "portal" }, { "pad", "Speed Pad", "shoe" }, { "eggs", "Pet Eggs", "egg" } }) do
	local b = tpButtonRow(i, place[3], place[2])
	b.Activated:Connect(function()
		TeleportRemote:FireServer(place[1])
		closePanel()
	end)
end
local mapButtons = {}
local mapList = MapInfo:GetChildren()
table.sort(mapList, function(a, b) return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0) end)
for _, info in ipairs(mapList) do
	local m = info:GetAttribute("Index") or 1
	local b, text = tpButtonRow(3 + m, "portal", "Map " .. m .. ": " .. (info:GetAttribute("Title") or ""))
	local accent = info:GetAttribute("Color") or COLORS.teleport
	b.BackgroundColor3 = accent:Lerp(Color3.new(0, 0, 0), 0.25)
	local lock = drawIcon(b, "lock", 34)
	lock.AnchorPoint = Vector2.new(1, 0.5)
	lock.Position = UDim2.new(1, -8, 0.5, 0)
	mapButtons[m] = { button = b, text = text, lock = lock }
	b.Activated:Connect(function()
		if (player:GetAttribute("MaxMap") or 1) >= m then
			TeleportRemote:FireServer("map" .. m)
			closePanel()
		else
			bounce(b:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = b }), 0.9)
		end
	end)
end
tpPanel.Size = UDim2.fromOffset(320, 72 + (3 + #mapList) * 58)
local function refreshMaps()
	local maxMap = player:GetAttribute("MaxMap") or 1
	local here = player:GetAttribute("CurrentMap") or 1
	for m, mb in pairs(mapButtons) do
		local open = maxMap >= m
		mb.lock.Visible = not open
		mb.text.TextTransparency = open and 0 or 0.45
		mb.button.AutoButtonColor = open
		mb.text.Text = (if here == m then "> " else "") .. "Map " .. m .. ": " .. (mapList[m] and mapList[m]:GetAttribute("Title") or "")
	end
end
refreshMaps()
player:GetAttributeChangedSignal("MaxMap"):Connect(refreshMaps)
player:GetAttributeChangedSignal("CurrentMap"):Connect(refreshMaps)

-- a big round action button at the bottom of a panel
local function panelAction(p, text, color, onClick)
	local b = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, -60, 0, 50),
		BackgroundColor3 = color,
		Text = "",
		ZIndex = 22,
		Parent = p,
	})
	corner(b, 14)
	stroke(b, color:Lerp(Color3.new(0, 0, 0), 0.45), 3)
	local t = label(b, text, UDim2.new(1, -20, 1, -12), { Position = UDim2.fromOffset(10, 6), ZIndex = 23 })
	b.Activated:Connect(onClick)
	return b, t
end
local function panelLine(p, y, color)
	return label(p, "", UDim2.new(1, -40, 0, 24), { Position = UDim2.fromOffset(20, y), TextColor3 = color or WHITE, ZIndex = 22 })
end

-- rebirth: reset cash + speed for a bigger cash multiplier
local rebirthPanel = panel("RebirthMenu", UDim2.fromOffset(360, 270), "Rebirth", COLORS.rebirth, "rebirth")
local rbNeed = panelLine(rebirthPanel, 66)
local rbMult = panelLine(rebirthPanel, 98, Color3.fromRGB(150, 255, 150))
local rbNote = panelLine(rebirthPanel, 132, Color3.fromRGB(200, 205, 225))
rbNote.Text = "Resets cash + speed. Keeps pets, trophies and wins."
rbNote.Size = UDim2.new(1, -40, 0, 36)
local rbAction, rbActionText = panelAction(rebirthPanel, "REBIRTH", Color3.fromRGB(70, 200, 90), function()
	RebirthRemote:FireServer()
	closePanel()
end)
local function refreshRebirth()
	local speed = player:GetAttribute("Speed") or 0
	local need = player:GetAttribute("RebirthSpeed") or 0
	local can = speed >= need
	rbNeed.Text = "Speed: " .. fmt(speed) .. " / " .. fmt(need)
	rbNeed.TextColor3 = can and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 140, 140)
	rbMult.Text = string.format("Cash x%.1f  >  x%.1f", player:GetAttribute("Multiplier") or 1, player:GetAttribute("NextMultiplier") or 1)
	rbAction.BackgroundColor3 = can and Color3.fromRGB(70, 200, 90) or Color3.fromRGB(95, 100, 115)
	rbActionText.Text = can and "REBIRTH!" or "Need more speed"
end
for _, a in ipairs({ "Speed", "RebirthSpeed", "Multiplier", "NextMultiplier" }) do
	player:GetAttributeChangedSignal(a):Connect(refreshRebirth)
end
refreshRebirth()

-- prestige: unlocked at the final zone; start over with a trophy multiplier
local prestigePanel = panel("PrestigeMenu", UDim2.fromOffset(380, 290), "Prestige", COLORS.prestige, "star")
local prState = panelLine(prestigePanel, 66)
local prMult = panelLine(prestigePanel, 100, Color3.fromRGB(255, 220, 90))
local prNote = panelLine(prestigePanel, 134, Color3.fromRGB(200, 205, 225))
prNote.Text = "Resets cash, speed, trophies and maps. Keeps your pets and rebirths."
prNote.Size = UDim2.new(1, -40, 0, 40)
local prAction, prActionText = panelAction(prestigePanel, "PRESTIGE", Color3.fromRGB(150, 90, 235), function()
	if player:GetAttribute("PrestigeReady") then
		PrestigeRemote:FireServer()
		closePanel()
	end
end)
-- the prestige button is dim with a lock until you can use it, then it glows
local prLock = drawIcon(prTile, "lock", 40)
prLock.AnchorPoint = Vector2.new(0.5, 0.5)
prLock.Position = UDim2.fromScale(0.78, 0.3)
prLock.ZIndex = 6
local prDim = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = prTile })
corner(prDim, 10)
local function refreshPrestige()
	local ready = player:GetAttribute("PrestigeReady") == true
	local p = player:GetAttribute("Prestige") or 0
	prState.Text = ready and "You reached the final zone!" or "Reach the final zone to prestige"
	prState.TextColor3 = ready and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 160, 160)
	prMult.Text = "Prestige " .. p .. "  -  Trophies x" .. (1 + p) .. "  >  x" .. (2 + p)
	prAction.BackgroundColor3 = ready and Color3.fromRGB(150, 90, 235) or Color3.fromRGB(95, 100, 115)
	prActionText.Text = ready and "PRESTIGE!" or "Locked"
	prLock.Visible = not ready
	prDim.Visible = not ready
end
for _, a in ipairs({ "PrestigeReady", "Prestige" }) do
	player:GetAttributeChangedSignal(a):Connect(refreshPrestige)
end
refreshPrestige()
RunService.RenderStepped:Connect(function()
	if player:GetAttribute("PrestigeReady") then
		prIcon.Rotation = math.sin(os.clock() * 4) * 10
	end
end)

-- pets: what you own, what it gives, fuse 3 into a better one
local TIER_NAMES = { "", "Golden ", "Rainbow " }
local TIER_COLORS = { WHITE, Color3.fromRGB(255, 215, 60), Color3.fromRGB(255, 120, 230) }
local TIER_MULT = { 1, 3, 9 }
local petPanel = panel("PetsMenu", UDim2.fromOffset(470, 380), "Your Pets", COLORS.pets, "pet")
local bonusLabel = label(petPanel, "", UDim2.new(1, -32, 0, 22), { Position = UDim2.fromOffset(16, 56), TextColor3 = Color3.fromRGB(150, 255, 150), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
local petList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(12, 84),
	Size = UDim2.new(1, -24, 1, -96),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ZIndex = 22,
	Parent = petPanel,
})
new("UIGridLayout", { CellSize = UDim2.fromOffset(140, 150), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = petList })

local function refreshPets()
	for _, c in ipairs(petList:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local ok, pets = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("PetsJson") or "{}")
	end)
	pets = ok and pets or {}
	local equipped = {}
	for key in string.gmatch(player:GetAttribute("EquippedPets") or "", "[^,]+") do
		equipped[key] = (equipped[key] or 0) + 1
	end
	bonusLabel.Text = "Equipped pets give +" .. fmt(player:GetAttribute("PetBonus") or 0) .. "% cash"
	local list = {}
	for key, count in pairs(pets) do
		local name, tier = string.match(key, "^(.+)|(%d)$")
		tier = tonumber(tier)
		local info = name and PetInfo:FindFirstChild(name)
		if info and tier then
			table.insert(list, { key = key, name = name, tier = tier, count = count, info = info, bonus = (info:GetAttribute("Bonus") or 0) * (TIER_MULT[tier] or 1) })
		end
	end
	table.sort(list, function(a, b)
		return a.bonus > b.bonus
	end)
	if #list == 0 then
		label(petList, "No pets yet! Hatch eggs with trophies.", UDim2.fromOffset(400, 30), { ZIndex = 23 })
		return
	end
	for i, p in ipairs(list) do
		local card = new("Frame", { LayoutOrder = i, BackgroundColor3 = Color3.fromRGB(58, 64, 86), ZIndex = 23, Parent = petList })
		corner(card, 12)
		stroke(card, if equipped[p.key] then Color3.fromRGB(120, 255, 120) else TIER_COLORS[p.tier], 3)
		local face = drawIcon(card, "pet", 54, p.info:GetAttribute("Body"), p.info:GetAttribute("Accent"), p.info:GetAttribute("Style"))
		face.AnchorPoint = Vector2.new(0.5, 0)
		face.Position = UDim2.new(0.5, 0, 0, 3)
		label(card, TIER_NAMES[p.tier] .. p.name, UDim2.new(1, -8, 0, 18), { Position = UDim2.fromOffset(4, 58), TextColor3 = TIER_COLORS[p.tier], ZIndex = 24 })
		label(card, "+" .. fmt(p.bonus) .. "% cash  •  x" .. p.count, UDim2.new(1, -8, 0, 16), { Position = UDim2.fromOffset(4, 78), TextColor3 = Color3.fromRGB(150, 255, 150), ZIndex = 24 })
		if equipped[p.key] then
			label(card, "EQUIPPED", UDim2.new(1, -8, 0, 14), { Position = UDim2.fromOffset(4, 96), ZIndex = 24 })
		end
		if p.tier < 3 then
			local can = p.count >= 3
			local fuse = new("TextButton", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.new(1, -16, 0, 28),
				BackgroundColor3 = if can then Color3.fromRGB(250, 180, 40) else Color3.fromRGB(90, 94, 110),
				Text = "",
				ZIndex = 24,
				Parent = card,
			})
			corner(fuse, 8)
			label(fuse, if can then "Fuse 3 > " .. TIER_NAMES[p.tier + 1] else "Fuse (" .. p.count .. "/3)", UDim2.new(1, -8, 1, -6), { Position = UDim2.fromOffset(4, 3), ZIndex = 25 })
			fuse.Activated:Connect(function()
				if can then
					FuseRemote:FireServer(p.key)
				end
			end)
		end
	end
end
for _, attr in ipairs({ "PetsJson", "EquippedPets", "PetBonus" }) do
	player:GetAttributeChangedSignal(attr):Connect(function()
		if petPanel.Visible then
			refreshPets()
		end
	end)
end

------------------------------------------------------------------------
-- Button actions
------------------------------------------------------------------------
pressable(tpButton, tpScale, function()
	showPanel(tpPanel)
end)
pressable(petButton, petScale, function()
	refreshPets()
	showPanel(petPanel)
end)
pressable(invButton, invScale, function()
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and can then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end)
pressable(rbButton, rbScale, function()
	refreshRebirth()
	showPanel(rebirthPanel)
end)
pressable(prButton, prScale, function()
	refreshPrestige()
	showPanel(prestigePanel)
end)
pressable(passButton, passScale, function()
	if player:GetAttribute("HasCashPass") then
		return
	end
	if passId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end
end)

------------------------------------------------------------------------
-- COLLECTING CASH
--   on your screen: a cash brick with "+545" pops up, wiggles, and flies
--   into your Cash tile
--   in the world: a green swirl spins up around whoever grabbed it
------------------------------------------------------------------------
local fxLayer = new("Frame", { Name = "CashPops", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = gui })

local active = 0
local function cashPop(amount)
	if active > 8 then
		return -- plenty on screen already
	end
	active += 1
	local view = fxLayer.AbsoluteSize
	-- somewhere on the right two-thirds of the screen (clear of the buttons)
	local x = math.random(math.floor(view.X * 0.38), math.floor(view.X * 0.85))
	local y = math.random(math.floor(view.Y * 0.25), math.floor(view.Y * 0.72))
	local pop = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(170, 150),
		BackgroundTransparency = 1,
		Rotation = math.random(-12, 12),
		ZIndex = 31,
		Parent = fxLayer,
	})
	local scale = new("UIScale", { Scale = 0, Parent = pop })
	local brick = drawIcon(pop, "cash", 116)
	brick.Position = UDim2.fromOffset(27, -18)
	local text = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.fromOffset(170, 66),
		Font = FONT,
		Text = "+" .. fmt(amount),
		TextColor3 = Color3.fromRGB(215, 255, 200),
		TextScaled = true,
		ZIndex = 34,
		Parent = pop,
	})
	new("UIStroke", { Color = Color3.fromRGB(25, 95, 35), Thickness = 5, LineJoinMode = Enum.LineJoinMode.Round, Parent = text })
	new("UIGradient", { Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 255, 170)), Rotation = 90, Parent = text })
	-- pop in with a bounce, wiggle, then fly into the Cash tile
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.spawn(function()
		local r0 = pop.Rotation
		for k = 1, 6 do
			pop.Rotation = r0 + math.sin(k * 1.4) * 6
			task.wait(0.06)
		end
		task.wait(0.3)
		local tile = stats.Cash.Tile
		local target = tile.AbsolutePosition + tile.AbsoluteSize / 2 - fxLayer.AbsolutePosition
		tween(pop, 0.45, { Position = UDim2.fromOffset(target.X, target.Y), Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(scale, 0.45, { Scale = 0.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.45)
		pop:Destroy()
		active -= 1
		bounce(stats.Cash.Scale, 1.14)
	end)
end

-- the green swirl around a character: two tilted rings of glowing bits that
-- spin up around them and fade out, with a burst of sparkles
local function swirl(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local folder = new("Folder", { Name = "CashSwirl", Parent = workspace })
	local bits = {}
	for ring = 1, 2 do
		for k = 1, 14 do
			local p = new("Part", {
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = if ring == 1 then Color3.fromRGB(120, 255, 90) else Color3.fromRGB(60, 220, 120),
				Size = Vector3.new(1.3, 0.25, 0.5),
				Transparency = 0.15,
				Parent = folder,
			})
			table.insert(bits, { Part = p, Ring = ring, A = k / 14 * math.pi * 2 })
		end
	end
	local sparkle = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one, CFrame = root.CFrame, Parent = folder })
	local burst = new("ParticleEmitter", {
		Color = ColorSequence.new(Color3.fromRGB(180, 255, 140)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 0,
		Parent = sparkle,
	})
	burst:Emit(18)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > 0.7 or not root.Parent then
			conn:Disconnect()
			folder:Destroy()
			return
		end
		local u = t / 0.7
		local center = root.Position + Vector3.new(0, -1.5 + u * 2.5, 0)
		local radius = 3.2 + u * 1.2
		for _, b in ipairs(bits) do
			local a = b.A + t * (if b.Ring == 1 then 14 else -11)
			local tilt = if b.Ring == 1 then CFrame.Angles(0.35, 0, 0.15) else CFrame.Angles(-0.25, 0, -0.3)
			local offset = (tilt * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius)).Position
			local pos = center + offset
			b.Part.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
			b.Part.Transparency = 0.15 + u * 0.85
		end
	end)
end

-- the cash burst around a character when they grab cash: a green glow on the
-- whole body, a ring rippling out on the floor, bills and coins flying out,
-- and green "$" signs floating up
local lastAura = setmetatable({}, { __mode = "k" })
local function cashAura(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local now = os.clock()
	if lastAura[character] and now - lastAura[character] < 0.25 then
		return -- grabbing lots of cash at once: don't stack bursts
	end
	lastAura[character] = now
	local folder = new("Folder", { Name = "CashAura", Parent = workspace })
	local feet = root.Position - Vector3.new(0, 2.9, 0)

	-- green glow on the body
	local glow = new("Highlight", {
		FillColor = Color3.fromRGB(110, 255, 110),
		OutlineColor = Color3.fromRGB(210, 255, 190),
		FillTransparency = 0.55,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Adornee = character,
		Parent = folder,
	})
	tween(glow, 0.7, { FillTransparency = 1, OutlineTransparency = 1 })

	-- a ring rippling out on the floor (two of them, one after the other)
	for i = 0, 1 do
		local ring = new("Part", {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Color = (i == 0) and Color3.fromRGB(120, 255, 110) or Color3.fromRGB(255, 225, 80),
			Size = Vector3.new(0.15, 2, 2),
			Transparency = 0.15,
			CFrame = CFrame.new(feet + Vector3.new(0, 0.1 + i * 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Parent = folder,
		})
		task.delay(i * 0.12, function()
			tween(ring, 0.55, { Size = Vector3.new(0.15, 13 - i * 3, 13 - i * 3), Transparency = 1 }, Enum.EasingStyle.Quad)
		end)
	end

	-- bills and coins burst out, spin, and fall back down
	local bits = {}
	for i = 1, 10 do
		local isCoin = i % 3 == 0
		local p = new("Part", {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Shape = isCoin and Enum.PartType.Cylinder or Enum.PartType.Block,
			Size = isCoin and Vector3.new(0.12, 0.6, 0.6) or Vector3.new(0.9, 0.05, 0.45),
			Color = isCoin and Color3.fromRGB(255, 205, 50) or Color3.fromRGB(90, 210, 90),
			Material = Enum.Material.SmoothPlastic,
			Reflectance = isCoin and 0.3 or 0,
			Parent = folder,
		})
		local a = (i / 10) * math.pi * 2 + math.random() * 0.5
		local speed = 9 + math.random() * 6
		table.insert(bits, {
			part = p,
			vel = Vector3.new(math.cos(a) * speed * 0.6, 14 + math.random() * 8, math.sin(a) * speed * 0.6),
			spin = Vector3.new(math.random() * 12 - 6, math.random() * 12 - 6, math.random() * 12 - 6),
			pos = root.Position + Vector3.new(0, 0.5, 0),
		})
	end

	-- "$" signs floating up around them
	for i = 1, 5 do
		local bb = new("BillboardGui", {
			Size = UDim2.fromOffset(40, 40),
			StudsOffset = Vector3.new(math.random() * 4 - 2, 0, 0),
			AlwaysOnTop = false,
			LightInfluence = 0,
			Adornee = root,
			Parent = folder,
		})
		local t = new("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = "$",
			TextScaled = true,
			TextColor3 = (i % 2 == 0) and Color3.fromRGB(255, 225, 80) or Color3.fromRGB(140, 255, 120),
			Parent = bb,
		})
		new("UIStroke", { Color = Color3.fromRGB(20, 80, 25), Thickness = 3, Parent = t })
		local x = bb.StudsOffset.X
		task.delay(i * 0.07, function()
			tween(bb, 0.9, { StudsOffset = Vector3.new(x * 1.4, 4.5 + math.random() * 1.5, 0) }, Enum.EasingStyle.Quad)
			tween(t, 0.9, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(t:FindFirstChildOfClass("UIStroke"), 0.9, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
	end

	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		if t > 1.1 then
			conn:Disconnect()
			folder:Destroy()
			return
		end
		for _, b in ipairs(bits) do
			b.vel += Vector3.new(0, -45 * dt, 0)
			b.pos += b.vel * dt
			if b.pos.Y < feet.Y + 0.1 then
				b.pos = Vector3.new(b.pos.X, feet.Y + 0.1, b.pos.Z)
				b.vel = Vector3.new(b.vel.X * 0.5, -b.vel.Y * 0.3, b.vel.Z * 0.5)
			end
			b.part.CFrame = CFrame.new(b.pos) * CFrame.Angles(b.spin.X * t, b.spin.Y * t, b.spin.Z * t)
			b.part.Transparency = math.clamp((t - 0.7) / 0.4, 0, 1)
		end
	end)
end

CashFxRemote.OnClientEvent:Connect(function(_pos, amount, who)
	if who == player then
		cashPop(amount)
	end
	if who and who.Character then
		swirl(who.Character)
		cashAura(who.Character)
	end
end)

------------------------------------------------------------------------
-- BOSS CHASE BAR: who's chasing you and how close it is (top middle)
------------------------------------------------------------------------
local chase = new("Frame", {
	Name = "BossChase",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(380, 66),
	BackgroundColor3 = Color3.fromRGB(40, 20, 28),
	BackgroundTransparency = 0.15,
	Visible = false,
	ZIndex = 35,
	Parent = gui,
})
corner(chase, 14)
local chaseStroke = stroke(chase, Color3.fromRGB(255, 70, 70), 3)
local chaseName = label(chase, "", UDim2.new(1, -24, 0, 26), { Position = UDim2.fromOffset(12, 5), TextColor3 = Color3.fromRGB(255, 120, 120), ZIndex = 36 })
local chaseBack = new("Frame", { Position = UDim2.new(0, 14, 0, 38), Size = UDim2.new(1, -28, 0, 16), BackgroundColor3 = Color3.fromRGB(20, 12, 16), ZIndex = 36, Parent = chase })
corner(chaseBack, 8)
local chaseFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(110, 230, 90), ZIndex = 37, Parent = chaseBack })
corner(chaseFill, 8)
local chaseText = label(chaseBack, "", UDim2.new(1, 0, 1, 2), { Position = UDim2.fromOffset(0, -1), ZIndex = 38 })
local CHASE_RANGE = 60
local shownGap = CHASE_RANGE
RunService.RenderStepped:Connect(function(dt)
	local who = player:GetAttribute("ChasedBy")
	chase.Visible = who ~= nil
	if not who then return end
	local gap = player:GetAttribute("BossGap") or CHASE_RANGE
	shownGap += (gap - shownGap) * math.min(1, dt * 8)
	local u = math.clamp(shownGap / CHASE_RANGE, 0, 1)
	chaseName.Text = string.upper(who) .. " IS CHASING YOU!"
	chaseFill.Size = UDim2.fromScale(math.max(0.03, u), 1)
	-- green when you're far ahead, red (and shaking) when it's right behind you
	local danger = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(110, 230, 90), u)
	chaseFill.BackgroundColor3 = danger
	chaseStroke.Color = danger
	chaseText.Text = math.floor(gap) .. " studs behind you"
	chase.Rotation = (u < 0.25) and math.sin(os.clock() * 40) * 1.5 or 0
end)

------------------------------------------------------------------------
-- ZONE CLEARED: a gold card drops in, a shine sweeps across it, the trophies
-- count up, then the card shrinks and flies into your Trophies tile
------------------------------------------------------------------------
local clearLayer = new("Frame", { Name = "ZoneCleared", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = gui })
local clearToken = 0

local function burstStars(parent, center, color)
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local star = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(14, 14),
			Rotation = 45,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 44,
			Parent = parent,
		})
		corner(star, 3)
		local dist = math.random(90, 150)
		tween(star, 0.6, { Position = UDim2.fromOffset(center.X + math.cos(a) * dist, center.Y + math.sin(a) * dist), Rotation = 225, BackgroundTransparency = 1, Size = UDim2.fromOffset(6, 6) })
		task.delay(0.65, function() star:Destroy() end)
	end
end

local function zoneCleared(zoneName, trophies, mapName)
	clearToken += 1
	local token = clearToken
	clearLayer:ClearAllChildren()
	local card = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, -120),
		Size = UDim2.fromOffset(430, 140),
		BackgroundColor3 = Color3.fromRGB(255, 200, 50),
		ClipsDescendants = false,
		ZIndex = 41,
		Parent = clearLayer,
	})
	corner(card, 18)
	stroke(card, Color3.fromRGB(150, 90, 15), 4)
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(240, 160, 30)), Rotation = 90, Parent = card })
	local cardScale = new("UIScale", { Parent = card })
	-- the shine: a slanted white bar that sweeps across (clipped to the card)
	local clip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 42, Parent = card })
	corner(clip, 18)
	local shine = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, -60, 0.5, 0),
		Size = UDim2.new(0, 46, 1.6, 0),
		Rotation = 20,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 42,
		Parent = clip,
	})
	local icon = drawIcon(card, "trophy", 120)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromOffset(62, 62)
	icon.ZIndex = 43
	label(card, "ZONE CLEARED!", UDim2.fromOffset(290, 40), { Position = UDim2.fromOffset(122, 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 43 })
	label(card, (mapName and (mapName .. "  -  ") or "") .. (zoneName or ""), UDim2.fromOffset(290, 24), { Position = UDim2.fromOffset(122, 50), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 250, 225), ZIndex = 43 })
	local count = label(card, "+0", UDim2.fromOffset(290, 52), { Position = UDim2.fromOffset(122, 76), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 43 })
	count:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(150, 80, 10)
	count:FindFirstChildOfClass("UIStroke").Thickness = 4

	-- drop in
	tween(card, 0.45, { Position = UDim2.new(0.5, 0, 0.2, 0) }, Enum.EasingStyle.Back)
	task.delay(0.3, function()
		if token ~= clearToken then return end
		burstStars(clearLayer, Vector2.new(clearLayer.AbsoluteSize.X / 2, clearLayer.AbsoluteSize.Y * 0.2), Color3.fromRGB(255, 230, 90))
		tween(shine, 0.6, { Position = UDim2.new(1, 60, 0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	end)
	-- count up + trophy wobble
	task.spawn(function()
		local t0 = os.clock()
		while token == clearToken do
			local u = math.min(1, (os.clock() - t0) / 0.9)
			count.Text = "+" .. fmt(trophies * (1 - (1 - u) ^ 3))
			icon.Rotation = math.sin(os.clock() * 12) * 8 * (1 - u)
			if u >= 1 then break end
			RunService.RenderStepped:Wait()
		end
	end)
	-- fly into the Trophies tile
	task.delay(2.3, function()
		if token ~= clearToken then return end
		local tile = stats.Trophies.Tile
		local target = tile.AbsolutePosition + tile.AbsoluteSize / 2 - clearLayer.AbsolutePosition
		tween(card, 0.45, { Position = UDim2.fromOffset(target.X, target.Y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(cardScale, 0.45, { Scale = 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.45)
		if token == clearToken then
			card:Destroy()
			bounce(stats.Trophies.Scale, 1.2)
		end
	end)
end
ZoneClearedRemote.OnClientEvent:Connect(zoneCleared)

------------------------------------------------------------------------
-- EGG HATCHING: dim the screen, the egg wobbles harder and cracks, a flash,
-- the two halves fly apart and your pet pops out in front of spinning rays
------------------------------------------------------------------------
local TIER_RAY = { nil, Color3.fromRGB(255, 215, 60), Color3.fromRGB(255, 120, 230) }
local hatchLayer = new("Frame", { Name = "Hatch", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60, Visible = false, Parent = gui })
local hatchQueue = {}
local hatching = false

local function playHatch(petName, tier, bonus, fused)
	local info = PetInfo:FindFirstChild(petName)
	local body = info and info:GetAttribute("Body")
	local accent = info and info:GetAttribute("Accent")
	local style = info and info:GetAttribute("Style")
	local eggColor = info and info:GetAttribute("EggColor") or Color3.fromRGB(250, 240, 220)
	local eggSpots = info and info:GetAttribute("EggSpots") or Color3.fromRGB(120, 210, 90)
	local eggDesign = info and info:GetAttribute("EggDesign")
	local rarityName = info and info:GetAttribute("Rarity") or "Common"
	local rarityColor = info and info:GetAttribute("RarityColor") or WHITE
	local rayColor = TIER_RAY[tier] or rarityColor

	hatchLayer:ClearAllChildren()
	hatchLayer.Visible = true
	local dim = new("Frame", { BackgroundColor3 = Color3.fromRGB(10, 10, 20), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60, Parent = hatchLayer })
	tween(dim, 0.25, { BackgroundTransparency = 0.35 })
	local center = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(240, 240), BackgroundTransparency = 1, ZIndex = 61, Parent = hatchLayer })
	local centerScale = new("UIScale", { Scale = 0, Parent = center })

	if fused then
		-- three pets spin in and merge
		local minis = {}
		for i = 1, 3 do
			local mini = drawIcon(center, "pet", 90, body, accent, style)
			mini.AnchorPoint = Vector2.new(0.5, 0.5)
			local a = i / 3 * math.pi * 2
			mini.Position = UDim2.new(0.5, math.cos(a) * 110, 0.5, math.sin(a) * 110)
			minis[i] = mini
		end
		tween(centerScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		task.wait(0.4)
		for _, mini in ipairs(minis) do
			tween(mini, 0.6, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 360 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		task.wait(0.6)
		for _, mini in ipairs(minis) do mini:Destroy() end
	else
		-- the egg pops up, then wobbles harder and harder while it cracks
		local egg = drawIcon(center, "egg", 240, eggColor, eggSpots, eggDesign)
		tween(centerScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		task.wait(0.4)
		local cracks = {
			{ 0.42, 0.34, 0.14, 0.3 }, { 0.5, 0.42, 0.12, -0.6 }, { 0.58, 0.36, 0.13, 0.5 },
			{ 0.35, 0.52, 0.12, -0.4 }, { 0.65, 0.5, 0.12, 0.4 },
		}
		for step = 1, 3 do
			for k = 1, 6 do
				local amount = 6 + step * 6
				egg.Rotation = math.sin(k * 1.5) * amount
				task.wait(0.05 - step * 0.008)
			end
			egg.Rotation = 0
			for c = 1, math.min(#cracks, step * 2 - 1) do
				local cr = cracks[c]
				if not egg:FindFirstChild("Crack" .. c) then
					new("Frame", {
						Name = "Crack" .. c,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(cr[1], cr[2] + 0.12),
						Size = UDim2.new(cr[3], 0, 0, 5),
						Rotation = math.deg(cr[4]),
						BackgroundColor3 = eggColor:Lerp(Color3.new(0, 0, 0), 0.6),
						BorderSizePixel = 0,
						ZIndex = 62,
						Parent = egg,
					})
				end
			end
			task.wait(0.18)
		end
		-- the halves: two copies of the egg, each showing only its top or bottom
		local halves = {}
		for h = 1, 2 do
			local clip = new("Frame", {
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Position = UDim2.fromScale(0, h == 1 and 0 or 0.56),
				Size = UDim2.fromScale(1, h == 1 and 0.56 or 0.44),
				ZIndex = 62,
				Parent = center,
			})
			local copy = drawIcon(clip, "egg", 240, eggColor, eggSpots, eggDesign)
			copy.Position = UDim2.fromOffset(0, h == 1 and 0 or -240 * 0.56)
			halves[h] = clip
		end
		egg:Destroy()
		tween(halves[1], 0.5, { Position = UDim2.new(-0.35, 0, -0.45, 0), Rotation = -35 }, Enum.EasingStyle.Quad)
		tween(halves[2], 0.5, { Position = UDim2.new(0.35, 0, 0.95, 0), Rotation = 25 }, Enum.EasingStyle.Quad)
		task.delay(0.5, function()
			for _, h in ipairs(halves) do h:Destroy() end
		end)
	end

	-- flash
	local flash = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = 70, Parent = hatchLayer })
	tween(flash, 0.5, { BackgroundTransparency = 1 })

	-- spinning rays in the pet's rarity color
	local rays = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(520, 520), BackgroundTransparency = 1, ZIndex = 61, Parent = hatchLayer })
	for r = 1, 12 do
		local ray = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 34, 0.5, 0),
			Rotation = r * 30,
			BackgroundColor3 = rayColor,
			BorderSizePixel = 0,
			ZIndex = 61,
			Parent = rays,
		})
		new("UIGradient", { Transparency = NumberSequence.new(1, 0.35), Rotation = 90, Parent = ray })
	end
	-- the rays turn around their bottom center, so give each one a pivot frame
	for _, ray in ipairs(rays:GetChildren()) do
		local rot = ray.Rotation
		local pivot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Rotation = rot, BackgroundTransparency = 1, ZIndex = 61, Parent = rays })
		ray.Rotation = 0
		ray.Parent = pivot
	end
	local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(230, 230), BackgroundColor3 = rayColor, BackgroundTransparency = 0.55, ZIndex = 61, Parent = hatchLayer })
	corner(glow, 999)

	-- the pet
	local petHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(200, 200), BackgroundTransparency = 1, ZIndex = 63, Parent = hatchLayer })
	local petScale = new("UIScale", { Scale = 0.2, Parent = petHolder })
	drawIcon(petHolder, "pet", 200, body, accent, style)
	tween(petScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	center:Destroy()

	local tierName = TIER_NAMES[tier] or ""
	local title = label(hatchLayer, (fused and "FUSED!  " or "") .. tierName .. petName, UDim2.fromOffset(520, 52), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, 120),
		TextColor3 = TIER_COLORS[tier] or WHITE,
		ZIndex = 64,
	})
	local sub = label(hatchLayer, string.upper(rarityName) .. "   +" .. fmt(bonus) .. "% cash", UDim2.fromOffset(420, 32), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, 176),
		TextColor3 = rarityColor,
		ZIndex = 64,
	})
	for _, l in ipairs({ title, sub }) do
		l.TextTransparency = 1
		tween(l, 0.4, { TextTransparency = 0 })
	end

	local t0 = os.clock()
	local done = false
	local skip = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = hatchLayer })
	skip.Activated:Connect(function() done = true end)
	while not done and os.clock() - t0 < 2.6 do
		local t = os.clock() - t0
		rays.Rotation = t * 40
		petHolder.Rotation = math.sin(t * 3) * 6
		glow.Size = UDim2.fromOffset(230 + math.sin(t * 5) * 14, 230 + math.sin(t * 5) * 14)
		RunService.RenderStepped:Wait()
	end
	tween(petScale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(dim, 0.3, { BackgroundTransparency = 1 })
	for _, l in ipairs({ title, sub }) do tween(l, 0.25, { TextTransparency = 1 }) end
	rays.Visible = false
	glow.Visible = false
	task.wait(0.3)
	hatchLayer.Visible = false
	hatchLayer:ClearAllChildren()
end

PetHatchedRemote.OnClientEvent:Connect(function(petName, tier, bonus, fused)
	if #hatchQueue >= 3 then return end
	table.insert(hatchQueue, { petName, tier, bonus, fused })
	if hatching then return end
	hatching = true
	task.spawn(function()
		while #hatchQueue > 0 do
			local h = table.remove(hatchQueue, 1)
			local ok, err = pcall(playHatch, h[1], h[2], h[3], h[4])
			if not ok then
				warn("hatch animation: " .. tostring(err))
				hatchLayer.Visible = false
			end
		end
		hatching = false
	end)
end)
