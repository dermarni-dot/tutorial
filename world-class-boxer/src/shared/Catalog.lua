-- Catalog: gym equipment levels, gear (gloves, shoes, wraps, mouthguards, robes),
-- glove customization options, gear brands, sponsors, coaches, other purchasables
-- and the gym facility tier.
local Config = require(script.Parent:WaitForChild("Config"))

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
	medball = { name = "Medicine Ball", area = "Weight Room", levels = {
		{ name = "Cracked Leather Ball", cost = 0, mult = 0.9, desc = "Old ball, bare floor" },
		{ name = "Rubber Ball Set", cost = 2500, mult = 1.05, desc = "Three weights and a rack" },
		{ name = "Slam Ball & Wall Target", cost = 18000, mult = 1.2, desc = "Slam pad and wall-ball target" },
		{ name = "Elite Core Station", cost = 85000, mult = 1.4, desc = "Rep-counting core station" },
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
	"bench", "dumbbells", "barbell", "squat", "pullup", "medball",
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
	{ id = "Worn", name = "Worn Gloves", tier = "Beginner", brand = "GymIssue", oz = 16, price = 0, power = -0.03, speed = 0, durability = 0.6, startCondition = 55,
		custom = { color = true } },
	{ id = "Cheap", name = "Cheap Gloves", tier = "Beginner", brand = "Strikewell", oz = 14, price = 200, power = 0, speed = 0, durability = 0.8,
		custom = { color = true } },
	{ id = "Competition", name = "Competition Gloves", tier = "Intermediate", brand = "Ringcraft", oz = 10, price = 3000, power = 0.02, speed = 0.03, durability = 1.0,
		custom = { color = true, trim = true, stitching = true } },
	{ id = "Professional", name = "Professional Gloves", tier = "Intermediate", brand = "Ironvale", oz = 10, price = 15000, power = 0.04, speed = 0.04, durability = 1.2,
		custom = { color = true, trim = true, stitching = true, finish = true, logo = true } },
	{ id = "Championship", name = "Championship Gloves", tier = "Elite", brand = "Kazari", oz = 8, price = 90000, power = 0.06, speed = 0.05, durability = 1.5,
		custom = { color = true, trim = true, stitching = true, finish = true, logo = true, embroidery = true } },
	{ id = "Custom", name = "Custom Gloves", tier = "Elite", brand = "AtelierNine", oz = 8, price = 250000, power = 0.07, speed = 0.06, durability = 1.6,
		custom = { color = true, trim = true, stitching = true, finish = true, metallic = true, logo = true, embroidery = true, brand = true } },
	{ id = "WorldChampion", name = "World Champion Gloves", tier = "Legendary", brand = "Laurel", oz = 8, price = 1000000, requiresTier = 8, power = 0.09, speed = 0.08, durability = 2.0, aura = true,
		custom = { color = true, trim = true, stitching = true, finish = true, metallic = true, logo = true, embroidery = true, brand = true } },
}
Catalog.GloveFinishes = { "Leather", "Matte", "Patent", "Metallic" }
Catalog.GloveLogos = { "None", "Star", "Crown", "Lightning", "Flame", "Skull", "Initials", "Flag" }
Catalog.LogoGlyphs = { Star = "★", Crown = "♛", Lightning = "⚡", Flame = "🔥", Skull = "☠" }
Catalog.GloveStitching = { "Classic", "Double", "Contrast", "Gold" }

-- style = shoe build (trainer | boot | proBoot | eliteBoot); sole overrides the brand's sole type
Catalog.Shoes = {
	{ id = "Sneakers", name = "Worn Sneakers", price = 0, footwork = -0.02, durability = 0.6, startCondition = 60, brand = "Strikewell", style = "trainer", sole = "Foam" },
	{ id = "Boots", name = "Boxing Boots", price = 800, footwork = 0, durability = 1.0, brand = "Ringcraft", style = "boot", sole = "Rubber" },
	{ id = "ProBoots", name = "Pro Boots", price = 6000, footwork = 0.03, durability = 1.3, brand = "Ironvale", style = "proBoot", sole = "Suede" },
	{ id = "EliteBoots", name = "Elite Boots", price = 40000, footwork = 0.05, durability = 1.6, brand = "Kazari", style = "eliteBoot", sole = "Split" },
}
-- style = wrap build (cotton | gel); frayed = loose dangling ends
Catalog.Wraps = {
	{ id = "OldWraps", name = "Old Wraps", price = 0, injury = 1.15, durability = 0.6, startCondition = 50, brand = "GymIssue", style = "cotton", frayed = true },
	{ id = "Cotton", name = "Cotton Wraps", price = 50, injury = 1.0, durability = 1.0, brand = "Ringcraft", style = "cotton" },
	{ id = "Gel", name = "Gel Wraps", price = 600, injury = 0.7, durability = 1.4, brand = "Ironvale", style = "gel" },
}
Catalog.Mouthguards = {
	{ id = "BoilBite", name = "Boil-and-Bite Guard", price = 0, chin = 0, brand = "GymIssue" },
	{ id = "CustomFit", name = "Custom-Fit Guard", price = 1500, chin = 2, brand = "AtelierNine" },
}
Catalog.Robes = {
	{ id = "None", name = "No Robe", price = 0, pop = 0 },
	{ id = "Classic", name = "Classic Robe", price = 500, pop = 1 },
	{ id = "Hooded", name = "Hooded Robe", price = 2000, pop = 2 },
	{ id = "Champion", name = "Champion Robe", price = 50000, pop = 5, requiresTier = 8 },
}
Catalog.TrunkStyles = { "Classic", "Long", "Striped", "Pro" }
Catalog.ShoeStyles = { "Low-Top", "High-Top" }

------------------------------------------------------------------------
-- Gear brands (all fictional). Each brand has a visual signature the Builder draws:
--   wordmark/font (built-in Enum.Font NAME; resolve with pcall) / wordColor, glyph = short
--   monogram printed on the glove back, cuff and boot heel (plain text, no emoji),
--   palette = default colours { primary, secondary, accent } as {r,g,b},
--   stitch = Single | Double | Contrast | Hidden | Gold, closure = velcro | lace,
--   cuff = Short | Velcro | Lace | LongLace | Strap, sole = Foam | Rubber | Gum | Suede | Split,
--   finish = default glove material (Leather | Matte | Patent | Metallic),
--   shape = glove proportions { len, width, cuff, knuckle } (multipliers),
--   piping = glove seam piping colour ("trim" = use the glove trim colour), palm = palm panel tone.
------------------------------------------------------------------------
Catalog.Brands = {
	GymIssue = { id = "GymIssue", name = "Gym Issue", wordmark = "", font = "GothamBold", wordColor = { 230, 230, 230 }, glyph = "",
		palette = { primary = { 150, 30, 30 }, secondary = { 60, 60, 60 }, accent = { 220, 220, 215 } },
		stitch = "Single", closure = "velcro", cuff = "Velcro", sole = "Foam", finish = "Matte",
		shape = { len = 1.05, width = 1.05, cuff = 0.9, knuckle = 1.0 }, piping = "none", palm = 0.9,
		tier = "Beginner", desc = "Unbranded loaner kit from the gym box" },
	Strikewell = { id = "Strikewell", name = "Strikewell", wordmark = "STRIKEWELL", font = "GothamBlack", wordColor = { 255, 255, 255 }, glyph = "SW",
		palette = { primary = { 20, 60, 190 }, secondary = { 245, 245, 245 }, accent = { 255, 200, 40 } },
		stitch = "Single", closure = "velcro", cuff = "Velcro", sole = "Foam", finish = "Matte",
		shape = { len = 1.0, width = 1.05, cuff = 0.95, knuckle = 1.0 }, piping = "trim", palm = 0.85,
		tier = "Beginner", desc = "Moulded vinyl budget gear with a big velcro strap" },
	Ringcraft = { id = "Ringcraft", name = "Ringcraft", wordmark = "RINGCRAFT", font = "Oswald", wordColor = { 255, 255, 255 }, glyph = "RC",
		palette = { primary = { 200, 25, 30 }, secondary = { 25, 60, 200 }, accent = { 245, 245, 245 } },
		stitch = "Double", closure = "velcro", cuff = "Strap", sole = "Rubber", finish = "Leather", targetArea = true,
		shape = { len = 1.0, width = 1.0, cuff = 1.0, knuckle = 1.05 }, piping = "trim", palm = 0.9,
		tier = "Intermediate", desc = "Amateur competition standard: white target knuckle, wide strap" },
	Ironvale = { id = "Ironvale", name = "Ironvale", wordmark = "IRONVALE", font = "Michroma", wordColor = { 210, 210, 215 }, glyph = "IV",
		palette = { primary = { 20, 20, 20 }, secondary = { 120, 120, 130 }, accent = { 200, 25, 30 } },
		stitch = "Contrast", closure = "lace", cuff = "Lace", sole = "Suede", finish = "Leather",
		shape = { len = 0.96, width = 0.98, cuff = 1.1, knuckle = 1.1 }, piping = { 200, 200, 205 }, palm = 0.88,
		tier = "Intermediate", desc = "Pro lace-up leather with a compact puncher's shape" },
	Kazari = { id = "Kazari", name = "Kazari", wordmark = "KAZARI", font = "Bangers", wordColor = { 255, 215, 90 }, glyph = "KZ",
		palette = { primary = { 120, 20, 30 }, secondary = { 20, 20, 20 }, accent = { 230, 180, 30 } },
		stitch = "Hidden", closure = "lace", cuff = "LongLace", sole = "Gum", finish = "Patent",
		shape = { len = 0.95, width = 0.95, cuff = 1.25, knuckle = 1.15 }, piping = { 230, 180, 30 }, palm = 0.92,
		tier = "Elite", desc = "Hand-made fight gloves: long laced cuff, embossed side wordmark" },
	AtelierNine = { id = "AtelierNine", name = "Atelier Nine", wordmark = "ATELIER 9", font = "Antique", wordColor = { 245, 240, 225 }, glyph = "A9",
		palette = { primary = { 245, 240, 230 }, secondary = { 30, 30, 30 }, accent = { 190, 150, 70 } },
		stitch = "Gold", closure = "lace", cuff = "LongLace", sole = "Split", finish = "Leather",
		shape = { len = 0.97, width = 0.96, cuff = 1.2, knuckle = 1.1 }, piping = "trim", palm = 0.9, plate = true,
		tier = "Elite", desc = "Bespoke workshop: custom name plate on the cuff" },
	Laurel = { id = "Laurel", name = "Laurel Legacy", wordmark = "LAUREL", font = "Garamond", wordColor = { 255, 215, 90 }, glyph = "LL",
		palette = { primary = { 230, 180, 30 }, secondary = { 20, 20, 20 }, accent = { 255, 255, 255 } },
		stitch = "Gold", closure = "lace", cuff = "LongLace", sole = "Split", finish = "Metallic",
		shape = { len = 0.95, width = 0.95, cuff = 1.25, knuckle = 1.15 }, piping = { 255, 215, 90 }, palm = 0.95, plate = true, beltPlate = true,
		tier = "Legendary", desc = "Champions only: gold piping and a belt-style side plate" },
}
Catalog.BrandOrder = { "GymIssue", "Strikewell", "Ringcraft", "Ironvale", "Kazari", "AtelierNine", "Laurel" }

function Catalog.Brand(id)
	return Catalog.Brands[id] or Catalog.Brands.GymIssue
end

-- brand for a gear item. kind = "gloves"|"shoes"|"wraps"|"mouthguard"; override = app.gloves.brand
-- (honoured only for gloves whose custom.brand is set, and only when it names a real brand)
function Catalog.GearBrand(kind, itemId, override)
	local list = Catalog.GearList and Catalog.GearList(kind)
	local item = list and Catalog.Find(list, itemId)
	if kind == "gloves" and item and item.custom and item.custom.brand and type(override) == "string" and Catalog.Brands[override] then
		return Catalog.Brands[override]
	end
	return Catalog.Brand(item and item.brand)
end

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
	-- home add-ons: requiresAny = must own one of these first (checked by Career.Buy, shown by the Hub).
	-- Training applies HomeGym.gains to stat gains AND muscle growth, RecoverySuite.sleepBonus in SleepQuality.
	{ id = "Garage", cat = "Home Upgrades", name = "Garage", price = 60000, requiresAny = { "Apartment", "House", "Mansion" }, desc = "Shows your cars at home" },
	{ id = "HomeGym", cat = "Home Upgrades", name = "Home Gym", price = 80000, requiresAny = { "Apartment", "House", "Mansion" }, desc = "+3% training gains", gains = 0.03 },
	{ id = "TrophyRoom", cat = "Home Upgrades", name = "Trophy Room", price = 150000, requiresAny = { "House", "Mansion" }, desc = "+2 Confidence, +3 Popularity", conf = 2, pop = 3 },
	{ id = "RecoverySuite", cat = "Home Upgrades", name = "Home Recovery Suite", price = 250000, requiresAny = { "House", "Mansion" }, desc = "Better sleep (+5%)", sleepBonus = 0.05 },
	{ id = "PoolDeck", cat = "Home Upgrades", name = "Pool Deck", price = 400000, requiresAny = { "House", "Mansion" }, desc = "+4 Popularity, a pool at home", pop = 4 },
	{ id = "SportsCar", cat = "Cars", name = "Sports Car", price = 120000, desc = "+5 Popularity", pop = 5 },
	{ id = "Supercar", cat = "Cars", name = "Supercar", price = 1500000, desc = "+12 Popularity", pop = 12 },
	{ id = "Hypercar", cat = "Cars", name = "Hypercar", price = 6000000, desc = "+20 Popularity", pop = 20 },
}

