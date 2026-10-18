--[[
	AssetLibrary
	Detailed Blender meshes for the map (assets/IslandAssets.fbx).

	Import that FBX into Studio once (Home > Import 3D). The importer makes a
	Model named "IslandAssets"; leave it in Workspace or ServerStorage and the
	generator uses its meshes instead of building things from parts.

	Every mesh is named "<Asset>__<Style>" (e.g. "Palace__Marble"). Three tiny
	marker meshes per asset ("<Asset>__Origin", "__Up", "__Front") give the
	asset's ground point, up and front directions and its true size, so it
	doesn't matter which axis or unit settings the importer used.

	Coordinates from the Blender scripts map to asset-local offsets with
	AssetLibrary.fromBlender(x, y, z) (Blender is Z-up with the front at -Y).
]]

local Util = require(script.Parent.Util)

local AssetLibrary = {}

AssetLibrary.IMPORT_NAME = "IslandAssets"
local MARKER_LEN = 10 -- studs between the Origin and Up markers in Blender

local M = Enum.Material
local rgb = Color3.fromRGB

-- colour, material and flags per style
local STYLES = {
	Marble = { rgb(244, 240, 230), M.Marble },
	Stone = { rgb(232, 218, 190), M.Limestone },
	Plaster = { rgb(236, 226, 206), M.Plaster },
	Sandstone = { rgb(198, 156, 108), M.Sandstone },
	Trim = { rgb(222, 160, 104), M.Sandstone },
	Gold = { rgb(214, 172, 74), M.Foil },
	Teal = { rgb(30, 116, 124), M.CeramicTiles },
	Dark = { rgb(34, 28, 28), M.SmoothPlastic },
	Door = { rgb(92, 60, 40), M.WoodPlanks },
	Wood = { rgb(132, 98, 66), M.WoodPlanks },
	WoodDark = { rgb(70, 50, 38), M.Wood },
	Fabric = { rgb(166, 46, 44), M.Fabric, soft = true },
	Fabric2 = { rgb(222, 152, 44), M.Fabric, soft = true },
	Canvas = { rgb(214, 196, 168), M.Fabric, soft = true },
	Rope = { rgb(222, 200, 150), M.Fabric, soft = true },
	Shingle = { rgb(70, 82, 104), M.RoofShingles },
	Thatch = { rgb(146, 120, 80), M.Grass },
	Tile = { rgb(62, 60, 66), M.ClayRoofTiles },
	Shoji = { rgb(252, 238, 210), M.SmoothPlastic },
	Vermilion = { rgb(178, 50, 38), M.SmoothPlastic },
	Black = { rgb(30, 28, 28), M.SmoothPlastic },
	Granite = { rgb(150, 148, 144), M.Granite },
	Snow = { rgb(242, 247, 252), M.Snow },
	Bark = { rgb(98, 74, 52), M.Wood },
	BarkPale = { rgb(226, 222, 210), M.Wood },
	Leaves = { rgb(84, 148, 62), M.LeafyGrass, soft = true },
	LeavesLight = { rgb(130, 186, 84), M.LeafyGrass, soft = true },
	LeavesDark = { rgb(34, 64, 48), M.Grass, soft = true },
	LeavesGold = { rgb(236, 206, 96), M.LeafyGrass, soft = true },
	Blossom = { rgb(244, 170, 200), M.LeafyGrass, soft = true },
	Moss = { rgb(82, 120, 56), M.Grass },
	Frond = { rgb(72, 134, 54), M.Grass, soft = true },
	Coconut = { rgb(92, 66, 38), M.Wood, soft = true },
	Flower2 = { rgb(250, 220, 90), M.SmoothPlastic, soft = true },
	Fruit = { rgb(232, 120, 40), M.SmoothPlastic, soft = true },
	Fruit2 = { rgb(200, 40, 50), M.SmoothPlastic, soft = true },
	Clay = { rgb(176, 96, 60), M.Slate },
	Quartz = { rgb(236, 240, 246), M.Glass, transparency = 0.05, reflectance = 0.15 },
	Bone = { rgb(232, 226, 208), M.Marble },
	Concrete = { rgb(98, 96, 94), M.Concrete },
	Glass = { rgb(30, 38, 46), M.Glass, reflectance = 0.15 },
	GlassClear = { rgb(210, 235, 250), M.Glass, transparency = 0.45, reflectance = 0.2 },
	Rebar = { rgb(96, 58, 40), M.CorrodedMetal, soft = true },
	Paint = { rgb(110, 58, 40), M.CorrodedMetal },
	Rubber = { rgb(24, 22, 22), M.Rubber },
	Metal = { rgb(60, 58, 56), M.Metal },
	Iron = { rgb(50, 50, 54), M.Metal },
	Bronze = { rgb(74, 64, 50), M.Metal },
	White = { rgb(240, 238, 232), M.Plaster },
	Red = { rgb(178, 44, 40), M.Plaster },
	Hull = { rgb(92, 66, 46), M.WoodPlanks },
	Bastion = { rgb(236, 236, 240), M.Concrete },
	BastionTrim = { rgb(210, 212, 222), M.Concrete },
	Glow = { rgb(255, 214, 150), M.Neon, glow = true },
	GlowBlue = { rgb(150, 210, 255), M.Neon, glow = true },
	GlowGreen = { rgb(170, 255, 220), M.Neon, glow = true },
	Lantern = { rgb(232, 80, 48), M.Neon, glow = true },
}
AssetLibrary.STYLES = STYLES

