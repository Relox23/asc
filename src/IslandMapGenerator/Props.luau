--[[
	Props
	Reusable scenery: trees, palms, lanterns, torches, rocks, cars, bones...
	Trees are built once as templates and cloned, so thousands stay fast.
]]

local Layout = require(script.Parent.IslandLayout)
local Util = require(script.Parent.Util)
local AssetLibrary = require(script.Parent.AssetLibrary)

local Props = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, ball, rod, beam, column, disc, wedge =
	Util.box, Util.ball, Util.rod, Util.beam, Util.column, Util.disc, Util.wedge
local NOCOL = { collide = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local NOSHADOW = { shadow = false }
local TAU = math.pi * 2

local templateCache = {}

local function variants(key, count, seed, build)
	local list = templateCache[key]
	if list then
		return list
	end
	list = {}
	local rng = Random.new(Layout.SEED + seed)
	for i = 1, count do
		table.insert(list, Util.template(key .. i, function(m)
			build(m, rng, i)
		end))
	end
	templateCache[key] = list
	return list
end

function Props.randomTemplate(rng, list)
	return list[rng:NextInteger(1, #list)]
end

-- Palm tree ---------------------------------------------------------------------
-- Every tree/plant list below prefers the detailed Blender meshes (in a few tints)
-- and falls back to part-built versions when they aren't imported.
local function tints(style, colors)
	local list = {}
	for _, c in ipairs(colors) do
		table.insert(list, { [style] = c })
	end
	return list
end

function Props.palms()
	local meshes = AssetLibrary.templates({ "Palm_A", "Palm_B" }, tints("Frond", { rgb(72, 134, 54), rgb(88, 148, 58), rgb(62, 120, 50) }))
	if meshes then
		return meshes
	end
	return variants("Palm", 5, 101, function(m, rng)
		local H = rng:NextNumber(26, 36)
		local lean = rng:NextNumber(3, 9)
		local bark = Util.vary(rng, rgb(132, 104, 72), 0.08)
		local prev = Vector3.new(0, -2, 0)
		local segs = 5
		for s = 1, segs do
			local t = s / segs
			local p = Vector3.new(lean * t * t, H * t, 0)
			rod(m, prev, p, 2.5 - 0.9 * t, s % 2 == 0 and bark or Util.vary(rng, bark, 0.1), M.Wood)
			prev = p
		end
		local top = prev
		ball(m, top, 2.6, rgb(96, 84, 52), M.Wood, NOCOL)
		local leaf = Util.vary(rng, rgb(70, 132, 52), 0.1)
		for f = 1, 7 do
			local a = f / 7 * TAU + rng:NextNumber(-0.25, 0.25)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local len = rng:NextNumber(11, 15)
			local mid = top + dir * len * 0.5 + Vector3.new(0, 1.8, 0)
			local tip = top + dir * len + Vector3.new(0, -rng:NextNumber(3, 6), 0)
			beam(m, top, mid, 3.6, 0.35, leaf, M.Grass, NOCOL_NOSHADOW)
			beam(m, mid, tip, 2.6, 0.35, Util.vary(rng, leaf, 0.12), M.Grass, NOCOL)
		end
		for c = 1, 3 do
			local a = c / 3 * TAU
			ball(m, top + Vector3.new(math.cos(a) * 1.3, -1.6, math.sin(a) * 1.3), 1.5, rgb(92, 66, 38), M.Wood, NOCOL_NOSHADOW)
		end
	end)
end

-- Broadleaf trees of the Wildwood -------------------------------------------------------
local FOREST_LEAVES = {
	rgb(76, 140, 58),
	rgb(92, 158, 64),
	rgb(62, 120, 52),
	rgb(110, 168, 70),
	rgb(84, 132, 46),
}
local BLOSSOMS = {
	rgb(244, 170, 200),
	rgb(250, 214, 228),
	rgb(206, 170, 236),
	rgb(255, 236, 200),
}

local function canopyTree(m, rng, leafColors, H, trunkD, puffs, puffSize)
	local bark = Util.vary(rng, rgb(98, 74, 52), 0.1)
	column(m, Vector3.new(0, -2, 0), 5, trunkD * 1.45, bark, M.Wood)
	local bend = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
	local mid = Vector3.new(0, H * 0.5, 0) + bend
	local top = Vector3.new(0, H * 0.8, 0) + bend * 1.6
	rod(m, Vector3.new(0, 0, 0), mid, trunkD, bark, M.Wood)
	rod(m, mid, top, trunkD * 0.72, bark, M.Wood)
	local tips = { top + Vector3.new(0, H * 0.18, 0) }
	for b = 1, 2 do
		local a = rng:NextNumber(0, TAU)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local from = mid:Lerp(top, rng:NextNumber(0.2, 0.7))
		local to = from + dir * H * rng:NextNumber(0.28, 0.4) + Vector3.new(0, H * 0.22, 0)
		rod(m, from, to, trunkD * 0.45, bark, M.Wood, NOSHADOW)
		table.insert(tips, to)
	end
	for p = 1, puffs do
		local base = tips[(p - 1) % #tips + 1]
		local off = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.4, 0.6), rng:NextNumber(-1, 1)) * puffSize * 0.45
		local size = puffSize * rng:NextNumber(0.75, 1.15)
		ball(m, base + off, size, Util.vary(rng, Util.pick(rng, leafColors), 0.07), M.LeafyGrass, NOCOL)
	end
end

function Props.forestTrees()
	local meshes = AssetLibrary.templates({ "Broadleaf_A", "Broadleaf_B", "Broadleaf_C" }, tints("Leaves", { FOREST_LEAVES[1], FOREST_LEAVES[2], FOREST_LEAVES[5] }))
	if meshes then
		return meshes
	end
	return variants("WildwoodTree", 8, 202, function(m, rng)
		canopyTree(m, rng, FOREST_LEAVES, rng:NextNumber(24, 36), rng:NextNumber(2.6, 3.8), 5, rng:NextNumber(15, 21))
	end)
end

-- Petals drifting down from a blossom tree's canopy.
local function addPetals(m, color, height)
	if m:FindFirstChild("Petals") then
		return -- templates are shared, add this once
	end
	local glow = box(m, CFrame.new(0, height, 0), Vector3.new(1, 1, 1), color, M.SmoothPlastic, {
		collide = false,
		shadow = false,
		transparency = 1,
	})
	glow.Name = "Petals"
	Util.particles(glow, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(color),
		Size = Util.ns(0, 0.5, 1, 0.3),
		Transparency = Util.ns(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(5, 8),
		Rate = 2,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0.6, -1.2, 0.3),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Shape = Enum.ParticleEmitterShape.Sphere,
	})
end

function Props.blossomTrees()
	local meshes = AssetLibrary.templates({ "Blossom_A", "Blossom_B" }, tints("Blossom", BLOSSOMS))
	if meshes then
		for _, t in ipairs(meshes) do
			local blossom = AssetLibrary.piece(t, "Blossom")
			addPetals(t, blossom and blossom.Color or BLOSSOMS[1], 18)
		end
		return meshes
	end
	return variants("BlossomTree", 4, 203, function(m, rng, i)
		local petals = { BLOSSOMS[(i - 1) % #BLOSSOMS + 1] }
		canopyTree(m, rng, petals, rng:NextNumber(20, 28), rng:NextNumber(2.4, 3.2), 5, rng:NextNumber(13, 18))
		addPetals(m, petals[1], 24)
	end)
end

-- Slender pale-barked trees
function Props.slenderTrees()
	local meshes = AssetLibrary.templates({ "SilverTree" })
	if meshes then
		return meshes
	end
	return variants("SilverTree", 3, 204, function(m, rng)
		local H = rng:NextNumber(34, 46)
		local bark = rgb(226, 222, 210)
		rod(m, Vector3.new(0, -2, 0), Vector3.new(rng:NextNumber(-1, 1), H, rng:NextNumber(-1, 1)), 2.2, bark, M.Wood)
		for b = 1, 3 do
			local y = H * (0.25 + b * 0.2)
			box(m, CFrame.new(0, y, 0) * CFrame.Angles(0, b, 0), Vector3.new(2.3, 0.6, 2.3), rgb(60, 56, 52), M.Wood, NOCOL_NOSHADOW)
		end
		local leaf = Util.vary(rng, rgb(150, 190, 80), 0.1)
		for p = 1, 3 do
			ball(m, Vector3.new(rng:NextNumber(-2, 2), H * (0.55 + p * 0.13), rng:NextNumber(-2, 2)), 12 - p * 1.5, leaf, M.LeafyGrass, NOCOL)
		end
	end)
end

-- Rare giant trees with hanging vines and glowing mushrooms
function Props.ancientTrees()
	local meshes = AssetLibrary.templates({ "AncientTree" })
	if meshes then
		return meshes
	end
	return variants("AncientTree", 3, 205, function(m, rng)
		local H = rng:NextNumber(70, 92)
		local D = rng:NextNumber(13, 17)
		local bark = Util.vary(rng, rgb(88, 66, 48), 0.08)
		local moss = rgb(74, 110, 52)
		column(m, Vector3.new(0, -4, 0), 10, D * 1.6, bark, M.Wood)
		-- roots
		for r = 1, 6 do
			local a = r / 6 * TAU + rng:NextNumber(-0.2, 0.2)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			rod(m, dir * D * 0.3 + Vector3.new(0, 7, 0), dir * D * 1.6 + Vector3.new(0, -2, 0), D * 0.32, r % 2 == 0 and moss or bark, M.Wood)
		end
		local mid = Vector3.new(rng:NextNumber(-3, 3), H * 0.55, rng:NextNumber(-3, 3))
		local top = Vector3.new(rng:NextNumber(-5, 5), H * 0.85, rng:NextNumber(-5, 5))
		rod(m, Vector3.new(0, 0, 0), mid, D, bark, M.Wood)
		rod(m, mid, top, D * 0.75, bark, M.Wood)
		local tips = { top + Vector3.new(0, 10, 0) }
		for b = 1, 5 do
			local a = b / 5 * TAU + rng:NextNumber(-0.3, 0.3)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local from = mid:Lerp(top, rng:NextNumber(0.1, 0.9))
			local to = from + dir * rng:NextNumber(22, 32) + Vector3.new(0, rng:NextNumber(8, 18), 0)
			rod(m, from, to, D * 0.36, bark, M.Wood)
			table.insert(tips, to)
		end
		for p = 1, 10 do
			local base = tips[(p - 1) % #tips + 1]
			local off = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-4, 8), rng:NextNumber(-12, 12))
			ball(m, base + off, rng:NextNumber(30, 44), Util.vary(rng, Util.pick(rng, FOREST_LEAVES), 0.08), M.LeafyGrass, NOCOL)
		end
		-- hanging vines
		for v = 1, 8 do
			local base = tips[(v - 1) % #tips + 1] + Vector3.new(rng:NextNumber(-10, 10), -8, rng:NextNumber(-10, 10))
			local len = rng:NextNumber(16, 30)
			box(m, CFrame.new(base - Vector3.new(0, len / 2, 0)), Vector3.new(0.6, len, 0.6), moss, M.Grass, NOCOL_NOSHADOW)
		end
		-- glowing mushrooms between the roots
		for s = 1, 4 do
			local a = s / 4 * TAU + 0.4
			local p = Vector3.new(math.cos(a), 0, math.sin(a)) * D * 1.1
			local h = rng:NextNumber(2, 4)
			column(m, p, h, 0.9, rgb(230, 226, 210), M.SmoothPlastic, NOCOL_NOSHADOW)
			local cap = disc(m, p + Vector3.new(0, h, 0), 1, rng:NextNumber(3, 4.5), rgb(90, 220, 255), M.Neon, NOCOL_NOSHADOW)
			if s == 1 then
				Util.pointLight(cap, rgb(110, 220, 255), 1.2, 18)
			end
		end
	end)
end

-- Snowy pines ---------------------------------------------------------------------------
-- Each tier is four wedges sloping outwards; alternate tiers are turned 45 degrees.
local function pineTier(m, y, radius, height, color, material, turn)
	for q = 0, 3 do
		local a = q * math.pi / 2 + turn
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local c = Vector3.new(0, y + height / 2, 0) + dir * (radius / 2)
		wedge(m, CFrame.lookAt(c, c + dir), Vector3.new(radius * 1.2, height, radius), color, material, NOCOL)
	end
end

function Props.pines()
	local meshes = AssetLibrary.templates({ "Pine_A", "Pine_B", "Pine_C" })
	if meshes then
		return meshes
	end
	return variants("SnowPine", 8, 301, function(m, rng, i)
		local H = rng:NextNumber(38, 62)
		local bark = rgb(74, 56, 44)
		rod(m, Vector3.new(0, -3, 0), Vector3.new(0, H * 0.75, 0), H * 0.045, bark, M.Wood)
		local snowy = i % 3 == 0
		local green = Util.vary(rng, rgb(32, 62, 48), 0.1)
		local snow = rgb(236, 243, 248)
		local tiers = 3
		for k = 1, tiers do
			local t = (k - 1) / tiers
			local y = H * (0.16 + t * 0.6)
			local r = H * (0.33 - t * 0.24)
			local h = H * 0.36
			local color, mat = green, M.Grass
			if snowy or k == tiers or (k % 2 == 0 and rng:NextNumber() < 0.5) then
				color, mat = snow, M.Snow
			end
			pineTier(m, y, r, h, color, mat, (k % 2) * math.pi / 4)
		end
	end)
end

-- Bare winter tree (no leaves), used around the village and temple.
function Props.bareTrees()
	local meshes = AssetLibrary.templates({ "BareTree" })
	if meshes then
		return meshes
	end
	return variants("BareTree", 3, 302, function(m, rng)
		local bark = rgb(60, 48, 42)
		local function branch(from, dir, len, d, depth)
			local to = from + dir * len
			rod(m, from, to, d, bark, M.Wood, NOSHADOW)
			if depth > 0 then
				for _ = 1, 3 do
					local nd = (dir + Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(0.1, 0.6), rng:NextNumber(-0.8, 0.8))).Unit
					branch(to, nd, len * 0.66, d * 0.6, depth - 1)
				end
			else
				ball(m, to, d * 3, rgb(240, 246, 250), M.Snow, NOCOL_NOSHADOW)
			end
		end
		branch(Vector3.new(0, -2, 0), Vector3.new(0, 1, 0), rng:NextNumber(14, 20), 2.6, 2)
	end)
end

-- Crystal-white dead trees of the Hollow Expanse
function Props.quartzTrees()
	local meshes = AssetLibrary.templates({ "QuartzTree_A", "QuartzTree_B" })
	if meshes then
		return meshes
	end
	return variants("QuartzTree", 6, 401, function(m, rng)
		local color = rgb(236, 240, 246)
		local function branch(from, dir, len, d, depth)
			local to = from + dir * len
			rod(m, from, to, d, color, M.Glass, { reflectance = 0.15, transparency = 0.08 })
			if depth > 0 then
				local count = rng:NextInteger(2, 3)
				for _ = 1, count do
					local nd = (dir + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.1, 0.5), rng:NextNumber(-1, 1)) * 0.8).Unit
					branch(to, nd, len * rng:NextNumber(0.55, 0.75), d * 0.58, depth - 1)
				end
			end
		end
		local lean = Vector3.new(rng:NextNumber(-0.2, 0.2), 1, rng:NextNumber(-0.2, 0.2)).Unit
		branch(Vector3.new(0, -3, 0), lean, rng:NextNumber(14, 22), rng:NextNumber(2.2, 3.2), 2)
	end)
