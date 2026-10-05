-- UI: the game's design system - "fight night broadcast".
-- Near-black glass panels, championship gold and fight red accents, a condensed display face
-- (Oswald) for titles and every number, Gotham for body copy, a 4 px spacing grid, tight corners,
-- soft stacked shadows and quick ease-out motion. Every widget the menus are built from lives here
-- (windows, cards, buttons, bars, sliders, a colour wheel, toggles, cyclers, tabs, toasts, chips,
-- badges, segmented meters, stat tiles, vector icons) plus responsive scaling: UI.MountRoot gives
-- a ScreenGui one scaled root frame (UIScale) so phones, tablets and desktops get the same layout.
-- Built-in fonts only (Font.new on rbxasset families, resolved inside pcall).
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

------------------------------------------------------------------------
-- Tokens
------------------------------------------------------------------------
UI.Theme = {
	-- surfaces
	bg = rgb(10, 12, 17), -- window base (deep ink with a cold tint)
	panel = rgb(20, 23, 31), -- cards
	panel2 = rgb(32, 37, 49), -- raised: inactive buttons, tracks, rows
	line = rgb(58, 65, 82), -- dividers and quiet strokes
	ink = rgb(5, 6, 9),
	-- type
	text = rgb(242, 244, 248),
	sub = rgb(150, 158, 176),
	dim = rgb(98, 106, 124),
	white = rgb(255, 255, 255),
	-- accents
	gold = rgb(247, 196, 66), -- championship gold: primary actions, titles, the player
	goldDeep = rgb(205, 140, 30),
	red = rgb(234, 48, 56), -- fight red: danger, the opponent, live
	redDeep = rgb(150, 18, 30),
	blue = rgb(58, 142, 255), -- info, stamina, the blue corner
	blueDeep = rgb(24, 80, 190),
	green = rgb(50, 214, 126), -- health, success
	greenDeep = rgb(20, 140, 78),
	orange = rgb(255, 148, 48), -- warnings, body damage
	purple = rgb(176, 122, 255), -- concussion
	cyan = rgb(70, 214, 232), -- hydration / tech readouts
	-- legacy font enums (every module still passes these)
	font = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBlack,
	semi = Enum.Font.GothamBold,
}
local T = UI.Theme

-- spacing grid (4 px) and corner radii
UI.S = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32, xxxl = 48 }
UI.R = { sm = 4, md = 6, lg = 10, xl = 14 }

