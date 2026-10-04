-- Creator: the full character creator.
-- Identity (names, age, nationality, walkout song, voice), Face (6 shapes + feature sliders),
-- Eyes & Skin, Hair (type, 24 styles, length/density/thickness, colour wheel, highlights,
-- dye patterns, beard), Body (height, weight class, weight, reach, frame, six sliders),
-- Gear & Style (trunks, socks, shoes, wraps, mouthguard, robe, gloves) and Fight Style.
-- Every change previews live on your character (server-built), with a turntable camera.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local UI = require(Shared:WaitForChild("UI"))
local State = require(script.Parent:WaitForChild("State"))
local T = UI.Theme

local Creator = {}
local player = State.player

local function newState()
	return {
		first = "", last = "", nickname = "", age = 20, nationality = "USA", music = "", voice = "Calm",
		weightClass = 5, weight = 145, reachDelta = 2, style = "BoxerPuncher", specialty = "Speed",
		look = Looks.Defaults(1),
	}
end
local C = newState()
local page = "Identity"
local PAGES = { "Identity", "Face", "Eyes & Skin", "Hair", "Body", "Gear & Style", "Fight Style" }
local HEAD_PAGES = { Face = true, ["Eyes & Skin"] = true, Hair = true }

local shade, win, body
local camConn, previewConn
local camYaw = 0
local dirty = false
local lastSent = 0

local function preview()
	dirty = true
end

local function hands()
	return page == "Gear & Style" and "gloves" or "wraps"
end

local function freeze(on)
	local _, hum = State.char()
	if hum then
		hum.WalkSpeed = on and 0 or 16
		hum.JumpHeight = on and 0 or 7.2
	end
	State.SetAnimate(not on)
end

local function idsOf(list)
	local out = {}
	for _, v in ipairs(list) do
		table.insert(out, v.id or v)
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

-- swatches + an optional colour wheel
local function colorField(parent, label, get, set, palette)
	local holder = UI.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.List(holder, 4)
	local _, refresh = UI.Swatches(holder, label, palette, paletteIndex(palette, get()), function(rgb)
		set(rgb)
		preview()
	end)
	local wheel
	UI.Button(holder, "Custom colour", { Size = UDim2.new(0, 150, 0, 26), TextSize = 13, BackgroundColor3 = T.panel2 }, function()
		if wheel then
			wheel:Destroy()
			wheel = nil
			return
		end
		wheel = UI.ColorWheel(holder, label .. " - colour wheel", get(), function(rgb)
			set(rgb)
			refresh(nil)
			preview()
		end)
	end)
	return holder
end

local function startingStats()
	local style = Config.FindById(Config.Styles, C.style) or Config.Styles[4]
	local spec = Config.FindById(Config.Specialties, C.specialty) or Config.Specialties[1]
	local frame = Config.FindById(Config.BodyTypes, C.look.body.frame) or Config.BodyTypes[2]
	local base = 26 + (C.age - 16) * 0.75
	local out = {}
	for _, k in ipairs(Config.StatKeys) do
		out[k] = math.clamp(math.floor(base + (style.mods[k] or 0) + (frame.mods[k] or 0) + (spec.stats[k] or 0)), 10, 60)
	end
	return out
end

local function modsText(mods)
	local parts = {}
	for _, k in ipairs(Config.StatKeys) do
		local v = mods[k]
		if v and v ~= 0 then
			table.insert(parts, string.format("%s%d %s", v > 0 and "+" or "", v, Config.StatNames[k]))
		end
	end
	return table.concat(parts, ", ")
end