end

-- Bushes --------------------------------------------------------------------------------
function Props.bushes()
	local meshes = AssetLibrary.templates({ "Bush_A", "Bush_B" }, tints("Leaves", { FOREST_LEAVES[1], FOREST_LEAVES[3], FOREST_LEAVES[4] }))
	if meshes then
		return meshes
	end
	return variants("Bush", 6, 501, function(m, rng, i)
		local leaf = Util.vary(rng, FOREST_LEAVES[(i - 1) % #FOREST_LEAVES + 1], 0.08)
		for b = 1, rng:NextInteger(2, 3) do
			ball(m, Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(1, 2.5), rng:NextNumber(-3, 3)), rng:NextNumber(5, 8), leaf, M.LeafyGrass, NOCOL)
		end
		if i % 2 == 0 then
			local flower = BLOSSOMS[(i / 2 - 1) % #BLOSSOMS + 1]
			for f = 1, 4 do
				local a = f / 4 * TAU
				ball(m, Vector3.new(math.cos(a) * 3, 4, math.sin(a) * 3), 1.2, flower, M.SmoothPlastic, NOCOL_NOSHADOW)
			end
		end
	end)
end

-- Lanterns, torches, lights ----------------------------------------------------------------

-- Japanese stone lantern (toro). position is the ground point.
function Props.stoneLantern(parent, position, yaw, snowy)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0)
	local mesh = AssetLibrary.place("StoneLantern", parent, cf)
	if mesh then
		local fx = AssetLibrary.anchor(mesh, cf, Vector3.new(0, 0, 7.8), "Light")
		Util.pointLight(fx, rgb(255, 178, 96), 1.4, 22, false)
		if not snowy then
			for _, p in ipairs(mesh:GetChildren()) do
				if p:GetAttribute("Style") == "Snow" then
					p:Destroy()
				end
			end
		end
		return mesh
	end
	local m = Util.model(parent, "StoneLantern")
	local stone = rgb(150, 148, 142)
	box(m, cf * CFrame.new(0, 0.6, 0), Vector3.new(4.4, 1.2, 4.4), stone, M.Granite)
	column(m, (cf * CFrame.new(0, 1.2, 0)).Position, 4.5, 1.8, stone, M.Granite)
	box(m, cf * CFrame.new(0, 6, 0), Vector3.new(3.6, 0.8, 3.6), stone, M.Granite)
	local light = box(m, cf * CFrame.new(0, 7.4, 0), Vector3.new(2.6, 2, 2.6), rgb(255, 196, 120), M.Neon, NOSHADOW)
	Util.pointLight(light, rgb(255, 178, 96), 1.4, 22, false)
	Util.hipRoof(m, cf * CFrame.new(0, 8.4, 0), 5.6, 5.6, 1.8, 0.6, stone, M.Granite)
	ball(m, (cf * CFrame.new(0, 10.4, 0)).Position, 1.2, stone, M.Granite)
	if snowy then
		box(m, cf * CFrame.new(0, 9.9, 0), Vector3.new(3.4, 0.6, 3.4), rgb(240, 246, 252), M.Snow, NOSHADOW)
	end
	return m
end

-- Standing torch with real fire.
function Props.torch(parent, position, height, color)
	height = height or 9
	local m = Util.model(parent, "Torch")
	column(m, position, height, 0.9, rgb(70, 52, 38), M.Wood)
	local bowl = disc(m, position + Vector3.new(0, height, 0), 1, 2.6, color or rgb(196, 160, 72), M.Metal)
	Util.fire(bowl, 3, 7)
	Util.pointLight(bowl, rgb(255, 150, 70), 1.6, 26, false)
	return m
end

-- Tall street lamp with a warm lantern.
function Props.streetLamp(parent, position, height)
	height = height or 14
	local scale = height / 13.4
	local mesh = AssetLibrary.place("StreetLamp", parent, CFrame.new(position), scale)
	if mesh then
		local fx = AssetLibrary.anchor(mesh, CFrame.new(position), Vector3.new(0, 0, 15.4), "Light")
		Util.pointLight(fx, rgb(255, 196, 120), 1.5, 30, false)
		return mesh
	end
	local m = Util.model(parent, "Lamp")
	local metal = rgb(62, 56, 48)
	column(m, position, height, 0.8, metal, M.Metal)
	disc(m, position + Vector3.new(0, 0.4, 0), 0.8, 2.4, metal, M.Metal)
	local lamp = box(m, CFrame.new(position + Vector3.new(0, height + 1.4, 0)), Vector3.new(1.8, 2.4, 1.8), rgb(255, 214, 150), M.Neon, NOSHADOW)
	Util.pointLight(lamp, rgb(255, 196, 120), 1.5, 30, false)
	box(m, CFrame.new(position + Vector3.new(0, height + 2.9, 0)), Vector3.new(2.6, 0.6, 2.6), metal, M.Metal)
	return m
end

-- Rocks ------------------------------------------------------------------------------------
-- A cluster of tilted stone blocks (cheap, looks good on beaches and in ruins).
function Props.rockCluster(parent, rng, position, size, color, material)
	local m = Util.model(parent, "Rocks")
	for _ = 1, rng:NextInteger(2, 4) do
		local s = Vector3.new(rng:NextNumber(0.6, 1.2), rng:NextNumber(0.4, 0.9), rng:NextNumber(0.6, 1.2)) * size
		local cf = CFrame.new(position + Vector3.new(rng:NextNumber(-0.6, 0.6) * size, s.Y * 0.2, rng:NextNumber(-0.6, 0.6) * size))
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), rng:NextNumber(-0.4, 0.4))
		box(m, cf, s, Util.vary(rng, color, 0.08), material or M.Rock)
	end
	return m
