--[[
	Watchtower
	The great watchtower in the middle of the dunes, shaped after the Pleiades
	Watchtower: a flared base with a temple entrance, a long slender shaft with
	a balcony, a crown of six onion-domed pillars whose stalactite roots hang
	far below, a saucer-ringed central spire, and two colossal horn-shaped
	arches rising over it all.

	If a mesh version has been imported into Studio (a Model named
	"PleiadesWatchtower" in ServerStorage or Workspace, made from
	assets/PleiadesWatchtower.fbx), that mesh is used. Otherwise the same
	shape is built from parts. The numbers below mirror
	tools/blender/pleiades_watchtower.py, so both versions line up.
]]

local Util = require(script.Parent.Util)

local Watchtower = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local box, column, disc, wedge = Util.box, Util.column, Util.disc, Util.wedge
local NOSHADOW = { shadow = false }
local NOCOL_NOSHADOW = { collide = false, shadow = false }
local TAU = math.pi * 2
local HALF_PI = math.pi / 2

Watchtower.IMPORT_NAME = "PleiadesWatchtower"
Watchtower.HEIGHT = 1153 -- from the horn feet (22 studs below ground) to the horn tips
local FOOT_DEPTH = 22
Watchtower.CROWN_TOP = 704 -- walkable crown platform
Watchtower.BALCONY_TOP = 575

local STYLE = {
	Stone = { color = rgb(238, 234, 226), material = M.Marble },
	Trim = { color = rgb(222, 160, 104), material = M.Sandstone },
	Gold = { color = rgb(214, 172, 74), material = M.Foil },
	Dark = { color = rgb(34, 30, 30), material = M.SmoothPlastic },
	Glow = { color = rgb(170, 220, 255), material = M.Neon },
}

-- Shape ------------------------------------------------------------------------------------------
local function sample(fn, a, b, n, out)
	for i = 0, n do
		table.insert(out, fn(a + (b - a) * i / n))
	end
end

local function bodyProfile()
	local p = { { 0, -8 }, { 152, -8 }, { 152, 4 }, { 142, 4 }, { 142, 12 }, { 130, 12 }, { 130, 22 }, { 122, 22 }, { 122, 26 } }
	sample(function(t)
		return { 44 + 78 * (1 - t) ^ 2.6, 26 + 132 * t }
	end, 0.02, 1, 18, p)
	for _, q in ipairs({ { 52, 158 }, { 52, 166 }, { 44, 168 } }) do
		table.insert(p, q)
	end
	local z, r0, r1, top = 168, 42, 25, 560
	for k = 0, 4 do
		local za, zb = z + k * (top - z) / 5, z + (k + 1) * (top - z) / 5
		local ra = r0 + (r1 - r0) * ((za - z) / (top - z)) ^ 0.8
		local rb = r0 + (r1 - r0) * ((zb - z) / (top - z)) ^ 0.8
		for _, q in ipairs({ { ra, za + 0.1 }, { rb, zb - 5 }, { rb + 3, zb - 4 }, { rb + 3, zb - 1 }, { rb, zb } }) do
			table.insert(p, q)
		end
	end
	for _, q in ipairs({ { 25, 560 }, { 46, 563 }, { 48, 568 }, { 48, 572 }, { 27, 575 }, { 26, 640 } }) do
		table.insert(p, q)
	end
	sample(function(t)
		return { 26 + 50 * t ^ 2.2, 640 + 52 * t }
	end, 0.05, 1, 10, p)
	for _, q in ipairs({ { 80, 696 }, { 80, 702 }, { 70, 704 }, { 0, 704 } }) do
		table.insert(p, q)
	end
	return p
end

