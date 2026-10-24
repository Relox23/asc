--[[
	WorldStage  (stage "world", docs/intro/DESIGN.md §1 W1-W8, §3, §7.2, §7.3)
	Everything above and on Sylverune, built at ctx.origins.world (read every frame: the landing
	point may be refined right before this stage starts):

	  SkyRift     the Rift asset high in the sky, opening downward (SpaceStage.Rift, far side: the
	              view is a dark violet hole into space instead of the forest picture)
	  SoulCore    the world part of the core (SpaceStage.Core: glow, pulse, comet tail) until the
	              morph; the `morph` marker condenses light into the character (sparkles flying in,
	              a burst + light flash at the end)
	  Sword       ResonanceSword: `resonance` blends the Crystal pieces from colourless glass to
	              Neon soul colour (Assets.setResonance), `glow` -> light + outline, `held` -> the
	              pivot sits in the character's right hand (CharacterRig:GripCF, every frame);
	              registered as an impact-frame silhouette; `resonate` -> burst of sparkles;
	              a glowing wake (Trail) while surfing and sparks while braking
	  Blast       glow-explosion sphere (Neon balls in the soul colour, `opacity`, diameter = 2 x scale)
	  SlashArc    the swing's crescent (`opacity`)
	  Shockwave   the ring (uniform scale = radius, `opacity`, white -> soul colour as it fades) and a
	              dust wall racing outward along the ground with it (emitters on the ring, ground
	              found by raycasts) + a dust burst at the stop (`shockwave` marker)
	  Streaks     3D speed streaks flowing past the character during the dive (speedlines window)
	  Wind        trees bend away from the landing point (§7.3, exactly; every pivot saved and
	              restored exactly), workspace.GlobalWind gust (saved and restored)

	Everything this stage makes lives in one folder under ctx.root; every property it changes on
	map instances (tree part CFrames, model WorldPivots, workspace.GlobalWind) is put back exactly
	when the wind has passed, on SetActive(false) and in Destroy().
	Stage interface: see init.luau.
]]

local Convert = require(script.Parent.Convert)
local SpaceStage = require(script.Parent.SpaceStage)