------------------------------------------------------------------------
-- Camera: turntable framing the face or the full body
------------------------------------------------------------------------
local function camera(on)
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	local cam = workspace.CurrentCamera
	if not on then
		cam.CameraType = Enum.CameraType.Custom
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	camConn = RunService.RenderStepped:Connect(function(dt)
		cam = workspace.CurrentCamera
		-- the engine resets the camera to Custom whenever the character (re)spawns
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local char, _, root = State.char()
		local head = char and char:FindFirstChild("Head")
		if not (root and head) then
			return
		end
		local rot = CFrame.Angles(0, camYaw, 0) * root.CFrame.Rotation
		local look, right = rot.LookVector, rot.RightVector
		local goal
		if HEAD_PAGES[page] then
			local target = head.Position + Vector3.new(0, 0.05, 0)
			goal = CFrame.lookAt(target + look * 4 + right * 1.5 + Vector3.new(0, 0.25, 0), target + right * 1.15)
		else
			local target = root.Position + Vector3.new(0, 0.7, 0)
			goal = CFrame.lookAt(target + look * 10.5 + right * 3.8 + Vector3.new(0, 0.8, 0), target + right * 3.0)
		end
		cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 7, 0, 1))
	end)
end

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
local render

local function pageIdentity()
	UI.TextInput(body, "First name", C.first, "e.g. Marcus", 14, function(v)
		C.first = v
	end)
	UI.TextInput(body, "Last name", C.last, "e.g. Rivera", 16, function(v)
		C.last = v
	end)
	UI.TextInput(body, "Boxing nickname", C.nickname, "e.g. The Hurricane", 20, function(v)
		C.nickname = v
	end)
	UI.Slider(body, "Age", 16, 35, C.age, 1, function(v)
		C.age = v
	end)
	UI.Cycler(body, "Gender", { 1, 2 }, C.look.gender, function(g)
		local keep = { skin = C.look.skin, eye = C.look.face.eyeColor, shape = C.look.face.shape, seed = C.look.face.seed }
		C.look = Looks.Defaults(g)
		C.look.skin, C.look.face.eyeColor, C.look.face.shape, C.look.face.seed = keep.skin, keep.eye, keep.shape, keep.seed
		preview()
	end, function(g)
		return Config.Genders[g]
	end)
	UI.Cycler(body, "Nationality", Config.Nationalities, C.nationality, function(v)
		C.nationality = v
	end)
	local sample
	UI.Cycler(body, "Voice type", Config.VoiceTypes, C.voice, function(v)
		C.voice = v
		sample.Text = "\"" .. string.format(Config.VoiceLines[v][1], "my opponent") .. "\""
	end)
	sample = UI.Line(body, "\"" .. string.format(Config.VoiceLines[C.voice][1], "my opponent") .. "\"", { TextColor3 = Color3.fromRGB(255, 170, 170), TextSize = 14 })
	UI.TextInput(body, "Walkout song (audio ID)", C.music, "Optional Roblox audio ID", 20, function(v)
		C.music = v:gsub("%D", "")
	end)
	UI.Line(body, "Your voice type shapes your press-conference lines and the ring announcer's introduction. The walkout song plays during your ring walk.", { TextColor3 = T.sub, TextSize = 13 })
	UI.Line(body, "Younger boxers start weaker but develop faster. Veterans start stronger but peak sooner.", { TextColor3 = T.sub, TextSize = 13 })
end

local function pageFace()
	local f = C.look.face
	local shapeRow = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Grid(shapeRow, UDim2.new(1 / 3, -6, 0, 34), nil, 6)
	for i, s in ipairs(Looks.FaceShapes) do
		UI.Button(shapeRow, s, { LayoutOrder = i, TextSize = 14, BackgroundColor3 = f.shape == s and T.gold or T.panel2, TextColor3 = f.shape == s and T.bg or T.text }, function()
			f.shape = s
			preview()
			render()
		end)
	end
	for _, s in ipairs(Looks.FaceSliders) do
		UI.Slider(body, s.label, s.min, s.max, f[s.key] or 0, nil, function(v)
			f[s.key] = v
			preview()
		end, function(v)
			return string.format("%+d", math.floor(v * 100 + (v >= 0 and 0.5 or -0.5)))
		end)
	end
	UI.Button(body, "Randomize face", { Size = UDim2.new(0, 200, 0, 34) }, function()
		local r = Looks.Random(math.random(1, 1000000), C.look.gender)
		for _, list in ipairs({ Looks.FaceSliders }) do
			for _, s in ipairs(list) do
				f[s.key] = r.face[s.key]
			end
		end
		f.shape = r.face.shape
		f.seed = r.face.seed
		preview()
		render()
	end)
