--[[
	MonsterFactory  (ModuleScript)
	Location: ServerScriptService > Services > MonsterFactory

	Builds the five Sea Monster models out of Parts so no external assets are needed.
	Every monster has:
	  * Root (anchored)   - MonsterService moves this with CFrame every frame.
	  * Welded detail parts (eyes, fins, jaws, tentacles) that follow the Root.
	  * Optional Segments (separate anchored parts) for eels/serpents; they trail the head.
	Forward direction = Root.CFrame.LookVector (-Z).

	Want custom meshes? Replace Build() output with your own Model that has a
	PrimaryPart named "Root" (anchored, everything else welded) and it just works.
]]

local MonsterFactory = {}

local function newPart(props, parent)
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function sphereMesh(p: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

-- Creates a detail part at root.CFrame * offset and welds it to the root.
local function attach(root: BasePart, model: Model, offset: CFrame, props)
	props.CFrame = root.CFrame * offset
	local p = newPart(props, model)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function addEyes(root: BasePart, model: Model, s: number, z: number, x: number, y: number, size: number, color: Color3)
	for _, side in ipairs({ -1, 1 }) do
		local eye = attach(root, model, CFrame.new(side * x * s, y * s, z * s), {
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size * s,
			Material = Enum.Material.Neon,
			Color = color,
		})
		attach(root, model, CFrame.new(side * (x * s + size * s * 0.3), y * s, z * s - size * s * 0.2), {
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size * s * 0.45,
			Color = Color3.new(0, 0, 0),
		})
		if side == 1 then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 14 * s
			light.Brightness = 2
			light.Parent = eye
		end
	end
end

local function addTeeth(root: BasePart, model: Model, s: number, z: number, y: number, width: number, count: number)
	for i = 1, count do
		local x = (-width / 2 + (width / (count - 1)) * (i - 1)) * s
		attach(root, model, CFrame.new(x, y * s, z * s) * CFrame.Angles(math.rad(180), 0, 0), {
			Name = "Tooth",
			Size = Vector3.new(0.4, 0.9, 0.4) * s,
			Color = Color3.fromRGB(250, 250, 240),
		})
	end
end

----------------------------------------------------------------------
-- Body plans
----------------------------------------------------------------------
local Builders = {}

Builders.Shark = function(root, model, cfg, s)
	root.Size = Vector3.new(6, 5, 16) * s
	root.Color = cfg.BodyColor
	sphereMesh(root)
	local belly = attach(root, model, CFrame.new(0, -0.9 * s, -0.5 * s), { Name = "Belly", Size = Vector3.new(5, 3, 13) * s, Color = cfg.BellyColor })
	sphereMesh(belly)
	attach(root, model, CFrame.new(0, 3 * s, 0.5 * s) * CFrame.Angles(math.rad(-20), 0, 0), {
		Name = "DorsalFin",
		Size = Vector3.new(0.6, 4, 3.5) * s,
		Color = cfg.BodyColor,
	})
	for _, side in ipairs({ -1, 1 }) do
		attach(root, model, CFrame.new(side * 3.5 * s, -1 * s, -1.5 * s) * CFrame.Angles(0, 0, math.rad(side * 25)), {
			Name = "PectoralFin",
			Size = Vector3.new(4, 0.5, 2.5) * s,
			Color = cfg.BodyColor,
		})
	end
	attach(root, model, CFrame.new(0, 1 * s, 9 * s) * CFrame.Angles(math.rad(25), 0, 0), {
		Name = "TailFin",
		Size = Vector3.new(0.6, 6, 2.5) * s,
		Color = cfg.BodyColor,
	})
	attach(root, model, CFrame.new(0, -1.2 * s, -6.8 * s), { Name = "Mouth", Size = Vector3.new(3.4, 0.8, 1.6) * s, Color = Color3.fromRGB(120, 20, 30) })
	addTeeth(root, model, s, -7.3, -0.7, 3, 6)
	addEyes(root, model, s, -5.2, 2.2, 0.8, 1, cfg.AccentColor)
end

Builders.Angler = function(root, model, cfg, s)
	root.Size = Vector3.new(9, 8, 10) * s
	root.Color = cfg.BodyColor
	sphereMesh(root)
	-- Huge lower jaw
	attach(root, model, CFrame.new(0, -2.5 * s, -3.5 * s), { Name = "Jaw", Size = Vector3.new(7, 2, 4) * s, Color = cfg.BellyColor })
	addTeeth(root, model, s, -5.6, -1.4, 6, 9)
	addTeeth(root, model, s, -5.4, -3.1, 5, 7)
	-- Lure: rod + glowing bulb in front of its face
	attach(root, model, CFrame.new(0, 5.5 * s, -3 * s) * CFrame.Angles(math.rad(-40), 0, 0), {
		Name = "LureRod",
		Size = Vector3.new(0.3, 6, 0.3) * s,
		Color = cfg.BodyColor,
	})
	local bulb = attach(root, model, CFrame.new(0, 7.5 * s, -6 * s), {
		Name = "LureBulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.6 * s,
		Material = Enum.Material.Neon,
		Color = cfg.AccentColor,
	})
	local light = Instance.new("PointLight")
	light.Color = cfg.AccentColor
	light.Range = 30
	light.Brightness = 4
	light.Parent = bulb
	attach(root, model, CFrame.new(0, 0, 5.5 * s) * CFrame.Angles(0, 0, 0), {
		Name = "TailFin",
		Size = Vector3.new(0.5, 6, 3) * s,
		Color = cfg.BodyColor,
	})
	addEyes(root, model, s, -3, 2.6, 2.6, 0.9, Color3.fromRGB(255, 255, 255))
end

Builders.Kraken = function(root, model, cfg, s)
	-- Mantle points backwards/up; tentacles trail behind while it swims forward.
	root.Size = Vector3.new(8, 8, 14) * s
	root.Color = cfg.BodyColor
	sphereMesh(root)
	for i = 1, 6 do
		local angle = math.rad(i * 60)
		attach(root, model, CFrame.new(math.cos(angle) * 3.2 * s, math.sin(angle) * 3.2 * s, 0) * CFrame.new(0, 0, -2 * s), {
			Name = "GlowSpot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2 * s,
			Material = Enum.Material.Neon,
			Color = cfg.AccentColor,
		})
	end
	for i = 1, 8 do
		local angle = math.rad(i * 45)
		local offset = Vector3.new(math.cos(angle) * 2.6, math.sin(angle) * 2.6, 0) * s
		for seg = 1, 4 do
			attach(
				root,
				model,
				CFrame.new(offset * (1 + seg * 0.25)) * CFrame.new(0, 0, (6 + seg * 3.2) * s),
				{
					Name = "Tentacle",
					Size = Vector3.new(1.3 - seg * 0.2, 1.3 - seg * 0.2, 3.4) * s,
					Color = if seg % 2 == 0 then cfg.BellyColor else cfg.BodyColor,
				}
			)
		end
	end
	addEyes(root, model, s, -4.5, 3.6, 1.5, 1.6, cfg.AccentColor)
end

local function buildSegmented(root, model, cfg, s, headSize: Vector3)
	root.Size = headSize * s
	root.Color = cfg.BodyColor
	sphereMesh(root)
	attach(root, model, CFrame.new(0, -0.9 * s, -headSize.Z * 0.35 * s), {
		Name = "Jaw",
		Size = Vector3.new(headSize.X * 0.8, 1, headSize.Z * 0.5) * s,
		Color = cfg.BellyColor,
	})
	addTeeth(root, model, s, -headSize.Z * 0.5, -0.4, headSize.X * 0.6, 6)
	addEyes(root, model, s, -headSize.Z * 0.25, headSize.X * 0.38, headSize.Y * 0.25, 0.9, cfg.AccentColor)

	local segments = {}
	local count = cfg.Segments or 8
	for i = 1, count do
		local t = i / count
		local size = Vector3.new(headSize.X * (1 - t * 0.6), headSize.Y * (1 - t * 0.6), headSize.Z * 0.7) * s
		local seg = newPart({
			Name = "Segment" .. i,
			Anchored = true,
			Size = size,
			Color = if i % 2 == 0 then cfg.BodyColor else cfg.BellyColor,
			CFrame = root.CFrame * CFrame.new(0, 0, (headSize.Z * 0.5 + i * headSize.Z * 0.6) * s),
		}, model)
		sphereMesh(seg)
		-- Neon stripe on every other segment (spots for the eel, lava cracks for the serpent)
		if i % 2 == 1 then
			local stripe = newPart({
				Name = "Stripe",
				Anchored = false,
				Size = Vector3.new(size.X * 0.4, size.Y * 0.25, size.Z * 0.6),
				Material = Enum.Material.Neon,
				Color = cfg.AccentColor,
				CFrame = seg.CFrame * CFrame.new(0, size.Y * 0.4, 0),
			}, model)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = seg
			weld.Part1 = stripe
			weld.Parent = stripe
		end
		table.insert(segments, seg)
	end
	return segments, headSize.Z * 0.6 * s
end

Builders.Eel = function(root, model, cfg, s)
	return buildSegmented(root, model, cfg, s, Vector3.new(3.5, 3.5, 6))
end

Builders.Serpent = function(root, model, cfg, s)
	local segments, spacing = buildSegmented(root, model, cfg, s, Vector3.new(5, 4.5, 8))
	-- Horns + embers
	for _, side in ipairs({ -1, 1 }) do
		attach(root, model, CFrame.new(side * 2 * s, 2.5 * s, 1 * s) * CFrame.Angles(math.rad(-35), 0, math.rad(side * -20)), {
			Name = "Horn",
			Size = Vector3.new(0.7, 4, 0.7) * s,
			Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(30, 20, 20),
		})
	end
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(cfg.AccentColor)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.8, 0)
	embers.Lifetime = NumberRange.new(0.5, 1)
	embers.Rate = 25
	embers.Speed = NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Parent = root
	return segments, spacing
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
-- Returns { Model, Root, Segments, SegmentSpacing, Label }
function MonsterFactory.Build(cfg, zone, homeCFrame: CFrame, parent: Instance)
	local s = cfg.Scale or 1
	local model = Instance.new("Model")
	model.Name = cfg.Name

	local root = newPart({
		Name = "Root",
		Anchored = true,
		CFrame = homeCFrame,
		Size = Vector3.new(6, 6, 6),
	}, model)
	model.PrimaryPart = root

	local builder = Builders[cfg.Kind] or Builders.Shark
	local segments, spacing = builder(root, model, cfg, s)

	-- Name tag + state (Patrolling / HUNTING)
	local gui = Instance.new("BillboardGui")
	gui.Name = "MonsterLabel"
	gui.Size = UDim2.fromOffset(260, 56)
	gui.StudsOffset = Vector3.new(0, 7 * s, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextColor3 = zone.AccentColor
	label.Text = cfg.Name .. "\n💤 Guarding"
	label.Parent = gui
	gui.Parent = root

	-- Burst played when it aggros.
	local roar = Instance.new("ParticleEmitter")
	roar.Name = "RoarBurst"
	roar.Enabled = false
	roar.Color = ColorSequence.new(Color3.fromRGB(255, 60, 60))
	roar.LightEmission = 1
	roar.Size = NumberSequence.new(2 * s, 0)
	roar.Lifetime = NumberRange.new(0.4, 0.8)
	roar.Speed = NumberRange.new(15, 25)
	roar.SpreadAngle = Vector2.new(180, 180)
	roar.Parent = root

	model.Parent = parent
	return {
		Model = model,
		Root = root,
		Segments = segments or {},
		SegmentSpacing = spacing or 0,
		Label = label,
	}
end

return MonsterFactory
