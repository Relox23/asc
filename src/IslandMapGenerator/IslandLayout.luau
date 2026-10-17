--[[
	IslandLayout
	Shared description of the island: size, where every region sits and where
	the landmarks are. The generator uses it to build the map and the client
	uses it (from ReplicatedStorage) to know which region the player is in.

	Change ISLAND_RADIUS to scale the whole map. Every landmark is placed as a
	fraction of the radius so the layout keeps its shape at any size.
]]

local Layout = {}

-- Size --------------------------------------------------------------------
Layout.ISLAND_RADIUS = 6000 -- coastline radius in studs (island is ~12,000 studs across)
Layout.WORLD_BORDER = math.floor(Layout.ISLAND_RADIUS * 1.23) -- invisible wall out at sea
Layout.OCEAN_EXTENT = math.ceil(Layout.ISLAND_RADIUS * 1.45 / 256) * 256 -- sea is drawn out to this half-width
Layout.SEA_LEVEL = 0
Layout.SEED = 20261017

-- Central capital ------------------------------------------------------------
Layout.HUB_RADIUS = 640 -- radius of the mesa the capital is built on
Layout.HUB_HEIGHT = 150 -- height of the mesa top
Layout.HUB_APRON = 760 -- sandy foothills around the mesa
Layout.RAMP_LENGTH = 560 -- grand causeways from the city gates down to each region
Layout.ROAD_WIDTH = 40

-- Coast -------------------------------------------------------------------
Layout.BEACH_WIDTH = 240 -- width of the sand strip around the whole island
Layout.ZONE_BLEND = 380 -- width of the soft border between two regions

-- Regions, in order around the island. Each owns a 72 degree slice.
Layout.ZONE_ORDER = { "Forest", "Snow", "Hollow", "Ruins", "Dunes" }

Layout.ZoneInfo = {
	Hub = { name = "Solkhar", subtitle = "Citadel of the Sun Throne" },
	Forest = { name = "Eloria Wildwood", subtitle = "Where the old magic still breathes" },
	Snow = { name = "Shirayuki Vale", subtitle = "A village asleep beneath the snow" },
	Hollow = { name = "The Hollow Expanse", subtitle = "Under a moon that never sets" },
	Ruins = { name = "Ashen Remnant", subtitle = "What is left of the old world" },
	Dunes = { name = "Sea of Whispering Dunes", subtitle = "The Starwarden Watchtower waits" },
	Coast = { name = "The Endless Shore", subtitle = "Nothing lies beyond the sea" },
}

local TAU = math.pi * 2
local FIRST_ANGLE = -math.pi / 2

Layout.ZoneAngle = {}
for i, id in ipairs(Layout.ZONE_ORDER) do
	local a = FIRST_ANGLE + (i - 1) * TAU / #Layout.ZONE_ORDER
	Layout.ZoneAngle[id] = math.atan2(math.sin(a), math.cos(a))
end
Layout.HALF_SECTOR = math.pi / #Layout.ZONE_ORDER

local function wrap(a)
	return (a + math.pi) % TAU - math.pi
end
Layout.wrapAngle = wrap

-- Point on the ground plane at an angle and distance from the island center.
function Layout.polar(angle, radius)
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Unit direction pointing from the center towards a region.
function Layout.zoneDirection(id)
	local a = Layout.ZoneAngle[id]
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- Landmarks -----------------------------------------------------------------
local R = Layout.ISLAND_RADIUS
local A = Layout.ZoneAngle
local polar = Layout.polar