------------------------------------------------------------------------
-- Sponsors (all fictional). One active deal per slot (trunks | robe | corner | gear).
-- perFight is paid every fight while the deal runs, winBonus / koBonus on top; fights = contract length.
-- logo = { bg, fg = {r,g,b}, text, glyph } drawn on trunks / robe / corner pads / billboards;
-- shop = the CityMap shop front that belongs to the brand (local sponsors).
------------------------------------------------------------------------
Catalog.Sponsors = {
	{ id = "TonysPizza", name = "Tony's Pizza", scope = "Local", minTier = 2, minPop = 3, perFight = 600, winBonus = 300, koBonus = 300, fights = 4, slot = "trunks",
		logo = { bg = { 200, 30, 30 }, fg = { 255, 240, 200 }, text = "TONY'S", glyph = "PIZZA" }, shop = "TONY'S PIZZA" },
	{ id = "IronSupplements", name = "Iron Supplements", scope = "Local", minTier = 2, minPop = 5, perFight = 900, winBonus = 400, koBonus = 400, fights = 4, slot = "robe",
		logo = { bg = { 30, 30, 30 }, fg = { 240, 110, 20 }, text = "IRON", glyph = "SUPPS" }, shop = "IRON SUPPLEMENTS" },
	{ id = "FuelAndGo", name = "Fuel & Go", scope = "Local", minTier = 3, minPop = 10, perFight = 2500, winBonus = 1000, koBonus = 1500, fights = 5, slot = "corner",
		logo = { bg = { 20, 140, 60 }, fg = { 255, 255, 255 }, text = "FUEL & GO", glyph = "F&G" }, shop = "FUEL & GO" },
	{ id = "WCBProShop", name = "WCB Pro Shop", scope = "Local", minTier = 3, minPop = 12, perFight = 3000, winBonus = 1500, koBonus = 1500, fights = 5, slot = "gear",
		logo = { bg = { 25, 60, 200 }, fg = { 255, 255, 255 }, text = "WCB PRO", glyph = "WCB" }, shop = "WCB PRO SHOP" },
	{ id = "ApexAthletics", name = "Apex Athletics", scope = "National", minTier = 5, minPop = 30, perFight = 25000, winBonus = 10000, koBonus = 15000, fights = 6, slot = "trunks",
		logo = { bg = { 20, 20, 20 }, fg = { 0, 170, 190 }, text = "APEX", glyph = "AX" } },
	{ id = "VoltaraEnergy", name = "Voltara Energy", scope = "National", minTier = 5, minPop = 35, perFight = 30000, winBonus = 12000, koBonus = 20000, fights = 6, slot = "corner",
		logo = { bg = { 120, 30, 160 }, fg = { 255, 230, 60 }, text = "VOLTARA", glyph = "V" } },
	{ id = "NorthwindAir", name = "Northwind Air", scope = "Global", minTier = 6, minPop = 45, perFight = 60000, winBonus = 25000, koBonus = 25000, fights = 6, slot = "robe",
		logo = { bg = { 240, 240, 240 }, fg = { 25, 60, 200 }, text = "NORTHWIND", glyph = "NW" } },
	{ id = "BluepeakMobile", name = "Bluepeak Mobile", scope = "Global", minTier = 6, minPop = 50, perFight = 80000, winBonus = 30000, koBonus = 40000, fights = 6, slot = "gear",
		logo = { bg = { 0, 90, 170 }, fg = { 255, 255, 255 }, text = "BLUEPEAK", glyph = "BP" } },
	{ id = "CrownmarkWatches", name = "Crownmark Watches", scope = "Global", minTier = 8, minPop = 65, perFight = 250000, winBonus = 100000, koBonus = 100000, fights = 5, slot = "robe",
		logo = { bg = { 20, 20, 20 }, fg = { 230, 180, 30 }, text = "CROWNMARK", glyph = "CM" } },
	{ id = "HalcyonMotors", name = "Halcyon Motors", scope = "Global", minTier = 8, minPop = 75, perFight = 400000, winBonus = 150000, koBonus = 200000, fights = 5, slot = "trunks",
		logo = { bg = { 160, 160, 170 }, fg = { 20, 20, 20 }, text = "HALCYON", glyph = "H" } },
}
Catalog.SponsorSlots = { "trunks", "robe", "corner", "gear" }

