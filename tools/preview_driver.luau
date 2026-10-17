-- Prints a top-down height/material map of the island for tools/preview.py
local G = GENERATOR
local Landscape = mockRequire(G.Landscape)
local Layout = mockRequire(G.IslandLayout)
Landscape.init()

local RES = tonumber(_G.PREVIEW_RES) or 400
local EXT = Layout.ISLAND_RADIUS * 1.15
local step = 2 * EXT / RES

local stats = {}
for j = 0, RES - 1 do
	local z = -EXT + (j + 0.5) * step
	local row = table.create(RES)
	for i = 0, RES - 1 do
		local x = -EXT + (i + 0.5) * step
		local h, surf, _, _, _, water = Landscape.sample(x, z)
		local zone = Layout.getZone(x, z)
		local st = stats[zone]
		if not st then
			st = { n = 0, sum = 0, min = math.huge, max = -math.huge }
			stats[zone] = st
		end
		if h > 0 then
			st.n += 1
			st.sum += h
			st.min = math.min(st.min, h)
			st.max = math.max(st.max, h)
		end
		row[i + 1] = string.format("%.1f:%s:%.0f", h, surf.Name, water)
	end
	print("ROW " .. table.concat(row, " "))
end
for zone, st in pairs(stats) do
	print(string.format("STAT %s n=%d mean=%.1f min=%.1f max=%.1f", zone, st.n, st.sum / math.max(st.n, 1), st.min, st.max))
end
print(string.format("INFO ext=%.0f lake=%s pond=%s village=%.1f temple=%.1f tower=%.1f bastion=%.1f stairsFoot=%.1f", EXT,
	tostring(Landscape.ForestLakeLevel), tostring(Landscape.SnowPondLevel), Landscape.VillageHeight, Landscape.TempleHeight,
	Landscape.WatchtowerHeight, Landscape.BastionHeight, Landscape.StairsFootHeight))
for _, id in ipairs(Layout.ZONE_ORDER) do
	print("RAMP " .. id .. " " .. tostring(Landscape["RampBottom" .. id]))
end
for name, p in pairs(Layout.Landmarks) do
	print(string.format("MARK %s %.1f %.1f", name, p.X, p.Z))
end
for _, p in ipairs(Layout.forestCottages()) do
	print(string.format("MARK cottage %.1f %.1f", p.X, p.Z))
end
