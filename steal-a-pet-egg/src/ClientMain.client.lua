-- ClientMain (LocalScript) — StarterPlayer.StarterPlayerScripts.ClientMain
-- HUD: cash, income, speed, carry/chase banner, lock timer, notifications
-- and Robux shop.
-- Also hides prompts that aren't meant for this player.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")

--------------------------------------------------------------------------------
-- Prompt filtering (e.g. you never see "Steal" on your own eggs)
--------------------------------------------------------------------------------
local function applyAudience(prompt)
	local ownerOnly = prompt:GetAttribute("OwnerOnly")
	local othersOnly = prompt:GetAttribute("OthersOnly")
	local hidden = (ownerOnly ~= nil and ownerOnly ~= player.UserId) or (othersOnly ~= nil and othersOnly == player.UserId)
	prompt.MaxActivationDistance = if hidden then 0 else (prompt:GetAttribute("Range") or Config.PromptRange)
end

local function watchPrompt(prompt)
	applyAudience(prompt)
	prompt.AttributeChanged:Connect(function()
		applyAudience(prompt)
	end)
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") then
		watchPrompt(descendant)
	end
end
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		watchPrompt(descendant)
	end
end)

--------------------------------------------------------------------------------
-- UI helpers
--------------------------------------------------------------------------------
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or Color3.fromRGB(0, 0, 0)
	s.Transparency = 0.3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	for key, value in pairs(props) do
		l[key] = value
	end
	l.Parent = parent
	return l
end

local gui = Instance.new("ScreenGui")
gui.Name = "EggHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Cash panel
--------------------------------------------------------------------------------
local cashPanel = Instance.new("Frame")
cashPanel.AnchorPoint = Vector2.new(0.5, 0)
cashPanel.Position = UDim2.new(0.5, 0, 0, 6)
cashPanel.Size = UDim2.fromOffset(250, 66)
cashPanel.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
cashPanel.BackgroundTransparency = 0.15
cashPanel.Parent = gui
corner(cashPanel, 14)
stroke(cashPanel, 2, Color3.fromRGB(255, 210, 80))
local cashScale = Instance.new("UIScale")
cashScale.Parent = cashPanel

local cashLabel = label(cashPanel, {
	Size = UDim2.new(1, -16, 0.6, 0),
	Position = UDim2.fromOffset(8, 4),
	TextColor3 = Color3.fromRGB(255, 220, 90),
	Text = "💰 $0",
})
local incomeLabel = label(cashPanel, {
	Size = UDim2.new(1, -16, 0.32, 0),
	Position = UDim2.new(0, 8, 0.62, 0),
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(130, 240, 140),
	Text = "+$0/s",
})

local speedLabel = label(cashPanel, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 4),
	Size = UDim2.new(1, 0, 0, 22),
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255, 225, 120),
	Text = "⚡ Speed 0",
})

local lockLabel = label(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 100),
	Size = UDim2.fromOffset(260, 24),
	TextColor3 = Color3.fromRGB(140, 200, 255),
	Visible = false,
})

local lastCash = 0
local function setCash(value)
	cashLabel.Text = "💰 " .. Util.Money(value)
	if value > lastCash then
		cashScale.Scale = 1.06
		TweenService:Create(cashScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
	end
	lastCash = value
end

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats")
	local cash = leaderstats:WaitForChild("Cash")
	lastCash = cash.Value
	setCash(cash.Value)
	cash.Changed:Connect(setCash)

	local speed = leaderstats:WaitForChild("Speed")
	local function setSpeed(value)
		local training = if player:GetAttribute("OnTreadmill") then "  🏃 training..." else ""
		speedLabel.Text = "⚡ Speed " .. Util.FormatNumber(value) .. training
	end
	setSpeed(speed.Value)
	speed.Changed:Connect(setSpeed)
	player:GetAttributeChangedSignal("OnTreadmill"):Connect(function()
		setSpeed(speed.Value)
	end)
end)

local function refreshIncome()
	local income = player:GetAttribute("IncomePerSec") or 0
	incomeLabel.Text = "+" .. Util.Money(income) .. "/s"
end
refreshIncome()
player:GetAttributeChangedSignal("IncomePerSec"):Connect(refreshIncome)

--------------------------------------------------------------------------------
-- Carry banner
--------------------------------------------------------------------------------
local carryBanner = Instance.new("TextLabel")
carryBanner.AnchorPoint = Vector2.new(0.5, 1)
carryBanner.Position = UDim2.new(0.5, 0, 1, -110)
carryBanner.Size = UDim2.fromOffset(440, 44)
carryBanner.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
carryBanner.BackgroundTransparency = 0.1
carryBanner.Font = Enum.Font.FredokaOne
carryBanner.TextScaled = true
carryBanner.TextColor3 = Color3.new(1, 1, 1)
carryBanner.Visible = false
carryBanner.Parent = gui
corner(carryBanner, 12)
local bannerPadding = Instance.new("UIPadding")
bannerPadding.PaddingLeft = UDim.new(0, 12)
bannerPadding.PaddingRight = UDim.new(0, 12)
bannerPadding.PaddingTop = UDim.new(0, 6)
bannerPadding.PaddingBottom = UDim.new(0, 6)
bannerPadding.Parent = carryBanner

local function refreshCarry()
	local rarityId = player:GetAttribute("CarryingEgg")
	if not rarityId then
		carryBanner.Visible = false
		return
	end
	local rarity = Config.RarityById[rarityId]
	local stolen = player:GetAttribute("CarryingStolen")
	local chasedBy = player:GetAttribute("ChasedBy")
	if chasedBy then
		carryBanner.Text = "🚨 The " .. chasedBy .. " is chasing you! RUN!"
		carryBanner.BackgroundColor3 = Color3.fromRGB(150, 25, 25)
	elseif stolen then
		carryBanner.Text = "🏃 STOLEN " .. rarityId .. " Egg — RUN to your nest!"
		carryBanner.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
	else
		carryBanner.Text = "🥚 " .. rarityId .. " Egg — carry it to your nest!"
		carryBanner.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	end
	carryBanner.TextColor3 = if rarity then rarity.Color:Lerp(Color3.new(1, 1, 1), 0.4) else Color3.new(1, 1, 1)
	carryBanner.Visible = true
end
player:GetAttributeChangedSignal("CarryingEgg"):Connect(refreshCarry)
player:GetAttributeChangedSignal("CarryingStolen"):Connect(refreshCarry)
player:GetAttributeChangedSignal("ChasedBy"):Connect(refreshCarry)
refreshCarry()

--------------------------------------------------------------------------------
-- Lock timer
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		local lockedUntil = player:GetAttribute("LockedUntil") or 0
		local remaining = lockedUntil - workspace:GetServerTimeNow()
		if remaining > 0 then
			lockLabel.Text = "🔒 Nest locked: " .. Util.FormatTime(remaining)
			lockLabel.Visible = true
		else
			lockLabel.Visible = false
		end
		task.wait(0.25)
	end
end)

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------
local toastList = Instance.new("Frame")
toastList.AnchorPoint = Vector2.new(0.5, 0)
toastList.Position = UDim2.new(0.5, 0, 0, 156)
toastList.Size = UDim2.fromOffset(480, 200)
toastList.BackgroundTransparency = 1
toastList.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = toastList

