-- Config: core tunable data for "Become a World Class Boxer"
local Config = {}

Config.GameName = "Become a World Class Boxer"
Config.DataStoreName = "WorldClassBoxer_v2"
Config.DataVersion = 2
Config.RoundSeconds = 60 -- real-time length of one fight round
Config.RestSeconds = 7 -- between rounds
Config.SparRoundSeconds = 45
Config.StatCap = 99
Config.WorldPerClass = 30 -- AI boxers per weight class (9 classes = 270 boxers)
Config.GainScale = 1.35 -- global training gain multiplier

Config.StatKeys = {
	"PunchSpeed", "Power", "Endurance", "Stamina", "Footwork", "HeadMovement",
	"Blocking", "Countering", "RingIQ", "Chin", "Reflexes", "Recovery",
}
Config.StatNames = {
	PunchSpeed = "Punch Speed", Power = "Knockout Power", Endurance = "Endurance",
	Stamina = "Stamina", Footwork = "Footwork", HeadMovement = "Head Movement",
	Blocking = "Blocking", Countering = "Countering", RingIQ = "Ring IQ",
	Chin = "Chin", Reflexes = "Reflexes", Recovery = "Recovery",
}
Config.MentalKeys = { "Confidence", "Discipline", "Aggression", "Focus", "Composure" }

Config.MuscleKeys = { "chest", "shoulders", "arms", "back", "legs", "core", "neck" }
Config.MuscleNames = {
	chest = "Chest", shoulders = "Shoulders", arms = "Arms", back = "Back",
	legs = "Legs", core = "Core", neck = "Neck",
}

Config.WeightClasses = {
	{ name = "Flyweight", limit = 112, min = 105 },
	{ name = "Bantamweight", limit = 118, min = 113 },
	{ name = "Featherweight", limit = 126, min = 119 },
	{ name = "Lightweight", limit = 135, min = 127 },
	{ name = "Welterweight", limit = 147, min = 136 },
	{ name = "Middleweight", limit = 160, min = 148 },
	{ name = "Light Heavyweight", limit = 175, min = 161 },
	{ name = "Cruiserweight", limit = 200, min = 176 },
	{ name = "Heavyweight", limit = 280, min = 201 },
}

-- ai.range = preferred distance as a share of the fighter's jab range
Config.Styles = {
	{
		id = "OutBoxer", name = "Out-Boxer", desc = "Fast movement, strong jab, high stamina",
		mods = { PunchSpeed = 5, Footwork = 8, Stamina = 6, Endurance = 3, Power = -6 },
		fight = { jab = 1.3, combo = 1.0, inside = 0.9, power = 0.92, counter = 1.0, move = 1.2 },
		ai = { range = 0.94, aggression = 0.35, jabRate = 0.55 },
	},
	{
		id = "Swarmer", name = "Swarmer", desc = "Aggressive pressure, fast combinations, strong inside",
		mods = { PunchSpeed = 5, Endurance = 6, Chin = 4, HeadMovement = 3, Footwork = -2, Blocking = -2 },
		fight = { jab = 0.9, combo = 1.3, inside = 1.15, power = 1.0, counter = 0.9, move = 1.05 },
		ai = { range = 0.72, aggression = 0.8, jabRate = 0.2 },
	},
	{
		id = "Slugger", name = "Slugger", desc = "Huge knockout power, lower speed",
		mods = { Power = 12, Chin = 6, PunchSpeed = -6, Footwork = -6, HeadMovement = -2 },
		fight = { jab = 0.85, combo = 0.9, inside = 1.08, power = 1.22, counter = 0.9, move = 0.9 },
		ai = { range = 0.8, aggression = 0.65, jabRate = 0.2 },
	},
	{
		id = "BoxerPuncher", name = "Boxer-Puncher", desc = "Balanced offense and defense",
		mods = { Power = 3, Blocking = 3, PunchSpeed = 3, RingIQ = 3 },
		fight = { jab = 1.1, combo = 1.1, inside = 1.0, power = 1.08, counter = 1.1, move = 1.05 },
		ai = { range = 0.86, aggression = 0.55, jabRate = 0.4 },
	},
	{
		id = "CounterPuncher", name = "Counter Puncher", desc = "Reads opponents, big timing bonuses",
		mods = { Countering = 10, Reflexes = 6, RingIQ = 4, Power = -2, Endurance = -1 },
		fight = { jab = 1.0, combo = 0.95, inside = 0.95, power = 1.0, counter = 1.6, move = 1.05 },
		ai = { range = 0.9, aggression = 0.3, jabRate = 0.35 },
	},
}

-- AI personalities in the ring. Each maps to a style and defensive habits.
Config.Archetypes = {
	{ id = "Pressure", name = "Aggressive Pressure Fighter", style = "Swarmer",
		ai = { aggr = 0.15, block = 0.25, slip = 0.2, roll = 0.3, parry = 0.05, pivot = 0.05, body = 0.22, overhand = 0.05, adapt = 1.0 } },
	{ id = "Counter", name = "Fast Counter Puncher", style = "CounterPuncher",
		ai = { aggr = -0.1, block = 0.2, slip = 0.45, roll = 0.15, parry = 0.35, pivot = 0.15, body = 0.05, overhand = 0.03, adapt = 1.2 } },
	{ id = "Technician", name = "Technical Genius", style = "BoxerPuncher",
		ai = { aggr = 0.0, block = 0.3, slip = 0.3, roll = 0.2, parry = 0.2, pivot = 0.25, body = 0.12, overhand = 0.05, adapt = 1.6 } },
	{ id = "KO", name = "Knockout Artist", style = "Slugger",
		ai = { aggr = 0.05, block = 0.3, slip = 0.1, roll = 0.1, parry = 0.02, pivot = 0.02, body = 0.1, overhand = 0.25, adapt = 0.8 } },
	{ id = "Defensive", name = "Defensive Specialist", style = "OutBoxer",
		ai = { aggr = -0.2, block = 0.45, slip = 0.35, roll = 0.25, parry = 0.25, pivot = 0.35, body = 0.02, overhand = 0.0, adapt = 1.1 } },
}

