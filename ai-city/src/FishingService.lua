-- FishingService (ModuleScript) — ServerScriptService.Modules.FishingService
-- Real fishing for players.
--   • Grab a free fishing rod at the start of the pier on Mirror Lake (or by
--     the pond in the park). It goes in your hotbar.
--   • Face the water and click (or F) to cast: the line flies out and the
--     bobber lands on the water.
--   • Wait... when the bobber dips (a fish is biting!) click again, fast.
--     Too slow and it gets away; too early and you reel in an empty hook.
--   • What you catch: 12 kinds of fish from common to legendary, each with its
--     own size (in pounds) and value in coins. You hold it up for everyone to
--     see, and rare catches make the news. Your biggest catch is remembered.
-- Water areas are parts tagged "Water" with attributes Radius, Surface, Depth.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local FishingService = {}
local S

FishingService.FISH = {
	-- { id, name, rarity, weight range (lbs), coins per lb, color }
	{ "Bluegill", "Bluegill", "Common", 0.3, 1.2, 6, Color3.fromRGB(90, 130, 170) },
	{ "Perch", "Yellow Perch", "Common", 0.4, 1.6, 6, Color3.fromRGB(200, 180, 80) },
	{ "Carp", "Carp", "Common", 2, 9, 2, Color3.fromRGB(150, 120, 70) },
	{ "Sunfish", "Sunfish", "Common", 0.3, 1, 7, Color3.fromRGB(230, 150, 60) },
	{ "Bass", "Largemouth Bass", "Uncommon", 1.5, 7, 5, Color3.fromRGB(80, 120, 70) },
	{ "Trout", "Rainbow Trout", "Uncommon", 1, 6, 6, Color3.fromRGB(200, 140, 160) },
	{ "Catfish", "Catfish", "Uncommon", 3, 14, 3, Color3.fromRGB(110, 100, 90) },
	{ "Pike", "Northern Pike", "Rare", 4, 18, 5, Color3.fromRGB(100, 140, 90) },
	{ "Salmon", "Salmon", "Rare", 4, 15, 6, Color3.fromRGB(230, 120, 100) },
	{ "Sturgeon", "Sturgeon", "Epic", 15, 60, 3, Color3.fromRGB(90, 100, 110) },
	{ "Koi", "Golden Koi", "Legendary", 3, 12, 25, Color3.fromRGB(255, 190, 40) },
	{ "Boot", "Old Boot", "Junk", 1, 2, 0, Color3.fromRGB(60, 45, 35) },
}
local RARITY = { Junk = 8, Common = 52, Uncommon = 26, Rare = 10, Epic = 3, Legendary = 1 }
local RARITY_EMOJI = { Junk = "🥾", Common = "🐟", Uncommon = "🐠", Rare = "🐡", Epic = "🦈", Legendary = "✨" }

local sessions = {} -- [player] = { State = "wait"|"bite", Bobber, Token, Water }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character
end

local function waters()
	return CollectionService:GetTagged("Water")
end

-- a spot on the water in front of the player (up to 18 studs out)
local function castPoint(root)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.1 then
		return nil
	end
	look = look.Unit
	for dist = 18, 5, -1 do
		local p = root.Position + look * dist
		for _, w in ipairs(waters()) do
			local c = w.Position
			local r = w:GetAttribute("Radius") or 10
			if Vector3.new(p.X - c.X, 0, p.Z - c.Z).Magnitude < r - 1.5 then
				return Vector3.new(p.X, w:GetAttribute("Surface") or c.Y, p.Z), w
			end
		end
	end
	return nil
end

local function rod(character)
	local tool = character and character:FindFirstChildOfClass("Tool")
	return if tool and tool:GetAttribute("Rod") then tool else nil
end

local function clear(player)
	local s = sessions[player]
	sessions[player] = nil
	if s and s.Bobber then
		s.Bobber:Destroy()
	end
	local character = player.Character
	if character then
		character:SetAttribute("Fishing", nil)
		character:SetAttribute("FishBite", nil)
	end
end

