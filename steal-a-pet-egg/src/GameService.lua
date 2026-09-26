-- GameService (ModuleScript) — ServerScriptService.Modules.GameService
-- The core game, all server-authoritative:
--   * Eggs grow in guarded nests out in the biomes
--   * Grab one and a guardian chases you until you escape its range
--   * Carry it home, where it incubates and can be stolen from your base
--   * Other players can snatch an egg off your head or bonk you to drop it
--   * Hatched pets earn cash; 3 of the same pet fuse into a bigger one
--   * Treadmill + speed shop make you faster so you can raid farther biomes

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local WHITE = Color3.new(1, 1, 1)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Visuals = require(Shared:WaitForChild("Visuals"))

local GameService = {}

local RED = Color3.fromRGB(255, 100, 100)
local GREEN = Color3.fromRGB(120, 235, 130)
local ORANGE = Color3.fromRGB(255, 175, 70)
local BLUE = Color3.fromRGB(130, 195, 255)
local GOLD = Color3.fromRGB(255, 215, 90)
local PINK = Color3.fromRGB(240, 130, 240)

local map
local notifyRemote
local hatchRemote
local slapRemote
local eggsFolder
local ringsFolder
local creaturesFolder

local eggs = {} -- [BasePart] = egg record
local states = {} -- [Player] = player state

-- Lifetime stats for the leaderboards (profile.Stats)
local function addStat(state, key, amount)
	local stats = state and state.Profile.Stats
	if stats then
		stats[key] = (stats[key] or 0) + (amount or 1)
	end
end
local plotOwners = {} -- [plotIndex] = Player

local rng = Random.new()
local onEggPrompt -- assigned further down

-- Server-wide luck bought from the shop: { Mult, Until }
local serverLuck = { Mult = 1, Until = 0 }
local function currentLuck()
	if workspace:GetServerTimeNow() < serverLuck.Until then
		return serverLuck.Mult
	end
	return 1
end

local PASS_KEYS = { "DoubleCashPass", "DoubleSpeedPass", "FastHatchPass" }

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
local function now()
	return workspace:GetServerTimeNow()
end

local function notify(player, text, color)
	if player and player.Parent then
		notifyRemote:FireClient(player, text, color)
	end
end

local function notifyAll(text, color)
	notifyRemote:FireAllClients(text, color)
end

local function getRoot(player)
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	return root, hum
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function setCash(state, amount)
	state.Profile.Cash = amount
	state.CashValue.Value = math.floor(amount)
end

local function trySpend(state, amount)
	if state.Profile.Cash >= amount then
		setCash(state, state.Profile.Cash - amount)
		return true
	end
	return false
end

-- Walk speed depends on the Speed stat, whether you're carrying, and stuns.
local function applyWalkSpeed(player)
	local state = states[player]
	local _, hum = getRoot(player)
	if not state or not hum then
		return
	end
	if now() < state.StunnedUntil then
		hum.WalkSpeed = state.StunSpeed
		return
	end
	local speed = Config.WalkSpeed(state.Profile.Speed)
	if state.InTown then
		speed = math.min(speed, Config.TownWalkSpeed) -- normal pace behind the red line
	end
	if state.Carrying then
		speed *= Config.CarrySpeedMultiplier
	end
	if state.BoostUntil and now() < state.BoostUntil and not state.InTown then
		speed *= Config.GrabBoostMultiplier -- adrenaline right after grabbing an egg
	end
	hum.WalkSpeed = speed
end

local function stun(player, duration, speed)
	local state = states[player]
	if not state then
		return
	end
	state.StunnedUntil = now() + duration
	state.StunSpeed = speed
	applyWalkSpeed(player)
	task.delay(duration + 0.05, function()
		if states[player] then
			applyWalkSpeed(player)
		end
	end)
end

local refreshSpeedPad -- defined further down

local function addSpeed(state, amount)
	state.Profile.Speed += amount
	state.SpeedValue.Value = state.Profile.Speed
	applyWalkSpeed(state.Player)
	if refreshSpeedPad and state.Plot.SpeedPrompt then
		refreshSpeedPad(state)
	end
end

-- Prompt audiences are read by the client, which hides prompts that aren't for
-- it ("Owner" = only that user sees it, "Others" = everyone except that user).
-- The server still re-checks every trigger.
local function setPromptAudience(prompt, mode, userId)
	prompt:SetAttribute("OwnerOnly", if mode == "Owner" then userId else nil)
	prompt:SetAttribute("OthersOnly", if mode == "Others" then userId else nil)
end

local function makePrompt(parent, actionText, objectText, holdDuration)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText or ""
	prompt.HoldDuration = holdDuration or 0
	prompt.MaxActivationDistance = Config.PromptRange
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Range", Config.PromptRange)
	prompt.Parent = parent
	return prompt
end

local function isInsidePlot(plot, position)
	return math.abs(position.X - plot.Center.X) <= plot.HalfWidth and math.abs(position.Z - plot.Center.Z) <= plot.HalfDepth
end

local function isOnTreadmill(plot, position)
	local tread = plot.Treadmill
	local localPos = tread.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= tread.Size.X / 2 + 0.5 and math.abs(localPos.Z) <= tread.Size.Z / 2 + 0.5 and localPos.Y < 6
end

local function freeSlot(state)
	for i = 1, state.Profile.Slots do
		if state.Nest[i] == nil then
			return i
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Eggs
-- rec.State: "Wild" (in a biome nest), "Carried", "Base" (incubating in a
-- player's base), "Dropped", "Rain", "Destroyed".
-- rec.HomeBiome is set while that biome's guardian is hunting the egg.
--------------------------------------------------------------------------------
local function refreshEggLabel(rec)
	local rarity = Config.RarityById[rec.Rarity]
	local title = rarity.Id .. " Egg"
	local variant = rec.Part:GetAttribute("EggVariant")
	if variant and variant ~= "Classic" then
		title = variant .. " " .. title
	end
	local mutation = rec.Mutation and Config.MutationById[rec.Mutation]
	if mutation then
		title = mutation.Icon .. " " .. mutation.Id .. " " .. title
	end
	if rec.Stolen then
		title = "Stolen " .. title
	end
	if (rec.PetSize or 1) >= Config.HugePetSize then
		title = "HUGE " .. title
	elseif (rec.PetSize or 1) >= Config.BigPetSize then
		title = "BIG " .. title
	end
	local sub = ""
	if rec.State == "Wild" then
		sub = "Guarded!"
	elseif rec.State == "Base" then
		sub = "Hatching in " .. Util.FormatTime(rec.Remaining)
	elseif rec.State == "Carried" then
		sub = if rec.HomeBiome or rec.Stolen then "RUN!" else "Take it home!"
	elseif rec.State == "Dropped" then
		sub = "Dropped! Grab it!"
	elseif rec.State == "Rain" then
		sub = "FREE!"
	end
	Visuals.SetLabel(rec.Part, title, sub, if mutation then mutation.Color else rarity.Color)
	if rec.State == "Base" then
		-- progress bar, and cracks that spread as it gets close to hatching
		local progress = 1 - rec.Remaining / rarity.HatchTime
		Visuals.SetProgress(rec.Part, progress, rarity.Color:Lerp(Color3.new(1, 1, 1), 0.2))
		if progress >= 0.5 then
			Visuals.CrackEgg(rec.Part, 1)
		end
		if progress >= 0.8 then
			Visuals.CrackEgg(rec.Part, 2, rarity.Color)
		end
	else
		Visuals.SetProgress(rec.Part, nil)
	end
end

-- The last few seconds before hatching, the egg wobbles in its spot
local function wobbleEgg(rec)
	if not rec.BaseCFrame or rec.State ~= "Base" then
		return
	end
	rec.WobbleDir = -(rec.WobbleDir or 1)
	rec.WobbleTween = TweenService:Create(rec.Part, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), { CFrame = rec.BaseCFrame * CFrame.Angles(0, 0, math.rad(14 * rec.WobbleDir)) })
	rec.WobbleTween:Play()
end

local function endHunt(rec)
	if rec.HomeBiome then
		rec.HomeBiome.Hunted[rec] = nil
		rec.HomeBiome = nil
	end
end

-- petSize is optional: by default the pet's size is rolled now, and the egg
-- is scaled to match, so a big pet always comes in a big egg.
local function createEgg(rarityId, remaining, stolen, mutation, petSize)
	local rarity = Config.RarityById[rarityId]
	local part = Visuals.MakeEgg(rarityId)
	if mutation and not Visuals.ApplyMutation(part, mutation) then
		mutation = nil
	end
	petSize = if petSize and petSize > 0 then petSize else Config.RollSize(rng)
	Visuals.ScaleEgg(part, Config.EggScale(petSize))
	part.Parent = eggsFolder
	local rec = {
		Part = part,
		Rarity = rarityId,
		Mutation = mutation,
		PetSize = petSize,
		Remaining = remaining or rarity.HatchTime,
		Stolen = stolen or false,
		State = "None",
	}
	rec.Prompt = makePrompt(part, "", "", 0)
	rec.Prompt.Triggered:Connect(function(player)
		onEggPrompt(player, rec)
	end)
	eggs[part] = rec
	return rec
end

local function destroyEgg(rec)
	if rec.Tween then
		rec.Tween:Cancel()
		rec.Tween = nil
	end
	endHunt(rec)
	rec.State = "Destroyed"
	eggs[rec.Part] = nil
	rec.Part:Destroy()
end

local function makeGrabbable(rec, state, lifetime)
	rec.State = state
	rec.Prompt.ActionText = "Grab"
	rec.Prompt.ObjectText = rec.Rarity .. " Egg"
	rec.Prompt.HoldDuration = Config.GrabHoldTime
	rec.Prompt.Enabled = true
	setPromptAudience(rec.Prompt, nil)
	refreshEggLabel(rec)
	local token = {}
	rec.DespawnToken = token
	task.delay(lifetime, function()
		if rec.State == state and rec.DespawnToken == token then
			destroyEgg(rec)
		end
	end)
end

--------------------------------------------------------------------------------
-- Wild nests
--------------------------------------------------------------------------------
local function placeInSpot(biome, spot, rec)
	rec.State = "Wild"
	rec.Spot = spot
	rec.SpotBiome = biome
	rec.Carrier = nil
	rec.DespawnToken = nil
	rec.Part.Anchored = true
	local home = CFrame.new(spot.Position + Vector3.new(0, rec.Part.Size.Y / 2 + 0.3, 0))
	rec.Part.CFrame = home
	rec.Part:SetAttribute("WildHome", home) -- clients use this to spin and bob it
	-- glowing ring in the egg's rarity color under the nest
	if spot.Ring then
		spot.Ring:Destroy()
	end
	spot.Ring = Visuals.MakeRarityRing(rec.Rarity, spot.Position)
	spot.Ring.Parent = ringsFolder
	rec.Prompt.ActionText = "Grab"
	rec.Prompt.ObjectText = rec.Rarity .. " Egg (guarded by " .. biome.Def.GuardianName .. ")"
	rec.Prompt.HoldDuration = Config.NestGrabHoldTime
	rec.Prompt.Enabled = true
	setPromptAudience(rec.Prompt, nil)
	spot.Egg = rec
	spot.NextSpawn = nil
	refreshEggLabel(rec)
