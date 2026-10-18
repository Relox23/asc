--[[
	IslandMapGenerator
	Builds the whole island map inside Roblox Studio.

	How to use (Studio, edit mode, NOT while playtesting):
	  1. Put this ModuleScript in ServerStorage (Insert from File... -> IslandMapGenerator.rbxmx)
	  2. Open View > Command Bar and run:
	         require(game.ServerStorage.IslandMapGenerator).Build()
	  3. Wait for "[IslandMap] Done" in the Output window (a few minutes).

	For the detailed buildings and trees, first import assets/IslandAssets.fbx
	(Home > Import 3D) and keep the imported model named "IslandAssets".

	Rebuild only some parts:
	         require(game.ServerStorage.IslandMapGenerator).Build({ "Snow", "Atmosphere" })
	Remove everything it made:
	         require(game.ServerStorage.IslandMapGenerator).Clear()
]]

local Config = require(script.Config)
local Layout = require(script.IslandLayout)
local Landscape = require(script.Landscape)
local TerrainWriter = require(script.TerrainWriter)
local Atmosphere = require(script.Atmosphere)
local Util = require(script.Util)
local AssetLibrary = require(script.AssetLibrary)

local Generator = {}

local ZONE_STEPS = { "Hub", "Forest", "Snow", "Hollow", "Dunes", "Ruins", "Coast", "Sky" }

local function islandFolder()
	return Util.folder(workspace, "Island")
end

local function removeDefaults()
	if not Config.REMOVE_DEFAULT_BASEPLATE then
		return
	end
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local obj = workspace:FindFirstChild(name)
		if obj and obj:IsA("BasePart") then
			obj:Destroy()
		end
	end
end

local function setupStreaming()
	if not Config.STREAMING then
		return
	end
	local ok, err = pcall(function()
		workspace.StreamingEnabled = true
	end)
	-- newer Studio versions renamed or removed the radius settings; they are optional
	pcall(function()
		workspace.StreamingMinRadius = 256
	end)
	pcall(function()
		workspace.StreamingTargetRadius = 2048
	end)
	if not ok then
		warn("[IslandMap] Could not enable streaming automatically (" .. tostring(err) .. "). Turn on Workspace.StreamingEnabled by hand.")
	end
end

function Generator.Clear()
	local island = workspace:FindFirstChild("Island")
	if island then
		island:Destroy()
	end
	workspace.Terrain:Clear()
	Util.log("Cleared the island")
end

-- steps: optional list like { "Terrain", "Snow" }; nil builds everything enabled in Config.Build
function Generator.Build(steps)
	local started = os.clock()
	local wanted = {}
	if steps then
		for _, s in ipairs(steps) do
			wanted[s] = true
		end
	else
		for name, enabled in pairs(Config.Build) do
			wanted[name] = enabled
		end
	end

	Util.log(string.format("Building island (radius %d studs)...", Layout.ISLAND_RADIUS))
	AssetLibrary.reset() -- pick up a freshly imported IslandAssets model
	if not AssetLibrary.available() then
		Util.log("No " .. AssetLibrary.IMPORT_NAME .. " model found; building everything from parts (see README to import the detailed meshes)")
	end
	Landscape.init()
	removeDefaults()
	local island = islandFolder()

	if wanted.Terrain then
		if Config.CLEAR_EXISTING then
			workspace.Terrain:Clear()
		end
		TerrainWriter.Generate()
	end

	local failures = {}
	for i, name in ipairs(ZONE_STEPS) do
		if wanted[name] then
			if Config.CLEAR_EXISTING then
				local old = island:FindFirstChild(name)
				if old then
					old:Destroy()
				end
			end
			local folder = Util.folder(island, name)
			local rng = Random.new(Layout.SEED + i * 1000)
			local ok, err = xpcall(function()
				require(script.Zones[name]).Build(folder, rng)
			end, debug.traceback)
			if not ok then
				table.insert(failures, name)
				warn("[IslandMap] " .. name .. " failed:\n" .. tostring(err))
			end
			task.wait()
		end
	end

	if wanted.Atmosphere then
		Atmosphere.Build()
	end
	setupStreaming()

	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint("Island map generated")
	end)

	local parts = 0
	for _, d in ipairs(island:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	if #failures > 0 then
		warn("[IslandMap] Finished with errors in: " .. table.concat(failures, ", "))
	end
	Util.log(string.format("Done in %.0fs. %d parts. Press Play to explore!", os.clock() - started, parts))
end

return Generator
