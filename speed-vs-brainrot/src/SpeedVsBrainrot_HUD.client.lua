--[[
	SPEED VS BRAINROT  —  HUD  (LocalScript)
	Put this in: StarterPlayer > StarterPlayerScripts  (next to SpeedVsBrainrot_Client)

	What it adds:
	  • Three chunky studded stat tiles on the left: 👟 Speed (red), 💵 Cash
	    (green) and 🏆 Trophies (yellow). The numbers count up and the tile
	    bounces when they go up.
	  • Four big square buttons under them:
	      🌀 Teleport  - spawn, the green speed pad, or the egg row
	      🦇 3x Cash   - your gamepass (shows "ONLY ⏣price!" above it)
	      👥 Invite    - invite friends ("Play with friends!")
	      🐶 Pets      - your pets, what they give, and Fuse 3 → 1 better pet
	  • When you collect cash: a big cash brick with "+545" pops up on the
	    screen, wiggles, then flies into your Cash tile; and a green swirl
	    spins around your character (other players see your swirl too).
	  • When you earn trophies: a gold banner slides down at the top ("🏆 +3").

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
	speed = Color3.fromRGB(235, 70, 80),
	cash = Color3.fromRGB(70, 200, 60),
	trophies = Color3.fromRGB(245, 200, 40),
	teleport = Color3.fromRGB(80, 170, 235),
	pass = Color3.fromRGB(60, 200, 90),
	invite = Color3.fromRGB(250, 205, 50),
	pets = Color3.fromRGB(80, 170, 235),
}

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
	new("UIStroke", { Color = Color3.fromRGB(25, 25, 30), Thickness = 2.5, LineJoinMode = Enum.LineJoinMode.Round, Parent = l })
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
	local tile = new("Frame", {
		BackgroundColor3 = color,
		Size = size,
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(tile, 8)
	stroke(tile, color:Lerp(Color3.new(0, 0, 0), 0.45), 3)
	new("UIGradient", {
		Color = ColorSequence.new(color:Lerp(WHITE, 0.18), color:Lerp(Color3.new(0, 0, 0), 0.12)),
		Rotation = 90,
		Parent = tile,
	})
	-- the studs
	local studs = new("Frame", {
		Name = "Studs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = tile.ZIndex,
		Parent = tile,
	})
	corner(studs, 8)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(14, 14),
		CellPadding = UDim2.fromOffset(6, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = studs,
	})
	local w, h = size.X.Offset, size.Y.Offset
	local count = math.max(1, math.floor((w - 4) / 20)) * math.max(1, math.floor((h - 4) / 20))
	for _ = 1, count do
		local stud = new("Frame", {
			BackgroundColor3 = color:Lerp(WHITE, 0.12),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = studs,
		})
		corner(stud, 7)
		new("UIStroke", { Color = color:Lerp(Color3.new(0, 0, 0), 0.3), Thickness = 1.2, Transparency = 0.45, Parent = stud })
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
	Position = UDim2.fromOffset(14, 70),
	Size = UDim2.fromOffset(240, 600),
	Parent = gui,
})

------------------------------------------------------------------------
-- Stat tiles: 👟 Speed, 💵 Cash, 🏆 Trophies
------------------------------------------------------------------------
local stats = {}
local function statTile(key, icon, y, color)
	local tile, scale = studTile(column, color, UDim2.fromOffset(176, 66), { Position = UDim2.fromOffset(0, y), Name = key .. "Tile" })
	label(tile, icon, UDim2.fromOffset(56, 56), { Position = UDim2.fromOffset(4, 5), ZIndex = 3 })
	local value = label(tile, "0", UDim2.new(1, -66, 0, 40), {
		Position = UDim2.fromOffset(60, 13),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	stats[key] = { Tile = tile, Scale = scale, Value = value, Shown = 0, Target = 0, Prefix = "" }
	return stats[key]
end
statTile("Speed", "👟", 0, COLORS.speed)
statTile("Cash", "💵", 76, COLORS.cash)
statTile("Trophies", "🏆", 152, COLORS.trophies)

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
local BTN = 100
local GAP = 14
local function squareButton(name, icon, text, color, x, y)
	local tile, scale = studTile(column, color, UDim2.fromOffset(BTN, BTN), { Position = UDim2.fromOffset(x, y), Name = name })
	local button = new("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = tile,
	})
	local iconLabel = label(tile, icon, UDim2.fromOffset(62, 62), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), ZIndex = 3 })
	local textLabel = label(tile, text, UDim2.new(1, -8, 0, 26), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), ZIndex = 4 })
	return tile, scale, button, iconLabel, textLabel
