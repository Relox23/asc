--[[
	SpaceStage  (stage "space", docs/intro/DESIGN.md §1 S0-S4, §3, §5, §7.2)
	Everything of the void far from the island, built at ctx.origins.space:

	  SkyAnchor   the dome, 1600 stars, 3 galaxies (point parts) and 8 nebulae (pre-warmed
	              ParticleEmitters), re-pivoted onto the camera every frame (one BulkMoveTo), so the
	              sky never parallaxes. Display rules exactly as tools/blender/intro/space.py:
	                star    b = clamp((stars - appear) / 0.08) * (1 - 0.45 * twinkle * (0.5 + 0.5 sin(2.2 t + phase)))
	                galaxy  u = smoothstep(clamp((galaxies - delay) / 0.7)); p = rotZ((1 - u) twist) lerp(from, to, u)
	                        in the galaxy frame (X = xaxis, Y = normal x xaxis, Z = normal), brightness u
	                nebula  a = smoothstep(clamp((nebula - appear) / 0.35))
	              Stars are opaque Neon balls whose colour is scaled by b (cheap: no transparency
	              sorting for 1600 parts); galaxy points are translucent Neon balls (transparency by u).
	  SoulCore    the asset + halo + PointLight (glow / pulse) + comet tail (tail channel: three Beams
	              trailing along -velocity, a Trail and a sparkle emitter, all in the soul colour)
	  Planet      ShatteredPlanet on its track
	  Rift        cracks revealed in order with flicker and small flashes (crack), shards flung outward
	              along the rift plane, tumbling and fading, rim and view scaling in (open)
	  DustMotes   specks streaming upward past the camera while falling

	Stage interface: see init.luau. Shared pieces for the world stage:
	    SpaceStage.Core.new(parent, assets, color, name)   soul core visual (also used in the world)
	    SpaceStage.Rift.new(parent, assets, name, opts)    rift visual (opts.farSide: the world's SkyRift)
	    SpaceStage.util                                    small helpers (present, velocity, emitter, ...)
]]

local Convert = require(script.Parent.Convert)

local SpaceStage = {}
SpaceStage.__index = SpaceStage

-- display rules of tools/blender/intro/space.py
local STAR_FADE = 0.08
local GALAXY_SPAN = 0.7
local NEBULA_FADE = 0.35
local TWINKLE_DEPTH = 0.45
local TWINKLE_SPEED = 2.2
-- stars smaller than this (studs at ~900 away, ~1 px at 1080p) would shimmer in and out of
-- existence between pixels; the size field stays the diameter otherwise
local STAR_MIN_D = 1.2
local GALAXY_POINT_TRANSPARENCY = 0.4 -- galaxy points at full brightness (overlaps read as glow)
local GALAXY_HAZE_TRANSPARENCY = 0.78 -- the dim, big puffs between the arms

-- built-in particle textures (content/textures/particles of the Roblox client)
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local TAU = math.pi * 2
local WHITE = Color3.new(1, 1, 1)
local NSK = NumberSequenceKeypoint.new

---------------------------------------------------------------------------------------------- helpers
local util = {}
SpaceStage.util = util

local function clamp01(x)
	return x < 0 and 0 or (x > 1 and 1 or x)
end
util.clamp01 = clamp01

local function smooth(x)
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end
util.smooth = smooth

-- deterministic pseudo random 0..1
local function hash(i, s)
	local x = math.sin(i * 12.9898 + s * 78.233) * 43758.5453
	return x - math.floor(x)
end
util.hash = hash

local function scaleColor(c, k)
	return Color3.new(c.R * k, c.G * k, c.B * k)
end
util.scaleColor = scaleColor

-- Is a track's object there at t? Its `visible` channel, and t inside the baked range (a track
-- baked for part of the timeline only exists there; single-sample tracks are constant).
local function present(track, s, t)
	local v = s.channels.visible
	if v ~= nil and v < 0.5 then
		return false
	end
	if track.n > 1 and (t < track.t0 - 1e-3 or t > track.t1 + 1e-3) then
		return false
	end
	return true
end
util.present = present

-- World-space velocity (studs/s) of a track at t, never differencing across a cut.
-- Leaves the track's sample table at time t.
local function velocity(tl, track, origin, t)
	local h = 1 / 30
	local a, b = t - h, t
	if tl:cutBetween(a, b) then
		a, b = t, t + h
	end
	local p0 = Convert.posOf(track:sample(a).pos)
	local p1 = Convert.posOf(track:sample(b).pos)
	track:sample(t)
	return origin:VectorToWorldSpace((p1 - p0) / (b - a))