local toastCount = 0
local function toast(text, color)
	toastCount += 1
	local item = Instance.new("TextLabel")
	item.LayoutOrder = toastCount
	item.Size = UDim2.new(1, 0, 0, 34)
	item.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
	item.BackgroundTransparency = 0.15
	item.Font = Enum.Font.GothamBold
	item.TextSize = 17
	item.TextWrapped = true
	item.TextColor3 = color or Color3.new(1, 1, 1)
	item.TextStrokeTransparency = 0.6
	item.Text = text
	item.Parent = toastList
	corner(item, 10)

	-- keep at most 4 on screen
	local items = {}
	for _, child in ipairs(toastList:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #items - 4 do
		items[i]:Destroy()
	end

	task.delay(4, function()
		if item.Parent then
			local fade = TweenInfo.new(0.4)
			TweenService:Create(item, fade, { BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.4)
			item:Destroy()
		end
	end)
end
Notify.OnClientEvent:Connect(toast)

--------------------------------------------------------------------------------
-- Shop: game passes, server luck and boosts
--------------------------------------------------------------------------------
local TABS = {
	{ Id = "Passes", Title = "⭐ Game Passes", Color = Color3.fromRGB(255, 190, 50) },
	{ Id = "Luck", Title = "🍀 Server Luck", Color = Color3.fromRGB(90, 210, 110) },
	{ Id = "Boosts", Title = "⚡ Boosts", Color = Color3.fromRGB(90, 160, 255) },
}

-- Big "Shop" button on the left, like Steal an Egg
local shopButton = Instance.new("TextButton")
shopButton.Name = "ShopButton"
shopButton.AnchorPoint = Vector2.new(0, 0.5)
shopButton.Position = UDim2.new(0, 14, 0.45, 0)
shopButton.Size = UDim2.fromOffset(150, 58)
shopButton.BackgroundColor3 = Color3.fromRGB(90, 220, 80)
shopButton.Font = Enum.Font.FredokaOne
shopButton.TextScaled = true
shopButton.Text = "🛒 Shop"
shopButton.TextColor3 = Color3.new(1, 1, 1)
shopButton.TextStrokeTransparency = 0.2
shopButton.Parent = gui
corner(shopButton, 12)
stroke(shopButton, 3, Color3.fromRGB(30, 90, 30))
local shopPad = Instance.new("UIPadding")
shopPad.PaddingTop = UDim.new(0, 8)
shopPad.PaddingBottom = UDim.new(0, 8)
shopPad.Parent = shopButton

-- Panel
local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.fromOffset(760, 470)
panel.BackgroundColor3 = Color3.fromRGB(34, 30, 52)
panel.Visible = false
panel.Parent = gui
corner(panel, 20)
stroke(panel, 4, Color3.fromRGB(255, 210, 90))
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(760, 470)
sizeLimit.Parent = panel
local panelGradient = Instance.new("UIGradient")
panelGradient.Color = ColorSequence.new(Color3.fromRGB(60, 48, 96), Color3.fromRGB(26, 22, 40))
panelGradient.Rotation = 90
panelGradient.Parent = panel

local header = label(panel, {
	Position = UDim2.fromOffset(24, 10),
	Size = UDim2.new(1, -110, 0, 48),
	Text = "🛒 SHOP",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 220, 90),
})
local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -14, 0, 12)
closeButton.Size = UDim2.fromOffset(46, 46)
closeButton.BackgroundColor3 = Color3.fromRGB(235, 70, 80)
closeButton.Font = Enum.Font.FredokaOne
closeButton.TextScaled = true
closeButton.Text = "X"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Parent = panel
corner(closeButton, 12)
stroke(closeButton, 3, Color3.fromRGB(120, 20, 30))

local tabBar = Instance.new("Frame")
tabBar.BackgroundTransparency = 1
tabBar.Position = UDim2.fromOffset(20, 66)
tabBar.Size = UDim2.new(1, -40, 0, 44)
tabBar.Parent = panel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 10)
tabLayout.Parent = tabBar

local grid = Instance.new("ScrollingFrame")
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.Position = UDim2.fromOffset(20, 120)
grid.Size = UDim2.new(1, -40, 1, -135)
grid.ScrollBarThickness = 6
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.CanvasSize = UDim2.new()
grid.Parent = panel
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(226, 316)
gridLayout.CellPadding = UDim2.fromOffset(12, 12)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

local function priceText(item, id)
	if id == 0 then
		return "R$ " .. item.Price
	end
	local infoType = if item.Pass then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
	if ok and info and info.PriceInRobux then
		return "R$ " .. info.PriceInRobux
	end
	return "R$ " .. item.Price
end

local cards = {}
local function buildCard(item, order)
	local id = Config.Products[item.Key] or 0
	local card = Instance.new("Frame")
	card.LayoutOrder = order
	card.BackgroundColor3 = item.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	card.Parent = grid
	corner(card, 16)
	stroke(card, 3, item.Color)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(item.Color:Lerp(Color3.new(0, 0, 0), 0.3), item.Color:Lerp(Color3.new(0, 0, 0), 0.7))
	grad.Rotation = 90
	grad.Parent = card

	local icon = label(card, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 84), Text = item.Icon, TextStrokeTransparency = 1 })
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon
	label(card, { Position = UDim2.fromOffset(10, 100), Size = UDim2.new(1, -20, 0, 36), Text = item.Title, TextColor3 = Color3.new(1, 1, 1) })
	local desc = label(card, { Position = UDim2.fromOffset(12, 140), Size = UDim2.new(1, -24, 0, 80), Text = item.Desc, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(230, 230, 240), TextStrokeTransparency = 1 })
	desc.TextScaled = false
	desc.TextSize = 15
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top

	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -14)
	buy.Size = UDim2.new(1, -30, 0, 50)
	buy.BackgroundColor3 = Color3.fromRGB(80, 210, 90)
	buy.Font = Enum.Font.FredokaOne
	buy.TextScaled = true
	buy.Text = "R$ " .. item.Price
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.TextStrokeTransparency = 0.3
	buy.Parent = card
	corner(buy, 12)
	stroke(buy, 3, Color3.fromRGB(30, 100, 30))
	local buyPad = Instance.new("UIPadding")
	buyPad.PaddingTop = UDim.new(0, 8)
	buyPad.PaddingBottom = UDim.new(0, 8)
	buyPad.Parent = buy

	task.spawn(function()
		buy.Text = priceText(item, id)
	end)

	-- the Speed boost shows exactly how much Speed you'd get right now
	if item.ScalesWithSpeed then
		task.spawn(function()
			local speed = player:WaitForChild("leaderstats"):WaitForChild("Speed")
			local function refresh()
				desc.Text = "Instantly gain +" .. Util.FormatNumber(Config.SpeedBoostFor(speed.Value)) .. " Speed (25% of your Speed, at least 25)."
			end
			refresh()
			speed.Changed:Connect(refresh)
		end)
	end

	local function refreshOwned()
		if item.Pass and player:GetAttribute("Pass_" .. item.Key) then
			buy.Text = "✅ OWNED"
			buy.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
			buy.AutoButtonColor = false
		end
	end
	if item.Pass then
		player:GetAttributeChangedSignal("Pass_" .. item.Key):Connect(refreshOwned)
		refreshOwned()
	end

	buy.Activated:Connect(function()
		if item.Pass and player:GetAttribute("Pass_" .. item.Key) then
			return
		end
		if id == 0 then
			toast("🛠️ " .. item.Title .. " isn't set up yet: add its ID in Config.Products." .. item.Key, Color3.fromRGB(255, 200, 120))
			return
		end
		if item.Pass then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
	buy.MouseEnter:Connect(function()
		TweenService:Create(iconScale, TweenInfo.new(0.15), { Scale = 1.15 }):Play()
	end)
	buy.MouseLeave:Connect(function()
		TweenService:Create(iconScale, TweenInfo.new(0.15), { Scale = 1 }):Play()
	end)
	cards[item] = card
end

for i, item in ipairs(Config.Shop) do
	buildCard(item, i)
end

local tabButtons = {}
local function selectTab(tabId)
	for item, card in pairs(cards) do
		card.Visible = item.Tab == tabId
	end
	for id, button in pairs(tabButtons) do
		local selected = id == tabId
		button.BackgroundTransparency = if selected then 0 else 0.55
		button.Size = UDim2.fromOffset(220, if selected then 44 else 38)
	end
	grid.CanvasPosition = Vector2.zero
end

for _, tab in ipairs(TABS) do
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(220, 44)
	button.BackgroundColor3 = tab.Color
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.Text = tab.Title
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.3
	button.Parent = tabBar
	corner(button, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = button
	tabButtons[tab.Id] = button
	button.Activated:Connect(function()
		selectTab(tab.Id)
	end)
end
selectTab("Passes")

local function setShopOpen(open)
	if open then
		panel.Visible = true
		panelScale.Scale = 0.7
		TweenService:Create(panelScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else
		panel.Visible = false
	end
end
shopButton.Activated:Connect(function()
	setShopOpen(not panel.Visible)
end)
closeButton.Activated:Connect(function()
	setShopOpen(false)
end)

-- keep the panel usable on small screens
local function fitPanel()
	local camera = workspace.CurrentCamera
	if camera then
		local vp = camera.ViewportSize
		local scale = math.min(1, (vp.X - 40) / 760, (vp.Y - 60) / 470)
		sizeLimit.MaxSize = Vector2.new(760 * scale, 470 * scale)
		panel.Size = UDim2.fromOffset(760 * scale, 470 * scale)
		gridLayout.CellSize = UDim2.fromOffset(226 * scale, 316 * scale)
	end
end
fitPanel()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)
end

--------------------------------------------------------------------------------
-- Server luck timer under the cash panel
--------------------------------------------------------------------------------
local luckLabel = label(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 124),
	Size = UDim2.fromOffset(300, 26),
	TextColor3 = Color3.fromRGB(130, 255, 150),
	Visible = false,
})
task.spawn(function()
	while true do
		local mult = workspace:GetAttribute("ServerLuck") or 1
		local untilTime = workspace:GetAttribute("ServerLuckUntil") or 0
		local remaining = untilTime - workspace:GetServerTimeNow()
		if mult > 1 and remaining > 0 then
			luckLabel.Text = "🍀 " .. mult .. "x Server Luck  " .. Util.FormatTime(remaining)
			luckLabel.Visible = true
		else
			luckLabel.Visible = false
		end
		task.wait(0.5)
	end
end)

