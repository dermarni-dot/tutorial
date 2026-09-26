-- CodesService (ModuleScript) — ServerScriptService.Modules.CodesService
-- Redeemable codes (Config.Codes). Each code works once per player; used codes
-- are saved in the player's profile (profile.Codes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local CodesService = {}

local GameService
local remote
local lastTry = {} -- [Player] = os.clock() of their last attempt

local function grant(player, reward)
	if reward.Egg then
		local ok = GameService.GiveBaseEgg(player, reward.Egg)
		if not ok then
			return false, "Your pet pen is full! Make room, then try the code again."
		end
		return true, "A free " .. reward.Egg .. " Egg is in your pet pen!"
	elseif reward.Treat then
		if not GameService.GrantTreat(player, reward.Treat, reward.Minutes) then
			return false, "Couldn't give the treat right now."
		end
		local def = Config.TreatByKey[reward.Treat]
		return true, "A free " .. def.Icon .. " " .. def.Name .. "!"
	elseif reward.SpeedPercent then
		local amount = math.max(reward.MinSpeed or 0, math.floor(GameService.GetSpeed(player) * reward.SpeedPercent))
		GameService.GrantSpeed(player, amount)
		return true, "+" .. Util.FormatNumber(amount) .. " Speed!"
	else
		local income = player:GetAttribute("IncomePerSec") or 0
		local amount = math.max(reward.MinCash or 0, math.floor(income * 60 * (reward.CashMinutes or 0)))
		GameService.GrantCash(player, amount)
		return true, "+" .. Util.Money(amount) .. " cash!"
	end
end

function CodesService.Init(gameService, codesEvent)
	GameService = gameService
	remote = codesEvent
	remote.OnServerEvent:Connect(function(player, code)
		if type(code) ~= "string" or #code > 40 then
			return
		end
		local now = os.clock()
		if now - (lastTry[player] or 0) < 1 then
			return
		end
		lastTry[player] = now
		local profile = GameService.GetProfile(player)
		if not profile then
			return
		end
		code = string.upper((code:gsub("%s", "")))
		local reward = Config.Codes[code]
		if not reward then
			remote:FireClient(player, false, "That code doesn't exist. Check the spelling!")
			return
		end
		profile.Codes = profile.Codes or {}
		if profile.Codes[code] then
			remote:FireClient(player, false, "You already used this code.")
			return
		end
		local ok, text = grant(player, reward)
		if ok then
			profile.Codes[code] = true
		end
		remote:FireClient(player, ok, if ok then "🎉 " .. text else text)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
	end)
end

return CodesService
