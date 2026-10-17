--[[
	Sea of Whispering Dunes
	Towering golden dunes that roll forever. In their exact middle stands the
	Starwarden Watchtower: seven stacked tiers with glowing star windows, an
	observatory crowned by an armillary sphere around a captive star, and a
	pillar of light that can be seen from anywhere on the island.
	Around it: wind-carved hoodoos and arches, a colossal buried statue,
	the bones of a sand leviathan and lost caravans.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local TerrainWriter = require(script.Parent.Parent.TerrainWriter)
local Util = require(script.Parent.Parent.Util)
local Props = require(script.Parent.Parent.Props)

local Dunes = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, ball, column, disc, rod, beam, wedge = Util.box, Util.ball, Util.column, Util.disc, Util.rod, Util.beam, Util.wedge
local NOCOL = { collide = false }
local NOSHADOW = { shadow = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local TAU = math.pi * 2
local HALF_PI = math.pi / 2
local L = Layout.Landmarks

local STONE = rgb(226, 212, 182)
local STONE_ALT = rgb(214, 196, 160)
local STONE_DARK = rgb(184, 152, 112)
local GOLD = rgb(214, 172, 74)
local STARLIGHT = rgb(160, 214, 255)
local SANDSTONE = rgb(204, 160, 112)

local function flatCF(pos, dir)
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

local function ground(p)
	return Vector3.new(p.X, Landscape.heightAt(p.X, p.Z), p.Z)
end

local TELEPORT_SOURCE = [[
-- Teleport circle: touching it carries a player to the linked circle.
local pad = script.Parent
local busy = {}
pad.Touched:Connect(function(hit)
	local character = hit.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or busy[character] then
		return
	end
	local target = pad:GetAttribute("Target")
	if typeof(target) ~= "Vector3" then
		return
	end
	busy[character] = true
	character:PivotTo(CFrame.new(target + Vector3.new(0, 5, 0)))
	task.delay(2, function()
		busy[character] = nil
	end)
end)
]]

local function teleportPad(parent, pos, target, color)
	local pad = disc(parent, pos, 1, 16, color, M.Neon, NOSHADOW)
	pad.Name = "TeleportCircle"
	pad.Transparency = 0.25
	pad:SetAttribute("Target", target)
	Util.pointLight(pad, color, 2, 24)
	Util.particles(pad, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(color),
		Size = Util.ns(0, 0.8, 1, 0),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 25,
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(10, 10),
		EmissionDirection = Enum.NormalId.Right,
		LightEmission = 1,
	})
	local s = Instance.new("Script")
	s.Name = "Teleport"
	s.Source = TELEPORT_SOURCE
	s.Parent = pad
	return pad
end

-- Ring of beams (for the armillary sphere).
local function ring(parent, center, radius, axisCF, thickness, color, material)
	local seg = 28
	for k = 0, seg - 1 do
		local a0, a1 = k / seg * TAU, (k + 1) / seg * TAU
		local p0 = center + axisCF:VectorToWorldSpace(Vector3.new(math.cos(a0) * radius, math.sin(a0) * radius, 0))
		local p1 = center + axisCF:VectorToWorldSpace(Vector3.new(math.cos(a1) * radius, math.sin(a1) * radius, 0))
		beam(parent, p0, p1, thickness, thickness, color, material, NOCOL_NOSHADOW)
	end
end

-- Watchtower --------------------------------------------------------------------------------------
local function buildWatchtower(parent, rng)
	local m = Util.model(parent, "StarwardenWatchtower")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local g = Landscape.WatchtowerHeight
	local C = Vector3.new(L.Watchtower.X, g, L.Watchtower.Z)
	local toCenter = Vector3.new(-C.X, 0, -C.Z).Unit

	-- stepped foundation
	disc(m, C + Vector3.new(0, -8, 0), 24, 320, STONE_DARK, M.Sandstone)
	disc(m, C + Vector3.new(0, -2, 0), 24, 276, STONE, M.Limestone)
	disc(m, C + Vector3.new(0, 4, 0), 24, 236, STONE_ALT, M.Limestone)
	disc(m, C + Vector3.new(0, 16.2, 0), 0.6, 238, GOLD, M.Foil, NOSHADOW)
	for k = 0, 2 do
		local r0 = 118 + k * 21
		local p = C + toCenter * (r0 + 10)
		box(m, flatCF(Vector3.new(p.X, g + 13 - k * 6 - 6, p.Z), toCenter), Vector3.new(60, 12, 22), STONE, M.Limestone)
	end

	-- seven buttresses and guardian pillars
	for k = 0, 6 do
		local a = k / 7 * TAU + math.atan2(toCenter.Z, toCenter.X) + TAU / 14
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local c = C + dir * 118 + Vector3.new(0, 16 + 35, 0)
		wedge(m, flatCF(c, dir), Vector3.new(18, 70, 56), STONE_ALT, M.Limestone)
		local pillarBase = ground(C + dir * 150)
		column(m, pillarBase - Vector3.new(0, 4, 0), 64, 11, STONE, M.Limestone)
		box(m, CFrame.new(pillarBase + Vector3.new(0, 61, 0)), Vector3.new(14, 3, 14), STONE_DARK, M.Sandstone)
		local star = box(m, CFrame.new(pillarBase + Vector3.new(0, 68, 0)) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), Vector3.new(5, 5, 5), STARLIGHT, M.Neon, NOCOL_NOSHADOW)
		Util.pointLight(star, STARLIGHT, 1.5, 34)
	end

	-- the seven tiers
	local y = g + 16
	for i = 0, 6 do
		local r = 88 - i * 8
		local h = 70 - i * 3
		local base = C + Vector3.new(0, y - C.Y, 0)
		column(m, base, h, r * 2, i % 2 == 0 and STONE or STONE_ALT, M.Limestone)
		for k = 0, 6 do
			local a = k / 7 * TAU + i * 0.22
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			box(m, flatCF(base + dir * (r - 0.6) + Vector3.new(0, h / 2, 0), dir), Vector3.new(5, h, 4), STONE_DARK, M.Sandstone)
			local a2 = a + TAU / 14
			local dir2 = Vector3.new(math.cos(a2), 0, math.sin(a2))
			box(m, flatCF(base + dir2 * (r + 0.1) + Vector3.new(0, h * 0.55, 0), dir2), Vector3.new(2.4, h * 0.4, 0.8), STARLIGHT, M.Neon, NOCOL_NOSHADOW)
		end
		disc(m, base + Vector3.new(0, h, 0), 4, r * 2 + 10, STONE_DARK, M.Sandstone)
		disc(m, base + Vector3.new(0, h + 2.2, 0), 0.6, r * 2 + 6, GOLD, M.Foil, NOSHADOW)
		if i % 2 == 1 then
			disc(m, base + Vector3.new(0, h - 4, 0), 2, r * 2 + 26, STONE, M.Limestone)
		end
		y += h
	end

	-- grand door facing the island center
	local doorCF = flatCF(C + toCenter * 87.5 + Vector3.new(0, 16, 0), toCenter)
	box(m, doorCF * CFrame.new(0, 17, 0), Vector3.new(22, 34, 1.2), rgb(40, 30, 26), M.Wood)
	Util.cylinder(m, doorCF * CFrame.new(0, 34, 0) * CFrame.Angles(0, HALF_PI, 0), 1.2, 22, rgb(40, 30, 26), M.Wood)
	box(m, doorCF * CFrame.new(-12, 18, -0.6), Vector3.new(2.4, 38, 1.6), GOLD, M.Foil, NOSHADOW)
	box(m, doorCF * CFrame.new(12, 18, -0.6), Vector3.new(2.4, 38, 1.6), GOLD, M.Foil, NOSHADOW)

	-- observatory on top
	local top = C + Vector3.new(0, y - C.Y, 0)
	disc(m, top + Vector3.new(0, 2, 0), 4, 124, STONE_DARK, M.Sandstone)
	for k = 0, 27 do
		local a = k / 28 * TAU
		box(m, CFrame.new(top + Vector3.new(math.cos(a) * 60, 7, math.sin(a) * 60)), Vector3.new(2, 6, 2), STONE, M.Limestone, NOSHADOW)
	end
	for k = 0, 6 do
		local a = k / 7 * TAU
		column(m, top + Vector3.new(math.cos(a) * 44, 4, math.sin(a) * 44), 40, 7, STONE, M.Marble)
	end
	disc(m, top + Vector3.new(0, 46, 0), 4, 104, STONE_DARK, M.Sandstone)
	ball(m, top + Vector3.new(0, 47, 0), 76, rgb(240, 236, 226), M.Marble)
	disc(m, top + Vector3.new(0, 62, 0), 1.2, 69.8, GOLD, M.Foil, NOSHADOW)

	-- armillary sphere around a captive star
	local core = top + Vector3.new(0, 140, 0)
	rod(m, top + Vector3.new(0, 84, 0), core - Vector3.new(0, 18, 0), 3, GOLD, M.Foil)
	ring(m, core, 44, CFrame.new(), 2.2, GOLD, M.Foil)
	ring(m, core, 40, CFrame.Angles(HALF_PI, 0, 0), 2.2, GOLD, M.Foil)
	ring(m, core, 36, CFrame.Angles(HALF_PI, 0.8, 0) * CFrame.Angles(0, 0, 0.5), 2, STARLIGHT, M.Neon)
	local star = ball(m, core, 18, rgb(230, 244, 255), M.Neon, NOCOL_NOSHADOW)
	Util.pointLight(star, STARLIGHT, 4, 60, false)
	Util.particles(star, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(rgb(200, 230, 255), rgb(255, 230, 160)),
		Size = Util.ns(0, 2.5, 1, 0),
		Lifetime = NumberRange.new(2, 4),
		Rate = 30,
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})
	local beamPart = Util.cylinder(m, CFrame.new(core + Vector3.new(0, 1000, 0)) * CFrame.Angles(0, 0, HALF_PI), 1980, 5, rgb(200, 230, 255), M.Neon, NOCOL_NOSHADOW)
	beamPart.Transparency = 0.55
	beamPart.CanQuery = false
	beamPart.Name = "LightPillar"

	-- teleport circles between the door and the observatory
	-- (each circle drops you a little away from the other one so you don't bounce straight back)
	local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
	local bottomPad = C + toCenter * 106 + Vector3.new(0, 16.6, 0)
	local topPad = top + Vector3.new(0, 4.6, 0) + toCenter * 52
	teleportPad(m, bottomPad, top + Vector3.new(0, 4.6, 0) + side * 52, STARLIGHT)
	teleportPad(m, topPad, bottomPad + toCenter * 14, rgb(255, 220, 150))
	return m
end

-- Colossal buried statue and hand --------------------------------------------------------------------
local function buriedStatue(parent, rng, pos)
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
	buildWatchtower(folder, rng)

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
