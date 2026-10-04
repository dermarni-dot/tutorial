-- Catalog: gym equipment levels, gear (gloves, shoes, wraps, mouthguards, robes),
-- glove customization options, coaches and other purchasables.
local Catalog = {}

------------------------------------------------------------------------
-- Gym equipment. Each station has quality levels; higher = better gains and visuals.
-- requiresTier = career tier needed (8 = World Champion) for elite equipment.
------------------------------------------------------------------------
Catalog.Stations = {
	heavybag = { name = "Heavy Bag", area = "Boxing Area", levels = {
		{ name = "Old Worn Canvas Bag", cost = 0, mult = 0.85, desc = "Torn canvas, slow progress" },
		{ name = "Basic Gym Heavy Bag", cost = 1500, mult = 1.0, desc = "Better durability, slight boost" },
		{ name = "Professional Leather Bag", cost = 12000, mult = 1.15, desc = "Real striking feedback, faster progress" },
		{ name = "Elite Training Bag", cost = 60000, mult = 1.3, desc = "Improved power gains, advanced drills" },
		{ name = "Championship Smart Bag", cost = 300000, mult = 1.5, desc = "Motion sensors, impact tracking, max gains" },
		{ name = "Champion Training Bag", cost = 900000, mult = 1.7, requiresTier = 8, elite = true, desc = "Elite: gold-trimmed, champion drills" },
	} },
	speedbag = { name = "Speed Bag", area = "Boxing Area", levels = {
		{ name = "Basic Speed Bag", cost = 0, mult = 0.9, desc = "Slow rebound" },
		{ name = "Pro Speed Bag", cost = 8000, mult = 1.15, desc = "Better leather, faster rebounds" },
		{ name = "Championship Speed Bag", cost = 90000, mult = 1.35, desc = "Lightning rebound, crisp sound" },
		{ name = "Olympic Speed Bag", cost = 450000, mult = 1.55, requiresTier = 8, elite = true, desc = "Elite: Olympic-grade platform" },
	} },
	doubleend = { name = "Double-End Bag", area = "Boxing Area", levels = {
		{ name = "Basic Double-End Bag", cost = 0, mult = 0.9, desc = "Slow, predictable" },
		{ name = "Fast Double-End Bag", cost = 6000, mult = 1.1, desc = "Quicker movement" },
		{ name = "Pro Reflex Bag", cost = 45000, mult = 1.3, desc = "Fast and erratic" },
		{ name = "Lightning Reflex Bag", cost = 250000, mult = 1.5, desc = "Elite reaction training" },
	} },
	mitts = { name = "Mitt Work", area = "Boxing Area", levels = {
		{ name = "Volunteer Coach", cost = 0, mult = 0.9, desc = "Basic combinations" },
		{ name = "Local Trainer", cost = 5000, mult = 1.05, desc = "More combinations" },
		{ name = "Pro Trainer", cost = 30000, mult = 1.2, desc = "Defensive moves in combos" },
		{ name = "Elite Trainer", cost = 150000, mult = 1.35, desc = "Advanced combos, faster calls" },
		{ name = "Hall of Fame Trainer", cost = 600000, mult = 1.5, desc = "Championship combinations" },
	} },
	mirror = { name = "Shadow Boxing Mirror", area = "Boxing Area", levels = {
		{ name = "Cracked Mirror", cost = 0, mult = 0.95, desc = "Gets the job done" },
		{ name = "Studio Mirror Wall", cost = 2000, mult = 1.1, desc = "Full-length mirrors" },
		{ name = "Smart Mirror", cost = 50000, mult = 1.3, desc = "Form feedback on every move" },
	} },
	ring = { name = "Sparring Ring", area = "Boxing Area", levels = {
		{ name = "Worn Gym Ring", cost = 0, mult = 0.9, desc = "Saggy ropes, patched canvas" },
		{ name = "Club Ring", cost = 10000, mult = 1.1, desc = "Proper ropes and canvas" },
		{ name = "Professional Ring", cost = 150000, mult = 1.35, requiresTier = 8, elite = true, desc = "Elite: championship-spec ring" },
	} },
	bench = { name = "Weight Bench", area = "Weight Room", levels = {
		{ name = "Rusty Bench", cost = 0, mult = 0.9, desc = "Wobbly but works" },
		{ name = "Standard Bench", cost = 2500, mult = 1.05, desc = "Solid and safe" },
		{ name = "Olympic Bench", cost = 20000, mult = 1.2, desc = "Olympic bar and plates" },
		{ name = "Elite Power Station", cost = 100000, mult = 1.4, desc = "Pro strength setup" },
	} },
	dumbbells = { name = "Dumbbells", area = "Weight Room", levels = {
		{ name = "Mismatched Dumbbells", cost = 0, mult = 0.9, desc = "Odd sizes" },
		{ name = "Rubber Hex Set", cost = 2000, mult = 1.05, desc = "Full rack" },
		{ name = "Chrome Pro Set", cost = 15000, mult = 1.2, desc = "Gleaming pro set" },
		{ name = "Elite Adjustable Set", cost = 80000, mult = 1.4, desc = "Precision loading" },
	} },
	barbell = { name = "Barbell Platform", area = "Weight Room", levels = {
		{ name = "Bent Bar", cost = 0, mult = 0.9, desc = "Seen better days" },
		{ name = "Standard Barbell", cost = 3000, mult = 1.05, desc = "Straight bar, iron plates" },
		{ name = "Olympic Barbell", cost = 20000, mult = 1.2, desc = "Bumper plates" },
		{ name = "Elite Lifting Platform", cost = 90000, mult = 1.4, desc = "Pro platform" },
	} },
	squat = { name = "Squat Rack", area = "Weight Room", levels = {
		{ name = "Basic Squat Stands", cost = 0, mult = 0.9, desc = "Just stands" },
		{ name = "Squat Rack", cost = 4000, mult = 1.05, desc = "Safety pins" },
		{ name = "Power Rack", cost = 25000, mult = 1.2, desc = "Full cage" },
		{ name = "Elite Rack", cost = 110000, mult = 1.4, desc = "Competition rack" },
	} },
	pullup = { name = "Pull-Up Station", area = "Weight Room", levels = {
		{ name = "Doorframe Bar", cost = 0, mult = 0.9, desc = "Basic bar" },
		{ name = "Wall Station", cost = 1500, mult = 1.05, desc = "Wall-mounted" },
		{ name = "Power Tower", cost = 12000, mult = 1.2, desc = "Dip and pull-up tower" },
		{ name = "Elite Rig", cost = 70000, mult = 1.4, desc = "Multi-grip rig" },
	} },
	treadmill = { name = "Treadmill", area = "Cardio Room", levels = {
		{ name = "Old Treadmill", cost = 0, mult = 0.9, desc = "Squeaky belt" },
		{ name = "Gym Treadmill", cost = 5000, mult = 1.05, desc = "Smooth running" },
		{ name = "Pro Treadmill", cost = 30000, mult = 1.2, desc = "Incline programs" },
		{ name = "Smart Treadmill", cost = 120000, mult = 1.4, desc = "Live pace coaching" },
	} },
	bike = { name = "Bike", area = "Cardio Room", levels = {
		{ name = "Squeaky Bike", cost = 0, mult = 0.9, desc = "It squeaks" },
		{ name = "Spin Bike", cost = 4000, mult = 1.05, desc = "Weighted flywheel" },
		{ name = "Air Bike", cost = 25000, mult = 1.25, desc = "Brutal conditioning" },
	} },
	rower = { name = "Row Machine", area = "Cardio Room", levels = {
		{ name = "Old Rower", cost = 0, mult = 0.9, desc = "Sticky seat" },
		{ name = "Air Rower", cost = 6000, mult = 1.1, desc = "Fan resistance" },
		{ name = "Water Rower", cost = 35000, mult = 1.3, desc = "Smooth water drag" },
	} },
	rope = { name = "Jump Rope", area = "Cardio Room", levels = {
		{ name = "Basic Rope", cost = 0, mult = 0.9, desc = "Plastic rope" },
		{ name = "Speed Rope", cost = 800, mult = 1.05, desc = "Faster spins" },
		{ name = "Weighted Rope", cost = 6000, mult = 1.2, desc = "Unlocks double unders" },
		{ name = "Pro Beaded Rope", cost = 30000, mult = 1.35, desc = "Advanced footwork drills" },
	} },
	ladder = { name = "Agility Ladder", area = "Cardio Room", levels = {
		{ name = "Chalk Lines", cost = 0, mult = 0.9, desc = "Drawn on the floor" },
		{ name = "Agility Ladder", cost = 1000, mult = 1.05, desc = "Proper ladder" },
		{ name = "Pro Ladder & Cones", cost = 8000, mult = 1.2, desc = "Complex patterns" },
		{ name = "Smart Reaction Lights", cost = 60000, mult = 1.4, desc = "Light-cued footwork" },
	} },
	track = { name = "Roadwork Route", area = "Outdoors", levels = {
		{ name = "Neighborhood Loop", cost = 0, mult = 1.0, desc = "Around the gym" },
	} },
	pool = { name = "Swimming Pool", area = "Pool", levels = {
		{ name = "Community Pool", cost = 0, mult = 1.0, desc = "Shared lanes" },
		{ name = "Lap Pool", cost = 15000, mult = 1.15, desc = "Dedicated lap lanes" },
		{ name = "Olympic Pool", cost = 90000, mult = 1.3, desc = "Olympic-length pool" },
	} },
	icebath = { name = "Ice Bath", area = "Recovery Area", levels = {
		{ name = "Plastic Tub", cost = 0, mult = 0.9, desc = "Bag of ice" },
		{ name = "Ice Bath", cost = 3000, mult = 1.1, desc = "Proper cold plunge" },
		{ name = "Cryo Tub", cost = 40000, mult = 1.3, desc = "Controlled cryotherapy" },
	} },
	stretch = { name = "Stretching Area", area = "Recovery Area", levels = {
		{ name = "Floor Mat", cost = 0, mult = 1.0, desc = "Thin mat" },
		{ name = "Yoga Studio", cost = 2500, mult = 1.15, desc = "Mats, bands and rollers" },
	} },
	massage = { name = "Massage Table", area = "Recovery Area", levels = {
		{ name = "Folding Table", cost = 0, mult = 0.9, desc = "$100 per session" },
		{ name = "Massage Therapist", cost = 20000, mult = 1.2, free = true, desc = "Free sessions" },
	} },
	sauna = { name = "Sauna", area = "Recovery Area", levels = {
		{ name = "Sauna Suit", cost = 0, mult = 0.8, desc = "Sweaty plastic suit" },
		{ name = "Wooden Sauna", cost = 10000, mult = 1.0, desc = "Proper weight cuts" },
		{ name = "Infrared Sauna", cost = 50000, mult = 1.2, desc = "Efficient, safer cuts" },
	} },
	chamber = { name = "Elite Recovery Chamber", area = "Recovery Area", levels = {
		{ name = "Elite Recovery Chamber", cost = 0, mult = 1.0, desc = "Buy it in the Shop (Elite)" },
	} },
}

