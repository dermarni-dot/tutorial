-- Panels (ModuleScript) — StarterPlayerScripts.CityClient.Panels
-- The windows you open: the city map, the People directory and profile
-- cards, voting, speeches, the mayor's desk, conversations with citizens,
-- elevators, help, settings, the welcome screen, election results and the
-- "BUSTED!" screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Faces = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Faces"))
local UI = require(script.Parent:WaitForChild("UI"))
local C = UI.C

local Panels = {}
local player = Players.LocalPlayer
local ctx
local screen

local function request(data)
	local ok, result = pcall(function()
		return ctx.Remotes.Request:InvokeServer(data)
	end)
	if ok and type(result) == "table" then
		return result
	end
	return { Ok = false, Error = "Couldn't reach the city." }
end

local function fail(result)
	ctx.Hud.Toast("⚠️", "Hmm...", result.Error or "That didn't work.", C.Red)
end

local function clear(frame, keep)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") and not (keep and keep[child]) then
			child:Destroy()
		end
	end
end

local STAGE_EMOJI = { Baby = "👶", Toddler = "🧒", Child = "🧒", Teen = "🧑", Adult = "🧑", Retired = "🧓" }
local PERSONALITY_EMOJI = { cheerful = "😊", shy = "😳", grumpy = "😒", chatty = "🗣️", bookish = "🤓", sporty = "💪", artsy = "🎨", curious = "🧐", calm = "😌", funny = "😄" }

