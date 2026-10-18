--[[
	TerrainWriter
	Writes the landscape into Roblox terrain, 256x256 stud chunk by chunk.
	Open sea is filled with big FillBlock calls; every chunk that touches the
	island is written voxel by voxel with WriteVoxels.
]]

local Layout = require(script.Parent.IslandLayout)
local Landscape = require(script.Parent.Landscape)
local Util = require(script.Parent.Util)
local Waterworks = require(script.Parent.Waterworks)

local TerrainWriter = {}

local M = Enum.Material
local AIR, WATER, ICE = M.Air, M.Water, M.Ice
local STRATA = Landscape.STRATA
local STRATA_MATS = { M.Sandstone, M.Sandstone, M.Limestone, M.Sandstone, M.Rock }

local VOX = 4
local CHUNK = 256
local N = CHUNK / VOX
local BOTTOM = Landscape.BOTTOM
local SEABED = Landscape.SEABED

local BANK_SLOPE = 0.75
local CLIFF_SLOPE = 1.2

-- Terrain colours. These are global per material, so each material is used by one region.
TerrainWriter.MaterialColors = {
	Grass = Color3.fromRGB(92, 156, 66),
	LeafyGrass = Color3.fromRGB(70, 128, 54),
	Ground = Color3.fromRGB(112, 88, 62),
	Sand = Color3.fromRGB(228, 194, 132),
	Sandstone = Color3.fromRGB(200, 150, 100),
	Limestone = Color3.fromRGB(230, 214, 178),
	Pavement = Color3.fromRGB(204, 184, 146),
	Salt = Color3.fromRGB(236, 237, 242),
	Slate = Color3.fromRGB(176, 180, 190),
	Mud = Color3.fromRGB(30, 28, 32),
	Basalt = Color3.fromRGB(56, 52, 54),
	Snow = Color3.fromRGB(242, 247, 255),
	Glacier = Color3.fromRGB(190, 222, 238),
	Ice = Color3.fromRGB(166, 208, 232),
	Rock = Color3.fromRGB(116, 117, 124),
	Cobblestone = Color3.fromRGB(128, 124, 118),
}

local function applyColors(terrain)
	for name, color in pairs(TerrainWriter.MaterialColors) do
		terrain:SetMaterialColor(M[name], color)
	end
	terrain.WaterColor = Color3.fromRGB(22, 112, 140)
	terrain.WaterReflectance = 0.55
	terrain.WaterTransparency = 0.7
	terrain.WaterWaveSize = 0.22
	terrain.WaterWaveSpeed = 11
	pcall(function()
		terrain.Decoration = true -- animated grass blades
	end)
end

