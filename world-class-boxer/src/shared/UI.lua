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
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local UI = {}

-- the input device in use and the controller's button names (Shared.Gamepad); optional: without it
-- every window simply behaves as on keyboard and mouse
local Gamepad
do
	local ok, m = pcall(function()
		return require(script.Parent:WaitForChild("Gamepad", 5))
	end)
	Gamepad = ok and type(m) == "table" and m or nil
end
UI.Gamepad = Gamepad

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

------------------------------------------------------------------------
-- Readability floor: no text renders below UI.MinTextPx screen pixels
------------------------------------------------------------------------
-- A label's design size is kept in the attribute TextBase (and a UITextSizeConstraint's in MinTextBase);
-- under a scaled root (UI.MountRoot) the size actually used is max(design, TextFloor(root scale)), so
-- the 10 px captions of a 1080p layout grow to 14 design px at 720p and 15 on a phone, and stay 10 where
-- there is room. Re-applied when a root rescales and when a subtree built elsewhere is parented under
-- a root. Labels whose size changes later go through UI.SetTextSize.
UI.MinTextPx = 11
local FLOOR_LIMIT = 22 -- design sizes from here up are never below the floor (smallest root scale ~0.55)
function UI.TextFloor(scale)
	scale = tonumber(scale) or 1
	return math.ceil(UI.MinTextPx / math.max(scale, 0.1) - 1e-6)
end

local function floorText(obj, floor)
	local base = obj:GetAttribute("TextBase")
	if type(base) == "number" then
		local want = math.max(base, floor)
		if obj.TextSize ~= want then
			obj.TextSize = want
		end
		return
	end
	base = obj:GetAttribute("MinTextBase")
	if type(base) == "number" and obj:IsA("UITextSizeConstraint") then
		local want = math.max(base, floor)
		if obj.MinTextSize ~= want then
			if obj.MaxTextSize < want then
				obj.MaxTextSize = want
			end
			obj.MinTextSize = want
		end
	end
end

local mounted = {} -- [root] = { gui, scale, floor } (UI.MountRoot)
local function rootOf(obj)
	local r = obj
	while r and not mounted[r] do
		r = r.Parent
	end
	return r
end

-- design text size for a label / button / box (the floor applies on top); use it instead of
-- writing TextSize directly when a small label's size changes after it was built
function UI.SetTextSize(obj, size)
	if size < FLOOR_LIMIT then
		obj:SetAttribute("TextBase", size)
		local r = rootOf(obj)
		obj.TextSize = r and math.max(size, mounted[r].floor) or size
	else
		obj:SetAttribute("TextBase", nil)
		obj.TextSize = size
	end
	return obj
end

local function registerText(obj, props)
	if not props.TextScaled and (props.TextSize or 16) < FLOOR_LIMIT then
		UI.SetTextSize(obj, props.TextSize or 16)
	end
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
	registerText(label, props)
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

-- kind: close, left, right, up, down, check, plus, minus, play, menu, lock, dot, star, bolt, reset / undo
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
	elseif kind == "reset" or kind == "undo" then
		-- a ring open at the top left with an arrow head on its end (reset: back to the default; undo)
		local ring = UI.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.fromScale(0.74, 0.74), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z, Parent = f })
		UI.Corner(ring, size)
		local st = UI.New("UIStroke", { Color = color, Thickness = th, Parent = ring })
		-- the gap: a gradient on the stroke fades its top-left quarter out
		UI.New("UIGradient", { Rotation = -45, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(0.31, 0), NumberSequenceKeypoint.new(1, 0) }), Parent = st })
		bar(f, 0.34, th, 0.2, 0.26, 0, color, z)
		bar(f, 0.34, th, 0.07, 0.2 + 0.13, 90, color, z)
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
	registerText(b, props)
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
-- the colour language for meters, one meaning per colour everywhere (fight HUD, gym, body map):
-- "how much is left" bars (health, head, body, condition) follow the value: green above 60 %, gold
-- above 35 %, orange above 18 %, red below. Stamina is blue while there is gas, amber from half,
-- red under a quarter.
UI.Amber = Color3.fromRGB(255, 178, 46)
function UI.Ramp(v)
	v = tonumber(v) or 0
	return v > 0.6 and T.green or (v > 0.35 and T.gold or (v > 0.18 and T.orange or T.red))
end
function UI.StamColor(v)
	v = tonumber(v) or 0
	return v >= 0.5 and T.blue or (v >= 0.25 and UI.Amber or T.red)
end
-- dark or white text for a label on a solid colour (whichever reads better)
function UI.InkOn(c)
	local lum = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	return lum > 0.42 and T.ink or Color3.new(1, 1, 1)
