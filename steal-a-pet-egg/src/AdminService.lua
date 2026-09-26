-- AdminService (ModuleScript) — ServerScriptService.Modules.AdminService
-- Testing commands for you (the game owner), anyone in Config.Admins, and
-- everyone while playing in Roblox Studio.
--
-- Use them from the 🛠 Admin panel, or type them in chat:
--   !cash 1000000      add cash (negative numbers take it away)
--   !speed 500         add Speed          !setspeed 50   set Speed exactly
--   !egg Mythic        get an egg of that rarity in your hands  (!egg mythic galaxy = with a mutation)
--   !pet Divine        put a random pet of that rarity in your base (!pet divine rainbow = mutated)
--   !pet Galaxy Dragon put that exact pet in your base   (!shiny ... for a shiny one)
--   !hatch             hatch every egg in your base now
--   !grow              grow every pet one stage   (!grow adult = straight to Adult)
--   !treadmill 7       set your treadmill tier (1 = Basic ... 7 = Cosmic)
--   !luck 10           start 10x server luck
--   !rain              egg rain           !refill   respawn all wild eggs
--   !tp void           teleport (town, forest, desert, snow, volcano, void, candy, ocean, heaven)
--   !daily             make today's daily reward claimable again (!daily reset = back to Day 1)
--   !time night        set the time for everyone (day, sunset, night, 0-24; !time cycle = back to normal)
--   !reset             wipe your progress
--   !help              list the commands

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DailyRewardService = require(script.Parent:WaitForChild("DailyRewardService"))

local AdminService = {}

local GameService
local notifyRemote

local GOLD = Color3.fromRGB(255, 215, 90)
local RED = Color3.fromRGB(255, 100, 100)

local function isAdmin(player)
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.Admins or {}, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
	return ok and rank >= 254
end

local function say(player, text, color)
	notifyRemote:FireClient(player, "🛠 " .. text, color or GOLD)
end

-- Case-insensitive match for rarity names (so "mythic" works)
local function findRarity(word)
	for _, r in ipairs(Config.Rarities) do
		if string.lower(r.Id) == string.lower(word or "") then
			return r.Id
		end
	end
	return nil
end

local function findMutation(word)
	for _, m in ipairs(Config.Mutations) do
		if string.lower(m.Id) == string.lower(word or "") then
			return m.Id
		end
	end
	return nil
end

