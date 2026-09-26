-- Monetization (ModuleScript) — ServerScriptService.Modules.Monetization
-- Handles Developer Product receipts and the 2x Cash game pass.
-- Set the IDs in ReplicatedStorage.Shared.Config.Products.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Monetization = {}

-- Remember receipts already granted this server so a retry never double-grants.
local granted = {}

function Monetization.Init(GameService)
	local products = Config.Products

	MarketplaceService.ProcessReceipt = function(receipt)
		if granted[receipt.PurchaseId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player or not GameService.IsReady(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local handled = false
		if products.InstantHatch ~= 0 and receipt.ProductId == products.InstantHatch then
			handled = GameService.InstantHatch(player)
		elseif products.EggRain ~= 0 and receipt.ProductId == products.EggRain then
			GameService.EggRain(player)
			handled = true
		elseif products.SpeedBoost ~= 0 and receipt.ProductId == products.SpeedBoost then
			handled = GameService.GrantSpeed(player, Config.SpeedBoostFor(GameService.GetSpeed(player)))
		else
			for _, item in ipairs(Config.Shop) do
				if item.Luck and products[item.Key] ~= 0 and receipt.ProductId == products[item.Key] then
					handled = GameService.ActivateServerLuck(item.Luck, player)
				end
			end
		end

		if handled then
			granted[receipt.PurchaseId] = true
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, item in ipairs(Config.Shop) do
			if item.Pass and products[item.Key] ~= 0 and passId == products[item.Key] then
				GameService.GrantPass(player, item.Key)
			end
		end
	end)
end

return Monetization