end

local function spawnWildEgg(biome, spot)
	local weights = biome.Def.Eggs
	local luck = currentLuck()
	-- luck multiplies the odds of each rarer tier in this zone
	local lowest = math.huge
	for id in pairs(weights) do
		lowest = math.min(lowest, Config.RarityById[id].Order)
	end
	local rarity = Util.WeightedPick(Config.Rarities, function(r)
		local w = weights[r.Id] or 0
		return w * luck ^ ((r.Order - lowest) * 0.5)
	end, rng)
	-- late zones roll mutations more often (the roll takes the square root of luck)
	local mutation = Config.RollMutation(rng, luck * (biome.Def.MutationBoost or 1) ^ 2)
	local rec = createEgg(rarity.Id, nil, false, mutation)
	placeInSpot(biome, spot, rec)
	local mdef = mutation and Config.MutationById[mutation]
	if Config.AnnounceSpawnRarities[rarity.Id] or (mdef and Config.AnnounceMutations[mutation]) then
		local name = (if mdef then mdef.Icon .. " " .. mutation .. " " else "") .. rarity.Id
		notifyAll("🥚 A " .. name .. " Egg appeared in " .. biome.Def.Name .. "!", if mdef then mdef.Color else rarity.Color)
	end
end

-- The guardian got its egg back: put it in a free spot, or discard it.
local function returnToNest(rec)
	local biome = rec.HomeBiome
	endHunt(rec)
	if biome then
		for _, spot in ipairs(biome.Spots) do
			if not spot.Egg then
				placeInSpot(biome, spot, rec)
				return
			end
		end
	end
	destroyEgg(rec)
end

--------------------------------------------------------------------------------
-- Base lock
--------------------------------------------------------------------------------
local function setLocked(state, locked)
	state.LockActive = locked
	state.Plot.Dome.Transparency = if locked then 0.55 else 1
	for _, slot in pairs(state.Nest) do
		if slot.Kind == "Egg" then
			slot.Egg.Prompt.Enabled = not locked
		end
	end
	state.Player:SetAttribute("LockedUntil", if locked then state.LockedUntil else 0)
end

local function updateLockLabel(state)
	local t = now()
	local title, sub
	if state.LockActive then
		title, sub = "LOCKED", Util.FormatTime(state.LockedUntil - t)
	elseif t < state.LockReadyAt then
		title, sub = "RECHARGING", Util.FormatTime(state.LockReadyAt - t)
	else
		title, sub = "LOCK BASE", "Ready!"
	end
	Visuals.SetLabel(state.Plot.LockButton, title, sub, BLUE)
end

local function onLockPressed(player)
	local state = states[player]
	if not state then
		return
	end
	local t = now()
	if state.LockActive then
		notify(player, "Your base is already locked.", BLUE)
		return
	end
	if t < state.LockReadyAt then
		notify(player, "Lock recharging: " .. Util.FormatTime(state.LockReadyAt - t), RED)
		return
	end
	state.LockedUntil = t + Config.LockDuration
	state.LockReadyAt = state.LockedUntil + Config.LockCooldown
	setLocked(state, true)
	updateLockLabel(state)
	notify(player, "🔒 Base locked for " .. Config.LockDuration .. "s! Eggs can't be stolen.", BLUE)
end

--------------------------------------------------------------------------------
-- Pen and speed shop
--------------------------------------------------------------------------------
-- The pen is open: everyone gets the whole pen, nothing to buy
local function refreshSlots(state)
	state.Profile.Slots = Config.MaxSlots
end

-- The gold pad sells treadmill upgrades
local function treadmillLevel(state)
	return Config.TreadmillLevels[state.Profile.TreadmillLevel or 1] or Config.TreadmillLevels[1]
end

-- Dress the treadmill for its tier: belt stripes, frame, rails, neon trim,
-- light, console screen and pips, halo and particles (see Config.TreadmillLevels)
local TREAD_METAL = Color3.fromRGB(205, 208, 218)
local function paintTreadmill(state)
	local current = state.Profile.TreadmillLevel or 1
	local level = treadmillLevel(state)
	local model = state.Plot.Model
	local tread = state.Plot.Treadmill
	local color = level.Color
	local fancy = current >= 4 -- Gold and up get shiny tier-colored rails
	local stripes = model:FindFirstChild("TreadmillStripes")
	if stripes then
		for _, stripe in ipairs(stripes:GetChildren()) do
			stripe.Color = color
		end
	end
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			if d.Name == "TreadmillFrame" then
				d.Color = color:Lerp(Color3.new(0, 0, 0), 0.5)
				d.Material = Enum.Material[level.Frame or "Metal"]
			elseif d.Name == "TreadTrim" or d.Name == "TreadSkirt" or d.Name == "ConsoleGlow" then
				d.Color = color
			elseif d.Name == "SideRail" or d.Name == "RailPost" or d.Name == "ConsolePost" or d.Name == "Roller" then
				d.Color = if fancy then color:Lerp(Color3.new(1, 1, 1), 0.35) else TREAD_METAL
				d.Material = if fancy then Enum.Material.Foil else Enum.Material.Metal
			end
		end
	end
	local pips = model:FindFirstChild("TreadPips")
	if pips then
		for _, pip in ipairs(pips:GetChildren()) do
			local tier = pip:GetAttribute("Tier") or 99
			local owned = tier <= current
			pip.Color = if owned then Config.TreadmillLevels[tier].Color else Color3.fromRGB(45, 45, 55)
			pip.Material = if owned then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
	local halo = model:FindFirstChild("TreadHalo")
	if halo then
		for _, orb in ipairs(halo:GetChildren()) do
			orb.Color = color
			orb.Transparency = if level.Halo then 0 else 1
		end
	end
	local light = tread:FindFirstChild("TreadLight")
	if light then
		light.Color = color
		light.Brightness = level.Glow or 0
		light.Enabled = (level.Glow or 0) > 0
	end
	local fx = tread:FindFirstChild("TierFx")
	if fx then
		local def = level.Fx
		fx.Enabled = def ~= nil
		if def then
			fx.Rate = def.Rate
			fx.Size = NumberSequence.new(def.Size, 0)
			fx.Speed = NumberRange.new(def.Speed * 0.6, def.Speed)
			fx.Texture = if def.Fire then "rbxasset://textures/particles/fire_main.dds" else "rbxasset://textures/particles/sparkles_main.dds"
			fx.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.6))
		end
	end
	tread:SetAttribute("Rainbow", level.Rainbow == true)
	local console = model:FindFirstChild("Console")
	local screen = console and console:FindFirstChild("Screen")
	local bg = screen and screen:FindFirstChild("Bg")
	if bg then
		bg.TierLabel.Text = string.upper(level.Name) .. " TREADMILL"
		bg.TierLabel.TextColor3 = color
		bg.MultLabel.Text = "x" .. Util.FormatNumber(level.Mult) .. " SPEED"
		bg.Edge.Color = color
	end
	state.ScreenStatus = nil -- redraw the status line on the next tick
end

-- Burst of sparkles when you buy a new treadmill tier
local function treadmillBurst(state)
	local tread = state.Plot.Treadmill
	local burst = tread:FindFirstChild("BurstFx")
	if burst then
		local color = treadmillLevel(state).Color
		burst.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		burst:Emit(80)
	end
	local light = tread:FindFirstChild("TreadLight")
	if light then
		local glow = light.Brightness
		light.Enabled = true
		light.Brightness = 6
		TweenService:Create(light, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = glow }):Play()
	end
end

-- Screen status line and belt "running" state, only touched when they change
local function setTreadmillStatus(state, running, gain)
	local text = if running then "▶ +" .. Util.FormatNumber(gain) .. " Speed / sec" else "Step on to train!"
	if state.ScreenStatus == text then
		return
	end
	state.ScreenStatus = text
	local tread = state.Plot.Treadmill
	tread:SetAttribute("Running", running)
	local back = state.Plot.Model:FindFirstChild("TreadBackFx")
	local runFx = back and back:FindFirstChild("RunFx")
	if runFx then
		runFx.Enabled = running
	end
	local console = state.Plot.Model:FindFirstChild("Console")
	local screen = console and console:FindFirstChild("Screen")
	local bg = screen and screen:FindFirstChild("Bg")
	if bg then
		bg.StatusLabel.Text = text
		bg.StatusLabel.TextColor3 = if running then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(200, 210, 235)
	end
end

refreshSpeedPad = function(state)
	local levels = Config.TreadmillLevels
	local current = state.Profile.TreadmillLevel or 1
	local nextLevel = levels[current + 1]
	if nextLevel then
		Visuals.SetLabel(state.Plot.SpeedPad, "🏃 " .. nextLevel.Name .. " Treadmill x" .. nextLevel.Mult, Util.Money(nextLevel.Cost), nextLevel.Color)
		state.Plot.SpeedPrompt.ObjectText = nextLevel.Name .. " Treadmill: x" .. nextLevel.Mult .. " Speed (" .. Util.Money(nextLevel.Cost) .. ")"
		state.Plot.SpeedPrompt.Enabled = true
	else
		Visuals.SetLabel(state.Plot.SpeedPad, "🏃 MAX TREADMILL", levels[current].Name .. " x" .. levels[current].Mult, levels[current].Color)
		state.Plot.SpeedPrompt.ObjectText = "Your treadmill is maxed out"
		state.Plot.SpeedPrompt.Enabled = false
	end
end

local function onBuySpeed(player) -- buys the next treadmill upgrade
	local state = states[player]
	if not state then
		return
	end
	local current = state.Profile.TreadmillLevel or 1
	local nextLevel = Config.TreadmillLevels[current + 1]
	if not nextLevel then
		return
	end
	if not trySpend(state, nextLevel.Cost) then
		notify(player, "Not enough cash! The " .. nextLevel.Name .. " Treadmill costs " .. Util.Money(nextLevel.Cost), RED)
		return
	end
	state.Profile.TreadmillLevel = current + 1
	paintTreadmill(state)
	treadmillBurst(state)
	refreshSpeedPad(state)
	notify(player, "🏃 " .. nextLevel.Name .. " Treadmill unlocked! Training now gives x" .. nextLevel.Mult .. " Speed", nextLevel.Color)
end

