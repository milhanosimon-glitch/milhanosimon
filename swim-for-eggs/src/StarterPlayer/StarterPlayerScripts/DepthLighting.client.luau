--[[
	DepthLighting  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > DepthLighting

	Smoothly tweens Lighting, Atmosphere, ColorCorrection and the Terrain water
	colour as the local player's Y drops through each 100-stud biome.

	All changes are LOCAL (only this player sees them), so every player gets the
	lighting of their own depth.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("SwimForEggsShared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local TWEEN_INFO = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local CHECK_INTERVAL = 0.15

-- Ensure the post-processing objects exist (created locally).
local function ensure(className: string, name: string, parent: Instance)
	local obj = parent:FindFirstChild(name)
	if not obj or not obj:IsA(className) then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = parent
	end
	return obj
end

-- Lighting only supports ONE Atmosphere; reuse an existing one if present.
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or ensure("Atmosphere", "DepthAtmosphere", Lighting)
local colorCorrection = ensure("ColorCorrectionEffect", "DepthColorCorrection", Lighting)
local bloom = ensure("BloomEffect", "DepthBloom", Lighting)
bloom.Intensity = 0.6
bloom.Size = 30
bloom.Threshold = 1.6 -- makes Neon corals, crystals and monster eyes glow

local terrain = Workspace.Terrain
local activeTweens = {}
local currentKey = nil

local function cancelTweens()
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end
	table.clear(activeTweens)
end

local function play(instance: Instance, goals)
	local ok, tween = pcall(TweenService.Create, TweenService, instance, TWEEN_INFO, goals)
	if ok then
		tween:Play()
		table.insert(activeTweens, tween)
	else
		warn("[DepthLighting] Tween failed:", tween)
	end
end

local function applyPreset(preset)
	cancelTweens()
	play(Lighting, {
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
		Brightness = preset.Brightness,
	})
	play(atmosphere, {
		Density = preset.AtmosphereDensity,
		Color = preset.AtmosphereColor,
		Decay = preset.AtmosphereDecay,
		Haze = preset.AtmosphereHaze,
	})
	play(colorCorrection, {
		TintColor = preset.TintColor,
		Saturation = preset.Saturation,
		Contrast = preset.Contrast,
	})
	play(terrain, { WaterColor = preset.WaterColor })
end

-- Returns a key ("Surface" or zone index) and its preset.
local function getPresetForPosition(position: Vector3)
	if not Config.IsUnderwater(position) then
		return "Surface", Config.SurfaceLighting
	end
	local depth = Config.GetDepth(position.Y)
	local index = Config.GetZoneIndexForDepth(depth)
	return index, Config.Zones[index].Lighting
end

-- Instant apply on start so the first frame isn't wrong.
do
	local preset = Config.SurfaceLighting
	Lighting.Ambient = preset.Ambient
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.Brightness = preset.Brightness
	atmosphere.Density = preset.AtmosphereDensity
	atmosphere.Color = preset.AtmosphereColor
	atmosphere.Decay = preset.AtmosphereDecay
	atmosphere.Haze = preset.AtmosphereHaze
	colorCorrection.TintColor = preset.TintColor
	colorCorrection.Saturation = preset.Saturation
	colorCorrection.Contrast = preset.Contrast
	currentKey = "Surface"
end

local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	if elapsed < CHECK_INTERVAL then
		return
	end
	elapsed = 0

	-- Use the camera so lighting matches what the player actually sees
	-- (falls back to the head if the camera is somewhere odd, e.g. main menu).
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local position
	if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		position = camera.CFrame.Position
	elseif head then
		position = head.Position
	else
		return
	end

	local key, preset = getPresetForPosition(position)
	if key ~= currentKey then
		currentKey = key
		applyPreset(preset)
	end
end)
