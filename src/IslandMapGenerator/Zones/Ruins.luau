--[[
	Ashen Remnant
	A dead city swallowed by black sand. No streets survive, only shattered
	skyscrapers jutting out of the dunes at odd angles, toppled towers,
	burnt-out cars half buried in ash, smouldering fires and bent street lamps.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local Util = require(script.Parent.Parent.Util)
local Props = require(script.Parent.Parent.Props)

local Ruins = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, rod = Util.box, Util.rod
local NOSHADOW = { shadow = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local TAU = math.pi * 2
local HALF_PI = math.pi / 2
local L = Layout.Landmarks

local CONCRETE = rgb(98, 96, 94)
local CONCRETE_DARK = rgb(70, 68, 68)
local GLASS = rgb(30, 38, 46)
local REBAR = rgb(96, 58, 40)
local SOOT = rgb(14, 14, 16)

local function ground(p)
	return Vector3.new(p.X, Landscape.heightAt(p.X, p.Z), p.Z)
end

-- One broken skyscraper. cf is the center of its footprint at the base.
local function skyscraper(parent, rng, cf, w, d, H)
	local m = Util.model(parent, "Skyscraper")
	local tint = Util.vary(rng, CONCRETE, 0.1)
	local glass = Util.vary(rng, GLASS, 0.15)

	-- The tower is split into two halves; the right half broke off lower down,
	-- leaving a stepped, sheared silhouette.
	local hl = H
	local hr = H * rng:NextNumber(0.55, 0.88)
	local halves = { { x = -w / 4, h = hl }, { x = w / 4, h = hr } }
	for _, half in ipairs(halves) do
		box(m, cf * CFrame.new(half.x, half.h / 2, 0), Vector3.new(w / 2 - 1, half.h, d - 2), glass, M.Glass, { reflectance = 0.12 })
	end
	-- floor bands: full width up to the break, then only the standing half
	for y = 6, hl - 4, 12 do
		if y < hr - 4 then
			box(m, cf * CFrame.new(0, y, 0), Vector3.new(w + 0.6, 1.4, d + 0.6), tint, M.Concrete, NOSHADOW)
		else
			box(m, cf * CFrame.new(-w / 4 - 0.2, y, 0), Vector3.new(w / 2 + 0.2, 1.4, d + 0.6), tint, M.Concrete, NOSHADOW)
		end
	end
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local ch = c[1] < 0 and hl or hr
		box(m, cf * CFrame.new(c[1] * (w / 2 - 0.4), ch / 2, c[2] * (d / 2 - 0.4)), Vector3.new(2.6, ch, 2.6), tint, M.Concrete)
	end
	box(m, cf * CFrame.new(0, hl / 2, 0), Vector3.new(2.4, hl, d + 0.4), tint, M.Concrete, NOSHADOW)

	-- slab hanging off the break, sagging toward the fallen half
	box(m, cf * CFrame.new(w / 4, hr + 3, 0) * CFrame.Angles(0, 0, -rng:NextNumber(0.3, 0.7)), Vector3.new(w / 2, 1.4, d * 0.8), tint, M.Concrete)

	-- jagged broken crowns on both halves
	for _, half in ipairs(halves) do
		for _ = 1, rng:NextInteger(2, 4) do
			local sx = rng:NextNumber(0.25, 0.5) * w / 2
			local sz = rng:NextNumber(0.2, 0.5) * d
			local h = rng:NextNumber(4, 22)
			local x = half.x + rng:NextNumber(-1, 1) * (w / 2 - sx) / 2
			local z = rng:NextNumber(-1, 1) * (d - sz) / 2
			box(m, cf * CFrame.new(x, half.h + h / 2 - 1, z), Vector3.new(sx, h, sz), tint, M.Concrete)
		end
		for _ = 1, rng:NextInteger(4, 7) do
			local x = half.x + rng:NextNumber(-0.45, 0.45) * w / 2
			local z = rng:NextNumber(-0.45, 0.45) * d
			local a = (cf * CFrame.new(x, half.h - 1, z)).Position
			local b = (cf * CFrame.new(x + rng:NextNumber(-3, 3), half.h + rng:NextNumber(5, 16), z + rng:NextNumber(-3, 3))).Position
			rod(m, a, b, 0.5, REBAR, M.CorrodedMetal, NOCOL_NOSHADOW)
		end
	end

	-- blown-out holes, some still burning inside
	for k = 1, rng:NextInteger(3, 6) do
		local face = rng:NextInteger(0, 3)
		local y = rng:NextNumber(0.15, 0.9) * hr
		local hw = (face % 2 == 0) and w or d
		local off = rng:NextNumber(-0.3, 0.3) * hw
		local hole = cf * CFrame.Angles(0, face * HALF_PI, 0) * CFrame.new(off, y, -((face % 2 == 0) and d or w) / 2 - 0.3)
		local p = box(m, hole, Vector3.new(rng:NextNumber(8, 22), rng:NextNumber(10, 24), 1.2), SOOT, M.Basalt, NOSHADOW)
		if k == 1 and rng:NextNumber() < 0.35 then
			Util.pointLight(p, rgb(255, 110, 40), 2, 30)
			Util.particles(p, {
				Texture = Util.TEX.fire,
				Color = Util.cs(rgb(255, 160, 60), rgb(255, 60, 20)),
				Size = Util.ns(0, 3, 1, 0),
				Transparency = Util.ns(0, 0.3, 1, 1),
				Lifetime = NumberRange.new(0.6, 1.2),
				Rate = 20,
				Speed = NumberRange.new(3, 6),
				EmissionDirection = Enum.NormalId.Top,
				LightEmission = 1,
			})
		end
	end
	return m
end

-- Concrete chunks scattered around a point.
local function debris(parent, rng, center, radius, count)
	local m = Util.model(parent, "Debris")
	for _ = 1, count do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(0.2, 1) * radius
		local p = ground(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		local s = Vector3.new(rng:NextNumber(3, 12), rng:NextNumber(2, 7), rng:NextNumber(3, 12))
		box(m, CFrame.new(p + Vector3.new(0, s.Y * 0.2, 0)) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, TAU), rng:NextNumber(-0.6, 0.6)), s, Util.vary(rng, CONCRETE_DARK, 0.15), M.Concrete)
	end
	return m
end

local function charredTree(parent, rng, pos)
	local m = Util.model(parent, "CharredTree")
	local bark = rgb(26, 24, 24)
	local top = pos + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(14, 22), rng:NextNumber(-2, 2))
	rod(m, pos - Vector3.new(0, 2, 0), top, 1.8, bark, M.Wood)
	for _ = 1, 3 do
		local from = pos:Lerp(top, rng:NextNumber(0.4, 0.9))
		rod(m, from, from + Vector3.new(rng:NextNumber(-7, 7), rng:NextNumber(2, 7), rng:NextNumber(-7, 7)), 0.8, bark, M.Wood, NOSHADOW)
	end
	return m
end

local function billboard(parent, rng, pos)
	local m = Util.model(parent, "FallenBillboard")
	local yaw = rng:NextNumber(0, TAU)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(rng:NextNumber(0.3, 1.1), 0, rng:NextNumber(-0.2, 0.2))
	local faded = Util.pick(rng, { rgb(120, 60, 50), rgb(70, 90, 110), rgb(140, 120, 70), rgb(90, 90, 96) })
	box(m, cf * CFrame.new(0, 10, 0), Vector3.new(30, 14, 1), faded, M.SmoothPlastic)
	box(m, cf * CFrame.new(0, 10, 0.8), Vector3.new(31, 15, 0.6), rgb(50, 48, 46), M.CorrodedMetal, NOSHADOW)
	for _, x in ipairs({ -10, 10 }) do
		rod(m, (cf * CFrame.new(x, -4, 1)).Position, (cf * CFrame.new(x, 4, 1)).Position, 1.2, rgb(60, 56, 52), M.CorrodedMetal)
	end
	return m
end

---------------------------------------------------------------------------------------------------------
function Ruins.Build(folder, rng)
	Util.log("Building Ashen Remnant...")
	local center = L.RuinsCenter
	local inner = Layout.HUB_RADIUS + Layout.HUB_APRON * 0.8
	local outer = Layout.ISLAND_RADIUS - Layout.BEACH_WIDTH - 250

	local function spot(nearCenter, maxDist)
		for _ = 1, 40 do
			local p
			if nearCenter then
				local a = rng:NextNumber(0, TAU)
				p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * math.sqrt(rng:NextNumber()) * maxDist
			else
				local a = Layout.ZoneAngle.Ruins + rng:NextNumber(-0.85, 0.85) * Layout.HALF_SECTOR
				p = Layout.polar(a, rng:NextNumber(inner, outer))
			end
			local q = Landscape.query(p.X, p.Z)
			if q.land and q.zone == "Ruins" and not q.underwater then
				return Vector3.new(p.X, q.h, p.Z)
			end
		end
		return nil
	end

	-- skyline
	local towers = Util.folder(folder, "Skyscrapers")
	local placed = {}
	local built = 0
	for _ = 1, 160 do
		if built >= 34 then
			break
		end
		local p = spot(true, 1900)
		if p then
			local ok = true
			for _, o in ipairs(placed) do
				if (o - p).Magnitude < 170 then
					ok = false
					break
				end
			end
			if ok then
				table.insert(placed, p)
				local w, d = rng:NextNumber(46, 84), rng:NextNumber(46, 84)
				local roll = rng:NextNumber()
				local yaw = CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
				-- taller towers closer to the old downtown
				local downtown = 1 - math.clamp((p - center).Magnitude / 1900, 0, 1)
				local H = rng:NextNumber(110, 200) + downtown * rng:NextNumber(80, 240)
				if roll < 0.12 then
					-- toppled tower lying in the sand
					local cf = CFrame.new(p + Vector3.new(0, math.min(w, d) * 0.25, 0)) * yaw * CFrame.Angles(HALF_PI * 0.94, 0, 0) * CFrame.new(0, -H * 0.15, 0)
					skyscraper(towers, rng, cf, w, d, H * 0.7)
				elseif roll < 0.3 then
					-- stump
					skyscraper(towers, rng, CFrame.new(p - Vector3.new(0, 6, 0)) * yaw, w, d, rng:NextNumber(26, 70))
				elseif roll < 0.6 then
					local tilt = CFrame.Angles(rng:NextNumber(-0.22, 0.22), 0, rng:NextNumber(-0.22, 0.22))
					skyscraper(towers, rng, CFrame.new(p - Vector3.new(0, rng:NextNumber(12, 30), 0)) * yaw * tilt, w, d, H)
				else
					skyscraper(towers, rng, CFrame.new(p - Vector3.new(0, rng:NextNumber(8, 24), 0)) * yaw, w, d, H)
				end
				-- rubble mound and chunks at the base
				for _ = 1, 3 do
					local a = rng:NextNumber(0, TAU)
					workspace.Terrain:FillBall(p + Vector3.new(math.cos(a) * w * 0.55, -6, math.sin(a) * d * 0.55), rng:NextNumber(14, 26), M.Basalt)
				end
				debris(towers, rng, p, math.max(w, d) * 1.1, rng:NextInteger(6, 11))
				built += 1
			end
		end
		Util.breathe()
	end

	-- wrecks and remains scattered through the dunes
	local wrecks = Util.folder(folder, "Wrecks")
	for _ = 1, 120 do
		local p = spot(rng:NextNumber() < 0.7, 2300) or spot(false)
		if p then
			local yaw = CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
			local roll = rng:NextNumber()
			local cf
			if roll < 0.18 then
				cf = CFrame.new(p + Vector3.new(0, 5.6, 0)) * yaw * CFrame.Angles(0, 0, math.pi)
			elseif roll < 0.3 then
				cf = CFrame.new(p + Vector3.new(0, 3.4, 0)) * yaw * CFrame.Angles(0, 0, HALF_PI)
			else
				cf = CFrame.new(p - Vector3.new(0, rng:NextNumber(0.5, 2.5), 0)) * yaw * CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
			end
			Props.wreckedCar(wrecks, rng, cf)
		end
		Util.breathe()
	end
	for _ = 1, 45 do
		local p = spot(true, 2300)
		if p then
			Props.brokenLamp(wrecks, rng, p)
		end
	end
	for _ = 1, 40 do
		local p = spot(false)
		if p then
			charredTree(wrecks, rng, p)
		end
	end
	for _ = 1, 8 do
		local p = spot(true, 2000)
		if p then
			billboard(wrecks, rng, p - Vector3.new(0, 3, 0))
		end
	end
	for _ = 1, 16 do
		local p = spot(true, 2200)
		if p then
			debris(wrecks, rng, p, 40, rng:NextInteger(5, 9))
		end
	end

	-- smouldering fires
	local fires = Util.model(folder, "Smoulders")
	for k = 1, 12 do
		local p = spot(true, 2000)
		if p then
			Props.smoulder(fires, p + Vector3.new(0, 1, 0), k <= 3)
		end
	end
	Util.log(string.format("  %d skyscrapers", built))
end

return Ruins
