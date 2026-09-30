-- UI (ModuleScript) — StarterPlayerScripts.CityClient.UI
-- AI City's look: colors, fonts, and helpers for building the interface
-- (rounded panels, buttons that bounce, windows that pop open, bars...).

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local UI = {}
local Icons = require(script.Parent:WaitForChild("Icons"))
UI.Icons = Icons

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
UI.rgb = rgb

UI.C = {
	Bg = rgb(16, 18, 28),
	Panel = rgb(24, 27, 41),
	Panel2 = rgb(34, 38, 57),
	Panel3 = rgb(46, 51, 76),
	Line = rgb(64, 70, 100),
	Text = rgb(242, 244, 252),
	Sub = rgb(160, 168, 198),
	Dim = rgb(110, 116, 145),
	Gold = rgb(255, 196, 72),
	Blue = rgb(84, 150, 255),
	Green = rgb(78, 210, 132),
	Red = rgb(240, 78, 88),
	Pink = rgb(255, 110, 170),
	Purple = rgb(160, 110, 255),
	Orange = rgb(255, 140, 60),
	Teal = rgb(60, 200, 200),
	White = rgb(255, 255, 255),
}
UI.KIND_COLORS = { civic = UI.C.Blue, work = UI.C.Orange, store = UI.C.Pink, fun = UI.C.Green, home = UI.C.Sub }

UI.Font = Enum.Font.GothamMedium
UI.Bold = Enum.Font.GothamBold
UI.Black = Enum.Font.GothamBlack
UI.Title = Enum.Font.FredokaOne

-- Instance.new with properties and children
-- Phones (touch only) and small screens get the compact layout
function UI.Compact()
	local UIS = game:GetService("UserInputService")
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	local small = vp ~= nil and vp.Y ~= nil and vp.Y > 0 and vp.Y < 520
	return (UIS.TouchEnabled and not UIS.KeyboardEnabled) or small
end

-- How much a frame (sized in pixels) must shrink to fit on the screen,
-- counting its ScreenGui's own UIScale (1 = it already fits)
function UI.FitScale(frame, margin)
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	if not vp or not vp.X or vp.X <= 0 then
		return 1
	end
	local gui = frame:FindFirstAncestorOfClass("ScreenGui")
	local s = gui and gui:FindFirstChildOfClass("UIScale")
	local k = s and s.Scale or 1
	local w = frame.AbsoluteSize.X
	local h = frame.AbsoluteSize.Y
	local size = frame.Size
	if size and size.X and size.X.Offset > 0 then
		w, h = size.X.Offset * k, size.Y.Offset * k
	end
	margin = margin or 16
	-- (Roblox's top bar takes about 36 pixels)
	return math.min(1, (vp.X - margin) / math.max(1, w), (vp.Y - margin - 40) / math.max(1, h))
end

function UI.new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.corner(obj, radius)
	return UI.new("UICorner", { CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius or 10), Parent = obj })
end

function UI.stroke(obj, color, thickness, transparency)
	return UI.new("UIStroke", { Color = color or UI.C.Line, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = obj })
end

function UI.pad(obj, all, top, right, bottom, left)
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, top or all or 0),
		PaddingRight = UDim.new(0, right or all or 0),
		PaddingBottom = UDim.new(0, bottom or all or 0),
		PaddingLeft = UDim.new(0, left or all or 0),
		Parent = obj,
	})
end

function UI.list(obj, direction, padding, hAlign, vAlign)
	return UI.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = obj,
	})
end

function UI.gradient(obj, c1, c2, rotation, transparency)
	return UI.new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rotation or 90, Transparency = transparency, Parent = obj })
end