local util = SpaceStage.util
local clamp01, hash = util.clamp01, util.hash
local present, velocity = util.present, util.velocity
local invisiblePart, attachment, emitter = util.invisiblePart, util.attachment, util.emitter
local light, setLight, setParent = util.light, util.setLight, util.setParent
local TEX_SMOKE, TEX_SPARKLE = util.TEX_SMOKE, util.TEX_SPARKLE
local TEX_SPARKS = "rbxasset://textures/particles/fire_sparks_main.dds" -- built-in (Fire's sparks)

local WorldStage = {}
WorldStage.__index = WorldStage

local WHITE = Color3.new(1, 1, 1)
local TAU = math.pi * 2
local NSK = NumberSequenceKeypoint.new
local CSK = ColorSequenceKeypoint.new

-- §7.3 shockwave wind
local WIND_SPEED = 160 -- studs/s, the wave front
local WIND_SETTLE = 4.5 -- tau after which a tree is back at rest (restored exactly)
local function windF(tau)
	if tau < 0 then
		return 0
	end
	return (1 - math.exp(-tau / 0.12)) * math.exp(-tau / 1.1) * math.cos(TAU * tau / 1.6)
end
local function windA(d)
	return 0.42 * math.clamp(1 - d / 340, 0.15, 1)
end
WorldStage.windF = windF
WorldStage.windA = windA

local GUST = 55 -- studs/s added to workspace.GlobalWind at the peak (grass flattening)
local GUST_END = 5.5 -- seconds after the wind marker the gust is over (GlobalWind restored)
local BRAKE_TIME = 2.0 -- the brake ends at the shockwave marker (DESIGN §1: 33.0-35.0)
local MORPH_CONDENSE = 0.6 -- morph marker -> burst (DESIGN §1: morph 20.3, flash 20.9)
local DUST_EMITTERS = 32 -- each one hops around its sector of the ring every frame
local DUST_SECTORS = 96 -- ground heights are raycast once per (sector, 8-stud radius step)
local STREAKS = 18
local STREAK_SPAN = 70 -- studs of streak field along the travel direction

---------------------------------------------------------------------------------------- helpers
-- CFrame at pos whose UpVector is up (any right vector).
local function frameUp(pos, up)
	local helper = math.abs(up.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis
	local right = helper:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, up, right:Cross(up))
end

-- Linear position of a baked sampler (Track or the character sampler) at t, Blender coordinates
-- -> Roblox stage-local Vector3. No table writes (safe to call between other samples).
local function samplerPos(s, t)
	local P = s.posData
	if not P then
		return Vector3.zero
	end
	local n = s.n
	local fi = math.clamp((t - s.t0) * s.rate, 0, math.max(n - 1, 0))
	local i = math.floor(fi)
	local f = fi - i
	if i >= n - 1 then
		i, f = n - 1, 0
	end
	local b = i * 3
	local x, y, z = P[b + 1], P[b + 2], P[b + 3]
	if f > 0 then
		x += (P[b + 4] - x) * f
		y += (P[b + 5] - y) * f
		z += (P[b + 6] - z) * f
	end
	return Convert.pos(x, y, z)
end

-- World velocity of a sampler at t (one-sided at cuts).
local function samplerVel(tl, s, origin, t)
	local h = 1 / 30
	local a, b = t - h, t
	if tl:cutBetween(a, b) then
		a, b = t, t + h
	end
	return origin:VectorToWorldSpace((samplerPos(s, b) - samplerPos(s, a)) / (b - a))
end

local function window(t, t0, t1, fadeIn, fadeOut)
	if not t0 or not t1 or t < t0 or t > t1 then
		return 0
	end
	return clamp01((t - t0) / fadeIn) * clamp01((t1 - t) / fadeOut)
end

local function setEnabled(inst, on)
	if inst.Enabled ~= on then
		inst.Enabled = on
	end
end

local function moveParts(parts, cframes)
	if #parts == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(parts) do
			pcall(function()
				p.CFrame = cframes[i]
			end)
		end
	end
end

local function isTreePiece(name)
	return string.find(name, "Trunk", 1, true) ~= nil or string.find(name, "Bark", 1, true) ~= nil
end

---------------------------------------------------------------------------------------- the sword
local Sword = {}
Sword.__index = Sword

local CRYSTAL_PALE = Color3.fromRGB(225, 235, 245)

function Sword.new(parent, ctx)
	local self = setmetatable({}, Sword)
	local Assets = ctx.assets
	self.ctx = ctx
	self.color = ctx.color
	local model = Assets.place("ResonanceSword", parent)
	model.Name = "Sword"
	self.model = model
	Assets.setResonance(model, ctx.color, 0)
	self.resonance = 0
	self.mover = Assets.mover(model)
	ctx.screen:AddSilhouette("sword", model)

	-- blade extent along the sword's +Y (asset-local, pivot = grip centre)
	local tip, base = 0, math.huge
	local pivot = model:GetPivot()
	for _, p in ipairs(Assets.pieces(model, "Blade")) do
		local o = pivot:ToObjectSpace(p.CFrame)
		local half = 0.5 * (math.abs(o.XVector.Y) * p.Size.X + math.abs(o.YVector.Y) * p.Size.Y + math.abs(o.ZVector.Y) * p.Size.Z)
		tip = math.max(tip, o.Position.Y + half)
		base = math.min(base, o.Position.Y - half)
	end
	if tip <= 0 then
		tip, base = 4.5, 0.65
	end
	base = math.clamp(base, 0.3, tip * 0.5)
	self.tip, self.base = tip, base

	local fx = invisiblePart(parent, "Sword__FX")
	self.fx = fx
	self.tipAt = attachment(fx, "Tip", Vector3.new(0, tip - 0.25, 0))
	self.baseAt = attachment(fx, "Base", Vector3.new(0, base + 0.2, 0))
	self.midAt = attachment(fx, "Mid", Vector3.new(0, (tip + base) / 2, 0))
	self.light = light(fx, CRYSTAL_PALE, 12)

	local wake = Instance.new("Trail")
	wake.Name = "Wake"
	wake.Attachment0 = self.tipAt
	wake.Attachment1 = self.baseAt
	wake.LightEmission = 1
	wake.LightInfluence = 0
	wake.Color = ColorSequence.new(ctx.color:Lerp(WHITE, 0.45), ctx.color)
	wake.Transparency = NumberSequence.new({ NSK(0, 0.25), NSK(0.6, 0.75), NSK(1, 1) })
	wake.Lifetime = 0.35
	wake.MinLength = 0.05
	wake.Enabled = false
	wake.Parent = fx
	self.wake = wake

	self.burst = emitter(self.midAt, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(ctx.color:Lerp(WHITE, 0.7), ctx.color),
		LightEmission = 1,
		Size = NumberSequence.new({ NSK(0, 0.7, 0.25), NSK(1, 0) }),
		Transparency = NumberSequence.new({ NSK(0, 0), NSK(0.6, 0.2), NSK(1, 1) }),
		Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(10, 26),
		Drag = 3,
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
	})

	-- sparks while braking: a tiny part whose +Y is the spray direction
	local sparkPart = invisiblePart(parent, "Sword__Sparks", Vector3.new(0.3, 0.3, 0.3))
	self.sparkPart = sparkPart
	self.sparks = emitter(sparkPart, {
		Texture = TEX_SPARKS,
		Color = ColorSequence.new({ CSK(0, WHITE), CSK(0.35, ctx.color:Lerp(WHITE, 0.5)), CSK(1, ctx.color) }),
		LightEmission = 1,
		Size = NumberSequence.new({ NSK(0, 0.32, 0.1), NSK(1, 0) }),
		Squash = NumberSequence.new(2.2),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Transparency = NumberSequence.new({ NSK(0, 0), NSK(0.7, 0.15), NSK(1, 1) }),
		Lifetime = NumberRange.new(0.25, 0.65),
		Speed = NumberRange.new(22, 46),
		SpreadAngle = Vector2.new(26, 26),
		Acceleration = Vector3.new(0, -55, 0),
		Drag = 2,
		EmissionDirection = Enum.NormalId.Top,
		Brightness = 2,
	})

	local hl = Instance.new("Highlight")
	hl.Name = "SwordGlow"
	hl.Adornee = model
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.Enabled = false
	hl.Parent = fx
	self.highlight = hl

	self.shown = true
	self.last = {}
	return self