--------------------------------------------------------------------------------
-- Base eggs, carrying and dropping
--------------------------------------------------------------------------------
local function placeEggInBase(player, index, rec)
	local state = states[player]
	rec.State = "Base"
	rec.Carrier = nil
	rec.TakenFrom = nil
	rec.Owner = player
	rec.SlotIndex = index
	rec.Part.Anchored = true
	rec.Part.CFrame = CFrame.new(state.Plot.SlotTops[index] + Vector3.new(0, rec.Part.Size.Y / 2, 0))
	rec.BaseCFrame = rec.Part.CFrame
	rec.Prompt.ActionText = "Steal"
	rec.Prompt.ObjectText = player.DisplayName .. "'s " .. rec.Rarity .. " Egg"
	rec.Prompt.HoldDuration = Config.BaseStealHoldTime
	rec.Prompt.Enabled = not state.LockActive
	setPromptAudience(rec.Prompt, "Others", player.UserId)
	state.Nest[index] = { Kind = "Egg", Egg = rec }
	refreshEggLabel(rec)
end

local function startCarry(player, rec)
	if rec.WobbleTween then
		rec.WobbleTween:Cancel()
		rec.WobbleTween = nil
	end
	rec.BaseCFrame = nil
	local state = states[player]
	local root = getRoot(player)
	if not state or not root then
		return false
	end
	if rec.Tween then
		rec.Tween:Cancel()
		rec.Tween = nil
	end
	rec.State = "Carried"
	rec.Part:SetAttribute("WildHome", nil)
	state.Training = false
	rec.Carrier = player
	rec.Owner = nil
	rec.SlotIndex = nil
	rec.Spot = nil
	rec.DespawnToken = nil

	local part = rec.Part
	part.Anchored = true
	part.CFrame = root.CFrame * CFrame.new(0, 4.7 + (part.Size.Y - Visuals.EggHalfHeight * 2) / 2, -0.3) -- held up in both hands
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Massless = true
	part.Anchored = false

	-- Other players can snatch it off your head.
	rec.Prompt.ActionText = "Steal"
	rec.Prompt.ObjectText = player.DisplayName .. "'s " .. rec.Rarity .. " Egg"
	rec.Prompt.HoldDuration = Config.CarrierStealHoldTime
	rec.Prompt.Enabled = true
	setPromptAudience(rec.Prompt, "Others", player.UserId)

	state.Carrying = rec
	applyWalkSpeed(player)
	player:SetAttribute("CarryingEgg", rec.Rarity)
	player:SetAttribute("CarryingStolen", rec.Stolen)
	refreshEggLabel(rec)
	return true
end

local function releaseCarry(player)
	local state = states[player]
	local rec = state and state.Carrying
	if not rec then
		return nil
	end
	state.Carrying = nil
	rec.Carrier = nil
	local weld = rec.Part:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	rec.Part.Anchored = true
	rec.Part.Massless = false
	rec.Prompt.Enabled = false
	player:SetAttribute("CarryingEgg", nil)
	player:SetAttribute("CarryingStolen", nil)
	applyWalkSpeed(player)
	return rec
end

-- Called when a carrier dies, gets bonked or leaves.
local function dropCarried(player)
	local state = states[player]
	if not state or not state.Carrying then
		return
	end
	local rec = state.Carrying
	local position = rec.Part.Position
	releaseCarry(player)

	-- Eggs stolen from someone's base fly back to it if there's room.
	local owner = rec.OriginalOwner
	local ownerState = owner and states[owner]
	if ownerState and not rec.HomeBiome then
		local index = freeSlot(ownerState)
		if index then
			rec.Stolen = false
			rec.OriginalOwner = nil
			placeEggInBase(owner, index, rec)
			notify(owner, "🛡️ Your " .. rec.Rarity .. " Egg was recovered!", GREEN)
			return
		end
	end

	rec.Part.CFrame = CFrame.new(position.X, rec.Part.Size.Y / 2 + 0.3, position.Z)
	makeGrabbable(rec, "Dropped", Config.DroppedEggLifetime)
end

--------------------------------------------------------------------------------
-- Pet Index: every pet you get is recorded (profile.Index, mirrored into a
-- player.PetIndex folder for the client). Finishing a rarity row gives a
-- permanent cash bonus of Config.IndexBonusPerRarity.
--------------------------------------------------------------------------------
local function indexProgress(profile, rarityId)
	local rarity = Config.RarityById[rarityId]
	local found = 0
	for _, def in ipairs(rarity.Creatures) do
		if profile.Index[def.Name] then
			found += 1
		end
	end
	return found, #rarity.Creatures
end

local function refreshIndexBonus(state)
	local complete = 0
	for _, rarity in ipairs(Config.Rarities) do
		local found, total = indexProgress(state.Profile, rarity.Id)
		if found == total then
			complete += 1
		end
	end
	state.IndexBonus = complete * Config.IndexBonusPerRarity
	state.Player:SetAttribute("IndexBonus", state.IndexBonus)
end

local function addIndexFlag(state, name)
	local flag = Instance.new("BoolValue")
	flag.Name = name
	flag.Value = true
	flag.Parent = state.IndexFolder
end

local function discoverPet(state, name)
	local profile = state.Profile
	local def = Config.CreatureByName[name]
	if not def or profile.Index[name] then
		return
	end
	profile.Index[name] = true
	addIndexFlag(state, name)
	if state.Loading then
		return -- old saves: quietly add pets that are already in the base
	end
	local rarity = Config.RarityById[def.Rarity]
	local found, total = indexProgress(profile, def.Rarity)
	notify(state.Player, "📖 New pet in your Index: " .. name .. "! (" .. def.Rarity .. " " .. found .. "/" .. total .. ")", rarity.Color)
	if found == total then
		refreshIndexBonus(state)
		notify(state.Player, "🏆 " .. def.Rarity .. " Index complete! +" .. math.floor(Config.IndexBonusPerRarity * 100 + 0.5) .. "% cash from all your pets, forever!", GOLD)
		notifyAll("🏆 " .. state.Player.DisplayName .. " completed the " .. def.Rarity .. " Pet Index!", rarity.Color)
	end
end

--------------------------------------------------------------------------------
-- Revenge: when a thief gets your egg home, you get Config.RevengeTime seconds
-- to steal any egg from them for bonus cash. The client reads the
-- RevengeTarget / RevengeUntil attributes to show a timer and highlight them.
--------------------------------------------------------------------------------
local function setRevenge(state, target, untilTime)
	state.RevengeOn = target
	state.RevengeUntil = if target then untilTime else 0
	state.Player:SetAttribute("RevengeTarget", if target then target.UserId else nil)
	state.Player:SetAttribute("RevengeUntil", if target then untilTime else nil)
end

-- thief just got an egg that belonged to victim home
local function onEggStolen(thief, victim, rarityId)
	local thiefState, victimState = states[thief], states[victim]
	if not thiefState or not victimState or thief == victim then
		return
	end
	if thiefState.RevengeOn == victim and now() < thiefState.RevengeUntil then
		local income = thief:GetAttribute("IncomePerSec") or 0
		local bonus = math.max(Config.RevengeMinCash, math.floor(income * 60 * Config.RevengeCashMinutes))
		setCash(thiefState, thiefState.Profile.Cash + bonus)
		setRevenge(thiefState, nil)
		thiefState.RevengeReadyAt = now() + Config.RevengeCooldown
		notify(thief, "😤 REVENGE on " .. victim.DisplayName .. "! +" .. Util.Money(bonus) .. " bonus cash!", GOLD)
		notifyAll("😤 " .. thief.DisplayName .. " got revenge on " .. victim.DisplayName .. "!", ORANGE)
		return -- a revenge steal doesn't open a counter-revenge
	end
	if now() < (victimState.RevengeReadyAt or 0) then
		return
	end
	setRevenge(victimState, thief, now() + Config.RevengeTime)
	notify(victim, "🚨 " .. thief.DisplayName .. " stole your " .. rarityId .. " Egg! Steal any egg from them within " .. Util.FormatTime(Config.RevengeTime) .. " for REVENGE cash!", RED)
end

--------------------------------------------------------------------------------
-- Treats: timed growth + cash boosts bought at the town stall
--------------------------------------------------------------------------------
local function showTreat(state)
	local treat = state.Profile.Treat
	state.Player:SetAttribute("TreatKey", if treat then treat.Key else nil)
	state.Player:SetAttribute("TreatUntil", if treat then treat.Until else nil)
end

-- The active treat's definition, or nil (and clears it once it runs out)
local function activeTreat(state)
	local treat = state.Profile.Treat
	if not treat then
		return nil
	end
	if os.time() >= treat.Until then
		state.Profile.Treat = nil
		showTreat(state)
		local def = Config.TreatByKey[treat.Key]
		notify(state.Player, (if def then def.Icon .. " Your " .. def.Name else "Your treat") .. " wore off.", ORANGE)
		return nil
	end
	return Config.TreatByKey[treat.Key]
end

--------------------------------------------------------------------------------
-- Pets, hatching and fusing
--------------------------------------------------------------------------------
local spawnCreature

local function removeCreature(state, index)
	local slot = state.Nest[index]
	if slot and slot.Kind == "Creature" then
		slot.Model:Destroy()
		state.Nest[index] = nil
	end
end

spawnCreature = function(player, index, data)
	local state = states[player]
	local plot = state.Plot
	local model = Visuals.MakeCreature(data)
	local bodyHeight = model.PrimaryPart.Size.Y
	-- feet reach about 0.6 of the body height below its center; floaters hover
	local footDrop = model:GetAttribute("FootDrop") or bodyHeight * 0.62
	local position = plot.SlotTops[index] + Vector3.new(0, footDrop + (model:GetAttribute("Hover") or 0), 0)
	model:PivotTo(CFrame.lookAt(position, position + plot.FrontDir))
	-- the owner's pen: every client walks the pet around inside it
	model:SetAttribute("PenCFrame", plot.PenCFrame)
	model:SetAttribute("PenHalfSize", plot.PenHalfSize)
	model:SetAttribute("RoamSeed", index * 7919 + plot.Index * 131)
	model.Parent = creaturesFolder

	local prompt = makePrompt(model.PrimaryPart, "Sell", Config.CreatureTitle(data) .. " (" .. Util.Money(Config.SellValue(data)) .. ")", 0.6)
	prompt.Name = "SellPrompt"
	setPromptAudience(prompt, "Owner", player.UserId)
	prompt.Triggered:Connect(function(who)
		if who ~= player then
			return
		end
		local slot = state.Nest[index]
		if not slot or slot.Model ~= model then
			return
		end
		local sellValue = Config.SellValue(data) -- worth more as it grows
		removeCreature(state, index)
		setCash(state, state.Profile.Cash + sellValue)
		notify(player, "Sold " .. Config.CreatureTitle(data) .. " for " .. Util.Money(sellValue), GOLD)
	end)

	state.Nest[index] = { Kind = "Creature", Model = model, Data = data }
	discoverPet(state, data.Name)
end

