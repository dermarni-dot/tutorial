-- Config (ModuleScript) — ReplicatedStorage.Shared.Config
-- Every tunable number in the game lives here.

local Config = {}

--------------------------------------------------------------------------------
-- Economy
--------------------------------------------------------------------------------
Config.StartingCash = 0
-- Every base has one open pen that holds this many eggs and pets (no slots to buy)
Config.MaxSlots = 24
Config.StartingSlots = Config.MaxSlots
Config.SellSeconds = 45 -- a pet sells for this many seconds of its income

--------------------------------------------------------------------------------
-- Speed
-- Walk speed comes from your Speed stat (see Config.WalkSpeed below).
-- Carrying an egg multiplies it by CarrySpeedMultiplier.
--------------------------------------------------------------------------------
-- Speed stat can grow into the millions. Walk speed climbs faster the more
-- tenfolds of Speed you have, so every upgrade feels quicker:
-- 5 -> 49, 300 -> 100, 1K -> 119, 11K -> 162, 200K -> 222, 1M -> 260,
-- 25M -> 344, 100M -> 384, 2.5B -> 485, 50B -> 589 (capped at 650).
Config.BaseWalkSpeed = 32
Config.WalkPerTenfold = 20 -- extra walk speed every time your Speed goes x10...
Config.WalkCurve = 3 -- ...plus this x (tenfolds squared), so later tenfolds add more
Config.MaxWalkSpeed = 650
Config.GuardianEdge = 0.995 -- guardians run this fraction of your carry speed at their zone's SpeedNeeded
Config.CarrySpeedMultiplier = 0.9
Config.StartingSpeed = 5 -- enough to outrun the first guardian

-- Treadmill: step on it to auto-run. Every second you gain
-- (1 + TreadmillGainScale x the square root of your Speed) x your treadmill tier.
-- The square root keeps it from snowballing: going 10x faster takes about 3x
-- longer each time, so every new zone takes a few minutes of training with the
-- matching tier (1K on Basic ~3.5 min, 1M on Diamond ~7 min, 50B on Celestial ~12 min).
Config.TreadmillBaseInterval = 1
Config.TreadmillSlowdown = 4
Config.TreadmillMaxInterval = 1 -- a gain every second
Config.TreadmillGainScale = 0.3
Config.TreadmillBeltSpeed = 12 -- how fast the belt stripes scroll

-- Treadmill upgrades: the gold pad in your base buys better treadmills with
-- cash. Each one multiplies the Speed your treadmill gives, and looks fancier:
--   Glow  = brightness of the light under the belt
--   Frame = frame material (Metal if not set)
--   Fx    = sparkles rising off the belt { Rate, Size, Speed, Fire = true for flames }
--   Halo  = a ring of orbs spinning above the treadmill
--   Rainbow = belt stripes cycle through every color
Config.TreadmillLevels = {
	{ Name = "Basic", Mult = 1, Cost = 0, Color = Color3.fromRGB(255, 120, 120), Glow = 0 },
	{ Name = "Bronze", Mult = 2, Cost = 2500, Color = Color3.fromRGB(205, 127, 50), Glow = 0.4 },
	{ Name = "Silver", Mult = 4, Cost = 40000, Color = Color3.fromRGB(200, 205, 215), Glow = 0.6, Fx = { Rate = 3, Size = 0.3, Speed = 2 } },
	{ Name = "Gold", Mult = 8, Cost = 500000, Color = Color3.fromRGB(255, 200, 50), Glow = 0.8, Frame = "Foil", Fx = { Rate = 5, Size = 0.35, Speed = 2 } },
	{ Name = "Diamond", Mult = 16, Cost = 8000000, Color = Color3.fromRGB(110, 230, 255), Glow = 1, Frame = "Glass", Fx = { Rate = 8, Size = 0.4, Speed = 3 } },
	{ Name = "Emerald", Mult = 32, Cost = 150000000, Color = Color3.fromRGB(60, 230, 120), Glow = 1.2, Frame = "Glass", Fx = { Rate = 10, Size = 0.45, Speed = 3 } },
	{ Name = "Cosmic", Mult = 64, Cost = 3000000000, Color = Color3.fromRGB(190, 110, 255), Glow = 1.4, Frame = "Glass", Fx = { Rate = 14, Size = 0.5, Speed = 4 }, Halo = true },
	{ Name = "Galaxy", Mult = 128, Cost = 60000000000, Color = Color3.fromRGB(90, 130, 255), Glow = 1.6, Frame = "Glass", Fx = { Rate = 16, Size = 0.55, Speed = 4 }, Halo = true },
	{ Name = "Nebula", Mult = 256, Cost = 1200000000000, Color = Color3.fromRGB(255, 110, 200), Glow = 1.8, Frame = "Glass", Fx = { Rate = 18, Size = 0.8, Speed = 2.5 }, Halo = true },
	{ Name = "Supernova", Mult = 512, Cost = 25000000000000, Color = Color3.fromRGB(255, 150, 40), Glow = 2, Frame = "Foil", Fx = { Rate = 22, Size = 0.9, Speed = 6, Fire = true }, Halo = true },
	{ Name = "Quantum", Mult = 1024, Cost = 500000000000000, Color = Color3.fromRGB(60, 255, 230), Glow = 2.2, Frame = "Glass", Fx = { Rate = 26, Size = 0.5, Speed = 8 }, Halo = true },
	{ Name = "Celestial", Mult = 2048, Cost = 10000000000000000, Color = Color3.fromRGB(255, 245, 200), Glow = 2.5, Frame = "Foil", Fx = { Rate = 30, Size = 0.7, Speed = 5 }, Halo = true, Rainbow = true },
}

-- (old Speed pad settings, no longer used by the base)
Config.SpeedShopAmount = 5 -- minimum; the pad gives 10% of your Speed once that's more
Config.SpeedShopPercent = 0.10
Config.SpeedShopBaseCost = 150
Config.SpeedShopGrowth = 1.6

--------------------------------------------------------------------------------
-- Prompts (seconds to hold E)
--------------------------------------------------------------------------------
Config.NestGrabHoldTime = 0.5 -- taking an egg from a guarded nest
Config.BaseStealHoldTime = 1.25 -- taking an incubating egg from someone's base
Config.CarrierStealHoldTime = 0.6 -- snatching an egg off another player's head
Config.GrabHoldTime = 0.4 -- picking up a dropped / rained egg
Config.PromptRange = 10

--------------------------------------------------------------------------------
-- Guardians
--------------------------------------------------------------------------------
Config.GuardianCatchRange = 7
Config.SlapFlightTime = 1.1 -- seconds you fly through the air after a guardian slaps you, before landing back home
Config.GuardianStunTime = 1.5
Config.GuardianStunSpeed = 4

--------------------------------------------------------------------------------
-- Nest lock
--------------------------------------------------------------------------------
Config.LockDuration = 60 -- seconds the forcefield stays up
Config.LockCooldown = 90 -- seconds after it drops before it can be used again

--------------------------------------------------------------------------------
-- Bonk bat
--------------------------------------------------------------------------------
Config.BonkRange = 9
Config.BonkCooldown = 0.8
Config.BonkStunTime = 1.2
Config.BonkStunSpeed = 5

--------------------------------------------------------------------------------
-- Hatching, shinies and fusing
--------------------------------------------------------------------------------
Config.ShinyChance = 0.05
Config.StolenShinyChance = 0.25 -- eggs stolen from another player are more likely to hatch shiny
Config.ShinyMultiplier = 3
Config.AnnounceHatchRarities = { Legendary = true, Mythic = true, Divine = true, Secret = true }
Config.AnnounceSpawnRarities = { Legendary = true, Mythic = true, Divine = true, Secret = true }

--------------------------------------------------------------------------------
-- Growing up: pets hatch as babies and grow while they sit in your base.
-- Each stage lasts rarity.HatchTime * GrowthFactor seconds. Older = more cash.
--------------------------------------------------------------------------------
Config.GrowthFactor = 6
Config.Stages = {
	{ Name = "Baby", Mult = 1, Scale = 0.6, Weight = 0.25 },
	{ Name = "Juvenile", Mult = 1.5, Scale = 0.75, Weight = 0.5 },
	{ Name = "Adolescent", Mult = 2.2, Scale = 0.88, Weight = 0.75 },
	{ Name = "Adult", Mult = 3, Scale = 1, Weight = 1 },
}

-- Size: every pet rolls a size when it hatches. It sets the adult weight
-- (BaseWeight of its rarity x size), how big it looks, and a small cash bonus.
Config.BaseWeight = { Common = 8, Uncommon = 12, Rare = 18, Epic = 26, Legendary = 38, Mythic = 55, Divine = 75, Secret = 100 }
Config.SizeIncomePower = 0.5 -- cash bonus = size ^ this (a 2x size pet earns ~1.4x)

function Config.RollSize(rng)
	local r = rng:NextNumber()
	if r < 0.01 then
		return math.floor(rng:NextNumber(2, 3) * 100) / 100 -- HUGE
	elseif r < 0.08 then
		return math.floor(rng:NextNumber(1.35, 2) * 100) / 100 -- big
	end
	return math.floor(rng:NextNumber(0.75, 1.3) * 100) / 100
end

function Config.GrowTime(rarityId)
	local rarity = Config.RarityById[rarityId]
	return (if rarity then rarity.HatchTime else 10) * Config.GrowthFactor
end

