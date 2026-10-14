--[[
	Config  (ModuleScript)
	Location: ReplicatedStorage > SwimForEggsShared > Config

	Single source of truth for Swim for Eggs. Both the server and the client
	require this module, so NEVER put secrets in here.

	World layout (1 stud = 1 "metre" on the Depth Meter):

	    Z = -160 ........ Z = 0 ............................................ Z = 1000
	    [  SAFE ZONE  ]  [ OCEAN: seabed slopes diagonally down from -10 to -500 ]
	    Y = +1 (land)     Surface water level is Y = 0

	Every 100 studs of depth the biome changes (5 zones).
]]

local Config = {}

----------------------------------------------------------------------
-- WORLD GEOMETRY
----------------------------------------------------------------------
Config.World = {
	SurfaceY = 0, -- Y of the water surface
	OceanMinX = -160,
	OceanMaxX = 160,
	OceanStartZ = 0, -- shoreline
	OceanEndZ = 1000, -- far aquarium wall
	ShoreDepth = 10, -- seabed depth at the shoreline
	MaxDepth = 500, -- seabed depth at the far wall
	ZoneHeight = 100, -- a new biome every 100 studs of depth

	SafeZoneMinZ = -160,
	SafeZoneMaxZ = 0,
	SafeZoneTopY = 1, -- walkable height of the Safe Zone island

	AquariumThickness = 12,
	AquariumHeightAboveSurface = 40,

	-- Set to false if you hand-build the map yourself (see GUIDE.md, section 2).
	BuildMapProcedurally = true,
}

-- Returns the seabed height (Y) at a given Z coordinate.
function Config.GetSeabedY(z: number): number
	local w = Config.World
	local t = math.clamp((z - w.OceanStartZ) / (w.OceanEndZ - w.OceanStartZ), 0, 1)
	return w.SurfaceY - (w.ShoreDepth + (w.MaxDepth - w.ShoreDepth) * t)
end

-- Inverse of GetSeabedY: the Z coordinate where the seabed reaches `depth`.
function Config.GetZForDepth(depth: number): number
	local w = Config.World
	local t = math.clamp((depth - w.ShoreDepth) / (w.MaxDepth - w.ShoreDepth), 0, 1)
	return w.OceanStartZ + t * (w.OceanEndZ - w.OceanStartZ)
end

-- Depth below the surface for a world Y value (never negative).
function Config.GetDepth(y: number): number
	return math.max(0, Config.World.SurfaceY - y)
end