local library -- nil = not looked yet, false = no library imported

local function findSource()
	local ServerStorage = game:GetService("ServerStorage")
	local source = ServerStorage:FindFirstChild(AssetLibrary.IMPORT_NAME)
	if not source then
		local inWorkspace = workspace:FindFirstChild(AssetLibrary.IMPORT_NAME)
		if inWorkspace then
			-- keep the imported original out of the game world
			inWorkspace.Parent = ServerStorage
			source = inWorkspace
		end
	end
	return source
end

-- Forget what was loaded (call before each build so a fresh import is picked up).
function AssetLibrary.reset()
	library = nil
end

local function load()
	if library ~= nil then
		return library or nil
	end
	local source = findSource()
	if not source then
		library = false
		return nil
	end
	local assets = {}
	local count = 0
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") then
			local asset, rest = string.match(d.Name, "^(.-)__(.+)$")
			if asset then
				local entry = assets[asset]
				if not entry then
					entry = { pieces = {}, markers = {} }
					assets[asset] = entry
					count += 1
				end
				if rest == "Origin" or rest == "Up" or rest == "Front" then
					entry.markers[rest] = d
				else
					local style = (string.gsub(rest, "_%d+$", ""))
					table.insert(entry.pieces, { part = d, style = style })
				end
			end
		end
	end
	library = { assets = assets, templates = {}, tinted = {} }
	Util.log(string.format("Using %d detailed models from the imported %s model", count, AssetLibrary.IMPORT_NAME))
	return library
end

function AssetLibrary.available()
	return load() ~= nil
end

-- Asset-local offset of a point given in the Blender scripts' coordinates.
function AssetLibrary.fromBlender(x, y, z)
	return Vector3.new(-x, z, y)
end

local function applyStyle(p, styleName)
	p.Anchored = true
	local s = STYLES[styleName]
	if s then
		p.Color = s[1]
		p.Material = s[2]
		p.Transparency = s.transparency or 0
		p.Reflectance = s.reflectance or 0
		if s.soft or s.glow then
			p.CanCollide = false
			p.CanTouch = false
		end
		if s.glow then
			p.CastShadow = false
		end
	end
	pcall(function()
		if s and (s.soft or s.glow) then
			p.CollisionFidelity = Enum.CollisionFidelity.Box
		elseif p.Size.Magnitude > 80 then
			p.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
		end
	end)
	p:SetAttribute("Style", styleName)
end

