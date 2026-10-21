--[[
	Screen
	Everything 2D of the intro (DESIGN §7.2, §7.4): one ScreenGui (IgnoreGuiInset,
	DisplayOrder 100) with, bottom to top: impact frames (ViewportFrame with
	silhouettes + radial lines), speed lines, colour flash, cinematic bars
	(2.39:1 letterbox), black fade, skip hint.

	All animation is a function of cutscene time t (no tweens): a marker starts an
	effect at its own time, Update(t) draws the state at t. So a long frame or a
	jump in t shows exactly what should be on screen at t.

	    local screen = Screen.new(player, camera, config)
	    screen:Bars(show, seconds, t0)          slide the bars in (true) / out (false)
	    screen:Fade(toBlack, seconds, t0)       fade to black (true) / from black (false)
	    screen:Flash(color, seconds, t0)        full-screen flash fading out over seconds
	    screen:Shake(magnitude, seconds, t0)    camera shake (studs of jitter), decays
	    screen:ShakeOffset(t) -> CFrame         camera-local offset; camera.CFrame = cf * offset
	    screen:SpeedLines(on, t0)               screen-space speed lines
	    screen:Impact(mode, t0)                 "white" | "black" | "off" (§7.4)
	    screen:AddSilhouette(name, source, poseFn?)   clones the visible parts of source (Model or
	                                            part) into the impact ViewportFrame; while impact
	                                            frames show they follow poseFn(sourcePart) -> CFrame
	                                            (default sourcePart.CFrame)
	    screen:RemoveSilhouette(name)
	    screen:SetSkipHint(visible)
	    screen:Update(t, dt)                    draw (call after the camera and the models are set)
	    screen:Destroy()                        removes the gui, shows the hidden game GUI again
]]

local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Screen = {}
Screen.__index = Screen

local BAR_RATIO = 2.39
local SPEED_LINES = 36
local IMPACT_LINES = 32
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2
local HIDDEN_CORE = { "Backpack", "PlayerList", "Health", "EmotesMenu" }

local Z_IMPACT, Z_IMPACT_LINES, Z_SPEED, Z_FLASH, Z_BARS, Z_FADE, Z_HINT = 1, 2, 3, 4, 5, 6, 7

local function clamp01(x)
	return x < 0 and 0 or (x > 1 and 1 or x)
end

local function smooth(x)
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