Config.Specialties = {
	{ id = "Speed", stats = { PunchSpeed = 8 } },
	{ id = "Strength", stats = { Power = 5, Chin = 3 } },
	{ id = "Agility", stats = { Footwork = 4, HeadMovement = 4 } },
	{ id = "Endurance", stats = { Endurance = 5, Stamina = 3 } },
	{ id = "Chin", stats = { Chin = 8 } },
	{ id = "Defense", stats = { Blocking = 5, HeadMovement = 3 } },
	{ id = "Reflexes", stats = { Reflexes = 8 } },
	{ id = "Power Punching", stats = { Power = 8 } },
	{ id = "Footwork", stats = { Footwork = 8 } },
	{ id = "Ring IQ", stats = { RingIQ = 5, Countering = 3 } },
}

-- Body types set the frame (bone structure) and how much muscle the boxer can build.
-- Everyone starts lean with low muscle mass; training does the rest.
Config.BodyTypes = {
	{ id = "Lean", width = 0.92, depth = 0.92, potential = 0.8, mods = { Footwork = 3, PunchSpeed = 2, Power = -2 } },
	{ id = "Athletic", width = 1.0, depth = 1.0, potential = 0.95, mods = { Stamina = 2, Footwork = 1 } },
	{ id = "Muscular", width = 1.05, depth = 1.03, potential = 1.05, mods = { Power = 2, Chin = 1 } },
	{ id = "Power Build", width = 1.1, depth = 1.07, potential = 1.15, mods = { Power = 3, Chin = 2, PunchSpeed = -1, Footwork = -2 } },
	{ id = "Heavyweight Build", width = 1.18, depth = 1.14, potential = 1.25, mods = { Power = 4, Chin = 3, PunchSpeed = -2, Footwork = -3, Stamina = -2 } },
}

-- Career tiers. rounds = fight length at that tier; campDays = days of training camp.
Config.Tiers = {
	{ name = "Amateur", rounds = 3, purse = { 50, 200 }, campDays = 3 },
	{ name = "Local Pro", rounds = 4, purse = { 1500, 5000 }, campDays = 4 },
	{ name = "Regional Champion", rounds = 6, purse = { 8000, 20000 }, campDays = 5 },
	{ name = "National Champion", rounds = 8, purse = { 30000, 80000 }, campDays = 5 },
	{ name = "International Contender", rounds = 10, purse = { 100000, 250000 }, campDays = 6 },
	{ name = "Top 10 Ranked", rounds = 10, purse = { 300000, 800000 }, campDays = 6 },
	{ name = "Title Challenger", rounds = 12, purse = { 800000, 1500000 }, campDays = 7 },
	{ name = "World Champion", rounds = 12, purse = { 2500000, 6000000 }, campDays = 7 },
	{ name = "Undisputed Champion", rounds = 12, purse = { 8000000, 20000000 }, campDays = 8 },
	{ name = "Boxing Legend", rounds = 12, purse = { 10000000, 30000000 }, campDays = 8 },
}

Config.Orgs = { "WBA", "WBC", "IBF", "WBO" }

-- Fight venues (ring system)
Config.Venues = {
	CommunityCenter = { name = "Community Center", kind = "Local Ring" },
	ClubArena = { name = "City Club Arena", kind = "Local Ring" },
	Arena = { name = "Grand Arena", kind = "Professional Ring" },
	Stadium = { name = "National Stadium", kind = "World Title Ring" },
}
function Config.VenueFor(kind, tier)
	if kind == "World Title" or kind == "Unification" or kind == "Title Defense" or tier >= 8 then
		return "Stadium"
	elseif kind == "Amateur Bout" or tier <= 1 then
		return "CommunityCenter"
	elseif tier <= 3 or kind == "Regional Title" then
		return "ClubArena"
	end
	return "Arena"
end