-- typography: Font objects for the built-in families (nil when Font.new is unavailable)
local function face(family, weight)
	local ok, f = pcall(function()
		return Font.new("rbxasset://fonts/families/" .. family .. ".json", weight or Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	end)
	return ok and f or nil
end
UI.Fonts = {
	display = face("Oswald", Enum.FontWeight.Bold), -- titles, the logo, big labels
	displayMed = face("Oswald", Enum.FontWeight.SemiBold), -- buttons, tabs, section heads
	number = face("Oswald", Enum.FontWeight.Bold), -- stats, clocks, records, money
	heading = face("GothamSSm", Enum.FontWeight.Heavy),
	label = face("GothamSSm", Enum.FontWeight.Bold),
	body = face("GothamSSm", Enum.FontWeight.Medium),
	mono = face("RobotoMono", Enum.FontWeight.Medium),
}
local FONT_FALLBACK = {
	display = Enum.Font.Oswald, displayMed = Enum.Font.Oswald, number = Enum.Font.Oswald, heading = Enum.Font.GothamBlack,
	label = Enum.Font.GothamBold, body = Enum.Font.GothamMedium, mono = Enum.Font.RobotoMono,
}

-- motion
UI.Motion = {
	fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	base = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	slow = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	spring = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	linear = TweenInfo.new(1, Enum.EasingStyle.Linear),
}

function UI.Tween(inst, props, info)
	if type(info) == "string" then
		info = UI.Motion[info]
	elseif type(info) == "number" then
		info = TweenInfo.new(info, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	local tw = TweenService:Create(inst, info or UI.Motion.base, props)
	tw:Play()
	return tw
end

-- a colour a bit lighter / darker (k > 0 toward white, k < 0 toward black)
function UI.Shade(c, k)
	if k >= 0 then
		return c:Lerp(Color3.new(1, 1, 1), k)
	end
	return c:Lerp(Color3.new(0, 0, 0), -k)
end

------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------
function UI.New(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.Corner(inst, r)
	UI.New("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = inst })
	return inst
end

function UI.Stroke(inst, color, thickness, transparency)
	UI.New("UIStroke", { Color = color or T.line, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst })
	return inst
end

function UI.Pad(inst, p, p2)
	UI.New("UIPadding", {
		PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p),
		PaddingLeft = UDim.new(0, p2 or p), PaddingRight = UDim.new(0, p2 or p), Parent = inst,
	})
	return inst
end

function UI.List(inst, pad, horizontal, align)
	UI.New("UIListLayout", {
		Padding = UDim.new(0, pad or 6),
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = horizontal and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top,
		Parent = inst,
	})
	return inst
end

function UI.Grid(inst, cellW, cellH, pad)
	UI.New("UIGridLayout", {
		CellSize = typeof(cellW) == "UDim2" and cellW or UDim2.fromOffset(cellW, cellH),
		CellPadding = UDim2.fromOffset(pad or 6, pad or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inst,
	})
	return inst
end

-- a UIGradient. colors: Color3 | { Color3, ... } (evenly spaced) | ColorSequence;
-- transparency: number | { t0, t1, ... } | NumberSequence; opts.type = "Radial" | "Elliptical" (new engine
-- feature, set inside pcall so an older client keeps the linear gradient)
local function colorSeq(c)
	if typeof(c) == "ColorSequence" then
		return c
	elseif typeof(c) == "Color3" then
		return ColorSequence.new(c)
	end
	local keys = {}
	for i, col in ipairs(c) do
		keys[i] = ColorSequenceKeypoint.new(#c == 1 and 0 or (i - 1) / (#c - 1), col)
	end
	if #keys == 1 then
		return ColorSequence.new(keys[1].Value)
	end
	return ColorSequence.new(keys)
end
local function numberSeq(n)
	if typeof(n) == "NumberSequence" then
		return n
	elseif type(n) == "number" then
		return NumberSequence.new(n)
	end
	local keys = {}
	for i, v in ipairs(n) do
		keys[i] = NumberSequenceKeypoint.new(#n == 1 and 0 or (i - 1) / (#n - 1), v)
	end
	if #keys == 1 then
		return NumberSequence.new(keys[1].Value)
	end
	return NumberSequence.new(keys)
end
UI.ColorSeq, UI.NumberSeq = colorSeq, numberSeq

function UI.Gradient(inst, colors, rotation, transparency, opts)
	local g = UI.New("UIGradient", { Color = colorSeq(colors or Color3.new(1, 1, 1)), Rotation = rotation or 0, Parent = inst })
	if transparency ~= nil then
		g.Transparency = numberSeq(transparency)
	end
	if opts and opts.type then
		pcall(function()
			g.Type = Enum.GradientType[opts.type]
		end)
	end
	if opts and opts.offset then
		g.Offset = opts.offset
	end
	return g
end

------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------
-- resolves a design font role ("display", "number", ...) onto a text object
function UI.SetFace(obj, role)
	local f = UI.Fonts[role]
	if f then
		local ok = pcall(function()
			obj.FontFace = f
		end)
		if ok then
			return
		end
	end
	obj.Font = FONT_FALLBACK[role] or T.font
end

-- applies props.Face (a design role) or the typographic rule "heavy and big = display face"
local function applyFace(obj, props, role)
	if role then
		UI.SetFace(obj, role)
	end
end

function UI.Frame(parent, props)
	props = props or {}
	props.Parent = parent
	if props.BackgroundColor3 == nil then
		props.BackgroundColor3 = T.panel
	end
	props.BorderSizePixel = 0
	return UI.New("Frame", props)
end

local function textRole(props)
	local role = props.Face
	props.Face = nil
	if role then
		props.Font = nil
		return role
	end
	-- the type hierarchy: a heavy face at heading sizes is a title -> the condensed display face
	if props.Font == T.bold and (props.TextSize or 16) >= 18 and not props.TextScaled then
		props.Font = nil
		return "display"
	end
	return nil
end

function UI.Text(parent, text, props)
	props = props or {}
	props.Parent = parent
	props.Text = text
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.TextColor3 = props.TextColor3 or T.text
	local role = textRole(props)
	if not role then
		props.Font = props.Font or T.font
	end
	props.TextSize = props.TextSize or 16
	props.TextWrapped = props.TextWrapped ~= false
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.RichText = props.RichText or false
	if props.Size == nil then
		-- full-width label that grows downward when its text wraps
		props.Size = UDim2.new(1, 0, 0, (props.TextSize or 16) + 6)
		props.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.Y
	end
	local label = UI.New("TextLabel", props)
	applyFace(label, props, role)
	return label
end

-- a display-face label (titles / numbers); props as UI.Text
function UI.Title(parent, text, props)
	props = props or {}
	props.Face = props.Face or "display"
	props.TextSize = props.TextSize or 32
	props.TextWrapped = props.TextWrapped or false
	return UI.Text(parent, text, props)
end

------------------------------------------------------------------------
-- Icons: tiny vector glyphs drawn from frames (no image assets)
------------------------------------------------------------------------
local function bar(parent, w, h, x, y, rot, color, z)
	local f = UI.New("Frame", {
		Name = "Stroke", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, y, 0), Size = UDim2.new(w, 0, 0, h),
		Rotation = rot or 0, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z or 1, Parent = parent,
	})
	UI.Corner(f, math.ceil(h / 2))
	return f
end

-- kind: close, left, right, up, down, check, plus, minus, play, menu, lock, dot, star, bolt
function UI.Icon(parent, kind, size, color, props)
	size = size or 16
	color = color or T.text
	local th = math.max(2, math.floor(size / 7 + 0.5))
	local f = UI.New("Frame", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), BorderSizePixel = 0, Parent = parent })
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local z = f.ZIndex
	if kind == "close" then
		bar(f, 1.1, th, 0.5, 0.5, 45, color, z)
		bar(f, 1.1, th, 0.5, 0.5, -45, color, z)
	elseif kind == "left" or kind == "right" or kind == "up" or kind == "down" then
		local base = ({ right = 0, down = 90, left = 180, up = 270 })[kind]
		local a = math.rad(base)
		-- two strokes ending at the tip (each stroke's direction points at the tip)
		for _, s in ipairs({ -1, 1 }) do
			local ang = base + s * 45
			local r = math.rad(ang)
			local cx, cy = 0.5 + math.cos(a) * 0.2 - math.cos(r) * 0.28, 0.5 + math.sin(a) * 0.2 - math.sin(r) * 0.28
			bar(f, 0.62, th, cx, cy, ang, color, z)
		end
	elseif kind == "check" then
		bar(f, 0.36, th, 0.31, 0.61, 45, color, z)
		bar(f, 0.64, th, 0.61, 0.5, -48, color, z)
	elseif kind == "plus" then
		bar(f, 0.8, th, 0.5, 0.5, 0, color, z)
		bar(f, 0.8, th, 0.5, 0.5, 90, color, z)
	elseif kind == "minus" then
		bar(f, 0.8, th, 0.5, 0.5, 0, color, z)
	elseif kind == "menu" then
		for i, y in ipairs({ 0.25, 0.5, 0.75 }) do
			bar(f, i == 2 and 0.62 or 0.86, th, i == 2 and 0.43 or 0.5, y, 0, color, z)
		end
	elseif kind == "play" then
		-- a right-pointing triangle from three strokes
		bar(f, 0.62, th, 0.53, 0.35, 31, color, z)
		bar(f, 0.62, th, 0.53, 0.65, -31, color, z)
		bar(f, 0.64, th, 0.28, 0.5, 90, color, z)
	elseif kind == "lock" then
		local body = UI.New("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.95), Size = UDim2.fromScale(0.74, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z, Parent = f })
		UI.Corner(body, 2)
		local shackle = UI.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.05), Size = UDim2.fromScale(0.5, 0.56), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z, Parent = f })
		UI.Corner(shackle, size)
		UI.Stroke(shackle, color, th)
	elseif kind == "star" then
		for i = 0, 2 do
			bar(f, 0.9, th, 0.5, 0.52, i * 60 + 90, color, z)
		end
	elseif kind == "bolt" then
		bar(f, 0.5, th, 0.56, 0.3, 60, color, z)
		bar(f, 0.5, th, 0.5, 0.5, 0, color, z)
		bar(f, 0.5, th, 0.44, 0.7, 60, color, z)
	else -- dot
		local d = UI.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z, Parent = f })
		UI.Corner(d, size)
	end
	return f
end