-- deterministic pseudo random 0..1
local function hash(i, s)
	local x = math.sin(i * 12.9898 + s * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function frame(parent, name, z, color)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or BLACK
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function taperedLine(parent, z)
	local f = frame(parent, "Line", z, WHITE)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundTransparency = 0
	f.Visible = false
	local g = Instance.new("UIGradient")
	-- left end (inner, towards the screen centre) invisible, right end (outer) solid
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.55, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	g.Parent = f
	return f
end

-- A value easing from `from` to `to` over [t0, t0 + dur].
local function ramp(state, t)
	if state.dur <= 0 then
		return t >= state.t0 and state.to or state.from
	end
	return state.from + (state.to - state.from) * smooth((t - state.t0) / state.dur)
end

function Screen.new(player, camera, config)
	local self = setmetatable({}, Screen)
	self.player = player
	self.camera = camera
	self.config = config or {}
	self.t = 0
	self.bars = { from = 0, to = 0, t0 = 0, dur = 0 }
	self.fade = { from = 0, to = 0, t0 = 0, dur = 0 }
	self.flash = { color = WHITE, t0 = -1, dur = 0 }
	self.shakes = {}
	self.speed = { on = false, t0 = -100 }
	self.impactMode = "off"
	self.silhouettes = {}
	self.hiddenGuis = {}
	self.hiddenCore = {}

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroCutsceneScreen"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.gui = gui

	-- impact frames
	local vf = Instance.new("ViewportFrame")
	vf.Name = "ImpactFrame"
	vf.BorderSizePixel = 0
	vf.Size = UDim2.fromScale(1, 1)
	vf.BackgroundColor3 = WHITE
	vf.BackgroundTransparency = 0
	vf.ZIndex = Z_IMPACT
	vf.Visible = false
	vf.LightDirection = Vector3.new(-0.3, -1, -0.4)
	vf.Parent = gui
	local vcam = Instance.new("Camera")
	vcam.Name = "ImpactCamera"
	vcam.Parent = vf
	vf.CurrentCamera = vcam
	self.impactFrame = vf
	self.impactCamera = vcam
	self.impactLinesFrame = frame(gui, "ImpactLines", Z_IMPACT_LINES)
	self.impactLinesFrame.Visible = false
	self.impactLines = {}
	for i = 1, IMPACT_LINES do
		self.impactLines[i] = taperedLine(self.impactLinesFrame, Z_IMPACT_LINES)
	end

	-- speed lines
	self.speedFrame = frame(gui, "SpeedLines", Z_SPEED)
	self.speedFrame.Visible = false
	self.speedLines = {}
	for i = 1, SPEED_LINES do
		self.speedLines[i] = taperedLine(self.speedFrame, Z_SPEED)
	end

	self.flashFrame = frame(gui, "Flash", Z_FLASH, WHITE)
	self.flashFrame.Visible = false

	self.barTop = frame(gui, "BarTop", Z_BARS)
	self.barTop.BackgroundTransparency = 0
	self.barTop.Visible = false
	self.barBottom = frame(gui, "BarBottom", Z_BARS)
	self.barBottom.BackgroundTransparency = 0
	self.barBottom.AnchorPoint = Vector2.new(0, 1)
	self.barBottom.Visible = false

	self.fadeFrame = frame(gui, "Fade", Z_FADE)
	self.fadeFrame.Visible = false

	local hint = Instance.new("TextLabel")
	hint.Name = "SkipHint"
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.new(1, -24, 1, -18)
	hint.Size = UDim2.fromOffset(260, 24)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 16
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextColor3 = WHITE
	hint.TextTransparency = 0.35
	hint.TextStrokeTransparency = 0.8
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	hint.Text = touchOnly and "Tap to skip" or "Press Space to skip"
	hint.ZIndex = Z_HINT
	hint.Visible = false
	hint.Parent = gui
	self.hint = hint

	if self.config.HIDE_GUI ~= false and playerGui then
		self:_hideGameGui(playerGui)
	end
	gui.Parent = playerGui
	return self
end

function Screen:_hideGameGui(playerGui)
	for _, g in ipairs(playerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= self.gui and g.Enabled then
			g.Enabled = false
			table.insert(self.hiddenGuis, g)
		end
	end
	for _, name in ipairs(HIDDEN_CORE) do
		local item = Enum.CoreGuiType[name]
		local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, item)
		if ok and enabled then
			if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, item, false) then
				table.insert(self.hiddenCore, item)
			end
		end
	end
end

-- Markers ------------------------------------------------------------------------------------------------
function Screen:Bars(show, seconds, t0)
	local b = self.bars
	b.from = ramp(b, t0)
	b.to = show and 1 or 0
	b.t0 = t0
	b.dur = seconds or 1
end

function Screen:Fade(toBlack, seconds, t0)
	local f = self.fade
	f.from = ramp(f, t0)
	f.to = toBlack and 1 or 0
	if not toBlack and f.from < 1e-3 then
		f.from = 1 -- "from black" starts black even when nothing faded in before
	end
	f.t0 = t0
	f.dur = seconds or 1
end

function Screen:Flash(color, seconds, t0)
	self.flash.color = color or WHITE
	self.flash.t0 = t0
	self.flash.dur = math.max(seconds or 0.3, 1 / 60)
end