--------------------------------------------------------------------------------
-- Biome moods: blend the sky, haze and colors as you travel, and show a banner
-- when you enter a new biome.
--------------------------------------------------------------------------------
local Lighting = game:GetService("Lighting")

local zoneBanner = Instance.new("Frame")
zoneBanner.AnchorPoint = Vector2.new(0.5, 0.5)
zoneBanner.Position = UDim2.fromScale(0.5, 0.3)
zoneBanner.Size = UDim2.fromOffset(520, 90)
zoneBanner.BackgroundTransparency = 1
zoneBanner.Visible = false
zoneBanner.Parent = gui
local zoneTitle = label(zoneBanner, {
	Size = UDim2.fromScale(1, 0.62),
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.2,
	Text = "",
})
local zoneSub = label(zoneBanner, {
	Position = UDim2.fromScale(0, 0.62),
	Size = UDim2.fromScale(1, 0.38),
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255, 225, 150),
	Text = "",
})

local bannerToken = 0
local function showZone(title, sub, color)
	bannerToken += 1
	local token = bannerToken
	zoneTitle.Text = title
	zoneTitle.TextColor3 = color
	zoneSub.Text = sub
	zoneTitle.TextTransparency = 1
	zoneSub.TextTransparency = 1
	zoneBanner.Visible = true
	local fadeIn = TweenInfo.new(0.4)
	TweenService:Create(zoneTitle, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(zoneSub, fadeIn, { TextTransparency = 0 }):Play()
	task.delay(2.8, function()
		if token ~= bannerToken then
			return
		end
		local fadeOut = TweenInfo.new(0.6)
		TweenService:Create(zoneTitle, fadeOut, { TextTransparency = 1 }):Play()
		TweenService:Create(zoneSub, fadeOut, { TextTransparency = 1 }):Play()
	end)
end

local function applyMood(mood)
	local atmosphere = Lighting:FindFirstChild("MoodAtmosphere")
	local cc = Lighting:FindFirstChild("MoodCC")
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	if atmosphere then
		TweenService:Create(atmosphere, info, { Color = mood.Color, Decay = mood.Decay, Density = mood.Density, Haze = mood.Haze, Glare = mood.Glare or 0.2 }):Play()
	end
	if cc then
		TweenService:Create(cc, info, { TintColor = mood.Tint, Brightness = mood.Brightness, Saturation = mood.Saturation }):Play()
	end
	local clouds = workspace.Terrain:FindFirstChild("MoodClouds")
	if clouds and mood.CloudColor then
		TweenService:Create(clouds, info, { Color = mood.CloudColor, Cover = mood.CloudCover or 0.6 }):Play()
	end
end

task.spawn(function()
	local biomesFolder = workspace:WaitForChild("Map"):WaitForChild("Biomes")
	local current = nil
	while true do
		task.wait(0.5)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local zone = "Town"
			for _, biome in ipairs(biomesFolder:GetChildren()) do
				local minZ, maxZ = biome:GetAttribute("MinZ"), biome:GetAttribute("MaxZ")
				if minZ and root.Position.Z >= minZ and root.Position.Z < maxZ then
					zone = biome:GetAttribute("BiomeIndex")
				end
			end
			if zone ~= current then
				local first = current == nil
				current = zone
				if zone == "Town" then
					applyMood(Config.TownMood)
					if not first then
						showZone("🏠 Town", "You're safe here. Get your egg home!", Color3.fromRGB(255, 240, 200))
					end
				else
					local def = Config.Biomes[zone]
					applyMood(def.Mood)
					showZone(def.Name, def.GuardianName .. " guards these eggs  •  Speed " .. Util.FormatNumber(Config.RecommendedSpeed(def)) .. "+ needed", def.GuardianColor:Lerp(Color3.new(1, 1, 1), 0.35))
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Pets roam around their owner's pen. Done on each client so it's smooth and
-- costs the server nothing: walk to a random spot, look around, repeat.
--------------------------------------------------------------------------------
task.spawn(function()
	local RunService = game:GetService("RunService")
	local petsFolder = workspace:WaitForChild("Pets")
	local roamers = {}

	local function lerpAngle(a, b, t)
		local d = (b - a + math.pi) % (2 * math.pi) - math.pi
		return a + d * t
	end

	local function track(model)
		if not model:IsA("Model") then
			return
		end
		local body = model.PrimaryPart or model:WaitForChild("Body", 5)
		local pen = model:GetAttribute("PenCFrame")
		local half = model:GetAttribute("PenHalfSize")
		if not body or typeof(pen) ~= "CFrame" or typeof(half) ~= "Vector2" then
			return
		end
		local rng = Random.new(model:GetAttribute("RoamSeed") or math.floor(os.clock() * 1000))
		local radius = math.max(body.Size.X, body.Size.Z) * 0.65
		local start = pen:PointToObjectSpace(body.Position)
		local float = (model:GetAttribute("Hover") or 0) > 0
		roamers[model] = {
			Body = body,
			Pen = pen,
			Half = Vector2.new(math.max(0.5, half.X - radius), math.max(0.5, half.Y - radius)),
			Y = body.Position.Y,
			Pos = Vector2.new(start.X, start.Z),
			Yaw = 0,
			LookYaw = 0,
			Target = nil,
			Wait = rng:NextNumber(0.5, 4),
			Rng = rng,
			Float = float,
			Speed = if float then rng:NextNumber(2.5, 3.5) else rng:NextNumber(4, 6.5),
			Hop = body.Size.Y * 0.09,
			Phase = rng:NextNumber(0, 10),
		}
	end

	petsFolder.ChildAdded:Connect(function(model)
		task.defer(track, model)
	end)
	petsFolder.ChildRemoved:Connect(function(model)
		roamers[model] = nil
	end)
	for _, model in ipairs(petsFolder:GetChildren()) do
		task.spawn(track, model)
	end

	RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, 0.1)
		local now = os.clock()
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position
		for model, r in pairs(roamers) do
			if not model.Parent or not r.Body.Parent then
				roamers[model] = nil
				continue
			end
			-- don't bother animating pets far away from you
			if camPos and (r.Body.Position - camPos).Magnitude > 450 then
				continue
			end
			local moving = false
			if r.Target then
				local delta = r.Target - r.Pos
				local dist = delta.Magnitude
				if dist < 0.25 then
					r.Target = nil
					r.Wait = r.Rng:NextNumber(1.5, 5)
					r.LookYaw = r.Yaw
				else
					local dir = delta / dist
					-- ease in/out at the ends of a walk
					local speed = r.Speed * math.clamp(dist / 2, 0.35, 1)
					r.Pos += dir * math.min(dist, speed * dt)
					r.Yaw = lerpAngle(r.Yaw, math.atan2(-dir.X, -dir.Y), math.min(1, dt * 7))
					moving = true
				end
			else
				r.Wait -= dt
				-- idle: now and then turn to look somewhere else
				if r.Rng:NextNumber() < dt * 0.4 then
					r.LookYaw = r.Yaw + r.Rng:NextNumber(-1.2, 1.2)
				end
				r.Yaw = lerpAngle(r.Yaw, r.LookYaw, math.min(1, dt * 3))
				if r.Wait <= 0 then
					-- mostly short strolls, sometimes a trip across the pen
					local target
					if r.Rng:NextNumber() < 0.65 then
						local a = r.Rng:NextNumber(0, math.pi * 2)
						local d = r.Rng:NextNumber(3, 10)
						target = r.Pos + Vector2.new(math.cos(a), math.sin(a)) * d
					else
						target = Vector2.new(r.Rng:NextNumber(-1, 1) * r.Half.X, r.Rng:NextNumber(-1, 1) * r.Half.Y)
					end
					r.Target = Vector2.new(math.clamp(target.X, -r.Half.X, r.Half.X), math.clamp(target.Y, -r.Half.Y, r.Half.Y))
				end
			end

			local t = now + r.Phase
			local bob, roll, pitch = 0, 0, 0
			if r.Float then
				bob = math.sin(t * 2) * 0.5
				roll = math.sin(t * 1.3) * 0.06
				pitch = if moving then -0.12 else math.sin(t * 1.7) * 0.04
			elseif moving then
				local w = t * (6 + r.Speed)
				bob = math.abs(math.sin(w)) * r.Hop -- little hops
				roll = math.sin(w) * 0.12 -- waddle
				pitch = -0.06
			else
				bob = (math.sin(t * 2.4) + 1) * 0.06 -- breathing
			end
			local world = r.Pen:PointToWorldSpace(Vector3.new(r.Pos.X, 0, r.Pos.Y))
			r.Body.CFrame = CFrame.new(world.X, r.Y + bob, world.Z) * r.Pen.Rotation * CFrame.Angles(0, r.Yaw, 0) * CFrame.Angles(pitch, 0, roll)
		end
	end)
end)