function UI.tween(obj, seconds, props, style, direction)
	local t = TweenService:Create(obj, TweenInfo.new(seconds or 0.2, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function UI.text(parent, text, size, font, color, props)
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text or "",
		TextSize = size or 14,
		Font = font or UI.Font,
		TextColor3 = color or UI.C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, (size or 14) + 6),
		RichText = true,
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	return label
end

-- Little sounds (built-in Roblox sounds)
local SOUNDS = {
	click = "rbxasset://sounds/electronicpingshort.wav",
	pop = "rbxasset://sounds/button.wav",
	punch = "rbxasset://sounds/swordslash.wav",
	notify = "rbxasset://sounds/electronicpingshort.wav",
	coin = "rbxasset://sounds/electronicpingshort.wav",
	splash = "rbxasset://sounds/impact_water.mp3",
}
UI.Muted = false
function UI.sound(name, volume, speed)
	if UI.Muted or not SOUNDS[name] then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = SOUNDS[name]
	s.Volume = volume or 0.35
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
end

-- A panel: a rounded, slightly see-through box with a thin border
function UI.panel(parent, props)
	local frame = UI.new("Frame", {
		BackgroundColor3 = UI.C.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		if k ~= "Radius" and k ~= "Shadow" and k ~= "Glass" then -- our own options, not Frame properties
			frame[k] = v
		end
	end
	UI.corner(frame, (props and props.Radius) or 14)
	UI.stroke(frame, UI.C.Line, 1, 0.45)
	-- a soft top-to-bottom shade gives panels some depth
	UI.gradient(frame, UI.C.White, UI.rgb(196, 200, 222), 90)
	return frame
end

-- A button that grows on hover and squishes on click
function UI.button(parent, text, props, onClick)
	props = props or {}
	local color = props.Color or UI.C.Panel3
	local button = UI.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = text or "",
		TextColor3 = props.TextColor or UI.C.Text,
		Font = props.Font or UI.Bold,
		TextSize = props.TextSize or 15,
		Size = props.Size or UDim2.fromOffset(120, 38),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		TextWrapped = props.Wrapped or false,
		RichText = true,
		Parent = parent,
	})
	if props.XAlign then
		button.TextXAlignment = props.XAlign
	end
	UI.corner(button, props.Radius or 10)
	local stroke = UI.stroke(button, color:Lerp(UI.C.White, 0.25), 1, 0.5)
	UI.gradient(button, UI.C.White, UI.rgb(200, 200, 215), 90)
	local scale = UI.new("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1.04 })
		UI.tween(button, 0.12, { BackgroundColor3 = color:Lerp(UI.C.White, 0.12) })
		stroke.Transparency = 0.2
	end)
	button.MouseLeave:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1 })
		UI.tween(button, 0.12, { BackgroundColor3 = color })
		stroke.Transparency = 0.5
	end)
	button.MouseButton1Down:Connect(function()
		UI.tween(scale, 0.06, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1.04 }, Enum.EasingStyle.Back)
	end)
	if onClick then
		button.Activated:Connect(function()
			UI.sound("pop", 0.25, 1.1)
			onClick()
		end)
	end
	-- second return value: change the button's color later
	local function setColor(c)
		color = c
		button.BackgroundColor3 = c
		stroke.Color = c:Lerp(UI.C.White, 0.25)
	end
	return button, setColor
end

-- A small rounded label with an icon (chips on the HUD)
function UI.chip(parent, text, color, props)
	local chip = UI.new("TextLabel", {
		BackgroundColor3 = color or UI.C.Panel3,
		BackgroundTransparency = 0.1,
		Text = text or "",
		TextColor3 = UI.C.Text,
		Font = UI.Bold,
		TextSize = 13,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		RichText = true,
		Parent = parent,
	})
	UI.corner(chip, 12)
	UI.pad(chip, 0, 0, 10, 0, 10)
	for k, v in pairs(props or {}) do
		chip[k] = v
	end
	return chip
end

-- A progress bar: returns the frame and a setter (0..1, animated)
function UI.bar(parent, color, height, props)
	local back = UI.new("Frame", { BackgroundColor3 = UI.C.Bg, BackgroundTransparency = 0.2, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, height or 8), Parent = parent })
	UI.corner(back, (height or 8) / 2)
	local fill = UI.new("Frame", { BackgroundColor3 = color or UI.C.Green, BorderSizePixel = 0, Size = UDim2.fromScale(0.5, 1), Parent = back })
	UI.corner(fill, (height or 8) / 2)
	UI.gradient(fill, UI.C.White, UI.C.White:Lerp(color or UI.C.Green, 0.6), 0, NumberSequence.new(0.6, 0))
	for k, v in pairs(props or {}) do
		back[k] = v
	end
	local function set(v, c)
		UI.tween(fill, 0.4, { Size = UDim2.fromScale(math.clamp(v, 0, 1), 1) })
		if c then
			fill.BackgroundColor3 = c
		end
	end
	return back, set, fill
end

-- A scrolling list that grows with its content
function UI.scroll(parent, props)
	local s = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = UI.C.Line,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		s[k] = v
	end
	return s
end

-- The blur behind open windows
local blur
local openCount = 0
local function setBlur(on)
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "CityUIBlur"
		blur.Size = 0
		blur.Parent = Lighting
	end
	openCount = math.max(0, openCount + (if on then 1 else -1))
	UI.tween(blur, 0.25, { Size = if openCount > 0 then 10 else 0 })
end