end

-- Broken classical column lying or standing.
function Props.brokenColumn(parent, rng, position, color, material)
	local m = Util.model(parent, "BrokenColumn")
	local d = rng:NextNumber(5, 8)
	if rng:NextNumber() < 0.5 then
		local h = rng:NextNumber(8, 26)
		box(m, CFrame.new(position + Vector3.new(0, 1, 0)), Vector3.new(d * 1.5, 2, d * 1.5), color, material)
		column(m, position + Vector3.new(0, 2, 0), h, d, color, material)
		box(m, CFrame.new(position + Vector3.new(0, h + 2.3, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)),
			Vector3.new(d * 0.9, 1.2, d * 0.9), color, material)
	else
		local a = rng:NextNumber(0, TAU)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local len = rng:NextNumber(14, 30)
		rod(m, position + Vector3.new(0, d * 0.35, 0), position + dir * len + Vector3.new(0, d * 0.3, 0), d, color, material)
		local p2 = position + dir * (len + d * 0.9) + Vector3.new(0, d * 0.3, 0)
		rod(m, p2, p2 + (dir + Vector3.new(0.4, 0, 0.5)).Unit * len * 0.4, d, color, material)
	end
	return m
end

-- Giant skeleton half buried in sand: spine, ribs and a horned skull.
function Props.giantSkeleton(parent, rng, position, yaw, scale)
	local mesh = AssetLibrary.place("Skeleton", parent, CFrame.new(position) * CFrame.Angles(0, yaw, 0), scale)
	if mesh then
		return mesh
	end
	local m = Util.model(parent, "AncientRemains")
	local bone = rgb(232, 226, 208)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local segs = 18
	local spine = {}
	for s = 0, segs do
		local t = s / segs
		local p = cf * Vector3.new(0, (4 + math.sin(t * math.pi) * 10) * scale, (t - 0.5) * 140 * scale)
		spine[s] = p
		ball(m, p, (5 - t * 2) * scale, bone, M.Marble)
	end
	for s = 3, 12 do
		local p = spine[s]
		local ribLen = (34 - math.abs(s - 7) * 3) * scale
		for side = -1, 1, 2 do
			local prev = p
			for k = 1, 4 do
				local a = k / 4 * math.pi * 0.9
				local q = p + cf:VectorToWorldSpace(Vector3.new(side * math.sin(a) * ribLen * 0.55, (math.cos(a) - 1) * ribLen * 0.45, 0))
				rod(m, prev, q, 1.6 * scale, bone, M.Marble, NOSHADOW)
				prev = q
			end
		end
	end
	local head = spine[segs] + cf.LookVector * -14 * scale + Vector3.new(0, -2 * scale, 0)
	ball(m, head, 22 * scale, bone, M.Marble)
	box(m, CFrame.lookAt(head, head - cf.LookVector) * CFrame.new(0, -6 * scale, -12 * scale), Vector3.new(14, 5, 18) * scale, bone, M.Marble)
	for side = -1, 1, 2 do
		local eye = head + cf:VectorToWorldSpace(Vector3.new(side * 5 * scale, 3 * scale, 9 * scale))
		ball(m, eye, 6 * scale, rgb(30, 28, 32), M.SmoothPlastic, NOCOL)
		local hornBase = head + cf:VectorToWorldSpace(Vector3.new(side * 8 * scale, 8 * scale, -2 * scale))
		local hornTip = hornBase + cf:VectorToWorldSpace(Vector3.new(side * 10, 18, -14) * scale)
		rod(m, hornBase, hornTip, 3 * scale, bone, M.Marble)
	end
	return m
