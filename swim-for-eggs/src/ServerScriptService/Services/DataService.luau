--[[
	DataService  (ModuleScript)
	Location: ServerScriptService > Services > DataService

	Owns ALL persistent player data. Other services never touch DataStores or
	leaderstats directly; they call this API.

	Player hierarchy created on join (replicates to the client so the UI can read it):

	Player
	├── leaderstats (Folder)
	│   ├── Coins (IntValue)
	│   └── Eggs Stolen (IntValue)
	├── Gear (Folder)                      -- what is currently EQUIPPED
	│   ├── EquippedTank (StringValue)     -- e.g. "Scuba"
	│   ├── EquippedFlippers (StringValue) -- e.g. "Turbo"
	│   └── EquippedMutation (StringValue) -- e.g. "Golden"
	└── Inventory (Folder)                 -- what is OWNED
	    ├── Tanks (Folder)     > BoolValue per owned item id
	    ├── Flippers (Folder)  > BoolValue per owned item id
	    └── Mutations (Folder) > BoolValue per owned item id

	Saved data shape:
	{
		Coins = 0, EggsStolen = 0,
		Owned    = { Tanks = { Bubble = true }, Flippers = { Starter = true }, Mutations = { None = true } },
		Equipped = { Tanks = "Bubble", Flippers = "Starter", Mutations = "None" },
		Receipts = { "purchaseId", ... },   -- Developer Product idempotency
	}
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SwimForEggsShared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local DataService = {}
DataService.ProfileLoaded = Signal.new() -- (player, profile)
DataService.GearChanged = Signal.new() -- (player, shopId, itemId)

local STORE_NAME = "SwimForEggs_PlayerData_v1"
local LOAD_ATTEMPTS = 5
local SAVE_ATTEMPTS = 4

local store = nil
local profiles = {} -- [Player] = { Data = table, CanSave = bool, Saving = bool }

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Adds any keys missing from `data` (lets you add new fields without wiping saves).
local function reconcile(data, template)
	for key, value in pairs(template) do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" then
			-- Only recurse into dictionaries, not arrays like Receipts.
			if next(value) ~= nil and #value == 0 then
				reconcile(data[key], value)
			end
		end
	end
end

local function buildDefaultData()
	local data = {
		Coins = Config.Gameplay.StartingCoins,
		EggsStolen = 0,
		Owned = {},
		Equipped = {},
		Receipts = {},
	}
	for _, shopId in ipairs(Config.ShopOrder) do
		local defaultId = Config.GetDefaultItemId(shopId)
		data.Owned[shopId] = { [defaultId] = true }
		data.Equipped[shopId] = defaultId
	end
	return data
end

local DEFAULT_DATA = buildDefaultData()

-- pcall with exponential backoff (1s, 2s, 4s, ...)
local function withRetries(label, attempts, fn)
	local lastErr
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(("[DataService] %s failed (attempt %d/%d): %s"):format(label, attempt, attempts, tostring(result)))
		if attempt < attempts then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, lastErr
end

-- Repairs corrupted / outdated data (removed items, wrong types, ...).
local function sanitize(data)
	if type(data.Coins) ~= "number" or data.Coins ~= data.Coins then
		data.Coins = 0
	end
	data.Coins = math.max(0, math.floor(data.Coins))
	if type(data.EggsStolen) ~= "number" then
		data.EggsStolen = 0
	end
	if type(data.Receipts) ~= "table" then
		data.Receipts = {}
	end

	for _, shopId in ipairs(Config.ShopOrder) do
		if type(data.Owned[shopId]) ~= "table" then
			data.Owned[shopId] = {}
		end
		local defaultId = Config.GetDefaultItemId(shopId)
		data.Owned[shopId][defaultId] = true

		-- Drop items that no longer exist in Config.
		for itemId in pairs(data.Owned[shopId]) do
			if not Config.GetItem(shopId, itemId) then
				data.Owned[shopId][itemId] = nil
			end
		end

		local equipped = data.Equipped[shopId]
		if type(equipped) ~= "string" or not data.Owned[shopId][equipped] then
			data.Equipped[shopId] = defaultId
		end
	end
end

----------------------------------------------------------------------
-- Value objects (leaderstats / Gear / Inventory)
----------------------------------------------------------------------
local function newValue(className, name, value, parent)
	local v = Instance.new(className)
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function buildFolders(player, data)
	for _, name in ipairs({ "leaderstats", "Gear", "Inventory" }) do
		local old = player:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	newValue("IntValue", "Coins", data.Coins, leaderstats)
	newValue("IntValue", "Eggs Stolen", data.EggsStolen, leaderstats)
	leaderstats.Parent = player

	local gear = Instance.new("Folder")
	gear.Name = "Gear"
	for _, shopId in ipairs(Config.ShopOrder) do
		newValue("StringValue", Config.Shops[shopId].GearValue, data.Equipped[shopId], gear)
	end
	gear.Parent = player

	local inventory = Instance.new("Folder")
	inventory.Name = "Inventory"
	for _, shopId in ipairs(Config.ShopOrder) do
		local folder = Instance.new("Folder")
		folder.Name = shopId
		for itemId in pairs(data.Owned[shopId]) do
			newValue("BoolValue", itemId, true, folder)
		end
		folder.Parent = inventory
	end
	inventory.Parent = player
end

local function syncLeaderstats(player, data)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local coins = leaderstats:FindFirstChild("Coins")
	local eggs = leaderstats:FindFirstChild("Eggs Stolen")
	if coins then
		coins.Value = data.Coins
	end
	if eggs then
		eggs.Value = data.EggsStolen
	end
end

----------------------------------------------------------------------
-- Load / Save
----------------------------------------------------------------------
local function keyFor(player)
	return "Player_" .. player.UserId
end

function DataService:_load(player)
	local data = nil
	local canSave = false

	if store then
		local ok, result = withRetries("Load " .. player.Name, LOAD_ATTEMPTS, function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			data = result
			canSave = true
		elseif RunService:IsStudio() then
			warn("[DataService] DataStore unavailable in Studio (enable 'Studio Access to API Services'). Using temporary data.")
		else
			-- Never let someone play with blank data that would overwrite their real save.
			player:Kick("Swim for Eggs couldn't load your data. Please rejoin in a minute!")
			return
		end
	end

	if type(data) ~= "table" then
		data = deepCopy(DEFAULT_DATA)
	end
	reconcile(data, DEFAULT_DATA)
	sanitize(data)

	if player.Parent ~= Players then
		return -- left while loading
	end

	local profile = { Data = data, CanSave = canSave, Saving = false }
	profiles[player] = profile
	buildFolders(player, data)
	player:SetAttribute("DataLoaded", true)
	self.ProfileLoaded:Fire(player, profile)
end

function DataService:SaveNow(player): boolean
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return false
	end

	-- Wait for an in-flight save to finish so saves never overlap.
	local waited = 0
	while profile.Saving and waited < 30 do
		waited += task.wait(0.1)
	end
	profile.Saving = true

	local snapshot = deepCopy(profile.Data)
	local ok = withRetries("Save " .. player.Name, SAVE_ATTEMPTS, function()
		return store:UpdateAsync(keyFor(player), function()
			return snapshot
		end)
	end)

	profile.Saving = false
	return ok
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function DataService:GetProfile(player)
	return profiles[player]
end

function DataService:WaitForProfile(player, timeout: number?)
	local deadline = os.clock() + (timeout or 10)
	while not profiles[player] and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService:GetCoins(player): number
	local profile = profiles[player]
	return profile and profile.Data.Coins or 0
end

function DataService:AddCoins(player, amount: number): boolean
	local profile = profiles[player]
	if not profile or type(amount) ~= "number" or amount ~= amount then
		return false
	end
	profile.Data.Coins = math.max(0, math.floor(profile.Data.Coins + amount))
	syncLeaderstats(player, profile.Data)
	return true
end

-- Returns true only if the player could afford it (atomic check + spend).
function DataService:SpendCoins(player, amount: number): boolean
	local profile = profiles[player]
	if not profile or type(amount) ~= "number" or amount < 0 then
		return false
	end
	if profile.Data.Coins < amount then
		return false
	end
	profile.Data.Coins -= amount
	syncLeaderstats(player, profile.Data)
	return true
end

function DataService:IncrementEggsStolen(player, amount: number?)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Data.EggsStolen += (amount or 1)
	syncLeaderstats(player, profile.Data)
end

function DataService:OwnsItem(player, shopId: string, itemId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.Data.Owned[shopId] ~= nil and profile.Data.Owned[shopId][itemId] == true
end

function DataService:GrantItem(player, shopId: string, itemId: string): boolean
	local profile = profiles[player]
	if not profile or not Config.GetItem(shopId, itemId) then
		return false
	end
	profile.Data.Owned[shopId][itemId] = true

	local folder = player:FindFirstChild("Inventory") and player.Inventory:FindFirstChild(shopId)
	if folder and not folder:FindFirstChild(itemId) then
		newValue("BoolValue", itemId, true, folder)
	end
	return true
end

function DataService:Equip(player, shopId: string, itemId: string): boolean
	local profile = profiles[player]
	if not profile or not self:OwnsItem(player, shopId, itemId) then
		return false
	end
	profile.Data.Equipped[shopId] = itemId

	local gear = player:FindFirstChild("Gear")
	local value = gear and gear:FindFirstChild(Config.Shops[shopId].GearValue)
	if value then
		value.Value = itemId
	end
	self.GearChanged:Fire(player, shopId, itemId)
	return true
end

-- Returns the Config item table of what the player has equipped (falls back to default).
function DataService:GetEquippedItem(player, shopId: string)
	local profile = profiles[player]
	local itemId = profile and profile.Data.Equipped[shopId] or Config.GetDefaultItemId(shopId)
	return Config.GetItem(shopId, itemId) or Config.Items[shopId][1]
end

function DataService:HasReceipt(player, purchaseId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and table.find(profile.Data.Receipts, purchaseId) ~= nil
end

function DataService:RecordReceipt(player, purchaseId: string)
	local profile = profiles[player]
	if not profile then
		return
	end
	table.insert(profile.Data.Receipts, purchaseId)
	while #profile.Data.Receipts > Config.Monetization.ReceiptHistoryLimit do
		table.remove(profile.Data.Receipts, 1)
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function DataService:Init(context)
	self.Context = context
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] Could not open DataStore:", result)
	end
end

function DataService:Start()
	local function onPlayerAdded(player)
		local ok, err = pcall(self._load, self, player)
		if not ok then
			warn("[DataService] Load crashed for", player.Name, err)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:SaveNow(player)
		profiles[player] = nil
	end)

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(Config.Gameplay.AutosaveInterval)
			for player in pairs(profiles) do
				task.spawn(self.SaveNow, self, player)
			end
		end
	end)

	-- Server shutdown: save everyone in parallel (BindToClose gives us ~30s).
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				self:SaveNow(player)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