local function pickFish(water)
	local total = 0
	for _, f in ipairs(FishingService.FISH) do
		total += RARITY[f[3]] or 1
	end
	-- the pond in the park: mostly small fish (and the koi)
	local pond = water and water:GetAttribute("Kind") == "pond"
	local roll = math.random() * total
	for _, f in ipairs(FishingService.FISH) do
		roll -= RARITY[f[3]] or 1
		if roll <= 0 then
			if pond and (f[1] == "Sturgeon" or f[1] == "Catfish" or f[1] == "Pike") then
				return FishingService.FISH[1]
			end
			return f
		end
	end
	return FishingService.FISH[1]
end

local function catch(player, s)
	local root, character = rootOf(player)
	local f = pickFish(s.Water)
	local lbs = math.floor((f[4] + (f[5] - f[4]) * math.random() ^ 1.6) * 10 + 0.5) / 10
	local coins = math.max(if f[3] == "Junk" then 0 else 1, math.floor(lbs * f[6] + 0.5))
	clear(player)
	if coins > 0 then
		S.City.AddCoins(player, coins, "🎣 " .. f[2])
	end
	local pd = S.City.Data(player)
	local record = false
	if pd then
		pd.FishCaught = (pd.FishCaught or 0) + 1
		if f[3] ~= "Junk" and lbs > (pd.BiggestFish or 0) then
			pd.BiggestFish = lbs
			pd.BiggestFishName = f[2]
			record = pd.FishCaught > 1
		end
		player:SetAttribute("FishCaught", pd.FishCaught)
	end
	-- hold it up (see Poses)
	if character then
		character:SetAttribute("Caught", f[1])
		character:SetAttribute("CaughtColor", f[7])
		character:SetAttribute("CaughtSize", math.clamp(0.6 + lbs / 12, 0.6, 2.4))
		character:SetAttribute("CaughtAt", os.clock())
		task.delay(3.5, function()
			if character.Parent and character:GetAttribute("Caught") == f[1] then
				character:SetAttribute("Caught", nil)
			end
		end)
	end
	local text = if f[3] == "Junk" then "Just an old boot... it happens." else lbs .. " lb " .. f[2] .. "  ·  " .. f[3] .. "  ·  +" .. coins .. " coins" .. (if record then "  ·  🏆 your biggest yet!" else "")
	S.City.Toast(player, RARITY_EMOJI[f[3]] or "🐟", if f[3] == "Junk" then "Blub." else "You caught a " .. f[2] .. "!", text, if f[3] == "Legendary" then rgb(255, 200, 40) elseif f[3] == "Epic" then rgb(170, 90, 240) elseif f[3] == "Rare" then rgb(60, 150, 240) else rgb(90, 180, 120))
	S.City.SendNear(root and root.Position or Vector3.zero, 80, { Type = "FishCaught", Name = f[2], Rarity = f[3], Player = player.UserId })
	if f[3] == "Legendary" or f[3] == "Epic" then
		S.City.News("🎣 " .. player.DisplayName .. " reeled in a " .. lbs .. " lb " .. f[2] .. " at Mirror Lake!", "City")
	end
	pcall(S.City.Progress, player, "fish", 1)
	return { Ok = true, Caught = f[2], Rarity = f[3], Lbs = lbs, Coins = coins }
end

local function bite(player, token)
	local s = sessions[player]
	if not s or s.Token ~= token or s.State ~= "wait" then
		return
	end
	s.State = "bite"
	s.Bites = (s.Bites or 0) + 1
	local character = player.Character
	if character then
		character:SetAttribute("FishBite", os.clock())
	end
	-- the bobber dips
	local base = s.BobberCf
	pcall(function()
		TweenService:Create(s.Bobber, TweenInfo.new(0.12), { CFrame = base * CFrame.new(0, -0.6, 0) }):Play()
	end)
	S.City.Send(player, { Type = "FishBite", Position = base.Position })
	local window = 1.4
	task.delay(window, function()
		local now = sessions[player]
		if now and now.Token == token and now.State == "bite" then
			-- too slow: it got away (maybe another nibble later)
			now.State = "wait"
			if character then
				character:SetAttribute("FishBite", nil)
			end
			if now.Bobber.Parent then
				now.Bobber.CFrame = base
			end
			if now.Bites >= 3 then
				S.City.Toast(player, "🐟", "It got away!", "Too slow. Cast again!", rgb(200, 120, 80))
				clear(player)
				return
			end
			S.City.Toast(player, "🐟", "It got away...", "Keep watching the bobber. Click the moment it dips!", rgb(200, 120, 80))
			task.delay(math.random(30, 70) / 10, function()
				bite(player, token)
			end)
		end
	end)