end

function Sword:SetShown(shown, parent)
	if shown == self.shown then
		return
	end
	self.shown = shown
	setParent(self.model, shown and parent or nil)
	if not shown then
		self.wake.Enabled = false
		self.sparks.Enabled = false
		self.highlight.Enabled = false
		setLight(self.light, 0)
	end
end

-- cf: pivot (world), scale: track scale, ch: channels; extra: { flash = 0..1 light spike,
-- wake = bool, sparks = rate, sparkDir = world direction of the spray }
function Sword:Update(cf, scale, ch, extra)
	local Assets = self.ctx.assets
	self.mover:MoveTo(cf, math.max(scale or 1, 0.01))
	self.fx.CFrame = cf
	local r = clamp01(ch.resonance or self.resonance)
	if math.abs(r - self.resonance) > 0.004 or (r >= 1 and self.resonance < 1) or (r <= 0 and self.resonance > 0) then
		self.resonance = r
		Assets.setResonance(self.model, self.color, r)
	end
	local glow = math.max(ch.glow or 0, 0)
	local flash = extra.flash or 0
	local glowColor = CRYSTAL_PALE:Lerp(self.color, r)
	local last = self.last
	if last.glow == nil or math.abs(glow - last.glow) > 0.01 or math.abs(r - last.r) > 0.01 or flash > 0 or last.flash > 0 then
		last.glow, last.r, last.flash = glow, r, flash
		local level = clamp01(glow / 3)
		setLight(self.light, 1.3 * glow + 6 * flash, 8 + 6 * math.min(glow, 3) + 20 * flash)
		self.light.Color = glowColor
		local hl = self.highlight
		local on = level > 0.02 or flash > 0.02
		setEnabled(hl, on)
		if on then
			local k = math.min(1, level + flash)
			hl.OutlineColor = glowColor:Lerp(WHITE, 0.2)
			hl.OutlineTransparency = 1 - 0.85 * k
			hl.FillColor = glowColor
			hl.FillTransparency = 1 - 0.3 * k
		end
	end
	setEnabled(self.wake, extra.wake == true)
	local rate = extra.sparks or 0
	local on = rate > 1
	setEnabled(self.sparks, on)
	if on then
		self.sparks.Rate = rate
		local dir = extra.sparkDir
		if not dir or dir.Magnitude < 1e-3 then
			dir = cf.UpVector
		end
		-- from the blade's rear half, spraying back along the travel direction
		local at = cf * Vector3.new(0, self.base + (self.tip - self.base) * 0.25, 0)
		self.sparkPart.CFrame = frameUp(at, dir.Unit)
	end
end

function Sword:Burst()
	self.burst:Emit(70)
end

function Sword:ClearTrail()
	pcall(function()
		self.wake:Clear()
	end)
end