end

-- Burnt-out car for the ruined city.
local CAR_PAINT = { rgb(110, 58, 40), rgb(70, 70, 74), rgb(140, 128, 108), rgb(96, 40, 36), rgb(52, 64, 72), rgb(150, 120, 60) }
function Props.wreckedCar(parent, rng, groundCF)
	local paint = Util.vary(rng, Util.pick(rng, CAR_PAINT), 0.1)
	local mesh = AssetLibrary.place(rng:NextNumber() < 0.6 and "Car_A" or "Car_B", parent, groundCF, 1, { Paint = paint })
	if mesh then
		return mesh
	end
	local m = Util.model(parent, "WreckedCar")
	local rust = rgb(102, 62, 40)
	local glass = rgb(20, 22, 26)
	box(m, groundCF * CFrame.new(0, 2.4, 0), Vector3.new(7, 2.6, 15), paint, M.CorrodedMetal)
	box(m, groundCF * CFrame.new(0, 4.6, 0.8) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, 0), Vector3.new(6.2, 2.2, 7.2), paint, M.CorrodedMetal)
	box(m, groundCF * CFrame.new(0, 4.6, 0.8), Vector3.new(6.4, 1.6, 6), glass, M.Glass, NOSHADOW)
	box(m, groundCF * CFrame.new(0, 2.6, -7.4), Vector3.new(6.6, 1.4, 0.6), rust, M.CorrodedMetal, NOSHADOW)
	for _, w in ipairs({ { -3.4, -4.6 }, { 3.4, -4.6 }, { -3.4, 4.6 }, { 3.4, 4.6 } }) do
		if rng:NextNumber() < 0.8 then
			Util.cylinder(m, groundCF * CFrame.new(w[1], 1.4, w[2]), 1.2, 2.8, rgb(24, 22, 22), M.Rubber, NOSHADOW)
		end
	end
	return m
