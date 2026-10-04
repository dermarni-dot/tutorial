-- UI: helper library for building the game's interface in code
-- (windows, cards, buttons, sliders, a colour wheel, toggles, cyclers, tabs, toasts).
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = {}

UI.Theme = {
	bg = Color3.fromRGB(14, 14, 18),
	panel = Color3.fromRGB(24, 24, 30),
	panel2 = Color3.fromRGB(36, 36, 44),
	line = Color3.fromRGB(62, 62, 74),
	text = Color3.fromRGB(240, 240, 245),
	sub = Color3.fromRGB(160, 160, 175),
	gold = Color3.fromRGB(255, 196, 40),
	red = Color3.fromRGB(220, 40, 45),
	blue = Color3.fromRGB(50, 110, 240),
	green = Color3.fromRGB(60, 200, 110),
	orange = Color3.fromRGB(240, 140, 40),
	font = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBlack,
	semi = Enum.Font.GothamBold,
}
local T = UI.Theme

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

function UI.Stroke(inst, color, thickness)
	UI.New("UIStroke", { Color = color or T.line, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst })
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

function UI.Frame(parent, props)
	props = props or {}
	props.Parent = parent
	if props.BackgroundColor3 == nil then
		props.BackgroundColor3 = T.panel
	end
	props.BorderSizePixel = 0
	return UI.New("Frame", props)
end

function UI.Text(parent, text, props)
	props = props or {}
	props.Parent = parent
	props.Text = text
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or T.text
	props.Font = props.Font or T.font
	props.TextSize = props.TextSize or 16
	props.TextWrapped = props.TextWrapped ~= false
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.RichText = props.RichText or false
	if props.Size == nil then
		-- full-width label that grows downward when its text wraps
		props.Size = UDim2.new(1, 0, 0, (props.TextSize or 16) + 6)
		props.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.Y
	end
	return UI.New("TextLabel", props)
end

function UI.Button(parent, text, props, onClick)
	props = props or {}
	props.Parent = parent
	props.Text = text
	props.AutoButtonColor = props.AutoButtonColor ~= false
	props.BackgroundColor3 = props.BackgroundColor3 or T.panel2
	props.TextColor3 = props.TextColor3 or T.text
	props.Font = props.Font or T.bold
	props.TextSize = props.TextSize or 16
	props.TextWrapped = true
	props.Size = props.Size or UDim2.new(0, 160, 0, 38)
	props.BorderSizePixel = 0
	local b = UI.New("TextButton", props)
	UI.Corner(b, 6)
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
	props.ScrollBarThickness = 6
	props.ScrollBarImageColor3 = T.gold
	props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	props.CanvasSize = UDim2.new()
	props.ScrollingDirection = Enum.ScrollingDirection.Y
	return UI.New("ScrollingFrame", props)
end

-- horizontal bar; returns frame and setter(fraction, color?)
function UI.Bar(parent, props, color)
	local bg = UI.Frame(parent, props)
	bg.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	UI.Corner(bg, 4)
	local fill = UI.Frame(bg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color or T.green })
	UI.Corner(fill, 4)
	local function set(f, c)
		fill.Size = UDim2.fromScale(math.clamp(f, 0, 1), 1)
		if c then
			fill.BackgroundColor3 = c
		end
	end
	return bg, set, fill
end

-- label + bar + value text in one row
function UI.StatRow(parent, label, value, max, color, valueText)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 })
	UI.Text(f, label, { Size = UDim2.new(0.34, 0, 1, 0), TextSize = 14, AutomaticSize = Enum.AutomaticSize.None })
	local _, set = UI.Bar(f, { Position = UDim2.new(0.34, 0, 0, 5), Size = UDim2.new(0.5, 0, 0, 12) }, color)
	set((value or 0) / (max or 100))
	UI.Text(f, valueText or tostring(math.floor(value or 0)), { Position = UDim2.new(0.86, 0, 0, 0), Size = UDim2.new(0.14, 0, 1, 0), TextSize = 14, Font = T.semi, AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right })
	return f, set
end

