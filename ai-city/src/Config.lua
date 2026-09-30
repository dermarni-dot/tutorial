-- AI City :: shared settings (tweak these to tune the game)
-- ReplicatedStorage.Shared.Config
--
-- Every key from the original file is still here with the same shape, so the
-- rest of the game keeps working. Changed values say what they were and why.
local Config = {}

Config.POPULATION = 150 -- a big city: more people on the streets and in the houses (lower it if the server struggles)
Config.SEED = 1776 -- same seed = same citizens every server (lets memories persist)
Config.DAY_LENGTH = 480 -- real seconds per in-game day (1 in-game hour = 20 seconds)
Config.WALK_SPEED = 9.5 -- a brisk city walking pace, used whenever a player is close enough to see them
Config.TRAVEL_SPEED = 16 -- pace far away from every player, so trips across the ~700-stud city still fit the day
Config.HURRY_SPEED = 14 -- a jog, for citizens running late for work or curfew
Config.WATCH_RADIUS = 140 -- citizens within this many studs of any player walk at the real pace
Config.TALK_RADIUS = 16 -- how close a player must stay while talking
Config.GOSSIP_RADIUS = 9
Config.GOSSIP_COOLDOWN = 22
Config.SPEECH_RADIUS = 75
Config.SPEECH_COOLDOWN = 45
Config.MEMORY_LIMIT = 30
Config.ELECTION_INTERVAL = 480 -- was 420: now exactly one election per in-game day, so it always lands at the same hour
Config.STARTING_COINS = 100
Config.COIN_TICK = 10 -- coins each player gets every real minute
Config.GIFT_AMOUNT = 10
Config.DATASTORE_NAME = "AICity_v1"

-- the State Prison east of town (PrisonService)
Config.PRISON = true -- false: arrests use the little holding cell at the police station
Config.PRISON_INMATES = 20 -- inmates who live there (two to a cell)
Config.PRISON_SECONDS = 45 -- a player's base sentence; +25 seconds per wanted star

Config.ValueNames = { "wealth", "community", "safety", "freedom", "nature", "tradition" }

-- Stances are what players talk about in speeches, and what mayors pass as policies.
-- "values" = which citizen values the idea appeals to (+) or offends (-).
-- "city" = what happens to city stats when a mayor passes it.
-- Balance rules used below: every stance offends at least one value (so no
-- idea is liked by everyone), and every policy's city effects add up to
-- somewhere between +2 and +6 (so no policy is an automatic win).
Config.Stances = {
	{ id = "LowerTaxes", label = "Lower taxes", pitch = "Keep more of what you earn!",
		values = { wealth = 1, freedom = 0.5, community = -0.5 }, city = { economy = 8, safety = -4 } },
	{ id = "RaiseWages", label = "Raise wages", pitch = "Every worker deserves more!",
		values = { community = 1, wealth = 0.4, tradition = -0.3 }, city = { economy = -3, happiness = 6 } },
	-- was safety +12 / economy -3 (net +9, far better than anything else)
	{ id = "MorePolice", label = "Add more police patrols", pitch = "A safe city is a happy city!",
		values = { safety = 1, tradition = 0.5, freedom = -0.7 }, city = { safety = 10, economy = -4 } },
	{ id = "BuildParks", label = "Build more parks", pitch = "Green space for everyone!",
		values = { nature = 1, community = 0.5, wealth = -0.3 }, city = { happiness = 5, economy = -3 } },
	-- was liked by every value with no downside, so it always won; parties cost safety now
	{ id = "FreeFestival", label = "Throw a city festival", pitch = "Let's celebrate together!",
		values = { community = 1, freedom = 0.4, tradition = 0.2, safety = -0.3 }, city = { happiness = 8, economy = -4, safety = -2 } },
	-- was economy +12 / happiness -3 (net +9); smog makes people a bit less happy now
	{ id = "NewFactory", label = "Open a new factory", pitch = "Jobs, jobs, jobs!",
		values = { wealth = 0.8, nature = -1, tradition = 0.2 }, city = { economy = 10, happiness = -5 } },
	{ id = "Curfew", label = "Start a nighttime curfew", pitch = "Home by ten, stay safe!",
		values = { safety = 0.8, tradition = 0.6, freedom = -1 }, city = { safety = 8, happiness = -5 } },
	{ id = "FundSchool", label = "Fund the school", pitch = "Invest in our future!",
		values = { community = 0.7, tradition = 0.2, wealth = -0.2, freedom = 0.3 }, city = { happiness = 4, economy = 2 } },
	-- new: nature and tradition only had one or two ideas each
	{ id = "PlantTrees", label = "Plant trees on every street", pitch = "A greener city breathes easier!",
		values = { nature = 1, tradition = 0.2, wealth = -0.4 }, city = { happiness = 4, economy = -1 } },
	{ id = "HistoricDistrict", label = "Protect the old town", pitch = "Keep our history alive!",
		values = { tradition = 1, community = 0.3, freedom = -0.3, wealth = -0.2 }, city = { happiness = 3, economy = 1 } },
	{ id = "NightMarket", label = "Open a night market", pitch = "Shop, eat and stay out late!",
		values = { wealth = 0.6, freedom = 0.6, community = 0.3, safety = -0.5, tradition = -0.3 }, city = { economy = 7, safety = -3 } },
	{ id = "NeighborhoodWatch", label = "Start a neighborhood watch", pitch = "Neighbors looking out for neighbors!",
		values = { safety = 0.7, community = 0.6, freedom = -0.4 }, city = { safety = 5, happiness = 1, economy = -1 } },
	{ id = "BankLoans", label = "Cheap loans from the city bank", pitch = "Start your dream business!",
		values = { wealth = 0.9, freedom = 0.4, tradition = -0.4, safety = -0.2 }, city = { economy = 7, happiness = 1, safety = -3 } },
}

