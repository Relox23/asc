--[[
	The Hollow Expanse
	An endless white desert under eternal night. A giant crescent moon hangs
	over the horizon, crystal-white dead trees and leaning pale spires dot the
	dunes, enormous bones lie half buried, and at the heart of it all rises the
	Pale Bastion: a colossal white dome ringed by needle-thin towers.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local TerrainWriter = require(script.Parent.Parent.TerrainWriter)
local Util = require(script.Parent.Parent.Util)
local Props = require(script.Parent.Parent.Props)
local Config = require(script.Parent.Parent.Config)
local AssetLibrary = require(script.Parent.Parent.AssetLibrary)

local Hollow = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, ball, column, disc, rod, beam = Util.box, Util.ball, Util.column, Util.disc, Util.rod, Util.beam
local NOSHADOW = { shadow = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local TAU = math.pi * 2
local L = Layout.Landmarks

local WHITE = rgb(236, 236, 240)
local PALE = rgb(214, 216, 224)
local SPIRIT = rgb(150, 210, 255)

local function flatCF(pos, dir)
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

local function ground(p)
	return Vector3.new(p.X, Landscape.heightAt(p.X, p.Z), p.Z)
end

-- The Pale Bastion -------------------------------------------------------------------------------
local function buildBastion(parent, rng)
	local m = Util.model(parent, "PaleBastion")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local G = Vector3.new(L.Bastion.X, Landscape.BastionHeight, L.Bastion.Z)
	local R, sink = 450, 120
	local toCenter = Vector3.new(-G.X, 0, -G.Z).Unit

	-- the dome, its crown spire and the great gate (one mesh, gate facing the island centre)
	local dome = AssetLibrary.place("Bastion", m, flatCF(G, toCenter))
	if dome then
		dome.Name = "Dome"
		local beacon = AssetLibrary.anchor(dome, flatCF(G, toCenter), Vector3.new(0, 0, 668), "Beacon")
		Util.pointLight(beacon, SPIRIT, 3, 60)
	else
		ball(m, G - Vector3.new(0, sink, 0), R * 2, WHITE, M.Concrete)
		for _, y in ipairs({ 40, 130, 220, 290 }) do
			local yy = y + sink
			local d = 2 * math.sqrt(R * R - yy * yy) + 3
			disc(m, G + Vector3.new(0, y, 0), 5, d, PALE, M.Concrete, NOSHADOW)
		end

		-- crown spire on top of the dome
		local top = G + Vector3.new(0, R - sink, 0)
		column(m, top - Vector3.new(0, 20, 0), 140, 46, WHITE, M.Concrete)
		disc(m, top + Vector3.new(0, 120, 0), 6, 64, PALE, M.Concrete)
		column(m, top + Vector3.new(0, 123, 0), 90, 22, WHITE, M.Concrete)
		rod(m, top + Vector3.new(0, 210, 0), top + Vector3.new(0, 330, 0), 6, WHITE, M.Concrete)
		local beacon = ball(m, top + Vector3.new(0, 332, 0), 8, SPIRIT, M.Neon, NOSHADOW)
		Util.pointLight(beacon, SPIRIT, 3, 60)
	end

	-- needle towers around the dome
	for k = 0, 6 do
		local a = k / 7 * TAU + 0.2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = ground(G + dir * (R + rng:NextNumber(70, 140)))
		local h = rng:NextNumber(220, 420)
		-- the mesh is 320 studs to its top disc, with the glowing tip at 413
		local needle = AssetLibrary.place("NeedleTower", m, flatCF(base, -dir), h / 320)
		if needle then
			if k % 2 == 0 then
				local tip = AssetLibrary.anchor(needle, flatCF(base, -dir), Vector3.new(0, 0, 413), "Tip")
				Util.pointLight(tip, SPIRIT, 2, 40)
			end
			continue
		end
		box(m, CFrame.new(base + Vector3.new(0, 8, 0)), Vector3.new(44, 24, 44), PALE, M.Concrete)
		column(m, base, h, 26, WHITE, M.Concrete)
		disc(m, base + Vector3.new(0, h * 0.55, 0), 4, 36, PALE, M.Concrete, NOSHADOW)
		disc(m, base + Vector3.new(0, h, 0), 6, 48, PALE, M.Concrete)
		column(m, base + Vector3.new(0, h + 3, 0), 30, 12, WHITE, M.Concrete)
		rod(m, base + Vector3.new(0, h + 33, 0), base + Vector3.new(0, h + 90, 0), 3, WHITE, M.Concrete)
		local tip = ball(m, base + Vector3.new(0, h + 91, 0), 4, SPIRIT, M.Neon, NOSHADOW)
		if k % 2 == 0 then
			Util.pointLight(tip, SPIRIT, 2, 40)
		end
	end

	-- the great gate, facing the island center
	local gatePos = G + toCenter * (math.sqrt(R * R - sink * sink) - 18)
	if not dome then
		local gcf = flatCF(gatePos, toCenter)
		box(m, gcf * CFrame.new(0, 45, 0), Vector3.new(64, 92, 60), rgb(10, 10, 14), M.SmoothPlastic)
		for _, s in ipairs({ -1, 1 }) do
			box(m, gcf * CFrame.new(s * 40, 55, -26), Vector3.new(16, 112, 18), WHITE, M.Concrete)
		end
		box(m, gcf * CFrame.new(0, 116, -26), Vector3.new(98, 16, 20), WHITE, M.Concrete)
		box(m, gcf * CFrame.new(0, 100, -31), Vector3.new(64, 3, 4), SPIRIT, M.Neon, NOCOL_NOSHADOW)
	end

	-- processional road of white slabs and pillars leading to the gate
	for k = 0, 34 do
		local p = ground(gatePos + toCenter * (40 + k * 10))
		box(m, flatCF(p, toCenter), Vector3.new(26, 1.6, 9.4), PALE, M.Marble, NOSHADOW)
		if k % 5 == 2 then
			for _, s in ipairs({ -1, 1 }) do
				local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
				local q = ground(p + side * s * 24)
				box(m, CFrame.new(q + Vector3.new(0, 20, 0)), Vector3.new(6, 44, 6), WHITE, M.Concrete)
				box(m, CFrame.new(q + Vector3.new(0, 42.5, 0)), Vector3.new(8, 2, 8), PALE, M.Concrete, NOSHADOW)
				local glow = box(m, CFrame.new(q + Vector3.new(0, 44.5, 0)) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), Vector3.new(2.6, 2.6, 2.6), SPIRIT, M.Neon, NOCOL_NOSHADOW)
				if k % 10 == 2 then
					Util.pointLight(glow, SPIRIT, 1.5, 30)
				end
			end
		end
	end

	-- outer wall ring with four breaks
	local ringR = R + 220
	for s = 0, 71 do
		if s % 18 > 1 then
			local a = (s + 0.5) / 72 * TAU
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			if dir:Dot(toCenter) < 0.97 then
				local p = ground(G + dir * ringR)
				local len = TAU * ringR / 72 + 1
				box(m, CFrame.lookAt(p + Vector3.new(0, 9, 0), p + Vector3.new(0, 9, 0) + Vector3.new(-dir.Z, 0, dir.X)), Vector3.new(10, 26, len), WHITE, M.Concrete)
			end
		end
	end
	return m, G
end

-- Crescent moon ----------------------------------------------------------------------------------------
local function buildMoon(parent)
	local m = Util.model(parent, "HollowMoon")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local a = Layout.ZoneAngle.Hollow
	local radial = Vector3.new(math.cos(a), 0, math.sin(a))
	local tangent = Vector3.new(-radial.Z, 0, radial.X)
	local pos = radial * (Layout.ISLAND_RADIUS + 1400) + Vector3.new(0, 2300, 0)
	local D = 1000
	local moon = ball(m, pos, D, rgb(252, 250, 236), M.Neon, NOCOL_NOSHADOW)
	moon.Name = "Moon"
	moon.CanQuery = false
	local shadow = ball(m, pos + tangent * D * 0.3 - radial * D * 0.12, D * 0.96, rgb(6, 8, 16), M.SmoothPlastic, NOCOL_NOSHADOW)
	shadow.Name = "MoonShadow"
	shadow.CanQuery = false
	return m
end

-- Glowing fissure lines in the sand ---------------------------------------------------------------------
local function fissure(parent, rng, pos)
	local m = Util.model(parent, "Fissure")
	local p = pos
	local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
	for k = 1, rng:NextInteger(3, 6) do
		dir = (dir + Vector3.new(rng:NextNumber(-0.7, 0.7), 0, rng:NextNumber(-0.7, 0.7))).Unit
		local q = p + dir * rng:NextNumber(10, 24)
		local a = ground(p) + Vector3.new(0, 0.15, 0)
		local b = ground(q) + Vector3.new(0, 0.15, 0)
		local seg = beam(m, a, b, rng:NextNumber(0.8, 1.6), 0.3, SPIRIT, M.Neon, NOCOL_NOSHADOW)
		if k == 1 then
			Util.pointLight(seg, SPIRIT, 1, 20)
		end
		p = q
	end
	return m
end

---------------------------------------------------------------------------------------------------------
function Hollow.Build(folder, rng)
	Util.log("Building The Hollow Expanse...")
	local _, bastion = buildBastion(folder, rng)
	buildMoon(folder)

	local R = Landscape.MAX_COAST
	local function spot(minR, maxR)
		for _ = 1, 40 do
			local a = Layout.ZoneAngle.Hollow + rng:NextNumber(-0.85, 0.85) * Layout.HALF_SECTOR
			local p = Layout.polar(a, rng:NextNumber(minR, maxR))
			local q = Landscape.query(p.X, p.Z)
			if q.land and q.zone == "Hollow" and (p - Vector3.new(bastion.X, 0, bastion.Z)).Magnitude > 760 then
				return Vector3.new(p.X, q.h, p.Z)
			end
		end
		return nil
	end
	local outer = Layout.ISLAND_RADIUS - Layout.BEACH_WIDTH - 200
	local inner = Layout.HUB_RADIUS + Layout.HUB_APRON * 0.7

	-- leaning pale spires and arches (terrain)
	local spires = 0
	for _ = 1, 40 do
		local p = spot(inner, outer)
		if p then
			TerrainWriter.spire(rng, p, rng:NextNumber(60, 220), rng:NextNumber(12, 26), M.Slate, rng:NextNumber(0.08, 0.35))
			spires += 1
		end
		Util.breathe()
	end
	for _ = 1, 3 do
		local p = spot(inner + 400, outer - 200)
		if p then
			local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
			local b = ground(p + dir * rng:NextNumber(120, 200))
			TerrainWriter.arch(p - Vector3.new(0, 6, 0), b - Vector3.new(0, 6, 0), rng:NextNumber(70, 110), rng:NextNumber(12, 16), M.Slate)
		end
	end

	-- remains of colossal creatures
	local bones = Util.model(folder, "Remains")
	for i = 1, 3 do
		local p = spot(inner + 200, outer)
		if p then
			Props.giantSkeleton(bones, rng, p - Vector3.new(0, 10, 0), rng:NextNumber(0, TAU), i == 1 and 2.2 or rng:NextNumber(1.2, 1.7))
		end
	end

	-- broken white pillars
	local pillars = Util.model(folder, "Pillars")
	for _ = 1, 34 do
		local p = spot(inner, outer)
		if p then
			Props.brokenColumn(pillars, rng, p - Vector3.new(0, 1, 0), WHITE, M.Marble)
		end
	end

	-- fissures and drifting spirit motes
	local glow = Util.model(folder, "SpiritGlow")
	for _ = 1, 26 do
		local p = spot(inner, outer)
		if p then
			fissure(glow, rng, p)
		end
	end
	for _ = 1, 14 do
		local p = spot(inner, outer)
		if p then
			local e = box(glow, CFrame.new(p + Vector3.new(0, 12, 0)), Vector3.new(80, 20, 80), SPIRIT, M.SmoothPlastic, { collide = false, shadow = false, transparency = 1 })
			e.CanQuery = false
			Util.particles(e, {
				Texture = Util.TEX.sparkle,
				Color = Util.cs(rgb(190, 230, 255), rgb(255, 255, 255)),
				Size = Util.ns(0, 0, 0.3, 0.8, 1, 0),
				Lifetime = NumberRange.new(6, 10),
				Rate = 8,
				Speed = NumberRange.new(0.4, 1.2),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 0.5, 0),
				LightEmission = 1,
				Shape = Enum.ParticleEmitterShape.Box,
			})
		end
	end

	-- crystal-white dead trees
	local trees = Util.folder(folder, "QuartzTrees")
	local quartz = Props.quartzTrees()
	local spacing = 150 / math.sqrt(math.max(Config.FOLIAGE_DENSITY, 0.05))
	local count = 0
	for _, p in ipairs(Util.scatterGrid(rng, -R, -R, R, R, spacing)) do
		if Layout.getZone(p.X, p.Z) == "Hollow" and rng:NextNumber() < 0.4 then
			local q = Landscape.query(p.X, p.Z)
			if q.land and q.zone == "Hollow" and (p - Vector3.new(bastion.X, 0, bastion.Z)).Magnitude > 720 then
				Util.place(Props.randomTemplate(rng, quartz), trees, Vector3.new(p.X, q.h - 1, p.Z), rng:NextNumber(0, TAU), rng:NextNumber(0.8, 1.6))
				count += 1
			end
		end
		Util.breathe()
	end
	Util.log(string.format("  %d spires, %d quartz trees", spires, count))
end

return Hollow