function UI.Clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if not (c:IsA("UIListLayout") or c:IsA("UIPadding") or c:IsA("UIGridLayout") or c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UISizeConstraint")) then
			c:Destroy()
		end
	end
end

------------------------------------------------------------------------
-- Windows & cards
------------------------------------------------------------------------
-- returns shade, win, body (scrolling list area) ; opts = { side = "left", noShade, onClose, scroll = false }
function UI.Window(gui, name, w, h, title, opts)
	opts = opts or {}
	local old = gui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local shade = UI.Frame(gui, { Name = name, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = opts.noShade and 1 or 0.45, ZIndex = opts.z or 10 })
	if opts.noShade then
		shade.Active = false
	else
		shade.Active = true
	end
	local win = UI.Frame(shade, { Name = "Win", BackgroundColor3 = T.bg, Size = UDim2.new(0.96, 0, 0.92, 0) })
	if opts.side == "left" then
		win.AnchorPoint = Vector2.new(0, 0.5)
		win.Position = UDim2.new(0, 16, 0.5, 0)
		win.Size = UDim2.new(0.46, 0, 0.92, 0)
	elseif opts.side == "right" then
		win.AnchorPoint = Vector2.new(1, 0.5)
		win.Position = UDim2.new(1, -16, 0.5, 0)
		win.Size = UDim2.new(0.42, 0, 0.92, 0)
	else
		win.AnchorPoint = Vector2.new(0.5, 0.5)
		win.Position = UDim2.fromScale(0.5, 0.5)
	end
	win.Active = true
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(w, h), MinSize = Vector2.new(math.min(w, 300), math.min(h, 220)), Parent = win })
	UI.Corner(win, 12)
	UI.Stroke(win, T.gold, 2)
	if title then
		UI.Text(win, title, { Name = "Title", Font = T.bold, TextSize = 24, TextColor3 = T.gold, Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -80, 0, 32), AutomaticSize = Enum.AutomaticSize.None, TextScaled = false })
	end
	if opts.onClose then
		UI.Button(win, "X", { Name = "Close", Size = UDim2.fromOffset(38, 34), Position = UDim2.new(1, -48, 0, 10), BackgroundColor3 = T.red }, function()
			opts.onClose()
		end)
	end
	local body
	local top = title and 50 or 12
	local bottom = opts.footer and (opts.footer + 8) or 12
	if opts.scroll ~= false then
		body = UI.Scroll(win, { Name = "Body", Position = UDim2.fromOffset(16, top), Size = UDim2.new(1, -32, 1, -(top + bottom)) })
		UI.List(body, 8)
		UI.Pad(body, 2, 4)
	else
		body = UI.Frame(win, { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, top), Size = UDim2.new(1, -32, 1, -(top + bottom)) })
	end
	return shade, win, body
end

function UI.Card(parent, props)
	local f = UI.Frame(parent, { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = (props and props.color) or T.panel, LayoutOrder = props and props.order or 0 })
	UI.Corner(f, 8)
	UI.Pad(f, 10)
	UI.List(f, 5)
	if props and props.stroke then
		UI.Stroke(f, props.stroke, 2)
	end
	return f
end

function UI.Line(parent, text, props)
	props = props or {}
	props.AutomaticSize = Enum.AutomaticSize.Y
	props.Size = props.Size or UDim2.new(1, 0, 0, 0)
	return UI.Text(parent, text, props)
end

function UI.Header(parent, text, color)
	return UI.Line(parent, text, { Font = T.bold, TextSize = 18, TextColor3 = color or T.gold })
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

-- slider row: returns frame, setValue(v)
function UI.Slider(parent, label, min, max, value, step, onChange, fmt)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = T.panel })
	UI.Corner(f, 6)
	UI.Text(f, label, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.36, -10, 1, 0), TextColor3 = T.sub, TextSize = 14, AutomaticSize = Enum.AutomaticSize.None })
	local track = UI.Frame(f, { Position = UDim2.new(0.36, 0, 0.5, -3), Size = UDim2.new(0.5, -10, 0, 6), BackgroundColor3 = Color3.fromRGB(12, 12, 16), Active = true })
	UI.Corner(track, 3)
	local fill = UI.Frame(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.gold })
	UI.Corner(fill, 3)
	local knob = UI.Frame(track, { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = T.text })
	UI.Corner(knob, 8)
	local hit = UI.New("TextButton", { Parent = track, Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 16, 0, 30), Position = UDim2.new(0, -8, 0.5, -15) })
	local valText = UI.Text(f, "", { Position = UDim2.new(0.86, 0, 0, 0), Size = UDim2.new(0.14, -8, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Font = T.semi, TextSize = 14, AutomaticSize = Enum.AutomaticSize.None })
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

-- on/off toggle row
function UI.Toggle(parent, label, value, onChange)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = T.panel })
	UI.Corner(f, 6)
	UI.Text(f, label, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.7, -10, 1, 0), TextColor3 = T.sub, TextSize = 14, AutomaticSize = Enum.AutomaticSize.None })
	local state = value and true or false
	local b
	b = UI.Button(f, "", { Size = UDim2.fromOffset(84, 28), Position = UDim2.new(1, -94, 0.5, -14), TextSize = 14 }, function()
		state = not state
		b.Text = state and "ON" or "OFF"
		b.BackgroundColor3 = state and T.green or T.panel2
		if onChange then
			onChange(state)
		end
	end)
	b.Text = state and "ON" or "OFF"
	b.BackgroundColor3 = state and T.green or T.panel2
	return f
end

