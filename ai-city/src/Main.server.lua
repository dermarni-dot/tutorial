-- Main (Script) — ServerScriptService.Main
-- Starts AI City: builds the map, loads the saved city (or makes new
-- families), starts the clock and brings everyone to life.
--
--   MapBuilder      the city: streets, buildings, interiors, parks, the lake
--   Life            who lives here: families, ages, jobs, schools, daily plans
--   CityService     the clock, city stats and mood, the mayor, elections,
--                   speeches, coins, memories, gossip, news, saving
--   CitizenService  the NPCs: walking, working, sitting, soccer, chatting...
--   DialogueService talking to citizens (and them talking to each other)
--   CrimeService    fighting, stabbing, pickpocketing, robberies, witnesses, police, jail
--   CombatService   weapons (the Hardware store shop), blocking, waking up at the hospital
--   StreetCrimeService other people's crimes (pickpockets, bag snatchers, robbers, graffiti), arrests, the jail
--   FitnessService  sprinting XP, fitness levels, gym treadmills
--   FoodService     buying food at the Bakery, Cafe, Diner, Restaurant, Ice Cream shop and Market
--   JobService      jobs for players: clock in at a workplace and work a shift for coins
--   BrawlService    street fights between citizens (crowds, police, breaking them up)
--   DisguiseService hoodies, ski masks and disguises (the Clothing store), wearing them
--   PlayerService   elevators, citizen profiles, the directory
--
-- Other scripts can get the map with:
--   local map = require(ServerScriptService.Modules.MapBuilder).Build()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Modules = ServerScriptService:WaitForChild("Modules")

local RUN_DAY_CYCLE = true -- set to false if another script already moves Lighting.ClockTime
local START_HOUR = 7.5

local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local Life = require(Modules:WaitForChild("Life"))
local CityService = require(Modules:WaitForChild("CityService"))

local map = MapBuilder.Build()
print(string.format("[AI City] Built %d places, %d homes, %d walking points", #map.PlaceList, #map.Homes, #map.Nodes))

local services = {
	Config = Config,
	Map = map,
	MapBuilder = MapBuilder,
	Life = Life.new(Config, map.Homes),
	City = CityService,
}
CityService.Init(services)
if not CityService.Load() then
	services.Life:Generate()
end
print(string.format("[AI City] %d citizens in %d households", #services.Life.List, #services.Life.Households))

CityService.StartClock(START_HOUR, RUN_DAY_CYCLE)
CityService.Start()
CityService.News("Welcome to AI City! Give a speech on the plaza stage and win the next election.", "Welcome", true)

-- The citizens. Turn them off with Config.RUN_CITIZENS = false if your own
-- scripts spawn citizens (you can still use CitizenLook and Life).
if Config.RUN_CITIZENS ~= false then
	services.Citizens = require(Modules:WaitForChild("CitizenService"))
	services.Dialogue = require(Modules:WaitForChild("DialogueService"))
	services.Crime = require(Modules:WaitForChild("CrimeService"))
	services.Players = require(Modules:WaitForChild("PlayerService"))
	services.Combat = require(Modules:WaitForChild("CombatService"))
	services.Disguise = require(Modules:WaitForChild("DisguiseService"))
	services.Brawl = require(Modules:WaitForChild("BrawlService"))
	services.StreetCrime = require(Modules:WaitForChild("StreetCrimeService"))
	services.Fitness = require(Modules:WaitForChild("FitnessService"))
	services.Food = require(Modules:WaitForChild("FoodService"))
	services.Jobs = require(Modules:WaitForChild("JobService"))
	services.Homes = require(Modules:WaitForChild("HomeService"))
	services.Gangs = require(Modules:WaitForChild("GangService"))
	services.Love = require(Modules:WaitForChild("RelationshipService"))
	services.Dialogue.Start(services)
	services.Crime.Start(services)
	services.Players.Start(services)
	services.Combat.Start(services)
	services.Disguise.Start(services)
	services.Brawl.Start(services)
	services.StreetCrime.Start(services)
	services.Fitness.Start(services)
	services.Food.Start(services)
	services.Jobs.Start(services)
	services.Homes.Start(services)
	services.Gangs.Start(services)
	services.Love.Start(services)
	task.spawn(services.Citizens.Start, services)
end
