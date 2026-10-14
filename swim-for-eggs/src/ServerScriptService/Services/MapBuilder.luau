--[[
	MapBuilder  (ModuleScript)
	Location: ServerScriptService > Services > MapBuilder

	Procedurally builds the whole map on server start so the game is playable
	the moment you paste the scripts in:

	Workspace
	└── SwimForEggsMap (Model)
	    ├── SafeZone (Model)        ground, beach, ramp, spawn, EggDropZone, decorations
	    ├── Shops (Model)           TankShop / FlipperShop / MutationShop (ProximityPrompts)
	    ├── Aquariums (Model)       giant glass tanks replacing every fence
	    ├── Biomes (Folder)         one Model of props per depth zone
	    ├── Spawns (Folder)         EggSpawn_<zone>_<n>, MonsterHome_<zone> (invisible anchors)
	    ├── Eggs (Folder)           live egg parts (filled by EggService)
	    └── Monsters (Folder)       live monsters (filled by MonsterService)

	If you prefer to hand-build the map, set Config.World.BuildMapProcedurally = false
	and provide a Model named "SwimForEggsMap" containing at least:
	  - Spawns folder with EggSpawn_* parts (Attribute ZoneIndex) and MonsterHome_<index> parts
	  - A part named "EggDropZone"
	  - Empty "Eggs" and "Monsters" folders
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SwimForEggsShared")
local Config = require(Shared:WaitForChild("Config"))

local W = Config.World
local P = Config.Palette

local MapBuilder = {}

----------------------------------------------------------------------
-- Generic helpers
----------------------------------------------------------------------
local function make(className: string, props: { [string]: any }, parent: Instance?)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Anchored decorative part with sane defaults.
local function part(props: { [string]: any }, parent: Instance?): Part
	local merged = {
		Anchored = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Material = Enum.Material.SmoothPlastic,
	}
	for k, v in pairs(props) do
		merged[k] = v
	end
	return make("Part", merged, parent)
end

local function applyStyle(p: BasePart, style)
	p.Material = style.Material
	p.Color = style.Color
	if style.Transparency then
		p.Transparency = style.Transparency
	end
	if style.Reflectance then
		p.Reflectance = style.Reflectance
	end
end

-- Rotated slab whose TOP face runs along the line p0 -> p1 (used for seabed + ramp).
local function slopeSlab(p0: Vector3, p1: Vector3, width: number, thickness: number): (CFrame, Vector3)
	local mid = (p0 + p1) / 2
	local dir = p1 - p0
	local cf = CFrame.lookAt(mid, mid + dir.Unit) * CFrame.new(0, -thickness / 2, 0)
	return cf, Vector3.new(width, thickness, dir.Magnitude)
end

local function billboard(adornee: BasePart, text: string, color: Color3, studsOffsetY: number, size: UDim2?)
	local gui = make("BillboardGui", {
		Name = "Label",
		Size = size or UDim2.fromOffset(240, 60),
		StudsOffset = Vector3.new(0, studsOffsetY, 0),
		AlwaysOnTop = false,
		MaxDistance = 150,
		LightInfluence = 0,
		Adornee = adornee,
	}, adornee)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	}, gui)
	return gui
end

local function surfaceSign(signPart: BasePart, text: string, bg: Color3)
	local gui = make("SurfaceGui", {
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
	}, signPart)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = bg,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
	}, gui)
end