-- "< value >" cycler over a list; display(v) formats the value
function UI.Cycler(parent, label, list, value, onChange, display)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = T.panel })
	UI.Corner(f, 6)
	UI.Text(f, label, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.36, -10, 1, 0), TextColor3 = T.sub, TextSize = 14, AutomaticSize = Enum.AutomaticSize.None })
	local cur = value
	local val = UI.Text(f, "", { Position = UDim2.new(0.36, 38, 0, 0), Size = UDim2.new(0.64, -86, 1, 0), Font = T.semi, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None })
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
	UI.Button(f, "<", { Size = UDim2.fromOffset(32, 30), Position = UDim2.new(0.36, 0, 0.5, -15) }, function()
		step(-1)
	end)
	UI.Button(f, ">", { Size = UDim2.fromOffset(32, 30), Position = UDim2.new(1, -40, 0.5, -15) }, function()
		step(1)
	end)
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
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel })
	UI.Corner(f, 6)
	UI.Pad(f, 6, 10)
	UI.List(f, 4)
	UI.Text(f, label, { TextColor3 = T.sub, TextSize = 14 })
	local holder = UI.Frame(f, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Grid(holder, 28, 28, 5)
	local buttons = {}
	local function refresh(idx)
		for i, b in ipairs(buttons) do
			local s = b:FindFirstChildOfClass("UIStroke")
			s.Color = i == idx and T.gold or T.line
			s.Thickness = i == idx and 3 or 1
		end
	end
	for i, col in ipairs(colors) do
		local b = UI.Button(holder, "", { BackgroundColor3 = toColor(col), LayoutOrder = i }, function()
			refresh(i)
			if onPick then
				onPick({ col[1], col[2], col[3] }, i)
			end
		end)
		UI.Stroke(b, T.line, 1)
		buttons[i] = b
	end
	refresh(selected)
	return f, refresh
end

-- colour wheel (hue around, saturation outwards) + brightness slider
function UI.ColorWheel(parent, label, rgb, onChange)
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 214), BackgroundColor3 = T.panel })
	UI.Corner(f, 6)
	UI.Text(f, label, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(0.4, 0, 0, 20), TextColor3 = T.sub, TextSize = 14, AutomaticSize = Enum.AutomaticSize.None })
	local color = toColor(rgb or { 200, 30, 30 })
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
	UI.Corner(preview, 8)
	UI.Stroke(preview, T.line, 1)
	-- brightness slider with a gradient track
	local track = UI.Frame(f, { Position = UDim2.new(0, R * 2 + 28, 0, 112), Size = UDim2.new(1, -(R * 2 + 44), 0, 14), BackgroundColor3 = Color3.new(1, 1, 1), Active = true })
	UI.Corner(track, 4)
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
		local cx, cy = wheel.AbsolutePosition.X + R, wheel.AbsolutePosition.Y + R
		local dx, dy = pos.X - cx, cy - pos.Y
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
	local f = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = T.panel })
	UI.Corner(f, 6)
	UI.Text(f, label, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.36, -10, 1, 0), TextColor3 = T.sub, TextSize = 14, AutomaticSize = Enum.AutomaticSize.None })
	local box = UI.New("TextBox", {
		Parent = f, Text = value or "", PlaceholderText = placeholder or "", ClearTextOnFocus = false,
		Position = UDim2.new(0.36, 0, 0, 5), Size = UDim2.new(0.64, -8, 0, 30), BackgroundColor3 = T.panel2,
		TextColor3 = T.text, PlaceholderColor3 = T.sub, Font = T.font, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
	})
	UI.Corner(box, 6)
	UI.Pad(box, 0, 8)
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

-- horizontal tab bar; returns frame and select(name)
function UI.Tabs(parent, names, current, onSelect, props)
	local bar = UI.Frame(parent, props or { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34) })
	bar.BackgroundTransparency = 1
	UI.List(bar, 5, true)
	local buttons = {}
	local function select(name)
		for n, b in pairs(buttons) do
			b.BackgroundColor3 = n == name and T.gold or T.panel2
			b.TextColor3 = n == name and T.bg or T.text
		end
	end
	for i, name in ipairs(names) do
		buttons[name] = UI.Button(bar, name, { Size = UDim2.new(1 / #names, -5, 1, 0), TextSize = 13, LayoutOrder = i }, function()
			select(name)
			onSelect(name)
		end)
	end
	select(current)
	return bar, select
end

------------------------------------------------------------------------
-- Toast notifications
------------------------------------------------------------------------
local toastHolder
function UI.Toast(gui, text, color, duration)
	if not toastHolder or not toastHolder.Parent then
		toastHolder = UI.Frame(gui, { Name = "Toasts", BackgroundTransparency = 1, Size = UDim2.new(0, 380, 1, -140), Position = UDim2.new(0.5, -190, 0, 70), ZIndex = 50 })
		UI.List(toastHolder, 6, false, Enum.HorizontalAlignment.Center)
	end
	local f = UI.Frame(toastHolder, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.bg, BackgroundTransparency = 0.08, ZIndex = 50 })
	UI.Corner(f, 8)
	UI.Stroke(f, color or T.gold, 2)
	UI.Pad(f, 9)
	local label = UI.Text(f, text, { TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), ZIndex = 51, Font = T.semi, TextSize = 15 })
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
			TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.4)
			f:Destroy()
		end
	end)
end

return UI
