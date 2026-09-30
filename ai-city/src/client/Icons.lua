-- Icons (ModuleScript) — StarterPlayerScripts.CityClient.Icons
-- AI City's own icon set, drawn from rounded shapes (no image uploads needed,
-- and they stay sharp at any size).
--
--   Icons.Glyph(parent, "map", 28, props)          just the drawing
--   Icons.Badge(parent, "map", 60, color, props)   an app icon: the drawing on a
--                                                  glossy rounded square
--   Icons.Set(icon, "moon")                        swap the drawing in place
--   Icons.Has(name)
--
-- Every icon is drawn on a 1×1 grid (0,0 is the top left, 0.5,0.5 the middle).
-- "fg" is the icon's main color (white by default); "hole" is the color of the
-- cut-outs (the badge or background color behind it). Some icons (coins,
-- hearts, weapons...) have their own colors.

local Icons = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local GOLD, GOLD_DARK, GOLD_LIGHT = rgb(255, 196, 72), rgb(214, 146, 36), rgb(255, 226, 130)
local RED, RED_DARK = rgb(240, 70, 84), rgb(190, 40, 56)
local WOOD, WOOD_DARK = rgb(206, 150, 90), rgb(150, 100, 56)
local METAL, METAL_DARK = rgb(206, 212, 224), rgb(130, 138, 156)
local SKIN = rgb(236, 190, 150)
local KNIT = rgb(38, 38, 46)

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
-- a drawing context maps grid coordinates into a frame (clip boxes get their own)
local function context(frame, px, fg, hole, z)
	return { Frame = frame, X0 = 0, Y0 = 0, SX = 1, SY = 1, Px = px, Fg = fg, Hole = hole, Z = z, N = 0 }
end

local function place(ctx, gui, x, y, w, h)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale((x - ctx.X0) / ctx.SX, (y - ctx.Y0) / ctx.SY)
	gui.Size = UDim2.fromScale(w / ctx.SX, h / ctx.SY)
	ctx.N += 1
	gui.ZIndex = ctx.Z + ctx.N
	gui.BorderSizePixel = 0
	gui.Name = "Ink"
	gui.Parent = ctx.Frame
	return gui
end

local function decorate(gui, o)
	if o.r then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(o.r, 0)
		c.Parent = gui
	end
	if o.rot then
		gui.Rotation = o.rot
	end
	if o.grad then
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(o.grad[1], o.grad[2])
		g.Rotation = o.grad[3] or 90
		g.Parent = gui
	end
end

-- a rectangle centered on x, y (o.r = corner roundness 0..0.5, o.rot = degrees)
local function R(ctx, x, y, w, h, color, o)
	o = o or {}
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = o.t or 0
	place(ctx, f, x, y, w, h)
	decorate(f, o)
	return f
end

-- a circle
local function C(ctx, x, y, d, color, o)
	o = o or {}
	o.r = 0.5
	return R(ctx, x, y, d, d, color, o)
end

-- a ring (d = outer size, t = line width)
local function O(ctx, x, y, d, t, color, o)
	o = o or {}
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	place(ctx, f, x, y, d - 2 * t, d - 2 * t)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(o.r or 0.5, 0)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = math.max(1, t * ctx.Px)
	s.Transparency = o.t or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	if o.rot then
		f.Rotation = o.rot
	end
	return f
end

