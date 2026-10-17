--[[
	The Endless Shore
	The sand beach that rings the whole island, dressed to match the region
	behind it, plus a lighthouse, a shipwreck and the invisible world border
	out at sea.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local TerrainWriter = require(script.Parent.Parent.TerrainWriter)
local Util = require(script.Parent.Parent.Util)
local Props = require(script.Parent.Parent.Props)
local Config = require(script.Parent.Parent.Config)

local Coast = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, ball, column, disc, rod, wedge = Util.box, Util.ball, Util.column, Util.disc, Util.rod, Util.wedge
local NOCOL = { collide = false }
local NOSHADOW = { shadow = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local TAU = math.pi * 2
local HALF_PI = math.pi / 2

local DRIFTWOOD = rgb(176, 160, 136)

local function ground(p)
	return Vector3.new(p.X, Landscape.heightAt(p.X, p.Z), p.Z)
end

-- Point on the beach at an angle, `inland` studs from the waterline.
local function beachPoint(angle, inland)
	local rc = Landscape.coastRadius(angle)
	return Layout.polar(angle, rc - inland)
end

local function driftwood(parent, rng, pos)
	local a = rng:NextNumber(0, TAU)
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local len = rng:NextNumber(8, 16)
	local p0 = pos - dir * len / 2 + Vector3.new(0, 0.6, 0)
	local p1 = pos + dir * len / 2 + Vector3.new(0, 0.9, 0)
	local m = Util.model(parent, "Driftwood")
	rod(m, p0, p1, rng:NextNumber(1.2, 2), DRIFTWOOD, M.Wood)
	rod(m, p0:Lerp(p1, 0.6), p0:Lerp(p1, 0.6) + Vector3.new(rng:NextNumber(-3, 3), 1.5, rng:NextNumber(-3, 3)), 0.6, DRIFTWOOD, M.Wood, NOSHADOW)
	return m
end

local function iceChunks(parent, rng, pos)
	local m = Util.model(parent, "IceChunks")
	for _ = 1, rng:NextInteger(2, 4) do
		local s = Vector3.new(rng:NextNumber(3, 9), rng:NextNumber(2, 6), rng:NextNumber(3, 9))
		box(m, CFrame.new(pos + Vector3.new(rng:NextNumber(-6, 6), s.Y * 0.2, rng:NextNumber(-6, 6))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), rng:NextNumber(-0.4, 0.4)), s, rgb(190, 226, 244), M.Glacier, { transparency = 0.15, reflectance = 0.1 })
	end
	return m
end

-- Lighthouse --------------------------------------------------------------------------------------------
local function lighthouse(parent, rng, pos, seaDir)
	local m = Util.model(parent, "OldLighthouse")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	TerrainWriter.boulder(rng, pos + Vector3.new(0, -4, 0), 22, M.Rock)
	local base = pos + Vector3.new(0, 10, 0)
	column(m, base - Vector3.new(0, 4, 0), 8, 30, rgb(120, 118, 112), M.Cobblestone)
	local white, red = rgb(240, 238, 232), rgb(178, 44, 40)
	local y = 4
	for k = 0, 5 do
		local d = 22 - k * 1.6
		column(m, base + Vector3.new(0, y, 0), 12, d, k % 2 == 0 and white or red, M.Plaster)
		y += 12
	end
	disc(m, base + Vector3.new(0, y, 0), 2, 22, rgb(50, 50, 54), M.Metal)
	for k = 0, 15 do
		local a = k / 16 * TAU
		box(m, CFrame.new(base + Vector3.new(math.cos(a) * 10.5, y + 2.5, math.sin(a) * 10.5)), Vector3.new(0.5, 3, 0.5), rgb(40, 40, 44), M.Metal, NOSHADOW)
	end
	column(m, base + Vector3.new(0, y + 1, 0), 10, 12, rgb(220, 240, 255), M.Glass, { transparency = 0.5, reflectance = 0.2 })
	local lamp = ball(m, base + Vector3.new(0, y + 6, 0), 6, rgb(255, 240, 190), M.Neon, NOSHADOW)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 40
	spot.Range = 60
	spot.Brightness = 6
	spot.Color = rgb(255, 236, 190)
	spot.Parent = lamp
	lamp.CFrame = CFrame.lookAt(lamp.Position, lamp.Position + seaDir)
	Util.pointLight(lamp, rgb(255, 236, 190), 3, 60)
	disc(m, base + Vector3.new(0, y + 11.5, 0), 1.4, 16, red, M.Metal)
	ball(m, base + Vector3.new(0, y + 12, 0), 10, red, M.Metal)
	ball(m, base + Vector3.new(0, y + 17.6, 0), 1.6, rgb(40, 40, 44), M.Metal)
	-- keeper's cottage
	local inland = -seaDir
	local hc = CFrame.lookAt(pos + inland * 30, pos + inland * 30 + seaDir)
	local g = Landscape.heightAt(hc.Position.X, hc.Position.Z)
	hc = hc - Vector3.new(0, hc.Position.Y - g, 0)
	box(m, hc * CFrame.new(0, 5, 0), Vector3.new(16, 12, 12), white, M.Plaster)
	Util.gableRoof(m, hc * CFrame.new(0, 11, 0) * CFrame.Angles(0, HALF_PI, 0), 15, 19, 6, red, M.RoofShingles)
	local win = box(m, hc * CFrame.new(-4, 6, -6.1), Vector3.new(3, 3, 0.3), rgb(255, 214, 140), M.SmoothPlastic, NOSHADOW)
	Util.surfaceLight(win, Enum.NormalId.Front, rgb(255, 200, 130), 1, 12)
	return m
end

-- Shipwreck ----------------------------------------------------------------------------------------------
local function shipwreck(parent, rng, pos, seaDir)
	local m = Util.model(parent, "Shipwreck")
	local hull = rgb(92, 66, 46)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(-seaDir.Z, 0, seaDir.X)) * CFrame.Angles(0, 0, 0.35) * CFrame.new(0, 2, 0)
	box(m, cf * CFrame.new(0, 0, 0), Vector3.new(20, 3, 60), hull, M.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		box(m, cf * CFrame.new(s * 10, 5, 0) * CFrame.Angles(0, 0, s * 0.25), Vector3.new(2, 12, 58), hull, M.WoodPlanks)
	end
	wedge(m, cf * CFrame.new(0, 4, -36) * CFrame.Angles(0, math.pi, 0), Vector3.new(18, 10, 14), hull, M.WoodPlanks)
	-- broken ribs at the stern
	for z = 18, 30, 4 do
		for _, s in ipairs({ -1, 1 }) do
			rod(m, (cf * CFrame.new(s * 9, 1, z)).Position, (cf * CFrame.new(s * 12, 14, z)).Position, 1.4, hull, M.Wood, NOSHADOW)
		end
	end
	box(m, cf * CFrame.new(0, 8, -6), Vector3.new(18, 1, 34), rgb(122, 92, 64), M.WoodPlanks)
	local mast = rod(m, (cf * CFrame.new(0, 8, -4)).Position, (cf * CFrame.new(2, 46, -6)).Position, 2.2, rgb(80, 58, 40), M.Wood)
	mast.Name = "Mast"
	rod(m, (cf * CFrame.new(-12, 36, -5)).Position, (cf * CFrame.new(14, 38, -6)).Position, 1, rgb(80, 58, 40), M.Wood, NOSHADOW)
	box(m, cf * CFrame.new(-2, 28, -5.3) * CFrame.Angles(0, 0, 0.08), Vector3.new(16, 14, 0.3), rgb(220, 210, 186), M.Fabric, NOCOL)
	rod(m, (cf * CFrame.new(0, 8, 20)).Position, (cf * CFrame.new(16, -2, 34)).Position, 1.6, rgb(80, 58, 40), M.Wood)
	for _ = 1, 5 do
		local p = ground(pos + Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40)))
		box(m, CFrame.new(p + Vector3.new(0, 1, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), 0), Vector3.new(3.4, 3.4, 3.4), rgb(140, 104, 66), M.WoodPlanks)
	end
	local chest = box(m, CFrame.new(ground(pos + seaDir * -24) + Vector3.new(0, 1.2, 0)), Vector3.new(4, 2.6, 2.6), rgb(110, 70, 40), M.WoodPlanks)
	chest.Name = "Chest"
	box(m, chest.CFrame * CFrame.new(0, 0.2, -1.35), Vector3.new(4.2, 0.4, 0.2), rgb(214, 172, 74), M.Foil, NOCOL_NOSHADOW)
	return m