end

local function cast(player)
	local root, character = rootOf(player)
	local tool = rod(character)
	if not root or not tool then
		return { Ok = false }
	end
	local point, water = castPoint(root)
	if not point then
		S.City.Toast(player, "🎣", "Face the water", "Stand at the edge (or on the pier) facing the water, then cast.", rgb(80, 160, 220))
		return { Ok = false, Error = "No water in front of you" }
	end
	local token = {}
	-- the cast (everyone sees the swing, then the bobber lands)
	character:SetAttribute("Casting", os.clock())
	local bobber = Instance.new("Part")
	bobber.Name = "Bobber"
	bobber.Shape = Enum.PartType.Ball
	bobber.Size = Vector3.one * 0.6
	bobber.Color = rgb(230, 50, 50)
	bobber.Material = Enum.Material.SmoothPlastic
	bobber.Anchored, bobber.CanCollide, bobber.CanQuery, bobber.CanTouch = true, false, false, false
	local cf = CFrame.new(point + Vector3.new(0, 0.15, 0))
	bobber.CFrame = CFrame.new(root.Position + Vector3.new(0, 4, 0))
	local top = Instance.new("Part")
	top.Name = "BobberTop"
	top.Shape = Enum.PartType.Ball
	top.Size = Vector3.one * 0.35
	top.Color = rgb(250, 250, 250)
	top.Anchored, top.CanCollide, top.CanQuery, top.CanTouch = false, false, false, false
	top.Massless = true
	top.CFrame = bobber.CFrame * CFrame.new(0, 0.3, 0)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = bobber, top
	w.Parent = top
	top.Parent = bobber
	bobber.Parent = workspace
	-- the fishing line from the rod tip
	local tip = tool:FindFirstChild("Tip", true)
	if tip and tip:IsA("Attachment") then
		local a1 = Instance.new("Attachment")
		a1.Parent = bobber
		local line = Instance.new("Beam")
		line.Name = "FishingLine"
		line.Attachment0, line.Attachment1 = tip, a1
		line.Width0, line.Width1 = 0.04, 0.04
		line.Color = ColorSequence.new(rgb(240, 240, 240))
		line.Transparency = NumberSequence.new(0.2)
		line.FaceCamera = true
		line.CurveSize0 = -2
		line.Parent = bobber
	end
	pcall(function()
		TweenService:Create(bobber, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cf }):Play()
	end)
	task.delay(0.6, function()
		if bobber.Parent then
			bobber.CFrame = cf
		end
	end)
	sessions[player] = { State = "wait", Bobber = bobber, BobberCf = cf, Token = token, Water = water, Started = os.clock() }
	character:SetAttribute("Fishing", "wait")
	task.delay(math.random(35, 90) / 10, function()
		bite(player, token)
	end)
	return { Ok = true, Cast = true }
end

-- one button: cast, then reel in (a catch if a fish is biting)
local function fishAction(player)
	local _, character = rootOf(player)
	if not rod(character) then
		return { Ok = false, Error = "Hold your fishing rod first." }
	end
	if S.Crime and S.Crime.IsJailed(player) then
		return { Ok = false }
	end
	local s = sessions[player]
	if not s then
		return cast(player)
	end
	if s.State == "bite" then
		return catch(player, s)
	end
	-- nothing biting yet: reel in empty
	if os.clock() - (s.Started or 0) > 0.8 then
		clear(player)
		character:SetAttribute("Casting", nil)
		return { Ok = true, Reeled = true }
	end
	return { Ok = true }