-- a text glyph (★, ?, ...)
local function T(ctx, x, y, s, text, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.Font = font or Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextSize = math.max(8, math.floor(s * ctx.Px * 0.9))
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	place(ctx, l, x, y, s, s)
	return l
end

-- draw inside a box that cuts off everything outside it (x0, y0 → x1, y1)
local function clip(ctx, x0, y0, x1, y1, fn)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.ClipsDescendants = true
	place(ctx, f, (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0)
	local sub = { Frame = f, X0 = x0, Y0 = y0, SX = x1 - x0, SY = y1 - y0, Px = ctx.Px, Fg = ctx.Fg, Hole = ctx.Hole, Z = f.ZIndex or 1, N = 0 }
	fn(sub)
	return f
end

-- the point `dist` along a rotated line through x, y
local function along(x, y, rot, dist)
	local a = math.rad(rot)
	return x + math.sin(a) * dist, y - math.cos(a) * dist
end

local function shade(c, k)
	return c:Lerp(BLACK, k)
end

--------------------------------------------------------------------------------
-- The icons
--------------------------------------------------------------------------------
local D = {}

D.phone = function(c)
	R(c, 0.5, 0.5, 0.48, 0.84, c.Fg, { r = 0.2 })
	R(c, 0.5, 0.48, 0.38, 0.6, c.Hole, { r = 0.08 })
	R(c, 0.5, 0.155, 0.14, 0.035, c.Hole, { r = 0.5 })
	C(c, 0.5, 0.86, 0.075, c.Hole)
	-- a little app grid on the screen
	for i = 0, 1 do
		for j = 0, 2 do
			R(c, 0.4 + i * 0.2, 0.3 + j * 0.16, 0.12, 0.1, c.Fg, { r = 0.3, t = 0.35 })
		end
	end
end

D.map = function(c)
	local fg = c.Fg
	R(c, 0.27, 0.52, 0.25, 0.64, fg, { rot = -5, r = 0.06 })
	R(c, 0.5, 0.52, 0.25, 0.64, shade(fg, 0.18), { rot = 5, r = 0.06 })
	R(c, 0.73, 0.52, 0.25, 0.64, fg, { rot = -5, r = 0.06 })
	-- a dotted route
	for k, p in ipairs({ { 0.22, 0.7 }, { 0.32, 0.62 }, { 0.42, 0.58 }, { 0.52, 0.56 } }) do
		C(c, p[1], p[2], 0.055, RED, { t = k * 0.1 })
	end
	-- the pin
	R(c, 0.66, 0.44, 0.2, 0.2, RED_DARK, { rot = 45, r = 0.15 })
	C(c, 0.66, 0.33, 0.3, RED)
	C(c, 0.66, 0.33, 0.12, WHITE)
end

D.people = function(c)
	local back = shade(c.Fg, 0.22)
	C(c, 0.68, 0.34, 0.24, back)
	R(c, 0.68, 0.66, 0.36, 0.3, back, { r = 0.5 })
	R(c, 0.68, 0.75, 0.36, 0.12, back)
	C(c, 0.4, 0.37, 0.3, c.Hole)
	C(c, 0.4, 0.37, 0.26, c.Fg)
	R(c, 0.4, 0.72, 0.5, 0.34, c.Hole, { r = 0.5 })
	R(c, 0.4, 0.72, 0.44, 0.3, c.Fg, { r = 0.5 })
	R(c, 0.4, 0.81, 0.44, 0.12, c.Fg)
end

D.news = function(c)
	R(c, 0.54, 0.52, 0.6, 0.74, c.Fg, { r = 0.1 })
	R(c, 0.27, 0.6, 0.14, 0.5, shade(c.Fg, 0.2), { r = 0.3 })
	R(c, 0.54, 0.27, 0.44, 0.08, c.Hole, { r = 0.5 })
	R(c, 0.43, 0.46, 0.2, 0.18, rgb(84, 150, 255), { r = 0.15 })
	R(c, 0.66, 0.41, 0.16, 0.05, c.Hole, { r = 0.5, t = 0.3 })
	R(c, 0.66, 0.5, 0.16, 0.05, c.Hole, { r = 0.5, t = 0.3 })
	R(c, 0.54, 0.64, 0.44, 0.05, c.Hole, { r = 0.5, t = 0.3 })
	R(c, 0.5, 0.74, 0.36, 0.05, c.Hole, { r = 0.5, t = 0.3 })
end

D.vote = function(c)
	R(c, 0.5, 0.34, 0.38, 0.4, WHITE, { rot = -8, r = 0.08 })
	R(c, 0.45, 0.34, 0.09, 0.045, rgb(60, 180, 100), { rot = 45 })
	R(c, 0.53, 0.31, 0.18, 0.045, rgb(60, 180, 100), { rot = -50 })
	R(c, 0.5, 0.67, 0.72, 0.4, c.Fg, { r = 0.12 })
	R(c, 0.5, 0.49, 0.72, 0.06, shade(c.Fg, 0.25), { r = 0.5 })
	R(c, 0.5, 0.49, 0.42, 0.035, c.Hole, { r = 0.5 })
	R(c, 0.5, 0.7, 0.24, 0.08, c.Hole, { r = 0.5, t = 0.4 })
end

D.goals = function(c)
	C(c, 0.46, 0.54, 0.78, c.Fg)
	C(c, 0.46, 0.54, 0.58, c.Hole)
	C(c, 0.46, 0.54, 0.4, c.Fg)
	C(c, 0.46, 0.54, 0.2, RED)
	-- the dart
	R(c, 0.63, 0.37, 0.4, 0.05, shade(c.Fg, 0.6), { rot = -45, r = 0.5 })
	R(c, 0.8, 0.2, 0.11, 0.11, RED, { rot = 45, r = 0.2 })
end

D.mic = function(c)
	clip(c, 0.2, 0.4, 0.8, 0.74, function(k)
		O(k, 0.5, 0.42, 0.52, 0.06, c.Fg)
	end)
	R(c, 0.5, 0.35, 0.3, 0.5, c.Fg, { r = 0.5 })
	R(c, 0.5, 0.28, 0.16, 0.035, c.Hole, { r = 0.5, t = 0.3 })
	R(c, 0.5, 0.36, 0.16, 0.035, c.Hole, { r = 0.5, t = 0.3 })
	R(c, 0.5, 0.44, 0.16, 0.035, c.Hole, { r = 0.5, t = 0.3 })
	R(c, 0.5, 0.79, 0.07, 0.14, c.Fg)
	R(c, 0.5, 0.87, 0.34, 0.07, c.Fg, { r = 0.5 })
end

D.mayor = function(c)
	clip(c, 0.1, 0.05, 0.9, 0.36, function(k)
		R(k, 0.5, 0.37, 0.44, 0.44, c.Fg, { rot = 45, r = 0.06 })
	end)
	C(c, 0.5, 0.27, 0.08, c.Hole)
	R(c, 0.5, 0.39, 0.7, 0.07, c.Fg, { r = 0.3 })
	for _, x in ipairs({ 0.24, 0.41, 0.59, 0.76 }) do
		R(c, x, 0.59, 0.09, 0.3, c.Fg)
	end
	R(c, 0.5, 0.78, 0.72, 0.07, c.Fg)
	R(c, 0.5, 0.86, 0.82, 0.07, c.Fg, { r = 0.3 })
end

D.help = function(c)
	C(c, 0.5, 0.5, 0.82, c.Fg)
	T(c, 0.51, 0.5, 0.58, "?", c.Hole, Enum.Font.FredokaOne)
end

D.settings = function(c)
	for k = 0, 3 do
		R(c, 0.5, 0.5, 0.17, 0.88, c.Fg, { rot = k * 45, r = 0.25 })
	end
	C(c, 0.5, 0.5, 0.68, c.Fg)
	C(c, 0.5, 0.5, 0.28, c.Hole)
end

D.chat = function(c)
	R(c, 0.34, 0.72, 0.18, 0.18, c.Fg, { rot = 30, r = 0.1 })
	R(c, 0.5, 0.46, 0.84, 0.58, c.Fg, { r = 0.4 })
	for _, x in ipairs({ 0.32, 0.5, 0.68 }) do
		C(c, x, 0.46, 0.1, c.Hole)
	end
end

D.siren = function(c)
	for _, a in ipairs({ -55, 0, 55 }) do
		local x, y = along(0.5, 0.5, a, 0.4)
		R(c, x, y, 0.06, 0.13, RED, { rot = a, r = 0.5 })
	end
	clip(c, 0.1, 0.1, 0.9, 0.66, function(k)
		C(k, 0.5, 0.66, 0.52, RED, { grad = { rgb(255, 150, 150), RED, 90 } })
	end)
	R(c, 0.4, 0.5, 0.07, 0.14, WHITE, { r = 0.5, t = 0.3, rot = -20 })
	R(c, 0.5, 0.71, 0.66, 0.12, c.Fg, { r = 0.3 })
	R(c, 0.5, 0.82, 0.74, 0.08, shade(c.Fg, 0.25), { r = 0.3 })
end

D.fist = function(c)
	local fg = c.Fg
	R(c, 0.52, 0.84, 0.36, 0.16, shade(fg, 0.15), { r = 0.2 })
	R(c, 0.52, 0.56, 0.58, 0.46, fg, { r = 0.22 })
	for k, x in ipairs({ 0.33, 0.47, 0.61, 0.75 }) do
		R(c, x, 0.36 + (if k == 1 or k == 4 then 0.03 else 0), 0.13, 0.24, fg, { r = 0.45 })
		R(c, x + 0.066, 0.4, 0.012, 0.16, c.Hole, { t = 0.5 })
	end
	R(c, 0.43, 0.6, 0.36, 0.13, shade(fg, 0.12), { r = 0.5, rot = -12 })
	R(c, 0.43, 0.6, 0.3, 0.012, c.Hole, { t = 0.6, rot = -12 })
end

D.shield = function(c, star)
	R(c, 0.5, 0.6, 0.46, 0.46, c.Fg, { rot = 45, r = 0.12 })
	R(c, 0.5, 0.38, 0.66, 0.46, c.Fg, { r = 0.14 })
	-- the right half a little darker, like light from the left
	clip(c, 0.5, 0, 1, 1, function(k)
		R(k, 0.5, 0.6, 0.46, 0.46, shade(c.Fg, 0.14), { rot = 45, r = 0.12 })
		R(k, 0.5, 0.38, 0.66, 0.46, shade(c.Fg, 0.14), { r = 0.14 })
	end)
	if star ~= false then
		T(c, 0.5, 0.47, 0.36, "★", c.Hole)
	end
end

D.coin = function(c)
	C(c, 0.5, 0.54, 0.82, GOLD_DARK)
	C(c, 0.5, 0.5, 0.82, GOLD, { grad = { GOLD_LIGHT, GOLD, 90 } })
	O(c, 0.5, 0.5, 0.62, 0.05, GOLD_DARK, { t = 0.3 })
	T(c, 0.5, 0.51, 0.36, "★", GOLD_DARK)
	R(c, 0.33, 0.28, 0.16, 0.06, WHITE, { r = 0.5, rot = -40, t = 0.3 })
end

D.heart = function(c)
	C(c, 0.36, 0.42, 0.36, RED)
	C(c, 0.64, 0.42, 0.36, RED)
	R(c, 0.5, 0.58, 0.36, 0.36, RED, { rot = 45, r = 0.08 })
	C(c, 0.34, 0.38, 0.12, WHITE, { t = 0.35 })
end

D.star = function(c)
	T(c, 0.5, 0.5, 0.95, "★", c.Fg)
end

D.smile = function(c)
	C(c, 0.5, 0.5, 0.84, c.Fg)
	C(c, 0.37, 0.42, 0.11, c.Hole)
	C(c, 0.63, 0.42, 0.11, c.Hole)
	clip(c, 0.2, 0.55, 0.8, 0.8, function(k)
		O(k, 0.5, 0.5, 0.46, 0.075, c.Hole)
	end)
end

D.sun = function(c)
	for k = 0, 3 do
		R(c, 0.5, 0.5, 0.08, 0.92, GOLD, { rot = k * 45, r = 0.5 })
	end
	C(c, 0.5, 0.5, 0.6, c.Hole)
	C(c, 0.5, 0.5, 0.52, GOLD, { grad = { GOLD_LIGHT, GOLD, 90 } })
end

D.moon = function(c)
	C(c, 0.46, 0.52, 0.74, rgb(255, 236, 170), { grad = { rgb(255, 245, 200), rgb(250, 214, 120), 90 } })
	C(c, 0.66, 0.38, 0.6, c.Hole)
	C(c, 0.3, 0.6, 0.08, rgb(230, 190, 100), { t = 0.3 })
	T(c, 0.82, 0.74, 0.18, "★", rgb(255, 236, 170))
end

D.sunset = function(c)
	clip(c, 0, 0, 1, 0.66, function(k)
		for j = -1, 1 do
			R(k, 0.5, 0.66, 0.07, 0.92, rgb(255, 150, 70), { rot = j * 45, r = 0.5 })
		end
		C(k, 0.5, 0.66, 0.52, rgb(255, 150, 70), { grad = { rgb(255, 214, 110), rgb(255, 120, 60), 90 } })
	end)
	R(c, 0.5, 0.74, 0.8, 0.06, rgb(255, 150, 70), { r = 0.5 })
	R(c, 0.5, 0.84, 0.5, 0.05, rgb(255, 150, 70), { r = 0.5, t = 0.35 })
end

D.bat = function(c)
	local rot = 40
	local x, y = along(0.5, 0.5, rot, 0.12)
	R(c, x, y, 0.22, 0.62, WOOD, { rot = rot, r = 0.5, grad = { rgb(236, 190, 130), WOOD, 0 } })
	x, y = along(0.5, 0.5, rot, -0.24)
	R(c, x, y, 0.07, 0.36, WOOD_DARK, { rot = rot, r = 0.5 })
	x, y = along(0.5, 0.5, rot, -0.3)
	R(c, x, y, 0.09, 0.18, rgb(60, 60, 70), { rot = rot, r = 0.4 })
	x, y = along(0.5, 0.5, rot, -0.42)
	C(c, x, y, 0.12, rgb(60, 60, 70))
end

D.hammer = function(c)
	local rot = 40
	local x, y = along(0.46, 0.56, rot, 0)
	R(c, x, y, 0.1, 0.66, WOOD, { rot = rot, r = 0.4 })
	x, y = along(0.46, 0.56, rot, -0.2)
	R(c, x, y, 0.13, 0.24, RED, { rot = rot, r = 0.4 })
	local hx, hy = along(0.46, 0.56, rot, 0.3)
	R(c, hx, hy, 0.54, 0.2, METAL, { rot = rot, r = 0.18, grad = { WHITE, METAL, 90 } })
	-- the striking face and the claw
	local a = math.rad(rot)
	R(c, hx + math.cos(a) * 0.26, hy + math.sin(a) * 0.26, 0.08, 0.24, METAL_DARK, { rot = rot, r = 0.3 })
	R(c, hx - math.cos(a) * 0.27, hy - math.sin(a) * 0.27, 0.12, 0.12, METAL_DARK, { rot = rot + 45, r = 0.2 })
end

D.knife = function(c)
	local rot = 40
	local x, y = along(0.5, 0.5, rot, 0.14)
	R(c, x, y, 0.17, 0.5, METAL, { rot = rot, r = 0.5, grad = { WHITE, METAL, 0 } })
	x, y = along(0.5, 0.5, rot, 0.1)
	local a = math.rad(rot)
	R(c, x - math.cos(a) * 0.045, y - math.sin(a) * 0.045, 0.06, 0.44, METAL_DARK, { rot = rot, r = 0.5, t = 0.4 })
	x, y = along(0.5, 0.5, rot, -0.13)
	R(c, x, y, 0.3, 0.06, rgb(90, 94, 110), { rot = rot, r = 0.5 })
	x, y = along(0.5, 0.5, rot, -0.3)
	R(c, x, y, 0.13, 0.3, rgb(52, 44, 44), { rot = rot, r = 0.35 })
	for _, d in ipairs({ -0.25, -0.35 }) do
		local px, py = along(0.5, 0.5, rot, d)
		C(c, px, py, 0.04, METAL)
	end
end

D.hoodie = function(c)
	local body = rgb(70, 74, 92)
	R(c, 0.5, 0.7, 0.72, 0.5, body, { r = 0.22 })
	C(c, 0.5, 0.36, 0.5, body)
	C(c, 0.5, 0.4, 0.3, rgb(28, 28, 36))
	C(c, 0.44, 0.4, 0.05, rgb(230, 230, 240))
	C(c, 0.56, 0.4, 0.05, rgb(230, 230, 240))
	R(c, 0.45, 0.62, 0.025, 0.14, WHITE, { r = 0.5 })
	R(c, 0.55, 0.62, 0.025, 0.14, WHITE, { r = 0.5 })
	R(c, 0.5, 0.82, 0.36, 0.1, shade(body, 0.2), { r = 0.4 })
end

D.disguise = function(c)
	local hat = rgb(120, 86, 60)
	R(c, 0.5, 0.26, 0.46, 0.26, hat, { r = 0.25 })
	R(c, 0.5, 0.33, 0.46, 0.06, rgb(30, 30, 30))
	R(c, 0.5, 0.41, 0.82, 0.08, shade(hat, 0.15), { r = 0.5 })
	for _, x in ipairs({ 0.36, 0.64 }) do
		C(c, x, 0.58, 0.24, rgb(24, 24, 30))
		R(c, x - 0.04, 0.55, 0.08, 0.035, WHITE, { r = 0.5, t = 0.45, rot = -30 })
	end
	R(c, 0.5, 0.57, 0.1, 0.035, rgb(24, 24, 30))
	R(c, 0.5, 0.77, 0.34, 0.1, rgb(80, 52, 34), { r = 0.5 })
	C(c, 0.31, 0.75, 0.12, rgb(80, 52, 34))
	C(c, 0.69, 0.75, 0.12, rgb(80, 52, 34))
end

D.mask = function(c)
	C(c, 0.5, 0.14, 0.14, KNIT)
	C(c, 0.5, 0.52, 0.76, KNIT, { grad = { rgb(70, 70, 84), KNIT, 90 } })
	R(c, 0.5, 0.46, 0.52, 0.15, SKIN, { r = 0.5 })
	C(c, 0.39, 0.46, 0.08, rgb(30, 30, 36))
	C(c, 0.61, 0.46, 0.08, rgb(30, 30, 36))
	R(c, 0.5, 0.68, 0.16, 0.06, rgb(170, 70, 70), { r = 0.5 })
	for _, y in ipairs({ 0.3, 0.84 }) do
		R(c, 0.5, y, 0.34, 0.02, WHITE, { t = 0.8 })
	end
end

D.idcard = function(c)
	R(c, 0.5, 0.52, 0.86, 0.62, c.Fg, { r = 0.12 })
	R(c, 0.5, 0.27, 0.86, 0.1, shade(c.Fg, 0.2), { r = 0.3 })
	C(c, 0.3, 0.47, 0.18, c.Hole)
	R(c, 0.3, 0.66, 0.24, 0.14, c.Hole, { r = 0.5 })
	R(c, 0.65, 0.44, 0.3, 0.06, c.Hole, { r = 0.5 })
	R(c, 0.65, 0.56, 0.3, 0.06, c.Hole, { r = 0.5, t = 0.4 })
	R(c, 0.61, 0.68, 0.22, 0.06, c.Hole, { r = 0.5, t = 0.4 })
end

D.elevator = function(c)
	R(c, 0.5, 0.6, 0.72, 0.68, c.Fg, { r = 0.1 })
	R(c, 0.36, 0.62, 0.24, 0.56, c.Hole, { t = 0.35, r = 0.05 })
	R(c, 0.64, 0.62, 0.24, 0.56, c.Hole, { t = 0.35, r = 0.05 })
	T(c, 0.36, 0.13, 0.2, "▲", c.Fg)
	T(c, 0.64, 0.13, 0.2, "▼", c.Fg)
end

D.trophy = function(c)
	O(c, 0.25, 0.36, 0.24, 0.05, GOLD_DARK)
	O(c, 0.75, 0.36, 0.24, 0.05, GOLD_DARK)
	R(c, 0.5, 0.28, 0.52, 0.24, GOLD)
	C(c, 0.5, 0.4, 0.52, GOLD, { grad = { GOLD_LIGHT, GOLD, 0 } })
	R(c, 0.5, 0.28, 0.52, 0.24, GOLD, { grad = { GOLD_LIGHT, GOLD, 0 } })
	T(c, 0.5, 0.38, 0.24, "★", GOLD_DARK)
	R(c, 0.5, 0.7, 0.09, 0.16, GOLD_DARK)
	R(c, 0.5, 0.82, 0.42, 0.1, GOLD, { r = 0.3 })
	R(c, 0.5, 0.89, 0.5, 0.06, GOLD_DARK, { r = 0.3 })
end

D.close = function(c)
	R(c, 0.5, 0.5, 0.12, 0.72, c.Fg, { rot = 45, r = 0.5 })
	R(c, 0.5, 0.5, 0.12, 0.72, c.Fg, { rot = -45, r = 0.5 })
end

D.police = function(c)
	D.shield(c, false)
	T(c, 0.5, 0.47, 0.38, "★", GOLD)
end

D.city = function(c)
	local lit = rgb(255, 214, 110)
	local towers = {
		{ 0.2, 0.64, 0.2, 0.44, rgb(120, 170, 255) },
		{ 0.4, 0.5, 0.2, 0.72, rgb(90, 140, 240) },
		{ 0.6, 0.57, 0.18, 0.58, rgb(140, 190, 255) },
		{ 0.8, 0.68, 0.2, 0.36, rgb(100, 150, 245) },
	}
	R(c, 0.4, 0.1, 0.025, 0.12, c.Fg)
	C(c, 0.4, 0.05, 0.05, RED)
	for _, t in ipairs(towers) do
		R(c, t[1], t[2], t[3], t[4], t[5], { r = 0.08, grad = { WHITE, rgb(150, 170, 220), 90 } })
		local rows = math.floor(t[4] / 0.11)
		for row = 1, rows do
			for col = -1, 1, 2 do
				local on = (row + col + math.floor(t[1] * 10)) % 3 ~= 0
				R(c, t[1] + col * t[3] * 0.22, t[2] - t[4] / 2 + row * 0.1 - 0.02, t[3] * 0.24, 0.045, if on then lit else rgb(40, 60, 110), { t = if on then 0 else 0.3 })
			end
		end
	end
	R(c, 0.5, 0.9, 0.94, 0.05, c.Fg, { r = 0.5 })
end

D.hospital = function(c)
	R(c, 0.5, 0.5, 0.24, 0.72, c.Fg, { r = 0.2 })
	R(c, 0.5, 0.5, 0.72, 0.24, c.Fg, { r = 0.2 })
end

D.bolt = function(c)
	local y = rgb(255, 214, 60)
	R(c, 0.56, 0.3, 0.2, 0.48, y, { rot = 22 })
	R(c, 0.44, 0.7, 0.2, 0.48, y, { rot = 22 })
	R(c, 0.5, 0.5, 0.46, 0.14, y, { rot = -12 })
	R(c, 0.52, 0.34, 0.07, 0.3, WHITE, { rot = 22, t = 0.5 })
end

D.run = function(c)
	local fg = c.Fg
	C(c, 0.6, 0.17, 0.18, fg)
	R(c, 0.52, 0.42, 0.14, 0.34, fg, { rot = 20, r = 0.4 })
	-- arms
	R(c, 0.38, 0.38, 0.08, 0.26, fg, { rot = 70, r = 0.5 })
	R(c, 0.66, 0.44, 0.08, 0.24, fg, { rot = -50, r = 0.5 })
	-- legs, mid-stride
	R(c, 0.38, 0.7, 0.09, 0.32, fg, { rot = 40, r = 0.5 })
	R(c, 0.58, 0.72, 0.09, 0.3, fg, { rot = -25, r = 0.5 })
	R(c, 0.24, 0.84, 0.16, 0.08, fg, { r = 0.5 })
	R(c, 0.68, 0.88, 0.16, 0.08, fg, { r = 0.5 })
	-- speed lines
	for k, y in ipairs({ 0.34, 0.5, 0.66 }) do
		R(c, 0.14, y, 0.16 - k * 0.02, 0.04, fg, { r = 0.5, t = 0.4 })
	end
end

-- food
D.croissant = function(c)
	local g, d = rgb(236, 170, 80), rgb(196, 124, 50)
	R(c, 0.22, 0.6, 0.26, 0.2, d, { rot = -35, r = 0.5 })
	R(c, 0.78, 0.6, 0.26, 0.2, d, { rot = 35, r = 0.5 })
	R(c, 0.34, 0.5, 0.3, 0.3, g, { rot = -20, r = 0.5 })
	R(c, 0.66, 0.5, 0.3, 0.3, g, { rot = 20, r = 0.5 })
	R(c, 0.5, 0.46, 0.34, 0.36, g, { r = 0.5, grad = { rgb(250, 205, 120), g, 90 } })
	R(c, 0.5, 0.46, 0.04, 0.3, d, { t = 0.3 })
	R(c, 0.36, 0.48, 0.03, 0.22, d, { rot = -20, t = 0.4 })
	R(c, 0.64, 0.48, 0.03, 0.22, d, { rot = 20, t = 0.4 })
end
D.donut = function(c)
	C(c, 0.5, 0.52, 0.8, rgb(214, 150, 80))
	C(c, 0.5, 0.49, 0.72, rgb(250, 140, 190))
	C(c, 0.5, 0.5, 0.24, c.Hole)
	for k, p in ipairs({ { 0.3, 0.34 }, { 0.62, 0.26 }, { 0.72, 0.52 }, { 0.36, 0.7 }, { 0.6, 0.72 }, { 0.24, 0.52 } }) do
		R(c, p[1], p[2], 0.1, 0.035, ({ rgb(255, 255, 255), rgb(90, 200, 255), rgb(255, 220, 60) })[k % 3 + 1], { rot = k * 50, r = 0.5 })
	end
end
D.coffee = function(c)
	for _, x in ipairs({ 0.38, 0.5, 0.62 }) do
		R(c, x, 0.16, 0.05, 0.16, c.Fg, { r = 0.5, t = 0.45 })
	end
	O(c, 0.76, 0.56, 0.26, 0.06, rgb(240, 240, 235))
	R(c, 0.46, 0.6, 0.5, 0.5, rgb(245, 245, 240), { r = 0.2 })
	R(c, 0.46, 0.4, 0.44, 0.08, rgb(110, 70, 40), { r = 0.5 })
	R(c, 0.46, 0.62, 0.5, 0.1, rgb(120, 80, 50))
	R(c, 0.46, 0.88, 0.64, 0.06, rgb(210, 210, 205), { r = 0.5 })
end
D.muffin = function(c)
	R(c, 0.5, 0.7, 0.52, 0.36, rgb(240, 240, 250), { r = 0.12 })
	for k = -2, 2 do
		R(c, 0.5 + k * 0.1, 0.7, 0.02, 0.34, rgb(200, 200, 215))
	end
	C(c, 0.5, 0.42, 0.66, rgb(200, 150, 90), { grad = { rgb(230, 180, 110), rgb(190, 130, 70), 90 } })
	for _, p in ipairs({ { 0.38, 0.34 }, { 0.58, 0.3 }, { 0.46, 0.46 }, { 0.66, 0.44 }, { 0.32, 0.5 } }) do
		C(c, p[1], p[2], 0.09, rgb(90, 70, 170))
	end
end
D.burger = function(c)
	clip(c, 0, 0.1, 1, 0.42, function(k)
		C(k, 0.5, 0.42, 0.78, rgb(222, 150, 70), { grad = { rgb(240, 180, 100), rgb(210, 130, 60), 90 } })
	end)
	for _, p in ipairs({ { 0.34, 0.28 }, { 0.5, 0.22 }, { 0.64, 0.3 } }) do
		R(c, p[1], p[2], 0.05, 0.025, rgb(255, 245, 220), { r = 0.5 })
	end
	R(c, 0.5, 0.46, 0.84, 0.08, rgb(90, 190, 70), { r = 0.5 })
	R(c, 0.5, 0.51, 0.76, 0.06, rgb(255, 205, 60), { r = 0.3 })
	R(c, 0.5, 0.6, 0.8, 0.13, rgb(110, 60, 40), { r = 0.5 })
	R(c, 0.5, 0.74, 0.76, 0.14, rgb(222, 150, 70), { r = 0.45 })
end
D.fries = function(c)
	for k = -2, 2 do
		R(c, 0.5 + k * 0.09, 0.34 - (k % 2) * 0.05, 0.08, 0.42, rgb(255, 210, 70), { rot = k * 5, r = 0.2 })
	end
	R(c, 0.5, 0.68, 0.56, 0.44, rgb(230, 50, 60), { r = 0.12 })
	R(c, 0.5, 0.5, 0.56, 0.06, rgb(200, 30, 40), { r = 0.3 })
	C(c, 0.5, 0.68, 0.16, rgb(255, 210, 70))
end
D.milkshake = function(c)
	R(c, 0.6, 0.18, 0.05, 0.3, rgb(240, 70, 90), { rot = 15, r = 0.5 })
	C(c, 0.5, 0.3, 0.3, WHITE)
	C(c, 0.36, 0.34, 0.24, WHITE)
	C(c, 0.64, 0.34, 0.24, WHITE)
	C(c, 0.5, 0.18, 0.1, rgb(220, 40, 60))
	R(c, 0.5, 0.64, 0.46, 0.5, rgb(250, 170, 190), { r = 0.15 })
	R(c, 0.5, 0.64, 0.46, 0.08, WHITE, { t = 0.5 })
end
D.pasta = function(c)
	clip(c, 0, 0.5, 1, 1, function(k)
		C(k, 0.5, 0.5, 0.84, rgb(240, 240, 245))
	end)
	R(c, 0.5, 0.5, 0.84, 0.05, rgb(210, 210, 220), { r = 0.5 })
	C(c, 0.5, 0.44, 0.6, rgb(240, 200, 100))
	for k = 0, 3 do
		O(c, 0.42 + k * 0.05, 0.42 + (k % 2) * 0.04, 0.2, 0.03, rgb(220, 170, 70))
	end
	C(c, 0.4, 0.36, 0.12, rgb(200, 60, 40))
	C(c, 0.58, 0.38, 0.12, rgb(200, 60, 40))
	R(c, 0.5, 0.3, 0.12, 0.06, rgb(80, 170, 60), { rot = 30, r = 0.5 })
end
D.pizza = function(c)
	clip(c, 0.1, 0.12, 0.9, 0.92, function(k)
		R(k, 0.5, 0.2, 0.56, 0.56, rgb(250, 200, 90), { rot = 45 })
	end)
	R(c, 0.5, 0.18, 0.8, 0.12, rgb(210, 140, 60), { r = 0.5 })
	for _, p in ipairs({ { 0.4, 0.34 }, { 0.58, 0.32 }, { 0.5, 0.52 } }) do
		C(c, p[1], p[2], 0.12, rgb(200, 50, 40))
	end
end
D.icecream = function(c)
	clip(c, 0.2, 0.5, 0.8, 0.96, function(k)
		R(k, 0.5, 0.5, 0.42, 0.42, rgb(220, 160, 90), { rot = 45 })
	end)
	R(c, 0.5, 0.56, 0.44, 0.03, rgb(180, 120, 60), { t = 0.3 })
	C(c, 0.5, 0.44, 0.4, rgb(250, 190, 210))
	C(c, 0.5, 0.24, 0.34, rgb(255, 245, 220))
	C(c, 0.5, 0.1, 0.1, rgb(220, 40, 60))
end
D.apple = function(c)
	C(c, 0.38, 0.56, 0.5, rgb(220, 50, 60))
	C(c, 0.62, 0.56, 0.5, rgb(220, 50, 60))
	C(c, 0.5, 0.64, 0.5, rgb(200, 40, 50))
	R(c, 0.5, 0.24, 0.05, 0.16, rgb(110, 70, 40), { rot = 10 })
	R(c, 0.62, 0.22, 0.18, 0.09, rgb(80, 180, 70), { rot = -25, r = 0.5 })
	C(c, 0.36, 0.48, 0.1, WHITE, { t = 0.5 })
end
D.sandwich = function(c)
	R(c, 0.5, 0.36, 0.8, 0.14, rgb(236, 190, 120), { r = 0.4 })
	R(c, 0.5, 0.47, 0.84, 0.07, rgb(90, 190, 70), { r = 0.5 })
	R(c, 0.5, 0.54, 0.78, 0.07, rgb(240, 150, 150), { r = 0.3 })
	R(c, 0.5, 0.6, 0.74, 0.06, rgb(255, 210, 70))
	R(c, 0.5, 0.71, 0.8, 0.14, rgb(236, 190, 120), { r = 0.4 })
end
D.energy = function(c)
	R(c, 0.5, 0.52, 0.44, 0.74, rgb(40, 200, 110), { r = 0.12, grad = { rgb(90, 240, 150), rgb(30, 160, 90), 0 } })
	R(c, 0.5, 0.16, 0.38, 0.06, rgb(200, 205, 215), { r = 0.4 })
	R(c, 0.5, 0.88, 0.38, 0.06, rgb(200, 205, 215), { r = 0.4 })
	R(c, 0.54, 0.44, 0.1, 0.24, WHITE, { rot = 22 })
	R(c, 0.46, 0.62, 0.1, 0.24, WHITE, { rot = 22 })
	R(c, 0.5, 0.53, 0.22, 0.06, WHITE, { rot = -12 })
end

D.briefcase = function(c)
	-- the handle, the case, a clasp and a seam
	R(c, 0.5, 0.26, 0.3, 0.14, c.Fg, { r = 0.3 })
	R(c, 0.5, 0.28, 0.18, 0.07, c.Hole, { r = 0.3 })
	R(c, 0.5, 0.58, 0.8, 0.52, rgb(170, 110, 60), { r = 0.14, grad = { rgb(200, 140, 80), rgb(140, 88, 46), 90 } })
	R(c, 0.5, 0.52, 0.8, 0.05, rgb(110, 70, 36))
	R(c, 0.5, 0.53, 0.14, 0.12, rgb(250, 210, 90), { r = 0.2 })
end

-- names that mean the same icon
local ALIAS = {
	Phone = "phone", Map = "map", People = "people", News = "news", Vote = "vote", Goals = "goals",
	Speech = "mic", Mayor = "mayor", Help = "help", Settings = "settings", Wardrobe = "mask",
	Fists = "fist", Bat = "bat", Hammer = "hammer", Knife = "knife", Hoodie = "hoodie", Disguise = "disguise", SkiMask = "mask",
	["📱"] = "phone", ["🗺️"] = "map", ["👥"] = "people", ["📰"] = "news", ["🗳️"] = "vote", ["🎯"] = "goals",
	["🎤"] = "mic", ["🏛️"] = "mayor", ["❓"] = "help", ["⚙️"] = "settings", ["🥷"] = "mask", ["👊"] = "fist",
	["🏏"] = "bat", ["🔨"] = "hammer", ["🔪"] = "knife", ["🛡️"] = "shield", ["🪙"] = "coin", ["❤️"] = "heart",
	["💬"] = "chat", ["🚨"] = "siren", ["🪪"] = "idcard", ["🛗"] = "elevator", ["🏆"] = "trophy", ["🏙️"] = "city",
	["🧥"] = "hoodie", ["🥸"] = "disguise", ["☀️"] = "sun", ["🌙"] = "moon", ["🌅"] = "sunset", ["🌇"] = "sunset",
	["💰"] = "coin", ["💼"] = "briefcase", Jobs = "briefcase", ["😊"] = "smile", ["🏥"] = "hospital", ["🚓"] = "police",
}
Icons.Alias = ALIAS

local function resolve(name)
	return if D[name] then name else ALIAS[name]
end

function Icons.Has(name)
	return name ~= nil and resolve(name) ~= nil
end

local function holeFor(parent)
	if parent and parent:IsA("GuiObject") and (parent.BackgroundTransparency or 0) < 1 and parent.BackgroundColor3 then
		return parent.BackgroundColor3
	end
	return rgb(24, 27, 41)
end

local function draw(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child.Name == "Ink" then
			child:Destroy()
		end
	end
	local name = resolve(frame:GetAttribute("Icon"))
	local fn = name and D[name]
	if not fn then
		return
	end
	local px = frame:GetAttribute("Px") or 32
	local ctx = context(frame, px, frame:GetAttribute("Fg") or WHITE, frame:GetAttribute("Hole") or rgb(24, 27, 41), frame.ZIndex or 1)
	fn(ctx)
end

-- just the drawing (a transparent square)
function Icons.Glyph(parent, name, px, props)
	props = props or {}
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Icon"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(px, px)
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.Position = props.Position or UDim2.new()
	frame.LayoutOrder = props.LayoutOrder or 0
	frame.ZIndex = props.ZIndex or (if parent and parent:IsA("GuiObject") then parent.ZIndex or 1 else 1)
	frame.Visible = props.Visible ~= false
	frame:SetAttribute("Icon", name)
	frame:SetAttribute("Px", px)
	frame:SetAttribute("Fg", props.Color or WHITE)
	frame:SetAttribute("Hole", props.Hole or holeFor(parent))
	draw(frame)
	frame.Parent = parent
	return frame
end

-- an app icon: a glossy rounded square in `color` with the drawing on it
function Icons.Badge(parent, name, px, color, props)
	props = props or {}
	local badge = Instance.new("Frame")
	badge.Name = props.Name or "Badge"
	badge.BackgroundColor3 = color
	badge.BorderSizePixel = 0
	badge.Size = UDim2.fromOffset(px, px)
	badge.AnchorPoint = props.AnchorPoint or Vector2.zero
	badge.Position = props.Position or UDim2.new()
	badge.LayoutOrder = props.LayoutOrder or 0
	badge.ZIndex = props.ZIndex or (if parent and parent:IsA("GuiObject") then parent.ZIndex or 1 else 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(props.Round or 0.26, 0)
	corner.Parent = badge
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(color:Lerp(WHITE, 0.28), shade(color, 0.12))
	g.Rotation = 90
	g.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Color = color:Lerp(WHITE, 0.45)
	stroke.Thickness = math.max(1, px / 40)
	stroke.Transparency = 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = badge
	-- a soft shine across the top
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.9
	shine.BorderSizePixel = 0
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.fromScale(0.5, 0.05)
	shine.Size = UDim2.fromScale(0.84, 0.34)
	shine.ZIndex = (badge.ZIndex or 1) + 1
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.4, 0)
	sc.Parent = shine
	shine.Parent = badge
	local glyph = Icons.Glyph(badge, name, math.floor(px * (props.Fill or 0.66)), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Color = props.Color, Hole = props.Hole or color, ZIndex = (badge.ZIndex or 1) + 2 })
	badge.Parent = parent
	return badge, glyph
end

-- swap the drawing (for icons that change: the sky, the weapon in your hand)
function Icons.Set(icon, name, color)
	if icon:GetAttribute("Icon") == name and (color == nil or icon:GetAttribute("Fg") == color) then
		return
	end
	icon:SetAttribute("Icon", name)
	if color then
		icon:SetAttribute("Fg", color)
	end
	draw(icon)
end

Icons.Names = {}
for name in pairs(D) do
	table.insert(Icons.Names, name)
end
table.sort(Icons.Names)

return Icons