function Catalog.Sponsor(id)
	return Catalog.Find(Catalog.Sponsors, id)
end

-- sponsors whose requirements a career meets (deterministic; offers = this minus active deals)
function Catalog.SponsorsFor(careerTier, popularity)
	local out = {}
	for _, s in ipairs(Catalog.Sponsors) do
		if (careerTier or 1) >= s.minTier and (popularity or 0) >= s.minPop then
			table.insert(out, s)
		end
	end
	return out
end

------------------------------------------------------------------------
-- Gym facility tier (Config.GymTiers). Shared so server (growth) and client (visuals, Hub) agree.
------------------------------------------------------------------------
-- average upgrade progress 0..1 over Catalog.StationOrder (unbought stations count as level 1)
function Catalog.GymProgress(levels)
	levels = type(levels) == "table" and levels or {}
	local total, n = 0, 0
	for _, id in ipairs(Catalog.StationOrder) do
		local st = Catalog.Stations[id]
		local maxLv = st and #st.levels or 1
		if maxLv > 1 then
			local lv = math.clamp(math.floor(tonumber(levels[id]) or 1), 1, maxLv)
			total += (lv - 1) / (maxLv - 1)
			n += 1
		end
	end
	return n > 0 and total / n or 0
end

local function ownsAny(owned, list)
	for _, id in ipairs(list) do
		if owned[id] == true then
			return true
		end
	end
	return false
