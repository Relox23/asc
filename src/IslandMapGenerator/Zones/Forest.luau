--[[
	Eloria Wildwood
	A lush, enchanted forest: groves and sunny clearings, blossom trees shedding
	petals, a colossal world tree, a lake fed by a waterfall, glowing mushrooms,
	elven ruins, and only a handful of cottages hidden among the trees.
	New players arrive in a stone circle near the causeway from the capital.
]]

local Layout = require(script.Parent.Parent.IslandLayout)
local Landscape = require(script.Parent.Parent.Landscape)
local TerrainWriter = require(script.Parent.Parent.TerrainWriter)
local Util = require(script.Parent.Parent.Util)
local Props = require(script.Parent.Parent.Props)
local Config = require(script.Parent.Parent.Config)
local AssetLibrary = require(script.Parent.Parent.AssetLibrary)
local Waterworks = require(script.Parent.Parent.Waterworks)

local Forest = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, ball, column, disc, rod, beam = Util.box, Util.ball, Util.column, Util.disc, Util.rod, Util.beam
local NOCOL = { collide = false }
local NOSHADOW = { shadow = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local TAU = math.pi * 2
local HALF_PI = math.pi / 2
local L = Layout.Landmarks

local BARK = rgb(96, 72, 52)
local MOSS = rgb(82, 120, 56)
local WOOD_DARK = rgb(74, 52, 38)
local STONE = rgb(150, 148, 140)

local function flatCF(pos, dir)
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

local function ground(p)
	return Vector3.new(p.X, Landscape.heightAt(p.X, p.Z), p.Z)
end

-- World tree --------------------------------------------------------------------------------
-- Spirit motes around the crown and glowing rune stones around the roots.
local function worldTreeExtras(m, base, rng)
	-- drifting spirit motes all around the crown
	local motes = box(m, CFrame.new(base + Vector3.new(0, 190, 0)), Vector3.new(260, 160, 260), rgb(255, 255, 255), M.SmoothPlastic, {
		collide = false,
		shadow = false,
		transparency = 1,
	})
	motes.CanQuery = false
	Util.particles(motes, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(rgb(200, 255, 170), rgb(255, 230, 140)),
		Size = Util.ns(0, 0, 0.3, 1.2, 1, 0),
		Lifetime = NumberRange.new(6, 10),
		Rate = 40,
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -0.4, 0),
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Box,
	})

	-- rune stones around the roots
	for k = 0, 9 do
		local a = k / 10 * TAU
		local p = ground(base + Vector3.new(math.cos(a) * 150, 0, math.sin(a) * 150))
		local cf = flatCF(p, base - p) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
		box(m, cf * CFrame.new(0, 6, 0), Vector3.new(6, 16, 3), STONE, M.Slate)
		box(m, cf * CFrame.new(0, 14.4, 0), Vector3.new(6.4, 1.2, 3.4), MOSS, M.Grass, NOSHADOW)
		box(m, cf * CFrame.new(0, 7, -1.55), Vector3.new(0.8, 9, 0.2), rgb(120, 255, 200), M.Neon, NOCOL_NOSHADOW)
	end
end