--------------------------------------------------------------------------------
-- Treadmill belts: scroll the stripes so the belts look like they're moving
--------------------------------------------------------------------------------
local RunService = game:GetService("RunService")
task.spawn(function()
	local plotsFolder = workspace:WaitForChild("Map"):WaitForChild("Plots")
	local belts = {}
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		local tread = plot:WaitForChild("Treadmill", 10)
		local stripes = plot:WaitForChild("TreadmillStripes", 10)
		if tread and stripes then
			local list = {}
			for _, stripe in ipairs(stripes:GetChildren()) do
				table.insert(list, { Part = stripe, Offset = stripe:GetAttribute("Offset") or 0, Y = stripe.Position.Y })
			end
			table.insert(belts, { Tread = tread, Length = stripes:GetAttribute("Length") or tread.Size.Z, Stripes = list })
		end
	end
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		for _, belt in ipairs(belts) do
			local cf = belt.Tread.CFrame
			local back = -cf.LookVector
			for _, s in ipairs(belt.Stripes) do
				local frac = (s.Offset + t * Config.TreadmillBeltSpeed / belt.Length) % 1
				local pos = cf.Position + back * ((frac - 0.5) * belt.Length)
				s.Part.CFrame = CFrame.lookAt(Vector3.new(pos.X, s.Y, pos.Z), Vector3.new(pos.X, s.Y, pos.Z) + cf.LookVector)
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- Wild eggs slowly spin and bob in their nests
--------------------------------------------------------------------------------
task.spawn(function()
	local eggsFolder = workspace:WaitForChild("Eggs")
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		for i, egg in ipairs(eggsFolder:GetChildren()) do
			local home = egg:GetAttribute("WildHome")
			if home and egg:IsA("BasePart") and egg.Anchored then
				local phase = t * 1.6 + i
				egg.CFrame = home * CFrame.new(0, math.sin(phase) * 0.25 + 0.25, 0) * CFrame.Angles(0, t * 0.8 + i, math.sin(phase * 0.5) * 0.08)
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- Carry pose: anyone carrying an egg holds it up over their head with both
-- arms raised (overrides the arm swing of the run animation). Runs for every
-- player so you see other carriers doing it too.
--------------------------------------------------------------------------------
local function shoulders(char)
	local upper = char:FindFirstChild("RightUpperArm")
	if upper then -- R15
		local r = upper:FindFirstChild("RightShoulder")
		local l = char:FindFirstChild("LeftUpperArm") and char.LeftUpperArm:FindFirstChild("LeftShoulder")
		return r, l, "R15"
	end
	local torso = char:FindFirstChild("Torso")
	if torso then -- R6
		return torso:FindFirstChild("Right Shoulder"), torso:FindFirstChild("Left Shoulder"), "R6"
	end
	return nil
end

local carryTime = 0
RunService.Stepped:Connect(function(_, dt)
	carryTime += dt
	for _, other in ipairs(Players:GetPlayers()) do
		local char = other.Character
		if char and other:GetAttribute("CarryingEgg") then
			local right, left, rig = shoulders(char)
			local wobble = math.sin(carryTime * 10) * 0.06 -- little bounce while running
			if rig == "R15" then
				if right then
					right.Transform = CFrame.Angles(math.rad(165) + wobble, 0, math.rad(-12))
				end
				if left then
					left.Transform = CFrame.Angles(math.rad(165) - wobble, 0, math.rad(12))
				end
			elseif rig == "R6" then
				if right then
					right.Transform = CFrame.Angles(0, 0, math.rad(165) + wobble)
				end
				if left then
					left.Transform = CFrame.Angles(0, 0, math.rad(-165) - wobble)
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Treadmill training: step on your own treadmill and you lock into the middle
-- of the belt, auto-running, until you press STOP.
--------------------------------------------------------------------------------
local TreadmillRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Treadmill")
local DEFAULT_RUN = { R15 = "rbxassetid://913376220", R6 = "rbxassetid://180426354" }

local stopButton = Instance.new("TextButton")
stopButton.Name = "StopTraining"
stopButton.AnchorPoint = Vector2.new(0.5, 1)
stopButton.Position = UDim2.new(0.5, 0, 1, -170)
stopButton.Size = UDim2.fromOffset(220, 64)
stopButton.BackgroundColor3 = Color3.fromRGB(235, 70, 80)
stopButton.Font = Enum.Font.FredokaOne
stopButton.TextScaled = true
stopButton.Text = "⏹ STOP"
stopButton.TextColor3 = Color3.new(1, 1, 1)
stopButton.TextStrokeTransparency = 0.2
stopButton.Visible = false
stopButton.Parent = gui
corner(stopButton, 16)
stroke(stopButton, 3, Color3.fromRGB(120, 20, 30))
local stopPad = Instance.new("UIPadding")
stopPad.PaddingTop = UDim.new(0, 10)
stopPad.PaddingBottom = UDim.new(0, 10)
stopPad.Parent = stopButton

local trainingLabel = label(gui, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -240),
	Size = UDim2.fromOffset(360, 34),
	Text = "🏃 Training... +Speed",
	TextColor3 = Color3.fromRGB(255, 225, 120),
	Visible = false,
})

local training = nil -- { Track, Tread, Root }
local mustStepOff = false

local function myTreadmill()
	local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot:FindFirstChild("Treadmill")
		end
	end
	return nil
end

local function onBelt(tread, position)
	local localPos = tread.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= tread.Size.X / 2 + 0.3 and math.abs(localPos.Z) <= tread.Size.Z / 2 + 0.3 and localPos.Y > -1 and localPos.Y < 7
end

local function stopTraining()
	if not training then
		return
	end
	local t = training
	training = nil
	mustStepOff = true
	if t.Track then
		t.Track:Stop(0.2)
	end
	if t.Root and t.Root.Parent then
		-- hop off the side of the treadmill
		local cf = t.Tread.CFrame
		t.Root.CFrame = CFrame.lookAt(cf.Position + cf.RightVector * (t.Tread.Size.X / 2 + 3) + Vector3.new(0, 3, 0), cf.Position + cf.RightVector * (t.Tread.Size.X / 2 + 3) + Vector3.new(0, 3, 0) + cf.LookVector)
	end
	stopButton.Visible = false
	trainingLabel.Visible = false
	TreadmillRemote:FireServer("stop")
end

local function startTraining(tread, root, hum)
	local animator = hum:FindFirstChildOfClass("Animator")
	local track
	if animator then
		local anim = Instance.new("Animation")
		local animate = hum.Parent:FindFirstChild("Animate")
		local runValue = animate and animate:FindFirstChild("run")
		local runAnim = runValue and runValue:FindFirstChildOfClass("Animation")
		anim.AnimationId = if runAnim then runAnim.AnimationId elseif hum.RigType == Enum.HumanoidRigType.R15 then DEFAULT_RUN.R15 else DEFAULT_RUN.R6
		local ok, loaded = pcall(animator.LoadAnimation, animator, anim)
		if ok then
			track = loaded
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			track:Play(0.2)
			track:AdjustSpeed(1.3)
		end
	end
	-- lock into the middle of the belt, facing the console
	local cf = tread.CFrame
	local height = hum.HipHeight + root.Size.Y / 2 + tread.Size.Y / 2
	local pos = cf.Position + Vector3.new(0, height, 0)
	local pin = CFrame.lookAt(pos, pos + cf.LookVector)
	root.CFrame = pin
	-- pinned every frame (not anchored, so your position still syncs to the server)
	training = { Track = track, Tread = tread, Root = root, Pin = pin }
	stopButton.Visible = true
	trainingLabel.Visible = true
	TreadmillRemote:FireServer("start")
end

stopButton.Activated:Connect(stopTraining)

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if training then
		if not root or not hum or hum.Health <= 0 or player:GetAttribute("CarryingEgg") then
			stopTraining()
		else
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = training.Pin
			-- keep reminding the server we're training (recovers from any hiccup)
			local t = os.clock()
			if t - (training.LastPing or 0) > 2 then
				training.LastPing = t
				TreadmillRemote:FireServer("start")
			end
			local nextIn = player:GetAttribute("TrainNext")
			local gain = player:GetAttribute("TrainGain")
			if nextIn and gain then
				trainingLabel.Text = "🏃 Training: +" .. Util.FormatNumber(gain) .. " Speed in " .. math.ceil(nextIn) .. "s"
			else
				trainingLabel.Text = "🏃 Training..."
			end
		end
		return
	end
	if not root or not hum or hum.Health <= 0 then
		return
	end
	local tread = myTreadmill()
	if not tread then
		return
	end
	local here = onBelt(tread, root.Position)
	if mustStepOff then
		if not here then
			mustStepOff = false
		end
	elseif here and not player:GetAttribute("CarryingEgg") then
		startTraining(tread, root, hum)
	end
end)

