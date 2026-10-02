--[[
	SPEED VS BRAINROT  —  HUD  (LocalScript)
	Put this in: StarterPlayer > StarterPlayerScripts  (next to SpeedVsBrainrot_Client)

	What it adds:
	  • Three chunky studded stat tiles on the left: Speed (red, a sneaker),
	    Cash (green, a cash brick) and Trophies (yellow, a trophy). The numbers
	    count up and the tile bounces when they go up.
	  • Four big square buttons under them:
	      Teleport  (a swirling portal)   - spawn, the speed pad, or the egg row
	      3x Cash   (an angry bat)        - your gamepass ("ONLY <robux>price!" above it)
	      Invite    (two friends)         - invite friends ("Play with friends!")
	      Pets      (a puppy)             - your pets, what they give, and Fuse 3 -> 1 better pet
	  • When you collect cash: a big cash brick with "+545" pops up on the
	    screen, wiggles, then flies into your Cash tile; and a green swirl
	    spins around your character (other players see your swirl too).
	  • When you earn trophies: a gold banner slides down at the top (trophy +3).

	No emojis and no uploaded images: every icon is drawn out of rounded
	frames (see ICONS below), so it looks the same on every device.

	It reads the stats the server already puts on your player (Cash, Speed,
	Trophies, HasCashPass, PetsJson, EquippedPets) and uses the server's
	remotes (CashFx, Teleport, Fuse), so the server script needs no changes.
	If your SpeedVsBrainrot_Client already draws its own stat boxes, delete
	those so you don't see them twice.
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
local PetInfo = ReplicatedStorage:WaitForChild("SVB_Pets")

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
	-- a chunky 3D stack: the front of the bills, the lighter top, and a
	-- yellow paper band wrapping over both
	return {
		S(0.5, 0.63, 0.86, 0.38, rgb(50, 175, 60), { r = 0.1, rot = -12 }),
		S(0.5, 0.58, 0.82, 0.03, rgb(25, 110, 35), { rot = -12, line = 0, flat = true }),
		S(0.5, 0.67, 0.82, 0.03, rgb(25, 110, 35), { rot = -12, line = 0, flat = true }),
		S(0.5, 0.76, 0.8, 0.03, rgb(25, 110, 35), { rot = -12, line = 0, flat = true }),
		S(0.53, 0.4, 0.84, 0.2, rgb(140, 235, 110), { r = 0.12, rot = -12 }),
		S(0.51, 0.64, 0.2, 0.39, rgb(240, 165, 30), { r = 0.04, rot = -12 }),
		S(0.53, 0.4, 0.19, 0.21, rgb(255, 215, 80), { r = 0.04, rot = -12 }),
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

-- an egg with spots
function ICONS.egg()
	return {
		S(0.5, 0.54, 0.62, 0.8, rgb(250, 240, 220), { r = 0.5 }),
		S(0.38, 0.42, 0.14, 0.12, rgb(120, 210, 90), { r = 0.5, line = 0 }),
		S(0.6, 0.6, 0.18, 0.15, rgb(120, 210, 90), { r = 0.5, line = 0 }),
		S(0.42, 0.74, 0.12, 0.1, rgb(120, 210, 90), { r = 0.5, line = 0 }),
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
-- one size on every screen (designed for a 720 px tall screen)
local screenScale = new("UIScale", { Parent = gui })
local function rescale()
	local cam = workspace.CurrentCamera
	local h = cam and cam.ViewportSize.Y or 720
	screenScale.Scale = math.clamp(h / 720, 0.62, 1.35)
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

local column = new("Frame", {
	Name = "LeftColumn",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 96),
	Size = UDim2.fromOffset(240, 600),
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

-- teleport menu
local tpPanel = panel("TeleportMenu", UDim2.fromOffset(300, 250), "Teleport", COLORS.teleport, "portal")
for i, place in ipairs({ { "spawn", "Spawn", "portal" }, { "pad", "Speed Pad", "shoe" }, { "eggs", "Pet Eggs", "egg" } }) do
	local b = new("TextButton", {
		Position = UDim2.fromOffset(20, 62 + (i - 1) * 60),
		Size = UDim2.new(1, -40, 0, 50),
		BackgroundColor3 = COLORS.teleport:Lerp(WHITE, 0.1),
		Text = "",
		ZIndex = 22,
		Parent = tpPanel,
	})
	corner(b, 12)
	stroke(b, COLORS.teleport:Lerp(Color3.new(0, 0, 0), 0.4), 3)
	drawIcon(b, place[3], 40).Position = UDim2.fromOffset(8, 2)
	label(b, place[2], UDim2.new(1, -70, 1, -12), { Position = UDim2.fromOffset(58, 6), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23 })
	b.Activated:Connect(function()
		TeleportRemote:FireServer(place[1])
		closePanel()
	end)
end

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
-- trophy banner: slides down at the top when you earn trophies
------------------------------------------------------------------------
local banner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -130),
	Size = UDim2.new(1, 0, 0, 84),
	BackgroundColor3 = Color3.fromRGB(120, 92, 30),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	ZIndex = 40,
	Parent = gui,
})
new("UIGradient", {
	Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 70, 80)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(190, 150, 50)), ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 70, 80)) }),
	Parent = banner,
})
for _, y in ipairs({ 0, 1 }) do
	new("Frame", { AnchorPoint = Vector2.new(0, y), Position = UDim2.fromScale(0, y), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Color3.fromRGB(255, 205, 60), BorderSizePixel = 0, ZIndex = 41, Parent = banner })
end
local bannerIcon = drawIcon(banner, "trophy", 66)
bannerIcon.AnchorPoint = Vector2.new(1, 0)
bannerIcon.Position = UDim2.new(0.5, -10, 0, 9)
local bannerText = label(banner, "", UDim2.new(0.4, 0, 0, 62), { Position = UDim2.new(0.5, 4, 0, 11), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 })
local lastTrophies = player:GetAttribute("Trophies") or 0
local bannerToken = 0
player:GetAttributeChangedSignal("Trophies"):Connect(function()
	local now = player:GetAttribute("Trophies") or 0
	local gained = now - lastTrophies
	lastTrophies = now
	if gained <= 0 then
		return
	end
	bannerToken += 1
	local token = bannerToken
	bannerText.Text = "+" .. fmt(gained)
	tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, 0) }, Enum.EasingStyle.Back)
	task.delay(2.2, function()
		if bannerToken == token then
			tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -130) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
end)
