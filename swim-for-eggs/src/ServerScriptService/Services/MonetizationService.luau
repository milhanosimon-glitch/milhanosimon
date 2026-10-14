--[[
	MonetizationService  (ModuleScript)
	Location: ServerScriptService > Services > MonetizationService

	* Gamepasses (one-time, permanent): Infinite Oxygen, 2x Coins.
	  Ownership is checked on join and after an in-game purchase, then exposed as
	  a replicated player attribute (e.g. "Pass_InfiniteOxygen" = true).
	* Developer Products (repeatable): 1,000 Coins, 10,000 Coins, Emergency Air.
	  Granted ONLY through MarketplaceService.ProcessReceipt, which:
	    - is the only place products are ever granted,
	    - is idempotent (PurchaseId stored in the player's saved data),
	    - returns PurchaseGranted only after the grant has been saved,
	    - returns NotProcessedYet on any failure so Roblox retries later.

	IMPORTANT: Only ONE script in the whole game may set ProcessReceipt.
	Set the real IDs in ReplicatedStorage > SwimForEggsShared > Config.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SwimForEggsShared")
local Config = require(Shared:WaitForChild("Config"))

local MonetizationService = {}

local productsById = {} -- [productId] = product config
local passesById = {} -- [passId] = pass config

function MonetizationService:Init(context)
	self.Context = context
	self.Services = context.Services

	for key, product in pairs(Config.DevProducts) do
		if product.Id ~= 0 then
			productsById[product.Id] = product
		else
			warn(("[Monetization] DevProduct '%s' has Id 0 (disabled). Set it in Config."):format(key))
		end
	end
	for key, pass in pairs(Config.GamePasses) do
		if pass.Id ~= 0 then
			passesById[pass.Id] = pass
		else
			warn(("[Monetization] GamePass '%s' has Id 0 (disabled). Set it in Config."):format(key))
		end
	end
end

----------------------------------------------------------------------
-- Gamepasses
----------------------------------------------------------------------
function MonetizationService:HasPass(player: Player, passKey: string): boolean
	local pass = Config.GamePasses[passKey]
	return pass ~= nil and player:GetAttribute(pass.Attribute) == true
end

function MonetizationService:_grantPass(player: Player, pass)
	player:SetAttribute(pass.Attribute, true)
	if pass == Config.GamePasses.InfiniteOxygen then
		self.Services.SwimOxygenService:RefillOxygen(player)
	end
end

function MonetizationService:_checkPasses(player: Player)
	if RunService:IsStudio() and Config.Monetization.StudioGrantAllPasses then
		for _, pass in pairs(Config.GamePasses) do
			self:_grantPass(player, pass)
		end
		return
	end

	for passId, pass in pairs(passesById) do
		task.spawn(function()
			for attempt = 1, 3 do
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
				if ok then
					if owns and player.Parent then
						self:_grantPass(player, pass)
					end
					return
				end
				warn(("[Monetization] UserOwnsGamePassAsync failed (%d/3): %s"):format(attempt, tostring(owns)))
				task.wait(2 * attempt)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Developer Products
----------------------------------------------------------------------
function MonetizationService:_grantProduct(player: Player, product): boolean
	local reward = product.Reward
	if reward.Type == "Coins" then
		return self.Services.DataService:AddCoins(player, reward.Amount)
	elseif reward.Type == "OxygenRefill" then
		self.Services.SwimOxygenService:RefillOxygen(player)
		return true
	end
	warn("[Monetization] Unknown reward type:", reward.Type)
	return false
end

function MonetizationService:ProcessReceipt(receiptInfo)
	local product = productsById[receiptInfo.ProductId]
	if not product then
		warn("[Monetization] Receipt for unknown product id", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player left; Roblox will retry next time they join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local DataService = self.Services.DataService
	local profile = DataService:WaitForProfile(player, 15)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Already granted (Roblox can call ProcessReceipt more than once).
	if DataService:HasReceipt(player, receiptInfo.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local ok, granted = pcall(self._grantProduct, self, player, product)
	if not ok or not granted then
		warn("[Monetization] Grant failed:", granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	DataService:RecordReceipt(player, receiptInfo.PurchaseId)

	-- Persist before confirming. In Studio without API access we can't save, so allow it.
	local saved = DataService:SaveNow(player)
	if not saved and profile.CanSave then
		-- Grant + receipt are in memory; a retry this session will hit HasReceipt above.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	self.Context.Remotes.Notify:FireClient(player, "🎉 Thanks! You received " .. product.Name, "Success")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local ok, decision = pcall(self.ProcessReceipt, self, receiptInfo)
		if not ok then
			warn("[Monetization] ProcessReceipt crashed:", decision)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		local pass = passesById[passId]
		if pass then
			self:_grantPass(player, pass)
			self.Context.Remotes.Notify:FireClient(player, "🎉 You now own " .. pass.Name .. "!", "Success")
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:_checkPasses(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_checkPasses(player)
	end
end

return MonetizationService