-- 1..#Config.Zones
function Config.GetZoneIndexForDepth(depth: number): number
	return math.clamp(math.floor(depth / Config.World.ZoneHeight) + 1, 1, #Config.Zones)
end

-- Z range [zStart, zEnd] covered by a zone's seabed.
function Config.GetZoneZRange(zoneIndex: number): (number, number)
	local w = Config.World
	local zStart = if zoneIndex == 1 then w.OceanStartZ else Config.GetZForDepth((zoneIndex - 1) * w.ZoneHeight)
	local zEnd = if zoneIndex == #Config.Zones then w.OceanEndZ else Config.GetZForDepth(zoneIndex * w.ZoneHeight)
	return zStart, zEnd
end

-- Is the XZ position inside the ocean rectangle?
function Config.IsInOceanXZ(pos: Vector3): boolean
	local w = Config.World
	return pos.X >= w.OceanMinX and pos.X <= w.OceanMaxX and pos.Z >= w.OceanStartZ and pos.Z <= w.OceanEndZ
end

-- Used for swim speed: body is in (or touching) the water.
function Config.IsInWater(pos: Vector3): boolean
	return Config.IsInOceanXZ(pos) and pos.Y < Config.World.SurfaceY + 1.5
end

-- Used for oxygen: the HEAD is below the surface.
function Config.IsUnderwater(headPos: Vector3): boolean
	return Config.IsInOceanXZ(headPos) and headPos.Y < Config.World.SurfaceY - 0.5
end

----------------------------------------------------------------------
-- GAMEPLAY TUNING
----------------------------------------------------------------------
Config.Gameplay = {
	StartingCoins = 0,
	LandWalkSpeed = 16, -- speed on the Safe Zone island (flippers only work in water)
	CarrySpeedMultiplier = 1, -- set < 1 to make carrying an egg slower

	BaseOxygenDrainPerSecond = 1, -- multiplied by the zone's OxygenDrainMultiplier ("pressure")
	OxygenRefillPerSecond = 30, -- refill speed while your head is above water
	OxygenTickRate = 0.1, -- seconds between server oxygen updates

	EggsPerZone = 3,
	EggRespawnTime = 8, -- after an egg is scored
	DroppedEggReturnTime = 15, -- a dropped egg floats home after this long
	DropPickupCooldown = 1.5, -- the player who dropped an egg can't instantly re-grab it

	DoubleCoinsMultiplier = 2, -- 2x Coins gamepass
	AutosaveInterval = 120,
	ShopRequestCooldown = 0.25,
}

----------------------------------------------------------------------
-- CLASSIC "STEAL AN EGG" PALETTE (vibrant, SmoothPlastic + Neon)
----------------------------------------------------------------------
Config.Palette = {
	Grass = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(98, 214, 84) },
	GrassEdge = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(64, 170, 62) },
	Beach = { Material = Enum.Material.Sand, Color = Color3.fromRGB(255, 226, 150) },
	Path = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(255, 236, 179) },
	Wood = { Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(196, 132, 74) },
	RoofRed = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(255, 72, 72) },
	RoofWhite = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(255, 255, 255) },
	NeonCyan = { Material = Enum.Material.Neon, Color = Color3.fromRGB(0, 255, 230) },
	NeonPink = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 70, 200) },
	NeonYellow = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 230, 40) },
	AquariumGlass = { Material = Enum.Material.Glass, Color = Color3.fromRGB(175, 235, 255), Transparency = 0.45, Reflectance = 0.15 },
	AquariumWater = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(0, 160, 255), Transparency = 0.6 },
	DropZone = { Material = Enum.Material.Neon, Color = Color3.fromRGB(0, 255, 140), Transparency = 0.75 },

	-- Terrain water (Workspace > Terrain properties)
	WaterColor = Color3.fromRGB(20, 190, 215),
	WaterTransparency = 0.55,
	WaterReflectance = 0.25,
	WaterWaveSize = 0.12,
	WaterWaveSpeed = 8,
}

----------------------------------------------------------------------
-- DEPTH ZONES (biomes) + their guardian Sea Monsters
----------------------------------------------------------------------
-- Lighting keys are consumed by StarterPlayerScripts > DepthLighting.
Config.SurfaceLighting = {
	Ambient = Color3.fromRGB(140, 140, 150),
	OutdoorAmbient = Color3.fromRGB(150, 170, 190),
	Brightness = 3,
	AtmosphereDensity = 0.3,
	AtmosphereColor = Color3.fromRGB(199, 220, 255),
	AtmosphereDecay = Color3.fromRGB(106, 140, 180),
	AtmosphereHaze = 1,
	TintColor = Color3.fromRGB(255, 255, 255),
	Saturation = 0.15,
	Contrast = 0.05,
	WaterColor = Color3.fromRGB(20, 190, 215),
}