-- City "moods" shown on the HUD, from calm to chaotic.
Config.CityStates = {
	Celebrating = { emoji = "🎉", label = "Celebrating", color = Color3.fromRGB(255, 120, 220), desc = "Music in the streets. Everyone's out partying." },
	Prosperous = { emoji = "💰", label = "Prosperous", color = Color3.fromRGB(255, 205, 70), desc = "Money is flowing and people are content." },
	Peaceful = { emoji = "☮️", label = "Peaceful", color = Color3.fromRGB(110, 215, 140), desc = "Calm streets, happy neighbors." },
	Stable = { emoji = "🙂", label = "Stable", color = Color3.fromRGB(120, 175, 240), desc = "Nothing special. The city ticks along." },
	Tense = { emoji = "😟", label = "Tense", color = Color3.fromRGB(240, 170, 80), desc = "People are grumbling. Something could snap." },
	Unrest = { emoji = "✊", label = "Unrest", color = Color3.fromRGB(240, 110, 60), desc = "Protests are forming. Trust is breaking down." },
	Chaos = { emoji = "🔥", label = "CHAOS", color = Color3.fromRGB(235, 50, 50), desc = "Crime, riots and fury. The city is falling apart!" },
}

-- Jobs. "place" is the id of a building in Config.Places (MapBuilder gives
-- every place enough work spots for its slots). Hours are in-game hours 0-24.
Config.Jobs = {
	{ title = "Baker", place = "Bakery", slots = 3, start = 5, stop = 13, pay = 12 },
	{ title = "Barista", place = "Cafe", slots = 3, start = 7, stop = 15, pay = 10 },
	{ title = "Doctor", place = "Hospital", slots = 2, start = 8, stop = 18, pay = 25 },
	{ title = "Nurse", place = "Hospital", slots = 3, start = 8, stop = 17, pay = 16 },
	{ title = "Police Officer", place = "PoliceStation", slots = 3, start = 9, stop = 18, pay = 16 },
	-- new: nobody watched the city at night, even though crime and curfews happen then
	{ title = "Night Officer", place = "PoliceStation", slots = 2, start = 18, stop = 24, pay = 18 },
	{ title = "Teacher", place = "School", slots = 3, start = 7, stop = 15, pay = 14 },
	{ title = "Factory Worker", place = "Factory", slots = 6, start = 6, stop = 15, pay = 12 },
	{ title = "Shopkeeper", place = "Shop", slots = 3, start = 9, stop = 18, pay = 13 },
	{ title = "City Clerk", place = "TownHall", slots = 3, start = 9, stop = 17, pay = 15 },
	{ title = "Gardener", place = "Park", slots = 2, start = 7, stop = 14, pay = 10 },
	{ title = "Street Musician", place = "Plaza", slots = 2, start = 11, stop = 19, pay = 6 },
	-- new buildings, new jobs
	{ title = "Bank Teller", place = "Bank", slots = 3, start = 9, stop = 17, pay = 18 },
	{ title = "Bank Manager", place = "Bank", slots = 1, start = 9, stop = 17, pay = 30 },
	{ title = "Firefighter", place = "FireStation", slots = 3, start = 8, stop = 20, pay = 17 },
	{ title = "Librarian", place = "Library", slots = 2, start = 9, stop = 17, pay = 12 },
	{ title = "Chef", place = "Restaurant", slots = 2, start = 11, stop = 22, pay = 15 },
	{ title = "Waiter", place = "Restaurant", slots = 2, start = 11, stop = 22, pay = 9 },
	{ title = "Pharmacist", place = "Pharmacy", slots = 1, start = 9, stop = 18, pay = 20 },
	{ title = "Office Worker", place = "Office", slots = 5, start = 9, stop = 17, pay = 17 },
	{ title = "Hotel Receptionist", place = "Hotel", slots = 2, start = 7, stop = 19, pay = 11 },
	{ title = "Cinema Clerk", place = "Cinema", slots = 2, start = 14, stop = 23, pay = 9 },
	{ title = "Fitness Coach", place = "Gym", slots = 1, start = 6, stop = 14, pay = 12 },
	{ title = "Store Clerk", place = "Mall", slots = 4, start = 10, stop = 19, pay = 11 },
	{ title = "Mechanic", place = "GasStation", slots = 2, start = 7, stop = 16, pay = 14 },
	{ title = "Warehouse Worker", place = "Warehouse", slots = 3, start = 6, stop = 15, pay = 12 },
	-- new: the three schools, the daycare and the new buildings
	{ title = "Middle School Teacher", place = "MiddleSchool", slots = 3, start = 7, stop = 15, pay = 14 },
	{ title = "High School Teacher", place = "HighSchool", slots = 3, start = 7, stop = 15, pay = 15 },
	{ title = "Coach", place = "HighSchool", slots = 1, start = 10, stop = 18, pay = 13 },
	{ title = "Daycare Worker", place = "Daycare", slots = 2, start = 7, stop = 18, pay = 11 },
	{ title = "Museum Guide", place = "Museum", slots = 2, start = 10, stop = 18, pay = 12 },
	{ title = "Mail Carrier", place = "PostOffice", slots = 2, start = 8, stop = 16, pay = 13 },
	{ title = "Arcade Attendant", place = "Arcade", slots = 1, start = 12, stop = 22, pay = 9 },
	{ title = "Cook", place = "Diner", slots = 2, start = 6, stop = 15, pay = 12 },
	{ title = "Programmer", place = "Office", slots = 4, start = 9, stop = 17, pay = 22 },
	{ title = "Accountant", place = "Office", slots = 3, start = 9, stop = 17, pay = 19 },
	{ title = "Night Janitor", place = "Office", slots = 1, start = 18, stop = 24, pay = 11 },
	{ title = "Community Organizer", place = "CommunityCenter", slots = 1, start = 10, stop = 18, pay = 12 },
	-- someone behind the till in every shop (see CitizenService.TryCheckout)
	{ title = "Toy Store Clerk", place = "ToyStore", slots = 1, start = 10, stop = 19, pay = 10 },
	{ title = "Electronics Clerk", place = "Electronics", slots = 1, start = 10, stop = 19, pay = 12 },
	{ title = "Bookseller", place = "Bookstore", slots = 1, start = 9, stop = 18, pay = 10 },
	{ title = "Florist", place = "Florist", slots = 1, start = 8, stop = 17, pay = 10 },
	{ title = "Pet Shop Clerk", place = "PetShop", slots = 1, start = 9, stop = 18, pay = 10 },
	{ title = "Ice Cream Server", place = "IceCream", slots = 1, start = 11, stop = 21, pay = 9 },
	{ title = "Hardware Clerk", place = "Hardware", slots = 1, start = 8, stop = 17, pay = 11 },
}
-- Realistic citizens from the Roblox catalog (all optional; empty lists keep
-- the built-in look). Paste the number from a catalog link:
--   body bundles  roblox.com/bundles/<id>/...   (the body, and a 3D head with
--                 its own face if the bundle has one)
--   hair          roblox.com/catalog/<id>/...   (hair accessories)
--   clothes       3D layered clothing: { AssetId = <id>, AccessoryType = Enum.AccessoryType.Sweater }
-- Each citizen always gets the same pick from each list, so the town is mixed.
Config.CITIZEN_BUNDLES = { Man = {}, Woman = {} }
Config.CITIZEN_HAIR = { Man = {}, Woman = {} }
Config.CITIZEN_CLOTHES = {
	-- examples from Roblox's own documentation:
	-- { AssetId = 6984769289, AccessoryType = Enum.AccessoryType.Sweater },
	-- { AssetId = 6984767443, AccessoryType = Enum.AccessoryType.Jacket },
}
Config.BUNDLE_HEADS = true -- use a bundle's 3D head and face (false: keep the drawn faces)
Config.ROUND_HAIR = true -- built-in hair has a round cap instead of a box
Config.UNEMPLOYED_CHANCE = 0.12
Config.RETIRE_AGE = 67

