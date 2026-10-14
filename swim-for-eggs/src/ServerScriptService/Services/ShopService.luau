--[[
	ShopService  (ModuleScript)
	Location: ServerScriptService > Services > ShopService

	Handles the three Safe Zone shops (Oxygen Tanks, Flippers, Egg Mutations).
	The client calls:  Remotes.ShopAction:InvokeServer(shopId, itemId)
	  * Not owned -> buy with Coins (server checks price) then auto-equip.
	  * Owned     -> equip.
	Returns (success: boolean, message: string).

	NEVER trust the client: ids, prices and location are all validated here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("SwimForEggsShared")
local Config = require(Shared:WaitForChild("Config"))

local ShopService = {}

local lastRequest = {} -- [Player] = os.clock()

function ShopService:Init(context)
	self.Context = context
	self.Services = context.Services
end

local function isOnSafeZone(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return root.Position.Z <= Config.World.SafeZoneMaxZ + 10 and root.Position.Y >= Config.World.SurfaceY - 2
end

function ShopService:HandleRequest(player: Player, shopId: any, itemId: any): (boolean, string)
	-- 1) Type validation
	if type(shopId) ~= "string" or type(itemId) ~= "string" then
		return false, "Invalid request."
	end
	if not Config.Shops[shopId] then
		return false, "That shop doesn't exist."
	end
	local item = Config.GetItem(shopId, itemId)
	if not item then
		return false, "That item doesn't exist."
	end

	-- 2) Rate limit
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < Config.Gameplay.ShopRequestCooldown then
		return false, "Slow down!"
	end
	lastRequest[player] = now

	-- 3) State validation
	local DataService = self.Services.DataService
	if not DataService:GetProfile(player) then
		return false, "Your data is still loading..."
	end
	if self.Services.EggService:GetCarriedEgg(player) then
		return false, "Drop off your egg before shopping!"
	end
	if not isOnSafeZone(player) then
		return false, "Shops only work in the Safe Zone."
	end

	-- 4) Equip if owned
	if DataService:OwnsItem(player, shopId, itemId) then
		if DataService:GetEquippedItem(player, shopId).Id == itemId then
			return true, item.Name .. " is already equipped."
		end
		DataService:Equip(player, shopId, itemId)
		return true, "Equipped " .. item.Name .. "!"
	end

	-- 5) Buy
	if not DataService:SpendCoins(player, item.Price) then
		local missing = item.Price - DataService:GetCoins(player)
		return false, string.format("You need %d more coins!", missing)
	end
	DataService:GrantItem(player, shopId, itemId)
	DataService:Equip(player, shopId, itemId)
	task.spawn(DataService.SaveNow, DataService, player) -- protect purchases from crashes
	return true, "Bought & equipped " .. item.Name .. "!"
end

function ShopService:Start()
	self.Context.Remotes.ShopAction.OnServerInvoke = function(player, shopId, itemId)
		local ok, success, message = pcall(self.HandleRequest, self, player, shopId, itemId)
		if not ok then
			warn("[ShopService] error:", success)
			return false, "Something went wrong. Try again!"
		end
		return success, message
	end

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return ShopService