end

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

-- A development bar on the 0..100 muscle scale, the same everywhere a muscle level is shown (Body tab,
-- training cards, session result), so the picture means one thing: the fill is the level now, the
-- gold tick the frame's potential. opts: value, cap, color (the fill), gain = { from, to } (the level
-- before in the fill colour, the growth just made in bright green, at least 4 px so a small gain
-- still shows), pending (the level once tonight's growth lands: a pale green stretch)
function UI.LevelBar(parent, props, opts)
	opts = opts or {}
	local bg = UI.Frame(parent, props)
	if not props.Name then
		bg.Name = "Level"
	end
	bg.BackgroundColor3 = T.ink
	bg.BackgroundTransparency = 0.05
	UI.Corner(bg, UI.R.sm)
	local function f01(v)
		return math.clamp((tonumber(v) or 0) / 100, 0, 1)
	end
	local function seg(name, a, b, color, transparency, z, minPx)
		if b - a <= 0 and not minPx then
			return nil
		end
		local s = UI.Frame(bg, { Name = name, Position = UDim2.fromScale(a, 0), Size = UDim2.new(math.max(0, b - a), (b - a) < 0.012 and (minPx or 0) or 0, 1, 0),
			BackgroundColor3 = color, BackgroundTransparency = transparency or 0, ZIndex = z or 2 })
		UI.Corner(s, UI.R.sm)
		return s
	end
	if opts.gain then
		local from, to = f01(opts.gain[1]), f01(opts.gain[2])
		seg("Before", 0, from, opts.color or T.line, 0, 2)
		if opts.pending then
			seg("Tonight", to, math.max(to, f01(opts.pending)), T.green, 0.62, 2)
		end
		seg("Gain", from, math.max(from, to), T.green, 0, 3, 4)
	else
		seg("Fill", 0, f01(opts.value), opts.color or T.green, 0, 2)
	end
	if opts.cap then
		UI.Frame(bg, { Name = "Cap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(f01(opts.cap), 0.5), Size = UDim2.new(0, 2, 1, 6), BackgroundColor3 = T.gold, ZIndex = 4 })
	end
	return bg
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
	-- outline chips sit on a dark fill so they read on any backdrop (blurred 3D, glass, photos)
	local f = UI.Frame(parent, {
		Size = props.Size or UDim2.fromOffset(0, props.h or 22), AutomaticSize = props.Size and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		BackgroundColor3 = props.solid and color or T.bg:Lerp(color, 0.12), BackgroundTransparency = props.solid and 0 or 0.2, LayoutOrder = props.order or 0, Name = props.Name or "Chip",
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
	-- the readability floor follows the scale: every registered label under this root gets it
	local floor = UI.TextFloor(s)
	if floor ~= info.floor then
		info.floor = floor
		for _, d in ipairs(root:GetDescendants()) do
			if d:GetAttribute("TextBase") ~= nil or d:GetAttribute("MinTextBase") ~= nil then
				floorText(d, floor)
			end
		end
	end
	root:SetAttribute("UIScale", s)
end

-- gives a ScreenGui one scaled root frame; everything goes inside it (returns the root). The
-- listeners go away with the root (MainMenu mounts a new one every time it opens).
function UI.MountRoot(gui, name)
	local root = UI.New("Frame", { Name = name or "Root", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = gui })
	local info = { gui = gui, scale = UI.New("UIScale", { Name = "RootScale", Parent = root }), floor = 0 }
	mounted[root] = info
	applyScale(root, info)
	local conns = {}
	local function rescale()
		if root.Parent then
			applyScale(root, info)
		end
	end
	table.insert(conns, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale))
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
	end
	-- a subtree built elsewhere and parented in here picks up the floor; a size constraint keeps its
	-- design minimum in MinTextBase the first time it is seen
	table.insert(conns, root.DescendantAdded:Connect(function(d)
		if d:GetAttribute("TextBase") ~= nil or d:GetAttribute("MinTextBase") ~= nil then
			floorText(d, info.floor)
		elseif d:IsA("UITextSizeConstraint") then
			if d.MinTextSize < FLOOR_LIMIT then
				d:SetAttribute("MinTextBase", d.MinTextSize)
				floorText(d, info.floor)
			end
		end
	end))
	root.Destroying:Connect(function()
		mounted[root] = nil
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		table.clear(conns)
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
	local root = rootOf(obj)
	return root and mounted[root].scale.Scale or 1
end

-- the design-pixel size of the area an object lays out in (its root's canvas)
function UI.CanvasSize(obj)
	local root = rootOf(obj)
	local screen = root and mounted[root].gui or obj:FindFirstAncestorWhichIsA("LayerCollector")
	local abs = screen and screen.AbsoluteSize or Vector2.zero
	if abs.X < 2 or abs.Y < 2 then
		local cam = workspace.CurrentCamera
		abs = cam and cam.ViewportSize or Vector2.new(1600, 900)
	end
	-- computed fresh (same formula as the root's UIScale) so a resize handler never sees a stale scale
	local s = root and UI.ScaleFor(abs.X, abs.Y, UI.UserScale) or 1
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
-- Gamepad navigation
------------------------------------------------------------------------
-- Roblox's own selection (GuiService.SelectedObject) moves between selectable objects with the D-pad /
-- left stick and A presses the selected button. The kit adds the rest: a start selection when a window
-- opens (or the player picks up a pad while one is open), the selection kept inside the top window (each
-- UI.Window is a SelectionGroup) and put back near where it was when a re-render destroys it, B = the
-- window's back / close, D-pad left / right (and A) on slider, cycler, toggle and colour rows (held on a
-- slider: it keeps stepping; X puts a slider back to its default), and the right stick scrolling the list
-- under the selection. UI.PadStart(button) makes a button its window's start
-- selection. UI.PadHold(key, true) pauses all of it while a screen with its own navigation is up (the main
-- menu, a fight).
local padWindows = {} -- open UI.Window entries, oldest first: { shade, win, back, lastPos }
local padHolds = {}
local padStarted = false
local scrollY, scrollConn, scrollFrame = 0, nil, nil

local function isPad()
	return Gamepad ~= nil and Gamepad.IsPad()
end
UI.IsPad = isPad

-- on screen: every GuiObject up to the ScreenGui visible and the ScreenGui enabled
local function shown(obj)
	local o = obj
	while o do
		if o:IsA("LayerCollector") then
			return o.Enabled
		elseif o:IsA("GuiObject") and not o.Visible then
			return false
		end
		o = o.Parent
	end
	return false
end

local function centre(o)
	return o.AbsolutePosition + o.AbsoluteSize / 2
end

local function topWindow()
	for i = #padWindows, 1, -1 do
		local w = padWindows[i]
		if w.shade.Parent and w.win.Parent then
			return w
		end
		-- removed without Destroy: forget it
		table.remove(padWindows, i)
	end
	return nil
end

-- the top window's panel (nil when none is open): a window's own pad shortcuts act only while it is on top
function UI.PadTop()
	local w = topWindow()
	return w and w.win
end

local function selectableIn(root)
	local list = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") and d.Selectable and (d:IsA("GuiButton") or d:IsA("TextBox") or d:GetAttribute("PadRow")) and d.AbsoluteSize.X > 1 and d.AbsoluteSize.Y > 1
			and shown(d) then
			table.insert(list, d)
		end
	end
	return list
end

-- selects a button inside root: the one nearest `near` (screen px: where the selection was before a
-- re-render), else the one marked by UI.PadStart, else the first in reading order (a window's close
-- button last)
function UI.PadSelect(root, near)
	if not root then
		return nil
	end
	local list = selectableIn(root)
	local pick, best
	if near then
		for _, o in ipairs(list) do
			local d = (centre(o) - near).Magnitude
			if not best or d < best then
				best, pick = d, o
			end
		end
	end
	if not pick then
		for _, o in ipairs(list) do
			if o:GetAttribute("PadStart") then
				pick = o
				break
			end
		end
	end
	if not pick then
		for _, o in ipairs(list) do
			if o.Name ~= "Close" or #list == 1 then
				local p = o.AbsolutePosition
				local key = math.floor(p.Y / 8) * 100000 + p.X
				if not best or key < best then
					best, pick = key, o
				end
			end
		end
	end
	if pick then
		pcall(function()
			GuiService.SelectedObject = pick
		end)
	end
	return pick
end

-- makes sure the top window holds the selection (on a gamepad, nothing held)
function UI.PadRefresh()
	if not isPad() or next(padHolds) then
		return
	end
	local w = topWindow()
	if not w then
		return
	end
	local sel = GuiService.SelectedObject
	-- (a close button picked only because the content was not built yet gives way to it)
	if sel and sel:IsDescendantOf(w.win) and shown(sel) and not (sel == w.auto and sel.Name == "Close") then
		return
	end
	w.auto = UI.PadSelect(w.win, w.lastPos)
end

function UI.PadStart(obj)
	if obj then
		obj:SetAttribute("PadStart", true)
	end
	return obj
end

local function clearSelection()
	if GuiService.SelectedObject ~= nil then
		pcall(function()
			GuiService.SelectedObject = nil
		end)
	end
end
UI.ClearSelection = clearSelection

function UI.PadHold(key, on)
	local v = on and true or nil
	if padHolds[key] == v then
		return
	end
	padHolds[key] = v
	if v then
		clearSelection()
	else
		task.defer(UI.PadRefresh)
	end
end

local function scrollStep(dt)
	local sf = scrollFrame
	if scrollY == 0 or not (sf and sf.Parent) then
		if scrollConn then
			scrollConn:Disconnect()
			scrollConn = nil
		end
		return
	end
	local maxY = math.max(0, sf.AbsoluteCanvasSize.Y - sf.AbsoluteWindowSize.Y)
	local cp = sf.CanvasPosition
	local y = math.clamp(cp.Y - scrollY * math.min(dt, 0.1) * 900, 0, maxY)
	if y ~= cp.Y then
		sf.CanvasPosition = Vector2.new(cp.X, y)
	end
end

-- the list the right stick scrolls: the one around the selection, else the window's biggest
local function scrollTarget(w)
	local sel = GuiService.SelectedObject
	local sf = sel and sel:IsDescendantOf(w.win) and sel:FindFirstAncestorWhichIsA("ScrollingFrame")
	if sf then
		return sf
	end
	local area = 0
	for _, d in ipairs(w.win:GetDescendants()) do
		if d:IsA("ScrollingFrame") and d.Visible then
			local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
			if a > area then
				area, sf = a, d
			end
		end
	end
	return sf or nil
end

-- a D-pad held on a selected slider keeps stepping it (bumped to stop)
local padRepeat = 0
local function padInput(input)
	local k = input.KeyCode
	if k ~= Enum.KeyCode.ButtonB and k ~= Enum.KeyCode.DPadLeft and k ~= Enum.KeyCode.DPadRight and k ~= Enum.KeyCode.ButtonA and k ~= Enum.KeyCode.ButtonX then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if k == Enum.KeyCode.ButtonB then
		-- B = back / close (whether or not Roblox's own selection also took it)
		local w = not next(padHolds) and topWindow()
		if w and w.back then
			w.back()
		end
		return
	end
	-- a selected input row steps (its own buttons are not selectable: D-pad left / right would leave it);
	-- X puts a selected slider back to its default
	local sel = GuiService.SelectedObject
	if not (sel and sel:GetAttribute("PadRow")) then
		return
	end
	if k == Enum.KeyCode.ButtonX then
		UI.ResetRow(sel)
		return
	end
	local dir = k == Enum.KeyCode.ButtonA and 0 or (k == Enum.KeyCode.DPadLeft and -1 or 1)
	UI.Nudge(sel, dir)
	if dir ~= 0 and sel:GetAttribute("Slider") then
		padRepeat += 1
		local my = padRepeat
		task.delay(0.4, function()
			while padRepeat == my and GuiService.SelectedObject == sel and sel.Parent do
				UI.Nudge(sel, dir)
				task.wait(0.075)
			end
		end)
	end
end

local function padInit()
	if padStarted or not Gamepad or not RunService:IsClient() then
		return
	end
	padStarted = true
	Gamepad.Changed:Connect(function(mode)
		if mode == "gamepad" then
			UI.PadRefresh()
		else
			-- back on mouse / touch: no selection frame left on a window
			local sel = GuiService.SelectedObject
			local w = topWindow()
			if sel and w and sel:IsDescendantOf(w.win) then
				clearSelection()
			end
		end
	end)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local w = topWindow()
		if not w then
			return
		end
		local sel = GuiService.SelectedObject
		if sel then
			if sel:IsDescendantOf(w.win) then
				w.lastPos = centre(sel)
			end
		else
			-- a re-render destroyed it, or B dropped it: select again near where it was once the new
			-- content exists
			task.delay(0.05, UI.PadRefresh)
		end
	end)
	UserInputService.InputBegan:Connect(padInput)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.DPadRight then
			padRepeat += 1
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.Thumbstick2 then
			return
		end
		local y = input.Position.Y
		local was = scrollY
		scrollY = math.abs(y) > 0.25 and y or 0
		if scrollY ~= 0 and was == 0 and not next(padHolds) then
			local w = topWindow()
			scrollFrame = w and scrollTarget(w)
			if scrollFrame and not scrollConn then
				scrollConn = RunService.Heartbeat:Connect(scrollStep)
			end
		end
	end)
end

-- labels whose text depends on the device in use (key caps, "press E" hints): fn(mode) -> text, run now and
-- again whenever the player switches between keyboard, gamepad and touch; the entry goes with the label
local hints = {}
local hintConn
local function applyHint(label, fn, mode)
	local ok, t = pcall(fn, mode)
	if ok and type(t) == "string" and label.Text ~= t then
		label.Text = t
	end
end
function UI.BindHint(label, fn)
	if not label then
		return label
	end
	local fresh = hints[label] == nil
	hints[label] = fn
	applyHint(label, fn, Gamepad and Gamepad.Mode() or "keyboard")
	if fresh then
		label.Destroying:Connect(function()
			hints[label] = nil
		end)
	end
	if not hintConn and Gamepad then
		hintConn = Gamepad.Changed:Connect(function(mode)
			for l, f in pairs(hints) do
				applyHint(l, f, mode)
			end
		end)
	end
	return label
end
-- the usual hint: kbd text on keyboard, the pad button's name on a gamepad, touch text (or kbd) on touch
function UI.KeyHint(kbd, padKey, touch)
	return function(mode)
		if mode == "gamepad" and Gamepad then
			return type(padKey) == "string" and padKey or Gamepad.Label(padKey)
		elseif mode == "touch" and touch then
			return touch
		end
		return kbd
	end
end
-- the device in use ("keyboard" | "gamepad" | "touch")
function UI.InputMode()
	return Gamepad and Gamepad.Mode() or "keyboard"
end

------------------------------------------------------------------------
-- Windows & cards
------------------------------------------------------------------------
-- returns shade, win, body (scrolling list area) ; opts = { side = "left"|"right", noShade, onClose,
-- onBack (gamepad B when it is not onClose), scroll = false, footer = px, z,
-- kicker = "SMALL CAPTION ABOVE THE TITLE" }
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
	-- gamepad: the window is a selection group (the D-pad stays inside it), B is its back / close
	-- (opts.onBack, else opts.onClose), and it takes the selection once its content is built
	pcall(function()
		win.SelectionGroup = true
		win.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
		win.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
		win.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
		win.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	end)
	local entry = { shade = shade, win = win, back = opts.onBack or opts.onClose }
	table.insert(padWindows, entry)
	shade.Destroying:Connect(function()
		local i = table.find(padWindows, entry)
		if i then
			table.remove(padWindows, i)
		end
		task.defer(UI.PadRefresh)
	end)
	padInit()
	task.defer(UI.PadRefresh)
	task.delay(0.3, UI.PadRefresh)
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
-- a scrolling list held still while a slider is dragged or wheel-adjusted (ref-counted: a drag and a
-- hover can overlap on one list, and the list gets its own setting back when the last one lets go)
local scrollHolds = {} -- [ScrollingFrame] = { n = holds, was = ScrollingEnabled before }
local function holdScroll(sf, on)
	if not sf then
		return
	end
	local h = scrollHolds[sf]
	if on then
		if not h then
			h = { n = 0, was = sf.ScrollingEnabled }
			scrollHolds[sf] = h
			sf.ScrollingEnabled = false
		end
		h.n += 1
	elseif h then
		h.n -= 1
		if h.n <= 0 then
			scrollHolds[sf] = nil
			if sf.Parent then
				sf.ScrollingEnabled = h.was
			end
		end
	end
end

local MB1, TOUCH, MOVE, WHEEL = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.UserInputType.MouseMovement, Enum.UserInputType.MouseWheel

-- onPos(screen position, first) while the pointer that pressed target stays down - anywhere on the screen,
-- so a drag need not stay on the bar; onEnd() once it is released. A touch drag follows its own finger
-- only (a second finger on the screen does not yank it), and the scrolling list around target holds
-- still for the drag (a sideways slide on a phone would otherwise scroll the page).
local function dragTracker(target, onPos, onEnd)
	local active -- the InputObject that started the drag (the mouse button or the touch)
	local held -- the ScrollingFrame held still for it
	local function stop()
		active = nil
		if held then
			holdScroll(held, false)
			held = nil
		end
	end
	target.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if active == nil and (t == MB1 or t == TOUCH) then
			active = input
			held = target:FindFirstAncestorWhichIsA("ScrollingFrame")
			holdScroll(held, true)
			onPos(Vector2.new(input.Position.X, input.Position.Y), true)
		end
	end)
	local c1 = UserInputService.InputChanged:Connect(function(input)
		if active == nil then
			return
		end
		local t = input.UserInputType
		if (t == MOVE and active.UserInputType == MB1) or (t == TOUCH and input == active) then
			onPos(Vector2.new(input.Position.X, input.Position.Y), false)
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if active ~= nil and (input == active or (input.UserInputType == MB1 and active.UserInputType == MB1)) then
			stop()
			if onEnd then
				onEnd()
			end
		end
	end)
	target.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
		stop()
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

-- input rows (slider, cycler, toggle) by frame: their step function, for keyboard / gamepad focus
-- navigation (UI.Nudge; MainMenu's settings screen), and a slider's back-to-default (UI.ResetRow: X on a
-- gamepad)
local inputNudge = {}
local inputReset = {}
local function registerNudge(f, fn)
	inputNudge[f] = fn
	f.Destroying:Connect(function()
		inputNudge[f] = nil
		inputReset[f] = nil
	end)
end

-- gamepad: the whole row is one selectable stop; D-pad left / right steps it (UI.Nudge from the kit's
-- pad input) instead of moving the selection, so its own small buttons are left out of the selection
local function padRow(f, ...)
	f.Selectable = true
	f:SetAttribute("PadRow", true)
	f.NextSelectionLeft = f
	f.NextSelectionRight = f
	for _, b in ipairs({ ... }) do
		b.Selectable = false
	end
end

-- a [-] / [+] held down repeats (one hold at a time: any pointer release anywhere stops it)
local holdTok = 0
local holdConn
local function holdStop()
	holdTok += 1
end
local function holdRepeat(row, fn)
	fn()
	holdTok += 1
	local my = holdTok
	if not holdConn then
		holdConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == MB1 or input.UserInputType == TOUCH then
				holdStop()
			end
		end)
	end
	task.delay(0.4, function()
		while holdTok == my and row.Parent do
			fn()
			task.wait(0.07)
		end
	end)
end

-- words for a value: opts.words is fn(v) -> text, or a list spread evenly over the range
local function wordFor(words, v, a)
	if type(words) == "function" then
		return words(v)
	elseif type(words) == "table" and #words > 0 then
		return words[math.clamp(math.floor(a * #words) + 1, 1, #words)]
	end
	return nil
end

-- slider row: returns frame, setValue(v). Two lines: the label, the value in plain words (opts.words)
-- next to its number (fmt) and a reset-to-default button (opts.default; X on a gamepad) on top, then a
-- big [-] / track / [+] line: tap or click anywhere on the track to jump there, drag from it and keep
-- dragging anywhere on the screen, the mouse wheel steps it while the pointer rests on it, [-] / [+]
-- step it (held: repeat) and a notch marks the default. opts.hint = one line under the label.
-- onChange(v) fires on every change (live preview: callers throttle what it costs); opts.onRelease
-- delays it to the end of a drag instead (a setting that rebuilds the screen it lives on: the UI scale);
-- opts.onEnd(v) fires once at the end of every gesture (a drag let go, a step, a reset, a wheel notch).
function UI.Slider(parent, label, min, max, value, step, onChange, fmt, opts)
	opts = opts or {}
	local hint = opts.hint
	local hasDefault = type(opts.default) == "number"
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, hint and 86 or 70), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.45 })
	f:SetAttribute("Slider", true)
	UI.Corner(f, UI.R.md)
	local right = hasDefault and 50 or 14
	UI.Text(f, label, { Name = "Label", Position = UDim2.fromOffset(14, 6), Size = UDim2.new(0.5, -14, 0, 22), TextColor3 = T.text, TextSize = 15, Font = T.semi,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local valText = UI.Text(f, "", { Name = "Value", Face = "displayMed", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -right, 0, 4), Size = UDim2.new(0.5, 8 - right, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Right, TextSize = 18, TextColor3 = T.gold, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	if hint then
		UI.Text(f, hint, { Name = "Hint", Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 16), TextSize = 12, TextColor3 = T.sub,
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	local y0 = hint and 44 or 30
	local track = UI.Frame(f, { Name = "Track", Position = UDim2.new(0, 62, 0, y0 + 14), Size = UDim2.new(1, -124, 0, 8), BackgroundColor3 = T.ink, BackgroundTransparency = 0.1 })
	UI.Corner(track, 4)
	local fill = UI.Frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.gold })
	UI.Corner(fill, 4)
	UI.Gradient(fill, { T.goldDeep:Lerp(Color3.new(1, 1, 1), 0.2), Color3.new(1, 1, 1) }, 0)
	if hasDefault and max > min then
		local da = math.clamp((opts.default - min) / (max - min), 0, 1)
		UI.Frame(track, { Name = "Notch", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(da, 0.5), Size = UDim2.fromOffset(2, 20), BackgroundColor3 = T.text, BackgroundTransparency = 0.35 })
	end
	local knob = UI.Frame(track, { Name = "Knob", Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = T.white })
	UI.Corner(knob, 12)
	UI.Stroke(knob, T.gold, 3)
	-- the hit area: the whole line between [-] and [+] (wider and taller than the bar itself)
	local hit = UI.New("TextButton", { Name = "Hit", Parent = f, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 50, 0, y0 - 4),
		Size = UDim2.new(1, -100, 0, 44), Selectable = false })
	local cur = value
	local dragging = false
	local resetBtn, resetIcon, atDefault
	local q = step or (max - min) / 200 -- free sliders move in half-percent steps (a drag sends fewer changes)
	local function show(v)
		local a = max > min and math.clamp((v - min) / (max - min), 0, 1) or 0
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		local num = fmt and fmt(v) or (step and step >= 1 and tostring(math.floor(v + 0.5)) or string.format("%d%%", math.floor(a * 100 + 0.5)))
		local word = wordFor(opts.words, v, a)
		valText.Text = (word and num ~= "") and (word .. "  ·  " .. num) or (word or num)
		f:SetAttribute("Value", v)
		local at = resetBtn and math.abs(v - opts.default) < q * 0.5
		if resetBtn and at ~= atDefault then
			-- the reset button dims while the value sits on its default
			atDefault = at
			resetBtn.BackgroundTransparency = at and 0.75 or 0.2
			for _, d in ipairs(resetIcon:GetDescendants()) do
				if d:IsA("Frame") and d.BackgroundTransparency < 1 then
					d.BackgroundColor3 = at and T.dim or T.text
				elseif d:IsA("UIStroke") then
					d.Color = at and T.dim or T.text
				end
			end
		end
	end
	local function set(v, fire)
		v = math.clamp(v, min, max)
		v = math.clamp(math.floor((v - min) / q + 0.5) * q + min, min, max)
		if v ~= cur then
			cur = v
			show(v)
			if fire and onChange and not (dragging and opts.onRelease) then
				onChange(v)
			end
		end
	end
	local committed = value
	local function gestureEnd()
		if opts.onEnd then
			opts.onEnd(cur)
		end
	end
	dragTracker(hit, function(pos)
		dragging = true
		local a = math.clamp((pos.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		set(min + (max - min) * a, true)
	end, function()
		dragging = false
		if opts.onRelease and onChange and cur ~= committed then
			committed = cur
			onChange(cur)
		end
		committed = cur
		gestureEnd()
	end)
	local function nudge(d)
		if d == 0 then
			return -- (A on the row: a slider has nothing to press)
		end
		set(cur + d * (step or (max - min) / 20), true)
		committed = cur
		gestureEnd()
	end
	local function reset()
		if hasDefault then
			set(opts.default, true)
			committed = cur
			gestureEnd()
		end
	end
	-- the mouse wheel steps the slider once the pointer has really moved onto its track (not when the
	-- page scrolls a track under a resting pointer); the list holds still meanwhile
	local wheelFrom, wheelArmed = nil, false
	local wheelList
	local function disarm()
		wheelFrom = nil
		if wheelArmed then
			wheelArmed = false
			holdScroll(wheelList, false)
		end
	end
	hit.MouseEnter:Connect(function()
		wheelFrom = UserInputService:GetMouseLocation()
	end)
	hit.MouseMoved:Connect(function()
		if not wheelArmed and wheelFrom and (UserInputService:GetMouseLocation() - wheelFrom).Magnitude > 2 then
			wheelArmed = true
			wheelList = f:FindFirstAncestorWhichIsA("ScrollingFrame")
			holdScroll(wheelList, true)
		end
	end)
	hit.MouseLeave:Connect(disarm)
	hit.InputChanged:Connect(function(input)
		if wheelArmed and input.UserInputType == WHEEL and input.Position.Z ~= 0 then
			nudge(input.Position.Z > 0 and 1 or -1)
		end
	end)
	f.Destroying:Connect(disarm)
	local steppers = {}
	for _, spec in ipairs({ { "Minus", -1, UDim2.new(0, 10, 0, y0), "minus" }, { "Plus", 1, UDim2.new(1, -46, 0, y0), "plus" } }) do
		local b = UI.Button(f, "", { Name = spec[1], Size = UDim2.fromOffset(36, 36), Position = spec[3], BackgroundColor3 = T.panel2, BackgroundTransparency = 0.2 })
		UI.Icon(b, spec[4], 13, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		b.MouseButton1Down:Connect(function()
			holdRepeat(f, function()
				nudge(spec[2])
			end)
		end)
		b.MouseButton1Up:Connect(holdStop)
		b.MouseLeave:Connect(holdStop)
		table.insert(steppers, b)
	end
	if hasDefault then
		resetBtn = UI.Button(f, "", { Name = "Reset", Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 2), BackgroundColor3 = T.panel2 }, reset)
		resetIcon = UI.Icon(resetBtn, "reset", 14, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		table.insert(steppers, resetBtn)
		inputReset[f] = reset
	end
	registerNudge(f, nudge)
	padRow(f, hit, table.unpack(steppers))
	show(value)
	return f, function(v)
		cur = v
		committed = v
		show(v)
	end
end

-- puts the slider row that contains obj back to its default (false when obj is in none / it has none)
function UI.ResetRow(obj)
	local o = obj
	while o do
		local fn = inputReset[o]
		if fn then
			fn()
			return true
		end
		o = o.Parent
	end
	return false
end

-- steps the input row that contains obj (a slider's [-] / [+], a cycler, a toggle, or the row itself)
-- by dir (-1 / +1; a toggle flips); false if obj is in none
function UI.Nudge(obj, dir)
	local o = obj
	while o do
		local fn = inputNudge[o]
		if fn then
			fn(dir)
			return true
		end
		o = o.Parent
	end
	return false
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
	local function flip()
		state = not state
		show(true)
		if onChange then
			onChange(state)
		end
	end
	sw.MouseButton1Click:Connect(flip)
	registerNudge(f, flip)
	padRow(f, sw)
	show(false)
	return f
end

-- "< value >" cycler over a list; display(v) formats the value
function UI.Cycler(parent, label, list, value, onChange, display)
	local f = inputRow(parent, label)
	local cur = value
	-- a long value on a narrow row takes a second line before it is cut ("Welterweight (136-147)")
	local val = UI.Text(f, "", { Name = "Value", Position = UDim2.new(0.36, 40, 0, 0), Size = UDim2.new(0.64, -94, 1, 0), Font = T.semi, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, LineHeight = 0.95 })
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
	-- dir 0 (A on the row) steps forward
	registerNudge(f, function(d)
		step(d == 0 and 1 or d)
	end)
	padRow(f, prev, nextB)
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

-- swatch grid; colors = list of {r,g,b}; onPick(rgb, index). The picked swatch wears a gold ring and a
-- tick; opts.names (one per colour) shows the picked colour's name next to the label, opts.size = the
-- swatch size (36). Returns frame, refresh(index | nil = none picked: a custom colour)
function UI.Swatches(parent, label, colors, selected, onPick, opts)
	opts = opts or {}
	local size = opts.size or 36
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.45 })
	UI.Corner(f, UI.R.md)
	UI.Pad(f, 10, 14)
	UI.List(f, 8)
	local head = UI.Frame(f, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0 })
	UI.Text(head, label, { Name = "Label", Size = UDim2.new(0.6, 0, 1, 0), TextColor3 = T.text, TextSize = 15, Font = T.semi, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd })
	local nameText = UI.Text(head, "", { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, 0, 1, 0), Face = "displayMed", TextSize = 17,
		TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local holder = UI.Frame(f, { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	UI.Grid(holder, size, size, 8)
	holder:FindFirstChildOfClass("UIGridLayout").HorizontalAlignment = Enum.HorizontalAlignment.Left
	local buttons = {}
	local function refresh(idx)
		for i, b in ipairs(buttons) do
			local on = i == idx
			local s = b:FindFirstChild("Ring")
			if s then
				s.Color = on and T.gold or Color3.new(1, 1, 1)
				s.Transparency = on and 0 or 0.85
				s.Thickness = on and 3 or 1
			end
			local tick = b:FindFirstChild("Tick")
			if tick then
				tick.Visible = on
			end
		end
		local names = opts.names
		nameText.Text = idx and names and names[idx] or (idx and "" or "Custom")
	end
	for i, col in ipairs(colors) do
		local c = toColor(col)
		local b = UI.New("TextButton", { Name = "Swatch" .. i, Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = c, LayoutOrder = i, Parent = holder })
		UI.Corner(b, math.floor(size / 2))
		UI.New("UIStroke", { Name = "Ring", Color = Color3.new(1, 1, 1), Transparency = 0.85, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
		local tick = UI.Icon(b, "check", math.floor(size * 0.45), UI.InkOn(c), { Name = "Tick", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		tick.Visible = false
		UI.Hover(b, { radius = math.floor(size / 2), amount = 0.8 })
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
	-- gamepad: D-pad left / right turns the hue (a washed-out colour takes some saturation so the turn
	-- shows), A steps the brightness down and wraps back to full
	registerNudge(f, function(d)
		if d == 0 then
			v = v <= 0.3 and 1 or math.max(0.25, v - 0.25)
		else
			h = (h + d / 24) % 1
			if s < 0.15 then
				s = 0.6
			end
		end
		render(true)
	end)
	padRow(f, hitW, hitB)
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
	UI.SetTextSize(box, 15)
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
	local function pick(name, animate)
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
			pick(name, true)
			onSelect(name)
		end)
	end
	pick(current, false)
	return bar, function(name)
		pick(name, true)
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