-- Families, kids and growing up (see the Life module)
Config.MAX_POPULATION = 220 -- no new babies once the city has this many people
Config.ADULT_AGE = 18 -- kids finish school and start work (or look for it) at this age
Config.DAYS_PER_YEAR = 4 -- in-game days per year of age (4 days = 32 real minutes; a newborn grows up in ~10 real hours)
Config.PREGNANCY_DAYS = 2 -- in-game days from "expecting" to the baby being born
Config.BABY_CHANCE = 0.2 -- chance per in-game day that an eligible couple starts expecting
Config.PARENT_AGE_MIN = 21 -- couples between these ages can have babies
Config.PARENT_AGE_MAX = 45
Config.MAX_KIDS = 4 -- per family
Config.COMMUTE_BUFFER = 0.25 -- spare time (in-game hours) on top of the walk to work, so people arrive a little early
Config.SCHOOL_START = 8 -- kids 6-17 are at school during these hours (with recess on the playground)
Config.SCHOOL_END = 15
Config.KIDS_BEDTIME = 20 -- under-13s; teens stay up until ADULT_BEDTIME
Config.ADULT_BEDTIME = 22
Config.WAKE_UP = 6.5
-- new: three schools by age (each has its own building and teachers), and a daycare for toddlers
Config.Schools = {
	{ place = "School", label = "Elementary School", minAge = 6, maxAge = 10 },
	{ place = "MiddleSchool", label = "Middle School", minAge = 11, maxAge = 13 },
	{ place = "HighSchool", label = "High School", minAge = 14, maxAge = 17 },
}
Config.DAYCARE_AGE = 3 -- toddlers from this age until school go to the daycare while their parents work