-- The normalised template for an asset (pivot at its ground point, front = -Z), or nil.
function AssetLibrary.template(name)
	local lib = load()
	if not lib then
		return nil
	end
	local cached = lib.templates[name]
	if cached ~= nil then
		return cached or nil
	end
	local entry = lib.assets[name]
	local mk = entry and entry.markers
	if not entry or not (mk.Origin and mk.Up and mk.Front) or #entry.pieces == 0 then
		if entry then
			warn("[IslandMap] Asset " .. name .. " is missing its marker meshes; using the parts version")
		end
		lib.templates[name] = false
		return nil
	end
	local origin = mk.Origin.Position
	local upVector = mk.Up.Position - origin
	local scale = MARKER_LEN / upVector.Magnitude
	local up = upVector.Unit
	local front = mk.Front.Position - origin
	front = (front - up * front:Dot(up)).Unit
	local back = -front
	local frame = CFrame.fromMatrix(origin, up:Cross(back), up, back)
	local toLocal = frame:Inverse()

	local model = Instance.new("Model")
	model.Name = name
	for _, piece in ipairs(entry.pieces) do
		local p = piece.part:Clone()
		for _, child in ipairs(p:GetChildren()) do
			child:Destroy() -- drop imported SurfaceAppearances, welds, etc.
		end
		local rel = toLocal * piece.part.CFrame
		p.Size = piece.part.Size * scale
		p.CFrame = CFrame.new(rel.Position * scale) * rel.Rotation
		applyStyle(p, piece.style)
		p.Parent = model
	end
	model.WorldPivot = CFrame.new()
	lib.templates[name] = model
	return model
end

function AssetLibrary.has(name)
	return AssetLibrary.template(name) ~= nil
end

local function recolor(model, colors)
	if not colors then
		return
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local c = colors[p:GetAttribute("Style")]
			if c then
				p.Color = c
			end
		end
	end
end

-- Template copy with some styles recoloured (cached), for tree and palm variety.
function AssetLibrary.tinted(name, colors, key)
	local lib = load()
	local base = AssetLibrary.template(name)
	if not base then
		return nil
	end
	local id = name .. "|" .. key
	local t = lib.tinted[id]
	if not t then
		t = base:Clone()
		recolor(t, colors)
		t.WorldPivot = CFrame.new()
		lib.tinted[id] = t
	end
	return t
end

-- Templates for every listed asset that exists, optionally in several tints.
-- tints: list of {Style = Color3} tables (or nil). Returns nil when none exist.
function AssetLibrary.templates(names, tints)
	if not AssetLibrary.available() then
		return nil
	end
	local list = {}
	for _, name in ipairs(names) do
		if AssetLibrary.has(name) then
			if tints then
				for i, colors in ipairs(tints) do
					table.insert(list, AssetLibrary.tinted(name, colors, tostring(i)))
				end
			else
				table.insert(list, AssetLibrary.template(name))
			end
		end
	end
	return #list > 0 and list or nil
end

-- Clone an asset into the world. cf is where its ground point goes (front = cf.LookVector).
function AssetLibrary.place(name, parent, cf, scale, colors)
	local t = AssetLibrary.template(name)
	if not t then
		return nil
	end
	local m = t:Clone()
	if scale and math.abs(scale - 1) > 1e-3 then
		m:ScaleTo(scale)
	end
	m:PivotTo(cf)
	recolor(m, colors)
	m.Parent = parent
	return m
end

-- First piece of a placed asset with the given style (to hang lights or particles on).
function AssetLibrary.piece(model, style)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Style") == style then
			return p
		end
	end
	return nil
end

-- Invisible anchor part at an asset-local Blender position (for lights and particles).
function AssetLibrary.anchor(model, cf, blenderPos, name)
	local scale = model:GetScale()
	local p = Instance.new("Part")
	p.Name = name or "FX"
	p.Size = Vector3.new(1, 1, 1)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.CFrame = cf * CFrame.new(AssetLibrary.fromBlender(blenderPos.X, blenderPos.Y, blenderPos.Z) * scale)
	p.Parent = model
	return p
end

return AssetLibrary