-- display order for the Gym tab
Catalog.StationOrder = {
	"heavybag", "speedbag", "doubleend", "mitts", "mirror", "ring",
	"bench", "dumbbells", "barbell", "squat", "pullup",
	"treadmill", "bike", "rower", "rope", "ladder", "pool",
	"icebath", "stretch", "massage", "sauna",
}

function Catalog.RepairCost(stationId, level)
	local st = Catalog.Stations[stationId]
	local lv = st and st.levels[level]
	return math.floor(60 + (lv and lv.cost or 0) * 0.04)
end

------------------------------------------------------------------------
-- Gear
------------------------------------------------------------------------
-- custom = which customizations the glove allows
Catalog.Gloves = {
	{ id = "Worn", name = "Worn Gloves", tier = "Beginner", price = 0, power = -0.03, speed = 0, durability = 0.6, startCondition = 55,
		custom = { color = true } },
	{ id = "Cheap", name = "Cheap Gloves", tier = "Beginner", price = 200, power = 0, speed = 0, durability = 0.8,
		custom = { color = true } },
	{ id = "Competition", name = "Competition Gloves", tier = "Intermediate", price = 3000, power = 0.02, speed = 0.03, durability = 1.0,
		custom = { color = true, trim = true, stitching = true } },
	{ id = "Professional", name = "Professional Gloves", tier = "Intermediate", price = 15000, power = 0.04, speed = 0.04, durability = 1.2,
		custom = { color = true, trim = true, stitching = true, finish = true, logo = true } },
	{ id = "Championship", name = "Championship Gloves", tier = "Elite", price = 90000, power = 0.06, speed = 0.05, durability = 1.5,
		custom = { color = true, trim = true, stitching = true, finish = true, logo = true, embroidery = true } },
	{ id = "Custom", name = "Custom Gloves", tier = "Elite", price = 250000, power = 0.07, speed = 0.06, durability = 1.6,
		custom = { color = true, trim = true, stitching = true, finish = true, metallic = true, logo = true, embroidery = true } },
	{ id = "WorldChampion", name = "World Champion Gloves", tier = "Legendary", price = 1000000, requiresTier = 8, power = 0.09, speed = 0.08, durability = 2.0, aura = true,
		custom = { color = true, trim = true, stitching = true, finish = true, metallic = true, logo = true, embroidery = true } },
}
Catalog.GloveFinishes = { "Leather", "Matte", "Patent", "Metallic" }
Catalog.GloveLogos = { "None", "Star", "Crown", "Lightning", "Flame", "Skull", "Initials", "Flag" }
Catalog.LogoGlyphs = { Star = "★", Crown = "♛", Lightning = "⚡", Flame = "🔥", Skull = "☠" }
Catalog.GloveStitching = { "Classic", "Double", "Contrast", "Gold" }

