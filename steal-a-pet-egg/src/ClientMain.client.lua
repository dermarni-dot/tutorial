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
cashPanel.Position = UDim2.new(0.5, 0, 0, 8)
cashPanel.Size = UDim2.fromOffset(270, 72)
cashPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
cashPanel.Parent = gui
corner(cashPanel, 16)
stroke(cashPanel, 3, Color3.fromRGB(255, 200, 70))
local cashGradient = Instance.new("UIGradient")
cashGradient.Color = ColorSequence.new(Color3.fromRGB(58, 46, 92), Color3.fromRGB(24, 20, 38))
cashGradient.Rotation = 90
cashGradient.Parent = cashPanel
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

-- small rounded badge used under the cash panel
local function pill(parent, props)
	local l = label(parent, props)
	l.BackgroundTransparency = 0.1
	l.BackgroundColor3 = Color3.fromRGB(26, 22, 40)
	corner(l, 12)
	stroke(l, 2, props.TextColor3)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = l
	return l
end

local speedLabel = pill(cashPanel, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 6),
	Size = UDim2.fromOffset(230, 28),
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255, 225, 120),
	Text = "⚡ Speed 0",
})

local lockLabel = pill(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 118),
	Size = UDim2.fromOffset(250, 28),
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
corner(carryBanner, 14)
local carryStroke = Instance.new("UIStroke")
carryStroke.Thickness = 3
carryStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
carryStroke.Parent = carryBanner
local carryScale = Instance.new("UIScale")
carryScale.Parent = carryBanner
local carryPulse = TweenService:Create(carryScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.07 })
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
		carryPulse:Cancel()
		return
	end
	local rarity = Config.RarityById[rarityId]
	local stolen = player:GetAttribute("CarryingStolen")
	local chasedBy = player:GetAttribute("ChasedBy")
	if chasedBy then
		carryPulse:Play()
	else
		carryPulse:Cancel()
		carryScale.Scale = 1
	end
	carryStroke.Color = if chasedBy or stolen then Color3.fromRGB(255, 90, 90) elseif rarity then rarity.Color else Color3.new(1, 1, 1)
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
toastList.Position = UDim2.new(0.5, 0, 0, 182)
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
	local itemStroke = Instance.new("UIStroke")
	itemStroke.Thickness = 2
	itemStroke.Color = color or Color3.new(1, 1, 1)
	itemStroke.Transparency = 0.35
	itemStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	itemStroke.Parent = item
	local itemScale = Instance.new("UIScale")
	itemScale.Scale = 0.85
	itemScale.Parent = item
	item.BackgroundTransparency = 1
	item.TextTransparency = 1
	item.TextStrokeTransparency = 1
	TweenService:Create(itemScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(item, TweenInfo.new(0.2), { BackgroundTransparency = 0.15, TextTransparency = 0, TextStrokeTransparency = 0.6 }):Play()

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
			TweenService:Create(itemStroke, fade, { Transparency = 1 }):Play()
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
panel.ZIndex = 5
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
	Position = UDim2.new(0.5, 0, 0, 150),
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

--------------------------------------------------------------------------------
-- Day and night. The clock comes from server time so everyone sees the same
-- sky; some zones pin their own time (Magma Crater = sunset, Void = night).
--------------------------------------------------------------------------------
local zoneClock = 15
local zoneClockBlend = Instance.new("NumberValue") -- 0 = follow the day cycle, 1 = zone's own time
zoneClockBlend.Value = 0
local dayAmbient = Instance.new("Color3Value")
dayAmbient.Value = Config.TownMood.Ambient or Color3.fromRGB(126, 132, 148)
local NIGHT_AMBIENT = Color3.fromRGB(64, 74, 118)
local NIGHT_INDOOR = Color3.fromRGB(38, 42, 66)
local DAY_INDOOR = Color3.fromRGB(58, 62, 74)

local function cycleClock()
	if gui:GetAttribute("AlwaysDay") then
		return 13
	end
	local fixed = workspace:GetAttribute("ClockOverride")
	if type(fixed) == "number" then
		return fixed
	end
	local minutes = Config.DayCycleMinutes or 0
	if minutes <= 0 then
		return 15
	end
	local dayShare = Config.DayFraction or 0.72
	local t = (workspace:GetServerTimeNow() / (minutes * 60)) % 1
	if t < dayShare then
		return 6.5 + t / dayShare * 12 -- 6:30 sunrise to 18:30 sunset
	end
	return (18.5 + (t - dayShare) / (1 - dayShare) * 12) % 24
end

local function blendClock(a, b, t)
	local d = (b - a + 12) % 24 - 12
	return (a + d * t) % 24
end

-- 1 in full daylight, 0 at night, smooth through dawn and dusk
local function daylight(clock)
	if clock >= 7.5 and clock <= 17 then
		return 1
	elseif clock >= 19.5 or clock <= 5 then
		return 0
	elseif clock < 7.5 then
		return (clock - 5) / 2.5
	end
	return 1 - (clock - 17) / 2.5
end

-- The zone's own sky (tweened when you change zones); the time of day tints it
local zoneSky = {
	AtmoColor = Instance.new("Color3Value"),
	AtmoDecay = Instance.new("Color3Value"),
	CloudColor = Instance.new("Color3Value"),
	Haze = Instance.new("NumberValue"),
	Glare = Instance.new("NumberValue"),
	Density = Instance.new("NumberValue"),
	Cover = Instance.new("NumberValue"),
}
zoneSky.AtmoColor.Value = Config.TownMood.Color
zoneSky.AtmoDecay.Value = Config.TownMood.Decay
zoneSky.CloudColor.Value = Config.TownMood.CloudColor or Color3.new(1, 1, 1)
zoneSky.Haze.Value = Config.TownMood.Haze
zoneSky.Glare.Value = Config.TownMood.Glare or 0.2
zoneSky.Density.Value = Config.TownMood.Density
zoneSky.Cover.Value = Config.TownMood.CloudCover or 0.6
local SUNSET_SKY, SUNSET_DECAY, SUNSET_CLOUD = Color3.fromRGB(255, 175, 145), Color3.fromRGB(235, 110, 95), Color3.fromRGB(255, 175, 165)
local NIGHT_SKY, NIGHT_DECAY, NIGHT_CLOUD = Color3.fromRGB(45, 55, 115), Color3.fromRGB(15, 20, 55), Color3.fromRGB(70, 75, 110)

local clockTime = 15
game:GetService("RunService").Heartbeat:Connect(function()
	clockTime = blendClock(cycleClock(), zoneClock, zoneClockBlend.Value)
	local d = daylight(clockTime)
	Lighting.ClockTime = clockTime
	Lighting.Brightness = 0.9 + 1.4 * d
	Lighting.OutdoorAmbient = NIGHT_AMBIENT:Lerp(dayAmbient.Value, d)
	Lighting.Ambient = NIGHT_INDOOR:Lerp(DAY_INDOOR, d)
	Lighting.ExposureCompensation = -0.12 + (1 - d) * 0.3
	-- warm light at the edges of the day
	local golden = math.max(0, 1 - math.abs(d - 0.5) * 2)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 240, 215):Lerp(Color3.fromRGB(255, 170, 110), golden)
	-- sky colors: golden-pink at sunrise/sunset, deep blue at night. Zones that
	-- pin their own time (Void, Magma Crater...) keep their own sky.
	local follow = 1 - zoneClockBlend.Value
	local sunset, night = golden * follow, (1 - d) * follow
	local atmosphere = Lighting:FindFirstChild("MoodAtmosphere")
	if atmosphere then
		atmosphere.Color = zoneSky.AtmoColor.Value:Lerp(SUNSET_SKY, sunset * 0.55):Lerp(NIGHT_SKY, night * 0.7)
		atmosphere.Decay = zoneSky.AtmoDecay.Value:Lerp(SUNSET_DECAY, sunset * 0.5):Lerp(NIGHT_DECAY, night * 0.8)
		atmosphere.Haze = zoneSky.Haze.Value + sunset * 0.8
		atmosphere.Glare = zoneSky.Glare.Value + sunset * 0.7
		atmosphere.Density = zoneSky.Density.Value
	end
	local clouds = workspace.Terrain:FindFirstChild("MoodClouds")
	if clouds then
		clouds.Color = zoneSky.CloudColor.Value:Lerp(SUNSET_CLOUD, sunset * 0.6):Lerp(NIGHT_CLOUD, night * 0.8)
		clouds.Cover = zoneSky.Cover.Value * (1 - night * 0.35)
	end
end)

