--[[
	GameManager  (ModuleScript)
	Location: ServerScriptService > Services > GameManager

	The core loop glue:
	  * Detects a carrier entering the EggDropZone in the Safe Zone.
	  * Scores: base egg value x Mutation multiplier x 2x Coins pass -> Coins.
	  * Increments "Eggs Stolen" leaderstat.
	  * Drops the chasing monster's aggro (it swims home).
	  * Keeps each player's "Objective" attribute up to date for the HUD.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SwimForEggsShared")
local Config = require(Shared:WaitForChild("Config"))

local GameManager = {}

local SCORE_CHECK_INTERVAL = 0.1
local DEFAULT_OBJECTIVE = "Swim down the slope and steal an egg! 🥚"

local LOST_MESSAGES = {
	drowned = "💧 You drowned and dropped the egg! Grab it before it floats home.",
	died = "💀 You died and dropped the egg!",
	caught = nil, -- MonsterService already sends a message
	timeout = nil,
	left = nil,
	scored = nil,
}

function GameManager:Init(context)
	self.Context = context
	self.Services = context.Services
end

local function isInsidePart(zonePart: BasePart, position: Vector3): boolean
	local localPos = zonePart.CFrame:PointToObjectSpace(position)
	local half = zonePart.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

function GameManager:SetObjective(player: Player, text: string)
	if player.Parent then
		player:SetAttribute("Objective", text)
	end
end

function GameManager:Score(player: Player)
	local EggService = self.Services.EggService
	local DataService = self.Services.DataService
	local MonetizationService = self.Services.MonetizationService

	local info = EggService:ConsumeEgg(player)
	if not info then
		return
	end

	local multiplier = info.Multiplier
	local hasDouble = MonetizationService and MonetizationService:HasPass(player, "DoubleCoins")
	if hasDouble then
		multiplier *= Config.Gameplay.DoubleCoinsMultiplier
	end
	local coins = math.max(1, math.floor(info.BaseValue * multiplier + 0.5))

	DataService:AddCoins(player, coins)
	DataService:IncrementEggsStolen(player, 1)

	-- Monster gives up and swims home.
	self.Services.MonsterService:DropAggroFor(player)

	self:SetObjective(player, DEFAULT_OBJECTIVE)
	self.Context.Remotes.Celebrate:FireClient(player, {
		Coins = coins,
		ZoneName = info.ZoneName,
		Mutation = info.MutationName,
		Multiplier = multiplier,
		DoubleCoins = hasDouble == true,
	})
end

function GameManager:Start()
	local map = self.Services.MapBuilder:GetMap()
	local dropZone = map:FindFirstChild("EggDropZone", true)
	if not dropZone then
		warn("[GameManager] No EggDropZone part found in the map - scoring disabled!")
	end

	local EggService = self.Services.EggService

	-- Objective updates
	EggService.EggStolen:Connect(function(player, record)
		local zone = Config.Zones[record.ZoneIndex]
		self:SetObjective(player, string.format("Bring the %s Egg back to the Safe Zone! %s is coming!", zone.Name, zone.Monster.Name))
	end)

	EggService.EggCarrierLost:Connect(function(player, _record, reason)
		self:SetObjective(player, DEFAULT_OBJECTIVE)
		local message = LOST_MESSAGES[reason]
		if message and player.Parent then
			self.Context.Remotes.Notify:FireClient(player, message, "Warning")
		end
	end)

	local function onPlayerAdded(player: Player)
		self:SetObjective(player, DEFAULT_OBJECTIVE)
		player.CharacterAdded:Connect(function()
			if not EggService:GetCarriedEgg(player) then
				self:SetObjective(player, DEFAULT_OBJECTIVE)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	-- Scoring loop
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < SCORE_CHECK_INTERVAL or not dropZone then
			return
		end
		accumulator = 0

		-- Copy the carriers first: scoring mutates the table.
		local carriers = {}
		for player in pairs(EggService:GetAllCarriers()) do
			table.insert(carriers, player)
		end

		for _, player in ipairs(carriers) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and isInsidePart(dropZone, root.Position) then
				local ok, err = pcall(self.Score, self, player)
				if not ok then
					warn("[GameManager] Score failed for", player.Name, err)
				end
			end
		end
	end)
end

return GameManager
