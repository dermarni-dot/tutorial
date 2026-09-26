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
-- Walk speed = BaseWalkSpeed + your Speed stat (capped at MaxWalkSpeed).
-- Carrying an egg multiplies it by CarrySpeedMultiplier.
--------------------------------------------------------------------------------
-- Speed stat can grow into the millions; walk speed grows with its log so you
-- never get silly fast: 0 -> 28, 1K -> 75, 25K -> 96, 1M -> 121 (capped at 135).
Config.BaseWalkSpeed = 28
Config.WalkPerTenfold = 15.5 -- extra walk speed every time your Speed goes x10
Config.MaxWalkSpeed = 135
Config.GuardianEdge = 0.995 -- guardians run this fraction of your carry speed at their zone's SpeedNeeded
Config.CarrySpeedMultiplier = 0.9
Config.StartingSpeed = 5 -- enough to outrun the first guardian

-- Treadmill: step on it to auto-run and gain +1 Speed every
-- TreadmillBaseInterval * (1 + Speed / TreadmillSlowdown) seconds.
Config.TreadmillBaseInterval = 1
Config.TreadmillSlowdown = 4
Config.TreadmillMaxInterval = 1 -- a gain every second
Config.TreadmillGainPercent = 0.009 -- each second you gain 1 + 0.9% of your Speed
Config.TreadmillBeltSpeed = 12 -- how fast the belt stripes scroll