end

-- unmet requirements of one tier as display strings (empty = reached)
function Catalog.GymTierNeeds(tierDef, frac, owned, careerTier)
	owned = type(owned) == "table" and owned or {}
	local needs = {}
	if frac < tierDef.minFrac then
		table.insert(needs, string.format("Upgrade equipment to %d%% (now %d%%)", math.floor(tierDef.minFrac * 100 + 0.5), math.floor(frac * 100)))
	end
	if (careerTier or 1) < tierDef.minCareerTier and not (tierDef.orOwned and ownsAny(owned, tierDef.orOwned)) then
		local tierName = Config.Tiers[tierDef.minCareerTier] and Config.Tiers[tierDef.minCareerTier].name or ("tier " .. tierDef.minCareerTier)
		-- only offer alternatives that can be bought before that rank (an item locked behind a higher
		-- career tier is no shortcut), by their shop names
		local alts = {}
		for _, id in ipairs(tierDef.orOwned or {}) do
			local item = Catalog.Find(Catalog.Shop, id)
			if not (item and item.requiresTier and item.requiresTier >= tierDef.minCareerTier) then
				table.insert(alts, item and item.name or tostring(id))
			end
		end
		local alt = #alts > 0 and (" (or own the " .. table.concat(alts, " / ") .. ")") or ""
		table.insert(needs, "Reach " .. tierName .. alt)
	end
	for _, id in ipairs(tierDef.needsOwned or {}) do
		if owned[id] ~= true then
			local item = Catalog.Find(Catalog.Shop, id)
			table.insert(needs, "Own the " .. (item and item.name or id))
		end
	end
	return needs
end

-- (gym.levels, owned, career tier) -> index 1..4, Config.GymTiers entry, frac 0..1, needs-for-next (or nil at the top)
function Catalog.GymTier(levels, owned, careerTier)
	local frac = Catalog.GymProgress(levels)
	local idx = 1
	for i, t in ipairs(Config.GymTiers) do
		if #Catalog.GymTierNeeds(t, frac, owned, careerTier) == 0 then
			idx = i
		else
			break
		end
	end
	local nextDef = Config.GymTiers[idx + 1]
	return idx, Config.GymTiers[idx], frac, nextDef and Catalog.GymTierNeeds(nextDef, frac, owned, careerTier) or nil
end

-- every facility unlocked at tier index idx (cumulative) as a set { [facilityId] = true }
function Catalog.GymFacilities(idx)
	local set = {}
	for i = 1, math.clamp(tonumber(idx) or 1, 1, #Config.GymTiers) do
		for _, f in ipairs(Config.GymTiers[i].facilities) do
			set[f] = true
		end
	end
	return set
end

return Catalog