end

-- World border ----------------------------------------------------------------------------------------------
local function worldBorder(parent)
	local m = Util.model(parent, "WorldBorder")
	local R = Layout.WORLD_BORDER
	local n = 96
	for k = 0, n - 1 do
		local a = (k + 0.5) / n * TAU
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = dir * R + Vector3.new(0, 600, 0)
		local p = box(m, CFrame.lookAt(pos, pos + Vector3.new(-dir.Z, 0, dir.X)), Vector3.new(20, 1400, TAU * R / n + 4), rgb(255, 255, 255), M.SmoothPlastic, {
			shadow = false,
			transparency = 1,
		})
		p.CanQuery = false
		p.CanTouch = false
	end
	return m
end

---------------------------------------------------------------------------------------------------------
function Coast.Build(folder, rng)
	Util.log("Dressing the shore...")
	local palms = Props.palms()
	local quartz = Props.quartzTrees()
	local deco = Util.folder(folder, "BeachDecor")
	local R = Layout.ISLAND_RADIUS
	local steps = math.floor(TAU * R / 60 * math.min(Config.FOLIAGE_DENSITY, 2))
	local count = 0
	for k = 0, steps - 1 do
		local a = k / steps * TAU + rng:NextNumber(-0.002, 0.002)
		local p = beachPoint(a, rng:NextNumber(50, Layout.BEACH_WIDTH - 30))
		local q = Landscape.query(p.X, p.Z)
		if q.h > 1.5 and not q.ocean then
			local pos = Vector3.new(p.X, q.h, p.Z)
			local zone = Layout.getZone(p.X * 0.97, p.Z * 0.97)
			local r = rng:NextNumber()
			if zone == "Forest" or zone == "Dunes" then
				if r < 0.32 then
					Util.place(Props.randomTemplate(rng, palms), deco, pos - Vector3.new(0, 1, 0), rng:NextNumber(0, TAU), rng:NextNumber(0.85, 1.25))
				elseif r < 0.4 then
					driftwood(deco, rng, pos)
				elseif r < 0.46 then
					Props.rockCluster(deco, rng, pos, rng:NextNumber(4, 9), rgb(140, 136, 128), M.Rock)
				end
			elseif zone == "Snow" then
				if r < 0.16 then
					Props.rockCluster(deco, rng, pos, rng:NextNumber(5, 10), rgb(118, 120, 126), M.Rock)
					workspace.Terrain:FillBall(pos + Vector3.new(0, 3, 0), rng:NextNumber(3, 5), M.Snow)
				elseif r < 0.26 then
					iceChunks(deco, rng, pos)
				elseif r < 0.3 then
					driftwood(deco, rng, pos)
				end
			elseif zone == "Hollow" then
				if r < 0.08 then
					Util.place(Props.randomTemplate(rng, quartz), deco, pos - Vector3.new(0, 1, 0), rng:NextNumber(0, TAU), rng:NextNumber(0.6, 1))
				elseif r < 0.18 then
					Props.rockCluster(deco, rng, pos, rng:NextNumber(4, 8), rgb(214, 216, 224), M.Slate)
				end
			elseif zone == "Ruins" then
				if r < 0.1 then
					Props.rockCluster(deco, rng, pos, rng:NextNumber(4, 10), rgb(80, 78, 76), M.Concrete)
				elseif r < 0.13 then
					Props.wreckedCar(deco, rng, CFrame.new(pos - Vector3.new(0, 1.5, 0)) * CFrame.Angles(0.1, rng:NextNumber(0, TAU), 0.15))
				elseif r < 0.18 then
					driftwood(deco, rng, pos)
				end
			end
			count += 1
		end
		Util.breathe()
	end

	-- a few rocky outcrops in the surf
	for _ = 1, 40 do
		local a = rng:NextNumber(0, TAU)
		local p = beachPoint(a, -rng:NextNumber(20, 120))
		TerrainWriter.boulder(rng, Vector3.new(p.X, rng:NextNumber(-6, 2), p.Z), rng:NextNumber(8, 18), M.Rock)
	end

	-- landmarks on the shore
	local la = Layout.ZoneAngle.Forest - 0.42
	local lp = beachPoint(la, 70)
	lighthouse(folder, rng, ground(lp), Vector3.new(math.cos(la), 0, math.sin(la)))
	local sa = Layout.ZoneAngle.Dunes + 0.3
	local sp = beachPoint(sa, 40)
	shipwreck(folder, rng, ground(sp), Vector3.new(math.cos(sa), 0, math.sin(sa)))

	worldBorder(folder)
	Util.log(string.format("  %d beach spots dressed", count))
end

return Coast
