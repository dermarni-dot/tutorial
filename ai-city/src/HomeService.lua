-- HomeService (ModuleScript) — ServerScriptService.Modules.HomeService
-- Houses with real front doors, a house of your own, and break-ins.
--   • Doors: every house has a wooden front door on a hinge. It swings open
--     when someone walks up (citizens always get in) and closes behind them.
--   • Locks: homes people live in are locked to players. Empty houses are open
--     to look around.
--   • Your own house: "Buy house" at an empty house's door. It's yours (saved),
--     the door opens only for you, and you wake up there when you join.
--   • Break-ins: hold E on a locked door to force it open. Inside there are
--     valuables to steal. If the family is home or a neighbor sees, they call
--     the police, and some houses have an alarm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HomeService = {}
local S
local doors = {} -- list of door records
local byAddress = {} -- [address] = door record
local buckets = {} -- [key] = { door records } (for finding doors near people)
local BUCKET = 60
local OPEN_RANGE = 6.5
local REPAIR_TIME = 240 -- seconds until a forced door is fixed

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function key(x, z)
	return math.floor(x / BUCKET) .. ":" .. math.floor(z / BUCKET)
end

local function priceOf(home)
	local b = home.Building
	return if b and b.W >= 54 then 900 elseif b and b.Floors > 1 then 600 else 450
end

-- is anyone living here? (a citizen household)
local function occupied(home)
	for _, h in pairs(S.Life.Households or {}) do
		if h.Home == home.Index and #(h.Members or {}) > 0 then
			return true, h
		end
	end
	return false
end

local function setOpen(d, open)
	if d.Open == open then
		return
	end
	d.Open = open
	local goal = if open then d.Hinge * CFrame.Angles(0, math.rad(-100), 0) * CFrame.new(d.Width / 2, 0, 0) else d.Closed
	d.Part.CanCollide = not open
	local ok = pcall(function()
		TweenService:Create(d.Part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal }):Play()
	end)
	if not ok then
		d.Part.CFrame = goal
	end
end

-- who may open this door
local function lockedFor(d, player)
	if d.Broken then
		return false
	end
	if d.Owner then
		return d.Owner ~= player.UserId
	end
	return d.Lived
end

local function refreshPrompts(d)
	local vacant = not d.Lived and not d.Owner
	d.BuyPrompt.Enabled = vacant
	d.BuyPrompt.ObjectText = d.Home.Address .. "  ·  🪙 " .. priceOf(d.Home)
	d.BreakPrompt.Enabled = not vacant and not d.Broken
	d.Part:SetAttribute("Owner", d.Owner)
	d.Part:SetAttribute("Broken", d.Broken or nil)
end

--------------------------------------------------------------------------------
-- Owning a house
--------------------------------------------------------------------------------
local function releaseHome(player)
	for _, d in ipairs(doors) do
		if d.Owner == player.UserId then
			d.Owner = nil
			refreshPrompts(d)
		end
	end
end

local function claim(player, d, announce)
	releaseHome(player)
	d.Owner = player.UserId
	refreshPrompts(d)
	player:SetAttribute("HomeAddress", d.Home.Address)
	if announce then
		S.City.Toast(player, "🏠", "Welcome home!", d.Home.Address .. " is yours. The door opens only for you, and you'll wake up here.", rgb(90, 180, 120))
		S.City.News("🏠 " .. player.DisplayName .. " moved into " .. d.Home.Address .. ".", "City")
	end
end

local function buy(player, d)
	if d.Owner or d.Lived then
		return
	end
	local pd = S.City.Data(player)
	local price = priceOf(d.Home)
	if not pd or not S.City.Spend(player, price, "🏠 Bought " .. d.Home.Address) then
		S.City.Toast(player, "🪙", "Not enough coins", "This house costs " .. price .. " coins.", rgb(230, 170, 60))
		return
	end
	pd.Home = d.Home.Address
	claim(player, d, true)
	if S.MapBuilder and S.MapBuilder.FurnishHome then
		pcall(S.MapBuilder.FurnishHome, d.Home)
	end
end

function HomeService.HomeOf(player)
	for _, d in ipairs(doors) do
		if d.Owner == player.UserId then
			return d.Home
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Break-ins
--------------------------------------------------------------------------------
local LOOT = {
	{ "JewelryBox", "💍 Jewelry box", Vector3.new(1, 0.6, 0.8), rgb(160, 60, 110), 40, 90 },
	{ "CashStash", "💵 Cash under the mattress", Vector3.new(1.2, 0.3, 0.8), rgb(110, 170, 100), 25, 70 },
	{ "Laptop", "💻 Laptop", Vector3.new(1.4, 0.12, 1), rgb(60, 62, 70), 30, 60 },
	{ "GameConsole", "🎮 Game console", Vector3.new(1.2, 0.4, 0.9), rgb(240, 240, 245), 20, 50 },
}