player.CharacterAdded:Connect(function()
	training = nil
	mustStepOff = false
	stopButton.Visible = false
	trainingLabel.Visible = false
end)

--------------------------------------------------------------------------------
-- Admin panel (testing tools). Only shows for admins / in Studio; the server
-- checks every command again.
--------------------------------------------------------------------------------
local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin")

local adminButton = shopButton:Clone()
adminButton.Name = "AdminButton"
adminButton.Position = UDim2.new(0, 14, 0.45, 128)
adminButton.Size = UDim2.fromOffset(150, 46)
adminButton.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
adminButton.Text = "🛠 Admin"
adminButton.Visible = false
adminButton.Parent = gui

local adminPanel = Instance.new("ScrollingFrame")
adminPanel.Name = "AdminPanel"
adminPanel.AnchorPoint = Vector2.new(0, 0.5)
adminPanel.Position = UDim2.new(0, 176, 0.5, 0)
adminPanel.Size = UDim2.fromOffset(330, 430)
adminPanel.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
adminPanel.BackgroundTransparency = 0.05
adminPanel.BorderSizePixel = 0
adminPanel.ScrollBarThickness = 6
adminPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
adminPanel.CanvasSize = UDim2.new()
adminPanel.Visible = false
adminPanel.Parent = gui
corner(adminPanel, 14)
stroke(adminPanel, 3, Color3.fromRGB(140, 140, 170))
local adminLayout = Instance.new("UIListLayout")
adminLayout.Padding = UDim.new(0, 6)
adminLayout.SortOrder = Enum.SortOrder.LayoutOrder
adminLayout.Parent = adminPanel
local adminPad = Instance.new("UIPadding")
adminPad.PaddingTop = UDim.new(0, 10)
adminPad.PaddingLeft = UDim.new(0, 10)
adminPad.PaddingRight = UDim.new(0, 16)
adminPad.PaddingBottom = UDim.new(0, 10)
adminPad.Parent = adminPanel

local adminOrder = 0
local function adminHeader(text)
	adminOrder += 1
	local h = label(adminPanel, { LayoutOrder = adminOrder, Size = UDim2.new(1, 0, 0, 24), Text = text, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 220, 110) })
	return h
end

