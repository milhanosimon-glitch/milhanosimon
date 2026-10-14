--[[
	SwimOxygenService  (ModuleScript)
	Location: ServerScriptService > Services > SwimOxygenService

	Gear-based swimming & oxygen (server-authoritative):
	  * Swim speed  = equipped Flippers' SwimSpeed (Humanoid.WalkSpeed drives swim speed).
	  * Breath time = equipped Tank's Oxygen seconds.
	  * Deeper zones drain faster (zone.OxygenDrainMultiplier = "water pressure").
	  * Head above water -> oxygen refills quickly.
	  * Oxygen hits 0 -> the player drowns. The egg is dropped by EggService's death handler.

	Replicated player attributes (read by the HUD):
	  Oxygen (number), MaxOxygen (number), InWater (bool), LastDeathCause (string)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SwimForEggsShared")
local Config = require(Shared:WaitForChild("Config"))

local G = Config.Gameplay

local SwimOxygenService = {}

function SwimOxygenService:Init(context)
	self.Context = context
	self.Services = context.Services
end

local function hasInfiniteOxygen(player: Player): boolean
	return player:GetAttribute(Config.GamePasses.InfiniteOxygen.Attribute) == true
end

function SwimOxygenService:RefillOxygen(player: Player)
	local max = player:GetAttribute("MaxOxygen") or self.Services.DataService:GetEquippedItem(player, "Tanks").Oxygen
	player:SetAttribute("Oxygen", max)
end

function SwimOxygenService:Drown(player: Player, humanoid: Humanoid)
	if humanoid.Health <= 0 then
		return
	end
	player:SetAttribute("LastDeathCause", "Drowned")
	local notify = self.Context.Remotes.Notify
	notify:FireClient(player, "💀 You ran out of oxygen and drowned!", "Danger")
	humanoid.Health = 0 -- EggService's Died handler drops the egg where you sank
end

----------------------------------------------------------------------
-- Gear visuals: the equipped Tank on the back, Flippers on the feet.
----------------------------------------------------------------------
local function weldVisual(character: Model, attachTo: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = attachTo.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachTo
	weld.Part1 = p
	weld.Parent = p
	p.Parent = character
	return p
end

function SwimOxygenService:ApplyGearVisuals(player: Player)
	local character = player.Character
	if not character then
		return
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("GearVisual") then
			child:Destroy()
		end
	end

	local DataService = self.Services.DataService
	local tank = DataService:GetEquippedItem(player, "Tanks")
	local flippers = DataService:GetEquippedItem(player, "Flippers")

	-- R15 uses UpperTorso / LeftFoot / RightFoot, R6 uses Torso / Left Leg / Right Leg.
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		local tankPart = weldVisual(
			character,
			torso,
			"GearTank",
			Vector3.new(2.6, 1.3, 1.3),
			CFrame.new(0, 0, 0.9) * CFrame.Angles(0, 0, math.rad(90)),
			tank.Color,
			Enum.PartType.Cylinder
		)
		tankPart:SetAttribute("GearVisual", true)
	end

	for _, footName in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }) do
		local foot = character:FindFirstChild(footName)
		if foot and foot:IsA("BasePart") then
			local yOffset = if footName:find("Leg") then -foot.Size.Y / 2 else -foot.Size.Y / 2 + 0.1
			local fin = weldVisual(
				character,
				foot,
				"GearFlipper",
				Vector3.new(1.1, 0.2, 2.4),
				CFrame.new(0, yOffset, -0.9),
				flippers.Color
			)
			fin.Material = Enum.Material.Neon
			fin:SetAttribute("GearVisual", true)
		end
	end
end

function SwimOxygenService:_tickPlayer(player: Player, dt: number)
	local DataService = self.Services.DataService
	if not DataService:GetProfile(player) then
		return
	end

	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if not humanoid or not root or not head or humanoid.Health <= 0 then
		return
	end

	-- Oxygen
	local tank = DataService:GetEquippedItem(player, "Tanks")
	local maxOxygen = tank.Oxygen
	if player:GetAttribute("MaxOxygen") ~= maxOxygen then
		player:SetAttribute("MaxOxygen", maxOxygen)
	end

	local oxygen = player:GetAttribute("Oxygen")
	if type(oxygen) ~= "number" then
		oxygen = maxOxygen
	end

	local underwater = Config.IsUnderwater(head.Position)
	if underwater then
		if not hasInfiniteOxygen(player) then
			local depth = Config.GetDepth(head.Position.Y)
			local zone = Config.Zones[Config.GetZoneIndexForDepth(depth)]
			oxygen -= G.BaseOxygenDrainPerSecond * zone.OxygenDrainMultiplier * dt
		end
	else
		oxygen += G.OxygenRefillPerSecond * dt
	end
	oxygen = math.clamp(oxygen, 0, maxOxygen)
	player:SetAttribute("Oxygen", oxygen)

	if oxygen <= 0 and underwater and not hasInfiniteOxygen(player) then
		self:Drown(player, humanoid)
		return
	end

	-- Swim speed (Flippers only work in water)
	local inWater = Config.IsInWater(root.Position)
	if player:GetAttribute("InWater") ~= inWater then
		player:SetAttribute("InWater", inWater)
	end

	local speed = G.LandWalkSpeed
	if inWater then
		speed = DataService:GetEquippedItem(player, "Flippers").SwimSpeed
	end
	if player:GetAttribute("CarryingEgg") then
		speed *= G.CarrySpeedMultiplier
	end
	if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
		humanoid.WalkSpeed = speed
	end
end

function SwimOxygenService:Start()
	local function onCharacterAdded(player: Player, character: Model)
		player:SetAttribute("LastDeathCause", "")
		player:SetAttribute("InWater", false)
		-- Fresh lungs on every respawn.
		local tank = self.Services.DataService:GetEquippedItem(player, "Tanks")
		player:SetAttribute("MaxOxygen", tank.Oxygen)
		player:SetAttribute("Oxygen", tank.Oxygen)

		-- Wait for the body parts to exist, then dress the character.
		task.spawn(function()
			if character:WaitForChild("HumanoidRootPart", 10) then
				task.wait(0.5) -- let the avatar finish assembling
				if player.Character == character then
					local ok, err = pcall(self.ApplyGearVisuals, self, player)
					if not ok then
						warn("[SwimOxygenService] Gear visuals failed:", err)
					end
				end
			end
		end)
	end

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	-- Re-dress the character when gear changes in a shop.
	self.Services.DataService.GearChanged:Connect(function(player, shopId)
		if shopId == "Tanks" or shopId == "Flippers" then
			pcall(self.ApplyGearVisuals, self, player)
		end
	end)

	-- Fixed-rate tick (cheaper than every frame, still smooth for the HUD).
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < G.OxygenTickRate then
			return
		end
		local step = accumulator
		accumulator = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(self._tickPlayer, self, player, step)
			if not ok then
				warn("[SwimOxygenService] tick error for", player.Name, err)
			end
		end
	end)
end

return SwimOxygenService