local SPIRE_PROFILE = {
	{ 0, 702 }, { 19, 702 }, { 19, 792 }, { 23, 794 }, { 23, 800 }, { 19, 802 },
	{ 24, 808 }, { 29, 818 }, { 31, 828 }, { 28, 840 }, { 20, 850 }, { 11, 858 }, { 6, 864 }, { 6, 868 },
	{ 40, 869 }, { 90, 871 }, { 124, 874 }, { 130, 877 }, { 124, 880 }, { 88, 883 }, { 40, 885 }, { 9, 886 },
	{ 9, 904 }, { 13, 908 }, { 13, 912 }, { 9, 914 }, { 6, 930 }, { 4, 970 }, { 2, 1010 }, { 0.8, 1040 }, { 0, 1044 },
}

local SATELLITE_PROFILE = {
	{ 0, 468 }, { 1.5, 480 }, { 3.5, 510 }, { 6, 552 }, { 8.5, 600 }, { 11, 650 }, { 13, 692 },
	{ 12, 704 }, { 12, 764 }, { 15, 766 }, { 15, 771 }, { 12, 773 }, { 17, 782 }, { 19.5, 792 },
	{ 17, 803 }, { 11, 811 }, { 6, 817 }, { 4, 822 }, { 2.4, 840 }, { 1, 862 }, { 0, 866 },
}
local SATELLITE_RADIUS = 54

-- Revolved profile approximated with stacked cylinders. cf is the axis base (Y up).
local function latheParts(m, cf, profile, style, minRadius)
	for i = 1, #profile - 1 do
		local r0, z0 = profile[i][1], profile[i][2]
		local r1, z1 = profile[i + 1][1], profile[i + 1][2]
		local dz = z1 - z0
		if dz > 0.25 then
			local r = math.max((r0 + r1) / 2, minRadius or 0.6)
			Util.cylinder(m, cf * CFrame.new(0, (z0 + z1) / 2, 0) * CFrame.Angles(0, 0, HALF_PI), dz + 0.05, r * 2, style.color, style.material)
		end
	end
end

local function bezier(p0, p1, p2, p3, t)
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

-- One horn arch in the tower's local X/Y plane (side = -1 or 1).
local function horn(m, T, side, style, inset, scale, depthScale)
	local p0 = Vector3.new(side * 285, -20, 0)
	local p1 = Vector3.new(side * 272, 440, 0)
	local p2 = Vector3.new(side * 222, 860, 0)
	local p3 = Vector3.new(side * 30, 1130, 0)
	local n = 22
	for i = 0, n - 1 do
		local ta, tb = i / n, (i + 1) / n
		local a, b = bezier(p0, p1, p2, p3, ta), bezier(p0, p1, p2, p3, tb)
		local t = (ta + tb) / 2
		local d = (b - a).Unit
		local across = Vector3.new(d.Y, -d.X, 0) * side
		local w = (92 * (1 - t) ^ 1.2 + 3) * scale + math.max(0, 1 - t * 8) * 40 * scale
		local dep = (50 * (1 - t) ^ 1.1 + 2) * depthScale
		local mid = (a + b) / 2 + across * (inset * w)
		local cf = T * CFrame.fromMatrix(mid, across, d)
		box(m, cf, Vector3.new(w, (b - a).Magnitude + 2, dep), style.color, style.material)
	end
end

local function portico(m, T)
	local stone = STYLE.Stone
	local y0 = -128 -- local Z (front is -Z)
	box(m, T * CFrame.new(0, 6, y0 - 6), Vector3.new(78, 4, 34), stone.color, stone.material)
	for k = 0, 2 do
		box(m, T * CFrame.new(0, 3 - k * 1.5, y0 - 24 - k * 3), Vector3.new(78 - k * 4, 8 - k * 3, 3), stone.color, stone.material)
	end
	for _, x in ipairs({ -30, -18, -6, 6, 18, 30 }) do
		column(m, (T * CFrame.new(x, 8, y0 - 16)).Position, 34, 5.2, stone.color, stone.material)
		box(m, T * CFrame.new(x, 43, y0 - 16), Vector3.new(7, 2, 7), stone.color, stone.material, NOSHADOW)
	end
	box(m, T * CFrame.new(0, 46, y0 - 10), Vector3.new(76, 6, 22), stone.color, stone.material)
	-- pediment: two wedges back to back
	for _, s in ipairs({ -1, 1 }) do
		wedge(m, T * CFrame.new(s * 20, 56.5, y0 - 10) * CFrame.Angles(0, s * -HALF_PI, 0), Vector3.new(24, 15, 40), stone.color, stone.material)
	end
	for _, x in ipairs({ -36, 36 }) do
		box(m, T * CFrame.new(x, 26, y0 + 4), Vector3.new(6, 44, 40), stone.color, stone.material)
	end
	box(m, T * CFrame.new(0, 24, -122), Vector3.new(22, 34, 14), STYLE.Dark.color, STYLE.Dark.material)