Catalog.Shoes = {
	{ id = "Sneakers", name = "Worn Sneakers", price = 0, footwork = -0.02, durability = 0.6, startCondition = 60 },
	{ id = "Boots", name = "Boxing Boots", price = 800, footwork = 0, durability = 1.0 },
	{ id = "ProBoots", name = "Pro Boots", price = 6000, footwork = 0.03, durability = 1.3 },
	{ id = "EliteBoots", name = "Elite Boots", price = 40000, footwork = 0.05, durability = 1.6 },
}
Catalog.Wraps = {
	{ id = "OldWraps", name = "Old Wraps", price = 0, injury = 1.15, durability = 0.6, startCondition = 50 },
	{ id = "Cotton", name = "Cotton Wraps", price = 50, injury = 1.0, durability = 1.0 },
	{ id = "Gel", name = "Gel Wraps", price = 600, injury = 0.7, durability = 1.4 },
}
Catalog.Mouthguards = {
	{ id = "BoilBite", name = "Boil-and-Bite Guard", price = 0, chin = 0 },
	{ id = "CustomFit", name = "Custom-Fit Guard", price = 1500, chin = 2 },
}
Catalog.Robes = {
	{ id = "None", name = "No Robe", price = 0, pop = 0 },
	{ id = "Classic", name = "Classic Robe", price = 500, pop = 1 },
	{ id = "Hooded", name = "Hooded Robe", price = 2000, pop = 2 },
	{ id = "Champion", name = "Champion Robe", price = 50000, pop = 5, requiresTier = 8 },
}
Catalog.TrunkStyles = { "Classic", "Long", "Striped", "Pro" }
Catalog.ShoeStyles = { "Low-Top", "High-Top" }