local function rollCreature(rarityId, stolen)
	local rarity = Config.RarityById[rarityId]
	-- rarer pets inside a rarity can have a lower Weight (default 1)
	local def = Util.WeightedPick(rarity.Creatures, function(c)
		return c.Weight or 1
	end, rng)
	local chance = if stolen then Config.StolenShinyChance else Config.ShinyChance
	chance = math.min(0.5, chance * math.sqrt(currentLuck()))
	return { Name = def.Name, Rarity = rarityId, Shiny = rng:NextNumber() < chance, Tier = 1, Size = Config.RollSize(rng), Age = 0 }
end

-- The egg bursts open in the world: shell pieces fly out, a flash of light
-- and a puff of sparkles in the rarity color (everyone nearby sees it).
local function hatchBurst(eggPart, color)
	local folder = workspace:FindFirstChild("Effects") or Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = workspace
	local pos, size, shellColor = eggPart.Position, eggPart.Size, eggPart.Color
	local pieces = {}
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local shard = Instance.new("Part")
		shard.Name = "EggShard"
		shard.Size = Vector3.new(size.X * 0.34, size.Y * 0.28, 0.25)
		shard.CFrame = CFrame.new(pos + Vector3.new(math.cos(a), (i % 3 - 1) * 0.5, math.sin(a)) * size.X * 0.3) * CFrame.Angles(math.random() * 3, a, math.random() * 3)
		shard.Color = if i % 3 == 0 then WHITE else shellColor
		shard.Material = Enum.Material.SmoothPlastic
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.Parent = folder
		shard.AssemblyLinearVelocity = Vector3.new(math.cos(a) * 14, 18 + math.random() * 10, math.sin(a) * 14)
		shard.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		TweenService:Create(shard, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.45), { Transparency = 1 }):Play()
		table.insert(pieces, shard)
	end
	local flash = Instance.new("Part")
	flash.Name = "HatchFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = size
	flash.Position = pos
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Color = color:Lerp(WHITE, 0.5)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.1
	flash.Parent = folder
	table.insert(pieces, flash)
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = size * 3.2, Transparency = 1 }):Play()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 5
	light.Parent = flash
	TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(color, WHITE)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.8, 0)
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Speed = NumberRange.new(10, 20)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Drag = 3
	sparkles.Rate = 0
	sparkles.Parent = flash
	sparkles:Emit(35)
	task.delay(1.4, function()
		for _, piece in ipairs(pieces) do
			piece:Destroy()
		end
	end)
end

local function hatch(player, index)
	local state = states[player]
	local rec = state.Nest[index].Egg
	local data = rollCreature(rec.Rarity, rec.Stolen)
	data.Mutation = rec.Mutation
	data.Size = rec.PetSize or data.Size -- the size the egg showed
	local eggVariant = rec.Part:GetAttribute("EggVariant")
	local burstColor = if rec.Mutation and Config.MutationById[rec.Mutation] then Config.MutationById[rec.Mutation].Color else Config.RarityById[rec.Rarity].Color
	hatchBurst(rec.Part, burstColor)
	destroyEgg(rec)
	state.Nest[index] = nil
	local isNew = not state.Profile.Index[data.Name]
	spawnCreature(player, index, data)
	addStat(state, "Hatched")
	if hatchRemote then
		-- the client shows a big reveal with a 3D preview of the pet
		hatchRemote:FireClient(player, { Name = data.Name, Rarity = data.Rarity, Shiny = data.Shiny, Mutation = data.Mutation, Size = data.Size, Tier = data.Tier, Age = 0, New = isNew, EggVariant = eggVariant })
	end

	local rarity = Config.RarityById[data.Rarity]
	local name = Config.CreatureTitle(data)
	local income = Config.CreatureIncome(data)
	notify(player, "🐣 Hatched a baby " .. (if data.Shiny then "✨" else "") .. name .. " (" .. string.format("%.1f kg", Config.PetWeight(data)) .. ")! +" .. Util.Money(income) .. "/s, earns more as it grows", rarity.Color)
	if Config.AnnounceHatchRarities[data.Rarity] or (data.Shiny and rarity.Order >= 4) then
		notifyAll("🎉 " .. player.DisplayName .. " hatched a " .. name .. "!", rarity.Color)
	end
end

local function onFuse(player)
	local state = states[player]
	if not state then
		return
	end
	-- Group pets of the same kind and tier. Shiny, mutation, size and age don't
	-- have to match: the fused pet keeps the best of each.
	local groups = {}
	local maxed = 0
	for index = 1, Config.MaxSlots do
		local slot = state.Nest[index]
		if slot and slot.Kind == "Creature" then
			local d = slot.Data
			if (d.Tier or 1) >= #Config.Tiers then
				maxed += 1
			else
				local key = d.Name .. "|" .. (d.Tier or 1)
				groups[key] = groups[key] or { Name = d.Name, Tier = d.Tier or 1, Slots = {} }
				table.insert(groups[key].Slots, index)
			end
		end
	end

	-- Pick the group that makes the best pet; inside a group, fuse the best
	-- three (most valuable first) if there are more than three.
	local function value(index)
		return Config.CreatureIncome(state.Nest[index].Data)
	end
	local best, bestValue
	for _, group in pairs(groups) do
		if #group.Slots >= Config.FuseCount then
			table.sort(group.Slots, function(a, b)
				return value(a) > value(b)
			end)
			local total = 0
			for i = 1, Config.FuseCount do
				total += value(group.Slots[i])
			end
			if not best or total > bestValue then
				best, bestValue = group, total
			end
		end
	end
	if not best then
		if maxed > 0 and next(groups) == nil then
			notify(player, "Your pets are already " .. Config.Tiers[#Config.Tiers].Prefix .. "— the biggest they can get!", RED)
		else
			notify(player, "You need " .. Config.FuseCount .. " of the same pet (below " .. Config.Tiers[#Config.Tiers].Prefix .. "size) in your base to fuse.", RED)
		end
		return
	end

	-- read everything we keep BEFORE the pets are removed
	local shiny, mutation, bestMult, size, age = false, nil, 0, 0, 0
	local rarityId
	for i = 1, Config.FuseCount do
		local d = state.Nest[best.Slots[i]].Data
		rarityId = d.Rarity
		shiny = shiny or d.Shiny == true
		local m = d.Mutation and Config.MutationById[d.Mutation]
		if m and m.Mult > bestMult then
			mutation, bestMult = d.Mutation, m.Mult
		end
		size = math.max(size, d.Size or 1)
		age = math.max(age, d.Age or 0)
	end
	local fused = { Name = best.Name, Rarity = rarityId, Shiny = shiny, Mutation = mutation, Tier = best.Tier + 1, Size = if size > 0 then size else 1, Age = age }
	for i = 1, Config.FuseCount do
		removeCreature(state, best.Slots[i])
	end
	spawnCreature(player, best.Slots[1], fused)
	local rarity = Config.RarityById[fused.Rarity]
	notify(player, "🧬 Fused into " .. Config.CreatureTitle(fused) .. "! +" .. Util.Money(Config.CreatureIncome(fused)) .. "/s", PINK)
	if rarity.Order >= 4 then
		notifyAll("🧬 " .. player.DisplayName .. " fused a " .. Config.CreatureTitle(fused) .. "!", rarity.Color)
	end
end

--------------------------------------------------------------------------------
-- Egg prompt: grab from nest, steal from a base, snatch from a carrier,
-- or pick up a dropped / rained egg.
--------------------------------------------------------------------------------
onEggPrompt = function(player, rec)
	local state = states[player]
	if not state or rec.State == "Destroyed" then
		return
	end
	if state.Carrying then
		notify(player, "You're already carrying an egg!", RED)
		return
	end
	if not getRoot(player) or now() < state.StunnedUntil then
		return
	end

	if rec.State == "Wild" then
		local biome, spot = rec.SpotBiome, rec.Spot
		spot.Egg = nil
		if spot.Ring then
			spot.Ring:Destroy()
			spot.Ring = nil
		end
		spot.NextSpawn = now() + biome.Def.RespawnTime
		rec.TakenFrom = nil
		rec.GrabPos = spot.Position -- the guardian chases until you're Leash studs from here
		rec.Spot = nil
		rec.HomeBiome = biome
		local guardian = biome.Guardian
		if guardian and not guardian.Target then
			guardian.WakeUntil = now() + Config.GuardianWakeTime -- it was napping
		end
		biome.Hunted[rec] = true
		state.BoostUntil = now() + Config.GrabBoostTime
		startCarry(player, rec)
		task.delay(Config.GrabBoostTime + 0.05, function()
			if states[player] then
				applyWalkSpeed(player)
			end
		end)
		notify(player, "🥚 Got a " .. rec.Rarity .. " Egg! The " .. biome.Def.GuardianName .. " is coming. RUN!", ORANGE)
	elseif rec.State == "Base" then
		local owner = rec.Owner
		if owner == player then
			return
		end
		local ownerState = owner and states[owner]
		if ownerState then
			if ownerState.LockActive then
				notify(player, "That base is locked!", RED)
				return
			end
			ownerState.Nest[rec.SlotIndex] = nil
		end
		rec.Stolen = true
		rec.OriginalOwner = owner
		rec.TakenFrom = owner
		rec.StolenFromName = if owner then owner.DisplayName else "someone"
		startCarry(player, rec)
		notify(player, "😈 You grabbed " .. rec.StolenFromName .. "'s " .. rec.Rarity .. " Egg! RUN home!", ORANGE)
		if owner then
			notify(owner, "⚠️ " .. player.DisplayName .. " is stealing your " .. rec.Rarity .. " Egg! Bonk them!", RED)
		end
	elseif rec.State == "Carried" then
		local victim = rec.Carrier
		if not victim or victim == player then
			return
		end
		releaseCarry(victim)
		rec.Stolen = true
		rec.TakenFrom = victim
		rec.StolenFromName = victim.DisplayName
		startCarry(player, rec)
		notify(player, "😈 You snatched " .. victim.DisplayName .. "'s " .. rec.Rarity .. " Egg!", ORANGE)
		notify(victim, "⚠️ " .. player.DisplayName .. " snatched your egg!", RED)
	elseif rec.State == "Dropped" or rec.State == "Rain" then
		rec.TakenFrom = nil
		startCarry(player, rec)
	end
end

--------------------------------------------------------------------------------
-- Guardians
--------------------------------------------------------------------------------
local function pickTarget(biome)
	local guardian = biome.Guardian
	local best, bestDist
	for rec in pairs(biome.Hunted) do
		if rec.State == "Carried" or rec.State == "Dropped" then
			local dist = (flat(rec.Part.Position) - flat(guardian.Position)).Magnitude
			if not best or dist < bestDist then
				best, bestDist = rec, dist
			end
		else
			biome.Hunted[rec] = nil
		end
	end
	return best
end

local function setChased(guardian, player)
	if guardian.ChasedPlayer == player then
		return
	end
	if guardian.ChasedPlayer then
		guardian.ChasedPlayer:SetAttribute("ChasedBy", nil)
	end
	guardian.ChasedPlayer = player
	if player then
		player:SetAttribute("ChasedBy", guardian.Name)
	end
end

-- A giant cartoon glove: a white palm with fingers, a thumb and a red cuff,
-- welded to the palm so tweening the palm moves the whole glove.
local function makeSlapGlove()
	local glove = Instance.new("Model")
	glove.Name = "SlapGlove"
	local WHITE = Color3.fromRGB(250, 250, 250)
	local function piece(name, size, offset, color, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.Color = color or WHITE
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = glove
		return p, offset
	end
	local palm = piece("Palm", Vector3.new(5, 5.6, 1.8), nil, WHITE, Enum.PartType.Ball)
	palm.Anchored = true
	glove.PrimaryPart = palm
	local parts = {
		{ piece("Cuff", Vector3.new(1.6, 4.4, 4.4), CFrame.new(0, -3.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(230, 50, 60), Enum.PartType.Cylinder) },
	}
	for i, x in ipairs({ -1.65, -0.55, 0.55, 1.65 }) do
		local len = if i == 1 or i == 4 then 3 else 3.6
		table.insert(parts, { piece("Finger", Vector3.new(1.1, len, 1.1), CFrame.new(x, 2.6 + len / 2 - 0.9, 0)) })
	end
	table.insert(parts, { piece("Thumb", Vector3.new(1.2, 2.6, 1.2), CFrame.new(-3, 0.2, 0) * CFrame.Angles(0, 0, math.rad(50))) })
	for _, info in ipairs(parts) do
		local p, offset = info[1], info[2]
		p.CFrame = palm.CFrame * offset
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = palm
		weld.Part1 = p
		weld.Parent = p
	end
	return glove, palm
end

-- The slap everyone can see: the glove swings through the player, a ring and
-- stars burst out, and a "SLAP!" pops up over them.
local function slapEffect(fromPosition, hit, away)
	local folder = workspace:FindFirstChild("Effects") or Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = workspace

	local glove, palm = makeSlapGlove()
	local up = Vector3.yAxis
	local startCF = CFrame.lookAt(hit - away * 9 + up * 7, hit - away * 9 + up * 7 + away) * CFrame.Angles(math.rad(-60), 0, 0)
	local endCF = CFrame.lookAt(hit + away * 3 + up * 1.5, hit + away * 3 + up * 1.5 + away) * CFrame.Angles(math.rad(20), 0, 0)
	palm.CFrame = startCF
	for _, d in ipairs(glove:GetChildren()) do
		if d ~= palm and d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	glove.Parent = folder
	TweenService:Create(palm, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = endCF }):Play()
	task.delay(0.16, function()
		-- impact: a ring that shoots out, a star burst and the SLAP! sign
		local ring = Instance.new("Part")
		ring.Name = "SlapRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.3, 2, 2)
		ring.CFrame = CFrame.new(hit) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = Color3.fromRGB(255, 240, 150)
		ring.Material = Enum.Material.Neon
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Parent = folder
		TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 22, 22), Transparency = 1 }):Play()

		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		burst.Color = ColorSequence.new(Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 120, 60))
		burst.LightEmission = 0.8
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
		burst.Lifetime = NumberRange.new(0.4, 0.8)
		burst.Speed = NumberRange.new(25, 45)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Drag = 4
		burst.Rate = 0
		burst.Parent = ring
		burst:Emit(40)

		local sign = Instance.new("BillboardGui")
		sign.Name = "SlapText"
		sign.Size = UDim2.fromScale(12, 4)
		sign.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		sign.AlwaysOnTop = true
		sign.LightInfluence = 0
		sign.Parent = ring
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.Text = "SLAP!"
		text.Rotation = -8
		text.TextColor3 = Color3.fromRGB(255, 230, 70)
		text.TextStrokeColor3 = Color3.fromRGB(150, 20, 20)
		text.TextStrokeTransparency = 0
		text.Parent = sign
		TweenService:Create(text, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

		-- the glove follows through and fades away
		TweenService:Create(palm, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = endCF * CFrame.new(0, 2, -4) }):Play()
		for _, d in ipairs(glove:GetChildren()) do
			if d:IsA("BasePart") then
				TweenService:Create(d, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.25), { Transparency = 1 }):Play()
			end
		end
		task.delay(1, function()
			ring:Destroy()
			glove:Destroy()
		end)
	end)