---------------------------------------------------------------------------------------- the stage
function WorldStage.new(ctx)
	local self = setmetatable({}, WorldStage)
	self.ctx = ctx
	self.active = false
	local Assets = ctx.assets
	local tl = ctx.timeline
	local folder = Instance.new("Folder")
	folder.Name = "World"
	self.folder = folder

	local function trackOf(name)
		local track = tl:track(name)
		if track and track.stage ~= "space" then
			return track
		end
		return nil
	end

	-- times of the events this stage animates (from the markers, so the state is a function of t)
	local switch = tl.stageSwitch
	local function markerAfter(kind, arg1, after)
		for _, m in ipairs(tl.markers) do
			if m.kind == kind and (arg1 == nil or m.args[1] == arg1) and m.t >= after - 1e-6 then
				return m
			end
		end
		return nil
	end
	local morph = markerAfter("morph", nil, -math.huge)
	self.morphT = morph and morph.t or nil
	if self.morphT then
		-- the burst comes with the flash right after the morph (DESIGN §1: 20.3 -> flash 20.9)
		local flash = markerAfter("flash", nil, self.morphT + 0.1)
		self.morphBurstT = (flash and flash.t <= self.morphT + 1.5) and flash.t or self.morphT + MORPH_CONDENSE
	end
	local shock = markerAfter("shockwave", nil, -math.huge)
	self.shockT = shock and shock.t or nil
	local wind = markerAfter("wind", nil, -math.huge)
	local worldData = ctx.data.world or {}
	self.windT = (wind and wind.t) or worldData.windStart
	self.windStrength = wind and tonumber(wind.args[1]) or 1
	local surfOn = markerAfter("speedlines", "on", switch)
	local surfOff = surfOn and markerAfter("speedlines", "off", surfOn.t)
	self.surf0 = surfOn and surfOn.t or nil
	self.surf1 = surfOff and surfOff.t or self.shockT
	if self.shockT then
		self.brake0, self.brake1 = self.shockT - BRAKE_TIME, self.shockT
	end

	self.skyRiftTrack = trackOf("SkyRift")
	if self.skyRiftTrack then
		self.skyRift = SpaceStage.Rift.new(folder, Assets, "SkyRift", { farSide = true })
	end
	self.coreTrack = trackOf("SoulCore")
	if self.coreTrack then
		self.core = SpaceStage.Core.new(folder, Assets, ctx.color, "SoulCore")
	end
	self.swordTrack = trackOf("Sword")
	if self.swordTrack then
		self.sword = Sword.new(folder, ctx)
	end

	self.blastTrack = trackOf("Blast")
	if self.blastTrack then
		local outer = Assets.part(folder, "Blast__Glow", "CoreGlow", Vector3.new(2, 2, 2), CFrame.new(), Enum.PartType.Ball)
		outer.Color = ctx.color
		outer.Transparency = 1
		local inner = Assets.part(folder, "Blast__Core", "CoreGlow", Vector3.new(1, 1, 1), CFrame.new(), Enum.PartType.Ball)
		inner.Color = ctx.color:Lerp(WHITE, 0.55)
		inner.Transparency = 1
		self.blast = {
			outer = outer,
			inner = inner,
			light = light(outer, ctx.color, 60),
			glow = util.glowSprite(outer, "BlastGlow", ctx.color:Lerp(WHITE, 0.25)), -- soft halo around the sphere
			shown = false,
		}
	end

	self.slashTrack = trackOf("SlashArc")
	if self.slashTrack then
		local model = Assets.place("SlashArc", folder, nil, ctx.color)
		self.slash = { model = model, mover = Assets.mover(model), opacity = -1, shown = true }
	end

	self.shockTrack = trackOf("Shockwave")
	if self.shockTrack then
		local model = Assets.place("Shockwave", folder, nil, ctx.color, 0)
		self.shock = { model = model, mover = Assets.mover(model), opacity = -1, blend = -1, shown = true }
	end

	-- dust: a wall of dust riding the ring along the ground + the burst at the stop
	local dustPart = invisiblePart(folder, "ShockDust")
	self.dustPart = dustPart
	local dustColor = Color3.fromRGB(196, 182, 156)
	self.dust = {}
	for k = 1, DUST_EMITTERS do
		local a = attachment(dustPart, "Dust" .. k)
		local e = emitter(a, {
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(dustColor:Lerp(ctx.color, 0.12), dustColor),
			LightInfluence = 0.8,
			LightEmission = 0.05,
			Size = NumberSequence.new({ NSK(0, 4, 1), NSK(0.35, 11, 2.5), NSK(1, 18, 4) }),
			Transparency = NumberSequence.new({ NSK(0, 0.2), NSK(0.5, 0.45), NSK(1, 1) }),
			Lifetime = NumberRange.new(1.1, 2.1),
			Speed = NumberRange.new(5, 14),
			SpreadAngle = Vector2.new(30, 30),
			Drag = 1.6,
			Acceleration = Vector3.new(0, 2.5, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
			EmissionDirection = Enum.NormalId.Top,
		})
		self.dust[k] = { at = a, e = e, base = (k - 1) / DUST_EMITTERS * TAU }
	end
	self.dustBurstAt = attachment(dustPart, "Burst")
	self.dustBurst = emitter(self.dustBurstAt, {
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(dustColor:Lerp(WHITE, 0.15), dustColor),
		LightInfluence = 0.8,
		Size = NumberSequence.new({ NSK(0, 4, 1.5), NSK(0.4, 12, 3), NSK(1, 20, 4) }),
		Transparency = NumberSequence.new({ NSK(0, 0.35), NSK(0.6, 0.6), NSK(1, 1) }),
		Lifetime = NumberRange.new(1.4, 2.6),
		Speed = NumberRange.new(30, 70),
		SpreadAngle = Vector2.new(84, 84),
		Drag = 2.6,
		Acceleration = Vector3.new(0, 3, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		EmissionDirection = Enum.NormalId.Top,
	})

	-- morph: light condensing into the body, then a burst
	local morphPart = invisiblePart(folder, "MorphFX", Vector3.new(9, 9, 9))
	self.morphPart = morphPart
	self.condense = emitter(morphPart, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(ctx.color, ctx.color:Lerp(WHITE, 0.8)),
		LightEmission = 1,
		Size = NumberSequence.new({ NSK(0, 0.15), NSK(0.3, 0.55, 0.2), NSK(1, 0.1) }),
		Transparency = NumberSequence.new({ NSK(0, 1), NSK(0.2, 0.1), NSK(1, 0.3) }),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(7, 12),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Rotation = NumberRange.new(0, 360),
	})
	self.morphAt = attachment(morphPart, "Center")
	self.morphBurst = emitter(self.morphAt, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(ctx.color:Lerp(WHITE, 0.6), ctx.color),
		LightEmission = 1,
		Size = NumberSequence.new({ NSK(0, 0.9, 0.3), NSK(1, 0) }),
		Transparency = NumberSequence.new({ NSK(0, 0), NSK(0.7, 0.25), NSK(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.3),
		Speed = NumberRange.new(14, 32),
		Drag = 3.5,
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-180, 180),
	})
	self.morphLight = light(morphPart, ctx.color, 30)

	-- speed streaks: beams flowing past the character during the dive
	local streakPart = invisiblePart(folder, "Streaks")
	self.streakPart = streakPart
	self.streaks = {}
	for k = 1, STREAKS do
		local a0 = attachment(streakPart, "S" .. k .. "a")
		local a1 = attachment(streakPart, "S" .. k .. "b")
		local b = Instance.new("Beam")
		b.Name = "Streak" .. k
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 1
		b.Color = ColorSequence.new(WHITE:Lerp(ctx.color, 0.25))
		b.Transparency = NumberSequence.new({ NSK(0, 0.2), NSK(1, 1) })
		b.Width0 = 0.1
		b.Width1 = 0.02
		b.Enabled = false
		b.Parent = streakPart
		local radius = 2.5 + 11 * hash(k, 1)
		local ang = hash(k, 2) * TAU
		self.streaks[k] = {
			beam = b,
			a0 = a0,
			a1 = a1,
			x = math.cos(ang) * radius,
			y = math.sin(ang) * radius,
			phase = hash(k, 4),
			len = 0.6 + 0.8 * hash(k, 5),
			on = false,
		}
	end

	self.trees = nil -- collected when the stage starts (after streaming, with the final landing)
	self.savedWind = nil
	return self
end

function WorldStage:SetActive(active)
	if active == self.active then
		return
	end
	self.active = active
	self.folder.Parent = active and self.ctx.root or nil
	if active then
		self:_collectTrees()
	else
		self:_restoreTrees()
		self:_restoreWind()
	end
end

---------------------------------------------------------------------------------------- trees
function WorldStage:_exclusions()
	local list = { self.ctx.root }
	local Players = game:GetService("Players")
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

function WorldStage:_collectTrees()
	if self.trees then
		return
	end
	local ctx = self.ctx
	local trees = {}
	self.trees = trees
	local landing = ctx.landing
	if not landing then
		return
	end
	local radius = (ctx.config and ctx.config.WIND_RADIUS) or 320
	local seen = {}
	local claimed = {} -- parts already moved by a tree (nested models never move a part twice)
	local function consider(model, loose)
		if seen[model] or not model:IsA("Model") or model == workspace then
			return
		end
		seen[model] = true
		if model:FindFirstChildOfClass("Humanoid") or model:IsDescendantOf(ctx.root) then
			return
		end
		local ok, pivot = pcall(model.GetPivot, model)
		if not ok or not pivot then
			return
		end
		if loose then
			-- a model found by its Trunk / Bark piece may have its pivot at the middle: bend it
			-- about the bottom of its bounding box (the generator's trees pivot at their base)
			local okBox, boxCF, boxSize = pcall(model.GetBoundingBox, model)
			if okBox and boxCF then
				local bottom = boxCF.Position.Y - 0.5 * (math.abs(boxCF.XVector.Y) * boxSize.X + math.abs(boxCF.YVector.Y) * boxSize.Y + math.abs(boxCF.ZVector.Y) * boxSize.Z)
				if pivot.Y - bottom > 2 then
					pivot = CFrame.new(pivot.X, bottom, pivot.Z) * pivot.Rotation
				end
			end
		end
		local flat = Vector3.new(pivot.X - landing.X, 0, pivot.Z - landing.Z)
		local d = flat.Magnitude
		if d > radius then
			return
		end
		local parts, orig, offsets = {}, {}, {}
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Anchored and not claimed[p] then
				claimed[p] = true
				table.insert(parts, p)
				table.insert(orig, p.CFrame)
				table.insert(offsets, pivot:ToObjectSpace(p.CFrame))
			end
		end
		if #parts == 0 then
			return
		end
		local away = d > 0.05 and flat.Unit or Vector3.xAxis
		table.insert(trees, {
			model = model,
			parts = parts,
			orig = orig,
			offsets = offsets,
			cframes = table.clone(orig),
			pivot = pivot,
			worldPivot = model.WorldPivot,
			hasPrimary = model.PrimaryPart ~= nil,
			d = d,
			axis = Vector3.yAxis:Cross(away).Unit, -- +angle tilts the top away from the landing point
			A = windA(d),
			moved = false,
			done = false,
		})
	end
	local island = workspace:FindFirstChild("Island")
	local forest = island and island:FindFirstChild("Forest")
	local folder = forest and forest:FindFirstChild("Trees")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			consider(m)
		end
	end
	-- any other model with a Trunk / Bark piece nearby
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self:_exclusions()
	local ok, hits = pcall(function()
		return workspace:GetPartBoundsInRadius(landing, radius + 40, params)
	end)
	if ok and hits then
		for _, p in ipairs(hits) do
			if not claimed[p] and isTreePiece(p.Name) then
				local m = p:FindFirstAncestorOfClass("Model")
				if m then
					consider(m, true)
				end
			end
		end
	end
end

local function restoreTree(tree)
	if tree.moved then
		tree.moved = false
		moveParts(tree.parts, tree.orig)
		if not tree.hasPrimary then
			pcall(function()
				tree.model.WorldPivot = tree.worldPivot
			end)
		end
	end
end

function WorldStage:_restoreTrees()
	for _, tree in ipairs(self.trees or {}) do
		restoreTree(tree)
	end
end

function WorldStage:_updateTrees(t)
	local trees = self.trees
	local t0 = self.windT
	if not trees or not t0 or t < t0 then
		return
	end
	local strength = self.windStrength or 1
	local batchParts, batchCF = self.batchParts or {}, self.batchCF or {}
	self.batchParts, self.batchCF = batchParts, batchCF
	table.clear(batchParts)
	table.clear(batchCF)
	for _, tree in ipairs(trees) do
		if not tree.done then
			local tau = t - t0 - tree.d / WIND_SPEED
			if tau > WIND_SETTLE then
				restoreTree(tree)
				tree.done = true
			elseif tau >= 0 then
				local theta = tree.A * strength * windF(tau)
				local p = tree.pivot.Position
				local pivot = CFrame.new(p) * CFrame.fromAxisAngle(tree.axis, theta) * tree.pivot.Rotation
				local offsets, cframes = tree.offsets, tree.cframes
				for i, part in ipairs(tree.parts) do
					local cf = pivot * offsets[i]
					cframes[i] = cf
					table.insert(batchParts, part)
					table.insert(batchCF, cf)
				end
				if not tree.hasPrimary then
					tree.model.WorldPivot = pivot
				end
				tree.moved = true
			end
		end
	end
	moveParts(batchParts, batchCF)
end

---------------------------------------------------------------------------------------- wind gust
function WorldStage:_restoreWind()
	if self.savedWind then
		pcall(function()
			workspace.GlobalWind = self.savedWind
		end)
		self.savedWind = nil
	end
end

function WorldStage:_updateWind(t)
	local t0 = self.windT
	if not t0 or t < t0 or self.windDone then
		return
	end
	local tau = t - t0
	if tau > GUST_END then
		self:_restoreWind()
		self.windDone = true
		return
	end
	if not self.savedWind then
		self.savedWind = workspace.GlobalWind
		-- the wave travels toward the camera of the wide shot: blow from the landing point to it
		local ctx = self.ctx
		local d = ctx.cameraCF.Position - ctx.landing
		d = Vector3.new(d.X, 0, d.Z)
		self.windDir = d.Magnitude > 1 and d.Unit or ctx.origins.world.LookVector
	end
	local env = (1 - math.exp(-tau / 0.15)) * math.exp(-tau / 1.5)
	workspace.GlobalWind = self.savedWind + self.windDir * (GUST * (self.windStrength or 1) * env)
end

---------------------------------------------------------------------------------------- frame
function WorldStage:_updateCore(t, origin)
	local track = self.coreTrack
	local s = track:sample(t)
	local shown = t >= self.ctx.timeline.stageSwitch - 1e-6 and present(track, s, t)
	self.core:SetShown(shown)
	if shown then
		local vel = velocity(self.ctx.timeline, track, origin, t)
		s = track:sample(t)
		self.core:Update(Convert.assetCF(origin, s.pos, s.rot), s.scale, s.channels, vel)
	end
end

function WorldStage:_updateMorph(t)
	local tm, tb = self.morphT, self.morphBurstT
	local active = tm ~= nil and t >= tm - 0.05 and t <= tb + 1.6
	local cond = active and t < tb
	setEnabled(self.condense, cond)
	if not active then
		setLight(self.morphLight, 0)
		return
	end
	local rig = self.ctx.character
	local cf = rig and rig.rootCF
	if cf then
		self.morphPart.CFrame = CFrame.new(cf.Position)
	end
	local u = clamp01((t - tm) / math.max(tb - tm, 0.05))
	if cond then
		self.condense.Rate = 90 + 110 * u
	elseif not self.morphBurstDone then
		self.morphBurstDone = true
		self.morphBurst:Emit(90)
	end
	local b
	if t < tb then
		b = 1.5 + 4.5 * u * u
	else
		b = 10 * math.exp(-(t - tb) / 0.35)
	end
	setLight(self.morphLight, b, 18 + 12 * u)
end

function WorldStage:_updateSword(t, origin, rootVel)
	local track = self.swordTrack
	local sword = self.sword
	local s = track:sample(t)
	local ch = s.channels
	local shown = present(track, s, t)
	sword:SetShown(shown, self.folder)
	if not shown then
		return
	end
	local rig = self.ctx.character
	local cf
	if (ch.held or 0) >= 0.5 and rig and rig.animated then
		cf = rig:GripCF()
	else
		cf = Convert.assetCF(origin, s.pos, s.rot)
	end
	local extra = self.swordExtra or {}
	self.swordExtra = extra
	local tr = self.resonateT
	extra.flash = tr and t >= tr and math.exp(-(t - tr) / 0.25) or 0
	if extra.flash < 0.01 then
		extra.flash = 0
	end
	extra.wake = self.surf0 ~= nil and t >= self.surf0 and t <= (self.shockT or self.surf1 or self.surf0)
	local brake = window(t, self.brake0, self.brake1, 0.25, 0.08)
	extra.sparks = brake * (100 + 100 * clamp01((t - (self.brake0 or t)) / BRAKE_TIME))
	extra.sparkDir = -rootVel + Vector3.new(0, 0.35 * rootVel.Magnitude + 2, 0)
	sword:Update(cf, s.scale, ch, extra)
end

function WorldStage:_updateBlast(t, origin)
	local b = self.blast
	local track = self.blastTrack
	local s = track:sample(t)
	local opacity = clamp01(s.channels.opacity or 1)
	local shown = present(track, s, t) and s.scale > 1e-3 and opacity > 0.003
	if shown ~= b.shown then
		b.shown = shown
		if not shown then
			b.outer.Transparency = 1
			b.inner.Transparency = 1
			setLight(b.light, 0)
			util.setGlow(b.glow, 0, 0)
		end
	end
	if not shown then
		return
	end
	local d = math.clamp(s.scale * 2, 0.05, 2048)
	local cf = origin * CFrame.new(Convert.posOf(s.pos))
	b.outer.Size = Vector3.new(d, d, d)
	b.outer.CFrame = cf
	b.outer.Transparency = 1 - 0.62 * opacity
	local di = math.max(d * 0.55, 0.05)
	b.inner.Size = Vector3.new(di, di, di)
	b.inner.CFrame = cf
	b.inner.Transparency = 1 - 0.9 * opacity
	setLight(b.light, 7 * opacity, math.min(10 + d * 1.5, 60))
	util.setGlow(b.glow, d * 1.3, 0.6 * opacity, nil, 1.5)
end

function WorldStage:_follow(f, track, t, origin)
	local Assets = self.ctx.assets
	local s = track:sample(t)
	local opacity = clamp01(s.channels.opacity or 1)
	local shown = present(track, s, t) and s.scale > 1e-3 and opacity > 0.003
	if shown ~= f.shown then
		f.shown = shown
		setParent(f.model, shown and self.folder or nil)
	end
	if not shown then
		return nil
	end
	f.mover:MoveTo(Convert.assetCF(origin, s.pos, s.rot), s.scale)
	if math.abs(opacity - f.opacity) > 0.005 then
		f.opacity = opacity
		Assets.setOpacity(f.model, opacity)
	end
	return s, opacity
end

-- Ground height under the ring at angle a (radians) and radius, cached per sector / radius step.
function WorldStage:_groundAt(center, a, radius)
	local cache = self.groundCache
	if not cache or (self.groundCenter - center).Magnitude > 1 then
		cache = {}
		self.groundCache, self.groundCenter = cache, center
	end
	local sec = math.floor(a / TAU * DUST_SECTORS) % DUST_SECTORS
	local step = math.floor(radius / 8 + 0.5)
	local key = step * DUST_SECTORS + sec
	local y = cache[key]
	if y == nil then
		local ab = (sec + 0.5) / DUST_SECTORS * TAU
		local p = center + Vector3.new(math.cos(ab), 0, math.sin(ab)) * (step * 8)
		local hit = self.rayParams and workspace:Raycast(p + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), self.rayParams)
		y = hit and hit.Position.Y or center.Y
		cache[key] = y
	end
	return y
end

function WorldStage:_updateShock(t, origin)
	local f = self.shock
	local s, opacity = self:_follow(f, self.shockTrack, t, origin)
	local dustOn = false
	if s then
		local blend = clamp01(1 - opacity)
		if math.abs(blend - f.blend) > 0.02 then
			f.blend = blend
			self.ctx.assets.recolor(f.model, self.ctx.color, blend)
		end
		-- dust riding the ring along the ground
		local radius = s.scale -- the ring asset has radius 1
		local center = origin * Convert.posOf(s.pos)
		local maxR = ((self.ctx.config and self.ctx.config.WIND_RADIUS) or 320) + 80
		dustOn = radius > 3 and radius < maxR and opacity > 0.08
		if dustOn then
			self.dustPart.CFrame = CFrame.new(center)
			-- denser as the ring grows (the same dust per stud of ring), thinning out at the edge
			local rate = math.clamp(radius * 0.09, 8, 30) * opacity * clamp01((maxR - radius) / 80)
			local frame = math.floor(t * 60)
			local sector = TAU / DUST_EMITTERS
			for k, dk in ipairs(self.dust) do
				local a = (dk.base + sector * hash(k, frame)) % TAU
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				local y = self:_groundAt(center, a, radius)
				dk.at.CFrame = frameUp(Vector3.new(dir.X * radius, y - center.Y + 0.5, dir.Z * radius), (dir * 1.4 + Vector3.yAxis).Unit)
				dk.e.Rate = rate
				setEnabled(dk.e, true)
			end
		end
	end
	if not dustOn then
		for _, dk in ipairs(self.dust) do
			setEnabled(dk.e, false)
		end
	end
end

function WorldStage:_updateStreaks(t, rootVel)
	local level = window(t, self.surf0, self.surf1, 0.2, 0.25)
	local speed = rootVel.Magnitude
	level *= clamp01((speed - 12) / 45)
	local rig = self.ctx.character
	local center = rig and rig.rootCF and rig.rootCF.Position
	if level < 0.02 or not center or speed < 1 then
		if self.streaksOn then
			self.streaksOn = false
			for _, st in ipairs(self.streaks) do
				st.beam.Enabled = false
				st.on = false
			end
		end
		return
	end
	self.streaksOn = true
	local dir = rootVel.Unit
	-- the field's -Z is the travel direction
	self.streakPart.CFrame = CFrame.lookAt(center, center + dir, math.abs(dir.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis)
	local flow = speed * 1.1
	local len = math.clamp(speed * 0.16, 3, 16)
	for k, st in ipairs(self.streaks) do
		-- along the travel axis: from STREAK_SPAN/2 ahead to STREAK_SPAN/2 behind, wrapping
		local u = (st.phase - t * flow / STREAK_SPAN) % 1
		local z = -(u - 0.5) * STREAK_SPAN -- local -Z = ahead
		local fade = math.sin(math.pi * u)
		local w = level * fade * (0.6 + 0.4 * hash(k, 6))
		local on = w > 0.05
		if on ~= st.on then
			st.on = on
			st.beam.Enabled = on
		end
		if on then
			st.a0.Position = Vector3.new(st.x, st.y, z)
			st.a1.Position = Vector3.new(st.x, st.y, z + len * st.len)
			st.beam.Width0 = 0.13 * w
			st.beam.Width1 = 0.02 * w
		end
	end
end

function WorldStage:Update(t, _dt)
	local ctx = self.ctx
	local tl = ctx.timeline
	local origin = ctx.origins.world
	if not self.rayParams then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = self:_exclusions()
		params.IgnoreWater = false
		params.RespectCanCollide = true
		self.rayParams = params
	end

	if self.skyRift then
		local track = self.skyRiftTrack
		local s = track:sample(t)
		local shown = present(track, s, t) and s.scale > 1e-3
		self.skyRift:SetShown(shown)
		if shown then
			local ch = s.channels
			self.skyRift:Update(Convert.assetCF(origin, s.pos, s.rot), s.scale, ch.crack or 1, ch.open or 1, t)
		end
	end
	if self.core then
		self:_updateCore(t, origin)
	end
	self:_updateMorph(t)

	local rootVel = Vector3.zero
	local cs = tl:characterTrack()
	if cs and cs.posData then
		rootVel = samplerVel(tl, cs, origin, t)
	end
	if self.sword then
		self:_updateSword(t, origin, rootVel)
	end
	if self.blast then
		self:_updateBlast(t, origin)
	end
	if self.slash then
		self:_follow(self.slash, self.slashTrack, t, origin)
	end
	if self.shock then
		self:_updateShock(t, origin)
	end
	self:_updateStreaks(t, rootVel)
	self:_updateTrees(t)
	self:_updateWind(t)
end

function WorldStage:OnMarker(kind, _args, t)
	if kind == "cut" then
		if self.core then
			self.core:ClearTrail()
		end
		if self.sword then
			self.sword:ClearTrail()
		end
	elseif kind == "resonate" then
		self.resonateT = t
		if self.sword and self.active then
			self.sword:Burst()
		end
	elseif kind == "shockwave" then
		self.shockT = self.shockT or t
		if self.active then
			-- dust bursts from the ground under the sword
			local center
			local sword = self.sword
			if sword and sword.shown then
				center = sword.model:GetPivot().Position
			else
				local rig = self.ctx.character
				center = rig and rig.rootCF and rig.rootCF.Position
			end
			if center then
				local hit = self.rayParams and workspace:Raycast(center + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), self.rayParams)
				local ground = hit and hit.Position or Vector3.new(center.X, self.ctx.landing.Y, center.Z)
				self.dustPart.CFrame = CFrame.new(ground)
				self.dustBurstAt.CFrame = CFrame.new(0, 0.5, 0)
				self.dustBurst:Emit(60)
			end
		end
	elseif kind == "wind" then
		self.windT = t
	end
end

function WorldStage:Destroy()
	self:_restoreTrees()
	self:_restoreWind()
	pcall(function()
		self.ctx.screen:RemoveSilhouette("sword")
	end)
	self.folder:Destroy()
end

return WorldStage