Config.Zones = {
	{
		Name = "Coral Reef",
		Kind = "Reef",
		TerrainMaterial = Enum.Material.Sand,
		TerrainColor = Color3.fromRGB(255, 221, 153),
		AccentColor = Color3.fromRGB(255, 85, 170),
		EggColor = Color3.fromRGB(255, 245, 210),
		EggValue = 25,
		OxygenDrainMultiplier = 1.0,
		Lighting = {
			Ambient = Color3.fromRGB(90, 170, 190),
			OutdoorAmbient = Color3.fromRGB(110, 200, 220),
			Brightness = 2.5,
			AtmosphereDensity = 0.45,
			AtmosphereColor = Color3.fromRGB(80, 220, 230),
			AtmosphereDecay = Color3.fromRGB(30, 140, 180),
			AtmosphereHaze = 1.5,
			TintColor = Color3.fromRGB(200, 255, 250),
			Saturation = 0.3,
			Contrast = 0.1,
			WaterColor = Color3.fromRGB(25, 200, 210),
		},
		Monster = {
			Name = "Snapjaw the Reef Shark",
			Kind = "Shark",
			BodyColor = Color3.fromRGB(90, 140, 200),
			BellyColor = Color3.fromRGB(235, 240, 250),
			AccentColor = Color3.fromRGB(255, 230, 0),
			Scale = 1,
			PatrolSpeed = 8,
			ChaseSpeed = 13,
			ReturnSpeed = 18,
			TurnRate = 5,
			KillRadius = 6,
			PatrolRadius = 45,
			AggroRoarTime = 0.9,
			LeadTime = 0.3,
		},
	},
	{
		Name = "Kelp Forest",
		Kind = "Kelp",
		TerrainMaterial = Enum.Material.LeafyGrass,
		TerrainColor = Color3.fromRGB(70, 130, 60),
		AccentColor = Color3.fromRGB(120, 255, 90),
		EggColor = Color3.fromRGB(170, 255, 130),
		EggValue = 100,
		OxygenDrainMultiplier = 1.25,
		Lighting = {
			Ambient = Color3.fromRGB(60, 120, 80),
			OutdoorAmbient = Color3.fromRGB(70, 140, 100),
			Brightness = 1.6,
			AtmosphereDensity = 0.55,
			AtmosphereColor = Color3.fromRGB(60, 170, 120),
			AtmosphereDecay = Color3.fromRGB(20, 90, 60),
			AtmosphereHaze = 2,
			TintColor = Color3.fromRGB(190, 240, 200),
			Saturation = 0.15,
			Contrast = 0.12,
			WaterColor = Color3.fromRGB(30, 140, 100),
		},
		Monster = {
			Name = "Kelpstrangler the Moray",
			Kind = "Eel",
			BodyColor = Color3.fromRGB(60, 110, 40),
			BellyColor = Color3.fromRGB(150, 170, 60),
			AccentColor = Color3.fromRGB(230, 255, 60),
			Segments = 10,
			Scale = 1.1,
			PatrolSpeed = 9,
			ChaseSpeed = 18,
			ReturnSpeed = 22,
			TurnRate = 5.5,
			KillRadius = 6.5,
			PatrolRadius = 50,
			AggroRoarTime = 0.8,
			LeadTime = 0.35,
		},
	},
	{
		Name = "Twilight Zone",
		Kind = "Twilight",
		TerrainMaterial = Enum.Material.Slate,
		TerrainColor = Color3.fromRGB(60, 70, 110),
		AccentColor = Color3.fromRGB(90, 140, 255),
		EggColor = Color3.fromRGB(120, 170, 255),
		EggValue = 350,
		OxygenDrainMultiplier = 1.5,
		Lighting = {
			Ambient = Color3.fromRGB(40, 50, 110),
			OutdoorAmbient = Color3.fromRGB(40, 60, 120),
			Brightness = 0.8,
			AtmosphereDensity = 0.65,
			AtmosphereColor = Color3.fromRGB(50, 60, 150),
			AtmosphereDecay = Color3.fromRGB(15, 20, 70),
			AtmosphereHaze = 2.5,
			TintColor = Color3.fromRGB(170, 180, 255),
			Saturation = 0,
			Contrast = 0.15,
			WaterColor = Color3.fromRGB(25, 40, 110),
		},
		Monster = {
			Name = "Lurelight the Anglerfish",
			Kind = "Angler",
			BodyColor = Color3.fromRGB(35, 30, 60),
			BellyColor = Color3.fromRGB(70, 60, 100),
			AccentColor = Color3.fromRGB(120, 255, 255),
			Scale = 1.3,
			PatrolSpeed = 8,
			ChaseSpeed = 23,
			ReturnSpeed = 26,
			TurnRate = 4.5,
			KillRadius = 8,
			PatrolRadius = 50,
			AggroRoarTime = 0.75,
			LeadTime = 0.35,
		},
	},
	{
		Name = "Glowing Abyss",
		Kind = "Abyss",
		TerrainMaterial = Enum.Material.Basalt,
		TerrainColor = Color3.fromRGB(40, 25, 60),
		AccentColor = Color3.fromRGB(190, 80, 255),
		EggColor = Color3.fromRGB(220, 140, 255),
		EggValue = 1200,
		OxygenDrainMultiplier = 1.75,
		Lighting = {
			Ambient = Color3.fromRGB(60, 20, 110),
			OutdoorAmbient = Color3.fromRGB(30, 10, 60),
			Brightness = 0.3,
			AtmosphereDensity = 0.72,
			AtmosphereColor = Color3.fromRGB(110, 40, 200),
			AtmosphereDecay = Color3.fromRGB(20, 0, 50),
			AtmosphereHaze = 3,
			TintColor = Color3.fromRGB(210, 170, 255),
			Saturation = 0.25,
			Contrast = 0.2,
			WaterColor = Color3.fromRGB(40, 10, 80),
		},
		Monster = {
			Name = "The Abyssal Kraken",
			Kind = "Kraken",
			BodyColor = Color3.fromRGB(110, 40, 170),
			BellyColor = Color3.fromRGB(160, 80, 220),
			AccentColor = Color3.fromRGB(0, 255, 230),
			Scale = 1.5,
			PatrolSpeed = 7,
			ChaseSpeed = 29,
			ReturnSpeed = 30,
			TurnRate = 4,
			KillRadius = 10,
			PatrolRadius = 55,
			AggroRoarTime = 0.7,
			LeadTime = 0.4,
		},
	},
	{
		Name = "Magma Vents",
		Kind = "Magma",
		TerrainMaterial = Enum.Material.CrackedLava,
		TerrainColor = Color3.fromRGB(255, 90, 20),
		AccentColor = Color3.fromRGB(255, 120, 0),
		EggColor = Color3.fromRGB(255, 170, 60),
		EggValue = 4000,
		OxygenDrainMultiplier = 2.0,
		Lighting = {
			Ambient = Color3.fromRGB(140, 50, 20),
			OutdoorAmbient = Color3.fromRGB(90, 25, 10),
			Brightness = 0.6,
			AtmosphereDensity = 0.6,
			AtmosphereColor = Color3.fromRGB(255, 90, 30),
			AtmosphereDecay = Color3.fromRGB(90, 10, 0),
			AtmosphereHaze = 2.5,
			TintColor = Color3.fromRGB(255, 190, 160),
			Saturation = 0.35,
			Contrast = 0.2,
			WaterColor = Color3.fromRGB(90, 25, 15),
		},
		Monster = {
			Name = "Magmaw the Lava Leviathan",
			Kind = "Serpent",
			BodyColor = Color3.fromRGB(45, 30, 30),
			BellyColor = Color3.fromRGB(90, 40, 30),
			AccentColor = Color3.fromRGB(255, 100, 0),
			Segments = 14,
			Scale = 1.6,
			PatrolSpeed = 10,
			ChaseSpeed = 36,
			ReturnSpeed = 36,
			TurnRate = 4.5,
			KillRadius = 11,
			PatrolRadius = 55,
			AggroRoarTime = 0.6,
			LeadTime = 0.4,
		},
	},
}