end

-- Leaning, broken lamp post for the ruins
function Props.brokenLamp(parent, rng, position)
	local m = Util.model(parent, "BrokenLamp")
	local metal = rgb(56, 52, 50)
	local bend = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	local mid = position + Vector3.new(0, 12, 0) + bend * 2
	local top = mid + (Vector3.new(0, 1, 0) + bend * rng:NextNumber(0.6, 1.6)).Unit * 10
	rod(m, position - Vector3.new(0, 2, 0), mid, 0.8, metal, M.CorrodedMetal)
	rod(m, mid, top, 0.7, metal, M.CorrodedMetal)
	rod(m, top, top + (bend + Vector3.new(0, -0.3, 0)).Unit * 4, 0.6, metal, M.CorrodedMetal)
	return m
end

-- Smouldering fire with smoke, for ruins and camps.
function Props.smoulder(parent, position, big)
	local p = box(parent, CFrame.new(position), Vector3.new(4, 1, 4), rgb(30, 26, 24), M.Basalt, { collide = false, shadow = false, transparency = 1 })
	p.Name = "Smoulder"
	Util.particles(p, {
		Texture = Util.TEX.smoke,
		Color = Util.cs(rgb(40, 38, 38), rgb(90, 86, 84)),
		Size = Util.ns(0, big and 8 or 4, 1, big and 34 or 16),
		Transparency = Util.ns(0, 0.5, 1, 1),
		Lifetime = NumberRange.new(8, 14),
		Rate = big and 6 or 3,
		Speed = NumberRange.new(6, 10),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = Vector3.new(2, 1, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		LightInfluence = 1,
	})
	Util.particles(p, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(rgb(255, 150, 60), rgb(255, 70, 20)),
		Size = Util.ns(0, 0.4, 1, 0),
		Lifetime = NumberRange.new(2, 4),
		Rate = big and 14 or 6,
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(30, 30),
		LightEmission = 1,
	})
	Util.pointLight(p, rgb(255, 110, 40), 2, big and 40 or 22, false)
	return p
end

return Props