-- a 3D portrait of a citizen (a local copy of their model, turning slowly)
local function portrait(parent, model, closeUp, props)
	local vp = UI.new("ViewportFrame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), Ambient = Color3.fromRGB(170, 170, 185), LightColor = Color3.fromRGB(255, 245, 230), LightDirection = Vector3.new(-1, -1, -1), Parent = parent })
	for k, v in pairs(props or {}) do
		vp[k] = v
	end
	UI.corner(vp, 14)
	UI.gradient(vp, C.White, C.Panel3, 90)
	if not model or not model.Parent then
		UI.text(vp, "👤", 60, UI.Font, C.Sub, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		return vp
	end
	local ok, copy = pcall(function()
		model.Archivable = true
		return model:Clone()
	end)
	if not ok or not copy then
		return vp
	end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local world = Instance.new("WorldModel")
	world.Parent = vp
	copy.Parent = world
	local root = copy:FindFirstChild("HumanoidRootPart")
	local head = copy:FindFirstChild("Head")
	local base = root and root.CFrame or copy:GetPivot()
	copy:PivotTo(CFrame.new(0, 0, 0) * (base - base.Position))
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = vp
	vp.CurrentCamera = camera
	local s = model:GetAttribute("Scale") or 1
	local focus = if closeUp and head then head.Position - base.Position else Vector3.new(0, 0.3 * s, 0)
	local dist = (if closeUp then 5.2 else 14) * s
	local fwd = (base - base.Position).LookVector
	local overlay
	if closeUp and head then
		-- viewports don't draw SurfaceGuis, so the drawn face goes on top as a copy
		camera.CFrame = CFrame.lookAt(focus + fwd * dist, focus)
		local face = model:FindFirstChild("Head") and model.Head:FindFirstChild("CityFace")
		if face then
			local d = dist - head.Size.Z / 2
			local visible = 2 * d * math.tan(math.rad(camera.FieldOfView / 2))
			local k = head.Size.Y / visible
			overlay = UI.new("Frame", { Name = "FaceOverlay", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(k * head.Size.X / head.Size.Y, k), ClipsDescendants = true, ZIndex = 3, Parent = vp })
			UI.new("UIAspectRatioConstraint", { AspectRatio = head.Size.X / head.Size.Y, Parent = overlay })
			for _, child in ipairs(face:GetChildren()) do
				child:Clone().Parent = overlay
			end
		end
		return vp, overlay
	end
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not vp.Parent then
			conn:Disconnect()
			return
		end
		local a = os.clock() * 0.5
		local dir = CFrame.Angles(0, a, 0):VectorToWorldSpace(fwd)
		camera.CFrame = CFrame.lookAt(focus + dir * dist + Vector3.new(0, 1.2 * s, 0), focus)
	end)
	return vp
end

--------------------------------------------------------------------------------
-- The city map
--------------------------------------------------------------------------------
local function buildMap()
	local win = UI.window(screen, "City Map", "🗺️", UDim2.fromOffset(980, 640), C.Green)
	Panels.Map = win
	local body = win.Body
	local canvas = UI.new("Frame", { BackgroundColor3 = UI.rgb(62, 108, 62), ClipsDescendants = true, Size = UDim2.new(1, -290, 1, 0), Parent = body })
	UI.corner(canvas, 12)
	local world = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Position = UDim2.fromScale(0.5, 0.5), Parent = canvas })
	local zoom = UI.new("UIScale", { Scale = 0.62, Parent = world })
	local pins = ctx.Hud.DrawCity(world, 1, { PinSize = 24, Labels = true })
	local me = UI.text(world, "▲", 26, UI.Black, C.Gold, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(28, 28), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	UI.new("UIStroke", { Thickness = 2, Parent = me })
	local wpPin = UI.text(world, "📍", 30, UI.Font, C.White, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(32, 32), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12, Visible = false })
	local dots = {}
	local showPeople = true
	-- zoom and pan
	local zoomBar = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 15, Parent = canvas })
	UI.list(zoomBar, Enum.FillDirection.Horizontal, 6)
	local function setZoom(z)
		zoom.Scale = math.clamp(z, 0.35, 2.4)
	end
	UI.button(zoomBar, "＋", { Size = UDim2.fromOffset(36, 36), LayoutOrder = 1 }, function()
		setZoom(zoom.Scale * 1.3)
	end).ZIndex = 16
	UI.button(zoomBar, "－", { Size = UDim2.fromOffset(36, 36), LayoutOrder = 2 }, function()
		setZoom(zoom.Scale / 1.3)
	end).ZIndex = 16
	UI.button(zoomBar, "🎯 Me", { Size = UDim2.fromOffset(70, 36), LayoutOrder = 3, TextSize = 13 }, function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			world.Position = UDim2.new(0.5, -root.Position.X * zoom.Scale, 0.5, -root.Position.Z * zoom.Scale)
		end
	end).ZIndex = 16
	local peopleButton, setPeopleColor = UI.button(zoomBar, "👥 People", { Size = UDim2.fromOffset(92, 36), LayoutOrder = 4, TextSize = 13, Color = C.Blue }, nil)
	peopleButton.ZIndex = 16
	peopleButton.Activated:Connect(function()
		showPeople = not showPeople
		setPeopleColor(if showPeople then C.Blue else C.Panel3)
	end)
	local dragging, dragStart, startPos
	canvas.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, world.Position
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			setZoom(zoom.Scale * (if input.Position.Z > 0 then 1.15 else 1 / 1.15))
		end
	end)
	canvas.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			setZoom(zoom.Scale * (if input.Position.Z > 0 then 1.15 else 1 / 1.15))
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			world.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- the side list
	local side = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 276, 1, 0), Parent = body })
	local search = UI.new("TextBox", { BackgroundColor3 = C.Panel2, PlaceholderText = "🔍 Search places...", PlaceholderColor3 = C.Dim, Text = "", TextColor3 = C.Text, Font = UI.Font, TextSize = 15, ClearTextOnFocus = false, Size = UDim2.new(1, 0, 0, 38), TextXAlignment = Enum.TextXAlignment.Left, Parent = side })
	UI.corner(search, 10)
	UI.pad(search, 0, 0, 10, 0, 12)
	local filters = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 28), Parent = side })
	UI.list(filters, Enum.FillDirection.Horizontal, 4)
	local kindFilter = nil
	local list = UI.scroll(side, { Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 1, -196) })
	UI.list(list, Enum.FillDirection.Vertical, 5)
	local info = UI.panel(side, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = C.Panel2, Radius = 12 })
	UI.pad(info, 10)
	local infoTitle = UI.text(info, "Tap a place", 17, UI.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 22) })
	local infoText = UI.text(info, "Pins show every building. Drag to move, scroll to zoom.", 13, UI.Font, C.Sub, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 36), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local selected
	local goButton = UI.button(info, "📍 Set waypoint", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 32), Color = C.Gold, TextColor = C.Bg, TextSize = 14 }, function()
		if selected then
			ctx.World.Waypoint(selected.Position, selected.Label, Config.PlaceById[selected.Id] and Config.PlaceById[selected.Id].emoji)
			win.Close()
		end
	end)
	goButton.Visible = false
	local places = {}
	local function select(place)
		selected = place
		infoTitle.Text = (Config.PlaceById[place.Id] and Config.PlaceById[place.Id].emoji or "📍") .. " " .. place.Label
		infoText.Text = (if place.Open then "🟢 Open now" else "🔴 Closed right now") .. "  ·  👷 " .. place.Workers .. " working  ·  🙋 " .. place.Visitors .. " visiting"
		goButton.Visible = true
		world.Position = UDim2.new(0.5, -place.Position.X * zoom.Scale, 0.5, -place.Position.Z * zoom.Scale)
		local pin = pins[place.Id]
		if pin then
			local s = pin:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = pin })
			s.Scale = 1.8
			UI.tween(s, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	local function rebuild()
		clear(list)
		local q = string.lower(search.Text)
		for _, place in ipairs(places) do
			if (q == "" or string.find(string.lower(place.Label), q, 1, true)) and (not kindFilter or place.Kind == kindFilter) then
				local row = UI.button(list, "", { Size = UDim2.new(1, -8, 0, 44), Color = C.Panel2 }, function()
					select(place)
				end)
				local emoji = Config.PlaceById[place.Id] and Config.PlaceById[place.Id].emoji or (string.find(place.Id, "^Woods") and "🌲") or "📍"
				local dot = UI.new("TextLabel", { BackgroundColor3 = UI.KIND_COLORS[place.Kind] or C.Sub, Text = emoji, TextSize = 16, Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(6, 6), Parent = row })
				UI.corner(dot, UDim.new(0.5, 0))
				UI.text(row, place.Label, 14, UI.Bold, C.Text, { Position = UDim2.fromOffset(46, 3), Size = UDim2.new(1, -52, 0, 18) })
				UI.text(row, (if place.Open then "🟢 Open" else "🔴 Closed") .. "  ·  " .. (place.Workers + place.Visitors) .. " inside", 12, UI.Font, C.Sub, { Position = UDim2.fromOffset(46, 22), Size = UDim2.new(1, -52, 0, 16) })
			end
		end
	end
	for _, f in ipairs({ { nil, "All" }, { "civic", "🏛️" }, { "work", "💼" }, { "store", "🛍️" }, { "fun", "🎉" } }) do
		local b = UI.button(filters, f[2], { Size = UDim2.fromOffset(if f[1] then 44 else 48, 28), TextSize = 13, Color = if f[1] then (UI.KIND_COLORS[f[1]]):Lerp(C.Panel2, 0.5) else C.Panel3 }, function()
			kindFilter = f[1]
			rebuild()
		end)
	end
	for id, pin in pairs(pins) do
		pin.Activated:Connect(function()
			for _, place in ipairs(places) do
				if place.Id == id then
					select(place)
				end
			end
		end)
	end
	search:GetPropertyChangedSignal("Text"):Connect(rebuild)
	win.OnOpen = function()
		local result = request({ Action = "Places" })
		if result.Ok then
			places = result.Places
			table.sort(places, function(a, b)
				return a.Label < b.Label
			end)
			rebuild()
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			world.Position = UDim2.new(0.5, -root.Position.X * zoom.Scale, 0.5, -root.Position.Z * zoom.Scale)
		end
	end
	RunService.RenderStepped:Connect(function()
		if not win.IsOpen() then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			me.Position = UDim2.fromOffset(root.Position.X, root.Position.Z)
			local look = root.CFrame.LookVector
			me.Rotation = math.deg(math.atan2(look.X, -look.Z))
		end
		local wp = workspace:FindFirstChild("CityWaypoint")
		local anchor = wp and wp:FindFirstChild("WaypointAnchor")
		wpPin.Visible = anchor ~= nil
		if anchor then
			wpPin.Position = UDim2.fromOffset(anchor.Position.X, anchor.Position.Z)
		end
		local k = 0
		if showPeople then
			for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Citizen")) do
				local r = model:FindFirstChild("HumanoidRootPart")
				if r then
					k += 1
					local dot = dots[k]
					if not dot then
						dot = UI.new("Frame", { BackgroundColor3 = C.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 6), ZIndex = 9, Parent = world })
						UI.corner(dot, UDim.new(0.5, 0))
						dots[k] = dot
					end
					dot.Visible = true
					dot.Position = UDim2.fromOffset(r.Position.X, r.Position.Z)
					dot.BackgroundColor3 = if model:GetAttribute("Chasing") then C.Red elseif model:GetAttribute("Stage") == "Child" or model:GetAttribute("Stage") == "Teen" then C.Gold else C.White
				end
			end
		end
		for j = k + 1, #dots do
			dots[j].Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- Profile cards
--------------------------------------------------------------------------------
local function buildProfile()
	local win = UI.window(screen, "Citizen", "🪪", UDim2.fromOffset(720, 520), C.Blue)
	Panels.Profile = win
	local body = win.Body
	local left = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 230, 1, 0), Parent = body })
	local right = UI.scroll(body, { Position = UDim2.fromOffset(246, 0), Size = UDim2.new(1, -246, 1, 0) })
	UI.list(right, Enum.FillDirection.Vertical, 8)
	local backButton
	function Panels.OpenProfile(id, fromDirectory)
		local data = request({ Action = "Profile", Id = id })
		if not data.Ok then
			return fail(data)
		end
		clear(left)
		clear(right)
		win.Title.Text = data.Name
		win.SetIcon(STAGE_EMOJI[data.Stage] or "🪪")
		portrait(left, data.Model, false, { Size = UDim2.new(1, 0, 0, 290) })
		local buttons = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 300), Size = UDim2.new(1, 0, 0, 40), Parent = left })
		UI.list(buttons, Enum.FillDirection.Horizontal, 8)
		UI.button(buttons, "📍 Find", { Size = UDim2.fromOffset(110, 40), Color = C.Gold, TextColor = C.Bg }, function()
			request({ Action = "Locate", Id = id })
			win.Close()
		end)
		if fromDirectory then
			UI.button(buttons, "↩ Back", { Size = UDim2.fromOffset(110, 40) }, function()
				Panels.Directory.Open()
			end)
		end
		UI.text(left, "Tip: walk up to " .. string.match(data.Name, "^(%S+)") .. " and press E to talk.", 12, UI.Font, C.Dim, { Position = UDim2.fromOffset(0, 350), Size = UDim2.new(1, 0, 0, 34), TextWrapped = true })
		-- who they are
		local order = 0
		local function row(icon, label, value, color)
			order += 1
			local r = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 22), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = right })
			UI.text(r, icon .. "  <b>" .. label .. "</b>", 14, UI.Font, C.Sub, { Size = UDim2.fromOffset(150, 22) })
			UI.text(r, value, 14, UI.Bold, color or C.Text, { Position = UDim2.fromOffset(150, 0), Size = UDim2.new(1, -150, 0, 22), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
		end
		local function header(text)
			order += 1
			UI.text(right, text, 16, UI.Title, C.Gold, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 24) })
		end
		order += 1
		local chips = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order, Parent = right })
		UI.list(chips, Enum.FillDirection.Horizontal, 6)
		UI.chip(chips, (STAGE_EMOJI[data.Stage] or "") .. " " .. data.Age .. " years old", C.Panel3)
		UI.chip(chips, (PERSONALITY_EMOJI[data.Personality] or "🙂") .. " " .. (data.Personality or ""), C.Purple)
		UI.chip(chips, "🎯 " .. (data.Hobby or ""), C.Teal)
		if data.Expecting then
			UI.chip(chips, "🍼 Baby in " .. data.Expecting .. "d", C.Pink)
		end
		row("📍", "Right now", data.Activity ~= "" and data.Activity or "—")
		if data.Job then
			row("💼", "Job", data.Job .. " at the " .. (data.Workplace or "?"))
			if data.Hours then
				local a = UI.formatHour(data.Hours[1])
				local b = UI.formatHour(data.Hours[2] % 24)
				row("🕘", "Hours", a .. (if data.Hours[1] >= 12 then " PM" else " AM") .. " – " .. b .. (if data.Hours[2] % 24 >= 12 then " PM" else " AM"))
			end
		elseif data.School then
			row("🎒", "School", data.School)
		elseif data.Stage == "Retired" then
			row("🌅", "Work", "Retired")
		elseif data.Stage == "Adult" then
			row("🔎", "Work", "Looking for a job")
		end
		row("🏠", "Home", data.Home or "No home yet")
		-- mood
		order += 1
		local moodRow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 22), LayoutOrder = order, Parent = right })
		UI.text(moodRow, UI.moodEmoji(data.Mood) .. "  <b>Mood</b>", 14, UI.Font, C.Sub, { Size = UDim2.fromOffset(150, 22) })
		local _, set = UI.bar(moodRow, UI.moodColor(data.Mood), 10, { Position = UDim2.new(0, 150, 0.5, -5), Size = UDim2.new(1, -200, 0, 10) })
		set(data.Mood / 100)
		UI.text(moodRow, tostring(data.Mood), 13, UI.Bold, C.Text, { Position = UDim2.new(1, -40, 0, 0), Size = UDim2.fromOffset(40, 22), TextXAlignment = Enum.TextXAlignment.Right })
		-- about you
		header("💭 What they think of you")
		row(UI.hearts(data.Opinion), "", if data.Opinion >= 50 then "They adore you!" elseif data.Opinion >= 15 then "They like you" elseif data.Opinion <= -45 then "They can't stand you" elseif data.Opinion <= -12 then "They don't like you" else "They don't know you yet", if data.Opinion >= 15 then C.Green elseif data.Opinion <= -12 then C.Red else C.Text)
		for _, m in ipairs(data.Memories or {}) do
			order += 1
			local mem = UI.text(right, (if m.Feeling >= 0 then "💚 " else "💢 ") .. "“You " .. m.Text .. "”", 13, UI.Font, if m.Feeling >= 0 then C.Green:Lerp(C.White, 0.3) else C.Red:Lerp(C.White, 0.3), { LayoutOrder = order, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -10, 0, 18) })
		end
		-- values
		if data.Values and data.Values[1] then
			header("🗳️ What matters to them")
			order += 1
			local vals = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order, Parent = right })
			UI.list(vals, Enum.FillDirection.Horizontal, 6)
			UI.chip(vals, "❤️ " .. data.Values[1].Label, C.Green:Lerp(C.Panel3, 0.4))
			if data.Values[2] then
				UI.chip(vals, "👍 " .. data.Values[2].Label, C.Blue:Lerp(C.Panel3, 0.4))
			end
			if data.Values[3] then
				UI.chip(vals, "👎 " .. data.Values[3].Label, C.Red:Lerp(C.Panel3, 0.4))
			end
		end
		-- family and friends (tap to open their card)
		local function people(title, list)
			if #list == 0 then
				return
			end
			header(title)
			order += 1
			local wrap = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = right })
			UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(140, 32), CellPadding = UDim2.fromOffset(6, 6), Parent = wrap })
			for _, p in ipairs(list) do
				UI.button(wrap, (STAGE_EMOJI[p.Stage] or "🧑") .. " " .. p.Name .. (if p.Age then " (" .. p.Age .. ")" else ""), { TextSize = 13, Color = C.Panel2 }, function()
					Panels.OpenProfile(p.Id, fromDirectory)
				end)
			end
		end
		people("👨‍👩‍👧 Family", data.Family or {})
		people("🤝 Friends", data.Friends or {})
		win.Open()
	end
