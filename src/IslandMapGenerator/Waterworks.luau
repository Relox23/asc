--[[
	Waterworks
	Real (terrain) water for the built water features: the capital's fountain
	basins and their upper bowls, the reflecting pools in front of the palace,
	and the waterfall that pours off the plateau into Mirror Lake (a spring pool,
	a stream to the cliff edge and the falling curtain of water).

	Terrain water comes in 4-stud voxels, so every feature here lines up with
	that grid; the stone rims around them then hide nothing and the water
	edges stay perfectly straight. Players can swim in all of it.
]]

local Layout = require(script.Parent.IslandLayout)
local Landscape = require(script.Parent.Landscape)

local Waterworks = {}

local function snap(v)
	return math.floor(v / 4 + 0.5) * 4
end
Waterworks.snap = snap

local TOP = Layout.HUB_HEIGHT
Waterworks.BASIN_TOP = math.floor((TOP + 2) / 4) * 4 -- fountain water surface (152 on the default mesa)
Waterworks.BASIN_HALF = 12 -- the basin holds a 24 x 24 stud square of water
Waterworks.BOWL_HALF = 4 -- the upper bowl holds 8 x 8

-- Fountain plaza centres on each avenue of the capital, snapped to the voxel grid.
function Waterworks.fountainCenters()
	local out = {}
	for _, id in ipairs(Layout.ZONE_ORDER) do
		local p = Layout.zoneDirection(id) * 412
		table.insert(out, Vector3.new(snap(p.X), TOP, snap(p.Z)))
	end
	return out
end

-- Two long pools flanking the approach to the palace. Only built when the Forest
-- avenue runs along a world axis (true for the default layout).
function Waterworks.palacePools()
	local dir = Layout.zoneDirection("Forest")
	if math.abs(dir.X) > 1e-6 and math.abs(dir.Z) > 1e-6 then
		return {}
	end
	dir = Vector3.new(math.round(dir.X), 0, math.round(dir.Z))
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local floorY = TOP + 12 -- top of the first palace terrace
	local bottom = math.floor(floorY / 4) * 4
	local pools = {}
	for _, s in ipairs({ -1, 1 }) do
		local a = dir * 164 + side * (s * 28)
		local b = dir * 216 + side * (s * 44)
		table.insert(pools, {
			min = Vector3.new(math.min(a.X, b.X), bottom, math.min(a.Z, b.Z)),
			max = Vector3.new(math.max(a.X, b.X), bottom + 4, math.max(a.Z, b.Z)),
			floorY = floorY,
		})
	end
	return pools
end

local function rect(list, p0, p1, side, half, y0, y1)
	local a = p0 + side * half
	local b = p1 - side * half
	table.insert(list, {
		min = Vector3.new(math.min(a.X, b.X), y0, math.min(a.Z, b.Z)),
		max = Vector3.new(math.max(a.X, b.X), y1, math.max(a.Z, b.Z)),
	})
end

-- The waterfall's water: spring pool, stream and curtain (or nil if there is no plateau).
function Waterworks.waterfallParts()
	local wf = Landscape.Waterfall
	if not wf then
		return nil
	end
	local f = wf.f
	local side = Vector3.new(-f.Z, 0, f.X)
	local c = Vector3.new(wf.center.X, 0, wf.center.Z)
	local parts = {}
	rect(parts, c + f * (wf.r - 84), c + f * (wf.r - 60), side, 12, wf.top - 8, wf.top) -- spring pool
	rect(parts, c + f * (wf.r - 60), c + f * wf.r, side, 4, wf.top - 4, wf.top) -- stream
	local bottom = math.floor(wf.level / 4) * 4 - 8
	rect(parts, c + f * wf.r, c + f * (wf.r + 4), side, 8, bottom, wf.top) -- falling curtain
	return parts, wf
end

function Waterworks.regions()
	local list = {}
	local top = Waterworks.BASIN_TOP
	for _, c in ipairs(Waterworks.fountainCenters()) do
		local h, b = Waterworks.BASIN_HALF, Waterworks.BOWL_HALF
		table.insert(list, { min = Vector3.new(c.X - h, top - 8, c.Z - h), max = Vector3.new(c.X + h, top, c.Z + h) })
		table.insert(list, { min = Vector3.new(c.X - b, top + 4, c.Z - b), max = Vector3.new(c.X + b, top + 8, c.Z + b) })
	end
	for _, p in ipairs(Waterworks.palacePools()) do
		table.insert(list, { min = p.min, max = p.max })
	end
	local fall = Waterworks.waterfallParts()
	if fall then
		for _, r in ipairs(fall) do
			table.insert(list, { min = Vector3.new(r.min.X, r.min.Y, r.min.Z), max = Vector3.new(r.max.X, r.max.Y, r.max.Z) })
		end
	end
	return list
end

-- Fill every water feature with terrain water (run after the terrain is written).
function Waterworks.Build()
	local terrain = workspace.Terrain
	for _, r in ipairs(Waterworks.regions()) do
		local size = r.max - r.min
		if size.X > 0 and size.Y > 0 and size.Z > 0 then
			terrain:FillBlock(CFrame.new((r.min + r.max) / 2), size, Enum.Material.Water)
		end
	end
end

return Waterworks