end
util.velocity = velocity

local function invisiblePart(parent, name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Transparency = 1
	p.Size = size or Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = cf or CFrame.new()
	p.Parent = parent
	return p
end
util.invisiblePart = invisiblePart

local function attachment(parent, name, pos)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = pos or Vector3.zero
	a.Parent = parent
	return a
end
util.attachment = attachment

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.LightInfluence = 0
	e.Texture = TEX_SPARKLE
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end
util.emitter = emitter
util.TEX_SMOKE = TEX_SMOKE
util.TEX_SPARKLE = TEX_SPARKLE

local function light(parent, color, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = math.min(range or 16, 60)
	l.Brightness = 0
	l.Shadows = false
	l.Enabled = false
	l.Parent = parent
	return l
end
util.light = light

local function setLight(l, brightness, range)
	local on = brightness > 0.01
	if l.Enabled ~= on then
		l.Enabled = on
	end
	if on then
		l.Brightness = brightness
		if range then
			l.Range = math.clamp(range, 0, 60)
		end
	end
end
util.setLight = setLight

local function setParent(inst, parent)
	if inst.Parent ~= parent then
		inst.Parent = parent
	end
end
util.setParent = setParent

local function bulkMove(parts, cframes)
	if #parts == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i = 1, #parts do
			local p = parts[i]
			if p.Parent then
				p.CFrame = cframes[i]
			end
		end
	end
end
util.bulkMove = bulkMove

----------------------------------------------------------------------------------- soul core visual
local Core = {}
Core.__index = Core
SpaceStage.Core = Core

local TAIL_LENGTH = 18 -- studs at tail = 1 (core diameter ~3)
-- comet tail beams: { length factor, width at the core, width at the end, transparency at the core,
-- whiteness at the core }
local TAIL_BEAMS = {
	{ 1.0, 2.3, 0.15, 0.3, 0.35 },
	{ 0.7, 4.8, 0.7, 0.72, 0 },
	{ 0.42, 0.9, 0.05, 0.0, 0.8 },
}

function Core.new(parent, assets, color, name)
	local self = setmetatable({}, Core)
	self.color = color
	self.parent = parent
	local folder = Instance.new("Folder")
	folder.Name = name or "SoulCore"
	self.folder = folder
	local model = assets.place("SoulCore", folder, nil, color)
	self.model = model
	self.mover = assets.mover(model)
	self.glowParts = assets.pieces(model, "CoreGlow")
	self.ringParts = assets.pieces(model, "CoreRing")
	self.halo = assets.part(folder, "SoulCore__Halo", "CoreGlow", Vector3.new(4, 4, 4), CFrame.new(), Enum.PartType.Ball)
	self.halo.Color = color
	self.halo.Transparency = 1

	local fx = invisiblePart(folder, "SoulCore__FX")
	self.fx = fx
	self.light = light(fx, color, 20)
	local head = attachment(fx, "Head")
	self.tailEnds = {}
	self.beams = {}
	for k, spec in ipairs(TAIL_BEAMS) do
		local tip = attachment(fx, "Tail" .. k, Vector3.new(0, 0, -1))
		local b = Instance.new("Beam")
		b.Name = "Tail" .. k
		b.Attachment0 = head
		b.Attachment1 = tip
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 12
		b.Width0 = spec[2]
		b.Width1 = spec[3]
		b.Color = ColorSequence.new(color:Lerp(WHITE, spec[5]), color)
		b.Transparency = NumberSequence.new({ NSK(0, spec[4]), NSK(0.45, spec[4] + (1 - spec[4]) * 0.5), NSK(1, 1) })
		b.Enabled = false
		b.Parent = fx
		self.tailEnds[k] = tip
		self.beams[k] = b
	end
	local ta, tb = attachment(fx, "TrailA", Vector3.new(0, 0.85, 0)), attachment(fx, "TrailB", Vector3.new(0, -0.85, 0))
	local trail = Instance.new("Trail")
	trail.Attachment0 = ta
	trail.Attachment1 = tb
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(color:Lerp(WHITE, 0.4), color)
	trail.Transparency = NumberSequence.new({ NSK(0, 0.35), NSK(1, 1) })
	trail.WidthScale = NumberSequence.new({ NSK(0, 1), NSK(1, 0.1) })
	trail.Lifetime = 0.4
	trail.MinLength = 0.05
	trail.Enabled = false
	trail.Parent = fx
	self.trail = trail
	self.sparkles = emitter(fx, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(color:Lerp(WHITE, 0.6), color),
		LightEmission = 1,
		Size = NumberSequence.new({ NSK(0, 0.45, 0.15), NSK(1, 0) }),
		Transparency = NumberSequence.new({ NSK(0, 0), NSK(0.7, 0.3), NSK(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.4),
		Speed = NumberRange.new(0.5, 2.5),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Shape = Enum.ParticleEmitterShape.Sphere,
	})
	self.dir = Vector3.yAxis -- tail direction (world), kept when the core stands still
	self.shown = false
	self.last = {}
	return self
end

function Core:SetShown(shown)
	if shown == self.shown then
		return
	end
	self.shown = shown
	setParent(self.folder, shown and self.parent or nil)
	if not shown then
		self.trail.Enabled = false
		self.sparkles.Enabled = false
	end
end

function Core:ClearTrail()
	pcall(function()
		self.trail:Clear()
	end)
end

-- cf: core pivot (world), scale: track scale, ch: channels, vel: world velocity (studs/s)
function Core:Update(cf, scale, ch, vel)
	local glow = ch.glow or 1
	local pulse = ch.pulse or 0
	local tail = clamp01(ch.tail or 0)
	scale = math.max(scale or 1, 0.01)
	self.mover:MoveTo(cf, scale)
	local last = self.last
	if last.glow == nil or math.abs(glow - last.glow) > 0.004 or math.abs(pulse - last.pulse) > 0.004 then
		last.glow, last.pulse = glow, pulse
		local level = clamp01(glow) ^ 0.8
		local hot = clamp01((glow - 1) / 2) * 0.55 + clamp01(pulse) * 0.15
		local core = scaleColor(self.color, math.min(1, level * (1 + 0.35 * pulse))):Lerp(WHITE, hot)
		for _, p in ipairs(self.glowParts) do
			p.Color = core
		end
		local ring = scaleColor(self.color, math.min(1, level * 1.1))
		for _, p in ipairs(self.ringParts) do
			p.Color = ring
		end
		local halo = self.halo
		local alpha = math.clamp(0.06 * glow + 0.14 * pulse, 0, 0.36)
		halo.Transparency = alpha > 0.005 and 1 - alpha or 1
		local d = (2.9 + 1.1 * math.min(glow, 3)) * (1 + 0.35 * pulse) * scale
		halo.Size = Vector3.new(d, d, d)
		setLight(self.light, 0.8 * glow + 1.6 * pulse, (9 + 7 * math.min(glow, 3)) * scale)
	end
	local pos = cf.Position
	self.halo.CFrame = cf
	if vel and vel.Magnitude > 0.5 then
		self.dir = -vel.Unit
	end
	local dir = self.dir
	self.fx.CFrame = CFrame.lookAt(pos, pos + dir, math.abs(dir.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis)
	local L = tail * TAIL_LENGTH * scale
	local on = L > 0.2
	for k, b in ipairs(self.beams) do
		if b.Enabled ~= on then
			b.Enabled = on
		end
		if on then
			self.tailEnds[k].Position = Vector3.new(0, 0, -L * TAIL_BEAMS[k][1])
		end
	end
	local trailOn = tail > 0.03
	if self.trail.Enabled ~= trailOn then
		self.trail.Enabled = trailOn
	end
	if trailOn and math.abs(tail - (last.tail or -1)) > 0.01 then
		last.tail = tail
		self.trail.Lifetime = 0.12 + 0.5 * tail
		self.trail.MaxLength = 2 + L
	end
	local sp = self.sparkles
	local rate = 50 * tail
	if sp.Enabled ~= (rate > 0.5) then
		sp.Enabled = rate > 0.5
	end
	if rate > 0.5 then
		sp.Rate = rate
		sp.Acceleration = dir * 6
	end
end

function Core:Destroy()
	self.folder:Destroy()
end

----------------------------------------------------------------------------------------- rift visual
local Rift = {}
Rift.__index = Rift
SpaceStage.Rift = Rift

local RIFT_LIGHT = Color3.fromRGB(190, 140, 255)

--[[ opts.farSide: the world's SkyRift, seen from the far side, where the forest picture would be
	wrong: its view becomes a dark violet glow (a hole into space). ]]
function Rift.new(parent, assets, name, opts)
	opts = opts or {}
	local self = setmetatable({}, Rift)
	self.parent = parent
	local folder = Instance.new("Folder")
	folder.Name = name
	self.folder = folder
	local model = assets.place("Rift", folder)
	self.model = model
	local parts = assets.pieces(model)
	self.parts = parts
	self.base = {}
	self.cframes = {}
	self.lastT = {}
	self.lastS = {}
	local idx = {}
	for i, p in ipairs(parts) do
		idx[p] = i
		self.base[i] = { cf = p.CFrame, size = p.Size, tr = p:GetAttribute("BaseTransparency") or p.Transparency }
		self.cframes[i] = p.CFrame
		self.lastS[i] = 1
	end
	local function indices(style)
		local list = {}
		for _, p in ipairs(assets.pieces(model, style)) do
			table.insert(list, idx[p])
		end
		return list
	end
	self.cracks = indices("Crack")
	self.shards = indices("Shard")
	self.rims = indices("RiftEdge")
	self.views = indices("RiftView")
	self.role = {}
	for k, i in ipairs(self.cracks) do
		self.role[i] = { kind = "crack", k = k }
	end
	for k, i in ipairs(self.shards) do
		local rng = Random.new(1009 + k * 31)
		local pos = self.base[i].cf.Position
		local flat = Vector3.new(pos.X, 0, pos.Z)
		local a = rng:NextNumber(0, TAU)
		self.role[i] = {
			kind = "shard",
			dir = flat.Magnitude > 0.3 and flat.Unit or Vector3.new(math.cos(a), 0, math.sin(a)),
			dist = rng:NextNumber(9, 24),
			lift = rng:NextNumber(0.5, 5),
			axis = rng:NextUnitVector(),
			spin = rng:NextNumber(2.5, 7.5),
			fade = rng:NextNumber(0.4, 0.62),
		}
	end
	for _, i in ipairs(self.rims) do
		self.role[i] = { kind = "rim" }
	end
	for _, i in ipairs(self.views) do
		self.role[i] = { kind = "view" }
	end
	if opts.farSide then
		for _, i in ipairs(self.views) do
			local p = parts[i]
			for _, c in ipairs(p:GetChildren()) do
				if c:IsA("SurfaceAppearance") or c:IsA("Decal") then
					c:Destroy()
				end
			end
			if p:IsA("MeshPart") then
				pcall(function()
					p.TextureID = ""
				end)
			end
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(24, 10, 46)
		end
	end
	for _, p in ipairs(parts) do
		p.Transparency = 1
	end
	self.anchor = invisiblePart(folder, "Rift__FX")
	self.light = light(self.anchor, RIFT_LIGHT, 50)
	self.flashAt = attachment(self.anchor, "Flash")
	self.flash = emitter(self.flashAt, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(WHITE, RIFT_LIGHT),
		LightEmission = 1,
		Size = NumberSequence.new({ NSK(0, 2.6, 0.8), NSK(1, 0) }),
		Transparency = NumberSequence.new({ NSK(0, 0), NSK(1, 0.6) }),
		Lifetime = NumberRange.new(0.12, 0.28),
		Speed = NumberRange.new(0, 0.5),
		Rotation = NumberRange.new(0, 360),
		Brightness = 2,
	})
	self.revealed = {}
	self.shown = false
	self.scale = 1
	return self
end

function Rift:SetShown(shown)
	if shown ~= self.shown then
		self.shown = shown
		setParent(self.folder, shown and self.parent or nil)
	end
end

local function setTransparency(self, i, tr)
	if math.abs(tr - self.lastT[i]) > 0.004 or (tr >= 1) ~= (self.lastT[i] >= 1) then
		self.lastT[i] = tr
		self.parts[i].Transparency = tr
	end
end

-- cf: rift pivot (world), scale: track scale, crack/open: channels 0..1, t: cutscene time
function Rift:Update(cf, scale, crack, open, t)
	local S = math.max(scale or 1, 0.01)
	local parts, base, cframes, lastS = self.parts, self.base, self.cframes, self.lastS
	local lastT = self.lastT
	for i in ipairs(parts) do
		lastT[i] = lastT[i] or -1
	end
	local nCracks = #self.cracks
	local frame = math.floor(t * 30)
	local openE = 1 - (1 - open) ^ 2.2 -- ease out: shards fly fast, then drift
	local rimS = 0.22 + 0.78 * smooth(open / 0.7)
	local viewS = smooth((open - 0.04) / 0.6)
	local crackFade = 1 - smooth(open / 0.35)
	local activity = 0
	for i, p in ipairs(parts) do
		local b = base[i]
		local role = self.role[i]
		local localCF, size, tr = b.cf, 1, 1
		local kind = role and role.kind
		if kind == "crack" then
			local k = role.k
			local r = (k - 1) / math.max(nCracks, 1) * 0.9
			local lvl = clamp01((crack - r) / 0.05)
			local fresh = 1 - clamp01((crack - r) / 0.18)
			local flick = hash(k, frame) > 0.45 and 1 or 0.2
			local vis = lvl * (1 - fresh * (1 - flick)) * crackFade
			tr = 1 - (1 - b.tr) * vis
			if lvl > 0 and lvl < 1 then
				activity = math.max(activity, fresh)
			end
			if lvl > 0 and not self.revealed[k] then
				self.revealed[k] = true
				if self.shown and crackFade > 0.5 then
					self.flashAt.Position = b.cf.Position * S
					self.flash:Emit(3)
				end
			elseif lvl <= 0 then
				self.revealed[k] = nil
			end
		elseif kind == "shard" then
			local glass = open > 0.001 and 1 or smooth((crack - 0.55) / 0.45) * 0.55
			local vis = glass * (1 - smooth((open - role.fade) / (1 - role.fade)))
			tr = 1 - (1 - b.tr) * vis
			if open > 0.001 then
				local pos = b.cf.Position + role.dir * (role.dist * openE) + Vector3.yAxis * (role.lift * openE)
				localCF = CFrame.new(pos) * CFrame.fromAxisAngle(role.axis, role.spin * open) * b.cf.Rotation
				size = 1 - 0.35 * open
			end
		elseif kind == "rim" then
			tr = open > 0.005 and b.tr or 1
			localCF = CFrame.new(b.cf.Position * rimS) * b.cf.Rotation
			size = rimS
		elseif kind == "view" then
			tr = viewS > 0.02 and b.tr or 1
			localCF = CFrame.new(b.cf.Position * viewS) * b.cf.Rotation
			size = math.max(viewS, 0.02)
		end
		setTransparency(self, i, tr)
		local s = size * S
		if math.abs(s - lastS[i]) > 1e-3 * math.max(s, 0.01) then
			lastS[i] = s
			local sz = b.size * s
			p.Size = Vector3.new(math.max(sz.X, 0.001), math.max(sz.Y, 0.001), math.max(sz.Z, 0.001))
		end
		if S ~= 1 then
			localCF = CFrame.new(localCF.Position * S) * localCF.Rotation
		end
		cframes[i] = cf * localCF
	end
	bulkMove(parts, cframes)
	self.model.WorldPivot = cf
	self.anchor.CFrame = cf
	local flicker = activity * (hash(frame, 3.7) > 0.6 and 1 or 0.25)
	setLight(self.light, 3 * smooth(open) + 2.5 * flicker, 46 * S)
end

function Rift:Destroy()
	self.folder:Destroy()
end

---------------------------------------------------------------------------------------- the sky
-- Builds the SkyAnchor contents. Returns the sky state used by SpaceStage:_updateSky.
local function buildSky(model, assets, starfield)
	local sky = {
		parts = {}, -- every part moved with the sky (one BulkMoveTo)
		offsets = {}, -- their sky-local CFrames
		cframes = {},
		stars = {},
		galaxies = {},
		nebulae = {},
	}
	local function add(p, offset)
		table.insert(sky.parts, p)
		table.insert(sky.offsets, offset)
		table.insert(sky.cframes, offset)
		return #sky.parts
	end
	local dome = assets.place("SpaceDome", model, Convert.ASSET_TURN)
	for _, p in ipairs(assets.pieces(dome)) do
		add(p, p.CFrame)
	end

	local tpl = Instance.new("Part")
	tpl.Shape = Enum.PartType.Ball
	tpl.Material = Enum.Material.Neon
	tpl.Anchored = true
	tpl.CanCollide = false
	tpl.CanTouch = false
	tpl.CanQuery = false
	tpl.CastShadow = false
	tpl.Massless = true
	tpl.TopSurface = Enum.SurfaceType.Smooth
	tpl.BottomSurface = Enum.SurfaceType.Smooth
	tpl.Transparency = 1

	local data = starfield or {}
	local stars = data.stars or {}
	local starFolder = Instance.new("Folder")
	starFolder.Name = "Stars"
	starFolder.Parent = model
	for k = 0, #stars // 9 - 1 do
		local o = k * 9
		local d = math.max(stars[o + 4], STAR_MIN_D)
		local p = tpl:Clone()
		p.Name = "Star"
		p.Size = Vector3.new(d, d, d)
		local offset = CFrame.new(Convert.pos(stars[o + 1], stars[o + 2], stars[o + 3]))
		p.CFrame = offset
		p.Parent = starFolder
		add(p, offset)
		table.insert(sky.stars, {
			part = p,
			color = Color3.new(stars[o + 5], stars[o + 6], stars[o + 7]),
			appear = stars[o + 8],
			phase = stars[o + 9],
			b = -1,
		})
	end

	for gi, g in ipairs(data.galaxies or {}) do
		local n = g.normal or { 0, 0, 1 }
		local Z = Vector3.new(n[1], n[2], n[3]).Unit
		local X
		if g.xaxis then
			X = Vector3.new(g.xaxis[1], g.xaxis[2], g.xaxis[3]).Unit
		else -- space.frame_axes
			local helper = math.abs(Z.Z) < 0.9 and Vector3.zAxis or Vector3.xAxis
			X = helper:Cross(Z).Unit
		end
		local Y = Z:Cross(X)
		local c = g.center or { 0, 0, 0 }
		local gal = {
			c = Convert.pos(c[1], c[2], c[3]),
			X = Convert.pos(X.X, X.Y, X.Z),
			Y = Convert.pos(Y.X, Y.Y, Y.Z),
			Z = Convert.pos(Z.X, Z.Y, Z.Z),
			twist = g.twist or 0,
			points = {},
		}
		local folder = Instance.new("Folder")
		folder.Name = "Galaxy_" .. gi
		folder.Parent = model
		local pts = g.points or {}
		for k = 0, #pts // 11 - 1 do
			local o = k * 11
			local col = Color3.new(pts[o + 8], pts[o + 9], pts[o + 10])
			local haze = math.max(col.R, col.G, col.B) < 0.42
			local d = math.max(pts[o + 7], 0.5)
			local p = tpl:Clone()
			p.Name = "GalaxyPoint"
			p.Size = Vector3.new(d, d, d)
			p.Color = haze and scaleColor(col, 1.6) or col
			p.Parent = folder
			local pt = {
				part = p,
				from = Vector3.new(pts[o + 1], pts[o + 2], pts[o + 3]),
				to = Vector3.new(pts[o + 4], pts[o + 5], pts[o + 6]),
				delay = pts[o + 11],
				base = haze and GALAXY_HAZE_TRANSPARENCY or GALAXY_POINT_TRANSPARENCY,
				u = -1,
			}
			pt.index = add(p, CFrame.new(gal.c))
			table.insert(gal.points, pt)
		end
		table.insert(sky.galaxies, gal)
	end

	for ni, nb in ipairs(data.nebulae or {}) do
		local c = nb.center or { 0, 0, 0 }
		local r = nb.radius or 150
		local col = nb.color or { 0.5, 0.3, 0.9 }
		local color = Color3.new(col[1], col[2], col[3])
		local anchor = Instance.new("Part")
		anchor.Name = "Nebula_" .. ni
		anchor.Shape = Enum.PartType.Ball
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(r, r, r) * 0.8
		anchor.Parent = model
		local offset = CFrame.new(Convert.pos(c[1], c[2], c[3]))
		anchor.CFrame = offset
		add(anchor, offset)
		local common = {
			Texture = TEX_SMOKE,
			LightEmission = 1,
			LightInfluence = 0,
			Lifetime = NumberRange.new(20),
			Speed = NumberRange.new(0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-3, 3),
			LockedToPart = true,
			-- slowed down: the pre-warmed clouds outlive any hitch of the stage (~400 s)
			TimeScale = 0.05,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Transparency = NumberSequence.new(1),
		}
		local haze = emitter(anchor, common)
		haze.Name = "Haze"
		haze.Color = ColorSequence.new(color)
		haze.Size = NumberSequence.new({ NSK(0, r * 1.6, r * 0.35), NSK(1, r * 1.6, r * 0.35) })
		local core = emitter(anchor, common)
		core.Name = "Core"
		core.Color = ColorSequence.new(color:Lerp(Color3.new(1, 0.92, 1), 0.35))
		core.Size = NumberSequence.new({ NSK(0, r * 0.85, r * 0.25), NSK(1, r * 0.85, r * 0.25) })
		table.insert(sky.nebulae, {
			appear = nb.appear or 0,
			emitters = { { e = haze, count = 7, alpha = 0.42 }, { e = core, count = 4, alpha = 0.3 } },
			a = -1,
		})
	end
	tpl:Destroy()
	return sky
end

-- galaxy point positions for channel value g (sky-local offsets + brightness)
local function layoutGalaxies(sky, g)
	local offsets = sky.offsets
	for _, gal in ipairs(sky.galaxies) do
		local c, X, Y, Z, twist = gal.c, gal.X, gal.Y, gal.Z, gal.twist
		for _, pt in ipairs(gal.points) do
			local u = smooth((g - pt.delay) / GALAXY_SPAN)
			local f, to = pt.from, pt.to
			local x = f.X + (to.X - f.X) * u
			local y = f.Y + (to.Y - f.Y) * u
			local z = f.Z + (to.Z - f.Z) * u
			local phi = (1 - u) * twist
			local cs, sn = math.cos(phi), math.sin(phi)
			local xr, yr = x * cs - y * sn, x * sn + y * cs
			offsets[pt.index] = CFrame.new(c + X * xr + Y * yr + Z * z)
			if math.abs(u - pt.u) > 0.01 or (u <= 0) ~= (pt.u <= 0) or (u >= 1 and pt.u < 1) then
				pt.u = u
				pt.part.Transparency = u > 0.003 and 1 - (1 - pt.base) * u or 1
			end
		end
	end
end

---------------------------------------------------------------------------------------- the stage
function SpaceStage.new(ctx)
	local self = setmetatable({}, SpaceStage)
	self.ctx = ctx
	self.active = false
	local Assets = ctx.assets
	local tl = ctx.timeline
	local folder = Instance.new("Folder")
	folder.Name = "Space"
	self.folder = folder

	local skyModel = Instance.new("Model")
	skyModel.Name = "SkyAnchor"
	self.skyModel = skyModel
	self.sky = buildSky(skyModel, Assets, ctx.data.starfield)
	skyModel.WorldPivot = CFrame.new()
	skyModel.Parent = folder
	self.starfield = tl:track("Starfield")
	self.channels = { stars = -1, galaxies = -1, nebula = -1 }

	local function trackOf(name)
		local track = tl:track(name)
		if track and track.stage ~= "world" then
			return track
		end
		return nil
	end
	self.coreTrack = tl:track("SoulCore") -- space + world: this stage shows it while active
	if self.coreTrack then
		self.core = Core.new(folder, Assets, ctx.color, "SoulCore")
	end
	self.planetTrack = trackOf("Planet")
	if self.planetTrack then
		self.planet = Assets.place("ShatteredPlanet", folder)
		self.planet.Name = "Planet"
		self.planetMover = Assets.mover(self.planet)
		self.planetShown = true
	end
	self.riftTrack = trackOf("Rift")
	if self.riftTrack then
		self.rift = Rift.new(folder, Assets, "Rift")
	end

	-- dust motes streaming past the camera (world-space particles left behind as it falls)
	local motes = invisiblePart(folder, "DustMotes", Vector3.new(70, 50, 70))
	self.motes = emitter(motes, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(205, 220, 255)),
		LightEmission = 1,
		Size = NumberSequence.new({ NSK(0, 0), NSK(0.15, 0.22, 0.1), NSK(0.85, 0.22, 0.1), NSK(1, 0) }),
		Transparency = NumberSequence.new({ NSK(0, 0.35), NSK(1, 0.6) }),
		Lifetime = NumberRange.new(2, 3.5),
		Rate = 80,
		Speed = NumberRange.new(6, 9),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(8, 8),
		Rotation = NumberRange.new(0, 360),
	})
	self.motesPart = motes
	local spawn = tl:firstMarker("stage", "world")
	self.motesFrom = 1.5
	self.motesTo = spawn and spawn.t or tl.stageSwitch
	self.prewarmed = false
	folder.Parent = ctx.root
	return self
end

function SpaceStage:SetActive(active)
	self.active = active
	self.folder.Parent = active and self.ctx.root or nil
	if not active then
		self.motes.Enabled = false
	end
end

function SpaceStage:_updateSky(t)
	local ctx = self.ctx
	local sky = self.sky
	local sf = self.starfield
	local function ch(name)
		local v = sf and sf:channel(name, t)
		return v == nil and 1 or v
	end
	local starsCh, galCh, nebCh, twinkle = ch("stars"), ch("galaxies"), ch("nebula"), ch("twinkle")

	if math.abs(galCh - self.channels.galaxies) > 1e-5 then
		self.channels.galaxies = galCh
		layoutGalaxies(sky, galCh)
	end
	-- re-pivot onto the camera: the sky never parallaxes (DESIGN §2 SkyAnchor)
	local skyCF = CFrame.new(ctx.cameraCF.Position) * ctx.origins.space.Rotation
	local parts, offsets, cframes = sky.parts, sky.offsets, sky.cframes
	for i = 1, #parts do
		cframes[i] = skyCF * offsets[i]
	end
	bulkMove(parts, cframes)
	self.skyModel.WorldPivot = skyCF

	for _, s in ipairs(sky.stars) do
		local fade = clamp01((starsCh - s.appear) / STAR_FADE)
		local b = 0
		if fade > 0 then
			b = fade * (1 - TWINKLE_DEPTH * twinkle * (0.5 + 0.5 * math.sin(TWINKLE_SPEED * t + s.phase)))
		end
		local last = s.b
		if math.abs(b - last) > 0.012 or (b <= 0.004) ~= (last <= 0.004) then
			s.b = b
			local p = s.part
			if b > 0.004 then
				p.Color = scaleColor(s.color, b)
				if last <= 0.004 then
					p.Transparency = 0
				end
			else
				p.Transparency = 1
			end
		end
	end

	if not self.prewarmed then
		-- the clouds exist from the start (invisible), so they never pop in
		self.prewarmed = true
		for _, nb in ipairs(sky.nebulae) do
			for _, spec in ipairs(nb.emitters) do
				spec.e:Emit(spec.count)
			end
		end
	end
	if math.abs(nebCh - self.channels.nebula) > 1e-4 then
		self.channels.nebula = nebCh
		for _, nb in ipairs(sky.nebulae) do
			local a = smooth((nebCh - nb.appear) / NEBULA_FADE)
			if math.abs(a - nb.a) > 0.005 or (a <= 0) ~= (nb.a <= 0) then
				nb.a = a
				for _, spec in ipairs(nb.emitters) do
					spec.e.Transparency = NumberSequence.new(1 - a * spec.alpha)
				end
			end
		end
	end
end

function SpaceStage:Update(t, dt)
	local ctx = self.ctx
	local tl = ctx.timeline
	local origin = ctx.origins.space
	self:_updateSky(t)

	if self.core then
		local track = self.coreTrack
		local vel = velocity(tl, track, origin, t)
		local s = track:sample(t)
		local shown = present(track, s, t)
		self.core:SetShown(shown)
		if shown then
			self.core:Update(Convert.assetCF(origin, s.pos, s.rot), s.scale, s.channels, vel)
		end
	end

	if self.planet then
		local track = self.planetTrack
		local s = track:sample(t)
		local shown = present(track, s, t) and s.scale > 1e-3
		if shown ~= self.planetShown then
			self.planetShown = shown
			self.planet.Parent = shown and self.folder or nil
		end
		if shown then
			self.planetMover:MoveTo(Convert.assetCF(ctx.origin(track.stage, t), s.pos, s.rot), s.scale)
		end
	end

	if self.rift then
		local track = self.riftTrack
		local s = track:sample(t)
		local ch = s.channels
		local shown = present(track, s, t) and s.scale > 1e-3
		self.rift:SetShown(shown)
		if shown then
			self.rift:Update(Convert.assetCF(ctx.origin(track.stage, t), s.pos, s.rot), s.scale, ch.crack or 0, ch.open or 0, t)
		end
	end

	-- dust motes: an emission box around the camera; the specks stay in the world, so the fall
	-- makes them stream upward. Their own speed tops the relative speed up to ~10 studs/s.
	local camPos = ctx.cameraCF.Position
	local on = t >= self.motesFrom and t < self.motesTo
	if self.motes.Enabled ~= on then
		self.motes.Enabled = on
	end
	if on then
		local fall = 0
		if self.lastCam and dt and dt > 1e-4 then
			fall = math.clamp((self.lastCam.Y - camPos.Y) / dt, 0, 200)
		end
		local up = math.max(1, 10 - fall)
		self.motes.Speed = NumberRange.new(up * 0.7, up * 1.1)
	end
	self.lastCam = camPos
	self.motesPart.CFrame = CFrame.new(camPos - Vector3.new(0, 18, 0))
end

function SpaceStage:OnMarker(kind, _args, _t)
	if kind == "cut" and self.core then
		self.core:ClearTrail()
	end
end

function SpaceStage:Destroy()
	self.folder:Destroy()
end

return SpaceStage