end

local rowY = 152 + 66 + 36
local _tpTile, tpScale, tpButton = squareButton("Teleport", "🌀", "Teleport", COLORS.teleport, 0, rowY)
local passTile, passScale, passButton, passIcon, passText = squareButton("CashPass", "🦇", "3x 💵", COLORS.pass, BTN + GAP, rowY)
local _invTile, invScale, invButton = squareButton("Invite", "👥", "Invite", COLORS.invite, 0, rowY + BTN + GAP + 22)
local _petTile, petScale, petButton = squareButton("Pets", "🐶", "Pets", COLORS.pets, BTN + GAP, rowY + BTN + GAP + 22)

-- "Play with friends!" under the invite button
label(column, "Play with friends!", UDim2.fromOffset(BTN + 20, 20), { Position = UDim2.fromOffset(-10, rowY + 2 * BTN + GAP + 24) })

-- the gamepass button: a glowing rainbow border, the price above it
passText.TextColor3 = Color3.fromRGB(200, 255, 170)
local passStroke = passTile:FindFirstChildOfClass("UIStroke")
passStroke.Thickness = 4
passStroke.Color = WHITE
local rainbow = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 230, 90)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 90, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 70)),
	}),
	Parent = passStroke,
})
local priceLabel = label(column, "ONLY " .. ROBUX .. "?!", UDim2.fromOffset(BTN + 10, 22), {
	Position = UDim2.fromOffset(BTN + GAP - 5, rowY - 24),
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
		priceLabel.Text = "OWNED ✅"
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

local function panel(name, size, title, color)
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
	label(head, title, UDim2.new(1, -70, 0, 40), { Position = UDim2.fromOffset(16, 5), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
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

-- 🌀 teleport menu
local tpPanel = panel("TeleportMenu", UDim2.fromOffset(300, 250), "🌀 Teleport", COLORS.teleport)
for i, place in ipairs({ { "spawn", "🏝️ Spawn" }, { "pad", "⚡ Speed Pad" }, { "eggs", "🥚 Pet Eggs" } }) do
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
	label(b, place[2], UDim2.new(1, -16, 1, -12), { Position = UDim2.fromOffset(8, 6), ZIndex = 23 })
	b.Activated:Connect(function()
		TeleportRemote:FireServer(place[1])
		closePanel()
	end)
end

-- 🐶 pets: what you own, what it gives, fuse 3 into a better one
local TIER_NAMES = { "", "Golden ", "Rainbow " }
local TIER_COLORS = { WHITE, Color3.fromRGB(255, 215, 60), Color3.fromRGB(255, 120, 230) }
local TIER_MULT = { 1, 3, 9 }
local petPanel = panel("PetsMenu", UDim2.fromOffset(470, 380), "🐶 Your Pets", COLORS.pets)
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
		label(petList, "No pets yet! Hatch eggs with 🏆 trophies.", UDim2.fromOffset(400, 30), { ZIndex = 23 })
		return
	end
	for i, p in ipairs(list) do
		local card = new("Frame", { LayoutOrder = i, BackgroundColor3 = Color3.fromRGB(58, 64, 86), ZIndex = 23, Parent = petList })
		corner(card, 12)
		stroke(card, if equipped[p.key] then Color3.fromRGB(120, 255, 120) else TIER_COLORS[p.tier], 3)
		label(card, p.info:GetAttribute("Icon") or "🐾", UDim2.fromOffset(52, 52), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), ZIndex = 24 })
		label(card, TIER_NAMES[p.tier] .. p.name, UDim2.new(1, -8, 0, 18), { Position = UDim2.fromOffset(4, 58), TextColor3 = TIER_COLORS[p.tier], ZIndex = 24 })
		label(card, "+" .. fmt(p.bonus) .. "% cash  •  x" .. p.count, UDim2.new(1, -8, 0, 16), { Position = UDim2.fromOffset(4, 78), TextColor3 = Color3.fromRGB(150, 255, 150), ZIndex = 24 })
		if equipped[p.key] then
			label(card, "✅ Equipped", UDim2.new(1, -8, 0, 14), { Position = UDim2.fromOffset(4, 96), ZIndex = 24 })
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
			label(fuse, if can then "Fuse 3 → " .. TIER_NAMES[p.tier + 1] else "Fuse (" .. p.count .. "/3)", UDim2.new(1, -8, 1, -6), { Position = UDim2.fromOffset(4, 3), ZIndex = 25 })
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
-- 💵 COLLECTING CASH
--   on your screen: a cash brick with "+545" pops up, wiggles, and flies
--   into your Cash tile
--   in the world: a green swirl spins up around whoever grabbed it
------------------------------------------------------------------------
local fxLayer = new("Frame", { Name = "CashPops", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = gui })

-- a little 2D cash brick like the icon: green stack, yellow band, bill lines
local function cashBrick(parent, size)
	local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), ZIndex = 31, Parent = parent })
	local body = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.95, 0.7),
		BackgroundColor3 = Color3.fromRGB(70, 200, 75),
		Rotation = -14,
		ZIndex = 31,
		Parent = holder,
	})
	corner(body, 6)
	new("UIStroke", { Color = Color3.fromRGB(20, 80, 30), Thickness = 3, Parent = body })
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(120, 235, 110), Color3.fromRGB(50, 160, 60)), Rotation = 90, Parent = body })
	for k = 1, 3 do
		new("Frame", { Position = UDim2.new(0, 0, k / 4, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(30, 120, 40), BorderSizePixel = 0, ZIndex = 32, Parent = body })
	end
	local band = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0.26, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 190, 50),
		BorderSizePixel = 0,
		ZIndex = 33,
		Parent = body,
	})
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 225, 110), Color3.fromRGB(240, 160, 30)), Rotation = 90, Parent = band })
	return holder
