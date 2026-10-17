--[[
	IslandAtmosphere (LocalScript, installed into StarterPlayerScripts)
	Gives every region its own sky, light, fog, colour grading and weather,
	blending smoothly as the player walks between them, and shows the region's
	name when they arrive.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Layout = require(ReplicatedStorage:WaitForChild("IslandLayout"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local rgb = Color3.fromRGB

-- Optional ambient loops: paste a sound asset id (e.g. "rbxassetid://123") per region.
local AMBIENT_SOUNDS = {
	Hub = "",
	Forest = "",
	Snow = "",
	Hollow = "",
	Ruins = "",
	Dunes = "",
}

local PROFILES = {
	Hub = {
		lighting = { ClockTime = 13.5, Brightness = 3.2, ExposureCompensation = 0, Ambient = rgb(90, 80, 70), OutdoorAmbient = rgb(150, 135, 115) },
		atmosphere = { Density = 0.28, Offset = 0.2, Color = rgb(235, 215, 180), Decay = rgb(200, 150, 100), Glare = 0.5, Haze = 1.6 },
		grade = { TintColor = rgb(255, 246, 232), Saturation = 0.1, Contrast = 0.08, Brightness = 0.02 },
		bloom = { Intensity = 0.5, Size = 26, Threshold = 1.4 },
		rays = { Intensity = 0.08 },
		clouds = { Cover = 0.45, Density = 0.5, Color = rgb(255, 250, 240) },
		sky = { MoonAngularSize = 11, StarCount = 3000 },
		celestial = true,
		weather = "dust",
	},
	Forest = {
		lighting = { ClockTime = 15.2, Brightness = 2.8, ExposureCompensation = 0, Ambient = rgb(80, 95, 80), OutdoorAmbient = rgb(130, 150, 125) },
		atmosphere = { Density = 0.33, Offset = 0.3, Color = rgb(200, 225, 200), Decay = rgb(110, 140, 100), Glare = 0.3, Haze = 1.2 },
		grade = { TintColor = rgb(246, 255, 240), Saturation = 0.18, Contrast = 0.06, Brightness = 0.02 },
		bloom = { Intensity = 0.6, Size = 28, Threshold = 1.3 },
		rays = { Intensity = 0.12 },
		clouds = { Cover = 0.55, Density = 0.55, Color = rgb(255, 255, 250) },
		sky = { MoonAngularSize = 11, StarCount = 3000 },
		celestial = true,
		weather = "pollen",
	},
	Snow = {
		lighting = { ClockTime = 10.5, Brightness = 2.4, ExposureCompensation = 0, Ambient = rgb(110, 120, 140), OutdoorAmbient = rgb(170, 180, 200) },
		atmosphere = { Density = 0.42, Offset = 0.1, Color = rgb(215, 225, 240), Decay = rgb(170, 185, 210), Glare = 0.1, Haze = 2.4 },
		grade = { TintColor = rgb(232, 242, 255), Saturation = -0.12, Contrast = 0.04, Brightness = 0 },
		bloom = { Intensity = 0.4, Size = 24, Threshold = 1.6 },
		rays = { Intensity = 0.03 },
		clouds = { Cover = 0.85, Density = 0.7, Color = rgb(230, 235, 245) },
		sky = { MoonAngularSize = 11, StarCount = 3000 },
		celestial = true,
		weather = "snow",
	},
	Hollow = {
		lighting = { ClockTime = 0, Brightness = 1.4, ExposureCompensation = 0.35, Ambient = rgb(60, 66, 90), OutdoorAmbient = rgb(125, 135, 175) },
		atmosphere = { Density = 0.3, Offset = 0, Color = rgb(60, 70, 100), Decay = rgb(20, 24, 40), Glare = 0, Haze = 0.8 },
		grade = { TintColor = rgb(210, 220, 255), Saturation = -0.4, Contrast = 0.12, Brightness = 0 },
		bloom = { Intensity = 0.9, Size = 34, Threshold = 1.1 },
		rays = { Intensity = 0 },
		clouds = { Cover = 0, Density = 0.2, Color = rgb(120, 130, 160) },
		sky = { MoonAngularSize = 11, StarCount = 5000 },
		celestial = false,
		weather = "motes",
	},
	Ruins = {
		lighting = { ClockTime = 17.6, Brightness = 1.8, ExposureCompensation = 0, Ambient = rgb(70, 60, 60), OutdoorAmbient = rgb(120, 100, 95) },
		atmosphere = { Density = 0.5, Offset = 0.15, Color = rgb(120, 100, 95), Decay = rgb(70, 50, 45), Glare = 0.2, Haze = 2.8 },
		grade = { TintColor = rgb(255, 225, 210), Saturation = -0.35, Contrast = 0.15, Brightness = -0.02 },
		bloom = { Intensity = 0.5, Size = 24, Threshold = 1.5 },
		rays = { Intensity = 0.05 },
		clouds = { Cover = 0.9, Density = 0.9, Color = rgb(90, 85, 85) },
		sky = { MoonAngularSize = 11, StarCount = 1000 },
		celestial = true,
		weather = "ash",
	},
	Dunes = {
		lighting = { ClockTime = 12.8, Brightness = 3.6, ExposureCompensation = 0, Ambient = rgb(110, 90, 70), OutdoorAmbient = rgb(180, 150, 110) },
		atmosphere = { Density = 0.38, Offset = 0.25, Color = rgb(240, 205, 150), Decay = rgb(210, 140, 80), Glare = 0.8, Haze = 2.2 },
		grade = { TintColor = rgb(255, 236, 210), Saturation = 0.05, Contrast = 0.1, Brightness = 0.02 },
		bloom = { Intensity = 0.5, Size = 26, Threshold = 1.4 },
		rays = { Intensity = 0.1 },
		clouds = { Cover = 0.1, Density = 0.3, Color = rgb(255, 245, 230) },
		sky = { MoonAngularSize = 11, StarCount = 3000 },
		celestial = true,
		weather = "sand",
	},
}

local BLEND = TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

-- Effects (created by the generator; made here if missing) --------------------------------------
local function ensure(className, parent, name)
	local obj = parent:FindFirstChild(name)
	if not obj then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = parent
	end
	return obj
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or ensure("Atmosphere", Lighting, "Atmosphere")
local sky = Lighting:FindFirstChildOfClass("Sky") or ensure("Sky", Lighting, "Sky")
local grade = ensure("ColorCorrectionEffect", Lighting, "IslandGrade")
local bloom = ensure("BloomEffect", Lighting, "IslandBloom")
local rays = ensure("SunRaysEffect", Lighting, "IslandSunRays")
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or ensure("Clouds", workspace.Terrain, "Clouds")

-- Weather ----------------------------------------------------------------------------------------
local weatherPart = Instance.new("Part")
weatherPart.Name = "LocalWeather"
weatherPart.Anchored = true
weatherPart.CanCollide = false
weatherPart.CanQuery = false
weatherPart.CanTouch = false
weatherPart.CastShadow = false
weatherPart.Transparency = 1
weatherPart.Size = Vector3.new(240, 1, 240)
weatherPart.Parent = workspace

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function emitter(props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightInfluence = 0
	e.Shape = Enum.ParticleEmitterShape.Box
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = weatherPart
	return e
end

local WEATHER = {
	snow = {
		emitter({
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			LightInfluence = 0.6,
			Size = NumberSequence.new(0.35),
			Transparency = NumberSequence.new(0.1),
			Lifetime = NumberRange.new(7, 9),
			Rate = 420,
			Speed = NumberRange.new(6, 10),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(20, 20),
			Acceleration = Vector3.new(2, 0, 1),
			RotSpeed = NumberRange.new(-90, 90),
		}),
	},
	ash = {
		emitter({
			Texture = SPARKLE,
			Color = ColorSequence.new(rgb(70, 66, 66), rgb(140, 136, 132)),
			LightInfluence = 1,
			Size = NumberSequence.new(0.3),
			Lifetime = NumberRange.new(8, 12),
			Rate = 160,
			Speed = NumberRange.new(2, 4),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(3, 0, 0),
		}),
		emitter({
			Texture = SPARKLE,
			Color = ColorSequence.new(rgb(255, 140, 50), rgb(255, 60, 20)),
			LightEmission = 1,
			Size = NumberSequence.new(0.2),
			Lifetime = NumberRange.new(6, 9),
			Rate = 12,
			Speed = NumberRange.new(1, 2),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(60, 60),
		}),
	},
	sand = {
		emitter({
			Texture = SMOKE,
			Color = ColorSequence.new(rgb(236, 200, 140)),
			LightInfluence = 1,
			Size = NumberSequence.new(6, 14),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.82),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(4, 6),
			Rate = 40,
			Speed = NumberRange.new(2, 4),
			EmissionDirection = Enum.NormalId.Bottom,
			Acceleration = Vector3.new(26, 0, 8),
			RotSpeed = NumberRange.new(-30, 30),
		}),
	},
	motes = {
		emitter({
			Texture = SPARKLE,
			Color = ColorSequence.new(rgb(210, 230, 255)),
			LightEmission = 1,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, 0.5),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Lifetime = NumberRange.new(6, 9),
			Rate = 60,
			Speed = NumberRange.new(1, 2),
			EmissionDirection = Enum.NormalId.Bottom,
			Acceleration = Vector3.new(0, 1.2, 0),
		}),
	},
	pollen = {
		emitter({
			Texture = SPARKLE,
			Color = ColorSequence.new(rgb(255, 236, 140), rgb(190, 255, 150)),
			LightEmission = 1,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Lifetime = NumberRange.new(5, 8),
			Rate = 45,
			Speed = NumberRange.new(0.5, 1.5),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(180, 180),
		}),
	},
	dust = {
		emitter({
			Texture = SPARKLE,
			Color = ColorSequence.new(rgb(255, 236, 200)),
			LightInfluence = 1,
			Size = NumberSequence.new(0.15),
			Lifetime = NumberRange.new(6, 9),
			Rate = 20,
			Speed = NumberRange.new(0.5, 1),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(180, 180),
		}),
	},
}
local weatherHeight = { snow = 55, ash = 55, sand = 30, motes = -25, pollen = -20, dust = -10 }
local currentWeather = nil

local function setWeather(kind)
	for name, list in pairs(WEATHER) do
		for _, e in ipairs(list) do
			e.Enabled = name == kind
		end
	end
	currentWeather = kind
end

-- Region banner -------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "RegionBanner"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function makeLabel(y, size, font)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, y)
	l.Size = UDim2.new(0.8, 0, 0, size)
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextTransparency = 1
	l.TextStrokeTransparency = 1
	l.Parent = gui
	return l
end
local title = makeLabel(0.17, 54, Enum.Font.Garamond)
local subtitle = makeLabel(0.17 + 0.065, 26, Enum.Font.Garamond)
local bannerToken = 0

local function showBanner(zone)
	local info = Layout.ZoneInfo[zone]
	if not info then
		return
	end
	bannerToken += 1
	local token = bannerToken
	title.Text = string.upper(info.name)
	subtitle.Text = info.subtitle
	local fadeIn = TweenInfo.new(1.2, Enum.EasingStyle.Sine)
	for _, l in ipairs({ title, subtitle }) do
		TweenService:Create(l, fadeIn, { TextTransparency = 0, TextStrokeTransparency = 0.6 }):Play()
	end
	task.delay(4, function()
		if token ~= bannerToken then
			return
		end
		local fadeOut = TweenInfo.new(1.6, Enum.EasingStyle.Sine)
		for _, l in ipairs({ title, subtitle }) do
			TweenService:Create(l, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

-- Ambient sound -----------------------------------------------------------------------------------------
local ambient = Instance.new("Sound")
ambient.Name = "RegionAmbience"
ambient.Looped = true
ambient.Volume = 0
ambient.Parent = SoundService

local function setAmbient(zone)
	local id = AMBIENT_SOUNDS[zone]
	TweenService:Create(ambient, TweenInfo.new(1.5), { Volume = 0 }):Play()
	task.delay(1.6, function()
		if id and id ~= "" then
			ambient.SoundId = id
			ambient:Play()
			TweenService:Create(ambient, TweenInfo.new(2), { Volume = 0.5 }):Play()
		else
			ambient:Stop()
		end
	end)
end

-- The Hollow's moon only shows its crescent at night -------------------------------------------------------
local function moonParts()
	local island = workspace:FindFirstChild("Island")
	local hollow = island and island:FindFirstChild("Hollow")
	local moon = hollow and hollow:FindFirstChild("HollowMoon")
	if moon then
		return moon:FindFirstChild("Moon"), moon:FindFirstChild("MoonShadow")
	end
	return nil, nil
end

-- Applying a region ----------------------------------------------------------------------------------------
local function apply(zone, instant)
	local p = PROFILES[zone]
	if not p then
		return
	end
	local info = instant and TweenInfo.new(0) or BLEND
	TweenService:Create(Lighting, info, p.lighting):Play()
	TweenService:Create(atmosphere, info, p.atmosphere):Play()
	TweenService:Create(grade, info, p.grade):Play()
	TweenService:Create(bloom, info, p.bloom):Play()
	TweenService:Create(rays, info, p.rays):Play()
	TweenService:Create(clouds, info, p.clouds):Play()
	TweenService:Create(sky, info, p.sky):Play()
	sky.CelestialBodiesShown = p.celestial
	setWeather(p.weather)
	local moon, shadow = moonParts()
	if moon and shadow then
		local night = zone == "Hollow"
		TweenService:Create(moon, info, { Transparency = night and 0 or 0.55 }):Play()
		TweenService:Create(shadow, info, { Transparency = night and 0 or 1 }):Play()
	end
end

local currentZone = nil
local pending, pendingSince = nil, 0

local function focusPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		return root.Position
	end
	return camera.Focus.Position
end

local function update()
	local pos = focusPosition()
	local zone = Layout.getZone(pos.X, pos.Z)
	if zone == "Coast" then
		zone = currentZone or "Forest" -- out at sea, keep the last region's mood
	end
	if zone ~= currentZone then
		-- require the player to stay in the new region briefly, so borders don't flicker
		if pending ~= zone then
			pending, pendingSince = zone, os.clock()
		elseif os.clock() - pendingSince > 0.6 or currentZone == nil then
			local first = currentZone == nil
			currentZone = zone
			pending = nil
			apply(zone, first)
			showBanner(zone)
			setAmbient(zone)
		end
	else
		pending = nil
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(update)
		if not ok then
			warn("[IslandAtmosphere]", err)
		end
		task.wait(0.3)
	end
end)

-- keep the weather volume above the camera
game:GetService("RunService").RenderStepped:Connect(function()
	local cf = camera.CFrame
	local offset = currentWeather and weatherHeight[currentWeather] or 50
	weatherPart.CFrame = CFrame.new(cf.Position + Vector3.new(0, offset, 0))
end)