------------------------------------------------------------------------
-- Interaction: hover / press feedback for any GuiButton
------------------------------------------------------------------------
-- a white sheen that lifts on hover and a quick scale-down on press; hover does not touch
-- BackgroundColor3, so callers can keep recolouring selected / unselected buttons freely
function UI.Hover(btn, opts)
	opts = opts or {}
	local radius = opts.radius
	if radius == nil then
		local c = btn:FindFirstChildOfClass("UICorner")
		radius = c and c.CornerRadius.Offset or 6
	end
	local overlay = UI.New("Frame", {
		Name = "Hover", BackgroundColor3 = opts.color or Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), ZIndex = btn.ZIndex, Active = false, Parent = btn,
	})
	if radius > 0 then
		UI.Corner(overlay, radius)
	end
	local scale = btn:FindFirstChild("Press")
	if not scale then
		scale = UI.New("UIScale", { Name = "Press", Scale = 1, Parent = btn })
	end
	local hoverT = opts.amount or 0.9
	local hovering = false
	btn.MouseEnter:Connect(function()
		hovering = true
		UI.Tween(overlay, { BackgroundTransparency = hoverT }, UI.Motion.fast)
	end)
	btn.MouseLeave:Connect(function()
		hovering = false
		UI.Tween(overlay, { BackgroundTransparency = 1 }, UI.Motion.fast)
		UI.Tween(scale, { Scale = 1 }, UI.Motion.fast)
	end)
	btn.MouseButton1Down:Connect(function()
		UI.Tween(scale, { Scale = opts.press or 0.96 }, UI.Motion.fast)
	end)
	btn.MouseButton1Up:Connect(function()
		UI.Tween(scale, { Scale = 1 }, UI.Motion.spring)
		if not hovering then
			UI.Tween(overlay, { BackgroundTransparency = 1 }, UI.Motion.fast)
		end
	end)
	return overlay
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
-- variant from the colour callers already pass: gold = primary, red = danger / fight, green =
-- confirm, blue = info, anything else = secondary glass. props.variant overrides.
local function variantOf(props)
	if props.variant then
		return props.variant
	end
	local c = props.BackgroundColor3
	if c == T.gold then
		return "primary"
	elseif c == T.red then
		return "danger"
	elseif c == T.green then
		return "success"
	elseif c == T.blue then
		return "info"
	elseif c == T.orange then
		return "warn"
	end
	return "secondary"
end
local VARIANT_TEXT = { primary = T.ink, success = T.ink, warn = T.ink }

function UI.Button(parent, text, props, onClick)
	props = props or {}
	local variant = variantOf(props)
	props.variant = nil
	props.Parent = parent
	props.Text = text
	props.AutoButtonColor = false
	props.BackgroundColor3 = props.BackgroundColor3 or T.panel2
	props.TextColor3 = props.TextColor3 or VARIANT_TEXT[variant] or T.text
	local role = textRole(props)
	local explicitFont = props.Font ~= nil
	props.TextSize = props.TextSize or 16
	if not explicitFont and not role then
		-- buttons speak in the condensed display face (a touch larger: it is narrow)
		role = "displayMed"
		props.TextSize += 2
	end
	props.Font = props.Font or T.bold
	props.TextWrapped = true
	props.Size = props.Size or UDim2.new(0, 160, 0, 38)
	props.BorderSizePixel = 0
	local b = UI.New("TextButton", props)
	applyFace(b, props, role)
	UI.Corner(b, UI.R.md)
	if b.BackgroundTransparency < 0.98 then
		if variant == "secondary" then
			UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.9, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
			UI.Gradient(b, { Color3.new(1, 1, 1), Color3.fromRGB(205, 208, 216) }, 90)
		else
			-- a lit top edge on the solid colours
			UI.Gradient(b, { Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196) }, 90)
		end
		UI.Hover(b)
	end
	if onClick then
		b.MouseButton1Click:Connect(onClick)
	end
	return b
end

function UI.Scroll(parent, props)
	props = props or {}
	props.Parent = parent
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.ScrollBarThickness = props.ScrollBarThickness or 4
	props.ScrollBarImageColor3 = T.sub
	props.ScrollBarImageTransparency = 0.45
	props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	props.CanvasSize = UDim2.new()
	props.ScrollingDirection = props.ScrollingDirection or Enum.ScrollingDirection.Y
	props.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	return UI.New("ScrollingFrame", props)
end

------------------------------------------------------------------------
-- Bars & meters
------------------------------------------------------------------------
-- horizontal bar; returns frame and setter(fraction, color?)
function UI.Bar(parent, props, color)
	local bg = UI.Frame(parent, props)
	bg.BackgroundColor3 = T.ink
	bg.BackgroundTransparency = 0.15
	local h = bg.Size.Y.Offset
	local r = h > 0 and math.min(4, math.ceil(h / 2)) or 3
	UI.Corner(bg, r)
	local fill = UI.Frame(bg, { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color or T.green })
	UI.Corner(fill, r)
	UI.Gradient(fill, { Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190) }, 90)
	local function set(f, c)
		fill.Size = UDim2.fromScale(math.clamp(f, 0, 1), 1)
		if c then
			fill.BackgroundColor3 = c
		end
	end
	return bg, set, fill
end

-- segmented meter (n blocks, broadcast style); returns frame and setter(fraction, color?)
function UI.Segments(parent, n, props, color)
	local f = UI.Frame(parent, props)
	f.BackgroundTransparency = 1
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	local segs = {}
	for i = 1, n do
		local s = UI.Frame(f, { Size = UDim2.new(1 / n, -2 * (n - 1) / n, 1, 0), BackgroundColor3 = T.panel2, LayoutOrder = i })
		UI.Corner(s, 2)
		segs[i] = s
	end
	local cur = color or T.gold
	local function set(frac, c)
		cur = c or cur
		local lit = frac * n
		for i, s in ipairs(segs) do
			local k = math.clamp(lit - (i - 1), 0, 1)
			s.BackgroundColor3 = k > 0 and cur or T.panel2
			s.BackgroundTransparency = k > 0 and (1 - (0.35 + 0.65 * k)) or 0
		end
	end
	return f, set
end

