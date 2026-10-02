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
	    screen, wiggles, then flies into your Cash tile; and a green swirl
	    spins around your character (other players see your swirl too).
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

-- a pet: a round face with ears (colors from the pet; a puppy by default)
function ICONS.pet(body, accent)
	body = body or rgb(200, 140, 80)
	accent = accent or rgb(140, 85, 45)
	return {
		S(0.22, 0.42, 0.22, 0.4, accent, { r = 0.5, rot = 20 }),
		S(0.78, 0.42, 0.22, 0.4, accent, { r = 0.5, rot = -20 }),
		S(0.5, 0.52, 0.66, 0.62, body, { r = 0.5 }),
		S(0.5, 0.66, 0.36, 0.26, body:Lerp(rgb(255, 255, 255), 0.55), { r = 0.5 }),
		S(0.5, 0.6, 0.14, 0.09, rgb(30, 25, 25), { r = 0.5, flat = true }),
		S(0.38, 0.46, 0.08, 0.11, rgb(30, 25, 25), { r = 0.5, line = 0, flat = true }),
		S(0.62, 0.46, 0.08, 0.11, rgb(30, 25, 25), { r = 0.5, line = 0, flat = true }),
		S(0.39, 0.44, 0.03, 0.03, rgb(255, 255, 255), { r = 0.5, line = 0, flat = true }),
		S(0.63, 0.44, 0.03, 0.03, rgb(255, 255, 255), { r = 0.5, line = 0, flat = true }),
		S(0.5, 0.75, 0.08, 0.08, rgb(255, 120, 150), { r = 0.5, line = 0, flat = true }),
	}
end

-- an egg with a stripe and spots (colors from the egg; cream + green by default)
function ICONS.egg(color, spots)
	color = color or rgb(250, 240, 220)
	spots = spots or rgb(120, 210, 90)
	return {
		S(0.5, 0.54, 0.62, 0.8, color, { r = 0.5 }),
		S(0.5, 0.56, 0.6, 0.08, spots, { line = 0, flat = true }),
		S(0.38, 0.38, 0.14, 0.12, spots, { r = 0.5, line = 0 }),
		S(0.62, 0.42, 0.11, 0.1, spots, { r = 0.5, line = 0 }),
		S(0.6, 0.72, 0.16, 0.13, spots, { r = 0.5, line = 0 }),
		S(0.4, 0.74, 0.11, 0.1, spots, { r = 0.5, line = 0 }),
		S(0.36, 0.3, 0.07, 0.14, rgb(255, 255, 255), { r = 0.5, line = 0, flat = true, a = 0.35, rot = 20 }),
	}
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
		local face = drawIcon(card, "pet", 54, p.info:GetAttribute("Body"), p.info:GetAttribute("Accent"))
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

CashFxRemote.OnClientEvent:Connect(function(_pos, amount, who)
	if who == player then
		cashPop(amount)
	end
	if who and who.Character then
		swirl(who.Character)
	end
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
	local eggColor = info and info:GetAttribute("EggColor") or Color3.fromRGB(250, 240, 220)
	local eggSpots = info and info:GetAttribute("EggSpots") or Color3.fromRGB(120, 210, 90)
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
			local mini = drawIcon(center, "pet", 90, body, accent)
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
		local egg = drawIcon(center, "egg", 240, eggColor, eggSpots)
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
			local copy = drawIcon(clip, "egg", 240, eggColor, eggSpots)
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
	drawIcon(petHolder, "pet", 200, body, accent)
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
