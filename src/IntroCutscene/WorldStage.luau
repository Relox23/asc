--[[
	WorldStage  (PLACEHOLDER — replaced by the real world stage, DESIGN §7.2)
	Minimal implementation of the stage interface (see init.luau) so the whole
	cutscene runs end to end: SkyRift, SoulCore, Sword, Shockwave, SlashArc and
	Blast follow their tracks (`visible`, `scale`, `opacity`, `resonance`, and
	`held` -> the sword sits in the right hand via CharacterRig:GripCF()). The
	sword is registered as an impact-frame silhouette.
]]

local Convert = require(script.Parent.Convert)

local WorldStage = {}
WorldStage.__index = WorldStage

local FOLLOW = { SkyRift = "Rift", SoulCore = "SoulCore", Sword = "ResonanceSword", Shockwave = "Shockwave", SlashArc = "SlashArc" }

function WorldStage.new(ctx)
	local self = setmetatable({}, WorldStage)
	self.ctx = ctx
	self.active = false
	local Assets = ctx.assets
	local folder = Instance.new("Folder")
	folder.Name = "World"
	self.folder = folder

	self.followers = {}
	for trackName, assetName in pairs(FOLLOW) do
		local track = ctx.timeline:track(trackName)
		if track and track.stage ~= "space" then
			local model = Assets.place(assetName, folder, nil, ctx.color)
			local f = { name = trackName, track = track, model = model, mover = Assets.mover(model), scale = 1, shown = true }
			table.insert(self.followers, f)
			if trackName == "Sword" then
				self.sword = f
				ctx.screen:AddSilhouette("sword", model)
			end
		end
	end
	local blastTrack = ctx.timeline:track("Blast")
	if blastTrack then
		local ball = Assets.part(folder, "Blast__Glow", "CoreGlow", Vector3.new(2, 2, 2), CFrame.new(), Enum.PartType.Ball)
		ball.Color = ctx.color
		self.blast = { track = blastTrack, part = ball }
	end
	folder.Parent = ctx.root
	return self
end

function WorldStage:SetActive(active)
	self.active = active
	self.folder.Parent = active and self.ctx.root or nil
end

function WorldStage:Update(t, _dt)
	local ctx = self.ctx
	local Assets = ctx.assets
	for _, f in ipairs(self.followers) do
		local s = f.track:sample(t)
		local ch = s.channels
		local show = (ch.visible == nil or ch.visible >= 0.5) and (f.track.stage ~= "camera" or t >= ctx.timeline.stageSwitch)
		if show ~= f.shown then
			f.shown = show
			f.model.Parent = show and self.folder or nil
		end
		if show then
			if math.abs(s.scale - f.scale) > 1e-3 and s.scale > 1e-3 then
				f.model:ScaleTo(s.scale)
				f.scale = s.scale
				f.mover = Assets.mover(f.model)
			end
			local cf
			if f == self.sword and (ch.held or 0) >= 0.5 then
				cf = ctx.character:GripCF()
			else
				cf = Convert.assetCF(ctx.origin(f.track.stage, t), s.pos, s.rot)
			end
			f.mover:MoveTo(cf)
			if ch.resonance and math.abs(ch.resonance - (f.resonance or -1)) > 0.01 then
				f.resonance = ch.resonance
				Assets.setResonance(f.model, ctx.color, ch.resonance)
			end
			if ch.opacity and math.abs(ch.opacity - (f.opacity or -1)) > 0.01 then
				f.opacity = ch.opacity
				Assets.setOpacity(f.model, ch.opacity)
			end
		end
	end
	local b = self.blast
	if b then
		local s = b.track:sample(t)
		local ch = s.channels
		local show = (ch.visible == nil or ch.visible >= 0.5) and s.scale > 1e-3
		b.part.Transparency = show and (1 - (ch.opacity or 1)) or 1
		if show then
			local d = math.clamp(s.scale * 2, 0.05, 2048)
			b.part.Size = Vector3.new(d, d, d)
			b.part.CFrame = Convert.cf(ctx.origin(b.track.stage, t), s.pos, s.rot)
		end
	end
end

function WorldStage:OnMarker(_kind, _args, _t) end

function WorldStage:Destroy()
	self.ctx.screen:RemoveSilhouette("sword")
	self.folder:Destroy()
end

return WorldStage
