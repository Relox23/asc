-- Builds the props (no voxel terrain) and dumps parts + terrain heights per view for tools/render.py
local Gen = mockRequire(GENERATOR)
local Landscape = mockRequire(GENERATOR.Landscape)
local Layout = mockRequire(GENERATOR.IslandLayout)
Gen.Build({ "Hub", "Forest", "Snow", "Hollow", "Dunes", "Ruins", "Coast" })

local VIEWS = __VIEWS__

local function shapeOf(p)
	if p:IsA("WedgePart") then
		return "W"
	end
	if p:FindFirstChildOfClass("SpecialMesh") then
		return "E"
	end
	local shape = p.Shape
	if shape and shape.Name == "Ball" then
		return "S"
	elseif shape and shape.Name == "Cylinder" then
		return "C"
	end
	return "B"
end

local parts = {}
for _, d in ipairs(workspace.Island:GetDescendants()) do
	if d:IsA("BasePart") then
		table.insert(parts, d)
	end
end

for vi, v in ipairs(VIEWS) do
	print("VIEW " .. vi)
	local c, r = v.center, v.radius
	for _, p in ipairs(parts) do
		local pos = p.Position
		local dx, dz = pos.X - c.X, pos.Z - c.Z
		local ext = math.max(p.Size.X, p.Size.Y, p.Size.Z)
		if dx * dx + dz * dz < (r + ext) ^ 2 or v.all then
			if p.Transparency < 0.9 then
				local col = p.Color
				print(string.format(
					"P %s %.2f %.2f %.2f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f",
					shapeOf(p), p.CFrame:GetComponents()) .. string.format(" %.2f %.2f %.2f %.3f %.3f %.3f %.2f %s",
					p.Size.X, p.Size.Y, p.Size.Z, col.R, col.G, col.B, p.Transparency, p.Material.Name))
			end
		end
	end
	for _, f in ipairs(MOCK.fills) do
		local pos = f[2].Position
		if (pos.X - c.X) ^ 2 + (pos.Z - c.Z) ^ 2 < (r + 50) ^ 2 then
			print(string.format("F %s %.2f %.2f %.2f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", f[1],
				f[2]:GetComponents()) .. string.format(" %.2f %.2f %s", f[3], f[5] or 0, f[4]))
		end
	end
	local step = v.step
	local n = math.floor(2 * r / step)
	print(string.format("T %.2f %.2f %.2f %d", c.X - r, c.Z - r, step, n))
	for j = 0, n - 1 do
		local row = table.create(n)
		local z = c.Z - r + (j + 0.5) * step
		for i = 0, n - 1 do
			local x = c.X - r + (i + 0.5) * step
			local h, surf, _, _, _, water = Landscape.sample(x, z)
			row[i + 1] = string.format("%.1f:%s:%.0f", h, surf.Name, water)
		end
		print("R " .. table.concat(row, " "))
	end
end