end

local function buildParts(parent, T)
	local m = Util.model(parent, "PleiadesWatchtower")
	latheParts(m, T, bodyProfile(), STYLE.Stone)
	latheParts(m, T, SPIRE_PROFILE, STYLE.Stone)
	for k = 0, 5 do
		local a = k / 6 * TAU
		latheParts(m, T * CFrame.new(math.cos(a) * SATELLITE_RADIUS, 0, math.sin(a) * SATELLITE_RADIUS), SATELLITE_PROFILE, STYLE.Stone)
		local p = T * CFrame.new(math.cos(a) * SATELLITE_RADIUS, 0, math.sin(a) * SATELLITE_RADIUS)
		disc(m, (p * CFrame.new(0, 768.5, 0)).Position, 5, 31.4, STYLE.Gold.color, STYLE.Gold.material, NOSHADOW)
		disc(m, (p * CFrame.new(0, 691.5, 0)).Position, 3.5, 28.2, STYLE.Gold.color, STYLE.Gold.material, NOSHADOW)
	end
	-- warm bands and gold rings
	for _, b in ipairs({ { 22, 123, 3 }, { 150, 50, 2 }, { 562, 46.5, 2 }, { 690, 79, 3 } }) do
		disc(m, (T * CFrame.new(0, b[1] + b[3] / 2, 0)).Position, b[3], b[2] * 2 + 1.2, STYLE.Trim.color, STYLE.Trim.material, NOSHADOW)
	end
	disc(m, (T * CFrame.new(0, 877, 0)).Position, 3, 262, STYLE.Gold.color, STYLE.Gold.material, NOSHADOW)
	disc(m, (T * CFrame.new(0, 797, 0)).Position, 4.5, 47.2, STYLE.Gold.color, STYLE.Gold.material, NOSHADOW)
	-- ribs on the flare
	for k = 0, 15 do
		local a = k / 16 * TAU + TAU / 32
		for i = 0, 11 do
			local function at(t)
				local r = 44 + 78 * (1 - t) ^ 2.6 + 1.6
				return (T * CFrame.new(math.cos(a) * r, 26 + 132 * t, math.sin(a) * r)).Position
			end
			Util.rod(m, at(i / 12), at((i + 1) / 12), 3.4, STYLE.Trim.color, STYLE.Trim.material, NOSHADOW)
		end
	end
	-- window slits
	for _, z in ipairs({ 230, 330, 430, 520, 610 }) do
		local t = math.clamp((z - 168) / (560 - 168), 0, 1)
		local r = z < 560 and 42 + (25 - 42) * t ^ 0.8 or 26
		for k = 0, 5 do
			local a = k / 6 * TAU + (z % 7) * 0.2
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local cf = T * CFrame.lookAt(dir * (r - 0.4) + Vector3.new(0, z, 0), dir * r * 2 + Vector3.new(0, z, 0))
			box(m, cf, Vector3.new(3.2, 12, 2.4), STYLE.Dark.color, STYLE.Dark.material, NOSHADOW)
		end
	end
	portico(m, T)
	for _, s in ipairs({ -1, 1 }) do
		horn(m, T, s, STYLE.Stone, 0, 1, 1)
		horn(m, T, s, STYLE.Trim, -0.42, 0.22, 1.06)
	end
	return m
