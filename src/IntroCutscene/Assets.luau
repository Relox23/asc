--[[
	Assets
	Client-side loader of the intro meshes (assets/IntroAssets.fbx, DESIGN §6).

	Import IntroAssets.fbx into Studio (Home > Import 3D), keep the model named
	"IntroAssets" and put it in ReplicatedStorage (Workspace also works, read
	only: it is never moved or changed, but with streaming it may not reach the
	client). Every mesh is "<Asset>__<Style>[_n]" (e.g. "Rift__Crack_01") and
	each asset has three marker meshes "<Asset>__Origin/__Up/__Front" that give
	its pivot, up, front and true size whatever axis/unit settings the importer
	used (same scheme as src/IslandMapGenerator/AssetLibrary.luau). Without the
	import every asset has a simple procedural stand-in built from parts, so the
	cutscene always works.

	Normalised models: pivot = the asset origin, front = -Z (LookVector), up = +Y,
	sizes in studs; asset-local offsets = Convert.fromBlender(x, y, z). Every part
	is anchored, CanCollide/CanTouch/CanQuery false, has the attributes "Style"
	(e.g. "Crack"), "Piece" (e.g. "Crack_01") and "BaseTransparency".

	    Assets.place(name, parent, cf?, tint?, blend?) -> Model   (never nil; import or stand-in)
	    Assets.template(name)        -> Model?   normalised imported template (nil = not imported)
	    Assets.imported(name)        -> boolean
	    Assets.fallback(name)        -> Model?   the procedural stand-in template
	    Assets.pieces(model, style?) -> { BasePart }  sorted by name (all parts when style is nil)
	    Assets.piece(model, pieceName) -> BasePart?    e.g. "Crack_01", "RiftView", "Blade"
	    Assets.styleOf(part)         -> string?
	    Assets.tintColor(style, tint, blend?) -> Color3  style colour blended toward the tint
	    Assets.recolor(model or {parts}, tint, blend?)   every tinted style (CoreGlow, CoreRing,
	                                                     CoreShell, Wave, Arc) toward the tint
	    Assets.setResonance(model or {parts}, tint, r)   Crystal: colourless glass (r 0) -> Neon tint (r 1)
	    Assets.setOpacity(model or {parts}, opacity)     transparency = 1 - (1 - base) * opacity
	    Assets.mover(model)          -> mover; mover:MoveTo(cf) moves all parts at once (BulkMoveTo)
	    Assets.part(parent, name, style, size, cf, shape?) -> Part  (styled, no collisions)
	    Assets.preload(names?)       yields: ContentProvider:PreloadAsync on the imported meshes
	    Assets.reset()               forget the cache (a new import is picked up)
	    Assets.STYLES, Assets.NAMES
]]

local Config = require(script.Parent.Config)

local Assets = {}

Assets.IMPORT_NAME = "IntroAssets"
Assets.NAMES = { "SpaceDome", "SoulCore", "ShatteredPlanet", "Rift", "ResonanceSword", "Shockwave", "SlashArc" }
local MARKER_LEN = 10 -- studs between the Origin and Up markers in Blender

local M = Enum.Material
local rgb = Color3.fromRGB
local TAU = math.pi * 2

--[[ style -> { colour, material, transparency?, reflectance?, glow? (Neon, no shadow),
	noShadow?, tint? (recoloured by Assets.recolor), tintBlend? (default blend) } ]]
local STYLES = {
	Void = { rgb(0, 0, 0), M.SmoothPlastic, noShadow = true },
	CoreGlow = { rgb(255, 255, 255), M.Neon, glow = true, tint = true },
	CoreRing = { rgb(255, 255, 255), M.Neon, glow = true, tint = true },
	CoreShell = { rgb(255, 255, 255), M.Glass, transparency = 0.35, noShadow = true, tint = true, tintBlend = 0.25 },
	Ocean = { rgb(28, 70, 140), M.SmoothPlastic },
	Land = { rgb(70, 120, 60), M.Grass },
	LandDry = { rgb(150, 120, 80), M.Sand },
	Ice = { rgb(230, 240, 250), M.Ice },
	Cloud = { rgb(245, 245, 250), M.SmoothPlastic, transparency = 0.15, noShadow = true },
	Crust = { rgb(70, 55, 50), M.Basalt },
	Magma = { rgb(255, 110, 30), M.Neon, glow = true },
	PlanetCore = { rgb(255, 220, 140), M.Neon, glow = true },
	Debris = { rgb(85, 75, 70), M.Basalt },
	Crack = { rgb(230, 240, 255), M.Neon, glow = true },
	Shard = { rgb(200, 220, 255), M.Glass, transparency = 0.3, reflectance = 0.3, noShadow = true },
	RiftEdge = { rgb(190, 140, 255), M.Neon, glow = true },
	RiftView = { rgb(255, 255, 255), M.SmoothPlastic, noShadow = true },
	Blade = { rgb(210, 215, 225), M.Metal, reflectance = 0.2 },
	Crystal = { rgb(225, 235, 245), M.Glass, transparency = 0.25, noShadow = true },
	Guard = { rgb(40, 40, 48), M.Metal },
	Gold = { rgb(214, 172, 74), M.Foil },
	Grip = { rgb(60, 40, 30), M.Fabric },
	Wave = { rgb(255, 255, 255), M.Neon, glow = true, tint = true, tintBlend = 0 },
	Arc = { rgb(255, 255, 255), M.Neon, glow = true, tint = true },
}
Assets.STYLES = STYLES