end

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
	local brick = cashBrick(pop, 96)
	brick.Position = UDim2.fromOffset(46, 0)
	local text = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.fromOffset(170, 66),
		Font = FONT,
		Text = "+" .. fmt(amount),
		TextColor3 = Color3.fromRGB(240, 255, 235),
		TextScaled = true,
		ZIndex = 34,
		Parent = pop,
	})
	new("UIStroke", { Color = Color3.fromRGB(30, 110, 40), Thickness = 4, LineJoinMode = Enum.LineJoinMode.Round, Parent = text })
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
-- 🏆 trophy banner: slides down at the top when you earn trophies
------------------------------------------------------------------------
local banner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -120),
	Size = UDim2.new(0.8, 0, 0, 90),
	BackgroundColor3 = Color3.fromRGB(255, 200, 60),
	BackgroundTransparency = 0.25,
	ZIndex = 40,
	Parent = gui,
})
new("UIGradient", {
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	Parent = banner,
})
local bannerText = label(banner, "", UDim2.new(1, 0, 0, 70), { Position = UDim2.fromOffset(0, 10), ZIndex = 41 })
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
	bannerText.Text = "🏆 +" .. fmt(gained)
	tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, 0) }, Enum.EasingStyle.Back)
	task.delay(2.2, function()
		if bannerToken == token then
			tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -120) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
end)
