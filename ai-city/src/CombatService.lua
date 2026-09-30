-- CombatService (ModuleScript) — ServerScriptService.Modules.CombatService
-- Weapons and fighting for players:
--   • the weapons shop at the Hardware store (a bat, a hammer, a knife)
--   • your weapons as tools in your hotbar (saved between visits)
--   • blocking (hold X / right mouse: you take a third of the damage)
--   • getting knocked out: you wake up at the hospital (wanted stars cleared,
--     a hospital bill), and the police confiscate your weapons when they arrest you
-- The attacks themselves (who you hit, witnesses, stars) are in CrimeService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapons"))

local CombatService = {}
local S
local blocking = {} -- [player] = true while blocking

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

--------------------------------------------------------------------------------
-- The weapons as Roblox tools (held in the right hand, blade/barrel pointing out)
--------------------------------------------------------------------------------
local function piece(tool, handle, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.CFrame = handle.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = handle, p
	weld.Parent = p
	p.Parent = tool
	return p
end

local BUILD = {}
BUILD.Bat = function(tool, handle)
	handle.Size = Vector3.new(0.3, 1.6, 0.3)
	handle.Color = rgb(60, 40, 30)
	piece(tool, handle, "Barrel", Vector3.new(0.5, 2.2, 0.5), CFrame.new(0, 1.8, 0), rgb(196, 150, 96), Enum.Material.Wood)
	piece(tool, handle, "Tip", Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, 2.9, 0), rgb(196, 150, 96), Enum.Material.Wood, Enum.PartType.Ball)
	piece(tool, handle, "Knob", Vector3.new(0.45, 0.2, 0.45), CFrame.new(0, -0.8, 0), rgb(40, 30, 24), Enum.Material.Wood)
	tool.Grip = CFrame.new(0, -0.3, 0)
end
BUILD.Hammer = function(tool, handle)
	handle.Size = Vector3.new(0.28, 2, 0.28)
	handle.Color = rgb(150, 105, 60)
	handle.Material = Enum.Material.Wood
	piece(tool, handle, "Head", Vector3.new(0.5, 0.5, 1.4), CFrame.new(0, 1.1, 0.1), rgb(90, 94, 100), Enum.Material.Metal)
	piece(tool, handle, "Claw", Vector3.new(0.3, 0.3, 0.6), CFrame.new(0, 1.2, -0.75) * CFrame.Angles(math.rad(25), 0, 0), rgb(90, 94, 100), Enum.Material.Metal)
	piece(tool, handle, "Grip", Vector3.new(0.34, 0.7, 0.34), CFrame.new(0, -0.6, 0), rgb(200, 40, 40), Enum.Material.Rubber)
	tool.Grip = CFrame.new(0, -0.5, 0)
end
BUILD.Knife = function(tool, handle)
	handle.Size = Vector3.new(0.22, 0.7, 0.3)
	handle.Color = rgb(30, 30, 34)
	handle.Material = Enum.Material.Rubber
	piece(tool, handle, "Guard", Vector3.new(0.3, 0.08, 0.5), CFrame.new(0, 0.38, 0), rgb(150, 150, 156), Enum.Material.Metal)
	piece(tool, handle, "Blade", Vector3.new(0.06, 1.1, 0.28), CFrame.new(0, 0.95, 0.02), rgb(215, 220, 228), Enum.Material.Metal)
	piece(tool, handle, "BladeTip", Vector3.new(0.06, 0.25, 0.16), CFrame.new(0, 1.55, 0.07) * CFrame.Angles(math.rad(-25), 0, 0), rgb(215, 220, 228), Enum.Material.Metal)
	tool.Grip = CFrame.new(0, -0.1, 0)
end

