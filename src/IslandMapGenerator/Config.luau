--[[
	Config
	Settings for the map generator. Change these before running Build().
	Island size and region layout live in IslandLayout.
]]

local Config = {}

-- Which parts of the map to build. Turn one off to rebuild only the rest.
Config.Build = {
	Terrain = true,
	Hub = true,
	Forest = true,
	Snow = true,
	Hollow = true,
	Dunes = true,
	Ruins = true,
	Coast = true,
	Atmosphere = true,
}

-- Where players spawn: "Forest" (the Eloria Wildwood clearing) or "Hub" (the capital).
-- Both spawn pads are always built; this picks which one is enabled.
Config.PLAYER_START = "Forest"

-- Multiplies how many trees, bushes and rocks are scattered.
-- 1 = full forests (~150k parts in total). Lower it on weaker PCs or for mobile.
Config.FOLIAGE_DENSITY = 1

-- Delete the existing terrain and the previously generated map before building.
Config.CLEAR_EXISTING = true

-- Remove the default "Baseplate" and "SpawnLocation" from a fresh place.
Config.REMOVE_DEFAULT_BASEPLATE = true

-- Turn on instance streaming. Strongly recommended for a map this size.
Config.STREAMING = true

-- Keep Studio responsive: yield after this many seconds of work.
Config.YIELD_EVERY = 0.12

-- Print progress to the Output window.
Config.VERBOSE = true

return Config