function Catalog.Find(list, id)
	for _, item in ipairs(list) do
		if item.id == id then
			return item
		end
	end
	return nil
end

function Catalog.GearList(kind)
	if kind == "gloves" then
		return Catalog.Gloves
	elseif kind == "shoes" then
		return Catalog.Shoes
	elseif kind == "wraps" then
		return Catalog.Wraps
	elseif kind == "mouthguard" then
		return Catalog.Mouthguards
	elseif kind == "robe" then
		return Catalog.Robes
	end
	return nil
end

function Catalog.RepairGearCost(kind, item)
	local price = item and item.price or 0
	return math.floor(25 + price * (kind == "gloves" and 0.06 or 0.08))
end

------------------------------------------------------------------------
-- Coaches: one per specialty, three tiers. Salary is paid each fight.
------------------------------------------------------------------------
Catalog.CoachSpecialties = {
	{ id = "Power", stats = { "Power", "Chin" } },
	{ id = "Speed", stats = { "PunchSpeed", "Reflexes" } },
	{ id = "Defense", stats = { "Blocking", "HeadMovement" } },
	{ id = "Footwork", stats = { "Footwork" } },
	{ id = "Conditioning", stats = { "Stamina", "Endurance", "Recovery" } },
	{ id = "RingIQ", name = "Ring IQ", stats = { "RingIQ", "Countering" } },
}
Catalog.CoachTiers = {
	{ name = "Local", boost = 0.15, cost = 3000, salary = 300 },
	{ name = "Pro", boost = 0.3, cost = 25000, salary = 2500 },
	{ name = "Elite", boost = 0.5, cost = 200000, salary = 15000 },
}
Catalog.CoachNames = {
	Power = { "Big Sal Moretti", "Hank \"Anvil\" Brody", "Viktor Steinholt" },
	Speed = { "Quick Tommy Lin", "Darius \"Flash\" Webb", "Hiro Takamatsu" },
	Defense = { "Old Man Ezra", "Felipe \"The Wall\" Ruiz", "Marcus Bellamy" },
	Footwork = { "Coach Dee Harper", "Luis \"Dancer\" Ortega", "Sasha Volkova" },
	Conditioning = { "Big Mike Tolliver", "Ingrid Larsen", "Dr. Ray Okafor" },
	RingIQ = { "Professor Gil Fontaine", "Cyrus \"Chess\" Abara", "Emmanuel Steele-Ward" },
}