end

local function pageEyesSkin()
	local f = C.look.face
	local skins = {}
	for i, c in ipairs(Looks.SkinTones) do
		skins[i] = c
	end
	UI.Swatches(body, "Skin tone", skins, C.look.skin, function(_, i)
		C.look.skin = i
		preview()
	end)
	UI.Swatches(body, "Eye colour", Looks.EyeColors, f.eyeColor, function(_, i)
		f.eyeColor = i
		preview()
	end)
	for _, s in ipairs(Looks.EyeSliders) do
		UI.Slider(body, s.label, s.min, s.max, f[s.key] or 0, nil, function(v)
			f[s.key] = v
			preview()
		end)
	end
	UI.Header(body, "SKIN DETAILS")
	for _, s in ipairs(Looks.SkinSliders) do
		UI.Slider(body, s.label, s.min, s.max, f[s.key] or 0, s.step, function(v)
			f[s.key] = v
			preview()
		end)
	end
	UI.Button(body, "New skin detail pattern", { Size = UDim2.new(0, 230, 0, 32), TextSize = 14 }, function()
		f.seed = math.random(1, 1000000)
		preview()
	end)
end

local function pageHair()
	local h = C.look.hair
	UI.Cycler(body, "Hair type", Looks.HairTypes, h.type, function(v)
		h.type = v
		preview()
	end)
	UI.Header(body, "HAIRSTYLE")
	local grid = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Grid(grid, UDim2.new(1 / 3, -6, 0, 30), nil, 6)
	for i, s in ipairs(Looks.HairStyles) do
		UI.Button(grid, s, { LayoutOrder = i, TextSize = 13, BackgroundColor3 = h.style == s and T.gold or T.panel2, TextColor3 = h.style == s and T.bg or T.text }, function()
			h.style = s
			preview()
			render()
		end)
	end
	for _, s in ipairs(Looks.HairSliders) do
		UI.Slider(body, s.label, s.min, s.max, h[s.key] or 0.5, nil, function(v)
			h[s.key] = v
			preview()
		end)
	end
	colorField(body, "Hair colour", function()
		return h.color
	end, function(rgb)
		h.color = rgb
	end, Looks.HairColors)
	UI.Toggle(body, "Highlights", h.hl, function(v)
		h.hl = v
		preview()
	end)
	UI.Cycler(body, "Dye pattern", Looks.DyePatterns, h.dye, function(v)
		h.dye = v
		preview()
	end)
	colorField(body, "Highlight / dye colour", function()
		return h.hcolor
	end, function(rgb)
		h.hcolor = rgb
	end, Looks.HairColors)
	if C.look.gender == 1 then
		UI.Cycler(body, "Beard", Looks.BeardStyles, C.look.beard.style, function(v)
			C.look.beard.style = v
			preview()
		end)
	end
	UI.Line(body, "Hair and beards grow over time - visit the Barber Shop in the gym to restyle, recolour or trim.", { TextColor3 = T.sub, TextSize = 13 })
end