local function buildWorldTree(parent, rng)
	local base = Vector3.new(L.WorldTree.X, Landscape.WorldTreeHeight - 2, L.WorldTree.Z)
	local mesh = AssetLibrary.place("WorldTree", parent, CFrame.new(base))
	if mesh then
		mesh.Name = "Elderheart_WorldTree"
		mesh.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		for k = 0, 5 do
			local a = k / 6 * TAU
			local fx = AssetLibrary.anchor(mesh, CFrame.new(base), Vector3.new(math.cos(a) * 70, math.sin(a) * 70, 150), "SpiritLight")
			Util.pointLight(fx, rgb(150, 255, 210), 1.5, 40)
		end
		worldTreeExtras(mesh, base, rng)
		return mesh
	end
	local m = Util.model(parent, "Elderheart_WorldTree")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local H = 230

	-- six strands twisting around each other form the trunk
	for s = 1, 6 do
		local a0 = s / 6 * TAU
		local prev
		for k = 0, 9 do
			local t = k / 9
			local a = a0 + t * TAU * 0.55
			local r = 30 - t * 17
			local p = base + Vector3.new(math.cos(a) * r, t * H, math.sin(a) * r)
			if prev then
				rod(m, prev, p, 32 - t * 18, s % 3 == 0 and Util.vary(rng, MOSS, 0.06) or Util.vary(rng, BARK, 0.05), M.Wood)
			end
			prev = p
		end
	end
	column(m, base - Vector3.new(0, 4, 0), 46, 76, BARK, M.Wood)

	-- roots
	for r = 1, 11 do
		local a = r / 11 * TAU + rng:NextNumber(-0.15, 0.15)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local p0 = base + dir * 20 + Vector3.new(0, 26, 0)
		local p1 = base + dir * 48 + Vector3.new(0, 14, 0)
		local p2 = base + dir * rng:NextNumber(70, 95) + Vector3.new(0, -2, 0)
		local p3 = base + dir * rng:NextNumber(105, 130) + Vector3.new(0, -8, 0)
		local color = r % 2 == 0 and MOSS or BARK
		rod(m, p0, p1, 16, color, M.Wood)
		rod(m, p1, p2, 11, color, M.Wood)
		rod(m, p2, p3, 6, color, M.Wood)
	end

	-- branches and canopy
	local tips = {}
	for b = 1, 9 do
		local a = b / 9 * TAU + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local from = base + Vector3.new(0, rng:NextNumber(150, 215), 0)
		local mid = from + dir * rng:NextNumber(50, 70) + Vector3.new(0, rng:NextNumber(20, 40), 0)
		local tip = mid + dir * rng:NextNumber(40, 60) + Vector3.new(0, rng:NextNumber(5, 25), 0)
		rod(m, from, mid, 12, BARK, M.Wood)
		rod(m, mid, tip, 7, BARK, M.Wood)
		table.insert(tips, tip)
		table.insert(tips, mid + Vector3.new(0, 20, 0))
	end
	table.insert(tips, base + Vector3.new(0, H + 20, 0))
	local leaves = { rgb(120, 190, 92), rgb(94, 170, 82), rgb(150, 210, 110), rgb(104, 182, 120) }
	for i, tip in ipairs(tips) do
		local size = i == #tips and 150 or rng:NextNumber(62, 100)
		ball(m, tip + Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-4, 10), rng:NextNumber(-8, 8)), size, Util.pick(rng, leaves), M.LeafyGrass, NOCOL)
		if i % 4 == 0 then
			ball(m, tip + Vector3.new(rng:NextNumber(-20, 20), 18, rng:NextNumber(-20, 20)), size * 0.5, rgb(236, 206, 96), M.LeafyGrass, NOCOL)
		end
	end

	-- hanging spirit lanterns
	for k = 1, 12 do
		local tip = tips[(k - 1) % #tips + 1]
		local p = tip + Vector3.new(rng:NextNumber(-20, 20), -rng:NextNumber(40, 60), rng:NextNumber(-20, 20))
		box(m, CFrame.new((p + tip) / 2 + Vector3.new(0, -14, 0)), Vector3.new(0.3, (tip - p).Magnitude - 28, 0.3), MOSS, M.Grass, NOCOL_NOSHADOW)
		local orb = ball(m, p, 3, rgb(170, 255, 220), M.Neon, NOCOL_NOSHADOW)
		if k % 2 == 0 then
			Util.pointLight(orb, rgb(150, 255, 210), 1.5, 30)
		end
	end

	worldTreeExtras(m, base, rng)
	return m
end

-- Lake, waterfall and dock -------------------------------------------------------------------------
local function buildLake(parent, rng)
	local m = Util.model(parent, "MirrorLake")
	local level = Landscape.ForestLakeLevel
	local lake = L.ForestLake
	local surface = math.ceil(level / 4) * 4 -- terrain water fills whole 4-stud voxels
	local water = rgb(206, 236, 255)

	-- the waterfall itself is terrain water (see Waterworks); here: spray, streaks, mist and rocks
	local parts, wf = Waterworks.waterfallParts()
	if parts then
		local f = wf.f
		local side = Vector3.new(-f.Z, 0, f.X)
		local lip = Vector3.new(wf.center.X, wf.top, wf.center.Z) + f * wf.r
		local height = math.max(wf.top - surface, 8)
		local sheetPos = lip + f * 4.6 + Vector3.new(0, -height / 2, 0)
		local sheet = box(m, CFrame.lookAt(sheetPos, sheetPos + f), Vector3.new(16, height, 1), water, M.Glass, { collide = false, shadow = false, transparency = 1 })
		sheet.Name = "FallingWater"
		sheet.CanQuery = false
		Util.particles(sheet, {
			Texture = Util.TEX.smoke,
			Color = Util.cs(rgb(255, 255, 255), rgb(200, 230, 250)),
			Size = Util.ns(0, 2.2, 1, 3.4),
			Transparency = Util.ns(0, 0.55, 0.7, 0.75, 1, 1),
			Lifetime = NumberRange.new(0.8, 1.3),
			Rate = 70,
			Speed = NumberRange.new(2, 4),
			Acceleration = Vector3.new(0, -46, 0),
			EmissionDirection = Enum.NormalId.Bottom,
			Shape = Enum.ParticleEmitterShape.Box,
			LightInfluence = 1,
		})
		local spray = box(m, CFrame.lookAt(lip + f * 2 + Vector3.new(0, 0.6, 0), lip + f * 6 + Vector3.new(0, 0.6, 0)), Vector3.new(14, 1, 2), water, M.Glass, { collide = false, shadow = false, transparency = 1 })
		spray.Name = "LipSpray"
		Util.particles(spray, {
			Texture = Util.TEX.sparkle,
			Color = Util.cs(rgb(235, 248, 255)),
			Size = Util.ns(0, 0.8, 1, 0.3),
			Transparency = Util.ns(0, 0.3, 1, 1),
			Lifetime = NumberRange.new(0.8, 1.4),
			Rate = 30,
			Speed = NumberRange.new(4, 7),
			SpreadAngle = Vector2.new(25, 10),
			Acceleration = Vector3.new(0, -30, 0),
			EmissionDirection = Enum.NormalId.Front,
		})
		local footPos = lip + f * 9 + Vector3.new(0, surface - wf.top + 1.5, 0)
		local mist = box(m, CFrame.new(footPos), Vector3.new(26, 2, 12), water, M.Glass, { collide = false, shadow = false, transparency = 1 })
		mist.Name = "Mist"
		Util.particles(mist, {
			Texture = Util.TEX.smoke,
			Color = Util.cs(rgb(240, 248, 255)),
			Size = Util.ns(0, 6, 1, 20),
			Transparency = Util.ns(0, 0.55, 1, 1),
			Lifetime = NumberRange.new(3, 5),
			Rate = 14,
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(60, 60),
			Shape = Enum.ParticleEmitterShape.Box,
			LightInfluence = 1,
		})
		-- boulders framing the falls and the stream
		for _, s in ipairs({ -1, 1 }) do
			for k = 0, 3 do
				local p = lip + side * s * rng:NextNumber(12, 16) + f * rng:NextNumber(1, 5) + Vector3.new(0, -k * height / 4, 0)
				TerrainWriter.boulder(rng, p, rng:NextNumber(5, 8), M.Rock)
			end
			for k = 1, 4 do
				local p = lip - f * (k * 14) + side * s * rng:NextNumber(7, 10) + Vector3.new(0, 1, 0)
				TerrainWriter.boulder(rng, p, rng:NextNumber(2.5, 4), M.Rock)
			end
		end
	end

	-- lily pads with a few flowers
	for _ = 1, 40 do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(60, 220)
		local q = lake + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if Landscape.heightAt(q.X, q.Z) < level - 2 then
			disc(m, Vector3.new(q.X, surface + 0.15, q.Z), 0.2, rng:NextNumber(3, 6), rgb(70, 140, 60), M.Grass, NOCOL_NOSHADOW)
			if rng:NextNumber() < 0.3 then
				ball(m, Vector3.new(q.X, surface + 0.6, q.Z), 1.2, rgb(250, 200, 220), M.SmoothPlastic, NOCOL_NOSHADOW)
			end
		end
	end

	-- wooden dock on the shore facing the capital
	local towardCenter = (Vector3.new(0, 0, 0) - lake)
	towardCenter = Vector3.new(towardCenter.X, 0, towardCenter.Z).Unit
	local startP = lake + towardCenter * 300
	local endP = lake + towardCenter * 230
	local planks = rgb(132, 100, 70)
	local deckY = surface + 2.2
	local a0 = Vector3.new(startP.X, deckY, startP.Z)
	local a1 = Vector3.new(endP.X, deckY, endP.Z)
	local len = (a1 - a0).Magnitude
	local cf = CFrame.lookAt(a0:Lerp(a1, 0.5), a1)
	box(m, cf, Vector3.new(10, 0.8, len), planks, M.WoodPlanks)
	for z = -len / 2, len / 2, 10 do
		for _, x in ipairs({ -4.5, 4.5 }) do
			local post = (cf * CFrame.new(x, 0, z)).Position
			column(m, post - Vector3.new(0, 14, 0), 16, 1.2, WOOD_DARK, M.Wood)
		end
	end
	local lampPos = (cf * CFrame.new(4.5, 0.4, -len / 2 + 2)).Position
	Props.streetLamp(m, lampPos, 7)
	-- small rowing boat tied at the end
	local boatCF = cf * CFrame.new(-9, -1.6, -len / 2 + 4) * CFrame.Angles(0, 0.2, 0)
	box(m, boatCF, Vector3.new(4.6, 1.6, 12), rgb(120, 82, 54), M.WoodPlanks)
	Util.wedge(m, boatCF * CFrame.new(0, 0, -7.5), Vector3.new(4.6, 1.6, 3), rgb(120, 82, 54), M.WoodPlanks)
	box(m, boatCF * CFrame.new(0, 0.6, 0), Vector3.new(4, 0.3, 1.4), rgb(90, 64, 44), M.Wood, NOSHADOW)
	return m
end

-- Cottage -----------------------------------------------------------------------------------------
local ROOFS = { rgb(70, 82, 104), rgb(128, 58, 48), rgb(84, 104, 66), rgb(96, 70, 60) }

-- Picket fence, vegetable rows and a woodpile in front of a cottage.
local function cottageGarden(m, rng, cf, W, D)
	-- picket fence around a front garden
	local fence = rgb(226, 216, 196)
	local gardenFront = -D / 2 - 14
	for x = -W / 2 - 4, W / 2 + 4, 3 do
		if math.abs(x) > 3 then
			local p = (cf * CFrame.new(x, 0, gardenFront)).Position
			local g = Landscape.heightAt(p.X, p.Z)
			box(m, CFrame.new(Vector3.new(p.X, g + 1.6, p.Z)) * cf.Rotation, Vector3.new(0.5, 4, 0.5), fence, M.Wood, NOSHADOW)
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		local a = (cf * CFrame.new(s * 3, 0, gardenFront)).Position
		local b = (cf * CFrame.new(s * (W / 2 + 4), 0, gardenFront)).Position
		local ga, gb = Landscape.heightAt(a.X, a.Z), Landscape.heightAt(b.X, b.Z)
		beam(m, Vector3.new(a.X, ga + 2.6, a.Z), Vector3.new(b.X, gb + 2.6, b.Z), 0.3, 0.6, fence, M.Wood, NOSHADOW)
	end
	-- vegetable rows and a woodpile
	for row = 0, 2 do
		local c = cf * CFrame.new(-W / 4, 0.3, -D / 2 - 5 - row * 3)
		box(m, c, Vector3.new(8, 1, 1.6), rgb(92, 64, 44), M.Ground, NOSHADOW)
		for k = -1, 1 do
			ball(m, (c * CFrame.new(k * 2.5, 0.9, 0)).Position, 1.4, rgb(90, 160, 60), M.LeafyGrass, NOCOL_NOSHADOW)
		end
	end
	for k = 0, 5 do
		local c = cf * CFrame.new(W / 2 + 2 + (k % 3) * 1.5 + (k // 3) * 0.75, 1 + (k // 3) * 1.3, 0) * CFrame.Angles(0, HALF_PI, 0)
		Util.cylinder(m, c, 6, 1.4, rgb(130, 96, 64), M.Wood, NOSHADOW)
	end
end

local function cottage(parent, rng, pos, facing)
	local cf = flatCF(pos, facing)
	local mesh = AssetLibrary.place("Cottage", parent, cf, 1, { Shingle = Util.pick(rng, ROOFS) })
	if mesh then
		local smoke = AssetLibrary.anchor(mesh, cf, Vector3.new(8, 4.5, 28.4), "ChimneySmoke")
		Util.particles(smoke, {
			Texture = Util.TEX.smoke,
			Color = Util.cs(rgb(220, 220, 220), rgb(170, 170, 170)),
			Size = Util.ns(0, 1.5, 1, 7),
			Transparency = Util.ns(0, 0.4, 1, 1),
			Lifetime = NumberRange.new(5, 8),
			Rate = 3,
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(8, 8),
			Acceleration = Vector3.new(1, 0.4, 0),
			EmissionDirection = Enum.NormalId.Top,
			LightInfluence = 1,
		})
		Util.pointLight(AssetLibrary.anchor(mesh, cf, Vector3.new(-3.4, -9.9, 10.8), "PorchLight"), rgb(255, 190, 120), 1.2, 18)
		Util.pointLight(AssetLibrary.anchor(mesh, cf, Vector3.new(0, 0, 7), "Hearth"), rgb(255, 190, 120), 1, 16)
		cottageGarden(mesh, rng, cf, 24, 18)
		return mesh
	end
	local m = Util.model(parent, "Cottage")
	local W, D, H = 24, 18, 12
	local plaster = Util.vary(rng, rgb(240, 228, 204), 0.03)
	local roofColor = Util.pick(rng, ROOFS)

	box(m, cf * CFrame.new(0, 0.5, 0), Vector3.new(W + 2, 4, D + 2), STONE, M.Cobblestone)
	box(m, cf * CFrame.new(0, 2.5 + H / 2, 0), Vector3.new(W, H, D), plaster, M.Plaster)
	-- timber framing on the long faces
	for _, z in ipairs({ -D / 2 - 0.25, D / 2 + 0.25 }) do
		for _, x in ipairs({ -W / 2 + 0.5, -W / 6, W / 6, W / 2 - 0.5 }) do
			box(m, cf * CFrame.new(x, 2.5 + H / 2, z), Vector3.new(1, H, 0.5), WOOD_DARK, M.Wood, NOSHADOW)
		end
		box(m, cf * CFrame.new(0, 2.5 + H - 0.5, z), Vector3.new(W, 1, 0.5), WOOD_DARK, M.Wood, NOSHADOW)
		box(m, cf * CFrame.new(0, 2.5 + H / 2, z), Vector3.new(W, 0.8, 0.5), WOOD_DARK, M.Wood, NOSHADOW)
	end
	for _, x in ipairs({ -W / 2 - 0.25, W / 2 + 0.25 }) do
		box(m, cf * CFrame.new(x, 2.5 + H / 2, 0), Vector3.new(0.5, 0.8, D), WOOD_DARK, M.Wood, NOSHADOW)
	end

	-- door and glowing windows on the front (-Z)
	box(m, cf * CFrame.new(0, 2.5 + 4, -D / 2 - 0.3), Vector3.new(4.4, 8, 0.4), rgb(92, 60, 40), M.WoodPlanks, NOSHADOW)
	ball(m, (cf * CFrame.new(1.4, 6.5, -D / 2 - 0.55)).Position, 0.5, rgb(214, 172, 74), M.Metal, NOCOL_NOSHADOW)
	for _, x in ipairs({ -W / 3, W / 3 }) do
		local win = box(m, cf * CFrame.new(x, 2.5 + 7.5, -D / 2 - 0.3), Vector3.new(4, 4, 0.3), rgb(255, 214, 140), M.SmoothPlastic, NOSHADOW)
		Util.surfaceLight(win, Enum.NormalId.Front, rgb(255, 200, 130), 1.2, 14, 90)
		box(m, cf * CFrame.new(x, 2.5 + 7.5, -D / 2 - 0.5), Vector3.new(4.4, 0.4, 0.2), WOOD_DARK, M.Wood, NOCOL_NOSHADOW)
		box(m, cf * CFrame.new(x, 2.5 + 7.5, -D / 2 - 0.5), Vector3.new(0.4, 4.4, 0.2), WOOD_DARK, M.Wood, NOCOL_NOSHADOW)
		box(m, cf * CFrame.new(x, 2.5 + 5.2, -D / 2 - 1), Vector3.new(5, 1, 1.4), rgb(110, 76, 50), M.Wood, NOSHADOW)
		for f = -1, 1 do
			ball(m, (cf * CFrame.new(x + f * 1.4, 2.5 + 6, -D / 2 - 1)).Position, 1, Util.pick(rng, { rgb(240, 120, 160), rgb(250, 220, 90), rgb(180, 120, 230) }), M.SmoothPlastic, NOCOL_NOSHADOW)
		end
	end

	-- steep gable roof with the ridge along the long side, and a chimney
	local roofCF = cf * CFrame.new(0, 2.5 + H, 0) * CFrame.Angles(0, HALF_PI, 0)
	Util.gableRoof(m, roofCF, D + 5, W + 4, 10, roofColor, M.RoofShingles)
	box(m, roofCF * CFrame.new(0, 10.2, 0), Vector3.new(1.2, 1, W + 4.6), WOOD_DARK, M.Wood, NOSHADOW)
	local chimney = box(m, cf * CFrame.new(W / 2 - 4, 2.5 + H + 8, D / 4), Vector3.new(3.4, 14, 3.4), STONE, M.Cobblestone)
	local top = box(m, cf * CFrame.new(W / 2 - 4, 2.5 + H + 15.5, D / 4), Vector3.new(4, 1, 4), rgb(110, 108, 104), M.Slate, NOSHADOW)
	Util.particles(top, {
		Texture = Util.TEX.smoke,
		Color = Util.cs(rgb(220, 220, 220), rgb(170, 170, 170)),
		Size = Util.ns(0, 1.5, 1, 7),
		Transparency = Util.ns(0, 0.4, 1, 1),
		Lifetime = NumberRange.new(5, 8),
		Rate = 3,
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(8, 8),
		Acceleration = Vector3.new(1, 0.4, 0),
		EmissionDirection = Enum.NormalId.Top,
		LightInfluence = 1,
	})
	chimney.Name = "Chimney"

	-- porch lantern
	local lantern = box(m, cf * CFrame.new(-3.6, 2.5 + 9.5, -D / 2 - 0.9), Vector3.new(1.2, 1.6, 1.2), rgb(255, 210, 140), M.Neon, NOCOL_NOSHADOW)
	Util.pointLight(lantern, rgb(255, 190, 120), 1.2, 18)

	cottageGarden(m, rng, cf, W, D)
	return m
end

-- Spawn clearing -------------------------------------------------------------------------------------
local function buildSpawn(parent, rng)
	local m = Util.model(parent, "WildwoodArrival")
	local center = Vector3.new(L.ForestSpawn.X, Landscape.ForestSpawnHeight, L.ForestSpawn.Z)
	local toHub = Vector3.new(-center.X, 0, -center.Z).Unit

	disc(m, center + Vector3.new(0, 0.3, 0), 1.6, 34, STONE, M.Cobblestone)
	disc(m, center + Vector3.new(0, 1.2, 0), 0.4, 26, MOSS, M.Grass, NOSHADOW)

	-- glowing rune ring
	local runes = rgb(120, 255, 190)
	for k = 0, 23 do
		local a0, a1 = k / 24 * TAU, (k + 0.6) / 24 * TAU
		local p0 = center + Vector3.new(math.cos(a0) * 26, 0.6, math.sin(a0) * 26)
		local p1 = center + Vector3.new(math.cos(a1) * 26, 0.6, math.sin(a1) * 26)
		beam(m, p0, p1, 1, 0.3, runes, M.Neon, NOCOL_NOSHADOW)
	end

	-- standing stones
	for k = 0, 11 do
		local a = k / 12 * TAU + 0.13
		local p = ground(center + Vector3.new(math.cos(a) * 40, 0, math.sin(a) * 40))
		local h = rng:NextNumber(12, 20)
		local cf = flatCF(p, center - p) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06))
		box(m, cf * CFrame.new(0, h / 2 - 2, 0), Vector3.new(6, h + 2, 3.5), Util.vary(rng, STONE, 0.06), M.Slate)
		box(m, cf * CFrame.new(0, h - 0.4, 0), Vector3.new(6.4, 1, 3.9), MOSS, M.Grass, NOSHADOW)
		box(m, cf * CFrame.new(0, h / 2, -1.85), Vector3.new(0.7, h * 0.5, 0.2), runes, M.Neon, NOCOL_NOSHADOW)
	end

	-- floating crystal above the circle
	local crystal = box(m, CFrame.new(center + Vector3.new(0, 22, 0)) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), Vector3.new(4, 4, 4), rgb(140, 255, 210), M.Neon, NOCOL_NOSHADOW)
	Util.pointLight(crystal, rgb(140, 255, 210), 2, 40)
	Util.particles(crystal, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(rgb(170, 255, 220)),
		Size = Util.ns(0, 0.6, 1, 0),
		Lifetime = NumberRange.new(2, 3),
		Rate = 12,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn_Forest"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(center + Vector3.new(0, 1.6, 0))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = M.Slate
	spawn.Color = rgb(120, 150, 130)
	spawn.Transparency = 0.4
	spawn.Enabled = Config.PLAYER_START ~= "Hub"
	spawn.Parent = m

	-- signpost towards the capital, the world tree and the lake
	local postPos = ground(center + toHub * 22 + Vector3.new(-toHub.Z, 0, toHub.X) * 10)
	column(m, postPos - Vector3.new(0, 2, 0), 14, 1.2, WOOD_DARK, M.Wood)
	local signs = {
		{ "Solkhar", toHub },
		{ "Elderheart", (L.WorldTree - center).Unit },
		{ "Mirror Lake", (L.ForestLake - center).Unit },
	}
	for i, s in ipairs(signs) do
		local dir = Vector3.new(s[2].X, 0, s[2].Z).Unit
		local p = postPos + Vector3.new(0, 12 - i * 2.2, 0) + dir * 3
		local board = box(m, CFrame.lookAt(p, p + dir) * CFrame.Angles(0, HALF_PI, 0), Vector3.new(7, 1.6, 0.4), rgb(140, 104, 70), M.WoodPlanks, NOSHADOW)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.CanvasSize = Vector2.new(350, 80)
			gui.LightInfluence = 1
			gui.Parent = board
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = s[1]
			label.TextColor3 = rgb(250, 240, 214)
			label.Font = Enum.Font.Garamond
			label.TextScaled = true
			label.Parent = gui
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		Props.streetLamp(m, ground(center + toHub * 30 + Vector3.new(-toHub.Z, 0, toHub.X) * s * 8), 9)
	end
	return m
end

-- Elven ruins ----------------------------------------------------------------------------------------
local function ruinSite(parent, rng, pos)
	local m = Util.model(parent, "ElvenRuins")
	local stone = rgb(214, 210, 196)
	local yaw = rng:NextNumber(0, TAU)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	-- broken arch
	for _, s in ipairs({ -1, 1 }) do
		local base = ground((cf * CFrame.new(s * 12, 0, 0)).Position)
		column(m, base - Vector3.new(0, 2, 0), s < 0 and 26 or 18, 4.4, stone, M.Limestone)
		box(m, CFrame.new(base + Vector3.new(0, 0.5, 0)) * cf.Rotation, Vector3.new(7, 3, 7), stone, M.Limestone)
	end
	local top = cf * CFrame.new(0, 24, 0)
	for k = 0, 3 do
		local t0, t1 = k / 6 * math.pi, (k + 1) / 6 * math.pi
		local p0 = (top * CFrame.new(-12 * math.cos(t0), 6 * math.sin(t0), 0)).Position
		local p1 = (top * CFrame.new(-12 * math.cos(t1), 6 * math.sin(t1), 0)).Position
		beam(m, p0, p1, 4, 3.4, stone, M.Limestone)
	end
	-- vines and moss
	for _ = 1, 5 do
		local p = (cf * CFrame.new(rng:NextNumber(-14, 14), rng:NextNumber(8, 22), rng:NextNumber(-1, 1))).Position
		box(m, CFrame.new(p), Vector3.new(0.5, rng:NextNumber(6, 12), 0.5), MOSS, M.Grass, NOCOL_NOSHADOW)
	end
	for _ = 1, 4 do
		local p = ground((cf * CFrame.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-30, 30))).Position)
		Props.brokenColumn(m, rng, p, stone, M.Limestone)
	end
	-- mossy steps
	for k = 0, 3 do
		local p = (cf * CFrame.new(0, 0, -10 - k * 3)).Position
		local g = Landscape.heightAt(p.X, p.Z)
		box(m, CFrame.new(Vector3.new(p.X, g - 1 + (3 - k) * 0.6, p.Z)) * cf.Rotation, Vector3.new(20 - k * 2, 2 + (3 - k) * 1.2, 3), k % 2 == 0 and stone or MOSS, M.Limestone)
	end
	return m