-- Every building on the map. MapBuilder looks places up here for their sign
-- (emoji + label). kind: "civic", "work", "store", "fun" or "home".
Config.Places = {
	{ id = "Plaza", label = "City Plaza", emoji = "⛲", kind = "civic" },
	{ id = "TownHall", label = "Town Hall", emoji = "🏛️", kind = "civic" },
	{ id = "Bank", label = "City Bank", emoji = "🏦", kind = "work" },
	{ id = "PoliceStation", label = "Police", emoji = "🚓", kind = "civic" },
	{ id = "FireStation", label = "Fire Station", emoji = "🚒", kind = "civic" },
	{ id = "Hospital", label = "Hospital", emoji = "🏥", kind = "civic" },
	{ id = "School", label = "Elementary School", emoji = "🏫", kind = "civic" },
	{ id = "MiddleSchool", label = "Middle School", emoji = "🏫", kind = "civic" },
	{ id = "HighSchool", label = "High School", emoji = "🎓", kind = "civic" },
	{ id = "Daycare", label = "Daycare", emoji = "🧸", kind = "civic" },
	{ id = "Library", label = "Library", emoji = "📚", kind = "fun" },
	{ id = "Park", label = "Central Park", emoji = "🌳", kind = "fun" },
	{ id = "SportsField", label = "Sports Field", emoji = "⚽", kind = "fun" },
	{ id = "Bakery", label = "Bakery", emoji = "🥐", kind = "store" },
	{ id = "Cafe", label = "Cafe", emoji = "☕", kind = "store" },
	{ id = "Shop", label = "Market", emoji = "🛒", kind = "store" },
	{ id = "Pharmacy", label = "Pharmacy", emoji = "💊", kind = "store" },
	{ id = "Restaurant", label = "Restaurant", emoji = "🍝", kind = "store" },
	{ id = "Hotel", label = "Grand Hotel", emoji = "🏨", kind = "work" },
	{ id = "Office", label = "Offices", emoji = "🏢", kind = "work" },
	{ id = "Cinema", label = "Cinema", emoji = "🎬", kind = "fun" },
	{ id = "Gym", label = "Gym", emoji = "🏋️", kind = "fun" },
	{ id = "Mall", label = "Clothing", emoji = "👕", kind = "store" },
	{ id = "ToyStore", label = "Toys", emoji = "🧸", kind = "store" },
	{ id = "Electronics", label = "Electronics", emoji = "📱", kind = "store" },
	{ id = "Florist", label = "Flowers", emoji = "💐", kind = "store" },
	{ id = "PetShop", label = "Pet Shop", emoji = "🐶", kind = "store" },
	{ id = "Bookstore", label = "Books", emoji = "📖", kind = "store" },
	{ id = "IceCream", label = "Ice Cream", emoji = "🍦", kind = "store" },
	{ id = "Hardware", label = "Hardware", emoji = "🔨", kind = "store" },
	{ id = "Factory", label = "Factory", emoji = "🏭", kind = "work" },
	{ id = "Warehouse", label = "Warehouse", emoji = "📦", kind = "work" },
	{ id = "GasStation", label = "Gas & Garage", emoji = "⛽", kind = "work" },
	-- new
	{ id = "Museum", label = "City Museum", emoji = "🏺", kind = "fun" },
	{ id = "PostOffice", label = "Post Office", emoji = "📮", kind = "civic" },
	{ id = "Arcade", label = "Arcade", emoji = "🕹️", kind = "fun" },
	{ id = "Diner", label = "Diner", emoji = "🍔", kind = "store" },
	{ id = "CommunityCenter", label = "Community Center", emoji = "🤝", kind = "civic" },
	{ id = "WillowPark", label = "Willow Park", emoji = "🌿", kind = "fun" },
	{ id = "Lake", label = "Mirror Lake", emoji = "🎣", kind = "fun" },
	-- the North Shore, up Shore Drive past the north edge of town
	{ id = "Funland", label = "Funland", emoji = "🎡", kind = "fun" },
	{ id = "Beach", label = "Sunset Beach", emoji = "🏖️", kind = "fun" },
	{ id = "AutoLand", label = "AutoLand", emoji = "🚗", kind = "store" },
}
Config.PlaceById = {}
for _, place in ipairs(Config.Places) do
	Config.PlaceById[place.id] = place