end

--------------------------------------------------------------------------------
-- The directory: people, news
--------------------------------------------------------------------------------
local function buildDirectory()
	local win = UI.window(screen, "People of AI City", "👥", UDim2.fromOffset(760, 560), C.Purple)
	Panels.Directory = win
	local body = win.Body
	local tabs = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = body })
	UI.list(tabs, Enum.FillDirection.Horizontal, 8)
	local search = UI.new("TextBox", { BackgroundColor3 = C.Panel2, PlaceholderText = "🔍 Search by name, job or school...", PlaceholderColor3 = C.Dim, Text = "", TextColor3 = C.Text, Font = UI.Font, TextSize = 15, ClearTextOnFocus = false, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 38), TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
	UI.corner(search, 10)
	UI.pad(search, 0, 0, 10, 0, 12)
	local list = UI.scroll(body, { Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 1, -90) })
	UI.list(list, Enum.FillDirection.Vertical, 6)
	local tab = "People"
	local people, news = {}, {}
	local sortBy = "Name"
	local function rebuild()
		clear(list)
		search.Visible = tab == "People"
		list.Position = UDim2.fromOffset(0, if tab == "People" then 90 else 44)
		list.Size = UDim2.new(1, 0, 1, if tab == "People" then -90 else -44)
		if tab == "People" then
			local q = string.lower(search.Text)
			local shown = {}
			for _, p in ipairs(people) do
				if q == "" or string.find(string.lower(p.Name .. " " .. p.Role .. " " .. p.Activity), q, 1, true) then
					table.insert(shown, p)
				end
			end
			if sortBy == "Likes" then
				table.sort(shown, function(a, b)
					return a.Opinion > b.Opinion
				end)
			elseif sortBy == "Mood" then
				table.sort(shown, function(a, b)
					return a.Mood > b.Mood
				end)
			end
			for _, p in ipairs(shown) do
				local row = UI.button(list, "", { Size = UDim2.new(1, -10, 0, 52), Color = C.Panel2 }, function()
					Panels.OpenProfile(p.Id, true)
				end)
				local avatar = UI.new("TextLabel", { BackgroundColor3 = C.Panel3, Text = STAGE_EMOJI[p.Stage] or "🧑", TextSize = 22, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(6, 6), Parent = row })
				UI.corner(avatar, UDim.new(0.5, 0))
				UI.text(row, "<b>" .. p.Name .. "</b>  <font color='#a0a8c6'>" .. p.Age .. " · " .. p.Role .. "</font>", 15, UI.Font, C.Text, { Position = UDim2.fromOffset(56, 5), Size = UDim2.new(1, -250, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd })
				UI.text(row, p.Activity, 13, UI.Font, C.Sub, { Position = UDim2.fromOffset(56, 26), Size = UDim2.new(1, -250, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
				UI.text(row, UI.moodEmoji(p.Mood) .. " " .. p.Mood, 14, UI.Bold, UI.moodColor(p.Mood), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 15), Size = UDim2.fromOffset(60, 22), TextXAlignment = Enum.TextXAlignment.Right })
				UI.text(row, UI.hearts(p.Opinion), 11, UI.Font, C.Text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 15), Size = UDim2.fromOffset(100, 22), TextXAlignment = Enum.TextXAlignment.Right })
				local find = UI.button(row, "📍", { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -40, 0, 9), TextSize = 16, Color = C.Panel3 }, function()
					request({ Action = "Locate", Id = p.Id })
					win.Close()
				end)
			end
		else
			for _, n in ipairs(news) do
				local row = UI.panel(list, { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Panel2, Radius = 10 })
				UI.pad(row, 10)
				local time = UI.formatHour(n.Hour or 0)
				UI.text(row, "<font color='#ffc448'><b>Day " .. ((n.Day or 0) + 1) .. " · " .. time .. "</b></font>   " .. n.Text, 14, UI.Font, C.Text, { AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, Size = UDim2.new(1, 0, 0, 18) })
			end
		end
	end
	for _, t in ipairs({ { "People", "👥 People" }, { "News", "📰 News" }, { "Likes", "❤️ Who likes me" }, { "Mood", "😄 Happiest" } }) do
		UI.button(tabs, t[2], { Size = UDim2.fromOffset(if t[1] == "Likes" then 150 else 120, 34), TextSize = 14 }, function()
			if t[1] == "Likes" or t[1] == "Mood" then
				tab, sortBy = "People", t[1]
			else
				tab, sortBy = t[1], "Name"
			end
			rebuild()
		end)
	end
	search:GetPropertyChangedSignal("Text"):Connect(rebuild)
	function Panels.OpenDirectory(which)
		tab, sortBy = which or "People", "Name"
		if win.IsOpen() then
			rebuild()
		else
			win.Open()
		end
	end
	win.OnOpen = function()
		local result = request({ Action = "Directory" })
		if result.Ok then
			people = result.People
		end
		local info = request({ Action = "CityInfo" })
		if info.Ok then
			news = info.News or {}
		end
		rebuild()
	end
end

--------------------------------------------------------------------------------
-- Stance cards (speeches and policies)
--------------------------------------------------------------------------------
local VALUE_ICONS = { wealth = "💰", community = "🤝", safety = "🛡️", freedom = "🕊️", nature = "🌳", tradition = "🏛️" }
local STAT_ICONS = { economy = "💰", safety = "🛡️", happiness = "😊" }