----------------------------------------------------------------------
-- TERRAIN: water volume + sloping, biome-coloured seabed
----------------------------------------------------------------------
local function buildTerrain()
	local terrain = Workspace.Terrain
	terrain.WaterColor = P.WaterColor
	terrain.WaterTransparency = P.WaterTransparency
	terrain.WaterReflectance = P.WaterReflectance
	terrain.WaterWaveSize = P.WaterWaveSize
	terrain.WaterWaveSpeed = P.WaterWaveSpeed

	for _, zone in ipairs(Config.Zones) do
		pcall(terrain.SetMaterialColor, terrain, zone.TerrainMaterial, zone.TerrainColor)
	end

	local width = W.OceanMaxX - W.OceanMinX
	local centerX = (W.OceanMaxX + W.OceanMinX) / 2

	-- 1) Water, filled zone by zone (keeps each FillBlock well under the voxel limit).
	for i = 1, #Config.Zones do
		local z0, z1 = Config.GetZoneZRange(i)
		local bottom = Config.GetSeabedY(z1) - 60
		local height = W.SurfaceY - bottom
		terrain:FillBlock(
			CFrame.new(centerX, W.SurfaceY - height / 2, (z0 + z1) / 2),
			Vector3.new(width, height, z1 - z0),
			Enum.Material.Water
		)
		task.wait()
	end

	-- 2) Seabed: a thick slab per zone, overwriting the water below the slope.
	for i, zone in ipairs(Config.Zones) do
		local z0, z1 = Config.GetZoneZRange(i)
		z0 = math.max(W.OceanStartZ - 8, z0 - 4) -- slight overlap so zones join seamlessly
		z1 = z1 + 4
		local p0 = Vector3.new(centerX, Config.GetSeabedY(z0), z0)
		local p1 = Vector3.new(centerX, Config.GetSeabedY(z1), z1)
		local cf, size = slopeSlab(p0, p1, width + 16, 48)
		terrain:FillBlock(cf, size, zone.TerrainMaterial)
		task.wait()
	end
end