-- Pulls a mutation name off the end of the args, if there is one.
local function popMutation(args)
	local m = findMutation(args[#args])
	if m then
		table.remove(args)
	end
	return m
end

local function findPet(name)
	for petName in pairs(Config.CreatureByName) do
		if string.lower(petName) == string.lower(name or "") then
			return petName
		end
	end
	return nil
end

local COMMANDS = {}

COMMANDS.cash = function(player, args)
	local amount = tonumber(args[1]) or 1000000
	GameService.Admin.AddCash(player, amount)
	say(player, "Added $" .. amount)
end

COMMANDS.speed = function(player, args)
	local amount = tonumber(args[1]) or 100
	GameService.GrantSpeed(player, amount)
end

COMMANDS.setspeed = function(player, args)
	local value = tonumber(args[1]) or Config.StartingSpeed
	GameService.Admin.SetSpeed(player, value)
	say(player, "Speed set to " .. value)
end

COMMANDS.egg = function(player, args)
	local mutation = popMutation(args)
	local rarity = findRarity(args[1]) or "Common"
	if GameService.Admin.GiveEgg(player, rarity, mutation) then
		say(player, "Here's a " .. (if mutation then mutation .. " " else "") .. rarity .. " Egg. Carry it home!")
	end
end

local function givePet(player, args, shiny)
	local mutation = popMutation(args)
	local word = table.concat(args, " ")
	local target = findPet(word) or findRarity(word) or "Common"
	local ok, result = GameService.Admin.GivePet(player, target, shiny, mutation)
	if ok then
		say(player, "Added " .. (if shiny then "✨Shiny " else "") .. (if mutation then mutation .. " " else "") .. result .. " to your base")
	else
		say(player, "Couldn't add pet: " .. tostring(result), RED)
	end
end

COMMANDS.pet = function(player, args)
	givePet(player, args, false)
end

COMMANDS.shiny = function(player, args)
	givePet(player, args, true)
end

COMMANDS.grow = function(player, args)
	local toAdult = string.lower(args[1] or "") == "adult" or string.lower(args[1] or "") == "max"
	GameService.Admin.Grow(player, toAdult)
	say(player, if toAdult then "All your pets are now Adults" else "Your pets grew up one stage")
end

COMMANDS.treadmill = function(player, args)
	local level = tonumber(args[1]) or #Config.TreadmillLevels
	GameService.Admin.SetTreadmill(player, level)
	say(player, "Treadmill set to level " .. level)
end

COMMANDS.hatch = function(player)
	GameService.Admin.HatchAll(player)
end

COMMANDS.luck = function(player, args)
	local mult = tonumber(args[1]) or 10
	GameService.ActivateServerLuck(mult, player)
end

COMMANDS.rain = function(player)
	GameService.EggRain(player)
end

COMMANDS.refill = function(player)
	GameService.Admin.RefillNests()
	say(player, "Respawned every wild egg")
end

COMMANDS.tp = function(player, args)
	local zone = table.concat(args, " ")
	if not GameService.Admin.Teleport(player, zone) then
		say(player, "Unknown place. Try: town, forest, desert, snow, volcano, void, candy, ocean, heaven, shroom, spooky, clockwork, cyber", RED)
	end
end

COMMANDS.daily = function(player, args)
	local mode = string.lower(args[1] or "")
	if DailyRewardService.AdminSet(player, if mode == "reset" then "reset" else "next") then
		say(player, if mode == "reset" then "Daily streak reset to Day 1" else "Skipped to the next day: your daily reward is ready")
	end
end

local TIMES = { day = 13, noon = 12, morning = 8, sunset = 18.2, dusk = 18.7, night = 0, midnight = 0 }
COMMANDS.time = function(player, args)
	local word = string.lower(args[1] or "")
	local clock = TIMES[word] or tonumber(word)
	workspace:SetAttribute("ClockOverride", if clock then clock % 24 else nil)
	say(player, if clock then "Time set to " .. word .. " for everyone" else "Day/night cycle is running again")
end

COMMANDS.reset = function(player)
	GameService.Admin.Reset(player)
	say(player, "Progress reset", RED)
end

COMMANDS.help = function(player)
	say(player, "!cash !speed !setspeed !egg !pet !shiny !hatch !grow !treadmill !luck !rain !refill !tp !daily !time !reset")
end

local function run(player, message)
	if not isAdmin(player) then
		return
	end
	local words = string.split(message, " ")
	local name = string.lower(table.remove(words, 1) or "")
	local args = {}
	for _, w in ipairs(words) do
		if w ~= "" then
			table.insert(args, w)
		end
	end
	local command = COMMANDS[name]
	if command then
		local ok, err = pcall(command, player, args)
		if not ok then
			say(player, "Command failed: " .. tostring(err), RED)
		end
	end
end

function AdminService.Init(gameService, notifyEvent, adminEvent)
	GameService = gameService
	notifyRemote = notifyEvent

	-- The Admin panel sends commands through this RemoteEvent
	adminEvent.OnServerEvent:Connect(function(player, message)
		if type(message) == "string" and #message < 200 then
			run(player, message)
		end
	end)

	-- Chat commands start with "!"
	local function hook(player)
		if isAdmin(player) then
			player:SetAttribute("IsAdmin", true)
		end
		player.Chatted:Connect(function(message)
			if string.sub(message, 1, 1) == "!" then
				run(player, string.sub(message, 2))
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
end

return AdminService