BUILD.Pistol = function(tool, handle)
	handle.Size = Vector3.new(0.3, 0.8, 0.4)
	handle.Color = rgb(34, 34, 38)
	handle.Material = Enum.Material.Metal
	piece(tool, handle, "Slide", Vector3.new(0.32, 0.34, 1.3), CFrame.new(0, 0.45, -0.35), rgb(50, 52, 58), Enum.Material.Metal)
	piece(tool, handle, "Barrel", Vector3.new(0.16, 0.16, 0.2), CFrame.new(0, 0.45, -1.05), rgb(20, 20, 22), Enum.Material.Metal)
	piece(tool, handle, "TriggerGuard", Vector3.new(0.08, 0.2, 0.4), CFrame.new(0, 0.12, -0.3), rgb(30, 30, 34), Enum.Material.Metal)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.45, -1.2)
	muzzle.Parent = handle
	-- held pointing forward (the grip is the handle; the barrel runs along -Z)
	tool.Grip = CFrame.new(0, -0.1, 0.1)
end
BUILD.Shotgun = function(tool, handle)
	handle.Size = Vector3.new(0.3, 0.6, 0.5)
	handle.Color = rgb(110, 70, 40)
	handle.Material = Enum.Material.Wood
	piece(tool, handle, "Stock", Vector3.new(0.34, 0.5, 1.4), CFrame.new(0, 0.1, 0.9), rgb(110, 70, 40), Enum.Material.Wood)
	piece(tool, handle, "Body", Vector3.new(0.34, 0.4, 1.1), CFrame.new(0, 0.3, -0.6), rgb(40, 40, 44), Enum.Material.Metal)
	piece(tool, handle, "Barrel", Vector3.new(0.2, 0.2, 2.2), CFrame.new(0, 0.42, -2.1), rgb(30, 30, 34), Enum.Material.Metal)
	piece(tool, handle, "Pump", Vector3.new(0.28, 0.24, 0.8), CFrame.new(0, 0.2, -1.9), rgb(110, 70, 40), Enum.Material.Wood)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.42, -3.2)
	muzzle.Parent = handle
	tool.Grip = CFrame.new(0, -0.1, 0.2)
end

function CombatService.MakeTool(id)
	local info = Weapons.List[id]
	if not info or not BUILD[id] then
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = info.Name
	tool.ToolTip = info.Emoji .. " " .. info.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Weapon", id)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = tool
	BUILD[id](tool, handle)
	return tool
end

-- Which weapon a player is holding ("Fists" if none)
function CombatService.Equipped(player)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("Weapon")
	return if id and Weapons.List[id] then id else "Fists"
end