local function adminRow(buttons)
	adminOrder += 1
	local row = Instance.new("Frame")
	row.LayoutOrder = adminOrder
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 34)
	row.Parent = adminPanel
	local rowLayout = Instance.new("UIGridLayout")
	rowLayout.CellPadding = UDim2.fromOffset(5, 5)
	rowLayout.CellSize = UDim2.new(1 / #buttons, -5, 0, 34)
	rowLayout.Parent = row
	for _, info in ipairs(buttons) do
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = info[3] or Color3.fromRGB(70, 110, 200)
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.Text = info[1]
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = row
		corner(b, 8)
		local p = Instance.new("UIPadding")
		p.PaddingTop = UDim.new(0, 6)
		p.PaddingBottom = UDim.new(0, 6)
		p.PaddingLeft = UDim.new(0, 4)
		p.PaddingRight = UDim.new(0, 4)
		p.Parent = b
		b.Activated:Connect(function()
			AdminRemote:FireServer(info[2])
		end)
	end
end

local GREEN_BTN = Color3.fromRGB(70, 170, 90)
local GOLD_BTN = Color3.fromRGB(200, 150, 40)
local RED_BTN = Color3.fromRGB(200, 60, 70)
adminHeader("💰 Cash")
adminRow({ { "+$1K", "cash 1000", GREEN_BTN }, { "+$1M", "cash 1000000", GREEN_BTN }, { "+$1B", "cash 1000000000", GREEN_BTN }, { "+$1T", "cash 1000000000000", GREEN_BTN } })
adminHeader("⚡ Speed")
adminRow({ { "+1K", "speed 1000", GOLD_BTN }, { "+100K", "speed 100000", GOLD_BTN }, { "+1M", "speed 1000000", GOLD_BTN }, { "Reset", "setspeed " .. Config.StartingSpeed, GOLD_BTN } })
adminHeader("🥚 Get an egg (in your hands)")
local eggButtons = {}
for i, r in ipairs(Config.Rarities) do
	table.insert(eggButtons, { r.Id, "egg " .. r.Id, r.Color:Lerp(Color3.new(0, 0, 0), 0.35) })
	if #eggButtons == 4 or i == #Config.Rarities then
		adminRow(eggButtons)
		eggButtons = {}
	end
end
adminHeader("🌈 Mutated Epic egg (in your hands)")
local mutButtons = {}
for i, m in ipairs(Config.Mutations) do
	table.insert(mutButtons, { m.Id, "egg epic " .. m.Id, m.Color:Lerp(Color3.new(0, 0, 0), 0.35) })
	if #mutButtons == 4 or i == #Config.Mutations then
		adminRow(mutButtons)
		mutButtons = {}
	end
end
adminHeader("🐾 Add a pet to your base")
local petButtons = {}
for i, r in ipairs(Config.Rarities) do
	table.insert(petButtons, { r.Id, "pet " .. r.Id, r.Color:Lerp(Color3.new(0, 0, 0), 0.35) })
	if #petButtons == 4 or i == #Config.Rarities then
		adminRow(petButtons)
		petButtons = {}
	end
end
adminHeader("🧪 Base & world")
adminRow({ { "Hatch All", "hatch" }, { "Refill Eggs", "refill" } })
adminRow({ { "Grow +1 Stage", "grow", GREEN_BTN }, { "Grow to Adult", "grow adult", GREEN_BTN } })
adminRow({ { "Max Treadmill", "treadmill 7", GOLD_BTN }, { "Basic Treadmill", "treadmill 1", GOLD_BTN } })
adminRow({ { "2x Luck", "luck 2", GREEN_BTN }, { "5x Luck", "luck 5", GREEN_BTN }, { "10x Luck", "luck 10", GREEN_BTN }, { "Egg Rain", "rain" } })
adminHeader("🚀 Teleport")
adminRow({ { "Town", "tp town" }, { "Forest", "tp forest" }, { "Desert", "tp desert" } })
adminRow({ { "Snow", "tp snow" }, { "Volcano", "tp volcano" }, { "Void", "tp void" } })
adminHeader("🎁 Daily reward")
adminRow({ { "Next Day", "daily", GOLD_BTN }, { "Back to Day 1", "daily reset", GOLD_BTN } })
adminHeader("⚠️ Danger")
adminRow({ { "Reset My Progress", "reset", RED_BTN } })
adminOrder += 1
local chatHelp = label(adminPanel, { LayoutOrder = adminOrder, Size = UDim2.new(1, 0, 0, 60), Font = Enum.Font.Gotham, TextStrokeTransparency = 1, TextColor3 = Color3.fromRGB(200, 200, 215), Text = "Chat commands: !cash 500 · !speed 50 · !egg mythic · !pet galaxy dragon · !shiny divine · !luck 10 · !tp void · !daily · !help" })
chatHelp.TextScaled = false
chatHelp.TextSize = 13
chatHelp.TextWrapped = true

adminButton.Activated:Connect(function()
	adminPanel.Visible = not adminPanel.Visible
end)
local function refreshAdmin()
	adminButton.Visible = player:GetAttribute("IsAdmin") == true
	if not adminButton.Visible then
		adminPanel.Visible = false
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(refreshAdmin)
refreshAdmin()

--------------------------------------------------------------------------------
-- Daily streak rewards (the server side is DailyRewardService)
--------------------------------------------------------------------------------
local DailyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DailyReward")
local DAILY_GOLD = Color3.fromRGB(255, 200, 80)

local dailyButton = shopButton:Clone()
dailyButton.Name = "DailyButton"
dailyButton.Position = UDim2.new(0, 14, 0.45, -70)
dailyButton.BackgroundColor3 = Color3.fromRGB(255, 150, 60)
dailyButton.Text = "🎁 Daily"
dailyButton.Parent = gui
dailyButton:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(130, 60, 10)

-- red "!" dot while a reward is waiting
local dailyBadge = label(dailyButton, {
	Name = "Badge",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -2, 0, -6),
	Size = UDim2.fromOffset(28, 28),
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(235, 50, 60),
	Text = "!",
	Visible = false,
})
corner(dailyBadge, 14)

local DAILY_W, DAILY_H = 660, 350
local dailyPanel = Instance.new("Frame")
dailyPanel.Name = "DailyPanel"
dailyPanel.AnchorPoint = Vector2.new(0.5, 0.5)
dailyPanel.Position = UDim2.fromScale(0.5, 0.5)
dailyPanel.Size = UDim2.fromOffset(DAILY_W, DAILY_H)
dailyPanel.BackgroundColor3 = Color3.fromRGB(34, 30, 52)
dailyPanel.ZIndex = 5
dailyPanel.Visible = false
dailyPanel.Parent = gui
corner(dailyPanel, 20)
stroke(dailyPanel, 4, Color3.fromRGB(255, 170, 70))
local dailyScale = Instance.new("UIScale")
dailyScale.Parent = dailyPanel
local dailyGradient = panelGradient:Clone()
dailyGradient.Parent = dailyPanel

label(dailyPanel, {
	Position = UDim2.fromOffset(24, 10),
	Size = UDim2.new(1, -110, 0, 48),
	Text = "🎁 DAILY REWARDS",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = DAILY_GOLD,
})
local streakLabel = label(dailyPanel, {
	Position = UDim2.fromOffset(26, 60),
	Size = UDim2.new(1, -52, 0, 22),
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(230, 230, 240),
	TextStrokeTransparency = 1,
	Text = "",
})
local dailyClose = closeButton:Clone()
dailyClose.Parent = dailyPanel

local dailyCards = Instance.new("Frame")
dailyCards.BackgroundTransparency = 1
dailyCards.Position = UDim2.fromOffset(20, 96)
dailyCards.Size = UDim2.new(1, -40, 0, 156)
dailyCards.Parent = dailyPanel
local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Horizontal
cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardLayout.Padding = UDim.new(0, 8)
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Parent = dailyCards

local claimButton = Instance.new("TextButton")
claimButton.AnchorPoint = Vector2.new(0.5, 1)
claimButton.Position = UDim2.new(0.5, 0, 1, -18)
claimButton.Size = UDim2.fromOffset(300, 56)
claimButton.Font = Enum.Font.FredokaOne
claimButton.TextScaled = true
claimButton.TextColor3 = Color3.new(1, 1, 1)
claimButton.TextStrokeTransparency = 0.2
claimButton.Parent = dailyPanel
corner(claimButton, 14)
stroke(claimButton, 3, Color3.fromRGB(20, 60, 20))
local claimPad = Instance.new("UIPadding")
claimPad.PaddingTop = UDim.new(0, 9)
claimPad.PaddingBottom = UDim.new(0, 9)
claimPad.Parent = claimButton

local REWARD_ICONS = { Cash = "💰", Speed = "⚡", Egg = "🥚" }
local dailyState = nil
local dailyAutoOpened = false
local dailyRefreshAsked = 0