-- label + bar + value text in one row
function UI.StatRow(parent, label, value, max, color, valueText)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 })
	UI.Text(f, label, { Size = UDim2.new(0.34, 0, 1, 0), TextSize = 13, Font = T.semi, TextColor3 = T.sub, AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
	local _, set = UI.Bar(f, { Position = UDim2.new(0.34, 0, 0.5, -4), Size = UDim2.new(0.5, 0, 0, 8) }, color)
	set((value or 0) / (max or 100))
	UI.Text(f, valueText or tostring(math.floor(value or 0)), { Face = "number", Position = UDim2.new(0.86, 0, 0, 0), Size = UDim2.new(0.14, 0, 1, 0), TextSize = 16, AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	return f, set
end

-- a big number over a small caption (stat tile)
function UI.Stat(parent, value, caption, props)
	props = props or {}
	local f = UI.Frame(parent, { Size = props.Size or UDim2.fromOffset(110, 64), BackgroundColor3 = props.color or T.panel2, BackgroundTransparency = props.transparency or 0.25, LayoutOrder = props.order or 0 })
	UI.Corner(f, UI.R.md)
	local v = UI.Text(f, tostring(value), { Face = "number", TextSize = props.valueSize or 28, TextColor3 = props.valueColor or T.text, TextXAlignment = props.align or Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0.62, -6), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextScaled = props.scaled == true })
	if props.scaled then
		UI.New("UITextSizeConstraint", { MaxTextSize = props.valueSize or 28, MinTextSize = 10, Parent = v })
	end
	local c = UI.Text(f, string.upper(caption or ""), { Font = T.semi, TextSize = 11, TextColor3 = T.sub, TextXAlignment = props.align or Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 12, 0.62, 0), Size = UDim2.new(1, -24, 0.38, -6), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	return f, v, c
end

-- a small pill: uppercase label on a tinted background (status chips, tags)
function UI.Chip(parent, text, color, props)
	props = props or {}
	color = color or T.gold
	local f = UI.Frame(parent, {
		Size = props.Size or UDim2.fromOffset(0, props.h or 22), AutomaticSize = props.Size and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		BackgroundColor3 = color, BackgroundTransparency = props.solid and 0 or 0.82, LayoutOrder = props.order or 0, Name = props.Name or "Chip",
	})
	if props.Position then
		f.Position = props.Position
	end
	if props.AnchorPoint then
		f.AnchorPoint = props.AnchorPoint
	end
	UI.Corner(f, props.radius or UI.R.sm)
	if not props.solid then
		UI.Stroke(f, color, 1, 0.55)
	end
	local t = UI.Text(f, string.upper(text), { Font = T.semi, TextSize = props.TextSize or 11, TextColor3 = props.solid and (props.textColor or T.ink) or color, Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	UI.Pad(t, 0, 8)
	return f, t
end
UI.Badge = function(parent, text, color, props)
	props = props or {}
	props.solid = true
	return UI.Chip(parent, text, color, props)
end

-- a thin divider line (fades at both ends)
function UI.Divider(parent, props)
	props = props or {}
	local d = UI.Frame(parent, { Name = "Divider", Size = props.Size or UDim2.new(1, 0, 0, 1), BackgroundColor3 = props.color or Color3.new(1, 1, 1), BackgroundTransparency = 0, LayoutOrder = props.order or 0 })
	if props.Position then
		d.Position = props.Position
	end
	UI.Gradient(d, Color3.new(1, 1, 1), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, props.alpha or 0.88), NumberSequenceKeypoint.new(0.85, props.alpha or 0.88), NumberSequenceKeypoint.new(1, 1),
	}))
	return d
end

-- an eyebrow label: gold tick + small uppercase caption (section kickers)
function UI.Kicker(parent, text, color, props)
	props = props or {}
	local f = UI.Frame(parent, { Name = "Kicker", BackgroundTransparency = 1, Size = props.Size or UDim2.new(1, 0, 0, 18), LayoutOrder = props.order or 0 })
	if props.Position then
		f.Position = props.Position
	end
	UI.Frame(f, { Size = UDim2.fromOffset(3, 12), Position = UDim2.new(0, 0, 0.5, -6), BackgroundColor3 = color or T.gold })
	UI.Text(f, string.upper(text), { Font = T.semi, TextSize = props.TextSize or 12, TextColor3 = color or T.gold, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -10, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	return f
end

-- glass styling for an existing frame: dark translucent body, lit top edge, hairline stroke
function UI.Glass(frame, opts)
	opts = opts or {}
	frame.BackgroundColor3 = opts.color or T.bg
	frame.BackgroundTransparency = opts.transparency or 0.08
	frame.BorderSizePixel = 0
	if opts.radius ~= false then
		UI.Corner(frame, opts.radius or UI.R.lg)
	end
	UI.Gradient(frame, { Color3.new(1, 1, 1), Color3.fromRGB(176, 180, 190) }, 90)
	UI.New("UIStroke", { Color = opts.stroke or Color3.new(1, 1, 1), Transparency = opts.strokeT or 0.88, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })
	return frame
end

-- soft shadow layers (stacked translucent frames) inside `holder`, behind a child of the same size
function UI.Shadow(holder, radius, strength)
	strength = strength or 1
	for i, spec in ipairs({ { 3, 0.82 }, { 8, 0.9 }, { 16, 0.95 } }) do
		local grow = spec[1]
		local s = UI.Frame(holder, {
			Name = "Shadow" .. i, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1 - (1 - spec[2]) * strength,
			Position = UDim2.new(0, -grow, 0, -grow + math.floor(grow / 2)), Size = UDim2.new(1, grow * 2, 1, grow * 2), ZIndex = holder.ZIndex,
		})
		UI.Corner(s, (radius or 10) + grow)
	end
end

function UI.Clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if not (c:IsA("UIListLayout") or c:IsA("UIPadding") or c:IsA("UIGridLayout") or c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UISizeConstraint") or c:IsA("UIGradient") or c:IsA("UIScale")) then
			c:Destroy()
		end
	end
end

------------------------------------------------------------------------
-- Responsive scaling
------------------------------------------------------------------------
-- design canvas = 1600 x 900; phones (short landscape screens) keep text readable with a higher floor
UI.DesignSize = Vector2.new(1600, 900)
UI.UserScale = 1
function UI.ScaleFor(w, h, userScale)
	w, h = tonumber(w) or 1600, tonumber(h) or 900
	if w <= 0 or h <= 0 then
		return 1
	end
	local s = math.min(w / UI.DesignSize.X, h / UI.DesignSize.Y)
	local floor = h <= 480 and 0.78 or 0.7
	s = math.clamp(s, floor, 1.45)
	return s * math.clamp(tonumber(userScale) or 1, 0.75, 1.3)
end

local mounted = {} -- [root] = { gui, scale }
local function applyScale(root, info)
	local gui = info.gui
	local abs = gui.AbsoluteSize
	if abs.X <= 1 or abs.Y <= 1 then
		local cam = workspace.CurrentCamera
		abs = cam and cam.ViewportSize or Vector2.new(1600, 900)
	end
	local s = UI.ScaleFor(abs.X, abs.Y, UI.UserScale)
	info.scale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
	root:SetAttribute("UIScale", s)
end

-- gives a ScreenGui one scaled root frame; everything goes inside it (returns the root)
function UI.MountRoot(gui, name)
	local root = UI.New("Frame", { Name = name or "Root", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = gui })
	local info = { gui = gui, scale = UI.New("UIScale", { Name = "RootScale", Parent = root }) }
	mounted[root] = info
	applyScale(root, info)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if root.Parent then
			applyScale(root, info)
		end
	end)
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if root.Parent then
				applyScale(root, info)
			end
		end)
	end
	root.Destroying:Connect(function()
		mounted[root] = nil
	end)
	return root
end

-- the Settings "UI scale" slider
function UI.SetUserScale(k)
	UI.UserScale = math.clamp(tonumber(k) or 1, 0.75, 1.3)
	for root, info in pairs(mounted) do
		if root.Parent then
			applyScale(root, info)
		end
	end
end

-- the scale of the root an object lives under (screen px per design px)
function UI.ScaleOf(obj)
	local root = obj
	while root and not mounted[root] do
		root = root.Parent
	end
	return root and mounted[root].scale.Scale or 1
end

-- the design-pixel size of the area an object lays out in (its root's canvas)
function UI.CanvasSize(obj)
	local root = obj
	while root and not mounted[root] do
		root = root.Parent
	end
	local s = root and mounted[root].scale.Scale or 1
	local screen = root and mounted[root].gui or obj:FindFirstAncestorWhichIsA("LayerCollector")
	local abs = screen and screen.AbsoluteSize or Vector2.zero
	if abs.X < 2 or abs.Y < 2 then
		local cam = workspace.CurrentCamera
		abs = cam and cam.ViewportSize or Vector2.new(1600, 900)
	end
	return Vector2.new(abs.X / s, abs.Y / s)
end

-- the 3D world softly blurred behind modal windows (ref-counted; GUI stays sharp)
local backdrop = { n = 0, fx = nil }
function UI.Backdrop(on)
	backdrop.n = math.max(0, backdrop.n + (on and 1 or -1))
	local cam = workspace.CurrentCamera
	if backdrop.n > 0 then
		if not (backdrop.fx and backdrop.fx.Parent) and cam then
			backdrop.fx = UI.New("BlurEffect", { Name = "UIBackdropBlur", Size = 0, Parent = cam })
		end
		if backdrop.fx then
			UI.Tween(backdrop.fx, { Size = 14 }, UI.Motion.base)
		end
	elseif backdrop.fx then
		local fx = backdrop.fx
		backdrop.fx = nil
		fx:Destroy()
	end
end

------------------------------------------------------------------------
-- Windows & cards
------------------------------------------------------------------------
-- returns shade, win, body (scrolling list area) ; opts = { side = "left"|"right", noShade, onClose,
-- scroll = false, footer = px, z, kicker = "SMALL CAPTION ABOVE THE TITLE" }
function UI.Window(gui, name, w, h, title, opts)
	opts = opts or {}
	local old = gui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local z = opts.z or 10
	local shade = UI.Frame(gui, { Name = name, Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.ink, BackgroundTransparency = 1, ZIndex = z })
	if opts.noShade then
		shade.Active = false
	else
		shade.Active = true
		UI.Tween(shade, { BackgroundTransparency = 0.38 }, UI.Motion.base)
		UI.Backdrop(true)
		shade.Destroying:Connect(function()
			UI.Backdrop(false)
		end)
	end
	-- holder = the window's geometry; shadow layers and the panel live inside it
	local holder = UI.Frame(shade, { Name = "Holder", BackgroundTransparency = 1, Size = UDim2.new(0.96, 0, 0.92, 0), ZIndex = z })
	if opts.side == "left" then
		holder.AnchorPoint = Vector2.new(0, 0.5)
		holder.Position = UDim2.new(0, 24, 0.5, 0)
		holder.Size = UDim2.new(0.46, 0, 0.92, 0)
	elseif opts.side == "right" then
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -24, 0.5, 0)
		holder.Size = UDim2.new(0.42, 0, 0.92, 0)
	else
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
	end
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(w, h), MinSize = Vector2.new(math.min(w, 300), math.min(h, 220)), Parent = holder })
	UI.Shadow(holder, UI.R.xl, 1)
	local win = UI.Frame(holder, { Name = "Win", BackgroundColor3 = T.bg, Size = UDim2.fromScale(1, 1), ZIndex = z })
	win.Active = true
	UI.Glass(win, { transparency = opts.noShade and 0.06 or 0.03, radius = UI.R.xl })
	-- broadcast accent: a thin gold line glowing along the top edge
	local accent = UI.Frame(win, { Name = "Accent", Position = UDim2.new(0, 28, 0, 0), Size = UDim2.new(1, -56, 0, 2), BackgroundColor3 = opts.accent or T.gold, ZIndex = z })
	UI.Gradient(accent, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.15), NumberSequenceKeypoint.new(0.8, 0.15), NumberSequenceKeypoint.new(1, 1) }))
	-- short screens (phones in landscape) get a compact header
	local short = UI.CanvasSize(gui).Y < 560
	local top = 16
	if title then
		local kick = opts.kicker and not short
		if kick then
			UI.Text(win, string.upper(opts.kicker), { Name = "Kicker", Font = T.semi, TextSize = 12, TextColor3 = opts.accent or T.gold, Position = UDim2.fromOffset(40, 14), Size = UDim2.new(1, -120, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		end
		local ty = kick and 26 or (short and 8 or 14)
		local ts = short and 26 or 32
		UI.Frame(win, { Name = "TitleTick", Position = UDim2.fromOffset(24, ty + math.floor(ts * 0.22)), Size = UDim2.fromOffset(4, math.floor(ts * 0.75)), BackgroundColor3 = opts.accent or T.gold })
		UI.Text(win, string.upper(title), { Name = "Title", Face = "display", TextSize = ts, TextColor3 = T.text, Position = UDim2.fromOffset(40, ty), Size = UDim2.new(1, -110, 0, ts + 6),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		top = ty + ts + (short and 14 or 20)
		UI.Divider(win, { Position = UDim2.new(0, 16, 0, top - (short and 6 or 8)), Size = UDim2.new(1, -32, 0, 1) })
	end
	if opts.onClose then
		local cs = short and 32 or 38
		local close = UI.Button(win, "", { Name = "Close", Size = UDim2.fromOffset(cs, cs), Position = UDim2.new(1, -(cs + 14), 0, short and 8 or 14), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.2 }, function()
			opts.onClose()
		end)
		UI.Icon(close, "close", 14, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	end
	local body
	local bottom = opts.footer and (opts.footer + 8) or 16
	if opts.scroll ~= false then
		body = UI.Scroll(win, { Name = "Body", Position = UDim2.fromOffset(20, top), Size = UDim2.new(1, -40, 1, -(top + bottom)) })
		UI.List(body, 10)
		UI.Pad(body, 2, 4)
	else
		body = UI.Frame(win, { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, top), Size = UDim2.new(1, -40, 1, -(top + bottom)) })
	end
	-- opening motion: the panel rises and settles
	local pop = UI.New("UIScale", { Name = "Open", Scale = 0.965, Parent = holder })
	UI.Tween(pop, { Scale = 1 }, UI.Motion.base)
	return shade, win, body
end

function UI.Card(parent, props)
	props = props or {}
	local f = UI.Frame(parent, { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = props.color or T.panel, BackgroundTransparency = props.transparency or 0.05, LayoutOrder = props.order or 0 })
	UI.Corner(f, UI.R.lg)
	UI.Pad(f, props.pad or 14)
	UI.List(f, props.gap or 6)
	if props.stroke then
		-- highlighted card: tinted stroke plus a glow of the accent fading from the left edge
		UI.Stroke(f, props.stroke, 1.5, 0.3)
		f.BackgroundColor3 = (props.color or T.panel):Lerp(props.stroke, 0.16)
		UI.Gradient(f, { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150) }, 0)
	else
		UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.93, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
	end
	return f
end

function UI.Line(parent, text, props)
	props = props or {}
	props.AutomaticSize = Enum.AutomaticSize.Y
	props.Size = props.Size or UDim2.new(1, 0, 0, 0)
	return UI.Text(parent, text, props)
end

-- section header: display face, gold tick (returns the label)
function UI.Header(parent, text, color)
	local f = UI.Frame(parent, { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34) })
	UI.Frame(f, { Size = UDim2.fromOffset(3, 16), Position = UDim2.new(0, 0, 0, 13), BackgroundColor3 = color or T.gold })
	local t = UI.Text(f, string.upper(text), { Face = "displayMed", TextSize = 20, TextColor3 = color or T.text, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -12, 0, 28),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	return t
end

function UI.Row(parent, h)
	local f = UI.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h or 38) })
	UI.List(f, 8, true)
	return f
end

------------------------------------------------------------------------
-- Inputs
------------------------------------------------------------------------
local function dragTracker(target, onPos)
	local dragging = false
	local function update(input)
		onPos(Vector2.new(input.Position.X, input.Position.Y))
	end
	target.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			update(input)
		end
	end)
	local c1 = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	target.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