-- Stage index (1..4) from the pet's age in seconds
function Config.PetStage(data)
	local age = data.Age or 0
	local stage = 1 + math.floor(age / Config.GrowTime(data.Rarity))
	return math.clamp(stage, 1, #Config.Stages)
end

-- Seconds until the next stage (nil when fully grown)
function Config.TimeToGrow(data)
	local stage = Config.PetStage(data)
	if stage >= #Config.Stages then
		return nil
	end
	return stage * Config.GrowTime(data.Rarity) - (data.Age or 0)
end

function Config.PetWeight(data)
	local stage = Config.Stages[Config.PetStage(data)]
	local base = Config.BaseWeight[data.Rarity] or 10
	return base * (data.Size or 1) * stage.Weight
end

-- How big the model looks compared with a normal-size adult
function Config.PetVisualScale(data)
	local stage = Config.Stages[Config.PetStage(data)]
	return stage.Scale * (data.Size or 1) ^ (1 / 3)
end

Config.FuseCount = 3 -- this many identical pets fuse into one of the next tier
Config.Tiers = {
	{ Prefix = "", Multiplier = 1, Scale = 1 },
	{ Prefix = "Big ", Multiplier = 4, Scale = 1.35 },
	{ Prefix = "Huge ", Multiplier = 16, Scale = 1.7 },
}

--------------------------------------------------------------------------------
-- Mutations: special effects that can spawn on wild eggs. The pet that hatches
-- keeps the mutation and earns Mult times more. Chance is per egg spawn
-- (server luck raises it). Rarest listed first.
--------------------------------------------------------------------------------
Config.Mutations = {
	{ Id = "Galaxy", Icon = "🌌", Chance = 0.003, Mult = 10, Color = Color3.fromRGB(120, 70, 220) },
	{ Id = "Rainbow", Icon = "🌈", Chance = 0.005, Mult = 7, Color = Color3.fromRGB(255, 120, 200) },
	{ Id = "Lava", Icon = "🔥", Chance = 0.012, Mult = 4, Color = Color3.fromRGB(255, 100, 30) },
	{ Id = "Frozen", Icon = "❄️", Chance = 0.012, Mult = 4, Color = Color3.fromRGB(150, 220, 255) },
	{ Id = "Electric", Icon = "⚡", Chance = 0.015, Mult = 3.5, Color = Color3.fromRGB(255, 240, 80) },
	{ Id = "Diamond", Icon = "💎", Chance = 0.02, Mult = 3, Color = Color3.fromRGB(120, 230, 255) },
	{ Id = "Golden", Icon = "🌟", Chance = 0.05, Mult = 2, Color = Color3.fromRGB(255, 200, 50) },
}
Config.AnnounceMutations = { Galaxy = true, Rainbow = true }
Config.MutationById = {}
for _, m in ipairs(Config.Mutations) do
	Config.MutationById[m.Id] = m
end

-- Rolls a mutation for a new egg (or nil). luck is the server luck multiplier.
function Config.RollMutation(rng, luck)
	local boost = math.sqrt(luck or 1)
	for _, m in ipairs(Config.Mutations) do
		if rng:NextNumber() < m.Chance * boost then
			return m.Id
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Dropped eggs & Egg Rain
--------------------------------------------------------------------------------
Config.DroppedEggLifetime = 20
Config.EggRainCount = 12
Config.EggRainLifetime = 30
Config.EggRainWeights = { Common = 20, Uncommon = 40, Rare = 25, Epic = 10, Legendary = 4, Mythic = 1, Divine = 0.2, Secret = 0.02 }

--------------------------------------------------------------------------------
-- Robux products. Leave at 0 until you create them on the Creator Dashboard.
-- Buttons for products set to 0 are hidden automatically.
--------------------------------------------------------------------------------
Config.Products = {
	-- Game Passes (one-time, permanent)
	DoubleCashPass = 0, -- 2x cash from pets
	DoubleSpeedPass = 0, -- 2x Speed from the treadmill and the speed shop
	FastHatchPass = 0, -- eggs hatch 2x faster
	-- Developer Products (can be bought again and again)
	ServerLuck2x = 0, -- 2x rarer eggs for everyone in the server, 15 min
	ServerLuck5x = 0, -- 5x rarer eggs for everyone in the server, 15 min
	ServerLuck10x = 0, -- 10x rarer eggs for everyone in the server, 15 min
	InstantHatch = 0, -- hatches every egg in your base now
	EggRain = 0, -- drops free eggs in the plaza for everyone
	SpeedBoost = 0, -- +25% of your Speed (minimum SpeedBoostAmount)
}
Config.SpeedBoostAmount = 25 -- minimum Speed from the boost
Config.SpeedBoostPercent = 0.25 -- the boost gives this share of your current Speed (or the minimum, if higher)

function Config.SpeedBoostFor(currentSpeed)
	return math.max(Config.SpeedBoostAmount, math.floor(currentSpeed * Config.SpeedBoostPercent))
end
Config.ServerLuckDuration = 15 * 60

-- What the in-game Shop shows. Price is only a label for when the real price
-- can't be loaded (e.g. the ID is still 0); set real prices on the Creator Dashboard.
Config.Shop = {
	{ Tab = "Passes", Key = "DoubleCashPass", Pass = true, Title = "2x Cash", Icon = "💰", Desc = "Every pet earns double cash, forever.", Price = 199, Color = Color3.fromRGB(80, 200, 100) },
	{ Tab = "Passes", Key = "DoubleSpeedPass", Pass = true, Title = "2x Speed Gain", Icon = "⚡", Desc = "Double the Speed you gain from your treadmill.", Price = 149, Color = Color3.fromRGB(255, 190, 50) },
	{ Tab = "Passes", Key = "FastHatchPass", Pass = true, Title = "2x Hatch Speed", Icon = "🐣", Desc = "Your eggs hatch twice as fast.", Price = 99, Color = Color3.fromRGB(255, 140, 190) },
	{ Tab = "Luck", Key = "ServerLuck2x", Luck = 2, Title = "2x Server Luck", Icon = "🍀", Desc = "Rarer eggs spawn for the whole server for 15 minutes.", Price = 49, Color = Color3.fromRGB(110, 220, 120) },
	{ Tab = "Luck", Key = "ServerLuck5x", Luck = 5, Title = "5x Server Luck", Icon = "🍀", Desc = "Much rarer eggs for the whole server for 15 minutes.", Price = 149, Color = Color3.fromRGB(80, 190, 255) },
	{ Tab = "Luck", Key = "ServerLuck10x", Luck = 10, Title = "10x Server Luck", Icon = "🌈", Desc = "Mythic hunting time! Huge luck for everyone for 15 minutes.", Price = 299, Color = Color3.fromRGB(200, 110, 255) },
	{ Tab = "Boosts", Key = "InstantHatch", Title = "Instant Hatch", Icon = "⏩", Desc = "Hatch every egg in your base right now.", Price = 25, Color = Color3.fromRGB(255, 170, 60) },
	{ Tab = "Boosts", Key = "SpeedBoost", Title = "+25% Speed", Icon = "👟", Desc = "Instantly gain 25% of your Speed (at least 25).", Price = 39, Color = Color3.fromRGB(255, 120, 80), ScalesWithSpeed = true },
	{ Tab = "Boosts", Key = "EggRain", Title = "Egg Rain", Icon = "🌧️", Desc = "Rain free eggs on the plaza for everyone!", Price = 99, Color = Color3.fromRGB(90, 160, 255) },
}

--------------------------------------------------------------------------------
-- Daily streak rewards. Players claim one reward per day from the 🎁 Daily
-- button (days roll over at midnight UTC). Coming back the next day moves you
-- up the streak; missing a day starts you over at Day 1. After Day 7 it loops.
--   Kind = "Cash":  CashMinutes worth of your current income, at least MinCash
--   Kind = "Speed": SpeedPercent of your Speed, at least MinSpeed
--   Kind = "Egg":   an egg of that Rarity drops into your pet pen (it can roll a mutation)
--------------------------------------------------------------------------------
Config.DailyRewards = {
	{ Kind = "Cash", CashMinutes = 5, MinCash = 500 },
	{ Kind = "Cash", CashMinutes = 10, MinCash = 1500 },
	{ Kind = "Speed", SpeedPercent = 0.10, MinSpeed = 10 },
	{ Kind = "Cash", CashMinutes = 20, MinCash = 5000 },
	{ Kind = "Egg", Rarity = "Rare" },
	{ Kind = "Cash", CashMinutes = 30, MinCash = 15000 },
	{ Kind = "Egg", Rarity = "Epic" },
}

--------------------------------------------------------------------------------
-- Treats, sold at the 🍦 stall in town for cash. While a treat is active your
-- pets grow up faster (Growth x) and earn a little more (Cash = +%).
-- One treat at a time: buying the same one adds time (up to TreatMaxMinutes),
-- buying a different one replaces it. Price = CostSeconds of your income,
-- at least MinCost, so treats stay worth it as you get richer.
--------------------------------------------------------------------------------
Config.Treats = {
	{ Key = "Cookie", Name = "Crunchy Cookie", Icon = "🍪", Growth = 1.5, Cash = 0.10, Minutes = 3, CostSeconds = 60, MinCost = 100, Color = Color3.fromRGB(210, 150, 90) },
	{ Key = "Cupcake", Name = "Sprinkle Cupcake", Icon = "🧁", Growth = 2, Cash = 0.15, Minutes = 5, CostSeconds = 180, MinCost = 1000, Color = Color3.fromRGB(255, 140, 190) },
	{ Key = "IceCream", Name = "Triple Ice Cream", Icon = "🍦", Growth = 3, Cash = 0.20, Minutes = 5, CostSeconds = 420, MinCost = 5000, Color = Color3.fromRGB(120, 200, 255) },
	{ Key = "Cake", Name = "Golden Pet Cake", Icon = "🎂", Growth = 5, Cash = 0.25, Minutes = 10, CostSeconds = 1500, MinCost = 25000, Color = Color3.fromRGB(255, 200, 70) },
}
Config.TreatMaxMinutes = 30
Config.TreatByKey = {}
for _, treat in ipairs(Config.Treats) do
	Config.TreatByKey[treat.Key] = treat
end

function Config.TreatCost(treat, incomePerSec)
	return math.max(treat.MinCost, math.floor((incomePerSec or 0) * treat.CostSeconds))
end

--------------------------------------------------------------------------------
-- Codes players can type in the 🎟️ Codes menu. Each works once per player.
-- Rewards: CashMinutes (of the player's income, at least MinCash),
-- Egg = rarity (goes in the pet pen), Treat = treat key, SpeedPercent / MinSpeed.
-- Add a line to make a new code; codes are not case-sensitive.
--------------------------------------------------------------------------------
Config.Codes = {
	RELEASE = { CashMinutes = 10, MinCash = 2500 },
	EGGSTRA = { Egg = "Rare" },
	ZOOM = { SpeedPercent = 0.15, MinSpeed = 50 },
	SWEETTOOTH = { Treat = "Cupcake" },
	PETS499 = { Egg = "Epic" },
}

--------------------------------------------------------------------------------
-- Pet Index: every pet you get is recorded in your 📖 Index. Collecting every
-- pet of a rarity gives a permanent cash bonus on all your pets.
--------------------------------------------------------------------------------
Config.IndexBonusPerRarity = 0.05 -- +5% cash for each completed rarity row

--------------------------------------------------------------------------------
-- Revenge: when someone steals your egg and gets it home, you have RevengeTime
-- seconds to steal any egg back from them for bonus cash (RevengeCashMinutes
-- of your income, at least RevengeMinCash). After a payout you can't get a new
-- revenge chance for RevengeCooldown seconds, so friends can't farm it.
--------------------------------------------------------------------------------
Config.RevengeTime = 5 * 60
Config.RevengeCashMinutes = 5
Config.RevengeMinCash = 1000
Config.RevengeCooldown = 15 * 60

--------------------------------------------------------------------------------
-- Admins: these UserIds can use the Admin panel and "!" chat commands in the
-- live game. The game's owner (or group rank 254+) always can, and everyone can
-- while testing in Roblox Studio.
--------------------------------------------------------------------------------
Config.Admins = {}

--------------------------------------------------------------------------------
-- Saving
--------------------------------------------------------------------------------
Config.DataStoreName = "StealAPetEgg_v2"
Config.AutosaveInterval = 120

--------------------------------------------------------------------------------
-- Rarities and the creatures inside each egg
--------------------------------------------------------------------------------
Config.Rarities = {
	{
		Id = "Common",
		HatchTime = 10,
		Color = Color3.fromRGB(215, 215, 215),
		Creatures = {
			{ Name = "Pebble Pup", Style = "Pup", Income = 1, Color = Color3.fromRGB(150, 140, 130), Pattern = "Spots" },
			{ Name = "Mossling", Style = "Moss", Income = 1, Color = Color3.fromRGB(110, 170, 90) },
			{ Name = "Chirpy", Style = "Bird", Income = 2, Color = Color3.fromRGB(250, 210, 90) },
			{ Name = "Bunbun", Style = "Bunny", Income = 1, Color = Color3.fromRGB(255, 225, 235), Accessory = "Bow" },
			{ Name = "Froggle", Style = "Frog", Income = 2, Color = Color3.fromRGB(120, 210, 90), Pattern = "Spots" },
			{ Name = "Slimey", Style = "Slime", Income = 2, Color = Color3.fromRGB(90, 220, 200) },
			{ Name = "Mochi Hamster", Style = "Hamster", Income = 1, Color = Color3.fromRGB(245, 200, 150), Pattern = "Freckles", PatternColor = Color3.fromRGB(200, 140, 110) },
			{ Name = "Lil Chick", Style = "Chick", Income = 1, Color = Color3.fromRGB(255, 235, 120) },
			{ Name = "Piglet Pip", Style = "Pig", Income = 1, Color = Color3.fromRGB(255, 180, 190), Accessory = "Bow" },
			{ Name = "Woolly Lamb", Style = "Sheep", Income = 1, Color = Color3.fromRGB(250, 245, 235), Accessory = "Bell" },
			{ Name = "Moo Moo", Style = "Cow", Income = 2, Color = Color3.fromRGB(250, 250, 250) },
			{ Name = "Buzzy Bee", Style = "Bee", Income = 2, Color = Color3.fromRGB(255, 210, 60) },
			{ Name = "Dotty Ladybug", Style = "Ladybug", Income = 1, Color = Color3.fromRGB(230, 50, 50) },
			{ Name = "Slowpoke Snail", Style = "Snail", Income = 1, Color = Color3.fromRGB(210, 190, 150) },
			{ Name = "Pinchy Crab", Style = "Crab", Income = 2, Color = Color3.fromRGB(240, 100, 70) },
			{ Name = "Prickles", Style = "Hedgehog", Income = 2, Color = Color3.fromRGB(160, 120, 90) },
			{ Name = "Teddy Bear", Style = "Bear", Income = 1, Color = Color3.fromRGB(180, 130, 90), Accessory = "Bow", Accent = Color3.fromRGB(90, 160, 255) },
			{ Name = "Muddy Pup", Style = "Pup", Income = 1, Color = Color3.fromRGB(140, 100, 70), Pattern = "Spots" },
			{ Name = "Tabby Kitten", Style = "Cat", Income = 2, Color = Color3.fromRGB(230, 160, 90), Pattern = "Stripes", Plain = true },
			{ Name = "Button Bunny", Style = "Bunny", Income = 1, Color = Color3.fromRGB(200, 180, 160), Accessory = "Flower" },
			{ Name = "Pond Frog", Style = "Frog", Income = 2, Color = Color3.fromRGB(90, 170, 80), Pattern = "Spots" },
			{ Name = "Jelly Slime", Style = "Slime", Income = 2, Color = Color3.fromRGB(255, 120, 180), Pattern = "Hearts" },
			{ Name = "Pip Sparrow", Style = "Bird", Income = 1, Color = Color3.fromRGB(170, 130, 90), Pattern = "Freckles", PatternColor = Color3.fromRGB(110, 80, 60) },
			{ Name = "Nibbles", Style = "Hamster", Income = 1, Color = Color3.fromRGB(205, 205, 215), Accessory = "Leaf" },
			{ Name = "Duckling Dee", Style = "Duck", Income = 1, Color = Color3.fromRGB(255, 240, 140) },
			{ Name = "Sprout Pal", Style = "Moss", Income = 2, Color = Color3.fromRGB(140, 200, 90), Accessory = "Flower", Accent = Color3.fromRGB(255, 230, 90) },
			{ Name = "Tiny Turtle", Style = "Turtle", Income = 2, Color = Color3.fromRGB(130, 190, 120) },
			{ Name = "Fluffball", Style = "Sheep", Income = 2, Color = Color3.fromRGB(235, 238, 255), Accessory = "Bow", Accent = Color3.fromRGB(150, 120, 255) },
			{ Name = "Fuzzy Chick", Style = "Chick", Income = 1, Color = Color3.fromRGB(255, 245, 180), Accessory = "Bow" },
			{ Name = "Sandy Crab", Style = "Crab", Income = 1, Color = Color3.fromRGB(240, 200, 140), Pattern = "Spots" },
			{ Name = "Garden Snail", Style = "Snail", Income = 2, Color = Color3.fromRGB(170, 140, 200), Accessory = "Leaf" },
			{ Name = "Lil Seal", Style = "Seal", Income = 2, Color = Color3.fromRGB(190, 200, 210), Pattern = "Freckles", PatternColor = Color3.fromRGB(120, 130, 150) },
			{ Name = "Cocoa Duck", Style = "Duck", Income = 2, Color = Color3.fromRGB(132, 85, 54) },
			{ Name = "Cozy Calf", Style = "Cow", Income = 2, Color = Color3.fromRGB(206, 172, 130) },
			{ Name = "Peachy Calf", Style = "Cow", Income = 3, Color = Color3.fromRGB(255, 190, 155), Pattern = "Stars", Accessory = "Bow" },
			{ Name = "Pebble Hamster", Style = "Hamster", Income = 1, Color = Color3.fromRGB(157, 171, 142), Pattern = "Freckles" },
			{ Name = "Meadow Turtle", Style = "Turtle", Income = 2, Color = Color3.fromRGB(159, 189, 106), Pattern = "Patches" },
			{ Name = "Cocoa Kitty", Style = "Cat", Income = 1, Color = Color3.fromRGB(122, 92, 53) },
			{ Name = "Cocoa Snail", Style = "Snail", Income = 1, Color = Color3.fromRGB(137, 93, 65), Accessory = "Bandana" },
			{ Name = "Sunny Snail", Style = "Snail", Income = 2, Color = Color3.fromRGB(255, 221, 102), Accessory = "Bow" },
			{ Name = "Cozy Mouse", Style = "Mouse", Income = 3, Color = Color3.fromRGB(199, 151, 119) },
			{ Name = "Minty Pony", Style = "Pony", Income = 1, Color = Color3.fromRGB(158, 228, 204), Pattern = "Freckles", Accessory = "Scarf" },
			{ Name = "Cozy Kitty", Style = "Cat", Income = 3, Color = Color3.fromRGB(203, 155, 115), Pattern = "Stripes", Accessory = "Beanie" },
			{ Name = "Cozy Pony", Style = "Pony", Income = 2, Color = Color3.fromRGB(211, 171, 121) },
			{ Name = "Puddle Pony", Style = "Pony", Income = 2, Color = Color3.fromRGB(122, 175, 227), Accessory = "Bow" },
			{ Name = "Button Turtle", Style = "Turtle", Income = 3, Color = Color3.fromRGB(239, 190, 199), Pattern = "Hearts", Accessory = "Bow" },
			{ Name = "Clover Turtle", Style = "Turtle", Income = 1, Color = Color3.fromRGB(114, 208, 111), Accessory = "Flower" },
			{ Name = "Hazel Squirrel", Style = "Squirrel", Income = 3, Color = Color3.fromRGB(185, 122, 98), Accessory = "TopHat" },
			{ Name = "Clover Chick", Style = "Chick", Income = 2, Color = Color3.fromRGB(122, 196, 109), Pattern = "Stripes", Accessory = "Flower" },
			{ Name = "Cocoa Koala", Style = "Koala", Income = 3, Color = Color3.fromRGB(129, 92, 60), Pattern = "Freckles" },
			{ Name = "Meadow Hamster", Style = "Hamster", Income = 2, Color = Color3.fromRGB(146, 209, 100) },
			{ Name = "Pebble Mouse", Style = "Mouse", Income = 1, Color = Color3.fromRGB(156, 156, 147), Pattern = "Freckles" },
			{ Name = "Pebble Bee", Style = "Bee", Income = 2, Color = Color3.fromRGB(167, 166, 141), Pattern = "Freckles" },
			{ Name = "Pebble Otter", Style = "Otter", Income = 1, Color = Color3.fromRGB(172, 163, 155), Pattern = "Freckles", Accessory = "PartyHat" },
			{ Name = "Sunny Pup", Style = "Pup", Income = 2, Color = Color3.fromRGB(245, 213, 115), Pattern = "Spots" },
			{ Name = "Button Mouse", Style = "Mouse", Income = 1, Color = Color3.fromRGB(251, 178, 200), Pattern = "Hearts", Accessory = "Bow" },
			{ Name = "Peachy Bee", Style = "Bee", Income = 3, Color = Color3.fromRGB(253, 200, 152), Pattern = "Patches", Accessory = "Bow" },
			{ Name = "Peachy Turtle", Style = "Turtle", Income = 1, Color = Color3.fromRGB(255, 185, 157), Accessory = "Bow" },
			{ Name = "Fuzzy Birdie", Style = "Bird", Income = 3, Color = Color3.fromRGB(236, 200, 173), Accessory = "PartyHat" },
			{ Name = "Hazel Pup", Style = "Pup", Income = 3, Color = Color3.fromRGB(172, 127, 85) },
			{ Name = "Button Calf", Style = "Cow", Income = 1, Color = Color3.fromRGB(239, 187, 194), Pattern = "Patches" },
			{ Name = "Meadow Pony", Style = "Pony", Income = 2, Color = Color3.fromRGB(155, 193, 112) },
			{ Name = "Hazel Kitty", Style = "Cat", Income = 1, Color = Color3.fromRGB(168, 125, 84) },
			{ Name = "Fuzzy Ladybug", Style = "Ladybug", Income = 1, Color = Color3.fromRGB(220, 196, 163) },
			{ Name = "Meadow Duck", Style = "Duck", Income = 1, Color = Color3.fromRGB(152, 205, 119) },
			{ Name = "Sunny Birdie", Style = "Bird", Income = 1, Color = Color3.fromRGB(255, 228, 99), Accessory = "Bow" },
			{ Name = "Button Hamster", Style = "Hamster", Income = 1, Color = Color3.fromRGB(230, 173, 198), Pattern = "Hearts", Accessory = "Bow" },
			{ Name = "Cotton Squirrel", Style = "Squirrel", Income = 2, Color = Color3.fromRGB(252, 253, 239), Pattern = "Freckles", Accessory = "Bow" },
			{ Name = "Hazel Piglet", Style = "Pig", Income = 3, Color = Color3.fromRGB(173, 135, 98), Pattern = "Spots" },
			{ Name = "Peachy Hamster", Style = "Hamster", Income = 1, Color = Color3.fromRGB(255, 192, 140), Accessory = "Bow" },
			{ Name = "Minty Koala", Style = "Koala", Income = 1, Color = Color3.fromRGB(172, 244, 207), Pattern = "Stripes", Accessory = "Scarf" },
			{ Name = "Minty Hedgehog", Style = "Hedgehog", Income = 3, Color = Color3.fromRGB(168, 235, 196), Accessory = "Scarf" },
			{ Name = "Minty Slime", Style = "Slime", Income = 1, Color = Color3.fromRGB(160, 246, 212), Accessory = "Scarf" },
			{ Name = "Sunny Mouse", Style = "Mouse", Income = 1, Color = Color3.fromRGB(250, 223, 120), Accessory = "Bow" },
			{ Name = "Cotton Hedgehog", Style = "Hedgehog", Income = 2, Color = Color3.fromRGB(236, 237, 238), Accessory = "Bow" },
			{ Name = "Puddle Hedgehog", Style = "Hedgehog", Income = 3, Color = Color3.fromRGB(129, 176, 218), Pattern = "Freckles" },
			{ Name = "Puddle Slime", Style = "Slime", Income = 1, Color = Color3.fromRGB(115, 161, 220) },
		},
	},
	{
		Id = "Uncommon",
		HatchTime = 20,
		Color = Color3.fromRGB(110, 220, 120),
		Creatures = {
			{ Name = "Glow Newt", Style = "Newt", Income = 6, Color = Color3.fromRGB(120, 255, 170) },
			{ Name = "Puffcap", Style = "Mushroom", Income = 7, Color = Color3.fromRGB(230, 120, 160) },
			{ Name = "Snugbat", Style = "Bat", Income = 8, Color = Color3.fromRGB(120, 100, 160) },
			{ Name = "Fennec Fox", Style = "Fox", Income = 7, Color = Color3.fromRGB(245, 150, 70), Accessory = "Scarf" },
			{ Name = "Pengu", Style = "Penguin", Income = 8, Color = Color3.fromRGB(55, 65, 90) },
			{ Name = "Hoot", Style = "Owl", Income = 9, Color = Color3.fromRGB(165, 120, 80), Accessory = "Glasses" },
			{ Name = "Coco Monkey", Style = "Monkey", Income = 7, Color = Color3.fromRGB(150, 100, 60), Accessory = "Headphones" },
			{ Name = "Sunny Duck", Style = "Duck", Income = 8, Color = Color3.fromRGB(255, 220, 60), Accessory = "Bow", Accent = Color3.fromRGB(90, 160, 255) },
			{ Name = "Piggy Bank", Style = "Pig", Income = 8, Color = Color3.fromRGB(255, 150, 200), Pattern = "Hearts", Accessory = "TopHat" },
			{ Name = "Honey Bear", Style = "Bear", Income = 7, Color = Color3.fromRGB(220, 160, 60), Accessory = "Scarf" },
			{ Name = "Raccoon Rascal", Style = "Raccoon", Income = 8, Color = Color3.fromRGB(130, 130, 140) },
			{ Name = "Gray Wolf", Style = "Wolf", Income = 9, Color = Color3.fromRGB(150, 150, 160) },
			{ Name = "Cactus Buddy", Style = "Cactus", Income = 6, Color = Color3.fromRGB(100, 180, 100), Accessory = "Flower" },
			{ Name = "Harbor Seal", Style = "Seal", Income = 7, Color = Color3.fromRGB(140, 150, 170), Pattern = "Spots" },
			{ Name = "Bumble Queen", Style = "Bee", Income = 9, Color = Color3.fromRGB(255, 190, 40), Accessory = "Tiara" },
			{ Name = "Lucky Ladybug", Style = "Ladybug", Income = 7, Color = Color3.fromRGB(80, 200, 90) },
			{ Name = "Hermit Crab", Style = "Crab", Income = 8, Color = Color3.fromRGB(230, 140, 90), Accessory = "Beanie", Accent = Color3.fromRGB(90, 160, 255) },
			{ Name = "Baby Elephant", Style = "Elephant", Income = 9, Color = Color3.fromRGB(170, 175, 195), Accessory = "Bow" },
			{ Name = "Mini Shark", Style = "Shark", Income = 8, Color = Color3.fromRGB(120, 150, 190) },
			{ Name = "Boo Ghost", Style = "Ghost", Income = 8, Color = Color3.fromRGB(240, 240, 255) },
			{ Name = "Beep Bot", Style = "Robot", Income = 9, Color = Color3.fromRGB(170, 180, 200) },
			{ Name = "Twinkle Star", Style = "Star", Income = 7, Color = Color3.fromRGB(255, 230, 100) },
			{ Name = "Blossom Bunny", Style = "Bunny", Income = 8, Color = Color3.fromRGB(255, 190, 220), Pattern = "Hearts", Accessory = "Flower" },
			{ Name = "Party Pup", Style = "Pup", Income = 7, Color = Color3.fromRGB(240, 200, 150), Accessory = "PartyHat" },
			{ Name = "Cozy Hamster", Style = "Hamster", Income = 6, Color = Color3.fromRGB(240, 220, 190), Accessory = "Beanie" },
			{ Name = "Snowy Owl", Style = "Owl", Income = 9, Color = Color3.fromRGB(240, 245, 250), Pattern = "Spots", PatternColor = Color3.fromRGB(90, 90, 100) },
			{ Name = "Mallard", Style = "Duck", Income = 7, Color = Color3.fromRGB(90, 150, 90) },
			{ Name = "Spotted Newt", Style = "Newt", Income = 8, Color = Color3.fromRGB(255, 170, 60), Pattern = "Spots", PatternColor = Color3.fromRGB(60, 40, 30) },
			{ Name = "Toadcap", Style = "Mushroom", Income = 7, Color = Color3.fromRGB(200, 90, 60) },
			{ Name = "Ringtail", Style = "Raccoon", Income = 8, Color = Color3.fromRGB(200, 190, 180) },
			{ Name = "Lil Lion", Style = "Lion", Income = 9, Color = Color3.fromRGB(240, 190, 90) },
			{ Name = "Fox Kit", Style = "Fox", Income = 8, Color = Color3.fromRGB(230, 120, 60), Accessory = "Scarf", Accent = Color3.fromRGB(90, 160, 255) },
			{ Name = "Coral Raccoon", Style = "Raccoon", Income = 7, Color = Color3.fromRGB(255, 138, 112), Pattern = "Patches" },
			{ Name = "Autumn Bat", Style = "Bat", Income = 7, Color = Color3.fromRGB(221, 145, 71), Accessory = "Leaf" },
			{ Name = "Speckled Fox", Style = "Fox", Income = 10, Color = Color3.fromRGB(214, 217, 195), Pattern = "Spots" },
			{ Name = "Stormy Pony", Style = "Pony", Income = 7, Color = Color3.fromRGB(132, 128, 170) },
			{ Name = "Autumn Sloth", Style = "Sloth", Income = 8, Color = Color3.fromRGB(210, 134, 81), Accessory = "Leaf" },
			{ Name = "Stormy Fish", Style = "Fish", Income = 10, Color = Color3.fromRGB(132, 125, 157), Accessory = "Antenna" },
			{ Name = "Sandy Otter", Style = "Otter", Income = 6, Color = Color3.fromRGB(226, 211, 147), Pattern = "Hearts", Accessory = "Bandana" },
			{ Name = "Berry Kangaroo", Style = "Kangaroo", Income = 10, Color = Color3.fromRGB(190, 92, 140), Pattern = "Hearts", Accessory = "Bow" },
			{ Name = "Rosy Raccoon", Style = "Raccoon", Income = 8, Color = Color3.fromRGB(255, 150, 181), Pattern = "Hearts" },
			{ Name = "Speckled Parrot", Style = "Parrot", Income = 8, Color = Color3.fromRGB(215, 208, 196), Pattern = "Freckles" },
			{ Name = "Dusty Monkey", Style = "Monkey", Income = 9, Color = Color3.fromRGB(193, 176, 126) },
			{ Name = "Lavender Kangaroo", Style = "Kangaroo", Income = 7, Color = Color3.fromRGB(180, 172, 235), Pattern = "Spots" },
			{ Name = "Autumn Penguin", Style = "Penguin", Income = 10, Color = Color3.fromRGB(227, 139, 70), Accessory = "Leaf" },
			{ Name = "Rosy Otter", Style = "Otter", Income = 6, Color = Color3.fromRGB(244, 148, 200), Pattern = "Hearts", Accessory = "PartyHat" },
			{ Name = "Mossy Flamingo", Style = "Flamingo", Income = 10, Color = Color3.fromRGB(99, 172, 78), Accessory = "Leaf" },
			{ Name = "Autumn Monkey", Style = "Monkey", Income = 9, Color = Color3.fromRGB(232, 147, 62), Pattern = "Patches", Accessory = "Leaf" },
			{ Name = "Misty Penguin", Style = "Penguin", Income = 10, Color = Color3.fromRGB(184, 189, 217) },
			{ Name = "Lavender Pony", Style = "Pony", Income = 9, Color = Color3.fromRGB(181, 161, 240) },
			{ Name = "Stormy Bat", Style = "Bat", Income = 7, Color = Color3.fromRGB(110, 120, 148), Accessory = "Beanie" },
			{ Name = "Coral Bat", Style = "Bat", Income = 6, Color = Color3.fromRGB(243, 138, 114), Pattern = "Hearts" },
			{ Name = "Sandy Parrot", Style = "Parrot", Income = 6, Color = Color3.fromRGB(220, 201, 153) },
			{ Name = "Rosy Parrot", Style = "Parrot", Income = 9, Color = Color3.fromRGB(244, 150, 182), Pattern = "Hearts", Accessory = "Scarf" },
			{ Name = "Lavender Swan", Style = "Swan", Income = 9, Color = Color3.fromRGB(202, 167, 232), Pattern = "Hearts", Accessory = "Bandana" },
			{ Name = "Berry Otter", Style = "Otter", Income = 10, Color = Color3.fromRGB(207, 73, 134), Pattern = "Stripes", Accessory = "Bow" },
			{ Name = "Rosy Fish", Style = "Fish", Income = 6, Color = Color3.fromRGB(244, 152, 193), Pattern = "Hearts" },
			{ Name = "Speckled Newt", Style = "Newt", Income = 10, Color = Color3.fromRGB(211, 202, 196), Pattern = "Spots" },
			{ Name = "Frosty Swan", Style = "Swan", Income = 9, Color = Color3.fromRGB(178, 234, 255), Pattern = "Stars", Accessory = "PartyHat" },
			{ Name = "Misty Flamingo", Style = "Flamingo", Income = 9, Color = Color3.fromRGB(185, 198, 211) },
			{ Name = "Mossy Parrot", Style = "Parrot", Income = 7, Color = Color3.fromRGB(108, 166, 92), Accessory = "Leaf" },
			{ Name = "Berry Seal", Style = "Seal", Income = 7, Color = Color3.fromRGB(191, 82, 149), Pattern = "Hearts", Accessory = "Bow" },
			{ Name = "Sandy Axolotl", Style = "Axolotl", Income = 7, Color = Color3.fromRGB(241, 201, 150), Pattern = "Spots" },
			{ Name = "Speckled Fish", Style = "Fish", Income = 7, Color = Color3.fromRGB(213, 198, 194), Pattern = "Spots" },
			{ Name = "Mossy Fox", Style = "Fox", Income = 7, Color = Color3.fromRGB(98, 171, 87) },
			{ Name = "Misty Kangaroo", Style = "Kangaroo", Income = 8, Color = Color3.fromRGB(178, 209, 227), Pattern = "Freckles" },
			{ Name = "Misty Pony", Style = "Pony", Income = 9, Color = Color3.fromRGB(196, 209, 225), Pattern = "Spots" },
			{ Name = "Sandy Kangaroo", Style = "Kangaroo", Income = 7, Color = Color3.fromRGB(221, 195, 145), Pattern = "Stars", Accessory = "Bandana" },
			{ Name = "Frosty Bat", Style = "Bat", Income = 7, Color = Color3.fromRGB(201, 226, 255) },
			{ Name = "Coral Seal", Style = "Seal", Income = 6, Color = Color3.fromRGB(255, 130, 130), Pattern = "Freckles" },
			{ Name = "Frosty Seal", Style = "Seal", Income = 7, Color = Color3.fromRGB(181, 218, 246), Pattern = "Spots", Accessory = "Scarf" },
			{ Name = "Stormy Owl", Style = "Owl", Income = 7, Color = Color3.fromRGB(108, 123, 152), Accessory = "Antenna" },
			{ Name = "Lavender Otter", Style = "Otter", Income = 7, Color = Color3.fromRGB(190, 167, 228), Pattern = "Patches" },
			{ Name = "Berry Crab", Style = "Crab", Income = 7, Color = Color3.fromRGB(198, 69, 130), Accessory = "Bow" },
			{ Name = "Frosty Axolotl", Style = "Axolotl", Income = 9, Color = Color3.fromRGB(201, 235, 244), Accessory = "Scarf" },
			{ Name = "Coral Squirrel", Style = "Squirrel", Income = 9, Color = Color3.fromRGB(245, 141, 130) },
			{ Name = "Mossy Pony", Style = "Pony", Income = 8, Color = Color3.fromRGB(106, 155, 85), Pattern = "Patches", Accessory = "Leaf" },
		},
	},
	{
		Id = "Rare",
		HatchTime = 40,
		Color = Color3.fromRGB(80, 160, 255),
		Creatures = {
			{ Name = "Frostfin", Style = "Fish", Income = 35, Color = Color3.fromRGB(150, 220, 255) },
			{ Name = "Emberkit", Style = "Cat", Income = 40, Color = Color3.fromRGB(255, 120, 60) },
			{ Name = "Thundercub", Style = "Cub", Income = 45, Color = Color3.fromRGB(255, 230, 80) },
			{ Name = "Pandy", Style = "Panda", Income = 42, Color = Color3.fromRGB(245, 245, 245), Accessory = "Bow" },
			{ Name = "Axolittle", Style = "Axolotl", Income = 48, Color = Color3.fromRGB(255, 160, 200), Pattern = "Hearts" },
			{ Name = "Koi Fin", Style = "Koi", Income = 38, Color = Color3.fromRGB(255, 140, 60) },
			{ Name = "Shell Turtle", Style = "Turtle", Income = 42, Color = Color3.fromRGB(110, 170, 110), Accessory = "Bandana" },
			{ Name = "Tiger Cub", Style = "Cat", Income = 44, Color = Color3.fromRGB(255, 150, 50), Pattern = "Stripes", PatternColor = Color3.fromRGB(40, 30, 30), Plain = true },
			{ Name = "Arctic Wolf", Style = "Wolf", Income = 46, Color = Color3.fromRGB(235, 240, 250), Accessory = "Scarf" },
			{ Name = "Hammerhead", Style = "Shark", Income = 42, Color = Color3.fromRGB(110, 130, 160) },
			{ Name = "Moon Bunny", Style = "Bunny", Income = 40, Color = Color3.fromRGB(220, 220, 255), Pattern = "Stars", PatternColor = Color3.fromRGB(255, 240, 150) },
			{ Name = "Lava Crab", Style = "Crab", Income = 45, Color = Color3.fromRGB(200, 60, 40), Pattern = "Spots", PatternColor = Color3.fromRGB(255, 160, 40), PatternGlow = true },
			{ Name = "Robo Pup", Style = "Robot", Income = 43, Color = Color3.fromRGB(200, 210, 230), Accessory = "Bandana" },
			{ Name = "Spooky Ghost", Style = "Ghost", Income = 41, Color = Color3.fromRGB(180, 160, 255), Accessory = "Horns", Accent = Color3.fromRGB(120, 60, 180) },
			{ Name = "Sea Lion", Style = "Seal", Income = 39, Color = Color3.fromRGB(180, 140, 100) },
			{ Name = "Emperor Pengu", Style = "Penguin", Income = 47, Color = Color3.fromRGB(40, 50, 70), Accessory = "Tiara" },
			{ Name = "Blue Jay", Style = "Bird", Income = 38, Color = Color3.fromRGB(80, 140, 230) },
			{ Name = "Spike Hog", Style = "Hedgehog", Income = 42, Color = Color3.fromRGB(80, 110, 220) },
			{ Name = "Circus Elephant", Style = "Elephant", Income = 46, Color = Color3.fromRGB(190, 170, 230), Accessory = "PartyHat", Accent = Color3.fromRGB(255, 90, 120) },
			{ Name = "Luna Moth", Style = "Moth", Income = 44, Color = Color3.fromRGB(170, 230, 170) },
			{ Name = "Coral Octopus", Style = "Octopus", Income = 43, Color = Color3.fromRGB(255, 120, 110) },
			{ Name = "Prickly Pear", Style = "Cactus", Income = 37, Color = Color3.fromRGB(130, 190, 110), Accessory = "Flower", Accent = Color3.fromRGB(255, 90, 160) },
			{ Name = "Badger Bandit", Style = "Raccoon", Income = 41, Color = Color3.fromRGB(70, 70, 80), Accessory = "Bandana" },
			{ Name = "Red Panda", Style = "Raccoon", Income = 45, Color = Color3.fromRGB(200, 90, 50) },
			{ Name = "Jungle Frog", Style = "Frog", Income = 40, Color = Color3.fromRGB(60, 200, 120), Pattern = "Spots", PatternColor = Color3.fromRGB(40, 90, 220) },
			{ Name = "Firefly", Style = "Bee", Income = 38, Color = Color3.fromRGB(90, 80, 60), Pattern = "Spots", PatternColor = Color3.fromRGB(255, 240, 90), PatternGlow = true },
			{ Name = "Dalmatian", Style = "Pup", Income = 39, Color = Color3.fromRGB(250, 250, 250), Pattern = "Spots", PatternColor = Color3.fromRGB(30, 30, 35), Accessory = "Bell" },
			{ Name = "Thunder Sheep", Style = "Sheep", Income = 44, Color = Color3.fromRGB(130, 140, 170), Accessory = "Antenna" },
			{ Name = "Golden Hamster", Style = "Hamster", Income = 46, Color = Color3.fromRGB(255, 200, 80), Accessory = "Tiara" },
			{ Name = "Pumpkin Bear", Style = "Bear", Income = 42, Color = Color3.fromRGB(255, 140, 40), Accessory = "Leaf" },
			{ Name = "Snow Seal", Style = "Seal", Income = 40, Color = Color3.fromRGB(240, 245, 255), Pattern = "Stars", PatternColor = Color3.fromRGB(170, 210, 255) },
			{ Name = "Sunburst Lion", Style = "Lion", Income = 43, Color = Color3.fromRGB(243, 187, 71), Pattern = "Swirl", Accessory = "Flower" },
			{ Name = "Moonlit Wolf", Style = "Wolf", Income = 43, Color = Color3.fromRGB(185, 198, 255), Pattern = "Stars" },
			{ Name = "Thunder Octopus", Style = "Octopus", Income = 42, Color = Color3.fromRGB(255, 228, 91), Pattern = "Stripes", Accessory = "Antenna" },
			{ Name = "Ruby Rhino", Style = "Rhino", Income = 43, Color = Color3.fromRGB(226, 59, 79), Pattern = "Gems", Accessory = "Bow" },
			{ Name = "Sunburst Giraffe", Style = "Giraffe", Income = 46, Color = Color3.fromRGB(255, 192, 72), Pattern = "Swirl" },
			{ Name = "Blaze Bear", Style = "Bear", Income = 47, Color = Color3.fromRGB(247, 120, 46), Pattern = "Stripes" },
			{ Name = "Ruby Panda", Style = "Panda", Income = 43, Color = Color3.fromRGB(208, 43, 84), Pattern = "Gems" },
			{ Name = "Thunder Bot", Style = "Robot", Income = 46, Color = Color3.fromRGB(255, 218, 83), Accessory = "Antenna" },
			{ Name = "Glacier Bear", Style = "Bear", Income = 37, Color = Color3.fromRGB(159, 212, 245), Accessory = "Scarf" },
			{ Name = "Sunburst Bear", Style = "Bear", Income = 47, Color = Color3.fromRGB(255, 186, 66), Pattern = "Swirl" },
			{ Name = "Ember Hippo", Style = "Hippo", Income = 45, Color = Color3.fromRGB(245, 108, 59), Pattern = "Spots", Accessory = "Beanie" },
			{ Name = "Thunder Shark", Style = "Shark", Income = 41, Color = Color3.fromRGB(254, 242, 87), Accessory = "Antenna" },
			{ Name = "Crystal Panda", Style = "Panda", Income = 48, Color = Color3.fromRGB(179, 230, 255), Pattern = "Gems" },
			{ Name = "Emerald Bear", Style = "Bear", Income = 37, Color = Color3.fromRGB(54, 188, 104), Pattern = "Gems" },
			{ Name = "Emerald Bot", Style = "Robot", Income = 50, Color = Color3.fromRGB(54, 192, 100), Pattern = "Gems" },
			{ Name = "Ruby Peacock", Style = "Peacock", Income = 36, Color = Color3.fromRGB(221, 58, 76), Pattern = "Spots" },
			{ Name = "Thunder Rhino", Style = "Rhino", Income = 41, Color = Color3.fromRGB(247, 237, 79), Pattern = "Stripes", Accessory = "Antenna" },
			{ Name = "Ember Deer", Style = "Stag", Income = 36, Color = Color3.fromRGB(229, 98, 64), Pattern = "Spots" },
			{ Name = "Blaze Rhino", Style = "Rhino", Income = 46, Color = Color3.fromRGB(253, 120, 47), Pattern = "Stripes", Accessory = "Flower" },
			{ Name = "Glacier Bot", Style = "Robot", Income = 40, Color = Color3.fromRGB(150, 216, 246), Pattern = "Freckles" },
			{ Name = "Ember Panda", Style = "Panda", Income = 43, Color = Color3.fromRGB(242, 90, 63), Pattern = "Spots" },
			{ Name = "Moonlit Deer", Style = "Stag", Income = 38, Color = Color3.fromRGB(184, 188, 246), Pattern = "Stars" },
			{ Name = "Moonlit Hippo", Style = "Hippo", Income = 47, Color = Color3.fromRGB(192, 184, 255), Pattern = "Stars" },
			{ Name = "Ruby Hippo", Style = "Hippo", Income = 44, Color = Color3.fromRGB(217, 53, 70), Pattern = "Stripes" },
			{ Name = "Emerald Wolf", Style = "Wolf", Income = 50, Color = Color3.fromRGB(46, 189, 102), Pattern = "Gems" },
			{ Name = "Blaze Croc", Style = "Croc", Income = 44, Color = Color3.fromRGB(251, 106, 38), Pattern = "Stripes" },
			{ Name = "Sunburst Panda", Style = "Panda", Income = 40, Color = Color3.fromRGB(251, 183, 64), Pattern = "Swirl" },
			{ Name = "Jungle Koi", Style = "Koi", Income = 41, Color = Color3.fromRGB(61, 167, 84), Pattern = "Stars" },
			{ Name = "Sapphire Bot", Style = "Robot", Income = 44, Color = Color3.fromRGB(64, 81, 228), Pattern = "Gems" },
			{ Name = "Glacier Lion", Style = "Lion", Income = 37, Color = Color3.fromRGB(147, 222, 237), Pattern = "Stars", Accessory = "Scarf" },
			{ Name = "Jungle Dolphin", Style = "Dolphin", Income = 37, Color = Color3.fromRGB(63, 178, 93), Accessory = "Bandana" },
			{ Name = "Crystal Kangaroo", Style = "Kangaroo", Income = 39, Color = Color3.fromRGB(180, 217, 255), Pattern = "Gems", Accessory = "Bandana" },
			{ Name = "Sapphire Wolf", Style = "Wolf", Income = 40, Color = Color3.fromRGB(69, 100, 220), Pattern = "Gems" },
			{ Name = "Jungle Elephant", Style = "Elephant", Income = 46, Color = Color3.fromRGB(68, 175, 85), Accessory = "Flower" },
			{ Name = "Sapphire Kangaroo", Style = "Kangaroo", Income = 46, Color = Color3.fromRGB(50, 79, 230), Pattern = "Gems" },
			{ Name = "Blaze Wolf", Style = "Wolf", Income = 48, Color = Color3.fromRGB(255, 116, 47), Pattern = "Stripes" },
			{ Name = "Sapphire Elephant", Style = "Elephant", Income = 36, Color = Color3.fromRGB(68, 94, 215), Pattern = "Gems", Accessory = "Bow" },
			{ Name = "Tidal Shark", Style = "Shark", Income = 46, Color = Color3.fromRGB(57, 150, 228), Accessory = "Flower" },
			{ Name = "Jungle Croc", Style = "Croc", Income = 42, Color = Color3.fromRGB(66, 174, 95), Accessory = "Leaf" },
			{ Name = "Crystal Koi", Style = "Koi", Income = 36, Color = Color3.fromRGB(180, 218, 251), Pattern = "Gems" },
			{ Name = "Moonlit Koi", Style = "Koi", Income = 35, Color = Color3.fromRGB(194, 186, 249), Pattern = "Stars" },
			{ Name = "Emerald Hippo", Style = "Hippo", Income = 48, Color = Color3.fromRGB(60, 178, 120), Pattern = "Gems", Accessory = "PartyHat" },
			{ Name = "Ember Elephant", Style = "Elephant", Income = 45, Color = Color3.fromRGB(239, 98, 55), Pattern = "Spots" },
			{ Name = "Crystal Peacock", Style = "Peacock", Income = 44, Color = Color3.fromRGB(167, 223, 251), Pattern = "Gems" },
			{ Name = "Glacier Shark", Style = "Shark", Income = 46, Color = Color3.fromRGB(156, 208, 251), Pattern = "Stars" },
		},
	},
	{
		Id = "Epic",
		HatchTime = 75,
		Color = Color3.fromRGB(180, 90, 255),
		Creatures = {
			{ Name = "Voidmoth", Style = "Moth", Income = 220, Color = Color3.fromRGB(90, 50, 140) },
			{ Name = "Crystal Stag", Style = "Stag", Income = 260, Color = Color3.fromRGB(200, 160, 255) },
			{ Name = "Dino Rex", Style = "Dino", Income = 240, Color = Color3.fromRGB(110, 190, 90), Pattern = "Spots" },
			{ Name = "Jelly Queen", Style = "Jelly", Income = 280, Color = Color3.fromRGB(230, 130, 255) },
			{ Name = "Neon Newt", Style = "Newt", Income = 230, Color = Color3.fromRGB(80, 255, 200) },
			{ Name = "Storm Owl", Style = "Owl", Income = 250, Color = Color3.fromRGB(90, 110, 170), Pattern = "Stripes", PatternColor = Color3.fromRGB(255, 240, 90), PatternGlow = true },
			{ Name = "Great White", Style = "Shark", Income = 260, Color = Color3.fromRGB(200, 210, 220) },
			{ Name = "Shadow Wolf", Style = "Wolf", Income = 270, Color = Color3.fromRGB(60, 50, 80), Pattern = "Stripes", PatternColor = Color3.fromRGB(170, 90, 255), PatternGlow = true },
			{ Name = "Crystal Hedgehog", Style = "Hedgehog", Income = 250, Color = Color3.fromRGB(170, 220, 255), Pattern = "Gems" },
			{ Name = "Mecha Bot", Style = "Robot", Income = 280, Color = Color3.fromRGB(120, 130, 150), Accessory = "Shades" },
			{ Name = "Phantom Ghost", Style = "Ghost", Income = 240, Color = Color3.fromRGB(120, 255, 200), Pattern = "Swirl", PatternColor = Color3.fromRGB(220, 255, 240), PatternGlow = true },
			{ Name = "King Leo", Style = "Lion", Income = 290, Color = Color3.fromRGB(255, 200, 80), Accessory = "Tiara" },
			{ Name = "Galaxy Octopus", Style = "Octopus", Income = 265, Color = Color3.fromRGB(90, 60, 160), Pattern = "Stars", PatternGlow = true },
			{ Name = "Mammoth", Style = "Elephant", Income = 255, Color = Color3.fromRGB(150, 110, 80), Accessory = "Scarf", Accent = Color3.fromRGB(90, 160, 255) },
			{ Name = "Rainbow Snail", Style = "Snail", Income = 230, Color = Color3.fromRGB(255, 160, 220), Pattern = "Rainbow" },
			{ Name = "Samurai Crab", Style = "Crab", Income = 245, Color = Color3.fromRGB(180, 40, 40), Accessory = "Bandana", Accent = Color3.fromRGB(250, 250, 250) },
			{ Name = "Queen Bee", Style = "Bee", Income = 275, Color = Color3.fromRGB(255, 200, 40), Accessory = "Tiara" },
			{ Name = "Wizard Cat", Style = "Cat", Income = 285, Color = Color3.fromRGB(80, 70, 160), Pattern = "Stars", Accessory = "WizardHat", Plain = true },
			{ Name = "Neon Pig", Style = "Pig", Income = 235, Color = Color3.fromRGB(255, 80, 200), Pattern = "Spots", PatternColor = Color3.fromRGB(80, 255, 240), PatternGlow = true },
			{ Name = "Cyber Bunny", Style = "Bunny", Income = 270, Color = Color3.fromRGB(90, 230, 255), Pattern = "Stripes", PatternColor = Color3.fromRGB(255, 60, 200), PatternGlow = true, Accessory = "Shades" },
			{ Name = "Magma Turtle", Style = "Turtle", Income = 250, Color = Color3.fromRGB(120, 60, 40), Pattern = "Spots", PatternColor = Color3.fromRGB(255, 130, 30), PatternGlow = true },
			{ Name = "Starfish", Style = "Star", Income = 225, Color = Color3.fromRGB(255, 140, 90), Pattern = "Freckles", PatternColor = Color3.fromRGB(255, 230, 200) },
			{ Name = "Frost Lion", Style = "Lion", Income = 280, Color = Color3.fromRGB(190, 230, 255), Accessory = "Scarf", Accent = Color3.fromRGB(80, 120, 255) },
			{ Name = "DJ Raccoon", Style = "Raccoon", Income = 265, Color = Color3.fromRGB(100, 100, 120), Accessory = "Headphones" },
			{ Name = "Dune Serpent", Style = "Serpent", Income = 255, Color = Color3.fromRGB(220, 180, 110) },
			{ Name = "Cotton Candy Sheep", Style = "Sheep", Income = 240, Color = Color3.fromRGB(255, 190, 230), Pattern = "Hearts", PatternColor = Color3.fromRGB(150, 210, 255) },
			{ Name = "Ember Bear", Style = "Bear", Income = 260, Color = Color3.fromRGB(200, 70, 40), Pattern = "Spots", PatternColor = Color3.fromRGB(255, 180, 60), PatternGlow = true },
			{ Name = "Thunderbird", Style = "Bird", Income = 275, Color = Color3.fromRGB(80, 90, 200), Pattern = "Stripes", PatternColor = Color3.fromRGB(255, 240, 90), PatternGlow = true },
			{ Name = "Mystic Griffin", Style = "Griffin", Income = 267, Color = Color3.fromRGB(168, 101, 232), Accessory = "WizardHat" },
			{ Name = "Shadow Kitsune", Style = "Kitsune", Income = 229, Color = Color3.fromRGB(60, 49, 110), Pattern = "Stripes", Accessory = "TopHat" },
			{ Name = "Neon Wolf", Style = "Wolf", Income = 275, Color = Color3.fromRGB(255, 64, 189), Pattern = "Hearts" },
			{ Name = "Aurora Kitsune", Style = "Kitsune", Income = 274, Color = Color3.fromRGB(112, 250, 203), Pattern = "Swirl" },
			{ Name = "Rune Whale", Style = "Whale", Income = 224, Color = Color3.fromRGB(93, 128, 193) },
			{ Name = "Toxic Dragon", Style = "Drake", Income = 287, Color = Color3.fromRGB(130, 255, 71), Pattern = "Spots" },
			{ Name = "Aurora Lion", Style = "Lion", Income = 270, Color = Color3.fromRGB(114, 249, 202), Pattern = "Spots", Accessory = "Bandana" },
			{ Name = "Shadow Rex", Style = "Dino", Income = 269, Color = Color3.fromRGB(59, 70, 100), Pattern = "Spots", Accessory = "Horns" },
			{ Name = "Aurora Jelly", Style = "Jelly", Income = 249, Color = Color3.fromRGB(118, 255, 208), Pattern = "Swirl" },
			{ Name = "Rune Peacock", Style = "Peacock", Income = 226, Color = Color3.fromRGB(78, 123, 209), Accessory = "WizardHat" },
			{ Name = "Magma Shark", Style = "Shark", Income = 265, Color = Color3.fromRGB(245, 82, 41), Pattern = "Spots", Accessory = "Bandana" },
			{ Name = "Amethyst Wolf", Style = "Wolf", Income = 235, Color = Color3.fromRGB(168, 105, 211) },
			{ Name = "Obsidian Kitsune", Style = "Kitsune", Income = 246, Color = Color3.fromRGB(52, 28, 39) },
			{ Name = "Cyber Unicorn", Style = "Unicorn", Income = 237, Color = Color3.fromRGB(82, 235, 250) },
			{ Name = "Neon Griffin", Style = "Griffin", Income = 288, Color = Color3.fromRGB(249, 76, 192), Pattern = "Spots", Accessory = "Headphones" },
			{ Name = "Cyber Griffin", Style = "Griffin", Income = 243, Color = Color3.fromRGB(67, 241, 255), Pattern = "Spots" },
			{ Name = "Mystic Croc", Style = "Croc", Income = 280, Color = Color3.fromRGB(155, 88, 233), Pattern = "Stars" },
			{ Name = "Magma Croc", Style = "Croc", Income = 292, Color = Color3.fromRGB(255, 88, 42), Pattern = "Spots" },
			{ Name = "Neon Croc", Style = "Croc", Income = 261, Color = Color3.fromRGB(246, 77, 210), Accessory = "Headphones" },
			{ Name = "Rune Croc", Style = "Croc", Income = 233, Color = Color3.fromRGB(82, 111, 208), Accessory = "WizardHat" },
			{ Name = "Magma Unicorn", Style = "Unicorn", Income = 290, Color = Color3.fromRGB(255, 100, 32), Pattern = "Spots", Accessory = "Beanie" },
			{ Name = "Rune Griffin", Style = "Griffin", Income = 233, Color = Color3.fromRGB(91, 122, 193), Accessory = "WizardHat" },
			{ Name = "Plasma Rex", Style = "Dino", Income = 234, Color = Color3.fromRGB(248, 99, 151) },
			{ Name = "Arcane Shark", Style = "Shark", Income = 252, Color = Color3.fromRGB(119, 85, 228), Accessory = "WizardHat" },
			{ Name = "Mystic Star", Style = "Star", Income = 255, Color = Color3.fromRGB(164, 102, 224), Accessory = "WizardHat" },
			{ Name = "Obsidian Pegasus", Style = "Pegasus", Income = 295, Color = Color3.fromRGB(46, 32, 45) },
			{ Name = "Aurora Peacock", Style = "Peacock", Income = 223, Color = Color3.fromRGB(126, 243, 203), Pattern = "Swirl" },
			{ Name = "Mystic Rex", Style = "Dino", Income = 236, Color = Color3.fromRGB(166, 96, 238) },
			{ Name = "Cyber Peacock", Style = "Peacock", Income = 295, Color = Color3.fromRGB(67, 241, 255), Accessory = "Shades" },
			{ Name = "Amethyst Peacock", Style = "Peacock", Income = 224, Color = Color3.fromRGB(155, 98, 231), Pattern = "Stars" },
			{ Name = "Shadow Dragon", Style = "Drake", Income = 257, Color = Color3.fromRGB(59, 49, 95), Pattern = "Spots" },
			{ Name = "Cyber Jelly", Style = "Jelly", Income = 256, Color = Color3.fromRGB(82, 232, 255), Pattern = "Stars", Accessory = "Shades" },
			{ Name = "Neon Shark", Style = "Shark", Income = 249, Color = Color3.fromRGB(255, 58, 198), Pattern = "Stripes" },
			{ Name = "Magma Star", Style = "Star", Income = 232, Color = Color3.fromRGB(244, 79, 31), Pattern = "Spots" },
			{ Name = "Plasma Kitsune", Style = "Kitsune", Income = 221, Color = Color3.fromRGB(250, 79, 163), Pattern = "Swirl" },
			{ Name = "Plasma Jelly", Style = "Jelly", Income = 247, Color = Color3.fromRGB(255, 81, 159), Pattern = "Swirl" },
			{ Name = "Plasma Pegasus", Style = "Pegasus", Income = 237, Color = Color3.fromRGB(243, 81, 162), Pattern = "Hearts" },
			{ Name = "Amethyst Rex", Style = "Dino", Income = 256, Color = Color3.fromRGB(158, 106, 226), Accessory = "Bandana" },
			{ Name = "Arcane Serpent", Style = "Serpent", Income = 244, Color = Color3.fromRGB(115, 88, 210), Accessory = "WizardHat" },
			{ Name = "Obsidian Dragon", Style = "Drake", Income = 239, Color = Color3.fromRGB(50, 43, 61), Accessory = "Horns" },
			{ Name = "Shadow Whale", Style = "Whale", Income = 274, Color = Color3.fromRGB(75, 51, 104), Accessory = "Horns" },
			{ Name = "Amethyst Dragon", Style = "Drake", Income = 235, Color = Color3.fromRGB(160, 100, 232) },
		},
	},
	{
		Id = "Legendary",
		HatchTime = 120,
		Color = Color3.fromRGB(255, 180, 40),
		Creatures = {
			{ Name = "Solar Drake", Style = "Drake", Income = 1500, Color = Color3.fromRGB(255, 160, 40) },
			{ Name = "Tidal Serpent", Style = "Serpent", Income = 1800, Color = Color3.fromRGB(40, 140, 220) },
			{ Name = "Starlight Unicorn", Style = "Unicorn", Income = 1700, Color = Color3.fromRGB(255, 250, 255), Pattern = "Stars" },
			{ Name = "Nine-Tail Kitsune", Style = "Kitsune", Income = 2100, Color = Color3.fromRGB(255, 240, 245), Weight = 0.6 },
			{ Name = "Sakura Fox", Style = "Fox", Income = 1600, Color = Color3.fromRGB(255, 170, 200), Accessory = "Flower" },
			{ Name = "Sun Phoenix", Style = "Phoenix", Income = 1900, Color = Color3.fromRGB(255, 150, 40) },
			{ Name = "Megalodon", Style = "Shark", Income = 2000, Color = Color3.fromRGB(70, 90, 120), Pattern = "Stripes", PatternColor = Color3.fromRGB(40, 50, 70) },
			{ Name = "Moonlight Wolf", Style = "Wolf", Income = 1800, Color = Color3.fromRGB(200, 210, 255), Pattern = "Stars" },
			{ Name = "Sun Lion", Style = "Lion", Income = 1900, Color = Color3.fromRGB(255, 170, 40), Pattern = "Swirl", PatternColor = Color3.fromRGB(255, 240, 150) },
			{ Name = "Aurora Seal", Style = "Seal", Income = 1550, Color = Color3.fromRGB(140, 255, 220), Pattern = "Swirl", PatternColor = Color3.fromRGB(200, 140, 255) },
			{ Name = "Treasure Pig", Style = "Pig", Income = 1650, Color = Color3.fromRGB(255, 210, 80), Pattern = "Gems", Accessory = "TopHat" },
			{ Name = "Guardian Bot", Style = "Robot", Income = 1850, Color = Color3.fromRGB(230, 230, 250), Accessory = "Cape" },
			{ Name = "Spirit Ghost", Style = "Ghost", Income = 1700, Color = Color3.fromRGB(170, 230, 255), Accessory = "Halo" },
			{ Name = "Nebula Octopus", Style = "Octopus", Income = 1750, Color = Color3.fromRGB(140, 80, 220), Pattern = "Stars" },
			{ Name = "Royal Elephant", Style = "Elephant", Income = 2050, Color = Color3.fromRGB(200, 160, 255), Pattern = "Gems", Accessory = "Tiara" },
			{ Name = "Diamond Hedgehog", Style = "Hedgehog", Income = 1600, Color = Color3.fromRGB(160, 240, 255), Pattern = "Gems" },
			{ Name = "Flame Stag", Style = "Stag", Income = 1950, Color = Color3.fromRGB(255, 110, 50) },
			{ Name = "Thunder Drake", Style = "Drake", Income = 2100, Color = Color3.fromRGB(90, 120, 255), Pattern = "Stripes", PatternColor = Color3.fromRGB(255, 240, 90) },
			{ Name = "Frost Phoenix", Style = "Phoenix", Income = 2000, Color = Color3.fromRGB(150, 220, 255) },
			{ Name = "Jade Dragon", Style = "Serpent", Income = 1900, Color = Color3.fromRGB(80, 200, 120), Accessory = "Horns", Accent = Color3.fromRGB(255, 220, 120) },
			{ Name = "Shogun Crab", Style = "Crab", Income = 1500, Color = Color3.fromRGB(200, 160, 40), Accessory = "Bandana", Accent = Color3.fromRGB(200, 30, 40) },
			{ Name = "Comet Star", Style = "Star", Income = 1650, Color = Color3.fromRGB(140, 200, 255), Pattern = "Swirl", PatternColor = Color3.fromRGB(255, 255, 255) },
			{ Name = "Candy Unicorn", Style = "Unicorn", Income = 1800, Color = Color3.fromRGB(255, 200, 230), Pattern = "Hearts", PatternColor = Color3.fromRGB(150, 210, 255) },
			{ Name = "Ninja Raccoon", Style = "Raccoon", Income = 1700, Color = Color3.fromRGB(50, 50, 60), Accessory = "Bandana", Accent = Color3.fromRGB(220, 40, 50) },
			{ Name = "Storm Bee", Style = "Bee", Income = 1550, Color = Color3.fromRGB(120, 140, 255), Pattern = "Spots", PatternColor = Color3.fromRGB(255, 255, 120) },
			{ Name = "Leaf Kitsune", Style = "Kitsune", Income = 2150, Color = Color3.fromRGB(170, 230, 140), Accessory = "Leaf" },
			{ Name = "Sky Kitsune", Style = "Kitsune", Income = 2100, Color = Color3.fromRGB(137, 190, 243), Pattern = "Hearts" },
			{ Name = "Titan Unicorn", Style = "Unicorn", Income = 1500, Color = Color3.fromRGB(159, 154, 170) },
			{ Name = "Sky Rex", Style = "Dino", Income = 2000, Color = Color3.fromRGB(140, 202, 255), Pattern = "Patches" },
			{ Name = "Jade Lion", Style = "Lion", Income = 1800, Color = Color3.fromRGB(81, 200, 121) },
			{ Name = "Solar Phoenix", Style = "Phoenix", Income = 1600, Color = Color3.fromRGB(245, 178, 33), Pattern = "Swirl" },
			{ Name = "Tempest Dragon", Style = "Drake", Income = 1800, Color = Color3.fromRGB(68, 159, 208), Pattern = "Stripes" },
			{ Name = "Crimson Griffin", Style = "Griffin", Income = 1500, Color = Color3.fromRGB(197, 23, 59) },
			{ Name = "Jade Wolf", Style = "Wolf", Income = 1600, Color = Color3.fromRGB(60, 201, 121) },
			{ Name = "Storm Cerberus", Style = "Cerberus", Income = 2200, Color = Color3.fromRGB(95, 117, 202), Pattern = "Stripes" },
			{ Name = "Golden Dragon", Style = "Drake", Income = 1600, Color = Color3.fromRGB(255, 217, 66), Accessory = "Tiara" },
			{ Name = "Golden Unicorn", Style = "Unicorn", Income = 2100, Color = Color3.fromRGB(255, 215, 71), Pattern = "Hearts" },
			{ Name = "Ivory Cerberus", Style = "Cerberus", Income = 2100, Color = Color3.fromRGB(249, 252, 231), Pattern = "Spots" },
			{ Name = "Royal Serpent", Style = "Serpent", Income = 2100, Color = Color3.fromRGB(127, 77, 190), Pattern = "Spots", Accessory = "Tiara" },
			{ Name = "Crimson Whale", Style = "Whale", Income = 1800, Color = Color3.fromRGB(199, 26, 51), Accessory = "Cape" },
			{ Name = "Ivory Whale", Style = "Whale", Income = 2200, Color = Color3.fromRGB(248, 250, 227), Pattern = "Patches" },
			{ Name = "Inferno Unicorn", Style = "Unicorn", Income = 1600, Color = Color3.fromRGB(255, 71, 24), Pattern = "Spots" },
			{ Name = "Storm Rex", Style = "Dino", Income = 1900, Color = Color3.fromRGB(81, 103, 207), Pattern = "Hearts" },
			{ Name = "Golden Rex", Style = "Dino", Income = 2200, Color = Color3.fromRGB(243, 201, 59), Pattern = "Patches" },
			{ Name = "Ivory Serpent", Style = "Serpent", Income = 1700, Color = Color3.fromRGB(251, 255, 220) },
			{ Name = "Titan Phoenix", Style = "Phoenix", Income = 2000, Color = Color3.fromRGB(152, 146, 165), Accessory = "Cape" },
			{ Name = "Sky Griffin", Style = "Griffin", Income = 1600, Color = Color3.fromRGB(134, 193, 255), Accessory = "Bow" },
			{ Name = "Jade Unicorn", Style = "Unicorn", Income = 2000, Color = Color3.fromRGB(65, 201, 123) },
			{ Name = "Phantom Lion", Style = "Lion", Income = 1700, Color = Color3.fromRGB(156, 165, 219) },
			{ Name = "Golden Lion", Style = "Lion", Income = 2000, Color = Color3.fromRGB(255, 213, 78), Pattern = "Freckles" },
			{ Name = "Jade Pegasus", Style = "Pegasus", Income = 1900, Color = Color3.fromRGB(81, 193, 119), Pattern = "Patches", Accessory = "TopHat" },
			{ Name = "Inferno Wolf", Style = "Wolf", Income = 2000, Color = Color3.fromRGB(255, 78, 18), Pattern = "Spots" },
			{ Name = "Titan Dragon", Style = "Drake", Income = 1600, Color = Color3.fromRGB(142, 145, 176), Accessory = "Cape" },
			{ Name = "Ivory Unicorn", Style = "Unicorn", Income = 1500, Color = Color3.fromRGB(239, 255, 237) },
			{ Name = "Titan Rex", Style = "Dino", Income = 2100, Color = Color3.fromRGB(158, 153, 161), Accessory = "Cape" },
			{ Name = "Tempest Phoenix", Style = "Phoenix", Income = 2100, Color = Color3.fromRGB(76, 166, 218), Pattern = "Stripes" },
			{ Name = "Inferno Serpent", Style = "Serpent", Income = 1700, Color = Color3.fromRGB(251, 89, 23), Pattern = "Spots" },
			{ Name = "Tempest Lion", Style = "Lion", Income = 2200, Color = Color3.fromRGB(70, 164, 212), Pattern = "Stripes", Accessory = "Bandana" },
			{ Name = "Storm Kitsune", Style = "Kitsune", Income = 1600, Color = Color3.fromRGB(87, 111, 194), Pattern = "Stripes" },
			{ Name = "Royal Pegasus", Style = "Pegasus", Income = 1700, Color = Color3.fromRGB(132, 73, 206), Accessory = "Tiara" },
			{ Name = "Sky Dragon", Style = "Drake", Income = 2200, Color = Color3.fromRGB(143, 203, 255) },
			{ Name = "Inferno Dragon", Style = "Drake", Income = 1700, Color = Color3.fromRGB(246, 73, 40), Pattern = "Spots" },
			{ Name = "Phantom Whale", Style = "Whale", Income = 2000, Color = Color3.fromRGB(149, 174, 200), Accessory = "Cape" },
			{ Name = "Tempest Rex", Style = "Dino", Income = 1800, Color = Color3.fromRGB(76, 151, 222), Pattern = "Stars" },
			{ Name = "Phantom Pegasus", Style = "Pegasus", Income = 2200, Color = Color3.fromRGB(171, 175, 198) },
			{ Name = "Phantom Serpent", Style = "Serpent", Income = 1700, Color = Color3.fromRGB(171, 178, 203), Accessory = "Cape" },
		},
	},
	{
		Id = "Mythic",
		HatchTime = 240,
		Color = Color3.fromRGB(255, 70, 110),
		Creatures = {
			{ Name = "Cosmic Phoenix", Style = "Phoenix", Income = 11000, Color = Color3.fromRGB(255, 90, 150) },
			{ Name = "Galaxy Dragon", Style = "Drake", Income = 12500, Color = Color3.fromRGB(120, 70, 220), Pattern = "Stars" },
			{ Name = "Void Kraken", Style = "Kraken", Income = 14000, Color = Color3.fromRGB(70, 40, 120), Weight = 0.5 },
			{ Name = "Abyss Serpent", Style = "Serpent", Income = 12000, Color = Color3.fromRGB(40, 50, 110) },
			{ Name = "Crystal King Stag", Style = "Stag", Income = 13000, Color = Color3.fromRGB(170, 120, 255) },
			{ Name = "Leviathan", Style = "Shark", Income = 14000, Color = Color3.fromRGB(40, 60, 110), Pattern = "Stripes", PatternColor = Color3.fromRGB(80, 255, 240) },
			{ Name = "Fenrir", Style = "Wolf", Income = 13500, Color = Color3.fromRGB(90, 90, 120), Accessory = "Horns", Accent = Color3.fromRGB(60, 40, 40) },
			{ Name = "Nemean Lion", Style = "Lion", Income = 13000, Color = Color3.fromRGB(255, 220, 120), Pattern = "Gems" },
			{ Name = "Ghost King", Style = "Ghost", Income = 12000, Color = Color3.fromRGB(200, 120, 255), Accessory = "Tiara" },
			{ Name = "Omega Bot", Style = "Robot", Income = 12500, Color = Color3.fromRGB(255, 60, 90), Pattern = "Stripes", PatternColor = Color3.fromRGB(255, 230, 90), Accessory = "Shades" },
			{ Name = "Abyss Octopus", Style = "Octopus", Income = 13000, Color = Color3.fromRGB(40, 40, 90), Pattern = "Spots", PatternColor = Color3.fromRGB(90, 255, 230) },
			{ Name = "Cosmic Elephant", Style = "Elephant", Income = 11500, Color = Color3.fromRGB(80, 60, 160), Pattern = "Stars" },
			{ Name = "Void Bunny", Style = "Bunny", Income = 11000, Color = Color3.fromRGB(50, 30, 80), Pattern = "Stars", PatternColor = Color3.fromRGB(200, 140, 255) },
			{ Name = "Crimson Wolf", Style = "Wolf", Income = 12000, Color = Color3.fromRGB(180, 30, 50), Pattern = "Stripes", PatternColor = Color3.fromRGB(255, 120, 80) },
			{ Name = "Hydra", Style = "Serpent", Income = 14500, Color = Color3.fromRGB(60, 140, 90), Accessory = "Horns" },
			{ Name = "Ice Dragon", Style = "Drake", Income = 13500, Color = Color3.fromRGB(180, 230, 255), Pattern = "Swirl", PatternColor = Color3.fromRGB(255, 255, 255) },
			{ Name = "Inferno Phoenix", Style = "Phoenix", Income = 14000, Color = Color3.fromRGB(255, 70, 30), Pattern = "Spots", PatternColor = Color3.fromRGB(255, 230, 90) },
			{ Name = "Starfall Stag", Style = "Stag", Income = 12500, Color = Color3.fromRGB(120, 110, 220), Pattern = "Stars" },
			{ Name = "Eclipse Kitsune", Style = "Kitsune", Income = 13500, Color = Color3.fromRGB(60, 50, 90), Pattern = "Swirl", PatternColor = Color3.fromRGB(255, 200, 90) },
			{ Name = "Nova Star", Style = "Star", Income = 11000, Color = Color3.fromRGB(255, 120, 200), Pattern = "Gems" },
			{ Name = "Blood Kraken", Style = "Kraken", Income = 15000, Color = Color3.fromRGB(120, 40, 60), Weight = 0.5 },
			{ Name = "Lunar Unicorn", Style = "Unicorn", Income = 12000, Color = Color3.fromRGB(200, 210, 255), Pattern = "Stars" },
			{ Name = "Gold Rush Hamster", Style = "Hamster", Income = 11000, Color = Color3.fromRGB(255, 200, 60), Pattern = "Gems", Accessory = "Tiara" },
			{ Name = "Chrono Whale", Style = "Whale", Income = 11700, Color = Color3.fromRGB(203, 178, 99), Accessory = "Glasses" },
			{ Name = "Starborn Whale", Style = "Whale", Income = 15000, Color = Color3.fromRGB(255, 224, 150) },
			{ Name = "Chrono Pegasus", Style = "Pegasus", Income = 14100, Color = Color3.fromRGB(210, 167, 90), Pattern = "Freckles", Accessory = "Glasses" },
			{ Name = "Chrono Kitsune", Style = "Kitsune", Income = 11300, Color = Color3.fromRGB(201, 177, 87) },
			{ Name = "Galactic Dragon", Style = "Drake", Income = 12700, Color = Color3.fromRGB(111, 68, 212), Pattern = "Stars" },
			{ Name = "Abyssal Kitsune", Style = "Kitsune", Income = 12800, Color = Color3.fromRGB(17, 46, 83), Accessory = "Bow" },
			{ Name = "Quantum Shark", Style = "Shark", Income = 12900, Color = Color3.fromRGB(89, 218, 252), Accessory = "PartyHat" },
			{ Name = "Dread Cerberus", Style = "Cerberus", Income = 12600, Color = Color3.fromRGB(99, 31, 37), Pattern = "Spots", Accessory = "Horns" },
			{ Name = "Quantum Unicorn", Style = "Unicorn", Income = 14200, Color = Color3.fromRGB(72, 232, 255), Pattern = "Stars" },
			{ Name = "Dread Griffin", Style = "Griffin", Income = 13100, Color = Color3.fromRGB(89, 10, 28), Accessory = "Horns" },
			{ Name = "Galactic Kitsune", Style = "Kitsune", Income = 14500, Color = Color3.fromRGB(98, 66, 196) },
			{ Name = "Rift Serpent", Style = "Serpent", Income = 13400, Color = Color3.fromRGB(192, 58, 252) },
			{ Name = "Abyssal Phoenix", Style = "Phoenix", Income = 12000, Color = Color3.fromRGB(24, 34, 83) },
			{ Name = "Starborn Unicorn", Style = "Unicorn", Income = 12900, Color = Color3.fromRGB(252, 242, 160), Pattern = "Stars" },
			{ Name = "Rift Griffin", Style = "Griffin", Income = 13400, Color = Color3.fromRGB(176, 53, 251) },
			{ Name = "Abyssal Pegasus", Style = "Pegasus", Income = 11300, Color = Color3.fromRGB(10, 51, 95) },
			{ Name = "Galactic Unicorn", Style = "Unicorn", Income = 13000, Color = Color3.fromRGB(109, 63, 209), Pattern = "Stars" },
			{ Name = "Cosmic Kitsune", Style = "Kitsune", Income = 12500, Color = Color3.fromRGB(129, 67, 212), Pattern = "Stars" },
			{ Name = "Void Unicorn", Style = "Unicorn", Income = 12400, Color = Color3.fromRGB(44, 29, 86) },
			{ Name = "Starborn Cerberus", Style = "Cerberus", Income = 12800, Color = Color3.fromRGB(255, 224, 144), Pattern = "Stars", Accessory = "PartyHat" },
			{ Name = "Dread Pegasus", Style = "Pegasus", Income = 14600, Color = Color3.fromRGB(79, 12, 47), Pattern = "Patches", Accessory = "Horns" },
			{ Name = "Nebula Phoenix", Style = "Phoenix", Income = 14600, Color = Color3.fromRGB(235, 88, 191), Pattern = "Stars" },
			{ Name = "Eclipse Phoenix", Style = "Phoenix", Income = 12300, Color = Color3.fromRGB(56, 49, 70), Pattern = "Freckles" },
			{ Name = "Astral Phoenix", Style = "Phoenix", Income = 14700, Color = Color3.fromRGB(143, 166, 255) },
			{ Name = "Rift Pegasus", Style = "Pegasus", Income = 11700, Color = Color3.fromRGB(174, 61, 255), Accessory = "TopHat" },
			{ Name = "Astral Griffin", Style = "Griffin", Income = 11100, Color = Color3.fromRGB(143, 171, 244), Pattern = "Stars" },
			{ Name = "Eclipse Kraken", Style = "Kraken", Income = 13000, Color = Color3.fromRGB(50, 38, 67), Pattern = "Patches" },
			{ Name = "Astral Dragon", Style = "Drake", Income = 12900, Color = Color3.fromRGB(162, 154, 255), Pattern = "Stars" },
			{ Name = "Void Dragon", Style = "Drake", Income = 14000, Color = Color3.fromRGB(56, 40, 82), Pattern = "Spots" },
			{ Name = "Nebula Kitsune", Style = "Kitsune", Income = 13700, Color = Color3.fromRGB(219, 99, 191), Pattern = "Swirl" },
			{ Name = "Cosmic Cerberus", Style = "Cerberus", Income = 13100, Color = Color3.fromRGB(117, 79, 221), Pattern = "Stars" },
			{ Name = "Quantum Cerberus", Style = "Cerberus", Income = 13800, Color = Color3.fromRGB(69, 217, 243), Accessory = "Glasses" },
			{ Name = "Cosmic Serpent", Style = "Serpent", Income = 11100, Color = Color3.fromRGB(119, 62, 216), Pattern = "Stars" },
			{ Name = "Nebula Pegasus", Style = "Pegasus", Income = 12200, Color = Color3.fromRGB(218, 85, 203), Pattern = "Swirl" },
			{ Name = "Eclipse Whale", Style = "Whale", Income = 13400, Color = Color3.fromRGB(50, 28, 69), Pattern = "Patches", Accessory = "Flower" },
		},
	},
	{
		Id = "Divine",
		HatchTime = 420,
		Color = Color3.fromRGB(255, 240, 170),
		Creatures = {
			{ Name = "Celestial Unicorn", Style = "Unicorn", Income = 65000, Color = Color3.fromRGB(255, 245, 210) },
			{ Name = "Seraph Kitsune", Style = "Kitsune", Income = 80000, Color = Color3.fromRGB(255, 230, 160), Weight = 0.6 },
			{ Name = "Halo Owl", Style = "Owl", Income = 60000, Color = Color3.fromRGB(250, 235, 200) },
			{ Name = "Holy Panda", Style = "Panda", Income = 70000, Color = Color3.fromRGB(255, 245, 215), Accessory = "Halo" },
			{ Name = "Archangel Lion", Style = "Lion", Income = 78000, Color = Color3.fromRGB(255, 245, 210), Accessory = "Halo" },
			{ Name = "Heavenly Wolf", Style = "Wolf", Income = 72000, Color = Color3.fromRGB(255, 250, 235), Accessory = "Halo" },
			{ Name = "Cherub Pig", Style = "Pig", Income = 60000, Color = Color3.fromRGB(255, 220, 230), Pattern = "Hearts", Accessory = "Halo" },
			{ Name = "Angel Bunny", Style = "Bunny", Income = 62000, Color = Color3.fromRGB(255, 250, 250), Pattern = "Hearts", Accessory = "Halo" },
			{ Name = "Divine Dragon", Style = "Drake", Income = 85000, Color = Color3.fromRGB(255, 230, 150), Pattern = "Gems" },
			{ Name = "Holy Phoenix", Style = "Phoenix", Income = 80000, Color = Color3.fromRGB(255, 240, 190) },
			{ Name = "Sacred Elephant", Style = "Elephant", Income = 75000, Color = Color3.fromRGB(250, 240, 220), Pattern = "Gems", Accessory = "Tiara" },
			{ Name = "Blessed Spirit", Style = "Ghost", Income = 64000, Color = Color3.fromRGB(255, 245, 200), Accessory = "Halo" },
			{ Name = "Radiant Stag", Style = "Stag", Income = 77000, Color = Color3.fromRGB(255, 235, 170), Pattern = "Swirl", PatternColor = Color3.fromRGB(255, 255, 255) },
			{ Name = "Polaris", Style = "Star", Income = 66000, Color = Color3.fromRGB(255, 245, 180), Pattern = "Gems" },
			{ Name = "Oracle Bot", Style = "Robot", Income = 70000, Color = Color3.fromRGB(255, 235, 180), Accessory = "Halo" },
			{ Name = "Zenith Serpent", Style = "Serpent", Income = 82000, Color = Color3.fromRGB(255, 235, 190), Pattern = "Stars", Accessory = "Halo" },
			{ Name = "Blessed Swan", Style = "Swan", Income = 79300, Color = Color3.fromRGB(239, 232, 226), Accessory = "PartyHat" },
			{ Name = "Blessed Griffin", Style = "Griffin", Income = 69300, Color = Color3.fromRGB(250, 245, 222), Accessory = "Bow" },
			{ Name = "Angelic Pegasus", Style = "Pegasus", Income = 79000, Color = Color3.fromRGB(255, 254, 244), Accessory = "Halo" },
			{ Name = "Glorious Pegasus", Style = "Pegasus", Income = 62800, Color = Color3.fromRGB(255, 206, 126), Pattern = "Gems", Accessory = "Halo" },
			{ Name = "Blessed Owl", Style = "Owl", Income = 63000, Color = Color3.fromRGB(255, 246, 214), Pattern = "Spots", Accessory = "Halo" },
			{ Name = "Heavenly Kitsune", Style = "Kitsune", Income = 77500, Color = Color3.fromRGB(237, 236, 255), Accessory = "Halo" },
			{ Name = "Glorious Owl", Style = "Owl", Income = 66100, Color = Color3.fromRGB(244, 215, 121), Pattern = "Patches", Accessory = "Halo" },
			{ Name = "Radiant Swan", Style = "Swan", Income = 65200, Color = Color3.fromRGB(248, 239, 162), Pattern = "Gems", Accessory = "Halo" },
			{ Name = "Sacred Unicorn", Style = "Unicorn", Income = 75600, Color = Color3.fromRGB(247, 223, 182), Pattern = "Gems" },
			{ Name = "Angelic Phoenix", Style = "Phoenix", Income = 60500, Color = Color3.fromRGB(243, 255, 246), Accessory = "Halo" },
			{ Name = "Angelic Kitsune", Style = "Kitsune", Income = 64700, Color = Color3.fromRGB(255, 253, 252), Accessory = "Halo" },
			{ Name = "Celestial Whale", Style = "Whale", Income = 62500, Color = Color3.fromRGB(255, 245, 198), Pattern = "Patches", Accessory = "Halo" },
			{ Name = "Luminous Pegasus", Style = "Pegasus", Income = 68800, Color = Color3.fromRGB(255, 254, 199), Pattern = "Hearts", Accessory = "Halo" },
			{ Name = "Glorious Dragon", Style = "Drake", Income = 83900, Color = Color3.fromRGB(254, 217, 120), Pattern = "Spots", Accessory = "Halo" },
			{ Name = "Holy Pegasus", Style = "Pegasus", Income = 74100, Color = Color3.fromRGB(255, 246, 192), Pattern = "Stars", Accessory = "Halo" },
			{ Name = "Celestial Griffin", Style = "Griffin", Income = 71300, Color = Color3.fromRGB(255, 252, 201), Accessory = "Halo" },
			{ Name = "Luminous Lion", Style = "Lion", Income = 64000, Color = Color3.fromRGB(253, 252, 193), Pattern = "Patches", Accessory = "Halo" },
			{ Name = "Celestial Swan", Style = "Swan", Income = 68300, Color = Color3.fromRGB(255, 245, 212), Accessory = "Halo" },
			{ Name = "Radiant Kitsune", Style = "Kitsune", Income = 61300, Color = Color3.fromRGB(248, 235, 152), Pattern = "Gems", Accessory = "Halo" },
			{ Name = "Seraphic Unicorn", Style = "Unicorn", Income = 60400, Color = Color3.fromRGB(255, 251, 250), Accessory = "Bandana" },
			{ Name = "Sacred Griffin", Style = "Griffin", Income = 74200, Color = Color3.fromRGB(255, 219, 172), Pattern = "Freckles" },
			{ Name = "Heavenly Phoenix", Style = "Phoenix", Income = 65500, Color = Color3.fromRGB(229, 233, 251), Pattern = "Stars", Accessory = "PartyHat" },
			{ Name = "Luminous Unicorn", Style = "Unicorn", Income = 60300, Color = Color3.fromRGB(255, 246, 191), Pattern = "Hearts", Accessory = "Halo" },
			{ Name = "Seraphic Owl", Style = "Owl", Income = 76400, Color = Color3.fromRGB(254, 249, 240), Accessory = "Halo" },
			{ Name = "Sacred Kitsune", Style = "Kitsune", Income = 82700, Color = Color3.fromRGB(245, 233, 160), Pattern = "Spots", Accessory = "Halo" },
			{ Name = "Holy Whale", Style = "Whale", Income = 60900, Color = Color3.fromRGB(254, 235, 199), Pattern = "Spots", Accessory = "Halo" },
			{ Name = "Holy Serpent", Style = "Serpent", Income = 72000, Color = Color3.fromRGB(247, 231, 181), Pattern = "Stars", Accessory = "Halo" },
			{ Name = "Seraphic Swan", Style = "Swan", Income = 65600, Color = Color3.fromRGB(255, 255, 238), Pattern = "Stars" },
		},
	},
	{
		Id = "Secret",
		HatchTime = 600,
		Color = Color3.fromRGB(40, 40, 50),
		Creatures = {
			{ Name = "Glitch Cat", Style = "GlitchCat", Income = 350000, Color = Color3.fromRGB(35, 35, 45) },
			{ Name = "Rainbow Dragon", Style = "Drake", Income = 500000, Color = Color3.fromRGB(255, 120, 200), Pattern = "Rainbow", Weight = 0.5 },
			{ Name = "404 Bunny", Style = "GlitchBunny", Income = 400000, Color = Color3.fromRGB(30, 30, 38) },
			{ Name = "Glitch Wolf", Style = "Wolf", Income = 420000, Color = Color3.fromRGB(30, 30, 40), Pattern = "Pixels" },
			{ Name = "Error Bot", Style = "Robot", Income = 380000, Color = Color3.fromRGB(40, 10, 15), Pattern = "Pixels", Accessory = "Shades", Accent = Color3.fromRGB(255, 40, 60) },
			{ Name = "Null Ghost", Style = "Ghost", Income = 360000, Color = Color3.fromRGB(20, 20, 25), Pattern = "Pixels" },
			{ Name = "Rainbow Unicorn", Style = "Unicorn", Income = 550000, Color = Color3.fromRGB(255, 150, 220), Pattern = "Rainbow", Weight = 0.5 },
			{ Name = "Prismatic Lion", Style = "Lion", Income = 480000, Color = Color3.fromRGB(255, 255, 255), Pattern = "Rainbow", Accessory = "Tiara" },
			{ Name = "Void Octopus", Style = "Octopus", Income = 450000, Color = Color3.fromRGB(15, 10, 30), Pattern = "Stars", PatternColor = Color3.fromRGB(200, 140, 255) },
			{ Name = "Infinity Shark", Style = "Shark", Income = 520000, Color = Color3.fromRGB(20, 20, 40), Pattern = "Rainbow", Weight = 0.5 },
			{ Name = "Omega Kitsune", Style = "Kitsune", Income = 600000, Color = Color3.fromRGB(30, 20, 40), Pattern = "Pixels", Accessory = "Halo", Weight = 0.4 },
			{ Name = "Infinity Whale", Style = "Whale", Income = 424700, Color = Color3.fromRGB(31, 27, 37), Pattern = "Rainbow" },
			{ Name = "Hyper Cerberus", Style = "Cerberus", Income = 461600, Color = Color3.fromRGB(255, 56, 149), Accessory = "Headphones" },
			{ Name = "Error Wolf", Style = "Wolf", Income = 383000, Color = Color3.fromRGB(54, 9, 30), Accessory = "Shades" },
			{ Name = "Error Cerberus", Style = "Cerberus", Income = 619700, Color = Color3.fromRGB(71, 0, 31), Accessory = "Shades" },
			{ Name = "Paradox Whale", Style = "Whale", Income = 627200, Color = Color3.fromRGB(81, 0, 118), Pattern = "Pixels" },
			{ Name = "Hyper Phoenix", Style = "Phoenix", Income = 372500, Color = Color3.fromRGB(254, 42, 152), Accessory = "Headphones" },
			{ Name = "Glitched Serpent", Style = "Serpent", Income = 486500, Color = Color3.fromRGB(40, 39, 51), Pattern = "Pixels" },
			{ Name = "Hyper Dragon", Style = "Drake", Income = 535200, Color = Color3.fromRGB(252, 60, 156), Pattern = "Stars", Accessory = "Scarf", Weight = 0.5 },
			{ Name = "Infinity Griffin", Style = "Griffin", Income = 432100, Color = Color3.fromRGB(32, 28, 34), Weight = 0.5 },
			{ Name = "Omega Wolf", Style = "Wolf", Income = 594200, Color = Color3.fromRGB(47, 22, 59), Weight = 0.5 },
			{ Name = "Paradox Wolf", Style = "Wolf", Income = 431100, Color = Color3.fromRGB(84, 11, 119), Pattern = "Pixels" },
			{ Name = "Null Griffin", Style = "Griffin", Income = 485000, Color = Color3.fromRGB(19, 20, 33), Pattern = "Pixels" },
			{ Name = "Omega Unicorn", Style = "Unicorn", Income = 390000, Color = Color3.fromRGB(48, 24, 60), Weight = 0.5 },
			{ Name = "Infinity Phoenix", Style = "Phoenix", Income = 415900, Color = Color3.fromRGB(22, 25, 33) },
			{ Name = "Omega Griffin", Style = "Griffin", Income = 380300, Color = Color3.fromRGB(30, 11, 53), Accessory = "Bandana" },
			{ Name = "Paradox Serpent", Style = "Serpent", Income = 478600, Color = Color3.fromRGB(87, 9, 112), Pattern = "Pixels", Accessory = "PartyHat" },
			{ Name = "Prismatic Dragon", Style = "Drake", Income = 392800, Color = Color3.fromRGB(252, 255, 255), Pattern = "Rainbow" },
			{ Name = "Rainbow Wolf", Style = "Wolf", Income = 508800, Color = Color3.fromRGB(252, 153, 216), Pattern = "Rainbow", Weight = 0.5 },
			{ Name = "Phantasm Cerberus", Style = "Cerberus", Income = 435600, Color = Color3.fromRGB(156, 251, 230), Weight = 0.5 },
			{ Name = "Rainbow Pegasus", Style = "Pegasus", Income = 387100, Color = Color3.fromRGB(255, 154, 221), Pattern = "Rainbow" },
		},
	},
}

--------------------------------------------------------------------------------
-- Biomes, in order from town outward. Each has a guarded nest.
--   GuardianSpeed: how fast the guardian runs (studs/sec)
--   Leash: (not used anymore: guardians chase you until you reach the town's safe zone)
--   RespawnTime: seconds before an empty nest spot grows a new egg
--   Eggs: rarity weights for eggs that spawn here
--------------------------------------------------------------------------------
Config.Biomes = {
	{
		Id = "Forest",
		Name = "Whispering Forest",
		Floor = { Color3.fromRGB(108, 196, 72), Color3.fromRGB(92, 178, 60) },
		Walls = { Color3.fromRGB(214, 122, 82), Color3.fromRGB(230, 142, 98) },
		Props = { "Tree", "Tree", "TallTree", "Bush", "Bush", "Mushroom", "Rock", "Log" },
		Feature = "Pond",
		Particles = "Fireflies",
		GuardianName = "Bramble Bear",
		GuardianStyle = "Bear",
		GuardianColor = Color3.fromRGB(120, 80, 50),
		SpeedNeeded = 0, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 220,
		RespawnTime = 12,
		EggSpots = 16,
		Eggs = { Common = 80, Uncommon = 20 },
		Mood = { Color = Color3.fromRGB(175, 215, 240), Decay = Color3.fromRGB(95, 135, 110), Density = 0.3, Haze = 0.6, Glare = 0.2, Tint = Color3.fromRGB(245, 255, 242), Brightness = 0, Saturation = 0.18, CloudColor = Color3.fromRGB(255, 255, 255), CloudCover = 0.6, Bloom = 0.45, Rays = 0.12, Contrast = 0.12, Ambient = Color3.fromRGB(118, 140, 118) },
	},
	{
		Id = "Desert",
		Name = "Scorch Dunes",
		Floor = { Color3.fromRGB(238, 208, 140), Color3.fromRGB(222, 190, 122) },
		Walls = { Color3.fromRGB(205, 160, 100), Color3.fromRGB(222, 180, 118) },
		Props = { "Cactus", "Cactus", "DeadBush", "Sandstone", "Pillar", "Skull" },
		Feature = "Dunes",
		Particles = "Dust",
		GuardianName = "Dune Scorpion",
		GuardianStyle = "Scorpion",
		GuardianColor = Color3.fromRGB(200, 120, 40),
		SpeedNeeded = 1000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 230,
		RespawnTime = 25,
		EggSpots = 15,
		Eggs = { Uncommon = 60, Rare = 40 },
		Mood = { Color = Color3.fromRGB(240, 215, 175), Decay = Color3.fromRGB(200, 150, 100), Density = 0.34, Haze = 1.2, Glare = 0.4, Tint = Color3.fromRGB(255, 246, 228), Brightness = 0.01, Saturation = 0.15, CloudColor = Color3.fromRGB(255, 238, 215), CloudCover = 0.45, Bloom = 0.55, Rays = 0.09, Contrast = 0.16, Ambient = Color3.fromRGB(160, 140, 115) },
	},
	{
		Id = "Snow",
		Name = "Frostpeak",
		Floor = { Color3.fromRGB(240, 246, 255), Color3.fromRGB(214, 230, 248) },
		Walls = { Color3.fromRGB(150, 196, 236), Color3.fromRGB(172, 212, 245) },
		Props = { "Pine", "Pine", "Pine", "IceCrystal", "SnowRock", "Snowman" },
		Feature = "FrozenLake",
		Particles = "Snowfall",
		GuardianName = "Frost Yeti",
		GuardianStyle = "Yeti",
		GuardianColor = Color3.fromRGB(200, 230, 255),
		SpeedNeeded = 25000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 240,
		RespawnTime = 45,
		EggSpots = 14,
		Eggs = { Rare = 65, Epic = 35 },
		Mood = { Color = Color3.fromRGB(210, 228, 255), Decay = Color3.fromRGB(150, 180, 220), Density = 0.4, Haze = 1.2, Glare = 0.15, Tint = Color3.fromRGB(236, 246, 255), Brightness = 0, Saturation = 0.02, CloudColor = Color3.fromRGB(235, 242, 255), CloudCover = 0.75, Bloom = 0.6, Rays = 0.06, Contrast = 0.08, Ambient = Color3.fromRGB(150, 165, 190) },
	},
	{
		Id = "Volcano",
		Name = "Magma Crater",
		Floor = { Color3.fromRGB(78, 52, 48), Color3.fromRGB(60, 40, 38) },
		Walls = { Color3.fromRGB(110, 45, 35), Color3.fromRGB(135, 58, 40) },
		Props = { "LavaRock", "LavaRock", "Obsidian", "Torch", "DeadTree" },
		Feature = "Volcano",
		Particles = "Embers",
		GuardianName = "Lava Golem",
		GuardianStyle = "Golem",
		GuardianColor = Color3.fromRGB(255, 90, 30),
		SpeedNeeded = 200000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 250,
		RespawnTime = 90,
		EggSpots = 13,
		Eggs = { Epic = 65, Legendary = 35 },
		Mood = { Color = Color3.fromRGB(230, 130, 95), Decay = Color3.fromRGB(110, 40, 25), Density = 0.44, Haze = 1.6, Glare = 0.3, Tint = Color3.fromRGB(255, 224, 208), Brightness = -0.02, Saturation = 0.2, CloudColor = Color3.fromRGB(95, 65, 60), CloudCover = 0.8, Clock = 18.15, Bloom = 0.85, Rays = 0.16, Contrast = 0.2, Ambient = Color3.fromRGB(140, 80, 65) },
	},
	{
		Id = "Void",
		Name = "Starfall Void",
		Floor = { Color3.fromRGB(70, 48, 118), Color3.fromRGB(55, 36, 96) },
		Walls = { Color3.fromRGB(42, 28, 78), Color3.fromRGB(58, 40, 102) },
		Props = { "Crystal", "Crystal", "Obelisk", "FloatingRock", "FloatingRock" },
		Feature = "FloatingIslands",
		Particles = "Motes",
		GuardianName = "Void Wraith",
		GuardianStyle = "Wraith",
		Boss = true,
		GuardianColor = Color3.fromRGB(170, 90, 255),
		SpeedNeeded = 1000000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 260,
		RespawnTime = 180,
		EggSpots = 12,
		Eggs = { Legendary = 65, Mythic = 30, Divine = 4.5, Secret = 0.5 },
		Mood = { Color = Color3.fromRGB(140, 100, 215), Decay = Color3.fromRGB(45, 20, 90), Density = 0.44, Haze = 1, Glare = 0.2, Tint = Color3.fromRGB(222, 205, 255), Brightness = -0.05, Saturation = 0.25, CloudColor = Color3.fromRGB(150, 105, 220), CloudCover = 0.7, Clock = 0.5, Bloom = 1, Rays = 0, Contrast = 0.2, Ambient = Color3.fromRGB(110, 90, 160) },
	},

	{
		Id = "Candy",
		Name = "Candy Kingdom",
		Floor = { Color3.fromRGB(255, 190, 220), Color3.fromRGB(255, 170, 205) },
		Walls = { Color3.fromRGB(170, 110, 210), Color3.fromRGB(190, 130, 225) },
		Props = { "Lollipop", "Lollipop", "CandyCane", "Gumdrop", "CottonCandyTree", "CottonCandyTree" },
		Particles = "Sprinkles",
		GuardianName = "Gummy Titan",
		GuardianStyle = "Gummy",
		GuardianColor = Color3.fromRGB(240, 60, 90),
		SpeedNeeded = 5000000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 270,
		RespawnTime = 240,
		EggSpots = 12,
		Eggs = { Legendary = 40, Mythic = 50, Divine = 9, Secret = 1 },
		Mood = { Color = Color3.fromRGB(255, 200, 230), Decay = Color3.fromRGB(230, 140, 200), Density = 0.3, Haze = 0.8, Glare = 0.2, Tint = Color3.fromRGB(255, 240, 250), Brightness = 0.02, Saturation = 0.3, CloudColor = Color3.fromRGB(255, 210, 240), CloudCover = 0.55, Bloom = 0.55, Rays = 0.08, Contrast = 0.1, Ambient = Color3.fromRGB(180, 140, 170) },
	},
	{
		Id = "Ocean",
		Name = "Sunken Reef",
		Floor = { Color3.fromRGB(225, 210, 160), Color3.fromRGB(210, 195, 145) },
		Walls = { Color3.fromRGB(40, 110, 140), Color3.fromRGB(50, 130, 160) },
		Props = { "Coral", "Coral", "Kelp", "Kelp", "Clam", "SeaRock" },
		Particles = "Bubbles",
		GuardianName = "Reef King",
		GuardianStyle = "ReefKing",
		GuardianColor = Color3.fromRGB(255, 110, 80),
		SpeedNeeded = 25000000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 280,
		RespawnTime = 300,
		EggSpots = 11,
		Eggs = { Mythic = 65, Divine = 31, Secret = 4 },
		Mood = { Color = Color3.fromRGB(80, 170, 200), Decay = Color3.fromRGB(20, 70, 110), Density = 0.55, Haze = 2, Glare = 0, Tint = Color3.fromRGB(200, 235, 255), Brightness = -0.03, Saturation = 0.1, CloudColor = Color3.fromRGB(120, 180, 210), CloudCover = 0.8, Clock = 13, Bloom = 0.6, Rays = 0.2, Contrast = 0.15, Ambient = Color3.fromRGB(70, 130, 160) },
	},
	{
		Id = "Heaven",
		Name = "Celestial Heights",
		Floor = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(238, 238, 250) },
		Walls = { Color3.fromRGB(255, 225, 150), Color3.fromRGB(255, 235, 175) },
		Props = { "CloudPuff", "CloudPuff", "GoldPillar", "HeavenTree", "HeavenTree" },
		Particles = "Feathers",
		GuardianName = "Seraph Sentinel",
		GuardianStyle = "Seraph",
		Boss = true,
		GuardianColor = Color3.fromRGB(255, 205, 90),
		SpeedNeeded = 100000000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 290,
		RespawnTime = 360,
		EggSpots = 10,
		Eggs = { Mythic = 35, Divine = 57, Secret = 8 },
		Mood = { Color = Color3.fromRGB(255, 245, 220), Decay = Color3.fromRGB(255, 220, 170), Density = 0.32, Haze = 1.2, Glare = 0.6, Tint = Color3.fromRGB(255, 250, 235), Brightness = 0.04, Saturation = 0.05, CloudColor = Color3.fromRGB(255, 250, 240), CloudCover = 0.9, Clock = 12, Bloom = 0.9, Rays = 0.25, Contrast = 0.08, Ambient = Color3.fromRGB(200, 190, 170) },
	},
	{
		Id = "Shroom",
		Name = "Glowshroom Grotto",
		Floor = { Color3.fromRGB(48, 70, 84), Color3.fromRGB(40, 60, 74) },
		Walls = { Color3.fromRGB(78, 46, 118), Color3.fromRGB(96, 60, 140) },
		Props = { "GiantShroom", "GiantShroom", "ShroomCluster", "ShroomCluster", "GlowRock" },
		Particles = "Spores",
		GuardianName = "Spore Colossus",
		GuardianStyle = "Shroom",
		GuardianColor = Color3.fromRGB(80, 230, 255),
		SpeedNeeded = 500000000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 300,
		RespawnTime = 400,
		EggSpots = 10,
		Eggs = { Mythic = 30, Divine = 60, Secret = 10 },
		Mood = { Color = Color3.fromRGB(120, 95, 200), Decay = Color3.fromRGB(40, 80, 110), Density = 0.45, Haze = 1.4, Glare = 0, Tint = Color3.fromRGB(220, 232, 255), Brightness = -0.02, Saturation = 0.3, CloudColor = Color3.fromRGB(100, 80, 150), CloudCover = 0.7, Clock = 21, Bloom = 1, Rays = 0, Contrast = 0.18, Ambient = Color3.fromRGB(95, 115, 160) },
	},
	{
		Id = "Spooky",
		Name = "Haunted Hollow",
		Floor = { Color3.fromRGB(72, 82, 60), Color3.fromRGB(60, 70, 50) },
		Walls = { Color3.fromRGB(62, 56, 74), Color3.fromRGB(78, 72, 90) },
		Props = { "Pumpkin", "Pumpkin", "Gravestone", "Gravestone", "SpookyTree", "SpookyTree" },
		Particles = "Mist",
		GuardianName = "Pumpkin King",
		GuardianStyle = "Pumpkin",
		GuardianColor = Color3.fromRGB(255, 130, 30),
		SpeedNeeded = 2500000000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 310,
		RespawnTime = 450,
		EggSpots = 10,
		Eggs = { Mythic = 20, Divine = 66, Secret = 14 },
		Mood = { Color = Color3.fromRGB(110, 140, 120), Decay = Color3.fromRGB(40, 70, 50), Density = 0.55, Haze = 2.2, Glare = 0, Tint = Color3.fromRGB(215, 240, 222), Brightness = -0.04, Saturation = -0.1, CloudColor = Color3.fromRGB(80, 90, 85), CloudCover = 0.85, Clock = 23.5, Bloom = 0.8, Rays = 0, Contrast = 0.22, Ambient = Color3.fromRGB(95, 115, 105) },
	},
	{
		Id = "Clockwork",
		Name = "Clockwork Citadel",
		Floor = { Color3.fromRGB(160, 118, 76), Color3.fromRGB(140, 102, 64) },
		Walls = { Color3.fromRGB(112, 82, 52), Color3.fromRGB(132, 98, 62) },
		Props = { "Gear", "Gear", "SteamPipe", "Lamppost", "CogTower" },
		Particles = "Steam",
		GuardianName = "Brass Automaton",
		GuardianStyle = "Automaton",
		GuardianColor = Color3.fromRGB(210, 160, 70),
		SpeedNeeded = 10000000000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 320,
		RespawnTime = 500,
		EggSpots = 10,
		Eggs = { Mythic = 10, Divine = 70, Secret = 20 },
		Mood = { Color = Color3.fromRGB(240, 190, 130), Decay = Color3.fromRGB(150, 90, 50), Density = 0.38, Haze = 1.3, Glare = 0.5, Tint = Color3.fromRGB(255, 238, 210), Brightness = 0.01, Saturation = 0.12, CloudColor = Color3.fromRGB(230, 190, 150), CloudCover = 0.5, Clock = 17.6, Bloom = 0.6, Rays = 0.18, Contrast = 0.16, Ambient = Color3.fromRGB(160, 130, 100) },
	},
	{
		Id = "Cyber",
		Name = "Neon Nexus",
		Floor = { Color3.fromRGB(28, 22, 50), Color3.fromRGB(38, 30, 66) },
		Walls = { Color3.fromRGB(42, 30, 84), Color3.fromRGB(56, 40, 108) },
		Props = { "NeonTower", "NeonTower", "HoloTree", "DataPillar", "NeonSign" },
		Particles = "Data",
		GuardianName = "Omega Mech",
		GuardianStyle = "Mech",
		Boss = true,
		GuardianColor = Color3.fromRGB(255, 60, 200),
		SpeedNeeded = 50000000000, -- Speed needed to outrun this guardian (its speed is worked out from this)
		Leash = 330,
		RespawnTime = 600,
		EggSpots = 10,
		Eggs = { Divine = 70, Secret = 30 },
		Mood = { Color = Color3.fromRGB(150, 70, 220), Decay = Color3.fromRGB(30, 10, 70), Density = 0.4, Haze = 1, Glare = 0.3, Tint = Color3.fromRGB(235, 215, 255), Brightness = -0.02, Saturation = 0.35, CloudColor = Color3.fromRGB(120, 60, 180), CloudCover = 0.5, Clock = 0.3, Bloom = 1.2, Rays = 0.05, Contrast = 0.25, Ambient = Color3.fromRGB(110, 80, 170) },
	},
}

-- Leaderboards: big boards in town (in front of the bases) that rank the top
-- players across every server. Format: "Money", "Time" or "Number".
Config.Leaderboards = {
	{ Key = "Cash", Title = "RICHEST", Icon = "💰", Format = "Money", Color = Color3.fromRGB(90, 220, 110) },
	{ Key = "TimePlayed", Title = "MOST TIME PLAYED", Icon = "⏱️", Format = "Time", Color = Color3.fromRGB(110, 190, 255) },
	{ Key = "Hatched", Title = "PETS HATCHED", Icon = "🐣", Format = "Number", Color = Color3.fromRGB(255, 205, 80) },
	{ Key = "Stolen", Title = "EGGS STOLEN", Icon = "😈", Format = "Number", Color = Color3.fromRGB(255, 95, 95) },
	{ Key = "Speed", Title = "FASTEST", Icon = "⚡", Format = "Number", Color = Color3.fromRGB(255, 240, 90) },
	{ Key = "Index", Title = "PET INDEX", Icon = "📖", Format = "Number", Color = Color3.fromRGB(190, 130, 255) },
	{ Key = "Collected", Title = "EGGS BROUGHT HOME", Icon = "🥚", Format = "Number", Color = Color3.fromRGB(255, 160, 200) },
	{ Key = "Slapped", Title = "MOST SLAPPED", Icon = "💥", Format = "Number", Color = Color3.fromRGB(255, 150, 60) },
}
Config.LeaderboardSize = 10 -- rows per board
Config.LeaderboardRefresh = 90 -- seconds between updates (kept slow for Roblox's DataStore limits)

-- Town floor and wall colors (checkerboard pairs)
Config.TownFloor = { Color3.fromRGB(116, 206, 78), Color3.fromRGB(100, 190, 66) }
Config.TownWalls = { Color3.fromRGB(214, 122, 82), Color3.fromRGB(230, 142, 98) }

-- Lighting mood in town (the client blends between moods as you travel).
Config.TownMood = { Color = Color3.fromRGB(180, 212, 255), Decay = Color3.fromRGB(92, 122, 172), Density = 0.26, Haze = 0.35, Glare = 0.2, Tint = Color3.fromRGB(255, 251, 245), Brightness = 0, Saturation = 0.15, CloudColor = Color3.fromRGB(255, 255, 255), CloudCover = 0.6, Bloom = 0.4, Rays = 0.04, Contrast = 0.1, Ambient = Color3.fromRGB(126, 132, 148) }
-- Mood extras: Clock pins the time of day in that zone (Volcano = sunset,
-- Void = night), Bloom / Rays / Contrast tune the glow, sun rays and punch,
-- and Ambient is the outdoor shadow color in daylight.

--------------------------------------------------------------------------------
-- Day and night. Everyone on a server sees the same time. Set
-- DayCycleMinutes to 0 to keep it afternoon forever. Admins can test with
-- !time day / sunset / night / cycle.
--------------------------------------------------------------------------------
Config.DayCycleMinutes = 16 -- one full day + night
Config.DayFraction = 0.72 -- share of the cycle that is daytime

--------------------------------------------------------------------------------
-- Lookup tables and helpers (built automatically, don't edit)
--------------------------------------------------------------------------------
Config.RarityById = {}
Config.CreatureByName = {}
for order, rarity in ipairs(Config.Rarities) do
	rarity.Order = order
	Config.RarityById[rarity.Id] = rarity
	for _, creature in ipairs(rarity.Creatures) do
		creature.Rarity = rarity.Id
		Config.CreatureByName[creature.Name] = creature
	end
end

function Config.WalkSpeed(speedStat: number): number
	local tens = math.log10(1 + math.max(0, speedStat))
	return math.min(Config.BaseWalkSpeed + Config.WalkPerTenfold * tens + Config.WalkCurve * tens * tens, Config.MaxWalkSpeed)
end

-- Speed stat needed to outrun a biome's guardian while carrying an egg.
function Config.RecommendedSpeed(biome): number
	return biome.SpeedNeeded
end

function Config.SpeedShopAmountFor(speedStat: number): number
	return math.max(Config.SpeedShopAmount, math.floor(speedStat * Config.SpeedShopPercent))
end

-- Each guardian runs just under your carry speed at its zone's SpeedNeeded
for _, biome in ipairs(Config.Biomes) do
	biome.GuardianSpeed = math.floor(Config.WalkSpeed(biome.SpeedNeeded) * Config.CarrySpeedMultiplier * Config.GuardianEdge * 10) / 10
end

function Config.SpeedShopCost(purchases: number): number
	return math.floor(Config.SpeedShopBaseCost * Config.SpeedShopGrowth ^ purchases)
end

function Config.TreadmillInterval(speedStat: number): number
	return math.min(Config.TreadmillMaxInterval, Config.TreadmillBaseInterval * (1 + speedStat / Config.TreadmillSlowdown))
end

-- How much Speed one treadmill tick gives: grows with your Speed so it stays worth it
function Config.TreadmillGain(speedStat: number): number
	return math.floor(1 + Config.TreadmillGainScale * math.sqrt(math.max(0, speedStat)))
end

-- data = { Name, Shiny, Tier }
function Config.CreatureIncome(data): number
	local def = Config.CreatureByName[data.Name]
	if not def then
		return 0
	end
	local tier = Config.Tiers[data.Tier or 1] or Config.Tiers[1]
	local income = def.Income * tier.Multiplier
	if data.Shiny then
		income *= Config.ShinyMultiplier
	end
	local mutation = data.Mutation and Config.MutationById[data.Mutation]
	if mutation then
		income *= mutation.Mult
	end
	income *= Config.Stages[Config.PetStage(data)].Mult
	income *= (data.Size or 1) ^ Config.SizeIncomePower
	return math.floor(income * 10 + 0.5) / 10
end

function Config.SellValue(data): number
	return math.floor(Config.CreatureIncome(data) * Config.SellSeconds)
end

function Config.CreatureTitle(data): string
	local tier = Config.Tiers[data.Tier or 1] or Config.Tiers[1]
	local name = tier.Prefix .. data.Name
	if data.Mutation and Config.MutationById[data.Mutation] then
		name = data.Mutation .. " " .. name
	end
	if data.Shiny then
		name = "Shiny " .. name
	end
	return name
end

return Config
