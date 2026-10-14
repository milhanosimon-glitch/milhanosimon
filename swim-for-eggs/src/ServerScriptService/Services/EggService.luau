--[[
	EggService  (ModuleScript)
	Location: ServerScriptService > Services > EggService

	The Egg, Mutation & steal logic.

	Egg states:
	  Idle       - resting on its pedestal, touchable
	  Carried    - welded to a player's back
	  Dropped    - floating where the carrier drowned; anyone can grab it,
	               returns to its pedestal after Config.Gameplay.DroppedEggReturnTime
	  Respawning - scored; a new egg appears after Config.Gameplay.EggRespawnTime

	Signals (consumed by MonsterService and GameManager):
	  EggStolen(player, record)               -> monster aggro
	  EggCarrierLost(player, record, reason)  -> reason: "drowned" | "died" | "caught" | "left" | "scored"

	Replicated player attributes:
	  CarryingEgg (string zone name or nil), CarryingMultiplier (number), CarryingMutation (string)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SwimForEggsShared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local G = Config.Gameplay
local W = Config.World

local EggService = {}
EggService.EggStolen = Signal.new()
EggService.EggCarrierLost = Signal.new()

local records = {} -- [eggId] = record
local carrying = {} -- [Player] = record

----------------------------------------------------------------------
-- Visuals
----------------------------------------------------------------------
local function makeLabel(eggPart: BasePart, text: string, color: Color3)
	local old = eggPart:FindFirstChild("EggLabel")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggLabel"
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Adornee = eggPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
	gui.Parent = eggPart
end

local function clearMutationFx(eggPart: BasePart)
	for _, child in ipairs(eggPart:GetChildren()) do
		if child:GetAttribute("MutationFx") then
			child:Destroy()
		end
	end
end

-- Resets the egg to its biome look.
local function applyBaseLook(record)
	local eggPart = record.Part
	if not eggPart then
		return
	end
	local zone = Config.Zones[record.ZoneIndex]
	record.RainbowToken += 1 -- stops any rainbow loop
	clearMutationFx(eggPart)
	eggPart.Material = Enum.Material.SmoothPlastic
	eggPart.Color = zone.EggColor
	local light = eggPart:FindFirstChild("Glow")
	if light then
		light.Color = zone.AccentColor
	end
	makeLabel(eggPart, string.format("%s Egg • 💰%d", zone.Name, zone.EggValue), zone.AccentColor)
end

-- Mutation Item effects: neon material, glow, particles, rainbow cycling.
local function applyMutationLook(record, mutation)
	local eggPart = record.Part
	if not eggPart then
		return
	end
	applyBaseLook(record)
	if not mutation or mutation.Id == "None" then
		return
	end

	local zone = Config.Zones[record.ZoneIndex]
	eggPart.Material = Enum.Material.Neon
	eggPart.Color = mutation.Color

	local light = Instance.new("PointLight")
	light.Name = "MutationLight"
	light.Color = mutation.Color
	light.Range = 16
	light.Brightness = 3
	light:SetAttribute("MutationFx", true)
	light.Parent = eggPart

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "MutationParticles"
	particles.Color = ColorSequence.new(mutation.Color)
	particles.LightEmission = 1
	particles.Size = NumberSequence.new(0.5, 0)
	particles.Lifetime = NumberRange.new(0.6, 1.2)
	particles.Rate = if mutation.Sparkles then 40 else 15
	particles.Speed = NumberRange.new(1, 3)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles:SetAttribute("MutationFx", true)
	particles.Parent = eggPart

	if mutation.Sparkles then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = mutation.Color
		sparkles:SetAttribute("MutationFx", true)
		sparkles.Parent = eggPart
	end

	makeLabel(
		eggPart,
		string.format("%s %s Egg • x%s", mutation.Name, zone.Name, tostring(mutation.Multiplier)),
		mutation.Color
	)

	if mutation.Rainbow then
		local token = record.RainbowToken
		task.spawn(function()
			local hue = 0
			while record.RainbowToken == token and eggPart.Parent do
				hue = (hue + 0.02) % 1
				local color = Color3.fromHSV(hue, 1, 1)
				eggPart.Color = color
				light.Color = color
				task.wait(0.1)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Egg part lifecycle
----------------------------------------------------------------------
function EggService:_createPart(record)
	local eggPart = Instance.new("Part")
	eggPart.Name = "Egg_" .. record.Id
	eggPart.Size = Vector3.new(3, 4, 3)
	eggPart.Anchored = true
	eggPart.CanCollide = false
	eggPart.CanQuery = false
	eggPart.CanTouch = true
	eggPart.Massless = true
	eggPart.CastShadow = false
	eggPart.CFrame = record.HomeCFrame
	eggPart:SetAttribute("EggId", record.Id)
	eggPart:SetAttribute("ZoneIndex", record.ZoneIndex)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere -- stretched sphere = egg shape
	mesh.Parent = eggPart

	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Range = 12
	glow.Brightness = 1.5
	glow.Parent = eggPart

	record.Part = eggPart
	applyBaseLook(record)

	eggPart.Touched:Connect(function(hit)
		local ok, err = pcall(self._onTouched, self, record, hit)
		if not ok then
			warn("[EggService] touch error:", err)
		end
	end)

	eggPart.Parent = self.EggsFolder
	record.State = "Idle"
	return eggPart
end

function EggService:_onTouched(record, hit: BasePart)
	if record.State ~= "Idle" and record.State ~= "Dropped" then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if carrying[player] or not player:GetAttribute("DataLoaded") then
		return
	end
	if record.State == "Dropped" and record.LastDropper == player and os.clock() - record.DroppedAt < G.DropPickupCooldown then
		return
	end
	self:_attach(record, player, character)
end

function EggService:_attach(record, player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local eggPart = record.Part
	if not root or not eggPart then
		return
	end

	record.State = "Carried"
	record.Carrier = player
	record.DropToken += 1 -- cancels a pending "float home" timer
	carrying[player] = record

	-- Visually attach: held above the player's head (classic "steal" pose),
	-- welded so it follows perfectly. Massless so it doesn't slow swimming.
	eggPart.CanTouch = false
	eggPart.CFrame = root.CFrame * CFrame.new(0, 5, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = eggPart
	weld.Parent = eggPart
	eggPart.Anchored = false

	-- Mutation Item effects.
	local mutation = self.Services.DataService:GetEquippedItem(player, "Mutations")
	record.Mutation = mutation
	applyMutationLook(record, mutation)

	local zone = Config.Zones[record.ZoneIndex]
	player:SetAttribute("CarryingEgg", zone.Name)
	player:SetAttribute("CarryingMultiplier", mutation.Multiplier)
	player:SetAttribute("CarryingMutation", mutation.Id)

	self.EggStolen:Fire(player, record)
end

-- Unwelds and anchors the egg; clears the carrier. Does NOT move it.
function EggService:_detach(record)
	local eggPart = record.Part
	if eggPart then
		local weld = eggPart:FindFirstChild("CarryWeld")
		if weld then
			weld:Destroy()
		end
		eggPart.Anchored = true
		eggPart.AssemblyLinearVelocity = Vector3.zero
		eggPart.AssemblyAngularVelocity = Vector3.zero
	end

	local player = record.Carrier
	if player then
		carrying[player] = nil
		player:SetAttribute("CarryingEgg", nil)
		player:SetAttribute("CarryingMultiplier", nil)
		player:SetAttribute("CarryingMutation", nil)
	end
	record.Carrier = nil
	return player
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function EggService:GetCarriedEgg(player: Player)
	return carrying[player]
end

function EggService:GetCarriersForZone(zoneIndex: number): { Player }
	local result = {}
	for player, record in pairs(carrying) do
		if record.ZoneIndex == zoneIndex then
			table.insert(result, player)
		end
	end
	return result
end

function EggService:GetAllCarriers()
	return carrying
end

-- Puts an egg back on its pedestal (used by timers and monster reclaim).
function EggService:ReturnHome(record, reason: string?)
	local player = self:_detach(record)
	if not record.Part then
		return
	end
	record.DropToken += 1
	record.Mutation = nil
	record.Part.CFrame = record.HomeCFrame
	record.Part.CanTouch = true
	applyBaseLook(record)
	record.State = "Idle"
	if player then
		self.EggCarrierLost:Fire(player, record, reason or "returned")
	end
end

-- Drop the egg where the player is (drowning / dying). It floats there, stealable.
function EggService:DropEgg(player: Player, reason: string)
	local record = carrying[player]
	if not record or not record.Part then
		return
	end
	local position = record.Part.Position
	self:_detach(record)

	-- Only leave it in the ocean; anywhere else (e.g. on land) just send it home.
	if not Config.IsInOceanXZ(position) or position.Y > W.SurfaceY then
		record.DropToken += 1
		record.Mutation = nil
		record.Part.CFrame = record.HomeCFrame
		record.Part.CanTouch = true
		applyBaseLook(record)
		record.State = "Idle"
		self.EggCarrierLost:Fire(player, record, reason)
		return
	end

	local floorY = Config.GetSeabedY(position.Z) + 3
	position = Vector3.new(position.X, math.max(position.Y, floorY), position.Z)
	record.Part.CFrame = CFrame.new(position)
	record.Part.CanTouch = true
	record.State = "Dropped"
	record.DroppedAt = os.clock()
	record.LastDropper = player

	record.DropToken += 1
	local token = record.DropToken
	task.delay(G.DroppedEggReturnTime, function()
		if record.State == "Dropped" and record.DropToken == token then
			self:ReturnHome(record, "timeout")
		end
	end)

	self.EggCarrierLost:Fire(player, record, reason)
end

-- A Sea Monster caught the carrier: the egg goes straight back to its pedestal.
function EggService:ReclaimFromPlayer(player: Player)
	local record = carrying[player]
	if record then
		self:ReturnHome(record, "caught")
	end
end

-- Scored at the Safe Zone. Returns the reward info, destroys the egg, schedules a respawn.
function EggService:ConsumeEgg(player: Player)
	local record = carrying[player]
	if not record then
		return nil
	end
	local zone = Config.Zones[record.ZoneIndex]
	local mutation = record.Mutation or Config.Items.Mutations[1]
	local info = {
		ZoneIndex = record.ZoneIndex,
		ZoneName = zone.Name,
		BaseValue = zone.EggValue,
		Multiplier = mutation.Multiplier,
		MutationName = mutation.Name,
		MutationId = mutation.Id,
	}

	self:_detach(record)
	record.RainbowToken += 1
	record.State = "Respawning"
	record.Mutation = nil
	if record.Part then
		record.Part:Destroy()
		record.Part = nil
	end

	task.delay(G.EggRespawnTime, function()
		if record.State == "Respawning" then
			self:_createPart(record)
		end
	end)

	self.EggCarrierLost:Fire(player, record, "scored")
	return info
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function EggService:Init(context)
	self.Context = context
	self.Services = context.Services
end

function EggService:Start()
	local map = self.Services.MapBuilder:GetMap()
	self.EggsFolder = map:WaitForChild("Eggs")
	local spawns = map:WaitForChild("Spawns")

	for _, spawnPart in ipairs(spawns:GetChildren()) do
		if spawnPart:IsA("BasePart") and spawnPart.Name:match("^EggSpawn") then
			local zoneIndex = spawnPart:GetAttribute("ZoneIndex")
			if type(zoneIndex) ~= "number" or not Config.Zones[zoneIndex] then
				warn("[EggService] EggSpawn missing a valid ZoneIndex attribute:", spawnPart:GetFullName())
				continue
			end
			local id = spawnPart.Name
			local record = {
				Id = id,
				ZoneIndex = zoneIndex,
				HomeCFrame = spawnPart.CFrame,
				State = "Respawning",
				Part = nil,
				Carrier = nil,
				Mutation = nil,
				DropToken = 0,
				RainbowToken = 0,
				DroppedAt = 0,
				LastDropper = nil,
			}
			records[id] = record
			self:_createPart(record)
		end
	end

	-- Death: drop the egg where the player sank.
	local function onCharacterAdded(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then
			return
		end
		humanoid.Died:Connect(function()
			if carrying[player] then
				local cause = player:GetAttribute("LastDeathCause")
				self:DropEgg(player, if cause == "Drowned" then "drowned" else "died")
			end
		end)
	end

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		-- Character removed without dying (reset via LoadCharacter, etc.)
		player.CharacterRemoving:Connect(function()
			local record = carrying[player]
			if record then
				self:ReturnHome(record, "died")
			end
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local record = carrying[player]
		if record then
			self:ReturnHome(record, "left")
		end
		carrying[player] = nil
	end)
end

return EggService
