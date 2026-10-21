--[[
	LightingFX
	Lighting looks of the intro (DESIGN §7.2). Everything it touches is saved
	first and put back exactly by Restore (properties, enabled flags, parents).

	    local fx = LightingFX.new(camera?)
	    fx:Begin()            save + Lighting:SetAttribute("CutsceneActive", true)
	    fx:Space()            black ambient, low side sun, strong bloom, cool grade; Atmosphere and Sky
	                          taken out of Lighting, Clouds and every post effect (Lighting + camera) off
	    fx:World()            the saved look again + a slight warm grade
	    fx:Set(prop, value)   change a Lighting property (saved; put back by the next Space/World
	                          switch and by Restore, so a stage sets its tweaks in SetActive(true))
	    fx:Effect(className, props) -> instance  an extra effect in Lighting, destroyed by Restore
	                          (destroy it yourself earlier if it belongs to one stage only)
	    fx:Restore()          everything back, attribute back, created effects destroyed (idempotent)

	LightingFX.SPACE / LightingFX.SPACE_EFFECTS / LightingFX.WORLD_GRADE are the
	looks (stages may tweak them before calling Space/World).
]]

local Lighting = game:GetService("Lighting")

local LightingFX = {}
LightingFX.__index = LightingFX

local rgb = Color3.fromRGB

LightingFX.SPACE = {
	ClockTime = 7.1, -- low sun: hard side light, the planet reads as a crescent
	GeographicLatitude = 0,
	Brightness = 3.2,
	Ambient = rgb(0, 0, 0),
	OutdoorAmbient = rgb(6, 7, 14),
	ColorShift_Top = rgb(255, 244, 228),
	ColorShift_Bottom = rgb(0, 0, 0),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0.25,
	ExposureCompensation = 0,
	FogStart = 100000,
	FogEnd = 100000,
	FogColor = rgb(0, 0, 0),
	GlobalShadows = true,
	ShadowSoftness = 0.1,
}

LightingFX.SPACE_EFFECTS = {
	{ "BloomEffect", { Name = "IntroSpaceBloom", Intensity = 1.4, Size = 40, Threshold = 0.85 } },
	{
		"ColorCorrectionEffect",
		{ Name = "IntroSpaceGrade", Brightness = 0, Contrast = 0.12, Saturation = 0.12, TintColor = rgb(236, 240, 255) },
	},
}

LightingFX.WORLD_GRADE = { Name = "IntroWorldGrade", Brightness = 0.01, Contrast = 0.04, Saturation = 0.06, TintColor = rgb(255, 246, 234) }

function LightingFX.new(camera)
	local self = setmetatable({}, LightingFX)
	self.camera = camera or workspace.CurrentCamera
	self.saved = {} -- prop -> original value (only props we changed)
	self.removed = {} -- { instance, parent } taken out of the lighting
	self.disabled = {} -- instances whose Enabled we set false
	self.created = {} -- instances we made
	self.spaceEffects = {}
	self.mode = nil
	self.begun = false
	return self
end

function LightingFX:Begin()
	if self.begun then
		return
	end
	self.begun = true
	self.attribute = Lighting:GetAttribute("CutsceneActive")
	Lighting:SetAttribute("CutsceneActive", true)
end

function LightingFX:Set(prop, value)
	if self.saved[prop] == nil then
		self.saved[prop] = Lighting[prop]
	end
	Lighting[prop] = value
end

function LightingFX:Effect(className, props)
	local e = Instance.new(className)
	for k, v in pairs(props or {}) do
		e[k] = v
	end
	e.Parent = Lighting
	table.insert(self.created, e)
	return e
end

local function destroy(list)
	for _, inst in ipairs(list) do
		pcall(function()
			inst:Destroy()
		end)
	end
	table.clear(list)
end

-- put back properties, parents and enabled flags (keeps the attribute and created world effects)
function LightingFX:_restoreLook()
	for prop, value in pairs(self.saved) do
		pcall(function()
			Lighting[prop] = value
		end)
	end
	table.clear(self.saved)
	for i = #self.removed, 1, -1 do
		local entry = self.removed[i]
		pcall(function()
			entry[1].Parent = entry[2]
		end)
	end
	table.clear(self.removed)
	for _, inst in ipairs(self.disabled) do
		pcall(function()
			inst.Enabled = true
		end)
	end
	table.clear(self.disabled)
	destroy(self.spaceEffects)
end

function LightingFX:Space()
	self:Begin()
	self:_restoreLook()
	self.mode = "space"
	-- Atmosphere and Sky have no Enabled switch: take them out of Lighting for now
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("Sky") then
			table.insert(self.removed, { child, child.Parent })
			child.Parent = nil
		end
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds and clouds.Enabled then
		clouds.Enabled = false
		table.insert(self.disabled, clouds)
	end
	local holders = { Lighting }
	if self.camera then
		table.insert(holders, self.camera)
	end
	for _, holder in ipairs(holders) do
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("PostEffect") and child.Enabled then
				child.Enabled = false
				table.insert(self.disabled, child)
			end
		end
	end
	for prop, value in pairs(LightingFX.SPACE) do
		self:Set(prop, value)
	end
	-- a sky without sun, moon or stars behind the space dome
	local sky = Instance.new("Sky")
	sky.Name = "IntroSpaceSky"
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	sky.Parent = Lighting
	table.insert(self.spaceEffects, sky)
	for _, spec in ipairs(LightingFX.SPACE_EFFECTS) do
		local e = Instance.new(spec[1])
		for k, v in pairs(spec[2]) do
			e[k] = v
		end
		e.Parent = Lighting
		table.insert(self.spaceEffects, e)
	end
end

function LightingFX:World()
	self:Begin()
	self:_restoreLook()
	self.mode = "world"
	if not self.worldGrade then
		self.worldGrade = self:Effect("ColorCorrectionEffect", LightingFX.WORLD_GRADE)
	end
end

function LightingFX:Restore()
	self:_restoreLook()
	destroy(self.created)
	self.worldGrade = nil
	if self.begun then
		self.begun = false
		pcall(function()
			Lighting:SetAttribute("CutsceneActive", self.attribute)
		end)
	end
	self.mode = nil
end

return LightingFX