local function dailyCard(i, reward, status) -- status: "Claimed", "Ready", "Tomorrow" or "Later"
	local highlight = status == "Ready" or status == "Tomorrow"
	local card = Instance.new("Frame")
	card.LayoutOrder = i
	card.Size = UDim2.fromOffset(80, 156)
	card.BackgroundColor3 = if status == "Ready" then Color3.fromRGB(110, 80, 30) else Color3.fromRGB(52, 46, 78)
	card.BackgroundTransparency = if status == "Claimed" then 0.5 else 0
	card.Parent = dailyCards
	corner(card, 12)
	stroke(card, if highlight then 3 else 2, if status == "Ready" then DAILY_GOLD elseif status == "Tomorrow" then Color3.fromRGB(130, 195, 255) else Color3.fromRGB(95, 90, 125))

	local title = if status == "Ready" then "TODAY" elseif status == "Tomorrow" then "Next" else "Day " .. i
	label(card, { Position = UDim2.fromOffset(4, 6), Size = UDim2.new(1, -8, 0, 22), Text = title, TextColor3 = if highlight then DAILY_GOLD else Color3.fromRGB(210, 210, 225) })
	label(card, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 50), Text = REWARD_ICONS[reward.Kind] or "🎁", TextStrokeTransparency = 1 })
	local rarity = reward.Rarity and Config.RarityById[reward.Rarity]
	local text = label(card, {
		Position = UDim2.fromOffset(4, 92),
		Size = UDim2.new(1, -8, 0, 54),
		Text = reward.Text,
		Font = Enum.Font.GothamBold,
		TextWrapped = true,
		TextColor3 = if rarity then rarity.Color else Color3.new(1, 1, 1),
	})
	local maxSize = Instance.new("UITextSizeConstraint")
	maxSize.MaxTextSize = 17
	maxSize.Parent = text
	if status == "Claimed" then
		label(card, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(52, 52), Text = "✅", TextStrokeTransparency = 1, ZIndex = 2 })
	end
end

local function formatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
end

local function refreshClaimButton()
	local st = dailyState
	if not st then
		claimButton.Text = "Loading..."
		claimButton.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
	elseif st.CanClaim then
		claimButton.Text = "🎁 CLAIM DAY " .. st.Day .. "!"
		claimButton.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
	else
		claimButton.Text = "Next reward in " .. formatCountdown(st.NextAt - workspace:GetServerTimeNow())
		claimButton.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
	end
end

local function rebuildDaily()
	for _, child in ipairs(dailyCards:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local st = dailyState
	if not st then
		return
	end
	for i, reward in ipairs(st.Rewards) do
		local status = "Later"
		if i < st.Day then
			status = "Claimed"
		elseif i == st.Day then
			status = if st.CanClaim then "Ready" else "Tomorrow"
		end
		dailyCard(i, reward, status)
	end
	if st.CurrentStreak > 0 then
		streakLabel.Text = "🔥 " .. st.CurrentStreak .. "-day streak! Come back tomorrow to keep it going."
	else
		streakLabel.Text = "Claim every day in a row for bigger rewards. Miss a day and you start over!"
	end
	dailyBadge.Visible = st.CanClaim
	refreshClaimButton()
end

local dailyFit = 1
local function setDailyOpen(open)
	if open then
		dailyPanel.Visible = true
		DailyRemote:FireServer("Refresh") -- cash rewards grow with your income
		dailyScale.Scale = 0.7 * dailyFit
		TweenService:Create(dailyScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = dailyFit }):Play()
	else
		dailyPanel.Visible = false
	end
end
local function fitDaily()
	local camera = workspace.CurrentCamera
	if camera then
		local vp = camera.ViewportSize
		dailyFit = math.min(1, (vp.X - 40) / DAILY_W, (vp.Y - 60) / DAILY_H)
		dailyScale.Scale = dailyFit
	end
end
fitDaily()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitDaily)
end

dailyButton.Activated:Connect(function()
	setDailyOpen(not dailyPanel.Visible)
end)
dailyClose.Activated:Connect(function()
	setDailyOpen(false)
end)
claimButton.Activated:Connect(function()
	if dailyState and dailyState.CanClaim then
		DailyRemote:FireServer("Claim")
	end
end)

DailyRemote.OnClientEvent:Connect(function(state)
	dailyState = state
	rebuildDaily()
	-- pop the panel open the first time a reward is waiting
	if state.CanClaim and not dailyAutoOpened then
		dailyAutoOpened = true
		task.delay(1.5, setDailyOpen, true)
	end
end)
DailyRemote:FireServer("Refresh")

-- countdown, and ask for a fresh state once the new day starts
task.spawn(function()
	while true do
		task.wait(1)
		local st = dailyState
		if st and not st.CanClaim then
			if dailyPanel.Visible then
				refreshClaimButton()
			end
			if workspace:GetServerTimeNow() >= st.NextAt and dailyRefreshAsked ~= st.NextAt then
				dailyRefreshAsked = st.NextAt
				DailyRemote:FireServer("Refresh")
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Pet Index: a collection book of every pet. The server mirrors the pets you've
-- found into player.PetIndex; finished rarity rows give a cash bonus.
--------------------------------------------------------------------------------
local INDEX_W, INDEX_H = 760, 470
local indexButton = shopButton:Clone()
indexButton.Name = "IndexButton"
indexButton.Position = UDim2.new(0, 14, 0.45, 70)
indexButton.Size = UDim2.fromOffset(150, 50)
indexButton.BackgroundColor3 = Color3.fromRGB(80, 140, 240)
indexButton.Text = "📖 Index"
indexButton.Parent = gui
indexButton:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(20, 50, 120)

local indexPanel = Instance.new("Frame")
indexPanel.Name = "IndexPanel"
indexPanel.AnchorPoint = Vector2.new(0.5, 0.5)
indexPanel.Position = UDim2.fromScale(0.5, 0.52)
indexPanel.Size = UDim2.fromOffset(INDEX_W, INDEX_H)
indexPanel.BackgroundColor3 = Color3.fromRGB(34, 30, 52)
indexPanel.ZIndex = 5
indexPanel.Visible = false
indexPanel.Parent = gui
corner(indexPanel, 20)
stroke(indexPanel, 4, Color3.fromRGB(110, 170, 255))
local indexScale = Instance.new("UIScale")
indexScale.Parent = indexPanel
panelGradient:Clone().Parent = indexPanel

label(indexPanel, {
	Position = UDim2.fromOffset(24, 10),
	Size = UDim2.new(1, -110, 0, 48),
	Text = "📖 PET INDEX",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(150, 200, 255),
})
local indexSummary = label(indexPanel, {
	Position = UDim2.fromOffset(26, 60),
	Size = UDim2.new(1, -52, 0, 22),
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(230, 230, 240),
	TextStrokeTransparency = 1,
	Text = "",
})
local indexClose = closeButton:Clone()
indexClose.Parent = indexPanel

local indexList = Instance.new("ScrollingFrame")
indexList.BackgroundTransparency = 1
indexList.BorderSizePixel = 0
indexList.Position = UDim2.fromOffset(20, 92)
indexList.Size = UDim2.new(1, -30, 1, -104)
indexList.ScrollBarThickness = 6
indexList.AutomaticCanvasSize = Enum.AutomaticSize.Y
indexList.CanvasSize = UDim2.new()
indexList.Parent = indexPanel
local indexLayout = Instance.new("UIListLayout")
indexLayout.Padding = UDim.new(0, 8)
indexLayout.SortOrder = Enum.SortOrder.LayoutOrder
indexLayout.Parent = indexList

local indexTiles = {} -- [pet name] = { Frame, Name, Icon }
local indexHeaders = {} -- [rarity id] = header label
local bonusPercent = math.floor(Config.IndexBonusPerRarity * 100 + 0.5)

for order, rarity in ipairs(Config.Rarities) do
	indexHeaders[rarity.Id] = label(indexList, {
		LayoutOrder = order * 2 - 1,
		Size = UDim2.new(1, -10, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rarity.Color,
		Text = rarity.Id,
	})
	local grid = Instance.new("Frame")
	grid.LayoutOrder = order * 2
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Size = UDim2.new(1, -10, 0, 0)
	grid.Parent = indexList
	local gridLayout2 = Instance.new("UIGridLayout")
	gridLayout2.CellSize = UDim2.fromOffset(160, 44)
	gridLayout2.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout2.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout2.Parent = grid
	for i, def in ipairs(rarity.Creatures) do
		local tile = Instance.new("Frame")
		tile.LayoutOrder = i
		tile.BackgroundColor3 = Color3.fromRGB(52, 46, 78)
		tile.Parent = grid
		corner(tile, 10)
		stroke(tile, 2, rarity.Color)
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 8, 0.5, 0)
		dot.Size = UDim2.fromOffset(28, 28)
		dot.Parent = tile
		corner(dot, 14)
		local icon = label(dot, { Size = UDim2.fromScale(1, 1), Text = "?", TextStrokeTransparency = 1 })
		local name = label(tile, {
			Position = UDim2.fromOffset(42, 0),
			Size = UDim2.new(1, -48, 1, 0),
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeTransparency = 1,
			TextWrapped = true,
		})
		local maxSize = Instance.new("UITextSizeConstraint")
		maxSize.MaxTextSize = 15
		maxSize.Parent = name
		indexTiles[def.Name] = { Frame = tile, Dot = dot, Icon = icon, Name = name, Def = def }
	end
end

local function refreshIndex()
	local folder = player:FindFirstChild("PetIndex")
	local foundAll, totalAll, completeRows = 0, 0, 0
	for _, rarity in ipairs(Config.Rarities) do
		local found = 0
		for _, def in ipairs(rarity.Creatures) do
			local tile = indexTiles[def.Name]
			local have = folder ~= nil and folder:FindFirstChild(def.Name) ~= nil
			if have then
				found += 1
				tile.Dot.BackgroundColor3 = def.Color
				tile.Icon.Text = ""
				tile.Name.Text = def.Name
				tile.Name.TextColor3 = Color3.new(1, 1, 1)
				tile.Frame.BackgroundTransparency = 0
			else
				tile.Dot.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
				tile.Icon.Text = "?"
				tile.Name.Text = "???"
				tile.Name.TextColor3 = Color3.fromRGB(140, 135, 165)
				tile.Frame.BackgroundTransparency = 0.4
			end
		end
		local total = #rarity.Creatures
		foundAll += found
		totalAll += total
		local done = found == total
		if done then
			completeRows += 1
		end
		indexHeaders[rarity.Id].Text = rarity.Id .. "  " .. found .. "/" .. total .. (if done then "  ✅ +" .. bonusPercent .. "% cash" else "  (finish for +" .. bonusPercent .. "% cash)")
	end
	indexSummary.Text = "Found " .. foundAll .. "/" .. totalAll .. " pets  ·  Bonus: +" .. (completeRows * bonusPercent) .. "% cash from all your pets"
end

task.spawn(function()
	local folder = player:WaitForChild("PetIndex")
	folder.ChildAdded:Connect(refreshIndex)
	folder.ChildRemoved:Connect(refreshIndex)
	refreshIndex()
end)
refreshIndex()

local indexFit = 1
local function fitIndex()
	local camera = workspace.CurrentCamera
	if camera then
		local vp = camera.ViewportSize
		indexFit = math.min(1, (vp.X - 40) / INDEX_W, (vp.Y - 60) / INDEX_H)
		indexScale.Scale = indexFit
	end
end
fitIndex()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitIndex)
end
local function setIndexOpen(open)
	indexPanel.Visible = open
	if open then
		indexScale.Scale = 0.7 * indexFit
		TweenService:Create(indexScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = indexFit }):Play()
	end