local function pageBody()
	local b = C.look.body
	local frames = idsOf(Config.BodyTypes)
	local desc
	UI.Cycler(body, "Body type", frames, b.frame, function(v)
		b.frame = v
		local ft = Config.FindById(Config.BodyTypes, v)
		desc.Text = modsText(ft.mods) .. string.format("   |   muscle potential %d%%", math.floor(ft.potential * 100))
		preview()
	end)
	local ft = Config.FindById(Config.BodyTypes, b.frame)
	desc = UI.Line(body, modsText(ft.mods) .. string.format("   |   muscle potential %d%%", math.floor(ft.potential * 100)), { TextColor3 = T.sub, TextSize = 13 })
	UI.Slider(body, "Height", 60, 84, C.look.height, 1, function(v)
		C.look.height = v
		preview()
	end, function(v)
		return Config.HeightText(v)
	end)
	local idx = {}
	for i = 1, #Config.WeightClasses do
		idx[i] = i
	end
	UI.Cycler(body, "Weight class", idx, C.weightClass, function(v)
		C.weightClass = v
		local wc = Config.WeightClasses[v]
		C.weight = math.clamp(C.weight, wc.min, wc.limit)
		render()
	end, function(v)
		local wc = Config.WeightClasses[v]
		return string.format("%s (%d-%d)", wc.name, wc.min, wc.limit)
	end)
	local wc = Config.WeightClasses[C.weightClass]
	C.weight = math.clamp(C.weight, wc.min, wc.limit)
	UI.Slider(body, "Walk-around weight", wc.min, wc.limit, C.weight, 1, function(v)
		C.weight = v
	end, function(v)
		return v .. " lbs"
	end)
	UI.Slider(body, "Reach", -3, 6, C.reachDelta, 1, function(v)
		C.reachDelta = v
	end, function(v)
		return (C.look.height + v) .. " in"
	end)
	UI.Header(body, "BUILD")
	for _, s in ipairs(Looks.BodySliders) do
		UI.Slider(body, s.label, s.min, s.max, b[s.key] or 0, nil, function(v)
			b[s.key] = v
			preview()
		end, function(v)
			return string.format("%+d", math.floor(v * 100 + (v >= 0 and 0.5 or -0.5)))
		end)
	end
	UI.Line(body, "Everyone starts lean. Training transforms your body: power work builds chest, shoulders, arms and back; cardio burns fat; balanced training builds an athletic physique.", { TextColor3 = T.sub, TextSize = 13 })
end

local function pageGear()
	local a = C.look.attire
	local g = C.look.gloves
	local pal = Looks.Palette
	UI.Button(body, "Champion kit (black & red)", { Size = UDim2.new(0, 260, 0, 34), TextSize = 14, BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
		-- black pro trunks with red waistband, hems and striped side panels; black boxing
		-- boots with red laces and soles; white socks; red gloves with a white cuff band
		a.trunks, a.trim, a.trunkStyle = { 20, 20, 20 }, { 200, 25, 30 }, "Pro"
		a.socks, a.shoes, a.shoeStyle = { 240, 240, 240 }, { 20, 20, 20 }, "High-Top"
		a.robe, a.robeTrim = { 20, 20, 20 }, { 200, 25, 30 }
		g.color, g.trim = { 200, 25, 30 }, { 240, 240, 240 }
		preview()
		render()
	end)
	UI.Header(body, "TRUNKS")
	colorField(body, "Trunks colour", function()
		return a.trunks
	end, function(c)
		a.trunks = c
		a.robe = c
	end, pal)
	colorField(body, "Trim / waistband", function()
		return a.trim
	end, function(c)
		a.trim = c
	end, pal)
	UI.Cycler(body, "Trunk style", Catalog.TrunkStyles, a.trunkStyle, function(v)
		a.trunkStyle = v
		preview()
	end)
	UI.Header(body, "FOOTWEAR")
	colorField(body, "Socks", function()
		return a.socks
	end, function(c)
		a.socks = c
	end, pal)
	colorField(body, "Boxing shoes", function()
		return a.shoes
	end, function(c)
		a.shoes = c
	end, pal)
	UI.Cycler(body, "Shoe style", { "Low-Top", "High-Top" }, a.shoeStyle, function(v)
		a.shoeStyle = v
		preview()
	end)
	UI.Header(body, "HANDS & MOUTH")
	colorField(body, "Gloves", function()
		return g.color
	end, function(c)
		g.color = c
	end, pal)
	colorField(body, "Hand wraps", function()
		return a.wraps
	end, function(c)
		a.wraps = c
	end, pal)
	colorField(body, "Mouthguard", function()
		return a.mouthguard
	end, function(c)
		a.mouthguard = c
	end, pal)
	UI.Header(body, "ROBE (walkouts)")
	colorField(body, "Robe trim", function()
		return a.robeTrim
	end, function(c)
		a.robeTrim = c
	end, pal)
	UI.Line(body, "You start with worn, beaten-up gloves. Better gloves (Gear tab) unlock trim, stitching, finishes, logos and name embroidery at the Locker Room.", { TextColor3 = T.sub, TextSize = 13 })
end

local function pageStyle()
	UI.Header(body, "BOXING STYLE")
	for _, s in ipairs(Config.Styles) do
		local selected = C.style == s.id
		local b = UI.Button(body, "", { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = selected and Color3.fromRGB(60, 50, 20) or T.panel }, function()
			C.style = s.id
			render()
		end)
		if selected then
			UI.Stroke(b, T.gold, 2)
		end
		UI.Text(b, s.name, { Font = T.bold, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 22), AutomaticSize = Enum.AutomaticSize.None })
		UI.Text(b, s.desc .. "  (" .. modsText(s.mods) .. ")", { TextColor3 = T.sub, TextSize = 13, Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 32), AutomaticSize = Enum.AutomaticSize.None })
	end
	local specs = idsOf(Config.Specialties)
	UI.Cycler(body, "Specialty", specs, C.specialty, function(v)
		C.specialty = v
		render()
	end)
	local spec = Config.FindById(Config.Specialties, C.specialty)
	UI.Line(body, "Specialty bonus: " .. modsText(spec.stats) .. " and +25% training gains on those stats.", { TextColor3 = T.sub, TextSize = 13 })
	UI.Header(body, "STARTING STATS")
	local grid = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Grid(grid, UDim2.new(0.5, -4, 0, 24), nil, 4)
	local stats = startingStats()
	for i, k in ipairs(Config.StatKeys) do
		local v = stats[k]
		UI.Text(grid, string.format("%s  %d", Config.StatNames[k], v), { TextSize = 15, LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 1, 0), TextColor3 = v >= 40 and T.green or T.text })
	end
	UI.Line(body, string.format("Overall %d  -  You'll start as an amateur at the local gym with %s.", Config.Overall(stats), Config.Money(500)), { Font = T.semi, TextSize = 14 })
