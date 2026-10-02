--[[
	SPEED VS BRAINROT  -  Admin panel (LocalScript)
	Put this in: StarterPlayer > StarterPlayerScripts

	Admins get an ADMIN button (top right, or press F2). Everything is clicks:
	  PLAYERS  pick a player (or Everyone) and give cash / speed / trophies / pets,
	           teleport to them, bring them, send them to a map, unlock maps or
	           prestige, god mode, reset, kick
	  SERVER   announce a message to everyone, start a cash event (x2 / x5 / x10),
	           remove all bosses
	  ADMINS   (game owner only) add an admin by clicking a player or typing a
	           username, and remove admins. The list is saved for every server.
	The server checks every click, so nobody else can use these.
	Everyone also sees admin announcements as a big banner.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SVB_Remotes")
local AdminRemote = remotes:WaitForChild("Admin")
local AnnounceRemote = remotes:WaitForChild("Announce")
local PetInfo = ReplicatedStorage:WaitForChild("SVB_Pets")
local MapInfo = ReplicatedStorage:WaitForChild("SVB_Maps")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local BG = Color3.fromRGB(30, 33, 46)
local CARD = Color3.fromRGB(44, 48, 66)
local ACCENT = Color3.fromRGB(255, 80, 90)

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then inst[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	inst.Parent = props and props.Parent
	return inst
end
local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 10), Parent = p }) end
local function stroke(p, c, t) return new("UIStroke", { Color = c, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p }) end
local function text(parent, str, size, props)
	local l = new("TextLabel", { BackgroundTransparency = 1, Font = FONT, Text = str, TextColor3 = WHITE, TextScaled = true, Size = size, Parent = parent })
	new("UIStroke", { Color = Color3.fromRGB(15, 15, 20), Thickness = 2, Parent = l })
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end
local function button(parent, str, color, size, onClick)
	local b = new("TextButton", { BackgroundColor3 = color, Size = size, Text = "", AutoButtonColor = true, Parent = parent })
	corner(b, 8)
	stroke(b, color:Lerp(Color3.new(0, 0, 0), 0.45), 2)
	text(b, str, UDim2.new(1, -10, 1, -8), { Position = UDim2.fromOffset(5, 4) })
	b.Activated:Connect(onClick)
	return b
end
-- a button you have to press twice (for reset / kick)
local function dangerButton(parent, str, size, onConfirm)
	local armed = false
	local b
	b = button(parent, str, Color3.fromRGB(200, 60, 70), size, function()
		local label = b:FindFirstChildOfClass("TextLabel")
		if armed then
			armed = false
			label.Text = str
			onConfirm()
		else
			armed = true
			label.Text = "Sure? Click again"
			task.delay(3, function()
				if armed then
					armed = false
					label.Text = str
				end
			end)
		end
	end)
	return b
end

------------------------------------------------------------------------
-- Announcement banner (everyone sees these)
------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "SVB_Admin", ResetOnSpawn = false, DisplayOrder = 30, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })
-- fits any screen: full size on a computer, shrinks to fit a phone
local uiScale = new("UIScale", { Scale = 0.85, Parent = gui })
local function fitScreen()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
	uiScale.Scale = math.min(0.85, v.X / 800, (v.Y - 20) / 520)
end
fitScreen()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScreen) end

local banner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -140),
	Size = UDim2.new(0.7, 0, 0, 96),
	BackgroundColor3 = Color3.fromRGB(25, 20, 40),
	BackgroundTransparency = 0.1,
	Parent = gui,
})
corner(banner, 16)
local bannerStroke = stroke(banner, Color3.fromRGB(255, 215, 60), 3)
local bannerFrom = text(banner, "", UDim2.new(1, -30, 0, 26), { Position = UDim2.fromOffset(15, 8), TextColor3 = Color3.fromRGB(255, 215, 60) })
local bannerText = text(banner, "", UDim2.new(1, -30, 0, 50), { Position = UDim2.fromOffset(15, 38) })
local bannerToken = 0
AnnounceRemote.OnClientEvent:Connect(function(message, from)
	bannerToken += 1
	local token = bannerToken
	bannerFrom.Text = (from == "EVENT") and "SERVER EVENT" or ("ANNOUNCEMENT FROM " .. string.upper(tostring(from)))
	bannerStroke.Color = (from == "EVENT") and Color3.fromRGB(120, 255, 110) or Color3.fromRGB(255, 215, 60)
	bannerText.Text = tostring(message)
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	task.delay(6, function()
		if token == bannerToken then
			TweenService:Create(banner, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -140) }):Play()
		end
	end)