-- Treadmill upgrades: the gold pad in your base buys better treadmills with
-- cash. Each one multiplies the Speed your treadmill gives.
Config.TreadmillLevels = {
	{ Name = "Basic", Mult = 1, Cost = 0, Color = Color3.fromRGB(255, 120, 120) },
	{ Name = "Bronze", Mult = 2, Cost = 2500, Color = Color3.fromRGB(205, 127, 50) },
	{ Name = "Silver", Mult = 4, Cost = 40000, Color = Color3.fromRGB(200, 205, 215) },
	{ Name = "Gold", Mult = 8, Cost = 500000, Color = Color3.fromRGB(255, 200, 50) },
	{ Name = "Diamond", Mult = 16, Cost = 8000000, Color = Color3.fromRGB(110, 230, 255) },
	{ Name = "Emerald", Mult = 32, Cost = 150000000, Color = Color3.fromRGB(60, 230, 120) },
	{ Name = "Cosmic", Mult = 64, Cost = 3000000000, Color = Color3.fromRGB(190, 110, 255) },
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
			{ Name = "Pebble Pup", Style = "Pup", Income = 1, Color = Color3.fromRGB(150, 140, 130) },
			{ Name = "Mossling", Style = "Moss", Income = 1, Color = Color3.fromRGB(110, 170, 90) },
			{ Name = "Chirpy", Style = "Bird", Income = 2, Color = Color3.fromRGB(250, 210, 90) },
			{ Name = "Bunbun", Style = "Bunny", Income = 1, Color = Color3.fromRGB(255, 225, 235) },
			{ Name = "Froggle", Style = "Frog", Income = 2, Color = Color3.fromRGB(120, 210, 90) },
			{ Name = "Slimey", Style = "Slime", Income = 2, Color = Color3.fromRGB(90, 220, 200) },
			{ Name = "Mochi Hamster", Style = "Hamster", Income = 1, Color = Color3.fromRGB(245, 200, 150) },
			{ Name = "Lil Chick", Style = "Chick", Income = 1, Color = Color3.fromRGB(255, 235, 120) },
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
			{ Name = "Fennec Fox", Style = "Fox", Income = 7, Color = Color3.fromRGB(245, 150, 70) },
			{ Name = "Pengu", Style = "Penguin", Income = 8, Color = Color3.fromRGB(55, 65, 90) },
			{ Name = "Hoot", Style = "Owl", Income = 9, Color = Color3.fromRGB(165, 120, 80) },
			{ Name = "Coco Monkey", Style = "Monkey", Income = 7, Color = Color3.fromRGB(150, 100, 60) },
			{ Name = "Sunny Duck", Style = "Duck", Income = 8, Color = Color3.fromRGB(255, 220, 60) },
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
			{ Name = "Pandy", Style = "Panda", Income = 42, Color = Color3.fromRGB(245, 245, 245) },
			{ Name = "Axolittle", Style = "Axolotl", Income = 48, Color = Color3.fromRGB(255, 160, 200) },
			{ Name = "Koi Fin", Style = "Koi", Income = 38, Color = Color3.fromRGB(255, 140, 60) },
			{ Name = "Shell Turtle", Style = "Turtle", Income = 42, Color = Color3.fromRGB(110, 170, 110) },
		},
	},
	{
		Id = "Epic",
		HatchTime = 75,
		Color = Color3.fromRGB(180, 90, 255),
		Creatures = {
			{ Name = "Voidmoth", Style = "Moth", Income = 220, Color = Color3.fromRGB(90, 50, 140) },
			{ Name = "Crystal Stag", Style = "Stag", Income = 260, Color = Color3.fromRGB(200, 160, 255) },
			{ Name = "Dino Rex", Style = "Dino", Income = 240, Color = Color3.fromRGB(110, 190, 90) },
			{ Name = "Jelly Queen", Style = "Jelly", Income = 280, Color = Color3.fromRGB(230, 130, 255) },
			{ Name = "Neon Newt", Style = "Newt", Income = 230, Color = Color3.fromRGB(80, 255, 200) },
			{ Name = "Storm Owl", Style = "Owl", Income = 250, Color = Color3.fromRGB(90, 110, 170) },
		},
	},
	{
		Id = "Legendary",
		HatchTime = 120,
		Color = Color3.fromRGB(255, 180, 40),
		Creatures = {
			{ Name = "Solar Drake", Style = "Drake", Income = 1500, Color = Color3.fromRGB(255, 160, 40) },
			{ Name = "Tidal Serpent", Style = "Serpent", Income = 1800, Color = Color3.fromRGB(40, 140, 220) },
			{ Name = "Starlight Unicorn", Style = "Unicorn", Income = 1700, Color = Color3.fromRGB(255, 250, 255) },
			{ Name = "Nine-Tail Kitsune", Style = "Kitsune", Income = 2100, Color = Color3.fromRGB(255, 240, 245), Weight = 0.6 },
			{ Name = "Sakura Fox", Style = "Fox", Income = 1600, Color = Color3.fromRGB(255, 170, 200) },
			{ Name = "Sun Phoenix", Style = "Phoenix", Income = 1900, Color = Color3.fromRGB(255, 150, 40) },
		},
	},
	{
		Id = "Mythic",
		HatchTime = 240,
		Color = Color3.fromRGB(255, 70, 110),
		Creatures = {
			{ Name = "Cosmic Phoenix", Style = "Phoenix", Income = 11000, Color = Color3.fromRGB(255, 90, 150) },
			{ Name = "Galaxy Dragon", Style = "Drake", Income = 12500, Color = Color3.fromRGB(120, 70, 220) },
			{ Name = "Void Kraken", Style = "Kraken", Income = 14000, Color = Color3.fromRGB(70, 40, 120), Weight = 0.5 },
			{ Name = "Abyss Serpent", Style = "Serpent", Income = 12000, Color = Color3.fromRGB(40, 50, 110) },
			{ Name = "Crystal King Stag", Style = "Stag", Income = 13000, Color = Color3.fromRGB(170, 120, 255) },
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
			{ Name = "Holy Panda", Style = "Panda", Income = 70000, Color = Color3.fromRGB(255, 245, 215) },
		},
	},
	{
		Id = "Secret",
		HatchTime = 600,
		Color = Color3.fromRGB(40, 40, 50),
		Creatures = {
			{ Name = "Glitch Cat", Style = "GlitchCat", Income = 350000, Color = Color3.fromRGB(35, 35, 45) },
			{ Name = "Rainbow Dragon", Style = "Drake", Income = 500000, Color = Color3.fromRGB(255, 120, 200), Weight = 0.5 },
			{ Name = "404 Bunny", Style = "GlitchBunny", Income = 400000, Color = Color3.fromRGB(30, 30, 38) },
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
		Mood = { Color = Color3.fromRGB(175, 215, 240), Decay = Color3.fromRGB(95, 135, 110), Density = 0.3, Haze = 0.6, Glare = 0.2, Tint = Color3.fromRGB(245, 255, 242), Brightness = 0, Saturation = 0.18, CloudColor = Color3.fromRGB(255, 255, 255), CloudCover = 0.6 },
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
		Mood = { Color = Color3.fromRGB(240, 215, 175), Decay = Color3.fromRGB(200, 150, 100), Density = 0.34, Haze = 1.2, Glare = 0.4, Tint = Color3.fromRGB(255, 246, 228), Brightness = 0.01, Saturation = 0.15, CloudColor = Color3.fromRGB(255, 238, 215), CloudCover = 0.45 },
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
		Mood = { Color = Color3.fromRGB(210, 228, 255), Decay = Color3.fromRGB(150, 180, 220), Density = 0.4, Haze = 1.2, Glare = 0.15, Tint = Color3.fromRGB(236, 246, 255), Brightness = 0, Saturation = 0.02, CloudColor = Color3.fromRGB(235, 242, 255), CloudCover = 0.75 },
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
		Mood = { Color = Color3.fromRGB(230, 130, 95), Decay = Color3.fromRGB(110, 40, 25), Density = 0.44, Haze = 1.6, Glare = 0.3, Tint = Color3.fromRGB(255, 224, 208), Brightness = -0.02, Saturation = 0.2, CloudColor = Color3.fromRGB(95, 65, 60), CloudCover = 0.8 },
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
		Mood = { Color = Color3.fromRGB(140, 100, 215), Decay = Color3.fromRGB(45, 20, 90), Density = 0.44, Haze = 1, Glare = 0.2, Tint = Color3.fromRGB(222, 205, 255), Brightness = -0.05, Saturation = 0.25, CloudColor = Color3.fromRGB(150, 105, 220), CloudCover = 0.7 },
	},
}

-- Town floor and wall colors (checkerboard pairs)
Config.TownFloor = { Color3.fromRGB(116, 206, 78), Color3.fromRGB(100, 190, 66) }
Config.TownWalls = { Color3.fromRGB(214, 122, 82), Color3.fromRGB(230, 142, 98) }

-- Lighting mood in town (the client blends between moods as you travel).
Config.TownMood = { Color = Color3.fromRGB(180, 212, 255), Decay = Color3.fromRGB(92, 122, 172), Density = 0.26, Haze = 0.35, Glare = 0.2, Tint = Color3.fromRGB(255, 251, 245), Brightness = 0, Saturation = 0.15, CloudColor = Color3.fromRGB(255, 255, 255), CloudCover = 0.6 }

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
	return math.min(Config.BaseWalkSpeed + Config.WalkPerTenfold * math.log10(1 + math.max(0, speedStat)), Config.MaxWalkSpeed)
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
	return math.floor(1 + speedStat * Config.TreadmillGainPercent)
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