local function stanceCard(parent, stance, selectedFn, onClick, showCity)
	local card, setColor = UI.button(parent, "", { Color = C.Panel2, Size = UDim2.fromOffset(0, 0) }, onClick)
	UI.pad(card, 10)
	UI.text(card, stance.label, 16, UI.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 20), TextWrapped = true })
	UI.text(card, "“" .. stance.pitch .. "”", 13, UI.Font, C.Sub, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 32), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local tags = {}
	if showCity then
		for stat, amount in pairs(stance.city or {}) do
			table.insert(tags, (STAT_ICONS[stat] or "") .. (if amount > 0 then "+" else "") .. amount)
		end
	else
		for v, w in pairs(stance.values or {}) do
			table.insert(tags, (VALUE_ICONS[v] or v) .. (if w > 0 then "👍" else "👎"))
		end
	end
	UI.text(card, table.concat(tags, "  "), 13, UI.Bold, C.Gold, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 18) })
	local function refresh()
		setColor(if selectedFn() then C.Gold:Lerp(C.Panel2, 0.55) else C.Panel2)
	end
	refresh()
	return card, refresh
end

local function buildSpeech()
	local win = UI.window(screen, "Give a Speech", "🎤", UDim2.fromOffset(820, 580), C.Gold)
	Panels.Speech = win
	local body = win.Body
	UI.text(body, "Pick up to <b>2 ideas</b> to promise the city. Citizens who share those values will cheer (and remember you at the election). Others will boo!", 14, UI.Font, C.Sub, { Size = UDim2.new(1, 0, 0, 36), TextWrapped = true })
	local grid = UI.scroll(body, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -110) })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 0, 104), CellPadding = UDim2.fromOffset(8, 8), Parent = grid })
	local picked = {}
	local refreshers = {}
	for _, stance in ipairs(Config.Stances) do
		local _, refresh = stanceCard(grid, stance, function()
			return table.find(picked, stance.id) ~= nil
		end, function()
			local i = table.find(picked, stance.id)
			if i then
				table.remove(picked, i)
			elseif #picked < 2 then
				table.insert(picked, stance.id)
			else
				table.remove(picked, 1)
				table.insert(picked, stance.id)
			end
			for _, r in ipairs(refreshers) do
				r()
			end
		end, false)
		table.insert(refreshers, refresh)
	end
	local result = UI.text(body, "", 14, UI.Bold, C.Text, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, -240, 0, 50), TextWrapped = true })
	UI.button(body, "🎤  Give the speech!", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(220, 52), Color = C.Gold, TextColor = C.Bg, TextSize = 17 }, function()
		if #picked == 0 then
			result.Text = "👆 Pick at least one idea first."
			return
		end
		result.Text = "📣 Speaking..."
		local r = request({ Action = "Speech", Stances = picked })
		if not r.Ok then
			result.Text = "⚠️ " .. (r.Error or "")
			return
		end
		result.Text = string.format("👏 %d cheered   👎 %d booed   😐 %d shrugged", r.Liked, r.Disliked, r.Neutral) .. (if r.Quotes and r.Quotes[1] then "\n" .. r.Quotes[1] else "")
		ctx.Hud.Toast("🎤", "Speech given!", string.format("%d cheered, %d booed. You're running for mayor now!", r.Liked, r.Disliked), C.Gold)
		task.delay(2.5, function()
			win.Close()
		end)
	end)
end

local function buildMayor()
	local win = UI.window(screen, "The Mayor's Desk", "🏛️", UDim2.fromOffset(820, 580), C.Gold)
	Panels.Mayor = win
	local body = win.Body
	local note = UI.text(body, "As mayor you can pass <b>one policy a day</b>. Each one changes the city's economy, safety and happiness, and citizens will love or hate you for it.", 14, UI.Font, C.Sub, { Size = UDim2.new(1, 0, 0, 36), TextWrapped = true })
	local grid = UI.scroll(body, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44) })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 0, 104), CellPadding = UDim2.fromOffset(8, 8), Parent = grid })
	for _, stance in ipairs(Config.Stances) do
		stanceCard(grid, stance, function()
			return false
		end, function()
			local r = request({ Action = "Policy", Stance = stance.id })
			if r.Ok then
				ctx.Hud.Toast("🏛️", "Policy passed!", stance.label, C.Gold)
				win.Close()
			else
				fail(r)
			end
		end, true)
	end
	win.OnOpen = function()
		local info = request({ Action = "CityInfo" })
		if info.Ok and not info.IsMayor then
			note.Text = "🗳️ You're not the mayor (yet!). Give a speech on the plaza stage and win the next election."
		elseif info.Ok and not info.CanPass then
			note.Text = "✅ You already passed a policy today. Come back tomorrow, Mayor!"
		end
	end
end