end

local function caught(biome, player, rec)
	releaseCarry(player)
	addStat(states[player], "Slapped")
	returnToNest(rec)
	stun(player, Config.GuardianStunTime + Config.SlapFlightTime, Config.GuardianStunSpeed)
	notify(player, "💥 SLAP! The " .. biome.Def.GuardianName .. " caught you, took the egg back and sent you home!", RED)

	-- Slap! The glove hits you, you go flying (your client does the flight,
	-- shake and SLAP! text) and land back at the start of your base.
	local root = getRoot(player)
	local state = states[player]
	if not root or not state then
		return
	end
	local from = biome.Guardian.Position
	local away = (root.Position - from) * Vector3.new(1, 0, 1)
	away = if away.Magnitude > 0.1 then away.Unit else root.CFrame.LookVector
	slapEffect(from, root.Position, away)
	if slapRemote then
		slapRemote:FireClient(player, away, biome.Def.GuardianName)
	end
	state.SlapToken = (state.SlapToken or 0) + 1
	local token = state.SlapToken
	task.delay(Config.SlapFlightTime, function()
		local s = states[player]
		local char = player.Character
		if s and s.SlapToken == token and char and char.Parent then
			char:PivotTo(s.Plot.SpawnCFrame)
			local r = getRoot(player)
			if r then
				r.AssemblyLinearVelocity = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end)
end

local function updateGuardian(biome, dt)
	local guardian = biome.Guardian
	local def = biome.Def

	local target = guardian.Target
	if not (target and biome.Hunted[target] and (target.State == "Carried" or target.State == "Dropped")) then
		target = pickTarget(biome)
		guardian.Target = target
	end

	local waking = guardian.WakeUntil and now() < guardian.WakeUntil
	if waking then
		target = nil -- still rubbing its eyes: no chasing or catching yet
	end

	local goal
	local chasedPlayer = nil
	if target then
		if target.State == "Carried" then
			local carrier = target.Carrier
			local root = carrier and getRoot(carrier)
			if root then
				if root.Position.Z < map.SafeZoneZ then -- made it past the red line into town
					endHunt(target)
					guardian.Target = nil
					refreshEggLabel(target)
					notify(carrier, "😅 You escaped the " .. def.GuardianName .. " into the safe zone!", GREEN)
				else
					goal = root.Position
					chasedPlayer = carrier
				end
			end
		else
			goal = target.Part.Position
		end
	end
	setChased(guardian, chasedPlayer)

	local home = not goal
	goal = goal or (if waking then guardian.Position else biome.GuardianHome)
	local offset = flat(goal) - flat(guardian.Position)
	local distance = offset.Magnitude
	local speed = if home then def.GuardianSpeed * 0.6 else def.GuardianSpeed

	local moving = distance > 0.05
	if moving then
		local step = math.min(speed * dt, distance)
		local dir = offset.Unit
		guardian.Position += dir * step
		guardian.Facing = dir
		distance -= step
	elseif home then
		guardian.Facing = -Vector3.zAxis
	end
	guardian.Resting = home and distance <= 0.05 and not waking

	-- Cartoon motion: bouncy waddle while running, slow breathing while napping,
	-- and the boss always hovers.
	guardian.Phase += dt * (if moving then 2 + math.min(speed, 130) * 0.12 else 1.5) -- fast guardians don't waddle into a blur
	local bob, roll = 0, 0
	if def.Boss then
		bob = math.sin(guardian.Phase * 0.8) * 1.2
		roll = if moving then math.sin(guardian.Phase) * 0.05 else 0
	elseif moving then
		bob = math.abs(math.sin(guardian.Phase)) * 1.1
		roll = math.sin(guardian.Phase) * 0.12
	else
		bob = math.sin(guardian.Phase) * 0.15
	end
	guardian.Model:PivotTo(CFrame.lookAt(guardian.Position, guardian.Position + guardian.Facing) * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, roll))
	if guardian.Sleep then
		guardian.Sleep.Enabled = guardian.Resting
	end

	if not waking and target and guardian.Target == target and distance <= Config.GuardianCatchRange then
		if target.State == "Carried" and target.Carrier then
			caught(biome, target.Carrier, target)
		elseif target.State == "Dropped" then
			returnToNest(target)
		end
		guardian.Target = nil
	end
end

local function spawnGuardian(biome)
	local model, height = Visuals.MakeGuardian(biome.Def)
	local position = biome.GuardianHome + Vector3.new(0, height, 0)
	model:PivotTo(CFrame.lookAt(position, position - Vector3.zAxis))
	model.Parent = workspace
	biome.Guardian = {
		Model = model,
		Position = position,
		Name = biome.Def.GuardianName,
		Facing = -Vector3.zAxis,
		Phase = math.random() * 6,
		Sleep = model.PrimaryPart:FindFirstChild("SleepGui"),
	}
end

--------------------------------------------------------------------------------
-- Bonk bat: hit a player who's carrying an egg to make them drop it
--------------------------------------------------------------------------------
local BAT_SWING_SOUND = "rbxasset://sounds/swordslash.wav"
local BAT_HIT_SOUND = "rbxasset://sounds/swordlunge.wav"
local BAT_EQUIP_SOUND = "rbxasset://sounds/unsheath.wav"

local function playSound(parent, soundId, volume, speed)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMaxDistance = 80
	sound.Parent = parent
	sound:Play()
	task.delay(3, function()
		sound:Destroy()
	end)
end

-- Cartoon "BONK!" that pops over the victim's head.
local function bonkPopup(character)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BonkPopup"
	gui.Size = UDim2.fromOffset(160, 70)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.4, 0.4)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "BONK!"
	label.TextColor3 = Color3.fromRGB(255, 225, 60)
	label.TextStrokeColor3 = Color3.fromRGB(120, 40, 0)
	label.TextStrokeTransparency = 0
	label.Rotation = math.random(-15, 15)
	label.Parent = gui
	gui.Parent = head
	TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
	task.delay(0.55, function()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.fromScale(0.5, 0.1) }):Play()
	end)
	task.delay(0.9, function()
		gui:Destroy()
	end)
end