----------------------------------------------------------------------
-- AQUARIUM BARRIERS (replace every fence)
----------------------------------------------------------------------
-- size.X = length along the wall, size.Y = height, size.Z = thickness
local function buildAquarium(name: string, cf: CFrame, size: Vector3, parent: Instance, rng: Random)
	local model = make("Model", { Name = name })

	local glass = part({ Name = "Glass", Size = size, CFrame = cf, CanCollide = true, CastShadow = false }, model)
	applyStyle(glass, P.AquariumGlass)

	local inner = part({
		Name = "InnerWater",
		Size = size - Vector3.new(2, 2, 4),
		CFrame = cf,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, model)
	applyStyle(inner, P.AquariumWater)

	-- Rising bubbles inside the tank.
	make("ParticleEmitter", {
		Name = "Bubbles",
		Color = ColorSequence.new(Color3.fromRGB(210, 245, 255)),
		LightEmission = 0.6,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new(0.6, 0.2),
		Lifetime = NumberRange.new(4, 7),
		Rate = math.clamp(size.X * size.Y / 2000, 5, 60),
		Speed = NumberRange.new(3, 6),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(10, 10),
	}, inner)

	-- Neon frame: top + bottom rails and vertical posts.
	local accentStyles = { P.NeonCyan, P.NeonPink }
	for _, yOff in ipairs({ size.Y / 2, -size.Y / 2 }) do
		local rail = part({
			Name = "NeonRail",
			Size = Vector3.new(size.X + 2, 2, size.Z + 1),
			CFrame = cf * CFrame.new(0, yOff, 0),
			CanCollide = false,
			CastShadow = false,
		}, model)
		applyStyle(rail, P.NeonCyan)
	end
	local postCount = math.max(2, math.floor(size.X / 48) + 1)
	for i = 0, postCount - 1 do
		local x = -size.X / 2 + (size.X / (postCount - 1)) * i
		local post = part({
			Name = "NeonPost",
			Size = Vector3.new(2, size.Y, size.Z + 1),
			CFrame = cf * CFrame.new(x, 0, 0),
			CanCollide = false,
			CastShadow = false,
		}, model)
		applyStyle(post, accentStyles[(i % 2) + 1])
	end

	-- Decorative fish swimming inside the glass (static, cheap, colourful).
	local fishColors = {
		Color3.fromRGB(255, 140, 0),
		Color3.fromRGB(255, 230, 40),
		Color3.fromRGB(255, 70, 200),
		Color3.fromRGB(0, 255, 230),
		Color3.fromRGB(120, 255, 90),
	}
	local fishCount = math.clamp(math.floor(size.X / 25), 4, 40)
	for _ = 1, fishCount do
		local localPos = Vector3.new(
			rng:NextNumber(-size.X / 2 + 4, size.X / 2 - 4),
			rng:NextNumber(-size.Y / 2 + 4, size.Y / 2 - 4),
			0
		)
		local fish = part({
			Name = "Fish",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.5, 2.5, 2.5),
			CFrame = cf * CFrame.new(localPos),
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = fishColors[rng:NextInteger(1, #fishColors)],
		}, model)
		part({
			Name = "Tail",
			Size = Vector3.new(0.4, 1.6, 1.4),
			CFrame = fish.CFrame * CFrame.new(-1.6, 0, 0),
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Material = Enum.Material.Neon,
			Color = fish.Color,
		}, model)
	end

	model.Parent = parent
	return model
end

local function buildAquariumWalls(map: Model, rng: Random)
	local folder = make("Model", { Name = "Aquariums" }, map)
	local t = W.AquariumThickness
	local top = W.SurfaceY + W.AquariumHeightAboveSurface
	local bottom = Config.GetSeabedY(W.OceanEndZ) - 70
	local height = top - bottom
	local midY = (top + bottom) / 2

	local zMin = W.SafeZoneMinZ - t
	local zMax = W.OceanEndZ + t
	local length = zMax - zMin
	local midZ = (zMin + zMax) / 2

	-- Left & right walls (rotated so their X axis runs along world Z).
	for _, side in ipairs({ -1, 1 }) do
		local x = if side < 0 then W.OceanMinX - t / 2 else W.OceanMaxX + t / 2
		buildAquarium(
			if side < 0 then "LeftAquarium" else "RightAquarium",
			CFrame.new(x, midY, midZ) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(length, height, t),
			folder,
			rng
		)
	end

	local width = (W.OceanMaxX - W.OceanMinX) + t * 2
	local midX = (W.OceanMaxX + W.OceanMinX) / 2
	-- Back wall behind the Safe Zone (only needs to stand on the island).
	local backBottom = W.SafeZoneTopY - 30
	buildAquarium(
		"BackAquarium",
		CFrame.new(midX, (top + backBottom) / 2, W.SafeZoneMinZ - t / 2),
		Vector3.new(width, top - backBottom, t),
		folder,
		rng
	)
	-- Far wall at the end of the Magma Vents.
	buildAquarium("FarAquarium", CFrame.new(midX, midY, W.OceanEndZ + t / 2), Vector3.new(width, height, t), folder, rng)
end

----------------------------------------------------------------------
-- SAFE ZONE + SHOPS
----------------------------------------------------------------------
local function buildShop(shopsModel: Model, shopId: string, position: Vector3)
	local shop = Config.Shops[shopId]
	local model = make("Model", { Name = shopId .. "Shop" })
	model:SetAttribute("ShopId", shopId)

	local base = CFrame.new(position)
	-- Counter (the prompt lives here)
	local counter = part({ Name = "Counter", Size = Vector3.new(18, 4, 4), CFrame = base * CFrame.new(0, 2, 4) }, model)
	applyStyle(counter, P.Wood)
	local counterTop = part({ Name = "CounterTop", Size = Vector3.new(19, 0.6, 5), CFrame = base * CFrame.new(0, 4.3, 4) }, model)
	counterTop.Color = shop.ThemeColor

	-- Pillars
	for _, x in ipairs({ -9, 9 }) do
		local pillar = part({ Name = "Pillar", Size = Vector3.new(1.5, 14, 1.5), CFrame = base * CFrame.new(x, 7, 4) }, model)
		applyStyle(pillar, P.RoofWhite)
		local backPillar = part({ Name = "Pillar", Size = Vector3.new(1.5, 14, 1.5), CFrame = base * CFrame.new(x, 7, -6) }, model)
		applyStyle(backPillar, P.RoofWhite)
	end

	-- Striped awning roof (classic candy stripes)
	for i = 0, 5 do
		local stripe = part({
			Name = "Awning",
			Size = Vector3.new(22 / 6, 1, 13),
			CFrame = base * CFrame.new(-11 + 22 / 12 + (22 / 6) * i, 14.5, -1) * CFrame.Angles(math.rad(-12), 0, 0),
		}, model)
		applyStyle(stripe, if i % 2 == 0 then { Material = Enum.Material.SmoothPlastic, Color = shop.ThemeColor } else P.RoofWhite)
	end

	-- Sign facing the spawn (+Z). A Part's Front face is -Z, so rotate 180°.
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(16, 4, 0.5),
		CFrame = base * CFrame.new(0, 18, 4) * CFrame.Angles(0, math.pi, 0),
	}, model)
	sign.Color = shop.ThemeColor
	surfaceSign(sign, shop.Icon .. " " .. shop.DisplayName, shop.ThemeColor)

	-- Neon trim under the counter
	local trim = part({ Name = "NeonTrim", Size = Vector3.new(18.2, 0.4, 4.2), CFrame = base * CFrame.new(0, 0.4, 4), CanCollide = false }, model)
	applyStyle(trim, { Material = Enum.Material.Neon, Color = shop.ThemeColor })

	local prompt = make("ProximityPrompt", {
		Name = "ShopPrompt",
		ActionText = "Open Shop",
		ObjectText = shop.DisplayName,
		HoldDuration = 0,
		MaxActivationDistance = 14,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
	}, counter)
	prompt:SetAttribute("ShopId", shopId)

	model.PrimaryPart = counter
	model.Parent = shopsModel
	return model
