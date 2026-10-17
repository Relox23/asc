--[[
	Util
	Small helpers for building anchored parts quickly.
	Every helper takes a parent first and returns the new part.
]]

local Config = require(script.Parent.Config)

local Util = {}

local M = Enum.Material
local SMOOTH = Enum.SurfaceType.Smooth
local HALF_PI = math.pi / 2

Util.rgb = Color3.fromRGB

local lastYield = os.clock()

-- Yield every Config.YIELD_EVERY seconds so Studio doesn't freeze.
function Util.breathe()
	if os.clock() - lastYield > Config.YIELD_EVERY then
		task.wait()
		lastYield = os.clock()
	end
end

function Util.log(...)
	if Config.VERBOSE then
		print("[IslandMap]", ...)
	end
end

local function finish(p, parent, color, material, opts)
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Color = color
	p.Material = material or M.SmoothPlastic
	if opts then
		if opts.collide == false then
			p.CanCollide = false
			p.CanTouch = false
		end
		if opts.shadow == false then
			p.CastShadow = false
		end
		if opts.transparency then
			p.Transparency = opts.transparency
		end
		if opts.reflectance then
			p.Reflectance = opts.reflectance
		end
		if opts.name then
			p.Name = opts.name
		end
	end
	p.Parent = parent
	return p
end

local function clampSize(v)
	return Vector3.new(
		math.clamp(v.X, 0.05, 2048),
		math.clamp(v.Y, 0.05, 2048),
		math.clamp(v.Z, 0.05, 2048)
	)
end

-- Block centered on cf.
function Util.box(parent, cf, size, color, material, opts)
	local p = Instance.new("Part")
	p.Size = clampSize(size)
	p.CFrame = cf
	return finish(p, parent, color, material, opts)
end

-- Wedge centered on cf. The sloped face points along cf.LookVector.
function Util.wedge(parent, cf, size, color, material, opts)
	local p = Instance.new("WedgePart")
	p.Size = clampSize(size)
	p.CFrame = cf
	return finish(p, parent, color, material, opts)
end

-- Sphere centered on pos.
function Util.ball(parent, pos, diameter, color, material, opts)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	local d = math.clamp(diameter, 0.05, 2048)
	p.Size = Vector3.new(d, d, d)
	p.CFrame = CFrame.new(pos)
	return finish(p, parent, color, material, opts)
end

-- Ellipsoid (sphere mesh). Collision stays box-shaped, so it defaults to no collision.
function Util.ellipsoid(parent, cf, size, color, material, opts)
	local p = Instance.new("Part")
	p.Size = clampSize(size)
	p.CFrame = cf
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	opts = opts or {}
	if opts.collide == nil then
		opts.collide = false
	end
	return finish(p, parent, color, material, opts)
end

-- Cylinder whose axis runs along cf's X axis.
function Util.cylinder(parent, cf, length, diameter, color, material, opts)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = clampSize(Vector3.new(length, diameter, diameter))
	p.CFrame = cf
	return finish(p, parent, color, material, opts)
end

-- Upright cylinder standing on base (a Vector3 at its bottom center).
function Util.column(parent, base, height, diameter, color, material, opts)
	local cf = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, HALF_PI)
	return Util.cylinder(parent, cf, height, diameter, color, material, opts)
end

-- Flat disc (short upright cylinder) centered on pos.
function Util.disc(parent, pos, thickness, diameter, color, material, opts)
	local cf = CFrame.new(pos) * CFrame.Angles(0, 0, HALF_PI)
	return Util.cylinder(parent, cf, thickness, diameter, color, material, opts)
end

-- Cylinder from point a to point b.
function Util.rod(parent, a, b, diameter, color, material, opts)
	local len = (b - a).Magnitude
	if len < 0.05 then
		len = 0.05
	end
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, HALF_PI, 0)
	return Util.cylinder(parent, cf, len, diameter, color, material, opts)
end

-- Block from point a to point b (a beam or plank), width x thickness.
function Util.beam(parent, a, b, width, thickness, color, material, opts)
	local len = math.max((b - a).Magnitude, 0.05)
	local cf = CFrame.lookAt((a + b) / 2, b)
	return Util.box(parent, cf, Vector3.new(width, thickness, len), color, material, opts)
end

function Util.model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Util.folder(parent, name)
	local f = parent:FindFirstChild(name)
	if f then
		return f
	end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Util.pointLight(part, color, brightness, range, shadows)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = math.min(range, 60)
	l.Shadows = shadows or false
	l.Parent = part
	return l