--------------------------------------------------------------------------------
-- Voting
--------------------------------------------------------------------------------
local function buildVote()
	local win = UI.window(screen, "Election", "🗳️", UDim2.fromOffset(760, 560), C.Blue)
	Panels.Vote = win
	local body = win.Body
	local top = UI.text(body, "", 15, UI.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 44), TextWrapped = true })
	local list = UI.scroll(body, { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50) })
	UI.list(list, Enum.FillDirection.Vertical, 8)
	win.OnOpen = function()
		local info = request({ Action = "CityInfo" })
		if not info.Ok then
			return
		end
		clear(list)
		local left = math.floor(info.ElectionIn or 0)
		top.Text = string.format("🏛️ Mayor: <b>%s</b>     ⏳ Next election in <b>%d:%02d</b>\n<font color='#a0a8c6'>Want to run? Give a speech at the plaza stage. Citizens vote for whoever shares their values (and whoever they like).</font>", info.Mayor and info.Mayor.Name or "nobody", math.floor(left / 60), left % 60)
		for _, cand in ipairs(info.Candidates or {}) do
			local chosen = info.MyVote == cand.Key
			local card = UI.panel(list, { Size = UDim2.new(1, -10, 0, 96), BackgroundColor3 = if chosen then C.Blue:Lerp(C.Panel2, 0.6) else C.Panel2, Radius = 12 })
			UI.pad(card, 12)
			UI.text(card, (if cand.Kind == "player" then "🎮 " else "👤 ") .. "<b>" .. cand.Name .. "</b>" .. (if cand.UserId == player.UserId then "  <font color='#ffc448'>(you!)</font>" else ""), 18, UI.Font, C.Text, { Size = UDim2.new(1, -160, 0, 24) })
			local stances = {}
			for _, s in ipairs(cand.Stances or {}) do
				table.insert(stances, "• " .. s.Label)
			end
			UI.text(card, table.concat(stances, "     "), 14, UI.Font, C.Sub, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -160, 0, 40), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
			UI.button(card, if chosen then "✅ Your vote" else "Vote", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(140, 44), Color = if chosen then C.Green else C.Blue }, function()
				local r = request({ Action = "Vote", Candidate = cand.Key })
				if r.Ok then
					ctx.Hud.Toast("🗳️", "Vote cast!", r.Text, C.Blue)
					win.OnOpen()
				else
					fail(r)
				end
			end)
		end
		if info.Policies and #info.Policies > 0 then
			UI.text(list, "📜 Recent policies", 16, UI.Title, C.Gold, { Size = UDim2.new(1, 0, 0, 24) })
			for _, p in ipairs(info.Policies) do
				UI.text(list, "• " .. p.Label .. "  <font color='#a0a8c6'>(Mayor " .. tostring(p.By) .. ", day " .. ((p.Day or 0) + 1) .. ")</font>", 14, UI.Font, C.Text, { Size = UDim2.new(1, 0, 0, 20) })
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Conversations
--------------------------------------------------------------------------------
local function buildDialogue()
	local sheet = UI.panel(screen, { Name = "Dialogue", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -100), Size = UDim2.fromOffset(820, 250), Visible = false, Radius = 18, ZIndex = 15 })
	local scale = UI.new("UIScale", { Parent = sheet })
	local face = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(150, 150), Parent = sheet })
	local name = UI.text(sheet, "", 22, UI.Title, C.White, { Position = UDim2.fromOffset(180, 12), Size = UDim2.new(1, -240, 0, 28) })
	local sub = UI.text(sheet, "", 13, UI.Font, C.Sub, { Position = UDim2.fromOffset(180, 40), Size = UDim2.new(1, -240, 0, 18) })
	local line = UI.text(sheet, "", 17, UI.Font, C.Text, { Position = UDim2.fromOffset(180, 64), Size = UDim2.new(1, -196, 0, 72), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local you = UI.text(sheet, "", 14, UI.Font, C.Gold, { Position = UDim2.fromOffset(180, 60), Size = UDim2.new(1, -196, 0, 18), TextWrapped = true, Visible = false })
	local meta = UI.text(sheet, "", 13, UI.Font, C.Sub, { Position = UDim2.fromOffset(14, 170), Size = UDim2.fromOffset(150, 70), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Center })
	local options = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(180, 140), Size = UDim2.new(1, -196, 0, 100), Parent = sheet })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.333, -6, 0, 30), CellPadding = UDim2.fromOffset(6, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = options })
	local close = UI.button(sheet, "✕", { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -44, 0, 10), TextSize = 15 }, function()
		Panels.EndDialogue(true)
	end)
	local current
	local typing = {}
	local optionKeys = {}
	local overlay
	local talkingUntil = 0
	local nextBlink, blinkUntil = 0, 0
	RunService.RenderStepped:Connect(function()
		if not current or not overlay or not overlay.Parent then
			return
		end
		local now = os.clock()
		if now > nextBlink then
			blinkUntil = now + 0.13
			nextBlink = now + 2 + math.random() * 3
		end
		local talk = if now < talkingUntil then math.floor((math.sin(now * 17) * 0.5 + 0.5) * 3 + 0.5) / 3 else 0
		pcall(Faces.Set, overlay, current.Expression or "neutral", if now < blinkUntil then 1 else 0, talk, 0)
	end)
	local function typeOut(text)
		local token = {}
		typing = token
		line.Text = ""
		talkingUntil = os.clock() + math.min(4, (utf8.len(text) or #text) * 0.009 + 0.3)
		task.spawn(function()
			local n = utf8.len(text) or #text
			local shown = 0
			while shown < n and typing == token do
				shown = math.min(n, shown + 2)
				local ok, cut = pcall(function()
					return string.sub(text, 1, (utf8.offset(text, shown + 1) or (#text + 1)) - 1)
				end)
				line.Text = if ok then cut else text
				task.wait(0.018)
			end
			if typing == token then
				line.Text = text
			end
		end)
	end
	local function setOptions(list)
		clear(options)
		optionKeys = {}
		for k, opt in ipairs(list or {}) do
			optionKeys[k] = opt.Key
			local b = UI.button(options, (if k <= 9 and not UserInputService.TouchEnabled then "<font color='#ffc448'>" .. k .. "</font>  " else "") .. opt.Text, { TextSize = 13, Color = if opt.Key == "bye" then C.Panel3 elseif opt.Key == "insult" then UI.rgb(90, 36, 44) elseif opt.Key == "gift" then UI.rgb(40, 90, 60) else C.Panel2, LayoutOrder = k, XAlign = Enum.TextXAlignment.Left }, function()
				Panels.Choose(opt.Key)
			end)
			UI.pad(b, 0, 0, 6, 0, 8)
			b.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end
	local function setMeta(data)
		meta.Text = string.format("%s %s\nMood %s %d\n%s", data.PersonalityEmoji or PERSONALITY_EMOJI[data.Personality] or "🙂", data.Personality or "", UI.moodEmoji(data.Mood or 60), data.Mood or 60, UI.hearts(data.Opinion or 0))
	end
	function Panels.OpenDialogue(data)
		current = data
		sheet.Visible = true
		scale.Scale = 0.85
		UI.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		clear(face)
		local _, faceCopy = portrait(face, data.Model, true)
		overlay = faceCopy
		name.Text = data.Name
		sub.Text = data.Title .. "  ·  " .. data.Age .. " years old  ·  " .. (data.Activity or "")
		you.Visible = false
		line.Position = UDim2.fromOffset(180, 64)
		typeOut(data.Text or "")
		setMeta(data)
		setOptions(data.Options)
		if data.Memories and data.Memories[1] then
			ctx.Hud.Toast("💭", data.Name .. " remembers you", "“You " .. data.Memories[1] .. "”", C.Purple)
		end
	end
	function Panels.Choose(key)
		if not current then
			return
		end
		setOptions({})
		local r = request({ Action = "Dialogue", Option = key })
		if not r.Ok then
			Panels.EndDialogue(false)
			return
		end
		if r.PlayerLine then
			you.Visible = true
			you.Text = "You: “" .. r.PlayerLine .. "”"
			line.Position = UDim2.fromOffset(180, 84)
		else
			you.Visible = false
			line.Position = UDim2.fromOffset(180, 64)
		end
		typeOut(r.Text or "")
		current.Mood, current.Opinion = r.Mood or current.Mood, r.Opinion or current.Opinion
		current.Expression = r.Expression or current.Expression
		setMeta(current)
		setOptions(r.Options)
		if r.Done then
			task.delay(2.2, function()
				if current and #optionKeys == 0 then
					Panels.EndDialogue(false)
				end
			end)
		end
	end
	function Panels.EndDialogue(tellServer)
		if tellServer and current then
			task.spawn(request, { Action = "DialogueEnd" })
		end
		current = nil
		typing = {}
		UI.tween(scale, 0.15, { Scale = 0.85 })
		task.delay(0.15, function()
			if not current then
				sheet.Visible = false
			end
		end)
	end
	function Panels.DialogueKey(n)
		if current and optionKeys[n] then
			Panels.Choose(optionKeys[n])
			return true
		end
		return false
	end
	function Panels.InDialogue()
		return current ~= nil
	end
end

--------------------------------------------------------------------------------
-- Elevator, help, settings, welcome, results, busted
--------------------------------------------------------------------------------
local function buildElevator()
	local win = UI.window(screen, "Elevator", "🛗", UDim2.fromOffset(360, 420), C.Teal)
	Panels.Elevator = win
	local body = win.Body
	local title = UI.text(body, "", 15, UI.Bold, C.Sub, { Size = UDim2.new(1, 0, 0, 20) })
	local grid = UI.scroll(body, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28) })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(94, 50), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	function Panels.OpenElevator(data)
		win.Title.Text = if data.Stairs then "Stairs" else "Elevator"
		win.SetIcon(if data.Stairs then "🪜" else "🛗")
		title.Text = "🏢 " .. tostring(data.Building) .. " · you're on " .. (if data.Current == 1 then "the lobby" else "floor " .. data.Current)
		clear(grid)
		for f = data.Floors, 1, -1 do
			local here = f == data.Current
			UI.button(grid, (if f == 1 then "🚪 Lobby" else "Floor " .. f), { Color = if here then C.Teal:Lerp(C.Panel2, 0.4) else C.Panel2, TextSize = 15, LayoutOrder = data.Floors - f }, function()
				if here then
					return
				end
				win.Close()
				ctx.World.Fade(ctx.Hud.Screen, 1)
				local r = request({ Action = "Elevator", Door = data.Door, Floor = f })
				if not r.Ok and r.Error then
					fail(r)
				end
			end)
		end
		win.Open()
	end
end

local function buildHelp()
	local win = UI.window(screen, "How to play", "❓", UDim2.fromOffset(760, 560), C.Gold)
	Panels.Help = win
	local list = UI.scroll(win.Body)
	UI.list(list, Enum.FillDirection.Vertical, 8)
	local sections = {
		{ "🏙️ Welcome to AI City", "Every citizen has a name, a family, a job or a school, a personality, a daily routine and a memory. They wake up, go to work 9 to 5 (or bake bread at 5 AM!), sit at their desks, lift weights at the gym, play soccer after school, chat with friends and go to bed. Watch them, talk to them, and try to become mayor." },
		{ "💬 Talk to people", "Walk up to anyone and press <b>E</b>. Ask about their day, their job, the mayor, the gossip. Tell jokes, give compliments or gifts, ask for directions, ask them to walk with you... They remember everything you do, and they'll tell their friends." },
		{ "🎤 Become mayor", "Go to the stage on the city plaza and press <b>B</b> to give a speech. Pick ideas that match what people care about. Then press <b>V</b> to vote. The mayor gets a salary and can pass one policy a day (<b>N</b>)." },
		{ "🗺️ Find your way", "<b>M</b> opens the city map (tap a place to set a waypoint). <b>P</b> opens the People directory: tap anyone to see their card, or 📍 to find them. Press <b>E</b> at elevator doors to ride up the office towers." },
		{ "⚔️ Fighting", "<b>F</b> (or click with a weapon) attacks, <b>hold X</b> blocks (you take a third of the damage). Buy a 🏏 bat, 🔨 hammer or 🔪 knife at the Hardware store: they hit harder, but using them is a much more serious crime. Tough citizens and the police fight back, so watch your ❤️ health. If you get knocked out, you wake up at the hospital (wanted stars cleared, but there's a bill)." },
		{ "🚨 Crime", "<b>F</b> attacks, <b>G</b> (hold) picks a pocket, <b>R</b> (hold) robs a register or the bank vault. If anyone sees you, you get wanted stars and the police come after you. Get caught and you're BUSTED: a fine and time in jail. Kids can't be hurt." },
		{ "🫥 Losing the police", "The police only know where they <b>last saw</b> you. Break their line of sight (around a corner, into a building) and they'll run there and search around. Hide in a <b>trash can, hedge or park bush</b> (hold <b>Q</b>): they can't see you, unless they search right next to your spot (or saw you climb in!). Stay out of sight and the stars fade one by one, faster while you're hiding. <b>Space</b> gets you out." },
		{ "🦹 Other people's crimes", "You're not the only criminal in town. Pickpockets, bag snatchers, store robbers and graffiti taggers show up now and then (more at night). If someone shouts <b>STOP, THIEF!</b>, chase them down and hit them (<b>F</b>): they give up, the owner gets their things back, you get a reward, and the police take them to jail. Watch your own pockets too: stand still too long and someone might pick them. Visit the police station to see who's locked up in the cell." },
		{ "🥷 Disguises", "Buy a 🧥 <b>hoodie</b>, a 🥷 <b>ski mask</b> or a 🥸 <b>disguise kit</b> at the 👕 Clothing store, and wear them with <b>C</b>. Witnesses may not recognize you (fewer stars, no notoriety, nobody remembers it was you), the police have to get closer to spot you, and it all works much better <b>at night</b>. After a crime, change or take off your outfit where nobody can see: the police keep looking for the old one. But a ski mask in daylight makes people nervous..." },
		{ "⌨️ Keys", "Tab phone · E talk / use · M map · P people · V vote · B speech · N mayor · F attack · X block · 1-4 hotbar · G pickpocket · R rob · Q hide · C wardrobe · H help · 1-9 answer in conversations · Esc close windows" },
	}
	for _, s in ipairs(sections) do
		local card = UI.panel(list, { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Panel2, Radius = 12 })
		UI.pad(card, 12)
		UI.list(card, Enum.FillDirection.Vertical, 4)
		UI.text(card, s[1], 18, UI.Title, C.Gold, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 })
		UI.text(card, s[2], 14, UI.Font, C.Text, { AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2 })
	end
end

local function buildSettings()
	local win = UI.window(screen, "Settings", "⚙️", UDim2.fromOffset(420, 330), C.Sub)
	Panels.Settings = win
	local list = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = win.Body })
	UI.list(list, Enum.FillDirection.Vertical, 10)
	local function toggle(label, get, set)
		local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = list })
		UI.text(row, label, 16, UI.Bold, C.Text, { Size = UDim2.new(1, -100, 1, 0) })
		local button, setColor
		button, setColor = UI.button(row, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(90, 40) }, function()
			set(not get())
			button.Text = if get() then "ON" else "OFF"
			setColor(if get() then C.Green else C.Panel3)
		end)
		button.Text = if get() then "ON" else "OFF"
		setColor(if get() then C.Green else C.Panel3)
	end
	toggle("🏷️ Name tags over people", function()
		return ctx.World.ShowPlates
	end, function(v)
		ctx.World.SetPlates(v)
	end)
	toggle("🔊 Sounds", function()
		return not UI.Muted
	end, function(v)
		UI.Muted = not v
	end)
	toggle("💃 Body language up close", function()
		return ctx.Poses.PoseRadius > 0
	end, function(v)
		ctx.Poses.PoseRadius = if v then 130 else 0
	end)