-- A window: a header with an icon, a title and a close button, and a body.
-- Returns { Frame, Body, Open(), Close(), IsOpen(), OnClose }
local windows = {}
function UI.window(screen, title, icon, size, accent)
	accent = accent or UI.C.Gold
	local win = {}
	local frame = UI.panel(screen, {
		Name = title .. "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size or UDim2.fromOffset(640, 460),
		Visible = false,
		ZIndex = 20,
		BackgroundTransparency = 0.02,
		Radius = 18,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(1100, 760), Parent = frame })
	local scale = UI.new("UIScale", { Scale = 0.9, Parent = frame })
	local header = UI.new("Frame", { BackgroundColor3 = UI.C.Panel2, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 54), ZIndex = 21, Parent = frame })
	UI.corner(header, 18)
	UI.new("Frame", { BackgroundColor3 = UI.C.Panel2, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -18), ZIndex = 21, Parent = header })
	UI.new("Frame", { BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, 0), ZIndex = 22, Parent = header })
	-- the header glows faintly in the window's color
	UI.gradient(header, accent:Lerp(UI.C.White, 0.2), UI.C.White, 0, NumberSequence.new(0.2, 0))
	local iconLabel = UI.text(header, "", 26, UI.Font, UI.C.Text, { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(14, 7), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
	-- the window's icon: a little app badge in the window's color (or an emoji if there's no icon for it)
	local badge, glyph = Icons.Badge(header, Icons.Has(icon) and icon or "help", 38, accent:Lerp(UI.C.Panel, 0.15), { Position = UDim2.fromOffset(15, 8), ZIndex = 22 })
	function win.SetIcon(name)
		if Icons.Has(name) then
			Icons.Set(glyph, name)
			badge.Visible = true
			iconLabel.Text = ""
		else
			badge.Visible = false
			iconLabel.Text = name or ""
		end
	end
	win.SetIcon(icon)
	local titleLabel = UI.text(header, title, 22, UI.Title, UI.C.Text, { Size = UDim2.new(1, -140, 0, 30), Position = UDim2.fromOffset(60, 12), ZIndex = 22 })
	local close = UI.button(header, "", { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -46, 0, 9), Color = UI.C.Panel3, TextSize = 16 }, function()
		win.Close()
	end)
	Icons.Glyph(close, "close", 16, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Hole = UI.C.Panel3 })
	close.ZIndex = 23
	local body = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 1, -58), ZIndex = 21, Parent = frame })
	UI.pad(body, 14)
	win.Frame, win.Body, win.Header, win.Title, win.Icon = frame, body, header, titleLabel, iconLabel
	local open = false
	function win.IsOpen()
		return open
	end
	function win.Open()
		if open then
			return
		end
		-- one big window at a time
		for _, other in ipairs(windows) do
			if other ~= win and other.IsOpen() and not other.Keep then
				other.Close()
			end
		end
		open = true
		frame.Visible = true
		-- always fits on the screen (phones too)
		local fit = UI.FitScale(frame)
		scale.Scale = 0.85 * fit
		UI.tween(scale, 0.28, { Scale = fit }, Enum.EasingStyle.Back)
		setBlur(true)
		UI.sound("click", 0.3, 1.2)
		if win.OnOpen then
			task.spawn(win.OnOpen)
		end
		-- controllers: select the first button (see Gamepad)
		if UI.OnOpen then
			UI.OnOpen(frame)
		end
	end
	function win.Close()
		if not open then
			return
		end
		open = false
		setBlur(false)
		UI.tween(scale, 0.15, { Scale = 0.9 })
		task.delay(0.15, function()
			if not open then
				frame.Visible = false
			end
		end)
		if win.OnClose then
			task.spawn(win.OnClose)
		end
	end
	function win.Toggle()
		if open then
			win.Close()
		else
			win.Open()
		end
	end
	table.insert(windows, win)
	return win
end

function UI.AnyOpen()
	for _, w in ipairs(windows) do
		if w.IsOpen() then
			return true
		end
	end
	return false
end

function UI.closeAll()
	local any = false
	for _, w in ipairs(windows) do
		if w.IsOpen() then
			w.Close()
			any = true
		end
	end
	return any
end

-- Hearts for how much someone likes you (-100..100)
function UI.hearts(opinion)
	local n = math.floor(math.abs(opinion) / 20 + 0.5)
	if opinion >= 0 then
		return string.rep("❤️", math.min(5, n)) .. string.rep("🤍", 5 - math.min(5, n))
	end
	return string.rep("💔", math.min(5, n)) .. string.rep("🤍", 5 - math.min(5, n))
end

function UI.moodEmoji(mood)
	if mood >= 80 then
		return "😄"
	elseif mood >= 62 then
		return "🙂"
	elseif mood >= 45 then
		return "😐"
	elseif mood >= 30 then
		return "😕"
	elseif mood >= 18 then
		return "😢"
	end
	return "😠"
end

function UI.moodColor(mood)
	if mood >= 62 then
		return UI.C.Green
	elseif mood >= 40 then
		return UI.C.Gold
	end
	return UI.C.Red
end

function UI.formatHour(h)
	h = h % 24
	local hour = math.floor(h)
	local minute = math.floor((h - hour) * 60)
	local suffix = if hour >= 12 then "PM" else "AM"
	local shown = hour % 12
	if shown == 0 then
		shown = 12
	end
	return string.format("%d:%02d", shown, minute), suffix
end

function UI.commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return UI