end

-- Imported mesh ----------------------------------------------------------------------------------------
function Watchtower.findImported()
	local ServerStorage = game:GetService("ServerStorage")
	local source = ServerStorage:FindFirstChild(Watchtower.IMPORT_NAME)
	if not source then
		local inWorkspace = workspace:FindFirstChild(Watchtower.IMPORT_NAME)
		if inWorkspace then
			-- keep the imported original safe in ServerStorage so rebuilds can reuse it
			inWorkspace.Parent = ServerStorage
			source = inWorkspace
		end
	end
	return source
end

local CORNERS = {}
for _, x in ipairs({ -1, 1 }) do
	for _, y in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			table.insert(CORNERS, Vector3.new(x, y, z))
		end
	end
end

local function bounds(parts)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in ipairs(parts) do
		local half = p.Size / 2
		for _, c in ipairs(CORNERS) do
			local w = p.CFrame * (c * half)
			lo = lo:Min(w)
			hi = hi:Max(w)
		end
	end
	return lo, hi
end

local function transform(parts, cf)
	for _, p in ipairs(parts) do
		p.CFrame = cf * p.CFrame
	end
end

local function about(center, rot)
	return CFrame.new(center) * rot * CFrame.new(-center)
end

local function findPart(parts, pattern)
	for _, p in ipairs(parts) do
		if string.find(p.Name, pattern) then
			return p
		end
	end
	return nil
end

local function placeImported(parent, source, base, front)
	local m = source:Clone()
	m.Name = "PleiadesWatchtower"
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if source:IsA("BasePart") then
		table.insert(parts, m)
	end
	if #parts == 0 then
		warn("[IslandMap] The imported PleiadesWatchtower has no parts; building the parts version instead")
		m:Destroy()
		return nil
	end

	-- 1. stand it upright: the tallest axis becomes Y
	local lo, hi = bounds(parts)
	local size, center = hi - lo, (lo + hi) / 2
	if size.X > size.Y and size.X >= size.Z then
		transform(parts, about(center, CFrame.Angles(0, 0, HALF_PI)))
	elseif size.Z > size.Y and size.Z > size.X then
		transform(parts, about(center, CFrame.Angles(-HALF_PI, 0, 0)))
	end
	local porch = findPart(parts, "Portico")
	lo, hi = bounds(parts)
	center = (lo + hi) / 2
	if porch and porch.Position.Y > center.Y then
		transform(parts, about(center, CFrame.Angles(math.pi, 0, 0)))
	end

	-- 2. scale to full size
	lo, hi = bounds(parts)
	center = (lo + hi) / 2
	local k = Watchtower.HEIGHT / (hi.Y - lo.Y)
	for _, p in ipairs(parts) do
		local rot = p.CFrame.Rotation
		p.Size = p.Size * k
		p.CFrame = CFrame.new(center + (p.Position - center) * k) * rot
	end

	-- 3. turn the entrance to face `front`
	local body = findPart(parts, "Body")
	lo, hi = bounds(parts)
	center = (lo + hi) / 2
	local axis = body and body.Position or center
	if porch then
		local d = porch.Position - axis
		local yaw = math.atan2(d.Z, d.X) - math.atan2(front.Z, front.X)
		transform(parts, about(Vector3.new(axis.X, center.Y, axis.Z), CFrame.Angles(0, yaw, 0)))
	end

	-- 4. stand it on the ground at `base`
	lo, hi = bounds(parts)
	axis = body and body.Position or (lo + hi) / 2
	transform(parts, CFrame.new(base.X - axis.X, base.Y - FOOT_DEPTH - lo.Y, base.Z - axis.Z))

	-- 5. colour by name prefix
	for _, p in ipairs(parts) do
		p.Anchored = true
		local prefix = string.match(p.Name, "^(%a+)_")
		local style = prefix and STYLE[prefix]
		if style then
			p.Color = style.color
			p.Material = style.material
		end
		if prefix == "Glow" then
			p.CanCollide = false
			p.CastShadow = false
		end
		pcall(function()
			p.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
		end)
	end
	if m:IsA("Model") then
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
	m.Parent = parent
	return m
