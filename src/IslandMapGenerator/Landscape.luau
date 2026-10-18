--[[
	Landscape
	The shape of the island. heightAt(x, z) gives the ground height anywhere;
	sample(x, z) also decides the terrain materials. Every builder asks this
	module where the ground is, so props always sit on the terrain.
]]

local Layout = require(script.Parent.IslandLayout)

local Landscape = {}

local noise = math.noise
local abs, sqrt, exp, floor, min, max = math.abs, math.sqrt, math.exp, math.floor, math.min, math.max
local cos, sin, atan2, pi = math.cos, math.sin, math.atan2, math.pi
local clamp = math.clamp

local R = Layout.ISLAND_RADIUS
local HUB_R, HUB_H = Layout.HUB_RADIUS, Layout.HUB_HEIGHT
local APRON = Layout.HUB_APRON
local RAMP = Layout.RAMP_LENGTH
local ROAD = Layout.ROAD_WIDTH
local BEACH = Layout.BEACH_WIDTH
local BLEND = Layout.ZONE_BLEND
local HALF = Layout.HALF_SECTOR
local ORDER = Layout.ZONE_ORDER
local NZ = #ORDER
local wrap = Layout.wrapAngle
local L = Layout.Landmarks

local ZA = {}
local ZI = {}
for i, id in ipairs(ORDER) do
	ZA[i] = Layout.ZoneAngle[id]
	ZI[id] = i
end

Landscape.SEABED = -72
Landscape.BOTTOM = -96

local S0 = (Layout.SEED % 9973) * 0.0131 + 0.377

local function n2(x, z, f, o)
	return noise(x * f + o * 13.37, z * f - o * 7.91, S0 + o * 0.173)
end

-- Fractal noise, roughly in -1..1.
local function fbm(x, z, f, octaves, o)
	local sum, amp, norm = 0, 1, 0
	for i = 1, octaves do
		sum += n2(x, z, f, o + i * 3) * amp
		norm += amp
		amp *= 0.5
		f *= 2.03
	end
	return sum / norm * 2.2
end

local function smooth(e0, e1, x)
	local t = clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Asymmetric dune cross-section: long windward slope, short steep lee face.
local function duneProfile(p)
	if p < 0.74 then
		local t = p / 0.74
		return t * t * (3 - 2 * t)
	end
	local t = (p - 0.74) / 0.26
	return 1 - t * t * (3 - 2 * t)
end

Landscape.noise2 = n2
Landscape.fbm = fbm
Landscape.smooth = smooth

-- Region height functions -----------------------------------------------------
local VX, VZ = L.SnowVillage.X, L.SnowVillage.Z
local TX, TZ = L.Temple.X, L.Temple.Z

local function forestH(x, z)
	local h = 36 + 20 * fbm(x, z, 1 / 1100, 4, 1) + 6 * fbm(x, z, 1 / 260, 3, 2)
	local ridge = 1 - abs(n2(x, z, 1 / 1700, 3)) * 2.4
	h += 60 * max(0, ridge - 0.45)
	return h
end

local function snowH(x, z)
	local h = 52 + 24 * fbm(x, z, 1 / 1000, 4, 11)
	local ridged, amp, f = 0, 1, 1 / 950
	for i = 1, 4 do
		local v = max(0, 1 - abs(n2(x, z, f, 12 + i)) * 2.2)
		ridged += v * v * amp
		amp *= 0.5
		f *= 2.07
	end
	local mask = smooth(-0.15, 0.25, n2(x, z, 1 / 2600, 19))
	local dv = sqrt((x - VX) ^ 2 + (z - VZ) ^ 2)
	mask *= smooth(520, 1350, dv)
	h += ridged * 140 * mask
	h += 270 * exp(-((x - TX) ^ 2 + (z - TZ) ^ 2) / (640 * 640))
	return h
end

local function hollowH(x, z)
	local h = 26 + 14 * fbm(x, z, 1 / 900, 3, 21)
	local u = x * 0.8 + z * 0.6 + 170 * n2(x, z, 1 / 1300, 22)
	h += 10 * duneProfile((u / 430) % 1)
	return h
end