------------------------------------------------------------------------
-- Other purchases (Shop tab)
------------------------------------------------------------------------
Catalog.Shop = {
	{ id = "Nutritionist", cat = "Nutrition", name = "Nutritionist", price = 20000, desc = "+25% from meals, unlocks Personal Chef Feast, -15% training fatigue" },
	{ id = "Physio", cat = "Recovery", name = "Physiotherapist", price = 35000, desc = "Injuries heal 50% faster" },
	{ id = "MountainCamp", cat = "Training Camps", name = "Mountain Training Camp", price = 40000, desc = "+1 camp day, +10% stamina gains" },
	{ id = "EliteCamp", cat = "Training Camps", name = "Elite Training Camp", price = 400000, desc = "+2 camp days, +10% all gains" },
	{ id = "SmartSystem", cat = "Elite Equipment", name = "Smart Training System", price = 750000, requiresTier = 8, desc = "Elite: +10% all gains, live analytics in drills" },
	{ id = "RecoveryChamber", cat = "Elite Equipment", name = "Elite Recovery Chamber", price = 1200000, requiresTier = 8, desc = "Elite: unlocks the recovery chamber" },
	{ id = "Apartment", cat = "Houses", name = "City Apartment", price = 50000, desc = "Better sleep (+10%), +5 Confidence, +3 Popularity", sleep = 0.1, conf = 5, pop = 3 },
	{ id = "House", cat = "Houses", name = "Suburban House", price = 400000, desc = "Better sleep (+20%), +10 Confidence, +6 Popularity", sleep = 0.2, conf = 10, pop = 6 },
	{ id = "Mansion", cat = "Houses", name = "Mansion", price = 5000000, desc = "Best sleep (+30%), +15 Confidence, +15 Popularity", sleep = 0.3, conf = 15, pop = 15 },
	{ id = "SportsCar", cat = "Cars", name = "Sports Car", price = 120000, desc = "+5 Popularity", pop = 5 },
	{ id = "Supercar", cat = "Cars", name = "Supercar", price = 1500000, desc = "+12 Popularity", pop = 12 },
	{ id = "Hypercar", cat = "Cars", name = "Hypercar", price = 6000000, desc = "+20 Popularity", pop = 20 },
}

return Catalog