local library -- nil = not looked yet, false = nothing imported
local fallbacks = {}

local function findSource()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local source = ReplicatedStorage:FindFirstChild(Assets.IMPORT_NAME)
	if source then
		return source
	end
	return workspace:FindFirstChild(Assets.IMPORT_NAME)
end

function Assets.reset()
	library = nil
	fallbacks = {}
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
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") then
			local asset, rest = string.match(d.Name, "^(.-)__(.+)$")
			if asset then
				local entry = assets[asset]
				if not entry then
					entry = { pieces = {}, markers = {} }
					assets[asset] = entry
				end
				if rest == "Origin" or rest == "Up" or rest == "Front" then
					entry.markers[rest] = d
				else
					local style = (string.gsub(rest, "_%d+$", ""))
					table.insert(entry.pieces, { part = d, style = style, piece = rest })
				end
			end
		end
	end
	library = { assets = assets, templates = {} }
	return library
end

-- Styling ---------------------------------------------------------------------------------------------
local function noCollide(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
end

local function applyStyle(p, styleName)
	noCollide(p)
	local s = STYLES[styleName]
	if s then
		p.Color = s[1]
		p.Material = s[2]
		p.Transparency = s.transparency or 0
		p.Reflectance = s.reflectance or 0
		if s.glow or s.noShadow then
			p.CastShadow = false
		end
	end
	p:SetAttribute("Style", styleName)
	p:SetAttribute("BaseTransparency", p.Transparency)
end
Assets.applyStyle = applyStyle

function Assets.styleOf(part)
	return part:GetAttribute("Style")
end

function Assets.tintColor(style, tint, blend)
	local s = STYLES[style]
	if not s then
		return tint
	end
	blend = blend or s.tintBlend or 1
	return s[1]:Lerp(tint, math.clamp(blend, 0, 1))
end

local function partsOf(target)
	if type(target) ~= "table" then
		if target:IsA("BasePart") then
			return { target }
		end
		local list = {}
		for _, d in ipairs(target:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end
	return target
end

function Assets.recolor(target, tint, blend)
	for _, p in ipairs(partsOf(target)) do
		local style = p:GetAttribute("Style")
		local s = style and STYLES[style]
		if s and s.tint then
			p.Color = Assets.tintColor(style, tint, blend)
		end
	end
end

local CRYSTAL = STYLES.Crystal
function Assets.setResonance(target, tint, r)
	r = math.clamp(r or 0, 0, 1)
	local color = CRYSTAL[1]:Lerp(tint, r)
	local material = r >= 0.5 and M.Neon or M.Glass
	local transparency = (CRYSTAL.transparency or 0) * (1 - r)
	for _, p in ipairs(partsOf(target)) do
		if p:GetAttribute("Style") == "Crystal" then
			p.Color = color
			if p.Material ~= material then
				p.Material = material
			end
			p.Transparency = transparency
		end
	end
end

function Assets.setOpacity(target, opacity)
	opacity = math.clamp(opacity or 1, 0, 1)
	for _, p in ipairs(partsOf(target)) do
		local base = p:GetAttribute("BaseTransparency") or 0
		p.Transparency = 1 - (1 - base) * opacity
	end
end

function Assets.pieces(model, style)
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (style == nil or d:GetAttribute("Style") == style) then
			table.insert(list, d)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

function Assets.piece(model, pieceName)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Piece") == pieceName then
			return d
		end
	end
	return nil
end

-- The face of a part whose normal is closest to a world direction.
local function faceToward(part, dir)
	local localDir = part.CFrame:VectorToObjectSpace(dir)
	local best, bestDot = Enum.NormalId.Top, -math.huge
	for _, id in ipairs(Enum.NormalId:GetEnumItems()) do
		local d = Vector3.FromNormalId(id):Dot(localDir)
		if d > bestDot then
			best, bestDot = id, d
		end
	end
	return best
end

-- RiftView: keep the imported texture; otherwise Config.RIFT_VIEW_IMAGE; otherwise a forest swirl.
local function fixRiftView(p, model)
	local hasTexture = p:FindFirstChildOfClass("SurfaceAppearance") ~= nil
	if p:IsA("MeshPart") and p.TextureID ~= "" then
		hasTexture = true
	end
	if hasTexture then
		return
	end
	local image = Config.RIFT_VIEW_IMAGE
	if image and image ~= "" then
		local ok = p:IsA("MeshPart") and pcall(function()
			p.TextureID = image
		end)
		if not ok then
			local decal = Instance.new("Decal")
			decal.Texture = image
			decal.Face = faceToward(p, Vector3.yAxis)
			decal.Parent = p
		end
		return
	end
	p.Color = rgb(64, 118, 70)
	p.Material = M.Grass
	-- a few flat discs on top (asset +Y is the viewing side): a green-blue swirl seen from high above
	local r = math.max(p.Size.X, p.Size.Y, p.Size.Z) / 2
	local ringColors = { rgb(46, 92, 54), rgb(96, 150, 80), rgb(60, 112, 170) }
	for k, color in ipairs(ringColors) do
		local d = r * (1 - k * 0.22) * 2
		local off = Vector3.new(math.cos(k * 2.1) * r * 0.12, 0.06 + 0.03 * k, math.sin(k * 2.1) * r * 0.12)
		local cf = CFrame.new(p.Position + off) * CFrame.Angles(0, 0, math.pi / 2)
		local ring = Assets.part(model, "Rift__RiftView_" .. (k + 1), "RiftView", Vector3.new(0.05, d, d), cf, Enum.PartType.Cylinder)
		ring.Color = color
		ring.Material = k == 3 and M.Glass or M.Grass
		ring:SetAttribute("Piece", "RiftView")
	end
end

-- Imported templates ----------------------------------------------------------------------------------
function Assets.template(name)
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
			warn("[IntroCutscene] Asset " .. name .. " is missing its marker meshes; using the stand-in")
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
		if p then
			local keepLook = piece.style == "RiftView"
			for _, child in ipairs(p:GetChildren()) do
				if not (keepLook and child:IsA("SurfaceAppearance")) then
					child:Destroy()
				end
			end
			local rel = toLocal * piece.part.CFrame
			p.Size = piece.part.Size * scale
			p.CFrame = CFrame.new(rel.Position * scale) * rel.Rotation
			applyStyle(p, piece.style)
			p:SetAttribute("Piece", piece.piece)
			p.Parent = model
			if keepLook then
				fixRiftView(p, model)
			end
		end
	end
	model.WorldPivot = CFrame.new()
	model:SetAttribute("Source", "import")
	lib.templates[name] = model
	return model
end

function Assets.imported(name)
	return Assets.template(name) ~= nil
end

-- Yields. Loads the imported meshes so they don't pop in (call from task.spawn).
function Assets.preload(names)
	local list = {}
	for _, name in ipairs(names or Assets.NAMES) do
		local t = Assets.template(name)
		if t then
			for _, p in ipairs(t:GetDescendants()) do
				if p:IsA("MeshPart") then
					table.insert(list, p)
				end
			end
		end
	end
	if #list > 0 then
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end
end

-- Procedural stand-ins ----------------------------------------------------------------------------------
function Assets.part(parent, name, style, size, cf, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	applyStyle(p, style)
	local piece = string.match(name, "__(.+)$")
	p:SetAttribute("Piece", piece or name)
	p.Parent = parent
	return p
end
local part = Assets.part

-- ring of n box segments, radius r, in the plane whose normal is the frame's +Y
local function ring(model, prefix, style, frame, r, n, thickness, width, numbered)
	local seg = TAU * r / n * 1.08
	for k = 1, n do
		local a = (k - 0.5) / n * TAU
		local cf = frame * CFrame.Angles(0, -a, 0) * CFrame.new(r, 0, 0)
		local name = numbered and string.format("%s_%02d", prefix, k) or prefix
		part(model, name, style, Vector3.new(width, thickness, seg), cf)
	end
end

local BUILDERS = {}

BUILDERS.SpaceDome = function(m)
	-- a black box of six slabs around the camera (parts can't be seen from inside a sphere)
	local R, S = 990, 2000
	local faces = {
		CFrame.new(R, 0, 0),
		CFrame.new(-R, 0, 0),
		CFrame.new(0, R, 0) * CFrame.Angles(0, 0, math.pi / 2),
		CFrame.new(0, -R, 0) * CFrame.Angles(0, 0, math.pi / 2),
		CFrame.new(0, 0, R) * CFrame.Angles(0, math.pi / 2, 0),
		CFrame.new(0, 0, -R) * CFrame.Angles(0, math.pi / 2, 0),
	}
	for k, cf in ipairs(faces) do
		part(m, "SpaceDome__Void_" .. k, "Void", Vector3.new(4, S, S), cf)
	end
end

BUILDERS.SoulCore = function(m)
	part(m, "SoulCore__CoreGlow", "CoreGlow", Vector3.new(1.6, 1.6, 1.6), CFrame.new(), Enum.PartType.Ball)
	part(m, "SoulCore__CoreShell", "CoreShell", Vector3.new(2.6, 2.6, 2.6), CFrame.new(), Enum.PartType.Ball)
	ring(m, "SoulCore__CoreRing", "CoreRing", CFrame.Angles(math.rad(70), 0, 0), 1.9, 18, 0.08, 0.08)
	ring(m, "SoulCore__CoreRing", "CoreRing", CFrame.Angles(0, 0, math.rad(-65)), 1.9, 18, 0.08, 0.08)
end

BUILDERS.ShatteredPlanet = function(m)
	local rng = Random.new(31)
	part(m, "ShatteredPlanet__Ocean", "Ocean", Vector3.new(640, 640, 640), CFrame.new(), Enum.PartType.Ball)
	for k = 1, 9 do
		local dir = rng:NextUnitVector()
		if dir.Z < -0.3 then
			dir = Vector3.new(dir.X, dir.Y, -dir.Z)
		end
		local d = rng:NextNumber(140, 230)
		local style = k % 3 == 0 and "LandDry" or "Land"
		part(m, "ShatteredPlanet__" .. style .. "_" .. k, style, Vector3.new(d, d, d), CFrame.new(dir * (320 - d * 0.47)), Enum.PartType.Ball)
	end
	part(m, "ShatteredPlanet__Ice_1", "Ice", Vector3.new(200, 200, 200), CFrame.new(0, 245, 0), Enum.PartType.Ball)
	part(m, "ShatteredPlanet__Ice_2", "Ice", Vector3.new(200, 200, 200), CFrame.new(0, -245, 0), Enum.PartType.Ball)
	-- the destroyed side (front, -Z): glowing fracture and crust bulging out of it
	part(m, "ShatteredPlanet__Crust", "Crust", Vector3.new(600, 600, 600), CFrame.new(0, 0, -50), Enum.PartType.Ball)
	part(m, "ShatteredPlanet__Magma", "Magma", Vector3.new(560, 560, 560), CFrame.new(0, 0, -95), Enum.PartType.Ball)
	part(m, "ShatteredPlanet__PlanetCore", "PlanetCore", Vector3.new(180, 180, 180), CFrame.new(0, 0, -300), Enum.PartType.Ball)
	for k = 1, 36 do
		local a = math.rad(-75 + 150 * (k - 1) / 35) + rng:NextNumber(-0.05, 0.05)
		local r = rng:NextNumber(380, 520)
		local pos = Vector3.new(math.sin(a) * r, rng:NextNumber(-60, 60), -math.cos(a) * r)
		local s = rng:NextNumber(6, 34)
		local cf = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
		part(m, "ShatteredPlanet__Debris_" .. k, "Debris", Vector3.new(s, s * rng:NextNumber(0.5, 1), s * rng:NextNumber(0.6, 1.2)), cf)
	end
end

BUILDERS.Rift = function(m)
	local rng = Random.new(9)
	-- opening in the asset's XZ plane (Blender XY), facing +Y (Blender +Z)
	for k = 1, 14 do
		local r0 = (k - 1) / 14 * 11
		local len = rng:NextNumber(3, 5.5)
		local a = rng:NextNumber(0, TAU)
		local mid = r0 + len / 2
		local cf = CFrame.new(math.cos(a) * mid, 0.05, math.sin(a) * mid) * CFrame.Angles(0, -a + rng:NextNumber(-0.4, 0.4), 0)
		part(m, string.format("Rift__Crack_%02d", k), "Crack", Vector3.new(len, 0.08, 0.22), cf)
	end
	local k = 0
	for gx = 0, 3 do
		for gz = 0, 3 do
			k += 1
			local x, z = (gx - 1.5) * 6, (gz - 1.5) * 6
			local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
			local s = rng:NextNumber(4.5, 6.5)
			part(m, string.format("Rift__Shard_%02d", k), "Shard", Vector3.new(s, 0.15, s * rng:NextNumber(0.5, 0.9)), cf)
		end
	end
	ring(m, "Rift__RiftEdge", "RiftEdge", CFrame.new(), 14, 28, 0.35, 0.9)
	local view = part(m, "Rift__RiftView", "RiftView", Vector3.new(0.1, 27, 27), CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	fixRiftView(view, m)
end

BUILDERS.ResonanceSword = function(m)
	-- grip centre at the origin, blade along +Y, edges facing +-X
	part(m, "ResonanceSword__Blade", "Blade", Vector3.new(0.5, 3.9, 0.12), CFrame.new(0, 2.55, 0))
	part(m, "ResonanceSword__Blade_2", "Blade", Vector3.new(0.3, 0.3, 0.12), CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.pi / 4))
	part(m, "ResonanceSword__Crystal", "Crystal", Vector3.new(0.14, 3.0, 0.16), CFrame.new(0, 2.35, 0))
	part(m, "ResonanceSword__Crystal_2", "Crystal", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 4))
	part(m, "ResonanceSword__Crystal_3", "Crystal", Vector3.new(0.26, 0.26, 0.26), CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.pi / 4))
	part(m, "ResonanceSword__Guard", "Guard", Vector3.new(1.6, 0.22, 0.34), CFrame.new(0, 0.5, 0))
	part(m, "ResonanceSword__Gold", "Gold", Vector3.new(1.7, 0.07, 0.38), CFrame.new(0, 0.63, 0))
	part(m, "ResonanceSword__Grip", "Grip", Vector3.new(0.9, 0.24, 0.24), CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	part(m, "ResonanceSword__Gold_2", "Gold", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0, -0.55, 0), Enum.PartType.Ball)
end

BUILDERS.Shockwave = function(m)
	ring(m, "Shockwave__Wave", "Wave", CFrame.new(), 1, 32, 0.04, 0.12)
end

BUILDERS.SlashArc = function(m)
	local n = 16
	for k = 1, n do
		local u = (k - 0.5) / n
		local a = math.rad(-100 + 200 * u)
		local w = 0.15 + 0.85 * math.sin(u * math.pi)
		local cf = CFrame.Angles(0, -a, 0) * CFrame.new(5, 0, 0)
		part(m, "SlashArc__Arc", "Arc", Vector3.new(w, 0.05, TAU * 5 / 32 * 1.1), cf)
	end
end

function Assets.fallback(name)
	local cached = fallbacks[name]
	if cached then
		return cached
	end
	local build = BUILDERS[name]
	if not build then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = name
	build(m)
	m.WorldPivot = CFrame.new()
	m:SetAttribute("Source", "fallback")
	fallbacks[name] = m
	return m
end

-- Placing -----------------------------------------------------------------------------------------------
function Assets.place(name, parent, cf, tint, blend)
	local t = Assets.template(name) or Assets.fallback(name)
	local m
	if t then
		m = t:Clone()
	else
		m = Instance.new("Model")
		m.Name = name
		part(m, name .. "__Missing", "Crack", Vector3.new(1, 1, 1), CFrame.new())
		m.WorldPivot = CFrame.new()
	end
	if tint then
		Assets.recolor(m, tint, blend)
	end
	m:PivotTo(cf or CFrame.new())
	m.Parent = parent
	return m
end

local bulkMoveWorks = true
local function bulkMove(parts, cframes)
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Moves every part of a model at once, keeping their offsets from the model's pivot.
function Assets.mover(model)
	local parts = Assets.pieces(model)
	local pivot = model:GetPivot()
	local offsets, cframes = {}, {}
	for i, p in ipairs(parts) do
		offsets[i] = pivot:ToObjectSpace(p.CFrame)
		cframes[i] = p.CFrame
	end
	local mover = { model = model, parts = parts }
	function mover:MoveTo(cf)
		for i = 1, #parts do
			cframes[i] = cf * offsets[i]
		end
		local ok = bulkMoveWorks and pcall(bulkMove, parts, cframes)
		if not ok then
			bulkMoveWorks = false -- (only when the engine refuses; then part by part from now on)
			for i = 1, #parts do
				parts[i].CFrame = cframes[i]
			end
		end
		model.WorldPivot = cf
	end
	return mover
end

return Assets