local function ruinsH(x, z)
	local h = 22 + 18 * fbm(x, z, 1 / 800, 4, 41)
	local u = -x * 0.6 + z * 0.8 + 150 * n2(x, z, 1 / 1000, 42)
	h += 16 * duneProfile((u / 260) % 1) * (0.6 + n2(x, z, 1 / 1500, 43))
	return h
end

local function dunesH(x, z)
	local h = 30 + 26 * fbm(x, z, 1 / 1800, 3, 31)
	local u = x * 0.34 + z * 0.94 + 280 * n2(x, z, 1 / 1500, 32)
	local amp = 52 + 40 * n2(x, z, 1 / 2200, 33)
	h += amp * duneProfile((u / 400) % 1)
	local u2 = x * 0.9 - z * 0.43 + 120 * n2(x, z, 1 / 900, 34)
	h += 12 * duneProfile((u2 / 170) % 1)
	return h
end

local ZONE_HEIGHT = {}
ZONE_HEIGHT[ZI.Forest] = forestH
ZONE_HEIGHT[ZI.Snow] = snowH
ZONE_HEIGHT[ZI.Hollow] = hollowH
ZONE_HEIGHT[ZI.Ruins] = ruinsH
ZONE_HEIGHT[ZI.Dunes] = dunesH

local function apronH(x, z)
	return 26 + 7 * fbm(x, z, 1 / 500, 3, 51)
end

-- Coastline -----------------------------------------------------------------
local function coastRadius(theta)
	local cx, cz = cos(theta), sin(theta)
	return R
		* (1 + 0.09 * noise(cx * 1.7 + 5.3, cz * 1.7 - 2.1, S0) + 0.04 * noise(cx * 5.1 - 1.7, cz * 5.1 + 3.3, S0 + 1))
end
Landscape.coastRadius = coastRadius
Landscape.MAX_COAST = R * 1.12

-- Features (filled in by init) -------------------------------------------------
local craters = {}
local lakes = {}
local plateaus = {}
local pads = {}
local corridor
local rampBottom = {}

-- Steps 1-3: regions, foothills, craters, hills, lakes.
local weights = table.create(NZ, 0)

local function regionHeight(x, z, d, theta)
	local b = clamp(BLEND / max(d, 300), 0.02, HALF * 0.9)
	local sum = 0
	for i = 1, NZ do
		local w = 1 - smooth(HALF - b, HALF + b, abs(wrap(theta - ZA[i])))
		weights[i] = w
		sum += w
	end
	local h = 0
	for i = 1, NZ do
		local w = weights[i] / sum
		if w > 0.001 then
			h += ZONE_HEIGHT[i](x, z) * w
		end
	end
	-- Foothills around the capital mesa
	h = lerp(apronH(x, z), h, smooth(HUB_R + 40, HUB_R + APRON, d))
	return h
end

local function featureHeight(x, z, h, withLakes)
	for _, c in ipairs(craters) do
		local dx, dz = x - c.x, z - c.z
		local dd = dx * dx + dz * dz
		local rr = c.r * 1.7
		if dd < rr * rr then
			local dc = sqrt(dd)
			if dc < c.r then
				h -= c.r * 0.2 * (1 - (dc / c.r) ^ 2)
			end
			h += c.r * 0.07 * exp(-((dc - c.r) / (0.22 * c.r)) ^ 2)
		end
	end
	if withLakes then
		for _, lk in ipairs(lakes) do
			local dx, dz = x - lk.x, z - lk.z
			local dd = dx * dx + dz * dz
			if dd < (lk.r * 1.3) ^ 2 then
				local dl = sqrt(dd) * (1 + 0.12 * n2(x, z, 1 / 120, 70))
				local bowl = 1 - smooth(lk.r * 0.45, lk.r, dl)
				h = lerp(h, lk.level - lk.depth, bowl)
			end
		end
		-- flat-topped plateaus: a sheer straight cliff on one side, gentle slopes elsewhere
		for _, pl in ipairs(plateaus) do
			local dx, dz = x - pl.x, z - pl.z
			if abs(dx) < pl.reach and abs(dz) < pl.reach then
				local u = dx * pl.fx + dz * pl.fz
				local v = abs(-dx * pl.fz + dz * pl.fx) + 14 * n2(x, z, 1 / 90, 72)
				local back = -u + 14 * n2(x, z, 1 / 90, 73)
				local m = (1 - smooth(pl.r, pl.r + pl.steep, u))
					* (1 - smooth(pl.r, pl.r + pl.gentle, back))
					* (1 - smooth(pl.r * 0.8, pl.r * 0.8 + pl.gentle * 0.7, v))
				if m > 0 then
					h = lerp(h, pl.top, m)
				end
			end
		end
	end
	return h