end)

------------------------------------------------------------------------
-- The panel (only built for admins)
------------------------------------------------------------------------
local built = false
local function buildPanel()
	if built then return end
	built = true

	local openButton = button(gui, "ADMIN", ACCENT, UDim2.fromOffset(110, 40), function() end)
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -16, 0, 60)

	local panel = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 480),
		BackgroundColor3 = BG,
		Visible = false,
		Parent = gui,
	})
	corner(panel, 16)
	stroke(panel, ACCENT, 3)
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = ACCENT, Parent = panel })
	corner(head, 16)
	text(head, "ADMIN PANEL", UDim2.new(0, 260, 0, 34), { Position = UDim2.fromOffset(16, 7), TextXAlignment = Enum.TextXAlignment.Left })
	local status = text(head, "", UDim2.new(0, 300, 0, 22), { Position = UDim2.new(1, -370, 0, 13), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 240, 200) })
	local close = button(head, "X", Color3.fromRGB(60, 20, 25), UDim2.fromOffset(40, 36), function() panel.Visible = false end)
	close.Position = UDim2.new(1, -48, 0, 6)

	local function toggle()
		panel.Visible = not panel.Visible
	end
	openButton.Activated:Connect(toggle)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F2 then toggle() end
	end)

	-- left: players
	local selectedId, selectedName = 0, "Everyone"
	local listFrame = new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(0, 190, 1, -72),
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	})
	corner(listFrame, 10)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = listFrame })
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10), Parent = listFrame })

	-- right: tabs
	local tabs = {}
	local tabBar = new("Frame", { Position = UDim2.fromOffset(214, 60), Size = UDim2.new(1, -226, 0, 36), BackgroundTransparency = 1, Parent = panel })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = tabBar })
	local pages = new("Frame", { Position = UDim2.fromOffset(214, 104), Size = UDim2.new(1, -226, 1, -116), BackgroundTransparency = 1, Parent = panel })
	local function showTab(name)
		for n, t in pairs(tabs) do
			t.page.Visible = n == name
			t.button.BackgroundColor3 = (n == name) and ACCENT or CARD
		end
		if name == "Admins" then AdminRemote:FireServer("getAdmins") end
	end
	local function tab(name, order)
		local page = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false, Parent = pages })
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
		local b = button(tabBar, name, CARD, UDim2.fromOffset(120, 34), function() showTab(name) end)
		b.LayoutOrder = order
		tabs[name] = { page = page, button = b }
		return page
	end

	-- a row of buttons with a title
	local rowOrder = 0
	local function row(page, title, buttons)
		rowOrder += 1
		local r = new("Frame", { Size = UDim2.new(1, -10, 0, 64), BackgroundColor3 = CARD, LayoutOrder = rowOrder, Parent = page })
		corner(r, 10)
		text(r, title, UDim2.new(1, -16, 0, 18), { Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 205, 230) })
		local holder = new("ScrollingFrame", { Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 34), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), Parent = r })
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = holder })
		for _, spec in ipairs(buttons) do
			if spec.danger then
				dangerButton(holder, spec[1], UDim2.fromOffset(spec.w or 100, 32), spec[2])
			elseif spec.box then
				local box = new("TextBox", { Size = UDim2.fromOffset(spec.w or 160, 32), BackgroundColor3 = Color3.fromRGB(20, 22, 32), Font = FONT, TextScaled = true, Text = "", PlaceholderText = spec[1], TextColor3 = WHITE, PlaceholderColor3 = Color3.fromRGB(120, 125, 150), ClearTextOnFocus = false, Parent = holder })
				corner(box, 8)
				spec.ref.box = box
			else
				button(holder, spec[1], spec.color or Color3.fromRGB(70, 130, 220), UDim2.fromOffset(spec.w or 100, 32), spec[2])
			end
		end
		return r
	end

	local function act(action, a, b)
		AdminRemote:FireServer(action, selectedId, a, b)
	end
	local GREEN, GOLDC, BLUE, PURPLE = Color3.fromRGB(60, 170, 75), Color3.fromRGB(215, 160, 30), Color3.fromRGB(70, 130, 220), Color3.fromRGB(140, 90, 220)

	-- PLAYERS tab
	local pPage = tab("Player", 1)
	local who = text(pPage, "Everyone", UDim2.new(1, -10, 0, 28), { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 215, 60), LayoutOrder = 0 })
	row(pPage, "Cash", {
		{ "+1K", function() act("cash", 1e3) end, color = GREEN, w = 80 },
		{ "+1M", function() act("cash", 1e6) end, color = GREEN, w = 80 },
		{ "+1B", function() act("cash", 1e9) end, color = GREEN, w = 80 },
		{ "+1T", function() act("cash", 1e12) end, color = GREEN, w = 80 },
	})
	row(pPage, "Speed", {
		{ "+100", function() act("speed", 100) end, color = Color3.fromRGB(220, 70, 70), w = 80 },
		{ "+1K", function() act("speed", 1e3) end, color = Color3.fromRGB(220, 70, 70), w = 80 },
		{ "+10K", function() act("speed", 1e4) end, color = Color3.fromRGB(220, 70, 70), w = 80 },
		{ "+100K", function() act("speed", 1e5) end, color = Color3.fromRGB(220, 70, 70), w = 80 },
	})
	row(pPage, "Trophies", {
		{ "+100", function() act("trophies", 100) end, color = GOLDC, w = 80 },
		{ "+10K", function() act("trophies", 1e4) end, color = GOLDC, w = 80 },
		{ "+1M", function() act("trophies", 1e6) end, color = GOLDC, w = 80 },
	})
	local custom = {}
	row(pPage, "Custom amount (use a minus to take away)", {
		{ "Amount", box = true, ref = custom, w = 150 },
		{ "Cash", function() act("cash", tonumber(custom.box.Text)) end, color = GREEN, w = 80 },
		{ "Speed", function() act("speed", tonumber(custom.box.Text)) end, color = Color3.fromRGB(220, 70, 70), w = 80 },
		{ "Trophies", function() act("trophies", tonumber(custom.box.Text)) end, color = GOLDC, w = 90 },
	})
	row(pPage, "Move", {
		{ "Go to them", function() act("tpTo") end, w = 110 },
		{ "Bring here", function() act("bring") end, w = 110 },
		{ "To Map 1", function() act("toMap", 1) end, color = PURPLE, w = 100 },
		{ "To Map 2", function() act("toMap", 2) end, color = PURPLE, w = 100 },
	})
	local zoneBox = {}
	row(pPage, "Send to a zone (type the zone number)", {
		{ "Zone #", box = true, ref = zoneBox, w = 90 },
		{ "Map 1 zone", function() act("toZone", 1, tonumber(zoneBox.box.Text) or 1) end, color = PURPLE, w = 120 },
		{ "Map 2 zone", function() act("toZone", 2, tonumber(zoneBox.box.Text) or 1) end, color = PURPLE, w = 120 },
	})
	row(pPage, "Progress", {
		{ "Unlock maps", function() act("unlockMaps") end, color = PURPLE, w = 130 },
		{ "Unlock prestige", function() act("prestigeReady") end, color = PURPLE, w = 150 },
		{ "+1 rebirth", function() act("rebirths", 1) end, color = Color3.fromRGB(240, 130, 40), w = 110 },
		{ "+10 rebirths", function() act("rebirths", 10) end, color = Color3.fromRGB(240, 130, 40), w = 120 },
	})
	row(pPage, "Fun", {
		{ "God mode", function() act("god") end, color = GOLDC, w = 100 },
		{ "Freeze", function() act("freeze") end, color = BLUE, w = 90 },
		{ "Respawn", function() act("respawn") end, color = BLUE, w = 100 },
		{ "Pause boss", function() act("pauseBoss") end, color = PURPLE, w = 110 },
	})
	row(pPage, "Size", {
		{ "Tiny", function() act("size", 0.5) end, color = BLUE, w = 80 },
		{ "Normal", function() act("size", 1) end, color = BLUE, w = 90 },
		{ "Big", function() act("size", 2) end, color = BLUE, w = 80 },
		{ "Giant", function() act("size", 3.5) end, color = BLUE, w = 90 },
	})
	local kickReason = {}
	row(pPage, "Danger zone", {
		{ "Reset data", function() act("reset") end, danger = true, w = 150 },
		{ "Kick reason", box = true, ref = kickReason, w = 150 },
		{ "Kick", function() act("kick", kickReason.box.Text) end, danger = true, w = 150 },
	})

	-- pets: a grid of every pet, normal / golden / rainbow
	rowOrder += 1
	local petCard = new("Frame", { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = CARD, LayoutOrder = rowOrder, Parent = pPage })
	corner(petCard, 10)
	text(petCard, "Give a pet", UDim2.new(1, -16, 0, 18), { Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 205, 230) })
	local tier = 1
	local tierButtons = {}
	local tierBar = new("Frame", { Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 30), BackgroundTransparency = 1, Parent = petCard })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = tierBar })
	for i, name in ipairs({ "Normal", "Golden", "Rainbow" }) do
		tierButtons[i] = button(tierBar, name, (i == 1) and ACCENT or Color3.fromRGB(70, 75, 100), UDim2.fromOffset(100, 28), function()
			tier = i
			for j, b in ipairs(tierButtons) do b.BackgroundColor3 = (j == i) and ACCENT or Color3.fromRGB(70, 75, 100) end
		end)
	end
	local allPetsButton = button(tierBar, "Give ALL pets", GREEN, UDim2.fromOffset(140, 28), function()
		act("allPets", tier)
	end)
	allPetsButton.LayoutOrder = 10
	local grid = new("Frame", { Position = UDim2.fromOffset(8, 62), Size = UDim2.new(1, -16, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = petCard })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(122, 30), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	new("UIPadding", { PaddingBottom = UDim.new(0, 10), Parent = petCard })
	local pets = PetInfo:GetChildren()
	table.sort(pets, function(a, b) return (a:GetAttribute("Bonus") or 0) < (b:GetAttribute("Bonus") or 0) end)
	for i, info in ipairs(pets) do
		local col = info:GetAttribute("RarityColor") or WHITE
		local b = button(grid, info.Name, col:Lerp(Color3.fromRGB(40, 40, 55), 0.55), UDim2.fromOffset(122, 30), function()
			act("pet", info.Name, tier)
		end)
		b.LayoutOrder = i
	end

	-- SERVER tab
	local sPage = tab("Server", 2)
	local announce = {}
	row(sPage, "Announce to everyone", {
		{ "Type a message...", box = true, ref = announce, w = 330 },
		{ "Send", function()
			AdminRemote:FireServer("announce", 0, announce.box.Text)
			announce.box.Text = ""
		end, color = GOLDC, w = 90 },
	})
	row(sPage, "Cash event (every pickup is worth more, for everyone)", {
		{ "Off", function() AdminRemote:FireServer("event", 0, 1) end, color = Color3.fromRGB(90, 95, 115), w = 80 },
		{ "x2", function() AdminRemote:FireServer("event", 0, 2) end, color = GREEN, w = 80 },
		{ "x5", function() AdminRemote:FireServer("event", 0, 5) end, color = GREEN, w = 80 },
		{ "x10", function() AdminRemote:FireServer("event", 0, 10) end, color = GREEN, w = 80 },
	})
	local function server(action, value) return function() AdminRemote:FireServer(action, 0, value) end end
	row(sPage, "Speed event (everyone runs faster)", {
		{ "Off", server("speedEvent", 1), color = Color3.fromRGB(90, 95, 115), w = 80 },
		{ "x1.5", server("speedEvent", 1.5), color = Color3.fromRGB(220, 70, 70), w = 80 },
		{ "x2", server("speedEvent", 2), color = Color3.fromRGB(220, 70, 70), w = 80 },
		{ "x3", server("speedEvent", 3), color = Color3.fromRGB(220, 70, 70), w = 80 },
	})
	row(sPage, "Trophy event (more trophies for every zone)", {
		{ "Off", server("trophyEvent", 1), color = Color3.fromRGB(90, 95, 115), w = 80 },
		{ "x2", server("trophyEvent", 2), color = GOLDC, w = 80 },
		{ "x5", server("trophyEvent", 5), color = GOLDC, w = 80 },
		{ "x10", server("trophyEvent", 10), color = GOLDC, w = 80 },
	})
	row(sPage, "Cash rain + gravity", {
		{ "Cash rain!", server("cashRain"), color = GREEN, w = 120 },
		{ "Low gravity", server("gravity", 60), color = BLUE, w = 120 },
		{ "Normal gravity", server("gravity", 196.2), color = Color3.fromRGB(90, 95, 115), w = 140 },
	})
	row(sPage, "Time of day", {
		{ "Zones decide", server("time", nil), color = Color3.fromRGB(90, 95, 115), w = 130 },
		{ "Day", server("time", 13), color = GOLDC, w = 80 },
		{ "Sunset", server("time", 18), color = Color3.fromRGB(240, 130, 40), w = 90 },
		{ "Night", server("time", 0), color = Color3.fromRGB(60, 70, 140), w = 80 },
	})
	row(sPage, "Bosses", {
		{ "Remove all", function() AdminRemote:FireServer("clearBosses", 0) end, color = PURPLE, w = 110 },
		{ "Slow", server("bossSpeed", 0.6), color = PURPLE, w = 80 },
		{ "Normal", server("bossSpeed", 1), color = Color3.fromRGB(90, 95, 115), w = 90 },
		{ "Fast", server("bossSpeed", 1.5), color = Color3.fromRGB(200, 60, 70), w = 80 },
		{ "Pause", server("bossSpeed", 0), color = BLUE, w = 80 },
	})

	-- ME tab: things for the admin themselves (fly, spectate)
	local mPage = tab("Me", 4)
	local flySpeed, flyConn, flyVel = 80, nil, nil
	local function stopFly()
		if flyConn then flyConn:Disconnect() flyConn = nil end
		if flyVel then flyVel:Destroy() flyVel = nil end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.PlatformStand = false end
	end
	local function startFly()
		stopFly()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum then return end
		local att = root:FindFirstChild("RootAttachment") or new("Attachment", { Parent = root })
		flyVel = new("LinearVelocity", { Attachment0 = att, MaxForce = math.huge, RelativeTo = Enum.ActuatorRelativeTo.World, VectorVelocity = Vector3.zero, Parent = root })
		hum.PlatformStand = true
		-- move with the normal controls (keys, thumbstick); look up or down to climb or dive.
		-- Space goes up, Ctrl goes down on a keyboard
		flyConn = RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			local look = cam.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			local move = hum.MoveDirection
			local v = move
			if move.Magnitude > 0 and flat.Magnitude > 0 then
				v = move + Vector3.new(0, look.Y * move:Dot(flat.Unit) * 1.5, 0)
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then v += Vector3.yAxis end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then v -= Vector3.yAxis end
			flyVel.VectorVelocity = v * flySpeed
			if flat.Magnitude > 0 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
		end)
	end
	player.CharacterAdded:Connect(function() flyConn, flyVel = nil, nil end)
	row(mPage, "Fly (move normally, look up or down to climb)", {
		{ "Fly ON", startFly, color = GREEN, w = 100 },
		{ "Fly OFF", stopFly, color = Color3.fromRGB(90, 95, 115), w = 100 },
		{ "Slow", function() flySpeed = 40 end, color = BLUE, w = 70 },
		{ "Fast", function() flySpeed = 150 end, color = BLUE, w = 70 },
		{ "Zoom", function() flySpeed = 400 end, color = BLUE, w = 70 },
	})
	row(mPage, "Spectate (pick a player on the left first)", {
		{ "Watch them", function()
			local target = Players:GetPlayerByUserId(selectedId)
			local hum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
			if hum then workspace.CurrentCamera.CameraSubject = hum end
		end, color = PURPLE, w = 130 },
		{ "Back to me", function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then workspace.CurrentCamera.CameraSubject = hum end
		end, color = Color3.fromRGB(90, 95, 115), w = 130 },
	})
	row(mPage, "Quick: give yourself", {
		{ "God mode", function() AdminRemote:FireServer("god", player.UserId) end, color = GOLDC, w = 110 },
		{ "+1B cash", function() AdminRemote:FireServer("cash", player.UserId, 1e9) end, color = GREEN, w = 110 },
		{ "+100K speed", function() AdminRemote:FireServer("speed", player.UserId, 1e5) end, color = Color3.fromRGB(220, 70, 70), w = 130 },
	})

	-- ADMINS tab (owner only)
	local aPage
	local adminRows = {}
	local function fillAdmins(list)
		if not aPage then return end
		for _, r in ipairs(adminRows) do r:Destroy() end
		table.clear(adminRows)
		if #list == 0 then
			table.insert(adminRows, text(aPage, "No extra admins yet.", UDim2.new(1, -10, 0, 24), { LayoutOrder = 100, TextColor3 = Color3.fromRGB(180, 185, 210) }))
		end
		for i, a in ipairs(list) do
			local r = new("Frame", { Size = UDim2.new(1, -10, 0, 40), BackgroundColor3 = CARD, LayoutOrder = 100 + i, Parent = aPage })
			corner(r, 8)
			text(r, a.name, UDim2.new(1, -150, 0, 24), { Position = UDim2.fromOffset(10, 8), TextXAlignment = Enum.TextXAlignment.Left })
			local rm = button(r, "Remove", Color3.fromRGB(200, 60, 70), UDim2.fromOffset(110, 30), function()
				AdminRemote:FireServer("removeAdmin", 0, a.id)
			end)
			rm.Position = UDim2.new(1, -118, 0, 5)
			table.insert(adminRows, r)
		end
	end
	local function buildAdminsTab()
		if aPage or not player:GetAttribute("IsOwner") then return end
		aPage = tab("Admins", 3)
		local add = {}
		row(aPage, "Add an admin by username (works even if they're offline)", {
			{ "Username", box = true, ref = add, w = 230 },
			{ "Add admin", function()
				AdminRemote:FireServer("addAdmin", 0, add.box.Text)
				add.box.Text = ""
			end, color = GREEN, w = 130 },
		})
		row(aPage, "Or pick someone in the list on the left, then:", {
			{ "Make them admin", function()
				if selectedId ~= 0 then AdminRemote:FireServer("addAdmin", 0, selectedId) end
			end, color = GREEN, w = 180 },
		})
		text(aPage, "ADMINS", UDim2.new(1, -10, 0, 24), { LayoutOrder = 99, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 215, 60) })
	end
	buildAdminsTab()
	player:GetAttributeChangedSignal("IsOwner"):Connect(buildAdminsTab)

	-- the player list
	local function refreshPlayers()
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		local entries = { { id = 0, name = "Everyone" } }
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(entries, { id = p.UserId, name = p.DisplayName .. ((p == player) and " (you)" or "") })
		end
		for i, e in ipairs(entries) do
			local b = button(listFrame, e.name, (e.id == selectedId) and ACCENT or Color3.fromRGB(65, 70, 95), UDim2.new(1, 0, 0, 34), function()
				selectedId, selectedName = e.id, e.name
				who.Text = selectedName
				refreshPlayers()
			end)
			b.LayoutOrder = i
		end
		if selectedId ~= 0 and not Players:GetPlayerByUserId(selectedId) then
			selectedId, selectedName = 0, "Everyone"
			who.Text = selectedName
		end
	end
	refreshPlayers()
	Players.PlayerAdded:Connect(refreshPlayers)
	Players.PlayerRemoving:Connect(function() task.defer(refreshPlayers) end)

	AdminRemote.OnClientEvent:Connect(function(kind, data)
		if kind == "result" then
			status.Text = tostring(data)
		elseif kind == "admins" then
			fillAdmins(data or {})
		end
	end)

	showTab("Player")
end

local function checkAdmin()
	local isAdmin = player:GetAttribute("IsAdmin") == true
	if isAdmin then buildPanel() end
	if not built then return end
	-- lost admin: hide the button and the panel
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("TextButton") then
			c.Visible = isAdmin
		elseif c:IsA("Frame") and c ~= banner and not isAdmin then
			c.Visible = false
		end
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(checkAdmin)
checkAdmin()
