--[[
	Sea of Whispering Dunes
	Towering golden dunes that roll forever. In their exact middle stands the
	great watchtower (see Watchtower.luau), wreathed in a sea of clouds.
	Around it: wind-carved hoodoos and arches, a colossal buried statue,
	the bones of a sand leviathan and lost caravans.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local TerrainWriter = require(script.Parent.Parent.TerrainWriter)
local Util = require(script.Parent.Parent.Util)
local Props = require(script.Parent.Parent.Props)
local Watchtower = require(script.Parent.Parent.Watchtower)
local AssetLibrary = require(script.Parent.Parent.AssetLibrary)

local Dunes = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, ball, rod, wedge = Util.box, Util.ball, Util.rod, Util.wedge
local NOCOL = { collide = false }
local NOSHADOW = { shadow = false }
local TAU = math.pi * 2
local HALF_PI = math.pi / 2
local L = Layout.Landmarks

local STONE_ALT = rgb(214, 196, 160)
local STONE_DARK = rgb(184, 152, 112)
local GOLD = rgb(214, 172, 74)
local SANDSTONE = rgb(204, 160, 112)

local function flatCF(pos, dir)
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

local function ground(p)
	return Vector3.new(p.X, Landscape.heightAt(p.X, p.Z), p.Z)
end

-- Colossal buried statue and hand --------------------------------------------------------------------
local HAND = AssetLibrary.fromBlender(110, -10, 0) -- where the mesh's hand comes out of the sand

-- The statue mesh, sunk into the sand and looking up at the sky. It also holds
-- the hand, so pick the heading where the ground under the hand is closest in
-- height and roll the statue a little to make up the rest.
local function statueMesh(parent, rng, pos)
	if not AssetLibrary.has("Colossus") then
		return nil
	end
	local best, bestDiff
	local start = rng:NextNumber(0, TAU)
	for k = 0, 11 do
		local a = start + k / 12 * TAU
		local face = Vector3.new(math.cos(a), 0, math.sin(a))
		local hand = (flatCF(pos, face) * CFrame.new(HAND)).Position
		local diff = math.abs(Landscape.heightAt(hand.X, hand.Z) - pos.Y)
		if not best or diff < bestDiff then
			best, bestDiff = face, diff
		end
	end
	local cf = flatCF(pos - Vector3.new(0, 18, 0), best) * CFrame.Angles(0.25, 0, 0)
	local hand = (cf * CFrame.new(HAND)).Position
	local want = Landscape.heightAt(hand.X, hand.Z) - 3
	local roll = math.clamp(math.asin(math.clamp((hand.Y - want) / HAND.Magnitude, -1, 1)), -0.3, 0.3)
	cf = cf * CFrame.Angles(0, 0, roll)
	local m = AssetLibrary.place("Colossus", parent, cf)
	m.Name = "BuriedColossus"
	-- sand drifted around the wrist
	workspace.Terrain:FillBall((cf * CFrame.new(HAND)).Position - Vector3.new(0, 4, 0), 12, M.Sand)
	return m
end

local function buriedStatue(parent, rng, pos)
	local mesh = statueMesh(parent, rng, pos)
	if mesh then
		return mesh
	end
	local m = Util.model(parent, "BuriedColossus")
	local face = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
	local cf = flatCF(pos - Vector3.new(0, 18, 0), face) * CFrame.Angles(0.25, 0, 0.18)
	ball(m, cf.Position, 64, SANDSTONE, M.Sandstone)
	box(m, cf * CFrame.new(0, 12, -24), Vector3.new(40, 8, 20), SANDSTONE, M.Sandstone)
	wedge(m, cf * CFrame.new(0, 0, -33), Vector3.new(8, 16, 8), SANDSTONE, M.Sandstone)
	for _, s in ipairs({ -1, 1 }) do
		ball(m, (cf * CFrame.new(s * 11, 6, -26)).Position, 9, rgb(60, 44, 34), M.SmoothPlastic, NOCOL)
	end
	box(m, cf * CFrame.new(0, -12, -26), Vector3.new(18, 3, 8), rgb(150, 110, 80), M.Sandstone)
	-- tall headdress, cracked
	box(m, cf * CFrame.new(0, 34, 4), Vector3.new(50, 20, 40), STONE_DARK, M.Sandstone)
	wedge(m, cf * CFrame.new(-18, 52, 4) * CFrame.Angles(0, HALF_PI, 0), Vector3.new(40, 18, 14), STONE_DARK, M.Sandstone)
	box(m, cf * CFrame.new(0, 34, -16), Vector3.new(50, 3, 2), GOLD, M.Foil, NOSHADOW)

	-- an enormous hand reaching out of the sand nearby
	local handPos = ground(pos + Vector3.new(-face.Z, 0, face.X) * 110)
	local hcf = CFrame.new(handPos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * CFrame.Angles(-0.5, 0, 0)
	box(m, hcf * CFrame.new(0, 10, 0), Vector3.new(26, 30, 10), SANDSTONE, M.Sandstone)
	for f = 0, 3 do
		local x = -9 + f * 6
		local p0 = (hcf * CFrame.new(x, 25, 0)).Position
		local p1 = (hcf * CFrame.new(x, 38 - math.abs(f - 1.5) * 2, -3)).Position
		local p2 = (hcf * CFrame.new(x, 46 - math.abs(f - 1.5) * 3, -10)).Position
		rod(m, p0, p1, 5.4, SANDSTONE, M.Sandstone)
		rod(m, p1, p2, 4.8, SANDSTONE, M.Sandstone)
	end
	local t0 = (hcf * CFrame.new(14, 14, -2)).Position
	rod(m, t0, (hcf * CFrame.new(22, 26, -8)).Position, 6, SANDSTONE, M.Sandstone)
	return m
end

-- Lost caravan -------------------------------------------------------------------------------------------
local function caravan(parent, rng, pos)
	local mesh = AssetLibrary.place("Caravan", parent, CFrame.new(pos - Vector3.new(0, 1, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * CFrame.Angles(0, 0, 0.08))
	if mesh then
		mesh.Name = "LostCaravan"
		return mesh
	end
	local m = Util.model(parent, "LostCaravan")
	local cf = CFrame.new(pos - Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * CFrame.Angles(0, 0, 0.2)
	local wood = rgb(120, 86, 56)
	box(m, cf * CFrame.new(0, 3, 0), Vector3.new(9, 2, 16), wood, M.WoodPlanks)
	for _, z in ipairs({ -5, 5 }) do
		Util.cylinder(m, cf * CFrame.new(-5, 2.2, z), 1, 6, rgb(90, 64, 42), M.Wood)
	end
	Util.cylinder(m, cf * CFrame.new(3, 0.4, 6) * CFrame.Angles(0, 0, 1.2), 1, 6, rgb(90, 64, 42), M.Wood)
	for k = -1, 1 do
		local p = cf * CFrame.new(0, 7, k * 5)
		rod(m, (cf * CFrame.new(-4.5, 4, k * 5)).Position, p.Position + Vector3.new(0, 1, 0), 0.5, wood, M.Wood, NOSHADOW)
		rod(m, (cf * CFrame.new(4.5, 4, k * 5)).Position, p.Position + Vector3.new(0, 1, 0), 0.5, wood, M.Wood, NOSHADOW)
	end
	Util.gableRoof(m, cf * CFrame.new(0, 4, 2), 10, 9, 4, rgb(214, 196, 168), M.Fabric, NOCOL)
	for _ = 1, 4 do
		local p = cf * CFrame.new(rng:NextNumber(-10, 10), 1, rng:NextNumber(-12, 12))
		box(m, p * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), 0), Vector3.new(3, 3, 3), rgb(140, 104, 66), M.WoodPlanks)
	end
	return m
end

---------------------------------------------------------------------------------------------------------
function Dunes.Build(folder, rng)
	Util.log("Building Sea of Whispering Dunes...")
	local towerBase = Vector3.new(L.Watchtower.X, Landscape.WatchtowerHeight, L.Watchtower.Z)
	Watchtower.Build(folder, towerBase, -towerBase)

	local tower = L.Watchtower
	local function spot(minR, maxR, clear)
		for _ = 1, 40 do
			local a = Layout.ZoneAngle.Dunes + rng:NextNumber(-0.85, 0.85) * Layout.HALF_SECTOR
			local p = Layout.polar(a, rng:NextNumber(minR, maxR))
			local q = Landscape.query(p.X, p.Z)
			if q.land and q.zone == "Dunes" and (p - tower).Magnitude > (clear or 420) then
				return Vector3.new(p.X, q.h, p.Z)
			end
		end
		return nil
	end
	local outer = Layout.ISLAND_RADIUS - Layout.BEACH_WIDTH - 220
	local inner = Layout.HUB_RADIUS + Layout.HUB_APRON * 0.8

	-- wind-carved hoodoos and arches
	for _ = 1, 26 do
		local p = spot(inner, outer)
		if p then
			TerrainWriter.spire(rng, p, rng:NextNumber(40, 130), rng:NextNumber(10, 22), M.Sandstone, rng:NextNumber(0.02, 0.12))
		end
		Util.breathe()
	end
	for _ = 1, 4 do
		local p = spot(inner + 300, outer - 200, 600)
		if p then
			local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
			local b = ground(p + dir * rng:NextNumber(90, 160))
			TerrainWriter.arch(p - Vector3.new(0, 8, 0), b - Vector3.new(0, 8, 0), rng:NextNumber(60, 100), rng:NextNumber(10, 15), M.Sandstone)
		end
	end

	local relics = Util.model(folder, "Relics")
	local s = spot(inner + 500, outer - 300, 900)
	if s then
		buriedStatue(relics, rng, s)
	end
	local w = spot(inner + 300, outer, 700)
	if w then
		Props.giantSkeleton(relics, rng, w - Vector3.new(0, 14, 0), rng:NextNumber(0, TAU), 2.8)
	end
	for _ = 1, 3 do
		local p = spot(inner, outer, 500)
		if p then
			caravan(relics, rng, p)
		end
	end
	for _ = 1, 30 do
		local p = spot(inner, outer)
		if p then
			Props.brokenColumn(relics, rng, p - Vector3.new(0, 2, 0), STONE_ALT, M.Sandstone)
		end
	end
end

return Dunes