local function giveTools(player)
	local pd = S.City.Data(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not pd or not backpack then
		return
	end
	for _, id in ipairs(Weapons.Order) do
		if pd.Weapons and pd.Weapons[id] then
			local name = Weapons.List[id].Name
			local has = backpack:FindFirstChild(name) or (player.Character and player.Character:FindFirstChild(name))
			if not has then
				local tool = CombatService.MakeTool(id)
				if tool then
					tool.Parent = backpack
				end
			end
		end
	end
end

-- The police take your weapons when you're arrested
function CombatService.Confiscate(player)
	local pd = S.City.Data(player)
	if not pd or not pd.Weapons or next(pd.Weapons) == nil then
		return
	end
	local names = {}
	for id in pairs(pd.Weapons) do
		table.insert(names, Weapons.List[id] and (Weapons.List[id].Emoji .. " " .. Weapons.List[id].Name) or id)
	end
	pd.Weapons = {}
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, tool in ipairs(container:GetChildren()) do
				if tool:IsA("Tool") and tool:GetAttribute("Weapon") then
					tool:Destroy()
				end
			end
		end
	end
	S.City.Toast(player, "🚔", "Weapons confiscated", "The police took your " .. table.concat(names, ", ") .. ".", rgb(230, 60, 60))
end

function CombatService.IsBlocking(player)
	return blocking[player] == true
end

--------------------------------------------------------------------------------
-- The shop
--------------------------------------------------------------------------------
local function shopData(player)
	local pd = S.City.Data(player)
	local items = {}
	for _, id in ipairs(Weapons.Order) do
		local w = Weapons.List[id]
		table.insert(items, { Id = id, Name = w.Name, Emoji = w.Emoji, Price = w.Price, Damage = w.Damage, Range = w.Range, Cooldown = w.Cooldown, Desc = w.Desc, Owned = pd and pd.Weapons and pd.Weapons[id] == true })
	end
	return items
end

local function buy(player, data)
	local pd = S.City.Data(player)
	local w = Weapons.List[data.Id or ""]
	if not pd or not w or w.Price <= 0 then
		return { Ok = false, Error = "That's not for sale." }
	end
	pd.Weapons = pd.Weapons or {}
	if pd.Weapons[data.Id] then
		return { Ok = false, Error = "You already have one." }
	end
	if S.Crime and S.Crime.IsJailed(player) then
		return { Ok = false, Error = "Not from jail!" }
	end
	if not S.City.Spend(player, w.Price, w.Emoji .. " Bought a " .. w.Name) then
		return { Ok = false, Error = "You need " .. w.Price .. " coins." }
	end
	-- the clerk rings it up (if someone is working the till)
	if S.Citizens and S.Citizens.ServePlayer then
		pcall(S.Citizens.ServePlayer, player, S.Map.Places.Hardware, "shop", 1)
	end
	pd.Weapons[data.Id] = true
	giveTools(player)
	return { Ok = true, Text = "You bought a " .. w.Name .. "! It's in your hotbar.", Items = shopData(player) }
end

local function addShop()
	local store = S.Map.Places.Hardware
	if not store then
		return
	end
	local counter = Instance.new("Part")
	counter.Name = "WeaponsShop"
	counter.Anchored = true
	counter.CanCollide = false
	counter.CanQuery = false
	counter.Transparency = 1
	counter.Size = Vector3.new(2, 2, 2)
	counter.CFrame = CFrame.new((store.Inside or store.Door) + Vector3.new(0, 3, 0))
	counter.Parent = store.Model or workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Buy weapons"
	prompt.ObjectText = "🔨 Hardware store"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Shop")
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		S.City.Send(player, { Type = "Shop", Items = shopData(player), Coins = S.City.Coins(player) })
	end)
end

--------------------------------------------------------------------------------
-- Health: getting knocked out and waking up at the hospital
--------------------------------------------------------------------------------
local function setupCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	blocking[player] = nil
	player:SetAttribute("Blocking", nil)
	-- woke up after being knocked out: in the hospital
	if player:GetAttribute("WakeAtHospital") then
		player:SetAttribute("WakeAtHospital", nil)
		local hospital = S.Map.Places.Hospital
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if hospital and root then
			task.wait(0.2)
			root.CFrame = CFrame.new((hospital.Inside or hospital.Door) + Vector3.new(0, 3.5, 0))
		end
		S.City.Toast(player, "🏥", "You woke up in the hospital", "The doctors patched you up.", rgb(90, 180, 220))
	end
	task.defer(giveTools, player)
	humanoid.Died:Connect(function()
		player:SetAttribute("WakeAtHospital", true)
		local bill = math.min(S.City.Coins(player), 30)
		if bill > 0 then
			S.City.AddCoins(player, -bill, "🏥 Hospital bill")
		end
		if S.Crime then
			S.Crime.ClearWanted(player)
		end
		S.City.Send(player, { Type = "Down", Bill = bill })
	end)
end

function CombatService.Start(services)
	S = services
	S.City.Handle("BuyWeapon", buy)
	S.City.Handle("Shop", function(player)
		return { Ok = true, Items = shopData(player), Coins = S.City.Coins(player) }
	end)
	S.City.Handle("Block", function(player, data)
		blocking[player] = data.On == true or nil
		player:SetAttribute("Blocking", blocking[player])
		if player.Character then
			player.Character:SetAttribute("Blocking", blocking[player])
		end
		return { Ok = true }
	end)
	addShop()
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
		if player.Character then
			task.spawn(setupCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		blocking[player] = nil
	end)
end

return CombatService