end
UI.DragTracker = dragTracker

-- the shared row every input sits in: label left, control right
local function inputRow(parent, label, h)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, h or 44), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.45 })
	UI.Corner(f, UI.R.md)
	UI.Text(f, label, { Name = "Label", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.36, -14, 1, 0), TextColor3 = T.sub, TextSize = 14, Font = T.semi,
		AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd })
	return f
end

-- slider row: returns frame, setValue(v)
function UI.Slider(parent, label, min, max, value, step, onChange, fmt)
	local f = inputRow(parent, label)
	local track = UI.Frame(f, { Name = "Track", Position = UDim2.new(0.36, 0, 0.5, -2), Size = UDim2.new(0.5, -18, 0, 4), BackgroundColor3 = T.ink, BackgroundTransparency = 0.1, Active = true })
	UI.Corner(track, 2)
	local fill = UI.Frame(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.gold })
	UI.Corner(fill, 2)
	UI.Gradient(fill, { T.goldDeep:Lerp(Color3.new(1, 1, 1), 0.2), Color3.new(1, 1, 1) }, 0)
	local knob = UI.Frame(track, { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = T.white })
	UI.Corner(knob, 8)
	UI.Stroke(knob, T.gold, 2)
	local hit = UI.New("TextButton", { Parent = track, Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 16, 0, 32), Position = UDim2.new(0, -8, 0.5, -16) })
	local valText = UI.Text(f, "", { Face = "number", Position = UDim2.new(0.86, 0, 0, 0), Size = UDim2.new(0.14, -14, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 17,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local cur = value
	local function show(v)
		local a = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		valText.Text = fmt and fmt(v) or (step and step >= 1 and tostring(math.floor(v + 0.5)) or string.format("%d%%", math.floor(a * 100 + 0.5)))
	end
	local function set(v, fire)
		v = math.clamp(v, min, max)
		if step then
			v = math.floor((v - min) / step + 0.5) * step + min
		end
		if v ~= cur then
			cur = v
			show(v)
			if fire and onChange then
				onChange(v)
			end
		end
	end
	dragTracker(hit, function(pos)
		local a = math.clamp((pos.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		set(min + (max - min) * a, true)
	end)
	show(value)
	return f, function(v)
		cur = v
		show(v)
	end
end

-- on/off toggle row: a pill switch that slides
function UI.Toggle(parent, label, value, onChange)
	local f = inputRow(parent, label)
	f.Label.Size = UDim2.new(1, -90, 1, 0)
	local state = value and true or false
	local sw = UI.New("TextButton", { Name = "Switch", Text = "", AutoButtonColor = false, BorderSizePixel = 0, Size = UDim2.fromOffset(50, 26), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
		BackgroundColor3 = T.panel2, Parent = f })
	UI.Corner(sw, 13)
	UI.Stroke(sw, Color3.new(1, 1, 1), 1, 0.88)
	local knob = UI.Frame(sw, { Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = T.white })
	UI.Corner(knob, 10)
	local stateText = UI.Text(f, "", { Name = "State", Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -72, 0.5, 0), Size = UDim2.fromOffset(30, 16),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	local function show(animate)
		local goal = { Position = state and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }
		local bgGoal = { BackgroundColor3 = state and T.green or T.panel2 }
		if animate then
			UI.Tween(knob, goal, UI.Motion.base)
			UI.Tween(sw, bgGoal, UI.Motion.base)
		else
			knob.Position = goal.Position
			sw.BackgroundColor3 = bgGoal.BackgroundColor3
		end
		stateText.Text = state and "ON" or "OFF"
		stateText.TextColor3 = state and T.green or T.sub
	end
	sw.MouseButton1Click:Connect(function()
		state = not state
		show(true)
		if onChange then
			onChange(state)
		end
	end)
	show(false)
	return f
end

-- "< value >" cycler over a list; display(v) formats the value
function UI.Cycler(parent, label, list, value, onChange, display)
	local f = inputRow(parent, label)
	local cur = value
	local val = UI.Text(f, "", { Name = "Value", Position = UDim2.new(0.36, 40, 0, 0), Size = UDim2.new(0.64, -94, 1, 0), Font = T.semi, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local function show()
		val.Text = display and display(cur) or tostring(cur)
	end
	local function step(d)
		local i = table.find(list, cur) or 1
		i = ((i - 1 + d) % #list) + 1
		cur = list[i]
		show()
		if onChange then
			onChange(cur)
		end
	end
	local prev = UI.Button(f, "", { Name = "Prev", Size = UDim2.fromOffset(32, 32), Position = UDim2.new(0.36, 0, 0.5, -16) }, function()
		step(-1)
	end)
	UI.Icon(prev, "left", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	local nextB = UI.Button(f, "", { Name = "Next", Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -46, 0.5, -16) }, function()
		step(1)
	end)
	UI.Icon(nextB, "right", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	show()
	return f, function(v)
		cur = v
		show()
	end
end

local function toColor(c)
	if typeof(c) == "Color3" then
		return c
	end
	return Color3.fromRGB(c[1], c[2], c[3])
end
UI.ToColor = toColor

local function toRGB(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
UI.ToRGB = toRGB

-- swatch row; colors = list of {r,g,b}; onPick(rgb, index)
function UI.Swatches(parent, label, colors, selected, onPick)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.45 })
	UI.Corner(f, UI.R.md)
	UI.Pad(f, 10, 14)
	UI.List(f, 8)
	UI.Text(f, label, { TextColor3 = T.sub, TextSize = 14, Font = T.semi })
	local holder = UI.Frame(f, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Grid(holder, 30, 30, 8)
	local buttons = {}
	local function refresh(idx)
		for i, b in ipairs(buttons) do
			local s = b:FindFirstChild("Ring")
			if s then
				s.Color = i == idx and T.gold or Color3.new(1, 1, 1)
				s.Transparency = i == idx and 0 or 0.85
				s.Thickness = i == idx and 3 or 1
			end
		end
	end
	for i, col in ipairs(colors) do
		local b = UI.New("TextButton", { Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = toColor(col), LayoutOrder = i, Parent = holder })
		UI.Corner(b, 15)
		UI.New("UIStroke", { Name = "Ring", Color = Color3.new(1, 1, 1), Transparency = 0.85, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
		UI.Hover(b, { radius = 15, amount = 0.8 })
		b.MouseButton1Click:Connect(function()
			refresh(i)
			if onPick then
				onPick({ col[1], col[2], col[3] }, i)
			end
		end)
		buttons[i] = b
	end
	refresh(selected)
	return f, refresh
end

-- colour wheel (hue around, saturation outwards) + brightness slider
function UI.ColorWheel(parent, label, rgbValue, onChange)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 214), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.45 })
	UI.Corner(f, UI.R.md)
	UI.Text(f, label, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(0.5, 0, 0, 20), TextColor3 = T.sub, TextSize = 14, Font = T.semi, AutomaticSize = Enum.AutomaticSize.None })
	local color = toColor(rgbValue or { 200, 30, 30 })
	local h, s, v = color:ToHSV()
	local R = 90
	local wheel = UI.Frame(f, { BackgroundTransparency = 1, Size = UDim2.fromOffset(R * 2, R * 2), Position = UDim2.fromOffset(12, 28), Active = true })
	local rings, sectors = 6, 28
	local dots = {}
	for ring = 0, rings do
		local rr = ring / rings
		local n = ring == 0 and 1 or math.max(6, math.floor(sectors * rr + 0.5))
		local size = ring == 0 and 18 or math.max(10, 2 * math.pi * rr * R / n + 3)
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * math.pi * 2
			local hue = (i + 0.5) / n
			local x = R + math.cos(a) * rr * (R - 8)
			local y = R - math.sin(a) * rr * (R - 8)
			local d = UI.Frame(wheel, { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), BackgroundColor3 = Color3.fromHSV(hue, rr, 1) })
			UI.Corner(d, math.ceil(size / 2))
			table.insert(dots, { d = d, hue = hue, sat = rr })
		end
	end
	local marker = UI.Frame(wheel, { Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 3 })
	UI.Corner(marker, 7)
	UI.Stroke(marker, Color3.new(1, 1, 1), 2)
	local preview = UI.Frame(f, { Size = UDim2.fromOffset(60, 60), Position = UDim2.new(0, R * 2 + 28, 0, 34), BackgroundColor3 = color })
	UI.Corner(preview, UI.R.lg)
	UI.Stroke(preview, Color3.new(1, 1, 1), 1, 0.8)
	-- brightness slider with a gradient track
	local track = UI.Frame(f, { Position = UDim2.new(0, R * 2 + 28, 0, 112), Size = UDim2.new(1, -(R * 2 + 44), 0, 14), BackgroundColor3 = Color3.new(1, 1, 1), Active = true })
	UI.Corner(track, 7)
	local grad = UI.New("UIGradient", { Parent = track })
	local knob = UI.Frame(track, { Size = UDim2.fromOffset(8, 22), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = T.text })
	UI.Corner(knob, 3)
	UI.Stroke(knob, Color3.new(0, 0, 0), 1)
	UI.Text(f, "Brightness", { Position = UDim2.new(0, R * 2 + 28, 0, 132), Size = UDim2.new(1, -(R * 2 + 44), 0, 18), TextSize = 13, TextColor3 = T.sub, AutomaticSize = Enum.AutomaticSize.None })
	local function render(fire)
		local c = Color3.fromHSV(h, s, v)
		preview.BackgroundColor3 = c
		local a = h * math.pi * 2
		marker.Position = UDim2.fromOffset(R + math.cos(a) * s * (R - 8), R - math.sin(a) * s * (R - 8))
		grad.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(h, s, 1))
		knob.Position = UDim2.fromScale(v, 0.5)
		for _, dot in ipairs(dots) do
			dot.d.BackgroundColor3 = Color3.fromHSV(dot.hue, dot.sat, math.max(0.25, v))
		end
		if fire and onChange then
			onChange(toRGB(c))
		end
	end
	local hitW = UI.New("TextButton", { Parent = wheel, Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	dragTracker(hitW, function(pos)
		local cx, cy = wheel.AbsolutePosition.X + wheel.AbsoluteSize.X / 2, wheel.AbsolutePosition.Y + wheel.AbsoluteSize.Y / 2
		-- the wheel may be drawn under a UIScale: measure in screen px, convert back to design px
		local k = wheel.AbsoluteSize.X / (R * 2)
		local dx, dy = (pos.X - cx) / k, (cy - pos.Y) / k
		local dist = math.sqrt(dx * dx + dy * dy)
		s = math.clamp(dist / (R - 8), 0, 1)
		local ang = math.atan2(dy, dx)
		if ang < 0 then
			ang += math.pi * 2
		end
		h = ang / (math.pi * 2)
		render(true)
	end)
	local hitB = UI.New("TextButton", { Parent = track, Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.5, -15) })
	dragTracker(hitB, function(pos)
		v = math.clamp((pos.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		render(true)
	end)
	render(false)
	return f, function(newRgb)
		h, s, v = toColor(newRgb):ToHSV()
		render(false)
	end
end

function UI.TextInput(parent, label, value, placeholder, maxLen, onChange)
	local f = inputRow(parent, label, 48)
	local box = UI.New("TextBox", {
		Parent = f, Text = value or "", PlaceholderText = placeholder or "", ClearTextOnFocus = false,
		Position = UDim2.new(0.36, 0, 0.5, -17), Size = UDim2.new(0.64, -14, 0, 34), BackgroundColor3 = T.ink, BackgroundTransparency = 0.2, BorderSizePixel = 0,
		TextColor3 = T.text, PlaceholderColor3 = T.dim, Font = T.font, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
	})
	UI.Corner(box, UI.R.md)
	UI.Pad(box, 0, 10)
	local stroke = UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.85, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = box })
	box.Focused:Connect(function()
		stroke.Color, stroke.Transparency = T.gold, 0.1
	end)
	box.FocusLost:Connect(function()
		stroke.Color, stroke.Transparency = Color3.new(1, 1, 1), 0.85
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > maxLen then
			box.Text = box.Text:sub(1, maxLen)
		end
		if onChange then
			onChange(box.Text)
		end
	end)
	return f, box
end

-- horizontal tab bar with a sliding underline; returns frame and select(name)
function UI.Tabs(parent, names, current, onSelect, props)
	local bar = UI.Frame(parent, props or { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38) })
	bar.BackgroundTransparency = 1
	local holder = UI.Frame(bar, { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -3) })
	UI.List(holder, 4, true)
	UI.Frame(bar, { Name = "Track", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88 })
	local under = UI.Frame(bar, { Name = "Underline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1 / #names, -4, 0, 3), BackgroundColor3 = T.gold, ZIndex = 2 })
	local buttons = {}
	local function select(name, animate)
		local idx = table.find(names, name) or 1
		for n, b in pairs(buttons) do
			b.TextColor3 = n == name and T.text or T.sub
		end
		local goal = { Position = UDim2.new((idx - 1) / #names, 0, 1, 0) }
		if animate then
			UI.Tween(under, goal, UI.Motion.base)
		else
			under.Position = goal.Position
		end
	end
	for i, name in ipairs(names) do
		buttons[name] = UI.Button(holder, string.upper(name), { Size = UDim2.new(1 / #names, -4, 1, 0), TextSize = 14, LayoutOrder = i, BackgroundTransparency = 1 }, function()
			select(name, true)
			onSelect(name)
		end)
	end
	select(current, false)
	return bar, function(name)
		select(name, true)
	end
end

------------------------------------------------------------------------
-- Toast notifications (top right, slide in, accent bar in the message colour)
------------------------------------------------------------------------
local toastHolder
function UI.Toast(gui, text, color, duration)
	if not toastHolder or not toastHolder.Parent then
		toastHolder = UI.Frame(gui, { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0, 400, 1, -160), Position = UDim2.new(1, -24, 0, 76), ZIndex = 50 })
		UI.List(toastHolder, 8, false, Enum.HorizontalAlignment.Right)
	end
	color = color or T.gold
	local f = UI.Frame(toastHolder, { Name = "Toast", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 50 })
	local card = UI.Frame(f, { Name = "Card", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(60, 0), BackgroundColor3 = T.bg, BackgroundTransparency = 1, ZIndex = 50 })
	UI.Corner(card, UI.R.lg)
	local stroke = UI.New("UIStroke", { Color = color, Transparency = 1, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })
	UI.New("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 14), Parent = card })
	local accent = UI.Frame(card, { Name = "Bar", Position = UDim2.new(0, -14, 0, -6), Size = UDim2.new(0, 3, 1, 12), BackgroundColor3 = color, BackgroundTransparency = 1, ZIndex = 51 })
	UI.Corner(accent, 2)
	local label = UI.Text(card, text, { TextXAlignment = Enum.TextXAlignment.Left, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), ZIndex = 51, Font = T.semi, TextSize = 15, TextTransparency = 1 })
	UI.Tween(card, { Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.06 }, UI.Motion.base)
	UI.Tween(stroke, { Transparency = 0.55 }, UI.Motion.base)
	UI.Tween(accent, { BackgroundTransparency = 0 }, UI.Motion.base)
	UI.Tween(label, { TextTransparency = 0 }, UI.Motion.base)
	local kids = toastHolder:GetChildren()
	if #kids > 7 then
		for _, k in ipairs(kids) do
			if k:IsA("Frame") and k ~= f then
				k:Destroy()
				break
			end
		end
	end
	task.delay(duration or 3.6, function()
		if f.Parent then
			UI.Tween(card, { BackgroundTransparency = 1, Position = UDim2.fromOffset(40, 0) }, UI.Motion.base)
			UI.Tween(stroke, { Transparency = 1 }, UI.Motion.base)
			UI.Tween(accent, { BackgroundTransparency = 1 }, UI.Motion.base)
			UI.Tween(label, { TextTransparency = 1 }, UI.Motion.base)
			task.wait(0.3)
			f:Destroy()
		end
	end)
end

return UI