local function applyMood(mood)
	local atmosphere = Lighting:FindFirstChild("MoodAtmosphere")
	local cc = Lighting:FindFirstChild("MoodCC")
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	if atmosphere then
		TweenService:Create(zoneSky.AtmoColor, info, { Value = mood.Color }):Play()
		TweenService:Create(zoneSky.AtmoDecay, info, { Value = mood.Decay }):Play()
		TweenService:Create(zoneSky.Haze, info, { Value = mood.Haze }):Play()
		TweenService:Create(zoneSky.Glare, info, { Value = mood.Glare or 0.2 }):Play()
		TweenService:Create(zoneSky.Density, info, { Value = mood.Density }):Play()
	end
	if cc then
		TweenService:Create(cc, info, { TintColor = mood.Tint, Brightness = mood.Brightness, Saturation = mood.Saturation, Contrast = mood.Contrast or 0.1 }):Play()
	end
	local bloom = Lighting:FindFirstChild("MoodBloom")
	if bloom then
		TweenService:Create(bloom, info, { Intensity = mood.Bloom or 0.4 }):Play()
	end
	local rays = Lighting:FindFirstChild("MoodRays")
	if rays then
		TweenService:Create(rays, info, { Intensity = mood.Rays or 0.04 }):Play()
	end
	if mood.Clock then
		zoneClock = mood.Clock
	end
	TweenService:Create(zoneClockBlend, TweenInfo.new(3, Enum.EasingStyle.Sine), { Value = if mood.Clock then 1 else 0 }):Play()
	TweenService:Create(dayAmbient, info, { Value = mood.Ambient or Color3.fromRGB(126, 132, 148) }):Play()
	if mood.CloudColor then
		TweenService:Create(zoneSky.CloudColor, info, { Value = mood.CloudColor }):Play()
		TweenService:Create(zoneSky.Cover, info, { Value = mood.CloudCover or 0.6 }):Play()
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
					gui:SetAttribute("ZoneColor", Color3.fromRGB(255, 240, 200))
					gui:SetAttribute("ZoneName", "🏠 Town")
					applyMood(Config.TownMood)
					if not first then
						showZone("🏠 Town", "You're safe here. Get your egg home!", Color3.fromRGB(255, 240, 200))
					end
				else
					local def = Config.Biomes[zone]
					gui:SetAttribute("ZoneColor", def.GuardianColor:Lerp(Color3.new(1, 1, 1), 0.35))
					gui:SetAttribute("ZoneName", "📍 " .. def.Name)
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
			local orbs = {}
			local halo = plot:FindFirstChild("TreadHalo")
			if halo then
				for i, orb in ipairs(halo:GetChildren()) do
					orbs[i] = orb
				end
			end
			table.insert(belts, { Tread = tread, Length = stripes:GetAttribute("Length") or tread.Size.Z, Stripes = list, Halo = halo, Orbs = orbs, Pos = 0, Speed = 1 })
		end
	end
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		for _, belt in ipairs(belts) do
			local cf = belt.Tread.CFrame
			local back = -cf.LookVector
			-- the belt speeds up smoothly while someone is training on it
			local want = if belt.Tread:GetAttribute("Running") then 2.6 else 1
			belt.Speed += (want - belt.Speed) * math.min(1, dt * 3)
			belt.Pos += dt * belt.Speed * Config.TreadmillBeltSpeed / belt.Length
			local rainbow = belt.Tread:GetAttribute("Rainbow")
			for i, s in ipairs(belt.Stripes) do
				local frac = (s.Offset + belt.Pos) % 1
				local pos = cf.Position + back * ((frac - 0.5) * belt.Length)
				s.Part.CFrame = CFrame.lookAt(Vector3.new(pos.X, s.Y, pos.Z), Vector3.new(pos.X, s.Y, pos.Z) + cf.LookVector)
				if rainbow then
					s.Part.Color = Color3.fromHSV((t * 0.25 + i / #belt.Stripes) % 1, 0.6, 1)
				end
			end
			-- top tiers: a ring of orbs spins and bobs above the treadmill
			local halo = belt.Halo
			if halo and #belt.Orbs > 0 and belt.Orbs[1].Transparency < 1 then
				local center = halo:GetAttribute("Center")
				local radius = halo:GetAttribute("Radius") or 3
				if center then
					local spin = t * belt.Speed * 0.9
					for i, orb in ipairs(belt.Orbs) do
						local a = spin + i / #belt.Orbs * math.pi * 2
						orb.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * radius, math.sin(t * 2 + i) * 0.35, math.sin(a) * radius))
					end
				end
			end
		end
	end)
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
adminRow({ { "+100M", "speed 100000000", GOLD_BTN }, { "+1B", "speed 1000000000", GOLD_BTN }, { "+10B", "speed 10000000000", GOLD_BTN }, { "+50B", "speed 50000000000", GOLD_BTN } })
adminRow({ { "+1T", "speed 1000000000000", GOLD_BTN }, { "+100T", "speed 100000000000000", GOLD_BTN }, { "+2.5Qa", "speed 2500000000000000", GOLD_BTN }, { "+10Qa", "speed 10000000000000000", GOLD_BTN } })
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
adminRow({ { "Max Treadmill", "treadmill " .. #Config.TreadmillLevels, GOLD_BTN }, { "Basic Treadmill", "treadmill 1", GOLD_BTN } })
adminRow({ { "2x Luck", "luck 2", GREEN_BTN }, { "5x Luck", "luck 5", GREEN_BTN }, { "10x Luck", "luck 10", GREEN_BTN }, { "Egg Rain", "rain" } })
adminHeader("🚀 Teleport")
adminRow({ { "Town", "tp town" }, { "Forest", "tp forest" }, { "Desert", "tp desert" } })
adminRow({ { "Snow", "tp snow" }, { "Volcano", "tp volcano" }, { "Void", "tp void" } })
adminRow({ { "Candy", "tp candy" }, { "Reef", "tp ocean" }, { "Heaven", "tp heaven" } })
adminRow({ { "Shroom", "tp shroom" }, { "Spooky", "tp spooky" }, { "Clock", "tp clockwork" }, { "Neon", "tp cyber" } })
adminRow({ { "Jungle", "tp jungle" }, { "Crystal", "tp crystal" }, { "Toy", "tp toy" }, { "Aurora", "tp aurora" } })
adminRow({ { "Sakura", "tp sakura" }, { "Inferno", "tp inferno" }, { "Galaxy", "tp galaxy" }, { "Rainbow", "tp rainbow" } })
adminHeader("🌙 Time of day (everyone)")
adminRow({ { "Day", "time day", GOLD_BTN }, { "Sunset", "time sunset", GOLD_BTN }, { "Night", "time night", GOLD_BTN }, { "Cycle", "time cycle", GOLD_BTN } })
adminHeader("🎁 Daily reward")
adminRow({ { "Next Day", "daily", GOLD_BTN }, { "Back to Day 1", "daily reset", GOLD_BTN } })
adminHeader("⚠️ Danger")
adminRow({ { "Reset My Progress", "reset", RED_BTN } })
adminOrder += 1
local chatHelp = label(adminPanel, { LayoutOrder = adminOrder, Size = UDim2.new(1, 0, 0, 60), Font = Enum.Font.Gotham, TextStrokeTransparency = 1, TextColor3 = Color3.fromRGB(200, 200, 215), Text = "Chat commands: !cash 500 · !speed 50 · !egg mythic · !pet galaxy dragon · !shiny divine · !luck 10 · !tp void · !daily · !time night · !help" })
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
-- UI polish: side menu, bouncy glossy buttons, one panel open at a time
--------------------------------------------------------------------------------
-- Side menu: Daily / Shop / Index / Admin stacked on the left edge
local sideMenu = Instance.new("Frame")
sideMenu.Name = "SideMenu"
sideMenu.AnchorPoint = Vector2.new(0, 0.5)
sideMenu.Position = UDim2.new(0, 14, 0.5, 0)
sideMenu.Size = UDim2.fromOffset(160, 280)
sideMenu.BackgroundTransparency = 1
sideMenu.ZIndex = 6 -- stays clickable above the dimmed backdrop
sideMenu.Parent = gui
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 10)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sideLayout.Parent = sideMenu
local sideScale = Instance.new("UIScale")
sideScale.Parent = sideMenu
for order, button in ipairs({ dailyButton, shopButton, indexButton, adminButton }) do
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(160, if button == adminButton then 46 else 56)
	button.Parent = sideMenu
end
adminPanel.Position = UDim2.new(0, 190, 0.5, 0)
adminPanel.ZIndex = 6
toastList.ZIndex = 7 -- notifications show above open panels

local function fitSideMenu()
	local camera = workspace.CurrentCamera
	if camera then
		sideScale.Scale = math.clamp(camera.ViewportSize.Y / 720, 0.7, 1)
	end
end
fitSideMenu()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitSideMenu)
end

-- Dim the game behind open panels; tap outside a panel to close it
local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 1
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.ZIndex = 4
backdrop.Visible = false
backdrop.Parent = gui

local menuPanels = { panel, dailyPanel, indexPanel }
local function refreshBackdrop()
	local anyOpen = false
	for _, p in ipairs(menuPanels) do
		anyOpen = anyOpen or p.Visible
	end
	if anyOpen and not backdrop.Visible then
		backdrop.Visible = true
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
	elseif not anyOpen then
		backdrop.Visible = false
	end
end
for _, p in ipairs(menuPanels) do
	p:GetPropertyChangedSignal("Visible"):Connect(function()
		if p.Visible then
			for _, other in ipairs(menuPanels) do
				if other ~= p then
					other.Visible = false
				end
			end
		end
		refreshBackdrop()
	end)
end
backdrop.Activated:Connect(function()
	for _, p in ipairs(menuPanels) do
		p.Visible = false
	end
end)

-- Every button gets a glossy top light and grows on hover / squishes on press
local juiced = setmetatable({}, { __mode = "k" })
juiced[backdrop] = true
local PRESS = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function juice(button)
	if juiced[button] then
		return
	end
	juiced[button] = true
	local scale = button:FindFirstChild("PressScale") or Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = button
	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		TweenService:Create(scale, PRESS, { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		TweenService:Create(scale, PRESS, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, PRESS, { Scale = 0.92 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, PRESS, { Scale = if hovering then 1.05 else 1 }):Play()
	end)
	if not button:FindFirstChildOfClass("UIGradient") then
		local gloss = Instance.new("UIGradient")
		gloss.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 215))
		gloss.Rotation = 90
		gloss.Parent = button
	end
end
for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("TextButton") then
		juice(d)
	end
end
gui.DescendantAdded:Connect(function(d)
	if d:IsA("TextButton") then
		juice(d)
	end
end)

-- The Daily button gently wiggles while a reward is waiting
task.spawn(function()
	local wiggle = TweenInfo.new(0.12, Enum.EasingStyle.Sine)
	while true do
		task.wait(3)
		if dailyBadge.Visible then
			for _, angle in ipairs({ -6, 6, -4, 4, 0 }) do
				TweenService:Create(dailyButton, wiggle, { Rotation = angle }):Play()
				task.wait(0.12)
			end
		end
	end
end)


-- Sky life: hot air balloons drifting over town and bird flocks by day.
-- Client-only decorations, so they cost the server nothing.
local function setupSkyLife()
	local RunService = game:GetService("RunService")
	local folder = Instance.new("Folder")
	folder.Name = "SkyLife"
	folder.Parent = workspace
	local function skyPart(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do
			p[k] = v
		end
		p.Parent = folder
		return p
	end

	-- balloons: a striped envelope, a basket and ropes, all welded to the envelope
	local balloonColors = { { Color3.fromRGB(255, 90, 110), Color3.fromRGB(255, 220, 90) }, { Color3.fromRGB(90, 170, 255), Color3.new(1, 1, 1) }, { Color3.fromRGB(120, 220, 130), Color3.fromRGB(255, 150, 60) }, { Color3.fromRGB(190, 120, 255), Color3.fromRGB(255, 190, 230) }, { Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 90, 90) } }
	local balloons = {}
	for i, pair in ipairs(balloonColors) do
		local model = Instance.new("Model")
		model.Name = "Balloon"
		model.Parent = folder
		local envelope = skyPart({ Name = "Envelope", Shape = Enum.PartType.Ball, Size = Vector3.one * 22, Color = pair[1], Material = Enum.Material.Fabric })
		envelope.Parent = model
		model.PrimaryPart = envelope
		local parts = { { envelope, CFrame.new() } }
		for band = -2, 2 do
			local r = 11 * math.cos(math.asin(band * 3.2 / 11))
			local b = skyPart({ Name = "Stripe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, r * 2 + 0.3, r * 2 + 0.3), Color = if band % 2 == 0 then pair[2] else pair[1], Material = Enum.Material.Fabric })
			b.Parent = model
			table.insert(parts, { b, CFrame.new(0, band * 3.2, 0) * CFrame.Angles(0, 0, math.rad(90)) })
		end
		local basket = skyPart({ Name = "Basket", Size = Vector3.new(4, 3, 4), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.WoodPlanks })
		basket.Parent = model
		table.insert(parts, { basket, CFrame.new(0, -17, 0) })
		for _, c in ipairs({ { -1.6, -1.6 }, { 1.6, -1.6 }, { -1.6, 1.6 }, { 1.6, 1.6 } }) do
			local rope = skyPart({ Name = "Rope", Size = Vector3.new(0.2, 8, 0.2), Color = Color3.fromRGB(90, 70, 50), Material = Enum.Material.Fabric })
			rope.Parent = model
			table.insert(parts, { rope, CFrame.new(c[1] * 1.3, -12, c[2] * 1.3) })
		end
		local flame = skyPart({ Name = "Burner", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, Color = Color3.fromRGB(255, 170, 60), Material = Enum.Material.Neon })
		flame.Parent = model
		table.insert(parts, { flame, CFrame.new(0, -11, 0) })
		local center = Vector3.new(-420 + i * 150, 0, -10 + (i % 2) * 120)
		table.insert(balloons, { Parts = parts, Center = center, Radius = 40 + i * 8, Height = 115 + i * 12, Speed = 0.02 + i * 0.004, Phase = i * 1.3 })
	end

	-- birds: little V flocks that cross the sky while it's light out
	local flocks = {}
	local function newFlock()
		local parts = {}
		local dir = if math.random() < 0.5 then 1 else -1
		for k = 0, 6 do
			local row = math.ceil(k / 2)
			local side = if k % 2 == 0 then 1 else -1
			for w = -1, 1, 2 do
				local wing = skyPart({ Name = "Wing", Size = Vector3.new(1.6, 0.15, 0.5), Color = Color3.fromRGB(40, 40, 50), Material = Enum.Material.SmoothPlastic })
				table.insert(parts, { wing, Vector3.new(-dir * row * 3, 0, side * row * 3), w })
			end
		end
		return { Parts = parts, Dir = dir, X = -dir * 800, Z = math.random(-60, 1600), Y = math.random(90, 140), Speed = math.random(22, 32) }
	end

	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		for _, b in ipairs(balloons) do
			local a = t * b.Speed + b.Phase
			local pos = b.Center + Vector3.new(math.cos(a) * b.Radius, b.Height + math.sin(t * 0.3 + b.Phase) * 4, math.sin(a) * b.Radius)
			local root = CFrame.new(pos) * CFrame.Angles(0, a, 0)
			for _, entry in ipairs(b.Parts) do
				entry[1].CFrame = root * entry[2]
			end
		end
		local light = Lighting.ClockTime > 6.5 and Lighting.ClockTime < 18
		if light and #flocks < 2 and math.random() < dt * 0.05 then
			table.insert(flocks, newFlock())
		end
		for i = #flocks, 1, -1 do
			local f = flocks[i]
			f.X += f.Dir * f.Speed * dt
			local flap = math.sin(t * 10) * 0.5
			for _, entry in ipairs(f.Parts) do
				local base = Vector3.new(f.X, f.Y, f.Z) + entry[2]
				entry[1].CFrame = CFrame.new(base + Vector3.new(0, 0, entry[3] * 0.8)) * CFrame.Angles(entry[3] * flap, 0, 0)
			end
			if math.abs(f.X) > 820 then
				for _, entry in ipairs(f.Parts) do
					entry[1]:Destroy()
				end
				table.remove(flocks, i)
			end
		end
	end)
end
setupSkyLife()

--------------------------------------------------------------------------------
-- Slapped! When a guardian catches you: white flash, camera shake, a big SLAP!,
-- you spin through the air, then land at home with dizzy stars.
--------------------------------------------------------------------------------
local function setupSlap()
	local SlapRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Slapped")
	local RunService = game:GetService("RunService")

	local flash = Instance.new("Frame")
	flash.Name = "SlapFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 50
	flash.Visible = false
	flash.Parent = gui

	local slapText = Instance.new("TextLabel")
	slapText.Name = "SlapText"
	slapText.AnchorPoint = Vector2.new(0.5, 0.5)
	slapText.Position = UDim2.fromScale(0.5, 0.4)
	slapText.Size = UDim2.fromOffset(520, 170)
	slapText.BackgroundTransparency = 1
	slapText.Font = Enum.Font.FredokaOne
	slapText.TextScaled = true
	slapText.Text = "SLAP!"
	slapText.TextColor3 = Color3.fromRGB(255, 230, 70)
	slapText.TextStrokeTransparency = 1
	slapText.ZIndex = 51
	slapText.Visible = false
	slapText.Parent = gui
	local slapStroke = Instance.new("UIStroke")
	slapStroke.Thickness = 6
	slapStroke.Color = Color3.fromRGB(150, 20, 20)
	slapStroke.Parent = slapText
	local slapScale = Instance.new("UIScale")
	slapScale.Parent = slapText
	local subText = Instance.new("TextLabel")
	subText.Name = "SlapSub"
	subText.AnchorPoint = Vector2.new(0.5, 0)
	subText.Position = UDim2.new(0.5, 0, 1, -8)
	subText.Size = UDim2.new(1, 0, 0, 36)
	subText.BackgroundTransparency = 1
	subText.Font = Enum.Font.GothamBlack
	subText.TextScaled = true
	subText.TextColor3 = Color3.new(1, 1, 1)
	subText.TextStrokeTransparency = 0.2
	subText.ZIndex = 51
	subText.Parent = slapText

	local shakeUntil, shakeStrength = 0, 0
	RunService:BindToRenderStep("SlapShake", Enum.RenderPriority.Camera.Value + 1, function()
		local left = shakeUntil - os.clock()
		if left > 0 then
			local s = shakeStrength * math.min(1, left / 0.5)
			local cam = workspace.CurrentCamera
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * s), math.rad((math.random() - 0.5) * s), math.rad((math.random() - 0.5) * s * 1.5))
		end
	end)

	-- dizzy stars circling your head after you land
	local function dizzy(char, seconds)
		local head = char:FindFirstChild("Head")
		if not head then
			return
		end
		local stars = Instance.new("BillboardGui")
		stars.Name = "DizzyStars"
		stars.Size = UDim2.fromOffset(90, 40)
		stars.StudsOffset = Vector3.new(0, 2.2, 0)
		stars.LightInfluence = 0
		stars.Parent = head
		local labels = {}
		for i = 1, 3 do
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromOffset(26, 26)
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.TextScaled = true
			l.Text = if i == 2 then "💫" else "⭐"
			l.Parent = stars
			labels[i] = l
		end
		local start = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t > seconds or not stars.Parent then
				conn:Disconnect()
				stars:Destroy()
				return
			end
			for i, l in ipairs(labels) do
				local a = t * 6 + i * math.pi * 2 / 3
				l.Position = UDim2.new(0.5, math.cos(a) * 34, 0.5, math.sin(a) * 9)
				l.ZIndex = if math.sin(a) > 0 then 2 else 1
			end
		end)
	end

	local lines = { "Back to the start!", "Ouch! Sent home!", "That's gotta hurt!", "Yeeted home!", "Bonk! Try again!" }
	SlapRemote.OnClientEvent:Connect(function(away, guardianName)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local flightTime = Config.SlapFlightTime or 1.1

		-- flash + shake + SLAP!
		flash.Visible = true
		flash.BackgroundTransparency = 0.1
		TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		task.delay(0.36, function()
			flash.Visible = false
		end)
		shakeUntil, shakeStrength = os.clock() + 0.6, 6
		slapText.Visible = true
		slapText.Rotation = math.random(-12, 12)
		slapText.TextTransparency = 0
		slapStroke.Transparency = 0
		subText.Text = (if guardianName then "The " .. guardianName .. " got you! " else "") .. lines[math.random(#lines)]
		subText.TextTransparency = 0
		slapScale.Scale = 2.4
		TweenService:Create(slapScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(flightTime + 0.4, function()
			local info = TweenInfo.new(0.35)
			TweenService:Create(slapText, info, { TextTransparency = 1 }):Play()
			TweenService:Create(slapStroke, info, { Transparency = 1 }):Play()
			TweenService:Create(subText, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.36, function()
				slapText.Visible = false
				subText.TextStrokeTransparency = 0.2
			end)
		end)

		-- fly! spinning up and away until the server lands you at home
		if root and humanoid then
			local dir = if typeof(away) == "Vector3" and away.Magnitude > 0 then away.Unit else root.CFrame.LookVector
			humanoid.PlatformStand = true
			root.AssemblyLinearVelocity = dir * 90 + Vector3.new(0, 75, 0)
			root.AssemblyAngularVelocity = dir:Cross(Vector3.yAxis) * -14 + Vector3.new(0, 8, 0)
			task.delay(flightTime + 0.1, function()
				if humanoid.Parent then
					humanoid.PlatformStand = false
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
					dizzy(char, Config.GuardianStunTime or 1.5)
				end
			end)
		end
	end)
end
setupSlap()

--------------------------------------------------------------------------------
-- Trail home: while you carry an egg, a glowing beam runs from you to your base
-- so you can find your way back at top speed without slowing down to look.
--------------------------------------------------------------------------------
local function setupHomeTrail()
	local target = Instance.new("Part")
	target.Name = "HomeTrailTarget"
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Transparency = 1
	target.Size = Vector3.one
	local targetAttach = Instance.new("Attachment")
	targetAttach.Parent = target
	local beam = Instance.new("Beam")
	beam.Name = "HomeTrail"
	beam.Attachment1 = targetAttach
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 225, 90), Color3.fromRGB(120, 255, 150))
	beam.Transparency = NumberSequence.new(0.15, 0.5)
	beam.LightEmission = 1
	beam.Width0 = 1.4
	beam.Width1 = 3
	beam.FaceCamera = true
	beam.Segments = 20
	beam.Enabled = false
	beam.Parent = target

	local function myFloor()
		local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
		if not plots then
			return nil
		end
		for _, plot in ipairs(plots:GetChildren()) do
			if plot:GetAttribute("OwnerUserId") == player.UserId then
				return plot:FindFirstChild("Floor")
			end
		end
		return nil
	end

	local function refresh()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local floor = myFloor()
		if player:GetAttribute("CarryingEgg") and root and floor then
			local rootAttach = root:FindFirstChild("HomeTrailAttach") or Instance.new("Attachment")
			rootAttach.Name = "HomeTrailAttach"
			rootAttach.Position = Vector3.new(0, -2.2, 0)
			rootAttach.Parent = root
			target.Position = floor.Position + Vector3.new(0, 2, 0)
			target.Parent = workspace
			beam.Attachment0 = rootAttach
			beam.Enabled = true
		else
			beam.Enabled = false
		end
	end
	player:GetAttributeChangedSignal("CarryingEgg"):Connect(refresh)
	player.CharacterAdded:Connect(function()
		task.defer(refresh)
	end)
	refresh()
end
setupHomeTrail()

--------------------------------------------------------------------------------
-- Incubator panel: every egg in your pet pen with how long until it hatches.
-- Soonest first; tap the header to fold it away.
--------------------------------------------------------------------------------
local function setupIncubator()
	local MAX_ROWS = 8
	local panel = Instance.new("Frame")
	panel.Name = "Incubator"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -14, 0.56, 0)
	panel.Size = UDim2.fromOffset(250, 40)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(28, 24, 44)
	panel.BackgroundTransparency = 0.15
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)
	stroke(panel, 2, Color3.fromRGB(255, 205, 90))
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, 26)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.FredokaOne
	header.TextScaled = true
	header.TextColor3 = Color3.fromRGB(255, 225, 120)
	header.TextStrokeTransparency = 0.5
	header.Text = "🥚 Incubating"
	header.Parent = panel
	juiced[header] = true
	local folded = false
	header.Activated:Connect(function()
		folded = not folded
	end)

	local rows = {}
	for i = 1, MAX_ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundColor3 = Color3.fromRGB(45, 40, 70)
		row.Visible = false
		row.Parent = panel
		corner(row, 10)
		local icon = Instance.new("Frame")
		icon.Name = "EggIcon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 6, 0.5, 0)
		icon.Size = UDim2.fromOffset(22, 28)
		icon.Parent = row
		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0.5, 0)
		iconCorner.Parent = icon
		local iconStroke = Instance.new("UIStroke")
		iconStroke.Thickness = 2
		iconStroke.Parent = icon
		local name = label(row, { Name = "EggName", Position = UDim2.fromOffset(34, 2), Size = UDim2.new(1, -96, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, Text = "" })
		local time = label(row, { Name = "TimeLeft", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 2), Size = UDim2.fromOffset(58, 18), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(150, 255, 160), Text = "" })
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.Position = UDim2.fromOffset(34, 25)
		bar.Size = UDim2.new(1, -40, 0, 9)
		bar.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
		bar.Parent = row
		corner(bar, 5)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = bar
		corner(fill, 5)
		rows[i] = { Row = row, Icon = icon, IconStroke = iconStroke, Name = name, Time = time, Fill = fill }
	end
	local more = label(panel, { Name = "More", LayoutOrder = MAX_ROWS + 1, Size = UDim2.new(1, 0, 0, 16), Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(200, 195, 220), TextStrokeTransparency = 1, Text = "" })

	local function refresh()
		local eggsFolder = workspace:FindFirstChild("Eggs")
		local mine = {}
		if eggsFolder then
			for _, egg in ipairs(eggsFolder:GetChildren()) do
				if egg:GetAttribute("OwnerUserId") == player.UserId then
					table.insert(mine, egg)
				end
			end
		end
		table.sort(mine, function(a, b)
			return (a:GetAttribute("TimeLeft") or 0) < (b:GetAttribute("TimeLeft") or 0)
		end)
		panel.Visible = #mine > 0
		header.Text = "🥚 Incubating (" .. #mine .. ")" .. (if folded then "  ▸" else "  ▾")
		for i, r in ipairs(rows) do
			local egg = mine[i]
			r.Row.Visible = egg ~= nil and not folded
			if egg then
				local rarity = Config.RarityById[egg:GetAttribute("Rarity") or ""]
				local mutation = Config.MutationById[egg:GetAttribute("Mutation") or ""]
				local size = egg:GetAttribute("PetSize") or 1
				local color = if rarity then rarity.Color else Color3.new(1, 1, 1)
				local title = (if rarity then rarity.Id else "?") .. " Egg"
				if mutation then
					title = mutation.Icon .. " " .. mutation.Id .. " " .. title
				end
				if size >= Config.HugePetSize then
					title = "HUGE " .. title
				elseif size >= Config.BigPetSize then
					title = "BIG " .. title
				end
				r.Name.Text = title
				r.Name.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.4)
				r.Icon.BackgroundColor3 = color
				r.IconStroke.Color = if mutation then mutation.Color else color:Lerp(Color3.new(0, 0, 0), 0.3)
				local left = egg:GetAttribute("TimeLeft") or 0
				r.Time.Text = if left <= 0 then "Hatching!" else Util.FormatTime(left)
				r.Fill.BackgroundColor3 = color:Lerp(Color3.fromRGB(120, 255, 140), 0.35)
				r.Fill.Size = UDim2.fromScale(egg:GetAttribute("Progress") or 0, 1)
			end
		end
		more.Visible = #mine > MAX_ROWS and not folded
		more.Text = "+" .. (#mine - MAX_ROWS) .. " more in your pen"
	end
	task.spawn(function()
		while true do
			refresh()
			task.wait(0.5)
		end
	end)
end
setupIncubator()

-- 3D previews, hatch reveal, pet details, clock badge, title screen and
-- console controls. In their own function to stay under Luau's local limit.
local function setupExtraGui()
	--------------------------------------------------------------------------------
	-- 3D pet previews: builds the real pet model inside a ViewportFrame and spins it
	--------------------------------------------------------------------------------
	local Visuals = require(Shared:WaitForChild("Visuals"))
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local ContextActionService = game:GetService("ContextActionService")
	local RenderStepped = game:GetService("RunService").RenderStepped

	local function petViewport(parent, data, silhouette)
		local vp = Instance.new("ViewportFrame")
		vp.Name = "PetPreview"
		vp.BackgroundTransparency = 1
		vp.Size = UDim2.fromScale(1, 1)
		vp.Ambient = if silhouette then Color3.fromRGB(40, 36, 60) else Color3.fromRGB(175, 175, 190)
		vp.LightColor = Color3.fromRGB(255, 250, 240)
		vp.LightDirection = Vector3.new(-0.5, -1, -0.8)
		local ok, model = pcall(Visuals.MakeCreature, data)
		if not ok or not model then
			vp.Parent = parent
			return vp, function() end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Sparkles") or d:IsA("PointLight") or d:IsA("Highlight") then
				d:Destroy()
			elseif silhouette and d:IsA("BasePart") then
				d.Color = Color3.fromRGB(22, 20, 34)
				d.Material = Enum.Material.SmoothPlastic
			end
		end
		model.Parent = vp
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.Parent = vp
		vp.CurrentCamera = camera
		local center, size = model:GetBoundingBox()
		local dist = size.Magnitude * 1.35
		local angle = math.rad(-25)
		local function place()
			local offset = Vector3.new(math.sin(angle), 0.32, -math.cos(angle)) * dist
			camera.CFrame = CFrame.lookAt(center.Position + offset, center.Position)
		end
		place()
		local conn = RenderStepped:Connect(function(dt)
			angle += dt * 0.9
			place()
		end)
		vp.Parent = parent
		return vp, function()
			conn:Disconnect()
			vp:Destroy()
		end
	end

	local function whereToFind(rarityId)
		local zones = {}
		for _, biome in ipairs(Config.Biomes) do
			if (biome.Eggs[rarityId] or 0) > 0 then
				table.insert(zones, biome.Name)
			end
		end
		if (Config.EggRainWeights[rarityId] or 0) > 0 then
			table.insert(zones, "Egg Rain")
		end
		return if #zones > 0 then table.concat(zones, ", ") else "???"
	end

	--------------------------------------------------------------------------------
	-- Hatch reveal: a big card with the new pet spinning in 3D
	--------------------------------------------------------------------------------
	local HatchedRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Hatched")

	local reveal = Instance.new("TextButton") -- click / tap / A anywhere on it to dismiss
	reveal.Name = "HatchReveal"
	juiced[reveal] = true -- has its own gradient and pop animation
	reveal.Text = ""
	reveal.AutoButtonColor = false
	reveal.AnchorPoint = Vector2.new(0.5, 0.5)
	reveal.Position = UDim2.fromScale(0.5, 0.48)
	reveal.Size = UDim2.fromOffset(340, 430)
	reveal.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	reveal.ZIndex = 8
	reveal.Visible = false
	reveal.Parent = gui
	corner(reveal, 22)
	local revealStroke = Instance.new("UIStroke")
	revealStroke.Thickness = 5
	revealStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	revealStroke.Parent = reveal
	local revealGradient = Instance.new("UIGradient")
	revealGradient.Rotation = 90
	revealGradient.Parent = reveal
	local revealScale = Instance.new("UIScale")
	revealScale.Parent = reveal

	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.new(0.5, 0, 0, 170)
	rays.Size = UDim2.fromOffset(10, 10)
	rays.Rotation = 0
	rays.Parent = reveal
	local rayParts = {}
	for i = 0, 7 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(26, 300)
		ray.Rotation = i * 22.5
		ray.BackgroundTransparency = 0.82
		ray.BorderSizePixel = 0
		ray.Parent = rays
		table.insert(rayParts, ray)
	end
	local revealNew = label(reveal, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 34), Text = "✨ NEW PET! ✨", TextColor3 = Color3.fromRGB(255, 230, 110) })
	local revealStage = Instance.new("Frame")
	revealStage.BackgroundTransparency = 1
	revealStage.Position = UDim2.fromOffset(20, 52)
	revealStage.Size = UDim2.new(1, -40, 0, 236)
	revealStage.Parent = reveal
	local revealName = label(reveal, { Position = UDim2.fromOffset(14, 292), Size = UDim2.new(1, -28, 0, 40), Text = "" })
	local revealRarity = label(reveal, { Position = UDim2.fromOffset(14, 332), Size = UDim2.new(1, -28, 0, 26), Font = Enum.Font.GothamBold, Text = "" })
	local revealStats = label(reveal, { Position = UDim2.fromOffset(14, 362), Size = UDim2.new(1, -28, 0, 22), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(150, 255, 160), Text = "" })
	local revealHint = label(reveal, { Position = UDim2.fromOffset(14, 396), Size = UDim2.new(1, -28, 0, 18), Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(200, 200, 215), TextStrokeTransparency = 1, Text = "Tap to continue" })

	local revealQueue = {}
	local revealing = false
	local stopRevealModel = nil
	local revealToken = 0

	--------------------------------------------------------------------------------
	-- Egg opening: before the pet card, the egg drops in, shakes three times
	-- (harder each time) as cracks spread and its glow grows, then bursts open in
	-- a flash with flying shell pieces (and confetti for rare pets). Rarer eggs
	-- take a little longer. Tap anywhere to skip.
	--------------------------------------------------------------------------------
	local playOpening
	do
		local overlay = Instance.new("TextButton")
		overlay.Name = "EggOpening"
		juiced[overlay] = true
		overlay.Text = ""
		overlay.AutoButtonColor = false
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.fromRGB(8, 6, 16)
		overlay.BackgroundTransparency = 1
		overlay.BorderSizePixel = 0
		overlay.ZIndex = 30
		overlay.Visible = false
		overlay.Parent = gui

		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.47)
		glow.Size = UDim2.fromOffset(160, 160)
		glow.BackgroundTransparency = 0.55
		glow.BorderSizePixel = 0
		glow.ZIndex = 31
		glow.Parent = overlay
		corner(glow, 999)
		local openRays = Instance.new("Frame")
		openRays.BackgroundTransparency = 1
		openRays.AnchorPoint = Vector2.new(0.5, 0.5)
		openRays.Position = UDim2.fromScale(0.5, 0.47)
		openRays.Size = UDim2.fromOffset(10, 10)
		openRays.ZIndex = 31
		openRays.Parent = overlay
		local openRayParts = {}
		for i = 0, 11 do
			local ray = Instance.new("Frame")
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.fromOffset(22, 520)
			ray.Rotation = i * 15
			ray.BackgroundTransparency = 1
			ray.BorderSizePixel = 0
			ray.ZIndex = 31
			ray.Parent = openRays
			table.insert(openRayParts, ray)
		end

		local stage = Instance.new("ViewportFrame")
		stage.Name = "EggStage"
		stage.AnchorPoint = Vector2.new(0.5, 0.5)
		stage.Position = UDim2.fromScale(0.5, 0.47)
		stage.Size = UDim2.fromOffset(260, 300)
		stage.BackgroundTransparency = 1
		stage.Ambient = Color3.fromRGB(180, 175, 195)
		stage.LightColor = Color3.fromRGB(255, 250, 240)
		stage.LightDirection = Vector3.new(-0.5, -1, -0.8)
		stage.ZIndex = 32
		stage.Parent = overlay
		local stageCam = Instance.new("Camera")
		stageCam.FieldOfView = 30
		stageCam.Parent = stage
		stage.CurrentCamera = stageCam

		local caption = label(overlay, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.75), Size = UDim2.fromOffset(420, 44), ZIndex = 33, Text = "" })
		local skipHint = label(overlay, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(300, 20), Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(190, 185, 210), TextStrokeTransparency = 1, ZIndex = 33, Text = "Tap to skip" })
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.BackgroundTransparency = 1
		flash.BorderSizePixel = 0
		flash.ZIndex = 36
		flash.Parent = overlay

		local skipped = false
		overlay.Activated:Connect(function()
			skipped = true
		end)

		local spinRays = false
		RenderStepped:Connect(function(dt)
			if spinRays then
				openRays.Rotation = (openRays.Rotation + dt * 40) % 360
			end
		end)

		-- UI shell pieces and confetti flying out from the middle
		local function burstPieces(color, count, confetti)
			for i = 1, count do
				local piece = Instance.new("Frame")
				piece.AnchorPoint = Vector2.new(0.5, 0.5)
				piece.Position = UDim2.fromScale(0.5, 0.47)
				local w = if confetti then math.random(8, 14) else math.random(26, 46)
				piece.Size = UDim2.fromOffset(w, if confetti then w * 0.5 else math.random(18, 34))
				piece.BackgroundColor3 = if confetti then Color3.fromHSV(math.random(), 0.7, 1) else (if i % 3 == 0 then Color3.new(1, 1, 1) else color)
				piece.BorderSizePixel = 0
				piece.Rotation = math.random(0, 360)
				piece.ZIndex = 35
				piece.Parent = overlay
				if not confetti then
					corner(piece, 6)
				end
				local a = math.random() * math.pi * 2
				local dist = if confetti then math.random(260, 520) else math.random(180, 340)
				local target = UDim2.new(0.5, math.cos(a) * dist, 0.47, math.sin(a) * dist * 0.8 + (if confetti then 160 else 60))
				local t = if confetti then 1.4 else 0.8
				TweenService:Create(piece, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target, Rotation = piece.Rotation + math.random(-360, 360), BackgroundTransparency = 1 }):Play()
				task.delay(t + 0.05, function()
					piece:Destroy()
				end)
			end
		end

		-- Plays the opening for `data` (the hatched pet), then calls done().
		playOpening = function(data, done)
			local rarity = Config.RarityById[data.Rarity]
			local mutation = data.Mutation and Config.MutationById[data.Mutation]
			local color = if mutation then mutation.Color else rarity.Color
			local order = rarity.Order
			local pace = 1 + math.min(order, 8) * 0.06 -- rarer eggs take a little longer
			skipped = false

			-- the egg model, the same design as the one that hatched
			stage:ClearAllChildren()
			stageCam.Parent = stage
			local model = Instance.new("Model")
			local ok, egg = pcall(Visuals.MakeEgg, data.Rarity, data.EggVariant)
			if ok and egg then
				if mutation then
					pcall(Visuals.ApplyMutation, egg, data.Mutation)
				end
				for _, d in ipairs(egg:GetDescendants()) do
					if d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Sparkles") or d:IsA("PointLight") then
						d:Destroy()
					end
				end
				egg.Anchored = true
				egg.CFrame = CFrame.new()
				egg.Parent = model
				model.PrimaryPart = egg
				model.Parent = stage
				local _, size = model:GetBoundingBox()
				stageCam.CFrame = CFrame.lookAt(Vector3.new(0, size.Y * 0.1, -size.Magnitude * 2.6), Vector3.zero)
			end
			local function pose(cf)
				if model.PrimaryPart then
					model:PivotTo(cf)
				end
			end

			glow.BackgroundColor3 = color
			glow.Size = UDim2.fromOffset(120, 120)
			glow.BackgroundTransparency = 0.7
			for _, ray in ipairs(openRayParts) do
				ray.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3)
				ray.BackgroundTransparency = 1
			end
			local petSize = data.Size or 1
			caption.Text = if petSize >= Config.HugePetSize then "A HUGE egg is hatching..." elseif petSize >= Config.BigPetSize then "A BIG egg is hatching..." else "Hatching..."
			caption.TextColor3 = Color3.new(1, 1, 1)
			skipHint.Text = if UserInputService.GamepadEnabled then "Press Ⓐ to skip" else "Tap to skip"
			flash.BackgroundTransparency = 1
			stage.Position = UDim2.new(0.5, 0, 0.47, -400)
			overlay.BackgroundTransparency = 1
			overlay.Visible = true
			if UserInputService.GamepadEnabled then
				GuiService.SelectedObject = overlay
			end
			TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.3 }):Play()

			local function wait(seconds)
				local t0 = os.clock()
				while os.clock() - t0 < seconds do
					if skipped then
						return false
					end
					RenderStepped:Wait()
				end
				return not skipped
			end
			-- shake the egg for `seconds` at `strength` degrees, jiggling the stage too
			local function shake(seconds, strength)
				local t0 = os.clock()
				while os.clock() - t0 < seconds do
					if skipped then
						return false
					end
					local t = os.clock() - t0
					local s = strength * math.sin(t / seconds * math.pi)
					pose(CFrame.Angles(math.rad(math.sin(t * 38) * s * 0.4), 0, math.rad(math.sin(t * 45) * s)))
					stage.Position = UDim2.new(0.5, math.sin(t * 60) * s * 0.4, 0.47, 0)
					RenderStepped:Wait()
				end
				pose(CFrame.new())
				stage.Position = UDim2.fromScale(0.5, 0.47)
				return not skipped
			end

			task.spawn(function()
				local ok2 = true
				-- 1. drop in with a bounce
				TweenService:Create(stage, TweenInfo.new(0.45, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.47) }):Play()
				ok2 = wait(0.55)
				-- 2. three shakes, harder each time, with cracks and a growing glow
				for i = 1, 3 do
					if not ok2 then
						break
					end
					ok2 = shake(0.32 * pace, 10 + i * 8)
					if ok2 and egg and i <= 2 then
						pcall(Visuals.CrackEgg, egg, i, color)
					end
					TweenService:Create(glow, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(150 + i * 50, 150 + i * 50), BackgroundTransparency = 0.65 - i * 0.12 }):Play()
					if i == 2 then
						caption.Text = if order >= 5 then "Something rare is coming..." else "Almost there..."
						caption.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3)
						spinRays = true
						for _, ray in ipairs(openRayParts) do
							TweenService:Create(ray, TweenInfo.new(0.3), { BackgroundTransparency = 0.8 }):Play()
						end
					end
					ok2 = ok2 and wait(0.22 * pace)
				end
				-- 3. a last frantic wiggle, then it bursts
				if ok2 then
					ok2 = shake(0.4 * pace, 34)
				end
				flash.BackgroundTransparency = 0
				stage:ClearAllChildren()
				stageCam.Parent = stage
				burstPieces(color, 12, false)
				if order >= 4 or mutation or data.Shiny then
					burstPieces(color, 40, true)
				end
				TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(glow, TweenInfo.new(0.4), { Size = UDim2.fromOffset(900, 900), BackgroundTransparency = 1 }):Play()
				caption.Text = ""
				task.wait(0.12)
				-- 4. hand over to the pet card, fading the overlay out behind it
				done()
				TweenService:Create(overlay, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
				for _, ray in ipairs(openRayParts) do
					TweenService:Create(ray, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
				end
				task.wait(0.4)
				spinRays = false
				overlay.Visible = false
				if GuiService.SelectedObject == overlay then
					GuiService.SelectedObject = nil
				end
			end)
		end
	end

	local presentReveal
	local function showNextReveal()
		if revealing or #revealQueue == 0 then
			return
		end
		revealing = true
		revealToken += 1
		local token = revealToken
		local data = table.remove(revealQueue, 1)
		playOpening(data, function()
			if token == revealToken and revealing then
				presentReveal(data, token)
			end
		end)
	end

	presentReveal = function(data, token)
		local rarity = Config.RarityById[data.Rarity]
		local mutation = data.Mutation and Config.MutationById[data.Mutation]
		local color = if mutation then mutation.Color else rarity.Color
		revealGradient.Color = ColorSequence.new(color:Lerp(Color3.fromRGB(40, 30, 70), 0.55), Color3.fromRGB(22, 18, 36))
		revealStroke.Color = color
		for _, ray in ipairs(rayParts) do
			ray.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3)
		end
		revealNew.Visible = data.New == true
		revealName.Text = (if data.Shiny then "✨ " else "") .. Config.CreatureTitle(data)
		revealName.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		revealRarity.Text = rarity.Id:upper() .. (if mutation then "  ·  " .. mutation.Icon .. " " .. mutation.Id else "") .. (if (data.Size or 1) >= 2 then "  ·  HUGE" else "")
		revealRarity.TextColor3 = rarity.Color
		revealStats.Text = "+" .. Util.Money(Config.CreatureIncome(data)) .. "/s  ·  " .. string.format("%.1f kg", Config.PetWeight(data)) .. "  ·  grows up over time"
		revealHint.Text = if UserInputService.GamepadEnabled then "Press Ⓐ to continue" else "Tap to continue"
		if stopRevealModel then
			stopRevealModel()
		end
		local _, stop = petViewport(revealStage, data, false)
		stopRevealModel = stop
		reveal.Visible = true
		revealScale.Scale = 0.3
		TweenService:Create(revealScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = reveal
		end
		task.delay(if rarity.Order >= 5 then 5 else 3.2, function()
			if token == revealToken and revealing then
				reveal:SetAttribute("Dismiss", true)
			end
		end)
	end

	local function dismissReveal()
		if not revealing then
			return
		end
		revealing = false
		reveal.Visible = false
		if GuiService.SelectedObject == reveal then
			GuiService.SelectedObject = nil
		end
		if stopRevealModel then
			stopRevealModel()
			stopRevealModel = nil
		end
		task.delay(0.15, showNextReveal)
	end
	reveal.Activated:Connect(dismissReveal)
	reveal:GetAttributeChangedSignal("Dismiss"):Connect(function()
		if reveal:GetAttribute("Dismiss") then
			reveal:SetAttribute("Dismiss", nil)
			dismissReveal()
		end
	end)
	RenderStepped:Connect(function(dt)
		if reveal.Visible then
			rays.Rotation = (rays.Rotation + dt * 25) % 360
		end
	end)

	HatchedRemote.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" or not Config.RarityById[data.Rarity] then
			return
		end
		table.insert(revealQueue, data)
		-- hatching lots at once (Instant Hatch): keep only the 3 rarest
		if #revealQueue > 3 then
			table.sort(revealQueue, function(a, b)
				return Config.RarityById[a.Rarity].Order > Config.RarityById[b.Rarity].Order
			end)
			for i = #revealQueue, 4, -1 do
				table.remove(revealQueue, i)
			end
		end
		showNextReveal()
	end)

	--------------------------------------------------------------------------------
	-- Pet Index details: tap a pet to see it in 3D (a silhouette if not found yet)
	--------------------------------------------------------------------------------
	local detail = Instance.new("Frame")
	detail.Name = "PetDetail"
	detail.AnchorPoint = Vector2.new(0.5, 0.5)
	detail.Position = UDim2.fromScale(0.5, 0.5)
	detail.Size = UDim2.fromOffset(330, 420)
	detail.BackgroundColor3 = Color3.fromRGB(28, 24, 44)
	detail.ZIndex = 20
	detail.Visible = false
	detail.Parent = indexPanel
	corner(detail, 18)
	local detailStroke = Instance.new("UIStroke")
	detailStroke.Thickness = 4
	detailStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	detailStroke.Parent = detail
	local detailStage = Instance.new("Frame")
	detailStage.BackgroundColor3 = Color3.fromRGB(45, 40, 70)
	detailStage.Position = UDim2.fromOffset(16, 16)
	detailStage.Size = UDim2.new(1, -32, 0, 210)
	detailStage.Parent = detail
	corner(detailStage, 14)
	local detailName = label(detail, { Position = UDim2.fromOffset(16, 234), Size = UDim2.new(1, -32, 0, 36), Text = "" })
	local detailRarity = label(detail, { Position = UDim2.fromOffset(16, 270), Size = UDim2.new(1, -32, 0, 22), Font = Enum.Font.GothamBold, Text = "" })
	local detailInfo = label(detail, { Position = UDim2.fromOffset(20, 298), Size = UDim2.new(1, -40, 0, 64), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(225, 225, 240), TextStrokeTransparency = 1, TextWrapped = true, Text = "" })
	detailInfo.TextScaled = false
	detailInfo.TextSize = 15
	detailInfo.TextYAlignment = Enum.TextYAlignment.Top
	local detailClose = Instance.new("TextButton")
	detailClose.AnchorPoint = Vector2.new(0.5, 1)
	detailClose.Position = UDim2.new(0.5, 0, 1, -14)
	detailClose.Size = UDim2.fromOffset(160, 42)
	detailClose.BackgroundColor3 = Color3.fromRGB(90, 140, 240)
	detailClose.Font = Enum.Font.FredokaOne
	detailClose.TextScaled = true
	detailClose.Text = "Back"
	detailClose.TextColor3 = Color3.new(1, 1, 1)
	detailClose.Parent = detail
	corner(detailClose, 12)
	local detailPad = Instance.new("UIPadding")
	detailPad.PaddingTop = UDim.new(0, 7)
	detailPad.PaddingBottom = UDim.new(0, 7)
	detailPad.Parent = detailClose

	local stopDetailModel = nil
	local lastTile = nil
	local function closeDetail()
		detail.Visible = false
		if stopDetailModel then
			stopDetailModel()
			stopDetailModel = nil
		end
		if UserInputService.GamepadEnabled and lastTile and indexPanel.Visible then
			GuiService.SelectedObject = lastTile
		end
	end
	detailClose.Activated:Connect(closeDetail)

	local function openDetail(def, hit)
		lastTile = hit
		local folder = player:FindFirstChild("PetIndex")
		local found = folder ~= nil and folder:FindFirstChild(def.Name) ~= nil
		local rarity = Config.RarityById[def.Rarity]
		detailStroke.Color = rarity.Color
		detailName.Text = if found then def.Name else "???"
		detailName.TextColor3 = if found then rarity.Color:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.fromRGB(160, 155, 185)
		detailRarity.Text = rarity.Id:upper() .. (if found then "  ·  ✅ Collected" else "  ·  Not found yet")
		detailRarity.TextColor3 = rarity.Color
		local lines = { "💰 Earns +" .. Util.Money(def.Income * Config.IncomeMultiplier * Config.Stages[1].Mult) .. "/s as a baby (up to " .. Util.Money(def.Income * Config.IncomeMultiplier * Config.Stages[#Config.Stages].Mult) .. "/s grown)" }
		table.insert(lines, "🥚 Found in: " .. whereToFind(def.Rarity))
		if found and (def.Pattern or def.Accessory) then
			table.insert(lines, "🎨 " .. (def.Pattern or "") .. (if def.Pattern and def.Accessory then " · " else "") .. (def.Accessory or ""))
		end
		detailInfo.Text = table.concat(lines, "\n")
		if stopDetailModel then
			stopDetailModel()
		end
		local _, stop = petViewport(detailStage, { Name = def.Name, Rarity = def.Rarity, Tier = 1, Size = 1, Age = 1e9 }, not found)
		stopDetailModel = stop
		detail.Visible = true
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = detailClose
		end
	end

	for _, tile in pairs(indexTiles) do
		local hit = Instance.new("TextButton")
		hit.Name = "Open"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 3
		hit.Parent = tile.Frame
		hit.Activated:Connect(function()
			openDetail(tile.Def, hit)
		end)
	end
	indexPanel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not indexPanel.Visible then
			closeDetail()
		end
	end)

	--------------------------------------------------------------------------------
	-- Top-left badge: time of day and the zone you're in
	--------------------------------------------------------------------------------
	local infoChip = Instance.new("Frame")
	infoChip.Name = "InfoChip"
	infoChip.Position = UDim2.fromOffset(14, 8)
	infoChip.Size = UDim2.fromOffset(230, 58)
	infoChip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	infoChip.Parent = gui
	corner(infoChip, 14)
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Thickness = 2.5
	chipStroke.Color = Color3.fromRGB(255, 240, 200)
	chipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	chipStroke.Parent = infoChip
	local chipGradient = Instance.new("UIGradient")
	chipGradient.Color = ColorSequence.new(Color3.fromRGB(58, 46, 92), Color3.fromRGB(24, 20, 38))
	chipGradient.Rotation = 90
	chipGradient.Parent = infoChip
	local timeLabel = label(infoChip, { Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 230, 140), Text = "☀️ 3:00 PM" })
	local zoneLabel = label(infoChip, { Position = UDim2.fromOffset(12, 31), Size = UDim2.new(1, -24, 0, 20), Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Text = "🏠 Town" })

	local function refreshZoneChip()
		zoneLabel.Text = gui:GetAttribute("ZoneName") or "🏠 Town"
		local c = gui:GetAttribute("ZoneColor")
		zoneLabel.TextColor3 = if typeof(c) == "Color3" then c else Color3.new(1, 1, 1)
		chipStroke.Color = if typeof(c) == "Color3" then c else Color3.fromRGB(255, 240, 200)
	end
	gui:GetAttributeChangedSignal("ZoneName"):Connect(refreshZoneChip)
	refreshZoneChip()

	task.spawn(function()
		while true do
			local clock = clockTime
			local h = math.floor(clock)
			local m = math.floor((clock - h) * 60)
			local icon = if clock >= 7.5 and clock < 17 then "☀️" elseif (clock >= 5 and clock < 7.5) or (clock >= 17 and clock < 19.5) then "🌅" else "🌙"
			timeLabel.Text = string.format("%s %d:%02d %s", icon, (h + 11) % 12 + 1, m, if h < 12 then "AM" else "PM")
			task.wait(0.5)
		end
	end)

	--------------------------------------------------------------------------------
	-- Title screen when you join
	--------------------------------------------------------------------------------
	local splash = Instance.new("Frame")
	splash.Name = "TitleScreen"
	splash.Size = UDim2.new(1, 0, 1, 80)
	splash.Position = UDim2.fromOffset(0, -80)
	splash.BackgroundColor3 = Color3.new(1, 1, 1)
	splash.ZIndex = 30
	splash.Parent = gui
	local splashGradient = Instance.new("UIGradient")
	splashGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 50, 130)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(35, 25, 70)), ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 15, 40)) })
	splashGradient.Rotation = 90
	splashGradient.Parent = splash
	local eggRow = label(splash, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(420, 80), Text = "🥚 🐣 🥚", TextStrokeTransparency = 1 })
	local splashTitle = label(splash, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(640, 100), Text = "STEAL A PET EGG", TextColor3 = Color3.fromRGB(255, 220, 90), TextStrokeTransparency = 0 })
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 4
	titleStroke.Color = Color3.fromRGB(120, 60, 20)
	titleStroke.Parent = splashTitle
	label(splash, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.fromOffset(560, 30), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 215, 240), Text = "Grab eggs · Outrun guardians · Hatch 499 pets" })
	local playButton = Instance.new("TextButton")
	playButton.Name = "PlayButton"
	playButton.AnchorPoint = Vector2.new(0.5, 0.5)
	playButton.Position = UDim2.fromScale(0.5, 0.7)
	playButton.Size = UDim2.fromOffset(260, 74)
	playButton.BackgroundColor3 = Color3.fromRGB(90, 220, 80)
	playButton.Font = Enum.Font.FredokaOne
	playButton.TextScaled = true
	playButton.Text = "▶ PLAY"
	playButton.TextColor3 = Color3.new(1, 1, 1)
	playButton.TextStrokeTransparency = 0.2
	playButton.Parent = splash
	corner(playButton, 18)
	stroke(playButton, 4, Color3.fromRGB(30, 100, 30))
	local playPad = Instance.new("UIPadding")
	playPad.PaddingTop = UDim.new(0, 12)
	playPad.PaddingBottom = UDim.new(0, 12)
	playPad.Parent = playButton
	local splashHint = label(splash, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromOffset(400, 22), Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(190, 185, 215), TextStrokeTransparency = 1, Text = "" })

	task.spawn(function()
		local t = 0
		while splash.Parent do
			t += task.wait(0.03)
			eggRow.Rotation = math.sin(t * 2) * 6
			eggRow.Position = UDim2.fromScale(0.5, 0.3 + math.sin(t * 3) * 0.01)
		end
	end)

	local function closeSplash()
		if not splash.Parent then
			return
		end
		if GuiService.SelectedObject == playButton then
			GuiService.SelectedObject = nil
		end
		local fade = TweenInfo.new(0.5)
		for _, d in ipairs(splash:GetDescendants()) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				TweenService:Create(d, fade, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, fade, { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(splash, fade, { BackgroundTransparency = 1 }):Play()
		task.delay(0.55, function()
			splash:Destroy()
		end)
	end
	playButton.Activated:Connect(closeSplash)

	--------------------------------------------------------------------------------
	-- Console / gamepad controls
	--   View (Back) button  open the side menu so the D-pad can move through it
	--   Y                   Daily Rewards
	--   B                   close whatever is open (menus, pet details, reveal, treadmill)
	--   A                   press the highlighted button
	-- Walking, holding X to grab eggs and R2 to swing the Bonk Bat are Roblox defaults.
	--------------------------------------------------------------------------------
	-- Gold highlight around the selected button
	local selection = Instance.new("Frame")
	selection.Name = "GamepadSelection"
	selection.BackgroundTransparency = 1
	selection.Size = UDim2.fromScale(1, 1)
	local selectionStroke = Instance.new("UIStroke")
	selectionStroke.Thickness = 4
	selectionStroke.Color = Color3.fromRGB(255, 215, 80)
	selectionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	selectionStroke.Parent = selection
	corner(selection, 12)
	pcall(function()
		player.PlayerGui.SelectionImageObject = selection
	end)
	task.spawn(function()
		while true do
			selectionStroke.Transparency = 0.15 + math.abs(math.sin(os.clock() * 3)) * 0.35
			task.wait(0.05)
		end
	end)
	for _, name in ipairs({ "Backdrop" }) do
		local b = gui:FindFirstChild(name)
		if b then
			b.Selectable = false
		end
	end

	local function usingGamepad()
		local last = UserInputService:GetLastInputType()
		return last.Name:find("Gamepad") ~= nil
	end

	-- the main button of each menu, selected when it opens with a gamepad
	local function firstVisibleButton(root)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("TextButton") and d.Visible and d.Selectable and d.Name ~= "Backdrop" then
				local ok = true
				local p = d.Parent
				while p and p ~= root do
					if p:IsA("GuiObject") and not p.Visible then
						ok = false
						break
					end
					p = p.Parent
				end
				if ok then
					return d
				end
			end
		end
		return nil
	end
	local MENU_FOCUS = {
		[panel] = function()
			return firstVisibleButton(grid)
		end,
		[dailyPanel] = function()
			return claimButton
		end,
		[indexPanel] = function()
			return firstVisibleButton(indexList)
		end,
	}
	for menu, focus in pairs(MENU_FOCUS) do
		menu:GetPropertyChangedSignal("Visible"):Connect(function()
			if menu.Visible and usingGamepad() then
				task.defer(function()
					GuiService.SelectedObject = focus()
				end)
			end
		end)
	end

	local function anyMenuOpen()
		return panel.Visible or dailyPanel.Visible or indexPanel.Visible or adminPanel.Visible or reveal.Visible or detail.Visible
	end

	local function closeTop()
		if splash.Parent then
			closeSplash()
		elseif reveal.Visible then
			dismissReveal()
		elseif detail.Visible then
			closeDetail()
		elseif panel.Visible or dailyPanel.Visible or indexPanel.Visible then
			panel.Visible = false
			dailyPanel.Visible = false
			indexPanel.Visible = false
		elseif adminPanel.Visible then
			adminPanel.Visible = false
		elseif stopButton.Visible then
			stopTraining()
		else
			return false
		end
		GuiService.SelectedObject = nil
		return true
	end

	ContextActionService:BindActionAtPriority("EggMenuNav", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if splash.Parent then
			closeSplash()
		elseif GuiService.SelectedObject and not anyMenuOpen() then
			GuiService.SelectedObject = nil
		else
			GuiService.SelectedObject = dailyButton
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonSelect)

	ContextActionService:BindActionAtPriority("EggBack", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if closeTop() then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3000, Enum.KeyCode.ButtonB)

	ContextActionService:BindActionAtPriority("EggDaily", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or splash.Parent then
			return Enum.ContextActionResult.Pass
		end
		dailyPanel.Visible = not dailyPanel.Visible
		if not dailyPanel.Visible then
			GuiService.SelectedObject = nil
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonY)

	ContextActionService:BindActionAtPriority("EggStart", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and splash.Parent then
			closeSplash()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3000, Enum.KeyCode.ButtonStart, Enum.KeyCode.ButtonA)

	-- Button hints, only while a controller is being used
	local hints = label(gui, {
		Name = "GamepadHints",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(430, 30),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = Color3.fromRGB(24, 20, 38),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "  ⧉ View: menu   Ⓨ Daily   Ⓑ Close   Ⓧ Grab   R2 Bonk",
		Visible = false,
	})
	corner(hints, 10)
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingTop = UDim.new(0, 5)
	hintPad.PaddingBottom = UDim.new(0, 5)
	hintPad.Parent = hints
	local function refreshInputHints()
		local pad = usingGamepad()
		hints.Visible = pad
		splashHint.Text = if pad then "Press Ⓐ or Start to play" else ""
		revealHint.Text = if pad then "Press Ⓐ to continue" else "Tap to continue"
	end
	UserInputService.LastInputTypeChanged:Connect(refreshInputHints)
	refreshInputHints()
	if usingGamepad() then
		GuiService.SelectedObject = playButton
	end
end
setupExtraGui()

-- Treat Shop and Egg Facts: opened from the two market stalls in town.
local function setupStalls()
	local Visuals = require(Shared:WaitForChild("Visuals"))
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local ContextActionService = game:GetService("ContextActionService")
	local TreatsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Treats")

	-- A panel in the same style as the Shop: gradient, colored border, title, X
	local function makePanel(name, title, accent, width, height)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.52)
		frame.Size = UDim2.fromOffset(width, height)
		frame.BackgroundColor3 = Color3.fromRGB(34, 30, 52)
		frame.ZIndex = 5
		frame.Visible = false
		frame.Parent = gui
		corner(frame, 20)
		stroke(frame, 4, accent)
		panelGradient:Clone().Parent = frame
		local scale = Instance.new("UIScale")
		scale.Parent = frame
		label(frame, { Position = UDim2.fromOffset(24, 10), Size = UDim2.new(1, -110, 0, 48), Text = title, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.3) })
		local close = closeButton:Clone()
		close.Parent = frame
		close.Activated:Connect(function()
			frame.Visible = false
		end)
		local fit = 1
		local function refit()
			local camera = workspace.CurrentCamera
			if camera then
				local vp = camera.ViewportSize
				fit = math.min(1, (vp.X - 40) / width, (vp.Y - 60) / height)
				scale.Scale = fit
			end
		end
		refit()
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
		end
		frame:GetPropertyChangedSignal("Visible"):Connect(function()
			if frame.Visible then
				scale.Scale = 0.7 * fit
				TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
				for _, other in ipairs(menuPanels) do
					if other ~= frame then
						other.Visible = false
					end
				end
			end
			refreshBackdrop()
		end)
		table.insert(menuPanels, frame)
		return frame
	end

	------------------------------------------------------------------------
	-- 🍦 Treat Shop
	------------------------------------------------------------------------
	local treatPanel = makePanel("TreatShop", "🍦 TREAT SHOP", Color3.fromRGB(255, 140, 190), 760, 430)
	label(treatPanel, {
		Position = UDim2.fromOffset(26, 58),
		Size = UDim2.new(1, -52, 0, 20),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(230, 225, 240),
		TextStrokeTransparency = 1,
		Text = "Treats make your pets grow up faster and earn a bit more. One at a time; the same treat again adds time.",
	})
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(20, 92)
	row.Size = UDim2.new(1, -40, 0, 316)
	row.Parent = treatPanel
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 12)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	local treatCards = {}
	for i, treat in ipairs(Config.Treats) do
		local card = Instance.new("Frame")
		card.LayoutOrder = i
		card.Size = UDim2.fromOffset(170, 316)
		card.BackgroundColor3 = Color3.new(1, 1, 1)
		card.Parent = row
		corner(card, 16)
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = treat.Color
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Parent = card
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(treat.Color:Lerp(Color3.new(0, 0, 0), 0.35), treat.Color:Lerp(Color3.new(0, 0, 0), 0.75))
		g.Rotation = 90
		g.Parent = card
		label(card, { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 70), Text = treat.Icon, TextStrokeTransparency = 1 })
		label(card, { Position = UDim2.fromOffset(8, 84), Size = UDim2.new(1, -16, 0, 30), Text = treat.Name })
		local stats = label(card, { Position = UDim2.fromOffset(10, 118), Size = UDim2.new(1, -20, 0, 76), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(235, 235, 245), TextStrokeTransparency = 1, TextWrapped = true, Text = "🌱 Grow " .. treat.Growth .. "x faster\n💰 +" .. math.floor(treat.Cash * 100 + 0.5) .. "% cash\n⏱ " .. treat.Minutes .. " minutes" })
		stats.TextScaled = false
		stats.TextSize = 16
		local status = label(card, { Position = UDim2.fromOffset(8, 200), Size = UDim2.new(1, -16, 0, 26), TextColor3 = Color3.fromRGB(150, 255, 160), Text = "" })
		local buy = Instance.new("TextButton")
		buy.Name = "BuyTreat"
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.new(0.5, 0, 1, -14)
		buy.Size = UDim2.new(1, -24, 0, 50)
		buy.BackgroundColor3 = Color3.fromRGB(80, 210, 90)
		buy.Font = Enum.Font.FredokaOne
		buy.TextScaled = true
		buy.TextColor3 = Color3.new(1, 1, 1)
		buy.TextStrokeTransparency = 0.3
		buy.Text = "$" .. treat.MinCost
		buy.Parent = card
		corner(buy, 12)
		stroke(buy, 3, Color3.fromRGB(30, 100, 30))
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = buy
		buy.Activated:Connect(function()
			TreatsRemote:FireServer("Buy", treat.Key)
		end)
		treatCards[treat.Key] = { Buy = buy, Status = status, Stroke = cardStroke, Treat = treat }
	end

	-- HUD timer while a treat is active
	local treatChip = label(gui, {
		Name = "TreatTimer",
		Position = UDim2.fromOffset(14, 74),
		Size = UDim2.fromOffset(230, 30),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(26, 22, 40),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Text = "",
	})
	corner(treatChip, 12)
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Thickness = 2
	chipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	chipStroke.Parent = treatChip
	local chipPad = Instance.new("UIPadding")
	chipPad.PaddingLeft = UDim.new(0, 10)
	chipPad.PaddingTop = UDim.new(0, 5)
	chipPad.PaddingBottom = UDim.new(0, 5)
	chipPad.Parent = treatChip

	local function refreshTreats()
		local key = player:GetAttribute("TreatKey")
		local untilTime = player:GetAttribute("TreatUntil") or 0
		local left = untilTime - workspace:GetServerTimeNow()
		local active = key and left > 0 and Config.TreatByKey[key]
		local income = player:GetAttribute("IncomePerSec") or 0
		for k, c in pairs(treatCards) do
			c.Buy.Text = Util.Money(Config.TreatCost(c.Treat, income))
			local isActive = active and k == key
			c.Status.Text = if isActive then "ACTIVE " .. Util.FormatTime(left) else ""
			c.Stroke.Thickness = if isActive then 5 else 3
		end
		if active then
			treatChip.Visible = true
			treatChip.Text = active.Icon .. " " .. active.Growth .. "x grow · +" .. math.floor(active.Cash * 100 + 0.5) .. "% · " .. Util.FormatTime(left)
			treatChip.TextColor3 = active.Color:Lerp(Color3.new(1, 1, 1), 0.4)
			chipStroke.Color = active.Color
		else
			treatChip.Visible = false
		end
	end
	task.spawn(function()
		while true do
			refreshTreats()
			task.wait(0.5)
		end
	end)

	------------------------------------------------------------------------
	-- 🥚 Egg Facts
	------------------------------------------------------------------------
	local EGG_FUN_FACTS = {
		Common = "The easiest eggs to grab. The Bramble Bear is slow, so these are perfect for beginners.",
		Uncommon = "Leafy shells! Found in the forest and the dunes. Great for filling your Index early on.",
		Rare = "Rare eggs glow and can hatch into sharks, tigers and robots.",
		Epic = "Crystal shells. Epic pets earn over 200x more than Commons.",
		Legendary = "Golden eggs with wings. Guardians get fast here, so train your Speed first!",
		Mythic = "Cosmic eggs with their own orbiting stars. Found past Magma Crater, and most common in the Sunken Reef.",
		Divine = "Holy eggs with halos. Over half the eggs in Celestial Heights are Divine!",
		Secret = "The rarest eggs in the game. Most common in Jungle Ruins, Crystal Caverns and Toy Town. Nobody knows what's inside until it hatches!",
		Astral = "Starlit eggs from Jungle Ruins and beyond. Astral pets earn millions every second!",
		Cosmic = "Galaxy eggs that swirl with stars. Found from Toy Town onward, and each pet earns tens of millions per second.",
		Omega = "The most powerful eggs of all, cracked with red light. Only in Sakura Gardens and past it; Omega pets earn hundreds of millions per second.",
	}

	local factsPanel = makePanel("EggFacts", "🥚 EGG FACTS", Color3.fromRGB(255, 200, 90), 780, 490)
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(20, 66)
	list.Size = UDim2.new(1, -30, 1, -78)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = factsPanel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local function spawnsText(rarityId)
		local parts = {}
		for _, biome in ipairs(Config.Biomes) do
			local weight = biome.Eggs[rarityId] or 0
			if weight > 0 then
				local total = 0
				for _, w in pairs(biome.Eggs) do
					total += w
				end
				local pct = weight / total * 100
				table.insert(parts, biome.Name .. " (" .. (if pct < 1 then string.format("%.1f", pct) else tostring(math.floor(pct + 0.5))) .. "%)")
			end
		end
		if (Config.EggRainWeights[rarityId] or 0) > 0 then
			table.insert(parts, "🌧️ Egg Rain")
		end
		return table.concat(parts, ", ")
	end

	local eggStages = {}
	for order, rarity in ipairs(Config.Rarities) do
		local rowFrame = Instance.new("Frame")
		rowFrame.LayoutOrder = order
		rowFrame.Size = UDim2.new(1, -10, 0, 128)
		rowFrame.BackgroundColor3 = Color3.fromRGB(48, 42, 72)
		rowFrame.Parent = list
		corner(rowFrame, 14)
		stroke(rowFrame, 2, rarity.Color)
		local stage = Instance.new("Frame")
		stage.BackgroundColor3 = Color3.fromRGB(30, 26, 46)
		stage.Position = UDim2.fromOffset(10, 10)
		stage.Size = UDim2.fromOffset(108, 108)
		stage.Parent = rowFrame
		corner(stage, 12)
		eggStages[rarity.Id] = stage
		local minIncome, maxIncome = math.huge, 0
		for _, def in ipairs(rarity.Creatures) do
			minIncome = math.min(minIncome, def.Income)
			maxIncome = math.max(maxIncome, def.Income)
		end
		label(rowFrame, { Position = UDim2.fromOffset(130, 8), Size = UDim2.new(1, -140, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.2), Text = rarity.Id .. " Egg" })
		local info = label(rowFrame, {
			Position = UDim2.fromOffset(130, 38),
			Size = UDim2.new(1, -140, 0, 84),
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Color3.fromRGB(225, 225, 240),
			TextStrokeTransparency = 1,
			TextWrapped = true,
			Text = "⏱ Hatches in " .. Util.FormatTime(rarity.HatchTime) .. "   🐾 " .. #rarity.Creatures .. " pets   💰 " .. Util.Money(minIncome * Config.IncomeMultiplier * Config.Stages[1].Mult) .. " to " .. Util.Money(maxIncome * Config.IncomeMultiplier * Config.Stages[1].Mult) .. "/s as babies\n"
				.. "📍 Spawns in: " .. spawnsText(rarity.Id) .. "\n"
				.. "🎨 Looks: " .. table.concat(Visuals.EggVariantNames(rarity.Id), ", ") .. "\n"
				.. "💡 " .. (EGG_FUN_FACTS[rarity.Id] or ""),
		})
		info.TextScaled = false
		info.TextSize = 14
	end

	-- general facts at the bottom
	local mutationBits = {}
	for _, m in ipairs(Config.Mutations) do
		table.insert(mutationBits, m.Icon .. " " .. m.Id .. " " .. (m.Chance * 100) .. "% (" .. m.Mult .. "x)")
	end
	local footer = label(list, {
		LayoutOrder = 100,
		Size = UDim2.new(1, -10, 0, 150),
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.fromRGB(26, 22, 40),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextStrokeTransparency = 1,
		TextColor3 = Color3.fromRGB(230, 225, 245),
		TextWrapped = true,
		Text = "✨ Shiny: " .. math.floor(Config.ShinyChance * 100) .. "% of eggs hatch shiny, " .. math.floor(Config.StolenShinyChance * 100) .. "% if you stole the egg from another player. Shiny pets earn " .. Config.ShinyMultiplier .. "x.\n"
			.. "🧬 Mutations (rolled when an egg spawns): " .. table.concat(mutationBits, ", ") .. ". Server Luck makes them more common.\n"
			.. "🥚 Wild eggs regrow in their nests. The guardian chases you until you get far enough from its nest, and never past the red Safe Zone line.\n"
			.. "🏃 You run 10% slower while carrying an egg. Eggs in your base can be stolen unless you lock it.",
	})
	footer.TextScaled = false
	footer.TextSize = 14
	corner(footer, 12)
	local footerPad = Instance.new("UIPadding")
	footerPad.PaddingLeft = UDim.new(0, 12)
	footerPad.PaddingRight = UDim.new(0, 12)
	footerPad.PaddingTop = UDim.new(0, 10)
	footerPad.Parent = footer

	-- 3D eggs, built the first time the panel opens and spinning while it's open
	local eggModels = {}
	local spinConn = nil
	factsPanel:GetPropertyChangedSignal("Visible"):Connect(function()
		if factsPanel.Visible then
			if #eggModels == 0 then
				for rarityId, stage in pairs(eggStages) do
					local vp = Instance.new("ViewportFrame")
					vp.BackgroundTransparency = 1
					vp.Size = UDim2.fromScale(1, 1)
					vp.Ambient = Color3.fromRGB(180, 180, 195)
					vp.LightDirection = Vector3.new(-0.5, -1, -0.8)
					local ok, egg = pcall(Visuals.MakeEgg, rarityId, "Classic")
					if ok and egg then
						for _, d in ipairs(egg:GetDescendants()) do
							if d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("PointLight") then
								d:Destroy()
							end
						end
						egg.CFrame = CFrame.new()
						egg.Parent = vp
						local cam = Instance.new("Camera")
						cam.FieldOfView = 40
						cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.5, -9.5), Vector3.new(0, 0.2, 0))
						cam.Parent = vp
						vp.CurrentCamera = cam
						table.insert(eggModels, egg)
					end
					vp.Parent = stage
				end
			end
			spinConn = game:GetService("RunService").RenderStepped:Connect(function(dt)
				for _, egg in ipairs(eggModels) do
					egg.CFrame = egg.CFrame * CFrame.Angles(0, dt * 0.8, 0)
				end
			end)
		elseif spinConn then
			spinConn:Disconnect()
			spinConn = nil
		end
	end)

	------------------------------------------------------------------------
	-- Open them from the stall prompts
	------------------------------------------------------------------------
	local function hook(prompt)
		if prompt.Name == "TreatShopPrompt" then
			prompt.Triggered:Connect(function()
				treatPanel.Visible = true
			end)
		elseif prompt.Name == "EggFactsPrompt" then
			prompt.Triggered:Connect(function()
				factsPanel.Visible = true
			end)
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			hook(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			hook(d)
		end
	end)

	-- Controller: select the first treat when the shop opens; B closes both panels
	treatPanel:GetPropertyChangedSignal("Visible"):Connect(function()
		if treatPanel.Visible and UserInputService:GetLastInputType().Name:find("Gamepad") then
			task.defer(function()
				GuiService.SelectedObject = treatCards[Config.Treats[1].Key].Buy
			end)
		end
	end)
	ContextActionService:BindActionAtPriority("EggStallBack", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and (treatPanel.Visible or factsPanel.Visible) then
			treatPanel.Visible = false
			factsPanel.Visible = false
			GuiService.SelectedObject = nil
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3001, Enum.KeyCode.ButtonB)
end
setupStalls()