end

local function buildWelcome()
	local cover = UI.new("Frame", { BackgroundColor3 = C.Bg, BackgroundTransparency = 0.55, Size = UDim2.fromScale(1, 1), ZIndex = 40, Visible = false, Parent = screen })
	UI.gradient(cover, C.White, C.White, 90, NumberSequence.new(0.4, 0))
	local card = UI.panel(cover, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(720, 460), ZIndex = 41, Radius = 22 })
	UI.gradient(card, C.Panel2, C.Panel, 90)
	local scale = UI.new("UIScale", { Parent = card })
	UI.Icons.Badge(card, "city", 76, UI.rgb(40, 60, 130), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), ZIndex = 42, Fill = 0.8 })
	UI.text(card, "AI CITY", 54, UI.Title, C.Gold, { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 60), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 })
	UI.text(card, "A living city of people with jobs, families, feelings and memories.", 17, UI.Font, C.Sub, { Position = UDim2.fromOffset(0, 146), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 })
	local row = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(30, 190), Size = UDim2.new(1, -60, 0, 170), ZIndex = 42, Parent = card })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.25, -9, 1, 0), CellPadding = UDim2.fromOffset(12, 0), Parent = row })
	for _, f in ipairs({ { "chat", "Talk", "Everyone has their own personality and remembers you", C.Blue }, { "mic", "Run for mayor", "Give speeches, win votes, pass laws", UI.rgb(200, 140, 30) }, { "map", "Explore", "Offices, schools, a gym, a lake, a museum...", UI.rgb(60, 170, 110) }, { "siren", "Crime", "...but if anyone sees you, the police will come", UI.rgb(60, 70, 110) } }) do
		local c = UI.panel(row, { BackgroundColor3 = C.Panel3, Radius = 14, ZIndex = 43 })
		UI.pad(c, 10)
		UI.Icons.Badge(c, f[1], 42, f[4], { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), ZIndex = 44 })
		UI.text(c, f[2], 16, UI.Bold, C.Text, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 44 })
		UI.text(c, f[3], 13, UI.Font, C.Sub, { Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 70), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 44 })
	end
	local go = UI.button(card, "▶  Start exploring", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(260, 54), Color = C.Gold, TextColor = C.Bg, TextSize = 19 }, function()
		UI.tween(scale, 0.2, { Scale = 0.8 })
		UI.tween(cover, 0.3, { BackgroundTransparency = 1 })
		task.delay(0.25, function()
			cover.Visible = false
		end)
	end)
	go.ZIndex = 44
	local orbiting
	local function stopOrbit()
		if orbiting then
			orbiting:Disconnect()
			orbiting = nil
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
	end
	go.Activated:Connect(stopOrbit)
	function Panels.Welcome()
		-- a slow flight over downtown behind the welcome card
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		local start = os.clock()
		orbiting = RunService.RenderStepped:Connect(function()
			local a = (os.clock() - start) * 0.08
			local pos = Vector3.new(math.cos(a) * 190, 95 + math.sin(a * 0.7) * 15, math.sin(a) * 190)
			camera.CFrame = CFrame.lookAt(pos, Vector3.new(0, 15, 0))
		end)
		cover.Visible = true
		scale.Scale = 0.8
		UI.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local function buildResults()
	local win = UI.window(screen, "Election Results", "🏆", UDim2.fromOffset(520, 420), C.Gold)
	Panels.Results = win
	local list = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = win.Body })
	UI.list(list, Enum.FillDirection.Vertical, 10)
	function Panels.ShowResults(data)
		clear(list)
		local won = data.WinnerUserId == player.UserId
		UI.text(list, if won then "🎉 YOU WON! You're the new mayor!" else "🏛️ " .. data.Winner .. (if data.Reelected then " was re-elected!" else " is the new mayor!"), 22, UI.Title, C.Gold, { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true })
		local total = 0
		for _, r in ipairs(data.Results) do
			total += r.Votes
		end
		for k, r in ipairs(data.Results) do
			local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = list })
			UI.text(row, (if k == 1 then "🥇 " elseif k == 2 then "🥈 " elseif k == 3 then "🥉 " else "   ") .. r.Name .. (if r.UserId == player.UserId then " (you)" else ""), 16, UI.Bold, C.Text, { Size = UDim2.new(1, -60, 0, 20) })
			UI.text(row, tostring(r.Votes), 16, UI.Bold, C.Gold, { Position = UDim2.new(1, -60, 0, 0), Size = UDim2.fromOffset(60, 20), TextXAlignment = Enum.TextXAlignment.Right })
			local _, set = UI.bar(row, if k == 1 then C.Gold else C.Blue, 12, { Position = UDim2.fromOffset(0, 26) })
			set(0)
			task.delay(0.2 + k * 0.15, function()
				set(r.Votes / math.max(1, total))
			end)
		end
		win.Open()
		ctx.World.Confetti(screen)
	end
end

local function buildBusted()
	local cover = UI.new("Frame", { BackgroundColor3 = UI.rgb(120, 10, 20), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 45, Visible = false, Parent = screen })
	local big = UI.text(cover, "🚔 BUSTED!", 84, UI.Title, C.White, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(800, 100), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 46 })
	UI.new("UIStroke", { Thickness = 4, Color = C.Bg, Parent = big })
	local small = UI.text(cover, "", 20, UI.Bold, C.White, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(800, 60), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, ZIndex = 46 })
	local scale = UI.new("UIScale", { Parent = big })
	function Panels.Busted(data)
		cover.Visible = true
		cover.BackgroundTransparency = 0.2
		small.Text = string.format("You're going to jail for %d seconds.%s", data.Seconds or 30, if (data.Fine or 0) > 0 then "  Fine: 🪙 " .. data.Fine else "")
		scale.Scale = 2.5
		UI.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.World.Shake(1.2, 0.5)
		task.delay(3.5, function()
			UI.tween(cover, 0.5, { BackgroundTransparency = 1 })
			task.wait(0.5)
			cover.Visible = false
		end)
	end