-- Punches: base damage, stamina cost, windup seconds (before speed scaling), hit chance, range mult
Config.PunchList = { "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }
Config.PunchNames = {
	jab = "Jab", cross = "Cross", leadhook = "Lead Hook", rearhook = "Rear Hook",
	uppercut = "Uppercut", overhand = "Overhand",
}
Config.Punches = {
	jab = { dmg = 3.0, stam = 2.5, windup = 0.16, hit = 0.82, range = 1.10, cutChance = 0.01, hand = "L", kind = "straight" },
	cross = { dmg = 6.5, stam = 5.0, windup = 0.24, hit = 0.70, range = 1.05, cutChance = 0.03, hand = "R", kind = "straight" },
	leadhook = { dmg = 7.5, stam = 5.5, windup = 0.26, hit = 0.64, range = 0.85, cutChance = 0.05, hand = "L", kind = "hook" },
	rearhook = { dmg = 8.5, stam = 6.5, windup = 0.30, hit = 0.60, range = 0.85, cutChance = 0.05, hand = "R", kind = "hook" },
	uppercut = { dmg = 9.0, stam = 6.5, windup = 0.30, hit = 0.58, range = 0.75, cutChance = 0.03, hand = "R", kind = "uppercut" },
	overhand = { dmg = 10.5, stam = 8.5, windup = 0.42, hit = 0.52, range = 1.0, cutChance = 0.06, hand = "R", kind = "overhand", overGuard = 0.5 },
}

------------------------------------------------------------------------
-- Training
------------------------------------------------------------------------
-- minigame types: combo, rhythm, reaction, mitts, shadow, reps, pace, course, swim, ladder, rope, hold, spar
Config.Activities = {
	{ id = "HeavyBag", name = "Heavy Bag", area = "Boxing Area", station = "heavybag", minigame = "combo", pose = "heavybag",
		energy = 22, hydration = 8, nutrition = 6, fatigue = 16, fat = -0.08,
		gains = { Power = 1.0, Endurance = 0.5, PunchSpeed = 0.4, RingIQ = 0.25 },
		muscle = { shoulders = 0.7, arms = 0.4, core = 0.3 }, wear = { gloves = 1.0, wraps = 0.8 },
		injuries = { "wrist", "shoulder" }, desc = "Punch power, endurance, combination speed, technique" },
	{ id = "SpeedBag", name = "Speed Bag", area = "Boxing Area", station = "speedbag", minigame = "rhythm", pose = "speedbag",
		energy = 14, hydration = 5, nutrition = 3, fatigue = 9, fat = -0.04,
		gains = { PunchSpeed = 1.0, Reflexes = 0.5, RingIQ = 0.25 },
		muscle = { shoulders = 0.35, arms = 0.3 }, wear = { gloves = 0.3, wraps = 0.5 },
		injuries = { "wrist" }, desc = "Hand speed, rhythm, timing, coordination" },
	{ id = "DoubleEnd", name = "Double-End Bag", area = "Boxing Area", station = "doubleend", minigame = "reaction", pose = "guard",
		energy = 16, hydration = 6, nutrition = 4, fatigue = 11, fat = -0.05,
		gains = { Reflexes = 0.9, HeadMovement = 0.6, Countering = 0.8, Blocking = 0.3 },
		muscle = { shoulders = 0.25 }, wear = { gloves = 0.5, wraps = 0.3 },
		injuries = { "wrist" }, desc = "Defense, reflexes, counter punching" },
	{ id = "MittWork", name = "Mitt Work", area = "Boxing Area", station = "mitts", minigame = "mitts", pose = "guard",
		energy = 22, hydration = 8, nutrition = 5, fatigue = 14, fat = -0.07,
		gains = { PunchSpeed = 0.5, Countering = 0.6, Power = 0.3, RingIQ = 0.7 },
		muscle = { shoulders = 0.45, arms = 0.3, core = 0.2 }, wear = { gloves = 0.8, wraps = 0.5 },
		injuries = { "wrist", "shoulder" }, desc = "Coach-called combinations, timing, Ring IQ" },
	{ id = "Shadow", name = "Shadow Boxing", area = "Boxing Area", station = "mirror", minigame = "shadow", pose = "guard",
		energy = 12, hydration = 5, nutrition = 3, fatigue = 8, fat = -0.05,
		gains = { Footwork = 0.6, HeadMovement = 0.6, RingIQ = 0.45 },
		muscle = { shoulders = 0.2 }, wear = { shoes = 0.3 },
		injuries = {}, desc = "Footwork, head movement, ring craft" },
	{ id = "Sparring", name = "Sparring", area = "Boxing Area", station = "ring", minigame = "spar", pose = "guard",
		energy = 30, hydration = 12, nutrition = 8, fatigue = 24, fat = -0.1,
		gains = { RingIQ = 0.8, Countering = 0.6, Blocking = 0.6, HeadMovement = 0.5, Chin = 0.4 },
		muscle = { neck = 0.4, shoulders = 0.2 }, wear = { gloves = 1.2, wraps = 0.8, shoes = 0.4 },
		injuries = { "ribs", "cut" }, desc = "Live rounds: experience, timing, defense, Ring IQ" },
	{ id = "Bench", name = "Weight Bench", area = "Weight Room", station = "bench", minigame = "reps", pose = "bench",
		energy = 22, hydration = 5, nutrition = 8, fatigue = 15, fat = -0.04,
		gains = { Power = 0.8, Chin = 0.2 }, muscle = { chest = 1.3, shoulders = 0.5, arms = 0.4 },
		wear = { wraps = 0.2 }, injuries = { "shoulder" }, desc = "Upper body strength, punching power" },
	{ id = "Dumbbells", name = "Dumbbells", area = "Weight Room", station = "dumbbells", minigame = "reps", pose = "curl",
		energy = 16, hydration = 4, nutrition = 6, fatigue = 11, fat = -0.03,
		gains = { Power = 0.4, Blocking = 0.45 }, muscle = { arms = 1.4, shoulders = 0.4 },
		wear = {}, injuries = { "wrist" }, desc = "Arm strength, stability" },
	{ id = "Barbell", name = "Barbell Deadlifts", area = "Weight Room", station = "barbell", minigame = "reps", pose = "deadlift",
		energy = 26, hydration = 6, nutrition = 9, fatigue = 17, fat = -0.05,
		gains = { Power = 0.7, Endurance = 0.35 }, muscle = { back = 0.9, legs = 0.6, core = 0.5, neck = 0.3 },
		wear = {}, injuries = { "back" }, desc = "Total-body strength, traps and back" },
	{ id = "Squat", name = "Squat Rack", area = "Weight Room", station = "squat", minigame = "reps", pose = "squat",
		energy = 26, hydration = 6, nutrition = 9, fatigue = 18, fat = -0.05,
		gains = { Power = 0.5, Footwork = 0.5 }, muscle = { legs = 1.5, core = 0.3 },
		wear = { shoes = 0.2 }, injuries = { "hamstring", "back" }, desc = "Leg power, explosiveness" },
	{ id = "PullUps", name = "Pull-Up Station", area = "Weight Room", station = "pullup", minigame = "reps", pose = "pullup",
		energy = 18, hydration = 5, nutrition = 6, fatigue = 13, fat = -0.04,
		gains = { Endurance = 0.5, Power = 0.3 }, muscle = { back = 1.4, arms = 0.5 },
		wear = {}, injuries = { "shoulder" }, desc = "Back strength, endurance, posture" },
	{ id = "Roadwork", name = "Roadwork Running", area = "Outdoors", station = "track", minigame = "course", pose = "none",
		energy = 26, hydration = 15, nutrition = 8, fatigue = 15, fat = -0.45,
		gains = { Stamina = 1.0, Endurance = 0.7, Recovery = 0.3 }, muscle = { legs = 0.45 },
		wear = { shoes = 1.5 }, injuries = { "hamstring", "ankle" }, desc = "Stamina, endurance, conditioning, burns fat" },
	{ id = "Treadmill", name = "Treadmill", area = "Cardio Room", station = "treadmill", minigame = "pace", pose = "run",
		energy = 18, hydration = 10, nutrition = 5, fatigue = 11, fat = -0.3,
		gains = { Stamina = 0.6, Recovery = 0.6 }, muscle = { legs = 0.3 },
		wear = { shoes = 0.8 }, injuries = { "hamstring" }, desc = "Fitness, recovery" },
	{ id = "Bike", name = "Bike", area = "Cardio Room", station = "bike", minigame = "pace", pose = "bike",
		energy = 16, hydration = 9, nutrition = 5, fatigue = 9, fat = -0.25,
		gains = { Stamina = 0.5, Endurance = 0.5, Recovery = 0.3 }, muscle = { legs = 0.5 },
		wear = {}, injuries = {}, desc = "Low-impact conditioning" },
	{ id = "Rower", name = "Row Machine", area = "Cardio Room", station = "rower", minigame = "pace", pose = "row",
		energy = 18, hydration = 9, nutrition = 6, fatigue = 12, fat = -0.3,
		gains = { Stamina = 0.5, Endurance = 0.6, Power = 0.2 }, muscle = { back = 0.6, legs = 0.3, arms = 0.2 },
		wear = {}, injuries = { "back" }, desc = "Full-body conditioning" },
	{ id = "Swimming", name = "Swimming Laps", area = "Pool", station = "pool", minigame = "swim", pose = "none",
		energy = 22, hydration = 6, nutrition = 8, fatigue = 10, fat = -0.35,
		gains = { Stamina = 0.8, Recovery = 0.9, Endurance = 0.5 },
		muscle = { shoulders = 0.5, back = 0.5, chest = 0.3, arms = 0.3, legs = 0.3, core = 0.3 },
		wear = {}, injuries = {}, desc = "Stamina, recovery, full-body development" },
	{ id = "Ladder", name = "Agility Ladder", area = "Cardio Room", station = "ladder", minigame = "ladder", pose = "ladder",
		energy = 14, hydration = 6, nutrition = 4, fatigue = 9, fat = -0.12,
		gains = { Footwork = 1.0, PunchSpeed = 0.2, Reflexes = 0.3 }, muscle = { legs = 0.3 },
		wear = { shoes = 1.0 }, injuries = { "ankle" }, desc = "Footwork, speed, movement" },
	{ id = "Rope", name = "Jump Rope", area = "Cardio Room", station = "rope", minigame = "rope", pose = "rope",
		energy = 16, hydration = 8, nutrition = 4, fatigue = 10, fat = -0.25,
		gains = { Stamina = 0.5, Footwork = 0.6, Reflexes = 0.3, PunchSpeed = 0.2 }, muscle = { legs = 0.4 },
		wear = { shoes = 0.8 }, injuries = { "ankle" }, desc = "Conditioning, rhythm, foot speed" },
	-- Recovery (no stat gains)
	{ id = "IceBath", name = "Ice Bath", area = "Recovery Area", station = "icebath", minigame = "hold", pose = "sit",
		recovery = { fatigue = -24, energy = 5, heal = 1 }, desc = "Cuts fatigue and soreness, speeds injury healing" },
	{ id = "Stretch", name = "Stretching", area = "Recovery Area", station = "stretch", minigame = "hold", pose = "stretch",
		recovery = { fatigue = -12, energy = 3, heal = 0.5, flexible = true }, desc = "Lowers injury risk for the rest of the day" },
	{ id = "Massage", name = "Massage Table", area = "Recovery Area", station = "massage", minigame = "hold", pose = "lie",
		recovery = { fatigue = -30, energy = 8, heal = 1 }, price = 100, desc = "Deep recovery (free with a therapist upgrade)" },
	{ id = "Chamber", name = "Elite Recovery Chamber", area = "Recovery Area", station = "chamber", minigame = "hold", pose = "lie",
		recovery = { fatigue = -50, energy = 25, heal = 2 }, requires = "RecoveryChamber", desc = "End-game recovery tech" },
	{ id = "Sauna", name = "Sauna (Weight Cut)", area = "Recovery Area", station = "sauna", minigame = "hold", pose = "sit",
		recovery = { fatigue = 4, energy = -10, hydration = -25, water = -2.5 }, desc = "Sweat out water weight before a weigh-in" },
}

Config.Injuries = {
	wrist = { name = "Sprained Wrist", days = { 3, 6 }, blocks = { "HeavyBag", "SpeedBag", "MittWork", "DoubleEnd", "Dumbbells", "Sparring" }, fight = { Power = -6, PunchSpeed = -4 } },
	shoulder = { name = "Shoulder Strain", days = { 4, 8 }, blocks = { "Bench", "PullUps", "HeavyBag", "Swimming", "Rower" }, fight = { Power = -5, Blocking = -3 } },
	hamstring = { name = "Pulled Hamstring", days = { 4, 8 }, blocks = { "Roadwork", "Squat", "Ladder", "Rope", "Treadmill" }, fight = { Footwork = -8 } },
	back = { name = "Back Spasm", days = { 3, 7 }, blocks = { "Barbell", "Squat", "PullUps", "Rower" }, fight = { Power = -4, Endurance = -4 } },
	ankle = { name = "Rolled Ankle", days = { 3, 6 }, blocks = { "Roadwork", "Ladder", "Rope", "Treadmill" }, fight = { Footwork = -6 } },
	ribs = { name = "Bruised Ribs", days = { 5, 10 }, blocks = { "Sparring", "Rower", "Swimming" }, fight = { Endurance = -6, Chin = -3 } },
	cut = { name = "Cut Eyebrow", days = { 6, 12 }, blocks = { "Sparring" }, fight = { Chin = -2 }, reopens = true },
}

Config.Meals = {
	{ id = "Water", name = "Water (Cooler)", price = 0, hydration = 35, nutrition = 0, energy = 0, fat = 0 },
	{ id = "SportsDrink", name = "Sports Drink", price = 6, hydration = 45, nutrition = 5, energy = 4, fat = 0 },
	{ id = "FastFood", name = "Fast Food Burger", price = 12, hydration = -5, nutrition = 35, energy = 4, fat = 0.35 },
	{ id = "Balanced", name = "Balanced Meal", price = 45, hydration = 5, nutrition = 40, energy = 6, fat = 0 },
	{ id = "Protein", name = "Protein Shake", price = 25, hydration = 10, nutrition = 20, energy = 3, fat = 0, muscleBuff = 0.15 },
	{ id = "Athlete", name = "Athlete Meal Plan", price = 160, hydration = 10, nutrition = 60, energy = 10, fat = -0.05, gainsBuff = 0.1 },
	{ id = "Chef", name = "Personal Chef Feast", price = 600, hydration = 15, nutrition = 75, energy = 15, fat = -0.1, gainsBuff = 0.2, requires = "Nutritionist" },
}

Config.MittCombos = {
	-- tier 1
	{ tier = 1, name = "1-2", keys = { "jab", "cross" } },
	{ tier = 1, name = "1-1-2", keys = { "jab", "jab", "cross" } },
	{ tier = 1, name = "1-2-3", keys = { "jab", "cross", "leadhook" } },
	-- tier 2
	{ tier = 2, name = "Jab-Hook-Cross", keys = { "jab", "leadhook", "cross" } },
	{ tier = 2, name = "2-3-2", keys = { "cross", "leadhook", "cross" } },
	{ tier = 2, name = "1-2-Slip-2", keys = { "jab", "cross", "slipL", "cross" } },
	-- tier 3
	{ tier = 3, name = "Slip-Cross-Hook", keys = { "slipR", "cross", "leadhook" } },
	{ tier = 3, name = "1-2-3-2", keys = { "jab", "cross", "leadhook", "cross" } },
	{ tier = 3, name = "Body Jab-Head Cross", keys = { "jab", "cross", "rearhook" } },
	-- tier 4
	{ tier = 4, name = "Roll-Hook-Hook", keys = { "roll", "leadhook", "rearhook" } },
	{ tier = 4, name = "1-2-Uppercut-Hook", keys = { "jab", "cross", "uppercut", "leadhook" } },
	{ tier = 4, name = "Slip-Slip-Overhand", keys = { "slipL", "slipR", "overhand" } },
	-- tier 5
	{ tier = 5, name = "Champion Flurry", keys = { "jab", "cross", "leadhook", "rearhook", "uppercut" } },
	{ tier = 5, name = "Pivot-Hook-Cross-Hook", keys = { "pivotL", "leadhook", "cross", "leadhook" } },
	{ tier = 5, name = "Parry-Cross-Roll-Hook", keys = { "parry", "cross", "roll", "leadhook" } },
}
Config.MittPraise = { "That's it!", "Beautiful!", "Sharp!", "Again!", "Good, good!", "Snap it back!", "Yes! Like that!" }
Config.MittCritique = {
	sloppy = { "Clean it up!", "Don't telegraph it!", "Hands back to the chin!", "Throw what I call!" },
	slow = { "Too slow - stay sharp!", "Finish the combo!", "Faster hands!", "Don't think, react!" },
}

------------------------------------------------------------------------
-- Training sessions: drill data, coaching, grades and records
------------------------------------------------------------------------
-- one real second of a drill counts as this many seconds of training for the
-- calorie / distance / time-in readouts (a 40 s session stands in for a few minutes of work)
Config.TrainingTimeScale = 6

-- working heart-rate target (bpm) while training hard at each activity
Config.TrainingHR = {
	HeavyBag = 170, SpeedBag = 150, DoubleEnd = 156, MittWork = 166, Shadow = 142,
	Bench = 128, Dumbbells = 120, Barbell = 140, Squat = 142, PullUps = 134,
	Roadwork = 172, Treadmill = 170, Bike = 166, Rower = 172, Swimming = 158,
	Ladder = 154, Rope = 166,
}
-- recovery sessions settle the heart rate around resting HR + this offset (the sauna's heat raises it)
Config.RecoveryHR = { IceBath = -4, Stretch = 2, Massage = -6, Chamber = -8, Sauna = 44 }

-- session grades from the server's session quality (0.4 .. 1.5)
Config.Grades = {
	{ id = "S", min = 1.35, rgb = { 255, 196, 40 } },
	{ id = "A", min = 1.2, rgb = { 60, 200, 110 } },
	{ id = "B", min = 1.0, rgb = { 70, 140, 255 } },
	{ id = "C", min = 0.8, rgb = { 240, 140, 40 } },
	{ id = "D", min = 0, rgb = { 220, 40, 45 } },
}

-- coach technique tips, shown during rests between rounds and sets
Config.TrainingTips = {
	HeavyBag = {
		"Turn your hip into the cross.", "Exhale on every shot.", "Hands back to the chin after every punch.",
		"Power starts in your back foot - push off the floor.", "Punch through the bag, not at it.",
		"Move after every combination - don't stand and admire it.",
	},
	SpeedBag = {
		"Small circles - let the bag do the work.", "Keep your fists at eye level.",
		"Relax your shoulders - tension kills rhythm.", "Listen to the rhythm. It's a drum, not a fight.",
		"Hit with the side of the fist, not the knuckles.",
	},
	DoubleEnd = {
		"Watch the bag, not your gloves.", "Slip just enough - an inch is as good as a mile.",
		"Counter the moment it comes back.", "Keep your chin tucked behind your shoulder.",
		"Short, sharp shots - this bag punishes wide punches.",
	},
	MittWork = {
		"Listen for the call, then snap it back.", "Hit the mitt and return on the same line.",
		"Stay in your stance between combos.", "Breathe out sharp on every punch.",
		"After a slip, the counter comes right away.",
	},
	Shadow = {
		"Picture an opponent in front of you.", "Never cross your feet.", "Move your head after you punch.",
		"Small steps keep you balanced.", "Check the mirror: chin down, hands up.",
	},
	Bench = {
		"Shoulder blades pinched, feet planted.", "Lower it under control, drive it up hard.",
		"Breathe in on the way down, out on the push.", "Touch mid-chest on every rep.",
	},
	Dumbbells = {
		"No swinging - make the arms do the work.", "Elbows pinned to your sides.",
		"Squeeze at the top, slow on the way down.", "Strong hands make strong punches.",
	},
	Barbell = {
		"Flat back, chest up.", "Push the floor away - don't yank the bar.", "Keep the bar close to your shins.",
		"Lock out with your hips, not your lower back.", "Brace your core before every pull.",
	},
	Squat = {
		"Knees track over your toes.", "Sit back and down, chest proud.", "Drive up through your heels.",
		"Brace like you're about to take a body shot.",
	},
	PullUps = {
		"Full hang at the bottom, chin over the bar at the top.", "Pull your elbows down to your ribs.",
		"No kipping - strict reps build a strong back.", "Squeeze your shoulder blades together.",
	},
	Roadwork = {
		"Run tall with relaxed shoulders.", "Find a steady breathing rhythm.", "Roadwork wins the late rounds.",
		"Push the hills, recover on the flats.",
	},
	Treadmill = {
		"Light, quick steps - land under your hips.", "Sprint hard, then really recover.", "Your arms drive your legs.",
		"Fight pace is intervals, not jogging.",
	},
	Bike = {
		"Smooth circles, not stomps.", "Push the sprints, spin easy to recover.", "Keep your upper body still.",
		"Low impact, big engine.",
	},
	Rower = {
		"Legs, then back, then arms.", "Fast drive, slow recovery.", "Sit tall at the catch - don't hunch.",
		"The power comes from your legs, not your arms.",
	},
	Swimming = {
		"Long strokes, steady breathing.", "Swimming builds lungs without pounding the joints.",
		"Push off the wall hard every length.", "Relax your neck when you breathe.",
	},
	Ladder = {
		"Stay on the balls of your feet.", "Quick feet, quiet feet.", "Eyes up - feel the ladder.",
		"Let your arms move with your feet.",
	},
	Rope = {
		"Small jumps - an inch off the floor.", "Turn the rope with your wrists, not your arms.",
		"Land soft on the balls of your feet.", "Stay relaxed and find the rhythm.",
		"Skipping builds the legs for twelve rounds.",
	},
	IceBath = {
		"Slow breaths - fight the urge to gasp.", "The cold flushes soreness out of the muscles.",
		"Relax your shoulders and let the cold work.",
	},
	Stretch = {
		"Never bounce a stretch - ease into it.", "Breathe out to sink deeper.", "Loose muscles get injured less.",
	},
	Massage = {
		"Let the tension go on every exhale.", "Deep tissue work speeds up recovery.", "Relax into the table.",
	},
	Chamber = {
		"Oxygen, compression and cold - elite recovery.", "Breathe deep and let the machine work.",
		"Champions recover like champions.",
	},
	Sauna = {
		"Sweat out water, not muscle.", "Rehydrate right after the weigh-in.",
		"Dizzy means get out - cutting weight is not a contest.", "Small sips only until you make weight.",
	},
}

-- the coach's verdict on the result screen
Config.GradeRemarks = {
	S = { "World-class session. That's how champions train.", "Perfect. I've got nothing to fix today.", "Championship work - bottle that." },
	A = { "Sharp work. Keep that standard.", "Really good session - just small details left.", "That's the level. Again tomorrow." },
	B = { "Solid work. Now clean up the details.", "Good session - next time make it great.", "Decent. More focus next time." },
	C = { "You got through it. I need more snap.", "Sloppy in places - concentrate.", "Average. Champions don't do average." },
	D = { "That wasn't good enough. Reset and go again.", "Your mind was somewhere else today.", "We're going back to basics." },
}
-- activity-specific remarks for great (hi) and poor (lo) sessions
Config.ActivityRemarks = {
	HeavyBag = { hi = "That bag felt every shot. Heavy hands!", lo = "You're pushing the bag, not punching it. Snap!" },
	SpeedBag = { hi = "Like a drum roll - beautiful rhythm.", lo = "You're chasing the bag. Find the rhythm first." },
	DoubleEnd = { hi = "Eyes like a hawk. Nothing got through.", lo = "That bag tagged you all day. Watch it!" },
	MittWork = { hi = "Crisp. You were reading my mind.", lo = "Listen to the call before you throw." },
	Shadow = { hi = "Smooth as silk in the mirror.", lo = "Your feet were stuck. Move with purpose." },
	Bench = { hi = "Strong press. That's real power.", lo = "Control the bar - don't let it control you." },
	Dumbbells = { hi = "Clean curls, no cheating. Good.", lo = "Too much swinging. Strict reps." },
	Barbell = { hi = "Textbook pulls. Strong back.", lo = "Watch that back - technique before weight." },
	Squat = { hi = "Deep and powerful. Those legs carry punches.", lo = "Too shallow. Sit into it." },
	PullUps = { hi = "Strict and strong. That back is coming along.", lo = "Half reps don't count. Full range." },
	Roadwork = { hi = "That's championship roadwork.", lo = "You jogged it. Push the pace." },
	Treadmill = { hi = "Every interval on the money.", lo = "Hit your zones - sprint means sprint." },
	Bike = { hi = "Big engine today. Great intervals.", lo = "Your cadence was all over the place." },
	Rower = { hi = "Powerful strokes. Great splits.", lo = "Hold your stroke rate steady." },
	Swimming = { hi = "Smooth lengths. Your lungs will thank you.", lo = "Steady strokes - you're fighting the water." },
	Ladder = { hi = "Fast feet! That's ring movement.", lo = "Heavy feet. Stay light and quick." },
	Rope = { hi = "The rope was singing today.", lo = "Too many trips. Find the rhythm." },
	IceBath = { hi = "Calm in the cold. That's discipline.", lo = "Control your breathing in there." },
	Stretch = { hi = "Loose and limber. Perfect.", lo = "Breathe into the stretch, don't fight it." },
	Massage = { hi = "Fully relaxed. Great recovery.", lo = "Let go - you're still holding tension." },
	Chamber = { hi = "Maximum recovery. Fresh legs tomorrow.", lo = "Breathe with the machine." },
	Sauna = { hi = "Controlled cut. Smart work.", lo = "Easy on the breathing - stay calm in the heat." },
}

-- strength stations: exercise name, believable load range and the muscle group that sets it
Config.LiftLoads = {
	Bench = { name = "BENCH PRESS", min = 95, max = 315, muscle = "chest" },
	Dumbbells = { name = "DUMBBELL CURLS", min = 20, max = 80, muscle = "arms", each = true },
	Barbell = { name = "DEADLIFT", min = 135, max = 495, muscle = "back" },
	Squat = { name = "BACK SQUAT", min = 115, max = 405, muscle = "legs" },
	PullUps = { name = "PULL-UPS", min = 0, max = 45, muscle = "back", bodyweight = true },
}

-- agility ladder drills (F = up, B = down, L = left, R = right); lv = ladder level needed
Config.LadderDrills = {
	{ name = "QUICK FEET", lv = 1, steps = { "F", "F", "F", "F", "F", "F" } },
	{ name = "LATERAL SHUFFLE", lv = 1, steps = { "R", "R", "R", "L", "L", "L" } },
	{ name = "IN-OUT", lv = 1, steps = { "F", "L", "R", "F", "L", "R", "F" } },
	{ name = "ZIG-ZAG", lv = 1, steps = { "L", "F", "R", "F", "L", "F", "R" } },
	{ name = "HOPSCOTCH", lv = 2, steps = { "F", "F", "L", "R", "F", "F", "L", "R" } },
	{ name = "ICKY SHUFFLE", lv = 2, steps = { "R", "F", "L", "L", "F", "R", "R", "F" } },
	{ name = "CROSSOVER", lv = 2, steps = { "R", "F", "R", "L", "F", "L", "R", "F" } },
	{ name = "SPRINT & BACKPEDAL", lv = 2, steps = { "F", "F", "F", "B", "B", "F", "F", "F" } },
	{ name = "CARIOCA", lv = 3, steps = { "R", "B", "R", "F", "R", "B", "R", "F", "R" } },
	{ name = "BOX DRILL", lv = 3, steps = { "F", "R", "B", "L", "F", "R", "B", "L", "F" } },
	{ name = "SNAKE", lv = 3, steps = { "L", "F", "R", "F", "L", "F", "R", "F", "L", "F" } },
}

-- shadow-boxing flow chains (F/B/L/R = steps, slipL/slipR/roll = head movement, jab/cross/leadhook = punches)
Config.ShadowFlows = {
	{ "jab", "B", "slipR", "cross" },
	{ "F", "jab", "cross", "L" },
	{ "slipL", "leadhook", "cross", "B" },
	{ "jab", "jab", "roll", "leadhook" },
	{ "roll", "cross", "leadhook", "B" },
	{ "F", "cross", "slipL", "leadhook" },
	{ "slipR", "slipL", "cross", "R" },
	{ "jab", "R", "cross", "leadhook" },
	{ "B", "jab", "F", "cross" },
	{ "jab", "cross", "roll", "cross" },
}

-- recovery session context
Config.StretchNames = { "HAMSTRINGS", "HIP FLEXORS", "SHOULDERS", "CALVES", "LOWER BACK", "QUADS", "CHEST", "NECK" }
Config.IceBathTempC = { 12, 8, 3 } -- plastic tub, ice bath, cryo tub
Config.SaunaTempC = { 0, 90, 60 } -- sauna suit (no room), wooden sauna, infrared sauna

------------------------------------------------------------------------
-- World & flavor
------------------------------------------------------------------------
Config.Nationalities = {
	"USA", "Mexico", "United Kingdom", "Ireland", "Philippines", "Japan", "Cuba", "Puerto Rico",
	"Ukraine", "Kazakhstan", "Russia", "Nigeria", "Ghana", "South Africa", "Brazil", "Argentina",
	"Canada", "Australia", "France", "Germany", "Italy", "Spain", "Dominican Republic", "Jamaica",
	"Haiti", "Venezuela", "Colombia", "Thailand", "South Korea", "China", "India", "Uzbekistan",
	"Cameroon", "Kenya", "New Zealand", "Poland", "Sweden", "Turkey", "Egypt", "Morocco",
}
Config.Genders = { "Male", "Female" }
Config.VoiceTypes = { "Deep", "Raspy", "Smooth", "Hype", "Calm" }

Config.FirstNames = {
	"Marcus", "Diego", "Tyson", "Andre", "Kenji", "Aleksandr", "Oleksandr", "Manny", "Carlos", "Liam",
	"Darnell", "Rafael", "Viktor", "Kwame", "Tunde", "Jamal", "Mateo", "Sean", "Connor", "Hiroshi",
	"Luis", "Jorge", "Emmanuel", "Isaac", "Dmitri", "Ivan", "Nikolai", "Jose", "Miguel", "Terrence",
	"Devon", "Malik", "Andrzej", "Erik", "Lars", "Paulo", "Thiago", "Ricardo", "Omar", "Youssef",
	"Samuel", "Joshua", "Daniel", "Anthony", "Callum", "Ryota", "Naoya", "Jin", "Wei", "Arjun",
	"Bektemir", "Daulet", "Juan", "Felix", "Kofi", "Chidi", "Tremaine", "Xavier", "Gideon", "Shamar",
	"Rolando", "Errol", "Tobias", "Vasil", "Simon", "Dante", "Elijah", "Rocco", "Angelo", "Mikhail",
}
Config.FirstNamesF = {
	"Clara", "Katie", "Amanda", "Alicia", "Selena", "Mikayla", "Natasha", "Savannah", "Lauren",
	"Ebony", "Chantelle", "Maria", "Yolanda", "Rania", "Shannon", "Terri", "Jessica", "Erika",
	"Naoko", "Hana", "Lucia", "Camila", "Adaeze", "Zara", "Imani", "Sofia", "Elena", "Olena",
}
Config.LastNames = {
	"Alvarez", "Johnson", "Okafor", "Tanaka", "Petrov", "Kovalenko", "Ramirez", "Murphy", "Walsh",
	"Garcia", "Mendoza", "Reyes", "Santos", "Silva", "Williams", "Brooks", "Carter", "Mensah",
	"Adeyemi", "Boateng", "Nakamura", "Inoue", "Kim", "Park", "Zhang", "Singh", "Ivanov", "Volkov",
	"Smirnov", "Novak", "Kowalski", "Fischer", "Muller", "Rossi", "Bianchi", "Lopez", "Hernandez",
	"Cruz", "Torres", "Diaz", "Morales", "Ortiz", "Castillo", "Vargas", "Romero", "Haddad", "Benali",
	"Abdullaev", "Zhakupov", "Usmonov", "OConnor", "Fitzgerald", "Hughes", "Thompson", "Davis",
	"Jackson", "Harris", "Stone", "Steele", "Knox", "Rivers", "King", "Price", "Grant", "Banks",
	"Duarte", "Pacheco", "Okonkwo", "Ndlovu", "Kariuki", "Lindqvist", "Yilmaz", "Mahmoud", "Sato",
}
Config.Nicknames = {
	"The Hammer", "Iron Fist", "El Toro", "The Assassin", "Lightning", "The Monster", "Bad Intentions",
	"The Professor", "Smoke", "The Machine", "Hit Squad", "Golden Boy", "The Ghost", "Thunder",
	"Dynamite", "The Butcher", "Showtime", "Cobra", "The Truth", "Gravedigger", "Red Dragon",
	"The Surgeon", "Nightmare", "Pretty Boy", "The Problem", "Venom", "Hurricane", "The Viking",
	"Kid Dynamo", "Babyface", "The Bull", "Silk", "Razor", "King Kong", "The Saint", "Warrior",
	"Rocket", "Mad Dog", "The Wolf", "Diamond",
}

Config.Personalities = {
	"Trash Talker", "Respectful Veteran", "Showman", "Silent Assassin", "Hothead", "Technician",
}
Config.TrashTalk = {
	["Trash Talker"] = {
		"%s is a paper champion. I'm about to fold them up and mail them home.",
		"I've seen better footwork at a bus stop. %s is in over their head.",
		"Tell %s to bring a stretcher to the arena. They'll need it.",
	},
	["Respectful Veteran"] = {
		"%s is a fine young fighter, but experience wins fights like this.",
		"I respect %s. That respect ends when the bell rings.",
	},
	["Showman"] = {
		"The cameras love me, and after fight night they'll love watching %s fall.",
		"It's showtime, baby. %s is just my opening act.",
	},
	["Silent Assassin"] = {
		"...I'll do my talking in the ring.",
		"Nothing to say about %s. Fight night says it all.",
	},
	["Hothead"] = {
		"I can't stand %s. I'm going to hurt them. Simple as that.",
		"Get %s out of my face before the weigh-in turns into a fight!",
	},
	["Technician"] = {
		"%s drops the right hand after the jab. I've watched the tape. It's over.",
		"I've studied %s for months. Every habit, every tell.",
	},
}
Config.RevengeTalk = {
	"Last time was a fluke. This time %s goes to sleep.",
	"I've thought about that loss every day. %s owes me.",
	"Rematch clause, revenge mission. %s knows what's coming.",
}
Config.TrilogyTalk = {
	"One win each. This trilogy decides who the better fighter really is, %s.",
	"Rubber match. History remembers the winner of this one, %s.",
}
-- the player's press-conference lines, by voice type (%s = opponent)
Config.VoiceLines = {
	Deep = { "I don't talk much. Fight night, %s finds out why.", "Heavy hands, heavy heart. %s is in trouble." },
	Raspy = { "I've been through wars, %s. You're just another one.", "Listen close, %s. I'm coming for everything." },
	Smooth = { "No disrespect, %s, but this is my era.", "Stay calm, look good, win clean. Sorry, %s." },
	Hype = { "LET'S GO! %s picked the WRONG fighter!", "I'm the future, baby! %s is the past!" },
	Calm = { "I've prepared well. %s is a good fighter. I'm better.", "We trained for everything %s can do." },
}
Config.AnnouncerIntro = {
	Deep = "In the red corner... a quiet storm...",
	Raspy = "In the red corner... battle-tested and hungry...",
	Smooth = "In the red corner... the smoothest operator in the sport...",
	Hype = "In the red corner... the most electric fighter alive...",
	Calm = "In the red corner... composed, clinical, dangerous...",
}

-- Fictional all-time greats for the GOAT ranking
Config.Legends = {
	{ name = "\"Thunder\" Jack Monroe", score = 1400 },
	{ name = "Ray \"Silk\" Delacroix", score = 1320 },
	{ name = "Ivan \"The Bear\" Koslov", score = 1250 },
	{ name = "Benny \"Golden Hands\" Ortega", score = 1180 },
	{ name = "Marvin \"The Marvel\" Hayes", score = 1110 },
	{ name = "Kazuo \"Typhoon\" Mori", score = 1040 },
	{ name = "Sugar Lou Whitfield", score = 980 },
	{ name = "Archie \"Old Mongoose\" Banks", score = 900 },
	{ name = "Roberto \"Iron Palms\" Villa", score = 860 },
	{ name = "Joe \"The Bomber\" Lyle", score = 820 },
	{ name = "Percy \"Smooth\" Grant", score = 740 },
	{ name = "Henry \"Hammerin\" Armstead", score = 690 },
	{ name = "Manuel \"El Relampago\" Quezon", score = 650 },
	{ name = "Cesar \"El Brujo\" Zamora", score = 580 },
	{ name = "Tommy \"Tornado\" Hearne", score = 520 },
	{ name = "Ricky \"The Rocket\" Hart", score = 430 },
	{ name = "Wilfred \"Cannon\" Gamez", score = 380 },
	{ name = "Danny \"Red Fox\" Lowes", score = 300 },
	{ name = "Gus \"The Brick\" Pemberton", score = 220 },
	{ name = "Eddie \"The Eagle\" Tran", score = 150 },
}
Config.HallOfFameScore = 450

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function Config.FindById(list, id)
	for _, item in ipairs(list) do
		if item.id == id or item.name == id then
			return item
		end
	end
	return nil
end

function Config.WeightClassIndex(name)
	for i, wc in ipairs(Config.WeightClasses) do
		if wc.name == name then
			return i
		end
	end
	return 5
end

function Config.HeightText(inches)
	inches = math.floor(inches + 0.5)
	return string.format("%d'%d\"", math.floor(inches / 12), inches % 12)
end

function Config.Money(n)
	n = math.floor(n or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (n < 0 and "-$" or "$") .. out
end

-- grade letter (S/A/B/C/D) for a session quality
function Config.GradeFor(quality)
	local q = tonumber(quality) or 0
	for _, g in ipairs(Config.Grades) do
		if q >= g.min then
			return g.id
		end
	end
	return "D"
end

function Config.GradeInfo(id)
	for _, g in ipairs(Config.Grades) do
		if g.id == id then
			return g
		end
	end
	return Config.Grades[#Config.Grades]
end

-- session quality as the percentage the player sees (a perfect drill = 100%)
function Config.QualityPct(quality)
	local q = tonumber(quality) or 0
	if q ~= q then
		q = 0
	end
	return math.clamp(math.floor(q * 100 / 1.45 + 0.5), 0, 100)
end

function Config.Overall(stats)
	local total = 0
	for _, k in ipairs(Config.StatKeys) do
		total += stats[k] or 0
	end
	return math.floor(total / #Config.StatKeys + 0.5)
end

return Config