end

local function applyPads(x, z, h)
	for _, p in ipairs(pads) do
		local dd = (x - p.x) ^ 2 + (z - p.z) ^ 2
		local outer = p.r + p.fall
		if dd < outer * outer then
			local m = 1 - smooth(p.r, outer, sqrt(dd))
			h = lerp(h, p.h, m)
		end
	end
	return h
end

local function applyCorridor(x, z, h)
	local c = corridor
	if not c then
		return h
	end
	local px, pz = x - c.ax, z - c.az
	local t = clamp((px * c.dx + pz * c.dz) / c.len2, 0, 1)
	local qx, qz = c.ax + c.dx * t - x, c.az + c.dz * t - z
	local lat2 = qx * qx + qz * qz
	if lat2 < c.outer * c.outer then
		local m = 1 - smooth(c.inner, c.outer, sqrt(lat2))
		h = lerp(h, lerp(c.ha, c.hb, t), m)
	end
	return h
end

-- Values exposed by the last call to sample()/heightAt()
local lastKind, lastZone, lastS, lastRoad, lastPath, lastWater, lastFrozen, lastLakebed
local KIND_OCEAN, KIND_BEACH, KIND_LAND, KIND_HUB, KIND_APRON = 0, 1, 2, 3, 4

local function pathAt(x, z, zone)
	for _, p in ipairs(Layout.Paths) do
		if p.zone == zone then
			local pts = p.points
			local half = p.width * 0.5 * (1 + 0.35 * n2(x, z, 1 / 60, 95))
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local abx, abz = b.X - a.X, b.Z - a.Z
				local len2 = abx * abx + abz * abz
				local t = clamp(((x - a.X) * abx + (z - a.Z) * abz) / len2, 0, 1)
				-- gentle meander
				local wob = 26 * n2(a.X + abx * t, a.Z + abz * t, 1 / 260, 96)
				local nx, nz = -abz / sqrt(len2), abx / sqrt(len2)
				local qx = a.X + abx * t + nx * wob - x
				local qz = a.Z + abz * t + nz * wob - z
				if qx * qx + qz * qz < half * half then
					return p.material
				end
			end
		end
	end
	return nil
end