end

--------------------------------------------------------------------------------
-- The phone (Tab): every app in one place
--------------------------------------------------------------------------------
local function buildPhone()
	local phone = UI.new("Frame", { Name = "Phone", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, 600), Size = UDim2.fromOffset(300, 560), BackgroundColor3 = UI.rgb(12, 12, 16), Visible = false, ZIndex = 30, Parent = screen })
	UI.corner(phone, 38)
	UI.stroke(phone, UI.rgb(80, 80, 96), 3, 0)
	local screenArea = UI.new("Frame", { Name = "Screen", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), ClipsDescendants = true, BackgroundColor3 = UI.rgb(40, 30, 90), ZIndex = 31, Parent = phone })
	UI.corner(screenArea, 30)
	UI.gradient(screenArea, UI.rgb(90, 70, 200), UI.rgb(20, 60, 120), 135)
	-- the status bar: time, coins
	local status = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), ZIndex = 32, Parent = screenArea })
	local clock = UI.text(status, "9:30", 14, UI.Bold, C.White, { Position = UDim2.fromOffset(24, 8), Size = UDim2.fromOffset(80, 20), ZIndex = 33 })
	local coins = UI.text(status, "🪙 0", 13, UI.Bold, C.White, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 8), Size = UDim2.fromOffset(120, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 33 })
	local notch = UI.new("Frame", { BackgroundColor3 = UI.rgb(12, 12, 16), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(90, 22), ZIndex = 33, Parent = screenArea })
	UI.corner(notch, 11)
	-- home screen: a greeting and the apps
	local home = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -80), ZIndex = 32, Parent = screenArea })
	local hello = UI.text(home, "", 26, UI.Title, C.White, { Position = UDim2.fromOffset(20, 6), Size = UDim2.new(1, -40, 0, 32), TextScaled = true, ZIndex = 33 })
	UI.new("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 14, Parent = hello })
	local sub = UI.text(home, "", 13, UI.Font, UI.rgb(220, 220, 255), { Position = UDim2.fromOffset(20, 38), Size = UDim2.new(1, -40, 0, 18), ZIndex = 33 })
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 76), Size = UDim2.new(1, -32, 1, -80), ZIndex = 32, Parent = home })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(74, 86), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	-- the goals page
	local page = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -80), Visible = false, ZIndex = 32, Parent = screenArea })
	UI.text(page, "🎯 Today's goals", 22, UI.Title, C.White, { Position = UDim2.fromOffset(20, 6), Size = UDim2.new(1, -40, 0, 30), ZIndex = 33 })
	local goalList = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 46), Size = UDim2.new(1, -32, 1, -50), ZIndex = 32, Parent = page })
	UI.list(goalList, Enum.FillDirection.Vertical, 8)
	local open = false
	local P = {}
	Panels.Phone = P
	local function showHome()
		home.Visible, page.Visible = true, false
	end
	local function showGoals()
		home.Visible, page.Visible = false, true
		clear(goalList)
		local goals = ctx.Hud.GoalData or {}
		for k, g in ipairs(goals) do
			local card = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = k, ZIndex = 33, Parent = goalList })
			UI.corner(card, 14)
			UI.text(card, g.Emoji, 26, UI.Font, C.White, { Position = UDim2.fromOffset(8, 10), Size = UDim2.fromOffset(40, 40), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 34 })
			UI.text(card, g.Text, 13, UI.Bold, C.White, { Position = UDim2.fromOffset(54, 8), Size = UDim2.new(1, -62, 0, 32), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 34 })
			UI.text(card, if g.Done then "✅ Done! +" .. g.Reward .. " 🪙" else g.Have .. " / " .. g.Need .. "   ·   🪙 " .. g.Reward, 12, UI.Bold, if g.Done then C.Green else C.Gold, { Position = UDim2.fromOffset(54, 40), Size = UDim2.new(1, -62, 0, 16), ZIndex = 34 })
		end
		if #goals == 0 then
			UI.text(goalList, "New goals every morning!", 14, UI.Font, C.White, { ZIndex = 33 })
		end
	end
	local function app(order, emoji, name, color, fn)
		local b = UI.new("TextButton", { BackgroundTransparency = 1, Text = "", LayoutOrder = order, ZIndex = 33, Parent = grid })
		local icon = UI.Icons.Badge(b, emoji, 60, color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), ZIndex = 34 })
		UI.text(b, name, 12, UI.Bold, C.White, { Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 34 })
		local scale = UI.new("UIScale", { Parent = icon })
		b.MouseEnter:Connect(function()
			UI.tween(scale, 0.12, { Scale = 1.08 })
		end)
		b.MouseLeave:Connect(function()
			UI.tween(scale, 0.12, { Scale = 1 })
		end)
		b.Activated:Connect(function()
			UI.sound("pop", 0.25, 1.2)
			UI.tween(scale, 0.06, { Scale = 0.9 })
			task.delay(0.08, function()
				fn()
			end)
		end)
	end
	app(1, "🗺️", "Map", UI.rgb(60, 170, 110), function()
		P.Close()
		Panels.Map.Open()
	end)
	app(2, "👥", "People", UI.rgb(150, 90, 230), function()
		P.Close()
		Panels.OpenDirectory("People")
	end)
	app(3, "📰", "News", UI.rgb(230, 90, 80), function()
		P.Close()
		Panels.OpenDirectory("News")
	end)
	app(4, "🗳️", "Vote", UI.rgb(70, 130, 240), function()
		P.Close()
		Panels.Vote.Open()
	end)
	app(5, "🎯", "Goals", UI.rgb(240, 170, 40), showGoals)
	app(6, "🎤", "Speech", UI.rgb(200, 140, 30), function()
		P.Close()
		Panels.Speech.Open()
	end)
	app(7, "🏛️", "Mayor", UI.rgb(130, 100, 50), function()
		P.Close()
		Panels.Mayor.Open()
	end)
	app(8, "🥷", "Wardrobe", UI.rgb(120, 80, 190), function()
		P.Close()
		Panels.ToggleWardrobe()
	end)
	app(9, "❓", "Help", UI.rgb(80, 90, 120), function()
		P.Close()
		Panels.Help.Open()
	end)
	app(10, "⚙️", "Settings", UI.rgb(110, 110, 130), function()
		P.Close()
		Panels.Settings.Open()
	end)
	-- the home bar: back to the home screen
	local homeBar = UI.new("TextButton", { BackgroundColor3 = C.White, BackgroundTransparency = 0.3, Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(110, 6), ZIndex = 35, Parent = screenArea })
	UI.corner(homeBar, 3)
	homeBar.Activated:Connect(showHome)
	function P.IsOpen()
		return open
	end
	function P.Open()
		if open then
			return
		end
		open = true
		showHome()
		phone.Visible = true
		local name = player.DisplayName
		local h = game:GetService("Lighting").ClockTime
		hello.Text = (if h < 12 then "Good morning" elseif h < 18 then "Good afternoon" else "Good evening") .. "!"
		local state = ReplicatedStorage:FindFirstChild("CityState")
		sub.Text = name .. (if state then " · " .. (state:GetAttribute("Weekday") or "") .. " · " .. string.lower(state:GetAttribute("StateLabel") or "stable") else "")
		clock.Text = (UI.formatHour(h))
		coins.Text = "🪙 " .. UI.commas(player:GetAttribute("Coins") or 0)
		phone.Position = UDim2.new(1, -24, 1, 600)
		UI.tween(phone, 0.35, { Position = UDim2.new(1, -24, 1, -110) }, Enum.EasingStyle.Back)
		UI.sound("click", 0.3, 1.5)
	end
	function P.Close()
		if not open then
			return
		end
		open = false
		UI.tween(phone, 0.25, { Position = UDim2.new(1, -24, 1, 600) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.25, function()
			if not open then
				phone.Visible = false
			end
		end)
	end
	function P.Toggle()
		if open then
			P.Close()
		else
			P.Open()
		end
	end
end

--------------------------------------------------------------------------------
-- The weapons shop (Hardware store)
--------------------------------------------------------------------------------
local function buildShop()
	local win = UI.window(screen, "Hardware Store", "🔨", UDim2.fromOffset(760, 460), C.Red)
	Panels.Shop = win
	local body = win.Body
	local top = UI.text(body, "", 15, UI.Bold, C.Sub, { Size = UDim2.new(1, 0, 0, 22) })
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -64), Parent = body })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 1, 0), CellPadding = UDim2.fromOffset(10, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	UI.text(body, "⚠️ Hurting people is a crime. Anyone who sees it calls the police, and they take your weapons when they arrest you.", 12, UI.Font, C.Dim, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 30), TextWrapped = true })
	local function stat(card, label, value, maxValue, color, y)
		UI.text(card, label, 12, UI.Bold, C.Sub, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(70, 16) })
		local _, set = UI.bar(card, color, 8, { Position = UDim2.new(0, 72, 0, y + 4), Size = UDim2.new(1, -72, 0, 8) })
		set(value / maxValue)
	end
	function Panels.OpenShop(data)
		clear(grid)
		top.Text = "🪙 You have " .. UI.commas(data.Coins or 0) .. " coins. Weapons go in your hotbar (1, 2, 3...)."
		for k, item in ipairs(data.Items or {}) do
			local card = UI.panel(grid, { BackgroundColor3 = C.Panel2, Radius = 14, LayoutOrder = k })
			UI.pad(card, 12)
			UI.Icons.Badge(card, item.Id, 54, UI.rgb(150, 50, 60), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Fill = 0.78 })
			UI.text(card, item.Name, 18, UI.Title, C.Text, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
			UI.text(card, item.Desc, 12, UI.Font, C.Sub, { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 48), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
			stat(card, "Damage", item.Damage, 60, C.Red, 138)
			stat(card, "Speed", 1 / item.Cooldown, 2.6, C.Gold, 158)
			stat(card, "Reach", item.Range, 8, C.Blue, 178)
			UI.button(card, if item.Owned then "✅ Owned" else "🪙 " .. item.Price .. "  Buy", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 40), Color = if item.Owned then C.Panel3 else C.Gold, TextColor = if item.Owned then C.Sub else C.Bg }, function()
				if item.Owned then
					return
				end
				local r = request({ Action = "BuyWeapon", Id = item.Id })
				if r.Ok then
					ctx.Hud.Toast(item.Emoji, "Bought a " .. item.Name .. "!", "It's in your hotbar. Click or F to attack, hold X to block.", C.Gold)
					data.Items = r.Items
					data.Coins = (data.Coins or 0) - item.Price
					Panels.OpenShop(data)
				else
					fail(r)
				end
			end)
		end
		win.Open()
	end