local function clearLoot(d)
	for _, p in ipairs(d.Loot or {}) do
		if p.Parent then
			p:Destroy()
		end
	end
	d.Loot = {}
end

local function placeLoot(d)
	clearLoot(d)
	local spots = d.Home.Spots or {}
	if #spots == 0 then
		return
	end
	local n = math.random(2, 3)
	for k = 1, n do
		local spot = spots[math.random(1, #spots)]
		local item = LOOT[math.random(1, #LOOT)]
		local p = Instance.new("Part")
		p.Name = item[1]
		p.Anchored, p.CanCollide = true, false
		p.Size = item[3]
		p.Color = item[4]
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = spot.CFrame * CFrame.new(math.random(-10, 10) / 10, 0.6 + item[3].Y / 2, math.random(-10, 10) / 10)
		p.Parent = d.Home.Model or workspace
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Steal"
		prompt.ObjectText = item[2]
		prompt.HoldDuration = 1
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = p
		prompt.Triggered:Connect(function(player)
			if not p.Parent or d.Owner == player.UserId then
				return
			end
			local coins = math.random(item[5], item[6])
			p:Destroy()
			S.City.AddCoins(player, coins, "🏠 Stole a " .. item[2]:gsub("^%S+ ", ""))
			S.City.Toast(player, "🏠", "+" .. coins .. " coins", "You grabbed the " .. item[2]:gsub("^%S+ ", "") .. ".", rgb(230, 170, 60))
			-- is anyone home to see it?
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and S.Crime and S.Crime.Report then
				S.Crime.Report(player, root.Position, nil, 2, "rob a house", "robbed " .. d.Home.Address, 1)
			end
		end)
		table.insert(d.Loot, p)
	end
end

local function breakIn(player, d)
	if d.Broken or not lockedFor(d, player) then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (S.Crime and S.Crime.IsJailed(player)) then
		return
	end
	d.Broken = true
	d.BrokenUntil = os.clock() + REPAIR_TIME
	refreshPrompts(d)
	setOpen(d, true)
	if S.MapBuilder and S.MapBuilder.FurnishHome then
		pcall(S.MapBuilder.FurnishHome, d.Home)
	end
	placeLoot(d)
	S.City.Toast(player, "🚪", "You're in", "Grab the valuables and get out before anyone notices.", rgb(150, 110, 255))
	-- the family inside, a neighbor who saw, or the alarm
	local _, household = occupied(d.Home)
	local home = false
	if household and S.Citizens then
		for _, id in ipairs(household.Members or {}) do
			local brain = S.Citizens.ByCitizenId and S.Citizens.ByCitizenId(id)
			if brain and brain.Root and (brain.Root.Position - d.Home.Door).Magnitude < 35 and S.Citizens.CanReact(brain) then
				home = true
				task.delay(0.5, function()
					S.Citizens.Flee(brain, root.Position, 12, ({ "Someone's breaking in!!", "Get out of my house!", "Help! Burglar!" })[math.random(1, 3)])
				end)
			end
		end
	end
	local alarm = math.random() < (Config.HOUSE_ALARM_CHANCE or 0.35)
	if alarm then
		local s = Instance.new("Sound")
		s.Name = "HouseAlarm"
		s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		s.Looped = true
		s.Volume = 0.8
		s.PlaybackSpeed = 2
		s.Parent = d.Part
		pcall(function()
			s:Play()
		end)
		task.delay(25, function()
			s:Destroy()
		end)
		S.City.Toast(player, "🚨", "ALARM!", "The house alarm went off. The police are on the way.", rgb(230, 60, 60))
		if S.Crime then
			S.Crime.AddStars(player, 1, "A house alarm went off at " .. d.Home.Address .. "!")
		end
	end
	if S.Crime and S.Crime.Report then
		S.Crime.Report(player, root.Position, nil, if home then 3 else 2, "break into " .. d.Home.Address, "broke into " .. d.Home.Address, if home then 2 else 1)
	end
	S.City.Crime(2)
end

--------------------------------------------------------------------------------
-- Doors
--------------------------------------------------------------------------------
local function addDoor(home)
	local hd = home.Building and home.Building.HouseDoor
	if not hd or not hd.Part.Parent then
		return
	end
	local d = { Home = home, Part = hd.Part, Hinge = hd.Hinge, Closed = hd.Part.CFrame, Width = hd.Width, Open = false, Loot = {} }
	d.Lived = occupied(home)
	-- a still spot in front of the door for the prompts (the door itself moves)
	local anchor = Instance.new("Part")
	anchor.Name = "DoorPrompts"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = d.Closed * CFrame.new(0, -1, -1.4)
	anchor.Parent = hd.Part.Parent
	local buyPrompt = Instance.new("ProximityPrompt")
	buyPrompt.Name = "BuyHouse"
	buyPrompt.ActionText = "Buy house"
	buyPrompt.KeyboardKeyCode = Enum.KeyCode.G
	buyPrompt.HoldDuration = 0.6
	buyPrompt.MaxActivationDistance = 9
	buyPrompt.RequiresLineOfSight = false
	buyPrompt.Parent = anchor
	buyPrompt.Triggered:Connect(function(player)
		buy(player, d)
	end)
	local breakPrompt = Instance.new("ProximityPrompt")
	breakPrompt.Name = "BreakIn"
	breakPrompt.ActionText = "Break in"
	breakPrompt.ObjectText = home.Address
	breakPrompt.KeyboardKeyCode = Enum.KeyCode.E
	breakPrompt.HoldDuration = 2.5
	breakPrompt.MaxActivationDistance = 7
	breakPrompt.RequiresLineOfSight = false
	breakPrompt.UIOffset = Vector2.new(0, 60)
	breakPrompt.Parent = anchor
	breakPrompt.Triggered:Connect(function(player)
		breakIn(player, d)
	end)
	d.BuyPrompt, d.BreakPrompt = buyPrompt, breakPrompt
	refreshPrompts(d)
	table.insert(doors, d)
	byAddress[home.Address] = d
	local k = key(home.Door.X, home.Door.Z)
	buckets[k] = buckets[k] or {}
	table.insert(buckets[k], d)
	hd.Part:SetAttribute("Address", home.Address)
end

local function nearbyDoors(pos, out)
	local bx, bz = math.floor(pos.X / BUCKET), math.floor(pos.Z / BUCKET)
	for dx = -1, 1 do
		for dz = -1, 1 do
			for _, d in ipairs(buckets[(bx + dx) .. ":" .. (bz + dz)] or {}) do
				local c = d.Closed.Position
				local flat = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude
				if flat < OPEN_RANGE and math.abs(pos.Y - c.Y) < 8 then
					out[d] = out[d] or {}
					table.insert(out[d], pos)
				end
			end
		end
	end
end

local function step()
	-- who is near which door
	local want = {} -- [door] = true: open it
	local near = {}
	if S.Citizens and S.Citizens.List then
		for _, brain in ipairs(S.Citizens.List) do
			if brain.Root and brain.Model.Parent and brain.State ~= "ko" and brain.State ~= "hospital" then
				local marks = {}
				nearbyDoors(brain.Root.Position, marks)
				for d in pairs(marks) do
					want[d] = true
				end
			end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local marks = {}
			nearbyDoors(root.Position, marks)
			for d in pairs(marks) do
				near[d] = true
				if not lockedFor(d, player) then
					want[d] = true
				end
			end
		end
	end
	local now = os.clock()
	for _, d in ipairs(doors) do
		if d.Broken and now > (d.BrokenUntil or 0) and not near[d] then
			-- fixed: a new lock, and the valuables put away
			d.Broken = nil
			clearLoot(d)
			refreshPrompts(d)
		end
		setOpen(d, want[d] == true or d.Broken == true)
	end
end

function HomeService.Start(services)
	S = services
	for _, home in ipairs(S.Map.Homes or {}) do
		if home.Kind == "house" then
			addDoor(home)
		end
	end
	-- your saved house
	local function join(player)
		task.spawn(function()
			for _ = 1, 40 do
				if S.City.Data(player) then
					break
				end
				task.wait(0.25)
			end
			local pd = S.City.Data(player)
			local d = pd and pd.Home and byAddress[pd.Home]
			if d and not d.Owner and not d.Lived then
				claim(player, d, false)
			elseif pd and pd.Home and not d then
				pd.Home = nil
			end
			-- wake up at home
			local function spawnHome(character)
				local mine = HomeService.HomeOf(player)
				local root = character:WaitForChild("HumanoidRootPart", 5)
				if mine and root and mine.Inside then
					task.wait(0.2)
					root.CFrame = CFrame.new(mine.Inside + Vector3.new(0, 3, 0))
				end
			end
			player.CharacterAdded:Connect(spawnHome)
			if player.Character and d and d.Owner == player.UserId then
				task.spawn(spawnHome, player.Character)
			end
		end)
	end
	Players.PlayerAdded:Connect(join)
	for _, p in ipairs(Players:GetPlayers()) do
		join(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, d in ipairs(doors) do
			if d.Owner == player.UserId then
				d.Owner = nil
				refreshPrompts(d)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(step)
			if not ok then
				warn("[HomeService] " .. tostring(err))
				task.wait(2)
			end
		end
	end)
end

HomeService.Doors = doors
HomeService.BreakIn = breakIn
HomeService.Buy = buy

return HomeService