local function writeChunk(terrain, cx, cz)
	-- Sample one column ring wider than the chunk so slopes are right at the edges.
	local hs, surf, bank, cliff, sub, wl, frz = {}, {}, {}, {}, {}, {}, {}
	local maxTop = Layout.SEA_LEVEL
	for i = 0, N + 1 do
		local x = cx + (i - 1) * VOX + VOX / 2
		local hrow = table.create(N + 2)
		hs[i] = hrow
		if i >= 1 and i <= N then
			surf[i], bank[i], cliff[i], sub[i], wl[i], frz[i] = {}, {}, {}, {}, {}, {}
		end
		for k = 0, N + 1 do
			local z = cz + (k - 1) * VOX + VOX / 2
			if i >= 1 and i <= N and k >= 1 and k <= N then
				local h, s1, s2, s3, s4, w, f = Landscape.sample(x, z)
				hrow[k] = h
				surf[i][k], bank[i][k], cliff[i][k], sub[i][k], wl[i][k], frz[i][k] = s1, s2, s3, s4, w, f
				if h > maxTop then
					maxTop = h
				end
				if w > maxTop then
					maxTop = w
				end
			else
				hrow[k] = Landscape.heightAt(x, z)
			end
		end
	end

	local yMin = BOTTOM
	local yMax = math.ceil((maxTop + 8) / VOX) * VOX
	local ny = (yMax - yMin) / VOX

	local mats = table.create(N)
	local occs = table.create(N)
	for i = 1, N do
		local mi, oi = table.create(ny), table.create(ny)
		mats[i], occs[i] = mi, oi
		for j = 1, ny do
			mi[j] = table.create(N, AIR)
			oi[j] = table.create(N, 0)
		end
	end

	for i = 1, N do
		local mi, oi = mats[i], occs[i]
		local hprev, hcur, hnext = hs[i - 1], hs[i], hs[i + 1]
		for k = 1, N do
			local h = hcur[k]
			local slope = math.max(math.abs(hnext[k] - hprev[k]), math.abs(hcur[k + 1] - hcur[k - 1])) / (2 * VOX)
			local top = surf[i][k]
			if slope > CLIFF_SLOPE then
				top = cliff[i][k]
			elseif slope > BANK_SLOPE then
				top = bank[i][k]
			end
			local deep = sub[i][k]
			local water = wl[i][k]
			local frozen = frz[i][k]
			for j = 1, ny do
				local yb = yMin + (j - 1) * VOX
				local occ = (h - yb) / VOX
				if occ > 0.02 then
					if occ > 1 then
						occ = 1
					end
					local mat
					if h - yb < 7 then
						mat = top
					elseif deep == STRATA then
						mat = STRATA_MATS[(math.floor((yb + 1000) / 12) % #STRATA_MATS) + 1]
					else
						mat = deep
					end
					mi[j][k] = mat
					oi[j][k] = occ
				elseif yb < water then
					if frozen and yb >= water - 8 then
						mi[j][k] = ICE
					else
						mi[j][k] = WATER
					end
					oi[j][k] = 1
				else
					break
				end
			end
		end
	end

	local region = Region3.new(Vector3.new(cx, yMin, cz), Vector3.new(cx + CHUNK, yMax, cz + CHUNK)):ExpandToGrid(VOX)
	terrain:WriteVoxels(region, VOX, mats, occs)
end

function TerrainWriter.Generate()
	Landscape.init()
	local terrain = workspace.Terrain
	applyColors(terrain)

	local ext = Layout.OCEAN_EXTENT
	local landReach = Landscape.MAX_COAST + 760
	local total = (2 * ext / CHUNK) ^ 2
	local done, landChunks = 0, 0
	local lastReport = -1
	local started = os.clock()

	local function oceanRun(x0, x1, cz)
		local w = x1 - x0
		local cxm = (x0 + x1) / 2
		terrain:FillBlock(
			CFrame.new(cxm, (BOTTOM + SEABED) / 2, cz + CHUNK / 2),
			Vector3.new(w, SEABED - BOTTOM, CHUNK),
			M.Sand
		)
		terrain:FillBlock(
			CFrame.new(cxm, (SEABED + Layout.SEA_LEVEL) / 2, cz + CHUNK / 2),
			Vector3.new(w, Layout.SEA_LEVEL - SEABED, CHUNK),
			WATER
		)
	end

	for cz = -ext, ext - CHUNK, CHUNK do
		local runStart = nil
		for cx = -ext, ext - CHUNK, CHUNK do
			local nx = math.clamp(0, cx, cx + CHUNK)
			local nz = math.clamp(0, cz, cz + CHUNK)
			local nearest = math.sqrt(nx * nx + nz * nz)
			if nearest > landReach then
				runStart = runStart or cx
			else
				if runStart then
					oceanRun(runStart, cx, cz)
					runStart = nil
				end
				writeChunk(terrain, cx, cz)
				landChunks += 1
			end
			done += 1
			Util.breathe()
		end
		if runStart then
			oceanRun(runStart, ext, cz)
		end
		local pct = math.floor(done / total * 20) * 5
		if pct ~= lastReport then
			lastReport = pct
			Util.log(string.format("Terrain %d%% (%d island chunks, %.0fs)", pct, landChunks, os.clock() - started))
		end
	end
	-- fountains, pools and the waterfall are terrain water too
	Waterworks.Build()
end

-- Terrain shapes added on top of the base landscape -----------------------------

-- A boulder made of a few overlapping terrain balls.
function TerrainWriter.boulder(rng, pos, size, material)
	local terrain = workspace.Terrain
	terrain:FillBall(pos, size, material)
	for _ = 1, rng:NextInteger(1, 3) do
		local off = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.6), rng:NextNumber(-1, 1)) * size * 0.7
		terrain:FillBall(pos + off, size * rng:NextNumber(0.45, 0.8), material)
	end
end

-- A leaning rock spire made of stacked, shrinking cylinders.
function TerrainWriter.spire(rng, base, height, radius, material, lean)
	local terrain = workspace.Terrain
	local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(1, 0, 0)
	end
	dir = dir.Unit
	local up = (Vector3.new(0, 1, 0) + dir * (lean or 0.15)).Unit
	local segments = math.max(2, math.floor(height / 40))
	local segH = height / segments
	local p = base - Vector3.new(0, 10, 0)
	for s = 1, segments do
		local r = radius * (1 - (s - 1) / segments * 0.7)
		local c = p + up * (segH / 2)
		terrain:FillCylinder(CFrame.lookAt(c, c + up) * CFrame.Angles(math.pi / 2, 0, 0), segH + 6, r, material)
		p = p + up * segH
		up = (up + Vector3.new(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))).Unit
	end
	terrain:FillBall(p, radius * 0.35, material)
end

-- A natural stone arch from a to b.
function TerrainWriter.arch(base1, base2, height, thickness, material)
	local terrain = workspace.Terrain
	local steps = 24
	for s = 0, steps do
		local t = s / steps
		local p = base1:Lerp(base2, t) + Vector3.new(0, math.sin(t * math.pi) * height, 0)
		local r = thickness * (1.25 - 0.45 * math.sin(t * math.pi))
		terrain:FillBall(p, r, material)
	end
end

return TerrainWriter
