--[[
	Sky
	Puffy clouds placed by hand-picked rules: a sea of clouds wrapping the
	watchtower just below its crown, drifting clouds high over the island,
	mist clinging to the temple mountain and the snowy valleys, morning mist
	over Mirror Lake and heavy ash clouds over the ruined city.
	The Hollow Expanse is left clear so its moon and stars stay visible.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local Util = require(script.Parent.Parent.Util)

local Sky = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local TAU = math.pi * 2
local L = Layout.Landmarks

local WHITE = rgb(252, 252, 255)
local ASH = rgb(78, 74, 76)

-- One cloud: a flat base with rounder puffs piled on top.
local function cloud(parent, rng, center, size, color, transparency)
	local m = Util.model(parent, "Cloud")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local cf = CFrame.new(center) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	local opts = { collide = false, shadow = false, transparency = transparency }
	local base = Util.ellipsoid(m, cf * CFrame.new(0, -size * 0.12, 0), Vector3.new(size * 3.2, size * 0.55, size * 1.9), color, M.SmoothPlastic, opts)
	base.CanQuery = false
	for _ = 1, rng:NextInteger(6, 10) do
		local off = Vector3.new(rng:NextNumber(-1.3, 1.3), rng:NextNumber(-0.05, 0.4), rng:NextNumber(-0.7, 0.7)) * size
		local k = rng:NextNumber(0.5, 1) * size
		local puff = Util.ellipsoid(m, cf * CFrame.new(off), Vector3.new(k * 2, k * 1.3, k * 2 * rng:NextNumber(0.8, 1.1)), color, M.SmoothPlastic, opts)
		puff.CanQuery = false
	end
	return m
end
Sky.cloud = cloud

local function around(rng, center, minR, maxR)
	local a = rng:NextNumber(0, TAU)
	local r = rng:NextNumber(minR, maxR)
	return Vector3.new(center.X + math.cos(a) * r, 0, center.Z + math.sin(a) * r)
end

function Sky.Build(folder, rng)
	Util.log("Adding clouds...")
	local count = 0

	-- sea of clouds around the watchtower, just under the crown
	local tower = Util.model(folder, "WatchtowerCloudSea")
	for _ = 1, 24 do
		local p = around(rng, L.Watchtower, 170, 820)
		cloud(tower, rng, p + Vector3.new(0, Landscape.WatchtowerHeight + rng:NextNumber(540, 625), 0), rng:NextNumber(45, 90), WHITE, 0.08)
		count += 1
	end

	-- high drifting clouds over the island (none over the Hollow's night sky)
	local high = Util.model(folder, "HighClouds")
	local R = Layout.ISLAND_RADIUS
	local placed = 0
	for _ = 1, 200 do
		if placed >= 46 then
			break
		end
		local p = around(rng, Vector3.zero, 0, R * 1.02)
		if Layout.getZone(p.X, p.Z) ~= "Hollow" and (p - L.Watchtower).Magnitude > 900 then
			cloud(high, rng, p + Vector3.new(0, rng:NextNumber(780, 1100), 0), rng:NextNumber(60, 120), WHITE, 0.1)
			placed += 1
		end
	end
	count += placed

	-- mist wrapped around the temple mountain
	local temple = Util.model(folder, "TempleMist")
	for _ = 1, 10 do
		local p = around(rng, L.Temple, 300, 580)
		local h = math.max(Landscape.heightAt(p.X, p.Z), Landscape.TempleHeight - 110)
		cloud(temple, rng, p + Vector3.new(0, h + rng:NextNumber(10, 40), 0), rng:NextNumber(40, 70), WHITE, 0.25)
		count += 1
	end

	-- low clouds drifting through the snowy valleys
	local valley = Util.model(folder, "ValleyMist")
	local valleyPlaced = 0
	for _ = 1, 80 do
		if valleyPlaced >= 8 then
			break
		end
		local a = Layout.ZoneAngle.Snow + rng:NextNumber(-0.8, 0.8) * Layout.HALF_SECTOR
		local p = Layout.polar(a, rng:NextNumber(R * 0.35, R * 0.85))
		if (p - L.SnowVillage).Magnitude > 500 and (p - L.Temple).Magnitude > 700 then
			cloud(valley, rng, p + Vector3.new(0, Landscape.heightAt(p.X, p.Z) + rng:NextNumber(70, 130), 0), rng:NextNumber(45, 80), WHITE, 0.3)
			valleyPlaced += 1
		end
	end
	count += valleyPlaced

	-- morning mist over Mirror Lake
	local lake = Util.model(folder, "LakeMist")
	for _ = 1, 4 do
		local p = around(rng, L.ForestLake, 0, 220)
		cloud(lake, rng, p + Vector3.new(0, Landscape.ForestLakeLevel + rng:NextNumber(20, 40), 0), rng:NextNumber(26, 40), WHITE, 0.45)
		count += 1
	end

	-- heavy ash clouds over the ruined city
	local ash = Util.model(folder, "AshClouds")
	for _ = 1, 14 do
		local p = around(rng, L.RuinsCenter, 0, 2100)
		cloud(ash, rng, p + Vector3.new(0, rng:NextNumber(380, 520), 0), rng:NextNumber(70, 120), Util.vary(rng, ASH, 0.12), 0.12)
		count += 1
	end
	Util.log(string.format("  %d clouds", count))
end

return Sky
