-- Services: the gym's service windows.
--  Barber Shop  - grouped styles, hair types, hairline / line-up, part, recolour / dye / highlights,
--                 beards + beard colour; a fresh cut resets growth (previewed live); prices from
--                 Looks.BarberPrice (the same function the server charges with)
--  Locker Room  - trunks, socks, shoes, laces, wraps + wrap pattern, mouthguard, robe and glove
--                 customization (glove options unlock with better gloves: trim, stitching, finishes,
--                 metallic, logos, name & nickname embroidery, brand on custom gloves)
--  Nutrition Bar, water coolers, and Sleep (ends the day with a day transition)
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))
local UI = require(Shared:WaitForChild("UI"))
local State = require(script.Parent:WaitForChild("State"))
local T = UI.Theme

local Services = {}

local function deepcopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = deepcopy(v)
	end
	return out
end

local function sameColor(a, b)
	return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function paletteIndex(palette, c)
	for i, p in ipairs(palette) do
		if sameColor(p, c) then
			return i
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Customization session shared by the barber and the locker room
------------------------------------------------------------------------
local session -- { section, look, shade, win, body, dirty, conn, camConn, saved }

-- a soft client-only key light on the face while sitting in the barber chair
local function keyLight(on)
	local cam = workspace.CurrentCamera
	local old = cam and cam:FindFirstChild("BarberKeyLight")
	if old then
		old:Destroy()
	end
	if not (on and cam) then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = "BarberKeyLight"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	local key = Instance.new("SpotLight")
	key.Brightness = 1.3
	key.Range = 9
	key.Angle = 50
	key.Color = Color3.fromRGB(255, 238, 220)
	key.Face = Enum.NormalId.Front
	key.Parent = p
	p.Parent = cam
	return p
end

local function closeSession(save)
	local s = session
	if not s then
		return
	end
	session = nil
	State.windows.Custom = nil
	State.HidePrompts("Custom", false)
	State.HideHud("Custom", false)
	if s.conn then
		s.conn:Disconnect()
	end
	if s.camConn then
		s.camConn:Disconnect()
	end
	keyLight(false)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	local _, hum = State.char()
	if hum then
		hum.WalkSpeed = 16
	end
	State.SetAnimate(true)
	if s.shade then
		s.shade:Destroy()
	end
	if not save then
		task.spawn(State.req, "EndCustomize")
	end
end

local function sessionCamera(head)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local yaw = 0
	local light = head and keyLight(true) or nil
	return RunService.RenderStepped:Connect(function(dt)
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local char, _, root = State.char()
		local h = char and char:FindFirstChild("Head")
		if not (root and h) then
			return
		end
		if session and session.spin then
			yaw += session.spin * dt * 2.5
		end
		local rot = CFrame.Angles(0, yaw, 0) * root.CFrame.Rotation
		local look, right = rot.LookVector, rot.RightVector
		local goal
		if head then
			local t = h.Position
			goal = CFrame.lookAt(t + look * 4.2 + right * 1.6 + Vector3.new(0, 0.3, 0), t + right * 1.2)
			if light and light.Parent then
				light.CFrame = CFrame.lookAt(t + look * 2.2 + right * 1.3 + Vector3.new(0, 1.1, 0), t)
			end
		else
			local t = root.Position + Vector3.new(0, 0.6, 0)
			goal = CFrame.lookAt(t + look * 10 + right * 3.6 + Vector3.new(0, 0.8, 0), t + right * 2.8)
		end
		cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 7, 0, 1))
	end)
end