Layout.Landmarks = {
	ForestSpawn = polar(A.Forest + 0.04, Layout.HUB_RADIUS + Layout.RAMP_LENGTH + 560),
	WorldTree = polar(A.Forest + 0.1, R * 0.6),
	ForestLake = polar(A.Forest - 0.24, R * 0.43),
	SnowVillage = polar(A.Snow - 0.13, R * 0.42),
	Temple = polar(A.Snow + 0.17, R * 0.72),
	Bastion = polar(A.Hollow + 0.02, R * 0.6),
	RuinsCenter = polar(A.Ruins, R * 0.55),
	Watchtower = polar(A.Dunes, R * 0.57),
}
Layout.Landmarks.SnowPond = Layout.Landmarks.SnowVillage
	+ (Layout.Landmarks.Temple - Layout.Landmarks.SnowVillage).Unit:Cross(Vector3.new(0, 1, 0)) * 330

-- Where each causeway from the capital reaches the ground.
function Layout.rampFoot(id)
	return polar(A[id], Layout.HUB_RADIUS + Layout.RAMP_LENGTH + 40)
end

-- The temple staircase climbs from here to the temple courtyard.
do
	local temple = Layout.Landmarks.Temple
	local toVillage = (Layout.Landmarks.SnowVillage - temple).Unit
	Layout.Landmarks.TempleStairsTop = temple + toVillage * 130
	Layout.Landmarks.TempleStairsFoot = temple + toVillage * 860
	-- the village street runs towards the stairs; the trail from the capital enters at its far end
	local street = (Layout.Landmarks.TempleStairsFoot - Layout.Landmarks.SnowVillage).Unit
	Layout.Landmarks.SnowVillageGate = Layout.Landmarks.SnowVillage - street * 175
end

-- Trails drawn into the terrain (material only).
Layout.Paths = {
	{
		zone = "Forest",
		material = "Ground",
		width = 16,
		points = { Layout.rampFoot("Forest"), Layout.Landmarks.ForestSpawn, Layout.Landmarks.WorldTree },
	},
	{
		zone = "Snow",
		material = "Ground",
		width = 14,
		points = {
			Layout.rampFoot("Snow"),
			Layout.Landmarks.SnowVillageGate,
			Layout.Landmarks.SnowVillage,
			Layout.Landmarks.TempleStairsFoot,
		},
	},
}

-- A handful of rare cottages hidden in the forest. Deterministic so the
-- terrain generator and the builder agree on where they are.
local cottageCache
function Layout.forestCottages()
	if cottageCache then
		return cottageCache
	end
	cottageCache = {}
	local rng = Random.new(Layout.SEED + 77)
	local avoid = { Layout.Landmarks.ForestSpawn, Layout.Landmarks.WorldTree, Layout.Landmarks.ForestLake }
	local tries = 0
	while #cottageCache < 7 and tries < 500 do
		tries += 1
		local a = A.Forest + rng:NextNumber(-0.85, 0.85) * Layout.HALF_SECTOR
		local p = polar(a, rng:NextNumber(R * 0.3, R * 0.86))
		local ok = true
		for _, q in ipairs(avoid) do
			if (p - q).Magnitude < 650 then
				ok = false
				break
			end
		end
		for _, q in ipairs(cottageCache) do
			if (p - q).Magnitude < 900 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(cottageCache, p)
		end
	end
	return cottageCache
end

-- Region lookup ---------------------------------------------------------------
local noise = math.noise

-- Border wobble so regions don't meet along straight lines.
function Layout.warpedAngle(x, z)
	return math.atan2(z, x) + 0.11 * noise(x / 1500 + 3.1, z / 1500 - 1.7, 0.5)
end

-- Which region a world position belongs to ("Hub", one of ZONE_ORDER, or "Coast").
function Layout.getZone(x, z)
	local d = math.sqrt(x * x + z * z)
	if d < Layout.HUB_RADIUS + 60 then
		return "Hub"
	end
	if d > R + 120 then
		return "Coast"
	end
	local theta = Layout.warpedAngle(x, z)
	local best, bestDist = nil, math.huge
	for _, id in ipairs(Layout.ZONE_ORDER) do
		local ad = math.abs(wrap(theta - A[id]))
		if ad < bestDist then
			best, bestDist = id, ad
		end
	end
	return best
end

return Layout
