--[[
	SpaceStage  (PLACEHOLDER — replaced by the real space stage, DESIGN §7.2)
	Minimal implementation of the stage interface (see init.luau) so the whole
	cutscene runs end to end: the space dome and a few hundred stars follow the
	camera (SkyAnchor), and the SoulCore / Planet / Rift tracks move their
	IntroAssets models (shown by their `visible` channel, scaled by `scale`).
]]

local Convert = require(script.Parent.Convert)

local SpaceStage = {}
SpaceStage.__index = SpaceStage

local FOLLOW = { SoulCore = "SoulCore", Planet = "ShatteredPlanet", Rift = "Rift" }
local MAX_STARS = 400

function SpaceStage.new(ctx)
	local self = setmetatable({}, SpaceStage)
	self.ctx = ctx
	self.active = false
	local Assets = ctx.assets
	local folder = Instance.new("Folder")
	folder.Name = "Space"
	self.folder = folder

	-- SkyAnchor: dome + stars, re-pivoted onto the camera every frame
	local sky = Instance.new("Model")
	sky.Name = "SkyAnchor"
	sky.Parent = folder
	Assets.place("SpaceDome", sky)
	local stars = ctx.data.starfield and ctx.data.starfield.stars or {}
	self.stars = {}
	local count = math.min(#stars // 9, MAX_STARS)
	for k = 0, count - 1 do
		local b = k * 9
		local size = math.max(stars[b + 4], 0.6) * 2
		local p = Assets.part(sky, "Star", "Crack", Vector3.new(size, size, size), CFrame.new(Convert.pos(stars[b + 1], stars[b + 2], stars[b + 3])), Enum.PartType.Ball)
		p.Color = Color3.new(stars[b + 5], stars[b + 6], stars[b + 7])
		p.Transparency = 1
		table.insert(self.stars, { part = p, appear = stars[b + 8] })
	end
	sky.WorldPivot = CFrame.new()
	self.skyMover = Assets.mover(sky)
	self.starfield = ctx.timeline:track("Starfield")

	self.followers = {}
	for trackName, assetName in pairs(FOLLOW) do
		local track = ctx.timeline:track(trackName)
		if track and track.stage ~= "world" then
			local model = Assets.place(assetName, folder, nil, ctx.color)
			table.insert(self.followers, { track = track, model = model, mover = Assets.mover(model), scale = 1, shown = true })
		end
	end
	folder.Parent = ctx.root
	return self
end

function SpaceStage:SetActive(active)
	self.active = active
	self.folder.Parent = active and self.ctx.root or nil
end

function SpaceStage:Update(t, _dt)
	local ctx = self.ctx
	local origin = ctx.origins.space
	self.skyMover:MoveTo(CFrame.new(ctx.cameraCF.Position) * origin.Rotation)
	local level = self.starfield and self.starfield:channel("stars", t) or 1
	for _, s in ipairs(self.stars) do
		s.part.Transparency = 1 - math.clamp((level - s.appear) / 0.08, 0, 1)
	end
	for _, f in ipairs(self.followers) do
		local s = f.track:sample(t)
		local visible = s.channels.visible
		local show = visible == nil or visible >= 0.5
		if show ~= f.shown then
			f.shown = show
			f.model.Parent = show and self.folder or nil
		end
		if show then
			if math.abs(s.scale - f.scale) > 1e-3 and s.scale > 1e-3 then
				f.model:ScaleTo(s.scale)
				f.scale = s.scale
				f.mover = ctx.assets.mover(f.model)
			end
			f.mover:MoveTo(Convert.assetCF(ctx.origin(f.track.stage, t), s.pos, s.rot))
		end
	end
end

function SpaceStage:OnMarker(_kind, _args, _t) end

function SpaceStage:Destroy()
	self.folder:Destroy()
end

return SpaceStage