function Screen:Shake(magnitude, seconds, t0)
	table.insert(self.shakes, { mag = magnitude or 0.5, dur = math.max(seconds or 0.5, 1e-3), t0 = t0, seed = #self.shakes * 7.31 + t0 })
end

function Screen:ShakeOffset(t)
	local x, y, roll = 0, 0, 0
	local shakes = self.shakes
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local p = (t - s.t0) / s.dur
		if p >= 1 then
			table.remove(shakes, i)
		elseif p >= 0 then
			local k = s.mag * (1 - p) * (1 - p)
			local tt = (t - s.t0) * 17
			x += math.noise(tt, s.seed, 0.5) * 2 * k
			y += math.noise(s.seed, tt, 1.5) * 2 * k
			roll += math.noise(tt, 2.5, s.seed) * k * 0.02
		end
	end
	if x == 0 and y == 0 and roll == 0 then
		return CFrame.identity
	end
	return CFrame.new(x, y, 0) * CFrame.Angles(0, 0, roll)
end

function Screen:SpeedLines(on, t0)
	if on == self.speed.on then
		return
	end
	-- keep the level continuous when toggled mid-ramp
	local level = self:_speedLevel(t0)
	self.speed.on = on
	if on then
		self.speed.t0 = t0 - level * 0.25
	else
		self.speed.t0 = t0 - (1 - level) * 0.35
	end
end

function Screen:_speedLevel(t)
	local s = self.speed
	if s.on then
		return clamp01((t - s.t0) / 0.25)
	end
	return 1 - clamp01((t - s.t0) / 0.35)
end

function Screen:Impact(mode, _t0)
	if mode ~= "white" and mode ~= "black" then
		mode = "off"
	end
	self.impactMode = mode
	local vf = self.impactFrame
	if mode == "off" then
		vf.Visible = false
		self.impactLinesFrame.Visible = false
		return
	end
	local white = mode == "white"
	vf.BackgroundColor3 = white and WHITE or BLACK
	vf.Ambient = white and BLACK or WHITE
	vf.LightColor = white and BLACK or WHITE
	vf.ImageColor3 = white and BLACK or WHITE
	local lineColor = white and BLACK or WHITE
	for _, line in ipairs(self.impactLines) do
		line.BackgroundColor3 = lineColor
	end
	vf.Visible = true
	self.impactLinesFrame.Visible = true
end

-- Silhouettes ------------------------------------------------------------------------------------------
local function silhouetteClone(part)
	local archivable = part.Archivable
	part.Archivable = true
	local c = part:Clone()
	part.Archivable = archivable
	if not c then
		return nil
	end
	for _, child in ipairs(c:GetChildren()) do
		if child:IsA("DataModelMesh") then
			if child:IsA("SpecialMesh") then
				child.TextureId = ""
			end
		else
			child:Destroy()
		end
	end
	if c:IsA("MeshPart") then
		pcall(function()
			c.TextureID = ""
		end)
	end
	c.Anchored = true
	c.CanCollide = false
	c.CanTouch = false
	c.CanQuery = false
	c.CastShadow = false
	c.Material = Enum.Material.SmoothPlastic
	c.Color = WHITE
	c.Transparency = 0
	c.Reflectance = 0
	c.LocalTransparencyModifier = 0
	return c
end

function Screen:AddSilhouette(name, source, poseFn)
	self:RemoveSilhouette(name)
	local parts = {}
	if source:IsA("BasePart") then
		table.insert(parts, source)
	end
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local modelArchivable
	if source:IsA("Model") then
		modelArchivable = source.Archivable
		source.Archivable = true
	end
	local pairsList = {}
	for _, p in ipairs(parts) do
		if p.Transparency < 0.99 and p.Name ~= "HumanoidRootPart" then
			local c = silhouetteClone(p)
			if c then
				c.Parent = self.impactFrame
				table.insert(pairsList, { p, c })
			end
		end
	end
	if modelArchivable ~= nil then
		source.Archivable = modelArchivable
	end
	self.silhouettes[name] = { list = pairsList, pose = poseFn }
end

function Screen:RemoveSilhouette(name)
	local s = self.silhouettes[name]
	if s then
		for _, pair in ipairs(s.list) do
			pair[2]:Destroy()
		end
		self.silhouettes[name] = nil
	end
end

function Screen:SetSkipHint(visible)
	self.hint.Visible = visible and true or false
end

-- Drawing ----------------------------------------------------------------------------------------------
function Screen:_size()
	local s = self.gui.AbsoluteSize
	if s.X < 1 or s.Y < 1 then
		s = self.camera and self.camera.ViewportSize or Vector2.new(1280, 720)
	end
	return s.X, s.Y
end

function Screen:_drawSpeedLines(t, w, h)
	local level = self:_speedLevel(t)
	if level <= 0 then
		self.speedFrame.Visible = false
		return
	end
	self.speedFrame.Visible = true
	local R = 0.5 * math.sqrt(w * w + h * h)
	for i, line in ipairs(self.speedLines) do
		local a = (i - 1 + hash(i, 1) * 0.8) / SPEED_LINES * TAU
		local speed = 1.4 + hash(i, 2) * 1.6
		local phase = (t * speed + hash(i, 3)) % 1
		local rOut = R * (1.12 - 0.6 * phase)
		local len = R * (0.16 + 0.26 * hash(i, 4))
		local mid = rOut - len / 2
		local alpha = level * math.sin(math.pi * phase) * 0.75
		line.Visible = alpha > 0.02
		line.Position = UDim2.new(0.5, math.cos(a) * mid, 0.5, math.sin(a) * mid)
		line.Size = UDim2.fromOffset(len, 1.5 + 2 * hash(i, 5))
		line.Rotation = math.deg(a)
		line.BackgroundTransparency = 1 - alpha
	end
end

function Screen:_drawImpact(t, w, h)
	local camera = self.camera
	if camera then
		self.impactCamera.CFrame = camera.CFrame
		self.impactCamera.FieldOfView = camera.FieldOfView
	end
	for _, s in pairs(self.silhouettes) do
		local pose = s.pose
		for _, pair in ipairs(s.list) do
			local src, c = pair[1], pair[2]
			local cf = pose and pose(src) or src.CFrame
			c.CFrame = cf
		end
	end
	-- radial lines, re-randomised every frame (deterministic per 1/60 s)
	local R = 0.5 * math.sqrt(w * w + h * h)
	local seed = math.floor(t * 60)
	for i, line in ipairs(self.impactLines) do
		local a = hash(i, seed) * TAU
		local len = R * (0.3 + 0.45 * hash(i, seed + 0.5))
		local mid = R * 1.05 - len / 2
		line.Visible = true
		line.Position = UDim2.new(0.5, math.cos(a) * mid, 0.5, math.sin(a) * mid)
		line.Size = UDim2.fromOffset(len, 2 + 7 * hash(i, seed + 0.25) ^ 2)
		line.Rotation = math.deg(a)
	end
end

function Screen:Update(t, _dt)
	self.t = t
	local w, h = self:_size()

	-- bars
	local b = ramp(self.bars, t)
	local barH = math.max(0, (h - w / BAR_RATIO) / 2)
	local showBars = b > 1e-3 and barH > 0.5
	self.barTop.Visible = showBars
	self.barBottom.Visible = showBars
	if showBars then
		local size = UDim2.new(1, 0, 0, math.ceil(barH) + 1)
		self.barTop.Size = size
		self.barBottom.Size = size
		self.barTop.Position = UDim2.fromOffset(0, -(barH + 1) * (1 - b))
		self.barBottom.Position = UDim2.new(0, 0, 1, (barH + 1) * (1 - b))
	end

	-- black fade
	local f = ramp(self.fade, t)
	self.fadeFrame.Visible = f > 1e-3
	self.fadeFrame.BackgroundTransparency = 1 - f

	-- flash
	local fl = self.flash
	local p = (t - fl.t0) / fl.dur
	if fl.dur > 0 and p >= 0 and p < 1 then
		self.flashFrame.Visible = true
		self.flashFrame.BackgroundColor3 = fl.color
		self.flashFrame.BackgroundTransparency = 1 - (1 - p) * (1 - p)
	else
		self.flashFrame.Visible = false
	end

	self:_drawSpeedLines(t, w, h)
	if self.impactMode ~= "off" then
		self:_drawImpact(t, w, h)
	end
end

function Screen:Destroy()
	for name in pairs(self.silhouettes) do
		self:RemoveSilhouette(name)
	end
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
	for _, g in ipairs(self.hiddenGuis) do
		pcall(function()
			if g.Parent then
				g.Enabled = true
			end
		end)
	end
	table.clear(self.hiddenGuis)
	for _, item in ipairs(self.hiddenCore) do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, item, true)
	end
	table.clear(self.hiddenCore)
end

return Screen