local function bonk(attacker, tool)
	local aState = states[attacker]
	local aRoot = getRoot(attacker)
	if not aState or not aRoot then
		return
	end
	local t = now()
	if t - aState.LastBonk < Config.BonkCooldown then
		return
	end
	aState.LastBonk = t

	-- Swing: the default character Animate script plays its slash animation
	-- whenever a StringValue named "toolanim" appears in the equipped tool.
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	task.delay(0.5, function()
		anim:Destroy()
	end)
	local handle = tool:FindFirstChild("Handle")
	if handle then
		playSound(handle, BAT_SWING_SOUND, 0.6, 1.1)
	end

	-- Hit lands a moment into the swing
	task.wait(0.12)
	aRoot = getRoot(attacker)
	if not aRoot then
		return
	end
	for victim, vState in pairs(states) do
		if victim ~= attacker then
			local vRoot = getRoot(victim)
			if vRoot then
				local offset = vRoot.Position - aRoot.Position
				local distance = offset.Magnitude
				if distance <= Config.BonkRange and (distance < 1 or aRoot.CFrame.LookVector:Dot(offset.Unit) > 0.2) then
					bonkPopup(victim.Character)
					playSound(vRoot, BAT_HIT_SOUND, 0.8, 0.8)
					if vState.Carrying then
						local rarity = vState.Carrying.Rarity
						dropCarried(victim)
						stun(victim, Config.BonkStunTime, Config.BonkStunSpeed)
						notify(victim, "💥 " .. attacker.DisplayName .. " bonked you! You dropped your egg!", RED)
						notify(attacker, "💥 Bonk! " .. victim.DisplayName .. " dropped a " .. rarity .. " Egg!", ORANGE)
					end
				end
			end
		end
	end
end

