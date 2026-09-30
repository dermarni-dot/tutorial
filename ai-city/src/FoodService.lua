-- FoodService (ModuleScript) — ServerScriptService.Modules.FoodService
-- Buy food at the city's food places: the Bakery, the Cafe, the Diner, the
-- Restaurant, the Ice Cream shop and the Market (press E at the counter).
-- You eat it right away: it heals you and refills stamina (see Shared.Food),
-- with a little eating animation everyone can see.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Food = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Food"))

local FoodService = {}
local S
local counters = {} -- [place id] = counter part

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function placeLabel(id)
	local info = Config.PlaceById and Config.PlaceById[id]
	return info and info.label or id
end

local function menu(player, placeId)
	local out = {}
	for _, id in ipairs(Food.Menus[placeId] or {}) do
		local f = Food.Items[id]
		table.insert(out, { Id = id, Name = f.Name, Icon = f.Icon, Price = f.Price, Heal = f.Heal, Energy = f.Energy, Boost = f.Boost, BoostTime = f.BoostTime, Desc = f.Desc, Color = f.Color })
	end
	return { Ok = true, Place = placeId, Label = placeLabel(placeId), Items = out, Coins = S.City.Coins(player) }
end

local function buy(player, info)
	local placeId = info.Place
	local item = Food.Items[info.Id or ""]
	local counter = counters[placeId or ""]
	if not item or not counter or not table.find(Food.Menus[placeId] or {}, info.Id) then
		return { Ok = false, Error = "They don't sell that here." }
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or (root.Position - counter.Position).Magnitude > 30 then
		return { Ok = false, Error = "Walk up to the counter first." }
	end
	if S.Crime and S.Crime.IsJailed(player) then
		return { Ok = false, Error = "No snacks in jail!" }
	end
	if not S.City.Spend(player, item.Price, "🍽️ " .. item.Name) then
		return { Ok = false, Error = "You need " .. item.Price .. " coins." }
	end
	-- eat it: heal, stamina, a boost
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + item.Heal)
	if item.Boost then
		player:SetAttribute("Boost", item.Boost)
		player:SetAttribute("BoostUntil", workspace:GetServerTimeNow() + (item.BoostTime or 60))
	end
	S.City.Send(player, { Type = "Food", Energy = item.Energy, Name = item.Name })
	character:SetAttribute("Eating", info.Id)
	task.delay(2.6, function()
		if character.Parent and character:GetAttribute("Eating") == info.Id then
			character:SetAttribute("Eating", nil)
		end
	end)
	S.City.Progress(player, "food", 1)
	local r = menu(player, placeId)
	r.Text = "Yum! " .. item.Name .. (if item.Heal > 0 then "  +" .. item.Heal .. " ❤️" else "") .. (if item.Energy > 0 then "  +" .. item.Energy .. " ⚡" else "")
	return r
end

local function addCounter(place)
	local counter = Instance.new("Part")
	counter.Name = "FoodCounter"
	counter.Anchored = true
	counter.CanCollide = false
	counter.CanQuery = false
	counter.Transparency = 1
	counter.Size = Vector3.new(2, 2, 2)
	counter.CFrame = CFrame.new((place.Inside or place.Door) + Vector3.new(0, 3, 0))
	counter.Parent = place.Model or workspace
	counters[place.Id] = counter
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FoodPrompt"
	prompt.ActionText = "Order food"
	prompt.ObjectText = placeLabel(place.Id)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Shop")
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		local data = menu(player, place.Id)
		data.Type = "FoodMenu"
		S.City.Send(player, data)
	end)
end

function FoodService.Start(services)
	S = services
	for placeId in pairs(Food.Menus) do
		local place = S.Map.Places[placeId]
		if place then
			addCounter(place)
		end
	end
	S.City.Handle("FoodMenu", function(player, info)
		if not counters[info.Place or ""] then
			return { Ok = false }
		end
		return menu(player, info.Place)
	end)
	S.City.Handle("BuyFood", buy)
end

return FoodService