end

function Util.surfaceLight(part, face, color, brightness, range, angle)
	local l = Instance.new("SurfaceLight")
	l.Face = face
	l.Color = color
	l.Brightness = brightness
	l.Range = math.min(range, 60)
	l.Angle = angle or 90
	l.Parent = part
	return l
end

function Util.fire(part, size, heat, color, secondary)
	local f = Instance.new("Fire")
	f.Size = size
	f.Heat = heat
	f.Color = color or Color3.fromRGB(255, 140, 50)
	f.SecondaryColor = secondary or Color3.fromRGB(255, 60, 20)
	f.Parent = part
	return f
end

-- Particle emitter with sensible defaults; props overrides anything.
function Util.particles(part, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = part
	return e
end

-- Number / colour sequence helpers
function Util.ns(...)
	local pts = { ... }
	if #pts == 1 then
		return NumberSequence.new(pts[1])
	end
	local kps = {}
	for i = 1, #pts, 2 do
		table.insert(kps, NumberSequenceKeypoint.new(pts[i], pts[i + 1]))
	end
	return NumberSequence.new(kps)
end

function Util.cs(a, b)
	return ColorSequence.new(a, b or a)
end

-- Gable roof: two wedges meeting at a ridge.
-- cf is the center of the eaves line (top of the walls); the ridge runs along cf's Z axis.
function Util.gableRoof(parent, cf, width, depth, height, color, material, opts)
	local half = width / 2
	local left = Util.wedge(
		parent,
		cf * CFrame.new(-half / 2, height / 2, 0) * CFrame.Angles(0, HALF_PI, 0),
		Vector3.new(depth, height, half),
		color,
		material,
		opts
	)
	local right = Util.wedge(
		parent,
		cf * CFrame.new(half / 2, height / 2, 0) * CFrame.Angles(0, -HALF_PI, 0),
		Vector3.new(depth, height, half),
		color,
		material,
		opts
	)
	return left, right
end

-- Hip roof built from four sloped plates (reads well from any angle).
-- cf is the center of the eaves; returns nothing.
function Util.hipRoof(parent, cf, width, depth, rise, thickness, color, material, opts)
	local hw, hd = width / 2, depth / 2
	local angX = math.atan2(rise, hw)
	local angZ = math.atan2(rise, hd)
	local slantX = math.sqrt(hw * hw + rise * rise)
	local slantZ = math.sqrt(hd * hd + rise * rise)
	-- front / back plates span the full width
	for _, sgn in ipairs({ 1, -1 }) do
		local c = cf * CFrame.new(0, rise / 2, sgn * hd / 2) * CFrame.Angles(sgn * angZ, 0, 0)
		Util.box(parent, c, Vector3.new(width, thickness, slantZ), color, material, opts)
	end
	-- side plates
	for _, sgn in ipairs({ 1, -1 }) do
		local c = cf * CFrame.new(sgn * hw / 2, rise / 2, 0) * CFrame.Angles(0, 0, -sgn * angX)
		Util.box(parent, c, Vector3.new(slantX, thickness, depth), color, material, opts)
	end
end

-- Builds a model with fn(model) at the origin and returns it as a template.
-- The template lives in an unparented folder until cloned.
function Util.template(name, fn)
	local m = Instance.new("Model")
	m.Name = name
	fn(m)
	m.WorldPivot = CFrame.new()
	return m
end

-- Places a clone of template at position with a yaw (radians) and scale.
function Util.place(template, parent, position, yaw, scale, tilt)
	local m = template:Clone()
	if scale and math.abs(scale - 1) > 0.01 then
		m:ScaleTo(scale)
	end
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0)
	if tilt then
		cf = cf * tilt
	end
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

-- Shuffled jittered grid of points inside a square region (for scattering).
function Util.scatterGrid(rng, minX, minZ, maxX, maxZ, spacing)
	local pts = {}
	local x = minX
	while x < maxX do
		local z = minZ
		while z < maxZ do
			table.insert(pts, Vector3.new(x + rng:NextNumber(0, spacing), 0, z + rng:NextNumber(0, spacing)))
			z += spacing
		end
		x += spacing
	end
	return pts
end

function Util.vary(rng, color, amount)
	local k = 1 + rng:NextNumber(-amount, amount)
	return Color3.new(math.clamp(color.R * k, 0, 1), math.clamp(color.G * k, 0, 1), math.clamp(color.B * k, 0, 1))
end

function Util.pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

-- Built-in particle textures that ship with every Roblox install.
Util.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}

return Util