local function core(x, z)
	local d = sqrt(x * x + z * z)
	local theta = atan2(z, x)
	local s = coastRadius(theta) - d
	lastS = s
	lastRoad = false
	lastPath = nil
	lastWater = Layout.SEA_LEVEL
	lastFrozen = false
	lastLakebed = false

	if s < 0 then
		lastKind = KIND_OCEAN
		lastZone = "Coast"
		return lerp(-3, Landscape.SEABED, smooth(0, 700, -s)) + 2 * n2(x, z, 1 / 90, 97)
	end

	local wtheta = Layout.warpedAngle(x, z)
	local mtheta = wtheta + 0.035 * n2(x, z, 1 / 110, 61)
	local best, bestDist = 1, math.huge
	for i = 1, NZ do
		local ad = abs(wrap(mtheta - ZA[i]))
		if ad < bestDist then
			best, bestDist = i, ad
		end
	end
	lastZone = ORDER[best]

	if s < BEACH then
		lastKind = KIND_BEACH
		return lerp(-3, 7, s / BEACH) + 0.8 * n2(x, z, 1 / 40, 90)
	end

	local h = regionHeight(x, z, d, wtheta)
	h = featureHeight(x, z, h, true)
	h = applyPads(x, z, h)
	h = applyCorridor(x, z, h)

	-- Capital mesa with a ragged cliff edge
	local edge = d + 26 * n2(x, z, 1 / 85, 81) + 10 * n2(x, z, 1 / 26, 82)
	local hub = 1 - smooth(HUB_R - 34, HUB_R + 34, edge)
	if hub > 0 then
		h = lerp(h, HUB_H, hub)
	end

	-- Grand causeways from the city gates down to every region
	if d < HUB_R + RAMP + 200 then
		for i = 1, NZ do
			local dth = wrap(theta - ZA[i])
			if abs(dth) < 0.9 then
				local along = d * cos(dth)
				local lat = abs(d * sin(dth))
				if lat < ROAD * 0.5 + 50 then
					local t = clamp((along - (HUB_R - 60)) / (RAMP + 60), 0, 1)
					local rh = lerp(HUB_H, rampBottom[i], t)
					local m = (1 - smooth(ROAD * 0.5, ROAD * 0.5 + 48, lat))
						* (1 - smooth(HUB_R + RAMP, HUB_R + RAMP + 90, along))
					h = lerp(h, rh, m)
					if lat < ROAD * 0.5 - 1 and along > HUB_R - 100 and along < HUB_R + RAMP + 20 then
						lastRoad = true
					end
				end
			end
		end
	end

	-- Leave the beach gently
	local t = smooth(BEACH, BEACH + 520, s)
	h = lerp(7 + (s - BEACH) * 0.02, h, t)

	if hub > 0.5 then
		lastKind = KIND_HUB
		lastZone = "Hub"
	elseif d < HUB_R + APRON * 0.55 then
		lastKind = KIND_APRON
	else
		lastKind = KIND_LAND
		if t < 0.25 + 0.15 * n2(x, z, 1 / 70, 98) then
			lastKind = KIND_BEACH
		end
	end

	for _, lk in ipairs(lakes) do
		local dd = (x - lk.x) ^ 2 + (z - lk.z) ^ 2
		if dd < (lk.r * 1.25) ^ 2 then
			lastWater = max(lastWater, lk.level)
			-- frozen ponds keep open water in the middle; ice only along the shore
			lastFrozen = lk.frozen and sqrt(dd) > lk.r * (0.6 + 0.08 * n2(x, z, 1 / 40, 71))
			lastLakebed = h < lk.level + 1
		end
	end

	if lastKind == KIND_LAND or lastKind == KIND_APRON then
		lastPath = pathAt(x, z, lastZone)
	end
	return h
end

-- Public API --------------------------------------------------------------------
local initialized = false