-- A wooden bat held upright: grip tape handle, knob, and a thick barrel.
local function makeBat()
	local tool = Instance.new("Tool")
	tool.Name = "Bonk Bat"
	tool.ToolTip = "Hit egg carriers to make them drop it"
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.8, 0)

	local wood = Color3.fromRGB(205, 150, 90)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 2.4, 0.35)
	handle.Color = Color3.fromRGB(35, 35, 40)
	handle.Material = Enum.Material.Fabric
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local function piece(name, shape, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.CFrame = handle.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		p.Parent = tool
	end
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X; stand them up
	piece("Knob", Enum.PartType.Cylinder, Vector3.new(0.25, 0.6, 0.6), CFrame.new(0, -1.25, 0) * upright, wood, Enum.Material.Wood)
	piece("Taper", Enum.PartType.Cylinder, Vector3.new(0.9, 0.5, 0.5), CFrame.new(0, 1.6, 0) * upright, wood, Enum.Material.Wood)
	piece("Barrel", Enum.PartType.Cylinder, Vector3.new(2.6, 0.75, 0.75), CFrame.new(0, 3.2, 0) * upright, wood, Enum.Material.Wood)
	piece("Cap", Enum.PartType.Ball, Vector3.new(0.75, 0.75, 0.75), CFrame.new(0, 4.5, 0), wood, Enum.Material.Wood)
	piece("Stripe", Enum.PartType.Cylinder, Vector3.new(0.2, 0.78, 0.78), CFrame.new(0, 3.9, 0) * upright, Color3.fromRGB(220, 50, 50), Enum.Material.SmoothPlastic)
	return tool, handle
end

local function giveBat(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild("Bonk Bat") then
		return
	end
	local tool, handle = makeBat()
	tool.Activated:Connect(function()
		bonk(player, tool)
	end)
	tool.Equipped:Connect(function()
		playSound(handle, BAT_EQUIP_SOUND, 0.4)
	end)
	tool.Parent = backpack
end

--------------------------------------------------------------------------------
-- Characters
--------------------------------------------------------------------------------
local function onCharacter(player, char)
	local state = states[player]
	if not state then
		return
	end
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root then
		return
	end
	applyWalkSpeed(player)
	hum.Died:Connect(function()
		dropCarried(player)
	end)
	task.delay(0.15, function()
		if char.Parent and states[player] then
			char:PivotTo(state.Plot.SpawnCFrame)
		end
	end)
	giveBat(player)
end

--------------------------------------------------------------------------------
-- Loops
--------------------------------------------------------------------------------
-- Deposits carried eggs at home and runs the treadmills.
local function fastLoop()
	while true do
		local dt = task.wait(0.2)
		for player, state in pairs(states) do
			local root = getRoot(player)
			if root then
				local rec = state.Carrying
				if rec and isInsidePlot(state.Plot, root.Position) then
					local index = freeSlot(state)
					if index then
						local wasHunted = rec.HomeBiome ~= nil
						local stolenFrom = rec.OriginalOwner
						local stolenName = rec.StolenFromName
						local takenFrom = rec.TakenFrom
						releaseCarry(player)
						endHunt(rec)
						if stolenFrom == player then
							rec.Stolen = false -- took back your own egg
						end
						rec.OriginalOwner = nil
						rec.StolenFromName = nil
						placeEggInBase(player, index, rec)
						if rec.Stolen then
							local pct = math.floor(Config.StolenShinyChance * 100)
							notify(player, "😈 Stole a " .. rec.Rarity .. " Egg from " .. (stolenName or "someone") .. "! " .. pct .. "% shiny chance!", ORANGE)
						elseif wasHunted then
							notify(player, "🏠 Made it home! " .. rec.Rarity .. " Egg is incubating.", GREEN)
						else
							notify(player, rec.Rarity .. " Egg is incubating. Guard it!", GREEN)
						end
						if takenFrom and takenFrom ~= player then
							onEggStolen(player, takenFrom, rec.Rarity)
							addStat(state, "Stolen")
						elseif wasHunted then
							addStat(state, "Collected")
						end
					elseif now() - state.LastFullWarn > 3 then
						state.LastFullWarn = now()
						notify(player, "Your pen is full! Sell or fuse pets to make room.", RED)
					end
				end

				-- Training: the client locks you onto your treadmill and plays the run
				-- animation after telling us "start"; we only count it while you're
				-- actually on the belt.
				-- stop training if you pick up an egg, or wander off the treadmill for
				-- more than a moment (small position hiccups are ignored)
				if state.Training then
					local near = (root.Position - state.Plot.Treadmill.Position).Magnitude < 25
					state.OffTreadTime = if near then 0 else (state.OffTreadTime or 0) + dt
					if state.Carrying or state.OffTreadTime > 2 then
						state.Training = false
					end
				end
				if state.Training then
					state.TreadProgress += dt
					local interval = Config.TreadmillInterval(state.Profile.Speed)
					if state.TreadProgress >= interval then
						state.TreadProgress = 0
						local gain = Config.TreadmillGain(state.Profile.Speed) * treadmillLevel(state).Mult * (if state.Passes.DoubleSpeedPass then 2 else 1)
						addSpeed(state, gain)
					end
					local nextInterval = Config.TreadmillInterval(state.Profile.Speed)
					player:SetAttribute("OnTreadmill", true)
					player:SetAttribute("TrainGain", Config.TreadmillGain(state.Profile.Speed) * treadmillLevel(state).Mult * (if state.Passes.DoubleSpeedPass then 2 else 1))
					player:SetAttribute("TrainNext", math.max(0, nextInterval - state.TreadProgress))
					setTreadmillStatus(state, true, player:GetAttribute("TrainGain") / math.max(nextInterval, 0.01))
				else
					player:SetAttribute("OnTreadmill", nil)
					player:SetAttribute("TrainNext", nil)
					setTreadmillStatus(state, false)
				end
			end
		end
	end
end

local function tickLoop()
	while true do
		local dt = task.wait(1)
		local t = now()

		-- Regrow nest eggs
		for _, biome in ipairs(map.Biomes) do
			for _, spot in ipairs(biome.Spots) do
				if not spot.Egg and spot.NextSpawn and t >= spot.NextSpawn then
					spawnWildEgg(biome, spot)
				end
			end
		end

		for player, state in pairs(states) do
			local income = 0
			local treat = activeTreat(state)
			local growth = if treat then treat.Growth else 1
			for i = 1, Config.MaxSlots do
				local slot = state.Nest[i]
				if slot then
					if slot.Kind == "Egg" then
						slot.Egg.Remaining -= dt * (if state.Passes.FastHatchPass then 2 else 1)
						if slot.Egg.Remaining <= 0 then
							hatch(player, i)
						else
							refreshEggLabel(slot.Egg)
							if slot.Egg.Remaining <= 6 then
								wobbleEgg(slot.Egg)
							end
						end
					else
						-- growing up: age the pet, rebuild it bigger when it reaches a new stage
						local data = slot.Data
						local before = Config.PetStage(data)
						if before < #Config.Stages then
							data.Age = (data.Age or 0) + dt * growth
							local after = Config.PetStage(data)
							if after ~= before then
								removeCreature(state, i)
								spawnCreature(player, i, data)
								local stageName = Config.Stages[after].Name
								notify(player, "🌱 Your " .. Config.CreatureTitle(data) .. " grew into " .. (if after == #Config.Stages then "an " else "a ") .. stageName .. "! (" .. string.format("%.1f kg", Config.PetWeight(data)) .. ")", GREEN)
							end
						end
						local current = state.Nest[i]
						if current and current.Model and current.Model.PrimaryPart then
							Visuals.RefreshPetLabel(current.Model.PrimaryPart, data)
							local sell = current.Model.PrimaryPart:FindFirstChild("SellPrompt")
							if sell then
								sell.ObjectText = Config.CreatureTitle(data) .. " (" .. Util.Money(Config.SellValue(data)) .. ")"
							end
						end
						income += Config.CreatureIncome(data)
					end
				end
			end
			if state.Passes.DoubleCashPass then
				income *= 2
			end
			income *= 1 + (state.IndexBonus or 0)
			if treat then
				income *= 1 + treat.Cash
			end
			if income > 0 then
				setCash(state, state.Profile.Cash + income)
			end
			player:SetAttribute("IncomePerSec", income)

			if state.RevengeOn and t >= state.RevengeUntil then
				setRevenge(state, nil)
				notify(player, "⌛ Your revenge chance ran out.", ORANGE)
			end

			if state.LockActive and t >= state.LockedUntil then
				setLocked(state, false)
				notify(player, "🔓 Your base lock wore off!", ORANGE)
			end
			updateLockLabel(state)
		end
	end
end

--------------------------------------------------------------------------------
-- Plot visuals
--------------------------------------------------------------------------------
local function resetPlot(plot)
	for _, label in ipairs(plot.SignLabels) do
		label.Text = "Empty Base"
	end
	plot.Dome.Transparency = 1
	for _, pad in ipairs({ plot.LockButton, plot.SpeedPad, plot.FusePad }) do
		Visuals.SetLabel(pad, "", "")
	end
	for _, prompt in ipairs({ plot.LockPrompt, plot.SpeedPrompt, plot.FusePrompt }) do
		setPromptAudience(prompt, "Owner", -1)
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function GameService.Init(mapData, notifyEvent, treadmillEvent)
	map = mapData
	notifyRemote = notifyEvent
	hatchRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("Hatched")
	slapRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("Slapped")

	-- treadmill start / stop from the client
	if treadmillEvent then
		treadmillEvent.OnServerEvent:Connect(function(player, action)
			local state = states[player]
			if not state then
				return
			end
			if action == "start" then
				local root = getRoot(player)
				-- lenient check: the client's newest position may not have reached us yet
				if root and not state.Carrying and (root.Position - state.Plot.Treadmill.Position).Magnitude < 25 then
					state.Training = true
					state.OffTreadTime = 0
				end
			elseif action == "stop" then
				state.Training = false
			end
		end)
	end

	eggsFolder = Instance.new("Folder")
	eggsFolder.Name = "Eggs"
	eggsFolder.Parent = workspace
	ringsFolder = Instance.new("Folder")
	ringsFolder.Name = "EggRings"
	ringsFolder.Parent = workspace
	creaturesFolder = Instance.new("Folder")
	creaturesFolder.Name = "Pets"
	creaturesFolder.Parent = workspace

	for _, plot in ipairs(map.Plots) do
		-- the belt carries anyone standing on it toward the back of the base
		for _, pad in ipairs({ plot.LockButton, plot.SpeedPad, plot.FusePad }) do
			Visuals.AddLabel(pad, 3.5)
		end
		plot.LockPrompt = makePrompt(plot.LockButton, "Lock Base", "Base Lock", 0)
		plot.SpeedPrompt = makePrompt(plot.SpeedPad, "Upgrade", "Treadmill", 0.3)
		plot.FusePrompt = makePrompt(plot.FusePad, "Fuse", Config.FuseCount .. " identical pets → 1 bigger pet", 0.5)
		local handlers = {
			[plot.LockPrompt] = onLockPressed,
			[plot.SpeedPrompt] = onBuySpeed,
			[plot.FusePrompt] = onFuse,
		}
		for prompt, handler in pairs(handlers) do
			prompt.Triggered:Connect(function(player)
				if plotOwners[plot.Index] == player then
					handler(player)
				end
			end)
		end
		resetPlot(plot)
	end

	for _, biome in ipairs(map.Biomes) do
		biome.Hunted = {}
		local spots = {}
		for i, position in ipairs(biome.Spots) do
			spots[i] = { Position = position }
		end
		biome.Spots = spots
		spawnGuardian(biome)
		for _, spot in ipairs(spots) do
			spawnWildEgg(biome, spot)
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, biome in ipairs(map.Biomes) do
			updateGuardian(biome, dt)
		end
		-- behind the red line (town and bases) everyone walks at a normal pace;
		-- your full Speed kicks in once you cross into the zones
		for player, state in pairs(states) do
			local root = getRoot(player)
			if root then
				local inTown = root.Position.Z < map.SafeZoneZ
				if inTown ~= state.InTown then
					state.InTown = inTown
					applyWalkSpeed(player)
				end
			end
		end
	end)
	task.spawn(fastLoop)
	task.spawn(tickLoop)
end

function GameService.AddPlayer(player, profile)
	local plot
	for _, p in ipairs(map.Plots) do
		if not plotOwners[p.Index] then
			plot = p
			break
		end
	end
	if not plot then
		player:Kick("This server is full. Please join another one!")
		return
	end
	plotOwners[plot.Index] = player
	plot.Model:SetAttribute("OwnerUserId", player.UserId)

	-- Parent the folder first, then add Cash and then Speed one at a time: the
	-- player list builds its columns in the order stats arrive, and adding them
	-- all at once can put the numbers under the wrong column names.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Value = math.floor(profile.Cash)
	cashValue.Parent = leaderstats
	local speedValue = Instance.new("IntValue")
	speedValue.Name = "Speed"
	speedValue.Value = profile.Speed
	speedValue.Parent = leaderstats

	local state = {
		Player = player,
		Profile = profile,
		Plot = plot,
		Nest = {},
		Carrying = nil,
		CashValue = cashValue,
		SpeedValue = speedValue,
		SessionClock = os.clock(),
		LockActive = false,
		LockedUntil = 0,
		LockReadyAt = 0,
		LastFullWarn = 0,
		LastBonk = 0,
		StunnedUntil = 0,
		StunSpeed = 0,
		TreadProgress = 0,
		Passes = {},
	}
	states[player] = state

	local indexFolder = Instance.new("Folder")
	indexFolder.Name = "PetIndex"
	indexFolder.Parent = player
	state.IndexFolder = indexFolder
	state.IndexBonus = 0
	for name in pairs(profile.Index) do
		if Config.CreatureByName[name] then
			addIndexFlag(state, name)
		else
			profile.Index[name] = nil -- pet was removed from Config
		end
	end
	state.Loading = true

	for _, label in ipairs(plot.SignLabels) do
		label.Text = player.DisplayName .. "'s Base"
	end
	for _, prompt in ipairs({ plot.LockPrompt, plot.SpeedPrompt, plot.FusePrompt }) do
		setPromptAudience(prompt, "Owner", player.UserId)
	end
	refreshSlots(state)
	refreshSpeedPad(state)
	paintTreadmill(state)
	updateLockLabel(state)
	Visuals.SetLabel(plot.FusePad, "FUSE", Config.FuseCount .. " same → 1 bigger", PINK)

	-- Rebuild the saved base
	for key, entry in pairs(profile.Nest) do
		local index = tonumber(key)
		if index and index >= 1 and index <= profile.Slots and type(entry) == "table" and not state.Nest[index] then
			if entry.Kind == "Egg" and Config.RarityById[entry.Rarity] then
				local savedSize = tonumber(entry.PetSize)
				local rec = createEgg(entry.Rarity, tonumber(entry.Remaining), entry.Stolen == true, Config.MutationById[entry.Mutation or ""] and entry.Mutation or nil, if savedSize then math.clamp(savedSize, 0.5, 3) else nil)
				placeEggInBase(player, index, rec)
			elseif entry.Kind == "Creature" and Config.CreatureByName[entry.Name] then
				local def = Config.CreatureByName[entry.Name]
				local tier = math.clamp(tonumber(entry.Tier) or 1, 1, #Config.Tiers)
				local mutation = if Config.MutationById[entry.Mutation or ""] then entry.Mutation else nil
				spawnCreature(player, index, {
					Name = entry.Name,
					Rarity = def.Rarity,
					Shiny = entry.Shiny == true,
					Tier = tier,
					Mutation = mutation,
					-- size 0 came from an old fusing bug: those pets get their normal size back
					Size = if (tonumber(entry.Size) or 0) > 0 then math.clamp(tonumber(entry.Size), 0.5, 3) else 1,
					Age = math.max(0, tonumber(entry.Age) or 0),
				})
			end
		end
	end

	state.Loading = false
	refreshIndexBonus(state)
	showTreat(state)

	-- Game passes
	for _, key in ipairs(PASS_KEYS) do
		local passId = Config.Products[key]
		if passId ~= 0 then
			task.spawn(function()
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
				if ok and owns and states[player] then
					GameService.GrantPass(player, key, true)
				end
			end)
		end
	end

	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

-- Current save data for a player (also used for autosaves).
function GameService.Snapshot(player)
	local state = states[player]
	if not state then
		return nil
	end
	local nest = {}
	for index, slot in pairs(state.Nest) do
		if slot.Kind == "Egg" then
			nest[tostring(index)] = {
				Kind = "Egg",
				Rarity = slot.Egg.Rarity,
				Remaining = math.max(0, math.floor(slot.Egg.Remaining)),
				Stolen = slot.Egg.Stolen,
				Mutation = slot.Egg.Mutation,
				PetSize = slot.Egg.PetSize,
			}
		else
			nest[tostring(index)] = {
				Kind = "Creature",
				Name = slot.Data.Name,
				Shiny = slot.Data.Shiny,
				Tier = slot.Data.Tier or 1,
				Mutation = slot.Data.Mutation,
				Size = slot.Data.Size or 1,
				Age = math.floor(slot.Data.Age or 0),
			}
		end
	end
	state.Profile.Nest = nest
	-- fold this session's play time into the saved total
	local t = os.clock()
	addStat(state, "TimePlayed", math.floor(t - (state.SessionClock or t)))
	state.SessionClock = t - ((t - (state.SessionClock or t)) % 1)
	return state.Profile
end

-- Everything the leaderboards rank, for one player (nil if not loaded).
function GameService.GetLeaderStats(player)
	local state = states[player]
	if not state then
		return nil
	end
	local profile = state.Profile
	local stats = profile.Stats or {}
	local found = 0
	for _ in pairs(profile.Index) do
		found += 1
	end
	return {
		Cash = profile.Cash,
		Speed = profile.Speed,
		TimePlayed = (stats.TimePlayed or 0) + math.floor(os.clock() - (state.SessionClock or os.clock())),
		Hatched = stats.Hatched or 0,
		Stolen = stats.Stolen or 0,
		Collected = stats.Collected or 0,
		Index = found,
		Slapped = stats.Slapped or 0,
	}
end

function GameService.RemovePlayer(player)
	local state = states[player]
	if not state then
		return nil
	end

	-- A carried egg that nobody else owns goes into your base before saving.
	local rec = state.Carrying
	if rec and not rec.OriginalOwner then
		local index = freeSlot(state)
		if index then
			releaseCarry(player)
			endHunt(rec)
			placeEggInBase(player, index, rec)
		end
	end
	dropCarried(player)

	-- Anyone carrying this player's stolen eggs now just keeps them.
	for _, other in pairs(eggs) do
		if other.OriginalOwner == player then
			other.OriginalOwner = nil
		end
		if other.TakenFrom == player then
			other.TakenFrom = nil
		end
	end
	for _, otherState in pairs(states) do
		if otherState.RevengeOn == player then
			setRevenge(otherState, nil)
		end
	end
	for _, biome in ipairs(map.Biomes) do
		if biome.Guardian.ChasedPlayer == player then
			biome.Guardian.ChasedPlayer = nil
		end
	end

	local profile = GameService.Snapshot(player)

	-- the empty base goes back to a plain, stopped treadmill
	setTreadmillStatus(state, false)
	paintTreadmill({ Profile = { TreadmillLevel = 1 }, Plot = state.Plot })

	for _, slot in pairs(state.Nest) do
		if slot.Kind == "Egg" then
			destroyEgg(slot.Egg)
		else
			slot.Model:Destroy()
		end
	end
	states[player] = nil
	plotOwners[state.Plot.Index] = nil
	state.Plot.Model:SetAttribute("OwnerUserId", nil)
	resetPlot(state.Plot)
	return profile
end

-- Robux product effects ------------------------------------------------------
function GameService.InstantHatch(player)
	local state = states[player]
	if not state then
		return false
	end
	for _, slot in pairs(state.Nest) do
		if slot.Kind == "Egg" then
			slot.Egg.Remaining = 0
		end
	end
	notify(player, "⚡ Instant Hatch! All your eggs are hatching!", GOLD)
	return true
end

function GameService.EggRain(byPlayer)
	local area = map.RainArea
	for i = 1, Config.EggRainCount do
		local rarity = Util.WeightedPick(Config.Rarities, function(r)
			return Config.EggRainWeights[r.Id] or 0
		end, rng)
		local rec = createEgg(rarity.Id, nil, false, Config.RollMutation(rng, currentLuck()))
		local ground = Vector3.new(rng:NextNumber(-area.HalfWidth, area.HalfWidth), rec.Part.Size.Y / 2 + 0.3, rng:NextNumber(area.MinZ, area.MaxZ))
		rec.Part.CFrame = CFrame.new(ground + Vector3.new(0, 60 + i * 3, 0))
		makeGrabbable(rec, "Rain", Config.EggRainLifetime)
		local tween = TweenService:Create(rec.Part, TweenInfo.new(1.6 + i * 0.1, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = CFrame.new(ground) })
		rec.Tween = tween
		tween:Play()
	end
	notifyAll("🌧️ " .. byPlayer.DisplayName .. " made it rain eggs in town! Grab them!", GOLD)
end

function GameService.GrantSpeed(player, amount)
	local state = states[player]
	if not state then
		return false
	end
	addSpeed(state, amount)
	notify(player, "⚡ +" .. Util.FormatNumber(amount) .. " Speed!", GOLD)
	return true
end

function GameService.GrantPass(player, key, silent)
	local state = states[player]
	if not state then
		return
	end
	state.Passes[key] = true
	player:SetAttribute("Pass_" .. key, true)
	if key == "DoubleSpeedPass" then
		refreshSpeedPad(state)
	end
	if not silent then
		for _, item in ipairs(Config.Shop) do
			if item.Key == key then
				notify(player, item.Icon .. " " .. item.Title .. " unlocked! Thanks for the support!", GOLD)
			end
		end
	end
end

function GameService.ActivateServerLuck(mult, byPlayer)
	local t = now()
	if t < serverLuck.Until and serverLuck.Mult >= mult then
		serverLuck.Until += Config.ServerLuckDuration -- same or weaker luck: extend the timer
	else
		local remaining = math.max(0, serverLuck.Until - t)
		serverLuck.Mult = mult
		serverLuck.Until = t + Config.ServerLuckDuration + remaining
	end
	workspace:SetAttribute("ServerLuck", serverLuck.Mult)
	workspace:SetAttribute("ServerLuckUntil", serverLuck.Until)
	notifyAll("🍀 " .. byPlayer.DisplayName .. " activated " .. mult .. "x Server Luck! Rarer eggs are spawning!", Color3.fromRGB(120, 255, 140))
	-- re-roll every egg still sitting in the nests so the luck kicks in right away
	for _, biome in ipairs(map.Biomes) do
		for _, spot in ipairs(biome.Spots) do
			if spot.Egg and spot.Egg.State == "Wild" then
				destroyEgg(spot.Egg)
				spot.Egg = nil
				spawnWildEgg(biome, spot)
			end
		end
	end
	return true
end

function GameService.GetSpeed(player)
	local state = states[player]
	return if state then state.Profile.Speed else 0
end

-- Treats (the 🍦 stall in town) ----------------------------------------------
function GameService.BuyTreat(player, key)
	local state = states[player]
	local def = Config.TreatByKey[key]
	if not state or not def then
		return false
	end
	local t = os.clock()
	if t - (state.LastTreatBuy or 0) < 0.4 then
		return false
	end
	state.LastTreatBuy = t
	local cost = Config.TreatCost(def, player:GetAttribute("IncomePerSec") or 0)
	if not trySpend(state, cost) then
		notify(player, "You need " .. Util.Money(cost) .. " for a " .. def.Name .. ".", RED)
		return false
	end
	local current = state.Profile.Treat
	local now = os.time()
	local maxUntil = now + Config.TreatMaxMinutes * 60
	if current and current.Key == key and current.Until > now then
		current.Until = math.min(current.Until + def.Minutes * 60, maxUntil)
		notify(player, def.Icon .. " More " .. def.Name .. "! " .. Util.FormatTime(current.Until - now) .. " left.", GOLD)
	else
		state.Profile.Treat = { Key = key, Until = now + def.Minutes * 60 }
		notify(player, def.Icon .. " " .. def.Name .. "! Pets grow " .. def.Growth .. "x faster and earn +" .. math.floor(def.Cash * 100 + 0.5) .. "% for " .. def.Minutes .. " min.", GOLD)
	end
	showTreat(state)
	return true
end

-- A free treat (codes, rewards). Replaces or extends like buying one.
function GameService.GrantTreat(player, key, minutes)
	local state = states[player]
	local def = Config.TreatByKey[key]
	if not state or not def then
		return false
	end
	local now = os.time()
	local length = (minutes or def.Minutes) * 60
	local current = state.Profile.Treat
	if current and current.Key == key and current.Until > now then
		current.Until = math.min(current.Until + length, now + Config.TreatMaxMinutes * 60)
	else
		state.Profile.Treat = { Key = key, Until = now + length }
	end
	showTreat(state)
	return true
end

-- Daily reward helpers (used by DailyRewardService) --------------------------
function GameService.GetProfile(player)
	local state = states[player]
	return if state then state.Profile else nil
end

function GameService.GrantCash(player, amount)
	local state = states[player]
	if not state then
		return false
	end
	setCash(state, state.Profile.Cash + amount)
	return true
end

-- Drops a fresh egg straight into the player's pet pen. Fails if the pen is full.
function GameService.GiveBaseEgg(player, rarityId)
	local state = states[player]
	if not state or not Config.RarityById[rarityId] then
		return false
	end
	local index = freeSlot(state)
	if not index then
		return false
	end
	local rec = createEgg(rarityId, nil, false, Config.RollMutation(rng, currentLuck()))
	placeEggInBase(player, index, rec)
	return true, rec.Mutation
end

--------------------------------------------------------------------------------
-- Admin / testing helpers (used by AdminService)
--------------------------------------------------------------------------------
GameService.Admin = {}

function GameService.Admin.AddCash(player, amount)
	local state = states[player]
	if state then
		setCash(state, math.max(0, state.Profile.Cash + amount))
	end
end

function GameService.Admin.SetSpeed(player, value)
	local state = states[player]
	if state then
		state.Profile.Speed = math.max(0, math.floor(value))
		state.SpeedValue.Value = state.Profile.Speed
		applyWalkSpeed(player)
	end
end

function GameService.Admin.GiveEgg(player, rarityId, mutation)
	local state = states[player]
	if not state or not Config.RarityById[rarityId] or not getRoot(player) then
		return false
	end
	if state.Carrying then
		destroyEgg(releaseCarry(player))
	end
	local rec = createEgg(rarityId, nil, false, mutation)
	return startCarry(player, rec)
end

function GameService.Admin.GivePet(player, nameOrRarity, shiny, mutation)
	local state = states[player]
	if not state then
		return false, "not loaded"
	end
	local def = Config.CreatureByName[nameOrRarity]
	if not def and Config.RarityById[nameOrRarity] then
		local list = Config.RarityById[nameOrRarity].Creatures
		def = list[rng:NextInteger(1, #list)]
	end
	if not def then
		return false, "no pet or rarity called " .. tostring(nameOrRarity)
	end
	local index = freeSlot(state)
	if not index then
		return false, "your base is full"
	end
	spawnCreature(player, index, { Name = def.Name, Rarity = def.Rarity, Shiny = shiny == true, Tier = 1, Mutation = mutation, Size = Config.RollSize(rng), Age = 0 })
	return true, def.Name
end

function GameService.Admin.MaxSlots(player)
	local state = states[player]
	if state then
		state.Profile.Slots = Config.MaxSlots
		refreshSlots(state)
	end
end

function GameService.Admin.RefillNests()
	for _, biome in ipairs(map.Biomes) do
		for _, spot in ipairs(biome.Spots) do
			if spot.Egg and spot.Egg.State == "Wild" then
				destroyEgg(spot.Egg)
				spot.Egg = nil
			end
			if not spot.Egg then
				spawnWildEgg(biome, spot)
			end
		end
	end
end

function GameService.Admin.Teleport(player, zone)
	local state = states[player]
	local char = player.Character
	if not state or not char then
		return false
	end
	zone = string.lower(zone or "")
	if zone == "" or zone == "town" or zone == "home" or zone == "base" then
		char:PivotTo(state.Plot.SpawnCFrame)
		return true
	end
	for _, biome in ipairs(map.Biomes) do
		if string.lower(biome.Def.Id) == zone or string.lower(biome.Def.Name) == zone or tostring(biome.Index) == zone then
			local pos = biome.Center + Vector3.new(0, 5, -60)
			char:PivotTo(CFrame.lookAt(pos, pos + Vector3.zAxis))
			return true
		end
	end
	return false
end

function GameService.Admin.Reset(player)
	local state = states[player]
	if not state then
		return
	end
	if state.Carrying then
		destroyEgg(releaseCarry(player))
	end
	for index, slot in pairs(state.Nest) do
		if slot.Kind == "Egg" then
			destroyEgg(slot.Egg)
		else
			slot.Model:Destroy()
		end
		state.Nest[index] = nil
	end
	state.Profile.Slots = Config.StartingSlots
	state.Profile.SpeedBuys = 0
	state.Profile.TreadmillLevel = 1
	paintTreadmill(state)
	setCash(state, Config.StartingCash)
	state.Profile.Index = {}
	state.Profile.Treat = nil
	showTreat(state)
	state.IndexFolder:ClearAllChildren()
	refreshIndexBonus(state)
	GameService.Admin.SetSpeed(player, Config.StartingSpeed)
	refreshSlots(state)
	refreshSpeedPad(state)
end

-- Ages every pet in your base to the next stage (or straight to Adult)
function GameService.Admin.Grow(player, toAdult)
	local state = states[player]
	if not state then
		return
	end
	for index = 1, Config.MaxSlots do
		local slot = state.Nest[index]
		if slot and slot.Kind == "Creature" then
			local data = slot.Data
			local stage = Config.PetStage(data)
			local target = if toAdult then #Config.Stages else math.min(stage + 1, #Config.Stages)
			data.Age = (target - 1) * Config.GrowTime(data.Rarity)
			removeCreature(state, index)
			spawnCreature(player, index, data)
		end
	end
end

function GameService.Admin.SetTreadmill(player, level)
	local state = states[player]
	if state then
		state.Profile.TreadmillLevel = math.clamp(math.floor(level), 1, #Config.TreadmillLevels)
		paintTreadmill(state)
		refreshSpeedPad(state)
	end
end

function GameService.Admin.HatchAll(player)
	return GameService.InstantHatch(player)
end

function GameService.IsReady(player)
	return states[player] ~= nil
end

return GameService