end

Config.Hobbies = { "painting", "playing chess", "gardening", "jogging", "cooking", "playing guitar",
	"reading", "gaming", "fishing", "dancing", "birdwatching", "knitting" }
-- the hobbies people go out for (MapBuilder gives each of these spots in the park and plaza)
Config.OutdoorHobbies = { painting = true, gardening = true, jogging = true, reading = true, birdwatching = true, fishing = true,
	["playing chess"] = true, ["playing guitar"] = true, dancing = true } -- new: the plaza has chess tables, benches and a dance floor

Config.FirstNames = { "Maria", "James", "Aisha", "Kenji", "Sofia", "Malik", "Elena", "Diego", "Priya", "Omar",
	"Grace", "Liam", "Zara", "Mateo", "Hana", "Isaac", "Nia", "Lucas", "Amara", "Theo", "Ivy", "Rafael",
	"Leila", "Noah", "Chloe", "Tariq", "Mei", "Andre", "Rosa", "Felix", "Yara", "Samuel", "Nora", "Kofi",
	"Lena", "Victor", "Imani", "Oscar", "Freya", "Jamal", "Ruby", "Hugo", "Asha", "Marcus", "Luna", "Emeka",
	"Clara", "Tomas", "Sadie", "Ravi",
	-- more names for the babies born in the city (still alternating female / male)
	"Ava", "Ethan", "Mila", "Julian", "Zoe", "Adrian", "Layla", "Kai", "Iris", "Mason", "Alma", "Elijah",
	"Naomi", "Leo", "Stella", "Arjun", "Hazel", "Caleb", "Aria", "Dominic", "Maya", "Finn", "Olivia", "Jonah",
	"Camila", "Ezra", "Talia", "Silas", "Bea", "Arlo", "Wren", "Ibrahim", "Esme", "Jasper", "Keiko", "Rowan",
	"Paloma", "Soren", "Ines", "Tobias", "Farah", "Milo", "Gemma", "Reza", "Lucia", "Declan", "Amina", "Hiro",
	"Elsa", "Nico" }
Config.LastNames = { "Lopez", "Carter", "Okafor", "Tanaka", "Rossi", "Johnson", "Novak", "Silva", "Patel",
	"Haddad", "Kim", "Walsh", "Mensah", "Garcia", "Nguyen", "Fischer", "Brooks", "Moreau", "Singh", "Reyes",
	"Larsen", "Adeyemi", "Chen", "Duarte", "Bennett" }

return Config