function Landscape.init()
	if initialized then
		return
	end
	initialized = true

	local function rawHeight(p, withLakes)
		local d = math.max(p.Magnitude, 1)
		local h = regionHeight(p.X, p.Z, d, Layout.warpedAngle(p.X, p.Z))
		return featureHeight(p.X, p.Z, h, withLakes)
	end

	-- Impact craters in the ruined city
	local rng = Random.new(Layout.SEED + 5)
	for _ = 1, 8 do
		local a = rng:NextNumber(0, pi * 2)
		local rr = rng:NextNumber(450, 2000)
		table.insert(craters, {
			x = L.RuinsCenter.X + cos(a) * rr,
			z = L.RuinsCenter.Z + sin(a) * rr,
			r = rng:NextNumber(90, 230),
		})
	end

	local lake = L.ForestLake
	local function addLake(pos, r, depth, frozen)
		local level = math.huge
		for k = 0, 47 do
			local a = k / 48 * pi * 2
			local q = pos + Vector3.new(cos(a), 0, sin(a)) * r * 1.18
			level = min(level, rawHeight(q, false))
		end
		level = floor(level - 2)
		table.insert(lakes, { x = pos.X, z = pos.Z, r = r, depth = depth, level = level, frozen = frozen })
		return level
	end
	Landscape.ForestLakeLevel = addLake(lake, 330, 24, false)
	Landscape.SnowPondLevel = addLake(L.SnowPond, 120, 10, true)

	-- Rocky plateau on the far side of Mirror Lake. Its lake-facing cliff runs along a
	-- voxel grid line so the terrain-water waterfall pouring off it has straight edges.
	do
		local out = lake.Unit
		local fx, fz = 0, 0 -- direction from the plateau toward the lake (a cardinal axis)
		if abs(out.X) > abs(out.Z) then
			fx = out.X > 0 and -1 or 1
		else
			fz = out.Z > 0 and -1 or 1
		end
		local r = 124
		local cx = floor((lake.X - fx * (r + 200)) / 4 + 0.5) * 4
		local cz = floor((lake.Z - fz * (r + 200)) / 4 + 0.5) * 4
		local center = Vector3.new(cx, 0, cz)
		local top = floor((rawHeight(center, true) + 72) / 4) * 4
		table.insert(plateaus, { x = cx, z = cz, fx = fx, fz = fz, r = r, steep = 6, gentle = 150, top = top, reach = r + 200 })
		Landscape.Waterfall = {
			center = Vector3.new(cx, top, cz),
			f = Vector3.new(fx, 0, fz),
			r = r,
			top = top,
			level = Landscape.ForestLakeLevel,
		}
	end

	-- Flattened building sites
	local function addPad(pos, r, fall, raise)
		local h = rawHeight(pos, true) + (raise or 0)
		table.insert(pads, { x = pos.X, z = pos.Z, r = r, fall = fall, h = h })
		return h
	end
	Landscape.VillageHeight = addPad(L.SnowVillage, 300, 260)
	Landscape.TempleHeight = addPad(L.Temple, 160, 110, 6)
	Landscape.WatchtowerHeight = addPad(L.Watchtower, 330, 320)
	Landscape.BastionHeight = addPad(L.Bastion, 780, 320)
	Landscape.WorldTreeHeight = addPad(L.WorldTree, 170, 220, 10)
	Landscape.ForestSpawnHeight = addPad(L.ForestSpawn, 130, 160)
	for _, c in ipairs(Layout.forestCottages()) do
		addPad(c, 60, 70)
	end

	-- Straight stair corridor up the temple mountain
	local a, b = L.TempleStairsFoot, L.TempleStairsTop
	local ha = applyPads(a.X, a.Z, rawHeight(a, true))
	local hb = Landscape.TempleHeight
	corridor = {
		ax = a.X,
		az = a.Z,
		dx = b.X - a.X,
		dz = b.Z - a.Z,
		len2 = (b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2,
		ha = ha,
		hb = hb,
		inner = 15,
		outer = 42,
	}
	Landscape.StairsFootHeight = ha

	-- Height at the bottom of each causeway
	for i, id in ipairs(ORDER) do
		local foot = Layout.polar(ZA[i], HUB_R + RAMP)
		local h = applyCorridor(foot.X, foot.Z, applyPads(foot.X, foot.Z, rawHeight(foot, true)))
		rampBottom[i] = h
		Landscape["RampBottom" .. id] = h
	end
end

-- Ground height at a point.
function Landscape.heightAt(x, z)
	if not initialized then
		Landscape.init()
	end
	return core(x, z)
end

-- Ground position (Vector3) under a point.
function Landscape.groundAt(x, z)
	return Vector3.new(x, Landscape.heightAt(x, z), z)
end

-- Height plus everything a prop scatterer wants to know about the spot.
function Landscape.query(x, z)
	local h = Landscape.heightAt(x, z)
	local kind = lastKind
	return {
		h = h,
		zone = lastZone,
		coastDistance = lastS,
		ocean = kind == KIND_OCEAN,
		beach = kind == KIND_BEACH,
		hub = kind == KIND_HUB,
		apron = kind == KIND_APRON,
		land = kind == KIND_LAND,
		road = lastRoad,
		path = lastPath ~= nil,
		underwater = h < lastWater,
		water = lastWater,
	}
end

-- Slope (rise over run) estimated from four neighbours.
function Landscape.slopeAt(x, z, step)
	step = step or 4
	local hx1 = Landscape.heightAt(x + step, z)
	local hx0 = Landscape.heightAt(x - step, z)
	local hz1 = Landscape.heightAt(x, z + step)
	local hz0 = Landscape.heightAt(x, z - step)
	return max(abs(hx1 - hx0), abs(hz1 - hz0)) / (2 * step)
end

-- Materials ------------------------------------------------------------------------
local M = Enum.Material
Landscape.STRATA = "Strata"

local ZONE_MATS = {
	Forest = { surf = M.Grass, alt = M.LeafyGrass, bank = M.Ground, cliff = M.Rock, sub = M.Rock, bed = M.Ground },
	Snow = { surf = M.Snow, alt = M.Snow, bank = M.Snow, cliff = M.Rock, sub = M.Rock, bed = M.Rock },
	Hollow = { surf = M.Salt, alt = M.Slate, bank = M.Salt, cliff = M.Slate, sub = M.Slate, bed = M.Slate },
	Ruins = { surf = M.Mud, alt = M.Basalt, bank = M.Mud, cliff = M.Basalt, sub = M.Basalt, bed = M.Basalt },
	Dunes = { surf = M.Sand, alt = M.Sandstone, bank = M.Sand, cliff = M.Sandstone, sub = M.Sandstone, bed = M.Sand },
}
local ALT_THRESHOLD = { Forest = 0.12, Snow = 2, Hollow = 0.34, Ruins = 0.4, Dunes = 0.38 }

--[[
	Ground height and materials at a point.
	Returns h, surface, bank (moderate slopes), cliff (steep slopes),
	sub (below the surface), water level, frozen.
]]
function Landscape.sample(x, z)
	local h = Landscape.heightAt(x, z)
	local kind = lastKind
	local water, frozen = lastWater, lastFrozen

	if kind == KIND_OCEAN then
		local surf = n2(x, z, 1 / 300, 99) > 0.3 and M.Rock or M.Sand
		return h, surf, surf, M.Rock, M.Sandstone, water, false
	elseif kind == KIND_HUB then
		local surf = lastRoad and M.Pavement or M.Sandstone
		local dd = sqrt(x * x + z * z)
		-- avenues and the ring road of the capital
		if dd < HUB_R - 70 then
			local theta = atan2(z, x)
			for i = 1, NZ do
				local dth = wrap(theta - ZA[i])
				if abs(dth) < 0.5 and abs(dd * sin(dth)) < 17 then
					surf = M.Pavement
				end
			end
			if (dd > 240 and dd < 296) or (dd > HUB_R - 132 and dd < HUB_R - 104) then
				surf = M.Pavement
			end
		end
		return h, surf, M.Sandstone, M.Sandstone, Landscape.STRATA, water, false
	elseif kind == KIND_APRON then
		if lastRoad then
			return h, M.Pavement, M.Sandstone, M.Sandstone, Landscape.STRATA, water, false
		end
		local zm = ZONE_MATS[lastZone]
		local dd = sqrt(x * x + z * z)
		local blend = smooth(HUB_R, HUB_R + APRON * 0.55, dd) + 0.25 * n2(x, z, 1 / 90, 63)
		local surf
		if blend > 0.75 then
			surf = zm.surf
		else
			surf = n2(x, z, 1 / 140, 64) > 0.05 and M.Sandstone or M.Sand
		end
		return h, lastPath and M[lastPath] or surf, M.Sandstone, M.Sandstone, Landscape.STRATA, water, false
	elseif kind == KIND_BEACH then
		local zm = ZONE_MATS[lastZone]
		local cliff = lastZone == "Snow" and M.Rock or M.Sandstone
		return h, M.Sand, M.Sand, cliff, zm.sub, water, false
	end

	local zone = lastZone
	local zm = ZONE_MATS[zone]
	local surf = zm.surf
	if lastRoad then
		return h, M.Pavement, M.Sandstone, M.Sandstone, Landscape.STRATA, water, false
	end
	if n2(x, z, 1 / 170, 101) > ALT_THRESHOLD[zone] then
		surf = zm.alt
	end
	if zone == "Snow" and h > 300 and n2(x, z, 1 / 90, 102) > 0.05 then
		surf = M.Glacier
	end
	if lastPath then
		surf = M[lastPath]
	end
	if lastLakebed then
		surf = zm.bed
	end
	return h, surf, zm.bank, zm.cliff, zm.sub, water, frozen
end

return Landscape