end

local PAGE_FN = {
	Identity = pageIdentity, Face = pageFace, ["Eyes & Skin"] = pageEyesSkin, Hair = pageHair,
	Body = pageBody, ["Gear & Style"] = pageGear, ["Fight Style"] = pageStyle,
}

local tabsFrame, nextBtn
local lastPage
function render()
	if not (shade and shade.Parent) then
		return
	end
	UI.Clear(tabsFrame)
	for i, name in ipairs(PAGES) do
		UI.Button(tabsFrame, name, { LayoutOrder = i, TextSize = 13, BackgroundColor3 = name == page and T.gold or T.panel2, TextColor3 = name == page and T.bg or T.text }, function()
			local wasHands = hands()
			page = name
			if hands() ~= wasHands then
				preview()
			end
			render()
		end)
	end
	local y = lastPage == page and body.CanvasPosition or Vector2.zero
	lastPage = page
	UI.Clear(body)
	local ok, err = pcall(PAGE_FN[page])
	if not ok then
		warn("[Creator]", err)
	end
	task.defer(function()
		if body and body.Parent then
			body.CanvasPosition = y
		end
	end)
	if nextBtn then
		nextBtn.Text = page == PAGES[#PAGES] and "BEGIN CAREER" or "NEXT"
	end
end

function Creator.Open()
	if shade and shade.Parent then
		return
	end
	State.closeAll("Creator")
	C = newState()
	page = "Identity"
	camYaw = 0
	shade, win, body = UI.Window(State.gui, "Creator", 600, 720, "CREATE YOUR BOXER", { side = "left", noShade = true, footer = 50 })
	tabsFrame = UI.Frame(win, { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 48), Size = UDim2.new(1, -32, 0, 72) })
	UI.Grid(tabsFrame, UDim2.new(0.25, -5, 0, 32), nil, 5)
	body.Position = UDim2.fromOffset(16, 128)
	body.Size = UDim2.new(1, -32, 1, -190)
	UI.Button(win, "RANDOM LOOK", { Size = UDim2.fromOffset(140, 30), Position = UDim2.new(1, -156, 0, 12), TextSize = 13 }, function()
		local g = C.look.gender
		C.look = Looks.Random(math.random(1, 1000000), g)
		C.look.body.frame = "Athletic"
		preview()
		render()
	end)
	local nav = UI.Frame(win, { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 1, -54), Size = UDim2.new(1, -32, 0, 42) })
	UI.Button(nav, "BACK", { Size = UDim2.new(0.3, 0, 1, 0) }, function()
		local i = table.find(PAGES, page) or 1
		page = PAGES[math.max(1, i - 1)]
		preview()
		render()
	end)
	nextBtn = UI.Button(nav, "NEXT", { Size = UDim2.new(0.66, 0, 1, 0), Position = UDim2.new(0.34, 0, 0, 0), BackgroundColor3 = T.gold, TextColor3 = T.bg })
	nextBtn.MouseButton1Click:Connect(function()
		local i = table.find(PAGES, page) or 1
		if i < #PAGES then
			page = PAGES[i + 1]
			preview()
			render()
			return
		end
		if C.first:gsub("%s", "") == "" or C.last:gsub("%s", "") == "" then
			State.toast("Give your boxer a first and last name.", T.red)
			page = "Identity"
			render()
			return
		end
		nextBtn.Text = "CREATING..."
		local res = State.req("CreateBoxer", {
			first = C.first, last = C.last, nickname = C.nickname, age = C.age, nationality = C.nationality,
			music = C.music, voice = C.voice, weightClass = C.weightClass, weight = C.weight, reachDelta = C.reachDelta,
			style = C.style, specialty = C.specialty, look = C.look,
		})
		if res.ok then
			Creator.Close()
			State.toast("Welcome to the fight game! Your amateur career starts now.", T.gold, 5)
			State.toast("Train at the gym stations, eat and sleep - then book a fight at the FIGHT BOARD (or press H).", T.gold, 7)
		else
			nextBtn.Text = "BEGIN CAREER"
			State.toast(res.err or "Couldn't create your boxer", T.red)
		end
	end)
	-- turntable controls (right side of the screen)
	local turn = UI.Frame(shade, { Name = "Turntable", BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 40), Position = UDim2.new(0.75, -110, 1, -60) })
	UI.List(turn, 8, true, Enum.HorizontalAlignment.Center)
	local function spin(d)
		camYaw += d
	end
	local held = 0
	for _, def in ipairs({ { "<", 0.35 }, { "FRONT", 0 }, { ">", -0.35 } }) do
		local b = UI.Button(turn, def[1], { Size = UDim2.fromOffset(def[1] == "FRONT" and 80 or 50, 36), TextSize = 14 }, function()
			if def[2] == 0 then
				camYaw = 0
			else
				spin(def[2])
			end
		end)
		b.MouseButton1Down:Connect(function()
			if def[2] ~= 0 then
				held = def[2]
			end
		end)
		b.MouseButton1Up:Connect(function()
			held = 0
		end)
		b.MouseLeave:Connect(function()
			held = 0
		end)
	end
	freeze(true)
	camera(true)
	State.HidePrompts("Creator", true)
	render()
	if previewConn then
		previewConn:Disconnect()
	end
	previewConn = RunService.Heartbeat:Connect(function(dt)
		if held ~= 0 then
			camYaw += held * dt * 4
		end
		if dirty and os.clock() - lastSent > 0.28 then
			dirty = false
			lastSent = os.clock()
			task.spawn(function()
				local r = State.req("PreviewLook", C.look, hands())
				if r and r.throttled then
					dirty = true
				end
			end)
		end
	end)
	State.windows.Creator = Creator.Close
	preview()
end

function Creator.Close()
	State.windows.Creator = nil
	if previewConn then
		previewConn:Disconnect()
		previewConn = nil
	end
	camera(false)
	freeze(false)
	State.HidePrompts("Creator", false)
	if shade then
		shade:Destroy()
		shade = nil
	end
end

function Creator.IsOpen()
	return shade ~= nil and shade.Parent ~= nil
end

-- the character respawned while creating: keep the player's choices, re-apply the preview
function Creator.Refresh()
	if not Creator.IsOpen() then
		return
	end
	freeze(true)
	camera(true)
	preview()
end

State.open.Creator = Creator.Open
return Creator
