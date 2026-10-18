-- Tests the detailed-mesh path against a fake IslandAssets import (see library_fixture.py).
-- Every asset is checked under several importer orientations and unit scales: each
-- mesh piece must land exactly where the Blender script modelled it.
local AssetLibrary = mockRequire(GENERATOR.AssetLibrary)

local EXPORT_SCALE = 0.1 -- tools/blender/kit.py
local failures = 0

-- OBJ coordinates are Blender's (x, y, z) exported Y-up at 1/10 scale: (x, z, -y) * 0.1
local function blenderOf(v)
	return Vector3.new(v.X, -v.Z, v.Y) / EXPORT_SCALE
end

local byAsset = {}
for _, f in ipairs(LIBRARY_FIXTURE) do
	local asset, rest = string.match(f.name, "^(.-)__(.+)$")
	byAsset[asset] = byAsset[asset] or { pieces = {} }
	if rest == "Origin" then
		byAsset[asset].origin = blenderOf(f.center)
	elseif rest ~= "Up" and rest ~= "Front" then
		table.insert(byAsset[asset].pieces, f)
	end
end
local names = {}
for name in pairs(byAsset) do
	table.insert(names, name)
end
table.sort(names)

local function near(a, b, tol)
	return (a - b).Magnitude <= tol
end

local function extents(cf, size)
	local r = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local e = Vector3.zero
	for i, axis in ipairs(r) do
		local s = (i == 1 and size.X) or (i == 2 and size.Y) or size.Z
		e += Vector3.new(math.abs(axis.X), math.abs(axis.Y), math.abs(axis.Z)) * s
	end
	return e
end

local function check(label, transform, scale)
	makeLibrary(transform, scale)
	AssetLibrary.reset()
	local bad, pieces = 0, 0
	for _, name in ipairs(names) do
		local entry = byAsset[name]
		local t = AssetLibrary.template(name)
		if not t then
			print("  missing template " .. name)
			bad += 1
			continue
		end
		local byName = {}
		for _, p in ipairs(t:GetChildren()) do
			byName[p.Name] = p
		end
		for _, f in ipairs(entry.pieces) do
			local p = byName[f.name]
			local b = blenderOf(f.center) - entry.origin
			local want = AssetLibrary.fromBlender(b.X, b.Y, b.Z)
			local bs = Vector3.new(f.size.X, f.size.Z, f.size.Y) / EXPORT_SCALE -- Blender size
			local wantExt = Vector3.new(bs.X, bs.Z, bs.Y)
			pieces += 1
			if not p then
				print("  " .. name .. ": piece missing " .. f.name)
				bad += 1
			elseif not near(p.Position, want, 0.02) or not near(extents(p.CFrame, p.Size), wantExt, 0.02) then
				print(string.format("  %s: %s at %s size %s, want %s size %s", name, f.name, tostring(p.Position), tostring(extents(p.CFrame, p.Size)), tostring(want), tostring(wantExt)))
				bad += 1
			end
		end
	end

	-- place one asset and an anchor and check them in the world
	local cf = CFrame.new(120, 40, -310) * CFrame.Angles(0, 0.7, 0)
	local folder = Instance.new("Folder")
	local m = AssetLibrary.place("Torii", folder, cf, 1.5, { Vermilion = Color3.new(0, 0, 1) })
	local fx = AssetLibrary.anchor(m, cf, Vector3.new(8, 0, 13.3), "Test")
	local wantFx = cf * (AssetLibrary.fromBlender(8, 0, 13.3) * 1.5)
	if not near(fx.Position, wantFx, 0.02) then
		print("  anchor misplaced", fx.Position, wantFx)
		bad += 1
	end
	local verm = AssetLibrary.piece(m, "Vermilion")
	if not verm or verm.Color.B ~= 1 or verm.Color.R ~= 0 then
		print("  recolour failed")
		bad += 1
	end
	-- the torii's crossbeam must be level and its pillars upright in the world
	local ext = extents(verm.CFrame, verm.Size)
	if math.abs(verm.CFrame.UpVector:Dot(cf.UpVector)) < 0.999 and math.abs(verm.CFrame.RightVector:Dot(cf.UpVector)) < 0.999 and math.abs(verm.CFrame.LookVector:Dot(cf.UpVector)) < 0.999 then
		print("  placed piece is tilted", ext)
		bad += 1
	end
	print(string.format("%-34s %3d assets, %4d pieces, %d problems", label, #names, pieces, bad))
	failures += bad
end

check("as exported", CFrame.new(), 1)
check("x10 units, offset", CFrame.new(500, 20, -40), 10)
check("Z-up import", CFrame.Angles(-math.pi / 2, 0, 0), 3.571)
check("turned around, x0.28", CFrame.Angles(0, math.pi, 0), 0.28)
check("X-up, odd yaw", CFrame.Angles(0, 1.1, math.pi / 2), 2)
print(failures == 0 and "LIBRARY OK" or ("LIBRARY FAILURES " .. failures))
