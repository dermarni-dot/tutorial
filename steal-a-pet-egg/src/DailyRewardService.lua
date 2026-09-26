-- DailyRewardService (ModuleScript) — ServerScriptService.Modules.DailyRewardService
-- Daily streak rewards: players claim one reward per day from the 🎁 Daily
-- button. Every day in a row moves them to a better reward (Config.DailyRewards);
-- missing a day starts them over at Day 1. Days roll over at midnight UTC.
-- The streak is saved in the player's profile as profile.Daily.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local DailyRewardService = {}

local GameService
local remote
local notifyRemote

local GOLD = Color3.fromRGB(255, 215, 90)
local RED = Color3.fromRGB(255, 100, 100)
local DAY = 24 * 60 * 60

local function today()
	return os.time() // DAY
end

-- Which card (1-7) a streak number lands on. After the last day it loops.
local function dayIndex(streak)
	return (streak - 1) % #Config.DailyRewards + 1
end

-- The streak number the next claim would give, and whether it can be claimed now.
local function nextClaim(daily, t)
	if daily.LastDay == t then
		return daily.Streak + 1, false -- already claimed today
	elseif daily.LastDay == t - 1 then
		return daily.Streak + 1, true -- claimed yesterday: streak continues
	end
	return 1, true -- first claim, or missed a day
end

-- Cash and Speed rewards grow with the player so they stay worth claiming.
local function rewardAmount(player, reward)
	if reward.Kind == "Cash" then
		local income = player:GetAttribute("IncomePerSec") or 0
		return math.max(reward.MinCash, math.floor(income * 60 * reward.CashMinutes))
	elseif reward.Kind == "Speed" then
		return math.max(reward.MinSpeed, math.floor(GameService.GetSpeed(player) * reward.SpeedPercent))
	end
	return nil
end

local function describe(player, reward)
	if reward.Kind == "Cash" then
		return Util.Money(rewardAmount(player, reward))
	elseif reward.Kind == "Speed" then
		return "+" .. Util.FormatNumber(rewardAmount(player, reward)) .. " Speed"
	end
	return reward.Rarity .. " Egg"
end

local function sendState(player)
	local profile = GameService.GetProfile(player)
	if not profile or not player.Parent then
		return
	end
	local t = today()
	local daily = profile.Daily
	local streak, canClaim = nextClaim(daily, t)
	local rewards = {}
	for i, reward in ipairs(Config.DailyRewards) do
		rewards[i] = { Kind = reward.Kind, Rarity = reward.Rarity, Text = describe(player, reward) }
	end
	remote:FireClient(player, {
		Day = dayIndex(streak), -- the card the next claim is for
		CanClaim = canClaim,
		CurrentStreak = if daily.LastDay >= t - 1 then daily.Streak else 0,
		NextAt = (t + 1) * DAY, -- unix time the next day starts
		Rewards = rewards,
	})
end

local function claim(player)
	local profile = GameService.GetProfile(player)
	if not profile then
		return
	end
	local t = today()
	local streak, canClaim = nextClaim(profile.Daily, t)
	if not canClaim then
		sendState(player)
		return
	end

	local day = dayIndex(streak)
	local reward = Config.DailyRewards[day]
	local ok, text = false, describe(player, reward)
	if reward.Kind == "Cash" then
		ok = GameService.GrantCash(player, rewardAmount(player, reward))
	elseif reward.Kind == "Speed" then
		ok = GameService.GrantSpeed(player, rewardAmount(player, reward))
	elseif reward.Kind == "Egg" then
		local mutation
		ok, mutation = GameService.GiveBaseEgg(player, reward.Rarity)
		if ok and mutation then
			text = mutation .. " " .. text
		elseif not ok then
			notifyRemote:FireClient(player, "🥚 Your pet pen is full! Sell or fuse a pet, then claim your egg.", RED)
		end
	end

	if ok then
		profile.Daily.Streak = streak
		profile.Daily.LastDay = t
		local where = if reward.Kind == "Egg" then " It's in your pet pen." else ""
		notifyRemote:FireClient(player, "🎁 Day " .. day .. " reward: " .. text .. "!" .. where .. " 🔥 " .. streak .. "-day streak", GOLD)
	end
	sendState(player)
end

function DailyRewardService.Init(gameService, dailyEvent, notifyEvent)
	GameService = gameService
	remote = dailyEvent
	notifyRemote = notifyEvent

	remote.OnServerEvent:Connect(function(player, action)
		if action == "Claim" then
			claim(player)
		elseif action == "Refresh" then
			sendState(player)
		end
	end)
end

-- Call once the player's profile has loaded.
function DailyRewardService.PlayerReady(player)
	sendState(player)
end

-- Admin testing: "next" pretends a day has passed (streak continues),
-- "reset" starts the streak over at Day 1.
function DailyRewardService.AdminSet(player, mode)
	local profile = GameService.GetProfile(player)
	if not profile then
		return false
	end
	if mode == "reset" then
		profile.Daily.Streak = 0
		profile.Daily.LastDay = -1
	else
		profile.Daily.LastDay = today() - 1
	end
	sendState(player)
	return true
end

return DailyRewardService
