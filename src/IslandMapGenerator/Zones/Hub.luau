--[[
	Solkhar, Citadel of the Sun Throne (central capital)
	A walled desert city on a sandstone mesa: a tiered royal palace with a great
	dome, a sun-clock spire, rings of flat-roofed houses, fountain plazas with
	markets, and five grand gates whose causeways lead down to every region.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local Util = require(script.Parent.Parent.Util)
local Props = require(script.Parent.Parent.Props)
local Config = require(script.Parent.Parent.Config)
local AssetLibrary = require(script.Parent.Parent.AssetLibrary)
local Waterworks = require(script.Parent.Parent.Waterworks)

local Hub = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, ball, column, disc, wedge, cylinder = Util.box, Util.ball, Util.column, Util.disc, Util.wedge, Util.cylinder
local NOCOL = { collide = false }
local NOSHADOW = { shadow = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local TAU = math.pi * 2
local HALF_PI = math.pi / 2

local TOP = Layout.HUB_HEIGHT
local HUB_R = Layout.HUB_RADIUS
local WALL_R = HUB_R - 80
local TIER1_R, TIER1_TOP = 228, TOP + 12
local TIER2_R, TIER2_TOP = 132, TOP + 30

local STONE = rgb(232, 218, 190)
local STONE_DARK = rgb(196, 160, 112)
local MARBLE = rgb(244, 240, 230)
local GOLD = rgb(214, 172, 74)
local TEAL = rgb(30, 116, 124)
local DOOR = rgb(52, 36, 28)
local WINDOW = rgb(34, 28, 30)

local HOUSE_COLORS = {
	rgb(236, 224, 200),
	rgb(226, 204, 166),
	rgb(242, 234, 216),
	rgb(216, 188, 150),
	rgb(234, 214, 180),
	rgb(222, 196, 172),
}
local CLOTH = {
	rgb(30, 116, 124),
	rgb(166, 46, 44),
	rgb(222, 152, 44),
	rgb(62, 62, 132),
	rgb(240, 236, 226),
	rgb(120, 40, 92),
}
local GATE_COLORS = {
	Forest = rgb(78, 164, 88),
	Snow = rgb(150, 200, 238),
	Hollow = rgb(220, 222, 236),
	Ruins = rgb(150, 46, 44),
	Dunes = rgb(232, 172, 64),
}

local function flatCF(pos, dir)
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

-- Facing angles of the five avenues
local AVENUES = {}
for _, id in ipairs(Layout.ZONE_ORDER) do
	table.insert(AVENUES, { id = id, angle = Layout.ZoneAngle[id], dir = Layout.zoneDirection(id) })
end

local function nearAvenue(p, width)
	local d = p.Magnitude
	local theta = math.atan2(p.Z, p.X)
	for _, av in ipairs(AVENUES) do
		local dth = Layout.wrapAngle(theta - av.angle)
		if math.abs(dth) < HALF_PI and math.abs(d * math.sin(dth)) < width then
			return true
		end
	end
	return false
end

-- Small helpers -------------------------------------------------------------------------

-- Arched window/door: dark rectangle with a round top, on a wall facing -Z of cf.
local function arch(parent, cf, w, h, color)
	box(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, 0.6), color, M.SmoothPlastic, NOSHADOW)
	cylinder(parent, cf * CFrame.new(0, h, 0) * CFrame.Angles(0, HALF_PI, 0), 0.6, w, color, M.SmoothPlastic, NOSHADOW)
end

local function obelisk(parent, base, height)
	local m = Util.model(parent, "Obelisk")
	box(m, CFrame.new(base + Vector3.new(0, 2, 0)), Vector3.new(8, 4, 8), STONE_DARK, M.Sandstone)
	box(m, CFrame.new(base + Vector3.new(0, 4 + height / 2, 0)), Vector3.new(4.4, height, 4.4), STONE, M.Limestone)
	Util.hipRoof(m, CFrame.new(base + Vector3.new(0, 4 + height, 0)), 4.4, 4.4, 4, 0.8, GOLD, M.Foil)
	return m
end

-- Palace ------------------------------------------------------------------------------------
local function buildPalace(parent)
	local front = Layout.zoneDirection("Forest")
	local P = flatCF(Vector3.new(0, TIER2_TOP, 0), front) -- local -Z faces the Forest avenue
	local mesh = AssetLibrary.place("Palace", parent, P)
	if mesh then
		mesh.Name = "SunThronePalace"
		mesh.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		for _, x in ipairs({ -14, 14 }) do
			Props.torch(mesh, (P * CFrame.new(x, 0, -52)).Position, 8)
		end
		local crown = AssetLibrary.anchor(mesh, P, Vector3.new(0, 6, 136), "CrownLight")
		Util.pointLight(crown, rgb(255, 210, 130), 2, 40)
		return mesh
	end
	local m = Util.model(parent, "SunThronePalace")

	local function at(x, y, z)
		return P * CFrame.new(x, y, z)
	end

	-- plinth, hall, cornice
	box(m, at(0, 1.5, 6), Vector3.new(118, 3, 88), STONE_DARK, M.Sandstone)
	box(m, at(0, 25, 6), Vector3.new(110, 44, 80), STONE, M.Limestone)
	box(m, at(0, 47.5, 6), Vector3.new(114, 3, 84), STONE_DARK, M.Sandstone)
	box(m, at(0, 20, 6), Vector3.new(111, 1.6, 81), GOLD, M.Foil, NOSHADOW)

	-- roof merlons
	for x = -52, 52, 8 do
		for _, z in ipairs({ -35, 47 }) do
			box(m, at(x, 51, z), Vector3.new(4, 4, 2), STONE, M.Limestone, NOSHADOW)
		end
	end
	for z = -27, 39, 8 do
		for _, x in ipairs({ -56, 56 }) do
			box(m, at(x, 51, z), Vector3.new(2, 4, 4), STONE, M.Limestone, NOSHADOW)
		end
	end

	-- drum and great dome
	local domeCenter = (P * CFrame.new(0, 49, 6)).Position
	column(m, domeCenter, 16, 66, STONE, M.Limestone)
	disc(m, domeCenter + Vector3.new(0, 16, 0), 2, 70, GOLD, M.Foil)
	for k = 0, 11 do
		local a = k / 12 * TAU
		local p = domeCenter + Vector3.new(math.cos(a) * 33, 4, math.sin(a) * 33)
		arch(m, flatCF(p, Vector3.new(math.cos(a), 0, math.sin(a))), 4, 7, WINDOW)
	end
	ball(m, domeCenter + Vector3.new(0, 16, 0), 68, MARBLE, M.Marble)
	disc(m, domeCenter + Vector3.new(0, 26, 0), 2, 59.6, TEAL, M.SmoothPlastic, NOSHADOW)
	local tip = domeCenter + Vector3.new(0, 50, 0)
	column(m, tip - Vector3.new(0, 2, 0), 8, 4, GOLD, M.Foil)
	ball(m, tip + Vector3.new(0, 8, 0), 6, GOLD, M.Foil)
	Util.rod(m, tip + Vector3.new(0, 10, 0), tip + Vector3.new(0, 24, 0), 1.2, GOLD, M.Foil)
	local crown = ball(m, tip + Vector3.new(0, 25, 0), 3, rgb(255, 222, 140), M.Neon, NOSHADOW)
	Util.pointLight(crown, rgb(255, 210, 130), 2, 40)

	-- corner towers
	for _, c in ipairs({ { -55, -34 }, { 55, -34 }, { -55, 46 }, { 55, 46 } }) do
		local base = (P * CFrame.new(c[1], 0, c[2])).Position
		column(m, base, 80, 22, STONE, M.Limestone)
		disc(m, base + Vector3.new(0, 46, 0), 2, 28, STONE_DARK, M.Sandstone)
		disc(m, base + Vector3.new(0, 68, 0), 2, 28, STONE_DARK, M.Sandstone)
		disc(m, base + Vector3.new(0, 80, 0), 2, 26, GOLD, M.Foil)
		for k = 0, 3 do
			local a = k / 4 * TAU + math.pi / 4
			local p = base + Vector3.new(math.cos(a) * 11.1, 54, math.sin(a) * 11.1)
			arch(m, flatCF(p, Vector3.new(math.cos(a), 0, math.sin(a))), 3, 7, WINDOW)
		end
		ball(m, base + Vector3.new(0, 80, 0), 22, MARBLE, M.Marble)
		Util.rod(m, base + Vector3.new(0, 90, 0), base + Vector3.new(0, 102, 0), 1, GOLD, M.Foil)
		ball(m, base + Vector3.new(0, 102, 0), 2.4, GOLD, M.Foil)
	end

	-- side wings with small domes
	for _, sx in ipairs({ -1, 1 }) do
		box(m, at(sx * 75, 15, 10), Vector3.new(40, 30, 60), STONE, M.Limestone)
		box(m, at(sx * 75, 31, 10), Vector3.new(42, 2, 62), STONE_DARK, M.Sandstone)
		ball(m, (at(sx * 75, 32, 10)).Position, 24, MARBLE, M.Marble)
		ball(m, (at(sx * 75, 45, 10)).Position, 2.4, GOLD, M.Foil)
		for z = -10, 30, 13 do
			arch(m, at(sx * 95.4, 8, z) * CFrame.Angles(0, -sx * HALF_PI, 0), 4, 10, WINDOW)
		end
	end

	-- facade windows (two rows) on front and back
	for _, row in ipairs({ 8, 28 }) do
		for x = -45, 45, 13 do
			if math.abs(x) > 12 then
				arch(m, at(x, row, -34.3), 5, 9, WINDOW)
				arch(m, at(x, row, 46.3) * CFrame.Angles(0, math.pi, 0), 5, 9, WINDOW)
			end
		end
	end

	-- grand door with a sun emblem
	arch(m, at(0, 0, -34.4), 18, 26, DOOR)
	local sun = (at(0, 36, -34.8)).Position
	cylinder(m, CFrame.lookAt(sun, sun + front) * CFrame.Angles(0, HALF_PI, 0), 0.8, 12, GOLD, M.Foil, NOSHADOW)
	for k = 0, 11 do
		local a = k / 12 * TAU
		local off = (P * CFrame.Angles(0, 0, a)).RightVector
		Util.beam(m, sun + off * 6.5, sun + off * 10.5, 1.2, 0.5, GOLD, M.Foil, NOCOL_NOSHADOW)
	end

	-- front colonnade
	for x = -42, 42, 12 do
		local base = (at(x, 0, -46)).Position
		box(m, CFrame.new(base + Vector3.new(0, 1, 0)), Vector3.new(6, 2, 6), STONE_DARK, M.Sandstone)
		column(m, base + Vector3.new(0, 2, 0), 32, 4.6, MARBLE, M.Marble)
		box(m, CFrame.new(base + Vector3.new(0, 35, 0)), Vector3.new(6.4, 2, 6.4), GOLD, M.Foil)
	end
	box(m, at(0, 39, -41), Vector3.new(96, 4, 14), STONE, M.Limestone)
	box(m, at(0, 41.6, -41), Vector3.new(98, 1.2, 15), STONE_DARK, M.Sandstone)
	box(m, at(0, 0.5, -42), Vector3.new(98, 1, 18), STONE_DARK, M.Sandstone)

	-- banners between the columns
	for _, x in ipairs({ -30, -18, 18, 30 }) do
		box(m, at(x, 26, -47.2), Vector3.new(5, 18, 0.3), TEAL, M.Fabric, NOCOL_NOSHADOW)
		box(m, at(x, 17.4, -47.3), Vector3.new(5, 1.2, 0.3), GOLD, M.Foil, NOCOL_NOSHADOW)
	end

	-- braziers flanking the door
	for _, x in ipairs({ -14, 14 }) do
		Props.torch(m, (at(x, 0, -52)).Position, 8)
	end
	return m
end

-- Sun-clock spire ------------------------------------------------------------------------------
local function buildClockSpire(parent)
	local a = Layout.ZoneAngle.Forest + TAU / 10
	local base = Vector3.new(math.cos(a) * 186, TIER1_TOP, math.sin(a) * 186)
	local face = Vector3.new(-math.cos(a), 0, -math.sin(a))
	local cf = flatCF(base, -face)
	local mesh = AssetLibrary.place("ClockSpire", parent, cf)
	if mesh then
		mesh.Name = "SunClockSpire"
		mesh.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		local bell = AssetLibrary.anchor(mesh, cf, Vector3.new(0, 0, 165), "BellLight")
		Util.pointLight(bell, rgb(255, 200, 120), 1.5, 34)
		return mesh, base
	end
	local m = Util.model(parent, "SunClockSpire")

	box(m, cf * CFrame.new(0, 3, 0), Vector3.new(32, 6, 32), STONE_DARK, M.Sandstone)
	box(m, cf * CFrame.new(0, 66, 0), Vector3.new(24, 120, 24), STONE, M.Limestone)
	for _, c in ipairs({ { -12, -12 }, { 12, -12 }, { -12, 12 }, { 12, 12 } }) do
		box(m, cf * CFrame.new(c[1], 66, c[2]), Vector3.new(3.4, 120, 3.4), STONE_DARK, M.Sandstone)
	end
	for y = 30, 120, 24 do
		box(m, cf * CFrame.new(0, y, 0), Vector3.new(26, 1.6, 26), STONE_DARK, M.Sandstone, NOSHADOW)
	end
	for y = 20, 110, 24 do
		for s = 0, 3 do
			arch(m, cf * CFrame.Angles(0, s * HALF_PI, 0) * CFrame.new(0, y, -12.3), 3, 8, WINDOW)
		end
	end

	-- clock chamber
	box(m, cf * CFrame.new(0, 141, 0), Vector3.new(30, 30, 30), STONE, M.Limestone)
	box(m, cf * CFrame.new(0, 156.5, 0), Vector3.new(33, 2, 33), GOLD, M.Foil)
	for s = 0, 3 do
		local f = cf * CFrame.Angles(0, s * HALF_PI, 0) * CFrame.new(0, 141, -15)
		cylinder(m, f * CFrame.new(0, 0, -0.4) * CFrame.Angles(0, HALF_PI, 0), 0.8, 25, GOLD, M.Foil, NOSHADOW)
		local dial = cylinder(m, f * CFrame.new(0, 0, -0.9) * CFrame.Angles(0, HALF_PI, 0), 0.6, 22, rgb(250, 244, 226), M.SmoothPlastic, NOSHADOW)
		Util.surfaceLight(dial, Enum.NormalId.Right, rgb(255, 230, 180), 0.8, 14, 80)
		for h = 0, 11 do
			local ang = h / 12 * TAU
			local len = h % 3 == 0 and 2.6 or 1.2
			box(m, f * CFrame.new(math.sin(ang) * 9, math.cos(ang) * 9, -1.3) * CFrame.Angles(0, 0, -ang), Vector3.new(0.6, len, 0.3), rgb(40, 30, 24), M.SmoothPlastic, NOCOL_NOSHADOW)
		end
		-- hands at ten past ten
		local hour, minute = -math.pi / 3, math.pi / 3
		box(m, f * CFrame.new(0, 0, -1.5) * CFrame.Angles(0, 0, -hour) * CFrame.new(0, 2.6, 0), Vector3.new(1, 5.2, 0.3), rgb(40, 30, 24), M.Metal, NOCOL_NOSHADOW)
		box(m, f * CFrame.new(0, 0, -1.6) * CFrame.Angles(0, 0, -minute) * CFrame.new(0, 3.6, 0), Vector3.new(0.6, 7.2, 0.3), rgb(40, 30, 24), M.Metal, NOCOL_NOSHADOW)
	end

	-- open belfry, bell and dome
	for _, c in ipairs({ { -12, -12 }, { 12, -12 }, { -12, 12 }, { 12, 12 } }) do
		box(m, cf * CFrame.new(c[1], 167, c[2]), Vector3.new(4, 20, 4), STONE, M.Limestone)
	end
	box(m, cf * CFrame.new(0, 178, 0), Vector3.new(30, 2, 30), STONE_DARK, M.Sandstone)
	local bellPos = (cf * CFrame.new(0, 166, 0)).Position
	ball(m, bellPos, 9, GOLD, M.Foil)
	column(m, bellPos - Vector3.new(0, 4, 0), 4, 9.6, GOLD, M.Foil)
	local glow = ball(m, bellPos - Vector3.new(0, 6, 0), 1, rgb(255, 210, 140), M.Neon, NOCOL_NOSHADOW)
	Util.pointLight(glow, rgb(255, 200, 120), 1.5, 34)
	ball(m, (cf * CFrame.new(0, 179, 0)).Position, 26, MARBLE, M.Marble)
	Util.rod(m, (cf * CFrame.new(0, 190, 0)).Position, (cf * CFrame.new(0, 208, 0)).Position, 1.4, GOLD, M.Foil)
	for k = 0, 7 do
		local ang = k / 8 * TAU
		local o = (cf * CFrame.new(0, 200, 0)).Position
		Util.rod(m, o, o + Vector3.new(math.cos(ang) * 5, 1.5, math.sin(ang) * 5), 0.5, GOLD, M.Foil, NOCOL_NOSHADOW)
	end
	ball(m, (cf * CFrame.new(0, 209, 0)).Position, 3, GOLD, M.Foil)
	return m, base
end

-- Platforms and stairs ---------------------------------------------------------------------------
local function buildTiers(parent)
	local m = Util.model(parent, "RoyalTerraces")
	local function tier(radius, bottom, top)
		disc(m, Vector3.new(0, (bottom + top) / 2, 0), top - bottom, radius * 2, STONE, M.Limestone)
		disc(m, Vector3.new(0, top - 0.4, 0), 1.2, radius * 2 + 3, STONE_DARK, M.Sandstone, NOSHADOW)
		disc(m, Vector3.new(0, bottom + 2, 0), 1, radius * 2 + 1, GOLD, M.Foil, NOSHADOW)
	end
	tier(TIER1_R, TOP - 4, TIER1_TOP)
	tier(TIER2_R, TIER1_TOP - 1, TIER2_TOP)

	local function stairs(dir, rFrom, bottomY, topY)
		local steps = math.ceil((topY - bottomY) / 1.5)
		local rise = (topY - bottomY) / steps
		for k = 1, steps do
			local r = rFrom + (k - 0.5) * 2.6
			local stepTop = topY - (k - 1) * rise
			local center = dir * r
			box(m, flatCF(Vector3.new(center.X, (stepTop + bottomY - 2) / 2, center.Z), dir), Vector3.new(34, stepTop - bottomY + 2, 2.7), STONE, M.Limestone)
		end
		local foot = dir * (rFrom + steps * 2.6 + 4)
		local side = Vector3.new(-dir.Z, 0, dir.X)
		for _, s in ipairs({ -1, 1 }) do
			obelisk(m, Vector3.new(foot.X, bottomY, foot.Z) + side * s * 22, 20)
		end
	end
	for _, av in ipairs(AVENUES) do
		stairs(av.dir, TIER1_R - 1, TOP, TIER1_TOP)
		stairs(av.dir, TIER2_R - 1, TIER1_TOP, TIER2_TOP)
	end
	return m
end

-- Houses --------------------------------------------------------------------------------------------
local function house(parent, rng, cf, w, d)
	local m = Util.model(parent, "House")
	local color = Util.pick(rng, HOUSE_COLORS)
	local trim = Util.vary(rng, STONE_DARK, 0.06)
	local roll = rng:NextNumber()
	local levels = roll < 0.3 and 1 or (roll < 0.8 and 2 or 3)
	local h = levels * 12

	box(m, cf * CFrame.new(0, h / 2 - 1, 0), Vector3.new(w, h + 2, d), color, M.Plaster)
	box(m, cf * CFrame.new(0, h + 0.6, 0), Vector3.new(w + 1.2, 1.2, d + 1.2), trim, M.Sandstone, NOSHADOW)
	box(m, cf * CFrame.new(0, 0.3, 0), Vector3.new(w + 0.8, 1.6, d + 0.8), trim, M.Sandstone, NOSHADOW)

	-- door, windows
	arch(m, cf * CFrame.new(rng:NextNumber(-w / 4, w / 4), 0, -d / 2 - 0.2), 4.5, 7, DOOR)
	for lv = 1, levels do
		local y = (lv - 1) * 12 + (lv == 1 and 5 or 3.5)
		if lv > 1 or w > 24 then
			local xs = w > 24 and { -w / 4, w / 4 } or { 0 }
			for _, x in ipairs(xs) do
				if lv > 1 or math.abs(x) > 4 then
					arch(m, cf * CFrame.new(x, y, -d / 2 - 0.2), 3, 4.5, WINDOW)
				end
			end
		end
		if rng:NextNumber() < 0.6 then
			arch(m, cf * CFrame.new(w / 2 + 0.2, y, 0) * CFrame.Angles(0, -HALF_PI, 0), 3, 4.5, WINDOW)
		end
	end

	-- awning over the door
	if rng:NextNumber() < 0.55 then
		local cloth = Util.pick(rng, CLOTH)
		wedge(m, cf * CFrame.new(0, 9.2, -d / 2 - 2.2), Vector3.new(w * 0.6, 1.6, 4.4), cloth, M.Fabric, NOCOL_NOSHADOW)
	end

	-- rooftop: dome, upper room or clutter
	local r = rng:NextNumber()
	if r < 0.28 then
		local dd = math.min(w, d) * 0.62
		disc(m, (cf * CFrame.new(0, h + 1.2, 0)).Position, 2, dd + 2, trim, M.Sandstone, NOSHADOW)
		ball(m, (cf * CFrame.new(0, h + 2, 0)).Position, dd, rng:NextNumber() < 0.3 and TEAL or MARBLE, M.Marble)
		ball(m, (cf * CFrame.new(0, h + 2 + dd / 2, 0)).Position, 1.6, GOLD, M.Foil, NOCOL)
	elseif r < 0.5 then
		box(m, cf * CFrame.new(w * 0.2, h + 4.5, d * 0.2), Vector3.new(w * 0.45, 8, d * 0.45), color, M.Plaster)
		box(m, cf * CFrame.new(w * 0.2, h + 9, d * 0.2), Vector3.new(w * 0.45 + 1, 1, d * 0.45 + 1), trim, M.Sandstone, NOSHADOW)
	else
		for _ = 1, rng:NextInteger(1, 3) do
			local p = cf * CFrame.new(rng:NextNumber(-w / 3, w / 3), h + 1.8, rng:NextNumber(-d / 3, d / 3))
			if rng:NextNumber() < 0.5 then
				ball(m, p.Position, rng:NextNumber(1.8, 2.8), rgb(176, 96, 60), M.Slate, NOCOL)
			else
				box(m, p * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(2.4, 2.4, 2.4), rgb(140, 104, 66), M.WoodPlanks, NOCOL)
			end
		end
		if rng:NextNumber() < 0.4 then
			local cloth = Util.pick(rng, CLOTH)
			box(m, cf * CFrame.new(0, h + 6, 0) * CFrame.Angles(0.08, 0, 0), Vector3.new(w * 0.7, 0.3, d * 0.6), cloth, M.Fabric, NOCOL)
			for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
				column(m, (cf * CFrame.new(c[1] * w * 0.33, h + 1, c[2] * d * 0.28)).Position, 5, 0.5, rgb(90, 70, 50), M.Wood, NOCOL_NOSHADOW)
			end
		end
	end
	return m
end

-- Plaza with fountain and market stalls ------------------------------------------------------------
local function waterJet(parent, pos, dir, rate, speed)
	local p = box(parent, CFrame.lookAt(pos, pos + dir), Vector3.new(0.6, 0.6, 0.6), GOLD, M.SmoothPlastic, { collide = false, shadow = false, transparency = 1 })
	p.Name = "WaterJet"
	p.CanQuery = false
	Util.particles(p, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(rgb(210, 240, 255), rgb(130, 205, 240)),
		Size = Util.ns(0, 0.45, 1, 0.2),
		Transparency = Util.ns(0, 0.1, 1, 0.8),
		Lifetime = NumberRange.new(0.7, 1.4),
		Rate = rate,
		Speed = NumberRange.new(speed * 0.85, speed),
		SpreadAngle = Vector2.new(8, 8),
		Acceleration = Vector3.new(0, -30, 0),
		EmissionDirection = Enum.NormalId.Front,
	})
	return p
end

-- Fountain around one of Waterworks' grid-aligned basins (the water itself is terrain water).
local function fountain(parent, center)
	local base = Vector3.new(center.X, Waterworks.BASIN_TOP - 2, center.Z) -- water line sits 2 above the base
	local m = AssetLibrary.place("Fountain", parent, CFrame.new(base))
	local spout = base + Vector3.new(0, 13.6, 0)
	if not m then
		m = Util.model(parent, "Fountain")
		local h, b = Waterworks.BASIN_HALF, Waterworks.BOWL_HALF
		for _, s in ipairs({ -1, 1 }) do
			box(m, CFrame.new(base + Vector3.new(0, 1.3, s * (h + 1.3))), Vector3.new(2 * h + 5.2, 4.6, 2.6), STONE, M.Limestone)
			box(m, CFrame.new(base + Vector3.new(s * (h + 1.3), 1.3, 0)), Vector3.new(2.6, 4.6, 2 * h), STONE, M.Limestone)
			box(m, CFrame.new(base + Vector3.new(0, 8.05, s * (b + 0.7))), Vector3.new(2 * b + 2.8, 5.1, 1.4), STONE, M.Limestone)
			box(m, CFrame.new(base + Vector3.new(s * (b + 0.7), 8.05, 0)), Vector3.new(1.4, 5.1, 2 * b), STONE, M.Limestone)
		end
		box(m, CFrame.new(base + Vector3.new(0, -6.2, 0)), Vector3.new(2 * h, 0.4, 2 * h), TEAL, M.CeramicTiles, NOSHADOW)
		column(m, base + Vector3.new(0, -6.4, 0), 12, 4, STONE, M.Limestone)
		box(m, CFrame.new(base + Vector3.new(0, 5.7, 0)), Vector3.new(2 * b + 2.8, 0.6, 2 * b + 2.8), STONE_DARK, M.Sandstone)
		ball(m, base + Vector3.new(0, 12, 0), 2.4, GOLD, M.Foil)
		spout = base + Vector3.new(0, 12.4, 0)
	end
	m.Name = "Fountain"
	waterJet(m, spout, Vector3.new(0, 1, 0), 70, 13)
	for _, d in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
		waterJet(m, base + d * 5.8 + Vector3.new(0, 8.6, 0), (d + Vector3.new(0, 0.3, 0)).Unit, 18, 6)
	end
	return m
end

-- Reflecting pools beside the palace approach (terrain water inside marble rims).
local function buildPools(parent)
	for _, pool in ipairs(Waterworks.palacePools()) do
		local m = Util.model(parent, "ReflectingPool")
		local mn, mx = pool.min, pool.max
		local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
		local sx, sz = mx.X - mn.X, mx.Z - mn.Z
		local h = mx.Y + 1 - pool.floorY
		local y = pool.floorY + h / 2
		box(m, CFrame.new(cx, pool.floorY + 0.05, cz), Vector3.new(sx, 0.1, sz), TEAL, M.CeramicTiles, NOSHADOW)
		box(m, CFrame.new(cx, y, mn.Z - 1), Vector3.new(sx + 4, h, 2), MARBLE, M.Marble)
		box(m, CFrame.new(cx, y, mx.Z + 1), Vector3.new(sx + 4, h, 2), MARBLE, M.Marble)
		box(m, CFrame.new(mn.X - 1, y, cz), Vector3.new(2, h, sz), MARBLE, M.Marble)
		box(m, CFrame.new(mx.X + 1, y, cz), Vector3.new(2, h, sz), MARBLE, M.Marble)
		local long = sx > sz and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
		local len = math.max(sx, sz)
		for k = 1, 3 do
			local p = Vector3.new(cx, mx.Y - 0.3, cz) + long * (len * (k / 4 - 0.5))
			ball(m, p, 1.4, GOLD, M.Foil)
			waterJet(m, p + Vector3.new(0, 0.6, 0), Vector3.new(0, 1, 0), 30, 9)
		end
	end
end

local function stall(parent, rng, cf)
	local m = Util.model(parent, "MarketStall")
	local cloth = Util.pick(rng, CLOTH)
	local wood = rgb(110, 80, 54)
	for _, c in ipairs({ { -5, -4 }, { 5, -4 }, { -5, 4 }, { 5, 4 } }) do
		column(m, (cf * CFrame.new(c[1], 0, c[2])).Position, c[2] < 0 and 9 or 10.5, 0.7, wood, M.Wood, NOSHADOW)
	end
	box(m, cf * CFrame.new(0, 10, 0) * CFrame.Angles(-0.18, 0, 0), Vector3.new(12, 0.3, 10), cloth, M.Fabric, NOCOL)
	box(m, cf * CFrame.new(0, 9.3, -5.1), Vector3.new(12, 1.4, 0.3), Util.pick(rng, CLOTH), M.Fabric, NOCOL_NOSHADOW)
	box(m, cf * CFrame.new(0, 1.8, -2.5), Vector3.new(10, 3.6, 3), wood, M.WoodPlanks)
	local goods = { rgb(232, 120, 40), rgb(200, 40, 50), rgb(240, 200, 60), rgb(120, 170, 60), rgb(150, 90, 180) }
	for g = -1, 1 do
		local p = cf * CFrame.new(g * 3, 4.1, -2.5)
		if rng:NextNumber() < 0.5 then
			box(m, p * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Vector3.new(2.4, 1, 2), Util.pick(rng, goods), M.Fabric, NOCOL_NOSHADOW)
		else
			ball(m, p.Position + Vector3.new(0, 0.4, 0), 1.8, Util.pick(rng, goods), M.SmoothPlastic, NOCOL_NOSHADOW)
		end
	end
	return m
end

-- Walls and gates --------------------------------------------------------------------------------------
-- Dark slate plaque showing text on its front (-Z) face.
local function namePlaque(parent, cf, text)
	local plaque = box(parent, cf, Vector3.new(30, 6.4, 0.4), rgb(48, 40, 34), M.Slate, NOSHADOW)
	plaque.Name = "NamePlaque"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(720, 150)
	gui.LightInfluence = 0.2
	gui.Parent = plaque
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = rgb(240, 206, 120)
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.Parent = gui
	return plaque
end

local function buildWalls(parent)
	local m = Util.model(parent, "CityWalls")
	local segments = 84
	local gateHalf = (Layout.ROAD_WIDTH / 2 + 16) / WALL_R
	local wallH = 34

	local function inGate(a, extra)
		for _, av in ipairs(AVENUES) do
			if math.abs(Layout.wrapAngle(a - av.angle)) < gateHalf + (extra or 0) then
				return av
			end
		end
		return nil
	end

	for s = 0, segments - 1 do
		local a = (s + 0.5) / segments * TAU
		if not inGate(a, 0.02) then
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local tangent = Vector3.new(-dir.Z, 0, dir.X)
			local pos = dir * WALL_R + Vector3.new(0, TOP - 4 + wallH / 2, 0)
			local len = TAU * WALL_R / segments + 1.2
			local cf = CFrame.lookAt(pos, pos + tangent)
			box(m, cf, Vector3.new(12, wallH + 4, len), STONE, M.Sandstone)
			box(m, cf * CFrame.new(0, wallH / 2 + 2.4, 0), Vector3.new(13, 1, len), STONE_DARK, M.Sandstone, NOSHADOW)
			for k = -1, 1, 2 do
				box(m, cf * CFrame.new(5.5, wallH / 2 + 5, k * len / 4), Vector3.new(2.4, 5, len / 4), STONE, M.Sandstone, NOSHADOW)
			end
			local towerBase = dir * (WALL_R + 3) + Vector3.new(0, TOP, 0)
			if s % 7 == 3 and not inGate(a, 0.08) and AssetLibrary.place("WallTower", m, CFrame.lookAt(towerBase, towerBase + dir)) then
				-- detailed tower mesh placed
			elseif s % 7 == 3 and not inGate(a, 0.08) then
				local base = dir * (WALL_R + 3) + Vector3.new(0, TOP - 4, 0)
				column(m, base, wallH + 18, 26, STONE, M.Sandstone)
				disc(m, base + Vector3.new(0, wallH + 18, 0), 2, 30, STONE_DARK, M.Sandstone)
				ball(m, base + Vector3.new(0, wallH + 19, 0), 22, MARBLE, M.Marble)
				Util.rod(m, base + Vector3.new(0, wallH + 28, 0), base + Vector3.new(0, wallH + 38, 0), 0.8, GOLD, M.Foil)
				local flag = box(m, CFrame.new(base + Vector3.new(2.5, wallH + 36, 0)), Vector3.new(5, 3, 0.3), TEAL, M.Fabric, NOCOL_NOSHADOW)
				flag.Name = "Pennant"
			end
		end
	end

	-- the five gates
	for _, av in ipairs(AVENUES) do
		local color = GATE_COLORS[av.id]
		local ground = av.dir * WALL_R + Vector3.new(0, TOP, 0)
		local gateCF = CFrame.lookAt(ground, ground + av.dir) -- front faces out of the city
		local mesh = AssetLibrary.place("CityGate", m, gateCF, 1, { Fabric = color })
		if mesh then
			mesh.Name = "Gate_" .. av.id
			local name = string.upper(Layout.ZoneInfo[av.id].name)
			namePlaque(mesh, gateCF * CFrame.new(AssetLibrary.fromBlender(0, -9.75, 45.2)), name)
			namePlaque(mesh, gateCF * CFrame.new(AssetLibrary.fromBlender(0, 9.25, 45.2)) * CFrame.Angles(0, math.pi, 0), name)
			for _, x in ipairs({ -38, 38 }) do
				local fx = AssetLibrary.anchor(mesh, gateCF, Vector3.new(x, -19.5, 13.6), "Brazier")
				Util.fire(fx, 4, 8)
				Util.pointLight(fx, rgb(255, 160, 80), 2, 36)
			end
			continue
		end
		local gm = Util.model(m, "Gate_" .. av.id)
		local dir = av.dir
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local center = dir * WALL_R + Vector3.new(0, TOP - 4, 0)
		local gap = Layout.ROAD_WIDTH + 8
		for _, s in ipairs({ -1, 1 }) do
			local base = center + side * s * (gap / 2 + 14)
			column(gm, base, 64, 30, STONE, M.Sandstone)
			disc(gm, base + Vector3.new(0, 64, 0), 2.4, 34, GOLD, M.Foil)
			ball(gm, base + Vector3.new(0, 65, 0), 28, MARBLE, M.Marble)
			Util.rod(gm, base + Vector3.new(0, 78, 0), base + Vector3.new(0, 92, 0), 1, GOLD, M.Foil)
			ball(gm, base + Vector3.new(0, 92, 0), 2.6, GOLD, M.Foil)
			local brazier = disc(gm, base + dir * 17 + Vector3.new(0, 12, 0), 1.2, 4, GOLD, M.Metal)
			Util.fire(brazier, 4, 8)
			Util.pointLight(brazier, rgb(255, 160, 80), 2, 36)
		end
		-- stone arch over the road made of voussoirs
		local archBase = center + Vector3.new(0, 30, 0)
		local span = gap + 4
		for k = 0, 8 do
			local t0, t1 = k / 9 * math.pi, (k + 1) / 9 * math.pi
			local p0 = archBase + side * (math.cos(t0) * span / 2) + Vector3.new(0, math.sin(t0) * 12, 0)
			local p1 = archBase + side * (math.cos(t1) * span / 2) + Vector3.new(0, math.sin(t1) * 12, 0)
			local mid = (p0 + p1) / 2
			box(gm, CFrame.lookAt(mid, p1, dir), Vector3.new(4, 14, (p1 - p0).Magnitude + 0.6), STONE, M.Sandstone)
		end
		local lintelCF = CFrame.lookAt(archBase + Vector3.new(0, 18, 0), archBase + Vector3.new(0, 18, 0) + side)
		box(gm, lintelCF, Vector3.new(14, 8, span + 18), STONE, M.Sandstone)
		box(gm, lintelCF * CFrame.new(0, 4.6, 0), Vector3.new(15, 1.2, span + 20), GOLD, M.Foil, NOSHADOW)

		-- plaque with the destination name, facing out of the city, and again facing the palace
		local name = string.upper(Layout.ZoneInfo[av.id].name)
		namePlaque(gm, CFrame.lookAt(archBase + dir * 7.2 + Vector3.new(0, 18, 0), archBase + dir * 20 + Vector3.new(0, 18, 0)), name)
		namePlaque(gm, CFrame.lookAt(archBase - dir * 7.2 + Vector3.new(0, 18, 0), archBase - dir * 20 + Vector3.new(0, 18, 0)), name)

		-- hanging banners in the region's colour
		for _, s in ipairs({ -1, 1 }) do
			local p = center + side * s * (gap / 2 + 14) + dir * 15.4 + Vector3.new(0, 40, 0)
			box(gm, CFrame.lookAt(p, p + dir), Vector3.new(8, 26, 0.3), color, M.Fabric, NOCOL_NOSHADOW)
			box(gm, CFrame.lookAt(p, p + dir) * CFrame.new(0, -13.6, 0), Vector3.new(8, 1.2, 0.4), GOLD, M.Foil, NOCOL_NOSHADOW)
		end
	end
	return m
end

-- Causeways down from the gates ----------------------------------------------------------------------
local function buildCauseways(parent)
	local m = Util.model(parent, "Causeways")
	for _, av in ipairs(AVENUES) do
		local dir = av.dir
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local half = Layout.ROAD_WIDTH / 2 + 1.2
		local from, to = HUB_R - 40, HUB_R + Layout.RAMP_LENGTH - 10
		local step = 28
		local r = from
		local index = 0
		while r < to do
			local r2 = math.min(r + step, to)
			for _, s in ipairs({ -1, 1 }) do
				local pa = dir * r + side * s * half
				local pb = dir * r2 + side * s * half
				local a = Vector3.new(pa.X, Landscape.heightAt(pa.X, pa.Z) + 1.6, pa.Z)
				local b = Vector3.new(pb.X, Landscape.heightAt(pb.X, pb.Z) + 1.6, pb.Z)
				Util.beam(m, a, b, 2.4, 5, STONE, M.Sandstone)
				if index % 4 == 0 then
					Props.streetLamp(m, a + Vector3.new(0, 1.6, 0) - side * s * 0.2, 12)
				end
			end
			r = r2
			index += 1
			Util.breathe()
		end
		-- guardian obelisks at the foot of each causeway
		local foot = dir * (to + 14)
		for _, s in ipairs({ -1, 1 }) do
			local p = foot + side * s * (half + 8)
			obelisk(m, Vector3.new(p.X, Landscape.heightAt(p.X, p.Z) - 1, p.Z), 26)
		end
	end
	return m
end

-- Spawn plaza -----------------------------------------------------------------------------------------
local function buildSpawn(parent)
	local m = Util.model(parent, "HubSpawnPlaza")
	local dir = Layout.zoneDirection("Forest")
	local p = dir * 196 + Vector3.new(0, TIER1_TOP, 0)
	disc(m, p + Vector3.new(0, 0.2, 0), 0.4, 38, STONE_DARK, M.Sandstone, NOSHADOW)
	disc(m, p + Vector3.new(0, 0.4, 0), 0.4, 32, GOLD, M.Foil, NOSHADOW)
	disc(m, p + Vector3.new(0, 0.6, 0), 0.4, 20, MARBLE, M.Marble, NOSHADOW)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn_Hub"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(p + Vector3.new(0, 0.9, 0))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = M.Marble
	spawn.Color = MARBLE
	spawn.Transparency = 0.3
	spawn.Enabled = Config.PLAYER_START == "Hub"
	spawn.Parent = m
	return m
end

---------------------------------------------------------------------------------------------------------
function Hub.Build(folder, rng)
	Util.log("Building Solkhar (capital)...")
	buildTiers(folder)
	buildPools(folder)
	buildPalace(folder)
	local _, clockBase = buildClockSpire(folder)
	buildWalls(folder)
	Util.breathe()
	buildCauseways(folder)
	buildSpawn(folder)

	-- fountain plazas on each avenue
	local plazas = {}
	local market = Util.model(folder, "Markets")
	local fountainCenters = Waterworks.fountainCenters()
	for i, av in ipairs(AVENUES) do
		local c = fountainCenters[i]
		local center = Vector3.new(c.X, 0, c.Z)
		table.insert(plazas, center)
		fountain(market, c)
		local side = Vector3.new(-av.dir.Z, 0, av.dir.X)
		for _, off in ipairs({ { 30, -24 }, { 30, 24 }, { -30, -24 }, { -30, 24 } }) do
			local pos = center + side * off[1] + av.dir * off[2] + Vector3.new(0, TOP, 0)
			local cf = flatCF(pos, center + Vector3.new(0, TOP, 0) - pos)
			if not AssetLibrary.place("MarketStall", market, cf, 1, { Fabric = Util.pick(rng, CLOTH), Fabric2 = Util.pick(rng, CLOTH) }) then
				stall(market, rng, cf)
			end
		end
		for k = 0, 5 do
			local a = k / 6 * TAU + 0.3
			local p = center + Vector3.new(math.cos(a) * 46, 0, math.sin(a) * 46)
			if not nearAvenue(p, 22) then
				Util.place(Props.randomTemplate(rng, Props.palms()), market, p + Vector3.new(0, TOP, 0), rng:NextNumber(0, TAU), rng:NextNumber(0.9, 1.15))
			end
		end
	end

	-- palms and lamps lining the avenues
	local avenueDeco = Util.model(folder, "AvenueTrees")
	for _, av in ipairs(AVENUES) do
		local side = Vector3.new(-av.dir.Z, 0, av.dir.X)
		for r = 316, 520, 34 do
			if math.abs(r - 412) > 56 then
				for _, s in ipairs({ -1, 1 }) do
					local p = av.dir * r + side * s * 22 + Vector3.new(0, TOP, 0)
					if (r // 34) % 2 == 0 then
						Util.place(Props.randomTemplate(rng, Props.palms()), avenueDeco, p, rng:NextNumber(0, TAU), rng:NextNumber(0.9, 1.1))
					else
						Props.streetLamp(avenueDeco, p, 13)
					end
				end
			end
		end
	end

	-- houses in rings between the avenues
	local houses = Util.model(folder, "Houses")
	local count = 0
	local houseKinds = AssetLibrary.has("House_A") and AssetLibrary.has("House_B") and AssetLibrary.has("House_C") and {
		{ name = "House_A", w = 28 },
		{ name = "House_B", w = 29 },
		{ name = "House_C", w = 21 },
	} or nil
	for ringR = 322, WALL_R - 68, 42 do
		local a = rng:NextNumber(0, 0.2)
		while a < TAU do
			local kind = houseKinds and Util.pick(rng, houseKinds)
			local scale = kind and rng:NextNumber(0.88, 1.12) or 1
			local w = kind and kind.w * scale or rng:NextNumber(20, 32)
			local d = kind and 24 or rng:NextNumber(20, 30)
			local center = Vector3.new(math.cos(a) * ringR, 0, math.sin(a) * ringR)
			local blocked = nearAvenue(center, 26 + w / 2)
				or (clockBase and (center - Vector3.new(clockBase.X, 0, clockBase.Z)).Magnitude < 40)
			for _, pz in ipairs(plazas) do
				if (center - pz).Magnitude < 66 then
					blocked = true
				end
			end
			if not blocked then
				if rng:NextNumber() < 0.1 then
					Util.place(Props.randomTemplate(rng, Props.palms()), houses, center + Vector3.new(0, TOP, 0), rng:NextNumber(0, TAU), 1)
				else
					local jitter = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
					local pos = center + jitter + Vector3.new(0, TOP, 0)
					if kind then
						AssetLibrary.place(kind.name, houses, flatCF(pos, -center), scale, {
							Plaster = Util.pick(rng, HOUSE_COLORS),
							Fabric = Util.pick(rng, CLOTH),
						})
					else
						house(houses, rng, flatCF(pos, -center), w, d)
					end
					count += 1
				end
			end
			a += (w + rng:NextNumber(6, 12)) / ringR
			Util.breathe()
		end
	end
	Util.log(string.format("  %d houses", count))

	-- palms on the ledge outside the walls
	local ledge = Util.model(folder, "LedgePalms")
	for k = 0, 39 do
		local a = k / 40 * TAU + rng:NextNumber(-0.04, 0.04)
		local p = Vector3.new(math.cos(a), 0, math.sin(a)) * (WALL_R + 34)
		if not nearAvenue(p, 40) then
			local h = Landscape.heightAt(p.X, p.Z)
			if h > TOP - 3 then
				Util.place(Props.randomTemplate(rng, Props.palms()), ledge, Vector3.new(p.X, h, p.Z), rng:NextNumber(0, TAU), rng:NextNumber(0.9, 1.2))
			end
		end
	end
end

return Hub