----------------------------------------------------------------------
-- SHOPS & GEAR
----------------------------------------------------------------------
-- Shop ids double as keys in the saved data (Owned.<ShopId>, Equipped.<ShopId>)
-- and as folder names under Player > Inventory.
Config.Shops = {
	Tanks = { DisplayName = "Oxygen Tanks", GearValue = "EquippedTank", ThemeColor = Color3.fromRGB(0, 200, 255), Icon = "🫧" },
	Flippers = { DisplayName = "Flippers", GearValue = "EquippedFlippers", ThemeColor = Color3.fromRGB(255, 170, 0), Icon = "🦶" },
	Mutations = { DisplayName = "Egg Mutations", GearValue = "EquippedMutation", ThemeColor = Color3.fromRGB(200, 90, 255), Icon = "🧬" },
}
Config.ShopOrder = { "Tanks", "Flippers", "Mutations" }

-- Oxygen = seconds of breath at 1x drain.
Config.Items = {
	Tanks = {
		{ Id = "Bubble", Name = "Bubble Snorkel", Oxygen = 20, Price = 0, Color = Color3.fromRGB(150, 230, 255) },
		{ Id = "Scuba", Name = "Scuba Tank", Oxygen = 40, Price = 300, Color = Color3.fromRGB(255, 210, 0) },
		{ Id = "Twin", Name = "Twin Tank", Oxygen = 70, Price = 2000, Color = Color3.fromRGB(255, 120, 40) },
		{ Id = "DeepSea", Name = "Deep-Sea Rig", Oxygen = 110, Price = 8000, Color = Color3.fromRGB(120, 90, 255) },
		{ Id = "Nuclear", Name = "Nuclear Lung", Oxygen = 180, Price = 28000, Color = Color3.fromRGB(90, 255, 60) },
	},
	-- SwimSpeed = Humanoid.WalkSpeed while in water (Roblox swim speed uses WalkSpeed).
	Flippers = {
		{ Id = "Starter", Name = "Starter Fins", SwimSpeed = 16, Price = 0, Color = Color3.fromRGB(255, 255, 255) },
		{ Id = "Coral", Name = "Coral Kickers", SwimSpeed = 22, Price = 400, Color = Color3.fromRGB(255, 110, 150) },
		{ Id = "Turbo", Name = "Turbo Tails", SwimSpeed = 28, Price = 2500, Color = Color3.fromRGB(255, 170, 0) },
		{ Id = "Jet", Name = "Jet Flippers", SwimSpeed = 34, Price = 9000, Color = Color3.fromRGB(0, 220, 255) },
		{ Id = "Mythic", Name = "Mythic Mermaid Fins", SwimSpeed = 42, Price = 30000, Color = Color3.fromRGB(200, 90, 255) },
	},
	-- Applied to any egg you steal while equipped.
	Mutations = {
		{ Id = "None", Name = "Plain Egg", Multiplier = 1, Price = 0, Color = Color3.fromRGB(240, 240, 240) },
		{ Id = "Golden", Name = "Golden Shell", Multiplier = 1.5, Price = 1000, Color = Color3.fromRGB(255, 200, 40) },
		{ Id = "Toxic", Name = "Toxic Neon", Multiplier = 2, Price = 4500, Color = Color3.fromRGB(90, 255, 60) },
		{ Id = "Rainbow", Name = "Rainbow Yolk", Multiplier = 3, Price = 15000, Color = Color3.fromRGB(255, 80, 80), Rainbow = true },
		{ Id = "Galaxy", Name = "Galaxy Egg", Multiplier = 5, Price = 50000, Color = Color3.fromRGB(120, 60, 255), Sparkles = true },
	},
}