end

local function buildSafeZone(map: Model)
	local safe = make("Model", { Name = "SafeZone" }, map)
	local zLen = W.SafeZoneMaxZ - W.SafeZoneMinZ
	local zMid = (W.SafeZoneMaxZ + W.SafeZoneMinZ) / 2
	local width = (W.OceanMaxX - W.OceanMinX) + W.AquariumThickness * 2
	local midX = (W.OceanMaxX + W.OceanMinX) / 2

	-- Island body: tall enough to wall off the water in front of it.
	local ground = part({
		Name = "Ground",
		Size = Vector3.new(width, 70, zLen),
		CFrame = CFrame.new(midX, W.SafeZoneTopY - 35, zMid),
	}, safe)
	applyStyle(ground, P.Grass)

	-- Beach strip along the shoreline.
	local beach = part({
		Name = "Beach",
		Size = Vector3.new(width, 0.2, 30),
		CFrame = CFrame.new(midX, W.SafeZoneTopY + 0.1, W.SafeZoneMaxZ - 15),
	}, safe)
	applyStyle(beach, P.Beach)

	-- Central path from spawn to the shops and to the beach.
	local path = part({
		Name = "Path",
		Size = Vector3.new(16, 0.2, zLen - 30),
		CFrame = CFrame.new(midX, W.SafeZoneTopY + 0.1, zMid - 15),
	}, safe)
	applyStyle(path, P.Path)

	-- Underwater ramp so players can swim back up onto the island.
	local rampCf, rampSize = slopeSlab(
		Vector3.new(midX, W.SurfaceY - 9, W.OceanStartZ + 36),
		Vector3.new(midX, W.SafeZoneTopY, W.OceanStartZ),
		width - 40,
		3
	)
	local ramp = part({ Name = "ExitRamp", Size = rampSize, CFrame = rampCf }, safe)
	applyStyle(ramp, P.Beach)

	-- Spawn
	local spawn = make("SpawnLocation", {
		Name = "SafeZoneSpawn",
		Anchored = true,
		Neutral = true,
		Duration = 3,
		Size = Vector3.new(14, 1, 14),
		CFrame = CFrame.new(midX, W.SafeZoneTopY + 0.5, W.SafeZoneMinZ + 75),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 255, 255),
		TopSurface = Enum.SurfaceType.Smooth,
	}, safe)
	local spawnRing = part({
		Name = "SpawnRing",
		Size = Vector3.new(16, 0.8, 16),
		CFrame = spawn.CFrame * CFrame.new(0, -0.15, 0),
		CanCollide = false,
	}, safe)
	applyStyle(spawnRing, P.NeonCyan)

	-- Egg drop-off (scoring) zone on the beach.
	local dropZone = part({
		Name = "EggDropZone",
		Size = Vector3.new(90, 14, 26),
		CFrame = CFrame.new(midX, W.SafeZoneTopY + 7, W.SafeZoneMaxZ - 16),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, safe)
	applyStyle(dropZone, P.DropZone)
	billboard(dropZone, "🥚 EGG DROP-OFF 🥚", Color3.fromRGB(0, 255, 140), 10, UDim2.fromOffset(320, 70))

	-- Shops along the back of the island.
	local shops = make("Model", { Name = "Shops" }, map)
	local shopZ = W.SafeZoneMinZ + 30
	buildShop(shops, "Tanks", Vector3.new(midX - 50, W.SafeZoneTopY, shopZ))
	buildShop(shops, "Flippers", Vector3.new(midX, W.SafeZoneTopY, shopZ))
	buildShop(shops, "Mutations", Vector3.new(midX + 50, W.SafeZoneTopY, shopZ))

	-- Palm-ish decorations for the classic vibe.
	local rng = Random.new(42)
	for _ = 1, 14 do
		local x = rng:NextNumber(W.OceanMinX + 15, W.OceanMaxX - 15)
		if math.abs(x - midX) < 30 then
			continue
		end
		local z = rng:NextNumber(W.SafeZoneMinZ + 50, W.SafeZoneMaxZ - 40)
		local h = rng:NextNumber(10, 16)
		part({
			Name = "PalmTrunk",
			Size = Vector3.new(1.6, h, 1.6),
			CFrame = CFrame.new(x, W.SafeZoneTopY + h / 2, z),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(160, 110, 60),
		}, safe)
		for leaf = 0, 4 do
			part({
				Name = "PalmLeaf",
				Size = Vector3.new(1, 0.4, 8),
				CFrame = CFrame.new(x, W.SafeZoneTopY + h, z)
					* CFrame.Angles(0, math.rad(leaf * 72), 0)
					* CFrame.new(0, 0, -3.5)
					* CFrame.Angles(math.rad(-20), 0, 0),
				Color = Color3.fromRGB(60, 200, 80),
				CanCollide = false,
			}, safe)
		end
	end
end

----------------------------------------------------------------------
-- BIOME PROPS
----------------------------------------------------------------------
local function propsFor(kind: string, model: Model, pos: Vector3, rng: Random, zone)
	local accent = zone.AccentColor
	if kind == "Reef" then
		local coralColors = {
			Color3.fromRGB(255, 105, 180),
			Color3.fromRGB(255, 140, 60),
			Color3.fromRGB(170, 85, 255),
			Color3.fromRGB(255, 230, 60),
			Color3.fromRGB(0, 230, 200),
		}
		local color = coralColors[rng:NextInteger(1, #coralColors)]
		for branch = 1, rng:NextInteger(2, 4) do
			local h = rng:NextNumber(3, 9)
			local cf = CFrame.new(pos)
				* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5))
				* CFrame.new(0, h / 2, 0)
			part({
				Name = "CoralBranch" .. branch,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(h, 1.4, 1.4),
				CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
				Color = color,
			}, model)
			part({
				Name = "CoralTip",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(2, 2, 2),
				CFrame = cf * CFrame.new(0, h / 2, 0),
				Color = color,
				Material = if rng:NextNumber() < 0.3 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				CanCollide = false,
			}, model)
		end
		if rng:NextNumber() < 0.4 then
			part({ -- starfish
				Name = "Starfish",
				Size = Vector3.new(3, 0.4, 3),
				CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-4, 4), 0.5, rng:NextNumber(-4, 4))) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
				Color = Color3.fromRGB(255, 120, 40),
				CanCollide = false,
			}, model)
		end
	elseif kind == "Kelp" then
		local segments = rng:NextInteger(4, 8)
		local cf = CFrame.new(pos)
		for s = 1, segments do
			local len = 7
			cf = cf * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.15, 0.15))
			local seg = part({
				Name = "KelpStalk",
				Size = Vector3.new(0.8, len, 0.8),
				CFrame = cf * CFrame.new(0, len / 2, 0),
				Material = Enum.Material.Grass,
				Color = Color3.fromRGB(58, 145, 60),
				CanCollide = false,
			}, model)
			if s % 2 == 0 then
				part({
					Name = "KelpLeaf",
					Size = Vector3.new(3.5, 0.2, 1.4),
					CFrame = seg.CFrame * CFrame.new(1.8, 0, 0) * CFrame.Angles(0, 0, math.rad(25)),
					Material = Enum.Material.Grass,
					Color = Color3.fromRGB(90, 190, 70),
					CanCollide = false,
				}, model)
			end
			cf = cf * CFrame.new(0, len, 0)
		end
		if rng:NextNumber() < 0.25 then
			part({
				Name = "Rock",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * rng:NextNumber(4, 9),
				CFrame = CFrame.new(pos + Vector3.new(4, 0, 0)),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(80, 90, 80),
			}, model)
		end
	elseif kind == "Twilight" then
		if rng:NextNumber() < 0.55 then
			part({
				Name = "Rock",
				Size = Vector3.new(rng:NextNumber(5, 12), rng:NextNumber(4, 10), rng:NextNumber(5, 12)),
				CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(70, 80, 110),
			}, model)
		else
			-- Bioluminescent jellyfish floating above the seabed.
			local jellyPos = pos + Vector3.new(0, rng:NextNumber(15, 45), 0)
			local bell = part({
				Name = "JellyBell",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(4, 4, 4),
				CFrame = CFrame.new(jellyPos),
				Material = Enum.Material.Neon,
				Color = if rng:NextNumber() < 0.5 then Color3.fromRGB(120, 170, 255) else Color3.fromRGB(255, 120, 230),
				Transparency = 0.3,
				CanCollide = false,
			}, model)
			for t = 1, 4 do
				part({
					Name = "JellyTentacle",
					Size = Vector3.new(0.2, 5, 0.2),
					CFrame = bell.CFrame * CFrame.Angles(0, math.rad(t * 90), 0) * CFrame.new(1, -4, 0),
					Material = Enum.Material.Neon,
					Color = bell.Color,
					Transparency = 0.4,
					CanCollide = false,
				}, model)
			end
			if rng:NextNumber() < 0.35 then
				make("PointLight", { Color = bell.Color, Range = 16, Brightness = 2 }, bell)
			end
		end
	elseif kind == "Abyss" then
		if rng:NextNumber() < 0.6 then
			local crystalColor = if rng:NextNumber() < 0.5 then Color3.fromRGB(0, 255, 230) else Color3.fromRGB(200, 80, 255)
			for c = 1, rng:NextInteger(2, 4) do
				local h = rng:NextNumber(6, 18)
				local crystal = part({
					Name = "Crystal" .. c,
					Size = Vector3.new(rng:NextNumber(1.5, 3.5), h, rng:NextNumber(1.5, 3.5)),
					CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6), rng:NextNumber(-0.6, 0.6)) * CFrame.new(0, h / 2, 0),
					Material = Enum.Material.Neon,
					Color = crystalColor,
				}, model)
				if c == 1 and rng:NextNumber() < 0.4 then
					make("PointLight", { Color = crystalColor, Range = 18, Brightness = 2.5 }, crystal)
				end
			end
		else
			local stemH = rng:NextNumber(3, 7)
			part({
				Name = "MushroomStem",
				Size = Vector3.new(1.2, stemH, 1.2),
				CFrame = CFrame.new(pos + Vector3.new(0, stemH / 2, 0)),
				Color = Color3.fromRGB(230, 220, 255),
				CanCollide = false,
			}, model)
			part({
				Name = "MushroomCap",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(5, 5, 5),
				CFrame = CFrame.new(pos + Vector3.new(0, stemH + 0.5, 0)),
				Material = Enum.Material.Neon,
				Color = accent,
				CanCollide = false,
			}, model)
		end
	elseif kind == "Magma" then
		if rng:NextNumber() < 0.55 then
			local h = rng:NextNumber(6, 14)
			part({
				Name = "VentChimney",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(h, 6, 6),
				CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Basalt,
				Color = Color3.fromRGB(45, 35, 35),
			}, model)
			local mouth = part({
				Name = "VentMouth",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.6, 4.5, 4.5),
				CFrame = CFrame.new(pos + Vector3.new(0, h + 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 120, 0),
				CanCollide = false,
			}, model)
			make("ParticleEmitter", {
				Name = "VentPlume",
				Color = ColorSequence.new(Color3.fromRGB(255, 150, 40), Color3.fromRGB(60, 40, 40)),
				LightEmission = 0.8,
				Size = NumberSequence.new(1, 4),
				Transparency = NumberSequence.new(0.2, 1),
				Lifetime = NumberRange.new(2, 3),
				Rate = 12,
				Speed = NumberRange.new(6, 10),
				EmissionDirection = Enum.NormalId.Right, -- cylinder axis is X, rotated to point up
			}, mouth)
			if rng:NextNumber() < 0.4 then
				make("PointLight", { Color = Color3.fromRGB(255, 110, 20), Range = 20, Brightness = 3 }, mouth)
			end
		else
			part({
				Name = "LavaRock",
				Size = Vector3.new(rng:NextNumber(4, 10), rng:NextNumber(3, 7), rng:NextNumber(4, 10)),
				CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), 0),
				Material = Enum.Material.CrackedLava,
				Color = Color3.fromRGB(255, 90, 20),
			}, model)
		end
	end
