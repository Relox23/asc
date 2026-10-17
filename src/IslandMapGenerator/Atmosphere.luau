--[[
	Atmosphere
	Sets up Lighting (Future lighting, sky, atmosphere, bloom, colour grading,
	sun rays, clouds) and installs the client script that changes the mood
	region by region.
]]

local Util = require(script.Parent.Util)

local Atmosphere = {}

local rgb = Color3.fromRGB

local function replace(parent, className, name)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	return obj
end

function Atmosphere.Build()
	Util.log("Setting up lighting and atmosphere...")
	local Lighting = game:GetService("Lighting")

	-- remove default effects so ours are the only ones
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("SunRaysEffect") or child:IsA("ColorCorrectionEffect") then
			child:Destroy()
		end
	end

	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	Lighting.GlobalShadows = true
	Lighting.Brightness = 2.8
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 28
	Lighting.Ambient = rgb(80, 95, 80)
	Lighting.OutdoorAmbient = rgb(130, 150, 125)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ShadowSoftness = 0.25
	Lighting.ExposureCompensation = 0

	local sky = replace(Lighting, "Sky", "Sky")
	sky.CelestialBodiesShown = true
	sky.StarCount = 3000
	sky.MoonAngularSize = 11
	sky.SunAngularSize = 14

	local atmosphere = replace(Lighting, "Atmosphere", "Atmosphere")
	atmosphere.Density = 0.33
	atmosphere.Offset = 0.3
	atmosphere.Color = rgb(200, 225, 200)
	atmosphere.Decay = rgb(110, 140, 100)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2

	local grade = replace(Lighting, "ColorCorrectionEffect", "IslandGrade")
	grade.TintColor = rgb(246, 255, 240)
	grade.Saturation = 0.18
	grade.Contrast = 0.06
	grade.Brightness = 0.02

	local bloom = replace(Lighting, "BloomEffect", "IslandBloom")
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.3

	local rays = replace(Lighting, "SunRaysEffect", "IslandSunRays")
	rays.Intensity = 0.12
	rays.Spread = 0.8

	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or replace(workspace.Terrain, "Clouds", "Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.55
	clouds.Color = rgb(255, 255, 250)

	-- shared layout for the client
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local oldLayout = ReplicatedStorage:FindFirstChild("IslandLayout")
	if oldLayout then
		oldLayout:Destroy()
	end
	script.Parent.IslandLayout:Clone().Parent = ReplicatedStorage

	-- client mood script
	local starterScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if starterScripts then
		local old = starterScripts:FindFirstChild("IslandAtmosphere")
		if old then
			old:Destroy()
		end
		script.Parent.Client.IslandAtmosphere:Clone().Parent = starterScripts
	else
		warn("[IslandMap] StarterPlayerScripts not found; the region atmosphere script was not installed")
	end
end

return Atmosphere
