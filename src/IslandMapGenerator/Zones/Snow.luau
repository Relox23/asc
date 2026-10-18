--[[
	Shirayuki Vale
	A deep, silent winter forest of snow-laden pines covering most of the region.
	In a valley sits a very small Japanese village by a frozen pond. Far beyond,
	a long stone stairway lined with lanterns and torii climbs a mountain to
	Ryuudou Temple, with its gate, great hall, five-storey pagoda and bell.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local TerrainWriter = require(script.Parent.Parent.TerrainWriter)
local Util = require(script.Parent.Parent.Util)
local Props = require(script.Parent.Parent.Props)
local Config = require(script.Parent.Parent.Config)
local AssetLibrary = require(script.Parent.Parent.AssetLibrary)

local Snow = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, ball, column, disc, rod, beam, wedge = Util.box, Util.ball, Util.column, Util.disc, Util.rod, Util.beam, Util.wedge
local NOSHADOW = { shadow = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local TAU = math.pi * 2
local HALF_PI = math.pi / 2
local L = Layout.Landmarks

local SNOW = rgb(242, 247, 252)
local WOOD = rgb(70, 50, 38)
local WOOD_LIGHT = rgb(120, 92, 66)
local PLASTER = rgb(238, 234, 224)
local VERMILION = rgb(178, 50, 38)
local TILE = rgb(62, 60, 66)
local THATCH = rgb(146, 120, 80)
local GRANITE = rgb(150, 148, 144)
local SHOJI = rgb(252, 238, 210)
local GOLD = rgb(214, 172, 74)

local function flatCF(pos, dir)
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

local function ground(p)
	return Vector3.new(p.X, Landscape.heightAt(p.X, p.Z), p.Z)
end

-- Roof with a layer of snow on top (gable).
local function snowyGable(parent, cf, width, depth, height, color, material)
	Util.gableRoof(parent, cf, width, depth, height, color, material)
	Util.gableRoof(parent, cf * CFrame.new(0, 1, 0), width - 1, depth - 0.6, height, SNOW, M.Snow, NOSHADOW)
end

-- Hip roof with snow on top.
local function snowyHip(parent, cf, width, depth, rise, color)
	Util.hipRoof(parent, cf, width, depth, rise, 1.4, color, M.ClayRoofTiles)
	Util.hipRoof(parent, cf * CFrame.new(0, 1, 0), width - 2, depth - 2, rise, 0.8, SNOW, M.Snow, NOSHADOW)
end

local function label(part, face, text, color, canvas)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = canvas or Vector2.new(400, 120)
	gui.LightInfluence = 0.6
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = color
	t.Font = Enum.Font.Garamond
	t.TextScaled = true
	t.Parent = gui
	return gui
end

local function redLantern(parent, pos)
	local l = Util.ellipsoid(parent, CFrame.new(pos), Vector3.new(1.8, 2.6, 1.8), rgb(232, 80, 48), M.Neon, NOCOL_NOSHADOW)
	Util.pointLight(l, rgb(255, 130, 80), 1.2, 18)
	box(parent, CFrame.new(pos + Vector3.new(0, 1.5, 0)), Vector3.new(1.2, 0.4, 1.2), rgb(30, 26, 24), M.Wood, NOCOL_NOSHADOW)
	return l
end

-- Torii gate standing at cf (ground center); people walk through along cf's Z axis.
local function torii(parent, cf, width, height, color)
	-- the mesh's pillars stand 16 apart
	local mesh = AssetLibrary.place("Torii", parent, cf, width / 16, color and { Vermilion = color })
	if mesh then
		return mesh
	end
	local m = Util.model(parent, "Torii")
	color = color or VERMILION
	for _, s in ipairs({ -1, 1 }) do
		local base = (cf * CFrame.new(s * width / 2, 0, 0)).Position
		column(m, base - Vector3.new(0, 2, 0), height + 2, width * 0.09, color, M.SmoothPlastic)
		column(m, base - Vector3.new(0, 1, 0), 3, width * 0.12, rgb(30, 28, 28), M.SmoothPlastic)
	end
	box(m, cf * CFrame.new(0, height * 0.78, 0), Vector3.new(width + width * 0.16, height * 0.06, width * 0.08), color, M.SmoothPlastic)
	box(m, cf * CFrame.new(0, height + height * 0.04, 0), Vector3.new(width * 1.42, height * 0.07, width * 0.12), color, M.SmoothPlastic)
	box(m, cf * CFrame.new(0, height + height * 0.1, 0), Vector3.new(width * 1.5, height * 0.05, width * 0.14), rgb(28, 26, 26), M.SmoothPlastic)
	box(m, cf * CFrame.new(0, height + height * 0.14, 0), Vector3.new(width * 1.48, height * 0.03, width * 0.13), SNOW, M.Snow, NOSHADOW)
	box(m, cf * CFrame.new(0, height * 0.9, 0), Vector3.new(width * 0.06, height * 0.12, width * 0.1), color, M.SmoothPlastic)
	return m
end

local function chimneySmoke(part)
	Util.particles(part, {
		Texture = Util.TEX.smoke,
		Color = Util.cs(rgb(230, 230, 232), rgb(190, 190, 196)),
		Size = Util.ns(0, 1, 1, 6),
		Transparency = Util.ns(0, 0.5, 1, 1),
		Lifetime = NumberRange.new(5, 8),
		Rate = 2,
		Speed = NumberRange.new(2, 3),
		SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Top,
		LightInfluence = 1,
	})
end

-- Minka (farmhouse) at cf ground center, front facing -Z.
local function minka(parent, rng, cf, W, D, thatched)
	-- the meshes are 22 x 16; scale by the requested width
	local mesh = AssetLibrary.place(thatched and "Minka_Thatch" or "Minka_Tile", parent, cf, W / 22)
	if mesh then
		mesh.Name = "Minka"
		chimneySmoke(AssetLibrary.anchor(mesh, cf, Vector3.new(0, 0, thatched and 26.5 or 22.5), "Smoke"))
		local lamp = AssetLibrary.anchor(mesh, cf, Vector3.new(9.5, -11.6, 10.3), "Lantern")
		Util.pointLight(lamp, rgb(255, 130, 80), 1.2, 18)
		-- warm light glowing out through the paper screens
		local screen = AssetLibrary.anchor(mesh, cf, Vector3.new(0, -8.4, 7.2), "ScreenGlow")
		Util.surfaceLight(screen, Enum.NormalId.Front, rgb(255, 206, 140), 1.4, 16, 100)
		return mesh
	end
	local m = Util.model(parent, "Minka")
	box(m, cf * CFrame.new(0, 0.2, 0), Vector3.new(W + 3, 2.4, D + 3), GRANITE, M.Granite)
	box(m, cf * CFrame.new(0, 2, 0), Vector3.new(W, 1.2, D), WOOD_LIGHT, M.WoodPlanks)
	box(m, cf * CFrame.new(0, 7.35, 0), Vector3.new(W - 0.6, 9.5, D - 0.6), PLASTER, M.Plaster)
	for _, x in ipairs({ -W / 2, -W / 6, W / 6, W / 2 }) do
		for _, z in ipairs({ -D / 2, D / 2 }) do
			box(m, cf * CFrame.new(x, 7.5, z), Vector3.new(1.2, 11, 1.2), WOOD, M.Wood)
		end
	end
	for _, z in ipairs({ -D / 2, D / 2 }) do
		box(m, cf * CFrame.new(0, 12.2, z), Vector3.new(W + 1, 1.2, 1), WOOD, M.Wood, NOSHADOW)
		box(m, cf * CFrame.new(0, 4, z), Vector3.new(W + 0.6, 0.8, 0.9), WOOD, M.Wood, NOSHADOW)
	end
	for _, x in ipairs({ -W / 2, W / 2 }) do
		box(m, cf * CFrame.new(x, 12.2, 0), Vector3.new(1, 1.2, D + 1), WOOD, M.Wood, NOSHADOW)
	end
	-- glowing shoji screens
	for i, x in ipairs({ -W / 3, 0, W / 3 }) do
		local panel = box(m, cf * CFrame.new(x, 8, -D / 2 - 0.1), Vector3.new(W / 3 - 2, 7, 0.3), SHOJI, M.SmoothPlastic, NOSHADOW)
		if i == 2 then
			Util.surfaceLight(panel, Enum.NormalId.Front, rgb(255, 206, 140), 1.4, 16, 100)
		end
		for _, y in ipairs({ 6, 8, 10 }) do
			box(m, cf * CFrame.new(x, y, -D / 2 - 0.3), Vector3.new(W / 3 - 2, 0.25, 0.2), WOOD, M.Wood, NOCOL_NOSHADOW)
		end
		box(m, cf * CFrame.new(x, 8, -D / 2 - 0.3), Vector3.new(0.25, 7, 0.2), WOOD, M.Wood, NOCOL_NOSHADOW)
	end
	-- engawa (veranda) and stepping stone
	box(m, cf * CFrame.new(0, 2.6, -D / 2 - 2.2), Vector3.new(W + 2, 0.6, 4), WOOD_LIGHT, M.WoodPlanks)
	box(m, cf * CFrame.new(0, 0.9, -D / 2 - 5.2), Vector3.new(4, 1, 2.2), GRANITE, M.Granite)

	-- roof (ridge along X)
	local roofCF = cf * CFrame.new(0, 12.8, 0) * CFrame.Angles(0, HALF_PI, 0)
	local rise = thatched and 10 or 8
	snowyGable(m, roofCF, D + 9, W + 7, rise, thatched and THATCH or TILE, thatched and M.Grass or M.ClayRoofTiles)
	box(m, cf * CFrame.new(0, 12.8 + rise + 1, 0), Vector3.new(W + 8, 1.6, 2), WOOD, M.Wood, NOSHADOW)
	local ridge = box(m, cf * CFrame.new(0, 12.8 + rise + 2.1, 0), Vector3.new(W + 8, 0.8, 2.6), SNOW, M.Snow, NOSHADOW)
	chimneySmoke(ridge)
	redLantern(m, (cf * CFrame.new(W / 2 - 1.5, 10, -D / 2 - 3.5)).Position)

	-- firewood and a barrel by the side
	for k = 0, 4 do
		local c = cf * CFrame.new(W / 2 + 2.4 + (k % 3) * 1.4, 1 + (k // 3) * 1.3, 2) * CFrame.Angles(0, HALF_PI, 0)
		Util.cylinder(m, c, 6, 1.3, rgb(122, 90, 60), M.Wood, NOSHADOW)
	end
	box(m, cf * CFrame.new(W / 2 + 3.4, 2.6, 2), Vector3.new(4.8, 0.6, 6.4), SNOW, M.Snow, NOSHADOW)
	column(m, (cf * CFrame.new(-W / 2 - 2.5, 0, -2)).Position, 3.6, 3, WOOD_LIGHT, M.Wood)
	disc(m, (cf * CFrame.new(-W / 2 - 2.5, 3.8, -2)).Position, 0.6, 3, SNOW, M.Snow, NOSHADOW)
	return m
end

-- Village ---------------------------------------------------------------------------------------
local function buildVillage(parent, rng)
	local m = Util.model(parent, "ShirayukiVillage")
	local center = Vector3.new(L.SnowVillage.X, Landscape.VillageHeight, L.SnowVillage.Z)
	local outDir = (L.TempleStairsFoot - L.SnowVillage)
	outDir = Vector3.new(outDir.X, 0, outDir.Z).Unit
	local V = flatCF(center, outDir) -- -Z points toward the temple path

	-- stone-slab street
	for z = -150, 150, 6 do
		local p = ground((V * CFrame.new(rng:NextNumber(-0.6, 0.6), 0, z)).Position)
		box(m, CFrame.new(p + Vector3.new(0, 0.1, 0)) * V.Rotation * CFrame.Angles(0, rng:NextNumber(-0.06, 0.06), 0), Vector3.new(9, 1, 4.6), Util.vary(rng, GRANITE, 0.05), M.Slate, NOSHADOW)
	end

	local houses = {
		{ -30, -90, false },
		{ 31, -64, true },
		{ -33, -12, true },
		{ 32, 22, false },
		{ -30, 74, false },
		{ 36, 108, true, true },
	}
	for _, h in ipairs(houses) do
		local x, z = h[1], h[2]
		local yaw = x < 0 and -HALF_PI or HALF_PI
		local p = ground((V * CFrame.new(x, 0, z)).Position)
		local elder = h[4] -- the village elder's larger house
		minka(m, rng, CFrame.new(p) * V.Rotation * CFrame.Angles(0, yaw, 0), elder and 32 or rng:NextNumber(20, 24), elder and 20 or rng:NextNumber(15, 17), h[3])
	end

	-- well in the square
	local wellPos = ground((V * CFrame.new(14, 0, 40)).Position)
	column(m, wellPos - Vector3.new(0, 1, 0), 4, 7, GRANITE, M.Granite)
	disc(m, wellPos + Vector3.new(0, 3.1, 0), 0.2, 5.4, rgb(20, 24, 30), M.SmoothPlastic, NOSHADOW)
	for _, s in ipairs({ -1, 1 }) do
		column(m, wellPos + Vector3.new(s * 3.2, 0, 0), 9, 0.8, WOOD, M.Wood)
	end
	snowyGable(m, CFrame.new(wellPos + Vector3.new(0, 9, 0)) * V.Rotation, 9, 5, 3, TILE, M.ClayRoofTiles)

	-- lanterns along the street
	for z = -130, 130, 44 do
		for _, x in ipairs({ -8, 8 }) do
			Props.stoneLantern(m, ground((V * CFrame.new(x, 0, z + (x > 0 and 22 or 0))).Position), 0, true)
		end
	end

	-- torii at both ends of the street
	torii(m, CFrame.new(ground((V * CFrame.new(0, 0, -158)).Position)) * V.Rotation, 16, 18)
	torii(m, CFrame.new(ground((V * CFrame.new(0, 0, 160)).Position)) * V.Rotation, 14, 16)

	-- small roadside shrine
	local shrinePos = ground((V * CFrame.new(-14, 0, -150)).Position)
	local shrine = CFrame.new(shrinePos) * V.Rotation * CFrame.Angles(0, -HALF_PI, 0)
	box(m, shrine * CFrame.new(0, 1, 0), Vector3.new(5, 2, 5), GRANITE, M.Granite)
	box(m, shrine * CFrame.new(0, 4, 0), Vector3.new(3.4, 4, 3), WOOD_LIGHT, M.Wood)
	snowyGable(m, shrine * CFrame.new(0, 6, 0), 5.4, 4.6, 2, TILE, M.ClayRoofTiles)
	redLantern(m, (shrine * CFrame.new(0, 4.5, -2.6)).Position)

	-- bamboo fences
	for _, side in ipairs({ -1, 1 }) do
		for z = -120, 110, 4 do
			if math.abs(z) > 20 then
				local p = ground((V * CFrame.new(side * 56, 0, z)).Position)
				column(m, p - Vector3.new(0, 1, 0), 6, 0.7, rgb(150, 160, 96), M.Wood, NOSHADOW)
			end
		end
		for _, z0 in ipairs({ -120, 24 }) do
			local a = ground((V * CFrame.new(side * 56, 0, z0)).Position)
			local b = ground((V * CFrame.new(side * 56, 0, z0 + 96)).Position)
			beam(m, a + Vector3.new(0, 3.5, 0), b + Vector3.new(0, 3.5, 0), 0.4, 0.4, rgb(120, 130, 80), M.Wood, NOSHADOW)
		end
	end

	-- drifts of snow against the houses
	for _ = 1, 14 do
		local p = ground((V * CFrame.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(-140, 140))).Position)
		if math.abs((V:PointToObjectSpace(p)).X) > 14 then
			workspace.Terrain:FillBall(p, rng:NextNumber(3, 6), M.Snow)
		end
	end

	-- frozen pond with a viewing lantern and a bench
	local pond = L.SnowPond
	local pondLevel = Landscape.SnowPondLevel
	local toVillage = (L.SnowVillage - pond).Unit
	local bank = pond + toVillage * 132
	Props.stoneLantern(m, ground(bank), 0, true)
	local benchPos = ground(pond + toVillage * 140 + Vector3.new(8, 0, 8))
	box(m, CFrame.new(benchPos + Vector3.new(0, 2, 0)) * V.Rotation, Vector3.new(8, 0.6, 2.4), WOOD_LIGHT, M.WoodPlanks)
	box(m, CFrame.new(benchPos + Vector3.new(0, 2.5, 0)) * V.Rotation, Vector3.new(7.6, 0.4, 2), SNOW, M.Snow, NOSHADOW)
	for _, s in ipairs({ -1, 1 }) do
		box(m, CFrame.new(benchPos + Vector3.new(0, 1, 0)) * V.Rotation * CFrame.new(s * 3.2, 0, 0), Vector3.new(0.8, 2, 2), WOOD, M.Wood)
	end
	m:SetAttribute("PondLevel", pondLevel)
	return m, V
end

-- Jizo statues along the trail -----------------------------------------------------------------------
local function jizo(parent, pos, facing)
	local m = Util.model(parent, "Jizo")
	local cf = flatCF(pos, facing)
	box(m, cf * CFrame.new(0, 0.6, 0), Vector3.new(3.4, 1.6, 3), GRANITE, M.Granite)
	column(m, (cf * CFrame.new(0, 1.2, 0)).Position, 3.6, 2.4, GRANITE, M.Granite)
	ball(m, (cf * CFrame.new(0, 5.6, 0)).Position, 2.4, GRANITE, M.Granite)
	wedge(m, cf * CFrame.new(0, 3.6, -0.9), Vector3.new(2.4, 1.6, 1), rgb(196, 40, 36), M.Fabric, NOCOL_NOSHADOW)
	disc(m, (cf * CFrame.new(0, 6.9, 0)).Position, 0.6, 2.2, SNOW, M.Snow, NOSHADOW)
	return m
end

-- Temple --------------------------------------------------------------------------------------------
local function pagoda(parent, base, facing)
	local mesh = AssetLibrary.place("Pagoda", parent, flatCF(base, facing))
	if mesh then
		mesh.Name = "FiveStoreyPagoda"
		return mesh
	end
	local m = Util.model(parent, "FiveStoreyPagoda")
	box(m, CFrame.new(base + Vector3.new(0, 1.5, 0)), Vector3.new(28, 3, 28), GRANITE, M.Granite)
	local y = 3
	for i = 0, 4 do
		local s = 16 - i * 2
		box(m, CFrame.new(base + Vector3.new(0, y + 4.5, 0)), Vector3.new(s, 9, s), PLASTER, M.Plaster)
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			box(m, CFrame.new(base + Vector3.new(c[1] * s / 2, y + 4.5, c[2] * s / 2)), Vector3.new(1.2, 9, 1.2), VERMILION, M.SmoothPlastic, NOSHADOW)
		end
		box(m, CFrame.new(base + Vector3.new(0, y + 8.6, 0)), Vector3.new(s + 1.6, 1.2, s + 1.6), VERMILION, M.SmoothPlastic, NOSHADOW)
		snowyHip(m, CFrame.new(base + Vector3.new(0, y + 9.2, 0)), s + 14, s + 14, 4.5, TILE)
		y += 13
	end
	local top = base + Vector3.new(0, y + 1, 0)
	rod(m, top - Vector3.new(0, 4, 0), top + Vector3.new(0, 30, 0), 1.2, GOLD, M.Foil)
	for k = 1, 9 do
		disc(m, top + Vector3.new(0, 3 + k * 2.4, 0), 0.6, 3.6 - k * 0.15, GOLD, M.Foil, NOSHADOW)
	end
	ball(m, top + Vector3.new(0, 31, 0), 2.4, GOLD, M.Foil)
	return m
end

local function bellTower(parent, cf)
	local mesh = AssetLibrary.place("BellPavilion", parent, cf)
	if mesh then
		return mesh
	end
	local m = Util.model(parent, "BellPavilion")
	box(m, cf * CFrame.new(0, 1.5, 0), Vector3.new(22, 3, 22), GRANITE, M.Granite)
	for _, c in ipairs({ { -8, -8 }, { 8, -8 }, { -8, 8 }, { 8, 8 } }) do
		column(m, (cf * CFrame.new(c[1], 3, c[2])).Position, 17, 1.8, VERMILION, M.SmoothPlastic)
	end
	box(m, cf * CFrame.new(0, 19.6, 0), Vector3.new(19, 1.2, 19), VERMILION, M.SmoothPlastic, NOSHADOW)
	snowyHip(m, cf * CFrame.new(0, 20.2, 0), 28, 28, 7, TILE)
	local bronze = rgb(74, 64, 50)
	column(m, (cf * CFrame.new(0, 8, 0)).Position, 9.5, 7, bronze, M.Metal)
	ball(m, (cf * CFrame.new(0, 17, 0)).Position, 6.8, bronze, M.Metal)
	box(m, cf * CFrame.new(0, 19, 0), Vector3.new(16, 1, 1), WOOD, M.Wood, NOSHADOW)
	-- hanging log striker
	Util.cylinder(m, cf * CFrame.new(-7.5, 11, 0), 7, 1.6, WOOD_LIGHT, M.Wood, NOSHADOW)
	for _, s in ipairs({ -1, 1 }) do
		box(m, cf * CFrame.new(-7.5 + s * 2.5, 15, 0), Vector3.new(0.2, 8, 0.2), rgb(220, 200, 150), M.Fabric, NOCOL_NOSHADOW)
	end
	return m
end

local function komainu(parent, cf)
	local m = Util.model(parent, "Komainu")
	box(m, cf * CFrame.new(0, 1.5, 0), Vector3.new(6.4, 3, 8.4), GRANITE, M.Granite)
	cf = cf * CFrame.new(0, 3, 0)
	box(m, cf * CFrame.new(0, 2, 0), Vector3.new(5, 4, 7), GRANITE, M.Granite)
	box(m, cf * CFrame.new(0, 5.5, 0.8), Vector3.new(3.4, 3, 5), GRANITE, M.Granite)
	ball(m, (cf * CFrame.new(0, 8.4, -1.2)).Position, 3.6, GRANITE, M.Granite)
	ball(m, (cf * CFrame.new(0, 8.8, 1.4)).Position, 2.2, GRANITE, M.Granite)
	box(m, cf * CFrame.new(0, 4.3, 0.8), Vector3.new(3.6, 0.6, 5.2), SNOW, M.Snow, NOSHADOW)
	return m
end

local function buildTemple(parent, rng)
	local m = Util.model(parent, "RyuudouTemple")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local center = Vector3.new(L.Temple.X, Landscape.TempleHeight, L.Temple.Z)
	local front = (L.TempleStairsTop - L.Temple)
	front = Vector3.new(front.X, 0, front.Z).Unit
	local T = flatCF(center, front) -- -Z points down the stairs

	-- stone courtyard
	box(m, T * CFrame.new(0, -0.6, 0), Vector3.new(206, 2.6, 206), GRANITE, M.Slate)
	for z = -96, 0, 6 do
		box(m, T * CFrame.new(0, 0.9, z), Vector3.new(12, 0.6, 5.4), Util.vary(rng, rgb(170, 168, 162), 0.04), M.Granite, NOSHADOW)
	end

	-- earthen walls with tiled caps
	local function wallRun(fromX, fromZ, toX, toZ)
		local a = (T * CFrame.new(fromX, 0, fromZ)).Position
		local b = (T * CFrame.new(toX, 0, toZ)).Position
		local cf = CFrame.lookAt((a + b) / 2, b)
		local len = (b - a).Magnitude
		box(m, cf * CFrame.new(0, 4, 0), Vector3.new(3, 10, len), PLASTER, M.Plaster)
		box(m, cf * CFrame.new(0, 0.2, 0), Vector3.new(3.6, 2, len), GRANITE, M.Granite, NOSHADOW)
		snowyGable(m, cf * CFrame.new(0, 9, 0), 6, len + 1, 2.4, TILE, M.ClayRoofTiles)
	end
	wallRun(-100, 100, 100, 100)
	wallRun(-100, -100, -100, 100)
	wallRun(100, -100, 100, 100)
	wallRun(-100, -100, -26, -100)
	wallRun(26, -100, 100, -100)

	-- sanmon (two-storey gate)
	local G = T * CFrame.new(0, 0, -100)
	local gate = AssetLibrary.place("TempleGate", m, G)
	if gate then
		gate.Name = "Sanmon"
		-- the name board's black panel sits at Blender (0, -6.75, 27); the text goes just in front of it
		local plaque = box(gate, G * CFrame.new(AssetLibrary.fromBlender(0, -7.12, 27)), Vector3.new(10.2, 4.2, 0.1), rgb(30, 28, 28), M.SmoothPlastic, NOCOL_NOSHADOW)
		plaque.Name = "NameBoard"
		label(plaque, Enum.NormalId.Front, "龍洞寺", GOLD)
	else
		box(m, G * CFrame.new(0, 0.4, 0), Vector3.new(48, 2, 20), GRANITE, M.Granite)
		for _, x in ipairs({ -18, -6, 6, 18 }) do
			for _, z in ipairs({ -6, 6 }) do
				column(m, (G * CFrame.new(x, 1, z)).Position, 20, 2.6, VERMILION, M.SmoothPlastic)
			end
		end
		box(m, G * CFrame.new(0, 20.6, 0), Vector3.new(40, 1.6, 14), VERMILION, M.SmoothPlastic)
		snowyHip(m, G * CFrame.new(0, 21.4, 0), 54, 28, 7, TILE)
		box(m, G * CFrame.new(0, 28, 0), Vector3.new(32, 9, 11), PLASTER, M.Plaster)
		for _, x in ipairs({ -16, -5.3, 5.3, 16 }) do
			box(m, G * CFrame.new(x, 28, -5.6), Vector3.new(1, 9, 0.6), VERMILION, M.SmoothPlastic, NOSHADOW)
		end
		box(m, G * CFrame.new(0, 32.4, 0), Vector3.new(34, 1.2, 13), VERMILION, M.SmoothPlastic, NOSHADOW)
		snowyHip(m, G * CFrame.new(0, 33, 0), 46, 24, 9, TILE)
		local plaque = box(m, G * CFrame.new(0, 26.4, -6.4), Vector3.new(10, 4, 0.6), rgb(40, 32, 28), M.Wood, NOSHADOW)
		label(plaque, Enum.NormalId.Front, "龍洞寺", GOLD)
	end
	for _, x in ipairs({ -12, 12 }) do
		redLantern(m, (G * CFrame.new(x, 17, -8)).Position)
	end

	-- lanterns lining the way to the hall
	for z = -84, -20, 16 do
		for _, x in ipairs({ -12, 12 }) do
			Props.stoneLantern(m, (T * CFrame.new(x, 0.8, z)).Position, 0, true)
		end
	end

	-- main hall
	local Hc = T * CFrame.new(0, 0, 36)
	local hall = AssetLibrary.place("TempleHall", m, Hc)
	if hall then
		hall.Name = "MainHall"
		local lantern = AssetLibrary.anchor(hall, Hc, Vector3.new(0, -29.5, 23.7), "GreatLantern")
		Util.pointLight(lantern, rgb(255, 120, 70), 2, 34)
		local door = AssetLibrary.anchor(hall, Hc, Vector3.new(0, -20.2, 15), "DoorGlow")
		Util.surfaceLight(door, Enum.NormalId.Front, rgb(255, 196, 120), 1, 20, 90)
	else
		box(m, Hc * CFrame.new(0, 3, 0), Vector3.new(96, 6, 70), GRANITE, M.Granite)
		for k = 1, 6 do
			box(m, Hc * CFrame.new(0, 6 - k, -35 - k * 2 + 1), Vector3.new(30, 2, 2), GRANITE, M.Granite)
		end
		box(m, Hc * CFrame.new(0, 18, 4), Vector3.new(72, 24, 46), PLASTER, M.Plaster)
		for x = -36, 36, 9 do
			column(m, (Hc * CFrame.new(x, 6, -27)).Position, 24, 2.6, VERMILION, M.SmoothPlastic)
			column(m, (Hc * CFrame.new(x, 6, 4 - 23)).Position, 24, 2, WOOD, M.Wood, NOSHADOW)
		end
		box(m, Hc * CFrame.new(0, 29.5, -27), Vector3.new(76, 2, 2.4), VERMILION, M.SmoothPlastic)
		box(m, Hc * CFrame.new(0, 7.2, -24), Vector3.new(76, 0.6, 8), WOOD_LIGHT, M.WoodPlanks)
		box(m, Hc * CFrame.new(0, 9, -27.6), Vector3.new(72, 0.5, 0.5), VERMILION, M.SmoothPlastic, NOSHADOW)
		for _, x in ipairs({ -18, 0, 18 }) do
			local door = box(m, Hc * CFrame.new(x, 15, -19.2), Vector3.new(12, 16, 0.6), rgb(96, 64, 42), M.Wood, NOSHADOW)
			for _, y in ipairs({ 10, 14, 18, 22 }) do
				box(m, Hc * CFrame.new(x, y, -19.6), Vector3.new(12, 0.3, 0.3), WOOD, M.Wood, NOCOL_NOSHADOW)
			end
			if x == 0 then
				Util.surfaceLight(door, Enum.NormalId.Front, rgb(255, 196, 120), 1, 20, 90)
			end
		end
		local bigLantern = Util.ellipsoid(m, Hc * CFrame.new(0, 24, -29), Vector3.new(6, 9, 6), rgb(220, 60, 40), M.Neon, NOCOL_NOSHADOW)
		Util.pointLight(bigLantern, rgb(255, 120, 70), 2, 34)
		box(m, Hc * CFrame.new(0, 8.4, -30), Vector3.new(8, 3.6, 4), rgb(100, 70, 46), M.WoodPlanks)
		-- double roof
		snowyHip(m, Hc * CFrame.new(0, 30.4, 4), 100, 74, 12, TILE)
		box(m, Hc * CFrame.new(0, 40, 4), Vector3.new(60, 10, 34), PLASTER, M.Plaster)
		box(m, Hc * CFrame.new(0, 45.2, 4), Vector3.new(62, 1.2, 36), VERMILION, M.SmoothPlastic, NOSHADOW)
		snowyHip(m, Hc * CFrame.new(0, 45.8, 4), 80, 54, 18, TILE)
		for _, x in ipairs({ -22, 22 }) do
			local p = (Hc * CFrame.new(x, 64.6, 4)).Position
			box(m, CFrame.new(p) * T.Rotation * CFrame.Angles(0, 0, x > 0 and -0.3 or 0.3), Vector3.new(2, 6, 2), GOLD, M.Foil, NOSHADOW)
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		komainu(m, Hc * CFrame.new(s * 22, 0.6, -50))
	end

	pagoda(m, (T * CFrame.new(64, 0, -40)).Position, T.LookVector)
	bellTower(m, T * CFrame.new(-62, 0, -44))

	-- sacred cedar wrapped in a shimenawa rope
	local cedarPos = (T * CFrame.new(-62, 0, 52)).Position
	Util.place(Props.pines()[2], m, cedarPos - Vector3.new(0, 1, 0), 0.4, 1.6)
	local rope = rgb(222, 200, 150)
	for k = 0, 15 do
		local a0, a1 = k / 16 * TAU, (k + 1) / 16 * TAU
		local r = 4.6
		beam(m, cedarPos + Vector3.new(math.cos(a0) * r, 10, math.sin(a0) * r), cedarPos + Vector3.new(math.cos(a1) * r, 10, math.sin(a1) * r), 1, 1, rope, M.Fabric, NOSHADOW)
	end
	for k = 0, 3 do
		local a = k / 4 * TAU + 0.4
		local p = cedarPos + Vector3.new(math.cos(a) * 5, 8, math.sin(a) * 5)
		box(m, CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, math.sin(a))) * CFrame.Angles(0, 0, 0.3), Vector3.new(1.2, 3, 0.1), rgb(250, 250, 250), M.SmoothPlastic, NOCOL_NOSHADOW)
	end
	return m, T
end

-- Stairway ---------------------------------------------------------------------------------------------
local function buildStairway(parent, rng)
	local m = Util.model(parent, "TempleStairway")
	local foot, top = L.TempleStairsFoot, L.TempleStairsTop
	local footH, topH = Landscape.StairsFootHeight, Landscape.TempleHeight
	local dir = Vector3.new(top.X - foot.X, 0, top.Z - foot.Z)
	local len = dir.Magnitude
	dir = dir.Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local run = 3
	local n = math.floor(len / run)
	local rise = (topH - footH) / n
	for k = 0, n do
		local t = k / n
		local p = foot + dir * (t * len)
		local stepTop = footH + k * rise
		local lineH = footH + t * (topH - footH)
		local h = stepTop - (lineH - 4)
		box(m, flatCF(Vector3.new(p.X, stepTop - h / 2, p.Z), dir), Vector3.new(20, h, run + 0.25), Util.vary(rng, GRANITE, 0.04), M.Granite)
		if k % 28 == 14 then
			for _, s in ipairs({ -1, 1 }) do
				Props.stoneLantern(m, Vector3.new(p.X, stepTop - 0.5, p.Z) + side * s * 13, 0, true)
			end
		end
		Util.breathe()
	end
	-- torii along the climb
	for _, t in ipairs({ 0, 0.33, 0.66 }) do
		local p = foot + dir * (t * len - 6)
		local hgt = Landscape.heightAt(p.X, p.Z)
		torii(m, flatCF(Vector3.new(p.X, hgt, p.Z), dir), 24, t == 0 and 30 or 24)
	end
	-- stone marker at the foot
	local markerPos = ground(foot - dir * 14 + side * 20)
	local marker = box(m, flatCF(markerPos + Vector3.new(0, 7, 0), -side), Vector3.new(4.5, 16, 4.5), GRANITE, M.Granite)
	label(marker, Enum.NormalId.Front, "龍洞寺\nRYUUDOU TEMPLE", rgb(40, 34, 30), Vector2.new(200, 600))
	label(marker, Enum.NormalId.Back, "龍洞寺\nRYUUDOU TEMPLE", rgb(40, 34, 30), Vector2.new(200, 600))
	disc(m, markerPos + Vector3.new(0, 15.3, 0), 0.6, 5, SNOW, M.Snow, NOSHADOW)
	return m
end

-- A lone charcoal-burner's hut high in the forest ------------------------------------------------------------
local function findQuietSpot(rng)
	local best, bestSlope = nil, math.huge
	local R = Layout.ISLAND_RADIUS
	for _ = 1, 260 do
		local a = Layout.ZoneAngle.Snow + rng:NextNumber(-0.7, 0.7) * Layout.HALF_SECTOR
		local p = Layout.polar(a, rng:NextNumber(R * 0.55, R * 0.82))
		local far = (p - L.SnowVillage).Magnitude > 900 and (p - L.Temple).Magnitude > 800
		if far then
			local q = Landscape.query(p.X, p.Z)
			if q.land and q.zone == "Snow" and q.h > 90 then
				local s = Landscape.slopeAt(p.X, p.Z, 10)
				if s < bestSlope then
					best, bestSlope = p, s
				end
			end
		end
	end
	return best
end

local function buildHut(parent, rng)
	local spot = findQuietSpot(rng)
	if not spot then
		return
	end
	local m = Util.model(parent, "MountainHut")
	local p = ground(spot)
	local facing = Vector3.new(-p.X, 0, -p.Z).Unit
	minka(m, rng, flatCF(p - Vector3.new(0, 1.5, 0), facing), 18, 14, true)
	-- charcoal kiln
	local kiln = ground(p + Vector3.new(-facing.Z, 0, facing.X) * 22)
	ball(m, kiln, 12, rgb(120, 96, 80), M.Ground)
	disc(m, kiln + Vector3.new(0, 4.8, 0), 0.6, 8, SNOW, M.Snow, NOSHADOW)
	local vent = box(m, CFrame.new(kiln + Vector3.new(0, 6, 0)), Vector3.new(1.4, 1.4, 1.4), rgb(60, 50, 44), M.Basalt, NOSHADOW)
	Util.particles(vent, {
		Texture = Util.TEX.smoke,
		Color = Util.cs(rgb(120, 116, 112), rgb(200, 200, 204)),
		Size = Util.ns(0, 1.5, 1, 10),
		Transparency = Util.ns(0, 0.4, 1, 1),
		Lifetime = NumberRange.new(6, 9),
		Rate = 3,
		Speed = NumberRange.new(3, 5),
		SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Top,
		LightInfluence = 1,
	})
	Props.stoneLantern(m, ground(p + facing * 16), 0, true)
end

---------------------------------------------------------------------------------------------------------
function Snow.Build(folder, rng)
	Util.log("Building Shirayuki Vale...")
	buildVillage(folder, rng)
	buildTemple(folder, rng)
	buildStairway(folder, rng)
	buildHut(folder, rng)

	-- jizo statues along the trail from the capital
	local path = Layout.Paths[2].points
	local jz = Util.model(folder, "TrailJizo")
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local d = (b - a)
		local len = d.Magnitude
		local side = Vector3.new(-d.Z, 0, d.X).Unit
		for t = 260, len - 200, 420 do
			local p = a + d.Unit * t + side * 16
			jizo(jz, ground(p), -side)
		end
	end

	-- the winter forest
	local pines = Props.pines()
	local bare = Props.bareTrees()
	local trees = Util.folder(folder, "Pines")
	local rocks = Util.folder(folder, "Rocks")
	local spacing = 50 / math.sqrt(math.max(Config.FOLIAGE_DENSITY, 0.05))
	local R = Landscape.MAX_COAST
	local foot, top = L.TempleStairsFoot, L.TempleStairsTop
	local sx, sz = top.X - foot.X, top.Z - foot.Z
	local slen2 = sx * sx + sz * sz
	local function nearStairs(x, z)
		local t = math.clamp(((x - foot.X) * sx + (z - foot.Z) * sz) / slen2, 0, 1)
		local dx, dz = foot.X + sx * t - x, foot.Z + sz * t - z
		return dx * dx + dz * dz < 36 * 36
	end
	local count, rockCount = 0, 0
	for _, p in ipairs(Util.scatterGrid(rng, -R, -R, R, R, spacing)) do
		if Layout.getZone(p.X, p.Z) == "Snow" then
			local q = Landscape.query(p.X, p.Z)
			if q.land and q.zone == "Snow" and not q.path and not q.road and not q.underwater then
				local dv = (p - L.SnowVillage).Magnitude
				local dt = (p - L.Temple).Magnitude
				local dp = (p - L.SnowPond).Magnitude
				if dv > 300 and dt > 225 and dp > 150 and not nearStairs(p.X, p.Z) then
					local slope = Landscape.slopeAt(p.X, p.Z)
					local grove = Landscape.noise2(p.X, p.Z, 1 / 600, 300)
					if slope > 1.05 then
						if rng:NextNumber() < 0.12 then
							local pos = Vector3.new(p.X, q.h, p.Z)
							TerrainWriter.boulder(rng, pos, rng:NextNumber(6, 12), M.Rock)
							workspace.Terrain:FillBall(pos + Vector3.new(0, 6, 0), rng:NextNumber(4, 6), M.Snow)
							rockCount += 1
						end
					elseif rng:NextNumber() < math.clamp(0.62 + grove * 1.3, 0.12, 0.96) then
						local pos = Vector3.new(p.X, q.h - 1.5, p.Z)
						if dv < 560 and rng:NextNumber() < 0.25 then
							Util.place(Props.randomTemplate(rng, bare), trees, pos, rng:NextNumber(0, TAU), rng:NextNumber(0.9, 1.3))
						else
							Util.place(Props.randomTemplate(rng, pines), trees, pos, rng:NextNumber(0, TAU), rng:NextNumber(0.75, 1.4))
						end
						count += 1
					end
				end
			end
		end
		Util.breathe()
	end
	Util.log(string.format("  %d trees, %d snowy boulders", count, rockCount))
	rocks:SetAttribute("Count", rockCount)
end

return Snow