end

local function buildBiomes(map: Model, spawns: Folder)
	local biomes = make("Folder", { Name = "Biomes" }, map)
	local midX = (W.OceanMaxX + W.OceanMinX) / 2

	for i, zone in ipairs(Config.Zones) do
		local rng = Random.new(1000 + i)
		local model = make("Model", { Name = string.format("%d_%s", i, (zone.Name:gsub(" ", ""))) }, biomes)
		local z0, z1 = Config.GetZoneZRange(i)

		-- Egg pedestals (placed first so props can avoid them)
		local eggDepth = (i - 1) * W.ZoneHeight + 60
		local eggZ = math.clamp(Config.GetZForDepth(eggDepth), z0 + 15, z1 - 15)
		local pedestalXs = {}
		local count = Config.Gameplay.EggsPerZone
		for n = 1, count do
			local x = midX + (n - (count + 1) / 2) * 45
			table.insert(pedestalXs, x)
			local z = eggZ + rng:NextNumber(-8, 8)
			local floorY = Config.GetSeabedY(z)

			local pedestal = part({
				Name = "EggPedestal",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(10, 8, 8),
				CFrame = CFrame.new(x, floorY + 1, z) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(240, 240, 250),
			}, model)
			part({
				Name = "PedestalRing",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.6, 9, 9),
				CFrame = pedestal.CFrame * CFrame.new(4.8, 0, 0),
				Material = Enum.Material.Neon,
				Color = zone.AccentColor,
				CanCollide = false,
			}, model)

			part({
				Name = string.format("EggSpawn_%d_%d", i, n),
				Size = Vector3.new(1, 1, 1),
				CFrame = CFrame.new(x, floorY + 8.5, z),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			}, spawns):SetAttribute("ZoneIndex", i)
		end

		-- Monster home: hovering above the pedestals.
		local homeZ = eggZ
		local home = part({
			Name = "MonsterHome_" .. i,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(midX, Config.GetSeabedY(homeZ) + 24, homeZ),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, spawns)
		home:SetAttribute("ZoneIndex", i)

		-- Props
		local propCount = 55
		local placed = 0
		local attempts = 0
		while placed < propCount and attempts < propCount * 4 do
			attempts += 1
			local x = rng:NextNumber(W.OceanMinX + 10, W.OceanMaxX - 10)
			local z = rng:NextNumber(z0 + 4, z1 - 4)
			local tooClose = false
			for _, px in ipairs(pedestalXs) do
				if math.abs(px - x) < 14 and math.abs(z - eggZ) < 22 then
					tooClose = true
					break
				end
			end
			if not tooClose then
				placed += 1
				propsFor(zone.Kind, model, Vector3.new(x, Config.GetSeabedY(z), z), rng, zone)
			end
		end

		-- Zone sign floating at the entrance of each biome.
		local signAnchor = part({
			Name = "ZoneSign",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(midX, Config.GetSeabedY(z0) + 30, z0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, model)
		billboard(signAnchor, string.format("%dm • %s", (i - 1) * W.ZoneHeight, zone.Name), zone.AccentColor, 0, UDim2.fromOffset(360, 70))

		task.wait()
	end
end

----------------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------------
function MapBuilder:Init(context)
	self.Context = context

	local existing = Workspace:FindFirstChild("SwimForEggsMap")
	if existing then
		-- Hand-built (or previously built) map: just make sure runtime folders exist.
		for _, name in ipairs({ "Spawns", "Eggs", "Monsters" }) do
			if not existing:FindFirstChild(name) then
				make("Folder", { Name = name }, existing)
			end
		end
		self.Map = existing
		return
	end

	if not W.BuildMapProcedurally then
		error("[MapBuilder] No SwimForEggsMap in Workspace and BuildMapProcedurally is false.")
	end

	local map = make("Model", { Name = "SwimForEggsMap" })
	local spawns = make("Folder", { Name = "Spawns" }, map)
	make("Folder", { Name = "Eggs" }, map)
	make("Folder", { Name = "Monsters" }, map)

	local okTerrain, terrainErr = pcall(buildTerrain)
	if not okTerrain then
		warn("[MapBuilder] Terrain build failed:", terrainErr)
	end

	local rng = Random.new(7)
	buildSafeZone(map)
	buildAquariumWalls(map, rng)
	buildBiomes(map, spawns)

	map.Parent = Workspace
	self.Map = map
	print("[MapBuilder] Map built.")
end

function MapBuilder:GetMap()
	return self.Map
end

return MapBuilder