-- ⚙️ Settings and 🎟️ Codes: two small buttons under the side menu
local function setupSettingsAndCodes()
	local CodesRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Codes")

	local function makeMenu(name, title, accent, width, height)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromOffset(width, height)
		frame.BackgroundColor3 = Color3.fromRGB(34, 30, 52)
		frame.ZIndex = 5
		frame.Visible = false
		frame.Parent = gui
		corner(frame, 20)
		stroke(frame, 4, accent)
		panelGradient:Clone().Parent = frame
		local scale = Instance.new("UIScale")
		scale.Parent = frame
		label(frame, { Position = UDim2.fromOffset(24, 10), Size = UDim2.new(1, -110, 0, 46), Text = title, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.3) })
		local close = closeButton:Clone()
		close.Parent = frame
		close.Activated:Connect(function()
			frame.Visible = false
		end)
		frame:GetPropertyChangedSignal("Visible"):Connect(function()
			if frame.Visible then
				scale.Scale = 0.7
				TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				for _, other in ipairs(menuPanels) do
					if other ~= frame then
						other.Visible = false
					end
				end
			end
			refreshBackdrop()
		end)
		table.insert(menuPanels, frame)
		return frame
	end

	-- two small buttons side by side at the bottom of the side menu
	local row = Instance.new("Frame")
	row.Name = "SmallButtons"
	row.LayoutOrder = 10
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(160, 46)
	row.Parent = sideMenu
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = row
	sideMenu.Size = UDim2.fromOffset(160, 340)
	local function smallButton(text, color)
		local b = shopButton:Clone()
		b.Name = text
		b.Size = UDim2.fromOffset(76, 46)
		b.Text = text
		b.BackgroundColor3 = color
		b.Parent = row
		return b
	end
	local settingsButton = smallButton("⚙️", Color3.fromRGB(110, 110, 135))
	local codesButton = smallButton("🎟️", Color3.fromRGB(240, 110, 150))

	----------------------------------------------------------------------------
	-- Codes
	----------------------------------------------------------------------------
	local codesPanel = makeMenu("CodesPanel", "🎟️ CODES", Color3.fromRGB(240, 110, 150), 460, 270)
	label(codesPanel, { Position = UDim2.fromOffset(26, 58), Size = UDim2.new(1, -52, 0, 20), Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(225, 220, 240), TextStrokeTransparency = 1, Text = "Type a code for a free reward! Each code works once." })
	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.Position = UDim2.fromOffset(26, 92)
	box.Size = UDim2.new(1, -52, 0, 52)
	box.BackgroundColor3 = Color3.fromRGB(22, 20, 34)
	box.Font = Enum.Font.FredokaOne
	box.TextScaled = true
	box.PlaceholderText = "ENTER CODE"
	box.PlaceholderColor3 = Color3.fromRGB(120, 115, 145)
	box.Text = ""
	box.TextColor3 = Color3.new(1, 1, 1)
	box.ClearTextOnFocus = false
	box.Parent = codesPanel
	corner(box, 12)
	stroke(box, 2, Color3.fromRGB(240, 110, 150))
	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingTop = UDim.new(0, 10)
	boxPad.PaddingBottom = UDim.new(0, 10)
	boxPad.Parent = box
	local redeem = Instance.new("TextButton")
	redeem.Name = "Redeem"
	redeem.AnchorPoint = Vector2.new(0.5, 0)
	redeem.Position = UDim2.new(0.5, 0, 0, 156)
	redeem.Size = UDim2.fromOffset(200, 50)
	redeem.BackgroundColor3 = Color3.fromRGB(80, 210, 90)
	redeem.Font = Enum.Font.FredokaOne
	redeem.TextScaled = true
	redeem.Text = "REDEEM"
	redeem.TextColor3 = Color3.new(1, 1, 1)
	redeem.Parent = codesPanel
	corner(redeem, 12)
	stroke(redeem, 3, Color3.fromRGB(30, 100, 30))
	local rPad = Instance.new("UIPadding")
	rPad.PaddingTop = UDim.new(0, 8)
	rPad.PaddingBottom = UDim.new(0, 8)
	rPad.Parent = redeem
	local result = label(codesPanel, { Position = UDim2.fromOffset(20, 214), Size = UDim2.new(1, -40, 0, 28), Font = Enum.Font.GothamBold, Text = "" })
	local function send()
		if box.Text:gsub("%s", "") ~= "" then
			result.Text = "Checking..."
			result.TextColor3 = Color3.fromRGB(220, 220, 235)
			CodesRemote:FireServer(box.Text)
		end
	end
	redeem.Activated:Connect(send)
	box.FocusLost:Connect(function(enter)
		if enter then
			send()
		end
	end)
	CodesRemote.OnClientEvent:Connect(function(ok, message)
		result.Text = message
		result.TextColor3 = if ok then Color3.fromRGB(130, 255, 150) else Color3.fromRGB(255, 130, 130)
		if ok then
			box.Text = ""
		end
	end)
	codesButton.Activated:Connect(function()
		codesPanel.Visible = not codesPanel.Visible
		result.Text = ""
	end)

	----------------------------------------------------------------------------
	-- Settings (just for you, this session)
	----------------------------------------------------------------------------
	local settingsPanel = makeMenu("SettingsPanel", "⚙️ SETTINGS", Color3.fromRGB(150, 150, 190), 460, 340)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(24, 64)
	list.Size = UDim2.new(1, -48, 1, -76)
	list.Parent = settingsPanel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local settings = { Labels = true, Effects = true, AlwaysDay = false, SkyLife = true }
	local function applySettings()
		local pets = workspace:FindFirstChild("Pets")
		if pets then
			for _, d in ipairs(pets:GetDescendants()) do
				if d:IsA("BillboardGui") and d.Name == "Label" then
					d.Enabled = settings.Labels
				end
			end
		end
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Sparkles") or d:IsA("Fire") or d:IsA("Smoke") then
				if d:GetAttribute("WasEnabled") == nil then
					d:SetAttribute("WasEnabled", d.Enabled)
				end
				d.Enabled = settings.Effects and d:GetAttribute("WasEnabled")
			end
		end
		gui:SetAttribute("AlwaysDay", settings.AlwaysDay)
		local sky = workspace:FindFirstChild("SkyLife")
		if sky then
			for _, d in ipairs(sky:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = if settings.SkyLife then 0 else 1
				end
			end
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if not settings.Effects and (d:IsA("ParticleEmitter") or d:IsA("Sparkles") or d:IsA("Fire") or d:IsA("Smoke")) then
			d:SetAttribute("WasEnabled", d.Enabled)
			d.Enabled = false
		elseif not settings.Labels and d:IsA("BillboardGui") and d.Name == "Label" and d:FindFirstAncestor("Pets") then
			d.Enabled = false
		end
	end)

	local function toggleRow(order, key, title, sub)
		local r = Instance.new("Frame")
		r.LayoutOrder = order
		r.Size = UDim2.new(1, 0, 0, 52)
		r.BackgroundColor3 = Color3.fromRGB(48, 42, 72)
		r.Parent = list
		corner(r, 12)
		label(r, { Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -130, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, Text = title })
		local s2 = label(r, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -130, 0, 16), Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 195, 220), TextStrokeTransparency = 1, Text = sub })
		s2.TextScaled = false
		s2.TextSize = 13
		local b = Instance.new("TextButton")
		b.Name = "Toggle"
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -12, 0.5, 0)
		b.Size = UDim2.fromOffset(96, 36)
		b.Font = Enum.Font.FredokaOne
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = r
		corner(b, 18)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 6)
		pad.Parent = b
		local function show()
			b.Text = if settings[key] then "ON" else "OFF"
			b.BackgroundColor3 = if settings[key] then Color3.fromRGB(80, 200, 90) else Color3.fromRGB(110, 105, 130)
		end
		b.Activated:Connect(function()
			settings[key] = not settings[key]
			show()
			applySettings()
		end)
		show()
	end
	toggleRow(1, "Labels", "🏷️ Pet name tags", "Show names and income above pets")
	toggleRow(2, "Effects", "✨ Particle effects", "Turn off for smoother play on slow devices")
	toggleRow(3, "AlwaysDay", "☀️ Always daytime", "Skip night (only for you)")
	toggleRow(4, "SkyLife", "🎈 Balloons & birds", "Things flying around the sky")
	settingsButton.Activated:Connect(function()
		settingsPanel.Visible = not settingsPanel.Visible
	end)

	-- Controller: select the main button when a panel opens; B closes it
	local GuiService = game:GetService("GuiService")
	local UserInputService = game:GetService("UserInputService")
	local ContextActionService = game:GetService("ContextActionService")
	local firstToggle = list:FindFirstChildWhichIsA("Frame"):FindFirstChild("Toggle")
	for p, target in pairs({ [codesPanel] = box, [settingsPanel] = firstToggle }) do
		p:GetPropertyChangedSignal("Visible"):Connect(function()
			if p.Visible and UserInputService:GetLastInputType().Name:find("Gamepad") then
				task.defer(function()
					GuiService.SelectedObject = target
				end)
			end
		end)
	end
	ContextActionService:BindActionAtPriority("EggSettingsBack", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and (codesPanel.Visible or settingsPanel.Visible) then
			codesPanel.Visible = false
			settingsPanel.Visible = false
			GuiService.SelectedObject = nil
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3002, Enum.KeyCode.ButtonB)
end
setupSettingsAndCodes()


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