end

-- Teleport circles --------------------------------------------------------------------------------------
local TELEPORT_SOURCE = [[
-- Teleport circle: touching it carries a player to the linked circle.
local pad = script.Parent
local busy = {}
pad.Touched:Connect(function(hit)
	local character = hit.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or busy[character] then
		return
	end
	local target = pad:GetAttribute("Target")
	if typeof(target) ~= "Vector3" then
		return
	end
	busy[character] = true
	character:PivotTo(CFrame.new(target + Vector3.new(0, 5, 0)))
	task.delay(2, function()
		busy[character] = nil
	end)
end)
]]

local function teleportPad(parent, pos, target, color)
	local pad = disc(parent, pos, 1, 16, color, M.Neon, NOSHADOW)
	pad.Name = "TeleportCircle"
	pad.Transparency = 0.25
	pad:SetAttribute("Target", target)
	Util.pointLight(pad, color, 2, 24)
	Util.particles(pad, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(color),
		Size = Util.ns(0, 0.8, 1, 0),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 25,
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(10, 10),
		EmissionDirection = Enum.NormalId.Right,
		LightEmission = 1,
	})
	local s = Instance.new("Script")
	s.Name = "Teleport"
	s.Source = TELEPORT_SOURCE
	s.Parent = pad
	return pad
end

---------------------------------------------------------------------------------------------------------
-- Builds the tower standing on `base` (ground point) with its entrance facing `front`.
function Watchtower.Build(parent, base, front)
	front = Vector3.new(front.X, 0, front.Z).Unit
	local T = CFrame.lookAt(base, base + front) -- local -Z is the entrance side
	local source = Watchtower.findImported()
	local m = source and placeImported(parent, source, base, front)
	if m then
		Util.log("  using the imported PleiadesWatchtower mesh")
	else
		m = buildParts(parent, T)
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end

	local extras = Util.model(parent, "WatchtowerLights")
	extras.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	-- warm lights around the balcony and the crown, and a glint like in the old paintings
	for k = 0, 3 do
		local a = k / 4 * TAU + TAU / 8
		local p = box(extras, T * CFrame.new(math.cos(a) * 44, Watchtower.BALCONY_TOP + 3, math.sin(a) * 44), Vector3.new(1.4, 2.4, 1.4), rgb(255, 220, 160), M.Neon, NOCOL_NOSHADOW)
		Util.pointLight(p, rgb(255, 210, 150), 1.5, 30)
	end
	local glint = box(extras, T * CFrame.new(0, 420, -38) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), Vector3.new(3, 3, 3), STYLE.Glow.color, M.Neon, NOCOL_NOSHADOW)
	Util.pointLight(glint, STYLE.Glow.color, 2, 50)
	Util.particles(glint, {
		Texture = Util.TEX.sparkle,
		Color = Util.cs(rgb(220, 240, 255), rgb(255, 236, 200)),
		Size = Util.ns(0, 6, 1, 0),
		Lifetime = NumberRange.new(1, 2),
		Rate = 6,
		Speed = NumberRange.new(0, 0.5),
		LightEmission = 1,
	})

	-- teleport circles: in front of the entrance <-> the crown platform
	local bottom = (T * CFrame.new(0, 0.6, -176)).Position
	local topPad = (T * CFrame.new(26, Watchtower.CROWN_TOP + 0.6, -15)).Position
	local landing = (T * CFrame.new(-26, Watchtower.CROWN_TOP + 0.6, 15)).Position
	teleportPad(extras, bottom, landing, rgb(160, 214, 255))
	teleportPad(extras, topPad, bottom + front * 16, rgb(255, 220, 150))
	return m
end

return Watchtower
