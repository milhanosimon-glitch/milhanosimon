--[[
	GameBootstrap  (Script)
	Location: ServerScriptService > GameBootstrap

	The ONLY server Script. It:
	  1. Creates the RemoteEvents/RemoteFunctions the client uses.
	  2. Requires every ModuleScript in ServerScriptService > Services in a fixed order.
	  3. Calls :Init(context) on each (synchronous setup, map building),
	     then :Start() on each (connections and loops).
	  4. Spawns characters only once the map exists.

	Keeping one entry point avoids race conditions between scripts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Don't spawn anybody until the Safe Zone exists, or they fall into the void.
Players.CharacterAutoLoads = false

local ServicesFolder = ServerScriptService:WaitForChild("Services")

local LOAD_ORDER = {
	"DataService",
	"MapBuilder",
	"SwimOxygenService",
	"EggService",
	"MonsterService",
	"ShopService",
	"MonetizationService",
	"GameManager",
}

----------------------------------------------------------------------
-- Remotes (ReplicatedStorage > SwimForEggsRemotes)
----------------------------------------------------------------------
local function createRemotes()
	local folder = ReplicatedStorage:FindFirstChild("SwimForEggsRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SwimForEggsRemotes"
		folder.Parent = ReplicatedStorage
	end

	local function ensure(className, name)
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	end

	return {
		ShopAction = ensure("RemoteFunction", "ShopAction"), -- client -> server: buy/equip
		Notify = ensure("RemoteEvent", "Notify"), -- server -> client: toast messages
		Celebrate = ensure("RemoteEvent", "Celebrate"), -- server -> client: score popup
	}
end

local context = {
	Services = {},
	Remotes = createRemotes(),
}

----------------------------------------------------------------------
-- Require
----------------------------------------------------------------------
for _, name in ipairs(LOAD_ORDER) do
	local module = ServicesFolder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn(("[Bootstrap] Missing ModuleScript Services.%s"):format(name))
		continue
	end
	local ok, result = pcall(require, module)
	if ok then
		context.Services[name] = result
	else
		warn(("[Bootstrap] Failed to require %s: %s"):format(name, tostring(result)))
	end
end

----------------------------------------------------------------------
-- Init (in order, synchronous)
----------------------------------------------------------------------
for _, name in ipairs(LOAD_ORDER) do
	local service = context.Services[name]
	if service and type(service.Init) == "function" then
		local ok, err = pcall(service.Init, service, context)
		if not ok then
			warn(("[Bootstrap] %s:Init() failed: %s"):format(name, tostring(err)))
		end
	end
end

----------------------------------------------------------------------
-- Start (in order, each in its own thread)
----------------------------------------------------------------------
for _, name in ipairs(LOAD_ORDER) do
	local service = context.Services[name]
	if service and type(service.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn(("[Bootstrap] %s:Start() failed: %s"):format(name, tostring(err)))
			end
		end)
	end
end

----------------------------------------------------------------------
-- Map is ready -> allow spawning
----------------------------------------------------------------------
Players.CharacterAutoLoads = true
for _, player in ipairs(Players:GetPlayers()) do
	if not player.Character then
		task.spawn(function()
			local ok, err = pcall(player.LoadCharacter, player)
			if not ok then
				warn("[Bootstrap] LoadCharacter failed for", player.Name, err)
			end
		end)
	end
end
-- Players who join from now on spawn automatically (CharacterAutoLoads = true).

print("[Swim for Eggs] Server ready 🌊🥚")