function Config.GetItem(shopId: string, itemId: string)
	local list = Config.Items[shopId]
	if not list then
		return nil
	end
	for _, item in ipairs(list) do
		if item.Id == itemId then
			return item
		end
	end
	return nil
end

function Config.GetDefaultItemId(shopId: string): string
	return Config.Items[shopId][1].Id
end

----------------------------------------------------------------------
-- MONETIZATION
-- Replace the 0s with your real IDs (Creator Hub > your experience > Monetization).
-- An Id of 0 disables that pass/product safely.
----------------------------------------------------------------------
Config.GamePasses = {
	InfiniteOxygen = {
		Id = 0,
		Name = "Infinite Oxygen",
		Description = "Never run out of air. Breathe forever!",
		Attribute = "Pass_InfiniteOxygen",
		Icon = "♾️",
	},
	DoubleCoins = {
		Id = 0,
		Name = "2x Coins",
		Description = "Double coins from every egg you score.",
		Attribute = "Pass_DoubleCoins",
		Icon = "💰",
	},
}

Config.DevProducts = {
	Coins1000 = { Id = 0, Name = "1,000 Coins", Description = "A pouch of shiny coins.", Reward = { Type = "Coins", Amount = 1000 }, Icon = "🪙" },
	Coins10000 = { Id = 0, Name = "10,000 Coins", Description = "A treasure chest!", Reward = { Type = "Coins", Amount = 10000 }, Icon = "💎" },
	OxygenRefill = { Id = 0, Name = "Emergency Air", Description = "Instantly refill your oxygen.", Reward = { Type = "OxygenRefill" }, Icon = "🫁" },
}

Config.Monetization = {
	-- When true, every gamepass is granted while play-testing in Studio.
	StudioGrantAllPasses = false,
	ReceiptHistoryLimit = 50,
}

return Config
