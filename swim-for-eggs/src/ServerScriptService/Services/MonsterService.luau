--[[
	MonsterService  (ModuleScript)
	Location: ServerScriptService > Services > MonsterService

	Sea Monster AI. One guardian per depth zone.

	State machine:
	  Patrol  -> lazily swims between random waypoints around its home (the eggs).
	  Roar    -> an egg from its zone was stolen: freezes for AggroRoarTime, faces the
	             thief, bursts red particles (gives the thief a head start).
	  Chase   -> 3D steering pursuit of the carrier (predicts where they are going).
	  Return  -> target gone / caught / scored / left the water: swims back home.

	Why not PathfindingService? It only plans for walking agents on the ground.
	Open water is a 3D volume, so we use steering behaviours instead:
	  * Seek with velocity prediction (LeadTime)
	  * Raycast "whiskers" for obstacle avoidance (rocks, coral, chimneys, terrain)
	  * Hard clamps so monsters stay inside the water and above the seabed
	  * Smooth turning (TurnRate) + tail wiggle for a swimming look

	Catch: distance check every frame (more reliable than .Touched for anchored,
	CFrame-driven parts). Caught -> egg returns to pedestal, player dies,
	monster swims back to patrol.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SwimForEggsShared")
local Config = require(Shared:WaitForChild("Config"))

local W = Config.World

local MonsterService = {}

local monsters = {} -- array of monster state tables
local monstersByZone = {} -- [zoneIndex] = monster

local AVOID_ANGLES = { -- (pitch, yaw) candidates tried when the path ahead is blocked
	{ 35, 0 },
	{ 0, 40 },
	{ 0, -40 },
	{ -30, 0 },
	{ 35, 50 },
	{ 35, -50 },
	{ 70, 0 },
	{ 0, 85 },
	{ 0, -85 },
}
local TARGET_SCAN_INTERVAL = 0.2
local FILTER_REFRESH_INTERVAL = 1

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- ignore kelp, decor, etc. that players can swim through
rayParams.IgnoreWater = true

----------------------------------------------------------------------
-- Math helpers
----------------------------------------------------------------------
local function safeLookAt(pos: Vector3, dir: Vector3): CFrame
	if dir.Magnitude < 1e-4 then
		return CFrame.new(pos)
	end
	dir = dir.Unit
	local up = if math.abs(dir.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(pos, pos + dir, up)
end

-- Keeps a monster inside the ocean volume and above the seabed.
local function clampToWater(pos: Vector3, radius: number): Vector3
	local x = math.clamp(pos.X, W.OceanMinX + radius, W.OceanMaxX - radius)
	local z = math.clamp(pos.Z, W.OceanStartZ + radius, W.OceanEndZ - radius)
	local floorY = Config.GetSeabedY(z) + radius
	local ceilY = math.max(floorY, W.SurfaceY - radius * 0.6 - 1)
	local y = math.clamp(pos.Y, floorY, ceilY)
	return Vector3.new(x, y, z)
end

local function getRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root :: BasePart, humanoid
	end
	return nil, nil
end

----------------------------------------------------------------------
-- State changes
----------------------------------------------------------------------
function MonsterService:_setLabel(m, text: string, color: Color3?)
	if m.Label then
		m.Label.Text = m.Config.Name .. "\n" .. text
		m.Label.TextColor3 = color or Config.Zones[m.ZoneIndex].AccentColor
	end
end

function MonsterService:_clearChaseFlag(player: Player?, m)
	if player and player.Parent and player:GetAttribute("ChasedBy") == m.Config.Name then
		player:SetAttribute("ChasedBy", nil)
	end
end

function MonsterService:_aggro(m, player: Player, withRoar: boolean)
	if m.Target == player and (m.State == "Chase" or m.State == "Roar") then
		return
	end
	self:_clearChaseFlag(m.Target, m)
	m.Target = player
	player:SetAttribute("ChasedBy", m.Config.Name)

	if withRoar then
		m.State = "Roar"
		m.RoarUntil = os.clock() + m.Config.AggroRoarTime
		local burst = m.Root:FindFirstChild("RoarBurst")
		if burst then
			burst:Emit(40)
		end
		self.Context.Remotes.Notify:FireClient(player, string.format("⚠️ %s woke up! SWIM!", m.Config.Name), "Danger")
	else
		m.State = "Chase"
	end
	self:_setLabel(m, "😡 HUNTING", Color3.fromRGB(255, 60, 60))
end

function MonsterService:_goHome(m)
	self:_clearChaseFlag(m.Target, m)
	m.Target = nil
	m.State = "Return"
	self:_setLabel(m, "↩️ Returning")
end

-- Picks the nearest carrier of this zone's eggs who is still in the water.
function MonsterService:_findTarget(m): Player?
	local best, bestDist = nil, math.huge
	for _, player in ipairs(self.Services.EggService:GetCarriersForZone(m.ZoneIndex)) do
		local root = getRoot(player)
		if root and Config.IsInWater(root.Position) then
			local dist = (root.Position - m.Position).Magnitude
			if dist < bestDist then
				best, bestDist = player, dist
			end
		end
	end
	return best
end

function MonsterService:_retarget(m)
	local nextTarget = self:_findTarget(m)
	if nextTarget then
		self:_aggro(m, nextTarget, false)
	else
		self:_goHome(m)
	end
end

-- Drops aggro on a player (called by GameManager after scoring).
function MonsterService:DropAggroFor(player: Player)
	for _, m in ipairs(monsters) do
		if m.Target == player then
			self:_retarget(m)
		end
	end
	if player.Parent then
		player:SetAttribute("ChasedBy", nil)
	end
end

function MonsterService:_catch(m, player: Player, humanoid: Humanoid)
	-- Change state FIRST so the EggCarrierLost signal doesn't double-handle us.
	self:_goHome(m)
	player:SetAttribute("LastDeathCause", m.Config.Name)
	self.Services.EggService:ReclaimFromPlayer(player)
	self.Context.Remotes.Notify:FireClient(player, string.format("🦷 %s caught you and took back its egg!", m.Config.Name), "Danger")
	humanoid.Health = 0
end

----------------------------------------------------------------------
-- Steering
----------------------------------------------------------------------
function MonsterService:_avoid(m, desiredDir: Vector3): Vector3
	local lookAhead = m.AvoidDistance
	local origin = m.Position
	local hit = Workspace:Raycast(origin, desiredDir * lookAhead, rayParams)
	if not hit then
		return desiredDir
	end

	local baseCf = safeLookAt(origin, desiredDir)
	local best, bestScore = nil, -math.huge
	for _, angles in ipairs(AVOID_ANGLES) do
		local candidate = (baseCf * CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), 0)).LookVector
		if not Workspace:Raycast(origin, candidate * lookAhead, rayParams) then
			local score = candidate:Dot(desiredDir)
			if score > bestScore then
				best, bestScore = candidate, score
			end
		end
	end
	if best then
		return best
	end

	-- Fully boxed in: slide along the surface we hit.
	local normal = hit.Normal
	local slide = desiredDir - normal * desiredDir:Dot(normal)
	if slide.Magnitude < 0.05 then
		return normal
	end
	return (slide.Unit + normal * 0.5).Unit
end

function MonsterService:_newWaypoint(m)
	local r = m.Config.PatrolRadius
	local angle = math.random() * math.pi * 2
	local dist = r * (0.3 + math.random() * 0.7)
	local offset = Vector3.new(math.cos(angle) * dist, (math.random() - 0.5) * 20, math.sin(angle) * dist)
	m.Waypoint = clampToWater(m.Home + offset, m.Radius)
	m.WaypointDeadline = os.clock() + 10
end

function MonsterService:_moveAndRender(m, desired: Vector3, speed: number, dt: number, allowOvershoot: boolean)
	local distance = desired.Magnitude
	local dir = if distance > 0.05 then desired / distance else m.Dir
	dir = self:_avoid(m, dir)

	-- Smooth turning
	local alpha = math.clamp(m.Config.TurnRate * dt, 0, 1)
	local blended = m.Dir:Lerp(dir, alpha)
	m.Dir = if blended.Magnitude > 1e-3 then blended.Unit else dir

	local step = speed * dt
	if not allowOvershoot then
		step = math.min(step, distance)
	end
	m.Position = clampToWater(m.Position + m.Dir * step, m.Radius)

	-- Tail wiggle: faster when chasing
	local wiggleSpeed = if m.State == "Chase" then 14 else 6
	local wiggle = math.sin(os.clock() * wiggleSpeed + m.Phase) * math.rad(if m.State == "Chase" then 12 else 6)
	m.Root.CFrame = safeLookAt(m.Position, m.Dir) * CFrame.Angles(0, wiggle, 0)

	-- Segmented bodies (eel / serpent) trail the head.
	if #m.Segments > 0 then
		local prev = m.Root.Position + m.Root.CFrame.LookVector * -m.SegmentSpacing * 0.5
		for _, seg in ipairs(m.Segments) do
			local offset = seg.Position - prev
			if offset.Magnitude < 1e-3 then
				offset = -m.Dir
			end
			local newPos = prev + offset.Unit * m.SegmentSpacing
			seg.CFrame = safeLookAt(newPos, prev - newPos)
			prev = newPos
		end
	end
end

function MonsterService:_isTouching(m, position: Vector3): boolean
	local cfg = m.Config
	if (m.Root.Position - position).Magnitude <= cfg.KillRadius then
		return true
	end
	-- The long body of eels/serpents is also deadly.
	local segRadius = cfg.KillRadius * 0.6
	for _, seg in ipairs(m.Segments) do
		if (seg.Position - position).Magnitude <= segRadius then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------
function MonsterService:_step(m, dt: number)
	local cfg = m.Config
	local now = os.clock()

	-- Validate current target
	if m.State == "Chase" or m.State == "Roar" then
		local player = m.Target
		local root, humanoid = nil, nil
		if player and player.Parent then
			root, humanoid = getRoot(player)
		end
		local record = player and self.Services.EggService:GetCarriedEgg(player)
		if not root or not humanoid or not record or record.ZoneIndex ~= m.ZoneIndex then
			self:_retarget(m)
		elseif not Config.IsInWater(root.Position) then
			-- Leash: thief climbed out of the ocean (Safe Zone). Give up.
			self:_retarget(m)
		else
			if m.State == "Roar" then
				-- Face the thief, shake in place.
				local toTarget = root.Position - m.Position
				if toTarget.Magnitude > 1e-3 then
					local blended = m.Dir:Lerp(toTarget.Unit, math.clamp(cfg.TurnRate * 2 * dt, 0, 1))
					if blended.Magnitude > 1e-3 then
						m.Dir = blended.Unit
					end
				end
				local shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.6
				m.Root.CFrame = safeLookAt(m.Position + shake, m.Dir)
				if now >= m.RoarUntil then
					m.State = "Chase"
				end
				return
			end

			-- Chase: aim where the player WILL be.
			local velocity = root.AssemblyLinearVelocity
			local lead = velocity * cfg.LeadTime
			if lead.Magnitude > 25 then
				lead = lead.Unit * 25
			end
			local aimPoint = root.Position + lead
			self:_moveAndRender(m, aimPoint - m.Position, cfg.ChaseSpeed, dt, true)

			if self:_isTouching(m, root.Position) then
				self:_catch(m, player, humanoid)
			end
			return
		end
	end

	-- Not chasing: look for thieves a few times per second.
	if now >= m.NextScan then
		m.NextScan = now + TARGET_SCAN_INTERVAL
		local target = self:_findTarget(m)
		if target then
			self:_aggro(m, target, false)
			return
		end
	end

	if m.State == "Return" then
		local toHome = m.Home - m.Position
		if toHome.Magnitude < 6 then
			m.State = "Patrol"
			self:_setLabel(m, "💤 Guarding")
			self:_newWaypoint(m)
		else
			self:_moveAndRender(m, toHome, cfg.ReturnSpeed, dt, false)
		end
		return
	end

	-- Patrol
	if not m.Waypoint or (m.Waypoint - m.Position).Magnitude < 5 or now > m.WaypointDeadline then
		self:_newWaypoint(m)
	end
	self:_moveAndRender(m, m.Waypoint - m.Position, cfg.PatrolSpeed, dt, false)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function MonsterService:Init(context)
	self.Context = context
	self.Services = context.Services
end

function MonsterService:Start()
	local MonsterFactory = require(script.Parent:WaitForChild("MonsterFactory"))
	local map = self.Services.MapBuilder:GetMap()
	local spawns = map:WaitForChild("Spawns")
	local folder = map:WaitForChild("Monsters")

	for i, zone in ipairs(Config.Zones) do
		local home = spawns:FindFirstChild("MonsterHome_" .. i)
		if not home then
			warn("[MonsterService] Missing Spawns.MonsterHome_" .. i .. " - zone has no guardian.")
			continue
		end
		local ok, built = pcall(MonsterFactory.Build, zone.Monster, zone, home.CFrame, folder)
		if not ok then
			warn("[MonsterService] Failed to build", zone.Monster.Name, built)
			continue
		end
		local scale = zone.Monster.Scale or 1
		local m = {
			ZoneIndex = i,
			Config = zone.Monster,
			Model = built.Model,
			Root = built.Root,
			Segments = built.Segments,
			SegmentSpacing = built.SegmentSpacing,
			Label = built.Label,
			Home = home.Position,
			Position = home.Position,
			Dir = Vector3.new(0, 0, -1),
			Radius = 4 * scale,
			AvoidDistance = 12 * scale,
			State = "Patrol",
			Target = nil,
			RoarUntil = 0,
			NextScan = 0,
			Waypoint = nil,
			WaypointDeadline = 0,
			Phase = math.random() * 10,
		}
		table.insert(monsters, m)
		monstersByZone[i] = m
	end

	-- Raycasts ignore monsters, eggs and every character.
	local function refreshFilter()
		local list = { folder, map:FindFirstChild("Eggs") }
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(list, player.Character)
			end
		end
		rayParams.FilterDescendantsInstances = list
	end
	refreshFilter()

	-- INSTANT aggro the moment an egg is stolen.
	self.Services.EggService.EggStolen:Connect(function(player, record)
		local m = monstersByZone[record.ZoneIndex]
		if m then
			self:_aggro(m, player, true)
		end
	end)

	-- Carrier lost the egg (drowned, scored, left...) -> retarget or go home.
	self.Services.EggService.EggCarrierLost:Connect(function(player, record, _reason)
		local m = monstersByZone[record.ZoneIndex]
		if m and m.Target == player then
			self:_retarget(m)
		end
		if player.Parent and player:GetAttribute("ChasedBy") == (m and m.Config.Name) then
			player:SetAttribute("ChasedBy", nil)
		end
	end)

	local filterTimer = 0
	local errorCooldown = 0
	RunService.Heartbeat:Connect(function(dt)
		filterTimer += dt
		if filterTimer >= FILTER_REFRESH_INTERVAL then
			filterTimer = 0
			refreshFilter()
		end
		dt = math.min(dt, 0.1) -- avoid teleport-y jumps after a server hitch
		for _, m in ipairs(monsters) do
			local ok, err = pcall(self._step, self, m, dt)
			if not ok and os.clock() > errorCooldown then
				errorCooldown = os.clock() + 5
				warn("[MonsterService] step error:", err)
			end
		end
	end)
end

return MonsterService