end
FishingService.Action = fishAction

--------------------------------------------------------------------------------
-- The rod
--------------------------------------------------------------------------------
function FishingService.MakeRod()
	local tool = Instance.new("Tool")
	tool.Name = "Fishing Rod"
	tool.ToolTip = "🎣 Fishing Rod"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Rod", true)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 1.4, 0.3)
	handle.Color = rgb(40, 40, 44)
	handle.Material = Enum.Material.Rubber
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = tool
	local function piece(name, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide, p.Massless = false, true
		p.CFrame = handle.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = handle, p
		w.Parent = p
		p.Parent = tool
		return p
	end
	local pole = piece("Pole", Vector3.new(0.14, 6.5, 0.14), CFrame.new(0, 3.9, 0), rgb(140, 100, 60), Enum.Material.Wood)
	piece("Reel", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0.3, 0.3, 0), rgb(180, 180, 190), Enum.Material.Metal)
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 3.2, 0)
	tip.Parent = pole
	tool.Grip = CFrame.new(0, -0.3, 0)
	return tool
end

local function giveRod(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	for _, container in ipairs({ backpack, player.Character }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("Rod") then
					S.City.Toast(player, "🎣", "You already have a rod", "Pick it from your hotbar, face the water and click (or F) to cast.", rgb(80, 160, 220))
					return
				end
			end
		end
	end
	FishingService.MakeRod().Parent = backpack
	local pd = S.City.Data(player)
	if pd then
		pd.HasRod = true
	end
	S.City.Toast(player, "🎣", "Got a fishing rod!", "Pick it from your hotbar, face the water and click (or F) to cast. When the bobber dips, click fast!", rgb(80, 160, 220))
end

local function rodStand(pos, label)
	local stand = Instance.new("Part")
	stand.Name = "RodStand"
	stand.Anchored = true
	stand.Size = Vector3.new(2, 3, 1)
	stand.Color = rgb(120, 80, 50)
	stand.Material = Enum.Material.WoodPlanks
	stand.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0))
	stand.Parent = workspace:FindFirstChild("City") or workspace
	for k = -1, 1 do
		local r = Instance.new("Part")
		r.Name = "StandRod"
		r.Anchored, r.CanCollide = true, false
		r.Size = Vector3.new(0.12, 5, 0.12)
		r.Color = rgb(140, 100, 60)
		r.CFrame = stand.CFrame * CFrame.new(k * 0.6, 2.5, 0) * CFrame.Angles(0, 0, math.rad(k * 6))
		r.Parent = stand
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RodPrompt"
	prompt.ActionText = "Grab a fishing rod"
	prompt.ObjectText = label
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand
	prompt.Triggered:Connect(giveRod)
end

function FishingService.Start(services)
	S = services
	-- rod stands by the water
	for _, w in ipairs(waters()) do
		local c, r = w.Position, w:GetAttribute("Radius") or 10
		local at = w:GetAttribute("RodStand")
		local pos = at or Vector3.new(c.X + r + 3, 0.2, c.Z)
		rodStand(pos, if w:GetAttribute("Kind") == "pond" then "Park pond" else "Mirror Lake")
	end
	S.City.Handle("Fish", fishAction)
	-- your rod comes back when you respawn (if you had one)
	local function hook(player)
		player.CharacterAdded:Connect(function()
			clear(player)
			task.wait(1)
			local pd = S.City.Data(player)
			local backpack = player:FindFirstChildOfClass("Backpack")
			if pd and pd.HasRod and backpack and not backpack:FindFirstChild("Fishing Rod") then
				FishingService.MakeRod().Parent = backpack
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerRemoving:Connect(clear)
	-- walking away or putting the rod down pulls the line in
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, s in pairs(sessions) do
				local root, character = rootOf(player)
				if not root or not rod(character) or (s.BobberCf and (root.Position - s.BobberCf.Position).Magnitude > 30) then
					clear(player)
				end
			end
		end
	end)
end

FishingService.Sessions = sessions
FishingService.GiveRod = giveRod

return FishingService