end

-- Glowing mushrooms -------------------------------------------------------------------------------
local function mushrooms(parent, rng, pos)
	local m = Util.model(parent, "GlowShrooms")
	local caps = { rgb(90, 220, 255), rgb(255, 120, 220), rgb(170, 255, 120) }
	local cap = Util.pick(rng, caps)
	local first
	for _ = 1, rng:NextInteger(3, 5) do
		local p = ground(pos + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5)))
		local h = rng:NextNumber(1.5, 5)
		column(m, p - Vector3.new(0, 1, 0), h + 1, 0.8, rgb(232, 226, 210), M.SmoothPlastic, NOCOL_NOSHADOW)
		local c = disc(m, p + Vector3.new(0, h, 0), 0.8, rng:NextNumber(2.4, 4.6), cap, M.Neon, NOCOL_NOSHADOW)
		first = first or c
	end
	Util.pointLight(first, cap, 1.1, 16)
	return m
end

---------------------------------------------------------------------------------------------------------
function Forest.Build(folder, rng)
	Util.log("Building Eloria Wildwood...")
	buildSpawn(folder, rng)
	buildWorldTree(folder, rng)
	buildLake(folder, rng)

	local cottages = Util.model(folder, "Cottages")
	for _, c in ipairs(Layout.forestCottages()) do
		local g = ground(c)
		local facing = Vector3.new(-c.X, 0, -c.Z).Unit
		cottage(cottages, rng, g, Vector3.new(facing.X + rng:NextNumber(-0.6, 0.6), 0, facing.Z + rng:NextNumber(-0.6, 0.6)))
	end

	-- scatter the forest
	local trees = Util.folder(folder, "Trees")
	local broadleaf, blossom, slender, ancient = Props.forestTrees(), Props.blossomTrees(), Props.slenderTrees(), Props.ancientTrees()
	local bushes = Props.bushes()
	local avoid = {
		{ L.ForestSpawn, 90 },
		{ L.WorldTree, 175 },
		{ L.ForestLake, 380 },
		{ Landscape.Waterfall and Landscape.Waterfall.center or L.ForestLake, 170 },
	}
	for _, c in ipairs(Layout.forestCottages()) do
		table.insert(avoid, { c, 60 })
	end
	local spacing = 46 / math.sqrt(math.max(Config.FOLIAGE_DENSITY, 0.05))
	local R = Landscape.MAX_COAST
	local count, ruinsBuilt, shroomCount = 0, 0, 0
	local ruinSpots = {}
	local pts = Util.scatterGrid(rng, -R, -R, R, R, spacing)
	for _, p in ipairs(pts) do
		if Layout.getZone(p.X, p.Z) == "Forest" then
			local q = Landscape.query(p.X, p.Z)
			if q.land and q.zone == "Forest" and not q.path and not q.road and not q.underwater then
				local blocked = false
				for _, a in ipairs(avoid) do
					local dx, dz = p.X - a[1].X, p.Z - a[1].Z
					if dx * dx + dz * dz < a[2] * a[2] then
						blocked = true
						break
					end
				end
				local grove = Landscape.noise2(p.X, p.Z, 1 / 700, 200)
				local chance = math.clamp(0.42 + grove * 1.5, 0.04, 0.95)
				if not blocked and rng:NextNumber() < chance and Landscape.slopeAt(p.X, p.Z) < 0.9 then
					local roll = rng:NextNumber()
					local pos = Vector3.new(p.X, q.h - 1, p.Z)
					local yaw = rng:NextNumber(0, TAU)
					if roll < 0.012 and grove > 0.05 then
						Util.place(Props.randomTemplate(rng, ancient), trees, pos - Vector3.new(0, 2, 0), yaw, rng:NextNumber(0.9, 1.2))
						if shroomCount < 120 then
							mushrooms(trees, rng, pos + Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-30, 30)))
							shroomCount += 1
						end
					elseif roll < 0.09 then
						Util.place(Props.randomTemplate(rng, blossom), trees, pos, yaw, rng:NextNumber(0.85, 1.2))
					elseif roll < 0.22 then
						Util.place(Props.randomTemplate(rng, slender), trees, pos, yaw, rng:NextNumber(0.85, 1.2))
					else
						Util.place(Props.randomTemplate(rng, broadleaf), trees, pos, yaw, rng:NextNumber(0.8, 1.35))
					end
					count += 1
					-- undergrowth
					if rng:NextNumber() < 0.45 then
						local b = Vector3.new(p.X + rng:NextNumber(-14, 14), 0, p.Z + rng:NextNumber(-14, 14))
						Util.place(Props.randomTemplate(rng, bushes), trees, Vector3.new(b.X, Landscape.heightAt(b.X, b.Z) - 0.8, b.Z), rng:NextNumber(0, TAU), rng:NextNumber(0.8, 1.4))
					end
					if grove > 0.18 and shroomCount < 120 and rng:NextNumber() < 0.04 then
						mushrooms(trees, rng, pos + Vector3.new(8, 0, 8))
						shroomCount += 1
					end
				elseif not blocked and grove < -0.2 and #ruinSpots < 5 and rng:NextNumber() < 0.01 then
					local farEnough = true
					for _, r in ipairs(ruinSpots) do
						if (r - p).Magnitude < 900 then
							farEnough = false
						end
					end
					if farEnough then
						table.insert(ruinSpots, p)
					end
				elseif not blocked and rng:NextNumber() < 0.06 then
					-- flowers and bushes in the clearings
					Util.place(Props.randomTemplate(rng, bushes), trees, Vector3.new(p.X, q.h - 0.8, p.Z), rng:NextNumber(0, TAU), rng:NextNumber(0.7, 1.1))
				end
			end
		end
		Util.breathe()
	end
	local ruins = Util.model(folder, "Ruins")
	for _, p in ipairs(ruinSpots) do
		ruinSite(ruins, rng, ground(p))
		ruinsBuilt += 1
	end
	Util.log(string.format("  %d trees, %d ruins, %d mushroom rings", count, ruinsBuilt, shroomCount))
end

return Forest