local function openSession(section, title, width, onRender, footerFn)
	if session then
		closeSession(false)
	end
	if State.busy() then
		State.toast("Finish what you're doing first.", T.red)
		return nil
	end
	local P = State.P
	if not (P and P.created) then
		return nil
	end
	State.closeAll("Custom")
	local r = State.req("BeginCustomize", section)
	if not r.ok then
		State.toast(r.err or "Not available right now", T.red)
		return nil
	end
	local s = { section = section, look = deepcopy(P.appearance), dirty = false, lastSent = 0 }
	session = s
	State.windows.Custom = function()
		closeSession(false)
	end
	s.shade, s.win, s.body = UI.Window(State.gui, "Custom", width, 720, title, { side = "left", noShade = true, footer = 56, onClose = function()
		closeSession(false)
	end })
	s.footer = UI.Frame(s.win, { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 1, -56), Size = UDim2.new(1, -32, 0, 44) })
	-- turntable buttons
	local turn = UI.Frame(s.shade, { Name = "Turntable", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -24), Size = UDim2.fromOffset(0, 48), AutomaticSize = Enum.AutomaticSize.X })
	UI.Glass(turn, { transparency = 0.15, radius = 24 })
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = turn })
	UI.List(turn, 6, true, Enum.HorizontalAlignment.Center)
	UI.Text(turn, "ROTATE", { Font = T.semi, TextSize = 10, TextColor3 = T.sub, Size = UDim2.fromOffset(50, 48), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, LayoutOrder = 0 })
	for i, d in ipairs({ { "<", 1 }, { ">", -1 } }) do
		local b = UI.Button(turn, "", { Size = UDim2.fromOffset(36, 36), LayoutOrder = i })
		b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 18)
		UI.Icon(b, d[1] == "<" and "left" or "right", 14, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		b.MouseButton1Down:Connect(function()
			if session then
				session.spin = d[2]
			end
		end)
		b.MouseButton1Up:Connect(function()
			if session then
				session.spin = 0
			end
		end)
		b.MouseLeave:Connect(function()
			if session then
				session.spin = 0
			end
		end)
	end
	local _, hum = State.char()
	if hum then
		hum.WalkSpeed = 0
	end
	State.SetAnimate(false)
	s.camConn = sessionCamera(section == "barber")
	s.render = function()
		if not (s.body and s.body.Parent) then
			return
		end
		local y = s.body.CanvasPosition
		UI.Clear(s.body)
		local ok, err = pcall(onRender, s)
		if not ok then
			warn("[Services]", err)
		end
		UI.Clear(s.footer)
		footerFn(s)
		task.defer(function()
			if s.body and s.body.Parent then
				s.body.CanvasPosition = y
			end
		end)
	end
	s.preview = function()
		s.dirty = true
		if s.updateFooter then
			s.updateFooter()
		end
	end
	s.conn = RunService.Heartbeat:Connect(function()
		if s.dirty and os.clock() - s.lastSent > 0.28 then
			s.dirty = false
			s.lastSent = os.clock()
			task.spawn(function()
				local res = State.req("PreviewLook", s.look, section == "locker" and "gloves" or "wraps", s.popts and s.popts() or nil)
				if res and res.throttled and session == s then
					s.dirty = true
				end
			end)
		end
	end)
	s.render()
	State.HidePrompts("Custom", true)
	-- the barber chair / locker is a full-screen scene: the HUD plate steps aside
	State.HideHud("Custom", true)
	if section == "locker" then
		s.preview() -- show the gloves on straight away
	end
	return s
end

local function colorField(s, parent, label, get, set, palette)
	local holder = UI.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.List(holder, 4)
	local _, refresh = UI.Swatches(holder, label, palette, paletteIndex(palette, get()), function(rgb)
		set(rgb)
		s.preview()
	end)
	local wheel
	UI.Button(holder, "Custom colour", { Size = UDim2.new(0, 150, 0, 26), TextSize = 13 }, function()
		if wheel then
			wheel:Destroy()
			wheel = nil
			return
		end
		wheel = UI.ColorWheel(holder, label .. " - colour wheel", get(), function(rgb)
			set(rgb)
			refresh(nil)
			s.preview()
		end)
	end)
end

------------------------------------------------------------------------
-- Barber
------------------------------------------------------------------------
-- the shared price function (Looks.BarberPrice) so the label always matches what the server charges
local function barberPrice(old, new)
	local ok, price = pcall(Looks.BarberPrice, old, new)
	return ok and price or 30
end

function Services.Barber()
	local opts = { cut = true, shave = false }
	local sess = openSession("barber", "BARBER SHOP", 560, function(s)
		local body = s.body
		local h = s.look.hair
		local beard = s.look.beard
		local P = State.P
		local grown = (P.appearance.hair and P.appearance.hair.growth) or 0
		local days = math.floor(grown / (Config.HairGrowthPerDay or 0.02) + 0.5)
		UI.Line(body, string.format("Big Lou: \"Sit down, champ. That's about %d day%s of growth since your last cut.\"", days, days == 1 and "" or "s"), { TextColor3 = Color3.fromRGB(255, 210, 160), TextSize = 14 })
		if not Config.BaldMode then
			UI.Cycler(body, "Hair type", Looks.HairTypeOrder, h.type, function(v)
				h.type = v
				s.preview()
			end, Looks.HairTypeName)
			for _, group in ipairs(Looks.HairStyleGroups) do
				UI.Header(body, group.name:upper())
				local grid = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
				UI.Grid(grid, UDim2.new(1 / 3, -6, 0, 30), nil, 6)
				for i, st in ipairs(group.styles) do
					UI.Button(grid, st, { LayoutOrder = i, TextSize = 13, BackgroundColor3 = h.style == st and T.gold or T.panel2, TextColor3 = h.style == st and T.bg or T.text }, function()
						h.style = st
						s.preview()
						s.render()
					end)
				end
			end
			UI.Header(body, "CUT")
			UI.Cycler(body, "Hairline", Looks.Hairlines, h.hairline or "Natural", function(v)
				h.hairline = v
				s.preview()
			end, function(v)
				return v == "Line-Up" and "Line-Up / edge-up" or v
			end)
			UI.Cycler(body, "Part", Looks.HairParts, h.part or "None", function(v)
				h.part = v
				s.preview()
			end)
			for _, sl in ipairs(Looks.HairSliders) do
				UI.Slider(body, sl.label, sl.min, sl.max, h[sl.key] or 0.5, nil, function(v)
					h[sl.key] = v
					s.preview()
				end)
			end
			UI.Toggle(body, "Fresh cut (resets hair growth)", opts.cut, function(v)
				opts.cut = v
				s.preview()
			end)
			UI.Header(body, "COLOUR")
			colorField(s, body, "Hair colour", function()
				return h.color
			end, function(c)
				h.color = c
			end, Looks.HairColors)
			UI.Toggle(body, "Highlights", h.hl, function(v)
				h.hl = v
				s.preview()
			end)
			UI.Cycler(body, "Dye pattern", Looks.DyePatterns, h.dye, function(v)
				h.dye = v
				s.preview()
			end)
			colorField(s, body, "Highlight / dye colour", function()
				return h.hcolor
			end, function(c)
				h.hcolor = c
			end, Looks.HairColors)
		end
		if s.look.gender == 1 then
			UI.Header(body, "BEARD")
			UI.Cycler(body, "Beard style", Looks.BeardStyles, beard.style, function(v)
				beard.style = v
				s.preview()
			end)
			UI.Toggle(body, "Beard matches hair colour", beard.color == nil, function(v)
				beard.color = (not v) and table.clone(h.color) or nil
				s.preview()
				s.render()
			end)
			if beard.color then
				colorField(s, body, "Beard colour", function()
					return beard.color
				end, function(c)
					beard.color = c
				end, Looks.HairColors)
			end
			UI.Toggle(body, "Shave / trim beard back", opts.shave, function(v)
				opts.shave = v
			end)
		end
		UI.Line(body, "Cut $30  -  new colour +$40  -  highlights / dye +$60  -  locs, twists & braids +$90-140  -  fades +$10  -  line-up +$15  -  new beard style +$15  -  beard colour +$20", { TextColor3 = T.sub, TextSize = 13 })
	end, function(s)
		local btn = UI.Button(s.footer, "", { Size = UDim2.new(0.62, 0, 1, 0), BackgroundColor3 = T.gold, TextColor3 = T.bg })
		s.updateFooter = function()
			btn.Text = "PAY & SAVE  " .. Config.Money(barberPrice(State.P.appearance, s.look))
		end
		s.updateFooter()
		btn.MouseButton1Click:Connect(function()
			local r = State.req("CustomizeLook", "barber", s.look, opts)
			if r.ok then
				State.toast("Looking sharp! Paid " .. Config.Money(r.price or 0) .. ".", T.green)
				closeSession(true)
			else
				State.toast(r.err or "Couldn't save", T.red)
			end
		end)
		UI.Button(s.footer, "CANCEL", { Size = UDim2.new(0.34, 0, 1, 0), Position = UDim2.new(0.66, 0, 0, 0) }, function()
			closeSession(false)
		end)
	end)
	if sess then
		-- preview the cut fresh (growth 0) or as it is now; only the head needs rebuilding
		sess.popts = function()
			return { growth = opts.cut and 0 or nil, only = { Face = true, Hair = true, Beard = true } }
		end
		sess.preview()
	end
end

------------------------------------------------------------------------
-- Locker room
------------------------------------------------------------------------
function Services.Locker()
	openSession("locker", "LOCKER ROOM", 560, function(s)
		local body = s.body
		local a, g = s.look.attire, s.look.gloves
		local P = State.P
		local pal = Looks.Palette
		local glove = Catalog.Find(Catalog.Gloves, P.gear.equipped.gloves) or Catalog.Gloves[1]
		local custom = glove.custom or {}
		UI.Button(body, "Champion kit (black & red)", { Size = UDim2.new(0, 260, 0, 34), TextSize = 14, BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
			-- black pro trunks with red trim and striped side panels, black boxing boots with red
			-- laces and soles, white socks, red gloves (colour/trim only where the gloves allow it)
			a.trunks, a.trim, a.trunkStyle = { 20, 20, 20 }, { 200, 25, 30 }, "Pro"
			a.socks, a.shoes, a.shoeStyle = { 240, 240, 240 }, { 20, 20, 20 }, "High-Top"
			a.robe, a.robeTrim = { 20, 20, 20 }, { 200, 25, 30 }
			if custom.color then
				g.color = { 200, 25, 30 }
			end
			if custom.trim then
				g.trim = { 240, 240, 240 }
			end
			s.preview()
			s.render()
		end)
		UI.Header(body, "GLOVES - " .. glove.name:upper())
		if custom.color then
			colorField(s, body, "Glove colour", function()
				return g.color
			end, function(c)
				g.color = c
			end, pal)
		end
		if custom.trim then
			colorField(s, body, "Glove trim / cuff", function()
				return g.trim
			end, function(c)
				g.trim = c
			end, pal)
		end
		if custom.stitching then
			UI.Cycler(body, "Stitching", Catalog.GloveStitching, g.stitching, function(v)
				g.stitching = v
				s.preview()
			end)
		end
		if custom.finish then
			local finishes = { "Leather", "Matte", "Patent" }
			if custom.metallic then
				table.insert(finishes, "Metallic")
			end
			UI.Cycler(body, "Finish", finishes, table.find(finishes, g.finish) and g.finish or "Leather", function(v)
				g.finish = v
				s.preview()
			end)
		end
		if custom.logo then
			UI.Cycler(body, "Logo", Catalog.GloveLogos, g.logo, function(v)
				g.logo = v
				s.preview()
			end)
		end
		if custom.brand then
			-- custom gloves can carry any maker's signature
			local own = Catalog.GearBrand("gloves", glove.id, nil)
			local brands = { "Auto" }
			for _, id in ipairs(Catalog.BrandOrder) do
				table.insert(brands, id)
			end
			UI.Cycler(body, "Brand", brands, table.find(brands, g.brand) and g.brand or "Auto", function(v)
				g.brand = v
				s.preview()
			end, function(v)
				if v == "Auto" then
					return "Own (" .. ((own and own.name) or "maker") .. ")"
				end
				local b = Catalog.Brand(v)
				return b and b.name or v
			end)
		end
		if custom.embroidery then
			UI.Toggle(body, "Embroider name (left cuff)", g.embName, function(v)
				g.embName = v
				s.preview()
			end)
			UI.Toggle(body, "Embroider nickname (right cuff)", g.embNick, function(v)
				g.embNick = v
				s.preview()
			end)
		end
		local locked = {}
		for _, k in ipairs({ "trim", "stitching", "finish", "metallic", "logo", "embroidery", "brand" }) do
			if not custom[k] then
				table.insert(locked, k)
			end
		end
		if #locked > 0 then
			UI.Line(body, "Locked on these gloves: " .. table.concat(locked, ", ") .. ". Buy better gloves in the Career Hub > Gear tab.", { TextColor3 = T.sub, TextSize = 13 })
		end
		UI.Header(body, "TRUNKS & ROBE")
		colorField(s, body, "Trunks", function()
			return a.trunks
		end, function(c)
			a.trunks = c
		end, pal)
		colorField(s, body, "Trim / waistband", function()
			return a.trim
		end, function(c)
			a.trim = c
		end, pal)
		UI.Cycler(body, "Trunk style", Catalog.TrunkStyles, a.trunkStyle, function(v)
			a.trunkStyle = v
			s.preview()
		end)
		colorField(s, body, "Robe", function()
			return a.robe
		end, function(c)
			a.robe = c
		end, pal)
		colorField(s, body, "Robe trim", function()
			return a.robeTrim
		end, function(c)
			a.robeTrim = c
		end, pal)
		UI.Header(body, "FEET, HANDS & MOUTH")
		colorField(s, body, "Socks", function()
			return a.socks
		end, function(c)
			a.socks = c
		end, pal)
		colorField(s, body, "Shoes", function()
			return a.shoes
		end, function(c)
			a.shoes = c
		end, pal)
		UI.Cycler(body, "Shoe style", Catalog.ShoeStyles, a.shoeStyle, function(v)
			a.shoeStyle = v
			s.preview()
		end)
		colorField(s, body, "Laces", function()
			return a.laces
		end, function(c)
			a.laces = c
		end, pal)
		colorField(s, body, "Hand wraps", function()
			return a.wraps
		end, function(c)
			a.wraps = c
		end, pal)
		UI.Cycler(body, "Wrap pattern", Looks.WrapPatterns, a.wrapPattern or "Solid", function(v)
			a.wrapPattern = v
			s.preview()
		end)
		colorField(s, body, "Mouthguard", function()
			return a.mouthguard
		end, function(c)
			a.mouthguard = c
		end, pal)
	end, function(s)
		UI.Button(s.footer, "SAVE", { Size = UDim2.new(0.62, 0, 1, 0), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
			local r = State.req("CustomizeLook", "locker", s.look, {})
			if r.ok then
				State.toast("New fit saved.", T.green)
				closeSession(true)
			else
				State.toast(r.err or "Couldn't save", T.red)
			end
		end)
		UI.Button(s.footer, "CANCEL", { Size = UDim2.new(0.34, 0, 1, 0), Position = UDim2.new(0.66, 0, 0, 0) }, function()
			closeSession(false)
		end)
	end)
end

------------------------------------------------------------------------
-- Nutrition bar & water
------------------------------------------------------------------------
local nutritionShade
local function closeNutrition()
	State.windows.Nutrition = nil
	if nutritionShade then
		nutritionShade:Destroy()
		nutritionShade = nil
	end
end

local function renderNutrition(body)
	local P = State.P
	UI.Clear(body)
	local c = P.condition
	-- the numbers that matter at the counter: cash, weight against the limit, body fat
	local tiles = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 64) })
	UI.Grid(tiles, UDim2.new(1 / 3, -6, 1, 0), nil, 8)
	local over = (P.weight or 0) > (P.weightLimit or math.huge)
	UI.Stat(tiles, Config.Money(P.money), "Cash", { valueColor = T.green, order = 1, scaled = true })
	UI.Stat(tiles, string.format("%.1f", P.weight or 0), string.format("lbs  ·  limit %d", P.weightLimit or 0), { valueColor = over and T.red or T.text, order = 2 })
	UI.Stat(tiles, string.format("%.1f%%", P.body.fat or 14), "Body fat", { order = 3 })
	local card = UI.Card(body)
	UI.StatRow(card, "ENERGY", c.energy, 100, T.gold)
	UI.StatRow(card, "HYDRATION", c.hydration, 100, T.blue)
	UI.StatRow(card, "NUTRITION", c.nutrition, 100, T.green)
	local function hex(col)
		return "#" .. col:ToHex()
	end
	for _, meal in ipairs(Config.Meals) do
		local locked = meal.requires and not P.owned[meal.requires]
		local row = UI.Card(body, locked and {} or (meal.price >= 150 and { stroke = T.gold } or {}))
		local head = UI.Frame(row, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
		UI.Text(head, string.upper(meal.name), { Face = "displayMed", TextSize = 20, TextColor3 = locked and T.sub or T.text, Size = UDim2.new(1, -110, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Chip(head, meal.price > 0 and Config.Money(meal.price) or "FREE", meal.price > 0 and T.gold or T.green, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), h = 24, TextSize = 12, solid = meal.price == 0 })
		local fx = {}
		local function add(text, col)
			table.insert(fx, string.format('<font color="%s">%s</font>', hex(col), text))
		end
		if meal.nutrition ~= 0 then
			add(string.format("%+d nutrition", meal.nutrition), meal.nutrition > 0 and T.green or T.red)
		end
		if meal.hydration ~= 0 then
			add(string.format("%+d hydration", meal.hydration), meal.hydration > 0 and T.blue or T.red)
		end
		if meal.energy ~= 0 then
			add(string.format("%+d energy", meal.energy), T.gold)
		end
		if meal.fat ~= 0 then
			add(meal.fat > 0 and "adds body fat" or "lean", meal.fat > 0 and T.orange or T.cyan)
		end
		if meal.gainsBuff then
			add(string.format("+%d%% training gains today", meal.gainsBuff * 100), T.purple)
		end
		if meal.muscleBuff then
			add(string.format("+%d%% muscle growth today", meal.muscleBuff * 100), T.purple)
		end
		UI.Line(row, table.concat(fx, "   ·   "), { TextSize = 13, TextColor3 = T.sub, RichText = true })
		UI.Button(row, locked and "NEEDS NUTRITIONIST" or (meal.id == "Water" and "DRINK" or "BUY & EAT"), { Size = UDim2.new(0, 190, 0, 32), TextSize = 14,
			BackgroundColor3 = locked and T.panel2 or T.gold, TextColor3 = locked and T.sub or T.bg }, function()
			if locked then
				return
			end
			local r = State.req("Eat", meal.id)
			if r.ok then
				State.toast(meal.name .. ": nutrition " .. math.floor(r.info.nutrition or 0) .. " gained", T.green)
			else
				State.toast(r.err or "Can't eat that", T.red)
			end
		end)
	end
	UI.Line(body, "Overeating turns into body fat. Running on empty burns muscle. Hydration and nutrition both multiply your training gains and improve your sleep.", { TextColor3 = T.sub, TextSize = 13 })
end

function Services.Nutrition()
	local P = State.P
	if not (P and P.created) then
		return
	end
	State.closeAll("Nutrition")
	local shade, _, body = UI.Window(State.gui, "Nutrition", 560, 640, "NUTRITION BAR", { onClose = closeNutrition })
	nutritionShade = shade
	State.windows.Nutrition = closeNutrition
	renderNutrition(body)
	local conn
	conn = State.Changed:Connect(function()
		if nutritionShade == shade and shade.Parent then
			renderNutrition(body)
		else
			conn:Disconnect()
		end
	end)
end

function Services.Water()
	local r = State.req("Eat", "Water")
	if r.ok then
		State.toast("Refreshing. Hydration " .. math.floor(r.info.hydration or 0) .. "%", Color3.fromRGB(120, 190, 255))
	else
		State.toast(r.err or "Can't drink right now", T.red)
	end
end

------------------------------------------------------------------------
-- Sleep (ends the day)
------------------------------------------------------------------------
local function dayTransition(res)
	local overlay = UI.Frame(State.gui, { Name = "Night", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 60 })
	local kicker = UI.Text(overlay, "A NEW DAY AT THE GYM", { Font = T.semi, TextSize = 14, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0.3, -24), ZIndex = 61, TextTransparency = 1, AutomaticSize = Enum.AutomaticSize.None })
	local title = UI.Text(overlay, "", { Face = "display", TextSize = 96, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 104), Position = UDim2.new(0, 0, 0.3, 0), ZIndex = 61, TextTransparency = 1, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local sub = UI.Text(overlay, "", { TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0.8, 0, 0, 0), Position = UDim2.new(0.1, 0, 0.3, 116), ZIndex = 61, TextTransparency = 1 })
	TweenService:Create(overlay, TweenInfo.new(0.7), { BackgroundTransparency = 0 }):Play()
	task.wait(0.8)
	local s = res.sleep or {}
	title.Text = "DAY " .. tostring(s.day or "?")
	local lines = { string.format("Slept well: %d%% sleep quality.", math.floor((s.quality or 0.7) * 100)) }
	if s.daysLeft then
		table.insert(lines, s.daysLeft == 0 and "FIGHT NIGHT IS HERE." or string.format("%d day%s of camp left.", s.daysLeft, s.daysLeft == 1 and "" or "s"))
	end
	for _, n in ipairs(s.notes or {}) do
		table.insert(lines, n)
	end
	sub.Text = table.concat(lines, "\n")
	TweenService:Create(kicker, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	TweenService:Create(sub, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	task.wait(2.6)
	TweenService:Create(overlay, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(kicker, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	TweenService:Create(sub, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	task.wait(0.9)
	overlay:Destroy()
end

function Services.Sleep()
	local P = State.P
	if not (P and P.created) or P.retired then
		return
	end
	if State.busy() then
		State.toast("Finish what you're doing first.", T.red)
		return
	end
	State.closeAll("Sleep")
	local shade
	local function close()
		State.windows.Sleep = nil
		if shade then
			shade:Destroy()
		end
	end
	local _, _, body
	shade, _, body = UI.Window(State.gui, "Sleep", 480, 330, "END THE DAY?", { onClose = close })
	State.windows.Sleep = close
	local c = P.condition
	local tiles = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 64) })
	UI.Grid(tiles, UDim2.new(1 / 3, -6, 1, 0), nil, 8)
	UI.Stat(tiles, tostring(P.day), "Day", { valueColor = T.gold, order = 1 })
	UI.Stat(tiles, string.format("%d%%", c.energy), "Energy", { valueColor = c.energy < 30 and T.red or T.text, order = 2 })
	UI.Stat(tiles, string.format("%d%%", c.fatigue), "Fatigue", { valueColor = c.fatigue > 60 and T.orange or T.text, order = 3 })
	UI.Line(body, "Sleep restores energy and clears fatigue. Sleep quality depends on your housing, hydration, nutrition, fatigue and injuries. Each night also counts down your fight camp, heals injuries, and your hair and beard keep growing.", { TextColor3 = T.sub, TextSize = 14 })
	if c.hydration < 40 or c.nutrition < 40 then
		UI.Line(body, "Tip: eat and drink before bed - you'll sleep better.", { TextColor3 = T.orange, TextSize = 14 })
	end
	if P.camp then
		UI.Line(body, string.format("Fight camp: %d day(s) left before fight night.", P.camp.daysLeft), { TextColor3 = T.gold, TextSize = 14 })
	end
	UI.Button(body, "SLEEP  ·  END THE DAY", { Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
		close()
		local r = State.req("Sleep")
		if r.ok then
			dayTransition(r)
		else
			State.toast(r.err or "Can't sleep now", T.red)
		end
	end)
end

State.open.Barber = Services.Barber
State.open.Locker = Services.Locker
State.open.Nutrition = Services.Nutrition
State.open.Water = Services.Water
State.open.Sleep = Services.Sleep
return Services