end

-- The wardrobe: hoodies, ski masks and disguises (and the Clothing store)
local function buildWardrobe()
	local win = UI.window(screen, "Wardrobe", "🥷", UDim2.fromOffset(760, 480), C.Purple)
	Panels.Wardrobe = win
	local body = win.Body
	local top = UI.text(body, "", 15, UI.Bold, C.Sub, { Size = UDim2.new(1, 0, 0, 22), RichText = true })
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -70), Parent = body })
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 1, 0), CellPadding = UDim2.fromOffset(10, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	UI.text(body, "🌙 Everything hides you better at night. Wear a top and a face item together. After a crime, change or take them off (C) where nobody can see you: the police will be looking for the wrong person.", 12, UI.Font, C.Dim, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 34), TextWrapped = true })
	local function stat(card, label, value, color, y, text)
		UI.text(card, label, 12, UI.Bold, C.Sub, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(78, 16) })
		local _, set = UI.bar(card, color, 8, { Position = UDim2.new(0, 80, 0, y + 4), Size = UDim2.new(1, -118, 0, 8) })
		set(value)
		UI.text(card, text, 12, UI.Bold, C.Text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, y), Size = UDim2.fromOffset(34, 16), TextXAlignment = Enum.TextXAlignment.Right })
	end
	local current
	function Panels.OpenWardrobe(data)
		current = data
		clear(grid)
		local hidden = math.floor((data.Hidden or 0) * 100 + 0.5)
		top.Text = (if data.Store then "👕 <b>Clothing store</b> · 🪙 " .. UI.commas(data.Coins or 0) .. " coins · " else "") .. "You're " .. hidden .. "% hidden right now" .. (if data.Night then " 🌙" else " ☀️")
		for k, item in ipairs(data.Items or {}) do
			local card = UI.panel(grid, { BackgroundColor3 = if item.Wearing then UI.rgb(58, 44, 86) else C.Panel2, Radius = 14, LayoutOrder = k })
			if item.Wearing then
				UI.stroke(card, C.Purple, 2, 0)
			end
			UI.pad(card, 12)
			UI.Icons.Badge(card, item.Id, 54, UI.rgb(110, 80, 180), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Fill = 0.78 })
			UI.text(card, item.Name, 18, UI.Title, C.Text, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
			UI.text(card, (if item.Slot == "Top" then "TOP · " else "FACE · ") .. item.Desc, 12, UI.Font, C.Sub, { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 62), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
			stat(card, "☀️ Hidden", item.Hidden, C.Blue, 152, math.floor(item.Hidden * 100) .. "%")
			stat(card, "🌙 At night", math.min(0.95, item.Hidden + item.Night), C.Purple, 172, math.floor(math.min(0.95, item.Hidden + item.Night) * 100) .. "%")
			stat(card, "👀 Noticed", item.Suspicious, C.Red, 192, if item.Suspicious > 0 then "day" else "no")
			local label, color, textColor
			if item.Owned then
				label, color, textColor = if item.Wearing then "Take off" else "Put on", if item.Wearing then C.Panel3 else C.Purple, C.White
			elseif data.Store then
				label, color, textColor = "🪙 " .. item.Price .. "  Buy", C.Gold, C.Bg
			else
				label, color, textColor = "👕 At the Clothing store", C.Panel3, C.Sub
			end
			UI.button(card, label, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 40), Color = color, TextColor = textColor }, function()
				local r
				if item.Owned then
					r = request({ Action = "Wear", Id = item.Id, On = not item.Wearing, Store = data.Store })
				elseif data.Store then
					r = request({ Action = "BuyOutfit", Id = item.Id })
				else
					return
				end
				if r.Ok then
					if r.Text then
						ctx.Hud.Toast(item.Emoji, r.Text, if item.Owned then "" else "Put it on or take it off anytime with C.", C.Purple)
					end
					r.Store = data.Store
					Panels.OpenWardrobe(r)
				else
					fail(r)
				end
			end)
		end
		win.Open()
	end
	-- C: open your wardrobe anywhere
	function Panels.ToggleWardrobe()
		if win.IsOpen() then
			win.Close()
			return
		end
		local r = request({ Action = "Wardrobe" })
		if r and r.Ok then
			Panels.OpenWardrobe(r)
		end
	end
end

-- knocked out: the screen fades, you wake up at the hospital
local function buildDown()
	local cover = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 45, Visible = false, Parent = screen })
	local big = UI.text(cover, "💫 KNOCKED OUT", 72, UI.Title, C.White, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(800, 90), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 46 })
	UI.new("UIStroke", { Thickness = 4, Color = C.Red, Parent = big })
	local small = UI.text(cover, "", 20, UI.Bold, C.Sub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(800, 60), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, ZIndex = 46 })
	local scale = UI.new("UIScale", { Parent = big })
	function Panels.Down(data)
		cover.Visible = true
		cover.BackgroundTransparency = 1
		UI.tween(cover, 1.2, { BackgroundTransparency = 0.15 })
		small.Text = "You'll wake up at the hospital." .. (if (data.Bill or 0) > 0 then "  Hospital bill: 🪙 " .. data.Bill else "")
		scale.Scale = 0.6
		UI.tween(scale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(4.5, function()
			UI.tween(cover, 0.8, { BackgroundTransparency = 1 })
			task.wait(0.8)
			cover.Visible = false
		end)
	end
end

function Panels.Start(context)
	ctx = context
	screen = UI.new("ScreenGui", { Name = "CityPanels", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 10, Parent = player:WaitForChild("PlayerGui") })
	Panels.Screen = screen
	local uiScale = UI.new("UIScale", { Parent = screen })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 720), 0.55, 1.15)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	buildMap()
	buildProfile()
	buildDirectory()
	buildSpeech()
	buildMayor()
	buildVote()
	buildDialogue()
	buildElevator()
	buildHelp()
	buildSettings()
	buildWelcome()
	buildResults()
	buildBusted()
	buildShop()
	buildWardrobe()
	buildDown()
	buildPhone()
end

return Panels