end
indexButton.Activated:Connect(function()
	setIndexOpen(not indexPanel.Visible)
end)
indexClose.Activated:Connect(function()
	setIndexOpen(false)
end)

--------------------------------------------------------------------------------
-- Revenge: when someone steals your egg, show a timer and outline the thief
-- in red (only you see it) until you steal from them or time runs out.
--------------------------------------------------------------------------------
local revengeBox = Instance.new("Frame")
revengeBox.Name = "RevengeTimer"
revengeBox.AnchorPoint = Vector2.new(1, 0)
revengeBox.Position = UDim2.new(1, -14, 0, 70)
revengeBox.Size = UDim2.fromOffset(270, 64)
revengeBox.BackgroundColor3 = Color3.fromRGB(120, 20, 30)
revengeBox.BackgroundTransparency = 0.1
revengeBox.Visible = false
revengeBox.Parent = gui
corner(revengeBox, 12)
stroke(revengeBox, 3, Color3.fromRGB(255, 90, 90))
local revengeTitle = label(revengeBox, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 30), TextColor3 = Color3.fromRGB(255, 220, 90), Text = "" })
local revengeSub = label(revengeBox, { Position = UDim2.fromOffset(10, 34), Size = UDim2.new(1, -20, 0, 24), Font = Enum.Font.GothamBold, TextStrokeTransparency = 1, Text = "" })

local revengeHighlight = Instance.new("Highlight")
revengeHighlight.FillColor = Color3.fromRGB(255, 40, 40)
revengeHighlight.FillTransparency = 0.6
revengeHighlight.OutlineColor = Color3.fromRGB(255, 220, 90)
revengeHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
revengeHighlight.Enabled = false
revengeHighlight.Parent = workspace.CurrentCamera or workspace

local lastRevengeTarget = nil
local function updateRevenge()
	local targetId = player:GetAttribute("RevengeTarget")
	local untilTime = player:GetAttribute("RevengeUntil") or 0
	local target = targetId and Players:GetPlayerByUserId(targetId)
	local remaining = untilTime - workspace:GetServerTimeNow()
	if not target or remaining <= 0 then
		revengeBox.Visible = false
		revengeHighlight.Enabled = false
		revengeHighlight.Adornee = nil
		lastRevengeTarget = nil
		return
	end
	if target ~= lastRevengeTarget then
		lastRevengeTarget = target
		showZone("🚨 EGG STOLEN!", target.DisplayName .. " took your egg. Steal from them for REVENGE cash!", Color3.fromRGB(255, 90, 90))
	end
	revengeBox.Visible = true
	revengeTitle.Text = "😤 REVENGE on " .. target.DisplayName
	revengeSub.Text = "Steal any egg from them: " .. Util.FormatTime(remaining)
	revengeHighlight.Adornee = target.Character
	revengeHighlight.Enabled = target.Character ~= nil
end
player:GetAttributeChangedSignal("RevengeTarget"):Connect(updateRevenge)
task.spawn(function()
	while true do
		updateRevenge()
		task.wait(0.5)
	end
end)

--------------------------------------------------------------------------------
-- Rainbow mutation: cycle tagged parts through the rainbow
--------------------------------------------------------------------------------
task.spawn(function()
	local rainbowParts = {}
	local function scan()
		table.clear(rainbowParts)
		for _, folderName in ipairs({ "Eggs", "Pets" }) do
			local folder = workspace:FindFirstChild(folderName)
			if folder then
				for _, d in ipairs(folder:GetDescendants()) do
					if d:IsA("BasePart") and d:GetAttribute("RainbowFX") then
						table.insert(rainbowParts, d)
					end
				end
			end
		end
	end
	local t, lastScan = 0, -1
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		if t - lastScan > 1 then
			lastScan = t
			scan()
		end
		for i, p in ipairs(rainbowParts) do
			if p.Parent then
				p.Color = Color3.fromHSV((t * 0.35 + i * 0.07) % 1, 0.65, 1)
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- Welcome tips
--------------------------------------------------------------------------------
task.delay(2, function()
	toast("🥚 Run down the road, grab an egg from a nest and outrun its guardian!", Color3.fromRGB(255, 230, 150))
	task.wait(4.5)
	toast("🏃 Step on your treadmill to train Speed and reach rarer zones.", Color3.fromRGB(255, 225, 120))
	task.wait(4.5)
	toast("😈 Steal eggs from other players. 🏏 Bonk thieves with your bat!", Color3.fromRGB(255, 190, 120))
end)
